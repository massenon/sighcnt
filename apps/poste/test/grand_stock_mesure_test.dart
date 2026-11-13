import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import 'aide_grand_stock.dart';

/// LA MESURE DU DOUBLE COMPTAGE DU GRAND STOCK (lot IMP-E, étape 1, décision de la Direction du 13/11/2026 : « l'argument du double comptage n'est pas prouvé : il faut le mesurer »).
/// Un fileul écrit le Grand Stock chez lui par la voie d'IMP-D (`importerEtDemander`), la VRAIE mère Dart rejoue la demande, et l'on compte, chez le fileul ET chez la mère, les
/// fiches et les quantités de chaque article après plusieurs tours de synchronisation.
void main() {
  test('MESURE : écrit chez le fileul puis rejoué par la mère, le Grand Stock se compte DEUX fois (fiches, lots, mouvements)', () async {
    final c = Clinique(9421, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour();
      final r = f1.importer('gs-valide');
      expect(r.resultat.ok, isTrue, reason: '${r.resultat.motif}');
      final id = '${r.demande!['id']}';
      expect(f1.etat('MED1'), {'fichesProduit': 1, 'stockGros': stockMed1, 'fichesLot': 2, 'sommeLots': 150, 'mouvementsEntree': 2, 'sommeEntrees': 150}, reason: 'écrit chez le fileul : exact');
      await c.converger(() => f1.demande(id)?['etat'] == demandeImportAppliquee, 'la mère rejoue la demande');
      // CE QUI EST MESURÉ À L'ARBRE D'AVANT : le catalogue, les lots et les mouvements existent en double chez le fileul ET chez la mère.
      for (final (nom, e) in [('fileul', f1.etat('MED1')), ('mère', c.etatMere('MED1'))]) {
        expect(e['fichesProduit'], 2, reason: '$nom : le produit existe sous deux identités de synchronisation');
        expect(e['fichesLot'], 4, reason: '$nom : chaque lot existe deux fois');
        expect(e['sommeLots'], 300, reason: '$nom : 300 unités en lot pour 150 importées');
        expect(e['mouvementsEntree'], 4, reason: '$nom : chaque mouvement d\'entrée existe deux fois');
        expect(e['sommeEntrees'], 300);
      }
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
