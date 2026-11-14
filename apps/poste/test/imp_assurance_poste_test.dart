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

/// LOT 8B, GROUPE GARANTIES ET COUVERTURES AU POSTE : les garanties des souscripteurs (versions datées) et les couvertures d'assurance sont portées. Les fichiers sont ceux que la maquette a
/// écrits (`test/fixtures/import`), le magasin est celui des vecteurs. Voie d'un fileul rattaché : les garanties (configuration) s'écrivent chez lui ET partent à la mère en demande ; les couvertures
/// (activité) s'écrivent directement. RG-09 : la prise en charge se lit à la date de la pièce, une pièce émise garde le taux de sa date.
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


Map<String, Object?> repartition(Magasin m, String date) {
  final r = repartir(
      patient: m.collection('patients').parId('PAT0003'),
      lignes: [
        {'libelle': 'Consultation généraliste', 'categorie': 'consultation', 'montant': 10000}
      ],
      date: date,
      couvertures: m.collection('couverturesAssurance').toutes,
      souscripteurs: m.collection('souscripteurs').toutes,
      garanties: m.collection('garanties').toutes);
  return {'partAssureur': r.partAssureur, 'partPatient': r.partPatient};
}

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  group('la voie', () {
    test('QUAND : sur un fileul rattaché les garanties (configuration) s\'écrivent chez lui ET se demandent ; les couvertures (activité) s\'écrivent directement ; ailleurs tout est direct', () {
      VoieImportFileul voie(String j, {bool fileul = true}) => DemandesImportPoste.voie(fileulRattache: fileul, declaration: donnees.matrice.matriceImport.declaration(j));
      expect(voie('garanties'), VoieImportFileul.directeEtDemande);
      expect(voie('couvertures-assurance'), VoieImportFileul.directe);
      expect(voie('garanties', fileul: false), VoieImportFileul.directe);
    });
  });

  group('RG-09 : une version datée ne change pas ce que dit une pièce émise', () {
    testWidgets('GARANTIES : la version du 2027-01-01 (70 %) est lue à partir de sa date ; avant, la pièce garde 80 % ; le fichier rejoué est « inchangé »', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-garanties', role: 'da');
      expect(repartition(m, '2026-12-15'), {'partAssureur': 8000, 'partPatient': 2000});
      await televerser(t, 'ga-valide');
      expect(find.textContaining('Analyse conforme.'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      final serie = m.collection('garanties').toutes.where((g) => g['libelle'] == 'Consultation généraliste').toList();
      expect(serie.length, 2, reason: 'la version remplacée reste écrite');
      expect(serie.map((g) => g['version']).toSet(), {1, 2});
      expect(repartition(m, '2026-12-15'), {'partAssureur': 8000, 'partPatient': 2000}, reason: 'la pièce émise avant la date garde son taux');
      expect(repartition(m, '2027-02-01'), {'partAssureur': 7000, 'partPatient': 3000}, reason: 'à partir de la date, la nouvelle version');
      await televerser(t, 'ga-valide');
      expect(find.byKey(const Key('imp-constat-GARANTIE_INCHANGEE')), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('GARANTIES : une facture émise sous la grille refuse la date d\'effet, nommée (FACTURE_DEJA_EMISE), rien n\'est écrit', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-garanties', role: 'da');
      await televerser(t, 'ga-facture-emise');
      expect(find.byKey(const Key('imp-constat-FACTURE_DEJA_EMISE')), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (1 ligne)'), findsNothing);
      expect(m.collection('garanties').toutes.length, 3);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('COUVERTURES : la précédente est close la veille, la couverture du dossier est reprise au premier changement, la fiche du dossier suit la couverture en force AUJOURD\'HUI', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-couvertures-assurance', role: 'da');
      await televerser(t, 'cv-valide');
      expect(find.textContaining('Analyse conforme.'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      final cou = m.collection('couverturesAssurance').toutes;
      expect(cou.firstWhere((c) => c['id'] == 'COU1')['fin'], '2029-12-31');
      expect(cou.where((c) => c['patientId'] == 'PAT0004').length, 2, reason: 'reprise du dossier + couverture neuve');
      expect(cou.firstWhere((c) => c['patientId'] == 'PAT0004' && c['debut'] == null)['fin'], '2030-01-31');
      expect(m.collection('patients').parId('PAT0003')!['assureur'], 'AFR', reason: 'la bascule de 2030 ne change rien ce matin');
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('sur un fileul rattaché', () {
    testWidgets('GARANTIES : écrit chez le fileul (marquage « en attente de la mère ») ET demande déposée, en un geste', (t) async {
      final m = magasin();
      await rattacher(t, m);
      await ouvrir(t, m, 'imp-garanties', role: 'da');
      await televerser(t, 'ga-suivante');
      expect(find.byKey(const Key('imp-importer-et-demander')), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (1 ligne)'), findsNothing);
      await toucher(t, find.byKey(const Key('imp-importer-et-demander')));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire chez moi et envoyer la demande'));
      await t.pump(const Duration(milliseconds: 300));
      expect(m.collection('garanties').toutes.where((g) => g['version'] == 2 && g['libelle'] == 'Consultation généraliste').length, 1);
      expect(m.collection(demandesImportCollection).toutes, hasLength(1));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('COUVERTURES : écriture directe chez le fileul, sans demande (activité)', (t) async {
      final m = magasin();
      await rattacher(t, m);
      await ouvrir(t, m, 'imp-couvertures-assurance', role: 'da');
      await televerser(t, 'cv-suivante');
      expect(find.byKey(const Key('imp-importer-et-demander')), findsNothing);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (1 ligne)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(m.collection('couverturesAssurance').toutes.where((c) => c['debut'] == '2030-06-01').length, 1);
      expect(m.collection(demandesImportCollection).toutes, isEmpty);
      await t.pump(const Duration(seconds: 10));
    });
  });
}
