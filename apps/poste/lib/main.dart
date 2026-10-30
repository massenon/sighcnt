import 'package:flutter/material.dart';

import 'core/config_poste.dart';
import 'core/theme.dart';
import 'mere/client_mere.dart';
import 'modules/module_sigh.dart';
import 'modules/registre.dart';
import 'shell/coque.dart';
import 'sync/etat_sync.dart';
import 'sync/moteur_fileul.dart';

/// Mode du poste (`--dart-define=SIGH_MODE=mere`). En production il viendra du fichier de configuration du poste ;
/// l'exécutable est le MÊME dans les deux cas.
const String modeSigh = String.fromEnvironment('SIGH_MODE', defaultValue: 'fileul');
const String adresseMere = String.fromEnvironment('SIGH_MERE', defaultValue: 'http://127.0.0.1:9000');
const String secretAdmin = String.fromEnvironment('SIGH_ADMIN', defaultValue: '');

/// Fichier SQLite du poste fileul. À remplacer par le dossier de données de l'application à l'installation (T8).
const String cheminBase = String.fromEnvironment('SIGH_DB', defaultValue: 'sigh-poste.db');

void main() {
  // Poste fileul : le moteur de synchronisation tourne dans l'application et alimente la pastille.
  // (Le moteur de la MÈRE est un service séparé ; la console le pilote par son API.)
  if (ConfigPoste.modeDepuis(modeSigh) == ModePoste.fileul) {
    final moteur = MoteurFileul.creer(dbChemin: cheminBase, mere: adresseMere)..demarrer();
    runApp(SighPoste(etatSync: moteur.source()));
  } else {
    runApp(const SighPoste());
  }
}

class SighPoste extends StatelessWidget {
  const SighPoste({super.key, this.config, this.client, this.etatSync, this.droit});

  /// Injectables pour les tests ; en production, le client vise le service local de la mère.
  final ConfigPoste? config;
  final ClientMere? client;
  final SourceEtatSync? etatSync;

  /// Filtre de droits (matrice RBAC) ; absent = tous les modules du mode.
  final bool Function(ModuleSigh)? droit;

  @override
  Widget build(BuildContext context) {
    final cfg = config ?? ConfigPoste(mode: client != null ? ModePoste.mere : ConfigPoste.modeDepuis(modeSigh));
    final tous = [
      ...modulesCommuns(),
      if (cfg.estMere) ...modulesMere(client ?? ClientMere(base: Uri.parse(adresseMere), secretAdmin: secretAdmin)),
    ];
    return MaterialApp(
      title: 'SIGH-CNT',
      debugShowCheckedModeBanner: false,
      theme: ThemeSigh.clair(),
      home: CoquePoste(
        config: cfg,
        modules: modulesVisibles(cfg, tous: tous, droit: droit),
        etatSync: etatSync ?? ValueNotifier(const EtatSync(niveau: NiveauSync.horsLigne)),
      ),
    );
  }
}
