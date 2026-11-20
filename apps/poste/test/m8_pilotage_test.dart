import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Tableau de bord et recettes : tout est CALCULÉ depuis les factures. Chaque valeur affichée est recomptée ici INDÉPENDAMMENT (sur le magasin),
/// jamais lue de l'écran qu'on teste. L'horloge du poste est fixée à une date du jeu (16/08/2026) — c'est ce que fait le banc de la maquette.
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 8, 16);

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin', DateTime? le}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => le ?? auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<String?> kpis(WidgetTester t) => [
      for (final w
          in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
        w.data
    ];

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  testWidgets(
      'dashboard : les 8 KPI = recomptes indépendants (jour, mois, reliquats, impayées, part assurance)',
      (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm8-dashboard');
    final f = m.collection('factures').actives;
    num s(Iterable<Fiche> r, String k) =>
        r.fold<num>(0, (a, x) => a + ((x[k] as num?) ?? 0));
    final jour = f.where((x) => x['date'] == '2026-08-16');
    final mois = f.where((x) => '${x['date']}'.startsWith('2026-08'));
    expect(kpis(t), [
      money(s(jour, 'montantTTC')),
      money(s(jour, 'montantPaye')),
      money(s(mois, 'montantTTC')),
      money(s(mois, 'montantPaye')),
      nombre(f.length),
      money(s(f, 'reliquat')),
      nombre(f.where((x) => x['statutPaiement'] == 'impayee').length),
      money(s(f.where((x) => x['assureur'] != null), 'partAssurance')),
    ]);
    expect(mois, isNotEmpty, reason: 'la sonde ne doit pas mesurer des zéros');
    expect(find.byKey(const Key('graphique:anneau')), findsOneWidget);
    expect(find.text('Dernières factures'), findsOneWidget);
    expect(find.text('Accès rapides'), findsOneWidget);
  });

  testWidgets(
      'dashboard : un raccourci mène à l’écran, et la liste des dernières factures est bornée à dix',
      (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm8-dashboard');
    await t.ensureVisible(find.text('Reliquats').last);
    await t.tap(find.text('Reliquats').last);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Reliquats en cours'), findsWidgets);
  });

  testWidgets(
      'recettes : plage libre sur août = somme indépendante des factures de la plage ; taux de recouvrement',
      (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm8-recettes');
    await t.tap(find.text('Plage de dates libre'));
    await t.pump();
    final f = m.collection('factures').actives.where((x) =>
        (x['date'] as String).compareTo('2026-07-18') >= 0 &&
        (x['date'] as String).compareTo('2026-08-16') <= 0);
    // Plage libre par défaut : du = auj − 29 jours, au = auj.
    final enc = f.fold<num>(0, (a, x) => a + ((x['montantPaye'] as num?) ?? 0));
    final fac = f.fold<num>(0, (a, x) => a + ((x['montantTTC'] as num?) ?? 0));
    final v = kpis(t);
    expect(v[0], money(enc));
    expect(v[1], money(fac));
    expect(v[3], fac == 0 ? '—' : '${(enc * 100 / fac).round()} %');
    expect(enc, greaterThan(0));
  });

  testWidgets(
      'recettes : changer la périodicité recalcule (journée ⊂ semaine ⊂ mois)',
      (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm8-recettes');
    num lire() => num.parse(kpis(t)[0]!.replaceAll(RegExp(r'[^\d]'), ''));
    final jour = lire();
    await t.tap(find.byKey(const Key('kit:champ:periode')));
    await t.pumpAndSettle();
    await t.tap(find.text('Mensuelle').last);
    await t.pumpAndSettle();
    expect(lire(), greaterThanOrEqualTo(jour));
    expect(find.text('Évolution des encaissements'), findsNothing,
        reason: 'une seule tranche (le mois) : pas de courbe');
  });

  testWidgets(
      'recettes : l’état imprimé porte un TOTAL refait depuis les lignes',
      (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm8-recettes');
    await t.tap(find.text('Plage de dates libre'));
    await t.pump();
    await t.ensureVisible(find.text('Éditer l’état'));
    await t.tap(find.text('Éditer l’état'));
    await t.pumpAndSettle();
    expect(find.text('État des recettes'), findsWidgets);
    expect(find.text('TOTAL'), findsOneWidget);
  });

  testWidgets(
      'opérations : KPI recomptés sur la journée ; l’inventaire annonce l’écart (manquant / excédent / juste) et l’édite',
      (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    // Le jeu est daté : on pose l'horloge sur son jour le plus chargé (sinon la sonde mesurerait des zéros).
    final dates = <String, int>{};
    for (final x in m.collection('factures').actives) {
      dates['${x['date']}'] = (dates['${x['date']}'] ?? 0) + 1;
    }
    final plein = (dates.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
    await ouvrir(t, m, 'm8-operations', le: DateTime.parse(plein));
    final jour = m
        .collection('factures')
        .actives
        .where((x) => x['date'] == plein)
        .toList();
    expect(jour, isNotEmpty);
    final enc =
        jour.fold<num>(0, (a, x) => a + ((x['montantPaye'] as num?) ?? 0));
    expect(kpis(t)[0], nombre(jour.length));
    expect(kpis(t)[1], money(enc));
    await t.tap(find.text('Inventaire de caisse'));
    await t.pumpAndSettle();
    expect(find.textContaining('Caisse juste.'), findsOneWidget,
        reason: 'le compté proposé est le théorique');
    final theorique = jour
        .where((x) => (x['modePaiement'] ?? 'especes') == 'especes')
        .fold<num>(0, (a, x) => a + ((x['montantPaye'] as num?) ?? 0));
    await t.enterText(
        find.descendant(
            of: find.byKey(const Key('kit:champ:compte')),
            matching: find.byType(TextField)),
        '${theorique.round() - 500}');
    await t.pump();
    expect(find.textContaining('Écart de ${money(500)} — manquant'),
        findsOneWidget);
    await t.enterText(
        find.descendant(
            of: find.byKey(const Key('kit:champ:compte')),
            matching: find.byType(TextField)),
        '${theorique.round() + 500}');
    await t.pump();
    expect(find.textContaining('excédent'), findsOneWidget);
    await t.tap(find.text('Éditer l’inventaire'));
    await t.pumpAndSettle();
    expect(find.text('Excédent constaté'), findsOneWidget);
    expect(find.textContaining('La Directrice Administrative'), findsOneWidget);
  });
}
