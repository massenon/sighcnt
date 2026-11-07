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

/// cfg-imagerie-catalogue : les règles (indicateurs, choix « a|b », message de bascule) sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/cfa_regles_test.dart) ; ici, l'ÉCRAN — la modalité propre à l'examen, la variable qui se FERME sans se supprimer, et les droits.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final im = obj(v['imagerie']);

  Future<void> onglet(WidgetTester t, String id) => toucherM14(t, find.byKey(Key('kit:onglet:$id')));
  Future<void> chercher(WidgetTester t, String q) async {
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, q);
    await t.pump(const Duration(milliseconds: 500));
  }

  casM14('ouverture : quatre indicateurs, deux onglets, en-têtes de la maquette, modalité de chaque examen, origine « à valider »', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-imagerie-catalogue');
    for (final k in (im['kpis'] as List).cast<List>()) {
      expect(find.text('${k[0]}'), findsOneWidget, reason: '${k[0]}');
      expect(find.text('${k[1]}'), findsWidgets, reason: '${k[0]} = ${k[1]}');
    }
    expect(find.text('La demande du brouillon manuscrit'), findsOneWidget);
    expect(find.byKey(const Key('kit:onglet:examens:actif')), findsOneWidget);
    expect(find.byKey(const Key('kit:onglet:variables')), findsOneWidget);
    for (final h in obj(im['examens'])['entetes'] as List) {
      expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
    }
    for (final l in (obj(im['examens'])['lignes'] as List).cast<List>()) {
      expect(find.text('${l[0]}'), findsWidgets, reason: '${l[0]}');
      expect(find.text('${l[2]}'), findsWidgets, reason: '${l[2]}');
    }
    expect(find.text('Documentée'), findsWidgets);
    expect(find.widgetWithText(BoutonSigh, 'Nouvel examen'), findsOneWidget);
  });

  casM14('création d’un examen : la modalité range l’examen dans son tableau ; code et intitulé manquants sont refusés', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-imagerie-catalogue');
    final avant = m.collection('examensImagerie').toutes.length;
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvel examen'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(m.collection('examensImagerie').toutes.length, avant);
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'code', 'TST-IM1');
    await saisir(t, 'label', 'Examen test');
    await choisirM14(t, 'modalite', 'Radiographie');
    await saisir(t, 'voie', 'sus-pubienne');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('examensImagerie').toutes.first;
    expect([f['code'], f['label'], f['modalite'], f['voie']], ['TST-IM1', 'Examen test', 'radiographie', 'sus-pubienne']);
    expect(find.text('Examen créé.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await chercher(t, 'Examen test');
    expect(find.text('Radiographie'), findsWidgets);
  });

  casM14('onglet Variables : en-têtes de la maquette, création avec choix « a | b || » → liste sans vides ; l’édition RELIT les choix dans le champ texte', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-imagerie-catalogue');
    await onglet(t, 'variables');
    for (final h in obj(im['variables'])['entetes'] as List) {
      expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
    }
    final premiere = (obj(im['variables'])['lignes'] as List).cast<List>().first;
    expect(find.text('${premiere[1]}'), findsWidgets);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle variable'));
    await choisirM14(t, 'examen', 'Échographie pelvienne');
    await saisir(t, 'code', 'TST_V1');
    await saisir(t, 'libelle', 'Variable test');
    await saisir(t, 'optionsTexte', ' homogène | hétérogène ||  ');
    await saisir(t, 'rubrique', 'Résultat');
    await saisir(t, 'ordre', '7');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('variablesImagerie').toutes.first;
    expect(f['options'], ['homogène', 'hétérogène']);
    expect(f['ordre'], 7);
    expect(f['examen'], 'IMG-ECHO-PEL');
    expect(f['type'], 'liste');
    expect(f.containsKey('optionsTexte'), isFalse, reason: 'le champ de saisie ne survit pas à la transformation');
    expect(find.text('Variable créé.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await chercher(t, 'Variable test');
    await toucherM14(t, find.byTooltip('Modifier').first);
    final champ = t.widget<TextField>(find.descendant(of: find.byKey(const Key('kit:champ:optionsTexte')), matching: find.byType(TextField)));
    expect(champ.controller!.text, 'homogène|hétérogène');
  });

  casM14('fermer une variable : elle reste (jamais supprimée), l’état et le message le DISENT, la réouverture la rend ; la fermeture compte', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-imagerie-catalogue');
    await onglet(t, 'variables');
    final col = m.collection('variablesImagerie');
    final cible = col.actives.first;
    await chercher(t, '${cible['libelle']}');
    await toucherM14(t, find.byTooltip('Fermer la variable').first);
    expect(col.parId(cible['id'])!['actif'], false);
    expect(find.text('Variable fermée.'), findsOneWidget);
    expect(find.text('Les comptes rendus déjà rendus la conservent.'), findsOneWidget);
    expect(find.text('Fermée'), findsWidgets);
    expect(col.actives.length, col.toutes.length, reason: 'une variable fermée n’est pas archivée');
    await t.pump(const Duration(seconds: 10));
    await toucherM14(t, find.byTooltip('Rouvrir la variable').first);
    expect(col.parId(cible['id'])!['actif'], true);
    expect(find.text('Variable rouverte.'), findsOneWidget);
  });

  casM14('droits : en lecture seule, ni création, ni modification, ni fermeture (absentes, jamais grisées)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-imagerie-catalogue', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-imagerie-catalogue'));
    expect(find.widgetWithText(BoutonSigh, 'Nouvel examen'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    await onglet(t, 'variables');
    expect(find.widgetWithText(BoutonSigh, 'Nouvelle variable'), findsNothing);
    expect(find.byTooltip('Fermer la variable'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
  });
}
