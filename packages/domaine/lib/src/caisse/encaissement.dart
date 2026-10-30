/// ENCAISSEMENT — cœur arithmétique de `PR.encaisser` et de `ecrireEncaissement` (prototype_html/assets/js/parcours.js).
///
/// Porté ICI : quelles lignes un versement règle, l'état de la facture après versement (reliquat, solde, base MECeF),
/// et l'écriture comptable équilibrée (RG-10). Hors de ce fichier, dans l'orchestration du poste : le déblocage du
/// laboratoire, de l'imagerie et des tâches d'aval, la journalisation (RG-12), l'insertion en base.
///
/// Les vecteurs (`test/vecteurs/encaissement.json`) sont des SÉQUENCES de versements engendrées par la maquette.
///
/// Corrigés dans la maquette PUIS portés (docs/architecture/ECARTS-MAQUETTE.md, E1 et E3, décision du 30/10/2026) :
///   · la part assureur n'est constatée (411 / 706) qu'au PREMIER versement d'une facture ;
///   · le numéro de pièce est une série annuelle : millésime de la date, rang suivant, repris par les versements suivants.
/// Reste porté fidèlement et signalé : une pièce sans lignes accepte un versement supérieur au dû (E2).
library;

import '../format/js.dart';

const compteCaisse = '571000';
const compteClientsAssurance = '411110';
const comptePrestations = '706000';

class ResultatEncaissement {
  const ResultatEncaissement({required this.facture, required this.deja, required this.lignesReglees, required this.montantRegle, required this.restantDu, required this.ecritures});

  /// La facture APRÈS versement (copie ; l'entrée n'est jamais modifiée).
  final Map<String, Object?> facture;

  /// La facture était déjà soldée : rien ne bouge.
  final bool deja;
  final List<String> lignesReglees;
  final double? montantRegle;
  final double? restantDu;
  final List<Map<String, Object?>> ecritures;
}

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

double _n(Object? v) => nombreOuZero(v);

/// `PR.encaisser(factureId, {lignes | montant, mode})`. `aujourdhui` : `YYYY-MM-DD` de l'écriture ; `maintenant` : ISO.
ResultatEncaissement encaisser(
  Map<String, Object?> facture, {
  List<String>? lignes,
  num? montant,
  String? mode,
  required String aujourdhui,
  required String maintenant,
  String utilisateur = '',
  List<Map<String, Object?>> ecritures = const [],
}) {
  if (facture['statutPaiement'] == 'soldee') {
    return ResultatEncaissement(facture: facture, deja: true, lignesReglees: const [], montantRegle: null, restantDu: null, ecritures: const []);
  }
  final toutes = ((facture['lignes'] ?? const []) as List).map((l) => (l as Map).cast<String, Object?>()).toList();
  final duTotal = facture['partPatient'] != null ? _n(facture['partPatient']) : _n(facture['montantTTC']);

  final reglees = <Map<String, Object?>>[];
  var paye = 0.0;
  if (lignes != null && lignes.isNotEmpty) {
    final vises = lignes.toSet();
    for (final l in toutes) {
      if (l['statutPaiement'] == 'paye' || !vises.contains(l['id'])) continue;
      reglees.add(l);
      paye += _n(l['partPatient']);
    }
  } else if (toutes.isNotEmpty) {
    // Allocation d'un montant global : les lignes dues, dans l'ordre, tant que la somme versée les couvre ENTIÈREMENT.
    var reste = montant != null ? montant.toDouble() : duTotal;
    for (final l in toutes) {
      if (l['statutPaiement'] == 'paye') continue;
      final part = _n(l['partPatient']);
      if (part <= reste) {
        reglees.add(l);
        reste -= part;
        paye += part;
      }
    }
  } else {
    // Pièce antérieure au modèle par lignes : on conserve le comportement par montant.
    paye = montant != null ? montant.toDouble() : duTotal;
  }

  final lignesMaj = toutes.map((l) {
    if (!reglees.any((r) => identical(r, l))) return l;
    return {...l, 'statutPaiement': 'paye', 'montantRegle': l['partPatient'], 'payeLe': maintenant, 'payePar': utilisateur};
  }).toList();
  final totalPaye = _n(facture['montantPaye']) + paye;
  final restantDu = lignesMaj.isNotEmpty
      ? lignesMaj.where((l) => l['statutPaiement'] != 'paye').fold(0.0, (n, l) => n + _n(l['partPatient']))
      : (duTotal - totalPaye) > 0 ? duTotal - totalPaye : 0.0;
  final solde = restantDu <= 0;
  final modeRetenu = _vrai(mode) ? mode! : 'especes';

  final apres = <String, Object?>{
    ...facture,
    'lignes': lignesMaj,
    'montantPaye': totalPaye,
    'reliquat': restantDu,
    'modePaiement': modeRetenu,
    'statutPaiement': solde ? 'soldee' : (totalPaye > 0 ? 'partielle' : 'impayee'),
    'statutMecef': solde ? 'valide' : 'en_attente',
    // Le point fiscal : seule la part réglée par le patient est normalisée (ni la part assureur, ni les remises).
    'baseMecef': totalPaye,
    'dernierReglement': {'date': maintenant, 'montant': paye, 'mode': modeRetenu, 'lignes': reglees.map((l) => l['id']).toList(), 'encaissePar': utilisateur},
  };

  final posees = paye > 0 ? ecritureEncaissement(apres, paye, aujourdhui, ecritures) : <Map<String, Object?>>[];
  return ResultatEncaissement(
    facture: apres,
    deja: false,
    lignesReglees: [for (final l in reglees) '${l['id']}'],
    montantRegle: paye,
    restantDu: restantDu,
    ecritures: posees,
  );
}

/// La créance sur l'assureur est-elle déjà constatée pour cette facture (une écriture 411 non archivée) ?
bool creanceAssureurConstatee(Map<String, Object?> facture, List<Map<String, Object?>> ecritures) =>
    ecritures.any((e) => e['pieceId'] == facture['id'] && e['compte'] == compteClientsAssurance && e['statut'] != 'archive');

/// Numéro de pièce de caisse : celui de la première écriture de la facture, sinon `CAI-AAAA-NNNNN` (rang suivant de l'année).
String numeroPieceCaisse(Map<String, Object?> facture, String date, List<Map<String, Object?>> ecritures) {
  for (final e in ecritures) {
    if (e['pieceId'] == facture['id'] && e['journal'] == 'CAI' && _vrai(e['numero'])) return '${e['numero']}';
  }
  final prefixe = 'CAI-${date.substring(0, 4)}-';
  var max = 0;
  for (final e in ecritures) {
    final n = e['numero'];
    if (n is String && n.startsWith(prefixe)) {
      final rang = int.tryParse(n.substring(prefixe.length)) ?? 0;
      if (rang > max) max = rang;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(5, '0')}';
}

/// Écriture d'encaissement : débit 571 de la part réglée, débit 411 de la part assureur (au premier versement seulement),
/// crédit 706 du total. Contrôlée ÉQUILIBRÉE avant d'exister (RG-10) : un déséquilibre rend une liste vide. Brouillon.
List<Map<String, Object?>> ecritureEncaissement(Map<String, Object?> facture, double montantRegle, String aujourdhui, [List<Map<String, Object?>> ecritures = const []]) {
  final partAssureur = creanceAssureurConstatee(facture, ecritures) ? 0.0 : _n(facture['partAssureur']);
  final total = montantRegle + partAssureur;
  if (total <= 0) return const [];

  final ref = '${_vrai(facture['numero']) ? facture['numero'] : facture['id']}';
  final numero = numeroPieceCaisse(facture, aujourdhui, ecritures);
  final base = <String, Object?>{
    'numero': numero, 'date': aujourdhui, 'journal': 'CAI', 'journalLibelle': 'Journal de caisse-dépenses',
    'libelle': 'Encaissement facture $ref — ${facture['patient'] ?? ''}',
    'pieceId': facture['id'], 'pieceNumero': facture['numero'], 'origine': 'Automatique — Caisse', 'statut': 'brouillon',
  };
  final l = <Map<String, Object?>>[];
  if (montantRegle > 0) l.add({...base, 'compte': compteCaisse, 'debit': montantRegle, 'credit': 0.0});
  if (partAssureur > 0) {
    l.add({...base, 'compte': compteClientsAssurance, 'debit': partAssureur, 'credit': 0.0, 'libelle': '${base['libelle']} — part ${_vrai(facture['assureur']) ? facture['assureur'] : 'assureur'}'});
  }
  l.add({...base, 'compte': comptePrestations, 'debit': 0.0, 'credit': total});

  final debit = l.fold(0.0, (n, x) => n + (x['debit']! as double));
  final credit = l.fold(0.0, (n, x) => n + (x['credit']! as double));
  if (debit != credit) return const [];
  return l;
}
