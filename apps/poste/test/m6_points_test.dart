import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Les deux points du gestionnaire de stock : la règle est rejouée par `packages/domaine/test/points_test.dart` ; ici, l'ÉCRAN — ce que l'agent
/// lit après avoir réglé les commandes, comparé aux vecteurs tirés des écrans réels de la maquette (`vecteurs/points.json`).
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 8, 16);

Map<String, Object?> vecteurs() => (jsonDecode(File('../../packages/domaine/test/vecteurs/points.json')
        .readAsStringSync()) as Map)
    .cast<String, Object?>();

Map<String, Object?> cas(String famille, String nom) =>
    ((vecteurs()[famille] as List).cast<Map>().firstWhere((c) => c['nom'] == nom)).cast<String, Object?>();

String norm(Object? s) => '${s ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
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

Finder champ(String nom) => find.descendant(
    of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(InkWell));

/// Ouvre la liste du champ [nom], y cherche [cible] si elle n'est pas visible, la choisit ; une liste à choix multiples reste ouverte : on la ferme.
Future<void> choisir(WidgetTester t, String nom, String cible,
    {bool multiple = false}) async {
  await toucher(t, champ(nom).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  if (multiple) {
    await t.tapAt(const Offset(2, 2));
    await t.pump(const Duration(milliseconds: 300));
  }
  await t.pump(const Duration(milliseconds: 400));
}

KpiSigh kpi(WidgetTester t, String libelle) => t.widget<KpiSigh>(
    find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle));

/// Les indicateurs affichés sont ceux que la maquette a lus sur le même réglage.
void memesIndicateurs(WidgetTester t, Map<String, Object?> vecteur) {
  for (final k in (vecteur['kpis'] as List).cast<Map>()) {
    final a = kpi(t, '${k['label']}');
    expect(norm(a.valeur), norm(k['valeur']), reason: '${k['label']}');
    expect(a.indice == null ? null : norm(a.indice), k['indice'] == null ? null : norm(k['indice']),
        reason: 'indice de ${k['label']}');
  }
}

/// La note du point (la règle de l'écran, elle aussi une note, est posée au-dessus par la coque).
String note(WidgetTester t) => norm(t
    .widgetList<NoteSigh>(find.byType(NoteSigh))
    .map((n) => n.texte)
    .firstWhere((x) => x.contains('pièce(s)') || x.contains('flux de la période') || x.contains('état à date')));

Set<String> textes(WidgetTester t) => {
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if ((w.data ?? w.textSpan?.toPlainText()) != null)
          norm(w.data ?? w.textSpan!.toPlainText())
    };

void essai(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  setUp(
      () => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('m6-point-ventes', () {
    essai('le mois fini le 16/08 : indicateurs, note, journal et évolution de la maquette',
        (t) async {
      final v = cas('ventes', 'mois fini le 16/08/2026');
      await ouvrir(t, magasin(), 'm6-point-ventes');
      memesIndicateurs(t, v);
      expect(note(t), norm(v['note']));
      expect(find.text('Affichage de 1 à 20 sur 52 enregistrements'), findsOneWidget);
      // La première ligne du journal est celle que la maquette montre en tête (la pièce la plus récente).
      final premiere = ((((v['onglets'] as Map)['journal'] as Map)['tables'] as List).first as List).first as Map;
      expect(find.text('${premiere['numero']}'), findsWidgets);
      await toucher(t, find.text('Évolution'));
      expect(find.text('Ventes par jour'), findsOneWidget);
      expect(find.byType(GraphiqueBarres), findsOneWidget);
    });

    essai('la périodicité annuelle recompte tout : 230 pièces, six secteurs, évolution au mois',
        (t) async {
      final v = cas('ventes', 'année finie le 16/08/2026 (évolution au mois)');
      await ouvrir(t, magasin(), 'm6-point-ventes');
      await choisir(t, 'periode', 'Annuelle');
      memesIndicateurs(t, v);
      expect(note(t), norm(v['note']));
      await toucher(t, find.text('Par groupe et famille'));
      expect(find.text('Par groupe de prestation'), findsOneWidget);
      expect(find.text('Par catégorie de prestation'), findsOneWidget);
      expect(find.text('Poids des groupes dans le chiffre net'), findsOneWidget);
      expect(find.text('Hospitalisation et soins'), findsWidgets);
      await toucher(t, find.text('Évolution'));
      expect(find.text('Ventes par mois'), findsOneWidget);
    });

    essai('un groupe de prestation filtre la MÊME population de lignes', (t) async {
      final v = cas('ventes', 'groupe Laboratoire, année');
      await ouvrir(t, magasin(), 'm6-point-ventes');
      await choisir(t, 'periode', 'Annuelle');
      await choisir(t, 'groupes', 'Laboratoire', multiple: true);
      memesIndicateurs(t, v);
      expect(note(t), norm(v['note']));
      expect(note(t), contains('Groupe(s) : 1.'));
    });

    essai('« Réinitialiser les filtres » rend toute la population et les invites', (t) async {
      final tout = cas('ventes', 'année finie le 16/08/2026 (évolution au mois)');
      await ouvrir(t, magasin(), 'm6-point-ventes');
      await choisir(t, 'periode', 'Annuelle');
      await choisir(t, 'groupes', 'Maternité', multiple: true);
      expect(norm(kpi(t, 'Facturé brut').valeur), isNot(norm((tout['kpis'] as List).first['valeur'])));
      await toucher(t, find.text('Réinitialiser les filtres'));
      memesIndicateurs(t, tout);
      expect(find.text('Tous les groupes'), findsOneWidget);
      expect(find.text('Tous les clients'), findsOneWidget);
    });

    essai('« Par patient » : un client retenu, ses lignes secteur par secteur', (t) async {
      final v = cas('ventes', 'un client, année (onglet Par patient)');
      final bloc = ((((v['onglets'] as Map)['patients'] as Map)['blocs']) as List).first as Map;
      await ouvrir(t, magasin(), 'm6-point-ventes');
      await toucher(t, find.text('Par patient'));
      expect(find.textContaining('Choisissez un ou plusieurs clients'), findsOneWidget,
          reason: 'sans client retenu, l\'onglet explique ce qu\'il attend');
      await choisir(t, 'periode', 'Annuelle');
      await choisir(t, 'clients', '${bloc['patient']}', multiple: true);
      await toucher(t, find.text('Par patient'));
      expect(find.text('${bloc['patient']}'), findsWidgets);
      expect(textes(t), contains(norm(bloc['sous'])));
      expect(textes(t), contains(norm(bloc['net'])));
      for (final s in (bloc['secteurs'] as List).cast<Map>()) {
        expect(textes(t), contains(norm(s['resume'])), reason: 'résumé du secteur ${s['titre']}');
        for (final ligne in (s['lignes'] as List).cast<List>()) {
          expect(find.text('${ligne[1]}'), findsWidgets, reason: 'pièce ${ligne[1]}');
        }
      }
    });

    essai('le point global énonce les trois parts en toutes lettres, avec les filtres en force', (t) async {
      final v = cas('ventes', 'mois fini le 16/08/2026');
      final imp = (v['impressions'] as Map)['global'] as Map;
      await ouvrir(t, magasin(), 'm6-point-ventes');
      await toucher(t, find.text('Point global'));
      final vus = textes(t);
      expect(vus, contains('POINT GLOBAL DES VENTES'));
      for (final bloc in (imp['contenu'] as List).cast<Map>()) {
        if (bloc['texte'] != null) {
          expect(vus, contains(norm(bloc['texte'])), reason: '${bloc['texte']}');
        }
      }
      expect(vus, contains('FILTRES APPLIQUÉS À CET ÉTAT'));
      // Les filtres relevés par la maquette sur la page sont ceux de la pièce : périodicité, date d'arrêté, bornes.
      for (final f in (imp['filtres'] as List).cast<List>()) {
        expect(vus.any((x) => x.contains('${f[0]} : ${f[1]}') || x == norm('${f[0]} : ${f[1]}')), isTrue,
            reason: 'filtre ${f[0]}');
      }
      final tableau = ((imp['contenu'] as List).first as Map)['table'] as Map;
      for (final cellule in (tableau['pied'] as List).cast<String>().where((x) => x.isNotEmpty)) {
        expect(vus, contains(norm(cellule)), reason: 'pied du tableau : $cellule');
      }
    });

    essai('le point par patient : une page par patient du lot, et le vide se DIT', (t) async {
      final v = cas('ventes', 'un client, année (onglet Par patient)');
      final bloc = ((((v['onglets'] as Map)['patients'] as Map)['blocs']) as List).first as Map;
      await ouvrir(t, magasin(), 'm6-point-ventes');
      await toucher(t, find.text('Point par patient'));
      expect(textes(t), contains('POINT DES VENTES PAR PATIENT'));
      expect(textes(t).any((x) => x.startsWith('Patient : ')), isTrue,
          reason: 'sans client retenu, l\'état couvre tous les clients de la période');
      await toucher(t, find.text('Fermer').last);
      // Un client retenu qui n'a rien acheté ce jour-là : l'état le dit au lieu d'imprimer une page vide.
      await choisir(t, 'periode', 'Journalière');
      await choisir(t, 'clients', '${bloc['patient']}', multiple: true);
      await toucher(t, find.text('Point par patient'));
      expect(textes(t), contains('Aucune vente sur la période pour les clients retenus.'));
    });

    essai('une vente nouvelle entre dans le point, une pièce archivée en sort (RG-14)', (t) async {
      final m = magasin();
      final v = cas('ventes', 'mois fini le 16/08/2026');
      final avant = norm((v['kpis'] as List).first['valeur']);
      await ouvrir(t, m, 'm6-point-ventes');
      expect(norm(kpi(t, 'Facturé brut').valeur), avant);
      final r = m.collection('factures').inserer({
        'id': 'FTEST1',
        'numero': 'FN-2026-09999',
        'patientId': 'PTEST',
        'patient': 'TEST Client',
        'patientCode': 'CNT/9999/26',
        'date': '2026-08-15',
        'type': 'Consultation',
        'statut': 'actif',
        'lignes': [
          {
            'id': 'L1',
            'categorie': 'consultation',
            'designation': 'Consultation de test',
            'quantite': 2,
            'prixUnitaire': 5000,
            'montantBrut': 10000,
            'remise': 0,
            'montant': 10000,
            'partAssureur': 0,
            'partPersonnel': 0,
            'partPatient': 10000,
            'statutPaiement': 'du',
          }
        ]
      });
      await t.pump(const Duration(milliseconds: 300));
      // 690 448 + 10 000
      expect(norm(kpi(t, 'Facturé brut').valeur).replaceAll(RegExp(r'\D'), ''), '700448');
      expect(norm(kpi(t, 'Articles vendus').valeur).replaceAll(RegExp(r'\D'), ''), '152');
      expect(find.text('Affichage de 1 à 20 sur 53 enregistrements'), findsOneWidget);
      r.annuler();
      await t.pump(const Duration(milliseconds: 300));
      expect(norm(kpi(t, 'Facturé brut').valeur), avant);
      expect(m.collection('factures').parId('FTEST1')!['statut'], 'archive',
          reason: 'annuler archive, ne supprime pas');
    });
  });

  group('m6-point-stock', () {
    essai('l\'état à date : stock restant à la pharmacie, quantité ET montant', (t) async {
      final v = cas('stock', 'vue pharmacie_restant, mois fini le 16/08/2026');
      await ouvrir(t, magasin(), 'm6-point-stock');
      memesIndicateurs(t, v);
      expect(note(t), norm(v['note']));
      // L'en-tête de colonne est composé en capitales par le kit : on compare sans la casse.
      expect(textes(t).map((x) => x.toLowerCase()), contains('quantité en stock'));
      expect(find.text('Cumul par famille d’articles'), findsOneWidget);
      expect(find.text('Répartition de la valeur par famille'), findsOneWidget);
    });

    essai('un flux se lit sur une période : le stock sorti du magasin, au mois puis à l\'année', (t) async {
      await ouvrir(t, magasin(), 'm6-point-stock');
      await choisir(t, 'vue', 'Stock sorti par le magasin');
      var v = cas('stock', 'vue magasin_sorti, mois fini le 16/08/2026');
      memesIndicateurs(t, v);
      expect(note(t), norm(v['note']));
      expect(textes(t).map((x) => x.toLowerCase()), contains('quantité mouvementée'));
      expect(textes(t).map((x) => x.toLowerCase()), isNot(contains('quantité en stock')));
      await choisir(t, 'periode', 'Annuelle');
      v = cas('stock', 'vue magasin_sorti, année finie le 16/08/2026');
      memesIndicateurs(t, v);
    });

    essai('un état ignore la périodicité : la changer ne bouge rien', (t) async {
      await ouvrir(t, magasin(), 'm6-point-stock');
      final avant = norm(kpi(t, 'Montant').valeur);
      expect(find.byWidgetPredicate((w) => w is IgnorePointer && w.child is Opacity), findsOneWidget,
          reason: 'la périodicité est inactive sur un état');
      await t.tap(champ('periode').first, warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Annuelle'), findsNothing, reason: 'la liste ne s\'ouvre pas');
      expect(norm(kpi(t, 'Montant').valeur), avant);
    });

    essai('une famille filtre la vue et le cumul par famille disparaît à une seule famille', (t) async {
      await ouvrir(t, magasin(), 'm6-point-stock');
      await choisir(t, 'familles', 'Médicaments', multiple: true);
      final v = cas('stock', 'état pharmacie, familles Médicaments');
      memesIndicateurs(t, v);
      expect(find.text('Cumul par famille d’articles'), findsNothing);
    });

    essai('le point imprimé nomme la nature, la méthode de valorisation et refait ses totaux', (t) async {
      final v = cas('stock', 'vue pharmacie_restant, mois fini le 16/08/2026');
      await ouvrir(t, magasin(), 'm6-point-stock');
      await toucher(t, find.text('Imprimer le point'));
      final vus = textes(t);
      expect(vus, contains('STOCK RESTANT À LA PHARMACIE'));
      for (final p in ((v['impression'] as Map)['cartouche'] as List).cast<List>()) {
        expect(vus.any((x) => x.contains(norm(p[1]))), isTrue, reason: '${p[0]} : ${p[1]}');
      }
      final pied = ((((v['impression'] as Map)['contenu'] as List).first as Map)['table'] as Map)['pied'] as List;
      for (final c in pied.cast<String>().where((x) => x.isNotEmpty)) {
        expect(vus, contains(norm(c)), reason: 'pied : $c');
      }
      expect(vus, contains('FILTRES APPLIQUÉS À CET ÉTAT'));
      for (final f in ((v['impression'] as Map)['filtres'] as List).cast<List>()) {
        expect(vus, contains(norm('${f[0]} : ${f[1]}')), reason: 'filtre ${f[0]}');
      }
    });

    essai('un mouvement entré au magasin gonfle le stock nouveau, et seulement lui', (t) async {
      final m = magasin();
      final p = m.collection('produits').actives.firstWhere((x) => x['stockGros'] != null && x['seuilAlerte'] != null);
      await ouvrir(t, m, 'm6-point-stock');
      await choisir(t, 'vue', 'Stock nouveau enregistré au magasin');
      final avant = kpi(t, 'Quantité').valeur;
      m.collection('mouvements').inserer({
        'id': 'MTEST',
        'reference': 'M999999',
        'date': '2026-08-16',
        'produitId': p['id'],
        'produit': p['designation'],
        'type': 'entree',
        'quantite': 7,
        'stockType': 'gros',
        'justificatif': 'BL-TEST',
        'statut': 'actif',
      });
      await t.pump(const Duration(milliseconds: 300));
      final apres = kpi(t, 'Quantité').valeur;
      num lire(String s) => num.parse(s.replaceAll(RegExp(r'\D'), ''));
      expect(lire(apres) - lire(avant), 7);
      // un transfert n'est pas une entrée nouvelle : le même mouvement côté détail n'y compte pas
      m.collection('mouvements').inserer({
        'id': 'MTEST2',
        'reference': 'M999998',
        'date': '2026-08-16',
        'produitId': p['id'],
        'produit': p['designation'],
        'type': 'entree',
        'quantite': 50,
        'stockType': 'detail',
        'statut': 'actif',
      });
      await t.pump(const Duration(milliseconds: 300));
      expect(lire(kpi(t, 'Quantité').valeur) - lire(avant), 7);
    });
  });
}
