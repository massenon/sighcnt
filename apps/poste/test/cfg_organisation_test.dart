import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfa_commun.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/cfg.json').readAsStringSync()));
String s(Object? x) => '$x'.replaceAll(RegExp(r'[\s  ]'), '');

/// cfg-organisation : les règles sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cfa_regles_test.dart) ; ici, l'ÉCRAN — les trois
/// onglets, les saisies, l'archivage, la correspondance poste → rôle → modules (mesurée sur l'écran réel) et ce qui est ABSENT sans le droit.
void main() {
  setUpAll(() async {
    await chargerPolices();
    cfaPoserNavigation(donneesNav);
  });
  tearDown(ToastsSigh.viderPourTests);
  final o = obj(v['organisation']);

  casM14('ouverture : indicateurs de la maquette, trois onglets, en-têtes, 14 secteurs dans l’ordre de la note', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-organisation');
    for (final k in (o['kpis'] as List).cast<List>()) {
      expect(find.text('${k[0]}'), findsOneWidget, reason: '${k[0]}');
      expect(find.text('${k[1]}'), findsWidgets, reason: '${k[0]} = ${k[1]}');
    }
    expect(find.text('Secteurs (NS 145)'), findsOneWidget);
    expect(find.text('Organigramme'), findsOneWidget);
    expect(find.text('Poste → rôle → accès'), findsOneWidget);
    for (final h in obj(o['secteurs'])['entetes'] as List) {
      expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
    }
    final lignes = (obj(o['secteurs'])['lignes'] as List).cast<List>();
    for (final l in lignes.take(6)) {
      expect(find.text('${l[1]}'), findsWidgets, reason: '${l[1]}');
    }
    expect(find.textContaining('NS 145/08/DA/CNT/2026'), findsWidgets);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer la répartition'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsOneWidget);
  });

  casM14('« Imprimer la répartition » : l’état de la maquette (cartouche, signataire)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la répartition'));
    final etat = obj(o['impressionRepartition']);
    expect(find.text('${etat['titre']}'), findsWidgets);
    for (final x in (etat['cartouche'] as List).cast<List>().take(3)) {
      expect(find.textContaining('${x[0]}'), findsWidgets, reason: '${x[0]}');
    }
    expect(find.textContaining('TAKI Alimatou épse BASSONGUI'), findsWidgets);
  });

  casM14('création d’un secteur sans code : trois lettres, rang 15 ; avec code : le code saisi est GARDÉ', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'libelle', 'Zone Test Alpha');
    await choisirM14(t, 'role', 'Infirmier / Sage-femme');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    var f = m.collection('secteurs').toutes.first;
    expect(f['code'], 'ZON');
    expect(f['ordre'], 15);
    expect(f['role'], 'infirmier');
    expect(f['source'], 'Décision de la Direction');
    expect(find.text('Secteur créé.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'libelle', 'Bloc Annexe');
    await saisir(t, 'code', 'bka');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    f = m.collection('secteurs').toutes.first;
    expect(f['code'], 'bka');
    expect(f['ordre'], 16);
  });

  casM14('un secteur sans libellé est refusé en le nommant ; rien n’est écrit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(m.collection('secteurs').toutes.length, 14);
  });

  casM14('archivage d’un secteur : motif exigé, la fiche reste (RG-14), le compteur baisse', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.byTooltip('Archiver').first);
    await t.enterText(find.byType(TextField).last, 'Fusion de secteurs');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('secteurs').actives.length, 13);
    expect(m.collection('secteurs').toutes.length, 14);
    expect(find.text('13'), findsWidgets);
  });

  casM14('onglet Organigramme : l’arbre, le tableau des postes, la création d’un poste SANS rattachement devient un sommet', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.text('Organigramme').first);
    expect(find.text('Organigramme de la Clinique NASSIERA TOO'), findsOneWidget);
    expect(find.text('Postes — création, réaffectation et archivage'), findsOneWidget);
    expect(find.text('(01)'), findsWidgets);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer l’organigramme'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'poste', 'Poste Test Sommet');
    await saisir(t, 'effectif', '2');
    await choisirM14(t, 'role', 'Infirmier / Sage-femme');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('postes').toutes.first;
    expect(f['poste'], 'Poste Test Sommet');
    expect(f['parentId'], isNull);
    expect(f['effectif'], 2);
    expect(find.text('Poste créé.'), findsOneWidget);
    // Le poste neuf est un sommet : l'effectif porté augmente de 2 (44 → 46).
    expect(find.text('46'), findsWidgets);
  });

  casM14('onglet Poste → rôle → accès : calculé, lecture seule, et IDENTIQUE à ce que l’écran réel de la maquette affiche pour chaque poste', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.text('Poste → rôle → accès').first);
    expect(find.textContaining('État calculé'), findsOneWidget);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    final lignes = (obj(o['roles'])['lignes'] as List).cast<List>();
    final postes = m.collection('postes').actives;
    expect(lignes.length, postes.length);
    for (final l in lignes) {
      final p = postes.firstWhere((x) => x['poste'] == l[0]);
      expect(cfaModulesDuRole(m, donneesNav, '${p['role']}').join(), s(l[4]).replaceAll(' ', ''), reason: '${l[0]} (${p['role']})');
    }
    // Les badges du premier poste sont à l'écran.
    final premier = cfaModulesDuRole(m, donneesNav, '${postes.first['role']}');
    for (final code in premier.toSet()) {
      expect(find.widgetWithText(BadgeSigh, code), findsWidgets, reason: code);
    }
  });

  casM14('droits : en lecture seule, aucune commande d’écriture (absentes, jamais grisées) et le bandeau le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-organisation', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-organisation'));
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    // La consultation et l'impression restent ouvertes.
    expect(find.widgetWithText(BoutonSigh, 'Imprimer la répartition'), findsOneWidget);
  });
}
