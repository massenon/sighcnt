/// MECeF, lot M1 : les cinq états d'une pièce du registre fiscal (E2299).
///
/// Il n'y a pas de « facture simple » : toute vente est normalisée (décision de la Direction du 07/11/2026). Les identifiants STOCKÉS `valide` et
/// `rejete` restent ceux des jeux du poste (on ne renomme pas un identifiant technique) ; [etatMecefDe] donne le nom canonique.
library;

class EtatMecef {
  const EtatMecef(this.id, this.stocke, this.libelle);
  final String id;
  final String stocke;
  final String libelle;
}

const etatsMecef = [
  EtatMecef('normalisee', 'valide', 'Normalisée'),
  EtatMecef('en_attente', 'en_attente', 'En attente de transmission'),
  EtatMecef('a_verifier', 'a_verifier', 'À vérifier'),
  EtatMecef('refusee', 'rejete', 'Refusée'),
  EtatMecef('expiree', 'expiree', 'Expirée'),
];

/// L'état canonique d'une pièce, ou null quand elle n'est pas du registre fiscal (avoir `sans_objet`, statut absent).
EtatMecef? etatMecefDe(Object? statutOuPiece) {
  final s = statutOuPiece is Map ? statutOuPiece['statutMecef'] : statutOuPiece;
  for (final e in etatsMecef) {
    if (e.stocke == s) return e;
  }
  return null;
}

/// Une pièce porte le bloc fiscal imprimé (QR, NIM, code, compteurs) seulement quand elle est réellement normalisée ; sinon le bandeau DEMO.
bool porteBlocFiscal(Object? piece) =>
    etatMecefDe(piece)?.id == 'normalisee' &&
    (piece is! Map || '${piece['numeroMecef'] ?? ''}'.isNotEmpty);

/// Les deux lignes du bandeau imprimé sur une pièce non normalisée (jamais un faux code) ; vide quand la pièce est normalisée.
List<String> bandeauDemoMecef(Object? piece) {
  if (porteBlocFiscal(piece)) return const [];
  return [
    'DEMO : pièce non normalisée',
    'Cette pièce n’a pas été normalisée (état : ${etatMecefDe(piece)?.libelle ?? 'non applicable'}). Elle ne porte ni code MECeF, ni QR, ni compteurs.',
  ];
}
