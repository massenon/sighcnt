import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/auth/acc_registre_sessions.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-securite-utilisateurs : l'écran « Sécurité des utilisateurs » (retour de la Direction du 01/11/2026). Les règles (politique et ses bornes, comptes
/// bloqués, expiration, réinitialisation imposée) sont rejouées sur les vecteurs de la maquette par packages/domaine/test/sessions_securite_test.dart ;
/// ici, l'ÉCRAN et ses gestes dans le poste.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Finder kpi(String libelle, String valeur) => find.descendant(of: find.widgetWithText(KpiSigh, libelle), matching: find.text(valeur));

  Future<void> onglet(WidgetTester t, String libelle) => toucherM14(t, find.descendant(of: find.byKey(const Key('kit:onglets-barre')), matching: find.textContaining(libelle)));

  casM14('six indicateurs, quatre onglets, huit lignes de politique avec leur source et leur application', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-securite-utilisateurs');
    for (final e in ['Comptes actifs', 'Comptes bloqués', 'Mots de passe à renouveler', 'Double facteur manquant', 'Tentatives refusées', 'Sessions ouvertes']) {
      expect(find.text(e), findsOneWidget, reason: e);
    }
    expect(kpi('Comptes bloqués', '0'), findsOneWidget);
    for (final o in ['Politique', 'Comptes', 'Tentatives de connexion', 'Sessions']) {
      expect(find.descendant(of: find.byKey(const Key('kit:onglets-barre')), matching: find.textContaining(o)), findsWidgets, reason: o);
    }
    // Les valeurs de référence, et la politique née au magasin sans écriture au journal.
    final fiche = m.collection('politiqueSecurite').actives.single;
    expect({for (final k in secPolitiqueDefaut.keys) k: fiche[k]}, secPolitiqueDefaut);
    for (final p in secParametresPolitique) {
      expect(find.text(p.libelle), findsOneWidget, reason: p.cle);
      expect(find.text(p.source), findsWidgets, reason: p.cle);
    }
    expect(find.text('8 caractères'), findsOneWidget);
    expect(find.text('Historique des mots de passe interdits'), findsOneWidget);
    expect(find.textContaining('Proposition à valider'), findsOneWidget, reason: 'l\'historique n\'a aucune source : il le dit');
    expect(find.text('Composition du mot de passe'), findsOneWidget);
    expect(find.text('Double facteur obligatoire pour les rôles'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Modifier la politique'), findsOneWidget);
    expect(m.collection('audit').toutes.where((e) => '${e['reference']}'.startsWith('POL')), isEmpty, reason: 'l\'amorçage ne se journalise pas');
  });

  casM14('« Modifier la politique » : une valeur hors bornes est refusée en nommant la règle, une valeur valide est écrite, journalisée et appliquée au verrou', (t) async {
    final m = magasinM14();
    final reg = RegistreSessions.de(m);
    Duration? delai;
    reg.appliquerDelaiVerrou = (d) => delai = d;
    await ouvrirM14(t, m, 'm14-securite-utilisateurs');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Modifier la politique'));
    await saisir(t, 'longueurMin', '7');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.textContaining('Longueur minimale du mot de passe : une valeur entière entre 8 et 64 est attendue.'), findsOneWidget);
    expect(m.collection('politiqueSecurite').actives.single['longueurMin'], 8, reason: 'rien n\'est écrit');
    await saisir(t, 'longueurMin', '14');
    await saisir(t, 'inactiviteMin', '10');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Politique de sécurité enregistrée.'), findsOneWidget);
    final f = m.collection('politiqueSecurite').actives.single;
    expect(f['longueurMin'], 14);
    expect(f['inactiviteMin'], 10);
    expect(delai, const Duration(minutes: 10), reason: 'le délai d\'inactivité s\'applique aussitôt');
    final e = m.collection('audit').toutes.first;
    expect(e['action'], 'Modification');
    expect(e['module'], 'M14');
    expect(find.text('14 caractères'), findsOneWidget);
    expect(kpi('Sessions ouvertes', '12'), findsOneWidget);
    expect(find.text('Verrou à 10 min'), findsOneWidget);
  });

  casM14('bloquer un compte par le geste : motif obligatoire, blocage écrit et journalisé, indicateur à jour, puis débloquer', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-securite-utilisateurs');
    await onglet(t, 'Comptes');
    final cible = (m.collection('utilisateurs').actives..sort((a, b) => '${a['nomComplet']}'.compareTo('${b['nomComplet']}'))).first;
    expect(find.widgetWithText(BoutonSigh, 'Bloquer'), findsWidgets);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Bloquer').first);
    expect(find.text('Bloquer le compte de ${cible['nomComplet']}'), findsOneWidget);
    // Sans motif : le formulaire refuse (champ obligatoire).
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Bloquer le compte'));
    expect(m.collection('utilisateurs').parId(cible['id'])!['bloque'], isNot(true));
    await saisir(t, 'motif', 'Départ du poste, accès à retirer');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Bloquer le compte'));
    expect(find.text('Compte bloqué.'), findsOneWidget);
    final u = m.collection('utilisateurs').parId(cible['id'])!;
    expect(u['bloque'], true);
    expect(u['bloqueMotif'], 'Départ du poste, accès à retirer');
    expect(u['bloquePar'], isNotEmpty);
    expect(u['bloqueLe'], isNotNull);
    expect(kpi('Comptes bloqués', '1'), findsOneWidget);
    expect(m.collection('audit').toutes.first['action'], 'Modification');
    // Débloquer : confirmation, puis le compte retrouve l'accès, ses échecs repartent de zéro.
    expect(find.widgetWithText(BoutonSigh, 'Débloquer'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Débloquer'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Débloquer').last);
    final apres = m.collection('utilisateurs').parId(cible['id'])!;
    expect(apres['bloque'], false);
    expect(apres['echecs'], 0);
    expect(apres['debloquePar'], isNotEmpty);
    expect(kpi('Comptes bloqués', '0'), findsOneWidget);
    expect(m.collection('utilisateurs').actives.length, 48, reason: 'rien n\'est supprimé');
  });

  casM14('imposer la réinitialisation : l\'obligation est posée (auteur, date), aucun secret ne passe, le geste ne se répète pas', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-securite-utilisateurs');
    await onglet(t, 'Comptes');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imposer la réinitialisation').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imposer la réinitialisation').last);
    final imposes = m.collection('utilisateurs').actives.where((u) => u['doitChangerMotDePasse'] == true && u['reinitialisationImposeePar'] != null).toList();
    expect(imposes.length, 1);
    expect(imposes.single['reinitialisationImposeeLe'], isNotNull);
    expect(imposes.single.keys.where((k) => k.toLowerCase() == 'motdepasse' || k.toLowerCase() == 'secret'), isEmpty);
    expect(kpi('Mots de passe à renouveler', '1'), findsOneWidget);
    // Le même geste, redemandé, est refusé en le disant (la règle du domaine).
    final r = secImposerReinitialisation(imposes.single, acteur: const SecActeurCompte(identifiant: 'a', nom: 'A'), maintenant: aujourdhui);
    expect(r.refus!.code, 'DEJA_IMPOSEE');
  });

  casM14('« Clôturer les sessions » d\'un compte : toutes ses sessions ouvertes passent à clôturée, le registre les garde', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-securite-utilisateurs');
    final reg = RegistreSessions.de(m);
    final visee = reg.fiches.firstWhere((f) => f['source'] == 'demonstration' && f['etat'] == 'active');
    await onglet(t, 'Comptes');
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')), '${visee['identifiant']}');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(BoutonSigh, 'Clôturer les sessions'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer les sessions'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer les sessions').last);
    expect(reg.fiches.where((f) => f['identifiant'] == visee['identifiant'] && secSessionOuverte(f)), isEmpty);
    expect(reg.fiche('${visee['id']}')!['etat'], 'cloturee');
    expect(reg.fiches.length, 12, reason: 'aucune fiche supprimée (RG-14)');
  });

  casM14('droits : administrateur seul au manifeste ; en lecture seule, toutes les commandes d\'écriture sont ABSENTES', (t) async {
    for (final r in ['direction', 'da', 'caissier', 'medecin', 'dm']) {
      expect(donneesNav.matrice.peutVoir(r, 'm14-securite-utilisateurs'), isFalse, reason: r);
    }
    expect(donneesNav.matrice.peutVoir('admin', 'm14-securite-utilisateurs'), isTrue);
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-securite-utilisateurs', donnees: donneesLectureSeule('admin', 'm14-securite-utilisateurs'));
    expect(find.text('Comptes actifs'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Modifier la politique'), findsNothing);
    await onglet(t, 'Comptes');
    expect(find.widgetWithText(BoutonSigh, 'Bloquer'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Débloquer'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Imposer la réinitialisation'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Clôturer les sessions'), findsNothing);
  });
}
