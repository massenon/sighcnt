import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Les six écrans de stock de M6 (`m6-dashboard`, `m6-produits`, `m6-stock-gros`, `m6-stock-detail`, `m6-lots`, `m6-alertes`).
///
/// Deux familles de tests :
///  - la PARITÉ CHIFFRÉE : le même jeu d'essai que celui posé dans la maquette (`packages/domaine/test/vecteurs/stock.json`, engendré par
///    `prototype_html/build/vecteurs-stock.js`) est monté dans Flutter, et chaque KPI et chaque ligne de tableau doit être celle que la maquette a
///    AFFICHÉE, au caractère près ;
///  - le COMPORTEMENT : création et refus, archivage annulable, droits, seuil non fixé, jour d'échéance.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(
    File('../../packages/domaine/test/vecteurs/stock.json')
        .readAsStringSync()) as Map<String, Object?>);
final auj = DateTime(2026, 8, 16);

List<Fiche> liste(Object? o) =>
    [for (final x in (o! as List)) (x as Map).cast<String, Object?>()];
Map<String, Object?> carte(Object? o) => (o! as Map).cast<String, Object?>();
Map<String, Object?> sorties() => carte(vecteurs['sorties']);

List<Fiche> fournisseurs() => liste(jsonDecode(
    File('assets/donnees/jeu/fournisseurs.json').readAsStringSync()));

/// Le magasin du jeu d'essai de la maquette (produits, lots, mouvements) + le référentiel des fournisseurs du jeu.
Magasin magasinEssai() {
  final jeu = carte(vecteurs['jeu']);
  return Magasin({
    'produits': liste(jeu['produits']),
    'lots': liste(jeu['lots']),
    'mouvements': liste(jeu['mouvements']),
    'fournisseurs': fournisseurs(),
  });
}

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin', DateTime? le}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => le ?? auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

/// (libellé, valeur) de chaque KPI affiché.
Map<String, String> kpisAffiches(WidgetTester t) {
  final l = [
    for (final w
        in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle'))))
      w.data!
  ];
  final v = [
    for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
      w.data!
  ];
  return {for (var i = 0; i < l.length; i++) l[i]: v[i]};
}

void verifierKpis(WidgetTester t, Object? ecranVecteur) {
  final affiches = kpisAffiches(t);
  final attendus = liste(carte(ecranVecteur)['kpis']);
  expect(affiches.length, attendus.length, reason: 'nombre de KPI');
  for (final k in attendus) {
    expect(affiches[k['libelle']], k['valeur'], reason: '${k['libelle']}');
  }
}

/// Le texte d'une LIGNE de tableau : tous les textes alignés verticalement sur le texte repère [repere] (le code, le n° de lot…), de gauche à
/// droite. La case de sélection et les icônes d'action n'ont pas de texte ; la désignation sur deux lignes est jointe par une espace.
String ligneAffichee(WidgetTester t, String repere, {int occurrence = 0}) {
  final r = find.text(repere).evaluate().toList()[occurrence];
  final dy = t.getCenter(find.byWidget(r.widget)).dy;
  final cellules = <(double, double, String)>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    if (w.data == null || w.data!.trim().isEmpty) continue;
    final c = t.getCenter(find.byWidget(w));
    if ((c.dy - dy).abs() <= 22 && c.dy > 0) {
      // les cellules sont rangées par COLONNE (bord gauche), puis de haut en bas pour une cellule sur deux lignes
      final g = t.getTopLeft(find.byWidget(w));
      cellules.add((g.dx, g.dy, w.data!));
    }
  }
  cellules.sort((a, b) {
    final x = (a.$1 - b.$1).abs() < 1 ? 0 : a.$1.compareTo(b.$1);
    return x != 0 ? x : a.$2.compareTo(b.$2);
  });
  return cellules.map((c) => c.$3).join(' ');
}

/// Les cellules NON VIDES d'une ligne lue dans la maquette, jointes.
String ligneAttendue(List<Object?> cellules, {Set<int> sauf = const {}}) => [
      for (final (i, c) in cellules.indexed)
        if ('$c'.isNotEmpty && !sauf.contains(i)) '$c'
    ].join(' ');

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité chiffrée avec la maquette (jeu d\'essai des vecteurs)', () {
    cas('m6-dashboard : les huit KPI, les deux bandeaux et le tableau des produits à réapprovisionner',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-dashboard');
      final d = carte(sorties()['dashboard']);
      verifierKpis(t, d);
      for (final n in (d['notes']! as List)) {
        expect(find.text('$n'), findsOneWidget);
      }
      final lignes = (carte((d['tableaux']! as List).first)['lignes']! as List);
      // la 4ᵉ colonne du tableau est la désignation d'un produit en stock 0 : chaque ligne est celle que la maquette a lue
      var dyPrecedent = -1.0;
      for (final l in lignes) {
        final code = '${(l as List)[0]}';
        final dy = t.getCenter(find.text(code)).dy;
        expect(dy, greaterThan(dyPrecedent),
            reason: 'ordre des lignes : $code');
        dyPrecedent = dy;
        expect(ligneAffichee(t, code), ligneAttendue(l), reason: code);
      }
    });

    cas('m6-dashboard : le magasin vide dit « Aucun produit sous le seuil d\'alerte. » et ne montre aucun bandeau',
        (t) async {
      await ouvrir(t, Magasin(), 'm6-dashboard');
      verifierKpis(t, carte(sorties()['vide'])['dashboard']);
      expect(
          find.text('Aucun produit sous le seuil d’alerte.'), findsOneWidget);
      expect(find.textContaining('sous le seuil d’alerte — établir'),
          findsNothing);
    });

    cas('m6-produits : KPI, ordre et ligne à ligne (valeur au CUMP, état)',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-produits');
      final p = carte(sorties()['produits']);
      verifierKpis(t, p);
      final table = carte((p['tableaux']! as List).first);
      var dyPrecedent = -1.0;
      for (final l in (table['lignes']! as List)) {
        final cellules = l as List;
        final code = '${cellules[1]}';
        final dy = t.getCenter(find.text(code)).dy;
        expect(dy, greaterThan(dyPrecedent), reason: 'ordre : $code');
        dyPrecedent = dy;
        // colonne 0 : case de sélection ; dernière : actions
        expect(ligneAffichee(t, code), ligneAttendue(cellules), reason: code);
      }
    });

    cas('m6-produits : un seuil non fixé s\'affiche « — » dans le tableau, « Non fixé » dans la fiche (jamais un zéro)',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-produits');
      await toucher(t, find.text('GANTS NON STERILES'));
      await t.pumpAndSettle();
      expect(find.text('Non fixé — signalé à part'), findsOneWidget);
    });

    for (final (id, cle) in [
      ('m6-stock-gros', 'stockGros'),
      ('m6-stock-detail', 'stockDetail')
    ]) {
      cas('$id : KPI, lignes du stock et mouvements de la période (30 jours jusqu\'au 16/08)',
          (t) async {
        await ouvrir(t, magasinEssai(), id);
        final e = carte(sorties()[cle]);
        verifierKpis(t, e);
        final table = carte((e['tableaux']! as List).first);
        for (final l in (table['lignes']! as List)) {
          final cellules = l as List;
          expect(ligneAffichee(t, '${cellules[0]}'), ligneAttendue(cellules),
              reason: '${cellules[0]}');
        }
        final mvts = carte(e['mouvementsDefaut']);
        for (final l in (mvts['lignes']! as List)) {
          final cellules = l as List;
          // le justificatif identifie un mouvement (BL-001, BS-003…)
          expect(ligneAffichee(t, '${cellules[4]}'), ligneAttendue(cellules),
              reason: '${cellules[4]}');
        }
        expect(find.text('Mouvements du'), findsOneWidget);
        expect(find.text('Mouvements de la période — le flux, pas l’état'),
            findsOneWidget);
      });
    }

    cas('m6-lots : KPI, échéances à la date du jour, et ordre de sortie FEFO',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-lots');
      final e = carte(sorties()['lots']);
      verifierKpis(t, e);
      final table = carte((e['tableaux']! as List).first);
      for (final l in (table['lignes']! as List)) {
        final cellules = l as List;
        expect(ligneAffichee(t, '${cellules[1]}'), ligneAttendue(cellules),
            reason: '${cellules[1]}');
      }
      await toucher(t, find.byKey(const Key('kit:onglet:fefo')));
      await t.pump();
      final fefo = carte(e['fefo']);
      var dyPrecedent = -1.0;
      for (final l in (fefo['lignes']! as List)) {
        final cellules = l as List;
        final lot = '${cellules[2]}';
        final dy = t.getCenter(find.text(lot)).dy;
        expect(dy, greaterThan(dyPrecedent),
            reason: 'rang ${cellules[0]} : $lot');
        dyPrecedent = dy;
        expect(ligneAffichee(t, lot), ligneAttendue(cellules), reason: lot);
      }
    });

    cas('m6-alertes : KPI et, onglet par onglet, les lignes lues dans la maquette',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-alertes');
      final e = carte(sorties()['alertes']);
      verifierKpis(t, e);
      final par = carte(e['parOnglet']);
      final ongletRuptures = carte(par['Ruptures']);
      for (final l in (ongletRuptures['lignes']! as List)) {
        final cellules = l as List;
        final code = '${cellules[0]}';
        final lue = ligneAffichee(t, code);
        // « À commander » : la maquette écrit 0 quand le seuil manque ; Flutter écrit un tiret (non calculable, écart E18)
        if (code == 'GNS') {
          expect(lue, ligneAttendue(cellules).replaceFirst('— 0', '— —'));
        } else {
          expect(lue, ligneAttendue(cellules), reason: code);
        }
      }
      await toucher(t, find.byKey(const Key('kit:onglet:seuil')));
      for (final l in (carte(par['Sous le seuil'])['lignes']! as List)) {
        final cellules = l as List;
        expect(ligneAffichee(t, '${cellules[0]}'), ligneAttendue(cellules),
            reason: '${cellules[0]}');
      }
      await toucher(t, find.byKey(const Key('kit:onglet:peremption')));
      for (final l in (carte(par['Péremptions'])['lignes']! as List)) {
        final cellules = l as List;
        expect(ligneAffichee(t, '${cellules[1]}'), ligneAttendue(cellules),
            reason: '${cellules[1]}');
      }
    });
  });

  group('création, modification, archivage', () {
    Future<void> saisir(WidgetTester t, String champ, String valeur) async {
      await t.enterText(
          find.descendant(
              of: find.byKey(Key('kit:champ:$champ')),
              matching: find.byType(TextField)),
          valeur);
      await t.pump();
    }

    cas('un médicament créé se vend au prix d\'achat (RG-02), le stock est la somme gros + détail, la fiche est insérée en tête et le geste est annulable',
        (t) async {
      final m = magasinEssai();
      await ouvrir(t, m, 'm6-produits');
      final col = m.collection('produits');
      final avant = col.actives.length;
      await toucher(t, find.text('Nouveau'));
      expect(find.text('Nouveau produit'), findsOneWidget);
      await saisir(t, 'code', 'NOUV');
      await saisir(t, 'designation', 'ARTICLE D\'ESSAI');
      await saisir(t, 'prixAchat', '500');
      await saisir(t, 'prixVente', '700');
      await saisir(t, 'stockGros', '3');
      await saisir(t, 'stockDetail', '4');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(col.actives.length, avant + 1);
      final p = col.actives.first;
      expect(p['code'], 'NOUV');
      expect(p['prixVente'], 500,
          reason: 'RG-02 : pas de marge sur un médicament');
      expect(p['cump'], 500);
      expect(p['stock'], 7);
      expect(p['seuilAlerte'], 10);
      expect(p['statut'], 'actif');
      expect(find.text('Nouveau produit créé.'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pump(const Duration(milliseconds: 300));
      expect(col.actives.length, avant);
      expect(col.parId(p['id']), isNotNull,
          reason: 'RG-14 : l\'annulation archive, elle ne supprime pas');
      expect(find.text('Action annulée.'), findsOneWidget);
    });

    cas('RG-03 : un stock négatif est REFUSÉ en le disant, rien n\'est écrit',
        (t) async {
      final m = magasinEssai();
      await ouvrir(t, m, 'm6-produits');
      final col = m.collection('produits');
      final avant = col.toutes.length;
      await toucher(t, find.text('Nouveau'));
      await saisir(t, 'code', 'NEG');
      await saisir(t, 'designation', 'NEGATIF');
      await saisir(t, 'prixAchat', '100');
      await saisir(t, 'stockGros', '-1');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('RG-03 — le stock ne peut pas devenir négatif.'),
          findsOneWidget);
      expect(col.toutes.length, avant);
      expect(find.text('Nouveau produit'), findsOneWidget,
          reason: 'la saisie reste ouverte pour être corrigée');
    });

    cas('un champ obligatoire manquant (code, prix d\'achat) bloque l\'enregistrement',
        (t) async {
      final m = magasinEssai();
      await ouvrir(t, m, 'm6-produits');
      final avant = m.collection('produits').toutes.length;
      await toucher(t, find.text('Nouveau'));
      await saisir(t, 'designation', 'SANS CODE');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);
      expect(m.collection('produits').toutes.length, avant);
    });

    cas('modifier un lot recalcule son statut à la date du jour (périmé depuis le 17/08) et la modification est annulable',
        (t) async {
      final m = magasinEssai();
      await ouvrir(t, m, 'm6-lots', le: DateTime(2026, 10, 30));
      final col = m.collection('lots');
      final lot = col.actives.firstWhere((l) => l['numeroLot'] == 'LOT-D04');
      expect(lot['statut'], 'alerte',
          reason: 'statut figé à la saisie, au 16/08');
      // l'icône « Modifier » de la ligne de LOT-D04
      final dy = t.getCenter(find.text('LOT-D04')).dy;
      final modifier = find.byTooltip('Modifier').evaluate().firstWhere(
          (e) => (t.getCenter(find.byWidget(e.widget)).dy - dy).abs() < 22);
      await toucher(t, find.byWidget(modifier.widget));
      expect(find.text('Modifier le lot'), findsOneWidget);
      await saisir(t, 'numeroLot', 'LOT-D04-BIS');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final apres = col.parId(lot['id'])!;
      expect(apres['numeroLot'], 'LOT-D04-BIS');
      expect(apres['statut'], 'perime', reason: 'recalculé à la date du jour');
      expect(apres['produit'], 'REACTIF GLYCEMIE');
      expect(find.text('Modification enregistrée.'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pump(const Duration(milliseconds: 300));
      expect(col.parId(lot['id'])!['numeroLot'], 'LOT-D04');
      expect(col.parId(lot['id'])!['statut'], 'alerte');
      expect(find.text('Action annulée.'), findsOneWidget);
    });

    cas('archiver est confirmé, visible et ANNULABLE ; la fiche reste au magasin (RG-14)',
        (t) async {
      final m = magasinEssai();
      await ouvrir(t, m, 'm6-produits');
      final col = m.collection('produits');
      final avant = col.actives.length;
      await toucher(t, find.byTooltip('Archiver').first);
      await t.pumpAndSettle();
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
      await t.tap(find.text('Archiver').last);
      await t.pumpAndSettle();
      expect(col.actives.length, avant - 1);
      expect(col.archivees.length, 1);
      expect(find.text('Enregistrement archivé.'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(col.actives.length, avant);
      expect(find.text('Action annulée.'), findsOneWidget);
    });
  });

  group('droits', () {
    cas('le gestionnaire de stock écrit ; la direction (lecture) n\'a ni Nouveau, ni Modifier, ni Archiver et le dit',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-produits', role: 'stock');
      expect(find.text('Nouveau'), findsOneWidget);
      expect(find.byTooltip('Modifier'), findsWidgets);
      expect(find.byTooltip('Archiver'), findsWidgets);
      await ouvrir(t, magasinEssai(), 'm6-produits', role: 'direction');
      expect(find.text('Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing,
          reason: 'commande ABSENTE, pas grisée');
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      await ouvrir(t, magasinEssai(), 'm6-lots', role: 'comptable');
      expect(find.text('Nouveau'), findsNothing);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
    });

    cas('m6-dashboard et m6-stock-gros sont FERMÉS au caissier : la coque ne les ouvre pas',
        (t) async {
      for (final id in ['m6-dashboard', 'm6-stock-gros']) {
        expect(donnees.matrice.peutVoir('caissier', id), isFalse, reason: id);
        await ouvrir(t, magasinEssai(), id, role: 'caissier');
        expect(find.text('Tableau de bord — Stocks'), findsNothing);
        expect(find.text('Stock gros (magasin central)'), findsNothing);
      }
      // …mais il garde le référentiel, le stock détail et les alertes
      for (final id in ['m6-produits', 'm6-stock-detail', 'm6-alertes']) {
        expect(donnees.matrice.peutVoir('caissier', id), isTrue, reason: id);
      }
    });
  });

  group('alertes', () {
    cas('l\'alerte SIGNALE, le circuit COMMANDE : aucun bon de commande ici, un renvoi aux bons de besoins (M7)',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-alertes');
      expect(find.textContaining('Établir un bon de commande'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Ouvrir les bons de besoins (M7)'),
          findsOneWidget);
      await toucher(t,
          find.widgetWithText(BoutonSigh, 'Ouvrir les bons de besoins (M7)'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Alertes & seuils'), findsNothing,
          reason: 'le bouton ouvre m7-besoins');
    });

    cas('un seuil NON FIXÉ n\'est pas un seuil de zéro : l\'article est signalé à part et sa quantité à commander est « — »',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-alertes');
      expect(find.textContaining('2 article(s) sans seuil d’alerte fixé'),
          findsOneWidget);
      // GNS est en rupture, sans seuil : « à commander » n'est pas calculable
      expect(ligneAffichee(t, 'GNS'), endsWith('0 0 0 — — SOBAPS Rupture'),
          reason: 'seuil « — » et à commander « — », jamais « 0 »');
    });

    cas('le jeu de la clinique (tous les seuils fixés) n\'affiche aucun bandeau « sans seuil »',
        (t) async {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      await ouvrir(t, m, 'm6-alertes');
      expect(find.textContaining('sans seuil d’alerte fixé'), findsNothing);
    });

    cas('le jour d\'échéance se compte en jours calendaires : l\'après-midi, un lot qui périme aujourd\'hui reste « Dans 0 j », pas « Périmé depuis 1 j »',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-lots',
          le: DateTime(2026, 8, 16, 15, 45));
      expect(ligneAffichee(t, 'LOT-B03'), contains('Dans 0 j'));
      expect(ligneAffichee(t, 'LOT-B02'), contains('Périmé depuis 1 j'));
      expect(ligneAffichee(t, 'LOT-D04'), contains('Dans 1 j'));
    });

    cas('le statut d\'un lot suit la date du jour (RG-05) : le même lot est « proche » le 16/08, « périmé » deux mois plus tard',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-lots', le: DateTime(2026, 10, 30));
      // LOT-D04 périmait le 17/08 : il est périmé à la date du jour, quel que soit le statut figé du jeu
      expect(ligneAffichee(t, 'LOT-D04'), contains('Périmé depuis 74 j'));
      expect(ligneAffichee(t, 'LOT-D04'), contains('Périmé'));
    });
  });

  group('fiche produit et états imprimés', () {
    cas('la fiche en tiroir porte la fiche, les lots FEFO et les mouvements, et ses commandes selon les droits',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-produits');
      await toucher(t, find.text('PARACETAMOL 500 MG'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('kit:tiroir-panneau')), findsOneWidget);
      expect(find.text('Stock total'), findsOneWidget);
      expect(find.text('Valeur au CUMP'), findsOneWidget);
      expect(find.textContaining('Fiche produit'), findsOneWidget);
      expect(find.textContaining('Lots (FEFO)'), findsOneWidget);
      expect(find.textContaining('Mouvements'), findsWidgets);
      expect(find.text('Sans marge (RG-02)'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Modifier'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Archiver'), findsOneWidget);
    });

    cas('les états s\'impriment : fiche article, état du stock, état des produits périmés',
        (t) async {
      await ouvrir(t, magasinEssai(), 'm6-lots');
      await toucher(
          t, find.widgetWithText(BoutonSigh, 'État des produits périmés'));
      await t.pumpAndSettle();
      expect(find.text('État des produits périmés'), findsWidgets);
      expect(find.textContaining('Lots concernés'), findsWidgets);
    });
  });
}
