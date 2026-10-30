// Rejoue les vecteurs de m6-etiquetage (prototype_html/build/vecteurs-etiquetage.js) : plan des rayons, indicateurs, étiquettes, fiche d'un emplacement créé.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/stock/emplacements.dart' as emp show etatStock;
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final v = lireVecteurs('etiquetage');
  final e = (v['entree']! as Map).cast<String, Object?>();
  final emplacements = liste(e['emplacements']);
  final produits = liste(e['produits']);
  final lots = liste(e['lots']);
  final lu = (v['lu']! as Map).cast<String, Object?>();
  final g = (v['gestes']! as Map).cast<String, Object?>();

  test('les quatre indicateurs', () {
    final k = kpisEtiquetage(emplacements: emplacements, produits: produits, lots: lots);
    expect(['${k.emplacements}', '${k.articlesRanges}', '${k.sansEmplacement}', '${k.lotsFefo}'], (lu['kpi'] as List).cast<String>());
  });

  test('le référentiel : « Articles rangés » compte les produits qui portent le CODE du casier, « 2 / 10 » avec la capacité', () {
    final lignes = liste((lu['tables'] as List).first['lignes']);
    expect(lignes.length, emplacements.length);
    for (var i = 0; i < lignes.length; i++) {
      final emp = emplacements.firstWhere((x) => x['code'] == (lignes[i]['cellules'] as List)[0]);
      final occ = occupationCasier(articlesRanges(emp['code'], produits), emp['capacite']);
      expect(occ.texte ?? 'vide', (lignes[i]['cellules'] as List)[4], reason: '${emp['code']}');
    }
  });

  test('le plan des rayons : casiers triés, six articles par carte puis « + N autre(s) », absence d\'emplacement nommée (E48)', () {
    final plan = planDesRayons(produits);
    final cartes = liste(lu['cartes']);
    expect(plan.length, cartes.length);
    for (var i = 0; i < plan.length; i++) {
      final c = cartes[i];
      expect(plan[i].libelle == 'Sans emplacement' ? 'Sans emplacement' : plan[i].cle, plan[i].libelle);
      expect('${plan[i].articles.length} article${plan[i].articles.length > 1 ? 's' : ''}', c['badge']);
      final lignes = (c['lignes'] as List).cast<String>();
      final premiers = plan[i].articles.take(6).map((p) => '${p['designation']} ${nombre(p['stock'])}').toList();
      expect(lignes.take(premiers.length).toList(), premiers);
      if (plan[i].articles.length > 6) expect(lignes.last, '+ ${plan[i].articles.length - 6} autre(s)');
    }
    // Le titre « undefined » de la maquette est corrigé : la carte des articles sans emplacement s'appelle « Sans emplacement ».
    expect(cartes.last['titre'], 'Sans emplacement');
    expect(plan.last.libelle, 'Sans emplacement');
  });

  test('l\'état d\'un article : rupture, critique (au seuil ou dessous), normal', () {
    final etats = {for (final l in liste((lu['tables'] as List)[1]['lignes'])) (l['cellules'] as List)[1]: (l['cellules'] as List)[5]};
    for (final p in produits) {
      final attendu = {'rupture': 'Rupture', 'critique': 'Critique', 'normal': 'Normal'}[emp.etatStock(p)];
      expect(attendu, etats[p['code']], reason: '${p['code']}');
    }
  });

  test('les étiquettes d\'un casier : lot qui périme le premier (FEFO), prix unitaire sans devise', () {
    final plan = planDesRayons(produits);
    final etiquettes = liste(g['etiquettesCasiers']);
    for (var i = 0; i < plan.length; i++) {
      final attendu = (etiquettes[i]['textes'] as List).map((t) => (t as List).cast<String>()).toList();
      final obtenu = [for (final p in plan[i].articles) ligneEtiquette(p, lots)];
      expect(obtenu, attendu);
    }
    final tout = (g['etiquettesTout']! as Map)['textes'] as List;
    expect(tout.length, produits.length);
    // L'étiquette de l'ARTESUNATE porte le lot LOT-A (15/12/2026), pas LOT-B (01/03/2027) : le plus proche de la péremption.
    final art = ligneEtiquette(produits.firstWhere((p) => p['code'] == 'Q1'), lots);
    expect(art, containsAllInOrder(['Lot : LOT-A', 'Péremption : 15/12/2026']));
  });

  test('la fiche d\'un nouvel emplacement : source datée, capacité vide = 0', () {
    final c = (g['creationOk']! as Map)['cree'] as Map;
    final fiche = nouvelEmplacement({
      'code': 'B2', 'libelle': 'Armoire sécurisée 2', 'zone': 'Armoire sécurisée', 'temperature': 'Sous clé, ambiante', 'capacite': '4', 'observation': 'Stupéfiants'
    }, DateTime(2026, 10, 30));
    memes(fiche, c, 'creation', ignorer: const {'id'});
    final sans = nouvelEmplacement({'code': 'Z0', 'libelle': 'Sans capacité', 'zone': 'Rayonnage sec', 'temperature': 'Ambiante', 'capacite': '', 'observation': ''}, DateTime(2026, 10, 30));
    memes(sans, (g['creationSansCapacite']! as Map)['cree'], 'sansCapacite', ignorer: const {'id'});
  });

  test('un casier à sa capacité est signalé plein', () {
    expect(occupationCasier(2, 2).plein, isTrue);
    expect(occupationCasier(1, 10).plein, isFalse);
    expect(occupationCasier(8, null).texte, '8');
    expect(occupationCasier(0, 5).texte, isNull);
  });
}
