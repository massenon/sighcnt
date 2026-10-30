import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jetons_shell.dart';
import 'bouton.dart';

enum TailleModale {
  sm(448),
  md(672),
  lg(896),
  xl(1152);

  const TailleModale(this.largeurMax);
  final double largeurMax;
}

/// Entête commun à la modale et au tiroir : px 20 py 16, filet bas, titre 16/24 en 600, sous-titre 12/16 slate-500, croix « Fermer ».
class _Entete extends StatelessWidget {
  const _Entete(
      {required this.titre,
      this.sousTitre,
      required this.surFermer,
      this.tronquer = false});
  final String titre;
  final String? sousTitre;
  final VoidCallback surFermer;
  final bool tronquer;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('kit:modale-entete'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: JetonsShell.slate200))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: Text(titre,
                    key: const Key('kit:modale-titre'),
                    overflow: tronquer ? TextOverflow.ellipsis : null,
                    style: const TextStyle(
                        color: JetonsShell.slate900,
                        fontSize: 16,
                        height: 24 / 16,
                        fontWeight: FontWeight.w600)),
              ),
              if (sousTitre != null)
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sousTitre!,
                        overflow: tronquer ? TextOverflow.ellipsis : null,
                        style: const TextStyle(
                            color: JetonsShell.slate500,
                            fontSize: 12,
                            height: 16 / 12))),
            ]),
          ),
          const SizedBox(width: 16),
          BoutonIcone(
              icone: LucideIcons.x, libelle: 'Fermer', onPressed: surFermer),
        ]),
      );
}

/// Pied : fond slate-50, filet haut, px 20 py 12, boutons alignés à droite avec 8 d'espace.
class _Pied extends StatelessWidget {
  const _Pied(this.enfants);
  final List<Widget> enfants;
  @override
  Widget build(BuildContext context) => Container(
        key: const Key('kit:modale-pied'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
            color: JetonsShell.slate50,
            border: Border(top: BorderSide(color: JetonsShell.slate200))),
        child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: enfants),
      );
}

typedef ConstruirePied = List<Widget> Function(VoidCallback fermer);

/// `U.modal` : fond navy-950 à 40 %, panneau blanc rayon 12 + ombre `pop`, collé en haut avec 48 px de marge, largeur max
/// selon la taille. Échap ferme (Navigator), le focus reste dans la modale (route modale), animation `pop-in` de 150 ms.
Future<T?> afficherModale<T>(
  BuildContext context, {
  required String titre,
  String? sousTitre,
  TailleModale taille = TailleModale.md,
  required Widget corps,
  ConstruirePied? pied,
  bool fermetureParFond = true,
}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: fermetureParFond,
      barrierLabel: 'Fermer la fenêtre',
      barrierColor: JetonsShell.navy950.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (_, a, __, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
              alignment: Alignment.topCenter,
              child: child)),
      pageBuilder: (ctx, _, __) {
        void fermer() => Navigator.of(ctx).pop();
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: taille.largeurMax),
                child: SizedBox(
                  width: double.infinity, // `w-full max-w-*`
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: titre,
                    child: Material(
                      key: const Key('kit:modale-panneau'),
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: JetonsShell.ombrePop),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Entete(
                                    titre: titre,
                                    sousTitre: sousTitre,
                                    surFermer: fermer),
                                Flexible(
                                    child: SingleChildScrollView(
                                        key: const Key('kit:modale-corps'),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 16),
                                        child: corps)),
                                if (pied != null) _Pied(pied(fermer)),
                              ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

/// `U.confirm` : modale `sm` à deux boutons ; renvoie `true` sur confirmation, `false` sinon (Échap, fond, annulation).
/// Le message est un TEXTE (jamais interprété) — pas d'injection par un nom de patient.
Future<bool> confirmerSigh(BuildContext context,
        {required String titre,
        required String message,
        String libelleOk = 'Confirmer',
        String libelleAnnuler = 'Annuler',
        bool dangereux = false}) async =>
    (await afficherModale<bool>(context,
        titre: titre,
        taille: TailleModale.sm,
        corps: Text(message,
            style: const TextStyle(
                color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: libelleAnnuler,
                  variante: VarianteBouton.secondaire,
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(false)),
              BoutonSigh(
                  libelle: libelleOk,
                  variante: dangereux
                      ? VarianteBouton.danger
                      : VarianteBouton.primaire,
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(true)),
            ])) ==
    true;

/// `U.drawer` : panneau de droite pleine hauteur (`max-w-xl` = 576), même entête / corps / pied que la modale, glissement `slide-in`.
Future<T?> afficherTiroir<T>(
  BuildContext context, {
  required String titre,
  String? sousTitre,
  double largeurMax = 576,
  required Widget corps,
  ConstruirePied? pied,
}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer le panneau',
      barrierColor: JetonsShell.navy950.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (_, a, __, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
          child: child),
      pageBuilder: (ctx, _, __) {
        void fermer() => Navigator.of(ctx).pop();
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: largeurMax),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: titre,
              child: Material(
                key: const Key('kit:tiroir-panneau'),
                color: Colors.white,
                elevation: 0,
                child: DecoratedBox(
                  decoration:
                      const BoxDecoration(boxShadow: JetonsShell.ombrePop),
                  child: SizedBox.expand(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Entete(
                              titre: titre,
                              sousTitre: sousTitre,
                              surFermer: fermer,
                              tronquer: true),
                          Expanded(
                              child: SingleChildScrollView(
                                  key: const Key('kit:tiroir-corps'),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 16),
                                  child: corps)),
                          if (pied != null) _Pied(pied(fermer)),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
