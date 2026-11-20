// ENGENDRÉ par prototype_html/build/vecteurs-maternite.js depuis assets/js/data-maternite.js, data-clinique.js et data.js — NE PAS ÉDITER.
// Référentiels de la maternité tracés vers le rapport officiel du 27/08/2026 (10 fonctions SONU, 15 méthodes PF, codification A/N, bornes écrites, partographie).
const Map<String, Object?> matDonnees = {
 "SONU": {
  "reference": "Rapport maternité 27/08/2026 — Tableau A (directives OMS / SNIS / SONU)",
  "fonctions": [
   {
    "num": 1,
    "type": "SONUB",
    "label": "Antibiotiques parentéraux",
    "description": "Ampicilline, gentamycine, métronidazole — infections maternelles et néonatales",
    "code": "SONU1"
   },
   {
    "num": 2,
    "type": "SONUB",
    "label": "Anticonvulsivants parentéraux",
    "description": "Sulfate de magnésium (MgSO4) — éclampsie et pré-éclampsie sévère",
    "code": "SONU2"
   },
   {
    "num": 3,
    "type": "SONUB",
    "label": "Oxytociques parentéraux",
    "description": "Ocytocine, GATPA — prévention et traitement de l’hémorragie du post-partum",
    "code": "SONU3"
   },
   {
    "num": 4,
    "type": "SONUB",
    "label": "Délivrance artificielle et révision utérine",
    "description": "Extraction manuelle du placenta, vérification de la cavité utérine",
    "code": "SONU4"
   },
   {
    "num": 5,
    "type": "SONUB",
    "label": "AMIU / curetage / curage",
    "description": "Aspiration Manuelle Intra-Utérine — avortement incomplet, rétention trophoblastique",
    "code": "SONU5"
   },
   {
    "num": 6,
    "type": "SONUB",
    "label": "Ventouse obstétricale",
    "description": "Accouchement instrumental — assistance mécanique à l’expulsion fœtale",
    "code": "SONU6"
   },
   {
    "num": 7,
    "type": "SONUB",
    "label": "Réanimation du nouveau-né",
    "description": "Désobstruction, ventilation au ballon et masque, réanimation cardio-pulmonaire néonatale",
    "code": "SONU7"
   },
   {
    "num": 8,
    "type": "SONUC",
    "label": "Transfusion sanguine d’urgence",
    "description": "Choc hémorragique sévère obstétrical — fonction SONUC",
    "code": "SONU8"
   },
   {
    "num": 9,
    "type": "SONUC",
    "label": "PEC éclampsie compliquée / chirurgie obstétricale",
    "description": "Soins intensifs, laparotomie d’urgence — rupture utérine, hémorragie réfractaire",
    "code": "SONU9"
   },
   {
    "num": 10,
    "type": "SONUC",
    "label": "Césarienne d’urgence",
    "description": "Extraction fœtale d’urgence par voie haute au bloc — fonction SONUC",
    "code": "SONU10"
   }
  ]
 },
 "METHODES_PF": [
  {
   "code": "diu",
   "label": "DIU (cuivre / hormonal)",
   "categorie": "Longue durée",
   "specification": "Stérilet de longue durée (5 à 10 ans)"
  },
  {
   "code": "diu_pp",
   "label": "DIU PP Immédiat",
   "categorie": "Longue durée",
   "specification": "Insertion dans les 10 min à 48 h après l’accouchement"
  },
  {
   "code": "noristerat",
   "label": "Noristérat",
   "categorie": "Courte durée",
   "specification": "Injection hormonale tous les 2 mois"
  },
  {
   "code": "depo_im",
   "label": "Depo IM (Dépo-Provera)",
   "categorie": "Courte durée",
   "specification": "Injectable intramusculaire tous les 3 mois"
  },
  {
   "code": "dmpa_sc",
   "label": "DMPA-SC Sayana Press",
   "categorie": "Courte durée",
   "specification": "Auto-injection ou injection CS sous-cutanée de 3 mois"
  },
  {
   "code": "co",
   "label": "CO (Contraceptifs Oraux)",
   "categorie": "Courte durée",
   "specification": "Pilule œstro-progestative quotidienne"
  },
  {
   "code": "jadelle",
   "label": "Jadelle (2 bâtonnets)",
   "categorie": "Longue durée",
   "specification": "Implant efficace 5 ans"
  },
  {
   "code": "implanon",
   "label": "Implanon / Nexplanon (1 bâtonnet)",
   "categorie": "Longue durée",
   "specification": "Implant efficace 3 ans"
  },
  {
   "code": "jadelle_pp",
   "label": "Jadelle PP Immédiat",
   "categorie": "Longue durée",
   "specification": "Pose en post-partum immédiat, en salle de maternité"
  },
  {
   "code": "implanon_pp",
   "label": "Implanon PP Immédiat",
   "categorie": "Longue durée",
   "specification": "Pose en post-partum immédiat"
  },
  {
   "code": "pilule",
   "label": "Pilule microprogestative",
   "categorie": "Courte durée",
   "specification": "Compatible avec l’allaitement maternel"
  },
  {
   "code": "ligature",
   "label": "Ligature des trompes",
   "categorie": "Définitive",
   "specification": "Contraception chirurgicale volontaire féminine"
  },
  {
   "code": "vasectomie",
   "label": "Vasectomie",
   "categorie": "Définitive",
   "specification": "Stérilisation masculine volontaire ambulatoire"
  },
  {
   "code": "collier",
   "label": "Collier du cycle / MAMA",
   "categorie": "Naturelle / barrière",
   "specification": "Méthodes naturelles, allaitement maternel et aménorrhée"
  },
  {
   "code": "preservatif",
   "label": "Préservatifs masculins / féminins",
   "categorie": "Naturelle / barrière",
   "specification": "Méthode barrière et double protection VIH/IST"
  }
 ],
 "STATUTS_ACCEPTANTE": [
  {
   "code": "A",
   "label": "A — Nouvelle acceptante"
  },
  {
   "code": "N",
   "label": "N — Ancienne acceptante (renouvellement / changement)"
  }
 ],
 "DOSES_SP": [
  "SP1",
  "SP2",
  "SP3",
  "SP4",
  "SP5"
 ],
 "TYPES_CPON": [
  {
   "code": "cpon1",
   "label": "CPoN 1",
   "fenetre": "6 h – 24 h (J0-J1)"
  },
  {
   "code": "cpon2",
   "label": "CPoN 2",
   "fenetre": "J6 – J14"
  },
  {
   "code": "cpon3",
   "label": "CPoN 3",
   "fenetre": "6ᵉ semaine"
  }
 ],
 "BORNES_NOUVEAU_NE": {
  "pc": {
   "min": 32,
   "max": 38,
   "unite": "cm",
   "libelle": "Périmètre crânien"
  },
  "pt": {
   "min": 30,
   "max": 36,
   "unite": "cm",
   "libelle": "Périmètre thoracique"
  },
  "apgarSeuil5min": 7,
  "source": "Rapport maternité 27/08/2026 — Module C et §5.4 (alertes de sécurité clinique)"
 },
 "AGES_RISQUE_CPN": {
  "min": 18,
  "max": 35
 },
 "URGENCES_MATERNITE": [
  {
   "code": "referee",
   "label": "Femme en travail référée d’urgence"
  },
  {
   "code": "referee_admise",
   "label": "Référée d’urgence ET admise à l’hôpital de référence"
  },
  {
   "code": "referee_pec",
   "label": "Référée d’urgence ET prise en charge par l’hôpital de référence"
  }
 ],
 "TRANCHES_AGE_CURATIF": [
  "< 1 mois",
  "1–11 mois",
  "1–4 ans",
  "5–9 ans",
  "10–14 ans",
  "15–19 ans",
  "20–24 ans",
  "25 ans et +"
 ],
 "PTME": {
  "reference": "Rapport maternité 27/08/2026 — Module I et tableau 6 (protocoles PTME)",
  "prophylaxiesNN": [
   {
    "code": 1,
    "label": "NVP"
   },
   {
    "code": 2,
    "label": "AZT"
   },
   {
    "code": 3,
    "label": "AZT + NVP"
   },
   {
    "code": 4,
    "label": "Aucune"
   }
  ],
  "allaitements": [
   "Exclusif",
   "Artificiel",
   "Mixte"
  ],
  "dureesARV": [
   "< 8 semaines",
   "≥ 8 semaines"
  ],
  "suivisEnfant": [
   "PCR naissance",
   "PCR-1 (6 semaines)",
   "PCR-2 (9 mois)",
   "Sérologie VIH (18 mois)"
  ]
 },
 "TYPES_ACCOUCHEMENT": [
  "Eutocique",
  "Dystocique",
  "Dirigé",
  "Gemellaire",
  "Trimellaire",
  "Césarienne"
 ],
 "ACTES_ACCOUCHEMENT": [
  "Épisiotomie",
  "Délivrance artificielle",
  "Révision utérine",
  "AMIU",
  "Ventouse obstétricale",
  "GATPA"
 ],
 "PARTOGRAMME": {
  "alerteDepart": 4,
  "alerteParHeure": 1,
  "actionDecalageHeures": 4,
  "liquides": [
   {
    "code": "I",
    "label": "I — Poche des eaux intacte"
   },
   {
    "code": "C",
    "label": "C — Liquide clair"
   },
   {
    "code": "M",
    "label": "M — Méconial (purée de pois)"
   },
   {
    "code": "S",
    "label": "S — Sanglant / hématique"
   },
   {
    "code": "V",
    "label": "V — « Jus de viande »"
   },
   {
    "code": "J",
    "label": "J — Jaunâtre"
   }
  ],
  "actions": [
   "Rupture artificielle de la PDE",
   "Antispasmodique",
   "Ocytocine",
   "Épisiotomie",
   "Ventouse / Forceps",
   "Référence",
   "Césarienne / Laparotomie"
  ],
  "chevauchement": [
   {
    "code": 0,
    "label": "0 — Pas de chevauchement, sutures palpables"
   },
   {
    "code": 1,
    "label": "1 — Apposition des os du crâne"
   },
   {
    "code": 2,
    "label": "2 — Chevauchement réductible"
   },
   {
    "code": 3,
    "label": "3 — Chevauchement irréductible"
   }
  ],
  "descente": [
   {
    "code": "5/5",
    "label": "5 travers de doigts (5/5)"
   },
   {
    "code": "4/5",
    "label": "4 travers de doigts (4/5)"
   },
   {
    "code": "3/5",
    "label": "3 travers de doigts (3/5)"
   },
   {
    "code": "2/5",
    "label": "2 travers de doigts (2/5)"
   },
   {
    "code": "1/5",
    "label": "1 travers de doigt (1/5)"
   }
  ],
  "contractions": [
   {
    "code": "courte",
    "label": "< 20 secondes"
   },
   {
    "code": "moyenne",
    "label": "20 à 40 secondes"
   },
   {
    "code": "longue",
    "label": "> 40 secondes"
   }
  ],
  "renseignements": [
   "Nom & prénoms",
   "Âge",
   "Âge gestationnel",
   "Gestité",
   "Parité",
   "Poids",
   "Date / heure de l’admission",
   "Date / heure de la rupture des membranes",
   "Date / heure de l’accouchement",
   "Numéro du dossier",
   "Nom de l’accoucheur",
   "Qualification"
  ],
  "source": "PARTOGRAPHIE — formulaire national ; légende et codes relevés sur un dossier RÉELLEMENT REMPLI (exemplaire de recette du 06/09/2026)."
 },
 "DROITS_FONDAMENTAUX": [
  "Droit à l’information",
  "Droit d’accès",
  "Droit au choix",
  "Droit à la sécurité",
  "Droit à la confidentialité et au secret professionnel",
  "Droit au confort",
  "Droit à la dignité",
  "Droit à l’assurance et aux avantages sociaux",
  "Droit à la continuité des soins",
  "Droit d’exprimer son opinion"
 ],
 "PLAN_ACCOUCHEMENT": [
  "Lieu de l’accouchement",
  "Accoucheur qualifié identifié",
  "Contact de l’accoucheur",
  "Mode de transport",
  "Accompagnant identifié",
  "Garde des enfants à la maison identifiée",
  "Décideur en l’absence du mari",
  "Épargne pour l’accouchement",
  "Donneur de sang prévu"
 ],
 "FACTEURS_SURVEILLANCE": [
  {
   "code": "age_min",
   "libelle": "Âge < 16 ans"
  },
  {
   "code": "age_max",
   "libelle": "Âge > 35 ans"
  },
  {
   "code": "taille",
   "libelle": "Taille < 1,50 m"
  },
  {
   "code": "boiterie",
   "libelle": "Boiterie"
  },
  {
   "code": "parite",
   "libelle": "Parité > 6"
  },
  {
   "code": "cesarienne",
   "libelle": "Césarienne au dernier accouchement"
  },
  {
   "code": "mortne",
   "libelle": "Mort-né au dernier accouchement"
  },
  {
   "code": "drepano",
   "libelle": "Drépanocytose SS ou SC"
  },
  {
   "code": "hta",
   "libelle": "HTA connue"
  },
  {
   "code": "fausses_couches",
   "libelle": "Fausses couches répétées"
  },
  {
   "code": "diabete",
   "libelle": "Diabète"
  },
  {
   "code": "autres",
   "libelle": "Autres facteurs"
  }
 ],
 "EXAMENS_DOSSIER": [
  {
   "code": "gs",
   "libelle": "Groupe sanguin",
   "groupe": "Immuno-hématologie"
  },
  {
   "code": "rh",
   "libelle": "Rhésus",
   "groupe": "Immuno-hématologie"
  },
  {
   "code": "coombs",
   "libelle": "Test de Coombs indirect",
   "groupe": "Immuno-hématologie"
  },
  {
   "code": "electrophorese",
   "libelle": "Électrophorèse de l’hémoglobine",
   "groupe": "Immuno-hématologie"
  },
  {
   "code": "hb",
   "libelle": "Taux d’hémoglobine",
   "groupe": "Hématologie"
  },
  {
   "code": "hematocrite",
   "libelle": "Hématocrite",
   "groupe": "Hématologie"
  },
  {
   "code": "plaquettes",
   "libelle": "Plaquettes",
   "groupe": "Hématologie"
  },
  {
   "code": "tpha",
   "libelle": "TPHA",
   "groupe": "Sérologie"
  },
  {
   "code": "vdrl",
   "libelle": "VDRL",
   "groupe": "Sérologie"
  },
  {
   "code": "hiv1",
   "libelle": "HIV 1",
   "groupe": "Sérologie"
  },
  {
   "code": "hiv2",
   "libelle": "HIV 2",
   "groupe": "Sérologie"
  },
  {
   "code": "toxo_igg",
   "libelle": "Toxoplasmose IgG",
   "groupe": "Sérologie"
  },
  {
   "code": "toxo_igm",
   "libelle": "Toxoplasmose IgM",
   "groupe": "Sérologie"
  },
  {
   "code": "rubeole_igg",
   "libelle": "Rubéole IgG",
   "groupe": "Sérologie"
  },
  {
   "code": "rubeole_igm",
   "libelle": "Rubéole IgM",
   "groupe": "Sérologie"
  },
  {
   "code": "hepatiteB",
   "libelle": "Hépatite B (à partir de 6 mois)",
   "groupe": "Sérologie"
  },
  {
   "code": "ecbu",
   "libelle": "ECBU",
   "groupe": "Bactériologie"
  },
  {
   "code": "glycemie",
   "libelle": "Glycémie à jeun",
   "groupe": "Biochimie"
  },
  {
   "code": "gp75",
   "libelle": "GP 75",
   "groupe": "Biochimie"
  }
 ],
 "COMPTES_RENDUS_MATERNITE": [
  {
   "code": "accouchement",
   "label": "Compte rendu d’accouchement",
   "icone": "baby",
   "acteCode": "ACCE",
   "rubriques": [
    [
     "dateHeure",
     "Date et heure de l’accouchement",
     "datetime",
     true
    ],
    [
     "termeSA",
     "Terme (semaines d’aménorrhée)",
     "nombre",
     true
    ],
    [
     "presentation",
     "Présentation",
     "liste",
     true,
     [
      "Céphalique",
      "Siège",
      "Transverse",
      "Autre"
     ]
    ],
    [
     "voie",
     "Voie d’accouchement",
     "liste",
     true,
     [
      "Voie basse eutocique",
      "Voie basse dystocique",
      "Césarienne"
     ]
    ],
    [
     "travailDuree",
     "Durée du travail (heures)",
     "nombre",
     false
    ],
    [
     "delivrance",
     "Délivrance",
     "liste",
     true,
     [
      "Spontanée et complète",
      "Dirigée",
      "Artificielle",
      "Révision utérine"
     ]
    ],
    [
     "episiotomie",
     "Épisiotomie",
     "binaire",
     false
    ],
    [
     "dechirure",
     "Déchirure périnéale",
     "liste",
     false,
     [
      "Aucune",
      "Degré 1",
      "Degré 2",
      "Degré 3",
      "Degré 4"
     ]
    ],
    [
     "pertesSanguines",
     "Pertes sanguines estimées (ml)",
     "nombre",
     false
    ],
    [
     "sexeEnfant",
     "Sexe de l’enfant",
     "liste",
     true,
     [
      "Masculin",
      "Féminin"
     ]
    ],
    [
     "poidsEnfant",
     "Poids de l’enfant (g)",
     "nombre",
     true
    ],
    [
     "apgar1",
     "Apgar à 1 minute",
     "nombre",
     false
    ],
    [
     "apgar5",
     "Apgar à 5 minutes",
     "nombre",
     false
    ],
    [
     "etatMere",
     "État de la mère à l’issue",
     "zone",
     true
    ],
    [
     "observations",
     "Observations",
     "zone",
     false
    ]
   ]
  },
  {
   "code": "planning_familial",
   "label": "Compte rendu de planning familial",
   "icone": "calendar-heart",
   "acteCode": null,
   "rubriques": [
    [
     "dateActe",
     "Date de l’acte",
     "date",
     true
    ],
    [
     "methode",
     "Méthode",
     "liste",
     true,
     [
      "Implant",
      "DIU / stérilet",
      "Injectable Noristerat / Laafia",
      "Injectable Sayana Press",
      "Pilule",
      "Préservatif",
      "Autre"
     ]
    ],
    [
     "geste",
     "Geste",
     "liste",
     true,
     [
      "Pose",
      "Retrait",
      "Renouvellement",
      "Conseil seul"
     ]
    ],
    [
     "counseling",
     "Counseling délivré",
     "binaire",
     true
    ],
    [
     "effetsSecondaires",
     "Effets secondaires expliqués",
     "binaire",
     true
    ],
    [
     "prochainRdv",
     "Prochain rendez-vous",
     "date",
     false
    ],
    [
     "observations",
     "Observations",
     "zone",
     false
    ]
   ],
   "note": "Les actes de planification familiale sont TOUS non couverts par les assurances (grille gynéco-obstétricale)."
  },
  {
   "code": "amiu",
   "label": "Compte rendu d’AMIU",
   "icone": "activity",
   "acteCode": "AMIU",
   "rubriques": [
    [
     "dateHeure",
     "Date et heure",
     "datetime",
     true
    ],
    [
     "indication",
     "Indication",
     "zone",
     true
    ],
    [
     "termeSA",
     "Terme au moment du geste (SA)",
     "nombre",
     false
    ],
    [
     "anesthesie",
     "Anesthésie / analgésie",
     "zone",
     false
    ],
    [
     "deroulement",
     "Déroulement du geste",
     "zone",
     true
    ],
    [
     "produitAspire",
     "Produit aspiré",
     "zone",
     false
    ],
    [
     "complications",
     "Complications",
     "zone",
     false
    ],
    [
     "suites",
     "Suites et conduite à tenir",
     "zone",
     true
    ],
    [
     "operateurId",
     "Opérateur",
     "soignant",
     true
    ]
   ]
  }
 ],
 "GROUPES_SANGUINS": [
  "O+",
  "O-",
  "A+",
  "A-",
  "B+",
  "B-",
  "AB+",
  "AB-"
 ],
 "CLASSES_MERES": [
  "1er trimestre",
  "2ème trimestre",
  "3ème trimestre",
  "Accouchée récente",
  "Accouchée tardive"
 ],
 "GRILLE_CPN": [
  {
   "code": "arrivee",
   "libelle": "Date et heure d’arrivée",
   "type": "texte",
   "groupe": "Venue"
  },
  {
   "code": "heureCpnr",
   "libelle": "Heure de la CPNR",
   "type": "texte",
   "groupe": "Venue"
  },
  {
   "code": "prestataire",
   "libelle": "Identité et qualification du prestataire",
   "type": "texte",
   "groupe": "Venue"
  },
  {
   "code": "terme",
   "libelle": "Terme de la grossesse",
   "type": "texte",
   "groupe": "Venue"
  },
  {
   "code": "echographie",
   "libelle": "Résultat de l’échographie",
   "type": "texte",
   "groupe": "Venue"
  },
  {
   "code": "plaintes",
   "libelle": "Plaintes",
   "type": "texte",
   "groupe": "Venue"
  },
  {
   "code": "ta",
   "libelle": "TA",
   "type": "texte",
   "groupe": "État général"
  },
  {
   "code": "pouls",
   "libelle": "Pouls",
   "type": "nombre",
   "groupe": "État général"
  },
  {
   "code": "temperature",
   "libelle": "Température",
   "type": "nombre",
   "groupe": "État général"
  },
  {
   "code": "muqueuses",
   "libelle": "Muqueuses",
   "type": "texte",
   "groupe": "État général"
  },
  {
   "code": "omi",
   "libelle": "OMI",
   "type": "texte",
   "groupe": "État général"
  },
  {
   "code": "pb",
   "libelle": "PB",
   "type": "texte",
   "groupe": "État général"
  },
  {
   "code": "conscience",
   "libelle": "Conscience",
   "type": "texte",
   "groupe": "État général"
  },
  {
   "code": "poids",
   "libelle": "Poids",
   "type": "nombre",
   "groupe": "État général"
  },
  {
   "code": "imc",
   "libelle": "IMC",
   "type": "nombre",
   "groupe": "État général",
   "calcule": true
  },
  {
   "code": "urines",
   "libelle": "Test d’urines (A/N/S/L)",
   "type": "texte",
   "groupe": "Examens",
   "aide": "A : Albumine · N : Nitrite · S : Sucre · L : Leucocyte"
  },
  {
   "code": "seins",
   "libelle": "Examen des seins",
   "type": "texte",
   "groupe": "Examens"
  },
  {
   "code": "inspection",
   "libelle": "Inspection",
   "type": "texte",
   "groupe": "Examens"
  },
  {
   "code": "hu",
   "libelle": "Mensuration : HU",
   "type": "nombre",
   "groupe": "Examens"
  },
  {
   "code": "presentation",
   "libelle": "Palpation : présentation",
   "type": "texte",
   "groupe": "Examens"
  },
  {
   "code": "pointsUreteraux",
   "libelle": "Points urétéraux moyens",
   "type": "texte",
   "groupe": "Examens"
  },
  {
   "code": "bdcf",
   "libelle": "Auscultation : BDCF",
   "type": "nombre",
   "groupe": "Examens"
  },
  {
   "code": "vulve",
   "libelle": "État de la vulve",
   "type": "texte",
   "groupe": "Examens"
  },
  {
   "code": "speculum",
   "libelle": "Pose du spéculum",
   "type": "texte",
   "groupe": "Examens"
  },
  {
   "code": "toucherVaginal",
   "libelle": "Toucher vaginal",
   "type": "texte",
   "groupe": "Examens"
  },
  {
   "code": "bassin",
   "libelle": "Examen du bassin",
   "type": "texte",
   "groupe": "Examens"
  },
  {
   "code": "diagnostic",
   "libelle": "Diagnostic",
   "type": "texte",
   "groupe": "Conclusion"
  },
  {
   "code": "sp",
   "libelle": "TPI / SP — dose administrée",
   "type": "texte",
   "groupe": "Prévention"
  },
  {
   "code": "deparasitage",
   "libelle": "Déparasitage",
   "type": "ouiNon",
   "groupe": "Prévention"
  },
  {
   "code": "fer",
   "libelle": "Fer 200 mg/jour",
   "type": "ouiNon",
   "groupe": "Prévention"
  },
  {
   "code": "foldine",
   "libelle": "Foldine 5 mg/jour",
   "type": "ouiNon",
   "groupe": "Prévention"
  },
  {
   "code": "milda",
   "libelle": "A dormi sous MILDA la nuit dernière ?",
   "type": "ouiNon",
   "groupe": "Prévention"
  },
  {
   "code": "conseilsNutrition",
   "libelle": "Conseils nutritionnels",
   "type": "ouiNon",
   "groupe": "Conseils"
  },
  {
   "code": "signesDanger",
   "libelle": "Informations sur les signes de danger",
   "type": "ouiNon",
   "groupe": "Conseils"
  },
  {
   "code": "counselingPF",
   "libelle": "Counseling sur la PF",
   "type": "ouiNon",
   "groupe": "Conseils"
  },
  {
   "code": "methodePF",
   "libelle": "Méthode choisie",
   "type": "texte",
   "groupe": "Conseils"
  },
  {
   "code": "conduite",
   "libelle": "Conduite à tenir",
   "type": "texte",
   "groupe": "Conclusion"
  },
  {
   "code": "rdvCpn",
   "libelle": "RDV — CPN",
   "type": "date",
   "groupe": "Suite"
  },
  {
   "code": "rdvClasse",
   "libelle": "RDV — Classe des mères",
   "type": "texte",
   "groupe": "Suite"
  },
  {
   "code": "rechercheActive",
   "libelle": "Recherche active",
   "type": "texte",
   "groupe": "Suite"
  }
 ],
 "INDICATEURS_DHIS2": [
  {
   "code": "pf_acceptation",
   "label": "Taux d’acceptation PF (nouvelles acceptantes)"
  },
  {
   "code": "gar",
   "label": "Proportion de grossesses à risque (GAR)"
  },
  {
   "code": "sp3",
   "label": "Couverture SP3"
  },
  {
   "code": "sp5",
   "label": "Couverture SP5"
  },
  {
   "code": "milda",
   "label": "Couverture MILDA"
  },
  {
   "code": "transferts",
   "label": "Parturientes transférées admises et prises en charge"
  }
 ]
};
