import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:test/test.dart';

/// Arbitrage de la Direction du 04/11/2026 (E1350) : la fenêtre de réinitialisation dure 30 minutes, jamais 24 heures, et c'est la MÈRE qui la referme.
void main() {
  late Mere m;
  setUp(() async => m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:')));

  test('la durée arrêtée est de 30 minutes', () => expect(dureeFenetreReinit, const Duration(minutes: 30)));

  test('fermée par défaut', () async => expect(await m.reinitOuverte(), isFalse));

  test('ouverte depuis 29 minutes : encore ouverte', () async {
    await m.base.poserMeta('reinit_ouverte', 1);
    await m.base.poserMeta('reinit_ouverte_ms', maintenantMs() - 29 * 60 * 1000);
    expect(await m.reinitOuverte(), isTrue);
  });

  test('ouverte depuis 31 minutes : refermée par la mère, sans console', () async {
    await m.base.poserMeta('reinit_ouverte', 1);
    await m.base.poserMeta('reinit_ouverte_ms', maintenantMs() - 31 * 60 * 1000);
    expect(await m.reinitOuverte(), isFalse);
    expect(await m.base.meta('reinit_ouverte'), '0');
    expect(await m.reinitOuverte(), isFalse);
  });

  test('un drapeau ouvert sans heure connue est refermé (jamais une fenêtre sans échéance)', () async {
    await m.base.poserMeta('reinit_ouverte', 1);
    expect(await m.reinitOuverte(), isFalse);
  });
}
