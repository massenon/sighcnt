/* ==========================================================================
 * CIRCUIT CLINIQUE — PRESCRIPTEURS, EXÉCUTANTS, BLOC ET MATERNITÉ
 * --------------------------------------------------------------------------
 * Source : entretien de Direction du 24/08/2026.
 *
 * CE QUE CE FICHIER TRANCHE, et qui n'existait nulle part :
 *
 * 1. UNE PRESCRIPTION N'EST PAS TOUJOURS UNE ORDONNANCE. La clinique en
 *    distingue DEUX : la prescription d'ORDONNANCE (des médicaments à
 *    délivrer) et la prescription de SOINS (des actes à exécuter). Les
 *    confondre rendait invisible tout le travail infirmier : un pansement
 *    prescrit n'est pas un médicament, il ne sort pas du stock, il ne se
 *    délivre pas au comptoir — il s'exécute, par quelqu'un, quelque part.
 *
 * 2. UNE PRESCRIPTION A QUATRE ORIGINES : consultation, hospitalisation,
 *    bloc et maternité. Le prototype ne connaissait que la consultation.
 *
 * 3. QUI PRESCRIT N'EST PAS QUI EXÉCUTE, et la sage-femme est aux deux.
 *    Prescripteurs : 3 médecins et 3 sages-femmes. Exécutants des soins :
 *    7 infirmiers et les 3 mêmes sages-femmes.
 *
 * 4. L'ADMINISTRATION D'UN TRAITEMENT SUIT UNE RÈGLE DE RELAIS, et c'est le
 *    point le plus fin de tout le circuit :
 *      - traitement AMBULATOIRE  → salle de soins, toujours, pour toutes les
 *        administrations ;
 *      - traitement en HOSPITALISATION → la PREMIÈRE administration revient à
 *        la salle de soins, les SUIVANTES à l'hospitalisation.
 *    Écrire « le service administre » aurait perdu ce relais, qui est
 *    précisément ce que la Direction a pris la peine de décrire.
 *
 * Les effectifs (3 / 3 / 7) sont ceux énoncés par la Direction. Ils
 * s'administrent depuis l'écran des soignants : la Direction a demandé
 * expressément que l'administrateur puisse ajouter et modifier.
 * ======================================================================== */
(function (global) {
  'use strict';

  var D = global.SIGH.data;

  /* ==========================================================================
   * QUALITÉS SOIGNANTES
   * ------------------------------------------------------------------------
   * `prescrit` et `execute` sont deux droits distincts portés par la même
   * fiche. La sage-femme les cumule — c'est le fait métier qui interdisait de
   * modéliser « prescripteur » et « exécutant » comme deux listes séparées.
   * ======================================================================== */
  var QUALITES = [
    {
      code: 'medecin', label: 'Médecin', pluriel: 'Médecins',
      prescrit: true, execute: false, icone: 'stethoscope',
      note: 'Prescrit ordonnances et soins, dans tous les secteurs.',
    },
    {
      code: 'sage_femme', label: 'Sage-femme', pluriel: 'Sages-femmes',
      prescrit: true, execute: true, icone: 'baby',
      note: 'Prescrit ET exécute. Seule qualité à cumuler les deux.',
    },
    {
      code: 'infirmier', label: 'Infirmier', pluriel: 'Infirmiers',
      prescrit: false, execute: true, icone: 'heart-pulse',
      note: 'Exécute les soins prescrits ; ne prescrit pas.',
    },
  ];

  /* ==========================================================================
   * TYPES DE PRESCRIPTION
   * ======================================================================== */
  var TYPES_PRESCRIPTION = [
    {
      code: 'ordonnance', label: 'Prescription d’ordonnance', icone: 'scroll-text',
      aval: 'Pharmacie — délivrance sur stock, puis administration',
      note: 'Des médicaments à délivrer. Consomme le stock (RG-03).',
    },
    {
      code: 'soins', label: 'Prescription de soins', icone: 'hand-heart',
      aval: 'Salle de soins, hospitalisation ou maternité — exécution',
      note: 'Des actes à exécuter. Ne consomme pas le stock ; se facture au catalogue AMI.',
    },
  ];

  /* ==========================================================================
   * ORIGINES DE PRESCRIPTION — les quatre points où l'on prescrit
   * ======================================================================== */
  var ORIGINES_PRESCRIPTION = [
    { code: 'consultation', label: 'Consultation', module: 'M2', icone: 'stethoscope' },
    { code: 'hospitalisation', label: 'Hospitalisation', module: 'M3', icone: 'bed-double' },
    { code: 'bloc', label: 'Bloc opératoire', module: 'M3', icone: 'scissors' },
    { code: 'maternite', label: 'Maternité', module: 'M4', icone: 'baby' },
  ];

  /* ==========================================================================
   * SECTEURS D'EXÉCUTION DES SOINS
   * ------------------------------------------------------------------------
   * Une prescription de soins est ADRESSÉE à un secteur. Sans destinataire,
   * elle n'apparaîtrait sur aucun poste et ne serait jamais exécutée.
   * ======================================================================== */
  var SECTEURS_SOINS = [
    { code: 'salle_soins', label: 'Salle de soins', icone: 'syringe' },
    { code: 'hospitalisation', label: 'Hospitalisation', icone: 'bed-double' },
    { code: 'maternite', label: 'Maternité', icone: 'baby' },
  ];

  /* ==========================================================================
   * MODALITÉS DE TRAITEMENT — d'où découle la règle de relais
   * ======================================================================== */
  var MODALITES_TRAITEMENT = [
    {
      code: 'ambulatoire', label: 'Ambulatoire',
      regle: 'Administré par la SALLE DE SOINS seule, du premier au dernier passage.',
    },
    {
      code: 'hospitalisation', label: 'En hospitalisation',
      regle: 'PREMIÈRE administration par la salle de soins ; les SUIVANTES par l’hospitalisation.',
    },
  ];

  /* --------------------------------------------------------------------------
   * LA RÈGLE DE RELAIS, écrite une seule fois
   * ------------------------------------------------------------------------
   * Elle vit ici, et non dans l'écran qui l'affiche, parce que trois écrans la
   * consultent : la salle de soins pour savoir ce qui lui revient,
   * l'hospitalisation pour savoir ce qui lui revient, et le registre des
   * prescriptions pour dire à l'avance qui fera quoi.
   *
   * `rang` est le numéro de l'administration à venir, à partir de 1.
   * ---------------------------------------------------------------------- */
  function secteurAdministrateur(modalite, rang) {
    if (modalite === 'ambulatoire') {
      return {
        secteur: 'salle_soins',
        motif: 'Traitement ambulatoire : toutes les administrations reviennent à la salle de soins.',
      };
    }
    if (rang <= 1) {
      return {
        secteur: 'salle_soins',
        motif: 'Première administration d’un traitement hospitalier : elle revient à la salle de soins.',
      };
    }
    return {
      secteur: 'hospitalisation',
      motif: 'Administration n° ' + rang + ' : le relais est passé à l’hospitalisation.',
    };
  }

  /* ==========================================================================
   * BLOC OPÉRATOIRE — COMPTE RENDU OPÉRATOIRE
   * ------------------------------------------------------------------------
   * Les huit rubriques dictées par la Direction, dans son ordre. Le NIP figure
   * séparément de l'identité : c'est le numéro que porte le dossier papier et
   * il est recopié tel quel sur la pièce.
   *
   * Trois intervenants NOMMÉS : opérateur, aide-opérateur, anesthésiste. Un
   * compte rendu opératoire sans ses opérateurs n'a aucune valeur de preuve —
   * c'est la pièce qu'on ressort quand une suite opératoire est contestée.
   * ======================================================================== */
  var RUBRIQUES_CRO = [
    { code: 'patient', label: 'Identité du patient', type: 'patient', requis: true },
    { code: 'nip', label: 'NIP', type: 'texte', requis: true, note: 'Recopié du dossier.' },
    { code: 'diagnosticPeroperatoire', label: 'Diagnostic peropératoire', type: 'zone', requis: true },
    { code: 'intervention', label: 'Intervention chirurgicale', type: 'zone', requis: true },
    { code: 'anesthesie', label: 'Anesthésie', type: 'zone', requis: true },
    { code: 'cro', label: 'Compte rendu opératoire proprement dit', type: 'zone', requis: true, lignes: 10 },
    { code: 'operateurId', label: 'Opérateur', type: 'soignant', requis: true },
    { code: 'aideOperateurId', label: 'Aide-opérateur', type: 'soignant', requis: false },
    { code: 'anesthesisteId', label: 'Anesthésiste', type: 'soignant', requis: true },
  ];

  /* ==========================================================================
   * CHECK-LISTES DU BLOC — AVANT (IN) ET APRÈS (OUT)
   * ------------------------------------------------------------------------
   * Deux listes distinctes, à deux moments distincts. Les fondre en une seule
   * ferait cocher après l'intervention ce qui devait l'être avant — ce qui
   * vide l'exercice de tout sens.
   *
   * Le contenu suit la pratique courante de sécurité au bloc. Il est marqué
   * `aValider` : la clinique n'a pas remis de check-liste écrite, ces items
   * sont donc une PROPOSITION, administrable, et les écrans le disent.
   * ======================================================================== */
  var CHECKLIST_IN = [
    'Identité du patient confirmée par le patient lui-même',
    'Intervention et site opératoire confirmés',
    'Consentement opératoire signé et présent au dossier',
    'Site opératoire marqué',
    'Jeûne préopératoire respecté',
    'Allergies connues vérifiées et signalées à l’équipe',
    'Voie veineuse posée et perméable',
    'Groupe sanguin et rhésus disponibles au dossier',
    'Matériel d’anesthésie vérifié et fonctionnel',
    'Risque hémorragique évalué',
    'Antibioprophylaxie administrée si indiquée',
    'Équipe au complet, chacun s’étant présenté par son nom et sa fonction',
  ];

  var CHECKLIST_OUT = [
    'Nature de l’intervention réellement pratiquée énoncée à voix haute',
    'Comptage des compresses, aiguilles et instruments exact',
    'Étiquetage des prélèvements vérifié (nom du patient, nature)',
    'Incidents ou difficultés per-opératoires signalés et consignés',
    'Drains et sondes en place recensés',
    'Prescriptions post-opératoires rédigées',
    'Surveillance post-opératoire prescrite et transmise au service',
    'Compte rendu opératoire rédigé et signé',
    'Dysfonctionnement matériel éventuel signalé',
  ];

  /* ==========================================================================
   * MATERNITÉ — TROIS COMPTES RENDUS
   * ------------------------------------------------------------------------
   * La maternité produit trois pièces que rien ne portait jusqu'ici. Chacune a
   * ses rubriques propres : les regrouper sous un « compte rendu » unique
   * aurait forcé la sage-femme à remplir des champs sans objet.
   * ======================================================================== */
  var COMPTES_RENDUS_MATERNITE = [
    {
      code: 'accouchement', label: 'Compte rendu d’accouchement', icone: 'baby',
      acteCode: 'ACCE',
      rubriques: [
        ['dateHeure', 'Date et heure de l’accouchement', 'datetime', true],
        ['termeSA', 'Terme (semaines d’aménorrhée)', 'nombre', true],
        ['presentation', 'Présentation', 'liste', true, ['Céphalique', 'Siège', 'Transverse', 'Autre']],
        ['voie', 'Voie d’accouchement', 'liste', true, ['Voie basse eutocique', 'Voie basse dystocique', 'Césarienne']],
        ['travailDuree', 'Durée du travail (heures)', 'nombre', false],
        ['delivrance', 'Délivrance', 'liste', true, ['Spontanée et complète', 'Dirigée', 'Artificielle', 'Révision utérine']],
        ['episiotomie', 'Épisiotomie', 'binaire', false],
        ['dechirure', 'Déchirure périnéale', 'liste', false, ['Aucune', 'Degré 1', 'Degré 2', 'Degré 3', 'Degré 4']],
        ['pertesSanguines', 'Pertes sanguines estimées (ml)', 'nombre', false],
        ['sexeEnfant', 'Sexe de l’enfant', 'liste', true, ['Masculin', 'Féminin']],
        ['poidsEnfant', 'Poids de l’enfant (g)', 'nombre', true],
        ['apgar1', 'Apgar à 1 minute', 'nombre', false],
        ['apgar5', 'Apgar à 5 minutes', 'nombre', false],
        ['etatMere', 'État de la mère à l’issue', 'zone', true],
        ['observations', 'Observations', 'zone', false],
      ],
    },
    {
      code: 'planning_familial', label: 'Compte rendu de planning familial', icone: 'calendar-heart',
      acteCode: null,
      rubriques: [
        ['dateActe', 'Date de l’acte', 'date', true],
        ['methode', 'Méthode', 'liste', true,
          ['Implant', 'DIU / stérilet', 'Injectable Noristerat / Laafia', 'Injectable Sayana Press', 'Pilule', 'Préservatif', 'Autre']],
        ['geste', 'Geste', 'liste', true, ['Pose', 'Retrait', 'Renouvellement', 'Conseil seul']],
        ['counseling', 'Counseling délivré', 'binaire', true],
        ['effetsSecondaires', 'Effets secondaires expliqués', 'binaire', true],
        ['prochainRdv', 'Prochain rendez-vous', 'date', false],
        ['observations', 'Observations', 'zone', false],
      ],
      note: 'Les actes de planification familiale sont TOUS non couverts par les assurances (grille gynéco-obstétricale).',
    },
    {
      code: 'amiu', label: 'Compte rendu d’AMIU', icone: 'activity',
      acteCode: 'AMIU',
      rubriques: [
        ['dateHeure', 'Date et heure', 'datetime', true],
        ['indication', 'Indication', 'zone', true],
        ['termeSA', 'Terme au moment du geste (SA)', 'nombre', false],
        ['anesthesie', 'Anesthésie / analgésie', 'zone', false],
        ['deroulement', 'Déroulement du geste', 'zone', true],
        ['produitAspire', 'Produit aspiré', 'zone', false],
        ['complications', 'Complications', 'zone', false],
        ['suites', 'Suites et conduite à tenir', 'zone', true],
        ['operateurId', 'Opérateur', 'soignant', true],
      ],
    },
  ];

  /* ==========================================================================
   * L'ÉQUIPE SOIGNANTE — effectifs énoncés par la Direction
   * ------------------------------------------------------------------------
   * Les noms sont rapprochés de l'organigramme quand celui-ci les porte ; les
   * autres sont des postes numérotés, à nommer par l'administrateur. Ce qui
   * est documenté, ce sont les EFFECTIFS : 3 médecins, 3 sages-femmes,
   * 7 infirmiers. Inventer six patronymes serait ajouter du faux à du vrai.
   * ======================================================================== */
  var EQUIPE = {
    medecin: 3,
    sage_femme: 3,
    infirmier: 7,
  };

  D.QUALITES_SOIGNANT = QUALITES;
  D.TYPES_PRESCRIPTION = TYPES_PRESCRIPTION;
  D.ORIGINES_PRESCRIPTION = ORIGINES_PRESCRIPTION;
  D.SECTEURS_SOINS = SECTEURS_SOINS;
  D.MODALITES_TRAITEMENT = MODALITES_TRAITEMENT;
  D.secteurAdministrateur = secteurAdministrateur;
  D.RUBRIQUES_CRO = RUBRIQUES_CRO;
  /* Proposées faute de document remis, puis ARRÊTÉES par les praticiens
     du bloc le 01/09/2026 (validation écrite — vague 51). */
  D.CHECKLIST_BLOC = { entree: CHECKLIST_IN, sortie: CHECKLIST_OUT,
    aValider: false, arreteLe: '2026-09-01', arretePar: 'Praticiens du bloc' };
  D.COMPTES_RENDUS_MATERNITE = COMPTES_RENDUS_MATERNITE;
  D.EFFECTIF_SOIGNANT = EQUIPE;
})(window);
