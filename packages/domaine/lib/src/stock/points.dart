/// Les points du gestionnaire de stock — `m6-point-ventes` (suivi des ventes) et `m6-point-stock` (point du stock valorisé).
///
/// Deux écrans CALCULÉS : rien n'est fourni, tout se lit sur les registres (factures et leurs lignes payables, produits, mouvements).
/// Chaque règle est rejouée sur les vecteurs tirés de l'écran réel de la maquette (`prototype_html/build/vecteurs-points.js`).
///
/// Ce qui est porté À L'IDENTIQUE, y compris ce qui surprend :
///  - un seul endroit qui additionne (`cumuler`) ; les pourcentages sont calculés sur le BRUT (seule base commune aux trois parts) ;
///  - les tris sont ceux de `C.sortBy` : stables, comparaison naturelle française, valeurs absentes en dernier ;
///  - `C.groupBy` rend un objet JavaScript : les clés « entières » passent AVANT les autres, ce qui décide de l'ordre des ex æquo ;
///  - un ÉTAT se lit à une date, un FLUX sur une période : la périodicité ne s'applique qu'au flux.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart';
import '../impression/etat.dart';
import '../referentiels/periodes.dart';

// ---------------------------------------------------------------------------------------------------------------------
// Référentiels (data.js) — les six secteurs de recette, les catégories de ligne, les sept familles d'articles
// ---------------------------------------------------------------------------------------------------------------------

class GroupePrestation {
  const GroupePrestation(this.id, this.label,
      {this.categories = const [], this.secteurs = const []});
  final String id;
  final String label;
  final List<String> categories;
  final List<String> secteurs;
}

/// `D.GROUPES_PRESTATION` : le vocabulaire arrêté des SIX secteurs (le groupe « echographie » porte l'IMAGERIE MÉDICALE : l'identifiant
/// technique n'a pas changé).
const groupesPrestation = [
  GroupePrestation('laboratoire', 'Laboratoire', categories: ['analyse']),
  GroupePrestation('pharmacie', 'Pharmacie', categories: ['medicament']),
  GroupePrestation('consultation', 'Consultation',
      categories: ['consultation']),
  GroupePrestation('echographie', 'Imagerie médicale',
      categories: ['imagerie'], secteurs: ['Imagerie médicale']),
  GroupePrestation('maternite', 'Maternité',
      secteurs: ['Maternité', 'Gynéco-obstétrique']),
  GroupePrestation('hospitalisation', 'Hospitalisation et soins',
      categories: ['hospitalisation', 'acte']),
];

class CategorieLigne {
  const CategorieLigne(this.id, this.label);
  final String id;
  final String label;
}

/// `D.CATEGORIES_LIGNE`.
const categoriesLigne = [
  CategorieLigne('consultation', 'Consultation'),
  CategorieLigne('acte', 'Acte / soin'),
  CategorieLigne('analyse', 'Analyse'),
  CategorieLigne('medicament', 'Médicament'),
  CategorieLigne('hospitalisation', 'Hospitalisation'),
];

/// `D.libelleCategorieLigne(id)`.
String libelleCategorieLigne(Object? id) {
  for (final c in categoriesLigne) {
    if (c.id == id) return c.label;
  }
  return (id == null || id == '') ? 'Autre' : '$id';
}

class FamilleArticle {
  const FamilleArticle(this.id, this.label, this.groupe);
  final String id;
  final String label;
  final String groupe;
}

/// `D.FAMILLES_ARTICLES` : les sept catégories de l'inventaire SAGE.
const famillesArticles = [
  FamilleArticle('medicament', 'Médicaments', 'pharmacie'),
  FamilleArticle('conso_medical', 'Consommables médicaux', 'pharmacie'),
  FamilleArticle('reactif', 'Réactifs de laboratoire', 'laboratoire'),
  FamilleArticle('conso_labo', 'Consommables de laboratoire', 'laboratoire'),
  FamilleArticle('petit_materiel', 'Petit matériel médical', 'equipement'),
  FamilleArticle('entretien', 'Produits d’entretien', 'logistique'),
  FamilleArticle('fourniture', 'Fournitures de bureau', 'logistique'),
];

/// `D.familleDe(categorie)`.
FamilleArticle? familleDe(Object? categorie) {
  for (final f in famillesArticles) {
    if (f.id == categorie) return f;
  }
  return null;
}

/// Le secteur de chaque acte du catalogue (collection `actes`) : la PREMIÈRE fiche portant le code fait foi, comme `secteurDeLigne`.
Map<String, String?> secteursDesActes(Iterable<Map<String, Object?>> actes) {
  final out = <String, String?>{};
  for (final a in actes) {
    final code = a['code'];
    if (code == null || out.containsKey('$code')) continue;
    final s = a['secteur'];
    out['$code'] = _vrai(s) ? '$s' : null;
  }
  return out;
}

/// `D.groupePrestation(categorie, ligne)` : le secteur de l'ACTE prime (un accouchement et un pansement sont tous deux des « actes »), la
/// catégorie répond sinon. L'appel à un seul argument continue de répondre.
GroupePrestation? groupePrestation(Object? categorie,
    [Map<String, Object?>? ligne,
    Map<String, String?> secteurParCode = const {}]) {
  String? secteur;
  if (ligne != null) {
    if (_vrai(ligne['secteur'])) {
      secteur = '${ligne['secteur']}';
    } else if (_vrai(ligne['acteCode'])) {
      secteur = secteurParCode['${ligne['acteCode']}'];
    }
  }
  if (secteur != null) {
    for (final g in groupesPrestation) {
      if (g.secteurs.contains(secteur)) return g;
    }
  }
  for (final g in groupesPrestation) {
    if (g.categories.contains(categorie)) return g;
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// Briques JavaScript reprises à l'identique
// ---------------------------------------------------------------------------------------------------------------------

bool _vrai(Object? v) => !(v == null ||
    v == false ||
    v == '' ||
    (v is num && (v == 0 || v.isNaN)));

double _n(Object? v) => nombreOuZero(v);

/// `String(x)` d'un nombre JavaScript : 80 → « 80 », 8,8 → « 8.8 » (jamais « 80.0 »).
String texteNombreJs(num v) {
  final d = v.toDouble();
  return d == d.truncateToDouble() && d.abs() < 1e21
      ? d.toInt().toString()
      : d.toString();
}

/// Clé d'objet JavaScript d'une valeur : `undefined` / `null` ont un nom.
String _cle(Object? v) => v == null ? 'undefined' : (v is num ? texteNombreJs(v) : '$v');

final _indice = RegExp(r'^(0|[1-9][0-9]*)$');

/// `C.groupBy(arr, key)` : un objet JavaScript. Les clés qui sont des indices de tableau (« 12 ») passent AVANT les autres, par ordre
/// croissant ; les autres gardent l'ordre d'insertion. C'est cet ordre qui départage les ex æquo des tris suivants.
Map<String, List<T>> grouper<T>(Iterable<T> l, String Function(T) cle) {
  final m = <String, List<T>>{};
  for (final x in l) {
    (m[cle(x)] ??= []).add(x);
  }
  final entiers = [
    for (final k in m.keys)
      if (_indice.hasMatch(k) && BigInt.parse(k) < BigInt.from(4294967295)) k
  ]..sort((a, b) => BigInt.parse(a).compareTo(BigInt.parse(b)));
  final out = <String, List<T>>{for (final k in entiers) k: m[k]!};
  for (final e in m.entries) {
    if (!out.containsKey(e.key)) out[e.key] = e.value;
  }
  return out;
}

/// `C.sortBy(arr, key, dir)` : tri STABLE (Array.prototype.sort), nombres entre eux, sinon `localeCompare('fr', {numeric: true})` ;
/// une valeur absente passe en dernier. Le tri de Dart n'est pas stable : l'indice d'origine départage.
List<T> trierStable<T>(List<T> l, Object? Function(T) cle,
    {bool descendant = false}) {
  final d = descendant ? -1 : 1;
  final idx = [for (var i = 0; i < l.length; i++) i];
  int cmp(int i, int j) {
    final x = cle(l[i]), y = cle(l[j]);
    if (x == null) return 1;
    if (y == null) return -1;
    if (x is num && y is num) {
      final r = (x - y) * d;
      return r > 0 ? 1 : (r < 0 ? -1 : 0);
    }
    return comparerNaturel(_cle(x), _cle(y)) * d;
  }

  idx.sort((i, j) {
    final c = cmp(i, j);
    return c != 0 ? c : i.compareTo(j);
  });
  return [for (final i in idx) l[i]];
}

double _somme<T>(Iterable<T> l, num Function(T) f) =>
    l.fold<double>(0, (a, x) => a + f(x));

DateTime? jourDe(Object? s) {
  if (s == null || '$s'.isEmpty) return null;
  final d = DateTime.tryParse('$s');
  if (d == null) return null;
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('$s')
      ? DateTime(d.year, d.month, d.day)
      : d;
}

/// `C.dansBornes(date, b)` sur une date texte : absente → faux.
bool dansBornesTexte(Object? date, Bornes b) {
  final d = jourDe(date);
  return d != null && dansBornes(d, b);
}

String _dateFRTexte(Object? s) {
  final d = jourDe(s);
  return d == null ? 'NaN/NaN/NaN' : dateFR(d);
}

String _num(num v) => nombre(v);

// ---------------------------------------------------------------------------------------------------------------------
// m6-point-ventes
// ---------------------------------------------------------------------------------------------------------------------

/// Une ligne de vente aplatie (`lignesVendues`) : chacune sait sa pièce.
class LigneVendue {
  LigneVendue({
    required this.date,
    required this.factureId,
    required this.numero,
    required this.type,
    required this.patientId,
    required this.patient,
    required this.patientCode,
    required this.assureur,
    required this.agent,
    required this.categorie,
    required this.groupe,
    required this.designation,
    required this.quantite,
    required this.prixUnitaire,
    required this.montantBrut,
    required this.remise,
    required this.motifRemise,
    required this.montant,
    required this.partAssureur,
    required this.partPersonnel,
    required this.partPatient,
    required this.regle,
    required this.montantRegle,
  });
  final String? date;
  final Object? factureId;
  final String? numero;
  final String? type;
  final Object? patientId;
  final String? patient;
  final String? patientCode;
  final String? assureur;
  final bool agent;
  final String? categorie;
  final String groupe;
  final String? designation;
  final double quantite;
  final double prixUnitaire;
  final double montantBrut;
  final double remise;
  final String? motifRemise;
  final double montant;
  final double partAssureur;
  final double partPersonnel;
  final double partPatient;
  final bool regle;
  final double montantRegle;

  /// Ce que la ligne a déjà réglé (zéro tant qu'elle n'est pas marquée « payée »).
  double get paye => regle ? montantRegle : 0;

  /// `resteLigne(l)` : la part du patient moins ce qu'il a réglé, jamais négative.
  double get reste => (partPatient - paye) < 0 ? 0 : partPatient - paye;
}

/// `lignesVendues(b)` : les lignes des factures ACTIVES dont la date tombe dans les bornes. Le groupe se lit sur la LIGNE entière
/// (le secteur de l'acte distingue la maternité du reste des soins), jamais sur la catégorie seule.
List<LigneVendue> lignesVendues(
    Iterable<Map<String, Object?>> factures, Bornes b,
    {Map<String, String?> secteurParCode = const {}}) {
  final out = <LigneVendue>[];
  for (final f in factures) {
    if (!dansBornesTexte(f['date'], b)) continue;
    final lignes = f['lignes'];
    if (lignes is! List) continue;
    for (final raw in lignes) {
      final l = (raw as Map).cast<String, Object?>();
      out.add(LigneVendue(
        date: f['date'] as String?,
        factureId: f['id'],
        numero: f['numero'] as String?,
        type: f['type'] as String?,
        patientId: f['patientId'],
        patient: f['patient'] as String?,
        patientCode: f['patientCode'] as String?,
        assureur: _vrai(f['assureur']) ? '${f['assureur']}' : null,
        agent: _vrai(f['priseEnChargePersonnel']),
        categorie: l['categorie'] as String?,
        groupe: groupePrestation(l['categorie'], l, secteurParCode)?.id ??
            'autre',
        designation: l['designation'] as String?,
        quantite: _n(l['quantite']),
        prixUnitaire: _n(l['prixUnitaire']),
        montantBrut: _n(l['montantBrut'] != null ? l['montantBrut'] : l['montant']),
        remise: _n(l['remise']),
        motifRemise: l['motifRemise'] as String?,
        montant: _n(l['montant']),
        partAssureur: _n(l['partAssureur']),
        partPersonnel: _n(l['partPersonnel']),
        partPatient: _n(l['partPatient']),
        regle: l['statutPaiement'] == 'paye',
        montantRegle: _n(l['montantRegle']),
      ));
    }
  }
  return out;
}

/// Les totaux d'un jeu de lignes : UN seul endroit qui additionne (`cumuler`).
class Cumul {
  const Cumul(this.pieces, this.lignes, this.quantite, this.brut, this.remise,
      this.net, this.assureur, this.personnel, this.patient, this.encaisse);
  final int pieces;
  final int lignes;
  final double quantite;
  final double brut;
  final double remise;
  final double net;
  final double assureur;
  final double personnel;
  final double patient;
  final double encaisse;

  /// Ce que les patients doivent encore : leur part moins ce qu'ils ont versé.
  double get resteDu => patient - encaisse;
}

Cumul cumuler(List<LigneVendue> l) => Cumul(
      grouper(l, (x) => _cle(x.factureId)).length,
      l.length,
      _somme(l, (x) => x.quantite),
      _somme(l, (x) => x.montantBrut),
      _somme(l, (x) => x.remise),
      _somme(l, (x) => x.montant),
      _somme(l, (x) => x.partAssureur),
      _somme(l, (x) => x.partPersonnel),
      _somme(l, (x) => x.partPatient),
      _somme(l.where((x) => x.regle), (x) => x.montantRegle),
    );

/// Les pourcentages demandés par la Direction, calculés sur le BRUT : une décimale (`Math.round(x / base * 1000) / 10`).
class Pourcentages {
  const Pourcentages(this.assureur, this.personnel, this.remise, this.patient);
  final double assureur;
  final double personnel;
  final double remise;
  final double patient;
}

Pourcentages pourcentages(Cumul t) {
  final base = t.brut;
  double pc(double x) => (base != 0 && !base.isNaN) ? arrondiJs(x / base * 1000) / 10 : 0;
  return Pourcentages(
      pc(t.assureur), pc(t.personnel), pc(t.remise), pc(t.patient));
}

/// Les lignes filtrées par client, groupe et article (listes vides = pas de filtre).
List<LigneVendue> filtrerVentes(List<LigneVendue> l,
        {List<String> clients = const [],
        List<String> groupes = const [],
        List<String> articles = const []}) =>
    [
      for (final x in l)
        if ((clients.isEmpty || clients.contains('${x.patientId}')) &&
            (groupes.isEmpty || groupes.contains(x.groupe)) &&
            (articles.isEmpty || articles.contains(x.designation)))
          x
    ];

/// L'intitulé du « Point » (note en tête de l'écran) : la période, les pièces, les lignes, les filtres retenus.
String noteVentes(Bornes b, Cumul t,
    {int clients = 0, int groupes = 0, int articles = 0}) {
  return '<strong>${libellePeriode(b)}</strong> — ${_num(t.pieces)} pièce(s), ${_num(t.lignes)} ligne(s) de vente.'
      '${clients > 0 ? ' Filtré sur $clients client(s).' : ''}'
      '${groupes > 0 ? ' Groupe(s) : $groupes.' : ''}'
      '${articles > 0 ? ' Article(s) : $articles.' : ''}';
}

/// 1. Le journal : une ligne par PIÈCE, la plus récente en tête.
List<Map<String, Object?>> journalVentes(List<LigneVendue> lignes) {
  final rows = <Map<String, Object?>>[];
  grouper(lignes, (x) => _cle(x.factureId)).forEach((k, g) {
    final t = cumuler(g), p2 = pourcentages(t);
    rows.add({
      'id': k,
      'numero': g.first.numero,
      'date': g.first.date,
      'patient': g.first.patient,
      'code': g.first.patientCode,
      'type': g.first.type,
      'assureur': g.first.assureur,
      'agent': g.first.agent,
      'nbLignes': g.length,
      'brut': t.brut,
      'remise': t.remise,
      'net': t.net,
      'assureurM': t.assureur,
      'personnelM': t.personnel,
      'patientM': t.patient,
      'encaisse': t.encaisse,
      'reste': t.resteDu,
      'pcAssureur': p2.assureur,
      'pcPersonnel': p2.personnel,
      'pcRemise': p2.remise,
    });
  });
  return trierStable(rows, (r) => r['date'], descendant: true);
}

/// 2. Par client : le point de caisse « pour un client choisi », le plus gros net en tête.
List<Map<String, Object?>> clientsVentes(List<LigneVendue> lignes) {
  final rows = <Map<String, Object?>>[];
  grouper(lignes, (x) => _cle(x.patientId)).forEach((k, g) {
    final t = cumuler(g), p2 = pourcentages(t);
    rows.add({
      'id': k,
      'patient': g.first.patient,
      'code': g.first.patientCode,
      'assureur': g.first.assureur,
      'agent': g.first.agent,
      'pieces': t.pieces,
      'quantite': t.quantite,
      'brut': t.brut,
      'remise': t.remise,
      'net': t.net,
      'assureurM': t.assureur,
      'personnelM': t.personnel,
      'encaisse': t.encaisse,
      'reste': t.resteDu,
      'pcAssureur': p2.assureur,
      'pcPersonnel': p2.personnel,
      'pcRemise': p2.remise,
    });
  });
  return trierStable(rows, (r) => r['net'], descendant: true);
}

/// 3. Par article : la QUANTITÉ vendue est la première colonne (c'est la question posée).
List<Map<String, Object?>> articlesVentes(List<LigneVendue> lignes) {
  final rows = <Map<String, Object?>>[];
  grouper(lignes, (x) => _cle(x.designation)).forEach((k, g) {
    final t = cumuler(g);
    final gr = groupesPrestation.where((x) => x.id == g.first.groupe);
    rows.add({
      'id': k,
      'designation': k,
      'categorie': libelleCategorieLigne(g.first.categorie),
      'groupe': gr.isEmpty ? '—' : gr.first.label,
      'quantite': t.quantite,
      'pieces': t.pieces,
      'clients': grouper(g, (x) => _cle(x.patientId)).length,
      'pu': g.first.prixUnitaire,
      'brut': t.brut,
      'remise': t.remise,
      'net': t.net,
      'encaisse': t.encaisse,
    });
  });
  return trierStable(rows, (r) => r['quantite'], descendant: true);
}

/// 4a. Par groupe de prestation (les six secteurs dans l'ordre arrêté) ; un groupe sans vente est écarté.
List<Map<String, Object?>> groupesVentes(List<LigneVendue> lignes) {
  final pg = grouper(lignes, (x) => x.groupe);
  return [
    for (final g in groupesPrestation)
      () {
        final t = cumuler(pg[g.id] ?? const []);
        return <String, Object?>{
          'id': g.id,
          'groupe': g.label,
          'quantite': t.quantite,
          'pieces': t.pieces,
          'brut': t.brut,
          'remise': t.remise,
          'net': t.net,
          'encaisse': t.encaisse,
        };
      }()
  ].where((r) => _vrai(r['net']) || _vrai(r['quantite'])).toList();
}

/// 4b. Par catégorie de ligne.
List<Map<String, Object?>> categoriesVentes(List<LigneVendue> lignes) {
  final pc = grouper(lignes, (x) => _cle(x.categorie));
  return [
    for (final c in categoriesLigne)
      () {
        final t = cumuler(pc[c.id] ?? const []);
        return <String, Object?>{
          'id': c.id,
          'categorie': c.label,
          'quantite': t.quantite,
          'net': t.net,
          'encaisse': t.encaisse,
        };
      }()
  ].where((r) => _vrai(r['net']) || _vrai(r['quantite'])).toList();
}

/// 5. L'évolution : le pas de découpage suit l'étendue demandée (au jour jusqu'à 62 jours, au mois au-delà).
class EvolutionVentes {
  const EvolutionVentes(this.parJour, this.etiquettes, this.net, this.encaisse);
  final bool parJour;
  final List<String> etiquettes;
  final List<double> net;
  final List<double> encaisse;
  bool get vide => etiquettes.isEmpty;
  String get titre => parJour ? 'Ventes par jour' : 'Ventes par mois';
}

const _mois = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre'
];

EvolutionVentes evolutionVentes(List<LigneVendue> lignes, Bornes b) {
  final parJour = b.jours <= 62;
  final cles = <String, List<LigneVendue>>{};
  final ordre = <String>[];
  for (final l in lignes) {
    final d = jourDe(l.date);
    if (d == null) continue;
    final k = parJour
        ? iso(d)
        : '${d.year}-${d.month.toString().padLeft(2, '0')}';
    if (!cles.containsKey(k)) {
      cles[k] = [];
      ordre.add(k);
    }
    cles[k]!.add(l);
  }
  ordre.sort();
  // `C.MOIS[m].slice(0, 4)` : « avril » devient « avri » — l'écran affiche cette abréviation telle quelle (écart E41).
  String mois4(String k) {
    final m = _mois[int.parse(k.split('-')[1]) - 1];
    return m.length < 4 ? m : m.substring(0, 4);
  }

  final labels = [
    for (final k in ordre)
      parJour
          ? dateFR(DateTime.parse(k)).substring(0, 5)
          : '${mois4(k)} ${k.substring(2, 4)}'
  ];
  return EvolutionVentes(
      parJour,
      labels,
      [for (final k in ordre) cumuler(cles[k]!).net],
      [for (final k in ordre) cumuler(cles[k]!).encaisse]);
}

/// 6. PAR PATIENT : ce qui a été VENDU à chaque patient retenu, secteur par secteur. C'est la désignation FACTURÉE (libellé de catalogue),
/// jamais ce qui a été trouvé : un état de ventes ne porte aucune donnée médicale (RG-13).
class BlocSecteur {
  const BlocSecteur(this.groupe, this.lignes, this.total);
  final GroupePrestation groupe;
  final List<LigneVendue> lignes;
  final Cumul total;
}

class BlocPatient {
  const BlocPatient(
      this.id, this.patient, this.code, this.assureur, this.total, this.secteurs);
  final String id;
  final String? patient;
  final String? code;
  final String? assureur;
  final Cumul total;
  final List<BlocSecteur> secteurs;

  /// « CNT/25/26 — assuré AFR » / « … — non assuré ».
  String get sousTitre =>
      '${_vrai(code) ? code : '—'}${assureur != null ? ' — assuré $assureur' : ' — non assuré'}';
}

List<BlocPatient> blocsParPatient(List<LigneVendue> lignes) {
  final pp = grouper(lignes.where((l) => _vrai(l.patientId)), (x) => _cle(x.patientId));
  return trierStable([
    for (final e in pp.entries)
      () {
        final g = e.value;
        final pg = grouper(g, (x) => x.groupe);
        return BlocPatient(
            e.key,
            g.first.patient,
            g.first.patientCode,
            g.first.assureur,
            cumuler(g),
            [
              for (final gr in groupesPrestation)
                () {
                  final l = trierStable(pg[gr.id] ?? <LigneVendue>[], (x) => x.date);
                  return BlocSecteur(gr, l, cumuler(l));
                }()
            ]);
      }()
  ], (b) => b.patient);
}

/// Les cellules d'une ligne dans le bloc d'un patient à l'écran : Date, Pièce, Désignation, Qté, Net, Part assureur, Payé, Reste dû.
List<String> cellulesLignePatient(LigneVendue l) => [
      _dateFRTexte(l.date),
      l.numero ?? '',
      l.designation ?? '',
      _num(l.quantite),
      money(l.montant, avecDevise: false),
      money(l.partAssureur, avecDevise: false),
      money(l.paye, avecDevise: false),
      money(l.reste, avecDevise: false),
    ];

/// Le résumé d'un secteur dans le bloc d'un patient : « 4 ligne(s) — 15 725 FCFA » ou « aucune vente ».
String resumeSecteur(BlocSecteur s) => s.lignes.isNotEmpty
    ? '${s.lignes.length} ligne(s) — ${money(s.total.net)}'
    : 'aucune vente';

// --- Les indicateurs de tête ---------------------------------------------------------------------------------------------

class IndicateurVentes {
  const IndicateurVentes(this.libelle, this.valeur, [this.indice]);
  final String libelle;
  final String valeur;
  final String? indice;
}

List<IndicateurVentes> indicateursVentes(Cumul t) {
  final pc = pourcentages(t);
  return [
    IndicateurVentes('Facturé brut', money(t.brut)),
    IndicateurVentes('Remises accordées', money(t.remise),
        '${texteNombreJs(pc.remise)} % du brut'),
    IndicateurVentes('Facturé net', money(t.net)),
    IndicateurVentes('Part assureur', money(t.assureur),
        '${texteNombreJs(pc.assureur)} % — créance à recouvrer'),
    IndicateurVentes('Prise en charge du personnel', money(t.personnel),
        '${texteNombreJs(pc.personnel)} % — supportée par la clinique'),
    IndicateurVentes('Encaissé', money(t.encaisse)),
    IndicateurVentes('Reste dû par les patients', money(t.resteDu)),
    IndicateurVentes(
        'Articles vendus', _num(t.quantite), 'toutes prestations confondues'),
  ];
}

// --- Les états imprimés ------------------------------------------------------------------------------------------------

sealed class BlocEtat {
  const BlocEtat();
}

class BlocEtatTexte extends BlocEtat {
  const BlocEtatTexte(this.texte, {this.gras = false});
  final String texte;
  final bool gras;
}

class BlocEtatTableau extends BlocEtat {
  const BlocEtatTableau(this.tableau);
  final TableauEtat tableau;
}

class EtatPoint {
  const EtatPoint(this.titre, this.sousTitre, this.cartouche, this.blocs);
  final String titre;
  final String sousTitre;
  final List<(String, String)> cartouche;
  final List<BlocEtat> blocs;
}

ColonneEtat _colMontant(String libelle, String cle) => ColonneEtat(
    libelle: libelle,
    valeur: (r) => money(r[cle], avecDevise: false),
    droite: true,
    somme: (r) => _n(r[cle]));

List<BlocEtat> _pagesPatients(List<LigneVendue> lignes) {
  final blocs = blocsParPatient(lignes);
  if (blocs.isEmpty) {
    return const [
      BlocEtatTexte('Aucune vente sur la période pour les clients retenus.')
    ];
  }
  final out = <BlocEtat>[];
  for (final p in blocs) {
    out.add(BlocEtatTexte(
        'Patient : ${p.patient} (${_vrai(p.code) ? p.code : '—'})',
        gras: true));
    out.add(BlocEtatTexte(
        '${p.assureur != null ? 'Assuré ${p.assureur}' : 'Non assuré'} — ${p.total.lignes} ligne(s), net facturé ${money(p.total.net, avecDevise: false)}, encaissé ${money(p.total.encaisse, avecDevise: false)}.'));
    for (final sec in p.secteurs) {
      out.add(BlocEtatTexte(sec.groupe.label, gras: true));
      if (sec.lignes.isEmpty) {
        out.add(const BlocEtatTexte('Aucune vente.'));
        continue;
      }
      out.add(BlocEtatTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Date', valeur: (l) => _dateFRTexte(l['date'])),
        ColonneEtat(libelle: 'Pièce', valeur: (l) => l['numero']),
        ColonneEtat(libelle: 'Désignation', valeur: (l) => l['designation']),
        ColonneEtat(
            libelle: 'Qté',
            valeur: (l) => _num(_n(l['quantite'])),
            droite: true,
            somme: (l) => _n(l['quantite'])),
        _colMontant('Brut', 'montantBrut'),
        _colMontant('Remise', 'remise'),
        _colMontant('Part assureur', 'partAssureur'),
        _colMontant('Payé', 'paye'),
        _colMontant('Reste dû', 'reste'),
      ], lignes: [
        for (final l in sec.lignes)
          {
            'date': l.date,
            'numero': l.numero,
            'designation': l.designation,
            'quantite': l.quantite,
            'montantBrut': l.montantBrut,
            'remise': l.remise,
            'partAssureur': l.partAssureur,
            'paye': l.paye,
            'reste': l.reste,
          }
      ])));
    }
  }
  return out;
}

/// La phrase d'un pourcentage : « 32.7 » (nombre JavaScript, une décimale au plus).
String _pcTxt(double v) => texteNombreJs(v);

/// Les états du point des ventes. [mode] : `detaille` (une ligne par pièce), `global` (les groupes, puis la synthèse) ou `patient`
/// (une page par patient). Les trois pourcentages sont énoncés EN TOUTES LETTRES sous le tableau : c'est la demande de la Direction.
EtatPoint etatVentes(String mode, List<LigneVendue> lignes, Bornes b,
    {int clients = 0, int groupes = 0, int articles = 0}) {
  final t = cumuler(lignes);
  final pc = pourcentages(t);
  final blocs = <BlocEtat>[];

  if (mode == 'patient') {
    blocs.addAll(_pagesPatients(lignes));
  } else if (mode == 'detaille') {
    final parPiece = grouper(lignes, (x) => _cle(x.factureId));
    final rows = trierStable([
      for (final g in parPiece.values)
        () {
          final tt = cumuler(g), pp = pourcentages(tt);
          return <String, Object?>{
            'date': _dateFRTexte(g.first.date),
            'dateIso': g.first.date,
            'numero': g.first.numero,
            'client': g.first.patient,
            'brut': tt.brut,
            'remise': tt.remise,
            'assureur': tt.assureur,
            'personnel': tt.personnel,
            'paye': tt.encaisse,
            'reste': tt.resteDu,
            'pcRemise': pp.remise,
            'pcAssureur': pp.assureur,
            'pcPersonnel': pp.personnel,
          };
        }()
    ], (r) => r['dateIso']);
    blocs.add(BlocEtatTableau(TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Date', valeur: (r) => r['date']),
      ColonneEtat(libelle: 'Pièce', valeur: (r) => r['numero']),
      ColonneEtat(libelle: 'Client', valeur: (r) => r['client']),
      _colMontant('Brut', 'brut'),
      _colMontant('Remise', 'remise'),
      ColonneEtat(
          libelle: '% remise',
          valeur: (r) => '${_pcTxt(_n(r['pcRemise']))} %',
          droite: true),
      _colMontant('Part assureur', 'assureur'),
      ColonneEtat(
          libelle: '% assureur',
          valeur: (r) => '${_pcTxt(_n(r['pcAssureur']))} %',
          droite: true),
      _colMontant('Personnel', 'personnel'),
      ColonneEtat(
          libelle: '% personnel',
          valeur: (r) => '${_pcTxt(_n(r['pcPersonnel']))} %',
          droite: true),
      _colMontant('Payé', 'paye'),
      _colMontant('Reste dû', 'reste'),
    ], lignes: rows)));
  } else {
    final pg = grouper(lignes, (x) => x.groupe);
    final rowsG = [
      for (final g in groupesPrestation)
        () {
          final tt = cumuler(pg[g.id] ?? const []);
          return <String, Object?>{
            'groupe': g.label,
            'quantite': tt.quantite,
            'brut': tt.brut,
            'remise': tt.remise,
            'net': tt.net,
            'paye': tt.encaisse,
          };
        }()
    ].where((r) => _vrai(r['net']) || _vrai(r['quantite'])).toList();
    blocs.add(BlocEtatTableau(TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Groupe de prestation', valeur: (r) => r['groupe']),
      ColonneEtat(
          libelle: 'Quantité',
          valeur: (r) => _num(_n(r['quantite'])),
          droite: true,
          somme: (r) => _n(r['quantite'])),
      _colMontant('Brut', 'brut'),
      _colMontant('Remise', 'remise'),
      _colMontant('Net facturé', 'net'),
      _colMontant('Encaissé', 'paye'),
    ], lignes: rowsG)));
  }

  blocs.addAll([
    const BlocEtatTexte('Répartition de la charge', gras: true),
    BlocEtatTexte(
        'Part réglée par les assureurs : ${money(t.assureur, avecDevise: false)} — ${_pcTxt(pc.assureur)} % du brut facturé. Cette part est une créance : elle se recouvre.'),
    BlocEtatTexte(
        'Part prise en charge par la clinique pour ses agents : ${money(t.personnel, avecDevise: false)} — ${_pcTxt(pc.personnel)} % du brut. Aucun tiers ne la doit ; elle ne remonte ni aux recettes ni à la comptabilité.'),
    BlocEtatTexte(
        'Remises accordées aux clients : ${money(t.remise, avecDevise: false)} — ${_pcTxt(pc.remise)} % du brut. Une remise diminue la base facturée ; elle n’est due par personne.'),
    BlocEtatTexte(
        'Reste à la charge des patients : ${money(t.patient, avecDevise: false)} — ${_pcTxt(pc.patient)} %, dont ${money(t.encaisse, avecDevise: false)} déjà encaissés et ${money(t.resteDu, avecDevise: false)} encore dus.'),
  ]);

  // Le point GLOBAL avec des clients retenus : le récapitulatif reste la première page, les pages patient suivent.
  if (mode == 'global' && clients > 0) blocs.addAll(_pagesPatients(lignes));

  final periode = libellePeriode(b);
  return EtatPoint(
    mode == 'patient'
        ? 'Point des ventes par patient'
        : (mode == 'detaille'
            ? 'Point détaillé des ventes'
            : 'Point global des ventes'),
    periode,
    [
      ('Période', periode),
      ('Pièces', _num(t.pieces)),
      ('Lignes de vente', _num(t.lignes)),
      ('Quantité totale', _num(t.quantite)),
      ('Clients retenus', clients > 0 ? _num(clients) : 'tous'),
      ('Groupes retenus', groupes > 0 ? _num(groupes) : 'tous'),
      ('Articles retenus', articles > 0 ? _num(articles) : 'tous'),
      ('Brut facturé', money(t.brut)),
    ],
    blocs,
  );
}

// ---------------------------------------------------------------------------------------------------------------------
// m6-point-stock
// ---------------------------------------------------------------------------------------------------------------------

class VueStock {
  const VueStock(this.id, this.label, this.flux);
  final String id;
  final String label;

  /// `false` : un ÉTAT, lu à une date ; `true` : un FLUX, lu sur une période.
  final bool flux;
  String get nature => flux ? 'flux' : 'etat';
}

/// Les cinq vues demandées. Le même mot les commande toutes : « ET LEUR MONTANT ».
const vuesStock = [
  VueStock('pharmacie_restant', 'Stock restant à la pharmacie', false),
  VueStock('pharmacie_recu', 'Stock reçu par la pharmacie', true),
  VueStock('magasin_nouveau', 'Stock nouveau enregistré au magasin', true),
  VueStock('magasin_sorti', 'Stock sorti par le magasin', true),
  VueStock('magasin_restant', 'Stock restant au magasin', false),
];

/// La méthode de valorisation des sorties de stock : un paramètre d'exploitation de la clinique (`S.valorisationSortie()`).
enum MethodeValorisation {
  prixVente,
  cump;

  static MethodeValorisation depuis(Object? v) =>
      v == 'cump' ? MethodeValorisation.cump : MethodeValorisation.prixVente;
  String get libelle => this == cump ? 'Coût unitaire moyen pondéré' : 'Prix de vente';
}

/// `S.valeurUnitaire(produit)` : `Math.round(cump || prixAchat || 0)` ou `Math.round(prixVente || prixAchat || 0)`.
int valeurUnitaire(Map<String, Object?> p, MethodeValorisation m) {
  double ou(Object? a, Object? b) {
    final x = _n(a);
    if (x != 0) return x;
    return _n(b);
  }

  final v = m == MethodeValorisation.cump
      ? ou(p['cump'], p['prixAchat'])
      : ou(p['prixVente'], p['prixAchat']);
  return arrondiJs(v).toInt();
}

class LigneStock {
  LigneStock({
    required this.id,
    required this.code,
    required this.designation,
    required this.unite,
    required this.famille,
    required this.quantite,
    required this.pu,
    required this.montant,
    required this.cump,
    required this.montantCump,
    this.seuil,
    this.sousSeuil = false,
    this.mouvements = 0,
  });
  final String id;
  final String? code;
  final String? designation;
  final String? unite;
  final String famille;
  final double quantite;
  final int pu;
  final double montant;
  final int cump;
  final double montantCump;
  final double? seuil;
  final bool sousSeuil;
  final int mouvements;

  /// La forme que la maquette rend à ses tableaux (`lignesFiltrees`).
  Map<String, Object?> toMap() => {
        'id': id,
        'code': code,
        'designation': designation,
        'unite': unite,
        'famille': famille,
        'quantite': quantite,
        'pu': pu,
        'montant': montant,
        'cump': cump,
        'montantCump': montantCump,
        if (seuil != null) 'seuil': seuil,
        if (mouvements > 0) 'mouvements': mouvements,
        if (seuil != null || mouvements == 0) 'sousSeuil': sousSeuil,
      };
}

String _libelleFamille(Object? categorie) =>
    familleDe(categorie)?.label ?? '$categorie';

/// `produitsRetenus()` : les produits ACTIFS des familles choisies (aucune famille = toutes).
List<Map<String, Object?>> produitsRetenus(
        Iterable<Map<String, Object?>> produits, List<String> familles) =>
    [
      for (final x in produits)
        if (familles.isEmpty || familles.contains(x['categorie'])) x
    ];

/// Les lignes d'un ÉTAT : ce qui reste, à la date, dans le stock visé (`stockGros` ou `stockDetail`). Une référence à zéro n'y figure que
/// si elle est sous son seuil.
List<LigneStock> lignesEtatStock(Iterable<Map<String, Object?>> produits,
    String champ, MethodeValorisation methode,
    {List<String> familles = const []}) {
  final out = <LigneStock>[];
  for (final x in produitsRetenus(produits, familles)) {
    final q = _n(x[champ]);
    final pu = valeurUnitaire(x, methode);
    final seuil = x['seuilAlerte'];
    final sous = seuil != null && q <= _n(seuil);
    final cumpBrut = _n(x['cump']);
    final l = LigneStock(
      id: '${x['id']}',
      code: x['code'] as String?,
      designation: x['designation'] as String?,
      unite: x['unite'] as String?,
      famille: _libelleFamille(x['categorie']),
      quantite: q,
      pu: pu,
      montant: q * pu,
      cump: arrondiJs(cumpBrut).toInt(),
      montantCump: arrondiJs(q * cumpBrut),
      seuil: seuil == null ? null : _n(seuil),
      sousSeuil: sous,
    );
    if (l.quantite > 0 || l.sousSeuil) out.add(l);
  }
  return out;
}

/// Les lignes d'un FLUX : ce qui a bougé, sur la période, pour les mouvements que retient [predicat]. Une ligne par produit, dans
/// l'ordre où le premier mouvement le rencontre.
List<LigneStock> lignesFluxStock(
    Iterable<Map<String, Object?>> produits,
    Iterable<Map<String, Object?>> mouvements,
    Bornes b,
    bool Function(Map<String, Object?>) predicat,
    MethodeValorisation methode,
    {List<String> familles = const []}) {
  final index = <String, Map<String, Object?>>{};
  for (final p in produits) {
    index['${p['id']}'] = p;
  }
  final cumulQ = <String, double>{};
  final nb = <String, int>{};
  final ordre = <String>[];
  for (final m in mouvements) {
    if (!dansBornesTexte(m['date'], b)) continue;
    if (!predicat(m)) continue;
    final pid = _cle(m['produitId']);
    final prod = index[pid];
    if (prod == null) continue;
    if (familles.isNotEmpty && !familles.contains(prod['categorie'])) continue;
    if (!cumulQ.containsKey(pid)) {
      cumulQ[pid] = 0;
      nb[pid] = 0;
      ordre.add(pid);
    }
    cumulQ[pid] = cumulQ[pid]! + _n(m['quantite']);
    nb[pid] = nb[pid]! + 1;
  }
  // `Object.keys` : les identifiants « entiers » passeraient les premiers ; ceux du jeu (PRD0001) n'en sont pas.
  final cles = grouper(ordre, (k) => k).keys;
  return [
    for (final k in cles)
      () {
        final prod = index[k]!;
        final pu = valeurUnitaire(prod, methode);
        final cump = arrondiJs(_n(prod['cump'])).toInt();
        final q = cumulQ[k]!;
        return LigneStock(
          id: k,
          code: prod['code'] as String?,
          designation: prod['designation'] as String?,
          unite: prod['unite'] as String?,
          famille: _libelleFamille(prod['categorie']),
          quantite: q,
          pu: pu,
          montant: q * pu,
          cump: cump,
          montantCump: q * cump,
          mouvements: nb[k]!,
        );
      }()
  ];
}

/// Ce que chaque vue retient. Un transfert écrit DEUX mouvements symétriques : seul le côté « détail » est une réception — compter aussi
/// la sortie du magasin doublerait ce que la pharmacie a reçu. Un transfert n'est pas une entrée NOUVELLE.
bool Function(Map<String, Object?>) predicatVue(String vueId) {
  switch (vueId) {
    case 'pharmacie_recu':
      return (m) =>
          (m['type'] == 'transfert' && m['stockType'] != 'gros') ||
          (m['type'] == 'entree' && m['stockType'] == 'detail');
    case 'magasin_nouveau':
      return (m) => m['type'] == 'entree' && m['stockType'] == 'gros';
    default:
      return (m) =>
          m['stockType'] == 'gros' &&
          const ['sortie', 'transfert', 'perte', 'casse', 'peremption']
              .contains(m['type']);
  }
}

/// Les lignes de la vue [vue] (non triées : l'écran les classe par montant décroissant).
List<LigneStock> lignesVueStock(
    VueStock vue,
    Iterable<Map<String, Object?>> produits,
    Iterable<Map<String, Object?>> mouvements,
    Bornes b,
    MethodeValorisation methode,
    {List<String> familles = const []}) {
  if (vue.id == 'pharmacie_restant') {
    return lignesEtatStock(produits, 'stockDetail', methode, familles: familles);
  }
  if (vue.id == 'magasin_restant') {
    return lignesEtatStock(produits, 'stockGros', methode, familles: familles);
  }
  return lignesFluxStock(produits, mouvements, b, predicatVue(vue.id), methode,
      familles: familles);
}

/// Le tri de l'écran et de l'état : montant décroissant, stable.
List<LigneStock> trierParMontant(List<LigneStock> l) =>
    trierStable(l, (x) => x.montant, descendant: true);

class TotauxStock {
  const TotauxStock(this.references, this.quantite, this.montant, this.montantCump);
  final int references;
  final double quantite;
  final double montant;
  final double montantCump;
}

TotauxStock totauxStock(List<LigneStock> l) => TotauxStock(
    l.length,
    _somme(l, (x) => x.quantite),
    _somme(l, (x) => x.montant),
    _somme(l, (x) => x.montantCump));

/// La note en tête du point du stock : un FLUX nomme sa période, un ÉTAT dit qu'il est indépendant d'elle.
String noteStock(VueStock vue, Bornes b) => vue.flux
    ? '<strong>${vue.label}</strong> — flux de la période : ${libellePeriode(b)}.'
    : '<strong>${vue.label}</strong> — <strong>état à date</strong>, indépendant de la périodicité choisie : ce qui reste en rayon ne dépend pas de la fenêtre qu’on regarde.';

/// Les quatre indicateurs. L'indice du montant dit « prix de vente » même quand la clinique valorise au CUMP : la maquette l'écrit en dur
/// (écart E42, porté fidèlement).
List<IndicateurVentes> indicateursStock(VueStock vue, TotauxStock t) => [
      IndicateurVentes('Références concernées', _num(t.references)),
      IndicateurVentes('Quantité', _num(t.quantite),
          vue.flux ? 'mouvements de la période' : 'unités en rayon'),
      IndicateurVentes(
          'Montant', money(t.montant), 'valorisé au prix de vente'),
      IndicateurVentes('Valorisation au CUMP', money(t.montantCump),
          'écart : ${money(t.montant - t.montantCump, avecDevise: false)}'),
    ];

/// Le cumul « par familles d'articles » dans l'ordre où les familles se présentent : c'est l'ORDRE DU GRAPHIQUE (la maquette ne trie que
/// le tableau).
List<Map<String, Object?>> cumulParFamille(List<LigneStock> l) {
  final rows = <Map<String, Object?>>[];
  grouper(l, (x) => x.famille).forEach((k, g) {
    rows.add({
      'id': k,
      'famille': k,
      'references': g.length,
      'quantite': _somme(g, (x) => x.quantite),
      'montant': _somme(g, (x) => x.montant),
    });
  });
  return rows;
}

/// … et le même cumul pour le tableau : le plus gros montant en tête.
List<Map<String, Object?>> cumulParFamilleTrie(List<LigneStock> l) =>
    trierStable(cumulParFamille(l), (r) => r['montant'], descendant: true);

/// L'état imprimé d'une vue.
EtatPoint etatStock(VueStock vue, List<LigneStock> lignes, Bornes b,
    DateTime arrete, MethodeValorisation methode,
    {int familles = 0}) {
  final l = trierParMontant(lignes);
  final flux = vue.flux;
  final periode = libellePeriode(b);
  final tot = totauxStock(l);
  return EtatPoint(
    vue.label,
    flux ? periode : 'État arrêté au ${dateFR(arrete)}',
    [
      ('Vue', vue.label),
      ('Nature', flux ? 'Flux de période' : 'État à date'),
      (flux ? 'Période' : 'Arrêté au', flux ? periode : dateFR(arrete)),
      ('Références', _num(l.length)),
      ('Quantité totale', _num(tot.quantite)),
      ('Familles retenues', familles > 0 ? _num(familles) : 'toutes'),
      ('Méthode de valorisation', methode.libelle),
      ('Montant total', money(tot.montant)),
    ],
    [
      BlocEtatTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Réf.', valeur: (r) => r['code']),
        ColonneEtat(libelle: 'Article', valeur: (r) => r['designation']),
        ColonneEtat(libelle: 'Famille', valeur: (r) => r['famille']),
        ColonneEtat(
            libelle: 'Quantité',
            valeur: (r) => '${_num(_n(r['quantite']))} ${r['unite'] ?? ''}',
            droite: true,
            somme: (r) => _n(r['quantite'])),
        ColonneEtat(
            libelle: 'P.U.',
            valeur: (r) => money(r['pu'], avecDevise: false),
            droite: true),
        _colMontant('Montant', 'montant'),
        _colMontant('Montant au CUMP', 'montantCump'),
      ], lignes: [
        for (final x in l) x.toMap()
      ])),
    ],
  );
}
