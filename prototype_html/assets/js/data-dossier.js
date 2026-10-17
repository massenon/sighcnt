/* ==========================================================================
 * LE DOSSIER PATIENT ÉTENDU — DEUX ZONES, DEUX RESPONSABILITÉS
 * --------------------------------------------------------------------------
 * Structure dictée par la Direction le 25/08/2026.
 *
 * LA COUPURE EN DEUX ZONES N'EST PAS UNE COMMODITÉ D'AFFICHAGE : c'est une
 * frontière de responsabilité.
 *
 *   ZONE 1 — ACCUEIL : identification, coordonnées, couverture, constantes.
 *     L'accueil remplit, et il ne voit rien d'autre (RG-13).
 *   ZONE 2 — CONSULTATION : historique, antécédents, examen physique,
 *     décisions. Le soignant remplit ; l'accueil n'y accède pas.
 *
 * Mêler les deux ferait qu'un secrétaire médical lirait un diagnostic en
 * cherchant un numéro de téléphone.
 *
 * LES ANTÉCÉDENTS SONT EN TROIS CATÉGORIES STRICTES, et la Direction a insisté
 * sur « strictes » : un antécédent chirurgical rangé dans les médicaux se perd
 * au moment où le chirurgien en a besoin — c'est-à-dire avant d'ouvrir.
 *
 * L'EXAMEN PHYSIQUE SUIT LES QUATRE TEMPS CLASSIQUES — inspection, palpation,
 * percussion, auscultation — dans cet ordre. Un champ unique « examen » laisse
 * l'interne écrire trois lignes et oublier la percussion ; quatre champs
 * rappellent ce qui n'a pas été fait.
 * ======================================================================== */
(function (global) {
  'use strict';

  var D = global.SIGH.data;

  /* --------------------------------------------------------------------------
   * LES TROIS CATÉGORIES D'ANTÉCÉDENTS
   * ------------------------------------------------------------------------ */
  var CATEGORIES_ANTECEDENT = [
    {
      code: 'medicaux', label: 'Antécédents médicaux', icone: 'stethoscope',
      note: 'Maladies chroniques, affections traitées, allergies, traitements au long cours.',
      exemples: ['Hypertension artérielle', 'Diabète', 'Drépanocytose', 'Asthme',
        'Épilepsie', 'Tuberculose traitée', 'Hépatite B', 'Insuffisance rénale',
        'Ulcère gastro-duodénal', 'Allergie médicamenteuse'],
    },
    {
      code: 'chirurgicaux', label: 'Antécédents chirurgicaux', icone: 'scissors',
      note: 'Toute intervention subie, avec sa date et son indication. C’est la première '
        + 'chose que le chirurgien cherche avant d’ouvrir.',
      exemples: ['Appendicectomie', 'Césarienne', 'Herniorraphie', 'Cholécystectomie',
        'Hystérectomie', 'Ostéosynthèse', 'Amygdalectomie', 'Laparotomie exploratrice'],
    },
    {
      code: 'gyneco_obstetricaux', label: 'Antécédents gynéco-obstétricaux', icone: 'baby',
      note: 'Gestité, parité, avortements, enfants vivants, contraception, ménarche, DDR.',
      exemples: ['Gestité', 'Parité', 'Avortements', 'Enfants vivants',
        'Contraception en cours', 'Âge des premières règles', 'Date des dernières règles',
        'Accouchement dystocique antérieur'],
    },
  ];

  /* --------------------------------------------------------------------------
   * L'EXAMEN PHYSIQUE — QUATRE TEMPS, DANS L'ORDRE
   * ------------------------------------------------------------------------ */
  var TEMPS_EXAMEN = [
    { code: 'inspection', label: 'Inspection', ordre: 1,
      note: 'Ce que l’on voit : état général, coloration, morphologie, cicatrices, déformations.' },
    { code: 'palpation', label: 'Palpation', ordre: 2,
      note: 'Ce que l’on sent : masses, défense, douleur provoquée, adénopathies, organomégalie.' },
    { code: 'percussion', label: 'Percussion', ordre: 3,
      note: 'Ce que l’on entend en percutant : matité, tympanisme, sonorité.' },
    { code: 'auscultation', label: 'Auscultation', ordre: 4,
      note: 'Ce que l’on entend au stéthoscope : bruits du cœur, murmure vésiculaire, râles, souffles.' },
  ];

  /* --------------------------------------------------------------------------
   * LE CYCLE DE VIE DU DOSSIER DE CONSULTATION
   * ------------------------------------------------------------------------
   * Quatre états, dictés par la Direction. L'ordre importe : un dossier ne
   * saute pas de l'attente à la clôture — s'il le pouvait, on clôturerait des
   * consultations qui n'ont jamais eu lieu.
   *
   * « EN ATTENTE LABO » n'est pas un état de garage : c'est celui où le
   * clinicien a prescrit et attend, et c'est lui qui permet de compter les
   * dossiers suspendus à un résultat.
   * ---------------------------------------------------------------------- */
  var ETATS_DOSSIER = [
    { code: 'attente', label: 'EN ATTENTE', couleur: 'neutral', ordre: 1,
      note: 'Le patient est enregistré et attend d’être reçu.',
      suivants: ['consultation'] },
    { code: 'consultation', label: 'EN CONSULTATION', couleur: 'info', ordre: 2,
      note: 'Le soignant a pris le patient en charge.',
      suivants: ['attente_labo', 'cloture'] },
    { code: 'attente_labo', label: 'EN ATTENTE LABO', couleur: 'warning', ordre: 3,
      note: 'Des examens ont été prescrits ; la décision attend leurs résultats.',
      suivants: ['consultation', 'cloture'] },
    { code: 'cloture', label: 'CLÔTURÉ', couleur: 'success', ordre: 4,
      note: 'La consultation est terminée et le dossier arrêté.',
      suivants: [] },
  ];

  function etatDossier(code) {
    return ETATS_DOSSIER.filter(function (e) { return e.code === code; })[0] || ETATS_DOSSIER[0];
  }

  /* Une transition est-elle permise ? Refuser les sauts n'est pas une rigidité
     d'école : clôturer un dossier resté « en attente » signerait une
     consultation qui n'a pas eu lieu. */
  function transitionPermise(de, vers) {
    var e = etatDossier(de);
    return e.suivants.indexOf(vers) !== -1;
  }

  /* --------------------------------------------------------------------------
   * CE QUE LE CHIRURGIEN SEUL PEUT ÉCRIRE
   * ------------------------------------------------------------------------
   * Condition posée par la Direction : « Actes Chirurgicaux & Bloc = chirurgien
   * seulement ». Le généraliste tient tout le reste du dossier.
   *
   * La règle porte sur l'ÉCRITURE, pas sur la lecture : le généraliste doit
   * pouvoir lire ce que le chirurgien a écrit — c'est son patient aussi.
   * ---------------------------------------------------------------------- */
  var RUBRIQUES_CHIRURGICALES = ['actesChirurgicaux', 'indicationOperatoire', 'blocPrevu', 'risqueOperatoire'];

  function peutEcrireRubrique(rubrique, capacite) {
    if (RUBRIQUES_CHIRURGICALES.indexOf(rubrique) === -1) return { ok: true };
    if (capacite === 'chirurgien') return { ok: true };
    return {
      ok: false,
      motif: 'Les actes chirurgicaux et la programmation du bloc ne sont renseignés que par le '
        + 'chirurgien. Un généraliste peut les LIRE — c’est son patient aussi — mais non les écrire.',
    };
  }

  /* --------------------------------------------------------------------------
   * L'EXAMEN PHYSIQUE PAR APPAREIL — MÉTHODE IPPOA (refonte Zone 2, 14/09/2026)
   * ------------------------------------------------------------------------
   * La METHODOLOGIE remise par la Direction remplace l'examen « global » en
   * quatre champs par un examen ORIENTÉ : chaque appareil porte ses quatre
   * temps (plus la menstruation là où elle a un sens). Le médecin ne déplie
   * que les appareils pertinents pour le motif ; un bouton « Normal par
   * défaut » pose « RAS » dans les champs restés vides.
   *
   * L'examen se range en UN objet JSON par dossier
   * (`examensPhysiques: { cardio_vasculaire: { inspection, … }, … }`) : une
   * colonne par appareil et par temps ferait trente-six champs vides sur
   * chaque fiche, et ajouter un appareil obligerait à changer la forme de la
   * collection. Ici, un appareil ajouté au référentiel paraît au formulaire
   * suivant sans rien d'autre à toucher.
   *
   * Les aides de saisie (« turgescence jugulaire, œdèmes… ») reprennent le
   * texte de la METHODOLOGIE ; elles guident, elles ne remplissent rien.
   * ---------------------------------------------------------------------- */
  var APPAREILS_EXAMEN = [
    { code: 'cardio_vasculaire', label: 'Appareil cardio-vasculaire', icone: 'heart-pulse',
      aides: { inspection: 'Turgescence jugulaire, œdèmes, cyanose…', palpation: 'Choc de pointe, pouls périphériques…',
        percussion: 'Limites cardiaques…', auscultation: 'Bruits du cœur, souffles…' } },
    { code: 'pleuro_pulmonaire', label: 'Appareil pleuro-pulmonaire', icone: 'wind',
      aides: { inspection: 'Type respiratoire, ampliation thoracique…', palpation: 'Vibrations vocales…',
        percussion: 'Sonorité pulmonaire, matité…', auscultation: 'Murmure vésiculaire, râles, sifflements…' } },
    { code: 'hepato_gastro_digestif', label: 'Hépato-gastro-digestif', icone: 'soup',
      aides: { inspection: 'Morphologie abdominale, cicatrices, circulation collatérale…', palpation: 'Souplesse, défense, masse, hépatomégalie…',
        percussion: 'Tympanisme, matité déclive…', auscultation: 'Bruits hydro-aériques…' } },
    { code: 'genito_urinaire', label: 'Génito-urinaire', icone: 'droplets', menstruation: true,
      aides: { inspection: 'Organes génitaux externes, écoulement…', palpation: 'Fosses lombaires, contact lombaire…',
        percussion: 'Globe vésical…', auscultation: '—' } },
    { code: 'locomoteur', label: 'Appareil locomoteur', icone: 'bone',
      aides: { inspection: 'Déformation, tuméfaction, attitude antalgique…', palpation: 'Douleur provoquée, mobilité articulaire…',
        percussion: 'Percussion des épineuses…', auscultation: '—' } },
    { code: 'orl', label: 'ORL', icone: 'ear',
      aides: { inspection: 'Oropharynx, amygdales, tympans…', palpation: 'Adénopathies cervicales, sinus…',
        percussion: '—', auscultation: '—' } },
    { code: 'neurologie', label: 'Neurologie', icone: 'brain',
      aides: { inspection: 'Conscience, Glasgow, déficit moteur…', palpation: 'Raideur méningée, réflexes, sensibilité…',
        percussion: 'Réflexes ostéo-tendineux…', auscultation: '—' } },
    { code: 'gyneco_obstetrique', label: 'Gynéco-obstétrique', icone: 'baby', menstruation: true, femme: true,
      aides: { inspection: 'Seins, morphologie abdominale, vulve…', palpation: 'Utérus, sensibilité, annexes…',
        percussion: 'Globe vésical…', auscultation: 'Bruits du cœur fœtal si grossesse…' } },
    { code: 'peau_phaneres', label: 'Peau et phanères', icone: 'hand',
      aides: { inspection: 'Éruption, plaie, ictère, pâleur…', palpation: 'Pli cutané, nodules…',
        percussion: '—', auscultation: '—' } },
  ];

  /* La mention posée par « Normal par défaut » — la METHODOLOGIE dit « RAS
     (Rien À Signaler) ». Une seule chaîne, pour que le récapitulatif sache
     reconnaître un appareil examiné normal d'un appareil non examiné. */
  var MENTION_NORMALE = 'RAS';

  var TYPES_VENUE = [
    { value: 'premiere', label: 'Première consultation' },
    { value: 'controle', label: 'Contrôle' },
    { value: 'suivi', label: 'Suivi' },
    { value: 'urgence', label: 'Urgence' },
  ];

  /* L'état général se COTE : trois valeurs, et la précision n'est exigée que
     lorsqu'il n'est pas bon — « altéré » sans dire en quoi ne se relit pas. */
  var ETATS_GENERAUX = [
    { value: 'bon', label: 'Bon' },
    { value: 'altere', label: 'Altéré' },
    { value: 'passable', label: 'Passable' },
  ];

  /* Les antécédents obstétricaux STRUCTURÉS (DOSSIER CONSULTATION §1), à côté
     du texte libre de la catégorie gynéco-obstétricale : les nombres se
     comptent, le récit s'explique. */
  var PATHOLOGIES_OBSTETRICALES_ANTERIEURES = ['Œuf clair', 'Grossesse môlaire', 'Fausse couche provoquée',
    'Fausse couche spontanée', 'Grossesse extra-utérine', 'Grossesse arrêtée'];

  /* L'examen obstétrical spécifique (DOSSIER CONSULTATION §3). */
  var EXAMEN_OBSTETRICAL = [
    { code: 'terme', label: 'Terme de la grossesse (SA)', type: 'text' },
    { code: 'hu', label: 'Hauteur utérine — HU (cm)', type: 'number' },
    { code: 'bdc', label: 'Bruits du cœur fœtal — BDC (bpm)', type: 'number' },
    { code: 'dosFoetal', label: 'Situation du dos fœtal', type: 'select', options: ['Dos à gauche', 'Dos à droite', 'Non précisé'] },
    { code: 'presentation', label: 'Présentation', type: 'select', options: ['Céphalique', 'Siège', 'Transverse', 'Non précisée'] },
    { code: 'perimetreOmbilical', label: 'Périmètre ombilical (cm)', type: 'number' },
    { code: 'consistanceUterus', label: 'Consistance de l’utérus', type: 'select', options: ['Souple', 'Contractile', 'Tonique'] },
    { code: 'speculum', label: 'Examen au spéculum', type: 'textarea' },
    { code: 'tv', label: 'Toucher vaginal — TV', type: 'textarea' },
  ];

  /**
   * L'examen physique d'un dossier, QUELLE QUE SOIT SA GÉNÉRATION.
   * Les dossiers d'avant la refonte portent quatre champs plats
   * (`exam_inspection`…) : un examen global, non orienté. On ne les réécrit
   * pas — ce serait inventer un appareil que le soignant n'a pas nommé — on
   * les présente sous une rubrique « Examen global (saisie antérieure) »,
   * exactement comme `lignesDe(dep)` adapte les dépenses mono-ligne.
   */
  function examensPhysiquesDe(dossier) {
    if (!dossier) return {};
    if (dossier.examensPhysiques && typeof dossier.examensPhysiques === 'object') return dossier.examensPhysiques;
    var global_ = {};
    TEMPS_EXAMEN.forEach(function (t) {
      if (dossier['exam_' + t.code]) global_[t.code] = dossier['exam_' + t.code];
    });
    return Object.keys(global_).length ? { global: global_ } : {};
  }

  /** Libellé d'un appareil, y compris la rubrique d'adaptation des anciennes saisies. */
  function appareilExamen(code) {
    if (code === 'global') return { code: 'global', label: 'Examen global (saisie antérieure à la refonte)', icone: 'history' };
    return APPAREILS_EXAMEN.filter(function (a) { return a.code === code; })[0] || { code: code, label: code, icone: 'circle' };
  }

  /** Les temps d'un appareil — les quatre, plus la menstruation s'il la porte. */
  function tempsDe(appareil) {
    var t = TEMPS_EXAMEN.map(function (x) { return { code: x.code, label: x.label, ordre: x.ordre }; });
    if (appareil && appareil.menstruation) t.push({ code: 'menstruation', label: 'Menstruation', ordre: 5 });
    return t;
  }

  /**
   * Le récapitulatif lisible de l'examen : une ligne par appareil RENSEIGNÉ.
   * Un appareil dont tous les temps valent « RAS » se condense en
   * « RAS — examen normal » : c'est ce que le médecin lit en premier, les
   * constatations anormales ressortent d'autant mieux.
   */
  function syntheseExamen(examens) {
    var out = [];
    Object.keys(examens || {}).forEach(function (code) {
      var bloc = examens[code] || {};
      var ap = appareilExamen(code);
      var remplis = tempsDe(ap).filter(function (t) { return bloc[t.code] && String(bloc[t.code]).trim(); });
      if (!remplis.length) return;
      var normal = remplis.every(function (t) { return String(bloc[t.code]).trim() === MENTION_NORMALE; });
      out.push({
        code: code, label: ap.label, normal: normal,
        texte: normal ? 'RAS — examen normal'
          : remplis.map(function (t) { return t.label + ' : ' + bloc[t.code]; }).join(' · '),
      });
    });
    return out;
  }

  D.APPAREILS_EXAMEN = APPAREILS_EXAMEN;
  D.MENTION_NORMALE = MENTION_NORMALE;
  D.TYPES_VENUE = TYPES_VENUE;
  D.ETATS_GENERAUX = ETATS_GENERAUX;
  D.PATHOLOGIES_OBSTETRICALES_ANTERIEURES = PATHOLOGIES_OBSTETRICALES_ANTERIEURES;
  D.EXAMEN_OBSTETRICAL = EXAMEN_OBSTETRICAL;
  D.examensPhysiquesDe = examensPhysiquesDe;
  D.appareilExamen = appareilExamen;
  D.tempsExamenDe = tempsDe;
  D.syntheseExamen = syntheseExamen;

  D.CATEGORIES_ANTECEDENT = CATEGORIES_ANTECEDENT;
  D.TEMPS_EXAMEN = TEMPS_EXAMEN;
  D.ETATS_DOSSIER = ETATS_DOSSIER;
  D.etatDossier = etatDossier;
  D.transitionPermise = transitionPermise;
  D.RUBRIQUES_CHIRURGICALES = RUBRIQUES_CHIRURGICALES;
  D.peutEcrireRubrique = peutEcrireRubrique;

  /* --------------------------------------------------------------------------
   * LE CHIRURGIEN REJOINT LE RÉFÉRENTIEL DES CAPACITÉS
   * ------------------------------------------------------------------------
   * Il n'y figurait pas : le prototype ne connaissait que « médecin ». Or la
   * Direction distingue explicitement ce que le généraliste et le chirurgien
   * peuvent écrire au dossier.
   * ---------------------------------------------------------------------- */
  if (D.CAPACITES && !D.CAPACITES.chirurgien) {
    D.CAPACITES.chirurgien = {
      label: 'Chirurgien', voirResultats: 'tous', voirEchographie: 'tous',
      prescrire: ['analyse', 'medicament', 'acte', 'hospitalisation', 'echographie', 'chirurgie'],
      executerSoins: false, remettreResultats: false,
      ecritRubriquesChirurgicales: true,
      note: 'Seul à renseigner les actes chirurgicaux et la programmation du bloc. '
        + 'Consulte le mardi et le jeudi (chirurgien-gynécologue).',
    };
  }
  if (D.CAPACITES && D.CAPACITES.medecin) {
    D.CAPACITES.medecin.ecritRubriquesChirurgicales = false;
  }
})(window);
