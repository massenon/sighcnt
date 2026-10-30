import 'package:flutter/material.dart';

import '../core/config_poste.dart';

/// Un module de la coque. La navigation est DÉRIVÉE du registre (comme `nav.js` pour la maquette) : aucun lien écrit à
/// la main, et un module d'un autre mode n'est jamais affiché.
class ModuleSigh {
  const ModuleSigh({required this.id, required this.libelle, required this.icone, required this.modes, required this.construire, this.groupe = 'Poste'});
  final String id;
  final String libelle;
  final IconData icone;

  /// Modes qui portent ce module : un module commun déclare les deux, un module de la mère déclare `{mere}` seulement.
  final Set<ModePoste> modes;
  final String groupe;
  final Widget Function(BuildContext contexte, ConfigPoste config) construire;

  bool disponiblePour(ConfigPoste c) => modes.contains(c.mode);
}
