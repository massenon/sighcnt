import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tiers_poste.dart';

import 'aide_grand_stock.dart';

/// LOT TIERS : la facture à un tiers payeur et ses pièces voyagent, contre la VRAIE mère Dart et de VRAIS moteurs de fileul (la mère arrêtée pour de vrai) :
///  - un tiers, une facture (brouillon puis émise, avec la décision de l'AIB et son numéro) écrits chez un fileul arrivent à la mère et à l'autre fileul ;
///  - identité COMMUNE par le contenu : la même facture écrite par deux postes, mère coupée, ne fait qu'UNE fiche, sans refus à « traiter » ;
///  - une pièce ÉMISE ne se réécrit pas : un fileul qui croyait encore la pièce en brouillon et change sa base est refusé PAR LA MÈRE au rejeu (refus nommé), la pièce reste intacte ;
///  - un règlement et son lettrage voyagent, la créance se calcule pareil partout.
/// Non éprouvé ici : le relais cPanel réel, deux machines distinctes, Windows.
Fiche facturePatient() => {
      'id': 'FAC-T1',
      'statut': 'actif',
      'numero': 'FAC-2026-0001',
      'date': '2026-10-10',
      'patientId': 'PAT0003',
      'patient': 'Patient Trois',
      'montantTTC': 200000,
      'type': 'Facture',
      'lignes': [
        for (final i in [1, 2, 3]) {'id': 'L00$i', 'designation': 'Prestation $i', 'montant': 100000, 'partAssureur': 0, 'partPersonnel': 0}
      ],
    };

TiersPoste svc(Magasin m) => TiersPoste(m, auteur: () => 'Agent test', libelleRole: 'Comptable', droit: (_) => true, horloge: () => DateTime(2026, 10, 30));

Iterable<Fiche> pieces(Magasin m) => m.collection('facturesTiers').actives;

void main() {
  test('TIERS : tiers, facture émise, règlement et lettrage voyagent ; même facture écrite par deux postes mère coupée : UNE fiche ; pièce émise réécrite : refusée par la mère', () async {
    final c = Clinique(9872, '${Directory.systemTemp.createTempSync('sigh-tiers-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'comptable', 'COMPTABLE UN');
      final f2 = await c.fileul('F2', 'comptable', 'COMPTABLE DEUX');
      bool partout(bool Function(Magasin) p) => [c.mm, f1.m, f2.m].every(p);
      // La facture du patient existe déjà partout (le circuit des factures de caisse n'est pas l'objet du test) : posée sans journal, elle ne voyage pas.
      for (final m in [c.mm, f1.m, f2.m]) {
        m.collection('factures').ajouterSansJournal(facturePatient());
      }
      final t1 = svc(f1.m);
      final tiers = t1.creerTiers({'nom': 'Société de test', 'type': 'entreprise', 'ifu': '3201642748321', 'delaiPaiementJours': 30, 'dateEffet': '2026-01-05'});
      expect(tiers['ok'], isTrue);
      await c.converger(() => true, 'tours', apres: 4);
      String etat() => [for (final m in [c.mm, f1.m, f2.m]) '${m.collection('tiersPayeurs').actives.length}/${m.collection('factures').parId('FAC-T1') != null}'].join(' ');
      expect(partout((m) => m.collection('tiersPayeurs').actives.length == 1), isTrue, reason: 'tiers : ${etat()} refus F1 ${await f1.moteur.refusees()}');
      expect(partout((m) => m.collection('factures').parId('FAC-T1') != null), isTrue, reason: 'facture : ${etat()}');

      // 1. Brouillon, décision de l'AIB, émission chez F1 : la mère et F2 reçoivent la pièce émise, son numéro et sa décision.
      final p = t1.proposer({'tiersCode': tiers['code'], 'date': '2026-10-12', 'lignes': [{'factureId': 'FAC-T1', 'ligneId': 'L001', 'montant': 100000}]});
      expect(p['ok'], isTrue, reason: '$p');
      expect(t1.deciderAib(p['id'], {'appliquer': true, 'situation': 'ifu_actif', 'taux': 1})['ok'], isTrue);
      expect(t1.emettre(p['id'])['numero'], 'FT-2026-0001');
      final r = t1.reglement({'tiersCode': tiers['code'], 'date': '2026-10-20', 'montant': 101000, 'mode': 'virement', 'referencePaiement': 'VIR-T1'});
      await c.converger(() => partout((m) => pieces(m).length == 1 && pieces(m).single['statut'] == 'emise' && m.collection('reglementsTiers').actives.length == 1), 'la pièce émise et le règlement arrivent partout', apres: 4);
      for (final m in [c.mm, f2.m]) {
        final f = pieces(m).single;
        expect([f['numero'], f['net'], (f['aibDecision'] as Map)['taux']], ['FT-2026-0001', 101000, 1]);
        expect(f.containsKey('numeroMecef'), isFalse, reason: 'aucun numéro MECeF fabriqué');
      }
      final lettre = svc(f2.m).lettrer(f2.m.collection('reglementsTiers').actives.single['id'], [
        {'factureTiersId': pieces(f2.m).single['id'], 'montant': 101000}
      ]);
      expect(lettre['ok'], isTrue, reason: '$lettre');
      await c.converger(() => partout((m) => m.collection('lettragesTiers').actives.length == 1), 'le lettrage fait chez F2 arrive partout', apres: 4);
      for (final m in [c.mm, f1.m]) {
        expect(svc(m).creance(pieces(m).single), 0, reason: 'la créance se calcule pareil partout (dû moins lettrages)');
      }
      expect(r['ok'], isTrue);

      // 2. MÈRE COUPÉE : F1 et F2 écrivent la MÊME facture (même tiers, même date, mêmes prestations) : UNE fiche.
      await c.mere.arreter();
      for (final f in [f1, f2]) {
        final b = svc(f.m).proposer({'tiersCode': tiers['code'], 'date': '2026-10-15', 'lignes': [{'factureId': 'FAC-T1', 'ligneId': 'L002', 'montant': 50000}]});
        expect(b['ok'], isTrue, reason: '${f.nom} : $b');
      }
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await c.demarrerMere();
      await c.converger(() => partout((m) => pieces(m).where((f) => f['statut'] == 'brouillon').length == 1), 'mère relancée : la même facture écrite par deux postes ne fait qu\'UNE fiche', apres: 6);
      for (final f in [f1, f2]) {
        final refus = [for (final x in await f.moteur.refusees()) if (x['code'] == 'fiche_existe') x];
        expect(refus, isEmpty, reason: '${f.nom} : aucun refus « fiche_existe » à traiter');
      }

      // 3. UNE PIÈCE ÉMISE NE SE RÉÉCRIT PAS : F1 émet le brouillon ; F2, qui le croit encore brouillon, change sa base : la mère refuse au rejeu.
      final b1 = pieces(f1.m).firstWhere((f) => f['statut'] == 'brouillon');
      expect(svc(f1.m).deciderAib(b1['id'], {'appliquer': false, 'motif': 'L\'acheteur paie son AIB'})['ok'], isTrue);
      expect(svc(f1.m).emettre(b1['id'])['numero'], 'FT-2026-0002');
      // La pièce émise parvient à la MÈRE (F1 pousse, la mère la relève) ; F2, qui n'a pas encore tiré, la croit toujours en brouillon.
      final fin = DateTime.now().add(const Duration(seconds: 30));
      while (!pieces(c.mm).any((f) => f['numero'] == 'FT-2026-0002' && f['statut'] == 'emise')) {
        await f1.tour();
        await c.pontM.cycle();
        expect(DateTime.now().isBefore(fin), isTrue, reason: 'la pièce émise n\'arrive pas à la mère');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final b2 = pieces(f2.m).firstWhere((f) => f['statut'] == 'brouillon');
      f2.m.collection('facturesTiers').mettreAJour(b2['id'], {'base': 1});
      await f2.tour();
      await c.converger(() => true, 'F2 rejoue', apres: 3);
      final refus = await f2.moteur.refusees();
      expect(refus.where((x) => x['code'] == 'FACTURE_TIERS_FIGEE'), isNotEmpty, reason: '$refus ; mère : ${[for (final f in pieces(c.mm)) [f['numero'], f['statut'], f['base']]]} ; F1 : ${[for (final f in pieces(f1.m)) [f['numero'], f['statut'], f['base']]]} ; F2 : ${[for (final f in pieces(f2.m)) [f['numero'], f['statut'], f['base']]]}');
      final chezMere = pieces(c.mm).firstWhere((f) => f['numero'] == 'FT-2026-0002');
      expect(chezMere['base'], 50000, reason: 'la pièce émise reste intacte à la mère');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
