import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';

/// Graphiques : comparés aux captures des VRAIS graphiques Chart.js de la maquette (600 px, mêmes séries) — pixels écartés bornés, mesurés et
/// écrits dans docs/architecture/rapport-parite-kit.json (« graphiques ») ; l'échelle verticale, elle, est vérifiée EXACTEMENT par les vecteurs
/// du domaine. Chart.js et Flutter n'antialiasent pas les courbes ni le texte pareil : un écart de quelques % est attendu, jamais promis nul.
const seuil = 0.10;
final mesures = <String, double>{};

Future<double> ecart(
    WidgetTester t, Widget w, String id, double hauteur) async {
  t.view.physicalSize = Size(700, hauteur + 40);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final cle = GlobalKey();
  await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter'),
      home: Material(
          color: Colors.white,
          child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                  key: cle,
                  child: ColoredBox(
                      color: Colors.white,
                      child: SizedBox(width: 600, child: w)))))));
  await t.pumpAndSettle();
  return (await t.runAsync(() async {
    final ref = (await (await ui.instantiateImageCodec(
                File('test/references/kit/graphique-$id.png')
                    .readAsBytesSync()))
            .getNextFrame())
        .image;
    final img =
        await (cle.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final a = (await img.toByteData())!.buffer.asUint8List(),
        r = (await ref.toByteData())!.buffer.asUint8List();
    var diff = 0;
    final h = ref.height < img.height ? ref.height : img.height;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < 600; x++) {
        final i = (y * img.width + x) * 4, j = (y * ref.width + x) * 4;
        if ((a[i] - r[j]).abs() > 64 ||
            (a[i + 1] - r[j + 1]).abs() > 64 ||
            (a[i + 2] - r[j + 2]).abs() > 64) diff++;
      }
    }
    return (diff + (ref.height - img.height).abs() * 600) / (ref.height * 600);
  }))!;
}

void main() {
  setUpAll(chargerPolices);
  tearDownAll(() {
    final f = File('../../docs/architecture/rapport-parite-kit.json');
    final j = f.existsSync()
        ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    j['graphiques'] = {
      'seuil': seuil,
      'ecart_pixels':
          mesures.map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(4))))
    };
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(j));
  });

  final cas = <String, (Widget, double)>{
    'barres': (
      const GraphiqueBarres(etiquettes: [
        'Mai',
        'Juin',
        'Juil.',
        'Août'
      ], series: [
        SerieGraphique('Recettes', [120, 180, 90, 210]),
        SerieGraphique('Dépenses', [80, 100, 70, 150],
            couleur: Color(0xFFF98307))
      ]),
      260
    ),
    'ligne': (
      const GraphiqueLigne(etiquettes: [
        'Mai',
        'Juin',
        'Juil.',
        'Août',
        'Sept.'
      ], series: [
        SerieGraphique('Admissions', [12, 30, 22, 40, 35])
      ]),
      260
    ),
    'anneau': (
      const GraphiqueAnneau(
          etiquettes: ['Consultation', 'Laboratoire', 'Pharmacie'],
          valeurs: [50, 30, 20]),
      260
    ),
    'sparkline': (const Sparkline([3, 5, 4, 8, 6, 9]), 40),
  };
  cas.forEach((id, c) {
    testWidgets('graphique $id contre Chart.js', (t) async {
      final e = await ecart(t, c.$1, id, c.$2);
      mesures[id] = e;
      expect(e, lessThanOrEqualTo(seuil),
          reason: '$id : ${(e * 100).toStringAsFixed(1)} % de pixels écartés');
    });
  });

  testWidgets('accessibilité : les valeurs sont dites, pas seulement dessinées',
      (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GraphiqueBarres(etiquettes: [
      'Mai',
      'Juin'
    ], series: [
      SerieGraphique('Recettes', [120, 180])
    ]))));
    expect(
        find.bySemanticsLabel(
            RegExp('Graphique en barres. Recettes : Mai 120, Juin 180')),
        findsOneWidget);
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GraphiqueAnneau(etiquettes: ['A', 'B'], valeurs: [75, 25]))));
    expect(find.bySemanticsLabel(RegExp('A : 75')), findsOneWidget);
    h.dispose();
  });

  testWidgets('un graphique vide ou nul ne plante pas', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Column(children: [
      GraphiqueBarres(etiquettes: [
        'a'
      ], series: [
        SerieGraphique('s', [0])
      ]),
      GraphiqueAnneau(etiquettes: ['a'], valeurs: [0]),
      Sparkline([1]),
    ]))));
    expect(tester(t), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();
