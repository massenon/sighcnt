// Rejoue les vecteurs de m6-reprise (prototype_html/build/vecteurs-reprise.js) : le référentiel SAGE engendré, le rapprochement recalculé, les indicateurs
// avec et sans la surcouche de valorisation, la fiche de valorisation saisie.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final v = lireVecteurs('reprise');
  final ref = ReferentielSage.instance;

  test('le lot d\'import et l\'inventaire sont ceux du document (184 articles, 12 080 unités)', () {
    expect(ref.articles.length, 184);
    expect(ref.totalUnites, 12080);
    expect(ref.lot['reference'], 'IMPORT-SAGE-20260715');
    expect(ref.lot['totalUnites'], ref.totalUnites, reason: 'contrôle de cohérence « Quantités concordantes »');
  });

  test('l\'unité et le seuil proposé suivent la désignation et la quantité', () {
    expect(seuilPropose(2), 5);
    expect(seuilPropose(50), 10);
    expect(seuilPropose(12), 5);
    for (final a in ref.articles) {
      expect(a.seuil, seuilPropose(a.quantite), reason: a.code);
    }
    expect(ref.articles.firstWhere((a) => a.code == 'ACU').unite, 'Ampoule');
  });

  test('le rapprochement au catalogue tarifaire recalculé est celui de la maquette (144 désignations)', () {
    final m = ref.rapprochement();
    expect(m.length, 144);
    for (final r in m) {
      final base = ref.catalogue.firstWhere((c) => c['n'] == r.n);
      expect(r.article, base['article']);
      expect(r.designationStock, base['designationStock']);
      expect(r.cump, base['cump']);
      expect(r.correspondance, base['correspondance']);
    }
    expect(m.where((r) => r.correspondance == 'absente').length, greaterThan(0));
  });

  for (final cle in ['avecSurcouche', 'sansSurcouche']) {
    test('indicateurs $cle', () {
      final fiches = cle == 'avecSurcouche' ? _surcoucheDuJeu() : <Map<String, Object?>>[];
      final k = kpisReprise(ref.articles, fiches);
      final lu = liste((v[cle]! as Map)['kpi']);
      expect(nombre(k.articles), lu[0]['valeur']);
      expect(nombre(k.unites), lu[1]['valeur']);
      expect(money(k.valeur), lu[2]['valeur']);
      expect(nombre(k.nonValorises), lu[3]['valeur']);
      expect(nombre(k.valorisesParClinique), lu[4]['valeur']);
      expect(k.indiceValorises, lu[4]['indice']);
    });
  }

  test('« non valorisé » = ni le document ni la clinique ; le prix retenu est celui du document, sinon celui qu\'on a saisi', () {
    final aba = ref.articles.firstWhere((a) => a.code == 'ABA');
    expect(aba.valorise, isFalse);
    expect(resteSansPrix(aba, const []), isTrue);
    expect(prixRevient(aba, const []), isNull);
    final fiche = [
      {'code': 'ABA', 'prixRevient': 850}
    ];
    expect(resteSansPrix(aba, fiche), isFalse);
    expect(prixRevient(aba, fiche), 850);
    final acc = ref.articles.firstWhere((a) => a.code == 'ACC');
    expect(prixRevient(acc, fiche), acc.cump);
  });

  test('la valorisation saisie : la fiche de surcouche et le message de succès', () {
    final s = (v['saisie']! as Map).cast<String, Object?>();
    final aba = ref.articles.firstWhere((a) => a.code == s['code']);
    final fiche = ficheValorisation(aba,
        prixRevient: 850, source: 'Facture UBIPHARM n° 4471', observation: 'Relevé du 28/10', auteur: 'c.bassongui', jour: '2026-10-30');
    memes(fiche, (s['ok']! as Map)['fiche'], 'fiche', ignorer: const {'id'});
    expect(['Référence valorisée.', detailValorisation(aba, 850)], ((s['ok']! as Map)['toasts'] as List).single);
    // Sans observation, le champ n'est pas écrit (la maquette écrit `null`, que le magasin n'enregistre pas).
    expect(ficheValorisation(aba, prixRevient: 1, source: 's', auteur: 'a', jour: '2026-10-30').containsKey('observation'), isFalse);
  });
}

/// La surcouche semée au socle de la maquette (34 fiches), telle que le jeu du poste la porte.
List<Map<String, Object?>> _surcoucheDuJeu() => liste(jsonDecode(
    File('../../apps/poste/assets/donnees/jeu/valorisationsSage.json').readAsStringSync()));
