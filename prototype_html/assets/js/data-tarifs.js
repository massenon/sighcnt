/* ==========================================================================
 * CATALOGUE TARIFAIRE — LES SIX GRILLES OFFICIELLES DE LA CLINIQUE
 * --------------------------------------------------------------------------
 * Source : les six documents de tarifs de newinfos/, lus le 24/08/2026 —
 * consultations, imageries médicales, analyses de laboratoire, actes
 * médico-infirmiers (AMI), actes gynéco-obstétricaux et kits, certificats.
 *
 * LE FAIT STRUCTURANT : chaque grille porte DEUX colonnes de prix,
 * « PRIX NON ASSURE » et « PRIX ASSURE », et le prix assuré est presque
 * toujours le plus élevé. Ce n'est pas une anomalie de saisie : le tarif
 * conventionné opposable à une compagnie n'est pas le tarif de guichet.
 * Un modèle à prix unique fausserait simultanément la facture du patient,
 * la créance de l'assureur et la recette comptable.
 *
 * TROIS ÉTATS, PAS DEUX, dans la colonne « assuré » :
 *   - un montant          → tarif conventionné ;
 *   - NON COUVERT         → l'acte existe et il est tarifé, mais aucune
 *                           compagnie ne le prend en charge : l'assuré paie
 *                           le prix non assuré. C'est le cas de toute la
 *                           planification familiale et de l'hydrotubation ;
 *   - un tiret « – »      → prix NON RENSEIGNÉ. Ni zéro, ni exclusion.
 *                           Trois occurrences : HIV, SPERMOGRAMME (assuré),
 *                           PSE. Elles restent nulles et l'écran le dit.
 *
 * LES CERTIFICATS portent une mention manuscrite sans équivoque :
 * « L'ASSURANCE NE COUVRE PAS À L'EXCEPTION DE SOS ». D'où la troisième
 * valeur de `assurable` : la chaîne 'sos'. Un booléen aurait obligé à
 * choisir entre exclure SOS à tort et ouvrir la couverture aux treize
 * compagnies à tort.
 *
 * LES MÉDICAMENTS n'ont pas de grille : le document qui s'en réclame ne
 * porte que 144 désignations, sans colonne de prix. C'est cohérent avec
 * RG-02 — le médicament se facture au prix d'achat, sans marge : son prix
 * est calculé, pas saisi.
 * ======================================================================== */
(function (global) {
  'use strict';

  var D = global.SIGH.data;

  /* Sentinelle de lisibilité : distingue « exclu de la couverture » d'un
     prix simplement absent. Les deux se lisent « – » sur le papier. */
  var NC = 'NON_COUVERT';

  var SRC = {
    cons: 'Tarifs des consultations NASSIERA TOO',
    img: 'Tarifs des imageries médicales de NASSIERA TOO',
    labo: 'Tarifs des analyses de laboratoire NASSIERA TOO',
    ami: 'Tarifs des actes médico-infirmiers (AMI) NASSIERA TOO',
    gyn: 'Tarifs des actes gynéco-obstétricaux et kits NASSIERA TOO',
    cert: 'Tarifs des certificats NASSIERA TOO',
  };

  /* ==========================================================================
   * FAMILLES — celles que les documents nomment eux-mêmes
   * ======================================================================== */
  var FAMILLES = [
    { code: 'CONSULTATION', label: 'Consultations', icone: 'stethoscope' },
    { code: 'IMAGERIE', label: 'Imagerie médicale', icone: 'scan-line' },
    { code: 'LABO', label: 'Analyses de laboratoire', icone: 'flask-conical' },
    { code: 'AMI', label: 'Actes médico-infirmiers', icone: 'syringe' },
    { code: 'GYNECO', label: 'Actes gynéco-obstétricaux et kits', icone: 'baby' },
    { code: 'CERTIFICAT', label: 'Certificats et attestations', icone: 'file-badge' },
  ];

  /* --------------------------------------------------------------------------
   * CONSULTATIONS
   * ------------------------------------------------------------------------
   * La consultation prénatale porte 1 500 / 5 000 sur le document, quand la
   * Direction a énoncé 15 000 à l'oral. Le document fait foi et la ligne est
   * marquée `aArbitrer` : écraser une pièce écrite par une phrase, ou
   * l'inverse, serait décider à la place de la clinique.
   * ---------------------------------------------------------------------- */
  var CONSULTATIONS = [
    ['CONS-GEN', 'Consultation généraliste', 3000, 5000, true],
    ['CONS-PRE', 'Consultation prénatale', 1500, 5000, true, { aArbitrer: 'La Direction a énoncé 15 000 F ; le document tarifaire porte 1 500 / 5 000.' }],
    ['CONS-SPE', 'Consultation spécialiste', 10000, 10000, true],
    ['CONS-DOM-GEN', 'Consultation à domicile — généraliste', 20000, 25000, true],
    ['CONS-DOM-SPE', 'Consultation à domicile — spécialiste', 25000, 30000, true],
    ['CONS-SPE-SRV', 'Consultation spécialiste sans rendez-vous', 10000, 15000, true],
  ];

  /* --------------------------------------------------------------------------
   * IMAGERIE MÉDICALE
   * ------------------------------------------------------------------------ */
  var IMAGERIES = [
    ['IMG-ECG', 'Électrocardiogramme (ECG)', 10000, 15000, true],
    ['IMG-ECHO-ABD', 'Échographie abdominale', 8000, 12000, true],
    ['IMG-ECHO-ABP', 'Échographie abdomino-pelvienne', 11000, 20000, true],
    ['IMG-ECHO-PEL', 'Échographie pelvienne', 5000, 9000, true],
    ['IMG-ECHO-PRO', 'Échographie prostatique', 8000, 12000, true],
    ['IMG-ECHO-OBS', 'Échographie obstétricale', 5000, 9000, true],
    ['IMG-MAPA', 'MAPA — mesure ambulatoire de la pression artérielle', 25000, 30000, true],
  ];

  /* --------------------------------------------------------------------------
   * ANALYSES DE LABORATOIRE — 41 lignes
   * ------------------------------------------------------------------------
   * L'anomalie du cadrage « colonnes de tarifs vierges — analyses » est levée
   * par ce document. Restent deux valeurs manquantes, conservées nulles :
   * HIV (les deux colonnes) et SPERMOGRAMME (colonne assuré). Le VIH est
   * l'examen le plus sensible du catalogue : lui inventer un prix serait la
   * pire des improvisations.
   * ---------------------------------------------------------------------- */
  var ANALYSES_TARIFS = [
    ['LAB-AKOP', 'AKOP', 2000, 2500, true],
    ['LAB-ASLO', 'ASLO', 2800, 3800, true],
    ['LAB-AZOT', 'Azotémie (urémie)', 1800, 2500, true],
    ['LAB-BILI', 'Bilirubine totale et conjuguée (directe)', 3400, 4800, true],
    ['LAB-BU', 'BU — bandelette urinaire', 500, 1000, true],
    ['LAB-CALC', 'Calcémie', 2200, 3200, true],
    ['LAB-CHOT', 'Cholestérol total', 3200, 4500, true],
    ['LAB-CHOH', 'Cholestérol HDL', 3200, 4500, true],
    ['LAB-CREA', 'Créatinine', 1800, 2500, true],
    ['LAB-CRP', 'CRP', 3000, 4000, true],
    ['LAB-ECBU', 'ECBU', 2500, 3500, true],
    ['LAB-EPHB', 'Électrophorèse de l’hémoglobine', 4000, 6000, true],
    ['LAB-GLY', 'Glycémie', 1700, 2200, true],
    ['LAB-GLYC', 'Glycémie capillaire', 1000, 1500, true],
    ['LAB-GEDP', 'GE-DP / frottis sanguin', 1000, 2000, true],
    ['LAB-GSRH', 'Groupe sanguin — Rhésus', 2500, 3500, true],
    ['LAB-HBC', 'Hémoglobine capillaire', 1000, 1500, true],
    ['LAB-HEPB', 'Hépatite B', 2500, 3500, true],
    ['LAB-HEPC', 'Hépatite C', 3000, 3400, true],
    /* Prix arrêtés par la Direction le 26/08/2026, alignés sur les sérologies
       voisines de la même grille (hépatites, TPHA). L'acte devient facturable ;
       le montant reste modifiable depuis le catalogue. */
    ['LAB-HIV', 'HIV', 2500, 3500, true,
      { arbitrage: 'Prix arrêté par la Direction le 26/08/2026 — la grille ne le portait pas. '
        + 'Aligné sur les sérologies voisines : hépatite B et TPHA, 2 500 / 3 500.' }],
    ['LAB-IONO', 'Ionogramme sanguin', 6500, 8500, true],
    ['LAB-MAGN', 'Magnésémie', 2200, 3200, true],
    ['LAB-NFS', 'NFS complète (hémogramme)', 4000, 6000, true],
    ['LAB-PU', 'Prélèvement urétral (PU)', 2500, 3500, true],
    ['LAB-PV', 'Prélèvement vaginal (PV)', 2500, 3500, true],
    ['LAB-PROT', 'Protidémie', 2200, 3200, true],
    ['LAB-SDW', 'Sérodiagnostic de Widal (SDW)', 4500, 6500, true],
    /* La grille ne portait que le non-assuré (5 000). Le tarif assuré suit le
       rapport moyen du laboratoire — 1,47 —, arrondi au demi-millier. */
    ['LAB-SPER', 'Spermogramme', 3400, 5000, true,
      { arbitrage: 'Tarif assuré arrêté par la Direction le 26/08/2026 — la grille ne le portait pas. '
        + 'Déduit du rapport moyen assuré / non assuré du laboratoire (1,47).' }],
    ['LAB-TBG', 'TBG sérique (sanguin)', 1500, 2000, true],
    ['LAB-TC', 'Temps de coagulation (TC)', 1000, 2000, true],
    ['LAB-TCA', 'Temps de céphaline activée ou kaolin (TCA / TCK)', 3000, 3500, true],
    ['LAB-EMMEL', 'Test d’Emmel', 1000, 2000, true],
    ['LAB-TPINR', 'TP + INR', 6500, 8500, true],
    ['LAB-TPHA', 'TPHA', 2500, 3500, true],
    ['LAB-TGO', 'Transaminase TGO / ASAT', 2200, 3200, true],
    ['LAB-TGP', 'Transaminase TGP / ALAT', 2200, 3200, true],
    ['LAB-GGT', 'Transaminase GGT', 3500, 4500, true],
    ['LAB-TRIG', 'Triglycéride', 2200, 3200, true],
    ['LAB-TS', 'Temps de saignement', 1000, 2000, true],
    ['LAB-URIC', 'Uricémie (acide urique)', 2200, 3200, true],
    ['LAB-VS', 'Vitesse de sédimentation (VS)', 2000, 3000, true],
  ];

  /* --------------------------------------------------------------------------
   * ACTES MÉDICO-INFIRMIERS (AMI) — 39 lignes, codées par la clinique
   * ------------------------------------------------------------------------
   * Les codes sont ceux du document : ils servent déjà au registre papier,
   * les renommer romprait la correspondance.
   * ---------------------------------------------------------------------- */
  var AMI = [
    ['ABCG', 'Abcès — grand', 10000, 14000, true],
    ['ABCM', 'Abcès — moyen', 8000, 12000, true],
    ['ABCP', 'Abcès — petit', 5000, 8000, true],
    ['ABCTP', 'Abcès — très petit', 3000, 5000, true],
    ['AERO', 'Aérosol', 2000, 2500, true],
    ['DEPM', 'Dépistage', 5000, 5000, true],
    ['EXTN', 'Extraction d’ongle', 5000, 7000, true],
    ['EXTO', 'Extraction de corps étranger', 6000, 8000, true],
    ['INFG', 'Infiltration — grande', 10000, 12000, true],
    ['INFM', 'Infiltration — moyenne', 7000, 10000, true],
    ['INFP', 'Infiltration — petite', 5000, 7000, true],
    ['LAVO', 'Lavage oculaire', 3000, 4000, true],
    ['LAVV', 'Lavage vésical', 5000, 7000, true],
    ['OXY1-3', 'Oxygénothérapie — 1 à 3 heures', 2000, 4000, true],
    ['OXY4-6', 'Oxygénothérapie — 4 à 6 heures', 4000, 6000, true],
    ['OXY7-12', 'Oxygénothérapie — 7 à 12 heures', 6000, 8000, true],
    ['OXY13-24', 'Oxygénothérapie — 13 à 24 heures', 12000, 15000, true],
    ['PAN', 'Pansement', 6000, 9000, true],
    ['PANG', 'Pansement — grand', 5000, 8000, true],
    ['PANM', 'Pansement — moyen', 3000, 5000, true],
    ['PANP', 'Pansement — petit', 1000, 2000, true],
    ['PANTG', 'Pansement — très grand', 8000, 12000, true],
    ['PANTP', 'Pansement — très petit', 500, 1000, true],
    ['PONA', 'Ponction d’ascite', 5000, 7000, true],
    ['PONG', 'Ponction — grande', 6000, 8000, true],
    ['PONLA', 'Ponction lombaire A', 3000, 4000, true],
    ['PONLE', 'Ponction lombaire E', 2000, 3000, true],
    ['PONS', 'Ponction simple', 2500, 3000, true],
    ['POSC', 'Pose de sonde', 5000, 7000, true],
    ['PSP', 'Petit soin ponctuel', 1000, 1500, true],
    ['POT', 'Pose de transfusion', 1000, 1500, true],
    /* Prix arrêtés par la Direction le 26/08/2026, alignés sur les poses
       voisines de la même grille : voie veineuse et transfusion. */
    ['PSE', 'Pose de sérum', 1000, 1500, true,
      { arbitrage: 'Prix arrêté par la Direction le 26/08/2026 — la grille ne le portait pas. '
        + 'Aligné sur les poses voisines : prise de voie veineuse et pose de transfusion.' }],
    ['PVV', 'Prise de voie veineuse', 800, 1200, true],
    ['SDI', 'Soin de drain', 10000, 15000, true],
    ['SIM', 'Soin — injection intramusculaire', 800, 1000, true],
    /* La Direction a arrêté 800 assuré / 1 200 non assuré le 26/08/2026. C'est
       exactement ce que donne l'inversion des colonnes appliquée à la grille
       (800 | 1 200) — la ligne n'a donc rien d'exceptionnel : elle confirme la
       règle générale. Elle avait été traitée comme une exception avant que la
       règle ne soit connue. */
    ['SIV', 'Soin — injection intraveineuse', 800, 1200, true],
    ['SC', 'Soin — injection sous-cutanée', 800, 1000, true],
    ['SNG', 'Sonde naso-gastrique', 3000, 5000, true],
    ['SV', 'Sonde vésicale', 5000, 7000, true],
    ['SUT', 'Suture', 1000, 1500, true],
  ];

  /* --------------------------------------------------------------------------
   * ACTES GYNÉCO-OBSTÉTRICAUX ET KITS — 31 lignes
   * ------------------------------------------------------------------------
   * Huit actes portent NON COUVERT en colonne assurée. La lecture métier est
   * nette : ce sont, sans exception, des actes de PLANIFICATION FAMILIALE
   * (implants, injectables, DIU) et l'hydrotubation. L'exclusion est
   * délibérée, ce n'est pas un oubli de saisie.
   * ---------------------------------------------------------------------- */
  var GYNECO = [
    ['ACCDC', 'Accouchement dystocique — césarienne', 12000, 18000, true],
    ['ACCDL', 'Accouchement dystocique — lourd', 20000, 25000, true],
    ['ACCDM', 'Accouchement dystocique — moyen', 15000, 20000, true],
    ['ACCD', 'Accouchement dystocique', 15000, 20000, true],
    ['ACCE', 'Accouchement eutocique', 10000, 15000, true],
    ['ACCS1', 'Accouchement sous surveillance — 1', 45000, 60000, true],
    ['ACCS2', 'Accouchement sous surveillance — 2', 60000, 75000, true],
    ['AMIU', 'Aspiration manuelle intra-utérine (AMIU)', 15000, 20000, true],
    ['BARI', 'Bartholinite — incision', 10000, 15000, true],
    ['DECG', 'Décollement — grand', 10000, 15000, true],
    ['DECP', 'Décollement — petit', 6000, 10000, true],
    ['DEG', 'Délivrance — grande', 8000, 12000, true],
    ['DEM', 'Délivrance — moyenne', 6000, 10000, true],
    ['DEP', 'Délivrance — petite', 5000, 8000, true],
    ['DEA', 'Délivrance artificielle', 5000, 8000, true],
    ['EPG', 'Épisiotomie — grande', 8000, 12000, true],
    ['EPM', 'Épisiotomie — moyenne', 6000, 10000, true],
    ['EPP', 'Épisiotomie — petite', 5000, 8000, true],
    ['EXAS', 'Examen sous spéculum', 5000, 8000, true],
    ['EXPU', 'Exploration utérine', 8000, 12000, true],
    ['HYD', 'Hydrotubation', 15000, NC, false],
    ['PCGJ', 'Pose de cathéter / gel', 4000, 6000, true],
    ['POSI', 'Pose d’implant', 1100, NC, false],
    ['POSD', 'Pose de DIU', 1700, 2500, true],
    ['POSJ', 'Pose d’injectable', 1100, NC, false],
    ['RETIM', 'Retrait d’implant', 2000, NC, false],
    ['RETJ', 'Retrait d’injectable', 2000, NC, false],
    ['RETD', 'Retrait de DIU / stérilet', 2000, NC, false],
    ['SIN', 'Soins IM de Noristerat / Laafia', 450, NC, false],
    ['SIS', 'Soins IM de Sayana Press', 500, NC, false],
    ['SURT', 'Surveillance du travail d’accouchement', 5000, 8000, true],
  ];

  /* --------------------------------------------------------------------------
   * CERTIFICATS — prix unique, couverture SOS seule
   * ------------------------------------------------------------------------
   * La grille ne porte qu'une colonne de prix, assortie de la mention
   * « L'ASSURANCE NE COUVRE PAS À L'EXCEPTION DE SOS ». `prixAssure` y vaut
   * donc `prixNonAssure`, et c'est `assurable: 'sos'` qui porte la règle.
   * ---------------------------------------------------------------------- */
  var CERTIFICATS_TARIFS = [
    ['CERT-DPS', 'Certificat médical de dispense aux activités physiques et sportives', 5000, 5000, 'sos'],
    ['CERT-ATG', 'Attestation de grossesse', 7000, 7000, 'sos'],
    ['CERT-DEC', 'Certificat médical de décès', 10000, 10000, 'sos'],
    ['CERT-CBV', 'Certificat médical initial / de coups et blessures volontaires', 20000, 20000, 'sos'],
    ['CERT-VC', 'Certificat médical de visite et de contre-visite', 8000, 8000, 'sos', { source: 'Mention manuscrite portée sur la grille des certificats' }],
    ['CERT-APT', 'Certificat médical d’aptitude', 7000, 7000, 'sos'],
  ];

  /* ==========================================================================
   * MISE EN FORME
   * ======================================================================== */
  /* ==========================================================================
   * L'INVERSION DES COLONNES — décision de la Direction du 26/08/2026
   * --------------------------------------------------------------------------
   * Les grilles imprimées portent « NON ASSURE | ASSURE » et font, lues
   * littéralement, payer l'assuré plus cher. La Direction affirme l'inverse et
   * donne deux valeurs qui le prouvent : prénatale 1 500 assuré / 5 000 non
   * assuré, soin intraveineux 800 assuré / 1 200 non assuré. Dans les deux cas
   * l'inversion des colonnes reproduit la réponse AU FRANC PRÈS — l'en-tête des
   * grilles est donc inversé à l'impression.
   *
   * La lecture littérale du papier est conservée sur chaque ligne : le jour où
   * quelqu'un rouvrira la grille, il faut pouvoir montrer d'où vient l'écart.
   * ======================================================================== */
  var COLONNES_INVERSEES = true;

  function batir(lignes, famille, source) {
    return lignes.map(function (l) {
      var o = l[5] || {};
      var assure = l[4];
      var c1 = l[2];        /* première colonne de la grille imprimée */
      var c2 = l[3];        /* seconde colonne de la grille imprimée */

      /* NON COUVERT n'a qu'un prix — celui que le patient règle — et ne
         s'inverse donc pas. Un prix absent reste absent. */
      var inversable = COLONNES_INVERSEES && c2 !== NC && c1 != null && c2 != null && c1 !== c2;
      var nonAssure = inversable ? c2 : c1;
      var pa = inversable ? c1 : c2;

      return {
        code: l[0],
        libelle: l[1],
        famille: famille,
        prixNonAssure: nonAssure,
        /* Ce que la grille imprime, mot pour mot — pour pouvoir justifier
           l'écart devant le papier. */
        grilleColonne1: c1,
        grilleColonne2: c2 === NC ? 'NON COUVERT' : c2,
        inverseDepuisGrille: inversable,
        /* NON COUVERT n'est pas un prix : la ligne reste au tarif non assuré
           et le motif accompagne la facture. */
        prixAssure: pa === NC ? null : pa,
        nonCouvert: pa === NC,
        assurable: assure,
        /* Un prix absent n'est ni un zéro ni une exclusion : c'est une valeur
           que le document ne donne pas et qu'il faut faire valider. */
        prixAValider: nonAssure == null || (pa == null && assure !== false),
        motifPrix: o.motifPrix || null,
        aArbitrer: o.aArbitrer || null,
        /* Un arbitrage TRANCHÉ n'est pas une divergence en attente : il est
           appliqué et daté. Les confondre ferait rouvrir une question réglée. */
        arbitrage: o.arbitrage || null,
        source: o.source || source,
        statut: 'actif',
      };
    });
  }

  /* --------------------------------------------------------------------------
   * RADIOGRAPHIE, MAMMOGRAPHIE, SCANNER, IRM — TARIFS D'ATTENTE (vague 61)
   * ------------------------------------------------------------------------
   * La grille des imageries remise ne porte que l'échographie, l'ECG et la
   * MAPA. Les quatre modalités ajoutées n'ont AUCUN prix documenté. Par
   * l'arbitrage du 01/09/2026 (« plus aucun montant nul »), elles reçoivent
   * un tarif d'ATTENTE — jamais présenté comme une donnée : `tarifProvisoire`
   * et un motif daté accompagnent chaque ligne, et l'écran des tarifs les
   * compte à part. Ces lignes ne passent PAS par `batir()` : elles ne viennent
   * d'aucune grille imprimée, il n'y a donc aucune colonne à inverser.
   * La règle de la Direction est tenue : l'assuré paie moins.
   * [code, libellé, prix non assuré, prix assuré]
   * ---------------------------------------------------------------------- */
  var MOTIF_ATTENTE_IMAGERIE = 'Tarif d’attente posé le 14/09/2026 — aucune grille remise pour cette modalité ; '
    + 'à arrêter par la Direction.';
  var IMAGERIES_ATTENTE = [
    ['IMG-RX-THO', 'Radiographie du thorax', 10000, 8000],
    ['IMG-RX-BAS', 'Radiographie du bassin', 12000, 10000],
    ['IMG-RX-RAC', 'Radiographie du rachis', 15000, 12000],
    ['IMG-RX-MEM', 'Radiographie d’un membre', 10000, 8000],
    ['IMG-RX-CRA', 'Radiographie du crâne et des sinus', 12000, 10000],
    ['IMG-RX-ASP', 'Abdomen sans préparation (ASP)', 10000, 8000],
    ['IMG-MAM-DEP', 'Mammographie bilatérale de dépistage', 30000, 25000],
    ['IMG-MAM-DIA', 'Mammographie diagnostique', 35000, 30000],
    ['IMG-TDM-CER', 'Scanner cérébral', 70000, 60000],
    ['IMG-TDM-THO', 'Scanner thoracique', 85000, 75000],
    ['IMG-TDM-ABP', 'Scanner abdomino-pelvien', 100000, 90000],
    ['IMG-TDM-RAC', 'Scanner du rachis', 85000, 75000],
    ['IMG-IRM-CER', 'IRM cérébrale', 150000, 130000],
    ['IMG-IRM-RAC', 'IRM du rachis lombaire', 150000, 130000],
    ['IMG-IRM-GEN', 'IRM du genou', 140000, 120000],
    ['IMG-IRM-PEL', 'IRM pelvienne', 160000, 140000],
  ].map(function (l) {
    return {
      code: l[0], libelle: l[1], famille: 'IMAGERIE',
      prixNonAssure: l[2], prixAssure: l[3],
      grilleColonne1: null, grilleColonne2: null, inverseDepuisGrille: false,
      nonCouvert: false, assurable: true,
      prixAValider: false,
      tarifProvisoire: true,
      motifPrix: MOTIF_ATTENTE_IMAGERIE,
      aArbitrer: null, arbitrage: null,
      source: 'Tarif d’attente — aucune grille remise',
      statut: 'actif',
    };
  });

  var CATALOGUE = []
    .concat(batir(CONSULTATIONS, 'CONSULTATION', SRC.cons))
    .concat(batir(IMAGERIES, 'IMAGERIE', SRC.img))
    .concat(IMAGERIES_ATTENTE)
    .concat(batir(ANALYSES_TARIFS, 'LABO', SRC.labo))
    .concat(batir(AMI, 'AMI', SRC.ami))
    .concat(batir(GYNECO, 'GYNECO', SRC.gyn))
    .concat(batir(CERTIFICATS_TARIFS, 'CERTIFICAT', SRC.cert));

  /* ==========================================================================
   * LE RÉFÉRENTIEL DE PRIX UNIQUE : MOTEUR PUR (PRD-TARIFS, lot T1)
   * --------------------------------------------------------------------------
   * Deux collections au magasin : `tarifs` (l'identité d'une prestation tarifée : code, libellé de facturation, libellé de grille, famille,
   * alias de code) et `versionsTarif` (une ligne par version de prix, IMMUABLE pour ce qui est du prix : une correction ajoute une version).
   * Ce moteur est PUR : il lit des tableaux, jamais le magasin, jamais l'horloge sans qu'on la lui donne. Le magasin lui prête ses collections
   * par `brancher()` ; sans magasin (semence en cours, page sans socle), les lecteurs retombent sur les constantes, comme avant.
   *
   * TROIS ESPACES DE CODES, UNE PRESTATION. Le code d'ACTE (`SO02`), le code de GRILLE (`SIV`) et le code d'ANALYSE (`L01`) désignaient trois fois la
   * même prestation, avec deux libellés et jusqu'à deux prix. Le code canonique est celui de l'acte, sinon celui de l'analyse, sinon celui de la
   * grille ; les autres sont des ALIAS. Chaque lecteur historique garde son espace (`parActe`, `parGrille`, `parAnalyse`) : il reçoit exactement ce qu'il
   * recevait. L'accesseur nouveau (`PR.tarifALaDate`) résout les trois.
   *
   * « EN VIGUEUR » N'EST JAMAIS STOCKÉ : c'est la version `valide` de plus grande (date d'effet, version) dont la date d'effet est antérieure ou égale
   * au JOUR de la pièce. Un poste hors ligne n'a pas de tâche de minuit : une bascule stockée serait fausse dès que l'horloge passe la date.
   * Une version `propose`, `refuse` ou `retire` n'est JAMAIS lue.
   * ======================================================================== */
  var TARIFS = (function () {
    var C = global.SIGH.core;
    var hote = null, cache = null, generation = 0, enSemence = false;

    function jourDe(d) {
      if (!d) return C.iso(C.aujourdhui());
      if (typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d)) return d;
      return C.iso(new Date(d));
    }
    function egal(a, b) { return (a == null && b == null) || a === b; }

    function indexer(tarifs, versions) {
      var h = { tarifs: tarifs, versions: versions, parCode: {}, parActe: {}, parGrille: {}, parAnalyse: {}, vers: {} };
      tarifs.forEach(function (p) {
        if (p.statut === 'archive') return;
        h.parCode[p.code] = p;
        if (p.codeActe) h.parActe[p.codeActe] = p;
        if (p.codeGrille) h.parGrille[p.codeGrille] = p;
        if (p.codeAnalyse) h.parAnalyse[p.codeAnalyse] = p;
      });
      tarifs.forEach(function (p) {
        if (p.statut === 'archive') return;
        (p.codesAlias || []).forEach(function (c) { if (!h.parCode[c]) h.parCode[c] = p; });
      });
      versions.forEach(function (v) { (h.vers[v.code] = h.vers[v.code] || []).push(v); });
      return h;
    }

    /** Le magasin prête ses collections : `fournisseur()` rend { tarifs, versions } ou null. */
    function brancher(fournisseur) { hote = fournisseur; cache = null; generation++; }
    function invalider() { generation++; }
    function modeSemence(oui) { enSemence = !!oui; }
    function lire() {
      if (enSemence || !hote) return null;
      var s = hote();
      if (!s || !Array.isArray(s.tarifs) || !Array.isArray(s.versions) || !s.tarifs.length) return null;
      var n = s.tarifs.length + '/' + s.versions.length;
      if (cache && cache.t === s.tarifs && cache.v === s.versions && cache.n === n && cache.g === generation) return cache.h;
      var h = indexer(s.tarifs, s.versions);
      cache = { t: s.tarifs, v: s.versions, n: n, g: generation, h: h };
      return h;
    }

    function plusRecente(a, b) {
      var da = a.dateEffet || '', db = b.dateEffet || '';
      if (da !== db) return da > db;
      return (a.version || 0) > (b.version || 0);
    }
    /** La version en vigueur de ce code à ce jour (AAAA-MM-JJ), ou null. */
    function enVigueur(h, code, jour) {
      var best = null;
      (h.vers[code] || []).forEach(function (v) {
        if (v.statut !== 'valide') return;
        if (v.dateEffet && v.dateEffet > jour) return;
        if (!best || plusRecente(v, best)) best = v;
      });
      return best;
    }

    /* Les deux motifs ci-dessous sont repris MOT POUR MOT de l'ancien `prix()` : ils s'impriment sur la ligne de facture, la parité les compare. */
    var MOTIF_NC = 'Acte NON COUVERT par les assurances — facturé au patient au tarif non assuré.';
    var MOTIF_SOS = 'Les certificats ne sont couverts que par SOS — vérifier la compagnie.';

    /** Le prix d'une prestation à une date, selon que la carte est valide ou non (RG-09). La forme est celle de l'ancien `D.tarifPrix`, enrichie. */
    function resoudre(h, p, date, assure) {
      var jour = jourDe(date);
      var v = enVigueur(h, p.code, jour);
      if (!v) return { absent: true, montant: null, motif: 'Aucune version de prix valide à la date du ' + jour + ' pour « ' + (p.libelle || p.code) + ' ».', code: p.code };
      var na = v.etatNonAssure === 'manquant' ? null : v.prixNonAssure;
      var base = { code: p.code, version: v.version, dateEffet: v.dateEffet || null, provisoire: v.provisoire === true };
      if (!assure) return Object.assign(base, { montant: na, tarif: 'non assuré', motif: null });
      if (v.etatAssure === 'nc' || p.assurable === false) return Object.assign(base, { montant: na, tarif: 'non assuré', motif: MOTIF_NC });
      if (p.assurable === 'sos') return Object.assign(base, { montant: na, tarif: 'non assuré', motif: MOTIF_SOS, reserveSos: true });
      if (v.etatAssure === 'unique') return Object.assign(base, { montant: na, tarif: 'assuré', motif: null });
      return Object.assign(base, { montant: v.etatAssure === 'montant' ? v.prixAssure : null, tarif: 'assuré', motif: null });
    }

    /** Les deux colonnes et leurs états, en vigueur à ce jour : ce que lisent l'écran et la projection. */
    function instantane(h, p, jour) {
      var v = enVigueur(h, p.code, jourDe(jour));
      if (!v) return null;
      var na = v.etatNonAssure === 'manquant' ? null : v.prixNonAssure;
      var pa = v.etatAssure === 'montant' ? v.prixAssure : (v.etatAssure === 'unique' ? na : null);
      return { na: na, pa: pa, etatNonAssure: v.etatNonAssure || 'montant', etatAssure: v.etatAssure, nc: v.etatAssure === 'nc', version: v.version, dateEffet: v.dateEffet || null, provisoire: v.provisoire === true, vrs: v };
    }

    /** La forme de l'ancienne entrée de grille : la SEMENCE (libellés, arbitrages, colonnes imprimées) superposée au prix en vigueur. */
    function entreeGrille(h, p, semence) {
      var s = instantane(h, p, null);
      var e = Object.assign({}, semence || { code: p.codeGrille, libelle: p.libelleGrille || p.libelle, famille: p.famille, source: p.source || null, statut: 'actif', motifPrix: null }, { assurable: p.assurable });
      if (semence) e.libelle = p.libelleGrille || semence.libelle;
      if (!s) { e.prixNonAssure = null; e.prixAssure = null; e.nonCouvert = false; e.prixAValider = true; return e; }
      e.prixNonAssure = s.na;
      e.nonCouvert = s.nc;
      e.prixAssure = s.nc ? null : s.pa;
      e.prixAValider = s.na == null || (s.pa == null && !s.nc && p.assurable !== false);
      e.version = s.version;
      return e;
    }

    /** Ce que chaque collection historique doit porter aujourd'hui. Renvoie le correctif des seuls champs de PRIX qui diffèrent (null si aucun). */
    function correctifActe(doc, p, s) {
      var c = {}; var poser = function (k, val) { if (!egal(doc[k], val)) c[k] = val; };
      poser('prix', s.na);
      if (doc.prixNonAssure !== undefined) poser('prixNonAssure', s.na);
      if (doc.prixAssure !== undefined || s.etatAssure === 'montant') poser('prixAssure', s.etatAssure === 'montant' ? s.pa : null);
      if (doc.nonCouvert !== undefined || s.nc) poser('nonCouvert', s.nc);
      if (p.assurable !== undefined && s.etatAssure === 'montant') poser('assurable', p.assurable);
      return Object.keys(c).length ? c : null;
    }
    function correctifAnalyse(doc, p, s) {
      return egal(doc.prix, s.na) ? null : { prix: s.na };
    }
    function correctifGrille(doc, p, s) {
      var c = {}; var poser = function (k, val) { if (!egal(doc[k], val)) c[k] = val; };
      poser('prixNonAssure', s.na); poser('nonCouvert', s.nc); poser('prixAssure', s.nc ? null : s.pa);
      poser('prixAValider', s.na == null || (s.pa == null && !s.nc && p.assurable !== false));
      return Object.keys(c).length ? c : null;
    }

    /* ---- Migration : les trois listes d'avant deviennent UN référentiel, sans changer un prix facturé aujourd'hui ----------------------------------- */
    function normLib(x) {
      return String(x || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/’/g, "'")
        .replace(/\([^)]*\)/g, ' ').replace(/[^a-z0-9]+/g, ' ').trim();
    }
    var MOTIF_GRILLE_ANALYSES = 'Prix de la grille imprimée « Tarifs des analyses de laboratoire » : proposé à la Direction (décision T2 du 11/11/2026), '
      + 'Oui ou Non analyse par analyse. Il ne change rien tant qu’il n’est pas validé.';
    var DATE_SEMENCE = '2026-11-11';

    function etatsActe(a) {
      var na = a.prixNonAssure != null ? a.prixNonAssure : (a.prix != null ? a.prix : null);
      var pa = a.prixAssure != null ? a.prixAssure : null, etatA;
      if (a.nonCouvert) { etatA = 'nc'; pa = null; }
      else if (pa != null) etatA = 'montant';
      else if (a.codeTarif || a.assurable === true) etatA = 'manquant';
      else etatA = 'unique';
      return { na: na, etatNA: na == null ? 'manquant' : 'montant', pa: pa, etatA: etatA };
    }
    function etatsGrille(g) {
      var etatA;
      if (g.nonCouvert) etatA = 'nc'; else if (g.prixAssure != null) etatA = 'montant'; else etatA = 'manquant';
      return { na: g.prixNonAssure != null ? g.prixNonAssure : null, etatNA: g.prixNonAssure == null ? 'manquant' : 'montant', pa: g.nonCouvert ? null : (g.prixAssure != null ? g.prixAssure : null), etatA: etatA };
    }
    function creerVersion(code, n, e, o) {
      var v = { id: code + '@' + (o.dateEffet || (o.aDater ? 'a-dater' : 'origine')) + '@' + n, code: code, version: n,
        prixNonAssure: e.na, prixAssure: e.pa, etatAssure: e.etatA,
        origine: o.origine, statut: o.statut || 'valide' };
      /* « montant » est l'état usuel de la colonne non assuré : il ne s'écrit que s'il est autre (quota du magasin). */
      if (e.etatNA !== 'montant') v.etatNonAssure = e.etatNA;
      if (o.dateEffet) v.dateEffet = o.dateEffet;
      if (o.aDater) v.aDater = true;
      if (o.motif) v.motif = o.motif;
      if (o.provisoire) v.provisoire = true;
      if (o.arreteLe) v.arreteLe = o.arreteLe;
      if (o.proposePar) { v.proposePar = o.proposePar; v.proposeLe = o.proposeLe || DATE_SEMENCE; }
      return v;
    }

    /** src = { actes: [fiches de la collection actes], grille: [entrées de la grille], analyses: [analyses], catalogue: [fiches catalogueTarifs] (facultatif) }.
        Rend { tarifs, versions, ecarts } : `ecarts` liste ce qui diverge entre les sources (aucun prix n'est corrigé en silence). */
    function migrer(src) {
      var actes = src.actes || [], grille = src.grille || [], analyses = src.analyses || [];
      var tarifs = [], versions = [], ecarts = [];
      var gParCode = {}, gLabo = {}, grilleUtilisee = {};
      grille.forEach(function (g) { gParCode[g.code] = g; if (g.famille === 'LABO') gLabo[normLib(g.libelle)] = g; });

      /* 1. Les actes : le code d'acte est canonique, la ligne de grille rapprochée devient un alias. */
      actes.forEach(function (a) {
        var g = a.codeTarif ? gParCode[a.codeTarif] : null;
        var e = etatsActe(a);
        var p = { id: a.code, code: a.code, codeActe: a.code, libelle: a.libelle, famille: g ? g.famille : (/^HO\d/.test(a.code) ? 'HOSPITALISATION' : 'ACTE'), statut: 'actif' };
        if (a.secteur) p.secteur = a.secteur;
        if (g) { p.codeGrille = g.code; p.codesAlias = [g.code]; if (g.libelle !== a.libelle) p.libelleGrille = g.libelle; grilleUtilisee[g.code] = true; }
        if (a.assurable !== undefined) p.assurable = a.assurable;
        if (a.variantesGrille && a.variantesGrille.length) p.variantesGrille = a.variantesGrille.map(function (x) { return x.code || x; });
        tarifs.push(p);
        versions.push(creerVersion(a.code, 1, e, { origine: 'migration', provisoire: a.tarifProvisoire === true, arreteLe: a.tarifArreteLe, motif: a.motifPrix }));
        if (g) {
          var eg = etatsGrille(g);
          if (eg.na !== e.na || eg.pa !== e.pa || eg.etatA !== e.etatA) {
            ecarts.push({ type: 'acte-grille', code: a.code, grille: g.code, acte: { na: e.na, pa: e.pa, etat: e.etatA }, ligneDeGrille: { na: eg.na, pa: eg.pa, etat: eg.etatA }, detail: 'Le prix de l’acte diffère de la ligne de grille : le prix de l’acte (celui de la caisse) est retenu.' });
          }
        }
      });

      /* 2. Les analyses : le code d'analyse est canonique ; la ligne LABO de même libellé NORMALISÉ (aucun rapprochement approximatif) devient un alias,
         et son prix arrive en version 2 PROPOSÉE quand il diffère de ce que la caisse facture. */
      analyses.forEach(function (a) {
        var g = gLabo[normLib(a.designation)];
        if (g && grilleUtilisee[g.code]) g = null;
        var prix = a.prix != null && a.prix > 0 ? a.prix : null;
        var e = { na: prix, etatNA: prix == null ? 'manquant' : 'montant', pa: prix, etatA: prix == null ? 'manquant' : 'unique' };
        var p = { id: a.code, code: a.code, codeAnalyse: a.code, libelle: a.designation, famille: 'LABO', statut: 'actif' };
        if (g) { p.codeGrille = g.code; p.codesAlias = [g.code]; p.libelleGrille = g.libelle; p.assurable = g.assurable; grilleUtilisee[g.code] = true; }
        tarifs.push(p);
        versions.push(creerVersion(a.code, 1, e, { origine: 'migration', provisoire: a.tarifProvisoire === true }));
        if (g) {
          var eg = etatsGrille(g);
          if (eg.na !== e.na || eg.pa !== e.pa || eg.etatA !== e.etatA) {
            versions.push(creerVersion(a.code, 2, eg, { origine: 'semence-grille', statut: 'propose', aDater: true, proposePar: 'Semence du socle', motif: MOTIF_GRILLE_ANALYSES }));
            ecarts.push({ type: 'analyse-grille', code: a.code, grille: g.code, facture: { na: e.na }, ligneDeGrille: { na: eg.na, pa: eg.pa, etat: eg.etatA }, detail: 'Version 2 proposée (le prix facturé aujourd’hui reste la version 1).' });
          }
        } else {
          ecarts.push({ type: 'analyse-sans-grille', code: a.code, detail: 'Aucune ligne de la grille imprimée ne porte ce libellé : un seul prix, celui de la caisse.' });
        }
      });

      /* 3. Les lignes de grille restantes : une prestation chacune, au prix que la grille donne (celui que lisaient les soins, l'imagerie, les certificats). */
      grille.forEach(function (g) {
        if (grilleUtilisee[g.code]) return;
        var e = etatsGrille(g);
        var p = { id: g.code, code: g.code, codeGrille: g.code, libelle: g.libelle, famille: g.famille, statut: 'actif' };
        if (g.assurable !== undefined) p.assurable = g.assurable;
        tarifs.push(p);
        versions.push(creerVersion(g.code, 1, e, { origine: 'migration', provisoire: g.tarifProvisoire === true, motif: g.motifPrix }));
        if (g.famille === 'LABO') ecarts.push({ type: 'grille-sans-analyse', code: g.code, detail: 'Ligne LABO de la grille sans analyse de même libellé : prestation propre, au prix de la grille.' });
      });

      /* 4. Les éditions faites au catalogue tarifaire (collection que personne ne lisait) : listées, jamais appliquées. */
      (src.catalogue || []).forEach(function (c) {
        var g = gParCode[c.code];
        if (!g) { ecarts.push({ type: 'catalogue-inconnu', code: c.code, detail: 'Fiche du catalogue tarifaire sans ligne de grille : non reprise.' }); return; }
        ['prixNonAssure', 'prixAssure', 'nonCouvert', 'assurable'].forEach(function (k) {
          if (!egal(c[k], g[k]) && !(k === 'nonCouvert' && !c[k] && !g[k])) {
            ecarts.push({ type: 'catalogue-grille', code: c.code, champ: k, catalogue: c[k], grille: g[k], detail: 'Édité au catalogue tarifaire sans effet sur la facturation : non repris.' });
          }
        });
      });
      return { tarifs: tarifs, versions: versions, ecarts: ecarts };
    }

    return {
      brancher: brancher, invalider: invalider, modeSemence: modeSemence, lire: lire, indexer: indexer, enVigueur: enVigueur, resoudre: resoudre,
      instantane: instantane, entreeGrille: entreeGrille, jourDe: jourDe, migrer: migrer, normLibelle: normLib,
      correctifActe: correctifActe, correctifAnalyse: correctifAnalyse, correctifGrille: correctifGrille,
      semence: null, DATE_SEMENCE: DATE_SEMENCE, MOTIF_GRILLE_ANALYSES: MOTIF_GRILLE_ANALYSES, MOTIF_NC: MOTIF_NC,
    };
  })();

  /* ==========================================================================
   * INTERROGATION
   * ======================================================================== */

  /* Le prix applicable dépend d'une seule question, celle de RG-09 : la carte
     est-elle valide à la date de facturation ? Elle ne dépend PAS du fait que
     le patient possède une carte — une carte expirée facture au tarif non
     assuré, et le dit. */
  function prix(code, assure, date) {
    var e = parEntree(code);
    if (!e) return { montant: null, motif: 'Acte absent du catalogue tarifaire.' };
    /* LE PRIX EST CELUI DE LA VERSION EN VIGUEUR À LA DATE DE LA PIÈCE (PRD-TARIFS, T1). Sans date, c'est celui d'aujourd'hui. */
    var h = TARIFS.lire();
    if (h) {
      var p = h.parGrille[code];
      if (p) {
        var r = TARIFS.resoudre(h, p, date || null, assure);
        if (r.absent) return { montant: null, motif: r.motif };
        delete r.absent;
        return r;
      }
    }
    if (!assure) {
      return { montant: e.prixNonAssure, tarif: 'non assuré', motif: null };
    }
    if (e.assurable === false || e.nonCouvert) {
      return {
        montant: e.prixNonAssure, tarif: 'non assuré',
        motif: 'Acte NON COUVERT par les assurances — facturé au patient au tarif non assuré.',
      };
    }
    if (e.assurable === 'sos') {
      return {
        montant: e.prixNonAssure, tarif: 'non assuré',
        motif: 'Les certificats ne sont couverts que par SOS — vérifier la compagnie.',
        reserveSos: true,
      };
    }
    return { montant: e.prixAssure, tarif: 'assuré', motif: null };
  }

  /* La couverture d'un certificat dépend de la compagnie, pas seulement du
     type d'acte : SOS fait exception, nommément. */
  function couvertPar(code, compagnie) {
    var e = parEntree(code);
    if (!e) return false;
    if (e.assurable === false || e.nonCouvert) return false;
    if (e.assurable === 'sos') return /sos/i.test(String(compagnie || ''));
    return true;
  }

  /* L'entrée de la grille est celle de la SEMENCE (libellés, arbitrages, colonnes imprimées) SUPERPOSÉE au prix en vigueur du
     référentiel : le lecteur historique reçoit la forme qu'il recevait, avec le prix que la caisse applique. */
  var INDEX = null;
  function semenceParCode(code) {
    if (!INDEX) {
      INDEX = {};
      CATALOGUE.forEach(function (e) { INDEX[e.code] = e; });
    }
    return INDEX[code] || null;
  }
  function parEntree(code) {
    var s = semenceParCode(code);
    var h = TARIFS.lire();
    if (!h) return s;
    var p = h.parGrille[code];
    if (!p) return s;
    return TARIFS.entreeGrille(h, p, s);
  }

  function parFamille(famille) {
    var h = TARIFS.lire();
    if (!h) return CATALOGUE.filter(function (e) { return e.famille === famille; });
    var vus = {}, out = [];
    CATALOGUE.forEach(function (e) { if (e.famille === famille) { vus[e.code] = true; var x = parEntree(e.code); if (x) out.push(x); } });
    h.tarifs.forEach(function (p) {
      if (p.famille === famille && p.codeGrille && !vus[p.codeGrille] && p.statut !== 'archive') { var x = parEntree(p.codeGrille); if (x) out.push(x); }
    });
    return out;
  }

  /* Les trois lignes dont le document ne donne pas le prix. L'écran les compte
     et les nomme : une facture ne peut pas être émise sur une valeur absente. */
  function sansPrix() {
    return CATALOGUE.map(function (e) { return parEntree(e.code); }).filter(function (e) { return e && e.prixAValider; });
  }

  /* ==========================================================================
   * CONTRÔLE DE COHÉRENCE
   * --------------------------------------------------------------------------
   * Règle posée par la Direction : dans TOUS les actes, l'assuré paie moins que
   * le non-assuré. Une ligne qui la contredit est soit une faute de saisie,
   * soit une exception délibérée — dans les deux cas elle doit se voir.
   * ======================================================================== */
  function incoherences() {
    return CATALOGUE.map(function (e) { return parEntree(e.code); }).filter(function (e) {
      if (!e || e.nonCouvert || e.prixAssure == null || e.prixNonAssure == null) return false;
      return e.prixAssure > e.prixNonAssure;
    });
  }

  /* ==========================================================================
   * RAPPROCHEMENT DES ACTES AVEC LES GRILLES
   * --------------------------------------------------------------------------
   * Les 69 actes du document « Répartition des activités » portaient 64 tarifs
   * D'ATTENTE, inventés le 20/08/2026 pour rendre la facturation exerçable. Les
   * six grilles imprimées donnent les prix réels — et DEUX par acte.
   *
   * DEUX NIVEAUX DE RAPPROCHEMENT, ET AUCUN TROISIÈME.
   *
   * 1. LIBELLÉ IDENTIQUE (aux accents, à la casse et aux parenthèses près) :
   *    appliqué sans discussion. « Échographie pelvienne » est « Échographie
   *    pelvienne ».
   * 2. CORRESPONDANCE NOMMÉE, écrite ici une par une avec sa raison. C'est
   *    délibérément un tableau à la main : un rapprochement approximatif
   *    apparierait « Consultation généraliste à domicile » avec « Consultation
   *    généraliste » et ferait perdre le déplacement, ou « Glycémie rapide »
   *    au lit du malade avec la « Glycémie » du laboratoire, qui n'est pas le
   *    même acte.
   *
   * CE QUI RESTE PROVISOIRE LE RESTE, ET DIT POURQUOI. Un acte que la grille
   * décline en plusieurs variantes — sept accouchements, quatre paliers
   * d'oxygénothérapie, trois épisiotomies, deux ponctions lombaires — ne peut
   * pas recevoir « le » prix de la grille : c'est à la clinique de dire quelle
   * variante son acte désigne. Le champ « variantesGrille » les porte, pour que
   * l'écran pose la question au lieu de choisir à sa place.
   * ======================================================================== */

  /* Acte du document  ->  code de la grille. Une ligne, une raison. */
  var CORRESPONDANCES = {
    SO02: 'SIV',   /* Soins intraveineux (SIV) = Soin — injection intraveineuse. Arbitré le 26/08. */
    SO13: 'AERO',  /* Aérosolthérapie = Aérosol. */
    MA10: 'AMIU',  /* AMIU = Aspiration manuelle intra-utérine. Le sigle est développé des deux côtés. */
    MA04: 'SIS',   /* Sayana Press : la grille le nomme. */
    MA07: 'SIN',   /* Noristérat : la grille le nomme, avec son équivalent Laafia. */
    MA06: 'POSD',  /* Pose de DIU. */
    MA09: 'RETD',  /* Retrait de DIU / stérilet. */
    MA05: 'POSI',  /* Implanon et Jadelle SONT des implants : la grille tarife la pose d'implant. */
    MA08: 'RETIM', /* Idem pour le retrait. */
    MA15: 'SURT',  /* Surveillance du travail d'accouchement. */
  };

  /* Actes que la grille décline : on ne choisit pas à la place de la clinique. */
  var DECLINES = {
    MA02: ['ACCE', 'ACCD', 'ACCDM', 'ACCDL', 'ACCDC', 'ACCS1', 'ACCS2'],
    MA14: ['EPP', 'EPM', 'EPG'],
    MG05: ['PONLE', 'PONLA'],
    SO12: ['OXY1-3', 'OXY4-6', 'OXY7-12', 'OXY13-24'],
    MG06: null, /* quatorze certificats, un prix par type : voir la famille « certificats ». */
  };

  function normLibelle(x) {
    return String(x || '').toLowerCase()
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/\u2019/g, "'")
      .replace(/\([^)]*\)/g, ' ')
      .replace(/[^a-z0-9]+/g, ' ').trim();
  }

  function rapprocherActes() {
    var actes = D.ACTES || [];
    if (!actes.length) return;

    var parLibelle = {}, parCode = {};
    CATALOGUE.forEach(function (e) {
      parLibelle[normLibelle(e.libelle)] = e;
      parCode[e.code] = e;
    });

    actes.forEach(function (a) {
      var g = parLibelle[normLibelle(a.libelle)];
      var voie = g ? 'libellé identique' : null;
      if (!g && CORRESPONDANCES[a.code]) {
        g = parCode[CORRESPONDANCES[a.code]];
        voie = 'correspondance nommée';
      }

      if (!g) {
        if (Object.prototype.hasOwnProperty.call(DECLINES, a.code)) {
          a.variantesGrille = (DECLINES[a.code] || []).map(function (c) {
            return parCode[c];
          }).filter(Boolean);
          a.motifPrix = a.variantesGrille && a.variantesGrille.length
            ? 'La grille décline cet acte en ' + a.variantesGrille.length + ' variantes : '
              + 'la clinique doit dire laquelle elle facture.'
            : 'Le prix dépend du type de pièce : voir la grille des certificats.';
        }
        return;
      }

      /* Le prix de référence est celui du NON-ASSURÉ : c'est le tarif affiché,
         celui qu'on applique par défaut. La part assurée s'y ajoute comme une
         seconde colonne, elle ne le remplace pas. */
      a.prix = g.prixNonAssure != null ? g.prixNonAssure : a.prix;
      a.prixNonAssure = g.prixNonAssure;
      a.prixAssure = g.prixAssure;
      a.nonCouvert = !!g.nonCouvert;
      a.assurable = g.assurable;
      a.codeTarif = g.code;
      a.tarifProvisoire = false;
      a.source = g.source;
      a.rapprochement = voie;
      if (g.arbitrage) a.arbitrage = g.arbitrage;
    });
  }

  rapprocherActes();

  /* Compte rendu du rapprochement, consommé par l'écran des tarifs : il doit
     pouvoir dire combien d'actes restent sans prix validé, et pourquoi. */
  D.actesRapproches = function () {
    return (D.ACTES || []).filter(function (a) { return a.codeTarif; });
  };
  D.actesProvisoires = function () {
    return (D.ACTES || []).filter(function (a) { return a.tarifProvisoire; });
  };
  D.actesDeclines = function () {
    return (D.ACTES || []).filter(function (a) { return a.variantesGrille && a.variantesGrille.length; });
  };

  /* ==========================================================================
   * LA SEMENCE ET LES LECTEURS HISTORIQUES DES CONSTANTES (PRD-TARIFS, T1)
   * --------------------------------------------------------------------------
   * `D.ANALYSES[i].prix` et `D.TYPES_CHAMBRE[i].tarif` étaient lus par une trentaine d'écrans (listes, estimations, caisse manuelle). Ils lisent
   * désormais le prix EN VIGUEUR du référentiel, par une propriété calculée posée sur la constante : un lecteur de plus ou de moins ne change rien, et
   * aucun ne peut plus facturer un prix que l'écran « Tarifs et prix » ne porte pas. La SEMENCE (valeur d'origine) est conservée à côté : elle seule
   * sert à bâtir le référentiel et à semer, jamais ce qu'on lit. Le lot T7 retirera ces propriétés quand les lecteurs passeront à l'accesseur daté.
   * ======================================================================== */
  var SEMENCE_ANALYSES = (D.ANALYSES || []).map(function (a) { return Object.assign({}, a); });
  var SEMENCE_CHAMBRES = (D.TYPES_CHAMBRE || []).map(function (c) { return Object.assign({}, c); });
  function prixCourant(h, p) { var s = TARIFS.instantane(h, p, null); return s ? s.na : null; }
  (D.ANALYSES || []).forEach(function (a) {
    var valeur = a.prix;
    Object.defineProperty(a, 'prix', {
      enumerable: true, configurable: true,
      get: function () { var h = TARIFS.lire(); var p = h && h.parAnalyse[a.code]; return p ? prixCourant(h, p) : valeur; },
      set: function (v) { valeur = v; },
    });
  });
  (D.TYPES_CHAMBRE || []).forEach(function (c, i) {
    var valeur = c.tarif, code = 'HO' + (i < 9 ? '0' : '') + (i + 1);
    Object.defineProperty(c, 'tarif', {
      enumerable: true, configurable: true,
      get: function () { var h = TARIFS.lire(); var p = h && h.parActe[code]; return p ? prixCourant(h, p) : valeur; },
      set: function (v) { valeur = v; },
    });
  });
  TARIFS.semence = { analyses: SEMENCE_ANALYSES, chambres: SEMENCE_CHAMBRES, grille: CATALOGUE, actes: function () { return D.ACTES || []; } };
  D.TARIFS = TARIFS;

  D.tarifsIncoherents = incoherences;
  D.TARIFS_COLONNES_INVERSEES = COLONNES_INVERSEES;
  D.FAMILLES_TARIF = FAMILLES;
  D.CATALOGUE = CATALOGUE;
  D.NON_COUVERT = NC;
  D.tarif = parEntree;
  D.tarifPrix = prix;
  D.tarifCouvertPar = couvertPar;
  D.tarifParFamille = parFamille;
  D.tarifsSansPrix = sansPrix;
})(window);
