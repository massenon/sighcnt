import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfb_perimetre.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-compte : les règles (refus du mot de passe, deux facteurs d'office) sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/cfb_regles_test.dart) ; ici, l'ÉCRAN — ce qu'il écrit, ce qu'il journalise (jamais le secret), et le PÉRIMÈTRE D'ACCÈS de chacun
/// des rôles, comparé à celui que la maquette affiche.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  setUp(() => cfbPoserRangeesRoles(cfbRangeesRoles(File('assets/donnees/manifeste.json').readAsStringSync())));

  casM14('ouverture : identité de l’agent connecté, identifiant en lecture seule, poste, initiales, compte actif', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-compte');
    for (final k in ['Informations personnelles', 'Sécurité du compte', 'Périmètre d’accès', 'Activité récente', 'Compte actif', 'Matrice RBAC']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    for (final k in ['Nom et prénoms *', 'Identifiant de connexion', 'Poste', 'Téléphone', 'Adresse électronique', 'Mot de passe actuel *', 'Nouveau mot de passe *']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(find.text('admin.systeme'), findsOneWidget);
    expect(find.text('AS'), findsOneWidget, reason: 'initiales de « Administrateur système »');
    // l’identifiant et le poste ne se saisissent pas : aucun champ de saisie ne porte ces libellés
    expect(find.byKey(const Key('kit:champ:identifiant')), findsNothing);
    expect(find.byKey(const Key('kit:champ:poste')), findsNothing);
  });

  casM14('périmètre d’accès : pour CHAQUE rôle, les modules affichés sont ceux de la maquette (une pastille par rangée du ruban)', (t) async {
    final v = (jsonDecode(File('../../packages/domaine/test/vecteurs/cfb.json').readAsStringSync()) as Map).cast<String, Object?>();
    final parRole = ((v['compte'] as Map)['parRole'] as Map).cast<String, Object?>();
    final m = magasinM14();
    final rangees = cfbRangeesRoles(File('assets/donnees/manifeste.json').readAsStringSync());
    cfbPoserRangeesRoles(rangees);
    for (final role in parRole.keys) {
      expect(cfbPerimetre(m, role, rangees), ((parRole[role] as Map)['perimetre'] as List).cast<String>(), reason: role);
    }
    await ouvrirM14(t, m, 'cfg-compte');
    expect(find.text('MERE'), findsNWidgets(5));
    expect(find.text('DASH'), findsOneWidget);
  });

  casM14('enregistrer : le nom est changé pour la session, journalisé avec son ancienne valeur, annoncé ; vide, rien ne part', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-compte');
    await saisir(t, 'nom', '');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Informations enregistrées.'), findsNothing);
    expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
    await saisir(t, 'nom', 'NOUVEAU Nom');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Informations enregistrées.'), findsOneWidget);
    expect(m.utilisateur, 'NOUVEAU Nom');
    final j = m.collection('audit').toutes.firstWhere((a) => a['entite'] == 'Compte');
    expect([j['action'], j['module'], j['reference']], ['Modification', 'CFG', 'admin.systeme']);
    expect(j['avant'], {'nom': 'Administrateur système'});
    expect(j['apres'], {'nom': 'NOUVEAU Nom'});
    expect(find.text('NN'), findsOneWidget);
  });

  casM14('mot de passe : formulaire incomplet, confirmation divergente et mot de passe trop court sont REFUSÉS en le disant ; rien n’est journalisé', (t) async {
    final m = magasinM14();
    final avant = m.collection('audit').toutes.length;
    await ouvrirM14(t, m, 'cfg-compte');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Modifier le mot de passe'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    await saisir(t, 'actuel', 'ancien');
    await saisir(t, 'nouveau', 'MotDePasse#2026X');
    await saisir(t, 'confirmation', 'MotDePasse#2027X');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Modifier le mot de passe'));
    expect(find.text('Les deux mots de passe ne correspondent pas.'), findsOneWidget);
    await saisir(t, 'nouveau', 'Court#1');
    await saisir(t, 'confirmation', 'Court#1');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Modifier le mot de passe'));
    expect(find.text('Le mot de passe doit comporter au moins 12 caractères.'), findsOneWidget);
    expect(m.collection('audit').toutes.length, avant);
  });

  casM14('mot de passe valide : le GESTE est journalisé (module M14), le secret n’apparaît nulle part — ni au journal ni dans les champs', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-compte');
    await saisir(t, 'actuel', 'ancien');
    await saisir(t, 'nouveau', 'MotDePasse#2026X');
    await saisir(t, 'confirmation', 'MotDePasse#2026X');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Modifier le mot de passe'));
    expect(find.text('Mot de passe modifié.'), findsOneWidget);
    final j = m.collection('audit').toutes.firstWhere((a) => a['entite'] == 'Utilisateur');
    expect([j['action'], j['module'], j['reference']], ['Modification', 'M14', 'admin.systeme']);
    expect(j['apres'], {'motDePasse': 'modifié'});
    expect(jsonEncode(m.collection('audit').toutes).contains('MotDePasse#2026X'), isFalse);
    expect(jsonEncode(m.collection('audit').toutes).contains('ancien'), isFalse);
    final champ = t.widget<TextField>(find.descendant(of: find.byKey(const Key('kit:champ:nouveau')), matching: find.byType(TextField)));
    expect(champ.controller?.text ?? '', isEmpty, reason: 'les champs sont vidés : le secret ne reste pas à l’écran');
  });

  casM14('activité récente : les gestes de l’agent connecté, les plus récents d’abord', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-compte');
    await saisir(t, 'nom', 'Administrateur système');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Modification — Compte'), findsOneWidget);
    expect(find.text('Module CFG'), findsWidgets);
    expect(find.text('à l’instant'), findsWidgets);
  });
}
