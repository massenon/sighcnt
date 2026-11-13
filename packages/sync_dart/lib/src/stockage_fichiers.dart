/// LE STOCKAGE DES FICHIERS NUMÉRISÉS sur le disque d'un poste (fileul ou mère), hors du magasin (lot D5, EF-DOC, EF-SYNC-18).
///
/// Un fichier se range sous `<dossier>/<aa>/<sha256>.<ext>` (`aa` = les deux premiers caractères de l'empreinte), à côté du magasin et SANS réseau. Quatre garanties, toutes
/// vérifiées par un test :
///  - l'empreinte est RECALCULÉE à l'écriture et à CHAQUE lecture : un fichier altéré sur le disque n'est jamais servi, le refus nomme l'empreinte ;
///  - l'écriture est atomique (fichier `.tmp` puis renommage) : une coupure de courant ne laisse jamais un fichier à moitié écrit sous son nom d'empreinte ;
///  - rien ne se supprime (RG-14) : le retrait d'une pièce de sa fiche ne touche jamais le fichier ; seuls les morceaux d'un transfert abandonné ou terminé sont effacés ;
///  - AU REPOS, quand une clé est fournie, le fichier est CHIFFRÉ (AES-256-GCM, nonce frais, l'empreinte liée au chiffré : un fichier recopié sous une autre empreinte ne
///    se déchiffre pas). Sans clé (développement, `SIGH_CHIFFREMENT=non`) : octets en clair, et le dit.
///
/// Les morceaux d'un transfert en cours se rangent sous `_partiels/<sha256>/` (chiffrés eux aussi), de sorte qu'un transfert coupé REPREND au dernier morceau vérifié, même après
/// un redémarrage.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

/// Une erreur NOMMÉE (code, motif, geste) : un refus du stockage, jamais un message muet.
class ErreurFichier implements Exception {
  const ErreurFichier(this.refus);
  final RefusFichier refus;
  @override
  String toString() => refus.toString();
}

/// Ce que `ranger` rend : l'empreinte, le format de stockage, la taille, et ce qui s'est passé (un fichier déjà présent et intact n'est pas réécrit : UNE copie).
class FichierRange {
  const FichierRange({required this.sha256, required this.ext, required this.mime, required this.taille, required this.nouveau, required this.repare});
  final String sha256;
  final String ext;
  final String mime;
  final int taille;

  /// Le fichier n'existait pas sous cette empreinte.
  final bool nouveau;

  /// Il existait mais ALTÉRÉ : les octets reçus l'ont réparé.
  final bool repare;
}

/// L'état d'un fichier sur CE poste, après VÉRIFICATION de son empreinte.
enum EtatLocalFichier { absent, present, altere }

/// La fiche d'accompagnement d'un fichier : où il sert (`usages` : famille et zone, CUMULÉS), son format, sa taille.
class MetaFichier {
  MetaFichier({required this.sha256, required this.mime, required this.ext, required this.taille, required this.usages, this.premiereLe, this.deposePar});
  final String sha256;
  final String mime;
  final String ext;
  final int taille;
  final List<Map<String, Object?>> usages;
  final String? premiereLe;
  final String? deposePar;

  /// La zone la plus STRICTE des usages d'une famille (0 si la famille n'est pas un usage de ce fichier).
  int zoneMax(String famille) {
    var z = 0;
    for (final u in usages) {
      if (u['famille'] == famille) z = max(z, (u['zone'] as num?)?.toInt() ?? 0);
    }
    return z;
  }

  bool sertA(String famille) => usages.any((u) => u['famille'] == famille);

  Map<String, Object?> toJson() => {'sha256': sha256, 'mime': mime, 'ext': ext, 'taille': taille, 'usages': usages, 'premiereLe': premiereLe, 'deposePar': deposePar};

  factory MetaFichier.depuisJson(Map<String, Object?> j) => MetaFichier(
        sha256: '${j['sha256']}',
        mime: '${j['mime']}',
        ext: '${j['ext']}',
        taille: (j['taille'] as num).toInt(),
        usages: [for (final u in (j['usages'] as List? ?? const [])) (u as Map).cast<String, Object?>()],
        premiereLe: j['premiereLe'] as String?,
        deposePar: j['deposePar'] as String?,
      );
}

class StockageFichiers {
  /// [cle] : 32 octets (AES-256) ; `null` ou vide : fichiers EN CLAIR.
  StockageFichiers(this.dossier, {List<int>? cle, DateTime Function()? horloge})
      : _cle = (cle == null || cle.isEmpty) ? null : SecretKey(cle),
        _horloge = horloge ?? DateTime.now {
    if (cle != null && cle.isNotEmpty && cle.length != 32) throw ArgumentError('la clé des fichiers fait 32 octets');
  }

  final String dossier;
  final SecretKey? _cle;
  final DateTime Function() _horloge;
  static final AesGcm _aes = AesGcm.with256bits();
  static const List<int> _entete = [0x53, 0x47, 0x46, 0x31]; // « SGF1 »
  final Random _alea = Random.secure();

  bool get chiffre => _cle != null;

  // --- chemins ---------------------------------------------------------------------------------------------------------------------------

  String _dir(String sha) => '$dossier/${sha.substring(0, 2)}';
  String cheminPour(String sha, String ext) => '${_dir(sha)}/$sha.$ext';
  String _cheminMeta(String sha) => '${_dir(sha)}/$sha.json';
  String _dirPartiels(String sha) => '$dossier/_partiels/$sha';

  static void _exigerEmpreinte(String sha) {
    if (!empreinteValide(sha)) {
      throw const ErreurFichier(RefusFichier('EMPREINTE_INVALIDE', 'l’empreinte demandée n’est pas un SHA-256 (64 caractères hexadécimaux)', 'Ouvrir la pièce depuis sa fiche.'));
    }
  }

  static const List<String> _extensions = ['pdf', 'jpg', 'png', 'webp'];

  /// Le chemin du fichier rangé sous cette empreinte, ou `null` s'il n'est pas (encore) arrivé sur ce poste.
  Future<String?> cheminDe(String sha) async {
    _exigerEmpreinte(sha);
    for (final e in _extensions) {
      final p = cheminPour(sha, e);
      if (await File(p).exists()) return p;
    }
    return null;
  }

  Future<bool> existe(String sha) async => (await cheminDe(sha)) != null;

  // --- chiffrement au repos ------------------------------------------------------------------------------------------------------------

  Future<List<int>> _sceller(List<int> clair, String aad) async {
    if (_cle == null) return clair;
    final b = await _aes.encrypt(clair, secretKey: _cle!, aad: utf8.encode(aad));
    return [..._entete, ...b.concatenation()];
  }

  /// Rend le clair, ou `null` si le contenu ne se déchiffre pas (altéré, autre clé, autre empreinte).
  Future<Uint8List?> _ouvrir(List<int> brut, String aad) async {
    if (_cle == null) return Uint8List.fromList(brut);
    if (brut.length < 4 + 12 + 16 || !(brut[0] == _entete[0] && brut[1] == _entete[1] && brut[2] == _entete[2] && brut[3] == _entete[3])) return null;
    try {
      final b = SecretBox.fromConcatenation(brut.sublist(4), nonceLength: 12, macLength: 16);
      return Uint8List.fromList(await _aes.decrypt(b, secretKey: _cle!, aad: utf8.encode(aad)));
    } catch (_) {
      return null;
    }
  }

  Future<void> _ecrireAtomique(String chemin, List<int> octets) async {
    final f = File(chemin);
    await f.parent.create(recursive: true);
    final tmp = File('$chemin.${_alea.nextInt(1 << 30).toRadixString(16)}.tmp');
    try {
      await tmp.writeAsBytes(octets, flush: true);
      await tmp.rename(chemin);
    } catch (e) {
      try {
        await tmp.delete();
      } catch (_) {}
      throw ErreurFichier(RefusFichier('ECRITURE_IMPOSSIBLE', 'le poste n’a pas pu ranger le fichier ($e)', 'Vérifier les droits d’écriture et la place libre du dossier des données.'));
    }
  }

  // --- lecture, vérification ------------------------------------------------------------------------------------------------------------

  String? _cacheSha;
  Uint8List? _cacheOctets;

  /// Les octets du fichier, EMPREINTE VÉRIFIÉE. Absent : `FICHIER_ABSENT` ; altéré (déchiffrement impossible ou empreinte différente) : `FICHIER_ALTERE`, jamais servi.
  Future<Uint8List> lire(String sha) async {
    _exigerEmpreinte(sha);
    if (_cacheSha == sha && _cacheOctets != null) return _cacheOctets!;
    final chemin = await cheminDe(sha);
    if (chemin == null) {
      throw const ErreurFichier(RefusFichier('FICHIER_ABSENT', 'ce fichier n’est pas (encore) arrivé sur ce poste', 'Attendre la synchronisation des fichiers, ou redéposer le scan depuis la fiche.'));
    }
    final brut = await File(chemin).readAsBytes();
    var clair = await _ouvrir(brut, 'fichier:$sha');
    // Un fichier en CLAIR sur un poste devenu chiffré (reste d'un poste d'avant) : lu si l'empreinte tient, puis réécrit chiffré. Sinon, altéré.
    if (clair == null && chiffre && sha256Octets(brut) == sha) {
      clair = Uint8List.fromList(brut);
      await _ecrireAtomique(chemin, await _sceller(clair, 'fichier:$sha'));
    }
    if (clair == null || sha256Octets(clair) != sha) {
      throw ErreurFichier(RefusFichier('FICHIER_ALTERE', 'le fichier rangé sur ce poste n’a plus son empreinte (${docAbrege(sha)}) : il n’est pas servi',
          'Redemander le fichier à la mère, ou redéposer le scan depuis la fiche.', {'sha256': sha}));
    }
    _cacheSha = sha;
    _cacheOctets = clair;
    return clair;
  }

  /// L'état de CE fichier sur ce poste, après vérification de l'empreinte.
  Future<EtatLocalFichier> etat(String sha) async {
    if (!await existe(sha)) return EtatLocalFichier.absent;
    try {
      await lire(sha);
      return EtatLocalFichier.present;
    } on ErreurFichier catch (e) {
      return e.refus.code == 'FICHIER_ALTERE' ? EtatLocalFichier.altere : EtatLocalFichier.absent;
    }
  }

  // --- rangement ----------------------------------------------------------------------------------------------------------------------

  /// Range des octets COMPLETS. L'empreinte est calculée ICI (celle que l'appelant annonce n'est qu'une promesse qu'on vérifie), le format est lu sur les OCTETS et doit être
  /// admis de la [famille] ; la taille ne dépasse pas [tailleMax]. Un fichier déjà présent et intact n'est PAS réécrit (une copie, jamais deux) ; un fichier altéré est RÉPARÉ par
  /// les octets reçus. La fiche d'accompagnement cumule les usages (famille, zone).
  Future<FichierRange> ranger(Uint8List octets,
      {required String famille, required int zone, String? deposePar, String? shaAnnonce, int? tailleMax}) async {
    if (octets.isEmpty) throw const ErreurFichier(RefusFichier('FICHIER_VIDE', 'le fichier ne contient aucun octet', 'Choisir un fichier numérisé non vide.'));
    if (tailleMax != null && octets.length > tailleMax) {
      throw ErreurFichier(RefusFichier('TAILLE_DEPASSEE', 'le fichier pèse ${fichierPoids(octets.length)}, le maximum réglé est ${fichierPoids(tailleMax)}',
          'Numériser en résolution plus basse, ou demander à l’administrateur de relever la taille maximale.'));
    }
    final c = fichierControlerContenu(octets, famille);
    if (c.refus != null) throw ErreurFichier(c.refus!);
    final sha = sha256Octets(octets);
    if (shaAnnonce != null && shaAnnonce.isNotEmpty && shaAnnonce != sha) {
      throw ErreurFichier(RefusFichier('EMPREINTE_DIVERGENTE', 'le fichier reçu n’a pas l’empreinte annoncée (transport altéré)', 'Déposer de nouveau le fichier.', {'recu': sha, 'annonce': shaAnnonce}));
    }
    final ext = fichierExtDeMime(c.format!.mime);
    final chemin = cheminPour(sha, ext);
    var nouveau = true;
    var repare = false;
    if (await File(chemin).exists()) {
      nouveau = false;
      final brut = await File(chemin).readAsBytes();
      final clair = await _ouvrir(brut, 'fichier:$sha');
      if (clair == null || sha256Octets(clair) != sha) {
        repare = true;
        await _ecrireAtomique(chemin, await _sceller(octets, 'fichier:$sha'));
      }
    } else {
      await _ecrireAtomique(chemin, await _sceller(octets, 'fichier:$sha'));
    }
    _cacheSha = null;
    _cacheOctets = null;
    final ancien = await meta(sha);
    final usages = [...?ancien?.usages];
    if (!usages.any((u) => u['famille'] == famille && u['zone'] == zone)) usages.add({'famille': famille, 'zone': zone});
    final m = MetaFichier(
        sha256: sha,
        mime: c.format!.mime,
        ext: ext,
        taille: octets.length,
        usages: usages,
        premiereLe: ancien?.premiereLe ?? _horloge().toIso8601String(),
        deposePar: ancien?.deposePar ?? deposePar);
    await _ecrireAtomique(_cheminMeta(sha), await _sceller(utf8.encode(jsonEncode(m.toJson())), 'meta:$sha'));
    return FichierRange(sha256: sha, ext: ext, mime: c.format!.mime, taille: octets.length, nouveau: nouveau, repare: repare);
  }

  /// La fiche d'accompagnement d'un fichier, ou `null`.
  Future<MetaFichier?> meta(String sha) async {
    _exigerEmpreinte(sha);
    final f = File(_cheminMeta(sha));
    if (!await f.exists()) return null;
    final clair = await _ouvrir(await f.readAsBytes(), 'meta:$sha');
    if (clair == null) return null;
    try {
      return MetaFichier.depuisJson((jsonDecode(utf8.decode(clair)) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  /// Toutes les empreintes rangées sur ce poste (sans lire les fichiers).
  Stream<String> empreintes() async* {
    final d = Directory(dossier);
    if (!await d.exists()) return;
    await for (final sous in d.list()) {
      if (sous is! Directory) continue;
      final nom = sous.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (nom.length != 2 || nom.startsWith('_')) continue;
      await for (final f in sous.list()) {
        if (f is! File) continue;
        final n = f.uri.pathSegments.last;
        final m = RegExp(r'^([0-9a-f]{64})\.(pdf|jpg|png|webp)$').firstMatch(n);
        if (m != null) yield m.group(1)!;
      }
    }
  }

  // --- transfert par morceaux avec reprise ---------------------------------------------------------------------------------------------

  String _cheminPartie(String sha, int i) => '${_dirPartiels(sha)}/$i.part';

  /// Ouvre (ou ROUVRE après une coupure) la réception d'un fichier : les morceaux déjà rangés sont RELUS ET RE-VÉRIFIÉS contre la description (une coupure en plein écriture ou
  /// un disque abîmé ne rend pas un morceau « reçu »), seuls les bons comptent. La description est refusée si elle est incohérente.
  Future<ReceptionFichier> ouvrirReception(DescriptionFichier d, {int tailleMax = 64 * 1024 * 1024}) async {
    final inco = d.incoherence(tailleMax: tailleMax);
    if (inco != null) throw ErreurFichier(inco);
    final dir = Directory(_dirPartiels(d.sha256));
    final deja = <int>[];
    if (await dir.exists()) {
      for (var i = 0; i < d.plan.nombre; i++) {
        final f = File(_cheminPartie(d.sha256, i));
        if (!await f.exists()) continue;
        final clair = await _ouvrir(await f.readAsBytes(), 'part:${d.sha256}:$i');
        if (clair != null && clair.length == d.plan.longueur(i) && sha256Octets(clair) == d.morceaux[i]) {
          deja.add(i);
        } else {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } else {
      await dir.create(recursive: true);
    }
    return ReceptionFichier(d, deja: deja);
  }

  /// Reçoit UN morceau : refusé en nommant s'il est altéré (il n'est pas rangé), rangé atomiquement sinon. Un morceau déjà reçu et vérifié est accepté sans réécriture.
  Future<RefusFichier?> deposerMorceau(ReceptionFichier r, int i, Uint8List octets) async {
    final refus = r.accepter(i, octets);
    if (refus != null) return refus;
    final f = File(_cheminPartie(r.description.sha256, i));
    if (!await f.exists()) {
      await _ecrireAtomique(f.path, await _sceller(octets, 'part:${r.description.sha256}:$i'));
    }
    return null;
  }

  /// Assemble les morceaux VÉRIFIÉS, vérifie l'empreinte de l'ENSEMBLE, puis range le fichier (format lu sur les octets, famille admise) et efface les morceaux. L'échec de
  /// l'assemblage jette les morceaux (ils ne prouvent pas un assemblage faux) et le dit.
  Future<FichierRange> assembler(ReceptionFichier r, {required String famille, required int zone, String? deposePar, int? tailleMax}) async {
    if (!r.complet) {
      throw ErreurFichier(RefusFichier('TRANSFERT_INCOMPLET', 'il manque ${r.manquants.length} morceau(x) : ${r.manquants.take(5).join(', ')}', 'Reprendre le transfert avec les morceaux manquants.', {'manquants': r.manquants}));
    }
    final sha = r.description.sha256;
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < r.description.plan.nombre; i++) {
      final clair = await _ouvrir(await File(_cheminPartie(sha, i)).readAsBytes(), 'part:$sha:$i');
      if (clair == null) {
        await abandonner(sha);
        throw ErreurFichier(RefusFichier('MORCEAU_ALTERE', 'le morceau $i rangé sur ce poste est illisible', 'Redemander le fichier.', {'morceau': i}));
      }
      out.add(clair);
    }
    final octets = out.takeBytes();
    final ens = r.verifierEnsemble(octets);
    if (ens != null) {
      await abandonner(sha);
      throw ErreurFichier(ens);
    }
    try {
      final res = await ranger(octets, famille: famille, zone: zone, deposePar: deposePar, shaAnnonce: sha, tailleMax: tailleMax);
      await abandonner(sha);
      return res;
    } on ErreurFichier {
      await abandonner(sha);
      rethrow;
    }
  }

  /// Efface les morceaux d'un transfert (terminé, abandonné ou invalide). Jamais le fichier lui-même.
  Future<void> abandonner(String sha) async {
    final d = Directory(_dirPartiels(sha));
    if (await d.exists()) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Les morceaux DÉJÀ rangés d'une empreinte (sans re-vérification : pour dire où en est un transfert).
  Future<List<int>> morceauxRanges(String sha) async {
    final d = Directory(_dirPartiels(sha));
    if (!await d.exists()) return const [];
    final out = <int>[];
    await for (final f in d.list()) {
      final m = RegExp(r'(\d+)\.part$').firstMatch(f.path);
      if (m != null) out.add(int.parse(m.group(1)!));
    }
    return out..sort();
  }
}
