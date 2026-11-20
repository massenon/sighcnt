import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show ciblesInventaire, stockTheorique;
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm6_mouvements_test.dart' show magasin, ouvrir, toucher, choisir, cas;

/// LOT INVENT-NC (décision 12 de la Direction du 15/11/2026) au poste : la feuille d'inventaire part VIDE ; un article dont rien n'est saisi est NON COMPTÉ
/// (ligne « nonCompte », sans physique ni écart), jamais « compté, écart zéro » ; son stock n'est jamais touché (RG-03) ; la validation reste possible ; le
/// registre le dit. Mêmes règles que la maquette (vecteurs `stock_mouvements.json`, cas « non compté »).
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  cas('feuille du magasin GROS : un article compté avec écart, un compté juste, les autres laissés vides : non comptés, stock inchangé, aucun mouvement pour eux ; le registre dit « Non comptés »', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm6-inventaire');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Lancer un inventaire'));
    await choisir(t, 'magasin', 'Stock gros (magasin central)');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Ouvrir la feuille de saisie'));
    await t.pump(const Duration(milliseconds: 400));
    final cible = ciblesInventaire(m.collection('produits').actives, 'Tous les articles');
    expect(cible.length, greaterThanOrEqualTo(3));
    final a = cible[0], b = cible[1], c = cible[2];
    // La case part VIDE et l'écart dit « non compté » (le théorique n'est plus recopié).
    expect(find.byKey(Key('inv:nc:${a['code']}')), findsOneWidget);
    final champA = t.widget<TextField>(find.byKey(Key('inv:${a['code']}')));
    expect(champA.controller!.text, isEmpty);
    final stocks = {for (final p in cible) p['id']: (p['stockGros'], p['stockDetail'], p['stock'])};
    final mvAvant = m.collection('mouvements').actives.length;
    final thA = stockTheorique(a, 'gros'), thC = stockTheorique(c, 'gros');
    await t.enterText(find.byKey(Key('inv:${a['code']}')), '${thA.toInt() + 2}');
    await t.enterText(find.byKey(Key('inv:${c['code']}')), '${thC.toInt()}');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(Key('inv:nc:${a['code']}')), findsNothing);
    expect(find.byKey(Key('inv:nc:${b['code']}')), findsOneWidget, reason: 'B laissé vide : non compté');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Valider l’inventaire').last);
    final inv = m.collection('inventaires').actives.single;
    expect(inv['nbArticles'], cible.length);
    expect(inv['nbComptes'], 2);
    expect(inv['nbNonComptes'], cible.length - 2);
    expect(inv['nbEcarts'], 1, reason: 'C compté juste n\'est pas un écart, B non compté non plus');
    final lignes = {for (final l in (inv['lignes'] as List)) (l as Map)['code']: l.cast<String, Object?>()};
    expect(lignes[b['code']]!['nonCompte'], true);
    expect(lignes[b['code']]!.containsKey('physique'), isFalse);
    expect(lignes[b['code']]!.containsKey('ecart'), isFalse);
    expect(lignes[c['code']]!['nonCompte'], isNull);
    expect(lignes[c['code']]!['ecart'], 0);
    // RG-03 : aucun stock touché hors de A, un seul mouvement (A).
    for (final p in cible.skip(1)) {
      final f = m.collection('produits').parId(p['id'])!;
      expect((f['stockGros'], f['stockDetail'], f['stock']), stocks[p['id']], reason: '${p['code']} : stock inchangé');
    }
    expect(m.collection('mouvements').actives.length, mvAvant + 1);
    expect(m.collection('mouvements').actives.first['produitId'], a['id']);
    expect(find.textContaining('non compté(s) : enregistré(s) « non compté », stock inchangé'), findsWidgets);
    // Le registre le dit.
    await ouvrir(t, m, 'm6-inventaire');
    expect(find.text('NON COMPTÉS'), findsWidgets, reason: 'en-tête de colonne (capitales du tableau)');
    expect(find.byKey(Key('inventaire-non-comptes-${inv['reference']}')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(Key('inventaire-non-comptes-${inv['reference']}'))).data, '${cible.length - 2}');
    // L'état imprimé le dit : « Non compté » sur la ligne, le compte au cartouche.
    await toucher(t, find.byTooltip('Imprimer l’état').first);
    await t.pumpAndSettle();
    expect(find.text('État d’inventaire'), findsWidgets);
    expect(find.text('Non compté'), findsNWidgets(2 * (cible.length - 2)),
        reason: 'chaque ligne non comptée dit « Non compté » au physique ET à l\'écart, jamais un physique égal au théorique');
    expect(find.textContaining('(stock inchangé)'), findsWidgets);
    await t.pump(const Duration(seconds: 15)); // le message de validation (12 s) se referme
  });
}
