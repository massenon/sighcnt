/// Banque de sang, donneurs et statistiques des réactifs (M5) — les règles de `m5-banque-sang`, `m5-donneurs` et `m5-reactifs-stats`, extraites de
/// `prototype_html/assets/js/modules/m5-laboratoire.js` et rejouées sur des vecteurs tirés des écrans RÉELS pilotés dans Chrome
/// (`prototype_html/build/vecteurs-sang.js` → `test/vecteurs/sang.json`). Tout est préfixé `sang` : le barrel du domaine ne tolère aucune collision.
///
/// Rien n'est fourni : les statistiques sont CALCULÉES depuis le stock, les lots et le registre des demandes ; les disponibilités par groupe, depuis
/// les poches. La banque de sang est une activité FERMÉE à la clinique (`modulesActifs`, MOD01/MOD02) : ce fichier ne porte pas ce mécanisme.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../stock/delivrance.dart' show referenceSuivante;
import '../stock/stock.dart' show joursAvantPeremption;
import 'dem_regles.dart' show demExamenDe, demSections;

typedef FicheSang = Map<String, Object?>;

/// Vérité JavaScript d'une valeur de fiche.
bool _vrai(Object? v) =>
    v != null && v != false && v != 0 && v != '' && !(v is double && v.isNaN);

double _n(Object? v) => nombreOuZero(v);

/// `D.GROUPES_SANGUINS` — les huit groupes, dans l'ordre de la maquette.
const sangGroupes = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

/// Les types de don proposés au formulaire des donneurs.
const sangTypesDon = ['Bénévole', 'Familial', 'Compensation'];

/// Délai minimal entre deux dons : `delai >= 90` (jours) dans la maquette, écrit en dur.
const sangDelaiEntreDons = 90;

/// Seuil de la teinte orange de la colonne « Reste » : `j < 7` dans la maquette.
const sangResteOrange = 7;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Statistiques des réactifs — m5-reactifs-stats
// ---------------------------------------------------------------------------------------------------------------------------------------------

class SangStatsReactifs {
  const SangStatsReactifs({
    required this.references,
    required this.valeur,
    required this.sousSeuil,
    required this.sansSeuil,
    required this.perimes,
    required this.alerte,
    required this.parSection,
  });

  /// Réactifs et consommables de laboratoire (`categorie` = `reactif` ou `conso_labo`), dans l'ordre du registre.
  final List<FicheSang> references;

  /// Σ stock × prix d'achat.
  final double valeur;

  /// Stock ≤ seuil, SEUIL FIXÉ : un seuil absent n'est pas un seuil de zéro.
  final List<FicheSang> sousSeuil;
  final List<FicheSang> sansSeuil;

  /// Lots (de ces références) dont le statut vaut `perime` / `alerte`.
  final int perimes;
  final int alerte;

  /// Demandes par section, du plus fréquent au moins fréquent (à égalité : l'ordre d'apparition).
  final List<({String section, int demandes})> parSection;
}

/// `seuilAlerte != null && stock <= seuilAlerte`. Un stock absent n'est comparé à rien (`undefined <= n` est faux en JS).
bool sangSousSeuil(FicheSang p) =>
    p['seuilAlerte'] != null &&
    p['stock'] != null &&
    _n(p['stock']) <= _n(p['seuilAlerte']);

/// La section d'une demande : la section de l'examen du catalogue qui répond à sa désignation (`L.section`), sinon sa catégorie, sinon « Autres ».
String sangSectionDemande(FicheSang demande, Iterable<FicheSang> examens) {
  final ex = demExamenDe(demande, examens);
  if (ex != null) return demSections['${ex['section']}'] ?? '${ex['section']}';
  return _vrai(demande['categorie']) ? '${demande['categorie']}' : 'Autres';
}

SangStatsReactifs sangStatsReactifs({
  required Iterable<FicheSang> produits,
  required Iterable<FicheSang> lots,
  required Iterable<FicheSang> demandes,
  required Iterable<FicheSang> examens,
}) {
  final refs = [
    for (final p in produits)
      if (p['categorie'] == 'reactif' || p['categorie'] == 'conso_labo') p
  ];
  final ids = {for (final p in refs) p['id']};
  final lotsRef = [
    for (final l in lots)
      if (ids.contains(l['produitId'])) l
  ];
  final parSection = <String, int>{};
  for (final r in demandes) {
    final s = sangSectionDemande(r, examens);
    parSection[s] = (parSection[s] ?? 0) + 1;
  }
  // Tri décroissant STABLE (Array.prototype.sort de V8) : à égalité, l'ordre d'apparition.
  final ordre = parSection.entries.toList();
  final rang = {for (var i = 0; i < ordre.length; i++) ordre[i].key: i};
  ordre.sort((a, b) {
    final d = b.value - a.value;
    return d != 0 ? d : rang[a.key]! - rang[b.key]!;
  });
  return SangStatsReactifs(
    references: refs,
    valeur: refs.fold<double>(0, (n, p) => n + _n(p['stock']) * _n(p['prixAchat'])),
    sousSeuil: [for (final p in refs) if (sangSousSeuil(p)) p],
    sansSeuil: [for (final p in refs) if (p['seuilAlerte'] == null) p],
    perimes: lotsRef.where((l) => l['statut'] == 'perime').length,
    alerte: lotsRef.where((l) => l['statut'] == 'alerte').length,
    parSection: [for (final e in ordre) (section: e.key, demandes: e.value)],
  );
}

/// Valeur d'une ligne du tableau : stock × prix d'achat (un champ absent vaut zéro).
double sangValeurReference(FicheSang p) => _n(p['stock']) * _n(p['prixAchat']);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Banque de sang — m5-banque-sang
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Disponible : ni périmée (l'ÉTAT enregistré, pas la date — écart E201) ni réservée.
bool sangPocheDisponible(FicheSang p) => p['etat'] != 'perime' && !_vrai(p['reserve']);

class SangKpisBanque {
  const SangKpisBanque(this.enStock, this.disponibles, this.alerte, this.perimees);
  final int enStock;
  final int disponibles;

  /// Péremption sous 7 jours — `etat == 'alerte'`.
  final int alerte;

  /// Périmées à détruire — `etat == 'perime'`.
  final int perimees;
}

SangKpisBanque sangKpisBanque(Iterable<FicheSang> poches) => SangKpisBanque(
      poches.length,
      poches.where(sangPocheDisponible).length,
      poches.where((p) => p['etat'] == 'alerte').length,
      poches.where((p) => p['etat'] == 'perime').length);

/// Poches disponibles d'un groupe.
int sangDisponiblesGroupe(Iterable<FicheSang> poches, String groupe) =>
    poches.where((p) => sangPocheDisponible(p) && p['groupe'] == groupe).length;

/// Teinte de la carte d'un groupe : aucune poche → danger ; une ou deux → attention ; au-delà → succès.
String sangTonGroupe(int disponibles) =>
    disponibles == 0 ? 'danger' : (disponibles <= 2 ? 'warning' : 'success');

/// « poche » au singulier jusqu'à une poche, « poches » au-delà (zéro est singulier, comme la maquette).
String sangMotPoche(int n) => n > 1 ? 'poches' : 'poche';

/// « O+ (2), O- (2), … » — la ligne « Disponibilité au … » du bon de demande de sang.
String sangLigneDisponibilite(Iterable<FicheSang> poches) =>
    sangGroupes.map((g) => '$g (${sangDisponiblesGroupe(poches, g)})').join(', ');

/// Jours restants avant la péremption (calendaires, écart E17) ; `null` si la date manque ou est illisible.
int? sangResteJours(DateTime auj, FicheSang p) =>
    joursAvantPeremption(auj, p['datePeremption']);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Donneurs — m5-donneurs
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Jours écoulés depuis le dernier don ; `null` si la date manque.
int? sangDelaiDon(DateTime auj, FicheSang d) {
  final j = joursAvantPeremption(auj, d['dernierDon']);
  return j == null ? null : -j;
}

/// La colonne « Éligibilité » : « Non éligible » (rouge) si la fiche l'écrit ; « Éligible » (vert) si le délai de 90 jours est écoulé ; sinon
/// « Délai N j » (orange), N étant le temps qui reste. Sans date de dernier don, la maquette écrit « Délai NaN j » (écart E202) : le poste écrit
/// « Délai inconnu ».
({String libelle, String ton}) sangEligibilite(DateTime auj, FicheSang d) {
  if (!_vrai(d['eligible'])) return (libelle: 'Non éligible', ton: 'danger');
  final delai = sangDelaiDon(auj, d);
  if (delai == null) return (libelle: 'Délai inconnu', ton: 'warning');
  return delai >= sangDelaiEntreDons
      ? (libelle: 'Éligible', ton: 'success')
      : (libelle: 'Délai ${sangDelaiEntreDons - delai} j', ton: 'warning');
}

/// Éligible ET délai écoulé — ce que compte l'indicateur « Éligibles ».
bool sangDonneurDisponible(DateTime auj, FicheSang d) {
  if (!_vrai(d['eligible'])) return false;
  final delai = sangDelaiDon(auj, d);
  return delai != null && delai >= sangDelaiEntreDons;
}

class SangKpisDonneurs {
  const SangKpisDonneurs(this.donneurs, this.eligibles, this.dons, this.benevoles);
  final int donneurs;
  final int eligibles;
  final num dons;
  final int benevoles;
}

SangKpisDonneurs sangKpisDonneurs(DateTime auj, Iterable<FicheSang> donneurs) =>
    SangKpisDonneurs(
        donneurs.length,
        donneurs.where((d) => sangDonneurDisponible(auj, d)).length,
        donneurs.fold<num>(0, (n, d) => n + _n(d['nbDons'])),
        donneurs.where((d) => d['type'] == 'Bénévole').length);

/// `onCreate` : un donneur nouveau est éligible, a donné une fois, à titre bénévole, aujourd'hui.
Map<String, Object?> sangValeursInitialesDonneur(DateTime auj) => {
      'eligible': true,
      'nbDons': '1',
      'type': 'Bénévole',
      'dernierDon': iso(auj),
    };

/// `transform` : la référence `DON-NNNN` n'est attribuée qu'à la création — rang suivant lu sur les fiches existantes, archivées comprises
/// (`C.referenceSuivante`, écart E200 : la maquette utilisait un compteur de page). Une fiche corrigée garde la sienne. Les nombres saisis en
/// texte redeviennent des nombres.
FicheSang sangFicheDonneur(Map<String, Object?> saisie,
    {required Iterable<FicheSang> existants, FicheSang? ancienne}) {
  final f = <String, Object?>{...saisie};
  final nb = saisie['nbDons'];
  if (nb is String) f['nbDons'] = nb.trim().isEmpty ? null : (num.tryParse(nb.trim()) ?? nb);
  if (!_vrai(f['reference'])) {
    f['reference'] = ancienne != null && _vrai(ancienne['reference'])
        ? ancienne['reference']
        : referenceSuivante('DON-', 4, existants);
  }
  return f;
}

/// `transform` sur les valeurs numériques d'une poche corrigée (`volume` saisi en texte).
FicheSang sangFichePoche(Map<String, Object?> saisie) {
  final f = <String, Object?>{...saisie};
  final v = saisie['volume'];
  if (v is String) f['volume'] = v.trim().isEmpty ? null : (num.tryParse(v.trim()) ?? v);
  return f;
}
