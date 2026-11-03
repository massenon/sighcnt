import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/plages_codes.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// RG-01 : deux postes ne tirent jamais le même numéro de dossier (limite levée le 03/11/2026).
final auj = DateTime(2026, 11, 3, 9);

Magasin poste() => Magasin({'patients': <Map<String, Object?>>[]});

void main() {
  test('sans service de plage, la règle historique (plus grand rang + 1) ; plage détenue : le numéro suivant, qui avance dès la réservation', () async {
    final m = poste();
    m.collection('patients').inserer({'code': 'CNT/7/26', 'nom': 'A'}, prefixe: 'PAT');
    final s = PlagesCodes.de(m);
    expect(s.actif, isFalse);
    expect(s.prochainCode(m.collection('patients').toutes, auj), 'CNT/8/26');
    s.obtenir = (taille, minimum) async => (minimum, minimum + taille - 1);
    await s.recharger(maintenant: auj);
    expect(s.plages.single['debut'], 8, reason: 'la plage commence au-dessus des dossiers que le poste connaît');
    expect(s.prochainCode(m.collection('patients').toutes, auj), 'CNT/8/26');
    expect(s.prochainCode(m.collection('patients').toutes, auj), 'CNT/9/26', reason: 'un second guichet ne reçoit pas le même numéro');
    expect(s.restants, 48);
  });

  test('plage épuisée hors ligne : jamais de numéro inventé, un code PROVISOIRE ; la plage est conservée au magasin', () async {
    final m = poste();
    final s = PlagesCodes.de(m);
    var enligne = true;
    var suivant = 100;
    s.obtenir = (taille, minimum) async {
      if (!enligne) throw StateError('hors ligne');
      final r = (suivant, suivant + 1);
      suivant += 2;
      return r;
    };
    await s.recharger(maintenant: auj);
    expect(s.prochainCode(const [], auj), 'CNT/100/26');
    expect(s.prochainCode(const [], auj), 'CNT/101/26');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // La recharge en ligne a donné une seconde plage (102-103) ; on la consomme, puis la mère devient injoignable.
    enligne = false;
    expect(s.prochainCode(const [], auj), 'CNT/102/26');
    expect(s.prochainCode(const [], auj), 'CNT/103/26');
    final c = s.prochainCode(const [], auj);
    expect(c, startsWith('PROV-'));
    expect(m.collection(PlagesCodes.collection).toutes, isNotEmpty);
  });

  test('BOUT EN BOUT : la mère et deux fileuls créent des dossiers en même temps, sans lien : aucun code en double, tout converge', () async {
    const port = 19441;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-plg'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteurA = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'A');
    final moteurB = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'B');
    final mm = poste(), ma = poste(), mb = poste();
    // Des dossiers déjà là sur la mère : les plages doivent commencer au-dessus.
    mm.collection('patients').inserer({'code': 'CNT/1109/26', 'nom': 'ANCIEN'}, prefixe: 'PAT');
    final transportMere = TransportMereLocale(port: port, admin: 'secret-test');
    PlagesCodes.de(mm).obtenir = transportMere.plage;
    PlagesCodes.de(ma).obtenir = (t, mi) => moteurA.demanderPlage(taille: t, minimum: mi);
    PlagesCodes.de(mb).obtenir = (t, mi) => moteurB.demanderPlage(taille: t, minimum: mi);
    PontActivite pont(Magasin m, TransportPont t, String e) => PontActivite(m, t, etiquette: e);
    TransportFileul tf(MoteurFileul mo) =>
        TransportFileul(lire: mo.liste, ecrireFiche: (c, f, {required existe, required champs}) => mo.ecrire(c, f, existe: existe, champs: champs));
    final pm = pont(mm, transportMere, 'M'), pa = pont(ma, tf(moteurA), 'A'), pb = pont(mb, tf(moteurB), 'B');
    try {
      for (final mo in [moteurA, moteurB]) {
        final code = await console.codeAppareil(mo == moteurA ? 'A' : 'B').timeout(const Duration(seconds: 20));
        await mo.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
        mo.demarrer();
      }
      await PlagesCodes.de(mm).recharger(maintenant: auj);
      await PlagesCodes.de(ma).recharger(maintenant: auj);
      await PlagesCodes.de(mb).recharger(maintenant: auj);
      for (final m in [mm, ma, mb]) {
        expect(PlagesCodes.de(m).restants, 50, reason: 'chaque poste détient sa plage');
      }
      // Trois postes, hors lien, créent trois dossiers chacun.
      for (final (m, nom) in [(mm, 'M'), (ma, 'A'), (mb, 'B')]) {
        for (var i = 0; i < 3; i++) {
          final code = PlagesCodes.de(m).prochainCode(m.collection('patients').toutes, auj);
          m.collection('patients').inserer({'code': code, 'nom': '$nom$i'}, prefixe: 'PAT');
        }
      }
      final fin = DateTime.now().add(const Duration(seconds: 40));
      bool fini() => [mm, ma, mb].every((m) => m.collection('patients').toutes.length == 10);
      while (!fini()) {
        for (final p in [pa, pb, pm]) {
          await p.cycle();
        }
        if (DateTime.now().isAfter(fin)) fail('pas de convergence : ${[mm, ma, mb].map((m) => m.collection('patients').toutes.length)} ; ${pm.erreur.value} ${pa.erreur.value} ${pb.erreur.value}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      for (final m in [mm, ma, mb]) {
        final codes = [for (final f in m.collection('patients').toutes) f['code']];
        expect(codes.toSet().length, codes.length, reason: 'aucun code en double : $codes');
        expect(m.collection('patients').toutes.any((f) => f['codeEnDoublon'] == true), isFalse);
        expect(codes.where((c) => '$c'.startsWith('PROV-')), isEmpty);
      }
      final rangs = [for (final f in mm.collection('patients').toutes) int.parse('${f['code']}'.split('/')[1])]..sort();
      expect(rangs.where((r) => r != 1109).every((r) => r > 1109), isTrue, reason: 'les plages commencent au-dessus des dossiers existants');
    } finally {
      pa.arreter();
      pb.arreter();
      pm.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
