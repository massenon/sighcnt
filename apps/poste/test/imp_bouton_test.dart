import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LE BOUTON « Importer les données » et le DROIT D'IMPORT distinct, au poste (lot IMP-C). Le droit se lit de la section `import` de `rbac.json` (superposée à chaud par
/// les fiches RBAC), jamais du droit d'éditer l'écran ni d'un nom de rôle ; le bouton est ABSENT sans lui. Les fichiers sont ceux que la maquette a écrits.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();
Uint8List fixture(String nom) => File('test/fixtures/import/$nom.xlsx').readAsBytesSync();

Magasin magasin({List<Map<String, Object?>> rbac = const []}) => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
      if (rbac.isNotEmpty) 'rbac': rbac,
    });

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

final bouton = find.byKey(const Key('imp-bouton-importer'));

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

Map<String, Object?> fiche(String role, Map<String, Object?> droitsImport) => {'id': 'RBAC-$role', 'role': role, 'statut': 'actif', 'droitsImport': droitsImport};

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  // Les écrans hôtes des jeux que le poste porte, lus de la DÉCLARATION (jamais recopiés ici).
  final hotes = {
    for (final d in donnees.matrice.matriceImport.declarations)
      if (jeuImportParId(d.id) != null)
        for (final h in d.hotes) h
  };

  test('les hôtes viennent de la déclaration du manifeste : un écran par jeu porté au moins, aucun nom de rôle', () {
    expect(hotes, containsAll(['m6-stock-gros', 'm10-personnel', 'm1-patients', 'm7-fournisseurs', 'm9-compagnies', 'm12-plan-comptable', 'm12-ouverture']));
  });

  cas('LE BOUTON SUIT LE DROIT D\'IMPORT, calculé de la matrice : présent chez qui importe un jeu de l\'écran, ABSENT chez les autres (jamais grisé)', (t) async {
    var presents = 0, absents = 0;
    for (final role in ['admin', 'da', 'stock', 'comptable', 'aide_comptable', 'direction', 'reception', 'caissier', 'medecin']) {
      for (final hote in ['m6-stock-gros', 'm1-patients', 'm12-ouverture', 'm7-fournisseurs']) {
        await ouvrir(t, magasin(), hote, role: role);
        final attendu = donnees.matrice.matriceImport.deLHote(hote, role).any((d) => jeuImportParId(d.id) != null);
        expect(bouton, attendu ? findsOneWidget : findsNothing, reason: '$role sur $hote');
        attendu ? presents++ : absents++;
      }
    }
    expect(presents, greaterThan(6));
    expect(absents, greaterThan(6));
  });

  cas('LES CINQ RÉFÉRENTIELS PORTÉS PAR LE LOT : un bouton à chaque hôte déclaré (natures, centres de coûts, unités, prestataires, emplacements), pour qui détient le jeu seulement', (t) async {
    final hotes5 = {
      'natures-facture': 'cfg-natures-facture',
      'centres-couts': 'cfg-centres-couts',
      'unites-labo': 'm5-unites',
      'prestataires': 'm10-prestataires',
      'emplacements': 'm6-etiquetage',
    };
    for (final e in hotes5.entries) {
      expect(donnees.matrice.matriceImport.declaration(e.key)!.hotes, contains(e.value), reason: 'l\'hôte vient de la déclaration : ${e.key}');
      await ouvrir(t, magasin(), e.value, role: 'admin');
      expect(bouton, findsOneWidget, reason: 'admin sur ${e.value}');
      await ouvrir(t, magasin(), e.value, role: 'caissier');
      expect(bouton, findsNothing, reason: 'le caissier ne détient aucun de ces jeux : ${e.value}');
    }
    // L'emplacement s'importe en mode « ignorer » (liste fermée de la Direction) : la fenêtre le dit, une ligne déjà tenue est comptée, jamais refusée.
    final m = magasin();
    await ouvrir(t, m, 'm6-etiquetage', role: 'admin');
    await toucher(t, bouton);
    expect(find.textContaining('Fiches déjà tenues : ignorées.'), findsOneWidget);
    SelecteursImport.choisir = () async => FichierChoisi('em-doublon-casse.xlsx', fixture('em-doublon-casse'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('1 ignorée(s) (fiche déjà tenue)'), findsOneWidget);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (1 ligne)'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
    expect(m.collection('emplacements').toutes.length, 2, reason: 'le casier A2 tenu n\'est pas réécrit ; A-2 est un casier distinct, écrit');
    expect(m.collection('lotsImportation').toutes.single['nbIgnores'], 1);
  });

  cas('LE DROIT N\'EST PAS CELUI D\'ÉDITER L\'ÉCRAN : le gestionnaire qui ÉDITE le Grand Stock n\'importe pas le répertoire des patients, et la Direction qui ne l\'édite pas peut importer si la matrice le lui donne', (t) async {
    expect(donnees.matrice.peutEditer('stock', 'm6-stock-gros'), isTrue);
    await ouvrir(t, magasin(), 'm6-stock-gros', role: 'stock');
    expect(bouton, findsOneWidget);
    // Il lit le répertoire des patients sans l'importer : l'écran s'ouvre, le bouton n'y est pas.
    await ouvrir(t, magasin(), 'm1-patients', role: 'stock');
    expect(bouton, findsNothing);
    // Une fiche RBAC ouvre le jeu à la Direction (voir, importer) : le bouton paraît, alors qu'elle n'édite pas l'écran (à chaud, sans recharger la matrice engendrée).
    expect(donnees.matrice.peutEditer('direction', 'm6-stock-gros'), isFalse);
    await ouvrir(t, magasin(rbac: [fiche('direction', {'grand-stock': {'voir': true, 'importer': true}})]), 'm6-stock-gros', role: 'direction');
    expect(bouton, findsOneWidget, reason: 'le droit d\'import est celui de la fiche, pas celui d\'éditer');
    // Et la fiche le ferme au gestionnaire (une surcharge restreint autant qu'elle accorde), alors qu'il édite toujours l'écran.
    await ouvrir(t, magasin(rbac: [fiche('stock', {'grand-stock': {'importer': false}})]), 'm6-stock-gros', role: 'stock');
    expect(bouton, findsNothing);
  });

  cas('LA PAGE DU JEU suit le même droit : « Téléverser » vient du droit d\'importer CE JEU, pas du droit d\'éditer l\'écran', (t) async {
    final televerser = find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)');
    // La Direction ne peut qu\'ouvrir et lire : une fiche lui donne le jeu, le téléversement paraît (à chaud).
    await ouvrir(t, magasin(), 'm6-import-grand-stock', role: 'direction');
    expect(televerser, findsNothing);
    expect(find.textContaining('Votre profil voit ce jeu sans pouvoir y importer'), findsOneWidget);
    await ouvrir(t, magasin(rbac: [fiche('direction', {'grand-stock': {'voir': true, 'importer': true}})]), 'm6-import-grand-stock', role: 'direction');
    expect(televerser, findsOneWidget);
    // Et la fiche le retire au gestionnaire, qui garde la lecture, le modèle et l\'historique.
    await ouvrir(t, magasin(rbac: [fiche('stock', {'grand-stock': {'importer': false}})]), 'm6-import-grand-stock', role: 'stock');
    expect(televerser, findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Télécharger le modèle (.xlsx)'), findsOneWidget);
  });

  cas('L\'HISTORIQUE se lit de son auteur et de la supervision ; l\'annulation est une commande du JEU et de l\'auteur du lot, jamais offerte à tout lecteur', (t) async {
    Map<String, Object?> lot(String id, String par) => {
          'id': id, 'statut': 'actif', 'reference': 'IMP-2026-00${id.substring(3)}', 'jeu': 'grand-stock', 'jeuLibelle': 'Importation Grand Stock', 'fichier': 'f.xlsx', 'date': '2026-11-01',
          'par': par, 'validePar': par, 'etat': 'applique', 'nbLignes': 1, 'nbAvertissements': 0, 'ecrits': <Object?>[]
        };
    Magasin avecLots() {
      final m = magasin();
      m.collection('lotsImportation').inserer(lot('LIM1', 'AUTRE AGENT'));
      return m;
    }

    final annuler = find.byWidgetPredicate((w) => w is BoutonIcone && w.libelle == 'Annuler le lot');
    // Le gestionnaire détient le droit d\'annuler le Grand Stock, mais le lot est d\'un autre agent et il ne supervise pas : il ne le lit pas, il ne peut pas l\'annuler.
    expect(donnees.matrice.droitImport('stock', 'grand-stock').annuler, isTrue);
    expect(donnees.matrice.matriceImport.supervise('stock'), isFalse);
    await ouvrir(t, avecLots(), 'm6-import-grand-stock', role: 'stock');
    expect(find.text('IMP-2026-001'), findsNothing);
    expect(annuler, findsNothing);
    // La DAF supervise (droit d\'annuler sur chaque jeu, tiré de la matrice) : elle lit tous les lots et peut défaire celui d\'un autre.
    expect(donnees.matrice.matriceImport.supervise('da'), isTrue);
    await ouvrir(t, avecLots(), 'm6-import-grand-stock', role: 'da');
    expect(find.text('IMP-2026-001'), findsOneWidget);
    expect(annuler, findsOneWidget);
    // Un AUTEUR qui ne détient plus le droit d\'annuler le jeu lit son lot et ne peut pas le défaire : l\'annulation est une commande du JEU (fiche : voir et importer sans annuler).
    final lui = donnees.matrice.libelle('stock')!;
    final m = magasin(rbac: [fiche('stock', {'grand-stock': {'annuler': false}})]);
    m.collection('lotsImportation').inserer(lot('LIM2', lui));
    await ouvrir(t, m, 'm6-import-grand-stock', role: 'stock');
    expect(find.text('IMP-2026-002'), findsOneWidget, reason: 'son lot, qu\'il lit');
    expect(annuler, findsNothing, reason: 'sans le droit d\'annuler CE jeu');
    final m2 = magasin();
    m2.collection('lotsImportation').inserer(lot('LIM3', lui));
    await ouvrir(t, m2, 'm6-import-grand-stock', role: 'stock');
    expect(annuler, findsOneWidget, reason: 'avec le droit, l\'auteur défait son lot');
  });

  cas('la fenêtre : un jeu, trois temps ; le fichier est vérifié sans rien écrire, puis importé, au nom de l\'agent, en un seul geste', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm1-patients', role: 'admin');
    await toucher(t, bouton);
    expect(find.text('Importer les données'), findsWidgets);
    expect(find.text('1. Télécharger le modèle'), findsOneWidget);
    expect(find.text('2. Téléverser et analyser'), findsOneWidget);
    expect(find.text('Historique des lots de ce jeu'), findsNothing, reason: 'la fenêtre n\'a ni historique ni indicateurs : ils sont à la page du jeu');
    expect(find.textContaining('Jeu restreint (RG-13)'), findsOneWidget);
    SelecteursImport.choisir = () async => FichierChoisi('pa-valide.xlsx', fixture('pa-valide'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Analyse conforme. 3 ligne(s)'), findsOneWidget);
    expect(m.collection('patients').toutes.length, 4, reason: 'la vérification n\'écrit rien (le magasin contrôlé tient quatre dossiers)');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
    expect(m.collection('patients').toutes.length, 7);
    expect(m.collection('lotsImportation').toutes.single['etat'], 'applique');
    expect(m.collection('lotsImportation').toutes.single['validePar'], isNotEmpty);
  });

  cas('JEU RESTREINT : le refus d\'un fichier de patients n\'écrit aucune valeur de cellule à l\'historique (le lot consigné porte la ligne, la colonne, le code et le geste)', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm1-patients', role: 'admin');
    await toucher(t, bouton);
    SelecteursImport.choisir = () async => FichierChoisi('pa-code-existant.xlsx', fixture('pa-code-existant'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Fichier refusé. Rien n’a été écrit.'), findsOneWidget);
    final lot = m.collection('lotsImportation').toutes.single;
    expect(lot['etat'], 'refuse');
    final texte = jsonEncode(lot['erreurs']);
    expect(texte, isNot(contains('CNT/1/25')), reason: 'le code patient déjà tenu n\'est pas recopié');
    expect(texte, isNot(contains('TCHANE')), reason: 'ni le nom du patient');
    expect(texte, contains('DOUBLON_MAGASIN'), reason: 'le code stable reste');
  });
}
