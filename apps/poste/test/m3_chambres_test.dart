import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// `m3-chambres` : l'écran rejoue les vecteurs de la maquette (registre d'admissions du vecteur → KPI, lignes, état imprimé) et sa parité N1 est
/// mesurée contre la fiche extraite.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/hospitalisation.json').readAsStringSync()) as Map).cast<String, Object?>();
List<Fiche> liste(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];
String _s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

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
      horloge: () => DateTime(2026, 8, 16, 10)));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  testWidgets('m3-chambres : KPI et lignes identiques à la maquette sur son registre d’admissions', (t) async {
    final a = (vecteurs['admissions'] as Map).cast<String, Object?>();
    final m = Magasin({'admissions': [for (final x in liste(a['etatFinal'])) {...x}], 'audit': const []}, 'POSTE');
    await ouvrir(t, m, 'm3-chambres');
    final ch = (a['chambres'] as Map).cast<String, Object?>();
    for (final k in liste(ch['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(_s(w.valeur), _s(k['valeur']), reason: '${k['libelle']}');
      expect(_s(w.indice), _s(k['indice']), reason: 'indice ${k['libelle']}');
    }
    final lignes = ((ch['tableaux'] as List).single as Map)['lignes'] as List;
    final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
    expect(tab.lignes.length, lignes.length);
    for (var i = 0; i < lignes.length; i++) {
      final l = lignes[i] as List;
      final r = tab.lignes[i];
      expect(r['code'], l[0]);
      expect(r['chambre'], l[1]);
      expect(r['statut'] == 'occupe' ? 'Occupé' : 'Libre', l[5]);
      expect(r['occupant'] ?? '—', l[6]);
    }
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('m3-chambres : parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm3-chambres');
    final fiche = (jsonDecode(File('../../docs/architecture/ecrans/m3-chambres.json').readAsStringSync()) as Map).cast<String, Object?>();
    final p = comparerContenu('m3-chambres', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
    await t.pump(const Duration(seconds: 10));
  });
}
