import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart' show idCollectionDemandes;

import '../core/donnees_navigation.dart';
import '../donnees/demandes_identite_poste.dart';
import '../donnees/magasin.dart';

/// LE SERVICE DE LA MÈRE QUI APPLIQUE LES DEMANDES D'IDENTITÉ des fileuls habilités (lot IDENT, décision de la Direction du 16/11/2026). Même patron que `ServiceDemandesValidation` : il écoute la collection
/// `demandesIdentite`, laisse un court délai pour grouper les arrivées, puis `DemandesIdentitePoste.appliquer` refait le contrôle de droit de la fiche RBAC SOUS LE RÔLE DE L'AUTEUR, à la date de sa
/// SIGNATURE, ajoute la version datée (qui descend aux fileuls par la configuration) et pose le verdict sur la demande (qui revient au fileul par le pont).
///
/// Idempotent : seule une demande « déposée » est traitée, un rejeu ne double jamais. Il ne tourne qu'à la MÈRE. Un échec d'un tour ne perd rien : la demande reste « déposée » et repart au tour suivant.
class ServiceDemandesIdentite {
  ServiceDemandesIdentite(this.magasin, {Future<DonneesNavigation> Function()? donnees, DateTime Function()? horloge, this.delai = const Duration(milliseconds: 400)})
      : _donnees = donnees ?? DonneesNavigation.chargerAssets,
        _horloge = horloge ?? DateTime.now;
  final Magasin magasin;
  final Future<DonneesNavigation> Function() _donnees;
  final DateTime Function() _horloge;
  final Duration delai;
  Timer? _minuterie;
  bool _enCours = false, _demarre = false;

  /// Nombre de demandes traitées depuis le démarrage.
  int traitees = 0;
  Object? derniereErreur;

  void demarrer() {
    if (_demarre) return;
    _demarre = true;
    magasin.collection(idCollectionDemandes).addListener(_armer);
    _armer();
  }

  void arreter() {
    _demarre = false;
    magasin.collection(idCollectionDemandes).removeListener(_armer);
    _minuterie?.cancel();
  }

  void _armer() {
    _minuterie?.cancel();
    _minuterie = Timer(delai, () => unawaited(traiter()));
  }

  /// Un tour : applique les demandes déposées. Rend le nombre de demandes traitées.
  Future<int> traiter() async {
    if (_enCours) return 0;
    _enCours = true;
    try {
      final nav = await _donnees();
      final n = DemandesIdentitePoste(magasin, matrice: nav.aChaud(magasin).matrice, horloge: _horloge, etiquette: 'M').appliquer();
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
