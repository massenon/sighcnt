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
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LOT 8B, GROUPE COMPTABILITÉ AU POSTE : les immobilisations, les budgets et les courriers sont portés. Les fichiers sont ceux que la maquette a écrits (`test/fixtures/import`), le magasin est
/// celui des vecteurs. Les trois jeux sont restreints et n'écrivent aucune configuration : écriture directe, même chez un fileul. Un budget ne s'écrit jamais sur un exercice clos (la garde est au
/// MOTEUR du magasin, l'écran la subit comme le fichier).
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();
Uint8List fixture(String nom) => File('test/fixtures/import/$nom.xlsx').readAsBytesSync();
final jour = DateTime(2026, 11, 1);

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
      key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: ecran, magasin: m, horloge: () => jour));
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



void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  group('la voie', () {
    test('QUAND : les trois jeux restreints de comptabilité s\'écrivent directement, même sur un fileul rattaché (aucune configuration de la mère)', () {
      for (final j in ['immobilisations', 'budgets', 'courriers']) {
        expect(DemandesImportPoste.voie(fileulRattache: true, declaration: donnees.matrice.matriceImport.declaration(j)), VoieImportFileul.directe, reason: j);
      }
    });
  });

  group('la garde du magasin : un exercice clos ne reçoit plus de budget', () {
    test('le motif est celui de l\'écran de la maquette ; l\'écriture est refusée au MOTEUR ; un exercice ouvert reçoit ses budgets', () {
      final m = magasin();
      final garde = ((vecteurs['compta'] as Map)['budgets'] as Map)['garde'] as Map;
      final motif = ((garde['toast'] as List).single as Map)['detail'];
      expect(
          () => m.collection('budgets').inserer({'reference': 'BG-2025-900', 'exercice': 2025, 'centreCout': 'laboratoire', 'centre': 'Laboratoire', 'nature': 'Investissements', 'prevu': 1}),
          throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', motif)));
      expect(m.collection('budgets').toutes.length, 1, reason: 'rien n\'est écrit');
      m.collection('budgets').inserer({'reference': 'BG-2026-900', 'exercice': 2026, 'centreCout': 'laboratoire', 'centre': 'Laboratoire', 'nature': 'Investissements', 'prevu': 1});
      expect(m.collection('budgets').toutes.length, 2);
    });
  });

  group('l\'écran', () {
    testWidgets('BUDGETS : un exercice clos (liasse) ou en clôture est refusé, nommé ; un fichier d\'exercices ouverts s\'écrit, numéroté à la suite', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-budgets', role: 'da');
      await televerser(t, 'bu-exercice-clos');
      expect(find.byKey(const Key('imp-constat-EXERCICE_CLOS')), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (1 ligne)'), findsNothing);
      await televerser(t, 'bu-exercice-en-cloture');
      expect(find.byKey(const Key('imp-constat-EXERCICE_EN_CLOTURE')), findsWidgets);
      await televerser(t, 'bu-valide');
      expect(find.textContaining('Analyse conforme.'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      final refs = [for (final b in m.collection('budgets').toutes) '${b['reference']}'];
      expect(refs, containsAll(['BG-2027-002', 'BG-2027-003', 'BG-2026-001']));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('IMMOBILISATIONS : le numéro explicite d\'abord, le numéro IM-NNN à la suite ; un bien cédé ne s\'importe pas', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-immobilisations', role: 'da');
      await televerser(t, 'im-bien-cede');
      expect(find.byKey(const Key('imp-constat-BIEN_CEDE')), findsWidgets);
      await televerser(t, 'im-valide');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect({for (final i in m.collection('immobilisations').toutes) '${i['reference']}'}, {'IM-001', 'IM-050', 'IM-051'});
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('COURRIERS : un courrier déjà tenu est IGNORÉ et compté, le neuf s\'écrit ; rejoué, rien à écrire', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-courriers', role: 'da');
      await televerser(t, 'co-deja-tenu');
      expect(find.byKey(const Key('imp-constat-IGNORE_EXISTANT')), findsWidgets);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (1 ligne)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(m.collection('courriers').toutes.length, 2);
      expect(m.collection('courriers').toutes.firstWhere((c) => c['objet'] == 'Courrier neuf')['traitement'], 'en_attente');
      await televerser(t, 'co-deja-tenu');
      expect(find.textContaining('Rien à écrire.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('FILEUL rattaché : les trois jeux s\'écrivent chez lui, sans demande (la commande de demande est ABSENTE)', (t) async {
      final m = magasin();
      await rattacher(t, m);
      await ouvrir(t, m, 'imp-immobilisations', role: 'da');
      await televerser(t, 'im-valide');
      expect(find.byKey(const Key('imp-importer-et-demander')), findsNothing);
      expect(find.byKey(const Key('imp-deposer-demande')), findsNothing);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(m.collection('immobilisations').toutes.length, 3);
      expect(m.collection(demandesImportCollection).toutes, isEmpty);
      await t.pump(const Duration(seconds: 10));
    });
  });
}
