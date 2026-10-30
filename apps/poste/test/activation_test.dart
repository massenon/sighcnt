import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/mere/activation.dart';

class FauxRelais implements RelaisMere {
  final List<String> appels = [];
  ActivationRefusee? refus;
  ActivationRefusee? refusDesactivation;
  @override
  Future<void> activer(
      {required String uuid,
      required String etiquette,
      required bool remplacer}) async {
    appels.add('activer $uuid $etiquette remplacer=$remplacer');
    if (refus != null) throw refus!;
  }

  @override
  Future<void> desactiver(String uuid) async {
    appels.add('desactiver $uuid');
    if (refusDesactivation != null) throw refusDesactivation!;
  }
}

class FauxService implements ServiceMere {
  bool marche = false;
  Object? echec;
  @override
  bool get enMarche => marche;
  @override
  Future<void> demarrer() async {
    if (echec != null) throw echec!;
    marche = true;
  }

  @override
  Future<void> arreter() async => marche = false;
}

void main() {
  late FauxRelais relais;
  late FauxService service;
  late StockageMemoire stockage;
  late ActivationMere activation;
  const cle = 'CLE-DE-CLINIQUE-0123456789';

  setUp(() {
    relais = FauxRelais();
    service = FauxService();
    stockage = StockageMemoire();
    activation = ActivationMere(
        stockage: stockage, service: service, relaisPour: (_, __) => relais);
  });

  test('premier démarrage : poste fileul, identifiant créé et conservé',
      () async {
    final p = await activation.parametres();
    expect(p.mode, ModePoste.fileul);
    expect(p.uuidPoste, isNotEmpty);
    expect((await activation.parametres()).uuidPoste, p.uuidPoste);
  });

  test(
      'activation réussie : relais déclaré, service démarré, mode mère PERSISTÉ',
      () async {
    final p = await activation.activer(
        relais: 'https://relais.exemple.bj',
        secretMere: 's3cret',
        cleClinique: cle,
        nomPoste: 'Serveur DAF');
    expect(p.mode, ModePoste.mere);
    expect(service.enMarche, isTrue);
    expect((await stockage.lire())!.mode, ModePoste.mere);
    expect(relais.appels.single,
        contains('activer ${p.uuidPoste} Serveur DAF remplacer=false'));
    expect(p.activeDepuis, isNotNull);
  });

  test(
      'UNE SEULE MÈRE : le refus du relais est relayé tel quel et rien ne démarre ni ne s\'écrit',
      () async {
    relais.refus = ActivationRefusee(
        'mere_deja_active', 'Une mère est déjà active : « Serveur DAF ».');
    await expectLater(
        activation.activer(
            relais: 'https://r.bj', secretMere: 's', cleClinique: cle),
        throwsA(isA<ActivationRefusee>()
            .having((e) => e.code, 'code', 'mere_deja_active')
            .having((e) => e.motif, 'motif', contains('Serveur DAF'))));
    expect(service.enMarche, isFalse);
    expect((await activation.parametres()).mode, ModePoste.fileul);
  });

  test('reprise explicite : « remplacer » est transmis', () async {
    await activation.activer(
        relais: 'https://r.bj',
        secretMere: 's',
        cleClinique: cle,
        remplacer: true);
    expect(relais.appels.single, contains('remplacer=true'));
  });

  test('champs obligatoires refusés EN LES NOMMANT, avant tout appel au relais',
      () async {
    for (final c in [
      (relais: '', secret: 's', cle: cle, code: 'relais_invalide'),
      (
        relais: 'pas-une-adresse',
        secret: 's',
        cle: cle,
        code: 'relais_invalide'
      ),
      (relais: 'https://r.bj', secret: '  ', cle: cle, code: 'secret_requis'),
      (
        relais: 'https://r.bj',
        secret: 's',
        cle: 'courte',
        code: 'cle_invalide'
      ),
    ]) {
      await expectLater(
          activation.activer(
              relais: c.relais, secretMere: c.secret, cleClinique: c.cle),
          throwsA(
              isA<ActivationRefusee>().having((e) => e.code, 'code', c.code)));
    }
    expect(relais.appels, isEmpty);
    expect(service.enMarche, isFalse);
  });

  test(
      'ATOMIQUE : si le service ne démarre pas, la déclaration au relais est retirée et le poste reste fileul',
      () async {
    service.echec = StateError('port 9000 occupé');
    await expectLater(
        activation.activer(
            relais: 'https://r.bj', secretMere: 's', cleClinique: cle),
        throwsA(isA<ActivationRefusee>()
            .having((e) => e.code, 'code', 'service_non_demarre')));
    expect(relais.appels.length, 2);
    expect(relais.appels.last, startsWith('desactiver'));
    expect((await activation.parametres()).mode, ModePoste.fileul);
  });

  test('désactivation : service arrêté, place libérée, poste fileul', () async {
    await activation.activer(
        relais: 'https://r.bj', secretMere: 's', cleClinique: cle);
    final r = await activation.desactiver(secretMere: 's');
    expect(r.parametres.mode, ModePoste.fileul);
    expect(r.avertissement, isNull);
    expect(service.enMarche, isFalse);
    expect(relais.appels.last, startsWith('desactiver'));
    expect(r.parametres.activeDepuis, isNull);
  });

  test(
      'désactivation avec relais injoignable : le poste redevient fileul QUAND MÊME et l\'AVERTISSEMENT le dit',
      () async {
    await activation.activer(
        relais: 'https://r.bj', secretMere: 's', cleClinique: cle);
    relais.refusDesactivation =
        ActivationRefusee('relais_injoignable', 'Le relais n’a pas répondu.');
    final r = await activation.desactiver(secretMere: 's');
    expect(r.parametres.mode, ModePoste.fileul);
    expect(r.avertissement, contains('n’a pas été libérée'));
    expect((await stockage.lire())!.mode, ModePoste.fileul);
  });

  test('un fichier de réglages illisible ne rend JAMAIS un poste mère',
      () async {
    final f = StockageFichier('${await _tmp()}/poste.json');
    await f
        .ecrire(const ParametresPoste(uuidPoste: 'u1', mode: ModePoste.mere));
    expect((await f.lire())!.mode, ModePoste.mere);
    await _corrompre(f.chemin);
    expect(await f.lire(), isNull);
  });
}

Future<String> _tmp() async =>
    (await Directory.systemTemp.createTemp('sigh-poste-')).path;
Future<void> _corrompre(String chemin) =>
    File(chemin).writeAsString('{ pas du json');
