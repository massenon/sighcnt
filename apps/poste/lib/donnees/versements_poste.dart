// LOT PAIE-V (Direction, 20/11/2026, section BI) : les versements successifs et les modes multiples, côté poste.
//
// Le cœur des règles est au domaine (`packages/domaine/lib/src/caisse/versements.dart`, vecteurs tirés de l'écran réel de la maquette). Ici : la lecture des modalités
// en base (`modalitesVersement`, versions datées, semées au socle), les gardes de collection (le moteur refuse aussi : masquer un bouton ne protège rien), et le RÉGLAGE
// des modalités par le geste réservé `regler_modalites_versement` (droit de la fiche RBAC, jamais un nom de rôle ; un fileul ne règle pas : réglage de branche posé à la mère).
// Aucun appel à un opérateur de mobile money : la référence de la transaction se saisit à la main.
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'magasin.dart';

/// Les fiches (toutes versions, sans les archives de la collection) des types, modalités et opérateurs.
List<Fiche> modalitesVersementPoste(Magasin m) => m.collection('modalitesVersement').actives;

/// Les versements ACTIFS d'une pièce, dans l'ordre d'enregistrement. Le lien est le NUMÉRO de la pièce (le même sur tous les postes) : l'identifiant local d'une pièce née chez un fileul n'est
/// pas celui de la mère ni d'un autre poste (identité de synchronisation distincte) ; à défaut de numéro, l'identifiant.
List<Fiche> versementsDePiecePoste(Magasin m, Fiche facture) {
  // L'ordre est celui du RANG (puis de l'instant), jamais celui d'arrivée : un versement reçu d'un autre poste prend sa place.
  final l = [
    for (final v in m.collection('versementsCaisse').actives)
      if (_memePiece(v, facture)) v
  ];
  l.sort((a, b) {
    final c = _n(a['rang']).compareTo(_n(b['rang']));
    return c != 0 ? c : '${a['horodatage'] ?? ''}'.compareTo('${b['horodatage'] ?? ''}');
  });
  return l;
}

bool _memePiece(Fiche versement, Fiche facture) {
  final n = '${facture['numero'] ?? ''}', vn = '${versement['factureNumero'] ?? ''}';
  return n.isNotEmpty && vn.isNotEmpty ? n == vn : versement['factureId'] == facture['id'];
}

double _n(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

/// La garde de la collection `versementsCaisse` : un versement enregistré ne se réécrit jamais (la correction passe par un avoir) ; une insertion directe qui
/// dépasserait le dû, sans référence exigée, sur une modalité archivée à sa date ou sur la part d'un assureur est REFUSÉE (même contrôle que la mère au rejeu).
String? gardeVersementPoste(Magasin m, String operation, Fiche apres) {
  if (operation == 'modifier') {
    final avant = m.collection('versementsCaisse').parId(apres['id']);
    if (avant == null) return null;
    for (final k in avant.keys) {
      if (k.startsWith('_') || k == 'statut') continue;
      if ('${avant[k]}' != '${apres[k]}') return 'VERSEMENT_FIGE : un versement enregistré ne se réécrit jamais ; la correction passe par un avoir ou un remboursement.';
    }
    return null;
  }
  if (operation != 'inserer' || apres['origine'] == 'encaissement_direct') return null;
  final fac = m.collection('factures').parId(apres['factureId']);
  if (fac == null) return 'VERSEMENT_PIECE_INTROUVABLE : la pièce du versement n’existe pas.';
  final deja = versementsDePiecePoste(m, fac).fold<double>(0, (n, v) => n + _n(v['montant']));
  final date = '${apres['date'] ?? ''}'.length >= 10 ? '${apres['date']}'.substring(0, 10) : d.iso(m.horloge());
  final r = d.refusUnVersement(fac, apres, date, deja, modalitesVersementPoste(m));
  return r == null ? null : '${r.code} : ${r.motif}';
}

/// La garde de `modalitesVersement` : une version ne se réécrit jamais (on en ajoute une, datée) ; une version en vigueur ne s'archive pas.
String? gardeModaliteVersementPoste(Magasin m, String operation, Fiche apres) {
  if (operation == 'archiver') {
    final avant = m.collection('modalitesVersement').parId(apres['id']) ?? apres;
    final eff = avant['dateEffet'];
    if (eff == null || '$eff'.substring(0, 10).compareTo(d.iso(m.horloge())) <= 0) {
      return 'MODALITE_VERSION_FIGEE : une version en vigueur ne s’archive pas ; poser une version qui archive le code.';
    }
    return null;
  }
  if (operation != 'modifier') return null;
  final avant = m.collection('modalitesVersement').parId(apres['id']);
  if (avant == null) return null;
  for (final k in const ['famille', 'code', 'libelle', 'actif', 'dateEffet', 'compte', 'compteLibelle', 'exigeReference', 'exigeOperateur']) {
    if ('${avant[k]}' != '${apres[k]}') return 'MODALITE_VERSION_FIGEE : une version d’une modalité de versement ne se réécrit pas. Ajouter une nouvelle version datée.';
  }
  return null;
}

/// Le refus nommé d'un réglage de modalité.
class RefusReglageVersement implements Exception {
  const RefusReglageVersement(this.code, this.motif, [this.geste]);
  final String code, motif;
  final String? geste;
  @override
  String toString() => '$code : $motif';
}

/// RÉGLER : une NOUVELLE VERSION datée d'un type, d'une modalité ou d'un opérateur (jamais une réécriture). [peutRegler] : le droit de la fiche RBAC du rôle de la
/// session (`regler_modalites_versement`) ; [fileul] : un fileul ne règle pas. Lève le refus nommé ; rend la fiche posée.
Fiche reglerModaliteVersementPoste(
  Magasin m, {
  required bool peutRegler,
  bool fileul = false,
  required String famille,
  required String code,
  required String libelle,
  String? compte,
  String? compteLibelle,
  bool exigeReference = false,
  bool exigeOperateur = false,
  bool actif = true,
  String? dateEffet,
  required String motif,
}) {
  if (!peutRegler) {
    throw const RefusReglageVersement('VERSEMENT_REGLAGE_RESERVE', 'Régler les modalités de versement est un droit réservé de la fiche du rôle.',
        'Demander à un rôle qui détient le droit « Régler les modalités de versement de la caisse » (matrice des droits).');
  }
  if (fileul) {
    throw const RefusReglageVersement('FILEUL_LECTURE_SEULE', 'Cette configuration est tenue par la mère ; modifiez-la sur le poste mère.',
        'Ouvrir le même écran sur le poste mère : la modification arrivera ici par la synchronisation.');
  }
  if (!d.famillesVersement.contains(famille)) {
    throw RefusReglageVersement('VERSEMENT_FAMILLE_INCONNUE', 'La famille « $famille » n’existe pas (type, modalité ou opérateur).', 'Choisir type, modalité ou opérateur.');
  }
  if (!RegExp(r'^[a-z][a-z0-9_]{1,31}$').hasMatch(code)) {
    throw RefusReglageVersement('VERSEMENT_CODE_INVALIDE', 'Le code « $code » est invalide : minuscules, chiffres et tiret bas, de 2 à 32 caractères, commençant par une lettre.',
        'Saisir un code court, par exemple « celtiis ».');
  }
  if (libelle.trim().isEmpty) throw const RefusReglageVersement('VERSEMENT_LIBELLE_ABSENT', 'Le libellé est obligatoire.', 'Saisir le libellé affiché au guichet.');
  if (famille == 'modalite' && !RegExp(r'^\d{6}$').hasMatch(compte ?? '')) {
    throw RefusReglageVersement('VERSEMENT_COMPTE_INVALIDE', 'Une modalité porte le compte comptable de son encaissement : six chiffres (reçu « ${compte ?? ''} »).',
        'Saisir le compte, par exemple 571000 (caisse) ou 521000.');
  }
  if (motif.trim().length < 3) throw const RefusReglageVersement('VERSEMENT_MOTIF_ABSENT', 'Un motif est obligatoire pour régler une modalité de versement.', 'Saisir le motif du changement.');
  final jour = dateEffet ?? d.iso(m.horloge());
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(jour)) throw const RefusReglageVersement('DATE_EFFET_INVALIDE', 'Date d’effet illisible : attendu AAAA-MM-JJ.', 'Choisir la date d’effet.');
  // Un poste installé AVANT le lot n'a pas la collection : le domaine lit alors la semence. Poser une première version sans la semence la ferait DISPARAÎTRE (la liste cesserait d'être vide) :
  // la semence est donc posée d'abord, par les gestes du magasin (journalisée, elle voyage à la mère).
  if (m.collection('modalitesVersement').actives.isEmpty) {
    for (final f in d.semenceModalitesVersement()) {
      m.collection('modalitesVersement').inserer({...f}, prefixe: 'MVS');
    }
  }
  final fiches = modalitesVersementPoste(m);
  final versions = d.versionsModalitesVersement(fiches, famille).where((r) => r['code'] == code && r['dateEffet'] != null).toList();
  if (versions.isNotEmpty && jour.compareTo('${versions.last['dateEffet']}'.substring(0, 10)) < 0) {
    throw const RefusReglageVersement('DATE_EFFET_ANTERIEURE', 'La date d’effet précède celle de la dernière version : une version ne s’insère pas dans le passé.', 'Choisir une date d’effet égale ou postérieure.');
  }
  if (!actif && famille == 'modalite' && d.modalitesVersementActives(fiches, 'modalite', jour).where((r) => r['code'] != code).isEmpty) {
    throw const RefusReglageVersement('VERSEMENT_DERNIERE_MODALITE', 'La dernière modalité proposée ne s’archive pas : la caisse ne pourrait plus enregistrer de versement.',
        'Ajouter ou réactiver une autre modalité d’abord.');
  }
  final avant = d.modaliteVersementALaDate(fiches, famille, code, jour);
  final fiche = <String, Object?>{
    'statut': 'actif',
    'famille': famille,
    'code': code,
    'libelle': libelle.trim(),
    'actif': actif,
    'dateEffet': jour,
    'motif': motif.trim(),
    'creeLe': m.horloge().toIso8601String(),
    'creePar': m.utilisateur,
    if (famille == 'modalite') ...{
      'compte': compte,
      'compteLibelle': (compteLibelle ?? '').trim().isEmpty ? libelle.trim() : compteLibelle!.trim(),
      'exigeReference': exigeReference,
      'exigeOperateur': exigeOperateur,
    },
  };
  final ins = m.collection('modalitesVersement').inserer(fiche, prefixe: 'MVS');
  m.journaliser(actif ? 'Modalité de versement : nouvelle version' : 'Modalité de versement : archivée', 'M8', 'modalitesVersement', '${ins.fiche['id']}',
      avant == null ? null : {'code': avant['code'], 'libelle': avant['libelle'], 'actif': avant['actif'] != false}, {'famille': famille, 'code': code, 'libelle': libelle.trim(), 'actif': actif, 'dateEffet': jour, 'motif': motif.trim()});
  return ins.fiche;
}

/// Un encaissement fait par montant et mode uniques (ancien chemin) laisse UNE fiche de versement, sans exigence de référence (origine `encaissement_direct`) : la caisse du
/// jour par modalité reste complète. [facture] : la pièce APRÈS l'encaissement (son réglé comprend déjà [montant]). Rend la fiche posée, ou null (mode qui n'est pas un versement).
Fiche? versementHeritagePoste(Magasin m, Fiche facture, num montant, String mode, DateTime maintenant) {
  final cible = d.modaliteDepuisMode(mode);
  if (cible == null || montant <= 0) return null;
  final fiches = modalitesVersementPoste(m);
  final jour = d.iso(maintenant);
  final mod = d.modaliteVersementALaDate(fiches, 'modalite', cible['modalite'], jour);
  if (mod == null) return null;
  final avant = d.resteDuPiece(facture, montantPaye: _n(facture['montantPaye']) - montant);
  final typ = d.modaliteVersementALaDate(fiches, 'type', montant >= avant ? 'solde' : 'acompte', jour) ?? d.modaliteVersementALaDate(fiches, 'type', 'acompte', jour);
  final op = cible['operateur'] == null ? null : d.modaliteVersementALaDate(fiches, 'operateur', cible['operateur'], jour);
  final fiche = <String, Object?>{
    'type': typ?['code'] ?? 'acompte',
    'typeLibelle': typ?['libelle'] ?? 'Acompte',
    'modalite': cible['modalite'],
    'modaliteLibelle': mod['libelle'],
    'compte': mod['compte'],
    'compteLibelle': mod['compteLibelle'] ?? mod['libelle'],
    'montant': montant,
    if (op != null) 'operateur': op['code'],
    if (op != null) 'operateurLibelle': op['libelle'],
    'factureId': facture['id'],
    'factureNumero': facture['numero'],
    'patientId': facture['patientId'],
    'patient': facture['patient'],
    if ('${facture['patientCode'] ?? ''}'.isNotEmpty) 'patientCode': facture['patientCode'],
    'rang': versementsDePiecePoste(m, facture).length + 1,
    'date': jour,
    'horodatage': maintenant.toIso8601String(),
    'agent': m.utilisateur,
    'origine': 'encaissement_direct',
    'resteApres': d.resteDuPiece(facture),
    'ecritureIds': const <String>[],
  };
  return m.collection('versementsCaisse').inserer(fiche, prefixe: 'VRS').fiche;
}
