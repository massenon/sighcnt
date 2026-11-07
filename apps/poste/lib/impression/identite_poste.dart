import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// L'IDENTITÉ IMPRIMÉE DU POSTE lit le magasin par le domaine : la version de `identiteLegale` en force À LA DATE DE LA PIÈCE (`C.identiteALaDate(date)`
/// de la maquette, Direction 06/11/2026). Sans version au magasin : la semence (`C.BRAND_ORIGINE`). Une facture datée d'hier garde l'en-tête d'hier.
IdentiteImprimee identiteImprimeeDe(Magasin m, DateTime date) => cfbIdentiteImprimee(m.collection('identiteLegale').actives, date);

/// La date d'une fiche (`date`, puis `dateEmission`), sinon la date d'édition.
DateTime datePiece(Map<String, Object?> f, DateTime sinon) {
  for (final k in const ['date', 'dateEmission', 'dateHeure']) {
    final d = DateTime.tryParse('${f[k] ?? ''}');
    if (d != null) return d;
  }
  return sinon;
}
