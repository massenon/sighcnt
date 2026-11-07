import 'dart:convert';

import 'package:sigh_sync/sigh_sync.dart';

import 'pont_activite.dart' show TransportPont;
import 'transcription_mobile.dart' show PieceSync;

/// Le transport du pont d'activité en MODE PAIR (ADR-0006) : lire = relire l'état FUSIONNÉ par la règle du domaine ; écrire = émettre une opération signée par le
/// rôle de l'agent. Rien ne passe par la mère. Seules les valeurs qui CHANGENT partent, avec la version vue de chaque champ : c'est ce qui distingue une
/// modification faite en connaissance de cause d'une écriture concurrente (qui, elle, reste marquée).
class TransportPair implements TransportPont {
  TransportPair(this._pair, this._role);
  final FileulPair _pair;
  final String Function() _role;

  @override
  Future<List<PieceSync>> liste(String collection) async {
    final fiches = _pair.etatActuel().fiches;
    return [
      for (final e in fiches.entries)
        if (e.key.startsWith('$collection/'))
          PieceSync(e.key.substring(collection.length + 1), (e.value['data'] as Map).cast<String, Object?>(), archive: e.value['archive'] == true)
    ];
  }

  @override
  Future<void> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    final courant = _pair.etatActuel().fiches['$collection/$fiche'];
    if (courant == null) {
      _pair.emettre({'collection': collection, 'fiche': fiche, 'type': 'creer', 'champs': champs, 'role': _role()});
      return;
    }
    final data = (courant['data'] as Map).cast<String, Object?>();
    final hlcs = (courant['hlc'] as Map).cast<String, Object?>();
    final changes = {for (final e in champs.entries) if (jsonEncode(data[e.key]) != jsonEncode(e.value)) e.key: e.value};
    if (changes.isEmpty) return;
    _pair.emettre({
      'collection': collection,
      'fiche': fiche,
      'type': 'modifier',
      'champs': changes,
      'vu': {for (final k in changes.keys) k: hlcs[k] ?? 0},
      'role': _role(),
    });
  }
}
