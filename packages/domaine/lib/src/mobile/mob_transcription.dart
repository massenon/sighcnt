/// TRANSCRIPTION AU POSTE D'UNE PRESCRIPTION DU MOBILE (E1559, E1561) : port de `PR.transcrireMobile` de la maquette, rejoué sur les vecteurs ENGENDRÉS
/// EN PILOTANT la maquette (`test/vecteurs/transcription_mobile.json`, `prototype_html/build/vecteurs-transcription-mobile.js`).
///
/// Une pièce `prescriptions` émise par le téléphone d'un soignant (famille C, immuable) ne devient une ordonnance, une facture de caisse et des files
/// d'aval que lorsqu'un POSTE la transcrit. La transcription passe par [csPrescrire] (le moteur de la fiche de consultation du poste, `PR.prescrire`) :
/// rien n'est recalculé à côté. Ce que ce fichier ajoute, ce sont les REFUS nommés, parce qu'une pièce reçue du terrain n'a pas été saisie devant le
/// catalogue de la clinique :
///  - le prix ne vient jamais du téléphone : prix d'achat du catalogue, sans marge (RG-02) ;
///  - la quantité ne dépasse pas le stock de la pharmacie (RG-03) : refus nommé, jamais un stock négatif ;
///  - la carte d'assurance se lit À LA DATE de la prescription (RG-09) ;
///  - une pièce n'est transcrite qu'UNE fois (`pieceMobileId` sur l'ordonnance) ;
///  - une pièce non transcriptible est REFUSÉE EN LE DISANT, jamais perdue ni transcrite à moitié.
library;

import '../consultation/cs_moteur.dart';
import '../consultation/cs_referentiels.dart' show FicheCs;
import 'mob_regles.dart';
import 'mob_transcription_donnees.dart';

export 'mob_transcription_donnees.dart' show mobCorrespondanceExamens;

/// Ce que la transcription a écrit (ou, pour une pièce déjà transcrite, ce qu'elle avait écrit : [deja] vaut alors `true` et rien n'est réécrit).
class TranscriptionMobile {
  const TranscriptionMobile(this.deja, this.ordonnance, this.facture, this.taches, this.demandes);
  final bool deja;
  final FicheCs ordonnance;
  final FicheCs? facture;
  final List<FicheCs> taches, demandes;
}

RefusMobile _refus(String code, String motif, String geste) => RefusMobile(code, motif, geste);

String _n(num v) => v == v.truncate() ? '${v.truncate()}' : '$v';

num _quantite(Object? v) {
  if (v is num) return v;
  return num.tryParse('${v ?? ''}'.replaceFirst(',', '.')) ?? double.nan;
}

/// `PR.transcrireMobile(piece, { note })` : transcrit une pièce `prescriptions` (médicaments ou analyses) en ordonnance, facture et tâches d'aval.
/// [note] : la note de consultation de la pièce (son diagnostic part sur l'ordonnance), ou `null`. Lève un [RefusMobile] nommé SANS rien écrire.
TranscriptionMobile mobTranscrire(StockCs s, MobFiche piece, {MobFiche? note}) {
  final pieceId = piece['id'] ?? piece['pieceId'];
  // Idempotence : une pièce n'est transcrite qu'une fois.
  if (pieceId != null) {
    for (final o in s.actives('ordonnances')) {
      if (o['pieceMobileId'] != null && o['pieceMobileId'] == pieceId) {
        return TranscriptionMobile(true, o, s.parId('factures', o['factureId']), const [], const []);
      }
    }
  }

  final nature = '${piece['nature'] ?? ''}';
  if (nature != 'medicament' && nature != 'analyse') {
    throw _refus('NATURE_NON_PORTEE', 'Le mobile ne prescrit pas « $nature ».', 'Prescrire depuis un poste de la clinique');
  }
  final fonction = '${piece['fonction'] ?? ''}';
  if (!mobPeutPrescrire(fonction, nature)) {
    throw _refus('FONCTION_NON_HABILITEE', mobMotifFonctionNonHabilitee(fonction, nature), 'Demander la prescription à un médecin');
  }
  final p = csPatientParCode(s, piece['patientCode']);
  if (p == null) {
    throw _refus('PATIENT_INTROUVABLE', 'Le dossier « ${piece['patientCode'] ?? 'sans code'} » n’existe pas à la clinique : la prescription ne peut pas être facturée.',
        'Rapprocher le dossier du patient avant de transcrire');
  }

  final medicaments = <Map<String, Object?>>[];
  final analyses = <String>[];
  if (nature == 'medicament') {
    final lignes = [for (final l in (piece['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
    if (lignes.isEmpty) throw _refus('ORDONNANCE_VIDE', 'L’ordonnance ne porte aucune ligne.', 'Refaire la prescription depuis le téléphone');
    final demande = <Object?, num>{};
    for (final l in lignes) {
      final prod = l['produitId'] == null || '${l['produitId']}'.isEmpty ? null : s.actives('produits').where((x) => x['id'] == l['produitId']).firstOrNull;
      if (prod == null) {
        throw _refus('PRODUIT_INCONNU', 'Médicament absent du catalogue de la clinique : « ${l['medicament'] ?? 'sans nom'} ».',
            'Choisir le médicament dans la liste du lot et refaire la prescription');
      }
      final q = _quantite(l['quantite']);
      if (!(q >= 1) || q != q.floor()) {
        throw _refus('QUANTITE_INVALIDE', 'Quantité invalide pour « ${prod['designation']} » : un entier d’au moins 1 est attendu.', 'Refaire la prescription depuis le téléphone');
      }
      demande[prod['id']] = (demande[prod['id']] ?? 0) + q;
      final dispo = (prod['stockDetail'] ?? prod['stock']) as num? ?? 0;
      if (demande[prod['id']]! > dispo) {
        throw _refus('STOCK_INSUFFISANT', 'Stock insuffisant pour « ${prod['designation']} » : disponible : ${_n(dispo)} ; demandé : ${_n(demande[prod['id']]!)} (RG-03).',
            'Corriger la quantité ou demander un transfert du gros.');
      }
      final jours = l['dureeJours'];
      medicaments.add({
        'produitId': prod['id'],
        'quantite': q,
        'posologie': '${l['posologie'] ?? ''}',
        'duree': jours == null ? '' : '${jours is num ? _n(jours) : jours}${(jours is num ? jours : (num.tryParse('$jours') ?? 0)) > 1 ? ' jours' : ' jour'}',
      });
    }
  } else {
    final examens = [for (final e in (piece['examens'] as List? ?? const [])) '$e'];
    if (examens.isEmpty) throw _refus('ORDONNANCE_VIDE', 'La demande ne porte aucun examen.', 'Refaire la demande depuis le téléphone');
    for (final nom in examens) {
      final code = mobCorrespondanceExamens[nom];
      if (code == null || !s.referentiel('analyses').any((a) => a['code'] == code)) {
        throw _refus('EXAMEN_INCONNU', 'Examen sans correspondance au catalogue du laboratoire : $nom.', 'Demander l’examen depuis un poste de la clinique');
      }
      analyses.add(code);
    }
  }

  final brute = '${piece['date'] ?? ''}';
  final date = (brute.indexOf('T') > 0 ? DateTime.tryParse(brute) : null) ?? s.maintenant;
  final res = csPrescrire(
      s,
      {
        'patientCode': p['code'],
        'medecin': piece['prescripteur'] ?? '',
        'diagnostic': note?['diagnostic'] ?? '',
        'date': date.toUtc().toIso8601String(),
        'urgent': nature == 'analyse' && '${piece['urgence'] ?? 'Non urgent'}' != 'Non urgent',
        'medicaments': medicaments,
        'analyses': analyses,
        'actes': <Object?>[],
        'origine': 'mobile',
        'secteurDemandeur': mobSecteurFonction(fonction) ?? 'Consultation',
      },
      const SessionCs());
  s.mettreAJour('ordonnances', res.ordonnance['id'], {'origine': 'mobile', 'pieceMobileId': pieceId, 'fonctionPrescripteur': fonction});
  return TranscriptionMobile(false, s.parId('ordonnances', res.ordonnance['id'])!, res.facture, res.taches, res.demandes);
}
