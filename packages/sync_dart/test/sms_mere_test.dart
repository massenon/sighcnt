// LES ENVOIS AUTOMATIQUES DE SMS DE LA MÈRE (lot SMS-R, ADR-0008) contre un relais de test qui applique le contrat du relais Laravel (`/sms/*` : identifiant opaque exigé, idempotence, retrait d'un
// envoi planifié, un envoi parti ne se retire pas). Ce que le relais REÇOIT est enregistré et fouillé : ni code patient, ni date de naissance, ni rendez-vous, ni médecin, ni motif.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:sigh_sync/src/mere.dart' hide refusDe;
import 'package:test/test.dart';

import 'aide_sauvegarde.dart';

/// Un relais de test : même contrat que `SmsController` (laravel). Il garde tout ce qu'il a reçu, brut.
class RelaisSms {
  RelaisSms._(this.serveur);
  final HttpServer serveur;
  final Map<String, Map<String, Object?>> lignes = {};
  final List<String> recus = [];
  static final _id = RegExp(r'^[0-9a-f]{64}$');

  String get base => 'http://127.0.0.1:${serveur.port}';

  static Future<RelaisSms> lancer() async {
    final r = RelaisSms._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    r.serveur.listen(r._traiter);
    return r;
  }

  Future<void> _traiter(HttpRequest req) async {
    final brut = await utf8.decodeStream(req);
    recus.add('${req.method} ${req.uri.path} $brut');
    Future<void> rendre(int statut, Object corps) async {
      req.response.statusCode = statut;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(corps));
      await req.response.close();
    }

    if (req.headers.value('x-mere') != secret) return rendre(403, {'code': 'mere_requise'});
    final b = brut.isEmpty ? <String, Object?>{} : (jsonDecode(brut) as Map).cast<String, Object?>();
    switch ('${req.method} ${req.uri.path}') {
      case 'POST /sms/deposer':
        final rep = <Map<String, Object?>>[];
        for (final m in (b['messages'] as List).cast<Map>()) {
          final id = '${m['id']}';
          if (!_id.hasMatch(id)) {
            rep.add({'id': id, 'etat': 'refuse', 'code': 'IDENTIFIANT_NON_OPAQUE'});
          } else if (lignes[id] != null && lignes[id]!['etat'] != 'retire') {
            rep.add({'id': id, 'etat': 'existant', 'etatMessage': lignes[id]!['etat']});
          } else {
            lignes[id] = {'etat': 'planifie', 'numero': m['numero'], 'texte': m['texte'], 'type': m['type'], 'heureEnvoi': m['heureEnvoi']};
            rep.add({'id': id, 'etat': 'planifie'});
          }
        }
        return rendre(200, {'messages': rep});
      case 'POST /sms/annuler':
        final rep = <Map<String, Object?>>[];
        for (final id in (b['ids'] as List).cast<String>()) {
          final l = lignes[id];
          if (l == null) {
            rep.add({'id': id, 'etat': 'inconnu'});
          } else if (l['etat'] == 'planifie') {
            l['etat'] = 'retire';
            rep.add({'id': id, 'etat': 'retire'});
          } else {
            rep.add({'id': id, 'etat': l['etat'] == 'retire' ? 'retire' : 'deja_parti'});
          }
        }
        return rendre(200, {'messages': rep});
      case 'GET /sms/etat':
        return rendre(200, {'fournisseur': 'twilio', 'identifiantsDefinis': true, 'configuree': true});
      case 'GET /sms/journal':
        return rendre(200, {'messages': []});
      case 'POST /sms/tester':
        return rendre(200, {'ok': true, 'idFournisseur': 'SM1'});
    }
    return rendre(404, {'code': 'route_inconnue'});
  }

  int planifies() => lignes.values.where((l) => l['etat'] == 'planifie').length;
  Future<void> arreter() => serveur.close(force: true);
}

Future<void> regler(Mere m, Map<String, Object?> valeurs) async {
  for (final e in valeurs.entries) {
    final d = definitionDeParametre(e.key)!;
    await m.ecrire(parCollectionParametres, '${e.key}@2020-01-01@1', Fiche({
      'cle': e.key, 'famille': 'sms', 'type': d.type.name, 'valeur': e.value, 'defaut': d.defaut, 'dateEffet': '2020-01-01', 'version': 1, 'auteur': 'admin', 'creeLe': '2026-11-16T08:00:00Z', 'mobile': false, 'sensible': false,
    }, {}, false));
  }
}

Future<void> fiche(Mere m, String c, String id, Map<String, Object?> data) => m.ecrire(c, id, Fiche(data, {}, false));

void main() {
  late Mere m;
  late RelaisSms relais;
  late Directory tmp;
  late SmsMere sms;
  final maintenant = DateTime(2026, 11, 16, 17, 0);

  SmsMere construire({String? url, Duration delai = const Duration(milliseconds: 40), DateTime? a}) => SmsMere(
      base: m.base, verrou: m.verrou, cle: cleDeTest, relais: url ?? relais.base, secretRelais: secret, evenement: m.evenementAsync, horloge: () => a ?? maintenant, delaiChangement: delai, delaiDemarrage: const Duration(days: 1), intervalle: const Duration(days: 1));

  setUp(() async {
    relais = await RelaisSms.lancer();
    tmp = Directory.systemTemp.createTempSync('sigh-sms-');
    m = await Mere.creer(ConfigMere(port: 0, dbChemin: '${tmp.path}/mere.sqlite', relais: relais.base, secretRelais: secret, dossierSauvegardes: '${tmp.path}/s', cleBase64: base64.encode(cleDeTest())));
    sms = construire();
    await fiche(m, 'patients', 'P1', {'nom': 'DOSSOU', 'prenom': 'Awa', 'telephone': '01 97 00 00 01', 'dateNaissance': '1990-11-17'});
    await fiche(m, 'patients', 'P2', {'nom': 'KOUDJO', 'prenom': 'Paul', 'telephone': '0197000002', 'dateNaissance': '1975-05-05'});
    await fiche(m, 'consultations', 'C1', {'patientId': 'P2', 'date': '2026-11-17T10:30', 'statut': 'planifiee', 'medecin': 'Dr SECRET', 'motif': 'paludisme'});
    await fiche(m, 'employes', 'E1', {'prenom': 'Koffi', 'nom': 'AGBO', 'telephone': '0197000003', 'dateNaissance': '1985-11-17', 'consentementSms': true});
    await fiche(m, 'employes', 'E2', {'prenom': 'Mina', 'nom': 'ZINSOU', 'telephone': '0197000004', 'dateNaissance': '1988-11-17'});
  });
  tearDown(() async {
    sms.arreter();
    m.sms.arreter();
    await m.arreter();
    await relais.arreter();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('désactivés par défaut : rien ne part, et le geste manuel le dit', () async {
    expect((await sms.passe())['actif'], false);
    await expectLater(sms.passe(manuel: true), throwsA(isA<ErreurSms>().having((e) => e.code, 'code', 'SMS_AUTO_DESACTIVES')));
    expect(relais.recus, isEmpty);
  });

  test('actifs : le relais reçoit des messages composés, avec des identifiants opaques, et RIEN d\'autre', () async {
    await regler(m, {smsCleActif: true});
    final r = await sms.passe();
    expect([r['calcules'], r['planifies'], r['existants']], [3, 3, 0]);
    expect(relais.lignes.length, 3);
    expect(relais.planifies(), 3);
    for (final id in relais.lignes.keys) {
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(id), isTrue);
    }
    final depots = relais.recus.where((x) => x.startsWith('POST /sms/deposer')).join('\n');
    for (final interdit in ['P1', 'P2', 'C1', 'E1', 'E2', '1990', '1975', '1985', 'DOSSOU', 'KOUDJO', 'AGBO', 'ZINSOU', 'SECRET', 'paludisme', 'medecin', 'patientId', 'consultation']) {
      expect(depots, isNot(contains(interdit)), reason: 'le relais ne reçoit jamais : $interdit');
    }
    expect(depots, contains('Awa'));
    // E2 (personnel sans accord) : aucun envoi ; un rappel pour P2 le 16 à 18 h, trois types distincts
    expect(relais.lignes.values.map((l) => l['type']).toSet(), {'rappel_rdv', 'anniversaire_patient', 'anniversaire_personnel'});
    expect(relais.lignes.values.any((l) => '${l['texte']}'.contains('Mina')), isFalse);
    final rappel = relais.lignes.values.firstWhere((l) => l['type'] == 'rappel_rdv');
    expect(rappel['heureEnvoi'], DateTime(2026, 11, 16, 18).millisecondsSinceEpoch);
    expect('${rappel['texte']}', contains('17/11/2026 à 10h30'));
  });

  test('idempotent : un second calcul ne double rien', () async {
    await regler(m, {smsCleActif: true});
    await sms.passe();
    final r = await sms.passe();
    expect([r['planifies'], r['existants']], [0, 3]);
    expect(relais.lignes.length, 3);
  });

  test('un rendez-vous annulé, un consentement retiré, un numéro corrigé retirent l\'envoi planifié', () async {
    await regler(m, {smsCleActif: true});
    await sms.passe();
    expect(relais.planifies(), 3);
    await fiche(m, 'consultations', 'C1', {'patientId': 'P2', 'date': '2026-11-17T10:30', 'statut': 'annulee'});
    await fiche(m, 'patients', 'P1', {'nom': 'DOSSOU', 'prenom': 'Awa', 'telephone': '01 97 00 00 01', 'dateNaissance': '1990-11-17', 'consentementSms': false});
    await fiche(m, 'employes', 'E1', {'prenom': 'Koffi', 'nom': 'AGBO', 'telephone': '12', 'dateNaissance': '1985-11-17', 'consentementSms': true});
    final r = await sms.passe();
    expect(r['retires'], 3);
    expect(relais.planifies(), 0);
    expect((r['ecartes'] as Map).keys.toSet(), {'CONSENTEMENT_RETIRE', 'NUMERO_INVALIDE', 'CONSENTEMENT_ABSENT'});
  });

  test('un rendez-vous déplacé : l\'ancien envoi est retiré, le nouveau est déposé', () async {
    await regler(m, {smsCleActif: true});
    await sms.passe();
    await fiche(m, 'consultations', 'C1', {'patientId': 'P2', 'date': '2026-11-18T09:00', 'statut': 'planifiee'});
    final r = await sms.passe();
    expect(r['retires'], 1);
    expect(r['planifies'], 1);
    expect(relais.lignes.values.where((l) => l['type'] == 'rappel_rdv' && l['etat'] == 'planifie').length, 1);
    expect(relais.lignes.values.firstWhere((l) => l['type'] == 'rappel_rdv' && l['etat'] == 'planifie')['heureEnvoi'], DateTime(2026, 11, 17, 18).millisecondsSinceEpoch);
  });

  test('un envoi parti ne se retire pas : le relais le dit, la mère le garde « parti »', () async {
    await regler(m, {smsCleActif: true});
    await sms.passe();
    relais.lignes.values.firstWhere((l) => l['type'] == 'rappel_rdv')['etat'] = 'envoye';
    await fiche(m, 'consultations', 'C1', {'patientId': 'P2', 'date': '2026-11-17T10:30', 'statut': 'annulee'});
    final r = await sms.passe();
    expect(r['dejaPartis'], 1);
    expect(r['retires'], 0);
    expect(relais.lignes.values.where((l) => l['etat'] == 'envoye').length, 1);
    final e = await sms.etat();
    expect((e['planifies'] as List).length, 2, reason: 'l\'envoi parti n\'est plus « planifié »');
    final r2 = await sms.passe();
    expect(r2['dejaPartis'], 0, reason: 'une fois parti, il n\'est plus redemandé');
  });

  group('rappel du matin même (Direction, 16/11/2026)', () {
    final soir = DateTime(2026, 11, 16, 19, 30);
    Iterable<Map<String, Object?>> rappels() => relais.lignes.values.where((l) => l['type'] == 'rappel_rdv');

    test('un rendez-vous vu APRÈS 18 h part le matin du rendez-vous à 7 h, avec le prénom, sans médecin ni motif ; le relais ne reçoit rien de plus', () async {
      await regler(m, {smsCleActif: true});
      final tard = construire(a: soir);
      final r = await tard.passe();
      expect(r['calcules'], 3, reason: 'le rappel du matin, les deux vœux du 17');
      final l = rappels().single;
      expect(l['heureEnvoi'], DateTime(2026, 11, 17, 7).millisecondsSinceEpoch);
      expect('${l['texte']}', contains('Paul'));
      expect('${l['texte']}', contains('10h30'));
      final depots = relais.recus.where((x) => x.startsWith('POST /sms/deposer')).join('\n');
      for (final interdit in ['SECRET', 'paludisme', 'medecin', 'rappel_rdv_matin', 'C1', 'P2', 'patientId']) {
        expect(depots, isNot(contains(interdit)), reason: 'le relais ne reçoit jamais : $interdit (la clé naturelle reste à la mère)');
      }
      tard.arreter();
    });

    test('la veille déjà déposée à 17 h n\'est JAMAIS doublée par le matin, même après 18 h : un seul rappel pour le rendez-vous', () async {
      await regler(m, {smsCleActif: true});
      await sms.passe();
      expect(rappels().length, 1);
      expect(rappels().single['heureEnvoi'], DateTime(2026, 11, 16, 18).millisecondsSinceEpoch);
      final tard = construire(a: DateTime(2026, 11, 16, 19, 0));
      final r = await tard.passe();
      expect(rappels().length, 1, reason: 'toujours un seul rappel au relais');
      expect(r['existants'], greaterThanOrEqualTo(1));
      tard.arreter();
    });

    test('idempotent : un second calcul du soir ne double pas le rappel du matin', () async {
      await regler(m, {smsCleActif: true});
      final tard = construire(a: soir);
      await tard.passe();
      final r = await tard.passe();
      expect(r['planifies'], 0);
      expect(rappels().length, 1);
      tard.arreter();
    });

    test('l\'heure du matin est LUE EN BASE : réglée à 8 h, le rappel part à 8 h ; jamais à l\'heure du rendez-vous ni après', () async {
      await regler(m, {smsCleActif: true, smsCleRappelHeureMatin: 8});
      final tard = construire(a: soir);
      await tard.passe();
      expect(rappels().single['heureEnvoi'], DateTime(2026, 11, 17, 8).millisecondsSinceEpoch);
      await fiche(m, 'consultations', 'C1', {'patientId': 'P2', 'date': '2026-11-17T07:30', 'statut': 'planifiee'});
      final r = await tard.passe();
      expect((r['ecartes'] as Map)['MATIN_APRES_LE_RENDEZ_VOUS'], 1, reason: 'rendez-vous à 7 h 30 : le matin de 8 h serait après lui');
      expect(r['retires'], 1, reason: 'l\'ancien rappel de 8 h est retiré, rien ne part après le rendez-vous');
      expect(relais.planifies(), 2, reason: 'ne restent que les deux vœux');
      tard.arreter();
    });
  });

  test('relais injoignable : refus nommé enregistré, rien d\'inventé', () async {
    await regler(m, {smsCleActif: true});
    final mort = construire(url: 'http://127.0.0.1:1');
    await expectLater(mort.passe(), throwsA(isA<ErreurSms>().having((e) => e.code, 'code', 'RELAIS_INJOIGNABLE')));
    final e = await mort.etat();
    expect((e['erreur'] as Map)['code'], 'RELAIS_INJOIGNABLE');
    expect((e['erreurRelais'] as Map)['code'], 'RELAIS_INJOIGNABLE');
    final sans = construire(url: '');
    await expectLater(sans.passe(), throwsA(isA<ErreurSms>().having((e) => e.code, 'code', 'RELAIS_NON_CONFIGURE')));
    mort.arreter();
    sans.arreter();
  });

  test('l\'état ne rend ni numéro en clair ni texte', () async {
    await regler(m, {smsCleActif: true});
    await sms.passe();
    final brut = jsonEncode(await sms.etat());
    for (final interdit in ['0197000', '97000001', 'Awa', 'rendez-vous', 'DOSSOU']) {
      expect(brut, isNot(contains(interdit)), reason: interdit);
    }
    expect(brut, contains('••••'));
  });

  test('l\'identifiant opaque dépend de la clé de la clinique et de rien d\'autre', () {
    final a = sms.identifiantOpaque('rappel_rdv:C1:2026-11-17');
    expect(a, sms.identifiantOpaque('rappel_rdv:C1:2026-11-17'));
    expect(a, isNot(sms.identifiantOpaque('rappel_rdv:C2:2026-11-17')));
    final autre = SmsMere(base: m.base, verrou: m.verrou, cle: () => List<int>.filled(32, 7), relais: relais.base, secretRelais: secret, evenement: m.evenementAsync);
    expect(autre.identifiantOpaque('rappel_rdv:C1:2026-11-17'), isNot(a), reason: 'sans la clé, l\'identifiant ne se recalcule pas');
    expect(a.length, 64);
  });

  test('un changement de fiche relance le calcul quelques secondes plus tard, regroupé', () async {
    await regler(m, {smsCleActif: true});
    sms.signaler();
    sms.signaler();
    sms.signaler();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(relais.recus.where((x) => x.startsWith('POST /sms/deposer')).length, 1);
    expect(relais.planifies(), 3);
  });

  test('les routes d\'administration passent par le secret de la mère et rendent des refus nommés', () async {
    expect(collectionsSmsSurveillees, containsAll(['consultations', 'patients', 'employes', 'parametres']));
    final t = await sms.tester('+22997000009');
    expect(t['ok'], true);
  });

  test('le geste réservé regler_passerelle_sms est contrôlé par la mère : administrateur et DAF oui, les autres refusés, sans rôle refusé', () {
    m.exigerGesteSms('admin');
    m.exigerGesteSms('da');
    for (final role in ['reception', 'direction', 'infirmier', '', null]) {
      expect(() => m.exigerGesteSms(role), throwsA(isA<Err>().having((e) => e.code, 'code', role == null || role.isEmpty ? 'ROLE_REQUIS' : 'GESTE_RESERVE')), reason: '$role');
    }
  });
}
