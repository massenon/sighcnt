import '../../mere/client_mere.dart';

/// SOURCE DES ÉCRANS DE LA CONSOLE MÈRE (mere-supervision, appareils, conflits, à traiter, journal des opérations, plages et baux, lots).
///
/// Les écrans ne parlent pas au réseau : ils lisent cette interface, que les tests remplacent par un faux sans réseau. Deux sortes de lecture :
///  - celles que le moteur de synchronisation (`packages/sync_dart`, routes `/admin/*`) ANNONCE réellement : état, appareils et curseurs,
///    conflits, contrôles de santé, accusés d'un renvoi, dépôt d'un lot ;
///  - celles que le moteur garde en base mais n'expose par AUCUNE route (refus consolidés, journal des opérations, plages, baux, lots déposés) :
///    elles rendent `null`, et l'écran dit « non disponible » au lieu d'inventer une valeur. `null` n'est pas une liste vide : une liste vide
///    se lit « rien à signaler », `null` se lit « la mère ne le dit pas ».
abstract class SourceMra {
  Future<EtatMere> etat();
  Future<Supervision> supervision();
  Future<List<Conflit>> tousLesConflits();
  Future<void> trancher(int id, String decision);
  Future<void> sauvegarderMaintenant();
  Future<String> codeAppareil(String etiquette);
  Future<({String code, String cle})> codeMobile(String etiquette, {required String profil, String? fonction});
  Future<void> revoquer(String uuid);
  Future<void> debloquer(String uuid);
  Future<void> renvoyerATous();

  /// Dépose un lot de tournée pour un mobile : rend le nombre de fiches RETENUES par la mère (une fiche inconnue d'elle est écartée).
  Future<int> composerLot(
      {required String uuid,
      required List<({String collection, String id})> fiches,
      int? dureeMs});

  /// Lectures que le moteur n'expose pas (voir l'en-tête) : `null` = non disponible.
  Future<List<RefusMra>?> refus();
  Future<List<OperationMra>?> operations();
  Future<PlagesBauxMra?> plagesEtBaux();
  Future<List<LotMra>?> lots();
}

/// Une opération REFUSÉE par la mère, telle que son accusé la nomme (code, motif, geste de correction).
class RefusMra {
  const RefusMra(
      {required this.appareil,
      required this.operation,
      required this.code,
      required this.motif,
      required this.geste,
      required this.quand});
  final String appareil;
  final String operation;
  final String code;
  final String motif;
  final String geste;
  final DateTime quand;
}

/// Une ligne du journal des opérations : la séquence est posée par la mère, jamais par l'horloge d'un poste.
/// `quand` est nul quand le moteur ne date pas l'opération avec une horloge de confiance.
class OperationMra {
  const OperationMra(
      {required this.seq,
      required this.appareil,
      required this.type,
      required this.collection,
      required this.fiche,
      this.quand});
  final int seq;
  final DateTime? quand;
  final String appareil;
  final String type;
  final String collection;
  final String fiche;
}

/// Plage de codes patients réservée à un appareil. `restants` et `epuisee` sont nuls tant que le moteur ne dit pas combien de numéros
/// l'appareil a consommés (il ne garde que les bornes).
class PlageMra {
  const PlageMra(
      {required this.appareil,
      required this.debut,
      required this.fin,
      this.restants});
  final String appareil;
  final int debut;
  final int fin;
  final int? restants;
}

/// Bail de stock par article. `alloue` et `consomme` sont nuls quand le moteur ne garde que le reste.
class BailMra {
  const BailMra(
      {required this.appareil,
      required this.article,
      required this.restant,
      this.alloue,
      this.consomme});
  final String appareil;
  final String article;
  final num restant;
  final num? alloue;
  final num? consomme;
}

class PlagesBauxMra {
  const PlagesBauxMra(
      {required this.plages, required this.baux, this.provisoires});
  final List<PlageMra> plages;
  final List<BailMra> baux;

  /// Numéros PROV- à réconcilier : nul tant que le moteur ne les compte pas.
  final int? provisoires;
}

/// Un lot de tournée déposé sur un mobile. `tournee` et `saisiesNonParties` sont nuls quand le moteur ne les porte pas.
class LotMra {
  const LotMra(
      {required this.appareil,
      required this.dossiers,
      required this.depose,
      required this.expire,
      this.tournee,
      this.saisiesNonParties});
  final String appareil;
  final String? tournee;
  final int dossiers;
  final DateTime depose;
  final DateTime expire;
  final int? saisiesNonParties;
}

/// Adaptateur sur le service HTTP de la mère (`ClientMere`) : appelle ce que la mère accepte, rend `null` pour ce qu'elle n'expose pas.
class SourceMraClient implements SourceMra {
  SourceMraClient(this.client);
  final ClientMere client;

  @override
  Future<EtatMere> etat() => client.etat();
  @override
  Future<Supervision> supervision() => client.supervision();
  @override
  Future<List<Conflit>> tousLesConflits() => client.tousLesConflits();
  @override
  Future<void> trancher(int id, String decision) =>
      client.trancher(id, decision);
  @override
  Future<void> sauvegarderMaintenant() => client.sauvegarderMaintenant();
  @override
  Future<String> codeAppareil(String etiquette) =>
      client.codeAppareil(etiquette);
  @override
  Future<({String code, String cle})> codeMobile(String etiquette, {required String profil, String? fonction}) =>
      client.codeMobile(etiquette, profil: profil, fonction: fonction);
  @override
  Future<void> revoquer(String uuid) => client.revoquer(uuid);
  @override
  Future<void> debloquer(String uuid) => client.debloquer(uuid);
  @override
  Future<void> renvoyerATous() => client.renvoyerATous();
  @override
  Future<int> composerLot(
          {required String uuid,
          required List<({String collection, String id})> fiches,
          int? dureeMs}) =>
      client.composerLot(uuid: uuid, fiches: fiches, dureeMs: dureeMs);

  // Le moteur garde ces données en base (tables `resultats`, `operations`, `plages`, `baux`, `sortie`) mais n'a aucune route pour les lire.
  @override
  Future<List<RefusMra>?> refus() async => null;
  @override
  Future<List<OperationMra>?> operations() async => null;
  @override
  Future<PlagesBauxMra?> plagesEtBaux() async => null;
  @override
  Future<List<LotMra>?> lots() async => null;
}

/// Source par défaut quand l'écran est monté sans client (tests, aperçus) : la coque d'un poste mère la fournit via `ecransMEREPour`.
class FournisseurMra {
  FournisseurMra._();
  static SourceMra? parDefaut;
}
