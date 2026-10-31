/// M9 — ASSURANCES, CRÉANCES & RELANCES : les règles chiffrées des dix écrans (`prototype_html/assets/js/modules/m9-assurances.js`).
///
/// Les écrans de la maquette lisaient le magasin ; ces fonctions reçoivent les fiches EN ARGUMENT. Chaque règle est rejouée sur des vecteurs tirés
/// des ÉCRANS RÉELS pilotés dans Chrome (`test/vecteurs/ass_m9.json`, engendré par `prototype_html/build/vecteurs-m9.js`) — jamais écrite de mémoire.
/// La prise en charge elle-même (RG-09, `repartir`) est celle de `caisse/prise_en_charge.dart` : on ne la duplique pas.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../referentiels/regles.dart' show joursEntre;

typedef AssFiche = Map<String, Object?>;

// --- dates : la sémantique de `new Date(texte)` de JavaScript ------------------------------------------------------------
final _dateSeule = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// `YYYY-MM-DD` seul = minuit UTC ; avec heure sans fuseau = heure locale ; avec fuseau = cet instant.
DateTime assDate(Object? v) {
  if (v is DateTime) return v;
  final t = '${v ?? ''}';
  if (_dateSeule.hasMatch(t)) return DateTime.parse('${t}T00:00:00Z');
  return DateTime.tryParse(t) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

bool assDateValide(Object? v) =>
    v is DateTime || (v != null && DateTime.tryParse('$v') != null);

/// `C.daysBetween(a, b)` : `Math.round((b − a) / 86 400 000)`.
int assJours(Object? a, DateTime b) => joursEntre(assDate(a), b);

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;
bool _actif(Map f) => f['statut'] != 'archive';
double _n(Object? v) => nombreOuZero(v);

double assSomme(Iterable<AssFiche> l, String cle) =>
    l.fold(0.0, (a, x) => a + _n(x[cle]));

// --- sélections --------------------------------------------------------------------------------------------------------------
/// `assures()` : les patients actifs qui portent une compagnie.
List<AssFiche> assAssures(Iterable<AssFiche> patients) =>
    [for (final p in patients) if (_actif(p) && _vrai(p['assureur'])) p];

/// `facturesAssurance()` : les factures actives qui portent une compagnie.
List<AssFiche> assFacturesAssurance(Iterable<AssFiche> factures) =>
    [for (final f in factures) if (_actif(f) && _vrai(f['assureur'])) f];

/// `creanceAssureur(code)` : la somme des parts assureur (le reliquat des factures prises en charge).
double assCreance(Iterable<AssFiche> facturesAssurance, String code) =>
    assSomme(facturesAssurance.where((f) => f['assureur'] == code), 'partAssurance');

/// `assureurNom(code)` : le nom de la compagnie, à défaut le code lui-même.
String assNomAssureur(String? code, Iterable<AssFiche> assureurs) {
  for (final a in assureurs) {
    if (a['code'] == code) return '${a['nom']}';
  }
  return '$code';
}

/// Les trois tranches d'ancienneté : la fabrique UNIQUE du filtre « Ancienneté de la dette » et de la balance âgée (deux découpages divergents ne se
/// verraient qu'en réunion). Une facture datée d'APRÈS aujourd'hui (jours négatifs) tombe dans « moins de 30 jours ».
const assTranches = ['moins30', '30a90', 'plus90'];

String assTrancheDe(int jours) =>
    jours <= 30 ? 'moins30' : (jours <= 90 ? '30a90' : 'plus90');

double assAnciennete(Iterable<AssFiche> facturesAssurance, String code,
        String tranche, DateTime auj) =>
    assSomme(
        facturesAssurance.where((x) =>
            x['assureur'] == code &&
            assTrancheDe(assJours(x['date'], auj)) == tranche),
        'partAssurance');

// --- tableau de bord ----------------------------------------------------------------------------------------------------------
class AssKpisDashboard {
  const AssKpisDashboard(
      {required this.compagnies,
      required this.assures,
      required this.valides,
      required this.expirees,
      required this.facturesAssurance,
      required this.creances,
      required this.tauxMoyen});
  final int compagnies, assures, valides, expirees, facturesAssurance;
  final double creances;

  /// `C.sum(assures, 'tauxPriseEnCharge') / n` ; 0 sans assuré.
  final double tauxMoyen;
}

/// La validité de la carte se lit AU MOTEUR (couverture datée) : l'appelant la passe en fonction, il ne s'en fait pas une copie.
AssKpisDashboard assKpisDashboard(
    {required List<AssFiche> assureurs,
    required List<AssFiche> patients,
    required List<AssFiche> factures,
    required bool Function(AssFiche) carteValide}) {
  final a = assAssures(patients);
  final fa = assFacturesAssurance(factures);
  final valides = a.where(carteValide).length;
  return AssKpisDashboard(
      compagnies: assureurs.where(_actif).length,
      assures: a.length,
      valides: valides,
      expirees: a.length - valides,
      facturesAssurance: fa.length,
      creances: assSomme(fa, 'partAssurance'),
      tauxMoyen: a.isEmpty ? 0 : assSomme(a, 'tauxPriseEnCharge') / a.length);
}

// --- compagnies ----------------------------------------------------------------------------------------------------------------
const assConventions = ['Signée', 'En cours de renouvellement', 'Suspendue'];

String assConvention(AssFiche a) =>
    _vrai(a['convention']) ? '${a['convention']}' : 'Signée';

/// Les cinq filtres avancés du référentiel : chacun répond à une question posée au bureau de la Directrice, pas à une colonne du tableau.
bool assFiltreCompagnie(String filtre, String valeur, AssFiche a,
    {required List<AssFiche> assures,
    required List<AssFiche> facturesAssurance,
    required bool Function(AssFiche) carteValide,
    required DateTime auj}) {
  final code = '${a['code']}';
  final mes = assures.where((x) => x['assureur'] == code).toList();
  switch (filtre) {
    case 'convention':
      return assConvention(a) == valeur;
    case 'creanceEtat':
      final c = assCreance(facturesAssurance, code);
      if (valeur == 'avec') return c > 0;
      if (valeur == 'sans') return c == 0;
      return c > 500000;
    case 'anciennete':
      return assAnciennete(facturesAssurance, code, valeur, auj) > 0;
    case 'portefeuille':
      if (valeur == 'aucun') return mes.isEmpty;
      if (valeur == 'petit') return mes.isNotEmpty && mes.length <= 9;
      return mes.length >= 10;
    case 'carte':
      if (mes.isEmpty) return false;
      final expirees = mes.where((x) => !carteValide(x)).length;
      return valeur == 'expiree' ? expirees > 0 : expirees == 0;
  }
  return true;
}

// --- assurés & cartes ---------------------------------------------------------------------------------------------------------
/// « Expire dans N j » (≤ 30 jours) ou « Valide » ; une carte non valide est « Expirée ».
String assValidite(AssFiche p, {required bool valide, required DateTime auj}) {
  if (!valide) return 'Expirée';
  final j = assJours(auj, assDate(p['carteExpiration'])) ;
  return j <= 30 ? 'Expire dans $j j' : 'Valide';
}

/// Résultat de `PR.changerCouverture` : un refus se NOMME ; sinon ce qu'il faut écrire (rien n'est écrasé — la couverture en cours est CLOSE).
class AssChangement {
  const AssChangement.refus(this.motif)
      : ok = false,
        reprise = null,
        fermer = null,
        nouvelle = null,
        majPatient = null;
  const AssChangement(
      {required this.reprise,
      required this.fermer,
      required this.nouvelle,
      required this.majPatient})
      : ok = true,
        motif = null;
  final bool ok;
  final String? motif;

  /// La couverture du dossier ancien, écrite AVANT d'être close (jamais écrite jusque-là) ; `null` si un historique existait déjà.
  final AssFiche? reprise;

  /// La couverture en cours à clore : `(id, fin)` — `id == null` quand c'est [reprise] (sa `fin` est déjà portée par la fiche).
  final ({String? id, String fin})? fermer;
  final AssFiche? nouvelle;

  /// Ce que la fiche du dossier reflète : la couverture en force AUJOURD'HUI (une bascule datée du mois prochain ne change rien ce matin).
  final AssFiche? majPatient;
}

String _jour(DateTime d) => iso(d);

/// `PR.changerCouverture(patient, v)` — ferme la couverture en cours à la veille de la date d'effet et en ouvre une nouvelle.
/// [historique] : les couvertures ACTIVES de ce patient. [maintenant] : l'horloge du poste.
AssChangement assChangerCouverture(AssFiche? patient,
    List<AssFiche> historique, AssFiche? v, DateTime maintenant) {
  if (patient == null) return const AssChangement.refus('Aucun patient désigné.');
  if (v == null || !_vrai(v['dateEffet'])) {
    return const AssChangement.refus(
        'La date d’effet est obligatoire : sans elle, la nouvelle couverture ne pourrait pas se distinguer de l’ancienne sur les pièces déjà émises.');
  }
  if (!_vrai(v['motif'])) {
    return const AssChangement.refus(
        'Le motif du changement est obligatoire (RG-12) — c’est lui qu’on relit quand une compagnie conteste une prise en charge.');
  }
  final dateEffet = '${v['dateEffet']}';
  final hist = [...historique]..sort((a, b) =>
      '${b['debut'] ?? '0000-00-00'}'.compareTo('${a['debut'] ?? '0000-00-00'}'));
  AssFiche? courante;
  for (final c in hist) {
    if (!_vrai(c['fin'])) {
      courante = c;
      break;
    }
  }
  AssFiche? reprise;
  // Première mise à jour d'un dossier ancien : la couverture qui s'achève n'a jamais été écrite. On l'inscrit AVANT de la clore.
  if (courante == null && _vrai(patient['assureur'])) {
    reprise = {
      'patientId': patient['id'],
      'patientCode': patient['code'],
      'patient': '${patient['nom']} ${patient['prenom']}',
      'assureur': patient['assureur'],
      'assureurNom': patient['assureurNom'],
      'numeroPolice': patient['numeroPolice'],
      'categorieAssurance': patient['categorieAssurance'],
      'tauxPriseEnCharge': patient['tauxPriseEnCharge'],
      'carteExpiration': patient['carteExpiration'],
      'souscripteurId': patient['souscripteurId'],
      'debut': null,
      'fin': null,
      'motif': 'Couverture reprise du dossier à la première mise à jour',
    };
    courante = reprise;
  }
  if (courante != null &&
      _vrai(courante['debut']) &&
      dateEffet.compareTo('${courante['debut']}') <= 0) {
    return AssChangement.refus(
        'La date d’effet (${dateFR(assDate(dateEffet))}) doit être postérieure au début de la couverture en cours (${dateFR(assDate(courante['debut']))}).');
  }
  final veille = _jour(assDate(dateEffet).subtract(const Duration(days: 1)));
  if (reprise != null) reprise['fin'] = veille;
  final nouvelle = <String, Object?>{
    'patientId': patient['id'],
    'patientCode': patient['code'],
    'patient': '${patient['nom']} ${patient['prenom']}',
    'assureur': _vrai(v['assureur']) ? v['assureur'] : null,
    'assureurNom': _vrai(v['assureurNom']) ? v['assureurNom'] : null,
    'numeroPolice': _vrai(v['numeroPolice']) ? v['numeroPolice'] : null,
    'categorieAssurance':
        _vrai(v['categorieAssurance']) ? v['categorieAssurance'] : null,
    'tauxPriseEnCharge': _n(v['tauxPriseEnCharge']),
    'carteExpiration': _vrai(v['carteExpiration']) ? v['carteExpiration'] : null,
    'souscripteurId': _vrai(v['souscripteurId']) ? v['souscripteurId'] : null,
    'debut': dateEffet,
    'fin': null,
    'motif': v['motif'],
  };
  // La fiche du dossier reflète la couverture EN FORCE aujourd'hui : on la cherche dans l'historique APRÈS le changement.
  final apres = <AssFiche>[
    for (final c in hist)
      (reprise == null && courante != null && c['id'] == courante['id'])
          ? {...c, 'fin': veille}
          : c,
    if (reprise != null) reprise,
    nouvelle,
  ];
  final auj = iso(maintenant);
  AssFiche? enForce;
  final tries = [...apres]..sort((a, b) =>
      '${b['debut'] ?? '0000-00-00'}'.compareTo('${a['debut'] ?? '0000-00-00'}'));
  for (final c in tries) {
    if (_vrai(c['debut']) && auj.compareTo('${c['debut']}') < 0) continue;
    if (_vrai(c['fin']) && auj.compareTo('${c['fin']}') > 0) continue;
    enForce = c;
    break;
  }
  final e = enForce ?? const <String, Object?>{};
  return AssChangement(
    reprise: reprise,
    fermer: courante == null
        ? null
        : (id: reprise != null ? null : '${courante['id']}', fin: veille),
    nouvelle: nouvelle,
    majPatient: {
      'assureur': _vrai(e['assureur']) ? e['assureur'] : null,
      'assureurNom': _vrai(e['assureurNom']) ? e['assureurNom'] : null,
      'numeroPolice': _vrai(e['numeroPolice']) ? e['numeroPolice'] : null,
      'categorieAssurance':
          _vrai(e['categorieAssurance']) ? e['categorieAssurance'] : null,
      'tauxPriseEnCharge': _vrai(e['tauxPriseEnCharge']) ? e['tauxPriseEnCharge'] : 0,
      'carteExpiration': _vrai(e['carteExpiration']) ? e['carteExpiration'] : null,
      'souscripteurId': _vrai(e['souscripteurId']) ? e['souscripteurId'] : null,
    },
  );
}

// --- conventions & garanties ---------------------------------------------------------------------------------------------------
/// `D.CATEGORIES_GARANTIE` — les seize catégories de garantie (identifiant, libellé).
const assCategoriesGarantie = [
  ('consultation', 'Consultations'),
  ('analyse', 'Analyses de laboratoire'),
  ('medicament', 'Médicaments et frais pharmaceutiques'),
  ('vitamine', 'Vitamines et fortifiants'),
  ('soin', 'Soins et actes infirmiers'),
  ('chirurgie', 'Chirurgie'),
  ('maternite', 'Maternité et accouchements'),
  ('hospitalisation', 'Hospitalisation'),
  ('imagerie', 'Imagerie et échographie'),
  ('ambulance', 'Ambulance'),
  ('dentaire', 'Dentaire'),
  ('optique', 'Optique'),
  ('vaccin', 'Vaccins'),
  ('kinesitherapie', 'Kinésithérapie'),
  ('certificat', 'Certificats médicaux'),
  ('autre', 'Autres prestations'),
];

String assLibelleCategorie(Object? id) {
  for (final c in assCategoriesGarantie) {
    if (c.$1 == id) return c.$2;
  }
  return '$id';
}

/// `D.UNITES_PLAFOND` / `PR.libelleUnite`.
const assUnitesPlafond = {
  'acte': 'par acte',
  'jour': 'par jour',
  'an': 'par an',
  'personne_an': 'par personne et par an',
  'personne_2ans': 'par personne, tous les deux ans',
};

String assLibelleUnite(Object? id) => assUnitesPlafond['$id'] ?? '$id';

/// Les catégories d'assurance d'un souscripteur ou d'un assuré : identifiant, libellé du filtre, badge (libellé, ton).
const assCategoriesAssurance = [
  ('entreprise', 'Assurance entreprise'),
  ('particulier', 'Assurance particulier'),
  ('personnel', 'Assurance personnel'),
];

/// `D.BAREME_REFERENCE` : le barème versé au dossier le 18/06/2026 — un régime EMPLOYEUR. Il donne la structure, pas les taux d'une convention.
class AssBareme {
  const AssBareme._();
  static const reference =
      'Conditions d’utilisation de la prise en charge — barème de remboursement';
  static const lieu = 'Cotonou';
  static const date = '2026-06-18';
  static const source =
      'DOC — Conditions d’utilisation de la prise en charge (18/06/2026)';
  static const garanties = <Map<String, Object?>>[
    {'code': 'G01', 'libelle': 'Consultation généraliste', 'categorie': 'consultation', 'taux': 80, 'plafond': 5000, 'unitePlafond': 'acte', 'zone': 'Bénin'},
    {'code': 'G02', 'libelle': 'Consultation spécialiste ou professeur', 'categorie': 'consultation', 'taux': 80, 'plafond': 10000, 'unitePlafond': 'acte', 'zone': 'Bénin'},
    {'code': 'G03', 'libelle': 'Hospitalisation — frais de chambre', 'categorie': 'hospitalisation', 'taux': 80, 'plafond': 15000, 'unitePlafond': 'jour', 'zone': 'Bénin'},
    {'code': 'G04', 'libelle': 'Frais pharmaceutiques', 'categorie': 'medicament', 'taux': 80, 'plafond': null, 'unitePlafond': null, 'zone': 'Bénin'},
    {'code': 'G05', 'libelle': 'Vitamines et fortifiants', 'categorie': 'vitamine', 'taux': 60, 'plafond': null, 'unitePlafond': null, 'zone': 'Bénin'},
    {'code': 'G06', 'libelle': 'Honoraires chirurgicaux', 'categorie': 'chirurgie', 'taux': 80, 'plafond': null, 'unitePlafond': null, 'zone': 'Bénin'},
    {'code': 'G07', 'libelle': 'Séjour de la mère accompagnant un enfant de moins de 5 ans', 'categorie': 'hospitalisation', 'taux': 80, 'plafond': 7500, 'unitePlafond': 'jour', 'zone': 'Bénin'},
    {'code': 'G08', 'libelle': 'Analyses et travaux de laboratoire', 'categorie': 'analyse', 'taux': 80, 'plafond': null, 'unitePlafond': null, 'zone': 'Bénin'},
    {'code': 'G09', 'libelle': 'Radiographie, échographie, scanner, IRM', 'categorie': 'imagerie', 'taux': 80, 'plafond': null, 'unitePlafond': null, 'zone': 'Bénin'},
    {'code': 'G10', 'libelle': 'Ambulance', 'categorie': 'ambulance', 'taux': 80, 'plafond': 20000, 'unitePlafond': 'acte', 'zone': 'Bénin'},
    {'code': 'G11', 'libelle': 'Kinésithérapie', 'categorie': 'kinesitherapie', 'taux': 80, 'plafond': 50000, 'unitePlafond': 'an', 'zone': 'Bénin'},
    {'code': 'G12', 'libelle': 'Dentaire', 'categorie': 'dentaire', 'taux': 80, 'plafond': null, 'unitePlafond': null, 'zone': 'Bénin'},
    {'code': 'G13', 'libelle': 'Prothèse dentaire (enfant de moins de 15 ans)', 'categorie': 'dentaire', 'taux': 65, 'plafond': 70000, 'unitePlafond': 'personne_an', 'zone': 'Bénin'},
    {'code': 'G14', 'libelle': 'Optique', 'categorie': 'optique', 'taux': 80, 'plafond': 120000, 'unitePlafond': 'personne_2ans', 'zone': 'Bénin'},
    {'code': 'G15', 'libelle': 'Vaccins (DT, fièvre jaune, coqueluche, polio, ROUVAX)', 'categorie': 'vaccin', 'taux': 55, 'plafond': 50000, 'unitePlafond': 'personne_an', 'zone': 'Bénin'},
    {'code': 'G16', 'libelle': 'Consultation pré et post-natale', 'categorie': 'maternite', 'taux': 80, 'plafond': null, 'unitePlafond': null, 'zone': 'Bénin'},
    {'code': 'G17', 'libelle': 'Accouchement normal', 'categorie': 'maternite', 'taux': 80, 'plafond': 150000, 'unitePlafond': 'acte', 'zone': 'Bénin'},
    {'code': 'G18', 'libelle': 'Accouchement par voie chirurgicale', 'categorie': 'maternite', 'taux': 80, 'plafond': 250000, 'unitePlafond': 'acte', 'zone': 'Bénin'},
    {'code': 'G19', 'libelle': 'Accouchement gémellaire', 'categorie': 'maternite', 'taux': 80, 'plafond': 300000, 'unitePlafond': 'acte', 'zone': 'Bénin'},
    {'code': 'G20', 'libelle': 'Accouchement hors clinique privée', 'categorie': 'maternite', 'taux': 80, 'plafond': 175000, 'unitePlafond': 'acte', 'zone': 'Bénin'},
  ];
  static const actesExclus = [
    'Visites prénuptiales', 'Avortements et fausses couches chez les enfants', 'Soins et analyses de reproduction',
    'Soins esthétiques et de confort', 'Soins traditionnels', 'Traitement des malformations', 'Check-up et bilan de santé',
    'Pédicure et manucure', 'Massages', 'Rééducation hors accident', 'Kinésithérapie sans accord préalable',
    'Examens non prescrits', 'Prothèses dentaires', 'Détartrages',
  ];
  static const produitsExclus = [
    'Médicaments non prescrits', 'Contraceptifs et hormones sauf prescription', 'Laxatifs', 'Coton', 'Compresses', 'Bandes',
    'Sparadraps', 'Antiseptiques', 'Dentifrices', 'Savons', 'Vaccins', 'Compléments alimentaires', 'Appareils d’orthopédie',
    'Produits d’esthétique', 'Aphrodisiaques', 'Thermomètre', 'Seringue', 'Vessie de glace', 'Bassin de lit', 'Irrigateur',
    'Sonde', 'Ventouse', 'Gants',
  ];
  static const accordPrealable = [
    'Scanner', 'Laser', 'IRM', 'Fibroscopie', 'MAPA', 'Échocardiaque', 'Échodoppler', 'Aérosolthérapie', 'Optique',
    'Coloscopie', 'Hystérosalpingographie', 'EEG', 'EMG', 'Traitement de plus de 45 jours', 'Traitements antiviraux',
  ];
}

/// Une convention saisie : une garantie par ligne du barème de référence, taux et plafond AJUSTÉS par la clinique (plafond vide = sans plafond).
/// [taux] / [plafonds] : les valeurs saisies, dans l'ordre du barème ; `null` = champ laissé tel quel (le taux du barème), `''` = sans plafond.
List<AssFiche> assGarantiesDepuisBareme(AssFiche souscripteur,
    {required List<Object?> taux, required List<Object?> plafonds}) {
  final src = '${AssBareme.reference} — ajusté par la clinique';
  return [
    for (var i = 0; i < AssBareme.garanties.length; i++)
      () {
        final g = AssBareme.garanties[i];
        final t = i < taux.length ? taux[i] : null;
        final p = i < plafonds.length ? plafonds[i] : g['plafond'];
        return <String, Object?>{
          'souscripteurId': souscripteur['id'],
          'assureur': souscripteur['assureur'],
          'code': g['code'],
          'libelle': g['libelle'],
          'categorie': g['categorie'],
          'taux': t == null ? _n(g['taux']) : _n(t),
          'plafond': p == null || p == '' ? null : _n(p),
          'unitePlafond': g['unitePlafond'],
          'zone': g['zone'],
          'source': src,
        };
      }(),
  ];
}

/// La fiche d'un nouveau souscripteur (`transform` de `K.creer`) : nom de la compagnie, listes vides, provenance.
AssFiche assSouscripteurDepuis(
    Map<String, Object?> saisie, Iterable<AssFiche> assureurs) {
  final nom = assNomAssureur('${saisie['assureur']}', assureurs);
  return {
    ...saisie,
    'assureurNom': nom,
    'actesExclus': <Object?>[],
    'produitsExclus': <Object?>[],
    'accordPrealable': <Object?>[],
    'source': 'Convention saisie par la clinique',
  };
}

/// Les cinq prestations proposées au simulateur (libellé, catégorie, montant d'essai).
const assLignesSimulateur = <Map<String, Object?>>[
  {'libelle': 'Consultation généraliste', 'categorie': 'consultation', 'montant': 5000},
  {'libelle': 'NFS complète', 'categorie': 'analyse', 'montant': 4000},
  {'libelle': 'Artésunate 60 mg injectable', 'categorie': 'medicament', 'montant': 1100},
  {'libelle': 'Vitamine C 500 mg', 'categorie': 'vitamine', 'montant': 500},
  {'libelle': 'Journée d’hospitalisation', 'categorie': 'hospitalisation', 'montant': 25000},
];

// --- prises en charge ----------------------------------------------------------------------------------------------------------
/// Niveau de prise en charge : « totale » = taux 100 ; « partielle » = taux < 100 (le taux 0 en fait partie).
bool assNiveau(AssFiche f, String v) => v == 'totale'
    ? _n(f['tauxPriseEnCharge']) == 100
    : _n(f['tauxPriseEnCharge']) < 100;

// --- relevé & facture mensuelle ------------------------------------------------------------------------------------------------
class AssVentilation {
  AssVentilation(this.consultation, this.analyse, this.soin);
  double consultation, analyse, soin;
}

/// `ventiler(f)` : consultations / analyses / soins. Les factures nées du parcours portent leurs lignes catégorisées ; les plus anciennes n'ont que
/// leur nature (`type`) — on retombe sur elle.
AssVentilation assVentiler(AssFiche f) {
  final v = AssVentilation(0, 0, 0);
  final lignes = f['lignes'];
  if (lignes is List && lignes.isNotEmpty && _vrai((lignes.first as Map)['categorie'])) {
    for (final x in lignes) {
      final l = (x as Map).cast<String, Object?>();
      final montant = l['montant'] != null
          ? _n(l['montant'])
          : _n(l['quantite']) * _n(l['prixUnitaire']);
      final c = l['categorie'];
      if (c == 'consultation' || c == 'certificat') {
        v.consultation += montant;
      } else if (c == 'analyse') {
        v.analyse += montant;
      } else {
        v.soin += montant;
      }
    }
    return v;
  }
  final t = '${f['type'] ?? ''}';
  if (RegExp('Consultation', caseSensitive: false).hasMatch(t)) {
    v.consultation = _n(f['montantTTC']);
  } else if (RegExp('Laboratoire', caseSensitive: false).hasMatch(t)) {
    v.analyse = _n(f['montantTTC']);
  } else {
    v.soin = _n(f['montantTTC']);
  }
  return v;
}

class AssLignePatient {
  AssLignePatient(this.patientId, this.patient, this.patientCode);
  final Object? patientId;
  final Object? patient;
  final String patientCode;
  final List<String> dates = [];
  double consultation = 0, analyse = 0, soin = 0, total = 0, assure = 0, assureur = 0;
}

class AssGroupeSouscripteur {
  AssGroupeSouscripteur(this.id, this.nom, this.police);
  final String id, nom, police;
  final Map<Object?, AssLignePatient> _lignes = {};
  List<AssLignePatient> patients = [];
  double total = 0, assure = 0, assureur = 0, consultation = 0, analyse = 0, soin = 0;
}

/// `parSouscripteur()` : un patient = une ligne du relevé, un souscripteur = un tableau ; triés par part assureur décroissante.
/// Les factures du mois : `assureur == code`, mois et année de la date (jour/mois LOCAL de l'instant, comme `getMonth()`).
List<AssGroupeSouscripteur> assReleveSouscripteurs({
  required List<AssFiche> facturesAssurance,
  required List<AssFiche> patients,
  required List<AssFiche> souscripteurs,
  required String code,
  required int mois,
  required int annee,
}) {
  final rows = [
    for (final f in facturesAssurance)
      if (f['assureur'] == code &&
          assDate(f['date']).toLocal().month - 1 == mois &&
          assDate(f['date']).toLocal().year == annee)
        f
  ];
  final groupes = <String, AssGroupeSouscripteur>{};
  for (final f in rows) {
    AssFiche? p;
    for (final x in patients) {
      if (_actif(x) && x['id'] == f['patientId']) {
        p = x;
        break;
      }
    }
    final sid = p != null && _vrai(p['souscripteurId']) ? '${p['souscripteurId']}' : 'SANS';
    AssFiche? s;
    if (sid != 'SANS') {
      for (final x in souscripteurs) {
        if (x['id'] == sid) s = x;
      }
    }
    final g = groupes.putIfAbsent(
        sid,
        () => AssGroupeSouscripteur(
            sid, s != null ? '${s['nom']}' : 'Sans souscripteur rattaché', s != null ? '${s['police']}' : '—'));
    final l = g._lignes.putIfAbsent(f['patientId'],
        () => AssLignePatient(f['patientId'], f['patient'], _vrai(f['patientCode']) ? '${f['patientCode']}' : '—'));
    final v = assVentiler(f);
    l.dates.add(dateFR(assDate(f['date'])));
    l.consultation += v.consultation;
    l.analyse += v.analyse;
    l.soin += v.soin;
    l.total += _n(f['montantTTC']);
    l.assure += _n(f['partPatient']);
    l.assureur += _n(f['partAssurance']);
  }
  final sortie = [
    for (final g in groupes.values)
      g
        ..patients = g._lignes.values.toList()
        ..total = g.patients.fold(0.0, (a, x) => a + x.total)
        ..assure = g.patients.fold(0.0, (a, x) => a + x.assure)
        ..assureur = g.patients.fold(0.0, (a, x) => a + x.assureur)
        ..consultation = g.patients.fold(0.0, (a, x) => a + x.consultation)
        ..analyse = g.patients.fold(0.0, (a, x) => a + x.analyse)
        ..soin = g.patients.fold(0.0, (a, x) => a + x.soin)
  ];
  // `Array.prototype.sort` est stable : à part égale, l'ordre d'apparition est conservé.
  final indexes = {for (var i = 0; i < sortie.length; i++) sortie[i]: i};
  sortie.sort((a, b) {
    final c = b.assureur.compareTo(a.assureur);
    return c != 0 ? c : indexes[a]!.compareTo(indexes[b]!);
  });
  return sortie;
}

/// Contrôle de cohérence : les deux pièces doivent se recouper (total = assuré + assureur ; total = consultations + analyses + soins, à 1 F près).
List<AssGroupeSouscripteur> assEcartsReleve(List<AssGroupeSouscripteur> groupes) => [
      for (final g in groupes)
        if ((g.total - (g.assure + g.assureur)).abs() > 1 ||
            (g.total - (g.consultation + g.analyse + g.soin)).abs() > 1)
          g
    ];

/// `FA 141/08/CNT/2026` : le numéro de la facture mensuelle (nombre de souscripteurs + 140, mois sur deux chiffres).
String assNumeroFactureMensuelle(int nbGroupes, int mois, int annee) =>
    'FA ${(nbGroupes + 140).toString().padLeft(3, '0')}/${(mois + 1).toString().padLeft(2, '0')}/CNT/$annee';

// --- historique par assureur -----------------------------------------------------------------------------------------------------
/// Les prestations assurées de la plage [du, au] (bornes incluses, comparées en instants comme `getTime()`), pour une compagnie ou toutes.
List<AssFiche> assHistorique({
  required List<AssFiche> facturesAssurance,
  required List<AssFiche> patients,
  required List<AssFiche> souscripteurs,
  required List<AssFiche> assureurs,
  required String code,
  required String du,
  required String au,
}) {
  final d1 = assDate(du).millisecondsSinceEpoch;
  final d2 = assDate(au).millisecondsSinceEpoch;
  final sortie = <AssFiche>[];
  for (final f in facturesAssurance) {
    final d = assDate(f['date']).millisecondsSinceEpoch;
    if (d < d1 || d > d2) continue;
    if (code.isNotEmpty && f['assureur'] != code) continue;
    AssFiche? p;
    for (final x in patients) {
      if (_actif(x) && x['id'] == f['patientId']) {
        p = x;
        break;
      }
    }
    AssFiche? s;
    if (p != null && _vrai(p['souscripteurId'])) {
      for (final x in souscripteurs) {
        if (x['id'] == p['souscripteurId']) s = x;
      }
    }
    sortie.add({
      ...f,
      'souscripteurNom': s != null ? s['nom'] : '—',
      'police': s != null ? s['police'] : '—',
      'assureurNom': assNomAssureur('${f['assureur']}', assureurs),
    });
  }
  return sortie;
}

// --- créances ------------------------------------------------------------------------------------------------------------------
class AssLigneCreance {
  const AssLigneCreance(
      {required this.code,
      required this.nom,
      required this.nbFactures,
      required this.total,
      required this.moins30,
      required this.de30a90,
      required this.plus90});
  final String code, nom;
  final int nbFactures;
  final double total, moins30, de30a90, plus90;
}

/// La balance âgée : les bornes portent sur la DATE DE LA FACTURE, l'ancienneté se compte TOUJOURS par rapport à aujourd'hui — les confondre ferait
/// vieillir une créance parce qu'on a rétréci la fenêtre. [du]/[au] : `YYYY-MM-DD` ou vide ; [anciennete] : '' ou une tranche ; [seuil] : 0 = tout.
List<AssLigneCreance> assBalanceAgee({
  required List<AssFiche> assureurs,
  required List<AssFiche> facturesAssurance,
  required DateTime auj,
  String du = '',
  String au = '',
  String compagnie = '',
  String anciennete = '',
  num seuil = 0,
}) {
  bool dansPlage(AssFiche f) {
    final s = '${f['date'] ?? ''}';
    final d = s.length >= 10 ? s.substring(0, 10) : s;
    if (du.isNotEmpty && d.compareTo(du) < 0) return false;
    if (au.isNotEmpty && d.compareTo(au) > 0) return false;
    return true;
  }

  final rows = <AssLigneCreance>[];
  for (final a in assureurs) {
    final code = '${a['code']}';
    final f = [
      for (final x in facturesAssurance)
        if (x['assureur'] == code && dansPlage(x)) x
    ];
    double dans(String t) => assSomme(
        f.where((x) => assTrancheDe(assJours(x['date'], auj)) == t), 'partAssurance');
    final r = AssLigneCreance(
        code: code,
        nom: '${a['nom']}',
        nbFactures: f.length,
        total: assSomme(f, 'partAssurance'),
        moins30: dans('moins30'),
        de30a90: dans('30a90'),
        plus90: dans('plus90'));
    if (!(r.total > 0)) continue;
    if (compagnie.isNotEmpty && r.code != compagnie) continue;
    if (anciennete.isNotEmpty) {
      final v = anciennete == 'moins30'
          ? r.moins30
          : (anciennete == '30a90' ? r.de30a90 : r.plus90);
      if (!(v > 0)) continue;
    }
    if (seuil > 0 && r.total < seuil) continue;
    rows.add(r);
  }
  return rows;
}

// --- relances ----------------------------------------------------------------------------------------------------------------
const assNiveauxRelance = ['1re relance', '2e relance', 'Mise en demeure'];
const assCanauxRelance = [
  'Courrier remis en main propre',
  'Courrier électronique',
  'Courrier recommandé',
  'Appel téléphonique',
];
const assSuitesRelance = [
  ('en_attente', 'En attente'),
  ('regularisee', 'Régularisée'),
  ('contestee', 'Contestée'),
];

/// `REL-0001` : la référence suit le registre (le plus grand numéro existant + 1). La maquette tirait `C.nextRef('REL-', 4)`, un compteur de
/// SESSION qui repart à 0001 à chaque chargement : voir E500 de `ECARTS-MAQUETTE.md`.
String assReferenceRelance(Iterable<AssFiche> relances) {
  var max = 0;
  for (final r in relances) {
    final m = RegExp(r'^REL-(\d+)$').firstMatch('${r['reference'] ?? ''}');
    if (m != null) {
      final n = int.parse(m.group(1)!);
      if (n > max) max = n;
    }
  }
  return 'REL-${(max + 1).toString().padLeft(4, '0')}';
}

/// Les paragraphes de la lettre de relance ou de la mise en demeure (le niveau décide du ton).
List<String> assLettreRelance(AssFiche r) {
  final demeure = r['niveau'] == 'Mise en demeure';
  return [
    'Madame, Monsieur,',
    'Sauf erreur ou omission de notre part, nous constatons que la somme de ${money(r['montant'])}, correspondant aux prestations réalisées au profit de vos assurés au titre de la période ${r['periode']}, demeure impayée à ce jour.',
    demeure
        ? 'En conséquence, nous vous mettons en demeure de procéder au règlement de cette somme dans un délai de quinze (15) jours à compter de la réception de la présente. À défaut, nous nous réservons le droit de suspendre la prise en charge de vos assurés et d’engager toute procédure utile au recouvrement de notre créance.'
        : 'Nous vous saurions gré de bien vouloir procéder au règlement dans les meilleurs délais. Si ce règlement a été effectué entre-temps, nous vous prions de ne pas tenir compte de la présente.',
    if (_vrai(r['observations'])) '${r['observations']}',
    'Nous vous prions d’agréer, Madame, Monsieur, l’expression de nos salutations distinguées.',
  ];
}

// --- facture mère ------------------------------------------------------------------------------------------------------------
/// Les quatre périodicités de la facture mère : (code, libellé, jours).
const assPeriodesMere = [
  ('mois', 'Mensuelle', 30),
  ('trimestre', 'Trimestrielle', 90),
  ('semestre', 'Semestrielle', 180),
  ('annee', 'Annuelle', 365),
];

class AssFilleMere {
  AssFilleMere(this.souscripteur);
  final String souscripteur;
  final List<AssFiche> factures = [];
  double montant = 0, assureur = 0, patient = 0;
  int lignes = 0;
}

/// `filles()` : une par souscripteur, agrégée depuis les factures patients réellement émises sur la période (`date >= depuis`, SANS borne haute).
/// La facture porte tantôt le CODE de l'assureur, tantôt son NOM : comparer à l'un seulement afficherait « 0 souscripteur ».
List<AssFilleMere> assFillesMere(
    List<AssFiche> factures, String code, String nom, String depuis) {
  final parSous = <String, AssFilleMere>{};
  for (final f in factures) {
    if (!_actif(f)) continue;
    final a = '${f['assureur'] ?? ''}';
    final correspond = a == code || a == nom;
    final d = '${f['date'] ?? ''}';
    if (!(correspond &&
        _n(f['partAssurance']) > 0 &&
        (d.length >= 10 ? d.substring(0, 10) : d).compareTo(depuis) >= 0)) continue;
    final sous = _vrai(f['souscripteur']) ? '${f['souscripteur']}' : 'Sans souscripteur désigné';
    final g = parSous.putIfAbsent(sous, () => AssFilleMere(sous));
    g.factures.add(f);
    g.montant += _n(f['montantTTC']);
    g.assureur += _n(f['partAssurance']);
    g.patient += _n(f['partPatient']);
    g.lignes += (f['lignes'] is List ? (f['lignes'] as List).length : 0);
  }
  final cles = parSous.keys.toList()..sort();
  return [for (final k in cles) parSous[k]!];
}

class AssRapprochement {
  const AssRapprochement(
      {required this.totalFilles,
      required this.totalFactures,
      required this.totalLignes,
      required this.ecarts,
      required this.concorde,
      required this.vide,
      required this.nbFactures});
  final double totalFilles, totalFactures, totalLignes;
  final List<String> ecarts;

  /// Un rapprochement SANS PIÈCE n'est pas concordant, il est vide : les confondre laisserait émettre une facture mère à zéro franc.
  final bool concorde, vide;
  final int nbFactures;
}

/// Le contrôle qui donne son sens à la pièce : trois totaux doivent coïncider (souscripteurs, factures patients, détail ligne à ligne).
/// Un écart nomme la pièce en cause.
AssRapprochement assRapprocher(List<AssFilleMere> filles) {
  final totalFilles = filles.fold(0.0, (n, g) => n + g.assureur);
  final toutes = [for (final g in filles) ...g.factures];
  final totalFactures = toutes.fold(0.0, (n, f) => n + _n(f['partAssurance']));
  double somLignes(AssFiche f) => (f['lignes'] is List ? f['lignes'] as List : const [])
      .fold(0.0, (m, l) => m + _n((l as Map)['partAssureur']));
  final totalLignes = toutes.fold(0.0, (n, f) => n + somLignes(f));
  final ecarts = <String>[];
  if (totalFilles != totalFactures) {
    ecarts.add(
        'Le total des souscripteurs (${money(totalFilles)}) diffère du total des factures patients (${money(totalFactures)}).');
  }
  if (totalFactures != totalLignes) {
    ecarts.add(
        'Le total des factures (${money(totalFactures)}) diffère du détail ligne à ligne (${money(totalLignes)}) — c’est le niveau auquel la compagnie contestera.');
    for (final f in toutes) {
      final s = somLignes(f);
      if (s != _n(f['partAssurance'])) {
        ecarts.add(
            'Pièce ${f['numero']} — ${f['patient']} : part assureur ${money(f['partAssurance'])} pour ${money(s)} au détail.');
      }
    }
  }
  return AssRapprochement(
      totalFilles: totalFilles,
      totalFactures: totalFactures,
      totalLignes: totalLignes,
      ecarts: ecarts,
      concorde: ecarts.isEmpty && toutes.isNotEmpty,
      vide: toutes.isEmpty,
      nbFactures: toutes.length);
}

/// La fiche d'une facture mère ÉMISE. [nbExistantes] : le nombre de fiches de la collection, ARCHIVÉES COMPRISES (le numéro ne se réutilise jamais) ;
/// [annee] : l'année de l'horloge réelle. Les numéros des filles sont FIGÉS : ils permettront, dans six mois, de refaire le rapprochement.
AssFiche assEmettreMere({
  required String code,
  required String nom,
  required String periode,
  required List<AssFilleMere> filles,
  required AssRapprochement rap,
  required String depuis,
  required DateTime auj,
  required int nbExistantes,
  required String emisePar,
}) {
  final label = assPeriodesMere.firstWhere((p) => p.$1 == periode).$2;
  return {
    'numero': 'FM-${auj.year}-${(nbExistantes + 1).toString().padLeft(4, '0')}',
    'compagnieCode': code,
    'compagnie': nom,
    'periode': periode,
    'periodeLabel': label,
    'debut': depuis,
    'fin': iso(auj),
    'dateEmission': iso(auj),
    'nbSouscripteurs': filles.length,
    'nbFactures': rap.nbFactures,
    'montantReclame': rap.totalFilles,
    'souscripteurs': [
      for (final g in filles)
        {
          'souscripteur': g.souscripteur,
          'nbFactures': g.factures.length,
          'montant': g.montant,
          'assureur': g.assureur,
          'patient': g.patient,
        }
    ],
    'piecesFilles': [
      for (final g in filles) for (final f in g.factures) f['numero']
    ],
    'controle': {
      'totalFilles': rap.totalFilles,
      'totalFactures': rap.totalFactures,
      'totalLignes': rap.totalLignes,
      'concordant': true,
    },
    'etat': 'transmise',
    'emisePar': emisePar,
  };
}

/// Refus NOMMÉ d'un règlement de facture mère : rien n'est écrit.
class RefusReglementMere implements Exception {
  const RefusReglementMere(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

/// Ce qu'un règlement de facture mère écrit : le patch de la mère, la ligne de règlement et ses DEUX écritures (banque / créance), en brouillon.
class ReglementMere {
  const ReglementMere(
      {required this.patch,
      required this.reglement,
      required this.ecritures,
      required this.solde});

  /// Ce qu'il faut écrire sur la facture mère (`reglements`, `montantRegle`, `reliquat`, `dateReglement`, `referenceReglement`, `etat`).
  final AssFiche patch;

  /// La ligne de règlement ajoutée (l'appelant renseigne `ecritureIds` après avoir inséré les écritures).
  final AssFiche reglement;

  /// Les deux lignes plates : débit 521000 Banque, crédit 411110 Clients compagnie d'assurance (RG-10 contrôlé avant écriture).
  final List<AssFiche> ecritures;
  final bool solde;
}

/// Les règlements d'une mère : la liste `reglements`, ou, pour une pièce de l'ancienne génération (un seul `montantRegle`), UN règlement.
List<AssFiche> assReglementsDe(AssFiche mere) {
  final l = mere['reglements'];
  if (l is List) return [for (final x in l) (x as Map).cast<String, Object?>()];
  return _vrai(mere['montantRegle'])
      ? [
          {
            'date': mere['dateReglement'],
            'montant': mere['montantRegle'],
            'reference': mere['referenceReglement'] ?? '',
            'ancien': true,
          }
        ]
      : <AssFiche>[];
}

double assTotalRegle(AssFiche mere) => assSomme(assReglementsDe(mere), 'montant');

/// Le reste dû : la facture moins la SOMME des règlements, jamais négatif.
double assResteDuMere(AssFiche mere) {
  final r = _n(mere['montantReclame']) - assTotalRegle(mere);
  return r > 0 ? r : 0.0;
}

/// Le règlement d'une facture mère (`reglerFactureMere`). Décision de la Direction du 31/10/2026 (B5, écart E501), corrigée dans la maquette PUIS portée :
/// les règlements sont CUMULATIFS et DATÉS (lignes de règlement) ; le solde est la facture moins la somme des règlements ; la pièce est soldée à zéro ;
/// un règlement ne dépasse jamais le dû ; chaque règlement pose sa propre écriture (débit 521000 Banque, crédit 411110, brouillon).
/// [ecritures] : celles déjà au journal (série annuelle `BQ-AAAA-NNNNN`). Lève [RefusReglementMere].
ReglementMere assReglerMere(
  AssFiche mere, {
  required String date,
  required num montant,
  required String reference,
  List<AssFiche> ecritures = const [],
  String utilisateur = '',
  String horodatage = '',
}) {
  final reste = assResteDuMere(mere);
  if (mere['etat'] == 'reglee' || reste <= 0) {
    throw RefusReglementMere(
        'La facture mère ${mere['numero']} est déjà soldée : aucun règlement de plus.');
  }
  final m = montant.toDouble();
  if (!(m > 0)) {
    throw const RefusReglementMere(
        'Le montant d’un règlement doit être strictement supérieur à 0 FCFA.');
  }
  if (m > reste) {
    throw RefusReglementMere(
        'Règlement refusé : ${money(m)} dépasseraient le dû de ${mere['numero']} (${money(reste)} restent à régler sur ${money(mere['montantReclame'])}).');
  }
  final jour = date.length >= 10 ? date.substring(0, 10) : date;
  if (jour.isEmpty) {
    throw const RefusReglementMere('La date du règlement est obligatoire.');
  }
  final ref = reference.trim();
  if (ref.isEmpty) {
    throw const RefusReglementMere(
        'La référence du virement ou du chèque est obligatoire.');
  }

  final prefixe = 'BQ-${jour.substring(0, 4)}-';
  var max = 0;
  for (final e in ecritures) {
    final n = e['numero'];
    if (n is String && n.startsWith(prefixe)) {
      final k = int.tryParse(n.substring(prefixe.length)) ?? 0;
      if (k > max) max = k;
    }
  }
  final numero = '$prefixe${(max + 1).toString().padLeft(5, '0')}';
  final base = <String, Object?>{
    'numero': numero,
    'date': jour,
    'journal': 'BQ',
    'journalLibelle': 'Journal de banque',
    'libelle':
        'Règlement facture mère ${mere['numero']}, ${mere['compagnie'] ?? ''} (réf. $ref)',
    'pieceId': mere['id'],
    'pieceNumero': mere['numero'],
    'origine': 'Règlement de facture mère',
    'statut': 'brouillon',
  };
  final lignes = <AssFiche>[
    {...base, 'compte': '521000', 'compteLibelle': 'Banque', 'debit': m, 'credit': 0},
    {
      ...base,
      'compte': '411110',
      'compteLibelle': 'Clients compagnie d’assurance',
      'debit': 0,
      'credit': m
    },
  ];

  final deja = assReglementsDe(mere);
  final reglement = <String, Object?>{
    'id': 'RGL${(deja.length + 1).toString().padLeft(3, '0')}',
    'date': jour,
    'montant': m,
    'reference': ref,
    'numeroEcriture': numero,
    'saisiPar': utilisateur,
    'horodatage': horodatage,
  };
  final tous = [...deja, reglement];
  final regle = assSomme(tous, 'montant');
  final nouveauReste = (_n(mere['montantReclame']) - regle) > 0
      ? _n(mere['montantReclame']) - regle
      : 0.0;
  return ReglementMere(
    patch: {
      'reglements': tous,
      'montantRegle': regle,
      'reliquat': nouveauReste,
      'dateReglement': jour,
      'referenceReglement': ref,
      'etat': nouveauReste <= 0 ? 'reglee' : 'transmise',
    },
    reglement: reglement,
    ecritures: lignes,
    solde: nouveauReste <= 0,
  );
}

/// Ce que l'enregistrement d'une convention écrit sur le souscripteur : la grille est saisie, et les exclusions / accords du barème sont repris.
AssFiche assConventionSaisie() => {
      'grilleSaisie': true,
      'actesExclus': [...AssBareme.actesExclus],
      'produitsExclus': [...AssBareme.produitsExclus],
      'accordPrealable': [...AssBareme.accordPrealable],
    };
