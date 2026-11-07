import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/sync/etat_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';

void main() {
  test(
      'le moteur fileul réel (sigh_sync) s\'instancie dans l\'application et se lit « hors ligne » sans mère',
      () async {
    final m =
        MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1');
    expect(m.uuid, isNotEmpty);
    final i = await m.instantane();
    expect(i.suspendu, isFalse);
    expect(i.enAttente, 0);
    final s = m.source(intervalle: const Duration(hours: 1));
    await s.actualiser();
    expect(s.value.niveau, anyOf(NiveauSync.synchronise, NiveauSync.horsLigne));
    s.dispose();
  });
}
