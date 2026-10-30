import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m5/res_comparatif.dart';
import 'package:sigh_poste/modules/m5/res_impression.dart';
import 'package:sigh_poste/modules/m5/res_resultats.dart';
import 'package:sigh_poste/modules/m5/res_stats.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

/// Le résultat d'analyse du laboratoire, ÉCRAN PAR ÉCRAN, contre les vecteurs tirés de la maquette en marche
/// (`packages/domaine/test/vecteurs/resultats.json`, engendré par `prototype_html/build/vecteurs-resultats.js`) : mêmes fiches en entrée, mêmes
/// profils, ce que l'agent lit à l'écran est comparé à ce que la maquette a affiché. Les règles sont rejouées une fois de plus par
/// `packages/domaine/test/res_labo_test.dart` ; ici, les COMPORTEMENTS (verrous, refus nommés, rectification, impression conditionnée).
Map<String, Object?> vecteurs() => (jsonDecode(
        File('../../packages/domaine/test/vecteurs/resultats.json').readAsStringSync())
    as Map)
    .cast<String, Object?>();

List<Fiche> liste(Object? v) =>
    [for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()];

/// 30 octobre 2026 : le jour où les vecteurs ont été tirés (l'âge et les « 30 derniers jours » en dépendent).
final auj = DateTime(2026, 10, 30, 12);

/// Le jeu sobre (référentiels du laboratoire, personnel, patients) + les fiches des vecteurs, dans l'ordre où la maquette les tenait.
Magasin magasin(Map<String, List<Fiche>> surcharges) {
  const dossier = 'test/fixtures/jeu_sobre';
  final jeux = <String, Iterable<Fiche>>{
    for (final nom in Magasin.collectionsDuJeu)
      nom: liste(jsonDecode(File('$dossier/$nom.json').readAsStringSync())),
    ...surcharges,
  };
  return Magasin(jeux, 'POSTE', {
    ...(jsonDecode(File('$dossier/referentiels.json').readAsStringSync()) as Map)
        .cast<String, Object?>()
  });
}

Future<void> monter(WidgetTester t, Magasin m, Widget ecran,
    {String role = 'direction', String utilisateur = 'DIR TEST'}) async {
  t.view.physicalSize = const Size(2600, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  m.utilisateur = utilisateur;
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ContexteEcran(
              ecranId: 'm5-test',
              role: role,
              droit: const Droit(voir: true, editer: true, annuler: true),
              magasin: m,
              aller: (_) {},
              utilisateur: utilisateur,
              horloge: () => auj,
              child: SingleChildScrollView(child: ecran)))));
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> onglet(WidgetTester t, String id) async {
  final f = find.byKey(Key('kit:onglet:$id'));
  await toucher(t, f);
}

Future<void> choisir(WidgetTester t, String nom, String cible) async {
  await toucher(
      t,
      find.descendant(
          of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

String norm(Object? s) => '${s ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();

/// La valeur affichée d'un indicateur.
String kpi(WidgetTester t, String libelle) {
  final c = find.byWidgetPredicate((w) => w is Semantics && w.properties.label?.startsWith('$libelle : ') == true);
  final lab = c.evaluate().map((e) => (e.widget as Semantics).properties.label!).first;
  return lab.substring(libelle.length + 3);
}

/// Les références affichées dans l'ordre vertical.
List<String> affichees(WidgetTester t, Iterable<String> refs) {
  final l = <(double, String)>[];
  for (final r in refs) {
    final f = find.text(r);
    if (f.evaluate().isNotEmpty) l.add((t.getTopLeft(f.first).dy, r));
  }
  l.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final x in l) x.$2];
}

String refDe(Object? cellule0) =>
    RegExp(r'^LAB-\d{5}').firstMatch('$cellule0')!.group(0)!;

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);
  final v = vecteurs();
  final entrees = (v['entrees'] as Map).cast<String, Object?>();

  Magasin jeuResultats() => magasin({
        'demandesAnalyses': liste((entrees['resultats'] as Map)['demandes']),
        'factures': const [],
        'plagesReactif': const [],
      });

  // --- m5-resultats : l'écran lu sous chaque profil ------------------------------------------------------------------------------------------
  group('m5-resultats : ce que chaque profil lit (vecteurs)', () {
    for (final c in liste(v['resultats'])) {
      final s = (c['session'] as Map).cast<String, Object?>();
      final plage = (c['plage'] as Map).cast<String, Object?>();
      cas('${c['profil']} / ${plage['nom']}', (t) async {
        final m = jeuResultats();
        await monter(
            t,
            m,
            EcranResultats(
                fonction: s['fonction'] as String?,
                secteur: s['secteur'] as String?,
                agentId: s['id'] as String?,
                du: '${plage['du']}',
                au: '${plage['au']}'),
            role: '${s['role']}',
            utilisateur: '${s['nom']}');
        final kp = liste(c['kpis']);
        for (final k in kp) {
          expect(kpi(t, '${k['libelle']}'), k['valeur'], reason: '${k['libelle']}');
        }
        // Les onglets portent leur compte.
        final ongs = (c['onglets'] as List).cast<String>();
        for (final (i, id) in ['attente', 'relecture', 'valides'].indexed) {
          final f = find.byKey(Key('kit:onglet:$id${i == 0 ? ':actif' : ''}'));
          expect(f, findsOneWidget, reason: id);
          final nombre = RegExp(r'(\d+)$').firstMatch(ongs[i])!.group(1);
          expect(find.descendant(of: f, matching: find.text(nombre!)), findsOneWidget,
              reason: 'compte de ${ongs[i]}');
        }
        // Les notes de restriction (« une restriction s'annonce »).
        for (final n in (c['notes'] as List).cast<String>()) {
          expect(find.textContaining(norm(n).substring(0, 60)), findsWidgets, reason: n);
        }
        final toutesRefs = liste(m.collection('demandesAnalyses').actives).map((d) => '${d['reference']}');
        final tabs = liste(c['tableaux']);
        for (final (i, id) in ['attente', 'relecture', 'valides'].indexed) {
          if (i > 0) await onglet(t, id);
          final lignes = liste(tabs[i]['lignes']);
          final attendu = [for (final l in lignes) refDe((l['cellules'] as List).first)];
          expect(affichees(t, toutesRefs), attendu, reason: 'lignes de l\'onglet $id');
          for (final l in lignes) {
            final ref = refDe((l['cellules'] as List).first);
            final b = liste(l['boutons']);
            if (i == 0) {
              expect(find.byKey(Key('res:saisir-verrou:$ref')).evaluate().isNotEmpty, b.first['verrou'], reason: ref);
              expect(find.byKey(Key('res:saisir:$ref')).evaluate().isNotEmpty, !(b.first['verrou'] as bool), reason: ref);
            } else if (i == 1) {
              expect(find.byKey(Key('res:verrou-relecture:$ref')).evaluate().isNotEmpty, b.first['verrou'], reason: ref);
              expect(find.byKey(Key('res:relire:$ref')).evaluate().isNotEmpty, !(b.first['verrou'] as bool), reason: ref);
              expect(find.byKey(Key('res:valider-bio:$ref')).evaluate().isNotEmpty, b.length == 2, reason: ref);
              if (b.length == 2) {
                expect(find.widgetWithText(BoutonSigh, '${b.last['lib']}'), findsWidgets);
              }
            } else {
              expect(find.byKey(Key('res:compte-rendu:$ref')), findsOneWidget);
            }
          }
        }
      });
    }
  });

  // --- La modale de saisie, contre la maquette pilotée ----------------------------------------------------------------------------------------
  group('m5-resultats : la saisie structurée (vecteurs)', () {
    for (final c in liste(v['saisie'])) {
      cas('${c['nom']}', (t) async {
        final d = {...(c['demande'] as Map).cast<String, Object?>(), 'id': 'DSAISIE', 'statut': 'actif'};
        final m = magasin({
          'demandesAnalyses': [d],
          'plagesReactif': liste((entrees['comparatif'] as Map)['plages']),
        });
        await monter(t, m, const EcranResultats(fonction: 'biologiste', agentId: 'AG1'),
            role: 'laborantin', utilisateur: 'KINNOU Ganiou');
        await toucher(t, find.byKey(Key('res:saisir:${d['reference']}')));
        if (c['ouverte'] != true) {
          expect(find.text('Aucune variable paramétrée pour cet examen.'), findsOneWidget);
          expect(find.textContaining('Définir ses variables à l’écran « Valeurs de référence »'), findsOneWidget);
          return;
        }
        expect(find.text('${c['titre']}'), findsOneWidget);
        final examen = '${c['nom']}'.contains('VIH') ? 'VIH' : 'NFS';
        final vars = [
          for (final x in m.collection('variablesLabo').actives)
            if (x['examen'] == examen && x['actif'] != false) x
        ]..sort((a, b) => ((a['ordre'] ?? 0) as num).compareTo((b['ordre'] ?? 0) as num));
        final lignes = liste(c['lignes']);
        expect(vars.length, lignes.length, reason: 'une ligne par variable active');
        for (final (i, l) in lignes.indexed) {
          final x = vars[i];
          final code = '${x['code']}';
          final lib = '${x['parent'] != null ? '↳ ' : ''}${x['libelle']}';
          expect('${l['variable']}'.startsWith(lib), isTrue, reason: '$lib / ${l['variable']}');
          if (x['accompagnement'] == true) {
            expect(find.text('${l['variable']}'.substring(lib.length)), findsWidgets);
          }
          final champ = find.byKey(Key('res:champ:$code'));
          expect(champ, findsOneWidget, reason: code);
          final attendu = (l['champ'] as Map).cast<String, Object?>();
          final w = t.widget(champ);
          if (attendu['balise'] == 'select') {
            expect(w is DropdownButton<String>, isTrue, reason: '$code est une liste');
            expect((w as DropdownButton<String>).items!.length, (attendu['options'] as List).length, reason: '$code : options');
          } else {
            expect(w is TextField, isTrue, reason: '$code est un champ');
          }
          if (l['unite'] != '—') expect(find.text('${l['unite']}'), findsWidgets);
          if (l['reference'] != '—') expect(find.text('${l['reference']}'), findsWidgets, reason: '$code : références');
        }
        if (c['apresSaisie'] != null) {
          final valeurs = <String, String>{
            if (examen == 'NFS') ...{'GB': '12', 'GR': '9', 'HB': '5', 'VGM': '85'},
          };
          for (final en in valeurs.entries) {
            await t.enterText(find.byKey(Key('res:champ:${en.key}')), en.value);
            await t.pump();
          }
          if (examen == 'VIH') {
            await toucher(t, find.byKey(Key('res:champ:${vars.first['code']}')));
            await toucher(t, find.text('Positif').last);
          }
          final badges = (c['apresSaisie'] as List).cast<String>();
          for (final (i, b) in badges.indexed) {
            final e = find.byKey(Key('res:ecart:${vars[i]['code']}'));
            final texte = find.descendant(of: e, matching: find.byType(Text));
            expect(texte.evaluate().isEmpty ? '' : (t.widget(texte.first) as Text).data, b,
                reason: 'écart de ${vars[i]['code']}');
          }
        }
        for (final b in (c['pied'] as List).cast<String>()) {
          expect(find.widgetWithText(BoutonSigh, b), findsWidgets, reason: b);
        }
      });
    }
  });

  // --- Les deux verrous, au geste -------------------------------------------------------------------------------------------------------
  Fiche demande(Magasin m, String etat, {String? prelevePar}) => m
      .collection('demandesAnalyses')
      .actives
      .firstWhere((d) =>
          d['etatAnalyse'] == etat &&
          (prelevePar == null || d['prelevePar'] == prelevePar));

  group('m5-resultats : les gestes', () {
    cas('le biologiste qui a prélevé valide : visible du prescripteur, notifié, journalisé, annulable', (t) async {
      final m = jeuResultats();
      final d = demande(m, 'valide_technique', prelevePar: 'KINNOU Ganiou');
      await monter(
          t,
          m,
          const EcranResultats(fonction: 'biologiste', agentId: 'AG1'),
          role: 'laborantin',
          utilisateur: 'KINNOU Ganiou');
      // Avant : le médecin ne voit pas ce résultat (premier verrou).
      expect(peutVoirResultat(d, const SessionLabo(fonction: 'medecin')).autorise, isFalse);
      await onglet(t, 'relecture');
      await toucher(t, find.byKey(Key('res:valider-bio:${d['reference']}')));
      expect(find.text('Validation biologique'), findsWidgets);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider biologiquement'));
      final apres = m.collection('demandesAnalyses').parId(d['id'])!;
      expect(apres['etatAnalyse'], 'valide');
      expect(apres['valideBiologiquePar'], 'KINNOU Ganiou');
      expect(apres['validationInterim'], false);
      expect(apres['qualiteValidateur'], 'Biologiste médical');
      final nots = m.collection('notifications').actives;
      expect(nots.length, 1);
      expect(nots.single['type'], 'resultat_disponible');
      expect(nots.single['destinataire'], d['prescripteur']);
      expect(nots.single['demandeId'], d['id']);
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Validation biologique'), isTrue);
      expect(peutVoirResultat(apres, const SessionLabo(fonction: 'medecin')).autorise, isTrue);
      expect(find.text('Validation biologique portée.'), findsOneWidget);
      // Annuler restitue la demande (la notification déjà émise reste, comme dans la maquette).
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('demandesAnalyses').parId(d['id'])!['etatAnalyse'], 'valide_technique');
      expect(find.text('Action annulée.'), findsOneWidget);
    });

    cas('le TSL ne valide que par intérim, et l\'intérim est porté sur la pièce', (t) async {
      final m = jeuResultats();
      final d = demande(m, 'valide_technique', prelevePar: 'IMOROU Choucouratou');
      await monter(t, m, const EcranResultats(agentId: 'AG2'),
          role: 'laborantin', utilisateur: 'IMOROU Choucouratou');
      await onglet(t, 'relecture');
      expect(find.text('Valider par intérim'), findsWidgets);
      await toucher(t, find.byKey(Key('res:valider-bio:${d['reference']}')));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider par intérim').last);
      final apres = m.collection('demandesAnalyses').parId(d['id'])!;
      expect(apres['etatAnalyse'], 'valide');
      expect(apres['validationInterim'], true);
      expect('${apres['qualiteValidateur']}', contains('par intérim du biologiste médical'));
    });

    cas('la continuité : un biologiste ne valide pas le prélèvement de l\'autre, et le refus NOMME le préleveur', (t) async {
      final m = jeuResultats();
      final d = demande(m, 'valide_technique', prelevePar: 'KINNOU Ganiou');
      await monter(t, m, const EcranResultats(fonction: 'biologiste', agentId: 'AG3'),
          role: 'laborantin', utilisateur: 'AUTRE Biologiste');
      await onglet(t, 'relecture');
      expect(find.byKey(Key('res:valider-bio:${d['reference']}')), findsNothing);
      await toucher(t, find.byKey(Key('res:verrou-relecture:${d['reference']}')));
      expect(find.text('Relecture réservée au préleveur.'), findsOneWidget);
      expect(find.textContaining('Le prélèvement a été fait par KINNOU Ganiou'), findsOneWidget);
      expect(m.collection('demandesAnalyses').parId(d['id'])!['etatAnalyse'], 'valide_technique');
      expect(m.collection('notifications').actives, isEmpty);
    });

    cas('un médecin n\'est pas habilité : la commande est ABSENTE, la note le dit', (t) async {
      final m = jeuResultats();
      await monter(t, m, const EcranResultats(), role: 'medecin', utilisateur: 'Dr TEST');
      await onglet(t, 'relecture');
      // Premier verrou : le médecin ne voit pas non plus les résultats non validés.
      expect(find.byType(BoutonSigh, skipOffstage: false).evaluate().where((e) => (e.widget as BoutonSigh).libelle.startsWith('Valid')), isEmpty);
      expect(find.textContaining('vous n’êtes pas habilité à porter la validation biologique'), findsOneWidget);
    });

    cas('saisie impossible avant la réception de l\'échantillon : visible, verrouillée, qui dit chez qui est la balle', (t) async {
      final m = jeuResultats();
      final d = demande(m, 'en_attente');
      await monter(t, m, const EcranResultats(fonction: 'biologiste', agentId: 'AG1'),
          role: 'laborantin', utilisateur: 'KINNOU Ganiou');
      await toucher(t, find.byKey(Key('res:saisir-verrou:${d['reference']}')));
      expect(find.text('Saisie impossible.'), findsOneWidget);
      expect(find.textContaining('Le patient doit d’abord passer à la caisse.'), findsOneWidget);
      expect(find.text('Saisie du résultat — ${d['analyse']}'), findsNothing);
      // Le clic sur la ligne est gardé aussi : un contrôle qu'on peut contourner n'en est pas un.
      ToastsSigh.viderPourTests();
      await toucher(t, find.text('${d['reference']}'));
      expect(find.text('Saisie impossible.'), findsOneWidget);
      expect(find.text('Saisie du résultat — ${d['analyse']}'), findsNothing);
    });

    cas('saisie : l\'écart se voit à la saisie, un résultat incomplet est refusé en nommant ce qui manque, puis la validation technique', (t) async {
      final m = jeuResultats();
      final d = demande(m, 'en_cours');
      await monter(t, m, const EcranResultats(fonction: 'biologiste', agentId: 'AG1'),
          role: 'laborantin', utilisateur: 'KINNOU Ganiou');
      await toucher(t, find.byKey(Key('res:saisir:${d['reference']}')));
      expect(find.text('Saisie du résultat — ${d['analyse']}'), findsOneWidget);
      // Les deux identifiants du dossier sont lus en tête de la saisie.
      expect(find.text('${d['codeAnalyse']}'), findsWidgets);
      final vars = [
        for (final x in m.collection('variablesLabo').actives)
          if (x['examen'] == 'NFS' && x['actif'] != false && x['accompagnement'] != true && x['parent'] == null) x
      ]..sort((a, b) => ((a['ordre'] ?? 0) as num).compareTo((b['ordre'] ?? 0) as num));
      expect(vars, isNotEmpty);
      // Valider sans rien saisir : refus nommé.
      await toucher(t, find.byKey(const Key('res:valider-resultat')));
      expect(find.text('Résultat incomplet.'), findsOneWidget);
      expect(m.collection('demandesAnalyses').parId(d['id'])!['etatAnalyse'], 'en_cours');
      // Chaque variable principale : la première au-dessus de sa borne (« Haut »), les autres dans la plage.
      for (final (i, x) in vars.indexed) {
        final haut = i == 0 ? (x['max'] as num) + 5 : ((x['min'] as num) + (x['max'] as num)) / 2;
        await t.enterText(find.byKey(Key('res:champ:${x['code']}')), '$haut');
        await t.pump();
        if (i == 0) {
          expect(find.text('Haut'), findsOneWidget, reason: 'l\'écart s\'affiche À LA SAISIE');
        }
      }
      ToastsSigh.viderPourTests();
      await toucher(t, find.byKey(const Key('res:valider-resultat')));
      final apres = m.collection('demandesAnalyses').parId(d['id'])!;
      expect(apres['etatAnalyse'], 'valide_technique', reason: 'PREMIER verrou seulement');
      expect(apres['conclusion'], 'Anormal');
      expect(apres['anormales'], 1);
      expect(apres['resultatStructure'], true);
      expect('${apres['resultat']}', contains('${vars.first['libelle']}'));
      expect(find.text('Validation technique portée.'), findsOneWidget);
      expect(find.textContaining('Le prescripteur NE VOIT PAS encore ce résultat'), findsOneWidget);
      expect(peutVoirResultat(apres, const SessionLabo(fonction: 'medecin')).autorise, isFalse);
    });

    cas('« enregistrer sans valider » : l\'état reste « saisi », rien n\'est rendu', (t) async {
      final m = jeuResultats();
      final d = demande(m, 'en_cours');
      await monter(t, m, const EcranResultats(fonction: 'biologiste', agentId: 'AG1'),
          role: 'laborantin', utilisateur: 'KINNOU Ganiou');
      await toucher(t, find.byKey(Key('res:saisir:${d['reference']}')));
      await t.enterText(find.byKey(const Key('res:champ:GB')), '5');
      await toucher(t, find.byKey(const Key('res:enregistrer')));
      final apres = m.collection('demandesAnalyses').parId(d['id'])!;
      expect(apres['etatAnalyse'], 'saisi');
      expect(apres['valideTechniqueLe'], isNull);
      expect(find.text('Résultat enregistré, non validé.'), findsOneWidget);
    });

    cas('rectification : jamais un écrasement — version sortante conservée, motif obligatoire, prescripteur averti', (t) async {
      final m = jeuResultats();
      final d = demande(m, 'valide');
      // La fiche du magasin est modifiée en place : on garde ce qu'elle était AVANT la rectification.
      final v0 = (d['version'] ?? 1) as num;
      final valeurs0 = {...(d['valeurs'] as Map).cast<String, Object?>()};
      await monter(t, m, const EcranResultats(), role: 'direction', utilisateur: 'DIR TEST');
      await onglet(t, 'valides');
      await toucher(t, find.byKey(Key('res:corriger:${d['reference']}')));
      await t.enterText(find.byKey(const Key('res:champ:GB')), '7.5');
      await toucher(t, find.byKey(const Key('res:enregistrer')));
      // Le résultat est rendu : la saisie devient une demande de RECTIFICATION.
      expect(find.text('Rectifier un résultat déjà rendu'), findsOneWidget);
      expect(find.text('Version actuelle'), findsOneWidget);
      expect(m.collection('demandesAnalyses').parId(d['id'])!['etatAnalyse'], 'valide');
      // Sans motif : refus, rien n'est écrit.
      await toucher(t, find.byKey(const Key('res:emettre-rectification')));
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(m.collection('demandesAnalyses').parId(d['id'])!['version'] ?? 1, v0);
      await t.enterText(find.byType(TextField).last, 'Erreur de transcription du GB');
      await toucher(t, find.byKey(const Key('res:emettre-rectification')));
      final apres = m.collection('demandesAnalyses').parId(d['id'])!;
      expect(apres['etatAnalyse'], 'rectifie');
      expect(apres['version'], v0 + 1);
      expect(apres['motifRectification'], 'Erreur de transcription du GB');
      final versions = apres['versions'] as List;
      expect(versions.last['valeurs'], valeurs0, reason: 'la version lue par le médecin reste consultable');
      expect(versions.last['motifRemplacement'], 'Erreur de transcription du GB');
      final nt = m.collection('notifications').actives.single;
      expect(nt['type'], 'resultat_rectifie');
      expect(nt['priorite'], 'haute');
      expect('${nt['detail']}', contains('Le résultat que vous avez consulté a changé.'));
      expect(find.textContaining('est notifié que le résultat a changé'), findsOneWidget);
    });

    cas('un résultat rendu s\'imprime seul ou en compte rendu complet du patient', (t) async {
      final m = jeuResultats();
      final d = demande(m, 'valide');
      await monter(t, m, const EcranResultats(), role: 'direction', utilisateur: 'DIR TEST');
      await onglet(t, 'valides');
      await toucher(t, find.byKey(Key('res:imprimer:${d['reference']}')));
      expect(find.text('Résultat d’analyse de laboratoire'), findsOneWidget);
    });
  });

  // --- m5-impression-resultats : le règlement se lit sur la ligne de facture --------------------------------------------------------------------
  group('m5-impression-resultats : impression conditionnée au règlement (vecteurs)', () {
    final imp = (v['impression'] as Map).cast<String, Object?>();
    final ent = (entrees['impression'] as Map).cast<String, Object?>();
    Magasin jeuImp() => magasin({
          'demandesAnalyses': liste(ent['demandes']),
          'factures': liste(ent['factures']),
        });
    for (final c in liste(imp['cas'])) {
      final s = (c['session'] as Map).cast<String, Object?>();
      cas('${c['profil']}', (t) async {
        final m = jeuImp();
        await monter(t, m, EcranImpressionResultats(fonction: s['fonction'] as String?), role: '${s['role']}', utilisateur: '${s['nom']}');
        for (final k in liste(c['kpis'])) {
          expect(kpi(t, '${k['libelle']}'), k['valeur'], reason: '${k['libelle']}');
        }
        final lignes = liste(c['lignes']);
        final attendu = [for (final l in lignes) refDe((l['cellules'] as List).first)];
        expect(affichees(t, m.collection('demandesAnalyses').actives.map((d) => '${d['reference']}')), attendu);
        for (final l in lignes) {
          final ref = refDe((l['cellules'] as List).first);
          final cel = '${(l['cellules'] as List)[5]}';
          final verrou = (liste(l['boutons']).first)['verrou'] as bool;
          expect(find.byKey(Key('res:imprimer-verrou:$ref')).evaluate().isNotEmpty, verrou, reason: ref);
          expect(find.byKey(Key('res:imprimer-resultat:$ref')).evaluate().isNotEmpty, !verrou, reason: ref);
          // Le libellé du règlement (et la pièce nommée) est lu sur la ligne.
          final libelle = cel.startsWith('Règlement dû') ? 'Règlement dû' : (cel.startsWith('Réglée') ? 'Réglée' : 'Sans pièce liée');
          expect(find.text(libelle), findsWidgets, reason: '$ref : $libelle');
          final piece = cel.substring(libelle.length);
          if (piece.isNotEmpty) expect(find.text(piece), findsWidgets, reason: '$ref : pièce $piece');
        }
      });
    }

    cas('imprimer un examen RÉGLÉ ouvre l\'aperçu ; un examen dû est verrouillé en nommant la pièce et la caisse', (t) async {
      final m = jeuImp();
      await monter(t, m, const EcranImpressionResultats());
      final pose = liste(imp['poses']);
      final regle = pose.firstWhere((p) => p['nom'] == 'ligne payée')['reference'];
      final du = pose.firstWhere((p) => p['nom'] == 'ligne due')['reference'];
      await toucher(t, find.byKey(Key('res:imprimer-verrou:$du')));
      expect(find.text('Impression verrouillée : examen non réglé.'), findsOneWidget);
      expect(find.textContaining('après règlement de la pièce FP-2026-D1. La balle est à la caisse.'), findsOneWidget);
      await toucher(t, find.byKey(Key('res:imprimer-resultat:$regle')));
      expect(find.text('Résultat d’analyse de laboratoire'), findsOneWidget);
    });

    cas('un profil sans accès aux résultats ne voit rien à imprimer (et l\'écran le dit)', (t) async {
      final m = jeuImp();
      await monter(t, m, const EcranImpressionResultats(), role: 'infirmier', utilisateur: 'Inf');
      expect(kpi(t, 'Résultats rendus'), '0');
      expect(find.text('Aucun résultat rendu dans votre périmètre.'), findsOneWidget);
    });
  });

  // --- m5-resultats-comparatif -----------------------------------------------------------------------------------------------------------------
  group('m5-resultats-comparatif : les antériorités aux bornes de leur époque (vecteurs)', () {
    final ent = (entrees['comparatif'] as Map).cast<String, Object?>();
    Magasin jeuCmp() => magasin({
          'demandesAnalyses': liste(ent['demandes']),
          'plagesReactif': liste(ent['plages']),
        });
    cas('sans patient choisi : la consigne, la liste des patients comparables et la note de périmètre', (t) async {
      final c0 = liste(v['comparatif']).first;
      await monter(t, jeuCmp(), const EcranComparatifResultats());
      expect(find.text('Choisir un patient pour ouvrir la comparaison.'), findsOneWidget);
      expect(find.textContaining('${(c0['notes'] as List).first}'), findsOneWidget);
      await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:patient')), matching: find.byType(InkWell)).first);
      for (final p in liste((c0['options'] as Map)['patients'])) {
        expect(find.text('${p['libelle']}'), findsOneWidget, reason: '${p['libelle']}');
      }
    });
    for (final c in liste(v['comparatif']).where((c) => c['lignes'] != null)) {
      cas('${c['patient']} / ${c['examen']} : ${(c['choisi'] as Map)['a']} → ${(c['choisi'] as Map)['b']}', (t) async {
        await monter(t, jeuCmp(), const EcranComparatifResultats());
        final libPatient = liste((c['options'] as Map)['patients']).firstWhere((p) => p['value'] == c['patient'])['libelle'];
        await choisir(t, 'patient', '$libPatient');
        final libExamen = liste((c['options'] as Map)['examens']).firstWhere((p) => p['value'] == c['examen'])['libelle'];
        await choisir(t, 'examen', '$libExamen');
        final choix = liste(c['choixPossibles']);
        final choisi = (c['choisi'] as Map).cast<String, Object?>();
        final defaut = (c['parDefaut'] as Map).cast<String, Object?>();
        if (choisi['a'] != defaut['a']) {
          await choisir(t, 'a', '${choix.firstWhere((x) => x['value'] == choisi['a'])['libelle']}');
        }
        if (choisi['b'] != defaut['b']) {
          await choisir(t, 'b', '${choix.firstWhere((x) => x['value'] == choisi['b'])['libelle']}');
        }
        for (final e in (c['entetes'] as List).cast<String>().skip(1).take(2)) {
          expect(find.text(e.toUpperCase() == e ? e : e), findsWidgets, reason: 'en-tête $e');
        }
        for (final l in liste(c['lignes'])) {
          final cel = (l['cellules'] as List).cast<String>();
          for (final x in cel) {
            expect(find.text(x), findsWidgets, reason: 'cellule $x');
          }
        }
        expect(find.textContaining('L’évolution se lit de gauche à droite.'), findsOneWidget);
      });
    }
    cas('un examen à UNE mesure : aucune antériorité, et le dit', (t) async {
      final c = liste(v['comparatif']).firstWhere((c) => c['examen'] == 'GLYAJ');
      await monter(t, jeuCmp(), const EcranComparatifResultats());
      final libPatient = liste((c['options'] as Map)['patients']).firstWhere((p) => p['value'] == c['patient'])['libelle'];
      await choisir(t, 'patient', '$libPatient');
      expect(find.text('Choisir un examen : ceux qui portent plusieurs mesures se comparent.'), findsOneWidget);
      await choisir(t, 'examen', '${liste((c['options'] as Map)['examens']).firstWhere((p) => p['value'] == 'GLYAJ')['libelle']}');
      expect(find.textContaining('Une seule mesure de cet examen : aucune antériorité à comparer.'), findsOneWidget);
    });
    cas('une infirmière ne compare rien : restriction annoncée, aucun patient proposé', (t) async {
      final c = liste(v['comparatif']).firstWhere((c) => c['profil'] == 'infirmier');
      await monter(t, jeuCmp(), const EcranComparatifResultats(), role: 'infirmier', utilisateur: 'Inf');
      expect(find.textContaining('${((c['notes'] as List).first as String).split(' ').first} résultat(s) rendus sont hors de votre périmètre'), findsOneWidget);
    });
  });

  // --- m5-stats ----------------------------------------------------------------------------------------------------------------------------
  group('m5-stats : les cinq axes sont des filtres (vecteurs)', () {
    final ent = (entrees['stats'] as Map).cast<String, Object?>();
    Magasin jeuStats() => magasin({
          'demandesAnalyses': liste(ent['demandes']),
          'patients': [...liste(ent['patients']), ...liste(jsonDecode(File('test/fixtures/jeu_sobre/patients.json').readAsStringSync()))],
        });
    for (final c in liste(v['stats']).where((c) => (c['filtres'] as Map)['periode'] == 'libre')) {
      final f = (c['filtres'] as Map).cast<String, Object?>();
      cas('${c['nom']}', (t) async {
        await monter(t, jeuStats(), EcranStatsLabo(periode: 'libre', du: '${f['du']}', au: '${f['au']}'));
        if (f['section'] != null) {
          await choisir(t, 'section', '${liste((c['options'] as List)[1]).firstWhere((o) => o['value'] == f['section'])['libelle']}');
        }
        if (f['service'] != null) await choisir(t, 'service', '${f['service']}');
        if (f['origine'] != null) {
          await choisir(t, 'origine', '${liste((c['options'] as List)[3]).firstWhere((o) => o['value'] == f['origine'])['libelle']}');
        }
        if (f['sexe'] != null) {
          await choisir(t, 'sexe', f['sexe'] == 'F' ? 'Féminin' : 'Masculin');
        }
        for (final k in liste(c['kpis'])) {
          expect(kpi(t, '${k['libelle']}'), k['valeur'], reason: '${k['libelle']}');
          if ('${k['indice']}'.isNotEmpty) expect(find.text('${k['indice']}'), findsOneWidget);
        }
        final titres = (c['cartes'] as List).cast<String>();
        for (final titre in titres) {
          expect(find.text(titre), findsWidgets, reason: titre);
        }
        if (c['vide'] != '') {
          expect(find.text('${c['vide']}'), findsOneWidget);
        } else {
          for (final l in (c['tableau'] as List)) {
            final cel = (l as List).cast<String>();
            expect(find.text(cel[0]), findsWidgets, reason: 'examen ${cel[0]}');
          }
          expect(find.text('${c['titreTableau']}'), findsOneWidget);
        }
      });
    }
    cas('imprimer l\'état : l\'activité du laboratoire, totaux CALCULÉS depuis les lignes', (t) async {
      final c = liste(v['stats']).first;
      final f = (c['filtres'] as Map).cast<String, Object?>();
      await monter(t, jeuStats(), EcranStatsLabo(periode: 'libre', du: '${f['du']}', au: '${f['au']}'));
      await toucher(t, find.byKey(const Key('res:imprimer-etat')));
      expect(find.text('Activité du laboratoire d’analyses biomédicales'), findsOneWidget);
      final etat = liste(c['impression']).firstWhere((j) => j['fn'] == 'etat');
      expect(find.text('${etat['sousTitre']}'), findsWidgets);
      expect(find.text('TOTAL'), findsWidgets);
    });
    cas('un jour sans examen : état vide dit, jamais un graphique vide', (t) async {
      await monter(t, jeuStats(), const EcranStatsLabo(periode: 'libre', du: '2026-01-01', au: '2026-01-31'));
      expect(find.text('Aucun examen sur la période et les filtres retenus.'), findsOneWidget);
      expect(find.text('Par section du bulletin'), findsNothing);
    });
  });
}
