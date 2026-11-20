import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LOT 8, droits d'import PAR JEU écrits au poste : « Rôles & permissions » règle, par rôle, trois cases par jeu (voir, importer, annuler). C'est la fiche `rbac` (`droitsImport`) que la maquette
/// écrit déjà et que le poste LISAIT seulement ; le moteur d'import relit le droit au moment d'écrire (masquer un bouton ne protège rien).
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  int rang(Magasin m, String role) {
    final actifs = [
      for (final r in m.collection('rolesBase').toutes)
        if (r['archive'] != true) '${r['id']}'
    ];
    return actifs.indexOf(role);
  }

  Future<void> ouvrirReglage(WidgetTester t, Magasin m, String role) async {
    await ouvrirM14(t, m, 'm14-roles');
    await toucherM14(t, find.byTooltip('Régler les importations').at(rang(m, role)));
    await t.pump(const Duration(milliseconds: 400));
  }

  bool coche(WidgetTester t, String cle) => t.getSemantics(find.byKey(Key(cle))).flagsCollection.isChecked == CheckedState.isTrue;

  Future<void> cliquer(WidgetTester t, String cle) async {
    await t.ensureVisible(find.byKey(Key(cle)));
    await t.pump();
    await t.tap(find.byKey(Key(cle)));
    await t.pump(const Duration(milliseconds: 200));
  }

  Fiche ficheRole(Magasin m, String role) => m.collection('rbac').toutes.firstWhere((x) => x['role'] == role);

  /// L'analyse d'un fichier de fournisseurs sous le rôle [role], avec la matrice EN FORCE (la matrice engendrée superposée aux fiches `rbac`) : le moteur lit le droit, jamais un nom de rôle.
  AnalyseImport analyseSous(Magasin m, String role) {
    final matrice = donneesNav.aChaud(m).matrice;
    final profil = ProfilImport(role: role, libelleRole: role, matrice: matrice.matriceImport);
    final c = (vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == 'fo-valide');
    final lignes = [
      for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
    ];
    return analyserLignes(jeuImportParId('fournisseurs')!, lignes, 'fo-valide.xlsx', PortMagasin(m, aujourdhui: () => DateTime(2026, 10, 30), nomAgent: 'AGENT TEST', profil: profil));
  }

  casM14('la fenêtre dit l\'origine (réglé / défaut du manifeste), « Non porté au poste » pour un jeu fermé, et part de l\'état en force', (t) async {
    final m = magasinM14();
    final sem = t.ensureSemantics();
    await ouvrirReglage(t, m, 'stock');
    expect(find.text('Importations du rôle « Gestionnaire de Stock »'), findsOneWidget);
    // Le gestionnaire de stock détient le Grand Stock (VIA) et les fournisseurs (VIA) d'origine, pas les patients.
    expect([coche(t, 'import:fournisseurs:voir'), coche(t, 'import:fournisseurs:importer'), coche(t, 'import:fournisseurs:annuler')], [true, true, true]);
    expect([coche(t, 'import:patients:voir'), coche(t, 'import:patients:importer'), coche(t, 'import:patients:annuler')], [false, false, false]);
    expect(find.text('défaut du manifeste'), findsWidgets);
    // Lot TFIN-2 : les vingt-neuf jeux de la maquette sont portés, plus aucun jeu n'est « Non porté au poste » (les deux derniers, prix d'achat et référentiel produits, le sont maintenant).
    expect(find.byKey(const Key('import:tarifs-produits:non-porte')), findsNothing, reason: 'le jeu des prix d\'achat est porté');
    expect(find.byKey(const Key('import:produits-referentiel:non-porte')), findsNothing, reason: 'le jeu du référentiel produits est porté');
    expect(find.byKey(const Key('import:fournisseurs:non-porte')), findsNothing);
    sem.dispose();
  });

  casM14('accorder « importer » : voir suit, seule la ligne touchée s\'écrit sur la fiche du rôle, l\'effet est AUSSITÔT dans le moteur', (t) async {
    final m = magasinM14();
    final sem = t.ensureSemantics();
    expect(analyseSous(m, 'agentadmin').droitRefuse, isTrue, reason: 'avant : le profil ne détient pas le jeu, le moteur refuse');
    await ouvrirReglage(t, m, 'agentadmin');
    expect(coche(t, 'import:fournisseurs:importer'), isFalse);
    await cliquer(t, 'import:fournisseurs:importer');
    expect(coche(t, 'import:fournisseurs:voir'), isTrue, reason: 'importer suppose voir');
    await toucherM14(t, find.byKey(const Key('import:enregistrer')));
    final ecrits = (ficheRole(m, 'agentadmin')['droitsImport'] as Map).cast<String, Object?>();
    expect(ecrits.keys, ['fournisseurs'], reason: 'seuls les jeux touchés sont écrits');
    expect(ecrits['fournisseurs'], {'voir': true, 'importer': true, 'annuler': false});
    expect(find.text('Droits d’importation enregistrés.'), findsOneWidget);
    expect(find.text('1 jeu(x) réglé(s), dont 1 à importer.'), findsOneWidget);
    final apres = analyseSous(m, 'agentadmin');
    expect(apres.droitRefuse, isFalse, reason: 'après : le droit en force est celui de la fiche');
    expect(apres.accepte, isTrue, reason: '${[for (final p in apres.problemes) p.code]}');
    expect(m.collection('audit').toutes.any((a) => '${a['action']}'.contains('Réglage des droits d’importation')), isTrue, reason: 'journalisé (RG-12)');
    sem.dispose();
  });

  casM14('une surcharge RESTREINT autant qu\'elle accorde : décocher « voir » retire importer et annuler, le moteur refuse', (t) async {
    final m = magasinM14();
    final sem = t.ensureSemantics();
    expect(analyseSous(m, 'stock').droitRefuse, isFalse, reason: 'avant : le gestionnaire détient le jeu d\'origine');
    await ouvrirReglage(t, m, 'stock');
    await cliquer(t, 'import:fournisseurs:voir');
    expect([coche(t, 'import:fournisseurs:voir'), coche(t, 'import:fournisseurs:importer'), coche(t, 'import:fournisseurs:annuler')], [false, false, false]);
    await toucherM14(t, find.byKey(const Key('import:enregistrer')));
    expect((ficheRole(m, 'stock')['droitsImport'] as Map)['fournisseurs'], {'voir': false, 'importer': false, 'annuler': false});
    final a = analyseSous(m, 'stock');
    expect(a.droitRefuse, isTrue);
    expect([for (final p in a.problemes) p.code], ['DROIT_IMPORT_REFUSE']);
    sem.dispose();
  });

  casM14('« Retirer les réglages d\'importation » rend chaque jeu au défaut du manifeste', (t) async {
    final m = magasinM14();
    final sem = t.ensureSemantics();
    await ouvrirReglage(t, m, 'stock');
    await cliquer(t, 'import:fournisseurs:voir');
    await toucherM14(t, find.byKey(const Key('import:enregistrer')));
    expect(analyseSous(m, 'stock').droitRefuse, isTrue);
    await toucherM14(t, find.byTooltip('Régler les importations').at(rang(m, 'stock')));
    await t.pump(const Duration(milliseconds: 400));
    await toucherM14(t, find.byKey(const Key('import:retirer')));
    expect(ficheRole(m, 'stock')['droitsImport'], isEmpty);
    expect(find.text('Réglages d’importation retirés.'), findsOneWidget);
    expect(analyseSous(m, 'stock').droitRefuse, isFalse);
    sem.dispose();
  });

  casM14('la commande « Régler les importations » est ABSENTE sans le droit d\'éditer l\'écran', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles', role: 'da', donnees: donneesLectureSeule('da', 'm14-roles'));
    expect(find.text('Rôles actifs'), findsOneWidget);
    expect(find.byTooltip('Régler les importations'), findsNothing);
  });
}
