import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'fichiers_poste.dart';
import 'magasin.dart';

/// Où la destination est, par rapport au disque des données : ce que le poste SAIT dire (Dart n'expose pas le numéro de périphérique d'un chemin).
enum MemeDisque { sansDestination, certain, indetermine }

/// LA SAUVEGARDE DES FICHIERS NUMÉRISÉS DU POSTE (lot D5, étape 7). Les fichiers ne sont pas dans le magasin : sa sauvegarde ne les couvre pas. Ce service copie le dossier des
/// fichiers vers une DESTINATION réglée (copie incrémentale, vérifiée, jamais tournante : voir `sauvegarderFichiers` de `sigh_sync`), toutes les heures et sur commande.
///
/// La destination est PROPRE À CE POSTE (un disque externe n'a de sens que branché ici) : elle vit dans un fichier local (`sauvegarde-fichiers.json`), JAMAIS dans une collection du
/// magasin, qui voyagerait vers les autres postes avec un chemin qui n'existe pas chez eux. Le réglage est réservé à l'administrateur et à la DAF, motivé, journalisé (RG-12).
/// Une destination qui disparaît donne une EXÉCUTION EN ERREUR, dite à l'écran et au journal, jamais un « ok » silencieux ni un repli sur le disque des données.
class SauvegardeFichiersPoste extends ChangeNotifier {
  SauvegardeFichiersPoste(this.magasin, this.fichiers,
      {required this.fichierReglage, this.dossierDonnees, this.cle, this.intervalle = const Duration(hours: 1), this.borne = const Duration(seconds: 15), DateTime Function()? horloge})
      : _horloge = horloge ?? DateTime.now {
    _lire();
  }

  final Magasin magasin;
  final FichiersPoste fichiers;

  /// Le fichier local du réglage (hors magasin).
  final String fichierReglage;

  /// Le dossier des données du poste : une destination dessous est sur le MÊME disque, certainement.
  final String? dossierDonnees;
  final List<int>? cle;
  final Duration intervalle;
  final Duration borne;
  final DateTime Function() _horloge;

  static final Expando<SauvegardeFichiersPoste> _installes = Expando<SauvegardeFichiersPoste>('SauvegardeFichiersPoste');
  static SauvegardeFichiersPoste? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;

  String? _destination;
  String? _reglePar;
  String? _regleLe;
  String? _motif;
  RapportSauvegardeFichiers? dernier;
  String? derniereLe;
  RefusFichier? derniereErreur;
  bool enCours = false;
  Timer? _minuterie;

  String? get destination => _destination;
  String? get reglePar => _reglePar;
  String? get regleLe => _regleLe;
  bool peutRegler(String role) => fichierPeutRegler(role);

  void _lire() {
    try {
      final f = File(fichierReglage);
      if (!f.existsSync()) return;
      final j = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
      _destination = j['destination'] as String?;
      _reglePar = j['reglePar'] as String?;
      _regleLe = j['regleLe'] as String?;
      _motif = j['motif'] as String?;
    } catch (_) {/* un fichier de réglage illisible vaut « aucune destination » : la carte le dit */}
  }

  void _ecrire() {
    final f = File(fichierReglage);
    f.parent.createSync(recursive: true);
    final tmp = File('$fichierReglage.tmp');
    tmp.writeAsStringSync(jsonEncode({'destination': _destination, 'reglePar': _reglePar, 'regleLe': _regleLe, 'motif': _motif}), flush: true);
    tmp.renameSync(fichierReglage);
  }

  /// « Même disque » : certain si la destination est dans le dossier des données ; sinon INDÉTERMINÉ (le poste ne peut pas le savoir : l'administrateur le confirme).
  MemeDisque get memeDisque {
    final d = _destination;
    if (d == null || d.isEmpty) return MemeDisque.sansDestination;
    final dd = dossierDonnees;
    if (dd == null) return MemeDisque.indetermine;
    try {
      return cheminSousOuEgal(Directory(d).resolveSymbolicLinksSync(), Directory(dd).resolveSymbolicLinksSync()) ? MemeDisque.certain : MemeDisque.indetermine;
    } catch (_) {
      return MemeDisque.indetermine;
    }
  }

  /// Règle la destination : administrateur et DAF seuls, motif obligatoire, destination VÉRIFIÉE par le poste avant d'être enregistrée (jamais créée). Rend le refus nommé, ou `null`.
  Future<RefusFichier?> definirDestination({required String role, required String chemin, required String? motif}) async {
    if (!fichierPeutRegler(role)) {
      return const RefusFichier('REGLAGE_RESERVE', 'seuls l’administrateur et la Directrice Administrative règlent la destination de la sauvegarde des fichiers', 'Demander à l’administrateur ou à la DAF.');
    }
    final m = (motif ?? '').trim();
    if (m.isEmpty) return const RefusFichier('MOTIF_REQUIS', 'le motif du réglage est obligatoire', 'Écrire pourquoi la destination change (RG-12).');
    final refus = await verifierDestinationSauvegarde(chemin, fichiers.stockage.dossier);
    if (refus != null) return refus;
    final avant = _destination;
    _destination = chemin.trim();
    _reglePar = magasin.utilisateur;
    _regleLe = _horloge().toIso8601String();
    _motif = m;
    _ecrire();
    magasin.journaliser('Destination de la sauvegarde des fichiers numérisés', 'M14', 'reglage', 'sauvegardeFichiers', {'destination': avant}, {'destination': _destination, 'motif': m.length > 60 ? m.substring(0, 60) : m});
    notifyListeners();
    return null;
  }

  void demarrer() {
    _minuterie ??= Timer.periodic(intervalle, (_) => unawaited(lancer()));
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  /// Une passe. Sans destination réglée : rien (la carte dit « aucune sauvegarde des fichiers »). Une destination qui ne convient plus : EXÉCUTION EN ERREUR, journalisée.
  Future<void> lancer({bool manuel = false}) async {
    final d = _destination;
    if (d == null || d.isEmpty || enCours) return;
    enCours = true;
    notifyListeners();
    try {
      final r = await sauvegarderFichiers(fichiers.stockage, destination: d, cle: cle, borne: borne, horloge: _horloge);
      dernier = r;
      derniereErreur = null;
      derniereLe = _horloge().toIso8601String();
      if (!r.complet && (r.alteres.isNotEmpty || r.erreurs.isNotEmpty)) {
        magasin.journaliser('Sauvegarde des fichiers numérisés incomplète', 'M14', 'sauvegardeFichiers', 'fichiers', null,
            {'copies': r.copies, 'alteres': r.alteres.map(docAbrege).toList(), 'erreurs': r.erreurs.length});
      }
    } on ErreurFichier catch (e) {
      dernier = null;
      derniereErreur = e.refus;
      derniereLe = _horloge().toIso8601String();
      magasin.journaliser('Sauvegarde des fichiers numérisés en erreur', 'M14', 'sauvegardeFichiers', 'fichiers', null, {'code': e.refus.code, 'destination': d});
    } finally {
      enCours = false;
      notifyListeners();
    }
  }

  /// Le contrôle complet de la destination (relit tout), ou le refus nommé.
  Future<(RapportControleSauvegarde?, RefusFichier?)> controler() async {
    final d = _destination;
    if (d == null || d.isEmpty) return (null, const RefusFichier('DESTINATION_ABSENTE', 'aucune destination n’est réglée', 'Régler un dossier de destination.'));
    final refus = await verifierDestinationSauvegarde(d, fichiers.stockage.dossier);
    if (refus != null) return (null, refus);
    return (await controlerSauvegardeFichiers(fichiers.stockage, destination: d, cle: cle), null);
  }

  /// La restauration : SIMULATION par défaut. Journalisée quand elle écrit (RG-12).
  Future<(RapportRestaurationFichiers?, RefusFichier?)> restaurer({required String role, bool simulation = true}) async {
    if (!fichierPeutRegler(role)) {
      return (null, const RefusFichier('REGLAGE_RESERVE', 'seuls l’administrateur et la Directrice Administrative restaurent les fichiers', 'Demander à l’administrateur ou à la DAF.'));
    }
    final d = _destination;
    if (d == null || d.isEmpty) return (null, const RefusFichier('DESTINATION_ABSENTE', 'aucune destination n’est réglée', 'Régler le dossier où la sauvegarde a été faite.'));
    final refus = await verifierDestinationSauvegarde(d, fichiers.stockage.dossier);
    if (refus != null) return (null, refus);
    try {
      final r = await restaurerFichiers(fichiers.stockage, source: d, cle: cle, simulation: simulation, horloge: _horloge);
      if (!simulation) {
        magasin.journaliser('Restauration des fichiers numérisés', 'M14', 'sauvegardeFichiers', 'fichiers', null, {'restaures': r.restaures, 'misDeCote': r.misDeCote, 'copiesAlterees': r.copiesAlterees.length});
        fichiers.rafraichir();
      }
      return (r, null);
    } on ErreurFichier catch (e) {
      return (null, e.refus);
    }
  }
}
