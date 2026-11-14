import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/service_installation.dart';
import '../../donnees/tarifs_poste.dart';
import '../../kit/validation_poste.dart';
import '../../shell/contexte_ecran.dart';

/// Le `TarifsPoste` d'un écran, avec les droits de l'agent connecté LUS DE LA MATRICE (jamais écrits en dur) : éditer « Tarifs et prix » (proposer une prestation), modifier « Référentiel produits »
/// (proposer un prix d'achat), modifier les réceptions d'achats (la proposition née d'une réception). Décider (Oui ou Non) reste la liste de rôles de la famille, jamais `editer`. Sur un FILEUL
/// rattaché, le moteur DÉPOSE une demande que la mère applique : il n'écrit jamais une version (famille R).
///
/// Lot TFIN-2 : sorti de `cft_tarifs.dart` pour que « Référentiel produits » (m6) et « Réceptions & contrôles » (m7) portent le MÊME geste que l'écran des prix, par le même objet.
TarifsPoste tarifsDeEcran(ContexteEcran c) {
  final m = c.magasin;
  final matrice = c.donnees?.matrice;
  return TarifsPoste(m,
      role: c.role,
      auteur: () => c.agent.nom.isEmpty ? 'Utilisateur' : c.agent.nom,
      fileul: ServiceInstallation.de(m).rattache,
      libelles: ValidationPoste(c).libelles,
      peutEditerEcran: c.droit.editer,
      peutEditerPour: matrice == null ? null : (r) => matrice.peutEditer(r, 'cfg-tarifs'),
      peutProposerPrixAchat: matrice?.peutEditer(c.role, 'm6-produits') ?? false,
      peutProposerPrixAchatPour: matrice == null ? null : (r) => matrice.peutEditer(r, 'm6-produits'),
      peutProposerReception: matrice?.peutEditer(c.role, 'm7-receptions') ?? false,
      peutProposerReceptionPour: matrice == null ? null : (r) => matrice.peutEditer(r, 'm7-receptions'),
      horloge: () => c.aujourdhui,
      etiquette: m.poste.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase());
}

/// Le prix d'achat EN VIGUEUR aujourd'hui d'un produit (jamais la fiche). Source unique de la colonne de « Référentiel produits », de celle de l'onglet Produits de « Tarifs et prix » et du filtre.
PrixProduit prixDuJour(ContexteEcran c, Map<String, Object?> produit) => TarifsPoste.prixProduit(c.magasin, produit, aujourdhui: c.aujourdhui, date: tarIso(c.aujourdhui));

/// Un article « à valoriser » : doté d'une prestation de prix mais sans prix d'achat en vigueur aujourd'hui (prix absent, jamais zéro : l'article ne se facture pas).
bool aValoriser(ContexteEcran c, Map<String, Object?> produit) => TarifsPoste.lire(c.magasin).parCode['${produit['code']}'] != null && prixDuJour(c, produit).absent;

/// Le prix d'achat en vigueur aujourd'hui (la version), `null` quand il est absent. Un article qui n'a PAS ENCORE de prestation de prix (avant la reprise de la mère) montre le prix que sa fiche
/// tient : c'est le seul cas où la fiche est lue.
num? achatDuJour(ContexteEcran c, Map<String, Object?> p) {
  if (TarifsPoste.lire(c.magasin).parCode['${p['code']}'] == null) return p['prixAchat'] as num?;
  final r = prixDuJour(c, p);
  return r.absent ? null : r.achat;
}

/// Le prix de vente DÉRIVÉ (RG-02) en vigueur aujourd'hui ; même repli que [achatDuJour].
num? venteDuJour(ContexteEcran c, Map<String, Object?> p) {
  if (TarifsPoste.lire(c.magasin).parCode['${p['code']}'] == null) return p['prixVente'] as num?;
  final r = prixDuJour(c, p);
  return r.absent ? null : r.vente;
}
