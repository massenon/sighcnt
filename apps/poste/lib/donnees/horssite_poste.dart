import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Ce que le poste sait demander à la copie hors site de la MÈRE (le service local, routes `/admin/horssite/*`). Une interface : un test la remplace par un double ; un fileul n'en a pas
/// (l'état se lit sur le poste mère). Un refus de la mère arrive en [RefusSauvegarde] nommé (code, motif, geste).
abstract class SourceHorsSite {
  Future<Map<String, Object?>> etat();
  Future<Map<String, Object?>> lancer(String type);
  Future<Map<String, Object?>> controler();
  Future<List<Map<String, Object?>>> copies(String type);
  Future<Map<String, Object?>> restaurer({required String type, required String copie, required String cible});
}

class ErreurHorsSite implements Exception {
  const ErreurHorsSite(this.refus);
  final RefusSauvegarde refus;
  @override
  String toString() => refus.toString();
}

/// La source réelle : le service de la mère sur cette machine (`http://127.0.0.1:9000`), avec son secret d'administration.
class SourceHorsSiteHttp implements SourceHorsSite {
  SourceHorsSiteHttp({required this.base, required this.admin, http.Client? client}) : _c = client ?? http.Client();
  final Uri base;
  final String admin;
  final http.Client _c;

  Future<Map<String, Object?>> _appel(String methode, String chemin, [Map<String, Object?>? corps]) async {
    final req = http.Request(methode, base.resolve(chemin))
      ..headers['x-admin'] = admin
      ..headers['content-type'] = 'application/json';
    if (corps != null) req.body = jsonEncode(corps);
    final http.Response rep;
    try {
      rep = await http.Response.fromStream(await _c.send(req).timeout(const Duration(minutes: 30)));
    } catch (_) {
      throw const ErreurHorsSite(RefusSauvegarde('MERE_INJOIGNABLE', 'le service de la poste mère ne répond pas', 'Vérifier que la poste mère est démarrée sur cette machine.'));
    }
    Map<String, Object?> j = {};
    try {
      j = (jsonDecode(utf8.decode(rep.bodyBytes)) as Map).cast<String, Object?>();
    } catch (_) {/* vide */}
    if (rep.statusCode >= 400) {
      throw ErreurHorsSite(RefusSauvegarde('${j['code'] ?? 'ERREUR_MERE'}', '${j['motif'] ?? 'réponse ${rep.statusCode}'}', '${j['geste'] ?? ''}'));
    }
    return j;
  }

  @override
  Future<Map<String, Object?>> etat() => _appel('GET', '/admin/horssite/etat');
  @override
  Future<Map<String, Object?>> lancer(String type) => _appel('POST', '/admin/horssite/lancer', {'type': type});
  @override
  Future<Map<String, Object?>> controler() => _appel('POST', '/admin/horssite/controler', {});
  @override
  Future<List<Map<String, Object?>>> copies(String type) async => [for (final c in ((await _appel('GET', '/admin/horssite/copies?type=$type'))['copies'] as List)) (c as Map).cast<String, Object?>()];
  @override
  Future<Map<String, Object?>> restaurer({required String type, required String copie, required String cible}) => _appel('POST', '/admin/horssite/restaurer', {'type': type, 'copie': copie, 'cible': cible});
}

/// LA COPIE HORS SITE AU POSTE (lot 5, ADR-0007). Le RÉGLAGE est un paramètre de clinique en base (famille `horssite`, versionné par date, défaut semé : DÉSACTIVÉE), posé à la poste mère
/// et reçu des fileuls par le journal ; il est réservé à l'administrateur et à la DAF, motivé, journalisé (RG-12). Un FILEUL le lit et ne le pose pas (refus nommé, commande absente de l'écran).
/// L'ÉTAT et les gestes (copier maintenant, contrôler, restaurer) passent par le service de la mère ([SourceHorsSite]) : un fileul n'en a pas.
class HorsSitePoste extends ChangeNotifier {
  HorsSitePoste(this.magasin, {bool Function()? estFileul, bool Function()? estMere, SourceHorsSite? source})
      : estFileul = estFileul ?? (() => false),
        _source = source,
        _estMere = estMere ?? (() => source != null);

  final Magasin magasin;
  final bool Function() estFileul;
  final SourceHorsSite? _source;
  final bool Function() _estMere;

  /// La source de l'état et des gestes : le service de la mère de CETTE machine, et seulement si ce poste est la mère (le mode peut changer pendant que l'application tourne).
  SourceHorsSite? get source => _estMere() ? _source : null;

  static final Expando<HorsSitePoste> _installes = Expando<HorsSitePoste>('HorsSitePoste');
  static HorsSitePoste? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;

  Map<String, Object?>? etatMere;
  RefusSauvegarde? erreurEtat;
  bool enCours = false;

  ServiceParametres get _parametres => serviceParametres(magasin, auteur: () => magasin.utilisateur, horloge: () => magasin.horloge());
  String get _aujourdhui => parametreDateIso(magasin.horloge());

  /// Le réglage est-il REÇU ? La fiche d'activation (même son semis) est arrivée : sinon on ne lit pas un défaut qui peut différer de ce que la mère a posé.
  bool get reglageRecu => _parametres.versions(shCleActif).isNotEmpty;

  /// Le réglage de la clinique, lu de la base (jamais du code). Non reçu : les défauts du domaine, [reglageRecu] faux, et l'écran le DIT (jamais « désactivée » en silence).
  ReglageHorsSite get reglage {
    if (!reglageRecu) return const ReglageHorsSite();
    final p = _parametres, d = _aujourdhui;
    int entier(String cle, int defaut) {
      final v = p.valeur(cle, d);
      return v is num ? v.toInt() : defaut;
    }

    String texte(String cle) => '${p.valeur(cle, d) ?? ''}';
    return ReglageHorsSite(
      actif: p.valeur(shCleActif, d) == true,
      magasin: ReglageType(destination: texte(shCleDestinationMagasin), dossier: texte(shCleDossierMagasin), copies: entier(shCleCopiesMagasin, shCopiesMagasinDefaut)),
      fichiers: ReglageType(destination: texte(shCleDestinationFichiers), dossier: texte(shCleDossierFichiers), copies: entier(shCleCopiesFichiers, shCopiesFichiersDefaut)),
      frequenceMinutes: entier(shCleFrequence, shFrequenceDefaut),
      heureControle: entier(shCleHeureControle, shHeureControleDefaut),
      tailleBloc: entier(shCleTailleBloc, shTailleBlocDefaut),
      blocsControles: entier(shCleBlocsControles, shBlocsControlesDefaut),
    );
  }

  bool peutRegler(String role) => shPeutRegler(role);

  Map<String, Object?> _valeurs(ReglageHorsSite r) => {
        shCleActif: r.actif,
        shCleDestinationMagasin: r.magasin.destination,
        shCleDestinationFichiers: r.fichiers.destination,
        shCleDossierMagasin: r.magasin.dossier,
        shCleDossierFichiers: r.fichiers.dossier,
        shCleFrequence: r.frequenceMinutes,
        shCleHeureControle: r.heureControle,
        shCleCopiesMagasin: r.magasin.copies,
        shCleCopiesFichiers: r.fichiers.copies,
        shCleTailleBloc: r.tailleBloc,
        shCleBlocsControles: r.blocsControles,
      };

  /// Pose le réglage : refus nommé (jamais silencieux) si fileul, rôle sans droit, motif absent, réglage hors bornes, activation sans destination, relais non relié (quand la mère le dit). N'écrit
  /// que ce qui change, comme NOUVELLE VERSION datée du jour ; journalisé (RG-12). Rend le refus ou `null`.
  RefusSauvegarde? definirReglage({required String role, required ReglageHorsSite nouveau, required String? motif}) {
    if (estFileul()) {
      return const RefusSauvegarde('FILEUL_LECTURE_SEULE', 'la copie hors site est un réglage de la clinique, posé à la poste mère : ce poste le reçoit par le journal', 'Régler la copie hors site sur le poste mère : ce poste reçoit ce réglage par le journal.');
    }
    if (!peutRegler(role)) {
      return const RefusSauvegarde('REGLAGE_RESERVE', 'seuls l\'administrateur et la Directrice Administrative règlent la copie hors site', 'Demander à l\'administrateur ou à la Directrice Administrative.');
    }
    final m = (motif ?? '').trim();
    if (m.isEmpty) return const RefusSauvegarde('MOTIF_REQUIS', 'le motif du réglage est obligatoire', 'Écrire pourquoi la copie hors site change (RG-12).');
    final ctrl = shVerifierReglageClinique(nouveau);
    if (ctrl != null) return ctrl;
    final etat = etatMere;
    if (nouveau.actif && etat != null && etat['relaisRelie'] == false && (nouveau.magasin.destination == 'relais' || nouveau.fichiers.destination == 'relais')) {
      return const RefusSauvegarde('RELAIS_NON_CONFIGURE', 'la poste mère n\'est pas reliée au relais web', 'Relier la mère au relais (adresse et secret de la mère), ou choisir un dossier distant.');
    }
    final avant = reglage;
    final p = _parametres;
    final voulu = _valeurs(nouveau), courant = _valeurs(avant);
    try {
      // Un poste autonome qui n'a pas encore le semis le sème (version 0 identique partout). Un fileul ne le peut pas : la garde du magasin le refuse.
      if (!reglageRecu) p.semerDefauts();
      final dejaLa = _valeurs(reglage);
      for (final e in voulu.entries) {
        if (dejaLa[e.key] == e.value) continue;
        final w = p.regler(e.key, e.value, _aujourdhui, motif: m);
        if (!w.ok) return RefusSauvegarde('REGLAGE_REFUSE', '${w.refus!.code} : ${w.refus!.motif}', w.refus!.geste);
      }
    } on EcritureRefusee catch (e) {
      return RefusSauvegarde('FILEUL_LECTURE_SEULE', e.motif, 'Régler la copie hors site sur le poste mère : ce poste reçoit ce réglage par le journal.');
    }
    magasin.journaliser('Réglage de la copie hors site', 'M14', 'reglage', 'horssite', {for (final e in courant.entries) e.key.substring(8): e.value}, {for (final e in voulu.entries) e.key.substring(8): e.value, 'motif': m.length > 40 ? m.substring(0, 40) : m});
    notifyListeners();
    return null;
  }

  // --- l'état et les gestes, par le service de la mère ----------------------------------------------------------------------------------------------

  RefusSauvegarde get _sansMere => const RefusSauvegarde('MERE_REQUISE', 'l\'état de la copie hors site se lit, et ses gestes se lancent, sur le poste mère', 'Ouvrir cet écran sur le poste mère.');

  Future<void> rafraichir() async {
    final s = source;
    if (s == null) {
      etatMere = null;
      erreurEtat = null;
      notifyListeners();
      return;
    }
    try {
      etatMere = await s.etat();
      erreurEtat = null;
    } on ErreurHorsSite catch (e) {
      etatMere = null;
      erreurEtat = e.refus;
    }
    notifyListeners();
  }

  Future<RefusSauvegarde?> _geste(Future<Object?> Function(SourceHorsSite s) f, {required String role, bool droit = true}) async {
    final s = source;
    if (s == null) return _sansMere;
    if (droit && !peutRegler(role)) return const RefusSauvegarde('REGLAGE_RESERVE', 'seuls l\'administrateur et la Directrice Administrative lancent ces gestes', 'Demander à l\'administrateur ou à la Directrice Administrative.');
    enCours = true;
    notifyListeners();
    try {
      await f(s);
      return null;
    } on ErreurHorsSite catch (e) {
      return e.refus;
    } finally {
      enCours = false;
      await rafraichir();
    }
  }

  Future<RefusSauvegarde?> copierMaintenant({required String role, required String type}) => _geste((s) => s.lancer(type), role: role);
  Future<RefusSauvegarde?> controlerMaintenant({required String role}) => _geste((s) => s.controler(), role: role);

  Future<(List<Map<String, Object?>>?, RefusSauvegarde?)> copies({required String role, required String type}) async {
    final s = source;
    if (s == null) return (null, _sansMere);
    if (!peutRegler(role)) return (null, const RefusSauvegarde('REGLAGE_RESERVE', 'seuls l\'administrateur et la Directrice Administrative voient les copies à restaurer', 'Demander à l\'administrateur ou à la Directrice Administrative.'));
    try {
      return (await s.copies(type), null);
    } on ErreurHorsSite catch (e) {
      return (null, e.refus);
    }
  }

  /// La restauration vers une cible NEUVE (jamais la base ni le dossier en service). La CONFIRMATION NOMMÉE est exigée ici, pas seulement à l'écran : il faut taper le nom du type restauré
  /// (« magasin » ou « fichiers »). Refus nommé sinon ; jamais silencieuse. Journalisée.
  Future<(Map<String, Object?>?, RefusSauvegarde?)> restaurer({required String role, required String type, required String copie, required String cible, required String confirmation}) async {
    final s = source;
    if (s == null) return (null, _sansMere);
    if (!peutRegler(role)) return (null, const RefusSauvegarde('REGLAGE_RESERVE', 'seuls l\'administrateur et la Directrice Administrative restaurent une copie hors site', 'Demander à l\'administrateur ou à la Directrice Administrative.'));
    if (confirmation.trim().toLowerCase() != type) {
      return (null, RefusSauvegarde('CONFIRMATION_REQUISE', 'la restauration n\'a pas été confirmée par son nom', 'Taper « $type » pour confirmer la restauration de cette copie.'));
    }
    if (cible.trim().isEmpty) return (null, const RefusSauvegarde('CIBLE_ABSENTE', 'aucun dossier de destination pour la restauration', 'Saisir le chemin complet d\'un dossier NEUF.'));
    enCours = true;
    notifyListeners();
    try {
      final r = await s.restaurer(type: type, copie: copie, cible: cible.trim());
      magasin.journaliser('Restauration d\'une copie hors site', 'M14', 'restauration', 'horssite', null, {'type': type, 'copie': copie.length > 12 ? copie.substring(0, 12) : copie});
      return (r, null);
    } on ErreurHorsSite catch (e) {
      return (null, e.refus);
    } finally {
      enCours = false;
      notifyListeners();
    }
  }
}
