import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// Les règles de fusion contre la VRAIE mère et deux VRAIS moteurs de fileul : un stock et une facture touchés par deux postes en même temps.
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 11, 3, 9);

/// Les bases SQLite de la mère et des deux fileuls sont CHIFFRÉES : la synchronisation marche à l'identique.
const cleSqlite = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

Magasin poste() => Magasin({
      'produits': [
        {'id': 'PRD1', 'designation': 'Paracétamol', 'stockGros': 10, 'stockDetail': 0, 'stock': 10}
      ],
      'factures': <M>[],
    });

void main() {
  test('BOUT EN BOUT : deux sorties de stock et deux règlements simultanés sur trois postes réels : rien ne se perd', () async {
    const port = 19451;
    final d = Directory.systemTemp.createTempSync('pbe');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-pbe', cleStockage: cleSqlite));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteurA = MoteurFileul.creer(dbChemin: '${d.path}/a.db', mere: 'http://127.0.0.1:1', nom: 'A', cleStockage: cleSqlite);
    final moteurB = MoteurFileul.creer(dbChemin: '${d.path}/b.db', mere: 'http://127.0.0.1:1', nom: 'B', cleStockage: cleSqlite);
    final mm = poste(), ma = poste(), mb = poste();
    TransportFileul tf(MoteurFileul mo) =>
        TransportFileul(lire: mo.liste, ecrireFiche: (c, f, {required existe, required champs}) => mo.ecrire(c, f, existe: existe, champs: champs));
    final pm = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pa = PontActivite(ma, tf(moteurA), etiquette: 'A', enLectureSeule: collectionsDeLaMereSeule);
    final pb = PontActivite(mb, tf(moteurB), etiquette: 'B', enLectureSeule: collectionsDeLaMereSeule);
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 45));
      while (!fini()) {
        for (final p in [pa, pb, pm]) {
          await p.cycle();
        }
        if (DateTime.now().isAfter(fin)) {
          final ia = await moteurA.instantane(), ib = await moteurB.instantane();
          // ignore: avoid_print
          print('DELTAS ${(await TransportMereLocale(port: port, admin: 'secret-test').liste('deltasCompteurs')).map((d) => '${d.id}:${d.data['cle']}:${d.data['delta']}').toList()}');
          // ignore: avoid_print
          print('REFUS A ${await moteurA.refusees()} B ${await moteurB.refusees()}');
          // ignore: avoid_print
          print('A: attente ${ia.enAttente} refus ${ia.aTraiter} err ${ia.derniereErreur} | B: attente ${ib.enAttente} refus ${ib.aTraiter} err ${ib.derniereErreur}');
          fail('$quoi : pas de convergence. stock ${[mm, ma, mb].map((m) => m.collection('produits').toutes.map((f) => f['stockGros']))} ; factures ${[mm, ma, mb].map((m) => m.collection('factures').toutes.map((f) => '${f['montantPaye']}/${f['reliquat']}/${f['statutPaiement']}'))} ; erreurs ${pm.erreur.value} ${pa.erreur.value} ${pb.erreur.value} ; refus ${pm.motifsRefus} ${pa.motifsRefus} ${pb.motifsRefus}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    try {
      for (final mo in [moteurA, moteurB]) {
        final code = await console.codeAppareil(mo == moteurA ? 'A' : 'B').timeout(const Duration(seconds: 20));
        await mo.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
        mo.demarrer();
      }
      num stock(Magasin m) => m.collection('produits').parId('PRD1')!['stockGros'] as num;
      await converger(() => [pm, pa, pb].every((p) => p.erreur.value == null) && mm.collection('produits').toutes.length == 1 && stock(ma) == 10 && stock(mb) == 10, 'départ');
      // Deux postes sortent du stock en même temps.
      ma.collection('produits').mettreAJour('PRD1', {'stockGros': 7, 'stock': 7});
      mb.collection('produits').mettreAJour('PRD1', {'stockGros': 6, 'stock': 6});
      await converger(() => stock(mm) == 3 && stock(ma) == 3 && stock(mb) == 3, 'stock');
      expect(ma.collection('produits').toutes, hasLength(1));

      // Une facture créée sur A ; deux guichets règlent une ligne chacun.
      ma.collection('factures').inserer({
        'numero': 'FP-2026-00001',
        'montantPaye': 0,
        'reliquat': 1500,
        'statutPaiement': 'impayee',
        'lignes': [
          {'id': 'L1', 'montant': 1000, 'statutPaiement': 'du'},
          {'id': 'L2', 'montant': 500, 'statutPaiement': 'du'},
        ],
      }, prefixe: 'FAC');
      await converger(() => mb.collection('factures').toutes.length == 1 && mm.collection('factures').toutes.length == 1, 'facture créée');
      final fa = ma.collection('factures').toutes.single, fb = mb.collection('factures').toutes.single;
      ma.collection('factures').mettreAJour(fa['id'], {
        'montantPaye': 500,
        'reliquat': 1000,
        'statutPaiement': 'partielle',
        'lignes': [
          {'id': 'L1', 'montant': 1000, 'statutPaiement': 'du'},
          {'id': 'L2', 'montant': 500, 'statutPaiement': 'paye', 'payePar': 'A', 'payeLe': '2026-11-03T10:00:00Z'},
        ],
      });
      mb.collection('factures').mettreAJour(fb['id'], {
        'montantPaye': 1000,
        'reliquat': 500,
        'statutPaiement': 'partielle',
        'lignes': [
          {'id': 'L1', 'montant': 1000, 'statutPaiement': 'paye', 'payePar': 'B', 'payeLe': '2026-11-03T10:00:05Z'},
          {'id': 'L2', 'montant': 500, 'statutPaiement': 'du'},
        ],
      });
      bool soldee(Magasin m) {
        final f = m.collection('factures').toutes.single;
        return f['montantPaye'] == 1500 && f['reliquat'] == 0 && f['statutPaiement'] == 'soldee' && (f['lignes'] as List).every((l) => (l as Map)['statutPaiement'] == 'paye');
      }

      await converger(() => soldee(mm) && soldee(ma) && soldee(mb), 'règlements');
      for (final m in [mm, ma, mb]) {
        expect(m.collection('factures').toutes, hasLength(1));
      }
      expect(String.fromCharCodes(File('${d.path}/mere.db').readAsBytesSync()).contains('FP-2026-00001'), isFalse, reason: 'la base de la mère ne montre rien en clair');
      expect(String.fromCharCodes(File('${d.path}/a.db').readAsBytesSync()).contains('FP-2026-00001'), isFalse, reason: 'ni le journal d’un fileul');
      expect(await moteurA.refusees(), isEmpty, reason: 'aucun refus de la mère à traiter');
      expect(await moteurB.refusees(), isEmpty);
    } finally {
      pa.arreter();
      pb.arreter();
      pm.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 180)));
}
