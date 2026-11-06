import 'package:flutter/foundation.dart';

/// Ce que l'écran « Échanges entre postes » lit du moteur pair, sans jamais l'importer : une valeur observable. `main.dart` la nourrit depuis `MoteurPair.etat()`.
class InstantanePair {
  const InstantanePair({this.appaire = false, this.horsLigne = false, this.enAttente = 0, this.cycles = 0});
  final bool appaire, horsLigne;
  final int enAttente, cycles;

  @override
  bool operator ==(Object o) => o is InstantanePair && o.appaire == appaire && o.horsLigne == horsLigne && o.enAttente == enAttente && o.cycles == cycles;
  @override
  int get hashCode => Object.hash(appaire, horsLigne, enAttente, cycles);

  static InstantanePair depuis(Map<String, Object?> etat) => InstantanePair(
      appaire: etat['uuid'] != null,
      horsLigne: etat['hors_ligne'] == true,
      enAttente: (etat['en_attente'] as num?)?.toInt() ?? 0,
      cycles: (etat['cycles'] as num?)?.toInt() ?? 0);
}

/// Les deux branchements de l'écran de réglage : le dossier où vit `pair.json`, et l'état du moteur s'il tourne. Posés par `main.dart` ; absents (tests, poste
/// sans dossier), l'écran le dit au lieu de deviner.
class EtatPairPoste {
  const EtatPairPoste._();
  static String? dossier;
  static ValueListenable<InstantanePair>? source;

  /// Le jeton d'appareil du poste auprès du relais (posé par `main` quand le mode pair tourne et que le poste est appairé) : l'envoi du coffre par courriel s'en sert.
  static String? Function()? jeton;
}
