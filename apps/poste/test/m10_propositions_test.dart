import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'rhb_aide.dart';

/// m10-propositions-planning (lot L6, Direction, 09/11/2026) : l'agent PROPOSE, le surveillant VALIDE. Les règles (contrôle de repos, refus nommés, visibilité par
/// agent) sont rejouées sur les vecteurs de la maquette par `packages/domaine/test/planning_rh_test.dart` et `test/planning_rh_poste_test.dart` ; ici l'ÉCRAN monté
/// sur le magasin du poste, les gestes accomplis, et ce qui est écrit.
const _jour = '2026-08-16';

/// Le magasin de test : le jeu du poste ET un agent du personnel qui porte le nom de l'agent de démonstration du rôle [role] (l'écran retrouve l'agent par le nom de la session).
Magasin _magasin(String role) {
  final m = magasinRhb();
  m.collection('personnel').inserer({
    'id': 'EMPPROP', 'statut': 'actif', 'nomComplet': _nom(role), 'matricule': '777', 'fonction': 'medecin', 'service': 'Médecine générale', 'poste': 'Médecin',
  }, prefixe: 'EMP');
  return m;
}

/// Le nom de l'agent de démonstration d'un rôle : le libellé du rôle à la matrice (c'est ce que la coque pose comme acteur sans session nominative).
String _nom(String role) => agentDemonstration(role, nom: donneesNav.matrice.libelle(role)).nom;

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  ControleurFormulaire ctl(WidgetTester t) => t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;

  group('m10-propositions-planning', () {
    casM14('le surveillant voit TOUTES les propositions, tranche, et n\'a pas de commande « Proposer » (il n\'est pas un agent du personnel)', (t) async {
      final m = magasinRhb();
      m.collection('propositionsPlanning').inserer({
        'type': 'ajout', 'employeId': 'EMP01', 'employe': 'BASSONGUI Chabi Séko', 'date': '2026-08-30', 'typeVacation': 'garde', 'motif': 'Je prends cette garde', 'etat': 'proposee',
        'proposeeLe': _jour, 'statut': 'actif',
      }, prefixe: 'PPL');
      await ouvrirM14(t, m, 'm10-propositions-planning', horloge: auj16, role: 'surveillant');
      expect(find.text('Propositions des agents'), findsOneWidget);
      expect(find.text('Réglages du planning et des présences'), findsOneWidget);
      expect([kpis(t)['À valider'], kpis(t)['Validées'], kpis(t)['Refusées']], ['1', '0', '0']);
      for (final c in ['Proposée le', 'Agent', 'Demande', 'Vacation visée', 'Proposition', 'Motif', 'État']) {
        expect(texteAffiche(t).contains(sansEspaces(c).toLowerCase()), isTrue, reason: 'en-tête $c');
      }
      expect(find.text('Ajouter une vacation'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Proposer une modification'), findsNothing);
      expect(find.text('Votre compte ne correspond à aucun agent du personnel : aucune proposition ne peut être rattachée. Se connecter avec le compte nominatif de l’agent.'), findsNothing);
      expect(find.byTooltip('Valider cette proposition'), findsOneWidget);
      expect(find.byTooltip('Refuser cette proposition'), findsOneWidget);
    });

    casM14('un compte sans agent du personnel : la note le dit, aucune commande de proposition (AGENT_NON_IDENTIFIE)', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-propositions-planning', horloge: auj16, role: 'medecin');
      expect(find.text('Mes propositions'), findsOneWidget);
      expect(find.text('Votre compte ne correspond à aucun agent du personnel : aucune proposition ne peut être rattachée. Se connecter avec le compte nominatif de l’agent.'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Proposer une modification'), findsNothing);
      expect(find.byTooltip('Valider cette proposition'), findsNothing);
    });

    casM14('l\'agent propose : le planning ne bouge pas, la proposition naît « à valider », il peut la retirer ; chacun ne voit que les siennes (RG-13)', (t) async {
      final m = _magasin('medecin');
      m.collection('propositionsPlanning').inserer({
        'type': 'ajout', 'employeId': 'EMP01', 'employe': 'BASSONGUI Chabi Séko', 'date': '2026-08-30', 'typeVacation': 'garde', 'motif': 'Celle d\'un autre', 'etat': 'proposee',
        'proposeeLe': _jour, 'statut': 'actif',
      }, prefixe: 'PPL');
      await ouvrirM14(t, m, 'm10-propositions-planning', horloge: auj16, role: 'medecin');
      expect(find.text('Celle d\'un autre'), findsNothing, reason: 'une proposition d\'autrui ne se lit pas');
      final planning = m.collection('planning').toutes.length;
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Proposer une modification'));
      expect(find.text('Proposer une modification de mon planning'), findsOneWidget);
      expect(find.text('Votre proposition ne change rien tant que le surveillant ne l’a pas validée.'), findsOneWidget);
      ctl(t).poser('date', '2026-09-20');
      ctl(t).poser('typeVacation', 'permanence');
      ctl(t).poser('motif', 'Je souhaite cette permanence');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Transmettre la proposition'));
      expect(find.text('Proposition transmise au surveillant.'), findsOneWidget);
      final p = m.collection('propositionsPlanning').toutes.first;
      expect([p['etat'], p['type'], p['date'], p['typeVacation'], p['employeId'], p['motif']], ['proposee', 'ajout', '2026-09-20', 'permanence', 'EMPPROP', 'Je souhaite cette permanence']);
      expect(m.collection('planning').toutes.length, planning, reason: 'une proposition ne change JAMAIS le planning validé');
      expect(find.text('Je souhaite cette permanence'), findsOneWidget);
      expect(kpis(t)['À valider'], '1');
      // Retirer sa proposition : elle devient « Retirée », jamais supprimée.
      ToastsSigh.viderPourTests();
      await t.pump(const Duration(milliseconds: 300));
      await toucherM14(t, find.byTooltip('Retirer ma proposition'));
      expect(m.collection('propositionsPlanning').parId(p['id'])!['etat'], 'annulee');
      expect(find.text('Proposition retirée.'), findsOneWidget);
      expect(find.text('Retirée'), findsOneWidget);
    });

    casM14('une proposition qui entamerait le repos est REFUSÉE tout de suite, nommée, et rien n\'est enregistré', (t) async {
      final m = _magasin('medecin');
      m.collection('planning').inserer({'employeId': 'EMPPROP', 'employe': _nom('medecin'), 'date': '2026-09-20', 'type': 'garde', 'fonction': 'medecin', 'statut': 'actif'}, prefixe: 'PLN');
      await ouvrirM14(t, m, 'm10-propositions-planning', horloge: auj16, role: 'medecin');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Proposer une modification'));
      ctl(t).poser('date', '2026-09-21');
      ctl(t).poser('typeVacation', 'garde');
      ctl(t).poser('motif', 'Trop tôt');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Transmettre la proposition'));
      expect(find.textContaining('Incompatibilité : le repos de 48 h qui suit une garde n’est pas respecté'), findsOneWidget);
      expect(find.text('Choisir un jour après le repos de 48 h, ou retirer l’autre garde.'), findsOneWidget);
      expect(m.collection('propositionsPlanning').toutes, isEmpty);
      expect(find.text('Proposer une modification de mon planning'), findsOneWidget, reason: 'la modale reste ouverte pour corriger');
    });

    casM14('le surveillant VALIDE : le planning est modifié (la vacation naît validée, origine « proposition »), le contrôle est refait ; le refus exige son motif', (t) async {
      final m = magasinRhb();
      final col = m.collection('propositionsPlanning');
      final ok = col.inserer({
        'type': 'ajout', 'employeId': 'EMP01', 'employe': 'BASSONGUI Chabi Séko', 'fonction': 'medecin', 'date': '2026-09-20', 'typeVacation': 'garde', 'motif': 'Ok', 'etat': 'proposee',
        'proposeeLe': _jour, 'statut': 'actif',
      }, prefixe: 'PPL').fiche['id'];
      final aRefuser = col.inserer({
        'type': 'ajout', 'employeId': 'EMP02', 'employe': 'Autre agent', 'date': '2026-09-22', 'typeVacation': 'permanence', 'motif': 'À refuser', 'etat': 'proposee',
        'proposeeLe': _jour, 'statut': 'actif',
      }, prefixe: 'PPL').fiche['id'];
      await ouvrirM14(t, m, 'm10-propositions-planning', horloge: auj16, role: 'surveillant');
      final avant = m.collection('planning').toutes.length;
      // Refuser d'abord : sans motif, rien ne se passe ; avec motif, il est écrit et l'agent le lira.
      await chercherTableau(t, 'Autre agent');
      await toucherM14(t, find.byTooltip('Refuser cette proposition'));
      expect(find.text('Refuser cette proposition ?'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Refuser'));
      expect(col.parId(aRefuser)!['etat'], 'proposee');
      await t.enterText(find.byType(TextField).last, 'Effectif insuffisant');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Refuser'));
      expect([col.parId(aRefuser)!['etat'], col.parId(aRefuser)!['motifRefus']], ['refusee', 'Effectif insuffisant']);
      expect(find.text('Motif du refus : Effectif insuffisant'), findsOneWidget);
      expect(m.collection('planning').toutes.length, avant, reason: 'un refus ne change pas le planning');
      // Valider.
      await chercherTableau(t, 'BASSONGUI');
      await toucherM14(t, find.byTooltip('Valider cette proposition'));
      expect(find.text('Valider cette proposition ?'), findsOneWidget);
      expect(find.textContaining('le contrôle du repos étant refait'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider'));
      expect(col.parId(ok)!['etat'], 'validee');
      final v = m.collection('planning').toutes.first;
      expect([v['employeId'], v['date'], v['type'], v['origine'], v['validationEtat'], v['propositionId']], ['EMP01', '2026-09-20', 'garde', 'proposition', 'validee', ok]);
      expect(m.collection('planning').toutes.length, avant + 1);
      expect(find.text('Proposition validée : planning modifié.'), findsOneWidget);
    });

    casM14('la DA voit tout, peut trancher une proposition et règle le circuit et l\'application directe', (t) async {
      final m = magasinRhb();
      m.collection('propositionsPlanning').inserer({
        'type': 'retrait', 'employeId': 'EMP01', 'employe': 'BASSONGUI Chabi Séko', 'vacationId': 'X', 'motif': 'x', 'etat': 'proposee', 'proposeeLe': _jour, 'statut': 'actif',
      }, prefixe: 'PPL');
      await ouvrirM14(t, m, 'm10-propositions-planning', horloge: auj16, role: 'da');
      // La DA voit tout et peut trancher une proposition (le circuit des propositions est celui du planning : surveillant, DA, administrateur).
      expect(find.byTooltip('Valider cette proposition'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Régler'), findsOneWidget, reason: 'la DA règle le circuit et l\'application directe');
    });
  });
}

Future<void> chercherTableau(WidgetTester t, String ref) async {
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, ref);
  await t.pump(const Duration(milliseconds: 500));
}
