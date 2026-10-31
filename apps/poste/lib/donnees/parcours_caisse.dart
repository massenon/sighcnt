import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'magasin.dart';

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

  /// Restitue TOUT ce que l'encaissement a écrit (facture, tâches, demandes, écritures) — une annulation visible, jamais partielle.
  final VoidCallback annuler;
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
}) {
  final fac = m.collection('factures').parId(factureId);
  if (fac == null)
    throw const RefusCaisse('FACTURE_INTROUVABLE', 'Facture introuvable.');
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
  );
  // E2 (corrigé le 31/10/2026) : un versement au-delà du dû d'une pièce sans lignes est REFUSÉ en nommant le défaut ; rien n'est écrit.
  if (r.refus != null) throw RefusCaisse('VERSEMENT_REFUSE', r.refus!);
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
    if (l['categorie'] != 'imagerie' || l['demandeImagerieId'] == null)
      continue;
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
    if (f['ordonnanceId'] != null)
      annulations.add(m
          .collection('ordonnances')
          .mettreAJour(f['ordonnanceId'], {'statutPaiement': 'soldee'}));
  }

  // Le comptable est informé par une écriture (brouillon), à CHAQUE versement.
  final ecr = <Fiche>[];
  for (final e in r.ecritures) {
    final ins = m.collection('ecritures').inserer(e, prefixe: 'ECR');
    ecr.add(ins.fiche);
    annulations.add(ins.annuler);
  }
  m.journaliser('Encaissement', 'M8', 'facture', '${f['numero']}', {
    'statutPaiement': fac['statutPaiement']
  }, {
    'statutPaiement': f['statutPaiement'],
    'montantPaye': f['montantPaye'],
    'verse': r.montantRegle,
    'lignes': r.lignesReglees.length,
    'restantDu': r.restantDu
  });

  return ResultatCaisse(
    facture: m.collection('factures').parId(factureId)!,
    deja: false,
    lignesReglees: r.lignesReglees,
    montantRegle: r.montantRegle ?? 0,
    restantDu: r.restantDu ?? 0,
    debloquees: debloquees,
    demandesLiberees: liberees,
    ecritures: ecr,
    annuler: () {
      for (final u in annulations.reversed) {
        u();
      }
    },
  );
}
