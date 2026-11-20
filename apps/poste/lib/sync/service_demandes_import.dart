import 'dart:async';

import '../core/donnees_navigation.dart';
import '../donnees/demandes_import_poste.dart';
import '../donnees/magasin.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show demandesImportCollection;

/// LE SERVICE DE LA MÈRE QUI TRAITE LES DEMANDES D'IMPORT des fileuls (lot IMP-C, réponse Q5). Une demande arrive à la mère par le pont (famille A) comme n'importe quelle fiche ;
/// ce service l'écoute, laisse un court délai pour grouper les arrivées, puis la traite : la mère rejoue l'analyse sous le rôle de l'auteur, applique ou refuse en nommant, et écrit le
/// verdict sur la même fiche (qui revient au fileul par le pont). La matrice des droits lue est celle EN FORCE à la mère (fiches RBAC superposées à chaud).
///
/// Il ne tourne qu'à la MÈRE : un fileul ne traite rien, il dépose. Un échec d'un tour ne perd rien : la demande reste « en attente » et repart au tour suivant.
class ServiceDemandesImport {
  ServiceDemandesImport(this.magasin, {Future<DonneesNavigation> Function()? donnees, DateTime Function()? horloge, this.delai = const Duration(milliseconds: 400)})
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

  /// Un tour : traite les demandes en attente. Rend le nombre de demandes traitées.
  Future<int> traiter() async {
    if (_enCours) return 0;
    _enCours = true;
    try {
      final nav = await _donnees();
      final matrice = nav.aChaud(magasin).matrice;
      final n = DemandesImportPoste(magasin, role: 'mere', auteur: () => 'Mère', matrice: matrice, aujourdhui: _horloge, etiquette: 'M').appliquerDemandes();
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
