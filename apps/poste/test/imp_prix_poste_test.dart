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

/// LOT 8B, GROUPE PRIX AU POSTE : les tarifs et prix, et le catalogue de l'imagerie, sont portés. Les fichiers sont ceux que la maquette a écrits (`test/fixtures/import`), le magasin est
/// celui des vecteurs. Voie d'un fileul rattaché : des prix ne s'écrivent JAMAIS chez lui (une version est immuable, la mère seule l'écrit) ; il dépose une demande d'import vérifiée,
/// la mère refait les contrôles sous le rôle de l'auteur. Son Oui vaut proposition : la décision revient à la mère.
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

ProfilImport profil(String role, {bool fileul = false}) =>
    ProfilImport(role: role, libelleRole: role, matrice: donnees.matrice.matriceImport, libellesRoles: DemandesImportPoste.libellesDesRoles(donnees.matrice), fileul: fileul);

PortMagasin port(Magasin m, String role, String nom, {bool fileul = false}) => PortMagasin(m, aujourdhui: () => jour, nomAgent: nom, profil: profil(role, fileul: fileul));

DemandesImportPoste demandes(Magasin m, String role, String nom, {bool fileul = false, String etiquette = 'F'}) =>
    DemandesImportPoste(m, role: role, auteur: () => nom, matrice: donnees.matrice, aujourdhui: () => jour, etiquette: etiquette, fileulRattache: fileul);

List<Map<String, Object?>> versions(Magasin m, String code) => [for (final v in m.collection('versionsTarif').toutes) if (v['code'] == code) v];

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  group('la voie', () {
    test('QUAND : sur un fileul rattaché les prix se DEMANDENT (rien n\'est écrit chez lui) ; ailleurs ils s\'écrivent directement', () {
      VoieImportFileul voie(String j, {bool fileul = true}) => DemandesImportPoste.voie(fileulRattache: fileul, declaration: donnees.matrice.matriceImport.declaration(j));
      expect(voie('tarifs'), VoieImportFileul.demandeSeule);
      expect(voie('tarifs', fileul: false), VoieImportFileul.directe);
      expect(voie('catalogue-imagerie'), isNot(VoieImportFileul.reserveeALaMere), reason: 'le catalogue n\'est pas restreint');
      expect(DemandesImportPoste.reservesALaMere(fileulRattache: true, matrice: donnees.matrice.matriceImport), isNot(contains('tarifs')));
    });
  });

  group('la demande d\'un fileul, rejouée par la mère', () {
    test('le fileul vérifie sous son profil, ne pose AUCUNE version ; la mère refait les contrôles et crée des PROPOSITIONS sous le nom et le rôle de l\'auteur ; rejeu sans effet', () {
      final mf = magasin(), mm = magasin();
      final f = demandes(mf, 'stock', 'LE GESTIONNAIRE', fileul: true);
      final jeu = jeuImportParId('tarifs')!;
      final a = analyserLignes(jeu, lignesDuCas('ta-proposition'), 'ta-proposition.xlsx', port(mf, 'stock', 'LE GESTIONNAIRE', fileul: true));
      expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) p.code]}');
      final avant = mf.collection('versionsTarif').toutes.length;
      final dem = f.deposer(jeu, a);
      expect(mf.collection('versionsTarif').toutes.length, avant, reason: 'rien n\'est écrit chez le fileul');
      expect(dem['etat'], demandeImportEnAttente);
      // La mère reçoit la fiche par le pont, puis la traite.
      mm.collection(demandesImportCollection).inserer({...dem});
      final mere = demandes(mm, 'mere', 'Mère', etiquette: 'M');
      expect(mere.appliquerDemandes(), 1);
      final verdict = mm.collection(demandesImportCollection).parId(dem['id'])!;
      expect(verdict['etat'], demandeImportAppliquee, reason: '${verdict['resultatMotif']}');
      final mg = versions(mm, 'MG01').singleWhere((v) => v['origine'] == 'import'), nfs = versions(mm, 'NFS').singleWhere((v) => v['origine'] == 'import');
      for (final v in [mg, nfs]) {
        expect(v['statut'], 'propose');
        expect(v['proposePar'], 'LE GESTIONNAIRE');
        expect(v['proposeRole'], 'stock');
        expect(v['origine'], 'import');
      }
      expect(nfs['etatAssure'], 'manquant', reason: 'un tiret n\'est pas un zéro');
      expect([for (final j in mm.collection('audit').toutes) j['action']], contains('Changement de prix : proposition à l’import'));
      // Rejeu : la demande déjà traitée ne s'écrit pas deux fois.
      final n = mm.collection('versionsTarif').toutes.length;
      mm.collection(demandesImportCollection).mettreAJour(dem['id'], {'etat': demandeImportEnAttente});
      mere.appliquerDemandes();
      expect(mm.collection('versionsTarif').toutes.length, n, reason: 'un rejeu n\'écrit rien de plus');
    });

    test('un fileul qui DÉCIDE (direction) ne valide pas à distance : son Oui vaut proposition, à la vérification ET chez la mère ; le même fichier, importé par la mère, valide', () {
      final jeu = jeuImportParId('tarifs')!;
      final mf = magasin();
      final a = analyserLignes(jeu, lignesDuCas('ta-valide'), 'ta-valide.xlsx', port(mf, 'direction', 'LA DIRECTION', fileul: true));
      final codes = [for (final p in a.problemes) '${p.n}:${p.code}'];
      expect(codes, containsAll(['2:OUI_VAUT_PROPOSITION', '3:OUI_VAUT_PROPOSITION']), reason: 'une prestation CRÉÉE est dite « version 1 proposée » sans avertissement : le Oui ne change pas un prix en vigueur');
      final motif = a.problemes.firstWhere((p) => p.code == 'OUI_VAUT_PROPOSITION').motif;
      expect(motif, contains('ce poste est un fileul rattaché'), reason: 'la raison se DIT : ce n\'est pas le profil qui manque de droit');
      final mm = magasin();
      final dem = demandes(mf, 'direction', 'LA DIRECTION', fileul: true).deposer(jeu, a);
      mm.collection(demandesImportCollection).inserer({...dem});
      demandes(mm, 'mere', 'Mère', etiquette: 'M').appliquerDemandes();
      expect(mm.collection(demandesImportCollection).parId(dem['id'])!['etat'], demandeImportAppliquee);
      expect([for (final v in mm.collection('versionsTarif').toutes) if (v['origine'] == 'import') v['statut']], everyElement('propose'), reason: 'aucune version validée par un fileul');
      // La mère, elle, décide : le même fichier importé par la DAF écrit des versions validées.
      final m2 = magasin();
      final pm = port(m2, 'da', 'LA DAF');
      final r = appliquer(jeu, analyserLignes(jeu, lignesDuCas('ta-valide'), 'ta-valide.xlsx', pm), pm);
      expect(r.ok, isTrue, reason: '${r.motif}');
      expect([for (final v in m2.collection('versionsTarif').toutes) if (v['origine'] == 'import') v['statut']], everyElement('valide'));
    });

    test('la mère REFUSE en nommant quand le magasin a changé depuis la vérification du fileul (une proposition est déjà en attente) : rien n\'est écrit, le verdict revient', () {
      final jeu = jeuImportParId('tarifs')!;
      final mf = magasin(), mm = magasin();
      final a = analyserLignes(jeu, lignesDuCas('ta-proposition'), 'ta-proposition.xlsx', port(mf, 'stock', 'LE GESTIONNAIRE', fileul: true));
      final dem = demandes(mf, 'stock', 'LE GESTIONNAIRE', fileul: true).deposer(jeu, a);
      // Entre-temps, la mère a une proposition en attente sur MG01.
      mm.collection('versionsTarif').inserer({
        'id': 'MG01@2027-02-01@2', 'code': 'MG01', 'version': 2, 'dateEffet': '2027-02-01', 'prixNonAssure': 6000, 'prixAssure': 3500, 'etatAssure': 'montant', 'motif': 'x', 'statut': 'propose',
        'proposePar': 'AUTRE', 'proposeLe': '2026-10-31', 'proposeRole': 'da', 'origine': 'ecran'
      });
      final avant = mm.collection('versionsTarif').toutes.length;
      mm.collection(demandesImportCollection).inserer({...dem});
      demandes(mm, 'mere', 'Mère', etiquette: 'M').appliquerDemandes();
      final v = mm.collection(demandesImportCollection).parId(dem['id'])!;
      expect(v['etat'], demandeImportRefusee);
      expect(v['resultatCode'], isNotEmpty);
      expect(v['resultatMotif'], isNotEmpty);
      expect(v['resultatGeste'], isNotEmpty);
      expect(mm.collection('versionsTarif').toutes.length, avant, reason: 'rien n\'est écrit chez la mère');
    });
  });

  group('au poste de la mère : un prix validé fait la même suite qu\'un Oui à l\'écran', () {
    test('une version validée à la date du jour met la fiche de lecture au pas (projection) ', () {
      final jeu = jeuImportParId('tarifs')!;
      final lignes = [
        for (final l in lignesDuCas('ta-valide').take(2)) l,
      ];
      // MG01 : prix en vigueur AUJOURD'HUI (la date d'effet devient le jour de l'horloge du test).
      final idxDate = lignes.first.indexOf('Date d’effet');
      expect(idxDate, greaterThan(0));
      lignes[1][idxDate] = '2026-11-01';
      final m = magasin();
      final p = port(m, 'da', 'LA DAF');
      final r = appliquer(jeu, analyserLignes(jeu, lignes, 'x.xlsx', p), p);
      expect(r.ok, isTrue, reason: '${r.motif}');
      final avant = m.collection('actes').toutes.firstWhere((a) => a['code'] == 'MG01')['prix'];
      demandes(m, 'da', 'LA DAF', etiquette: 'M').apresImportDePrix(r.lot);
      final apres = m.collection('actes').toutes.firstWhere((a) => a['code'] == 'MG01')['prix'];
      expect(avant, isNull, reason: 'la fiche de lecture ne portait aucun prix avant la suite de la validation');
      expect(apres, 5500);
    });
  });

  group('l\'écran', () {
    testWidgets('MÈRE (DAF) : vérification, confirmation, versions validées d\'emblée ; un lot validé ne s\'annule plus', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-actes', role: 'da');
      await televerser(t, 'ta-valide');
      expect(find.textContaining('Analyse conforme.'), findsOneWidget);
      expect(find.byKey(const Key('imp-deposer-demande')), findsNothing, reason: 'la mère écrit, elle ne demande pas');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(versions(m, 'MG01').where((v) => v['statut'] == 'valide' && v['origine'] == 'import'), hasLength(1));
      expect(m.collection('tarifs').toutes.where((x) => x['code'] == 'CS-NEW'), hasLength(1));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('FILEUL rattaché : la page dit « ne s\'écrivent pas chez vous », la commande d\'écriture est ABSENTE, la demande part ; aucune version n\'est écrite', (t) async {
      final m = magasin();
      await rattacher(t, m);
      await ouvrir(t, m, 'imp-actes', role: 'stock');
      await televerser(t, 'ta-proposition');
      expect(find.textContaining('Des prix ne s’écrivent pas chez vous.'), findsOneWidget);
      expect(find.textContaining('Analyse conforme.'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'), findsNothing);
      expect(find.byKey(const Key('imp-importer-et-demander')), findsNothing);
      final avant = m.collection('versionsTarif').toutes.length;
      await toucher(t, find.byKey(const Key('imp-deposer-demande')));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Envoyer la demande'));
      await t.pump(const Duration(milliseconds: 300));
      expect(m.collection('versionsTarif').toutes.length, avant, reason: 'rien n\'est écrit chez le fileul');
      expect(m.collection(demandesImportCollection).toutes, hasLength(1));
      expect(find.textContaining('est partie à la mère'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('CATALOGUE DE L\'IMAGERIE : examens « à valider », écrits ; le même fichier rejoué est refusé (doublon du magasin)', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-catalogue-imagerie', role: 'da');
      await televerser(t, 'ci-valide');
      expect(find.byKey(const Key('imp-constat-A_VALIDER')), findsWidgets);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(m.collection('examensImagerie').toutes.where((x) => x['aValider'] == true), hasLength(2));
      await televerser(t, 'ci-valide');
      expect(find.byKey(const Key('imp-constat-DOUBLON_MAGASIN')), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });
  });
}
