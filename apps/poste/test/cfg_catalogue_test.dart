import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/cfg.json').readAsStringSync()));
String s(Object? x) => '$x'.replaceAll(RegExp(r'[\s  ]'), '');

/// cfg-catalogue : les règles (KPI, notes, écart, couverture, création) sont rejouées sur les vecteurs de la maquette ; ici, l'ÉCRAN — les six familles,
/// les trois états de la colonne assurée (un montant, NON COUVERT, un tiret ≠ zéro), le détail qui NOMME l'arbitrage, et les droits.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final cat = obj(v['catalogue']);

  Future<void> chercher(WidgetTester t, String q) async {
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, q);
    await t.pump(const Duration(milliseconds: 500));
  }

  casM14('ouverture : quatre indicateurs, notes de la maquette, six familles, en-têtes', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue');
    for (final k in (cat['kpis'] as List).cast<List>()) {
      expect(find.text('${k[0]}'), findsOneWidget, reason: '${k[0]}');
      expect(find.text('${k[1]}'), findsWidgets, reason: '${k[0]} = ${k[1]}');
      if (k[2] != null) expect(find.text('${k[2]}'), findsOneWidget, reason: '${k[2]}');
    }
    for (final n in (cat['notes'] as List)) {
      expect(find.textContaining('$n'.substring(0, 50)), findsOneWidget);
    }
    for (final f in liste(cat['familles'])) {
      final libelle = '${f['onglet']}'.replaceFirst(RegExp(r'\d+$'), '');
      expect(find.text(libelle), findsWidgets, reason: libelle);
    }
    for (final h in obj(liste(cat['familles']).first['tableau'])['entetes'] as List) {
      expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
    }
    expect(find.widgetWithText(BoutonSigh, 'Nouvel acte'), findsOneWidget);
  });

  casM14('les prix s’écrivent comme à l’écran : écart signé, SOS seule, « — » pour les certificats sans écart utile', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue');
    final consultations = liste(cat['familles']).first;
    for (final l in (obj(consultations['tableau'])['lignes'] as List).cast<List>()) {
      expect(find.textContaining('${l[0]}'), findsWidgets, reason: '${l[0]}');
      expect(find.byWidgetPredicate((w) => w is Text && s(w.data) == s(l[3])), findsWidgets, reason: '${l[0]} prix assuré');
    }
    await toucherM14(t, find.text('Certificats et attestations').first);
    expect(find.textContaining('SOS seule — '), findsWidgets);
  });

  casM14('détail d’un acte ARBITRÉ : la marque « arbitré » et la décision de la Direction sont lisibles (un assuré qui paie moins n’est pas une coquille)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue');
    await toucherM14(t, find.text('Analyses de laboratoire').first);
    await chercher(t, 'LAB-HIV');
    expect(find.text('arbitré'), findsOneWidget);
    await toucherM14(t, find.byTooltip('Consulter').first);
    expect(find.textContaining('Prix arrêté par la Direction le 26/08/2026'), findsOneWidget);
    expect(find.text('Toutes compagnies'), findsOneWidget);
  });

  casM14('détail d’un acte NON COUVERT : badge, couverture « Aucune » et note nommée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue');
    await toucherM14(t, find.text('Actes gynéco-obstétricaux et kits').first);
    await chercher(t, 'HYD');
    expect(find.text('NON COUVERT'), findsOneWidget);
    await toucherM14(t, find.byTooltip('Consulter').first);
    expect(find.text('Aucune'), findsOneWidget);
    expect(find.textContaining('Tous les actes de planification familiale'), findsOneWidget);
  });

  casM14('création : un prix assuré vide est « à valider » (jamais zéro) ; NON COUVERT rend l’acte non assurable ; le prix absent bloque la ligne', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue');
    final avant = m.collection('catalogueTarifs').toutes.length;
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvel acte'));
    await saisir(t, 'code', 'TST-C2');
    await saisir(t, 'libelle', 'Acte Test Sans Assuré');
    await saisir(t, 'prixNonAssure', '5000');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    var f = m.collection('catalogueTarifs').toutes.first;
    expect(m.collection('catalogueTarifs').toutes.length, avant + 1);
    expect(f['famille'], 'CONSULTATION');
    expect(f['prixAssure'], isNull);
    expect(f['prixAValider'], true);
    expect(f['assurable'], true);
    expect(f['source'], 'Saisi par l’administrateur');
    expect(find.text('Acte créé.'), findsOneWidget);
    // Le prix manquant est annoncé en tête : « Prix non renseigné » passe à 1 et la note nomme l'acte.
    expect(find.textContaining('1 acte(s) sans prix au document : Acte Test Sans Assuré'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvel acte'));
    await saisir(t, 'code', 'TST-C3');
    await saisir(t, 'libelle', 'Acte Test Non Couvert');
    await saisir(t, 'prixNonAssure', '5000');
    await cocher(t, 'nonCouvert');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    f = m.collection('catalogueTarifs').toutes.first;
    expect([f['nonCouvert'], f['assurable'], f['prixAValider']], [true, false, false]);
  });

  casM14('champs obligatoires : code et désignation manquants sont refusés, rien n’est écrit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue');
    final avant = m.collection('catalogueTarifs').toutes.length;
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvel acte'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(m.collection('catalogueTarifs').toutes.length, avant);
  });

  casM14('archivage : motif exigé, l’acte reste (RG-14)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue');
    final avant = m.collection('catalogueTarifs').toutes.length;
    await toucherM14(t, find.byTooltip('Archiver').first);
    await t.enterText(find.byType(TextField).last, 'Doublon');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('catalogueTarifs').archivees.length, 1);
    expect(m.collection('catalogueTarifs').toutes.length, avant);
  });

  casM14('droits : en lecture seule, aucune commande d’écriture (absentes) mais la consultation reste', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-catalogue'));
    expect(find.widgetWithText(BoutonSigh, 'Nouvel acte'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
  });
}
