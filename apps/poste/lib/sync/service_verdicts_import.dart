import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart' show demandesImportCollection;

import '../core/donnees_navigation.dart';
import '../donnees/demandes_import_poste.dart';
import '../donnees/magasin.dart';

/// LE SERVICE DU FILEUL QUI SUIT LE VERDICT DE LA MÈRE sur les imports écrits chez lui (lot IMP-D, décision N de la Direction, 12/11/2026).
///
/// Un fileul écrit chez lui, tout de suite, puis la mère confirme ou refuse sur la même fiche de demande (`demandesImport`, qui revient par le pont). Ce service écoute cette collection :
///  * la mère a REFUSÉ : il restitue le lot local (archivage RG-14, jamais une suppression ; les fiches qu'une pièce émise utilise restent, marquées) et le dit sur la demande ;
///  * la mère a CONFIRMÉ : il lève le marquage « en attente de la mère » des fiches que sa configuration n'a pas encore remplacées ;
///  * la mère est INJOIGNABLE : rien ne change, la demande reste « en attente » dans la file du fileul (famille A) et ses fiches restent marquées.
///
/// Il ne tourne que sur un FILEUL rattaché (la mère traite les demandes, `ServiceDemandesImport`). Un échec d'un tour ne perd rien : la suite repart au tour suivant.
class ServiceVerdictsImport {
  ServiceVerdictsImport(this.magasin,
      {required this.role, required this.auteur, Future<DonneesNavigation> Function()? donnees, DateTime Function()? horloge, this.etiquette = 'F', this.delai = const Duration(milliseconds: 400)})
      : _donnees = donnees ?? DonneesNavigation.chargerAssets,
        _horloge = horloge ?? DateTime.now;
  final Magasin magasin;
  final String role;
  final String Function() auteur;
  final String etiquette;
  final Future<DonneesNavigation> Function() _donnees;
  final DateTime Function() _horloge;
  final Duration delai;
  Timer? _minuterie;
  bool _enCours = false, _demarre = false;

  /// Nombre de suites données depuis le démarrage.
  int suivies = 0;
  Object? derniereErreur;

  void demarrer() {
    if (_demarre) return;
    _demarre = true;
    magasin.collection(demandesImportCollection).addListener(_armer);
    _armer();
  }

  void arreter() {
    _demarre = false;
    magasin.collection(demandesImportCollection).removeListener(_armer);
    _minuterie?.cancel();
  }

  void _armer() {
    _minuterie?.cancel();
    _minuterie = Timer(delai, () => unawaited(traiter()));
  }

  /// Un tour : donne la suite des verdicts reçus. Rend le nombre de demandes suivies.
  Future<int> traiter() async {
    if (_enCours) return 0;
    _enCours = true;
    try {
      final nav = await _donnees();
      final matrice = nav.aChaud(magasin).matrice;
      final n = DemandesImportPoste(magasin, role: role, auteur: auteur, matrice: matrice, aujourdhui: _horloge, etiquette: etiquette, fileulRattache: true).traiterVerdicts();
      suivies += n;
      derniereErreur = null;
      return n;
    } catch (e) {
      derniereErreur = e;
      return 0;
    } finally {
      _enCours = false;
    }
  }
}
