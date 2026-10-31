import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/icones.dart';
import '../kit/bouton.dart';

String _norm(String x) =>
    normaliser(x).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// `accesRapides()` de la maquette : jusqu'à TROIS raccourcis en tête de page, DÉDUITS du manifeste — les voisins du module (dans l'ordre du
/// ruban), puis l'accueil du module — filtrés par les droits (le ruban l'est déjà : jamais de lien vers un écran interdit au profil). Les actions
/// que l'écran déclare passent en premier et ne sont JAMAIS reproposées sous le même libellé : deux boutons identiques font douter qu'ils
/// fassent la même chose.
List<Widget> accesRapides({
  required EcranNav ecran,
  required List<DomaineRuban> ruban,
  required List<Widget> declarees,
  required void Function(String id) aller,
}) {
  if (ecran.standalone || ecran.module == 'AUTH') return const [];
  final max = (3 - declarees.length).clamp(0, 3);
  if (max == 0) return const [];
  final deja = {
    for (final b in declarees.whereType<BoutonSigh>()) _norm(b.libelle)
  };
  final rangees = [
    for (final d in ruban)
      for (final r in d.rangees)
        if (r.code == ecran.module) r
  ];
  if (rangees.isEmpty) return const [];
  final voisins = [
    for (final r in rangees)
      for (final e in r.ecrans)
        if (e.id != ecran.id && !deja.contains(_norm(e.label))) (e, r)
  ];
  final sorties = <Widget>[];
  for (final (e, r) in voisins.take(max - (max > 1 ? 1 : 0))) {
    sorties.add(BoutonSigh(
        libelle: e.label,
        icone: icone(e.icone ?? r.icone),
        variante: VarianteBouton.secondaire,
        onPressed: () => aller(e.id)));
  }
  final r0 = rangees.first;
  if (sorties.length < max) {
    sorties.add(BoutonSigh(
        libelle: r0.label,
        icone: icone(r0.icone),
        variante: VarianteBouton.secondaire,
        onPressed: () => aller(r0.hub)));
  }
  return sorties;
}
