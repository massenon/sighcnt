import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// LES PARAMÈTRES DE CLINIQUE au poste (lot PARAM-CLINIQUE, décisions 10 et 14 de la Direction du 15/11/2026) : la colle entre le domaine
/// (`parametres_clinique.dart`, rejoué sur les vecteurs tirés de l'écran réel de la maquette) et le registre des paramètres du poste (`parametres`, famille
/// `clinique` : défauts semés, versionnés par date, réglage de BRANCHE posé à la mère, jamais vers un téléphone). Aucune valeur ici : le préavis de péremption
/// et les tranches de la balance âgée se LISENT à la date.

/// RG-05 : le préavis de péremption en vigueur au jour [jour].
int preavisPeremptionPoste(Magasin m, DateTime jour) => pcDelaiPeremption(m.collection(parCollectionParametres).toutes, parametreDateIso(jour));

/// Les deux bornes de la balance âgée en vigueur au jour [jour].
TranchesCreances tranchesCreancesPoste(Magasin m, DateTime jour) => pcTranches(m.collection(parCollectionParametres).toutes, parametreDateIso(jour));

/// Le statut d'un lot au jour [jour], selon le préavis LU à ce jour.
String statutLotPoste(Magasin m, Fiche lot, DateTime jour) => pcStatutLot(lot, parametreDateIso(jour), preavisPeremptionPoste(m, jour));

/// Les lots avec leur statut RECALCULÉ au jour [jour] selon le préavis lu (copies : la fiche n'est pas réécrite). Pour les tableaux de bord, qui lisaient le
/// statut écrit à la saisie (la maquette le recalcule à la date depuis le lot PARAM-CLINIQUE).
List<Fiche> lotsAuJour(Magasin m, Iterable<Fiche> lots, DateTime jour) {
  final preavis = preavisPeremptionPoste(m, jour), d = parametreDateIso(jour);
  return [for (final l in lots) {...l, 'statut': pcStatutLot(l, d, preavis)}];
}

/// Règle un paramètre de clinique : contrôle du domaine (geste réservé, bornes, cohérence des tranches, motif), puis NOUVELLE version datée (jamais une
/// réécriture), journalisée (RG-12). Un FILEUL ne règle pas (réglage posé à la mère, refus nommé). Rend `null` si réglé, sinon le refus nommé.
RefusParametreClinique? reglerParametreClinique(Magasin m,
    {required String cle,
    required Object? valeur,
    required String dateEffet,
    required bool gesteAccorde,
    required String libelleRole,
    required String? motif,
    bool fileul = false,
    DateTime Function()? horloge}) {
  final h = horloge ?? m.horloge;
  if (!gesteAccorde) {
    return RefusParametreClinique('PARAMETRE_CLINIQUE_RESERVE', 'Régler les paramètres de clinique est un droit réservé de la fiche du rôle : « $libelleRole » ne l’a pas.',
        'Demander à un rôle qui détient le droit « Régler les paramètres de clinique » (matrice des droits).');
  }
  if (fileul) {
    return const RefusParametreClinique('FILEUL_LECTURE_SEULE', 'Les paramètres de clinique sont un réglage de la clinique, posé à le poste mère : ce poste le reçoit par le journal.',
        'Régler le paramètre sur le poste mère : ce poste le reçoit par le journal.');
  }
  if ((motif ?? '').trim().length < 3) {
    return const RefusParametreClinique('PARAMETRE_MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour changer un paramètre de clinique.', 'Saisir le motif du changement.');
  }
  if (!Parametres.dateValide(dateEffet)) {
    return const RefusParametreClinique('DATE_EFFET_INVALIDE', 'Date d’effet illisible : attendu AAAA-MM-JJ.', 'Choisir la date d’effet.');
  }
  final versions = m.collection(parCollectionParametres).toutes;
  final autres = <String, Object?>{for (final d in pcDefinitions) if (d.cle != cle) d.cle: pcValeur(versions, d.cle, dateEffet)};
  final refus = pcControler(cle, valeur, autres: autres);
  if (refus != null) return refus;
  final service = serviceParametres(m, auteur: () => m.utilisateur, horloge: h);
  final derniere = service.historique(cle).where((v) => v.dateEffet != null).map((v) => v.dateEffet!).fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
  if (derniere != null && dateEffet.compareTo(derniere) < 0) {
    return RefusParametreClinique('DATE_EFFET_ANTERIEURE', 'La date d’effet ${dateFR(DateTime.parse(dateEffet))} précède celle de la dernière version (${dateFR(DateTime.parse(derniere))}) : une version ne s’insère pas dans le passé.',
        'Choisir une date d’effet égale ou postérieure.');
  }
  final avant = pcValeur(versions, cle, dateEffet);
  final voulu = (valeur is num ? valeur : num.parse('$valeur'.trim())).toInt();
  try {
    final w = service.regler(cle, voulu, dateEffet, motif: (motif ?? '').trim());
    if (!w.ok) return RefusParametreClinique('PARAMETRE_REGLAGE_REFUSE', '${w.refus!.code} : ${w.refus!.motif}', w.refus!.geste);
  } on EcritureRefusee catch (e) {
    return RefusParametreClinique('FILEUL_LECTURE_SEULE', e.motif, 'Régler le paramètre sur le poste mère : ce poste le reçoit par le journal.');
  }
  m.journaliser('Paramètre de clinique : nouvelle version', 'CFG', 'parametresClinique', cle, {'valeur': avant}, {'valeur': voulu, 'dateEffet': dateEffet, 'motif': (motif ?? '').trim()});
  return null;
}
