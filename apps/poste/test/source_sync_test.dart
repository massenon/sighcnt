import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/sync/etat_sync.dart';
import 'package:sigh_poste/sync/source_sync.dart';

void main() {
  test('lecture de l\'état : suspendu > hors ligne > en cours > synchronisé, jamais un voyant muet', () {
    expect(lireEtat(const InstantaneSync(suspendu: true, horsLigne: true)).niveau, NiveauSync.suspendu);
    expect(lireEtat(const InstantaneSync(horsLigne: true, enAttente: 3)).niveau, NiveauSync.horsLigne);
    expect(lireEtat(const InstantaneSync(horsLigne: true, enAttente: 3)).enAttente, 3);
    expect(lireEtat(const InstantaneSync(enAttente: 2)).niveau, NiveauSync.enCours);
    expect(lireEtat(const InstantaneSync()).niveau, NiveauSync.synchronise);
    expect(lireEtat(const InstantaneSync(aTraiter: 4)).aTraiter, 4);
  });

  test('instantané relu depuis la réponse de GET /etat du moteur', () {
    final i = InstantaneSync.depuisEtat({'hors_ligne': true, 'suspendu': false, 'en_attente': 5, 'a_traiter': [{}, {}], 'tentatives': 3, 'derniere_erreur': 'x'});
    expect([i.horsLigne, i.enAttente, i.aTraiter, i.tentatives, i.derniereErreur], [true, 5, 2, 3, 'x']);
  });

  test('« depuis » compte depuis le DÉBUT de la coupure, pas depuis le dernier sondage ; il repart à la reprise', () async {
    var horloge = DateTime(2026, 10, 30, 12, 0);
    var instantane = const InstantaneSync(horsLigne: true, enAttente: 1);
    final s = SourceSyncPeriodique(lire: () async => instantane, intervalle: const Duration(hours: 1), maintenant: () => horloge);
    await s.actualiser();
    final debut = s.value.depuis;
    expect(s.value.niveau, NiveauSync.horsLigne);
    expect(debut, DateTime(2026, 10, 30, 12, 0));
    horloge = DateTime(2026, 10, 30, 12, 20);
    await s.actualiser();
    expect(s.value.depuis, debut);
    instantane = const InstantaneSync();
    await s.actualiser();
    expect(s.value.niveau, NiveauSync.synchronise);
    expect(s.value.depuis, isNull);
    s.dispose();
  });

  test('un moteur qui ne répond pas se lit « hors ligne »', () async {
    final s = SourceSyncPeriodique(lire: () async => throw StateError('moteur arrêté'), intervalle: const Duration(hours: 1));
    await s.actualiser();
    expect(s.value.niveau, NiveauSync.horsLigne);
    s.dispose();
  });
}
