/// LES VERSEMENTS SUCCESSIFS ET LES MODES MULTIPLES (lot PAIE-V, Direction, 20/11/2026 ; docs/prd/PRD-paiement-par-versements-multimodes.md, section BI).
///
/// Port de `prototype_html/assets/js/parcours.js` (bloc « LES VERSEMENTS SUCCESSIFS ET LES MODES MULTIPLES » : `resteDuPiece`, `refusUnVersement`,
/// `controlerVersements`, `modePieceDepuis`) et de `data.js` (`semenceModalitesVersement`, `modaliteVersementALaDate`, `modalitesVersementActives`).
/// Vecteurs : `test/vecteurs/versements.json` (`prototype_html/build/vecteurs-versements.js`, tirés de la maquette ouverte dans Chrome).
///
/// Un patient règle SA part en autant de versements que nécessaire, de modes différents. Les types, modalités et opérateurs de mobile money sont des
/// paramètres de clinique en base (`modalitesVersement`, une fiche par version datée, jamais réécrite), jamais des constantes : ce fichier ne DÉFINIT que
/// leur défaut SEMÉ (proposition à valider) et ce que le moteur en lit à une date. Un refus se nomme (code, motif, geste) et n'écrit rien. La part d'un
/// assureur n'est jamais un versement de caisse. Aucun appel à un opérateur : la référence de la transaction se saisit à la main.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import 'prix_manquant.dart';

/// Le geste réservé de la fiche RBAC qui règle les modalités de versement (jamais un nom de rôle) ; d'origine l'administrateur et la Directrice Administrative.
const String gesteReglerModalitesVersement = 'regler_modalites_versement';

const List<String> famillesVersement = ['type', 'modalite', 'operateur'];

const String sourceModalitesVersement = 'Proposition à valider : réponses de la Direction du 20/11/2026 (DECISIONS-A-VALIDER, section BI)';

/// Les codes de refus nommés (le moteur refuse aussi, au rejeu de la synchronisation).
const String versementSuperieurAuDu = 'VERSEMENT_SUPERIEUR_AU_DU';
const String versementReferenceAbsente = 'VERSEMENT_REFERENCE_ABSENTE';
const String versementModaliteArchivee = 'VERSEMENT_MODALITE_ARCHIVEE';
const String versementPartAssureur = 'VERSEMENT_PART_ASSUREUR';
const String versementPieceSoldee = 'VERSEMENT_PIECE_SOLDEE';

/// Le défaut SEMÉ des modalités (huit fiches), identique à `D.semenceModalitesVersement()` de la maquette.
List<Map<String, Object?>> semenceModalitesVersement() {
  const defs = <Map<String, Object?>>[
    {'famille': 'type', 'code': 'acompte', 'libelle': 'Acompte'},
    {'famille': 'type', 'code': 'solde', 'libelle': 'Solde'},
    {'famille': 'modalite', 'code': 'especes', 'libelle': 'Espèces', 'compte': '571000', 'compteLibelle': 'Caisse', 'exigeReference': false, 'exigeOperateur': false},
    {'famille': 'modalite', 'code': 'mobile_money', 'libelle': 'Mobile money', 'compte': '521000', 'compteLibelle': 'Banques et mobile money', 'exigeReference': true, 'exigeOperateur': true},
    {'famille': 'modalite', 'code': 'tpe', 'libelle': 'TPE (carte bancaire)', 'compte': '521000', 'compteLibelle': 'Banques et mobile money', 'exigeReference': false, 'exigeOperateur': false},
    {'famille': 'operateur', 'code': 'mtn', 'libelle': 'MTN Mobile Money'},
    {'famille': 'operateur', 'code': 'moov', 'libelle': 'Moov Money'},
    {'famille': 'operateur', 'code': 'celtiis', 'libelle': 'Celtiis Cash'},
  ];
  return [
    for (var i = 0; i < defs.length; i++)
      {
        'id': 'MVS-${(i + 1).toString().padLeft(3, '0')}',
        'statut': 'actif',
        'actif': true,
        'dateEffet': null,
        'source': sourceModalitesVersement,
        'motif': 'Défaut semé',
        'creeLe': '2026-11-20',
        'creePar': 'Semence du socle',
        ...defs[i],
      },
  ];
}

String _jour(Object? d) => '$d'.length >= 10 ? '$d'.substring(0, 10) : '$d';

/// Les fiches (toutes versions) d'une famille, de la plus ancienne à la plus récente ; une liste vide retombe sur la semence (comme la maquette).
List<Map<String, Object?>> versionsModalitesVersement(List<Map<String, Object?>> fiches, [String? famille]) {
  final rows = fiches.isEmpty ? semenceModalitesVersement() : fiches;
  final out = [for (final r in rows) if (r['statut'] != 'archive' && (famille == null || r['famille'] == famille)) r];
  out.sort((a, b) {
    final c = '${a['dateEffet'] ?? ''}'.compareTo('${b['dateEffet'] ?? ''}');
    if (c != 0) return c;
    final d = '${a['creeLe'] ?? ''}'.compareTo('${b['creeLe'] ?? ''}');
    return d != 0 ? d : '${a['id']}'.compareTo('${b['id']}');
  });
  return out;
}

/// La version d'un code EN VIGUEUR à une date (même archivée : `actif` dit si elle est proposée) ; null si le code n'a aucune version à cette date.
Map<String, Object?>? modaliteVersementALaDate(List<Map<String, Object?>> fiches, String famille, Object? code, String date) {
  final d = _jour(date);
  Map<String, Object?>? v;
  for (final r in versionsModalitesVersement(fiches, famille)) {
    if (r['code'] == code && (r['dateEffet'] == null || _jour(r['dateEffet']).compareTo(d) <= 0)) v = r;
  }
  return v;
}

/// Les codes PROPOSÉS à la saisie à une date.
List<Map<String, Object?>> modalitesVersementActives(List<Map<String, Object?>> fiches, String famille, String date) {
  final vus = <Object?>{};
  final out = <Map<String, Object?>>[];
  for (final r in versionsModalitesVersement(fiches, famille)) {
    if (vus.add(r['code'])) {
      final v = modaliteVersementALaDate(fiches, famille, r['code'], date);
      if (v != null && v['actif'] != false) out.add(v);
    }
  }
  return out;
}

class RefusVersement {
  const RefusVersement(this.code, this.motif, this.geste, {this.rang, this.famille, this.reste});
  final String code, motif;
  final String? geste, famille;
  final int? rang;
  final double? reste;
}

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

double _n(Object? v) => nombreOuZero(v);

/// Le reste dû par le patient sur une pièce, CALCULÉ : la part patient des lignes valorisées moins le réglé (jamais un champ saisi). [montantPaye] remplace
/// le réglé de la pièce (le cumul des versements déjà reçus).
double resteDuPiece(Map<String, Object?> fac, {Object? montantPaye}) {
  final lignes = ((fac['lignes'] ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
  final du = lignes.isNotEmpty
      ? lignes.where((l) => !ligneSansPrix(l)).fold<double>(0, (n, l) => n + _n(l['partPatient']))
      : _n(fac['partPatient'] != null ? fac['partPatient'] : fac['montantTTC']);
  final r = du - _n(montantPaye ?? fac['montantPaye']);
  return r > 0 ? r : 0;
}

/// Contrôle d'UN versement contre une pièce à une date (pur, sans écriture) : null si recevable, sinon le refus nommé. [dejaVerse] : ce que la pièce a déjà reçu.
RefusVersement? refusUnVersement(Map<String, Object?> fac, Map<String, Object?> v, String date, double dejaVerse, List<Map<String, Object?>> fiches) {
  final lignes = ((fac['lignes'] ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
  final aPartPatient = _n(fac['partPatient']) > 0 || lignes.any((l) => _n(l['partPatient']) > 0);
  if (v['partie'] == 'assureur' || v['cible'] == 'assureur' || !aPartPatient) {
    return const RefusVersement(versementPartAssureur,
        'Un versement de caisse ne règle que la part du PATIENT : la part d’un assureur ou d’un tiers payeur n’est pas un versement de caisse.',
        'Régler la part de l’assureur par le circuit des règlements d’assureurs ou des tiers payeurs.');
  }
  final brut = v['montant'];
  final n = brut is num ? brut.toDouble() : (brut is String && brut.trim().isNotEmpty ? double.tryParse(brut.trim()) : null);
  if (n == null || !n.isFinite || n != n.floorToDouble() || n <= 0) {
    return RefusVersement('VERSEMENT_MONTANT_INVALIDE',
        'Le montant d’un versement est un nombre entier de francs strictement positif (reçu « ${brut ?? ''} »).', 'Saisir un montant entier supérieur à 0.');
  }
  final typ = modaliteVersementALaDate(fiches, 'type', v['type'], date);
  if (!_vrai(v['type']) || typ == null) {
    return RefusVersement('VERSEMENT_TYPE_INCONNU', 'Le type de versement « ${v['type'] ?? ''} » n’existe pas.', 'Choisir un type de versement de la liste.');
  }
  if (typ['actif'] == false) {
    return RefusVersement(versementModaliteArchivee, 'Le type de versement « ${typ['libelle']} » est archivé : il n’est plus proposé à la saisie.',
        'Choisir un type de versement proposé.', famille: 'type');
  }
  final mod = modaliteVersementALaDate(fiches, 'modalite', v['modalite'], date);
  if (!_vrai(v['modalite']) || mod == null) {
    return RefusVersement('VERSEMENT_MODALITE_INCONNUE', 'La modalité de versement « ${v['modalite'] ?? ''} » n’existe pas.', 'Choisir une modalité de la liste.');
  }
  if (mod['actif'] == false) {
    return RefusVersement(versementModaliteArchivee, 'La modalité « ${mod['libelle']} » est archivée : elle n’est plus proposée à la saisie.',
        'Choisir une modalité proposée (une modalité archivée reste lisible sur les pièces passées).', famille: 'modalite');
  }
  if (_vrai(mod['exigeOperateur'])) {
    final op = modaliteVersementALaDate(fiches, 'operateur', v['operateur'], date);
    if (!_vrai(v['operateur'])) {
      return RefusVersement('VERSEMENT_OPERATEUR_ABSENT', 'La modalité « ${mod['libelle']} » exige l’opérateur.', 'Choisir l’opérateur de la transaction.');
    }
    if (op == null) {
      return RefusVersement('VERSEMENT_OPERATEUR_INCONNU', 'L’opérateur « ${v['operateur']} » n’existe pas.', 'Choisir un opérateur de la liste.');
    }
    if (op['actif'] == false) {
      return RefusVersement(versementModaliteArchivee, 'L’opérateur « ${op['libelle']} » est archivé : il n’est plus proposé à la saisie.',
          'Choisir un opérateur proposé.', famille: 'operateur');
    }
  }
  if (_vrai(mod['exigeReference']) && '${v['referenceTransaction'] ?? ''}'.trim().isEmpty) {
    return RefusVersement(versementReferenceAbsente, 'La modalité « ${mod['libelle']} » exige la référence de la transaction (saisie à la main).',
        'Saisir la référence de la transaction relevée sur le message de l’opérateur.');
  }
  final reste = resteDuPiece(fac, montantPaye: dejaVerse);
  if (n > reste) {
    return RefusVersement(
        versementSuperieurAuDu,
        'Versement de ${money(n)} refusé : la pièce ${_vrai(fac['numero']) ? fac['numero'] : fac['id']} ne doit plus que ${money(reste)}. Un versement ne dépasse jamais le dû de la part du patient.',
        'Réduire le montant (le reste dû est ${money(reste)}) ; un trop-perçu se rend, il ne s’enregistre pas.',
        reste: reste);
  }
  return null;
}

class ControleVersements {
  const ControleVersements.ok(this.lignes, this.total) : refus = null;
  const ControleVersements.refus(this.refus)
      : lignes = const [],
        total = 0;
  final List<Map<String, Object?>> lignes;
  final double total;
  final RefusVersement? refus;
  bool get ok => refus == null;
}

/// Contrôle d'un LOT de versements saisis ensemble (pur, sans écriture) : les lignes normalisées et le total, ou le refus nommé du premier versement fautif.
ControleVersements controlerVersements(Map<String, Object?> fac, List<Map<String, Object?>> versements, String date, List<Map<String, Object?>> fiches) {
  if (fac['statutPaiement'] == 'soldee') {
    return ControleVersements.refus(RefusVersement(versementPieceSoldee,
        'La pièce ${_vrai(fac['numero']) ? fac['numero'] : fac['id']} est soldée : aucun versement ne s’y ajoute.',
        'Pour rendre un trop-perçu ou corriger, émettre un avoir ou un remboursement ; la pièce ne se réécrit pas.'));
  }
  if (versements.isEmpty) {
    return const ControleVersements.refus(RefusVersement('VERSEMENT_AUCUN', 'Aucun versement à enregistrer.', 'Ajouter au moins un versement.'));
  }
  var cumul = _n(fac['montantPaye']);
  var total = 0.0;
  final lignes = <Map<String, Object?>>[];
  for (var i = 0; i < versements.length; i++) {
    final v = versements[i];
    final refus = refusUnVersement(fac, v, date, cumul, fiches);
    if (refus != null) {
      return ControleVersements.refus(RefusVersement(refus.code, (versements.length > 1 ? 'Versement ${i + 1} : ' : '') + refus.motif, refus.geste,
          rang: i + 1, famille: refus.famille, reste: refus.reste));
    }
    final mod = modaliteVersementALaDate(fiches, 'modalite', v['modalite'], date)!;
    final typ = modaliteVersementALaDate(fiches, 'type', v['type'], date)!;
    final op = _vrai(mod['exigeOperateur']) ? modaliteVersementALaDate(fiches, 'operateur', v['operateur'], date) : null;
    final ref = '${v['referenceTransaction'] ?? ''}'.trim();
    final montant = v['montant'] is num ? (v['montant']! as num).toDouble() : double.parse('${v['montant']}'.trim());
    lignes.add({
      'type': v['type'],
      'typeLibelle': typ['libelle'],
      'modalite': v['modalite'],
      'modaliteLibelle': mod['libelle'],
      'compte': mod['compte'],
      'compteLibelle': mod['compteLibelle'] ?? mod['libelle'],
      'montant': montant,
      if (op != null) 'operateur': op['code'],
      if (op != null) 'operateurLibelle': op['libelle'],
      if (ref.isNotEmpty) 'referenceTransaction': ref,
    });
    cumul += montant;
    total += montant;
  }
  return ControleVersements.ok(lignes, total);
}

/// Le mode porté par la pièce : la modalité unique si tous les versements en ont une (MTN et Moov gardent leur ancien identifiant), « mixte » sinon.
String modePieceDepuis(List<Map<String, Object?>> lignes) {
  final codes = <String>{};
  for (final v in lignes) {
    codes.add(v['modalite'] == 'mobile_money' && (v['operateur'] == 'mtn' || v['operateur'] == 'moov') ? '${v['operateur']}' : '${v['modalite']}');
  }
  return codes.length == 1 ? codes.first : 'mixte';
}

/// LE REJEU (synchronisation, famille A) : la mère REFUSE un versement qui, ajouté à ceux déjà reçus pour la pièce, ferait dépasser le dû de la part du
/// patient (deux fileuls qui encaissent la même pièce hors ligne). Le moteur refuse aussi : masquer un bouton ne protège rien. [dejaVerse] : la somme des
/// versements ACTIFS déjà connus de la pièce. Retourne le refus nommé, ou null si le versement se rejoue.
RefusVersement? refusRejeuVersement(Map<String, Object?> facture, Map<String, Object?> entrant, double dejaVerse, List<Map<String, Object?>> fiches) {
  final date = _jour(entrant['date'] ?? '');
  return refusUnVersement(facture, entrant, date, dejaVerse, fiches);
}

/// Ancien mode de la maquette (`modePaiement`) vers la modalité de versement (`{modalite, operateur?}`) ; null pour un mode qui n'est pas un versement de caisse
/// (la prise en charge d'une assurance). Sert aux encaissements faits par montant et mode uniques, qui laissent AUSSI une fiche de versement.
Map<String, String>? modaliteDepuisMode(Object? mode) => switch ('$mode') {
      'especes' => {'modalite': 'especes'},
      'tpe' => {'modalite': 'tpe'},
      'mtn' => {'modalite': 'mobile_money', 'operateur': 'mtn'},
      'moov' => {'modalite': 'mobile_money', 'operateur': 'moov'},
      _ => null,
    };
