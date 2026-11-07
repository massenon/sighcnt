import 'package:sigh_domaine/sigh_domaine.dart';

import '../../mere/client_mere.dart';

/// SOURCE DES ÉCRANS DE LA CONSOLE MÈRE, LOT (b). Les écrans n'appellent jamais le réseau : ils lisent cette interface, injectable, comme
/// `ClientMere` pour la console et `SourceEtatSync` pour la pastille. Elle ne porte que ce que le moteur de la mère (`packages/sync_dart`)
/// expose réellement ; tout le reste a une implémentation par défaut qui dit « non disponible » (lecture : `null`, geste : [MrbIndisponible]).
/// Une capacité qui apparaît dans le moteur se branche ici, sans toucher aux écrans.

/// Refus nommé d'un geste que le service de la mère ne propose pas (encore). Le motif est affiché tel quel.
class MrbIndisponible implements Exception {
  MrbIndisponible(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

class MrbControle {
  const MrbControle({required this.nom, required this.etat, required this.detail, this.valeur});
  final String nom;

  /// `ok`, `attention`, `alerte` ou `inconnu` : « inconnu » ne rassure jamais.
  final String etat;
  final String detail;

  /// La mesure brute quand le moteur la donne (horodatage de la dernière sauvegarde, retard en opérations…).
  final Object? valeur;
}

class MrbSante {
  const MrbSante({required this.etat, required this.depot, required this.controles});
  final String etat;
  final String depot;
  final List<MrbControle> controles;

  MrbControle? controle(String nom) {
    for (final c in controles) {
      if (c.nom == nom) return c;
    }
    return null;
  }
}

class MrbAppareil {
  const MrbAppareil({required this.uuid, required this.etiquette, required this.role, required this.etat});
  final String uuid;
  final String etiquette;
  final String role;
  final String etat;
  String get nom => etiquette.isEmpty ? uuid : etiquette;
}

/// `GET /admin/etat` : uniquement les champs que le moteur renvoie. `nbOperations`, `repN` et `depot` peuvent manquer (ancienne mère) : `null`.
class MrbEtat {
  const MrbEtat({
    required this.epoch,
    required this.seqMax,
    required this.repSeq,
    required this.reinitOuverte,
    required this.alertes,
    required this.bloques,
    required this.derives,
    required this.appareils,
    this.nbOperations,
    this.repN,
    this.depot,
    this.restauration,
  });
  final int epoch;
  final int seqMax;
  final int repSeq;
  final int? nbOperations;
  final int? repN;
  final String? depot;
  final String? restauration;
  final bool reinitOuverte;
  final List<Map<String, Object?>> alertes;
  final List<String> bloques;
  final List<String> derives;
  final List<MrbAppareil> appareils;

  /// Opérations de la mère pas encore répliquées (chiffrées) vers le relais.
  int get retardRelais => seqMax - repSeq;

  MrbAppareil? appareil(String uuid) {
    for (final a in appareils) {
      if (a.uuid == uuid) return a;
    }
    return null;
  }
}

class MrbSauvegarde {
  const MrbSauvegarde({required this.date, required this.nature, this.tailleOctets, this.verification});
  final DateTime date;
  final String nature;
  final int? tailleOctets;

  /// `null` : jamais vérifiée, ou le service ne le dit pas.
  final String? verification;
}

class MrbEchangeRelais {
  const MrbEchangeRelais({required this.quand, required this.sens, required this.contenu, required this.resultat});
  final DateTime quand;
  final String sens;

  /// Une description des MÉTADONNÉES de l'échange (rang, taille), jamais son contenu : le relais est opaque.
  final String contenu;
  final String resultat;
}

class MrbCodeMobile {
  const MrbCodeMobile({required this.code, required this.payloadQr});
  final String code;

  /// Ce que le QR encode (code + clé de clinique). Réservé au QR : l'écran ne l'affiche JAMAIS en texte.
  final String payloadQr;
}

class MrbResultatReinit {
  const MrbResultatReinit({required this.sauvegarde, this.epoch});
  final String sauvegarde;
  final int? epoch;
}

abstract class MrbSource {
  const MrbSource();

  // --- ce que le moteur expose ---------------------------------------------------------------------------------------------------------------
  Future<MrbEtat> etat();
  Future<MrbSante> supervision();

  /// Les `limite` évènements les plus récents, du plus récent au plus ancien (le moteur plafonne à 500).
  Future<List<MrbLigneJournal>> journal({int limite = 500});

  /// Fiches `patients` actives : le seul décompte que la mère publie au relais.
  Future<int?> patientsActifs();

  /// Rend le chemin du fichier chiffré écrit par la mère.
  Future<String> sauvegarderMaintenant();
  Future<void> debloquer(String uuid);
  Future<void> revoquer(String uuid);
  Future<void> ouvrirFenetreReinit(bool ouvrir);
  Future<MrbResultatReinit> reinitialiser({required String confirmation, required String second});
  Future<MrbCodeMobile> codeMobile(String etiquette, {required String profil, String? fonction});

  /// Le nom de la clinique que le moteur exige en confirmation (`_clinique` dans `mere.dart`).
  String get nomClinique => 'NASSIERA TOO';

  // --- ce que le moteur n'expose pas encore : « non disponible » par défaut -----------------------------------------------------------------
  /// Le catalogue des fichiers de sauvegarde. `null` : le moteur ne les liste pas.
  Future<List<MrbSauvegarde>?> sauvegardes() async => null;

  /// Empreinte SHA-256 de la clé de clinique (64 hexadécimaux). `null` : le moteur ne la publie pas.
  Future<String?> empreinteCle() async => null;
  Future<DateTime?> cleCreeeLe() async => null;

  /// Derniers échanges avec le relais (métadonnées seulement). `null` : le moteur ne tient pas ce journal.
  Future<List<MrbEchangeRelais>?> echanges() async => null;

  /// Dernier battement réussi vers le relais. `null` : le moteur ne l'annonce pas (il le garde dans sa base).
  Future<DateTime?> dernierBattement() async => null;

  Future<void> verifierDerniereSauvegarde() async =>
      throw MrbIndisponible('La vérification de restauration (test à blanc) n’est pas proposée par le service de la mère : '
          'elle exige le fichier chiffré et la clé de clinique, que la console n’a pas.');
  Future<void> imprimerCopiePapier() async =>
      throw MrbIndisponible('La copie papier de la clé ne peut pas être produite depuis la console : le service de la mère n’expose pas la clé. '
          'Elle se fait à l’installation de la mère, devant le détenteur désigné (spec §12).');
  Future<void> tournerCle() async =>
      throw MrbIndisponible('La rotation de la clé n’est pas disponible : elle impose de rechiffrer le relais et de redistribuer la clé à tous les mobiles (spec §12).');
  Future<void> tournerSecretMere() async =>
      throw MrbIndisponible('La rotation du secret de la mère n’est pas disponible dans le service actuel : elle se fait côté relais et côté mère ensemble.');
  Future<void> testerLiaison() async =>
      throw MrbIndisponible('Le test de liaison n’est pas proposé par le service de la mère : la liaison se lit au contrôle « Relais en ligne » de la supervision.');
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Adaptateur sur le service réel (HTTP d'administration)
// ---------------------------------------------------------------------------------------------------------------------------------------------

int _entier(Object? v) => v is num ? v.toInt() : 0;

class MrbSourceClient extends MrbSource {
  const MrbSourceClient(this.client);
  final ClientMere client;

  Future<Map<String, Object?>> _get(String chemin) => client.brut('GET', chemin);

  @override
  Future<MrbEtat> etat() async {
    final j = await _get('/admin/etat');
    if (j['epoch'] is! num || j['seq_max'] is! num) {
      throw ErreurMere(502, 'reponse_inattendue', 'Le service de la mère a répondu sans époque ni rang : réponse ignorée.');
    }
    List<Map<String, Object?>> liste(Object? o) => [for (final x in (o as List? ?? const [])) (x as Map).cast<String, Object?>()];
    return MrbEtat(
      epoch: _entier(j['epoch']),
      seqMax: _entier(j['seq_max']),
      repSeq: _entier(j['rep_seq']),
      nbOperations: j['nb_operations'] is num ? _entier(j['nb_operations']) : null,
      repN: j['rep_n'] is num ? _entier(j['rep_n']) : null,
      depot: j['depot'] as String?,
      restauration: j['restauration'] as String?,
      reinitOuverte: j['reinit_ouverte'] == true,
      alertes: liste(j['alertes']),
      bloques: [for (final b in (j['bloques'] as List? ?? const [])) '$b'],
      derives: [for (final b in (j['derives'] as List? ?? const [])) '$b'],
      appareils: [
        for (final a in liste(j['appareils']))
          MrbAppareil(uuid: '${a['uuid']}', etiquette: '${a['etiquette'] ?? ''}', role: '${a['role'] ?? ''}', etat: '${a['etat'] ?? ''}')
      ],
    );
  }

  @override
  Future<MrbSante> supervision() async {
    final j = await _get('/admin/supervision');
    if (j['controles'] is! List) {
      throw ErreurMere(502, 'reponse_inattendue', 'Le service de la mère a répondu sans contrôles de santé : réponse ignorée.');
    }
    return MrbSante(
      etat: '${j['etat']}',
      depot: '${j['depot'] ?? ''}',
      controles: [
        for (final x in (j['controles'] as List))
          MrbControle(
              nom: '${(x as Map)['nom']}', etat: '${x['etat']}', detail: '${x['detail'] ?? ''}', valeur: x['valeur'])
      ],
    );
  }

  @override
  Future<List<MrbLigneJournal>> journal({int limite = 500}) async {
    final j = await _get('/admin/journal?limite=$limite');
    return [
      for (final x in (j['liste'] as List? ?? const []))
        MrbLigneJournal(
            quand: _entier((x as Map)['quand']),
            niveau: '${x['niveau']}',
            source: '${x['source']}',
            message: '${x['message']}')
    ];
  }

  @override
  Future<int?> patientsActifs() async {
    final j = await _get('/admin/compte?collection=patients');
    return j['n'] is num ? _entier(j['n']) : null;
  }

  @override
  Future<String> sauvegarderMaintenant() async => '${(await client.brut('POST', '/admin/sauvegarder'))['fichier']}';

  @override
  Future<void> debloquer(String uuid) => client.debloquer(uuid);

  @override
  Future<void> revoquer(String uuid) => client.revoquer(uuid);

  @override
  Future<void> ouvrirFenetreReinit(bool ouvrir) => client.ouvrirFenetreReinit(ouvrir);

  @override
  Future<MrbResultatReinit> reinitialiser({required String confirmation, required String second}) async {
    final j = await client.brut('POST', '/admin/reinitialiser', {'confirmation': confirmation, 'second': second});
    return MrbResultatReinit(sauvegarde: '${j['sauvegarde']}', epoch: j['epoch'] is num ? _entier(j['epoch']) : null);
  }

  @override
  Future<MrbCodeMobile> codeMobile(String etiquette, {required String profil, String? fonction}) async {
    final r = await client.codeMobile(etiquette, profil: profil, fonction: fonction);
    return MrbCodeMobile(code: r.code, payloadQr: mrbPayloadQrMobile(code: r.code, cleBase64: r.cle));
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Résolution : la source que les écrans lisent
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Posé par `ecransPortes` (registre.dart) quand le poste est mère : le client du service local.
ClientMere? mrbClientMere;

/// Posé par les tests : une source sans réseau. Prioritaire.
MrbSource? mrbSourceInjectee;

/// Cadence d'actualisation des écrans (la console de la mère sonde toutes les 3 s). Les tests la rallongent pour ne laisser aucun minuteur actif.
Duration mrbIntervalle = const Duration(seconds: 5);

MrbSource? mrbSourceCourante() {
  final i = mrbSourceInjectee;
  if (i != null) return i;
  final c = mrbClientMere;
  return c == null ? null : MrbSourceClient(c);
}
