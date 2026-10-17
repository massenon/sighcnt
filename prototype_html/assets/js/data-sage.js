/* =============================================================================
 * SIGH-CNT — Reprise des données SAGE 100 et du catalogue tarifaire
 * -----------------------------------------------------------------------------
 * Deux référentiels transcrits des documents réels de la clinique :
 *
 *   INVENTAIRE_SAGE   « Inventaire : Grand Stock » édité le 15/07/2026 depuis
 *                     SAGE 100 Gestion commerciale 15.01, tenue de compte en
 *                     F CFA, valorisation au CMUP. 175 articles, 12 080 unités,
 *                     3 976 459 FCFA de stock valorisé.
 *
 *   CATALOGUE_TARIFS  « Tarifs des médicaments et accessoires médicaux »,
 *                     144 désignations. Le document ne renseigne pas la colonne
 *                     des prix : ceux-ci sont repris du CMUP de l'inventaire
 *                     lorsque l'article y figure, et restent à fixer sinon.
 *
 * Conformément au principe de reprise (draf1 §10), chaque article conserve la
 * trace de son origine : source, lot d'import et date.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core;

  var LOT_IMPORT = {
    source: 'SAGE_100_GESTION_COMMERCIALE_15.01',
    document: 'Inventaire : Grand Stock',
    dateArrete: '2026-07-15',
    dateTirage: '2026-07-15T13:25:18',
    devise: 'F CFA',
    valorisation: 'CMUP',
    reference: 'IMPORT-SAGE-20260715',
    totalArticles: 175,
    totalUnites: 12080,
    totalValorise: 3976459,
    valideePar: null,
  };

  /* --------------------------------------------------------------------------
   * Inventaire Grand Stock — [référence, désignation, quantité, P.R. unitaire, catégorie]
   * Le P.R. unitaire est le coût unitaire moyen pondéré calculé par SAGE.
   * Une valeur nulle signale un article non valorisé dans le document source.
   * ----------------------------------------------------------------------- */
  var LIGNES_SAGE = [
    ['ABA', 'ABAISSE LANGUE', 2, 0, 'conso_medical'],
    ['ACC', 'ACCUZON', 50, 1000, 'medicament'],
    ['ACE', 'ACE MISO 200 µg 1 CP', 24, 250, 'medicament'],
    ['ACU', 'ACUPAN 20 MG INJ', 50, 650, 'medicament'],
    ['ADRE', 'ADRENALINE 1 MG INJ (EPINEPHRINE)', 5, 0, 'medicament'],
    ['AIG', 'AIGUILLE DE PL', 52, 53, 'conso_medical'],
    ['ALC', 'ALCOOL', 8, 0, 'conso_medical'],
    ['ALE', 'ALESE ABSORBANT', 25, 11, 'conso_medical'],
    ['AMI', 'AMINOPHYLLINE 250 MG INJ', 140, 500, 'medicament'],
    ['ANT', 'ANTISEPTIQUE', 76, 0, 'conso_medical'],
    ['ART120', 'ARTESUNATE 120 MG INJ', 5, 2200, 'medicament'],
    ['ARTE60', 'ARTESUNATE 60 MG INJ', 40, 1084, 'medicament'],
    ['ATR', 'ATROPINE 1MG INJ', 30, 1000, 'medicament'],
    ['BAN', 'BANDE VELPEAU', 24, 700, 'conso_medical'],
    ['BANE', 'BANDE ELASTIQUE', 24, 300, 'conso_medical'],
    ['BANG', 'BANDE A GAZ', 14, 263, 'conso_medical'],
    ['BAV', 'BAVETTE/MASQUE CHIRURGICAL', 77, 0, 'conso_medical'],
    ['BEC', 'BECTACEF 1G INJ', 14, 2350, 'medicament'],
    ['BEN', 'BENZATHINE PENICILLINE 2.4MUI INJ', 60, 1150, 'medicament'],
    ['BIP10', 'BILPATRIX 10 CM', 3, 1900, 'conso_medical'],
    ['BIP15', 'BIPLATRIX 15 CM', 3, 2700, 'conso_medical'],
    ['BIP20', 'BIPLATRIX 20 CM', 1, 2040, 'conso_medical'],
    ['BOIT', 'BOITE DE SECURITE', 75, 0, 'conso_medical'],
    ['BT', 'BETADINE JAUNE 500ML', 26, 0, 'conso_medical'],
    ['BUP', 'BUPIVACAINE HYPERBARE/4ML', 50, 0, 'medicament'],
    ['CACL', 'CACL 1 G INJ', 250, 500, 'medicament'],
    ['CAF', 'CAFEINE 50 MG INJ', 8, 591, 'medicament'],
    ['CALO', 'CALOT', 10, 0, 'conso_medical'],
    ['CAN2', 'CANNULE DE GUEDELE N°2', 4, 500, 'conso_medical'],
    ['CANG3', 'CANUL DE GUEDEL 3', 5, 500, 'conso_medical'],
    ['CANG4', 'CANUL DE GUEDEL 4', 6, 600, 'conso_medical'],
    ['CANG5', 'CANNUL DE GUEDELLE N°5', 4, 500, 'conso_medical'],
    ['CANG6', 'CANUL DE GUEDEL 6', 2, 500, 'conso_medical'],
    ['CAR', 'CARTABLE D’ECHOGRAPHIE', 10, 0, 'fourniture'],
    ['CARR', 'CARTABLE DE RADIOLOGIE', 40, 0, 'fourniture'],
    ['CAS', 'CASAQUE RENFORCEE', 2, 3173, 'conso_medical'],
    ['CATA', 'CATAPRESSAN 0.15 MG INJ', 50, 750, 'medicament'],
    ['CATH', 'CATHETHER G', 330, 150, 'conso_medical'],
    ['CEF', 'CEFOTAXIME 1000 MG INJ', 7, 2900, 'medicament'],
    ['CHA', 'CHAMPS ABDOMINAL', 6, 76, 'conso_medical'],
    ['CHLG', 'CHLORXY-G GEL', 5, 1400, 'medicament'],
    ['CIP', 'CIPLOX 200 MG INJ', 120, 650, 'medicament'],
    ['CM', 'CARNET DE MATERNITE', 150, 100, 'fourniture'],
    ['COM30', 'COMPRESSE STERILE 30X30', 20, 100, 'conso_medical'],
    ['COM4', 'COMPRESSE NON STERILE BTE DE 100', 4, 1826, 'conso_medical'],
    ['COM40', 'COMPRESSE STERILE 40X40', 500, 150, 'conso_medical'],
    ['CONEB', 'CONE BLEU', 4, 2200, 'conso_medical'],
    ['CONEJ', 'CONE JAUNE', 4, 2200, 'conso_medical'],
    ['COT', 'COTON HYDROPHYLE 500 G', 1, 0, 'conso_medical'],
    ['COT2', 'COTON CARDE', 11, 0, 'conso_medical'],
    ['CS', 'CARNET DE SOINS', 102, 100, 'fourniture'],
    ['CSL', 'CARNET DE SANTE DE L’ENFANT', 5, 300, 'fourniture'],
    ['DEX', 'DEXAMETHASONE 4 MG INJ', 310, 350, 'medicament'],
    ['DIA', 'DIAZEPAM 10 MG INJ', 10, 166, 'medicament'],
    ['DIC', 'DICLOFENAC 75 MG INJ', 30, 145, 'medicament'],
    ['DIU', 'DIU/STERILET', 94, 100, 'petit_materiel'],
    ['DRAR12', 'DRAIN DE REDON N°12', 3, 5000, 'conso_medical'],
    ['DRAR16', 'DRAIN DE REDON N°16', 3, 2188, 'conso_medical'],
    ['DRAR18', 'DRAIN DE REDON N°18', 2, 5000, 'conso_medical'],
    ['ECO', 'ECOUVILLON', 100, 0, 'conso_labo'],
    ['EPH', 'EPHEDRINE 30 MG INJ', 40, 0, 'medicament'],
    ['EPI23', 'EPIPLEX G23', 76, 51, 'conso_medical'],
    ['EXA', 'EXACYL 0.5 G INJ', 20, 750, 'medicament'],
    ['FIC', 'FICHE D’OBSERVATION', 62, 2, 'fourniture'],
    ['FILTA', 'FILTRE ANTI BACTERIEN ADULTE', 12, 2000, 'conso_medical'],
    ['FILTE', 'FILTRE ANTI BACTERIEN ENFANT', 2, 2000, 'conso_medical'],
    ['FLA', 'FLAGYL 500 MG INJ', 20, 700, 'medicament'],
    ['FORL', 'FORLAX SACHET', 10, 200, 'medicament'],
    ['G10.250', 'SERUM GLUCOSE 10% 250 ML', 15, 550, 'medicament'],
    ['G5.250', 'SERUM GLUCOSE 5% 250 ML', 20, 600, 'medicament'],
    ['G5.500', 'SERUM GLUCOSE 5% 500 ML', 90, 550, 'medicament'],
    ['GANR', 'GANT DE REVISION UTERINE 1 UNITE', 100, 114, 'conso_medical'],
    ['GELE', 'GEL ECHO', 2, 0, 'conso_medical'],
    ['GEN', 'GENTAMICINE 80 MG INJ', 100, 150, 'medicament'],
    ['GENC', 'GENTA COLLYRE', 3, 852, 'medicament'],
    ['GL', 'GANT D’EXAMEN 1 PAIRE', 2200, 25, 'conso_medical'],
    ['GLYR', 'GLYCEMIE CAPILLAIRE', 100, 1000, 'reactif'],
    ['GSACH', 'GANT EN SACHET', 17, 214, 'conso_medical'],
    ['HAL', 'HALDOL 5 MG INJ', 5, 250, 'medicament'],
    ['HBB', 'HBB 20 MG INJ', 60, 166, 'medicament'],
    ['HEMOC', 'HEMOGLOBINE CAPILLAIRE', 100, 1024, 'reactif'],
    ['HEPAD', 'HEPARINE 1CC INJ', 23, 595, 'medicament'],
    ['ISF', 'ISOFLURANE', 6, 778, 'medicament'],
    ['JAV', 'EAU DE JAVEL EN POUDRE', 3, 0, 'entretien'],
    ['JER10', 'JERSEY 10 CM BTE', 12, 650, 'conso_medical'],
    ['KCL', 'KCL 1 G INJ', 50, 300, 'medicament'],
    ['KET', 'KETAMINE 50MG/ML 10ML INJ', 5, 3961, 'medicament'],
    ['LAC', 'LACTIV SOL 200ML', 3, 0, 'entretien'],
    ['LAM', 'LAME DE BISTOURIS', 100, 100, 'conso_medical'],
    ['LAME', 'LAME PORTE OBJET B/72', 2, 600, 'conso_labo'],
    ['LAMEL', 'LAMELLE COUVRE OBJET B/100', 10, 0, 'conso_labo'],
    ['LAS', 'LASILIX/FUROSEMIDE 20 MG INJ', 114, 124, 'medicament'],
    ['LID', 'LIDOCAINE 1CC INJ', 795, 25, 'medicament'],
    ['LID2', 'LIDOCAINE 2% INJ', 15, 158, 'medicament'],
    ['LOX', 'LOXEN /NICARDIPINE 50 MG INJ', 15, 1400, 'medicament'],
    ['LUNA', 'LUNETTE D’O2 ADULTE', 14, 603, 'conso_medical'],
    ['LUNE', 'LUNETTE D’O2 ENFANT', 19, 671, 'conso_medical'],
    ['MAGN', 'MAGNESIUM 1.5 G/10 ML INJ', 7, 226, 'medicament'],
    ['MAN20', 'MANITOL 20% FL/500ML', 3, 0, 'medicament'],
    ['MASA', 'MASQUE FACIAL D’O2 ADULTE', 8, 2250, 'conso_medical'],
    ['MASB', 'MASQUE FACIAL BEBE', 12, 0, 'conso_medical'],
    ['MASE', 'MASQUE FACIAL D’O2 ENFANT', 11, 2250, 'conso_medical'],
    ['MCG', 'MICROGYNON', 40, 500, 'medicament'],
    ['MERS3', 'MERSITURE N°03', 2, 0, 'conso_medical'],
    ['MOR', 'MORPHINE 10 MG INJ', 30, 1270, 'medicament'],
    ['NACL', 'NACL 1 G INJ', 200, 100, 'medicament'],
    ['NOR', 'NORISTERAT/LAAFIA INJ', 24, 450, 'medicament'],
    ['NOV2.5', 'NOVALGIN 2.5 G INJ', 700, 700, 'medicament'],
    ['NOV5', 'NOVALGIN 500 MG INJ', 300, 300, 'medicament'],
    ['OMO', 'OMO SACHET', 111, 0, 'entretien'],
    ['OMP', 'OMEPRAZOLE/CAPRAZOLE 40MG INJ', 50, 2700, 'medicament'],
    ['ORD', 'ORDONANCIER', 28, 587, 'fourniture'],
    ['PAR1', 'PARACETAMOL 1G INJ', 200, 1350, 'medicament'],
    ['PEN1', 'PENI G 1 MUI INJ', 50, 500, 'medicament'],
    ['PERF', 'PERFUSEUR', 51, 150, 'conso_medical'],
    ['PH', 'PAPIER HYGIENIQUE', 21, 0, 'entretien'],
    ['PHE200', 'PHENOBARBITAL 200 MG INJ', 11, 729, 'medicament'],
    ['POC', 'POCHE D’URINE', 50, 416, 'conso_medical'],
    ['POCS', 'POCHE DE STOMIE', 11, 5000, 'conso_medical'],
    ['PRIM', 'PRIMPERAN 10 MG INJ', 500, 150, 'medicament'],
    ['PROA', 'PROTECTION ADULTE', 40, 1000, 'conso_medical'],
    ['PROP', 'PROPOFOL 200MG/20ML', 10, 266, 'medicament'],
    ['PROS', 'PROKEFEN SUPPO', 60, 175, 'medicament'],
    ['PROSG', 'PROSTIGMINE 0.5MG/1ML S INJ', 5, 0, 'medicament'],
    ['RL', 'RINGER LACTATE 500 ML', 90, 650, 'medicament'],
    ['ROBA', 'ROBINET D’ARRET 03 VOIES', 45, 100, 'conso_medical'],
    ['SACH100', 'SACHET POUBELLE 100 L', 147, 0, 'entretien'],
    ['SACH50', 'SACHET POUBELLE 50 L', 4, 0, 'entretien'],
    ['SACN5', 'SACHET NOIR 5F', 8, 0, 'entretien'],
    ['SAL', 'SALBUTAMOL 0.5 MG INJ', 30, 194, 'medicament'],
    ['SAP10', 'SONDE D’ASPIRATION N°10', 5, 250, 'conso_medical'],
    ['SAP12', 'SONDE D’ASPIRATION N°12', 21, 500, 'conso_medical'],
    ['SAP14', 'SONDE D’ASPIRATION N°14', 15, 475, 'conso_medical'],
    ['SAP16', 'SONDE D’ASPIRATION N°16', 13, 424, 'conso_medical'],
    ['SAP6', 'SONDE D’ASPIRATION N°06', 1, 396, 'conso_medical'],
    ['SAP8', 'SONDE D’ASPIRATION N°08', 5, 250, 'conso_medical'],
    ['SAV', 'SAVON LIQUIDE 1 LITRE ET DEMI', 1, 0, 'entretien'],
    ['SAY', 'SAYANA PRESS', 10, 200, 'medicament'],
    ['SB', 'SERUM BICABONATE 1.4 % 500 ML', 3, 0, 'medicament'],
    ['SER', 'SERENATAL CP', 60, 0, 'medicament'],
    ['SNG14', 'SONDE NASOGASTRIQUE N°14', 18, 700, 'conso_medical'],
    ['SNG16', 'SONDE NASOGASTRIQUE N°16', 4, 700, 'conso_medical'],
    ['SNG18', 'SONDE NASOGASTRIQUE N°18', 8, 550, 'conso_medical'],
    ['SNG6', 'SONDE NASOGASTRIQUE N°06', 5, 700, 'conso_medical'],
    ['SNG8', 'SONDE NASOGASTRIQUE N°08', 21, 700, 'conso_medical'],
    ['SOL10', 'SOLVANT 10 ML INJ', 200, 100, 'medicament'],
    ['SPA', 'SPASFON 40 MG INJ', 12, 538, 'medicament'],
    ['SPAR/14', 'SPARADRAP 1/4', 4, 1709, 'conso_medical'],
    ['SPARV', 'SPARADRAP PVV', 80, 200, 'conso_medical'],
    ['SPE', 'SPECULUM VAGINAL', 16, 499, 'conso_medical'],
    ['SS5', 'SERUM SALE 0.9% 500 ML', 120, 650, 'medicament'],
    ['SUI', 'SERINGUE A INSULINE 1ML', 6, 148, 'conso_medical'],
    ['SUU10', 'SERINGUE 10 CC', 100, 100, 'conso_medical'],
    ['SUU20', 'SERINGUE 20 CC', 5, 200, 'conso_medical'],
    ['SUU50', 'SERINGUE 50 CC', 77, 496, 'conso_medical'],
    ['SV2/14', 'SONDE VESICALE 02 VOIES N°14', 20, 700, 'conso_medical'],
    ['SV2V12', 'SONDE VESICALE 2 VOIES N°12', 10, 700, 'conso_medical'],
    ['SV2V16', 'SONDE VESICALE 02 VOIES N°16', 9, 571, 'conso_medical'],
    ['SV2V18', 'SONDE VESICALE 2 VOIES N°18', 10, 700, 'conso_medical'],
    ['SV2V8', 'SONDE VESICALE 2 VOIES N°8', 10, 393, 'conso_medical'],
    ['SV3V18', 'SONDE VESICALE 3 VOIES N°18', 5, 1500, 'conso_medical'],
    ['SV3V20', 'SONDE VESICALE 3 VOIES N°20', 9, 1500, 'conso_medical'],
    ['SV3V22', 'SONDE VESICALE 3 VOIES N°22', 4, 1219, 'conso_medical'],
    ['SV3VS20', 'SONDE VESICALE SILICONE 03 VOIES N°20', 2, 3000, 'conso_medical'],
    ['TBG', 'TBG URINAIRE', 60, 1001, 'reactif'],
    ['TIC', 'TICKET DE CAISSE', 22, 0, 'fourniture'],
    ['TRAM', 'TRAMAGEN 100 MG INJ', 160, 549, 'medicament'],
    ['TROC', 'TROUSSE DE CESARIENNE', 4, 10000, 'conso_medical'],
    ['TROU', 'TROUSSE UNIVERSEL', 6, 15000, 'conso_medical'],
    ['TUBAK', 'TUBE AKOP', 179, 0, 'conso_labo'],
    ['TUBEB', 'TUBE BOUCHON BLEU', 2, 2500, 'conso_labo'],
    ['TUBEC', 'TUBE BOUCHON CENDRE', 1, 4206, 'conso_labo'],
    ['TUBECB', 'TUBE ECBU', 81, 0, 'conso_labo'],
    ['TUBER', 'TUBE BOUCHON ROUGE PLASTIC', 2, 849, 'conso_labo'],
    ['TUBER2', 'TUBE BOUCHON ROUGE EN VERRE', 3, 3400, 'conso_labo'],
    ['TUBEV', 'TUBE BOUCHON VIOLET', 2, 839, 'conso_labo'],
    ['VEC', 'VECURO-M', 8, 1350, 'medicament'],
    ['VIC.0', 'FIL VICRYL 0', 1, 2250, 'conso_medical'],
    ['VIC1', 'FIL VICRYL 1', 24, 2250, 'conso_medical'],
    ['VIC2', 'FIL VICRYL 2', 36, 2250, 'conso_medical'],
    ['VIC2.0', 'FIL VICRYL 2/0', 36, 2250, 'conso_medical'],
    ['VITB2', 'VITAMINE B/C 2 ML INJ', 100, 300, 'medicament'],
    ['VITC', 'VITAMINE C 500 MG INJ', 225, 160, 'medicament'],
    ['VITK', 'VITAMINE K1 10 MG INJ', 50, 250, 'medicament'],
  ];

  /* --------------------------------------------------------------------------
   * P.R. global relevé sur le document, référence par référence.
   * SAGE arrondit le prix unitaire affiché mais conserve la valeur exacte au
   * global : c'est donc cette colonne qui fait foi pour la valorisation, et le
   * coût unitaire moyen pondéré en est déduit. Sans cela, la somme des
   * quantités × prix unitaires arrondis s'écarte du total du document.
   * ----------------------------------------------------------------------- */
  var PR_GLOBAL = {
    ABA: 0, ACC: 49996, ACE: 6000, ACU: 32500, ADRE: 0, AIG: 2740, ALC: 0, ALE: 268,
    AMI: 70000, ANT: 16, ART120: 11000, ARTE60: 43345, ATR: 30000, BAN: 16800, BANE: 7200,
    BANG: 3682, BAV: 0, BEC: 32900, BEN: 69000, BIP10: 5700, BIP15: 8100, BIP20: 2040,
    BOIT: 0, BT: 0, BUP: 1, CACL: 124996, CAF: 4728, CALO: 0, CAN2: 2000, CANG3: 2500,
    CANG4: 3600, CANG5: 2000, CANG6: 1000, CAR: 0, CARR: 0, CAS: 6346, CATA: 37500,
    CATH: 49500, CEF: 20300, CHA: 454, CHLG: 7000, CIP: 77999, CM: 15000, COM30: 1990,
    COM4: 7302, COM40: 74954, CONEB: 8799, CONEJ: 8799, COT: 0, COT2: 0, CS: 10190,
    CSL: 1500, DEX: 108356, DIA: 1660, DIC: 4340, DIU: 9400, DRAR12: 15000, DRAR16: 6564,
    DRAR18: 10000, ECO: 0, EPH: 0, EPI23: 3845, EXA: 14999, FIC: 110, FILTA: 24000,
    FILTE: 4000, FLA: 13995, FORL: 2000, 'G10.250': 8245, 'G5.250': 11996, 'G5.500': 49500,
    GANR: 11400, GELE: 0, GEN: 15000, GENC: 2556, GL: 55243, GLYR: 100000, GSACH: 3631,
    HAL: 1250, HBB: 9940, HEMOC: 102400, HEPAD: 13685, ISF: 4666, JAV: 0, JER10: 7800,
    KCL: 15000, KET: 19805, LAC: 0, LAM: 10040, LAME: 1200, LAMEL: 0, LAS: 14122,
    LID: 19882, LID2: 2375, LOX: 21000, LUNA: 8440, LUNE: 12757, MAGN: 1582, MAN20: 0,
    MASA: 18000, MASB: 0, MASE: 24750, MCG: 20000, MERS3: 0, MOR: 38102, NACL: 20000,
    NOR: 10800, 'NOV2.5': 489897, NOV5: 90000, OMO: 0, OMP: 135000, ORD: 16434,
    PAR1: 269996, PEN1: 25000, PERF: 7647, PH: 0, PHE200: 8019, POC: 20820, POCS: 55000,
    PRIM: 75000, PROA: 40000, PROP: 2660, PROS: 10500, PROSG: 0, RL: 58499, ROBA: 4500,
    SACH100: 0, SACH50: 0, SACN5: 0, SAL: 5824, SAP10: 1250, SAP12: 10500, SAP14: 7125,
    SAP16: 5512, SAP6: 396, SAP8: 1250, SAV: 0, SAY: 2000, SB: 0, SER: 0, SNG14: 12600,
    SNG16: 2800, SNG18: 4400, SNG6: 3500, SNG8: 14700, SOL10: 20000, SPA: 6460,
    'SPAR/14': 6834, SPARV: 15987, SPE: 7990, SS5: 78000, SUI: 890, SUU10: 10000,
    SUU20: 1000, SUU50: 38226, 'SV2/14': 14000, SV2V12: 7000, SV2V16: 5140, SV2V18: 7000,
    SV2V8: 3930, SV3V18: 7500, SV3V20: 13500, SV3V22: 4876, SV3VS20: 6000, TBG: 60034,
    TIC: 0, TRAM: 87810, TROC: 40000, TROU: 90000, TUBAK: 0, TUBEB: 5000, TUBEC: 4206,
    TUBECB: 0, TUBER: 1698, TUBER2: 10200, TUBEV: 1678, VEC: 10800, 'VIC.0': 2250,
    VIC1: 54000, VIC2: 81000, 'VIC2.0': 81000, VITB2: 30000, VITC: 35940, VITK: 12500,
  };

  var INVENTAIRE_SAGE = LIGNES_SAGE.map(function (a) {
    var code = a[0], quantite = a[2], prUnitaire = a[3];
    var prGlobal = PR_GLOBAL[code] != null ? PR_GLOBAL[code] : quantite * prUnitaire;
    return {
      code: code, designation: a[1], quantite: quantite,
      /* Prix unitaire tel qu'imprimé par SAGE (arrondi). */
      prUnitaire: prUnitaire,
      /* Valeur du document — référence pour la valorisation du stock. */
      prGlobal: prGlobal,
      /* CMUP exact déduit du global : quantité × cump = prGlobal. */
      cump: quantite ? prGlobal / quantite : prUnitaire,
      categorie: a[4],
      valorise: prGlobal > 0,
    };
  });

  /* --------------------------------------------------------------------------
   * Catalogue tarifaire — 144 désignations du document
   * « Tarifs des médicaments et accessoires médicaux ».
   * ----------------------------------------------------------------------- */
  var CATALOGUE_TARIFS = [
    'ACCUZON 1 G INJ', 'ACE-MISO', 'AMINOPHILLINE 250 MG INJ', 'AMPICILLINE 0,5 G INJ',
    'AMPICILLINE 1 G INJ', 'ARTESUNATE 120 MG INJ', 'ARTESUNATE 30 MG INJ', 'ARTESUNATE 60 MG INJ',
    'ASPEGIC 0,5 G INJ', 'ASPEGIC 1 G INJ', 'ATROPINE 1 MG INJ', 'BANDE A GAZ', 'BANDE VELPEAU',
    'BENZATHINE PENICILLINE 2,4 MUI INJ', 'BETACEF 1 G INJ', 'BIPLATRIX 10 CM', 'BIPLATRIX 15 CM',
    'BIPLATRIX 20 CM', 'CAFEINE 50 MG INJ', 'CACL 10 ML INJ', 'CATAPRESSAN 0,15 MG INJ',
    'CATHETER G16', 'CATHETER G18', 'CATHETER G20', 'CATHETER G22', 'CATHETER G24',
    'CELESTENE 4 MG INJ', 'CLOXACILLINE 1 G INJ', 'CORDARONE 150 MG INJ', 'CTA P12', 'CTA P18',
    'CTA P24', 'CTA P6', 'DEXAMETHASONE 4 MG INJ', 'DIAZEPAM 10 MG INJ', 'DICLOFENAC 75 MG INJ',
    'DICYNONE 250 MG INJ', 'DIGOXINE 0,5 MG INJ', 'DISLEP 25 MG INJ', 'DIU /STERILET',
    'DOBUTAMINE 250 MG INJ', 'EPHEDRINE 30 MG INJ', 'EPIPLEX G21', 'ERGOMETRINE 1 MG INJ',
    'ETHILON 0', 'ETHILON 1', 'ETHILON 2/0', 'ETHILON 3/0', 'EXACYL 0,5 G INJ', 'GANT STERILE',
    'GASPRAL (OMEPRAZOLE) 40 MG INJ', 'GELOFUSINE 4 % (GELATINE) 500 ML INJ', 'GENTAMICINE 80 INJ',
    'GLUCOSE 10 % 250 ML INJ', 'GLUCOSE 10 % 500 ML INJ', 'GLUCOSE 5 % 250 ML INJ',
    'GLUCOSE 5 % 500 ML INJ', 'GLYCEMIE CAPILLAIRE', 'HALDOL DECANOAS 50 MG INJ', 'HBB 20 MG INJ',
    'HEMOGLOBINE CAPILLAIRE', 'HEPARINE 5000 UI INJ', 'IMUCLAV 1G INJ',
    'ISOSORBIDE (RISORDAN) 10 MG INJ', 'JADELLE', 'JERSEY 10 CM', 'JERSEY 15 CM', 'KCL 10 ML INJ',
    'LAME DE BISTOURIS', 'LASILIX 20 MG INJ', 'LASILIX 250 MG INJ (SPECIALITE)', 'LOXEN 10 MG INJ',
    'LUNETTE D’O2 ADULTE', 'LUNETTE D’O2 ENFANT', 'MAGNESIUM INJ', 'MASQUE D’O2 ADULTE',
    'MASQUE D’O2 ENFANT', 'MERSUTURE 1', 'MERSUTURE 2', 'MERSUTURE 3', 'MIILDA', 'MORPHINE 10 MG INJ',
    'NACL 10 ML INJ', 'NORISTERAT INJ', 'NOVALGIN 2,5 G INJ', 'NOVALGIN 500 MG INJ',
    'OXYTOCIN 10 UI INJ', 'PACTH DE TRINITRINE 10 MG', 'PACTH DE TRINITRINE 5 MG (DISCORTINE)',
    'PERFALGAN 0,5 G INJ', 'PERFUSION DE PERFALGAN 1 G INJ', 'PHENOBARBITAL 200 MG INJ',
    'PHENOBARBITAL 40 MG INJ', 'POCHE D’URINE', 'PRIMPERAN INJ', 'PROLENE 0', 'PROLENE 1',
    'PROLENE 2/0', 'PROLENE 3/0', 'PROLENE 4/0', 'PROTECTION ADULTE', 'RENNIXIA 20 MG INJ',
    'RINGER 500 ML INJ', 'SALBUTAMOL INJ', 'SAT 1500 UI INJ', 'SAYANA PRESS',
    'SERUM BICARBONATE 1,4% 500 ML INJ', 'SERUM SALE 0,9 % 1 L INJ', 'SERUM SALE 0,9 % 500 ML INJ',
    'SONDE NASO-GASTRIQUE N°10', 'SONDE NASO-GASTRIQUE N°12', 'SONDE NASO-GASTRIQUE N°14',
    'SONDE NASO-GASTRIQUE N°16', 'SONDE NASO-GASTRIQUE N°18', 'SONDE NASO-GASTRIQUE N°8',
    'SONDE VESICALE 2 VOIES N°10', 'SONDE VESICALE 2 VOIES N°12', 'SONDE VESICALE 2 VOIES N°14',
    'SONDE VESICALE 2 VOIES N°16', 'SONDE VESICALE 2 VOIES N°18', 'SONDE VESICALE 2 VOIES N°20',
    'SONDE VESICALE 2 VOIES N°22', 'SONDE VESICALE 2 VOIES N°8', 'SONDE VESICALE 3 VOIES N°18',
    'SONDE VESICALE 3 VOIES N°20', 'SONDE VESICALE 3 VOIES N°22', 'SONDE VESICALE 3 VOIES N°24',
    'SPARADRAP', 'SPASFON 40 MG INJ', 'SPECULUM JETABLE', 'TANGANIL 500 MG INJ',
    'TRAMAGEN 100 MG INJ', 'VACCIN HEPATITE B INJ', 'VICRYL 0', 'VICRYL 1', 'VICRYL 2', 'VICRYL 2/0',
    'VICRYL 3/0', 'VICRYL 4/0', 'VIT B COMPLEX 10 ML INJ', 'VIT B COMPLEX 2 ML INJ',
    'VITAMINE C 500 MG INJ', 'VITAMINE K1 10 MG INJ', 'VOGALENE 10 MG INJ',
  ].map(function (d, i) {
    return { n: i + 1, designation: d, prix: null, tarifARenseigner: true };
  });

  /* --------------------------------------------------------------------------
   * Unité de conditionnement déduite de la désignation.
   * ----------------------------------------------------------------------- */
  function uniteDe(designation) {
    var d = designation.toUpperCase();
    if (/\bB(TE|\/)\s*\d|BOITE|SACHET|BTE DE/.test(d)) return 'Boîte';
    if (/\d+\s*ML\b|\d+\s*L\b|500 ML|250 ML/.test(d) && /SERUM|GLUCOSE|RINGER|SALE|BICABONATE|MANITOL/.test(d)) return 'Poche';
    if (/\bINJ\b|AMPOULE/.test(d)) return 'Ampoule';
    if (/\bCP\b|COMPRIME/.test(d)) return 'Comprimé';
    if (/GEL|COLLYRE|FLACON|SOL\b|LIQUIDE|ALCOOL|BETADINE|ISOFLURANE|JAVEL/.test(d)) return 'Flacon';
    if (/PAIRE/.test(d)) return 'Paire';
    if (/BANDE|SPARADRAP|JERSEY/.test(d)) return 'Rouleau';
    if (/CARNET|FICHE|ORDONANCIER|TICKET|CARTABLE/.test(d)) return 'Unité';
    return 'Unité';
  }

  /* Seuil d'alerte : absent du document source, proposé à 20 % du stock relevé
     (minimum 5) et à valider article par article par la clinique. */
  function seuilPropose(quantite) {
    return Math.max(5, Math.round(quantite * 0.2));
  }

  global.SIGH.sage = {
    LOT_IMPORT: LOT_IMPORT,
    INVENTAIRE_SAGE: INVENTAIRE_SAGE,
    CATALOGUE_TARIFS: CATALOGUE_TARIFS,
    uniteDe: uniteDe,
    seuilPropose: seuilPropose,
    /** Rapproche le catalogue tarifaire et l'inventaire, par désignation normalisée. */
    rapprochement: function () {
      function cle(s) {
        return C.norm(s).replace(/[^a-z0-9]/g, '');
      }
      var index = {};
      INVENTAIRE_SAGE.forEach(function (a) { index[cle(a.designation)] = a; });
      return CATALOGUE_TARIFS.map(function (t) {
        var exact = index[cle(t.designation)];
        var approche = exact || INVENTAIRE_SAGE.filter(function (a) {
          var ka = cle(a.designation), kt = cle(t.designation);
          return ka.indexOf(kt.slice(0, 10)) === 0 || kt.indexOf(ka.slice(0, 10)) === 0;
        })[0];
        return {
          n: t.n, designation: t.designation,
          article: approche ? approche.code : null,
          designationStock: approche ? approche.designation : null,
          cump: approche && approche.prUnitaire ? approche.prUnitaire : null,
          correspondance: exact ? 'exacte' : (approche ? 'approchée' : 'absente'),
        };
      });
    },
  };
})(window);
