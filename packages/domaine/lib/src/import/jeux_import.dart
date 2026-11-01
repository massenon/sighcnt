/// LES DIX JEUX D'IMPORT : port de la déclaration `JEUX` de la maquette (prototype_html/assets/js/modules/import.js).
///
/// Aucun jeu n'invente une donnée : les colonnes sont celles des collections existantes, les référentiels de contrôle viennent du magasin
/// (assureurs, fournisseurs, plan comptable) ou de `donnees_import.dart` (engendré depuis la maquette). Un jeu « proposition à valider » écrit
/// une donnée incomplète et le dit. Les vecteurs de la maquette (`test/vecteurs/import.json`) rejouent chaque règle.
library;

import '../format/recherche.dart' show normaliser;
import 'donnees_import.dart';
import 'moteur_import.dart';

typedef _V = Map<String, Object?>;

String _n(Object? s) => normaliser(s);

ColonneImport _col(String cle, String label, String type,
        {bool obligatoire = false,
        List<ValeurListe> Function(dynamic ctx)? liste,
        num? min,
        num? max,
        int? longueurMax,
        RegExp? motif,
        String? motifTexte,
        Object? exemple,
        String? aide,
        SousMinImport? sousMin}) =>
    ColonneImport(cle, label, type,
        obligatoire: obligatoire,
        liste: liste,
        min: min,
        max: max,
        longueurMax: longueurMax,
        motif: motif,
        motifTexte: motifTexte,
        exemple: exemple,
        aide: aide,
        sousMin: sousMin);

ColonneImport _oblig(String cle, String label, String type,
        {List<ValeurListe> Function(dynamic ctx)? liste,
        num? min,
        num? max,
        int? longueurMax,
        RegExp? motif,
        String? motifTexte,
        Object? exemple,
        String? aide,
        SousMinImport? sousMin}) =>
    _col(cle, label, type,
        obligatoire: true, liste: liste, min: min, max: max, longueurMax: longueurMax, motif: motif, motifTexte: motifTexte, exemple: exemple, aide: aide, sousMin: sousMin);

List<ValeurListe> Function(dynamic) _fixe(List<String> valeurs) => (_) => [for (final v in valeurs) ValeurListe(v)];
ProblemeImport _p(String colonne, Object? valeur, String code, String niveau, String motif, String geste) => constat(colonne, valeur, code, niveau, motif, geste);
List<ProblemeImport> _aucun(_V v, dynamic ctx, _V sc, int n) => const [];

num _num(Object? x) => (x as num?) ?? 0;
String _s(Object? x) => x == null ? '' : '$x';

// --- 1. GRAND STOCK ----------------------------------------------------------------------------------------------------------------

const _perissables = ['medicament', 'reactif'];

final JeuImport jeuGrandStock = JeuImport(
  id: 'grand-stock',
  ecran: 'm6-import-grand-stock',
  libelle: 'Importation Grand Stock',
  module: 'M6',
  statut: 'supporte',
  roles: const ['stock', 'da', 'admin', 'direction'],
  description: 'Situation initiale du magasin central : articles, lots, péremptions, quantités et prix de revient (inventaire SAGE « Grand Stock »).',
  source: 'Inventaire SAGE 100 « Grand Stock » du 15/07/2026 (docs/) : 184 articles, 12 080 unités, 3 976 459 FCFA.',
  cibles: const ['produits', 'lots', 'mouvements'],
  fichierModele: 'modele-import-grand-stock',
  gesteExiste: 'Retirez la ligne du fichier, ou archivez d’abord l’article existant (RG-14). Un import ne modifie jamais un article déjà tenu.',
  colonnes: [
    _oblig('code', 'Code article', 'texte', longueurMax: 24, exemple: 'PARA500', aide: 'Référence SAGE de l’article. Une ligne par lot : le même code peut figurer plusieurs fois avec des lots différents.'),
    _oblig('designation', 'Désignation', 'texte', longueurMax: 160, exemple: 'PARACETAMOL 500 MG CP B/100'),
    _oblig('categorie', 'Catégorie', 'liste', liste: (_) => [for (final c in importCategoriesProduit) ValeurListe(c[0], c[1])], exemple: 'Médicaments'),
    _col('unite', 'Unité', 'texte', longueurMax: 30, exemple: 'Boîte', aide: 'Vide : « Unité ».'),
    _oblig('quantite', 'Quantité', 'entier',
        min: 0,
        exemple: 120,
        aide: 'Quantité de CE lot. Jamais négative (RG-03).',
        sousMin: const SousMinImport('RG03_STOCK_NEGATIF', 'quantité négative : le stock ne peut jamais être négatif (RG-03)',
            'Saisissez la quantité réellement comptée, zéro ou plus. Une sortie se déclare au mouvement de stock, pas à l’import.')),
    _col('lot', 'N° de lot', 'texte', longueurMax: 40, exemple: 'L2026-014', aide: 'Obligatoire pour les médicaments et réactifs (rangement FEFO, RG-05).'),
    _col('peremption', 'Date de péremption', 'date', exemple: '2028-06-30'),
    _col('prixRevient', 'Prix de revient unitaire', 'entier', min: 0, exemple: 350, aide: 'En francs CFA. Vide : l’article est créé « à valoriser » et le dit (aucun prix n’est inventé).'),
    _col('seuil', 'Seuil d’alerte', 'entier', min: 0, exemple: 20, aide: 'Vide : proposé à 20 % de la quantité (minimum 5), marqué « à valider ».'),
    _col('emplacement', 'Emplacement', 'texte', longueurMax: 60, exemple: 'Rayon A, Casier 3'),
    _col('fournisseur', 'Code fournisseur', 'texte', longueurMax: 24, exemple: 'SOBAPS', aide: 'Code d’un fournisseur connu. Un code inconnu est signalé, jamais refusé.'),
  ],
  contexte: (port) => {
    'produits': {for (final x in port.toutes('produits')) _n(x['code']): x},
    'fournisseurs': {for (final x in port.actives('fournisseurs')) _n(x['code']): true},
    'jour': port.jour,
  },
  cle: (v) => ['${_n(v['code'])}|${_n(v['lot'] ?? '')}'],
  existe: (v, ctx) {
    final p = (ctx['produits'] as Map)[_n(v['code'])] as _V?;
    return p != null ? 'l’article « ${p['code']} » existe déjà dans le référentiel (${p['designation']})' : null;
  },
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    final lot = v['lot'], per = v['peremption'] as String?;
    final cat = v['categorie'];
    if (_perissables.contains(cat) && (lot == null || per == null)) {
      pb.add(_p(lot == null ? 'N° de lot' : 'Date de péremption', '', 'LOT_OBLIGATOIRE', importRefus,
          'un ${cat == 'reactif' ? 'réactif' : 'médicament'} sans lot ni péremption ne peut pas se ranger en FEFO (RG-05)', 'Renseignez le numéro de lot ET la date de péremption relevés sur la boîte.'));
    } else if ((lot != null && per == null) || (lot == null && per != null)) {
      pb.add(_p(lot == null ? 'N° de lot' : 'Date de péremption', '', 'LOT_INCOMPLET', importRefus, 'le lot et sa péremption vont ensemble : l’un est renseigné, l’autre non',
          'Renseignez les deux colonnes, ou laissez-les vides toutes les deux.'));
    }
    final qte = _num(v['quantite']);
    if (per != null && per.compareTo(ctx['jour'] as String) < 0 && qte > 0) {
      pb.add(_p('Date de péremption', per, 'PEREMPTION_PASSEE', importAvertissement, 'le lot est déjà périmé au $per', 'Le lot sera créé « périmé » pour être retiré du stock ; vérifiez la date saisie.'));
    }
    if (qte == 0) {
      pb.add(_p('Quantité', 0, 'QUANTITE_NULLE', importAvertissement, 'quantité nulle : l’article sera créé sans stock', 'Vérifiez le comptage si ce n’est pas voulu.'));
    }
    if (v['prixRevient'] == null) {
      pb.add(_p('Prix de revient unitaire', '', 'A_VALORISER', importAvertissement, 'prix de revient absent : l’article sera créé « à valoriser »', 'Valorisez-le ensuite à l’écran Reprise SAGE, avec sa source.'));
    }
    final f = v['fournisseur'];
    if (f != null && (ctx['fournisseurs'] as Map)[_n(f)] == null) {
      pb.add(_p('Code fournisseur', f, 'FOURNISSEUR_INCONNU', importAvertissement, 'aucun fournisseur « $f » au référentiel', 'Créez le fournisseur (jeu Fournisseurs) ou corrigez le code.'));
    }
    final k = _n(v['code']);
    final articles = sc['articles'] as Map<String, _V>;
    final ref = articles[k];
    if (ref == null) {
      articles[k] = {'n': n, 'designation': v['designation'], 'categorie': v['categorie'], 'unite': v['unite'] ?? 'Unité', 'prix': v['prixRevient']};
    } else if (ref['designation'] != v['designation'] || ref['categorie'] != v['categorie']) {
      pb.add(_p('Désignation', v['designation'], 'ARTICLE_INCOHERENT', importRefus, 'le code « ${v['code']} » porte une autre désignation ou catégorie que la ligne ${ref['n']}',
          'Un code désigne un seul article : alignez la désignation et la catégorie sur la ligne ${ref['n']}.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    final jour = port.jour;
    final groupes = <String, List<_V>>{};
    final ordre = <String>[];
    for (final l in lignes) {
      final k = _n(l.v['code']);
      if (!groupes.containsKey(k)) {
        groupes[k] = [];
        ordre.add(k);
      }
      groupes[k]!.add(l.v);
    }
    final mouvs = <_V>[...port.toutes('mouvements')];
    for (final k in ordre) {
      final ls = groupes[k]!, p = ls.first;
      final total = ls.fold<num>(0, (t, x) => t + _num(x['quantite']));
      final prix = p['prixRevient'] as num?;
      final seuilFourni = ls.any((x) => x['seuil'] != null);
      final seuil = seuilFourni
          ? ls.map((x) => _num(x['seuil'])).reduce((a, b) => a > b ? a : b)
          : (total * 0.2).round() < 5
              ? 5
              : (total * 0.2).round();
      final prod = ecrireFiche('produits', {
        'code': p['code'],
        'designation': p['designation'],
        'unite': p['unite'] ?? 'Unité',
        'categorie': p['categorie'],
        'prixAchat': prix ?? 0,
        'prixVente': prix ?? 0,
        'cump': prix ?? 0,
        'seuilAlerte': seuil,
        'seuilAValider': !seuilFourni,
        'stockGros': total,
        'stockDetail': 0,
        'stock': total,
        'quantiteImportee': total,
        'emplacement': p['emplacement'] ?? '',
        'fournisseur': p['fournisseur'] ?? '',
        'valoriseSage': false,
        if (prix == null || prix == 0) ...{'valorisationProvisoire': true, 'sourceValorisation': 'Prix de revient absent du fichier d’import ${lot['reference']} : à valoriser'},
      });
      for (final x in ls) {
        if (x['lot'] != null) {
          final jours = importJoursEntre(jour, x['peremption'] as String);
          ecrireFiche('lots', {
            'produitId': prod['id'],
            'produit': p['designation'],
            'numeroLot': x['lot'],
            'datePeremption': x['peremption'],
            'quantiteRestante': x['quantite'],
            'emplacement': x['emplacement'] ?? p['emplacement'] ?? '',
            'statut': jours < 0 ? 'perime' : (jours < 90 ? 'alerte' : 'actif'),
          });
        }
        final ref = _referenceMouvement(mouvs);
        mouvs.add({'reference': ref});
        ecrireFiche('mouvements', {
          'reference': ref,
          'date': jour,
          'produitId': prod['id'],
          'produit': p['designation'],
          'type': 'entree',
          'typeLabel': 'Entrée',
          'quantite': x['quantite'],
          'stockType': 'gros',
          'justificatif': 'Import ${lot['reference']} (stock initial${x['lot'] != null ? ', lot ${x['lot']}' : ''})',
          'utilisateur': port.utilisateur,
        });
      }
    }
  },
  dependances: (lot, port) {
    final ecrits = (lot['ecrits'] as List).cast<Map>();
    final ids = {for (final e in ecrits) if (e['collection'] == 'produits') e['id']};
    final propres = {for (final e in ecrits) if (e['collection'] == 'mouvements') e['id']};
    final autre = port.actives('mouvements').where((m) => ids.contains(m['produitId']) && !propres.contains(m['id'])).firstOrNull;
    if (autre != null) {
      return DependanceImport('MOUVEMENT_POSTERIEUR', 'l’article « ${autre['produit']} » a déjà un mouvement de stock (${autre['reference']}, ${autre['typeLabel']})',
          'Annulez d’abord ce mouvement, ou régularisez le stock par un inventaire : le lot ne peut pas être retiré sous un stock vivant (RG-03).');
    }
    return null;
  },
);

/// `C.referenceSuivante('M', 6, fiches)` : le plus grand rang des références `M…` plus un, sur 6 chiffres.
String _referenceMouvement(List<_V> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = _s(f['reference']);
    if (r.startsWith('M')) {
      final k = int.tryParse(r.substring(1)) ?? 0;
      if (k > max) max = k;
    }
  }
  return 'M${(max + 1).toString().padLeft(6, '0')}';
}

// --- 2. PERSONNEL ------------------------------------------------------------------------------------------------------------------

final JeuImport jeuPersonnel = JeuImport(
  id: 'personnel',
  ecran: 'imp-personnel',
  libelle: 'Importation du personnel',
  module: 'IMP',
  statut: 'supporte',
  roles: const ['da', 'admin'],
  description: 'Fiches des agents : matricule, identité, fonction, service, embauche. Aucune donnée de paie hors salaire de base.',
  source: 'Organigramme et liste du personnel de la clinique (docs/) : 44 agents.',
  cibles: const ['personnel'],
  fichierModele: 'modele-import-personnel',
  gesteExiste: 'Retirez la ligne : un import ne modifie pas une fiche existante. Corrigez-la à l’écran Personnel.',
  colonnes: [
    _oblig('matricule', 'Matricule', 'texte', longueurMax: 20, exemple: '45'),
    _oblig('nom', 'Nom', 'texte', longueurMax: 60, exemple: 'ADJOVI'),
    _oblig('prenom', 'Prénom', 'texte', longueurMax: 80, exemple: 'Marie'),
    _oblig('sexe', 'Sexe', 'liste', liste: _fixe(['M', 'F']), exemple: 'F'),
    _oblig('fonction', 'Fonction', 'liste', liste: _fixe(importFonctions), exemple: 'infirmier', aide: 'Code de fonction du logiciel : il décide des capacités métier.'),
    _oblig('poste', 'Poste', 'texte', longueurMax: 80, exemple: 'Infirmière'),
    _oblig('service', 'Service', 'liste', liste: (ctx) => [for (final s in ctx['services'] as List<String>) ValeurListe(s)], exemple: 'Soins infirmiers'),
    _col('categorie', 'Catégorie', 'texte', motif: RegExp(r'^E[1-5]-[1-3]$'), motifTexte: 'catégorie de la convention (E1-1 à E5-3)', exemple: 'E3-2'),
    _col('dateEmbauche', 'Date d’embauche', 'date', exemple: '2024-03-01'),
    _col('telephone', 'Téléphone', 'texte', longueurMax: 20, exemple: '0197000000'),
    _col('cnss', 'N° CNSS', 'texte', motif: RegExp(r'^\d{9}$'), motifTexte: '9 chiffres', exemple: '294011540'),
    _col('situation', 'Situation familiale', 'liste', liste: _fixe(['Célibataire', 'Marié(e)', 'Veuf(ve)']), exemple: 'Marié(e)'),
    _col('salaireBase', 'Salaire de base', 'entier', min: 0, exemple: 150000, aide: 'Francs CFA bruts mensuels. Réservé à la DAF et à l’administrateur.'),
  ],
  contexte: (port) {
    final m = <String, _V>{}, ident = <String, _V>{};
    final serv = <String>{...importServices};
    for (final p in port.toutes('personnel')) {
      m[_n(p['matricule'])] = p;
      ident['${_n(p['nom'])}|${_n(p['prenom'])}'] = p;
      if (p['statut'] != 'archive' && p['service'] != null && '${p['service']}'.isNotEmpty) serv.add('${p['service']}');
    }
    return {'matricules': m, 'identites': ident, 'services': serv.toList()..sort(), 'jour': port.jour};
  },
  cle: (v) => [_n(v['matricule']), 'id:${_n(v['nom'])}|${_n(v['prenom'])}'],
  existe: (v, ctx) {
    final p = (ctx['matricules'] as Map)[_n(v['matricule'])] ?? (ctx['identites'] as Map)['${_n(v['nom'])}|${_n(v['prenom'])}'];
    return p != null ? 'l’agent ${p['nom']} ${p['prenom']} (matricule ${p['matricule']}) existe déjà' : null;
  },
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    final d = v['dateEmbauche'] as String?;
    if (d != null && d.compareTo(ctx['jour'] as String) > 0) {
      pb.add(_p('Date d’embauche', d, 'DATE_FUTURE', importRefus, 'la date d’embauche est dans le futur', 'Saisissez la date réelle d’entrée en fonction.'));
    }
    if (v['salaireBase'] == null) {
      pb.add(_p('Salaire de base', '', 'SALAIRE_ABSENT', importAvertissement, 'salaire de base non renseigné', 'Le bulletin de paie ne pourra pas se calculer avant sa saisie.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('personnel', {
        'matricule': v['matricule'],
        'nom': v['nom'],
        'prenom': v['prenom'],
        'nomComplet': '${v['nom']} ${v['prenom']}',
        'sexe': v['sexe'],
        'fonction': v['fonction'],
        'poste': v['poste'],
        'service': v['service'],
        'categorie': v['categorie'],
        'dateEmbauche': v['dateEmbauche'],
        'telephone': v['telephone'],
        'cnss': v['cnss'],
        'situation': v['situation'],
        'salaireBase': v['salaireBase'],
      });
    }
  },
  dependances: (lot, port) {
    final ids = {for (final e in (lot['ecrits'] as List).cast<Map>()) e['id']};
    final p = port.actives('planning').where((x) => ids.contains(x['employeId'])).firstOrNull;
    return p != null ? DependanceImport('AGENT_AU_PLANNING', 'l’agent ${p['employe']} figure déjà au planning', 'Retirez-le du planning avant d’annuler le lot.') : null;
  },
);

// --- 3. PATIENTS -------------------------------------------------------------------------------------------------------------------

final _reCodePatient = RegExp(r'^CNT/?\d+/\d{2}$');

final JeuImport jeuPatients = JeuImport(
  id: 'patients',
  ecran: 'imp-patients',
  libelle: 'Importation du répertoire patients',
  module: 'IMP',
  statut: 'supporte',
  roles: const ['reception', 'agentadmin', 'da', 'admin'],
  description: 'Reprise du répertoire papier : identité, coordonnées, couverture. Jamais de dossier médical.',
  source: 'Registre papier des dossiers (environ 18 000) : seule l’identité administrative se reprend (CDCT 4.3).',
  cibles: const ['patients'],
  fichierModele: 'modele-import-patients',
  gesteExiste: 'Retirez la ligne : le dossier existe déjà. Un doublon d’identité se règle à l’écran Patients, jamais par un second dossier.',
  colonnes: [
    _col('code', 'Code dossier', 'texte',
        motif: _reCodePatient,
        motifTexte: 'code de la forme CNT/n/AA',
        exemple: '',
        aide: 'RG-01 : un code existant du registre papier est conservé tel quel et ne se modifie jamais. Vide : le prochain code est attribué automatiquement.'),
    _oblig('nom', 'Nom', 'texte', longueurMax: 60, exemple: 'ADJOVI'),
    _oblig('prenom', 'Prénom', 'texte', longueurMax: 80, exemple: 'Marie'),
    _oblig('sexe', 'Sexe', 'liste', liste: _fixe(['M', 'F']), exemple: 'F'),
    _col('dateNaissance', 'Date de naissance', 'date', exemple: '1990-04-12', aide: 'Date de naissance OU âge déclaré : au moins l’une des deux.'),
    _col('age', 'Âge déclaré', 'entier', min: 0, max: 120, exemple: ''),
    _col('telephone', 'Téléphone', 'texte', longueurMax: 20, exemple: '0197000000'),
    _col('quartier', 'Quartier', 'texte', longueurMax: 60, exemple: 'Boukoumbé'),
    _col('adresse', 'Adresse', 'texte', longueurMax: 120, exemple: 'Tchirimina, Natitingou'),
    _col('personneAPrevenir', 'Personne à prévenir', 'texte', longueurMax: 100, exemple: 'ADJOVI Paul'),
    _col('groupeSanguin', 'Groupe sanguin', 'liste', liste: _fixe(importGroupesSanguins), exemple: 'O+'),
    _col('assureur', 'Code assureur', 'liste', liste: (ctx) => [for (final a in ctx['assureurs'] as List<String>) ValeurListe(a)], exemple: ''),
    _col('numeroPolice', 'N° de police', 'texte', longueurMax: 40, exemple: ''),
    _col('dateCreation', 'Date d’ouverture du dossier', 'date', exemple: '2024-05-02', aide: 'Vide : date du jour.'),
  ],
  contexte: (port) {
    final codes = <String, _V>{}, ident = <String, _V>{}, tel = <String, _V>{};
    for (final p in port.toutes('patients')) {
      codes[_n(p['code'])] = p;
      if (p['dateNaissance'] != null) ident['${_n(p['nom'])}|${_n(p['prenom'])}|${p['dateNaissance']}'] = p;
      if (p['telephone'] != null && _s(p['telephone']).isNotEmpty) tel['${_n(p['nom'])}|${_n(p['prenom'])}|${_s(p['telephone']).replaceAll(RegExp(r'\s'), '')}'] = p;
    }
    final ass = <String, String>{};
    for (final a in port.actives('assureurs')) {
      ass['${a['code']}'] = '${a['nom']}';
    }
    return {'codes': codes, 'ident': ident, 'tel': tel, 'assureurs': ass.keys.toList(), 'nomsAssureurs': ass, 'jour': port.jour};
  },
  cle: (v) {
    final k = <String>[];
    if (v['code'] != null) k.add('code:${_n(v['code'])}');
    if (v['dateNaissance'] != null) k.add('nd:${_n(v['nom'])}|${_n(v['prenom'])}|${v['dateNaissance']}');
    if (v['telephone'] != null) k.add('nt:${_n(v['nom'])}|${_n(v['prenom'])}|${_s(v['telephone']).replaceAll(RegExp(r'\s'), '')}');
    return k;
  },
  existe: (v, ctx) {
    _V? p = v['code'] != null ? (ctx['codes'] as Map)[_n(v['code'])] as _V? : null;
    if (p != null) return 'RG-01 : le code ${p['code']} est déjà attribué à ${p['nom']} ${p['prenom']} (un code ne se réutilise jamais)';
    if (v['dateNaissance'] != null) p = (ctx['ident'] as Map)['${_n(v['nom'])}|${_n(v['prenom'])}|${v['dateNaissance']}'] as _V?;
    if (p == null && v['telephone'] != null) p = (ctx['tel'] as Map)['${_n(v['nom'])}|${_n(v['prenom'])}|${_s(v['telephone']).replaceAll(RegExp(r'\s'), '')}'] as _V?;
    return p != null ? 'doublon probable du dossier ${p['code']} (${p['nom']} ${p['prenom']})' : null;
  },
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    final jour = ctx['jour'] as String;
    final dn = v['dateNaissance'] as String?, dc = v['dateCreation'] as String?;
    if (dn == null && v['age'] == null) {
      pb.add(_p('Date de naissance', '', 'CHAMP_OBLIGATOIRE', importRefus, 'ni date de naissance ni âge déclaré', 'Renseignez la date de naissance, ou à défaut l’âge déclaré.'));
    }
    if (dn != null && dn.compareTo(jour) > 0) {
      pb.add(_p('Date de naissance', dn, 'DATE_FUTURE', importRefus, 'la date de naissance est dans le futur', 'Corrigez la date.'));
    }
    if (dc != null && dc.compareTo(jour) > 0) {
      pb.add(_p('Date d’ouverture du dossier', dc, 'DATE_FUTURE', importRefus, 'la date d’ouverture est dans le futur', 'Corrigez la date, ou laissez la colonne vide.'));
    }
    if (v['assureur'] != null && v['numeroPolice'] == null) {
      pb.add(_p('N° de police', '', 'POLICE_ABSENTE', importAvertissement, 'assuré sans numéro de police', 'La prise en charge (RG-09) ne pourra pas s’appliquer avant sa saisie.'));
    }
    if (v['telephone'] == null) {
      pb.add(_p('Téléphone', '', 'TELEPHONE_ABSENT', importAvertissement, 'aucun téléphone : le patient ne pourra pas être rappelé', 'Renseignez-le si le registre papier le porte.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    final rangs = <String, int>{};
    void noter(String? code) {
      final m = code == null ? null : RegExp(r'^CNT/?(\d+)/(\d{2})$').firstMatch(code);
      if (m != null) {
        final k = int.parse(m[1]!);
        if (k > (rangs[m[2]!] ?? 0)) rangs[m[2]!] = k;
      }
    }

    for (final p in port.toutes('patients')) {
      noter(_s(p['code']));
    }
    for (final l in lignes) {
      noter(l.v['code'] as String?);
    }
    final jour = port.jour;
    for (final l in lignes) {
      final v = l.v;
      final creation = (v['dateCreation'] as String?) ?? jour;
      var code = v['code'] as String?;
      if (code == null) {
        final an = creation.substring(2, 4);
        rangs[an] = (rangs[an] ?? 0) + 1;
        code = 'CNT/${rangs[an]}/$an';
      }
      final fiche = <String, Object?>{
        'code': code,
        'nom': v['nom'],
        'prenom': v['prenom'],
        'sexe': v['sexe'],
        'dateNaissance': v['dateNaissance'],
        'telephone': v['telephone'],
        'quartier': v['quartier'],
        'adresse': v['adresse'],
        'personneAPrevenir': v['personneAPrevenir'],
        'groupeSanguin': v['groupeSanguin'],
        'assureur': v['assureur'],
        'numeroPolice': v['numeroPolice'],
        'dateCreation': creation,
        'externe': false,
        'origineDossier': 'Reprise du répertoire papier',
      };
      if (v['dateNaissance'] != null) {
        fiche['age'] = importAgeAu(v['dateNaissance'] as String, jour);
      } else {
        fiche['age'] = v['age'];
        fiche['ageReferenceLe'] = jour;
      }
      if (v['assureur'] != null) {
        fiche['assure'] = true;
        fiche['assureurNom'] = (ctx['nomsAssureurs'] as Map)[v['assureur']];
      }
      ecrireFiche('patients', fiche);
    }
  },
  dependances: (lot, port) {
    final ids = {for (final e in (lot['ecrits'] as List).cast<Map>()) e['id']};
    for (final c in ['consultations', 'factures', 'admissions', 'demandesLabo', 'ordonnances', 'rendezVous']) {
      final r = port.actives(c).where((x) => ids.contains(x['patientId'])).firstOrNull;
      if (r != null) {
        return DependanceImport('DOSSIER_UTILISE', 'le dossier ${r['patientCode'] ?? r['patientId']} est déjà utilisé ($c)', 'Un dossier qui porte des actes ne s’annule pas par son lot : archivez-le à l’écran Patients.');
      }
    }
    return null;
  },
);

// --- 4. ACTES ET TARIFS ------------------------------------------------------------------------------------------------------------

final JeuImport jeuActes = JeuImport(
  id: 'actes',
  ecran: 'imp-actes',
  libelle: 'Importation du catalogue des actes',
  module: 'IMP',
  statut: 'supporte',
  roles: const ['da', 'admin', 'direction'],
  description: 'Actes et tarifs à deux prix (non assuré, assuré) avec les trois états de la colonne assurée : montant, NC (non couvert), tiret (valeur manquante).',
  source: 'Six grilles tarifaires imprimées et « Répartition des activités » (docs/) ; les prix du fichier font foi, aucun n’est complété par le logiciel.',
  cibles: const ['actes'],
  fichierModele: 'modele-import-actes',
  gesteExiste: 'Retirez la ligne : un tarif en vigueur se modifie à l’écran Catalogue des actes, versionné, jamais écrasé par un import.',
  colonnes: [
    _oblig('code', 'Code acte', 'texte', longueurMax: 20, exemple: 'MG01'),
    _oblig('libelle', 'Libellé', 'texte', longueurMax: 160, exemple: 'Consultation généraliste'),
    _oblig('secteur', 'Secteur', 'liste', liste: (ctx) => [for (final s in ctx['secteurs'] as List<String>) ValeurListe(s)], exemple: 'Médecine générale'),
    _oblig('prixNonAssure', 'Prix non assuré', 'tarif', exemple: 5000, aide: 'Montant entier en FCFA, ou un tiret si le prix manque. Un tiret n’est pas un zéro : l’acte ne se facture pas.'),
    _oblig('prixAssure', 'Prix assuré', 'tarif', exemple: 3000, aide: 'Montant, NC (aucune compagnie ne couvre l’acte : l’assuré paie le prix non assuré) ou un tiret (valeur manquante).'),
    _col('codeTarif', 'Code tarif', 'texte', longueurMax: 30, exemple: 'CONS-GEN'),
  ],
  contexte: (port) {
    final c = <String, _V>{};
    final sec = <String>{...importSecteursActes};
    for (final a in port.toutes('actes')) {
      c[_n(a['code'])] = a;
      if (a['statut'] != 'archive' && a['secteur'] != null && '${a['secteur']}'.isNotEmpty) sec.add('${a['secteur']}');
    }
    return {'actes': c, 'secteurs': sec.toList()..sort()};
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final a = (ctx['actes'] as Map)[_n(v['code'])];
    return a != null ? 'l’acte « ${a['code']} » existe déjà (${a['libelle']})' : null;
  },
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    final na = (v['prixNonAssure'] as Map)['etat'], as = (v['prixAssure'] as Map)['etat'];
    if (na == 'nc') {
      pb.add(_p('Prix non assuré', 'NC', 'NC_INTERDIT', importRefus, 'NC n’a de sens que dans la colonne assurée', 'Saisissez le prix de guichet, ou un tiret s’il manque.'));
    }
    if (na == 'manquant') {
      pb.add(_p('Prix non assuré', '-', 'PRIX_MANQUANT', importAvertissement, 'prix non assuré manquant : l’acte ne se facturera pas (un tiret n’est pas un zéro)', 'Saisissez le prix au catalogue dès qu’il est arrêté.'));
    }
    if (as == 'manquant') {
      pb.add(_p('Prix assuré', '-', 'PRIX_MANQUANT', importAvertissement, 'prix assuré manquant : l’acte ne se facturera pas aux assurés', 'Saisissez le prix assuré, ou NC si aucune compagnie ne couvre l’acte.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      final na = v['prixNonAssure'] as Map, as = v['prixAssure'] as Map;
      ecrireFiche('actes', {
        'code': v['code'],
        'libelle': v['libelle'],
        'secteur': v['secteur'],
        'codeTarif': v['codeTarif'],
        'prixNonAssure': na['etat'] == 'montant' ? na['montant'] : null,
        'prixAssure': as['etat'] == 'montant' ? as['montant'] : null,
        'nonCouvert': as['etat'] == 'nc',
        'assurable': as['etat'] != 'nc',
        'prix': na['etat'] == 'montant' ? na['montant'] : null,
        'tarifProvisoire': false,
        if (na['etat'] == 'manquant' || as['etat'] == 'manquant')
          'motifPrix': 'Valeur manquante à l’import ${lot['reference']} : l’acte ne se facture pas tant que le prix n’est pas saisi.',
      });
    }
  },
  dependances: (lot, port) {
    final codes = <Object?>{};
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final a = port.parId('${e['collection']}', e['id']);
      if (a != null) codes.add(a['code']);
    }
    final u = port.actives('prescriptions').where((x) => codes.contains(x['acteCode'])).firstOrNull;
    return u != null ? DependanceImport('ACTE_UTILISE', 'l’acte « ${u['acteCode']} » est déjà prescrit', 'Archivez l’acte au catalogue plutôt que d’annuler son lot.') : null;
  },
);

// --- 5. ANALYSES (proposition à valider) ---------------------------------------------------------------------------------------------

final JeuImport jeuAnalyses = JeuImport(
  id: 'analyses',
  ecran: 'imp-analyses',
  libelle: 'Importation du catalogue des analyses',
  module: 'IMP',
  statut: 'proposition',
  roles: const ['laborantin', 'da', 'admin'],
  description: 'Entrées du catalogue des examens (code, désignation, section). Les variables, unités et bornes ne se reprennent pas : le biologiste les valide.',
  source: 'Bulletin d’analyses bio-médicales et fiche de résultats du 21/08/2026 (docs/) : 48 analyses au catalogue.',
  limite: 'PROPOSITION À VALIDER : seule l’entrée du catalogue est créée. Sans variables ni bornes, un examen importé ne peut pas recevoir de résultat avant que le biologiste les ait saisies et validées.',
  cibles: const ['examensLabo'],
  fichierModele: 'modele-import-analyses',
  gesteExiste: 'Retirez la ligne : un examen en service se modifie à l’écran du catalogue du laboratoire.',
  colonnes: [
    _oblig('code', 'Code examen', 'texte', longueurMax: 20, exemple: 'GLY'),
    _oblig('designation', 'Désignation', 'texte', longueurMax: 160, exemple: 'Glycémie à jeun'),
    _oblig('section', 'Section', 'liste', liste: (_) => [for (final s in importSectionsLabo) ValeurListe(s[0], s[1])], exemple: 'Biochimie'),
    _col('echantillon', 'Échantillon', 'texte', longueurMax: 60, exemple: 'Sérum'),
    _col('delai', 'Délai de rendu', 'texte', longueurMax: 20, exemple: '4 h'),
  ],
  contexte: (port) => {
    'examens': {for (final e in port.toutes('examensLabo')) _n(e['code']): e}
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final e = (ctx['examens'] as Map)[_n(v['code'])];
    return e != null ? 'l’examen « ${e['code']} » existe déjà (${e['designation']})' : null;
  },
  regles: (v, ctx, sc, n) => [_p('Code examen', '', 'SANS_VARIABLES', importAvertissement, 'examen importé sans variables ni bornes de référence', 'Le biologiste les saisit puis les valide avant toute saisie de résultat.')],
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('examensLabo', {
        'code': v['code'],
        'designation': v['designation'],
        'section': v['section'],
        'sectionResultat': v['section'],
        'sectionBulletin': v['section'],
        'echantillon': v['echantillon'],
        'delai': v['delai'],
        'documente': false,
        'aValider': true,
      });
    }
  },
  dependances: (lot, port) {
    final codes = <Object?>{};
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final a = port.parId('${e['collection']}', e['id']);
      if (a != null) codes.add(a['code']);
    }
    final u = port.actives('demandesLabo').where((x) => codes.contains(x['examenCode']) || codes.contains(x['code'])).firstOrNull;
    return u != null ? const DependanceImport('EXAMEN_DEMANDE', 'l’examen est déjà demandé', 'Archivez-le au catalogue du laboratoire.') : null;
  },
);

// --- 6. FOURNISSEURS --------------------------------------------------------------------------------------------------------------

final JeuImport jeuFournisseurs = JeuImport(
  id: 'fournisseurs',
  ecran: 'imp-fournisseurs',
  libelle: 'Importation des fournisseurs',
  module: 'IMP',
  statut: 'supporte',
  roles: const ['stock', 'da', 'comptable', 'admin'],
  description: 'Fournisseurs de la clinique : identité fiscale, coordonnées, délai, banque.',
  source: 'Factures de vente et bons de livraison collectés (docs/), dont la facture SoBAPS.',
  cibles: const ['fournisseurs'],
  fichierModele: 'modele-import-fournisseurs',
  gesteExiste: 'Retirez la ligne : modifiez la fiche existante à l’écran Fournisseurs.',
  colonnes: [
    _oblig('code', 'Code fournisseur', 'texte', longueurMax: 24, exemple: 'SOBAPS'),
    _oblig('nom', 'Raison sociale', 'texte', longueurMax: 160, exemple: 'SoBAPS SA'),
    _col('type', 'Type', 'texte', longueurMax: 60, exemple: 'Grossiste pharmaceutique'),
    _col('ville', 'Ville', 'texte', longueurMax: 60, exemple: 'Parakou'),
    _col('adresse', 'Adresse', 'texte', longueurMax: 120, exemple: 'BP 201 Parakou'),
    _col('tel', 'Téléphone', 'texte', longueurMax: 60, exemple: '0191484242'),
    _col('ifu', 'IFU', 'texte', motif: RegExp(r'^\d{13}$'), motifTexte: '13 chiffres', exemple: '3202112446712'),
    _col('delai', 'Délai de livraison (jours)', 'entier', min: 0, max: 365, exemple: 5),
    _col('banque', 'Banque', 'texte', longueurMax: 60, exemple: 'BANK OF AFRICA'),
    _col('compte', 'N° de compte', 'texte', longueurMax: 30, exemple: '007393360019'),
  ],
  contexte: (port) => {
    'f': {for (final f in port.toutes('fournisseurs')) _n(f['code']): f}
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final f = (ctx['f'] as Map)[_n(v['code'])];
    return f != null ? 'le fournisseur « ${f['code']} » existe déjà (${f['nom']})' : null;
  },
  regles: (v, ctx, sc, n) => v['ifu'] != null
      ? const []
      : [_p('IFU', '', 'IFU_ABSENT', importAvertissement, 'IFU absent : la facture fournisseur ne sera pas justifiable fiscalement', 'Renseignez-le dès que la facture le porte.')],
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('fournisseurs', {
        'code': v['code'],
        'nom': v['nom'],
        'type': v['type'],
        'ville': v['ville'],
        'adresse': v['adresse'],
        'tel': v['tel'],
        'ifu': v['ifu'],
        'delai': v['delai'],
        'banque': v['banque'],
        'compte': v['compte'],
        'habilite': false,
      });
    }
  },
  dependances: (lot, port) {
    final codes = <Object?>{};
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final a = port.parId('${e['collection']}', e['id']);
      if (a != null) codes.add(a['code']);
    }
    final u = port.actives('commandes').where((x) => codes.contains(x['fournisseur']) || codes.contains(x['fournisseurCode'])).firstOrNull;
    return u != null ? const DependanceImport('FOURNISSEUR_UTILISE', 'une commande est déjà passée à ce fournisseur', 'Archivez-le à l’écran Fournisseurs.') : null;
  },
);

// --- 7. ASSUREURS ----------------------------------------------------------------------------------------------------------------

final JeuImport jeuAssureurs = JeuImport(
  id: 'assureurs',
  ecran: 'imp-assureurs',
  libelle: 'Importation des compagnies d’assurance',
  module: 'IMP',
  statut: 'supporte',
  roles: const ['da', 'comptable', 'admin'],
  description: 'Compagnies d’assurance : code, raison sociale, contacts, état de la convention.',
  source: 'Treize assureurs relevés dans les documents de cadrage (docs/).',
  cibles: const ['assureurs'],
  fichierModele: 'modele-import-assureurs',
  gesteExiste: 'Retirez la ligne : modifiez la compagnie à l’écran Compagnies.',
  colonnes: [
    _oblig('code', 'Code compagnie', 'texte', motif: RegExp(r'^[A-Za-z0-9]{2,8}$'), motifTexte: '2 à 8 lettres ou chiffres', exemple: 'NSIA'),
    _oblig('nom', 'Raison sociale', 'texte', longueurMax: 120, exemple: 'NSIA ASSURANCE'),
    _col('tel', 'Téléphones', 'texte', longueurMax: 80, exemple: '0153212091 / 0196043695', aide: 'Plusieurs numéros séparés par une barre oblique.'),
    _col('email', 'E-mail', 'texte', motif: RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$'), motifTexte: 'adresse e-mail', exemple: 'contact@exemple.bj'),
    _col('convention', 'Convention', 'liste', liste: _fixe(['Signée', 'En négociation', 'Aucune']), exemple: 'Signée'),
  ],
  contexte: (port) => {
    'a': {for (final a in port.toutes('assureurs')) _n(a['code']): a}
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final a = (ctx['a'] as Map)[_n(v['code'])];
    return a != null ? 'la compagnie « ${a['code']} » existe déjà (${a['nom']})' : null;
  },
  regles: (v, ctx, sc, n) => v['convention'] != null
      ? const []
      : [_p('Convention', '', 'CONVENTION_ABSENTE', importAvertissement, 'état de la convention non renseigné', 'Sans convention saisie, la facture reste intégralement au patient.')],
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('assureurs', {
        'code': v['code'],
        'nom': v['nom'],
        'tel': v['tel'] != null ? [for (final x in '${v['tel']}'.split('/')) x.trim()] : <String>[],
        'email': v['email'],
        'convention': v['convention'],
        'assures': 0,
      });
    }
  },
  dependances: (lot, port) {
    final codes = <Object?>{};
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final a = port.parId('${e['collection']}', e['id']);
      if (a != null) codes.add(a['code']);
    }
    final u = port.actives('souscripteurs').where((x) => codes.contains(x['assureur'])).firstOrNull ?? port.actives('patients').where((x) => codes.contains(x['assureur'])).firstOrNull;
    return u != null ? const DependanceImport('COMPAGNIE_UTILISEE', 'un souscripteur ou un patient dépend de cette compagnie', 'Annulez d’abord le lot des souscripteurs, ou archivez la compagnie.') : null;
  },
);

// --- 8. SOUSCRIPTEURS --------------------------------------------------------------------------------------------------------------

final JeuImport jeuSouscripteurs = JeuImport(
  id: 'souscripteurs',
  ecran: 'imp-souscripteurs',
  libelle: 'Importation des souscripteurs',
  module: 'IMP',
  statut: 'supporte',
  roles: const ['da', 'comptable', 'admin'],
  description: 'Souscripteurs rattachés à une compagnie : n° de police, catégorie, effectif, période.',
  source: 'Relevés de prestations et factures mensuelles par souscripteur (docs/).',
  limite: 'La grille de garanties du souscripteur (taux par catégorie, plafonds, exclusions) ne s’importe pas : elle se saisit à l’écran Souscripteurs. Sans elle, la facture reste intégralement au patient.',
  cibles: const ['souscripteurs'],
  fichierModele: 'modele-import-souscripteurs',
  gesteExiste: 'Retirez la ligne : modifiez le souscripteur à l’écran Souscripteurs.',
  colonnes: [
    _oblig('nom', 'Souscripteur', 'texte', longueurMax: 120, exemple: 'PIB Bénin'),
    _oblig('police', 'N° de police', 'texte', longueurMax: 40, exemple: 'AFR/2024/0100'),
    _oblig('assureur', 'Code compagnie', 'liste', liste: (ctx) => [for (final a in ctx['assureurs'] as List<String>) ValeurListe(a)], exemple: 'AFR', aide: 'Une compagnie déjà connue du magasin : importez-la d’abord.'),
    _col('categorie', 'Catégorie', 'liste', liste: _fixe(['entreprise', 'particulier', 'personnel']), exemple: 'entreprise'),
    _col('effectif', 'Effectif', 'entier', min: 0, exemple: 75),
    _col('dateDebut', 'Date de début', 'date', exemple: '2024-08-01'),
    _col('dateFin', 'Date de fin', 'date', exemple: ''),
  ],
  contexte: (port) {
    final a = <String, String>{};
    for (final x in port.actives('assureurs')) {
      a['${x['code']}'] = '${x['nom']}';
    }
    return {'polices': {for (final s in port.toutes('souscripteurs')) _n(s['police']): s}, 'nomsAssureurs': a, 'assureurs': a.keys.toList()};
  },
  cle: (v) => [_n(v['police'])],
  existe: (v, ctx) {
    final s = (ctx['polices'] as Map)[_n(v['police'])];
    return s != null ? 'la police « ${s['police']} » existe déjà (${s['nom']})' : null;
  },
  regles: (v, ctx, sc, n) {
    final d = v['dateDebut'] as String?, f = v['dateFin'] as String?;
    if (d != null && f != null && f.compareTo(d) < 0) {
      return [_p('Date de fin', f, 'PERIODE_INVERSEE', importRefus, 'la date de fin précède la date de début', 'Corrigez l’une des deux dates.')];
    }
    return const [];
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('souscripteurs', {
        'nom': v['nom'],
        'police': v['police'],
        'assureur': v['assureur'],
        'assureurNom': (ctx['nomsAssureurs'] as Map)[v['assureur']],
        'categorie': v['categorie'],
        'effectif': v['effectif'],
        'dateDebut': v['dateDebut'],
        'dateFin': v['dateFin'],
        'grilleSaisie': false,
        'actesExclus': <Object?>[],
        'produitsExclus': <Object?>[],
        'accordPrealable': <Object?>[],
      });
    }
  },
  dependances: (lot, port) {
    final ids = {for (final e in (lot['ecrits'] as List).cast<Map>()) e['id']};
    final u = port.actives('patients').where((x) => ids.contains(x['souscripteurId'])).firstOrNull;
    return u != null ? DependanceImport('SOUSCRIPTEUR_UTILISE', 'le dossier ${u['code']} est rattaché à ce souscripteur', 'Archivez le souscripteur plutôt que d’annuler son lot.') : null;
  },
);

// --- 9. PLAN COMPTABLE -------------------------------------------------------------------------------------------------------------

final JeuImport jeuPlanComptable = JeuImport(
  id: 'plan-comptable',
  ecran: 'imp-plan-comptable',
  libelle: 'Importation du plan comptable',
  module: 'IMP',
  statut: 'supporte',
  roles: const ['comptable', 'da', 'admin'],
  description: 'Comptes SYSCOHADA : numéro, libellé, journal par défaut. La classe se déduit du premier chiffre.',
  source: 'Plan comptable de la clinique, classeur SYSCOHADA 2025 (docs/) : 93 comptes.',
  cibles: const ['comptes'],
  fichierModele: 'modele-import-plan-comptable',
  gesteExiste: 'Retirez la ligne : un numéro de compte ne se double jamais au plan (le plan ne tolère aucun doublon).',
  colonnes: [
    _oblig('num', 'N° de compte', 'texte', motif: RegExp(r'^[1-9]\d{3,7}$'), motifTexte: 'numéro de 4 à 8 chiffres, premier chiffre de 1 à 9', exemple: '571000'),
    _oblig('libelle', 'Libellé', 'texte', longueurMax: 160, exemple: 'Caisse'),
    _col('journal', 'Journal', 'liste', liste: (_) => [for (final j in importJournaux) ValeurListe(j[0], j[0])], exemple: 'CAI'),
  ],
  contexte: (port) => {
    'comptes': {for (final x in port.toutes('comptes')) if (x['statut'] != 'archive') '${x['num']}': x}
  },
  cle: (v) => ['${v['num']}'],
  existe: (v, ctx) {
    final c = (ctx['comptes'] as Map)['${v['num']}'];
    return c != null ? 'le compte ${c['num']} existe déjà (${c['libelle']})' : null;
  },
  regles: _aucun,
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('comptes', {'num': v['num'], 'libelle': v['libelle'], 'classe': int.parse('${v['num']}'[0]), 'journal': v['journal'] ?? 'OD'});
    }
  },
  dependances: (lot, port) {
    final nums = <String>{};
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final a = port.parId('${e['collection']}', e['id']);
      if (a != null) nums.add('${a['num']}');
    }
    final u = port.actives('ecritures').where((x) => nums.contains('${x['compte']}')).firstOrNull;
    return u != null ? DependanceImport('COMPTE_UTILISE', 'le compte ${u['compte']} porte déjà l’écriture ${u['numero']}', 'Archivez le compte au plan plutôt que d’annuler son lot.') : null;
  },
);

// --- 10. SOLDES D'OUVERTURE -------------------------------------------------------------------------------------------------------

final JeuImport jeuSoldesOuverture = JeuImport(
  id: 'soldes-ouverture',
  ecran: 'imp-soldes-ouverture',
  libelle: 'Importation des soldes d’ouverture',
  module: 'IMP',
  statut: 'supporte',
  roles: const ['comptable', 'da', 'admin'],
  description: 'À-nouveaux d’un exercice : une pièce du journal AN, en brouillon, équilibrée (RG-10). Seules les classes 1 à 5 se reportent.',
  source: 'Bilan de clôture de l’exercice précédent : liasse déposée le 15/05/2026 (docs/).',
  cibles: const ['ecritures'],
  fichierModele: 'modele-import-soldes-ouverture',
  colonnes: [
    _oblig('date', 'Date', 'date', exemple: '2026-01-01', aide: 'Premier jour de l’exercice. Une seule date pour tout le fichier.'),
    _oblig('compte', 'N° de compte', 'texte', motif: RegExp(r'^[1-9]\d{3,7}$'), motifTexte: 'numéro de 4 à 8 chiffres', exemple: '571000'),
    _col('libelle', 'Libellé', 'texte', longueurMax: 160, exemple: 'Caisse à l’ouverture'),
    _col('tiers', 'Tiers', 'texte', longueurMax: 80, exemple: '', aide: 'Comptes de tiers (40, 41, 42, 43, 44, 47) : une ligne par tiers, le même compte peut donc se répéter.'),
    _col('debit', 'Débit', 'entier', min: 0, exemple: 250000),
    _col('credit', 'Crédit', 'entier', min: 0, exemple: ''),
  ],
  contexte: (port) {
    final c = <String, _V>{}, an = <String, String>{};
    for (final x in port.toutes('comptes')) {
      if (x['statut'] != 'archive') c['${x['num']}'] = x;
    }
    for (final e in port.toutes('ecritures')) {
      if (e['journal'] == 'AN' && e['statut'] != 'archive') an['${e['date']}'.substring(0, 4)] = '${e['numero']}';
    }
    return {'comptes': c, 'an': an};
  },
  cle: (v) => ['${v['compte']}|${_n(v['tiers'] ?? '')}'],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    final d = _num(v['debit']), cr = _num(v['credit']);
    final compte = '${v['compte']}';
    if ((ctx['comptes'] as Map)[compte] == null) {
      pb.add(_p('N° de compte', compte, 'COMPTE_INCONNU', importRefus, 'le compte $compte n’existe pas au plan comptable', 'Importez-le d’abord (jeu Plan comptable) ou corrigez le numéro.'));
    }
    if (int.parse(compte[0]) > 5) {
      pb.add(_p('N° de compte', compte, 'CLASSE_NON_REPORTABLE', importRefus, 'un compte de gestion (classes 6, 7, 8, 9) ne se reporte jamais : il est soldé par le résultat', 'Retirez la ligne : seules les classes 1 à 5 forment l’ouverture.'));
    }
    if (d > 0 && cr > 0) {
      pb.add(_p('Crédit', cr, 'DEUX_SENS', importRefus, 'une ligne d’écriture a un sens, pas deux : débit et crédit sont tous deux renseignés', 'Gardez le solde net dans UNE seule des deux colonnes.'));
    }
    if (d == 0 && cr == 0) {
      pb.add(_p('Débit', 0, 'LIGNE_NULLE', importRefus, 'ligne sans montant', 'Renseignez le débit ou le crédit, ou retirez la ligne.'));
    }
    return pb;
  },
  reglesLot: (lignes, ctx) {
    final pb = <ProblemeImport>[];
    final dates = <String>[];
    num td = 0, tc = 0;
    for (final l in lignes) {
      final d = '${l.v['date']}';
      if (!dates.contains(d)) dates.add(d);
      td += _num(l.v['debit']);
      tc += _num(l.v['credit']);
    }
    String fr(num x) => x.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '\u202F');
    if (dates.length > 1) {
      pb.add(_p('Date', dates.join(', '), 'DATES_MULTIPLES', importRefus, 'le fichier porte ${dates.length} dates : l’ouverture est une seule pièce à une seule date', 'Alignez toutes les lignes sur le premier jour de l’exercice.'));
    }
    if (td != tc) {
      pb.add(_p('Débit / Crédit', 'débit $td ≠ crédit $tc', 'RG10_DESEQUILIBRE', importRefus,
          'écriture non équilibrée (RG-10) : total débit ${fr(td)}, total crédit ${fr(tc)}, écart ${fr((td - tc).abs())}', 'Corrigez les montants jusqu’à égalité des deux totaux ; aucune pièce déséquilibrée ne s’écrit.'));
    }
    if (dates.length == 1 && (ctx['an'] as Map)[dates.first.substring(0, 4)] != null) {
      pb.add(_p('Date', dates.first, 'A_NOUVEAU_EXISTANT', importRefus, 'l’exercice ${dates.first.substring(0, 4)} porte déjà un à-nouveau (${(ctx['an'] as Map)[dates.first.substring(0, 4)]})',
          'Un exercice ne s’ouvre qu’une fois : annulez d’abord le lot ou l’à-nouveau existant.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    final an = '${lignes.first.v['date']}'.substring(0, 4);
    final existants = port.toutes('ecritures').where((e) => e['journal'] == 'AN' && '${e['numero']}'.startsWith('AN-$an-')).length;
    final numero = 'AN-$an-${(existants + 1).toString().padLeft(5, '0')}';
    final libJ = importJournaux.where((j) => j[0] == 'AN').map((j) => j[1]).firstOrNull ?? 'À-nouveaux';
    for (final l in lignes) {
      final v = l.v;
      final c = port.toutes('comptes').where((x) => '${x['num']}' == '${v['compte']}').firstOrNull ?? <String, Object?>{};
      ecrireFiche('ecritures', {
        'numero': numero,
        'date': v['date'],
        'journal': 'AN',
        'journalLibelle': libJ,
        'libelle': v['libelle'] ?? 'Solde d’ouverture ${v['compte']}${v['tiers'] != null ? ' ${v['tiers']}' : ''}',
        'compte': '${v['compte']}',
        'compteLibelle': c['libelle'] ?? '',
        'debit': v['debit'] ?? 0,
        'credit': v['credit'] ?? 0,
        'origine': 'Import des soldes d’ouverture',
        'statut': 'brouillon',
      });
    }
  },
  dependances: (lot, port) => null,
);

/// Les dix jeux, dans l'ordre de la maquette.
final List<JeuImport> jeuxImport = [
  jeuGrandStock,
  jeuPersonnel,
  jeuPatients,
  jeuActes,
  jeuAnalyses,
  jeuFournisseurs,
  jeuAssureurs,
  jeuSouscripteurs,
  jeuPlanComptable,
  jeuSoldesOuverture,
];

JeuImport? jeuImportParId(String id) => jeuxImport.where((j) => j.id == id).firstOrNull;
JeuImport? jeuImportParEcran(String ecran) => jeuxImport.where((j) => j.ecran == ecran).firstOrNull;
