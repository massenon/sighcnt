import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/m14/sauvegardes.dart' show enregistrerSauvegarde;
import 'package:sigh_poste/modules/mere/mrb_cle.dart';
import 'package:sigh_poste/modules/mere/mrb_commun.dart' show mrbDateHeure, mrbDateHeureMs;
import 'package:sigh_poste/modules/mere/mrb_integrite.dart';
import 'package:sigh_poste/modules/mere/mrb_journal.dart';
import 'package:sigh_poste/modules/mere/mrb_reinit.dart';
import 'package:sigh_poste/modules/mere/mrb_relais.dart';
import 'package:sigh_poste/modules/mere/mrb_sauvegardes.dart';
import 'package:sigh_poste/modules/mere/mrb_source.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// Console du poste mère, lot (b) : journal technique, sauvegardes, clé de clinique, intégrité, réinitialisation de production, relais, indicateurs.
/// Les écrans lisent une `MrbSource` injectée (aucun réseau). Chaque test peut échouer : un refus se nomme, une valeur sans source reste « non disponible »,
/// la clé n'apparaît jamais, une commande interdite est absente.
const cleBase64 = 'Y2xlLWRlLWNsaW5pcXVlLTAxMjM0NTY3ODk=';
final maintenant = DateTime(2026, 10, 31, 12);
int ago(Duration d) => maintenant.subtract(d).millisecondsSinceEpoch;

MrbEtat unEtat({
  int seqMax = 120,
  int repSeq = 100,
  int? repN = 7,
  bool reinit = false,
  String? restauration,
  List<String> bloques = const [],
  List<Map<String, Object?>> alertes = const [],
  List<MrbAppareil> appareils = const [],
}) =>
    MrbEtat(
        epoch: 3,
        seqMax: seqMax,
        repSeq: repSeq,
        repN: repN,
        nbOperations: seqMax,
        depot: 'pg',
        restauration: restauration,
        reinitOuverte: reinit,
        alertes: alertes,
        bloques: bloques,
        derives: const [],
        appareils: appareils);

MrbSante uneSante({List<MrbControle>? controles}) => MrbSante(etat: 'attention', depot: 'pg', controles: controles ?? [
      MrbControle(nom: 'Sauvegarde', etat: 'ok', detail: 'Dernière sauvegarde il y a 3.0 h.', valeur: ago(const Duration(hours: 3))),
      const MrbControle(nom: 'Relais en ligne', etat: 'ok', detail: '20 opération(s) pas encore répliquées (chiffrées) vers le relais.', valeur: 20),
    ]);

class Faux extends MrbSource {
  Faux({MrbEtat? etat, MrbSante? sante, this.journalV = const [], this.patients = 12});
  MrbEtat etatV = unEtat();
  MrbSante? santeV;
  List<MrbLigneJournal> journalV;
  int? patients;
  Object? panneEtat;
  final appels = <String>[];
  String? reponseReinit;

  // Capacités facultatives
  List<MrbSauvegarde>? catalogue;
  String? empreinte;
  DateTime? cree;
  List<MrbEchangeRelais>? echangesV;
  DateTime? battement;
  bool verifOk = false;

  @override
  Future<MrbEtat> etat() async {
    if (panneEtat != null) throw panneEtat!;
    return etatV;
  }

  @override
  Future<MrbSante> supervision() async {
    if (panneEtat != null) throw panneEtat!;
    return santeV ?? uneSante();
  }

  @override
  Future<List<MrbLigneJournal>> journal({int limite = 500}) async {
    if (panneEtat != null) throw panneEtat!;
    appels.add('journal $limite');
    return journalV.take(limite).toList();
  }

  @override
  Future<int?> patientsActifs() async => patients;

  @override
  Future<String> sauvegarderMaintenant() async {
    appels.add('sauvegarder');
    return '/srv/sauvegardes/manuelle-1.enc';
  }

  @override
  Future<void> debloquer(String uuid) async {
    appels.add('debloquer $uuid');
    etatV = unEtat(bloques: etatV.bloques.where((b) => b != uuid).toList(), appareils: etatV.appareils);
  }

  @override
  Future<void> revoquer(String uuid) async => appels.add('revoquer $uuid');

  @override
  Future<void> ouvrirFenetreReinit(bool ouvrir) async {
    appels.add('fenetre $ouvrir');
    etatV = unEtat(reinit: ouvrir);
  }

  @override
  Future<MrbResultatReinit> reinitialiser({required String confirmation, required String second}) async {
    appels.add('reinit $confirmation|$second');
    etatV = unEtat(reinit: false);
    journalV = [MrbLigneJournal(quand: maintenant.millisecondsSinceEpoch, niveau: 'alerte', source: 'administration', message: 'Réinitialisation des données (sauvegarde préalable : /srv/avant-reinit.db)'), ...journalV];
    return MrbResultatReinit(sauvegarde: reponseReinit ?? '/srv/avant-reinit.db', epoch: 4);
  }

  @override
  Future<MrbCodeMobile> codeMobile(String etiquette, {required String profil, String? fonction}) async {
    appels.add('codeMobile $etiquette $profil ${fonction ?? ''}'.trim());
    return MrbCodeMobile(code: 'MOBI9999', payloadQr: mrbPayloadQrMobile(code: 'MOBI9999', cleBase64: cleBase64));
  }

  @override
  Future<List<MrbSauvegarde>?> sauvegardes() async => catalogue;
  @override
  Future<String?> empreinteCle() async => empreinte;
  @override
  Future<DateTime?> cleCreeeLe() async => cree;
  @override
  Future<List<MrbEchangeRelais>?> echanges() async => echangesV;
  @override
  Future<DateTime?> dernierBattement() async => battement;
  @override
  Future<void> verifierDerniereSauvegarde() async {
    if (!verifOk) return super.verifierDerniereSauvegarde();
    appels.add('verifier');
  }
}

final donnees = DonneesNavigation.depuisDossier();

Future<Magasin> ouvrir(WidgetTester t, String ecran, Faux faux, {String role = 'admin', Magasin? magasin}) async {
  mrbSourceInjectee = faux;
  mrbIntervalle = const Duration(hours: 1);
  addTearDown(() => mrbSourceInjectee = null);
  t.view.physicalSize = const Size(1500, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  final m = magasin ?? Magasin();
  final client = ClientMere(base: Uri.parse('http://x'), secretAdmin: 's', client: MockClient((r) async => http.Response('[]', 200)));
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.mere, role: role),
      client: client,
      ecranInitial: ecran,
      magasin: m,
      horloge: () => maintenant));
  await pomper(t);
  return m;
}

Future<void> pomper(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// L'écran seul, avec des droits choisis (la coque ne les donne jamais partiels à `admin`).
Future<Magasin> monterSeul(WidgetTester t, Widget ecran, Faux faux, {Droit droit = const Droit(voir: true, editer: true, annuler: true), DateTime Function()? horloge, Duration? intervalle}) async {
  mrbSourceInjectee = faux;
  mrbIntervalle = intervalle ?? const Duration(hours: 1);
  addTearDown(() => mrbSourceInjectee = null);
  t.view.physicalSize = const Size(1500, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  final m = Magasin();
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: ContexteEcran(
                  ecranId: 'mere-test',
                  role: 'admin',
                  droit: droit,
                  magasin: m,
                  utilisateur: 'Mme TAKI',
                  aller: (_) {},
                  horloge: horloge ?? () => maintenant,
                  child: ecran)))));
  await pomper(t);
  return m;
}

const lectureSeule = Droit(voir: true, editer: false, annuler: false);
const ecritureSansAnnulation = Droit(voir: true, editer: true, annuler: false);

Finder bouton(String libelle) => find.byWidgetPredicate((w) => w is BoutonSigh && w.libelle == libelle);

/// Tout ce qui est lisible à l'écran : textes, étiquettes, contenu des champs de saisie et des textes sélectionnables.
String toutLeTexte(WidgetTester t) => [
      ...textesVisibles(t),
      for (final e in t.widgetList<EditableText>(find.byType(EditableText))) e.controller.text,
    ].join('\n');

String kpi(WidgetTester t, String libelle) => t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).valeur;
String? kpiIndice(WidgetTester t, String libelle) => t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).indice;

void main() {
  setUpAll(chargerPolices);

  group('branchement : les sept écrans sont portés et nommés', () {
    for (final (id, titre) in const [
      ('mere-journal-technique', 'Journal technique'),
      ('mere-sauvegardes', 'Sauvegardes et restauration'),
      ('mere-cle-clinique', 'Clé de clinique'),
      ('mere-integrite', 'Intégrité et altérations'),
      ('mere-reinit', 'Réinitialisation de production'),
      ('mere-relais', 'Relais en ligne'),
      ('mere-indicateurs', 'Indicateurs publiés'),
    ]) {
      testWidgets('$id s’ouvre dans la coque de la mère', (t) async {
        await ouvrir(t, id, Faux());
        expect(find.byKey(const Key('ecran-a-porter')), findsNothing, reason: '$id est encore « à porter »');
        expect(t.widget<Text>(find.byKey(const Key('titre-page'))).data, titre);
      });
    }

    testWidgets('sur un POSTE FILEUL le domaine « Poste mère » n’existe pas : ces écrans ne sont pas atteignables', (t) async {
      mrbSourceInjectee = Faux();
      addTearDown(() => mrbSourceInjectee = null);
      t.view.physicalSize = const Size(1500, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(SighPoste(donnees: donnees, config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin')));
      await t.pump();
      expect(find.byKey(const Key('domaine-Poste mère')), findsNothing);
    });

    testWidgets('un rôle sans accès à la mère (caissier) ne les ouvre pas', (t) async {
      await ouvrir(t, 'mere-reinit', Faux(), role: 'caissier');
      expect(find.text('Réinitialisation de production'), findsNothing, reason: 'écran fermé au profil : la coque ne le sert pas');
      expect(find.byKey(const Key('domaine-Poste mère')), findsNothing);
    });
  });

  group('journal technique', () {
    testWidgets('compte les 24 dernières heures par niveau, du plus récent au plus ancien, et filtre', (t) async {
      final f = Faux()
        ..journalV = [
          MrbLigneJournal(quand: ago(const Duration(hours: 1)), niveau: 'erreur', source: 'relais', message: 'Relais injoignable'),
          MrbLigneJournal(quand: ago(const Duration(hours: 2)), niveau: 'alerte', source: 'relais', message: 'Alerte trou (appareil u1)'),
          MrbLigneJournal(quand: ago(const Duration(hours: 5)), niveau: 'info', source: 'mere', message: 'Démarrage'),
          MrbLigneJournal(quand: ago(const Duration(hours: 30)), niveau: 'erreur', source: 'requete', message: 'Ancienne erreur'),
        ];
      await ouvrir(t, 'mere-journal-technique', f);
      expect(kpi(t, 'Évènements (24 h)'), '3');
      expect(kpi(t, 'Alertes'), '1');
      expect(kpi(t, 'Erreurs'), '1', reason: 'l’erreur de 30 h est hors fenêtre');
      expect(find.text('Relais injoignable'), findsOneWidget);
      final y = ['Relais injoignable', 'Alerte trou (appareil u1)', 'Démarrage'].map((s) => t.getTopLeft(find.text(s)).dy).toList();
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: 'du plus récent au plus ancien');
    });

    testWidgets('une lecture tronquée dans la fenêtre est annoncée « au moins »', (t) async {
      final f = Faux()
        ..journalV = [for (var i = 1; i <= mrbLimiteJournal; i++) MrbLigneJournal(quand: ago(Duration(minutes: i)), niveau: 'info', source: 's', message: 'e$i')];
      await ouvrir(t, 'mere-journal-technique', f);
      expect(kpi(t, 'Évènements (24 h)'), '$mrbLimiteJournal');
      expect(kpiIndice(t, 'Évènements (24 h)'), startsWith('au moins'));
    });

    testWidgets('service muet : « non disponible », jamais zéro, et la cause est nommée', (t) async {
      final f = Faux()..panneEtat = ErreurMere(503, 'base_indisponible', 'La base ne répond pas.');
      await ouvrir(t, 'mere-journal-technique', f);
      expect(kpi(t, 'Évènements (24 h)'), 'non disponible');
      expect(kpi(t, 'Alertes'), 'non disponible');
      expect(kpi(t, 'Erreurs'), 'non disponible');
      expect(find.textContaining('base_indisponible'), findsOneWidget);
      expect(find.text('Journal non lu : le service ne répond pas.'), findsOneWidget);
    });

    testWidgets('journal vide : le dit (ce n’est pas une panne)', (t) async {
      await ouvrir(t, 'mere-journal-technique', Faux());
      expect(kpi(t, 'Évènements (24 h)'), '0');
      expect(find.text('Aucun évènement enregistré.'), findsOneWidget);
    });

    testWidgets('l’export écrit un CSV des lignes affichées', (t) async {
      final ecrits = <String, String>{};
      final avant = enregistrerSauvegarde;
      enregistrerSauvegarde = (nom, contenu) async {
        ecrits[nom] = contenu;
        return '/tmp/$nom';
      };
      addTearDown(() => enregistrerSauvegarde = avant);
      final f = Faux()..journalV = [MrbLigneJournal(quand: ago(const Duration(hours: 1)), niveau: 'erreur', source: 'relais', message: 'Relais injoignable')];
      await ouvrir(t, 'mere-journal-technique', f);
      await t.tap(bouton('Exporter'));
      await pomper(t);
      await t.tap(bouton('CSV / Excel'));
      await pomper(t);
      expect(ecrits.keys.single, startsWith('journal-technique-mere-'));
      final csv = ecrits.values.single;
      expect(csv, contains('Quand'));
      expect(csv, contains('Relais injoignable'));
      expect(find.textContaining('Journal exporté'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('sauvegardes et restauration', () {
    testWidgets('la date de la dernière sauvegarde vient de la supervision ; conservation et vérification restent « non disponible »', (t) async {
      await ouvrir(t, 'mere-sauvegardes', Faux());
      expect(kpi(t, 'Dernière sauvegarde'), mrbDateHeureMs(ago(const Duration(hours: 3))));
      expect(kpiIndice(t, 'Dernière sauvegarde'), 'Dernière sauvegarde il y a 3.0 h.');
      expect(kpi(t, 'Conservation'), 'non disponible');
      expect(kpi(t, 'Dernière vérification'), 'non disponible');
      expect(find.textContaining('Catalogue des sauvegardes non disponible'), findsOneWidget);
    });

    testWidgets('« Aucune sauvegarde » du moteur s’affiche telle quelle (alerte), pas une date inventée', (t) async {
      final f = Faux()
        ..santeV = uneSante(controles: const [MrbControle(nom: 'Sauvegarde', etat: 'alerte', detail: 'Aucune sauvegarde n\'a jamais été faite.')]);
      await ouvrir(t, 'mere-sauvegardes', f);
      expect(kpi(t, 'Dernière sauvegarde'), 'Aucune');
    });

    testWidgets('« Sauvegarder maintenant » appelle la mère, annonce le fichier et trace la séance', (t) async {
      final f = Faux();
      await ouvrir(t, 'mere-sauvegardes', f);
      await t.tap(bouton('Sauvegarder maintenant'));
      await pomper(t);
      expect(f.appels, contains('sauvegarder'));
      expect(find.textContaining('/srv/sauvegardes/manuelle-1.enc'), findsOneWidget);
      expect(find.text('Manuelle'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('« Vérifier la dernière » : refus NOMMÉ quand le service ne sait pas le faire', (t) async {
      final f = Faux();
      await ouvrir(t, 'mere-sauvegardes', f);
      await t.tap(bouton('Vérifier la dernière'));
      await pomper(t);
      expect(find.textContaining('test à blanc'), findsOneWidget);
      expect(kpi(t, 'Dernière vérification'), 'non disponible', reason: 'un refus ne devient pas une vérification');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('quand le service sait vérifier, la date de vérification apparaît', (t) async {
      final f = Faux()..verifOk = true;
      await ouvrir(t, 'mere-sauvegardes', f);
      await t.tap(bouton('Vérifier la dernière'));
      await pomper(t);
      expect(f.appels, contains('verifier'));
      expect(kpi(t, 'Dernière vérification'), mrbDateHeure(maintenant));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('un catalogue fourni par le service remplit le tableau (taille manquante : « non disponible »)', (t) async {
      final f = Faux()
        ..catalogue = [
          MrbSauvegarde(date: DateTime(2026, 10, 30, 2), nature: 'Quotidienne', tailleOctets: 5 * 1024 * 1024, verification: 'Vérifiée'),
          MrbSauvegarde(date: DateTime(2026, 10, 29, 2), nature: 'Quotidienne'),
        ];
      await ouvrir(t, 'mere-sauvegardes', f);
      expect(find.text('5.0 Mo'), findsOneWidget);
      expect(find.text('Vérifiée'), findsOneWidget);
      expect(find.text('non disponible'), findsWidgets);
      expect(find.textContaining('Catalogue des sauvegardes non disponible'), findsNothing);
    });

    testWidgets('onglet Restaurer : l’état de la restauration vient du moteur, la procédure est nommée, aucun bouton ne la lance', (t) async {
      final f = Faux()..etatV = unEtat(restauration: 'echec: trou dans le journal au rang 5');
      await ouvrir(t, 'mere-sauvegardes', f);
      await t.tap(find.text('Restaurer').first);
      await pomper(t);
      expect(find.text('Restauration en échec : trou dans le journal au rang 5'), findsOneWidget);
      expect(find.textContaining('journal est VIDE'), findsOneWidget);
      expect(bouton('Restaurer'), findsNothing);
      await t.tap(find.text('Remplacer la mère').first);
      await pomper(t);
      expect(find.textContaining('par RESTAURATION'), findsOneWidget);
    });

    testWidgets('sans droit d’écrire : ni « Sauvegarder maintenant » ni « Vérifier la dernière » (absents)', (t) async {
      await monterSeul(t, const EcranSauvegardesMere(), Faux(), droit: lectureSeule);
      expect(bouton('Sauvegarder maintenant'), findsNothing);
      expect(bouton('Vérifier la dernière'), findsNothing);
    });
  });

  group('clé de clinique', () {
    testWidgets('empreinte publiée par le service : 8 caractères ; sinon « non disponible » ; jamais la clé', (t) async {
      final f = Faux()
        ..empreinte = 'ab12cd34' * 8
        ..cree = DateTime(2026, 8, 1, 9);
      await ouvrir(t, 'mere-cle-clinique', f);
      expect(kpi(t, 'Empreinte (SHA-256, 8 premiers)'), 'AB12CD34');
      expect(kpi(t, 'Créée le'), mrbDateHeure(DateTime(2026, 8, 1, 9)));
      expect(toutLeTexte(t), isNot(contains('ab12cd34ab12cd34')), reason: 'seuls les 8 premiers caractères sont montrés');
    });

    testWidgets('une valeur qui n’est pas une empreinte SHA-256 (par exemple la clé Base64) n’est PAS affichée', (t) async {
      final f = Faux()..empreinte = cleBase64;
      await ouvrir(t, 'mere-cle-clinique', f);
      expect(kpi(t, 'Empreinte (SHA-256, 8 premiers)'), 'non disponible');
      expect(toutLeTexte(t), isNot(contains(cleBase64)));
    });

    testWidgets('sans attestation : le détenteur « non désigné » est annoncé et la copie papier « Non attestée »', (t) async {
      await ouvrir(t, 'mere-cle-clinique', Faux());
      expect(find.textContaining('Détenteur de la copie papier non désigné'), findsOneWidget);
      expect(kpi(t, 'Copie papier'), 'Non attestée');
      expect(kpi(t, 'Empreinte (SHA-256, 8 premiers)'), 'non disponible');
    });

    testWidgets('l’attestation exige détenteur, scellé et contrôleur (refus nommé), puis s’enregistre au journal du poste (RG-12)', (t) async {
      final m = await ouvrir(t, 'mere-cle-clinique', Faux());
      await t.tap(bouton('Enregistrer l’attestation'));
      await pomper(t);
      expect(find.textContaining('Détenteur, Scellé n°, Contrôlé par'), findsOneWidget);
      expect(m.collection(mrbCollectionAttestations).toutes, isEmpty);
      await t.pump(const Duration(seconds: 10));

      await t.enterText(find.byKey(const Key('mrb:detenteur')), 'Mme TAKI Alimatou');
      await t.enterText(find.byKey(const Key('mrb:scelle')), 'SC-0042');
      await t.enterText(find.byKey(const Key('mrb:controle-par')), 'Dr BASSONGUI');
      await t.tap(bouton('Enregistrer l’attestation'));
      await pomper(t);
      final att = m.collection(mrbCollectionAttestations).toutes.single;
      expect(att['detenteur'], 'Mme TAKI Alimatou');
      expect(att['scelle'], 'SC-0042');
      expect(att['date'], '2026-10-31');
      expect(kpi(t, 'Copie papier'), 'Attestée le 31/10/2026');
      expect(find.textContaining('Détenteur de la copie papier non désigné'), findsNothing);
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Création' && a['entite'] == mrbCollectionAttestations), isTrue,
          reason: 'RG-12 : l’attestation est journalisée avec son auteur');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('le QR d’appairage mobile : un QR et le code, JAMAIS la clé en caractères', (t) async {
      final f = Faux()..empreinte = 'ab12cd34' * 8;
      await ouvrir(t, 'mere-cle-clinique', f);
      await t.tap(bouton('Afficher le QR d’appairage mobile'));
      await pomper(t);
      await t.enterText(find.byType(TextField).last, 'Dr Yeni');
      await t.tap(bouton('Générer le QR'));
      await pomper(t);
      // E1600 : le code porte le profil et la fonction (par défaut le premier choix : soignant, médecin).
      expect(f.appels, contains('codeMobile Dr Yeni soignant medecin'));
      expect(find.byKey(const Key('qual:qr')), findsOneWidget);
      expect(find.text('MOBI9999'), findsOneWidget);
      expect(toutLeTexte(t), isNot(contains(cleBase64)), reason: 'la clé ne s’affiche jamais en clair');
      expect(toutLeTexte(t), isNot(contains('sigh-mobile:')));
    });

    testWidgets('imprimer la copie papier et faire tourner la clé : refus NOMMÉS tant que le service ne les propose pas', (t) async {
      await ouvrir(t, 'mere-cle-clinique', Faux());
      await t.tap(bouton('Imprimer la copie papier'));
      await pomper(t);
      expect(find.textContaining('ne peut pas être produite depuis la console'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await t.tap(bouton('Faire tourner la clé'));
      await pomper(t);
      expect(find.text('Faire tourner la clé de clinique ?'), findsOneWidget);
      await t.tap(bouton('Faire tourner la clé').last);
      await pomper(t);
      expect(find.textContaining('rechiffrer le relais'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('droit d’écrire sans droit d’annuler : la rotation est ABSENTE, le reste demeure', (t) async {
      await monterSeul(t, const EcranCleClinique(), Faux(), droit: ecritureSansAnnulation);
      expect(bouton('Faire tourner la clé'), findsNothing);
      expect(bouton('Imprimer la copie papier'), findsOneWidget);
      expect(bouton('Afficher le QR d’appairage mobile'), findsOneWidget);
    });

    testWidgets('lecture seule : aucune commande ni formulaire d’attestation', (t) async {
      await monterSeul(t, const EcranCleClinique(), Faux(), droit: lectureSeule);
      expect(bouton('Imprimer la copie papier'), findsNothing);
      expect(bouton('Afficher le QR d’appairage mobile'), findsNothing);
      expect(bouton('Enregistrer l’attestation'), findsNothing);
      expect(find.text('Attestation de la copie papier'), findsOneWidget, reason: 'la lecture reste permise');
    });
  });

  group('intégrité et altérations', () {
    Faux avecBloque() => Faux()
      ..etatV = unEtat(
          bloques: ['u-2'],
          appareils: const [MrbAppareil(uuid: 'u-2', etiquette: 'Dr Yeni', role: 'mobile', etat: 'actif')],
          alertes: [
            {'type': 'authentification', 'appareil': 'u-2', 'n': 4, 'quand': ago(const Duration(hours: 2))}
          ])
      ..journalV = [
        MrbLigneJournal(quand: ago(const Duration(hours: 2)), niveau: 'alerte', source: 'relais', message: 'Alerte authentification (appareil u-2)'),
        MrbLigneJournal(quand: ago(const Duration(days: 3)), niveau: 'alerte', source: 'relais', message: 'Alerte trou (appareil u-9)'),
        MrbLigneJournal(quand: ago(const Duration(days: 40)), niveau: 'alerte', source: 'relais', message: 'Alerte trou (appareil u-1)'),
      ];

    testWidgets('l’appareil bloqué est nommé avec sa cause, l’heure de détection et le rang ; les compteurs viennent du journal', (t) async {
      await ouvrir(t, 'mere-integrite', avecBloque());
      expect(kpi(t, 'Appareils bloqués'), '1');
      expect(kpi(t, 'Enveloppes altérées (30 j)'), '1');
      expect(kpi(t, 'Trous détectés'), '1', reason: 'le trou de 40 jours est hors des 30 jours');
      expect(find.text('Dr Yeni'), findsOneWidget);
      expect(find.text('Enveloppe altérée (authentification GCM échouée)'), findsOneWidget);
      expect(find.text(mrbDateHeureMs(ago(const Duration(hours: 2)))), findsOneWidget);
      expect(find.text('4'), findsWidgets);
    });

    testWidgets('si le service a perdu l’alerte (redémarrage), la cause est dite non conservée, pas devinée', (t) async {
      final f = Faux()..etatV = unEtat(bloques: ['u-7']);
      await ouvrir(t, 'mere-integrite', f);
      expect(find.textContaining('Cause non conservée par le service'), findsOneWidget);
      expect(find.text('non disponible'), findsWidgets);
    });

    testWidgets('Débloquer : confirmation qui rappelle la vérification en personne, puis le geste', (t) async {
      final f = avecBloque();
      await ouvrir(t, 'mere-integrite', f);
      await t.tap(bouton('Débloquer'));
      await pomper(t);
      expect(find.textContaining('perdu ? volé ? relais compromis ?'), findsWidgets);
      expect(f.appels.where((a) => a.startsWith('debloquer')), isEmpty, reason: 'rien ne part avant la confirmation');
      await t.tap(bouton('Débloquer').last);
      await pomper(t);
      expect(f.appels, contains('debloquer u-2'));
      expect(kpi(t, 'Appareils bloqués'), '0');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('Révoquer demande le droit d’annuler : absent sans lui', (t) async {
      await monterSeul(t, const EcranIntegrite(), avecBloque(), droit: ecritureSansAnnulation);
      expect(bouton('Débloquer'), findsOneWidget);
      expect(bouton('Révoquer'), findsNothing);
      await monterSeul(t, const EcranIntegrite(), avecBloque());
      expect(bouton('Révoquer'), findsOneWidget);
      await t.tap(bouton('Révoquer'));
      await pomper(t);
      await t.tap(bouton('Révoquer').last);
      await pomper(t);
      expect(mrbSourceInjectee, isA<Faux>());
      expect((mrbSourceInjectee! as Faux).appels, contains('revoquer u-2'));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('lecture seule : ni Débloquer ni Révoquer', (t) async {
      await monterSeul(t, const EcranIntegrite(), avecBloque(), droit: lectureSeule);
      expect(bouton('Débloquer'), findsNothing);
      expect(bouton('Révoquer'), findsNothing);
      expect(find.text('Dr Yeni'), findsOneWidget);
    });

    testWidgets('aucun appareil bloqué : le dit', (t) async {
      await ouvrir(t, 'mere-integrite', Faux());
      expect(kpi(t, 'Appareils bloqués'), '0');
      expect(find.text('Aucun appareil bloqué.'), findsOneWidget);
    });
  });

  group('réinitialisation de production', () {
    Future<void> ouvrirLaFenetre(WidgetTester t) async {
      await t.tap(bouton('Ouvrir la fenêtre (30 min)'));
      await pomper(t);
      await t.pump(const Duration(seconds: 10));
      await pomper(t);
    }

    testWidgets('fenêtre fermée : seule la commande d’ouverture existe, la réinitialisation est ABSENTE', (t) async {
      await ouvrir(t, 'mere-reinit', Faux());
      expect(find.text('La fenêtre de réinitialisation est fermée.'), findsOneWidget);
      expect(bouton('Ouvrir la fenêtre (30 min)'), findsOneWidget);
      expect(bouton('Réinitialiser'), findsNothing);
      expect(find.byKey(const Key('mrb:confirmation')), findsNothing);
      expect(find.text('Ce qui est conservé'), findsOneWidget);
      expect(find.text('• tarifs'), findsOneWidget, reason: 'les essentiels du MOTEUR sont nommés');
      expect(find.text('• Patients et consultations'), findsOneWidget, reason: 'ce qui est vidé aussi');
    });

    testWidgets('sans le droit d’annuler : aucune commande, ni ouverture ni réinitialisation (absentes, pas grisées)', (t) async {
      await monterSeul(t, const EcranReinitialisation(), Faux(), droit: ecritureSansAnnulation);
      expect(bouton('Ouvrir la fenêtre (30 min)'), findsNothing);
      expect(bouton('Réinitialiser'), findsNothing);
      await monterSeul(t, const EcranReinitialisation(), Faux()..etatV = unEtat(reinit: true), droit: ecritureSansAnnulation);
      expect(bouton('Réinitialiser'), findsNothing, reason: 'même fenêtre ouverte par un autre : pas de droit, pas de commande');
      expect(find.byKey(const Key('mrb:confirmation')), findsNothing);
    });

    testWidgets('chaque garde refuse en se nommant et AUCUN appel de réinitialisation ne part', (t) async {
      final f = Faux()..etatV = unEtat(reinit: true);
      await monterSeul(t, const EcranReinitialisation(), f);
      expect(bouton('Réinitialiser'), findsOneWidget);

      await t.tap(bouton('Réinitialiser'));
      await pomper(t);
      expect(find.textContaining('Saisir le nom de la clinique'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));

      await t.enterText(find.byKey(const Key('mrb:confirmation')), 'nassiera too');
      await t.tap(bouton('Réinitialiser'));
      await pomper(t);
      expect(find.textContaining('Saisir le nom de la clinique'), findsOneWidget, reason: 'le nom se saisit à l’identique');
      await t.pump(const Duration(seconds: 10));

      await t.enterText(find.byKey(const Key('mrb:confirmation')), 'NASSIERA TOO');
      await t.tap(bouton('Réinitialiser'));
      await pomper(t);
      expect(find.textContaining('Un second profil (DAF ou Direction) doit confirmer'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));

      await t.enterText(find.byKey(const Key('mrb:second-profil')), 'mme taki');
      await t.tap(bouton('Réinitialiser'));
      await pomper(t);
      expect(find.textContaining('une autre personne'), findsOneWidget, reason: 'l’auteur (Mme TAKI) ne peut pas être son propre second profil');
      await t.pump(const Duration(seconds: 10));

      expect(f.appels.where((a) => a.startsWith('reinit')), isEmpty);
    });

    testWidgets('double confirmation passée : sauvegarde préalable annoncée, trace relue au journal, geste inscrit au journal du poste avec le second profil', (t) async {
      final f = Faux();
      final m = await ouvrir(t, 'mere-reinit', f);
      await ouvrirLaFenetre(t);
      await t.enterText(find.byKey(const Key('mrb:confirmation')), 'NASSIERA TOO');
      await t.enterText(find.byKey(const Key('mrb:second-profil')), 'Mme TAKI Alimatou');
      await t.tap(bouton('Réinitialiser'));
      await pomper(t);
      expect(find.text('Dernière confirmation'), findsOneWidget);
      expect(f.appels.where((a) => a.startsWith('reinit')), isEmpty, reason: 'rien ne part avant la dernière confirmation');
      await t.tap(bouton('Réinitialiser').last);
      await pomper(t);
      await pomper(t);
      expect(f.appels, contains('reinit NASSIERA TOO|Mme TAKI Alimatou'));
      expect(find.textContaining('Sauvegarde préalable : /srv/avant-reinit.db'), findsWidgets);
      expect(find.textContaining('Le geste est inscrit au journal technique de la mère'), findsOneWidget);
      expect(find.textContaining('Nouvelle époque : 4'), findsOneWidget);
      final trace = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Réinitialisation de production');
      expect(trace['succes'], isTrue);
      expect((trace['apres'] as Map)['secondProfil'], 'Mme TAKI Alimatou');
      expect((trace['apres'] as Map)['sauvegardePrealable'], '/srv/avant-reinit.db');
      expect(bouton('Réinitialiser'), findsNothing, reason: 'la fenêtre se referme avec le geste');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('si la trace n’est pas retrouvée au journal de la mère, l’écran le dit (il ne la suppose pas)', (t) async {
      final f = _FauxSansTrace();
      await ouvrir(t, 'mere-reinit', f);
      await ouvrirLaFenetre(t);
      await t.enterText(find.byKey(const Key('mrb:confirmation')), 'NASSIERA TOO');
      await t.enterText(find.byKey(const Key('mrb:second-profil')), 'Mme TAKI Alimatou');
      await t.tap(bouton('Réinitialiser'));
      await pomper(t);
      await t.tap(bouton('Réinitialiser').last);
      await pomper(t);
      await pomper(t);
      expect(f.appels.where((a) => a.startsWith('reinit')), hasLength(1));
      expect(find.textContaining('n’a pas été retrouvé au journal technique'), findsOneWidget);
      expect(find.textContaining('Le geste est inscrit au journal technique'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('un refus du service s’affiche avec sa cause et le geste ne se déclare pas fait', (t) async {
      final f = _FauxRefus();
      await ouvrir(t, 'mere-reinit', f);
      await ouvrirLaFenetre(t);
      await t.enterText(find.byKey(const Key('mrb:confirmation')), 'NASSIERA TOO');
      await t.enterText(find.byKey(const Key('mrb:second-profil')), 'Mme TAKI Alimatou');
      await t.tap(bouton('Réinitialiser'));
      await pomper(t);
      await t.tap(bouton('Réinitialiser').last);
      await pomper(t);
      expect(find.textContaining('reinit_fermee'), findsOneWidget);
      expect(find.textContaining('Activité réinitialisée'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('la fenêtre se referme d’elle-même après 30 minutes', (t) async {
      var horloge = maintenant;
      final f = Faux();
      await monterSeul(t, const EcranReinitialisation(), f, horloge: () => horloge, intervalle: const Duration(milliseconds: 200));
      await t.tap(bouton('Ouvrir la fenêtre (30 min)'));
      await pomper(t);
      expect(f.etatV.reinitOuverte, isTrue);
      expect(find.textContaining('Se referme dans 30 min'), findsOneWidget);
      horloge = maintenant.add(const Duration(minutes: 31));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(f.appels, contains('fenetre false'));
      expect(f.etatV.reinitOuverte, isFalse);
      expect(find.text('La fenêtre de réinitialisation est fermée.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('fenêtre ouverte par ailleurs : l’heure d’ouverture est dite inconnue, jamais inventée', (t) async {
      await monterSeul(t, const EcranReinitialisation(), Faux()..etatV = unEtat(reinit: true));
      expect(find.textContaining('Ouverte à une heure inconnue'), findsOneWidget);
    });
  });

  group('relais en ligne', () {
    testWidgets('liaison, retard et compteur d’enveloppes viennent du service ; battement et échanges : « non disponible »', (t) async {
      await ouvrir(t, 'mere-relais', Faux());
      expect(kpi(t, 'Liaison'), 'OK');
      expect(kpi(t, 'Retard de réplication'), '20');
      expect(kpi(t, 'Enveloppes au relais'), '7');
      expect(kpi(t, 'Dernier battement'), 'non disponible');
      expect(find.textContaining('Journal des échanges non disponible'), findsOneWidget);
    });

    testWidgets('sans relais configuré, la liaison est « Inconnu » et ne rassure pas', (t) async {
      final f = Faux()
        ..santeV = uneSante(controles: const [MrbControle(nom: 'Relais en ligne', etat: 'inconnu', detail: 'Aucun relais configuré : pas de copie hors site ni de mobiles.')]);
      await ouvrir(t, 'mere-relais', f);
      expect(kpi(t, 'Liaison'), 'Inconnu');
      expect(kpiIndice(t, 'Liaison'), contains('Aucun relais configuré'));
    });

    testWidgets('compteur d’enveloppes absent du service : « non disponible », pas zéro', (t) async {
      final f = Faux()..etatV = unEtat(repN: null);
      await ouvrir(t, 'mere-relais', f);
      expect(kpi(t, 'Enveloppes au relais'), 'non disponible');
    });

    testWidgets('les échanges n’affichent que des métadonnées', (t) async {
      final f = Faux()
        ..echangesV = [MrbEchangeRelais(quand: DateTime(2026, 10, 31, 11, 59), sens: 'depot', contenu: 'enveloppe de journal rang 7, 2 048 octets chiffrés', resultat: 'Accepté')];
      await ouvrir(t, 'mere-relais', f);
      expect(find.text('Mère vers relais'), findsOneWidget);
      expect(find.text('enveloppe de journal rang 7, 2 048 octets chiffrés'), findsOneWidget);
      expect(find.text('Accepté'), findsOneWidget);
    });

    testWidgets('Tester la liaison et faire tourner le secret : refus nommés, droits respectés', (t) async {
      await ouvrir(t, 'mere-relais', Faux());
      await t.tap(bouton('Tester la liaison'));
      await pomper(t);
      expect(find.textContaining('Le test de liaison n’est pas proposé'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await t.tap(bouton('Faire tourner le secret de la mère'));
      await pomper(t);
      await t.tap(bouton('Faire tourner le secret').last);
      await pomper(t);
      expect(find.textContaining('rotation du secret de la mère n’est pas disponible'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await monterSeul(t, const EcranRelais(), Faux(), droit: ecritureSansAnnulation);
      expect(bouton('Tester la liaison'), findsOneWidget);
      expect(bouton('Faire tourner le secret de la mère'), findsNothing);
    });

    testWidgets('le secret de la mère n’apparaît nulle part', (t) async {
      await ouvrir(t, 'mere-relais', Faux());
      expect(toutLeTexte(t).toLowerCase(), isNot(contains('x-mere')));
    });
  });

  group('indicateurs publiés', () {
    testWidgets('l’aperçu porte EXACTEMENT les trois champs du moteur, avec leurs valeurs lues', (t) async {
      final f = Faux()
        ..patients = 18042
        ..etatV = unEtat(seqMax: 500, repSeq: 480);
      await ouvrir(t, 'mere-indicateurs', f);
      final apercu = t.widget<SelectableText>(find.byKey(const Key('mrb:apercu-indicateurs'))).data!;
      expect(apercu, contains('"patients_actifs": 18042'));
      expect(apercu, contains('"seq_max": 500'));
      expect(apercu, contains('"retard_replication": 20'));
      expect(RegExp(r'"(\w+)":').allMatches(apercu).map((m) => m.group(1)).toList()..remove('indicateurs'), mrbChampsPublies);
      expect(kpi(t, 'Champs publiés'), '3');
      expect(kpi(t, 'Données de santé'), 'Aucune');
      expect(kpi(t, 'Fréquence'), 'non disponible');
    });

    testWidgets('un compteur illisible n’est pas remplacé par zéro dans l’aperçu', (t) async {
      final f = Faux()..patients = null;
      await ouvrir(t, 'mere-indicateurs', f);
      final apercu = t.widget<SelectableText>(find.byKey(const Key('mrb:apercu-indicateurs'))).data!;
      expect(apercu, contains('"patients_actifs": non disponible'));
      expect(apercu, isNot(contains('"patients_actifs": 0')));
    });

    testWidgets('aucun relais configuré : l’écran prévient que rien ne prouve que les indicateurs partent', (t) async {
      final f = Faux()
        ..santeV = uneSante(controles: const [MrbControle(nom: 'Relais en ligne', etat: 'inconnu', detail: 'Aucun relais configuré : pas de copie hors site ni de mobiles.')]);
      await ouvrir(t, 'mere-indicateurs', f);
      expect(find.textContaining('Rien ne prouve que ces indicateurs partent'), findsOneWidget);
    });

    testWidgets('service muet : tout est « non disponible »', (t) async {
      final f = Faux()..panneEtat = ErreurMere(503, 'base_indisponible', 'La base ne répond pas.');
      await ouvrir(t, 'mere-indicateurs', f);
      expect(kpi(t, 'Données de santé'), 'non disponible');
      final apercu = t.widget<SelectableText>(find.byKey(const Key('mrb:apercu-indicateurs'))).data!;
      expect('non disponible'.allMatches(apercu).length, 3);
    });
  });

  group('adaptateur sur le service réel (HTTP)', () {
    test('lit les champs que le moteur renvoie, refuse une réponse sans époque, ne devine rien', () async {
      final appels = <String>[];
      final client = ClientMere(
          base: Uri.parse('http://mere.test'),
          secretAdmin: 'secret',
          client: MockClient((r) async {
            appels.add('${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
            switch (r.url.path) {
              case '/admin/etat':
                return http.Response(
                    '{"epoch":3,"seq_max":120,"rep_seq":100,"rep_n":7,"nb_operations":120,"depot":"pg","reinit_ouverte":true,"alertes":[{"type":"trou","appareil":"u1","attendu":3,"recu":5,"quand":1000}],"bloques":["u1"],"derives":[],"appareils":[{"uuid":"u1","etiquette":"Dr Yeni","role":"mobile","etat":"actif"}],"restauration":null}',
                    200);
              case '/admin/supervision':
                return http.Response('{"etat":"ok","depot":"pg","controles":[{"nom":"Sauvegarde","etat":"ok","detail":"d","valeur":1234}]}', 200);
              case '/admin/journal':
                return http.Response('[{"id":2,"quand":1000,"niveau":"erreur","source":"relais","message":"x"}]', 200);
              case '/admin/compte':
                return http.Response('{"n":42}', 200);
              case '/admin/code-mobile':
                return http.Response('{"code":"MOBI9999","cle":"$cleBase64"}', 200);
              case '/admin/reinitialiser':
                return http.Response('{"sauvegarde":"/s/avant.db","epoch":4}', 200);
              default:
                return http.Response('{"code":"route_inconnue","motif":"Route inconnue."}', 404);
            }
          }));
      final s = MrbSourceClient(client);
      final e = await s.etat();
      expect((e.epoch, e.seqMax, e.repN, e.retardRelais, e.reinitOuverte), (3, 120, 7, 20, true));
      expect(e.bloques, ['u1']);
      expect(e.appareil('u1')!.nom, 'Dr Yeni');
      expect(e.alertes.single['type'], 'trou');
      final sa = await s.supervision();
      expect(sa.controle('Sauvegarde')!.valeur, 1234);
      expect((await s.journal(limite: 500)).single.niveau, 'erreur');
      expect(appels, contains('GET /admin/journal?limite=500'));
      expect(await s.patientsActifs(), 42);
      final mobile = await s.codeMobile('Dr Yeni', profil: 'soignant', fonction: 'medecin');
      expect(mobile.code, 'MOBI9999');
      expect(mobile.payloadQr, contains(cleBase64));
      final r = await s.reinitialiser(confirmation: 'NASSIERA TOO', second: 'X');
      expect((r.sauvegarde, r.epoch), ('/s/avant.db', 4));
      // Ce que le service n'expose pas : non disponible, sans appel réseau.
      appels.clear();
      expect(await s.empreinteCle(), isNull);
      expect(await s.sauvegardes(), isNull);
      expect(await s.echanges(), isNull);
      expect(await s.dernierBattement(), isNull);
      expect(await s.cleCreeeLe(), isNull);
      await expectLater(s.tournerCle(), throwsA(isA<MrbIndisponible>()));
      await expectLater(s.imprimerCopiePapier(), throwsA(isA<MrbIndisponible>()));
      await expectLater(s.verifierDerniereSauvegarde(), throwsA(isA<MrbIndisponible>()));
      await expectLater(s.testerLiaison(), throwsA(isA<MrbIndisponible>()));
      await expectLater(s.tournerSecretMere(), throwsA(isA<MrbIndisponible>()));
      expect(appels, isEmpty);
    });

    test('une réponse sans époque (service muet ou autre chose qu’une mère) est refusée, pas lue comme un état vide', () async {
      final s = MrbSourceClient(ClientMere(base: Uri.parse('http://x'), secretAdmin: 's', client: MockClient((r) async => http.Response('[]', 200))));
      await expectLater(s.etat(), throwsA(isA<ErreurMere>().having((e) => e.code, 'code', 'reponse_inattendue')));
      await expectLater(s.supervision(), throwsA(isA<ErreurMere>()));
    });

    test('un refus du service garde sa cause nommée', () async {
      final s = MrbSourceClient(ClientMere(
          base: Uri.parse('http://x'),
          secretAdmin: 's',
          client: MockClient((r) async => http.Response('{"code":"reinit_fermee","motif":"La réinitialisation est fermée."}', 403))));
      await expectLater(
          s.reinitialiser(confirmation: 'a', second: 'b'), throwsA(isA<ErreurMere>().having((e) => e.code, 'code', 'reinit_fermee')));
    });
  });
}

/// Un service qui refuse la réinitialisation (fenêtre refermée entre-temps) : l'écran doit nommer la cause.
class _FauxRefus extends Faux {
  @override
  Future<MrbResultatReinit> reinitialiser({required String confirmation, required String second}) =>
      throw ErreurMere(403, 'reinit_fermee', 'La réinitialisation est fermée : l’administrateur doit ouvrir la fenêtre.');
}

/// Un service dont le journal ne garde aucune trace de la réinitialisation.
class _FauxSansTrace extends Faux {
  @override
  Future<MrbResultatReinit> reinitialiser({required String confirmation, required String second}) async {
    appels.add('reinit $confirmation|$second');
    etatV = unEtat(reinit: false);
    return const MrbResultatReinit(sauvegarde: '/srv/avant-reinit.db', epoch: 4);
  }
}
