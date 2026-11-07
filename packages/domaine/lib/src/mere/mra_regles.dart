/// Règles de la console du poste mère (écrans mere-supervision, appareils, conflits, à traiter, journal, plages, lots).
/// Aucune valeur n'est inventée ici : ces fonctions ne font que LIRE ce que le moteur de synchronisation annonce
/// (séquence, curseurs, accusés, expirations) et le rendre comparable. Tout ce que le moteur ne fournit pas reste `null`.
library;

/// Retard d'un appareil : opérations posées par la mère que son curseur n'a pas encore atteintes. Jamais négatif.
int mraRetard(int seqMax, int derniereSeq) {
  final r = seqMax - derniereSeq;
  return r < 0 ? 0 : r;
}

/// Un appareil est « à jour » quand son curseur a rejoint la séquence courante de la mère.
bool mraAJour(int seqMax, int derniereSeq) => mraRetard(seqMax, derniereSeq) == 0;

/// Âge lisible d'un évènement : « il y a 12 s », « il y a 4 min », « il y a 3 h », « il y a 2 j ». `null` = jamais.
String mraAgeLisible(Duration? d) {
  if (d == null) return 'jamais';
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return 'il y a $s s';
  if (s < 3600) return 'il y a ${s ~/ 60} min';
  if (s < 86400) return 'il y a ${s ~/ 3600} h';
  return 'il y a ${s ~/ 86400} j';
}

/// Accusés d'un « Renvoyer vers tous » : les appareils ACTIFS qui ont acquitté la marque, et ceux qui n'ont pas encore répondu
/// (un poste éteint acquittera à sa reconnexion). Un accusé d'un appareil qui n'est plus actif ne compte pas.
({List<String> recus, List<String> attendus}) mraAccuses(Iterable<String> actifs, Iterable<String> acks) {
  final a = acks.toSet();
  final liste = actifs.toList();
  return (recus: [for (final u in liste) if (a.contains(u)) u], attendus: [for (final u in liste) if (!a.contains(u)) u]);
}

/// État d'un lot de tournée à partir de l'expiration que le moteur a posée dans la charge (`expire`, ms epoch).
String mraEtatLot(int expireMs, int maintenantMs) => maintenantMs >= expireMs ? 'expiré' : 'actif';

/// Nombre de numéros d'une plage [debut, fin] (bornes comprises). Une plage inversée vaut 0, jamais un nombre négatif.
int mraTaillePlage(int debut, int fin) => fin < debut ? 0 : fin - debut + 1;

/// Un doublon possible n'a pas de champ en conflit : le moteur le marque par ce nom de champ réservé.
const mraChampDoublon = 'doublon_possible';

/// Répartition des conflits ouverts : `(champs, doublons)`.
({int champs, int doublons}) mraRepartirConflits(Iterable<String> champsDesConflits) {
  var d = 0, c = 0;
  for (final ch in champsDesConflits) {
    ch == mraChampDoublon ? d++ : c++;
  }
  return (champs: c, doublons: d);
}
