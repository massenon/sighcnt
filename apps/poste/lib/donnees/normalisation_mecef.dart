import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'magasin.dart';

/// Ce que la normalisation d'une vente a rendu : un numéro, un refus nommé (code, motif, geste) ou rien à faire.
class ResultatNormalisation {
  const ResultatNormalisation.ok(this.numero, {required this.annuler})
      : code = null,
        motif = null,
        geste = null,
        ignore = false;
  const ResultatNormalisation.refus(this.code, this.motif, this.geste,
      {required this.annuler})
      : numero = null,
        ignore = false;
  const ResultatNormalisation.ignoree()
      : numero = null,
        code = null,
        motif = null,
        geste = null,
        ignore = true,
        annuler = _rien;
  final String? numero;
  final String? code;
  final String? motif;
  final String? geste;
  final bool ignore;

  /// Restitue ce que la normalisation a écrit (la pièce revient en attente).
  final VoidCallback annuler;
  bool get ok => numero != null;
}

void _rien() {}

/// Les numéros déjà portés par une facture ou un avoir : un numéro de pièce ne se reprend jamais.
Set<String> numerosPris(Magasin m) => {
      for (final c in ['factures', 'avoirs'])
        for (final f in m.collection(c).toutes)
          if ('${f['numeroMecef'] ?? ''}'.isNotEmpty) '${f['numeroMecef']}'
    };

/// NORMALISER UNE VENTE (E2299). Le poste n'a AUCUN boîtier branché et n'invente ni protocole ni adresse : la décision (refus nommés, acheteur,
/// montants entiers) est celle du domaine ; l'émission du numéro est celle de l'APPAREIL DE DÉMONSTRATION de la maquette, un numéro séquentiel
/// jamais déjà porté, marqué `mecefSimule` : la pièce l'imprime comme NON FISCAL. Une vente déjà normalisée ne se renormalise jamais ; l'état
/// `en_attente` est écrit AVANT l'émission ; un refus des montants écrit la pièce `refusee` (identifiant stocké `rejete`) en nommant le code.
ResultatNormalisation normaliserVente(
  Magasin m,
  String factureId, {
  Map<String, Object?>? acheteur,
  required DateTime maintenant,
  num tauxTvaCourant = 0,
}) {
  final col = m.collection('factures');
  final fac = col.parId(factureId);
  if (fac == null) {
    return ResultatNormalisation.refus(
        'FACTURE_INTROUVABLE',
        'La facture $factureId n’existe pas.',
        'Rouvrir la caisse et choisir une pièce du registre.',
        annuler: _rien);
  }
  final prep = d.preparerNormalisation(fac,
      acheteurSaisi: acheteur, tauxTvaCourant: tauxTvaCourant);
  if (prep.ignore) return const ResultatNormalisation.ignoree();
  final annulations = <VoidCallback>[];
  void undo() {
    for (final u in annulations.reversed) {
      u();
    }
  }

  if (!prep.ok) {
    final r = prep.refus!;
    // Un refus des MONTANTS écrit la pièce refusée en nommant le code ; les autres refus (pro-forma, règlement absent, déjà normalisée, acheteur)
    // n'écrivent rien.
    const deMontants = {
      'AUCUNE_LIGNE',
      'QUANTITE_INVALIDE',
      'PRIX_DECIMAL',
      'MONTANT_DECIMAL',
      'REMISE_INVALIDE',
      'TOTAL_INCOHERENT',
      'AIB_TAUX_INVALIDE'
    };
    if (deMontants.contains(r.code)) {
      final ach = d.acheteurDePiece(fac, saisi: acheteur).acheteur;
      annulations.add(col.mettreAJour(factureId, {
        'statutMecef': 'rejete',
        'codeRetour': r.code,
        'motifRefusMecef': r.motif,
        if (ach != null) ...{
          'ifuClient': ach.ifu,
          'acheteurNom': ach.nom,
          'aibTaux': ach.aibTaux,
        },
        'mecefSimule': true,
      }));
      m.journaliser('Normalisation refusée', 'MECEF', 'facture',
          '${fac['numero']}', {'statutMecef': fac['statutMecef']}, {'code': r.code});
    }
    return ResultatNormalisation.refus(r.code, r.motif, r.geste, annuler: undo);
  }
  final a = prep.acheteur!;
  final bascule = {
    'ifuClient': a.ifu,
    'acheteurNom': a.nom,
    'aibTaux': a.aibTaux,
    'mecefSimule': true,
  };
  // L'état est écrit AVANT l'émission (un redémarrage reprend au bon endroit).
  annulations.add(col.mettreAJour(factureId,
      {'statutMecef': 'en_attente', 'codeRetour': null, 'motifRefusMecef': null, ...bascule}));
  final porte = '${fac['numeroMecef'] ?? ''}';
  final numero = porte.isNotEmpty
      ? porte // un numéro déjà porté n'est JAMAIS réécrit
      : d.numeroMecefLibre(2000001 + numerosPris(m).length, numerosPris(m));
  annulations.add(col.mettreAJour(factureId, {
    'statutMecef': 'valide',
    'numeroMecef': numero,
    'codeRetour': 'OK-200',
    'dateTransmission': maintenant.toIso8601String(),
    'aibMontant': prep.montants!.aib,
    'normalisePar': m.utilisateur,
  }));
  m.journaliser('Normalisation', 'MECEF', 'facture', '${fac['numero']}',
      {'statutMecef': 'en_attente'}, {'statutMecef': 'valide', 'numero': numero});
  return ResultatNormalisation.ok(numero, annuler: undo);
}
