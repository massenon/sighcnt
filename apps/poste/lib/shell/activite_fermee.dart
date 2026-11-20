import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import 'page_standard.dart';

/// Un écran dont l'ACTIVITÉ est fermée (`cfg-modules`, collection `modulesActifs`) ouvert par son adresse : la coque le DIT au lieu de renvoyer à
/// l'accueil. La maquette renvoie la page 403 ; ici le refus est nommé et porte le motif de la fiche de fermeture (`fermeturePour`). L'activité
/// est fermée pour tous les rôles, administrateur compris : ce n'est pas une habilitation. Rien n'est supprimé, la réouverture rend l'écran en l'état.
class PageActiviteFermee extends StatelessWidget {
  const PageActiviteFermee({super.key, required this.ecran, required this.fermeture, required this.fil});
  final EcranNav ecran;

  /// La fiche de la collection `modulesActifs` qui ferme l'écran.
  final Map<String, Object?> fermeture;
  final List<String> fil;

  String get _motif {
    final m = fermeture['motif'];
    return (m != null && '$m'.trim().isNotEmpty) ? '$m' : 'Aucun motif n’a été consigné.';
  }

  String get _depuis {
    final le = fermeture['fermeLe'];
    final par = fermeture['fermePar'];
    final d = le == null ? null : DateTime.tryParse('$le');
    final date = d != null ? 'le ${dateFR(d)}' : '';
    final qui = (par != null && '$par'.isNotEmpty) ? 'par $par' : '';
    final t = [date, qui].where((x) => x.isNotEmpty).join(' ');
    return t.isEmpty ? '' : 'Fermée $t. ';
  }

  @override
  Widget build(BuildContext context) {
    return PageStandard(
      titre: 'Activité fermée',
      fil: fil,
      module: ecran.module,
      child: Container(
        key: const Key('activite-fermee'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: JetonsShell.slate200),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(LucideIcons.toggleLeft, size: 22, color: JetonsShell.slate400),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('L’écran « ${ecran.label} » n’est pas ouvert : ${fermeture['libelle'] ?? ecran.moduleLabel} est une activité fermée.',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: JetonsShell.slate900)),
              const SizedBox(height: 6),
              Text('Motif : $_motif', style: const TextStyle(color: JetonsShell.slate500, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                  '$_depuis'
                  'La fermeture vaut pour tous les rôles, administrateur compris. Aucune donnée n’est supprimée : rouvrir l’activité (Configuration, Activité des modules) rend l’écran en l’état.',
                  style: const TextStyle(color: JetonsShell.slate500, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }
}
