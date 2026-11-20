// LOT 8B, GROUPE GARANTIES ET COUVERTURES : les garanties des souscripteurs (versions datées) et les couvertures d'assurance des assurés (couverture datée, close la veille).
//
// Port de `prototype_html/assets/js/modules/import.js` (jeux 16 et 17) ; les vecteurs (`test/vecteurs/import.json`, cas `ga-*`, `cv-*` et section `assurances`) sont tirés de l'écran réel de la
// maquette par `prototype_html/build/vecteurs-import.js`. Même mécanisme que les prix : quand une donnée de référence change alors que des pièces ont été émises sous l'ancienne, on VERSIONNE
// par date, on n'écrase jamais. RG-09 : la prise en charge ne vaut que si la carte est valide à la date de facturation ; une couverture sans expiration le dit (avertissement), et la date
// d'effet ne rattrape jamais une pièce émise (elle garde sa répartition). Les deux jeux écrivent par les MÊMES fabriques que les écrans (`assPoserGarantie`, `assChangerCouverture`).
part of 'jeux_import.dart';

const _champsMiroirAssure = ['assureur', 'assureurNom', 'numeroPolice', 'categorieAssurance', 'tauxPriseEnCharge', 'carteExpiration', 'souscripteurId', 'souscripteur'];

const _colonneDuRefusGarantie = {
  'SOUSCRIPTEUR_INCONNU': 'N° de police',
  'CATEGORIE_INCONNUE': 'Catégorie',
  'GARANTIE_SANS_LIBELLE': 'Garantie',
  'TAUX_INVALIDE': 'Taux (%)',
  'PLAFOND_INVALIDE': 'Plafond (FCFA)',
  'UNITE_PLAFOND_REQUISE': 'Unité du plafond',
  'DATE_EFFET_REQUISE': 'Date d’effet',
  'VERSION_MEME_DATE': 'Date d’effet',
  'VERSION_ANTERIEURE': 'Date d’effet',
  'FACTURE_DEJA_EMISE': 'Date d’effet',
};

String _decrireGarantie(num taux, num? plafond, Object? unite) =>
    '${_jsNombre(taux.toDouble())} %, ${plafond == null ? 'sans plafond' : 'plafond ${nombre(plafond)} ${assLibelleUnite(unite)}'}';

AssPoseGarantie _poserGarantiePort(PortImport port, _V souscripteur, _V v, {bool essai = false, Map<String, Object?> champs = const {}, String? source}) => assPoserGarantie(
      {
        'souscripteurId': souscripteur['id'],
        'categorie': v['categorie'],
        'libelle': v['garantie'],
        'taux': v['taux'],
        'plafond': v['plafond'],
        'unitePlafond': v['unite'],
        'dateEffet': v['dateEffet'],
        'source': source,
        'motif': v['motif'],
      },
      souscripteurs: port.actives('souscripteurs'),
      garanties: port.actives('garanties'),
      factures: port.actives('factures'),
      patients: port.actives('patients'),
      couvertures: port.actives('couverturesAssurance'),
      essai: essai,
      champs: champs,
    );

// --- 16. GARANTIES (version datée) --------------------------------------------------------------------------------------------------

final JeuImport jeuGaranties = JeuImport(
  id: 'garanties',
  ecran: 'imp-garanties',
  libelle: 'Importation des garanties des souscripteurs',
  module: 'M9',
  statut: 'supporte',
  description: 'Taux et plafonds par souscripteur et par garantie, avec une date d’effet : chaque ligne qui change crée une NOUVELLE VERSION datée, jamais un écrasement.',
  source: 'Conventions de prise en charge par souscripteur (barème de remboursement, docs/) et écran « Conventions & garanties ».',
  limite:
      'Une version ne s’écrit que pour un souscripteur connu (par son numéro de police). La version remplacée reste écrite : une facture émise garde son taux, et une date d’effet qu’une facture a déjà dépassée est refusée. La clé est le souscripteur, la catégorie, la garantie (une catégorie en porte plusieurs : consultation généraliste et spécialiste) et la date d’effet. Une seule version par garantie et par fichier.',
  cibles: const ['garanties'],
  fichierModele: 'modele-import-garanties',
  colonnes: [
    _oblig('police', 'N° de police', 'texte', longueurMax: 40, exemple: 'AFR/2024/0100', aide: 'La police d’un souscripteur connu : importez-le d’abord au besoin.'),
    _oblig('categorie', 'Catégorie', 'liste', liste: (_) => [for (final c in assCategoriesGarantie) ValeurListe(c.$1, c.$2)], exemple: 'Consultations'),
    _oblig('garantie', 'Garantie', 'texte', longueurMax: 120, exemple: 'Consultation généraliste', aide: 'Le libellé de la garantie : il distingue deux garanties d’une même catégorie.'),
    _oblig('taux', 'Taux (%)', 'decimal', min: 0, max: 100, exemple: 80),
    _col('plafond', 'Plafond (FCFA)', 'entier', min: 0, exemple: 5000, aide: 'Vide : sans plafond. Un tiret n’est pas un zéro.'),
    _col('unite', 'Unité du plafond', 'liste',
        liste: (_) => [for (final u in assUnitesPlafond.entries) ValeurListe(u.key, u.value)], exemple: 'par acte', aide: 'Obligatoire quand un plafond est renseigné.'),
    _oblig('dateEffet', 'Date d’effet', 'date', exemple: '2027-01-01', aide: 'Le jour où ces valeurs s’appliquent. Les pièces antérieures gardent les valeurs de leur date.'),
    _col('motif', 'Motif', 'texte', longueurMax: 160, exemple: 'Avenant du 01/12/2026'),
    _col('source', 'Source', 'texte', longueurMax: 160, exemple: ''),
  ],
  contexte: (port) => {
        'polices': {for (final s in port.toutes('souscripteurs')) if (s['statut'] != 'archive') _n(s['police']): s},
        'port': port,
      },
  cle: (v) => ['${_n(v['police'])}|${v['categorie']}|${_n(v['garantie'])}|${v['dateEffet']}'],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final ligne = sc['ligne'] as LigneImport;
    final s = (ctx['polices'] as Map)[_n(v['police'])] as _V?;
    if (s == null) {
      return [
        _p('N° de police', v['police'], 'SOUSCRIPTEUR_INCONNU', importRefus, 'aucun souscripteur ne porte la police « ${v['police']} »',
            'Importez d’abord le souscripteur (jeu « Importation des souscripteurs ») ou corrigez le numéro de police.')
      ];
    }
    final e = _poserGarantiePort(ctx['port'] as PortImport, s, v, essai: true);
    final nouveau = _decrireGarantie(v['taux'] as num, v['plafond'] as num?, v['unite']);
    final extras = sc['extras'] as Map<int, String>;
    if (!e.ok && e.code == 'GARANTIE_INCHANGEE') {
      ligne.sansEcriture = 'inchange';
      extras[n] = _detailPrix({'ancien': nouveau, 'nouveau': nouveau, 'variation': '', 'decision': 'Inchangée'});
      return [_p('Taux (%)', '', 'GARANTIE_INCHANGEE', 'info', 'cette garantie porte déjà ces valeurs à cette date : aucune version, la ligne est comptée', 'Rien à faire.')];
    }
    if (!e.ok) return [_p(_colonneDuRefusGarantie[e.code] ?? 'Garantie', '', e.code!, importRefus, e.motif!, e.geste!)];
    final ancienne = e.ancienne;
    final anc = ancienne != null && ('${ancienne['dateEffet'] ?? ''}'.isEmpty || '${ancienne['dateEffet']}'.compareTo('${v['dateEffet']}') <= 0) ? ancienne : null;
    final d = anc == null ? 0.0 : arrondiJs(((v['taux'] as num) - (anc['taux'] as num)) * 10) / 10;
    extras[n] = _detailPrix({
      'ancien': anc != null ? _decrireGarantie(anc['taux'] as num, anc['plafond'] as num?, anc['unitePlafond']) : 'première version',
      'nouveau': nouveau,
      'variation': anc != null ? '${d > 0 ? '+' : ''}${_jsNombre(d)} pt' : '',
      'decision': anc != null ? 'Nouvelle version v${e.version} au ${dateFR(assDate(v['dateEffet']))}' : 'Première version au ${dateFR(assDate(v['dateEffet']))}',
    });
    return [
      if (v['unite'] != null && v['plafond'] == null)
        _avert('Unité du plafond', '', 'UNITE_SANS_PLAFOND', 'une unité de plafond sans plafond : elle est ignorée (garantie sans plafond)', 'Retirez l’unité ou renseignez le plafond.'),
    ];
  },
  // Une seule version par garantie et par fichier : deux dates pour la même garantie se poseraient dans l'ordre du fichier, et la seconde serait refusée à l'écriture, le lot entier avec elle.
  reglesLot: (lignes, ctx) {
    final vus = <String, int>{};
    final out = <ProblemeImport>[];
    for (final l in lignes) {
      if (l.sansEcriture != null || l.etat == 'refus') continue;
      final k = '${_n(l.v['police'])}|${l.v['categorie']}|${_n(l.v['garantie'])}';
      if (vus.containsKey(k)) {
        out.add(constat('Date d’effet', '', 'UNE_VERSION_PAR_GARANTIE', importRefus,
            'la garantie porte deux versions dans ce fichier (lignes ${vus[k]} et ${l.n}) : une seule version par garantie et par fichier', 'Gardez une ligne par garantie ; la version suivante s’importe dans un second fichier.'));
      } else {
        vus[k] = l.n;
      }
    }
    return out;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    for (final l in lignes) {
      final v = l.v;
      final s = (ctx['polices'] as Map)[_n(v['police'])] as _V;
      final r = _poserGarantiePort(port, s, v,
          source: v['source'] as String? ?? 'Lot d’import ${lot['reference']}', champs: {'lotImport': lot['reference'], 'validePar': port.utilisateur, 'dateImport': port.jour});
      if (!r.ok) throw StateError('ligne ${l.n} : ${r.motif}');
      final stockee = port.inserer('garanties', {'statut': 'actif', ...r.fiche!});
      declarer('garanties', stockee['id']);
    }
  },
  // Une version s'annule (archivage) tant qu'aucune facture n'a été émise sous elle et qu'aucune version plus récente de la série n'a été posée.
  dependances: (lot, port) {
    final propres = {for (final id in _ecritsDe(lot, 'garanties')) id};
    for (final id in _ecritsDe(lot, 'garanties')) {
      final g = port.parId('garanties', id);
      if (g == null || g['statut'] == 'archive') continue;
      final posterieure = assVersionsGarantie(port.actives('garanties'), g['souscripteurId'], g['categorie'], g['libelle'])
          .where((x) => !propres.contains(x['id']) && '${x['dateEffet'] ?? ''}'.compareTo('${g['dateEffet'] ?? ''}') > 0)
          .firstOrNull;
      if (posterieure != null) {
        return DependanceImport('VERSION_POSTERIEURE', 'une version plus récente de « ${g['libelle']} » prend effet le ${dateFR(assDate(posterieure['dateEffet']))}', 'Annulez d’abord le lot qui a posé la version plus récente.');
      }
      final s = port.parId('souscripteurs', g['souscripteurId']);
      final f = s != null && _vrai(g['dateEffet'])
          ? assFactureSousGrille(s, '${g['dateEffet']}',
              factures: port.actives('factures'), patients: port.actives('patients'), couvertures: port.actives('couverturesAssurance'), souscripteurs: port.actives('souscripteurs'))
          : null;
      if (f != null) {
        return DependanceImport('GARANTIE_UTILISEE', 'la facture ${f['numero']} du ${dateFR(assDate(f['date']))} a été émise sous cette version', 'Une version employée par une pièce émise ne s’annule plus : posez une nouvelle version datée.');
      }
    }
    return null;
  },
);

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

// --- 17. COUVERTURES D'ASSURANCE (RESTREINT, version datée par assuré) ----------------------------------------------------------------

final JeuImport jeuCouverturesAssurance = JeuImport(
  id: 'couvertures-assurance',
  ecran: 'imp-couvertures-assurance',
  libelle: 'Importation des couvertures d’assurance',
  module: 'M9',
  statut: 'supporte',
  description: 'Changement de couverture d’un assuré à une date d’effet : compagnie, police, motif, expiration de la carte. La couverture en cours est close la veille.',
  source: 'Écran « Assurés & cartes », geste « Mettre à jour la couverture » : l’historique conserve la couverture précédente.',
  limite:
      'La date d’effet et le motif sont OBLIGATOIRES : une date qu’on n’a pas saisie ne s’invente pas (aucune couverture « depuis l’origine » n’est écrite par un import). Le dossier du patient n’est jamais écrit par ce jeu : la fiche suit la couverture en force aujourd’hui, comme à l’écran. Aucune facture n’est écrite ni modifiée.',
  cibles: const ['couverturesAssurance'],
  fichierModele: 'modele-import-couvertures-assurance',
  colonnes: [
    _oblig('patient', 'Code patient', 'texte', longueurMax: 24, exemple: 'CNT/1/26', aide: 'Le code d’un dossier connu. Un code attribué ne se modifie jamais (RG-01).'),
    _oblig('assureur', 'Code compagnie', 'liste',
        liste: (ctx) => [for (final a in ((ctx as Map)['assureursListe'] as List)) ValeurListe('$a')], exemple: 'NSIA', aide: 'Une compagnie connue du magasin.'),
    _oblig('police', 'N° de police', 'texte', longueurMax: 40, exemple: 'AFR/2024/0100', aide: 'La police d’un souscripteur connu de cette compagnie.'),
    _oblig('dateEffet', 'Date d’effet', 'date', exemple: '2027-01-01', aide: 'La couverture précédente est close la veille. Obligatoire : une date d’effet ne s’invente pas.'),
    _oblig('motif', 'Motif', 'liste',
        liste: (_) => [for (final m in importMotifsCouverture) if (!m.startsWith('Fin de couverture')) ValeurListe(m)], exemple: 'Changement d’employeur'),
    _col('categorie', 'Catégorie', 'liste', liste: _fixe(const ['entreprise', 'particulier', 'personnel']), exemple: 'entreprise', aide: 'Vide : celle du souscripteur.'),
    _col('taux', 'Taux de prise en charge (%)', 'decimal', min: 0, max: 100, exemple: 80, aide: 'Vide : 0. La grille par garantie vit au souscripteur.'),
    _col('carteExpiration', 'Expiration de la carte', 'date', exemple: '2027-12-31', aide: 'Vide : la carte n’est jamais valide (RG-09) : facturation intégrale au patient.'),
  ],
  contexte: (port) {
    final pat = <String, _V>{}, pol = <String, _V>{}, noms = <String, Object?>{}, couv = <Object?, List<_V>>{}, facturesDe = <Object?, List<_V>>{};
    final ass = <String>[];
    for (final p in port.toutes('patients')) {
      if (p['statut'] != 'archive') pat[_n(p['code'])] = p;
    }
    for (final s in port.toutes('souscripteurs')) {
      if (s['statut'] != 'archive') pol[_n(s['police'])] = s;
    }
    for (final a in port.toutes('assureurs')) {
      if (a['statut'] != 'archive') {
        ass.add('${a['code']}');
        noms['${a['code']}'] = a['nom'];
      }
    }
    for (final c in port.toutes('couverturesAssurance')) {
      if (c['statut'] != 'archive') (couv[c['patientId']] ??= []).add(c);
    }
    for (final f in port.toutes('factures')) {
      if (f['statut'] != 'archive' && f['patientId'] != null) (facturesDe[f['patientId']] ??= []).add(f);
    }
    return <String, Object?>{'patients': pat, 'polices': pol, 'assureursListe': ass, 'nomsAssureurs': noms, 'couvertures': couv, 'facturesDe': facturesDe};
  },
  cle: (v) => ['${_n(v['patient'])}@${v['dateEffet']}'],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final p = (ctx['patients'] as Map)[_n(v['patient'])] as _V?;
    if (p == null) {
      return [
        _p('Code patient', v['patient'], 'PATIENT_INCONNU', importRefus, 'aucun dossier ne porte ce code',
            'Importez d’abord le patient (jeu « Importation du répertoire patients ») ou corrigez le code.')
      ];
    }
    final pb = <ProblemeImport>[];
    final s = (ctx['polices'] as Map)[_n(v['police'])] as _V?;
    if (s == null) {
      pb.add(_p('N° de police', v['police'], 'POLICE_INCONNUE', importRefus, 'aucun souscripteur ne porte la police « ${v['police']} »', 'Importez d’abord le souscripteur ou corrigez le numéro de police.'));
    } else if (s['assureur'] != v['assureur']) {
      pb.add(_p('N° de police', v['police'], 'POLICE_AUTRE_COMPAGNIE', importRefus, 'la police appartient à une autre compagnie que celle du fichier', 'Alignez le code compagnie sur celui du souscripteur.'));
    }
    final courante = ((ctx['couvertures'] as Map)[p['id']] as List?)?.cast<_V>().where((c) => !_vrai(c['fin'])).firstOrNull;
    if (courante != null && _vrai(courante['debut']) && '${v['dateEffet']}'.compareTo('${courante['debut']}') <= 0) {
      pb.add(_p('Date d’effet', v['dateEffet'], 'DATE_EFFET_ANTERIEURE', importRefus,
          'la date d’effet doit être postérieure au début de la couverture en cours (${dateFR(assDate(courante['debut']))})', 'Choisissez une date d’effet plus tardive.'));
    }
    if (v['carteExpiration'] == null) {
      pb.add(_avert('Expiration de la carte', '', 'CARTE_SANS_EXPIRATION', 'sans date d’expiration, la carte n’est jamais valide (RG-09) : le patient serait facturé intégralement', 'Renseignez l’expiration de la carte.'));
    }
    final f = (((ctx['facturesDe'] as Map)[p['id']] as List?) ?? const []).cast<_V>().where((x) {
      final d = '${x['date'] ?? ''}';
      return d.isNotEmpty && (d.length >= 10 ? d.substring(0, 10) : d).compareTo('${v['dateEffet']}') >= 0;
    }).firstOrNull;
    if (f != null) {
      pb.add(_avert('Date d’effet', v['dateEffet'], 'FACTURE_DEJA_EMISE', 'une facture du patient est datée à partir de cette date d’effet : elle garde sa répartition, seule sa relecture changerait',
          'Vérifiez la date d’effet : elle ne rattrape jamais une pièce émise.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    final ordre = [...lignes]..sort((a, b) {
        final pa = _n(a.v['patient']), pb = _n(b.v['patient']);
        if (pa != pb) return pa.compareTo(pb);
        return '${a.v['dateEffet']}'.compareTo('${b.v['dateEffet']}') < 0 ? -1 : 1;
      });
    final maintenant = DateTime.parse('${port.jour}T12:00:00');
    for (final l in ordre) {
      final v = l.v;
      final p = port.parId('patients', ((ctx['patients'] as Map)[_n(v['patient'])] as _V)['id'])!;
      final s = (ctx['polices'] as Map)[_n(v['police'])] as _V;
      final miroir = {for (final k in _champsMiroirAssure) k: p[k]};
      final historique = port.actives('couverturesAssurance').where((c) => c['patientId'] == p['id']).toList();
      final r = assChangerCouverture(
          p,
          historique,
          {
            'dateEffet': v['dateEffet'],
            'motif': v['motif'],
            'assureur': v['assureur'],
            'assureurNom': (ctx['nomsAssureurs'] as Map)[v['assureur']],
            'numeroPolice': s['police'],
            'categorieAssurance': v['categorie'] ?? s['categorie'],
            'tauxPriseEnCharge': v['taux'] ?? 0,
            'carteExpiration': v['carteExpiration'],
            'souscripteurId': s['id'],
          },
          maintenant,
          souscripteurs: port.actives('souscripteurs'));
      if (!r.ok) throw StateError('ligne ${l.n} : ${r.motif}');
      // Dans l'ordre où la maquette écrit : la couverture du dossier reprise AVANT d'être close, la couverture en cours close la veille, la couverture neuve.
      Object? repriseId, fermeeId, neuveId;
      Object? finAvant;
      if (r.reprise != null) repriseId = port.inserer('couverturesAssurance', {'statut': 'actif', ...r.reprise!})['id'];
      final f = r.fermer;
      if (f != null && f.id != null) {
        finAvant = port.parId('couverturesAssurance', f.id)?['fin'];
        port.mettreAJour('couverturesAssurance', f.id, {'fin': f.fin});
        fermeeId = f.id;
      }
      // Seule la couverture NEUVE porte la trace du lot ; la couverture reprise du dossier est un état d'AVANT, déclarée pour s'archiver avec le lot.
      neuveId = port.inserer('couverturesAssurance', {
        'statut': 'actif',
        ...r.nouvelle!,
        'source': 'Import ${lot['reference']}',
        'lotImport': lot['reference'],
        'validePar': port.utilisateur,
        'dateImport': port.jour,
      })['id'];
      // Ce que le geste a écrit, déclaré le plus récent d'abord (comme la maquette le relève dans son registre).
      declarer('couverturesAssurance', neuveId);
      if (repriseId != null) declarer('couverturesAssurance', repriseId);
      if (fermeeId != null) declarer('couverturesAssurance', fermeeId, avant: {'fin': finAvant});
      port.mettreAJour('patients', p['id'], r.majPatient!);
      final apres = port.parId('patients', p['id'])!;
      final avantP = <String, Object?>{for (final k in _champsMiroirAssure) if (apres[k] != miroir[k]) k: miroir[k]};
      if (avantP.isNotEmpty) declarer('patients', p['id'], avant: avantP);
    }
  },
  // Une couverture s'annule (l'ancienne reprend sa fin, le dossier retrouve son état) tant qu'aucune couverture plus récente n'a été posée et qu'aucune facture n'a été émise après le lot sous elle.
  dependances: (lot, port) {
    final propres = {for (final e in (lot['ecrits'] as List).cast<Map>()) e['id']};
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      if (e['collection'] != 'couverturesAssurance' || e['avant'] != null) continue;
      final c = port.parId('couverturesAssurance', e['id']);
      if (c == null || c['statut'] == 'archive') continue;
      final apres = port
          .actives('couverturesAssurance')
          .where((x) => x['patientId'] == c['patientId'] && !propres.contains(x['id']) && '${x['debut'] ?? ''}'.compareTo('${c['debut'] ?? ''}') > 0)
          .firstOrNull;
      if (apres != null) {
        return DependanceImport('COUVERTURE_POSTERIEURE', 'une couverture plus récente de cet assuré a été posée depuis (effet le ${dateFR(assDate(apres['debut']))})',
            'Annulez d’abord cette couverture, ou corrigez l’assuré à l’écran « Assurés & cartes ».');
      }
      // La maquette compare l'horodatage de CRÉATION de la facture à celui du lot ; le magasin du poste n'en tient pas : une facture est dite « émise après le lot » quand son JOUR est celui
      // du lot ou plus tard (prudent : la même journée compte). Écart consigné.
      final f = port.actives('factures').where((x) {
        final d = '${x['date'] ?? ''}';
        final jour = d.length >= 10 ? d.substring(0, 10) : d;
        return x['patientId'] == c['patientId'] && _vrai(c['debut']) && jour.compareTo('${c['debut']}') >= 0 && jour.compareTo('${lot['date'] ?? ''}') >= 0;
      }).firstOrNull;
      if (f != null) {
        return DependanceImport('FACTURE_SOUS_COUVERTURE', 'la facture ${f['numero']} du ${dateFR(assDate(f['date']))} a été émise sous cette couverture',
            'Une couverture employée par une pièce émise ne s’annule plus : posez une nouvelle couverture datée à l’écran « Assurés & cartes ».');
      }
    }
    return null;
  },
);
