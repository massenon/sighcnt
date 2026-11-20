import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../m14/commun_m14.dart' show droitModule, rolesDe, surchargesRbac;

/// Une rangée du manifeste avec les rôles que le MANIFESTE (pas la matrice) donne à chacun de ses écrans — c'est ce que lit « Périmètre d'accès » de
/// `cfg-compte` : `mod.items.some(it => N.can(role, { roles: it.roles || mod.roles, module: mod.code }))`, SANS identifiant d'écran, donc sans les
/// réglages d'écran de la matrice. Les deux ne disent pas la même chose (un accueil voit « Consultations & prescriptions » au ruban de la maquette
/// même quand le dossier lui en est fermé écran par écran) ; le poste reproduit la maquette.
class CfbRangeeRoles {
  const CfbRangeeRoles(this.code, this.alias, this.ecrans);
  final String code;
  final bool alias;

  /// Les rôles de chaque écran : `null` = tous (`'ALL'`). Une rangée d'ALIAS ne déclare aucun rôle propre : ses écrans s'ouvrent à tous (E850).
  final List<List<String>?> ecrans;
}

/// Les rangées, dans l'ordre du ruban, depuis `assets/donnees/manifeste.json` (ENGENDRÉ par la maquette).
List<CfbRangeeRoles> cfbRangeesRoles(String manifesteJson) {
  final m = (jsonDecode(manifesteJson) as Map).cast<String, Object?>();
  List<String>? roles(Object? r) => r is List ? [for (final x in r) '$x'] : null;
  final parId = {for (final e in (m['ecrans'] as List)) '${(e as Map)['id']}': roles(e['roles'])};
  return [
    for (final r in (m['modules'] as List))
      CfbRangeeRoles('${(r as Map)['code']}', r['alias'] == true,
          [for (final id in (r['ecrans'] as List)) (r['alias'] != true && parId.containsKey('$id')) ? parId['$id'] : roles(r['roles'])])
  ];
}

List<CfbRangeeRoles>? _chargees;

/// Les rangées déjà chargées (les tests les posent par [cfbPoserRangeesRoles]).
List<CfbRangeeRoles>? get cfbRangeesRolesChargees => _chargees;
void cfbPoserRangeesRoles(List<CfbRangeeRoles> r) => _chargees = r;

/// Chargées une fois depuis les assets (la coque détient le manifeste et ne le transmet pas aux écrans).
Future<List<CfbRangeeRoles>> cfbChargerRangeesRoles() async => _chargees ??= cfbRangeesRoles(await rootBundle.loadString('assets/donnees/manifeste.json'));

/// `N.can(role, { roles, module })` pour chaque écran de chaque rangée : un module FERMÉ par la clinique ne compte pas ; la surcharge du module décide
/// quand elle se prononce (dans les deux sens) ; sinon le manifeste fait foi, puis le droit du module.
List<String> cfbPerimetre(Magasin m, String role, List<CfbRangeeRoles> rangees) {
  if (rolesDe(m).any((r) => r.id == role && r.archive)) return const [];
  final fermetures = CfbFermetures.depuis(m.collection('modulesActifs').toutes);
  final sur = surchargesRbac(m);
  final droits = (sur[role]?['droits'] as Map?)?.cast<String, Object?>();
  final out = <String>[];
  for (final r in rangees) {
    if (r.ecrans.isEmpty || !fermetures.ecranActif('', r.code)) continue;
    final o = droits?[r.code] as Map?;
    final explicite = o != null && o['voir'] != null ? o['voir'] == true : null;
    final ok = explicite ?? r.ecrans.any((roles) => (roles == null || roles.contains(role)) && droitModule(m, role, r.code).voir);
    if (ok) out.add(r.code);
  }
  return out;
}
