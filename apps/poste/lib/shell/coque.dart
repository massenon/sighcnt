import 'package:flutter/material.dart';

import '../core/config_poste.dart';
import '../modules/module_sigh.dart';
import '../sync/etat_sync.dart';

/// Coque unique du poste (fileul et mère) : barre latérale DÉRIVÉE du registre, pastille de synchronisation permanente.
class CoquePoste extends StatefulWidget {
  const CoquePoste({super.key, required this.config, required this.modules, required this.etatSync});
  final ConfigPoste config;
  final List<ModuleSigh> modules;
  final SourceEtatSync etatSync;

  @override
  State<CoquePoste> createState() => _CoquePosteState();
}

class _CoquePosteState extends State<CoquePoste> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final modules = widget.modules;
    final libelleMode = widget.config.estMere ? 'poste mère' : 'poste fileul';
    if (modules.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text('SIGH-CNT — $libelleMode')), body: const Center(child: Text('Aucun module n’est ouvert à votre profil.')));
    }
    final courant = modules[_index.clamp(0, modules.length - 1)];
    return Scaffold(
      appBar: AppBar(
        title: Text('SIGH-CNT — $libelleMode'),
        actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: PastilleSync(source: widget.etatSync)))],
      ),
      body: Row(children: [
        NavigationRail(
          key: const Key('navigation'),
          extended: MediaQuery.of(context).size.width >= 1000,
          selectedIndex: _index.clamp(0, modules.length - 1),
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [for (final m in modules) NavigationRailDestination(icon: Icon(m.icone), label: Text(m.libelle))],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: KeyedSubtree(key: ValueKey(courant.id), child: courant.construire(context, widget.config))),
      ]),
    );
  }
}
