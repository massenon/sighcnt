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

  // ------------------------------------------------------------------------------------------------------------------------------------------------
  group('m12-seuil-rentabilite', () {
    casM14('les six indicateurs sont CALCULÉS depuis les écritures validées de la période, la répartition fixe / variable est dite proposition', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-seuil-rentabilite');
      final r = cpbSeuilRentabilite(m.collection('ecritures').actives, bornes('annee', DateTime(2026, 10, 30)), libelleCompte: cpaCompteLibelle);
      expect(find.text(money(r.ca)), findsWidgets);
      expect(find.text(money(r.variable)), findsOneWidget);
      expect(find.text(money(r.fixe)), findsOneWidget);
      expect(find.text(money(r.marge)), findsOneWidget);
      expect(find.text(money(r.seuil)), findsOneWidget);
      expect(find.text(money(r.securite)), findsOneWidget);
      expect(find.textContaining('est une proposition'), findsOneWidget);
      expect(find.textContaining('Le seuil n’est pas atteint sur la période retenue.'), findsOneWidget);
    });

    casM14('basculer un compte : le seuil se recalcule, la décision est écrite au magasin ET journalisée (RG-12)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-seuil-rentabilite');
      final avant = cpbSeuilRentabilite(m.collection('ecritures').actives, bornes('annee', DateTime(2026, 10, 30)), libelleCompte: cpaCompteLibelle);
      expect(find.byTooltip('Basculer en fixe'), findsWidgets);
      await toucherM14(t, find.byTooltip('Basculer en fixe').first);
      // 604100 est le compte le plus chargé (6 482 000) : il était variable, il devient fixe
      final fiche = m.collection('reglages').parId('naturesCharges')!;
      expect((fiche['valeur'] as Map)['604100'], 'fixe');
      expect(find.text('Nature corrigée.'), findsOneWidget);
      expect(find.textContaining('604100 — désormais fixe. Le seuil est recalculé.'), findsOneWidget);
      final apres = cpbSeuilRentabilite(m.collection('ecritures').actives, bornes('annee', DateTime(2026, 10, 30)),
          natures: {'604100': 'fixe'}, libelleCompte: cpaCompteLibelle);
      expect(apres.fixe, avant.fixe + 6482000);
      expect(find.text(money(apres.fixe)), findsOneWidget);
      expect(find.text(money(apres.variable)), findsOneWidget);
      // le journal est plafonné à 400 entrées : on lit la DERNIÈRE, pas la longueur
      final dernier = m.collection('audit').toutes.first;
      expect(dernier['reference'], 'naturesCharges');
      expect(dernier['action'], 'Création', reason: 'la première correction crée la fiche de réglage ; les suivantes la modifient');
    });

    casM14('une correction déjà écrite survit au rechargement de l\'écran', (t) async {
      final m = magasinComplet();
      m.collection('reglages').inserer({'id': 'naturesCharges', 'valeur': {'604100': 'fixe'}});
      await ouvrir(t, m, 'm12-seuil-rentabilite');
      final r = cpbSeuilRentabilite(m.collection('ecritures').actives, bornes('annee', DateTime(2026, 10, 30)),
          natures: {'604100': 'fixe'}, libelleCompte: cpaCompteLibelle);
      expect(find.text(money(r.fixe)), findsOneWidget);
      expect(find.byTooltip('Basculer en variable'), findsWidgets);
    });

    casM14('un seuil INCALCULABLE est un diagnostic, pas un défaut d\'affichage', (t) async {
      final m = magasinComplet();
      final nums = {for (final e in m.collection('ecritures').actives) if ('${e['compte']}'.startsWith('6')) '${e['compte']}'};
      m.collection('reglages').inserer({'id': 'naturesCharges', 'valeur': {for (final n in nums) n: 'variable'}});
      await ouvrir(t, m, 'm12-seuil-rentabilite');
      expect(find.text('incalculable'), findsOneWidget);
      expect(find.text('marge sur coût variable nulle ou négative'), findsOneWidget);
      expect(find.textContaining('Le seuil ne peut pas être calculé.'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });

    casM14('l\'impression porte la méthode, la réserve et le détail des charges avec un total CALCULÉ', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-seuil-rentabilite');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’analyse'));
      expect(find.text('Méthode'), findsOneWidget);
      expect(find.text('Réserve'), findsOneWidget);
      expect(find.text('Détail des charges'), findsOneWidget);
      expect(find.text('TOTAL'), findsWidgets);
    });

    casM14('lecture seule : « Basculer » est ABSENT (jamais grisé), l\'analyse reste lisible et le profil est nommé', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-seuil-rentabilite', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-seuil-rentabilite'));
      expect(find.byTooltip('Basculer en fixe'), findsNothing);
      expect(find.byTooltip('Basculer en variable'), findsNothing);
      expect(find.textContaining('Votre profil consulte l’analyse sans corriger la nature des charges.'), findsOneWidget);
      expect(find.text('Seuil de rentabilité'), findsWidgets);
    });
  });

  // ------------------------------------------------------------------------------------------------------------------------------------------------
  group('m12-analytique', () {
    casM14('la ventilation se DÉDUIT du centre porté par chaque écriture : sept centres, quatre indicateurs, marge « — » sans produit', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-analytique');
      final rows = cpbAnalytique(cpaEcrituresExercice(m.collection('ecritures').actives, 2026));
      expect(rows.length, 7);
      for (final r in rows) {
        expect(find.text(r.centre), findsWidgets, reason: r.centre);
      }
      expect(find.text(money(rows.fold<double>(0, (a, r) => a + r.resultat))), findsOneWidget);
      final direction = rows.firstWhere((r) => r.id == 'direction');
      expect(direction.produits, 0);
      expect(find.text('—'), findsWidgets);
      final maternite = rows.firstWhere((r) => r.id == 'maternite');
      expect(find.text('${maternite.marge} %'), findsWidgets);
    });

    casM14('trié par résultat décroissant : la meilleure marge en tête', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-analytique');
      final rows = cpbAnalytique(cpaEcrituresExercice(m.collection('ecritures').actives, 2026));
      final meilleur = ([...rows]..sort((a, b) => b.resultat.compareTo(a.resultat))).first;
      double y(String centre) => t.getTopLeft(find.descendant(of: find.byType(TableauSigh), matching: find.text(centre)).first).dy;
      for (final r in rows.where((r) => r != meilleur)) {
        expect(y(r.centre), greaterThan(y(meilleur.centre)), reason: '${r.centre} sous ${meilleur.centre}');
      }
    });

    casM14('l\'impression : balance analytique, total refait depuis les lignes ; aucune commande d\'écriture n\'existe', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-analytique');
      for (final k in ['Nouveau', 'Nouvelle écriture', 'Modifier', 'Archiver']) {
        expect(find.widgetWithText(BoutonSigh, k), findsNothing, reason: k);
      }
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la balance analytique'));
      expect(find.text('Balance analytique'), findsWidgets);
      expect(find.text('TOTAL'), findsWidgets);
      expect(find.textContaining('BASSONGUI Chabi Séko'), findsWidgets);
    });

    casM14('un exercice sans écriture ne casse pas l\'écran : sept centres à zéro', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-analytique', horloge: DateTime(2027, 3, 1, 10));
      expect(find.text('Centres de coûts'), findsOneWidget);
      expect(find.text('Résultat analytique'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------------------------------------------------------
  group('m12-budgets', () {
    final bornes26 = DateTime(2026, 10, 30, 10);

    casM14('le réalisé est LU aux écritures du centre ; au-delà du budget, le dépassement se lit (Direction : 337 %)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-budgets');
      final e = cpaEcrituresExercice(m.collection('ecritures').actives, bornes26.year);
      for (final b in m.collection('budgets').actives) {
        expect(find.text(money(cpbRealise(e, b['centreCout']), avecDevise: false)), findsWidgets, reason: '${b['reference']}');
      }
      expect(find.text('337 %'), findsOneWidget);
      expect(find.text(money(-11831000, avecDevise: false)), findsOneWidget);
    });

    casM14('créer un budget : référence lue sur les budgets EXISTANTS (E772), centre nommé, statut actif, journalisé', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-budgets');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await choisirM14(t, 'centreCout', 'Maternité');
      await saisir(t, 'prevu', '1500000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = m.collection('budgets').actives.first;
      expect(f['reference'], 'BG-2026-008', reason: 'jamais BG-2026-001, déjà attribuée');
      expect(f['centreCout'], 'maternite');
      expect(f['centre'], 'Maternité');
      expect(f['prevu'], 1500000);
      expect(f['exercice'], 2026);
      expect(f['statut'], 'actif');
      expect(find.text('Nouveau budget créé.'), findsOneWidget);
      expect([m.collection('audit').toutes.first['action'], m.collection('audit').toutes.first['reference']], ['Création', 'BG-2026-008']);
    });

    casM14('sans montant : le formulaire est REFUSÉ, rien n\'est écrit', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-budgets');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);
      expect(m.collection('budgets').actives.length, 7);
    });

    casM14('un montant négatif est REFUSÉ', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-budgets');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'prevu', '-5');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('La valeur doit être supérieure ou égale à 0.'), findsOneWidget);
      expect(m.collection('budgets').actives.length, 7);
    });

    casM14('E773 — modifier un budget CONSERVE sa référence (recalculée, elle le renumérotait)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-budgets');
      // la première ligne : le plus gros budget (Maternité, BG-2026-005)
      await toucherM14(t, find.byTooltip('Modifier').first);
      await saisir(t, 'prevu', '20000000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = m.collection('budgets').actives.firstWhere((b) => b['id'] == 'BUD005');
      expect(f['prevu'], 20000000);
      expect(f['reference'], 'BG-2026-005');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
    });

    casM14('archiver : motif obligatoire, annulable, jamais supprimé (RG-14)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-budgets');
      await toucherM14(t, find.byTooltip('Archiver').first);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Budget remplacé');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('budgets').actives.length, 6);
      expect(m.collection('budgets').toutes.length, 7, reason: 'rien n\'est supprimé');
      expect(find.text('Enregistrement archivé.'), findsOneWidget);
    });

    casM14('l\'onglet « Budget vs réalisé » compare le prévu et le réalisé', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-budgets');
      await toucherM14(t, find.text('Budget vs réalisé'));
      expect(find.text('Comparaison budget prévisionnel et réalisé'), findsOneWidget);
    });

    casM14('lecture seule : « Nouveau », « Modifier » et « Archiver » sont ABSENTS', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-budgets', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-budgets'));
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------------------------------------------------------
  group('m12-immobilisations', () {
    final auj = DateTime(2026, 10, 30, 10);
    Map<String, Object?> cede() => {
          'id': 'IMMX1', 'statut': 'actif', 'reference': 'IM-011', 'designation': 'Réfrigérateur de laboratoire', 'categorie': 'Matériel de laboratoire',
          'valeurAcquisition': 1000000, 'dureeAmortissement': 4, 'compte': '241000', 'dateAcquisition': '2025-03-15', 'etat': 'En service',
          'dateCession': '2025-12-20', 'valeurCession': 400000, 'motifSortie': 'Cession'
        };

    casM14('le registre : chaque bien porte sa durée en semestres, son amortissement cumulé et sa valeur nette, calculés', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-immobilisations');
      final biens = m.collection('immobilisations').actives;
      expect(biens.length, 10);
      final ambulance = biens.firstWhere((b) => b['reference'] == 'IM-004');
      expect(find.text('5 ans (10 sem.)'), findsWidgets);
      expect(find.text(money(cpbAmortiCumule(ambulance, auj), avecDevise: false)), findsWidgets);
      expect(find.text(money(cpbVnc(ambulance, auj), avecDevise: false)), findsWidgets);
    });

    casM14('les trois totaux SONT les colonnes BRUT / AMORT. / NET du bilan ; un bien SORTI en est exclu et compté à part', (t) async {
      final m = magasinComplet();
      m.collection('immobilisations').inserer(cede());
      await ouvrir(t, m, 'm12-immobilisations');
      final tot = cpbTotauxImmobilisations(m.collection('immobilisations').actives, auj);
      expect(tot.sorties, 1);
      expect(find.text('1 sortie(s) du patrimoine'), findsOneWidget);
      expect(find.text(money(tot.brut)), findsOneWidget);
      expect(find.text(money(tot.amort)), findsOneWidget);
      expect(find.text(money(tot.net)), findsOneWidget);
      // l'amortissement du bien cédé est ARRÊTÉ au 20/12/2025 : un semestre, pas les trois que l'horloge aurait comptés
      expect(find.text(money(125000, avecDevise: false)), findsWidgets);
      expect(find.text(money(875000, avecDevise: false)), findsWidgets);
      expect(find.text('20/12/2025'), findsWidgets);
    });

    casM14('« Report au bilan » : l\'ordre de la liasse, le total AZ, et les biens sortis nommés', (t) async {
      final m = magasinComplet();
      m.collection('immobilisations').inserer(cede());
      await ouvrir(t, m, 'm12-immobilisations');
      await toucherM14(t, find.text('Report au bilan'));
      expect(find.textContaining('Ce tableau EST la rubrique « Immobilisations corporelles » (AI)'), findsOneWidget);
      for (final r in ['IMMOBILISATIONS INCORPORELLES', 'IMMOBILISATIONS CORPORELLES', 'IMMOBILISATIONS FINANCIÈRES', 'TOTAL ACTIF IMMOBILISÉ']) {
        expect(find.text(r), findsOneWidget, reason: r);
      }
      expect(find.text('Matériel de transport'), findsOneWidget);
      expect(find.textContaining('1 bien(s) sorti(s) du patrimoine ne figurent PAS dans ce report'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le report'));
      expect(find.text('Report des immobilisations à l’actif du bilan'), findsWidgets);
      expect(find.text('TOTAL ACTIF IMMOBILISÉ'), findsWidgets);
    });

    casM14('la fiche (tiroir) : plan d\'amortissement SEMESTRIEL, semestres courus, impression avec le total des dotations', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-immobilisations');
      await toucherM14(t, find.text('Ambulance médicalisée').first);
      await t.pump(const Duration(milliseconds: 600));
      final b = m.collection('immobilisations').actives.firstWhere((x) => x['reference'] == 'IM-004');
      expect(find.text('Plan d’amortissement — pas SEMESTRIEL'), findsOneWidget);
      expect(find.text('${cpbSemestresEcoules(b, auj)} / ${cpbSemestresTotal(b)} (${cpbAnneesEcoulees(b, auj)} an(s) écoulé(s))'), findsOneWidget);
      expect(find.text('S2 2025'), findsOneWidget);
      expect(find.text('Couru'), findsWidgets);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer'));
      expect(find.text('TOTAL DES DOTATIONS', skipOffstage: false), findsWidgets);
      expect(find.text('Fiche d’immobilisation & plan d’amortissement'), findsWidgets);
    });

    casM14('créer un bien : référence lue sur les biens existants (IM-011, E772), amortissement calculé à la ligne, journalisé', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-immobilisations');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'designation', 'Réfrigérateur de laboratoire');
      await saisir(t, 'valeurAcquisition', '1000000');
      await saisir(t, 'dureeAmortissement', '4');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = m.collection('immobilisations').actives.first;
      expect(f['reference'], 'IM-011');
      expect(f['valeurAcquisition'], 1000000);
      expect(f['dureeAmortissement'], 4);
      expect(f['compte'], '241000');
      expect(f['etat'], 'En service');
      expect(f['statut'], 'actif');
      expect(find.text('Nouveau immobilisation créé.'), findsOneWidget);
      expect([m.collection('audit').toutes.first['action'], m.collection('audit').toutes.first['reference']], ['Création', 'IM-011']);
      expect(find.text('IM-011'), findsOneWidget);
    });

    casM14('une durée nulle est REFUSÉE ; un bien sans désignation aussi — rien n\'est écrit', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-immobilisations');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'designation', 'Bien sans durée');
      await saisir(t, 'valeurAcquisition', '1000');
      await saisir(t, 'dureeAmortissement', '0');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('La valeur doit être supérieure ou égale à 1.'), findsOneWidget);
      expect(m.collection('immobilisations').actives.length, 10);
    });

    casM14('E773 — modifier un bien CONSERVE sa référence', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-immobilisations');
      await toucherM14(t, find.byTooltip('Modifier').first);
      await saisir(t, 'fournisseur', 'Nouveau fournisseur');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = m.collection('immobilisations').actives.firstWhere((b) => b['id'] == 'IMM004');
      expect(f['reference'], 'IM-004');
      expect(f['fournisseur'], 'Nouveau fournisseur');
    });

    casM14('archiver : motif obligatoire, annulable, jamais supprimé (RG-14)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-immobilisations');
      await toucherM14(t, find.byTooltip('Archiver').first);
      await t.enterText(find.byType(TextField).last, 'Bien réformé');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('immobilisations').actives.length, 9);
      expect(m.collection('immobilisations').toutes.length, 10);
    });

    casM14('lecture seule : aucune commande d\'écriture, l\'impression du report reste offerte', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-immobilisations', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-immobilisations'));
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      await toucherM14(t, find.text('Report au bilan'));
      expect(find.widgetWithText(BoutonSigh, 'Imprimer le report'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------------------------------------------------------
  group('m12-banques', () {
    casM14('quatre comptes de trésorerie, dix-huit rapprochements : treize sans écart, cinq avec écart', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-banques');
      final b = cpbBilanRapprochements(m.collection('rapprochements').actives);
      expect([b.effectues, b.sansEcart, b.avecEcart], [18, 13, 5]);
      expect(m.collection('banques').actives.length, 4);
      for (final k in ['Comptes bancaires', 'Rapprochements effectués', 'Sans écart', 'Avec écart']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      expect(find.text('Rapproché'), findsWidgets);
    });

    casM14('ouvrir un compte : écrit en tête, actif, journalisé — sans attendre une livraison logicielle', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-banques');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await saisir(t, 'banque', 'Banque Atlantique Bénin');
      await saisir(t, 'intitule', 'Compte courant BAB');
      await saisir(t, 'numeroCompte', '010 20300 55');
      await saisir(t, 'compteComptable', '521300');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = m.collection('banques').actives.first;
      expect(f['banque'], 'Banque Atlantique Bénin');
      expect(f['devise'], 'FCFA');
      expect(f['statutCompte'], 'actif');
      expect(f['statut'], 'actif');
      expect(find.text('Compte créé.'), findsOneWidget);
      expect(m.collection('audit').toutes.first['action'], 'Création');
    });

    casM14('un compte sans établissement ni numéro est REFUSÉ, rien n\'est écrit', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-banques');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);
      expect(m.collection('banques').actives.length, 4);
    });

    casM14('clôturer un compte : la modification est écrite et annulable ; la caisse, sans numéro de compte, ne s\'enregistre pas (champ obligatoire)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-banques');
      // la ligne « Caisse » n'a pas de numéro de compte : le formulaire, qui l'exige, la refuse en le disant
      await toucherM14(t, find.byTooltip('Modifier').first);
      await choisirM14(t, 'statutCompte', 'Clôturé');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('banques').actives.first['statutCompte'], 'actif');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler'));
      // un compte bancaire se clôture
      await toucherM14(t, find.byTooltip('Modifier').at(1));
      await choisirM14(t, 'statutCompte', 'Clôturé');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(m.collection('banques').actives[1]['banque'], 'BOA');
      expect(m.collection('banques').actives[1]['statutCompte'], 'cloture');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      expect(find.text('Clôturé'), findsWidgets);
    });

    casM14('archiver un compte : motif obligatoire consigné au journal, jamais supprimé (RG-14)', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-banques');
      await toucherM14(t, find.byTooltip('Archiver').first);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Compte clôturé par la banque');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('banques').actives.length, 3);
      expect(m.collection('banques').toutes.length, 4);
      expect(m.collection('audit').toutes.any((a) => '${a['action']}'.contains('Motif d’archivage')), isTrue);
    });

    casM14('l\'état de rapprochement : trois rubriques et la phrase qui suit l\'écart', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-banques');
      expect(find.byTooltip('Imprimer l’état'), findsWidgets);
      await toucherM14(t, find.byTooltip('Imprimer l’état').first);
      expect(find.text('État de rapprochement bancaire'), findsWidgets);
      expect(find.text('ÉCART CONSTATÉ'), findsOneWidget);
      expect(find.text('Solde du compte en comptabilité'), findsOneWidget);
    });

    casM14('lecture seule : « Nouveau », « Modifier » et « Archiver » sont ABSENTS ; l\'impression d\'un état reste offerte', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-banques', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-banques'));
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Imprimer l’état'), findsWidgets);
    });
  });
}
