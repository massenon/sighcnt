/// LES FICHIERS NUMÉRISÉS CÔTÉ MÈRE (lot D5, EF-SYNC-18) : les routes `/fichiers/*` par lesquelles un FILEUL dépose un fichier et en vient chercher. Les fichiers voyagent À PART
/// du journal, par leur empreinte SHA-256 : les métadonnées (la fiche, le registre `fichiers`) passent par le journal comme toute fiche ; le BINAIRE passe ici, par morceaux
/// dont chacun porte son empreinte, avec REPRISE, l'empreinte de l'ensemble étant vérifiée avant de ranger.
///
///   POST /fichiers/ouvrir    {famille, type?, description}      ouvre (ou rouvre) un dépôt : rend les morceaux déjà reçus, ou `complet` si la mère a déjà ce fichier
///   PUT  /fichiers/morceau   ?sha256=&i=   corps = octets         reçoit UN morceau (refusé s'il est altéré : 409 MORCEAU_ALTERE, à renvoyer)
///   POST /fichiers/terminer  {sha256}                             assemble, vérifie l'ensemble, range (idempotent)
///   GET  /fichiers/info      ?sha256=&famille=[&morceau=]        la description (empreintes des morceaux) d'un fichier que la mère a
///   GET  /fichiers/morceau   ?sha256=&i=&famille=                 un morceau
///
/// CE QUI EST TENU ICI : la mère ne CONTACTE jamais un poste, l'appareil vient chercher ; JAMAIS vers un téléphone (RG-13) : tout appareil `mobile` est refusé, quelle que soit la
/// zone ; le droit est celui de la matrice `rbac.json` sur l'écran de la famille PLUS la zone du type de document (un poste dont le rôle ne lit pas la zone ne reçoit PAS le
/// binaire, et ne peut pas non plus le déposer) ; une seule copie par empreinte (un second déposant du même fichier cumule son usage, rien n'est recopié).
///
/// LIMITE DITE : le rôle de l'agent est DÉCLARÉ par l'appareil (en-tête `x-sigh-role`), comme celui d'une opération du journal : la mère authentifie l'APPAREIL, non la personne.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'mere.dart';
import 'stockage_fichiers.dart';

/// Le statut HTTP d'un refus nommé.
int _statut(String code) => switch (code) {
      'DROIT_REFUSE' || 'ZONE_REFUSEE' || 'FICHIERS_INTERDITS_AU_MOBILE' || 'PIECE_NON_RATTACHEE' => 403,
      'FICHIER_ABSENT' => 404,
      'FICHIER_ALTERE' || 'MORCEAU_ALTERE' || 'EMPREINTE_DIVERGENTE' || 'TRANSFERT_NON_OUVERT' || 'TRANSFERT_INCOMPLET' => 409,
      'FORMAT_REFUSE' => 415,
      'TAILLE_DEPASSEE' => 413,
      'MATRICE_INTROUVABLE' || 'FICHIERS_NON_ACTIVES' => 503,
      _ => 400,
    };

class _Reception {
  _Reception(this.reception, this.famille, this.zone, this.appareil, this.role);
  final ReceptionFichier reception;
  final String famille;
  final int zone;
  final String appareil;
  final String role;
}

/// Trouve `packages/rbac/data/rbac.json` (chemin donné, sinon en remontant depuis le dossier courant) et en tire la matrice. Refus nommé si introuvable ou illisible.
MatriceDroits chargerMatriceRbac(String chemin) {
  var f = chemin.isEmpty ? null : File(chemin);
  if (f == null) {
    var d = Directory.current.absolute;
    for (var i = 0; i < 8 && f == null; i++) {
      final c = File('${d.path}/packages/rbac/data/rbac.json');
      if (c.existsSync()) f = c;
      d = d.parent;
    }
  }
  if (f == null || !f.existsSync()) throw const ErreurFichier(RefusFichier('MATRICE_INTROUVABLE', 'la matrice des droits (rbac.json) est introuvable sur la mère', 'Indiquer le chemin de rbac.json à la configuration de la mère.'));
  try {
    return MatriceDroits.depuisJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
  } catch (e) {
    throw ErreurFichier(RefusFichier('MATRICE_INTROUVABLE', 'la matrice des droits (${f.path}) est illisible : $e', 'Régénérer rbac.json depuis la maquette.'));
  }
}

class FichiersMere {
  FichiersMere(this.mere, this.stockage, {MatriceDroits Function()? matrice}) : _matriceFournie = matrice;
  final Mere mere;
  final StockageFichiers stockage;
  final MatriceDroits Function()? _matriceFournie;
  MatriceDroits? _matrice;
  final Map<String, _Reception> _receptions = {};

  MatriceDroits get matrice => _matrice ??= (_matriceFournie ?? () => chargerMatriceRbac(mere.cfg.matriceChemin))();

  /// Le nombre de dépôts en cours (pour un contrôle de test).
  int get depotsEnCours => _receptions.length;

  Future<void> _repondreJson(HttpRequest req, int statut, Object? corps) => repondre(req, statut, corps);

  Future<void> _repondreRefus(HttpRequest req, RefusFichier r) => _repondreJson(req, _statut(r.code), r.toJson());

  Future<Uint8List> _corps(HttpRequest req, {int max = 5 * 1024 * 1024}) async {
    final b = BytesBuilder(copy: false);
    await for (final c in req) {
      b.add(c);
      if (b.length > max) throw const ErreurFichier(RefusFichier('TAILLE_DEPASSEE', 'le morceau reçu dépasse la taille maximale d’un morceau', 'Renvoyer des morceaux de la taille annoncée.'));
    }
    return b.takeBytes();
  }

  /// Le point d'entrée : authentifie l'APPAREIL (sous le verrou de la base), refuse tout téléphone, lit le rôle déclaré, puis route.
  Future<void> traiter(HttpRequest req) async {
    try {
      final app = await mere.verrou.executer(() => mere.auth(req));
      if (app.role == 'mobile') {
        throw const ErreurFichier(RefusFichier('FICHIERS_INTERDITS_AU_MOBILE', 'les fichiers numérisés ne sont jamais envoyés à un téléphone (RG-13)', 'Consulter la pièce depuis un poste de la clinique.'));
      }
      final role = req.headers.value('x-sigh-role') ?? '';
      if (role.isEmpty) throw const ErreurFichier(RefusFichier('ROLE_REQUIS', 'le rôle de l’agent n’est pas déclaré', 'Mettre le poste à jour.'));
      final q = req.uri.queryParameters;
      switch ('${req.method} ${req.uri.path}') {
        case 'POST /fichiers/ouvrir':
          return await _ouvrir(req, app, role);
        case 'PUT /fichiers/morceau':
          return await _recevoir(req, app, q);
        case 'POST /fichiers/terminer':
          return await _terminer(req, app, role);
        case 'GET /fichiers/info':
          return await _info(req, role, q);
        case 'GET /fichiers/morceau':
          return await _servir(req, role, q);
      }
      throw const ErreurFichier(RefusFichier('ACTION_INCONNUE', 'route de fichiers inconnue', 'Mettre le poste à jour.'));
    } on ErreurFichier catch (e) {
      await _repondreRefus(req, e.refus);
    } on Err catch (e) {
      await _repondreJson(req, e.statut, e.corps);
    } catch (e) {
      mere.evenementAsync('erreur', 'fichiers', '${req.method} ${req.uri.path} : $e');
      await _repondreJson(req, 500, {'code': 'erreur_interne', 'motif': '$e'});
    }
  }

  void _exiger(RefusFichier? r) {
    if (r != null) throw ErreurFichier(r);
  }

  String _famille(Object? f) {
    final s = '${f ?? ''}';
    if (!fichierFamilles.contains(s)) throw ErreurFichier(RefusFichier('FAMILLE_INCONNUE', 'la famille « $s » n’existe pas', 'Indiquer courrier ou patient.'));
    return s;
  }

  RefusFichier? _droit(String role, String famille, String geste, String? type) =>
      fichierRefusDroit(role: role, famille: famille, geste: geste, type: type, droitEcran: matrice.droit(role, fichierEcranDeFamille(famille)));

  Future<void> _ouvrir(HttpRequest req, Appareil app, String role) async {
    final b = await corpsJson(req);
    final famille = _famille(b['famille']);
    final type = b['type'] == null ? null : '${b['type']}';
    _exiger(_droit(role, famille, 'editer', type));
    final desc = DescriptionFichier.depuisJson(((b['description'] ?? {}) as Map).cast<String, Object?>());
    final inco = desc.incoherence();
    if (inco != null) throw ErreurFichier(inco);
    final zone = famille == 'patient' ? docZoneDe(type) : 0;
    final sha = desc.sha256;
    if (await stockage.etat(sha) == EtatLocalFichier.present) {
      // UNE copie par empreinte : le second déposant cumule son usage, rien n'est recopié.
      await stockage.ajouterUsage(sha, famille: famille, zone: zone);
      _receptions.remove(sha);
      return _repondreJson(req, 200, {'ok': true, 'complet': true, 'sha256': sha, 'recus': <int>[], 'morceaux': desc.plan.nombre});
    }
    final r = await stockage.ouvrirReception(desc);
    _receptions[sha] = _Reception(r, famille, zone, app.uuid, role);
    await _repondreJson(req, 200, {'ok': true, 'complet': false, 'sha256': sha, 'recus': (r.verifies.toList()..sort()), 'morceaux': desc.plan.nombre});
  }

  Future<void> _recevoir(HttpRequest req, Appareil app, Map<String, String> q) async {
    final sha = '${q['sha256'] ?? ''}';
    if (!empreinteValide(sha)) throw const ErreurFichier(RefusFichier('EMPREINTE_INVALIDE', 'l’empreinte demandée n’est pas un SHA-256 (64 caractères hexadécimaux)', 'Rouvrir le dépôt.'));
    final i = int.tryParse('${q['i'] ?? ''}');
    final r = _receptions[sha];
    if (r == null || r.appareil != app.uuid) {
      throw const ErreurFichier(RefusFichier('TRANSFERT_NON_OUVERT', 'aucun dépôt ouvert pour cette empreinte (la mère a pu redémarrer)', 'Rouvrir le dépôt : il reprend au dernier morceau vérifié.'));
    }
    final octets = await _corps(req, max: r.reception.description.tailleMorceau + 1024);
    final refus = await stockage.deposerMorceau(r.reception, i ?? -1, octets);
    if (refus != null) throw ErreurFichier(refus);
    await _repondreJson(req, 200, {'ok': true, 'recus': r.reception.verifies.length, 'morceaux': r.reception.description.plan.nombre});
  }

  Future<void> _terminer(HttpRequest req, Appareil app, String role) async {
    final b = await corpsJson(req);
    final sha = '${b['sha256'] ?? ''}';
    if (!empreinteValide(sha)) throw const ErreurFichier(RefusFichier('EMPREINTE_INVALIDE', 'l’empreinte demandée n’est pas un SHA-256 (64 caractères hexadécimaux)', 'Rouvrir le dépôt.'));
    final r = _receptions[sha];
    if (r == null) {
      // Idempotence : un « terminer » rejoué après le rangement répond comme la première fois.
      if (await stockage.etat(sha) == EtatLocalFichier.present) return _repondreJson(req, 200, {'ok': true, 'sha256': sha, 'nouveau': false});
      throw const ErreurFichier(RefusFichier('TRANSFERT_NON_OUVERT', 'aucun dépôt ouvert pour cette empreinte (la mère a pu redémarrer)', 'Rouvrir le dépôt : il reprend au dernier morceau vérifié.'));
    }
    if (r.appareil != app.uuid) throw const ErreurFichier(RefusFichier('TRANSFERT_NON_OUVERT', 'ce dépôt a été ouvert par un autre appareil', 'Rouvrir le dépôt.'));
    try {
      final res = await stockage.assembler(r.reception, famille: r.famille, zone: r.zone, deposePar: role);
      _receptions.remove(sha);
      mere.evenementAsync('info', 'fichiers', 'Fichier reçu ${docAbrege(sha)} (${r.famille}, ${fichierPoids(res.taille)})');
      await _repondreJson(req, 200, {'ok': true, 'sha256': sha, 'nouveau': res.nouveau});
    } on ErreurFichier catch (e) {
      if (e.refus.code != 'TRANSFERT_INCOMPLET') _receptions.remove(sha);
      rethrow;
    }
  }

  /// Le droit de LIRE un fichier par une famille : l'écran de la famille et la ZONE du type, relue de la fiche d'accompagnement (jamais d'un paramètre du client). Même
  /// règle que `api/fichiers.php` : un fichier inconnu n'est pas dit « absent » avant le contrôle du droit.
  Future<MetaFichier?> _autoriserLecture(String role, String famille, String sha) async {
    if (!empreinteValide(sha)) throw const ErreurFichier(RefusFichier('EMPREINTE_INVALIDE', 'l’empreinte demandée n’est pas un SHA-256 (64 caractères hexadécimaux)', 'Ouvrir la pièce depuis sa fiche.'));
    final meta = await stockage.meta(sha);
    final zoneMax = meta?.zoneMax(famille) ?? 0;
    final typeFictif = zoneMax >= 2 ? '__zone2__' : (famille == 'patient' ? 'Pièce d’identité' : null);
    _exiger(_droit(role, famille, 'voir', typeFictif));
    if (meta != null && !meta.sertA(famille)) {
      throw ErreurFichier(RefusFichier('PIECE_NON_RATTACHEE', 'cette empreinte n’est pas rattachée à la famille « $famille »', 'Ouvrir la pièce depuis la fiche qui la porte.'));
    }
    return meta;
  }

  Future<void> _info(HttpRequest req, String role, Map<String, String> q) async {
    final famille = _famille(q['famille']);
    final sha = '${q['sha256'] ?? ''}';
    final meta = await _autoriserLecture(role, famille, sha);
    final taille = int.tryParse('${q['morceau'] ?? ''}') ?? fichierTailleMorceau;
    final octets = await stockage.lire(sha);
    final d = DescriptionFichier.deOctets(octets, taille);
    final inco = d.incoherence();
    if (inco != null) throw ErreurFichier(inco);
    await _repondreJson(req, 200, {'ok': true, 'description': d.toJson(), 'mime': meta?.mime, 'ext': meta?.ext});
  }

  Future<void> _servir(HttpRequest req, String role, Map<String, String> q) async {
    final famille = _famille(q['famille']);
    final sha = '${q['sha256'] ?? ''}';
    await _autoriserLecture(role, famille, sha);
    final taille = int.tryParse('${q['morceau'] ?? ''}') ?? fichierTailleMorceau;
    final i = int.tryParse('${q['i'] ?? ''}') ?? -1;
    final octets = await stockage.lire(sha);
    final plan = PlanMorceaux(octets.length, taille);
    if (i < 0 || i >= plan.nombre) throw ErreurFichier(RefusFichier('MORCEAU_HORS_PLAN', 'le morceau $i n’existe pas dans ce fichier (${plan.nombre} morceaux)', 'Reprendre le transfert avec la liste des morceaux manquants.'));
    final part = Uint8List.sublistView(octets, plan.debut(i), plan.fin(i));
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.binary
      ..headers.set('x-sigh-morceau-sha256', sha256Octets(part))
      ..headers.contentLength = part.length
      ..add(part);
    await req.response.close();
  }
}
