import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import '../core/service_parametres.dart';
import '../modules/m2/cs_commun.dart' show StockMagasin;
import 'magasin.dart';
import 'normalisation_mecef.dart';
import 'versements_poste.dart';

/// LOT TARIF-FIX-2 : le réglage de clinique « encaisser le reste d'une pièce en attente de prix » à la date du geste (paramètre versionné, défaut semé « non »).
bool encaissementPartielPoste(Magasin m, DateTime maintenant) =>
    serviceParametres(m, auteur: () => m.utilisateur, horloge: () => maintenant).valeur(d.cleEncaissementPartielSansPrix, d.iso(maintenant)) == 'oui';

/// VALORISE les lignes sans prix d'une pièce dont le prix est désormais en vigueur à SA date (moteur du domaine `csValoriserFacture`). Rend les lignes valorisées.
List<Map<String, Object?>> valoriserFacturePoste(Magasin m, String factureId, DateTime maintenant) =>
    d.csValoriserFacture(StockMagasin(m, () => maintenant), factureId).valorisees;

/// Valorise toutes les pièces en attente (ouverture de la caisse, décision d'un prix). Rend le nombre de lignes valorisées.
int valoriserEnAttentePoste(Magasin m, DateTime maintenant) {
  var n = 0;
  for (final f in [...m.collection('factures').actives]) {
    if (f['statutPaiement'] == 'soldee' || d.lignesPrixManquant(f).isEmpty) continue;
    n += valoriserFacturePoste(m, '${f['id']}', maintenant).length;
  }
  return n;
}

/// Le titre court dit à la place d'une commande « Encaisser » absente : « En attente de prix : « CODE » prix à définir, … ».
String titreSansPrix(({String code, String motif, String geste, List<Map<String, Object?>> lignes, bool partiel}) refus) =>
    'En attente de prix : ${refus.lignes.map((x) => '« ${x['code']} » ${x['nature'] == d.natureManquePrixAchat ? 'prix à valoriser' : 'prix à définir'}').join(', ')}';

/// L'ÉTAT DE CAISSE d'une pièce pour l'écran : `refus` non nul quand l'encaissement serait refusé (la commande est alors ABSENTE, le motif est dit à sa place).
({bool encaissable, bool partiel, List<Map<String, Object?>> manques, ({String code, String motif, String geste, List<Map<String, Object?>> lignes, bool partiel})? refus})
    etatCaissePrix(Magasin m, Fiche facture, DateTime maintenant) {
  final enAttente = d.lignesPrixManquant(facture);
  if (enAttente.isEmpty) return (encaissable: true, partiel: false, manques: const [], refus: null);
  final stock = StockMagasin(m, () => maintenant);
  final manques = [
    for (final l in enAttente)
      if (d.csPrixLigneEnAttente(stock, facture, l) case final r when !r.ok) r.manque!
  ];
  if (manques.isEmpty) return (encaissable: true, partiel: false, manques: const [], refus: null);
  final partiel = encaissementPartielPoste(m, maintenant);
  final reste = ((facture['lignes'] as List?) ?? const []).any((x) => !d.ligneSansPrix((x as Map).cast<String, Object?>()) && x['statutPaiement'] != 'paye');
  final refus = d.refusEncaissementPrix(facture, manques, partiel, aujourdhui: d.iso(maintenant));
  return (encaissable: partiel && reste, partiel: partiel, manques: manques, refus: refus);
}

/// Refus NOMMÉ d'une opération de caisse : un code, un motif lisible (jamais un échec muet).
class RefusCaisse implements Exception {
  const RefusCaisse(this.code, this.motif);
  final String code;
  final String motif;
  @override
  String toString() => motif;
}

class ResultatCaisse {
  const ResultatCaisse({
    required this.facture,
    required this.deja,
    required this.lignesReglees,
    required this.montantRegle,
    required this.restantDu,
    required this.debloquees,
    required this.demandesLiberees,
    required this.ecritures,
    required this.annuler,
    this.normalisation,
    this.versements = const [],
  });
  final Fiche facture;
  final bool deja;
  final List<String> lignesReglees;
  final num montantRegle;
  final num restantDu;

  /// Types de tâches d'aval ouvertes par le règlement (`dispensation`, `prelevement`…).
  final List<String> debloquees;

  /// Références des examens (analyses, imagerie) libérés.
  final List<String> demandesLiberees;
  final List<Fiche> ecritures;

  /// LOT PAIE-V : les fiches de versement posées par cet encaissement (une par versement, liées à leur écriture comptable).
  final List<Fiche> versements;

  /// Restitue TOUT ce que l'encaissement a écrit (facture, tâches, demandes, écritures) — une annulation visible, jamais partielle.
  final VoidCallback annuler;

  /// La normalisation de la vente SOLDÉE (null tant que la pièce n'est pas soldée, ou qu'il n'y a rien à normaliser). Son refus ne défait pas
  /// l'encaissement : l'argent est reçu, la pièce devient `refusee` en le disant.
  final ResultatNormalisation? normalisation;
}

/// `PR.encaisser` côté poste : le cœur arithmétique est celui du domaine (vecteurs de la maquette) ; ici l'ORCHESTRATION — le laboratoire et
/// l'imagerie ne reçoivent que les prestations RÉGLÉES, les tâches d'aval s'ouvrent au solde, le comptable est informé par une ÉCRITURE
/// (brouillon, RG-10) posée à chaque versement.
ResultatCaisse encaisserFacture(
  Magasin m,
  String factureId, {
  List<String>? lignes,
  num? montant,
  String? mode,
  required DateTime maintenant,

  /// La fenêtre « Facture normalisée » : `ifu`, `nom`, `aibTaux`. Contrôlée AVANT toute écriture (E2299).
  Map<String, Object?>? acheteur,

  /// LOT PAIE-V (Direction, 20/11/2026) : des versements successifs de modes différents (type, modalite, operateur, referenceTransaction, montant) au lieu d'un
  /// montant et d'un mode uniques. Contrôlés un par un AVANT toute écriture (refus nommés) ; une écriture équilibrée et une fiche PAR versement.
  List<Map<String, Object?>>? versements,
}) {
  var fac = m.collection('factures').parId(factureId);
  if (fac == null) {
    throw const RefusCaisse('FACTURE_INTROUVABLE', 'Facture introuvable.');
  }
  // LOT TARIF-FIX-2 : une ligne sans prix se VALORISE d'abord (prix en vigueur à la date de la pièce) ; ce qui reste sans prix est refusé par le domaine, nommé.
  if (d.lignesPrixManquant(fac).isNotEmpty) {
    valoriserFacturePoste(m, factureId, maintenant);
    fac = m.collection('factures').parId(factureId)!;
  }
  final aujourdhui = d.iso(maintenant);
  final r = d.encaisser(
    fac,
    lignes: lignes,
    montant: montant,
    mode: mode,
    aujourdhui: aujourdhui,
    maintenant: maintenant.toIso8601String(),
    utilisateur: m.utilisateur,
    ecritures: m.collection('ecritures').actives,
    acheteur: acheteur,
    encaissementPartiel: encaissementPartielPoste(m, maintenant),
    versements: versements,
    modalites: modalitesVersementPoste(m),
    rangDepart: versementsDePiecePoste(m, factureId).length,
    agent: m.utilisateur,
  );
  // E2 (corrigé le 31/10/2026) : un versement au-delà du dû d'une pièce sans lignes est REFUSÉ en nommant le défaut ; rien n'est écrit.
  if (r.refus != null) {
    throw RefusCaisse(r.refusCode ?? 'VERSEMENT_REFUSE', r.refus!);
  }
  if (r.deja) {
    return ResultatCaisse(
        facture: fac,
        deja: true,
        lignesReglees: const [],
        montantRegle: 0,
        restantDu: 0,
        debloquees: const [],
        demandesLiberees: const [],
        ecritures: const [],
        annuler: () {});
  }
  final annulations = <VoidCallback>[];
  final f = r.facture;
  annulations.add(m.collection('factures').mettreAJour(factureId, {
    for (final k in [
      'lignes',
      'montantPaye',
      'reliquat',
      'modePaiement',
      'statutPaiement',
      'statutMecef',
      'baseMecef',
      'dernierReglement'
    ])
      k: f[k],
  }));

  final liberees = <String>[];
  final iso = maintenant.toIso8601String();
  final reglees = [
    for (final l in (f['lignes'] as List).cast<Map>())
      if (r.lignesReglees.contains('${l['id']}')) l.cast<String, Object?>()
  ];

  // Le laboratoire : SEULES les analyses réglées passent.
  final analyses = m.collection('demandesAnalyses');
  for (final l in reglees) {
    if (l['categorie'] != 'analyse' || l['demandeId'] == null) continue;
    final dem = analyses.parId(l['demandeId']);
    if (dem == null) continue;
    annulations.add(analyses.mettreAJour(dem['id'], {
      'bloqueParPaiement': false,
      'statutPaiement': 'soldee',
      'etatAnalyse':
          dem['etatAnalyse'] == 'valide' ? 'valide' : 'attente_prelevement',
      'regleLe': iso,
    }));
    liberees.add('${dem['reference'] ?? dem['id']}');
  }
  // L'imagerie suit la même règle : la séance réglée passe.
  final imagerie = m.collection('demandesImagerie');
  for (final l in reglees) {
    if (l['categorie'] != 'imagerie' || l['demandeImagerieId'] == null) {
      continue;
    }
    final di = imagerie.parId(l['demandeImagerieId']);
    if (di == null) continue;
    annulations.add(imagerie.mettreAJour(di['id'], {
      'bloqueParPaiement': false,
      'statut': di['statut'] == 'demandee' ? 'payee' : di['statut'],
      'regleLe': iso
    }));
    liberees.add('${di['reference'] ?? di['id']}');
  }

  final debloquees = <String>[];
  if (f['statutPaiement'] == 'soldee') {
    final taches = m.collection('taches');
    for (final t in taches.actives.where((t) => t['factureId'] == factureId)) {
      if (t['type'] == 'encaissement') {
        annulations.add(taches.mettreAJour(t['id'],
            {'statut': 'fait', 'faitLe': iso, 'faitPar': m.utilisateur}));
      } else if (t['statut'] == 'bloque') {
        annulations.add(taches.mettreAJour(t['id'], {'statut': 'en_attente'}));
        debloquees.add('${t['type']}');
      }
    }
    // Pièces antérieures au modèle par lignes : ce qui resterait bloqué faute de ligne est libéré au solde.
    for (final dem
        in analyses.actives.where((x) => x['bloqueParPaiement'] == true)) {
      if (dem['factureId'] == factureId ||
          (f['ordonnanceId'] != null &&
              dem['ordonnanceId'] == f['ordonnanceId'])) {
        annulations.add(analyses.mettreAJour(dem['id'], {
          'bloqueParPaiement': false,
          'statutPaiement': 'soldee',
          'etatAnalyse':
              dem['etatAnalyse'] == 'valide' ? 'valide' : 'attente_prelevement',
          'regleLe': iso,
        }));
        liberees.add('${dem['reference'] ?? dem['id']}');
      }
    }
    for (final di in imagerie.actives.where(
        (x) => x['bloqueParPaiement'] == true && x['factureId'] == factureId)) {
      annulations.add(imagerie.mettreAJour(di['id'], {
        'bloqueParPaiement': false,
        'statut': di['statut'] == 'demandee' ? 'payee' : di['statut'],
        'regleLe': iso
      }));
      liberees.add('${di['reference'] ?? di['id']}');
    }
    if (f['ordonnanceId'] != null) {
      annulations.add(m
          .collection('ordonnances')
          .mettreAJour(f['ordonnanceId'], {'statutPaiement': 'soldee'}));
    }
  }

  // Le comptable est informé par une écriture (brouillon), à CHAQUE versement.
  final ecr = <Fiche>[];
  final versementsPoses = <Fiche>[];
  if (versements != null) {
    // LOT PAIE-V : UNE écriture équilibrée PAR versement, puis la fiche du versement, liée à ses écritures (aucun champ nul).
    var rang = 0;
    final groupe = 'LOT-${maintenant.microsecondsSinceEpoch}';
    for (final parVersement in r.ecrituresParVersement) {
      final ids = <String>[];
      for (final e in parVersement) {
        final ins = m.collection('ecritures').inserer(e, prefixe: 'ECR');
        ecr.add(ins.fiche);
        ids.add('${ins.fiche['id']}');
        annulations.add(ins.annuler);
      }
      final fiche = {...r.versements[rang], 'groupe': groupe, 'ecritureIds': ids};
      final ins = m.collection('versementsCaisse').inserer(fiche, prefixe: 'VRS');
      versementsPoses.add(ins.fiche);
      annulations.add(ins.annuler);
      rang++;
    }
  } else {
    for (final e in r.ecritures) {
      final ins = m.collection('ecritures').inserer(e, prefixe: 'ECR');
      ecr.add(ins.fiche);
      annulations.add(ins.annuler);
    }
    // LOT PAIE-V : l'ancien chemin (montant et mode uniques) laisse AUSSI sa fiche de versement.
    final montantRegle = r.montantRegle ?? 0;
    if (montantRegle > 0) {
      final vh = versementHeritagePoste(m, f, montantRegle, '${f['modePaiement']}', maintenant);
      if (vh != null) {
        versementsPoses.add(vh);
        annulations.add(() => m.collection('versementsCaisse').archiver(vh['id']));
      }
    }
  }
  m.journaliser('Encaissement', 'M8', 'facture', '${f['numero']}', {
    'statutPaiement': fac['statutPaiement']
  }, {
    'statutPaiement': f['statutPaiement'],
    'montantPaye': f['montantPaye'],
    'verse': r.montantRegle,
    'lignes': r.lignesReglees.length,
    'restantDu': r.restantDu,
    if (versements != null) 'versements': versementsPoses.length,
  });

  // TOUTE VENTE SOLDÉE EST NORMALISÉE (Direction, 07/11/2026) ; un règlement partiel attend le solde, et une pièce à la charge de l'assureur seul
  // (rien encaissé) n'a rien à normaliser. Le refus de la normalisation ne défait pas l'encaissement.
  ResultatNormalisation? normalisation;
  final apres = m.collection('factures').parId(factureId)!;
  if (apres['statutPaiement'] == 'soldee' &&
      n0(apres['montantPaye']) > 0) {
    normalisation = normaliserVente(m, factureId,
        acheteur: acheteur, maintenant: maintenant);
    annulations.add(normalisation.annuler);
  }

  return ResultatCaisse(
    facture: m.collection('factures').parId(factureId)!,
    normalisation: normalisation,
    deja: false,
    lignesReglees: r.lignesReglees,
    montantRegle: r.montantRegle ?? 0,
    restantDu: r.restantDu ?? 0,
    debloquees: debloquees,
    demandesLiberees: liberees,
    ecritures: ecr,
    versements: versementsPoses,
    annuler: () {
      for (final u in annulations.reversed) {
        u();
      }
    },
  );
}

num n0(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
