import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/etat_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// Les TROIS pièces réelles ensemble, dans le processus de test : la mère (service), la console (client d'administration)
/// et le moteur fileul embarqué dans l'application. Aucun faux : c'est le code qui partira en production.
void main() {
  const port = 19431;

  Future<T> avant<T>(Future<T> Function() f) => f().timeout(const Duration(seconds: 20));

  test('console → code d\'appairage → fileul appairé → pastille « synchronisé » ; mère coupée → « hors ligne »', () async {
    final mere = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes'));
    await mere.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$port', nom: 'Caisse');
    final source = moteur.source(intervalle: const Duration(milliseconds: 200));
    try {
      expect((await console.etat()).appareils, isEmpty);

      final code = await avant(() => console.codeAppareil('Caisse'));
      await avant(() => moteur.appairer(code));
      moteur.demarrer();

      await _attendre(() => source.value.niveau == NiveauSync.synchronise, 'pastille synchronisée');
      final etat = await console.etat();
      expect(etat.appareils.map((a) => a.etiquette), contains('Caisse'));
      expect(etat.appareils.first.uuid, moteur.uuid);

      // La mère s'arrête : le poste continue, et le DIT.
      await mere.arreter();
      await _attendre(() => source.value.niveau == NiveauSync.horsLigne, 'pastille hors ligne');
      expect(source.value.depuis, isNotNull);
    } finally {
      source.dispose();
      try {
        await mere.arreter();
      } catch (_) {/* déjà arrêtée */}
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}

Future<void> _attendre(bool Function() condition, String quoi) async {
  final fin = DateTime.now().add(const Duration(seconds: 25));
  while (!condition()) {
    if (DateTime.now().isAfter(fin)) fail('délai dépassé : $quoi');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
