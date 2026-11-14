// LE REGISTRE DES PARAMÈTRES DÉCLARÉS (lot L0) : ce que les paramètres du poste proposent, avec leur défaut SEMÉ.
//
// C'est une DONNÉE, pas du code de gestion : le poste en sème la version 0 dans la collection `parametres` au premier démarrage (même fiche sur tous les postes,
// voir [Parametres.semer]) ; la valeur en vigueur se LIT ensuite dans la base, par [Parametres.resoudre], jamais ici. Chaque lot déclare ses paramètres dans cette
// liste, avec la source de son défaut. Aucun taux, aucune date, aucun numéro n'est inventé : les six entrées ci-dessous portent les défauts que la Direction a
// arrêtés le 09/11/2026 (`docs/decisions/DECISIONS-A-VALIDER.md`, section D ; `docs/plans/PLAN-decisions-2026-11-09.md`, colonne « Défaut »).
//
// `branche: false` : le réglage s'enregistre et se synchronise, mais l'écran qu'il commande ne le lit pas encore (lot à venir) ; l'écran des paramètres le dit.
// Le lot L3 a branché `mecef.mode` (lu par la normalisation, voir `src/mecef/mode.dart`). Les lots L5 et L6 ont branché `planning.circuitPresences` et
// `planning.agentModifieDirectement` (lus par le moteur du planning RH, `src/rh/planning_rh.dart`, et par la maquette). Les lots L7 et L8 ont branché
// `paie.copieFichePaieTelephone` (`src/rh/espace_mes.dart`), `planning.badgeSertDePointage` et `planning.delaiEntrePointagesBadge` (`src/rh/pointage_badge.dart`).
// Le lot ORG2 a branché `securite.delaiVerrouPosteSecours` (`src/securite/verrou_secours.dart`, lu par le verrou de session d'un poste désigné de secours).
// Le lot U a branché `affichage.planDuSite` (`src/acces/acc_plan_du_site.dart`, lu par les pages d'erreur, la commande des paramètres et l'adresse du plan du site).
// Aucune de ces définitions n'est envoyée au téléphone (`mobile: false`) : la liste blanche est vide tant qu'un lot ne démontre pas le besoin (RG-13).

import '../fichiers/ocr.dart' show ocrCleActif, ocrCleMoteur, ocrCleLangue, ocrCleDelai, ocrLangueDefaut, ocrDelaiDefautMs;
import 'parametres.dart';

const String _decisions = 'Décision de la Direction du 09/11/2026 (DECISIONS-A-VALIDER, section D)';

const List<DefinitionParametre> definitionsParametres = [
  DefinitionParametre(
    cle: 'mecef.mode',
    famille: 'mecef',
    type: TypeParametre.choix,
    choix: ['boitier', 'emecef'],
    libellesChoix: {'boitier': 'Boîtier physique', 'emecef': 'e-MECeF'},
    defaut: 'boitier',
    libelle: 'Mode de certification des factures',
    aide: 'Boîtier physique ou e-MECeF. Aucun numéro n\'est simulé au poste : sans adaptateur configuré, la vente reste en attente de certification. Le mode e-MECeF reste « non configuré : dossier d\'interface DGI requis ».',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L3 (MECeF)',
  ),
  DefinitionParametre(
    cle: 'bareme_aib.chargePrelevement',
    famille: 'bareme_aib',
    type: TypeParametre.choix,
    choix: ['clinique', 'acheteur'],
    libellesChoix: {'clinique': 'La clinique', 'acheteur': 'L\'acheteur'},
    defaut: 'clinique',
    libelle: 'Qui supporte le prélèvement de l\'AIB',
    aide: 'La clinique ne subit pas d\'AIB : par défaut elle supporte le prélèvement. Texte officiel manquant : réglage non arrêté (aucun effet comptable), la valeur à la date est portée par chaque vente et listée aux achats. Réglé ici ou à l\'écran « Barème de l\'AIB », onglet « Réglages » : les mêmes règles s\'appliquent.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L2 (AIB)',
  ),
  DefinitionParametre(
    cle: 'bareme_aib.branchementAchats',
    famille: 'bareme_aib',
    type: TypeParametre.choix,
    choix: ['desactive', 'actif'],
    libellesChoix: {'desactive': 'Désactivé (le moteur liste, n\'écrit rien)', 'actif': 'Activé (écrit ce qui est listé)'},
    defaut: 'desactive',
    libelle: 'Brancher l\'AIB sur les écritures d\'achat',
    aide: 'Différé par décision de la Direction : désactivé par défaut. L\'activation exige le compte d\'acompte, le compte de contrepartie et la charge arrêtés (refus nommé sinon).',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L2 (AIB)',
  ),
  DefinitionParametre(
    cle: 'bareme_aib.compteAcompte',
    famille: 'bareme_aib',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Compte d\'acompte (débit)',
    aide: 'Choisi par le comptable dans le plan comptable : aucun numéro n\'est proposé d\'office (vide tant qu\'il n\'est pas choisi).',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L2 (AIB)',
  ),
  DefinitionParametre(
    cle: 'bareme_aib.compteContrepartie',
    famille: 'bareme_aib',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Compte de contrepartie (crédit)',
    aide: 'Choisi par le comptable dans le plan comptable : une écriture s\'équilibre sur deux comptes que la clinique désigne (vide tant qu\'il n\'est pas choisi).',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L2 (AIB)',
  ),
  DefinitionParametre(
    cle: 'planning.circuitPresences',
    famille: 'planning',
    type: TypeParametre.choix,
    choix: ['surveillant', 'daf', 'surveillant_puis_daf'],
    libellesChoix: {'surveillant': 'Surveillant seul', 'daf': 'Directrice administrative seule', 'surveillant_puis_daf': 'Surveillant puis directrice administrative'},
    defaut: 'surveillant',
    libelle: 'Circuit de validation des présences et absences',
    aide: 'Surveillant seul, directrice administrative seule, ou surveillant puis directrice administrative. Congés et ordres de mission suivent le même circuit.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L5 (circuit des présences)',
  ),
  DefinitionParametre(
    cle: 'planning.agentModifieDirectement',
    famille: 'planning',
    type: TypeParametre.booleen,
    defaut: false,
    libelle: 'L\'agent modifie directement son planning',
    aide: 'Non : l\'agent propose, le surveillant valide.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L6 (propositions de planning)',
  ),
  DefinitionParametre(
    cle: 'paie.copieFichePaieTelephone',
    famille: 'paie',
    type: TypeParametre.booleen,
    defaut: true,
    libelle: 'Copie chiffrée de la fiche de paie sur le téléphone',
    aide: 'Oui : l\'agent garde sur son téléphone une copie chiffrée de sa propre fiche de paie ÉMISE (diffusée), jamais celle d\'un autre, jamais l\'ensemble de la paie, jamais recalculée à l\'appareil. Le réglage lui-même ne va PAS au téléphone (famille « paie » réservée) : la mère décide de publier ou de retirer la copie.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L7 (espace « Mes »)',
  ),
  DefinitionParametre(
    cle: 'planning.badgeSertDePointage',
    famille: 'planning',
    type: TypeParametre.booleen,
    defaut: true,
    libelle: 'Le badge sert de pointage',
    aide: 'Oui : un badge vérifié valide crée une présence « à valider » au registre (arrivée, puis départ au passage suivant), qui suit le circuit de validation des présences.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L8 (badge et pointage)',
  ),
  DefinitionParametre(
    cle: 'planning.delaiEntrePointagesBadge',
    famille: 'planning',
    type: TypeParametre.entier,
    defaut: 5,
    libelle: 'Délai minimal entre deux pointages par badge (minutes)',
    aide: 'Deux passages du même badge plus rapprochés sont refusés. Entier de 0 à 720 ; 0 ne refuse jamais. Valeur d\'attente de 5 minutes : aucun document ne la fixe, proposition à valider par la Direction.',
    source: 'Proposition à valider (lot L8) : aucun document ne fixe ce délai',
    branche: true,
    appliquePar: 'Lot L8 (badge et pointage)',
  ),
  DefinitionParametre(
    cle: 'securite.delaiVerrouPosteSecours',
    famille: 'securite',
    type: TypeParametre.entier,
    defaut: 5,
    libelle: 'Délai de verrou d\'un poste de secours (minutes)',
    aide: 'Un poste partagé de secours, où un agent sans téléphone ouvre sa propre session, se verrouille plus vite qu\'un poste ordinaire. Entier de 1 à 120. Valeur d\'attente de 5 minutes proposée par l\'équipe : aucun document ne la fixe, à valider par la Direction. Le délai ordinaire de 15 minutes (CDCT 12.2, politique de sécurité) ne change pas. Quel poste est « de secours » se désigne à ce poste même (donnée locale, jamais synchronisée).',
    source: 'Proposition à valider (décision P3 du 11/11/2026) : aucun document ne fixe ce délai',
    branche: true,
    appliquePar: 'Lot ORG2 (verrou d\'un poste de secours)',
  ),
  DefinitionParametre(
    cle: 'affichage.planDuSite',
    famille: 'affichage',
    type: TypeParametre.booleen,
    defaut: false,
    libelle: 'Afficher le plan du site',
    aide: 'Non par défaut (case décochée, « Installation et données », carte « Affichage ») : le plan du site (liste de tous les écrans) n\'est ni proposé dans les paramètres, ni sur les pages 403 et 404, et son adresse directe mène à la page 404. Seuls l\'administrateur et la Directrice Administrative le règlent. Réglage de la clinique : il voyage aux postes par le journal de configuration, jamais aux téléphones.',
    source: 'Demande de la Direction du 11/11/2026 (DECISIONS-A-VALIDER, section J) : désactivé par défaut',
    branche: true,
    appliquePar: 'Lot U (plan du site réglable)',
  ),
  // Lot C : la lecture des scans (OCR) est un réglage de CLINIQUE posé à la poste mère, versionné par date, reçu des fileuls, JAMAIS envoyé à un téléphone (`mobile: false`, famille réservée).
  // Il se règle à l'écran « Lecture des scans (OCR) » (droit, motif, refus nommés), pas au panneau générique.
  DefinitionParametre(
    cle: ocrCleActif,
    famille: 'ocr',
    type: TypeParametre.booleen,
    defaut: false,
    libelle: 'Lecture automatique des scans (OCR)',
    aide: 'Désactivée par défaut : l\'administrateur ou la Directrice Administrative l\'active à la main, une fois un moteur installé. Réglage de la clinique, posé à la poste mère.',
    source: 'Décision de la Direction du 13/11/2026 (DECISIONS-A-VALIDER, sections T et V) : désactivée par défaut, activée à la main',
    branche: true,
    appliquePar: 'Lot C (réglage OCR de clinique)',
  ),
  DefinitionParametre(
    cle: ocrCleMoteur,
    famille: 'ocr',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Moteur d\'OCR choisi',
    aide: 'Identifiant du moteur ; vide : aucun. Chaque poste dit seulement s\'il l\'a installé. Aucun moteur n\'est livré : la Direction le choisit après un essai sur trois vrais scans. Proposition à valider : le choix du moteur est posé par la clinique.',
    source: 'Proposition à valider (lot C) : la Direction n\'a pas dit qui choisit le moteur',
    branche: true,
    appliquePar: 'Lot C (réglage OCR de clinique)',
  ),
  DefinitionParametre(
    cle: ocrCleLangue,
    famille: 'ocr',
    type: TypeParametre.texte,
    defaut: ocrLangueDefaut,
    libelle: 'Langue de lecture',
    aide: 'Code de langue du moteur (« fra » pour le français).',
    source: 'Défaut du lot OCR-prep : français (langue de travail de la clinique)',
    branche: true,
    appliquePar: 'Lot C (réglage OCR de clinique)',
  ),
  DefinitionParametre(
    cle: ocrCleDelai,
    famille: 'ocr',
    type: TypeParametre.entier,
    defaut: ocrDelaiDefautMs,
    libelle: 'Délai de lecture par page (millisecondes)',
    aide: 'Au-delà, la lecture de la page est arrêtée, puis se relance. Valeur d\'attente de 120 secondes (lot OCR-prep) : aucun document ne la fixe, à valider.',
    source: 'Proposition à valider (lot OCR-prep) : aucun document ne fixe ce délai',
    branche: true,
    appliquePar: 'Lot C (réglage OCR de clinique)',
  ),
];

/// Le libellé d'une famille de paramètres, pour les onglets de l'écran des paramètres. Une famille absente de la table s'affiche sous son identifiant.
const Map<String, String> libellesFamillesParametres = {
  'mecef': 'MECeF',
  'bareme_aib': 'AIB',
  'planning': 'Planning et présences',
  'paie': 'Paie',
  'securite': 'Sécurité',
  'affichage': 'Affichage',
  'ocr': 'Lecture des scans (OCR)',
};

/// La définition d'une clé, ou `null`.
DefinitionParametre? definitionDeParametre(String cle) {
  for (final d in definitionsParametres) {
    if (d.cle == cle) return d;
  }
  return null;
}
