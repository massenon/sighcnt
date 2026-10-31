import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/mere/mrc_commun.dart';
import 'package:sigh_poste/modules/mere/mrc_plateforme.dart';
import 'package:sigh_poste/modules/mere/mrc_sources.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'aide_polices.dart';
import 'm14_aide.dart' show donneesLectureSeule;

/// Lot MERE c : les huit écrans de la console du poste mère, lus par une interface INJECTABLE (aucun réseau, aucun service Windows). Chaque test peut
/// échouer : une valeur sans source doit s'afficher « non disponible », un refus doit se nommer, une confirmation nommée doit être exacte, un fichier
/// fautif ne doit rien écrire.
typedef M = Map<String, Object?>;

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 31, 10);

EtatMere etat({List<M>? appareils, int seq = 100, bool reinit = false}) => EtatMere.depuis({
      'epoch': 3,
      'seq_max': seq,
      'rep_seq': seq,
      'conflits_ouverts': 0,
      'reinit_ouverte': reinit,
      'derives': [],
      'bloques': [],
      'alertes': [],
      'appareils': appareils ?? [],
    });

M appareil(String uuid, String nom, {int? contact, String role = 'fileul', String etat = 'actif'}) => {
      'uuid': uuid,
      'etiquette': nom,
      'role': role,
      'etat': etat,
      'dernier_contact': contact,
      'dernier_seq': 100,
      'derive_ms': 0,
    };

/// Source fausse : tout ce qu'elle fournit est scripté, tout appel est enregistré.
class FauxMrc extends MrcSources {
  FauxMrc({EtatMere? etatV, Supervision? santeV}) : _etat = etatV, _sante = santeV;
  EtatMere? _etat;
  Supervision? _sante;
  DateTime horloge = auj;
  bool enMarche = true;
  final List<String> appels = [];
  MrcResultat? refusArret;
  MrcValeur<String> ecoute = const MrcValeur.de('127.0.0.1 (boucle locale)');
  bool projection = false;
  List<String> adresses = const [];
  Set<String> injoignables = {};
  MrcValeur<int> schema = const MrcValeur.indisponible('schéma de la mère inconnu');
  Map<String, int> schemas = {};
  Map<String, bool?> constatsV = {};
  Object? panneLecture;

  void poser({EtatMere? etatV, Supervision? santeV}) {
    _etat = etatV ?? _etat;
    _sante = santeV ?? _sante;
  }

  @override
  DateTime maintenant() => horloge;

  @override
  Future<EtatMere> etat() async {
    appels.add('etat');
    if (panneLecture != null) throw panneLecture!;
    return _etat!;
  }

  @override
  Future<Supervision> supervision() async {
    appels.add('supervision');
    if (panneLecture != null) throw panneLecture!;
    return _sante!;
  }

  @override
  Future<ParametresPoste?> parametres() async => const ParametresPoste(uuidPoste: 'uuid-poste-1', mode: ModePoste.mere, nomPoste: 'Serveur', relais: 'https://relais.exemple.bj');

  @override
  MrcValeur<bool> serviceEnMarche() => MrcValeur.de(enMarche);
  @override
  MrcValeur<int> port() => const MrcValeur.de(8099);
  @override
  MrcValeur<String> adresseAdmin() => const MrcValeur.de('http://127.0.0.1:8099');
  @override
  MrcValeur<String> adresseEcoute() => ecoute;

  @override
  Future<MrcResultat> arreter() async {
    appels.add('arreter');
    if (refusArret != null) return refusArret!;
    enMarche = false;
    return const MrcResultat.ok('Service arrêté proprement.');
  }

  @override
  Future<MrcResultat> redemarrer() async {
    appels.add('redemarrer');
    enMarche = true;
    return const MrcResultat.ok('Service redémarré.');
  }

  @override
  Future<MrcResultat> desactiver(String secretMere) async {
    appels.add('desactiver:$secretMere');
    return const MrcResultat.ok('Mode mère désactivé.');
  }

  @override
  MrcValeur<bool> projectionDisponible() => projection ? const MrcValeur.de(true) : super.projectionDisponible();
  @override
  Future<MrcResultat> verifierParite() async {
    appels.add('parite');
    return projection ? const MrcResultat.ok('123 collections, 0 écart') : super.verifierParite();
  }

  @override
  Future<MrcResultat> reconstruireTables() async {
    appels.add('reconstruire');
    return projection ? const MrcResultat.ok('Tables reconstruites.') : super.reconstruireTables();
  }

  @override
  Future<List<String>> adressesLocales() async => adresses;
  @override
  Future<MrcResultat> testerAcces(String hote, int port) async {
    appels.add('test:$hote:$port');
    return injoignables.contains(hote) ? MrcResultat.refus('$hote:$port ne répond pas') : MrcResultat.ok('$hote:$port répond');
  }

  @override
  Future<MrcResultat> executerTache(String code) async {
    appels.add('tache:$code');
    return super.executerTache(code);
  }

  @override
  MrcValeur<int> schemaMere() => schema;
  @override
  MrcValeur<int> schemaAppareil(String uuid) => schemas.containsKey(uuid) ? MrcValeur.de(schemas[uuid]!) : super.schemaAppareil(uuid);

  @override
  Future<Map<String, bool?>> constats(ConfigPoste cfg, EtatMere? etat) async => {for (final e in mrcEtapes) e.id: constatsV[e.id]};
  @override
  MrcResultat consigner(String etape, {String? choix, required String par}) {
    appels.add('consigner:$etape:$choix:$par');
    constatsV[etape] = true;
    return MrcResultat.ok('Étape consignée par $par.');
  }
}

Supervision sante(List<Controle> c, {String depot = 'sqlite'}) => Supervision(etat: 'ok', controles: c, depot: depot);
Controle ctl(String nom, String etat, [String detail = '']) => Controle(nom: nom, etat: etat, detail: detail);

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');

Future<void> ouvrir(WidgetTester t, String ecran, FauxMrc faux, {Magasin? magasin, String role = 'admin', DonneesNavigation? nav}) async {
  Mrc.fabrique = (_) => faux;
  addTearDown(() => Mrc.fabrique = null);
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: nav ?? donnees,
      config: ConfigPoste(mode: ModePoste.mere, role: role, nomPoste: 'Serveur'),
      client: ClientMere(base: Uri.parse('http://127.0.0.1:1'), secretAdmin: 's'),
      ecranInitial: ecran,
      magasin: magasin ?? jeu(),
      horloge: () => auj));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> attendre(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await attendre(t);
}

Finder bouton(String libelle) => find.widgetWithText(BoutonSigh, libelle);

String kpi(WidgetTester t, String libelle) =>
    t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).valeur;
String? indice(WidgetTester t, String libelle) =>
    t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).indice;

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
      ToastsSigh.viderPourTests();
    });

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('mere-service', () {
    cas('les quatre indicateurs viennent des sources ; le démarrage automatique est « non disponible » avec son motif', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([ctl('Base de données', 'ok', 'SQLite répond en 3 ms.')]));
      await ouvrir(t, 'mere-service', f);
      expect(kpi(t, 'Mode de ce poste'), 'Poste mère');
      expect(kpi(t, 'Service'), 'En marche');
      expect(kpi(t, 'Port'), '8099');
      expect(kpi(t, 'Démarrage automatique'), 'non disponible');
      expect(indice(t, 'Démarrage automatique'), contains('service Windows'));
      // Le tableau de configuration porte des valeurs sourcées, pas des suppositions.
      expect(find.text('uuid-poste-1'), findsOneWidget);
      expect(find.text('https://relais.exemple.bj'), findsOneWidget);
      expect(find.text('SQLite'), findsOneWidget);
    });

    cas('service démarré mais muet : « Démarré, ne répond pas », avec la cause dans le bandeau', (t) async {
      final f = FauxMrc()..panneLecture = StateError('connexion refusée');
      await ouvrir(t, 'mere-service', f);
      expect(kpi(t, 'Service'), 'Démarré, ne répond pas');
      expect(find.textContaining('connexion refusée'), findsWidgets);
    });

    cas('arrêter proprement : confirmation, appel, puis service « Arrêté » à la relecture', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      await ouvrir(t, 'mere-service', f);
      await toucher(t, bouton('Arrêter proprement'));
      expect(find.textContaining('Les postes et les mobiles ne pourront plus synchroniser'), findsOneWidget);
      expect(f.appels.contains('arreter'), isFalse, reason: 'rien ne part avant la confirmation');
      await toucher(t, bouton('Arrêter proprement').last);
      expect(f.appels.where((a) => a == 'arreter').length, 1);
      expect(kpi(t, 'Service'), 'Arrêté');
      expect(find.text('Service arrêté proprement.'), findsOneWidget);
    });

    cas('un refus du service se NOMME à l’écran', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]))..refusArret = const MrcResultat.refus('le service est déjà arrêté');
      await ouvrir(t, 'mere-service', f);
      await toucher(t, bouton('Arrêter proprement'));
      await toucher(t, bouton('Arrêter proprement').last);
      expect(find.textContaining('Refusé : le service est déjà arrêté'), findsOneWidget);
    });

    cas('désactiver le mode mère : bouton fermé tant que la phrase n’est pas EXACTE, secret transmis tel quel', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      await ouvrir(t, 'mere-service', f);
      await toucher(t, bouton('Désactiver le mode mère'));
      final confirmer = bouton('Désactiver le mode mère').last;
      expect(t.widget<BoutonSigh>(confirmer).onPressed, isNull);
      await t.enterText(find.byKey(const Key('mrc-phrase')), 'désactiver le mode');
      await t.pump();
      expect(t.widget<BoutonSigh>(confirmer).onPressed, isNull, reason: 'une phrase approchée ne suffit pas');
      await t.enterText(find.byKey(const Key('mrc-phrase')), 'désactiver le mode mère');
      await t.enterText(find.byKey(const Key('mrc-secret')), 'S3cret-relais');
      await t.pump();
      expect(t.widget<BoutonSigh>(confirmer).onPressed, isNotNull);
      await toucher(t, confirmer);
      expect(f.appels, contains('desactiver:S3cret-relais'));
    });

    cas('en lecture seule, les trois commandes d’écriture sont ABSENTES (pas grisées) ; la lecture reste', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      await ouvrir(t, 'mere-service', f, role: 'da', nav: donneesLectureSeule('da', 'mere-service'));
      expect(kpi(t, 'Mode de ce poste'), 'Poste mère');
      for (final b in ['Arrêter proprement', 'Redémarrer', 'Désactiver le mode mère']) {
        expect(bouton(b), findsNothing, reason: b);
      }
      expect(bouton('Actualiser'), findsOneWidget);
    });

    cas('un rôle qui n’administre pas la mère ne lit RIEN du service (RG-13)', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      Mrc.fabrique = (_) => f;
      addTearDown(() => Mrc.fabrique = null);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ContexteEcran(
                  ecranId: 'mere-service',
                  role: 'caissier',
                  droit: const Droit(voir: true, editer: true, annuler: true),
                  magasin: jeu(),
                  aller: (_) {},
                  child: const EcranMereService(config: ConfigPoste(mode: ModePoste.mere))))));
      await attendre(t);
      expect(find.textContaining('réservée à l’administrateur système'), findsOneWidget);
      expect(find.byType(BoutonSigh), findsNothing, reason: 'une commande interdite est ABSENTE');
      expect(f.appels, isEmpty, reason: 'aucune lecture du service pour ce rôle');
    });
  });

  group('mere-base', () {
    cas('moteur lu à la supervision ; taille, schéma et migrations « non disponibles » ; en-têtes toujours visibles', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([ctl('Base de données', 'ok', 'SQLite répond en 3 ms.')]));
      await ouvrir(t, 'mere-base', f);
      expect(kpi(t, 'Moteur'), 'SQLite');
      expect(indice(t, 'Moteur'), 'SQLite répond en 3 ms.');
      expect(kpi(t, 'Taille'), 'non disponible');
      expect(kpi(t, 'Schéma'), 'non disponible');
      expect(kpi(t, 'Parité'), 'non vérifiée');
      for (final h in ['VERSION', 'DATE', 'RÉSUMÉ']) {
        expect(find.text(h), findsOneWidget, reason: 'tableau vide, colonne $h');
      }
      expect(find.textContaining('Non disponible : le moteur ne tient pas de registre de migrations'), findsOneWidget);
    });

    cas('la parité sans projection est REFUSÉE avec sa cause ; avec une projection elle est dite', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      await ouvrir(t, 'mere-base', f);
      await toucher(t, bouton('Vérifier la parité'));
      expect(find.textContaining('ne tient pas de projection relationnelle'), findsWidgets);
      expect(kpi(t, 'Parité'), 'non vérifiée');
      ToastsSigh.viderPourTests();
      f.projection = true;
      await toucher(t, bouton('Vérifier la parité'));
      expect(kpi(t, 'Parité'), 'vérifiée');
      expect(find.textContaining('123 collections, 0 écart'), findsWidgets);
    });

    cas('reconstruire les tables : sans projection, refus immédiat (aucune phrase demandée pour rien) ; avec, confirmation nommée', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      await ouvrir(t, 'mere-base', f);
      await toucher(t, bouton('Reconstruire les tables'));
      expect(find.byKey(const Key('mrc-phrase')), findsNothing);
      expect(f.appels, contains('reconstruire'));
      ToastsSigh.viderPourTests();
      f.appels.clear();
      f.projection = true;
      await toucher(t, bouton('Reconstruire les tables'));
      expect(find.byKey(const Key('mrc-phrase')), findsOneWidget);
      expect(f.appels, isNot(contains('reconstruire')), reason: 'rien avant la confirmation');
      await t.enterText(find.byKey(const Key('mrc-phrase')), 'RECONSTRUIRE LES TABLES');
      await t.pump();
      await toucher(t, bouton('Reconstruire').last);
      expect(f.appels, contains('reconstruire'));
    });
  });

  group('mere-reseau', () {
    cas('postes joignables d’après le dernier contact ; l’écoute sur la boucle locale est dite en danger', (t) async {
      final ms = auj.millisecondsSinceEpoch;
      final f = FauxMrc(
          etatV: etat(appareils: [
            appareil('u1', 'Caisse', contact: ms - 5 * 60000),
            appareil('u2', 'Réception', contact: ms - 50 * 60000),
            appareil('u3', 'Ancien', contact: ms, etat: 'revoque'),
            appareil('m1', 'Dr Yeni', contact: ms, role: 'mobile'),
          ]),
          santeV: sante([]))
        ..adresses = ['192.168.1.20'];
      await ouvrir(t, 'mere-reseau', f);
      expect(kpi(t, 'Postes joignables'), '1 sur 2', reason: 'ni le poste révoqué ni le mobile ne comptent');
      expect(indice(t, 'Postes joignables'), contains('pas un test réseau'));
      expect(kpi(t, 'Adresse locale'), '192.168.1.20');
      expect(kpi(t, 'Port'), '8099');
      expect(find.textContaining('n’écoute que sur 127.0.0.1 (boucle locale)'), findsOneWidget);
      expect(find.textContaining('localport=8099'), findsOneWidget);
    });

    cas('aucune interface : « non disponible », pas une adresse inventée', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      await ouvrir(t, 'mere-reseau', f);
      expect(kpi(t, 'Adresse locale'), 'non disponible');
      expect(indice(t, 'Adresse locale'), contains('aucune interface'));
    });

    cas('« Tester depuis un poste » teste chaque adresse et dit lesquelles ne répondent pas', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]))
        ..adresses = ['192.168.1.20']
        ..injoignables = {'192.168.1.20'};
      await ouvrir(t, 'mere-reseau', f);
      await toucher(t, bouton('Tester depuis un poste'));
      expect(f.appels.where((a) => a.startsWith('test:')), ['test:127.0.0.1:8099', 'test:192.168.1.20:8099']);
      expect(find.textContaining('Joignable : 127.0.0.1:8099 répond'), findsOneWidget);
      expect(find.textContaining('Injoignable : 192.168.1.20:8099 ne répond pas'), findsOneWidget);
      expect(find.textContaining('lancé depuis CE serveur'), findsOneWidget);
    });

    cas('renouveler le certificat : refusé, la cause est nommée (pas de TLS)', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      await ouvrir(t, 'mere-reseau', f);
      await toucher(t, bouton('Renouveler le certificat'));
      expect(find.textContaining('Refusé : aucun certificat'), findsOneWidget);
    });
  });

  group('mere-planificateur', () {
    Magasin avecTaches({int executions = 0, bool taches = true}) {
      final m = jeu();
      if (taches) {
        m.collection('tachesPlanifiees').remplacerContenu([
          {'id': 'stock_seuils', 'code': 'stock_seuils', 'libelle': 'Articles sous leur seuil d’alerte', 'frequence_min': 30, 'actif': true, 'derniere_le': '2026-10-31 09:50:00', 'dernier_statut': 'ok', 'duree_ms': 38, 'alertes': 51},
          {'id': 'sauvegarde_nocturne', 'code': 'sauvegarde_nocturne', 'libelle': 'Sauvegarde du magasin', 'frequence_min': 1440, 'actif': true, 'derniere_le': '2026-10-30 23:47:00', 'dernier_statut': 'erreur', 'dernier_message': 'disque plein', 'duree_ms': 218, 'alertes': 0},
        ]);
      } else {
        m.collection('tachesPlanifiees').remplacerContenu(const []);
      }
      m.collection('executionsTaches').remplacerContenu([
        for (var i = executions; i > 0; i--) {'id': i, 'code': 'stock_seuils', 'debut': '2026-10-31 09:50:00', 'statut': 'ok', 'origine': 'cron', 'alertes': 0}
      ]);
      return m;
    }

    cas('les compteurs viennent du registre : actives, en erreur, alertes de la dernière passe', (t) async {
      final f = FauxMrc();
      await ouvrir(t, 'mere-planificateur', f, magasin: avecTaches());
      expect(kpi(t, 'Tâches actives'), '2');
      expect(kpi(t, 'En erreur'), '1');
      expect(kpi(t, 'Alertes ouvertes'), '51');
      expect(find.text('Articles sous leur seuil d’alerte'), findsOneWidget);
      expect(find.textContaining('disque plein'), findsOneWidget);
    });

    cas('sans registre, les compteurs sont « non disponibles » : zéro tâche en erreur ne veut pas dire « aucune erreur »', (t) async {
      final f = FauxMrc();
      await ouvrir(t, 'mere-planificateur', f, magasin: avecTaches(taches: false));
      expect(kpi(t, 'Tâches actives'), 'non disponible');
      expect(kpi(t, 'En erreur'), 'non disponible');
      expect(indice(t, 'En erreur'), contains('aucun registre'));
      for (final h in ['TÂCHE', 'FRÉQUENCE', 'DERNIÈRE EXÉCUTION', 'RÉSULTAT', 'ALERTES']) {
        expect(find.text(h), findsWidgets, reason: h);
      }
    });

    cas('« Exécuter » appelle la source et le refus du moteur est nommé : rien n’est exécuté', (t) async {
      final f = FauxMrc();
      await ouvrir(t, 'mere-planificateur', f, magasin: avecTaches());
      await toucher(t, bouton('Exécuter').first);
      expect(f.appels.where((a) => a.startsWith('tache:')).length, 1);
      expect(find.textContaining('Refusé : ce poste n’a pas de planificateur'), findsOneWidget);
    });

    cas('le registre des exécutions est borné à 500', (t) async {
      final f = FauxMrc();
      await ouvrir(t, 'mere-planificateur', f, magasin: avecTaches(executions: 620));
      expect(find.textContaining('Dernières exécutions (500 gardées'), findsOneWidget);
    });
  });

  group('mere-notifications', () {
    final controles = [
      ctl('Base de données', 'ok', 'SQLite répond.'),
      ctl('Sauvegarde', 'alerte', 'Aucune sauvegarde n’a jamais été faite.'),
      ctl('Poste « Caisse »', 'attention', 'Vu il y a 40 min.'),
      ctl('Relais en ligne', 'inconnu', 'Aucun relais configuré.'),
    ];

    cas('alertes = contrôles non OK : ouvertes (alerte + attention), critiques, « inconnu » listé sans être compté', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante(controles));
      await ouvrir(t, 'mere-notifications', f);
      expect(kpi(t, 'Ouvertes'), '2');
      expect(kpi(t, 'Critiques'), '1');
      expect(kpi(t, 'Résolues (7 j)'), 'non disponible');
      expect(find.textContaining('Sauvegarde : Aucune sauvegarde'), findsOneWidget);
      expect(find.text('Critique'), findsOneWidget);
      expect(find.text('À surveiller'), findsOneWidget);
      expect(find.text('Inconnue'), findsOneWidget);
      expect(find.text('Admin, DAF'), findsNWidgets(3), reason: 'destinataires = rôles auxquels le manifeste ouvre l’écran (RG-13)');
      expect(find.text('non disponible'), findsWidgets, reason: 'le moteur ne date pas l’ouverture');
    });

    cas('une alerte se résout d’elle-même quand sa cause cesse', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante(controles));
      await ouvrir(t, 'mere-notifications', f);
      expect(kpi(t, 'Ouvertes'), '2');
      f.poser(santeV: sante([ctl('Base de données', 'ok'), ctl('Sauvegarde', 'ok', 'Dernière sauvegarde il y a 2 h.')]));
      await toucher(t, bouton('Actualiser'));
      expect(kpi(t, 'Ouvertes'), '0');
      expect(find.textContaining('Aucune alerte ouverte'), findsOneWidget);
    });

    cas('service muet : compteurs « non disponibles » et non zéro', (t) async {
      final f = FauxMrc()..panneLecture = StateError('hors service');
      await ouvrir(t, 'mere-notifications', f);
      expect(kpi(t, 'Ouvertes'), 'non disponible');
      expect(find.textContaining('hors service'), findsWidgets);
    });
  });

  group('mere-mise-en-service', () {
    cas('cinq étapes numérotées ; l’état se lit sur les constats ; « non vérifié » ne compte pas comme fait', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]))
        ..constatsV = {'identite': null, 'administrateur': true, 'jeu_depart': false, 'activation': true, 'appairage': false};
      await ouvrir(t, 'mere-mise-en-service', f);
      expect(kpi(t, 'Étapes faites'), '2 sur 5');
      for (final e in mrcEtapes) {
        expect(find.text(e.libelle), findsOneWidget);
      }
      expect(find.text('Non vérifié'), findsOneWidget);
      expect(find.text('Fait'), findsNWidgets(2));
      expect(find.text('À faire'), findsNWidgets(2));
    });

    cas('une étape bloquée refuse de s’ouvrir en nommant son prérequis', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]))..constatsV = {'activation': false, 'appairage': false};
      await ouvrir(t, 'mere-mise-en-service', f);
      expect(find.text('Bloquée'), findsOneWidget);
      await toucher(t, bouton('Ouvrir').last);
      expect(find.textContaining('Étape 5 « Premier appairage » bloquée'), findsOneWidget);
      expect(find.textContaining('étape 4 « Activation du mode mère »'), findsOneWidget);
    });

    cas('« essentiels seulement » exige la phrase EXACTE ; le choix est consigné au nom de l’agent', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]))..constatsV = {'jeu_depart': false};
      await ouvrir(t, 'mere-mise-en-service', f);
      await toucher(t, bouton('Ouvrir').at(2));
      expect(find.textContaining('Étape 3 : Jeu de départ'), findsOneWidget);
      await toucher(t, bouton('Consigner : essentiels seulement'));
      final ok = bouton('Consigner').last;
      expect(t.widget<BoutonSigh>(ok).onPressed, isNull);
      await t.enterText(find.byKey(const Key('mrc-phrase')), 'vider');
      await t.pump();
      expect(t.widget<BoutonSigh>(ok).onPressed, isNull);
      expect(f.appels.where((a) => a.startsWith('consigner')), isEmpty);
      await t.enterText(find.byKey(const Key('mrc-phrase')), 'vider l’activité');
      await t.pump();
      await toucher(t, ok);
      final consigne = f.appels.where((a) => a.startsWith('consigner')).single;
      expect(consigne, startsWith('consigner:jeu_depart:essentiels:'));
      expect(consigne.split(':').last, isNotEmpty, reason: 'aucune action anonyme (RG-12)');
      expect(kpi(t, 'Étapes faites'), '1 sur 5');
    });
  });

  group('mere-mises-a-jour', () {
    cas('compatibilité de schéma : à jour, refusé NOMMÉ, inconnu ; les compteurs suivent', (t) async {
      final f = FauxMrc(etatV: etat(appareils: [appareil('u1', 'Caisse'), appareil('u2', 'Réception'), appareil('u3', 'Labo'), appareil('u4', 'Révoqué', etat: 'revoque')]), santeV: sante([]))
        ..schema = const MrcValeur.de(68)
        ..schemas = {'u1': 68, 'u2': 66, 'u4': 10};
      await ouvrir(t, 'mere-mises-a-jour', f);
      expect(kpi(t, 'Schéma'), '68');
      expect(kpi(t, 'Postes à jour'), '1');
      expect(kpi(t, 'Postes refusés'), '1');
      expect(find.text('À jour'), findsOneWidget);
      expect(find.text('Refusé : schéma trop ancien'), findsOneWidget);
      expect(find.text('Inconnu'), findsOneWidget, reason: 'Labo : schéma non enregistré, ne rassure pas');
      expect(find.textContaining('schema_incompatible : « Réception » est au schéma 66, la mère au schéma 68'), findsOneWidget);
      expect(find.text('Révoqué'), findsNothing, reason: 'un appareil révoqué ne figure pas aux versions');
    });

    cas('sans version connue, rien n’est compté : « non disponible », jamais « 0 refusé »', (t) async {
      final f = FauxMrc(etatV: etat(appareils: [appareil('u1', 'Caisse')]), santeV: sante([]));
      await ouvrir(t, 'mere-mises-a-jour', f);
      expect(kpi(t, 'Postes refusés'), 'non disponible');
      expect(kpi(t, 'Version de la mère'), 'non disponible');
      expect(find.textContaining('ne refuse encore aucun poste trop ancien'), findsOneWidget);
    });

    cas('« Planifier le déploiement » est refusé en nommant ce qui manque', (t) async {
      final f = FauxMrc(etatV: etat(), santeV: sante([]));
      await ouvrir(t, 'mere-mises-a-jour', f);
      await toucher(t, bouton('Planifier le déploiement'));
      expect(find.textContaining('Refusé : aucun mécanisme de distribution'), findsOneWidget);
    });
  });

  group('mere-import (source réelle sur le magasin du poste)', () {
    const entete = 'reference;designation;quantite;pr_unitaire;categorie\n';
    late Map<String, String> fichiers;

    SourceFichiers source(Magasin m) => SourceFichiers(m, fichiers);

    setUp(() => fichiers = {});

    Future<void> ouvrirImport(WidgetTester t, Magasin m) async {
      Mrc.fabrique = (mg) => SourceFichiers(mg, fichiers);
      addTearDown(() => Mrc.fabrique = null);
      t.view.physicalSize = const Size(1600, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(SighPoste(
          key: UniqueKey(),
          donnees: donnees,
          config: const ConfigPoste(mode: ModePoste.mere, role: 'admin', nomPoste: 'Serveur'),
          client: ClientMere(base: Uri.parse('http://127.0.0.1:1'), secretAdmin: 's'),
          ecranInitial: 'mere-import',
          magasin: m,
          horloge: () => auj));
      await attendre(t);
    }

    Future<void> analyser(WidgetTester t, String chemin) async {
      await toucher(t, bouton('Importer un fichier'));
      await t.enterText(find.byKey(const Key('mrc-chemin')), chemin);
      await t.pump();
      await toucher(t, bouton('Analyser'));
    }

    cas('en lecture seule, « Importer un fichier » est ABSENT', (t) async {
      final m = jeu();
      await ouvrir(t, 'mere-import', FauxMrc(), magasin: m, role: 'da', nav: donneesLectureSeule('da', 'mere-import'));
      expect(bouton('Importer un fichier'), findsNothing);
      expect(find.text('LOT'), findsOneWidget, reason: 'le tableau reste lisible');
    });

    cas('le lot SAGE repris à la migration figure au tableau, sans validateur inventé', (t) async {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      await ouvrirImport(t, m);
      expect(find.text('IMPORT-SAGE-20260715'), findsOneWidget);
      expect(find.text('non renseigné'), findsWidgets);
      expect(kpi(t, 'Lots importés'), '1');
      expect(kpi(t, 'Lignes rejetées'), '0');
    });

    cas('un fichier fautif est refusé EN ENTIER : la ligne est nommée, rien n’est écrit, le rejet est consigné', (t) async {
      final m = jeu();
      final avant = m.collection('produits').toutes.length;
      fichiers['/lot.csv'] = '${entete}A1;GANTS;10;100;conso_medical\nA2;SERINGUE;-3;50;conso_medical\nA3;COTON;5;abc;conso_medical\n';
      await ouvrirImport(t, m);
      await analyser(t, '/lot.csv');
      final refus = [for (final w in t.widgetList<Text>(find.byKey(const Key('mrc-refus')))) w.data!];
      expect(refus.length, 2);
      expect(refus[0], contains('Ligne 3'));
      expect(refus[0], contains('quantite'));
      expect(refus[0], contains('RG-03'));
      expect(refus[1], contains('Ligne 4'));
      expect(find.textContaining('Fichier refusé en entier : 2 ligne(s) fautive(s). Rien n’a été écrit.'), findsOneWidget);
      expect(m.collection('produits').toutes.length, avant, reason: 'la ligne A1, valide, n’est PAS écrite non plus');
      expect(bouton('Valider et importer'), findsNothing);
      final lot = m.collection('lotsImport').actives.single;
      expect(lot['etat'], 'refusé');
      expect(lot['rejetees'], 2);
    });

    cas('un fichier valide : analyse, puis validation nommée ; chaque fiche porte source, lot et validateur', (t) async {
      final m = jeu();
      final avant = m.collection('produits').toutes.length;
      fichiers['/lot.csv'] = '${entete}ZZ1;GANTS TEST;10;100;conso_medical\nZZ2;SERINGUE TEST;5;0;medicament\n';
      await ouvrirImport(t, m);
      await analyser(t, '/lot.csv');
      expect(find.textContaining('Fichier accepté : 2 ligne(s), 15 unité(s)'), findsOneWidget);
      expect(m.collection('produits').toutes.length, avant, reason: 'rien n’est écrit avant la validation');
      await toucher(t, bouton('Valider et importer'));
      expect(find.textContaining('au nom de'), findsOneWidget);
      await toucher(t, bouton('Valider et importer').last);
      final ajoutes = m.collection('produits').toutes.where((p) => p['lotImport'] == 'IMPORT-SAGE-20261031').toList();
      expect(ajoutes.length, 2);
      expect(m.collection('produits').toutes.length, avant + 2);
      for (final p in ajoutes) {
        expect(p['source'], 'SAGE_100_GESTION_COMMERCIALE_15.01');
        expect('${p['validePar']}', isNotEmpty);
        expect(p.containsKey('seuilAlerte'), isFalse);
      }
      expect(ajoutes.firstWhere((p) => p['code'] == 'ZZ2')['valoriseSage'], isFalse);
      final lot = m.collection('lotsImport').actives.single;
      expect(lot['etat'], 'importé');
      expect(lot['lignes'], 2);
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Import' && a['reference'] == 'IMPORT-SAGE-20261031'), isTrue, reason: 'RG-12');
    });

    cas('un code déjà au catalogue est refusé en le nommant : rien n’est écrasé', (t) async {
      final m = jeu();
      final existant = '${m.collection('produits').actives.first['code']}';
      fichiers['/lot.csv'] = '$entete$existant;DOUBLON;1;1;medicament\n';
      await ouvrirImport(t, m);
      await analyser(t, '/lot.csv');
      expect(find.textContaining('rien n’est écrasé'), findsOneWidget);
    });

    cas('fichier illisible : le chemin est nommé, rien n’est écrit', (t) async {
      final m = jeu();
      await ouvrirImport(t, m);
      await analyser(t, '/absent.csv');
      expect(find.textContaining('Fichier illisible : /absent.csv'), findsOneWidget);
      expect(m.collection('lotsImport').toutes, isEmpty);
    });

    test('la source réelle refuse un lot non accepté sans rien écrire', () {
      final m = jeu();
      final avant = m.collection('produits').toutes.length;
      final s = source(m);
      final a = mrcAnalyserImport('${entete}A;B;-1;1;medicament\n', mrcProfilSage);
      final r = s.importer(a, fichier: 'f.csv', par: 'TEST');
      expect(r.ok, isFalse);
      expect(m.collection('produits').toutes.length, avant);
      expect(m.collection('lotsImport').toutes, isEmpty);
    });
  });

  group('sources réelles', () {
    test('mise en service : un choix consigné est relu, au nom de l’agent, et ne se duplique pas', () async {
      final m = jeu();
      final s = MrcSourcesReelles(magasin: m, horloge: () => auj);
      var c = await s.constats(const ConfigPoste(mode: ModePoste.fileul), null);
      expect(c['identite'], isNull, reason: 'aucune source : non vérifié');
      expect(c['jeu_depart'], isFalse);
      expect(c['activation'], isFalse);
      expect(c['appairage'], isNull);
      s.consigner('jeu_depart', choix: 'demonstration', par: 'TAKI Alimatou');
      s.consigner('jeu_depart', choix: 'essentiels', par: 'TAKI Alimatou');
      c = await s.constats(const ConfigPoste(mode: ModePoste.mere), etat(appareils: [appareil('u1', 'Caisse')]));
      expect(c['jeu_depart'], isTrue);
      expect(c['appairage'], isTrue);
      expect(m.collection('miseEnService').actives.length, 1);
      expect(m.collection('miseEnService').actives.single['choix'], 'essentiels');
      expect(s.consigner('inconnue', par: 'X').ok, isFalse);
    });

    test('une source sans contrôleur refuse d’arrêter, de redémarrer ou de désactiver en nommant la cause', () async {
      final s = MrcSourcesReelles(magasin: jeu());
      for (final r in [await s.arreter(), await s.redemarrer(), await s.desactiver('x')]) {
        expect(r.ok, isFalse);
        expect(r.message, contains('ne pilote pas'));
      }
      expect(s.serviceEnMarche().disponible, isFalse);
      expect(s.port().disponible, isFalse);
    });

    test('le moteur réel n’écoute QUE sur la boucle locale : l’écran le dit parce que c’est vrai', () async {
      const port = 19438;
      final service = ServiceMereLocal(ConfigMere(port: port, dbChemin: ':memory:', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-mrc'));
      await service.demarrer();
      try {
        final s = MrcSourcesReelles(magasin: jeu());
        expect(s.adresseEcoute().valeur, startsWith('127.0.0.1'));
        final externes = await s.adressesLocales();
        for (final a in externes) {
          Object? erreur;
          try {
            (await Socket.connect(a, port, timeout: const Duration(seconds: 2))).destroy();
          } catch (e) {
            erreur = e;
          }
          expect(erreur, isNotNull, reason: '$a:$port ne devrait pas joindre un service lié à 127.0.0.1');
        }
        final ok = await s.testerAcces('127.0.0.1', port);
        expect(ok.ok, isTrue, reason: ok.message);
        expect((await s.testerAcces('127.0.0.1', 19439)).ok, isFalse);
      } finally {
        await service.arreter();
      }
    });
  });
}

/// Source réelle dont la lecture de fichier est scriptée (aucun disque).
class SourceFichiers extends MrcSourcesReelles {
  SourceFichiers(Magasin m, this.fichiers) : super(magasin: m, horloge: () => auj);
  final Map<String, String> fichiers;
  @override
  Future<String> lireFichier(String chemin) async => fichiers[chemin] ?? (throw const FileSystemException('introuvable'));
}
