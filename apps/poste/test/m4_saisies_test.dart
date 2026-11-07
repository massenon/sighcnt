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

/// Rejoue les SAISIES pilotées dans la maquette (création, refus nommés, modification) sur les registres de M4 : le même formulaire est rempli avec
/// les mêmes valeurs, le même bouton est cliqué, et ce qui est ÉCRIT (ou refusé) est comparé à ce que la maquette a écrit (ou refusé).
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final saisies = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_saisies.json').readAsStringSync()));
final auj = DateTime(2026, 8, 16, 12);

const collections = {
  'm4-maternite': 'suiviMaternite',
  'm4-accouchements': 'accouchements',
  'm4-naissances': 'naissances',
  'm4-dossier-bebe': 'naissances',
  'm4-deces': 'deces',
  'm4-cpn': 'grossesses',
  'm4-cpon': 'cpon',
  'm4-planification': 'planificationFamiliale',
  'm4-sonu': 'registreSONU',
  'm4-ptme': 'ptme',
  'm4-soins-curatifs': 'soinsCuratifsMaternite',
};

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Pose les valeurs dans le formulaire de la modale ouverte (le contrôleur réel), comme l'agent les saisirait.
void poser(WidgetTester t, Map<String, Object?> saisie) {
  final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
  for (final e in saisie.entries) {
    final v = e.value;
    if (e.key == 'dateHeure' || e.key == 'debut') {
      final p = '$v'.split('T');
      ctl.poser('${e.key}Date', p[0]);
      ctl.poser('${e.key}Heure', p[1].substring(0, 5));
    } else if (v is List) {
      ctl.poser(e.key, [for (final x in v) '$x']);
    } else if (v is bool) {
      ctl.poser(e.key, v);
    } else {
      ctl.poser(e.key, '$v');
    }
  }
}

bool egal(Object? a, Object? b) {
  bool vide(Object? x) => x == null;
  if (vide(a) && vide(b)) return true;
  if (a is num && b is num) return a == b;
  if (a is List && b is List) return a.length == b.length && [for (var i = 0; i < a.length; i++) egal(a[i], b[i])].every((x) => x);
  if (a is Map && b is Map) return a.keys.toSet().union(b.keys.toSet()).every((k) => egal(a[k], b[k]));
  return '$a' == '$b';
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  const ignores = {'id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statut'};

  final toutes = liste(saisies['saisies']);
  for (final (idx, s) in toutes.indexed) {
    final ecran = '${s['ecran']}';
    final colNom = collections[ecran];
    if (colNom == null || s['modification'] == true) continue;
    cas('création — ${s['nom']}', (t) async {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      if ('${s['nom']}'.contains('sans date de naissance')) {
        final code = obj(saisies['contexte'])['femmeSansNaissance'];
        final p = m.collection('patients').toutes.firstWhere((x) => x['code'] == code);
        m.collection('patients').mettreAJour(p['id'], {'dateNaissance': null});
      }
      final col = m.collection(colNom);
      // La maquette a créé les fiches de ce lot dans l'ordre : on rejoue les précédentes du même registre pour que la référence suivante soit la même.
      var avant = 0;
      for (final x in toutes.take(idx)) {
        if (collections[x['ecran']] == colNom && x['modification'] != true) {
          for (final n in liste(x['nouvelles'] ?? const [])) {
            col.inserer({...n}, prefixe: 'T');
            avant++;
          }
        }
      }
      final n0 = col.toutes.length;
      await ouvrir(t, m, ecran);
      await t.ensureVisible(find.widgetWithText(BoutonSigh, 'Nouveau').first);
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Nouveau').first);
      await t.pump(const Duration(milliseconds: 400));
      poser(t, obj(s['saisie']));
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      final nouvelles = liste(s['nouvelles']);
      if (nouvelles.isEmpty) {
        expect(col.toutes.length, n0, reason: 'refus : rien n\'est écrit');
        final msg = ((s['toasts'] as List).first as List).first as String;
        if (msg != 'Le formulaire comporte des erreurs.') {
          expect(find.textContaining(msg.substring(0, 40)), findsWidgets, reason: 'le refus se nomme');
        } else {
          expect(find.text(msg), findsWidgets);
        }
      } else {
        expect(col.toutes.length, n0 + 1);
        final f = col.toutes.first;
        final att = nouvelles.single;
        for (final k in {...att.keys, ...f.keys}) {
          if (ignores.contains(k)) continue;
          if (k == 'patientId' || k == 'mereId') continue;
          expect(egal(f[k], att[k]), isTrue, reason: '$k : écrit ${f[k]}, maquette ${att[k]}');
        }
        await t.pump(const Duration(seconds: 1));
        // les toasts de la maquette : tous visibles (création + alerte éventuelle)
        for (final tt in (s['toasts'] as List).cast<List>()) {
          expect(find.textContaining('${tt.first}'.substring(0, '${tt.first}'.length < 20 ? '${tt.first}'.length : 20)), findsWidgets, reason: 'toast « ${tt.first} »');
        }
      }
    });
  }

  for (final s in liste(saisies['saisies'])) {
    final ecran = '${s['ecran']}';
    final colNom = collections[ecran];
    if (colNom == null || s['modification'] != true) continue;
    cas('modification — ${s['nom']}', (t) async {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      final col = m.collection(colNom);
      final ref = '${s['ref']}';
      final avant = col.toutes.firstWhere((x) => x['reference'] == ref);
      await ouvrir(t, m, ecran);
      await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, ref);
      await t.pump(const Duration(milliseconds: 500));
      await t.ensureVisible(find.byTooltip('Modifier').first);
      await t.pump();
      await t.tap(find.byTooltip('Modifier').first);
      await t.pump(const Duration(milliseconds: 400));
      poser(t, obj(s['saisie']));
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final apres = col.toutes.firstWhere((x) => x['id'] == avant['id']);
      expect(apres['reference'], ref, reason: 'la référence ne change pas à la modification (E401)');
      for (final e in obj(s['saisie']).entries) {
        if (e.key == 'dateHeure') continue;
        expect(egal(apres[e.key], e.value) || '${apres[e.key]}' == '${e.value}', isTrue, reason: '${e.key}');
      }
      for (final k in obj(s['patch']).keys) {
        if (k == 'dateHeure') {
          expect('${apres[k]}'.length, 16, reason: 'date-heure locale AAAA-MM-JJThh:mm (E402)');
          continue;
        }
        expect(egal(apres[k], obj(s['patch'])[k]) || '${apres[k]}' == '${obj(s['patch'])[k]}', isTrue, reason: 'patch ${k}: ${apres[k]} / ${obj(s['patch'])[k]}');
      }
    });
  }
}
