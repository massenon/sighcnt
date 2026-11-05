import 'dart:async';

import 'package:sigh_sync/sigh_sync.dart';

import '../donnees/magasin.dart';

/// Le moteur d'échange ENTRE PAIRS (ADR-0006) embarqué dans le poste : même code que le banc (`packages/sync_dart`). Le relais ne voit que des enveloppes chiffrées ;
/// la règle de fusion (domaine) tourne ICI, sur chaque poste. Les conflits marqués sont recopiés dans la collection LOCALE `conflitsPair` (jamais synchronisée :
/// chaque poste les recalcule du même ensemble d'opérations) d'où le centre de notifications les annonce, avec le son, à la personne habilitée.
class MoteurPair {
  MoteurPair._(this._pair, this._magasin);
  final FileulPair _pair;
  final Magasin _magasin;
  Timer? _miroir;

  static MoteurPair creer({required Magasin magasin, required String dbChemin, required String relais, required String cleHex, String nom = 'poste'}) =>
      MoteurPair._(FileulPair(ConfigPair(port: 0, relais: relais, dbChemin: dbChemin, cleHex: cleHex, nom: nom)), magasin);

  /// Pour les tests : un moteur sur un [FileulPair] déjà construit.
  factory MoteurPair.pour(FileulPair pair, Magasin magasin) => MoteurPair._(pair, magasin);

  void demarrer({Duration miroir = const Duration(seconds: 3)}) {
    unawaited(_pair.boucle());
    _miroir = Timer.periodic(miroir, (_) => recopierConflits());
  }

  void arreter() => _miroir?.cancel();

  /// Rend la collection `conflitsPair` fidèle aux conflits marqués : ajoute les nouveaux, archive (RG-14, jamais de suppression) ceux que la décision a levés.
  void recopierConflits() {
    final col = _magasin.collection('conflitsPair');
    final vivants = <String>{};
    for (final c in _pair.conflits()) {
      final cle = '${c['collection']}:${c['fiche']}:${c['champ']}';
      vivants.add(cle);
      if (col.actives.any((f) => f['cle'] == cle)) continue;
      col.inserer({
        'statut': 'actif',
        'cle': cle,
        'collection': c['collection'],
        'fiche': c['fiche'],
        'champ': c['champ'],
        'valeurs': '${c['valeurs'] ?? ''}',
      });
    }
    for (final f in col.actives.toList()) {
      if (!vivants.contains(f['cle'])) col.archiver('${f['id']}');
    }
  }

  Map<String, Object?> etat() => _pair.etat();
}
