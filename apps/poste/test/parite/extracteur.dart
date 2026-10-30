import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String normaliser(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Tous les textes affichés à l'écran (Text et RichText), normalisés : ce que l'agent LIT, comme `innerText` côté maquette.
Set<String> textesVisibles(WidgetTester t) {
  final out = <String>{};
  for (final w in t.widgetList<Text>(find.byType(Text))) {
    final d = w.data ?? w.textSpan?.toPlainText();
    if (d != null && d.trim().isNotEmpty) out.add(normaliser(d));
  }
  for (final w in t.widgetList<RichText>(find.byType(RichText))) {
    final d = w.text.toPlainText();
    if (d.trim().isNotEmpty) out.add(normaliser(d));
  }
  for (final w in t.widgetList<TextField>(find.byType(TextField))) {
    final l = w.decoration?.labelText;
    if (l != null) out.add(normaliser(l));
  }
  for (final w in t.widgetList<Tooltip>(find.byType(Tooltip))) {
    if (w.message != null) out.add(normaliser(w.message!));
  }
  return out;
}

/// Résultat de la comparaison d'un écran Flutter avec la fiche extraite de la maquette.
class Parite {
  Parite(this.id, this.attendus, this.manquants);
  final String id;
  final int attendus;
  final List<String> manquants;
  int get presents => attendus - manquants.length;
  double get taux => attendus == 0 ? 1 : presents / attendus;
}

/// N1 — CONTENU : chaque libellé que la maquette affiche (titre, description, KPI, onglets, en-têtes, commandes, champs)
/// doit figurer à l'écran. Les VALEURS de données ne sont pas comparées (elles dépendent du jeu).
Parite comparerContenu(
    String id, Map<String, Object?> fiche, Set<String> textes) {
  final attendus = <String>[];
  void ajouter(Object? v) {
    if (v is String && v.trim().isNotEmpty) attendus.add(normaliser(v));
    if (v is List) v.forEach(ajouter);
  }

  for (final k in [
    'titre',
    'description',
    'kpis',
    'onglets',
    'cartes',
    'tableaux',
    'champs'
  ]) {
    ajouter(fiche[k]);
  }
  // Les commandes portent des COMPTES issus du jeu (« Tous les factures409 », pagination « 1 »…) : le libellé se compare, la valeur non.
  for (final c in (fiche['commandes'] as List? ?? const [])) {
    if (c is! String) continue;
    final libelle = c.replaceFirst(RegExp(r'\d+$'), '').trim();
    if (libelle.isNotEmpty) attendus.add(normaliser(libelle));
  }
  final uniques = attendus.toSet().toList();
  final manquants = [
    for (final a in uniques)
      if (!textes.any((t) => t == a || t.contains(a))) a
  ];
  return Parite(id, uniques.length, manquants);
}
