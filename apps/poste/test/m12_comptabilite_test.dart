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

    casM14('110 comptes actifs (112 fiches, 2 doublons du plan archivés), quatre indicateurs, trois onglets ; un compte du document porte sa provenance', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      expect(m.collection('comptes').actives.length, 110, reason: 'les deux doublons (244100, 631810) sont archivés au chargement (E724/E725)');
      expect(m.collection('comptes').archivees.map((x) => x['num']).toSet(), {'244100', '631810'});
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
      expect(m.collection('comptes').actives.length, 110);
    });

    casM14('un numéro déjà attribué est REFUSÉ à la création', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'num', '601100');
      await saisir(t, 'libelle', 'Doublon');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Ce numéro de compte existe déjà.'), findsOneWidget);
      expect(m.collection('comptes').actives.length, 110);
    });

    casM14('l\'unicité vaut aussi à la MODIFICATION et face à un compte ARCHIVÉ (E724 levé), le refus nomme la corbeille', (t) async {
      final m = magasinM14();
      await ouvrir(t, m, 'm12-plan-comptable');
      await chercherCompte(t, '601100');
      await toucherM14(t, find.byTooltip('Modifier').first);
      await saisir(t, 'num', '604100');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Ce numéro de compte existe déjà.'), findsOneWidget);
      expect(m.collection('comptes').actives.firstWhere((x) => x['libelle'] == 'Achats de marchandises')['num'], '601100', reason: 'rien n\'est écrit');
      await t.pump(const Duration(seconds: 10));
    });

    casM14('un numéro de compte ARCHIVÉ ne se recrée pas : le refus dit où le restaurer', (t) async {
      final m = magasinM14();
      final cpt = m.collection('comptes').actives.firstWhere((x) => x['num'] == '604100');
      m.collection('comptes').archiver(cpt['id']);
      await ouvrir(t, m, 'm12-plan-comptable');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'num', '604100');
      await saisir(t, 'libelle', 'Essai');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Ce numéro de compte existe déjà (compte archivé : le restaurer depuis la corbeille).'), findsOneWidget);
      expect(m.collection('comptes').actives.where((x) => x['num'] == '604100'), isEmpty);
      await t.pump(const Duration(seconds: 10));
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

  group('m12-ecritures', () {
    Future<void> ligne(WidgetTester t, String compte, {String debit = '0', String credit = '0'}) async {
      await choisirM14(t, 'compte', compte);
      await saisir(t, 'debit', debit);
      await saisir(t, 'credit', credit);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ajouter la ligne'));
    }

    /// Ouvre la saisie et remplit l'en-tête ; les lignes viennent ensuite.
    Future<void> entete(WidgetTester t, {String journal = 'OD — Journal des opérations diverses', String libelle = 'Essai'}) async {
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle écriture'));
      await choisirM14(t, 'journal', journal);
      await saisir(t, 'libelle', libelle);
    }

    List<Fiche> piece(Magasin m, String libelle) =>
        [for (final e in m.collection('ecritures').toutes) if (e['libelle'] == libelle) e];

    casM14('quatre indicateurs lus sur les écritures actives ; le tableau porte ses dix colonnes', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      final a = m.collection('ecritures').actives;
      expect(find.text('Écritures enregistrées'), findsOneWidget);
      expect(find.text(nombre(a.where((e) => '${e['origine']}'.startsWith('Automatique')).length)), findsWidgets);
      for (final k in ['N° pièce', 'Date', 'Journal', 'Compte', 'Libellé de l’opération', 'Débit', 'Crédit', 'Centre de coûts', 'Origine', 'Statut']) {
        expect(find.text(k.toUpperCase()), findsWidgets, reason: k);
      }
    });

    casM14('une écriture VALIDÉE équilibrée : deux lignes plates en tête, numérotée dans la série, journalisée', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      final suivant = cpaNumeroPiece('OD', 2026, m.collection('ecritures').toutes);
      await entete(t, libelle: 'Achat de petit matériel');
      await ligne(t, '605600 — Achats de petit matériel et outillages', debit: '7500');
      await ligne(t, '571000 — Caisse', credit: '7500');
      expect(find.textContaining('RG-10 respectée'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider l’écriture'));
      final p = piece(m, 'Achat de petit matériel');
      expect(p.length, 2);
      expect(p.every((e) => e['numero'] == suivant && e['statut'] == 'validee' && e['origine'] == 'Saisie manuelle' && e['journal'] == 'OD'), isTrue);
      expect(p.fold<num>(0, (a, e) => a + (e['debit'] as num)), 7500);
      expect(p.fold<num>(0, (a, e) => a + (e['credit'] as num)), 7500);
      expect(m.collection('ecritures').toutes.first['libelle'], 'Achat de petit matériel', reason: 'insérées en tête');
      final journal = m.collection('audit').toutes.first;
      expect(journal['action'], 'Création', reason: 'RG-12 : la saisie est journalisée (le journal est plafonné à 400 : on lit la dernière entrée)');
      expect(journal['utilisateur'], isNotEmpty);
      expect(find.textContaining('enregistrée (2 ligne(s))'), findsOneWidget);
    });

    casM14('RG-10 : VALIDER une écriture déséquilibrée est REFUSÉ, l\'écart est nommé, la saisie reste ouverte, rien n\'est écrit', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      final n0 = m.collection('ecritures').toutes.length;
      await entete(t, libelle: 'Écriture déséquilibrée');
      await ligne(t, '601100 — Achats de marchandises', debit: '5000');
      await ligne(t, '571000 — Caisse', credit: '4000');
      expect(find.textContaining('La validation est impossible tant que débit ≠ crédit.'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider l’écriture'));
      expect(find.text('RG-10 — écriture déséquilibrée : validation impossible.'), findsOneWidget);
      expect(find.textContaining('Écart de ${money(1000)}.'), findsOneWidget);
      expect(m.collection('ecritures').toutes.length, n0);
      expect(find.text('Nouvelle écriture comptable'), findsOneWidget, reason: 'la saisie reste ouverte');
    });

    casM14('un BROUILLON déséquilibré est accepté ; sa validation, ligne par ligne, est refusée en nommant la pièce', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      await entete(t, libelle: 'Brouillon déséquilibré');
      await ligne(t, '601100 — Achats de marchandises', debit: '5000');
      await ligne(t, '571000 — Caisse', credit: '4000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer en brouillon'));
      final p = piece(m, 'Brouillon déséquilibré');
      expect(p.length, 2);
      expect(p.every((e) => e['statut'] == 'brouillon'), isTrue);
      await t.pump(const Duration(seconds: 6));
      await t.enterText(find.byType(TextField).first, 'Brouillon déséquilibré');
      await t.pump(const Duration(milliseconds: 600));
      await toucherM14(t, find.byTooltip('Valider').first);
      expect(find.text('RG-10 — écriture déséquilibrée : validation impossible.'), findsOneWidget);
      expect(find.textContaining('Pièce ${p.first['numero']} : écart de ${money(1000)}.'), findsOneWidget);
      expect(piece(m, 'Brouillon déséquilibré').every((e) => e['statut'] == 'brouillon'), isTrue, reason: 'aucune ligne n\'a été validée seule');
    });

    casM14('valider un brouillon équilibré valide la PIÈCE ENTIÈRE (E710)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      await entete(t, libelle: 'Frais de tenue de compte', journal: 'BQ — Journal de banque');
      await ligne(t, '631810 — Frais bancaire BOA', debit: '2500');
      await ligne(t, '521000 — Banque', credit: '2500');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer en brouillon'));
      await t.pump(const Duration(seconds: 6));
      await t.enterText(find.byType(TextField).first, 'Frais de tenue de compte');
      await t.pump(const Duration(milliseconds: 600));
      await toucherM14(t, find.byTooltip('Valider').first);
      final p = piece(m, 'Frais de tenue de compte');
      expect(p.length, 2);
      expect(p.every((e) => e['statut'] == 'validee'), isTrue, reason: 'les DEUX lignes, pas une seule');
      expect(find.text('Écriture validée.'), findsOneWidget);
    });

    casM14('archiver archive la PIÈCE entière (E716), jamais supprimée (RG-14), annulable', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      await entete(t, libelle: 'Pièce à archiver');
      await ligne(t, '601100 — Achats de marchandises', debit: '100');
      await ligne(t, '571000 — Caisse', credit: '100');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider l’écriture'));
      await t.pump(const Duration(seconds: 6));
      await t.enterText(find.byType(TextField).first, 'Pièce à archiver');
      await t.pump(const Duration(milliseconds: 600));
      await toucherM14(t, find.byTooltip('Archiver').first);
      final p = piece(m, 'Pièce à archiver');
      expect(p.length, 2, reason: 'rien n\'est supprimé');
      expect(p.every((e) => e['statut'] == 'archive'), isTrue);
      expect(find.text('Écriture archivée.'), findsOneWidget);
    });

    casM14('aucune ligne : « Ajouter au moins une ligne. » ; ni débit ni crédit, ou les deux sens : refus nommés', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      final n0 = m.collection('ecritures').toutes.length;
      await entete(t, libelle: 'Sans ligne');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer en brouillon'));
      expect(find.text('Ajouter au moins une ligne.'), findsOneWidget);
      await ligne(t, '601100 — Achats de marchandises');
      expect(find.text('Renseigner un montant au débit ou au crédit.'), findsOneWidget);
      await ligne(t, '601100 — Achats de marchandises', debit: '10', credit: '10');
      expect(find.text('Une ligne ne peut être simultanément au débit et au crédit.'), findsOneWidget);
      expect(m.collection('ecritures').toutes.length, n0);
    });

    casM14('exercice CLOS : l\'écriture est refusée avec le motif du moteur, rien n\'est écrit, aucun faux « enregistrée » (E713)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures', horloge: DateTime(2025, 12, 20, 10));
      final n0 = m.collection('ecritures').toutes.length;
      await entete(t, libelle: 'Écriture sur exercice clos');
      await ligne(t, '601100 — Achats de marchandises', debit: '1000');
      await ligne(t, '571000 — Caisse', credit: '1000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider l’écriture'));
      expect(find.text('Écriture refusée.'), findsOneWidget);
      expect(find.textContaining('Exercice 2025 clos le 15/05/2026 — lecture seule.'), findsOneWidget);
      expect(find.textContaining('enregistrée ('), findsNothing);
      expect(m.collection('ecritures').toutes.length, n0);
    });

    casM14('« Nouveau centre de coûts » sans quitter la saisie : code CCnn, source dite, sélectionné', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      final n0 = m.collection('centresCouts').toutes.length;
      await entete(t, libelle: 'Avec centre neuf');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau centre de coûts'));
      await t.enterText(
          find.descendant(of: find.byKey(const Key('kit:champ:libelle')).last, matching: find.byType(TextField)), 'Buanderie');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final cc = m.collection('centresCouts').toutes.first;
      expect(m.collection('centresCouts').toutes.length, n0 + 1);
      expect(cc['code'], 'CC${(n0 + 1).toString().padLeft(2, '0')}');
      expect(cc['source'], 'Créé depuis la saisie comptable');
      expect(cc['libelle'], 'Buanderie');
      expect(find.text('Nouvelle écriture comptable'), findsOneWidget, reason: 'la saisie n\'a pas été quittée');
    });

    casM14('la fiche d\'une écriture : toutes les lignes de la pièce, équilibre dit', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      await toucherM14(t, find.byTooltip('Consulter').first);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Lignes de l’écriture'), findsOneWidget);
      expect(find.textContaining('(RG-10)', findRichText: true), findsOneWidget);
    });

    casM14('en lecture seule : « Nouvelle écriture », « Valider » et « Archiver » sont ABSENTS, le bandeau le dit (E723)', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-ecritures', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-ecritures'));
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle écriture'), findsNothing);
      expect(find.byTooltip('Valider'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
    });
  });

  group('m12-grand-livre', () {
    casM14('le premier compte mouvementé est ouvert : mouvements, totaux et solde sont CEUX des écritures', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-grand-livre');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      final premier = cpaComptesMouvementes(m.collection('comptes').actives, e).first['num'] as String;
      final s = cpaSoldeCompte(e, premier);
      expect(find.text('$premier — ${cpaCompteLibelle(premier)}'), findsNWidgets(2), reason: 'la liste et le titre du tableau');
      expect(find.text(money(s.debit)), findsWidgets);
      expect(find.text(money(s.credit)), findsWidgets);
      expect(find.text(money(s.solde)), findsWidgets);
      expect(find.text(s.solde >= 0 ? 'Débiteur' : 'Créditeur'), findsOneWidget);
      expect(find.text('${cpaGrandLivre(e, premier).length}'), findsWidgets);
    });

    casM14('changer de compte recompose les mouvements ; le solde progressif suit chaque ligne', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-grand-livre');
      await choisirM14(t, 'compte', '571000 — Caisse');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      final s = cpaSoldeCompte(e, '571000');
      expect(find.text('571000 — Caisse'), findsWidgets);
      expect(find.text(money(s.solde)), findsWidgets);
      final gl = cpaGrandLivre(e, '571000');
      expect(find.text(cpaMontant(gl.first['soldeProgressif'])), findsWidgets, reason: 'premier solde progressif');
    });

    casM14('un compte sans mouvement n\'est pas proposé ; le plan à deux fiches au même numéro n\'en propose qu\'UNE (E724)', (t) async {
      final m = magasinComplet();
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      final l = cpaComptesMouvementes(m.collection('comptes').actives, e).map((x) => x['num']).toList();
      expect(l.where((x) => x == '631810').length, 1);
      expect(l.contains('101100'), isFalse, reason: 'capital souscrit : aucun mouvement');
      await ouvrir(t, m, 'm12-grand-livre');
      expect(find.text('Grand livre'), findsWidgets);
    });

    casM14('un exercice sans écriture : « Aucun mouvement sur ce compte. », l\'écran ne casse pas', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-grand-livre', horloge: DateTime(2027, 3, 1, 10));
      expect(find.text('Aucun mouvement sur ce compte.'), findsOneWidget);
    });

    casM14('l\'impression : le grand livre d\'un compte (totaux refaits) et le grand livre complet', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-grand-livre');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le grand livre'));
      expect(find.text('Grand livre'), findsWidgets);
      expect(find.textContaining('Compte 401000 — Fournisseurs'), findsWidgets);
      expect(find.text('TOTAL'), findsWidgets);
    });

    casM14('lecture seule : aucune commande d\'écriture n\'existe sur l\'écran', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-grand-livre');
      for (final k in ['Nouveau', 'Nouvelle écriture', 'Modifier', 'Archiver']) {
        expect(find.widgetWithText(BoutonSigh, k), findsNothing, reason: k);
      }
    });
  });

  group('m12-balance', () {
    casM14('RG-10 : sur le jeu, la balance est ÉQUILIBRÉE et ses totaux sont ceux du journal (E725 : le plan à deux fiches 631810 ne double plus rien)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-balance');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      final b = cpaBalance(m.collection('comptes').actives, e);
      expect(b.fold<double>(0, (a, x) => a + x.debit), e.fold<double>(0, (a, x) => a + (x['debit'] as num)));
      expect(find.text('Équilibrée'), findsOneWidget);
      expect(find.textContaining('La balance est équilibrée', findRichText: true), findsOneWidget);
    });

    casM14('un déséquilibre est DIT : bandeau danger, écart nommé, régularisation avant clôture', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({
        'numero': 'OD-2026-99998', 'date': '2026-10-30', 'journal': 'OD', 'compte': '601100', 'debit': 777, 'credit': 0, 'statut': 'validee', 'origine': 'Saisie manuelle'
      });
      await ouvrir(t, m, 'm12-balance');
      expect(find.textContaining('Balance déséquilibrée — écart de ${money(777)}', findRichText: true), findsOneWidget);
      expect(find.text(money(777)), findsWidgets);
    });

    casM14('la balance générale : une ligne par compte mouvementé, trois onglets de lecture, filtre par classe', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-balance');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, 2026);
      final b = cpaBalance(m.collection('comptes').actives, e);
      expect(find.text(nombre(b.length)), findsWidgets);
      for (final k in ['Compte', 'Intitulé', 'Classe', 'Mvts', 'Mouvement débit', 'Mouvement crédit', 'Solde débiteur', 'Solde créditeur']) {
        expect(find.text(k.toUpperCase()), findsWidgets, reason: k);
      }
    });

    casM14('la balance âgée : quatre tranches, créances patients et assureurs, impression totalisée', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-balance');
      await toucherM14(t, find.text('Balance âgée (tiers)'));
      for (final k in ['Moins de 30 jours', '30 à 60 jours', '60 à 90 jours', 'Plus de 90 jours']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      final tr = cpaBalanceAgee(m.collection('factures').actives, DateTime(2026, 10, 30, 10));
      expect(find.text(money(tr.fold<double>(0, (a, x) => a + x.montantPatients), avecDevise: false)), findsNothing, reason: 'le total n\'est pas dans le tableau');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la balance âgée'));
      expect(find.text('TOTAL DES CRÉANCES'), findsWidgets);
    });

    casM14('l\'impression de la balance : pied TOTAUX refait depuis les lignes', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-balance');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la balance'));
      expect(find.text('Balance générale des comptes'), findsWidgets);
      expect(find.text('TOTAUX'), findsWidgets);
    });

    casM14('lecture seule : aucune commande d\'écriture n\'existe sur l\'écran', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-balance');
      for (final k in ['Nouveau', 'Nouvelle écriture', 'Modifier', 'Archiver']) {
        expect(find.widgetWithText(BoutonSigh, k), findsNothing, reason: k);
      }
    });
  });

  group('m12-depenses', () {
    /// Saisit dans le champ [champ] DU DERNIER formulaire ouvert (une ligne se saisit dans une modale posée sur celle de la pièce).
    Future<void> saisirDernier(WidgetTester t, String champ, String texte) async {
      final f = find.descendant(of: find.byKey(Key('kit:champ:$champ')).last, matching: find.byType(TextField));
      await t.enterText(f, texte);
      await t.pump();
    }

    Future<void> ajouter(WidgetTester t, String libelle, String compte, String montant) async {
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ajouter une ligne'));
      await saisirDernier(t, 'libelle', libelle);
      await choisirM14(t, 'compteCharge', compte);
      await saisirDernier(t, 'montant', montant);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
    }

    Future<void> nouvelle(WidgetTester t, {String tresorerie = 'Caisse de la clinique'}) async {
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle dépense'));
      await choisirM14(t, 'compteTresorerie', tresorerie);
    }

    casM14('QUATRE indicateurs (pas cinq), calculés sur les dépenses ; la note compte celles sans justificatif', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses');
      final dep = m.collection('depenses').actives;
      final i = cpaIndicateursDepenses(dep, '2026-10-30');
      for (final k in ['Dépensé aujourd’hui', 'Dépensé ce mois', 'Total enregistré', 'Sans justificatif']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      expect(find.text('Dépense moyenne'), findsNothing, reason: 'retirée par l\'arbitrage du 31/08/2026');
      expect(find.text(money(i.total)), findsOneWidget);
      expect(find.textContaining('${i.nbSansRecu} dépense(s) sans justificatif, pour ${money(i.sansRecu)}', findRichText: true), findsOneWidget);
    });

    casM14('« Aujourd\'hui » est un FILTRE, pas un tri : la plage restreint les pièces et les indicateurs', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Aujourd’hui'));
      final jour = [for (final r in m.collection('depenses').actives) if (r['date'] == '2026-10-30') r];
      final i = cpaIndicateursDepenses(jour, '2026-10-30');
      expect(find.text(money(i.total)), findsWidgets);
      expect(find.text('${jour.length} dépense(s)'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Tout l’historique'));
      expect(find.text('${m.collection('depenses').actives.length} dépense(s)'), findsOneWidget);
    });

    casM14('une dépense à TROIS lignes : le total est la somme, un débit par ligne, un crédit de trésorerie du total, en BROUILLON, même numéro de pièce', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses');
      final reference = cpaReferenceDepense('2026-10-30', m.collection('depenses').toutes);
      await nouvelle(t);
      await ajouter(t, 'Gants d’examen', '601100 — Achats de marchandises', '12000');
      await ajouter(t, 'Compresses', '604100 — Matieres consommables', '8000');
      await ajouter(t, 'Sparadrap', '605600 — Achats de petit matériel et outillages', '4500');
      expect(find.text('TOTAL — 3 ligne(s)'), findsOneWidget);
      expect(find.text(cpaMontant(24500)), findsWidgets);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final d = m.collection('depenses').actives.first;
      expect(d['reference'], reference);
      expect(d['montant'], 24500);
      expect(d['libelle'], 'Gants d’examen (+2 autre(s))');
      expect(d['justificatif'], isNull, reason: 'le reçu n\'est pas bloquant');
      expect((d['lignes'] as List).length, 3);
      expect(d['saisiPar'], isNotEmpty, reason: 'RG-12 : aucune action anonyme');
      final e = [for (final x in m.collection('ecritures').actives) if (x['numero'] == reference) x];
      expect(e.length, 4);
      expect(e.every((x) => x['statut'] == 'brouillon' && x['origine'] == 'Dépense journalière' && x['pieceId'] == d['id']), isTrue);
      expect(e.fold<num>(0, (a, x) => a + (x['debit'] as num)), 24500);
      expect(e.fold<num>(0, (a, x) => a + (x['credit'] as num)), 24500, reason: 'RG-10');
      expect((d['ecritureIds'] as List).length, 4, reason: 'on retient TOUS les identifiants');
      expect(e.where((x) => n0(x['credit']) > 0).single['compte'], '571000');
      expect(find.textContaining('${money(24500)} en 3 ligne(s)'), findsOneWidget);
      expect(find.textContaining('sans justificatif'), findsWidgets);
    });

    casM14('une pièce sans ligne est REFUSÉE en le disant, rien n\'est écrit, la saisie reste ouverte', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses');
      final n0 = m.collection('depenses').toutes.length, e0 = m.collection('ecritures').toutes.length;
      await nouvelle(t);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('La pièce exige au moins une ligne de dépense.'), findsOneWidget);
      expect(m.collection('depenses').toutes.length, n0);
      expect(m.collection('ecritures').toutes.length, e0);
      expect(find.text('Nouvelle dépense'), findsWidgets);
    });

    casM14('exercice CLOS : refusé AVANT toute écriture, avec le motif du moteur (E714) — ni la dépense ni son écriture', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses', horloge: DateTime(2025, 11, 12, 10));
      final n0 = m.collection('depenses').toutes.length, e0 = m.collection('ecritures').toutes.length;
      await nouvelle(t, tresorerie: 'Compte courant BOA');
      await ajouter(t, 'Frais bancaires BOA', '631810 — Frais bancaire BOA', '9000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Écriture refusée.'), findsOneWidget);
      expect(find.textContaining('Exercice 2025 clos le 15/05/2026'), findsOneWidget);
      expect(m.collection('depenses').toutes.length, n0);
      expect(m.collection('ecritures').toutes.length, e0);
    });

    casM14('une sortie de BANQUE : crédit sur le compte 5xx de la fiche, journal BQE (E719)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses');
      await nouvelle(t, tresorerie: 'Compte courant BOA');
      await ajouter(t, 'Timbres fiscaux', '646210 — Droit de Timbre', '3000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final d = m.collection('depenses').actives.first;
      final e = [for (final x in m.collection('ecritures').actives) if (x['numero'] == d['reference']) x];
      expect(e.length, 2);
      expect(e.every((x) => x['journal'] == 'BQE'), isTrue);
      expect(e.where((x) => n0(x['credit']) > 0).single['compte'], '521100');
    });

    casM14('modifier : l\'écriture est REFAITE (toutes les anciennes lignes archivées), le total suit les lignes, elle repart en brouillon', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses');
      await nouvelle(t);
      await ajouter(t, 'Gants d’examen', '601100 — Achats de marchandises', '12000');
      await ajouter(t, 'Compresses', '604100 — Matieres consommables', '8000');
      await ajouter(t, 'Sparadrap', '605600 — Achats de petit matériel et outillages', '4500');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final d = m.collection('depenses').actives.first;
      final anciennes = (d['ecritureIds'] as List).toList();
      await t.pump(const Duration(seconds: 6));
      await t.enterText(find.byType(TextField).first, '${d['reference']}');
      await t.pump(const Duration(milliseconds: 600));
      await toucherM14(t, find.byTooltip('Modifier').first);
      await toucherM14(t, find.byTooltip('Retirer la ligne').at(2));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final r = m.collection('depenses').parId(d['id'])!;
      expect(r['montant'], 20000);
      expect((r['lignes'] as List).length, 2);
      for (final id in anciennes) {
        expect(m.collection('ecritures').parId(id)!['statut'], 'archive', reason: 'TOUTES les anciennes lignes');
      }
      final neuves = [for (final x in m.collection('ecritures').actives) if (x['numero'] == d['reference']) x];
      expect(neuves.length, 3);
      expect(neuves.fold<num>(0, (a, x) => a + (x['debit'] as num)), neuves.fold<num>(0, (a, x) => a + (x['credit'] as num)));
      expect(neuves.every((x) => x['statut'] == 'brouillon'), isTrue);
      expect(find.text('Dépense modifiée.'), findsOneWidget);
    });

    casM14('archiver : la dépense ET son écriture entière sont archivées, jamais supprimées (RG-14)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses');
      await nouvelle(t);
      await ajouter(t, 'Gants d’examen', '601100 — Achats de marchandises', '12000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final d = m.collection('depenses').actives.first;
      await t.pump(const Duration(seconds: 6));
      await t.enterText(find.byType(TextField).first, '${d['reference']}');
      await t.pump(const Duration(milliseconds: 600));
      await toucherM14(t, find.byTooltip('Archiver').first);
      expect(find.textContaining('La dépense et son écriture sont archivées, jamais supprimées (RG-14).'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('depenses').parId(d['id'])!['statut'], 'archive');
      for (final id in d['ecritureIds'] as List) {
        expect(m.collection('ecritures').parId(id)!['statut'], 'archive');
      }
      expect(m.collection('ecritures').toutes.where((x) => x['numero'] == d['reference']).length, 2, reason: 'rien n\'est supprimé');
    });

    casM14('la fiche d\'une dépense sans reçu dit « AUCUN — charge contestable » et l\'écriture « non posée » ; la pièce imprimée le redit', (t) async {
      final m = magasinComplet();
      final sans = m.collection('depenses').actives.firstWhere((r) => r['justificatif'] == null);
      await ouvrir(t, m, 'm12-depenses');
      await t.enterText(find.byType(TextField).first, '${sans['reference']}');
      await t.pump(const Duration(milliseconds: 600));
      await toucherM14(t, find.byTooltip('Consulter').first);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('AUCUN — charge contestable'), findsOneWidget);
      expect(find.text('non posée'), findsOneWidget);
      await t.tap(find.widgetWithText(BoutonSigh, 'Imprimer la pièce'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Pièce de dépense'), findsWidgets);
      expect(find.textContaining('Aucun justificatif joint : cette charge est contestable en cas de contrôle.'), findsWidgets);
    });

    casM14('« État des dépenses » : total refait depuis les lignes imprimées', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-depenses');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'État des dépenses'));
      expect(find.text('État des dépenses de trésorerie'), findsWidgets);
      expect(find.text('TOTAL'), findsWidgets);
    });

    casM14('en lecture seule : « Nouvelle dépense », « Modifier » et « Archiver » sont ABSENTS ; consulter et imprimer restent', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-depenses', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-depenses'));
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle dépense'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
      expect(find.byTooltip('Imprimer la pièce'), findsWidgets);
      expect(find.textContaining('Votre profil consulte les dépenses sans les saisir.'), findsOneWidget);
    });

    casM14('le caissier n\'a plus l\'écran (fermé le 02/09) : la coque ne l\'ouvre pas', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-depenses', role: 'caissier');
      expect(find.text('Nouvelle dépense'), findsNothing);
      expect(find.text('Dépensé aujourd’hui'), findsNothing);
    });
  });
}

num n0(Object? v) => v is num ? v : 0;
