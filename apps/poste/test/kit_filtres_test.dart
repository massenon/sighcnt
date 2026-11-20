import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// Géométrie de la barre de filtres de `U.dataTable` : la recherche et les sélections s'alignent sur UNE rangée (select
/// `w-auto min-w-[9rem]` de la maquette) et ne passent à la ligne que lorsque la largeur manque. Jamais un filtre par ligne
/// à 1440 px (défaut constaté par la Direction : chaque sélection prenait toute la largeur de la barre).
void main() {
  setUpAll(chargerPolices);

  Future<void> poser(WidgetTester t, double largeur, Widget w) async {
    t.view.physicalSize = Size(largeur, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
        home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: w)))));
    await t.pump();
  }

  Widget tableau(int nFiltres) => TableauSigh(
        colonnes: [ColonneTableau(cle: 'a', libelle: 'A')],
        lignes: const [
          {'a': 'x'}
        ],
        filtres: [
          for (var i = 0; i < nFiltres; i++)
            FiltreTableau(nom: 'f$i', libelle: ['Rôle', 'État', 'Service', 'Nature', 'Statut'][i], options: const [
              OptionChamp('1', 'Premier'),
              OptionChamp('2', 'Second'),
            ]),
        ],
      );

  /// Nombre de rangées distinctes occupées par les champs de filtre, et leur rangée-colonne.
  ({int rangees, int champs, List<Rect> rects}) mesurer(WidgetTester t) {
    final b = find.byKey(const Key('kit:tableau-barre'));
    final rects = [
      for (final e in find.descendant(of: b, matching: find.byType(InputDecorator)).evaluate())
        t.getRect(find.byWidget(e.widget))
    ];
    // Le premier champ est la recherche ; les suivants sont les filtres.
    final filtres = rects.skip(1).toList();
    final tops = {for (final r in filtres) r.top.round()};
    return (rangees: tops.length, champs: filtres.length, rects: filtres);
  }

  testWidgets('quatre filtres tiennent sur UNE rangée à 1440 px, avec la recherche', (t) async {
    await poser(t, 1440, tableau(4));
    final m = mesurer(t);
    expect(m.champs, 4);
    expect(m.rangees, 1, reason: 'les filtres doivent être côte à côte');
    final rech = t.getRect(find.byKey(const Key('kit:tableau-recherche')));
    expect(m.rects.first.top, closeTo(rech.top, 2), reason: 'recherche et sélections sur la même rangée');
    for (final r in m.rects) {
      expect(r.width, inInclusiveRange(144, 320));
      expect(r.height, closeTo(38, 1));
    }
    for (var i = 1; i < m.rects.length; i++) {
      expect(m.rects[i].left - m.rects[i - 1].right, closeTo(8, 0.5), reason: 'gouttière de 8 px (gap-2)');
    }
  });

  testWidgets('sous le seuil, les filtres passent à la ligne par groupes : jamais un par ligne', (t) async {
    await poser(t, 800, tableau(4));
    final m = mesurer(t);
    expect(m.rangees, greaterThanOrEqualTo(2), reason: 'la largeur manque : au moins deux rangées');
    expect(m.rangees, lessThan(m.champs), reason: 'plusieurs filtres par rangée');
    await poser(t, 480, tableau(4));
    final etroit = mesurer(t);
    expect(etroit.rangees, greaterThanOrEqualTo(m.rangees), reason: 'plus étroit, jamais moins de rangées');
  });

  testWidgets('largeur du filtre = contenu le plus large, minimum 144 px', (t) async {
    await poser(
        t,
        1440,
        TableauSigh(
          colonnes: [ColonneTableau(cle: 'a', libelle: 'A')],
          lignes: const [],
          filtres: [
            FiltreTableau(nom: 'c', libelle: 'État', options: const [OptionChamp('1', 'Actif')]),
            FiltreTableau(nom: 'l', libelle: 'Service', options: const [OptionChamp('1', 'Direction médicale et administrative')]),
          ],
        ));
    final m = mesurer(t);
    expect(m.rects[0].width, 144);
    expect(m.rects[1].width, greaterThan(220));
  });

  group('balayage d\'écrans réels à 1440 px', () {
    Future<void> ouvrirA(WidgetTester t, String ecran) async {
      t.view.physicalSize = const Size(1440, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');
      await t.pumpWidget(SighPoste(
          key: UniqueKey(),
          donnees: donneesNav,
          config: ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
          ecranInitial: ecran,
          magasin: m,
          horloge: () => aujourdhui));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    for (final ecran in [
      'm14-utilisateurs',
      'm8-factures',
      'm6-produits',
      'm10-personnel',
      'm2-rendezvous',
      'm7-commandes',
    ]) {
      testWidgets(ecran, (t) async {
        await ouvrirA(t, ecran);
        final barres = find.byKey(const Key('kit:tableau-barre'));
        expect(barres, findsWidgets, reason: '$ecran porte un tableau');
        var verifie = 0;
        for (final e in barres.evaluate()) {
          final b = find.byWidget(e.widget);
          final champs = [
            for (final d in find.descendant(of: b, matching: find.byType(InputDecorator)).evaluate())
              t.getRect(find.byWidget(d.widget))
          ];
          final rech = find.descendant(of: b, matching: find.byKey(const Key('kit:tableau-recherche')));
          final filtres = rech.evaluate().isEmpty ? champs : champs.skip(1).toList();
          if (filtres.length < 2) continue;
          verifie++;
          final tops = {for (final r in filtres) r.top.round()};
          expect(tops.length, lessThan(filtres.length), reason: '$ecran : un filtre par ligne');
          if (filtres.length <= 4) expect(tops.length, 1, reason: '$ecran : ${filtres.length} filtres sur une rangée');
        }
        expect(verifie, greaterThan(0), reason: '$ecran : aucune barre à plusieurs filtres mesurée');
      });
    }
  });
}
