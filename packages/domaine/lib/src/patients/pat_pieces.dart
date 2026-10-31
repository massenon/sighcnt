/// M1 — CERTIFICATS & ATTESTATIONS : les quatorze pièces certifiantes, leur numérotation annuelle, leur passage par la caisse (`PR.facturerPiece`)
/// et l'état de règlement LU sur la pièce de caisse (`PR.statutPiece`). Rejoué sur `test/vecteurs/pat_pieces.json`.
///
/// L'assurance ne couvre aucun certificat, SOS excepté : la couverture est portée par `assurable` (`true` / `false` / `'sos'`) — un booléen aurait
/// forcé à choisir entre exclure SOS à tort et ouvrir la couverture aux treize compagnies à tort.
library;

import '../caisse/prise_en_charge.dart' show carteValide;
import '../format/format_fr.dart';
import '../format/js.dart' show arrondiJs, nombreOuZero;
import 'pat_patients.dart';

/// Un type de pièce certifiante (collection `typesPiece` de la maquette, semée au socle).
class PatTypePiece {
  const PatTypePiece(this.id, this.sigle, this.libelle, this.direction, this.tarifCode, this.collision, this.examens);
  final String id;
  final String sigle;
  final String libelle;
  final String direction;
  final String? tarifCode;

  /// Deux sigles sont partagés dans les sources (CMA, CMD) : conservés et SIGNALÉS — renuméroter romprait la correspondance avec les registres papier.
  final String? collision;

  /// Le prénuptial ne se saisit pas : il se remplit depuis ces six examens validés biologiquement.
  final List<String>? examens;
}

/// Les quatorze types, tels que `store.seed()` les sème (extraits du magasin de la maquette par `vecteurs-m1.js`).
const patTypesPiece = <PatTypePiece>[
  PatTypePiece('TPC01', 'ATG', 'Attestation de grossesse', 'DG/DE', 'CERT-ATG', null, null),
  PatTypePiece('TPC02', 'CMNI', 'Certificat médical de non-infirmité', 'DG/DE', null, null, null),
  PatTypePiece('TPC03', 'CMA', 'Certificat médical d’accouchement', 'DG/DE', null, 'Le sigle CMA désigne aussi le certificat médical d’aptitude.', null),
  PatTypePiece('TPC04', 'CMA', 'Certificat médical d’aptitude', 'DG/DE', 'CERT-APT', 'Le sigle CMA désigne aussi le certificat médical d’accouchement.', null),
  PatTypePiece('TPC05', 'CMH', 'Certificat médical d’hospitalisation (garde-malade)', 'DG/DE', null, null, null),
  PatTypePiece('TPC06', 'CMD', 'Certificat médical de décès', 'DA', 'CERT-DEC', 'Le sigle CMD désigne aussi le certificat de genre de mort.', null),
  PatTypePiece('TPC07', 'CMD', 'Certificat médical de genre de mort', 'DA', null, 'Le sigle CMD désigne aussi le certificat médical de décès.', null),
  PatTypePiece('TPC08', 'CMP', 'Certificat médical prénuptial', 'CN', null, null, ['LAB-GSRH', 'LAB-HEPB', 'LAB-HEPC', 'LAB-TPHA', 'LAB-HIV', 'LAB-EPHB']),
  PatTypePiece('TPC09', 'CMCBV', 'Certificat médical de coups et blessures volontaires', 'CN', 'CERT-CBV', null, null),
  PatTypePiece('TPC10', 'CMDPS', 'Certificat médical de dispense aux activités physiques et sportives', 'DG/DE', 'CERT-DPS', null, null),
  PatTypePiece('TPC11', 'CMNCI', 'Certificat médical de non contre-indication aux activités physiques et sportives', 'DM/DA', null, null, null),
  PatTypePiece('TPC12', 'CMVC', 'Certificat médical de visite et de contre-visite', 'DG/DE', 'CERT-VC', null, null),
  PatTypePiece('TPC13', 'CMR-H', 'Certificat médical d’arrêt de travail et/ou d’hospitalisation', 'DG/DA', null, null, null),
  PatTypePiece('TPC14', 'SCAM', 'Sortie contre avis médical', 'CN', null, null, null),
];

String _pad(int n, int l) => n.toString().padLeft(l, '0');

/// `numeroter(t)` : le numéro d'ordre est propre au sigle ET à l'année (la série repart à 1 chaque 1er janvier, comme le registre papier) ; il
/// compte les pièces de la série, archivées comprises. Référence : `<SIGLE> 007/007/CNT/<direction>/<année>`.
({int numero, int annee, String reference}) patNumeroter(PatTypePiece t, Iterable<FichePat> pieces, int annee) {
  final n = pieces.where((x) => x['sigle'] == t.sigle && x['annee'] == annee).length + 1;
  return (
    numero: n,
    annee: annee,
    reference: '${t.sigle} ${_pad(n, 3)}/${_pad(n, 3)}/CNT/${t.direction}/$annee'
  );
}

/// Un patient est EXTERNE si son dossier le dit — jamais la pièce : la qualité appartient au dossier.
bool patEstExterne(FichePat piece, Iterable<FichePat> patients) {
  final id = piece['patientId'];
  final p = id != null
      ? patients.where((x) => x['id'] == id).firstOrNull
      : patients.where((x) => x['statut'] != 'archive' && x['code'] == piece['patientCode']).firstOrNull;
  return p != null && patVrai(p['externe']);
}

/// La couverture portée SUR la pièce : au guichet, « pourquoi je paie tout ? » doit trouver sa réponse sur le document.
String patCouverturePiece(Object? assurable) => assurable == 'sos'
    ? 'Couvert par SOS uniquement — toute autre compagnie : à la charge du patient'
    : 'Non couvert par les assurances';

class PatFacturePiece {
  const PatFacturePiece(this.facture, this.tache);
  final FichePat facture;
  final FichePat tache;
}

/// `PR.facturerPiece(v)` : une pièce tarifée passe par la caisse. `null` pour une pièce non tarifée. Seul SOS couvre un certificat, et seulement
/// carte valide à la date : la répartition suit la grille (`assurable == 'sos'`), non le taux du dossier.
PatFacturePiece? patFacturerPiece({
  required FichePat patient,
  required num? montant,
  required String libelle,
  required String reference,
  required String? acteCode,
  required Object? assurable,
  required Iterable<FichePat> couvertures,
  required int nbFactures,
  required String Function(String prefixe) nouvelId,
  required DateTime date,
}) {
  final m = arrondiJs(nombreOuZero(montant)).toInt();
  if (!(m > 0)) return null;
  final jour = iso(date);
  final couvert = assurable == 'sos' &&
      '${patient['assureur'] ?? ''}' == 'SOS' &&
      carteValide(patient, [for (final c in couvertures) c], date.toIso8601String());
  final taux = couvert ? nombreOuZero(patient['tauxPriseEnCharge']) : 0.0;
  final estAgent = patVrai(patient['personnelId']);
  final partAssureur = estAgent ? 0 : arrondiJs(m * taux / 100).toInt();
  final partPersonnel = estAgent ? m : 0;
  final partPatient = m - partAssureur - partPersonnel;
  final nom = '${patient['nom']} ${patient['prenom']}';
  final ligne = <String, Object?>{
    'id': 'L001',
    'categorie': 'acte',
    'designation': libelle,
    'quantite': 1,
    'prixUnitaire': m,
    'prixUnitaireNet': m,
    'montantBrut': m,
    'remise': 0,
    'motifRemise': null,
    'montant': m,
    'partAssureur': partAssureur,
    'partPersonnel': partPersonnel,
    'partPatient': partPatient,
    'demandeId': null,
    'produitId': null,
    'acteCode': acteCode,
    'demandeImagerieId': null,
    'statutPaiement': 'du',
    'montantRegle': 0,
    'payeLe': null,
    'payePar': null,
    'pieceRef': reference,
  };
  final numero = 'FC-${date.year}-${_pad(nbFactures + 1, 5)}';
  final id = nouvelId('FAC');
  final facture = <String, Object?>{
    'id': id,
    'lignes': [ligne],
    'numero': numero,
    'numeroMecef': null,
    'patientId': patient['id'],
    'patient': nom,
    'patientCode': patient['code'],
    'date': jour,
    'type': 'Certificat & attestation',
    'montantHT': m,
    'montantTTC': m,
    'montantBrut': m,
    'totalRemise': 0,
    'partPersonnel': partPersonnel,
    'priseEnChargePersonnel': estAgent,
    'personnelId': estAgent ? patient['personnelId'] : null,
    'assureur': patVrai(patient['assureur']) ? patient['assureur'] : null,
    'tauxPriseEnCharge': taux,
    'partAssurance': partAssureur,
    'partPatient': partPatient,
    'montantPaye': 0,
    'reliquat': partPatient,
    'modePaiement': null,
    'statutPaiement': 'impayee',
    'statutMecef': 'en_attente',
    'pieceId': null,
    'pieceRef': reference,
    'motifCouverture': couvert
        ? 'Certificat couvert par SOS — seule compagnie conventionnée sur ces pièces'
        : 'Certificat non couvert par les assurances (mention de la grille tarifaire)',
    'statut': 'actif',
  };
  final tache = <String, Object?>{
    'id': nouvelId('TCH'),
    'type': 'encaissement',
    'poste': 'caisse',
    'libelle': '$libelle — $nom',
    'detail': '$reference — ${money(m, avecDevise: false)}',
    'reference': numero,
    'factureId': id,
    'patientId': patient['id'],
    'patient': nom,
    'montant': partPatient,
    'statut': 'en_attente',
    'creeLe': date.toUtc().toIso8601String(),
  };
  return PatFacturePiece(facture, tache);
}

class PatStatutPiece {
  const PatStatutPiece(this.code, this.label, this.ton, this.detail, [this.facture]);
  final String code;
  final String label;

  /// `success` · `danger` · `warning` · `neutral` (tons de la maquette).
  final String ton;
  final String detail;
  final FichePat? facture;
}

/// `PR.statutPiece(piece)` : l'état de règlement est LU sur la ligne de facture, jamais stocké sur la pièce (deux vérités, c'est la mauvaise qu'on
/// afficherait). TROIS réponses : réglé · à encaisser · sans pièce liée — les dire impayées serait aussi faux que les dire réglées.
PatStatutPiece patStatutPiece(FichePat? piece, Iterable<FichePat> factures) {
  if (piece == null) return const PatStatutPiece('inconnu', '—', 'neutral', '');
  if (!patVrai(piece['montant'])) {
    return const PatStatutPiece('non_tarife', 'Non tarifée', 'neutral', 'Aucun tarif à la grille : rien à encaisser.');
  }
  final f = patVrai(piece['factureId'])
      ? factures.where((x) => x['id'] == piece['factureId']).firstOrNull
      : null;
  if (f == null) {
    return const PatStatutPiece('sans_piece', 'En attente', 'warning',
        'Aucune pièce de caisse liée — certificat délivré avant que la caisse ne soit dans le circuit. Ni réglé, ni impayé : on ne sait pas.');
  }
  final dues = ((f['lignes'] as List?) ?? const []).where((l) => (l as Map)['statutPaiement'] != 'paye').length;
  if (dues == 0) {
    return PatStatutPiece('regle', 'Réglé', 'success', 'Réglé à la caisse — pièce ${f['numero']}.', f);
  }
  final reste = patVrai(f['reliquat']) ? f['reliquat'] : f['partPatient'];
  return PatStatutPiece('a_encaisser', 'À encaisser', 'danger',
      'Le patient doit se présenter à la caisse avec la pièce ${f['numero']} — reste dû ${money(reste, avecDevise: false)}.', f);
}

class PatKpisPieces {
  const PatKpisPieces(this.delivrees, this.clinique, this.externes, this.exercice, this.encaisse, this.aEncaisser, this.sansPiece);
  final int delivrees;
  final int clinique;
  final int externes;
  final int exercice;
  final num encaisse;
  final num aEncaisser;
  final int sansPiece;
}

/// Les recettes sont celles qui sont ENTRÉES : le total des montants comptait des sommes jamais encaissées. (Écart E308 : « À encaisser » cumule le
/// MONTANT de la pièce, non la part restant due au patient — un assuré SOS y pèse 8 000 pour 1 600 dus. Porté fidèlement.)
PatKpisPieces patKpisPieces(List<FichePat> rows, Iterable<FichePat> patients, Iterable<FichePat> factures, int annee) {
  num regle = 0, aEnc = 0;
  var sans = 0;
  for (final r in rows) {
    final st = patStatutPiece(r, factures);
    final m = nombreOuZero(r['montant']);
    if (st.code == 'regle') {
      regle += m;
    } else if (st.code == 'a_encaisser') {
      aEnc += m;
    } else if (st.code == 'sans_piece') {
      sans += 1;
    }
  }
  final externes = rows.where((r) => patEstExterne(r, patients)).length;
  return PatKpisPieces(rows.length, rows.length - externes, externes,
      rows.where((r) => r['annee'] == annee).length, regle, aEnc, sans);
}
