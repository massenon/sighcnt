import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// `m14-taches` — « Tâches planifiées » : ce que le serveur de la maquette évalue à heure fixe (échéances, péremptions, seuils de stock, rendez-vous du
/// lendemain, créances âgées, sauvegarde) et ce qu'il a trouvé.
///
/// CET ÉCRAN NE FONCTIONNE QU'AVEC LE SERVEUR DE LA MAQUETTE. Le planificateur est `api/cron.php` (PHP / PostgreSQL) : il n'existe pas dans la cible
/// Flutter, où le poste ne planifie rien. Le poste affiche donc l'INSTANTANÉ du registre exporté du serveur (`tachesPlanifiees`, `executionsTaches`,
/// engendrés par `prototype_html/build/gen-jeu-planificateur.js`) : une tâche « en retard » l'est vraiment, personne ne la relance. « Exécuter » est
/// REFUSÉE en le disant, comme le fait la maquette quand le serveur refuse. Le contrôle de retard est celui de la maquette (plus de trois périodes).
class EcranTaches extends StatelessWidget with EcranMaquette {
  const EcranTaches({super.key});

  @override
  String get description =>
      'Ce que le serveur évalue à heure fixe — échéances, péremptions, seuils de stock, rendez-vous du lendemain, créances âgées, sauvegarde — et ce qu’il a trouvé.';

  @override
  String get regle =>
      'Le planificateur (api/cron.php) tourne sans écran ouvert. Il lit les registres, n’en écrit aucun, et applique les seuils que la clinique a fixés. Une alerte disparaît quand sa cause cesse ; elle n’est jamais supprimée (RG-14). Installer la tâche du système toutes les 5 minutes ; à défaut, le serveur se déclenche lui-même quand un poste est ouvert.';

  void _executer(BuildContext ctx, Fiche t) {
    ToastsSigh.afficher(ctx, 'Exécution refusée : ce poste n’a pas de planificateur.',
        type: TypeToast.erreur,
        detail:
            '« ${t['libelle']} » s’exécute dans le serveur de la maquette (api/cron.php) ; la cible Flutter ne planifie rien.');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final taches = c.magasin.collection('tachesPlanifiees').actives;
    final executions = c.magasin.collection('executionsTaches').actives;
    final b = secBilanTaches(taches, c.aujourdhui);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Tâches actives',
            valeur: nombre(b.actives),
            icone: LucideIcons.timer,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'En erreur',
            valeur: nombre(b.erreurs),
            icone: LucideIcons.triangleAlert,
            ton: b.erreurs > 0 ? TonSigh.danger : TonSigh.succes),
        KpiSigh(
            libelle: 'En retard sur leur fréquence',
            valeur: nombre(b.enRetard),
            icone: LucideIcons.clockAlert,
            ton: b.enRetard > 0 ? TonSigh.attention : TonSigh.succes,
            indice: 'Plus de trois périodes sans exécution'),
        KpiSigh(
            libelle: 'Alertes ouvertes (dernière passe)',
            valeur: nombre(b.alertes),
            icone: LucideIcons.bellRing,
            ton: TonSigh.neutre),
      ]),
      if (b.enRetard > 0) ...[
        const SizedBox(height: 16),
        NoteSigh(
            '${b.enRetard} tâche(s) n’ont pas tourné à leur fréquence. Vérifier que la tâche du système (cron Linux ou Planificateur de tâches Windows) est installée et active.',
            ton: TonSigh.attention,
            icone: LucideIcons.clockAlert),
      ],
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Registre des tâches',
          sansRemplissage: true,
          child: MiniTableauSigh(colonnes: [
            ColonneMini('Tâche', (t) => '${t['libelle']}'),
            ColonneMini('Fréquence', (t) => 'toutes les ${t['frequence_min']} min'),
            ColonneMini('Dernière exécution', (t) => secDerniereExecution(t['derniere_le'])),
            ColonneMini('Résultat', secResultatTache),
            ColonneMini('Durée', (t) => secDureeTache(t['duree_ms'])),
            ColonneMini('Alertes', (t) => nombre((t['alertes'] as num?) ?? 0)),
            ColonneMini('', (t) => '',
                rendu: (t) => c.droit.editer
                    ? BoutonSigh(
                        libelle: 'Exécuter',
                        taille: TailleBouton.sm,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => _executer(context, t))
                    : const SizedBox.shrink()),
          ], lignes: taches)),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Dernières exécutions',
          sansRemplissage: executions.isNotEmpty,
          child: executions.isEmpty
              ? const VideSigh('Aucune exécution enregistrée.', icone: LucideIcons.timer)
              : MiniTableauSigh(colonnes: [
                  ColonneMini('Début (UTC)', (e) => secDebutExecution(e['debut'])),
                  ColonneMini('Tâche', (e) => '${e['code']}'),
                  ColonneMini('Résultat', (e) => e['statut'] == 'ok' ? 'Réussie' : 'Erreur'),
                  ColonneMini('Déclenchée par', (e) => '${e['origine'] ?? '—'}'),
                  ColonneMini('Durée', (e) => '${e['duree_ms']} ms'),
                  ColonneMini('Alertes', (e) => nombre(e['alertes'])),
                ], lignes: executions)),
      const SizedBox(height: 16),
      const NoteSigh(
          'Limite du poste : ce registre est un instantané du planificateur du serveur de la maquette. Le poste n’exécute aucune de ces tâches : sans le serveur, elles ne tournent pas, et « Exécuter » est refusée.',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}
