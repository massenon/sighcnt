import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/impression/piece.dart';

import 'aide_polices.dart';

/// Impression : géométrie des gabarits contre la maquette (`references/kit/impression.json`), contenu du ticket identique (vecteurs, test du
/// domaine), PDF structurellement valide aux dimensions physiques (80 mm / A4). Le texte du PDF n'est pas relu (glyphes encodés) : on contrôle
/// la structure ; la fidélité du contenu est portée par les listes de lignes communes à l'aperçu et au PDF.
late Map<String, dynamic> ref;
final date = DateTime(2026, 10, 30, 14, 5);

final entree = EntreeTicket(
  operateur: 'A',
  numero: 'F-1',
  date: date,
  dossier: 'CNT/12/26',
  lignes: const [
    LigneArticle(
        designation: 'Consultation',
        quantite: 1,
        prixUnitaire: 3000,
        montant: 3000)
  ],
  total: 3000,
  partPatient: 3000,
  regle: 3000,
);

final piece = PieceA4(
  titre: 'État de test',
  reference: 'CNT-20261030-0001',
  utilisateur: 'ADJAHO Rose',
  edite: date,
  tableaux: [
    TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Désignation', valeur: (r) => r['d']),
      ColonneEtat(
          libelle: 'Montant',
          valeur: (r) => r['m'],
          droite: true,
          somme: (r) => r['m'] as num),
    ], lignes: const [
      {'d': 'A', 'm': 1000},
      {'d': 'B', 'm': 250}
    ])
  ],
  signatures: const [Signature('Le Caissier'), Signature('La DAF')],
);

Future<void> monter(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1400, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Inter'),
      home: Scaffold(
          body: SingleChildScrollView(
              child: Align(alignment: Alignment.topLeft, child: w)))));
  await t.pump();
}

void main() {
  setUpAll(() async {
    await chargerPolices();
    ref = jsonDecode(
            File('test/references/kit/impression.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  testWidgets(
      'ticket : 80 mm de large, hauteur proche de la maquette, lignes du domaine',
      (t) async {
    await monter(t, FeuilleTicket(entree: entree, reference: 'CNT-1'));
    final r = t.getRect(find.byKey(const Key('impression:ticket')));
    expect(r.width, closeTo((ref['ticket']['l'] as num).toDouble(), 0.5));
    final h = (ref['ticket']['h'] as num).toDouble();
    expect(r.height, closeTo(h, h * 0.08),
        reason: 'ticket ${r.height} vs ${ref['ticket']['h']}');
    expect(find.text('MONTANT TOTAL'), findsOneWidget);
    expect(find.text('trois mille francs CFA'), findsOneWidget);
    expect(find.text(IdentiteClinique.formulePolitesse), findsOneWidget);
  });

  testWidgets(
      'A4 : 210 × 297 mm, en-tête légal unique, titre, tableau avec total refait, pied normalisé',
      (t) async {
    await monter(t, FeuilleA4(piece: piece));
    final a4 = t.getRect(find.byKey(const Key('impression:a4')));
    expect(a4.width, closeTo((ref['a4']['l'] as num).toDouble(), 0.5));
    expect(a4.height, greaterThanOrEqualTo(mm(297) - 0.5));
    final e = t.getRect(find.byKey(const Key('impression:entete')));
    final he = (ref['entete']['h'] as num).toDouble();
    expect(e.height, closeTo(he, 8), reason: 'en-tête ${e.height} vs $he');
    expect(e.width, closeTo((ref['entete']['l'] as num).toDouble(), 1));
    final ti = t.getRect(find.byKey(const Key('impression:titre')));
    expect(ti.height, closeTo((ref['titre']['h'] as num).toDouble(), 6));
    final pied = t.getRect(find.byKey(const Key('impression:pied')));
    expect(pied.height, closeTo((ref['pied']['h'] as num).toDouble(), 6));
    // L'identité légale est imprimée une fois, depuis le domaine.
    expect(
        find.textContaining('IFU : ${IdentiteClinique.ifu}'), findsOneWidget);
    expect(
        find.textContaining('RCCM : ${IdentiteClinique.rccm}'), findsOneWidget);
    // Le total est calculé : 1000 + 250.
    expect(find.text('1 250'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(
        find.textContaining(
            'Document généré par ADJAHO Rose le 30/10/2026 à 14h05'),
        findsOneWidget);
    expect(find.text('Réf. document : CNT-20261030-0001'), findsOneWidget);
  });

  test('référence de pièce CNT-AAAAMMJJ-NNNN', () {
    expect(PieceA4.reference_(date, 7), 'CNT-20261030-0007');
  });

  testWidgets('PDF : ticket 80 mm et A4 structurellement valides', (t) async {
    final p = await t.runAsync(PolicesPdf.charger);
    final tk = (await t
        .runAsync(() => pdfTicket(entree, 'CNT-1', p!, compresser: false)))!;
    final a4 = (await t.runAsync(() => pdfA4(piece, p!, compresser: false)))!;
    String txt(List<int> b) => latin1.decode(b);
    expect(txt(tk.sublist(0, 5)), '%PDF-');
    expect(txt(a4.sublist(0, 5)), '%PDF-');
    expect(txt(tk.sublist(tk.length - 6)).trim(), '%%EOF');
    // MediaBox : 80 mm = 226,77 pt ; A4 = 595,28 × 841,89 pt.
    final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]');
    final mt = box.firstMatch(txt(tk))!;
    expect(double.parse(mt.group(1)!), closeTo(226.77, 0.1));
    final ma = box.firstMatch(txt(a4))!;
    expect(double.parse(ma.group(1)!), closeTo(595.28, 0.1));
    expect(double.parse(ma.group(2)!), closeTo(841.89, 0.1));
    expect(RegExp(r'/Type\s*/Page\b').hasMatch(txt(a4)), isTrue);
  });
}
