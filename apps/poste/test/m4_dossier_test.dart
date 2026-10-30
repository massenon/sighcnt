import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Dossier obstétrical : l'ouverture par la PAGE (numéro de série annuelle, DPA déduite de la DDR, risque par cumul des facteurs, refus), la
/// modification en modale (le diabète coché s'ajoute, la DDR corrigée déplace la DPA) et la fiche à cinq feuillets — rejoués sur la maquette.
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final dossier = obj(obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_regles.json').readAsStringSync()))['dossier']);
final lect = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_lectures.json').readAsStringSync()));
final saisies = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_saisies.json').readAsStringSync()));
// L'âge est relevé sur l'horloge de la page au moment de la création : la maquette tournait le 30/10/2026.
final auj = DateTime(2026, 10, 30, 12);

String s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

ControleurFormulaire ctl(WidgetTester t, {bool dernier = true}) =>
    t.widget<FormulaireSigh>(dernier ? find.byType(FormulaireSigh).last : find.byType(FormulaireSigh).first).controleur;

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  cas('la page propose le numéro de série annuelle lu sur le registre (archivés compris, cinq chiffres)', (t) async {
    for (final sr in liste(dossier['series'])) {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      final col = m.collection('dossiersObstetricaux');
      for (final f in col.toutes.toList()) {
        col.archiver(f['id']);
        col.mettreAJour(f['id'], {'numeroDossier': null});
      }
      for (final (i, n) in (sr['numeros'] as List).cast<List>().indexed) {
        col.inserer({'id': 'X$i', 'numeroDossier': n[0], 'statut': n[1]});
      }
      await ouvrir(t, m, 'm4-dossier-obstetrical-nouveau');
      expect('${ctl(t)['numeroDossier']}', sr['propose'], reason: '${sr['nom']}');
    }
  });

  for (final cr in liste(dossier['creations'])) {
    cas('ouverture — ${cr['nom']}', (t) async {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      final col = m.collection('dossiersObstetricaux');
      final n0 = col.toutes.length;
      await ouvrir(t, m, 'm4-dossier-obstetrical-nouveau');
      final c = ctl(t);
      for (final e in obj(cr['saisie']).entries) {
        e.value is bool ? c.poser(e.key, e.value) : c.poser(e.key, '${e.value}');
      }
      await t.ensureVisible(find.widgetWithText(BoutonSigh, 'Ouvrir le dossier').last);
      await t.tap(find.widgetWithText(BoutonSigh, 'Ouvrir le dossier').last);
      await t.pump(const Duration(milliseconds: 500));
      final att = liste(cr['nouvelles']);
      if (att.isEmpty) {
        expect(col.toutes.length, n0, reason: 'refus : rien n\'est écrit');
        expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
        return;
      }
      expect(col.toutes.length, n0 + 1);
      final f = col.toutes.first, a = att.single;
      for (final k in ['numeroDossier', 'patient', 'patientCode', 'dpa', 'age', 'facteurs', 'ddr', 'gestite', 'parite', 'statutDossier', 'referee', 'refereePar']) {
        final x = f[k], y = a[k];
        expect(x is Map ? jsonEncode(x) == jsonEncode(y) : '$x' == '$y' || (x == null && (y == null || y == '')), isTrue, reason: '$k : $x / $y');
      }
      expect(find.text('Dossier obstétrical créé.'), findsOneWidget);
      // l'écran de retour est le registre
      expect(find.text('Tous les dossiers obstétricaux'), findsWidgets);
    });
  }

  cas('modification en modale : le cumul des facteurs et la DPA suivent', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    final col = m.collection('dossiersObstetricaux');
    final md = obj(dossier['modification']);
    await ouvrir(t, m, 'm4-dossier-obstetrical');
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, '00003/26');
    await t.pump(const Duration(milliseconds: 500));
    await t.ensureVisible(find.byTooltip('Modifier').first);
    await t.tap(find.byTooltip('Modifier').first);
    await t.pump(const Duration(milliseconds: 400));
    final c = ctl(t);
    final pre = {for (final p in (md['prerempli'] as List).cast<List>()) '${p[0]}': p[1]};
    expect('${c['facteur_age_max']}', '${pre['facteur_age_max']}');
    expect('${c['facteur_diabete']}', '${pre['facteur_diabete']}');
    c.poser('facteur_diabete', true);
    c.poser('ddr', '2026-03-01');
    await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
    await t.pump(const Duration(milliseconds: 500));
    final apres = col.toutes.firstWhere((x) => x['numeroDossier'] == '00003/26');
    final att = obj(md['apres']);
    expect(jsonEncode(apres['facteurs']), jsonEncode(att['facteurs']));
    expect(apres['dpa'], att['dpa']);
    expect(apres['numeroDossier'], '00003/26');
  });

  cas('la fiche : cinq feuillets, KPI et contenu', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm4-dossier-obstetrical');
    await t.tap(find.byTooltip('Consulter').first);
    await t.pump(const Duration(milliseconds: 500));
    final f = obj(dossier['fiche']);
    for (final k in liste(f['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == '${k['label']}'));
      // la fiche de la maquette est celle d'un dossier créé plus tôt dans la même séance : on contrôle la forme, pas la valeur
      expect(w.valeur.isNotEmpty, isTrue, reason: '${k['label']}');
    }
    for (final o in (f['onglets'] as List)) {
      expect(find.textContaining('$o'.split(' (').first), findsWidgets, reason: 'onglet $o');
    }
    for (final (i, o) in liste(f['parOnglet']).indexed) {
      final tab = find.textContaining('${(f['onglets'] as List)[i]}'.split(' (').first).first;
      await t.ensureVisible(tab);
      await t.tap(tab);
      await t.pump(const Duration(milliseconds: 300));
      for (final carte in (o['cartes'] as List).toSet()) {
        expect(find.text('$carte'), findsWidgets, reason: 'carte « $carte »');
      }
    }
  });

  cas('l\'ouverture est fermée à un profil qui lit sans écrire', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm4-dossier-obstetrical-nouveau', role: 'caissier');
    // le caissier n'a pas M4 : la coque refuse l'écran, la page n'expose aucun formulaire
    expect(find.widgetWithText(BoutonSigh, 'Ouvrir le dossier'), findsNothing);
  });
}
