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

/// M12 — états financiers de synthèse (`m12-etats-financiers`) : les cinq feuillets de la liasse déposée. Les règles de calcul de la colonne « exercice en
/// cours » sont rejouées sur les vecteurs de l'écran réel (`packages/domaine/test/cpc_etats_test.dart`) ; ici, l'ÉCRAN : la parité N1, les cinq onglets, les
/// écarts internes CONSERVÉS, les pièces imprimées, et ce qui n'est JAMAIS corrigé.
Map<String, Object?> fiche(String id) =>
    (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

/// Le jeu complet PLUS des écritures validées de 2025 (exercice clos par la liasse : la garde les refuserait à l'écriture, elles entrent donc à
/// l'hydratation, comme un journal repris).
Magasin magasinAvec2025() {
  List<Fiche> lire(String n) =>
      [for (final f in jsonDecode(File('assets/donnees/jeu/$n.json').readAsStringSync()) as List) (f as Map).cast<String, Object?>()];
  final jeux = {for (final n in Magasin.collectionsDuJeu) n: lire(n)};
  jeux['ecritures'] = [
    for (final (i, x) in const [
      ['571000', 900000, 0],
      ['706000', 0, 900000],
      ['521000', 400000, 0],
      ['411000', 0, 400000],
    ].indexed)
      {'id': 'X25-$i', 'numero': 'E25-${i ~/ 2}', 'date': '2025-03-01', 'journal': 'OD', 'compte': x[0], 'debit': x[1], 'credit': x[2], 'statut': 'validee'},
    ...jeux['ecritures']!
  ];
  return Magasin(jeux, 'POSTE', (jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>());
}

/// Un onglet de l'écran (le ruban de la coque porte, lui aussi, des pastilles « Compte de résultat » ou « Flux de trésorerie » : on ne touche que l'onglet).
Future<void> onglet(WidgetTester t, String libelle) =>
    toucherM14(t, find.descendant(of: find.byType(OngletsSigh), matching: find.text(libelle)).first);

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final L = cpcLiasseDonnees;

  casM14('parité N1 : N1 = 100 %', (t) async {
    final m = magasinComplet();
    await ouvrirM14(t, m, 'm12-etats-financiers');
    final p = comparerContenu('m12-etats-financiers', fiche('m12-etats-financiers'), textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'm12-etats-financiers : ${p.presents}/${p.attendus}');
    expect(p.taux, 1.0);
  });

  group('l\'entête : ce que le dépôt dit', () {
    casM14('quatre indicateurs CITÉS de la liasse : CA, résultat net (et celui de N-1), total du bilan, six écarts internes', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      expect(find.text(money(190830994)), findsOneWidget);
      expect(find.text(money(4561200)), findsOneWidget);
      expect(find.text('N-1 : ${money(4472283)}'), findsOneWidget);
      expect(find.text(money(112937495)), findsOneWidget);
      expect(find.text('Actif = Passif — le bilan s’équilibre'), findsOneWidget);
      expect(find.text('6'), findsWidgets);
      expect(find.text('Signalés, jamais arbitrés'), findsOneWidget);
      expect(find.textContaining('Liasse CLINIQUE NASSIERA SARL, IFU 3201642748214, déposée le 15/05/2026 — code BK505416', findRichText: true), findsOneWidget);
      expect(find.textContaining('Direction Générale des Impôts, République du Bénin'), findsOneWidget);
    });
  });

  group('le bilan', () {
    casM14('les références, libellés et ordre du formulaire : AD, AI… à l\'actif, CA, CP… au passif', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      expect(find.text('BILAN — ACTIF (feuillet 5/51)'), findsOneWidget);
      expect(find.text('BILAN — PASSIF (feuillet 6/51)'), findsOneWidget);
      for (final x in ['IMMOBILISATIONS CORPORELLES', 'Terrains', 'Bâtiments', 'TOTAL CAPITAUX PROPRES ET RESSOURCES ASSIMILÉES']) {
        expect(find.text(x), findsWidgets, reason: x);
      }
      for (final r in ['AD', 'AI', 'BZ', 'CA', 'CP', 'DZ']) {
        expect(find.text(r), findsWidgets, reason: 'référence $r');
      }
      expect(find.text('BRUT 2025'), findsOneWidget);
      expect(find.text('NET 2024'), findsNWidgets(2));
      expect(find.textContaining('Le bilan déposé s’équilibre : total général de l’actif ${money(112937495)} = total général du passif ${money(112937495)}.', findRichText: true),
          findsOneWidget);
      // le dépôt se CITE tel quel, y compris ses zéros
      expect(find.text(money(180151372, avecDevise: false)), findsWidgets);
      expect(find.text(money(100066531, avecDevise: false)), findsWidgets);
    });

    casM14('la colonne « Exercice en cours » est CALCULÉE : « Clients » porte le solde débiteur du journal, une ligne que le journal n\'alimente pas reste « — »', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      final courant = cpcSourceExercice(m.collection('exercices').toutes, m.collection('ecritures').actives, 2026);
      final clients = L.ligne(L.bilanActif, 'BI')!;
      final v = cpcCalculActif(clients, courant)!;
      expect(v, 7397000);
      expect(find.text(money(v, avecDevise: false)), findsWidgets);
      expect(find.text('—'), findsWidgets);
      expect(find.text('EXERCICE EN COURS'), findsNWidgets(2));
      expect(find.text('EXERCICE 2025 (JOURNAL)'), findsNothing, reason: '2025 est clos par la liasse : le journal 2026 n\'a pas de précédent');
    });

    casM14('un journal qui porte 2025 : la colonne « Exercice 2025 (journal) » paraît à l\'actif ET au passif', (t) async {
      final m = magasinAvec2025();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      expect(find.text('EXERCICE 2025 (JOURNAL)'), findsNWidgets(2));
      final prec = cpcSourceExercice(m.collection('exercices').toutes, m.collection('ecritures').actives, 2025);
      expect(prec, hasLength(4));
      expect(cpcCalculActif(L.ligne(L.bilanActif, 'BS')!, prec), 1300000, reason: 'banque + caisse');
      expect(find.text(money(1300000, avecDevise: false)), findsWidgets);
    });

    casM14('un compte de tiers change de côté : un client créditeur paraît au PASSIF, jamais en négatif à l\'actif', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({'numero': 'T1', 'date': '2026-06-01', 'journal': 'OD', 'compte': '411000', 'debit': 0, 'credit': 9000000, 'statut': 'validee'});
      m.collection('ecritures').inserer({'numero': 'T1', 'date': '2026-06-01', 'journal': 'OD', 'compte': '571000', 'debit': 9000000, 'credit': 0, 'statut': 'validee'});
      await ouvrirM14(t, m, 'm12-etats-financiers');
      final courant = cpcSourceExercice(m.collection('exercices').toutes, m.collection('ecritures').actives, 2026);
      final actif = L.ligne(L.bilanActif, 'BI')!;
      expect(cpcCalculActif(actif, courant), isNull);
      expect(cpcCalculPassif({'comptes': actif['comptes']}, courant), isNotNull);
      expect(find.text('-${money(9000000, avecDevise: false)}'), findsNothing);
      expect(find.text(money(1603000, avecDevise: false)), findsNothing);
    });

    casM14('la note de lecture le dit : le compte de tiers y paraît du côté où son solde le place', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      expect(find.textContaining('Un compte de tiers y paraît du côté où son solde le place', findRichText: true), findsOneWidget);
      expect(find.textContaining('Elle reste vide là où le journal ne porte rien', findRichText: true), findsOneWidget);
    });
  });

  group('les quatre autres feuillets', () {
    casM14('compte de résultat : la marge commerciale NULLE confirme RG-02 ; les charges en négatif', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      await onglet(t, 'Compte de résultat');
      expect(find.text('COMPTE DE RÉSULTAT (feuillet 7/51)'), findsOneWidget);
      expect(find.text('Ventes de marchandises'), findsOneWidget);
      expect(find.text('MARGE COMMERCIALE (Somme TA à RB)'), findsOneWidget);
      expect(find.textContaining('La marge commerciale est nulle à la liasse déposée', findRichText: true), findsOneWidget);
      expect(find.text('-2${' '}415${' '}000'), findsOneWidget, reason: 'les charges du journal en négatif : la convention du formulaire');
    });

    casM14('flux de trésorerie : trois écarts internes CONSERVÉS, non arbitrés, nommés ; ZB porte toujours −18 108 317', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      await onglet(t, 'Tableau des flux de trésorerie');
      expect(find.text('TABLEAU DES FLUX DE TRÉSORERIE (feuillet 8/51)'), findsOneWidget);
      expect(find.text('Écarts internes du document déposé — conservés, non arbitrés'), findsOneWidget);
      expect(find.text('écart du document'), findsNWidgets(2), reason: 'deux lignes du tableau portent le badge ; trois écarts sont détaillés dessous');
      expect(find.text('Flux des activités opérationnelles (ZB)'), findsOneWidget);
      expect(find.text(money(-18108317, avecDevise: false)), findsOneWidget);
      expect(find.textContaining('les corriger ici ferait diverger le logiciel de ce que la clinique a réellement déposé', findRichText: true), findsOneWidget);
      expect(find.text('FLUX DE TRÉSORERIE PROVENANT DES ACTIVITÉS OPÉRATIONNELLES'), findsOneWidget);
    });

    casM14('disponibilités : note 11, variation en % sur |N-1|, négatif accepté, commentaires du formulaire', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      await onglet(t, 'Disponibilités');
      expect(find.text('NOTE 11 : DISPONIBILITÉS (feuillet 25/51)'), findsOneWidget);
      expect(find.text('Banques locales'), findsOneWidget);
      expect(find.text('89.56 %'), findsOneWidget);
      expect(find.text('-${money(3220000, avecDevise: false)}'), findsOneWidget);
      expect(find.text('Commentaires demandés par le formulaire'), findsOneWidget);
      expect(find.textContaining('Indiquer la date de rapprochement des comptes bancaires.'), findsOneWidget);
    });

    casM14('fiche de synthèse : note 34, variation en %, quatre écarts internes (CAFG, flux, trésorerie à 450 F près)', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      await onglet(t, 'Fiche de synthèse');
      expect(find.text('NOTE 34 : FICHE DE SYNTHÈSE DES PRINCIPAUX INDICATEURS FINANCIERS (feuillet 51/51)'), findsOneWidget);
      expect(find.text('7.72 %'), findsOneWidget);
      expect(find.text('Notes du formulaire'), findsOneWidget);
      expect(find.textContaining('450 F d’écart'), findsOneWidget);
      expect(find.text('Trésorerie nette'), findsOneWidget);
      expect(find.textContaining('(b) Les écarts de conversion doivent être éliminés'), findsOneWidget);
    });
  });

  group('l\'impression : cinq pièces, un cartouche du dépôt, trois signatures', () {
    for (final (bouton, titre, contient) in [
      ('Imprimer le bilan', 'Bilan', 'Contrôle : total général de l’actif'),
      ('Compte de résultat', 'Compte de résultat', 'Résultat net de l’exercice'),
      ('Flux de trésorerie', 'Tableau des flux de trésorerie', 'Écarts internes du document déposé, conservés et non arbitrés'),
      ('Disponibilités', 'NOTE 11 : DISPONIBILITÉS', 'figurent dans cette rubrique en négatif'),
      ('Fiche de synthèse', 'Fiche de synthèse des principaux indicateurs financiers', '(a) Résultat d’exploitation après impôt théorique'),
    ]) {
      casM14('« $bouton » : la pièce porte le code de dépôt et ses signatures', (t) async {
        final m = magasinComplet();
        await ouvrirM14(t, m, 'm12-etats-financiers');
        await toucherM14(t, find.widgetWithText(BoutonSigh, bouton));
        expect(find.text(titre), findsWidgets);
        expect(find.textContaining('BK505416', findRichText: true), findsWidgets);
        expect(find.textContaining(contient, findRichText: true), findsWidgets);
        expect(find.textContaining('KASSA Augustin', findRichText: true), findsWidgets);
        expect(find.textContaining('TAKI Alimatou', findRichText: true), findsWidgets);
        expect(find.textContaining('BASSONGUI Chabi Séko', findRichText: true), findsWidgets);
      });
    }

    casM14('« Immobilisations » renvoie au registre ; aucune commande d\'écriture sur cet écran de lecture', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-etats-financiers');
      expect(find.widgetWithText(BoutonSigh, 'Immobilisations'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
    });
  });
}
