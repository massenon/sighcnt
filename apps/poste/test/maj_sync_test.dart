import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/plages_codes.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LOT MAJ contre la VRAIE mère Dart et DEUX fileuls : la mère est mise à jour d'abord ; un fileul de format trop ancien reçoit 426 `schema_incompatible`, n'envoie rien et
/// garde ses saisies ; une fois mis à jour il se resynchronise sans doublon et la mère ne change que de ce qu'il apporte.
const port = 9890;
const admin = 'secret-maj';

Future<List<Map<String, Object?>>> operations(Mere m) async => [for (final r in await m.base.select('SELECT seq,id,appareil,collection,fiche,type,champs FROM operations ORDER BY seq')) {...r}];

Future<void> tours(MoteurFileul f, int n) async {
  for (var i = 0; i < n; i++) {
    await f.cycle();
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

void main() {
  group('import sur un fileul', mainImport);
  group('426', mainFormat);
}

void mainFormat() {
  late Mere mere;
  late ClientMere console;
  late Directory tmp;

  Future<MoteurFileul> fileul(String nom, {required int format}) async {
    final f = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$port', nom: nom);
    f.poserFormatDonnees(format);
    final code = await console.codeAppareil(nom).timeout(const Duration(seconds: 20));
    await f.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
    return f;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('maj-sync-');
    mere = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: admin, dossierSauvegardes: '${tmp.path}/sauv', formatDonnees: 2));
    await mere.demarrer();
    console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: admin);
  });
  tearDown(() async {
    await mere.arreter();
    await tmp.delete(recursive: true);
  });

  test('fileul trop ancien : 426 nommé, rien n’arrive à la mère, ses saisies hors ligne sont GARDÉES ; mis à jour, il se resynchronise sans doublon', () async {
    final a = await fileul('A', format: 2);
    final b = await fileul('B', format: 0);
    final ecritA = a.ecrire('patients', 'pa1', existe: false, champs: {'nom': 'Awa'});
    final ecritB = b.ecrire('patients', 'pb1', existe: false, champs: {'nom': 'Saisi hors ligne par B'});
    expect(ecritA['refus'], isNull);
    expect(ecritB['refus'], isNull);
    await tours(a, 3);
    await tours(b, 3);
    final ops = await operations(mere);
    expect([for (final o in ops) o['fiche']], ['pa1'], reason: 'seule la saisie du fileul à jour est arrivée');
    expect(b.refusFormat, isNotNull);
    expect(b.refusFormat!['code'], CodeMaj.protocole426);
    expect(b.refusFormat!['code_maj'], CodeMaj.ecartDeVersion);
    expect('${b.refusFormat!['geste']}', contains('Mettre à jour'));
    expect(b.enAttente, 1, reason: 'la saisie de B est toujours dans sa file');
    // la mère n'a rien reçu d'autre, et B n'a rien tiré non plus
    expect([for (final p in await b.liste('patients')) p.id], ['pb1'], reason: 'B ne voit que sa propre saisie : il n’a rien tiré de la mère non plus');
    final avant = jsonEncode(await operations(mere));

    // B est mis à jour (format 1 = une version d'écart, tolérée par défaut) : il se resynchronise
    b.poserFormatDonnees(1);
    await tours(b, 4);
    await tours(a, 3);
    expect(b.refusFormat, isNull);
    final apres = await operations(mere);
    expect([for (final o in apres) o['fiche']], ['pa1', 'pb1'], reason: 'la saisie hors ligne est arrivée une seule fois');
    expect(jsonEncode(apres.sublist(0, 1)), jsonEncode(jsonDecode(avant)), reason: 'ce que la mère avait reçu n’a pas bougé');
    expect([for (final p in await b.liste('patients')) p.id]..sort(), ['pa1', 'pb1']);
    expect([for (final p in await a.liste('patients')) p.id]..sort(), ['pa1', 'pb1']);
    await tours(b, 3);
    expect((await operations(mere)).length, 2, reason: 'aucun doublon après d’autres tours');
  });

  test('la mère non mise à jour refuse un fileul PLUS RÉCENT (la mère d’abord) ; l’écart toléré est un réglage en base', () async {
    final futur = await fileul('F', format: 4);
    futur.ecrire('patients', 'pf1', existe: false, champs: {'nom': 'x'});
    await tours(futur, 3);
    expect(futur.refusFormat!['geste'], contains('la mère d’abord'));
    expect(await operations(mere), isEmpty);
    await mere.base.poserMeta('maj_ecart_tolere', 2);
    await tours(futur, 4);
    expect((await operations(mere)).map((o) => o['fiche']), ['pf1'], reason: 'écart 2 sous une tolérance réglée à 2 : accepté, sa saisie en file est arrivée');
  });
}

/// Un FILEUL qui IMPORTE une base plus ancienne que sa dernière synchronisation (export portable d'avant, réinstallation) : le magasin est remplacé après les contrôles, le journal de la
/// mère est rejoué (idempotent), le fileul retrouve tout, AUCUN doublon, et la mère n'a pas changé d'un octet (ses opérations sont les mêmes, dans le même ordre).
void mainImport() {
  const portI = 9891;
  const adminI = 'secret-maj-import';
  final cle = List<int>.generate(32, (i) => (i * 3 + 9) & 0xff);

  Magasin poste() => Magasin({'patients': <Map<String, Object?>>[]});
  TransportFileul tf(MoteurFileul mo) => TransportFileul(lire: mo.liste, ecrireFiche: (c, f, {required existe, required champs}) => mo.ecrire(c, f, existe: existe, champs: champs));

  test('import sur un fileul rattaché : resynchronisation sans doublon, la mère intacte', () async {
    final tmp = await Directory.systemTemp.createTemp('maj-imp-');
    final mere = await Mere.creer(ConfigMere(port: portI, dbChemin: ':memory:', admin: adminI, dossierSauvegardes: '${tmp.path}/sauv'));
    await mere.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$portI'), secretAdmin: adminI);
    final moteurA = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$portI', nom: 'A');
    final moteurB = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$portI', nom: 'B');
    final mm = poste(), mb = poste();
    var ma = poste();
    final dirA = '${tmp.path}/A/donnees';
    await ma.brancherPersistance(PersistanceFichiers(dirA, cle: cle), delai: Duration.zero);
    final pm = PontActivite(mm, TransportMereLocale(port: portI, admin: adminI), etiquette: 'M');
    var pa = PontActivite(ma, tf(moteurA), etiquette: 'A');
    final pb = PontActivite(mb, tf(moteurB), etiquette: 'B');
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 40));
      while (!fini()) {
        for (final p in [pa, pb, pm]) {
          await p.cycle();
        }
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence ${[mm, ma, mb].map((m) => m.collection('patients').toutes.length)} ${pa.erreur.value} ${pb.erreur.value} ${pm.erreur.value}');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      for (var i = 0; i < 3; i++) {
        for (final p in [pa, pb, pm]) {
          await p.cycle();
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    final auj = DateTime(2026, 11, 17, 9);
    Fiche? parNom(Magasin m, String nom) => m.collection('patients').toutes.where((f) => '${f['nom']}'.startsWith(nom)).firstOrNull;
    String nomDe(Magasin m, String debut) => '${parNom(m, debut)?['nom']}';
    void nouveau(Magasin m, String nom) => m.collection('patients').inserer({'code': PlagesCodes.de(m).prochainCode(m.collection('patients').toutes, auj), 'nom': nom}, prefixe: 'PAT');
    try {
      for (final (mo, nom) in [(moteurA, 'A'), (moteurB, 'B')]) {
        await mo.rattacher('http://127.0.0.1:$portI', await console.codeAppareil(nom).timeout(const Duration(seconds: 20))).timeout(const Duration(seconds: 20));
        mo.demarrer();
      }
      PlagesCodes.de(mm).obtenir = TransportMereLocale(port: portI, admin: adminI).plage;
      PlagesCodes.de(ma).obtenir = (t, mi) => moteurA.demanderPlage(taille: t, minimum: mi);
      PlagesCodes.de(mb).obtenir = (t, mi) => moteurB.demanderPlage(taille: t, minimum: mi);
      for (final m in [mm, ma, mb]) {
        await PlagesCodes.de(m).recharger(maintenant: auj);
      }
      nouveau(ma, 'Awa');
      nouveau(mb, 'Koffi');
      await converger(() => [mm, ma, mb].every((m) => m.collection('patients').toutes.length == 2), 'départ');
      await ma.ecrireMaintenant();

      // la copie préalable et l'export portable de A, À CE MOMENT
      final svc = ServiceMiseAJour(dossier: dirA, cle: cle);
      await svc.preparer();
      final export = await svc.exporter('${tmp.path}/export-A.sighexp');
      final avantSync = DateTime.now();

      // la clinique continue : B corrige Koffi et ajoute Esther, A ajoute Tardif
      mb.collection('patients').mettreAJour(parNom(mb, 'Koffi')!['id'], {'nom': 'Koffi corrigé par B'});
      nouveau(mb, 'Esther');
      nouveau(ma, 'Tardif');
      await converger(() => [mm, ma, mb].every((m) => m.collection('patients').toutes.length == 4) && nomDe(mm, 'Koffi') == 'Koffi corrigé par B', 'suite');
      await ma.ecrireMaintenant();
      final operationsAvant = jsonEncode(await operations(mere));
      final miroirMere = jsonEncode(mm.collection('patients').toutes);

      // A importe l'export d'avant (réinstallation) : copie préalable à jour, import, nouveau magasin, rejeu du journal
      pa.arreter();
      await svc.preparer();
      final r = await svc.importer(export, geste: true, fileulRattache: true, derniereSynchro: DateTime.now().add(const Duration(seconds: 1)));
      expect(r.avertissements.single, startsWith('IMPORT_PLUS_ANCIEN_QUE_SYNC'));
      expect([for (final s in r.saisies) s.nature], contains('creee'), reason: 'les saisies de A absentes de la base importée sont listées');
      expect(avantSync.isBefore(DateTime.now()), isTrue);
      ma = poste();
      await ma.brancherPersistance(PersistanceFichiers(dirA, cle: cle), delai: Duration.zero);
      expect(ma.collection('patients').toutes.length, 2, reason: 'la base importée est celle d’avant');
      moteurA.rejouerDepuisLeDebut();
      pa = PontActivite(ma, tf(moteurA), etiquette: 'A');
      await converger(() => ma.collection('patients').toutes.length == 4 && nomDe(ma, 'Koffi') == 'Koffi corrigé par B', 'resynchronisation de A');

      // aucun doublon chez A, la mère n'a pas bougé
      final codes = [for (final f in ma.collection('patients').toutes) f['code']];
      expect(codes.toSet().length, codes.length, reason: 'aucun doublon : $codes');
      expect(nomDe(ma, 'Koffi'), 'Koffi corrigé par B', reason: 'la valeur validée par la mère n’a pas été réécrite par l’ancienne base');
      expect(jsonEncode(await operations(mere)), operationsAvant, reason: 'la mère n’a reçu AUCUNE opération de l’import');
      expect(jsonEncode(mm.collection('patients').toutes), miroirMere);
      expect(mb.collection('patients').toutes.length, 4);
    } finally {
      pa.arreter();
      pb.arreter();
      pm.arreter();
      try {
        await mere.arreter();
      } catch (_) {}
      await tmp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 150)));
}
