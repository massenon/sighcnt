import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfb_systeme.dart' show cfbViderActivite;

import 'aide_polices.dart';
import 'm11_aide.dart';

/// Retour de la Direction du 01/11/2026 : le vidage des jeux de test laissait la masse salariale, le calcul de la paie, la redevance ORTB, le coût de
/// l'agent et le tableau de bord Paie. Le vidage retire désormais les salaires de démonstration (l'effectif reste) et les fiches de poste ; les écrans
/// disent « non calculable » au lieu d'afficher des zéros. Scénario 75 de la maquette.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Magasin vide() {
    final m = magasin();
    cfbViderActivite(m, 'essai');
    return m;
  }

  bool aDuTexte(WidgetTester t, String morceau) => textes(t).any((x) => x.contains(morceau));

  test('le vidage garde l\'effectif, retire salaire, échelon et CNSS, vide les fiches de poste, garde le référentiel de paie', () {
    final m = magasin();
    final effectif = m.collection('personnel').toutes.length;
    expect(m.collection('fichesPoste').toutes, isNotEmpty);
    expect(m.collection('personnel').toutes.every((p) => p['salaireBase'] != null), isTrue);
    cfbViderActivite(m, 'essai');
    expect(m.collection('personnel').toutes.length, effectif);
    for (final p in m.collection('personnel').toutes) {
      expect([p['salaireBase'], p['categorie'], p['cnss']], [null, null, null], reason: '${p['nomComplet']}');
    }
    expect(m.collection('fichesPoste').toutes, isEmpty);
    expect(m.collection('bulletins').toutes, isEmpty);
    expect(m.collection('heuresSup').toutes, isEmpty);
    expect(m.collection('grillePrimes').toutes, isNotEmpty, reason: 'la grille des primes est un référentiel essentiel');
    expect(m.collection('regimesTravail').toutes, isNotEmpty);
    expect(m.collection('baremeNS131').toutes, isNotEmpty);
    expect(paiCalculerTous(m.collection('personnel').actives, 2026, 9, PaiEntrees(), DateTime(2026, 10, 30)), isEmpty);
  });

  cas('tableau de bord Paie : « Non calculable » partout, aucun montant, le bandeau nomme la cause', (t) async {
    await ouvrir(t, vide(), 'm11-dashboard');
    final lu = kpisAffiches(t);
    expect(lu['Masse salariale brute'], 'Non calculable');
    expect(lu['Net à payer'], 'Non calculable');
    expect(lu['Coût employeur total'], 'Non calculable');
    expect(lu.values.where((v) => v.contains('FCFA')), isEmpty);
    expect(aDuTexte(t, 'Aucun salaire de base n’est renseigné'), isTrue);
  });

  cas('calcul de la paie : zéro agent concerné, masses non calculables, aucune ligne', (t) async {
    await ouvrir(t, vide(), 'm11-calcul');
    final lu = kpisAffiches(t);
    expect(lu['Agents concernés'], '0');
    expect(lu['Masse salariale brute'], 'Non calculable');
    expect(lu['Net à payer'], 'Non calculable');
    expect(aDuTexte(t, 'Aucun salaire de base n’est renseigné'), isTrue);
  });

  cas('cotisations : CNSS, ITS et masse brute non calculables', (t) async {
    await ouvrir(t, vide(), 'm11-cotisations');
    final lu = kpisAffiches(t);
    expect(lu['CNSS part ouvrière'], 'Non calculable');
    expect(lu['ITS retenu'], 'Non calculable');
    expect(lu['Masse salariale brute'], 'Non calculable');
  });

  cas('redevance ORTB : non calculable, sans agent ni montant dû', (t) async {
    await ouvrir(t, vide(), 'm11-ortb');
    expect(aDuTexte(t, 'Redevances ORTB non calculables'), isTrue);
    expect(libellesKpi(t), isEmpty);
  });

  cas('fiches de poste : aucune fiche, aucun poste recensé d\'office, et l\'écran dit comment les retrouver', (t) async {
    await ouvrir(t, vide(), 'm10-fiches-poste');
    expect(aDuTexte(t, 'Aucune fiche de poste n’est enregistrée'), isTrue);
    expect(kpisAffiches(t)['Postes recensés'], '0');
  });

  cas('personnel : l\'effectif reste, la masse salariale et le salaire moyen sont « non renseignés »', (t) async {
    await ouvrir(t, vide(), 'm10-personnel');
    final lu = kpisAffiches(t);
    expect(lu['Masse salariale'], 'Non renseignée');
    expect(lu['Salaire moyen'], 'Non renseigné');
    expect(int.parse(lu['Effectif']!), greaterThan(0));
  });

  cas('jeu complet : les mêmes écrans calculent (garde contre un « Non calculable » permanent)', (t) async {
    await ouvrir(t, magasin(), 'm11-calcul');
    final lu = kpisAffiches(t);
    expect(lu['Masse salariale brute'], isNot('Non calculable'));
    expect(int.parse(lu['Agents concernés']!.replaceAll(RegExp(r'\s'), '')), greaterThan(0));
  });
}
