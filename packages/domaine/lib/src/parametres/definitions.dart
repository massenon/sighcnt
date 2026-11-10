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
// Aucune de ces définitions n'est envoyée au téléphone (`mobile: false`) : la liste blanche est vide tant qu'un lot ne démontre pas le besoin (RG-13).

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
];

/// Le libellé d'une famille de paramètres, pour les onglets de l'écran des paramètres. Une famille absente de la table s'affiche sous son identifiant.
const Map<String, String> libellesFamillesParametres = {
  'mecef': 'MECeF',
  'bareme_aib': 'AIB',
  'planning': 'Planning et présences',
  'paie': 'Paie',
};

/// La définition d'une clé, ou `null`.
DefinitionParametre? definitionDeParametre(String cle) {
  for (final d in definitionsParametres) {
    if (d.cle == cle) return d;
  }
  return null;
}
