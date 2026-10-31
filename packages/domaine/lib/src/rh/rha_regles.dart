import '../administration/adm_notes_donnees.dart' show admFonctions, admPrimesNs132;
import '../format/format_fr.dart';
import '../format/js.dart' show arrondiJs;
import '../format/recherche.dart' show trierPar;
import '../referentiels/regles.dart' show joursEntre;

/// M10 — RH, premier lot (fiches de poste, tableau de bord, personnel, fiche employé, contrats, congés, ordres de mission, prestataires externes).
/// Tout est CALCULÉ depuis les fiches du magasin, jamais fourni ; chaque règle est rejouée sur les vecteurs de la maquette
/// (`packages/domaine/test/vecteurs/rh.json`, tirés des écrans RÉELS par `prototype_html/build/vecteurs-rh.js`).
/// Rien n'est inventé : barèmes, primes et grilles viennent des notes NS 131 / NS 132 (`adm_notes_donnees.dart`).

typedef RhaFiche = Map<String, Object?>;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Référentiels de la maquette (`D.SERVICES`, `D.TYPES_PLANNING`, listes des champs des écrans)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `D.SERVICES` (un seul intitulé « Direction » : l'ancien « Administration » coupait l'effectif en deux).
const List<String> rhaServices = [
  'Médecine générale',
  'Maternité',
  'Chirurgie',
  'Laboratoire',
  'Pharmacie',
  'Imagerie / Échographie',
  'Soins infirmiers',
  'Accueil',
  'Direction',
  'Comptabilité',
];

/// `D.TYPES_PLANNING` : (identifiant, libellé, ton du badge).
const List<(String, String, String)> rhaTypesPlanning = [
  ('garde', 'Garde 24h', 'danger'),
  ('garde_hospi', 'Garde hospitalisation', 'danger'),
  ('garde_soins', 'Garde soins', 'warning'),
  ('permanence', 'Permanence', 'info'),
  ('soiree', 'Soirée', 'navy'),
  ('entretien_general', 'Entretien général de la journée', 'info'),
  ('repos24', 'Repos 24h', 'neutral'),
  ('repos48', 'Repos 48h', 'neutral'),
  ('conge', 'Congé', 'success'),
  ('absence', 'Absence', 'warning'),
  ('remplacement', 'Remplacement', 'navy'),
  ('incineration', 'Incinération des déchets', 'warning'),
];

String rhaTypePlanningLabel(Object? id) {
  for (final t in rhaTypesPlanning) {
    if (t.$1 == id) return t.$2;
  }
  return '$id';
}

String rhaTypePlanningTon(Object? id) {
  for (final t in rhaTypesPlanning) {
    if (t.$1 == id) return t.$3;
  }
  return 'neutral';
}

/// `fonctionLabel(id)` : le libellé de `D.FONCTIONS`, ou l'identifiant lui-même s'il est inconnu.
String rhaFonctionLabel(Object? id) => admFonctions[id] ?? '$id';

const List<String> rhaSituations = ['Célibataire', 'Marié(e)', 'Divorcé(e)', 'Veuf(ve)'];
const List<String> rhaNaturesContrat = ['CDI', 'CDD', 'Stage', 'Prestation'];
const List<String> rhaPeriodesEssai = ['1 mois', '3 mois', '6 mois'];
const List<String> rhaNaturesConge = ['Congé annuel', 'Congé de maternité', 'Congé de maladie', 'Absence autorisée', 'Congé exceptionnel'];

/// Décisions d'un congé : identifiant → (libellé, ton).
const Map<String, (String, String)> rhaDecisionsConge = {
  'valide': ('Accordé', 'success'),
  'en_attente': ('En attente', 'warning'),
  'refuse': ('Refusé', 'danger'),
};

const List<String> rhaNaturesMission = ['Mission', 'Formation', 'Représentation', 'Convoyage'];
const List<String> rhaMoyensMission = ['Véhicule de service', 'Transport en commun', 'Ambulance', 'Moyen personnel'];

/// `STATUTS_MISSION` : (identifiant, libellé, ton).
const List<(String, String, String)> rhaStatutsMission = [
  ('projet', 'En projet', 'neutral'),
  ('a_valider', 'En attente de validation DA', 'warning'),
  ('validee', 'Validée', 'info'),
  ('en_cours', 'En cours', 'info'),
  ('terminee', 'Terminée', 'success'),
  ('reportee', 'Reportée', 'warning'),
  ('annulee', 'Annulée', 'danger'),
];

/// `statutMission(id)` : un identifiant inconnu retombe sur « En projet », comme la maquette.
(String, String, String) rhaStatutMission(Object? id) {
  for (final s in rhaStatutsMission) {
    if (s.$1 == id) return s;
  }
  return rhaStatutsMission.first;
}

const List<String> rhaSpecialitesPrestataire = [
  'Circoncision',
  'Hydrotubation',
  'Accouchement',
  'Analyses spécialisées',
  'Chirurgie',
  'Échographie',
  'Anesthésie',
];

const List<String> rhaTypesCouverture = [
  'CNSS — régime général',
  'Mutuelle de santé',
  'Assurance accident du travail',
  'Assurance maladie complémentaire',
  'Assurance vie',
  'Prise en charge clinique (personnel)',
];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Dates et nombres « à la JavaScript »
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `C.toDate` : une date seule (« AAAA-MM-JJ ») est lue à MINUIT UTC comme `new Date('2018-06-27')` ; une date-heure sans fuseau est locale.
DateTime? rhaDate(Object? v) {
  if (v is DateTime) return v;
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m != null) return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return DateTime.tryParse(s);
}

/// `C.dateFR` d'une valeur de fiche (vide si absente).
String rhaDateFR(Object? v) {
  final d = rhaDate(v);
  if (d == null) return '';
  // Une date seule est lue en UTC : on en affiche les composantes UTC (la même date que `C.dateFR` en UTC+0, et celle de la fiche ailleurs).
  final s = '${v ?? ''}'.trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
  return dateFR(d);
}

/// `C.daysBetween(a, b)` : `Math.round((b − a) / 86 400 000)`.
int rhaJoursEntre(Object? a, Object? b) {
  final x = rhaDate(a), y = rhaDate(b);
  if (x == null || y == null) return 0;
  return joursEntre(x, y);
}

num rhaNum(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}'.trim()) ?? 0);

/// Un nombre JavaScript concaténé à une chaîne : « 5 » et non « 5.0 ».
String rhaNombreJs(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';

num rhaSomme(Iterable<RhaFiche> rows, String champ) => rows.fold<num>(0, (a, r) => a + rhaNum(r[champ]));

bool rhaVrai(Object? v) => v != null && v != false && v != 0 && v != '';

String rhaMois2(int n) => n.toString().padLeft(2, '0');

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Indicateurs
// ---------------------------------------------------------------------------------------------------------------------------------------------

class RhaKpi {
  const RhaKpi(this.libelle, this.valeur, {this.indice, this.ton = 'neutral'});
  final String libelle;
  final String valeur;
  final String? indice;
  final String ton;
}

/// `anciennete(e)` : mois = ⌊jours / 30,44⌋ depuis la date d'embauche.
({int ans, int mois}) rhaAnciennete(Object? dateEmbauche, DateTime auj) {
  final mois = (rhaJoursEntre(dateEmbauche, auj) / 30.44).floor();
  return (ans: (mois / 12).floor(), mois: mois % 12);
}

/// `anciennete moyenne` du tableau de bord : arrondie à la décimale (`Math.round(x * 10) / 10`), écrite comme un nombre JavaScript.
String rhaAncienneteMoyenne(List<RhaFiche> p, DateTime auj) {
  if (p.isEmpty) return '0 ans';
  final somme = p.fold<int>(0, (a, e) => a + rhaAnciennete(e['dateEmbauche'], auj).ans);
  return '${rhaNombreJs(arrondiJs(somme / p.length * 10) / 10)} ans';
}

String rhaSalaireMoyen(List<RhaFiche> p) => money(p.isEmpty ? 0 : rhaSomme(p, 'salaireBase') / p.length);

/// Indicateurs du tableau de bord RH (`m10-dashboard`).
List<RhaKpi> rhaKpisDashboard(List<RhaFiche> personnel, List<RhaFiche> planningDuJour, DateTime auj) {
  int de(bool Function(RhaFiche) t) => planningDuJour.where(t).length;
  return [
    RhaKpi('Effectif total', nombre(personnel.length), indice: 'Organigramme de la clinique', ton: 'navy'),
    RhaKpi('Masse salariale (base)', money(rhaSomme(personnel, 'salaireBase')), ton: 'info'),
    RhaKpi('Salaire moyen', rhaSalaireMoyen(personnel)),
    RhaKpi('Ancienneté moyenne', rhaAncienneteMoyenne(personnel, auj), ton: 'success'),
    RhaKpi('De garde aujourd’hui', nombre(de((x) => x['type'] == 'garde')), ton: 'danger'),
    RhaKpi('En permanence', nombre(de((x) => x['type'] == 'permanence')), ton: 'warning'),
    RhaKpi('En repos', nombre(de((x) => '${x['type']}'.startsWith('repos'))), ton: 'info'),
    RhaKpi('Agents à évaluer', nombre(personnel.length), indice: 'Barème NS 131', ton: 'navy'),
  ];
}

/// Les vacations d'un jour : `planning().filter(x => x.date === C.iso(AUJ))`.
List<RhaFiche> rhaPlanningDuJour(Iterable<RhaFiche> planning, DateTime auj) => [
      for (final x in planning)
        if (x['date'] == iso(auj)) x
    ];

/// `C.groupBy` : les groupes dans l'ORDRE DE PREMIÈRE APPARITION (les clés non numériques d'un objet JavaScript gardent leur ordre d'insertion).
Map<String, List<RhaFiche>> rhaGrouper(Iterable<RhaFiche> rows, String Function(RhaFiche) cle) {
  final g = <String, List<RhaFiche>>{};
  for (final r in rows) {
    g.putIfAbsent(cle(r), () => []).add(r);
  }
  return g;
}

/// « Effectif par fonction » : `K.ranking` trié par valeur décroissante (tri JavaScript stable : les ex æquo gardent l'ordre d'apparition).
List<({String libelle, int valeur})> rhaEffectifParFonction(List<RhaFiche> personnel) {
  final g = rhaGrouper(personnel, (e) => '${e['fonction']}');
  final l = [for (final e in g.entries) (libelle: rhaFonctionLabel(e.key), valeur: e.value.length)];
  return trierPar(l, (x) => x.valeur, descendant: true);
}

/// « Répartition par service » et « Masse salariale par service » : (service, effectif, masse de base).
List<({String service, int effectif, num masse})> rhaParService(List<RhaFiche> personnel) {
  final g = rhaGrouper(personnel, (e) => '${e['service']}');
  return [for (final e in g.entries) (service: e.key, effectif: e.value.length, masse: rhaSomme(e.value, 'salaireBase'))];
}

/// « Planning du jour » : (libellé du type, nombre) dans l'ordre d'apparition.
List<({String libelle, int nombre})> rhaRepartitionPlanning(List<RhaFiche> duJour) {
  final g = rhaGrouper(duJour, (x) => '${x['type']}');
  return [for (final e in g.entries) (libelle: rhaTypePlanningLabel(e.key), nombre: e.value.length)];
}

/// Indicateurs de `m10-personnel` (sur les fiches ACTIVES).
List<RhaKpi> rhaKpisPersonnel(List<RhaFiche> rows) => [
      RhaKpi('Effectif', nombre(rows.length), ton: 'navy'),
      RhaKpi('Masse salariale', money(rhaSomme(rows, 'salaireBase')), ton: 'info'),
      RhaKpi('Salaire moyen', rhaSalaireMoyen(rows)),
      RhaKpi('Femmes / Hommes', '${nombre(rows.where((e) => e['sexe'] == 'F').length)} / ${nombre(rows.where((e) => e['sexe'] == 'M').length)}', ton: 'success'),
    ];

/// `transform` de `m10-personnel` : le nom complet suit « NOM Prénom ».
RhaFiche rhaAgentEnregistrable(RhaFiche v) {
  v['nomComplet'] = '${v['nom']} ${v['prenom']}';
  return v;
}

/// Le portrait de l'agent : les deux premières initiales (`C.initials`).
String rhaInitiales(Object? s) => '$s'
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((w) => w.isEmpty ? '' : String.fromCharCode(w.runes.first))
    .join()
    .toUpperCase();

/// « Ancienneté » en table : « 8 a. 4 m. », en fiche : « 8 an(s) 4 mois ».
String rhaAncienneteCourte(Object? embauche, DateTime auj) {
  final a = rhaAnciennete(embauche, auj);
  return '${a.ans} a. ${a.mois} m.';
}

String rhaAncienneteLongue(Object? embauche, DateTime auj) {
  final a = rhaAnciennete(embauche, auj);
  return '${a.ans} an(s) ${a.mois} mois';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Fiche employé : planning du mois, primes NS 132, évaluations
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `vacations(employeId, annee, mois)` : le planning de l'agent sur un mois civil, trié par date (`mois` de 1 à 12, la date lue comme `new Date(p.date)`).
List<RhaFiche> rhaVacations(Iterable<RhaFiche> planning, Object? employeId, int annee, int mois) {
  final l = [
    for (final p in planning)
      if (p['employeId'] == employeId && _dansMois(p['date'], annee, mois)) p
  ];
  return l;
}

bool _dansMois(Object? date, int annee, int mois) {
  final d = rhaDate(date);
  if (d == null) return false;
  return d.year == annee && d.month == mois;
}

int rhaCompter(List<RhaFiche> vacations, String type) => vacations.where((p) => p['type'] == type).length;

/// Montant d'une prime pour une fonction : la ligne COURANTE de la grille datée (`grillePrimes`) ; à défaut, le barème d'origine de la NS 132.
/// Pas de date : la grille du jour s'applique (la fiche employé n'en passe pas).
num rhaMontantPrime(Iterable<RhaFiche> grille, String primeId, Object? fonctionId) {
  for (final g in grille) {
    if (g['primeId'] == primeId) {
      final montants = g['montants'];
      return montants is Map ? rhaNum(montants[fonctionId]) : 0;
    }
  }
  for (final p in admPrimesNs132) {
    if (p.id == primeId) return p.montants['$fonctionId'] ?? 0;
  }
  return 0;
}

class RhaLignePrime {
  const RhaLignePrime(this.prime, this.mode, this.montant, this.nb, this.total);
  final String prime;
  final String mode;
  final num montant;
  final int nb;
  final num total;
}

/// L'onglet « Primes (NS 132) » : une ligne par prime prévue pour la fonction ; forfait mensuel × 1, garde et permanence × leur nombre du mois, les
/// autres × 0 (elles se comptent à l'acte, au bulletin).
List<RhaLignePrime> rhaPrimesAgent(Iterable<RhaFiche> grille, Object? fonction, int gardes, int permanences) {
  final l = <RhaLignePrime>[];
  for (final p in admPrimesNs132) {
    final montant = rhaMontantPrime(grille, p.id, fonction);
    if (montant == 0) continue;
    final nb = p.mode == 'fixe' ? 1 : (p.id == 'garde' ? gardes : (p.id == 'permanence' ? permanences : 0));
    l.add(RhaLignePrime(p.libelle, p.mode == 'fixe' ? 'Forfait mensuel' : 'Par occurrence', montant, nb, montant * nb));
  }
  return l;
}

/// Libellé des décisions de l'onglet « Présences & congés » : `U.statut(code)` (code inconnu : le code lui-même).
const Map<String, (String, String)> rhaStatutsBadge = {
  'actif': ('Actif', 'success'),
  'archive': ('Archivé', 'neutral'),
  'valide': ('Validé', 'success'),
  'validee': ('Validée', 'success'),
  'en_attente': ('En attente', 'warning'),
  'rejete': ('Rejeté', 'danger'),
  'brouillon': ('Brouillon', 'neutral'),
  'en_cours': ('En cours', 'info'),
  'terminee': ('Terminée', 'success'),
};

(String, String) rhaStatutBadge(Object? code) {
  final s = rhaStatutsBadge['$code'];
  if (s != null) return s;
  final t = '${code ?? ''}'.isEmpty ? '—' : '$code';
  return (t, 'neutral');
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Contrats
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Jours restants avant l'échéance d'un contrat (`C.daysBetween(AUJ, c.dateFin)`).
int rhaJoursAvantEcheance(Object? dateFin, DateTime auj) => rhaJoursEntre(auj, dateFin);

/// Cellule « Échéance » d'un contrat : (texte, ton). Indéterminée sans date de fin ; « Échu » une fois dépassée ; « Dans N j » jusqu'à 90 jours.
({String texte, String? ton}) rhaEcheanceContrat(RhaFiche c, DateTime auj) {
  if (!rhaVrai(c['dateFin'])) return (texte: 'Indéterminée', ton: null);
  final j = rhaJoursAvantEcheance(c['dateFin'], auj);
  if (j < 0) return (texte: 'Échu', ton: 'danger');
  if (j <= 90) return (texte: 'Dans $j j', ton: 'warning');
  return (texte: rhaDateFR(c['dateFin']), ton: null);
}

/// Indicateurs de `m10-contrats`.
List<RhaKpi> rhaKpisContrats(List<RhaFiche> rows, DateTime auj) {
  final echeance = rows.where((c) {
    if (!rhaVrai(c['dateFin'])) return false;
    final j = rhaJoursAvantEcheance(c['dateFin'], auj);
    return j >= 0 && j <= 90;
  });
  return [
    RhaKpi('Contrats en vigueur', nombre(rows.length), ton: 'navy'),
    RhaKpi('CDI', nombre(rows.where((c) => c['nature'] == 'CDI').length), ton: 'success'),
    RhaKpi('CDD', nombre(rows.where((c) => c['nature'] == 'CDD').length), ton: 'warning'),
    RhaKpi('Échéances sous 90 jours', nombre(echeance.length), ton: echeance.isNotEmpty ? 'danger' : 'neutral'),
  ];
}

/// `transform` des contrats : l'agent désigné donne nom, matricule, poste et fonction ; la RÉFÉRENCE est celle de la fiche corrigée, sinon la
/// suivante de la série lue sur les contrats existants (archivés compris) — jamais un compteur de page (E620).
RhaFiche rhaContratEnregistrable(RhaFiche v, RhaFiche? agent, {required String reference}) {
  if (agent != null) {
    v['employe'] = agent['nomComplet'];
    v['matricule'] = agent['matricule'];
    v['poste'] = agent['poste'];
    v['fonction'] = agent['fonction'];
  }
  v['reference'] = reference;
  v['statutContrat'] = 'en_vigueur';
  return v;
}

/// Le texte des six articles du contrat imprimé.
List<(String, String)> rhaArticlesContrat(RhaFiche c) => [
      ('Article 1 — Objet', 'Engagement au poste de ${c['poste']}.'),
      (
        'Article 2 — Nature',
        'Contrat à durée ${c['nature'] == 'CDI' ? 'indéterminée' : 'déterminée'}${rhaVrai(c['dateFin']) ? ', prenant fin le ${rhaDateFR(c['dateFin'])}' : ''}.'
      ),
      ('Article 3 — Prise d’effet', 'Le présent contrat prend effet le ${rhaDateFR(c['dateDebut'])}.'),
      ('Article 4 — Période d’essai', '${rhaVrai(c['essai']) ? c['essai'] : '3 mois'}, renouvelable une fois.'),
      (
        'Article 5 — Rémunération',
        'Salaire mensuel de base de ${money(c['salaire'])}, auquel s’ajoutent les primes prévues par la note de service en vigueur (NS 132).'
      ),
      ('Article 6 — Obligations', 'L’Employé(e) est soumis(e) au règlement intérieur et au barème d’évaluation en vigueur (NS 131).'),
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Congés
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `Math.max(1, C.daysBetween(début, fin))`.
int rhaDureeConge(Object? debut, Object? fin) {
  final j = rhaJoursEntre(debut, fin);
  return j < 1 ? 1 : j;
}

/// `beforeSave` : motif du refus, ou `null`.
String? rhaRefuserConge(Object? debut, Object? fin) {
  final d = rhaDate(debut), f = rhaDate(fin);
  if (d != null && f != null && f.isBefore(d)) return 'La date de fin doit être postérieure à la date de début.';
  return null;
}

RhaFiche rhaCongeEnregistrable(RhaFiche v, RhaFiche? agent, {required String reference}) {
  if (agent != null) {
    v['employe'] = agent['nomComplet'];
    v['matricule'] = agent['matricule'];
    v['service'] = agent['service'];
  }
  v['duree'] = rhaDureeConge(v['dateDebut'], v['dateFin']);
  v['reference'] = reference;
  return v;
}

/// Un congé accordé est « en cours » quand le début est passé et que la fin n'est pas échue — la fin est lue à MINUIT et comparée à l'instant (un congé
/// qui se termine aujourd'hui n'est plus compté, comme à la maquette).
bool rhaCongeEnCours(RhaFiche c, DateTime auj) {
  if (c['statutConge'] != 'valide') return false;
  final d = rhaDate(c['dateDebut']), f = rhaDate(c['dateFin']);
  if (d == null || f == null) return false;
  return !d.isAfter(auj) && !f.isBefore(auj);
}

List<RhaKpi> rhaKpisConges(List<RhaFiche> rows, DateTime auj) {
  final accordes = rows.where((c) => c['statutConge'] == 'valide');
  return [
    RhaKpi('Demandes enregistrées', nombre(rows.length), ton: 'navy'),
    RhaKpi('En congé aujourd’hui', nombre(rows.where((c) => rhaCongeEnCours(c, auj)).length), ton: 'info'),
    RhaKpi('En attente de décision', nombre(rows.where((c) => c['statutConge'] == 'en_attente').length), ton: 'warning'),
    RhaKpi('Jours accordés', nombre(rhaSomme(accordes, 'duree')), ton: 'success'),
  ];
}

class RhaStatsConges {
  const RhaStatsConges(this.parService, this.parNature, this.parDecision, this.moisLibelles, this.moisJours);
  final List<(String, int)> parService;
  final List<(String, int)> parNature;

  /// Libellés « Accordés / En attente / Refusés » dans l'ordre d'apparition des décisions.
  final List<(String, int)> parDecision;
  final List<String> moisLibelles;

  /// Jours ACCORDÉS par mois de début, dans l'ordre chronologique.
  final List<num> moisJours;
}

/// La lecture graphique des congés (sur les fiches actives) : par service, par nature, par décision, jours accordés par mois (au moins DEUX mois, sinon la
/// courbe est omise : `moisLibelles` vide).
RhaStatsConges rhaStatsConges(List<RhaFiche> rows) {
  List<(String, int)> compter(String Function(RhaFiche) cle) => [for (final e in rhaGrouper(rows, cle).entries) (e.key, e.value.length)];
  const decisions = {'valide': 'Accordés', 'en_attente': 'En attente', 'refuse': 'Refusés'};
  final parMois = rhaGrouper(rows, (c) => '${c['dateDebut']}'.padRight(7).substring(0, 7).trimRight());
  final mois = parMois.keys.toList()..sort();
  return RhaStatsConges(
    compter((c) => rhaVrai(c['service']) ? '${c['service']}' : 'Non renseigné'),
    compter((c) => '${c['nature']}'),
    [for (final e in rhaGrouper(rows, (c) => '${c['statutConge']}').entries) (decisions[e.key] ?? e.key, e.value.length)],
    mois.length > 1 ? [for (final m in mois) moisAnnee(rhaDate('$m-01')!)] : const [],
    mois.length > 1 ? [for (final m in mois) rhaSomme(parMois[m]!.where((c) => c['statutConge'] == 'valide'), 'duree')] : const [],
  );
}

/// Le texte de la décision imprimée.
List<String> rhaTexteDecisionConge(RhaFiche c) {
  final nature = '${c['nature']}'.toLowerCase();
  final periode = 'du ${rhaDateFR(c['dateDebut'])} au ${rhaDateFR(c['dateFin'])}';
  final l = <String>['La Directrice Administrative de la CLINIQUE NASSIERA TOO SARL,'];
  if (c['statutConge'] == 'valide') {
    l.add('Accorde à ${c['employe']}, matricule ${c['matricule']}, un $nature de ${c['duree']} jour(s), $periode inclus.');
  } else if (c['statutConge'] == 'refuse') {
    l.add('Rejette la demande de $nature formulée par ${c['employe']} pour la période $periode.');
  } else {
    l.add('Accuse réception de la demande de $nature formulée par ${c['employe']}, en cours d’instruction.');
  }
  if (rhaVrai(c['remplacant'])) l.add('Pendant cette période, l’intéressé(e) est remplacé(e) par ${c['remplacant']}.');
  if (rhaVrai(c['motif'])) l.add('Motif : ${c['motif']}');
  return l;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Ordres de mission
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// La référence d'un ordre : `'OM-2026-' + pad(effectif TOTAL + 1, 4)` (archivés compris ; le millésime est celui de la maquette — écart E624).
String rhaReferenceMission(int effectifTotal) => 'OM-2026-${(effectifTotal + 1).toString().padLeft(4, '0')}';

List<RhaKpi> rhaKpisMissions(List<RhaFiche> rows) {
  final aValider = rows.where((m) => m['statutMission'] == 'a_valider').length;
  final enCours = rows.where((m) => m['statutMission'] == 'en_cours' || m['statutMission'] == 'validee').length;
  return [
    RhaKpi('Ordres de mission', nombre(rows.length), ton: 'navy'),
    RhaKpi('En attente de validation', nombre(aValider), indice: aValider > 0 ? 'Validation de la DA attendue' : 'Rien en attente', ton: aValider > 0 ? 'warning' : 'success'),
    RhaKpi('Missions en cours', nombre(enCours), ton: 'info'),
    RhaKpi('Terminées', nombre(rows.where((m) => m['statutMission'] == 'terminee').length), ton: 'success'),
  ];
}

/// `transform` de la création d'un ordre : l'agent désigné donne son nom et son poste ; la référence suit l'effectif.
RhaFiche rhaMissionEnregistrable(RhaFiche v, RhaFiche? agent, {required int effectifTotal}) {
  v['reference'] = rhaReferenceMission(effectifTotal);
  v['agent'] = agent != null ? agent['nomComplet'] : '—';
  v['fonction'] = agent != null ? (agent['poste'] ?? '') : '';
  return v;
}

/// Les trois gestes de la ligne d'un ordre, selon son état : (valider, terminer/reporter).
({bool valider, bool terminerReporter}) rhaGestesMission(Object? statut) =>
    (valider: statut == 'a_valider', terminerReporter: statut == 'validee' || statut == 'en_cours');

/// Ce que la validation écrit : état « Validée », la validatrice et la date (la maquette ne connaît que la Directrice Administrative).
RhaFiche rhaCorrectifValidationMission(DateTime auj) => {'statutMission': 'validee', 'valideePar': 'TAKI Alimatou', 'valideeLe': iso(auj)};

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Prestataires externes
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Montant dû = tarif par acte × actes réalisés (le mois en cours).
num rhaMontantDuPrestataire(RhaFiche p) => rhaNum(p['tarifActe']) * rhaNum(p['actesRealises']);

List<RhaKpi> rhaKpisPrestataires(List<RhaFiche> rows) => [
      RhaKpi('Prestataires référencés', nombre(rows.length), ton: 'navy'),
      RhaKpi('Actes du mois', nombre(rhaSomme(rows, 'actesRealises')), ton: 'info'),
      RhaKpi('Montant à régler', money(rows.fold<num>(0, (a, p) => a + rhaMontantDuPrestataire(p))), ton: 'warning'),
      RhaKpi('Sans facture normalisée', nombre(rows.where((p) => !rhaVrai(p['factureNormalisee'])).length), ton: 'danger'),
    ];

RhaFiche rhaPrestataireEnregistrable(RhaFiche v, {required String reference}) {
  v['reference'] = reference;
  return v;
}

class RhaStatsPrestataires {
  const RhaStatsPrestataires(this.specialites, this.montants, this.actes, this.facturesFournies, this.facturesManquantes, this.classement);
  final List<String> specialites;
  final List<num> montants;
  final List<num> actes;
  final int facturesFournies;
  final int facturesManquantes;

  /// Les huit mieux rémunérés : `sortBy(montant).reverse().slice(0, 8)` — le tri croissant STABLE puis inversé (les ex æquo sortent en ordre inverse).
  final List<({String libelle, num valeur, bool sansFacture})> classement;
}

RhaStatsPrestataires rhaStatsPrestataires(List<RhaFiche> rows) {
  final g = rhaGrouper(rows, (p) => '${p['specialite']}');
  final tri = trierPar(rows, rhaMontantDuPrestataire).reversed.take(8);
  return RhaStatsPrestataires(
    g.keys.toList(),
    [for (final e in g.entries) e.value.fold<num>(0, (a, p) => a + rhaMontantDuPrestataire(p))],
    [for (final e in g.entries) rhaSomme(e.value, 'actesRealises')],
    rows.where((x) => rhaVrai(x['factureNormalisee'])).length,
    rows.where((x) => !rhaVrai(x['factureNormalisee'])).length,
    [
      for (final x in tri) (libelle: '${x['nom']} — ${x['specialite']}', valeur: rhaMontantDuPrestataire(x), sansFacture: !rhaVrai(x['factureNormalisee']))
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Fiches de poste
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<RhaFiche> rhaMissionsDeFiche(RhaFiche f) => [
      for (final m in (f['missions'] as List? ?? const [])) (m as Map).cast<String, Object?>()
    ];

int rhaNbIndicateurs(RhaFiche f) => rhaMissionsDeFiche(f).fold<int>(0, (a, m) => a + ((m['indicateurs'] as List?)?.length ?? 0));

List<RhaKpi> rhaKpisFichesPoste(List<RhaFiche> rows) {
  final redigees = rows.where((r) => rhaVrai(r['redigee'])).length;
  return [
    RhaKpi('Postes recensés', nombre(rows.length), ton: 'navy'),
    RhaKpi('Fiches rédigées', nombre(redigees), indice: '${nombre(rows.length - redigees)} à rédiger', ton: redigees == rows.length ? 'success' : 'warning'),
    RhaKpi('Missions décrites', nombre(rows.fold<int>(0, (a, r) => a + rhaMissionsDeFiche(r).length)), ton: 'info'),
    RhaKpi('Indicateurs de performance', nombre(rows.fold<int>(0, (a, r) => a + rhaNbIndicateurs(r))), indice: 'ils rendent l’évaluation NS 131 mesurable', ton: 'success'),
  ];
}

/// `transform` d'une fiche créée à l'écran : sans mission, « rédigée », sa source dite. Les valeurs saisies l'emportent (dont le « statut du titulaire »).
RhaFiche rhaFicheDePosteEnregistrable(RhaFiche v) => {'missions': <Object?>[], 'redigee': true, 'source': 'Rédigée dans l’application', ...v};
