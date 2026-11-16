// Lot EXP : la sortie des tableaux au poste (kit `TableauSigh`) : cases par défaut, sélection gardée d'une page à l'autre, classeur .xlsx typé (relu par le
// lecteur du poste), colonne masquée et rendu exclus, tout exporter, limite refusée nommée sans fichier ni journal, journal RG-12, commande ABSENTE sans le
// droit et moteur qui refuse, aucune sortie sans journal.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/import/classeur_xlsx.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/kit/sortie_tableau.dart';

final _lignes = [
  for (var i = 1; i <= 30; i++)
    <String, Object?>{
      'id': 'F$i',
      'numero': 'FN-$i',
      'montant': i * 1500,
      'date': '2026-08-${(i % 28 + 1).toString().padLeft(2, '0')}',
      'telephone': '+229 97 00 00 ${i.toString().padLeft(2, '0')}',
      'nature': i.isOdd ? 'Consultation' : 'Pharmacie',
    }
];

const _colonnes = [
  ColonneTableau(cle: 'numero', libelle: 'N°'),
  ColonneTableau(cle: 'date', libelle: 'Date'),
  ColonneTableau(cle: 'nature', libelle: 'Nature'),
  ColonneTableau(cle: 'montant', libelle: 'Montant', droite: true),
  // une colonne MASQUÉE par son texte : la sortie ne lit jamais la valeur brute
  ColonneTableau(cle: 'telephone', libelle: 'Téléphone', texte: _masque),
];
String _masque(Map<String, Object?> l) => '•• •• ${'${l['telephone']}'.substring('${l['telephone']}'.length - 2)}';

late List<Map<String, Object?>> journal;
late Map<String, Uint8List> fichiers;

ContexteSortieTableau _ctx({bool? droit = true, int limite = 2000, bool avecJournal = true}) => ContexteSortieTableau(
      droit: droit,
      libelleRole: 'Caissier',
      limite: limite,
      journaliser: avecJournal ? journal.add : null,
      ecran: 'm8-factures',
      module: 'M8',
      utilisateur: 'Agent EXP',
      jour: DateTime(2026, 10, 30),
    );

Future<void> monter(WidgetTester t, {String? Function(String, String)? csv}) async {
  t.view.physicalSize = const Size(1400, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
    home: Scaffold(
        backgroundColor: JetonsShell.navy50,
        body: SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: TableauSigh(
                    titre: 'Factures',
                    nomExport: 'factures',
                    colonnes: _colonnes,
                    lignes: _lignes,
                    alExporter: csv == null ? null : (n, c) => csv(n, c))))),
  ));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> cocher(WidgetTester t, int rang) async {
  await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(rang));
  await t.pump();
}

Future<void> page(WidgetTester t, String n) async {
  await t.tap(find.widgetWithText(BoutonSigh, n).last);
  await t.pump();
}

Future<void> exporter(WidgetTester t, {String? perimetre, required String format}) async {
  await t.tap(find.byKey(const Key('kit:tableau-exporter')));
  await t.pumpAndSettle();
  if (perimetre != null) {
    await t.tap(find.byKey(Key('sortie:perimetre-$perimetre')));
    await t.pump();
  }
  await t.tap(find.byKey(Key('sortie:format-$format')));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    journal = [];
    fichiers = {};
    SortieTableauxPoste.contexteDeTest = _ctx();
    SortieTableauxPoste.enregistrer = (nom, octets) async {
      fichiers[nom] = octets;
      return '/dossier/$nom';
    };
  });
  tearDown(SortieTableauxPoste.reinitialiser);
  // le message (toast) d'une sortie s'efface au bout de quelques secondes : chaque test le laisse partir avant de finir

  testWidgets('cases PAR DÉFAUT (« Tout sélectionner » et une case par ligne de la page) et commande « Exporter »', (t) async {
    await monter(t);
    expect(find.bySemanticsLabel('Tout sélectionner'), findsOneWidget);
    expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNWidgets(12));
    expect(find.byKey(const Key('kit:tableau-exporter')), findsOneWidget);
  });

  testWidgets('la sélection se GARDE d’une page à l’autre ; le classeur .xlsx porte EXACTEMENT les lignes cochées, montants en nombres, dates en dates, le texte montré d’une colonne masquée ; journal RG-12', (t) async {
    await monter(t);
    await cocher(t, 0);
    await cocher(t, 2);
    await page(t, '2');
    await cocher(t, 0); // FN-13
    await page(t, '1');
    expect(find.text('3 lignes sélectionnées'), findsOneWidget);
    expect(find.byKey(const Key('kit:tableau-exporter-selection')), findsOneWidget);
    expect(find.byKey(const Key('kit:tableau-imprimer-selection')), findsOneWidget);
    await exporter(t, format: 'xlsx');
    expect(fichiers.keys, ['factures-2026-10-30.xlsx']);
    final f = lireClasseur(fichiers.values.single).single;
    expect(f.nom, 'Factures 2026-10-30');
    expect(f.lignes.first, ['N°', 'Date', 'Nature', 'Montant', 'Téléphone']);
    expect([for (final l in f.lignes.skip(1)) l[0]], ['FN-1', 'FN-3', 'FN-13']);
    expect([for (final l in f.lignes.skip(1)) l[3]], [1500, 4500, 19500], reason: 'montants en NOMBRES');
    expect([for (final l in f.formats.skip(1)) l[1]], [14, 14, 14], reason: 'dates au format date');
    expect(f.lignes[1][1], tabVersSerie('2026-08-02'));
    expect(f.lignes[1][4], '•• •• 01', reason: 'le texte montré, jamais la valeur brute');
    expect(journal, hasLength(1));
    expect(journal.single, containsPair('format', 'xlsx'));
    expect(journal.single, containsPair('perimetre', 'selection'));
    expect(journal.single['references'], ['F1', 'F3', 'F13']);
    expect('${journal.single}'.contains('+229'), isFalse, reason: 'jamais le contenu d’une cellule');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('une colonne masquée par l’agent ne sort pas ; CSV gardé, remis au rappel APRÈS le journal', (t) async {
    final recus = <String, String>{};
    await monter(t, csv: (n, c) {
      recus[n] = c;
      return null;
    });
    await t.tap(find.widgetWithText(BoutonSigh, 'Colonnes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Nature').last);
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Fermer'));
    await t.pumpAndSettle();
    await cocher(t, 1);
    await exporter(t, format: 'csv');
    expect(recus.keys, ['factures-2026-10-30.csv']);
    final l = recus.values.single.replaceFirst('﻿', '').split('\r\n');
    expect(l.first, '"N°";"Date";"Montant";"Téléphone"');
    expect(l[1], '"FN-2";"03/08/2026";"3000";"•• •• 02"');
    expect(journal.single['format'], 'csv');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('« Tout exporter » : les 30 lignes, toutes pages, en un seul classeur', (t) async {
    await monter(t);
    await exporter(t, perimetre: 'tout', format: 'xlsx');
    expect(lireClasseur(fichiers.values.single).single.lignes.length - 1, 30);
    expect(journal.single['perimetre'], 'tout');
    expect(journal.single['referencesTotal'], 30);
    expect((journal.single['references'] as List).length, 30);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('au-delà de la limite réglée : refus nommé EXPORT_AU_DELA_DE_LA_LIMITE, aucun fichier, aucun journal (jamais tronqué)', (t) async {
    SortieTableauxPoste.contexteDeTest = _ctx(limite: 2);
    await monter(t);
    await cocher(t, 0);
    await cocher(t, 1);
    await cocher(t, 2);
    await exporter(t, format: 'xlsx');
    expect(fichiers, isEmpty);
    expect(journal, isEmpty);
    expect(find.textContaining('EXPORT_AU_DELA_DE_LA_LIMITE'), findsOneWidget);
    expect(find.textContaining('3 lignes demandées'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('sans le droit (fiche RBAC) : « Exporter », « Exporter la sélection », « Imprimer la sélection » sont ABSENTS ; le moteur refuse en nommant le profil', (t) async {
    SortieTableauxPoste.contexteDeTest = _ctx(droit: false);
    await monter(t);
    expect(find.byKey(const Key('kit:tableau-exporter')), findsNothing);
    await cocher(t, 0);
    expect(find.text('1 ligne sélectionnée'), findsOneWidget);
    expect(find.byKey(const Key('kit:tableau-exporter-selection')), findsNothing);
    expect(find.byKey(const Key('kit:tableau-imprimer-selection')), findsNothing);
    final r = await sortirLignesPoste(t.element(find.byType(TableauSigh)),
        format: 'xlsx', colonnes: _colonnes, lignes: _lignes.take(1).toList(), perimetre: 'selection', nom: 'factures');
    expect(r.refus?.code, 'EXPORT_NON_AUTORISE');
    expect(r.refus?.motif, contains('Caissier'));
    expect(fichiers, isEmpty);
    expect(journal, isEmpty);
  });

  testWidgets('aucune sortie sans journal (RG-12) ni sans droits lisibles', (t) async {
    await monter(t);
    final ctx = t.element(find.byType(TableauSigh));
    final r1 = await sortirLignesPoste(ctx,
        format: 'csv', colonnes: _colonnes, lignes: _lignes.take(2).toList(), perimetre: 'selection', nom: 'factures', sortie: _ctx(avecJournal: false));
    expect(r1.refus?.code, 'JOURNAL_INDISPONIBLE');
    final r2 = await sortirLignesPoste(ctx,
        format: 'csv', colonnes: _colonnes, lignes: _lignes.take(2).toList(), perimetre: 'selection', nom: 'factures', sortie: _ctx(droit: null));
    expect(r2.refus?.code, 'DROITS_ILLISIBLES');
    expect(fichiers, isEmpty);
  });

  testWidgets('un encart (MiniTableauSigh) a ses cases et « Exporter » : la ligne cochée sort typée depuis le texte montré ; sans le droit, la commande est absente', (t) async {
    Future<void> monterMini() async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MiniTableauSigh(nomExport: 'top-produits', colonnes: [
        ColonneMini('Produit', (f) => '${f['nom']}'),
        ColonneMini('Péremption', (f) => '${f['peremption']}'),
        ColonneMini('Valeur', (f) => money(f['valeur'], avecDevise: false), droite: true),
      ], lignes: const [
        {'id': 'P1', 'nom': 'Paracétamol', 'peremption': '14/08/2027', 'valeur': 125000},
        {'id': 'P2', 'nom': 'Amoxicilline', 'peremption': '01/02/2027', 'valeur': 98000},
        {'id': 'P3', 'nom': 'Quinine', 'peremption': '—', 'valeur': 4500},
      ]))));
      await t.pump();
    }

    await monterMini();
    expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNWidgets(3));
    await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(1));
    await t.pump();
    expect(find.text('1 ligne sélectionnée'), findsOneWidget);
    await t.tap(find.byKey(const Key('kit:mini-exporter')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sortie:format-xlsx')));
    await t.pumpAndSettle();
    final f = lireClasseur(fichiers['top-produits-2026-10-30.xlsx']!).single;
    expect(f.lignes, [
      ['Produit', 'Péremption', 'Valeur'],
      ['Amoxicilline', tabVersSerie('2027-02-01'), 98000],
    ]);
    expect(f.formats[1][1], 14);
    expect(journal.single['references'], ['P2']);
    await t.pump(const Duration(seconds: 10));
    SortieTableauxPoste.contexteDeTest = _ctx(droit: false);
    await monterMini();
    await t.pumpWidget(const SizedBox());
    await monterMini();
    expect(find.byKey(const Key('kit:mini-exporter')), findsNothing);
    expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNWidgets(3));
  });
}
