// Les vecteurs de la barre supérieure, tirés de la maquette RÉELLE (`prototype_html/build/vecteurs-barre.js`, horloge figée au 16/08/2026 12:00) :
// moteur de notifications rôle par rôle, recherche globale, actions rapides. Le jeu de la sonde voyage avec les vecteurs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';
import 'package:sigh_poste/shell/recherche_globale.dart';

Map<String, Object?> m_(Object? x) => (x as Map).cast<String, Object?>();
List<Map<String, Object?>> l_(Object? x) => [for (final e in (x as List)) m_(e)];

final v = m_(jsonDecode(File('../../packages/domaine/test/vecteurs/barre.json').readAsStringSync()));
final donnees = DonneesNavigation.depuisDossier();
final horloge = DateTime.parse(v['horloge'] as String);

Magasin magasinDeLaSonde() {
  final jeu = m_(v['jeu']);
  final ref = m_(jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()));
  return Magasin({for (final e in jeu.entries) e.key: l_(e.value)}, 'POSTE', ref);
}

void main() {
  final roles = [for (final r in (v['roles'] as List)) '$r'];

  test('le moteur de notifications rend, rôle par rôle, la liste de la maquette (routage, regroupement au-delà de 3, ordre)', () {
    final m = magasinDeLaSonde();
    var lignes = 0;
    for (final r in roles) {
      final centre = CentreNotifications(magasin: m, donnees: () => donnees, role: () => r, horloge: () => horloge);
      final obtenu = [
        for (final n in centre.collecter().where((n) => n.categorie == 'metier'))
          {'source': n.source, 'domaine': n.domaine, 'priorite': n.priorite, 'titre': n.titre, 'detail': n.detail, 'lien': n.lien, 'groupe': n.groupe, 'nombre': n.nombre}
      ];
      final attendu = [
        for (final n in l_(m_(v['notifications'])[r]))
          {
            'source': n['source'],
            'domaine': n['domaine'],
            'priorite': n['priorite'],
            'titre': n['titre'],
            'detail': n['detail'],
            'lien': n['lien'],
            'groupe': n['groupe'],
            'nombre': n['nombre']
          }
      ];
      expect(obtenu, attendu, reason: 'notifications du rôle $r');
      lignes += attendu.length;
      centre.dispose();
    }
    expect(lignes, greaterThan(40), reason: 'la sonde doit couvrir des lignes de chaque source');
  });

  test('un seuil de regroupement : trois articles sous le seuil donnent UNE ligne, un seul reste nommé', () {
    final m = magasinDeLaSonde();
    final centre = CentreNotifications(magasin: m, donnees: () => donnees, role: () => 'stock', horloge: () => horloge);
    final stock = centre.collecter().where((n) => n.source == 'stock_seuil').toList();
    expect(stock.map((n) => n.nombre).toList()..sort(), [1, 3]);
    expect(stock.firstWhere((n) => n.groupe).titre, startsWith('3 article(s)'));
  });

  test('les actions rapides sont celles de la maquette, filtrées par les droits du rôle', () {
    for (final r in roles) {
      final attendu = [for (final a in l_(m_(v['actions'])[r])) a['ecran']];
      final obtenu = [
        for (final a in donnees.barre.actions)
          if (ecranOuvertAuRole(donnees, r, a.ecran)) a.ecran
      ];
      expect(obtenu, attendu, reason: 'actions du rôle $r');
    }
  });

  test('la recherche globale rend les mêmes groupes, les mêmes libellés, les mêmes cibles (écran et onglet) que la maquette', () {
    final m = magasinDeLaSonde();
    var requetes = 0, resultats = 0;
    for (final r in m_(v['recherche']).entries) {
      for (final q in m_(r.value).entries) {
        final obtenu = [
          for (final g in rechercheGlobale(requete: q.key, role: r.key, nav: donnees, magasin: m))
            {
              'groupe': g.groupe,
              'resultats': [
                for (final x in g.resultats) {'label': x.label, 'detail': x.detail, 'icone': x.icone, 'ecran': x.ecran, 'onglet': x.onglet}
              ]
            }
        ];
        expect(jsonDecode(jsonEncode(obtenu)), jsonDecode(jsonEncode(q.value)), reason: 'recherche « ${q.key} » sous ${r.key}');
        requetes++;
        resultats += obtenu.fold<int>(0, (a, g) => a + (g['resultats'] as List).length);
      }
    }
    expect(requetes, greaterThan(100));
    expect(resultats, greaterThan(100));
  });

  test('une requête de moins de deux caractères ne cherche rien', () {
    expect(rechercheGlobale(requete: 'p', role: 'admin', nav: donnees, magasin: magasinDeLaSonde()), isEmpty);
  });
}
