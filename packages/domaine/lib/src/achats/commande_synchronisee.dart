// LOT CMD (Direction, section AQ point 1 : « ELLE VOYAGE A LA SYNCHRONISATION ») : la COMMANDE DE STOCK GROS (RG-04) voyage entre les postes. Avant ce lot, la collection `commandes` restait
// locale : la Directrice Administrative ne pouvait valider que sur le poste de création.
//
// QUATRE RÈGLES, tenues ici et jamais recopiées ailleurs :
//  1. RÉFÉRENCE. Une commande créée sur un FILEUL porte une référence PROVISOIRE par poste, `BC-<année de la pièce>-P<poste>-nnnn` ; la MÈRE attribue le rang DÉFINITIF `BC-<année>-nnnn` à l'adoption
//     (le plus grand rang définitif de cette année, plus un). Une référence définitive ne se réécrit jamais (une pièce émise ne se réécrit pas) ; les anciennes références `BC-AAAA-nnnn` restent valides
//     et comptent dans la série. Pourquoi : deux fileuls tireraient le même rang d'une série `BC-2026-nnnn` ; seul le rang de la mère est unique (même principe que le code patient).
//  2. FAMILLE A (champ à champ), identité COMMUNE par le contenu (fournisseur, date, lignes) : deux postes qui saisissent la même commande, mère coupée, n'en font qu'UNE ; un rejeu est sans effet.
//     Jamais vers un téléphone (RG-13) : le prix d'achat et le fournisseur ne sont lus par aucun écran du mobile (refus nommé `achats_interdits_au_mobile` du lot de tournée).
//  3. VALIDATION SUR UN FILEUL. Le geste réservé `valider_commande_stock` se prend sur n'importe quel poste : sur un fileul, la décision est SIGNÉE et déposée dans `demandesValidation` (famille
//     `commande_stock`, circuit du lot CONT). La MÈRE l'applique MÉCANIQUEMENT, datée de la signature, après avoir refait les contrôles sous le RÔLE de l'auteur (le droit se relit à la mère : un
//     bouton absent ne protège rien). Une validation ÉCRITE DIRECTEMENT sur la fiche par un autre poste est REFUSÉE au rejeu par la mère (refus nommé `COMMANDE_VALIDATION_DIRECTE`).
//  4. Le numéro de la commande n'entre PAS dans l'identité (il est provisoire puis réécrit une fois par la mère).
library;

import 'dart:convert';

import '../fichiers/sha256.dart';
import '../numerotation/reference_annuelle.dart' show anneeDePiece;
import '../validation/demande_validation.dart';
import '../validation/validation.dart' show RefusValidation, valInstant;
import 'besoins.dart' show RefusAchat;
import 'commandes.dart';

/// La collection de ce lot (famille A à la mère).
const Set<String> collectionsAchatsSynchronisees = {'commandes'};

/// Elle ne va JAMAIS vers un téléphone (RG-13).
const Set<String> collectionsAchatsJamaisMobile = collectionsAchatsSynchronisees;

/// Le code du refus d'un lot de tournée qui nomme la commande.
const String codeAchatsInterditsAuMobile = 'achats_interdits_au_mobile';

/// La famille d'une décision de validation d'une commande dans `demandesValidation` (le registre des 15 familles de référentiels ne la porte pas : ce n'est pas un marquage « à valider »).
const String valFamilleCommandeStock = 'commande_stock';

/// Le libellé de cette décision (centre de notifications, pastille).
const String valLibelleCommandeStock = 'Validation d’une commande de stock gros (RG-04)';

String _norme(Object? v) => '${v ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _jour(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

/// L'identité de synchronisation COMMUNE d'une commande créée sur un poste, tirée de son contenu : fournisseur, jour de la pièce, lignes (article, quantité, prix unitaire, triées).
/// `null` si le fournisseur, la date ou les lignes manquent (la fiche garde alors l'identité propre à son poste, jamais une identité inventée).
String? identiteSyncCommande(Map<String, Object?> f) {
  final lignes = f['lignes'];
  if ('${f['fournisseur'] ?? ''}'.isEmpty || '${f['date'] ?? ''}'.isEmpty || lignes is! List || lignes.isEmpty) return null;
  final l = [
    for (final x in lignes)
      if (x is Map) '${_norme(x['produitId'])}:${_norme(x['quantite'])}:${_norme(x['prixUnitaire'])}'
  ]..sort();
  final e = sha256Octets(utf8.encode([_norme(f['fournisseur']), _jour(f['date']), ...l].join('|'))).substring(0, 20);
  return 'CMD-$e';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// RÉFÉRENCES
// ---------------------------------------------------------------------------------------------------------------------------------------------------

final RegExp _reProvisoire = RegExp(r'^BC-(\d{4})-P([A-Za-z0-9]+)-(\d+)$');
final RegExp _reDefinitive = RegExp(r'^BC-(\d{4})-(\d+)$');

/// Une référence `BC-AAAA-P<poste>-nnnn` : attribuée par un fileul, en attente du rang de la mère.
bool estReferenceCommandeProvisoire(Object? r) => _reProvisoire.hasMatch('${r ?? ''}');

/// Une référence définitive `BC-AAAA-nnnn` (celle de la mère, ou une ancienne référence valide).
bool estReferenceCommandeDefinitive(Object? r) => _reDefinitive.hasMatch('${r ?? ''}');

/// La référence PROVISOIRE d'une commande créée sur le poste [poste] : l'année est celle de la DATE DE LA PIÈCE (jamais une constante), le rang suit les provisoires de CE poste et de cette année
/// déjà écrites dans [commandes] (archivées comprises). [poste] : lettres et chiffres seuls (le reste est retiré). L'année vient de la fabrique unique du lot MIL (`anneeDePiece`) ; le rang, propre à chaque poste, est le seul calcul gardé ici.
String referenceCommandeProvisoire(
    {required Object? date, required String poste, required Iterable<Map<String, Object?>> commandes, required DateTime maintenant}) {
  final p = poste.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  final cle = p.isEmpty ? 'X' : p;
  final an = anneeDePiece(date, maintenant);
  var max = 0;
  for (final c in commandes) {
    final m = _reProvisoire.firstMatch('${c['reference'] ?? ''}');
    if (m != null && m.group(1) == '$an' && m.group(2) == cle) {
      final n = int.parse(m.group(3)!);
      if (n > max) max = n;
    }
  }
  return 'BC-$an-P$cle-${(max + 1).toString().padLeft(4, '0')}';
}

/// LA MÈRE : le rang DÉFINITIF de la commande dont la référence provisoire est [provisoire]. L'année est celle de la provisoire (l'année de la pièce) ; le rang est le plus grand rang DÉFINITIF de
/// cette année parmi [referencesExistantes], plus un (les provisoires ne comptent pas). `null` si [provisoire] n'en est pas une (une référence définitive ne se réécrit jamais).
String? referenceCommandeDefinitive(String provisoire, Iterable<String> referencesExistantes) {
  final m = _reProvisoire.firstMatch(provisoire);
  if (m == null) return null;
  final an = m.group(1)!;
  var max = 0;
  for (final r in referencesExistantes) {
    final d = _reDefinitive.firstMatch(r);
    if (d != null && d.group(1) == an) {
      final n = int.parse(d.group(2)!);
      if (n > max) max = n;
    }
  }
  return 'BC-$an-${(max + 1).toString().padLeft(4, '0')}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// REJEU À LA MÈRE : UNE VALIDATION NE S'ÉCRIT PAS DIRECTEMENT
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// Le refus nommé d'un rejeu : code, motif, geste.
class RefusRejeuCommande {
  const RefusRejeuCommande(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
}

bool _validee(Map<String, Object?>? c) =>
    c != null && statutsCommandeValides.contains(c['statutCommande']) && '${c['valideePar'] ?? ''}'.isNotEmpty;

/// LA MÈRE, sur une MODIFICATION reçue d'un autre poste (jamais sur le rejeu d'une création, qui est sans effet) : une référence DÉFINITIVE ne se réécrit jamais (règle 1, une pièce émise ne se
/// réécrit pas). Sans cette garde, un poste pourrait poser `BC-2026-9999` et décaler le rang définitif de toutes les commandes suivantes (le rang est le plus grand rang définitif de l'année,
/// plus un). Refus nommé `COMMANDE_REFERENCE_FIGEE`. [avant] : la fiche d'avant ; [apres] : la fiche telle qu'elle serait.
RefusRejeuCommande? refusRejeuReferenceCommande(Map<String, Object?>? avant, Map<String, Object?> apres) {
  if (avant != null && estReferenceCommandeDefinitive(avant['reference']) && '${apres['reference'] ?? ''}' != '${avant['reference']}') {
    return RefusRejeuCommande('COMMANDE_REFERENCE_FIGEE', 'La référence ${avant['reference']} de la commande est définitive : elle ne se réécrit pas (écriture reçue : « ${apres['reference'] ?? ''} »).',
        'Laisser la référence que la mère a attribuée ; une correction passe par une nouvelle commande, l\'ancienne s\'archive (RG-14).');
  }
  return null;
}

/// La MÈRE refait la garde RG-04 sur ce qu'un AUTRE POSTE écrit (un bouton masqué ne protège rien) : un statut « validée », « transmise », « livrée » ou « soldée » (ou un validateur) qui naît
/// d'une écriture directe est REFUSÉ ; la validation d'une commande déjà validée ne se réécrit pas. Seule la mère écrit une validation, par l'application d'une décision signée.
/// [avant] : la fiche d'avant (`null` à la création) ; [apres] : la fiche telle qu'elle serait (fusion de l'existant et de l'écriture).
RefusRejeuCommande? refusRejeuValidationCommande(Map<String, Object?>? avant, Map<String, Object?> apres) {
  final ref = '${apres['reference'] ?? avant?['reference'] ?? ''}';
  if (_validee(avant)) {
    if ('${avant!['valideePar']}' != '${apres['valideePar'] ?? ''}' || '${avant['dateValidation'] ?? ''}' != '${apres['dateValidation'] ?? ''}') {
      return RefusRejeuCommande('COMMANDE_VALIDATION_FIGEE', 'La validation de la commande $ref (${avant['valideePar']}) ne se réécrit pas : elle a été écrite directement par un autre poste.',
          'Laisser la validation telle que la mère l\'a posée ; une commande validée suit son circuit.');
    }
    return null;
  }
  final valide = statutsCommandeValides.contains(apres['statutCommande']) || '${apres['valideePar'] ?? ''}'.isNotEmpty;
  if (valide) {
    return RefusRejeuCommande('COMMANDE_VALIDATION_DIRECTE', 'Commande $ref : une validation écrite directement sur la fiche par un autre poste est REFUSÉE au rejeu (RG-04).',
        'Prendre la décision par le geste « Valider une commande de stock gros » : elle est signée, déposée à la mère, qui l\'applique après avoir refait les contrôles.');
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// DÉCISION SIGNÉE
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// L'identifiant sous lequel une commande se désigne entre postes : son identité de synchronisation (la même partout), à défaut son identifiant local.
String cibleCommande(Map<String, Object?> c) => '${(c['idSync'] ?? '').toString().isNotEmpty ? c['idSync'] : c['id']}';

/// La commande désignée par [cible] (identité de synchronisation ou identifiant local), ou `null`.
Map<String, Object?>? commandeDeLaCible(Iterable<Map<String, Object?>> commandes, String cible) {
  for (final c in commandes) {
    if ('${c['idSync'] ?? ''}' == cible || '${c['id']}' == cible) return c;
  }
  return null;
}

String _codeDuRefus(String motif) => RegExp(r'\(([A-Z_]+)\)').firstMatch(motif)?.group(1) ?? 'VALIDATION_COMMANDE_REFUSEE';

RefusValidation _refus(RefusAchat e) => RefusValidation(_codeDuRefus(e.motif), e.motif, null);

/// Ce que le dépôt rend : un refus nommé, ou la fiche à INSÉRER dans `demandesValidation`.
VerdictDepotValidation commandeDeposerValidation({
  required Map<String, Object?>? commande,
  required String role,
  required String acteur,
  required DateTime maintenant,
  required bool gesteAccorde,
  required String libelleRole,
  required String valideurs,
  required List<Map<String, Object?>> demandes,
  String etiquette = 'F',
}) {
  try {
    validationCommande(commande: commande, jour: _jour(valInstant(maintenant)), agent: acteur, gesteAccorde: gesteAccorde, libelleRole: libelleRole, valideurs: valideurs);
  } on RefusAchat catch (e) {
    return VerdictDepotValidation.refus(_refus(e));
  }
  final cible = cibleCommande(commande!);
  final existante = valDemandeEnAttenteDe(demandes, valFamilleCommandeStock, cible);
  if (existante != null) {
    final age = valAgeDemande(existante, maintenant);
    return VerdictDepotValidation.refus(RefusValidation(
        'DEMANDE_DEJA_DEPOSEE',
        'La validation de la commande ${commande['reference']} est déjà déposée par ${existante['demandePar']}${age == null ? '' : ' (en attente de la mère depuis ${valDureeLisible(age)})'}.',
        'Rien à faire : la mère l\'applique dès qu\'elle est joignable. Le travail courant n\'est pas bloqué.'));
  }
  return VerdictDepotValidation.ok({
    'id': 'DV$etiquette${maintenant.microsecondsSinceEpoch}${demandes.length}',
    'statut': 'actif',
    'famille': valFamilleCommandeStock,
    'cible': cible,
    'libelle': valLibelleCommandeStock,
    'reference': '${commande['reference'] ?? ''}',
    'etat': valEtatDeposee,
    'demandePar': acteur,
    'demandeRole': role,
    'demandeLe': valInstant(maintenant),
  });
}

/// Ce que la mère rend après avoir rejoué la décision : le correctif de la commande à écrire (`null` en cas de refus) et les champs du verdict à poser sur la demande.
class ApplicationValidationCommande {
  const ApplicationValidationCommande({required this.commandeId, required this.patch, required this.champsDemande});
  final Object? commandeId;
  final Map<String, Object?>? patch;
  final Map<String, Object?> champsDemande;
  bool get ok => patch != null;
}

/// LA MÈRE applique une décision « déposée » : le compte signataire existe avec ce rôle (refus nommés `SIGNATAIRE_*`), la commande existe et est en attente de validation, le geste est relu
/// SOUS LE RÔLE DE L'AUTEUR ([gesteDe]), la validation est datée de la SIGNATURE. `null` si la demande n'est pas « déposée » (idempotence). [comptes] null : contrôle du compte non tenu (outil).
ApplicationValidationCommande? commandeAppliquerDemande(
  Map<String, Object?> demande, {
  required DateTime maintenant,
  required Iterable<Map<String, Object?>> commandes,
  required bool Function(String role) gesteDe,
  required String Function(String role) libelleRole,
  required String valideurs,
  Iterable<Map<String, Object?>>? comptes,
}) {
  if (demande['etat'] != valEtatDeposee) return null;
  final signeLe = DateTime.tryParse('${demande['demandeLe']}') ?? maintenant;
  Map<String, Object?> refuse(String code, String motif, String? geste) => {
        'etat': valEtatRefusee,
        'traiteLe': valInstant(maintenant),
        'resultatCode': code,
        'resultatMotif': motif,
        'resultatGeste': geste,
      };
  final refusSignataire = comptes == null ? null : valControleSignataire(demande, comptes, signeLe);
  if (refusSignataire != null) {
    return ApplicationValidationCommande(commandeId: null, patch: null, champsDemande: refuse(refusSignataire.code, refusSignataire.motif, refusSignataire.geste));
  }
  final role = '${demande['demandeRole']}';
  final commande = commandeDeLaCible(commandes, '${demande['cible']}');
  final jour = _jour(signeLe.toLocal().toIso8601String());
  try {
    final patch = validationCommande(
        commande: commande, jour: jour, agent: '${demande['demandePar']}', gesteAccorde: gesteDe(role), libelleRole: libelleRole(role), valideurs: valideurs);
    return ApplicationValidationCommande(commandeId: commande!['id'], patch: patch, champsDemande: {'etat': valEtatAppliquee, 'traiteLe': valInstant(maintenant)});
  } on RefusAchat catch (e) {
    final r = _refus(e);
    return ApplicationValidationCommande(commandeId: null, patch: null, champsDemande: refuse(r.code, r.motif, 'Voir le message du refus.'));
  }
}
