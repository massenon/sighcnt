import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jetons_shell.dart';
import 'ton.dart';

/// `.card` : rayon 12, bordure slate-200, ombre `card`.
BoxDecoration decorationCarte() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: JetonsShell.slate200),
    boxShadow: JetonsShell.ombreCarte);

/// `U.card(titre, corps, actions)` : en-tête (px 20 py 14, filet bas), titre 14/20 en 600, corps p 20.
class CarteSigh extends StatelessWidget {
  const CarteSigh(
      {super.key,
      this.titre,
      required this.child,
      this.actions = const [],
      this.sansRemplissage = false});
  final String? titre;
  final Widget child;
  final List<Widget> actions;

  /// Tableaux : le corps touche les bords (`overflow-hidden`, pas de `card-body`).
  final bool sansRemplissage;

  @override
  Widget build(BuildContext context) => Container(
        decoration: decorationCarte(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (titre != null)
                  Container(
                    key: const Key('kit:carte-entete'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: JetonsShell.slate200))),
                    child: Row(children: [
                      Expanded(
                          child: Text(titre!,
                              key: const Key('kit:carte-titre'),
                              style: const TextStyle(
                                  color: JetonsShell.slate900,
                                  fontSize: 14,
                                  height: 20 / 14,
                                  fontWeight: FontWeight.w600))),
                      ...actions,
                    ]),
                  ),
                Padding(
                    key: const Key('kit:carte-corps'),
                    padding: sansRemplissage
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(20),
                    child: child),
              ]),
        ),
      );
}

/// `.kpi` : carte p 16 ; libellé 12/16 en 500 slate-500, valeur 24/32 en 600 (interligne −0,025 em), pastille d'icône 36×36 rayon 8.
class KpiSigh extends StatelessWidget {
  const KpiSigh(
      {super.key,
      required this.libelle,
      required this.valeur,
      this.icone,
      this.ton = TonSigh.navy,
      this.indice});
  final String libelle;
  final String valeur;
  final IconData? icone;
  final TonSigh ton;
  final String? indice;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '$libelle : $valeur',
        excludeSemantics: true,
        child: Container(
          key: const Key('kit:kpi'),
          padding: const EdgeInsets.all(16),
          decoration: decorationCarte(),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(libelle,
                        key: const Key('kit:kpi-libelle'),
                        style: const TextStyle(
                            color: JetonsShell.slate500,
                            fontSize: 12,
                            height: 16 / 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(valeur,
                        key: const Key('kit:kpi-valeur'),
                        style: const TextStyle(
                            color: JetonsShell.slate900,
                            fontSize: 24,
                            height: 32 / 24,
                            letterSpacing: -0.6,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    if (indice != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(indice!,
                              style: const TextStyle(
                                  color: JetonsShell.slate400,
                                  fontSize: 12,
                                  height: 16 / 12))),
                  ]),
            ),
            if (icone != null) ...[
              const SizedBox(width: 12),
              Container(
                key: const Key('kit:kpi-pastille'),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: ton.fond50, borderRadius: BorderRadius.circular(8)),
                child: Icon(icone, size: 20, color: ton.icone600),
              ),
            ],
          ]),
        ),
      );
}

/// `U.kpiGrid(specs, cols)` : grille gap 12, 4 colonnes en large (2 en dessous de 1024 px, 1 sous 640 px quand `serre`).
class KpiGrilleSigh extends StatelessWidget {
  const KpiGrilleSigh({super.key, required this.kpis, this.colonnes});
  final List<KpiSigh> kpis;
  final int? colonnes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final n = colonnes ?? (c.maxWidth >= 1024 ? 4 : 2);
        final l = (c.maxWidth - 12 * (n - 1)) / n;
        return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final k in kpis) SizedBox(width: l, child: k)]);
      });
}

/// `K.note` : encadré ton-50 / bordure ton-200, icône ton-600, texte 12/16 ton-900 ; px 12 py 8, rayon 8.
class NoteSigh extends StatelessWidget {
  const NoteSigh(this.texte,
      {super.key, this.ton = TonSigh.info, this.icone = LucideIcons.info});
  final String texte;
  final TonSigh ton;
  final IconData icone;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('kit:note'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: ton.fond50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ton.bordure200)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Icon(icone, size: 16, color: ton.icone600)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(texte,
                  style: TextStyle(
                      color: ton.texte900, fontSize: 12, height: 16 / 12))),
        ]),
      );
}

/// `U.empty` : icône 48 dans un disque slate-100, message 14/20 en 500, indice 12/16 ; py 56, px 24, espace 12.
class VideSigh extends StatelessWidget {
  const VideSigh(this.message,
      {super.key, this.indice, this.icone = LucideIcons.inbox, this.action});
  final String message;
  final String? indice;
  final IconData icone;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('kit:vide'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              key: const Key('kit:vide-icone'),
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                  color: JetonsShell.slate100, shape: BoxShape.circle),
              child: Icon(icone, size: 24, color: JetonsShell.slate400)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: JetonsShell.slate700,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w500)),
          if (indice != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384),
                child: Text(indice!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: JetonsShell.slate500,
                        fontSize: 12,
                        height: 16 / 12))),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ]),
      );
}
