import 'package:flutter/foundation.dart';

import '../mere/activation.dart';
import 'config_poste.dart';

/// État vivant du poste : son mode peut CHANGER pendant que l'application tourne (activation de la mère sur le serveur,
/// désactivation). La coque écoute ce contrôleur et recompose ses modules — rien n'est recompilé, rien n'est redémarré.
class ControleurPoste extends ChangeNotifier {
  ControleurPoste({required this.activation, required ConfigPoste config}) : _config = config;
  final ActivationMere activation;
  ConfigPoste _config;
  DateTime? _activeDepuis;
  String? _avertissement;

  ConfigPoste get config => _config;
  DateTime? get activeDepuis => _activeDepuis;

  /// Dernier avertissement de désactivation (place de mère non libérée au relais).
  String? get avertissement => _avertissement;

  Future<void> charger() async {
    final p = await activation.parametres();
    _config = ConfigPoste(mode: p.mode, role: _config.role, nomPoste: p.nomPoste);
    _activeDepuis = p.activeDepuis;
    notifyListeners();
  }

  /// Lève [ActivationRefusee] avec la cause nommée ; le mode ne change qu'en cas de succès.
  Future<void> activer({required String relais, required String secretMere, required String cleClinique, String? nomPoste, bool remplacer = false}) async {
    final p = await activation.activer(relais: relais, secretMere: secretMere, cleClinique: cleClinique, nomPoste: nomPoste, remplacer: remplacer);
    _config = ConfigPoste(mode: p.mode, role: _config.role, nomPoste: p.nomPoste);
    _activeDepuis = p.activeDepuis;
    _avertissement = null;
    notifyListeners();
  }

  Future<void> desactiver({required String secretMere}) async {
    final r = await activation.desactiver(secretMere: secretMere);
    _config = ConfigPoste(mode: r.parametres.mode, role: _config.role, nomPoste: r.parametres.nomPoste);
    _activeDepuis = null;
    _avertissement = r.avertissement;
    notifyListeners();
  }
}
