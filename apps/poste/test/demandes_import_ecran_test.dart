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
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
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
  final envoyer = find.byKey(const Key('imp-envoyer-demande'));
  final directe = find.byKey(const Key('imp-importer-et-demander'));
  final confirmer = find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)');

  test('QUAND : la voie dépend du jeu et du poste (fileul rattaché, collections cibles de configuration, quantités de stock, jeu restreint)', () {
    final decl = donnees.matrice.matriceImport.declaration;
    VoieImportFileul voie(String j, {bool fileul = true}) => DemandesImportPoste.voie(fileulRattache: fileul, declaration: decl(j));
    expect(voie('fournisseurs'), VoieImportFileul.directeEtDemande, reason: 'IMP-D : écrit chez le fileul ET demande à la mère');
    expect(voie('plan-comptable'), VoieImportFileul.directeEtDemande);
    expect(voie('fournisseurs', fileul: false), VoieImportFileul.directe, reason: 'la mère, ou un poste autonome, écrit directement');
    expect(voie('patients'), VoieImportFileul.directe, reason: 'l\'activité s\'écrit au fileul, par ses règles de fusion');
    expect(DemandesImportPoste.voie(fileulRattache: true, declaration: null), VoieImportFileul.directe);
    expect(voie('grand-stock'), VoieImportFileul.directeEtDemande, reason: 'IMP-E : le Grand Stock s\'écrit aussi chez le gestionnaire de stock');
    expect(voie('personnel'), VoieImportFileul.reserveeALaMere);
    expect(voie('personnel', fileul: false), VoieImportFileul.directe, reason: 'la mère importe en direct');
  });

  cas('JEU RESTREINT DE CONFIGURATION (le personnel) : le fileul le dit, vérifie le fichier si on veut, et ne propose NI import NI demande ; la mère importe', (t) async {
    final m = magasin();
    await rattacher(t, m);
    await ouvrir(t, m, 'm10-personnel', role: 'admin');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    expect(find.textContaining('Réglé sur la mère et jeu restreint.'), findsOneWidget);
    SelecteursImport.choisir = () async => FichierChoisi('pe-valide.xlsx', fixture('pe-valide'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Analyse conforme.'), findsOneWidget);
    expect(find.byKey(const Key('imp-envoyer-demande')), findsNothing, reason: 'les lignes d\'un jeu restreint ne voyagent pas dans une demande');
    expect(directe, findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'), findsNothing, reason: 'et rien ne s\'écrit sur un fileul : la configuration est réglée sur la mère');
    expect(m.collection(demandesImportCollection).toutes, isEmpty);
  });

  cas('FILEUL RATTACHÉ (IMP-D) : la fenêtre dit AVANT le oui ce qui va se passer ; le fichier s\'écrit chez lui tout de suite ET la demande part ; marquage, état, refus nommé, restitution', (t) async {
    final m = magasin();
    await rattacher(t, m);
    ApplicateurConfiguration(m, (_) async => []).poserGardes();
    final avant = m.collection('fournisseurs').toutes.length;
    await ouvrir(t, m, 'm7-fournisseurs', role: 'stock');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    expect(find.textContaining('Écrit chez vous maintenant, la mère confirmera.'), findsOneWidget, reason: 'la fenêtre le dit dès l\'ouverture');
    await televerser(t, 'fo-valide');
    expect(find.textContaining('Analyse conforme. 2 ligne(s)'), findsOneWidget);
    expect(confirmer, findsNothing, reason: 'une seule commande : écrire chez soi ET prévenir la mère');
    expect(envoyer, findsNothing, reason: 'il n\'y a plus de demande seule : tout jeu de configuration s\'écrit chez le fileul ET part en demande');
    expect(directe, findsOneWidget);
    expect(m.collection('fournisseurs').toutes.length, avant, reason: 'l\'analyse n\'écrit rien');
    await toucher(t, directe);
    // AVANT le oui : le message annonce l'écriture immédiate, la demande automatique, le marquage, la restitution sur refus.
    expect(find.textContaining('vont s’écrire CHEZ VOUS maintenant'), findsOneWidget);
    expect(find.textContaining('Une demande part automatiquement à la mère'), findsOneWidget);
    expect(find.textContaining('en attente de la mère'), findsWidgets);
    expect(find.textContaining('elles sont restituées'), findsNWidgets(2), reason: 'la note de la fenêtre ET le message de confirmation, avant le oui');
    expect(m.collection('fournisseurs').toutes.length, avant, reason: 'rien n\'est écrit tant que l\'agent n\'a pas dit oui');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire chez moi et envoyer la demande'));
    final d = m.collection(demandesImportCollection).toutes.single;
    expect([d['etat'], d['jeu'], d['demandeRole'], d['aEcrire'], d['ecritureDirecte']], [demandeImportEnAttente, 'fournisseurs', 'stock', 2, true]);
    expect(d['demandePar'], donnees.matrice.libelle('stock'), reason: 'RG-12 : la demande porte son auteur');
    expect(m.collection('fournisseurs').toutes.length, avant + 2, reason: 'écrit chez le fileul tout de suite');
    expect(m.collection('fournisseurs').actives.where((f) => f[champEnAttenteMere] == d['id']), hasLength(2));
    expect(m.collection(collectionLots).toutes.single['etat'], 'applique');
    expect(find.textContaining('est partie à la mère'), findsWidgets);
    expect(find.text('Écrit chez vous, en attente de la mère'), findsWidgets, reason: 'le fileul voit l\'état de sa demande : jamais « appliquée » avant la mère');
    expect(find.textContaining('Appliquée par la mère'), findsNothing);
    // La mère refuse : le fileul restitue et lit le code, le motif, le geste ET la restitution.
    m.collection(demandesImportCollection).mettreAJour('${d['id']}', {
      'etat': demandeImportRefusee,
      'resultatCode': 'RESULTAT_DIFFERENT',
      'resultatMotif': 'la mère ne produirait pas le même résultat que chez vous : elle n’écrirait pas la ligne 2 (déjà tenue chez elle)',
      'resultatGeste': 'Votre écriture locale est restituée.',
      'lignes': <Object?>[],
    });
    expect(DemandesImportPoste(m, role: 'stock', auteur: () => 'X', matrice: donnees.matrice, aujourdhui: () => DateTime(2026, 11, 1)).traiterVerdicts(), 1);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Refusée par la mère, écriture restituée'), findsWidgets);
    expect(find.byKey(const Key('imp-demande-refus-RESULTAT_DIFFERENT')), findsOneWidget);
    expect(find.textContaining('Votre écriture locale a été restituée (2 fiche(s) archivée(s))'), findsOneWidget);
    expect(m.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME' || f['code'] == 'LOCAL'), isEmpty);
  });

  cas('LE MARQUAGE « EN ATTENTE DE LA MÈRE » SE LIT sur la ligne du tableau de l\'écran de référentiel, et seulement tant que la mère n\'a pas confirmé', (t) async {
    final m = magasin();
    await rattacher(t, m);
    ApplicateurConfiguration(m, (_) async => []).poserGardes();
    final p = DemandesImportPoste(m, role: 'stock', auteur: () => 'LE GESTIONNAIRE', matrice: donnees.matrice, aujourdhui: () => DateTime(2026, 11, 1), etiquette: 'F1');
    final profil = ProfilImport(role: 'stock', libelleRole: 'stock', matrice: donnees.matrice.matriceImport);
    final a = analyserLignes(jeuImportParId('fournisseurs')!, [
      for (final l in (vecteurs['cas'] as List).cast<Map>().firstWhere((c) => c['id'] == 'fo-valide')['lignes'] as List) [for (final x in l as List) x]
    ], 'fo-valide.xlsx', PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 1), nomAgent: 'X', profil: profil));
    final r = p.importerEtDemander(jeuImportParId('fournisseurs')!, a);
    expect(r.resultat.ok, isTrue);
    await ouvrir(t, m, 'm7-fournisseurs', role: 'stock');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('kit:marque-attente-mere')), findsWidgets, reason: 'les fiches importées portent le marquage à l\'écran');
    // La mère confirme : le marquage est levé, plus rien n'est « en attente ».
    m.collection(demandesImportCollection).mettreAJour('${r.demande!['id']}', {'etat': demandeImportAppliquee, 'resultatLot': 'IMP-2026-001', 'resultatEcrits': 2, 'lignes': <Object?>[]});
    p.traiterVerdicts();
    await ouvrir(t, m, 'm7-fournisseurs', role: 'stock');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('kit:marque-attente-mere')), findsNothing);
  });

  cas('L\'HISTORIQUE DES LOTS dit « écrit chez vous, en attente de la mère » (jamais « appliqué » avant elle), propose l\'annulation tant qu\'elle n\'a pas statué, puis la retire', (t) async {
    final m = magasin();
    await rattacher(t, m);
    ApplicateurConfiguration(m, (_) async => []).poserGardes();
    final p = DemandesImportPoste(m, role: 'stock', auteur: () => donnees.matrice.libelle('stock')!, matrice: donnees.matrice, aujourdhui: () => DateTime(2026, 11, 1), etiquette: 'F1');
    final profil = ProfilImport(role: 'stock', libelleRole: 'stock', matrice: donnees.matrice.matriceImport);
    final a = analyserLignes(jeuImportParId('fournisseurs')!, [
      for (final l in (vecteurs['cas'] as List).cast<Map>().firstWhere((c) => c['id'] == 'fo-valide')['lignes'] as List) [for (final x in l as List) x]
    ], 'fo-valide.xlsx', PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 1), nomAgent: donnees.matrice.libelle('stock')!, profil: profil));
    final r = p.importerEtDemander(jeuImportParId('fournisseurs')!, a);
    final lot = '${r.resultat.lot!['reference']}';
    await ouvrir(t, m, 'imp-fournisseurs', role: 'stock');
    await t.pump(const Duration(milliseconds: 300));
    String etat() => t.widget<BadgeSigh>(find.byKey(Key('imp-lot-etat-$lot'))).libelle;
    expect(etat(), 'Écrit chez vous, en attente de la mère');
    expect(find.byTooltip('Annuler le lot'), findsOneWidget, reason: 'le droit d\'annuler du jeu, tant que la mère n\'a pas statué');
    m.collection(demandesImportCollection).mettreAJour('${r.demande!['id']}', {'etat': demandeImportAppliquee, 'resultatLot': 'IMP-2026-007', 'resultatEcrits': 2, 'lignes': <Object?>[]});
    await ouvrir(t, m, 'imp-fournisseurs', role: 'stock');
    await t.pump(const Duration(milliseconds: 300));
    expect(etat(), 'Appliqué', reason: 'confirmé par la mère seulement');
    expect(find.byTooltip('Annuler le lot'), findsNothing, reason: 'une commande interdite est absente : la mère détient les mêmes fiches');
  });

  cas('GRAND STOCK (IMP-E) : la fenêtre dit AVANT le oui « écrit chez vous maintenant, la mère confirmera » et que ce stock n\'est vu que de ce poste ; articles, lots et mouvements s\'écrivent chez le fileul, marqués ; la demande part ; aucun bouton de demande seule', (t) async {
    final m = magasin();
    await rattacher(t, m);
    ApplicateurConfiguration(m, (_) async => []).poserGardes();
    final avant = m.collection('produits').toutes.length;
    await ouvrir(t, m, 'm6-import-grand-stock', role: 'stock');
    expect(find.textContaining('Écrit chez vous maintenant, la mère confirmera.'), findsOneWidget, reason: 'le même texte que les autres jeux, dès l\'ouverture');
    expect(find.textContaining('Un stock chez vous d’abord.'), findsOneWidget, reason: 'et ce que cela veut dire pour un stock');
    expect(find.textContaining('ET des quantités de stock (lots, mouvements)'), findsNothing, reason: 'l\'ancienne note de la demande seule n\'existe plus');
    await televerser(t, 'gs-valide');
    expect(envoyer, findsNothing, reason: 'plus de demande seule');
    expect(find.textContaining('Confirmer l’importation'), findsNothing);
    expect(directe, findsOneWidget);
    await toucher(t, directe);
    expect(find.textContaining('ce stock n’est vu que de votre poste'), findsOneWidget, reason: 'la confirmation le dit aussi');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire chez moi et envoyer la demande'));
    final d = m.collection(demandesImportCollection).toutes.single;
    expect([d['etat'], d['jeu'], d['ecritureDirecte']], [demandeImportEnAttente, 'grand-stock', true]);
    expect(m.collection('produits').toutes.length, avant + 2, reason: 'MED1 et GANT1 sont écrits chez le fileul');
    expect(m.collection('lots').toutes.where((f) => f[champEnAttenteMere] == d['id']), hasLength(2), reason: 'les lots portent le marquage « en attente de la mère »');
    expect(m.collection('mouvements').toutes.where((f) => f[champEnAttenteMere] == d['id']), hasLength(3));
    expect(find.text('Écrit chez vous, en attente de la mère'), findsWidgets);
    // L'état « en attente de la mère » se lit sur les lots importés (écran des lots de M6) et sur les mouvements.
    await ouvrir(t, m, 'm6-lots', role: 'stock');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('kit:marque-attente-mere')), findsWidgets, reason: 'un lot importé et non confirmé se lit « En attente de la mère » à l\'écran des lots');
    await ouvrir(t, m, 'm6-mouvements', role: 'stock');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('kit:marque-attente-mere')), findsWidgets, reason: 'et les entrées au registre des mouvements');
  });

  cas('UN FICHIER REFUSÉ NE PART JAMAIS : la vérification du fileul est la même que celle de la mère, rien n\'est écrit, aucune demande n\'est déposée', (t) async {
    final m = magasin();
    await rattacher(t, m);
    await ouvrir(t, m, 'm7-fournisseurs', role: 'stock');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    await televerser(t, 'fo-ifu-invalide');
    expect(find.textContaining('Fichier refusé. Rien n’a été écrit.'), findsOneWidget);
    expect(envoyer, findsNothing);
    expect(directe, findsNothing);
    expect(m.collection(demandesImportCollection).toutes, isEmpty);
    expect(m.collection(collectionLots).toutes.single['etat'], 'refuse', reason: 'consigné à l\'historique local comme tout fichier refusé');
  });

  cas('LA MÈRE (ou un poste autonome) importe en direct : aucune demande, la commande d\'import local est présente', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm7-fournisseurs', role: 'stock');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    expect(find.textContaining('Écrit chez vous maintenant'), findsNothing);
    await televerser(t, 'fo-valide');
    expect(confirmer, findsOneWidget);
    expect(envoyer, findsNothing);
    expect(directe, findsNothing);
  });

  cas('LE SERVICE DE LA MÈRE confirme la demande directe : analyse rejouée sous le rôle de l\'auteur, MÊMES identifiants que chez le fileul, verdict nommé sur la même fiche, lignes effacées', (t) async {
    final fileul = magasin();
    await rattacher(t, fileul);
    ApplicateurConfiguration(fileul, (_) async => []).poserGardes();
    await ouvrir(t, fileul, 'm7-fournisseurs', role: 'stock');
    await toucher(t, find.byKey(const Key('imp-bouton-importer')));
    await televerser(t, 'fo-valide');
    await toucher(t, directe);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire chez moi et envoyer la demande'));
    final demande = {...fileul.collection(demandesImportCollection).toutes.single};
    expect((demande['lignes'] as List), isNotEmpty);
    final idsFileul = {for (final f in fileul.collection('fournisseurs').actives.where((f) => f[champEnAttenteMere] == demande['id'])) '${f['id']}'};
    expect(idsFileul, hasLength(2));
    // La demande arrive à la mère par le pont (fiche descriptive) ; le service la traite.
    final mere = magasin();
    mere.collection(demandesImportCollection).appliquerDistante(demande);
    final service = ServiceDemandesImport(mere, donnees: () async => donnees, horloge: () => DateTime(2026, 11, 1));
    final n = await t.runAsync(() => service.traiter());
    expect(n, 1);
    final v = mere.collection(demandesImportCollection).parId('${demande['id']}')!;
    expect(v['etat'], demandeImportAppliquee, reason: '${v['resultatMotif']}');
    expect(v['lignes'], isEmpty, reason: 'aucune valeur de cellule ne reste à la demande');
    final ecrits = mere.collection('fournisseurs').actives.where((f) => f['lotImport'] == v['resultatLot']).toList();
    expect(ecrits.map((f) => f['code']).toSet(), {'CAME', 'LOCAL'});
    expect(ecrits.map((f) => '${f['id']}').toSet(), idsFileul, reason: 'une identité de ligne : la fiche de la mère remplace celle du fileul, elle ne la double pas');
    expect(ecrits.every((f) => f['validePar'] == donnees.matrice.libelle('stock') && !f.containsKey(champEnAttenteMere)), isTrue);
  });
}
