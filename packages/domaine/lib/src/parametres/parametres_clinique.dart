// LES PARAMÈTRES DE CLINIQUE (lot PARAM-CLINIQUE, 16/11/2026 ; décisions 10 et 14 de la Direction du 15/11/2026, section AH).
//
// Port de la maquette (`prototype_html/assets/js/data.js` : `PARAMETRES_CLINIQUE`, `parametreCliniqueALaDate`, `statutLotALaDate`, `trancheCreance`, `libellesTranches` ;
// `parcours.js` : `SIGH.parametresClinique.controler`), rejoué sur les vecteurs tirés de l'écran réel « Règles métier versionnées »
// (`prototype_html/build/vecteurs-parametres-clinique.js` → `test/vecteurs/parametres_clinique.json`).
//
// Le préavis de péremption des lots (RG-05, 90 jours semés) et les deux bornes des tranches de la balance âgée (30 et 90 jours semés) sont des PARAMÈTRES
// DE CLINIQUE en base, versionnés par date (au poste : la collection `parametres` du lot L0, famille `clinique` : réglage de BRANCHE posé à la mère, jamais
// vers un téléphone). Aucun écran ne relit une constante : la valeur se LIT à la date. Les BORNES sont une proposition à valider (aucun document ne les fixe).
library;

import '../maj/maj.dart' show ReglagesMaj;
import 'parametres.dart';

/// La famille des paramètres de clinique (réglage de branche, fermée aux téléphones : [parFamillesJamaisMobile]).
const String pcFamille = 'clinique';

/// Le geste réservé de la fiche RBAC qui règle ces paramètres (décision 5 : un droit propre) ; d'origine l'administrateur et la Directrice Administrative.
const String pcGesteRegler = 'regler_parametres_clinique';

const String pcCleDelaiPeremption = 'stock.delaiPeremptionJours';
const String pcCleTrancheCourte = 'creances.trancheCourteJours';
const String pcCleTrancheLongue = 'creances.trancheLongueJours';

/// Lot PTA : la tolérance (jours) après la fin du trimestre d'une action du plan annuel avant l'alerte de retard (défaut 0, bornes à valider).
const String pcCleGraceRetardPlan = 'plan.graceRetardJours';

/// Lot MAJ (17/11/2026) : les trois réglages de la mise à jour du logiciel, lus au poste par `reglagesMajDe` (valeurs d'attente et bornes à valider, section BG).
const String pcCleMajAgeCopie = 'maj.ageMaxCopieHeures';
const String pcCleMajRetourArriere = 'maj.retourArriereMinutes';
const String pcCleMajEcartVersion = 'maj.ecartVersionTolere';

const String _source = 'Valeur d’avant (constante du code), semée telle quelle : décisions 10 et 14 de la Direction du 15/11/2026 (DECISIONS-A-VALIDER, section AH)';

/// Ce qu'une clé déclare de plus qu'une définition L0 : ses bornes (entier de [min] à [max]) et son unité.
class BornesParametreClinique {
  const BornesParametreClinique(this.cle, this.min, this.max, {this.unite = 'jours'});
  final String cle;
  final int min, max;
  final String unite;
}

const List<BornesParametreClinique> pcBornes = [
  BornesParametreClinique(pcCleDelaiPeremption, 1, 730),
  BornesParametreClinique(pcCleTrancheCourte, 1, 365),
  BornesParametreClinique(pcCleTrancheLongue, 2, 730),
  BornesParametreClinique(pcCleGraceRetardPlan, 0, 90),
  BornesParametreClinique(pcCleMajAgeCopie, 1, 168, unite: 'heures'),
  BornesParametreClinique(pcCleMajRetourArriere, 5, 480, unite: 'minutes'),
  BornesParametreClinique(pcCleMajEcartVersion, 0, 5, unite: 'version(s)'),
];

BornesParametreClinique? pcBornesDe(String cle) {
  for (final b in pcBornes) {
    if (b.cle == cle) return b;
  }
  return null;
}

/// Les trois définitions du registre L0 (défauts SEMÉS : la version 0 de chaque clé). Réglées à l'écran « Règles métier versionnées » (droit, motif, bornes),
/// pas au panneau générique ([parFamillesReglageDedie]).
const List<DefinitionParametre> pcDefinitions = [
  DefinitionParametre(
    cle: pcCleDelaiPeremption,
    famille: pcFamille,
    type: TypeParametre.entier,
    defaut: 90,
    libelle: 'Préavis de péremption des lots (jours)',
    aide: 'Un lot dont la date de péremption tombe dans ce délai est « péremption proche » : alerte, tableau de bord, ordre FEFO (RG-05). Entier de 1 à 730.',
    source: _source,
    branche: true,
    appliquePar: 'Lot PARAM-CLINIQUE',
  ),
  DefinitionParametre(
    cle: pcCleTrancheCourte,
    famille: pcFamille,
    type: TypeParametre.entier,
    defaut: 30,
    libelle: 'Balance âgée : fin de la première tranche (jours)',
    aide: 'Une créance de ce nombre de jours ou moins est dans la première tranche. Entier de 1 à 365, plus petit que la fin de la deuxième tranche.',
    source: _source,
    branche: true,
    appliquePar: 'Lot PARAM-CLINIQUE',
  ),
  DefinitionParametre(
    cle: pcCleTrancheLongue,
    famille: pcFamille,
    type: TypeParametre.entier,
    defaut: 90,
    libelle: 'Balance âgée : fin de la deuxième tranche (jours)',
    aide: 'Au-delà de ce nombre de jours, la créance est dans la dernière tranche (relance impérative). Entier de 2 à 730, plus grand que la fin de la première tranche.',
    source: _source,
    branche: true,
    appliquePar: 'Lot PARAM-CLINIQUE',
  ),
  DefinitionParametre(
    cle: pcCleGraceRetardPlan,
    famille: pcFamille,
    type: TypeParametre.entier,
    defaut: 0,
    libelle: 'Plan annuel : jours de tolérance après la fin du trimestre avant l’alerte de retard',
    aide: 'Une action non réalisée alerte quand son trimestre de fin est passé de plus de ce nombre de jours. Entier de 0 à 90 (0 : dès le lendemain).',
    source: 'Lot PTA (16/11/2026) : défaut 0, bornes à valider par la Direction',
    branche: true,
    appliquePar: 'Lot PTA',
  ),
  DefinitionParametre(
    cle: pcCleMajAgeCopie,
    famille: pcFamille,
    type: TypeParametre.entier,
    defaut: 24,
    libelle: 'Mise à jour : ancienneté maximale de la copie vérifiée (heures)',
    aide: 'Sans copie vérifiée de moins de ce nombre d’heures, une migration ou un import refuse (MAJ_SANS_SAUVEGARDE). Entier de 1 à 168.',
    source: 'Lot MAJ (17/11/2026) : défaut 24 h du PRD, bornes à valider par la Direction',
    branche: true,
    appliquePar: 'Lot MAJ',
  ),
  DefinitionParametre(
    cle: pcCleMajRetourArriere,
    famille: pcFamille,
    type: TypeParametre.entier,
    defaut: 30,
    libelle: 'Mise à jour : durée visée du retour arrière (minutes)',
    aide: 'Durée à laquelle la Direction s’attend pour revenir à la dernière copie vérifiée (objectif affiché, jamais un blocage). Entier de 5 à 480.',
    source: 'Lot MAJ (17/11/2026) : valeur d’attente de 30 minutes du PRD, à valider par la Direction',
    branche: true,
    appliquePar: 'Lot MAJ',
  ),
  DefinitionParametre(
    cle: pcCleMajEcartVersion,
    famille: pcFamille,
    type: TypeParametre.entier,
    defaut: 1,
    libelle: 'Mise à jour : écart de version de format toléré entre la mère et un fileul',
    aide: 'Au-delà de cet écart, la mère répond 426 schema_incompatible et le fileul garde ses saisies hors ligne. Entier de 0 à 5.',
    source: 'Lot MAJ (17/11/2026) : défaut d’une version, à valider par la Direction',
    branche: true,
    appliquePar: 'Lot MAJ',
  ),
];

/// Un refus nommé du contrôle : code, motif, geste.
class RefusParametreClinique {
  const RefusParametreClinique(this.code, this.motif, this.geste);
  final String code, motif, geste;
  Map<String, Object?> toJson() => {'ok': false, 'code': code, 'motif': motif, 'geste': geste};
  @override
  String toString() => '$code : $motif';
}

DefinitionParametre? _def(String cle) {
  for (final d in pcDefinitions) {
    if (d.cle == cle) return d;
  }
  return null;
}

num? _nombre(Object? v) {
  if (v is num) return v;
  if (v is String && v.trim().isNotEmpty) return num.tryParse(v.trim());
  return null;
}

/// `SIGH.parametresClinique.controler(cle, valeur, autres)` : `null` si la valeur est recevable, sinon le refus nommé. [autres] : la valeur des autres clés
/// à la même date (cohérence des deux tranches).
RefusParametreClinique? pcControler(String cle, Object? valeur, {Map<String, Object?> autres = const {}}) {
  final def = _def(cle), b = pcBornesDe(cle);
  if (def == null || b == null) {
    return RefusParametreClinique('PARAMETRE_CLINIQUE_INCONNU', 'Le paramètre « $cle » n’existe pas parmi les paramètres de clinique.', 'Choisir un paramètre listé à l’écran « Règles métier versionnées ».');
  }
  final n = _nombre(valeur);
  if (n == null || !n.isFinite || n != n.floor() || n < b.min || n > b.max) {
    return RefusParametreClinique('PARAMETRE_HORS_BORNES', '« ${def.libelle} » est un nombre entier de ${b.min} à ${b.max} ${b.unite} (reçu « ${valeur ?? 'null'} »).',
        'Saisir un nombre entier de ${b.min} à ${b.max}.');
  }
  if (cle == pcCleTrancheCourte || cle == pcCleTrancheLongue) {
    final courte = cle == pcCleTrancheCourte ? n : _nombre(autres[pcCleTrancheCourte]);
    final longue = cle == pcCleTrancheLongue ? n : _nombre(autres[pcCleTrancheLongue]);
    if (courte != null && longue != null && !(courte < longue)) {
      String e(num x) => x == x.truncate() ? '${x.toInt()}' : '$x';
      return RefusParametreClinique('TRANCHES_INCOHERENTES', 'La fin de la première tranche (${e(courte)} jours) doit être plus petite que la fin de la deuxième (${e(longue)} jours).',
          'Saisir une première tranche plus courte que la deuxième, ou régler d’abord l’autre borne.');
    }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LECTURE À LA DATE
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// La résolution de la MAQUETTE sur ses fiches (`parametresClinique` : `cle`, `valeur`, `dateEffet` AAAA-MM-JJ ou `null`, `creeLe`, `id`, `statut`) : la plus
/// grande date d'effet qui ne dépasse pas [date], à égalité la plus récemment créée ; les archivées sont ignorées ; sans version, le défaut de la définition.
({num? valeur, String? dateEffet, String origine, String? versionId}) pcResoudreFiches(List<Map<String, Object?>> fiches, String cle, String date) {
  final vs = [
    for (final f in fiches)
      if (f['statut'] != 'archive' && f['cle'] == cle) f
  ]..sort((a, b) {
      final c = '${a['dateEffet'] ?? ''}'.compareTo('${b['dateEffet'] ?? ''}');
      if (c != 0) return c;
      final d = '${a['creeLe'] ?? ''}'.compareTo('${b['creeLe'] ?? ''}');
      return d != 0 ? d : '${a['id']}'.compareTo('${b['id']}');
    });
  Map<String, Object?>? v;
  for (final f in vs) {
    final d = f['dateEffet'];
    if (d == null || '$d'.length < 10 || '$d'.substring(0, 10).compareTo(date) <= 0) v = f;
  }
  if (v == null) return (valeur: _def(cle)?.defaut as num?, dateEffet: null, origine: 'defaut', versionId: null);
  return (valeur: _nombre(v['valeur']), dateEffet: v['dateEffet'] as String?, origine: 'version', versionId: '${v['id']}');
}

/// La valeur ENTIÈRE en vigueur de [cle] à [date] (AAAA-MM-JJ), lue au registre L0 du poste ([versions] : les fiches de la collection `parametres`). Sans
/// version, le défaut SEMÉ de la définition (le même sur tous les postes).
int pcValeur(List<Map<String, Object?>> versions, String cle, String date) {
  final r = Parametres.resoudre(cle, [for (final f in versions) if (f['statut'] != 'archive' && f['cle'] == cle) Parametre.fromJson(f)], date, definition: _def(cle));
  final v = r.ok ? r.valeur!.valeur : _def(cle)!.defaut;
  return (v is num ? v : num.parse('$v')).toInt();
}

/// RG-05 : le préavis de péremption en vigueur à [date].
int pcDelaiPeremption(List<Map<String, Object?>> versions, String date) => pcValeur(versions, pcCleDelaiPeremption, date);

/// Les deux bornes de la balance âgée en vigueur à [date].
class TranchesCreances {
  const TranchesCreances(this.courte, this.longue);
  final int courte, longue;
}

TranchesCreances pcTranches(List<Map<String, Object?>> versions, String date) =>
    TranchesCreances(pcValeur(versions, pcCleTrancheCourte, date), pcValeur(versions, pcCleTrancheLongue, date));

/// `D.trancheCreance(jours, t)` : 'moins30' (première tranche), '30a90' (deuxième), 'plus90' (dernière). Les identifiants restent ceux des écrans.
String pcTrancheCreance(int jours, TranchesCreances t) => jours <= t.courte ? 'moins30' : (jours <= t.longue ? '30a90' : 'plus90');

/// `D.libellesTranches(t)` : les libellés longs et courts, tirés des bornes lues (jamais « 30 » ou « 90 » écrits dans un écran).
({String moins30, String de30a90, String plus90, String courtMoins30, String courtDe30a90, String courtPlus90}) pcLibellesTranches(TranchesCreances t) => (
      moins30: '${t.courte} jours ou moins',
      de30a90: 'De ${t.courte + 1} à ${t.longue} jours',
      plus90: 'Au-delà de ${t.longue} jours',
      courtMoins30: '≤ ${t.courte} j',
      courtDe30a90: '${t.courte + 1} à ${t.longue} j',
      courtPlus90: '> ${t.longue} j',
    );

/// `D.statutLotALaDate(l, date)` selon le préavis [preavis] lu à cette date : 'perime', 'alerte' ou 'actif' ; sans date de péremption, le statut écrit.
String pcStatutLot(Map<String, Object?> lot, String date, int preavis) {
  final p = '${lot['datePeremption'] ?? ''}';
  if (p.isEmpty) return '${lot['statut']}';
  final a = DateTime.parse('${p.substring(0, 10)}T00:00:00Z'), b = DateTime.parse('${date}T00:00:00Z');
  final j = (a.difference(b).inHours / 24).round();
  return j < 0 ? 'perime' : (j <= preavis ? 'alerte' : 'actif');
}

/// Lot MAJ : les réglages de la mise à jour en vigueur à [date] (AAAA-MM-JJ), lus au registre : jamais une constante du code.
ReglagesMaj reglagesMajDe(List<Map<String, Object?>> versions, String date) => ReglagesMaj(
    ageMaxCopieHeures: pcValeur(versions, pcCleMajAgeCopie, date),
    retourArriereMinutes: pcValeur(versions, pcCleMajRetourArriere, date),
    ecartVersionTolere: pcValeur(versions, pcCleMajEcartVersion, date));
