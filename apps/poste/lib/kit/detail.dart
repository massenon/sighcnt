import 'package:flutter/material.dart';

import '../core/jetons_shell.dart';
import 'badge.dart';
import 'ton.dart';

/// `U.descList` : grille à deux colonnes (une sous 640 px), espace 24 × 12 ; libellé 12 slate-500, valeur 14 en 500 slate-800 ; vide → « — ».
class DescListeSigh extends StatelessWidget {
  const DescListeSigh(this.paires, {super.key});

  /// Valeur : `String`, `null`/vide (affiché « — ») ou un `Widget` (badge, police fixe…).
  final List<(String, Object?)> paires;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final deux = c.maxWidth >= 640;
        final l = deux ? (c.maxWidth - 24) / 2 : c.maxWidth;
        return Wrap(spacing: 24, runSpacing: 12, children: [
          for (final p in paires)
            SizedBox(
              width: l,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.$1,
                        style: const TextStyle(
                            color: JetonsShell.slate500,
                            fontSize: 12,
                            height: 16 / 12)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: p.$2 is Widget
                          ? p.$2 as Widget
                          : Text(p.$2 == null || p.$2 == '' ? '—' : '${p.$2}',
                              style: const TextStyle(
                                  color: JetonsShell.slate800,
                                  fontSize: 14,
                                  height: 20 / 14,
                                  fontWeight: FontWeight.w500)),
                    ),
                  ]),
            ),
        ]);
      });
}

/// `U.statut(clé)` : statuts métier normalisés → badge coloré (le même référentiel que la maquette).
const Map<String, (String, TonSigh)> statutsMetier = {
  'actif': ('Actif', TonSigh.succes),
  'archive': ('Archivé', TonSigh.neutre),
  'inactif': ('Inactif', TonSigh.neutre),
  'libre': ('Libre', TonSigh.succes),
  'occupe': ('Occupé', TonSigh.danger),
  'soldee': ('Soldée', TonSigh.succes),
  'partielle': ('Partielle', TonSigh.attention),
  'impayee': ('Impayée', TonSigh.danger),
  'valide': ('Validé', TonSigh.succes),
  'validee': ('Validée', TonSigh.succes),
  'en_attente': ('En attente', TonSigh.attention),
  'rejete': ('Rejeté', TonSigh.danger),
  'brouillon': ('Brouillon', TonSigh.neutre),
  'en_cours': ('En cours', TonSigh.info),
  'terminee': ('Terminée', TonSigh.succes),
  'planifiee': ('Planifiée', TonSigh.navy),
  'reporte': ('Reporté', TonSigh.attention),
  'non_honore': ('Non honoré', TonSigh.danger),
  'sortie': ('Sorti', TonSigh.neutre),
  'perime': ('Périmé', TonSigh.danger),
  'alerte': ('Péremption proche', TonSigh.attention),
  'rupture': ('Rupture', TonSigh.danger),
  'critique': ('Critique', TonSigh.attention),
  'normal': ('Normal', TonSigh.succes),
  'moins_8h': ('Moins de 8h', TonSigh.info),
  'plus_8h': ('Plus de 8h', TonSigh.navy),
};

Widget statutBadge(Object? cle) {
  final s = statutsMetier['$cle'];
  return s != null
      ? BadgeSigh(s.$1, ton: s.$2)
      : BadgeSigh(cle == null || cle == '' ? '—' : '$cle');
}
