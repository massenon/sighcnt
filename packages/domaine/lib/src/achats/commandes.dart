/// BONS DE COMMANDE (m7-commandes) — RG-04 : toute commande de stock gros est validée par la Directrice Administrative AVANT transmission.
///
/// Rejoué sur `test/vecteurs/achats-commandes.json` (écran réel piloté dans Chrome).
///
/// Lot CLO-3 (Direction, 16/11/2026, section AH point 3 et AQ point 1) : VALIDER est le geste réservé `valider_commande_stock` de la fiche RBAC (d'origine la
/// Directrice Administrative seule), jamais un nom écrit : le validateur enregistré est l'AGENT de la session ; choisir « Validée », « Transmise », « Livrée » ou
/// « Soldée » au formulaire est REFUSÉ tant que la commande n'est pas validée par le geste (ce qui remplace les écarts E72 et E74 de la maquette d'origine).
library;

import 'nombres.dart';
import 'besoins.dart';

class StatutCommande {
  const StatutCommande(this.valeur, this.libelle, this.ton);
  final String valeur;
  final String libelle;
  final String ton;
}

const statutsCommande = [
  StatutCommande('brouillon', 'Brouillon', 'neutral'),
  StatutCommande('attente_validation', 'En attente de validation', 'warning'),
  StatutCommande('validee', 'Validée', 'info'),
  StatutCommande('transmise', 'Transmise au fournisseur', 'navy'),
  StatutCommande('livree', 'Livrée', 'success'),
  StatutCommande('soldee', 'Soldée', 'success'),
];

String libelleCommande(Object? s) => statutsCommande
    .firstWhere((x) => x.valeur == s,
        orElse: () => StatutCommande('$s', '$s', 'neutral'))
    .libelle;

String toneCommande(Object? s) => statutsCommande
    .where((x) => x.valeur == s)
    .map((x) => x.ton)
    .firstOrNull ??
    'neutral';

typedef _Commande = Map<String, Object?>;

num _n(Object? v) => nombreEntier(v);

List<_Commande> commandesEnAttente(Iterable<_Commande> actives) => [
      for (final c in actives)
        if (c['statutCommande'] == 'attente_validation') c
    ];

/// Les quatre indicateurs de l'écran.
({int enregistrees, int enAttente, num montant, int livrees}) indicateursCommandes(
        Iterable<_Commande> actives) =>
    (
      enregistrees: actives.length,
      enAttente: commandesEnAttente(actives).length,
      montant: actives.fold<num>(0, (a, c) => a + _n(c['montant'])),
      livrees: actives
          .where((c) => const ['livree', 'soldee'].contains(c['statutCommande']))
          .length,
    );

/// Le geste réservé de la fiche RBAC qui valide une commande de stock gros (RG-04).
const gesteValiderCommandeStock = 'valider_commande_stock';

/// Les statuts qu'aucun formulaire ne pose : seul le geste de validation (ou la poursuite du circuit d'une commande déjà validée) y mène.
const statutsCommandeValides = ['validee', 'transmise', 'livree', 'soldee'];

bool _validee(_Commande? c) =>
    c != null && statutsCommandeValides.contains(c['statutCommande']) && c['valideePar'] != null && c['valideePar'] != '';

/// Le refus de la maquette quand on choisit un statut validé sans validation (même texte, dit à l'agent).
String messageStatutCommandeNonValide(String statut, String valideurs) =>
    'Statut refusé (COMMANDE_NON_VALIDEE) : « ${libelleCommande(statut)} » ne se choisit pas au formulaire, la commande doit d’abord être validée par le geste « Valider une commande de stock gros » ($valideurs, RG-04). Choisir « En attente de validation ».';

/// Le geste de validation (RG-04) : la commande devient « Validée » et elle peut alors être transmise. Rend le correctif à écrire ou lève le refus NOMMÉ
/// (droit absent : le moteur refuse aussi, un bouton masqué ne protège rien ; commande introuvable, déjà validée, pas en attente).
/// [agent] est l'agent de la session ; [libelleRole] le libellé de son rôle ; [valideurs] les libellés des rôles qui détiennent le droit.
_Commande validationCommande(
    {required _Commande? commande,
    required String jour,
    required String agent,
    required bool gesteAccorde,
    required String libelleRole,
    required String valideurs}) {
  if (!gesteAccorde) {
    throw RefusAchat(
        'Validation refusée (VALIDATION_COMMANDE_RESERVEE) : Valider une commande de stock gros (RG-04) est un droit réservé de la fiche du rôle (« Valider une commande de stock gros ») : « $libelleRole » ne l’a pas. Demander la validation à : $valideurs.');
  }
  if (commande == null || commande['statut'] == 'archive') {
    throw const RefusAchat('Validation refusée (COMMANDE_INCONNUE) : La commande est introuvable ou archivée. Rafraîchir l’écran.');
  }
  if (_validee(commande)) {
    throw RefusAchat(
        'Validation refusée (COMMANDE_DEJA_VALIDEE) : La commande ${commande['reference']} est déjà validée par ${commande['valideePar']} : une validation ne se réécrit pas. Aucun geste : la commande peut suivre son circuit.');
  }
  if (commande['statutCommande'] != 'attente_validation') {
    throw RefusAchat(
        'Validation refusée (COMMANDE_PAS_EN_ATTENTE) : La commande ${commande['reference']} est « ${commande['statutCommande']} » : seule une commande en attente de validation se valide. Soumettre la commande à la validation d’abord (statut « En attente de validation »).');
  }
  return {'statutCommande': 'validee', 'valideePar': agent, 'dateValidation': jour};
}

/// LA GARDE RG-04 DU MAGASIN (`S.garder('commandes')` de la maquette) : un statut « validée », « transmise », « livrée » ou « soldée » (ou un validateur) ne naît que de la validation
/// posée par le geste réservé (de « en attente de validation » vers « validée », validateur nommé), jamais d'une autre écriture ; une validation posée ne se réécrit pas (RG-14).
/// Rend le motif nommé du refus ou `null`. [apres] est la fiche fusionnée ; [avant] la fiche d'avant (null à la création).
String? gardeCommandeRg04(String operation, Map<String, Object?> apres, Map<String, Object?>? avant) {
  if (operation != 'inserer' && operation != 'modifier') return null;
  final valide = statutsCommandeValides.contains(apres['statutCommande']);
  final aValideur = apres['valideePar'] != null && apres['valideePar'] != '';
  if (operation == 'modifier' && _validee(avant)) {
    if ('${avant!['valideePar']}' != '${apres['valideePar'] ?? ''}' || '${avant['dateValidation'] ?? ''}' != '${apres['dateValidation'] ?? ''}') {
      return 'VALIDATION_COMMANDE_FIGEE : la validation de la commande ${avant['reference']} (${avant['valideePar']}) ne se réécrit pas.';
    }
    return null;
  }
  final geste = operation == 'modifier' && avant != null && avant['statutCommande'] == 'attente_validation' && apres['statutCommande'] == 'validee' && aValideur;
  if ((valide || aValideur) && !geste && !(operation == 'inserer' && valide && aValideur)) {
    return 'COMMANDE_NON_VALIDEE : un statut « validée », « transmise », « livrée » ou « soldée » (ou un validateur) ne se pose que par le geste « Valider une commande de stock gros » (RG-04), jamais par le formulaire.';
  }
  return null;
}

/// Une ligne de commande : l'article, la quantité et le prix unitaire (la valeur est quantité × prix).
_Commande nouvelleLigneCommande(
    {required Map<String, Object?>? produit,
    required Object? quantite,
    required Object? prixUnitaire}) {
  final q = _n(quantite), pu = _n(prixUnitaire);
  if (produit == null || q <= 0) {
    throw const RefusAchat('Sélectionner un article et une quantité.');
  }
  return {
    'produitId': produit['id'],
    'produit': produit['designation'],
    'unite': produit['unite'],
    'quantite': q,
    'prixUnitaire': pu,
    'montant': q * pu,
  };
}

num montantCommande(Iterable<_Commande> lignes) =>
    lignes.fold<num>(0, (a, l) => a + _n(l['montant']));

/// Enregistre une commande (création ou modification) : ce que la modale de la maquette écrit.
/// [fournisseurs] = les fiches du référentiel (code, nom, délai) ; [commandes] = TOUTES les commandes (archivées comprises, pour la série).
_Commande commandeEnregistree(
    {required _Commande saisie,
    required List<_Commande> lignes,
    _Commande? existante,
    required Iterable<_Commande> fournisseurs,
    required Iterable<_Commande> commandes,
    required String jour,
    String valideurs = 'aucun rôle'}) {
  if (lignes.isEmpty) throw const RefusAchat('Ajouter au moins un article.');
  final v = {...saisie};
  final four =
      fournisseurs.where((x) => x['code'] == v['fournisseur']).firstOrNull;
  v['fournisseurNom'] = four != null ? four['nom'] : v['fournisseur'];
  v['delaiLivraison'] = four?['delai'];
  v['lignes'] = lignes;
  v['montant'] = montantCommande(lignes);
  if (existante == null) {
    // Année de la DATE DE LA PIÈCE (lot MIL) : jamais une année écrite ; le jour est un ISO AAAA-MM-JJ.
    final annee = RegExp(r'^\d{4}').firstMatch(jour)?.group(0);
    if (annee == null) {
      throw const RefusAchat('Date de la commande illisible : le numéro ne peut pas être attribué.');
    }
    v['reference'] = referenceAchatSuivante('BC-$annee-', 4, commandes);
  }
  // RG-04 : choisir un statut validé ne vaut PAS validation (refus nommé) ; une commande déjà validée garde son validateur et sa date.
  if (statutsCommandeValides.contains(v['statutCommande']) &&
      !(_validee(existante))) {
    throw RefusAchat(messageStatutCommandeNonValide('${v['statutCommande']}', valideurs));
  }
  if (_validee(existante)) {
    v.remove('valideePar');
    v.remove('dateValidation');
  }
  return v;
}

/// Les commandes à réceptionner : validées ou transmises (jamais avant la validation de la DAF).
List<_Commande> commandesAReceptionner(Iterable<_Commande> actives) => [
      for (final c in actives)
        if (const ['validee', 'transmise'].contains(c['statutCommande'])) c
    ];

/// Les quatre indicateurs de l'écran des réceptions.
({int aReceptionner, int realisees, num valeurAttendue, int fournisseurs})
    indicateursReceptions(Iterable<_Commande> actives) {
  final a = commandesAReceptionner(actives);
  return (
    aReceptionner: a.length,
    realisees: actives
        .where((c) => const ['livree', 'soldee'].contains(c['statutCommande']))
        .length,
    valeurAttendue: a.fold<num>(0, (s, c) => s + _n(c['montant'])),
    fournisseurs: {for (final c in a) '${c['fournisseur']}'}.length,
  );
}
