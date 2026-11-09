// LE REGISTRE DES PARAMÈTRES DÉCLARÉS (lot L0) : ce que les paramètres du poste proposent, avec leur défaut SEMÉ.
//
// C'est une DONNÉE, pas du code de gestion : le poste en sème la version 0 dans la collection `parametres` au premier démarrage (même fiche sur tous les postes,
// voir [Parametres.semer]) ; la valeur en vigueur se LIT ensuite dans la base, par [Parametres.resoudre], jamais ici. Chaque lot déclare ses paramètres dans cette
// liste, avec la source de son défaut. Aucun taux, aucune date, aucun numéro n'est inventé : les six entrées ci-dessous portent les défauts que la Direction a
// arrêtés le 09/11/2026 (`docs/decisions/DECISIONS-A-VALIDER.md`, section D ; `docs/plans/PLAN-decisions-2026-11-09.md`, colonne « Défaut »).
//
// `branche: false` : le réglage s'enregistre et se synchronise, mais l'écran qu'il commande ne le lit pas encore (lot à venir) ; l'écran des paramètres le dit.
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
    aide: 'Boîtier physique ou e-MECeF. Aucun numéro n\'est simulé au poste ; le mode e-MECeF reste « non configuré : dossier d\'interface DGI requis ».',
    source: _decisions,
    branche: false,
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
    aide: 'La clinique ne subit pas d\'AIB : par défaut elle supporte le prélèvement. Texte réglementaire à obtenir : tout reste « proposition à valider ».',
    source: _decisions,
    branche: false,
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
    branche: false,
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
    branche: false,
    appliquePar: 'Lot L6 (propositions de planning)',
  ),
  DefinitionParametre(
    cle: 'paie.copieFichePaieTelephone',
    famille: 'paie',
    type: TypeParametre.booleen,
    defaut: true,
    libelle: 'Copie chiffrée de la fiche de paie sur le téléphone',
    aide: 'Oui : l\'agent garde une copie chiffrée de sa fiche de paie sur son téléphone.',
    source: _decisions,
    branche: false,
    appliquePar: 'Lot L7 (espace « Mes »)',
  ),
  DefinitionParametre(
    cle: 'planning.badgeSertDePointage',
    famille: 'planning',
    type: TypeParametre.booleen,
    defaut: true,
    libelle: 'Le badge sert de pointage',
    aide: 'Oui : le badge se relie au registre des présences.',
    source: _decisions,
    branche: false,
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
