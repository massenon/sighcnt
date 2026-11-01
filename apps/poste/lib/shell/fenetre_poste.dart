import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// La fenêtre du poste, vue par la barre supérieure : passer en plein écran et en sortir. Une INTERFACE, parce que la plateforme n'est pas pilotable dans un
/// test (aucune fenêtre) : le test injecte [FenetreMemoire], le poste réel [FenetreSysteme].
abstract class FenetrePoste {
  /// L'état réel de la fenêtre (suit aussi la touche F11 et la sortie par le système).
  ValueListenable<bool> get pleinEcran;

  /// Bascule le plein écran. Lève une erreur si la plateforme refuse : l'appelant la DIT (« Plein écran indisponible sur ce poste »).
  Future<void> basculerPleinEcran();
}

/// La fenêtre réelle (Windows, Linux, macOS) pilotée par `window_manager`. Le plugin est initialisé par `main` ; en dehors d'un poste (test), l'appel
/// échoue et la barre l'annonce plutôt que de rester muette.
class FenetreSysteme with WindowListener implements FenetrePoste {
  FenetreSysteme() {
    windowManager.addListener(this);
  }
  final _etat = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get pleinEcran => _etat;

  @override
  Future<void> basculerPleinEcran() async {
    final actuel = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!actuel);
    _etat.value = !actuel;
  }

  @override
  void onWindowEnterFullScreen() => _etat.value = true;

  @override
  void onWindowLeaveFullScreen() => _etat.value = false;
}

/// Une fenêtre factice : l'état se bascule en mémoire (tests).
class FenetreMemoire implements FenetrePoste {
  FenetreMemoire({this.refuse = false});

  /// `true` : la plateforme refuse (le message d'indisponibilité doit paraître).
  final bool refuse;
  final _etat = ValueNotifier<bool>(false);
  int bascules = 0;

  @override
  ValueListenable<bool> get pleinEcran => _etat;

  @override
  Future<void> basculerPleinEcran() async {
    if (refuse) throw StateError('plein écran refusé');
    bascules++;
    _etat.value = !_etat.value;
  }
}
