import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show Droit;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/mere/mra_exploitation.dart';
import 'package:sigh_poste/modules/mere/mra_source.dart';
import 'package:sigh_poste/modules/mere/mra_supervision.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

/// Les sept écrans de la console du poste mère (a) : supervision, appareils, conflits, « À traiter », journal des opérations, plages et baux, lots.
/// Les écrans lisent une SOURCE injectable : ici un faux qui répond comme le moteur (mêmes champs, mêmes refus nommés) et enregistre les gestes reçus.

final _t0 = DateTime(2026, 10, 30, 12);

Appareil app(String uuid, String nom, String role,
        {String etat = 'actif', DateTime? contact, int seq = 0, int derive = 0, String? profil, String? fonction}) =>
    Appareil(uuid: uuid, etiquette: nom, role: role, etat: etat, dernierContact: contact, derniereSeq: seq, deriveMs: derive, profil: profil, fonction: fonction);

class SourceFauxMra implements SourceMra {
  final List<String> appels = [];
  Object? panne;
  ErreurMere? refus_;
  EtatMere etatMere = EtatMere(
      epoch: 3, seqMax: 120, repSeq: 100, conflitsOuverts: 2, alertes: const [], derives: const ['u-2'], bloques: const [], reinitOuverte: false, restauration: null,
      appareils: [
        app('u-1', 'Caisse', 'fileul', contact: _t0.subtract(const Duration(minutes: 4)), seq: 118),
        app('u-2', 'Dr Yeni', 'mobile', contact: _t0.subtract(const Duration(hours: 3)), seq: 90, derive: 700000),
        app('u-3', 'Ancien', 'fileul', etat: 'revoque', contact: _t0.subtract(const Duration(days: 9)), seq: 3),
        app('u-4', 'Neuf', 'fileul', seq: 0),
      ]);
  Supervision sante = Supervision(etat: 'alerte', depot: 'sqlite', controles: [
    Controle(nom: 'Sauvegarde', etat: 'alerte', detail: 'Aucune sauvegarde'),
    Controle(nom: 'Relais en ligne', etat: 'inconnu', detail: 'Jamais joint'),
    Controle(nom: 'Base de données', etat: 'ok', detail: 'sqlite'),
  ]);
  List<Conflit> conflits = [
    Conflit(id: 7, collection: 'patients', fiche: 'p1', champ: 'telephone', a: '222', b: '333', etat: 'ouvert', appareil: 'u-1'),
    Conflit(id: 8, collection: 'patients', fiche: 'p9', champ: 'doublon_possible', a: 'p1', b: 'p9', etat: 'ouvert'),
    Conflit(id: 9, collection: 'patients', fiche: 'p5', champ: 'nom', a: 'x', b: 'y', etat: 'tranche', decision: 'b'),
  ];
  List<RefusMra>? refusListe;
  List<OperationMra>? ops;
  PlagesBauxMra? plagesBaux;
  List<LotMra>? lotsListe;
  int retenus = 1;

  void _controle() {
    if (panne != null) throw panne!;
  }

  Future<T> _geste<T>(String nom, T v) async {
    _controle();
    appels.add(nom);
    if (refus_ != null) throw refus_!;
    return v;
  }

  @override
  Future<EtatMere> etat() async {
    _controle();
    return etatMere;
  }

  @override
  Future<Supervision> supervision() async {
    _controle();
    return sante;
  }

  @override
  Future<List<Conflit>> tousLesConflits() async {
    _controle();
    return conflits;
  }

  @override
  Future<void> trancher(int id, String decision) => _geste('trancher $id $decision', null);
  @override
  Future<void> sauvegarderMaintenant() => _geste('sauvegarder', null);
  @override
  Future<String> codeAppareil(String etiquette) => _geste('code-poste $etiquette', 'ABCD2345');
  @override
  Future<({String code, String cle})> codeMobile(String etiquette, {required String profil, String? fonction}) =>
      _geste('code-mobile $etiquette $profil ${fonction ?? ''}'.trim(), (code: 'MOBI2345', cle: 'CLE-CLINIQUE-XYZ'));
  @override
  Future<void> revoquer(String uuid) => _geste('revoquer $uuid', null);
  @override
  Future<void> debloquer(String uuid) => _geste('debloquer $uuid', null);
  @override
  Future<void> renvoyerATous() => _geste('resync', null);
  @override
  Future<int> composerLot({required String uuid, required List<({String collection, String id})> fiches, int? dureeMs}) =>
      _geste('lot $uuid ${fiches.map((f) => '${f.collection}:${f.id}').join(',')} ${dureeMs ?? 'defaut'}', retenus);
  @override
  Future<List<RefusMra>?> refus() async => refusListe;
  @override
  Future<List<OperationMra>?> operations() async => ops;
  @override
  Future<PlagesBauxMra?> plagesEtBaux() async => plagesBaux;
  @override
  Future<List<LotMra>?> lots() async => lotsListe;
}

Future<void> monter(WidgetTester t, Widget ecran, {Droit droit = const Droit(voir: true, editer: true, annuler: false), Magasin? magasin}) async {
  t.view.physicalSize = const Size(1600, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  final naviguees = <String>[];
  addTearDown(() => naviguees.clear());
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ContexteEcran(
              ecranId: 'mere',
              role: 'admin',
              droit: droit,
              magasin: magasin ?? Magasin(const {}, 'POSTE'),
              aller: naviguees.add,
              child: SingleChildScrollView(child: ecran)))));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> fin(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 10));
}

Finder bouton(String libelle) => find.widgetWithText(BoutonSigh, libelle);

String kpi(WidgetTester t, String libelle) => t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).valeur;

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  late SourceFauxMra src;
  setUp(() => src = SourceFauxMra());

  // ============================================================================================================================ SUPERVISION
  group('mere-supervision', () {
    testWidgets('les KPI viennent de l\'état de la mère ; un état inconnu ne rassure pas et se dit', (t) async {
      await monter(t, EcranMraSupervision(source: src, maintenant: () => _t0));
      expect(kpi(t, 'Santé de la mère'), 'ALERTE');
      expect(kpi(t, 'Époque'), '3');
      expect(kpi(t, 'Opérations'), '120');
      expect(kpi(t, 'Retard vers le relais'), '20');
      expect(find.text('Aucune sauvegarde'), findsOneWidget);
      expect(find.text('Jamais joint'), findsOneWidget);
      expect(find.text('Inconnu'), findsOneWidget, reason: 'le contrôle inconnu garde sa pastille neutre');
      expect(find.textContaining('Horloge à vérifier'), findsWidgets);
      await fin(t);
    });

    testWidgets('service muet : « non disponible » et bannière, JAMAIS un zéro', (t) async {
      src.panne = ErreurMere(503, 'indisponible', 'La base ne répond pas.');
      await monter(t, EcranMraSupervision(source: src));
      for (final k in ['Santé de la mère', 'Époque', 'Opérations', 'Retard vers le relais']) {
        expect(kpi(t, k), 'non disponible', reason: k);
      }
      expect(find.textContaining('indisponible'), findsWidgets);
      expect(find.textContaining('Le service de la mère ne répond pas'), findsWidgets);
      await fin(t);
    });

    testWidgets('sans source branchée l\'écran se dessine et dit « non disponible »', (t) async {
      await monter(t, const EcranMraSupervision());
      expect(kpi(t, 'Époque'), 'non disponible');
      expect(find.textContaining('source du moteur non branchée'), findsOneWidget);
      expect(kpi(t, 'Santé de la mère'), 'non disponible');
      await fin(t);
    });

    testWidgets('Sauvegarder maintenant appelle la mère ; un refus s\'affiche avec la cause nommée', (t) async {
      await monter(t, EcranMraSupervision(source: src));
      await toucher(t, bouton('Sauvegarder maintenant'));
      expect(src.appels, ['sauvegarder']);
      expect(find.text('Sauvegarde chiffrée effectuée.'), findsOneWidget);
      src.refus_ = ErreurMere(422, 'disque_plein', 'Plus de place pour la sauvegarde.');
      await toucher(t, bouton('Sauvegarder maintenant'));
      expect(find.textContaining('Plus de place pour la sauvegarde.'), findsOneWidget);
      await fin(t);
    });

    testWidgets('lecture seule : la commande d\'écriture est ABSENTE (pas grisée), les indicateurs restent', (t) async {
      await monter(t, EcranMraSupervision(source: src), droit: const Droit(voir: true, editer: false, annuler: false));
      expect(bouton('Sauvegarder maintenant'), findsNothing);
      expect(bouton('Actualiser'), findsOneWidget);
      expect(kpi(t, 'Époque'), '3');
      await fin(t);
    });

    testWidgets('un appareil bloqué se débloque depuis la supervision', (t) async {
      src.etatMere = EtatMere(
          epoch: 1, seqMax: 1, repSeq: 1, conflitsOuverts: 0, alertes: const [], derives: const [], bloques: const ['u-1'], reinitOuverte: false, restauration: null,
          appareils: [app('u-1', 'Caisse', 'fileul')]);
      await monter(t, EcranMraSupervision(source: src));
      await toucher(t, bouton('Débloquer'));
      expect(src.appels, ['debloquer u-1']);
      await fin(t);
    });
  });

  // ============================================================================================================================ APPAREILS
  group('mere-appareils', () {
    testWidgets('comptes, retard, horloge : une horloge jamais mesurée n\'est PAS déclarée conforme', (t) async {
      await monter(t, EcranMraAppareils(source: src, maintenant: () => _t0));
      expect(kpi(t, 'Appareils actifs'), '3');
      expect(kpi(t, 'Postes fileuls'), '2');
      expect(kpi(t, 'Mobiles'), '1');
      expect(kpi(t, 'Horloge à vérifier'), '1');
      expect(find.text('il y a 4 min'), findsOneWidget);
      expect(find.text('À vérifier (écart 12 min)'), findsOneWidget);
      expect(find.text('Conforme'), findsNWidgets(2), reason: 'Caisse et Ancien ont été mesurés (écart sous 2 min)');
      expect(find.text('inconnue'), findsOneWidget, reason: 'Neuf n\'a jamais contacté la mère');
      expect(find.text('jamais'), findsOneWidget);
      expect(find.text('Révoqué'), findsOneWidget);
      expect(find.text('non disponible'), findsWidgets, reason: 'agent et version ne sont pas tenus par la mère');
      await fin(t);
    });

    testWidgets('E1600 : la colonne « Fonction » dit ce que la mère a fixé ; un mobile d\'avant la fixation est « Non fixée » (la mère refusera ses pièces)', (t) async {
      final s = SourceFauxMra()
        ..etatMere = EtatMere(
            epoch: 3, seqMax: 120, repSeq: 100, conflitsOuverts: 0, alertes: const [], derives: const [], bloques: const [], reinitOuverte: false, restauration: null,
            appareils: [
              app('u-1', 'Caisse', 'fileul', seq: 5),
              app('u-2', 'Sage-femme de garde', 'mobile', seq: 5, profil: 'soignant', fonction: 'sage_femme'),
              app('u-3', 'Accueil de secours', 'mobile', seq: 5, profil: 'reception'),
              app('u-4', 'Ancien mobile', 'mobile', seq: 5),
            ]);
      await monter(t, EcranMraAppareils(source: s, maintenant: () => _t0));
      expect(find.text('Sage-femme'), findsOneWidget);
      expect(find.text('Non fixée'), findsOneWidget);
      expect(find.text('Aucune'), findsNWidgets(2), reason: 'le poste fileul et la réception de secours n\'ont pas de fonction de soignant');
      await fin(t);
    });

    testWidgets('E1600 : un code de mobile exige un profil ; la réception de secours n\'a pas de fonction, un soignant a la sienne, fixée par le code', (t) async {
      await monter(t, EcranMraAppareils(source: src, maintenant: () => _t0));
      await toucher(t, bouton('Appairer un mobile'));
      expect(find.byKey(const Key('kit:champ:fonction')), findsOneWidget, reason: 'profil soignant par défaut : la fonction se choisit ICI');
      expect(find.textContaining('La fonction est fixée par ce code'), findsOneWidget);
      // Profil « Réception de secours » : la fonction disparaît de la saisie.
      await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:profil')), matching: find.byType(InkWell)).first);
      await toucher(t, find.text('Réception de secours').last);
      expect(find.byKey(const Key('kit:champ:fonction')), findsNothing);
      await t.enterText(find.byType(TextField).last, 'Accueil de secours');
      await toucher(t, bouton('Générer le code'));
      expect(src.appels.last, 'code-mobile Accueil de secours reception');
      expect(find.textContaining('Ce code appaire : Réception de secours.'), findsOneWidget);
      await fin(t);
    });

    testWidgets('Révoquer demande confirmation puis appelle la mère ; un appareil révoqué n\'a plus la commande', (t) async {
      await monter(t, EcranMraAppareils(source: src, maintenant: () => _t0));
      expect(find.widgetWithText(BoutonSigh, 'Révoquer'), findsNWidgets(3), reason: '3 appareils non révoqués');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Révoquer').first);
      expect(find.text('Révoquer cet appareil ?'), findsOneWidget);
      expect(src.appels, isEmpty, reason: 'rien n\'est parti avant la confirmation');
      await toucher(t, find.descendant(of: find.byKey(const Key('kit:modale-panneau')), matching: find.widgetWithText(BoutonSigh, 'Révoquer')));
      expect(src.appels.single, startsWith('revoquer u-'));
      await fin(t);
    });

    testWidgets('Appairer un poste : le code à usage unique s\'affiche ; un mobile reçoit aussi la clé', (t) async {
      await monter(t, EcranMraAppareils(source: src, maintenant: () => _t0));
      await toucher(t, bouton('Appairer un poste'));
      await t.enterText(find.byType(TextField).last, 'Réception');
      await toucher(t, bouton('Générer le code'));
      expect(src.appels, ['code-poste Réception']);
      expect(find.byKey(const Key('mra-code')), findsOneWidget);
      expect(find.text('ABCD2345'), findsOneWidget);
      expect(find.byKey(const Key('mra-cle')), findsNothing);
      await toucher(t, bouton('Fermer'));

      await toucher(t, bouton('Appairer un mobile'));
      await t.enterText(find.byType(TextField).last, 'Dr Yeni 2');
      await toucher(t, bouton('Générer le code'));
      // E1600 : le code porte l'affectation (profil, fonction), présélectionnée sur le premier choix.
      expect(src.appels.last, 'code-mobile Dr Yeni 2 soignant medecin');
      expect(find.byKey(const Key('mra-affectation')), findsOneWidget);
      expect(find.textContaining('Ce code appaire : Soignant, Médecin.'), findsOneWidget);
      expect(find.text('CLE-CLINIQUE-XYZ'), findsOneWidget);
      await toucher(t, bouton('Fermer'));
      await fin(t);
    });

    testWidgets('le nom de l\'appareil est obligatoire : aucun code sans nom', (t) async {
      await monter(t, EcranMraAppareils(source: src));
      await toucher(t, bouton('Appairer un poste'));
      await toucher(t, bouton('Générer le code'));
      expect(src.appels, isEmpty);
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await t.tapAt(const Offset(5, 5));
      await t.pump(const Duration(milliseconds: 400));
      await fin(t);
    });

    testWidgets('Renvoyer vers tous : confirmation, appel, accusés par poste', (t) async {
      src.etatMere = EtatMere(
          epoch: 1, seqMax: 5, repSeq: 5, conflitsOuverts: 0, alertes: const [], derives: const [], bloques: const [], reinitOuverte: false, restauration: null,
          marqueResync: '1730000000000', acksResync: const ['u-1', 'u-9'],
          appareils: [app('u-1', 'Caisse', 'fileul', seq: 5), app('u-2', 'Labo', 'fileul', seq: 5), app('u-3', 'Ancien', 'fileul', etat: 'revoque')]);
      await monter(t, EcranMraAppareils(source: src, maintenant: () => _t0));
      expect(find.textContaining('1 accusé(s) sur 2'), findsOneWidget, reason: 'u-9 inconnu et u-3 révoqué ne comptent pas');
      expect(find.textContaining('en attente : Labo'), findsOneWidget);
      await toucher(t, bouton('Renvoyer vers tous'));
      expect(src.appels, isEmpty);
      await toucher(t, find.descendant(of: find.byKey(const Key('kit:modale-panneau')), matching: find.widgetWithText(BoutonSigh, 'Renvoyer')));
      expect(src.appels, ['resync']);
      await fin(t);
    });

    testWidgets('lecture seule : ni appairage, ni renvoi, ni révocation', (t) async {
      await monter(t, EcranMraAppareils(source: src), droit: const Droit(voir: true, editer: false, annuler: false));
      for (final l in ['Appairer un poste', 'Appairer un mobile', 'Renvoyer vers tous', 'Révoquer']) {
        expect(bouton(l), findsNothing, reason: l);
      }
      expect(kpi(t, 'Appareils actifs'), '3');
      await fin(t);
    });
  });

  // ============================================================================================================================ CONFLITS
  group('mere-conflits', () {
    testWidgets('ouverts, doublons ; « tranchés 30 j » non disponible (la mère ne date pas la décision)', (t) async {
      await monter(t, EcranMraConflits(source: src));
      expect(kpi(t, 'Ouverts'), '2');
      expect(kpi(t, 'Doublons possibles'), '1');
      expect(kpi(t, 'Tranchés (30 j)'), 'non disponible');
      expect(find.textContaining('1 tranché(s) au total'), findsOneWidget);
      expect(find.text('222'), findsOneWidget);
      expect(find.text('333'), findsOneWidget);
      expect(find.text('Caisse'), findsOneWidget, reason: 'origine nommée par l\'appareil');
      expect(find.text('non disponible'), findsWidgets, reason: 'origine du doublon non portée par la mère');
      expect(find.textContaining('Version B retenue'), findsOneWidget);
      await fin(t);
    });

    testWidgets('Garder B pose la décision b ; le doublon se classe par « Ce n\'est pas un doublon » (a)', (t) async {
      await monter(t, EcranMraConflits(source: src));
      expect(find.widgetWithText(BoutonSigh, 'Garder A'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Garder B'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ce n’est pas un doublon'));
      expect(src.appels, ['trancher 7 b', 'trancher 8 a']);
      await fin(t);
    });

    testWidgets('un refus de la mère (conflit déjà tranché) s\'affiche avec sa cause nommée', (t) async {
      src.refus_ = ErreurMere(422, 'conflit_inconnu', 'Conflit inexistant ou déjà tranché.');
      await monter(t, EcranMraConflits(source: src));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Garder A'));
      expect(find.textContaining('Conflit inexistant ou déjà tranché.'), findsOneWidget);
      await fin(t);
    });

    testWidgets('« Fusionner à la main » n\'est pas une commande : l\'écran dit pourquoi', (t) async {
      await monter(t, EcranMraConflits(source: src));
      expect(bouton('Fusionner à la main'), findsNothing);
      expect(find.textContaining('Fusionner à la main'), findsOneWidget);
      await fin(t);
    });

    testWidgets('lecture seule : aucune commande d\'arbitrage', (t) async {
      await monter(t, EcranMraConflits(source: src), droit: const Droit(voir: true, editer: false, annuler: false));
      expect(bouton('Garder A'), findsNothing);
      expect(bouton('Garder B'), findsNothing);
      expect(find.text('À arbitrer'), findsWidgets);
      await fin(t);
    });
  });

  // ============================================================================================================================ À TRAITER
  group('mere-a-traiter', () {
    testWidgets('la mère n\'expose pas les refus : « non disponible », aucun zéro', (t) async {
      await monter(t, EcranMraATraiter(source: src));
      for (final k in ['Refus ouverts', 'Appareils concernés', 'Plus ancien']) {
        expect(kpi(t, k), 'non disponible', reason: k);
      }
      expect(find.textContaining('aucune route pour la lire'), findsOneWidget);
      for (final h in ['APPAREIL', 'OPÉRATION', 'CODE', 'MOTIF', 'GESTE DE CORRECTION', 'ÂGE']) {
        expect(find.text(h), findsOneWidget, reason: 'en-tête $h même sans donnée');
      }
      await fin(t);
    });

    testWidgets('avec des refus : cause nommée, geste de correction, âge ; pas de commande Relancer', (t) async {
      src.refusListe = [
        RefusMra(appareil: 'u-1', operation: 'op-1', code: 'numero_hors_plage', motif: 'Le code CNT/1/26 n\'appartient pas à la plage de ce poste.', geste: 'Demander une nouvelle plage', quand: _t0.subtract(const Duration(hours: 2))),
        RefusMra(appareil: 'u-2', operation: 'op-2', code: 'invariant_viole', motif: 'Stock insuffisant pour A1 (RG-03).', geste: 'Corriger la quantité', quand: _t0.subtract(const Duration(minutes: 5))),
        RefusMra(appareil: 'u-1', operation: 'op-3', code: 'droit_refuse', motif: 'Un référentiel ne se modifie qu\'à la console de la mère.', geste: 'Demander la modification', quand: _t0.subtract(const Duration(minutes: 1))),
      ];
      await monter(t, EcranMraATraiter(source: src, maintenant: () => _t0));
      expect(kpi(t, 'Refus ouverts'), '3');
      expect(kpi(t, 'Appareils concernés'), '2');
      expect(kpi(t, 'Plus ancien'), 'il y a 2 h');
      expect(find.text('numero_hors_plage'), findsOneWidget);
      expect(find.text('Demander une nouvelle plage'), findsOneWidget);
      expect(find.text('Caisse'), findsWidgets);
      expect(bouton('Relancer'), findsNothing, reason: 'la mère ne rejoue pas un refus : pas de commande trompeuse');
      expect(find.textContaining('Relancer'), findsOneWidget);
      await fin(t);
    });

    testWidgets('aucun refus : « rien à corriger » et KPI à zéro (la mère l\'a dit)', (t) async {
      src.refusListe = const [];
      await monter(t, EcranMraATraiter(source: src));
      expect(kpi(t, 'Refus ouverts'), '0');
      expect(kpi(t, 'Plus ancien'), 'aucun');
      expect(find.text('Aucune opération refusée.'), findsOneWidget);
      await fin(t);
    });
  });

  // ============================================================================================================================ JOURNAL
  group('mere-journal-operations', () {
    OperationMra op(int s, String a, {DateTime? q}) => OperationMra(seq: s, appareil: a, type: 'modifier', collection: 'patients', fiche: 'p$s', quand: q);

    testWidgets('séquence, époque, appareils à jour et curseurs viennent de l\'état ; le journal est dit non disponible', (t) async {
      await monter(t, EcranMraJournalOperations(source: src));
      expect(kpi(t, 'Séquence courante'), '120');
      expect(kpi(t, 'Époque'), '3');
      expect(kpi(t, 'Appareils à jour'), '0 / 3', reason: '3 appareils non révoqués, aucun n\'a le curseur 120');
      expect(find.textContaining('aucune route pour la lire'), findsOneWidget);
      expect(find.text('118'), findsOneWidget, reason: 'curseur de la Caisse');
      expect(find.text('2'), findsWidgets, reason: 'retard de la Caisse : 120 - 118');
      expect(find.text('Ancien (révoqué)'), findsOneWidget);
      await fin(t);
    });

    testWidgets('opérations : ordre de séquence décroissant, date non disponible quand le moteur ne date pas', (t) async {
      src.ops = [op(1, 'u-1'), op(3, 'u-2', q: DateTime(2026, 10, 30, 9, 5)), op(2, 'u-1')];
      await monter(t, EcranMraJournalOperations(source: src));
      final seqs = t.widgetList<Text>(find.byKey(const Key('kit:tableau-table')).evaluate().isEmpty ? find.text('3') : find.descendant(of: find.byKey(const Key('kit:tableau-table')).first, matching: find.byType(Text))).map((w) => w.data).toList();
      expect(seqs.indexOf('3') < seqs.indexOf('2') && seqs.indexOf('2') < seqs.indexOf('1'), isTrue, reason: '$seqs');
      expect(find.text('30/10/2026 09:05'), findsOneWidget);
      expect(find.text('non disponible'), findsNWidgets(2));
      await fin(t);
    });

    testWidgets('appareils à jour : tous au curseur courant', (t) async {
      src.etatMere = EtatMere(
          epoch: 1, seqMax: 5, repSeq: 5, conflitsOuverts: 0, alertes: const [], derives: const [], bloques: const [], reinitOuverte: false, restauration: null,
          appareils: [app('u-1', 'Caisse', 'fileul', seq: 5), app('u-2', 'Labo', 'fileul', seq: 5)]);
      await monter(t, EcranMraJournalOperations(source: src));
      expect(kpi(t, 'Appareils à jour'), '2 / 2');
      await fin(t);
    });

    testWidgets('Renvoyer vers tous : confirmation puis appel ; absent en lecture seule', (t) async {
      await monter(t, EcranMraJournalOperations(source: src));
      await toucher(t, bouton('Renvoyer vers tous'));
      expect(src.appels, isEmpty);
      await toucher(t, find.descendant(of: find.byKey(const Key('kit:modale-panneau')), matching: find.widgetWithText(BoutonSigh, 'Renvoyer')));
      expect(src.appels, ['resync']);
      await monter(t, EcranMraJournalOperations(source: src), droit: const Droit(voir: true, editer: false, annuler: false));
      expect(bouton('Renvoyer vers tous'), findsNothing);
      await fin(t);
    });
  });

  // ============================================================================================================================ PLAGES ET BAUX
  group('mere-plages-baux', () {
    testWidgets('rien n\'est exposé : tout « non disponible », les gestes absents sont expliqués', (t) async {
      await monter(t, EcranMraPlagesBaux(source: src));
      for (final k in ['Plages actives', 'Numéros PROV- à réconcilier', 'Baux ouverts']) {
        expect(kpi(t, k), 'non disponible', reason: k);
      }
      expect(bouton('Allouer une plage'), findsNothing);
      expect(bouton('Accorder un bail'), findsNothing);
      expect(find.textContaining('Allouer une plage'), findsOneWidget);
      expect(find.textContaining('Accorder un bail'), findsOneWidget);
      await fin(t);
    });

    testWidgets('restants inconnus : « non calculable », jamais un compte supposé', (t) async {
      src.plagesBaux = const PlagesBauxMra(plages: [
        PlageMra(appareil: 'u-1', debut: 101, fin: 150, restants: 12),
        PlageMra(appareil: 'u-2', debut: 151, fin: 200),
      ], baux: [
        BailMra(appareil: 'u-1', article: 'ART-1', restant: 4),
        BailMra(appareil: 'u-2', article: 'ART-2', restant: 0),
      ]);
      await monter(t, EcranMraPlagesBaux(source: src));
      expect(kpi(t, 'Plages actives'), 'non calculable');
      expect(kpi(t, 'Numéros PROV- à réconcilier'), 'non disponible');
      expect(kpi(t, 'Baux ouverts'), '1');
      expect(find.text('101 à 150 (50 numéros)'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      await fin(t);
    });

    testWidgets('données complètes : plages actives, épuisées, PROV- comptés', (t) async {
      src.plagesBaux = const PlagesBauxMra(provisoires: 3, plages: [
        PlageMra(appareil: 'u-1', debut: 101, fin: 150, restants: 12),
        PlageMra(appareil: 'u-2', debut: 151, fin: 200, restants: 0),
      ], baux: [
        BailMra(appareil: 'u-1', article: 'ART-1', restant: 4, alloue: 10, consomme: 6),
      ]);
      await monter(t, EcranMraPlagesBaux(source: src));
      expect(kpi(t, 'Plages actives'), '1');
      expect(kpi(t, 'Numéros PROV- à réconcilier'), '3');
      expect(find.text('Épuisée'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      await fin(t);
    });
  });

  // ============================================================================================================================ LOTS
  group('mere-lots-tournee', () {
    LotMra lot(String a, int n, DateTime expire, {int? saisies}) => LotMra(appareil: a, dossiers: n, depose: _t0.subtract(const Duration(hours: 6)), expire: expire, saisiesNonParties: saisies, tournee: null);

    testWidgets('la liste des lots n\'est pas exposée : « non disponible »', (t) async {
      await monter(t, EcranMraLotsTournee(source: src));
      for (final k in ['Lots actifs', 'Dossiers sur le terrain', 'Saisies à remonter']) {
        expect(kpi(t, k), 'non disponible', reason: k);
      }
      expect(const EcranMraLotsTournee().regle, contains('remonte par le relais'), reason: 'règle de la fiche');
      await fin(t);
    });

    testWidgets('lots actifs et expirés ; saisies inconnues : « non calculable »', (t) async {
      src.lotsListe = [
        lot('u-2', 8, _t0.add(const Duration(hours: 20)), saisies: 2),
        lot('u-2', 5, _t0.subtract(const Duration(hours: 1)), saisies: 1),
        lot('u-2', 4, _t0.add(const Duration(hours: 5)), saisies: 3),
      ];
      await monter(t, EcranMraLotsTournee(source: src, maintenant: () => _t0));
      expect(kpi(t, 'Lots actifs'), '2');
      expect(kpi(t, 'Dossiers sur le terrain'), '12', reason: 'le lot expiré ne compte pas');
      expect(kpi(t, 'Saisies à remonter'), '5');
      expect(find.text('Expiré'), findsOneWidget);
      src.lotsListe = [lot('u-2', 8, _t0.add(const Duration(hours: 20)))];
      await t.pump(const Duration(seconds: 6));
      expect(kpi(t, 'Saisies à remonter'), 'non calculable');
      await fin(t);
    });

    testWidgets('Composer un lot : sans mobile appairé, refus nommé et rien n\'est envoyé', (t) async {
      src.etatMere = EtatMere(
          epoch: 1, seqMax: 1, repSeq: 1, conflitsOuverts: 0, alertes: const [], derives: const [], bloques: const [], reinitOuverte: false, restauration: null,
          appareils: [app('u-1', 'Caisse', 'fileul')]);
      await monter(t, EcranMraLotsTournee(source: src));
      await toucher(t, bouton('Composer un lot'));
      expect(find.textContaining('Aucun mobile appairé'), findsOneWidget);
      expect(src.appels, isEmpty);
      await fin(t);
    });

    testWidgets('Composer un lot : mobile, durée, dossiers choisis ; la mère dit combien elle en retient', (t) async {
      src.retenus = 1;
      final m = Magasin({
        'audit': const <Fiche>[],
        'patients': [
          {'id': 'p1', 'statut': 'actif', 'code': 'CNT/1/26', 'nom': 'AKPO', 'prenom': 'Rose'},
          {'id': 'p2', 'statut': 'actif', 'code': 'CNT/2/26', 'nom': 'BIO', 'prenom': 'Paul'},
        ],
      }, 'POSTE');
      await monter(t, EcranMraLotsTournee(source: src), magasin: m);
      await toucher(t, bouton('Composer un lot'));
      expect(find.textContaining('Dossiers du jour'), findsOneWidget);
      await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:dossiers')), matching: find.byType(InkWell)).first);
      await toucher(t, find.textContaining('AKPO').last);
      await toucher(t, find.textContaining('BIO').last);
      await t.tapAt(const Offset(5, 5));
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:heures')), matching: find.byType(TextField)), '24');
      await toucher(t, bouton('Déposer le lot'));
      expect(src.appels, hasLength(1), reason: '${src.appels}');
      expect(src.appels.single, 'lot u-2 patients:p1,patients:p2 86400000');
      expect(find.textContaining('1 dossier(s) retenu(s) sur 2'), findsOneWidget, reason: 'l\'écart est nommé');
      await fin(t);
    });

    testWidgets('lecture seule : la commande Composer un lot est absente', (t) async {
      await monter(t, EcranMraLotsTournee(source: src), droit: const Droit(voir: true, editer: false, annuler: false));
      expect(bouton('Composer un lot'), findsNothing);
      await fin(t);
    });
  });

  // ============================================================================================================================ COQUE ET ADAPTATEUR
  group('adaptateur du service et coque', () {
    final donnees = DonneesNavigation.depuisDossier();
    final appels = <String>[];

    ClientMere client() => ClientMere(
        base: Uri.parse('http://mere.test'),
        secretAdmin: 's',
        client: MockClient((req) async {
          appels.add('${req.method} ${req.url.path}');
          switch (req.url.path) {
            case '/admin/etat':
              return http.Response(
                  jsonEncode({
                    'epoch': 2,
                    'seq_max': 40,
                    'rep_seq': 38,
                    'conflits_ouverts': 1,
                    'alertes': [],
                    'derives': [],
                    'bloques': [],
                    'resync': {'marque': null, 'acks': []},
                    'appareils': [
                      {'uuid': 'u-1', 'etiquette': 'Caisse', 'role': 'fileul', 'etat': 'actif', 'dernier_contact': 1, 'dernier_seq': 40, 'derive_ms': 0}
                    ],
                  }),
                  200);
            case '/admin/supervision':
              return http.Response(jsonEncode({'etat': 'ok', 'depot': 'sqlite', 'controles': []}), 200);
            case '/admin/conflits':
              return http.Response(jsonEncode([]), 200);
            case '/admin/lot':
              return http.Response(jsonEncode({'fiches': 2}), 200);
          }
          return http.Response('{}', 404);
        }));

    Future<void> ouvrirEcran(WidgetTester t, String id, {String role = 'admin'}) async {
      t.view.physicalSize = const Size(1600, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(SighPoste(
          key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.mere, role: role), client: client(), ecranInitial: id));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    for (final id in ['mere-supervision', 'mere-appareils', 'mere-conflits', 'mere-a-traiter', 'mere-journal-operations', 'mere-plages-baux', 'mere-lots-tournee']) {
      testWidgets('la coque sert $id (mode mère) avec le service branché', (t) async {
        await ouvrirEcran(t, id);
        expect(find.byKey(const Key('titre-page')), findsOneWidget);
        expect(find.byKey(const Key('ecran-a-porter')), findsNothing, reason: '$id est porté');
        await fin(t);
      });
    }

    testWidgets('la lecture de l\'état passe par /admin/etat : époque et retard vraiment lus du service', (t) async {
      appels.clear();
      await ouvrirEcran(t, 'mere-supervision');
      expect(appels, contains('GET /admin/etat'));
      expect(kpi(t, 'Époque'), '2');
      expect(kpi(t, 'Retard vers le relais'), '2');
      expect(kpi(t, 'Santé de la mère'), 'OK');
      await fin(t);
    });

    testWidgets('un rôle sans accès au poste mère n\'ouvre pas ces écrans', (t) async {
      await ouvrirEcran(t, 'mere-lots-tournee', role: 'caissier');
      expect(find.text('Lots de tournée (mobiles)'), findsNothing);
      expect(find.text('Lots actifs'), findsNothing);
      await fin(t);
    });

    test('l\'adaptateur rend null (« non disponible ») pour ce que le moteur n\'expose pas, pas une liste vide', () async {
      final s = SourceMraClient(client());
      expect(await s.refus(), isNull);
      expect(await s.operations(), isNull);
      expect(await s.plagesEtBaux(), isNull);
      expect(await s.lots(), isNull);
    });

    test('le dépôt d\'un lot appelle POST /admin/lot et rend le nombre de fiches retenues', () async {
      appels.clear();
      final n = await SourceMraClient(client()).composerLot(uuid: 'u-2', fiches: [(collection: 'patients', id: 'p1'), (collection: 'patients', id: 'p2')]);
      expect(n, 2);
      expect(appels, ['POST /admin/lot']);
    });
  });
}
