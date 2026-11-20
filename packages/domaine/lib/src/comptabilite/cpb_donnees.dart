// ENGENDRÉ par prototype_html/build/vecteurs-comptabilite-b.js — NE PAS ÉDITER. `D.RUBRIQUES_RESULTAT` (la cascade des soldes de gestion) et `D.NATURE_CHARGE` (la répartition fixe / variable PROPOSÉE — un jugement de gestion,
// non une donnée du plan comptable) de prototype_html/assets/js/data.js.
library;

const List<Map<String, Object?>> cpbRubriquesResultat = [
  {
    'id': 'ventes_march',
    'label': 'Ventes de marchandises',
    'sens': 'produit',
    'prefixes': [
      '701',
    ],
    'sig': 'marge',
    'note': 'Médicaments et consommables revendus. RG-02 les facture au prix d’achat : la marge commerciale doit être nulle ou quasi nulle.',
  },
  {
    'id': 'achats_march',
    'label': 'Achats de marchandises',
    'sens': 'charge',
    'prefixes': [
      '601',
      '6032',
    ],
    'sig': 'marge',
  },
  {
    'id': 'production',
    'label': 'Prestations de services',
    'sens': 'produit',
    'prefixes': [
      '706',
      '702',
      '704',
      '707',
    ],
    'sig': 'valeurAjoutee',
    'note': 'Consultations, analyses, actes, hospitalisation : le cœur de l’activité.',
  },
  {
    'id': 'consommations',
    'label': 'Consommations intermédiaires',
    'sens': 'charge',
    'prefixes': [
      '602',
      '604',
      '605',
      '608',
      '61',
      '62',
      '63',
    ],
    'sig': 'valeurAjoutee',
    'note': 'Réactifs, eau, électricité, entretien, honoraires, frais bancaires — tout ce que la clinique achète pour travailler.',
  },
  {
    'id': 'impots',
    'label': 'Impôts et taxes',
    'sens': 'charge',
    'prefixes': [
      '64',
    ],
    'sig': 'ebe',
  },
  {
    'id': 'personnel',
    'label': 'Charges de personnel',
    'sens': 'charge',
    'prefixes': [
      '66',
    ],
    'sig': 'ebe',
    'note': 'Salaires bruts et charges sociales patronales.',
  },
  {
    'id': 'dotations',
    'label': 'Dotations aux amortissements',
    'sens': 'charge',
    'prefixes': [
      '68',
    ],
    'sig': 'exploitation',
  },
  {
    'id': 'autres_charges',
    'label': 'Autres charges d’exploitation',
    'sens': 'charge',
    'prefixes': [
      '65',
    ],
    'sig': 'exploitation',
  },
  {
    'id': 'produits_fin',
    'label': 'Produits financiers',
    'sens': 'produit',
    'prefixes': [
      '77',
    ],
    'sig': 'financier',
  },
  {
    'id': 'charges_fin',
    'label': 'Charges financières',
    'sens': 'charge',
    'prefixes': [
      '67',
    ],
    'sig': 'financier',
    'note': 'Intérêts d’emprunt. Ils sont ICI et non dans l’exploitation : les y mettre ferait juger l’activité sur des choix de financement.',
  },
  {
    'id': 'impot_societes',
    'label': 'Impôt sur le résultat',
    'sens': 'charge',
    'prefixes': [
      '89',
    ],
    'sig': 'net',
  },
];

/// Préfixe de compte → `fixe` ou `variable` (le préfixe le plus long l'emporte). `aValider` et `note` sont lus à part.
const Map<String, Object?> cpbNatureChargeReferentiel = {
  '64': 'fixe',
  '65': 'fixe',
  '66': 'fixe',
  '67': 'fixe',
  '68': 'fixe',
  '601': 'variable',
  '602': 'variable',
  '603': 'variable',
  '604': 'variable',
  '605': 'fixe',
  '608': 'variable',
  '612': 'variable',
  '616': 'fixe',
  '618': 'fixe',
  '622': 'fixe',
  '624': 'fixe',
  '625': 'fixe',
  '627': 'fixe',
  '628': 'fixe',
  '631': 'fixe',
  '632': 'fixe',
  '634': 'fixe',
  '635': 'fixe',
  '637': 'fixe',
  '638': 'fixe',
  'aValider': true,
  'note': 'Répartition PROPOSÉE par défaut. Elle relève de l’analyse de gestion, non du plan comptable, et se corrige compte par compte.',
};
