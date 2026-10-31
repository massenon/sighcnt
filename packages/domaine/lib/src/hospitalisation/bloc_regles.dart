/// BLOC, ANESTHÉSIE, CHECK-LISTES, DEMANDES DU SERVICE, PANSEMENTS ET SORTIES (M3) — règles et référentiels portés de `m3-hospitalisation.js`
/// (`m3-cpa`, `m3-bloc-cro`, `m3-cr-anesthesie`, `m3-bloc-checklist`, `m3-demande-examen`, `m3-bons-pansements`, `m3-sorties`,
/// `m3-sortie-avis-medical`) et de `D.CHECKLIST_BLOC`. Vecteurs : `test/vecteurs/bloc.json` (écrans réels pilotés dans Chrome, horloge 16/08/2026).
///
/// Doctrine : une CPA « avec réserves » EXIGE ses réserves nommées ; une intervention sans CPA est SIGNALÉE, jamais bloquée ; « aucun incident »
/// s'écrit ; une check-liste incomplète est signalée, jamais refusée ; les deux check-listes sont SÉPARÉES ; la sortie d'hospitalisation exige le
/// solde apuré (RG-06) et les trois signatures (RG-07) ; la sortie contre avis médical est motivée (RG-08).
library;

import '../caisse/mecef.dart' show tirage;
import '../format/js.dart';
import '../format/format_fr.dart' show iso;
import '../referentiels/regles.dart' show resultatRendu;
import '../stock/delivrance.dart' show referenceSuivante;
import 'hos_regles.dart';

typedef BlocFiche = Map<String, Object?>;

/// Un refus NOMMÉ : [message] s'affiche tel quel, [detail] en sous-titre du toast. Rien n'est écrit.
class BlocRefus {
  const BlocRefus(this.message, [this.detail]);
  final String message;
  final String? detail;
}

class BlocOption {
  const BlocOption(this.id, this.label);
  final String id;
  final String label;
}

bool _vrai(Object? v) => v != null && v != false && v != 0 && v != '';
String _s(Object? v) => '${v ?? ''}';

// --------------------------------------------------------------------------------------------- référentiels (lus sur les listes réelles)

/// Échelles ASA et Mallampati, techniques : proposées faute de document remis, ARRÊTÉES par les praticiens du bloc le 01/09/2026.
const blocAsa = [
  BlocOption('I', 'ASA I — patient sain'),
  BlocOption('II', 'ASA II — maladie systémique légère'),
  BlocOption('III', 'ASA III — maladie systémique sévère'),
  BlocOption('IV', 'ASA IV — menace vitale constante'),
  BlocOption('V', 'ASA V — moribond, survie improbable sans intervention'),
];
const blocMallampati = [
  BlocOption('I', 'Mallampati I — piliers, voile et luette visibles'),
  BlocOption('II', 'Mallampati II — luette partiellement masquée'),
  BlocOption('III', 'Mallampati III — seul le voile est visible'),
  BlocOption('IV', 'Mallampati IV — voile non visible'),
];
const blocTechniques = [
  'Anesthésie générale',
  'Rachianesthésie',
  'Péridurale',
  'Anesthésie locale',
  'Sédation',
];
const blocConclusionsCpa = [
  'Apte à l’anesthésie',
  'Apte avec réserves',
  'Intervention à reporter',
];
const blocDecisionsReveil = [
  'Retour dans le service',
  'Surveillance prolongée en salle de réveil',
  'Transfert / évacuation',
];

/// `D.CHECKLIST_BLOC` : DEUX listes séparées (avant l'incision / avant la sortie de salle), arrêtées par les praticiens du bloc le 01/09/2026.
const blocChecklistEntree = [
  'Identité du patient confirmée par le patient lui-même',
  'Intervention et site opératoire confirmés',
  'Consentement opératoire signé et présent au dossier',
  'Site opératoire marqué',
  'Jeûne préopératoire respecté',
  'Allergies connues vérifiées et signalées à l’équipe',
  'Voie veineuse posée et perméable',
  'Groupe sanguin et rhésus disponibles au dossier',
  'Matériel d’anesthésie vérifié et fonctionnel',
  'Risque hémorragique évalué',
  'Antibioprophylaxie administrée si indiquée',
  'Équipe au complet, chacun s’étant présenté par son nom et sa fonction',
];
const blocChecklistSortie = [
  'Nature de l’intervention réellement pratiquée énoncée à voix haute',
  'Comptage des compresses, aiguilles et instruments exact',
  'Étiquetage des prélèvements vérifié (nom du patient, nature)',
  'Incidents ou difficultés per-opératoires signalés et consignés',
  'Drains et sondes en place recensés',
  'Prescriptions post-opératoires rédigées',
  'Surveillance post-opératoire prescrite et transmise au service',
  'Compte rendu opératoire rédigé et signé',
  'Dysfonctionnement matériel éventuel signalé',
];
const blocChecklistArreteLe = '2026-09-01';

/// `L.SERVICES_DEMANDEURS` et `L.NIVEAUX_URGENCE` (fiche de demande d'examen du service).
const blocServicesDemandeurs = [
  BlocOption('maternite', 'Maternité'),
  BlocOption('medecine', 'Médecine'),
  BlocOption('specialite', 'Médecine et spécialité'),
];
const blocNiveauxUrgence = [
  BlocOption('aucune', 'Examen courant'),
  BlocOption('examen', 'Un examen urgent'),
  BlocOption('bilan', 'Bilan entier en urgence'),
];

/// Les deux actes de pansement du catalogue : SO09 (pansement) et CH04 (pansement chirurgical).
const blocCodesPansement = ['SO09', 'CH04'];

const blocEtatsSortie = [
  'Guéri',
  'Amélioré',
  'Stationnaire',
  'Transféré',
  'Sortie contre avis médical',
];

// --------------------------------------------------------------------------------------------- séries de références

/// `C.referenceSuivante` — le plus grand rang déjà écrit (archivées comprises) plus un ; jamais un compteur de page (écart E410).
String blocReferenceSuivante(String prefixe, int largeur, Iterable<BlocFiche> fiches) =>
    referenceSuivante(prefixe, largeur, fiches);

// --------------------------------------------------------------------------------------------- consultation pré-anesthésique

/// `controler` de `m3-cpa` : la réserve s'écrit — une aptitude conditionnelle sans condition nommée ne protège personne. Vaut à la création ET à
/// la modification.
BlocRefus? blocRefusCpa(Map<String, Object?> v) {
  if (v['conclusion'] != blocConclusionsCpa[0] && _s(v['observations']).trim().isEmpty) {
    return BlocRefus('Conclusion avec réserves : les nommer.',
        'Une CPA « ${v['conclusion']} » doit dire quelles réserves — c’est elles que le bloc doit lire.');
  }
  return null;
}

/// Indicateurs de `m3-cpa`. Les interventions sans CPA sont des COMPTES RENDUS OPÉRATOIRES (pas des patients) dont le patient n'a aucune CPA
/// active ; celles sans `patientId` ne comptent pas. SIGNALÉES, jamais bloquées — l'urgence n'attend pas.
({int cpa, int aptes, int reserves, int sansCpa}) blocKpisCpa(
    Iterable<BlocFiche> cpaActives, Iterable<BlocFiche> crosActifs) {
  final avec = {for (final r in cpaActives) r['patientId']};
  final sans = [
    for (final c in crosActifs)
      if (_vrai(c['patientId']) && !avec.contains(c['patientId'])) c
  ];
  final reserves = cpaActives.where((r) => r['conclusion'] != blocConclusionsCpa[0]).length;
  return (
    cpa: cpaActives.length,
    aptes: cpaActives.length - reserves,
    reserves: reserves,
    sansCpa: sans.length
  );
}

/// `amorcerAnesthesie()` : six CPA adossées aux six premières admissions, tirage `C.seeded(701)`. La maquette ne les sème qu'à l'ouverture de
/// l'écran quand la collection est vide ; le jeu du poste n'en porte pas (écart E417).
List<BlocFiche> blocAmorcerCpa(Iterable<BlocFiche> admissions) {
  final rnd = tirage(701);
  T pick<T>(List<T> a) => a[(rnd() * a.length).floor() % a.length];
  final out = <BlocFiche>[];
  var i = 0;
  for (final a in admissions.take(6)) {
    final conclu = i == 4 ? blocConclusionsCpa[1] : blocConclusionsCpa[0];
    final n = (i + 1).toString().padLeft(4, '0');
    out.add({
      'id': 'CPA$n',
      'statut': 'actif',
      'reference': 'CPA-2026-$n',
      'date': a['dateEntree'],
      'patientId': a['patientId'],
      'patient': a['patient'],
      'patientCode': a['patientCode'],
      'asa': pick(['I', 'I', 'II', 'II', 'III']),
      'mallampati': pick(['I', 'I', 'II', 'III']),
      'technique': pick(blocTechniques),
      'antecedentsAnesthesiques': pick(['Aucun', 'Aucun', 'Rachianesthésie en 2024, sans incident']),
      'allergies': pick(['Aucune connue', 'Aucune connue', 'Pénicilline']),
      'jeuneConsigne': true,
      'conclusion': conclu,
      'observations': conclu == blocConclusionsCpa[1] ? 'HTA à équilibrer avant l’intervention.' : '',
      'anesthesiste': 'Anesthésiste de la clinique',
    });
    i++;
  }
  return out;
}

// --------------------------------------------------------------------------------------------- compte rendu opératoire

/// Indicateurs de `m3-bloc-cro` : « Ce mois-ci » compare les sept premiers caractères de la date d'intervention au mois de [auj] ; l'aide-opérateur
/// n'est pas obligatoire.
({int total, int mois, int sansAide}) blocKpisCro(Iterable<BlocFiche> rows, DateTime auj) {
  final m = iso(auj).substring(0, 7);
  return (
    total: rows.length,
    mois: rows.where((r) => _s(r['dateOperation']).length >= 7 && _s(r['dateOperation']).substring(0, 7) == m).length,
    sansAide: rows.where((r) => !_vrai(r['aideOperateurId'])).length,
  );
}

/// `transform` de `m3-bloc-cro` : les NOMS portés par la fiche suivent les identifiants (opérateur, aide, anesthésiste, patient) — à la création
/// comme à la modification (écart E411 : la modification laissait l'ancien nom, sur une pièce de preuve).
BlocFiche blocConstruireCro(Map<String, Object?> v,
    {required BlocFiche? patient,
    required String Function(Object? id) nomSoignant,
    BlocFiche? existante,
    required Iterable<BlocFiche> toutes}) {
  return {
    ...v,
    if (existante == null) 'reference': blocReferenceSuivante('CRO-', 4, toutes),
    'patientId': patient?['id'],
    'patient': patient != null ? '${patient['nom']} ${patient['prenom']}' : v['patientCode'],
    'operateur': nomSoignant(v['operateurId']),
    'aideOperateur': _vrai(v['aideOperateurId']) ? nomSoignant(v['aideOperateurId']) : null,
    'anesthesiste': nomSoignant(v['anesthesisteId']),
  };
}

// --------------------------------------------------------------------------------------------- compte rendu d'anesthésie

/// « Aucun incident » s'écrit : un champ vide ne distingue pas l'absence d'incident de l'oubli. Un incident est NOMMÉ s'il est renseigné et ne
/// commence pas par « aucun » (`/^aucun/i`).
bool blocIncidentNomme(Object? incidents) =>
    _vrai(incidents) && !RegExp(r'^aucun', caseSensitive: false).hasMatch(_s(incidents).trim());

({int total, int incidents, int prolonges, int cro}) blocKpisCra(Iterable<BlocFiche> rows) => (
      total: rows.length,
      incidents: rows.where((r) => blocIncidentNomme(r['incidents'])).length,
      prolonges: rows.where((r) => r['decisionSortie'] == blocDecisionsReveil[1]).length,
      cro: rows.where((r) => _vrai(r['croReference'])).length,
    );

/// `transform` commun de la CPA et du compte rendu d'anesthésie : le patient (identifiant et nom) suit le code choisi — à la création comme à la
/// modification (E411). [prefixeReference] : `CPA-2026-` / `CRA-2026-` (création seule).
BlocFiche blocConstruirePatientCode(Map<String, Object?> v,
    {required BlocFiche? patient,
    String? prefixeReference,
    Iterable<BlocFiche> toutes = const []}) {
  return {
    ...v,
    if (prefixeReference != null) 'reference': blocReferenceSuivante(prefixeReference, 4, toutes),
    'patientId': patient?['id'],
    'patient': patient != null ? '${patient['nom']} ${patient['prenom']}' : v['patientCode'],
  };
}

// --------------------------------------------------------------------------------------------- check-listes

/// Points d'une check-liste : `{label, coche}`, et le nombre de cochés. Une check-liste incomplète est SIGNALÉE, jamais refusée — refuser
/// pousserait à tout cocher pour pouvoir avancer.
({List<BlocFiche> items, int coches, int total}) blocLignesChecklist(List<String> labels, Map<String, Object?> v) {
  final items = [
    for (final (i, l) in labels.indexed) {'label': l, 'coche': v['it$i'] == true}
  ];
  return (items: items, coches: items.where((x) => x['coche'] == true).length, total: items.length);
}

({int total, int entree, int sortie, int incompletes}) blocKpisChecklist(Iterable<BlocFiche> rows) => (
      total: rows.length,
      entree: rows.where((r) => r['moment'] == 'entree').length,
      sortie: rows.where((r) => r['moment'] == 'sortie').length,
      incompletes: rows.where((r) => nombreOuZero(r['coches']) < nombreOuZero(r['total'])).length,
    );

/// Le message de succès d'une check-liste : complète ou « N point(s) NON vérifié(s) ».
({String message, bool complete}) blocMessageChecklist(int coches, int total) => coches == total
    ? (message: 'Check-liste complète enregistrée.', complete: true)
    : (message: 'Check-liste enregistrée — ${total - coches} point(s) NON vérifié(s).', complete: false);

// --------------------------------------------------------------------------------------------- fiche de demande d'examen du service

/// « Un examen urgent » sans le nommer laisserait le laboratoire deviner.
BlocRefus? blocRefusDemandeExamen(Map<String, Object?> v) =>
    v['urgence'] == 'examen' && !_vrai(v['examenUrgent'])
        ? const BlocRefus('Nommer L’EXAMEN urgent.',
            '« Un examen urgent » sans le nommer laisserait le laboratoire deviner.')
        : null;

/// La valeur de la liste des prescripteurs qui désigne un prescripteur du DEHORS (`K.PRESCRIPTEUR_EXTERNE`).
const blocPrescripteurExterne = 'EXTERNE';

/// `K.nomPrescripteur(v, null, 'prescripteur')` : le nom à porter sur la pièce — jamais la valeur « EXTERNE » (écart E412 : la maquette l'enregistrait
/// telle quelle et perdait le nom saisi, alors que c'est lui qui permet de renvoyer le compte rendu).
String blocNomPrescripteur(Object? prescripteur, Object? externe) {
  if (prescripteur != blocPrescripteurExterne) return _s(prescripteur);
  final libre = _s(externe).trim();
  return libre.isNotEmpty ? '$libre (extérieur)' : 'Prescripteur extérieur';
}

/// `C.age(naissance)` en texte : « 56 ans » (jours écoulés / 365,25, arrondis à l'entier inférieur), « — » sans date de naissance.
String blocAgeTexte(Object? dateNaissance, DateTime auj) {
  if (!_vrai(dateNaissance)) return '—';
  final n = (hosJoursEntre(dateNaissance, auj) / 365.25).floor();
  return '${n < 0 ? 0 : n} ans';
}

/// Le secteur demandeur porté par la demande : seule la maternité en a un (RBAC métier — la sage-femme lit les résultats de son secteur).
String? blocSecteurDemandeur(Object? serviceDemandeur) =>
    serviceDemandeur == 'maternite' ? 'MATERNITÉ' : null;

({int fiches, int attente, int urgentes, int rendus}) blocKpisDemandes(Iterable<BlocFiche> rows) => (
      fiches: rows.length,
      attente: rows.where((r) => r['etatAnalyse'] == 'en_attente').length,
      urgentes: rows.where((r) => _vrai(r['urgent'])).length,
      rendus: rows.where((r) => resultatRendu(r['etatAnalyse'] as String?)).length,
    );

/// Les fiches du SERVICE : une VUE du registre des demandes (`origine === 'service'`), jamais une seconde collection.
List<BlocFiche> blocDemandesService(Iterable<BlocFiche> actives) =>
    [for (final r in actives) if (r['origine'] == 'service') r];

// --------------------------------------------------------------------------------------------- bons de pansement

/// `bons()` : une ordonnance dont TOUS les actes sont des pansements, sans médicament ni analyse.
List<BlocFiche> blocBonsPansement(Iterable<BlocFiche> ordonnances) => [
      for (final o in ordonnances)
        if (((o['actes'] as List?) ?? const []).isNotEmpty &&
            ((o['actes'] as List).every((a) => blocCodesPansement.contains((a as Map)['code']))) &&
            ((o['medicaments'] as List?) ?? const []).isEmpty &&
            ((o['analyses'] as List?) ?? const []).isEmpty)
          o
    ];

/// `seancesDe(o)` : UNE ligne payable PAR SÉANCE — la caisse encaisse des séances nommées. [reglees] : lignes de pansement à `statutPaiement: 'paye'`.
({BlocFiche? facture, int total, int reglees}) blocSeancesDe(BlocFiche o, Iterable<BlocFiche> facturesActives) {
  final fac = facturesActives.where((f) => f['id'] == o['factureId']).firstOrNull;
  final lignes = fac == null
      ? <BlocFiche>[]
      : [
          for (final l in (fac['lignes'] as List? ?? const []))
            if (blocCodesPansement.contains((l as Map)['acteCode'])) l.cast<String, Object?>()
        ];
  return (facture: fac, total: lignes.length, reglees: lignes.where((l) => l['statutPaiement'] == 'paye').length);
}

/// « Séances en attente de règlement » (C4, corrigé dans la maquette le 31/10/2026 puis porté, écart E413) : l'indicateur compte les SÉANCES
/// (lignes payables restantes), non les bons dont des séances restent dues : un bon de 5 séances dont 2 sont réglées pèse 3, pas 1.
({int bons, int attente}) blocKpisPansements(Iterable<BlocFiche> bons, Iterable<BlocFiche> facturesActives) => (
      bons: bons.length,
      attente: bons.fold<int>(0, (n, o) {
        final s = blocSeancesDe(o, facturesActives);
        return n + (s.total > 0 ? s.total - s.reglees : 0);
      }),
    );

/// Le nombre de séances saisi, borné à 1–12 (`Math.max(1, Math.min(12, Number(v) || 1))`).
int blocNombreSeances(Object? v) {
  final n = nombreOuZero(v).truncate();
  return (n == 0 ? 1 : n).clamp(1, 12);
}

// --------------------------------------------------------------------------------------------- sorties d'hospitalisation

/// `soldePatient(patientId)` : la somme des restes dus de TOUTES les factures actives du patient.
num blocSoldePatient(Iterable<BlocFiche> facturesActives, Object? patientId) {
  var s = 0.0;
  for (final f in facturesActives) {
    if (f['patientId'] == patientId) s += nombreOuZero(f['reliquat']);
  }
  return s == s.truncateToDouble() ? s.toInt() : s;
}

({int hospitalises, int finalisables, int bloquees, int realisees}) blocKpisSorties(
    Iterable<BlocFiche> admissionsActives, Iterable<BlocFiche> facturesActives) {
  final ec = hosEnCours(admissionsActives);
  return (
    hospitalises: ec.length,
    finalisables: ec.where((a) => blocSoldePatient(facturesActives, a['patientId']) <= 0).length,
    bloquees: ec.where((a) => blocSoldePatient(facturesActives, a['patientId']) > 0).length,
    realisees: admissionsActives.where((a) => a['statut'] == 'sortie').length,
  );
}

/// RG-07 d'abord (les trois signatures), puis RG-06 (solde non apuré → dérogation motivée, non blanche).
BlocRefus? blocRefusSortie(Map<String, Object?> v, num solde) {
  if (!_vrai(v['sigPatient']) || !_vrai(v['sigInfirmier']) || !_vrai(v['constatGardien'])) {
    return const BlocRefus('RG-07 — les trois signatures sont obligatoires.',
        'Patient, infirmier traitant et constat du gardien.');
  }
  if (solde > 0 && _s(v['derogation']).trim().isEmpty) {
    return const BlocRefus('RG-06 — solde non apuré : une dérogation motivée est requise.',
        'Encaisser le solde à la caisse ou saisir la dérogation de la Direction.');
  }
  return null;
}

/// Ce que la finalisation écrit sur l'admission : elle sort, le lit est libéré.
BlocFiche blocPatchSortie(Map<String, Object?> v) => {
      'statut': 'sortie',
      'dateSortie': v['dateSortie'],
      'etatSortie': v['etatSortie'],
      'consignes': v['consignes'],
      'derogation': _vrai(v['derogation']) ? v['derogation'] : null,
      'signaturePatient': true,
      'signatureInfirmier': true,
      'constatGardien': true,
    };

// --------------------------------------------------------------------------------------------- sortie contre avis médical

/// RG-08 : le motif est obligatoire (champ requis) ; si l'avis du Procureur est coché, sa RÉFÉRENCE l'est aussi.
BlocRefus? blocRefusAvisMedical(Map<String, Object?> v) =>
    _vrai(v['avisProcureur']) && _s(v['referenceProcureur']).trim().isEmpty
        ? const BlocRefus('La référence de l’avis du Procureur est obligatoire.')
        : null;

({int sorties, int procureur, int hospitalises, int clotures}) blocKpisAvis(
        Iterable<BlocFiche> sortiesActives, Iterable<BlocFiche> admissionsActives) =>
    (
      sorties: sortiesActives.length,
      procureur: sortiesActives.where((r) => _vrai(r['avisProcureur'])).length,
      hospitalises: hosEnCours(admissionsActives).length,
      clotures: sortiesActives.where((r) => _vrai(r['cloture'])).length,
    );

/// L'admission concernée par une sortie contre avis médical : le patient, son dossier et son lit sont recopiés (créée ou corrigée) ; la
/// référence reste celle de la fiche (E410).
BlocFiche blocConstruireAvis(Map<String, Object?> v,
    {BlocFiche? admission, BlocFiche? existante, required Iterable<BlocFiche> toutes}) {
  final f = {...v};
  if (admission != null) {
    f['patient'] = admission['patient'];
    f['patientCode'] = admission['patientCode'];
    f['lit'] = admission['lit'];
  }
  f['reference'] = _vrai(existante?['reference'])
      ? existante!['reference']
      : blocReferenceSuivante('SAM', 4, toutes);
  return f;
}
