/// LE RÈGLEMENT D'UNE DEMANDE se lit sur la LIGNE de facture qui la couvre — port de `indexReglements`, `reglementDemande` et `badgeReglement`
/// (m5-laboratoire.js, phase 6). Vecteurs : `test/vecteurs/resultats.json` (section `impression`).
///
/// C'est la raison d'être des lignes payables. Trois réponses, pas deux : RÉGLÉE, DUE, et SANS PIÈCE LIÉE — les demandes d'avant les lignes
/// payables n'ont pas de facture ; les dire impayées serait aussi faux que les dire réglées. Le compte rendu ne sort que pour un examen réglé.
library;

import 'res_habilitations.dart';

class ReglementDemande {
  const ReglementDemande(this.statut, {this.facture, this.montant});

  /// `regle` | `du` | `non_trace`.
  final String statut;
  final String? facture;
  final Object? montant;

  String get libelle => switch (statut) {
        'regle' => 'Réglée',
        'du' => 'Règlement dû',
        _ => 'Sans pièce liée',
      };
}

/// `indexReglements()` : demande → règlement, d'après les lignes des factures NON archivées, PARCOURUES DANS L'ORDRE DU MAGASIN. Si deux lignes
/// visent la même demande, la DERNIÈRE parcourue l'emporte (porté fidèlement : la maquette ne départage pas par la date ni par le statut).
Map<String, ReglementDemande> indexReglements(Iterable<FicheLabo> facturesActives) {
  final idx = <String, ReglementDemande>{};
  for (final f in facturesActives) {
    for (final l in (f['lignes'] as List? ?? const [])) {
      final ligne = (l as Map).cast<String, Object?>();
      final d = ligne['demandeId'];
      if (d != null && d != '') {
        idx['$d'] = ReglementDemande(
            ligne['statutPaiement'] == 'paye' ? 'regle' : 'du',
            facture: f['numero'] == null ? null : '${f['numero']}',
            montant: ligne['partPatient']);
      }
    }
  }
  return idx;
}

/// `reglementDemande(r, idx)`.
ReglementDemande reglementDemande(FicheLabo r, Map<String, ReglementDemande> idx) {
  final v = idx['${r['id']}'];
  if (v != null) return v;
  final bloque = r['bloqueParPaiement'];
  if (bloque != null && bloque != false && bloque != '' && bloque != 0) {
    final f = r['factureNumero'];
    final p = r['prix'];
    return ReglementDemande('du',
        facture: f == null || f == '' ? null : '$f',
        montant: p == null || p == 0 ? null : p);
  }
  return const ReglementDemande('non_trace');
}

/// Le libellé du verrou posé sur « Imprimer » quand le règlement est dû : il NOMME la pièce et le poste où la balle se trouve.
String motifImpressionVerrouillee(ReglementDemande g) =>
    'Examen non réglé — le patient doit passer à la caisse (${g.facture ?? 'pièce à émettre'}).';
