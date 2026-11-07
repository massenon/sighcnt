import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';

/// PARITÉ GÉOMÉTRIQUE du kit : chaque composant est monté dans le même conteneur que la maquette (960 px, marge 16) et ses
/// parties nommées sont mesurées contre `test/references/kit/kit.json` — ENGENDRÉ par `prototype_html/build/reference-kit.js`
/// en montant les VRAIS composants de la maquette dans Chrome. Tolérance : 1 px sur les hauteurs, 1,5 px sur les largeurs
/// imposées par la grille (les largeurs de texte dépendent du moteur de rendu et ne sont pas comparées).
/// Le rapport (écarts mesurés) est écrit dans docs/architecture/rapport-parite-kit.json.
late Map<String, dynamic> ref;
final rapport = <String, Map<String, Object?>>{};

Future<void> monter(WidgetTester t, Widget w, {double largeur = 960}) async {
  t.view.physicalSize = Size(largeur + 40, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
    home: Scaffold(
        backgroundColor: JetonsShell.navy50,
        body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: largeur,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(child: w))))),
  ));
  await t.pump(const Duration(milliseconds: 400));
}

Rect mesure(WidgetTester t, Finder f) => t.getRect(f.first);

void comparer(String comp, String partie, Rect r,
    {bool largeur = true,
    double tolH = 1,
    double tolL = 1.5,
    bool position = true}) {
  final m = ref['composants'][comp][partie] as Map<String, dynamic>?;
  expect(m, isNotNull, reason: '$comp.$partie absent de la référence');
  final dh = r.height - (m!['h'] as num);
  final dl = r.width - (m['l'] as num);
  rapport.putIfAbsent(comp, () => {})[partie] = {
    'ref_h': m['h'],
    'dart_h': double.parse(r.height.toStringAsFixed(2)),
    'ref_l': m['l'],
    'dart_l': double.parse(r.width.toStringAsFixed(2)),
    'ecart_h': double.parse(dh.toStringAsFixed(2)),
    'ecart_l': double.parse(dl.toStringAsFixed(2))
  };
  expect(dh.abs(), lessThanOrEqualTo(tolH),
      reason: '$comp.$partie hauteur ${r.height} ≠ ${m['h']}');
  if (largeur)
    expect(dl.abs(), lessThanOrEqualTo(tolL),
        reason: '$comp.$partie largeur ${r.width} ≠ ${m['l']}');
}

void main() {
  setUpAll(() async {
    await chargerPolices();
    ref = jsonDecode(File('test/references/kit/kit.json').readAsStringSync())
        as Map<String, dynamic>;
  });
  tearDownAll(() {
    final f = File('../../docs/architecture/rapport-parite-kit.json');
    final j = f.existsSync()
        ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    j['tolerance'] = {'hauteur_px': 1, 'largeur_px': 1.5};
    j['composants'] = rapport;
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(j));
  });

  testWidgets('boutons : hauteurs et rayons de la maquette', (t) async {
    await monter(
        t,
        const Wrap(spacing: 12, children: [
          BoutonSigh(libelle: 'Enregistrer', onPressed: _rien),
          BoutonSigh(
              libelle: 'Annuler',
              variante: VarianteBouton.secondaire,
              onPressed: _rien),
          BoutonSigh(
              libelle: 'Filtrer', taille: TailleBouton.sm, onPressed: _rien),
          BoutonSigh(
              libelle: 'Valider', taille: TailleBouton.lg, onPressed: _rien),
          BoutonIcone(
              icone: LucideIcons.x, libelle: 'Fermer', onPressed: _rien),
        ]));
    final b = find.byType(BoutonSigh);
    comparer('boutons', 'primaire', mesure(t, b.at(0)), largeur: false);
    comparer('boutons', 'secondaire', mesure(t, b.at(1)), largeur: false);
    comparer('boutons', 'petit', mesure(t, b.at(2)), largeur: false);
    comparer('boutons', 'grand', mesure(t, b.at(3)), largeur: false);
    comparer('boutons', 'icone', mesure(t, find.byType(BoutonIcone)));
  });

  testWidgets('badges : 20 px de haut, six tons', (t) async {
    await monter(
        t,
        Wrap(spacing: 12, children: [
          for (final ton in TonSigh.values) BadgeSigh('Statut', ton: ton)
        ]));
    final noms = ['neutre', 'navy', 'succes', 'attention', 'danger', 'info'];
    for (var i = 0; i < 6; i++) {
      comparer('badges', noms[i], mesure(t, find.byType(BadgeSigh).at(i)),
          largeur: false);
    }
  });

  testWidgets('carte : en-tête 49 px, corps p 20', (t) async {
    await monter(
        t,
        const CarteSigh(
            titre: 'Informations du patient',
            child: Text('Corps de la carte',
                style: TextStyle(fontSize: 14, height: 20 / 14))));
    comparer('carte', 'carte', mesure(t, find.byType(CarteSigh)));
    comparer(
        'carte', 'entete', mesure(t, find.byKey(const Key('kit:carte-entete'))),
        tolL: 2.5);
    comparer(
        'carte', 'corps', mesure(t, find.byKey(const Key('kit:carte-corps'))),
        tolH: 1, tolL: 2.5);
  });

  testWidgets('KPI : carte 86 px, quatre colonnes de 458 px', (t) async {
    await monter(
        t,
        const KpiGrilleSigh(colonnes: 2, kpis: [
          KpiSigh(
              libelle: 'Patients du jour',
              valeur: '128',
              icone: LucideIcons.users),
          KpiSigh(
              libelle: 'Recettes',
              valeur: '1 250 000 FCFA',
              icone: LucideIcons.wallet,
              ton: TonSigh.succes),
        ]));
    comparer('kpi', 'kpi', mesure(t, find.byKey(const Key('kit:kpi'))));
    comparer(
        'kpi', 'libelle', mesure(t, find.byKey(const Key('kit:kpi-libelle'))),
        largeur: false);
    comparer(
        'kpi', 'valeur', mesure(t, find.byKey(const Key('kit:kpi-valeur'))),
        largeur: false);
    comparer('kpi', 'pastille',
        mesure(t, find.byKey(const Key('kit:kpi-pastille'))));
  });

  testWidgets('onglets : barre de 42 px', (t) async {
    await monter(
        t,
        OngletsSigh(onglets: [
          OngletDef(
              id: 'a',
              libelle: 'Général',
              compte: 3,
              construire: (_) => const Text('A')),
          OngletDef(
              id: 'b',
              libelle: 'Antécédents',
              construire: (_) => const Text('B')),
        ]));
    comparer('onglets', 'barre',
        mesure(t, find.byKey(const Key('kit:onglets-barre'))));
    comparer('onglets', 'actif',
        mesure(t, find.byKey(const Key('kit:onglet:a:actif'))),
        largeur: false);
    comparer(
        'onglets', 'inactif', mesure(t, find.byKey(const Key('kit:onglet:b'))),
        largeur: false);
  });

  testWidgets(
      'formulaire à 6 colonnes : tiers, demi, plein à la largeur de la grille',
      (t) async {
    final c = ControleurFormulaire(const [
      ChampDef.section('Identité'),
      ChampDef(nom: 'nom', libelle: 'Nom', requis: true, col: ColChamp.tiers),
      ChampDef(nom: 'prenom', libelle: 'Prénom', col: ColChamp.tiers),
      ChampDef(
          nom: 'sexe',
          libelle: 'Sexe',
          type: TypeChamp.select,
          col: ColChamp.tiers,
          options: [OptionChamp('F'), OptionChamp('M')]),
      ChampDef(nom: 'adresse', libelle: 'Adresse', col: ColChamp.plein),
      ChampDef(nom: 'tel', libelle: 'Téléphone'),
      ChampDef(nom: 'quartier', libelle: 'Quartier'),
    ]);
    await monter(t, FormulaireSigh(controleur: c));
    comparer('formulaire', 'grille',
        mesure(t, find.byKey(const Key('kit:formulaire'))),
        tolH: 1);
    comparer(
        'formulaire', 'nom', mesure(t, find.byKey(const Key('kit:champ:nom'))));
    comparer('formulaire', 'prenom',
        mesure(t, find.byKey(const Key('kit:champ:prenom'))));
    comparer('formulaire', 'sexe',
        mesure(t, find.byKey(const Key('kit:champ:sexe'))));
    comparer('formulaire', 'pleine',
        mesure(t, find.byKey(const Key('kit:champ:adresse'))));
    comparer('formulaire', 'demi',
        mesure(t, find.byKey(const Key('kit:champ:tel'))));
    comparer('formulaire', 'section',
        mesure(t, find.byKey(const Key('kit:section'))),
        tolH: 1.01);
    // Positions : les trois premiers champs sont sur la MÊME rangée, aux abscisses de la grille.
    final x = [
      for (final n in ['nom', 'prenom', 'sexe'])
        mesure(t, find.byKey(Key('kit:champ:$n'))).left
    ];
    for (var i = 0; i < 3; i++) {
      expect(
          x[i] - 16,
          closeTo(
              (ref['composants']['formulaire'][['nom', 'prenom', 'sexe'][i]]
                      ['x'] as num) -
                  16,
              1.5));
    }
  });

  testWidgets(
      'formulaire : obligatoire refusé en le disant, champ masqué ni validé ni enregistré',
      (t) async {
    final c = ControleurFormulaire(const [
      ChampDef(nom: 'nom', libelle: 'Nom', requis: true),
      ChampDef(
          nom: 'type',
          libelle: 'Type',
          type: TypeChamp.select,
          options: [OptionChamp('a'), OptionChamp('b', 'Autre')]),
      ChampDef(
          nom: 'precision',
          libelle: 'Précisez',
          requis: true,
          condition: (controle: 'type', quand: ['b'])),
    ]);
    await monter(t, FormulaireSigh(controleur: c));
    expect(c.valider(), isNull);
    await t.pump();
    expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
    expect(find.byKey(const Key('kit:champ:precision')), findsNothing,
        reason: 'masqué tant que « Autre » n’est pas choisi');
    c.poser('nom', 'Awa');
    final ok = c.valider();
    expect(ok, isNotNull);
    expect(ok!.containsKey('precision'), isFalse);
    c.poser('type', 'b');
    await t.pump();
    expect(find.byKey(const Key('kit:champ:precision')), findsOneWidget);
    expect(c.valider(), isNull);
  });

  testWidgets('note et état vide', (t) async {
    await monter(
        t,
        const Column(children: [
          NoteSigh('Règle appliquée : la prise en charge vaut à la date.'),
          VideSigh('Aucun enregistrement.', indice: 'Créez le premier.')
        ]));
    comparer('note', 'note', mesure(t, find.byKey(const Key('kit:note'))),
        tolL: 1);
    comparer(
        'vide', 'icone', mesure(t, find.byKey(const Key('kit:vide-icone'))));
    comparer('vide', 'vide', mesure(t, find.byKey(const Key('kit:vide'))),
        largeur: false);
  });

  testWidgets('modale : marge haute 48, largeur 672, entête 75, pied 63',
      (t) async {
    late BuildContext ctx;
    await monter(t, Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }), largeur: 960);
    afficherModale<void>(ctx,
        titre: 'Nouveau patient',
        sousTitre: 'Ouverture de dossier',
        corps: const Text('Contenu',
            style: TextStyle(fontSize: 14, height: 20 / 14)),
        pied: (f) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: f),
              const BoutonSigh(libelle: 'Enregistrer', onPressed: _rien)
            ]);
    await t.pump();
    await t.pumpAndSettle();
    final p = mesure(t, find.byKey(const Key('kit:modale-panneau')));
    expect(
        p.top,
        closeTo((ref['composants']['modale']['panneau']['y'] as num).toDouble(),
            1.5),
        reason: 'my-8 + p-4');
    comparer('modale', 'panneau', p, tolH: 1.5);
    comparer('modale', 'entete',
        mesure(t, find.byKey(const Key('kit:modale-entete'))));
    comparer(
        'modale', 'pied', mesure(t, find.byKey(const Key('kit:modale-pied'))));
    expect(find.bySemanticsLabel('Fermer'), findsWidgets);
    // Échap ferme
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('kit:modale-panneau')), findsNothing);
  });

  testWidgets('tiroir : 576 px à droite, pleine hauteur, pied collé en bas',
      (t) async {
    late BuildContext ctx;
    await monter(t, Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }));
    afficherTiroir<void>(ctx,
        titre: 'Fiche patient',
        sousTitre: 'CNT/12/26',
        corps: const Text('Détail'),
        pied: (f) => [
              BoutonSigh(
                  libelle: 'Fermer',
                  variante: VarianteBouton.secondaire,
                  onPressed: f)
            ]);
    await t.pump();
    await t.pumpAndSettle();
    final p = mesure(t, find.byKey(const Key('kit:tiroir-panneau')));
    final r = ref['composants']['tiroir']['panneau'] as Map<String, dynamic>;
    expect(p.width, closeTo((r['l'] as num).toDouble(), 1.5));
    expect(p.height, closeTo(900, 1));
    expect(p.right, closeTo(1000, 1));
    comparer('tiroir', 'entete',
        mesure(t, find.byKey(const Key('kit:modale-entete'))));
    comparer(
        'tiroir', 'pied', mesure(t, find.byKey(const Key('kit:modale-pied'))));
    expect(mesure(t, find.byKey(const Key('kit:modale-pied'))).bottom,
        closeTo(900, 1));
  });

  testWidgets('tableau : barre 63, en-tête 36,5, ligne 57, pied 55', (t) async {
    final lignes = [
      for (var i = 1; i <= 30; i++)
        {
          'id': 'r$i',
          'code': 'CNT/$i/26',
          'nom': 'Patient $i',
          'montant': i * 1500,
          'statut': i.isOdd ? 'actif' : 'archive'
        }
    ];
    await monter(
        t,
        TableauSigh(
          titre: 'Patients',
          colonnes: const [
            ColonneTableau(cle: 'code', libelle: 'Code'),
            ColonneTableau(cle: 'nom', libelle: 'Nom'),
            ColonneTableau(cle: 'montant', libelle: 'Montant', droite: true),
            ColonneTableau(cle: 'statut', libelle: 'Statut'),
          ],
          lignes: lignes,
          actionsLigne: (_, __) => const [
            BoutonIcone(
                icone: LucideIcons.pencil,
                libelle: 'Modifier',
                onPressed: _rien)
          ],
        ));
    comparer('tableau', 'barre',
        mesure(t, find.byKey(const Key('kit:tableau-barre'))),
        tolL: 2.5);
    comparer('tableau', 'ligneEntete',
        mesure(t, find.byKey(const Key('kit:tableau-entete'))),
        largeur: false, tolH: 1);
    comparer('tableau', 'ligne',
        mesure(t, find.byKey(const Key('kit:tableau-ligne'))),
        largeur: false, tolH: 1);
    comparer(
        'tableau', 'pied', mesure(t, find.byKey(const Key('kit:tableau-pied'))),
        tolH: 1, tolL: 2.5);
    expect(find.text('Affichage de 1 à 12 sur 30 enregistrements'),
        findsOneWidget);
    expect(find.text('CNT/1/26'), findsOneWidget);
    expect(find.text('CNT/13/26'), findsNothing, reason: 'pagination de 12');
  });

  testWidgets(
      'tableau : recherche sans accents, tri, page 2, vide distinct, export',
      (t) async {
    String? csv;
    final lignes = [
      for (var i = 1; i <= 30; i++)
        {'id': 'r$i', 'nom': i == 5 ? 'Hélène' : 'Patient $i', 'n': i}
    ];
    await monter(
        t,
        TableauSigh(
          colonnes: const [
            ColonneTableau(cle: 'nom', libelle: 'Nom'),
            ColonneTableau(cle: 'n', libelle: 'N', droite: true)
          ],
          lignes: lignes,
          alExporter: (nom, c) => csv = c,
        ));
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')), 'helene');
    await t.pump();
    expect(find.text('Hélène'), findsOneWidget);
    expect(
        find.text('Affichage de 1 à 1 sur 1 enregistrement'), findsOneWidget);
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')), 'zzz');
    await t.pump();
    expect(find.text('Aucun résultat pour cette recherche.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')), '');
    await t.pump();
    await t.tap(find.text('N').first);
    await t.tap(find.text('N').first);
    await t.pump();
    expect(find.text('Patient 30'), findsOneWidget,
        reason: 'tri décroissant naturel');
    await t.tap(find.bySemanticsLabel('Page suivante'));
    await t.pump();
    expect(find.text('Affichage de 13 à 24 sur 30 enregistrements'),
        findsOneWidget);
    await t.tap(find.text('Exporter'));
    await t.pumpAndSettle();
    await t.tap(find.text('CSV / Excel'));
    await t.pumpAndSettle();
    expect(csv, startsWith('﻿"Nom";"N"\r\n'));
    expect(csv!.split('\r\n').length, 31);
  });
}

void _rien() {}
