/// Une opération = un geste d'écriture (spec §4). Format miroir de `packages/sync/banc`.
class Operation {
  Operation({
    required this.id,
    required this.appareil,
    required this.epoch,
    required this.hlc,
    required this.collection,
    required this.fiche,
    required this.type,
    required this.champs,
    this.vu = const {},
    this.bail = false,
  });

  /// UUID v7, créé par l'appareil ; sert de clé d'idempotence.
  final String id;
  final String appareil;
  final int epoch;

  /// Horloge logique hybride (ms) : jamais l'ordre d'application (c'est le `seq` de la mère).
  final int hlc;
  final String collection;
  final String fiche;

  /// creer | modifier | archiver | restaurer | sortie. Jamais « supprimer » (RG-14).
  final String type;
  final Map<String, Object?> champs;

  /// Pour chaque champ modifié : le `seq` de la dernière version vue par l'appareil.
  final Map<String, int> vu;
  final bool bail;

  Map<String, Object?> toJson() => {
        'id': id,
        'appareil': appareil,
        'epoch': epoch,
        'hlc': hlc,
        'collection': collection,
        'fiche': fiche,
        'type': type,
        'champs': champs,
        'vu': vu,
        if (bail) 'bail': true,
      };

  static Operation fromJson(Map<String, Object?> j) => Operation(
        id: j['id']! as String,
        appareil: j['appareil']! as String,
        epoch: j['epoch']! as int,
        hlc: j['hlc']! as int,
        collection: j['collection']! as String,
        fiche: j['fiche']! as String,
        type: j['type']! as String,
        champs: Map<String, Object?>.from(j['champs']! as Map),
        vu: Map<String, int>.from((j['vu'] ?? const {}) as Map),
        bail: (j['bail'] ?? false) as bool,
      );
}
