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

/// Rejoue les vecteurs de la maternité (prototype_html/build/vecteurs-maternite.js) sur les onze registres de M4 portés : indicateurs, ordre et
/// contenu des lignes, filtres, plage de dates. Le jeu est celui de la maquette (le même que celui des vecteurs), l'horloge le 16/08/2026.
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final vec = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/mat_lectures.json').readAsStringSync()));
final lectures = obj(vec['lectures']);
final auj = DateTime(2026, 8, 16, 12);

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

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

String s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');

String kpi(WidgetTester t, String l) => t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == l)).valeur;
String? indice(WidgetTester t, String l) => t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == l)).indice;

List<M> lignes(WidgetTester t) => t.state<TableauSighState>(find.byType(TableauSigh).first).lignesFiltrees.cast<M>();

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);

  for (final id in lectures.keys.where((k) => k != 'm4-dossier-obstetrical')) {
    final v = obj(lectures[id]);
    group(id, () {
      cas('indicateurs rejouent la maquette', (t) async {
        await ouvrir(t, jeu(), id);
        for (final k in liste(v['kpis'])) {
          expect(s(kpi(t, '${k['label']}')), s(k['valeur']), reason: '${k['label']}');
          expect(s(indice(t, '${k['label']}')), s(k['indice']), reason: 'indice de ${k['label']}');
        }
      });

      cas('lignes : même ordre, même contenu (première page)', (t) async {
        await ouvrir(t, jeu(), id);
        final cols = t.widget<TableauSigh>(find.byType(TableauSigh).first).colonnes;
        final ls = lignes(t);
        expect(ls.length, v['nb']);
        final p1 = (v['page1'] as List).cast<List>();
        for (var i = 0; i < p1.length; i++) {
          final attendu = s([for (final c in p1[i]) c].join());
          final obtenu = s([for (final c in cols) c.enTexte(ls[i])].join());
          expect(obtenu, attendu, reason: 'ligne ${i + 1}');
        }
      });

      cas('filtres : effectifs identiques', (t) async {
        await ouvrir(t, jeu(), id);
        final tous = lignes(t);
        final defs = t.widget<TableauSigh>(find.byType(TableauSigh).first).filtres;
        final fv = liste(v['filtres']);
        for (var i = 0; i < fv.length; i++) {
          for (final e in liste(fv[i]['effets'])) {
            final d = defs[i];
            final n = tous.where((r) => d.correspond != null ? d.correspond!(r, '${e['valeur']}') : '${r[d.nom]}' == '${e['valeur']}').length;
            expect(n, e['nb'], reason: '${d.libelle} = ${e['valeur']}');
          }
        }
      });

      if (v['plage'] != null) {
        cas('plage de dates', (t) async {
          await ouvrir(t, jeu(), id);
          final tab = t.state<TableauSighState>(find.byType(TableauSigh).first);
          final p = liste(v['plage']);
          await t.tap(find.byKey(const Key('mat:sept-jours')));
          await t.pump();
          expect(tab.lignesFiltrees.length, p[0]['nb']);
          await t.tap(find.byKey(const Key('mat:toute-periode')));
          await t.pump();
          expect(tab.lignesFiltrees.length, p[2]['nb']);
        });
      }
    });
  }
}
