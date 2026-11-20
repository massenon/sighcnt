// LA COPIE HORS SITE DE LA MÈRE (lot 5, ADR-0007) : désactivée par défaut, réglage lu de la base (paramètres versionnés), copie du magasin et des fichiers vers le relais de référence et vers un
// dossier distant, planificateur (horaire, de nuit, retards signalés UNE fois), journal technique sans nom de fichier, refus nommés enregistrés et alertés, restauration vers une cible neuve,
// et les routes d'administration (HORS verrou, refus nommés avec leur statut).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:sigh_sync/src/horssite_mere.dart';
import 'package:sigh_sync/src/mere.dart' hide refusDe;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

import 'aide_sauvegarde.dart';

Future<void> regler(Mere m, Map<String, Object?> valeurs, {String date = '2020-01-01', int version = 1}) async {
  for (final e in valeurs.entries) {
    final d = definitionDeParametre(e.key)!;
    final id = '${e.key}@$date@$version';
    await m.ecrire(parCollectionParametres, id, Fiche({
      'cle': e.key, 'famille': 'horssite', 'type': d.type.name, 'valeur': e.value, 'defaut': d.defaut, 'dateEffet': date, 'version': version, 'auteur': 'admin', 'creeLe': '2026-11-14T08:00:00Z', 'mobile': false, 'sensible': false,
    }, {}, false));
  }
}

Future<List<String>> journal(Mere m) async => [for (final r in await m.base.select("SELECT message FROM evenements WHERE source='sauvegarde' ORDER BY id")) '${r['message']}'];

void main() {
  late Mere m;
  late Relais relais;
  late Directory tmp;
  late String dossierFichiers;
  late String dossierSauv;

  setUp(() async {
    relais = await lancerRelais();
    tmp = Directory.systemTemp.createTempSync('sigh-horssite-');
    dossierFichiers = '${tmp.path}/fichiers';
    dossierSauv = '${tmp.path}/sauvegardes';
    m = await Mere.creer(ConfigMere(port: 0, dbChemin: '${tmp.path}/mere.sqlite', relais: relais.base, secretRelais: secret, dossierFichiers: dossierFichiers, dossierSauvegardes: dossierSauv, cleBase64: base64.encode(cleDeTest())));
  });
  tearDown(() async {
    m.horsSite.arreter();
    await relais.arreter();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<List<String>> rangerFichiers() async {
    final shas = <String>[];
    final dossier = '${Directory.current.path}/../../apps/poste/test/fixtures/fichiers';
    for (final (nom, famille) in [('scan.jpg', 'courrier'), ('scan.png', 'courrier'), ('courrier-texte.pdf', 'courrier')]) {
      final r = await m.stockageFichiers!.ranger(File('$dossier/$nom').readAsBytesSync(), famille: famille, zone: 0, deposePar: 'agent1');
      shas.add(r.sha256);
    }
    return shas;
  }

  group('désactivée par défaut', () {
    test('sans réglage : désactivée ; lancer est refusé en nommant ; une passe ne dépose rien', () async {
      expect((await m.horsSite.reglage()).actif, isFalse);
      final e = await refusDe(m.horsSite.lancer('magasin'));
      expect(e.code, 'HORSSITE_DESACTIVEE');
      expect(e.refus.geste, isNotEmpty);
      await m.horsSite.passe();
      expect((await relais.dest.etat())['nb_blocs'], 0);
      final etat = await m.horsSite.etat();
      expect(etat['actif'], false);
    });

    test('activée mais sans destination pour aucun type : refus nommé, rien déposé', () async {
      await regler(m, {shCleActif: true, shCleDestinationMagasin: 'aucune', shCleDestinationFichiers: 'aucune'});
      final e = await refusDe(m.horsSite.lancer('magasin'));
      expect(e.code, 'DESTINATION_ABSENTE');
      expect((await relais.dest.etat())['nb_blocs'], 0);
    });

    test('une version datée du FUTUR n\'est pas encore en vigueur (la règle de versionnement par date)', () async {
      await regler(m, {shCleActif: true}, date: '2099-01-01');
      expect((await m.horsSite.reglage()).actif, isFalse);
      await regler(m, {shCleActif: true}, date: '2020-01-01', version: 2);
      expect((await m.horsSite.reglage()).actif, isTrue);
    });
  });

  group('copie du magasin vers le relais', () {
    test('une copie : le relais reçoit des blocs, la base de la mère est restaurée octet par octet dans une cible neuve, le journal ne porte aucun nom', () async {
      await regler(m, {shCleActif: true, shCleDestinationMagasin: 'relais', shCleTailleBloc: 65536});
      await m.ecrire('patients', 'P1', Fiche({'nom': 'AKPO Hyperglycémie-Secrète'}, {}, false));
      final r = await m.horsSite.lancer('magasin');
      expect(r['ok'], true);
      expect(r['deposes'], greaterThanOrEqualTo(2));
      final e = await relais.dest.etat();
      expect((((e['copies'] as Map)['magasin']) as Map)['completes'], 1);
      // les blocs du relais ne portent ni le nom du patient, ni l'en-tête SQLite
      final tout = BytesBuilder();
      for (final f in Directory('${relais.dir.path}/blocs-relais/blocs').listSync(recursive: true).whereType<File>()) {
        tout.add(f.readAsBytesSync());
      }
      expect(utf8.decode(tout.takeBytes(), allowMalformed: true), isNot(contains('Hyperglycémie')), reason: 'un mot entier du texte (un mot court apparaîtrait par hasard dans du chiffré)');
      final copies = await m.horsSite.copies('magasin');
      final cible = '${tmp.path}/restauration';
      final res = await m.horsSite.restaurer(type: 'magasin', copie: (await relais.dest.copies('magasin')).first['id'] as String, cible: cible);
      expect(res['ok'], true);
      expect(copies.length, 1);
      final bd = sql.sqlite3.open('$cible/magasin');
      addTearDown(bd.close);
      expect(bd.select("SELECT COUNT(*) AS n FROM fiches WHERE collection='patients'").first['n'], 1);
      // le rejeu du même état est la même copie (rien de redéposé)
      final r2 = await m.horsSite.lancer('magasin');
      expect(r2['deposes'] ?? 0, lessThanOrEqualTo(r['deposes'] as int));
      // le journal technique : des codes et des compteurs, JAMAIS un nom de patient ni de fichier
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final texte = (await journal(m)).join('\n');
      expect(texte, contains('Copie hors site magasin'));
      expect(texte, isNot(contains('AKPO')));
      expect(texte, isNot(contains('.sqlite')));
    });

    test('quota du relais dépassé : refus nommé ESPACE_RELAIS_INSUFFISANT, enregistré à l\'état, journalisé et alerté ; rien d\'actuel détruit', () async {
      await regler(m, {shCleActif: true, shCleTailleBloc: 65536});
      await relais.regler('quotaOctets', 1000);
      final e = await refusDe(m.horsSite.lancer('magasin'));
      expect(e.code, 'ESPACE_RELAIS_INSUFFISANT');
      final etat = ((await m.horsSite.etat())['types'] as Map)['magasin'] as Map;
      expect((etat['erreur'] as Map)['code'], 'ESPACE_RELAIS_INSUFFISANT');
      expect((etat['erreur'] as Map)['geste'], isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final alertes = await m.base.select("SELECT message FROM evenements WHERE niveau='alerte' AND source='sauvegarde'");
      expect(alertes.map((r) => '${r['message']}').join(), contains('ESPACE_RELAIS_INSUFFISANT'));
    });

    test('relais injoignable : DESTINATION_INJOIGNABLE à l\'état, la copie reprend quand il revient (rien n\'est compté entre-temps)', () async {
      await regler(m, {shCleActif: true, shCleTailleBloc: 65536});
      await relais.arreter();
      await expectLater(m.horsSite.lancer('magasin'), throwsA(anything));
      final etat = ((await m.horsSite.etat())['types'] as Map)['magasin'] as Map;
      expect((etat['erreur'] as Map)['code'], 'DESTINATION_INJOIGNABLE');
      expect(etat['dernier'], isNull, reason: 'aucune copie réussie : jamais un faux « à jour »');
      relais = await lancerRelais();
    });
  });

  group('copie des fichiers vers un dossier distant', () {
    test('copie incrémentale, restauration dans un stockage neuf avec les usages, journal sans nom de fichier', () async {
      final shas = await rangerFichiers();
      final distant = Directory('${tmp.path}/distant')..createSync();
      await regler(m, {shCleActif: true, shCleDestinationFichiers: 'dossier', shCleDossierFichiers: distant.path, shCleTailleBloc: 65536});
      final r = await m.horsSite.lancer('fichiers');
      expect(r['elements'], 3);
      expect(r['deposes'], greaterThanOrEqualTo(3));
      final r2 = await m.horsSite.lancer('fichiers');
      expect(r2['deposes'], 0, reason: 'rien n\'a changé : aucun bloc redéposé');
      expect(r2['rejeu'], true);
      final cible = '${tmp.path}/restaure';
      final copieId = (await DestinationDossier(distant.path).copies('fichiers')).first['id'] as String;
      final res = await m.horsSite.restaurer(type: 'fichiers', copie: copieId, cible: cible);
      expect(res['elements'], 3);
      final neuf = StockageFichiers('$cible/fichiers', cle: null);
      for (final sha in shas) {
        expect(sha256Octets(await neuf.lire(sha)), sha);
        final meta = await neuf.meta(sha);
        expect(meta!.usages.any((u) => u['famille'] == 'courrier'), isTrue);
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final texte = (await journal(m)).join('\n');
      for (final sha in shas) {
        expect(texte, isNot(contains(sha.substring(0, 12))), reason: 'le journal ne porte jamais l\'empreinte (le nom) d\'un fichier');
      }
      expect(texte, isNot(contains('.jpg')));
      expect(texte, isNot(contains('.pdf')));
    });

    test('un fichier ajouté entre deux copies : seuls ses blocs sont déposés ; un dossier distant démonté : refus nommé, jamais créé', () async {
      await rangerFichiers();
      final distant = Directory('${tmp.path}/distant')..createSync();
      await regler(m, {shCleActif: true, shCleDestinationFichiers: 'dossier', shCleDossierFichiers: distant.path, shCleTailleBloc: 65536});
      await m.horsSite.lancer('fichiers');
      final nouveau = Uint8List.fromList(File('${Directory.current.path}/../../apps/poste/test/fixtures/fichiers/scan.jpg').readAsBytesSync())..[2000] ^= 0x55;
      await m.stockageFichiers!.ranger(nouveau, famille: 'courrier', zone: 0);
      final r = await m.horsSite.lancer('fichiers');
      expect(r['elements'], 4);
      expect(r['deposes'], lessThanOrEqualTo(4), reason: 'le nouveau fichier (2 blocs) et le manifeste');
      distant.deleteSync(recursive: true);
      final e = await refusDe(m.horsSite.lancer('fichiers'));
      expect(e.code, 'DOSSIER_INTROUVABLE');
      expect(distant.existsSync(), isFalse);
    });

    test('un fichier altéré à la SOURCE n\'est jamais propagé : il est compté, signalé, et la copie des autres continue', () async {
      final shas = await rangerFichiers();
      final chemin = (await m.stockageFichiers!.cheminDe(shas.first))!;
      final o = File(chemin).readAsBytesSync()..[40] ^= 1;
      File(chemin).writeAsBytesSync(o);
      final distant = Directory('${tmp.path}/distant')..createSync();
      await regler(m, {shCleActif: true, shCleDestinationFichiers: 'dossier', shCleDossierFichiers: distant.path, shCleTailleBloc: 65536});
      final r = await m.horsSite.lancer('fichiers');
      expect(r['elements'], 2, reason: 'les deux fichiers sains sont copiés');
      expect(r['illisibles'], 1);
      await Future<void>.delayed(const Duration(milliseconds: 150)); // les événements sont écrits hors verrou, sans attente
      final alertes = [for (final x in await m.base.select("SELECT message FROM evenements WHERE niveau='alerte' AND source='sauvegarde'")) '${x['message']}'];
      expect(alertes.join(), contains('illisible'));
      // le fichier altéré n'est PAS dans la copie : la restauration ne le contient pas
      final copieId = (await DestinationDossier(distant.path).copies('fichiers')).first['id'] as String;
      final res = await m.horsSite.restaurer(type: 'fichiers', copie: copieId, cible: '${tmp.path}/restaure');
      expect(res['elements'], 2);
      final neuf = StockageFichiers('${tmp.path}/restaure/fichiers', cle: null);
      expect(await neuf.existe(shas.first), isFalse);
      expect(await neuf.existe(shas.last), isTrue);
    });
  });

  group('planificateur', () {
    test('fichiers : dus après la fréquence réglée, pas avant ; retard signalé UNE fois ; magasin et contrôle de nuit après l\'heure réglée', () async {
      await rangerFichiers();
      final distant = Directory('${tmp.path}/distant')..createSync();
      await regler(m, {shCleActif: true, shCleDestinationFichiers: 'dossier', shCleDossierFichiers: distant.path, shCleTailleBloc: 65536, shCleHeureControle: 3, shCleFrequence: 60});
      var t = DateTime(2026, 11, 14, 10, 0);
      final h = HorsSiteMere(
          base: m.base, verrou: m.verrou, cle: () => cleDeTest(), relais: relais.base, secretRelais: secret, dossierSauvegardes: dossierSauv, evenement: m.evenementAsync, stockage: m.stockageFichiers, horloge: () => t);
      await h.passe();
      expect(((await h.etat())['types'] as Map)['fichiers']['dernier'], isNotNull, reason: 'jamais faite : due tout de suite');
      expect(((await h.etat())['types'] as Map)['magasin']['dernier'], isNotNull, reason: 'la première copie du magasin se fait dès l\'activation si l\'heure de nuit est passée');
      final magasin1 = ((((await h.etat())['types'] as Map)['magasin'] as Map)['dernier'] as Map)['quand'];
      final avant = ((((await h.etat())['types'] as Map)['fichiers'] as Map)['dernier'] as Map)['quand'];
      t = t.add(const Duration(minutes: 30));
      await h.passe();
      expect(((((await h.etat())['types'] as Map)['fichiers'] as Map)['dernier'] as Map)['quand'], avant, reason: '30 min : pas encore due');
      t = t.add(const Duration(minutes: 35));
      await h.passe();
      expect(((((await h.etat())['types'] as Map)['fichiers'] as Map)['dernier'] as Map)['quand'], isNot(avant), reason: '65 min : due');
      // la nuit : le magasin est copié, le contrôle est fait
      await h.passe();
      expect(((((await h.etat())['types'] as Map)['magasin'] as Map)['dernier'] as Map)['quand'], magasin1, reason: 'une seule copie de magasin par jour');
      t = DateTime(2026, 11, 15, 2, 50);
      await h.passe();
      expect(((((await h.etat())['types'] as Map)['magasin'] as Map)['dernier'] as Map)['quand'], magasin1, reason: 'avant l\'heure de nuit réglée (3 h) : pas de copie');
      t = DateTime(2026, 11, 15, 3, 10);
      await h.passe();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(((((await h.etat())['types'] as Map)['magasin'] as Map)['dernier'] as Map)['quand'], isNot(magasin1), reason: 'le lendemain après 3 h : la copie de nuit');
      expect((await h.etat())['controle'], isNotNull);
      final txt = (await journal(m)).join('\n');
      expect(txt, contains('Contrôle de la copie hors site'));
      // le retard : le dossier disparaît, plus aucune copie ne réussit, l'âge dépasse deux fréquences : UNE alerte
      distant.deleteSync(recursive: true);
      t = t.add(const Duration(hours: 5));
      await h.passe();
      await h.passe();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final retards = [for (final r in await m.base.select("SELECT message FROM evenements WHERE niveau='alerte' AND source='sauvegarde'")) '${r['message']}'].where((x) => x.contains('en retard')).toList();
      expect(retards.length, 1, reason: 'le retard est signalé UNE fois, pas à chaque passe');
      expect(retards.first, contains('fichiers'));
    });

    test('désactivée : la passe ne fait rien, même après des jours', () async {
      var t = DateTime(2026, 11, 14, 10, 0);
      final h = HorsSiteMere(base: m.base, verrou: m.verrou, cle: () => cleDeTest(), relais: relais.base, secretRelais: secret, dossierSauvegardes: dossierSauv, evenement: m.evenementAsync, horloge: () => t);
      await h.passe();
      t = t.add(const Duration(days: 3));
      await h.passe();
      expect(await journal(m), isEmpty);
      expect((await relais.dest.etat())['nb_blocs'], 0);
    });
  });

  group('routes d\'administration (hors verrou)', () {
    test('les refus sont nommés avec leur statut et leur geste ; sans le secret d\'administration : refusé', () async {
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = sock.port;
      await sock.close();
      await m.arreter();
      m = await Mere.creer(ConfigMere(port: port, dbChemin: '${tmp.path}/mere2.sqlite', relais: relais.base, secretRelais: secret, dossierFichiers: dossierFichiers, dossierSauvegardes: dossierSauv, cleBase64: base64.encode(cleDeTest())));
      await m.demarrer();
      Future<(int, Map<String, Object?>)> appel(String methode, String chemin, {Map<String, Object?>? corps, bool admin = true}) async {
        final c = HttpClient();
        final r = await c.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
        if (admin) r.headers.set('x-admin', 'admin-banc');
        r.headers.contentType = ContentType.json;
        if (corps != null) r.add(utf8.encode(jsonEncode(corps)));
        final rep = await r.close();
        final j = (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
        c.close();
        return (rep.statusCode, j);
      }

      final (s0, j0) = await appel('GET', '/admin/horssite/etat', admin: false);
      expect(s0, isNot(200), reason: '$j0');
      final (s1, j1) = await appel('GET', '/admin/horssite/etat');
      expect(s1, 200);
      expect(j1['actif'], false);
      final (s2, j2) = await appel('POST', '/admin/horssite/lancer', corps: {'type': 'magasin'});
      expect(s2, 409);
      expect(j2['code'], 'HORSSITE_DESACTIVEE');
      expect(j2['geste'], isNotEmpty);
      await regler(m, {shCleActif: true, shCleTailleBloc: 65536});
      final (s3, j3) = await appel('POST', '/admin/horssite/lancer', corps: {'type': 'magasin'});
      expect(s3, 200, reason: '$j3');
      final (s4, j4) = await appel('GET', '/admin/horssite/copies?type=magasin');
      expect(s4, 200);
      expect((j4['copies'] as List).length, 1);
      await relais.regler('quotaOctets', 100);
      await regler(m, {shCleTailleBloc: 131072}, version: 3);
      final (s5, j5) = await appel('POST', '/admin/horssite/lancer', corps: {'type': 'magasin'});
      expect(s5, 507);
      expect(j5['code'], 'ESPACE_RELAIS_INSUFFISANT');
      final (s6, j6) = await appel('POST', '/admin/horssite/restaurer', corps: {'type': 'magasin', 'copie': (j4['copies'] as List).first['id'], 'cible': tmp.path});
      expect(s6, 409);
      expect(j6['code'], 'CIBLE_EXISTE');
    });
  });
}
