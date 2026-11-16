import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm10_aide.dart';

/// LOT PLAN-INDIV : les écrans du poste sur la fiche du personnel. Valeurs d'attente (mention par champ, « Confirmer » réservé à un geste de la fiche RBAC, absent sans lui), onglet
/// « Planning personnalisé » (définir, appliquer à une période : aperçu sans écriture), carte « Régimes individuels » et ses deux modes. Les règles sont celles du domaine (vecteurs de la
/// maquette) : ici, le BRANCHEMENT. NON VÉRIFIÉ : Windows, pixels.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Map<String, List<M>> avecMentions() => {
        'personnel': [
          for (final e in jeu('personnel')) {...e, 'valeursAttente': {'salaireBase': true, 'categorie': true, 'dateEmbauche': true, 'cnss': true}}
        ],
      };

  testWidgets('valeurs d\'attente : quatre mentions, « Confirmer » avec motif lève la seule mention du champ et se journalise ; sans le geste, la commande est ABSENTE', (t) async {
    final m = poste(avecMentions());
    await ouvrir(t, m, 'm10-employe-profil');
    expect(find.widgetWithText(BadgeSigh, 'Valeur d’attente'), findsNWidgets(4));
    expect(find.widgetWithText(BoutonSigh, 'Confirmer'), findsNWidgets(4));
    await cliquer(t, find.widgetWithText(BoutonSigh, 'Confirmer').first);
    await t.tap(find.widgetWithText(BoutonSigh, 'Confirmer la valeur'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(BadgeSigh, 'Valeur d’attente'), findsNWidgets(4), reason: 'sans motif, rien ne change');
    poser(t, {'motif': 'Contrat signé du 02/04/2018'});
    await t.tap(find.widgetWithText(BoutonSigh, 'Confirmer la valeur'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(BadgeSigh, 'Valeur d’attente'), findsNWidgets(3));
    final premier = (m.collection('personnel').actives.toList()..sort((a, b) => '${a['matricule']}'.compareTo('${b['matricule']}'))).first;
    expect((premier['valeursAttente'] as Map).length, 3);
    expect(m.collection('audit').toutes.where((l) => l['action'] == 'Valeur d’attente confirmée'), hasLength(1));
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('sans le geste réservé : les mentions restent lues, « Confirmer » est absent (jamais grisé)', (t) async {
    final m = poste(avecMentions());
    await ouvrir(t, m, 'm10-employe-profil', role: 'direction');
    expect(find.widgetWithText(BadgeSigh, 'Valeur d’attente'), findsNWidgets(4));
    expect(find.widgetWithText(BoutonSigh, 'Confirmer'), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('onglet « Planning personnalisé » : refus nommé à l\'écran, version enregistrée, aperçu sans écriture puis application', (t) async {
    final m = poste({'planning': const [], 'planningsPersonnalises': const []});
    await ouvrir(t, m, 'm10-employe-profil');
    await cliquer(t, find.text('Planning personnalisé'));
    expect(find.text('Aucun planning personnalisé : cet agent suit la grille de son régime.'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Appliquer à une période'), findsNothing, reason: 'aucune version : rien à appliquer');
    await cliquer(t, find.widgetWithText(BoutonSigh, 'Définir une version'));
    poser(t, {'periodicite': 'hebdomadaire', 'dateEffet': '2026-11-02', 'j1': 'garde', 'j2': 'garde', 'motif': 'Gardes serrées'});
    await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Incompatibilité'), findsWidgets, reason: 'repos de 48 h du médecin');
    expect(m.collection('planningsPersonnalises').actives, isEmpty);
    poser(t, {'j2': ''});
    poser(t, {'j4': 'garde'});
    await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('planningsPersonnalises').actives, hasLength(1));
    expect(find.textContaining('Version 1 (hebdomadaire)'), findsOneWidget);
    await cliquer(t, find.widgetWithText(BoutonSigh, 'Appliquer à une période'));
    poser(t, {'du': '2026-11-02', 'au': '2026-11-08'});
    await t.tap(find.widgetWithText(BoutonSigh, 'Aperçu'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Aperçu : 2 à poser, 0 jour(s) occupé(s) conservé(s)'), findsOneWidget);
    expect(m.collection('planning').actives, isEmpty, reason: 'l\'aperçu n\'écrit rien');
    await t.tap(find.widgetWithText(BoutonSigh, 'Appliquer').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('planning').actives.map((p) => p['date']).toSet(), {'2026-11-02', '2026-11-05'});
    expect(m.collection('planning').actives.every((p) => p['validationEtat'] == 'validee' && p['origine'] == 'modele'), isTrue);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('sans le geste réservé : « Définir une version » est ABSENT de l\'onglet', (t) async {
    final m = poste({'planning': const [], 'planningsPersonnalises': const []});
    await ouvrir(t, m, 'm10-employe-profil', role: 'direction');
    await cliquer(t, find.text('Planning personnalisé'));
    expect(find.widgetWithText(BoutonSigh, 'Définir une version'), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });
}
