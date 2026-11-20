/// LA SAUVEGARDE HORS SITE (lot 5, ADR-0007) : le CLIENT de la mère, porté de `packages/sync/banc/sauvegarde-hs.js` (exécutable de référence, éprouvé par les scénarios SAUVHS du banc ;
/// vecteurs de chiffrement `test/vecteurs/sauvegarde_chiffrement.json`). Les règles pures (découpage, réglage, plan, rotation, manifeste) sont dans `sigh_domaine`.
///
/// Chiffrement AU POSTE, par la clé de la clinique (AES-256-GCM, la même que le journal) ; la clé ne part JAMAIS : la destination n'en reçoit ni le clair ni une dérivation.
///  - BLOC  = nonce (12) ‖ chiffré ‖ tag (16). Nonce DÉRIVÉ : HMAC-SHA-256(clé, « sigh-sauv-nonce|1|<genre>|<type>|<empreinte du clair> ») tronqué à 12 octets : un même clair donne le même
///            bloc (dédoublonnage, rejeu idempotent sans état local). AAD = « sigh-sauv-<genre>|1|<type> ». Identifiant = SHA-256 du BLOC.
///  - GENRE = « bloc » (données) ou « manifeste » (liste des éléments et de leurs blocs, chiffrée et découpée comme le reste : la destination ne voit ni noms ni formats).
///  - COPIE = l'empreinte du manifeste en clair : l'identité d'une copie est celle de son CONTENU (rejouer le même état est la même copie).
///
/// Une DESTINATION est une interface : le relais web ([DestinationRelais]) ou un dossier distant monté ([DestinationDossier]). SFTP n'est PAS fait (section AA).
/// La restauration télécharge, déchiffre et VÉRIFIE tout (empreinte du bloc, authentification, longueur, empreinte du clair) AVANT d'écrire : un bloc altéré ou manquant est refusé et NOMMÉ,
/// rien n'est restauré à moitié (cible neuve, dossier de travail renommé d'un coup).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

/// Un refus de la sauvegarde hors site, NOMMÉ (code, motif, geste).
class ErreurSauvegarde implements Exception {
  const ErreurSauvegarde(this.refus);
  final RefusSauvegarde refus;
  String get code => refus.code;
  @override
  String toString() => refus.toString();
}

ErreurSauvegarde _e(String code, String motif, String geste, [Map<String, Object?> plus = const {}]) => ErreurSauvegarde(RefusSauvegarde(code, motif, geste, plus));

final RegExp _id = RegExp(r'^[0-9a-f]{64}$');

/// Un élément illisible à la SOURCE (fichier altéré, absent) : la copie ne le propage JAMAIS, le compte et continue avec les autres ; le compte rendu le dit.
class ElementIllisible implements Exception {
  const ElementIllisible();
}

/// Un bloc scellé : son identifiant (SHA-256 du bloc), les octets à déposer, la longueur du clair.
class BlocScelle {
  const BlocScelle(this.id, this.octets, this.clair);
  final String id;
  final Uint8List octets;
  final int clair;
}

/// Le chiffrement des blocs (format du banc : `sauvegarde-hs.js`).
class ChiffreurSauvegarde {
  ChiffreurSauvegarde(List<int> cle)
      : _cle = SecretKey(cle),
        assert(cle.length == 32, 'clé de 32 octets exigée') {
    if (cle.length != 32) throw ArgumentError('clé de 32 octets exigée');
  }
  final SecretKey _cle;
  final AesGcm _aes = AesGcm.with256bits();
  final Hmac _hmac = Hmac.sha256();

  Future<BlocScelle> sceller(String genre, String type, List<int> clair) async {
    final mac = await _hmac.calculateMac(utf8.encode('sigh-sauv-nonce|1|$genre|$type|${sha256Octets(clair)}'), secretKey: _cle);
    final nonce = mac.bytes.sublist(0, 12);
    final boite = await _aes.encrypt(clair, secretKey: _cle, nonce: nonce, aad: utf8.encode('sigh-sauv-$genre|1|$type'));
    final blob = Uint8List.fromList([...nonce, ...boite.cipherText, ...boite.mac.bytes]);
    return BlocScelle(sha256Octets(blob), blob, clair.length);
  }

  /// Ouvre un bloc ; lève [ErreurSauvegarde] `CLE_INCORRECTE` si l'authentification échoue (le bloc est intact, l'identifiant ayant été vérifié par l'appelant).
  Future<Uint8List> ouvrir(String genre, String type, List<int> blob, String id) async {
    try {
      final clair = await _aes.decrypt(SecretBox(blob.sublist(12, blob.length - 16), nonce: blob.sublist(0, 12), mac: Mac(blob.sublist(blob.length - 16))), secretKey: _cle, aad: utf8.encode('sigh-sauv-$genre|1|$type'));
      return Uint8List.fromList(clair);
    } catch (_) {
      throw _e('CLE_INCORRECTE', 'le bloc $id est intact mais ne s\'ouvre pas avec cette clé', 'Utiliser la clé de la clinique qui a fait la copie (export de clé, copie papier sous scellé).', {'bloc': id});
    }
  }
}

/// Une destination des copies : le relais web ou un dossier distant monté. Mêmes opérations, mêmes refus nommés.
abstract class DestinationSauvegarde {
  /// Les limites, l'espace et les copies de la destination. Un champ absent n'est PAS un zéro : il est inconnu.
  Future<Map<String, Object?>> etat();
  Future<List<String>> manquants(List<String> ids);
  Future<Map<String, Object?>> deposerBloc(String id, Uint8List octets);
  Future<Map<String, Object?>> ouvrir(String id, String type, int date, int garder);
  Future<void> attacher(String id, List<String> ids);
  Future<Map<String, Object?>> valider(String id, List<String> racine);
  Future<List<Map<String, Object?>>> copies(String type);
  Future<Map<String, Object?>> copie(String id);
  Future<Uint8List> bloc(String id);
  String get libelle;
}

/// La destination « relais web » : les routes `/sauvegarde/*` du relais (en-tête de la mère). Le relais refuse en nommant (voir `relais-sauvegarde.js` et `SauvegardeController`).
class DestinationRelais implements DestinationSauvegarde {
  DestinationRelais(this.base, this.secretMere, {this.delai = const Duration(seconds: 60)}) {
    _http.connectionTimeout = const Duration(seconds: 5);
  }
  final String base;
  final String secretMere;
  final Duration delai;
  final HttpClient _http = HttpClient();

  @override
  String get libelle => 'relais web';

  Future<(int, Uint8List, ContentType?)> _appel(String methode, String chemin, {Object? corps, Uint8List? octets}) async {
    final req = await _http.openUrl(methode, Uri.parse('$base$chemin')).timeout(delai);
    req.headers.set('x-mere', secretMere);
    if (octets != null) {
      req.headers.contentType = ContentType.binary;
      req.contentLength = octets.length;
      req.add(octets);
    } else if (corps != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(corps)));
    }
    final rep = await req.close().timeout(delai);
    final tout = BytesBuilder(copy: false);
    await for (final c in rep.timeout(delai)) {
      tout.add(c);
    }
    return (rep.statusCode, tout.takeBytes(), rep.headers.contentType);
  }

  Future<Map<String, Object?>> _json(String methode, String chemin, {Object? corps, Uint8List? octets}) async {
    final (statut, brut, _) = await _appel(methode, chemin, corps: corps, octets: octets);
    Map<String, Object?> j = {};
    try {
      if (brut.isNotEmpty) j = (jsonDecode(utf8.decode(brut)) as Map).cast<String, Object?>();
    } catch (_) {/* vide */}
    if (statut >= 400) {
      final plus = {...j}..removeWhere((k, _) => const ['code', 'motif', 'geste'].contains(k));
      throw ErreurSauvegarde(RefusSauvegarde('${j['code'] ?? 'ERREUR_RELAIS'}', '${j['motif'] ?? 'réponse $statut'}', '${j['geste'] ?? ''}', {...plus, 'statut': statut}));
    }
    return j;
  }

  @override
  Future<Map<String, Object?>> etat() => _json('GET', '/sauvegarde/etat');
  @override
  Future<List<String>> manquants(List<String> ids) async => [for (final x in ((await _json('POST', '/sauvegarde/manquants', corps: {'ids': ids}))['manquants'] as List)) '$x'];
  @override
  Future<Map<String, Object?>> deposerBloc(String id, Uint8List octets) => _json('PUT', '/sauvegarde/bloc/$id', octets: octets);
  @override
  Future<Map<String, Object?>> ouvrir(String id, String type, int date, int garder) => _json('POST', '/sauvegarde/copie', corps: {'id': id, 'type': type, 'date': date, 'garder': garder});
  @override
  Future<void> attacher(String id, List<String> ids) async => _json('POST', '/sauvegarde/copie/$id/blocs', corps: {'ids': ids});
  @override
  Future<Map<String, Object?>> valider(String id, List<String> racine) => _json('POST', '/sauvegarde/copie/$id/valider', corps: {'racine': racine});
  @override
  Future<List<Map<String, Object?>>> copies(String type) async => [for (final x in ((await _json('GET', '/sauvegarde/copies?type=$type'))['copies'] as List)) (x as Map).cast<String, Object?>()];
  @override
  Future<Map<String, Object?>> copie(String id) => _json('GET', '/sauvegarde/copie/$id');
  @override
  Future<Uint8List> bloc(String id) async {
    final (statut, brut, type) = await _appel('GET', '/sauvegarde/bloc/$id');
    if (statut >= 400 || type?.mimeType != 'application/octet-stream') {
      Map<String, Object?> j = {};
      try {
        j = (jsonDecode(utf8.decode(brut)) as Map).cast<String, Object?>();
      } catch (_) {/* vide */}
      throw ErreurSauvegarde(RefusSauvegarde('${j['code'] ?? 'ERREUR_RELAIS'}', '${j['motif'] ?? 'réponse $statut'}', '${j['geste'] ?? ''}', {'statut': statut}));
    }
    return brut;
  }
}

/// La destination « dossier distant monté » (partage réseau, disque d'un autre site) : même format, même chiffrement, mêmes refus ; aucun quota ni limite de requête (l'espace est celui du
/// dossier : inconnu de ce poste, jamais compté comme zéro). Les blocs sont des fichiers `blocs/<2>/<id>`, les copies des fiches `copies/<id>.json` ; écriture atomique. Le dossier n'est
/// JAMAIS créé par le poste : il doit exister (un disque absent se créerait sur le disque des données).
class DestinationDossier implements DestinationSauvegarde {
  DestinationDossier(this.racine, {this.plancher = 2, this.plafond = 60, DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;
  final String racine;
  final int plancher;
  final int plafond;
  final DateTime Function() _horloge;

  @override
  String get libelle => 'dossier distant';

  String _bloc(String id) => '$racine/blocs/${id.substring(0, 2)}/$id';
  String _copie(String id) => '$racine/copies/$id.json';

  void _exiger() {
    if (!Directory(racine).existsSync()) {
      throw _e('DOSSIER_INTROUVABLE', '« $racine » n\'existe pas ou n\'est pas monté', 'Brancher ou monter le dossier distant : le poste ne le crée jamais.');
    }
  }

  Map<String, Object?> _lire(String id) {
    final f = File(_copie(id));
    if (!f.existsSync()) throw _e('COPIE_INCONNUE', 'cette copie n\'existe pas dans le dossier distant', 'Relire la liste des copies.');
    return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
  }

  void _ecrire(Map<String, Object?> c) {
    Directory('$racine/copies').createSync(recursive: true);
    final t = File('${_copie('${c['id']}')}.tmp');
    t.writeAsStringSync(jsonEncode(c), flush: true);
    t.renameSync(_copie('${c['id']}'));
  }

  List<Map<String, Object?>> _toutes() {
    final d = Directory('$racine/copies');
    if (!d.existsSync()) return [];
    return [for (final f in d.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>()];
  }

  @override
  Future<Map<String, Object?>> etat() async {
    _exiger();
    final cs = _toutes();
    int n(String t, String e) => cs.where((c) => c['type'] == t && c['etat'] == e).length;
    final copies = <String, Object?>{};
    for (final t in shTypes) {
      final completes = cs.where((c) => c['type'] == t && c['etat'] == 'complete').toList()..sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
      copies[t] = {'completes': n(t, 'complete'), 'archivees': n(t, 'archivee'), 'purgees': 0, 'ouvertes': n(t, 'ouverte'), 'derniere': completes.isEmpty ? null : completes.first};
    }
    // Aucun quota, aucune limite par copie : absents (inconnus), jamais zéro.
    return {'format': shFormat, 'limites': {'rotationPlancher': plancher, 'rotationPlafond': plafond}, 'copies': copies};
  }

  @override
  Future<List<String>> manquants(List<String> ids) async {
    _exiger();
    return [for (final i in ids.where(_id.hasMatch)) if (!File(_bloc(i)).existsSync()) i];
  }

  @override
  Future<Map<String, Object?>> deposerBloc(String id, Uint8List octets) async {
    _exiger();
    if (!_id.hasMatch(id)) throw _e('BLOC_ID_INVALIDE', 'l\'identifiant d\'un bloc est une empreinte SHA-256 en hexadécimal', 'Utiliser l\'empreinte du bloc chiffré.');
    if (octets.isEmpty) throw _e('BLOC_TROP_GROS', 'un bloc vide n\'est pas déposé', 'Réduire la taille de bloc du réglage.');
    if (sha256Octets(octets) != id) throw _e('BLOC_ALTERE_EN_ROUTE', 'les octets reçus n\'ont pas l\'empreinte annoncée : le bloc a été altéré en route', 'Renvoyer le bloc.');
    final f = File(_bloc(id));
    if (f.existsSync()) return {'id': id, 'taille': octets.length, 'rejeu': true};
    f.parent.createSync(recursive: true);
    final t = File('${f.path}.tmp');
    t.writeAsBytesSync(octets, flush: true);
    t.renameSync(f.path);
    return {'id': id, 'taille': octets.length};
  }

  @override
  Future<Map<String, Object?>> ouvrir(String id, String type, int date, int garder) async {
    _exiger();
    if (!_id.hasMatch(id) || !shTypes.contains(type)) throw _e('COPIE_INVALIDE', 'identifiant ou type de copie invalide', 'Utiliser l\'identifiant calculé par le poste mère (empreinte du manifeste) et un type connu.');
    final r = shRotation(const [], garder, plancher, plafond);
    if (!r.ok) throw ErreurSauvegarde(r.refus!);
    if (File(_copie(id)).existsSync()) return {'etat': _lire(id)['etat'], 'rejeu': true};
    _ecrire({'id': id, 'type': type, 'etat': 'ouverte', 'date': date, 'recu': _horloge().millisecondsSinceEpoch, 'garder': garder, 'nb_blocs': 0, 'taille': 0, 'liens': <String>[], 'racine': <String>[], 'motif': null});
    return {'etat': 'ouverte'};
  }

  @override
  Future<void> attacher(String id, List<String> ids) async {
    _exiger();
    final c = _lire(id);
    if (c['etat'] == 'complete') return;
    if (c['etat'] != 'ouverte') throw _e('COPIE_NON_OUVERTE', 'cette copie est ${c['etat']}', 'Rouvrir la copie par le poste mère.');
    final manque = await manquants(ids);
    if (manque.isNotEmpty) throw _e('BLOC_MANQUANT', '${manque.length} bloc(s) ne sont pas dans le dossier distant', 'Déposer d\'abord les blocs manquants.', {'manquants': manque.take(50).toList()});
    final liens = {...(c['liens'] as List).cast<String>(), ...ids};
    c['liens'] = liens.toList();
    c['nb_blocs'] = liens.length;
    c['taille'] = liens.fold<int>(0, (s, i) => s + File(_bloc(i)).lengthSync());
    _ecrire(c);
  }

  @override
  Future<Map<String, Object?>> valider(String id, List<String> racine) async {
    _exiger();
    final c = _lire(id);
    if (c['etat'] == 'complete') return {'etat': 'complete', 'rejeu': true, 'archivees': <String>[]};
    if (c['etat'] != 'ouverte') throw _e('COPIE_NON_OUVERTE', 'cette copie est ${c['etat']}', 'Rouvrir la copie par le poste mère.');
    if (racine.isEmpty) throw _e('RACINE_ABSENTE', 'une copie complète désigne les blocs de son manifeste', 'Déposer et désigner les blocs du manifeste.');
    final liens = (c['liens'] as List).cast<String>().toSet();
    final manque = racine.where((i) => !liens.contains(i)).toList();
    if (manque.isNotEmpty) throw _e('BLOC_MANQUANT', '${manque.length} bloc(s) du manifeste ne sont pas rattachés à cette copie', 'Rattacher les blocs du manifeste.', {'manquants': manque.take(50).toList()});
    c['etat'] = 'complete';
    c['racine'] = racine;
    _ecrire(c);
    final memeType = [for (final x in _toutes().where((x) => x['type'] == c['type'])) CopieVue.depuisJson(x)];
    final r = shRotation(memeType, c['garder'], plancher, plafond);
    for (final a in r.archiver) {
      final x = _lire(a);
      x['etat'] = 'archivee';
      _ecrire(x);
    }
    return {'etat': 'complete', 'archivees': r.archiver};
  }

  @override
  Future<List<Map<String, Object?>>> copies(String type) async {
    _exiger();
    return (_toutes().where((c) => c['type'] == type).toList()..sort((a, b) => (b['date'] as int).compareTo(a['date'] as int)))
        .map((c) => {...c}..remove('liens'))
        .toList();
  }

  @override
  Future<Map<String, Object?>> copie(String id) async {
    _exiger();
    final c = _lire(id);
    if (c['etat'] != 'complete' && c['etat'] != 'archivee') throw _e('COPIE_INCOMPLETE', 'cette copie n\'a jamais été validée', 'Choisir une copie complète.');
    return {...c}..remove('liens');
  }

  @override
  Future<Uint8List> bloc(String id) async {
    _exiger();
    final f = File(_bloc(id));
    if (!f.existsSync()) throw _e('BLOC_ABSENT', 'ce bloc n\'est pas (ou plus) dans le dossier distant', 'Choisir une autre copie.');
    return f.readAsBytesSync();
  }
}

/// Un élément à sauvegarder : une référence (« magasin », ou `<empreinte>.<ext>` d'un fichier numérisé : jamais un nom de patient), sa taille, sa lecture, ses métadonnées.
class ElementASauver {
  ElementASauver({required this.ref, required this.taille, required this.lire, this.meta, this.shaClair});
  final String ref;
  final int taille;
  final Future<Uint8List> Function() lire;
  final Map<String, Object?>? meta;

  /// L'empreinte du clair, si la source la connaît déjà (un fichier numérisé est adressé par elle) : permet de sauter la lecture quand les blocs sont déjà à la destination.
  final String? shaClair;
}

/// L'index local des blocs déjà déposés (par élément et taille de bloc) : une copie incrémentale ne relit pas ce que la destination tient déjà. Perdu, il n'enlève rien :
/// la copie relit et la destination dit ce qu'elle a.
typedef IndexBlocs = Map<String, List<Map<String, Object?>>>;

class ResultatDepot {
  ResultatDepot({required this.copie, required this.deposes, required this.dejaLa, required this.octetsDeposes, required this.rejeu, required this.archivees, required this.blocs, required this.octetsChiffres, this.illisibles = 0});
  final String copie;
  final int deposes;
  final int dejaLa;
  final int octetsDeposes;
  final bool rejeu;
  final List<String> archivees;
  final int blocs;
  final int octetsChiffres;

  /// Les éléments illisibles à la source, écartés (jamais propagés).
  final int illisibles;
}

/// SAUVEGARDER. [coupureApres] : le dépôt est COUPÉ (refus nommé `DEPOT_COUPE`) après tant de blocs déposés (banc, tests). [index] : l'index local (rempli au fil de la copie).
Future<ResultatDepot> sauvegarderHorsSite({
  required DestinationSauvegarde dest,
  required List<int> cle,
  required String type,
  required List<ElementASauver> elements,
  required int tailleBloc,
  required int garder,
  int? date,
  int? coupureApres,
  IndexBlocs? index,
  void Function(String)? journal,
}) async {
  if (!shTypes.contains(type)) throw _e('TYPE_INCONNU', 'le type « $type » n\'existe pas', 'Choisir magasin ou fichiers.');
  final ch = ChiffreurSauvegarde(cle);
  final etat = await dest.etat();
  final pre = shVerifierPlan(octetsCopie: elements.fold<int>(0, (s, e) => s + shTailleChiffree(e.taille, tailleBloc)), etat: etat);
  if (pre != null) throw ErreurSauvegarde(pre);
  final l = etat['limites'];
  if (l is Map && l['tailleBlocMax'] is int && tailleBloc > (l['tailleBlocMax'] as int)) {
    throw _e('BLOC_TROP_GROS', 'la taille de bloc réglée ($tailleBloc) dépasse celle de la destination (${l['tailleBlocMax']})', 'Réduire la taille de bloc du réglage.');
  }
  final ids = <String>[];
  var deposes = 0, dejaLa = 0, octetsDeposes = 0, octetsChiffres = 0, illisibles = 0;
  var lot = <BlocScelle>[];
  Future<void> vider() async {
    if (lot.isEmpty) return;
    final manque = (await dest.manquants([for (final b in lot) b.id])).toSet();
    for (final b in lot) {
      if (!manque.contains(b.id)) {
        dejaLa++;
        continue;
      }
      if (coupureApres != null && deposes >= coupureApres) {
        throw _e('DEPOT_COUPE', 'le dépôt a été coupé après $deposes bloc(s)', 'Relancer : la reprise ne renvoie que les blocs manquants.', {'deposes': deposes});
      }
      await dest.deposerBloc(b.id, b.octets);
      deposes++;
      octetsDeposes += b.octets.length;
    }
    lot = [];
  }

  final mans = <Map<String, Object?>>[];
  for (final e in elements) {
    final cleIndex = '${e.ref}@$tailleBloc';
    final connu = index?[cleIndex];
    if (connu != null && e.shaClair != null) {
      /* l'index local dit déjà les blocs de cet élément : on ne relit pas le fichier si la destination les tient tous */
      final idsConnus = [for (final b in connu) '${b['id']}'];
      final manque = <String>{};
      for (var i = 0; i < idsConnus.length; i += 2000) {
        manque.addAll(await dest.manquants(idsConnus.sublist(i, min(i + 2000, idsConnus.length))));
      }
      if (manque.isEmpty) {
        ids.addAll(idsConnus);
        dejaLa += idsConnus.length;
        octetsChiffres += connu.fold<int>(0, (s, b) => s + (b['taille'] as int));
        mans.add({'ref': e.ref, 'taille': e.taille, 'sha256': e.shaClair, if (e.meta != null) 'meta': e.meta, 'blocs': connu});
        continue;
      }
    }
    final Uint8List clair;
    try {
      clair = await e.lire();
    } on ElementIllisible {
      illisibles++;
      continue;
    }
    if (clair.length != e.taille) throw _e('ELEMENT_CHANGE', 'un élément a changé de taille pendant la lecture', 'Relancer la copie.');
    final blocs = <Map<String, Object?>>[];
    for (final p in shDecouper(clair.length, tailleBloc)) {
      final b = await ch.sceller('bloc', type, Uint8List.sublistView(clair, p.debut, p.debut + p.longueur));
      blocs.add({'id': b.id, 'taille': b.octets.length, 'clair': b.clair});
      ids.add(b.id);
      octetsChiffres += b.octets.length;
      lot.add(b);
      if (lot.length >= 16) await vider();
    }
    mans.add({'ref': e.ref, 'taille': clair.length, 'sha256': sha256Octets(clair), if (e.meta != null) 'meta': e.meta, 'blocs': blocs});
    index?[cleIndex] = blocs;
  }
  await vider();
  final m = shManifeste(type: type, elements: mans, tailleBloc: tailleBloc);
  final clairM = Uint8List.fromList(utf8.encode(jsonEncode(m)));
  final racine = <String>[];
  lot = [];
  for (final p in shDecouper(clairM.length, tailleBloc)) {
    final b = await ch.sceller('manifeste', type, Uint8List.sublistView(clairM, p.debut, p.debut + p.longueur));
    racine.add(b.id);
    lot.add(b);
    octetsChiffres += b.octets.length;
  }
  await vider();
  final copie = sha256Octets(clairM);
  final ouv = await dest.ouvrir(copie, type, date ?? DateTime.now().millisecondsSinceEpoch, garder);
  if (ouv['etat'] == 'complete') {
    journal?.call('copie $type déjà complète (rejeu) : $deposes bloc(s) déposé(s)');
    return ResultatDepot(copie: copie, deposes: deposes, dejaLa: dejaLa, octetsDeposes: octetsDeposes, rejeu: true, archivees: const [], blocs: ids.length + racine.length, octetsChiffres: octetsChiffres, illisibles: illisibles);
  }
  final tous = {...ids, ...racine}.toList();
  for (var i = 0; i < tous.length; i += 1000) {
    await dest.attacher(copie, tous.sublist(i, min(i + 1000, tous.length)));
  }
  final v = await dest.valider(copie, racine);
  journal?.call('copie $type validée : $deposes bloc(s) déposé(s), $dejaLa déjà présent(s)');
  return ResultatDepot(
      copie: copie, deposes: deposes, dejaLa: dejaLa, octetsDeposes: octetsDeposes, rejeu: false, archivees: [for (final x in (v['archivees'] as List? ?? const [])) '$x'], blocs: tous.length, octetsChiffres: octetsChiffres, illisibles: illisibles);
}

class ResultatRestauration {
  const ResultatRestauration({required this.type, required this.elements, required this.octets, required this.cible, required this.metas});
  final String type;
  final int elements;
  final int octets;
  final String cible;

  /// Les métadonnées de chaque élément (référence -> meta), pour reconstituer ce que le format brut ne porte pas.
  final Map<String, Map<String, Object?>?> metas;
}

/// RESTAURER dans une cible NEUVE. Tout est téléchargé, déchiffré et VÉRIFIÉ avant que la cible n'existe : un bloc altéré ou manquant est refusé et NOMMÉ ; rien n'est restauré à moitié.
/// [apresVerification] est appelée avec le dossier de travail VÉRIFIÉ, avant le renommage (par exemple pour ranger les fichiers dans un stockage neuf) ; si elle lève, rien n'est posé.
Future<ResultatRestauration> restaurerHorsSite({
  required DestinationSauvegarde dest,
  required List<int> cle,
  required String copieId,
  required String cible,
  Future<void> Function(String dossierTravail, List<Map<String, Object?>> elements)? apresVerification,
}) async {
  final ch = ChiffreurSauvegarde(cle);
  if (FileSystemEntity.typeSync(cible) != FileSystemEntityType.notFound) {
    throw _e('CIBLE_EXISTE', '« $cible » existe déjà', 'Restaurer vers un dossier NEUF : la restauration ne remplace jamais ce qui existe.');
  }
  final c = await dest.copie(copieId);
  Future<Uint8List> lire(String genre, String type, String id) async {
    Uint8List blob;
    try {
      blob = await dest.bloc(id);
    } on ErreurSauvegarde catch (x) {
      if (x.code == 'BLOC_ABSENT') throw _e('BLOC_MANQUANT', 'le bloc $id est absent', 'Choisir une autre copie.', {'bloc': id});
      if (x.code == 'BLOC_ALTERE_AU_RELAIS') throw _e('BLOC_ALTERE', 'le bloc $id est altéré au relais', 'Choisir une autre copie.', {'bloc': id});
      rethrow;
    }
    if (sha256Octets(blob) != id) throw _e('BLOC_ALTERE', 'le bloc $id ne correspond pas à son empreinte', 'Choisir une autre copie : celle-ci est altérée.', {'bloc': id});
    return ch.ouvrir(genre, type, blob, id);
  }

  final type = '${c['type']}';
  final morceauxM = <int>[];
  for (final id in (c['racine'] as List).cast<String>()) {
    morceauxM.addAll(await lire('manifeste', type, id));
  }
  final clairM = Uint8List.fromList(morceauxM);
  if (sha256Octets(clairM) != copieId) throw _e('MANIFESTE_ALTERE', 'le manifeste ne correspond pas à l\'identité de la copie', 'Choisir une autre copie.');
  Object? m;
  try {
    m = jsonDecode(utf8.decode(clairM));
  } catch (_) {
    throw _e('MANIFESTE_ILLISIBLE', 'le manifeste ne se lit pas', 'Choisir une autre copie.');
  }
  final refusM = shVerifierManifeste(m);
  if (refusM != null) throw ErreurSauvegarde(refusM);
  final man = (m as Map).cast<String, Object?>();
  final travail = '$cible.reprise-${Random.secure().nextInt(1 << 30).toRadixString(16)}';
  Directory(travail).createSync(recursive: true);
  try {
    final metas = <String, Map<String, Object?>?>{};
    final els = [for (final e in (man['elements'] as List)) (e as Map).cast<String, Object?>()];
    for (final e in els) {
      final out = BytesBuilder(copy: false);
      for (final b in (e['blocs'] as List).cast<Map>()) {
        final clair = await lire('bloc', '${man['type']}', '${b['id']}');
        if (clair.length != b['clair']) throw _e('BLOC_ALTERE', 'le bloc ${b['id']} n\'a pas la longueur annoncée', 'Choisir une autre copie.', {'bloc': '${b['id']}'});
        out.add(clair);
      }
      final tout = out.takeBytes();
      if (sha256Octets(tout) != e['sha256']) throw _e('EMPREINTE_CLAIR_DIVERGENTE', 'l\'élément ${e['ref']} ne correspond pas à son empreinte', 'Choisir une autre copie.', {'element': e['ref']});
      File('$travail/${e['ref']}').writeAsBytesSync(tout);
      metas['${e['ref']}'] = (e['meta'] as Map?)?.cast<String, Object?>();
    }
    if (apresVerification != null) await apresVerification(travail, els);
    Directory(travail).renameSync(cible);
    return ResultatRestauration(type: type, elements: els.length, octets: man['total'] as int, cible: cible, metas: metas);
  } catch (_) {
    try {
      Directory(travail).deleteSync(recursive: true);
    } catch (_) {/* au mieux */}
    rethrow;
  }
}

/// Le CONTRÔLE nocturne d'une destination : pour le type [type], la dernière copie complète est relue (manifeste déchiffré, cohérent) et [nbBlocs] blocs de données tirés au hasard sont
/// téléchargés, vérifiés (empreinte du bloc, authentification) de bout en bout. Rend `ok`, ou le premier refus nommé. 0 bloc : seul le manifeste est relu.
Future<RefusSauvegarde?> controlerHorsSite({required DestinationSauvegarde dest, required List<int> cle, required String type, required int nbBlocs, Random? hasard}) async {
  final copies = [for (final c in await dest.copies(type)) if (c['etat'] == 'complete') c];
  if (copies.isEmpty) return null;
  final ch = ChiffreurSauvegarde(cle);
  try {
    final c = await dest.copie('${copies.first['id']}');
    final morceaux = <int>[];
    for (final id in (c['racine'] as List).cast<String>()) {
      final blob = await dest.bloc(id);
      if (sha256Octets(blob) != id) return RefusSauvegarde('BLOC_ALTERE', 'le bloc $id du manifeste ne correspond pas à son empreinte', 'Refaire une copie complète ; signaler la panne du disque de la destination.', {'bloc': id});
      morceaux.addAll(await ch.ouvrir('manifeste', type, blob, id));
    }
    final m = jsonDecode(utf8.decode(morceaux));
    final refus = shVerifierManifeste(m);
    if (refus != null) return refus;
    final blocs = <(String, int)>[
      for (final e in ((m as Map)['elements'] as List)) for (final b in ((e as Map)['blocs'] as List)) ('${(b as Map)['id']}', b['clair'] as int)
    ];
    final h = hasard ?? Random.secure();
    blocs.shuffle(h);
    for (final (id, clair) in blocs.take(nbBlocs)) {
      final blob = await dest.bloc(id);
      if (sha256Octets(blob) != id) return RefusSauvegarde('BLOC_ALTERE', 'le bloc $id ne correspond pas à son empreinte', 'Refaire une copie complète ; signaler la panne du disque de la destination.', {'bloc': id});
      final ouvert = await ch.ouvrir('bloc', type, blob, id);
      if (ouvert.length != clair) return RefusSauvegarde('BLOC_ALTERE', 'le bloc $id n\'a pas la longueur annoncée', 'Refaire une copie complète.', {'bloc': id});
    }
    return null;
  } on ErreurSauvegarde catch (x) {
    return x.refus;
  }
}
