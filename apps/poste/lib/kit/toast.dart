import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jetons_shell.dart';
import 'bouton.dart';
import 'ton.dart';

enum TypeToast { succes, erreur, attention, info }

/// `U.toast` : carte de 22 rem, rayon 12, ombre `pop`, empilée en haut à droite sous la barre (56 + 16 px) ; le plus récent en tête. Avec `annuler`,
/// un bouton « Annuler » exécute l'annulation PUIS annonce « Action annulée. » (une annulation doit être visible). 4 s, 8 s avec annulation.
class ToastsSigh {
  ToastsSigh._();
  static final List<_Entree> _pile = [];
  static OverlayEntry? _hote;
  static OverlayState? _overlay;

  static void afficher(BuildContext context, String message,
      {TypeToast type = TypeToast.info,
      String? detail,
      VoidCallback? annuler,
      String messageAnnulation = 'Action annulée.',
      Duration? duree}) {
    // Le contexte d'un message fermé est défunt : l'annonce « Action annulée. » réutilise l'overlay déjà obtenu.
    final overlay =
        context.mounted ? Overlay.of(context, rootOverlay: true) : _overlay!;
    _overlay = overlay;
    final e = _Entree(message, type, detail, annuler, messageAnnulation);
    _pile.insert(0, e);
    _hote ??= OverlayEntry(builder: (_) => const _Pile());
    if (!(_hote!.mounted)) overlay.insert(_hote!);
    _pile.isNotEmpty ? _versions.value++ : null;
    e.minuterie = Timer(
        duree ??
            (annuler != null
                ? const Duration(seconds: 8)
                : const Duration(seconds: 4)),
        () => _fermer(e));
  }

  static final ValueNotifier<int> _versions = ValueNotifier(0);

  static void _fermer(_Entree e) {
    e.minuterie?.cancel();
    _pile.remove(e);
    _versions.value++;
    if (_pile.isEmpty && _hote != null) {
      if (_hote!.mounted) _hote!.remove();
      _hote =
          null; // une entrée retirée ne se réinsère pas : la suivante en crée une neuve
    }
  }

  /// Nombre de messages affichés (tests).
  static int get nombre => _pile.length;

  static void viderPourTests() {
    for (final e in [..._pile]) {
      _fermer(e);
    }
  }
}

class _Entree {
  _Entree(this.message, this.type, this.detail, this.annuler,
      this.messageAnnulation);
  final String message;
  final TypeToast type;
  final String? detail;
  final VoidCallback? annuler;
  final String messageAnnulation;
  Timer? minuterie;
}

class _Pile extends StatelessWidget {
  const _Pile();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: ToastsSigh._versions,
        builder: (context, _, __) => Positioned(
          top: 72,
          right: 16,
          child: Material(
            type: MaterialType.transparency,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final e in ToastsSigh._pile)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Carte(e)),
            ]),
          ),
        ),
      );
}

class _Carte extends StatelessWidget {
  const _Carte(this.e);
  final _Entree e;

  @override
  Widget build(BuildContext context) {
    final (ton, icone) = switch (e.type) {
      TypeToast.succes => (TonSigh.succes, LucideIcons.circleCheck),
      TypeToast.erreur => (TonSigh.danger, LucideIcons.circleAlert),
      TypeToast.attention => (TonSigh.attention, LucideIcons.triangleAlert),
      TypeToast.info => (TonSigh.neutre, LucideIcons.info),
    };
    final fond = e.type == TypeToast.info ? Colors.white : ton.fond50;
    final bord =
        e.type == TypeToast.info ? JetonsShell.slate200 : ton.bordure200;
    final couleurIcone =
        e.type == TypeToast.info ? JetonsShell.navy700 : ton.icone600;
    return Semantics(
      liveRegion: true,
      container: true,
      label: e.message,
      child: Container(
        width: 352,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: fond,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bord),
            boxShadow: JetonsShell.ombrePop),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icone, size: 20, color: couleurIcone)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.message,
                  style: const TextStyle(
                      color: JetonsShell.slate800,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w500)),
              if (e.detail != null)
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e.detail!,
                        style: const TextStyle(
                            color: JetonsShell.slate500,
                            fontSize: 12,
                            height: 16 / 12))),
            ]),
          ),
          const SizedBox(width: 12),
          if (e.annuler != null)
            BoutonSigh(
                libelle: 'Annuler',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () {
                  e.annuler!();
                  ToastsSigh._fermer(e);
                  ToastsSigh.afficher(context, e.messageAnnulation);
                }),
          const SizedBox(width: 4),
          BoutonIcone(
              icone: LucideIcons.x,
              libelle: 'Fermer',
              onPressed: () => ToastsSigh._fermer(e)),
        ]),
      ),
    );
  }
}
