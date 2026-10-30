import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

typedef Fiche = Map<String, Object?>;

/// Une collection du magasin (`S.collection(nom)` de la maquette) : fiches actives / archivées, archivage LOGIQUE annulable (RG-14 : jamais de
/// suppression physique). Lecture SYNCHRONE — c'est ce qui permet aux écrans de se composer comme ceux de la maquette.
///
/// C'est la COUTURE vers la persistance : ce magasin est en mémoire, hydraté depuis le jeu de démonstration ; la base locale et le journal
/// d'opérations (plan S4) viendront derrière la même interface sans toucher aux écrans.
class CollectionMagasin extends ChangeNotifier {
  CollectionMagasin(this.nom, Iterable<Fiche> fiches)
      : _fiches = [
          for (final f in fiches) {...f}
        ];
  final String nom;
  final List<Fiche> _fiches;

  static bool estArchivee(Fiche f) => f['statut'] == 'archive';

  List<Fiche> get actives => [
        for (final f in _fiches)
          if (!estArchivee(f)) f
      ];
  List<Fiche> get archivees => [
        for (final f in _fiches)
          if (estArchivee(f)) f
      ];
  List<Fiche> get toutes => List.unmodifiable(_fiches);
  Fiche? parId(Object? id) => _fiches.where((f) => f['id'] == id).firstOrNull;

  /// Archive la fiche (`statut: 'archive'`, ancien statut conservé) et rend la fonction qui ANNULE — une annulation doit être possible
  /// et visible (CLAUDE.md, « quatre pièges »).
  VoidCallback archiver(Object? id) {
    final f = parId(id);
    if (f == null || estArchivee(f)) return () {};
    f['statutAvantArchivage'] = f['statut'];
    f['statut'] = 'archive';
    notifyListeners();
    return () => restaurer(id);
  }

  void restaurer(Object? id) {
    final f = parId(id);
    if (f == null || !estArchivee(f)) return;
    final avant = f.remove('statutAvantArchivage');
    if (avant == null) {
      f.remove('statut');
    } else {
      f['statut'] = avant;
    }
    notifyListeners();
  }
}

class Magasin {
  Magasin([Map<String, Iterable<Fiche>> jeux = const {}])
      : _c = {
          for (final e in jeux.entries) e.key: CollectionMagasin(e.key, e.value)
        };
  final Map<String, CollectionMagasin> _c;

  /// Une collection absente est VIDE, jamais une erreur : l'écran dit « aucun enregistrement » (état vide), comme la maquette.
  CollectionMagasin collection(String nom) =>
      _c.putIfAbsent(nom, () => CollectionMagasin(nom, const []));

  static List<Fiche> _lire(String json) => [
        for (final f in jsonDecode(json) as List)
          (f as Map).cast<String, Object?>()
      ];

  static Future<Magasin> depuisAssets(List<String> noms,
          [String dossier = 'assets/donnees/jeu']) async =>
      Magasin({
        for (final n in noms)
          n: _lire(await rootBundle.loadString('$dossier/$n.json'))
      });

  /// Pour les tests : mêmes fichiers, lus sur le disque.
  static Magasin depuisDossier(List<String> noms,
          [String dossier = 'assets/donnees/jeu']) =>
      Magasin({
        for (final n in noms)
          n: _lire(File('$dossier/$n.json').readAsStringSync())
      });

  /// Collections que les écrans portés lisent (le jeu est engendré par `prototype_html/build/gen-poste-jeu.js`).
  static const collectionsDuJeu = ['factures', 'patients', 'avoirs'];
}
