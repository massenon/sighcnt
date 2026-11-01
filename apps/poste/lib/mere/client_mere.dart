import 'dart:convert';

import 'package:http/http.dart' as http;

/// Erreur nommée renvoyée par le service de la mère (`code` + `motif`) — affichée telle quelle, jamais reformulée.
class ErreurMere implements Exception {
  ErreurMere(this.statut, this.code, this.motif);
  final int statut;
  final String code;
  final String motif;
  @override
  String toString() => motif.isEmpty ? code : '$code — $motif';
}

class Appareil {
  Appareil(
      {required this.uuid,
      required this.etiquette,
      required this.role,
      required this.etat,
      required this.dernierContact,
      required this.derniereSeq,
      required this.deriveMs,
      this.profil,
      this.fonction});
  final String uuid;
  final String etiquette;
  final String role;
  final String etat;
  final DateTime? dernierContact;
  final int derniereSeq;
  final int deriveMs;

  /// Profil (soignant, reception) et fonction du soignant FIXÉS par le code d'appairage de la mère (E1600) ; `null` pour un poste fileul, ou pour un
  /// mobile appairé avant la fixation de la fonction.
  final String? profil;
  final String? fonction;

  bool get revoque => etat == 'revoque';

  factory Appareil.depuis(Map<String, Object?> j) => Appareil(
        uuid: j['uuid']! as String,
        etiquette: (j['etiquette'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        etat: (j['etat'] ?? '') as String,
        dernierContact: j['dernier_contact'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (j['dernier_contact']! as num).toInt()),
        derniereSeq: ((j['dernier_seq'] ?? 0) as num).toInt(),
        deriveMs: ((j['derive_ms'] ?? 0) as num).toInt(),
        profil: j['profil'] as String?,
        fonction: j['fonction'] as String?,
      );
}

class Conflit {
  Conflit(
      {required this.id,
      required this.collection,
      required this.fiche,
      required this.champ,
      required this.a,
      required this.b,
      required this.etat,
      this.appareil,
      this.decision});
  final int id;
  final String collection;
  final String fiche;
  final String champ;
  final Object? a;
  final Object? b;
  final String etat;

  /// Appareil à l'origine de la version B, et décision prise (`a` ou `b`) une fois tranché : lus tels que le moteur les écrit.
  final String? appareil;
  final String? decision;

  /// Un « doublon possible » n'a pas de champ en conflit : c'est une fiche créée qui ressemble à une autre.
  bool get estDoublon => champ == 'doublon_possible';

  factory Conflit.depuis(Map<String, Object?> j) => Conflit(
        id: (j['id']! as num).toInt(),
        collection: j['collection']! as String,
        fiche: j['fiche']! as String,
        champ: j['champ']! as String,
        a: j['a'] == null ? null : jsonDecode(j['a']! as String),
        b: j['b'] == null ? null : jsonDecode(j['b']! as String),
        etat: (j['etat'] ?? 'ouvert') as String,
        appareil: j['appareil'] as String?,
        decision: j['decision'] as String?,
      );
}

class EtatMere {
  EtatMere(
      {required this.epoch,
      required this.seqMax,
      required this.repSeq,
      required this.appareils,
      required this.conflitsOuverts,
      required this.alertes,
      required this.derives,
      required this.bloques,
      required this.reinitOuverte,
      required this.restauration,
      this.marqueResync,
      this.acksResync = const []});
  final int epoch;
  final int seqMax;
  final int repSeq;
  final List<Appareil> appareils;
  final int conflitsOuverts;
  final List<Map<String, Object?>> alertes;
  final List<String> derives;
  final List<String> bloques;
  final bool reinitOuverte;
  final String? restauration;

  /// Dernier « Renvoyer vers tous » (marque posée par la mère) et les appareils qui l'ont acquitté. `null` : aucun renvoi en cours.
  final String? marqueResync;
  final List<String> acksResync;

  /// Opérations de la mère pas encore répliquées (chiffrées) vers le relais.
  int get retardRelais => seqMax - repSeq;

  factory EtatMere.depuis(Map<String, Object?> j) => EtatMere(
        epoch: (j['epoch']! as num).toInt(),
        seqMax: (j['seq_max']! as num).toInt(),
        repSeq: ((j['rep_seq'] ?? 0) as num).toInt(),
        appareils: ((j['appareils'] ?? const []) as List)
            .map((x) => Appareil.depuis((x as Map).cast<String, Object?>()))
            .toList(),
        conflitsOuverts: ((j['conflits_ouverts'] ?? 0) as num).toInt(),
        alertes: ((j['alertes'] ?? const []) as List)
            .map((x) => (x as Map).cast<String, Object?>())
            .toList(),
        derives: ((j['derives'] ?? const []) as List).cast<String>(),
        bloques: ((j['bloques'] ?? const []) as List).cast<String>(),
        reinitOuverte: j['reinit_ouverte'] == true,
        restauration: j['restauration'] as String?,
        marqueResync: ((j['resync'] as Map?)?['marque']) as String?,
        acksResync: (((j['resync'] as Map?)?['acks'] ?? const []) as List)
            .map((x) => '$x')
            .toList(),
      );
}

/// Un contrôle de santé de la mère : `etat` ∈ ok · attention · alerte · inconnu. « inconnu » ne rassure jamais.
class Controle {
  Controle({required this.nom, required this.etat, required this.detail});
  final String nom;
  final String etat;
  final String detail;
  factory Controle.depuis(Map<String, Object?> j) => Controle(
      nom: '${j['nom']}', etat: '${j['etat']}', detail: '${j['detail'] ?? ''}');
}

class Supervision {
  Supervision(
      {required this.etat, required this.controles, required this.depot});
  final String etat;
  final List<Controle> controles;
  final String depot;
}

class EvenementJournal {
  EvenementJournal(
      {required this.quand,
      required this.niveau,
      required this.source,
      required this.message});
  final DateTime quand;
  final String niveau;
  final String source;
  final String message;
  factory EvenementJournal.depuis(Map<String, Object?> j) => EvenementJournal(
        quand:
            DateTime.fromMillisecondsSinceEpoch((j['quand']! as num).toInt()),
        niveau: '${j['niveau']}',
        source: '${j['source']}',
        message: '${j['message']}',
      );
}

/// Client du service local de la mère (API d'administration). La console ne contient AUCUNE règle : elle appelle ce que
/// la mère décide — un refus s'affiche avec la cause que la mère a nommée.
class ClientMere {
  ClientMere(
      {required this.base, required this.secretAdmin, http.Client? client})
      : _http = client ?? http.Client();
  final Uri base;
  final String secretAdmin;
  final http.Client _http;

  Map<String, String> get _entetes =>
      {'content-type': 'application/json', 'x-admin': secretAdmin};

  Future<Map<String, Object?>> _appel(String methode, String chemin,
      [Map<String, Object?>? corps]) async {
    final uri = base.resolve(chemin);
    final rep = methode == 'GET'
        ? await _http.get(uri, headers: _entetes)
        : await _http.post(uri,
            headers: _entetes, body: jsonEncode(corps ?? {}));
    final decode =
        rep.body.isEmpty ? <String, Object?>{} : jsonDecode(rep.body);
    if (rep.statusCode >= 400) {
      final m = decode is Map ? decode : const {};
      throw ErreurMere(rep.statusCode,
          '${m['code'] ?? 'http_${rep.statusCode}'}', '${m['motif'] ?? ''}');
    }
    return decode is Map ? decode.cast<String, Object?>() : {'liste': decode};
  }

  /// Appel d'une route d'administration dont la réponse n'a pas (encore) de type ici : les écrans du lot (b) lisent les champs que le moteur
  /// annonce réellement (`rep_n`, `depot`, `nb_operations`…) sans dupliquer le client. Un tableau JSON revient sous la clé `liste`.
  Future<Map<String, Object?>> brut(String methode, String chemin,
          [Map<String, Object?>? corps]) =>
      _appel(methode, chemin, corps);

  Future<EtatMere> etat() async =>
      EtatMere.depuis(await _appel('GET', '/admin/etat'));

  Future<List<Conflit>> conflits() async {
    final r = await _appel('GET', '/admin/conflits');
    return ((r['liste'] ?? const []) as List)
        .map((x) => Conflit.depuis((x as Map).cast<String, Object?>()))
        .where((c) => c.etat == 'ouvert')
        .toList();
  }

  /// Tous les conflits, tranchés compris (l'historique des décisions).
  Future<List<Conflit>> tousLesConflits() async {
    final r = await _appel('GET', '/admin/conflits');
    return ((r['liste'] ?? const []) as List)
        .map((x) => Conflit.depuis((x as Map).cast<String, Object?>()))
        .toList();
  }

  Future<void> trancher(int id, String decision) =>
      _appel('POST', '/admin/trancher', {'id': id, 'decision': decision});

  Future<String> codeAppareil(String etiquette) async =>
      '${(await _appel('POST', '/admin/code', {
            'etiquette': etiquette,
            'role': 'fileul'
          }))['code']}';

  /// Code d'appairage d'un MOBILE : rend aussi la clé de clinique (QR à scanner sur le téléphone).
  ///
  /// Le PROFIL (`soignant` ou `reception`) et la FONCTION du soignant (`medecin`, `sage_femme`, `infirmier`, `aide_soignant`) sont portés par le code :
  /// le téléphone les reçoit de la mère et ne peut plus les déclarer (E1600).
  Future<({String code, String cle})> codeMobile(String etiquette,
      {required String profil, String? fonction}) async {
    final r = await _appel('POST', '/admin/code-mobile', {
      'etiquette': etiquette,
      'profil': profil,
      if (fonction != null && fonction.isNotEmpty) 'fonction': fonction
    });
    return (code: '${r['code']}', cle: '${r['cle']}');
  }

  Future<void> revoquer(String uuid) =>
      _appel('POST', '/admin/revoquer', {'uuid': uuid});

  Future<void> renvoyerATous() => _appel('POST', '/admin/resync');

  Future<void> debloquer(String uuid) =>
      _appel('POST', '/admin/debloquer', {'uuid': uuid});

  Future<void> ouvrirFenetreReinit(bool ouvrir) =>
      _appel('POST', '/admin/reinit-fenetre', {'ouvrir': ouvrir});

  Future<String> reinitialiser(
          {required String confirmation, required String second}) async =>
      '${(await _appel('POST', '/admin/reinitialiser', {
            'confirmation': confirmation,
            'second': second
          }))['sauvegarde']}';

  Future<Supervision> supervision() async {
    final r = await _appel('GET', '/admin/supervision');
    return Supervision(
      etat: '${r['etat']}',
      depot: '${r['depot'] ?? ''}',
      controles: ((r['controles'] ?? const []) as List)
          .map((x) => Controle.depuis((x as Map).cast<String, Object?>()))
          .toList(),
    );
  }

  Future<List<EvenementJournal>> journal({int limite = 100}) async {
    final r = await _appel('GET', '/admin/journal?limite=$limite');
    return ((r['liste'] ?? const []) as List)
        .map((x) => EvenementJournal.depuis((x as Map).cast<String, Object?>()))
        .toList();
  }

  /// Dépose un lot de tournée pour un mobile (`POST /admin/lot`) : la mère chiffre la charge pour l'appareil. Rend le nombre de
  /// fiches réellement retenues (une fiche inconnue de la mère est écartée par le moteur, sans erreur).
  Future<int> composerLot(
      {required String uuid,
      required List<({String collection, String id})> fiches,
      int? dureeMs}) async {
    final r = await _appel('POST', '/admin/lot', {
      'uuid': uuid,
      'fiches': [
        for (final f in fiches) {'collection': f.collection, 'id': f.id}
      ],
      if (dureeMs != null) 'ttl_ms': dureeMs,
    });
    return ((r['fiches'] ?? 0) as num).toInt();
  }

  Future<void> sauvegarderMaintenant() => _appel('POST', '/admin/sauvegarder');
}
