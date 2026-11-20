// LOT 8B, GROUPE PRIX : les tarifs et prix de prestations, et le catalogue de l'imagerie.
//
// Port de `prototype_html/assets/js/modules/import.js` (jeux 4 et 13) ; les vecteurs (`test/vecteurs/import.json`, cas `ta-*`, `ci-*` et section `prix`) sont tirés de l'écran réel de la
// maquette par `prototype_html/build/vecteurs-import.js`. Le jeu `tarifs` écrit par le MÊME chemin que l'écran « Tarifs et prix » (`tarProposer`, contrôles, journal) : pas une seconde
// vérification. Le prix en vigueur ne bouge jamais à l'import : Oui + droit de décider = version validée d'emblée ; Oui sans ce droit ou vide = proposition ; Non (motif) = aucune version ;
// prix identique à celui en vigueur à la date = « inchangée ». Une version de prix est immuable : un lot validé ne s'annule plus (il se remplace par une nouvelle version, RG-14).
//
// Un FILEUL ne passe jamais par `ecrire` pour ce jeu : il dépose UNE demande par ligne (`propositionsTarif`, famille B) que la mère applique après avoir refait les contrôles sous le
// rôle de l'auteur (voie `VoieImportFileul.demandeParLigne`).
part of 'jeux_import.dart';

const _famillesPrix = <List<String>>[
  ['CONSULTATION', 'Consultations'],
  ['ACTE', 'Actes'],
  ['HOSPITALISATION', 'Hospitalisation'],
  ['AMI', 'Actes médico-infirmiers'],
  ['GYNECO', 'Gynéco-obstétrique et kits'],
  ['CERTIFICAT', 'Certificats et attestations'],
  ['LABO', 'Analyses de laboratoire'],
  ['IMAGERIE', 'Imagerie médicale'],
];
const _couverturesPrix = [ValeurListe('toutes', 'Toutes compagnies'), ValeurListe('sos', 'SOS seule'), ValeurListe('non', 'Non couvert')];

Object _assurableDe(String couverture) => switch (couverture) { 'toutes' => true, 'sos' => 'sos', _ => false };

/// Le refus d'une proposition se range sous la colonne qui le porte (`COLONNE_DU_REFUS` de la maquette).
const _colonneDuRefusPrix = {
  'MOTIF_REQUIS': 'Motif',
  'DATE_EFFET_REQUISE': 'Date d’effet',
  'DATE_PASSEE': 'Date d’effet',
  'DATE_PASSEE_RESERVEE': 'Date d’effet',
  'TARIF_DEJA_UTILISE': 'Date d’effet',
  'CHANGEMENT_EN_ATTENTE': 'Code',
  'PRESTATION_INTROUVABLE': 'Code',
  'CODE_EXISTANT': 'Code',
  'IDENTITE_INCOMPLETE': 'Désignation',
  'PRIX_ABSENT': 'Prix non assuré',
  'PRIX_INVALIDE': 'Prix non assuré',
};

String _jsNombre(double x) => x == x.truncateToDouble() ? x.toInt().toString() : x.toString();

/// `pourcent(avant, apres)` de la maquette : « 10 », « 12.5 » (une décimale, `Math.round`), vide si le prix de départ est nul.
String _variationPrix(num avant, num apres) => avant != 0 ? '${_jsNombre(arrondiJs((apres - avant) / avant * 1000) / 10)} %' : '';

/// `prixAffiche(na, etatA, pa)` : « 5 000 / 3 000 », « 4 000 / unique », « 8 000 / NC », « 4 200 / absent ».
String _prixAffiche(num? na, String etatA, num? pa) {
  final a = etatA == 'montant' ? nombre(pa) : (etatA == 'nc' ? 'NC' : (etatA == 'unique' ? 'unique' : 'absent'));
  return '${na == null ? 'absent' : nombre(na)} / $a';
}

/// Le détail d'une ligne de prix tel que la vérification le montre (colonnes Ancien, Nouveau, Variation, Décision de la maquette, en un seul texte).
String _detailPrix(Map<String, String> x) => [
      'Ancien : ${x['ancien']}',
      'nouveau : ${x['nouveau']}',
      if ((x['variation'] ?? '').isNotEmpty) 'variation : ${x['variation']}',
      'décision : ${x['decision']}',
    ].join(' ; ');

/// Le contexte de proposition de ce profil, sur le référentiel [h]. Le droit est celui d'IMPORTER le jeu `tarifs`, non celui d'éditer l'écran « Tarifs et prix » (le gestionnaire de stock importe
/// des prix sans pouvoir éditer cet écran) ; ce que l'import peut devenir (proposition, ou version validée par un profil qui décide) reste réglé par les mêmes fonctions.
ContexteTarif _contexteProposition(PortImport port, ReferentielTarifs h) => ContexteTarif(
      referentiel: h,
      aujourdhui: port.jour,
      role: port.profil.role,
      auteur: port.utilisateur,
      peutEditerEcran: port.profil.droit('tarifs').importer,
      fileul: port.profil.fileul,
      libelles: {...port.profil.libellesRoles, port.profil.role: port.profil.libelleRole},
      pieces: PiecesTarif(factures: port.toutes('factures'), demandesAnalyses: port.toutes('demandesAnalyses'), demandesImagerie: port.toutes('demandesImagerie')),
    );

ReferentielTarifs _referentielPrix(PortImport port) => ReferentielTarifs(port.toutes('tarifs'), port.toutes('versionsTarif'));

/// Ce que la ligne propose, dans la forme que `tarProposer` attend (`offreDeLigne` de la maquette). [lot] : la référence du lot (vide à l'analyse).
DemandeProposition offreDeLignePrix(_V v, ReferentielTarifs h, String? lot, {required bool valider}) {
  final code = '${v['code']}';
  final p = h.parCode[code];
  final na = v['prixNonAssure'] as Map, pa = v['prixAssure'] as Map;
  final etatA = '${pa['etat']}';
  Map<String, Object?>? creation;
  Object? assurable;
  if (p == null) {
    creation = {
      'libelle': v['designation'],
      'famille': v['famille'],
      if (v['secteur'] != null) 'secteur': v['secteur'],
      if (v['source'] != null) 'source': v['source'],
    };
    if (v['couverture'] != null) {
      assurable = _assurableDe('${v['couverture']}');
    } else if (etatA == 'nc') {
      assurable = false;
    }
  }
  return DemandeProposition(
    code: code,
    prixNonAssure: na['etat'] == 'montant' ? na['montant'] : null,
    etatAssure: etatA,
    prixAssure: etatA == 'montant' ? pa['montant'] : null,
    dateEffet: '${v['dateEffet']}',
    motif: v['motif'] as String?,
    source: v['source'] as String?,
    valider: valider,
    creation: creation,
    assurable: assurable,
    importJeu: 'tarifs',
    importLot: lot,
  );
}

/// Les contrôles de la proposition : Oui vaut « valider » seulement pour qui décide ; un refus de validation (profil qui ne décide pas, fileul) dégrade le Oui en proposition,
/// jamais en erreur (la maquette rejoue l'essai sans `valider`).
({ResultatTarif<PropositionTarif> resultat, bool valider}) proposerLignePrix(PortImport port, ReferentielTarifs h, _V v, String? lot, {required bool peutDecider}) {
  final cx = _contexteProposition(port, h);
  var valider = peutDecider && v['valider'] == 'oui';
  var r = tarProposer(cx, offreDeLignePrix(v, h, lot, valider: valider));
  if (!r.ok && valider && (r.refus!.code == 'VALIDATION_RESERVEE' || r.refus!.code == 'CONFIGURATION_DE_LA_MERE')) {
    valider = false;
    r = tarProposer(cx, offreDeLignePrix(v, h, lot, valider: false));
  }
  return (resultat: r, valider: valider);
}

List<ProblemeImport> _reglesTarifs(_V v, dynamic ctx0, _V sc, int n) {
  final ctx = ctx0 as Map<String, Object?>;
  final pb = <ProblemeImport>[];
  final ligne = sc['ligne'] as LigneImport;
  final h = ctx['h'] as ReferentielTarifs;
  if (h.vide) {
    return [_p('Code', v['code'], 'REFERENTIEL_ABSENT', importRefus, 'le référentiel de prix n’est pas chargé', 'Rechargez la page.')];
  }
  final code = '${v['code']}';
  final p = h.parCode[code];
  final na = v['prixNonAssure'] as Map, pa = v['prixAssure'] as Map;
  if (p != null && p['famille'] == 'PRODUIT') {
    return [
      _p(
          'Code',
          v['code'],
          'CODE_PRODUIT',
          importRefus,
          'le code « $code » est celui d’un produit : son prix d’achat se change par le jeu « Importation des prix d’achat », jamais par les prix de prestations',
          'Placez cette ligne dans le fichier du jeu « Importation des prix d’achat ».')
    ];
  }
  final s = p == null ? null : h.instantane(p, '${v['dateEffet']}');
  final extra = <String, String>{
    'ancien': s != null ? _prixAffiche(s.na, s.etatAssure, s.pa) : 'nouvelle prestation',
    'nouveau': _prixAffiche(na['etat'] == 'montant' ? na['montant'] as num : null, '${pa['etat']}', pa['montant'] as num?),
    'variation': '',
    'decision': '',
  };
  final extras = sc['extras'] as Map<int, String>;
  void dire() => extras[n] = _detailPrix(extra);
  if (s != null && na['etat'] == 'montant' && s.na != null && s.na != 0) {
    extra['variation'] = _variationPrix(s.na!, na['montant'] as num);
    if (pa['etat'] == 'montant' && s.etatAssure == 'montant' && s.pa != null && s.pa != 0 && s.pa != pa['montant']) {
      extra['variation'] = '${extra['variation']} (assuré ${_variationPrix(s.pa!, pa['montant'] as num)})';
    }
  }
  // Un NON est la décision de l'importateur : ni version, ni erreur. Son motif est obligatoire (il se lit au rapport et au lot).
  if (v['valider'] == 'non') {
    if (v['motif'] == null) {
      pb.add(_p('Motif', '', 'MOTIF_REQUIS', importRefus, 'une ligne « Non » se motive : sans motif, on ne sait pas pourquoi le prix n’est pas appliqué', 'Saisissez le motif de la ligne $n.'));
    } else {
      ligne.sansEcriture = 'non';
      extra['decision'] = 'Non : non appliquée';
      dire();
      pb.add(_p('Valider (Oui/Non)', 'Non', 'LIGNE_NON_APPLIQUEE', 'info', 'ligne non appliquée sur décision de l’importateur (motif : ${v['motif']})', 'Aucune version n’est créée.'));
    }
    return pb;
  }
  if (na['etat'] == 'nc') {
    pb.add(_p('Prix non assuré', 'NC', 'NC_INTERDIT', importRefus, 'NC n’a de sens que dans la colonne assurée', 'Saisissez le prix de guichet en francs.'));
  } else if (na['etat'] == 'manquant') {
    pb.add(_p('Prix non assuré', '-', 'PRIX_ABSENT', importRefus, 'un tiret n’est pas un zéro, et un prix non assuré absent n’est pas un tarif : la ligne ne se facturerait pas',
        'Saisissez le prix non assuré, ou retirez la ligne.'));
  } else if (pa['etat'] == 'manquant') {
    pb.add(_avert('Prix assuré', '-', 'PRIX_MANQUANT', 'prix assuré manquant : la ligne ne se facturera pas aux assurés (un tiret n’est pas un zéro)',
        'Saisissez le prix assuré dès qu’il est arrêté, ou NC si aucune compagnie ne couvre la prestation.'));
  }
  if (pb.any((x) => x.estRefus)) return pb;
  if (s != null &&
      na['etat'] == 'montant' &&
      pa['etat'] == 'montant' &&
      s.etatAssure == 'montant' &&
      na['montant'] == s.pa &&
      pa['montant'] == s.na &&
      s.pa != s.na) {
    pb.add(_avert('Prix assuré', pa['montant'], 'COLONNES_INVERSEES',
        'les deux colonnes paraissent inversées par rapport au prix en vigueur (non assuré ${nombre(s.na)}, assuré ${nombre(s.pa)}) : le fichier fait foi, rien n’est corrigé',
        'Vérifiez l’orientation des colonnes avant de confirmer.'));
  }
  if (p != null) {
    final libelle = '${p['libelle'] ?? ''}';
    if (v['designation'] != null && libelle.isNotEmpty && _n(v['designation']) != _n(libelle)) {
      pb.add(_avert('Désignation', v['designation'], 'IDENTITE_DIFFERENTE', 'la désignation du fichier diffère de celle de la fiche : elle n’est pas appliquée (un import ne modifie pas l’identité d’une prestation)',
          'Modifiez le libellé à l’écran « Tarifs et prix ».'));
    } else if (v['famille'] != null && p['famille'] != null && v['famille'] != p['famille']) {
      pb.add(_avert('Famille', v['famille'], 'IDENTITE_DIFFERENTE', 'la famille du fichier diffère de celle de la fiche : elle n’est pas appliquée', 'Modifiez la fiche à l’écran « Tarifs et prix ».'));
    } else if (v['couverture'] != null) {
      final a = _assurableDe('${v['couverture']}');
      final tenue = p['assurable'];
      if (a != tenue && !(a == true && tenue == null)) {
        pb.add(_avert('Couverture', v['couverture'], 'IDENTITE_DIFFERENTE', 'la couverture du fichier diffère de celle de la fiche : elle n’est pas appliquée', 'Modifiez la fiche à l’écran « Tarifs et prix ».'));
      }
    }
  } else if (v['designation'] == null) {
    pb.add(_p('Désignation', '', 'IDENTITE_INCOMPLETE', importRefus, 'le code « $code » est inconnu : une nouvelle prestation porte une désignation', 'Renseignez la désignation et la famille, ou corrigez le code.'));
  } else if (v['famille'] == null) {
    pb.add(_p('Famille', '', 'IDENTITE_INCOMPLETE', importRefus, 'le code « $code » est inconnu : une nouvelle prestation porte une famille', 'Renseignez la famille, ou corrigez le code.'));
  }
  if (pb.any((x) => x.estRefus)) return pb;
  // LE MÊME CHEMIN QUE L'ÉCRAN : tous les contrôles de la proposition, sans écrire (essai).
  final e = proposerLignePrix(ctx['port'] as PortImport, h, v, null, peutDecider: ctx['peutDecider'] == true);
  final r = e.resultat;
  if (!r.ok && r.refus!.code == 'PRIX_INCHANGE') {
    ligne.sansEcriture = 'inchange';
    extra['decision'] = 'Inchangée';
    dire();
    pb.add(_p('Prix non assuré', '', 'PRIX_INCHANGE', 'info', 'ce prix est déjà celui en vigueur à cette date : aucune version, la ligne est comptée', 'Rien à faire.'));
    return pb;
  }
  if (!r.ok) {
    final f = r.refus!;
    pb.add(_p(_colonneDuRefusPrix[f.code] ?? 'Prix non assuré', '', f.code, importRefus, f.motif, f.geste));
    return pb;
  }
  if (p == null) {
    extra['decision'] = e.valider ? 'Oui : prestation créée, version 1 validée' : 'Prestation créée, version 1 proposée (alerte)';
  } else if (e.valider) {
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

/// Écrit la version (et l'identité d'une prestation créée) d'une proposition recevable, avec sa ligne de journal (RG-12).
void _ecrireProposition(PortImport port, PropositionTarif prop, DeclarerFiche declarer) {
  final code = '${prop.version['code']}';
  if (prop.identite != null) {
    final id = port.inserer('tarifs', prop.identite!);
    declarer('tarifs', id['id']);
  }
  port.journaliser('Changement de prix : ${prop.journalAction}', 'CFG', 'prix', code, null, prop.journalExtra);
  final v = port.inserer('versionsTarif', prop.version);
  declarer('versionsTarif', v['id']);
}

/// Les deux jeux de PRIX s'annulent de la même façon : on RETIRE les propositions du lot, on archive les identités qu'il a créées ; une version déjà validée ne s'efface pas.
DependanceImport? _dependancesLotPrix(FicheImport lot, PortImport port) {
  if ((lot['ecrits'] as List).cast<Map>().any((e) => e['collection'] == 'actes')) {
    return const DependanceImport('LOT_ANCIEN', 'ce lot a écrit l’ancienne liste des actes, devenue une projection de lecture du référentiel de prix',
        'Corrigez le prix à l’écran « Tarifs et prix » : une version se remplace par une nouvelle version.');
  }
  for (final id in _ecritsDe(lot, 'versionsTarif')) {
    final v = port.parId('versionsTarif', id);
    if (v != null && v['statut'] == 'valide') {
      return DependanceImport('VERSION_DEJA_VALIDEE', 'la version ${v['id']} est déjà validée : une décision se remplace par une nouvelle version, elle ne s’efface pas',
          'Proposez une nouvelle version à l’écran « Tarifs et prix » (ou « Changer le prix d’achat » pour un produit) ; seules les propositions encore en attente se retirent avec leur lot.');
    }
  }
  return null;
}

ResultatAnnulationImport _annulerLotPrix(FicheImport lot, String? motif, PortImport port) {
  var retirees = 0, archivees = 0;
  final raison = 'Lot ${lot['reference']} annulé${motif != null && motif.isNotEmpty ? ' : $motif' : ''}';
  for (final id in _ecritsDe(lot, 'versionsTarif')) {
    final v = port.parId('versionsTarif', id);
    if (v == null || v['statut'] != 'propose') continue;
    final cx = _contexteProposition(port, _referentielPrix(port));
    final r = tarRetirer(cx, '$id', raison);
    if (!r.ok) return ResultatAnnulationImport.refus(r.refus!.code, r.refus!.motif, r.refus!.geste);
    final d = r.valeur!;
    port.journaliser('Changement de prix : ${d.journalAction}', 'CFG', 'prix', '${v['code']}', null, d.journalExtra);
    port.mettreAJour('versionsTarif', id, d.patch);
    retirees++;
  }
  for (final id in _ecritsDe(lot, 'tarifs')) {
    final vivantes = port.toutes('versionsTarif').where((x) => x['code'] == id && (x['statut'] == 'propose' || x['statut'] == 'valide'));
    if (vivantes.isEmpty && port.archiver('tarifs', id, 'Annulation du lot ${lot['reference']}')) archivees++;
  }
  return ResultatAnnulationImport.ok(retirees + archivees);
}

// --- 4. TARIFS ET PRIX ----------------------------------------------------------------------------------------------------------------

final JeuImport jeuTarifs = JeuImport(
  id: 'tarifs',
  ecran: 'imp-actes',
  libelle: 'Importation des tarifs et prix',
  module: 'IMP',
  statut: 'supporte',
  description:
      'Prix des prestations (consultations, actes, soins, analyses, imagerie, certificats) à deux colonnes, avec les trois états de la colonne assurée, une date d’effet et la décision Oui ou Non : chaque ligne qui change devient une version datée, jamais un écrasement.',
  source: 'Six grilles tarifaires imprimées et « Répartition des activités » (docs/) ; les prix du fichier font foi, aucun n’est complété par le logiciel.',
  limite:
      'Un import de prix ne change jamais le prix en vigueur par lui-même : la ligne devient une proposition soumise à l’alerte Oui/Non de la Directrice Administrative ou de la Direction, sauf si votre profil détient le droit de décider ET que la ligne dit Oui.',
  cibles: const ['tarifs', 'versionsTarif'],
  fichierModele: 'modele-import-tarifs',
  colonnes: [
    _oblig('code', 'Code', 'texte',
        longueurMax: 30,
        exemple: 'MG01',
        aide:
            'Code d’une prestation connue (changement de prix) ou d’une prestation nouvelle (création : désignation et famille obligatoires). Un code d’alias est reconnu.'),
    _col('designation', 'Désignation', 'texte',
        longueurMax: 160,
        exemple: 'Consultation généraliste',
        aide: 'Libellé de facturation. Obligatoire pour créer une prestation ; jamais appliqué à une prestation connue (un import ne modifie pas l’identité d’une fiche tenue).'),
    _col('famille', 'Famille', 'liste', liste: (_) => [for (final f in _famillesPrix) ValeurListe(f[0], f[1])], exemple: 'Actes', aide: 'Obligatoire pour créer une prestation.'),
    _col('secteur', 'Secteur', 'liste', liste: (ctx) => [for (final s in ((ctx as Map)['secteurs'] as List)) ValeurListe('$s')], exemple: 'Médecine générale'),
    _oblig('prixNonAssure', 'Prix non assuré', 'tarif',
        exemple: 5000, aide: 'Montant entier strictement positif en FCFA. NC n’existe pas dans cette colonne ; un tiret n’est pas un zéro : une ligne sans prix non assuré est refusée.'),
    _oblig('prixAssure', 'Prix assuré', 'tarif',
        unique: true,
        exemple: 3000,
        aide:
            'Montant, NC (aucune compagnie ne couvre l’acte : l’assuré paie le prix non assuré), UNIQUE (prix unique : la colonne assurée vaut la colonne non assurée) ou un tiret (valeur manquante, la ligne ne se facture pas aux assurés).'),
    _col('couverture', 'Couverture', 'liste',
        liste: (_) => _couverturesPrix,
        exemple: 'Toutes compagnies',
        aide: 'Pour une création seulement ; vide : toutes les compagnies (ou non couvert si le prix assuré est NC).'),
    _oblig('dateEffet', 'Date d’effet', 'date',
        exemple: '2027-01-01', aide: 'Obligatoire : le prix en vigueur ne change qu’à cette date. Une date passée est refusée (elle se propose à l’écran, avec sa case et son motif).'),
    _col('valider', 'Valider (Oui/Non)', 'liste',
        liste: (_) => const [ValeurListe('oui', 'Oui'), ValeurListe('non', 'Non')],
        exemple: 'Oui',
        aide:
            'Oui : le prix s’applique (validé d’emblée si votre profil décide, sinon proposition). Non : la ligne n’est pas appliquée, le motif est obligatoire. Vide : proposition.'),
    _col('motif', 'Motif', 'texte', longueurMax: 160, exemple: 'Nouvelle grille tarifaire', aide: 'Obligatoire pour toute ligne qui change un prix et pour tout Non.'),
    _col('source', 'Source', 'texte', longueurMax: 160, exemple: 'Grille du 01/12/2026'),
  ],
  contexte: (port) {
    final h = _referentielPrix(port);
    final sec = <String>{
      if (!h.vide)
        for (final p in h.tarifs)
          if (p['statut'] != 'archive' && p['secteur'] != null && '${p['secteur']}'.isNotEmpty) '${p['secteur']}',
      ...importSecteursActes,
    };
    return <String, Object?>{'h': h, 'secteurs': sec.toList()..sort(), 'jour': port.jour, 'peutDecider': tarPeutDecider(port.profil.role), 'fileul': port.profil.fileul, 'port': port};
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) => null,
  regles: _reglesTarifs,
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    final peutDecider = tarPeutDecider(port.profil.role);
    for (final l in lignes) {
      // Le référentiel est relu à CHAQUE ligne : la version qu'une ligne vient de poser compte pour la suivante (une proposition en attente, un rang).
      final h = _referentielPrix(port);
      final e = proposerLignePrix(port, h, l.v, '${lot['reference']}', peutDecider: peutDecider);
      if (!e.resultat.ok) throw StateError('ligne ${l.n} (${l.v['code']}) : ${e.resultat.refus!.motif}');
      _ecrireProposition(port, e.resultat.valeur!, declarer);
    }
  },
  dependances: _dependancesLotPrix,
  annuler: _annulerLotPrix,
);

// --- 13. CATALOGUE DE L'IMAGERIE ---------------------------------------------------------------------------------------------------

final JeuImport jeuCatalogueImagerie = JeuImport(
  id: 'catalogue-imagerie',
  ecran: 'imp-catalogue-imagerie',
  libelle: 'Importation du catalogue de l’imagerie',
  module: 'CFG',
  statut: 'supporte',
  description: 'Examens d’imagerie : code, libellé, modalité (échographie, radiographie, mammographie, scanner, IRM), voie d’abord, code tarifaire.',
  source: 'Écran « Catalogue de l’imagerie » : l’examen est un acte facturable, rangé dans le tableau de sa modalité.',
  limite:
      'PROPOSITION À VALIDER : un examen importé naît « à valider » et le dit ; il ne porte AUCUNE variable de compte rendu (elles se définissent au catalogue). Le prix ne s’importe pas : sans tarif en vigueur, l’examen est refusé à la prescription en le nommant.',
  cibles: const ['examensImagerie'],
  fichierModele: 'modele-import-catalogue-imagerie',
  gesteExiste: 'Retirez la ligne : un examen tenu se modifie à l’écran « Catalogue de l’imagerie ».',
  colonnes: [
    _oblig('code', 'Code examen', 'texte',
        motif: RegExp(r'^[A-Za-z0-9_-]{2,40}$'),
        motifTexte: '2 à 40 lettres, chiffres, tiret ou souligné',
        exemple: 'IMG-RAD-THO',
        aide: 'Aligné sur le code du référentiel tarifaire : un examen est un acte facturable.'),
    _oblig('libelle', 'Intitulé', 'texte', longueurMax: 160, exemple: 'Radiographie du thorax'),
    _oblig('modalite', 'Modalité', 'liste', liste: (_) => [for (final m in modalitesImagerie) ValeurListe(m.code, m.label)], exemple: 'Radiographie', aide: 'Elle range l’examen dans SON tableau.'),
    _col('voie', 'Voie d’abord', 'texte', longueurMax: 60, exemple: 'sus-pubienne'),
    _col('tarifCode', 'Code tarifaire (si différent)', 'texte', longueurMax: 30, exemple: '', aide: 'Quand l’examen se facture comme un autre.'),
  ],
  contexte: (port) => {'examens': _actifsParCode(port, 'examensImagerie', 'code'), 'jour': port.jour, 'h': _referentielPrix(port)},
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final x = (ctx['examens'] as Map)[_n(v['code'])] as _V?;
    return x != null ? 'l’examen « ${x['code']} » existe déjà (${x['label']})' : null;
  },
  regles: (v, ctx, sc, n) {
    final h = ctx['h'] as ReferentielTarifs;
    final jour = '${ctx['jour']}';
    final cible = '${v['tarifCode'] ?? v['code']}';
    final tarif = h.prixGrille(cible, jour, false, aujourdhui: jour);
    return [
      _avert('Code examen', '', 'A_VALIDER', 'examen importé en proposition : il porte la mention « à valider » jusqu’à la relecture du praticien de la famille',
          'L’échographiste ou le directeur médical le valide à l’écran « Catalogue de l’imagerie ».'),
      _avert('Code examen', '', 'SANS_VARIABLES', 'aucune variable de compte rendu n’est importée', 'Elles se définissent au catalogue (onglet « Variables »), jamais depuis un fichier.'),
      if (tarif.montant == null)
        _avert(v['tarifCode'] != null ? 'Code tarifaire (si différent)' : 'Code examen', v['tarifCode'] ?? v['code'], 'SANS_TARIF',
            'aucun tarif en vigueur pour ce code : l’examen sera refusé à la prescription en le nommant',
            'Proposez son prix à l’écran « Tarifs et prix » (famille Imagerie médicale) ou indiquez le code tarifaire d’un examen déjà tarifé.'),
    ];
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    for (final l in lignes) {
      final v = l.v;
      final m = modalitesImagerie.where((x) => x.code == v['modalite']).firstOrNull;
      ecrireFiche('examensImagerie', {
        'code': v['code'],
        'label': v['libelle'],
        'icone': m?.icone ?? 'scan-line',
        'voie': v['voie'],
        'modalite': v['modalite'],
        'tarifCode': v['tarifCode'],
        'aValider': true,
      });
    }
  },
  dependances: (lot, port) {
    final codes = {for (final id in _ecritsDe(lot, 'examensImagerie')) port.parId('examensImagerie', id)?['code']}..remove(null);
    final d = port.actives('demandesImagerie').where((x) => codes.contains(x['examenCode'])).firstOrNull;
    return d == null ? null : DependanceImport('EXAMEN_DEMANDE', 'l’examen est déjà demandé (${d['reference']})', 'Archivez l’examen à l’écran « Catalogue de l’imagerie » (RG-14) plutôt que d’annuler son lot.');
  },
);
