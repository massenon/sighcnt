import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/cfg/cfa_commun.dart' show cfaPoserNavigation;
import 'package:sigh_poste/modules/dash/tbb_patient.dart' show ChronologieDash;

import 'aide_polices.dart';

/// Tableaux de bord « B » (ambulancier, aide-soignante, échographiste, surveillant, assistant de direction, chirurgien, anesthésiste, assistant
/// comptable, maternité, espace patient). Chaque écran est rejoué sur les vecteurs tirés de l'écran RÉEL de la maquette piloté dans Chrome
/// (`prototype_html/build/vecteurs-dash-b.js`), d'abord sur le jeu du poste, puis sur le jeu ENRICHI de fiches du jour (le jeu est daté d'août : la plupart
/// des compteurs « du jour » y valent 0 et ne prouveraient rien). Horloge : 30/10/2026 10 h, celle du pilote.
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 30, 10);
final v = (jsonDecode(File('../../packages/domaine/test/vecteurs/tbb_dash.json').readAsStringSync()) as Map).cast<String, Object?>();

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
String sp(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1200);
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

/// Le jeu du poste, avec (ou sans) les fiches synthétiques du jeu enrichi — les MÊMES que celles posées dans la maquette.
Magasin magasin({required bool enrichi}) {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  if (enrichi) {
    final ajouts = obj(v['_ajouts']);
    for (final n in ajouts.keys) {
      final col = m.collection(n);
      // La maquette AJOUTE en queue (`concat`) : l'ordre des fiches de test n'a pas d'incidence sur les compteurs, mais on le respecte.
      for (final f in liste(ajouts[n])) {
        col.inserer({...f});
      }
    }
  }
  return m;
}

String texteDe(Element e) {
  final w = e.widget;
  if (w is Text) return w.data ?? w.textSpan?.toPlainText() ?? '';
  return '';
}

List<String> textesSous(WidgetTester t, Finder f) => [
      for (final e in find.descendant(of: f, matching: find.byType(Text)).evaluate()) sp(texteDe(e))
    ].where((s) => s.isNotEmpty).toList();

String ligneRegard(WidgetTester t) => sp(texteDe(find.byKey(const Key('tbb:regard-ligne')).evaluate().single as Element));
String noteRegard(WidgetTester t) => sp(texteDe(find.byKey(const Key('tbb:regard-note')).evaluate().single as Element));

/// Les KPI affichés : (libellé, valeur, indice).
List<(String, String, String?)> kpisAffiches(WidgetTester t) {
  final out = <(String, String, String?)>[];
  for (final k in find.byKey(const Key('kit:kpi')).evaluate()) {
    final textes = [
      for (final e in find.descendant(of: find.byElementPredicate((x) => identical(x, k)), matching: find.byType(Text)).evaluate())
        sp(texteDe(e))
    ].where((s) => s.isNotEmpty).toList();
    out.add((textes[0], textes[1], textes.length > 2 ? textes[2] : null));
  }
  return out;
}

void verifierEcran(WidgetTester t, String id, M lu) {
  final pr = obj(lu['premier']);
  // 1. Le premier regard : sa phrase, sa note, et son lien — seulement quand quelque chose attend.
  expect(ligneRegard(t), pr['ligne'], reason: '$id : ligne du premier regard');
  expect(noteRegard(t), pr['note'], reason: '$id : note du premier regard');
  final lien = pr['lien'];
  final boutons = find.descendant(of: find.byKey(const Key('tbb:premier-regard')), matching: find.byType(BoutonSigh));
  if (lien == null) {
    expect(boutons, findsNothing, reason: '$id : rien n’attend, donc aucun lien');
  } else {
    expect(boutons, findsOneWidget);
    expect((boutons.evaluate().single.widget as BoutonSigh).libelle, obj(lien)['texte']);
  }
  // 2. Les indicateurs : libellé, valeur, indice.
  final attendus = liste(lu['kpis']);
  final obtenus = kpisAffiches(t);
  expect(obtenus.length, attendus.length, reason: '$id : nombre de KPI');
  for (var i = 0; i < attendus.length; i++) {
    expect(obtenus[i].$1, attendus[i]['label'], reason: '$id : libellé du KPI $i');
    expect(obtenus[i].$2, attendus[i]['valeur'], reason: '$id : valeur du KPI ${attendus[i]['label']}');
    expect(obtenus[i].$3, attendus[i]['indice'], reason: '$id : indice du KPI ${attendus[i]['label']}');
  }
  // 3. Les accès rapides : chaque raccourci de la maquette, avec son détail.
  for (final r in liste(lu['raccourcis'])) {
    expect(find.text('${r['libelle']}'), findsWidgets, reason: '$id : raccourci ${r['libelle']}');
    if (r['detail'] != null) expect(find.text('${r['detail']}'), findsWidgets);
  }
  // 4. Les parcours : titres, étapes, pastilles de poste, mention « fermé à votre profil », bouton de la première action.
  var fermees = 0;
  for (final p in liste(lu['parcours'])) {
    final c = find.byKey(Key('tbb:parcours:${p['titre']}'));
    expect(c, findsOneWidget, reason: '$id : parcours ${p['titre']}');
    final textes = textesSous(t, c);
    if (p['detail'] != null) expect(textes, contains(p['detail']));
    final bouton = p['bouton'];
    final bs = find.descendant(of: c, matching: find.byType(BoutonSigh));
    if (bouton == null) {
      expect(bs, findsNothing, reason: '$id : ${p['titre']} — première étape fermée, donc pas de bouton');
    } else {
      expect((bs.evaluate().single.widget as BoutonSigh).libelle, obj(bouton)['texte']);
    }
    for (final e in liste(p['etapes'])) {
      final label = '${e['label']}';
      expect(textes, contains(label), reason: '$id : étape $label');
      final spans = [for (final s in (e['spans'] as List)) '$s'];
      final ferme = spans.contains('— fermé à votre profil');
      final cliquable = find.ancestor(of: find.descendant(of: c, matching: find.byKey(Key('tbb:etape:$label'))), matching: find.byType(InkWell));
      // Une étape ouverte qui mène à un écran est un lien ; une étape fermée reste visible mais NON cliquable.
      if (e['ecran'] != null) {
        expect(cliquable, findsWidgets, reason: '$id : étape $label cliquable');
      } else if (ferme) {
        expect(cliquable, findsNothing, reason: '$id : étape $label fermée, donc non cliquable');
      }
      if (ferme) fermees++;
      for (final s in spans) {
        if (s != label && s != '— fermé à votre profil') expect(textes, contains(s), reason: '$id : pastille de poste « $s »');
      }
      if (e['detail'] != null) expect(textes, contains(e['detail']));
    }
  }
  expect(find.text('— fermé à votre profil').evaluate().length, fermees, reason: '$id : mentions « fermé à votre profil »');
  // 5. Les notes de périmètre.
  for (final n in (lu['notes'] as List)) {
    expect(find.byWidgetPredicate((w) => w is Text && w.data != null && sp(w.data!) == sp('$n')), findsOneWidget, reason: '$id : note');
  }
  // 6. Les tableaux : en-têtes, nombre de lignes, cellules.
  final tables = find.byType(MiniTableauSigh).evaluate().map((e) => e.widget as MiniTableauSigh).toList();
  final attT = liste(lu['tables']);
  expect(tables.length, attT.length, reason: '$id : nombre de tableaux');
  for (var i = 0; i < attT.length; i++) {
    expect([for (final c in tables[i].colonnes) c.libelle.toUpperCase()], [for (final h in (attT[i]['entetes'] as List)) '$h'], reason: '$id : en-têtes');
    final lignes = liste(attT[i]['lignes']);
    expect(tables[i].lignes.length, lignes.length, reason: '$id : lignes de ${attT[i]['titre']}');
    for (var r = 0; r < lignes.length; r++) {
      final cel = [for (final x in (lignes[r]['cellules'] as List)) sp('$x')];
      for (var k = 0; k < tables[i].colonnes.length; k++) {
        final valeur = sp(tables[i].colonnes[k].valeur(tables[i].lignes[r]));
        if (valeur.isEmpty) continue; // colonne rendue en pastille (statut) : le texte vit dans le widget
        expect(valeur, cel[k], reason: '$id : ${attT[i]['titre']} ligne $r colonne $k');
      }
    }
  }
  // 7. Les états vides énoncent une phrase.
  for (final x in (lu['vides'] as List)) {
    expect(find.text('${(x as List)[1]}'), findsOneWidget, reason: '$id : vide « ${x[0]} »');
  }
}

void main() {
  setUpAll(() {
    chargerPolices();
    cfaPoserNavigation(donnees);
  });
  tearDown(ToastsSigh.viderPourTests);

  // Écrans de la maquette → classe de test. Chaque tableau est ouvert sous son propre rôle ET sous l'administrateur (tout ouvert).
  final ecrans = [for (final id in v.keys) if (id.startsWith('dash-') && id != 'dash-patient') id];

  for (final enrichi in [false, true]) {
    for (final id in ecrans) {
      final role = obj(v[id])['_proprio'] as String;
      testWidgets('$id sous $role — ${enrichi ? 'jeu enrichi des fiches du jour' : 'jeu du poste'} = écran réel de la maquette', (t) async {
        final m = magasin(enrichi: enrichi);
        await ouvrir(t, m, id, role: role);
        verifierEcran(t, id, obj(obj(v[id])[enrichi ? '_enrichi' : role]));
        await t.pump(const Duration(seconds: 10));
      });
    }
  }

  for (final id in ecrans) {
    testWidgets('$id sous admin (tout est ouvert) : aucune étape fermée, le bouton de chaque parcours est là', (t) async {
      await ouvrir(t, magasin(enrichi: false), id);
      expect(find.text('— fermé à votre profil'), findsNothing, reason: '$id : l’administrateur système a tout ouvert');
      final lu = obj(obj(v[id])['admin']);
      for (final p in liste(lu['parcours'])) {
        final premiere = liste(p['etapes']).first;
        final c = find.byKey(Key('tbb:parcours:${p['titre']}'));
        expect(find.descendant(of: c, matching: find.byType(BoutonSigh)), premiere['ecran'] == null ? findsNothing : findsOneWidget);
      }
      await t.pump(const Duration(seconds: 10));
    });
  }

  testWidgets('le lien du premier regard mène à l’écran, et une étape fermée au profil ne mène nulle part', (t) async {
    final m = magasin(enrichi: true);
    await ouvrir(t, m, 'dash-ambulancier', role: 'ambulancier');
    // Étape fermée à l'ambulancier (la fiche de référence relève du médecin) : visible, non cliquable.
    expect(find.text('— fermé à votre profil'), findsNWidgets(2));
    await t.tap(find.text('Emporter la fiche de référence'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('tbb:premier-regard')), findsOneWidget, reason: 'on est resté sur le tableau de bord');
    // Le lien du premier regard (3 interventions demandées ou en cours) ouvre le registre des interventions.
    await t.tap(find.descendant(of: find.byKey(const Key('tbb:premier-regard')), matching: find.byType(BoutonSigh)));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('tbb:premier-regard')), findsNothing, reason: 'le registre des interventions est ouvert');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('à zéro le premier regard énonce sa phrase et n’a pas de lien (tous les partogrammes clos)', (t) async {
    final m = magasin(enrichi: false);
    // Sur le jeu : deux partogrammes ouverts ou plus ; on les clôt tous (un partogramme clos n'est plus une femme en salle de travail).
    for (final p in m.collection('partogrammes').actives) {
      m.collection('partogrammes').mettreAJour(p['id'], {'clos': true});
    }
    await ouvrir(t, m, 'dash-maternite', role: 'infirmier');
    expect(ligneRegard(t), 'Aucun travail en cours dans la salle d’accouchement.');
    expect(find.descendant(of: find.byKey(const Key('tbb:premier-regard')), matching: find.byType(BoutonSigh)), findsNothing);
    expect(find.text('Aucun travail en cours.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('maternité : un terme dépassé figure dans la fenêtre, en danger, et le tri va du plus ancien au plus proche', (t) async {
    final m = magasin(enrichi: false);
    await ouvrir(t, m, 'dash-maternite', role: 'infirmier');
    final tables = find.byType(MiniTableauSigh).evaluate().map((e) => e.widget as MiniTableauSigh).toList();
    final termes = tables[1].lignes;
    expect(termes.first['numeroDossier'], '00007/26');
    expect(find.text('dépassé de 44 j'), findsOneWidget);
    expect(find.text('dans 5 j'), findsOneWidget);
    // Les dossiers « suivi » seuls, et aucun terme au-delà de quinze jours.
    for (final d in termes) {
      expect(d['statutDossier'], 'suivi');
      expect(tbbJoursEntre(auj, DateTime.parse('${d['dpa']}')), lessThanOrEqualTo(15));
    }
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('dash-patient : sélecteur, indicateurs, parcours de soins et fiche remise = écran réel de la maquette', (t) async {
    final m = magasin(enrichi: false);
    await ouvrir(t, m, 'dash-patient', role: 'reception');
    final sel = obj(obj(v['dash-patient'])['_selection']);
    final ech = liste(sel['echantillon']);
    // Premier patient (par ordre de code) : le sélecteur est préposé.
    final premier = ech.first;
    expect(find.textContaining('Patient'), findsWidgets);
    expect(find.text('${obj(premier['patient'])['nom']} ${obj(premier['patient'])['prenom']}'), findsWidgets);
    void kpis(M e) {
      final k = kpisAffiches(t);
      final att = liste(e['kpis']);
      expect([for (final x in k) (x.$1, x.$2)], [for (final x in att) ('${x['label']}', sp('${x['valeur']}'))]);
    }

    kpis(premier);
    expect(find.text('Accès rapides'), findsOneWidget);
    for (final l in ['Répertoire des patients', 'Rendez-vous', 'Nouvelle facture', 'Documents du patient']) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('Parcours de soins'), findsOneWidget);
    // La chronologie : « motif — diagnostic », puis « type avec praticien », puis la date.
    final fil = sp('${premier['fil']}');
    final textes = textesSous(t, find.byType(ChronologieDash));
    expect(sp(textes.join(' ')), fil);
    // « Remettre la fiche » ouvre l'aperçu de la pièce, signée du Secrétaire Médical.
    await t.ensureVisible(find.text('Remettre la fiche'));
    await t.tap(find.text('Remettre la fiche'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Situation du patient'), findsWidgets);
    expect(find.text('Dossier ${obj(premier['patient'])['code']}'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('dash-patient : choisir un autre patient recalcule les indicateurs (reste à payer) et la fiche remise — écran réel de la maquette', (t) async {
    final m = magasin(enrichi: false);
    await ouvrir(t, m, 'dash-patient', role: 'reception');
    final ech = liste(obj(obj(v['dash-patient'])['_selection'])['echantillon']);
    // SAMBIENI Bibata : une hospitalisation et 7 950 F restant à payer.
    final cible = ech.firstWhere((e) => obj(e['patient'])['nom'] == 'SAMBIENI');
    final nom = '${obj(cible['patient'])['nom']} ${obj(cible['patient'])['prenom']}';
    await t.ensureVisible(find.byKey(const Key('kit:champ:patient')));
    await t.tap(find.descendant(of: find.byKey(const Key('kit:champ:patient')), matching: find.byType(InkWell)).first);
    await t.pump(const Duration(milliseconds: 300));
    if (find.text(nom).evaluate().isEmpty) {
      await t.enterText(find.byType(TextField).last, 'SAMBIENI');
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.tap(find.text(nom).last);
    await t.pump(const Duration(milliseconds: 400));
    final k = kpisAffiches(t);
    expect([for (final x in k) (x.$1, x.$2)], [for (final x in liste(cible['kpis'])) ('${x['label']}', sp('${x['valeur']}'))]);
    expect(k.last.$2, '7 950 FCFA', reason: 'le reste à payer est la somme des reliquats de SES factures');
    // La commande « Remettre la fiche » imprime SES consultations, la plus récente d'abord, avec son reste à payer en cartouche.
    await t.ensureVisible(find.text('Remettre la fiche'));
    await t.tap(find.text('Remettre la fiche'));
    await t.pump(const Duration(milliseconds: 500));
    final piece = obj(cible['piece']);
    expect(find.text('Dossier ${obj(cible['patient'])['code']}'), findsWidgets);
    for (final c in (piece['cartouche'] as List)) {
      final att = sp('${(c as List)[1]}');
      expect(find.byWidgetPredicate((w) => w is Text && w.data != null && sp(w.data!).contains(att)), findsWidgets, reason: 'cartouche ${c[0]}');
    }
    expect(find.textContaining('Paludisme simple'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });
}
