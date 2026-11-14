import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/demandes_import_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LOT 8, GROUPE STOCK AU POSTE : le stock détail initial, le bon de transfert et le comptage d'inventaire sont portés. Les fichiers sont ceux que la maquette a écrits
/// (`test/fixtures/import`), le magasin est celui des vecteurs. Voie d'un fileul rattaché : le stock détail initial et le bon de transfert (restreints, ils écrivent `produits`) sont
/// RÉSERVÉS à la mère (le moteur refuse, nommé, et la commande est absente) ; le comptage n'écrit que `inventaires` : écriture directe.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();
Uint8List fixture(String nom) => File('test/fixtures/import/$nom.xlsx').readAsBytesSync();

Magasin magasin() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

List<List<Object?>> lignesDuCas(String id) {
  final c = (vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == id);
  return [
    for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
  ];
}

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'stock'}) async {
  t.view.physicalSize = const Size(1600, 1800);
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

Future<void> rattacher(WidgetTester t, Magasin m) async {
  await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
  expect(ServiceInstallation.de(m).rattache, isTrue);
}

Future<void> televerser(WidgetTester t, String nom) async {
  SelecteursImport.choisir = () async => FichierChoisi('$nom.xlsx', fixture(nom));
  await toucher(t, find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'));
  await t.pump(const Duration(milliseconds: 300));
}

num stock(Magasin m, String code, String champ) => m.collection('produits').toutes.firstWhere((p) => p['code'] == code)[champ] as num;

ProfilImport profil({Set<String> reserves = const {}}) =>
    ProfilImport(role: 'stock', libelleRole: 'Gestionnaire de stock', matrice: donnees.matrice.matriceImport, reservesALaMere: reserves);

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  group('la voie et le refus du moteur', () {
    test('QUAND : sur un fileul rattaché, le stock détail initial et le bon de transfert sont réservés à la mère, le comptage s\'écrit en direct ; ailleurs tout est direct', () {
      VoieImportFileul voie(String j, {bool fileul = true}) => DemandesImportPoste.voie(fileulRattache: fileul, declaration: donnees.matrice.matriceImport.declaration(j));
      expect(voie('stock-detail-initial'), VoieImportFileul.reserveeALaMere);
      expect(voie('transfert-lignes'), VoieImportFileul.reserveeALaMere);
      expect(voie('inventaire-comptage'), VoieImportFileul.directe);
      for (final j in ['stock-detail-initial', 'transfert-lignes', 'inventaire-comptage']) {
        expect(voie(j, fileul: false), VoieImportFileul.directe, reason: '$j : la mère, ou un poste autonome, écrit en direct');
      }
      final reserves = DemandesImportPoste.reservesALaMere(fileulRattache: true, matrice: donnees.matrice.matriceImport);
      expect(reserves, containsAll(['personnel', 'stock-detail-initial', 'transfert-lignes']));
      expect(reserves, isNot(contains('inventaire-comptage')));
      expect(DemandesImportPoste.reservesALaMere(fileulRattache: false, matrice: donnees.matrice.matriceImport), isEmpty);
    });

    test('LE MOTEUR REFUSE sur un fileul rattaché (code nommé), rien n\'est écrit, aucun stock ne bouge ; la mère écrit', () {
      for (final cas in [('stock-detail-initial', 'sd-valide', 'DOLIP', 'stockDetail'), ('transfert-lignes', 'tl-valide', 'COTON', 'stockGros')]) {
        final m = magasin();
        final avant = stock(m, cas.$3, cas.$4);
        final fileul = PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 1), nomAgent: 'LE GESTIONNAIRE', profil: profil(reserves: {'stock-detail-initial', 'transfert-lignes'}));
        final jeu = jeuImportParId(cas.$1)!;
        final a = analyserLignes(jeu, lignesDuCas(cas.$2), '${cas.$2}.xlsx', fileul);
        expect(a.accepte, isTrue, reason: 'le fichier peut être vérifié sur un fileul : ${[for (final p in a.problemes) p.code]}');
        final r = appliquer(jeu, a, fileul);
        expect(r.ok, isFalse, reason: cas.$1);
        expect(r.code, 'JEU_RESERVE_A_LA_MERE');
        expect(r.motif, contains('réservé au poste de la mère'));
        expect(r.geste, isNotEmpty);
        expect(stock(m, cas.$3, cas.$4), avant, reason: 'aucun stock ne bouge');
        expect(m.collection(collectionLots).toutes, isEmpty, reason: 'aucun lot d\'import n\'est consigné');
        // La mère (ou un poste autonome) écrit.
        final mere = PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 1), nomAgent: 'LE GESTIONNAIRE', profil: profil());
        final ok = appliquer(jeu, analyserLignes(jeu, lignesDuCas(cas.$2), '${cas.$2}.xlsx', mere), mere);
        expect(ok.ok, isTrue, reason: '${ok.motif}');
        expect(stock(m, cas.$3, cas.$4), isNot(avant), reason: 'la mère écrit : le stock a bougé');
      }
    });
  });

  group('au poste de la mère (ou autonome) : le geste de l\'écran', () {
    testWidgets('STOCK DÉTAIL INITIAL : fichier vérifié, confirmé, lot appliqué, détail posé et total augmenté ; le même fichier rejoué est refusé (déjà mouvementé)', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-stock-detail-initial');
      await televerser(t, 'sd-valide');
      expect(find.textContaining('Analyse conforme.'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(stock(m, 'DOLIP', 'stockDetail'), 40);
      expect(stock(m, 'DOLIP', 'stock'), 80);
      expect(stock(m, 'DOLIP', 'stockGros'), 40);
      expect(m.collection('lots').toutes.where((l) => l['magasin'] == 'detail').length, 2);
      expect(m.collection('mouvements').toutes.where((x) => x['stockType'] == 'detail' && x['type'] == 'entree').length, 2);
      // Rejoué : l'article porte maintenant du stock détail et un mouvement.
      await televerser(t, 'sd-valide');
      expect(find.byKey(const Key('imp-constat-DETAIL_DEJA_MOUVEMENTE')), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('BON DE TRANSFERT : un bon neuf numéroté, deux mouvements par ligne, gros débité et détail crédité ; RG-03 refuse un bon qui dépasse le stock', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-transfert-lignes');
      await televerser(t, 'tl-stock-insuffisant');
      expect(find.byKey(const Key('imp-constat-RG03_STOCK_INSUFFISANT')), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (1 ligne)'), findsNothing);
      await televerser(t, 'tl-valide');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(stock(m, 'AMOXI', 'stockGros'), 15);
      expect(stock(m, 'AMOXI', 'stockDetail'), 15);
      expect(stock(m, 'COTON', 'stockGros'), 8);
      final bon = m.collection('transferts').toutes.single;
      expect(bon['reference'], 'TR-00001');
      expect(bon['nbLignes'], 3);
      expect(m.collection('mouvements').toutes.where((x) => x['type'] == 'transfert').length, 6, reason: 'deux mouvements symétriques par ligne');
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('sur un fileul rattaché', () {
    testWidgets('STOCK DÉTAIL INITIAL : la page dit « réglé sur la mère », la commande d\'écriture est ABSENTE et rien ne s\'écrit', (t) async {
      final m = magasin();
      await rattacher(t, m);
      await ouvrir(t, m, 'imp-stock-detail-initial');
      await televerser(t, 'sd-valide');
      expect(find.textContaining('Réglé sur la mère et jeu restreint.'), findsOneWidget);
      expect(find.textContaining('Analyse conforme.'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'), findsNothing);
      expect(find.byKey(const Key('imp-importer-et-demander')), findsNothing);
      expect(stock(m, 'DOLIP', 'stockDetail'), 0);
      expect(m.collection(demandesImportCollection).toutes, isEmpty);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('COMPTAGE D\'INVENTAIRE : écriture directe chez le fileul, sans demande ; une feuille par magasin, aucun stock touché', (t) async {
      final m = magasin();
      await rattacher(t, m);
      await ouvrir(t, m, 'imp-inventaire-comptage');
      await televerser(t, 'ic-valide');
      expect(find.byKey(const Key('imp-importer-et-demander')), findsNothing, reason: 'pas de demande : le comptage n\'écrit que `inventaires`');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      final feuilles = m.collection('inventaires').toutes;
      expect(feuilles.length, 2);
      expect({for (final f in feuilles) f['magasin']}, {'gros', 'detail'});
      expect(feuilles.every((f) => f['statutInv'] == 'importe'), isTrue);
      expect(stock(m, 'AMOXI', 'stockGros'), 30, reason: 'l\'import crée la feuille et ne touche à aucun stock');
      expect(m.collection(demandesImportCollection).toutes, isEmpty);
      await t.pump(const Duration(seconds: 10));
    });
  });
  group('la régularisation d\'une feuille importée (geste humain du registre des inventaires)', () {
    Magasin avecFeuille() {
      final m = magasin();
      final f = ((vecteurs['stock'] as Map)['feuilles'] as List).cast<Map>().firstWhere((x) => x['magasin'] == 'gros').cast<String, Object?>();
      m.collection('inventaires').inserer({...f, 'id': 'INVX1', 'statut': 'actif'});
      return m;
    }

    testWidgets('la feuille se lit « Comptage importé, à régulariser » ; régulariser écrit UN mouvement par écart et passe la feuille à validée', (t) async {
      final m = avecFeuille();
      await ouvrir(t, m, 'm6-inventaire', role: 'stock');
      expect(find.text('Comptage importé, à régulariser'), findsOneWidget);
      await toucher(t, find.byKey(const Key('inventaire-regulariser-INV-0003')));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Régulariser'));
      await t.pump(const Duration(milliseconds: 300));
      expect(stock(m, 'AMOXI', 'stockGros'), 28);
      expect(stock(m, 'AMOXI', 'stock'), 28);
      final mv = m.collection('mouvements').toutes.where((x) => x['type'] == 'inventaire').toList();
      expect(mv.length, 1);
      expect(mv.single['justificatif'], 'Inventaire INV-0003');
      expect(m.collection('inventaires').parId('INVX1')!['statutInv'], 'valide');
      expect(find.byKey(const Key('inventaire-regulariser-INV-0003')), findsNothing, reason: 'une feuille régularisée ne se régularise pas deux fois');
      await t.pump(const Duration(seconds: 15));
    });

    testWidgets('le stock a bougé depuis le comptage : refus nommé, la feuille reste à régulariser, aucun stock ne bouge', (t) async {
      final m = avecFeuille();
      m.collection('produits').mettreAJour('PRD0003', {'stockGros': 31});
      await ouvrir(t, m, 'm6-inventaire', role: 'stock');
      await toucher(t, find.byKey(const Key('inventaire-regulariser-INV-0003')));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Régulariser'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('a bougé depuis le comptage'), findsWidgets);
      expect(stock(m, 'AMOXI', 'stockGros'), 31);
      expect(m.collection('mouvements').toutes.where((x) => x['type'] == 'inventaire'), isEmpty);
      expect(m.collection('inventaires').parId('INVX1')!['statutInv'], 'importe');
      await t.pump(const Duration(seconds: 15));
    });

    testWidgets('sans le droit d\'éditer l\'écran, la commande est ABSENTE', (t) async {
      final m = avecFeuille();
      await ouvrir(t, m, 'm6-inventaire', role: 'direction');
      expect(find.text('Comptage importé, à régulariser'), findsOneWidget);
      expect(find.byKey(const Key('inventaire-regulariser-INV-0003')), findsNothing);
      await t.pump(const Duration(seconds: 15));
    });
  });
}
