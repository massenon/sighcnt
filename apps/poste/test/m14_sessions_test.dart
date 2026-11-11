import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/auth/acc_registre_sessions.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-sessions : « Clôturer » CHANGE LE STATUT de la session (retour de la Direction du 01/11/2026). Les règles (graine 3413, refus nommés, patch de clôture)
/// sont rejouées sur les vecteurs de la maquette par packages/domaine/test/sessions_securite_test.dart ; ici, le GESTE complet dans l'écran.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Finder kpi(String libelle, String valeur) => find.descendant(of: find.widgetWithText(KpiSigh, libelle), matching: find.text(valeur));

  casM14('douze sessions de démonstration tirées des comptes actifs, cinq indicateurs, en-têtes de la maquette', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sessions');
    final fiches = RegistreSessions.de(m).fiches;
    expect(fiches.length, 12);
    expect(fiches.every((f) => f['source'] == 'demonstration'), isTrue);
    final k = secKpisSessions(secLignesSessions(fiches));
    for (final e in ['Sessions ouvertes', 'Postes distincts', 'Verrouillées pour inactivité', 'Clôturées', 'Délai de verrouillage']) {
      expect(find.text(e), findsOneWidget, reason: e);
    }
    expect(kpi('Sessions ouvertes', '${k.ouvertes}'), findsOneWidget);
    expect(kpi('Clôturées', '0'), findsOneWidget);
    expect(find.text('15 min'), findsNWidgets(2), reason: 'l’indicateur et la carte du poste de secours (poste ordinaire)');
    for (final e in ['IDENTIFIANT', 'UTILISATEUR', 'RÔLE', 'POSTE', 'ADRESSE RÉSEAU', 'OUVERTURE', 'INACTIVITÉ', 'ÉTAT', 'CLÔTURE']) {
      expect(find.text(e), findsOneWidget, reason: e);
    }
    // Suspendue à partir de quinze minutes d'inactivité, jamais avant.
    expect(fiches.every((f) => (f['etat'] == 'suspendue') == ((f['inactivite'] as int) >= 15)), isTrue);
    expect(find.textContaining('verrouillage automatique de l’écran'), findsOneWidget);
  });

  casM14('« Clôturer » : confirmation, puis le STATUT change (date, heure, auteur), le journal, les indicateurs et la ligne suivent', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sessions');
    final reg = RegistreSessions.de(m);
    final premiere = secLignesSessions(reg.fiches).first;
    final avant = m.collection('audit').toutes.length;
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNWidgets(12));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer').first);
    final conf = secConfirmationCloture(nomComplet: '${premiere['nomComplet']}', poste: '${premiere['poste']}', propre: false);
    expect(find.text(conf.titre), findsOneWidget);
    expect(find.text(conf.message), findsOneWidget);
    // Annuler la confirmation n'écrit rien.
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler'));
    expect(m.collection('audit').toutes.length, avant);
    expect(reg.fiche('${premiere['id']}')!['etat'], isNot('cloturee'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, conf.libelleOk));
    expect(find.text('Session clôturée.'), findsOneWidget);
    expect(find.text('${premiere['nomComplet']} (${premiere['poste']})'), findsOneWidget);
    final f = reg.fiche('${premiere['id']}')!;
    expect(f['etat'], 'cloturee', reason: 'le statut change');
    expect(f['clotureLe'], isNotNull);
    expect(f['cloturePar'], isNotEmpty);
    expect(f['cloturePropre'], false);
    expect(f['statut'], 'actif', reason: 'rien n’est archivé ni supprimé (RG-14)');
    expect(m.collection('sessionsUtilisateur').toutes.length, 12, reason: 'aucune fiche supprimée');
    // RG-12 : une entrée de journal, au nom de la collection du registre, avec l'état d'avant et d'après.
    expect(m.collection('audit').toutes.length, avant + 1);
    final e = m.collection('audit').toutes.first;
    expect(e['action'], 'Modification');
    expect(e['module'], 'M14');
    expect('${e['reference']}', '${premiere['id']}');
    expect((e['avant'] as Map)['etat'], isNot('cloturee'));
    expect((e['apres'] as Map)['etat'], 'cloturee');
    // Les indicateurs et la ligne suivent ; la session clôturée n'offre plus « Clôturer ».
    expect(kpi('Clôturées', '1'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNWidgets(11));
    expect(find.text('Clôturée'), findsWidgets);
    // Les comptes ne bougent pas : clôturer une session ne désactive personne.
    expect(m.collection('utilisateurs').actives.length, 48);
  });

  casM14('le filtre « État » : Clôturées, Ouvertes', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sessions');
    final reg = RegistreSessions.de(m);
    final id = '${secLignesSessions(reg.fiches).first['id']}';
    reg.cloturer(id,
        acteur: const SecActeurSession(role: 'admin', identifiant: 'admin', nom: 'Administrateur'), droitEditer: true, maintenant: aujourdhui);
    await t.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNWidgets(11));
    // Le filtre « État » est un menu de la barre du tableau : on choisit l'entrée comme le fait le geste (la sélection du menu, sans passer par son animation).
    Future<void> choisirEtat(String valeur) async {
      t.widget<PopupMenuButton<String>>(find.ancestor(of: find.byTooltip('État'), matching: find.byType(PopupMenuButton<String>)).first).onSelected!(valeur);
      await t.pump(const Duration(milliseconds: 300));
    }

    // « Clôturées » : seule la session clôturée reste, et elle n'offre plus « Clôturer ».
    await choisirEtat('cloturee');
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNothing);
    expect(find.text('Clôturée'), findsWidgets);
    // « Ouvertes » : les onze autres ; « Suspendues » : celles dont l'inactivité atteint quinze minutes.
    await choisirEtat('ouverte');
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNWidgets(11));
    await choisirEtat('suspendue');
    final suspendues = reg.fiches.where((f) => f['etat'] == 'suspendue').length;
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNWidgets(suspendues));
  });

  casM14('sa PROPRE session : la confirmation le DIT, la clôture déconnecte aussitôt le poste', (t) async {
    final m = magasinM14();
    final reg = RegistreSessions.de(m);
    var deconnecte = false;
    // La session réelle de l'administrateur, ouverte plus tard que toutes celles de la démonstration : elle arrive en tête du tableau.
    reg.ouvrir(identifiant: 'admin', nomComplet: 'Administrateur système', role: 'admin', poste: 'POSTE-TEST', maintenant: aujourdhui.add(const Duration(days: 1)));
    reg.surCloturePropre = () => deconnecte = true;
    await ouvrirM14(t, m, 'm14-sessions');
    final propre = reg.sessionCourante!;
    // Sans confirmation explicite, la règle refuse en nommant la session propre.
    final refus = secCloturerSession(
        fiche: reg.fiche(propre),
        acteur: SecActeurSession(role: 'admin', identifiant: 'admin', nom: 'Administrateur', sessionId: propre),
        droitEditer: true,
        maintenant: aujourdhui);
    expect(refus.refus!.code, 'SESSION_PROPRE');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer').first);
    expect(find.text('Clôturer VOTRE session ?'), findsOneWidget);
    expect(find.textContaining('Il s’agit de votre propre session'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler'));
    expect(reg.fiche(propre)!['etat'], 'active');
    expect(deconnecte, isFalse);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Clôturer ma session'));
    expect(reg.fiche(propre)!['etat'], 'cloturee');
    expect(reg.fiche(propre)!['cloturePropre'], true);
    expect(deconnecte, isTrue, reason: 'le poste retombe sur la connexion');
  });

  casM14('une session clôturée ne se rouvre ni ne se reclôture : refus nommé, rien n\'est réécrit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sessions');
    final reg = RegistreSessions.de(m);
    final id = '${secLignesSessions(reg.fiches).first['id']}';
    const acteur = SecActeurSession(role: 'admin', identifiant: 'admin', nom: 'Administrateur');
    expect(reg.cloturer(id, acteur: acteur, droitEditer: true, maintenant: aujourdhui).ok, isTrue);
    final cloturee = Map<String, Object?>.of(reg.fiche(id)!);
    final r = reg.cloturer(id, acteur: acteur, droitEditer: true, maintenant: aujourdhui.add(const Duration(hours: 1)));
    expect(r.ok, isFalse);
    expect(r.refus!.code, 'DEJA_CLOTUREE');
    expect(r.refus!.motif, contains('ne se rouvre pas'));
    expect(reg.fiche(id)!['clotureLe'], cloturee['clotureLe'], reason: 'la date de clôture ne bouge pas');
    reg.changerEtat(id, 'active', aujourdhui);
    expect(reg.fiche(id)!['etat'], 'cloturee', reason: 'le verrou ne reprend pas une session clôturée');
  });

  casM14('lecture seule : « Clôturer » est ABSENTE (jamais grisée)', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-sessions', role: 'da', donnees: donneesLectureSeule('da', 'm14-sessions'));
    expect(find.text('Sessions ouvertes'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Clôturer'), findsNothing);
  });
}
