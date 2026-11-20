import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' hide normaliser;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/m7/pv_reception.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// PV de réception (M7) : les règles sont rejouées sur les vecteurs du domaine ; ici, l'ÉCRAN — le geste « Nouveau PV » repris, cas par cas, sur
/// les situations pilotées dans la maquette (`packages/domaine/test/vecteurs/pv_reception.json`), ce qui est écrit, refusé, annulable, imprimé.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);

Map<String, Object?> doc() => (jsonDecode(File(
                '../../packages/domaine/test/vecteurs/pv_reception.json')
            .readAsStringSync()) as Map)
    .cast<String, Object?>();

List<Map<String, Object?>> liste(Object? v) => [
      for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()
    ];

/// Le jeu SANS registre de PV : les tests partent d'un registre vide et posent leurs propres fiches (le jeu amorcé a son test).
Magasin magasin() => Magasin.depuisDossier(
    [for (final c in Magasin.collectionsDuJeu) if (c != 'pvReceptions') c]);

/// Pose dans le magasin du test les bons de livraison et les produits que la maquette avait au moment du pilotage.
void poser(Magasin m, Map<String, Object?> entree) {
  for (final p in liste(entree['produits'])) {
    m.collection('produits').inserer({...p, 'statut': 'actif'});
  }
  for (final l in liste(entree['livraisons'])) {
    m.collection('livraisons').inserer({...l, 'statut': 'actif'});
  }
}

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
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

Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(
      t,
      find.descendant(
              of: find.byKey(Key('kit:champ:$champ')),
              matching: find.byType(InkWell))
          .first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> saisir(WidgetTester t, String champ, String texte) => t.enterText(
    find.descendant(
        of: find.byKey(Key('kit:champ:$champ')),
        matching: find.byType(TextField)),
    texte);

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void memes(Object? obtenu, Object? attendu, String chemin,
    {Set<String> ignorer = const {}}) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      if (ignorer.contains(k)) continue;
      memes(o[k], attendu[k], '$chemin.$k');
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]');
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

String ecranDe(String nature) => 'm7-pv-reception-$nature';

void main() {
  setUpAll(chargerPolices);
  setUp(
      () => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  final d = doc();

  cas('registre vide : état vide dit, quatre indicateurs à zéro, « Nouveau PV » offert',
      (t) async {
    for (final nature in [natureConsommables, natureReactifs]) {
      await ouvrir(t, magasin(), ecranDe(nature));
      expect(find.text('Aucun PV établi.'), findsOneWidget);
      expect([
        for (final w
            in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
          w.data
      ], ['0', '0', '0', '0']);
      expect(find.text('Nouveau PV'), findsOneWidget);
    }
  });

  cas('le jeu amorcé (comme la maquette, qui l\'amorce à l\'ouverture de l\'écran) : PV de démonstration, par nature, avec leurs indicateurs',
      (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    final pv = m.collection('pvReceptions').actives;
    expect(pv.where((x) => x['nature'] == 'consommables').length, 4);
    expect(pv.where((x) => x['nature'] == 'reactifs').length, 2);
    for (final nature in [natureConsommables, natureReactifs]) {
      await ouvrir(t, m, ecranDe(nature));
      final propres = pv.where((x) => x['nature'] == nature).toList();
      final res = resumerPv(propres);
      expect([
        for (final w
            in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
          w.data
      ], [
        nombre(res.etablis),
        nombre(res.conformes),
        nombre(res.avecReserves),
        nombre(res.nonConformes)
      ]);
      // Un registre ne montre que SA nature.
      for (final autre in pv.where((x) => x['nature'] != nature)) {
        expect(find.text('${autre['reference']}'), findsNothing);
      }
    }
  });

  // Les situations de la maquette, rejouées PAR L'ÉCRAN (la date du jour du banc est celle des vecteurs : 30/10/2026).
  for (final c in liste(d['cas'])) {
    final saisie = (liste([(c['entree']! as Map)['saisie']]).single);
    if (saisie['date'] != '2026-10-30') continue;
    cas('${c['nom']}', (t) async {
      final m = magasin();
      final e = (c['entree']! as Map).cast<String, Object?>();
      poser(m, e);
      final nature = '${c['nature']}';
      await ouvrir(t, m, ecranDe(nature));
      await toucher(t, find.text('Nouveau PV'));
      await choisir(t, 'livraisonRef', '${saisie['livraisonRef']} — ${m.collection('livraisons').actives.firstWhere((l) => l['reference'] == saisie['livraisonRef'])['fournisseurNom']}');
      if (nature == natureReactifs && saisie['chaineFroid'] == false) {
        await toucher(t, find.text('Chaîne du froid respectée à l’arrivée'));
      }
      if (saisie['conclusion'] != 'Conforme') {
        await choisir(t, 'conclusion', '${saisie['conclusion']}');
      }
      if ('${saisie['reserves']}'.isNotEmpty) {
        await saisir(t, 'reserves', '${saisie['reserves']}');
      }
      await saisir(t, 'representantFournisseur',
          '${saisie['representantFournisseur']}');
      await toucher(t, find.text('Établir le PV'));
      final s = (c['sortie']! as Map).cast<String, Object?>();
      final crees = m.collection('pvReceptions').actives;
      if (s['pv'] == null) {
        expect(crees, isEmpty, reason: 'rien n\'est écrit');
        final messages = liste(s['messages']);
        if (messages.isNotEmpty) {
          expect(find.text('${messages.first['message']}'), findsOneWidget);
        }
        return;
      }
      final pv = crees.single;
      // Le jeu du poste ne contient aucun PV : la série repart à 1 (la maquette, elle, continuait ses PV amorcés).
      memes(pv, s['pv'], 'pv', ignorer: {'reference', 'id'});
      expect(pv['reference'],
          'PV-${sigleNature(nature)}-2026-0001');
      expect(find.text('PV ${pv['reference']} établi.'), findsOneWidget);
      // La pièce s'ouvre à l'établissement (la maquette imprime aussitôt).
      expect(find.text('PROCÈS-VERBAL DE RÉCEPTION'), findsWidgets);
    });
  }

  cas('annuler après l\'établissement archive le PV (RG-14) : la fiche reste au magasin',
      (t) async {
    final m = magasin();
    final c = liste(d['cas']).firstWhere((x) => x['sortie'] != null && (x['sortie'] as Map)['pv'] != null && x['nature'] == 'consommables');
    poser(m, (c['entree']! as Map).cast<String, Object?>());
    await ouvrir(t, m, ecranDe(natureConsommables));
    final saisie = (c['entree']! as Map)['saisie'] as Map;
    await toucher(t, find.text('Nouveau PV'));
    await choisir(t, 'livraisonRef', '${saisie['livraisonRef']} — NATI Fournitures');
    await saisir(t, 'representantFournisseur', 'Livreur');
    await toucher(t, find.text('Établir le PV'));
    expect(m.collection('pvReceptions').actives.length, 1);
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('pvReceptions').actives, isEmpty);
    expect(m.collection('pvReceptions').toutes.length, 1,
        reason: 'archivage LOGIQUE : jamais de suppression physique');
  });

  cas('la modale ne propose que les bons de la nature : consommables ≠ réactifs',
      (t) async {
    final m = magasin();
    final c = liste(d['cas']).first;
    poser(m, (c['entree']! as Map).cast<String, Object?>());
    await ouvrir(t, m, ecranDe(natureReactifs));
    await toucher(t, find.text('Nouveau PV'));
    // LV-T02 ne porte que des consommables : il n'est pas offert aux réactifs.
    await toucher(
        t,
        find.descendant(
                of: find.byKey(const Key('kit:champ:livraisonRef')),
                matching: find.byType(InkWell))
            .first);
    expect(find.textContaining('LV-T03'), findsWidgets);
    expect(find.textContaining('LV-T02'), findsNothing);
    expect(find.text('Chaîne du froid respectée à l’arrivée'), findsOneWidget);
  });

  cas('consommables : pas de case « chaîne du froid » (null, jamais un booléen qui affirmerait un contrôle)',
      (t) async {
    final m = magasin();
    poser(m, (liste(d['cas']).first['entree']! as Map).cast<String, Object?>());
    await ouvrir(t, m, ecranDe(natureConsommables));
    await toucher(t, find.text('Nouveau PV'));
    expect(find.text('Chaîne du froid respectée à l’arrivée'), findsNothing);
  });

  cas('sans bon de la nature : refus nommé, aucune modale', (t) async {
    for (final x in liste(d['sansLivraison'])) {
      final m = magasin();
      // Aucune livraison active : celles du jeu sont archivées (le cas de la maquette).
      for (final l in m.collection('livraisons').actives) {
        m.collection('livraisons').archiver(l['id']);
      }
      await ouvrir(t, m, ecranDe('${x['nature']}'));
      await toucher(t, find.text('Nouveau PV'));
      expect(find.text('${liste(x['messages']).single['message']}'),
          findsOneWidget);
      expect(find.byKey(const Key('kit:champ:livraisonRef')), findsNothing);
      await t.pump(const Duration(seconds: 10));
    }
  });

  cas('RBAC : la Direction consulte sans pouvoir établir (commande ABSENTE, pas grisée)',
      (t) async {
    await ouvrir(t, magasin(), ecranDe(natureConsommables), role: 'direction');
    expect(find.text('PV de réception — consommables'), findsWidgets);
    expect(find.text('Nouveau PV'), findsNothing);
  });

  group('registre, tiroir et pièce imprimée repris de la maquette', () {
    for (final r in liste(d['registres'])) {
      final nature = '${r['nature']}';
      cas('registre « $nature » : indicateurs, lignes et tiroir', (t) async {
        final m = magasin();
        for (final p in liste(r['pvs'])) {
          m.collection('pvReceptions').inserer({...p});
        }
        await ouvrir(t, m, ecranDe(nature));
        // Indicateurs : les mêmes libellés et les mêmes valeurs que l'écran réel.
        final valeurs = [
          for (final w
              in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
            w.data
        ];
        expect(valeurs, [for (final k in (r['kpis']! as List)) (k as List)[1]]);
        final textes = textesVisibles(t);
        for (final h in (r['entetes']! as List)) {
          expect(textes.any((x) => x.contains(normaliser('$h'))), isTrue,
              reason: 'en-tête $h');
        }
        // Le tiroir du PV le plus récent porte tout ce que la maquette y affiche.
        final ouvert = (r['pvOuvert']! as Map).cast<String, Object?>();
        await toucher(t, find.text('${ouvert['reference']}').first);
        await t.pumpAndSettle();
        final tiroir = textesVisibles(t);
        for (final x in (r['tiroir']! as List)) {
          final a = normaliser('$x');
          expect(tiroir.any((v) => v == a || v.contains(a)), isTrue,
              reason: 'tiroir : « $x »');
        }
      });

      test('pièce imprimée « $nature » = celle de la maquette', () {
        final ouvert = (r['pvOuvert']! as Map).cast<String, Object?>();
        final attendu = (r['impression']! as Map).cast<String, Object?>();
        verifierPiece(
            piecePv(ouvert,
                nature: nature,
                utilisateur: 'Test',
                edite: aujourdhui,
                reference: 'CNT-20261030-0001'),
            attendu);
      });
    }

    for (final c in liste(d['cas'])) {
      final s = (c['sortie']! as Map).cast<String, Object?>();
      if (s['impression'] == null) continue;
      test('pièce imprimée — ${c['nom']}', () {
        verifierPiece(
            piecePv((s['pv']! as Map).cast<String, Object?>(),
                nature: '${c['nature']}',
                utilisateur: 'Test',
                edite: aujourdhui,
                reference: 'CNT-20261030-0001'),
            (s['impression']! as Map).cast<String, Object?>());
      });
    }
  });
}

/// La pièce Dart reprend celle de la maquette : titre, cartouche, tableau (sans total), paragraphes dans l'ordre, trois signatures.
void verifierPiece(PieceA4 p, Map<String, Object?> attendu) {
  expect(p.titre, attendu['titre']);
  expect(p.sousTitre, attendu['sousTitre']);
  expect([for (final c in p.cartouche) [c.$1, c.$2]], attendu['cartouche']);
  final contenu = liste(attendu['contenu']);
  final blocs = p.blocs;
  expect(blocs.length, contenu.length, reason: 'nombre de blocs');
  for (var i = 0; i < contenu.length; i++) {
    final x = contenu[i];
    final b = blocs[i];
    if (x['table'] != null) {
      final t = (x['table']! as Map).cast<String, Object?>();
      final tab = (b as BlocTableau).tableau;
      expect([for (final c in tab.colonnes) c.libelle], t['entetes']);
      expect(tab.cellules, t['lignes']);
      expect(tab.pied, t['pied'] is List && (t['pied'] as List).isEmpty ? isNull : isNotNull,
          reason: 'aucun total imprimé (somme déclarée mais total non activé : E19)');
    } else {
      expect((b as BlocTexte).texte, x['texte']);
    }
  }
  expect([for (final s in p.signatures) {'role': s.role, 'nom': s.nom}],
      attendu['signatures']);
}
