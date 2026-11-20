import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart' show ErreurFichier, EtatLocalFichier, StockageFichiers;

import '../donnees/fichiers_poste.dart';
import '../donnees/magasin.dart';

/// LA SYNCHRONISATION DES FICHIERS NUMÉRISÉS D'UN FILEUL (lot D5, EF-SYNC-18). Les MÉTADONNÉES (la fiche qui porte `fichier`, le registre `fichiers`) voyagent par le journal comme
/// toute fiche (pont d'activité) ; ce service fait voyager le BINAIRE, À PART, par son empreinte SHA-256 :
///
///  - l'ENVOI : ce que ce poste a déposé et que la mère n'a pas encore (file locale `transfertsFichiers`) part par morceaux de 256 Kio, chacun avec son empreinte, la mère recomposant
///    et vérifiant l'ensemble ; un transfert coupé REPREND au dernier morceau vérifié ; un morceau altéré est refusé par la mère et RENVOYÉ ;
///  - la RÉCEPTION : une fiche arrivée avant son binaire dit « fichier en cours de transfert » (mère joignable) ou « non disponible hors ligne », jamais un écran vide ; le poste vient
///    CHERCHER le binaire à la mère (la mère ne contacte jamais un poste), l'empreinte de l'ensemble est vérifiée avant de ranger ;
///  - les DROITS : un poste dont le rôle courant ne lit pas la zone du document ne demande pas son binaire, et la mère le lui refuserait (RG-13) ;
///  - JAMAIS un téléphone : ce service n'existe qu'au poste ; la mère refuse tout appareil mobile ;
///  - sans mère, rien ne part et rien n'échoue : les fichiers restent locaux.
///
/// Aucun octet de fichier ne passe par le relais en ligne : les métadonnées y arrivent chiffrées avec le journal, le binaire ne quitte jamais le réseau de la clinique (mère et fileuls).
class ReponseFichiers {
  const ReponseFichiers(this.statut, this.corps, this.entetes);
  final int statut;
  final Uint8List corps;
  final Map<String, String> entetes;

  Map<String, Object?> get json {
    try {
      return (jsonDecode(utf8.decode(corps)) as Map).cast<String, Object?>();
    } catch (_) {
      return const {};
    }
  }

  String? get code => json['code'] as String?;
}

typedef AppelFichiers = Future<ReponseFichiers> Function(String methode, String chemin, {List<int>? corps, Map<String, String> entetes, String typeContenu});

class ServiceFichiers extends ChangeNotifier implements EtatTransfertFichiers {
  ServiceFichiers(
      {required this.magasin,
      required this.fichiers,
      required this.appel,
      required this.roleCourant,
      required this.droitDe,
      this.tailleMorceau = fichierTailleMorceau,
      this.intervalle = const Duration(seconds: 3),
      this.essaisMorceau = 3}) {
    fichiers.transfert = this;
  }

  final Magasin magasin;
  final FichiersPoste fichiers;
  final AppelFichiers appel;

  /// Le rôle de l'agent connecté, ou `null` (aucune session) : sans lui, ce poste ne demande aucun binaire.
  final String? Function() roleCourant;

  /// Le droit d'un rôle sur un écran (la matrice RBAC, corrections à chaud comprises).
  final Droit Function(String role, String ecran) droitDe;
  final int tailleMorceau;
  final Duration intervalle;
  final int essaisMorceau;

  StockageFichiers get stockage => fichiers.stockage;
  Timer? _minuterie;
  bool _enCours = false;
  bool _joignable = false;
  final Set<String> _manquants = {};
  final Set<String> _refuses = {};

  /// La dernière erreur du cycle (`null` : tout va bien).
  final ValueNotifier<String?> erreur = ValueNotifier<String?>(null);

  /// Compteurs observables (tests et pastille) : morceaux envoyés, morceaux reçus, requêtes de morceaux évitées par la reprise.
  int morceauxEnvoyes = 0;
  int morceauxRecus = 0;
  int morceauxRenvoyes = 0;

  void demarrer() {
    _minuterie ??= Timer.periodic(intervalle, (_) => unawaited(cycle()));
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  @override
  bool get mereJoignable => _joignable;

  @override
  bool enCours(String sha) => _manquants.contains(sha) || _file().any((f) => f['sha256'] == sha && f['etat'] == 'attente');

  /// Les empreintes que ce poste attend et dont la mère n'a pas (encore) donné le binaire, ou qu'elle lui a REFUSÉES.
  Set<String> get enAttente => {..._manquants};
  Set<String> get refuses => {..._refuses};

  CollectionMagasin _col() => magasin.collection(fichiersFileEnvoi);
  List<Fiche> _file() => _col().toutes;

  // --- un cycle --------------------------------------------------------------------------------------------------------------------------------

  /// Un cycle : l'inventaire de ce qui reste à envoyer, l'envoi, puis la réception de ce qui manque. Jamais d'exception : un cycle qui échoue le dit et recommence.
  Future<void> cycle() async {
    if (_enCours) return;
    _enCours = true;
    try {
      await _inventaire();
      await _envoyer();
      await _recevoir();
      erreur.value = null;
    } on _MereInjoignable catch (e) {
      _joignable = false;
      erreur.value = 'Mère injoignable : ${e.cause}';
    } catch (e) {
      erreur.value = 'Synchronisation des fichiers impossible : $e';
    } finally {
      _enCours = false;
      notifyListeners();
    }
  }

  /// Les fiches qui portent un fichier présent sur ce poste et qu'AUCUNE ligne de la file ne couvre (déposées avant que le poste rejoigne une mère) : elles rejoignent la file,
  /// sous le rôle courant.
  Future<void> _inventaire() async {
    final role = roleCourant();
    for (final famille in fichierFamilles) {
      for (final f in magasin.collection(fichiersCollectionDe(famille)).actives) {
        final x = fichierDe(f);
        if (x == null) continue;
        final sha = '${x['sha256']}';
        final type = famille == 'patient' ? '${f['type']}' : null;
        final zone = famille == 'patient' ? docZoneDe(type) : 0;
        final id = 'ENV-${sha.substring(0, 16)}-$famille-$zone';
        if (_col().parId(id) != null) continue;
        if (role == null || !await stockage.existe(sha)) continue;
        _col().inserer({'id': id, 'sha256': sha, 'sens': 'envoi', 'famille': famille, 'type': type, 'zone': zone, 'role': role, 'etat': 'attente', 'essais': 0}, prefixe: 'ENV');
      }
    }
  }

  // --- appels ------------------------------------------------------------------------------------------------------------------------------------

  Future<ReponseFichiers> _appeler(String methode, String chemin, {List<int>? corps, required String role, String typeContenu = 'application/octet-stream'}) async {
    try {
      final r = await appel(methode, chemin, corps: corps, entetes: {'x-sigh-role': role}, typeContenu: typeContenu);
      _joignable = true;
      return r;
    } catch (e) {
      throw _MereInjoignable(e);
    }
  }

  Future<ReponseFichiers> _json(String methode, String chemin, Map<String, Object?> corps, String role) =>
      _appeler(methode, chemin, corps: utf8.encode(jsonEncode(corps)), role: role, typeContenu: 'application/json');

  // --- ENVOI ---------------------------------------------------------------------------------------------------------------------------------------

  Future<void> _envoyer() async {
    for (final f in _file().where((x) => x['etat'] == 'attente').toList()) {
      final sha = '${f['sha256']}';
      final role = '${f['role'] ?? ''}';
      if (role.isEmpty) continue;
      try {
        final fin = await _envoyerUn(f, sha, role);
        if (fin) _col().mettreAJour(f['id'], {'etat': 'confirme', 'majLe': magasin.horloge().toIso8601String()}, journaliser: false);
      } on ErreurFichier catch (e) {
        // Le fichier local est absent ou altéré : rien à envoyer tant qu'il ne l'est pas ; la file garde la ligne et le dit.
        _col().mettreAJour(f['id'], {'code': e.refus.code, 'motif': e.refus.motif, 'essais': ((f['essais'] as num?) ?? 0) + 1}, journaliser: false);
      }
    }
  }

  /// Envoie UN fichier : ouvre le dépôt, envoie les morceaux que la mère n'a pas (reprise), termine. `true` : la mère a le fichier. Une REFUS nommé de la mère (droit, zone,
  /// format, taille) est écrit sur la ligne (état `refus`) : il ne se rejoue pas à l'aveugle.
  Future<bool> _envoyerUn(Fiche ligne, String sha, String role) async {
    final octets = await stockage.lire(sha);
    final desc = DescriptionFichier.deOctets(octets, tailleMorceau);
    var ouv = await _json('POST', '/fichiers/ouvrir', {'famille': ligne['famille'], 'type': ligne['type'], 'description': desc.toJson()}, role);
    if (ouv.statut == 503) return false;
    if (ouv.statut != 200) return _refus(ligne, ouv);
    if (ouv.json['complet'] == true) return true;
    var recus = {for (final i in (ouv.json['recus'] as List? ?? const [])) (i as num).toInt()};
    for (var i = 0; i < desc.plan.nombre; i++) {
      if (recus.contains(i)) continue;
      final part = Uint8List.sublistView(octets, desc.plan.debut(i), desc.plan.fin(i));
      var ok = false;
      for (var essai = 0; essai < essaisMorceau && !ok; essai++) {
        final r = await _appeler('PUT', '/fichiers/morceau?sha256=$sha&i=$i', corps: part, role: role);
        if (r.statut == 200) {
          ok = true;
          morceauxEnvoyes++;
        } else if (r.code == 'MORCEAU_ALTERE') {
          morceauxRenvoyes++; // la mère a refusé un morceau altéré en route : on le RENVOIE
        } else if (r.code == 'TRANSFERT_NON_OUVERT') {
          // La mère a redémarré : on rouvre, elle rend ce qu'elle a gardé sur disque, on reprend de là.
          ouv = await _json('POST', '/fichiers/ouvrir', {'famille': ligne['famille'], 'type': ligne['type'], 'description': desc.toJson()}, role);
          if (ouv.statut != 200) return _refus(ligne, ouv);
          if (ouv.json['complet'] == true) return true;
          recus = {for (final k in (ouv.json['recus'] as List? ?? const [])) (k as num).toInt()};
          if (recus.contains(i)) ok = true;
        } else {
          return _refus(ligne, r);
        }
      }
      if (!ok) throw _MereInjoignable('le morceau $i n’a pas pu être envoyé');
    }
    final fin = await _json('POST', '/fichiers/terminer', {'sha256': sha}, role);
    if (fin.statut == 200) return true;
    return _refus(ligne, fin);
  }

  bool _refus(Fiche ligne, ReponseFichiers r) {
    final j = r.json;
    _col().mettreAJour(ligne['id'], {'etat': 'refus', 'code': j['code'], 'motif': j['motif'], 'geste': j['geste'], 'majLe': magasin.horloge().toIso8601String()}, journaliser: false);
    _refuses.add('${ligne['sha256']}');
    return false;
  }

  // --- RÉCEPTION -----------------------------------------------------------------------------------------------------------------------------

  Future<void> _recevoir() async {
    final role = roleCourant();
    _manquants.clear();
    if (role == null) return;
    final vus = <String>{};
    for (final famille in fichierFamilles) {
      final ecran = fichierEcranDeFamille(famille);
      for (final f in magasin.collection(fichiersCollectionDe(famille)).actives) {
        final x = fichierDe(f);
        if (x == null) continue;
        final sha = '${x['sha256']}';
        final type = famille == 'patient' ? '${f['type']}' : null;
        if (fichierRefusDroit(role: role, famille: famille, geste: 'voir', type: type, droitEcran: droitDe(role, ecran)) != null) continue;
        final etat = await stockage.etat(sha);
        if (etat == EtatLocalFichier.present) continue;
        if (!vus.add('$famille/$sha')) continue;
        _manquants.add(sha);
        if (_refuses.contains(sha)) continue;
        if (await _recevoirUn(famille, type, sha, role)) _manquants.remove(sha);
      }
    }
  }

  /// Vient CHERCHER un fichier à la mère. `false` : la mère ne l'a pas encore (le déposant ne l'a pas envoyé), ou un refus nommé (droit, zone), ou la mère est coupée : le poste
  /// reprendra au cycle suivant, à partir des morceaux déjà vérifiés.
  Future<bool> _recevoirUn(String famille, String? type, String sha, String role) async {
    final info = await _appeler('GET', '/fichiers/info?sha256=$sha&famille=$famille&morceau=$tailleMorceau', role: role);
    if (info.statut == 404) return false; // pas encore arrivé à la mère
    if (info.statut != 200) {
      if (info.statut == 403) _refuses.add(sha);
      return false;
    }
    final desc = DescriptionFichier.depuisJson(((info.json['description'] ?? {}) as Map).cast<String, Object?>());
    if (desc.sha256 != sha) return false; // une mère qui répondrait pour une autre empreinte n'est pas crue
    final reception = await stockage.ouvrirReception(desc);
    for (final i in reception.manquants) {
      var ok = false;
      for (var essai = 0; essai < essaisMorceau && !ok; essai++) {
        final r = await _appeler('GET', '/fichiers/morceau?sha256=$sha&i=$i&famille=$famille&morceau=$tailleMorceau', role: role);
        if (r.statut != 200) {
          if (r.statut == 403) _refuses.add(sha);
          return false;
        }
        final refus = await stockage.deposerMorceau(reception, i, r.corps);
        if (refus == null) {
          ok = true;
          morceauxRecus++;
        } else {
          morceauxRenvoyes++; // morceau altéré en route : refusé, redemandé
        }
      }
      if (!ok) return false;
    }
    try {
      await stockage.assembler(reception, famille: famille, zone: famille == 'patient' ? docZoneDe(type) : 0, deposePar: 'mère');
    } on ErreurFichier {
      return false; // empreinte de l'ensemble différente : les morceaux sont jetés, le poste redemandera
    }
    return true;
  }
}

class _MereInjoignable implements Exception {
  _MereInjoignable(this.cause);
  final Object cause;
  @override
  String toString() => 'mère injoignable : $cause';
}
