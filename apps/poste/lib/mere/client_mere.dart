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
  Appareil({required this.uuid, required this.etiquette, required this.role, required this.etat, required this.dernierContact, required this.derniereSeq, required this.deriveMs});
  final String uuid;
  final String etiquette;
  final String role;
  final String etat;
  final DateTime? dernierContact;
  final int derniereSeq;
  final int deriveMs;

  bool get revoque => etat == 'revoque';

  factory Appareil.depuis(Map<String, Object?> j) => Appareil(
        uuid: j['uuid']! as String,
        etiquette: (j['etiquette'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        etat: (j['etat'] ?? '') as String,
        dernierContact: j['dernier_contact'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['dernier_contact']! as num).toInt()),
        derniereSeq: ((j['dernier_seq'] ?? 0) as num).toInt(),
        deriveMs: ((j['derive_ms'] ?? 0) as num).toInt(),
      );
}

class Conflit {
  Conflit({required this.id, required this.collection, required this.fiche, required this.champ, required this.a, required this.b, required this.etat});
  final int id;
  final String collection;
  final String fiche;
  final String champ;
  final Object? a;
  final Object? b;
  final String etat;

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
      );
}

class EtatMere {
  EtatMere({required this.epoch, required this.seqMax, required this.repSeq, required this.appareils, required this.conflitsOuverts, required this.alertes, required this.derives, required this.bloques, required this.reinitOuverte, required this.restauration});
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

  /// Opérations de la mère pas encore répliquées (chiffrées) vers le relais.
  int get retardRelais => seqMax - repSeq;

  factory EtatMere.depuis(Map<String, Object?> j) => EtatMere(
        epoch: (j['epoch']! as num).toInt(),
        seqMax: (j['seq_max']! as num).toInt(),
        repSeq: ((j['rep_seq'] ?? 0) as num).toInt(),
        appareils: ((j['appareils'] ?? const []) as List).map((x) => Appareil.depuis((x as Map).cast<String, Object?>())).toList(),
        conflitsOuverts: ((j['conflits_ouverts'] ?? 0) as num).toInt(),
        alertes: ((j['alertes'] ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList(),
        derives: ((j['derives'] ?? const []) as List).cast<String>(),
        bloques: ((j['bloques'] ?? const []) as List).cast<String>(),
        reinitOuverte: j['reinit_ouverte'] == true,
        restauration: j['restauration'] as String?,
      );
}

/// Client du service local de la mère (API d'administration). La console ne contient AUCUNE règle : elle appelle ce que
/// la mère décide — un refus s'affiche avec la cause que la mère a nommée.
class ClientMere {
  ClientMere({required this.base, required this.secretAdmin, http.Client? client}) : _http = client ?? http.Client();
  final Uri base;
  final String secretAdmin;
  final http.Client _http;

  Map<String, String> get _entetes => {'content-type': 'application/json', 'x-admin': secretAdmin};

  Future<Map<String, Object?>> _appel(String methode, String chemin, [Map<String, Object?>? corps]) async {
    final uri = base.resolve(chemin);
    final rep = methode == 'GET' ? await _http.get(uri, headers: _entetes) : await _http.post(uri, headers: _entetes, body: jsonEncode(corps ?? {}));
    final decode = rep.body.isEmpty ? <String, Object?>{} : jsonDecode(rep.body);
    if (rep.statusCode >= 400) {
      final m = decode is Map ? decode : const {};
      throw ErreurMere(rep.statusCode, '${m['code'] ?? 'http_${rep.statusCode}'}', '${m['motif'] ?? ''}');
    }
    return decode is Map ? decode.cast<String, Object?>() : {'liste': decode};
  }

  Future<EtatMere> etat() async => EtatMere.depuis(await _appel('GET', '/admin/etat'));

  Future<List<Conflit>> conflits() async {
    final r = await _appel('GET', '/admin/conflits');
    return ((r['liste'] ?? const []) as List).map((x) => Conflit.depuis((x as Map).cast<String, Object?>())).where((c) => c.etat == 'ouvert').toList();
  }

  Future<void> trancher(int id, String decision) => _appel('POST', '/admin/trancher', {'id': id, 'decision': decision});

  Future<String> codeAppareil(String etiquette) async => '${(await _appel('POST', '/admin/code', {'etiquette': etiquette, 'role': 'fileul'}))['code']}';

  /// Code d'appairage d'un MOBILE : rend aussi la clé de clinique (QR à scanner sur le téléphone).
  Future<({String code, String cle})> codeMobile(String etiquette) async {
    final r = await _appel('POST', '/admin/code-mobile', {'etiquette': etiquette});
    return (code: '${r['code']}', cle: '${r['cle']}');
  }

  Future<void> revoquer(String uuid) => _appel('POST', '/admin/revoquer', {'uuid': uuid});

  Future<void> renvoyerATous() => _appel('POST', '/admin/resync');

  Future<void> debloquer(String uuid) => _appel('POST', '/admin/debloquer', {'uuid': uuid});

  Future<void> ouvrirFenetreReinit(bool ouvrir) => _appel('POST', '/admin/reinit-fenetre', {'ouvrir': ouvrir});

  Future<String> reinitialiser({required String confirmation, required String second}) async =>
      '${(await _appel('POST', '/admin/reinitialiser', {'confirmation': confirmation, 'second': second}))['sauvegarde']}';
}
