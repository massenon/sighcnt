import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// LA SATISFACTION EN LIGNE au poste (lot SAT, ADR-0009) : la colle entre le domaine (`qual_en_ligne.dart`) et le registre des paramètres du poste (famille `satisfaction`, défauts semés,
/// versionnés par date, réglage de clinique posé à la mère, jamais vers un téléphone). Aucune valeur ici : tout se LIT à la date.

Object? _valeur(Magasin m, String cle, DateTime jour) {
  final versions = [
    for (final f in m.collection(parCollectionParametres).toutes)
      if ('${f['cle']}' == cle) Parametre.fromJson({...f})
  ];
  final res = Parametres.resoudre(cle, versions, parametreDateIso(jour), definition: definitionDeParametre(cle));
  return res.ok ? res.valeur!.valeur : definitionDeParametre(cle)?.defaut;
}

/// Les points de collecte en vigueur (les sept points de la décision S2 par défaut).
List<({String code, String libelle})> pointsCollectePoste(Magasin m, DateTime jour) => qualPointsDepuisParametre(_valeur(m, qualClePointsCollecte, jour));

/// La collecte en ligne est-elle ouverte ? (désactivée par défaut)
bool collecteEnLignePoste(Magasin m, DateTime jour) => _valeur(m, qualCleEnLigne, jour) == 'oui';

/// L'adresse publique du relais pour les liens et l'affiche.
String adressePubliquePoste(Magasin m, DateTime jour) {
  final v = '${_valeur(m, qualCleAdressePublique, jour) ?? ''}'.trim();
  return v.isEmpty ? qualAdressePubliqueDefaut : v;
}
