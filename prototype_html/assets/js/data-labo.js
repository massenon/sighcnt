/* =============================================================================
 * SIGH-CNT — Laboratoire : bulletin, unités, valeurs de référence, variables
 * -----------------------------------------------------------------------------
 * DEUX DOCUMENTS RÉELS FONDENT CE FICHIER, et ils ne disent pas la même chose :
 *
 *   BULLETIN   « BULLETIN D'ANNALYSE BIO-MEDICALES » — le formulaire papier de
 *              demande. Il donne le CATALOGUE et son classement en six
 *              sections : hématologie, sérologie, parasitologie, biochimie,
 *              bactériologie, hormonologie.
 *
 *   RÉSULTATS  Fiche de résultats du dossier 2026080411, éditée le 21/08/2026.
 *              Elle donne les VARIABLES de chaque examen, leurs UNITÉS et leurs
 *              VALEURS DE RÉFÉRENCE — telles que le laboratoire les rend.
 *
 * Ce que la fiche de résultats a corrigé, et qu'il ne faut pas réintroduire :
 *
 *   — la formule leucocytaire est rendue en VALEURS ABSOLUES (G/l), pas en
 *     pourcentages. Lymphocytes 0,70 G/l pour une référence de 1 à 4,5 ;
 *   — les bornes du laboratoire ne sont PAS celles des manuels : hémoglobine
 *     11–14 g/dl sans distinction de sexe, GB 4–8 G/l, GR 3,5–5,3 T/l ;
 *   — la CCMH s'exprime en g/dl, pas en pourcentage ;
 *   — le VIH porte TROIS tests, chacun avec le NOM, le LOT et la DATE
 *     D'EXPIRATION de son réactif, puis une conclusion ;
 *   — la CRP porte deux variables : une issue qualitative et un taux sérique ;
 *   — l'ASLO est rendue en positif / négatif, pas en UI/l ;
 *   — « TBG » est le TEST BIOLOGIQUE DE GROSSESSE, pas une hormone thyroïdienne :
 *     la TSH figure séparément au bulletin.
 *
 * Une divergence entre les deux pièces est CONSERVÉE, non arbitrée : le
 * sérodiagnostic de Widal est classé en parasitologie sur le bulletin et en
 * sérologie sur la fiche de résultats. Le champ `sectionResultat` porte la
 * seconde ; c'est au biologiste de trancher, pas au logiciel.
 *
 * Enfin, `aValider` distingue ce qui est DOCUMENTÉ de ce qui ne l'est pas.
 * Les bornes lues sur la fiche de résultats valent `false` ; celles qu'il a
 * fallu suppléer pour les examens du bulletin absents de la fiche valent
 * `true`, et les écrans le disent. Les valeurs de référence dépendent du
 * réactif : le biologiste doit pouvoir les corriger, et c'est prévu.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* --------------------------------------------------------------------------
   * 1. SECTIONS DU BULLETIN
   * ----------------------------------------------------------------------- */
  var SECTIONS = [
    { id: 'hematologie', label: 'Hématologie', ordre: 1, icon: 'droplets', tone: 'danger' },
    { id: 'serologie', label: 'Sérologie', ordre: 2, icon: 'shield-alert', tone: 'warning' },
    { id: 'parasitologie', label: 'Parasitologie', ordre: 3, icon: 'bug', tone: 'success' },
    { id: 'biochimie', label: 'Biochimie', ordre: 4, icon: 'flask-conical', tone: 'info' },
    { id: 'bacteriologie', label: 'Bactériologie', ordre: 5, icon: 'microscope', tone: 'navy' },
    { id: 'hormonologie', label: 'Hormonologie', ordre: 6, icon: 'activity', tone: 'info' },
  ];

  /* --------------------------------------------------------------------------
   * 2. SERVICES DEMANDEURS ET CARACTÈRE D'URGENCE
   * Le document « Observations complémentaires » les impose OBLIGATOIRES sur la
   * fiche de demande, et distingue l'urgence d'UN examen de celle de TOUT le
   * bilan — ce ne sont pas les mêmes consignes pour le laboratoire.
   * ----------------------------------------------------------------------- */
  var SERVICES_DEMANDEURS = [
    { id: 'maternite', label: 'Maternité', ordre: 1 },
    { id: 'medecine', label: 'Médecine', ordre: 2 },
    { id: 'specialite', label: 'Médecine et spécialité', ordre: 3 },
  ];

  var NIVEAUX_URGENCE = [
    { id: 'aucune', label: 'Examen courant', tone: 'neutral', delaiHeures: null },
    { id: 'examen', label: 'Un examen urgent', tone: 'warning', delaiHeures: 2,
      aide: 'Seul l’examen coché est traité en urgence ; le reste du bilan suit le circuit courant.' },
    { id: 'bilan', label: 'Bilan entier en urgence', tone: 'danger', delaiHeures: 1,
      aide: 'Tout le bilan est traité en urgence — à réserver aux situations qui l’exigent.' },
  ];

  var ORIGINES_PATIENT = [
    { id: 'interne', label: 'Patient interne', aide: 'Reçu ou hospitalisé dans la clinique — le résultat part au prescripteur.' },
    { id: 'externe', label: 'Patient externe', aide: 'Adressé de l’extérieur — le résultat lui est remis directement.' },
  ];

  /* --------------------------------------------------------------------------
   * 3. UNITÉS — pré-insérées, comme demandé
   * Les symboles sont ceux de la fiche de résultats : « G/l », « T/l », « g/dl »
   * — et non les notations normalisées 10⁹/L ou g/L. Le laboratoire lit ce
   * qu'il écrit ; changer sa notation pour une autre, plus « correcte »,
   * l'obligerait à traduire à chaque lecture.
   * ----------------------------------------------------------------------- */
  var UNITES = [
    { id: 'g_l_hb', symbole: 'G/l', libelle: 'giga par litre', domaine: 'Hématologie', source: 'Fiche de résultats CNT' },
    { id: 't_l', symbole: 'T/l', libelle: 'téra par litre', domaine: 'Hématologie', source: 'Fiche de résultats CNT' },
    { id: 'g_dl', symbole: 'g/dl', libelle: 'gramme par décilitre', domaine: 'Hématologie', source: 'Fiche de résultats CNT' },
    { id: 'fl', symbole: 'fl', libelle: 'femtolitre', domaine: 'Hématologie', source: 'Fiche de résultats CNT' },
    { id: 'pg', symbole: 'pg', libelle: 'picogramme', domaine: 'Hématologie', source: 'Fiche de résultats CNT' },
    { id: 'mm', symbole: 'mm', libelle: 'millimètre (sédimentation)', domaine: 'Hématologie', source: 'Fiche de résultats CNT' },
    { id: 'pourcent', symbole: '%', libelle: 'pour cent', domaine: 'Général', source: 'Fiche de résultats CNT' },
    { id: 'g_l', symbole: 'g/l', libelle: 'gramme par litre', domaine: 'Biochimie', source: 'Fiche de résultats CNT' },
    { id: 'mg_l', symbole: 'mg/l', libelle: 'milligramme par litre', domaine: 'Biochimie', source: 'Fiche de résultats CNT' },
    { id: 'mmol_l', symbole: 'mmol/l', libelle: 'millimole par litre', domaine: 'Biochimie', source: 'Fiche de résultats CNT' },
    { id: 'ui_l', symbole: 'UI/l', libelle: 'unité internationale par litre', domaine: 'Biochimie', source: 'Fiche de résultats CNT' },
    { id: 'ng_ml', symbole: 'ng/ml', libelle: 'nanogramme par millilitre', domaine: 'Hormonologie', source: 'Fiche de résultats CNT' },
    { id: 'parasites_ul', symbole: 'parasites/µl', libelle: 'parasites par microlitre', domaine: 'Parasitologie', source: 'Fiche de résultats CNT' },
    { id: 'uui_ml', symbole: 'µUI/ml', libelle: 'micro-unité internationale par millilitre', domaine: 'Hormonologie', aValider: true },
    { id: 'pg_ml', symbole: 'pg/ml', libelle: 'picogramme par millilitre', domaine: 'Hormonologie', aValider: true },
    { id: 'mui_ml', symbole: 'mUI/ml', libelle: 'milli-unité internationale par millilitre', domaine: 'Hormonologie', aValider: true },
    { id: 'secondes', symbole: 's', libelle: 'seconde', domaine: 'Hémostase', aValider: true },
    { id: 'minutes', symbole: 'min', libelle: 'minute', domaine: 'Hémostase', aValider: true },
    { id: 'par_champ', symbole: '/champ', libelle: 'par champ microscopique', domaine: 'Bactériologie', aValider: true },
    { id: 'ufc_ml', symbole: 'UFC/ml', libelle: 'unité formant colonie par millilitre', domaine: 'Bactériologie', aValider: true },
    { id: 'millions_ml', symbole: '10⁶/ml', libelle: 'million par millilitre', domaine: 'Andrologie', aValider: true },
    { id: 'ml', symbole: 'ml', libelle: 'millilitre', domaine: 'Andrologie', aValider: true },
    { id: 'sans', symbole: '—', libelle: 'sans unité', domaine: 'Général' },
  ];

  /* --------------------------------------------------------------------------
   * 4. TYPES DE VARIABLE
   * ----------------------------------------------------------------------- */
  var TYPES_VARIABLE = [
    { id: 'numerique', label: 'Valeur numérique', icon: 'hash',
      aide: 'Une mesure et son unité, comparée à des bornes de référence.' },
    { id: 'binaire', label: 'Positif / Négatif', icon: 'toggle-left',
      valeurs: ['Positif', 'Négatif'], aide: 'Deux issues seulement.' },
    { id: 'ternaire', label: 'Positif / Négatif / Indéterminé', icon: 'circle-help',
      valeurs: ['Positif', 'Négatif', 'Indéterminé'],
      aide: 'Trois issues. Exigé par le VIH : un test discordant n’est ni positif ni négatif, '
        + 'et l’écrire « négatif » serait une faute.' },
    { id: 'titre', label: 'Titre (dilution)', icon: 'divide',
      valeurs: ['Négatif', '1/40', '1/80', '1/160', '1/320', '1/640', '1/1280'],
      aide: 'Une dilution — sérodiagnostic de Widal, VDRL quantitatif.' },
    { id: 'liste', label: 'Choix dans une liste', icon: 'list',
      aide: 'Un choix parmi des valeurs nommées, définies sur la variable.' },
    { id: 'texte', label: 'Texte libre', icon: 'text',
      aide: 'Une description : examen direct, culture, morphologie.' },
    { id: 'reactif', label: 'Réactif employé', icon: 'test-tube',
      aide: 'Nom commercial du réactif. Rétractable quand il cesse d’être exigé.' },
    { id: 'lot', label: 'Lot de réactif', icon: 'package',
      aide: 'Numéro de lot, tracé sur la fiche de résultats.' },
    { id: 'expiration', label: 'Expiration du réactif', icon: 'calendar-x',
      aide: 'Date de péremption du lot employé.' },
    { id: 'commentaire', label: 'Commentaire de l’examen', icon: 'message-square',
      aide: 'Interprétation propre à CET examen — distincte du commentaire général '
        + 'du compte rendu, qui porte sur l’échantillon.' },
  ];

  /* Les types qui accompagnent un résultat sans en être un. Ce sont eux que le
     biologiste « ferme » quand un changement de réactif les rend inutiles. */
  var TYPES_ACCOMPAGNEMENT = ['reactif', 'lot', 'expiration', 'commentaire'];

  /* --------------------------------------------------------------------------
   * 5. CATALOGUE DES EXAMENS — transcrit du bulletin papier
   * Forme : [code, désignation, section, échantillon, délai, options]
   * `options.sectionResultat` note un classement divergent sur la fiche de
   * résultats ; `options.absentFiche` marque un examen du bulletin dont la
   * fiche de résultats ne donne pas les paramètres.
   * ----------------------------------------------------------------------- */
  var EXAMENS = [
    /* --- Hématologie ---------------------------------------------------- */
    ['NFS', 'NFS complète (hémogramme)', 'hematologie', 'Sang total (EDTA)', '4 h'],
    ['RETIC', 'Taux de réticulocytes', 'hematologie', 'Sang total (EDTA)', '4 h', { absentFiche: true }],
    ['TS', 'Temps de saignement', 'hematologie', 'Capillaire', '2 h', { absentFiche: true }],
    ['TC', 'Temps de coagulation', 'hematologie', 'Sang total', '2 h', { absentFiche: true }],
    ['TP', 'Temps de prothrombine — INR', 'hematologie', 'Sang citraté', '6 h'],
    ['TCA', 'Temps de céphaline activée (TCA / TCK)', 'hematologie', 'Sang citraté', '6 h', { absentFiche: true }],
    ['VS', 'Vitesse de sédimentation', 'hematologie', 'Sang citraté', '4 h'],
    ['GSRH', 'Groupage sanguin — facteur Rhésus', 'hematologie', 'Sang total (EDTA)', '2 h'],
    ['EHB', 'Électrophorèse de l’hémoglobine', 'hematologie', 'Sang total (EDTA)', '72 h'],

    /* --- Sérologie ------------------------------------------------------- */
    ['AGHBS', 'Recherche AgHBs (hépatite B par test rapide)', 'serologie', 'Sérum', '4 h'],
    ['ACHCV', 'Anticorps anti-HCV', 'serologie', 'Sérum', '4 h'],
    ['ASLO', 'Antistreptolysine O (ASLO)', 'serologie', 'Sérum', '24 h'],
    ['TPHA', 'TPHA (syphilis)', 'serologie', 'Sérum', '24 h'],
    ['VDRL', 'VDRL', 'serologie', 'Sérum', '24 h'],
    ['VIH', 'VIH', 'serologie', 'Sérum', '4 h'],
    ['TOXO', 'Toxoplasmose', 'serologie', 'Sérum', '72 h', { absentFiche: true }],
    ['RUB', 'Rubéole', 'serologie', 'Sérum', '72 h', { absentFiche: true }],
    ['CHLAM', 'Chlamydiase', 'serologie', 'Sérum', '72 h', { absentFiche: true }],
    ['CRP', 'Protéine C-réactive (CRP)', 'serologie', 'Sérum', '4 h',
      { sectionBulletin: 'biochimie', note: 'Portée en biochimie sur le bulletin, en sérologie sur la fiche de résultats.' }],
    ['TBG', 'Test biologique de grossesse', 'serologie', 'Urine ou sérum', '1 h',
      { note: 'À ne pas confondre avec le dosage sérique de la ß-HCG, qui est quantitatif.' }],

    /* --- Parasitologie --------------------------------------------------- */
    ['GEDP', 'Goutte épaisse — densité parasitaire', 'parasitologie', 'Sang total (EDTA)', '2 h'],
    ['SDW', 'Sérodiagnostic de Widal', 'parasitologie', 'Sérum', '24 h',
      { sectionResultat: 'serologie',
        note: 'Classé en parasitologie sur le bulletin, en sérologie sur la fiche de résultats — divergence à trancher par le biologiste.' }],
    ['AKOP', 'AKOP — examen parasitologique des selles', 'parasitologie', 'Selles', '24 h',
      { sectionResultat: 'bacteriologie' }],
    ['MICRO', 'Recherche de microfilaires', 'parasitologie', 'Sang total', '24 h', { absentFiche: true }],
    ['BILH', 'Recherche d’œufs de bilharzie', 'parasitologie', 'Urine ou selles', '24 h', { absentFiche: true }],

    /* --- Biochimie ------------------------------------------------------- */
    ['GLYAJ', 'Glycémie à jeun', 'biochimie', 'Sérum ou plasma fluoré', '2 h'],
    ['GLYPP', 'Glycémie post-prandiale', 'biochimie', 'Sérum ou plasma fluoré', '2 h'],
    ['CREA', 'Créatinine', 'biochimie', 'Sérum', '4 h'],
    ['AZOT', 'Azotémie (urée)', 'biochimie', 'Sérum', '4 h'],
    ['CA', 'Calcémie', 'biochimie', 'Sérum', '4 h'],
    ['MG', 'Magnésémie', 'biochimie', 'Sérum', '4 h'],
    ['IONO', 'Ionogramme sanguin (Na, K, Cl)', 'biochimie', 'Sérum', '6 h'],
    ['TGO', 'Transaminases TGO / TGP', 'biochimie', 'Sérum', '4 h'],
    ['GGT', 'Gamma-GT', 'biochimie', 'Sérum', '4 h'],
    ['CHOLT', 'Cholestérol total', 'biochimie', 'Sérum', '4 h'],
    ['CHOLH', 'Cholestérol HDL', 'biochimie', 'Sérum', '4 h'],
    ['CHOLL', 'Cholestérol LDL', 'biochimie', 'Sérum', '4 h', { absentFiche: true }],
    ['TG', 'Triglycérides', 'biochimie', 'Sérum', '4 h'],
    ['BILI', 'Bilirubine totale, conjuguée et non conjuguée', 'biochimie', 'Sérum', '4 h'],
    ['PROT', 'Protidémie', 'biochimie', 'Sérum', '4 h'],
    ['LIPA', 'Lipasémie', 'biochimie', 'Sérum', '4 h', { absentFiche: true }],
    ['PHOS', 'Phosphorémie', 'biochimie', 'Sérum', '4 h'],
    ['PAL', 'Phosphatase alcaline', 'biochimie', 'Sérum', '4 h', { absentFiche: true }],
    ['G6PD', 'G6PD', 'biochimie', 'Sang total (EDTA)', '48 h', { absentFiche: true }],
    ['GLUCO', 'Glucorachie', 'biochimie', 'Liquide céphalo-rachidien', '2 h'],
    ['PROTR', 'Protéinorachie', 'biochimie', 'Liquide céphalo-rachidien', '2 h', { absentFiche: true }],
    ['DDIM', 'D-dimères', 'biochimie', 'Sang citraté', '24 h'],
    ['HBA1C', 'Hémoglobine glyquée (HbA1c)', 'biochimie', 'Sang total (EDTA)', '24 h'],
    ['URIC', 'Uricémie (acide urique)', 'biochimie', 'Sérum', '4 h'],

    /* --- Bactériologie ---------------------------------------------------- */
    ['ECBU', 'ECBU — examen cytobactériologique des urines', 'bacteriologie', 'Urine', '48 h'],
    ['PV', 'Prélèvement vaginal (PV)', 'bacteriologie', 'Prélèvement vaginal', '48 h'],
    ['ECBLCR', 'ECB du liquide céphalo-rachidien', 'bacteriologie', 'Liquide céphalo-rachidien', '48 h', { absentFiche: true }],
    ['ECBLP', 'ECB du liquide pleural', 'bacteriologie', 'Liquide pleural', '48 h', { absentFiche: true }],
    ['ECBLA', 'ECB du liquide d’ascite', 'bacteriologie', 'Liquide d’ascite', '48 h', { absentFiche: true }],
    ['ECBPUS', 'ECB du pus', 'bacteriologie', 'Pus', '48 h', { absentFiche: true }],
    ['PU', 'Prélèvement urétral (PU)', 'bacteriologie', 'Prélèvement urétral', '48 h', { absentFiche: true }],

    /* --- Hormonologie ------------------------------------------------------ */
    ['BHCG', 'ß-HCG (dosage sérique)', 'hormonologie', 'Sérum', '24 h', { absentFiche: true }],
    ['FSH', 'FSH', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['LH', 'LH', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['OEST', 'Œstradiol', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['PROG', 'Progestérone', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['PSAT', 'PSA total', 'hormonologie', 'Sérum', '72 h'],
    ['PSAL', 'PSA libre', 'hormonologie', 'Sérum', '72 h'],
    ['TESTO', 'Testostérone', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['AMH', 'AMH — hormone antimüllérienne', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['PRL', 'Prolactinémie', 'hormonologie', 'Sérum', '72 h'],
    ['TBGS', 'TBG sérique', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['TSH', 'TSH', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['T3', 'T3', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
    ['T4', 'T4', 'hormonologie', 'Sérum', '72 h', { absentFiche: true }],
  ].map(function (e, i) {
    var o = e[5] || {};
    return {
      id: 'EXA' + (i + 1 < 10 ? '0' : '') + (i + 1),
      code: e[0], designation: e[1], section: e[2],
      sectionResultat: o.sectionResultat || e[2],
      sectionBulletin: o.sectionBulletin || e[2],
      echantillon: e[3], delai: e[4],
      note: o.note || null,
      documente: !o.absentFiche,
      statut: 'actif',
      source: o.absentFiche
        ? 'Bulletin d’analyses bio-médicales — paramètres à définir par le biologiste'
        : 'Bulletin d’analyses bio-médicales + fiche de résultats CNT du 21/08/2026',
    };
  });

  /* --------------------------------------------------------------------------
   * 6. VARIABLES PAR EXAMEN
   * --------------------------------------------------------------------------
   * Forme : [code, libellé, type, unité, min, max, options]
   *   min/max  bornes lues sur la fiche de résultats (null = pas de borne) ;
   *   options.parent    code de la variable dont celle-ci est une SOUS-variable ;
   *   options.valeurs   choix d'une variable de type `liste` ;
   *   options.normal    issue attendue d'une variable binaire ou ternaire ;
   *   options.decimales décimales attendues à la saisie ;
   *   options.aValider  la borne n'est pas documentée — à confirmer ;
   *   options.regle     borne exprimée par une règle et non par un nombre.
   * ----------------------------------------------------------------------- */
  var V = {};

  /* --- Hématologie ------------------------------------------------------- */
  V.NFS = [
    ['GB', 'Globules blancs', 'numerique', 'g_l_hb', 4, 8, { decimales: 2 }],
    ['LY', 'Lymphocytes', 'numerique', 'g_l_hb', 1, 4.5, { parent: 'GB', decimales: 2 }],
    ['MO', 'Monocytes', 'numerique', 'g_l_hb', 0.2, 1, { parent: 'GB', decimales: 2 }],
    ['PNE', 'Polynucléaires éosinophiles', 'numerique', 'g_l_hb', 0.1, 0.4, { parent: 'GB', decimales: 2 }],
    ['PNB', 'Polynucléaires basophiles', 'numerique', 'g_l_hb', 0, 0.1, { parent: 'GB', decimales: 2 }],
    ['PNN', 'Polynucléaires neutrophiles', 'numerique', 'g_l_hb', 1.5, 6, { parent: 'GB', decimales: 2 }],
    ['GR', 'Globules rouges', 'numerique', 't_l', 3.5, 5.3, { decimales: 2 }],
    ['HB', 'Hémoglobine', 'numerique', 'g_dl', 11, 14, { decimales: 1 }],
    ['HTE', 'Hématocrite', 'numerique', 'pourcent', 35, 49, { decimales: 2 }],
    ['VGM', 'VGM', 'numerique', 'fl', 80, 100, { decimales: 2 }],
    ['CCMH', 'CCMH', 'numerique', 'g_dl', 32, 36, { decimales: 2 }],
    ['TCMH', 'TCMH', 'numerique', 'pg', 28, 32, { decimales: 2 }],
    ['PLQ', 'Plaquettes', 'numerique', 'g_l_hb', 150, 400, { decimales: 2 }],
  ];
  V.VS = [
    ['H1', 'Première heure', 'numerique', 'mm', null, 6, { decimales: 0 }],
    ['H2', 'Deuxième heure', 'numerique', 'mm', null, 10, { decimales: 0 }],
  ];
  V.EHB = [
    ['PHENO', 'Électrophorèse de l’hémoglobine', 'liste', 'sans', null, null, {
      valeurs: ['Hémoglobine AA', 'Hémoglobine AS', 'Hémoglobine SS', 'Hémoglobine AC',
        'Hémoglobine SC', 'Hémoglobine CC', 'Autre profil'],
      normal: 'Hémoglobine AA',
    }],
  ];
  V.GSRH = [
    ['GSRH', 'Groupe sanguin — Rhésus', 'liste', 'sans', null, null, {
      valeurs: ['A Rhésus Positif', 'A Rhésus Négatif', 'B Rhésus Positif', 'B Rhésus Négatif',
        'AB Rhésus Positif', 'AB Rhésus Négatif', 'O Rhésus Positif', 'O Rhésus Négatif'],
    }],
    ['DU', 'DU (Rhésus faible)', 'binaire', 'sans', null, null, { parent: 'GSRH', normal: 'Négatif' }],
  ];
  V.TP = [
    ['INR', 'INR', 'numerique', 'sans', 0.8, 1.2, { decimales: 2 }],
    ['TP', 'Taux de prothrombine', 'numerique', 'pourcent', 80, 100, { decimales: 2 }],
  ];
  V.TCA = [
    ['TCAM', 'Temps du malade', 'numerique', 'secondes', 25, 40, { decimales: 1, aValider: true }],
    ['TCAT', 'Temps du témoin', 'numerique', 'secondes', 25, 40, { parent: 'TCAM', decimales: 1, aValider: true }],
    ['TCAR', 'Rapport malade / témoin', 'numerique', 'sans', 0.8, 1.2, { parent: 'TCAM', decimales: 2, aValider: true }],
  ];
  V.TC = [['TCV', 'Temps de coagulation', 'numerique', 'minutes', 5, 10, { decimales: 0, aValider: true }]];
  V.TS = [['TSV', 'Temps de saignement', 'numerique', 'minutes', 2, 4, { decimales: 0, aValider: true }]];
  V.RETIC = [['RET', 'Réticulocytes', 'numerique', 'g_l_hb', 25, 100, { decimales: 1, aValider: true }]];

  /* --- Sérologie --------------------------------------------------------- */
  V.AGHBS = [
    ['AGHBS', 'Recherche AgHBs (hépatite B par test rapide)', 'binaire', 'sans', null, null, { normal: 'Négatif' }],
  ];
  V.ACHCV = [['ACHCV', 'Anticorps anti-HCV', 'binaire', 'sans', null, null, { normal: 'Négatif' }]];
  V.TPHA = [['TPHA', 'TPHA (syphilis)', 'binaire', 'sans', null, null, { normal: 'Négatif' }]];
  V.VDRL = [['VDRL', 'VDRL', 'binaire', 'sans', null, null, { normal: 'Négatif' }]];
  V.ASLO = [
    ['ASLO', 'Antistreptolysine O (ASLO)', 'binaire', 'sans', null, null, { normal: 'Négatif' }],
  ];
  V.TBG = [['TBG', 'Test biologique de grossesse', 'binaire', 'sans', null, null, { normal: 'Négatif' }]];

  /* Le VIH tel que la fiche le rend : trois tests, chacun avec le nom, le lot
     et l'expiration de son réactif, puis une conclusion. */
  V.VIH = [
    ['T1', 'VIH 1er test', 'ternaire', 'sans', null, null, { normal: 'Négatif' }],
    ['T1R', 'Réactif 1er test', 'reactif', 'sans', null, null, {
      parent: 'T1', valeurs: ['DETERMINE EARLY HIV1/2', 'WONDFO', 'First Response HIV 1/2', 'Uni-Gold HIV', 'SD Bioline HIV 1/2'],
    }],
    ['T1L', 'Lot réactif 1er test', 'lot', 'sans', null, null, { parent: 'T1' }],
    ['T1E', 'Expiration réactif 1er test', 'expiration', 'sans', null, null, { parent: 'T1' }],
    ['T2', 'VIH 2e test', 'ternaire', 'sans', null, null, { normal: 'Négatif' }],
    ['T2R', 'Réactif 2e test', 'reactif', 'sans', null, null, {
      parent: 'T2', valeurs: ['WONDFO', 'DETERMINE EARLY HIV1/2', 'First Response HIV 1/2', 'Uni-Gold HIV'],
    }],
    ['T2L', 'Lot réactif 2e test', 'lot', 'sans', null, null, { parent: 'T2' }],
    ['T2E', 'Expiration réactif 2e test', 'expiration', 'sans', null, null, { parent: 'T2' }],
    ['T3', 'VIH 3e test', 'ternaire', 'sans', null, null, { normal: 'Négatif' }],
    ['T3R', 'Réactif 3e test', 'reactif', 'sans', null, null, {
      parent: 'T3', valeurs: ['First Response HIV 1/2', 'DETERMINE EARLY HIV1/2', 'WONDFO', 'Uni-Gold HIV'],
    }],
    ['T3L', 'Lot réactif 3e test', 'lot', 'sans', null, null, { parent: 'T3' }],
    ['T3E', 'Expiration réactif 3e test', 'expiration', 'sans', null, null, { parent: 'T3' }],
    ['CONC', 'Conclusion', 'liste', 'sans', null, null, {
      valeurs: ['TEST NÉGATIF', 'TEST POSITIF', 'TEST INDÉTERMINÉ — à confirmer sur un second prélèvement'],
      normal: 'TEST NÉGATIF',
    }],
  ];

  /* Widal : le réactif d'abord, puis les huit antigènes dans l'ordre du
     document — tous les O, puis tous les H — et enfin le commentaire. */
  V.SDW = [
    ['REACT', 'Réactif', 'reactif', 'sans', null, null, {
      valeurs: ['BIO RAD', 'Fortress', 'Plasmatec', 'Cypress'],
    }],
    ['TO', 'TO', 'titre', 'sans', null, null, { normal: 'Négatif' }],
    ['AO', 'AO', 'titre', 'sans', null, null, { normal: 'Négatif' }],
    ['BO', 'BO', 'titre', 'sans', null, null, { normal: 'Négatif' }],
    ['CO', 'CO', 'titre', 'sans', null, null, { normal: 'Négatif' }],
    ['TH', 'TH', 'titre', 'sans', null, null, { normal: 'Négatif' }],
    ['AH', 'AH', 'titre', 'sans', null, null, { normal: 'Négatif' }],
    ['BH', 'BH', 'titre', 'sans', null, null, { normal: 'Négatif' }],
    ['CH', 'CH', 'titre', 'sans', null, null, { normal: 'Négatif' }],
    ['COMM', 'Commentaire', 'commentaire', 'sans', null, null, {
      valeurs: ['Absence d’argument sérologique en faveur d’une Salmonellose',
        'Présence d’arguments sérologiques en faveur d’une Salmonellose',
        'Résultat à confronter au contexte clinique et à une antériorité vaccinale'],
    }],
  ];

  /* La CRP porte DEUX variables : une issue qualitative et un taux. */
  V.CRP = [
    ['CRPQ', 'CRP', 'binaire', 'sans', null, null, { normal: 'Négatif' }],
    ['CRPT', 'Taux sérique', 'numerique', 'mg_l', null, 6, { parent: 'CRPQ', decimales: 2 }],
  ];

  V.TOXO = [
    ['IGG', 'IgG anti-toxoplasme', 'binaire', 'sans', null, null, { normal: 'Négatif', aValider: true }],
    ['IGM', 'IgM anti-toxoplasme', 'binaire', 'sans', null, null, { normal: 'Négatif', aValider: true }],
  ];
  V.RUB = [
    ['RIGG', 'IgG anti-rubéole', 'binaire', 'sans', null, null, { normal: 'Négatif', aValider: true }],
    ['RIGM', 'IgM anti-rubéole', 'binaire', 'sans', null, null, { normal: 'Négatif', aValider: true }],
  ];
  V.CHLAM = [['CHL', 'Chlamydia trachomatis', 'binaire', 'sans', null, null, { normal: 'Négatif', aValider: true }]];

  /* --- Parasitologie ------------------------------------------------------ */
  V.GEDP = [
    ['GE', 'Goutte épaisse', 'liste', 'sans', null, null, {
      valeurs: ['Absence de trophozoïtes',
        'Présence des trophozoïtes de Plasmodium falciparum',
        'Présence des trophozoïtes de Plasmodium malariae',
        'Présence des trophozoïtes de Plasmodium ovale',
        'Présence des trophozoïtes de Plasmodium vivax',
        'Présence de gamétocytes'],
      normal: 'Absence de trophozoïtes',
    }],
    ['DENS', 'Densité parasitaire', 'numerique', 'parasites_ul', null, null, { parent: 'GE', decimales: 0 }],
  ];
  V.AKOP = [
    ['ASP', 'Aspect des selles', 'liste', 'sans', null, null, {
      valeurs: ['Moulées', 'Pâteuses', 'Molles', 'Liquides', 'Glaireuses', 'Sanglantes'],
    }],
    ['COUL', 'Couleur des selles', 'liste', 'sans', null, null, {
      valeurs: ['Brunâtre', 'Grisâtre', 'Jaunâtre', 'Verdâtre', 'Noirâtre'],
    }],
    ['FLORE', 'Flore microbienne', 'liste', 'sans', null, null, {
      valeurs: ['Normale', 'Abondante', 'Pauvre', 'Absente'],
    }],
    ['LEV', 'Levure', 'liste', 'sans', null, null, {
      valeurs: ['Absentes', 'Rares', 'Quelques', 'Nombreuses', 'Très nombreuses'],
    }],
    ['PARA', 'Parasite', 'texte', 'sans', null, null, {}],
  ];
  V.MICRO = [['MF', 'Recherche de microfilaires', 'binaire', 'sans', null, null, { normal: 'Négatif', aValider: true }]];
  V.BILH = [['OB', 'Œufs de bilharzie', 'binaire', 'sans', null, null, { normal: 'Négatif', aValider: true }]];

  /* --- Bactériologie ------------------------------------------------------ */
  V.ECBU = [
    ['ASPU', 'Aspect de l’urine', 'liste', 'sans', null, null, {
      valeurs: ['Urines claires', 'Urines troubles', 'Urines hématiques', 'Urines purulentes'],
      normal: 'Urines claires',
    }],
    ['LEUC', 'Leucocytes', 'liste', 'sans', null, null, {
      valeurs: ['Absents', 'Rares', 'Quelques', 'Nombreux', 'Très nombreux'], normal: 'Absents',
    }],
    ['HEMU', 'Hématies', 'liste', 'sans', null, null, {
      valeurs: ['Absentes', 'Rares', 'Quelques', 'Nombreuses', 'Très nombreuses'], normal: 'Absentes',
    }],
    ['CELL', 'Cellules épithéliales', 'liste', 'sans', null, null, {
      valeurs: ['Absentes', 'Rares', 'Quelques', 'Nombreux', 'Très nombreux'],
    }],
    ['CRIS', 'Cristaux', 'texte', 'sans', null, null, {}],
    ['CYL', 'Cylindres', 'texte', 'sans', null, null, {}],
    ['LEVU', 'Levures', 'liste', 'sans', null, null, {
      valeurs: ['Absentes', 'Rares', 'Quelques', 'Nombreuses', 'Très nombreuses'], normal: 'Absentes',
    }],
    ['GRAM', 'Coloration de Gram', 'texte', 'sans', null, null, {}],
    ['COMM', 'Commentaire', 'commentaire', 'sans', null, null, {}],
  ];
  V.PV = [
    ['ASPV', 'Aspect du prélèvement vaginal', 'liste', 'sans', null, null, {
      valeurs: ['Normal', 'Leucorrhées modérées', 'Leucorrhées abondantes', 'Purulent', 'Hématique'],
      normal: 'Normal',
    }],
    ['ASPV2', 'Autre aspect du prélèvement vaginal', 'texte', 'sans', null, null, { parent: 'ASPV' }],
    ['TRIC', 'Trichomonas vaginalis', 'liste', 'sans', null, null, { valeurs: ['Non', 'Oui'], normal: 'Non' }],
    ['CELV', 'Cellules épithéliales', 'liste', 'sans', null, null, {
      valeurs: ['Absentes', 'Rares', 'Quelques', 'Nombreux', 'Très nombreux'],
    }],
    ['LEUV', 'Leucocytes', 'liste', 'sans', null, null, {
      valeurs: ['Absents', 'Rares', 'Quelques', 'Nombreux', 'Très nombreux'], normal: 'Absents',
    }],
    ['LEVV', 'Levure', 'texte', 'sans', null, null, {}],
    ['HEMV', 'Hématies', 'liste', 'sans', null, null, {
      valeurs: ['Absentes', 'Rares', 'Quelques', 'Nombreuses', 'Très nombreuses'], normal: 'Absentes',
    }],
    ['GRAMV', 'Coloration de Gram', 'texte', 'sans', null, null, {}],
    ['COMMV', 'Commentaire', 'commentaire', 'sans', null, null, {}],
  ];
  ['ECBLCR', 'ECBLP', 'ECBLA', 'ECBPUS', 'PU'].forEach(function (code) {
    V[code] = [
      ['ASPX', 'Aspect', 'texte', 'sans', null, null, { aValider: true }],
      ['LEUX', 'Leucocytes', 'numerique', 'par_champ', null, null, { decimales: 0, aValider: true }],
      ['DIRX', 'Examen direct', 'texte', 'sans', null, null, { aValider: true }],
      ['CULX', 'Culture', 'texte', 'sans', null, null, { aValider: true }],
      ['ATBX', 'Antibiogramme', 'texte', 'sans', null, null, { parent: 'CULX', aValider: true }],
      ['COMX', 'Commentaire', 'commentaire', 'sans', null, null, { aValider: true }],
    ];
  });

  /* --- Biochimie ---------------------------------------------------------- */
  V.GLYAJ = [['GLY', 'Glycémie', 'numerique', 'g_l', 0.70, 1.10, { decimales: 2 }]];
  V.GLYPP = [['GLYP', 'Glycémie', 'numerique', 'g_l', null, 1.6, { decimales: 2 }]];
  V.CREA = [['CREA', 'Créatinine', 'numerique', 'mg_l', 6, 14, { decimales: 1 }]];
  V.AZOT = [['AZO', 'Azotémie', 'numerique', 'g_l', 0.15, 0.45, { decimales: 2 }]];
  V.CA = [['CAL', 'Calcémie', 'numerique', 'mg_l', 84, 104, { decimales: 2 }]];
  V.MG = [['MAG', 'Magnésémie', 'numerique', 'mg_l', 16, 30, { decimales: 2 }]];
  V.IONO = [
    ['NA', 'Natrémie', 'numerique', 'mmol_l', 135, 148, { decimales: 2 }],
    ['K', 'Kaliémie', 'numerique', 'mmol_l', 3.4, 5.4, { decimales: 2 }],
    ['CL', 'Chlorémie', 'numerique', 'mmol_l', 98, 108, { decimales: 2 }],
  ];
  V.TGO = [
    ['TGO', 'TGO (ASAT)', 'numerique', 'ui_l', null, 45, { decimales: 2 }],
    ['TGP', 'TGP (ALAT)', 'numerique', 'ui_l', null, 49, { decimales: 2 }],
  ];
  V.GGT = [['GGTH', 'GGT', 'numerique', 'ui_l', null, 45, { decimales: 2 }]];
  V.CHOLT = [['CT', 'Cholestérol total', 'numerique', 'g_l', null, 2.0, { decimales: 2 }]];
  V.CHOLH = [['CH', 'Cholestérol HDL', 'numerique', 'g_l', 0.35, null, { decimales: 2 }]];
  V.CHOLL = [['CLD', 'Cholestérol LDL', 'numerique', 'g_l', null, 1.6, { decimales: 2, aValider: true }]];
  V.TG = [['TGL', 'Triglycérides', 'numerique', 'g_l', null, 1.5, { decimales: 2 }]];
  V.BILI = [
    ['BT', 'Bilirubine T', 'numerique', 'mg_l', null, 10, { decimales: 1 }],
    ['BC', 'Bilirubine C', 'numerique', 'mg_l', null, 2, { parent: 'BT', decimales: 1 }],
    ['BNC', 'Bilirubine NC', 'numerique', 'mg_l', null, 8, { parent: 'BT', decimales: 1, aValider: true }],
  ];
  V.PROT = [['PRO', 'Protidémie', 'numerique', 'g_l', 60, 80, { decimales: 1 }]];
  V.URIC = [['ACU', 'Acide urique', 'numerique', 'mg_l', 30, 70, { decimales: 2 }]];
  V.PHOS = [['PHO', 'Phosphorémie', 'numerique', 'mg_l', 25, 45, { decimales: 2 }]];
  V.GLUCO = [
    ['GLC', 'Glucorachie', 'numerique', 'g_l', null, null, {
      decimales: 2,
      regle: 'Inférieure à la moitié de la glycémie concomitante (< 1/2 glycémie).',
    }],
  ];
  V.PROTR = [['PRR', 'Protéinorachie', 'numerique', 'g_l', 0.15, 0.45, { decimales: 2, aValider: true }]];
  V.DDIM = [['DD', 'D-dimères', 'numerique', 'mg_l', 0, 0.5, { decimales: 2 }]];
  V.HBA1C = [['A1C', 'Hémoglobine glyquée (HbA1c)', 'numerique', 'pourcent', 4, 6.5, { decimales: 2 }]];
  V.LIPA = [['LIP', 'Lipasémie', 'numerique', 'ui_l', null, 60, { decimales: 1, aValider: true }]];
  V.PAL = [['PALV', 'Phosphatase alcaline', 'numerique', 'ui_l', 40, 130, { decimales: 1, aValider: true }]];
  V.G6PD = [
    ['G6', 'Activité G6PD', 'liste', 'sans', null, null, {
      valeurs: ['Normale', 'Déficit partiel', 'Déficit complet'], normal: 'Normale', aValider: true,
    }],
  ];

  /* --- Hormonologie -------------------------------------------------------- */
  V.PSAT = [['TPSA', 'TPSA', 'numerique', 'ng_ml', 0, 4, { decimales: 2 }]];
  V.PSAL = [
    ['PSAL', 'PSA libre', 'numerique', 'ng_ml', null, null, { decimales: 2 }],
    ['RATIO', 'Rapport PSA libre / PSA total', 'numerique', 'pourcent', 25, null, {
      parent: 'PSAL', decimales: 1, aValider: true,
    }],
  ];
  V.PRL = [['PROL', 'Prolactine', 'numerique', 'ng_ml', 3.34, 26.72, { decimales: 2 }]];
  V.TSH = [['TSHV', 'TSH', 'numerique', 'uui_ml', 0.4, 4.0, { decimales: 2, aValider: true }]];
  V.T3 = [['T3V', 'T3 libre', 'numerique', 'pg_ml', 2.3, 4.2, { decimales: 2, aValider: true }]];
  V.T4 = [['T4V', 'T4 libre', 'numerique', 'pg_ml', 8.9, 17.2, { decimales: 2, aValider: true }]];
  V.BHCG = [['HCG', 'ß-HCG', 'numerique', 'mui_ml', null, 5, { decimales: 2, aValider: true }]];
  V.FSH = [['FSHV', 'FSH', 'numerique', 'mui_ml', null, null, { decimales: 2, aValider: true }]];
  V.LH = [['LHV', 'LH', 'numerique', 'mui_ml', null, null, { decimales: 2, aValider: true }]];
  V.OEST = [['OES', 'Œstradiol', 'numerique', 'pg_ml', null, null, { decimales: 2, aValider: true }]];
  V.PROG = [['PRG', 'Progestérone', 'numerique', 'ng_ml', null, null, { decimales: 2, aValider: true }]];
  V.TESTO = [['TST', 'Testostérone', 'numerique', 'ng_ml', null, null, { decimales: 2, aValider: true }]];
  V.AMH = [['AMHV', 'AMH', 'numerique', 'ng_ml', null, null, { decimales: 2, aValider: true }]];
  V.TBGS = [['TBGV', 'TBG sérique', 'binaire', 'sans', null, null, { normal: 'Négatif', aValider: true }]];

  /* --------------------------------------------------------------------------
   * 7. MOTIFS DE COMMENTAIRE GÉNÉRAL
   * Le commentaire GÉNÉRAL porte sur l'échantillon et le compte rendu ; le
   * commentaire d'EXAMEN porte sur l'interprétation d'un résultat. Les
   * confondre ferait disparaître l'un des deux.
   * ----------------------------------------------------------------------- */
  var MOTIFS_COMMENTAIRE_GENERAL = [
    'Échantillon hémolysé — reprendre le prélèvement.',
    'Échantillon coagulé — reprendre le prélèvement.',
    'Quantité insuffisante pour la totalité des examens demandés.',
    'Échantillon parvenu hors délai de conservation.',
    'Examen non réalisé — réactif indisponible.',
    'Examen à confirmer sur un second prélèvement.',
    'Résultat rendu par téléphone au prescripteur.',
  ];

  /* --------------------------------------------------------------------------
   * 8. CONSTRUCTION DE LA LISTE À PLAT
   * ----------------------------------------------------------------------- */
  var VARIABLES = [];
  EXAMENS.forEach(function (ex) {
    (V[ex.code] || []).forEach(function (v, i) {
      var o = v[6] || {};
      var accompagnement = TYPES_ACCOMPAGNEMENT.indexOf(v[2]) !== -1;
      VARIABLES.push({
        id: 'VAR-' + ex.code + '-' + v[0],
        examen: ex.code, examenLibelle: ex.designation, section: ex.section,
        code: v[0], libelle: v[1], type: v[2], unite: v[3],
        min: v[4], max: v[5],
        parent: o.parent || null,
        valeurs: o.valeurs || null,
        decimales: o.decimales != null ? o.decimales : null,
        normal: o.normal || null,
        regle: o.regle || null,
        ordre: i + 1,
        /* `actif` porte la rétractation demandée : « quand le réactif va
           changer et qu'on n'aura pas besoin de faire ces interprétations et
           ces commentaires, on peut les fermer ». */
        actif: true,
        accompagnement: accompagnement,
        retractable: accompagnement,
        aValider: !!o.aValider,
        source: o.aValider
          ? 'Valeur usuelle — à confirmer par le biologiste médical'
          : 'Fiche de résultats CNT du 21/08/2026',
        statut: 'actif',
      });
    });
  });

  global.SIGH = global.SIGH || {};
  global.SIGH.labo = {
    SECTIONS: SECTIONS,
    SERVICES_DEMANDEURS: SERVICES_DEMANDEURS,
    NIVEAUX_URGENCE: NIVEAUX_URGENCE,
    ORIGINES_PATIENT: ORIGINES_PATIENT,
    UNITES: UNITES,
    TYPES_VARIABLE: TYPES_VARIABLE,
    TYPES_ACCOMPAGNEMENT: TYPES_ACCOMPAGNEMENT,
    EXAMENS: EXAMENS,
    VARIABLES: VARIABLES,
    MOTIFS_COMMENTAIRE_GENERAL: MOTIFS_COMMENTAIRE_GENERAL,
    source: 'Bulletin d’analyses bio-médicales (formulaire papier) et fiche de résultats '
      + 'du dossier 2026080411, éditée le 21/08/2026.',

    /** Le symbole d'une unité. */
    unite: function (id) {
      var u = UNITES.filter(function (x) { return x.id === id; })[0];
      return u ? u.symbole : '—';
    },

    /** Le libellé d'un type de variable. */
    type: function (id) {
      var t = TYPES_VARIABLE.filter(function (x) { return x.id === id; })[0];
      return t ? t.label : id;
    },

    /** Le libellé d'une section. */
    section: function (id) {
      var s = SECTIONS.filter(function (x) { return x.id === id; })[0];
      return s ? s.label : id;
    },

    /**
     * Un résultat s'écarte-t-il de la référence ?
     * Renvoie 'bas', 'haut' ou 'anormal' — ou null si le résultat est normal
     * ou si la variable n'a pas de référence. La fiche de résultats met en
     * GRAS les valeurs hors bornes : c'est ce que cette fonction commande.
     */
    ecart: function (variable, valeur) {
      if (!variable || valeur == null || valeur === '') return null;
      if (TYPES_ACCOMPAGNEMENT.indexOf(variable.type) !== -1) return null;
      if (['binaire', 'ternaire', 'liste', 'titre'].indexOf(variable.type) !== -1) {
        if (!variable.normal) return null;
        return String(valeur) === String(variable.normal) ? null : 'anormal';
      }
      if (variable.type === 'texte') return null;
      var n = Number(valeur);
      if (isNaN(n)) return null;
      if (variable.min != null && n < variable.min) return 'bas';
      if (variable.max != null && n > variable.max) return 'haut';
      return null;
    },

    /**
     * Les références telles qu'elles s'impriment sur la fiche :
     * « 4 - 8 », « < 6 », « > 0.35 » — la notation du document, pas une autre.
     */
    libelleReference: function (variable) {
      if (!variable) return '';
      if (variable.regle) return variable.regle;
      if (TYPES_ACCOMPAGNEMENT.indexOf(variable.type) !== -1) return '';
      if (['binaire', 'ternaire', 'liste', 'titre'].indexOf(variable.type) !== -1) {
        return variable.normal ? 'Attendu : ' + variable.normal : '';
      }
      if (variable.type === 'texte') return '';
      if (variable.min != null && variable.max != null) return variable.min + ' - ' + variable.max;
      if (variable.max != null) return '< ' + variable.max;
      if (variable.min != null) return '> ' + variable.min;
      return '';
    },

    /** Les variables d'un examen, dans leur ordre de rendu. */
    variablesDe: function (codeExamen) {
      return VARIABLES.filter(function (v) { return v.examen === codeExamen; })
        .sort(function (a, b) { return a.ordre - b.ordre; });
    },

    /** Un examen par son code. */
    examen: function (code) {
      return EXAMENS.filter(function (x) { return x.code === code; })[0] || null;
    },
  };
})(window);
