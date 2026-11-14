part of 'tarifs.dart';

// LES PRODUITS DANS LE RÉFÉRENTIEL DE PRIX UNIQUE (PRD-TARIFS, lot T5 de la maquette, porté au poste par le lot TFIN) : le MÊME moteur, la famille `PRODUIT`.
//
// Le code de la prestation EST le code de l'article. La colonne « non assuré » d'une version porte le PRIX D'ACHAT (un produit n'a qu'un prix : la colonne assurée vaut `unique`) ; un prix
// de vente propre n'existe que hors médicament et vit sur la version (`prixVente`). RG-02 : le prix de vente d'un MÉDICAMENT est son prix d'achat, jamais une marge ; il se DÉRIVE à la
// lecture, de la catégorie de la fiche et de la version, il ne se saisit pas. Un prix d'achat absent est un `manquant` : l'article ne se facture pas, jamais à zéro.
//
// Port de `data-tarifs.js` (famille PRODUIT) et de `parcours.js` (`prixProduitALaDate`, `evaluerPropositionProduit`, `ecrireVersionProduit`, `creerPrixProduit`, `produitsAValoriser`) ;
// les vecteurs (`test/vecteurs/tarifs_produits.json`) sont tirés de la maquette en marche par `prototype_html/build/vecteurs-tarifs-produits.js`. Fonctions PURES : le jour est fourni.

const String tarFamilleProduit = 'PRODUIT';

/// La catégorie dont le prix de vente EST le prix d'achat (RG-02). Une exception se valide par la Direction.
const String tarCategorieSansMarge = 'medicament';

/// Le prix d'achat d'une version : `null` quand il est absent (un tiret n'est pas un zéro).
num? tarPrixAchatDe(FicheTarif? v) => v != null && v['etatNonAssure'] != 'manquant' && v['prixNonAssure'] != null ? v['prixNonAssure'] as num : null;

/// Le prix de vente DÉRIVÉ (RG-02) : le prix d'achat pour un médicament ; hors médicament, le prix de vente propre de la version, sinon le prix d'achat.
num? tarPrixVenteProduit(Object? categorie, FicheTarif? v) {
  final achat = tarPrixAchatDe(v);
  if (achat == null) return null;
  if (categorie == tarCategorieSansMarge) return achat;
  return v!['prixVente'] != null ? v['prixVente'] as num : achat;
}

/// Le code désigne-t-il un PRODUIT ? (`estProduit` de `evaluerProposition`) : une prestation de la famille PRODUIT, ou la création d'un article. Sinon la proposition passe par [tarProposer],
/// avec l'autorité et les messages des prestations (un code inconnu est « Aucune prestation ne porte le code »).
bool tarEstProduit(ReferentielTarifs h, String code, {bool creation = false}) => creation || _prestationProduit(h, code) != null;

FicheTarif? _prestationProduit(ReferentielTarifs h, Object? code) {
  final p = h.parCode['$code'];
  return p != null && p['famille'] == tarFamilleProduit ? p : null;
}

class PrixProduit {
  const PrixProduit({required this.absent, this.achat, this.vente, this.version, this.dateEffet, this.motif});
  final bool absent;
  final num? achat;
  final num? vente;
  final int? version;
  final String? dateEffet;
  final String? motif;
}

/// L'accesseur daté (`prixProduitALaDate`) : le prix d'achat de la version EN VIGUEUR à la date de la PIÈCE (jamais la fiche, jamais l'horloge au calcul) et le prix de vente dérivé.
/// Un prix d'achat absent est rendu « absent » avec son motif : l'article ne se facture JAMAIS à zéro.
PrixProduit tarPrixProduit(ReferentielTarifs h, FicheTarif? produit, Object? date, {required String aujourdhui}) {
  if (produit == null || produit['code'] == null || '${produit['code']}'.isEmpty) return const PrixProduit(absent: true, motif: 'Produit inconnu.');
  if (h.vide) return const PrixProduit(absent: true, motif: 'Le référentiel de prix n’est pas chargé.');
  final p = _prestationProduit(h, produit['code']);
  if (p == null) return PrixProduit(absent: true, motif: 'Produit absent du référentiel de prix : « ${produit['code']} ».');
  final jour = tarJourDe(date, aujourdhui), v = h.enVigueur('${p['code']}', jour);
  final nom = produit['designation'] ?? produit['code'];
  if (v == null) return PrixProduit(absent: true, motif: 'Aucune version de prix d’achat valide à la date du $jour pour « $nom ».');
  final achat = tarPrixAchatDe(v);
  final rang = ((v['version'] as num?) ?? 0).toInt(), eff = v['dateEffet'] as String?;
  if (achat == null) {
    return PrixProduit(
        absent: true, version: rang, dateEffet: eff, motif: 'Le prix d’achat de « $nom » n’est pas renseigné (à valider) : l’article ne se facture jamais à zéro.');
  }
  return PrixProduit(absent: false, achat: achat, vente: tarPrixVenteProduit(produit['categorie'], v), version: rang, dateEffet: eff);
}

/// Ce que la fiche `produits` doit porter aujourd'hui : le correctif des seuls champs de PRIX qui diffèrent. Un prix absent ne corrige rien (la fiche garde son marquage « à valoriser »).
Map<String, Object?>? tarCorrectifProduit(FicheTarif doc, InstantaneTarif s) {
  final achat = s.na;
  if (achat == null) return null;
  final c = <String, Object?>{};
  final vente = tarPrixVenteProduit(doc['categorie'], s.vrs);
  if (doc['prixAchat'] != achat) c['prixAchat'] = achat;
  if (doc['prixVente'] != vente) c['prixVente'] = vente;
  return c.isEmpty ? null : c;
}

/// La version d'un produit à la reprise d'une fiche existante (ou à la semence) : le prix d'achat TENU AUJOURD'HUI. Un prix absent ou nul n'est jamais un tarif : `manquant`.
FicheTarif tarVersionProduit(FicheTarif pr, int n, String origine, {String? dateEffet, String? motif}) {
  final a = pr['prixAchat'];
  final num? achat = a is num && a > 0 ? a : null;
  final v = _creerVersion('${pr['code']}', n, (na: achat, etatNA: achat == null ? 'manquant' : 'montant', pa: null, etatA: 'unique'), origine: origine, dateEffet: dateEffet, motif: motif);
  final pv = pr['prixVente'];
  if (achat != null && pr['categorie'] != tarCategorieSansMarge && pv is num && pv > 0 && pv != achat) v['prixVente'] = pv;
  if (pr['valorisationProvisoire'] == true && pr['sourceValorisation'] != null) v['source'] = pr['sourceValorisation'];
  return v;
}

/// Les produits actifs deviennent des prestations de la famille PRODUIT, chacune avec sa version 1 (`migrerProduits`). Un produit déjà doté de sa prestation n'est PAS repris.
({List<FicheTarif> tarifs, List<FicheTarif> versions}) tarMigrerProduits(Iterable<FicheTarif> produits, {String origine = 'migration', Set<String> dejaDotes = const {}}) {
  final tarifs = <FicheTarif>[], versions = <FicheTarif>[];
  for (final pr in produits) {
    if (pr['statut'] == 'archive' || pr['code'] == null || '${pr['code']}'.isEmpty || dejaDotes.contains('${pr['code']}')) continue;
    tarifs.add({'id': pr['code'], 'code': pr['code'], 'libelle': pr['designation'] ?? pr['code'], 'famille': tarFamilleProduit, 'statut': 'actif'});
    versions.add(tarVersionProduit(pr, 1, origine));
  }
  return (tarifs: tarifs, versions: versions);
}

/// LES PRODUITS « À VALORISER » : les articles actifs dont AUCUN prix d'achat n'est en vigueur au [jour] (version 1 `manquant`). Une fiche sans identité de prix n'en fait pas partie ;
/// une proposition en attente ne la sort PAS de la liste : seul le Oui, qui met un prix en vigueur, le fait.
List<({FicheTarif produit, bool enAttente})> tarProduitsAValoriser(ReferentielTarifs h, Iterable<FicheTarif> produits, String jour) {
  final out = <({FicheTarif produit, bool enAttente})>[];
  for (final pr in produits) {
    if (pr['statut'] == 'archive') continue;
    final p = _prestationProduit(h, pr['code']);
    if (p == null) continue;
    final v = h.enVigueur('${p['code']}', jour);
    if (v != null && tarPrixAchatDe(v) != null) continue;
    final attente = (h.vers['${p['code']}'] ?? const <FicheTarif>[]).where((x) => x['statut'] == 'propose').length;
    out.add((produit: pr, enAttente: attente > 0));
  }
  return out;
}

/// La demande de changement du prix d'achat d'un produit (ou la création de sa version 1 avec [creation]).
class DemandeProduit {
  const DemandeProduit({
    required this.code,
    this.prixAchat,
    this.prixVente,
    this.dateEffet,
    this.motif,
    this.datePassee = false,
    this.valider = false,
    this.creation = false,
    this.libelle,
    this.source,
    this.importJeu,
    this.importLot,
    this.reception = false,
  });
  final String code;
  final Object? prixAchat;
  final Object? prixVente;
  final String? dateEffet;
  final String? motif;
  final bool datePassee;
  final bool valider;

  /// La création de la fiche pose la version 1 (« depuis l'origine », sans date d'effet) ; un prix absent y est permis (`manquant`).
  final bool creation;
  final String? libelle;
  final String? source;

  /// `tarifs-produits` ou `produits-referentiel` : la proposition naît d'un fichier (autorité = droit d'importer le jeu).
  final String? importJeu;
  final String? importLot;

  /// La proposition naît d'une réception d'achat.
  final bool reception;
  bool get viaImport => importJeu == 'tarifs-produits';
}

String _fcfa(num x) {
  final s = x.toInt().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Tous les contrôles d'une proposition de prix d'achat, SANS RIEN ÉCRIRE (`evaluerProposition` puis `evaluerPropositionProduit`), puis la version à écrire. [produits] : les fiches
/// `produits` (le code d'un article est celui de sa prestation de prix). Un refus se NOMME (code, motif, geste).
ResultatTarif<PropositionTarif> tarProposerProduit(ContexteTarif cx, DemandeProduit o, {required Iterable<FicheTarif> produits}) {
  ResultatTarif<PropositionTarif> non(RefusTarif r) => ResultatTarif.refuse(r);
  if (!o.creation && !cx.peutProposerProduit) {
    return non(o.viaImport
        ? const RefusTarif('PROPOSITION_RESERVEE', 'Proposer un prix d’achat par un fichier revient aux profils qui détiennent le droit d’importer le jeu « Importation des prix d’achat ».',
            'Demander ce droit à l’administrateur (« Rôles & permissions », section Importation).')
        : const RefusTarif('PROPOSITION_RESERVEE', 'Changer le prix d’achat d’un produit se fait au « Référentiel produits », par un profil qui peut modifier cet écran.',
            'Demander le changement au gestionnaire de stock, à la Directrice Administrative ou à l’administrateur.'));
  }
  if (o.valider && !cx.peutDecider) {
    return non(const RefusTarif('VALIDATION_RESERVEE', 'Valider un changement de prix revient à la Direction, à la Directrice Administrative et à l’administrateur : valider n’est pas modifier la fiche.',
        'Enregistrer le changement comme proposition : la décision revient à l’un de ces profils.'));
  }
  if (o.valider && cx.fileul) return non(tarRefusFileul());
  final h = cx.referentiel;
  if (h.vide) return non(const RefusTarif('REFERENTIEL_ABSENT', 'Le référentiel de prix n’est pas chargé.', 'Recharger la page.'));
  final creation = o.creation, code = creation ? o.code.trim() : o.code;
  final p = h.parCode[code];
  if (creation) {
    if (code.isEmpty) return non(const RefusTarif('IDENTITE_INCOMPLETE', 'Un produit porte un code.', 'Renseigner le code de l’article.'));
    if (p != null && p['famille'] != tarFamilleProduit) {
      return non(RefusTarif('CODE_EXISTANT',
          'Le code « $code » est déjà celui d’une prestation tarifée (${p['libelle'] ?? p['code']}) : un article ne peut pas reprendre le code d’une prestation.', 'Choisir un autre code d’article.'));
    }
    if (p != null) {
      return non(RefusTarif('PRIX_DEJA_VERSIONNE', 'Le code « $code » porte déjà un prix d’achat versionné : la création de la fiche ne pose pas une seconde version 1.',
          'Changer le prix d’achat par « Changer le prix d’achat » (date d’effet, motif, Oui ou Non).'));
    }
  } else if (p == null || p['famille'] != tarFamilleProduit) {
    return non(RefusTarif('PRESTATION_INTROUVABLE', 'Aucun produit ne porte le code « ${o.code} » au référentiel de prix.', 'Choisir un produit de la liste.'));
  }
  final fiches = produits.where((x) => x['code'] == code && x['statut'] != 'archive').toList();
  if (fiches.isEmpty) return non(RefusTarif('PRODUIT_INTROUVABLE', 'Aucun produit actif ne porte le code « $code ».', 'Choisir un produit du Référentiel produits.'));
  final pr = fiches.first;
  final brut = o.prixAchat, absent = brut == null || brut == '';
  final double achat = absent ? double.nan : _nombre(brut);
  if (absent && !creation) return non(const RefusTarif('PRIX_ABSENT', 'Le prix d’achat est absent : un prix vide n’est pas un tarif, l’article ne se facturerait pas.', 'Saisir le prix d’achat.'));
  if (!absent && achat == 0) {
    return non(const RefusTarif('PRIX_ZERO', 'Un zéro n’est pas un tarif (arbitrage « plus aucun montant nul ») : un article ne se facture jamais à zéro.',
        'Saisir un prix d’achat strictement positif, ou laisser l’article « à valoriser » (sans prix).'));
  }
  if (!absent && !_entierPositif(achat)) {
    return non(const RefusTarif('PRIX_INVALIDE', 'Le prix d’achat doit être un nombre entier de francs, strictement positif (le boîtier fiscal n’accepte que des montants entiers).', 'Corriger le prix d’achat.'));
  }
  final vb = o.prixVente;
  double? vente = (vb == null || vb == '') ? null : _nombre(vb);
  if (vente != null && !_entierPositif(vente)) {
    return non(const RefusTarif('PRIX_INVALIDE', 'Le prix de vente doit être un nombre entier de francs, strictement positif.', 'Corriger le prix de vente, ou le laisser vide (il vaut alors le prix d’achat).'));
  }
  final med = pr['categorie'] == tarCategorieSansMarge;
  final InstantaneTarif? sActuel = !creation ? h.instantane(p!, o.dateEffet ?? '') : null;
  if (med && vente != null && (absent || vente != achat)) {
    return non(RefusTarif('RG02_MARGE',
        'RG-02 : un médicament se facture au prix d’achat, sans marge : son prix de vente (${_fcfa(vente)}) ne peut pas différer de son prix d’achat${absent ? ' (absent)' : ' (${_fcfa(achat)})'}.',
        'Laisser le prix de vente vide : le prix de vente d’un médicament est son prix d’achat, il se dérive. Une exception se valide par la Direction.'));
  }
  if (!creation && (o.motif ?? '').trim().isEmpty) {
    return non(const RefusTarif('MOTIF_REQUIS', 'Un changement de prix se motive : sans motif, la Direction ne peut pas décider.', 'Saisir le motif du changement.'));
  }
  // La CRÉATION n'a pas de date d'effet : la version 1 vaut « depuis l'origine » (aucun prix antérieur à protéger).
  var passee = false;
  if (!creation) {
    final cd = _controleDateEffet(cx, o.dateEffet, o.datePassee);
    if (cd.refus != null) return non(cd.refus!);
    passee = cd.passee;
  }
  final existantes = h.versionsDe(code);
  if (!creation) {
    final enAttente = existantes.where((v) => v['statut'] == 'propose').firstOrNull;
    if (enAttente != null) {
      return non(RefusTarif('CHANGEMENT_EN_ATTENTE', 'Une proposition est déjà en attente de décision pour « $code » (version ${enAttente['version']}).',
          'La décider (Oui ou Non) ou la retirer avant d’en proposer une autre.'));
    }
    final s = sActuel;
    // Hors médicament, un prix de vente NON renseigné est CONSERVÉ (le prix d'achat change, la décision commerciale du prix de vente n'est pas prise ici).
    if (!med && vente == null && s != null && s.vrs['prixVente'] != null) vente = (s.vrs['prixVente'] as num).toDouble();
    final venteNouvelle = med ? achat : (vente ?? achat);
    final venteActuelle = s != null ? tarPrixVenteProduit(pr['categorie'], s.vrs) : null;
    if (s != null && s.na == achat && venteActuelle == venteNouvelle) {
      return non(const RefusTarif('PRIX_INCHANGE', 'Ce prix d’achat est déjà celui en vigueur à cette date : rien à proposer.', 'Modifier le prix d’achat, ou ne rien changer.'));
    }
    final ids = {for (final x in fiches) if (x['id'] != null) '${x['id']}'};
    final us = tarUsages(p!, o.dateEffet!, cx.pieces, aujourdhui: cx.aujourdhui, produitsIds: ids);
    if (us.isNotEmpty) return non(_refusUsage(code, o.dateEffet!, us, decision: false));
  }
  final rang = existantes.fold<int>(0, (m, v) => ((v['version'] as num?) ?? 0).toInt() > m ? ((v['version'] as num).toInt()) : m) + 1;
  final venteLibre = (!med && vente != null && vente != achat) ? vente : null;
  FicheTarif? identite;
  if (creation) identite = {'id': code, 'code': code, 'libelle': (o.libelle ?? pr['designation'] ?? code).toString().trim(), 'famille': tarFamilleProduit, 'statut': 'actif'};
  final v = <String, Object?>{
    'id': '$code@${creation ? 'origine' : o.dateEffet}@$rang',
    'code': code,
    'version': rang,
    if (!absent) 'prixNonAssure': achat.toInt(),
    'etatAssure': 'unique',
    'motif': (o.motif ?? '').trim(),
    'origine': o.viaImport ? 'import' : (creation ? 'creation' : 'ecran'),
    'statut': 'propose',
    'proposePar': cx.auteur,
    'proposeLe': cx.aujourdhui,
    'proposeRole': cx.role,
  };
  if (!creation) v['dateEffet'] = o.dateEffet;
  if (absent) v['etatNonAssure'] = 'manquant';
  if (venteLibre != null) v['prixVente'] = venteLibre.toInt();
  if ((o.importLot ?? '').isNotEmpty) v['lot'] = o.importLot;
  if ((o.source ?? '').trim().isNotEmpty) v['source'] = o.source!.trim();
  if (passee) v['datePassee'] = true;
  final valide = creation || o.valider;
  if (valide) {
    v['statut'] = 'valide';
    v['decidePar'] = v['proposePar'];
    v['decideLe'] = v['proposeLe'];
    v['roleDecision'] = v['proposeRole'];
    v['motifDecision'] = creation
        ? 'Première version du prix d’achat, posée à la création de l’article${(o.importLot ?? '').isNotEmpty ? ' (import ${o.importLot})' : ''}'
        : (o.viaImport ? 'Validée à l’import ${o.importLot ?? ''}' : 'Validée en un geste à la saisie');
  }
  return ResultatTarif.ok(PropositionTarif(
    version: v,
    identite: identite,
    valideeEnUnGeste: !creation && valide,
    journalAction: creation ? 'création du prix d’achat' : (o.viaImport ? (valide ? 'validation à l’import' : 'proposition à l’import') : (valide ? 'validation en un geste' : 'proposition')),
    journalExtra: {..._extraJournal(v, {'motif': v['motif'], 'role': v['proposeRole']}), 'produit': code},
  ));
}

/// Ce qu'une RÉCEPTION d'achat propose (`proposerPrixReception` de la maquette) : `ouverte` (une proposition de changement du prix d'achat est à écrire), `identique` (rien à proposer),
/// `deja_ouverte` (une proposition attend déjà sa décision : aucune seconde), `refusee` (le moteur refuse, la réception n'est JAMAIS bloquée) ou `sans_objet` (prix reçu absent ou non entier).
class IssuePrixReception {
  const IssuePrixReception(this.etat, {this.code, this.ancien, this.prix, this.dateEffet, this.refus, this.proposition, this.motif});
  final String etat;
  final String? code;

  /// Le prix d'achat en vigueur à la date de réception (`null` : sans prix).
  final num? ancien;
  final num? prix;
  final String? dateEffet;
  final RefusTarif? refus;

  /// La proposition à ÉCRIRE (état `ouverte` seulement) : le moteur n'écrit rien.
  final PropositionTarif? proposition;
  final String? motif;
}

/// UNE RÉCEPTION À UN AUTRE PRIX propose le changement du prix d'achat (lot T5b de la maquette, Direction, 12/11/2026), sans JAMAIS bloquer la réception : le prix reçu est celui de la ligne ;
/// s'il diffère du prix d'achat en vigueur à la DATE DE RÉCEPTION, une PROPOSITION s'ouvre (famille PRODUIT, date d'effet = date de réception, motif « prix constaté à la réception n° … »),
/// soumise au Oui ou Non du circuit commun. UNE SEULE proposition ouverte par produit. Le prix en vigueur, le prix de vente dérivé (RG-02) et les pièces émises ne bougent QU'AU OUI.
/// L'autorité est celle de MODIFIER l'écran des réceptions : l'appelant la pose dans [ContexteTarif.peutProposerProduit]. Le moteur n'écrit rien.
IssuePrixReception tarProposerPrixReception(ContexteTarif cx, {required FicheTarif produit, required Object? prixRecu, Object? date, String reference = '', required Iterable<FicheTarif> produits}) {
  // La maquette lit le prix reçu par `Number(...)` (vide ou nul vaut zéro) et ne met « sans objet » que sur un non-nombre, un négatif ou un décimal : un zéro est REFUSÉ en nommant (PRIX_ZERO) par le
  // moteur commun, jamais ignoré en silence.
  final prix = (prixRecu == null || (prixRecu is String && prixRecu.trim().isEmpty)) ? 0.0 : _nombre(prixRecu);
  if (produit['code'] == null || '${produit['code']}'.isEmpty || !prix.isFinite || prix < 0 || prix.floorToDouble() != prix) return const IssuePrixReception('sans_objet', motif: 'prix de réception non renseigné');
  final code = '${produit['code']}', h = cx.referentiel;
  final jour = tarJourDe(date, cx.aujourdhui);
  final en = tarPrixProduit(h, produit, jour, aujourdhui: cx.aujourdhui);
  if (!en.absent && en.achat == prix) return IssuePrixReception('identique', code: code, prix: prix.toInt());
  final p = _prestationProduit(h, code);
  if (p == null) return IssuePrixReception('sans_objet', code: code, motif: 'produit sans prix versionné');
  final attente = h.versionsDe(code).where((v) => v['statut'] == 'propose').firstOrNull;
  if (attente != null) return IssuePrixReception('deja_ouverte', code: code, prix: attente['prixNonAssure'] as num?);
  final ref = reference.trim();
  final passee = jour.compareTo(cx.aujourdhui) < 0;
  final r = tarProposerProduit(
      cx,
      DemandeProduit(
          code: code,
          prixAchat: prix.toInt(),
          dateEffet: jour,
          datePassee: passee,
          motif: 'prix constaté à la réception n° $ref',
          source: 'Réception $ref',
          reception: true),
      produits: produits);
  if (!r.ok) return IssuePrixReception('refusee', code: code, refus: r.refus);
  return IssuePrixReception('ouverte', code: code, ancien: en.absent ? null : en.achat, prix: prix.toInt(), dateEffet: jour, proposition: r.valeur);
}

/// Le refus d'un article créé SANS prix d'achat (`PR.refusPrixAchatAbsent`, lot T5b de la maquette) : code, motif, geste. Un tiret n'est pas un zéro, et zéro n'est pas un prix : l'article ne se
/// crée pas. Le seul cas où un article naît sans prix est la reprise du Grand Stock (le stock existe déjà), qui le marque « à valoriser ».
RefusTarif tarRefusPrixAchatAbsent(Object? code, Object? designation) {
  final nom = [code, designation].where((x) => x != null && '$x'.isNotEmpty).join(' : ');
  return RefusTarif('PRIX_ACHAT_ABSENT', 'le prix d’achat de l’article « $nom » n’est pas renseigné (absent, tiret ou nul) : un article sans prix d’achat ne se crée pas',
      'Renseignez son prix d’achat en FCFA. Si le stock existe déjà, passez par « Importation Grand Stock » : l’article y est créé « à valoriser », sans prix facturable, jusqu’à la décision d’un premier prix.');
}

/// Le motif de la version 1 posée à la CRÉATION d'un article (`creerPrixProduit` de la maquette) : un article sans prix d'achat naît « à valoriser ».
String tarMotifCreationProduit(num? achat) => achat == null ? 'Article créé sans prix d’achat : à valoriser' : 'Création de l’article';

/// La demande que la CRÉATION d'une fiche produit pose (`creerPrixProduit`) : le prix d'achat de la fiche (absent ou nul : `manquant`), son prix de vente propre hors médicament s'il diffère
/// du prix d'achat. La fiche porte déjà ce prix : la version 1 le DIT, elle ne le décide pas.
DemandeProduit tarDemandeCreationProduit(FicheTarif produit, {String? motif, String? source, String? importJeu, String? importLot}) {
  final a = produit['prixAchat'];
  final num? achat = a is num && a > 0 ? a : null;
  final pv = produit['prixVente'];
  return DemandeProduit(
    code: '${produit['code']}',
    prixAchat: achat,
    prixVente: (achat != null && produit['categorie'] != tarCategorieSansMarge && pv is num && pv > 0 && pv != achat) ? pv : null,
    creation: true,
    libelle: '${produit['designation'] ?? produit['code']}',
    motif: motif ?? tarMotifCreationProduit(achat),
    source: source,
    importJeu: importJeu,
    importLot: importLot,
  );
}

/// LA GARDE RG-02 DU MAGASIN (`garder('produits')` de la maquette, partie RG-02) : un médicament ne naît jamais avec une marge, et une fiche ne le devient pas par une modification. Tenue AU
/// MOTEUR, d'où que vienne l'écriture : masquer un champ ne protège rien. Rend le motif du refus (nommé) ou `null`. Le prix d'achat et le prix de vente de la fiche se règlent d'ailleurs
/// à l'écran (`transformerProduit` aligne la vente sur l'achat d'un médicament) ; la garde tient quand l'écran ne le fait pas (import, outil, synchronisation d'un autre poste).
const String tarMessageRg02 =
    'RG-02 : un médicament se facture au prix d’achat, sans marge : son prix de vente ne peut pas être libre. Le prix de vente d’un médicament EST son prix d’achat ; une exception se valide par la Direction.';

String? tarGardeProduitRg02(String operation, FicheTarif apres, FicheTarif? avant) {
  if (operation != 'inserer' && operation != 'modifier') return null;
  if (apres['categorie'] != tarCategorieSansMarge) return null;
  // Une modification qui ne touche NI le prix d'achat NI le prix de vente (un mouvement de stock, un seuil) passe : la garde juge le PRIX, pas l'historique de la fiche.
  if (operation == 'modifier' && avant != null && _egal(avant['prixAchat'], apres['prixAchat']) && _egal(avant['prixVente'], apres['prixVente'])) return null;
  final a = apres['prixAchat'], v = apres['prixVente'];
  if (a != null && v != null && v != a) return '$tarMessageRg02 (${apres['code']} : achat $a, vente $v)';
  return null;
}
