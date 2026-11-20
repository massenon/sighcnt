import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/horssite_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/horssite_ui.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

/// LA COPIE HORS SITE AU POSTE (lot 5, ADR-0007) : DÉSACTIVÉE par défaut, réglage de clinique en base (versionné par date), réservé à l'administrateur et à la DAF, motivé, journalisé ; un
/// fileul le lit sans le poser ; l'état et les gestes passent par la mère ; la restauration exige sa confirmation nommée ; les commandes sont ABSENTES sans le droit, jamais grisées.
class SourceFausse implements SourceHorsSite {
  final List<String> appels = [];
  Map<String, Object?> etatRendu = {
    'actif': true,
    'relaisRelie': true,
    'controle': {'quand': 1760000000000},
    'types': {
      'magasin': {'destination': 'relais', 'dernier': {'quand': 1760000000000, 'deposes': 7}, 'erreur': null, 'enRetard': false},
      'fichiers': {'destination': 'aucune', 'dernier': null, 'erreur': {'code': 'DOSSIER_INTROUVABLE', 'motif': 'le dossier n\'est pas monté', 'geste': 'Brancher le dossier.'}},
    },
  };
  @override
  Future<Map<String, Object?>> etat() async => etatRendu;
  @override
  Future<Map<String, Object?>> lancer(String type) async {
    appels.add('lancer:$type');
    return {'ok': true};
  }

  @override
  Future<Map<String, Object?>> controler() async {
    appels.add('controler');
    return {};
  }

  @override
  Future<List<Map<String, Object?>>> copies(String type) async => [
        {'id': 'a' * 64, 'etat': 'complete', 'date': 1760000000000, 'nbBlocs': 9},
      ];
  @override
  Future<Map<String, Object?>> restaurer({required String type, required String copie, required String cible}) async {
    appels.add('restaurer:$type:$cible');
    return {'ok': true, 'type': type, 'elements': 1, 'octets': 10, 'cible': cible};
  }
}

Magasin nouveau({bool semer = true}) {
  final m = Magasin({'audit': const [], 'personnel': const [], 'patients': const []}, 'POSTE')
    ..utilisateur = 'Agent Test'
    ..horloge = () => DateTime.utc(2026, 11, 14, 9);
  if (semer) serviceParametres(m, auteur: () => 'semis', horloge: () => m.horloge()).semerDefauts();
  return m;
}

int versions(Magasin m, String cle) => serviceParametres(m, auteur: () => 'x', horloge: () => m.horloge()).versions(cle).length;

void main() {
  group('le réglage', () {
    test('DÉSACTIVÉE par défaut : sans semis (non reçu), puis avec les défauts semés', () {
      final m = nouveau(semer: false);
      final s = HorsSitePoste(m);
      expect(s.reglageRecu, isFalse, reason: 'non reçu : jamais « désactivée » en silence');
      expect(s.reglage.actif, isFalse);
      final m2 = nouveau();
      final s2 = HorsSitePoste(m2);
      expect(s2.reglageRecu, isTrue);
      expect(s2.reglage.actif, isFalse);
      expect(s2.reglage.magasin.destination, 'relais');
      expect(s2.reglage.fichiers.destination, 'aucune');
      expect(s2.reglage.tailleBloc, 1024 * 1024);
      expect(s2.reglage.frequenceMinutes, 60);
    });

    test('refus nommés, rien n\'est écrit : fileul, rôle sans droit, motif absent, sans destination, hors bornes', () {
      final m = nouveau();
      final s = HorsSitePoste(m);
      final avant = versions(m, shCleActif);
      const voulu = ReglageHorsSite(actif: true);
      expect(s.definirReglage(role: 'soignant', nouveau: voulu, motif: 'essai')!.code, 'REGLAGE_RESERVE');
      expect(s.definirReglage(role: 'admin', nouveau: voulu, motif: '  ')!.code, 'MOTIF_REQUIS');
      expect(s.definirReglage(role: 'admin', nouveau: const ReglageHorsSite(actif: true, magasin: ReglageType(destination: 'aucune', dossier: '', copies: 7)), motif: 'essai')!.code, 'DESTINATION_ABSENTE');
      expect(s.definirReglage(role: 'admin', nouveau: const ReglageHorsSite(actif: true, magasin: ReglageType(destination: 'relais', dossier: '', copies: 1)), motif: 'essai')!.code, 'ROTATION_HORS_BORNES');
      expect(s.definirReglage(role: 'admin', nouveau: const ReglageHorsSite(actif: true, tailleBloc: 100), motif: 'essai')!.code, 'TAILLE_BLOC_HORS_BORNES');
      final fileul = HorsSitePoste(m, estFileul: () => true);
      final r = fileul.definirReglage(role: 'admin', nouveau: voulu, motif: 'essai');
      expect(r!.code, 'FILEUL_LECTURE_SEULE');
      expect(r.geste, contains('poste mère'));
      expect(versions(m, shCleActif), avant);
      expect(s.reglage.actif, isFalse);
    });

    test('l\'administrateur et la DAF règlent : nouvelle version datée, seulement ce qui change, journalisé (RG-12) ; un second enregistrement identique n\'ajoute rien', () {
      final m = nouveau();
      final s = HorsSitePoste(m);
      const voulu = ReglageHorsSite(actif: true, frequenceMinutes: 30);
      expect(s.definirReglage(role: 'admin', nouveau: voulu, motif: 'Mise en service'), isNull);
      expect(s.reglage.actif, isTrue);
      expect(s.reglage.frequenceMinutes, 30);
      expect(versions(m, shCleActif), 2, reason: 'version 0 semée, puis la version de l\'administrateur');
      expect(versions(m, shCleFrequence), 2);
      expect(versions(m, shCleTailleBloc), 1, reason: 'ce qui ne change pas n\'est pas réécrit');
      final ecrit = versions(m, shCleActif);
      expect(s.definirReglage(role: 'da', nouveau: voulu, motif: 'Même réglage'), isNull);
      expect(versions(m, shCleActif), ecrit);
      final journal = m.collection('audit').actives.where((x) => '${x['action']}'.contains('Réglage de la copie hors site')).toList();
      expect(journal.length, 2);
      expect('${journal.first}', contains('Agent Test'));
    });

    test('un poste autonome qui n\'a pas reçu le semis le sème à son premier réglage', () {
      final m = nouveau(semer: false);
      final s = HorsSitePoste(m);
      expect(s.definirReglage(role: 'admin', nouveau: const ReglageHorsSite(actif: true), motif: 'Premier réglage'), isNull);
      expect(s.reglageRecu, isTrue);
      expect(s.reglage.actif, isTrue);
    });

    test('activer vers le relais quand la mère dit qu\'elle n\'y est pas reliée : refus nommé RELAIS_NON_CONFIGURE ; un dossier distant reste permis', () async {
      final m = nouveau();
      final src = SourceFausse()..etatRendu = {'actif': false, 'relaisRelie': false, 'types': <String, Object?>{}};
      final s = HorsSitePoste(m, source: src, estMere: () => true);
      await s.rafraichir();
      expect(s.definirReglage(role: 'admin', nouveau: const ReglageHorsSite(actif: true), motif: 'essai')!.code, 'RELAIS_NON_CONFIGURE');
      expect(
          s.definirReglage(role: 'admin', nouveau: const ReglageHorsSite(actif: true, magasin: ReglageType(destination: 'dossier', dossier: '/mnt/sauv', copies: 7)), motif: 'dossier monté'),
          isNull);
    });
  });

  group('les gestes passent par la mère', () {
    test('un poste qui n\'est pas la mère : MERE_REQUISE ; sans droit : REGLAGE_RESERVE ; la mère les exécute', () async {
      final m = nouveau();
      final sans = HorsSitePoste(m);
      expect((await sans.copierMaintenant(role: 'admin', type: 'magasin'))!.code, 'MERE_REQUISE');
      final src = SourceFausse();
      final s = HorsSitePoste(m, source: src, estMere: () => true);
      expect((await s.copierMaintenant(role: 'soignant', type: 'magasin'))!.code, 'REGLAGE_RESERVE');
      expect(src.appels, isEmpty);
      expect(await s.copierMaintenant(role: 'admin', type: 'magasin'), isNull);
      expect(await s.controlerMaintenant(role: 'da'), isNull);
      expect(src.appels, ['lancer:magasin', 'controler']);
      final pasMere = HorsSitePoste(m, source: src, estMere: () => false);
      expect(pasMere.source, isNull, reason: 'le mode peut changer pendant que l\'application tourne');
    });

    test('la restauration exige sa confirmation NOMMÉE et une cible : jamais silencieuse ; journalisée', () async {
      final m = nouveau();
      final src = SourceFausse();
      final s = HorsSitePoste(m, source: src, estMere: () => true);
      final (_, r1) = await s.restaurer(role: 'admin', type: 'magasin', copie: 'a' * 64, cible: '/restaure', confirmation: '');
      expect(r1!.code, 'CONFIRMATION_REQUISE');
      expect(r1.geste, contains('magasin'));
      final (_, r2) = await s.restaurer(role: 'admin', type: 'magasin', copie: 'a' * 64, cible: '/restaure', confirmation: 'fichiers');
      expect(r2!.code, 'CONFIRMATION_REQUISE');
      final (_, r3) = await s.restaurer(role: 'admin', type: 'magasin', copie: 'a' * 64, cible: '  ', confirmation: 'magasin');
      expect(r3!.code, 'CIBLE_ABSENTE');
      final (_, r4) = await s.restaurer(role: 'soignant', type: 'magasin', copie: 'a' * 64, cible: '/restaure', confirmation: 'magasin');
      expect(r4!.code, 'REGLAGE_RESERVE');
      expect(src.appels, isEmpty, reason: 'aucun refus n\'a atteint la mère');
      final (res, r5) = await s.restaurer(role: 'admin', type: 'magasin', copie: 'a' * 64, cible: '/restaure', confirmation: ' Magasin ');
      expect(r5, isNull);
      expect(res!['cible'], '/restaure');
      expect(src.appels, ['restaurer:magasin:/restaure']);
      expect(m.collection('audit').actives.any((x) => '${x['action']}'.contains('Restauration d\'une copie hors site')), isTrue);
    });
  });

  group('la carte', () {
    Widget monter(Magasin m, String role) => MaterialApp(
        home: ContexteEcran(ecranId: 'm14-sauvegardes', role: role, droit: const Droit(voir: true, editer: true, annuler: true), magasin: m, aller: (_) {}, child: Scaffold(body: SingleChildScrollView(child: CarteHorsSite(role: role)))));

    testWidgets('sans service installé la carte n\'existe pas ; non reçu est DIT ; commandes ABSENTES sans le droit, jamais grisées', (t) async {
      t.view.physicalSize = const Size(1600, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(monter(nouveau(), 'admin'));
      expect(find.byKey(const Key('horssite:carte')), findsNothing);
      final m = nouveau(semer: false);
      HorsSitePoste(m).installer();
      await t.pumpWidget(monter(m, 'soignant'));
      await t.pump();
      expect(find.byKey(const Key('horssite:carte')), findsOneWidget);
      expect(find.textContaining('Réglage non encore reçu'), findsOneWidget);
      expect(find.byKey(const Key('horssite:regler')), findsNothing);
      expect(find.byKey(const Key('horssite:restaurer')), findsNothing);
      expect(find.byKey(const Key('horssite:sans-mere')), findsOneWidget);
    });

    testWidgets('la mère : état, erreur nommée avec son geste, commandes pour l\'administrateur, restauration guidée avec confirmation nommée', (t) async {
      t.view.physicalSize = const Size(1600, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final m = nouveau();
      final src = SourceFausse();
      final s = HorsSitePoste(m, source: src, estMere: () => true)..installer();
      expect(s.definirReglage(role: 'admin', nouveau: const ReglageHorsSite(actif: true, fichiers: ReglageType(destination: 'dossier', dossier: '/mnt/f', copies: 14)), motif: 'Mise en service'), isNull);
      await t.pumpWidget(monter(m, 'admin'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      expect(find.textContaining('ACTIVE'), findsOneWidget);
      expect(find.textContaining('dernière copie le'), findsOneWidget);
      expect(find.textContaining('DOSSIER_INTROUVABLE'), findsWidgets);
      expect(find.textContaining('Brancher le dossier.'), findsOneWidget);
      expect(find.byKey(const Key('horssite:regler')), findsOneWidget);
      expect(find.byKey(const Key('horssite:copier-magasin')), findsOneWidget);
      expect(find.byKey(const Key('horssite:copier-fichiers')), findsOneWidget);
      expect(find.byKey(const Key('horssite:restaurer')), findsOneWidget);
      await t.tap(find.byKey(const Key('horssite:copier-magasin')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      expect(src.appels, contains('lancer:magasin'));
      // la restauration : sans la confirmation nommée, refus affiché ; avec, la mère restaure
      await t.tap(find.byKey(const Key('horssite:restaurer')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byKey(const Key('horssite:cible')), '/restaure-neuf');
      await t.tap(find.byKey(const Key('horssite:lancer-restauration')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      expect(find.textContaining('CONFIRMATION_REQUISE'), findsOneWidget);
      expect(src.appels.where((a) => a.startsWith('restaurer')), isEmpty);
      await t.enterText(find.byKey(const Key('horssite:confirmation')), 'magasin');
      await t.tap(find.byKey(const Key('horssite:lancer-restauration')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 400));
      expect(src.appels, contains('restaurer:magasin:/restaure-neuf'));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('un FILEUL lit le réglage : une note, AUCUNE commande ; un non-administrateur sur la mère : aucune commande', (t) async {
      t.view.physicalSize = const Size(1600, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final m = nouveau();
      HorsSitePoste(m, estFileul: () => true).installer();
      await t.pumpWidget(monter(m, 'admin'));
      await t.pump();
      expect(find.byKey(const Key('horssite:fileul')), findsOneWidget);
      for (final k in ['regler', 'restaurer', 'controler', 'copier-magasin', 'copier-fichiers']) {
        expect(find.byKey(Key('horssite:$k')), findsNothing, reason: k);
      }
      final m2 = nouveau();
      HorsSitePoste(m2, source: SourceFausse(), estMere: () => true).installer();
      await t.pumpWidget(monter(m2, 'soignant'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      for (final k in ['regler', 'restaurer', 'controler', 'copier-magasin', 'copier-fichiers']) {
        expect(find.byKey(Key('horssite:$k')), findsNothing, reason: k);
      }
      await t.pump(const Duration(seconds: 10));
    });
  });
}
