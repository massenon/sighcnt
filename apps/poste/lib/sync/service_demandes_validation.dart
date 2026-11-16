import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart' show valCollectionDemandes;

import '../core/donnees_navigation.dart';
import '../donnees/demandes_validation_poste.dart';
import '../donnees/magasin.dart';

/// LE SERVICE DE LA MÈRE QUI APPLIQUE MÉCANIQUEMENT LES DÉCISIONS DE VALIDATION des fileuls (lot CONT, exigence de la Direction du 14/11/2026). Le poste de la mère n'est pas fait pour valider :
/// il est le serveur local, personne n'y travaille. La décision humaine (Valider) est prise, SIGNÉE et déposée par le profil de la famille depuis SON poste ; la mère n'est que l'applicateur.
/// Même patron que `ServicePropositionsTarif` et `ServiceDemandesImport` : ce service écoute la collection `demandesValidation`, laisse un court délai pour grouper les arrivées, puis
/// `DemandesValidationPoste.appliquer` refait les MÊMES contrôles sous le rôle et le nom de l'auteur, écrit le marquage (qui descend aux fileuls par la configuration) et pose le verdict sur
/// la demande (qui revient au fileul par le pont).
///
/// Idempotent : seule une demande « déposée » est traitée, un rejeu ne double jamais. Il ne tourne qu'à la MÈRE. Un échec d'un tour ne perd rien : la demande reste « déposée » et repart au
/// tour suivant ; mère coupée, tout s'empile au journal du fileul et se rejoue à la reconnexion.
class ServiceDemandesValidation {
  ServiceDemandesValidation(this.magasin, {Future<DonneesNavigation> Function()? donnees, DateTime Function()? horloge, this.delai = const Duration(milliseconds: 400)})
      : _donnees = donnees ?? DonneesNavigation.chargerAssets,
        _horloge = horloge ?? DateTime.now;
  final Magasin magasin;
  final Future<DonneesNavigation> Function() _donnees;
  final DateTime Function() _horloge;
  final Duration delai;
  Timer? _minuterie;
  bool _enCours = false, _demarre = false;

  /// Nombre de décisions traitées depuis le démarrage.
  int traitees = 0;
  Object? derniereErreur;

  void demarrer() {
    if (_demarre) return;
    _demarre = true;
    magasin.collection(valCollectionDemandes).addListener(_armer);
    _armer();
  }

  void arreter() {
    _demarre = false;
    magasin.collection(valCollectionDemandes).removeListener(_armer);
    _minuterie?.cancel();
  }

  void _armer() {
    _minuterie?.cancel();
    _minuterie = Timer(delai, () => unawaited(traiter()));
  }

  /// Un tour : applique les décisions déposées. Rend le nombre de décisions traitées.
  Future<int> traiter() async {
    if (_enCours) return 0;
    _enCours = true;
    try {
      final nav = await _donnees();
      final matrice = nav.aChaud(magasin).matrice;
      final n = DemandesValidationPoste(magasin, libelles: DemandesValidationPoste.libellesDesRoles(matrice), horloge: _horloge, etiquette: 'M', matrice: matrice).appliquer();
      traitees += n;
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
