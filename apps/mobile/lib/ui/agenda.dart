import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../moteur/moteur_mobile.dart';
import 'dossier.dart';

/// L'agenda du jour, lu dans le lot (rendez-vous et visites de la tournée), du plus tôt au plus tard. Un rendez-vous planifié d'un jour passé est
/// SIGNALÉ à part : le téléphone ne tranche pas une absence.
class AgendaJour extends StatefulWidget {
  const AgendaJour({super.key, required this.moteur});
  final MoteurMobile moteur;

  @override
  State<AgendaJour> createState() => _AgendaJourState();
}

class _AgendaJourState extends State<AgendaJour> {
  late Future<AgendaDuJour> _agenda = widget.moteur.soignant!.agenda();

  Widget _ligne(LigneAgenda l, int i, String prefixe) => ListTile(
        key: Key('$prefixe-$i'),
        leading: Text(l.heure.isEmpty ? '--' : l.heure, style: const TextStyle(fontWeight: FontWeight.w700)),
        title: Text(l.patient),
        subtitle: Text([if (l.motif.isNotEmpty) l.motif, if (l.type.isNotEmpty) l.type, l.statut].join(' · ')),
        trailing: l.patientId == null ? null : const Icon(Icons.chevron_right),
        onTap: l.patientId == null
            ? null
            : () async {
                await ouvrirDossier(context, widget.moteur, l.patientId!);
                if (mounted) {
                  setState(() {
                    _agenda = widget.moteur.soignant!.agenda();
                  });
                }
              },
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AgendaDuJour>(
      future: _agenda,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final a = snap.data!;
        if (a.duJour.isEmpty && a.enSouffrance.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Aucun rendez-vous aujourd’hui dans le lot de ce téléphone.', key: Key('agenda-vide'), textAlign: TextAlign.center)));
        }
        return ListView(children: [
          if (a.duJour.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Rien de prévu aujourd’hui.', key: Key('agenda-vide'))),
          for (final (i, l) in a.duJour.indexed) _ligne(l, i, 'rdv'),
          if (a.enSouffrance.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Planifiés d’un jour passé, à confirmer', key: const Key('en-souffrance'), style: TextStyle(color: ThemeSigh.attention, fontWeight: FontWeight.w700)),
            ),
            for (final (i, l) in a.enSouffrance.indexed) _ligne(l, i, 'souffrance'),
          ],
        ]);
      },
    );
  }
}
