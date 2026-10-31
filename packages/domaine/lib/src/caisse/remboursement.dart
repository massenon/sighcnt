/// REMBOURSEMENTS & ANNULATIONS : port de la modale « Nouvelle opération » de `m8-remboursements` (prototype_html/assets/js/modules/m8-facturation.js).
///
/// Trois natures, trois effets, tous motivés et journalisés (RG-12) :
///   · « Remboursement »  : rend un trop-perçu, la facture n'est pas touchée ;
///   · « Facture avoir »  : APPELLE le moteur unique `emettreAvoir` (collection `avoirs`), plafond cumulé, ligne nommée, contre-passation en brouillon ;
///   · « Annulation »     : la facture repasse impayée, MECeF « rejeté », marquée annulée (elle n'est jamais supprimée, RG-14).
///
/// Décision de la Direction du 31/10/2026 (B10), corrigée dans la maquette PUIS portée : UN SEUL canal d'avoir (E12). La nature « Facture avoir »
/// n'écrit plus une pièce NÉGATIVE dans `factures` ; l'opération garde le lien (`avoirId`, `avoirNumero`). Un montant est strictement supérieur
/// à 0 FCFA (E10). Rejoué sur les vecteurs de `test/vecteurs/remboursements.json`, engendrés en pilotant la modale réelle.
///
/// Corrigé dans la maquette PUIS porté (E8) : la référence `RB-NNNNN` est lue sur les opérations existantes, plus un compteur de page.
/// Porté fidèlement et signalé : E11 (la règle affichée dit que l'annulation d'une facture normalisée « déclenche l'émission d'un avoir MECeF » ;
/// le code passe seulement le statut MECeF à « rejeté »).
library;

import '../format/js.dart';
import 'avoir.dart';

class RefusOperation implements Exception {
  const RefusOperation(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

class OperationEnregistree {
  const OperationEnregistree(
      {required this.remboursement, this.avoir, this.patchFacture});

  /// La fiche `remboursements` à insérer (porte `avoirId` et `avoirNumero` pour la nature « Facture avoir »).
  final Map<String, Object?> remboursement;

  /// L'avoir émis par le moteur unique (nature « Facture avoir » seulement) : fiche `avoirs`, contre-passation, nouveau cumul de la facture.
  final AvoirEmis? avoir;

  /// Ce qu'il faut écrire sur la facture d'origine (nature « Annulation » seulement).
  final Map<String, Object?>? patchFacture;
}

const naturesOperation = ['Facture avoir', 'Remboursement', 'Annulation'];

/// Le motif du moteur d'avoir pour chaque « cas de figure » du formulaire (les motifs de `m8-facture-avoir`).
const motifsMoteurAvoir = {
  'erreur': 'Erreur de facturation',
  'non_rendu': 'Prestation non réalisée',
  'remboursement': 'Autre (préciser en observations)',
  'annulation': 'Prestation non réalisée',
};

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
/// Pour la nature « Facture avoir », [avoirs] / [facturesMere] / [idAvoir] / [jour] / [utilisateur] alimentent le moteur unique `emettreAvoir`.
/// Lève [RefusOperation] : champ manquant, montant non strictement positif, ou refus NOMMÉ du moteur d'avoir (plafond cumulé, mère consolidée).
OperationEnregistree enregistrerOperation({
  required Map<String, Object?> saisie,
  required Map<String, Object?>? facture,
  required List<Map<String, Object?>> remboursements,
  List<Map<String, Object?>> avoirs = const [],
  List<Map<String, Object?>> facturesMere = const [],
  String idAvoir = 'AVR-NOUVEAU',
  String jour = '',
  String utilisateur = '',
  String? horodatage,
}) {
  bool vide(String k) => '${saisie[k] ?? ''}'.trim().isEmpty;
  if (['factureId', 'nature', 'date', 'montant', 'motif', 'autorisePar']
      .any(vide)) {
    throw const RefusOperation('Le formulaire comporte des erreurs.');
  }
  final montant = nombreOuZero(saisie['montant']);
  // E10 (corrigé dans la maquette le 31/10/2026) : une opération de 0 FCFA ne corrige rien.
  if (!(montant > 0)) {
    throw const RefusOperation(
        'Le montant doit être strictement supérieur à 0 FCFA.');
  }
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
  AvoirEmis? avoir;
  Map<String, Object?>? patch;
  if (nature == 'Facture avoir') {
    if (facture == null) {
      throw const RefusOperation('Choisir la facture concernée.');
    }
    // B10 : UN SEUL canal. Le moteur écrit l'avoir (collection `avoirs`) ; l'opération garde le lien.
    final motifMoteur = motifsMoteurAvoir['${saisie['motifAvoir']}'] ??
        'Autre (préciser en observations)';
    final motif = '${saisie['motif'] ?? ''}';
    try {
      avoir = emettreAvoir(
        facture: facture,
        idAvoir: idAvoir,
        lignes: [
          {
            'designation':
                'Avoir sur facture ${facture['numero']} : ${motif.isEmpty ? motifMoteur : motif}',
            'montant': montant,
          }
        ],
        motif: motifMoteur,
        observations: motif,
        remboursement:
            '${saisie['motifAvoir']}' == 'remboursement' ? 'especes' : 'creance',
        date: '${saisie['date']}',
        origine: 'caisse',
        horodatage: horodatage,
        jour: jour.isEmpty ? '${saisie['date']}' : jour,
        utilisateur: utilisateur,
        facturesMere: facturesMere,
        avoirs: avoirs,
      );
    } on RefusAvoir catch (r) {
      throw RefusOperation(r.motif);
    }
    v['avoirId'] = idAvoir;
    v['avoirNumero'] = avoir.avoir['reference'];
  } else if (nature == 'Annulation' && facture != null) {
    patch = {
      'statutPaiement': 'impayee',
      'statutMecef': 'rejete',
      'annulee': true
    };
  }
  return OperationEnregistree(
      remboursement: v, avoir: avoir, patchFacture: patch);
}
