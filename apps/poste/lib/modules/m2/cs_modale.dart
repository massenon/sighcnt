import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../kit/kit.dart';

/// Ouvre une modale portant [champs] ; [valider] reçoit les valeurs saisies et rend `null` (enregistré) ou un REFUS nommé affiché en toast.
/// Le contexte de l'ÉCRAN sert aux messages : une modale vit au-dessus de la coque, hors du `ContexteEcran`.
Future<void> modaleFormulaire(
  BuildContext ecran, {
  required String titre,
  String? sousTitre,
  required List<ChampDef> champs,
  Map<String, Object?> initial = const {},
  required String libelleOk,
  required String? Function(Map<String, Object?> v) valider,
  TailleModale taille = TailleModale.lg,
  Widget? avant,
}) =>
    afficherModale<void>(ecran,
        titre: titre,
        sousTitre: sousTitre,
        taille: taille,
        corps: _CorpsFormulaire(
            ecran: ecran,
            champs: champs,
            initial: initial,
            libelleOk: libelleOk,
            valider: valider,
            avant: avant),
        pied: null);

class _CorpsFormulaire extends StatefulWidget {
  const _CorpsFormulaire(
      {required this.ecran,
      required this.champs,
      required this.initial,
      required this.libelleOk,
      required this.valider,
      this.avant});
  final BuildContext ecran;
  final List<ChampDef> champs;
  final Map<String, Object?> initial;
  final String libelleOk;
  final String? Function(Map<String, Object?>) valider;
  final Widget? avant;
  @override
  State<_CorpsFormulaire> createState() => _EtatCorpsFormulaire();
}

class _EtatCorpsFormulaire extends State<_CorpsFormulaire> {
  late final ControleurFormulaire f =
      ControleurFormulaire(widget.champs, widget.initial);

  @override
  void dispose() {
    f.dispose();
    super.dispose();
  }

  void _ok() {
    final v = f.valider();
    if (v == null) {
      ToastsSigh.afficher(widget.ecran, 'Le formulaire comporte des erreurs.',
          type: TypeToast.erreur);
      return;
    }
    final refus = widget.valider(v);
    if (refus != null) {
      ToastsSigh.afficher(widget.ecran, refus,
          type: TypeToast.erreur, duree: const Duration(seconds: 9));
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.avant != null) ...[widget.avant!, const SizedBox(height: 12)],
            FormulaireSigh(controleur: f),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              BoutonSigh(
                  libelle: widget.libelleOk,
                  icone: LucideIcons.save,
                  onPressed: _ok),
            ]),
          ]);
}
