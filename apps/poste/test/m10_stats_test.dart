import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m10-stats-gardes, m10-stats-permanences, m10-stats-presence : les écrans MONTÉS sur le jeu du poste, filtres réglés comme le fait l'agent, et comparés
/// aux relevés de la maquette (packages/domaine/test/vecteurs/rhb.json). Les règles chiffrées sont rejouées par packages/domaine/test/rhb_regles_test.dart.
final _vec = (jsonDecode(File('../../packages/domaine/test/vecteurs/rhb.json').readAsStringSync()) as Map).cast<String, Object?>();
final _jeu = (_vec['jeuDeLaMaquette'] as Map).cast<String, Object?>();
final _auj16 = DateTime(2026, 8, 16, 12);

Map<String, String> kpis(WidgetTester t) => {for (final k in t.widgetList<KpiSigh>(find.byType(KpiSigh))) k.libelle: k.valeur};
Map<String, String?> indices(WidgetTester t) => {for (final k in t.widgetList<KpiSigh>(find.byType(KpiSigh))) k.libelle: k.indice};

/// Règle le filtre [nom] de la barre (son contrôleur est celui du champ affiché).
Future<void> regler(WidgetTester t, String nom, String valeur) async {
  t.widget<FormulaireSigh>(find.byKey(Key('rhb:filtre:$nom'))).controleur.poser(nom, valeur);
  await t.pump(const Duration(milliseconds: 50));
}

List<Map<String, Object?>> cas(String ecran) => [for (final c in ((_jeu[ecran] as Map)['cas'] as List)) (c as Map).cast<String, Object?>()];
String norm(Object? s) => '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('m10-stats-gardes', () {
    casM14('ouverture sur le mois glissant : les quatre compteurs, le tableau et les graphiques de la maquette', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-gardes', horloge: _auj16);
      final c = cas('gardes').first;
      expect(c['du'], '2026-07-18');
      final k = kpis(t);
      expect([k['Vacations travaillées'], k['Gardes'], k['Agents concernés'], k['Moyenne par agent']], ['391', '298', '34', '11.5']);
      expect(indices(t)['Vacations travaillées'], 'sur 30 jour(s)');
      expect(indices(t)['Gardes'], 'multiplicateur des primes NS 132');
      expect(find.text('Gardes par agent — du 18/07/2026 au 16/08/2026'), findsOneWidget);
      final lignes = t.widget<TableauSigh>(find.byType(TableauSigh)).lignes;
      final tab = (c['table'] as Map)['lignes'] as List;
      expect(lignes.first['agent'], startsWith(norm((tab.first as List)[0]).split(' ').first));
      expect(norm('${lignes.first['agent']} ${lignes.first['fonctionLabel']} · ${lignes.first['service']}'), norm((tab.first as List)[0]));
      for (final titre in ['Charge par agent — les dix premiers', 'Répartition par service', 'Répartition par type de vacation', 'Évolution du nombre de vacations']) {
        expect(find.text(titre), findsOneWidget, reason: titre);
      }
      for (final e in ['Agent', 'Gardes', 'Permanences', 'Soirées', 'Autres', 'Total', 'Heures']) {
        expect(find.text(e.toUpperCase()), findsWidgets, reason: e);
      }
    });

    casM14('la périodicité POSITIONNE la plage : semaine = sept jours, et les compteurs suivent', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-gardes', horloge: _auj16);
      await regler(t, 'periode', 'semaine');
      final f = (n) => t.widget<FormulaireSigh>(find.byKey(Key('rhb:filtre:$n'))).controleur[n];
      expect([f('du'), f('au')], ['2026-08-10', '2026-08-16']);
      final k = kpis(t);
      expect([k['Vacations travaillées'], k['Gardes'], k['Agents concernés'], k['Moyenne par agent']], ['132', '101', '34', '3.9']);
      expect(indices(t)['Vacations travaillées'], 'sur 7 jour(s)');
      expect(find.text('Évolution du nombre de vacations'), findsNothing); // un seul mois : pas de courbe
    });

    casM14('un agent seul : une ligne, les compteurs de la maquette', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-gardes', horloge: _auj16);
      await regler(t, 'periode', 'libre');
      await regler(t, 'du', '2026-07-01');
      await regler(t, 'au', '2026-12-31');
      await regler(t, 'agent', 'EMP12');
      final k = kpis(t);
      expect([k['Vacations travaillées'], k['Gardes'], k['Agents concernés'], k['Moyenne par agent']], ['28', '28', '1', '28']);
      expect(t.widget<TableauSigh>(find.byType(TableauSigh)).lignes.length, 1);
    });

    casM14('un type « permanence » : zéro garde, huit agents', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-gardes', horloge: _auj16);
      await regler(t, 'periode', 'libre');
      await regler(t, 'du', '2026-07-01');
      await regler(t, 'au', '2026-12-31');
      await regler(t, 'type', 'permanence');
      final k = kpis(t);
      expect([k['Vacations travaillées'], k['Gardes'], k['Agents concernés'], k['Moyenne par agent']], ['101', '0', '8', '12.6']);
    });

    casM14('aucune vacation : le message dit quoi élargir, et rien n\'est compté', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-gardes', horloge: _auj16);
      await regler(t, 'periode', 'libre');
      await regler(t, 'du', '2030-01-01');
      await regler(t, 'au', '2030-01-31');
      expect(find.text('Aucune vacation sur la période et les filtres retenus.'), findsOneWidget);
      expect(find.textContaining('Les repos et congés ne sont jamais comptés.'), findsOneWidget);
      expect(find.byType(TableauSigh), findsNothing);
      expect(kpis(t)['Vacations travaillées'], '0');
      expect(kpis(t)['Moyenne par agent'], '0');
    });

    casM14('au 30/10/2026 (horloge des fiches) : le jeu daté d\'août ne montre rien sur le mois', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-gardes');
      expect(find.text('Aucune vacation sur la période et les filtres retenus.'), findsOneWidget);
      expect(indices(t)['Vacations travaillées'], 'sur 30 jour(s)');
    });

    casM14('« Imprimer l\'état » : cartouche, filtres en force, tableau totalisé, deux signatures', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-gardes', horloge: _auj16);
      await regler(t, 'periode', 'libre');
      await regler(t, 'du', '2026-08-01');
      await regler(t, 'au', '2026-08-31');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’état'));
      expect(find.text('État des gardes effectuées'), findsOneWidget);
      expect(find.text('du 01/08/2026 au 31/08/2026'), findsWidgets);
      expect(find.text('Vacations travaillées'), findsWidgets);
      expect(find.text('Le Surveillant Général'), findsWidgets);
      expect(find.text('GARBA Yahouza'), findsWidgets);
      expect(find.text('La Directrice Administrative'), findsWidgets);
      expect(find.text('TOTAL'), findsNWidgets(2)); // l'en-tête de la colonne et la ligne de total
    });
  });

  group('m10-stats-permanences', () {
    casM14('ouverture : permanences du mois arrêté au jour, comptées comme la maquette', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-permanences', horloge: _auj16);
      final k = kpis(t);
      expect([k['Permanences assurées'], k['Agents concernés'], k['Moyenne par agent'], k['Le plus sollicité']], ['51', '8', '6.4', 'ISSA Rabiatou']);
      expect(indices(t)['Le plus sollicité'], '7 permanence(s)');
      final c = cas('permanences').first;
      expect(find.textContaining(norm(c['note']).split(' — ').first), findsOneWidget);
      expect(find.textContaining('La permanence court de 08h à 18h ; la garde de vingt-quatre heures est comptée sur son propre écran.'), findsOneWidget);
      expect(find.text('Permanences par agent'), findsOneWidget);
      expect(find.text('Permanences par service'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Statistiques de garde'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Planning'), findsOneWidget);
    });

    casM14('un service : les permanences de l\'accueil seulement ; un service sans permanence : « — »', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-permanences', horloge: _auj16);
      await regler(t, 'arret', '2026-08-31');
      await regler(t, 'service', 'Accueil');
      var k = kpis(t);
      expect([k['Permanences assurées'], k['Agents concernés'], k['Moyenne par agent'], k['Le plus sollicité']], ['34', '4', '8.5', 'SAMBIENI Marguerite']);
      await regler(t, 'service', 'Comptabilité');
      k = kpis(t);
      expect([k['Permanences assurées'], k['Agents concernés'], k['Moyenne par agent'], k['Le plus sollicité']], ['0', '0', '0', '—']);
      expect(find.text('Permanences par agent'), findsNothing);
    });

    casM14('la périodicité « jour » : la journée arrêtée seulement', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-permanences', horloge: _auj16);
      await regler(t, 'periode', 'jour');
      final k = kpis(t);
      expect([k['Permanences assurées'], k['Agents concernés'], k['Moyenne par agent']], ['1', '1', '1.0']);
      expect(find.textContaining('Journée du 16/08/2026'), findsOneWidget);
    });

    casM14('« Imprimer l\'état » : la ligne de total porte la somme des permanences', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-permanences', horloge: _auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’état'));
      expect(find.text('Statistiques des permanences'), findsWidgets);
      expect(find.text('51'), findsWidgets);
      expect(find.text('Le Surveillant'), findsWidgets);
      expect(find.text('La Directrice de l’Administration et des Finances'), findsWidgets);
    });
  });

  group('m10-stats-presence', () {
    casM14('ouverture : taux global, retards, absences, service le plus assidu — sur trente jours', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-presence', horloge: _auj16);
      final k = kpis(t);
      expect(norm(k['Taux de présence global']), '94.5 %');
      expect([k['Retards'], k['Absences'], k['Service le plus assidu']], ['93', '61', 'Comptabilité']);
      final c = cas('presenceService').first;
      final vk = [for (final x in (c['kpis'] as List)) (x as Map)['valeur']];
      expect([norm(k['Taux de présence global']), k['Retards'], k['Absences'], k['Service le plus assidu']], [vk[0], vk[1], vk[2], vk[3]]);
      expect(find.textContaining('journée(s) pointée(s) sur la période, pour 9 service(s).'), findsOneWidget);
      expect(find.text('Taux de présence par service'), findsWidgets);
      expect(find.text('Présents, retards et absences par service'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Registre des présences'), findsOneWidget);
      expect(t.widget<TableauSigh>(find.byType(TableauSigh)).lignes.length, 9);
    });

    casM14('une plage sans pointage : « — », aucun graphique, aucun service', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-presence', horloge: _auj16);
      await regler(t, 'du', '2030-01-01');
      await regler(t, 'au', '2030-01-31');
      final k = kpis(t);
      expect([k['Taux de présence global'], k['Retards'], k['Absences'], k['Service le plus assidu']], ['—', '0', '0', '—']);
      expect(find.text('Présents, retards et absences par service'), findsNothing);
    });

    casM14('« Trente derniers jours » remet la plage de l\'horloge du poste', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-presence', horloge: _auj16);
      await regler(t, 'du', '2026-08-10');
      await regler(t, 'au', '2026-08-16');
      expect(norm(kpis(t)['Taux de présence global']), '94.2 %');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Trente derniers jours'));
      expect(norm(kpis(t)['Taux de présence global']), '94.5 %');
    });

    casM14('« Imprimer l\'état » : les deux signatures et le rappel de la règle du retard', (t) async {
      await ouvrirM14(t, magasinM14(), 'm10-stats-presence', horloge: _auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’état'));
      expect(find.text('Taux de présence par service'), findsWidgets);
      expect(find.textContaining('Le retard est compté comme une présence'), findsOneWidget);
      expect(find.text('Le Surveillant'), findsWidgets);
    });
  });
}
