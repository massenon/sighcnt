import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';

/// Le pied de page LÉGAL de la coque et des pages autonomes (Direction, 01/11/2026) : dénomination, IFU, RCCM, lus de l'identité unique de la clinique
/// ([IdentiteClinique.mentionLegale]). La maquette porte le même pied (`C.mentionLegale()` de `core.js`). Il ne s'imprime pas : les états ont leur propre pied.
class PiedLegal extends StatelessWidget {
  const PiedLegal({super.key, this.fond = Colors.white});

  /// Le fond de la bande (blanc sur la coque, gris clair sur les pages autonomes).
  final Color fond;

  @override
  Widget build(BuildContext context) => Material(
      type: MaterialType.transparency,
      child: Semantics(
      container: true,
      label: 'Mention légale',
      child: Container(
          key: const Key('pied-legal'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          decoration: BoxDecoration(color: fond, border: const Border(top: BorderSide(color: JetonsShell.slate200))),
          child: const Text(IdentiteClinique.mentionLegale,
              key: Key('pied-legal:texte'),
              textAlign: TextAlign.center,
              style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)))));
}
