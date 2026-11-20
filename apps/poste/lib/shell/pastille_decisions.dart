import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/theme.dart';
import '../donnees/magasin.dart';

/// LA PASTILLE « N DÉCISIONS EN ATTENTE DE LA MÈRE » (lot CONT, exigence de la Direction du 14/11/2026). Une décision de validation signée sur ce poste, une demande de prix ou une demande
/// d'import déposée attend que la mère l'applique : c'est un ÉTAT
/// dit en clair (le nombre RÉEL, jamais zéro quand il y en a, et l'âge de la plus ancienne), jamais un verrou. Absente quand rien n'attend. Elle est lue des collections `demandesValidation`, `propositionsTarif` et `demandesImport`,
/// donc se met à jour seule dès que le verdict de la mère revient.
class PastilleDecisions extends StatefulWidget {
  const PastilleDecisions({super.key, required this.magasin, this.maintenant});
  final Magasin magasin;

  /// Injectable pour les tests.
  final DateTime Function()? maintenant;

  @override
  State<PastilleDecisions> createState() => _EtatPastilleDecisions();
}

class _EtatPastilleDecisions extends State<PastilleDecisions> {
  Timer? _minuterie;

  @override
  void initState() {
    super.initState();
    // L'âge avance même quand rien ne change dans la collection.
    _minuterie = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const noms = [valCollectionDemandes, 'propositionsTarif', 'demandesImport'];
    final m = widget.magasin;
    return ListenableBuilder(
      listenable: Listenable.merge([for (final n in noms) m.collection(n)]),
      builder: (context, _) {
        final s = valSyntheseToutesAttentes({for (final n in noms) n: m.collection(n).toutes}, (widget.maintenant ?? DateTime.now)());
        if (s.nombre == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Semantics(
            label: s.libelle,
            child: Tooltip(
              message: 'Les décisions signées sur ce poste sont appliquées par la mère dès qu’elle est joignable. Le travail continue.',
              child: Container(
                key: const Key('pastille-decisions'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: ThemeSigh.attentionFond, borderRadius: BorderRadius.circular(999)),
                child: Text(s.libelle, style: TextStyle(color: ThemeSigh.attention, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ),
          ),
        );
      },
    );
  }
}
