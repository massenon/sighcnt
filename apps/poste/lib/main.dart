import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_sync/sigh_sync.dart';
import 'package:window_manager/window_manager.dart';

import 'donnees/magasin.dart';
import 'core/config_poste.dart';
import 'core/controleur_poste.dart';
import 'core/donnees_navigation.dart';
import 'core/parametres_poste.dart';
import 'core/theme.dart';
import 'mere/activation.dart';
import 'mere/client_mere.dart';
import 'modules/auth/acc_session.dart';
import 'modules/registre.dart';
import 'shell/coque.dart';
import 'shell/fenetre_poste.dart';
import 'sync/etat_sync.dart';
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

/// `SIGH_PLEIN_ECRAN=non` : ne pas passer en plein écran au démarrage (développement). Par défaut le poste se lance en plein écran.
const String pleinEcranAuDemarrage =
    String.fromEnvironment('SIGH_PLEIN_ECRAN', defaultValue: 'oui');

/// Dossier des données du poste. À remplacer par le dossier d'application du système à l'installation (tâche de packaging).
const String dossierDonnees =
    String.fromEnvironment('SIGH_DONNEES', defaultValue: 'donnees-poste');

/// La session du démarrage : la connexion est EXIGÉE sauf `SIGH_CONNEXION=non` (tests et développement). [connexion] surcharge la constante de compilation
/// pour les tests.
SessionPoste? sessionDemarrage({String connexion = connexionExigee, DateTime Function()? horloge}) =>
    connexion != 'non' ? SessionPoste(exigeConnexion: true, horloge: horloge) : null;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La fenêtre pilotable : un poste sans fenêtre native n'empêche pas le démarrage. Le poste se lance en PLEIN ÉCRAN (Direction, 01/11/2026) ; si la
  // plateforme refuse, le repli est nommé et la coque le dit au premier affichage. F11 et la barre supérieure basculent ensuite.
  FenetreSysteme? fenetre;
  try {
    await windowManager.ensureInitialized();
    fenetre = FenetreSysteme();
    if (pleinEcranAuDemarrage != 'non') await fenetre.demarrerPleinEcran();
  } catch (_) {}
  final stockage = StockageFichier('$dossierDonnees/poste.json');
  final activation = ActivationMere(
    stockage: stockage,
    service: ServiceMereLocal(ConfigMere(
        port: 9000,
        dbChemin: '$dossierDonnees/mere.db',
        admin: secretAdmin.isEmpty ? 'admin-local' : secretAdmin,
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
  final moteur = MoteurFileul.creer(
      dbChemin: '$dossierDonnees/poste.db', mere: adresseMere)
    ..demarrer();
  final magasin = await Magasin.depuisAssets(Magasin.collectionsDuJeu);
  // E1559 : les prescriptions que les téléphones des soignants envoient par la mère sont TRANSCRITES ici (ordonnance, facture de la caisse, files
  // d'aval) par le moteur de la fiche de consultation ; une pièce non transcriptible est refusée en le disant.
  ServiceTranscriptionMobile(magasin: magasin, source: moteur.pieces).demarrer();
  runApp(SighPoste(
      controleur: controleur,
      donnees: await DonneesNavigation.chargerAssets(),
      magasin: magasin,
      session: sessionDemarrage(),
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
      ecrans: ecransPortes(controleur: ctl, client: cl),
      magasin: magasin,
      horloge: horloge,
      etatSync: etatSync ??
          ValueNotifier(const EtatSync(niveau: NiveauSync.horsLigne)),
    );
  }
}
