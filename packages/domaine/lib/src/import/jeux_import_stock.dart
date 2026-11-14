// LOT 8, GROUPE STOCK : le stock détail initial, le bon de transfert et le comptage d'inventaire.
//
// Port de `prototype_html/assets/js/modules/import.js` (jeux 13 à 15) ; les vecteurs (`test/vecteurs/import.json`, section `stock`) sont tirés de l'écran réel de la maquette par
// `prototype_html/build/vecteurs-import.js`. Les trois jeux sont RESTREINTS (la déclaration de `rbac.json` le dit) : aucune valeur de cellule ne se recopie à l'historique.
//
// Voie d'un fileul rattaché (aucune règle propre, celle du lot IMP-D) : le stock détail initial et le bon de transfert écrivent `produits` (configuration de la mère) ET sont
// restreints : ils ne s'importent qu'au poste de la mère (`VoieImportFileul.reserveeALaMere`, refus nommé). Le comptage n'écrit que `inventaires` : écriture directe.
// RG-03 : le stock ne devient jamais négatif (ligne par ligne, en nommant l'article). RG-05 : le lot qui part est le premier à périmer. RG-14 : l'annulation archive.
part of 'jeux_import.dart';

typedef _Fiche = Map<String, Object?>;

/// Ce que le magasin sait déjà des articles : actifs par code, premier mouvement actif de chacun, lots actifs par article. Lu UNE fois par analyse.
Map<String, Object?> _contexteStock(PortImport port) {
  final produits = <String, _Fiche>{};
  for (final x in port.actives('produits')) {
    produits[_n(x['code'])] = x;
  }
  final mouvements = <Object?, _Fiche>{};
  for (final m in port.actives('mouvements')) {
    if (m['produitId'] != null && !mouvements.containsKey(m['produitId']))
      mouvements[m['produitId']] = m;
  }
  final lots = <Object?, List<_Fiche>>{};
  for (final l in port.actives('lots')) {
    (lots[l['produitId']] ??= []).add(l);
  }
  return {
    'produits': produits,
    'mouvements': mouvements,
    'lots': lots,
    'jour': port.jour
  };
}

ProblemeImport _articleInconnu(_V v) => _p(
    'Code article',
    v['code'],
    'ARTICLE_INCONNU',
    importRefus,
    'aucun article « ${v['code']} » au référentiel produits',
    'Créez l’article d’abord (jeu « Importation du référentiel produits » ou écran Référentiel produits), ou corrigez le code.');

String _statutLot(String peremption, String jour) {
  final j = importJoursEntre(jour, peremption);
  return j < 0 ? 'perime' : (j < 90 ? 'alerte' : 'actif');
}

/// Les valeurs distinctes non vides d'une colonne, dans l'ordre du fichier.
List<Object?> _distincts(List<LigneImport> lignes, String cle) {
  final vus = <Object?>{};
  final out = <Object?>[];
  for (final l in lignes) {
    final x = l.v[cle];
    if (x != null && x != '' && vus.add(x)) out.add(x);
  }
  return out;
}

/// Le plus grand rang d'une série `PREFIXE` + chiffres, plus un (`C.referenceSuivante`), archivés compris.
String _serie(String prefixe, int largeur, Iterable<_Fiche> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = _s(f['reference']);
    if (r.startsWith(prefixe)) {
      final k = int.tryParse(r.substring(prefixe.length)) ?? 0;
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

// --- 13. STOCK DÉTAIL INITIAL (UNE SEULE FOIS, tant qu'aucun mouvement n'existe) ---------------------------------------------------------

final JeuImport jeuStockDetailInitial = JeuImport(
  id: 'stock-detail-initial',
  ecran: 'imp-stock-detail-initial',
  libelle: 'Importation du stock détail initial',
  module: 'M6',
  statut: 'supporte',
  description:
      'Situation initiale de la pharmacie d’urgence : quantité de chaque article, avec son lot et sa péremption pour un médicament ou un réactif.',
  source:
      'Comptage de la pharmacie d’urgence à la mise en service (décision de la Direction du 11/11/2026 : un stock détail initial est légitime, UNE SEULE FOIS).',
  limite:
      'Un stock détail initial ne se pose qu’UNE FOIS par article, tant qu’aucun mouvement n’existe pour lui (comme le Grand Stock) : ensuite le détail naît d’un transfert du magasin central. '
      'Il est refusé si l’article porte déjà du stock détail ou si ses stocks gros et détail ne s’additionnent pas déjà au stock total.',
  cibles: const ['produits', 'lots', 'mouvements'],
  fichierModele: 'modele-import-stock-detail-initial',
  colonnes: [
    _oblig('code', 'Code article', 'texte',
        longueurMax: 24,
        exemple: 'PARA500',
        aide:
            'Un article déjà connu du référentiel produits. Une ligne par lot : le même code peut figurer plusieurs fois avec des lots différents.'),
    _col('lot', 'N° de lot', 'texte',
        longueurMax: 40,
        exemple: 'L2026-014',
        aide:
            'Obligatoire pour les médicaments et réactifs (rangement FEFO, RG-05).'),
    _col('peremption', 'Date de péremption', 'date', exemple: '2028-06-30'),
    _oblig('quantite', 'Quantité', 'entier',
        min: 0,
        exemple: 40,
        aide: 'Quantité de CE lot, au détail. Jamais négative (RG-03).',
        sousMin: const SousMinImport(
            'RG03_STOCK_NEGATIF',
            'quantité négative : le stock ne peut jamais être négatif (RG-03)',
            'Saisissez la quantité réellement comptée, zéro ou plus.')),
  ],
  contexte: _contexteStock,
  cle: (v) => ['${_n(v['code'])}|${_n(v['lot'] ?? '')}'],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final p = (ctx['produits'] as Map)[_n(v['code'])] as _Fiche?;
    if (p == null) return [_articleInconnu(v)];
    final pb = <ProblemeImport>[];
    final mv = (ctx['mouvements'] as Map)[p['id']] as _Fiche?;
    if (mv != null) {
      pb.add(_p(
          'Code article',
          v['code'],
          'DETAIL_DEJA_MOUVEMENTE',
          importRefus,
          'l’article « ${p['designation']} » a déjà un mouvement de stock (${mv['reference']}, ${mv['typeLabel']}) : un stock détail initial ne se pose qu’une fois, tant qu’aucun mouvement n’existe',
          'Constituez le détail par un transfert du magasin central, ou corrigez-le par un inventaire du stock détail.'));
    } else if (_num(p['stockDetail']) > 0) {
      pb.add(_p(
          'Code article',
          v['code'],
          'DETAIL_DEJA_EN_STOCK',
          importRefus,
          'l’article « ${p['designation']} » porte déjà ${nombre(p['stockDetail'])} ${_s(p['unite'])} au détail : le stock initial ne se pose pas sur un stock existant',
          'Corrigez le stock détail par un inventaire, pas par un second stock initial.'));
    }
    if (_num(p['stock']) != _num(p['stockGros']) + _num(p['stockDetail'])) {
      pb.add(_p(
          'Code article',
          v['code'],
          'STOCK_INCOHERENT',
          importRefus,
          'les stocks gros (${nombre(_num(p['stockGros']))}) et détail (${nombre(_num(p['stockDetail']))}) de « ${p['designation']} » ne s’additionnent pas au stock total (${nombre(_num(p['stock']))}) : un stock détail ne se pose pas sur une fiche incohérente',
          'Corrigez la fiche de l’article par un inventaire du magasin central, puis recommencez.'));
    }
    final lot = v['lot'], per = v['peremption'] as String?;
    if (_perissables.contains(p['categorie']) && (lot == null || per == null)) {
      pb.add(_p(
          lot == null ? 'N° de lot' : 'Date de péremption',
          '',
          'LOT_OBLIGATOIRE',
          importRefus,
          'un ${p['categorie'] == 'reactif' ? 'réactif' : 'médicament'} sans lot ni péremption ne peut pas se ranger en FEFO (RG-05)',
          'Renseignez le numéro de lot ET la date de péremption relevés sur la boîte.'));
    } else if ((lot != null && per == null) || (lot == null && per != null)) {
      pb.add(_p(
          lot == null ? 'N° de lot' : 'Date de péremption',
          '',
          'LOT_INCOMPLET',
          importRefus,
          'le lot et sa péremption vont ensemble : l’un est renseigné, l’autre non',
          'Renseignez les deux colonnes, ou laissez-les vides toutes les deux.'));
    }
    final qte = _num(v['quantite']);
    if (per != null && per.compareTo(ctx['jour'] as String) < 0 && qte > 0) {
      pb.add(_p(
          'Date de péremption',
          per,
          'PEREMPTION_PASSEE',
          importAvertissement,
          'le lot est déjà périmé au $per',
          'Le lot sera créé « périmé » pour être retiré du stock ; vérifiez la date saisie.'));
    }
    if (qte == 0)
      pb.add(_p(
          'Quantité',
          0,
          'QUANTITE_NULLE',
          importAvertissement,
          'quantité nulle : la ligne n’écrit rien',
          'Retirez-la du fichier si ce n’est pas voulu.'));
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    final jour = port.jour;
    final mouvs = <_V>[...port.toutes('mouvements')];
    final totaux = <Object?, num>{};
    final ordre = <_Fiche>[];
    for (final l in lignes) {
      final v = l.v;
      final p = (ctx['produits'] as Map)[_n(v['code'])] as _Fiche;
      final q = _num(v['quantite']);
      if (q == 0) continue;
      if (v['lot'] != null) {
        ecrireFiche('lots', {
          'produitId': p['id'],
          'produit': p['designation'],
          'numeroLot': v['lot'],
          'datePeremption': v['peremption'],
          'quantiteRestante': q,
          'emplacement': p['emplacement'] ?? '',
          'magasin': 'detail',
          'statut': _statutLot('${v['peremption']}', jour),
        });
      }
      final ref = _referenceMouvement(mouvs);
      mouvs.add({'reference': ref});
      ecrireFiche('mouvements', {
        'reference': ref,
        'date': jour,
        'produitId': p['id'],
        'produit': p['designation'],
        'type': 'entree',
        'typeLabel': 'Entrée',
        'quantite': q,
        'stockType': 'detail',
        'justificatif':
            'Import ${lot['reference']} (stock détail initial${v['lot'] != null ? ', lot ${v['lot']}' : ''})',
        'utilisateur': port.utilisateur,
      });
      if (!totaux.containsKey(p['id'])) {
        totaux[p['id']] = 0;
        ordre.add(p);
      }
      totaux[p['id']] = totaux[p['id']]! + q;
    }
    // Les compteurs en DERNIER : une fiche mise à jour ne se retire pas avec le reste de l'atomicité du moteur, elle se restitue ici (comme la maquette).
    final faits = <(Object?, _Fiche)>[];
    try {
      for (final p in ordre) {
        final fraiche = port.parId('produits', p['id'])!;
        final avant = {
          'stockDetail': _num(fraiche['stockDetail']),
          'stock': _num(fraiche['stock'])
        };
        port.mettreAJour('produits', p['id'], {
          'stockDetail': avant['stockDetail']! + totaux[p['id']]!,
          'stock': avant['stock']! + totaux[p['id']]!
        });
        faits.add((p['id'], avant));
      }
    } catch (e) {
      for (final f in faits.reversed) {
        port.mettreAJour('produits', f.$1, f.$2);
      }
      rethrow;
    }
  },
  dependances: (lot, port) {
    final ecrits = (lot['ecrits'] as List).cast<Map>();
    final propres = {
      for (final e in ecrits)
        if (e['collection'] == 'mouvements') e['id']
    };
    final ids = <Object?>{};
    for (final e in ecrits) {
      if (e['collection'] != 'mouvements') continue;
      final m = port.parId('mouvements', e['id']);
      if (m != null) ids.add(m['produitId']);
    }
    final autre = port
        .actives('mouvements')
        .where(
            (m) => ids.contains(m['produitId']) && !propres.contains(m['id']))
        .firstOrNull;
    if (autre == null) return null;
    return DependanceImport(
        'MOUVEMENT_POSTERIEUR',
        'l’article « ${autre['produit']} » a déjà un mouvement de stock postérieur (${autre['reference']}, ${autre['typeLabel']})',
        'Annulez d’abord ce mouvement, ou régularisez le stock détail par un inventaire : le lot ne peut pas être retiré sous un stock vivant (RG-03).');
  },
  // L'ANNULATION ARCHIVE les lots et les mouvements du lot (RG-14) et RESTITUE les compteurs ; le détail ne peut jamais redescendre sous zéro (RG-03).
  annuler: (lot, motif, port) {
    final qte = <Object?, num>{};
    final aArchiver = <Map>[];
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final f = port.parId('${e['collection']}', e['id']);
      if (f == null || f['statut'] == 'archive') continue;
      aArchiver.add(e);
      if (e['collection'] == 'mouvements')
        qte[f['produitId']] = (qte[f['produitId']] ?? 0) + _num(f['quantite']);
    }
    for (final id in qte.keys) {
      final p = port.parId('produits', id);
      if (p == null || _num(p['stockDetail']) < qte[id]!) {
        return ResultatAnnulationImport.refus(
            'DETAIL_DEJA_DISPENSE',
            'l’article « ${p != null ? p['designation'] : id} » n’a plus assez de stock détail pour retirer le stock initial (RG-03)',
            'Régularisez le stock détail par un inventaire.');
      }
    }
    final motifArchivage =
        'Annulation du lot ${lot['reference']}${motif != null && motif.isNotEmpty ? ' : $motif' : ''}';
    final faits = <Map>[];
    for (final e in aArchiver) {
      if (!port.archiver('${e['collection']}', e['id'], motifArchivage)) {
        for (final x in faits) {
          port.restaurer('${x['collection']}', x['id']);
        }
        return ResultatAnnulationImport.refus(
            'ARCHIVAGE_REFUSE',
            'le moteur a refusé d’archiver une fiche de « ${e['collection']} »',
            'Rien n’a été annulé.');
      }
      faits.add(e);
    }
    for (final id in qte.keys) {
      final p = port.parId('produits', id)!;
      port.mettreAJour('produits', id, {
        'stockDetail': _num(p['stockDetail']) - qte[id]!,
        'stock': _max0(_num(p['stock']) - qte[id]!)
      });
    }
    return ResultatAnnulationImport.ok(faits.length);
  },
);

num _max0(num x) => x < 0 ? 0 : x;

// --- 14. BON DE TRANSFERT : UNE FEUILLE = UN BON NEUF --------------------------------------------------------------------------------------

/// RG-03 pour UNE ligne : [deja] est ce qui est déjà posé sur le bon pour cet article. Rend un refus nommé, ou `null` (`PR.refusLigneTransfert`).
({String code, String motif, String geste})? _refusLigne(
    _Fiche pr, num q, num deja) {
  if (!(q > 0) || q.floor() != q) {
    return (
      code: 'QUANTITE_INVALIDE',
      motif:
          '« ${pr['designation']} » : la quantité doit être un entier supérieur à zéro',
      geste: 'Indiquer une quantité entière d’au moins 1.'
    );
  }
  final dispo = _num(pr['stockGros']) - deja;
  if (q > dispo) {
    return (
      code: 'RG03_STOCK_INSUFFISANT',
      motif:
          'RG-03 : « ${pr['designation']} » : ${nombre(dispo < 0 ? 0 : dispo)} ${_s(pr['unite'])} encore disponible(s) au magasin${deja != 0 ? ' (déjà ${nombre(deja)} sur ce bon)' : ''}, ${nombre(q)} demandé(s)',
      geste:
          'Réduire la quantité, ou attendre une réception fournisseur : le stock du magasin ne peut jamais devenir négatif.'
    );
  }
  return null;
}

/// Le lot à sortir en premier (FEFO, RG-05) : péremption la plus proche, ni périmé ni épuisé, et tenu au magasin CENTRAL (un lot posé au détail par un stock initial ne part pas du gros).
/// Un lot à péremption égale garde l'ordre du magasin (tri stable de la maquette).
_Fiche? _lotFefo(Object? produitId, Map ctx) {
  _Fiche? premier;
  for (final x
      in (ctx['lots'] as Map)[produitId] as List<_Fiche>? ?? const <_Fiche>[]) {
    if (x['statut'] == 'perime' ||
        !(_num(x['quantiteRestante']) > 0) ||
        x['magasin'] == 'detail') continue;
    if (premier == null ||
        '${x['datePeremption']}'.compareTo('${premier['datePeremption']}') < 0)
      premier = x;
  }
  return premier;
}

final JeuImport jeuTransfertLignes = JeuImport(
  id: 'transfert-lignes',
  ecran: 'imp-transfert-lignes',
  libelle: 'Importation d’un bon de transfert',
  module: 'M6',
  statut: 'supporte',
  description:
      'Un bon de transfert du magasin central vers la pharmacie de détail : une ligne par article (et par lot), un service destinataire pour tout le fichier.',
  source:
      'Bon de transfert de l’écran « Transferts gros → détail » : même numérotation, mêmes mouvements, mêmes stocks.',
  limite:
      'Une feuille crée UN bon neuf, par la MÊME fabrique que le geste de l’écran : un bon numéroté APRÈS la vérification, deux mouvements symétriques par ligne, stocks gros et détail. '
      'RG-03 se contrôle ligne par ligne en nommant l’article, en tenant compte des lignes déjà posées sur le bon ; le lot est celui qui part en premier (FEFO, RG-05) : un lot précisé qui n’est pas le premier est refusé. '
      'Le service, la date et le motif sont uniques pour tout le fichier.',
  cibles: const ['transferts', 'mouvements', 'produits'],
  fichierModele: 'modele-import-transfert-lignes',
  colonnes: [
    _oblig('code', 'Code article', 'texte',
        longueurMax: 24,
        exemple: 'PARA500',
        aide:
            'Un article connu du référentiel, déjà en stock au magasin central.'),
    _col('lot', 'N° de lot', 'texte',
        longueurMax: 40,
        exemple: 'L2026-014',
        aide:
            'Vide : le lot qui part en premier (FEFO) est retenu. Précisé : il doit être celui-là.'),
    _oblig('quantite', 'Quantité', 'entier',
        min: 0,
        exemple: 20,
        aide:
            'Quantité transférée au détail, au plus ce que le magasin central détient (RG-03).',
        sousMin: const SousMinImport(
            'RG03_STOCK_NEGATIF',
            'quantité négative : un transfert ne peut pas retirer du stock au détail (RG-03)',
            'Saisissez une quantité entière supérieure à zéro.')),
    _col('destination', 'Service destinataire', 'liste',
        liste: _fixe(importDestinationsTransfert),
        exemple: 'Pharmacie d’urgence',
        aide:
            'Le même pour toutes les lignes du fichier : une feuille est un seul bon.'),
    _col('date', 'Date du transfert', 'date',
        aide: 'Vide : aujourd’hui. La même pour toutes les lignes.'),
    _col('motif', 'Motif', 'texte',
        longueurMax: 160, aide: 'Le même pour toutes les lignes.'),
  ],
  contexte: _contexteStock,
  cle: (v) => ['${_n(v['code'])}|${_n(v['lot'] ?? '')}'],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final p = (ctx['produits'] as Map)[_n(v['code'])] as _Fiche?;
    if (p == null) return [_articleInconnu(v)];
    final pb = <ProblemeImport>[];
    final pose = sc['pose'] as Map<Object?, num>;
    final q = _num(v['quantite']);
    final date = v['date'] as String?;
    if (date != null && date.compareTo(ctx['jour'] as String) > 0) {
      pb.add(_p(
          'Date du transfert',
          date,
          'DATE_FUTURE',
          importRefus,
          'la date du transfert est dans le futur',
          'Saisissez la date du jour ou une date passée.'));
    }
    if (q == 0) {
      pb.add(_p(
          'Quantité',
          0,
          'QUANTITE_NULLE',
          importRefus,
          'un transfert de zéro n’est pas un transfert',
          'Retirez la ligne ou saisissez une quantité d’au moins 1.'));
    } else {
      // RG-03 LIGNE PAR LIGNE : le disponible tient compte de ce que les lignes précédentes ont déjà posé sur le bon.
      final r = _refusLigne(p, q, pose[p['id']] ?? 0);
      if (r != null)
        pb.add(_p(
            'Quantité', v['quantite'], r.code, importRefus, r.motif, r.geste));
      pose[p['id']] = (pose[p['id']] ?? 0) + q;
    }
    _Fiche? retenu;
    final fefo = _lotFefo(p['id'], ctx);
    final lotCell = v['lot'];
    if (lotCell != null) {
      final l =
          ((ctx['lots'] as Map)[p['id']] as List<_Fiche>? ?? const <_Fiche>[])
              .where((x) => _n(x['numeroLot']) == _n(lotCell))
              .firstOrNull;
      if (l == null) {
        pb.add(_p(
            'N° de lot',
            lotCell,
            'LOT_INCONNU',
            importRefus,
            'aucun lot « $lotCell » pour l’article « ${p['designation']} »',
            'Corrigez le numéro de lot, ou laissez la colonne vide pour retenir le lot FEFO.'));
      } else if (l['statut'] == 'perime') {
        pb.add(_p(
            'N° de lot',
            lotCell,
            'LOT_PERIME',
            importRefus,
            'le lot « $lotCell » est périmé : il ne se transfère pas',
            'Retirez-le du stock par une perte déclarée, puis transférez un lot valide.'));
      } else if (fefo != null && fefo['numeroLot'] != l['numeroLot']) {
        pb.add(_p(
            'N° de lot',
            lotCell,
            'LOT_NON_FEFO',
            importRefus,
            'le lot « $lotCell » n’est pas le premier à sortir : le lot « ${fefo['numeroLot']} » (péremption ${fefo['datePeremption']}) part avant lui (FEFO, RG-05)',
            'Laissez la colonne « N° de lot » vide pour retenir le lot FEFO, ou précisez-le.'));
      } else {
        retenu = l;
      }
    } else {
      retenu = fefo;
    }
    final dejaPose = (pose[p['id']] ?? 0) - q;
    (sc['extras'] as Map<int, String>)[n] =
        'Disponible au magasin avant la ligne : ${nombre((_num(p['stockGros']) - dejaPose) < 0 ? 0 : _num(p['stockGros']) - dejaPose)} ${_s(p['unite'])}'
        '${retenu != null ? ' · lot retenu : ${retenu['numeroLot']} (péremption ${retenu['datePeremption']})' : ' · aucun lot recensé'}';
    return pb;
  },
  reglesLot: (lignes, ctx) {
    final pb = <ProblemeImport>[];
    final dest = _distincts(lignes, 'destination'),
        dates = _distincts(lignes, 'date'),
        motifs = _distincts(lignes, 'motif');
    if (dest.isEmpty) {
      pb.add(_p(
          'Service destinataire',
          '',
          'DESTINATION_ABSENTE',
          importRefus,
          'aucune ligne ne nomme le service destinataire : un bon a une destination',
          'Renseignez la colonne « Service destinataire » sur au moins une ligne.'));
    }
    if (dest.length > 1) {
      pb.add(_p(
          'Service destinataire',
          dest.join(', '),
          'DESTINATIONS_MULTIPLES',
          importRefus,
          'le fichier porte ${dest.length} services destinataires : une feuille est UN bon, pour UN service',
          'Faites un fichier par service destinataire.'));
    }
    if (dates.length > 1) {
      pb.add(_p(
          'Date du transfert',
          dates.join(', '),
          'BON_UNIQUE',
          importRefus,
          'le fichier porte ${dates.length} dates : une feuille est UN bon, à une seule date',
          'Alignez toutes les lignes sur la même date, ou laissez la colonne vide.'));
    }
    if (motifs.length > 1) {
      pb.add(_p(
          'Motif',
          motifs.join(', '),
          'BON_UNIQUE',
          importRefus,
          'le fichier porte ${motifs.length} motifs : une feuille est UN bon, avec un seul motif',
          'Alignez les lignes sur le même motif, ou laissez la colonne vide.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    final dest = '${_distincts(lignes, 'destination').first}';
    final dates = _distincts(lignes, 'date'),
        motifs = _distincts(lignes, 'motif');
    final date = dates.isEmpty ? port.jour : '${dates.first}',
        motif = motifs.isEmpty ? '' : '${motifs.first}';
    // La MÊME règle que le geste de l'écran : RG-03 d'abord (rien n'est écrit si une ligne est refusée), numéro du bon APRÈS la vérification, stocks, mouvements, bon.
    final pose = <Object?, num>{};
    final pleines = <_Fiche>[];
    for (final l in lignes) {
      final p = (ctx['produits'] as Map)[_n(l.v['code'])] as _Fiche;
      final q = _num(l.v['quantite']);
      final r = _refusLigne(p, q, pose[p['id']] ?? 0);
      if (r != null) throw StateError(r.motif);
      pose[p['id']] = (pose[p['id']] ?? 0) + q;
      final lotCell = l.v['lot'];
      final lotF = lotCell == null
          ? _lotFefo(p['id'], ctx)
          : port
              .actives('lots')
              .where(
                  (x) => x['produitId'] == p['id'] && x['numeroLot'] == lotCell)
              .firstOrNull;
      pleines.add({
        'produitId': p['id'],
        'code': p['code'],
        'produit': p['designation'],
        'categorie': p['categorie'],
        'unite': p['unite'],
        'cump': p['cump'],
        'quantite': q,
        'lot': lotF?['numeroLot'],
        'peremption': lotF?['datePeremption'],
      });
    }
    final reference = _serie('TR-', 5, port.toutes('transferts'));
    final marque = {
      'source': 'Import Importation d’un bon de transfert',
      'lotImport': lot['reference'],
      'validePar': port.utilisateur,
      'dateImport': port.jour
    };
    // Les stocks se restituent dans l'ORDRE INVERSE si une écriture échoue (le même article peut figurer sur deux lignes de lots différents).
    final etats = <(Object?, _Fiche)>[];
    try {
      for (final pl in pleines) {
        final pr = port.parId('produits', pl['produitId'])!;
        final q = _num(pl['quantite']);
        etats.add((
          pr['id'],
          {'stockGros': pr['stockGros'], 'stockDetail': pr['stockDetail']}
        ));
        port.mettreAJour('produits', pr['id'], {
          'stockGros': _num(pr['stockGros']) - q,
          'stockDetail': _num(pr['stockDetail']) + q
        });
        // DEUX MOUVEMENTS SYMÉTRIQUES (RG-03) : le magasin débité, la pharmacie créditée.
        for (final t in const [
          ('Transfert — sortie magasin', 'gros'),
          ('Transfert — entrée pharmacie', 'detail')
        ]) {
          ecrireFiche('mouvements', {
            'reference': reference,
            'date': date,
            'produitId': pr['id'],
            'produit': pr['designation'],
            'type': 'transfert',
            'typeLabel': t.$1,
            'quantite': q,
            'stockType': t.$2,
            'justificatif': 'Bon de transfert $reference',
            'utilisateur': port.utilisateur,
            ...marque,
          });
        }
      }
      final total = pleines.fold<num>(0, (n, l) => n + _num(l['quantite']));
      ecrireFiche('transferts', {
        'date': date,
        'demandeur': dest,
        'motif': motif,
        ...marque,
        'reference': reference,
        'lignes': pleines,
        'nbLignes': pleines.length,
        'quantiteTotale': total,
        'valeur': pleines.fold<num>(
            0, (n, l) => n + _num(l['quantite']) * _num(l['cump'])),
        'operateur': port.utilisateur,
        'etat': 'receptionne',
        'dateReception': date,
        'produit': pleines.length == 1
            ? pleines.first['produit']
            : '${pleines.length} articles',
        'unite': pleines.length == 1 ? pleines.first['unite'] : '',
        'quantite': total,
      });
    } catch (e) {
      for (final x in etats.reversed) {
        port.mettreAJour('produits', x.$1, x.$2);
      }
      rethrow;
    }
  },
  dependances: (lot, port) => null,
  // L'ANNULATION RESTITUE LES STOCKS : le gros retrouve ce qui est parti, le détail rend ce qu'il a reçu, et ne peut pas descendre sous zéro (RG-03).
  annuler: (lot, motif, port) {
    _Fiche? bon;
    final mouvs = <_Fiche>[];
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final f = port.parId('${e['collection']}', e['id']);
      if (f == null || f['statut'] == 'archive') continue;
      if (e['collection'] == 'transferts') {
        bon = f;
      } else if (e['collection'] == 'mouvements') {
        mouvs.add(f);
      }
    }
    if (bon == null)
      return const ResultatAnnulationImport.refus('LOT_SANS_BON',
          'le bon de transfert de ce lot est déjà archivé', 'Aucune action.');
    final rendre = <Object?, num>{};
    for (final l in (bon['lignes'] as List).cast<Map>()) {
      rendre[l['produitId']] =
          (rendre[l['produitId']] ?? 0) + _num(l['quantite']);
    }
    for (final id in rendre.keys) {
      final p = port.parId('produits', id);
      if (p == null || _num(p['stockDetail']) < rendre[id]!) {
        return ResultatAnnulationImport.refus(
            'TRANSFERT_DEJA_DISPENSE',
            'l’article « ${p != null ? p['designation'] : id} » n’a plus assez de stock détail pour rendre ce transfert (${nombre(rendre[id])} à rendre, ${nombre(p != null ? _num(p['stockDetail']) : 0)} au détail) : une partie a déjà été dispensée (RG-03)',
            'Régularisez le stock détail par un inventaire, ou annulez d’abord les dispensations.');
      }
    }
    final motifArchivage =
        'Annulation du lot ${lot['reference']}${motif != null && motif.isNotEmpty ? ' : $motif' : ''}';
    final cibles = <(String, Object?)>[
      ('transferts', bon['id']),
      for (final m in mouvs) ('mouvements', m['id'])
    ];
    final faits = <(String, Object?)>[];
    for (final c in cibles) {
      if (!port.archiver(c.$1, c.$2, motifArchivage)) {
        for (final x in faits) {
          port.restaurer(x.$1, x.$2);
        }
        return ResultatAnnulationImport.refus(
            'ARCHIVAGE_REFUSE',
            'le moteur a refusé d’archiver une fiche de « ${c.$1} »',
            'Rien n’a été annulé.');
      }
      faits.add(c);
    }
    for (final id in rendre.keys) {
      final p = port.parId('produits', id)!;
      port.mettreAJour('produits', id, {
        'stockGros': _num(p['stockGros']) + rendre[id]!,
        'stockDetail': _num(p['stockDetail']) - rendre[id]!
      });
    }
    return ResultatAnnulationImport.ok(faits.length);
  },
);

// --- 15. COMPTAGE D'INVENTAIRE : crée la feuille, ne régularise JAMAIS ---------------------------------------------------------------------

String _libelleMagasin(Object? m) => m == 'detail'
    ? 'Stock détail (pharmacie d’urgence)'
    : 'Stock gros (magasin central)';

final JeuImport jeuInventaireComptage = JeuImport(
  id: 'inventaire-comptage',
  ecran: 'imp-inventaire-comptage',
  libelle: 'Importation d’un comptage d’inventaire',
  module: 'M6',
  statut: 'supporte',
  description:
      'Un comptage physique déjà fait : une ligne par article et par magasin nommé (gros ou détail), avec la quantité comptée.',
  source:
      'Feuille d’inventaire de l’écran « Inventaires » : même magasin nommé, même écart calculé du stock théorique de CE magasin.',
  limite:
      'L’import crée une feuille d’inventaire « comptage importé » et NE TOUCHE À AUCUN STOCK : la régularisation reste un geste humain, au registre des inventaires (un mouvement par écart, RG-03). '
      'Les deux magasins se comptent séparément : une feuille par magasin nommé. Si le stock a bougé entre le comptage et la régularisation, celle-ci est refusée.',
  cibles: const ['inventaires'],
  fichierModele: 'modele-import-inventaire-comptage',
  colonnes: [
    _oblig('magasin', 'Magasin', 'liste',
        liste: (_) =>
            [for (final m in importMagasinsInventaire) ValeurListe(m[0], m[1])],
        exemple: 'Stock gros',
        aide:
            'Gros ou détail seulement : un article ne porte pas d’autre stock.'),
    _oblig('code', 'Code article', 'texte',
        longueurMax: 24, exemple: 'PARA500'),
    _oblig('compte', 'Quantité comptée', 'entier',
        min: 0,
        exemple: 118,
        aide:
            'Le stock physique compté dans CE magasin. Jamais négative (RG-03).',
        sousMin: const SousMinImport(
            'RG03_STOCK_NEGATIF',
            'quantité comptée négative : un stock physique ne peut pas être négatif (RG-03)',
            'Saisissez la quantité réellement comptée, zéro ou plus.')),
    _col('type', 'Type d’inventaire', 'liste',
        liste: _fixe(importTypesInventaire),
        exemple: 'Ponctuel',
        aide: 'Vide : Ponctuel. Le même pour toutes les lignes d’un magasin.'),
    _col('date', 'Date du comptage', 'date',
        aide:
            'Vide : aujourd’hui. La même pour toutes les lignes d’un magasin.'),
  ],
  contexte: _contexteStock,
  cle: (v) => ['${v['magasin']}|${_n(v['code'])}'],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final p = (ctx['produits'] as Map)[_n(v['code'])] as _Fiche?;
    if (p == null) return [_articleInconnu(v)];
    final pb = <ProblemeImport>[];
    final theo =
            _num(v['magasin'] == 'detail' ? p['stockDetail'] : p['stockGros']),
        compte = _num(v['compte']),
        ecart = compte - theo;
    final date = v['date'] as String?;
    if (date != null && date.compareTo(ctx['jour'] as String) > 0) {
      pb.add(_p(
          'Date du comptage',
          date,
          'DATE_FUTURE',
          importRefus,
          'la date du comptage est dans le futur',
          'Saisissez la date du comptage réel.'));
    }
    (sc['extras'] as Map<int, String>)[n] =
        '${_libelleMagasin(v['magasin'])} : théorique ${nombre(theo)}, compté ${nombre(compte)}, écart ${ecart > 0 ? '+' : ''}${nombre(ecart)}';
    return pb;
  },
  reglesLot: (lignes, ctx) {
    final pb = <ProblemeImport>[];
    for (final m in const ['gros', 'detail']) {
      final ls = [
        for (final l in lignes)
          if (l.v['magasin'] == m) l
      ];
      if (ls.isEmpty) continue;
      final types = _distincts(ls, 'type'), dates = _distincts(ls, 'date');
      if (types.length > 1) {
        pb.add(_p(
            'Type d’inventaire',
            types.join(', '),
            'FEUILLE_UNIQUE',
            importRefus,
            'les lignes du ${_libelleMagasin(m).toLowerCase()} portent ${types.length} types d’inventaire : une feuille a un seul type',
            'Alignez les lignes de ce magasin sur le même type, ou laissez la colonne vide.'));
      }
      if (dates.length > 1) {
        pb.add(_p(
            'Date du comptage',
            dates.join(', '),
            'FEUILLE_UNIQUE',
            importRefus,
            'les lignes du ${_libelleMagasin(m).toLowerCase()} portent ${dates.length} dates : une feuille est un seul comptage',
            'Alignez les lignes de ce magasin sur la même date, ou laissez la colonne vide.'));
      }
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port, declarer) {
    for (final m in const ['gros', 'detail']) {
      final ls = [
        for (final l in lignes)
          if (l.v['magasin'] == m) l
      ];
      if (ls.isEmpty) continue;
      final types = _distincts(ls, 'type'), dates = _distincts(ls, 'date');
      final type = types.isEmpty ? 'Ponctuel' : '${types.first}',
          date = dates.isEmpty ? port.jour : '${dates.first}';
      final corps = <_Fiche>[];
      for (final l in ls) {
        final p = (ctx['produits'] as Map)[_n(l.v['code'])] as _Fiche;
        final theo = _num(m == 'detail' ? p['stockDetail'] : p['stockGros']);
        final e = _num(l.v['compte']) - theo;
        corps.add({
          'produitId': p['id'],
          'code': p['code'],
          'designation': p['designation'],
          'unite': p['unite'],
          'theorique': theo,
          'physique': l.v['compte'],
          'ecart': e,
          'cump': p['cump'],
          'valeur': e * _num(p['cump'])
        });
      }
      final ecarts = [
        for (final x in corps)
          if (_num(x['ecart']) != 0) x
      ];
      ecrireFiche('inventaires', {
        'reference': _serie('INV-', 4, port.toutes('inventaires')),
        'date': date,
        'type': type,
        'perimetre':
            'Comptage importé (${corps.length} article${corps.length > 1 ? 's' : ''})',
        'magasin': m,
        'magasinLabel': _libelleMagasin(m),
        'operateur': port.utilisateur,
        'statutInv': 'importe',
        'nbArticles': corps.length,
        'nbEcarts': ecarts.length,
        'valeurEcart': ecarts.fold<num>(0, (t, x) => t + _num(x['valeur'])),
        'lignes': corps,
      });
    }
  },
  dependances: (lot, port) {
    _Fiche? regularisee;
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final f = port.parId('inventaires', e['id']);
      if (f != null && f['statutInv'] == 'valide') {
        regularisee = f;
        break;
      }
    }
    if (regularisee == null) return null;
    return DependanceImport(
        'INVENTAIRE_REGULARISE',
        'la feuille ${regularisee['reference']} a été régularisée : des mouvements de stock s’appuient sur elle',
        'Annulez d’abord la régularisation par un inventaire inverse : un lot ne peut pas être retiré sous un stock régularisé (RG-03).');
  },
);
