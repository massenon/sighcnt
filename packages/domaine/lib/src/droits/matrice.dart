/// Droits d'un rôle sur un écran : voir, éditer, annuler. « Lecture seule » n'est pas un quatrième droit : un écran
/// visible sans droit d'éditer EST en lecture seule.
class Droit {
  const Droit({required this.voir, required this.editer, required this.annuler});
  final bool voir;
  final bool editer;
  final bool annuler;

  static const aucun = Droit(voir: false, editer: false, annuler: false);

  bool get lectureSeule => voir && !editer;

  @override
  bool operator ==(Object other) => other is Droit && other.voir == voir && other.editer == editer && other.annuler == annuler;

  @override
  int get hashCode => Object.hash(voir, editer, annuler);

  @override
  String toString() => 'Droit(voir: $voir, editer: $editer, annuler: $annuler)';
}

/// Matrice EFFECTIVE rôle × écran, lue depuis `packages/rbac/data/rbac.json` (ENGENDRÉE par la maquette, jamais saisie).
///
/// Règle d'or, inverse de celle de la maquette pour un rôle sans fiche : ici **tout ce qui n'est pas listé est refusé**.
/// La matrice extraite est déjà résolue (surcharges d'écran, modules, écrans universels) ; ce moteur ne recalcule rien.
class MatriceDroits {
  MatriceDroits._(this._parRole, this._archives, this._libelles);

  final Map<String, Map<String, Droit>> _parRole;
  final Set<String> _archives;
  final Map<String, String> _libelles;

  /// `json` = contenu décodé de `rbac.json`.
  factory MatriceDroits.depuisJson(Map<String, Object?> json) {
    final roles = (json['roles'] as List? ?? const []).cast<Map>();
    final parRole = <String, Map<String, Droit>>{};
    final brut = (json['parRole'] as Map? ?? const {}).cast<String, Object?>();
    brut.forEach((role, ecrans) {
      parRole[role] = {
        for (final e in (ecrans as Map).entries)
          '${e.key}': () {
            final t = (e.value as List).cast<num>();
            return Droit(voir: t[0] != 0, editer: t[1] != 0, annuler: t[2] != 0);
          }(),
      };
    });
    return MatriceDroits._(
      parRole,
      {for (final r in roles) if (r['archive'] == true) '${r['id']}'},
      {for (final r in roles) '${r['id']}': '${r['label']}'},
    );
  }

  /// Un rôle archivé n'ouvre aucune session (RG-14) : il n'a jamais d'écran.
  bool estArchive(String role) => _archives.contains(role);

  bool roleConnu(String role) => _libelles.containsKey(role);

  String? libelle(String role) => _libelles[role];

  Droit droit(String role, String ecran) {
    if (estArchive(role)) return Droit.aucun;
    return _parRole[role]?[ecran] ?? Droit.aucun;
  }

  bool peutVoir(String role, String ecran) => droit(role, ecran).voir;
  bool peutEditer(String role, String ecran) => droit(role, ecran).voir && droit(role, ecran).editer;
  bool peutAnnuler(String role, String ecran) => droit(role, ecran).voir && droit(role, ecran).annuler;

  /// Écrans que le rôle voit — c'est exactement ce que la navigation a le droit d'afficher.
  Set<String> ecransVisibles(String role) {
    if (estArchive(role)) return const {};
    return {for (final e in (_parRole[role] ?? const <String, Droit>{}).entries) if (e.value.voir) e.key};
  }
}
