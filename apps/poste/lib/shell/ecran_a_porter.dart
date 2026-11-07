import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/donnees_navigation.dart';
import '../core/jetons_shell.dart';
import 'page_standard.dart';

/// L'ÉTAT « écran indisponible sur ce poste » (Direction, 01/11/2026 : plus aucun gabarit de chantier). Tous les écrans du manifeste sont portés ; cet état
/// n'est que le filet d'un identifiant qui n'aurait pas de widget dans la configuration du poste. Il NOMME où l'écran vit (domaine, module, tranche) et ce
/// qu'il faut faire, jamais une page vide ni un chantier. Le test `ecrans_sans_chantier_test.dart` interdit qu'un rôle autorisé y parvienne.
class EcranAPorter extends StatelessWidget {
  const EcranAPorter(
      {super.key,
      required this.ecran,
      required this.donnees,
      required this.fil});
  final EcranNav ecran;
  final DonneesNavigation donnees;
  final List<String> fil;

  @override
  Widget build(BuildContext context) {
    final t = donnees.tranche(ecran.id);
    return PageStandard(
      titre: ecran.label,
      fil: fil,
      module: ecran.module,
      description: ecran.hub
          ? 'Page d’accueil du module « ${ecran.moduleLabel} ».'
          : null,
      child: Container(
        key: const Key('ecran-a-porter'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: JetonsShell.slate200),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(LucideIcons.circleOff,
              size: 22, color: JetonsShell.slate400),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cet écran n’est pas disponible sur ce poste',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: JetonsShell.slate900)),
              const SizedBox(height: 6),
              Text(
                  'Identifiant : ${ecran.id} · module ${ecran.module}${t != null ? ' · tranche $t' : ''}.',
                  style: const TextStyle(
                      color: JetonsShell.slate500, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                  'Il appartient au domaine « ${ecran.domaine} », module « ${ecran.moduleLabel} ». Aucun écran n’est enregistré pour lui dans la configuration de ce poste : signaler l’incident à l’administrateur.',
                  style: TextStyle(color: JetonsShell.slate500, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }
}
