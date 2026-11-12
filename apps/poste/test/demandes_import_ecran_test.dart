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
import 'package:sigh_poste/sync/service_demandes_import.dart';

import 'aide_polices.dart';

/// LA DEMANDE D'IMPORT AU POSTE (lot IMP-C, réponse Q5 de la Direction) : sur un FILEUL rattaché, un référentiel de configuration importé (les fournisseurs, tenus par la mère seule) ne
/// s'écrit pas ici : le fichier VÉRIFIÉ part en demande à la mère, qui rejoue l'analyse sous le rôle de l'auteur, applique ou refuse en nommant ; le fileul lit l'état. Les fichiers sont ceux
/// que la maquette a écrits (`test/fixtures/import`).
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();
Uint8List fixture(String nom) => File('test/fixtures/import/$nom.xlsx').readAsBytesSync();

Magasin magasin() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

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

Future<void> televerser(WidgetTester t, String fixtureNom) async {
  SelecteursImport.choisir = () async => FichierChoisi('$fixtureNom.xlsx', fixture(fixtureNom));
  await toucher(t, find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'));
  await t.pump(const Duration(milliseconds: 300));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });
  final envoyer = find.widgetWithText(BoutonSigh, 'Envoyer la demande à la mère (2 lignes)');
  final confirmer = find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)');

  test('QUAND : seulement sur un fileul rattaché, et seulement pour un jeu dont une collection cible est de configuration', () {
    final decl = donnees.matrice.matriceImport.declaration;
    expect(DemandesImportPoste.passeParUneDemande(fileulRattache: true, declaration: decl('fournisseurs')), isTrue);
    expect(DemandesImportPoste.passeParUneDemande(fileulRattache: true, declaration: decl('plan-comptable')), isTrue);
    expect(DemandesImportPoste.passeParUneDemande(fileulRattache: false, declaration: decl('fournisseurs')), isFalse, reason: 'la mère, ou un poste autonome, écrit directement');
    expect(DemandesImportPoste.passeParUneDemande(fileulRattache: true, declaration: decl('patients')), isFalse, reason: 'l\'activité s\'écrit au fileul, par ses règles de fusion');
    expect(DemandesImportPoste.passeParUneDemande(fileulRattache: true, declaration: null), isFalse);
  });

  cas('FILEUL RATTACHÉ : le fichier est vérifié ici, puis envoyé en demande ; rien n\'est écrit chez lui ; il lit l\'état puis la réponse nommée de la mère', (t) async {
    final m = magasin();
    await rattacher(t, m);
    final avant = m.collection('fournisseurs').toutes.length;
    await ouvrir(t, m, 'm7-fournisseurs', role: 'stock');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    expect(find.textContaining('Réglé sur la mère. Ce jeu écrit la configuration de la clinique'), findsOneWidget);
    await televerser(t, 'fo-valide');
    expect(find.textContaining('Analyse conforme. 2 ligne(s)'), findsOneWidget);
    expect(confirmer, findsNothing, reason: 'le fileul n\'écrit pas la configuration : la commande d\'import local est absente');
    expect(envoyer, findsOneWidget);
    await toucher(t, envoyer);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Envoyer la demande'));
    final d = m.collection(demandesImportCollection).toutes.single;
    expect([d['etat'], d['jeu'], d['demandeRole'], d['aEcrire']], [demandeImportEnAttente, 'fournisseurs', 'stock', 2]);
    expect(d['demandePar'], donnees.matrice.libelle('stock'), reason: 'RG-12 : la demande porte son auteur');
    expect(m.collection('fournisseurs').toutes.length, avant, reason: 'rien n\'est écrit sur le fileul');
    expect(m.collection(collectionLots).toutes, isEmpty, reason: 'aucun lot local : la mère écrira le sien');
    expect(find.textContaining('envoyée à la mère'), findsWidgets);
    expect(find.text('En attente de la mère'), findsOneWidget, reason: 'le fileul voit l\'état de sa demande');
    // La mère répond : refus nommé. Le fileul le lit (code, motif, geste), sans aucune valeur de cellule.
    m.collection(demandesImportCollection).mettreAJour('${d['id']}', {
      'etat': demandeImportRefusee,
      'resultatCode': 'DOUBLON_MAGASIN',
      'resultatMotif': 'rejoué à la mère, le fichier est refusé (ligne 2, Code) : une fiche équivalente est déjà tenue',
      'resultatGeste': 'Retirez la ligne : un import ne modifie jamais une fiche tenue.',
      'lignes': <Object?>[],
    });
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Refusée par la mère'), findsOneWidget);
    expect(find.byKey(const Key('imp-demande-refus-DOUBLON_MAGASIN')), findsOneWidget);
    expect(find.textContaining('une fiche équivalente est déjà tenue'), findsOneWidget);
  });

  cas('UN FICHIER REFUSÉ NE PART JAMAIS : la vérification du fileul est la même que celle de la mère, aucune demande n\'est déposée', (t) async {
    final m = magasin();
    await rattacher(t, m);
    await ouvrir(t, m, 'm7-fournisseurs', role: 'stock');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    await televerser(t, 'fo-ifu-invalide');
    expect(find.textContaining('Fichier refusé. Rien n’a été écrit.'), findsOneWidget);
    expect(envoyer, findsNothing);
    expect(m.collection(demandesImportCollection).toutes, isEmpty);
    expect(m.collection(collectionLots).toutes.single['etat'], 'refuse', reason: 'consigné à l\'historique local comme tout fichier refusé');
  });

  cas('LA MÈRE (ou un poste autonome) importe en direct : aucune demande, la commande d\'import local est présente', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm7-fournisseurs', role: 'stock');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    expect(find.textContaining('Réglé sur la mère. Ce jeu écrit'), findsNothing);
    await televerser(t, 'fo-valide');
    expect(confirmer, findsOneWidget);
    expect(envoyer, findsNothing);
  });

  cas('LE SERVICE DE LA MÈRE traite la demande : analyse rejouée sous le rôle de l\'auteur, lot écrit à son nom, verdict nommé sur la même fiche, lignes effacées', (t) async {
    // Le fileul dépose (collection `demandesImport`), la mère écoute et traite.
    final fileul = magasin();
    await rattacher(t, fileul);
    await ouvrir(t, fileul, 'm7-fournisseurs', role: 'stock');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    await televerser(t, 'fo-valide');
    await toucher(t, envoyer);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Envoyer la demande'));
    final demande = {...fileul.collection(demandesImportCollection).toutes.single};
    expect((demande['lignes'] as List), isNotEmpty);
    // La demande arrive à la mère par le pont (fiche descriptive) ; le service la traite.
    final mere = magasin();
    mere.collection(demandesImportCollection).appliquerDistante(demande);
    final service = ServiceDemandesImport(mere, donnees: () async => donnees, horloge: () => DateTime(2026, 11, 1));
    final n = await t.runAsync(() => service.traiter());
    expect(n, 1);
    final v = mere.collection(demandesImportCollection).parId('${demande['id']}')!;
    expect(v['etat'], demandeImportAppliquee, reason: '${v['resultatMotif']}');
    expect(v['resultatLot'], 'IMP-2026-001');
    expect(v['lignes'], isEmpty, reason: 'aucune valeur de cellule ne reste à la demande');
    final ecrits = mere.collection('fournisseurs').actives.where((f) => f['lotImport'] == 'IMP-2026-001').toList();
    expect(ecrits.map((f) => f['code']).toSet(), {'CAME', 'LOCAL'});
    expect(ecrits.every((f) => f['validePar'] == donnees.matrice.libelle('stock')), isTrue, reason: 'le lot est signé de l\'auteur de la demande, pas de la mère');
    // Rejouée une seconde fois (même fichier) : la mère REFUSE en nommant, elle ne réécrit rien.
    mere.collection(demandesImportCollection).appliquerDistante({...demande, 'id': 'DIM-2', 'etat': demandeImportEnAttente, 'lignes': demande['lignes']});
    final avant = mere.collection('fournisseurs').toutes.length;
    await t.runAsync(() => service.traiter());
    final v2 = mere.collection(demandesImportCollection).parId('DIM-2')!;
    expect([v2['etat'], v2['resultatCode']], [demandeImportRefusee, 'RIEN_A_ECRIRE'],
        reason: 'fournisseurs est en mode « ignorer » : toutes les lignes sont des fiches déjà tenues, rien à écrire, refus nommé');
    expect(v2['resultatGeste'], isNotEmpty);
    expect(mere.collection('fournisseurs').toutes.length, avant);
  });
}
