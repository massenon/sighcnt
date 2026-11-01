import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show mobEcranOuvertAuProfil, mobLibelleEcran, mobProfilDe;

import '../moteur/moteur_mobile.dart';
import 'a_traiter.dart';
import 'agenda.dart';
import 'lot.dart';
import 'reglages.dart';
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
  const Accueil({super.key, required this.moteur, this.coffreActif = false, this.apresReinitialisation});
  final MoteurMobile moteur;

  /// Vrai quand le code PIN garde l'application (l'écran des réglages ne dit « Activé » que si c'est vrai).
  final bool coffreActif;
  final VoidCallback? apresReinitialisation;

  /// Le profil du simulateur de ce téléphone (`soignant`, `medecin`, `sagefemme`, `reception`).
  String get _profil => mobProfilDe(reception: moteur.profil != ProfilMobile.soignant, fonction: moteur.soignant?.session.fonction ?? '');
  String get _agent => moteur.soignant?.session.agent ?? (moteur is ExtensionsMobile ? (moteur as ExtensionsMobile).agent : '');

  /// Réglages pour tous les profils ; lot de tournée pour ceux dont le simulateur l'ouvre (la commande est ABSENTE de la réception de secours).
  List<Widget> _actions(BuildContext context) => [
        if (moteur.soignant != null && mobEcranOuvertAuProfil(_profil, 'lot'))
          IconButton(
            key: const Key('ouvrir-lot'),
            tooltip: mobLibelleEcran('lot'),
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranLot(moteur: moteur, service: ServiceSuite.depuisSoignant(moteur.soignant!)))),
          ),
        IconButton(
          key: const Key('ouvrir-reglages'),
          tooltip: mobLibelleEcran('parametres'),
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => EcranReglages(moteur: moteur, profil: _profil, agent: _agent, verrouillageActif: coffreActif, apresReinitialisation: apresReinitialisation))),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final soignant = moteur.profil == ProfilMobile.soignant;
    final bandeau = ValueListenableBuilder<EtatMobile>(
        valueListenable: moteur.etat,
        builder: (_, e, __) => BandeauEtat(etat: e, ouvrirATraiter: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ATraiter(moteur: moteur)))));
    if (!soignant || moteur.soignant == null) {
      return Scaffold(
        appBar: AppBar(title: Text(soignant ? 'Ma tournée' : 'Réception de secours'), actions: _actions(context)),
        body: Column(children: [bandeau, Expanded(child: soignant ? Tournee(moteur: moteur) : Reception(moteur: moteur))]),
      );
    }
    // Soignant : l'agenda du jour d'abord (ce qu'on ouvre en arrivant), puis les dossiers du lot.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ma tournée'),
          actions: _actions(context),
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
