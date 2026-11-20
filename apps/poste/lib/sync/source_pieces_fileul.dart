import 'package:sigh_sync/sigh_sync.dart';

import 'transcription_mobile.dart';

/// La base de synchronisation du poste fileul (`Fileul` de `packages/sync_dart`), vue par le service de transcription : même moteur que le banc d'essai.
class SourcePiecesFileul implements SourcePiecesMobile {
  SourcePiecesFileul(this._f);
  final Fileul _f;

  @override
  Future<List<PieceSync>> liste(String collection) async {
    final (_, c) = await _f.commande('GET /liste', const {}, {'collection': collection});
    return [
      for (final x in (c! as List))
        PieceSync('${(x as Map)['id']}', ((x['data'] ?? const {}) as Map).cast<String, Object?>(), archive: x['archive'] == true)
    ];
  }

  @override
  Future<String> creer(String collection, Map<String, Object?> champs) async {
    final (_, c) = await _f.commande('POST /ecrire', {'type': 'creer', 'collection': collection, 'champs': champs}, const {});
    return '${(c! as Map)['fiche']}';
  }
}
