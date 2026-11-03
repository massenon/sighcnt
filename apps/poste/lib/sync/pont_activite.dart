import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../donnees/magasin.dart';
import 'transcription_mobile.dart' show PieceSync;

/// LE PONT ENTRE LE MAGASIN DU POSTE ET LE JOURNAL D'OPÉRATIONS (PLAN de synchronisation S2 à S4 ; E2130 à E2134).
///
/// Jusqu'ici seule la CONFIGURATION voyageait (mère vers fileuls). Le pont fait voyager, dans les DEUX sens et sans geste de l'agent, l'activité qui peut le faire
/// sans danger, et les mots de passe hachés (un mot de passe changé sur un fileul remonte à la mère, qui le rediffuse). Un geste local arme une minuterie ; une
/// interrogation périodique relit le journal. Rien n'est supprimé en route (RG-14) : un archivage est un champ `statut` qui voyage comme les autres.
///
/// CE QUE LE PONT NE PORTE PAS, ET QU'IL FAUT DIRE : factures, avoirs, écritures (numérotation certifiée), stock, lots et mouvements (RG-03), admissions et lits
/// (un lit, une admission active). Leurs règles de fusion ne sont pas posées : les y faire passer en « dernier geste gagne » les corromprait.
const Set<String> collectionsActivite = {
  'patients',
  'rendezvous',
  'constantes',
  'releves',
  'observations',
  'visites',
  'appels',
  'consultations',
  'dossiersConsultation',
  'antecedents',
};

/// Les fiches qui voyagent EN UN BLOC : un haché et son sel ne se mélangent jamais champ à champ entre deux postes.
const Set<String> collectionsAtomiques = {'identifiants'};

/// Les champs d'un haché qui restent PROPRES au poste : le compteur d'échecs et le verrou changent à chaque tentative ratée, ils ne voyagent pas (sinon chaque
/// mauvaise frappe réécrirait le haché partout et le ferait entrer en conflit avec un vrai changement de mot de passe).
const Set<String> champsLocauxDuHache = {'echecs', 'verrouJusqua', 'dernierEchecLe', 'dernierSuccesLe'};

/// Ce que le pont lit et écrit du côté du journal : le moteur du fileul, ou le service de la mère.
abstract class TransportPont {
  Future<List<PieceSync>> liste(String collection);
  Future<void> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs});
}

/// Le transport du FILEUL : sa base de synchronisation locale.
class TransportFileul implements TransportPont {
  TransportFileul({required this.lire, required this.ecrireFiche});
  final Future<List<PieceSync>> Function(String) lire;
  final void Function(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) ecrireFiche;
  @override
  Future<List<PieceSync>> liste(String collection) => lire(collection);
  @override
  Future<void> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) async =>
      ecrireFiche(collection, fiche, existe: existe, champs: champs);
}

/// Le transport de la MÈRE : le service de son propre processus (`GET /admin/liste`, `POST /admin/referentiel`).
class TransportMereLocale implements TransportPont {
  TransportMereLocale({required this.port, required this.admin, http.Client? client}) : _c = client ?? http.Client();
  final int port;
  final String admin;
  final http.Client _c;

  @override
  Future<List<PieceSync>> liste(String collection) async {
    final r = await _c
        .get(Uri.parse('http://127.0.0.1:$port/admin/liste?collection=${Uri.encodeQueryComponent(collection)}'), headers: {'x-admin': admin})
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw StateError('la mère a répondu ${r.statusCode}');
    return [
      for (final x in (jsonDecode(r.body) as List))
        PieceSync('${(x as Map)['id']}', (x['data'] as Map).cast<String, Object?>(), archive: x['archive'] == true)
    ];
  }

  @override
  Future<void> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    final r = await _c
        .post(Uri.parse('http://127.0.0.1:$port/admin/referentiel'),
            headers: {'content-type': 'application/json', 'x-admin': admin}, body: jsonEncode({'collection': collection, 'fiche': fiche, 'champs': champs}))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw StateError('la mère a répondu ${r.statusCode} : ${r.body}');
    final corps = jsonDecode(r.body);
    if (corps is Map && corps['statut'] == 'refusee') throw StateError('${corps['motif'] ?? corps['code']}');
  }
}

String _j(Object? o) => jsonEncode(o);

class PontActivite {
  PontActivite(this.magasin, this.transport,
      {required this.etiquette, Set<String>? collections, this.delai = const Duration(seconds: 1)})
      : collections = collections ?? {...collectionsActivite, ...collectionsAtomiques};
  final Magasin magasin;
  final TransportPont transport;

  /// Le préfixe propre à ce poste : un identifiant local `ID00042` qui existe sur deux postes à la fois devient `<étiquette>-ID00042`, unique dans la clinique.
  final String etiquette;
  final Set<String> collections;
  final Duration delai;

  /// La dernière version SYNCHRONISÉE de chaque fiche (clé `collection/idSync`) : sert de base à la fusion champ à champ.
  final Map<String, Map<String, Object?>> _base = {};
  final Map<String, VoidCallback> _ecouteurs = {};
  Timer? _minuterie, _periode;
  bool _enCours = false;

  final ValueNotifier<String?> erreur = ValueNotifier<String?>(null);
  final ValueNotifier<int> envoyees = ValueNotifier<int>(0);
  final ValueNotifier<int> recues = ValueNotifier<int>(0);

  /// Les patients dont le code CNT existe en double (RG-01) : jamais corrigés en silence, comptés et marqués `codeEnDoublon`.
  final ValueNotifier<int> doublonsDeCode = ValueNotifier<int>(0);

  void demarrer({Duration intervalle = const Duration(seconds: 3)}) {
    for (final n in collections) {
      if (_ecouteurs.containsKey(n)) continue;
      void ecoute() => _armer();
      _ecouteurs[n] = ecoute;
      magasin.collection(n).addListener(ecoute);
    }
    _periode?.cancel();
    _periode = Timer.periodic(intervalle, (_) => unawaited(cycle()));
    unawaited(cycle());
  }

  void arreter() {
    _minuterie?.cancel();
    _periode?.cancel();
    _minuterie = _periode = null;
    _ecouteurs.forEach((n, e) => magasin.collection(n).removeListener(e));
    _ecouteurs.clear();
  }

  void _armer() => _minuterie ??= Timer(delai, () {
        _minuterie = null;
        unawaited(cycle());
      });

  /// Un tour complet : d'abord ce que l'agent a fait (envoi), puis ce que les autres postes ont fait (réception).
  Future<void> cycle() async {
    if (_enCours) return;
    _enCours = true;
    try {
      await pousser();
      await tirer();
      erreur.value = null;
    } catch (e) {
      erreur.value = 'Synchronisation de l’activité impossible : $e';
    } finally {
      _enCours = false;
    }
  }

  static bool _atomique(String c) => collectionsAtomiques.contains(c);

  /// La forme d'une fiche dans le journal. Une fiche atomique devient un champ unique.
  Map<String, Object?> _versJournal(String c, Fiche f) {
    if (_atomique(c)) return {'atome': _j({...f}..removeWhere((k, _) => champsLocauxDuHache.contains(k)))};
    return {...f}..remove('id');
  }

  Map<String, Object?> _sansLocaux(String c, Map<String, Object?> d) => d;

  String _cleSync(String c, Fiche f) => _atomique(c) ? '${f['id']}' : '${f['idSync']}';

  Future<int> pousser() async {
    var n = 0;
    for (final c in collections) {
      final col = magasin.collection(c);
      List<PieceSync>? distant;
      for (final f in List<Fiche>.of(col.toutes)) {
        if ('${f['id'] ?? ''}'.isEmpty) continue;
        if (!_atomique(c) && '${f['idSync'] ?? ''}'.isEmpty) f['idSync'] = '$etiquette-${f['id']}';
        final cle = _cleSync(c, f);
        final champs = _versJournal(c, f);
        var base = _base['$c/$cle'];
        if (base != null && _j(base) == _j(champs)) continue;
        if (base == null) {
          // Une fiche que le journal porte déjà À L'IDENTIQUE n'est pas réécrite : un écho inutile entrerait en conflit avec le vrai changement qui suit.
          distant ??= await transport.liste(c);
          final deja = distant.where((p) => p.id == cle).firstOrNull;
          if (deja != null && _j(_sansLocaux(c, deja.data)) == _j(champs)) {
            _base['$c/$cle'] = champs;
            continue;
          }
        }
        // Seuls les champs qui ont changé partent : deux postes qui touchent des champs différents ne s'écrasent pas.
        final diff = base == null || _atomique(c)
            ? champs
            : <String, Object?>{for (final e in champs.entries) if (_j(base[e.key]) != _j(e.value)) e.key: e.value};
        distant ??= await transport.liste(c);
        final existe = distant.any((p) => p.id == cle);
        if (_atomique(c) && existe) {
          // Un haché plus ANCIEN que celui du journal ne l'écrase jamais (poste resté en retard) : il sera remplacé à la réception.
          final brut = distant.firstWhere((p) => p.id == cle).data['atome'];
          final d = brut is String ? DateTime.tryParse('${(jsonDecode(brut) as Map)['definiLe'] ?? ''}') : null;
          final i = DateTime.tryParse('${f['definiLe'] ?? ''}');
          if (d != null && (i == null || d.isAfter(i))) continue;
        }
        await transport.ecrire(c, cle, existe: existe, champs: diff);
        _base['$c/$cle'] = champs;
        n++;
      }
    }
    envoyees.value += n;
    return n;
  }

  Future<int> tirer() async {
    var n = 0;
    for (final c in collections) {
      final col = magasin.collection(c);
      for (final p in await transport.liste(c)) {
        final cle = p.id;
        final distant = p.data;
        if (_atomique(c)) {
          final brut = distant['atome'];
          if (brut is! String) continue;
          final f = (jsonDecode(brut) as Map).cast<String, Object?>();
          final local = col.parId(f['id']);
          if (local != null) {
            // Le plus RÉCENT gagne, jamais l'inverse : un mot de passe changé ici ne revient pas à l'ancien.
            final d = DateTime.tryParse('${f['definiLe'] ?? ''}');
            final i = DateTime.tryParse('${local['definiLe'] ?? ''}');
            if (d == null || (i != null && !d.isAfter(i))) {
              if (i != null && d != null && i.isAfter(d)) continue;
              _base['$c/$cle'] = distant;
              continue;
            }
          }
          if (local != null) {
            for (final k in champsLocauxDuHache) {
              if (local.containsKey(k)) f[k] = local[k];
            }
          }
          if (col.appliquerDistante(f)) n++;
          _base['$c/$cle'] = distant;
          continue;
        }
        final local = _parSync(col, cle);
        final recu = <String, Object?>{...distant, 'idSync': cle, if (p.archive) 'statut': 'archive'};
        if (local == null) {
          if (col.appliquerDistante({...recu, 'id': cle})) n++;
          _base['$c/$cle'] = recu;
          continue;
        }
        final base = _base['$c/$cle'];
        final fusion = <String, Object?>{};
        for (final k in {...recu.keys, ...local.keys}) {
          if (k == 'id') continue;
          // Fusion à trois voies : ce que l'agent a changé ici est gardé, le reste suit le journal.
          final changeIci = base != null && _j(local[k]) != _j(base[k]);
          final v = changeIci ? local[k] : (recu.containsKey(k) ? recu[k] : local[k]);
          if (v != null) fusion[k] = v;
        }
        fusion['id'] = local['id'];
        if (_j(fusion) != _j(local)) {
          col.appliquerDistante(fusion);
          n++;
        }
        _base['$c/$cle'] = recu;
      }
      if (c == 'patients') _marquerDoublons(col);
    }
    recues.value += n;
    return n;
  }

  Fiche? _parSync(CollectionMagasin col, String cle) {
    for (final f in col.toutes) {
      if (f['idSync'] == cle) return f;
    }
    return null;
  }

  /// RG-01 : deux dossiers ne portent jamais le même code. Si la rencontre de deux postes l'a produit, les deux fiches sont MARQUÉES, pas renumérotées (un code
  /// attribué ne se modifie pas) : la Direction tranche.
  void _marquerDoublons(CollectionMagasin col) {
    final vus = <String, List<Fiche>>{};
    for (final f in col.toutes) {
      final code = '${f['code'] ?? ''}';
      if (code.isEmpty || CollectionMagasin.estArchivee(f)) continue;
      (vus[code] ??= []).add(f);
    }
    var n = 0;
    for (final g in vus.values) {
      final doublon = g.length > 1;
      for (final f in g) {
        if (doublon) n++;
        if ((f['codeEnDoublon'] == true) != doublon) {
          f['codeEnDoublon'] = doublon;
          col.appliquerDistante({...f});
        }
      }
    }
    doublonsDeCode.value = n;
  }
}
