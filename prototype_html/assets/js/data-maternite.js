/* =============================================================================
 * RÉFÉRENTIELS MATERNITÉ — RAPPORT OFFICIEL DU 27/08/2026
 * -----------------------------------------------------------------------------
 * Source unique : « Intégration des Nouvelles Variables Cliniques, Registres
 * Hospitaliers & Édition Automatisée du Dossier Patient » (suite/), formalisé
 * entre l'équipe obstétricale, le laboratoire et les soins curatifs, complété
 * par les formulaires nationaux scannés (dossier obstétrical, grille CPN,
 * partographie, registre des accouchements, fiche de surveillance intégrée).
 *
 * RIEN N'EST INVENTÉ : chaque liste porte sa référence au rapport. Ce qui
 * a dû être supplété (bornes d'affichage, libellés courts) est marqué
 * `aValider` — même discipline que les valeurs de référence du laboratoire.
 * ========================================================================== */
(function (global) {
  'use strict';
  var D = global.SIGH.data;

  /* --------------------------------------------------------------------------
   * LES 10 FONCTIONS SONU — Tableau A du rapport
   * --------------------------------------------------------------------------
   * SONUB = 7 fonctions de base ; SONUC = les 3 complètes en sus. La
   * distinction est STRUCTURELLE : les rapports nationaux classent les
   * structures selon qu'elles posent 7 ou 10 fonctions.
   * ------------------------------------------------------------------------ */
  var SONU = {
    reference: 'Rapport maternité 27/08/2026 — Tableau A (directives OMS / SNIS / SONU)',
    fonctions: [
      [1, 'SONUB', 'Antibiotiques parentéraux', 'Ampicilline, gentamycine, métronidazole — infections maternelles et néonatales'],
      [2, 'SONUB', 'Anticonvulsivants parentéraux', 'Sulfate de magnésium (MgSO4) — éclampsie et pré-éclampsie sévère'],
      [3, 'SONUB', 'Oxytociques parentéraux', 'Ocytocine, GATPA — prévention et traitement de l’hémorragie du post-partum'],
      [4, 'SONUB', 'Délivrance artificielle et révision utérine', 'Extraction manuelle du placenta, vérification de la cavité utérine'],
      [5, 'SONUB', 'AMIU / curetage / curage', 'Aspiration Manuelle Intra-Utérine — avortement incomplet, rétention trophoblastique'],
      [6, 'SONUB', 'Ventouse obstétricale', 'Accouchement instrumental — assistance mécanique à l’expulsion fœtale'],
      [7, 'SONUB', 'Réanimation du nouveau-né', 'Désobstruction, ventilation au ballon et masque, réanimation cardio-pulmonaire néonatale'],
      [8, 'SONUC', 'Transfusion sanguine d’urgence', 'Choc hémorragique sévère obstétrical — fonction SONUC'],
      [9, 'SONUC', 'PEC éclampsie compliquée / chirurgie obstétricale', 'Soins intensifs, laparotomie d’urgence — rupture utérine, hémorragie réfractaire'],
      [10, 'SONUC', 'Césarienne d’urgence', 'Extraction fœtale d’urgence par voie haute au bloc — fonction SONUC'],
    ].map(function (f) {
      return { num: f[0], type: f[1], label: f[2], description: f[3], code: 'SONU' + f[0] };
    }),
  };
  function fonctionSONU(num) {
    return SONU.fonctions.filter(function (f) { return f.num === Number(num); })[0] || null;
  }

  /* --------------------------------------------------------------------------
   * LES 15 MÉTHODES CONTRACEPTIVES — Tableau B du rapport (registre PF)
   * --------------------------------------------------------------------------
   * Liste EXCLUSIVE (choix unique) et codification A/N : « A » = Nouvelle
   * Acceptante, « N » = Ancienne Acceptante (renouvellement ou changement).
   * La codification du rapport surprend (A pour nouvelle) : elle est reprise
   * TELLE QUELLE — c'est celle des registres papier nationaux.
   * ------------------------------------------------------------------------ */
  var METHODES_PF = [
    ['diu', 'DIU (cuivre / hormonal)', 'Longue durée', 'Stérilet de longue durée (5 à 10 ans)'],
    ['diu_pp', 'DIU PP Immédiat', 'Longue durée', 'Insertion dans les 10 min à 48 h après l’accouchement'],
    ['noristerat', 'Noristérat', 'Courte durée', 'Injection hormonale tous les 2 mois'],
    ['depo_im', 'Depo IM (Dépo-Provera)', 'Courte durée', 'Injectable intramusculaire tous les 3 mois'],
    ['dmpa_sc', 'DMPA-SC Sayana Press', 'Courte durée', 'Auto-injection ou injection CS sous-cutanée de 3 mois'],
    ['co', 'CO (Contraceptifs Oraux)', 'Courte durée', 'Pilule œstro-progestative quotidienne'],
    ['jadelle', 'Jadelle (2 bâtonnets)', 'Longue durée', 'Implant efficace 5 ans'],
    ['implanon', 'Implanon / Nexplanon (1 bâtonnet)', 'Longue durée', 'Implant efficace 3 ans'],
    ['jadelle_pp', 'Jadelle PP Immédiat', 'Longue durée', 'Pose en post-partum immédiat, en salle de maternité'],
    ['implanon_pp', 'Implanon PP Immédiat', 'Longue durée', 'Pose en post-partum immédiat'],
    ['pilule', 'Pilule microprogestative', 'Courte durée', 'Compatible avec l’allaitement maternel'],
    ['ligature', 'Ligature des trompes', 'Définitive', 'Contraception chirurgicale volontaire féminine'],
    ['vasectomie', 'Vasectomie', 'Définitive', 'Stérilisation masculine volontaire ambulatoire'],
    ['collier', 'Collier du cycle / MAMA', 'Naturelle / barrière', 'Méthodes naturelles, allaitement maternel et aménorrhée'],
    ['preservatif', 'Préservatifs masculins / féminins', 'Naturelle / barrière', 'Méthode barrière et double protection VIH/IST'],
  ].map(function (m) {
    return { code: m[0], label: m[1], categorie: m[2], specification: m[3] };
  });
  function methodePF(code) {
    return METHODES_PF.filter(function (m) { return m.code === code; })[0] || null;
  }
  var STATUTS_ACCEPTANTE = [
    { code: 'A', label: 'A — Nouvelle acceptante' },
    { code: 'N', label: 'N — Ancienne acceptante (renouvellement / changement)' },
  ];

  /* --------------------------------------------------------------------------
   * CPN — suivi de grossesse (Module B + tableau 8 du rapport)
   * ------------------------------------------------------------------------ */
  var DOSES_SP = ['SP1', 'SP2', 'SP3', 'SP4', 'SP5'];
  var TYPES_CPON = [
    { code: 'cpon1', label: 'CPoN 1', fenetre: '6 h – 24 h (J0-J1)' },
    { code: 'cpon2', label: 'CPoN 2', fenetre: 'J6 – J14' },
    { code: 'cpon3', label: 'CPoN 3', fenetre: '6ᵉ semaine' },
  ];

  /* --------------------------------------------------------------------------
   * NOUVEAU-NÉ — bornes du Module C
   * --------------------------------------------------------------------------
   * PC 32,0–38,0 cm ; PT 30,0–36,0 cm ; alerte si Apgar à 5 min < 7/10.
   * Ce sont les bornes ÉCRITES du rapport, pas des valeurs de manuel.
   * ------------------------------------------------------------------------ */
  var BORNES_NOUVEAU_NE = {
    pc: { min: 32, max: 38, unite: 'cm', libelle: 'Périmètre crânien' },
    pt: { min: 30, max: 36, unite: 'cm', libelle: 'Périmètre thoracique' },
    apgarSeuil5min: 7,
    source: 'Rapport maternité 27/08/2026 — Module C et §5.4 (alertes de sécurité clinique)',
  };
  /* Facteur de risque CPN : âge < 18 ans ou > 35 ans (§5.4 du rapport). */
  var AGES_RISQUE_CPN = { min: 18, max: 35 };

  var SOINS_ESSENTIELS_NN = ['Vitamine K1', 'Collyre tétracycline', 'Chlorhexidine 7,1 % (cordon)'];

  /* --------------------------------------------------------------------------
   * SOINS CURATIFS & URGENCES MATERNITÉ — Module E (Case 27 restructurée)
   * ------------------------------------------------------------------------ */
  var URGENCES_MATERNITE = [
    { code: 'referee', label: 'Femme en travail référée d’urgence' },
    { code: 'referee_admise', label: 'Référée d’urgence ET admise à l’hôpital de référence' },
    { code: 'referee_pec', label: 'Référée d’urgence ET prise en charge par l’hôpital de référence' },
  ];
  var TRANCHES_AGE_CURATIF = ['< 1 mois', '1–11 mois', '1–4 ans', '5–9 ans', '10–14 ans',
    '15–19 ans', '20–24 ans', '25 ans et +'];

  /* --------------------------------------------------------------------------
   * RÉFÉRENCE / CONTRE-RÉFÉRENCE — Module G (compléments)
   * ------------------------------------------------------------------------ */
  var TRANSPORTS_REFERENCE = ['Ambulance', 'Taxi', 'Moto', 'Barque', 'À pied', 'Autre'];
  var EVOLUTIONS_MALADIE = ['Guéri', 'Évadé', 'Décédé', 'Sortie contre avis médical', 'Référé'];

  /* --------------------------------------------------------------------------
   * PTME — registre quadripartite (Module I)
   * ------------------------------------------------------------------------ */
  var PTME = {
    reference: 'Rapport maternité 27/08/2026 — Module I et tableau 6 (protocoles PTME)',
    prophylaxiesNN: [
      { code: 1, label: 'NVP' }, { code: 2, label: 'AZT' },
      { code: 3, label: 'AZT + NVP' }, { code: 4, label: 'Aucune' },
    ],
    allaitements: ['Exclusif', 'Artificiel', 'Mixte'],
    dureesARV: ['< 8 semaines', '≥ 8 semaines'],
    suivisEnfant: ['PCR naissance', 'PCR-1 (6 semaines)', 'PCR-2 (9 mois)', 'Sérologie VIH (18 mois)'],
  };

  /* --------------------------------------------------------------------------
   * ACCOUCHEMENT — types et actes associés (cible Instructions + registre)
   * ------------------------------------------------------------------------ */
  var TYPES_ACCOUCHEMENT = ['Eutocique', 'Dystocique', 'Dirigé', 'Gemellaire', 'Trimellaire', 'Césarienne'];
  var ACTES_ACCOUCHEMENT = ['Épisiotomie', 'Délivrance artificielle', 'Révision utérine',
    'AMIU', 'Ventouse obstétricale', 'GATPA'];

  /* --------------------------------------------------------------------------
   * PARTOGRAMME — le modèle de la PARTOGRAPHIE nationale scannée
   * --------------------------------------------------------------------------
   * La ligne d'ALERTE part de 4 cm et progresse de 1 cm/h ; la ligne d'ACTION
   * lui est parallèle, décalée de 4 heures. Codes actions 1-7 du formulaire.
   * ------------------------------------------------------------------------ */
  var PARTOGRAMME = {
    alerteDepart: 4, alerteParHeure: 1, actionDecalageHeures: 4,
    liquides: [
      { code: 'I', label: 'I — Poche des eaux intacte' },
      { code: 'C', label: 'C — Liquide clair' },
      { code: 'M', label: 'M — Méconial (purée de pois)' },
      { code: 'S', label: 'S — Sanglant / hématique' },
      { code: 'V', label: 'V — « Jus de viande »' },
      { code: 'J', label: 'J — Jaunâtre' },
    ],
    actions: ['Rupture artificielle de la PDE', 'Antispasmodique', 'Ocytocine', 'Épisiotomie',
      'Ventouse / Forceps', 'Référence', 'Césarienne / Laparotomie'],
    /* LE CHEVAUCHEMENT DES OS DU CRÂNE, coté 0 à 3 : c'est lui qui distingue
       une descente qui progresse d'une disproportion. La légende du
       formulaire le porte, le prototype l'ignorait. */
    chevauchement: [
      { code: 0, label: '0 — Pas de chevauchement, sutures palpables' },
      { code: 1, label: '1 — Apposition des os du crâne' },
      { code: 2, label: '2 — Chevauchement réductible' },
      { code: 3, label: '3 — Chevauchement irréductible' },
    ],
    /* La descente de la tête se COTE EN TRAVERS DE DOIGTS, jamais en
       centimètres : c'est la mesure que la main donne. */
    descente: [
      { code: '5/5', label: '5 travers de doigts (5/5)' },
      { code: '4/5', label: '4 travers de doigts (4/5)' },
      { code: '3/5', label: '3 travers de doigts (3/5)' },
      { code: '2/5', label: '2 travers de doigts (2/5)' },
      { code: '1/5', label: '1 travers de doigt (1/5)' },
    ],
    contractions: [
      { code: 'courte', label: '< 20 secondes' },
      { code: 'moyenne', label: '20 à 40 secondes' },
      { code: 'longue', label: '> 40 secondes' },
    ],
    /* Les renseignements généraux de l'en-tête, tels que le formulaire les
       demande — ce sont eux qu'on relit quand une suite de couches est
       contestée. */
    renseignements: ['Nom & prénoms', 'Âge', 'Âge gestationnel', 'Gestité', 'Parité', 'Poids',
      'Date / heure de l’admission', 'Date / heure de la rupture des membranes',
      'Date / heure de l’accouchement', 'Numéro du dossier', 'Nom de l’accoucheur', 'Qualification'],
    source: 'PARTOGRAPHIE — formulaire national ; légende et codes relevés sur un dossier '
      + 'RÉELLEMENT REMPLI (exemplaire de recette du 06/09/2026).',
  };

  /* ==========================================================================
   * LE DOSSIER OBSTÉTRICAL — ce que le formulaire national porte réellement
   * --------------------------------------------------------------------------
   * Transcrit d'un dossier RÉELLEMENT REMPLI, suivi de la première CPN jusqu'à
   * l'accouchement et à la surveillance des deux premiers jours (exemplaire de
   * recette remis le 06/09/2026). Les scans de `suite/` donnaient les
   * formulaires VIERGES : on savait quelles cases existent, pas comment elles
   * se remplissent ni lesquelles se remplissent ensemble.
   *
   * AUCUNE IDENTITÉ N'EN EST REPRISE. Le document porte les données de santé
   * d'une personne réelle : c'est sa STRUCTURE qui est exploitée, jamais son
   * contenu — le jeu de démonstration invente ses propres patientes.
   *
   * Cinq feuillets, et le dossier les tient ensemble :
   *   1. dossier obstétrical (identité, procréateur, antécédents, facteurs de
   *      surveillance, examens complémentaires, HIV/syphilis) ;
   *   2. soins préventifs et promotionnels + consultation prénatale ;
   *   3. état et soins du nouveau-né, délivrance, placenta, issue ;
   *   4. fiche de surveillance intégrée de l'accouchée et du nouveau-né ;
   *   5. partographie.
   * ======================================================================== */

  /** Les dix droits fondamentaux, vulgarisés à chaque CPN. */
  var DROITS_FONDAMENTAUX = [
    'Droit à l’information', 'Droit d’accès', 'Droit au choix', 'Droit à la sécurité',
    'Droit à la confidentialité et au secret professionnel', 'Droit au confort',
    'Droit à la dignité', 'Droit à l’assurance et aux avantages sociaux',
    'Droit à la continuité des soins', 'Droit d’exprimer son opinion',
  ];

  /* LE PLAN POUR L'ACCOUCHEMENT. Ce n'est pas une formalité : chacune de ces
     neuf lignes est une cause connue de retard le jour de l'accouchement —
     savoir QUI décide en l'absence du mari, ou QUI garde les enfants, évite
     l'heure perdue à la chercher. */
  var PLAN_ACCOUCHEMENT = [
    'Lieu de l’accouchement', 'Accoucheur qualifié identifié', 'Contact de l’accoucheur',
    'Mode de transport', 'Accompagnant identifié', 'Garde des enfants à la maison identifiée',
    'Décideur en l’absence du mari', 'Épargne pour l’accouchement', 'Donneur de sang prévu',
  ];

  var CLASSES_MERES = ['1er trimestre', '2ème trimestre', '3ème trimestre',
    'Accouchée récente', 'Accouchée tardive'];

  /* LES DOUZE FACTEURS DE SURVEILLANCE, tels que le formulaire les coche.
     Ils ne sont pas décoratifs : c'est leur cumul qui classe la grossesse à
     risque, et c'est la question que la sage-femme pose en premier. */
  var FACTEURS_SURVEILLANCE = [
    { code: 'age_min', libelle: 'Âge < 16 ans' },
    { code: 'age_max', libelle: 'Âge > 35 ans' },
    { code: 'taille', libelle: 'Taille < 1,50 m' },
    { code: 'boiterie', libelle: 'Boiterie' },
    { code: 'parite', libelle: 'Parité > 6' },
    { code: 'cesarienne', libelle: 'Césarienne au dernier accouchement' },
    { code: 'mortne', libelle: 'Mort-né au dernier accouchement' },
    { code: 'drepano', libelle: 'Drépanocytose SS ou SC' },
    { code: 'hta', libelle: 'HTA connue' },
    { code: 'fausses_couches', libelle: 'Fausses couches répétées' },
    { code: 'diabete', libelle: 'Diabète' },
    { code: 'autres', libelle: 'Autres facteurs' },
  ];

  /** Les examens complémentaires du dossier — groupés comme le formulaire. */
  var EXAMENS_DOSSIER = [
    { code: 'gs', libelle: 'Groupe sanguin', groupe: 'Immuno-hématologie' },
    { code: 'rh', libelle: 'Rhésus', groupe: 'Immuno-hématologie' },
    { code: 'coombs', libelle: 'Test de Coombs indirect', groupe: 'Immuno-hématologie' },
    { code: 'electrophorese', libelle: 'Électrophorèse de l’hémoglobine', groupe: 'Immuno-hématologie' },
    { code: 'hb', libelle: 'Taux d’hémoglobine', groupe: 'Hématologie' },
    { code: 'hematocrite', libelle: 'Hématocrite', groupe: 'Hématologie' },
    { code: 'plaquettes', libelle: 'Plaquettes', groupe: 'Hématologie' },
    { code: 'tpha', libelle: 'TPHA', groupe: 'Sérologie' },
    { code: 'vdrl', libelle: 'VDRL', groupe: 'Sérologie' },
    { code: 'hiv1', libelle: 'HIV 1', groupe: 'Sérologie' },
    { code: 'hiv2', libelle: 'HIV 2', groupe: 'Sérologie' },
    { code: 'toxo_igg', libelle: 'Toxoplasmose IgG', groupe: 'Sérologie' },
    { code: 'toxo_igm', libelle: 'Toxoplasmose IgM', groupe: 'Sérologie' },
    { code: 'rubeole_igg', libelle: 'Rubéole IgG', groupe: 'Sérologie' },
    { code: 'rubeole_igm', libelle: 'Rubéole IgM', groupe: 'Sérologie' },
    { code: 'hepatiteB', libelle: 'Hépatite B (à partir de 6 mois)', groupe: 'Sérologie' },
    { code: 'ecbu', libelle: 'ECBU', groupe: 'Bactériologie' },
    { code: 'glycemie', libelle: 'Glycémie à jeun', groupe: 'Biochimie' },
    { code: 'gp75', libelle: 'GP 75', groupe: 'Biochimie' },
  ];

  /* ------------------------------------------------------------------------
   * LA GRILLE DE CONSULTATION PRÉNATALE, ligne par ligne
   * ------------------------------------------------------------------------
   * Le formulaire porte une COLONNE PAR VISITE — 1er trimestre, 2ème, puis
   * quatre colonnes de 3ème trimestre, toutes obligatoires. Ce sont donc les
   * mêmes lignes qu'on remplit à chaque venue : c'est ce qui permet de LIRE
   * une évolution (le poids, la hauteur utérine, la TA) plutôt qu'un état.
   * Un écran qui ne porterait qu'une visite à la fois perdrait exactement
   * l'information que la grille existe pour donner.
   * ---------------------------------------------------------------------- */
  var GRILLE_CPN = [
    { code: 'arrivee', libelle: 'Date et heure d’arrivée', type: 'texte', groupe: 'Venue' },
    { code: 'heureCpnr', libelle: 'Heure de la CPNR', type: 'texte', groupe: 'Venue' },
    { code: 'prestataire', libelle: 'Identité et qualification du prestataire', type: 'texte', groupe: 'Venue' },
    { code: 'terme', libelle: 'Terme de la grossesse', type: 'texte', groupe: 'Venue' },
    { code: 'echographie', libelle: 'Résultat de l’échographie', type: 'texte', groupe: 'Venue' },
    { code: 'plaintes', libelle: 'Plaintes', type: 'texte', groupe: 'Venue' },
    { code: 'ta', libelle: 'TA', type: 'texte', groupe: 'État général' },
    { code: 'pouls', libelle: 'Pouls', type: 'nombre', groupe: 'État général' },
    { code: 'temperature', libelle: 'Température', type: 'nombre', groupe: 'État général' },
    { code: 'muqueuses', libelle: 'Muqueuses', type: 'texte', groupe: 'État général' },
    { code: 'omi', libelle: 'OMI', type: 'texte', groupe: 'État général' },
    { code: 'pb', libelle: 'PB', type: 'texte', groupe: 'État général' },
    { code: 'conscience', libelle: 'Conscience', type: 'texte', groupe: 'État général' },
    { code: 'poids', libelle: 'Poids', type: 'nombre', groupe: 'État général' },
    { code: 'imc', libelle: 'IMC', type: 'nombre', groupe: 'État général', calcule: true },
    { code: 'urines', libelle: 'Test d’urines (A/N/S/L)', type: 'texte', groupe: 'Examens',
      aide: 'A : Albumine · N : Nitrite · S : Sucre · L : Leucocyte' },
    { code: 'seins', libelle: 'Examen des seins', type: 'texte', groupe: 'Examens' },
    { code: 'inspection', libelle: 'Inspection', type: 'texte', groupe: 'Examens' },
    { code: 'hu', libelle: 'Mensuration : HU', type: 'nombre', groupe: 'Examens' },
    { code: 'presentation', libelle: 'Palpation : présentation', type: 'texte', groupe: 'Examens' },
    { code: 'pointsUreteraux', libelle: 'Points urétéraux moyens', type: 'texte', groupe: 'Examens' },
    { code: 'bdcf', libelle: 'Auscultation : BDCF', type: 'nombre', groupe: 'Examens' },
    { code: 'vulve', libelle: 'État de la vulve', type: 'texte', groupe: 'Examens' },
    { code: 'speculum', libelle: 'Pose du spéculum', type: 'texte', groupe: 'Examens' },
    { code: 'toucherVaginal', libelle: 'Toucher vaginal', type: 'texte', groupe: 'Examens' },
    { code: 'bassin', libelle: 'Examen du bassin', type: 'texte', groupe: 'Examens' },
    { code: 'diagnostic', libelle: 'Diagnostic', type: 'texte', groupe: 'Conclusion' },
    { code: 'sp', libelle: 'TPI / SP — dose administrée', type: 'texte', groupe: 'Prévention' },
    { code: 'deparasitage', libelle: 'Déparasitage', type: 'ouiNon', groupe: 'Prévention' },
    { code: 'fer', libelle: 'Fer 200 mg/jour', type: 'ouiNon', groupe: 'Prévention' },
    { code: 'foldine', libelle: 'Foldine 5 mg/jour', type: 'ouiNon', groupe: 'Prévention' },
    { code: 'milda', libelle: 'A dormi sous MILDA la nuit dernière ?', type: 'ouiNon', groupe: 'Prévention' },
    { code: 'conseilsNutrition', libelle: 'Conseils nutritionnels', type: 'ouiNon', groupe: 'Conseils' },
    { code: 'signesDanger', libelle: 'Informations sur les signes de danger', type: 'ouiNon', groupe: 'Conseils' },
    { code: 'counselingPF', libelle: 'Counseling sur la PF', type: 'ouiNon', groupe: 'Conseils' },
    { code: 'methodePF', libelle: 'Méthode choisie', type: 'texte', groupe: 'Conseils' },
    { code: 'conduite', libelle: 'Conduite à tenir', type: 'texte', groupe: 'Conclusion' },
    { code: 'rdvCpn', libelle: 'RDV — CPN', type: 'date', groupe: 'Suite' },
    { code: 'rdvClasse', libelle: 'RDV — Classe des mères', type: 'texte', groupe: 'Suite' },
    { code: 'rechercheActive', libelle: 'Recherche active', type: 'texte', groupe: 'Suite' },
  ];

  /* ------------------------------------------------------------------------
   * LA FICHE DE SURVEILLANCE INTÉGRÉE — mère ET nouveau-né sur la MÊME feuille
   * ------------------------------------------------------------------------
   * Deux séries de relevés sur une seule grille de temps : les six premières
   * heures au quart d'heure puis à l'heure, ensuite J1 et J2 matin et soir.
   * Les séparer en deux fiches ferait perdre ce que la feuille unique donne —
   * la coïncidence, à la même minute, d'une hémorragie chez la mère et d'une
   * détresse chez l'enfant.
   * ---------------------------------------------------------------------- */
  var TEMPS_SURVEILLANCE = ['15 mn', '30 mn', '45 mn', '60 mn', '1H15', '1H30', '1H45',
    '2H00', '2H15', '2H30', '2H45', '3H00', '4H00', '5H00', '6H00'];
  var TEMPS_JOURS = ['J1 matin', 'J1 soir', 'J2 matin', 'J2 soir'];

  var SURVEILLANCE_MERE = [
    { code: 'pouls', libelle: 'Pouls' }, { code: 'ta', libelle: 'TA' },
    { code: 'temperature', libelle: 'Température' }, { code: 'respiration', libelle: 'Respiration' },
    { code: 'ecoulement', libelle: 'Écoulement vulvaire' },
    { code: 'globe', libelle: 'Globe de sécurité' },
    { code: 'psy', libelle: 'Réactions psychologiques' },
  ];
  var SURVEILLANCE_BEBE = [
    { code: 'temperature', libelle: 'Température (chiffre ; normal, chaud, froid)' },
    { code: 'coloration', libelle: 'Coloration (rose, anormale)' },
    { code: 'respiration', libelle: 'Fréquence respiratoire (normale, difficile)' },
    { code: 'cordon', libelle: 'Saignement du cordon ombilical' },
    { code: 'allaitement', libelle: 'Allaitement régulier' },
  ];
  var ACTIONS_SURVEILLANCE = ['Vitamine K1 au bébé', 'Collyre dans les yeux du bébé',
    'Pansement ombilical', 'Autres soins'];
  var HEURES_NOUVEAU_NE = ['H4', 'H8', 'H12', 'H16', 'H20', 'H24'];
  var ELEMENTS_NOUVEAU_NE = [
    { code: 'temperature', libelle: 'Température' },
    { code: 'respiration', libelle: 'Fréquence respiratoire' },
    { code: 'coloration', libelle: 'Coloration (rose, pâle, cyanose)' },
    { code: 'ictere', libelle: 'Ictère' },
    { code: 'neuro', libelle: 'État neurologique (éveil, tonus, réflexes archaïques)' },
    { code: 'meconium', libelle: 'Émission de méconium' },
    { code: 'urines', libelle: 'Émission d’urines' },
    { code: 'cordon', libelle: 'Saignement du cordon ombilical' },
    { code: 'sein', libelle: 'Comportement au sein' },
  ];

  /* ------------------------------------------------------------------------
   * DÉLIVRANCE, PLACENTA ET ISSUE — le troisième feuillet
   * ---------------------------------------------------------------------- */
  var MODES_DELIVRANCE = ['Naturelle', 'Artificielle', 'Assistée (GATPA)'];
  var GESTES_DELIVRANCE = ['Ocytocine 10 UI à la 1ʳᵉ minute', 'Traction contrôlée du cordon',
    'Massage utérin'];
  var EXAMEN_PLACENTA = [
    { code: 'cotyledons', libelle: 'Cotylédons intègres', type: 'ouiNon' },
    { code: 'cupule', libelle: 'Présence de cupule', type: 'ouiNon' },
    { code: 'insertionCordon', libelle: 'Insertion du cordon', type: 'texte' },
    { code: 'grandCote', libelle: 'Grand côté (cm)', type: 'nombre' },
    { code: 'petitCote', libelle: 'Petit côté (cm)', type: 'nombre' },
    { code: 'longueurCordon', libelle: 'Longueur du cordon (cm)', type: 'nombre' },
    { code: 'poidsPlacenta', libelle: 'Poids du placenta (g)', type: 'nombre' },
    { code: 'faceMaternelle', libelle: 'Examen de la face maternelle', type: 'texte' },
    { code: 'faceFoetale', libelle: 'Examen de la face fœtale', type: 'texte' },
  ];
  /* L'ISSUE se lit en quatre questions, et ce sont EXACTEMENT les quatre que
     les indicateurs nationaux comptent. */
  var ISSUES_ACCOUCHEMENT = [
    { code: 'femmeReferee', libelle: 'Femme référée' },
    { code: 'femmeDecedee', libelle: 'Femme décédée' },
    { code: 'nnReference', libelle: 'Nouveau-né référé' },
    { code: 'nnDecede', libelle: 'Nouveau-né décédé' },
  ];
  var SOINS_NOUVEAU_NE_FICHE = [
    { code: 'seinPrecoce', libelle: 'Mise au sein précoce' },
    { code: 'collyre', libelle: 'Collyre (une seule fois)' },
    { code: 'vitK1', libelle: 'Vitamine K1 — 1 mg IM ou 2 mg orale' },
    { code: 'examenSystematique', libelle: 'Examen systématique du nouveau-né' },
    { code: 'arv', libelle: 'ARV si mère séropositive' },
    { code: 'carteInfantile', libelle: 'Carte infantile remplie' },
  ];
  /* Le score d'APGAR, coté à 1, 5 et 10 minutes — cinq éléments sur trois
     cotations, comme la grille du formulaire. */
  var APGAR = {
    temps: ['1ʳᵉ minute', '5ᵉ minute', '10ᵉ minute'],
    elements: [
      { code: 'coeur', libelle: 'Cœur', cotations: ['Absent', '< 100', '> 100'] },
      { code: 'respiration', libelle: 'Respiration', cotations: ['Absent', 'Faible', 'Normal'] },
      { code: 'tonus', libelle: 'Tonus', cotations: ['Absent', 'Mouvements', 'Normal'] },
      { code: 'couleur', libelle: 'Couleur', cotations: ['Pâle', 'Cyanosé', 'Rosé'] },
      { code: 'reflexe', libelle: 'Réflexe', cotations: ['Absent', 'Faible', 'Normal'] },
    ],
  };
  var DEGRES_MORT_NE = ['1er degré', '2ème degré', '3ème degré'];


  /* --------------------------------------------------------------------------
   * ÉDITION AUTOMATISÉE & INDICATEURS (Modules J et §5.3)
   * ------------------------------------------------------------------------ */
  var INDICATEURS_DHIS2 = [
    { code: 'pf_acceptation', label: 'Taux d’acceptation PF (nouvelles acceptantes)' },
    { code: 'gar', label: 'Proportion de grossesses à risque (GAR)' },
    { code: 'sp3', label: 'Couverture SP3' },
    { code: 'sp5', label: 'Couverture SP5' },
    { code: 'milda', label: 'Couverture MILDA' },
    { code: 'transferts', label: 'Parturientes transférées admises et prises en charge' },
  ];

  /* --- Exposition ---------------------------------------------------------- */
  D.SONU = SONU;
  D.fonctionSONU = fonctionSONU;
  D.METHODES_PF = METHODES_PF;
  D.methodePF = methodePF;
  D.STATUTS_ACCEPTANTE = STATUTS_ACCEPTANTE;
  D.DOSES_SP = DOSES_SP;
  D.TYPES_CPON = TYPES_CPON;
  D.BORNES_NOUVEAU_NE = BORNES_NOUVEAU_NE;
  D.AGES_RISQUE_CPN = AGES_RISQUE_CPN;
  D.SOINS_ESSENTIELS_NN = SOINS_ESSENTIELS_NN;
  D.URGENCES_MATERNITE = URGENCES_MATERNITE;
  D.TRANCHES_AGE_CURATIF = TRANCHES_AGE_CURATIF;
  D.TRANSPORTS_REFERENCE = TRANSPORTS_REFERENCE;
  D.EVOLUTIONS_MALADIE = EVOLUTIONS_MALADIE;
  D.PTME = PTME;
  D.TYPES_ACCOUCHEMENT = TYPES_ACCOUCHEMENT;
  D.ACTES_ACCOUCHEMENT = ACTES_ACCOUCHEMENT;
  D.PARTOGRAMME = PARTOGRAMME;
  D.INDICATEURS_DHIS2 = INDICATEURS_DHIS2;
  /* Le dossier obstétrical et ses quatre feuillets. */
  D.DROITS_FONDAMENTAUX = DROITS_FONDAMENTAUX;
  D.PLAN_ACCOUCHEMENT = PLAN_ACCOUCHEMENT;
  D.CLASSES_MERES = CLASSES_MERES;
  D.FACTEURS_SURVEILLANCE = FACTEURS_SURVEILLANCE;
  D.EXAMENS_DOSSIER = EXAMENS_DOSSIER;
  D.GRILLE_CPN = GRILLE_CPN;
  D.TEMPS_SURVEILLANCE = TEMPS_SURVEILLANCE;
  D.TEMPS_JOURS = TEMPS_JOURS;
  D.SURVEILLANCE_MERE = SURVEILLANCE_MERE;
  D.SURVEILLANCE_BEBE = SURVEILLANCE_BEBE;
  D.ACTIONS_SURVEILLANCE = ACTIONS_SURVEILLANCE;
  D.HEURES_NOUVEAU_NE = HEURES_NOUVEAU_NE;
  D.ELEMENTS_NOUVEAU_NE = ELEMENTS_NOUVEAU_NE;
  D.MODES_DELIVRANCE = MODES_DELIVRANCE;
  D.GESTES_DELIVRANCE = GESTES_DELIVRANCE;
  D.EXAMEN_PLACENTA = EXAMEN_PLACENTA;
  D.ISSUES_ACCOUCHEMENT = ISSUES_ACCOUCHEMENT;
  D.SOINS_NOUVEAU_NE_FICHE = SOINS_NOUVEAU_NE_FICHE;
  D.APGAR = APGAR;
  D.DEGRES_MORT_NE = DEGRES_MORT_NE;
})(window);
