import 'dart:async';

import 'package:sigh_sync/sigh_sync.dart';

import 'source_sync.dart';

/// Le moteur de synchronisation d'un poste FILEUL embarqué dans l'application (même code que le banc d'essai :
/// `packages/sync_dart`). Il lit/écrit sa base locale, parle à la mère en HTTP et rattrape seul après une coupure.
/// L'interface n'en connaît que ces trois gestes : appairer, lire l'état, s'arrêter.
class MoteurFileul {
  MoteurFileul._(this._fileul);
  final Fileul _fileul;

  /// `dbChemin` = fichier SQLite du poste (`:memory:` en test). `mere` = adresse de la mère, ex. `http://192.168.1.10:9000`.
  static MoteurFileul creer(
      {required String dbChemin, required String mere, String nom = 'poste'}) {
    final f =
        Fileul(ConfigFileul(port: 0, mere: mere, dbChemin: dbChemin, nom: nom));
    return MoteurFileul._(f);
  }

  /// Lance la boucle de synchronisation (sans serveur de commande : l'application n'expose aucun port).
  void demarrer() => unawaited(_fileul.boucle());

  String get uuid => _fileul.uuid;

  Future<void> appairer(String code) async {
    final (statut, corps) =
        await _fileul.commande('POST /appairer', {'code': code}, const {});
    if (statut >= 400) {
      final c = corps is Map ? corps : const {};
      throw StateError(
          '${c['code'] ?? 'appairage_refuse'}${c['motif'] != null ? ' — ${c['motif']}' : ''}');
    }
  }

  Future<InstantaneSync> instantane() async {
    final (_, corps) = await _fileul.commande('GET /etat', const {}, const {});
    return InstantaneSync.depuisEtat((corps! as Map).cast<String, Object?>());
  }

  SourceSyncPeriodique source(
          {Duration intervalle = const Duration(seconds: 2)}) =>
      SourceSyncPeriodique(lire: instantane, intervalle: intervalle);
}
