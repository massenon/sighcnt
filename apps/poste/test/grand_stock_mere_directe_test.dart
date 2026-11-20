import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/import/port_magasin.dart';

import 'aide_grand_stock.dart';

/// LE SENS INVERSE (lot IMP-E) : la MÈRE (ou un poste autonome) importe le Grand Stock directement, ses fileuls le reçoivent par la configuration (le catalogue) et par le pont (lots,
/// mouvements, variations). Une mesure faite pour la décision du 13/11/2026 : le stock arrive-t-il exact chez un fileul qui n'a rien écrit, ou compté deux fois ?
void main() {
  test('LA MÈRE IMPORTE LE GRAND STOCK : un fileul qui n\'a rien écrit reçoit le stock EXACT (une fiche par article, lot et mouvement, 150 unités), jamais doublé', () async {
    final c = Clinique(9426, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour();
      final profil = ProfilImport(role: 'admin', libelleRole: 'admin', matrice: donnees.matrice.matriceImport);
      final port = PortMagasin(c.mm, aujourdhui: () => DateTime(2026, 11, 13), nomAgent: 'ADMIN MÈRE', profil: profil);
      final jeu = jeuImportParId('grand-stock')!;
      final a = analyserLignes(jeu, lignesDuCas('gs-valide'), 'gs-valide.xlsx', port)..empreinte = 'e-mere';
      expect(a.accepte, isTrue);
      final r = appliquer(jeu, a, port);
      expect(r.ok, isTrue, reason: '${r.motif}');
      expect(c.etatMere('MED1'), {'fichesProduit': 1, 'stockGros': 150, 'fichesLot': 2, 'sommeLots': 150, 'mouvementsEntree': 2, 'sommeEntrees': 150});
      await c.converger(() => f1.produits('MED1').isNotEmpty && f1.m.collection('lots').toutes.length >= 2, 'le fileul reçoit le stock de la mère', apres: 6);
      expect(f1.etat('MED1'), {'fichesProduit': 1, 'stockGros': 150, 'fichesLot': 2, 'sommeLots': 150, 'mouvementsEntree': 2, 'sommeEntrees': 150}, reason: 'chez le fileul : le stock de la mère, une fois');
      expect(f1.etat('GANT1'), {'fichesProduit': 1, 'stockGros': 40, 'fichesLot': 0, 'sommeLots': 0, 'mouvementsEntree': 1, 'sommeEntrees': 40});
      expect(c.etatMere('MED1')['stockGros'], 150, reason: 'la mère n\'a pas bougé');
      // Une sortie du fileul sur ce stock reçu atteint la mère UNE fois.
      f1.sortir('MED1', 'L1', 10);
      await c.converger(() => c.etatMere('MED1')['sommeLots'] == 140, 'la sortie du fileul atteint la mère', apres: 6);
      expect(c.etatMere('MED1'), {'fichesProduit': 1, 'stockGros': 140, 'fichesLot': 2, 'sommeLots': 140, 'mouvementsEntree': 2, 'sommeEntrees': 150});
      expect(f1.etat('MED1'), {'fichesProduit': 1, 'stockGros': 140, 'fichesLot': 2, 'sommeLots': 140, 'mouvementsEntree': 2, 'sommeEntrees': 150});
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
