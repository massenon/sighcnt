import 'dart:async';

import 'package:sigh_poste/shell/coque.dart';

/// Les bancs écrits avant le 03/11/2026 supposent la mise en page « panneau du méga-menu ouvert » (hauteurs de liste, éléments construits). Ils la gardent ;
/// le défaut LIVRÉ (panneau replié) est mesuré par `coque_test.dart`, qui le rétablit.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CoquePoste.panneauOuvertAuDemarrage = true;
  await testMain();
}
