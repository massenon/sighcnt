/// Paramétrage du laboratoire (M5) — les règles de `m5-catalogue`, `m5-unites`, `m5-valeurs-reference` et `m5-reactifs`, extraites de
/// `prototype_html/assets/js/modules/m5-laboratoire.js` et de `data-labo.js`, rejouées sur des vecteurs tirés des écrans RÉELS pilotés dans Chrome
/// (`prototype_html/build/vecteurs-catalogue-labo.js`). Tout est préfixé `cat` : le barrel du domaine ne tolère aucune collision.
///
/// Trois provenances qui ne se confondent jamais : documentée (fiche du 21/08/2026) · validée par le biologiste (01/09/2026) · à valider. Le seuil
/// d'alerte d'un réactif est fixé par la clinique : un seuil absent n'est PAS un seuil de zéro.
library;

import '../format/format_fr.dart';
import '../format/js.dart' show nombreOuZero;
import '../format/recherche.dart' show trierPar;

typedef FicheCat = Map<String, Object?>;

/// Vérité JavaScript d'une valeur de fiche (`undefined`, `null`, `false`, `0` et `''` sont faux).
bool _vrai(Object? v) =>
    v != null && v != false && v != 0 && v != '' && !(v is double && v.isNaN);

/// `v == null` côté JS (null ET undefined).
bool _absent(Object? v) => v == null;

/// `String(nombre)` côté JS : `4` et `4.0` s'écrivent « 4 », `3.5` « 3.5 ».
String catNombreJs(Object? v) {
  if (v is int) return '$v';
  if (v is double) return v == v.truncateToDouble() && v.abs() < 1e21 ? '${v.toInt()}' : '$v';
  return '${v ?? ''}';
}

/// Tri stable sur une clé (`Array.prototype.sort` est stable) — celui de `C.sortBy` : comparaison naturelle française.
List<T> _trier<T>(Iterable<T> l, Object? Function(T) cle, {bool descendant = false}) =>
    trierPar(l.toList(), cle, descendant: descendant);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Référentiels du laboratoire (data-labo.js)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les six sections du bulletin (`L.SECTIONS`), dans l'ordre du bulletin.
const List<({String id, String libelle})> catSections = [
  (id: 'hematologie', libelle: 'Hématologie'),
  (id: 'serologie', libelle: 'Sérologie'),
  (id: 'parasitologie', libelle: 'Parasitologie'),
  (id: 'biochimie', libelle: 'Biochimie'),
  (id: 'bacteriologie', libelle: 'Bactériologie'),
  (id: 'hormonologie', libelle: 'Hormonologie'),
];

/// Les types de variable de résultat (`L.TYPES_VARIABLE`).
const List<({String id, String libelle})> catTypesVariable = [
  (id: 'numerique', libelle: 'Valeur numérique'),
  (id: 'binaire', libelle: 'Positif / Négatif'),
  (id: 'ternaire', libelle: 'Positif / Négatif / Indéterminé'),
  (id: 'titre', libelle: 'Titre (dilution)'),
  (id: 'liste', libelle: 'Choix dans une liste'),
  (id: 'texte', libelle: 'Texte libre'),
  (id: 'reactif', libelle: 'Réactif employé'),
  (id: 'lot', libelle: 'Lot de réactif'),
  (id: 'expiration', libelle: 'Expiration du réactif'),
  (id: 'commentaire', libelle: 'Commentaire de l’examen'),
];

/// Les types qui accompagnent un résultat sans en être un : ce sont eux que le biologiste « ferme » (`L.TYPES_ACCOMPAGNEMENT`).
const List<String> catTypesAccompagnement = ['reactif', 'lot', 'expiration', 'commentaire'];

/// Les domaines d'unité (formulaire et filtre de `m5-unites`).
const List<String> catDomainesUnite = [
  'Hématologie', 'Biochimie', 'Hormonologie', 'Bactériologie', 'Parasitologie', 'Hémostase', 'Andrologie', 'Général'
];

/// `L.type(id)` : le libellé d'un type, ou l'identifiant lui-même.
String catLibelleType(Object? id) {
  for (final t in catTypesVariable) {
    if (t.id == id) return t.libelle;
  }
  return '${id ?? ''}';
}

/// `L.section(id)`.
String catLibelleSection(Object? id) {
  for (final s in catSections) {
    if (s.id == id) return s.libelle;
  }
  return '${id ?? ''}';
}

/// Le symbole d'une unité, lu au magasin (`symbole(id)`) : par identifiant OU par symbole ; une unité archivée se retrouve quand même (la maquette retombe
/// sur sa liste d'origine) ; sinon « — ».
String catSymboleUnite(Iterable<FicheCat> unites, Object? id) {
  FicheCat? trouve(bool Function(FicheCat) actif) {
    for (final u in unites) {
      if (actif(u) && (u['id'] == id || u['symbole'] == id)) return u;
    }
    return null;
  }

  final u = trouve((u) => u['statut'] != 'archive') ?? trouve((_) => true);
  return u != null ? '${u['symbole']}' : '—';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La référence d'une variable et le moteur des plages par lot (SIGH.laboPlages)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `L.libelleReference(variable)` : la notation du document (« 4 - 8 », « < 6 », « > 0.35 »), jamais une autre. Une règle écrite l'emporte ; un type
/// d'accompagnement n'a pas de référence ; une variable qualitative dit l'issue attendue.
String catLibelleReference(FicheCat? v) {
  if (v == null) return '';
  if (_vrai(v['regle'])) return '${v['regle']}';
  final type = v['type'];
  if (catTypesAccompagnement.contains(type)) return '';
  if (['binaire', 'ternaire', 'liste', 'titre'].contains(type)) {
    return _vrai(v['normal']) ? 'Attendu : ${v['normal']}' : '';
  }
  if (type == 'texte') return '';
  final min = v['min'], max = v['max'];
  if (!_absent(min) && !_absent(max)) return '${catNombreJs(min)} - ${catNombreJs(max)}';
  if (!_absent(max)) return '< ${catNombreJs(max)}';
  if (!_absent(min)) return '> ${catNombreJs(min)}';
  return '';
}

/// `plagePour(variable, date)` : la plage du lot EN SERVICE à la date — la dernière dont l'entrée en service (`dateDebut`) précède ou égale le jour
/// (`AAAA-MM-JJ`, les dix premiers caractères de la date), les plus anciennes d'abord (tri STABLE : à même date, la dernière du registre l'emporte).
/// Une plage archivée, ou d'une autre variable, n'existe pas ; une plage sans date vaut depuis toujours. Sans date, [jourDefaut] (aujourd'hui).
/// `null` : aucune plage, les bornes de la variable font foi.
FicheCat? catPlagePour(FicheCat variable, Iterable<FicheCat> plages, Object? date,
    {required String jourDefaut}) {
  final brut = _vrai(date) ? '$date' : '';
  final d = (brut.length > 10 ? brut.substring(0, 10) : brut);
  final jour = d.isEmpty ? jourDefaut : d;
  final candidates = [
    for (final p in plages)
      if (p['statut'] != 'archive' &&
          p['variableId'] == variable['id'] &&
          (!_vrai(p['dateDebut']) || '${p['dateDebut']}'.compareTo(jour) <= 0))
        p
  ];
  // Tri stable sur la date d'entrée (chaînes ISO : l'ordre des chaînes EST l'ordre du calendrier ; '' passe avant tout).
  final ordre = [for (var i = 0; i < candidates.length; i++) (i, candidates[i])];
  ordre.sort((a, b) {
    final c = '${a.$2['dateDebut'] ?? ''}'.compareTo('${b.$2['dateDebut'] ?? ''}');
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return ordre.isEmpty ? null : ordre.last.$2;
}

/// `variableALaDate(v, date)` : la variable avec les bornes du lot en service à cette date.
FicheCat catVariableALaDate(FicheCat v, Iterable<FicheCat> plages, Object? date,
    {required String jourDefaut}) {
  final p = catPlagePour(v, plages, date, jourDefaut: jourDefaut);
  return p != null ? {...v, 'min': p['min'], 'max': p['max']} : v;
}

/// `referenceALaDate(v, date)` : la référence imprimée, avec le lot nommé quand une plage s'applique (« 3.5 - 9 — lot LOT-A »).
String catReferenceALaDate(FicheCat v, Iterable<FicheCat> plages, Object? date,
    {required String jourDefaut}) {
  final p = catPlagePour(v, plages, date, jourDefaut: jourDefaut);
  final lib = catLibelleReference(p != null ? {...v, 'min': p['min'], 'max': p['max']} : v);
  return p != null && lib.isNotEmpty ? '$lib — lot ${p['lot']}' : lib;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m5-catalogue
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les quatre indicateurs du catalogue, sur les analyses ACTIVES : le tarif moyen d'un catalogue vide est zéro (jamais une division par zéro).
({int analyses, int categories, String tarifMoyen, int aConfirmer}) catKpisCatalogue(
    Iterable<FicheCat> actives) {
  final rows = actives.toList();
  final somme = rows.fold<double>(0, (a, r) => a + nombreOuZero(r['prix']));
  return (
    analyses: rows.length,
    categories: {for (final r in rows) '${r['categorie']}'}.length,
    tarifMoyen: money(rows.isEmpty ? 0 : somme / rows.length),
    aConfirmer: rows.where((r) => _vrai(r['tarifProvisoire'])).length,
  );
}

/// `Object.keys(C.groupBy(D.ANALYSES, champ)).sort()` : les valeurs distinctes, dans l'ordre des unités de code (« Hormonologie » avant « Hématologie »).
List<String> catValeursDistinctes(Iterable<FicheCat> fiches, String champ) =>
    ({for (final f in fiches) '${f[champ]}'}.toList()..sort());

/// L'onglet « Par catégorie » : une carte par catégorie (ordre alphabétique), ses analyses classées par désignation avec leur tarif.
List<({String categorie, List<FicheCat> analyses})> catParCategorie(Iterable<FicheCat> actives) {
  final g = <String, List<FicheCat>>{};
  for (final a in actives) {
    (g['${a['categorie']}'] ??= []).add(a);
  }
  final cles = _trier(g.keys, (k) => k);
  return [
    for (final k in cles) (categorie: k, analyses: _trier(g[k]!, (a) => a['designation']))
  ];
}

/// La fiche à enregistrer depuis le formulaire du catalogue : le tarif est un nombre (`type: 'money'`), le reste reste tel que saisi.
FicheCat catTransformAnalyse(Map<String, Object?> saisie) => {
      ...saisie,
      if (saisie.containsKey('prix')) 'prix': _nombreOuNull(saisie['prix']),
    };

/// `Number(v) || 0`, entier quand il l'est (la fiche écrit « 12 », pas « 12.0 »).
num _num0(Object? v) {
  final d = nombreOuZero(v);
  return d == d.truncateToDouble() ? d.toInt() : d;
}

num? _nombreOuNull(Object? v) {
  if (v == null || v == '') return null;
  if (v is num) return v;
  return num.tryParse('$v'.trim());
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m5-unites
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les quatre indicateurs des unités de mesure : celles reprises de la fiche (`!aValider`) et celles à confirmer.
({int unites, int reprises, int aConfirmer, int domaines}) catKpisUnites(Iterable<FicheCat> actives) {
  final rows = actives.toList();
  return (
    unites: rows.length,
    reprises: rows.where((u) => !_vrai(u['aValider'])).length,
    aConfirmer: rows.where((u) => _vrai(u['aValider'])).length,
    domaines: {for (final r in rows) '${r['domaine']}'}.length,
  );
}

/// Texte (recherche, export, tri) de la colonne « Provenance » d'une unité.
String catProvenanceUnite(FicheCat u) => _vrai(u['aValider']) ? 'à confirmer' : 'documentée';

/// Ce que la cellule « Provenance » affiche pour une unité DOCUMENTÉE : sa source, ou la fiche de résultats de la clinique.
String catSourceUnite(FicheCat u) =>
    _vrai(u['source']) ? '${u['source']}' : 'Fiche de résultats CNT';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m5-valeurs-reference
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les lignes du tableau des variables selon les trois filtres (section, examen, état) — la logique du `lignes()` de l'écran, VERBATIM : [variables] est
/// la collection ENTIÈRE (archivées comprises ; elles ne sont écartées que lorsqu'aucun état n'est retenu). Écart E181 porté tel quel : le filtre
/// « Documentées » garde aussi les variables validées par le biologiste (seuls les indicateurs séparent les trois provenances).
List<FicheCat> catLignesVariables(Iterable<FicheCat> variables,
    {String section = '', String examen = '', String etat = ''}) {
  return [
    for (final v in variables)
      if (!(section.isNotEmpty && v['section'] != section) &&
          !(examen.isNotEmpty && v['examen'] != examen) &&
          !(etat == 'documente' && (_vrai(v['aValider']) || !_vrai(v['actif']))) &&
          !(etat == 'valider' && !_vrai(v['aValider'])) &&
          !(etat == 'ferme' && v['actif'] != false) &&
          !(etat.isEmpty && v['statut'] == 'archive'))
        v
  ];
}

/// Les quatre indicateurs, sur les variables ACTIVES (non archivées) : documentées = ni à valider ni validées ; validées = portent `valideLe`.
({int variables, int documentees, int validees, int fermees}) catKpisVariables(
    Iterable<FicheCat> actives) {
  final t = actives.toList();
  return (
    variables: t.length,
    documentees: t.where((v) => !_vrai(v['aValider']) && !_vrai(v['valideLe'])).length,
    validees: t.where((v) => _vrai(v['valideLe'])).length,
    fermees: t.where((v) => v['actif'] == false).length,
  );
}

/// La provenance d'une variable — TROIS, pas deux : `fermée` · `à valider` · `validée` (suppléée puis arrêtée par le biologiste) · `documentée` (fiche
/// du 21/08/2026). Les fondre ferait passer une valeur usuelle pour une lecture du document.
String catProvenance(FicheCat v) {
  if (v['actif'] == false) return 'fermée';
  if (_vrai(v['aValider'])) return 'à valider';
  return _vrai(v['valideLe']) ? 'validée' : 'documentée';
}

/// Les examens proposés dans le filtre : ceux de la section choisie (tous si aucune).
List<FicheCat> catExamensDeSection(Iterable<FicheCat> examensActifs, String section) => [
      for (final e in examensActifs)
        if (section.isEmpty || e['section'] == section) e
    ];

const _numeriquesVariable = ['min', 'max', 'decimales', 'ordre'];

/// Le formulaire d'une variable → la fiche à écrire. [existante] : `null` à la création (variable « à valider » portant la date de création), sinon
/// la variable corrigée — une borne déplacée fait sortir la fiche du document, ce que sa source DIT (« Modifiée par … précédemment : … »).
/// Écart E182 corrigé : une valeur absente (`null`, `''`) n'est pas une valeur déplacée.
FicheCat catTransformVariable(Map<String, Object?> saisie,
    {FicheCat? existante,
    required Iterable<FicheCat> examensActifs,
    required String utilisateur,
    required DateTime maintenant}) {
  final val = {...saisie};
  for (final k in _numeriquesVariable) {
    if (val.containsKey(k)) val[k] = _nombreOuNull(val[k]);
  }
  for (final e in examensActifs) {
    if (e['code'] == val['examen']) {
      val['examenLibelle'] = e['designation'];
      val['section'] = e['section'];
      break;
    }
  }
  final accompagnement = catTypesAccompagnement.contains(val['type']);
  val['accompagnement'] = accompagnement;
  val['retractable'] = accompagnement;
  if (existante == null) {
    val['actif'] = true;
    val['aValider'] = true;
    val['source'] = 'Créée dans l’application le ${dateFR(maintenant)} — à valider';
  } else {
    Object? v(Object? x) => x == null || x == '' ? null : x;
    final bougee = v(val['min']) != v(existante['min']) ||
        v(val['max']) != v(existante['max']) ||
        v(val['normal']) != v(existante['normal']);
    if (bougee) {
      val['source'] =
          'Modifiée par $utilisateur le ${dateFR(maintenant)} — précédemment : ${catLibelleReference(existante).isEmpty ? '—' : catLibelleReference(existante)}';
    }
  }
  return val;
}

/// Le patch de « Fermer cette variable » / « Rouvrir » : la variable n'est jamais supprimée, elle disparaît des comptes rendus À VENIR.
FicheCat catPatchBascule(FicheCat v, {required String utilisateur, required DateTime maintenant}) {
  final fermer = v['actif'] != false;
  return {
    'actif': !fermer,
    'fermeeLe': fermer ? iso(maintenant) : null,
    'fermeePar': fermer ? utilisateur : null,
  };
}

/// Les variables NUMÉRIQUES d'examen (hors accompagnement) auxquelles une plage par lot peut s'appliquer.
List<FicheCat> catVariablesDePlage(Iterable<FicheCat> actives) => [
      for (final v in actives)
        if (!_vrai(v['accompagnement']) && v['type'] == 'numerique') v
    ];

/// Refus d'une plage « Une plage sans aucune borne ne compare rien » : `null` si au moins une borne est posée.
String? catRefuserPlage(Map<String, Object?> val) =>
    _nombreOuNull(val['min']) == null && _nombreOuNull(val['max']) == null
        ? 'Une plage sans aucune borne ne compare rien.'
        : null;

/// Le formulaire d'une plage → la fiche à écrire : bornes en nombres (ou `null`), et le nom de la variable, de l'examen et son code recopiés.
FicheCat catTransformPlage(Map<String, Object?> saisie, Iterable<FicheCat> variablesActives) {
  final val = {...saisie};
  for (final k in ['min', 'max']) {
    val[k] = _nombreOuNull(val[k]);
  }
  for (final v in variablesActives) {
    if (v['id'] == val['variableId']) {
      val['variableLibelle'] = v['libelle'];
      val['examenLibelle'] = v['examenLibelle'];
      val['examen'] = v['examen'];
      break;
    }
  }
  return val;
}

/// « 3.5 – 9.5 », « – 10 », « 2 – » : les bornes du lot, telles que le tableau les affiche (borne absente : rien — le zéro est une borne).
String catBornesPlage(FicheCat p) =>
    '${_absent(p['min']) ? '' : catNombreJs(p['min'])} – ${_absent(p['max']) ? '' : catNombreJs(p['max'])}'.trim();

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m5-reactifs
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les périodes de consommation (`PERIODES_LABO`) : `jours` vaut `null` pour la plage libre.
const List<({String id, String libelle, int? jours})> catPeriodesLabo = [
  (id: 'semaine', libelle: 'Semaine', jours: 7),
  (id: 'mois', libelle: 'Mois', jours: 30),
  (id: 'trimestre', libelle: 'Trimestre', jours: 91),
  (id: 'semestre', libelle: 'Semestre', jours: 182),
  (id: 'annee', libelle: 'Année', jours: 365),
  (id: 'libre', libelle: 'Plage libre', jours: null),
];

/// `depuis` : le premier jour (`AAAA-MM-JJ`) de la fenêtre de consommation — aujourd'hui compris, donc `jours − 1` jours en arrière ; `null` (plage libre)
/// = tout l'historique.
String? catDepuis(DateTime auj, int? jours) {
  if (jours == null) return null;
  final d = DateTime(auj.year, auj.month, auj.day - jours + 1);
  return iso(d);
}

/// Les réactifs et consommables de laboratoire parmi les produits ACTIFS.
List<FicheCat> catReactifs(Iterable<FicheCat> produitsActifs) => [
      for (final p in produitsActifs)
        if (p['categorie'] == 'reactif' || p['categorie'] == 'conso_labo') p
    ];

/// Un seuil POSÉ (`seuilAlerte != null`) : le vide `''` en est un côté JS, et vaut zéro dans les comparaisons — la maquette ne l'écarte que pour
/// `sansSeuil` et le bon de demande.
bool catSeuilPose(FicheCat p) => !_absent(p['seuilAlerte']);

/// Un seuil NON FIXÉ : absent ou vide. Il est signalé À PART — jamais compté comme un seuil de zéro.
bool catSansSeuil(FicheCat p) => _absent(p['seuilAlerte']) || p['seuilAlerte'] == '';

double _stock(FicheCat p) => nombreOuZero(p['stock']);
double _seuilJs(FicheCat p) => nombreOuZero(p['seuilAlerte']); // `p.stock <= null` : le seuil absent vaut 0 dans la comparaison

bool _rupture(FicheCat p) => p['stock'] is num && p['stock'] == 0;

/// Les indicateurs de `m5-reactifs` : « sous le seuil » COMPTE les ruptures (seuil posé et stock ≤ seuil) — ce n'est pas le KPI « hors rupture » du
/// référentiel des produits.
({int references, double valeur, int sousSeuil, int rupture, List<FicheCat> sansSeuil}) catKpisReactifs(
    Iterable<FicheCat> produits) {
  final l = produits.toList();
  return (
    references: l.length,
    valeur: l.fold<double>(0, (a, p) => a + nombreOuZero(_stock(p) * nombreOuZero(p['cump']))),
    sousSeuil: l.where((p) => catSeuilPose(p) && _stock(p) <= _seuilJs(p)).length,
    rupture: l.where(_rupture).length,
    sansSeuil: l.where(catSansSeuil).toList(),
  );
}

/// La valeur d'une référence au CUMP : `stock × cump`.
double catValeurReactif(FicheCat p) => nombreOuZero(_stock(p) * nombreOuZero(p['cump']));

/// L'état d'une ligne : `rupture` (stock nul), `critique` (stock ≤ seuil, le seuil absent valant 0), sinon `normal`.
String catEtatReactif(FicheCat p) =>
    _rupture(p) ? 'rupture' : (_stock(p) <= _seuilJs(p) ? 'critique' : 'normal');

/// La teinte de la cellule « Stock » : `danger` en rupture, `attention` sous le seuil, `` sinon.
String catTeinteStock(FicheCat p) =>
    _rupture(p) ? 'danger' : (_stock(p) <= _seuilJs(p) ? 'attention' : '');

/// Le filtre « Niveau de stock » : `rupture` · `alerte` (sous le seuil, hors rupture) · `ok` (au-dessus d'un seuil posé) · `sansSeuil`.
bool catNiveauCorrespond(FicheCat p, String niveau) {
  switch (niveau) {
    case 'rupture':
      return _rupture(p);
    case 'alerte':
      return catSeuilPose(p) && _stock(p) > 0 && _stock(p) <= _seuilJs(p);
    case 'sansSeuil':
      return catSansSeuil(p);
    default:
      return catSeuilPose(p) && _stock(p) > _seuilJs(p);
  }
}

/// Le bon de demande de réactifs : les références dont le seuil est FIXÉ et dont le stock l'a atteint (`stock ≤ seuil`).
List<FicheCat> catManquants(Iterable<FicheCat> produits) => [
      for (final p in produits)
        if (catSeuilPose(p) && p['seuilAlerte'] != '' && _stock(p) <= _seuilJs(p)) p
    ];

/// La quantité demandée sur le bon : de quoi revenir à deux fois le seuil, une unité au moins (`max(2 × seuil − stock, 1)`).
num catQuantiteDemandee(FicheCat p) {
  final v = _seuilJs(p) * 2 - _stock(p);
  final q = v > 1 ? v : 1;
  return q == q.truncateToDouble() ? q.toInt() : q;
}

/// `LAB-NNNN` : le plus grand rang déjà écrit au registre des produits (archivés compris), plus un — jamais un compteur de page (écart E180).
String catCodeReactif(Iterable<FicheCat> produits) {
  var max = 0;
  for (final p in produits) {
    final c = '${p['code'] ?? ''}';
    if (c.startsWith('LAB-')) {
      final k = int.tryParse(RegExp(r'^\s*[+-]?\d+').firstMatch(c.substring(4))?.group(0)?.trim() ?? '') ?? 0;
      if (k > max) max = k;
    }
  }
  return 'LAB-${(max + 1).toString().padLeft(4, '0')}';
}

/// Le formulaire d'un réactif → la fiche à écrire (création ET modification). Écart E184 corrigé : le seuil critique, facultatif, reste VIDE — jamais 0.
FicheCat catTransformReactif(Map<String, Object?> saisie) {
  final v = {...saisie};
  for (final k in ['stock', 'seuilAlerte', 'seuilCritique', 'cump']) {
    if (v.containsKey(k)) v[k] = _nombreOuNull(v[k]);
  }
  return v;
}

/// RG-03 : le stock ne peut jamais être négatif. Le refus se dit (`message`, `detail`) et rien n'est écrit — le champ déclarait `min: 0`, que la maquette
/// n'appliquait pas (écart E185, corrigé). `null` : accepté.
({String message, String detail})? catRefuserReactif(Map<String, Object?> saisie) {
  final stock = double.tryParse('${saisie['stock'] ?? ''}'.trim());
  return stock != null && stock < 0
      ? (message: 'Le stock ne peut pas être négatif.', detail: 'RG-03 — corriger la quantité saisie.')
      : null;
}

/// À la CRÉATION : le code (s'il manque), le stock et le CUMP (`Number(v) || 0`), la trace de qui a fixé le seuil et quand.
FicheCat catNouveauReactif(Map<String, Object?> saisie,
    {required Iterable<FicheCat> produits, required String utilisateur, required DateTime maintenant}) {
  final v = catTransformReactif(saisie);
  if (!_vrai(v['code'])) v['code'] = catCodeReactif(produits);
  v['stock'] = _num0(v['stock']);
  v['cump'] = _num0(v['cump']);
  v['seuilDefiniPar'] = utilisateur;
  v['seuilDefiniLe'] = iso(maintenant);
  return v;
}

/// Les sorties de stock des réactifs sur la fenêtre : le classement des plus consommés (jusqu'à dix), quantités cumulées par produit, du plus au moins
/// consommé (à égalité, l'ordre de première apparition).
List<({String produitId, num quantite})> catPlusConsommes(
    Iterable<FicheCat> mouvements, Set<Object?> produitIds, String? depuis) {
  final somme = <String, double>{};
  for (final m in mouvements) {
    if (m['type'] != 'sortie') continue;
    if (!produitIds.contains(m['produitId'])) continue;
    final d = '${m['date'] ?? ''}';
    if (depuis != null && (d.length > 10 ? d.substring(0, 10) : d).compareTo(depuis) < 0) continue;
    somme.update('${m['produitId']}', (s) => s + nombreOuZero(m['quantite']), ifAbsent: () => nombreOuZero(m['quantite']));
  }
  final ordre = somme.keys.toList();
  final tri = [for (var i = 0; i < ordre.length; i++) (i, ordre[i])]
    ..sort((a, b) {
      final c = somme[b.$2]!.compareTo(somme[a.$2]!);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [
    for (final e in tri.take(10)) (produitId: e.$2, quantite: somme[e.$2]!)
  ];
}

/// Le classement de la valeur du stock : les dix références les plus immobilisées (tri croissant stable PUIS inversé, comme `C.sortBy(...).reverse()` :
/// à valeur égale, c'est l'ordre inverse de la collection qui sort). La barre est rouge sous le seuil d'alerte.
List<FicheCat> catClasserParValeur(Iterable<FicheCat> produits) {
  final asc = _trier(produits, catValeurReactif);
  return asc.reversed.take(10).toList();
}

/// `x.seuilAlerte != null && x.stock <= x.seuilAlerte` : la teinte d'une barre du classement de valeur.
bool catSousSeuilTeinte(FicheCat p) => catSeuilPose(p) && _stock(p) <= _seuilJs(p);

/// Le libellé d'une catégorie de réactif dans les graphiques et le tableau.
String catLibelleCategorieReactif(Object? c) =>
    c == 'reactif' ? 'Réactifs' : 'Consommables de laboratoire';
