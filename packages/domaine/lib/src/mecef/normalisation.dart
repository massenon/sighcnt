/// MECeF, lot M1 : les contrôles qui précèdent la normalisation d'une vente, et les règles de retransmission.
///
/// Port de `normaliserVente` et `retransmettreMecef` (`prototype_html/assets/js/parcours.js`, E2299), SANS leur appareil : la maquette y simule un
/// boîtier, le poste n'en a aucun de branché et n'invente ni protocole ni adresse. Ce qui est porté, c'est la DÉCISION (refus nommés, acheteur,
/// montants entiers) ; l'émission d'un numéro reste un geste de l'appareil, simulé et marqué comme tel par l'appelant.
/// Les fonctions de montants et d'acheteur sont rejouées sur `mecef_montants.json` ; celles-ci sont éprouvées par `mecef_normalisation_test.dart`.
library;

import 'etats.dart';
import 'montants.dart';

/// Ce que la normalisation retient d'une pièce, ou le refus nommé.
class PreparationNormalisation {
  const PreparationNormalisation.ok(AcheteurMecef this.acheteur, MontantsMecef this.montants) : refus = null, ignore = false;
  const PreparationNormalisation.refus(RefusMecef this.refus)
      : acheteur = null,
        montants = null,
        ignore = false;
  const PreparationNormalisation.ignoree()
      : acheteur = null,
        montants = null,
        refus = null,
        ignore = true;
  final AcheteurMecef? acheteur;
  final MontantsMecef? montants;
  final RefusMecef? refus;

  /// Mode « Désactivé » (démonstration) : aucune normalisation.
  final bool ignore;
  bool get ok => acheteur != null;
}

num _num(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// L'acheteur d'une pièce : ce que la fenêtre a saisi, sinon ce que la pièce porte déjà, sinon les défauts (particulier, AIB par défaut).
({AcheteurMecef? acheteur, RefusMecef? refus}) acheteurDePiece(
    Map<String, Object?> fac,
    {Map<String, Object?>? saisi,
    int aibParDefaut = aibTauxParDefaut}) {
  final s = saisi ?? const {};
  return validerAcheteurMecef(
    ifu: s.containsKey('ifu') ? s['ifu'] : fac['ifuClient'],
    nom: s.containsKey('nom') ? s['nom'] : fac['acheteurNom'],
    aibTaux: s.containsKey('aibTaux') ? s['aibTaux'] : fac['aibTaux'],
    aibParDefaut: aibParDefaut,
  );
}

/// L'entrée de la fonction des montants pour une pièce de caisse (la pièce garde ses montants).
List<Map<String, Object?>> lignesMontantsPiece(Map<String, Object?> fac) {
  final ls = fac['lignes'];
  if (ls is List && ls.isNotEmpty) {
    return [for (final l in ls) ligneVersMecef((l as Map).cast<String, Object?>())];
  }
  return [
    {
      'designation': 'Prestation',
      'quantite': 1,
      'montantBrut': fac['montantTTC'],
      'prixUnitaire': fac['montantTTC'],
      'partAssureur': fac['partAssurance'] ?? 0,
      'partPersonnel': fac['partPersonnel'] ?? 0,
    }
  ];
}

/// Les contrôles de la normalisation d'une vente, dans l'ordre de la maquette : pro-forma, règlement, mode, déjà normalisée, acheteur, montants.
/// Un refus des montants est rendu avec ses données : l'appelant écrit alors la pièce `refusee` en nommant le code.
PreparationNormalisation preparerNormalisation(
  Map<String, Object?> fac, {
  Map<String, Object?>? acheteurSaisi,
  bool modeDesactive = false,
  int aibParDefaut = aibTauxParDefaut,
  num tauxTvaCourant = 0,
}) {
  final num_ = '${fac['numero'] ?? fac['id']}';
  if (fac['proforma'] == true) {
    return const PreparationNormalisation.refus(RefusMecef(
        'PROFORMA',
        'Une pro-forma n’est pas une vente : elle ne se normalise pas.',
        'Émettre la facture de vente.'));
  }
  if (!(_num(fac['montantPaye']) > 0)) {
    return PreparationNormalisation.refus(RefusMecef(
        'VENTE_NON_ENCAISSEE',
        'La facture $num_ n’a encaissé aucun règlement : une vente se normalise à l’encaissement.',
        'Encaisser la vente à la caisse.'));
  }
  if (modeDesactive) return const PreparationNormalisation.ignoree();
  if (porteBlocFiscal(fac)) {
    return PreparationNormalisation.refus(RefusMecef(
        'DEJA_NORMALISEE',
        'La facture $num_ est déjà normalisée (${fac['numeroMecef']}) : elle ne se renormalise jamais.',
        'La corriger par un avoir.'));
  }
  final ach = acheteurDePiece(fac, saisi: acheteurSaisi, aibParDefaut: aibParDefaut);
  if (ach.refus != null) return PreparationNormalisation.refus(ach.refus!);
  final m = mecefMontants(
    lignes: lignesMontantsPiece(fac),
    totalAttendu: _num(fac['montantTTC']),
    aibTaux: ach.acheteur!.aibTaux,
    tauxTvaCourant: tauxTvaCourant,
  );
  if (!m.ok) return PreparationNormalisation.refus(m.refus!);
  return PreparationNormalisation.ok(ach.acheteur!, m.montants!);
}

/// Un numéro simulé jamais déjà porté : le tirage, avancé d'un cran tant qu'il est pris.
String numeroMecefLibre(int tire, Set<String> pris) {
  var n = tire;
  while (pris.contains('MECEF$n')) {
    n++;
  }
  return 'MECEF$n';
}

/// Qui peut retransmettre une pièce (PRD section 7, Q7) : le caissier UNE fois, puis la Directrice Administrative et l'administrateur ; jamais une
/// vente normalisée ; une vente « à vérifier » se reprend, elle ne se retransmet pas. Null quand c'est permis.
RefusMecef? refusRetransmission(Map<String, Object?> fac, String role) {
  final num_ = '${fac['numero'] ?? fac['id']}';
  final etat = etatMecefDe(fac)?.id;
  if (etat == 'normalisee') {
    return RefusMecef(
        'DEJA_NORMALISEE',
        'La facture $num_ est déjà normalisée (${fac['numeroMecef']}) : elle ne se retransmet jamais.',
        'La corriger par un avoir.');
  }
  if (!const ['refusee', 'expiree', 'en_attente'].contains(etat)) {
    return RefusMecef(
        'PAS_RETRANSMISSIBLE',
        'La facture $num_ est à vérifier : elle se reprend sans doubler, elle ne se retransmet pas.',
        'Utiliser « Reprendre sans doubler ».');
  }
  final deja = _num(fac['retransmissions']).toInt();
  if (role == 'caissier' && deja >= 1) {
    return RefusMecef(
        'RETRANSMISSION_RESERVEE',
        'Le caissier ne retransmet qu’une fois : la facture $num_ l’a déjà été.',
        'Demander la retransmission à la Directrice Administrative.');
  }
  if (!const ['caissier', 'da', 'admin'].contains(role)) {
    return const RefusMecef(
        'RETRANSMISSION_INTERDITE',
        'La retransmission est réservée au caissier (une fois) et à la Directrice Administrative.',
        'Demander à la caisse ou à la DA.');
  }
  return null;
}
