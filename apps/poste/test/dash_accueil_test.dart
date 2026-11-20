import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-receptionniste` et `dash-admin-agent` : comparés au relevé des écrans réels.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('dash-receptionniste', () {
    final v = obj(vecteurs()['dash-receptionniste']);

    testWidgets('relevé de la maquette : file en attente, indicateurs, rendez-vous du jour, onze parcours', (t) async {
      await ouvrir(t, magasin(), 'dash-receptionniste', role: 'reception');
      comparer(t, v);
      expect(find.byKey(const Key('tba:parcours:Nouveau patient')), findsOneWidget);
      final groupes = liste(cartesVecteur(v).firstWhere((c) => c['parcours'] != null)['parcours']);
      expect(groupes.length, 11, reason: 'les onze chaînes dictées par la Direction');
      await finir(t);
    });

    testWidgets('les six accès rapides précèdent les parcours, et ils précèdent les indicateurs', (t) async {
      await ouvrir(t, magasin(), 'dash-receptionniste', role: 'reception');
      double haut(Finder f) => t.getTopLeft(f.first).dy;
      expect(haut(find.text('Répertoire patient')), lessThan(haut(find.text('Ce que vous faites ici — les parcours de l’accueil'))));
      expect(haut(find.text('Ce que vous faites ici — les parcours de l’accueil')), lessThan(haut(find.text('Dossiers créés ce mois'))));
      await finir(t);
    });

    testWidgets('sans rendez-vous du jour : l\'état vide le dit', (t) async {
      await ouvrir(t, magasin(), 'dash-receptionniste', role: 'reception', le: DateTime(2026, 10, 30, 10));
      expect(find.text('Aucun rendez-vous programmé aujourd’hui.'), findsOneWidget);
      await finir(t);
    });

    testWidgets('personne n\'attend : la phrase positive, sans lien', (t) async {
      final m = magasin();
      for (final x in m.collection('fileAttente').actives.toList()) {
        m.collection('fileAttente').mettreAJour(x['id'], {'etat': 'termine'});
      }
      await ouvrir(t, m, 'dash-receptionniste', role: 'reception');
      expect(find.text('Personne n’attend à l’accueil.'), findsOneWidget);
      await finir(t);
    });
  });

  group('dash-admin-agent', () {
    final v = obj(vecteurs()['dash-admin-agent']);

    testWidgets('relevé de la maquette : courriers à traiter, indicateurs comptés, notes de service', (t) async {
      await ouvrir(t, magasin(), 'dash-admin-agent', role: 'agentadmin');
      comparer(t, v);
      await finir(t);
    });

    testWidgets('les indicateurs sont COMPTÉS : un courrier traité sort du premier regard', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'dash-admin-agent', role: 'agentadmin');
      expect(find.textContaining('courrier(s) — restent à traiter'), findsOneWidget);
      for (final x in m.collection('courriers').actives.toList()) {
        m.collection('courriers').mettreAJour(x['id'], {'traitement': 'traite'});
      }
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Aucun courrier en attente.'), findsOneWidget);
      await finir(t);
    });
  });
}
