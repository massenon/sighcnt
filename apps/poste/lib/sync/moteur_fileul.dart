import 'dart:async';

import 'package:sigh_sync/sigh_sync.dart';

import 'source_pieces_fileul.dart';
import 'source_sync.dart';
import 'transcription_mobile.dart';

/// Le moteur de synchronisation d'un poste FILEUL embarqué dans l'application (même code que le banc d'essai :
/// `packages/sync_dart`). Il lit/écrit sa base locale, parle à la mère en HTTP et rattrape seul après une coupure.
/// L'interface n'en connaît que ces trois gestes : appairer, lire l'état, s'arrêter.
class MoteurFileul {
  MoteurFileul._(this._fileul);
  final Fileul _fileul;

  /// `dbChemin` = fichier SQLite du poste (`:memory:` en test). `mere` = adresse de la mère, ex. `http://192.168.1.10:9000`.
  static MoteurFileul creer(
      {required String dbChemin, required String mere, String nom = 'poste', String cleStockage = ''}) {
    final f =
        Fileul(ConfigFileul(port: 0, mere: mere, dbChemin: dbChemin, nom: nom, cleStockage: cleStockage));
    return MoteurFileul._(f);
  }

  /// Lance la boucle de synchronisation (sans serveur de commande : l'application n'expose aucun port).
  void demarrer() => unawaited(_fileul.boucle());

  String get uuid => _fileul.uuid;

  /// La base de synchronisation du poste, vue par la transcription des prescriptions du mobile (E1559).
  SourcePiecesMobile get pieces => SourcePiecesFileul(_fileul);

  /// Rattache ce poste à la mère d'une clinique : redirige le moteur vers [adresse], puis consomme le code d'appairage. Refus nommé (`StateError`) si la mère
  /// refuse (code expiré, déjà utilisé…) ou ne répond pas.
  Future<void> rattacher(String adresse, String code) async {
    _fileul.rediriger(adresse);
    await appairer(code);
  }

  /// Les fiches d'une collection telles que la mère les a diffusées (état confirmé du fileul).
  Future<List<PieceSync>> liste(String collection) => pieces.liste(collection);

  /// Écrit une fiche dans le journal du poste (`creer` si la fiche est nouvelle, `modifier` sinon) ; un refus nommé de la file locale lève `StateError`.
  Map<String, Object?> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) {
    final r = _fileul.ecrire({'collection': collection, 'fiche': fiche, 'type': existe ? 'modifier' : 'creer', 'champs': champs});
    if (r['refus'] != null) throw StateError('${r['motif'] ?? r['refus']}');
    return r;
  }

  /// Demande à la mère une PLAGE de numéros de dossier (RG-01) ; rend `(début, fin)`. Refus nommé (`StateError`) si la mère ne répond pas ou refuse.
  Future<(int, int)> demanderPlage({int taille = 50, int minimum = 0}) async {
    final (statut, corps) = await _fileul.commande('POST /plage', {'taille': taille, 'minimum': minimum}, const {});
    if (statut >= 400 || corps is! Map) throw StateError('la mère n’a pas alloué de plage (réponse $statut)');
    return ((corps['debut'] as num).toInt(), (corps['fin'] as num).toInt());
  }

  Future<void> appairer(String code) async {
    final (statut, corps) =
        await _fileul.commande('POST /appairer', {'code': code}, const {});
    if (statut >= 400) {
      final c = corps is Map ? corps : const {};
      throw StateError(
          '${c['code'] ?? 'appairage_refuse'}${c['motif'] != null ? ' — ${c['motif']}' : ''}');
    }
  }

  /// Les opérations que la mère a REFUSÉES (code, motif, geste), pour les dire : un refus ne se perd pas en silence.
  Future<List<Map<String, Object?>>> refusees() async {
    final (_, corps) = await _fileul.commande('GET /etat', const {}, const {});
    return [for (final r in ((corps! as Map)['a_traiter'] as List? ?? const [])) (r as Map).cast<String, Object?>()];
  }

  Future<InstantaneSync> instantane() async {
    final (_, corps) = await _fileul.commande('GET /etat', const {}, const {});
    return InstantaneSync.depuisEtat((corps! as Map).cast<String, Object?>());
  }

  SourceSyncPeriodique source(
          {Duration intervalle = const Duration(seconds: 2)}) =>
      SourceSyncPeriodique(lire: instantane, intervalle: intervalle);
}
