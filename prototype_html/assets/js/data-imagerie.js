/* ==========================================================================
 * IMAGERIE — LE MODÈLE DE COMPTE RENDU
 * --------------------------------------------------------------------------
 * Fondé sur SIX pièces réelles de newinfos/ :
 *   - cinq comptes rendus édités par la clinique (pelvienne, vésico-prostatique,
 *     abdomino-pelvienne, obstétricale, obstétricale du 1er trimestre) ;
 *   - le BROUILLON MANUSCRIT de l'échographiste, qui est la pièce décisive :
 *     il énumère lui-même, de sa main, les listes de choix qu'il veut voir
 *     pré-insérées.
 *
 * CE QUE LE BROUILLON DICTE, ET QU'IL NE FAUT PAS DÉFAIRE :
 *
 *   - des LISTES DE CHOIX partout où la valeur est catégorielle : nombre de
 *     sacs (01/02/03/autre), aspect (tonique/hypotonique), localisation
 *     (intra-utérine/extra-utérine/autre), réaction trophoblastique
 *     (décollement ou non), activité cardiaque (active/inactive) ;
 *
 *   - l'âge gestationnel est un COUPLE « n SA + n jours », pas un texte : le
 *     saisir librement autoriserait « 7 mois », qui ne se compare à rien.
 *     Le couple demeure ; depuis le 14/09/2026 ses deux moitiés se saisissent
 *     en champ texte (demande de l'échographiste), comme toutes les mesures ;
 *
 *   - MAIS la « Conclusion » reste en TEXTE LIBRE — « à remplir par
 *     moi-même ». (« Annexes », libre elle aussi à l'origine, a été RETIRÉE
 *     le 14/09/2026 sur demande de l'échographiste.)
 *
 * Le pied de chaque compte rendu réel porte « Réalisé par : AHOHOU Rodrigue »
 * avec ses téléphones : l'échographiste est un intervenant NOMMÉ sur la pièce,
 * au même titre que le prescripteur.
 * ======================================================================== */
(function (global) {
  'use strict';

  var D = global.SIGH.data;

  /* --------------------------------------------------------------------------
   * TYPES DE VARIABLE
   * ------------------------------------------------------------------------ */
  var TYPES = [
    { code: 'liste', label: 'Liste de choix' },
    { code: 'binaire', label: 'Deux valeurs' },
    { code: 'mesure', label: 'Mesure chiffrée' },
    { code: 'dimensions', label: 'Trois dimensions (mm)' },
    { code: 'gestationnel', label: 'Âge gestationnel (SA + jours)' },
    { code: 'texte', label: 'Texte libre' },
    { code: 'zone', label: 'Texte libre — plusieurs lignes' },
    { code: 'multiple', label: 'Choix multiples' },
  ];

  /* --------------------------------------------------------------------------
   * LES CINQ MODALITÉS — UN SOCLE COMMUN, CINQ TABLEAUX (vague 61)
   * ------------------------------------------------------------------------
   * Radiographie, mammographie, scanner et IRM ne sont PAS quatre modules :
   * ce sont quatre modalités qui se branchent sur le socle que l'échographie
   * a construit — la demande (`PR.ouvrirDemandeImagerie`), la ligne payable,
   * le verrou de caisse, les états demandée → payée → exécutée → validée, le
   * compte rendu par variables, le rendu au prescripteur, la galerie. Quatre
   * modules auraient recopié quatre fois ce circuit, et les copies auraient
   * divergé au premier correctif. La modalité est une PROPRIÉTÉ DE L'EXAMEN.
   *
   * CE QUI VIENT D'UN DOCUMENT ET CE QUI N'EN VIENT PAS. L'échographie repose
   * sur six pièces réelles. Pour les quatre autres modalités, AUCUN modèle de
   * compte rendu n'a été remis : leurs examens et variables sont une
   * PROPOSITION fondée sur la pratique radiologique courante (classification
   * ACR/BI-RADS pour la mammographie), marquée `aValider`, à arrêter par le
   * radiologue — exactement comme les check-listes du bloc l'ont été.
   *
   * `rubriquesLibres` : l'échographie ne garde que la « Conclusion » depuis
   * le 14/09/2026 (« Annexes » retirée à sa demande). Les autres modalités suivent le
   * plan classique du compte rendu radiologique — résultats rédigés,
   * conclusion, recommandation — la technique étant portée par des variables.
   * ---------------------------------------------------------------------- */
  var PROPOSITION = 'Proposition — aucun modèle de compte rendu remis pour cette modalité ; à arrêter par le radiologue.';
  var LIBRES_RADIOLOGIE = [
    { code: 'resultats', label: 'Résultats — description rédigée', note: 'Complète les variables : ce que les cases ne disent pas.' },
    { code: 'conclusion', label: 'Conclusion', note: 'Reprise telle quelle sur le compte rendu.', requis: true },
    { code: 'recommandation', label: 'Recommandation', note: 'Examen complémentaire, contrôle, avis spécialisé.' },
  ];
  var MODALITES = [
    /* 14/09/2026 : « Annexes » RETIRÉE à la demande de l'échographiste — la
       Conclusion reste libre. `saisieTexte` : les mesures se saisissent en
       texte (« 12 x 8 », « < 5 », « non mesurable »). `provenance` : le
       formulaire d'ouverture du compte rendu demande d'où vient le patient. */
    { code: 'echographie', label: 'Échographie', tableau: 'Tableau Échographie', ecran: 'm2-imagerie',
      icone: 'scan-line', aValider: null, saisieTexte: true, provenance: true,
      rubriquesLibres: [
        { code: 'conclusion', label: 'Conclusion', note: 'Rédigée par l’échographiste. Reprise telle quelle sur le compte rendu.', requis: true },
      ] },
    /* LES RÈGLES DE L'ÉCHOGRAPHIE, ÉTENDUES AUX QUATRE AUTRES (21/09/2026,
       APPLIQUER_REGLES.txt). Elles ne sont pas recopiées : elles sont
       PORTÉES PAR LA MODALITÉ, et une passe les applique à tous ses examens
       — présents comme futurs. Les écrire variable par variable sur les
       soixante déclarations des quatre modalités aurait garanti autant
       d'oublis, et un examen ajouté demain n'en aurait hérité d'aucune.
         - `saisieTexte` : « environ 12 mm », « sup à 5 cm » — le radiologue
           écrit des expressions cliniques, un champ numérique les refuse ;
         - `provenance` : d'où vient le patient, à l'en-tête du compte rendu ;
         - `autreSystematique` : toute liste de classification, de protocole
           ou d'incidence reçoit « Autre » et son champ de précision.
       « Annexes » n'a jamais existé pour ces quatre-là — LIBRES_RADIOLOGIE
       porte Résultats / Conclusion / Recommandation : la règle est donc
       déjà tenue, et il n'y a rien à retirer. */
    { code: 'radiographie', label: 'Radiographie', tableau: 'Tableau Radiographie', ecran: 'm2-imagerie-radiographie',
      icone: 'bone', aValider: PROPOSITION, saisieTexte: true, provenance: true, autreSystematique: true,
      rubriquesLibres: LIBRES_RADIOLOGIE },
    { code: 'mammographie', label: 'Mammographie', tableau: 'Tableau Mammographie', ecran: 'm2-imagerie-mammographie',
      icone: 'ribbon', aValider: PROPOSITION, saisieTexte: true, provenance: true, autreSystematique: true,
      rubriquesLibres: LIBRES_RADIOLOGIE },
    { code: 'scanner', label: 'Scanner', tableau: 'Tableau Scanner', ecran: 'm2-imagerie-scanner',
      icone: 'radiation', aValider: PROPOSITION, saisieTexte: true, provenance: true, autreSystematique: true,
      rubriquesLibres: LIBRES_RADIOLOGIE },
    { code: 'irm', label: 'IRM — imagerie par résonance magnétique', tableau: 'Tableau IRM', ecran: 'm2-imagerie-irm',
      icone: 'magnet', aValider: PROPOSITION, saisieTexte: true, provenance: true, autreSystematique: true,
      rubriquesLibres: LIBRES_RADIOLOGIE },
  ];

  /* --------------------------------------------------------------------------
   * LES SEPT EXAMENS DU CATALOGUE
   * ------------------------------------------------------------------------
   * Codes alignés sur ceux du catalogue tarifaire : un examen d'imagerie est
   * un acte facturable, et l'un ne doit pas exister sans l'autre.
   * ---------------------------------------------------------------------- */
  var EXAMENS = [
    { code: 'IMG-ECHO-PEL', label: 'Échographie pelvienne', icone: 'scan-line', voie: 'sus-pubienne', modalite: 'echographie' },
    { code: 'IMG-ECHO-ABD', label: 'Échographie abdominale', icone: 'scan-line', voie: 'transpariétale', modalite: 'echographie' },
    { code: 'IMG-ECHO-ABP', label: 'Échographie abdomino-pelvienne', icone: 'scan-line', voie: 'transpariétale', modalite: 'echographie' },
    { code: 'IMG-ECHO-PRO', label: 'Échographie vésico-prostatique', icone: 'scan-line', voie: 'sus-pubienne', modalite: 'echographie' },
    { code: 'IMG-ECHO-OBS', label: 'Échographie obstétricale', icone: 'baby', voie: 'sus-pubienne', modalite: 'echographie' },
    { code: 'IMG-ECHO-OBS1', label: 'Échographie obstétricale du 1er trimestre', icone: 'baby', voie: 'sus-pubienne',
      tarifCode: 'IMG-ECHO-OBS', modalite: 'echographie' },
    /* Ajouté le 14/09/2026 : le 1er trimestre « évolué », où l'embryon est
       devenu fœtus. Même tarif que l'obstétricale — aucune grille ne le
       distingue ; le distinguer serait inventer un prix. */
    { code: 'IMG-ECHO-OBS1E', label: 'Échographie obstétricale du 1er trimestre évolué', icone: 'baby', voie: 'sus-pubienne',
      tarifCode: 'IMG-ECHO-OBS', modalite: 'echographie' },
    /* L'ECG n'est pas une image, mais il se réalise et se rend au même poste :
       il reste au tableau de l'échographiste, où il a toujours été saisi. */
    { code: 'IMG-ECG', label: 'Électrocardiogramme (ECG)', icone: 'activity', voie: null, modalite: 'echographie' },

    /* --- Radiographie — proposition ------------------------------------- */
    { code: 'IMG-RX-THO', label: 'Radiographie du thorax', icone: 'bone', modalite: 'radiographie', aValider: PROPOSITION },
    { code: 'IMG-RX-BAS', label: 'Radiographie du bassin', icone: 'bone', modalite: 'radiographie', aValider: PROPOSITION },
    { code: 'IMG-RX-RAC', label: 'Radiographie du rachis', icone: 'bone', modalite: 'radiographie', aValider: PROPOSITION },
    { code: 'IMG-RX-MEM', label: 'Radiographie d’un membre', icone: 'bone', modalite: 'radiographie', aValider: PROPOSITION },
    { code: 'IMG-RX-CRA', label: 'Radiographie du crâne et des sinus', icone: 'bone', modalite: 'radiographie', aValider: PROPOSITION },
    { code: 'IMG-RX-ASP', label: 'Abdomen sans préparation (ASP)', icone: 'bone', modalite: 'radiographie', aValider: PROPOSITION },
    /* --- Mammographie — proposition -------------------------------------- */
    { code: 'IMG-MAM-DEP', label: 'Mammographie bilatérale de dépistage', icone: 'ribbon', modalite: 'mammographie', aValider: PROPOSITION },
    { code: 'IMG-MAM-DIA', label: 'Mammographie diagnostique', icone: 'ribbon', modalite: 'mammographie', aValider: PROPOSITION },
    /* --- Scanner — proposition ------------------------------------------- */
    { code: 'IMG-TDM-CER', label: 'Scanner cérébral', icone: 'radiation', modalite: 'scanner', aValider: PROPOSITION },
    { code: 'IMG-TDM-THO', label: 'Scanner thoracique', icone: 'radiation', modalite: 'scanner', aValider: PROPOSITION },
    { code: 'IMG-TDM-ABP', label: 'Scanner abdomino-pelvien', icone: 'radiation', modalite: 'scanner', aValider: PROPOSITION },
    { code: 'IMG-TDM-RAC', label: 'Scanner du rachis', icone: 'radiation', modalite: 'scanner', aValider: PROPOSITION },
    /* --- IRM — proposition ----------------------------------------------- */
    { code: 'IMG-IRM-CER', label: 'IRM cérébrale', icone: 'magnet', modalite: 'irm', aValider: PROPOSITION },
    { code: 'IMG-IRM-RAC', label: 'IRM du rachis lombaire', icone: 'magnet', modalite: 'irm', aValider: PROPOSITION },
    { code: 'IMG-IRM-GEN', label: 'IRM du genou', icone: 'magnet', modalite: 'irm', aValider: PROPOSITION },
    { code: 'IMG-IRM-PEL', label: 'IRM pelvienne', icone: 'magnet', modalite: 'irm', aValider: PROPOSITION },
  ];

  /* --------------------------------------------------------------------------
   * VARIABLES PAR EXAMEN
   * ------------------------------------------------------------------------
   * [code, libellé, type, options|unité, { rubrique, normal }]
   * ---------------------------------------------------------------------- */
  var V = {};

  /* ==========================================================================
   * CORRECTIONS DE L'ÉCHOGRAPHISTE — 14/09/2026
   * --------------------------------------------------------------------------
   * Trois mécanismes NOUVEAUX, portés par la variable elle-même et non codés
   * écran par écran — un écran qui les coderait en dur les oublierait au
   * premier examen ajouté :
   *
   *   - `conditionnels` : des champs de texte qui n'apparaissent QUE pour
   *     certaines valeurs (« Autre » → préciser ; « hétérogène » → décrire ;
   *     ovaire anormal → taille et échostructure). Un champ toujours visible
   *     ferait remplir « RAS » sous « homogène » ; un champ absent ferait
   *     écrire la précision dans la conclusion, où elle se perd.
   *   - `repete` : le bloc se DUPLIQUE selon le nombre déclaré par une autre
   *     variable (deux sacs → deux blocs de sac). Les blocs 2 et 3 paraissent
   *     repliables sous le premier : la modale ne s'allonge que si la
   *     grossesse est multiple. Les valeurs se rangent `CODE__2`, `CODE__3`.
   *   - la modalité `saisieTexte` : toutes les mesures d'échographie se
   *     saisissent en TEXTE — l'échographiste écrit « 12 x 8 », « < 5 »,
   *     « non mesurable » ; un champ numérique refusait ce qu'il écrit.
   *
   * Et une décision qui REMPLACE la précédente : la rubrique libre
   * « Annexes » est RETIRÉE de tous les comptes rendus d'échographie, à la
   * demande de l'échographiste lui-même ; la Conclusion reste libre.
   * ======================================================================== */
  function precision(valeurs, code, libelle) {
    return { quand: valeurs, code: code, libelle: libelle };
  }
  var AUTRE = ['Autre'];

  /* --- Échographie pelvienne (compte rendu ABALO/AGNILO) ------------------- */
  /* LES VALEURS QUI APPELLENT LA DESCRIPTION D'UN OVAIRE (21/09/2026).
     La directive nommait « ovaire droit anormal », « OVAIRE DROIT NORMAL »
     et « les deux anormaux ». La vague 63 avait lu une coquille pour
     « ovaire gauche anormal » et ne l'avait pas appliquée — elle l'avait
     SIGNALÉE. L'échographiste a confirmé le libellé : « ovaire droit
     normal » est une valeur à part entière, celle où le droit est sain et
     où c'est le GAUCHE qu'il faut décrire. Elle rejoint donc la liste des
     options ET celle des déclencheurs.

     « ovaire gauche anormal » RESTE déclencheur, bien que la directive ne
     le renomme pas : l'en retirer masquerait la taille et l'échostructure
     exactement quand l'ovaire gauche est anormal — la seule lecture qu'on
     ne puisse pas défendre. Une directive qui ajoute un cas n'en supprime
     pas un autre en silence. */
  var OVAIRE_A_DECRIRE = ['ovaire droit anormal', 'ovaire droit normal', 'ovaire gauche anormal', 'les deux anormaux'];
  V['IMG-ECHO-PEL'] = [
    ['VESSIE', 'Vessie', 'liste', ['bien remplie', 'insuffisamment remplie', 'vide'], { rubrique: 'Résultat', normal: 'bien remplie' }],
    ['UT_STAT', 'Statique utérine', 'liste', ['antéversée, antéfléchie', 'rétroversée', 'intermédiaire', 'latérodéviée', 'Autre'],
      { rubrique: 'Utérus', conditionnels: [precision(AUTRE, 'UT_STAT_AUTRE', 'Statique utérine — préciser')] }],
    ['UT_VAC', 'Vacuité utérine', 'liste', ['Visible', 'Non visible'], { rubrique: 'Utérus' }],
    ['UT_DIM', 'Dimensions utérines', 'dimensions', 'mm', { rubrique: 'Utérus' }],
    ['UT_ECHO', 'Échostructure', 'liste', ['homogène', 'hétérogène'],
      { rubrique: 'Utérus', normal: 'homogène', conditionnels: [precision(['hétérogène'], 'UT_ECHO_DET', 'Hétérogène — préciser')] }],
    ['UT_CONT', 'Contours', 'liste', ['réguliers', 'irréguliers'], { rubrique: 'Utérus', normal: 'réguliers' }],
    ['ENDO', 'Épaisseur de l’endomètre', 'mesure', 'mm', { rubrique: 'Utérus' }],
    ['ENDO_CONTENU', 'Contenu', 'texte', null, { rubrique: 'Utérus' }],
    /* La rubrique s'appelait « Annexes » (au sens anatomique). La rubrique
       LIBRE « Annexes » étant retirée, le même mot ne doit plus désigner le
       bloc des ovaires : on le nomme par ce qu'il contient. */
    ['OVAIRES', 'Ovaires', 'liste', ['normaux', 'ovaire droit anormal', 'ovaire droit normal',
      'ovaire gauche anormal', 'les deux anormaux'],
    { rubrique: 'Ovaires et cul-de-sac de Douglas', normal: 'normaux', conditionnels: [
      precision(OVAIRE_A_DECRIRE, 'OV_TAILLE', 'Taille'),
      precision(OVAIRE_A_DECRIRE, 'OV_ECHO', 'Échostructure'),
    ] }],
    ['DOUGLAS', 'Cul-de-sac de Douglas', 'liste', ['libre', 'épanchement de faible abondance', 'épanchement de moyenne abondance', 'épanchement de grande abondance'], { rubrique: 'Ovaires et cul-de-sac de Douglas', normal: 'libre' }],
  ];

  /* --- Échographie vésico-prostatique (compte rendu NOUKOURE OROU) --------- */
  V['IMG-ECHO-PRO'] = [
    ['PR_LARG', 'Prostate — largeur', 'mesure', 'mm', { rubrique: 'Prostate' }],
    ['PR_HAUT', 'Prostate — hauteur', 'mesure', 'mm', { rubrique: 'Prostate' }],
    ['PR_EP', 'Prostate — épaisseur', 'mesure', 'mm', { rubrique: 'Prostate' }],
    ['PR_VOL', 'Volume prostatique', 'mesure', 'g', { rubrique: 'Prostate' }],
    ['PR_ECHO', 'Échostructure prostatique', 'liste', ['homogène', 'hétérogène'], { rubrique: 'Prostate', normal: 'homogène' }],
    ['PR_NOD', 'Plus grand nodule', 'mesure', 'mm', { rubrique: 'Prostate' }],
    ['PR_CONT', 'Contours prostatiques', 'liste', ['réguliers', 'irréguliers'], { rubrique: 'Prostate', normal: 'réguliers' }],
    ['RD', 'Rein droit — axe bipolaire', 'mesure', 'mm', { rubrique: 'Reins' }],
    ['RG', 'Rein gauche — axe bipolaire', 'mesure', 'mm', { rubrique: 'Reins' }],
    ['R_DIL', 'Dilatation des voies excrétrices', 'binaire', ['absente', 'présente'], { rubrique: 'Reins', normal: 'absente' }],
    ['R_DIFF', 'Différenciation cortico-médullaire', 'binaire', ['conservée', 'altérée'], { rubrique: 'Reins', normal: 'conservée' }],
    ['R_LITH', 'Formation lithiasique', 'binaire', ['absente', 'présente'], { rubrique: 'Reins', normal: 'absente' }],
    ['VE_REPL', 'Vessie — réplétion', 'liste', ['bonne réplétion', 'réplétion insuffisante'], { rubrique: 'Vessie', normal: 'bonne réplétion' }],
    ['VE_PAROI', 'Vessie — épaisseur de paroi', 'mesure', 'mm', { rubrique: 'Vessie' }],
    ['VE_CONT', 'Vessie — contours de paroi', 'liste', ['réguliers', 'irréguliers'], { rubrique: 'Vessie', normal: 'réguliers' }],
    ['VE_CONT2', 'Vessie — contenu', 'liste', ['transsonore homogène', 'anéchogène homogène', 'échogène'], { rubrique: 'Vessie', normal: 'transsonore homogène' }],
    ['VE_MASSE', 'Masse intravésicale', 'binaire', ['absente', 'visible'], { rubrique: 'Vessie', normal: 'absente' }],
    ['RPM', 'Résidu post-mictionnel', 'mesure', 'ml', { rubrique: 'Vessie' }],
  ];

  /* --- Échographie abdomino-pelvienne (compte rendu ABDOU-RAHAMANE) -------- */
  V['IMG-ECHO-ABP'] = [
    ['FOIE', 'Foie — taille', 'mesure', 'mm', { rubrique: 'Foie et voies biliaires' }],
    ['FOIE_C', 'Foie — contours', 'liste', ['réguliers', 'irréguliers'], { rubrique: 'Foie et voies biliaires', normal: 'réguliers' }],
    ['FOIE_E', 'Foie — échostructure', 'liste', ['homogène', 'hétérogène'], { rubrique: 'Foie et voies biliaires', normal: 'homogène' }],
    ['VPORTE', 'Veine porte — calibre', 'mesure', 'mm', { rubrique: 'Foie et voies biliaires' }],
    ['VB_PAROI', 'Vésicule biliaire — paroi', 'mesure', 'mm', { rubrique: 'Foie et voies biliaires' }],
    ['VB_CONT', 'Vésicule biliaire — contenu', 'liste', ['transsonore alithiasique', 'lithiasique', 'sludge'], { rubrique: 'Foie et voies biliaires', normal: 'transsonore alithiasique' }],
    ['VB_VOIES', 'Voies biliaires intra et extra-hépatiques', 'binaire', ['sans anomalie', 'dilatées'], { rubrique: 'Foie et voies biliaires', normal: 'sans anomalie' }],
    ['VSH', 'Veines sus-hépatiques et veine cave inférieure', 'binaire', ['perméables, calibre normal', 'anormales'], { rubrique: 'Foie et voies biliaires', normal: 'perméables, calibre normal' }],
    ['RD2', 'Rein droit — axe bipolaire', 'mesure', 'mm', { rubrique: 'Reins' }],
    ['RG2', 'Rein gauche — axe bipolaire', 'mesure', 'mm', { rubrique: 'Reins' }],
    ['R_DIL2', 'Dilatation des voies excrétrices', 'binaire', ['absente', 'présente'], { rubrique: 'Reins', normal: 'absente' }],
    ['RATE', 'Rate — hauteur', 'mesure', 'mm', { rubrique: 'Rate et pancréas' }],
    ['PANC', 'Pancréas', 'liste', ['taille normale, contours réguliers, échostructure homogène', 'anormal'], { rubrique: 'Rate et pancréas', normal: 'taille normale, contours réguliers, échostructure homogène' }],
    ['VE_ABP', 'Vessie', 'liste', ['bonne réplétion, contenu anéchogène, paroi non épaissie', 'paroi épaissie', 'contenu échogène'], { rubrique: 'Appareil urinaire bas', normal: 'bonne réplétion, contenu anéchogène, paroi non épaissie' }],
    ['PR_ABP', 'Prostate — dimensions', 'dimensions', 'mm', { rubrique: 'Appareil urinaire bas' }],
    ['PR_VOL2', 'Volume prostatique', 'mesure', 'g', { rubrique: 'Appareil urinaire bas' }],
    ['RPM2', 'Résidu post-mictionnel', 'mesure', 'ml', { rubrique: 'Appareil urinaire bas' }],
    ['MASSE', 'Syndrome de masse ou adénopathie profonde', 'binaire', ['absent', 'présent'], { rubrique: 'Épanchements et masses', normal: 'absent' }],
    ['EPANCH', 'Épanchement liquidien intra-péritonéal', 'binaire', ['absent', 'présent'], { rubrique: 'Épanchements et masses', normal: 'absent' }],
  ];

  /* L'abdominale seule reprend les rubriques hautes de l'abdomino-pelvienne. */
  V['IMG-ECHO-ABD'] = V['IMG-ECHO-ABP'].filter(function (v) {
    return (v[4] || {}).rubrique !== 'Appareil urinaire bas';
  });

  /* --- Obstétricale du 1er trimestre — LE BROUILLON MANUSCRIT -------------- */
  /* Corrections du 14/09/2026 : réaction trophoblastique en quatre valeurs,
     vésicule vitelline ajoutée sous la dimension du sac, et la rubrique
     « Conclusion » à cases (type de grossesse, siège, évolutivité, contrôle
     programmé) RETIRÉE — la conclusion reste celle, rédigée, de
     l'échographiste. Le bloc du sac se DUPLIQUE selon le nombre de sacs,
     celui de l'embryon selon le nombre d'embryons.

     LE RYTHME CARDIAQUE, REPOSITIONNÉ (21/09/2026). La directive demandait
     de retirer le champ « Rythme cardiaque (bpm) » de sa place INITIALE —
     entre l'activité cardiaque et le LCC — puis le nommait parmi les champs
     à passer en TEXTE, entre le LCC et l'âge gestationnel correspondant.
     Le 14/09 n'avait lu que la première phrase et l'avait supprimé tout
     court : l'échographiste ne pouvait plus porter le rythme qu'il mesure.
     Il revient donc à SA place — après le LCC, et après la biométrie
     (BIP, PC, LF) sur l'examen évolué, où celle-ci suit immédiatement le
     LCC. Déplacer un champ n'est pas le supprimer : un compte rendu rendu
     avant le 14/09 le porte encore, et le relit sans rien perdre. */
  function premierTrimestre(evolue) {
    var nom = evolue ? 'Fœtus' : 'Embryon';
    var sac = { rubrique: 'Sac gestationnel', repete: 'SG_NB' };
    var bloc = { rubrique: nom, repete: 'EM_NB' };
    function o(base, extra) { return Object.assign({}, base, extra || {}); }
    var out = [
      ['SG_NB', 'Sac gestationnel — nombre', 'liste', ['01', '02', '03', 'autre'], { rubrique: 'Sac gestationnel' }],
      ['SG_ASP', 'Sac gestationnel — aspect', 'binaire', ['tonique', 'hypotonique'], o(sac, { normal: 'tonique' })],
      ['SG_LOC', 'Localisation', 'liste', ['intra-utérine', 'extra-utérine', 'Autre'],
        o(sac, { normal: 'intra-utérine', conditionnels: [precision(AUTRE, 'SG_LOC_AUTRE', 'Localisation — préciser')] })],
      ['SG_DIM', 'Dimension du sac', 'mesure', 'mm', o(sac)],
      ['VES_VIT', 'Vésicule vitelline', 'liste', ['vue', 'non vue'], o(sac, { normal: 'vue' })],
      ['SG_AG', 'Âge gestationnel', 'gestationnel', null, o(sac)],
      ['SG_TROPH', 'Réaction trophoblastique', 'liste', ['mauvaise', 'médiocre', 'bonne', 'décollement'], o(sac, { normal: 'bonne' })],
      ['EM_NB', nom + ' — nombre', 'liste', ['01', '02', '03', 'autre'], { rubrique: nom }],
      evolue
        ? ['EM_CARD', 'Activité cardiaque', 'liste', ['active ce jour', 'inactive', 'Autre'],
          o(bloc, { normal: 'active ce jour', conditionnels: [precision(AUTRE, 'EM_CARD_AUTRE', 'Activité cardiaque — préciser')] })]
        : ['EM_CARD', 'Activité cardiaque', 'binaire', ['active ce jour', 'inactive'], o(bloc, { normal: 'active ce jour' })],
      ['EM_LCC', 'LCC — longueur cranio-caudale', 'mesure', 'mm', o(bloc)],
    ];
    if (evolue) {
      /* « Immédiatement après le bloc LCC » : la biométrie du fœtus. */
      out.push(['EM_BIP', 'BIP — diamètre bipariétal', 'mesure', 'mm', o(bloc)]);
      out.push(['EM_PC', 'PC — périmètre crânien', 'mesure', 'mm', o(bloc)]);
      out.push(['EM_LF', 'LF — longueur du fémur', 'mesure', 'mm', o(bloc)]);
    }
    /* Le rythme cardiaque : une MESURE, donc saisie en texte comme les
       autres (« 150 », « environ 140 », « non mesurable ce jour »). */
    out.push(['EM_BPM', 'Rythme cardiaque', 'mesure', 'bpm', o(bloc)]);
    out.push(['EM_AG', 'Âge gestationnel correspondant', 'gestationnel', null, o(bloc)]);
    return out;
  }
  V['IMG-ECHO-OBS1'] = premierTrimestre(false);
  /* L'examen « évolué » : le même formulaire, où l'embryon est devenu FŒTUS
     et porte sa biométrie (BIP, PC, LF). Un seul générateur pour les deux :
     deux listes recopiées divergeraient au premier correctif. */
  V['IMG-ECHO-OBS1E'] = premierTrimestre(true);

  /* --- Obstétricale (compte rendu ABALO Bernadette) ------------------------ */
  V['IMG-ECHO-OBS'] = [
    ['F_NB', 'Fœtus — nombre', 'liste', ['01', '02', '03'], { rubrique: 'Fœtus' }],
    ['F_PRES', 'Présentation', 'liste', ['céphalique mobile dos à gauche', 'céphalique mobile dos à droite',
      'transversal dos supérieur', 'transversal dos inférieur', 'siège mobile dos à droite', 'siège mobile dos à gauche', 'Autre'],
    { rubrique: 'Fœtus', conditionnels: [precision(AUTRE, 'F_PRES_AUTRE', 'Présentation — préciser')] }],
    ['F_BPM', 'Activité cardiaque', 'mesure', 'bats/min', { rubrique: 'Fœtus' }],
    ['F_MAF', 'MAF — mouvements actifs fœtaux', 'binaire', ['présents', 'absents'], { rubrique: 'Fœtus', normal: 'présents' }],
    ['F_MR', 'MR — mouvements respiratoires', 'binaire', ['présents', 'absents'], { rubrique: 'Fœtus', normal: 'présents' }],
    ['BIP', 'BIP — diamètre bipariétal', 'mesure', 'mm', { rubrique: 'Biométrie' }],
    ['HC', 'HC — périmètre céphalique', 'mesure', 'mm', { rubrique: 'Biométrie' }],
    ['AC', 'AC — périmètre abdominal', 'mesure', 'mm', { rubrique: 'Biométrie' }],
    ['FL', 'FL — longueur fémorale', 'mesure', 'mm', { rubrique: 'Biométrie' }],
    ['AG', 'Âge gestationnel', 'gestationnel', null, { rubrique: 'Biométrie' }],
    ['PLAC_POS', 'Placenta — position', 'liste', ['antérieur loin du col', 'postérieur loin du col', 'bas inséré', 'recouvrant', 'Autre'],
      { rubrique: 'Annexes fœtales', normal: 'antérieur loin du col', conditionnels: [precision(AUTRE, 'PLAC_POS_AUTRE', 'Placenta — préciser la position')] }],
    ['PLAC_GR', 'Placenta — grade', 'liste', ['grade 0', 'grade I', 'grade II', 'grade III'], { rubrique: 'Annexes fœtales' }],
    /* « diminuée » et « augmentée » cèdent la place à la terminologie de
       l'échographiste, orthographe médicale rétablie (oligoamnios,
       hydramnios).

       « OLIGO-AMNIOS » PREND SON TRAIT D'UNION, « hydramnios » non — c'est
       ainsi que la directive les écrit, et c'est ainsi que l'échographiste
       les a confirmés le 21/09/2026. La dissymétrie n'est pas une coquille :
       on n'uniformise pas l'orthographe d'un professionnel pour faire joli.

       « AMNIOS », ET NON « ANAMNIOS » (arbitrage de l'échographiste,
       21/09/2026). La directive écrivait « Amnios » ; la vague 63 avait
       lu une coquille pour « anamnios » — l'absence de liquide — et gardé
       le mot savant en le SIGNALANT plutôt qu'en le corrigeant d'office.
       Interrogé, l'échographiste a confirmé : c'est « Amnios » qu'il
       porte sur ses comptes rendus. C'est SON vocabulaire qui fait foi
       sur la pièce qu'il signe — la liste dit ce qu'il écrit, elle ne lui
       enseigne pas sa nomenclature. */
    ['LA_ABOND', 'Liquide amniotique — abondance', 'liste', ['moyenne', 'en excès', 'amnios', 'oligo-amnios', 'oligo-amnios modéré',
      'oligo-amnios sévère', 'hydramnios', 'hydramnios modéré', 'hydramnios sévère', 'Autre'],
    { rubrique: 'Annexes fœtales', normal: 'moyenne', conditionnels: [precision(AUTRE, 'LA_ABOND_AUTRE', 'Abondance — préciser')] }],
    ['LA_IA', 'Index amniotique (mesure des 04 citernes)', 'mesure', 'mm', { rubrique: 'Annexes fœtales' }],
    ['LA_ASP', 'Liquide amniotique — aspect', 'liste', ['normal', 'trouble', 'Autre'],
      { rubrique: 'Annexes fœtales', normal: 'normal', conditionnels: [precision(AUTRE, 'LA_ASP_AUTRE', 'Aspect — préciser')] }],
    ['M_THOR', 'Thorax', 'liste', ['vu', 'non vu'], { rubrique: 'Morphologie', normal: 'vu' }],
    ['M_COEUR', 'Cœur', 'liste', ['actif (04 cavités)', 'anomalie'], { rubrique: 'Morphologie', normal: 'actif (04 cavités)' }],
    ['M_RACHIS', 'Colonne vertébrale', 'liste', ['vue et suivie', 'non vue'], { rubrique: 'Morphologie', normal: 'vue et suivie' }],
    ['M_CERV', 'Cerveau', 'liste', ['vu', 'non vu'], { rubrique: 'Morphologie', normal: 'vu' }],
    ['M_PAROI', 'Paroi abdominale', 'liste', ['fermée', 'anomalie'], { rubrique: 'Morphologie', normal: 'fermée' }],
    ['M_ESTOM', 'Estomac', 'liste', ['vu', 'non vu'], { rubrique: 'Morphologie', normal: 'vu' }],
    ['M_REINS', 'Reins', 'liste', ['vus', 'non vus'], { rubrique: 'Morphologie', normal: 'vus' }],
    ['M_VESSIE', 'Vessie', 'liste', ['vue', 'non vue'], { rubrique: 'Morphologie', normal: 'vue' }],
    ['M_SEXE', 'Sexe', 'liste', ['Masculin', 'Féminin', 'non déterminé'], { rubrique: 'Morphologie' }],
    ['M_AUTRES', 'Autres', 'texte', null, { rubrique: 'Morphologie', normal: 'RAS' }],
    /* La rubrique « Synthèse » (poids fœtal estimé, score de Manning, date
       probable d'accouchement, aspects pathologiques) est RETIRÉE à la
       demande de l'échographiste (14/09/2026). */
  ];

  /* --- ECG ----------------------------------------------------------------- */
  V['IMG-ECG'] = [
    ['RYTHME', 'Rythme', 'liste', ['sinusal régulier', 'sinusal irrégulier', 'fibrillation auriculaire', 'autre'], { rubrique: 'Tracé', normal: 'sinusal régulier' }],
    ['FC', 'Fréquence cardiaque', 'mesure', 'bpm', { rubrique: 'Tracé' }],
    ['PR', 'Espace PR', 'mesure', 'ms', { rubrique: 'Tracé' }],
    ['QRS', 'Durée du QRS', 'mesure', 'ms', { rubrique: 'Tracé' }],
    ['QT', 'Intervalle QT corrigé', 'mesure', 'ms', { rubrique: 'Tracé' }],
    ['AXE', 'Axe électrique', 'liste', ['normal', 'dévié à gauche', 'dévié à droite'], { rubrique: 'Tracé', normal: 'normal' }],
    ['REPOL', 'Repolarisation', 'liste', ['normale', 'trouble de repolarisation'], { rubrique: 'Tracé', normal: 'normale' }],
    ['HYPER', 'Signes d’hypertrophie', 'binaire', ['absents', 'présents'], { rubrique: 'Tracé', normal: 'absents' }],
    ['ISCH', 'Signes d’ischémie', 'binaire', ['absents', 'présents'], { rubrique: 'Tracé', normal: 'absents' }],
  ];

  /* ==========================================================================
   * LES QUATRE MODALITÉS AJOUTÉES — VARIABLES PROPOSÉES
   * --------------------------------------------------------------------------
   * Mêmes principes que l'échographie : listes de choix là où la valeur est
   * catégorielle, une valeur normale déclarée (ce qui s'en écarte passe en
   * gras sur la pièce), la conclusion en texte libre. Rien de ceci ne vient
   * d'un document de la clinique — voir `PROPOSITION`.
   * ======================================================================== */
  var SANS_AVEC = ['absente', 'présente'];

  /* La technique d'une radiographie : l'incidence et la qualité du cliché.
     Un cliché de qualité insuffisante se refait — le dire sur la pièce évite
     qu'un « normal » soit lu sur une image inexploitable. */
  var RX_TECHNIQUE = [
    ['RX_QUAL', 'Qualité technique du cliché', 'liste', ['satisfaisante', 'acceptable', 'insuffisante — à refaire'], { rubrique: 'Technique', normal: 'satisfaisante' }],
  ];

  V['IMG-RX-THO'] = [
    ['RX_INC', 'Incidence(s)', 'liste', ['face', 'face et profil', 'face au lit'], { rubrique: 'Technique', normal: 'face' }],
  ].concat(RX_TECHNIQUE, [
    ['THO_PAR', 'Parenchyme pulmonaire', 'liste', ['clair, sans opacité', 'opacité alvéolaire', 'syndrome interstitiel', 'nodule(s)', 'image cavitaire'], { rubrique: 'Poumons et plèvre', normal: 'clair, sans opacité' }],
    ['THO_CUL', 'Culs-de-sac pleuraux', 'liste', ['libres', 'comblement droit', 'comblement gauche', 'comblement bilatéral'], { rubrique: 'Poumons et plèvre', normal: 'libres' }],
    ['THO_PNX', 'Pneumothorax', 'binaire', ['absent', 'présent'], { rubrique: 'Poumons et plèvre', normal: 'absent' }],
    ['THO_ICT', 'Index cardio-thoracique', 'mesure', '', { rubrique: 'Cœur et médiastin' }],
    ['THO_COEUR', 'Silhouette cardiaque', 'liste', ['normale', 'cardiomégalie'], { rubrique: 'Cœur et médiastin', normal: 'normale' }],
    ['THO_MED', 'Médiastin', 'liste', ['normal', 'élargi'], { rubrique: 'Cœur et médiastin', normal: 'normal' }],
    ['THO_COUP', 'Coupoles diaphragmatiques', 'liste', ['régulières', 'surélévation droite', 'surélévation gauche'], { rubrique: 'Cadre osseux et parois', normal: 'régulières' }],
    ['THO_OS', 'Cadre osseux', 'liste', ['sans anomalie', 'fracture costale', 'lésion osseuse'], { rubrique: 'Cadre osseux et parois', normal: 'sans anomalie' }],
  ]);

  V['IMG-RX-BAS'] = [
    ['RX_INC', 'Incidence(s)', 'liste', ['face', 'face et profils de hanches'], { rubrique: 'Technique', normal: 'face' }],
  ].concat(RX_TECHNIQUE, [
    ['BAS_FRACT', 'Fracture', 'binaire', SANS_AVEC, { rubrique: 'Os et articulations', normal: 'absente' }],
    ['BAS_COT', 'Interlignes coxo-fémoraux', 'liste', ['conservés', 'pincement droit', 'pincement gauche', 'pincement bilatéral'], { rubrique: 'Os et articulations', normal: 'conservés' }],
    ['BAS_SI', 'Articulations sacro-iliaques', 'liste', ['normales', 'irrégularités', 'ankylose'], { rubrique: 'Os et articulations', normal: 'normales' }],
    ['BAS_TF', 'Têtes fémorales', 'liste', ['sphériques, de densité normale', 'ostéonécrose suspectée', 'déformées'], { rubrique: 'Os et articulations', normal: 'sphériques, de densité normale' }],
  ]);

  V['IMG-RX-RAC'] = [
    ['RAC_SEG', 'Segment exploré', 'liste', ['cervical', 'dorsal', 'lombaire', 'lombo-sacré'], { rubrique: 'Technique' }],
    ['RX_INC', 'Incidence(s)', 'liste', ['face et profil', 'face, profil et trois-quarts', 'dynamiques'], { rubrique: 'Technique', normal: 'face et profil' }],
  ].concat(RX_TECHNIQUE, [
    ['RAC_ALIGN', 'Alignement', 'liste', ['conservé', 'attitude scoliotique', 'listhésis', 'rectitude'], { rubrique: 'Rachis', normal: 'conservé' }],
    ['RAC_CORPS', 'Hauteur des corps vertébraux', 'liste', ['conservée', 'tassement'], { rubrique: 'Rachis', normal: 'conservée' }],
    ['RAC_DISC', 'Espaces intervertébraux', 'liste', ['conservés', 'pincement discal'], { rubrique: 'Rachis', normal: 'conservés' }],
    ['RAC_OSTEO', 'Ostéophytose', 'binaire', ['absente', 'présente'], { rubrique: 'Rachis', normal: 'absente' }],
    ['RAC_LYSE', 'Lésion lytique ou condensante', 'binaire', SANS_AVEC, { rubrique: 'Rachis', normal: 'absente' }],
  ]);

  V['IMG-RX-MEM'] = [
    ['MEM_COTE', 'Côté', 'liste', ['droit', 'gauche', 'bilatéral'], { rubrique: 'Technique' }],
    ['MEM_SEG', 'Segment', 'liste', ['épaule', 'bras', 'coude', 'avant-bras', 'poignet', 'main', 'hanche', 'cuisse', 'genou', 'jambe', 'cheville', 'pied'], { rubrique: 'Technique' }],
    ['RX_INC', 'Incidence(s)', 'liste', ['face et profil', 'face', 'profil', 'incidences spécifiques'], { rubrique: 'Technique', normal: 'face et profil' }],
  ].concat(RX_TECHNIQUE, [
    ['MEM_FRACT', 'Fracture', 'binaire', SANS_AVEC, { rubrique: 'Résultat osseux', normal: 'absente' }],
    ['MEM_TRAIT', 'Trait de fracture', 'liste', ['sans objet', 'transversal', 'oblique', 'spiroïde', 'comminutif', 'arrachement'], { rubrique: 'Résultat osseux', normal: 'sans objet' }],
    ['MEM_DEPL', 'Déplacement', 'binaire', ['non déplacée', 'déplacée'], { rubrique: 'Résultat osseux', normal: 'non déplacée' }],
    ['MEM_ART', 'Articulation', 'liste', ['congruente', 'luxation', 'épanchement', 'arthrose'], { rubrique: 'Articulations et parties molles', normal: 'congruente' }],
    ['MEM_PM', 'Parties molles', 'liste', ['sans anomalie', 'tuméfaction', 'corps étranger radio-opaque'], { rubrique: 'Articulations et parties molles', normal: 'sans anomalie' }],
  ]);

  V['IMG-RX-CRA'] = [
    ['RX_INC', 'Incidence(s)', 'liste', ['face et profil', 'Blondeau', 'Hirtz'], { rubrique: 'Technique', normal: 'face et profil' }],
  ].concat(RX_TECHNIQUE, [
    ['CRA_VOUTE', 'Voûte crânienne', 'liste', ['sans anomalie', 'trait de fracture', 'lésion lytique'], { rubrique: 'Crâne', normal: 'sans anomalie' }],
    ['CRA_SELLE', 'Selle turcique', 'liste', ['normale', 'élargie'], { rubrique: 'Crâne', normal: 'normale' }],
    ['CRA_SINUS', 'Sinus de la face', 'liste', ['clairs', 'comblement maxillaire', 'comblement frontal', 'pansinusite', 'niveau hydro-aérique'], { rubrique: 'Sinus', normal: 'clairs' }],
  ]);

  V['IMG-RX-ASP'] = [
    ['RX_INC', 'Incidence(s)', 'liste', ['debout de face', 'couché de face', 'debout et couché'], { rubrique: 'Technique', normal: 'debout de face' }],
  ].concat(RX_TECHNIQUE, [
    ['ASP_NHA', 'Niveaux hydro-aériques', 'binaire', ['absents', 'présents'], { rubrique: 'Abdomen', normal: 'absents' }],
    ['ASP_PNEU', 'Pneumopéritoine', 'binaire', ['absent', 'présent'], { rubrique: 'Abdomen', normal: 'absent' }],
    ['ASP_GAZ', 'Répartition gazeuse', 'liste', ['normale', 'distension grêlique', 'distension colique'], { rubrique: 'Abdomen', normal: 'normale' }],
    ['ASP_CALC', 'Calcifications', 'liste', ['aucune', 'lithiase rénale', 'lithiase vésiculaire', 'calcifications pancréatiques', 'autres'], { rubrique: 'Abdomen', normal: 'aucune' }],
  ]);

  /* --- Mammographie : la classification ACR (BI-RADS) PAR SEIN ------------
     C'est la conduite à tenir qui en découle, et elle diffère d'un sein à
     l'autre : une catégorie unique pour la patiente perdrait le côté. */
  var BIRADS = ['ACR 0 — évaluation incomplète', 'ACR 1 — normal', 'ACR 2 — bénin', 'ACR 3 — probablement bénin',
    'ACR 4 — suspect', 'ACR 5 — hautement suspect', 'ACR 6 — malignité prouvée'];
  var MAMMO = [
    ['MAM_ANT', 'Antécédents pertinents', 'texte', null, { rubrique: 'Contexte', normal: 'aucun' }],
    ['MAM_INC', 'Incidences', 'liste', ['face et oblique externe bilatérales', 'face et oblique externe — côté concerné', 'incidences complémentaires'], { rubrique: 'Technique', normal: 'face et oblique externe bilatérales' }],
    ['MAM_DENS', 'Densité mammaire', 'liste', ['type a — graisseux', 'type b — densités fibroglandulaires éparses', 'type c — dense hétérogène', 'type d — extrêmement dense'], { rubrique: 'Technique' }],
    ['MAM_MASSE_D', 'Sein droit — masse', 'binaire', SANS_AVEC, { rubrique: 'Sein droit', normal: 'absente' }],
    ['MAM_CALC_D', 'Sein droit — microcalcifications', 'liste', ['absentes', 'bénignes', 'suspectes'], { rubrique: 'Sein droit', normal: 'absentes' }],
    ['MAM_DIST_D', 'Sein droit — distorsion architecturale', 'binaire', SANS_AVEC, { rubrique: 'Sein droit', normal: 'absente' }],
    ['MAM_ACR_D', 'Sein droit — classification', 'liste', BIRADS, { rubrique: 'Sein droit', normal: 'ACR 1 — normal' }],
    ['MAM_MASSE_G', 'Sein gauche — masse', 'binaire', SANS_AVEC, { rubrique: 'Sein gauche', normal: 'absente' }],
    ['MAM_CALC_G', 'Sein gauche — microcalcifications', 'liste', ['absentes', 'bénignes', 'suspectes'], { rubrique: 'Sein gauche', normal: 'absentes' }],
    ['MAM_DIST_G', 'Sein gauche — distorsion architecturale', 'binaire', SANS_AVEC, { rubrique: 'Sein gauche', normal: 'absente' }],
    ['MAM_ACR_G', 'Sein gauche — classification', 'liste', BIRADS, { rubrique: 'Sein gauche', normal: 'ACR 1 — normal' }],
    ['MAM_GG', 'Ganglions axillaires', 'liste', ['non visibles ou d’aspect normal', 'adénopathie droite', 'adénopathie gauche', 'adénopathies bilatérales'], { rubrique: 'Creux axillaires', normal: 'non visibles ou d’aspect normal' }],
  ];
  V['IMG-MAM-DEP'] = MAMMO;
  V['IMG-MAM-DIA'] = [
    ['MAM_COTE', 'Côté exploré', 'liste', ['bilatéral', 'droit', 'gauche'], { rubrique: 'Contexte', normal: 'bilatéral' }],
    ['MAM_SIGNE', 'Signe d’appel', 'liste', ['nodule palpé', 'écoulement mamelonnaire', 'mastodynie', 'rétraction cutanée ou mamelonnaire', 'surveillance'], { rubrique: 'Contexte' }],
  ].concat(MAMMO);

  /* --- Scanner : l'INJECTION est une donnée de sécurité ---------------------
     Produit, volume, fonction rénale, allergie, réaction : c'est la pièce
     qu'on ressort le jour d'un incident. « Aucune réaction » s'ÉCRIT — un
     champ vide ne distingue pas l'absence d'incident de l'oubli. */
  var TDM_TECHNIQUE = [
    ['TDM_INJ', 'Injection de produit de contraste', 'binaire', ['sans injection', 'avec injection'], { rubrique: 'Technique et injection' }],
    ['TDM_PROD', 'Produit de contraste', 'texte', null, { rubrique: 'Technique et injection', normal: 'sans objet' }],
    ['TDM_VOL', 'Volume injecté', 'mesure', 'ml', { rubrique: 'Technique et injection' }],
    ['TDM_CREA', 'Créatininémie avant injection', 'mesure', 'mg/l', { rubrique: 'Technique et injection' }],
    ['TDM_ALL', 'Allergie connue à l’iode', 'binaire', ['non', 'oui'], { rubrique: 'Technique et injection', normal: 'non' }],
    ['TDM_REAC', 'Réaction à l’injection', 'liste', ['aucune', 'sans objet', 'réaction mineure', 'réaction sévère'], { rubrique: 'Technique et injection', normal: 'aucune' }],
    ['TDM_PDL', 'Produit dose-longueur (PDL)', 'mesure', 'mGy.cm', { rubrique: 'Technique et injection' }],
  ];
  V['IMG-TDM-CER'] = TDM_TECHNIQUE.concat([
    ['CER_PAR', 'Parenchyme cérébral', 'liste', ['densité normale', 'hypodensité ischémique', 'hyperdensité hémorragique', 'processus expansif'], { rubrique: 'Encéphale', normal: 'densité normale' }],
    ['CER_VENT', 'Système ventriculaire', 'liste', ['de taille normale', 'dilaté', 'comprimé'], { rubrique: 'Encéphale', normal: 'de taille normale' }],
    ['CER_LM', 'Ligne médiane', 'binaire', ['en place', 'déviée'], { rubrique: 'Encéphale', normal: 'en place' }],
    ['CER_EXTRA', 'Collection extra-axiale', 'binaire', SANS_AVEC, { rubrique: 'Encéphale', normal: 'absente' }],
    ['CER_FP', 'Fosse postérieure', 'liste', ['sans anomalie', 'anormale'], { rubrique: 'Encéphale', normal: 'sans anomalie' }],
    ['CER_OS', 'Voûte et base du crâne', 'liste', ['sans fracture', 'fracture'], { rubrique: 'Os', normal: 'sans fracture' }],
  ]);
  V['IMG-TDM-THO'] = TDM_TECHNIQUE.concat([
    ['TT_PAR', 'Parenchyme pulmonaire', 'liste', ['sans anomalie', 'condensation', 'verre dépoli', 'nodule(s)', 'emphysème'], { rubrique: 'Poumons', normal: 'sans anomalie' }],
    ['TT_NOD', 'Plus grand nodule', 'mesure', 'mm', { rubrique: 'Poumons' }],
    ['TT_PLEV', 'Épanchement pleural', 'liste', ['absent', 'droit', 'gauche', 'bilatéral'], { rubrique: 'Plèvre et médiastin', normal: 'absent' }],
    ['TT_MED', 'Adénopathies médiastinales', 'binaire', ['absentes', 'présentes'], { rubrique: 'Plèvre et médiastin', normal: 'absentes' }],
    ['TT_EP', 'Embolie pulmonaire (si angioscanner)', 'liste', ['sans objet', 'absente', 'présente'], { rubrique: 'Plèvre et médiastin', normal: 'sans objet' }],
  ]);
  V['IMG-TDM-ABP'] = TDM_TECHNIQUE.concat([
    ['TA_FOIE', 'Foie', 'liste', ['taille et densité normales', 'hépatomégalie', 'lésion focale'], { rubrique: 'Abdomen', normal: 'taille et densité normales' }],
    ['TA_RATE', 'Rate et pancréas', 'liste', ['sans anomalie', 'splénomégalie', 'anomalie pancréatique'], { rubrique: 'Abdomen', normal: 'sans anomalie' }],
    ['TA_REINS', 'Reins et voies excrétrices', 'liste', ['sans anomalie', 'dilatation', 'lithiase', 'masse rénale'], { rubrique: 'Abdomen', normal: 'sans anomalie' }],
    ['TA_EPAN', 'Épanchement intra-péritonéal', 'binaire', ['absent', 'présent'], { rubrique: 'Abdomen', normal: 'absent' }],
    ['TA_GG', 'Adénopathies profondes', 'binaire', ['absentes', 'présentes'], { rubrique: 'Pelvis et ganglions', normal: 'absentes' }],
    ['TA_PELV', 'Organes pelviens', 'liste', ['sans anomalie', 'masse pelvienne', 'épaississement vésical'], { rubrique: 'Pelvis et ganglions', normal: 'sans anomalie' }],
  ]);
  V['IMG-TDM-RAC'] = TDM_TECHNIQUE.concat([
    ['TR_SEG', 'Segment exploré', 'liste', ['cervical', 'dorsal', 'lombaire', 'lombo-sacré'], { rubrique: 'Rachis' }],
    ['TR_FRACT', 'Fracture', 'binaire', SANS_AVEC, { rubrique: 'Rachis', normal: 'absente' }],
    ['TR_HERN', 'Hernie discale', 'liste', ['absente', 'protrusion', 'hernie médiane', 'hernie postéro-latérale'], { rubrique: 'Rachis', normal: 'absente' }],
    ['TR_CANAL', 'Canal rachidien', 'liste', ['de calibre normal', 'rétréci'], { rubrique: 'Rachis', normal: 'de calibre normal' }],
  ]);

  /* --- IRM : les séquences et la sécurité magnétique ------------------------
     Les contre-indications se vérifient AVANT d'entrer dans la salle : un
     pacemaker ou un clip métallique ne s'apprend pas après l'examen. */
  var IRM_TECHNIQUE = [
    ['IRM_CI', 'Contre-indications vérifiées', 'liste', ['vérifiées — aucune', 'pacemaker', 'clip ou implant métallique', 'claustrophobie', 'grossesse'], { rubrique: 'Sécurité et technique', normal: 'vérifiées — aucune' }],
    ['IRM_SEQ', 'Séquences réalisées', 'multiple', ['T1', 'T2', 'FLAIR', 'Diffusion', 'T2*', 'STIR', 'T1 après gadolinium'], { rubrique: 'Sécurité et technique' }],
    ['IRM_GADO', 'Injection de gadolinium', 'binaire', ['sans gadolinium', 'avec gadolinium'], { rubrique: 'Sécurité et technique' }],
    ['IRM_CREA', 'Créatininémie avant injection', 'mesure', 'mg/l', { rubrique: 'Sécurité et technique' }],
  ];
  V['IMG-IRM-CER'] = IRM_TECHNIQUE.concat([
    ['IC_SB', 'Substance blanche', 'liste', ['signal normal', 'hypersignaux T2/FLAIR'], { rubrique: 'Encéphale', normal: 'signal normal' }],
    ['IC_DIFF', 'Restriction de diffusion', 'binaire', ['absente', 'présente'], { rubrique: 'Encéphale', normal: 'absente' }],
    ['IC_LES', 'Lésion focale', 'binaire', SANS_AVEC, { rubrique: 'Encéphale', normal: 'absente' }],
    ['IC_TAILLE', 'Taille de la lésion', 'mesure', 'mm', { rubrique: 'Encéphale' }],
    ['IC_VENT', 'Système ventriculaire', 'liste', ['de taille normale', 'dilaté'], { rubrique: 'Encéphale', normal: 'de taille normale' }],
  ]);
  V['IMG-IRM-RAC'] = IRM_TECHNIQUE.concat([
    ['IR_NIV', 'Niveau atteint', 'multiple', ['L1-L2', 'L2-L3', 'L3-L4', 'L4-L5', 'L5-S1'], { rubrique: 'Disques et canal' }],
    ['IR_HERN', 'Hernie discale', 'liste', ['absente', 'protrusion', 'hernie médiane', 'hernie postéro-latérale', 'hernie foraminale'], { rubrique: 'Disques et canal', normal: 'absente' }],
    ['IR_CONF', 'Conflit disco-radiculaire', 'binaire', ['absent', 'présent'], { rubrique: 'Disques et canal', normal: 'absent' }],
    ['IR_CANAL', 'Canal lombaire', 'liste', ['de calibre normal', 'sténose modérée', 'sténose serrée'], { rubrique: 'Disques et canal', normal: 'de calibre normal' }],
    ['IR_OS', 'Signal osseux vertébral', 'liste', ['normal', 'Modic 1', 'Modic 2', 'lésion suspecte'], { rubrique: 'Vertèbres', normal: 'normal' }],
  ]);
  V['IMG-IRM-GEN'] = IRM_TECHNIQUE.concat([
    ['IG_COTE', 'Côté', 'binaire', ['droit', 'gauche'], { rubrique: 'Genou' }],
    ['IG_MI', 'Ménisque interne', 'liste', ['intact', 'dégénératif', 'fissure', 'anse de seau'], { rubrique: 'Ménisques', normal: 'intact' }],
    ['IG_ME', 'Ménisque externe', 'liste', ['intact', 'dégénératif', 'fissure', 'anse de seau'], { rubrique: 'Ménisques', normal: 'intact' }],
    ['IG_LCA', 'Ligament croisé antérieur', 'liste', ['continu', 'rupture partielle', 'rupture complète'], { rubrique: 'Ligaments', normal: 'continu' }],
    ['IG_LCP', 'Ligament croisé postérieur', 'liste', ['continu', 'rupture partielle', 'rupture complète'], { rubrique: 'Ligaments', normal: 'continu' }],
    ['IG_EPAN', 'Épanchement articulaire', 'liste', ['absent', 'de faible abondance', 'abondant'], { rubrique: 'Articulation', normal: 'absent' }],
    ['IG_CART', 'Cartilage', 'liste', ['normal', 'chondropathie'], { rubrique: 'Articulation', normal: 'normal' }],
  ]);
  V['IMG-IRM-PEL'] = IRM_TECHNIQUE.concat([
    ['IP_UT', 'Utérus', 'liste', ['taille et signal normaux', 'myome(s)', 'adénomyose', 'masse'], { rubrique: 'Pelvis', normal: 'taille et signal normaux' }],
    ['IP_ENDO', 'Épaisseur de l’endomètre', 'mesure', 'mm', { rubrique: 'Pelvis' }],
    ['IP_OV', 'Ovaires', 'liste', ['normaux', 'kyste fonctionnel', 'kyste complexe', 'masse'], { rubrique: 'Pelvis', normal: 'normaux' }],
    ['IP_EPAN', 'Épanchement du cul-de-sac', 'binaire', ['absent', 'présent'], { rubrique: 'Pelvis', normal: 'absent' }],
    ['IP_GG', 'Adénopathies pelviennes', 'binaire', ['absentes', 'présentes'], { rubrique: 'Ganglions', normal: 'absentes' }],
  ]);

  /* --------------------------------------------------------------------------
   * MISE EN FORME
   * ---------------------------------------------------------------------- */
  var VARIABLES = [];
  Object.keys(V).forEach(function (code) {
    V[code].forEach(function (v, i) {
      var o = v[4] || {};
      VARIABLES.push({
        examen: code, code: v[0], libelle: v[1], type: v[2],
        options: Array.isArray(v[3]) ? v[3] : null,
        unite: Array.isArray(v[3]) ? null : v[3],
        rubrique: o.rubrique || 'Résultat',
        normal: o.normal || null,
        conditionnels: o.conditionnels || null,
        repete: o.repete || null,
        ordre: i + 1,
      });
    });
  });

  /* ==========================================================================
   * LA PASSE « AUTRE » — UNE RÈGLE, PAS SOIXANTE RETOUCHES (21/09/2026)
   * --------------------------------------------------------------------------
   * Toute liste de choix d'une modalité qui porte `autreSystematique` reçoit
   * l'option « Autre » et le champ de précision qui va avec. Trois bornes,
   * chacune pour une raison :
   *
   *   - SEULES LES LISTES (`liste`). Une variable `binaire` pose une question
   *     fermée — « fracture : absente / présente » : lui ajouter « Autre »
   *     n'ouvrirait aucun cas réel et ferait douter de la question.
   *   - JAMAIS DEUX FOIS. Une liste où « Autre » figure déjà est laissée
   *     intacte : c'est une valeur posée À LA MAIN, avec son propre champ de
   *     précision et son libellé — le doubler créerait deux « Autre » dans la
   *     même liste, dont un sans effet.
   *   - L'ÉCHOGRAPHIE EN EST EXCLUE. Ses listes viennent du brouillon
   *     manuscrit de l'échographiste, qui a placé « Autre » là où il le veut
   *     et nulle part ailleurs. L'ajouter partout contredirait une demande
   *     écrite — exactement ce que ce fichier interdit depuis l'origine.
   * ======================================================================== */
  var MODALITE_PAR_EXAMEN = {};
  EXAMENS.forEach(function (e) { MODALITE_PAR_EXAMEN[e.code] = e.modalite || 'echographie'; });
  var AUTRE_SYSTEMATIQUE = {};
  MODALITES.forEach(function (m) { if (m.autreSystematique) AUTRE_SYSTEMATIQUE[m.code] = true; });
  VARIABLES.forEach(function (v) {
    if (!AUTRE_SYSTEMATIQUE[MODALITE_PAR_EXAMEN[v.examen]]) return;
    if (v.type !== 'liste' || !Array.isArray(v.options)) return;
    var deja = v.options.some(function (o) { return String(o).toLowerCase() === 'autre'; });
    if (deja) return;
    v.options = v.options.concat(['Autre']);
    v.conditionnels = (v.conditionnels || []).concat([
      precision(AUTRE, v.code + '_AUTRE', v.libelle + ' — préciser'),
    ]);
  });

  /* --------------------------------------------------------------------------
   * LES DEUX RUBRIQUES QUI RESTENT LIBRES
   * ------------------------------------------------------------------------
   * Demande textuelle de l'échographiste, portée sur son brouillon : « Annexes
   * — à remplir par moi-même », puis « Conclusion ». Les fermer dans un
   * formulaire à cases irait contre une instruction écrite de sa main.
   * ---------------------------------------------------------------------- */
  /* « Annexes » a été retirée le 14/09/2026 — voir la modalité. Les comptes
     rendus antérieurs qui la portent l'affichent encore, marquée comme saisie
     antérieure : on ne fait pas disparaître ce qui a été écrit. */
  var RUBRIQUES_LIBRES = [
    { code: 'conclusion', label: 'Conclusion', note: 'Rédigée par l’échographiste. Reprise telle quelle sur le compte rendu.', requis: true },
  ];

  function variablesDe(codeExamen) {
    return VARIABLES.filter(function (v) { return v.examen === codeExamen; })
      .sort(function (a, b) { return a.ordre - b.ordre; });
  }

  function rubriquesDe(codeExamen) {
    var vus = {}, out = [];
    variablesDe(codeExamen).forEach(function (v) {
      if (vus[v.rubrique]) return;
      vus[v.rubrique] = true; out.push(v.rubrique);
    });
    return out;
  }

  function examen(code) {
    return EXAMENS.filter(function (x) { return x.code === code; })[0] || null;
  }

  /* Une valeur s'écarte-t-elle de la normale déclarée ? Le compte rendu réel
     met en gras ce qui sort de la norme — c'est cette mise en évidence que le
     clinicien lit en premier. */
  function ecart(variable, valeur) {
    if (!variable || !variable.normal || valeur == null || valeur === '' || Array.isArray(valeur)) return false;
    return String(valeur) !== String(variable.normal);
  }

  function modalite(code) {
    return MODALITES.filter(function (m) { return m.code === code; })[0] || null;
  }
  /* La modalité d'un examen. Un examen sans modalité déclarée — ajouté au
     catalogue avant la vague 61 — reste à l'échographie, où il était saisi. */
  function modaliteDeExamen(ex) {
    return (ex && ex.modalite) || 'echographie';
  }

  D.IMAGERIE = {
    TYPES: TYPES,
    MODALITES: MODALITES,
    EXAMENS: EXAMENS,
    VARIABLES: VARIABLES,
    RUBRIQUES_LIBRES: RUBRIQUES_LIBRES,
    PROPOSITION: PROPOSITION,
    variablesDe: variablesDe,
    rubriquesDe: rubriquesDe,
    examen: examen,
    ecart: ecart,
    modalite: modalite,
    modaliteDeExamen: modaliteDeExamen,
  };
})(window);
