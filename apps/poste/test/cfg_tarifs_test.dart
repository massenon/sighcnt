import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/cfg.json').readAsStringSync()));

/// cfg-tarifs : les règles (RG-02, codes, notes, filtres) sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cfa_regles_test.dart) ;
/// ici, l'ÉCRAN — quatre onglets, saisies, jamais de tarif inventé, et ce qui est ABSENT sans le droit.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final t0 = obj(v['tarifs']);

  Future<void> onglet(WidgetTester t, String libelle) => toucherM14(t, find.text(libelle).first);

  casM14('ouverture : les quatre indicateurs de la maquette, la propagation du tarif, quatre onglets avec leur compte, RG-02 en note', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs');
    for (final k in (t0['kpis'] as List).cast<List>()) {
      expect(find.text('${k[0]}'), findsOneWidget, reason: '${k[0]}');
      expect(find.text('${k[1]}'), findsWidgets, reason: '${k[0]} = ${k[1]}');
    }
    expect(find.text('8 secteurs'), findsOneWidget);
    expect(find.text('Colonnes de prix vierges aux sources'), findsOneWidget);
    expect(find.text('Propagation du tarif'), findsOneWidget);
    expect(find.text('TARIF MASTER'), findsOneWidget);
    for (final x in ['Pharmacie', 'Facturation', 'Assurances', 'Rapports', 'Comptabilité']) {
      expect(find.text(x), findsWidgets, reason: x);
    }
    for (final o in ['Produits & médicaments', 'Analyses de laboratoire', 'Actes & hospitalisation', 'Certificats et Attestations']) {
      expect(find.text(o), findsOneWidget, reason: o);
    }
    expect(find.textContaining('RG-02 — pour les médicaments'), findsOneWidget);
    for (final h in obj(t0['produits'])['entetes'] as List) {
      expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
    }
    expect(find.text('Sans marge'), findsWidgets);
  });

  casM14('création d’un médicament : RG-02 — le prix de vente SUIT le prix d’achat, code PRD-0185, stocks à zéro ; un consommable garde son prix', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs');
    final avant = m.collection('produits').toutes.length;
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'designation', 'Médicament Test A');
    await saisir(t, 'prixAchat', '700');
    await saisir(t, 'prixVente', '900');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    var f = m.collection('produits').toutes.first;
    expect(m.collection('produits').toutes.length, avant + 1);
    expect(f['categorie'], 'medicament');
    expect(f['prixAchat'], 700);
    expect(f['prixVente'], 700, reason: 'RG-02 : aucune marge sur un médicament');
    expect(f['code'], 'PRD-${(avant + 1).toString().padLeft(4, '0')}');
    expect([f['stock'], f['stockGros'], f['stockDetail']], [0, 0, 0]);
    expect(find.text('Produit créé.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'designation', 'Consommable Test B');
    await choisirM14(t, 'categorie', 'Consommable médical');
    await saisir(t, 'prixAchat', '300');
    await saisir(t, 'prixVente', '450');
    await saisir(t, 'code', 'CTB-1');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    f = m.collection('produits').toutes.first;
    expect([f['categorie'], f['prixAchat'], f['prixVente'], f['code']], ['conso_medical', 300, 450, 'CTB-1']);
  });

  casM14('produits : « Archiver » est ABSENT (les produits se retirent par le stock), « Modifier » corrige les quatre champs', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs');
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.byTooltip('Modifier'), findsWidgets);
    await toucherM14(t, find.byTooltip('Modifier').first);
    expect(find.text('Désignation *'), findsOneWidget);
    expect(find.text('Prix d’achat (FCFA) *'), findsOneWidget);
    expect(find.text('Prix de vente (FCFA) *'), findsOneWidget);
    expect(find.text('Catégorie *'), findsNothing, reason: 'la catégorie ne se modifie pas ici');
    expect(find.textContaining('doit rester égal au prix d’achat'), findsOneWidget);
  });

  casM14('onglet Analyses : valeurs d’attente à confirmer, création = rang 49, code L49, tarif TOUJOURS provisoire, « à confirmer » augmente', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs');
    await onglet(t, 'Analyses de laboratoire');
    expect(find.textContaining('valeurs d’attente à confirmer'), findsOneWidget);
    for (final h in obj(t0['analyses'])['entetes'] as List) {
      expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
    }
    expect(find.text('À confirmer'), findsWidgets);
    expect(find.text('48'), findsWidgets);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'designation', 'Analyse Test');
    await saisir(t, 'categorie', 'Hématologie');
    await saisir(t, 'prix', '2500');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('analyses').toutes.first;
    expect([f['n'], f['code'], f['prix'], f['tarifProvisoire']], [49, 'L49', 2500, true]);
    expect(find.text('Analyse créé.'), findsOneWidget);
    expect(find.text('49'), findsWidgets);
  });

  casM14('onglet Actes : trois notes (grille, déclinés), création SANS prix = absent (« à valider »), jamais zéro ; « à confirmer » augmente', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs');
    await onglet(t, 'Actes & hospitalisation');
    for (final n in (t0['notesActes'] as List)) {
      expect(find.textContaining('$n'.substring(0, 60)), findsOneWidget);
    }
    for (final h in obj(t0['actes'])['entetes'] as List) {
      expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
    }
    expect(find.widgetWithText(BoutonSigh, 'Imprimer la grille tarifaire'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'libelle', 'Acte Test Sans Prix');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('actes').toutes.first;
    expect(f['code'], 'ACT-074');
    expect(f.containsKey('prix') ? f['prix'] : null, isNull);
    expect(find.text('Acte créé.'), findsOneWidget);
    expect(find.text('49'), findsWidgets, reason: 'Tarifs à confirmer : 48 analyses + 1 acte sans prix');
  });

  casM14('« Imprimer la grille tarifaire » : l’état de la maquette', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs');
    await onglet(t, 'Actes & hospitalisation');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la grille tarifaire'));
    expect(find.text('Grille tarifaire des actes et prestations'), findsWidgets);
    expect(find.textContaining('Prestations au catalogue'), findsWidgets);
    expect(find.textContaining('Tarifs à valider'), findsWidgets);
  });

  casM14('onglet Certificats : lus depuis le catalogue (6), SOS seule, et les pièces sans tarif sont NOMMÉES', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs');
    await onglet(t, 'Certificats et Attestations');
    expect(find.textContaining('cet onglet les lit, il ne les duplique pas'), findsOneWidget);
    expect(find.text('SOS seule'), findsWidgets);
    expect(find.textContaining('8 type(s) de pièce sans tarif au catalogue'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing, reason: 'cet onglet ne duplique rien : aucune saisie');
  });

  casM14('droits : en lecture seule, aucune commande d’écriture (absentes, jamais grisées) et le bandeau le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-tarifs'));
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    await onglet(t, 'Actes & hospitalisation');
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer la grille tarifaire'), findsOneWidget);
  });
}
