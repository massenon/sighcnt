// LOT 8B, GROUPE COMPTABILITÉ : les immobilisations, les budgets et les courriers.
//
// Port de `prototype_html/assets/js/modules/import.js` (jeux 18 à 20) ; les vecteurs (`test/vecteurs/import.json`, cas `im-*`, `bu-*`, `co-*` et section `compta`) sont tirés de l'écran réel de la
// maquette par `prototype_html/build/vecteurs-import.js`. Les trois jeux sont RESTREINTS (aucune valeur de cellule ne se recopie à l'historique). Les numéros (IM-NNN, BG-AAAA-NNN, ARR et
// DEP-AAAA-NNNN) sont attribués à la suite de la série, ARCHIVÉS COMPRIS (un numéro ne se réutilise jamais), les numéros EXPLICITES du fichier d'abord. RG-10 : aucune écriture comptable n'est
// écrite par ces jeux. Courriers : ajout seul, un courrier déjà tenu est IGNORÉ et compté (mode « ignorer »). Budgets : seul un exercice OUVERT reçoit un budget (refus nommé sinon), et la
// garde du magasin (`cpcGardeBudgets`) refuse l'écriture sur un exercice clos d'où qu'elle vienne.
part of 'jeux_import.dart';

// --- 18. IMMOBILISATIONS (RESTREINT) ------------------------------------------------------------------------------------------------

final JeuImport jeuImmobilisations = JeuImport(
  id: 'immobilisations',
  ecran: 'imp-immobilisations',
  libelle: 'Importation des immobilisations',
  module: 'M12',
  statut: 'supporte',
  description: 'Registre des biens : désignation, catégorie, date d’acquisition, valeur, durée d’amortissement, compte SYSCOHADA.',
  source: 'Écran « Immobilisations & amortissements » : les biens du patrimoine de la clinique.',
  limite:
      'L’amortissement SEMESTRIEL se CALCULE à la lecture, de la date d’acquisition à aujourd’hui : il ne s’importe jamais, et aucune écriture comptable n’est écrite. Un bien cédé ne s’importe pas (la cession se déclare à l’écran). Le numéro IM-NNN est attribué par le logiciel quand la colonne Référence est vide.',
  cibles: const ['immobilisations'],
  fichierModele: 'modele-import-immobilisations',
  colonnesRetirees: const [
    ColonneRetiree('Date de cession', 'une cession se déclare à l’écran « Immobilisations & amortissements » : un bien déjà cédé ne s’importe pas'),
    ColonneRetiree('Prix de cession', 'une cession se déclare à l’écran : un bien déjà cédé ne s’importe pas'),
    ColonneRetiree('Motif de la sortie', 'une sortie du patrimoine se déclare à l’écran : un bien déjà sorti ne s’importe pas'),
    ColonneRetiree('Amortissement cumulé', 'l’amortissement se calcule à la lecture, jamais importé'),
    ColonneRetiree('Valeur nette comptable', 'la valeur nette se calcule à la lecture, jamais importée'),
    ColonneRetiree('Dotation', 'la dotation se calcule à la lecture, jamais importée'),
  ],
  gesteExiste: 'Retirez la ligne : un bien tenu se modifie à l’écran « Immobilisations & amortissements » ; son numéro n’est jamais réécrit.',
  colonnes: [
    _col('reference', 'Référence', 'texte',
        motif: RegExp(r'^[A-Za-z0-9-]{2,20}$'),
        motifTexte: '2 à 20 lettres, chiffres ou tirets',
        exemple: 'IM-050',
        aide: 'Vide : numéro IM-NNN attribué par le logiciel. Renseignée, elle ne doit pas déjà exister.'),
    _oblig('designation', 'Désignation du bien', 'texte', longueurMax: 160, exemple: 'Moniteur multiparamétrique'),
    _oblig('categorie', 'Catégorie', 'liste', liste: _fixe(importCategoriesImmobilisation), exemple: 'Matériel médical'),
    _oblig('dateAcquisition', 'Date d’acquisition', 'date', exemple: '2026-03-15', aide: 'Jamais dans le futur.'),
    _oblig('valeur', 'Valeur d’acquisition (FCFA)', 'entier',
        min: 1,
        exemple: 1800000,
        aide: 'Montant entier strictement positif. Un tiret n’est pas un zéro.',
        sousMin: const SousMinImport('VALEUR_NULLE', 'la valeur d’acquisition doit être strictement positive : un bien sans valeur n’est pas une immobilisation',
            'Saisissez la valeur d’acquisition en francs, ou retirez la ligne.')),
    _oblig('duree', 'Durée d’amortissement (années)', 'entier', min: 1, max: 30, exemple: 5),
    _oblig('compte', 'Compte d’immobilisation', 'texte',
        motif: RegExp(r'^\d{3,8}$'), motifTexte: 'numéro de compte SYSCOHADA de 3 à 8 chiffres', exemple: '241000', aide: 'Un compte d’immobilisation (classe 21 à 27) connu du plan comptable.'),
    _col('fournisseur', 'Fournisseur', 'texte', longueurMax: 120, exemple: ''),
    _col('etat', 'État', 'liste',
        liste: _fixe(const ['En service', 'En maintenance', 'Hors service', 'Cédé']), exemple: 'En service', aide: 'Vide : « En service ». « Cédé » est refusé : un bien déjà cédé ne s’importe pas.'),
  ],
  contexte: (port) {
    final refs = <String, _V>{}, ids = <String, _V>{}, comptes = <String, _V>{};
    for (final i in port.toutes('immobilisations')) {
      if (i['statut'] == 'archive') continue;
      if (i['reference'] != null && i['reference'] != '') refs[_n(i['reference'])] = i;
      ids['${_n(i['designation'])}|${i['dateAcquisition']}|${i['valeurAcquisition']}'] = i;
    }
    for (final c in port.toutes('comptes')) {
      if (c['statut'] != 'archive') comptes['${c['num']}'] = c;
    }
    return {'refs': refs, 'ids': ids, 'comptes': comptes, 'jour': port.jour};
  },
  cle: (v) => [if (v['reference'] != null) 'ref:${_n(v['reference'])}', '${_n(v['designation'])}|${v['dateAcquisition']}|${v['valeur']}'],
  existe: (v, ctx) {
    final a = v['reference'] != null ? (ctx['refs'] as Map)[_n(v['reference'])] as _V? : null;
    final b = (ctx['ids'] as Map)['${_n(v['designation'])}|${v['dateAcquisition']}|${v['valeur']}'] as _V?;
    if (a != null) return 'le bien « ${a['reference']} » existe déjà (${a['designation']})';
    return b != null ? 'un bien identique existe déjà (${b['reference']})' : null;
  },
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    if ('${v['dateAcquisition']}'.compareTo('${ctx['jour']}') > 0) {
      pb.add(_p('Date d’acquisition', v['dateAcquisition'], 'DATE_FUTURE', importRefus, 'la date d’acquisition est dans le futur', 'Saisissez la date réelle d’acquisition (un bien ne s’amortit pas avant d’exister).'));
    }
    if (v['etat'] == 'Cédé') {
      pb.add(_p('État', v['etat'], 'BIEN_CEDE', importRefus, 'un bien déjà cédé ne s’importe pas : il sort du patrimoine par la déclaration de cession à l’écran', 'Retirez la ligne.'));
    }
    final compte = '${v['compte']}';
    if (!(ctx['comptes'] as Map).containsKey(compte)) {
      pb.add(_p('Compte d’immobilisation', v['compte'], 'COMPTE_INCONNU', importRefus, 'le compte $compte n’existe pas au plan comptable', 'Importez-le d’abord (jeu « Importation du plan comptable ») ou corrigez le numéro.'));
    } else if (!RegExp(r'^2[1-7]').hasMatch(compte)) {
      pb.add(_p('Compte d’immobilisation', v['compte'], 'COMPTE_NON_IMMOBILISATION', importRefus, 'le compte $compte n’est pas un compte d’immobilisation (classes 21 à 27)', 'Choisissez un compte d’immobilisation.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    // Les numéros EXPLICITES d'abord : un numéro automatique ne prend jamais un numéro que le fichier porte plus bas.
    final ordre = [...lignes.where((l) => l.v['reference'] != null), ...lignes.where((l) => l.v['reference'] == null)];
    for (final l in ordre) {
      final v = l.v;
      ecrireFiche('immobilisations', {
        'reference': v['reference'] ?? _serie('IM-', 3, port.toutes('immobilisations')),
        'designation': v['designation'],
        'categorie': v['categorie'],
        'dateAcquisition': v['dateAcquisition'],
        'valeurAcquisition': v['valeur'],
        'dureeAmortissement': v['duree'],
        'compte': '${v['compte']}',
        'fournisseur': v['fournisseur'] ?? '',
        'etat': v['etat'] ?? 'En service',
      });
    }
  },
  dependances: (lot, port) {
    final b = _ecritsDe(lot, 'immobilisations').map((id) => port.parId('immobilisations', id)).where((x) => x != null && (_vrai(x['dateCession']) || x['etat'] == 'Cédé')).firstOrNull;
    return b == null
        ? null
        : DependanceImport('BIEN_CEDE_DEPUIS', 'le bien ${b['reference']} a été cédé ou sorti du patrimoine depuis l’import',
            'Un bien sorti se traite à l’écran « Immobilisations & amortissements » : sa fiche reste au registre.');
  },
);

// --- 19. BUDGETS (RESTREINT, exercice OUVERT seulement) -----------------------------------------------------------------------------

final JeuImport jeuBudgets = JeuImport(
  id: 'budgets',
  ecran: 'imp-budgets',
  libelle: 'Importation des budgets',
  module: 'M12',
  statut: 'supporte',
  description: 'Budget prévisionnel par exercice, centre de coûts et nature budgétaire.',
  source: 'Écran « Budgets » : un budget par exercice, centre et nature ; le réalisé se lit des écritures.',
  limite:
      'Seul un exercice OUVERT reçoit un budget : un exercice en clôture ou clos est refusé en le nommant (la garde est au magasin, l’écran la subit comme le fichier). Le réalisé n’est jamais importé : il se lit des écritures. Le numéro BG-AAAA-NNN est attribué par le logiciel.',
  cibles: const ['budgets'],
  fichierModele: 'modele-import-budgets',
  gesteExiste: 'Retirez la ligne : un budget tenu se modifie à l’écran « Budgets » ; son numéro n’est jamais réécrit.',
  colonnes: [
    _oblig('exercice', 'Exercice', 'entier', min: 2000, max: 2100, exemple: 2027, aide: 'L’année de l’exercice, qui doit être ouvert.'),
    _oblig('centre', 'Centre de coûts', 'liste',
        liste: (ctx) => [for (final c in ((ctx as Map)['centresListe'] as List)) ValeurListe('${(c as List)[0]}', '${c[1]}')],
        exemple: 'Laboratoire',
        aide: 'Le code ou l’intitulé d’un centre connu : importez-le d’abord au besoin.'),
    _oblig('nature', 'Nature budgétaire', 'liste', liste: _fixe(importNaturesBudget), exemple: 'Charges de fonctionnement'),
    _oblig('prevu', 'Montant prévisionnel (FCFA)', 'entier', min: 0, exemple: 5000000, aide: 'Montant entier, zéro ou plus. Un tiret n’est pas un zéro : il est refusé.'),
  ],
  contexte: (port) {
    final centres = <List<String>>[], lib = <String, Object?>{}, b = <String, _V>{};
    for (final c in port.toutes('centresCouts')) {
      if (c['statut'] != 'archive') {
        centres.add(['${c['code']}', '${c['libelle']}']);
        lib['${c['code']}'] = c['libelle'];
      }
    }
    for (final x in port.toutes('budgets')) {
      if (x['statut'] != 'archive') b['${x['exercice']}|${x['centreCout']}|${_n(x['nature'])}'] = x;
    }
    return <String, Object?>{'centresListe': centres, 'libelles': lib, 'budgets': b, 'exercices': port.toutes('exercices')};
  },
  cle: (v) => ['${v['exercice']}|${v['centre']}|${_n(v['nature'])}'],
  existe: (v, ctx) {
    final x = (ctx['budgets'] as Map)['${v['exercice']}|${v['centre']}|${_n(v['nature'])}'] as _V?;
    return x != null ? 'le budget ${x['reference']} existe déjà pour cet exercice, ce centre et cette nature' : null;
  },
  regles: (v, ctx, sc, n) {
    final a = (v['exercice'] as num).toInt();
    final e = cpcEtatExercice((ctx['exercices'] as List).cast<Map<String, Object?>>(), a);
    if (e == 'clos') {
      return [
        _p('Exercice', v['exercice'], 'EXERCICE_CLOS', importRefus, 'l’exercice $a est clos : lecture seule',
            'Seul un exercice ouvert reçoit un budget : rouvrez l’exercice (comptable, motif obligatoire) ou datez le budget de l’exercice ouvert.')
      ];
    }
    if (e != 'ouvert') {
      return [
        _p('Exercice', v['exercice'], 'EXERCICE_EN_CLOTURE', importRefus, 'l’exercice $a est en clôture : les modules n’y écrivent plus', 'Terminez ou reprenez la clôture, ou datez le budget de l’exercice ouvert.')
      ];
    }
    return const [];
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    for (final l in lignes) {
      final v = l.v;
      final ref = _serie('BG-${v['exercice']}-', 3, port.toutes('budgets'));
      ecrireFiche('budgets', {'reference': ref, 'exercice': v['exercice'], 'centreCout': v['centre'], 'centre': (ctx['libelles'] as Map)[v['centre']] ?? v['centre'], 'nature': v['nature'], 'prevu': v['prevu']});
    }
  },
  dependances: (lot, port) {
    final exercices = port.toutes('exercices');
    final b = _ecritsDe(lot, 'budgets').map((id) => port.parId('budgets', id)).where((x) => x != null && cpcEtatExercice(exercices, (x['exercice'] as num).toInt()) == 'clos').firstOrNull;
    return b == null
        ? null
        : DependanceImport('EXERCICE_CLOS', 'l’exercice ${b['exercice']} a été clos depuis l’import : le budget ${b['reference']} est en lecture seule', 'Rouvrez l’exercice (comptable, motif obligatoire) pour corriger.');
  },
);

// --- 20. COURRIERS (RESTREINT, ajout seul, « ignorer » permis) ----------------------------------------------------------------------

final JeuImport jeuCourriers = JeuImport(
  id: 'courriers',
  ecran: 'imp-courriers',
  libelle: 'Importation des courriers',
  module: 'M13',
  statut: 'supporte',
  description: 'Registre du courrier : sens, date, correspondant, objet, nature, service destinataire.',
  source: 'Écran « Courriers (départ / arrivée) » : le registre numéroté ARR-AAAA-NNNN et DEP-AAAA-NNNN.',
  limite:
      'Le registre est en AJOUT SEUL : un numéro d’ordre n’est jamais réécrit. La colonne N° d’ordre est facultative (vide : numéro attribué à la suite du registre) ; renseignée, elle doit suivre la série (ARR ou DEP selon le sens, année de la date). Le traitement, l’accusé de réception et la numérisation ne s’importent jamais : le courrier naît « en attente ». Un courrier déjà tenu est IGNORÉ, compté et nommé au rapport.',
  cibles: const ['courriers'],
  fichierModele: 'modele-import-courriers',
  gesteExiste: 'Retirez la ligne : le registre est en ajout seul, un courrier tenu ne se modifie pas par un import.',
  colonnesRetirees: const [
    ColonneRetiree('État du traitement', 'le traitement d’un courrier est un geste du service : il ne s’importe pas (le courrier naît « en attente »)'),
    ColonneRetiree('Accusé de réception', 'l’accusé de réception est un geste du service : il ne s’importe pas'),
    ColonneRetiree('Document numérisé', 'la pièce numérisée se dépose à l’écran : elle ne s’importe pas'),
  ],
  colonnes: [
    _col('reference', 'N° d’ordre', 'texte',
        motif: RegExp(r'^(ARR|DEP)-\d{4}-\d{4,}$'), motifTexte: 'ARR-AAAA-NNNN ou DEP-AAAA-NNNN', exemple: '', aide: 'Facultatif. Vide : numéro attribué à la suite du registre. Jamais réécrit.'),
    _oblig('sens', 'Sens', 'liste', liste: (_) => [for (final s in importSensCourrier) ValeurListe(s[0], s[1])], exemple: 'Arrivée'),
    _oblig('date', 'Date', 'date', exemple: '2026-11-03'),
    _col('correspondant', 'Correspondant', 'texte', longueurMax: 120, exemple: 'DDS Atacora-Donga'),
    _oblig('objet', 'Objet', 'texte', longueurMax: 200, exemple: 'Demande de renseignements'),
    _col('nature', 'Nature', 'liste', liste: _fixe(importNaturesCourrier), exemple: 'Lettre', aide: 'Vide : « Lettre » (comme l’écran).'),
    _col('affecteA', 'Service destinataire', 'liste', liste: _fixe(importServicesCourrier), exemple: 'Direction Administrative'),
  ],
  // Le registre est en AJOUT SEUL : un courrier ARCHIVÉ compte encore (son numéro n'est jamais réutilisé).
  contexte: (port) {
    final refs = <String, _V>{}, trio = <String, _V>{};
    for (final c in port.toutes('courriers')) {
      if (c['reference'] != null && c['reference'] != '') refs[_n(c['reference'])] = c;
      trio['${'${c['date']}'.length >= 10 ? '${c['date']}'.substring(0, 10) : c['date']}|${c['sens']}|${_n(c['objet'])}'] = c;
    }
    return {'refs': refs, 'trio': trio};
  },
  cle: (v) => [if (v['reference'] != null) 'ref:${_n(v['reference'])}', '${v['date']}|${v['sens']}|${_n(v['objet'])}'],
  existe: (v, ctx) {
    final a = v['reference'] != null ? (ctx['refs'] as Map)[_n(v['reference'])] as _V? : null;
    final b = (ctx['trio'] as Map)['${v['date']}|${v['sens']}|${_n(v['objet'])}'] as _V?;
    if (a != null) return 'le courrier ${a['reference']} est déjà au registre';
    return b != null ? 'le courrier ${b['reference']} (même date, même sens, même objet) est déjà au registre' : null;
  },
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    if (v['reference'] != null) {
      final ref = '${v['reference']}', pref = v['sens'] == 'arrivee' ? 'ARR' : 'DEP';
      if (ref.substring(0, 3) != pref || ref.substring(4, 8) != '${v['date']}'.substring(0, 4)) {
        pb.add(_p('N° d’ordre', v['reference'], 'NUMERO_INCOHERENT', importRefus, 'le numéro ne suit pas la série : $pref-${'${v['date']}'.substring(0, 4)}-NNNN (sens et année de la date)',
            'Alignez le numéro sur le sens et l’année du courrier, ou laissez la colonne vide.'));
      }
    }
    if (v['correspondant'] == null) pb.add(_avert('Correspondant', '', 'CORRESPONDANT_ABSENT', 'correspondant non renseigné', 'Il se complète à l’écran « Courriers (départ / arrivée) ».'));
    if (v['affecteA'] == null) pb.add(_avert('Service destinataire', '', 'SERVICE_ABSENT', 'service destinataire non renseigné', 'Il se complète à l’écran.'));
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    // Les numéros EXPLICITES d'abord : un numéro automatique ne prend jamais un numéro que le fichier porte plus bas.
    final ordre = [...lignes.where((l) => l.v['reference'] != null), ...lignes.where((l) => l.v['reference'] == null)];
    for (final l in ordre) {
      final v = l.v;
      final ref = v['reference'] ?? _serie('${v['sens'] == 'arrivee' ? 'ARR-' : 'DEP-'}${'${v['date']}'.substring(0, 4)}-', 4, port.toutes('courriers'));
      // Un import de lignes ne porte AUCUN fichier : `numerise` (dérivé du fichier rattaché) reste faux, la pièce se dépose ensuite sur la fiche.
      ecrireFiche('courriers', {
        'reference': ref,
        'sens': v['sens'],
        'date': v['date'],
        'correspondant': v['correspondant'] ?? '',
        'objet': v['objet'],
        'nature': v['nature'] ?? 'Lettre',
        'affecteA': v['affecteA'],
        'traitement': 'en_attente',
        'accuseReception': false,
      });
    }
  },
  dependances: (lot, port) {
    final c = _ecritsDe(lot, 'courriers')
        .map((id) => port.parId('courriers', id))
        .where((x) => x != null && (x['traitement'] != 'en_attente' || (x['fichier'] is Map && _vrai((x['fichier'] as Map)['sha256'])) || _vrai(x['accuseReception'])))
        .firstOrNull;
    return c == null
        ? null
        : DependanceImport('COURRIER_TRAITE', 'le courrier ${c['reference']} a déjà été traité, accusé ou numérisé', 'Un courrier traité reste au registre : archivez-le à l’écran (RG-14) plutôt que d’annuler son lot.');
  },
);
