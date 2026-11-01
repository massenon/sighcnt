import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'referentiel_barre.dart';

/// Ce que la coque sait de la maquette : le manifeste de navigation, la matrice des droits et l'état de parité de chaque
/// écran. Tout est ENGENDRÉ (`prototype_html/build/gen-poste-assets.js`) ; rien n'est écrit à la main.
class DonneesNavigation {
  DonneesNavigation(
      {required this.manifeste,
      required this.matrice,
      required Map<String, Map<String, Object?>> parite,
      this.referenceRbac,
      this.referenceModules,
      this.barre = const ReferentielBarre(),
      Map<String, Map<String, bool>> modulesVoir = const {},
      Map<String, ({String titre, String description})> descriptions = const {}})
      : _parite = parite,
        _modulesVoir = modulesVoir,
        _descriptions = descriptions;

  /// Droit de VOIR un module, par rôle, tel que la matrice engendrée le porte (`matriceModules` de `rbac.json`). Sert à décider si la page d'accueil d'un module
  /// (hub) est ouverte au rôle ; une décision prise à chaud sur un module n'y est pas relue (les écrans, eux, suivent la matrice à chaud).
  final Map<String, Map<String, bool>> _modulesVoir;

  /// Le module est-il ouvert au rôle ? Inconnu (matrice sans modules) : réputé ouvert, ce sont alors les écrans qui décident.
  bool moduleVisible(String role, String code) => _modulesVoir.isEmpty ? true : (_modulesVoir[role]?[code] ?? false);

  /// Rubriques de la recherche globale et actions rapides de la barre supérieure (engendrées depuis `nav.js`).
  final ReferentielBarre barre;
  final Manifeste manifeste;

  /// La matrice EN FORCE : celle de `rbac.json` (engendrée), ou la matrice superposée à chaud par [aChaud].
  final MatriceDroits matrice;
  final Map<String, Map<String, Object?>> _parite;

  /// Titre et description de chaque écran, repris de la déclaration de l'écran dans la maquette (`ecrans-descriptions.json`, engendré) : les cartes
  /// des pages d'accueil de module (hubs) les affichent.
  final Map<String, ({String titre, String description})> _descriptions;

  /// Titre de la déclaration de l'écran (vide si la maquette n'en donne pas : on retombe sur l'intitulé du manifeste).
  String? titreDeclare(String id) {
    final t = _descriptions[id]?.titre;
    return t == null || t.isEmpty ? null : t;
  }

  /// Description de la déclaration de l'écran, `null` si la maquette n'en porte aucune.
  String? descriptionDeclaree(String id) {
    final d = _descriptions[id]?.description;
    return d == null || d.isEmpty ? null : d;
  }

  /// Les fiches que la matrice engendrée a connues au jour de l'extraction (le jeu livré : collections `rbac` et `modulesActifs`). Elles sont la
  /// RÉFÉRENCE de la superposition : seul ce qui a changé depuis elles remplace la matrice engendrée. `null` = inconnues, aucune superposition.
  final List<Map<String, Object?>>? referenceRbac, referenceModules;

  /// Les mêmes données de navigation sous une autre matrice (manifeste, parité et références partagés).
  DonneesNavigation avecMatrice(MatriceDroits m) =>
      DonneesNavigation(manifeste: manifeste, matrice: m, parite: _parite, referenceRbac: referenceRbac, referenceModules: referenceModules, barre: barre, modulesVoir: _modulesVoir, descriptions: _descriptions);

  /// DROITS À CHAUD (A4) : la matrice engendrée reste la BASE ; les fiches de la collection `rbac` (surcharges par rôle, module et écran, rôles
  /// archivés ou créés) et de `modulesActifs` (activités fermées) du magasin la superposent, comme `N.can()` de la maquette, pour tout ce qui a changé
  /// depuis les fiches de l'extraction (`superposerDroits`). Fiches inchangées, matrice inchangée ; une décision saisie depuis m14-roles ou cfg-modules
  /// (ou rechargée du magasin persisté) est effective aussitôt. Références inconnues ou collections vides : la matrice engendrée reste en force.
  DonneesNavigation aChaud(Magasin m) {
    final rbac = m.collection('rbac').toutes;
    final modules = m.collection('modulesActifs').toutes;
    if ((referenceRbac == null && referenceModules == null) || (rbac.isEmpty && modules.isEmpty)) return this;
    return avecMatrice(superposerDroits(matrice, manifeste,
        rbac: rbac, modulesActifs: modules, referenceRbac: referenceRbac ?? const [], referenceModules: referenceModules ?? const []));
  }

  /// Tranche de portage (1 à 6) d'un écran, ou `null`.
  int? tranche(String id) => (_parite[id]?['tranche'] as num?)?.toInt();
  String statut(String id) => '${_parite[id]?['statut'] ?? 'non commencé'}';

  static List<Map<String, Object?>>? _fiches(String? json) =>
      json == null ? null : [for (final f in (jsonDecode(json) as List)) (f as Map).cast<String, Object?>()];

  /// `fichesRbac` / `fichesModules` : le jeu livré (`jeu/rbac.json`, `jeu/modulesActifs.json`), RÉFÉRENCE de la superposition à chaud.
  static DonneesNavigation depuisJson(
      {required String manifeste,
      required String rbac,
      required String parite,
      String? fichesRbac,
      String? fichesModules,
      String? rubriques,
      String? descriptions}) {
    final p = <String, Map<String, Object?>>{
      for (final e in ((jsonDecode(parite) as Map)['ecrans'] as List))
        '${(e as Map)['id']}': e.cast<String, Object?>(),
    };
    return DonneesNavigation(
      manifeste: Manifeste.depuisJson(
          (jsonDecode(manifeste) as Map).cast<String, Object?>()),
      matrice: MatriceDroits.depuisJson(
          (jsonDecode(rbac) as Map).cast<String, Object?>()),
      modulesVoir: _modulesVoirDe(rbac),
      parite: p,
      referenceRbac: _fiches(fichesRbac),
      referenceModules: _fiches(fichesModules),
      barre: rubriques == null ? const ReferentielBarre() : ReferentielBarre.depuisJson(rubriques),
      descriptions: descriptions == null
          ? const {}
          : {
              for (final e in ((jsonDecode(descriptions) as Map)['ecrans'] as Map).entries)
                '${e.key}': (titre: '${(e.value as Map)['titre'] ?? ''}', description: '${(e.value as Map)['description'] ?? ''}')
            },
    );
  }

  static Future<DonneesNavigation> chargerAssets() async => depuisJson(
        manifeste: await rootBundle.loadString('assets/donnees/manifeste.json'),
        rbac: await rootBundle.loadString('assets/donnees/rbac.json'),
        parite: await rootBundle.loadString('assets/donnees/parite.json'),
        fichesRbac: await rootBundle.loadString('assets/donnees/jeu/rbac.json'),
        fichesModules: await rootBundle.loadString('assets/donnees/jeu/modulesActifs.json'),
        rubriques: await rootBundle.loadString('assets/donnees/rubriques.json'),
        descriptions: await rootBundle.loadString('assets/donnees/ecrans-descriptions.json'),
      );

  /// Pour les tests : lit les mêmes fichiers engendrés sur le disque.
  static DonneesNavigation depuisDossier([String dossier = 'assets/donnees']) =>
      depuisJson(
        manifeste: File('$dossier/manifeste.json').readAsStringSync(),
        rbac: File('$dossier/rbac.json').readAsStringSync(),
        parite: File('$dossier/parite.json').readAsStringSync(),
        fichesRbac: _lireSiPresent('$dossier/jeu/rbac.json'),
        fichesModules: _lireSiPresent('$dossier/jeu/modulesActifs.json'),
        rubriques: _lireSiPresent('$dossier/rubriques.json'),
        descriptions: _lireSiPresent('$dossier/ecrans-descriptions.json'),
      );

  static Map<String, Map<String, bool>> _modulesVoirDe(String rbac) {
    final m = (jsonDecode(rbac) as Map)['matriceModules'];
    if (m is! Map) return const {};
    return {
      for (final r in m.entries)
        '${r.key}': {
          for (final c in (r.value as Map).entries) '${c.key}': (c.value as Map)['voir'] == true || (c.value as Map)['horsMatrice'] == true
        }
    };
  }

  static String? _lireSiPresent(String chemin) => File(chemin).existsSync() ? File(chemin).readAsStringSync() : null;
}
