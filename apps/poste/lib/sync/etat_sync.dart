import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Ce que l'agent doit pouvoir lire à tout instant (spec §5.8, EF-SYNC-14) : jamais un voyant muet.
enum NiveauSync { synchronise, enCours, enRetard, horsLigne, suspendu }

class EtatSync {
  const EtatSync(
      {required this.niveau,
      this.enAttente = 0,
      this.aTraiter = 0,
      this.depuis});
  final NiveauSync niveau;

  /// Opérations saisies localement qui n'ont pas encore été acceptées par la mère.
  final int enAttente;

  /// Refus de la mère : cause nommée et geste de correction à l'écran « À traiter ».
  final int aTraiter;

  /// Début de la situation courante (hors ligne depuis…, retard depuis…).
  final DateTime? depuis;

  String get libelle {
    switch (niveau) {
      case NiveauSync.synchronise:
        return 'Synchronisé';
      case NiveauSync.enCours:
        return 'Synchronisation…';
      case NiveauSync.enRetard:
        return 'En retard';
      case NiveauSync.horsLigne:
        return 'Hors ligne';
      case NiveauSync.suspendu:
        return 'Poste suspendu';
    }
  }
}

/// Source d'état : l'interface ne connaît pas le moteur (`sigh_sync`), elle écoute une valeur.
typedef SourceEtatSync = ValueListenable<EtatSync>;

class PastilleSync extends StatelessWidget {
  const PastilleSync({super.key, required this.source, this.maintenant});
  final SourceEtatSync source;

  /// Injectable pour les tests.
  final DateTime Function()? maintenant;

  (Color, Color) _couleurs(NiveauSync n) => switch (n) {
        NiveauSync.synchronise => (ThemeSigh.succes, ThemeSigh.succesFond),
        NiveauSync.enCours => (ThemeSigh.navy, ThemeSigh.navyDoux),
        NiveauSync.enRetard => (ThemeSigh.attention, ThemeSigh.attentionFond),
        NiveauSync.horsLigne => (ThemeSigh.attention, ThemeSigh.attentionFond),
        NiveauSync.suspendu => (ThemeSigh.danger, ThemeSigh.dangerFond),
      };

  String _duree(Duration d) {
    if (d.inMinutes >= 60) return '${d.inHours} h ${d.inMinutes % 60} min';
    if (d.inMinutes >= 1) return '${d.inMinutes} min';
    return '${d.inSeconds} s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EtatSync>(
      valueListenable: source,
      builder: (context, e, _) {
        final (texte, fond) = _couleurs(e.niveau);
        final maintenantFn = maintenant ?? DateTime.now;
        final details = <String>[
          if (e.depuis != null && e.niveau != NiveauSync.synchronise)
            'depuis ${_duree(maintenantFn().difference(e.depuis!))}',
          if (e.enAttente > 0) '${e.enAttente} en attente',
          if (e.aTraiter > 0) '${e.aTraiter} à traiter',
        ];
        final label = [e.libelle, ...details].join(' · ');
        return Semantics(
          label: 'État de la synchronisation : $label',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: fond, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 10, color: texte),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: texte, fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
          ),
        );
      },
    );
  }
}
