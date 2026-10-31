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

/// M12 — exercices et clôture : m12-cloture, m12-ouverture. Les règles (pré-clôture, deux gestes, à-nouveaux, lettrage, empreinte) sont rejouées sur les
/// vecteurs de la maquette dans `packages/domaine/test/cpc_exercice_test.dart` ; ici, l'ÉCRAN : la parité N1, puis ce qui est lu, demandé, validé,
/// refusé, écrit, journalisé — et ce qui n'est JAMAIS offert sans le droit.
Map<String, Object?> fiche(String id) =>
    (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

void validerBrouillons(Magasin m) {
  for (final e in m.collection('ecritures').actives) {
    if (e['statut'] == 'brouillon') m.collection('ecritures').mettreAJour(e['id'], {'statut': 'validee'});
  }
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité N1', () {
    for (final id in ['m12-cloture', 'm12-ouverture']) {
      casM14('$id : N1 = 100 %', (t) async {
        final m = magasinComplet();
        await ouvrirM14(t, m, id);
        final p = comparerContenu(id, fiche(id), textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
        expect(p.taux, 1.0);
      });
    }
  });

  group('m12-cloture', () {
    casM14('quatre indicateurs CALCULÉS : les brouillons du jeu BLOQUENT, le résultat provisoire se lit sur les écritures validées', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-cloture');
      final pre = cpcPreCloture(m.collection('ecritures').actives, 2026);
      expect(pre.bloquants.map((c) => c.id), ['brouillons']);
      expect(find.text('Exercice affiché'), findsOneWidget);
      expect(find.text('Ouvert'), findsWidgets);
      expect(find.text(money(pre.resultat)), findsOneWidget);
      expect(find.text('Contrôles bloquants en échec'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      // les exercices de la liasse déposée sont CLOS d'office : ni pré-clôture ni validation
      expect(find.text('Exercice 2025'), findsOneWidget);
      expect(find.text('Liasse déposée à la DGI — 15/05/2026'), findsNWidgets(2));
      expect(find.widgetWithText(BoutonSigh, 'Pré-clôture'), findsOneWidget, reason: 'seul 2026 est ouvert');
    });

    casM14('la pré-clôture NOMME le contrôle en échec et l\'écran où corriger ; sans blocage, elle propose la demande — au comptable seulement', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-cloture', role: 'comptable');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Pré-clôture'));
      expect(find.text('Pré-clôture — exercice 2026'), findsOneWidget);
      expect(find.text('ÉCHEC'), findsOneWidget);
      expect(find.textContaining('92 ligne(s) en brouillon'), findsOneWidget);
      expect(find.textContaining('→ Écritures comptables'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Demander la clôture'), findsNothing, reason: 'un contrôle bloquant en échec : la commande est ABSENTE');
    });

    casM14('un rôle qui ne demande pas (la Direction valide, elle ne demande pas) ne voit jamais « Demander la clôture », même sans blocage', (t) async {
      final m = magasinComplet();
      validerBrouillons(m);
      await ouvrirM14(t, m, 'm12-cloture', role: 'direction');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Pré-clôture'));
      expect(find.text('Conforme'), findsNWidgets(6));
      expect(find.widgetWithText(BoutonSigh, 'Demander la clôture'), findsNothing);
    });

    casM14('LES DEUX GESTES : le comptable demande (notification à la Direction, journal), la Direction valide, l\'exercice se FIGE', (t) async {
      final m = magasinComplet();
      validerBrouillons(m);
      await ouvrirM14(t, m, 'm12-cloture', role: 'comptable');
      expect(find.widgetWithText(BoutonSigh, 'Valider la clôture'), findsNothing, reason: 'signer n\'est pas saisir');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Pré-clôture'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Demander la clôture'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Demander la clôture').last);
      var x = m.collection('exercices').actives.firstWhere((e) => e['annee'] == 2026);
      expect(x['etat'], 'en_attente_cloture');
      expect(x['demandePar'], isNotEmpty);
      expect(m.collection('notifications').actives.first['poste'], 'direction');
      expect(m.collection('notifications').actives.first['libelle'], 'Clôture 2026 à valider');
      expect(m.collection('audit').actives.any((a) => a['action'] == 'Demande de clôture'), true);
      expect(find.text('Clôture 2026 demandée.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));

      // la Direction rouvre l'écran : l'exercice attend
      await ouvrirM14(t, m, 'm12-cloture', role: 'direction');
      expect(find.text('En attente de clôture'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider la clôture'));
      expect(find.text('Valider la clôture de l’exercice 2026'), findsOneWidget);
      // sans motif : refusé, nommé, rien n'est écrit
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider et clôturer'));
      expect(find.text('Clôture refusée.'), findsOneWidget);
      expect(find.text('Un motif est obligatoire pour valider une clôture.'), findsOneWidget);
      expect(m.collection('ecritures').actives.where((e) => e['numero'] == 'OD-2026-RES'), isEmpty);
      await t.pump(const Duration(seconds: 10));
      await saisir(t, 'motif', 'Exercice 2026 conforme');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider et clôturer'));
      x = m.collection('exercices').actives.firstWhere((e) => e['annee'] == 2026);
      expect(x['etat'], 'clos');
      expect(x['validePar'], isNot(x['demandePar']));
      expect(x['empreinte'], hasLength(64));
      expect(x['motif'], 'Exercice 2026 conforme');
      expect(m.collection('exercices').actives.any((e) => e['annee'] == 2027 && e['etat'] == 'ouvert'), true);
      final od = m.collection('ecritures').actives.where((e) => e['numero'] == 'OD-2026-RES').toList();
      final an = m.collection('ecritures').actives.where((e) => e['journal'] == 'AN' && e['date'] == '2027-01-01').toList();
      expect(od, isNotEmpty);
      expect(an, hasLength(102));
      double s(List<Fiche> l, String k) => l.fold(0.0, (a, e) => a + (e[k] as num));
      expect(s(od, 'debit'), s(od, 'credit'), reason: 'RG-10 : la pièce de résultat est équilibrée');
      expect(s(an, 'debit'), s(an, 'credit'), reason: 'RG-10 : les à-nouveaux sont équilibrés');
      expect(m.collection('notifications').actives.first['libelle'], 'Exercice 2026 clos');
      expect(m.collection('audit').actives.any((a) => a['action'] == 'Clôture d’exercice'), true);
      expect(find.text('Exercice 2026 clos.'), findsOneWidget);

      // LA GARDE : l'exercice clos refuse toute écriture, d'où qu'elle vienne — au moteur, pas au bouton
      expect(
          () => m.collection('ecritures').inserer({'numero': 'T-9', 'date': '2026-07-01', 'journal': 'OD', 'compte': '411100', 'debit': 10, 'credit': 0, 'statut': 'brouillon'}),
          throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', startsWith('Exercice 2026 clos le 30/10/2026 — lecture seule.'))));
      expect(m.collection('audit').toutes.first['action'], 'Écriture refusée', reason: 'le refus est journalisé (RG-12), en tête du journal');
      expect(m.collection('audit').toutes.first['module'], '—');
      expect(() => m.collection('ecritures').mettreAJour(od.first['id'], {'libelle': 'Retouche'}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection('ecritures').archiver(od.first['id']), throwsA(isA<EcritureRefusee>()));
      await t.pump(const Duration(seconds: 10));
    });

    casM14('JAMAIS le demandeur : « Signer n\'est pas saisir » — la même personne ne valide pas sa propre demande', (t) async {
      final m = magasinComplet();
      validerBrouillons(m);
      await ouvrirM14(t, m, 'm12-cloture', role: 'da');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Pré-clôture'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Demander la clôture'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Demander la clôture').last);
      await t.pump(const Duration(seconds: 10));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider la clôture'));
      await saisir(t, 'motif', 'Conforme');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider et clôturer'));
      expect(find.text('Clôture refusée.'), findsOneWidget);
      expect(find.textContaining('Signer n’est pas saisir'), findsOneWidget);
      expect(m.collection('exercices').actives.firstWhere((e) => e['annee'] == 2026)['etat'], 'en_attente_cloture');
    });

    casM14('un exercice clos par le poste imprime son procès-verbal ; l\'empreinte est tronquée à 32 caractères', (t) async {
      final m = magasinComplet();
      validerBrouillons(m);
      m.collection('exercices').mettreAJour('EXO-2026', {'etat': 'clos', 'resultat': -23087218, 'demandePar': 'A', 'validePar': 'B', 'valideLe': '2026-10-30T10:00:00.000Z', 'empreinte': 'a' * 64});
      await ouvrirM14(t, m, 'm12-cloture');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Procès-verbal'));
      expect(find.text('Procès-verbal de clôture — exercice 2026'), findsWidgets);
      expect(find.textContaining('${'a' * 32}…'), findsOneWidget);
      expect(find.text('Résultat net'), findsWidgets);
    });

    casM14('périodes : douze mois, l\'équilibre et les brouillons par mois', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-cloture');
      await toucherM14(t, find.text('Périodes de l’exercice'));
      expect(find.text('Périodes comptables — exercice 2026'), findsOneWidget);
      for (final mois in ['Janvier 2026', 'Octobre 2026', 'Décembre 2026']) {
        expect(find.text(mois), findsOneWidget);
      }
      expect(find.text('Équilibrée'), findsWidgets);
    });

    casM14('lettrage : un ensemble qui ne s\'annule pas est REFUSÉ en le chiffrant ; un ensemble qui s\'annule se lettre, puis se dé-lettre avec un motif', (t) async {
      final m = magasinComplet();
      final col = m.collection('ecritures');
      for (final l in [
        ['L1', 5000, 0],
        ['L2', 0, 5000],
        ['L3', 0, 3000]
      ]) {
        col.inserer({
          'id': l[0], 'numero': 'LT-${l[0]}', 'date': '2026-06-01', 'journal': 'OD', 'compte': '401000', 'compteLibelle': 'Fournisseurs',
          'libelle': 'Test ${l[0]}', 'debit': l[1], 'credit': l[2], 'statut': 'validee'
        });
      }
      await ouvrirM14(t, m, 'm12-cloture');
      await toucherM14(t, find.text('Lettrage des tiers'));
      expect(find.text('Lignes du compte 401000'), findsOneWidget);
      // L1 + L3 : ne s'annule pas
      await toucherM14(t, find.byKey(const Key('lettrage:L1')));
      await toucherM14(t, find.byKey(const Key('lettrage:L3')));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Lettrer la sélection'));
      expect(find.text('Lettrage refusé.'), findsOneWidget);
      expect(find.textContaining('l’ensemble ne s’annule pas (écart ${money(2000)})'), findsOneWidget);
      expect(col.parId('L1')!['lettrage'], isNull);
      await t.pump(const Duration(seconds: 10));
      // L1 + L2 : s'annule
      await toucherM14(t, find.byKey(const Key('lettrage:L3')));
      await toucherM14(t, find.byKey(const Key('lettrage:L2')));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Lettrer la sélection'));
      expect(col.parId('L1')!['lettrage'], 'A');
      expect(col.parId('L2')!['lettrage'], 'A');
      expect(col.parId('L3')!['lettrage'], isNull);
      expect(find.byKey(const Key('lettrage:L1')), findsNothing, reason: 'une ligne lettrée ne se recoche plus');
      await t.pump(const Duration(seconds: 10));
      // dé-lettrer : motif obligatoire
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Dé-lettrer un code…'));
      await saisir(t, 'code', 'a');
      await saisir(t, 'motif', 'x');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Dé-lettrer'));
      expect(find.text('Un motif est obligatoire pour dé-lettrer.'), findsOneWidget);
      expect(col.parId('L1')!['lettrage'], 'A');
      await t.pump(const Duration(seconds: 10));
      await saisir(t, 'motif', 'Erreur de saisie');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Dé-lettrer'));
      expect(col.parId('L1')!['lettrage'], isNull);
      expect(col.parId('L1')!['delettreMotif'], 'Erreur de saisie');
      expect(find.text('2 ligne(s) dé-lettrée(s).'), findsOneWidget);
    });

    casM14('en lecture seule : ni « Lettrer », ni « Dé-lettrer » — ABSENTS, pas grisés', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({'id': 'L1', 'numero': 'LT-1', 'date': '2026-06-01', 'journal': 'OD', 'compte': '401000', 'debit': 5, 'credit': 0, 'statut': 'validee'});
      await ouvrirM14(t, m, 'm12-cloture',
          role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-cloture'));
      await toucherM14(t, find.text('Lettrage des tiers'));
      expect(find.widgetWithText(BoutonSigh, 'Lettrer la sélection'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Dé-lettrer un code…'), findsNothing);
      expect(find.byKey(const Key('lettrage:L1')), findsNothing);
    });
  });

  group('m12-ouverture', () {
    casM14('les comptes reportés (classes 1 à 5) et le résultat qui ÉQUILIBRE sont CALCULÉS depuis le journal', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-ouverture');
      final s = cpcSoldesDeCloture(m.collection('ecritures').actives, 2026);
      expect(s.comptes.length, 8);
      expect(find.text(money(s.totalDebiteurs)), findsWidgets);
      expect(find.text(money(s.totalCrediteurs)), findsWidgets);
      expect(find.text('Compte 13 — il équilibre le report'), findsOneWidget);
      expect(find.textContaining('Le report s’équilibre'), findsOneWidget);
      expect(find.text('Bilan d’ouverture au 1ᵉʳ janvier 2027 — à-nouveaux des classes 1 à 5'), findsOneWidget);
      expect(find.text('Résultat net de l’exercice 2026'), findsOneWidget);
      // aucune charge ni produit au bilan d'ouverture
      for (final c in s.comptes) {
        expect('12345'.contains('${c['compte']}'[0]), true);
      }
    });

    casM14('le report écrit UNE pièce en BROUILLON au journal AN, annulable ; un second report est REFUSÉ en nommant le motif', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-ouverture');
      final avant = m.collection('ecritures').actives.length;
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Écrire les à-nouveaux'));
      expect(find.text('Écrire les à-nouveaux du 1ᵉʳ janvier 2027 ?'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Écrire le report'));
      final an = m.collection('ecritures').actives.where((e) => e['journal'] == 'AN').toList();
      expect(an, hasLength(9));
      expect(an.every((e) => e['statut'] == 'brouillon' && e['numero'] == 'AN-2027-00001'), true);
      expect(an.any((e) => e['compte'] == '130000'), true, reason: 'le résultat entre au compte 13');
      expect(m.collection('ecritures').actives.length, avant + 9);
      expect(find.text('À-nouveaux écrits — 9 ligne(s) au journal AN.'), findsOneWidget);
      expect(find.textContaining('sont DÉJÀ écrits : 9 ligne(s) au journal AN'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      // second geste : refusé, rien n'est écrit
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Écrire les à-nouveaux'));
      expect(find.text('Les à-nouveaux du 1ᵉʳ janvier 2027 existent déjà.'), findsOneWidget);
      expect(find.text('Les réécrire créerait un double report.'), findsOneWidget);
      expect(m.collection('ecritures').actives.length, avant + 9);
    });

    casM14('un report qui ne s\'équilibre pas est REFUSÉ (RG-10) : la note le dit, le toast chiffre l\'écart, rien n\'est écrit', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({
        'id': 'X-DESEQ', 'numero': 'ODX', 'date': '2026-05-05', 'journal': 'OD', 'compte': '571000', 'compteLibelle': 'Caisse', 'debit': 5000, 'credit': 0, 'statut': 'validee'
      });
      await ouvrirM14(t, m, 'm12-ouverture');
      final avant = m.collection('ecritures').actives.length;
      expect(find.textContaining('Le report NE S’ÉQUILIBRE PAS — écart de ${money(5000)}'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Écrire les à-nouveaux'));
      expect(find.text('Report refusé — écart de ${money(5000)} (RG-10).'), findsOneWidget);
      expect(m.collection('ecritures').actives.length, avant);
    });

    casM14('l\'impression porte le bilan d\'ouverture avec ses TOTAUX CALCULÉS', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-ouverture');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le bilan d’ouverture'));
      expect(find.text('Bilan d’ouverture — à-nouveaux'), findsWidgets);
      expect(find.text('TOTAUX DU REPORT'), findsOneWidget);
      final s = cpcSoldesDeCloture(m.collection('ecritures').actives, 2026);
      expect(find.text(money(s.totalDebiteurs + (s.resultat < 0 ? -s.resultat : 0), avecDevise: false)), findsWidgets);
    });

    casM14('en lecture seule : « Écrire les à-nouveaux » est ABSENT, pas grisé ; l\'impression reste', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-ouverture', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-ouverture'));
      expect(find.widgetWithText(BoutonSigh, 'Écrire les à-nouveaux'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer le bilan d’ouverture'), findsOneWidget);
    });
  });
}
