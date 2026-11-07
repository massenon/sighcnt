/// Les cinq modalités de l'imagerie médicale (`D.IMAGERIE.MODALITES`, `assets/js/data-imagerie.js`) et ce qu'elles portent.
///
/// La modalité est une PROPRIÉTÉ DE L'EXAMEN (`modalite` sur chaque fiche du catalogue `examensImagerie`) : le compte rendu n'en porte pas,
/// il pourrait contredire son examen. Les règles de l'échographie (mesures en texte, provenance, « Autre » systématique) sont PORTÉES PAR LA
/// MODALITÉ — une passe les applique à tous ses examens, présents comme futurs — et non recopiées variable par variable.
library;

/// Le marquage des quatre modalités sans modèle de compte rendu remis (`D.IMAGERIE.PROPOSITION`).
const propositionImagerie =
    'Proposition — aucun modèle de compte rendu remis pour cette modalité ; à arrêter par le radiologue.';

/// Une rubrique RÉDIGÉE du compte rendu (hors variables) : la Conclusion, et pour la radiologie les Résultats et la Recommandation.
class RubriqueLibre {
  const RubriqueLibre(this.code, this.label, this.note, {this.requis = false});
  final String code;
  final String label;
  final String note;
  final bool requis;
}

/// `LIBRES_RADIOLOGIE` : le plan classique du compte rendu radiologique — résultats rédigés, conclusion (obligatoire), recommandation.
const rubriquesLibresRadiologie = [
  RubriqueLibre('resultats', 'Résultats — description rédigée',
      'Complète les variables : ce que les cases ne disent pas.'),
  RubriqueLibre(
      'conclusion', 'Conclusion', 'Reprise telle quelle sur le compte rendu.',
      requis: true),
  RubriqueLibre('recommandation', 'Recommandation',
      'Examen complémentaire, contrôle, avis spécialisé.'),
];

/// `RUBRIQUES_LIBRES` : le repli quand la modalité n'en déclare pas — la seule Conclusion de l'échographiste (« Annexes » retirée le 14/09/2026).
const rubriquesLibresEchographie = [
  RubriqueLibre('conclusion', 'Conclusion',
      'Rédigée par l’échographiste. Reprise telle quelle sur le compte rendu.',
      requis: true),
];

class ModaliteImagerie {
  const ModaliteImagerie({
    required this.code,
    required this.label,
    required this.tableau,
    required this.ecran,
    required this.icone,
    this.aValider,
    this.saisieTexte = true,
    this.provenance = true,
    this.autreSystematique = false,
    this.rubriquesLibres = rubriquesLibresEchographie,
  });

  final String code;
  final String label;

  /// L'intitulé du tableau de la modalité (« Tableau IRM »).
  final String tableau;

  /// L'identifiant d'écran du tableau (retour par défaut du compte rendu).
  final String ecran;

  /// Nom d'icône Lucide déclaré par la maquette (`scan-line`, `bone`, `ribbon`, `radiation`, `magnet`).
  final String icone;

  /// Non nul pour les modalités dont le catalogue est une PROPOSITION (aucun modèle remis).
  final String? aValider;
  final bool saisieTexte;
  final bool provenance;
  final bool autreSystematique;
  final List<RubriqueLibre> rubriquesLibres;
}

const modalitesImagerie = [
  ModaliteImagerie(
      code: 'echographie',
      label: 'Échographie',
      tableau: 'Tableau Échographie',
      ecran: 'm2-imagerie',
      icone: 'scan-line'),
  ModaliteImagerie(
      code: 'radiographie',
      label: 'Radiographie',
      tableau: 'Tableau Radiographie',
      ecran: 'm2-imagerie-radiographie',
      icone: 'bone',
      aValider: propositionImagerie,
      autreSystematique: true,
      rubriquesLibres: rubriquesLibresRadiologie),
  ModaliteImagerie(
      code: 'mammographie',
      label: 'Mammographie',
      tableau: 'Tableau Mammographie',
      ecran: 'm2-imagerie-mammographie',
      icone: 'ribbon',
      aValider: propositionImagerie,
      autreSystematique: true,
      rubriquesLibres: rubriquesLibresRadiologie),
  ModaliteImagerie(
      code: 'scanner',
      label: 'Scanner',
      tableau: 'Tableau Scanner',
      ecran: 'm2-imagerie-scanner',
      icone: 'radiation',
      aValider: propositionImagerie,
      autreSystematique: true,
      rubriquesLibres: rubriquesLibresRadiologie),
  ModaliteImagerie(
      code: 'irm',
      label: 'IRM — imagerie par résonance magnétique',
      tableau: 'Tableau IRM',
      ecran: 'm2-imagerie-irm',
      icone: 'magnet',
      aValider: propositionImagerie,
      autreSystematique: true,
      rubriquesLibres: rubriquesLibresRadiologie),
];

/// `D.IMAGERIE.modalite(code)`.
ModaliteImagerie? modaliteImagerie(String code) {
  for (final m in modalitesImagerie) {
    if (m.code == code) return m;
  }
  return null;
}

/// `imModalite(code)` : une modalité inconnue répond `{code, label: code}` — ni mesures en texte, ni rubriques propres (repli de la maquette).
ModaliteImagerie modaliteOuInconnue(String code) =>
    modaliteImagerie(code) ??
    ModaliteImagerie(
        code: code,
        label: code,
        tableau: code,
        ecran: 'm2-imagerie',
        icone: 'scan-line',
        saisieTexte: false,
        provenance: false);

/// `D.IMAGERIE.modaliteDeExamen(ex)` : un examen sans modalité déclarée — ajouté au catalogue avant la vague 61 — reste à l'échographie.
String modaliteDeExamen(Map<String, Object?>? examen) {
  final m = examen?['modalite'];
  return (m is String && m.isNotEmpty) ? m : 'echographie';
}

/// `D.IMAGERIE.ecart(variable, valeur)` : la valeur s'écarte-t-elle de la normale déclarée ? Le compte rendu réel met en gras ce qui sort de la
/// norme. Une valeur absente, vide ou multiple n'est jamais un écart.
bool ecartDeLaNormale(Map<String, Object?>? variable, Object? valeur) {
  if (variable == null) return false;
  final normal = variable['normal'];
  if (normal == null || normal == '' || normal == false || normal == 0)
    return false;
  if (valeur == null || valeur == '' || valeur is List) return false;
  return '$valeur' != '$normal';
}
