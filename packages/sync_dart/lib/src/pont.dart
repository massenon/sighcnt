/// Le pont de la mère vers le relais (P2) et les mobiles (P3) — étape 1 : coque sans relais configuré.
library;

import 'mere.dart';

class Pont {
  Pont(this.mere);
  final Mere mere;
  final List<Map<String, Object?>> alertes = [];
  String get cleBase64 => '';
  void demarrer() {}
  void revoquerAuRelais(String uuid) {}
  Future<void> declarerCode(String hash) async {}
  Map<String, Object?> lot(Map<String, Object?> b) => {'fiches': 0};
}
