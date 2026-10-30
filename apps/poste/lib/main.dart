import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_sync/sigh_sync.dart';

import 'core/config_poste.dart';
import 'core/controleur_poste.dart';
import 'core/donnees_navigation.dart';
import 'core/parametres_poste.dart';
import 'core/theme.dart';
import 'mere/activation.dart';
import 'mere/client_mere.dart';
import 'modules/registre.dart';
import 'shell/coque.dart';
import 'sync/etat_sync.dart';
import 'sync/moteur_fileul.dart';

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

/// Dossier des données du poste. À remplacer par le dossier d'application du système à l'installation (tâche de packaging).
const String dossierDonnees =
    String.fromEnvironment('SIGH_DONNEES', defaultValue: 'donnees-poste');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(SighPoste(
      controleur: controleur,
      donnees: await DonneesNavigation.chargerAssets(),
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
      this.ecranInitial});

  /// Données de navigation engendrées (manifeste, droits, parité).
  final DonneesNavigation donnees;

  /// Injectables pour les tests. `controleur` : mode vivant (production). `config` : mode figé (tests de la coque).
  final ConfigPoste? config;
  final ControleurPoste? controleur;
  final ClientMere? client;
  final SourceEtatSync? etatSync;
  final String? ecranInitial;

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
      ecrans: ecransPortes(controleur: ctl, client: cl),
      etatSync: etatSync ??
          ValueNotifier(const EtatSync(niveau: NiveauSync.horsLigne)),
    );
  }
}
