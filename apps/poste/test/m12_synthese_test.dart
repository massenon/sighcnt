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

/// M12 — suivi et références : m12-echeances, m12-baseline-2025. Les règles sont rejouées sur les vecteurs de la maquette
/// (`packages/domaine/test/cpc_echeances_test.dart`) ; ici, l'ÉCRAN : la parité N1, puis ce qui est lu, validé, annulé, refusé, journalisé — et ce qui
/// n'est JAMAIS offert sans le droit.
Map<String, Object?> fiche(String id) =>
    (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

/// Choisit la valeur [valeur] (l'identifiant de l'option, pas son libellé) du filtre [libelle] du tableau : un `PopupMenuButton` dont l'infobulle est le
/// libellé du filtre. On déclenche son `onSelected`, comme le fait le toucher d'une entrée du menu.
Future<void> filtrer(WidgetTester t, String libelle, String valeur) async {
  final f = find.byWidgetPredicate((w) => w is PopupMenuButton<String> && w.tooltip == libelle);
  t.widget<PopupMenuButton<String>>(f).onSelected!(valeur);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité N1', () {
    for (final id in ['m12-echeances', 'm12-baseline-2025']) {
      casM14('$id : N1 = 100 %', (t) async {
        final m = magasinComplet();
        await ouvrirM14(t, m, id);
        final p = comparerContenu(id, fiche(id), textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
        expect(p.taux, 1.0);
      });
    }
  });

  group('m12-echeances', () {
    casM14('quatre indicateurs CALCULÉS, la barre de notification NOMME les retards, l\'alerte part 800 ms après l\'ouverture', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-echeances');
      final lignes = cpcLignesEcheances(m.collection('echeancesFiscales').actives, aujourdhui);
      final retard = lignes.where((l) => l['etat'] == 'en_retard').length;
      expect(retard, 13);
      for (final k in ['En retard', 'À payer sous 10 jours', 'Déclarations attendues', 'Réglées sur l’exercice']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      expect(find.text('Risque de pénalité'), findsOneWidget);
      expect(find.text('63 échéances au total'), findsOneWidget);
      expect(find.text('13 échéance(s) dépassée(s) et non réglée(s)'), findsOneWidget);
      expect(find.textContaining('ITS — 10/08/2026 (81 j de retard)'), findsOneWidget);
      expect(find.text('4 déclaration(s) à préparer'), findsOneWidget);
      // l'alerte de l'ouverture
      await t.pump(const Duration(milliseconds: 900));
      expect(find.text('13 échéance(s) en retard'), findsOneWidget);
      expect(find.text('Impôt sur les traitements salariaux — 10/08/2026'), findsOneWidget);
    });

    casM14('le tableau : état calculé, délai, report au jour ouvrable ; le filtre « En retard » ne garde que les retards', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-echeances');
      expect(find.text('Échéances de l’exercice 2026'), findsOneWidget);
      expect(find.text('reportée — jour ouvrable'), findsWidgets);
      expect(find.text('Payée'), findsWidgets);
      expect(find.text('KASSA Augustin'), findsWidgets);
      await filtrer(t, 'État', 'en_retard');
      expect(find.textContaining('j de retard'), findsWidgets);
      expect(find.text('Payée'), findsNothing);
      expect(find.text('Affichage de 1 à 13 sur 13 enregistrements'), findsOneWidget);
    });

    casM14('VALIDER UN PAIEMENT : le formulaire refuse en nommant, puis la quittance est écrite, journalisée (RG-12), annulable', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-echeances');
      await filtrer(t, 'État', 'en_retard');
      final premier = m.collection('echeancesFiscales').actives.firstWhere((e) => cpcCalculerEtat(e, aujourdhui) == 'en_retard');
      await toucherM14(t, find.byTooltip('Valider le paiement effectué').first);
      expect(find.text('Valider le paiement — ${premier['code']}'), findsOneWidget);
      expect(find.textContaining('Échéance dépassée de 81 jour(s)'), findsOneWidget);
      // sans montant ni référence : refusé, rien n'est écrit
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Confirmer le paiement'));
      expect(m.collection('echeancesFiscales').parId(premier['id'])!['paye'], isNot(true));
      await saisir(t, 'montant', '0');
      await saisir(t, 'reference', 'QUIT-TEST-0001');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Confirmer le paiement'));
      expect(find.text('La valeur minimale est 1.'), findsOneWidget);
      expect(m.collection('echeancesFiscales').parId(premier['id'])!['paye'], isNot(true));
      await saisir(t, 'montant', '125000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Confirmer le paiement'));
      final e = m.collection('echeancesFiscales').parId(premier['id'])!;
      expect(e['paye'], true);
      expect(e['montant'], 125000);
      expect(e['reference'], 'QUIT-TEST-0001');
      expect(e['moyen'], 'Virement bancaire');
      expect(e['datePaiement'], '2026-10-30');
      expect(e['valideePar'], isNotEmpty);
      expect(m.collection('audit').toutes.map((a) => a['action']).take(3), contains('Paiement fiscal validé'));
      expect(find.text('${premier['code']} — paiement de ${money(125000)} validé.'), findsOneWidget);
      expect(find.text('Quittance QUIT-TEST-0001'), findsOneWidget);
      // annuler le toast rend l'échéance due
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler').last);
      expect(m.collection('echeancesFiscales').parId(premier['id'])!['paye'], isNot(true), reason: 'l\'annulation du toast restitue l\'état d\'avant');
    });

    casM14('ANNULER la validation exige un motif, remet l\'échéance DUE, et garde la trace du paiement au journal', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-echeances');
      await filtrer(t, 'État', 'payee');
      final cible = m.collection('echeancesFiscales').actives.firstWhere((e) => e['paye'] == true);
      await toucherM14(t, find.byTooltip('Annuler la validation').first);
      expect(find.text('Annuler la validation du paiement ${cible['code']} ?'), findsOneWidget);
      final audit = m.collection('audit').toutes.length;
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler la validation'));
      expect(m.collection('echeancesFiscales').parId(cible['id'])!['paye'], true, reason: 'sans motif : rien ne change');
      await t.enterText(find.byType(TextField).last, 'Paiement saisi sur la mauvaise échéance');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler la validation'));
      final apres = m.collection('echeancesFiscales').parId(cible['id'])!;
      expect(apres['paye'], false);
      expect(apres['reference'], isNull);
      expect(apres['valideePar'], isNull);
      expect(apres['motifAnnulation'], 'Paiement saisi sur la mauvaise échéance');
      expect(m.collection('audit').toutes.length, greaterThanOrEqualTo(audit));
      expect(m.collection('audit').toutes.first['action'], 'Modification');
    });

    casM14('la quittance imprimée porte l\'obligation, la base réglementaire et la référence', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-echeances');
      await filtrer(t, 'État', 'payee');
      await toucherM14(t, find.byTooltip('Éditer la quittance').first);
      expect(find.text('Justificatif de paiement — obligation fiscale'), findsWidgets);
      expect(find.text('Base réglementaire'), findsOneWidget);
      expect(find.text('Référence de quittance'), findsOneWidget);
      expect(find.text('QUIT-ITS-2026'), findsWidgets);
    });

    casM14('le tiroir d\'une échéance due propose de valider ; celui d\'une échéance payée, la quittance', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-echeances');
      await filtrer(t, 'État', 'en_retard');
      await toucherM14(t, find.text('ITS').first);
      expect(find.text('Part'), findsWidgets);
      expect(find.text('Déclaration préalable'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Valider le paiement'), findsWidgets);
      expect(find.text('Éditer la quittance'), findsNothing);
    });

    casM14('un rappel s\'annonce : échéance, déclaration préalable et nombre de jours de retard', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-echeances');
      await filtrer(t, 'État', 'en_retard');
      await toucherM14(t, find.byTooltip('Rappeler cette échéance').first);
      expect(find.textContaining('Rappel — Impôt sur les traitements salariaux'), findsOneWidget);
      expect(find.text('Échéance du 10/08/2026 · Déclaration mensuelle avant paiement · dépassée de 81 jour(s)'), findsOneWidget);
    });

    casM14('tout est réglé : la barre le DIT (plus de « undefined », E804) et aucune alerte ne part', (t) async {
      final m = magasinComplet();
      for (final e in m.collection('echeancesFiscales').actives) {
        m.collection('echeancesFiscales').mettreAJour(e['id'], {'paye': true});
      }
      await ouvrirM14(t, m, 'm12-echeances');
      await t.pump(const Duration(milliseconds: 900));
      expect(find.text('Aucune échéance en attente immédiate'), findsOneWidget);
      expect(find.text('Toutes les échéances de l’exercice sont réglées.'), findsOneWidget);
      expect(find.textContaining('undefined'), findsNothing);
      expect(find.textContaining('en retard'), findsNothing);
    });

    casM14('en lecture seule : ni « Valider le paiement », ni « Annuler la validation » — ABSENTS ; rappel et quittance restent', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-echeances', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-echeances'));
      expect(find.widgetWithText(BoutonSigh, 'Valider le paiement'), findsNothing);
      expect(find.byTooltip('Valider le paiement effectué'), findsNothing);
      expect(find.byTooltip('Annuler la validation'), findsNothing);
      expect(find.byTooltip('Éditer la quittance'), findsWidgets);
      await filtrer(t, 'État', 'en_retard');
      expect(find.byTooltip('Rappeler cette échéance'), findsWidgets);
    });
  });

  group('m12-baseline-2025', () {
    casM14('huit indicateurs : le résultat 2025 CITE le classeur (190 830 994 − 160 264 063)', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-baseline-2025');
      final e = cpcExercice2025;
      expect(find.text(money(e.totalChiffreAffaires)), findsWidgets);
      expect(find.text(money(e.totalCharges)), findsWidgets);
      expect(find.text(money(e.resultat)), findsWidgets);
      expect(find.text('16.0\u00A0% du chiffre d’affaires'), findsOneWidget);
      expect(find.text('octobre'), findsOneWidget);
      expect(find.text('janvier'), findsOneWidget);
      expect(find.text('Emprunt, cautionnements, immobilisation'), findsOneWidget);
    });

    casM14('le DIAGNOSTIC est calculé : 141 667 FCFA est l\'échéance mensuelle du FONDS DE GARANTIE omise par la ligne TOTAL', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-baseline-2025');
      expect(find.textContaining('Écart de ${money(141667)}', findRichText: true), findsOneWidget);
      expect(find.textContaining('l’écart n’est pas un arrondi', findRichText: true), findsOneWidget);
      expect(find.textContaining('« FONDS DE GARANTIE » (novembre et décembre)', findRichText: true), findsOneWidget);
      expect(find.textContaining('c’est elle qui est fautive, non le détail', findRichText: true), findsOneWidget);
      expect(find.textContaining('la correction porte sur le document source, pas sur le logiciel', findRichText: true), findsOneWidget);
    });

    casM14('trois postes sans compte : un rattachement PROPOSÉ avec son motif — jamais une imputation appliquée', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-baseline-2025');
      expect(find.textContaining('3 poste(s) de dépense sans numéro de compte', findRichText: true), findsOneWidget);
      expect(find.textContaining('c’est une proposition à valider par le service comptable', findRichText: true), findsOneWidget);
      for (final c in ['275000', '631800', '646800']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
      expect(find.text('Dépôts et cautionnements versés'), findsOneWidget);
      // rien n'a été imputé : les écritures du jeu n'ont pas bougé
      expect(m.collection('ecritures').actives.any((e) => e['origine'] == 'Rattachement proposé'), false);
    });

    casM14('postes de charges : classés par poids, hors postes de bilan ; l\'onglet porte le décompte', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-baseline-2025');
      await toucherM14(t, find.textContaining('Postes de charges').last);
      expect(find.text('Personnel externe'), findsWidgets);
      expect(find.text('À rattacher'), findsWidgets);
      expect(find.text('34.2\u00A0%'), findsOneWidget);
      expect(find.text('Emprunt'), findsNothing);
    });

    casM14('comparaison : le chiffre d\'affaires 2026 se lit sur les factures du jeu, l\'écart est signé', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-baseline-2025');
      await toucherM14(t, find.text('Comparaison 2025 / 2026'));
      final c = cpcComparaison(cpcExercice2025, m.collection('factures').actives);
      expect(find.textContaining('L’exercice 2026 est alimenté par le jeu de démonstration'), findsOneWidget);
      expect(find.text(money(c.first.ca2026, avecDevise: false)), findsWidgets);
      expect(find.text('${c.first.evolution} %'), findsWidgets);
    });

    casM14('l\'impression porte le compte de résultat 2025 avec ses TOTAUX CALCULÉS', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-baseline-2025');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le compte de résultat 2025'));
      expect(find.text('Compte de résultat — exercice 2025'), findsWidgets);
      expect(find.text('TOTAL 2025'), findsOneWidget);
      expect(find.text('Postes de charges'), findsWidgets);
      expect(find.text('(à rattacher)'), findsWidgets);
    });
  });
}
