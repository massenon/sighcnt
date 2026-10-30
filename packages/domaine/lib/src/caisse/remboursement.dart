/// REMBOURSEMENTS & ANNULATIONS — port de la modale « Nouvelle opération » de `m8-remboursements` (prototype_html/assets/js/modules/m8-facturation.js).
///
/// Trois natures, trois effets, tous motivés et journalisés (RG-12) :
///   · « Remboursement »  — rend un trop-perçu : la facture n'est pas touchée ;
///   · « Facture avoir »  — une pièce à part entière, aux montants NÉGATIFS, rattachée à la facture d'origine et transmise à la MECeF ;
///   · « Annulation »     — la facture repasse impayée, MECeF « rejeté », marquée annulée (elle n'est jamais supprimée, RG-14).
///
/// Cet écran est l'ANCIEN canal de correction ; le canal de la phase 5 est `emettreAvoir` (contre-passation en écritures). Les deux coexistent dans la
/// maquette ; la Direction n'a pas arbitré. Rejoué sur les vecteurs de `test/vecteurs/remboursements.json`, engendrés en pilotant la modale réelle.
///
/// Corrigé dans la maquette PUIS porté (E8) : la référence `RB-NNNNN` est lue sur les opérations existantes, plus un compteur de page.
/// Portés fidèlement et signalés : E10 (un montant à 0 est accepté : le « min 1 » du champ n'est pas appliqué) ; E11 (la règle affichée dit que
/// l'annulation d'une facture normalisée « déclenche l'émission d'un avoir MECeF » — le code passe seulement le statut MECeF à « rejeté ») ;
/// E6 (millésime « 2026 » en dur dans le numéro de l'avoir).
library;

import '../format/js.dart';

class RefusOperation implements Exception {
  const RefusOperation(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

class OperationEnregistree {
  const OperationEnregistree(
      {required this.remboursement, this.factureAvoir, this.patchFacture});

  /// La fiche `remboursements` à insérer.
  final Map<String, Object?> remboursement;

  /// La pièce d'avoir NÉGATIVE (nature « Facture avoir » seulement) ; `mecef` dit qu'elle part à la normalisation (le numéro est tiré par l'appelant).
  final Map<String, Object?>? factureAvoir;

  /// Ce qu'il faut écrire sur la facture d'origine (nature « Annulation » seulement).
  final Map<String, Object?>? patchFacture;
}

const naturesOperation = ['Facture avoir', 'Remboursement', 'Annulation'];

/// Les factures proposées : réglées en tout ou partie, les plus récentes d'abord, 200 au plus.
List<Map<String, Object?>> facturesConcernables(
    List<Map<String, Object?>> factures) {
  final l = factures
      .where((f) =>
          nombreOuZero(f['montantPaye']) > 0 || f['statutPaiement'] != 'impayee')
      .toList()
    ..sort((a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
  return l.take(200).toList();
}

String _ref(Iterable<Map<String, Object?>> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith('RB-')) {
      final k = int.tryParse(r.substring(3)) ?? 0;
      if (k > max) max = k;
    }
  }
  return 'RB-${(max + 1).toString().padLeft(5, '0')}';
}

/// `Enregistrer`. [saisie] : `factureId, nature, motifAvoir, refacturation, date, montant, motif, autorisePar` (valeurs du formulaire).
/// [rangFactures] : nombre de factures actives (numérotation de l'avoir). Lève [RefusOperation] si un champ obligatoire manque.
OperationEnregistree enregistrerOperation({
  required Map<String, Object?> saisie,
  required Map<String, Object?>? facture,
  required List<Map<String, Object?>> remboursements,
  required int rangFactures,
}) {
  bool vide(String k) => '${saisie[k] ?? ''}'.trim().isEmpty;
  if (['factureId', 'nature', 'date', 'montant', 'motif', 'autorisePar']
      .any(vide)) {
    throw const RefusOperation('Le formulaire comporte des erreurs.');
  }
  final montant = nombreOuZero(saisie['montant']);
  final v = <String, Object?>{
    ...saisie,
    'montant': montant,
    if (facture != null) ...{
      'factureNumero': facture['numero'],
      'patient': facture['patient'],
      'patientCode': facture['patientCode'],
    },
    'reference': _ref(remboursements),
  };
  final nature = '${saisie['nature']}';
  Map<String, Object?>? avoir;
  Map<String, Object?>? patch;
  if (nature == 'Facture avoir' && facture != null) {
    // L'avoir est une pièce à part entière : montant négatif, rattachée à la facture d'origine, transmise à la MECeF. Il ne supprime pas la facture (RG-14).
    final neg = -montant.abs();
    avoir = {
      'numero': 'AV-2026-${(rangFactures + 1).toString().padLeft(5, '0')}',
      'mecef': true,
      'avoirDe': facture['id'],
      'avoirDeNumero': facture['numero'],
      'motifAvoir': saisie['motifAvoir'],
      'refacturation': saisie['refacturation'],
      'patientId': facture['patientId'],
      'patient': facture['patient'],
      'patientCode': facture['patientCode'],
      'date': saisie['date'],
      'type': 'Avoir',
      'montantHT': neg,
      'montantTTC': neg,
      'partAssurance': 0,
      'partPatient': neg,
      'montantPaye': 0,
      'reliquat': 0,
      'baseMecef': neg,
      'statutPaiement': 'soldee',
      'statutMecef': 'valide',
      'lignes': [
        {
          'designation':
              'Avoir sur facture ${facture['numero']} — ${saisie['motif'] ?? ''}',
          'quantite': 1,
          'prixUnitaire': neg,
          'montant': neg,
        }
      ],
    };
  } else if (nature == 'Annulation' && facture != null) {
    patch = {'statutPaiement': 'impayee', 'statutMecef': 'rejete', 'annulee': true};
  }
  return OperationEnregistree(
      remboursement: v, factureAvoir: avoir, patchFacture: patch);
}
