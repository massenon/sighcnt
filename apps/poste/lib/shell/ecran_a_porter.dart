import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/donnees_navigation.dart';
import '../core/jetons_shell.dart';
import 'page_standard.dart';

/// Écran de la maquette pas encore converti en Dart. Il DIT où il en est : sa tranche, son statut, et ce qu'il reste à
/// faire — jamais une page vide ni une erreur. Le prototype de référence est `prototype_html/pages/<id>.php`.
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
          const Icon(LucideIcons.construction,
              size: 22, color: JetonsShell.slate400),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Écran de la maquette à convertir',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: JetonsShell.slate900)),
              const SizedBox(height: 6),
              Text(
                  'Identifiant : ${ecran.id} · module ${ecran.module}${t != null ? ' · tranche $t' : ''} · parité : ${donnees.statut(ecran.id)}.',
                  style: const TextStyle(
                      color: JetonsShell.slate500, fontSize: 13)),
              const SizedBox(height: 4),
              const Text(
                  'Même contenu, même structure et même comportement que la maquette PHP — voir docs/plans/PLAN-conversion-305-ecrans.md.',
                  style: TextStyle(color: JetonsShell.slate500, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }
}
