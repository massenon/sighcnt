import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'parite/extracteur.dart';

/// M12 — comptabilité de base : m12-dashboard, m12-plan-comptable, m12-journaux, m12-ecritures, m12-depenses, m12-grand-livre, m12-balance.
/// Les règles sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cpa_comptabilite_test.dart) ; ici, l'ÉCRAN : la PARITÉ N1 mesurée
/// contre la fiche extraite de la maquette, puis ce qui est lu, saisi, refusé, écrit, journalisé — et ce qui n'est JAMAIS offert sans le droit.
const ecransCompta = [
  'm12-dashboard',
  'm12-plan-comptable',
  'm12-journaux',
  'm12-ecritures',
  'm12-depenses',
  'm12-grand-livre',
  'm12-balance',
];

Map<String, Object?> fiche(String id) =>
    (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin', DateTime? horloge}) =>
    ouvrirM14(t, m, ecran, role: role, horloge: horloge);

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité N1 : chaque libellé que la maquette affiche figure à l\'écran', () {
    for (final id in ecransCompta) {
      casM14('$id : N1 = 100 %', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        final p = comparerContenu(id, fiche(id), textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
        expect(p.taux, 1.0);
      });
    }
  });

  group('m12-dashboard', () {
    casM14('les huit indicateurs sont CALCULÉS depuis les écritures de l\'exercice, l\'alerte compte les brouillons', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-dashboard');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      final td = cpaTableauDeBord(e);
      expect(find.textContaining('${td.brouillons} écriture(s) en brouillon à valider.'), findsOneWidget);
      expect(find.textContaining(money(td.chiffreAffaires)), findsWidgets);
      expect(find.textContaining(money(td.charges)), findsWidgets);
      expect(find.text(td.equilibre ? 'Équilibré' : money(td.ecart)), findsWidgets);
    });

    casM14('un déséquilibre est DIT : la note danger nomme l\'écart', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({
        'numero': 'OD-2026-99999', 'date': '2026-10-30', 'journal': 'OD', 'compte': '601100', 'debit': 1234, 'credit': 0, 'statut': 'validee', 'origine': 'Saisie manuelle'
      });
      await ouvrir(t, m, 'm12-dashboard');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      expect(find.textContaining('RG-10 — déséquilibre constaté', findRichText: true), findsOneWidget);
      expect(find.textContaining(money(cpaTableauDeBord(e).ecart), findRichText: true), findsWidgets);
    });

    casM14('un exercice sans écriture ne casse pas l\'écran', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-dashboard', horloge: DateTime(2027, 3, 1, 10));
      expect(find.text('Trésorerie disponible'), findsOneWidget);
      expect(find.text('Équilibré'), findsWidgets);
    });
  });

  group('m12-plan-comptable', () {
    Future<void> chercherCompte(WidgetTester t, String q) async {
      await t.enterText(find.byType(TextField).first, q);
      await t.pump(const Duration(milliseconds: 600));
    }

    casM14('112 comptes, quatre indicateurs, trois onglets ; un compte du document porte sa provenance', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      expect(m.collection('comptes').actives.length, 112);
      for (final k in ['Comptes paramétrés', 'Issus des documents', 'Classes utilisées', 'Comptes mouvementés']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      for (final o in ['Tous les comptes', 'Par classe', 'Archivés']) {
        expect(find.text(o), findsOneWidget, reason: o);
      }
      expect(find.text('Document clinique'), findsWidgets);
    });

    casM14('un numéro qui n\'a pas six chiffres est REFUSÉ en le disant, rien n\'est écrit', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'num', '12345');
      await saisir(t, 'libelle', 'Compte court');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le numéro de compte doit comporter 6 chiffres.'), findsOneWidget);
      expect(m.collection('comptes').actives.length, 112);
    });

    casM14('un numéro déjà attribué est REFUSÉ à la création', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'num', '601100');
      await saisir(t, 'libelle', 'Doublon');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Ce numéro de compte existe déjà.'), findsOneWidget);
      expect(m.collection('comptes').actives.length, 112);
    });

    casM14('la création écrit un « Complément », en tête, journalisée', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      final avant = m.collection('audit').toutes.length;
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'num', '605900');
      await saisir(t, 'libelle', 'Petit outillage — essai');
      await choisirM14(t, 'classe', 'Classe 6 — Charges');
      await choisirM14(t, 'journal', 'ACH — Journal des achats');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = m.collection('comptes').actives.first;
      expect(f['num'], '605900');
      expect(f['classe'], 6);
      expect(f['journal'], 'ACH');
      expect(f['source'], 'CDCT');
      expect(f['statut'], 'actif');
      expect(m.collection('audit').toutes.length, greaterThan(avant), reason: 'RG-12 : la création est journalisée');
    });

    casM14('modifier un compte du DOCUMENT conserve sa provenance (E721 : la maquette la remettait à « Complément »)', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      await chercherCompte(t, '601100');
      await toucherM14(t, find.byTooltip('Modifier').first);
      await saisir(t, 'libelle', 'Achats de marchandises (corrigé)');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = m.collection('comptes').actives.firstWhere((x) => x['num'] == '601100');
      expect(f['libelle'], 'Achats de marchandises (corrigé)');
      expect(f['source'], 'DOC');
    });

    casM14('archiver : avec motif consigné, annulable, jamais supprimé (RG-14)', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      await chercherCompte(t, '601100');
      await toucherM14(t, find.byTooltip('Archiver').first);
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
      // Le poste EXIGE le motif (comme M14, E600) ; la maquette ne l'impose pas (E722).
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Compte doublon du classeur');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      final f = m.collection('comptes').toutes.firstWhere((x) => x['num'] == '601100');
      expect(f['statut'], 'archive');
      expect(m.collection('comptes').toutes.length, 112, reason: 'rien n\'est supprimé');
    });

    casM14('l\'onglet « Par classe » range chaque compte sous sa classe, avec son solde', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      await toucherM14(t, find.text('Par classe'));
      for (final k in [1, 2, 3, 4, 5, 6, 7]) {
        expect(find.text(cpaClasseLibelle(k)), findsOneWidget, reason: 'classe $k');
      }
      expect(find.text('401000'), findsOneWidget);
    });

    casM14('en lecture seule : ni « Nouveau », ni « Modifier », ni « Archiver » — ABSENTS, pas grisés', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'm12-plan-comptable',
          role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-plan-comptable'));
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
    });

    casM14('l\'impression : l\'aperçu porte le titre du plan comptable', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le plan comptable'));
      expect(find.text('Plan comptable SYSCOHADA'), findsWidgets);
    });
  });

  group('m12-journaux', () {
    casM14('huit journaux, quatre indicateurs, un écran CALCULÉ : aucune commande de création', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-journaux');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      for (final j in cpaJournaux) {
        expect(find.text(j.$2), findsWidgets, reason: j.$1);
      }
      expect(find.text('Journaux ouverts'), findsOneWidget);
      expect(find.text(nombre(e.length)), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.text('Équilibré'), findsWidgets);
    });

    casM14('un journal déséquilibré est DIT : « Écart » nommé, jamais un « Équilibré » de complaisance', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({
        'numero': 'ACH-2026-99999', 'date': '2026-10-30', 'journal': 'ACH', 'compte': '601100', 'debit': 4321, 'credit': 0, 'statut': 'validee', 'origine': 'Saisie manuelle'
      });
      await ouvrir(t, m, 'm12-journaux');
      final ach = cpaLignesJournaux(cpaEcrituresExercice(m.collection('ecritures').actives, 2026)).firstWhere((j) => j.code == 'ACH');
      expect(ach.equilibre, isFalse);
      expect(find.text('Écart ${nt(cpaMontant(ach.ecart))}'), findsNothing, reason: 'espace insécable de money()');
      expect(find.textContaining('Écart ', findRichText: true), findsOneWidget);
    });

    casM14('le tiroir d\'un journal : écritures du journal (quarante au plus), totaux, impression', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-journaux');
      await toucherM14(t, find.byTooltip('Consulter le journal').at(2));
      expect(find.textContaining('Journal CAI — '), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer le journal'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.widgetWithText(BoutonSigh, 'Imprimer le journal'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Journal comptable — Journal de caisse-dépenses'), findsWidgets);
      expect(find.text('TOTAUX'), findsWidgets, reason: 'le pied est refait depuis les lignes imprimées');
    });
  });
}
