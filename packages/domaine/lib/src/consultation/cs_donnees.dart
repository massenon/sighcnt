// ENGENDRÉ par prototype_html/build/vecteurs-consultation.js — référentiels de la consultation lus sur la maquette
// (data-dossier.js, data-clinique.js, data.js). Ne pas éditer à la main : relancer le script.
// ignore_for_file: prefer_single_quotes
library;

/// Les référentiels de la maquette, tels que `SIGH.data` les porte.
const Map<String, Object?> csDonnees = {
  'appareils': [
    {
      'code': 'cardio_vasculaire',
      'label': 'Appareil cardio-vasculaire',
      'icone': 'heart-pulse',
      'aides': {
        'inspection': 'Turgescence jugulaire, œdèmes, cyanose…',
        'palpation': 'Choc de pointe, pouls périphériques…',
        'percussion': 'Limites cardiaques…',
        'auscultation': 'Bruits du cœur, souffles…',
      },
    },
    {
      'code': 'pleuro_pulmonaire',
      'label': 'Appareil pleuro-pulmonaire',
      'icone': 'wind',
      'aides': {
        'inspection': 'Type respiratoire, ampliation thoracique…',
        'palpation': 'Vibrations vocales…',
        'percussion': 'Sonorité pulmonaire, matité…',
        'auscultation': 'Murmure vésiculaire, râles, sifflements…',
      },
    },
    {
      'code': 'hepato_gastro_digestif',
      'label': 'Hépato-gastro-digestif',
      'icone': 'soup',
      'aides': {
        'inspection': 'Morphologie abdominale, cicatrices, circulation collatérale…',
        'palpation': 'Souplesse, défense, masse, hépatomégalie…',
        'percussion': 'Tympanisme, matité déclive…',
        'auscultation': 'Bruits hydro-aériques…',
      },
    },
    {
      'code': 'genito_urinaire',
      'label': 'Génito-urinaire',
      'icone': 'droplets',
      'menstruation': true,
      'aides': {
        'inspection': 'Organes génitaux externes, écoulement…',
        'palpation': 'Fosses lombaires, contact lombaire…',
        'percussion': 'Globe vésical…',
        'auscultation': '—',
      },
    },
    {
      'code': 'locomoteur',
      'label': 'Appareil locomoteur',
      'icone': 'bone',
      'aides': {
        'inspection': 'Déformation, tuméfaction, attitude antalgique…',
        'palpation': 'Douleur provoquée, mobilité articulaire…',
        'percussion': 'Percussion des épineuses…',
        'auscultation': '—',
      },
    },
    {
      'code': 'orl',
      'label': 'ORL',
      'icone': 'ear',
      'aides': {
        'inspection': 'Oropharynx, amygdales, tympans…',
        'palpation': 'Adénopathies cervicales, sinus…',
        'percussion': '—',
        'auscultation': '—',
      },
    },
    {
      'code': 'neurologie',
      'label': 'Neurologie',
      'icone': 'brain',
      'aides': {
        'inspection': 'Conscience, Glasgow, déficit moteur…',
        'palpation': 'Raideur méningée, réflexes, sensibilité…',
        'percussion': 'Réflexes ostéo-tendineux…',
        'auscultation': '—',
      },
    },
    {
      'code': 'gyneco_obstetrique',
      'label': 'Gynéco-obstétrique',
      'icone': 'baby',
      'menstruation': true,
      'femme': true,
      'aides': {
        'inspection': 'Seins, morphologie abdominale, vulve…',
        'palpation': 'Utérus, sensibilité, annexes…',
        'percussion': 'Globe vésical…',
        'auscultation': 'Bruits du cœur fœtal si grossesse…',
      },
    },
    {
      'code': 'peau_phaneres',
      'label': 'Peau et phanères',
      'icone': 'hand',
      'aides': {
        'inspection': 'Éruption, plaie, ictère, pâleur…',
        'palpation': 'Pli cutané, nodules…',
        'percussion': '—',
        'auscultation': '—',
      },
    },
  ],
  'temps': [
    {
      'code': 'inspection',
      'label': 'Inspection',
      'ordre': 1,
      'note': 'Ce que l’on voit : état général, coloration, morphologie, cicatrices, déformations.',
    },
    {
      'code': 'palpation',
      'label': 'Palpation',
      'ordre': 2,
      'note': 'Ce que l’on sent : masses, défense, douleur provoquée, adénopathies, organomégalie.',
    },
    {
      'code': 'percussion',
      'label': 'Percussion',
      'ordre': 3,
      'note': 'Ce que l’on entend en percutant : matité, tympanisme, sonorité.',
    },
    {
      'code': 'auscultation',
      'label': 'Auscultation',
      'ordre': 4,
      'note': 'Ce que l’on entend au stéthoscope : bruits du cœur, murmure vésiculaire, râles, souffles.',
    },
  ],
  'antecedents': [
    {
      'code': 'medicaux',
      'label': 'Antécédents médicaux',
      'icone': 'stethoscope',
      'note': 'Maladies chroniques, affections traitées, allergies, traitements au long cours.',
      'exemples': [
        'Hypertension artérielle',
        'Diabète',
        'Drépanocytose',
        'Asthme',
        'Épilepsie',
        'Tuberculose traitée',
        'Hépatite B',
        'Insuffisance rénale',
        'Ulcère gastro-duodénal',
        'Allergie médicamenteuse',
      ],
    },
    {
      'code': 'chirurgicaux',
      'label': 'Antécédents chirurgicaux',
      'icone': 'scissors',
      'note': 'Toute intervention subie, avec sa date et son indication. C’est la première chose que le chirurgien cherche avant d’ouvrir.',
      'exemples': [
        'Appendicectomie',
        'Césarienne',
        'Herniorraphie',
        'Cholécystectomie',
        'Hystérectomie',
        'Ostéosynthèse',
        'Amygdalectomie',
        'Laparotomie exploratrice',
      ],
    },
    {
      'code': 'gyneco_obstetricaux',
      'label': 'Antécédents gynéco-obstétricaux',
      'icone': 'baby',
      'note': 'Gestité, parité, avortements, enfants vivants, contraception, ménarche, DDR.',
      'exemples': [
        'Gestité',
        'Parité',
        'Avortements',
        'Enfants vivants',
        'Contraception en cours',
        'Âge des premières règles',
        'Date des dernières règles',
        'Accouchement dystocique antérieur',
      ],
    },
  ],
  'etatsDossier': [
    {
      'code': 'attente',
      'label': 'EN ATTENTE',
      'couleur': 'neutral',
      'ordre': 1,
      'note': 'Le patient est enregistré et attend d’être reçu.',
      'suivants': [
        'consultation',
      ],
    },
    {
      'code': 'consultation',
      'label': 'EN CONSULTATION',
      'couleur': 'info',
      'ordre': 2,
      'note': 'Le soignant a pris le patient en charge.',
      'suivants': [
        'attente_labo',
        'cloture',
      ],
    },
    {
      'code': 'attente_labo',
      'label': 'EN ATTENTE LABO',
      'couleur': 'warning',
      'ordre': 3,
      'note': 'Des examens ont été prescrits ; la décision attend leurs résultats.',
      'suivants': [
        'consultation',
        'cloture',
      ],
    },
    {
      'code': 'cloture',
      'label': 'CLÔTURÉ',
      'couleur': 'success',
      'ordre': 4,
      'note': 'La consultation est terminée et le dossier arrêté.',
      'suivants': <Object?>[],
    },
  ],
  'typesVenue': [
    {
      'value': 'premiere',
      'label': 'Première consultation',
    },
    {
      'value': 'controle',
      'label': 'Contrôle',
    },
    {
      'value': 'suivi',
      'label': 'Suivi',
    },
    {
      'value': 'urgence',
      'label': 'Urgence',
    },
  ],
  'etatsGeneraux': [
    {
      'value': 'bon',
      'label': 'Bon',
    },
    {
      'value': 'altere',
      'label': 'Altéré',
    },
    {
      'value': 'passable',
      'label': 'Passable',
    },
  ],
  'pathologiesObstetricales': [
    'Œuf clair',
    'Grossesse môlaire',
    'Fausse couche provoquée',
    'Fausse couche spontanée',
    'Grossesse extra-utérine',
    'Grossesse arrêtée',
  ],
  'examenObstetrical': [
    {
      'code': 'terme',
      'label': 'Terme de la grossesse (SA)',
      'type': 'text',
    },
    {
      'code': 'hu',
      'label': 'Hauteur utérine — HU (cm)',
      'type': 'number',
    },
    {
      'code': 'bdc',
      'label': 'Bruits du cœur fœtal — BDC (bpm)',
      'type': 'number',
    },
    {
      'code': 'dosFoetal',
      'label': 'Situation du dos fœtal',
      'type': 'select',
      'options': [
        'Dos à gauche',
        'Dos à droite',
        'Non précisé',
      ],
    },
    {
      'code': 'presentation',
      'label': 'Présentation',
      'type': 'select',
      'options': [
        'Céphalique',
        'Siège',
        'Transverse',
        'Non précisée',
      ],
    },
    {
      'code': 'perimetreOmbilical',
      'label': 'Périmètre ombilical (cm)',
      'type': 'number',
    },
    {
      'code': 'consistanceUterus',
      'label': 'Consistance de l’utérus',
      'type': 'select',
      'options': [
        'Souple',
        'Contractile',
        'Tonique',
      ],
    },
    {
      'code': 'speculum',
      'label': 'Examen au spéculum',
      'type': 'textarea',
    },
    {
      'code': 'tv',
      'label': 'Toucher vaginal — TV',
      'type': 'textarea',
    },
  ],
  'rubriquesChirurgicales': [
    'actesChirurgicaux',
    'indicationOperatoire',
    'blocPrevu',
    'risqueOperatoire',
  ],
  'chapitres': [
    {
      'id': 'infectieuses',
      'label': 'Maladies infectieuses et parasitaires',
      'tone': 'danger',
    },
    {
      'id': 'respiratoire',
      'label': 'Appareil respiratoire',
      'tone': 'info',
    },
    {
      'id': 'digestif',
      'label': 'Appareil digestif',
      'tone': 'warning',
    },
    {
      'id': 'cardiovasculaire',
      'label': 'Appareil circulatoire',
      'tone': 'danger',
    },
    {
      'id': 'genito',
      'label': 'Appareil génito-urinaire',
      'tone': 'navy',
    },
    {
      'id': 'grossesse',
      'label': 'Grossesse, accouchement et puerpéralité',
      'tone': 'success',
    },
    {
      'id': 'metabolique',
      'label': 'Endocrinien, nutritionnel et métabolique',
      'tone': 'warning',
    },
    {
      'id': 'sang',
      'label': 'Sang et organes hématopoïétiques',
      'tone': 'danger',
    },
    {
      'id': 'peau',
      'label': 'Peau et tissu cellulaire sous-cutané',
      'tone': 'neutral',
    },
    {
      'id': 'osteo',
      'label': 'Système ostéo-articulaire',
      'tone': 'neutral',
    },
    {
      'id': 'traumatismes',
      'label': 'Traumatismes et empoisonnements',
      'tone': 'danger',
    },
    {
      'id': 'autres',
      'label': 'Autres motifs de recours',
      'tone': 'neutral',
    },
  ],
  'originesPrescription': [
    {
      'code': 'consultation',
      'label': 'Consultation',
      'module': 'M2',
      'icone': 'stethoscope',
    },
    {
      'code': 'hospitalisation',
      'label': 'Hospitalisation',
      'module': 'M3',
      'icone': 'bed-double',
    },
    {
      'code': 'bloc',
      'label': 'Bloc opératoire',
      'module': 'M3',
      'icone': 'scissors',
    },
    {
      'code': 'maternite',
      'label': 'Maternité',
      'module': 'M4',
      'icone': 'baby',
    },
  ],
  'secteursSoins': [
    {
      'code': 'salle_soins',
      'label': 'Salle de soins',
      'icone': 'syringe',
    },
    {
      'code': 'hospitalisation',
      'label': 'Hospitalisation',
      'icone': 'bed-double',
    },
    {
      'code': 'maternite',
      'label': 'Maternité',
      'icone': 'baby',
    },
  ],
  'modalites': [
    {
      'code': 'ambulatoire',
      'label': 'Ambulatoire',
      'regle': 'Administré par la SALLE DE SOINS seule, du premier au dernier passage.',
    },
    {
      'code': 'hospitalisation',
      'label': 'En hospitalisation',
      'regle': 'PREMIÈRE administration par la salle de soins ; les SUIVANTES par l’hospitalisation.',
    },
  ],
  'mentionNormale': 'RAS',
};
