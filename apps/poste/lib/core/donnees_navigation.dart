import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sigh_domaine/sigh_domaine.dart';

/// Ce que la coque sait de la maquette : le manifeste de navigation, la matrice des droits et l'état de parité de chaque
/// écran. Tout est ENGENDRÉ (`prototype_html/build/gen-poste-assets.js`) ; rien n'est écrit à la main.
class DonneesNavigation {
  DonneesNavigation(
      {required this.manifeste,
      required this.matrice,
      required Map<String, Map<String, Object?>> parite})
      : _parite = parite;
  final Manifeste manifeste;
  final MatriceDroits matrice;
  final Map<String, Map<String, Object?>> _parite;

  /// Tranche de portage (1 à 6) d'un écran, ou `null`.
  int? tranche(String id) => (_parite[id]?['tranche'] as num?)?.toInt();
  String statut(String id) => '${_parite[id]?['statut'] ?? 'non commencé'}';

  static DonneesNavigation depuisJson(
      {required String manifeste,
      required String rbac,
      required String parite}) {
    final p = <String, Map<String, Object?>>{
      for (final e in ((jsonDecode(parite) as Map)['ecrans'] as List))
        '${(e as Map)['id']}': e.cast<String, Object?>(),
    };
    return DonneesNavigation(
      manifeste: Manifeste.depuisJson(
          (jsonDecode(manifeste) as Map).cast<String, Object?>()),
      matrice: MatriceDroits.depuisJson(
          (jsonDecode(rbac) as Map).cast<String, Object?>()),
      parite: p,
    );
  }

  static Future<DonneesNavigation> chargerAssets() async => depuisJson(
        manifeste: await rootBundle.loadString('assets/donnees/manifeste.json'),
        rbac: await rootBundle.loadString('assets/donnees/rbac.json'),
        parite: await rootBundle.loadString('assets/donnees/parite.json'),
      );

  /// Pour les tests : lit les mêmes fichiers engendrés sur le disque.
  static DonneesNavigation depuisDossier([String dossier = 'assets/donnees']) =>
      depuisJson(
        manifeste: File('$dossier/manifeste.json').readAsStringSync(),
        rbac: File('$dossier/rbac.json').readAsStringSync(),
        parite: File('$dossier/parite.json').readAsStringSync(),
      );
}
