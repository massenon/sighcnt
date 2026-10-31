import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jetons_shell.dart';
import '../kit/carte.dart';

/// Gabarit de page de la maquette : fil d'Ariane → titre + code du module → description → devise → commandes → règle
/// (encadré bleu) → contenu. Même ordre, mêmes gabarits typographiques (titre 20/600, texte 14, devise 12 italique).
class PageStandard extends StatelessWidget {
  const PageStandard(
      {super.key,
      required this.titre,
      required this.fil,
      this.module,
      this.description,
      this.regle,
      this.actions = const [],
      required this.child,
      this.defilable = true});
  final String titre;
  final List<String> fil;
  final String? module;
  final String? description;
  final String? regle;
  final List<Widget> actions;
  final Widget child;

  /// `false` : le contenu gère lui-même son défilement (listes longues).
  final bool defilable;

  @override
  Widget build(BuildContext context) {
    final entete = <Widget>[
      Row(key: const Key('fil-ariane'), children: [
        for (var i = 0; i < fil.length; i++) ...[
          Text(fil[i],
              style: TextStyle(
                  color: i == fil.length - 1
                      ? JetonsShell.slate700
                      : JetonsShell.slate500,
                  fontSize: 12)),
          if (i < fil.length - 1)
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(LucideIcons.chevronRight,
                    size: 12, color: JetonsShell.slate400)),
        ],
      ]),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                  child: Text(titre,
                      key: const Key('titre-page'),
                      style: const TextStyle(
                          color: JetonsShell.slate900,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.4))),
              if (module != null) ...[
                const SizedBox(width: 8),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: JetonsShell.navy50,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(module!,
                        style: const TextStyle(
                            color: JetonsShell.navy800,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Consolas'))),
              ],
            ]),
            if (description != null)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(description!,
                      style: const TextStyle(
                          color: JetonsShell.slate500, fontSize: 14))),
            const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Votre santé, notre raison de vivre',
                    style: TextStyle(
                        color: JetonsShell.slate400,
                        fontSize: 12,
                        fontStyle: FontStyle.italic))),
          ]),
        ),
        if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
      ]),
      if (regle != null) ...[
        const SizedBox(height: 14),
        NoteSigh(regle!),
      ],
      const SizedBox(height: 16),
    ];
    final corps = Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: defilable
          ? SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [...entete, child]))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [...entete, Expanded(child: child)]),
    );
    return ColoredBox(color: JetonsShell.navy50, child: corps);
  }
}
