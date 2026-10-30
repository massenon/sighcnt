import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/impression/apercu.dart';

/// L'impression système n'est PAS testable sur du matériel ici : on prouve la COMMANDE de chaque plateforme et que tout refus est RENDU en clair.
void main() {
  tearDown(() {
    ImpressionPoste.systeme = Platform.operatingSystem;
    ImpressionPoste.lancer = (e, a) => Process.run(e, a);
  });

  test(
      'commande par plateforme : lp (Linux, macOS), verbe Print du shell (Windows)',
      () {
    ImpressionPoste.systeme = 'linux';
    final (exeL, argsL) = ImpressionPoste.commande('/tmp/a.pdf');
    expect(exeL, 'lp');
    expect(argsL, ['/tmp/a.pdf']);
    ImpressionPoste.systeme = 'macos';
    expect(ImpressionPoste.commande('/tmp/a.pdf').$1, 'lp');
    ImpressionPoste.systeme = 'windows';
    final (exe, args) = ImpressionPoste.commande(r'C:\Temp\a.pdf');
    expect(exe, 'powershell');
    expect(args.last, contains('-Verb Print'));
    expect(args.last, contains(r'C:\Temp\a.pdf'));
  });

  test(
      'succès → null ; refus du système → motif nommé avec le code ; commande absente → motif nommé',
      () async {
    ImpressionPoste.lancer = (e, a) async => ProcessResult(1, 0, '', '');
    expect(await ImpressionPoste.imprimer('/x.pdf'), isNull);
    ImpressionPoste.lancer =
        (e, a) async => ProcessResult(1, 1, '', 'lp: no default destination');
    final refus = await ImpressionPoste.imprimer('/x.pdf');
    expect(refus, contains('code 1'));
    expect(refus, contains('no default destination'));
    ImpressionPoste.lancer =
        (e, a) async => throw ProcessException('lp', a, 'introuvable');
    expect(await ImpressionPoste.imprimer('/x.pdf'),
        contains('Aucune commande d’impression'));
  });
}
