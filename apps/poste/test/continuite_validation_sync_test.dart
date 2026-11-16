import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/demandes_validation_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_validation.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LOT CONT : LA DÉCISION D'UN PROFIL SE PREND SUR SON POSTE FILEUL, LA MÈRE N'EST QUE L'APPLICATEUR MÉCANIQUE, contre la VRAIE mère et un VRAI moteur de fileul :
///  - le biologiste d'un fileul SIGNE sa décision (qui, quand) ; elle arrive à la mère par le pont, qui refait les contrôles et applique ; le verdict revient au fileul sur la même fiche ;
///  - le fileul n'est jamais arrêté : il saisit un dossier et dépose une seconde décision pendant que la première attend ;
///  - mère COUPÉE : tout s'empile au journal local, le compte dit « N décisions en attente de la mère » avec l'âge ; à son retour tout se rejoue, UNE seule fois ;
///  - jamais vers un téléphone (RG-13).
typedef M = Map<String, Object?>;
const cleSqlite = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
final donnees = DonneesNavigation.depuisDossier();

Magasin poste() => Magasin({
      'variablesLabo': [
        {'id': 'VL1', 'statut': 'actif', 'libelle': 'Hémoglobine', 'aValider': true},
        {'id': 'VL2', 'statut': 'actif', 'libelle': 'Créatinine', 'aValider': true},
      ],
      'unitesLabo': <M>[],
      'patients': <M>[],
      'audit': const [],
    });

Future<void> _attendre(bool Function() condition, String quoi, {int secondes = 40}) async {
  final fin = DateTime.now().add(Duration(seconds: secondes));
  while (!condition()) {
    if (DateTime.now().isAfter(fin)) fail('délai dépassé : $quoi');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

int lignesValidation(Magasin m, String cible) => m.collection('audit').toutes.where((a) => a['action'] == 'Validation' && '${a['reference']}' == cible).length;

void main() {
  test('BOUT EN BOUT : le biologiste du fileul signe, la mère applique mécaniquement à la date de la signature, le fileul n\'est jamais arrêté, rien vers un mobile', () async {
    const port = 19483;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-cont-1'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Laboratoire');
    final mm = poste(), mf = Magasin({'audit': const [], 'patients': <M>[]});
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(
        mf,
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: 'F');
    final tMere = DateTime.utc(2026, 11, 14, 12);
    final service = ServiceDemandesValidation(mm, donnees: () async => donnees, horloge: () => tMere);
    final signe = DateTime(2026, 11, 14, 8, 30);
    final libelles = DemandesValidationPoste.libellesDesRoles(donnees.matrice);
    final dem = DemandesValidationPoste(mf, libelles: libelles, horloge: () => signe, etiquette: 'F');
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 40));
      while (!fini()) {
        await pub.pousser();
        await appl.tirer();
        await pontF.cycle();
        await pontM.cycle();
        await service.traiter();
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, appl ${appl.erreur.value}, pontF ${pontF.erreur.value}, pontM ${pontM.erreur.value}, service ${service.derniereErreur})');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    try {
      final code = await console.codeAppareil('Laboratoire').timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      await converger(() => mf.collection('variablesLabo').toutes.length == 2, 'la configuration du laboratoire arrive au fileul');
      expect(mf.collection('variablesLabo').parId('VL1')!['aValider'], true);

      // Le geste direct d'un fileul reste refusé (la configuration est tenue par la mère) : la décision passe par le DÉPÔT SIGNÉ.
      final direct = valValiderReferentiel('labo_variables', 'VL1', role: 'laborantin', acteur: 'Dr KINNOU', maintenant: signe, lire: (n) => mf.collection(n).toutes, libelles: libelles, fileul: true);
      expect(direct.refus!.code, valCodeFileul);
      final d1 = dem.deposer('labo_variables', 'VL1', role: 'laborantin', acteur: 'Dr KINNOU', motif: 'bornes relues');
      expect(d1.ok, isTrue, reason: '${d1.refus?.motif}');
      // LE FILEUL N'EST JAMAIS ARRÊTÉ : une seconde décision, un dossier saisi, pendant que la première attend la mère.
      expect(dem.deposer('labo_variables', 'VL2', role: 'laborantin', acteur: 'Dr KINNOU').ok, isTrue);
      mf.collection('patients').inserer({'nom': 'ADJOVI', 'prenom': 'Rose', 'code': 'CNT/1/26'}, prefixe: 'PAT');
      expect(dem.synthese().nombre, 2, reason: 'le compte est le compte RÉEL des décisions qui attendent la mère');
      expect(mf.collection('variablesLabo').parId('VL1')!['aValider'], true, reason: 'rien n\'est validé chez le fileul tant que la mère n\'a pas appliqué : la règle en vigueur reste');
      final redeposer = dem.deposer('labo_variables', 'VL1', role: 'laborantin', acteur: 'Dr KINNOU');
      expect(redeposer.refus!.code, 'DEMANDE_DEJA_DEPOSEE', reason: 'jamais doublée');

      await converger(() => dem.demandes.every((d) => d['etat'] == valEtatAppliquee) && mf.collection('variablesLabo').toutes.every((v) => v['aValider'] == false), 'la mère applique, le verdict et la validation reviennent au fileul');
      final v1 = mm.collection('variablesLabo').parId('VL1')!;
      expect(v1['aValider'], false);
      expect(v1['validePar'], 'Dr KINNOU', reason: 'le NOM de la personne qui a décidé, pas celui de la mère');
      expect(v1['valideLe'], valInstant(signe), reason: 'la date de la SIGNATURE, pas celle de l\'application par la mère');
      expect(v1['motifCorrection'], 'bornes relues');
      expect(dem.demandes.every((d) => d['traitePar'] == 'Mère'), isTrue);
      expect(lignesValidation(mm, 'VL1'), 1, reason: 'une seule ligne de journal à la mère');
      expect(dem.synthese().nombre, 0, reason: 'plus rien n\'attend : le compte retombe à zéro');
      expect(mf.collection('patients').toutes, hasLength(1));

      // Jamais vers un téléphone (RG-13).
      final http0 = HttpClient();
      Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
        final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
        req.headers.contentType = ContentType.json;
        entetes.forEach(req.headers.set);
        if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
        final rep = await req.close();
        return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
      }

      Future<List<String>> recues(String role, Map<String, Object?> extra) async {
        final c = (await appel('POST', '/admin/code', corps: {'etiquette': role, 'role': role, ...extra}, entetes: {'x-admin': 'secret-test'}))['code'];
        final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-$role', 'plateforme': 'test'});
        final noms = <String>[];
        var depuis = 0;
        while (true) {
          final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
          if (pull['ops'] == null) fail('pull de $role à $depuis : $pull');
          final ops = (pull['ops'] as List).cast<Map>();
          for (final o in ops) {
            noms.add('${o['collection']}');
            depuis = (o['seq'] as num).toInt();
          }
          if (pull['fin'] == true || ops.isEmpty) break;
        }
        return noms;
      }

      expect(await recues('fileul', {}), contains(valCollectionDemandes), reason: 'un fileul reçoit les décisions et leur verdict');
      final mobile = await recues('mobile', {'profil': 'soignant', 'fonction': 'infirmier'});
      expect(mobile, isNotEmpty, reason: 'le téléphone lit bien le journal : l\'absence des décisions est une EXCLUSION, pas un journal vide');
      expect(mobile, isNot(contains(valCollectionDemandes)), reason: 'ni qui a décidé, ni le motif, ni le verdict ne partent vers un téléphone');
      http0.close(force: true);
    } finally {
      appl.arreter();
      pontF.arreter();
      pontM.arreter();
      service.arreter();
      await mere0.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 180)));

  test('MÈRE COUPÉE puis relancée : les décisions du fileul s\'empilent au journal local (compte et âge dits), le fileul continue, tout se rejoue UNE fois', () async {
    const port = 19484;
    final d = Directory.systemTemp.createTempSync('cont');
    addTearDown(() => d.deleteSync(recursive: true));
    ConfigMere config() => ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes', cleStockage: cleSqlite);
    var mere = await Mere.creer(config());
    await mere.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: '${d.path}/f.db', mere: 'http://127.0.0.1:$port', nom: 'Laboratoire', cleStockage: cleSqlite);
    final mm = poste(), mf = Magasin({'audit': const [], 'patients': <M>[]});
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(
        mf,
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: 'F');
    final service = ServiceDemandesValidation(mm, donnees: () async => donnees, horloge: () => DateTime.utc(2026, 11, 14, 20));
    var horloge = DateTime(2026, 11, 14, 8, 30);
    final libelles = DemandesValidationPoste.libellesDesRoles(donnees.matrice);
    final dem = DemandesValidationPoste(mf, libelles: libelles, horloge: () => horloge, etiquette: 'F');
    try {
      final code = await console.codeAppareil('Laboratoire');
      await moteur.appairer(code);
      moteur.demarrer();
      final fin0 = DateTime.now().add(const Duration(seconds: 40));
      while (mf.collection('variablesLabo').toutes.length != 2) {
        await pub.pousser();
        await appl.tirer();
        if (DateTime.now().isAfter(fin0)) fail('la configuration n\'arrive pas au fileul');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      // COUPURE : la mère s'arrête. Le fileul décide, saisit, continue.
      await mere.arreter();
      expect(dem.deposer('labo_variables', 'VL1', role: 'laborantin', acteur: 'Dr KINNOU').ok, isTrue, reason: 'décider hors ligne est possible : le dépôt est local');
      horloge = horloge.add(const Duration(hours: 1));
      expect(dem.deposer('labo_variables', 'VL2', role: 'laborantin', acteur: 'Dr KINNOU').ok, isTrue);
      mf.collection('patients').inserer({'nom': 'ADJOVI', 'prenom': 'Rose', 'code': 'CNT/2/26'}, prefixe: 'PAT');
      horloge = horloge.add(const Duration(hours: 2, minutes: 10));
      await pontF.cycle(); // le pont écrit dans la file LOCALE du moteur : il réussit sans la mère
      final s = dem.synthese();
      expect(s.nombre, 2, reason: 'l\'état « en attente de la mère » se dit avec le nombre');
      expect(s.plusAncienne, const Duration(hours: 3, minutes: 10), reason: '…et l\'âge de la plus ancienne');
      expect(s.libelle, '2 décisions en attente de la mère · la plus ancienne depuis 3 h 10 min');
      expect((await moteur.instantane()).enAttente, greaterThan(0), reason: 'les décisions attendent dans la file persistée du moteur : rien n\'est perdu');
      expect(mm.collection('variablesLabo').parId('VL1')!['aValider'], true, reason: 'la mère coupée n\'a encore rien reçu');

      // RETOUR : la mère repart sur SA base ; tout se rejoue dans l'ordre, une fois.
      mere = await Mere.creer(config());
      await mere.demarrer();
      final fin = DateTime.now().add(const Duration(seconds: 60));
      while (!(dem.demandes.length == 2 && dem.demandes.every((x) => x['etat'] == valEtatAppliquee) && mf.collection('variablesLabo').toutes.every((v) => v['aValider'] == false))) {
        await pub.pousser();
        await appl.tirer();
        await pontF.cycle();
        await pontM.cycle();
        await service.traiter();
        if (DateTime.now().isAfter(fin)) fail('pas de convergence au retour : ${[for (final x in dem.demandes) x['etat']]}, mère ${[for (final x in mm.collection(valCollectionDemandes).toutes) x['etat']]}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      for (var i = 0; i < 4; i++) {
        await pontF.cycle();
        await pontM.cycle();
        await service.traiter();
      }
      expect(mm.collection(valCollectionDemandes).toutes, hasLength(2), reason: 'rejouées UNE fois, jamais doublées');
      expect(lignesValidation(mm, 'VL1'), 1);
      expect(lignesValidation(mm, 'VL2'), 1);
      expect(mm.collection('variablesLabo').parId('VL1')!['valideLe'], valInstant(DateTime(2026, 11, 14, 8, 30)), reason: 'chaque décision garde SA date de signature, pas celle du rejeu');
      expect(mm.collection('variablesLabo').parId('VL2')!['valideLe'], valInstant(DateTime(2026, 11, 14, 9, 30)));
      expect(dem.synthese().nombre, 0);
      expect(mf.collection('patients').toutes, hasLength(1));
    } finally {
      appl.arreter();
      pontF.arreter();
      pontM.arreter();
      service.arreter();
      try {
        await mere.arreter();
      } catch (_) {/* déjà arrêtée */}
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('MESURE hors ligne prolongé : 300 décisions signées pendant trois jours de coupure, taille du journal local, délai de rejeu, ce que voit le fileul', () async {
    const port = 19485, n = 300;
    final d = Directory.systemTemp.createTempSync('cont-mesure');
    addTearDown(() => d.deleteSync(recursive: true));
    ConfigMere config() => ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes', cleStockage: cleSqlite);
    var mere = await Mere.creer(config());
    await mere.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: '${d.path}/f.db', mere: 'http://127.0.0.1:$port', nom: 'Laboratoire', cleStockage: cleSqlite);
    final mm = Magasin({
      'variablesLabo': [for (var i = 0; i < n; i++) {'id': 'V$i', 'statut': 'actif', 'libelle': 'Variable $i', 'aValider': true}],
      'audit': const [],
    });
    final mf = Magasin({'audit': const []});
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(mf, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)), etiquette: 'F');
    final service = ServiceDemandesValidation(mm, donnees: () async => donnees, horloge: () => DateTime.utc(2026, 11, 18));
    var horloge = DateTime(2026, 11, 14, 8);
    final dem = DemandesValidationPoste(mf, libelles: DemandesValidationPoste.libellesDesRoles(donnees.matrice), horloge: () => horloge, etiquette: 'F');
    try {
      await moteur.appairer(await console.codeAppareil('Laboratoire'));
      moteur.demarrer();
      final fin0 = DateTime.now().add(const Duration(seconds: 60));
      while (mf.collection('variablesLabo').toutes.length != n) {
        await pub.pousser();
        await appl.tirer();
        if (DateTime.now().isAfter(fin0)) fail('configuration');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await mere.arreter();
      final taille0 = File('${d.path}/f.db').lengthSync();
      for (var i = 0; i < n; i++) {
        expect(dem.deposer('labo_variables', 'V$i', role: 'laborantin', acteur: 'Dr KINNOU').ok, isTrue);
        horloge = horloge.add(const Duration(minutes: 14)); // 300 décisions étalées sur trois jours environ
      }
      await pontF.cycle();
      final attente = (await moteur.instantane()).enAttente;
      final taille1 = File('${d.path}/f.db').lengthSync();
      final s = dem.synthese();
      final octetsParDecision = jsonEncode(dem.demandes.first).length;
      mere = await Mere.creer(config());
      await mere.demarrer();
      final t0 = DateTime.now();
      final fin = DateTime.now().add(const Duration(seconds: 120));
      while (!(dem.demandes.every((x) => x['etat'] == valEtatAppliquee) && mf.collection('variablesLabo').toutes.every((v) => v['aValider'] == false))) {
        await pub.pousser();
        await appl.tirer();
        await pontF.cycle();
        await pontM.cycle();
        await service.traiter();
        if (DateTime.now().isAfter(fin)) fail('rejeu non abouti en 120 s : ${dem.demandes.where((x) => x['etat'] == valEtatAppliquee).length}/$n');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final rejeu = DateTime.now().difference(t0);
      expect(mm.collection(valCollectionDemandes).toutes, hasLength(n), reason: 'aucune décision doublée');
      expect(mm.collection('audit').toutes.where((a) => a['action'] == 'Validation').length, n, reason: 'une ligne de journal par décision');
      // ignore: avoid_print
      print('MESURE CONT : $n décisions hors ligne ; file du moteur en attente $attente ; base locale du fileul ${taille0 ~/ 1024} Kio puis ${taille1 ~/ 1024} Kio ; '
          '$octetsParDecision octets par décision ; pastille « ${s.libelle} » ; rejeu complet (aller, application, retour du verdict et de la configuration) en ${rejeu.inMilliseconds} ms');
    } finally {
      appl.arreter();
      pontF.arreter();
      pontM.arreter();
      service.arreter();
      try {
        await mere.arreter();
      } catch (_) {/* déjà arrêtée */}
    }
  }, timeout: const Timeout(Duration(seconds: 300)));
}
