/// M10 (B) — planning & gardes, statistiques de garde / de permanence / de présence, registre des présences, évaluations NS 131, sanctions, primes NS 132.
/// Symboles préfixés `rhb` / `Rhb`. Source : `prototype_html/assets/js/modules/m10-rh.js` et `data.js` ; vecteurs : `test/vecteurs/rhb.json`
/// (engendrés par `prototype_html/build/vecteurs-rh-b.js`, écrans montés dans Chrome).
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart' show trierPar;
import '../referentiels/periodes.dart';
import '../referentiels/regles.dart' show joursEntre;
import '../stock/points.dart' show dansBornesTexte;

typedef FicheRhb = Map<String, Object?>;

// ---------------------------------------------------------------------------------------------------------------------
// Référentiels (data.js)
// ---------------------------------------------------------------------------------------------------------------------

class RhbTypePlanning {
  const RhbTypePlanning(this.id, this.label, this.court, this.debut, this.fin, this.couleur, this.duree);
  final String id, label, court, couleur;
  final String? debut, fin;
  final double duree;
}

/// `D.TYPES_PLANNING` — transcrits des plannings réels de la clinique.
const rhbTypesPlanning = <RhbTypePlanning>[
  RhbTypePlanning('garde', 'Garde 24h', 'G', '08:00', '08:00', 'danger', 24),
  RhbTypePlanning('garde_hospi', 'Garde hospitalisation', 'GH', '08:00', '08:00', 'danger', 24),
  RhbTypePlanning('garde_soins', 'Garde soins', 'GS', '08:00', '18:30', 'warning', 10.5),
  RhbTypePlanning('permanence', 'Permanence', 'P', '08:00', '18:00', 'info', 10),
  RhbTypePlanning('soiree', 'Soirée', 'S', '18:00', '08:00', 'navy', 14),
  RhbTypePlanning('entretien_general', 'Entretien général de la journée', 'EGJ', '08:00', '18:00', 'info', 10),
  RhbTypePlanning('repos24', 'Repos 24h', 'R', null, null, 'neutral', 0),
  RhbTypePlanning('repos48', 'Repos 48h', 'R48', null, null, 'neutral', 0),
  RhbTypePlanning('conge', 'Congé', 'C', null, null, 'success', 0),
  RhbTypePlanning('absence', 'Absence', 'A', null, null, 'warning', 0),
  RhbTypePlanning('remplacement', 'Remplacement', 'Rp', null, null, 'navy', 0),
  RhbTypePlanning('incineration', 'Incinération des déchets', 'INC', '16:00', '18:00', 'warning', 2),
];

RhbTypePlanning? rhbTypePlanning(Object? id) {
  for (final t in rhbTypesPlanning) {
    if (t.id == id) return t;
  }
  return null;
}

String rhbTypePlanningLabel(Object? id) => rhbTypePlanning(id)?.label ?? '$id';
String rhbTypePlanningTon(Object? id) => rhbTypePlanning(id)?.couleur ?? 'neutral';

/// `REGLES_PLANNING` — le régime de travail de chaque catégorie, relevé sur les plannings. Le MAGASIN les porte aussi (`regimesTravail`,
/// administrable) ; cette liste est le repli (`D.regleDe`).
class RhbRegle {
  const RhbRegle(this.fonctions, this.libelle, this.vacations, this.repos, this.cycle, this.source, this.mention,
      {this.honoraire, this.honorairePeriodicite});
  final List<String> fonctions, vacations;
  final String libelle, source, mention;
  final String? repos, honorairePeriodicite;
  final int cycle;
  final int? honoraire;
}

const rhbReglesPlanning = <RhbRegle>[
  RhbRegle(['medecin'], 'Médecins', ['garde'], 'repos48', 2, 'Planning de travail des médecins',
      'Garde de 24 h (08h→08h), suivie d’un repos de 48 h.'),
  RhbRegle(['infirmier'], 'Infirmiers', ['garde_soins', 'garde_hospi'], 'repos48', 3, 'Planning de travail des infirmiers',
      'Deux postes distincts : garde soins de 08h à 18h30 et garde hospitalisation de 08h à 08h. Vingt jours travaillés par mois et par agent.'),
  RhbRegle(['sage_femme'], 'Sages-femmes', ['garde'], 'repos24', 2, 'Planning de travail des sages-femmes',
      'Garde de 24 h en alternance quotidienne, suivie d’un repos de 24 h.'),
  RhbRegle(['aide_soignant'], 'Aides-soignants', ['garde'], 'repos48', 3, 'Planning de travail des aides-soignants',
      'Rotation à trois : un agent de garde, deux au repos.'),
  RhbRegle(['accueil', 'caissiere'], 'Secrétaires médicaux et caisse', ['garde', 'permanence'], 'repos24', 3,
      'Planning de travail des secrétaires', 'Garde de 24 h et permanence de 08h à 18h ; pas de permanence le dimanche.'),
  RhbRegle(['entretien'], 'Agents d’entretien', ['permanence', 'entretien_general'], null, 3, 'Planning des agents d’entretien',
      'Rotation « P » (permanence) et « EGJ » (entretien général de la journée).'),
  RhbRegle(['securite'], 'Agents de sécurité', ['garde', 'soiree'], 'repos24', 3, 'Planning des agents de sécurité',
      'Rotation « G » (garde 24 h), « S » (soirée de 18h à 8h) et « R » (repos).'),
  RhbRegle(['aide_soignant', 'entretien'], 'Incinération des déchets de l’hôpital', ['incineration'], null, 7,
      'NS n° 132/07/DM/DA/CNT/2026 — prime d’incinération',
      'Incinération des déchets hospitaliers, poste hebdomadaire rémunéré 5 000 FCFA par mois au titre de la prime d’incinération (NS 132).',
      honoraire: 5000, honorairePeriodicite: 'mensuelle'),
];

RhbRegle? rhbRegleDe(String? fonction) {
  for (final r in rhbReglesPlanning) {
    if (r.fonctions.contains(fonction)) return r;
  }
  return null;
}

/// Un régime lu au magasin (`regimesTravail`) ou, à défaut, au repli : ce que l'écran en fait (libellé, vacations, repos, mention).
class RhbRegimeVu {
  const RhbRegimeVu(this.libelle, this.vacations, this.repos, this.mention);
  final String libelle, mention;
  final List<String> vacations;
  final String? repos;
}

List<String> _liste(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

/// `regleDe(fonction)` de l'écran de planning : le premier régime ACTIF du magasin qui couvre la fonction, sinon le repli de `data.js`.
RhbRegimeVu? rhbRegimeDe(List<FicheRhb> regimesActifs, String? fonction) {
  for (final r in regimesActifs) {
    if (_liste(r['fonctions']).contains(fonction)) {
      return RhbRegimeVu('${r['libelle']}', _liste(r['vacations']), r['repos'] == null || r['repos'] == '' ? null : '${r['repos']}', '${r['mention'] ?? ''}');
    }
  }
  final d = rhbRegleDe(fonction);
  return d == null ? null : RhbRegimeVu(d.libelle, d.vacations, d.repos, d.mention);
}

const rhbServices = [
  'Médecine générale', 'Maternité', 'Chirurgie', 'Laboratoire', 'Pharmacie',
  'Imagerie / Échographie', 'Soins infirmiers', 'Accueil', 'Direction', 'Comptabilité',
];

class RhbFonction {
  const RhbFonction(this.id, this.label, this.categorie);
  final String id, label, categorie;
}

const rhbFonctions = <RhbFonction>[
  RhbFonction('aide_soignant', 'Aide-soignant(e)', 'Paramédical'),
  RhbFonction('caissiere', 'Caissière', 'Administratif'),
  RhbFonction('accueil', 'Accueil / Secrétaire médical', 'Administratif'),
  RhbFonction('infirmier', 'Infirmier(ère)', 'Paramédical'),
  RhbFonction('sage_femme', 'Sage-femme', 'Paramédical'),
  RhbFonction('tsl', 'TSL (Technicien Supérieur de Laboratoire)', 'Technique'),
  RhbFonction('biomedical', 'Ingénieur biomédical', 'Technique'),
  RhbFonction('medecin', 'Médecin', 'Médical'),
  RhbFonction('direction', 'Direction', 'Direction'),
  RhbFonction('comptable', 'Comptable', 'Administratif'),
  RhbFonction('stock', 'Gestionnaire de stock', 'Logistique'),
  RhbFonction('dispensatrice', 'Dispensatrice', 'Pharmacie'),
  RhbFonction('securite', 'Agent de sécurité', 'Support'),
  RhbFonction('entretien', 'Agent d’entretien', 'Support'),
  RhbFonction('chauffeur', 'Chauffeur coursier', 'Support'),
];

/// `fonctionLabel(id)` — l'identifiant lui-même s'il est inconnu.
String rhbFonctionLabel(Object? id) {
  for (final f in rhbFonctions) {
    if (f.id == id) return f.label;
  }
  return '$id';
}

// ---------------------------------------------------------------------------------------------------------------------
// NS 131 — barème d'évaluation et de sanction (statique : c'est lui que lisent les évaluations, voir E650)
// ---------------------------------------------------------------------------------------------------------------------

const rhbNs131Reference = 'NS 131/07/DM/DA/CNT/2026';
const rhbNs131DateEffet = '2026-07-13';
const rhbNs131DateSignature = '2026-07-13';
const rhbNs131Version = 1;
const rhbNs131Statut = 'ACTIVE';
const rhbNs131Signataire = 'BASSONGUI C. Séko Y., Directeur Médical';
const rhbNs131Ampliation = 'Intéressés 41 — Archive 01';
const rhbNs131Mention = 'Abroge toute disposition antérieure contraire.';

class RhbNiveau {
  const RhbNiveau(this.id, this.label, this.aide);
  final String id, label, aide;
}

const rhbNiveaux = <RhbNiveau>[
  RhbNiveau('bonne', 'Bonne', 'Aucune sanction'),
  RhbNiveau('moyenne', 'Moyenne', '1er niveau de faute — 1 à 2 manquements'),
  RhbNiveau('faible', 'Faible à mauvaise', '2e niveau de faute — 3 manquements et plus'),
];

class RhbCritere {
  const RhbCritere(this.num, this.id, this.label, this.criteres, this.moyenne, this.faible);
  final String num, id, label;
  final List<String> criteres;
  final int moyenne, faible;

  /// `sanctions[niveau]` : « bonne » vaut toujours 0.
  int sanction(Object? niveau) => niveau == 'moyenne' ? moyenne : niveau == 'faible' ? faible : 0;
}

const rhbCriteres = <RhbCritere>[
  RhbCritere('01', 'ponctualite', 'Ponctualité et assiduité',
      ['Retard', 'Sortie non autorisée', 'Absence au poste', 'Assemblée de bavardage', 'Dormir aux heures de travail', 'Usage de portable'], 6, 10),
  RhbCritere('02', 'execution', 'Exécution des tâches', ['Tâches non exécutées', 'Tâches mal exécutées'], 10, 15),
  RhbCritere('03', 'attitude', 'Attitude envers les patients',
      ['Parler mal au malade', 'Dispute avec malade', 'Insulter ou critiquer le malade', 'Renvoi de malade'], 6, 10),
  RhbCritere('04', 'hierarchie', 'Respect de la hiérarchie', ['Manque de courtoisie', 'Indiscrétion', 'Manque d’intégrité'], 6, 10),
];

/// `D.NS131.prelevement(evaluation)` : total (% du brut) pour `{critereId: niveauId}`. Lit le barème d'ORIGINE de la note, jamais la collection
/// `baremeNS131` que l'écran du barème modifie (écart E650, porté fidèlement).
int rhbPrelevement(Map<String, Object?> criteres) =>
    rhbCriteres.fold<int>(0, (t, c) => t + c.sanction(criteres[c.id]));

/// `Math.round(salaire * pct / 100)`.
int rhbMontantPrelevement(Object? salaire, Object? pct) => arrondiJs(nombreOuZero(salaire) * nombreOuZero(pct) / 100).toInt();

// ---------------------------------------------------------------------------------------------------------------------
// NS 132 — grille des primes diverses, DATÉE (RG-11 : jamais changer une prime déjà calculée)
// ---------------------------------------------------------------------------------------------------------------------

const rhbNs132Reference = 'NS n° 132/07/DM/DA/CNT/2026';
const rhbNs132Objet = 'Primes diverses';
const rhbNs132DateEffet = '2026-07-13';
const rhbNs132DateSignature = '2026-07-13';
const rhbNs132Version = 1;
const rhbNs132Statut = 'ACTIVE';
const rhbNs132Signataire = 'BASSONGUI Chabi Séko, Directeur Médical';
const rhbNs132RecuPar = 'KASSA A. B. Augustin — reçu le 13/07/2026';

class RhbPrimeOrigine {
  const RhbPrimeOrigine(this.id, this.label, this.mode, this.montants);
  final String id, label, mode;
  final Map<String, int> montants;
}

/// Le barème d'ORIGINE de la note (`NS132.primes`) : repli du moteur, indépendant du magasin.
const rhbPrimesOrigine = <RhbPrimeOrigine>[
  RhbPrimeOrigine('permanence', 'Permanence', 'occurrence', {'aide_soignant': 600, 'caissiere': 600, 'accueil': 700, 'infirmier': 800, 'sage_femme': 800, 'tsl': 800}),
  RhbPrimeOrigine('garde', 'Garde', 'occurrence', {'aide_soignant': 900, 'caissiere': 900, 'accueil': 900, 'infirmier': 1500, 'sage_femme': 1500, 'tsl': 1500}),
  RhbPrimeOrigine('aide_bloc', 'Aide bloc', 'occurrence', {'aide_soignant': 500, 'caissiere': 500, 'accueil': 500, 'infirmier': 500, 'sage_femme': 500}),
  RhbPrimeOrigine('bloc_fixe', 'Prime de bloc fixe', 'fixe', {'aide_soignant': 10000, 'infirmier': 10000}),
  RhbPrimeOrigine('hydrotubation', 'Hydrotubation', 'occurrence', {'infirmier': 1300}),
  RhbPrimeOrigine('accouchement', 'Accouchement', 'occurrence', {'sage_femme': 1000}),
  RhbPrimeOrigine('caisse', 'Caisse', 'fixe', {'caissiere': 10000}),
  RhbPrimeOrigine('urgence', 'Urgence', 'occurrence', {'tsl': 2500}),
  RhbPrimeOrigine('incineration', 'Incinération', 'fixe', {'aide_soignant': 5000}),
  RhbPrimeOrigine('accueil', 'Accueil', 'fixe', {'accueil': 7000}),
  RhbPrimeOrigine('circoncision', 'Circoncision', 'occurrence', {'sage_femme': 1000}),
];

/// Les six colonnes de la grille imprimée (fonctions éligibles aux primes).
const rhbColonnesPrimes = ['aide_soignant', 'caissiere', 'accueil', 'infirmier', 'sage_femme', 'tsl'];

num _montantDe(Object? montants, String fonction) {
  final v = (montants as Map?)?[fonction];
  return v is num && v != 0 ? v : 0;
}

num rhbMontantOrigine(String primeId, String fonction) {
  for (final p in rhbPrimesOrigine) {
    if (p.id == primeId) return p.montants[fonction] ?? 0;
  }
  return 0;
}

/// `D.NS132.montant(primeId, fonction, date)` — [grille] et [historique] sont les fiches ACTIVES des collections `grillePrimes` et `historiquePrimes`.
///
/// Sans date, ou si la version courante était déjà en vigueur : la grille du jour. Sinon on remonte l'historique jusqu'à la version en vigueur ce
/// jour-là ; faute d'en trouver, le barème d'origine. UNE PRIME RETIRÉE (archivée) n'est plus au magasin : le moteur retombe sur le barème
/// d'origine et la calcule encore (écart E651, porté fidèlement).
num rhbMontantPrime(List<FicheRhb> grille, List<FicheRhb> historique, String primeId, String fonction, [String? date]) {
  FicheRhb? courant;
  for (final x in grille) {
    if (x['primeId'] == primeId) {
      courant = x;
      break;
    }
  }
  if (courant == null) return rhbMontantOrigine(primeId, fonction);
  final effet = courant['dateEffet'];
  if (date == null || date.isEmpty || effet == null || effet == '' || date.compareTo('$effet') >= 0) {
    return _montantDe(courant['montants'], fonction);
  }
  final versions = [
    for (final v in historique)
      if (v['primeId'] == primeId &&
          (v['dateEffet'] == null || v['dateEffet'] == '' || date.compareTo('${v['dateEffet']}') >= 0) &&
          (v['dateFin'] == null || v['dateFin'] == '' || date.compareTo('${v['dateFin']}') <= 0))
        v
  ];
  final tri = trierPar(versions, (v) => '${v['dateEffet']}', descendant: true);
  if (tri.isNotEmpty) return _montantDe(tri.first['montants'], fonction);
  return rhbMontantOrigine(primeId, fonction);
}

// ---------------------------------------------------------------------------------------------------------------------
// Planning : comptages, incompatibilité, portée
// ---------------------------------------------------------------------------------------------------------------------

/// `compter(employeId, annee, mois, type)` — [mois] de 1 à 12.
int rhbCompter(List<FicheRhb> planning, Object? employeId, int annee, int mois, String type) {
  var n = 0;
  for (final p in planning) {
    if (p['employeId'] != employeId || p['type'] != type) continue;
    final d = '${p['date']}';
    if (d.length >= 7 && int.tryParse(d.substring(0, 4)) == annee && int.tryParse(d.substring(5, 7)) == mois) n++;
  }
  return n;
}

/// Le jour [n] jours avant [jour] (ISO), en jours calendaires.
String rhbJourAvant(DateTime jour, int n) => iso(ajouterJours(jour, -n));

/// Le contrôle d'incompatibilité de l'affectation (`affecter`) : une garde de 24 h interdit d'en programmer une autre pendant le repos qui la
/// suit (24 h, ou 48 h pour un régime à `repos48`). Renvoie le JOUR de la garde en cause (ISO), ou `null` si l'affectation est possible.
String? rhbIncompatibiliteGarde(List<FicheRhb> planningActif,
    {required Object? employeId, required DateTime jour, required String type, required String? repos}) {
  if (type != 'garde' && type != 'garde_hospi') return null;
  final joursRepos = repos == 'repos48' ? 2 : 1;
  for (var k = 1; k <= joursRepos; k++) {
    final veille = rhbJourAvant(jour, k);
    final trouvee = planningActif.any((p) => p['employeId'] == employeId && p['date'] == veille && (p['type'] == 'garde' || p['type'] == 'garde_hospi'));
    if (trouvee) return veille;
  }
  return null;
}

/// Les vacations proposées à l'affectation : celles du régime de la catégorie, plus le repos et les quatre absences (aucun poste étranger à la fonction).
List<String> rhbVacationsAutorisees(RhbRegimeVu? regime) => regime == null
    ? [for (final t in rhbTypesPlanning) t.id]
    : [...regime.vacations, ...[regime.repos, 'conge', 'absence', 'remplacement'].whereType<String>().where((s) => s.isNotEmpty)];

/// Les vacations qu'une modification de régime touche : adossées à l'une de ses fonctions, déjà effectuées (avant [aujourdhui]) ou à venir.
({List<FicheRhb> concernees, List<FicheRhb> passees, List<FicheRhb> futures}) rhbVacationsDuRegime(
    List<FicheRhb> planningActif, List<String> fonctions, String aujourdhui) {
  final c = [for (final v in planningActif) if (fonctions.contains(v['fonction'])) v];
  return (
    concernees: c,
    passees: [for (final v in c) if ('${v['date']}'.compareTo(aujourdhui) < 0) v],
    futures: [for (final v in c) if ('${v['date']}'.compareTo(aujourdhui) >= 0) v],
  );
}

// ---------------------------------------------------------------------------------------------------------------------
// Statistiques de garde
// ---------------------------------------------------------------------------------------------------------------------

class RhbPeriodeGarde {
  const RhbPeriodeGarde(this.id, this.label, this.jours);
  final String id, label;
  final int? jours;
}

const rhbPeriodesGarde = <RhbPeriodeGarde>[
  RhbPeriodeGarde('semaine', 'Semaine', 7),
  RhbPeriodeGarde('mois', 'Mois', 30),
  RhbPeriodeGarde('trimestre', 'Trimestre', 91),
  RhbPeriodeGarde('semestre', 'Semestre', 182),
  RhbPeriodeGarde('annee', 'Année', 365),
  RhbPeriodeGarde('libre', 'Plage libre', null),
];

/// Les types de vacation qui comptent comme du travail effectué : repos et congés en sont EXCLUS (les compter ferait des agents les plus reposés
/// les plus chargés).
const rhbVacationsTravaillees = [
  'garde', 'garde_hospi', 'garde_soins', 'permanence', 'soiree', 'entretien_general', 'incineration', 'remplacement',
];

/// La plage posée par une périodicité (`appliquerPeriode`) : `(du, au)` en ISO, ou `null` pour la plage libre.
(String, String)? rhbPlageDePeriode(String periode, DateTime aujourdhui) {
  for (final p in rhbPeriodesGarde) {
    if (p.id == periode && p.jours != null) return (iso(ajouterJours(aujourdhui, -p.jours! + 1)), iso(aujourdhui));
  }
  return null;
}

/// `lignes()` de `m10-stats-gardes` : les vacations travaillées dans la plage et selon les cinq filtres (« » = pas de filtre).
List<FicheRhb> rhbLignesGardes(List<FicheRhb> planningActif,
    {String du = '', String au = '', String agent = '', String service = '', String type = '', String fonction = ''}) {
  return [
    for (final v in planningActif)
      if (rhbVacationsTravaillees.contains(v['type']) &&
          !(du.isNotEmpty && '${v['date']}'.compareTo(du) < 0) &&
          !(au.isNotEmpty && '${v['date']}'.compareTo(au) > 0) &&
          !(agent.isNotEmpty && v['employeId'] != agent) &&
          !(service.isNotEmpty && v['service'] != service) &&
          !(type.isNotEmpty && v['type'] != type) &&
          !(fonction.isNotEmpty && v['fonction'] != fonction))
        v
  ];
}

class RhbStatAgent {
  const RhbStatAgent(this.employeId, this.agent, this.fonction, this.fonctionLabel, this.service, this.total, this.gardes, this.permanences,
      this.soirees, this.autres, this.heures);
  final String employeId, agent, fonctionLabel, service;
  final String? fonction;
  final int total, gardes, permanences, soirees, autres;
  final double heures;
}

/// `parAgent(rows)` : le détail par agent, le plus chargé d'abord (tri STABLE : à égalité, l'ordre du planning).
List<RhbStatAgent> rhbParAgentGardes(List<FicheRhb> rows) {
  final g = <String, List<FicheRhb>>{};
  for (final r in rows) {
    (g['${r['employeId']}'] ??= []).add(r);
  }
  final out = <RhbStatAgent>[];
  for (final e in g.entries) {
    final v = e.value;
    final gardes = v.where((x) => '${x['type']}'.startsWith('garde')).length;
    final heures = v.fold<double>(0, (s, x) => s + (rhbTypePlanning(x['type'])?.duree ?? 0));
    final perm = v.where((x) => x['type'] == 'permanence').length;
    final soir = v.where((x) => x['type'] == 'soiree').length;
    final svc = v.first['service'];
    out.add(RhbStatAgent(
        e.key,
        '${v.first['employe']}',
        v.first['fonction'] as String?,
        rhbFonctionLabel(v.first['fonction']),
        svc == null || svc == '' ? '—' : '$svc',
        v.length,
        gardes,
        perm,
        soir,
        v.length - gardes - perm - soir,
        arrondiJs(heures * 10) / 10));
  }
  return trierPar(out, (a) => a.total, descendant: true);
}

/// `String(Math.round(x * 10) / 10)` : le nombre tel que JavaScript l'écrit (point décimal, pas de « .0 »).
String rhbDecimalJs(double x) {
  final v = arrondiJs(x * 10) / 10;
  return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}

/// Les jours que couvre la plage (`sur N jour(s)`) : 0 si une borne manque ; au moins 1 sinon.
int rhbJoursPlage(String du, String au) {
  if (du.isEmpty || au.isEmpty) return 0;
  final a = DateTime.tryParse(du), b = DateTime.tryParse(au);
  if (a == null || b == null) return 0;
  final n = arrondiJs((b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) / 86400000).toInt() + 1;
  return n < 1 ? 1 : n;
}

/// `libellePeriode()` de `m10-stats-gardes`.
String rhbLibellePlageGardes(String du, String au) {
  if (du.isEmpty || au.isEmpty) return 'toutes périodes';
  return 'du ${_dateIso(du)} au ${_dateIso(au)}';
}

String _dateIso(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? 'NaN/NaN/NaN' : dateFR(d);
}

/// Les groupes d'un tableau de lignes selon une clé, dans l'ordre de première apparition.
Map<String, List<FicheRhb>> rhbGrouper(Iterable<FicheRhb> rows, String Function(FicheRhb) cle) {
  final g = <String, List<FicheRhb>>{};
  for (final r in rows) {
    (g[cle(r)] ??= []).add(r);
  }
  return g;
}

// ---------------------------------------------------------------------------------------------------------------------
// Statistiques des permanences
// ---------------------------------------------------------------------------------------------------------------------

/// `estPermanence(v)` : la permanence (08h–18h) n'est PAS la garde de 24 h.
bool rhbEstPermanence(FicheRhb v) {
  final t = '${(v['type'] == null || v['type'] == '') ? (v['regimeLibelle'] ?? '') : v['type']}'.toLowerCase();
  return t.contains('permanence');
}

class RhbPermanenceAgent {
  RhbPermanenceAgent(this.id, this.agent, this.matricule, this.service, this.fonction);
  final String id, agent, matricule, service, fonction;
  int nombre = 0;
}

/// `parAgent()` de `m10-stats-permanences`. [service] vaut « — Tous les services — » (ou vide) pour ne rien filtrer.
List<RhbPermanenceAgent> rhbPermanencesParAgent(List<FicheRhb> planningActif, List<FicheRhb> personnelActif, Bornes b, String service) {
  FicheRhb? agentDe(Object? id) {
    for (final a in personnelActif) {
      if (a['id'] == id) return a;
    }
    return null;
  }

  final par = <String, RhbPermanenceAgent>{};
  for (final v in planningActif) {
    if (!dansBornesTexte(v['date'], b)) continue;
    if (!rhbEstPermanence(v)) continue;
    final a = agentDe(v['employeId'] ?? v['personnelId']);
    if (service.isNotEmpty && !service.contains('Tous')) {
      if (a == null || a['service'] != service) continue;
    }
    final cle = a != null ? '${a['id']}' : '${v['agent'] ?? 'inconnu'}';
    final x = par.putIfAbsent(
        cle,
        () => RhbPermanenceAgent(cle, a != null ? '${a['nomComplet']}' : '${v['agent'] ?? '—'}', a != null ? '${a['matricule']}' : '—',
            a != null ? '${a['service']}' : '—', a != null ? '${a['poste']}' : '—'));
    x.nombre++;
  }
  return trierPar(par.values.toList(), (x) => x.nombre, descendant: true);
}

// ---------------------------------------------------------------------------------------------------------------------
// Présences
// ---------------------------------------------------------------------------------------------------------------------

class RhbServicePresence {
  const RhbServicePresence(this.service, this.observes, this.presents, this.retards, this.absents, this.agents, this.taux, this.tauxRetard);
  final String service;
  final int observes, presents, retards, absents, agents;
  final double taux, tauxRetard;
}

/// Les pointages de la plage (`pointages()` de `m10-stats-presence`) : la date se lit sur ses dix premiers caractères.
List<FicheRhb> rhbPointagesDans(List<FicheRhb> presencesActives, String du, String au) => [
      for (final x in presencesActives)
        if (_dansPlageTexte('${x['date'] ?? ''}'.length > 10 ? '${x['date']}'.substring(0, 10) : '${x['date'] ?? ''}', du, au)) x
    ];

bool _dansPlageTexte(String d, String du, String au) => !(du.isNotEmpty && d.compareTo(du) < 0) && !(au.isNotEmpty && d.compareTo(au) > 0);

/// Les pointages du registre (`dansPlage()` de `m10-presences`) : la date se compare TELLE QUELLE.
List<FicheRhb> rhbPointagesRegistre(List<FicheRhb> presencesActives, String du, String au) => [
      for (final r in presencesActives)
        if (_dansPlageTexte('${r['date'] ?? ''}', du, au)) r
    ];

/// `parService()` : le taux se calcule sur les journées EFFECTIVEMENT renseignées ; le retard est une présence (l'agent est là).
List<RhbServicePresence> rhbPresenceParService(List<FicheRhb> pointages) {
  final par = rhbGrouper(pointages, (x) => '${x['service']}');
  final out = <RhbServicePresence>[];
  for (final e in par.entries) {
    final g = e.value;
    final presents = g.where((x) => x['etat'] == 'present').length;
    final retards = g.where((x) => x['etat'] == 'retard').length;
    final absents = g.where((x) => x['etat'] == 'absent').length;
    final obs = g.length;
    out.add(RhbServicePresence(
        e.key == '' ? 'Non renseigné' : e.key,
        obs,
        presents,
        retards,
        absents,
        g.map((x) => '${x['employeId']}').toSet().length,
        obs > 0 ? arrondiJs((presents + retards) / obs * 1000) / 10 : 0,
        obs > 0 ? arrondiJs(retards / obs * 1000) / 10 : 0));
  }
  return trierPar(out, (x) => x.taux, descendant: true);
}

// ---------------------------------------------------------------------------------------------------------------------
// Évaluations, fiche de solde
// ---------------------------------------------------------------------------------------------------------------------

/// `anciennete(e)` : années et mois pleins depuis l'embauche.
({int ans, int mois}) rhbAnciennete(Object? dateEmbauche, DateTime aujourdhui) {
  final d = DateTime.tryParse('$dateEmbauche');
  if (d == null) return (ans: 0, mois: 0);
  final mois = (joursEntre(d, aujourdhui) / 30.44).floor();
  return (ans: mois ~/ 12, mois: mois % 12);
}

/// Le solde d'une fiche d'évaluation : base + primes du mois = brut ; le prélèvement s'applique au brut AINSI RECOMPOSÉ. La prime d'ancienneté
/// (2 % du salaire par année, à partir de deux ans) figure sur la fiche imprimée mais n'entre PAS dans le brut (écart E652, porté fidèlement).
class RhbSolde {
  const RhbSolde(this.primeGarde, this.primePermanence, this.primeAccueil, this.primeAnciennete, this.brut, this.prelevement);
  final num primeGarde, primePermanence, primeAccueil;
  final int primeAnciennete;
  final num brut;
  final int prelevement;
}

RhbSolde rhbSolde(
    {required Object? salaireBrut,
    required Object? prelevementPct,
    required int gardes,
    required int permanences,
    required num montantGarde,
    required num montantPermanence,
    required num montantAccueil,
    required int ans}) {
  final pg = montantGarde * gardes;
  final pp = montantPermanence * permanences;
  final sb = nombreOuZero(salaireBrut);
  final brut = sb + pg + pp + montantAccueil;
  final anc = ans >= 2 ? arrondiJs(sb * 0.02 * ans).toInt() : 0;
  return RhbSolde(pg, pp, montantAccueil, anc, brut, arrondiJs(brut * nombreOuZero(prelevementPct) / 100).toInt());
}

// ---------------------------------------------------------------------------------------------------------------------
// Primes acquises du mois
// ---------------------------------------------------------------------------------------------------------------------

class RhbPrimeAcquise {
  const RhbPrimeAcquise(this.id, this.matricule, this.employe, this.fonction, this.service, this.gardes, this.permanences, this.primeGarde,
      this.primePermanence, this.primesFixes, this.total);
  final String id, matricule, employe, service;
  final String? fonction;
  final int gardes, permanences;
  final num primeGarde, primePermanence, primesFixes, total;
}

/// RG-11 : les primes du mois calculées depuis le planning et la grille en vigueur (sans date : la grille du jour, comme la maquette). Les primes
/// FIXES sont celles du barème d'origine (`D.NS132.primes`) lues au moteur : une prime créée à l'écran n'y figure pas (écart E651).
List<RhbPrimeAcquise> rhbPrimesAcquises(
    {required List<FicheRhb> personnelActif,
    required List<FicheRhb> planningActif,
    required List<FicheRhb> grille,
    required List<FicheRhb> historique,
    required int annee,
    required int mois}) {
  final out = <RhbPrimeAcquise>[];
  for (final e in personnelActif) {
    final f = '${e['fonction']}';
    final gardes = rhbCompter(planningActif, e['id'], annee, mois, 'garde');
    final perm = rhbCompter(planningActif, e['id'], annee, mois, 'permanence');
    final pg = rhbMontantPrime(grille, historique, 'garde', f) * gardes;
    final pp = rhbMontantPrime(grille, historique, 'permanence', f) * perm;
    final fixes = rhbPrimesOrigine.where((p) => p.mode == 'fixe').fold<num>(0, (s, p) => s + rhbMontantPrime(grille, historique, p.id, f));
    final total = pg + pp + fixes;
    if (total > 0) {
      out.add(RhbPrimeAcquise('${e['id']}', '${e['matricule']}', '${e['nomComplet']}', e['fonction'] as String?, '${e['service']}', gardes, perm, pg, pp, fixes, total));
    }
  }
  return out;
}

/// `x.toFixed(1)` : le nombre tel que JavaScript l'écrit (point décimal), contrairement à `C.num` qui met une virgule.
String rhbUneDecimale(double x) => toFixedJs(x, 1);

/// Le libellé d'une vacation à l'affectation : « Garde 24h (08:00 → 08:00) » ; sans horaire, le libellé seul.
String rhbLibelleVacation(RhbTypePlanning t) => t.debut != null ? '${t.label} (${t.debut} → ${t.fin})' : t.label;
