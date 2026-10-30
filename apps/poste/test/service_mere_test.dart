import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'activation_test.dart' show FauxRelais;

/// Le VRAI service de la mère, dans le processus : démarrage, arrêt, et refus quand le port est pris (atomicité).
void main() {
  test('le service réel démarre puis s\'arrête ; un second sur le même port échoue et le poste reste fileul', () async {
    const port = 19437;
    final premier = ServiceMereLocal(ConfigMere(port: port, dbChemin: ':memory:', dossierSauvegardes: '/tmp/sigh-test-sauvegardes'));
    await premier.demarrer();
    expect(premier.enMarche, isTrue);

    final relais = FauxRelais();
    final stockage = StockageMemoire();
    final activation = ActivationMere(
      stockage: stockage,
      service: ServiceMereLocal(ConfigMere(port: port, dbChemin: ':memory:', dossierSauvegardes: '/tmp/sigh-test-sauvegardes')),
      relaisPour: (_, __) => relais,
    );
    await expectLater(activation.activer(relais: 'https://r.bj', secretMere: 's', cleClinique: 'CLE-DE-CLINIQUE-0123456789'), throwsA(isA<ActivationRefusee>().having((e) => e.code, 'code', 'service_non_demarre')));
    expect((await activation.parametres()).mode, ModePoste.fileul);
    expect(relais.appels.last, startsWith('desactiver'));

    await premier.arreter();
    expect(premier.enMarche, isFalse);
    // Le port est libéré : l'activation réussit maintenant, avec le vrai service.
    final p = await activation.activer(relais: 'https://r.bj', secretMere: 's', cleClinique: 'CLE-DE-CLINIQUE-0123456789');
    expect(p.mode, ModePoste.mere);
    await activation.service.arreter();
  });
}
