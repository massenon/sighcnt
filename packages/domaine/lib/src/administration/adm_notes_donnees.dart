// ENGENDRÉ par prototype_html/build/vecteurs-administration.js — NE PAS ÉDITER. Notes de service NS 131 et NS 132 (D.NS131, D.NS132 de la maquette),
// telles que `m13-notes-service` les affiche.

/// NS 131 : critères d’évaluation et sanctions (en %) aux niveaux « moyenne » et « faible à mauvaise ».
class AdmCritereEvaluation {
  const AdmCritereEvaluation(this.numero, this.id, this.libelle, this.moyenne, this.faible);
  final String numero;
  final String id;
  final String libelle;
  final num moyenne;
  final num faible;
}

/// NS 132 : une prime, son mode (`fixe` = forfait mensuel, `occurrence`) et les fonctions concernées (montants en FCFA).
class AdmPrime {
  const AdmPrime(this.id, this.libelle, this.mode, this.montants);
  final String id;
  final String libelle;
  final String mode;
  final Map<String, num> montants;
}

/// Identité d’une note de service (`D.NS131` / `D.NS132`).
class AdmNoteService {
  const AdmNoteService({required this.reference, required this.objet, required this.version, required this.dateSignature, required this.dateEffet, required this.statut, required this.signataire, required this.source, required this.mention});
  final String reference;
  final String objet;
  final int version;
  final String dateSignature;
  final String dateEffet;
  final String statut;
  final String signataire;
  final String source;
  final String mention;
}

const AdmNoteService admNs131 = AdmNoteService(
  reference: 'NS 131/07/DM/DA/CNT/2026',
  objet: 'Modification de l’évaluation du rendement entrant dans le compte de la rémunération salariale',
  version: 1,
  dateSignature: '2026-07-13',
  dateEffet: '2026-07-13',
  statut: 'ACTIVE',
  signataire: 'BASSONGUI C. Séko Y., Directeur Médical',
  source: 'DOC — Note de service NS 131/07/DM/DA/CNT/2026',
  mention: 'Abroge toute disposition antérieure contraire.',
);

const AdmNoteService admNs132 = AdmNoteService(
  reference: 'NS n° 132/07/DM/DA/CNT/2026',
  objet: 'Primes diverses',
  version: 1,
  dateSignature: '2026-07-13',
  dateEffet: '2026-07-13',
  statut: 'ACTIVE',
  signataire: 'BASSONGUI Chabi Séko, Directeur Médical',
  source: 'DOC — Note de service NS 132/07/DM/DA/CNT/2026',
  mention: 'Abroge toute disposition antérieure contraire.',
);

const List<AdmCritereEvaluation> admCriteresNs131 = [
  AdmCritereEvaluation('01', 'ponctualite', 'Ponctualité et assiduité', 6, 10),
  AdmCritereEvaluation('02', 'execution', 'Exécution des tâches', 10, 15),
  AdmCritereEvaluation('03', 'attitude', 'Attitude envers les patients', 6, 10),
  AdmCritereEvaluation('04', 'hierarchie', 'Respect de la hiérarchie', 6, 10),
];

const List<AdmPrime> admPrimesNs132 = [
  AdmPrime('permanence', 'Permanence', 'occurrence', {'aide_soignant': 600, 'caissiere': 600, 'accueil': 700, 'infirmier': 800, 'sage_femme': 800, 'tsl': 800}),
  AdmPrime('garde', 'Garde', 'occurrence', {'aide_soignant': 900, 'caissiere': 900, 'accueil': 900, 'infirmier': 1500, 'sage_femme': 1500, 'tsl': 1500}),
  AdmPrime('aide_bloc', 'Aide bloc', 'occurrence', {'aide_soignant': 500, 'caissiere': 500, 'accueil': 500, 'infirmier': 500, 'sage_femme': 500}),
  AdmPrime('bloc_fixe', 'Prime de bloc fixe', 'fixe', {'aide_soignant': 10000, 'infirmier': 10000}),
  AdmPrime('hydrotubation', 'Hydrotubation', 'occurrence', {'infirmier': 1300}),
  AdmPrime('accouchement', 'Accouchement', 'occurrence', {'sage_femme': 1000}),
  AdmPrime('caisse', 'Caisse', 'fixe', {'caissiere': 10000}),
  AdmPrime('urgence', 'Urgence', 'occurrence', {'tsl': 2500}),
  AdmPrime('incineration', 'Incinération', 'fixe', {'aide_soignant': 5000}),
  AdmPrime('accueil', 'Accueil', 'fixe', {'accueil': 7000}),
  AdmPrime('circoncision', 'Circoncision', 'occurrence', {'sage_femme': 1000}),
];

/// `D.FONCTIONS` : identifiant → libellé (la carte de la NS 132 n’en affiche que le premier mot).
const Map<String, String> admFonctions = {
  'aide_soignant': 'Aide-soignant(e)',
  'caissiere': 'Caissière',
  'accueil': 'Accueil / Secrétaire médical',
  'infirmier': 'Infirmier(ère)',
  'sage_femme': 'Sage-femme',
  'tsl': 'TSL (Technicien Supérieur de Laboratoire)',
  'biomedical': 'Ingénieur biomédical',
  'medecin': 'Médecin',
  'direction': 'Direction',
  'comptable': 'Comptable',
  'stock': 'Gestionnaire de stock',
  'dispensatrice': 'Dispensatrice',
  'securite': 'Agent de sécurité',
  'entretien': 'Agent d’entretien',
  'chauffeur': 'Chauffeur coursier',
};
