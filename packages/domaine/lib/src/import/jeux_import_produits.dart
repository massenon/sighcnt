// LOT TFIN-2, GROUPE PRODUITS : les prix d'achat par fichier (`tarifs-produits`) et le référentiel produits (`produits-referentiel`).
//
// Port de `prototype_html/assets/js/modules/import.js` (jeux « 4 bis » et 11) ; les vecteurs (`test/vecteurs/import.json`, cas `tp-*`, `pf-*` et section `produits`) sont tirés de l'écran réel de la
// maquette par `prototype_html/build/vecteurs-import.js`.
//
//  * `tarifs-produits` écrit par le MÊME chemin que l'écran « Changer le prix d'achat » (`tarProposerProduit`, famille PRODUIT : RG-02, contrôle d'usage, une proposition en attente par article, provenance
//    `import`). Le prix en vigueur ne bouge jamais à l'import : Oui + droit de décider = version validée d'emblée ; Oui sans ce droit = proposition ; Non (motif) = aucune version ; prix identique = « inchangée ».
//    Une version est immuable : un lot qui en a validé une ne s'annule plus. Un FILEUL ne passe jamais par `ecrire` pour ce jeu (il écrit des versions de prix, famille R) : sa demande d'import vérifiée part à la
//    mère (voie `demandeSeule`, déduite des cibles), qui refait les contrôles sous le rôle de l'auteur ; le Oui d'un fileul vaut proposition.
//  * `produits-referentiel` crée des fiches NEUVES sans stock, avec la version 1 de leur prix d'achat par la MÊME voie que l'écran (création : valide, sans date d'effet). Sur un fileul, la fiche s'écrit chez lui
//    (activité) et la version 1 est LAISSÉE à la mère (reprise au démarrage et à l'arrivée d'une fiche) : une version ne s'écrit jamais chez un fileul.
part of 'jeux_import.dart';

/// Le refus d'une proposition de prix d'achat se range sous la colonne qui le porte (`COLONNE_DU_REFUS_PRODUIT` de la maquette).
const _colonneDuRefusProduit = {
  'MOTIF_REQUIS': 'Motif',
  'DATE_EFFET_REQUISE': 'Date d’effet',
  'DATE_PASSEE': 'Date d’effet',
  'DATE_PASSEE_RESERVEE': 'Date d’effet',
  'TARIF_DEJA_UTILISE': 'Date d’effet',
  'CHANGEMENT_EN_ATTENTE': 'Code article',
  'PRESTATION_INTROUVABLE': 'Code article',
  'PRODUIT_INTROUVABLE': 'Code article',
  'PRIX_ABSENT': 'Prix d’achat',
  'PRIX_ZERO': 'Prix d’achat',
  'PRIX_INVALIDE': 'Prix d’achat',
  'RG02_MARGE': 'Prix d’achat',
};

/// `achatVente(achat, vente)` de la maquette : « 250 », « 60 / vente 90 », « absent ».
String _achatVente(num? achat, num? vente) => achat == null ? 'absent' : nombre(achat) + (vente != null && vente != achat ? ' / vente ${nombre(vente)}' : '');

/// Le contexte de proposition de ce profil. Le droit est celui d'IMPORTER le jeu `tarifs-produits` (`peutProposerProduit({ import: { jeu } })` de la maquette), jamais celui d'éditer « Tarifs et prix ».
ContexteTarif _contexteProduit(PortImport port, ReferentielTarifs h) => ContexteTarif(
      referentiel: h,
      aujourdhui: port.jour,
      role: port.profil.role,
      auteur: port.utilisateur,
      peutProposerProduit: port.profil.droit('tarifs-produits').importer,
      fileul: port.profil.fileul,
      libelles: {...port.profil.libellesRoles, port.profil.role: port.profil.libelleRole},
      pieces: PiecesTarif(factures: port.toutes('factures'), demandesAnalyses: port.toutes('demandesAnalyses'), demandesImagerie: port.toutes('demandesImagerie')),
    );

/// Un article que la prestation de prix ne porte pas encore reçoit sa version 1 de REPRISE AVANT la proposition (`S.assurerTarifProduit` de la maquette : réparation de donnée, pas un geste de l'importateur).
/// [ecrire] : écrit cette reprise au magasin (à l'écriture) ; sinon le référentiel de la vérification la porte virtuellement, sans rien écrire.
ReferentielTarifs _referentielAvecReprise(PortImport port, _V produit, {required bool ecrire}) {
  final h = _referentielPrix(port);
  if (h.parCode['${produit['code']}'] != null) return h;
  final m = tarMigrerProduits([produit], origine: 'reprise');
  if (m.tarifs.isEmpty) return h;
  if (!ecrire) return ReferentielTarifs([...h.tarifs, ...m.tarifs], [...h.versions, ...m.versions]);
  for (final t in m.tarifs) {
    port.inserer('tarifs', t);
  }
  for (final v in m.versions) {
    port.inserer('versionsTarif', v);
  }
  return _referentielPrix(port);
}

DemandeProduit _offreProduit(_V v, _V produit, String? lot, {required bool valider}) {
  final pa = v['prixAchat'] as Map;
  return DemandeProduit(
    code: '${produit['code']}',
    prixAchat: pa['etat'] == 'montant' ? pa['montant'] : null,
    dateEffet: '${v['dateEffet']}',
    motif: v['motif'] as String?,
    source: v['source'] as String?,
    valider: valider,
    importJeu: 'tarifs-produits',
    importLot: lot,
  );
}

/// Les contrôles de la proposition, puis l'écriture : Oui vaut « valider » seulement pour qui décide ; un refus de validation (profil qui ne décide pas, fileul) dégrade le Oui en proposition,
/// jamais en erreur (la maquette rejoue l'essai sans `valider`).
({ResultatTarif<PropositionTarif> resultat, bool valider}) _proposerLigneProduit(PortImport port, ReferentielTarifs h, _V v, _V produit, String? lot, {required bool peutDecider}) {
  final cx = _contexteProduit(port, h);
  final produits = port.toutes('produits');
  var valider = peutDecider && v['valider'] == 'oui';
  var r = tarProposerProduit(cx, _offreProduit(v, produit, lot, valider: valider), produits: produits);
  if (!r.ok && valider && (r.refus!.code == 'VALIDATION_RESERVEE' || r.refus!.code == 'CONFIGURATION_DE_LA_MERE')) {
    valider = false;
    r = tarProposerProduit(cx, _offreProduit(v, produit, lot, valider: false), produits: produits);
  }
  return (resultat: r, valider: valider);
}

List<ProblemeImport> _reglesTarifsProduits(_V v, dynamic ctx0, _V sc, int n) {
  final ctx = ctx0 as Map<String, Object?>;
  final pb = <ProblemeImport>[];
  final ligne = sc['ligne'] as LigneImport;
  final port = ctx['port'] as PortImport;
  final produit = (ctx['produits'] as Map)[_n(v['code'])] as _V?;
  if (produit == null) {
    return [_p('Code article', v['code'], 'ARTICLE_INCONNU', importRefus, 'aucun article « ${v['code']} » au référentiel produits', 'Créez l’article (jeu « Importation du référentiel produits ») ou corrigez le code.')];
  }
  final h = _referentielAvecReprise(port, produit, ecrire: false);
  final p = h.parCode['${produit['code']}'];
  final na = v['prixAchat'] as Map;
  final s = p == null ? null : h.instantane(p, '${v['dateEffet']}');
  final extra = <String, String>{
    'ancien': s != null && s.na != null ? _achatVente(s.na, tarPrixVenteProduit(produit['categorie'], s.vrs)) : (p != null ? 'absent' : 'aucun prix versionné'),
    'nouveau': na['etat'] == 'montant' ? _achatVente(na['montant'] as num, produit['categorie'] == tarCategorieSansMarge ? na['montant'] as num : null) : 'absent',
    'variation': '',
    'decision': '',
  };
  final extras = sc['extras'] as Map<int, String>;
  void dire() => extras[n] = _detailPrix(extra);
  if (s != null && s.na != null && s.na != 0 && na['etat'] == 'montant') extra['variation'] = _variationPrix(s.na!, na['montant'] as num);
  dire();
  // Un NON est la décision de l'importateur : ni version, ni erreur. Son motif est obligatoire.
  if (v['valider'] == 'non') {
    if (v['motif'] == null) {
      pb.add(_p('Motif', '', 'MOTIF_REQUIS', importRefus, 'une ligne « Non » se motive : sans motif, on ne sait pas pourquoi le prix d’achat n’est pas appliqué', 'Saisissez le motif de la ligne $n.'));
    } else {
      ligne.sansEcriture = 'non';
      extra['decision'] = 'Non : non appliquée';
      dire();
      pb.add(_p('Valider (Oui/Non)', 'Non', 'LIGNE_NON_APPLIQUEE', 'info', 'ligne non appliquée sur décision de l’importateur (motif : ${v['motif']})', 'Aucune version n’est créée.'));
    }
    return pb;
  }
  if (na['etat'] == 'nc') {
    pb.add(_p('Prix d’achat', 'NC', 'NC_INTERDIT', importRefus, 'NC n’existe pas pour un prix d’achat (un article n’a pas de colonne assurée)', 'Saisissez le prix d’achat en francs.'));
  } else if (na['etat'] == 'manquant') {
    pb.add(_p('Prix d’achat', '-', 'PRIX_ABSENT', importRefus, 'un tiret n’est pas un zéro, et un prix d’achat absent n’est pas un prix : l’article ne se facturerait pas', 'Saisissez le prix d’achat, ou retirez la ligne.'));
  }
  if (pb.any((x) => x.estRefus)) return pb;
  // LE MÊME CHEMIN QUE L'ÉCRAN : tous les contrôles de la proposition, sans écrire (essai).
  final e = _proposerLigneProduit(port, h, v, produit, null, peutDecider: ctx['peutDecider'] == true);
  final r = e.resultat;
  if (!r.ok && r.refus!.code == 'PRIX_INCHANGE') {
    ligne.sansEcriture = 'inchange';
    extra['decision'] = 'Inchangée';
    dire();
    pb.add(_p('Prix d’achat', '', 'PRIX_INCHANGE', 'info', 'ce prix d’achat est déjà celui en vigueur à cette date : aucune version, la ligne est comptée', 'Rien à faire.'));
    return pb;
  }
  if (!r.ok) {
    final f = r.refus!;
    pb.add(_p(_colonneDuRefusProduit[f.code] ?? 'Prix d’achat', '', f.code, importRefus, f.motif, f.geste));
    return pb;
  }
  if (e.valider) {
    extra['decision'] = 'Oui : version validée à l’import';
  } else if (v['valider'] == 'oui') {
    extra['decision'] = 'Proposition (votre Oui vaut proposition)';
    pb.add(_avert(
        'Valider (Oui/Non)',
        'Oui',
        'OUI_VAUT_PROPOSITION',
        ctx['fileul'] == true && ctx['peutDecider'] == true
            ? 'ce poste est un fileul rattaché : la décision d’un prix est tenue par la mère, le Oui vaut proposition et la décision revient à la Directrice Administrative ou à la Direction (alerte)'
            : 'votre profil ne détient pas le droit de décider un prix : le Oui vaut proposition, la décision revient à la Directrice Administrative ou à la Direction (alerte)',
        'Aucune action : la ligne sera proposée.'));
  } else {
    extra['decision'] = 'Proposition (alerte Oui/Non)';
  }
  dire();
  return pb;
}

/// Un profil qui ne décide pas ne peut déposer qu'UNE proposition par article : une seconde ligne du même article (autre date) serait refusée à l'écriture, et le lot entier avec elle.
List<ProblemeImport> _reglesLotTarifsProduits(List<LigneImport> lignes, dynamic ctx0) {
  final ctx = ctx0 as Map<String, Object?>;
  if (ctx['peutDecider'] == true) return const [];
  final vus = <String, int>{};
  final out = <ProblemeImport>[];
  for (final l in lignes) {
    if (l.sansEcriture != null || l.etat == 'refus') continue;
    final k = _n(l.v['code']);
    if (vus.containsKey(k)) {
      out.add(_p(
          'Code article',
          '',
          'UNE_PROPOSITION_PAR_ARTICLE',
          importRefus,
          'l’article « ${l.v['code']} » porte deux lignes (lignes ${vus[k]} et ${l.n}) : une seule proposition peut attendre une décision par article',
          'Gardez une seule ligne par article, ou faites importer le fichier par un profil qui décide.'));
    } else {
      vus[k] = l.n;
    }
  }
  return out;
}

// --- 4 bis. PRIX D'ACHAT DES PRODUITS ---------------------------------------------------------------------------------------------

final JeuImport jeuTarifsProduits = JeuImport(
  id: 'tarifs-produits',
  ecran: 'imp-tarifs-produits',
  libelle: 'Importation des prix d’achat',
  module: 'M6',
  statut: 'supporte',
  description: 'Prix d’achat des articles du référentiel produits, avec une date d’effet et la décision Oui ou Non : chaque ligne qui change devient une version datée, jamais un écrasement de la fiche.',
  source: 'Fiche du référentiel produits (écran « Référentiel produits ») et inventaire initial (reprise) « Grand Stock » (docs/) ; les prix du fichier font foi, aucun n’est complété par le logiciel.',
  limite: 'Ce jeu ne change jamais le prix en vigueur par lui-même : la ligne devient une proposition soumise à l’alerte Oui/Non de la Directrice Administrative ou de la Direction, sauf si votre profil détient le droit de décider ET que la ligne dit Oui. '
      'RG-02 : le prix de vente d’un médicament est son prix d’achat, il suit sans marge. Une pièce déjà émise garde le prix de sa date. Jamais de quantité : le stock se reprend par le jeu « Importation Grand Stock ». '
      'Un tiret n’est pas un zéro : une ligne sans prix d’achat est refusée.',
  cibles: const ['tarifs', 'versionsTarif'],
  fichierModele: 'modele-import-prix-achat',
  colonnesRetirees: const [
    ColonneRetiree('Quantité', 'ce jeu ne porte jamais de quantité : le stock se reprend par le jeu « Importation Grand Stock »'),
    ColonneRetiree('N° de lot', 'ce jeu ne porte jamais de lot : les lots se reprennent par le jeu « Importation Grand Stock »'),
    ColonneRetiree('Stock gros', 'ce jeu ne porte jamais de stock : il se reprend par le jeu « Importation Grand Stock »'),
    ColonneRetiree('Stock détail', 'ce jeu ne porte jamais de stock : le détail se pose par le jeu « Importation du stock détail initial »'),
    ColonneRetiree('Prix de vente', 'le prix de vente d’un médicament est son prix d’achat (RG-02) et se dérive ; hors médicament il se change au « Référentiel produits »'),
  ],
  colonnes: [
    _oblig('code', 'Code article', 'texte',
        longueurMax: 24,
        exemple: 'PARA500',
        aide: 'Code d’un article connu du référentiel produits (une ligne par article et par date d’effet). Un article inconnu est refusé : il se crée par le jeu « Importation du référentiel produits ».'),
    _oblig('prixAchat', 'Prix d’achat', 'tarif', exemple: 400, aide: 'Montant entier strictement positif en FCFA. Un tiret n’est pas un zéro : une ligne sans prix d’achat est refusée ; NC n’existe pas pour un prix d’achat.'),
    _oblig('dateEffet', 'Date d’effet', 'date',
        exemple: '2027-01-01',
        aide: 'Le prix en vigueur ne change qu’à cette date. Une date passée est refusée (elle se propose à l’écran, avec sa case et son motif) ; une date que la facturation a déjà dépassée l’est aussi.'),
    _oblig('valider', 'Valider (Oui/Non)', 'liste',
        liste: (_) => const [ValeurListe('oui', 'Oui'), ValeurListe('non', 'Non')],
        exemple: 'Oui',
        aide: 'Oui : le prix s’applique (validé d’emblée si votre profil décide, sinon proposition). Non : la ligne n’est pas appliquée, le motif est obligatoire.'),
    _oblig('motif', 'Motif', 'texte', longueurMax: 160, exemple: 'Nouveau tarif du fournisseur', aide: 'Obligatoire pour toute ligne : il se lit à l’historique du prix et à l’alerte de décision.'),
    _col('source', 'Source', 'texte', longueurMax: 160, exemple: 'Facture fournisseur du 01/12/2026'),
  ],
  contexte: (port) => <String, Object?>{
    'produits': {
      for (final x in port.toutes('produits'))
        if (x['statut'] != 'archive') _n(x['code']): x
    },
    'jour': port.jour,
    'peutDecider': tarPeutDecider(port.profil.role),
    'fileul': port.profil.fileul,
    'port': port,
  },
  cle: (v) => ['${_n(v['code'])}@${v['dateEffet']}'],
  existe: (v, ctx) => null,
  regles: _reglesTarifsProduits,
  reglesLot: _reglesLotTarifsProduits,
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    final peutDecider = tarPeutDecider(port.profil.role);
    final produits = ((ctx as Map<String, Object?>)['produits'] as Map);
    for (final l in lignes) {
      final produit = produits[_n(l.v['code'])] as _V;
      // Le référentiel est relu à CHAQUE ligne : la version qu'une ligne vient de poser compte pour la suivante. La reprise d'un article sans prestation de prix précède la proposition.
      final h = _referentielAvecReprise(port, produit, ecrire: true);
      final e = _proposerLigneProduit(port, h, l.v, produit, '${lot['reference']}', peutDecider: peutDecider);
      if (!e.resultat.ok) throw StateError('ligne ${l.n} (${l.v['code']}) : ${e.resultat.refus!.motif}');
      _ecrireProposition(port, e.resultat.valeur!, declarer);
    }
  },
  dependances: _dependancesLotPrix,
  annuler: _annulerLotPrix,
);

// --- 11. RÉFÉRENTIEL PRODUITS (sans quantités ni lots) ----------------------------------------------------------------------------

/// L'article a-t-il servi à un acte (mouvement, lot, stock, pièce de caisse ou ordonnance) ? Un lot de référentiel ne s'annule que tant qu'aucun acte ne s'appuie dessus (`acteSurProduit` de la maquette).
DependanceImport? _acteSurProduit(PortImport port, Object? produitId) {
  final p = port.parId('produits', produitId);
  final nom = p?['designation'] ?? produitId;
  final m = port.actives('mouvements').where((x) => x['produitId'] == produitId).firstOrNull;
  if (m != null) {
    return DependanceImport('MOUVEMENT_POSTERIEUR', 'l’article « $nom » a déjà un mouvement de stock (${m['reference']}, ${m['typeLabel']})',
        'Un article qui a servi ne s’annule plus avec son lot : archivez-le à l’écran Référentiel produits.');
  }
  if (p != null && (_num(p['stock']) > 0 || _num(p['stockGros']) > 0 || _num(p['stockDetail']) > 0)) {
    return DependanceImport('STOCK_PRESENT', 'l’article « ${p['designation']} » porte du stock', 'Régularisez le stock par un inventaire, puis archivez l’article.');
  }
  if (port.actives('lots').any((l) => l['produitId'] == produitId)) {
    return DependanceImport('LOT_RATTACHE', 'l’article « $nom » porte des lots', 'Archivez l’article à l’écran Référentiel produits.');
  }
  final f = port.actives('factures').where((x) => ((x['lignes'] as List?) ?? const []).any((l) => (l as Map)['produitId'] == produitId)).firstOrNull;
  if (f != null) {
    return DependanceImport('PRODUIT_FACTURE', 'l’article « $nom » figure sur la facture ${f['numero']}', 'Une pièce émise ne se réécrit jamais : archivez l’article, il garde son prix sur la pièce.');
  }
  final o = port.actives('ordonnances').where((x) => ((x['medicaments'] as List?) ?? const []).any((l) => (l as Map)['produitId'] == produitId)).firstOrNull;
  if (o != null) {
    return DependanceImport('PRODUIT_PRESCRIT', 'l’article « $nom » figure sur l’ordonnance ${o['numero'] ?? o['reference']}', 'Archivez l’article à l’écran Référentiel produits.');
  }
  return null;
}

final JeuImport jeuProduitsReferentiel = JeuImport(
  id: 'produits-referentiel',
  ecran: 'imp-produits-referentiel',
  libelle: 'Importation du référentiel produits',
  module: 'M6',
  statut: 'supporte',
  description: 'Articles de la clinique : code, désignation, catégorie, unité, prix d’achat, seuil d’alerte. Jamais de quantité ni de lot.',
  source: 'Fiche du référentiel produits (écran « Référentiel produits ») et inventaire initial (reprise) « Grand Stock » (docs/).',
  limite: 'Ce jeu crée des fiches NEUVES, sans stock : les quantités et les lots se reprennent par « Importation Grand Stock », et un fichier qui porte une colonne de quantité ou de lot est refusé. '
      'Il ne modifie jamais un article déjà tenu (RG-02 : le prix de vente d’un médicament est son prix d’achat). Un article sans seuil est signalé « sans seuil », jamais compté à zéro. Un article sans prix d’achat est REFUSÉ (lot T5b) : le seul cas où un article naît sans prix est la reprise d’un stock qui existe déjà (« Importation Grand Stock »).',
  cibles: const ['produits'],
  fichierModele: 'modele-import-referentiel-produits',
  gesteExiste: 'Retirez la ligne : un import ne modifie jamais un article tenu. Corrigez-le à l’écran Référentiel produits.',
  colonnesRetirees: const [
    ColonneRetiree('Quantité', 'un référentiel ne porte jamais de quantité : le stock se reprend par le jeu « Importation Grand Stock »'),
    ColonneRetiree('N° de lot', 'un référentiel ne porte jamais de lot : les lots se reprennent par le jeu « Importation Grand Stock »'),
    ColonneRetiree('Date de péremption', 'un référentiel ne porte jamais de péremption : elle se reprend avec le lot, par le jeu « Importation Grand Stock »'),
    ColonneRetiree('Stock gros', 'un référentiel ne porte jamais de stock : il se reprend par le jeu « Importation Grand Stock »'),
    ColonneRetiree('Stock détail', 'un référentiel ne porte jamais de stock : le détail se pose par le jeu « Importation du stock détail initial »'),
  ],
  colonnes: [
    _oblig('code', 'Code article', 'texte', longueurMax: 24, exemple: 'PARA500', aide: 'Référence unique de l’article.'),
    _oblig('designation', 'Désignation', 'texte', longueurMax: 160, exemple: 'PARACETAMOL 500 MG CP B/100'),
    _oblig('categorie', 'Catégorie', 'liste', liste: (_) => [for (final c in categoriesProduit) ValeurListe(c.id, c.label)], exemple: 'Médicaments'),
    _oblig('unite', 'Unité', 'texte', longueurMax: 30, exemple: 'Boîte'),
    _col('prixAchat', 'Prix d’achat', 'tarif',
        exemple: 350,
        aide:
            'Obligatoire (la ligne sans prix est refusée en nommant l’article) : montant entier strictement positif en FCFA. Une ligne sans prix d’achat (cellule vide, tiret ou zéro) est REFUSÉE en nommant l’article : un tiret n’est pas un zéro. Si le stock de l’article existe déjà, passez par « Importation Grand Stock », qui le crée « à valoriser ». Un médicament se facture à ce prix, sans marge (RG-02).'),
    _col('prixVente', 'Prix de vente', 'entier',
        min: 0, aide: 'Hors médicament seulement. Vide : égal au prix d’achat. Un médicament n’a pas de prix de vente libre : renseigner un prix différent du prix d’achat est refusé.'),
    _col('seuil', 'Seuil d’alerte', 'entier', min: 0, exemple: 20, aide: 'Vide : l’article est signalé « sans seuil », jamais compté à zéro (aucune alerte n’est possible sans seuil).'),
    _col('emplacement', 'Emplacement', 'texte', longueurMax: 60, exemple: 'Rayon A, Casier 3'),
    _col('fournisseur', 'Code fournisseur', 'texte', longueurMax: 24, exemple: 'SOBAPS', aide: 'Code d’un fournisseur connu. Un code inconnu est signalé, jamais refusé.'),
  ],
  contexte: (port) {
    final empl = {for (final x in port.actives('emplacements')) _n(x['code']): true};
    return <String, Object?>{
      'produits': {for (final x in port.toutes('produits')) _n(x['code']): x},
      'fournisseurs': {for (final x in port.actives('fournisseurs')) _n(x['code']): true},
      'emplacements': empl,
      'nbEmplacements': empl.length,
    };
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final p = ((ctx as Map)['produits'] as Map)[_n(v['code'])] as _V?;
    return p != null ? 'l’article « ${p['code']} » existe déjà (${p['designation']})' : null;
  },
  regles: (v, ctx0, sc, n) {
    final ctx = ctx0 as Map<String, Object?>;
    final pb = <ProblemeImport>[];
    final med = v['categorie'] == tarCategorieSansMarge;
    // Le prix d'achat arrive en `tarif` (montant, NC, tiret) : seul un montant strictement positif est un prix. Chaque refus NOMME l'article (code stable, motif, geste).
    final pa = v['prixAchat'] as Map?;
    final num? achat = pa != null && pa['etat'] == 'montant' ? pa['montant'] as num : null;
    if (pa != null && pa['etat'] == 'nc') {
      pb.add(_p('Prix d’achat', 'NC', 'NC_INTERDIT', importRefus, 'NC n’existe pas pour un prix d’achat (article « ${v['code']} »)', 'Saisissez le prix d’achat en francs.'));
    } else if (pa == null || pa['etat'] == 'manquant' || achat == 0) {
      final r = tarRefusPrixAchatAbsent(v['code'], v['designation']);
      pb.add(_p('Prix d’achat', pa == null ? '' : (pa['etat'] == 'manquant' ? '-' : '0'), r.code, importRefus, r.motif, r.geste));
    }
    final pv = v['prixVente'] as num?;
    if (med && pv != null && achat != null && pv != achat) {
      pb.add(_p('Prix de vente', pv, 'RG02_PRIX_DE_VENTE', importRefus, 'RG-02 : un médicament se facture au prix d’achat, sans marge : son prix de vente ne peut pas être libre',
          'Laissez la colonne « Prix de vente » vide : le prix de vente d’un médicament est son prix d’achat. Une exception se valide par la Direction, à l’écran.'));
    }
    if (v['seuil'] == null) {
      pb.add(_avert('Seuil d’alerte', '', 'SANS_SEUIL', 'seuil d’alerte absent : l’article sera signalé « sans seuil », aucune alerte de stock ne le concernera', 'Fixez le seuil à l’écran Référentiel produits.'));
    }
    final f = v['fournisseur'];
    if (f != null && (ctx['fournisseurs'] as Map)[_n(f)] == null) {
      pb.add(_avert('Code fournisseur', f, 'FOURNISSEUR_INCONNU', 'aucun fournisseur « $f » au référentiel', 'Créez le fournisseur (jeu Fournisseurs) ou corrigez le code.'));
    }
    final e = v['emplacement'];
    if (e != null && (ctx['nbEmplacements'] as int) > 0 && (ctx['emplacements'] as Map)[_n(e)] == null) {
      pb.add(_avert('Emplacement', e, 'EMPLACEMENT_INCONNU', 'aucun emplacement « $e » au référentiel des emplacements',
          'Créez l’emplacement (jeu Emplacements) pour que le plan des rayons ne compte pas deux casiers pour un.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    for (final l in lignes) {
      // Le prix d'achat est ICI toujours un montant strictement positif : l'analyse a refusé le fichier sinon (jamais un article créé à zéro par ce jeu).
      final v = l.v;
      final med = v['categorie'] == tarCategorieSansMarge;
      final prix = (v['prixAchat'] as Map)['montant'] as num;
      final fiche = ecrireFiche('produits', {
        'code': v['code'],
        'designation': v['designation'],
        'unite': v['unite'],
        'categorie': v['categorie'],
        'prixAchat': prix,
        'prixVente': (med || v['prixVente'] == null) ? prix : v['prixVente'],
        'cump': prix,
        'seuilAlerte': v['seuil'],
        'stockGros': 0,
        'stockDetail': 0,
        'stock': 0,
        'emplacement': v['emplacement'] ?? '',
        'fournisseur': v['fournisseur'] ?? '',
      });
      // La version 1 du prix d'achat naît avec la fiche, par la MÊME voie que l'écran (création : valide, sans date d'effet). Sur un FILEUL rien d'une version ne s'écrit chez lui (famille R) :
      // la mère la pose (reprise au démarrage et à l'arrivée de la fiche).
      if (port.profil.surFileul) continue;
      final h = _referentielPrix(port);
      final r = tarProposerProduit(_contexteProduit(port, h), tarDemandeCreationProduit(fiche, source: 'Import ${lot['reference']}', importJeu: 'produits-referentiel', importLot: '${lot['reference']}'),
          produits: port.toutes('produits'));
      if (!r.ok) throw StateError('le prix d’achat de « ${fiche['code']} » n’a pas pu être versionné : ${r.refus!.motif}');
      _ecrireProposition(port, r.valeur!, declarer);
    }
  },
  dependances: (lot, port) {
    for (final id in _ecritsDe(lot, 'produits')) {
      final d = _acteSurProduit(port, id);
      if (d != null) return d;
    }
    return null;
  },
);
