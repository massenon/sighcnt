import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart' show famillesPair, DroitsOperation, collectionsPairSansPontPoste;
import 'package:sigh_sync/sigh_sync.dart';

import '../donnees/magasin.dart';
import 'pont_activite.dart' show PontActivite, TransportPont;
import 'transport_pair.dart';

/// Le moteur d'échange ENTRE PAIRS (ADR-0006) embarqué dans le poste : même code que le banc (`packages/sync_dart`). Le relais ne voit que des enveloppes chiffrées ;
/// la règle de fusion (domaine) tourne ICI, sur chaque poste. Les conflits marqués sont recopiés dans la collection LOCALE `conflitsPair` (jamais synchronisée :
/// chaque poste les recalcule du même ensemble d'opérations) d'où le centre de notifications les annonce, avec le son, à la personne habilitée.
class MoteurPair {
  MoteurPair._(this._pair, this._magasin);
  final FileulPair _pair;
  final Magasin _magasin;
  Timer? _miroir;

  static MoteurPair creer({required Magasin magasin, required String dbChemin, required String relais, required String cleHex, String nom = 'poste', DroitsOperation? droits}) =>
      MoteurPair._(FileulPair(ConfigPair(port: 0, relais: relais, dbChemin: dbChemin, cleHex: cleHex, nom: nom, droits: droits, collectionsCopie: collectionsDuPont)), magasin);

  /// Pour les tests : un moteur sur un [FileulPair] déjà construit.
  factory MoteurPair.pour(FileulPair pair, Magasin magasin) => MoteurPair._(pair, magasin);

  void demarrer({Duration miroir = const Duration(seconds: 3)}) {
    unawaited(_pair.boucle());
    _miroir = Timer.periodic(miroir, (_) => recopierConflits());
  }

  /// Consomme le code d'appairage délivré par le relais (à usage unique). Refus nommé (`StateError`) si le relais refuse ou ne répond pas.
  Future<void> appairer(String code) async {
    final (statut, corps) = await _pair.commande('POST /appairer', {'code': code});
    if (statut >= 400) throw StateError('appairage refusé (${(corps as Map?)?['code'] ?? statut})');
  }

  /// Le jeton d'appareil auprès du relais (`null` tant que le poste n'est pas appairé).
  String? get jeton => _pair.base.meta('jeton');

  bool get appaire => _pair.etat()['uuid'] != null;

  /// Le moteur du poste parle au relais ; le pont d'activité écrit et lit par lui. [role] : le rôle de l'agent connecté.
  /// Il ne porte QUE les collections de famille A (fiches à fusion par champ) : les autres familles (pièces émises, stock, flux de travail) ont leurs règles
  /// propres, et celles que la règle de fusion ne connaît pas seraient refusées une à une. Les écrire champ à champ les corromprait.
  static Set<String> get collectionsDuPont => {for (final e in famillesPair.entries) if (e.value == 'A') e.key}.difference(collectionsPairSansPontPoste);

  PontActivite pont({required String Function() role}) =>
      PontActivite(_magasin, transport(role: role), collections: collectionsDuPont, etiquette: '${_pair.etat()['uuid'] ?? 'pair'}'.replaceAll('-', '').padRight(6, '0').substring(0, 6));

  void arreter() => _miroir?.cancel();

  /// Rend la collection `conflitsPair` fidèle aux conflits marqués : ajoute les nouveaux, archive (RG-14, jamais de suppression) ceux que la décision a levés.
  void recopierConflits() {
    final col = _magasin.collection('conflitsPair');
    final vivants = <String>{};
    for (final c in _pair.conflits()) {
      // `fiche` porte « collection/identifiant » dans l'état fusionné
      final k = '${c['fiche']}';
      final i = k.indexOf('/');
      final collection = i < 0 ? '' : k.substring(0, i), fiche = i < 0 ? k : k.substring(i + 1);
      final cle = '$k:${c['champ']}';
      vivants.add(cle);
      if (col.actives.any((f) => f['cle'] == cle)) continue;
      col.inserer({
        'statut': 'actif',
        'cle': cle,
        'collection': collection,
        'fiche': fiche,
        'champ': c['champ'],
        'a': c['a'],
        'b': c['b'],
        'valeurs': '${c['a']} / ${c['b']}',
      });
    }
    for (final f in col.actives.toList()) {
      if (!vivants.contains(f['cle'])) col.archiver('${f['id']}');
    }
  }

  /// La personne habilitée TRANCHE : la valeur choisie s'écrit par une opération `trancher` (droit vérifié à l'émission, refus nommé `Err` sinon) ; le conflit
  /// se lève chez tous les postes quand l'opération leur parvient. [role] : le rôle de l'agent connecté.
  void trancher(Map<String, Object?> conflit, Object? valeur, {required String role}) {
    _pair.emettre({'collection': conflit['collection'], 'fiche': conflit['fiche'], 'type': 'trancher', 'champs': {conflit['champ'] as String: valeur}, 'role': role});
    recopierConflits();
  }

  /// Le transport du pont d'activité : les écritures du poste deviennent des opérations pair.
  TransportPont transport({required String Function() role}) => TransportPair(_pair, role);

  Map<String, Object?> etat() => _pair.etat();
}
