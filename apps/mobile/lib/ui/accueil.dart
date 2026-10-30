import 'package:flutter/material.dart';

import '../moteur/moteur_mobile.dart';
import 'reception.dart';
import 'tournee.dart';

/// Bandeau d'état : ce que le téléphone dit toujours de lui-même — jamais un voyant muet.
class BandeauEtat extends StatelessWidget {
  const BandeauEtat({super.key, required this.etat});
  final EtatMobile etat;

  String get texte {
    if (etat.suspendu) return 'Téléphone suspendu — contactez la clinique';
    final attente = etat.enAttente > 0 ? ' · ${etat.enAttente} en attente d’envoi' : '';
    final traiter = etat.aTraiter > 0 ? ' · ${etat.aTraiter} à traiter' : '';
    return '${etat.horsLigne ? 'Hors ligne' : 'Connecté'}$attente$traiter';
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('bandeau'),
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        color: etat.suspendu || etat.aTraiter > 0 ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(texte),
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
    return Scaffold(
      appBar: AppBar(title: Text(soignant ? 'Ma tournée' : 'Réception de secours')),
      body: Column(children: [
        ValueListenableBuilder<EtatMobile>(valueListenable: moteur.etat, builder: (_, e, __) => BandeauEtat(etat: e)),
        Expanded(child: soignant ? Tournee(moteur: moteur) : Reception(moteur: moteur)),
      ]),
    );
  }
}
