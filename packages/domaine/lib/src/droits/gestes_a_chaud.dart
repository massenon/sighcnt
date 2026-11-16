// LOT CLO-3 (Direction, 16/11/2026, section AH point 5) : LA LECTURE À CHAUD DES GESTES RÉSERVÉS, EN UN SEUL POINT.
//
// Un réglage ou une validation qui était réservé à une liste de rôles écrite dans le domaine (`['admin', 'da']`) est désormais un geste réservé de la fiche RBAC (`N.GESTES`, clé
// `gestes` de `rbac.json`). Le domaine ne connaît pas la matrice : le poste installe UNE fois la lecture à chaud (`gesInstaller`, au démarrage, à partir de `matrice.droitGeste` et
// `matriceGestes.rolesAvec`) ; avant cela (outil, test sans poste), [gesDroit] retombe sur le DÉFAUT D'ORIGINE du manifeste, passé par l'appelant, vérifié égal à `rbac.json` par un
// test. Une règle écrite à un seul endroit ne diverge pas : tout geste migré passe ici et nulle part ailleurs.

bool Function(String role, String geste)? _lecture;
List<String> Function(String geste)? _roles;

/// Le poste installe la lecture de la fiche RBAC À CHAUD ; `null` (les deux) revient aux défauts d'origine.
void gesInstaller({bool Function(String role, String geste)? lecture, List<String> Function(String geste)? roles}) {
  _lecture = lecture;
  _roles = roles;
}

/// Le rôle détient-il le geste réservé [geste] ? Lu dans la fiche RBAC installée, sinon le défaut d'origine [defaut] (la liste du manifeste).
bool gesDroit(String role, String geste, List<String> defaut) => _lecture != null ? _lecture!(role, geste) : defaut.contains(role);

/// Les rôles qui détiennent le geste (liste DÉRIVÉE du droit, pour les messages), sinon le défaut d'origine.
List<String> gesRoles(String geste, List<String> defaut) => _roles != null ? _roles!(geste) : defaut;
