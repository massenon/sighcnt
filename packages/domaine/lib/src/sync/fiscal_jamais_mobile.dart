// LA CONFIGURATION FISCALE NE VA JAMAIS VERS UN TÉLÉPHONE (Direction, 16/11/2026, lot FISC-2 ; RG-13). Les obligations et leur historique (avec les paramètres ORTB, liés aux salaires),
// les échéances, les paramètres du calendrier fiscal, les deux barèmes de l'AIB et leurs réglages, les imputations de l'AIB (qui portent un tiers, une base, un compte) sont lus par
// aucun écran du mobile : un téléphone perdu n'emporte ni calendrier fiscal, ni barème, ni imputation. La mère les exclut de ce qu'elle publie à un mobile, le pont les refuse dans un
// lot de tournée et ne les diffuse pas, même dans une portée.
library;

/// Les collections fiscales du poste.
const Set<String> collectionsFiscalesJamaisMobile = {
  'obligationsFiscales',
  'historiqueObligations',
  'echeancesFiscales',
  'parametresFiscaux',
  'situationsAib',
  'baremeAib',
  'reglagesAib',
  'imputationsAib',
};

/// Le code du refus d'un lot de tournée qui nomme l'une d'elles.
const String codeFiscalInterditAuMobile = 'fiscal_interdit_au_mobile';
