import 'package:flutter/material.dart';

import 'package:sigh_domaine/sigh_domaine.dart' show mobMentionAValider, mobRefusAValider;

import '../core/theme.dart';
import '../moteur/moteur_mobile.dart';

/// « À traiter » : chaque refus de la mère dit POURQUOI (motif) et QUOI FAIRE (geste). Rien n'est perdu : l'opération reste sur le téléphone,
/// elle n'est jamais rejouée telle quelle.
class ATraiter extends StatelessWidget {
  const ATraiter({super.key, required this.moteur});
  final MoteurMobile moteur;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('À traiter')),
      body: FutureBuilder<List<RefusAffiche>>(
        future: moteur.aTraiter(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final l = snap.data!;
          if (l.isEmpty) return const Center(child: Text('Aucun refus.', key: Key('a-traiter-vide')));
          return ListView(children: [
            for (final r in l)
              ListTile(
                key: Key('refus-${r.operation}'),
                leading: Icon(Icons.report_gmailerrorred, color: ThemeSigh.danger),
                title: Text(r.motif),
                subtitle: Text('À faire : ${r.geste}\n${r.code}${mobRefusAValider(r.code) ? '\n$mobMentionAValider' : ''}'),
                isThreeLine: true,
              ),
          ]);
        },
      ),
    );
  }
}
