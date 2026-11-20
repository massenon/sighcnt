/// LES ÉTATS D'UN RÉSULTAT D'ANALYSE — port de `D.ETATS_RESULTAT`, `D.etatResultat`, `D.resultatRendu` (prototype_html/assets/js/data.js).
///
/// Deux verrous, demandés par le biologiste. Entre eux, le résultat EXISTE mais le prescripteur ne le voit pas : c'est la fenêtre pendant
/// laquelle le laboratoire relit. Un état comparé à une chaîne écrite à la main plutôt qu'interrogé ici, c'est ainsi que deux vérités
/// s'installent (vague 35) : tout l'écran passe par ces trois fonctions.
library;

class EtatResultat {
  const EtatResultat(this.id, this.label, this.tone, this.ordre, [this.aide = '']);
  final String id;
  final String label;

  /// Ton du badge : `neutral`, `warning`, `info`, `navy`, `success`, `danger` (vocabulaire de la maquette).
  final String tone;
  final int ordre;
  final String aide;
}

const List<EtatResultat> etatsResultat = [
  EtatResultat('en_attente', 'En attente', 'neutral', 1,
      'Demande enregistrée, prélèvement non effectué.'),
  EtatResultat('attente_prelevement', 'Réglé — à prélever', 'warning', 2,
      'La caisse a encaissé : le prélèvement peut avoir lieu.'),
  EtatResultat('preleve', 'Prélevé', 'info', 3,
      'Échantillon prélevé, à acheminer au laboratoire.'),
  EtatResultat('en_cours', 'Au laboratoire', 'info', 4,
      'Échantillon reçu, analyse en cours.'),
  EtatResultat('saisi', 'Saisi, non validé', 'warning', 5,
      'Résultat porté mais non validé : ni le laboratoire ni le prescripteur ne s’y fient encore.'),
  EtatResultat('valide_technique', 'Validation technique', 'navy', 6,
      'Le technicien a validé sa saisie. Le prescripteur NE VOIT PAS ENCORE le résultat : c’est la fenêtre pendant laquelle le laboratoire relit.'),
  EtatResultat('valide', 'Validé biologiquement', 'success', 7,
      'Validation biologique portée : le résultat est visible du prescripteur et fait foi.'),
  EtatResultat('rectifie', 'Rectifié', 'danger', 8,
      'Une version rectificative a été émise après validation biologique. Le prescripteur est notifié que ce qu’il a lu a changé.'),
];

/// `D.etatResultat(id)` : l'état par son identifiant ; un état inconnu se nomme lui-même (il ne disparaît pas).
EtatResultat etatResultat(Object? id) {
  for (final e in etatsResultat) {
    if (e.id == id) return e;
  }
  final s = id == null || id == '' ? '—' : '$id';
  return EtatResultat('${id ?? ''}', s, 'neutral', 0);
}

/// `D.resultatRendu(etat)` : le résultat est-il OPPOSABLE au prescripteur ? Seuls `valide` et `rectifie` le sont.
bool resultatRendu(Object? etat) => etat == 'valide' || etat == 'rectifie';
