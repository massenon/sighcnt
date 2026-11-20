/// LES GESTES RÉSERVÉS PAR DROIT (lot B de la maquette, lot C du poste).
///
/// Un geste qui engage un professionnel nommé n'est pas une liste de rôles écrite dans le code : c'est un DROIT de la fiche RBAC, accordé PAR RÔLE (jamais par agent), déclaré au manifeste de
/// la maquette (`N.GESTES`) et exporté dans la section `gestes` de `packages/rbac/data/rbac.json`. Ce fichier le LIT, jamais un nom de rôle en dur : la matrice engendrée est la base, la
/// superposition à chaud des fiches (`a_chaud.dart`, clé `droitsGestes`) la recalcule comme `N.droitGeste()`.
///
/// Résolution (identique à la maquette) : geste ou rôle inconnu, FERMÉ ; rôle archivé, FERMÉ ; puis la fiche RBAC (`droitsGestes[geste]`, UNE SURCHARGE ACCORDE AUTANT QU'ELLE RESTREINT) ; à
/// défaut, la liste d'origine du manifeste. Un rôle créé en exploitation n'est dans aucune liste d'origine : il part de zéro. Ce n'est PAS la doctrine « sans fiche, tous les droits » des
/// écrans : un geste réservé ne s'ouvre jamais par défaut. Le droit n'ouvre aucun écran.
library;

/// Un geste réservé tel que le manifeste le déclare.
class DeclarationGeste {
  const DeclarationGeste({required this.id, required this.libelle, this.rolesDefaut = const [], this.defautSiEcritSur = const []});
  final String id, libelle;

  /// Les rôles qui le détiennent d'origine.
  final List<String> rolesDefaut;

  /// Les modules dont l'écriture donne le geste d'origine (la liste `rolesDefaut` en est tirée ; vérifiée contre la matrice par le test du paquet `rbac`).
  final List<String> defautSiEcritSur;

  factory DeclarationGeste.depuisJson(Map<String, Object?> j) => DeclarationGeste(
        id: '${j['id']}',
        libelle: '${j['libelle'] ?? ''}',
        rolesDefaut: [for (final r in (j['rolesDefaut'] as List? ?? const [])) '$r'],
        defautSiEcritSur: [for (final m in (j['defautSiEcritSur'] as List? ?? const [])) '$m'],
      );
}

/// La résolution du droit d'un geste pour un rôle : [surcharge] (la case de la fiche, `null` si elle ne nomme pas le geste) accorde autant qu'elle retire.
bool resoudreDroitGeste({required bool? surcharge, required bool roleArchive, required bool defaut}) {
  if (roleArchive) return false;
  return surcharge ?? defaut;
}

/// Ce que chaque rôle détient, par geste.
class MatriceGestes {
  MatriceGestes({required this.declarations, required Map<String, Map<String, bool>> parRole}) : _parRole = parRole;

  final List<DeclarationGeste> declarations;
  final Map<String, Map<String, bool>> _parRole;

  /// Aucune déclaration : un poste dont `rbac.json` ne porte pas la section `gestes` n'accorde aucun geste.
  static final MatriceGestes vide = MatriceGestes(declarations: const [], parRole: const {});

  /// `json` = la section `gestes` de `rbac.json`.
  factory MatriceGestes.depuisJson(Object? json) {
    if (json is! Map) return vide;
    final decl = [for (final j in (json['jeux'] as List? ?? const [])) DeclarationGeste.depuisJson((j as Map).cast<String, Object?>())];
    final parRole = <String, Map<String, bool>>{};
    ((json['parRole'] as Map?) ?? const {}).forEach((role, gestes) {
      parRole['$role'] = {for (final e in (gestes as Map).entries) '${e.key}': e.value != 0 && e.value != false && e.value != null};
    });
    return MatriceGestes(declarations: decl, parRole: parRole);
  }

  DeclarationGeste? declaration(String geste) => declarations.where((d) => d.id == geste).firstOrNull;

  /// `N.droitGeste(role, geste)` : rôle ou geste inconnu, FERMÉ.
  bool droit(String role, String geste) => _parRole[role]?[geste] ?? false;

  /// Les rôles que la matrice connaît.
  Iterable<String> get roles => _parRole.keys;

  /// `N.rolesAvecGeste(geste)`.
  List<String> rolesAvec(String geste) => [for (final e in _parRole.entries) if (e.value[geste] ?? false) e.key];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// LOT VAL (Direction, 16/11/2026 : « pas de rôle ni de validation en dur dans le code ») : la lecture À CHAUD de la fiche RBAC par les moteurs du domaine.
// ---------------------------------------------------------------------------------------------------------------------------------------------

bool Function(String role, String geste)? _lecteurGeste;
Iterable<String> Function()? _rolesConnusGeste;

/// Le poste branche la fiche RBAC À CHAUD (`matrice.droitGeste`, rôles connus de la matrice) ; `null` revient au DÉFAUT d'origine du manifeste (les listes de rôles des moteurs,
/// qui ne sont plus que ce défaut, vérifié égal à `rbac.json` par un test). Sans branchement (banc de protocole, tests purs), les listes d'origine décident, comme avant.
void gesInstaller({bool Function(String role, String geste)? lecteur, Iterable<String> Function()? roles}) {
  _lecteurGeste = lecteur;
  _rolesConnusGeste = roles;
}

/// Le rôle détient-il le geste réservé [geste] ? Lu de la fiche RBAC branchée, sinon [defaut] (la liste d'origine du manifeste).
bool gesDroit(String? role, String geste, List<String> defaut) {
  if (role == null || role.isEmpty) return false;
  final l = _lecteurGeste;
  return l != null ? l(role, geste) : defaut.contains(role);
}

/// Les rôles qui détiennent le geste (détenteurs d'origine d'abord, dans l'ordre de [defaut], pour que les motifs nomment le premier).
List<String> gesRoles(String geste, List<String> defaut) {
  final l = _lecteurGeste, r = _rolesConnusGeste;
  if (l == null || r == null) return defaut;
  final out = [for (final x in r()) if (l(x, geste)) x];
  int rang(String x) {
    final i = defaut.indexOf(x);
    return i < 0 ? 99 : i;
  }

  out.sort((a, b) => rang(a).compareTo(rang(b)));
  return out;
}
