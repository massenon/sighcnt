import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/classeur_xlsx.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Le module d'importation côté poste : l'ÉCRAN. Le moteur est rejoué sur les vecteurs de la maquette (`packages/domaine/test/import_test.dart`) ; ici, ce
/// que l'agent voit et fait : télécharger le modèle .xlsx, téléverser (sélecteur natif REMPLACÉ : aucun test ne dépend d'une boîte de dialogue), aperçu,
/// refus nommés, atomicité, annulation du lot, droits. Les fichiers sont ceux que la maquette a écrits.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();
Uint8List fixture(String nom) => File('test/fixtures/import/$nom.xlsx').readAsBytesSync();

Magasin magasin() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

final sauvegardes = <(String, Uint8List)>[];

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => DateTime(2026, 11, 1)));
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

Future<void> choisirFichier(WidgetTester t, String nomFixture, {String? nom}) async {
  SelecteursImport.choisir = () async => FichierChoisi(nom ?? '$nomFixture.xlsx', fixture(nomFixture));
  await toucher(t, find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'));
  await t.pump(const Duration(milliseconds: 300));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  setUp(() {
    sauvegardes.clear();
    SelecteursImport.enregistrer = (nom, octets) async {
      sauvegardes.add((nom, octets));
      return '/faux/$nom';
    };
  });
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  cas('Importation Grand Stock : le libellé exact, quatre indicateurs, trois cartes et l\'historique du jeu', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm6-import-grand-stock');
    expect(find.text('Importation Grand Stock'), findsWidgets);
    for (final k in ['Lots appliqués', 'Fiches importées', 'Fichiers refusés', 'Statut du jeu']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(find.text('Supporté'), findsOneWidget);
    for (final carte in ['1. Télécharger le modèle', '2. Téléverser et analyser', 'Historique des lots de ce jeu']) {
      expect(find.text(carte), findsOneWidget, reason: carte);
    }
    expect(find.text('Code article'), findsOneWidget, reason: 'le tableau des colonnes du modèle');
    expect(find.widgetWithText(BoutonSigh, 'Télécharger le modèle (.xlsx)'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Modèle CSV'), findsOneWidget);
  });

  cas('« Télécharger le modèle » produit un vrai .xlsx de trois feuilles, aux en-têtes exacts du jeu, et le CSV', (t) async {
    await ouvrir(t, magasin(), 'm6-import-grand-stock');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Télécharger le modèle (.xlsx)'));
    expect(sauvegardes.single.$1, 'modele-import-grand-stock.xlsx');
    expect(sauvegardes.single.$2.sublist(0, 2), [0x50, 0x4b]);
    final f = lireClasseur(sauvegardes.single.$2);
    expect(f.map((x) => x.nom), ['Données', 'Instructions', 'Listes']);
    expect(f[0].lignes.first, jeuGrandStock.colonnes.map((c) => c.label));
    expect(f[0].lignes[1].first, 'PARA500', reason: 'la ligne d\'exemple');
    expect(f[2].lignes.first.first, 'Catégorie');
    expect(find.text('Fichier enregistré.'), findsOneWidget);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Modèle CSV'));
    expect(sauvegardes.last.$1, 'modele-import-grand-stock.csv');
    expect(sauvegardes.last.$2.sublist(0, 3), [0xEF, 0xBB, 0xBF], reason: 'BOM UTF-8 : Excel lit les accents');
    expect(utf8.decode(sauvegardes.last.$2), startsWith('"Code article";'));
  });

  cas('un fichier fautif est REFUSÉ en entier : refus nommés, lot consigné « refusé », rien d\'écrit, rapport .xlsx', (t) async {
    final m = magasin();
    final avant = {for (final n in ['produits', 'lots', 'mouvements']) n: m.collection(n).toutes.length};
    await ouvrir(t, m, 'm6-import-grand-stock');
    await choisirFichier(t, 'gs-quantite-negative');
    expect(find.textContaining('Fichier refusé. Rien n’a été écrit.'), findsOneWidget);
    // Le refus est NOMMÉ : colonne, motif et geste, jamais muet.
    expect(find.byKey(const Key('imp-constat-RG03_STOCK_NEGATIF')), findsOneWidget);
    expect(find.textContaining('le stock ne peut jamais être négatif (RG-03)'), findsOneWidget);
    expect(find.textContaining('Saisissez la quantité réellement comptée'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (1 ligne)'), findsNothing, reason: 'aucune confirmation sur un fichier refusé');
    expect({for (final n in ['produits', 'lots', 'mouvements']) n: m.collection(n).toutes.length}, avant);
    final lot = m.collection(collectionLots).actives.single;
    expect(lot['etat'], 'refuse');
    expect(lot['reference'], 'IMP-2026-001');
    expect(lot['nbRefus'], 1);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Rapport d’erreurs (.xlsx)'));
    expect(sauvegardes.single.$1, 'rapport-IMP-2026-001.xlsx');
    final rapport = lireClasseur(sauvegardes.single.$2);
    expect(rapport.first.nom, 'Erreurs');
    expect(rapport.first.lignes[1][4], 'RG03_STOCK_NEGATIF');
  });

  cas('une colonne obligatoire manquante et un fichier illisible sont nommés', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm6-import-grand-stock');
    await choisirFichier(t, 'gs-colonne-manquante');
    expect(find.textContaining('colonne obligatoire « Quantité » absente'), findsOneWidget);
    expect(find.textContaining('téléchargez le modèle de nouveau'), findsOneWidget);
    SelecteursImport.choisir = () async => FichierChoisi('faux.xlsx', Uint8List.fromList(utf8.encode('pas un classeur')));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'));
    expect(find.textContaining('fichier illisible'), findsOneWidget);
    expect(m.collection(collectionLots).actives.length, 2, reason: 'les deux fichiers refusés sont consignés');
    expect(m.collection('produits').toutes.length, 2);
  });

  cas('un fichier conforme : aperçu, confirmation, lot écrit d\'un seul geste et signé, historique, annulation par archivage (RG-14)', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm6-import-grand-stock');
    await choisirFichier(t, 'gs-valide');
    expect(find.textContaining('Analyse conforme. 3 ligne(s) peuvent être écrites, dont 1 avec avertissement. Rien n’est encore écrit.'), findsOneWidget);
    expect(find.byKey(const Key('imp-constat-A_VALORISER')), findsOneWidget);
    expect(m.collection('produits').toutes.length, 2, reason: 'rien n\'est écrit avant la confirmation');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
    expect(find.text('Écrire ce lot ?'), findsOneWidget);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
    final lot = m.collection(collectionLots).actives.single;
    expect(lot['etat'], 'applique');
    expect(lot['reference'], 'IMP-2026-001');
    expect((lot['ecrits'] as List).length, 7);
    final med = m.collection('produits').actives.firstWhere((p) => p['code'] == 'MED1');
    expect(med['stock'], 150);
    expect(med['stockGros'], 150);
    expect(med['lotImport'], 'IMP-2026-001');
    expect(med['validePar'], isNotEmpty);
    expect('${med['source']}', 'Import Importation Grand Stock (gs-valide.xlsx)');
    expect(m.collection('lots').actives.map((l) => l['numeroLot']), containsAll(['L1', 'L2']));
    expect(m.collection('mouvements').actives.where((x) => x['lotImport'] == 'IMP-2026-001').length, 3);
    expect(m.collection('audit').toutes.where((a) => a['action'] == 'Import').length, 1, reason: 'RG-12 : le lot est journalisé');
    expect(find.textContaining('Lot IMP-2026-001 appliqué. 7 fiche(s) écrite(s)'), findsWidgets);
    expect(find.text('Appliqué'), findsWidgets);
    // Rejouer le même fichier : refusé, les articles existent maintenant.
    await choisirFichier(t, 'gs-valide');
    expect(find.textContaining('existe déjà dans le référentiel'), findsWidgets);
    expect(m.collection('produits').actives.where((p) => p['code'] == 'MED1').length, 1);
    // Annulation du lot : les fiches sont ARCHIVÉES, jamais supprimées.
    final annuler = find.byWidgetPredicate((w) => w is BoutonIcone && w.libelle == 'Annuler le lot');
    expect(annuler, findsOneWidget);
    await toucher(t, annuler);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler le lot'));
    expect(m.collection(collectionLots).parId(lot['id'])!['etat'], 'annule');
    expect(m.collection('produits').toutes.where((p) => p['lotImport'] == 'IMP-2026-001').every((p) => p['statut'] == 'archive'), isTrue);
    expect(m.collection('produits').toutes.where((p) => p['lotImport'] == 'IMP-2026-001').length, 2, reason: 'RG-14 : rien n\'est supprimé');
    expect(find.text('Lot annulé.'), findsOneWidget);
  });

  cas('annuler un lot sous un mouvement de stock postérieur est refusé en le nommant (RG-03)', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm6-import-grand-stock');
    await choisirFichier(t, 'gs-valide');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
    final p = m.collection('produits').actives.firstWhere((x) => x['code'] == 'MED1');
    m.collection('mouvements').inserer({'reference': 'M000050', 'produitId': p['id'], 'produit': p['designation'], 'type': 'sortie', 'typeLabel': 'Sortie', 'quantite': 3}, prefixe: 'MVT');
    await toucher(t, find.byWidgetPredicate((w) => w is BoutonIcone && w.libelle == 'Annuler le lot'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler le lot'));
    expect(find.text('Annulation refusée.'), findsOneWidget);
    expect(m.collection('produits').actives.where((x) => x['lotImport'] == 'IMP-2026-001').length, 2, reason: 'rien n\'est archivé');
    expect(m.collection(collectionLots).actives.single['etat'], 'applique');
  });

  cas('atomicité : une écriture refusée en cours de lot (exercice clos) ne laisse rien, le fichier est consigné', (t) async {
    final m = magasin();
    final avant = m.collection('ecritures').toutes.length;
    m.collection('ecritures').garder((op, f) => op == 'inserer' && m.collection('ecritures').toutes.length >= avant + 2 ? 'exercice clos (garde d\'essai)' : null);
    await ouvrir(t, m, 'imp-soldes-ouverture');
    await choisirFichier(t, 'so-valide');
    expect(find.textContaining('Analyse conforme. 4 ligne(s)'), findsOneWidget);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (4 lignes)'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
    expect(m.collection('ecritures').toutes.length, avant, reason: 'les deux premières lignes posées sont retirées');
    expect(find.textContaining('Importation refusée.'), findsWidgets);
    final lot = m.collection(collectionLots).actives.single;
    expect(lot['etat'], 'refuse');
    expect((lot['ecrits'] as List), isEmpty);
  });

  cas('RG-10 : une écriture non équilibrée est refusée avec les deux totaux ; RG-01 : un code patient existant aussi', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'imp-soldes-ouverture');
    await choisirFichier(t, 'so-desequilibre');
    expect(find.byKey(const Key('imp-constat-RG10_DESEQUILIBRE')), findsNothing, reason: 'le constat du fichier entier est un tableau, pas une ligne');
    expect(find.textContaining('écriture non équilibrée (RG-10)'), findsOneWidget);
    expect(find.textContaining('écart 50'), findsOneWidget);
    await ouvrir(t, m, 'imp-patients');
    await choisirFichier(t, 'pa-code-existant');
    expect(find.textContaining('RG-01 : le code CNT/1/25 est déjà attribué'), findsOneWidget);
    expect(m.collection('patients').toutes.length, 2);
  });

  cas('les droits : la Direction lit et télécharge le modèle, mais « Téléverser » est ABSENT (jamais grisé)', (t) async {
    await ouvrir(t, magasin(), 'm6-import-grand-stock', role: 'direction');
    expect(find.widgetWithText(BoutonSigh, 'Télécharger le modèle (.xlsx)'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'), findsNothing);
  });

  cas('l\'accueil du module : dix jeux marqués supporté ou proposition à valider, source et dernier lot, historique général', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'imp-accueil');
    expect(find.text('Jeux d’import'), findsWidgets);
    expect(find.widgetWithText(BoutonSigh, 'Ouvrir'), findsNWidgets(10));
    expect(find.text('Proposition à valider'), findsOneWidget);
    expect(find.text('Supporté'), findsNWidgets(9));
    expect(find.textContaining('Source : Inventaire SAGE 100'), findsOneWidget);
    expect(find.textContaining('Écrit dans : produits, lots, mouvements. Aucun lot à ce jour.'), findsOneWidget);
    await toucher(t, find.text('Historique des lots'));
    expect(find.text('Aucun lot.'), findsOneWidget);
  });
}
