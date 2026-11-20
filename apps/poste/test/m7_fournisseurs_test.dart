import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/m7/pv_factures_fournisseurs.dart';
import 'package:sigh_poste/modules/m7/pv_fournisseurs.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// Fournisseurs et factures fournisseurs (M7) : les règles sont rejouées sur les vecteurs du domaine ; ici, l'ÉCRAN — les gestes pilotés dans la
/// maquette (`vecteurs/fournisseurs_m7.json`, `vecteurs/factures_fournisseurs.json`), repris par le formulaire, le tiroir, l'archivage.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);

Map<String, Object?> doc(String nom) => (jsonDecode(File(
                '../../packages/domaine/test/vecteurs/$nom.json')
            .readAsStringSync()) as Map)
    .cast<String, Object?>();

List<Map<String, Object?>> liste(Object? v) => [
      for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()
    ];

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

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

Finder champ(String nom) => find.descendant(
    of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(TextField));

Future<void> saisir(WidgetTester t, String nom, String texte) =>
    t.enterText(champ(nom), texte);

String texteDuChamp(WidgetTester t, String nom) =>
    t.widget<TextField>(champ(nom)).controller!.text;

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

List<String?> kpis(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
        w.data
    ];

void memes(Object? obtenu, Object? attendu, String chemin,
    {Set<String> ignorer = const {}}) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      if (ignorer.contains(k)) continue;
      memes(o[k], attendu[k], '$chemin.$k');
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

void main() {
  setUpAll(chargerPolices);
  setUp(
      () => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  // ------------------------------------------------------------------ m7-fournisseurs
  group('m7-fournisseurs', () {
    final f = doc('fournisseurs_m7');
    final etat = (f['etat']! as Map).cast<String, Object?>();
    final casF = liste(f['cas']);
    Map<String, Object?> unCas(String motif) =>
        casF.firstWhere((c) => '${c['nom']}'.contains(motif));

    cas('indicateurs = ceux de l\'écran réel sur le même jeu ; onglets avec leur compte',
        (t) async {
      await ouvrir(t, magasin(), 'm7-fournisseurs');
      expect(kpis(t), [
        for (final k in ((etat['jeu']! as Map)['kpis']! as List)) (k as List)[1]
      ]);
      for (final o in ((etat['jeu']! as Map)['onglets']! as List)) {
        final libelle = '$o'.replaceFirst(RegExp(r'\d+$'), '');
        expect(find.textContaining(libelle), findsWidgets);
      }
    });

    cas('« Nouveau » : le fournisseur est écrit tel que la maquette l\'écrit (délai en nombre, case en booléen)',
        (t) async {
      final m = magasin();
      final c = unCas('création complète');
      final s = (c['saisie']! as Map).cast<String, Object?>();
      await ouvrir(t, m, 'm7-fournisseurs');
      await toucher(t, find.text('Nouveau'));
      expect(find.text('Nouveau fournisseur'), findsOneWidget);
      await saisir(t, 'code', '${s['code']}');
      await saisir(t, 'nom', '${s['nom']}');
      await choisir(t, 'type', '${s['type']}');
      await saisir(t, 'ville', '${s['ville']}');
      await saisir(t, 'tel', '${s['tel']}');
      await saisir(t, 'delai', '${s['delai']}');
      await toucher(t, find.text('Habilité pour les retours de produits périmés'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final cree = m.collection('fournisseurs').actives.first;
      memes(cree, (c['sortie']! as Map)['nouvelle'], 'fournisseur',
          ignorer: {'id'});
      expect(find.text('Nouveau fournisseur créé.'), findsOneWidget);
      expect(find.text('${s['code']}'), findsWidgets,
          reason: 'la référence est citée sous le message');
      // Annuler archive la fiche (RG-14) et le dit.
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('fournisseurs').actives.any((x) => x['code'] == s['code']),
          isFalse);
      expect(m.collection('fournisseurs').toutes.any((x) => x['code'] == s['code']),
          isTrue);
    });

    cas('« Nouveau » sans raison sociale : formulaire en erreur, rien n\'est écrit',
        (t) async {
      final m = magasin();
      final avant = m.collection('fournisseurs').toutes.length;
      await ouvrir(t, m, 'm7-fournisseurs');
      await toucher(t, find.text('Nouveau'));
      await saisir(t, 'code', 'TESTH');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('fournisseurs').toutes.length, avant);
    });

    cas('un code DÉJÀ pris est accepté : aucun contrôle d\'unicité (écart de la maquette, porté et signalé)',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm7-fournisseurs');
      await toucher(t, find.text('Nouveau'));
      await saisir(t, 'code', 'SOBAPS');
      await saisir(t, 'nom', 'Doublon SoBAPS');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(
          m.collection('fournisseurs').actives.where((x) => x['code'] == 'SOBAPS').length,
          2);
    });

    cas('« Modifier » : la modale est préremplie par la fiche ; le délai et l\'habilitation changent',
        (t) async {
      final m = magasin();
      final c = unCas('délai et habilitation');
      await ouvrir(t, m, 'm7-fournisseurs');
      final ligne = find.ancestor(
          of: find.text('CAME'), matching: find.byType(InkWell)).first;
      expect(ligne, findsOneWidget);
      // L'icône « Modifier » de la ligne CAME.
      final boutons = find.byTooltip('Modifier');
      expect(boutons, findsWidgets);
      // CAME est la première ligne triée par raison sociale.
      await toucher(t, boutons.first);
      expect(find.text('Modifier l’enregistrement'), findsOneWidget);
      final initiales = (c['valeursInitiales']! as Map).cast<String, Object?>();
      expect(texteDuChamp(t, 'code'), initiales['code']);
      expect(texteDuChamp(t, 'nom'), initiales['nom']);
      expect(texteDuChamp(t, 'delai'), initiales['delai']);
      await saisir(t, 'delai', '12');
      await toucher(t, find.text('Habilité pour les retours de produits périmés'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final apres = m.collection('fournisseurs').actives.firstWhere((x) => x['code'] == 'CAME');
      expect(apres['delai'], 12);
      expect(apres['habilite'], false);
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('fournisseurs').actives.firstWhere((x) => x['code'] == 'CAME')['delai'], 7);
    });

    cas('clic sur une ligne : le tiroir porte la fiche, les commandes et ses trois commandes en pied (Imprimer, Modifier, Archiver)',
        (t) async {
      await ouvrir(t, magasin(), 'm7-fournisseurs');
      final detail = liste(f['detail']).firstWhere((x) => x['code'] == 'NATIFOURN');
      await toucher(t, find.text('NATI Fournitures').first);
      await t.pumpAndSettle();
      final visibles = textesVisibles(t);
      for (final x in (detail['tiroir']! as List)) {
        final a = normaliser('$x');
        expect(visibles.any((v) => v == a || v.contains(a)), isTrue,
            reason: 'tiroir : « $x »');
      }
      expect(find.widgetWithText(BoutonSigh, 'Imprimer'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Modifier'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Archiver'), findsOneWidget);
    });

    cas('un fournisseur sans commande le dit', (t) async {
      await ouvrir(t, magasin(), 'm7-fournisseurs');
      await toucher(t, find.text('UBIPHARM Bénin').first);
      await t.pumpAndSettle();
      expect(find.text('Aucune commande enregistrée.'), findsOneWidget);
    });

    test('état imprimé = celui de la maquette (fiche, historique des commandes, TOTAL calculé)',
        () {
      final cmds = liste(etat['commandes']);
      for (final d in liste(f['detail'])) {
        final p = pieceFournisseur(
            (d['fiche']! as Map).cast<String, Object?>(), cmds,
            utilisateur: 'Test', edite: aujourdhui, reference: 'CNT-20261030-0001');
        final a = (d['impression']! as Map).cast<String, Object?>();
        expect(p.titre, a['titre']);
        expect(p.sousTitre, a['sousTitre']);
        expect([for (final c in p.cartouche) [c.$1, c.$2]], a['cartouche']);
        expect([for (final s in p.signatures) {'role': s.role, 'nom': s.nom}],
            a['signatures']);
        final contenu = liste(a['contenu']);
        if (contenu.isNotEmpty) {
          final tab = (contenu.single['table']! as Map).cast<String, Object?>();
          final t = p.blocs.whereType<BlocTableau>().single.tableau;
          expect([for (final c in t.colonnes) c.libelle], tab['entetes']);
          // Le vecteur a ses espaces normalisés (U+202F, U+00A0 -> « »).
          String sp(String x) => x.replaceAll(RegExp(r'\s+'), ' ');
          expect([for (final l in t.cellules) [for (final x in l) sp(x)]],
              tab['lignes']);
          expect([for (final x in t.pied!) sp(x)], (tab['pied']! as List).single);
        }
      }
    });

    cas('« Archiver » exige un MOTIF ; la fiche reste au magasin (RG-14) et l\'archivage s\'annule visiblement',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm7-fournisseurs');
      final avant = m.collection('fournisseurs').actives.length;
      await toucher(t, find.byTooltip('Archiver').first);
      await t.pumpAndSettle();
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
      await t.tap(find.text('Archiver').last);
      await t.pumpAndSettle();
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      expect(m.collection('fournisseurs').actives.length, avant);
      await t.enterText(find.byType(TextField).last, 'Fournisseur remplacé');
      await t.tap(find.text('Archiver').last);
      await t.pumpAndSettle();
      expect(m.collection('fournisseurs').actives.length, avant - 1);
      expect(m.collection('fournisseurs').toutes.length, avant);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('fournisseurs').actives.length, avant);
      expect(find.text('Archivage annulé.'), findsOneWidget);
    });

    cas('RBAC : la Direction consulte (lecture seule dite), sans Nouveau / Modifier / Archiver',
        (t) async {
      await ouvrir(t, magasin(), 'm7-fournisseurs', role: 'direction');
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      expect(find.text('Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
    });

    cas('RBAC : l\'assistant comptable écrit sans pouvoir archiver', (t) async {
      await ouvrir(t, magasin(), 'm7-fournisseurs', role: 'aide_comptable');
      expect(find.text('Nouveau'), findsOneWidget);
      expect(find.byTooltip('Modifier'), findsWidgets);
      expect(find.byTooltip('Archiver'), findsNothing);
    });
  });

  // ------------------------------------------------------------------ m7-factures-fournisseurs
  group('m7-factures-fournisseurs', () {
    final f = doc('factures_fournisseurs');
    final jeu = ((f['jeu']! as Map)['rendu']! as Map)['etat'] as Map;

    cas('indicateurs et bandeau d\'anomalie = ceux de l\'écran réel sur le même jeu', (t) async {
      await ouvrir(t, magasin(), 'm7-factures-fournisseurs');
      expect(kpis(t), [for (final k in (jeu['kpis']! as List)) (k as List)[1]]);
      expect(find.text('${jeu['noteTexte']}'), findsOneWidget);
    });

    cas('les en-têtes et les règlements sont ceux de la maquette ; pas de commande « Nouveau »',
        (t) async {
      await ouvrir(t, magasin(), 'm7-factures-fournisseurs');
      final textes = textesVisibles(t);
      for (final h in (jeu['entetes']! as List)) {
        expect(textes.any((x) => x.contains(normaliser('$h'))), isTrue,
            reason: 'en-tête $h');
      }
      expect(find.text('Nouveau'), findsNothing);
      expect(find.text('Payée'), findsWidgets);
      expect(find.text('Impayée'), findsWidgets);
    });

    for (final e in liste(f['editions'])) {
      cas('modifier — ${e['nom']}', (t) async {
        final m = magasin();
        final col = m.collection('facturesFournisseurs');
        // La pièce du pilotage, posée seule : même fiche, mêmes champs.
        for (final x in col.actives) {
          col.archiver(x['id']);
        }
        final avant = (e['avant']! as Map).cast<String, Object?>();
        col.inserer({...avant, 'id': 'FFT1', 'statut': 'actif'});
        await ouvrir(t, m, 'm7-factures-fournisseurs');
        await toucher(t, find.byTooltip('Modifier').first);
        // Le formulaire s'ouvre avec les valeurs de la maquette : « numero » et « montant » vides, les noms n'étant pas ceux de la fiche.
        final initiales = (e['valeursInitiales']! as Map).cast<String, Object?>();
        expect(texteDuChamp(t, 'numero'), initiales['numero']);
        expect(texteDuChamp(t, 'montant'), initiales['montant']);
        expect(texteDuChamp(t, 'fournisseur'), initiales['fournisseur']);
        final s = (e['saisie']! as Map).cast<String, Object?>();
        if (s.containsKey('numero')) await saisir(t, 'numero', '${s['numero']}');
        if (s.containsKey('montant')) await saisir(t, 'montant', '${s['montant']}');
        if (s.containsKey('statutPaiement')) {
          final libelle = {
            'payee': 'Payée',
            'partielle': 'Partielle',
            'impayee': 'Impayée'
          }['${s['statutPaiement']}']!;
          await choisir(t, 'statutPaiement', libelle);
        }
        await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
        final apres = col.parId('FFT1')!;
        final messages = liste(e['messages']);
        if (messages.first['type'] == 'error') {
          expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
          expect(apres['statutPaiement'], avant['statutPaiement']);
          return;
        }
        final diff = (e['diff']! as Map).cast<String, Object?>();
        for (final k in diff.keys) {
          if (diff[k] != null) memes(apres[k], diff[k], k);
        }
        // Le montant facturé NE BOUGE PAS : le champ « montant » n'est pas la colonne « montantFacture » (E21).
        expect(apres['montantFacture'], avant['montantFacture']);
        expect(apres['numeroFournisseur'], avant['numeroFournisseur']);
        // L'indicateur « Impayées » suit le règlement choisi.
        expect(kpis(t).last, ((e['apres']! as Map)['kpis'] as List).last[1]);
      });
    }

    cas('clic sur une ligne : le tiroir dit le verdict du rapprochement (anomalie / conforme)',
        (t) async {
      for (final x in liste(f['tiroirs'])) {
        final m = magasin();
        final col = m.collection('facturesFournisseurs');
        for (final y in col.actives) {
          col.archiver(y['id']);
        }
        col.inserer({...(x['fiche']! as Map).cast<String, Object?>(), 'id': 'FFT2'});
        await ouvrir(t, m, 'm7-factures-fournisseurs');
        await toucher(t, find.text('${(x['fiche']! as Map)['reference']}').first);
        await t.pumpAndSettle();
        final visibles = textesVisibles(t);
        for (final y in (x['texte']! as List)) {
          final a = normaliser('$y');
          expect(visibles.any((v) => v == a || v.contains(a)), isTrue,
              reason: '${x['reference']} : « $y »');
        }
        await t.pump(const Duration(seconds: 10));
      }
    });

    cas('RBAC : le gestionnaire de stock modifie et archive ; l\'assistant comptable modifie sans archiver ; la Direction consulte seulement',
        (t) async {
      await ouvrir(t, magasin(), 'm7-factures-fournisseurs', role: 'stock');
      expect(find.byTooltip('Modifier'), findsWidgets);
      expect(find.byTooltip('Archiver'), findsWidgets);
      await ouvrir(t, magasin(), 'm7-factures-fournisseurs', role: 'aide_comptable');
      expect(find.byTooltip('Modifier'), findsWidgets);
      expect(find.byTooltip('Archiver'), findsNothing);
      await ouvrir(t, magasin(), 'm7-factures-fournisseurs', role: 'direction');
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
    });

    test('le formulaire propose les noms de champs de la maquette, dans son ordre', () {
      expect([for (final c in champsFactureFournisseur) c.nom],
          ['numero', 'date', 'fournisseur', 'montant', 'echeance', 'statutPaiement']);
    });
  });
}
