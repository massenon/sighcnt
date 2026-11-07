/// FACTURE D'AVOIR — port de `emettreAvoir` (prototype_html/assets/js/modules/m8-facturation.js, phase 5).
///
/// Une pièce émise NE SE MODIFIE PAS et la caisse ne l'annule plus : l'avoir la CONTRE-PASSE — pièce numérotée qui nomme ses lignes,
/// écriture inverse en BROUILLON (la validation comptable reste un geste humain), registre fiscal MECeF alimenté. La facture PORTE ses avoirs
/// (`avoirIds`, `montantAvoirs`), elle n'est jamais réécrite.
///
/// Le moteur de la maquette lit le magasin ; celui-ci reçoit les fiches EN ARGUMENT (la facture, les factures mères, les avoirs déjà émis) et
/// RENVOIE ce qu'il faut écrire : le poste, le mobile de secours et la mère l'appellent avec ce qu'ils ont. Les vecteurs
/// (`test/vecteurs/avoir.json`) sont engendrés par la maquette.
///
/// Corrigé dans la maquette PUIS porté (docs/architecture/ECARTS-MAQUETTE.md, E8) : la référence est une SÉRIE ANNUELLE lue sur les avoirs déjà émis.
/// Porté fidèlement et signalé (E9) : une facture mère qui n'est qu'en BROUILLON bloque l'avoir comme une mère émise : le moteur ne regarde pas son statut.
///
/// Décision de la Direction du 31/10/2026 (B10), corrigée dans la maquette PUIS portée : ce moteur est le CANAL UNIQUE de l'avoir. L'écran de
/// facturation (nature « Facture avoir », E12) et l'avoir MECeF (E15) l'APPELLENT, sur la même collection `avoirs` ; le plafond est CUMULÉ partout ;
/// un montant est strictement supérieur à 0 FCFA (E10) ; on ne rectifie pas un avoir ; la DATE d'une pièce est un JOUR, l'instant d'émission est
/// porté à part (`horodatage`, E4).
///
/// L'équilibre de la contre-passation (RG-10) est CONSTRUIT, non contrôlé après coup : deux lignes de même montant, l'une au débit, l'autre au crédit.
library;

import '../format/format_fr.dart';
import '../format/js.dart';

/// Refus NOMMÉ : un refus se lit, il ne se devine pas. Rien n'est écrit.
class RefusAvoir implements Exception {
  const RefusAvoir(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

class AvoirEmis {
  const AvoirEmis(
      {required this.avoir,
      required this.ecritures,
      required this.montantAvoirs});

  /// La fiche `avoirs` à insérer (sans `ecritureIds`, que l'appelant renseigne après avoir inséré les écritures).
  final Map<String, Object?> avoir;

  /// Les deux lignes plates de la contre-passation, en brouillon (débit 706000 ; crédit 571000 espèces ou 411000 créance).
  final List<Map<String, Object?>> ecritures;

  /// Le nouveau cumul porté par la facture (`montantAvoirs`) ; l'identifiant de l'avoir s'ajoute à `avoirIds`.
  final double montantAvoirs;
}

double _n(Object? v) => nombreOuZero(v);

/// Le JOUR (`AAAA-MM-JJ`) d'une date : celui qui est ÉCRIT quand la valeur commence par une date (un instant ISO garde son jour écrit).
String jourEcrit(String date) {
  final m = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(date);
  return m == null ? date : m.group(1)!;
}

/// `referenceAvoir(date)` : `AV-AAAA-NNNN`, la série repartant à 1 chaque année, lue sur les avoirs ACTIFS déjà émis.
String referenceAvoir(String date, Iterable<Map<String, Object?>> avoirs) {
  final prefixe = 'AV-${date.length >= 4 ? date.substring(0, 4) : date}-';
  var max = 0;
  for (final a in avoirs) {
    final r = '${a['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final k = int.tryParse(r.substring(prefixe.length)) ?? 0;
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(4, '0')}';
}

/// `emettreAvoir(factureId, params)`. [idAvoir] : l'identifiant que l'appelant donnera à la fiche (les écritures le portent comme `pieceId`).
/// [jour] : `YYYY-MM-DD` de l'avoir si [date] est omise. Lève [RefusAvoir].
AvoirEmis emettreAvoir({
  required Map<String, Object?>? facture,
  required String idAvoir,
  required List<Map<String, Object?>> lignes,
  required String motif,
  required String jour,
  required String utilisateur,
  String? remboursement,
  String? observations,
  String? date,
  String? origine,
  String? horodatage,
  List<Map<String, Object?>> facturesMere = const [],
  List<Map<String, Object?>> avoirs = const [],
}) {
  if (facture == null) throw const RefusAvoir('Facture introuvable.');
  if (facture['type'] == 'Avoir' || _n(facture['montantTTC']) < 0) {
    throw RefusAvoir(
        'La pièce ${facture['numero']} est elle-même un avoir : on ne rectifie pas un avoir.');
  }

  // UNE FILLE CONSOLIDÉE EST FIGÉE : la mère porte son numéro et la compagnie détient la pièce. L'avoir est refusé EN NOMMANT la mère.
  for (final m in facturesMere) {
    if (m['statut'] == 'archive') continue;
    final filles = (m['piecesFilles'] as List?) ?? const [];
    if (filles.contains(facture['numero'])) {
      throw RefusAvoir(
          'La facture ${facture['numero']} est consolidée dans la facture mère ${m['numero']} (${m['compagnie'] ?? ''}), '
          'déjà émise : la corriger passerait derrière le dos de la compagnie. Émettre l’avoir au niveau de la mère, par avenant.');
    }
  }

  if (lignes.isEmpty) {
    throw const RefusAvoir(
        'Un avoir se rapporte à des LIGNES nommées — en cocher au moins une.');
  }
  final montant = lignes.fold(0.0, (a, l) => a + _n(l['montant']));
  if (!(montant > 0)) {
    throw const RefusAvoir(
        'Le montant de l’avoir doit être strictement supérieur à 0 FCFA.');
  }

  final deja = avoirs
      .where((a) => a['statut'] != 'archive' && a['factureId'] == facture['id'])
      .fold(0.0, (s, a) => s + _n(a['montant']));
  if (montant + deja > _n(facture['montantTTC'])) {
    throw RefusAvoir(
        'Le cumul des avoirs (${money(montant + deja)}) excéderait la facture (${money(facture['montantTTC'])}).');
  }

  final jourAvoir = (date == null || date.isEmpty) ? jour : jourEcrit(date);
  final reference = referenceAvoir(jourAvoir, avoirs);
  final suite = remboursement == null || remboursement.isEmpty ? 'creance' : remboursement;
  final fiche = <String, Object?>{
    'reference': reference,
    'date': jourAvoir,
    if (horodatage != null) 'horodatage': horodatage,
    'factureId': facture['id'],
    'factureNumero': facture['numero'],
    'patientId': facture['patientId'],
    'patient': facture['patient'],
    'patientCode': facture['patientCode'],
    'montant': montant,
    'motif': motif,
    'observations': observations ?? '',
    'lignesAnnulees': lignes,
    'remboursement': suite,
    'origine': origine == null || origine.isEmpty ? 'caisse' : origine,
    // Le registre fiscal : une facture normalisée validée exige la régularisation MECeF ; une pièce non transmise n'en relève pas.
    'statutMecef': facture['statutMecef'] == 'valide' ? 'en_attente' : 'sans_objet',
    'emisPar': utilisateur,
  };

  // LA CONTRE-PASSATION — écritures PLATES en brouillon : débit 706 (la recette diminue), crédit 571 si l'on rembourse en espèces, 411 sinon.
  final especes = suite == 'especes';
  final base = <String, Object?>{
    'numero': reference,
    'date': jourAvoir,
    'journal': 'CAI',
    'journalLibelle': 'Journal de caisse-dépenses',
    'pieceId': idAvoir,
    'pieceNumero': reference,
    'origine': 'Facture d’avoir',
    'statut': 'brouillon',
  };
  final ecritures = [
    {
      ...base,
      'compte': '706000',
      'compteLibelle': 'Prestations de services',
      'libelle': 'Contre-passation — ${facture['numero']} ($motif)',
      'debit': montant,
      'credit': 0,
    },
    {
      ...base,
      'compte': especes ? '571000' : '411000',
      'compteLibelle': especes ? 'Caisse' : 'Clients',
      'libelle': especes
          ? 'Remboursement en espèces — avoir $reference'
          : 'Créance réduite — avoir $reference',
      'debit': 0,
      'credit': montant,
    },
  ];
  return AvoirEmis(
      avoir: fiche,
      ecritures: ecritures,
      montantAvoirs: _n(facture['montantAvoirs']) + montant);
}
