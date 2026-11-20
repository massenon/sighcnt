// Imprime la clé publique de satisfaction de la clé de TEST du banc (celle de `test/satisfaction_mere_test.dart`), pour `apps/web/tests/navigateur/satisfaction.cjs`.
import 'dart:convert';

import 'package:sigh_sync/src/satisfaction_sceau.dart';

Future<void> main() async {
  print(base64.encode(await clePubliqueSatisfaction(List<int>.generate(32, (i) => (i * 11 + 5) & 0xff))));
}
