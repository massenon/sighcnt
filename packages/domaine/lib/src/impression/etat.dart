import '../format/format_fr.dart';

/// Colonne d'un état imprimé (`P.tableau`). Le TOTAL est une propriété de la colonne (`somme`) et il est REFAIT depuis les lignes réellement
/// imprimées : un état ne peut pas afficher un total qui ne corresponde pas à ce qu'il montre (vague 28 de la maquette).
class ColonneEtat {
  const ColonneEtat(
      {required this.libelle,
      required this.valeur,
      this.droite = false,
      this.somme});
  final String libelle;
  final Object? Function(Map<String, Object?>) valeur;
  final bool droite;

  /// `null` : colonne non totalisée (prix unitaires, taux : un total n'y aurait aucun sens).
  final num Function(Map<String, Object?>)? somme;
}

class TableauEtat {
  const TableauEtat(
      {required this.colonnes,
      required this.lignes,
      this.libelleTotal = 'TOTAL',
      this.mentions = const {}});
  final List<ColonneEtat> colonnes;
  final List<Map<String, Object?>> lignes;
  final String libelleTotal;

  /// Mentions de pied qui ne sont pas des sommes (solde reporté, renvoi réglementaire), par libellé de colonne.
  final Map<String, String> mentions;

  /// Ligne de total, ou `null` si aucune colonne ne se totalise.
  List<String>? get pied {
    if (!colonnes.any((c) => c.somme != null)) return null;
    return [
      for (var i = 0; i < colonnes.length; i++)
        if (i == 0)
          libelleTotal
        else if (colonnes[i].somme != null)
          money(
              lignes.fold<num>(0, (n, r) {
                final v = colonnes[i].somme!(r);
                return n + (v.isFinite ? v : 0);
              }),
              avecDevise: false)
        else
          mentions[colonnes[i].libelle] ?? '',
    ];
  }

  List<List<String>> get cellules => [
        for (final r in lignes)
          [
            for (final c in colonnes)
              () {
                final v = c.valeur(r);
                return v == null || v == '' ? '' : '$v';
              }(),
          ]
      ];
}
