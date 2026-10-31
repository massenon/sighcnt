import 'package:flutter/material.dart';

import '../moteur/moteur_mobile.dart';
import 'a_traiter.dart';
import 'agenda.dart';
import 'reception.dart';
import 'tournee.dart';

/// Bandeau d'état : ce que le téléphone dit toujours de lui-même — jamais un voyant muet.
class BandeauEtat extends StatelessWidget {
  const BandeauEtat({super.key, required this.etat, this.ouvrirATraiter});
  final EtatMobile etat;

  /// Un refus à traiter se lit : toucher le bandeau ouvre l'écran « À traiter ».
  final VoidCallback? ouvrirATraiter;

  String get texte {
    if (etat.suspendu) return 'Téléphone suspendu — contactez la clinique';
    final attente = etat.enAttente > 0 ? ' · ${etat.enAttente} en attente d’envoi' : '';
    final traiter = etat.aTraiter > 0 ? ' · ${etat.aTraiter} à traiter' : '';
    final lot = etat.lotExpire != null && etat.lotExpire! > 0 && DateTime.now().millisecondsSinceEpoch >= etat.lotExpire! ? ' · lot de tournée expiré' : '';
    return '${etat.horsLigne ? 'Hors ligne' : 'Connecté'}$attente$traiter$lot';
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: etat.aTraiter > 0 ? ouvrirATraiter : null,
        child: Container(
          key: const Key('bandeau'),
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: etat.suspendu || etat.aTraiter > 0 ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(texte),
        ),
      );
}

/// L'accueil dépend du PROFIL : le soignant a sa tournée, la réception de secours son formulaire d'accueil. Aucun des deux
/// ne voit l'autre — ce que le profil ne couvre pas n'est pas proposé (et le serveur le refuserait de toute façon).
class Accueil extends StatelessWidget {
  const Accueil({super.key, required this.moteur});
  final MoteurMobile moteur;

  @override
  Widget build(BuildContext context) {
    final soignant = moteur.profil == ProfilMobile.soignant;
    final bandeau = ValueListenableBuilder<EtatMobile>(
        valueListenable: moteur.etat,
        builder: (_, e, __) => BandeauEtat(etat: e, ouvrirATraiter: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ATraiter(moteur: moteur)))));
    if (!soignant || moteur.soignant == null) {
      return Scaffold(
        appBar: AppBar(title: Text(soignant ? 'Ma tournée' : 'Réception de secours')),
        body: Column(children: [bandeau, Expanded(child: soignant ? Tournee(moteur: moteur) : Reception(moteur: moteur))]),
      );
    }
    // Soignant : l'agenda du jour d'abord (ce qu'on ouvre en arrivant), puis les dossiers du lot.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ma tournée'),
          bottom: const TabBar(tabs: [Tab(key: Key('onglet-agenda'), text: 'Agenda du jour'), Tab(key: Key('onglet-dossiers'), text: 'Dossiers du lot')]),
        ),
        body: Column(children: [
          bandeau,
          Expanded(child: TabBarView(children: [AgendaJour(moteur: moteur), Tournee(moteur: moteur)])),
        ]),
      ),
    );
  }
}
