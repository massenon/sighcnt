import 'dart:async';

import '../core/donnees_navigation.dart';
import '../donnees/demandes_import_poste.dart';
import '../donnees/magasin.dart';
import '../donnees/tarifs_poste.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show tarCollectionDemandes;

/// LE SERVICE DE LA MÈRE QUI APPLIQUE LES DEMANDES DE PRIX des fileuls (lot TFIN, étape 0). Une proposition, une décision (Oui ou Non) ou un retrait déposé par un fileul depuis
/// « Tarifs et prix » arrive à la mère par le pont (collection `propositionsTarif`, famille B). Avant ce lot, `TarifsPoste.appliquerDemandes` n'était appelé par aucun service de
/// l'application livrée : la demande restait « déposée » pour toujours. Même patron que `ServiceDemandesImport` : ce service écoute la collection, laisse un court délai pour grouper
/// les arrivées, puis la mère refait les MÊMES contrôles sous le rôle et le nom de l'auteur, écrit la version (ou le refus nommé : code, motif, geste) et le verdict revient au
/// fileul par la même fiche.
///
/// Idempotent : une demande déjà « appliquée » ou « refusée » n'est jamais retraitée (rejeu sans effet). Il ne tourne qu'à la MÈRE. Un échec d'un tour ne perd rien : la demande
/// reste « déposée » et repart au tour suivant. Jamais vers un téléphone (la collection est exclue du mobile par le relais).
class ServicePropositionsTarif {
  ServicePropositionsTarif(this.magasin, {Future<DonneesNavigation> Function()? donnees, DateTime Function()? horloge, this.delai = const Duration(milliseconds: 400)})
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
    magasin.collection(tarCollectionDemandes).addListener(_armer);
    // LOT TFIN-2 : une fiche produit qui ARRIVE (créée chez un fileul, importée par le référentiel produits d'un fileul) reçoit sa version 1 de reprise à la mère, jamais chez le fileul (famille R).
    magasin.collection('produits').addListener(_armer);
    _armer();
  }

  void arreter() {
    _demarre = false;
    magasin.collection(tarCollectionDemandes).removeListener(_armer);
    magasin.collection('produits').removeListener(_armer);
    _minuterie?.cancel();
  }

  void _armer() {
    _minuterie?.cancel();
    _minuterie = Timer(delai, () => unawaited(traiter()));
  }

  /// Un tour : applique les demandes de prix en attente. Rend le nombre de demandes traitées.
  Future<int> traiter() async {
    if (_enCours) return 0;
    _enCours = true;
    try {
      TarifsPoste.assurerProduits(magasin);
      final nav = await _donnees();
      final matrice = nav.aChaud(magasin).matrice;
      final tarifs = TarifsPoste(magasin,
          role: 'mere',
          auteur: () => 'Mère',
          fileul: false,
          libelles: DemandesImportPoste.libellesDesRoles(matrice),
          peutEditerEcran: true,
          peutEditerPour: (r) => matrice.peutEditer(r, 'cfg-tarifs'),
          peutProposerPrixAchatPour: (r) => matrice.peutEditer(r, 'm6-produits'),
          // La proposition née d'une réception a l'autorité de MODIFIER les réceptions (lot TFIN-2), non celle de modifier « Référentiel produits ».
          peutProposerReceptionPour: (r) => matrice.peutEditer(r, 'm7-receptions'),
          horloge: _horloge,
          etiquette: 'M');
      final n = tarifs.appliquerDemandes();
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
