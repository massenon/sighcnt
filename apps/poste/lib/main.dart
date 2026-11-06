import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart' show cfbEssentielles, droitsDepuisMatrice;
import 'package:sigh_sync/sigh_sync.dart';
import 'package:window_manager/window_manager.dart';


import 'donnees/magasin.dart';
import 'donnees/persistance.dart';
import 'modules/cfg/cfb_systeme.dart' show CfbPersistance;
import 'core/config_poste.dart';
import 'core/dossier_donnees.dart';
import 'core/controleur_poste.dart';
import 'core/donnees_navigation.dart';
import 'core/identifiants.dart';
import 'core/service_installation.dart';
import 'core/parametres_poste.dart';
import 'core/theme.dart';
import 'mere/activation.dart';
import 'mere/client_mere.dart';
import 'modules/auth/acc_session.dart';
import 'modules/registre.dart';
import 'shell/coque.dart';
import 'shell/fenetre_poste.dart';
import 'sync/etat_sync.dart';
import 'sync/configuration_sync.dart';
import 'core/plages_codes.dart';
import 'sync/pont_activite.dart';
import 'sync/config_pair.dart';
import 'sync/config_smtp.dart';
import 'sync/etat_pair.dart';
import 'sync/moteur_pair.dart';
import 'sync/modale_trancher.dart';
import 'sync/reservation_stock.dart';
import 'sync/moteur_fileul.dart';
import 'sync/transcription_mobile.dart';

/// Le MODE du poste n'est plus une option de compilation : il vit dans les réglages du poste (`poste.json`) et se décide à
/// l'exécution, sur le serveur local, par « Ce poste → Activer le mode mère ». `SIGH_MODE` ne sert plus qu'à l'amorçage
/// de développement d'un poste NEUF (aucun réglage encore écrit).
const String modeAmorcage =
    String.fromEnvironment('SIGH_MODE', defaultValue: 'fileul');
const String adresseMere =
    String.fromEnvironment('SIGH_MERE', defaultValue: 'http://127.0.0.1:9000');
const String secretAdmin =
    String.fromEnvironment('SIGH_ADMIN', defaultValue: '');
const String roleDev =
    String.fromEnvironment('SIGH_ROLE', defaultValue: 'admin');

/// LA CONNEXION EST ACTIVÉE PAR DÉFAUT (Direction, 01/11/2026) : le poste démarre sur l'écran de connexion de la maquette (`index`), puis ouvre le tableau
/// de bord du rôle et le modal de notifications d'ouverture ; le verrou d'inactivité (quinze minutes) joue. `SIGH_CONNEXION=non` rétablit l'ancien mode
/// sans connexion (le poste s'ouvre sous `SIGH_ROLE`) : il ne sert plus qu'aux tests et au développement.
const String connexionExigee =
    String.fromEnvironment('SIGH_CONNEXION', defaultValue: 'oui');

/// `SIGH_PLEIN_ECRAN=oui` : démarrer en vrai plein écran (la barre des tâches disparaît). Par défaut (Direction, 02/11/2026) le poste démarre MAXIMISÉ, barre
/// des tâches visible, comme les logiciels de bureautique ; F11 et la barre supérieure basculent en plein écran à la demande.
const String pleinEcranAuDemarrage =
    String.fromEnvironment('SIGH_PLEIN_ECRAN', defaultValue: 'non');

/// `SIGH_MDP_DEMO=<mot de passe>` : DÉVELOPPEMENT SEULEMENT. Définit ce mot de passe pour tous les comptes actifs du jeu, avec changement obligatoire à la
/// première connexion. Vide (défaut) : seul l'administrateur reçoit un mot de passe provisoire aléatoire, affiché sur l'écran de connexion.
const String motDePasseDemo =
    String.fromEnvironment('SIGH_MDP_DEMO', defaultValue: '');

/// `SIGH_REPARTIR_A_ZERO=oui` : DÉVELOPPEMENT. Met de côté le magasin enregistré du poste (comptes, saisies) et repart du jeu d'origine. Le dossier n'est
/// pas supprimé : il est renommé `magasin.ancien-<date>`.
const String repartirAZero =
    String.fromEnvironment('SIGH_REPARTIR_A_ZERO', defaultValue: 'non');

/// `SIGH_ASSISTANT=non` : DÉVELOPPEMENT. Pas d'assistant de première installation : le poste garde l'ancien chemin (administrateur `admin.systeme` avec un mot
/// de passe provisoire affiché sur l'écran de connexion). Par défaut, un poste sans compte connectable démarre sur l'assistant.
const String assistantInstallation =
    String.fromEnvironment('SIGH_ASSISTANT', defaultValue: 'oui');

/// `SIGH_CHIFFREMENT=non` : DÉVELOPPEMENT. Garde le magasin du poste en JSON clair. Par défaut, les fichiers sont chiffrés.
const String chiffrementActif =
    String.fromEnvironment('SIGH_CHIFFREMENT', defaultValue: 'oui');

/// `SIGH_DONNEES` : DÉVELOPPEMENT et tests. Fixe le dossier des données tel quel. Absent, le dossier est celui du système (`%LOCALAPPDATA%\SIGHCNT\donnees`).
const String donneesSurcharge = String.fromEnvironment('SIGH_DONNEES');

/// Dossier des données du poste, résolu AU DÉMARRAGE par [preparerDossierDonnees] (jamais dans le dossier d'installation).
String dossierDonnees = 'donnees-poste';

/// La session du démarrage : la connexion est EXIGÉE sauf `SIGH_CONNEXION=non` (tests et développement). [connexion] surcharge la constante de compilation
/// pour les tests.
SessionPoste? sessionDemarrage({String connexion = connexionExigee, DateTime Function()? horloge}) =>
    connexion != 'non' ? SessionPoste(exigeConnexion: true, horloge: horloge) : null;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    dossierDonnees = await preparerDossierDonnees(
        resoudreDossierDonnees(surcharge: donneesSurcharge, env: Platform.environment, windows: Platform.isWindows));
  } on DossierDonneesInutilisable catch (e) {
    // Un refus NOMMÉ à l'écran : le poste ne démarre pas sur une base qu'il ne saura pas ouvrir.
    runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: SelectableText('SIGH-CNT ne peut pas démarrer.\n\n${e.motif}'))))));
    return;
  }
  // La fenêtre pilotable : un poste sans fenêtre native n'empêche pas le démarrage. Le poste se lance MAXIMISÉ (Direction, 02/11/2026 ; le plein écran du 01/11 reste à la demande) ; si la
  // plateforme refuse, le repli est nommé et la coque le dit au premier affichage. F11 et la barre supérieure basculent ensuite.
  FenetreSysteme? fenetre;
  try {
    await windowManager.ensureInitialized();
    fenetre = FenetreSysteme();
    if (pleinEcranAuDemarrage != 'non') {
      await fenetre.demarrerPleinEcran();
    } else {
      await windowManager.waitUntilReadyToShow(const WindowOptions(title: 'SIGH-CNT'), () async {
        await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
      });
    }
  } catch (_) {}
  // LA CLÉ DU POSTE, d'abord : elle chiffre les fichiers du magasin ET les bases SQLite de la synchronisation (la mère et le journal de ce poste), qui portent
  // tout autant les dossiers des patients. Sans chiffrement (`SIGH_CHIFFREMENT=non`), tout reste en clair, pour le développement seulement.
  final cle = chiffrementActif != 'non' ? await CleLocale('$dossierDonnees/cle-poste.bin').obtenir() : null;
  final cleSqlite = cle == null ? '' : cle.map((o) => o.toRadixString(16).padLeft(2, '0')).join();
  final stockage = StockageFichier('$dossierDonnees/poste.json', cle: cle);
  final activation = ActivationMere(
    stockage: stockage,
    service: ServiceMereLocal(ConfigMere(
        port: 9000,
        dbChemin: '$dossierDonnees/mere.db',
        admin: secretAdmin.isEmpty ? 'admin-local' : secretAdmin,
        cleStockage: cleSqlite,
        dossierSauvegardes: '$dossierDonnees/sauvegardes')),
    relaisPour: (relais, secret) => RelaisMereHttp(
        base: Uri.parse(relais), secretMere: secret, client: http.Client()),
  );
  var params = await activation.parametres();
  if (params.mode == ModePoste.fileul &&
      modeAmorcage == 'mere' &&
      params.activeDepuis == null) {
    params = params.avec(mode: ModePoste.mere);
  }
  final controleur = ControleurPoste(
      activation: activation,
      config: ConfigPoste(
          mode: params.mode, role: roleDev, nomPoste: params.nomPoste));
  if (params.mode == ModePoste.mere) {
    // Redémarrage d'une mère : le service repart (la place au relais est déjà la sienne).
    await activation.service.demarrer();
  }
  // Un poste RATTACHÉ à une clinique parle à SA mère (adresse enregistrée), pas à l'adresse de compilation.
  final moteur = MoteurFileul.creer(
      dbChemin: '$dossierDonnees/poste.db',
      cleStockage: cleSqlite,
      mere: params.rejoint && params.adresseMere.isNotEmpty ? params.adresseMere : adresseMere)
    ..demarrer();
  final magasin = await Magasin.depuisAssets(Magasin.collectionsDuJeu);
  // Le magasin se range sur disque : comptes, mots de passe (hachés), saisies et journal survivent à la fermeture du poste. Sans cela, tout repartait du
  // jeu d'origine à chaque lancement. Les fichiers sont en clair (le chiffrement SQLCipher est l'étape suivante du plan).
  // Les fichiers sont CHIFFRÉS (AES-256-GCM, clé liée à la session Windows par DPAPI) ; `SIGH_CHIFFREMENT=non` les garde en clair (développement).
  if (chiffrementActif != 'non') {
    CleLocale.courante = CleLocale('$dossierDonnees/cle-poste.bin');
    // La même clé locale protège la clé de la clinique dans `pair.json` (jamais en clair sur le disque).
    ConfigPairPoste.cleLocale = await CleLocale.courante!.obtenir();
  }
  final persistance = PersistanceFichiers('$dossierDonnees/magasin', cle: cle);
  if (repartirAZero == 'oui') await persistance.mettreDeCote();
  // Un jeu d'origine qui change (nouvelle version) n'écrase rien : ses fiches de référentiel manquantes sont ajoutées au magasin enregistré.
  await magasin.brancherPersistance(persistance, fusionnables: {...cfbEssentielles}.difference({'utilisateurs', 'identifiants'}));
  CfbPersistance.disponible = () => true;
  for (final probleme in persistance.problemes) {
    debugPrint(probleme);
  }
  AppLifecycleListener(onStateChange: (e) {
    if (e != AppLifecycleState.resumed) magasin.ecrireMaintenant();
  });
  // E1559 : les prescriptions que les téléphones des soignants envoient par la mère sont TRANSCRITES ici (ordonnance, facture de la caisse, files
  // d'aval) par le moteur de la fiche de consultation ; une pièce non transcriptible est refusée en le disant.
  if (connexionExigee != 'non' && assistantInstallation != 'non' && motDePasseDemo.isEmpty) {
    // Poste neuf : l'assistant propose « Première installation » ou « Rejoindre une clinique ». L'état d'installation vit dans les paramètres du poste.
    final installation = ServiceInstallation.de(magasin);
    await installation.attacher(stockage, await activation.parametres());
    // MÈRE : ses configurations et ses comptes partent vers le relais et les fileuls par le journal. FILEUL RATTACHÉ : il les reprend.
    PublicateurConfiguration? publicateur;
    void demarrerPublication() => publicateur ??= PublicateurConfiguration(
        magasin, publierVersMereLocale(port: 9000, admin: secretAdmin.isEmpty ? 'admin-local' : secretAdmin))
      ..demarrer();
    // L'ACTIVITÉ et les mots de passe voyagent dans les deux sens (pont magasin / journal, E2130 à E2134).
    PontActivite? pontMere, pontFileul;
    void demarrerPontMere() {
      final transport = TransportMereLocale(port: 9000, admin: secretAdmin.isEmpty ? 'admin-local' : secretAdmin);
      // La mère prend ses numéros de dossier dans le même carnet que les fileuls (RG-01).
      PlagesCodes.de(magasin).obtenir = transport.plage;
      ReservationStock.de(magasin)
        ..actif = true
        ..installer(magasin);
      unawaited(PlagesCodes.de(magasin).recharger());
      pontMere ??= PontActivite(magasin, transport, etiquette: 'M', surveillerLesAutres: true)..demarrer();
    }
    PontActivite creerPontFileul() => PontActivite(
        magasin,
        TransportFileul(
            lire: moteur.liste,
            ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        enLectureSeule: collectionsDeLaMereSeule,
        liaison: () async {
          final i = await moteur.instantane();
          return !i.horsLigne && !i.suspendu;
        },
        etiquette: moteur.uuid.replaceAll('-', '').substring(0, 6))
      ..demarrer();
    void demarrerPontFileul() {
      PlagesCodes.de(magasin).obtenir = (taille, minimum) => moteur.demanderPlage(taille: taille, minimum: minimum);
      ReservationStock.de(magasin)
        ..actif = true
        ..installer(magasin);
      unawaited(PlagesCodes.de(magasin).recharger());
      pontFileul ??= creerPontFileul();
    }
    ApplicateurConfiguration? applicateur;
    void demarrerApplication() => applicateur ??= ApplicateurConfiguration(magasin, moteur.liste)..demarrer();
    void demarrerApplicationEtPont() {
      demarrerApplication();
      demarrerPontFileul();
    }
    installation.activerMere = ({required relais, required secretMere, required cleClinique, nomPoste}) async {
      await controleur.activer(relais: relais, secretMere: secretMere, cleClinique: cleClinique, nomPoste: nomPoste);
      demarrerPublication();
      demarrerPontMere();
    };
    // La détection de l'étape « appairages » : combien d'appareils la mère connaît (sa console, sur le port local de son service).
    final consoleMere = ClientMere(base: Uri.parse('http://127.0.0.1:9000'), secretAdmin: secretAdmin.isEmpty ? 'admin-local' : secretAdmin);
    installation.compterAppareils = () async => (await consoleMere.etat()).appareils.length;
    installation.rattacherMoteur = ({required adresse, required code}) => moteur.rattacher(adresse, code);
    installation.surRattache = (_) => demarrerApplicationEtPont();
    if (params.mode == ModePoste.mere) {
      demarrerPublication();
      demarrerPontMere();
    }
    if (installation.rattache) demarrerApplicationEtPont();
  } else if (connexionExigee != 'non') {
    final ident = ServiceIdentifiants.de(magasin);
    final maintenant = DateTime.now();
    if (motDePasseDemo.isEmpty) {
      ServiceIdentifiants.provisoireAffiche =
          await ident.amorcerAdministrateur(maintenant: maintenant);
    } else {
      for (final u in magasin.collection('utilisateurs').toutes) {
        if ('${u['statut'] ?? 'actif'}' != 'actif') continue;
        await ident.definir('${u['id'] ?? u['identifiant']}', motDePasseDemo,
            par: 'Mise en service (démonstration)',
            doitChanger: true,
            maintenant: maintenant);
      }
    }
  }
  ServiceTranscriptionMobile(magasin: magasin, source: moteur.pieces).demarrer();
  final session = sessionDemarrage();
  // MODE PAIR (ADR-0006) : seulement si `pair.json` l'active. Les écritures du poste passent par le moteur pair, le relais ne voit que des enveloppes chiffrées.
  MoteurPair? moteurPair;
  EtatPairPoste.dossier = dossierDonnees;
  EtatSmtpPoste.dossier = dossierDonnees;
  try {
    final cp = ConfigPairPoste.lire(dossierDonnees);
    if (cp != null) {
      // Les droits de l'échange viennent de la MATRICE RBAC engendrée (la même que celle de la navigation), plus de la table du banc.
      final matrice = (await DonneesNavigation.chargerAssets()).matrice;
      moteurPair = MoteurPair.creer(
          magasin: magasin,
          dbChemin: '$dossierDonnees/pair.db',
          relais: cp.relais,
          cleHex: cp.cleHex,
          nom: cp.nom,
          droits: droitsDepuisMatrice(peutEditer: matrice.peutEditer, peutAnnuler: matrice.peutAnnuler));
      if (!moteurPair.appaire && cp.code != null) {
        try {
          await moteurPair.appairer(cp.code!);
          // Le code est à usage unique : consommé, il ne reste pas sur le disque.
          ConfigPairPoste.ecrire(dossierDonnees, code: '');
        } catch (e) {
          debugPrint('mode pair : $e');
        }
      }
      moteurPair
        ..demarrer()
        ..pont(role: () => session?.role ?? roleDev).demarrer();
      final etatPair = ValueNotifier<InstantanePair>(InstantanePair.depuis(moteurPair.etat()));
      EtatPairPoste.source = etatPair;
      EtatPairPoste.jeton = () => moteurPair?.jeton;
      final suivi = moteurPair;
      Timer.periodic(const Duration(seconds: 2), (_) => etatPair.value = InstantanePair.depuis(suivi.etat()));
    }
  } on FormatException catch (e) {
    debugPrint('mode pair non démarré : ${e.message}');
  }
  runApp(SighPoste(
      controleur: controleur,
      donnees: await DonneesNavigation.chargerAssets(),
      magasin: magasin,
      session: session,
      ouvrirTrancher: moteurPair == null
          ? null
          : (context) => ouvrirModaleTrancher(context, magasin: magasin, moteur: moteurPair!, role: session?.role ?? roleDev),
      fenetre: fenetre,
      etatSync: moteur.source()));
}

class SighPoste extends StatelessWidget {
  const SighPoste(
      {super.key,
      required this.donnees,
      this.config,
      this.controleur,
      this.client,
      this.etatSync,
      this.ouvrirTrancher,
      this.magasin,
      this.horloge,
      this.ecranInitial,
      this.session,
      this.fenetre,
      this.parametres = const {}});

  /// La fenêtre du poste (plein écran) ; absente = la fenêtre réelle.
  final FenetrePoste? fenetre;

  /// Session du poste (connexion, verrou d'inactivité) ; absente = l'agent est réputé connecté sous le rôle de la configuration.
  final SessionPoste? session;

  /// Paramètres de l'adresse d'un écran autonome (`jeton` de la page publique d'enquête).
  final Map<String, String> parametres;

  /// Données de navigation engendrées (manifeste, droits, parité).
  final DonneesNavigation donnees;

  /// Injectables pour les tests. `controleur` : mode vivant (production). `config` : mode figé (tests de la coque).
  final ConfigPoste? config;
  final ControleurPoste? controleur;
  final ClientMere? client;
  final SourceEtatSync? etatSync;

  /// Ouvre la modale « Conflits à trancher » (présente seulement si le mode pair est actif).
  final Future<void> Function(BuildContext)? ouvrirTrancher;
  final String? ecranInitial;

  /// Données des écrans portés (jeu de démonstration ; la base locale viendra derrière la même interface).
  final Magasin? magasin;
  final DateTime Function()? horloge;

  @override
  Widget build(BuildContext context) {
    final ecoute = controleur;
    return MaterialApp(
      title: 'SIGH-CNT',
      debugShowCheckedModeBanner: false,
      theme: ThemeSigh.clair(),
      home: ecoute == null
          ? _coque(
              config ??
                  ConfigPoste(
                      mode: client != null
                          ? ModePoste.mere
                          : ConfigPoste.modeDepuis(modeAmorcage)),
              null)
          : ListenableBuilder(
              listenable: ecoute,
              builder: (_, __) => _coque(ecoute.config, ecoute)),
    );
  }

  Widget _coque(ConfigPoste cfg, ControleurPoste? ctl) {
    final cl = cfg.estMere
        ? (client ??
            ClientMere(base: Uri.parse(adresseMere), secretAdmin: secretAdmin))
        : null;
    return CoquePoste(
      key: ValueKey(cfg.mode),
      config: cfg,
      donnees: donnees,
      ecranInitial: ecranInitial,
      session: session,
      fenetre: fenetre,
      parametres: parametres,
      ouvrirTrancher: ouvrirTrancher,
      ecrans: ecransPortes(controleur: ctl, client: cl),
      magasin: magasin,
      horloge: horloge,
      etatSync: etatSync ??
          ValueNotifier(const EtatSync(niveau: NiveauSync.horsLigne)),
    );
  }
}
