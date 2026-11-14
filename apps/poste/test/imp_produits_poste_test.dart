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

/// LOT TFIN-2, GROUPE PRODUITS AU POSTE : les prix d'achat par fichier et le référentiel produits sont portés (les deux dernières pages de jeu qui restaient fermées « Non porté au poste »). Les fichiers sont ceux que la maquette a écrits (`test/fixtures/import`), le magasin est
/// celui des vecteurs. Voie d'un fileul rattaché : des prix d'achat ne s'écrivent JAMAIS chez lui (une version est immuable, la mère seule l'écrit) ; il dépose une demande d'import
/// vérifiée, la mère refait les contrôles sous le rôle de l'auteur. Son Oui vaut proposition. Le référentiel produits écrit la fiche chez lui, la version 1 est celle de la mère.
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
    test('QUAND : sur un fileul rattaché les prix d\'achat se DEMANDENT (rien n\'est écrit chez lui) ; ailleurs ils s\'écrivent directement ; le référentiel produits n\'est pas restreint', () {
      VoieImportFileul voie(String j, {bool fileul = true}) => DemandesImportPoste.voie(fileulRattache: fileul, declaration: donnees.matrice.matriceImport.declaration(j));
      expect(voie('tarifs-produits'), VoieImportFileul.demandeSeule);
      expect(voie('tarifs-produits', fileul: false), VoieImportFileul.directe);
      expect(voie('produits-referentiel'), isNot(VoieImportFileul.reserveeALaMere));
      expect(jeuImportParEcran('imp-tarifs-produits')?.id, 'tarifs-produits', reason: 'la page est portée : plus de « Non porté au poste »');
      expect(jeuImportParEcran('imp-produits-referentiel')?.id, 'produits-referentiel');
    });
  });

  group('la demande d\'un fileul, rejouée par la mère', () {
    test('le fileul vérifie sous son profil, ne pose AUCUNE version ; la mère refait les contrôles et crée des PROPOSITIONS sous le nom et le rôle de l\'auteur ; rejeu sans effet (le verdict ne double jamais)', () {
      final mf = magasin(), mm = magasin();
      final f = demandes(mf, 'stock', 'LE GESTIONNAIRE', fileul: true);
      final jeu = jeuImportParId('tarifs-produits')!;
      final a = analyserLignes(jeu, lignesDuCas('tp-proposition'), 'tp-proposition.xlsx', port(mf, 'stock', 'LE GESTIONNAIRE', fileul: true));
      expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) p.code]}');
      final avant = mf.collection('versionsTarif').toutes.length;
      final dem = f.deposer(jeu, a);
      expect(mf.collection('versionsTarif').toutes.length, avant, reason: 'rien n\'est écrit chez le fileul');
      expect(dem['etat'], demandeImportEnAttente);
      mm.collection(demandesImportCollection).inserer({...dem});
      final mere = demandes(mm, 'mere', 'Mère', etiquette: 'M');
      expect(mere.appliquerDemandes(), 1);
      final verdict = mm.collection(demandesImportCollection).parId(dem['id'])!;
      expect(verdict['etat'], demandeImportAppliquee, reason: '${verdict['resultatMotif']}');
      for (final code in ['DOLIP', 'COTON']) {
        final v = versions(mm, code).singleWhere((v) => v['origine'] == 'import');
        expect([v['statut'], v['proposePar'], v['proposeRole']], ['propose', 'LE GESTIONNAIRE', 'stock'], reason: code);
      }
      final n = mm.collection('versionsTarif').toutes.length;
      mm.collection(demandesImportCollection).mettreAJour(dem['id'], {'etat': demandeImportEnAttente});
      mere.appliquerDemandes();
      expect(mm.collection('versionsTarif').toutes.length, n, reason: 'un rejeu n\'écrit rien de plus');
    });

    test('un fileul qui DÉCIDE (la Directrice Administrative) ne valide pas à distance : son Oui vaut proposition, à la vérification ET chez la mère', () {
      final jeu = jeuImportParId('tarifs-produits')!;
      final mf = magasin();
      final a = analyserLignes(jeu, lignesDuCas('tp-valide'), 'tp-valide.xlsx', port(mf, 'da', 'LA DAF', fileul: true));
      expect([for (final p in a.problemes) p.code], contains('OUI_VAUT_PROPOSITION'));
      expect(a.problemes.firstWhere((p) => p.code == 'OUI_VAUT_PROPOSITION').motif, contains('ce poste est un fileul rattaché'));
    });

    test('la mère REFUSE en nommant quand le magasin a changé depuis la vérification du fileul (une proposition est déjà en attente) : rien n\'est écrit, le verdict revient', () {
      final jeu = jeuImportParId('tarifs-produits')!;
      final mf = magasin(), mm = magasin();
      final a = analyserLignes(jeu, lignesDuCas('tp-proposition'), 'tp-proposition.xlsx', port(mf, 'stock', 'LE GESTIONNAIRE', fileul: true));
      final dem = demandes(mf, 'stock', 'LE GESTIONNAIRE', fileul: true).deposer(jeu, a);
      mm.collection('versionsTarif').inserer({
        'id': 'DOLIP@2027-02-01@2', 'code': 'DOLIP', 'version': 2, 'dateEffet': '2027-02-01', 'prixNonAssure': 400, 'etatAssure': 'unique', 'motif': 'x', 'statut': 'propose',
        'proposePar': 'AUTRE', 'proposeLe': '2026-10-31', 'proposeRole': 'da', 'origine': 'ecran'
      });
      final avant = mm.collection('versionsTarif').toutes.length;
      mm.collection(demandesImportCollection).inserer({...dem});
      demandes(mm, 'mere', 'Mère', etiquette: 'M').appliquerDemandes();
      final v = mm.collection(demandesImportCollection).parId(dem['id'])!;
      expect(v['etat'], demandeImportRefusee);
      expect([v['resultatCode'], v['resultatMotif'], v['resultatGeste']].every((x) => '$x'.isNotEmpty), isTrue, reason: 'un refus se nomme : code, motif, geste');
      expect(mm.collection('versionsTarif').toutes.length, avant, reason: 'rien n\'est écrit chez la mère');
    });
  });

  group('au poste de la mère : un prix d\'achat validé fait la même suite qu\'un Oui à l\'écran', () {
    test('une version validée à la date du jour met la FICHE du produit au pas de la version en vigueur (projection de ce seul article)', () {
      final jeu = jeuImportParId('tarifs-produits')!;
      final lignes = [for (final l in lignesDuCas('tp-valide').take(2)) l];
      final idxDate = lignes.first.indexOf('Date d’effet');
      lignes[1][idxDate] = '2026-11-01';
      final m = magasin();
      final p = port(m, 'da', 'LA DAF');
      final r = appliquer(jeu, analyserLignes(jeu, lignes, 'x.xlsx', p), p);
      expect(r.ok, isTrue, reason: '${r.motif}');
      expect(m.collection('produits').toutes.firstWhere((x) => x['code'] == 'DOLIP')['prixAchat'], 250, reason: 'avant la suite de la validation la fiche garde l\'ancien prix');
      demandes(m, 'da', 'LA DAF', etiquette: 'M').apresImportDePrix(r.lot);
      final dolip = m.collection('produits').toutes.firstWhere((x) => x['code'] == 'DOLIP');
      expect([dolip['prixAchat'], dolip['prixVente']], [300, 300], reason: 'RG-02 : médicament, vente = achat');
    });
  });

  group('l\'écran', () {
    testWidgets('MÈRE (DAF) : vérification, confirmation, versions validées d\'emblée ; un lot validé ne s\'annule plus', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-tarifs-produits', role: 'da');
      await televerser(t, 'tp-valide');
      expect(find.byKey(const Key('imp-deposer-demande')), findsNothing, reason: 'la mère écrit, elle ne demande pas');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(versions(m, 'DOLIP').where((v) => v['statut'] == 'valide' && v['origine'] == 'import'), hasLength(1));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('FILEUL rattaché : « ne s\'écrivent pas chez vous », la commande d\'écriture est ABSENTE, la demande part ; aucune version n\'est écrite', (t) async {
      final m = magasin();
      await rattacher(t, m);
      await ouvrir(t, m, 'imp-tarifs-produits', role: 'stock');
      await televerser(t, 'tp-proposition');
      expect(find.textContaining('Des prix ne s’écrivent pas chez vous.'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer l’importation (2 lignes)'), findsNothing);
      final avant = m.collection('versionsTarif').toutes.length;
      await toucher(t, find.byKey(const Key('imp-deposer-demande')));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Envoyer la demande'));
      await t.pump(const Duration(milliseconds: 300));
      expect(m.collection('versionsTarif').toutes.length, avant, reason: 'rien n\'est écrit chez le fileul');
      expect(m.collection(demandesImportCollection).toutes, hasLength(1));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('SANS le droit d\'importer les prix d\'achat : la commande d\'écriture est ABSENTE (le caissier n\'a même pas la page)', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-tarifs-produits', role: 'caissier');
      expect(find.widgetWithText(BoutonSigh, 'Téléverser un fichier (.xlsx ou .csv)'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('RÉFÉRENTIEL PRODUITS : trois articles créés sans stock, chacun avec sa version 1 ; le même fichier rejoué ne recrée rien (article déjà tenu)', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'imp-produits-referentiel', role: 'stock');
      await televerser(t, 'pf-valide');
      expect(find.byKey(const Key('imp-constat-SANS_SEUIL')), findsWidgets);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer l’importation (3 lignes)'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Écrire le lot'));
      await t.pump(const Duration(milliseconds: 300));
      expect(m.collection('produits').toutes.where((x) => '${x['code']}'.startsWith('NEW-')), hasLength(3));
      expect(m.collection('versionsTarif').toutes.where((v) => '${v['code']}'.startsWith('NEW-') && v['version'] == 1 && v['statut'] == 'valide'), hasLength(3));
      await televerser(t, 'pf-valide');
      expect(find.byKey(const Key('imp-constat-IGNORE_EXISTANT')), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });
  });
}
