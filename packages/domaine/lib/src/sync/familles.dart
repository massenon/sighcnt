/// Les quatre familles de fusion du PRD (§8) + le référentiel.
/// Chaque collection du dictionnaire de données en porte UNE (EF-SYNC-06).
enum Famille {
  /// A — fiche descriptive : fusion par champ, conflit nommé si le même champ diverge.
  ficheDescriptive('A'),

  /// B — journal append-only : union des lignes, jamais de modification.
  journal('B'),

  /// C — pièce émise immuable : aucune fusion, correction = nouvelle pièce liée.
  pieceEmise('C'),

  /// D — agrégat à invariant : la mère rejoue et vérifie, refus nommé si l'invariant tombe.
  invariant('D'),

  /// R — référentiel : seule la console de la mère écrit.
  referentiel('R');

  const Famille(this.code);
  final String code;
}
