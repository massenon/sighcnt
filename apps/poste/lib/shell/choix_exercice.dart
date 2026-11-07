import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';

/// LE CHOIX D'EXERCICE DE LA SESSION (arbitrage du 05/11/2026), miroir de `sigh-cnt:exercice` de la maquette : tenu EN MÉMOIRE pour la session du poste, jamais
/// écrit dans le magasin. Absent, l'exercice affiché est le plus récent encore ouvert ([cpcExerciceParDefaut]). Une nouvelle session repart du défaut.
class ChoixExercice {
  ChoixExercice._();
  static final ValueNotifier<int?> valeur = ValueNotifier<int?>(null);

  static void reinitialiser() => valeur.value = null;

  /// L'exercice effectivement affiché, d'après la liste des exercices du magasin (vide : l'année de l'horloge).
  static int courant(Magasin m, DateTime aujourdhui) {
    final exos = m.collection('exercices').actives;
    if (exos.isEmpty) return aujourdhui.year;
    return cpcExerciceChoisi(exos, valeur.value, aujourdhui);
  }
}

/// Le sélecteur de la barre supérieure : ‹ Exercice N · état ›. Les flèches sont ABSENTES aux bornes (pas d'exercice voisin), jamais grisées.
class SelecteurExercice extends StatelessWidget {
  const SelecteurExercice({super.key, required this.magasin, required this.aujourdhui});
  final Magasin magasin;
  final DateTime aujourdhui;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: ChoixExercice.valeur,
      builder: (_, __, ___) {
        final exos = magasin.collection('exercices').actives;
        if (exos.isEmpty) return const SizedBox.shrink();
        final annee = ChoixExercice.courant(magasin, aujourdhui);
        final etat = cpcEtatExercice(magasin.collection('exercices').toutes, annee);
        final prec = cpcExerciceVoisin(exos, annee, -1);
        final suiv = cpcExerciceVoisin(exos, annee, 1);
        final libelleEtat = switch (etat) { 'clos' => 'clos', 'en_cloture' => 'en clôture', _ => 'ouvert' };
        Widget fleche(String cle, IconData i, String info, int? vers) => vers == null
            ? const SizedBox(width: 4)
            : Tooltip(
                message: info,
                child: InkWell(
                    key: Key(cle),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => ChoixExercice.valeur.value = vers,
                    child: Padding(padding: const EdgeInsets.all(4), child: Icon(i, size: 16, color: JetonsShell.navy200))));
        return Semantics(
          label: 'Exercice comptable $annee, $libelleEtat',
          child: Container(
            key: const Key('selecteur-exercice'),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF), border: Border.all(color: const Color(0x26FFFFFF)), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              fleche('exercice-precedent', LucideIcons.chevronLeft, 'Exercice ${annee - 1}', prec),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Exercice $annee · $libelleEtat',
                      key: const Key('exercice-affiche'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
              fleche('exercice-suivant', LucideIcons.chevronRight, 'Exercice ${annee + 1}', suiv),
            ]),
          ),
        );
      },
    );
  }
}
