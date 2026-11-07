/// RÔLES & PERMISSIONS (M14) — port de la matrice RBAC ADMINISTRABLE de `m14-roles` (vague 15) : la couche de SURCHARGES que la maquette pose par-dessus le
/// manifeste (`surcharges()`, `droits()`, `droitsEcran()`, `appliquerRenommages()` de nav.js) et les gestes de l'écran.
/// Vecteurs : `test/vecteurs/securite.json` (les modales de la maquette pilotées dans Chrome).
///
/// COMMENT CELA S'ARTICULE AVEC LE MOTEUR DE DROITS DU POSTE. `MatriceDroits` (droits/matrice.dart) est ENGENDRÉE depuis `packages/rbac/data/rbac.json` et
/// n'est pas modifiée : ce fichier ne la réécrit pas. Il part de la MÊME matrice (la fiche `rolesBase`, dérivée de ce JSON) et y pose les décisions de
/// l'administrateur, collection `rbac`, une fiche par rôle, exactement comme la maquette. Le résultat est ce que l'ÉCRAN montre ; ce que le poste APPLIQUE
/// reste la matrice engendrée — une décision saisie ici n'est pas encore lue par `MatriceDroits` (elle est consignée, journalisée, et destinée à la
/// prochaine génération de la matrice par la mère).
library;

import 'sec_comptes.dart' show FicheSec, secVrai;

/// Les droits d'un rôle sur un module ou un écran. La LECTURE SEULE n'est pas un quatrième droit : un module visible sans droit d'agir y EST.
class DroitSec {
  const DroitSec(this.voir, this.editer, this.annuler,
      {this.origine = false, this.horsMatrice = false, this.roleArchive = false});
  final bool voir;
  final bool editer;
  final bool annuler;

  /// `true` : le manifeste décide encore (aucune surcharge).
  final bool origine;

  /// Un code absent du manifeste (écrans hors ruban : `AUTH`, `SUP`) : la matrice ne le gouverne pas, il n'est pas « fermé ».
  final bool horsMatrice;
  final bool roleArchive;
  bool get lectureSeule => voir && !editer && !annuler;

  static const ferme = DroitSec(false, false, false);

  @override
  bool operator ==(Object o) =>
      o is DroitSec && o.voir == voir && o.editer == editer && o.annuler == annuler;
  @override
  int get hashCode => Object.hash(voir, editer, annuler);
  @override
  String toString() => 'DroitSec($voir, $editer, $annuler)';
}

/// `surcharges()` : UNE fiche par rôle est la règle, mais un doublon ne rend pas la matrice imprévisible — on FUSIONNE champ par champ, la dernière
/// fiche l'emportant sur ce qu'elle définit, et seulement sur cela (un second enregistrement n'efface pas le renommage ni l'archivage du premier).
Map<String, FicheSec> secSurcharges(Iterable<FicheSec> fiches) {
  final out = <String, FicheSec>{};
  for (final f in fiches) {
    final role = f['role'];
    if (!secVrai(role)) continue;
    final deja = out['$role'];
    if (deja == null) {
      out['$role'] = {...f};
      continue;
    }
    final fusion = {...deja};
    for (final e in f.entries) {
      if (e.value == null) continue;
      if (e.key == 'droits' || e.key == 'droitsEcrans') {
        fusion[e.key] = {
          ...((deja[e.key] as Map?)?.cast<String, Object?>() ?? const {}),
          ...((e.value as Map?)?.cast<String, Object?>() ?? const {}),
        };
        continue;
      }
      fusion[e.key] = e.value;
    }
    out['$role'] = fusion;
  }
  return out;
}

/// Un rôle tel que l'écran l'affiche (`N.ROLES[x]` après `appliquerRenommages()`).
class RoleSec {
  const RoleSec(
      {required this.id,
      required this.label,
      required this.short,
      required this.color,
      required this.home,
      required this.labelOrigine,
      required this.shortOrigine,
      required this.archive,
      required this.cree});
  final String id;
  final String label;
  final String short;
  final String color;
  final String? home;
  final String labelOrigine;
  final String shortOrigine;
  final bool archive;

  /// Rôle inventé en exploitation (fiche `nouveau`), absent du manifeste.
  final bool cree;
}

/// Les rôles : ceux de la matrice engendrée (`rolesBase`), puis ceux que l'administrateur a CRÉÉS (fiche `nouveau`). Le libellé long suit la fiche
/// (renommage), le court suit le long (« l'oublier laissait le rôle renommé à l'endroit le plus visible de l'écran »), l'archivage vient de la fiche.
List<RoleSec> secRoles(Iterable<FicheSec> rolesBase, Map<String, FicheSec> sur) {
  final out = <RoleSec>[];
  final vus = <String>{};
  for (final b in rolesBase) {
    final id = '${b['id']}';
    vus.add(id);
    final f = sur[id];
    final labelOrigine = '${b['labelOrigine'] ?? b['label']}';
    final shortOrigine = '${b['shortOrigine'] ?? b['short'] ?? labelOrigine}';
    out.add(RoleSec(
      id: id,
      label: f != null && secVrai(f['libelle']) ? '${f['libelle']}' : labelOrigine,
      short: f != null && secVrai(f['libelleCourt'])
          ? '${f['libelleCourt']}'
          : (f != null && secVrai(f['libelle']) ? '${f['libelle']}' : shortOrigine),
      color: '${b['color'] ?? 'neutral'}',
      home: b['home'] as String?,
      labelOrigine: labelOrigine,
      shortOrigine: shortOrigine,
      archive: f != null && f['statut'] == 'archive',
      cree: false,
    ));
  }
  for (final e in sur.entries) {
    final f = e.value;
    if (f['nouveau'] != true || vus.contains(e.key)) continue;
    final origine = secVrai(f['libelleOrigine'])
        ? '${f['libelleOrigine']}'
        : (secVrai(f['libelle']) ? '${f['libelle']}' : e.key);
    out.add(RoleSec(
      id: e.key,
      label: secVrai(f['libelle']) ? '${f['libelle']}' : e.key,
      short: secVrai(f['libelleCourt'])
          ? '${f['libelleCourt']}'
          : (secVrai(f['libelle']) ? '${f['libelle']}' : e.key),
      color: '${f['couleur'] ?? 'neutral'}',
      home: (f['accueil'] as String?) ?? 'plan-du-site',
      labelOrigine: origine,
      shortOrigine: origine,
      archive: f['statut'] == 'archive',
      cree: true,
    ));
  }
  return out;
}

DroitSec? _depuisTriplet(Object? t) {
  if (t == 'hors') return const DroitSec(true, true, true, origine: true, horsMatrice: true);
  if (t is List && t.length >= 3) {
    return DroitSec(t[0] != 0, t[1] != 0, t[2] != 0, origine: true);
  }
  return null;
}

/// Les droits D'ORIGINE d'un rôle sur un module (`droitsOrigine`) : la matrice engendrée. Pour un rôle archivé à la source, la matrice est toute
/// fermée — c'est `modulesOrigine` qui dit ce que la RESTAURATION rend. Un rôle créé en exploitation part de zéro (« tous modules fermés »), sauf
/// les codes hors matrice, que la matrice ne gouverne pas.
DroitSec secDroitOrigine(
    FicheSec? base, String code, FicheSec? fiche, Iterable<FicheSec> rolesBase) {
  if (base == null) {
    for (final b in rolesBase) {
      if ((b['modules'] as Map?)?[code] == 'hors') {
        return const DroitSec(true, true, true, origine: true, horsMatrice: true);
      }
    }
    return const DroitSec(false, false, false, origine: true);
  }
  final archiveSource = base['archive'] == true;
  final restaure = archiveSource && fiche != null && fiche['statut'] != 'archive';
  final carte = (restaure && base['modulesOrigine'] != null
          ? base['modulesOrigine']
          : base['modules']) as Map? ??
      const {};
  return _depuisTriplet(carte[code]) ??
      const DroitSec(false, false, false, origine: true);
}

/// `droits(roleId, code)` : manifeste, puis surcharge. Point unique de la matrice affichée.
DroitSec secDroitModule(String role, String code,
    {required Map<String, FicheSec> bases,
    required Map<String, FicheSec> sur,
    required Iterable<FicheSec> rolesBase}) {
  final f = sur[role];
  final base = secDroitOrigine(bases[role], code, f, rolesBase);
  if (base.horsMatrice) return base;
  if (f != null && f['statut'] == 'archive') {
    return const DroitSec(false, false, false, roleArchive: true);
  }
  final o = (f?['droits'] as Map?)?[code] as Map?;
  if (o == null) return base;
  return _appliquer(o, base);
}

DroitSec _appliquer(Map o, DroitSec base) {
  final voir = o['voir'] != null ? o['voir'] == true : base.voir;
  var editer = o['editer'] != null ? o['editer'] == true : base.editer;
  var annuler = o['annuler'] != null ? o['annuler'] == true : base.annuler;
  if (!voir) {
    editer = false;
    annuler = false;
  }
  return DroitSec(voir, editer, annuler);
}

/// `droitsEcran(roleId, ecranId, code)` : l'écran l'emporte sur son module ; un écran non réglé suit son module. La maquette y ajoute les écrans
/// UNIVERSELS (`m7-besoins`, ouvert à tous) : le poste les connaît par `universels` de la rangée et les ouvre en voir + éditer, jamais annuler.
DroitSec secDroitEcran(String role, String ecranId, String code,
    {required Map<String, FicheSec> bases,
    required Map<String, FicheSec> sur,
    required Iterable<FicheSec> rolesBase,
    Set<String> universels = const {}}) {
  final base = secDroitModule(role, code, bases: bases, sur: sur, rolesBase: rolesBase);
  final o = ((sur[role]?['droitsEcrans']) as Map?)?[ecranId] as Map?;
  if (o == null && universels.contains(ecranId)) {
    return DroitSec(true, true, base.annuler);
  }
  if (o == null) return base;
  return _appliquer(o, base);
}

/// Les quatre états d'une case de la matrice : fermé (gris), lecture seule (bleu), partiel (orange : éditer OU annuler sans l'autre), plein (vert).
enum EtatCaseSec { ferme, lectureSeule, partiel, plein }

EtatCaseSec secEtatCase(DroitSec d) {
  if (!d.voir) return EtatCaseSec.ferme;
  if (d.lectureSeule) return EtatCaseSec.lectureSeule;
  if (!d.editer || !d.annuler) return EtatCaseSec.partiel;
  return EtatCaseSec.plein;
}

/// Info-bulle d'une case partielle : « Édition Annulation » telle que la maquette l'écrit (`(éditer ? 'Édition' : '') + (annuler ? ' Annulation' : '')`).
String secInfobulleCase(DroitSec d) {
  switch (secEtatCase(d)) {
    case EtatCaseSec.ferme:
      return 'Module fermé';
    case EtatCaseSec.lectureSeule:
      return 'Lecture seule';
    case EtatCaseSec.partiel:
      return '${d.editer ? 'Édition' : ''}${d.annuler ? ' Annulation' : ''}';
    case EtatCaseSec.plein:
      return 'Voir, éditer, annuler';
  }
}

// --- Les cases de la modale « Modifier les droits » ------------------------------------------------------------------------------------------

/// Les trois cases d'un module. La quatrième, « lecture seule », est DÉRIVÉE : `voir && !éditer && !annuler`.
class CasesDroitsSec {
  CasesDroitsSec(this.voir, this.editer, this.annuler);
  factory CasesDroitsSec.depuis(DroitSec d) => CasesDroitsSec(d.voir, d.editer, d.annuler);
  bool voir;
  bool editer;
  bool annuler;
  bool get lecture => voir && !editer && !annuler;

  /// Décocher « voir » retire aussi éditer et annuler.
  void cocherVoir(bool v) {
    voir = v;
    if (!v) {
      editer = false;
      annuler = false;
    }
  }

  /// Cocher « éditer » ouvre « voir » ; le décocher n'y touche pas.
  void cocherEditer(bool v) {
    editer = v;
    if (v) voir = true;
  }

  void cocherAnnuler(bool v) {
    annuler = v;
    if (v) voir = true;
  }

  /// Cocher « lecture seule » = voir sans agir ; la décocher ne fait rien (elle se RE-DÉRIVE : le module reste visible).
  void cocherLecture(bool v) {
    if (v) {
      voir = true;
      editer = false;
      annuler = false;
    }
  }

  Map<String, Object?> versFiche() => {'voir': voir, 'editer': editer, 'annuler': annuler};
}

enum ModeToutSec { ouvrir, lectureSeule, fermer }

/// « Tout ouvrir », « Tout en lecture seule », « Tout fermer ».
void secBasculerTout(Iterable<CasesDroitsSec> cases, ModeToutSec mode) {
  for (final c in cases) {
    switch (mode) {
      case ModeToutSec.ouvrir:
        c.voir = c.editer = c.annuler = true;
      case ModeToutSec.lectureSeule:
        c.voir = true;
        c.editer = c.annuler = false;
      case ModeToutSec.fermer:
        c.voir = c.editer = c.annuler = false;
    }
  }
}

/// Le détail de l'info-bulle de l'enregistrement : « N module(s) ouvert(s), dont M en lecture seule. »
({int ouverts, int figes}) secCompteOuverts(Iterable<CasesDroitsSec> cases) => (
      ouverts: cases.where((c) => c.voir).length,
      figes: cases.where((c) => c.voir && !c.editer && !c.annuler).length,
    );

// --- Création, renommage, archivage ----------------------------------------------------------------------------------------------------------

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ù': 'u', 'ú': 'u',
  'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
};

/// L'identifiant technique d'un rôle : minuscules, accents retirés (NFD), tout ce qui n'est ni lettre ni chiffre supprimé. `''` : invalide.
String secIdentifiantRole(String saisie) {
  final b = StringBuffer();
  for (final r in saisie.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final s = _accents[c] ?? c;
    if (RegExp(r'^[a-z0-9]$').hasMatch(s)) b.write(s);
  }
  return b.toString();
}

/// Les couleurs proposées à un rôle créé.
const secCouleursRole = <({String valeur, String libelle})>[
  (valeur: 'navy', libelle: 'Bleu institutionnel'),
  (valeur: 'info', libelle: 'Bleu clair'),
  (valeur: 'success', libelle: 'Vert'),
  (valeur: 'warning', libelle: 'Orange'),
  (valeur: 'danger', libelle: 'Rouge'),
  (valeur: 'neutral', libelle: 'Gris'),
];

/// Tous les modules FERMÉS nommément (les modules « tous les rôles » du manifeste s'ouvriraient d'eux-mêmes à un rôle neuf) et les écrans
/// universels fermés eux aussi : un écran universel ne cède que devant une surcharge d'ÉCRAN.
({Map<String, Object?> droits, Map<String, Object?> droitsEcrans}) secZeroDroits(
    Iterable<String> codesModules, Iterable<String> universels) {
  Map<String, Object?> ferme() => {'voir': false, 'editer': false, 'annuler': false};
  return (
    droits: {for (final c in codesModules) c: ferme()},
    droitsEcrans: {for (final u in universels) u: ferme()},
  );
}

/// Les modules du manifeste, sans doublon de code (les rangées `secondaire` répètent le code du module).
List<String> secCodesModules(Iterable<FicheSec> rangees) {
  final out = <String>[];
  for (final r in rangees) {
    final c = '${r['code']}';
    if (!out.contains(c)) out.add(c);
  }
  return out;
}

/// La note qui dit combien de modules sont fermés à la création (le nombre de codes DISTINCTS au vecteur : 32 rangées → 32 modules comptés par
/// `tousModules()`, c'est-à-dire par RANGÉE, pas par code distinct).
String secDetailCreationRole(int nombreModules) =>
    'Les $nombreModules modules sont fermés : le rôle n’ouvre aucun écran. Lui régler ses droits avec « Modifier les droits », puis '
    '« Régler écran par écran » pour les exceptions.';

/// Une tentative de connexion refusée, pour l'onglet et la barre de notification.
bool secTentativeAExaminer(FicheSec t) => !secVrai(t['traitee']);
