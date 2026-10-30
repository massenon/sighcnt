/// Mode du poste : UN seul exécutable. La mère est le fileul PLUS ses modules propres (service de synchronisation,
/// supervision, arbitrage). Le mode est une donnée de configuration du poste, jamais un second produit.
enum ModePoste { fileul, mere }

class ConfigPoste {
  const ConfigPoste({required this.mode, this.role = 'admin', this.nomPoste = 'Poste'});
  final ModePoste mode;

  /// Rôle de l'agent connecté (identifiant technique de `packages/rbac`).
  final String role;
  final String nomPoste;

  bool get estMere => mode == ModePoste.mere;

  static ModePoste modeDepuis(String valeur) => valeur == 'mere' ? ModePoste.mere : ModePoste.fileul;
}
