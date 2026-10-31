import 'qual_enquetes.dart' show QualFiche;

/// LE CENTRE DES VALIDATIONS EN ATTENTE (`adm-validations`, vague 49) — règles portées de `m13-administration.js`.
///
/// Un seul écran pour répondre à « qu'est-ce qui attend une validation, et de QUI ? ». Il ORIENTE, il ne valide JAMAIS en masse : la validation est un
/// geste humain, porté à SON POSTE. Quatre familles : les gestes de poste (comptés depuis les registres), les référentiels qui attendent un
/// PROFESSIONNEL nommé, ce qui attend un ARBITRAGE de la Direction, et ce que la Direction a déjà validé. Une file amorcée par un écran d'un autre
/// module s'annonce « non amorcée » plutôt que d'afficher un 0 faux (doctrine de la vague 31).

/// Une file de gestes à valider à son poste.
class QualFile {
  const QualFile(this.libelle, this.poste, this.compte, this.ecran, this.icone, {this.nonAmorcee = false});
  final String libelle;
  final String poste;

  /// `null` : file non amorcée sur ce poste (le compte serait un mensonge).
  final int? compte;
  final String ecran;
  final String icone;
  final bool nonAmorcee;

  String get sousTitre =>
      nonAmorcee ? 'File non amorcée sur ce poste — ouvrir l’écran pour la charger' : 'Le geste appartient à : $poste';
}

/// Un référentiel qui attend un professionnel nommé (la Direction ne signe pas à sa place).
class QualProfessionnel {
  const QualProfessionnel(this.libelle, this.qui, this.compte, this.ecran, this.motif);
  final String libelle;
  final String qui;
  final int compte;
  final String ecran;
  final String motif;
  String get titre => '$libelle — ${_nb(compte)} entrée(s)';
}

/// Ce qui attend un arbitrage de la Direction elle-même.
class QualArbitrage {
  const QualArbitrage(this.libelle, this.attente, this.ecran, this.motif);
  final String libelle;
  final String attente;
  final String ecran;
  final String motif;
  String get detail => 'Valeur d’attente : $attente · $motif';
}

String _nb(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

/// Les quatre arbitrages du badge (vague 54) : valeurs d'attente, que la Direction seule peut arrêter.
const qualArbitrages = [
  QualArbitrage('Durée de validité d’un badge du personnel', '24 mois (valeur d’attente)', 'm10-badges',
      'Aucun document de cadrage ne la fixe. Peut aussi suivre la durée du contrat.'),
  QualArbitrage('Format du numéro de série des badges', 'BDG-NNNNN-AAAA', 'm10-badges',
      'Proposé par analogie avec les pièces certifiantes (série annuelle). La clinique tient peut-être déjà une numérotation qu’il faudrait reprendre.'),
  QualArbitrage('Mentions portées au verso du badge', 'Restitution, perte, propriété', 'm10-badges-modeles',
      'Elles engagent la clinique envers le porteur : c’est à la Direction de les arrêter.'),
  QualArbitrage('Le badge sert-il de support de POINTAGE ?', 'Non — décision non prise', 'm10-badges',
      'S’il pointe, il se relie au registre des présences et la conception change : lecteur à l’entrée, horodatage, traitement des oublis de badge.'),
];

/// Ce que la Direction a validé le 01/09/2026 (vague 49) : (référentiel, décision).
const qualValidees = [
  ('Tarifs des actes (valeurs d’attente du 20/08)',
      'ARRÊTÉS par la Direction — plus aucun tarif provisoire au catalogue vivant ; la semence garde le marquage historique.'),
  ('Valorisation des 34 références SAGE',
      'Médiane de catégorie CONFIRMÉE ; révisable à la première facture fournisseur (surcouche tracée).'),
  ('Les quatre groupes d’articles', 'CONFIRMÉS — ils cessent d’être une proposition.'),
  ('Questionnaire de satisfaction', 'VALIDÉ — le recueil peut s’appuyer dessus.'),
  ('Bornes suppléées du laboratoire (61 variables)',
      'Validation écrite du BIOLOGISTE MÉDICAL (01/09) — badge « Validée », jamais confondu avec « Documentée ».'),
  ('Liste des 55 pathologies', 'Arrêtée par les MÉDECINS (tableau de morbidité, 01/09) — elle reste administrable.'),
  ('Check-listes du bloc, échelles ASA/Mallampati, techniques',
      'Arrêtées par les PRATICIENS DU BLOC (01/09) — la provenance proposée reste dite.'),
  ('Seuils d’alerte du stock', 'Seuils proposés (20 % du stock repris) CONFIRMÉS — révisables référence par référence.'),
  ('Rapprochement groupe ↔ centre de coûts',
      'ARRÊTÉ — bénéfice brut par groupe affiché, charges transverses non ventilées (dit).'),
];

bool _v(Object? x) => x != null && x != false && x != '' && x != 0;

List<QualFiche> _actives(Iterable<QualFiche>? l) => [
      for (final f in l ?? const <QualFiche>[])
        if (f['statut'] != 'archive') f
    ];

/// Les sept files de gestes de poste. [toutes] : la collection ENTIÈRE (archivées comprises) pour `besoins` et `commandes`, dont le vide signifie
/// « non amorcée » ; [aujourdhui] : date ISO du jour.
List<QualFile> qualFilesValidation({
  required Iterable<QualFiche> demandesAnalyses,
  required Iterable<QualFiche> ecritures,
  required Iterable<QualFiche> besoinsToutes,
  required Iterable<QualFiche> commandesToutes,
  required Iterable<QualFiche> factures,
  required Iterable<QualFiche> resultatsImagerie,
  required Iterable<QualFiche> echeancesFiscales,
  required String aujourdhui,
}) {
  final besoins = besoinsToutes.isNotEmpty;
  final commandes = commandesToutes.isNotEmpty;
  return [
    QualFile('Résultats à valider biologiquement', 'Biologiste médical',
        _actives(demandesAnalyses).where((d) => d['etatAnalyse'] == 'valide_technique').length, 'm5-resultats', 'shield-check'),
    QualFile('Écritures comptables en brouillon', 'Comptable',
        _actives(ecritures).where((e) => e['statut'] == 'brouillon').length, 'm12-ecritures', 'pencil-line'),
    QualFile('Bons de besoins en circuit de validation', 'Directrice Administrative',
        besoins
            ? _actives(besoinsToutes)
                .where((b) => const ['soumis', 'controle_stock', 'validation_da'].contains(b['etape']))
                .length
            : null,
        'm7-besoins',
        'clipboard-list',
        nonAmorcee: !besoins),
    QualFile('Commandes fournisseur à valider (RG-04)', 'Directrice Administrative',
        commandes ? _actives(commandesToutes).where((x) => x['statutCommande'] == 'attente_validation').length : null,
        'm7-commandes', 'shopping-cart',
        nonAmorcee: !commandes),
    QualFile(
        'Factures à normaliser MECeF',
        'Caisse / fiscalité',
        _actives(factures)
            .where((f) => f['statutMecef'] == 'en_attente' && f['numeroMecef'] != null && f['numeroMecef'] != '')
            .length,
        'mecef-factures',
        'file-badge'),
    QualFile('Comptes rendus d’imagerie à rendre', 'Échographiste',
        _actives(resultatsImagerie).where((r) => r['statut'] != 'rendu').length, 'm2-imagerie-demandes', 'scan-line'),
    QualFile(
        'Échéances fiscales dépassées',
        'Comptable / DAF',
        _actives(echeancesFiscales)
            .where((e) => !_v(e['paye']) && '${e['echeance'] ?? ''}'.compareTo(aujourdhui) < 0 && e['echeance'] != null)
            .length,
        'm12-echeances',
        'calendar-clock'),
  ];
}

/// Les deux référentiels « en attente d'un professionnel » : ce qui reste n'attend PAS une signature, mais une donnée physiquement manquante
/// (parc technique) ou structurellement récurrente (plages par lot de réactif).
List<QualProfessionnel> qualProfessionnels(
        {required Iterable<QualFiche> materiel, required Iterable<QualFiche> plagesReactif}) =>
    [
      QualProfessionnel(
          'Parc technique — fiches à compléter',
          'Ingénierie / administration',
          _actives(materiel).where((m) => _v(m['aCompleter'])).length,
          'm13-maintenance',
          'Marque, n° de série et mise en service MANQUENT physiquement : une validation ne crée pas un numéro de série — le marquage disparaît par la SAISIE, jamais par une signature.'),
      QualProfessionnel('Plages de référence par lot de réactif', 'Biologiste médical', _actives(plagesReactif).length,
          'm5-valeurs-reference', 'Structurel : chaque NOUVEAU lot porte ses bornes — la notice du réactif fait foi, à chaque arrivage.'),
    ];

/// Les quatre indicateurs du centre.
class QualBilanValidations {
  const QualBilanValidations(
      {required this.gestes, required this.filesConcernees, required this.files, required this.professionnels, required this.validees});
  final int gestes;
  final int filesConcernees;
  final int files;
  final int professionnels;
  final int validees;
  String get filesTexte => '$filesConcernees / $files';
}

QualBilanValidations qualBilanValidations(List<QualFile> files, List<QualProfessionnel> pros) => QualBilanValidations(
    gestes: files.fold(0, (n, x) => n + (x.compte ?? 0)),
    filesConcernees: files.where((x) => (x.compte ?? 0) > 0).length,
    files: files.length,
    professionnels: pros.where((x) => x.compte > 0).length,
    validees: qualValidees.length);
