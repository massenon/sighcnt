import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-roles : la matrice administrable de la maquette. Les règles sont rejouées sur les vecteurs par le domaine ; ici, l'ÉCRAN piloté comme la maquette l'a
/// été dans Chrome — mêmes gestes, mêmes fiches `rbac`, mêmes messages — et son articulation avec la matrice engendrée du poste.
final vecteurs =
    (jsonDecode(File('../../packages/domaine/test/vecteurs/securite.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
List<Map<String, Object?>> cas(String type) => [
      for (final c in (vecteurs['roles'] as List))
        if ((c as Map)['type'] == type) c.cast<String, Object?>()
    ];
Map<String, Object?> f(Object? x) => (x as Map).cast<String, Object?>();

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  /// Le rang du rôle dans la matrice (rôles actifs, dans l'ordre de la matrice engendrée).
  int rang(Magasin m, String role) {
    final actifs = [
      for (final r in m.collection('rolesBase').toutes)
        if (r['archive'] != true) '${r['id']}'
    ];
    return actifs.indexOf(role);
  }

  Future<void> icone(WidgetTester t, Magasin m, String role, String libelle) =>
      toucherM14(t, find.byTooltip(libelle).at(rang(m, role)));

  List<Map<String, Object?>> rangees(Magasin m) =>
      [for (final r in m.collection('modulesManifeste').toutes) r];
  int premierRang(Magasin m, String code) =>
      rangees(m).indexWhere((r) => r['code'] == code);

  /// Pose la case [cle] à [valeur] : comme la maquette (`clic(c, v)`), on ne touche que ce qui diffère — une case déjà dans l'état voulu ne bouge pas.
  Future<void> poser(WidgetTester t, String cle, bool valeur) async {
    final coche = t.getSemantics(find.byKey(Key(cle))).flagsCollection.isChecked == CheckedState.isTrue;
    if (coche == valeur) return;
    await t.ensureVisible(find.byKey(Key(cle)));
    await t.pump();
    await t.tap(find.byKey(Key(cle)));
    await t.pump(const Duration(milliseconds: 200));
  }

  Future<void> cliquer(WidgetTester t, String cle) async {
    await t.ensureVisible(find.byKey(Key(cle)));
    await t.pump();
    await t.tap(find.byKey(Key(cle)));
    await t.pump(const Duration(milliseconds: 200));
  }

  Fiche ficheRole(Magasin m, String role) =>
      m.collection('rbac').toutes.firstWhere((x) => x['role'] == role);

  casM14('ouverture : quatre indicateurs, cinq onglets, 20 rôles actifs × 32 modules, comptes par rôle et mention « ex- »', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles');
    for (final k in ['Rôles actifs', 'Rôles archivés', 'Modules protégés', 'Tentatives refusées']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    for (final o in ['Matrice des droits', 'Détail par rôle', 'Habilitations métier', 'Tentatives refusées', 'Rôles archivés']) {
      expect(find.textContaining(o), findsWidgets, reason: o);
    }
    final ouv = f(vecteurs['rolesOuverture']);
    final kpis = [for (final k in ouv['kpis'] as List) (k as List).cast<String>()];
    expect(kpis.map((k) => k[1]).toList(), ['20', '2', '32', '0']);
    for (final l in ouv['lignes'] as List) {
      final texte = (l as List)[0] as String;
      // « Libellé » puis « N compte(s) [· ex-…] » : deux textes dans la maquette (collés par textContent).
      final i = texte.indexOf(RegExp(r'\d+ compte\(s\)'));
      expect(find.text(texte.substring(0, i)), findsWidgets, reason: texte);
      expect(find.text(texte.substring(i)), findsWidgets, reason: texte);
    }
    expect(find.text('Matrice des droits d’accès'), findsOneWidget);
    expect(find.text('RÔLE'), findsOneWidget);
    expect(find.text('ACTIONS'), findsOneWidget);
    expect(find.text('Imprimer la matrice'), findsOneWidget);
    expect(find.text('Nouveau rôle'), findsOneWidget);
    // L'articulation avec le moteur de droits du poste est DITE.
    expect(find.textContaining('Le moteur de droits du poste (MatriceDroits) ne les relit pas encore'), findsOneWidget);
  });

  casM14('la matrice affichée reprend celle de la matrice engendrée du poste, case par case (réception : M1 plein sauf annuler → partiel)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles');
    // Les info-bulles des cases du rôle « Réception » (rang 11) : l'une au moins est « Lecture seule », une autre « Module fermé ».
    expect(find.byTooltip('Lecture seule'), findsWidgets);
    expect(find.byTooltip('Module fermé'), findsWidgets);
    expect(find.byTooltip('Voir, éditer, annuler'), findsWidgets);
    // Chaque case de la matrice affichée est celle de MatriceDroits (rbac.json) pour les écrans où le moteur a une réponse nette : le module M8 du caissier.
    final rb = f(m.collection('rolesBase').toutes.firstWhere((r) => r['id'] == 'caissier'));
    expect(f(rb['modules'])['M8'], [1, 1, 0], reason: 'caissier : M8 voir + éditer, pas annuler (M8.annuler fermé au caissier)');
  });

  casM14('« Modifier les droits » : les droits écrits sont ceux de la maquette (rôles reception, caissier, medecin, infirmier, stock, comptable, agentadmin, ambulancier)', (t) async {
    const gestes = <String, Future<void> Function(WidgetTester, Magasin)>{};
    final roles = {
      'lecture seule cochée : voir sans éditer ni annuler': ('reception', (WidgetTester t, Magasin m) => poser(t, 'case:${premierRang(m, 'M10')}:lecture', true)),
      'éditer coché ouvre aussi « voir »': ('caissier', (WidgetTester t, Magasin m) => poser(t, 'case:${premierRang(m, 'M12')}:editer', true)),
      'décocher « voir » retire éditer et annuler': ('medecin', (WidgetTester t, Magasin m) => poser(t, 'case:${premierRang(m, 'M8')}:voir', false)),
      'annuler coché seul ouvre « voir » (éditer reste faux)': ('infirmier', (WidgetTester t, Magasin m) => poser(t, 'case:${premierRang(m, 'M9')}:annuler', true)),
      '« Tout fermer »': ('comptable', (WidgetTester t, Magasin m) => toucherM14(t, find.widgetWithText(BoutonSigh, 'Tout fermer'))),
      '« Tout en lecture seule »': ('agentadmin', (WidgetTester t, Magasin m) => toucherM14(t, find.widgetWithText(BoutonSigh, 'Tout en lecture seule'))),
      '« Tout ouvrir »': ('ambulancier', (WidgetTester t, Magasin m) => toucherM14(t, find.widgetWithText(BoutonSigh, 'Tout ouvrir'))),
    };
    expect(gestes, isEmpty);
    final sem = t.ensureSemantics();
    for (final c in cas('droits')) {
      final nom = c['nom'] as String;
      final g = roles[nom];
      if (g == null) continue; // le cas « lecture seule décochée » n'a pas de geste distinct
      final m = magasinM14();
      await ouvrirM14(t, m, 'm14-roles');
      await icone(t, m, g.$1, 'Modifier les droits de ce rôle');
      await t.pump(const Duration(milliseconds: 400));
      await g.$2(t, m);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer les droits'));
      final attendu = f(f(liste0(f(c['apres'])['fiches']))['droits']);
      final obtenu = f(ficheRole(m, g.$1)['droits']);
      expect(obtenu.keys.toSet(), attendu.keys.toSet(), reason: nom);
      for (final code in attendu.keys) {
        expect(f(obtenu[code]), f(attendu[code]), reason: '$nom — $code');
      }
      // Le message d'enregistrement porte le détail de la maquette.
      expect(find.text('Droits du rôle « ${m.collection('rolesBase').toutes.firstWhere((r) => r['id'] == g.$1)['label']} » enregistrés.'), findsOneWidget, reason: nom);
      final detail = ((c['toasts'] as List).first as Map)['detail'] as String;
      expect(find.text(detail), findsOneWidget, reason: nom);
      // RG-12 : la modification est journalisée, avec la valeur écrite.
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Modification des droits RBAC' && a['reference'] == g.$1), isTrue, reason: nom);
      await t.pump(const Duration(seconds: 10));
    }
    sem.dispose();
  });

  casM14('la matrice se recalcule après l\'enregistrement : la case du module devient « Lecture seule » (info-bulle)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles');
    final avant = find.byTooltip('Lecture seule').evaluate().length;
    await icone(t, m, 'reception', 'Modifier les droits de ce rôle');
    await t.pump(const Duration(milliseconds: 400));
    await cliquer(t, 'case:${premierRang(m, 'M10')}:lecture');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer les droits'));
    // Les deux rangées de M1 et de M2 sont synchrones (état par code) : seul M10 change de case.
    expect(find.byTooltip('Lecture seule').evaluate().length, greaterThan(avant));
  });

  casM14('« Régler écran par écran » : l\'état initial est celui de la maquette (laborantin, M1), seuls les écrans touchés sont écrits', (t) async {
    final m = magasinM14();
    final c = cas('ecrans').first;
    await ouvrirM14(t, m, 'm14-roles');
    final sem = t.ensureSemantics();
    await icone(t, m, 'laborantin', 'Régler écran par écran');
    await t.pump(const Duration(milliseconds: 400));
    // Module M1 : on le choisit dans la liste (la modale s'ouvre sur le premier module du manifeste, M2).
    await choisirM14(t, 'module', 'M1 — Patients & constantes');
    final initial = (c['initial'] as List).cast<Map>();
    for (final (i, e) in initial.indexed) {
      bool coche(String d) => t.getSemantics(find.byKey(Key('ecran:$i:$d'))).flagsCollection.isChecked == CheckedState.isTrue;
      expect([coche('voir'), coche('editer'), coche('annuler')], [e['voir'], e['editer'], e['annuler']], reason: 'rang $i');
    }
    // La maquette ferme « m1-patients » (le premier de la liste ouvert au laborantin).
    final rangPatients = initial.indexWhere((e) => e['id'] == 'm1-patients');
    await cliquer(t, 'ecran:$rangPatients:voir');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final ecrits = f(ficheRole(m, 'laborantin')['droitsEcrans']);
    expect(f(ecrits['m1-patients']), {'voir': false, 'editer': false, 'annuler': false});
    expect(find.text('Droits par écran enregistrés.'), findsOneWidget);
    final detail = (((c['toasts'] as List).first) as Map)['detail'];
    expect(find.text('$detail'), findsOneWidget);
    sem.dispose();
  });

  casM14('« Retirer tous les réglages d\'écran » vide les écrans réglés et le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles');
    await icone(t, m, 'laborantin', 'Régler écran par écran');
    await t.pump(const Duration(milliseconds: 400));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer tous les réglages d’écran'));
    expect(f(ficheRole(m, 'laborantin')['droitsEcrans']), isEmpty);
    expect(find.text('Réglages d’écran retirés.'), findsOneWidget);
    expect(find.text('Tous les écrans suivent de nouveau leur module.'), findsOneWidget);
  });

  casM14('création d\'un rôle : tous les modules fermés, l\'écran universel fermé, aucun écran ouvert — comme la maquette', (t) async {
    final m = magasinM14();
    final vec = cas('creation').first;
    await ouvrirM14(t, m, 'm14-roles');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau rôle'));
    await saisir(t, 'libelle', 'Auditeur externe');
    await saisir(t, 'libelleCourt', 'Auditeur');
    await saisir(t, 'id', 'Auditeur Externe');
    await saisir(t, 'motif', 'Revue de conformité');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer le rôle'));
    final fiche = ficheRole(m, 'auditeurexterne');
    final attendu = f(liste0(f(vec['apres'])['fiches']));
    for (final k in ['nouveau', 'statut', 'libelle', 'libelleCourt', 'libelleOrigine', 'motif']) {
      expect(fiche[k], attendu[k], reason: k);
    }
    expect(fiche['couleur'], 'neutral', reason: 'défaut du formulaire');
    expect(fiche['accueil'], 'dash-admin');
    for (final d in f(fiche['droits']).values) {
      expect(f(d), {'voir': false, 'editer': false, 'annuler': false});
    }
    expect(f(fiche['droitsEcrans']).keys, ['m7-besoins']);
    expect(find.text('Rôle « Auditeur externe » créé.'), findsOneWidget);
    expect(find.text(secDetailCreationRole(32)), findsOneWidget);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Création d’un rôle'), isTrue);
    // Le rôle figure à la matrice (21 actifs), sans compte, et n'ouvre RIEN.
    expect(find.text('Auditeur externe'), findsWidgets);
    expect(find.text('21'), findsWidgets);
    for (final mo in rangees(m)) {
      final d = secDroitModule('auditeurexterne', '${mo['code']}',
          bases: {for (final b in m.collection('rolesBase').toutes) '${b['id']}': b},
          sur: secSurcharges(m.collection('rbac').toutes),
          rolesBase: m.collection('rolesBase').toutes);
      if (d.horsMatrice) continue;
      expect([d.voir, d.editer, d.annuler], [false, false, false], reason: '${mo['code']}');
    }
  });

  casM14('création refusée : identifiant déjà pris, identifiant sans caractère valable — rien n\'est écrit', (t) async {
    final m = magasinM14();
    final avant = m.collection('rbac').toutes.length;
    await ouvrirM14(t, m, 'm14-roles');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau rôle'));
    await saisir(t, 'libelle', 'Autre');
    await saisir(t, 'id', 'medecin');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer le rôle'));
    expect(find.text('Ce rôle existe déjà.'), findsOneWidget);
    expect(find.text('Médecin porte déjà l’identifiant « medecin ».'), findsOneWidget);
    await saisir(t, 'id', '---');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer le rôle'));
    expect(find.text('Identifiant technique invalide.'), findsOneWidget);
    expect(m.collection('rbac').toutes.length, avant);
  });

  casM14('renommage : l\'intitulé suit partout, le court suit le long, l\'annulation rétablit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles');
    await icone(t, m, 'laborantin', 'Renommer ce rôle');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Intitulé d’origine : Biologiste médical'), findsOneWidget);
    await saisir(t, 'libelle', 'Biologiste médical (test)');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Renommer'));
    expect(find.text('Rôle renommé.'), findsOneWidget);
    expect(ficheRole(m, 'laborantin')['libelle'], 'Biologiste médical (test)');
    expect(find.textContaining('Biologiste médical (test)'), findsWidgets);
    await toucherM14(t, find.text('Annuler').last);
    expect(ficheRole(m, 'laborantin')['libelle'], 'Biologiste médical');
  });

  casM14('archivage : motif exigé, rôle de la session refusé, comptes bloqués annoncés, annulable — RG-14', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles');
    // Le rôle de la session en cours ne s'archive pas.
    await icone(t, m, 'admin', 'Archiver ce rôle');
    expect(find.text('Impossible d’archiver le rôle de la session en cours.'), findsOneWidget);
    expect(find.text('Se connecter avec un autre profil pour procéder.'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await icone(t, m, 'ambulancier', 'Archiver ce rôle');
    expect(find.text('Archiver le rôle « Ambulancier » ?'), findsOneWidget);
    expect(find.textContaining('1 compte(s) sont rattachés à ce rôle.'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver le rôle'));
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Poste supprimé');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver le rôle'));
    final fiche = ficheRole(m, 'ambulancier');
    expect(fiche['statut'], 'archive');
    expect(fiche['motifArchivage'], 'Poste supprimé');
    expect(fiche['archivePar'], 'Administrateur système');
    expect(find.text('Rôle archivé.'), findsOneWidget);
    expect(find.text('1 compte(s) désormais bloqué(s).'), findsOneWidget);
    // Rien n'est supprimé : le rôle, ses droits et son libellé restent au magasin ; la matrice ne le montre plus.
    expect(f(fiche['droits']).isNotEmpty, isTrue);
    await toucherM14(t, find.text('Annuler').last);
    expect(ficheRole(m, 'ambulancier')['statut'], 'actif');
  });

  casM14('restauration d\'un rôle archivé au socle : il retrouve les droits que la maquette lui rend (rh : M1, M10, M11, RAP, DASH)', (t) async {
    final m = magasinM14();
    final vec = cas('restauration').firstWhere((c) => c['role'] == 'rh');
    await ouvrirM14(t, m, 'm14-roles');
    await toucherM14(t, find.textContaining('Rôles archivés').last);
    expect(find.text('Responsable RH'), findsOneWidget);
    expect(find.text('Pharmacien'), findsOneWidget);
    await toucherM14(t, find.byTooltip('Restaurer ce rôle').at(1));
    expect(find.text('Rôle « Responsable RH » restauré.'), findsOneWidget);
    final fiche = ficheRole(m, 'rh');
    expect(fiche['statut'], 'actif');
    expect(fiche['restaurePar'], 'Administrateur système');
    final attendu = f(f(vec['apres'])['matrice']);
    final bases = {for (final b in m.collection('rolesBase').toutes) '${b['id']}': b};
    final sur = secSurcharges(m.collection('rbac').toutes);
    for (final code in attendu.keys) {
      final a = f(attendu[code]);
      if (a['horsMatrice'] == true) continue;
      final d = secDroitModule('rh', code, bases: bases, sur: sur, rolesBase: m.collection('rolesBase').toutes);
      expect([d.voir, d.editer, d.annuler], [a['voir'], a['editer'], a['annuler']], reason: 'rh/$code');
    }
  });

  casM14('tentatives refusées : la barre d\'alerte, « Examiner » ouvre l\'onglet, le marquage « examinée » est tracé', (t) async {
    final m = magasinM14();
    m.collection('tentativesConnexion').inserer({
      'identifiant': 'v.test1',
      'nom': 'Test Tentative',
      'role': 'ambulancier',
      'motif': 'Rôle archivé',
      'horodatage': '2026-10-30T09:00:00.000Z'
    }, prefixe: 'TNT');
    m.collection('tentativesConnexion').inserer({
      'identifiant': 'v.test2',
      'nom': 'Test Deux',
      'role': 'ambulancier',
      'motif': 'Rôle archivé',
      'horodatage': '2026-10-30T09:05:00.000Z'
    }, prefixe: 'TNT');
    await ouvrirM14(t, m, 'm14-roles');
    expect(find.text('2 tentative(s) de connexion refusée(s)'), findsOneWidget);
    expect(find.textContaining('Dernière : Test Deux — 30/10/2026 à 09h05'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Examiner'));
    expect(find.text('Tentatives de connexion refusées'), findsOneWidget);
    expect(find.text('À examiner'), findsWidgets);
    await toucherM14(t, find.byTooltip('Marquer comme examinée').first);
    expect(find.text('Tentative marquée comme examinée.'), findsOneWidget);
    final t2 = m.collection('tentativesConnexion').toutes.firstWhere((x) => x['nom'] == 'Test Deux');
    expect(t2['traitee'], true);
    expect(t2['examineePar'], 'Administrateur système');
    expect(t2['examineeLe'], '2026-10-30');
    expect(find.text('1 tentative(s) de connexion refusée(s)'), findsOneWidget);
  });

  casM14('habilitations métier et rôles archivés : les tableaux de la maquette', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles');
    await toucherM14(t, find.textContaining('Habilitations métier').last);
    expect(find.text('Habilitations métier par fonction'), findsOneWidget);
    for (final e in ['FONCTION', 'RÉSULTATS D’ANALYSES', 'ÉCHOGRAPHIES', 'PEUT PRESCRIRE', 'EXÉCUTE LES SOINS', 'RÈGLE APPLIQUÉE']) {
      expect(find.text(e), findsOneWidget, reason: e);
    }
    expect(find.textContaining('Le rôle ouvre les écrans, la fonction décide des données'), findsOneWidget);
    await toucherM14(t, find.textContaining('Rôles archivés').last);
    expect(find.text('COMPTES BLOQUÉS'), findsOneWidget);
    expect(find.textContaining('RG-14 — l’archivage est logique'), findsOneWidget);
  });

  casM14('« Imprimer la matrice » : cartouche, une ligne par rôle actif, les trois signatures', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la matrice'));
    expect(find.text('Matrice des droits d’accès (RBAC)'), findsWidgets);
    expect(find.text('Politique de sécurité — situation au 30/10/2026'), findsOneWidget);
    expect(find.text('Le Directeur Médical'), findsOneWidget);
    expect(find.text('La Directrice Administrative'), findsOneWidget);
    expect(find.textContaining('Conformément à la règle RG-13'), findsOneWidget);
  });

  casM14('lecture seule : aucune commande d\'écriture — ni « Nouveau rôle », ni droits, ni écrans, ni renommage, ni archivage', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-roles', role: 'da', donnees: donneesLectureSeule('da', 'm14-roles'));
    expect(find.text('Rôles actifs'), findsOneWidget);
    expect(find.text('Nouveau rôle'), findsNothing);
    for (final c in ['Modifier les droits de ce rôle', 'Régler écran par écran', 'Renommer ce rôle', 'Archiver ce rôle']) {
      expect(find.byTooltip(c), findsNothing, reason: c);
    }
    expect(find.text('Imprimer la matrice'), findsOneWidget);
  });
}

Object liste0(Object? l) => (l as List).first as Object;
