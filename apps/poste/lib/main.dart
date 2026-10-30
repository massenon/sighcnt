import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'mere/client_mere.dart';
import 'mere/console.dart';
import 'sync/etat_sync.dart';

/// Mode de l'application : fileul (défaut) ou mère. Fixé à la compilation (`--dart-define=SIGH_MODE=mere`).
const String modeSigh = String.fromEnvironment('SIGH_MODE', defaultValue: 'fileul');
const String adresseMere = String.fromEnvironment('SIGH_MERE', defaultValue: 'http://127.0.0.1:9000');
const String secretAdmin = String.fromEnvironment('SIGH_ADMIN', defaultValue: '');

void main() => runApp(const SighPoste());

class SighPoste extends StatelessWidget {
  const SighPoste({super.key, this.client, this.etatSync});

  /// Injectables pour les tests ; en production, le client vise le service local de la mère.
  final ClientMere? client;
  final SourceEtatSync? etatSync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIGH-CNT',
      debugShowCheckedModeBanner: false,
      theme: ThemeSigh.clair(),
      home: modeSigh == 'mere' || client != null
          ? ConsoleMere(client: client ?? ClientMere(base: Uri.parse(adresseMere), secretAdmin: secretAdmin))
          : AccueilPoste(etatSync: etatSync ?? ValueNotifier(const EtatSync(niveau: NiveauSync.horsLigne))),
    );
  }
}

/// Coque du poste fileul : les modules viendront par tranches verticales (docs/architecture/PARITE-MAQUETTE.md).
class AccueilPoste extends StatelessWidget {
  const AccueilPoste({super.key, required this.etatSync});
  final SourceEtatSync etatSync;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SIGH-CNT — poste (fileul)'), actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: PastilleSync(source: etatSync)))]),
      body: const Center(child: Text('Aucun module porté pour l’instant — première tranche : caisse + MECeF + impression.')),
    );
  }
}
