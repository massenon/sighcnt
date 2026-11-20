import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/theme.dart';
import '../moteur/moteur_mobile.dart';
import 'commun.dart';

/// La version de l'application, telle que le build la porte (la page du simulateur affiche une version de démonstration).
const versionApplication = String.fromEnvironment('SIGH_VERSION', defaultValue: '0.1.0+1');

/// Réglages : le profil et l'agent de ce téléphone, les trois garanties (verrouillage, effacement à distance, notifications) et la réinitialisation de
/// l'appairage. Ce que la page affiche comme « Activé » ne l'est que si c'est vrai : le verrouillage dépend du coffre du code PIN, les notifications ne
/// sont pas branchées (E1571), et l'écran le dit au lieu d'afficher « Activées ».
class EcranReglages extends StatelessWidget {
  const EcranReglages({super.key, required this.moteur, required this.profil, required this.agent, required this.verrouillageActif, this.apresReinitialisation});
  final MoteurMobile moteur;
  final String profil, agent;
  final bool verrouillageActif;
  final VoidCallback? apresReinitialisation;

  Future<void> _reinitialiser(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(mobReglagesConfirmation, key: const Key('reglages-confirmation')),
        actions: [
          TextButton(key: const Key('reinit-annuler'), onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
          TextButton(key: const Key('reinit-ok'), onPressed: () => Navigator.of(c).pop(true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messager = ScaffoldMessenger.of(context);
    try {
      mobControlerReinitialisation(moteur.etat.value.enAttente);
    } on RefusMobile catch (r) {
      messager.showSnackBar(SnackBar(content: Text('${r.motif} À faire : ${r.geste}.'), duration: const Duration(seconds: 8)));
      return;
    }
    if (moteur is ExtensionsMobile) await (moteur as ExtensionsMobile).reinitialiserAppairage();
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    apresReinitialisation?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ext = moteur is ExtensionsMobile ? moteur as ExtensionsMobile : null;
    return Scaffold(
      appBar: AppBar(title: Text(mobLibelleEcran('parametres'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        FutureBuilder<String?>(
          future: ext?.appareil() ?? Future.value(null),
          builder: (context, snap) {
            final t = mobReglagesTelephone(profil: profil, agent: agent, appareil: snap.data, version: versionApplication);
            return CarteTitre(titre: mobReglagesCarte, enfants: [
              const Text('Profil', style: TextStyle(fontSize: 12)),
              Text(t.profil, key: const Key('reglages-profil'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Agent', style: TextStyle(fontSize: 12)),
              Text(t.agent, key: const Key('reglages-agent'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(t.appareil, key: const Key('reglages-appareil')),
            ]);
          },
        ),
        Card(
          child: Column(children: [
            for (final l in mobReglagesLignes)
              ListTile(
                key: Key('reglage-${l.titre}'),
                title: Text(l.titre),
                subtitle: Text(l.detail),
                trailing: Text(_fin(l), style: TextStyle(fontWeight: FontWeight.w700, color: _fin(l) == l.fin ? ThemeSigh.succes : ThemeSigh.attention)),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('reinitialiser-appairage'),
          icon: const Icon(Icons.link_off),
          style: OutlinedButton.styleFrom(foregroundColor: ThemeSigh.danger),
          label: Text(mobReglagesBouton),
          onPressed: () => _reinitialiser(context),
        ),
      ]),
    );
  }

  /// Ce qui est VRAI de chaque garantie, à la place du badge de la page quand il mentirait.
  String _fin(MobLigneReglage l) => switch (l.titre) {
        'Verrouillage automatique' => verrouillageActif ? l.fin : 'Désactivé',
        'Notifications' => 'Non branchées',
        _ => l.fin,
      };
}
