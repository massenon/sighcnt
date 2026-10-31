import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-utilisateurs : les règles sont rejouées sur les vecteurs de la maquette (packages/domaine/test/securite_test.dart) ; ici, l'ÉCRAN — ce qui est
/// saisi, refusé, écrit, journalisé, et ce qui ne l'est JAMAIS (le mot de passe).
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Future<void> remplirCompte(WidgetTester t,
      {String identifiant = 'v.test1',
      String? role = 'Médecin',
      String mdp = 'abcdefgh',
      String confirmation = 'abcdefgh'}) async {
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'identifiant', identifiant);
    if (role != null) await choisirM14(t, 'role', role);
    await saisir(t, 'motDePasse', mdp);
    await saisir(t, 'motDePasseConfirmation', confirmation);
  }

  casM14('ouverture : 48 comptes du jeu, quatre indicateurs, onglets, aucune colonne de secret', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-utilisateurs');
    expect(find.text('Comptes utilisateurs'), findsOneWidget);
    expect(find.text('Avec double facteur'), findsOneWidget);
    expect(find.text('Tous les comptes'), findsOneWidget);
    expect(m.collection('utilisateurs').actives.length, 48);
    for (final entete in ['Identifiant', 'Utilisateur', 'Rôle', 'Service', 'État', 'Double facteur', 'Dernier accès', 'Échecs']) {
      expect(find.text(entete.toUpperCase()), findsWidgets, reason: entete);
    }
    expect(find.textContaining('mot de passe', findRichText: true), findsNothing);
    // Aucune fiche du jeu ne porte de secret.
    for (final u in m.collection('utilisateurs').toutes) {
      expect(u.keys.where((k) => k.toLowerCase().contains('motdepasse') && k != 'motDePasseDefiniLe' && k != 'motDePasseDefiniPar'), isEmpty);
    }
  });

  casM14('création : le compte est écrit SANS son mot de passe, avec la date et l\'auteur de sa définition', (t) async {
    final m = magasinM14();
        await ouvrirM14(t, m, 'm14-utilisateurs');
    await remplirCompte(t);
    // Le champ est masqué.
    final champs = t.widgetList<TextField>(find.descendant(
        of: find.byKey(const Key('kit:champ:motDePasse')), matching: find.byType(TextField)));
    expect(champs.single.obscureText, isTrue);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final c = m.collection('utilisateurs').actives.first;
    expect(c['identifiant'], 'v.test1');
    expect(c['role'], 'medecin');
    expect(c['actif'], isTrue);
    expect(c['doitChangerMotDePasse'], isTrue);
    expect(c['motDePasseDefiniPar'], 'Administrateur système');
    expect(c['motDePasseDefiniLe'], isNotNull);
    expect(c['dernierAcces'], '2026-10-30');
    expect(c['echecs'], 0);
    expect(c.containsKey('motDePasse'), isFalse);
    expect(c.containsKey('motDePasseConfirmation'), isFalse);
    expect('$c'.contains('abcdefgh'), isFalse, reason: 'le secret ne figure nulle part dans la fiche');
    // RG-12 : la création est journalisée, et le journal ne contient pas non plus le secret.
    final journal = m.collection('audit').toutes.where((a) => a['module'] == 'M14');
    expect(journal.any((a) => a['action'] == 'Création'), isTrue);
    expect('${m.collection('audit').toutes}'.contains('abcdefgh'), isFalse);
    expect(find.text('Nouveau compte créé.'), findsOneWidget);
    // Annuler retire le compte (archivage, RG-14).
    await toucherM14(t, find.text('Annuler').last);
    expect(m.collection('utilisateurs').actives.length, 48);
    expect(m.collection('utilisateurs').archivees.any((u) => u['identifiant'] == 'v.test1'), isTrue);
  });

  casM14('un rôle à privilèges impose le double facteur, même case décochée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-utilisateurs');
    await remplirCompte(t, identifiant: 'v.dm', role: 'Directeur Médical');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(m.collection('utilisateurs').actives.first['mfa'], isTrue);
  });

  casM14('refus nommés : identifiant partagé, mot de passe court, confirmation différente — rien n\'est écrit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-utilisateurs');
    await remplirCompte(t, identifiant: 'admin.systeme', role: null);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Cet identifiant est déjà attribué : aucun compte ne peut être partagé.'), findsOneWidget);
    await saisir(t, 'identifiant', 'v.test2');
    await saisir(t, 'motDePasse', 'abcdefg');
    await saisir(t, 'motDePasseConfirmation', 'abcdefg');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le mot de passe doit compter au moins huit caractères.'), findsOneWidget);
    await saisir(t, 'motDePasse', 'abcdefgh');
    await saisir(t, 'motDePasseConfirmation', 'abcdefgX');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Les deux mots de passe saisis ne correspondent pas.'), findsOneWidget);
    expect(m.collection('utilisateurs').actives.length, 48);
    // Un identifiant vide : la validation du formulaire parle avant le contrôle métier.
    await saisir(t, 'identifiant', '');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(m.collection('utilisateurs').actives.length, 48);
  });

  casM14('modification : pas de champ de mot de passe, dernier accès et échecs CONSERVÉS (E591)', (t) async {
    final m = magasinM14();
    final cible = m.collection('utilisateurs').actives.firstWhere((u) => u['identifiant'] == 's.bassongui');
    expect(cible['echecs'], 2);
    final dernier = cible['dernierAcces'];
    await ouvrirM14(t, m, 'm14-utilisateurs');
    await t.enterText(find.byType(TextField).first, 's.bassongui');
    await t.pump(const Duration(milliseconds: 300));
    await toucherM14(t, find.byTooltip('Modifier').first);
    expect(find.byKey(const Key('kit:champ:motDePasse')), findsNothing);
    expect(find.byKey(const Key('kit:champ:motDePasseConfirmation')), findsNothing);
    await choisirM14(t, 'service', 'Comptabilité');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final apres = m.collection('utilisateurs').parId(cible['id'])!;
    expect(apres['service'], 'Comptabilité');
    expect(apres['echecs'], 2);
    expect(apres['dernierAcces'], dernier);
    expect(apres['nomComplet'], cible['nomComplet']);
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
  });

  casM14('archivage : le motif est exigé, journalisé ; le compte passe en « Archivés », rien n\'est supprimé', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-utilisateurs');
    await t.enterText(find.byType(TextField).first, 'admin.systeme');
    await t.pump(const Duration(milliseconds: 300));
    await toucherM14(t, find.byTooltip('Archiver').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);
    expect(m.collection('utilisateurs').archivees, isEmpty);
    await t.enterText(find.byType(TextField).last, 'Poste supprimé');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
    expect(m.collection('utilisateurs').archivees.single['identifiant'], 'admin.systeme');
    expect(m.collection('utilisateurs').toutes.length, 48, reason: 'RG-14 : rien n\'est supprimé');
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Motif d’archivage' && '${a['apres']}'.contains('Poste supprimé')), isTrue);
  });

  casM14('la fiche : périmètre d\'accès du rôle, et la fiche imprimable', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-utilisateurs');
    await t.enterText(find.byType(TextField).first, 's.bassongui');
    await t.pump(const Duration(milliseconds: 300));
    await toucherM14(t, find.byTooltip('Consulter').first);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Périmètre d’accès (RBAC)'), findsOneWidget);
    expect(find.textContaining('module(s) accessible(s) avec ce rôle.'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer'));
    expect(find.text('Fiche de compte utilisateur'), findsWidgets);
    expect(find.textContaining('toute action réalisée sous son compte lui est imputable'), findsOneWidget);
    expect(find.text('Lu et approuvé'), findsOneWidget);
  });

  casM14('lecture seule : « Nouveau », « Modifier » et « Archiver » sont ABSENTS (jamais grisés), le bandeau le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-utilisateurs',
        role: 'da', donnees: donneesLectureSeule('da', 'm14-utilisateurs'));
    expect(find.text('Comptes utilisateurs'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.byTooltip('Consulter'), findsWidgets);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
  });
}
