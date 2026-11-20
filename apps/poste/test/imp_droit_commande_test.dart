import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LOT 8 : la commande d'écriture de la fenêtre d'import suit le droit EN FORCE, relu à chaque affichage. Un fichier analysé par qui détenait le droit, dont le droit est retiré à chaud
/// (une fiche `rbac` écrite pendant que la fenêtre est ouverte), ne laisse PAS la commande « Confirmer l'importation » à l'écran : une commande interdite est absente, jamais grisée.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();
Uint8List fixture(String nom) => File('test/fixtures/import/$nom.xlsx').readAsBytesSync();

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  testWidgets('le droit d\'importer retiré à chaud : la commande « Confirmer l\'importation » disparaît de la fenêtre déjà ouverte', (t) async {
    final m = Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });
    t.view.physicalSize = const Size(1600, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(
        key: UniqueKey(), donnees: donnees, config: const ConfigPoste(mode: ModePoste.fileul, role: 'stock'), ecranInitial: 'imp-fournisseurs', magasin: m, horloge: () => DateTime(2026, 11, 1)));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    SelecteursImport.choisir = () async => FichierChoisi('fo-valide.xlsx', fixture('fo-valide'));
    final televerser = find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)');
    await t.ensureVisible(televerser);
    await t.tap(televerser);
    await t.pump(const Duration(milliseconds: 600));
    final confirmer = find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)');
    expect(confirmer, findsOneWidget, reason: 'le gestionnaire détient le jeu : fichier analysé, commande offerte');
    // Le droit d'importer est retiré (voir reste accordé) pendant que la fenêtre est ouverte.
    m.collection('rbac').inserer({
      'role': 'stock',
      'statut': 'actif',
      'droitsImport': {
        'fournisseurs': {'voir': true, 'importer': false, 'annuler': false}
      }
    });
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(confirmer, findsNothing, reason: 'le droit en force n\'est plus celui d\'importer : la commande est ABSENTE');
    await t.pump(const Duration(seconds: 10));
  });
}
