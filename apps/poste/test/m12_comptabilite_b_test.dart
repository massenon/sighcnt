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

/// M12 (B) — comptabilité : m12-analytique, m12-budgets, m12-immobilisations, m12-banques, m12-compte-resultat, m12-flux-tresorerie,
/// m12-seuil-rentabilite. Les règles sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cpb_*_test.dart) ; ici, l'ÉCRAN : la PARITÉ N1
/// mesurée contre la fiche extraite de la maquette, puis ce qui est lu, saisi, refusé, écrit, journalisé — et ce qui n'est JAMAIS offert sans le droit.
const ecransComptaB = [
  'm12-analytique',
  'm12-budgets',
  'm12-immobilisations',
  'm12-banques',
  'm12-compte-resultat',
  'm12-flux-tresorerie',
  'm12-seuil-rentabilite',
];

Map<String, Object?> fiche(String id) =>
    (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin', DateTime? horloge}) =>
    ouvrirM14(t, m, ecran, role: role, horloge: horloge);

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité N1 : chaque libellé que la maquette affiche figure à l\'écran', () {
    for (final id in ecransComptaB) {
      casM14('$id : N1 = 100 %', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        final p = comparerContenu(id, fiche(id), textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
        expect(p.taux, 1.0);
      });
    }
  });

  // ------------------------------------------------------------------------------------------------------------------------------------------------
  for (final genre in ['resultat', 'flux']) {
    final id = genre == 'resultat' ? 'm12-compte-resultat' : 'm12-flux-tresorerie';
    final res = genre == 'resultat';
    group(id, () {
      casM14('par défaut : exercice 2026 CALCULÉ (N) face à la liasse CITÉE (N-1), chaque indicateur lit les colonnes', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        final cols = cpbColonnesFeuillet(genre, '2026', DateTime(2026, 10, 30), m.collection('ecritures').actives);
        expect(find.text('EXERCICE 2026 (N)'), findsOneWidget);
        expect(find.text('EXERCICE AU 31/12/2025 (N-1)'), findsOneWidget);
        expect(find.text('${res ? 'NET (1) — ' : ''}calculé — arrêté au 30/10/2026'), findsOneWidget);
        expect(find.text('${res ? 'NET (1) — ' : ''}déposé — liasse BK505416'), findsOneWidget);
        for (final ref in res ? ['XB', 'XC', 'XD', 'XI'] : ['ZA', 'ZB', 'ZG', 'ZH']) {
          expect(find.text(money(cols[0].val(ref))), findsWidgets, reason: ref);
        }
        // un sous-total CITÉ du dépôt (chiffre d'affaires 2025) figure à sa place
        if (res) expect(find.text(money(190830994, avecDevise: false)), findsWidgets);
      });

      casM14('la colonne « calculé » reste VIDE (—) là où le journal ne porte rien ; la colonne « déposé » porte ses zéros', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        expect(find.text('—'), findsWidgets);
        expect(find.text('0'), findsWidgets);
      });

      casM14('les brouillons écartés sont annoncés, et seules les écritures validées sont retenues', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        final cols = cpbColonnesFeuillet(genre, '2026', DateTime(2026, 10, 30), m.collection('ecritures').actives);
        expect(cols[0].brouillons, greaterThan(0));
        expect(find.textContaining('${cols[0].brouillons} brouillon(s) écarté(s)'), findsOneWidget);
        expect(find.textContaining('${cols[0].nbLignes} ligne(s) d’écriture validée(s) retenue(s)'), findsOneWidget);
      });

      casM14('« liasse déposée » : les deux colonnes sont CITÉES, la date d\'arrêt disparaît, l\'en-tête de dépôt s\'affiche', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        await choisirM14(t, 'exercice', 'Exercice 2025 — liasse déposée (BK505416)');
        expect(find.text('Arrêté au'), findsNothing);
        expect(find.text('EXERCICE AU 31/12/2025 (N)'), findsOneWidget);
        expect(find.text('EXERCICE AU 31/12/2024 (N-1)'), findsOneWidget);
        expect(find.text('15/05/2026'), findsOneWidget);
        expect(find.text('BK505416'), findsWidgets);
        expect(find.text('3201642748214'), findsOneWidget);
        expect(find.textContaining('(déposé)'), findsWidgets);
        if (res) {
          expect(find.textContaining('les 9 sous-totaux déposés (XA à XI) se recalculent à l’identique'), findsWidgets);
        } else {
          // les écarts internes du document déposé sont CONSERVÉS et signalés, non arbitrés
          expect(find.text('Écarts internes du document déposé — conservés, non arbitrés'), findsOneWidget);
          expect(find.textContaining('Variation du BF (déposé ${money(31359405)}, recalculé ${money(-2632175)})'), findsOneWidget);
          expect(find.text('écart du document'), findsWidgets);
        }
      });

      casM14('la date d\'arrêt suit l\'horloge du poste : au 30 juin, rien de ce qui est écrit après n\'est retenu', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id, horloge: DateTime(2026, 6, 30, 10));
        final juin = cpbColonnesFeuillet(genre, '2026', DateTime(2026, 6, 30), m.collection('ecritures').actives);
        final fin = cpbColonnesFeuillet(genre, '2026', DateTime(2026, 10, 30), m.collection('ecritures').actives);
        expect(juin[0].nbLignes, lessThan(fin[0].nbLignes));
        expect(find.text('${res ? 'NET (1) — ' : ''}calculé — arrêté au 30/06/2026'), findsOneWidget);
        expect(find.textContaining('${juin[0].nbLignes} ligne(s) d’écriture validée(s) retenue(s)'), findsOneWidget);
      });

      casM14('impression : la pièce porte les colonnes N et N-1, les signatures, et la source de chaque colonne', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        await toucherM14(t, find.widgetWithText(BoutonSigh, res ? 'Imprimer le compte de résultat' : 'Imprimer le tableau des flux'));
        expect(find.text(res ? 'Compte de résultat' : 'Tableau des flux de trésorerie'), findsWidgets);
        expect(find.textContaining('Colonne N-1'), findsWidgets);
        expect(find.textContaining('La Directrice de l’Administration et des Finances'), findsWidgets);
      });

      casM14('aucune commande d\'écriture n\'existe : le feuillet se lit et s\'imprime', (t) async {
        final m = magasinComplet();
        await ouvrir(t, m, id);
        for (final k in ['Nouveau', 'Nouvelle écriture', 'Modifier', 'Archiver', 'Valider']) {
          expect(find.widgetWithText(BoutonSigh, k), findsNothing, reason: k);
        }
      });
    });
  }

  group('m12-compte-resultat : la lecture du formulaire et les contrôles', () {
    casM14('la marge commerciale (RG-02), l\'EBE et le résultat financier sont expliqués', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-compte-resultat');
      expect(find.textContaining('MARGE COMMERCIALE (XA) — RG-02'), findsOneWidget);
      expect(find.textContaining('EXCÉDENT BRUT D’EXPLOITATION (XD)'), findsOneWidget);
      expect(find.textContaining('RÉSULTAT FINANCIER (XF)'), findsOneWidget);
    });

    casM14('un compte de gestion SANS ligne du formulaire est NOMMÉ et non compté', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({
        'numero': 'OD-2026-99998', 'date': '2026-10-29', 'journal': 'OD', 'compte': '709000', 'debit': 0, 'credit': 777, 'statut': 'validee', 'origine': 'Saisie manuelle'
      });
      await ouvrir(t, m, 'm12-compte-resultat');
      expect(find.textContaining('1 compte(s) de gestion sans ligne du formulaire : 709000 (${money(777)})', findRichText: true), findsOneWidget);
    });
  });

  group('m12-flux-tresorerie : le contrôle du formulaire', () {
    casM14('exercice 2026 : trésorerie de classe 5 = trésorerie par les flux (ZH), les deux concordent', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-flux-tresorerie');
      final c = cpbColonnesFeuillet('flux', '2026', DateTime(2026, 10, 30), m.collection('ecritures').actives)[0];
      expect(c.ecart.abs(), lessThan(1));
      expect(find.textContaining('Contrôle : Trésorerie actif N - Trésorerie passif N'), findsOneWidget);
      expect(find.textContaining('Les deux concordent'), findsOneWidget);
      expect(find.text('Contrôle concordant'), findsOneWidget);
    });

    casM14('un mouvement que le tableau ne classe pas est NOMMÉ à l\'écran : l\'écart ne se corrige pas en silence', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({
        'numero': 'OD-2026-99997', 'date': '2026-10-29', 'journal': 'OD', 'compte': '521100', 'debit': 5000, 'credit': 0, 'statut': 'validee', 'origine': 'Saisie manuelle'
      });
      m.collection('ecritures').inserer({
        'numero': 'OD-2026-99997', 'date': '2026-10-29', 'journal': 'OD', 'compte': '131000', 'debit': 0, 'credit': 5000, 'statut': 'validee', 'origine': 'Saisie manuelle'
      });
      await ouvrir(t, m, 'm12-flux-tresorerie');
      expect(find.textContaining('131000 (${money(-5000)})', findRichText: true), findsOneWidget);
      expect(find.textContaining('Il se lève en complétant les écritures, pas en retouchant le tableau.'), findsOneWidget);
    });

    casM14('sans à-nouveaux, la trésorerie d\'ouverture vaut zéro et l\'écran renvoie au bilan d\'ouverture', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-flux-tresorerie');
      expect(find.textContaining('sans à-nouveaux (bilan d’ouverture), elle vaut zéro'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Bilan d’ouverture'), findsOneWidget);
    });
  });
}
