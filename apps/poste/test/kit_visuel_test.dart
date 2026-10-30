import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';

/// N3 — PARITÉ VISUELLE du kit : chaque composant est rendu dans les mêmes conditions que la capture de la maquette
/// (`test/references/kit/<id>.png`, prise dans Chrome par `build/reference-kit.js`) et comparé pixel à pixel.
/// Mesure : part des pixels dont un canal s'écarte de plus de 64/255. Le texte n'est pas rasterisé pareil par Chrome et
/// par Skia/Impeller : un écart de quelques % sur du texte est attendu, c'est pourquoi le seuil est borné (pas promis nul)
/// et l'écart MESURÉ est écrit dans docs/architecture/rapport-parite-kit.json (clé « visuel »).
const seuil = 0.12;
final mesures = <String, double>{};

Future<ui.Image> decoder(File f) async {
  final c = await ui.instantiateImageCodec(f.readAsBytesSync());
  return (await c.getNextFrame()).image;
}

Future<double> ecart(WidgetTester t, String id, Widget w, ui.Image ref) async {
  t.view.physicalSize = const Size(1000, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final cle = GlobalKey();
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
    home: Material(
        type: MaterialType.transparency,
        child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
                key: cle,
                child: Container(
                    width: 960,
                    color: JetonsShell.navy50,
                    padding: const EdgeInsets.all(16),
                    child: w)))),
  ));
  await t.pumpAndSettle();
  return (await t.runAsync(() async {
    final b = cle.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final h = ref.height < img.height ? ref.height : img.height;
    final a = (await img.toByteData())!.buffer.asUint8List();
    final r = (await ref.toByteData())!.buffer.asUint8List();
    var diff = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < 960; x++) {
        final i = (y * img.width + x) * 4, j = (y * ref.width + x) * 4;
        if ((a[i] - r[j]).abs() > 64 ||
            (a[i + 1] - r[j + 1]).abs() > 64 ||
            (a[i + 2] - r[j + 2]).abs() > 64) diff++;
      }
    }
    // Une hauteur différente est elle-même un écart : les lignes en trop comptent comme différentes.
    final lignesEnTrop = (ref.height - img.height).abs();
    return (diff + lignesEnTrop * 960) / (ref.height * 960);
  }))!;
}

void main() {
  setUpAll(chargerPolices);
  tearDownAll(() {
    final f = File('../../docs/architecture/rapport-parite-kit.json');
    final j = jsonDecode(f.existsSync() ? f.readAsStringSync() : '{}')
        as Map<String, dynamic>;
    j['visuel'] = {
      'seuil': seuil,
      'ecart_pixels':
          mesures.map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(4))))
    };
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(j));
  });

  final cas = <String, Widget>{
    'boutons': const Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          BoutonSigh(libelle: 'Enregistrer', onPressed: _r),
          BoutonSigh(
              libelle: 'Annuler',
              variante: VarianteBouton.secondaire,
              onPressed: _r),
          BoutonSigh(
              libelle: 'Filtrer', taille: TailleBouton.sm, onPressed: _r),
          BoutonSigh(
              libelle: 'Valider', taille: TailleBouton.lg, onPressed: _r),
          BoutonIcone(icone: LucideIcons.x, libelle: 'Fermer', onPressed: _r),
        ]),
    'carte': const CarteSigh(
        titre: 'Informations du patient',
        child: Text('Corps de la carte',
            style: TextStyle(
                fontSize: 14, height: 20 / 14, color: JetonsShell.slate800))),
    'kpi': const KpiGrilleSigh(colonnes: 2, kpis: [
      KpiSigh(
          libelle: 'Patients du jour', valeur: '128', icone: LucideIcons.users),
      KpiSigh(
          libelle: 'Recettes',
          valeur: '1 250 000 FCFA',
          icone: LucideIcons.wallet,
          ton: TonSigh.succes),
      KpiSigh(
          libelle: 'En retard',
          valeur: '4',
          icone: LucideIcons.clock,
          ton: TonSigh.danger),
      KpiSigh(
          libelle: 'À valider',
          valeur: '17',
          icone: LucideIcons.check,
          ton: TonSigh.attention),
    ]),
    'note':
        const NoteSigh('Règle appliquée : la prise en charge vaut à la date.'),
    'onglets': OngletsSigh(onglets: [
      OngletDef(
          id: 'a',
          libelle: 'Général',
          compte: 3,
          construire: (_) =>
              const Text('A', style: TextStyle(fontSize: 14, height: 20 / 14))),
      OngletDef(
          id: 'b', libelle: 'Antécédents', construire: (_) => const SizedBox()),
      OngletDef(
          id: 'c', libelle: 'Documents', construire: (_) => const SizedBox()),
    ]),
    'vide':
        const VideSigh('Aucun enregistrement.', indice: 'Créez le premier.'),
  };

  cas.forEach((id, w) {
    testWidgets('visuel : $id', (t) async {
      final ref =
          await t.runAsync(() => decoder(File('test/references/kit/$id.png')));
      final e = await ecart(t, id, w, ref!);
      mesures[id] = e;
      expect(e, lessThanOrEqualTo(seuil),
          reason:
              '$id : ${(e * 100).toStringAsFixed(1)} % de pixels écartés (seuil ${(seuil * 100).toStringAsFixed(0)} %)');
    });
  });
}

void _r() {}
