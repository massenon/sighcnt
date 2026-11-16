// LOT CONT (14/11/2026, exigence de la Direction) : UNE VALIDATION EN ATTENTE N'ARRÊTE JAMAIS UN FILEUL, ET LA DÉCISION HUMAINE NE SE PREND PAS SUR LE POSTE DE LA MÈRE.
//
// Avant ce lot, un fileul rattaché refusait de valider un référentiel (« Réglé sur la mère, valider depuis le poste principal », code `CONFIGURATION_DE_LA_MERE`) : les quinze
// familles du registre voyagent de la mère, donc le biologiste, la Directrice Administrative ou le chirurgien devaient aller sur le poste où personne ne travaille.
// Désormais la décision (Valider) se prend sur n'importe quel poste par le profil de la famille, est SIGNÉE (qui, quand, motif), et part comme une DEMANDE de famille A
// (`demandesValidation`, un fichier de fiches que le fileul dépose et que la mère complète du verdict, comme `propositionsTarif` et `demandesImport`). La mère n'est que
// l'applicateur MÉCANIQUE : elle refait les mêmes contrôles sous le rôle et le nom de l'auteur (un bouton absent ne protège rien), applique, et écrit le verdict sur la même
// fiche. Mère coupée : la demande reste « déposée » au journal du fileul, rejouée à la reconnexion ; un rejeu ne double jamais (seule une demande « déposée » est traitée).
//
// Règles tenues ici, jamais recopiées ailleurs :
//  - aucune liste de rôles propre à ce lot : le profil qui décide est celui de la FAMILLE du registre (`valFamilles`), la même source que le geste direct ;
//  - jamais d'auto-validation : rien ici ne valide une pièce dont personne n'a décidé ; passé le délai RÉGLABLE EN BASE ([valCleDelaiAlerteHeures], défaut semé), on ne fait
//    qu'ALERTER (jamais bloquer) ;
//  - la date de la validation est celle de la SIGNATURE (le moment où le profil a décidé), pas celle où la mère a appliqué.

import 'validation.dart';

/// La collection des demandes de validation d'un fileul (famille A de la synchronisation : le fileul dépose, la mère complète du verdict ; jamais vers un téléphone).
const String valCollectionDemandes = 'demandesValidation';

/// Le délai, en HEURES, au-delà duquel une décision toujours « en attente de la mère » déclenche une alerte (jamais un blocage). Réglage de clinique lu de la base ;
/// défaut semé 4 (Direction, 16/11/2026, lot CLO-3 ; c'était 24, proposition de la section AG).
const String valCleDelaiAlerteHeures = 'securite.delaiAlerteDecisionEnAttenteHeures';

/// Le défaut SEMÉ de [valCleDelaiAlerteHeures] (la valeur lue en vigueur vient de la base). 4 heures : Direction, 16/11/2026 (lot CLO-3, section AR), qui REMPLACE la proposition de 24 heures.
const int valDelaiAlerteDefautHeures = 4;

const String valEtatDeposee = 'deposee', valEtatAppliquee = 'appliquee', valEtatRefusee = 'refusee';

/// Ce que le dépôt rend : un refus nommé, ou la fiche à INSÉRER dans [valCollectionDemandes].
class VerdictDepotValidation {
  const VerdictDepotValidation.refus(this.refus) : fiche = null;
  const VerdictDepotValidation.ok(this.fiche) : refus = null;
  final RefusValidation? refus;
  final Map<String, Object?>? fiche;
  bool get ok => refus == null;
}

/// Les demandes qui attendent encore la mère (état « déposée », archivées exclues), de la plus ancienne à la plus récente.
List<Map<String, Object?>> valDemandesEnAttente(List<Map<String, Object?>> demandes) {
  final out = [
    for (final d in demandes)
      if (d['statut'] != 'archive' && d['etat'] == valEtatDeposee) d
  ]..sort((a, b) => '${a['demandeLe']}${a['id']}'.compareTo('${b['demandeLe']}${b['id']}'));
  return out;
}

/// La demande en attente d'une cible, ou `null` (une seule demande « déposée » par cible).
Map<String, Object?>? valDemandeEnAttenteDe(List<Map<String, Object?>> demandes, String famille, String cible) {
  for (final d in valDemandesEnAttente(demandes)) {
    if (d['famille'] == famille && '${d['cible']}' == cible) return d;
  }
  return null;
}

/// Depuis combien de temps la demande attend la mère (`null` si la date de signature est illisible : jamais un âge inventé).
Duration? valAgeDemande(Map<String, Object?> demande, DateTime maintenant) {
  final t = DateTime.tryParse('${demande['demandeLe']}');
  return t == null ? null : maintenant.toUtc().difference(t.toUtc());
}

/// Le dépôt d'une décision de validation par un FILEUL. Les contrôles sont ceux du geste direct (`valValiderReferentiel`, refus nommés `INTROUVABLE`, `VALIDATION_RESERVEE`,
/// `DEJA_VALIDE`, `TARIF_ABSENT`), rejoués ici sans la garde « réglé sur la mère » : décider n'est pas modifier la configuration. Une seconde décision sur une cible qui en a déjà
/// une en attente est refusée en nommant (`DEMANDE_DEJA_DEPOSEE`) : le travail courant n'est pas bloqué, la décision attend la mère.
/// [etiquette] distingue deux postes qui déposent à la même microseconde. Ne modifie rien : rend la fiche à écrire.
VerdictDepotValidation valDeposerValidation(
  String famille,
  String id, {
  required String role,
  required String acteur,
  required DateTime maintenant,
  required LectureValidation lire,
  required Map<String, String> libelles,
  String etiquette = 'F',
  String? motif,
}) {
  final controle = valValiderReferentiel(famille, id, role: role, acteur: acteur, maintenant: maintenant, lire: lire, libelles: libelles, fileul: false, motif: motif);
  if (!controle.ok) return VerdictDepotValidation.refus(controle.refus!);
  final existante = valDemandeEnAttenteDe(lire(valCollectionDemandes), famille, id);
  if (existante != null) {
    final age = valAgeDemande(existante, maintenant);
    return VerdictDepotValidation.refus(RefusValidation(
        'DEMANDE_DEJA_DEPOSEE',
        'La décision sur « $id » est déjà déposée par ${existante['demandePar']}'
            '${age == null ? '' : ' (en attente de la mère depuis ${valDureeLisible(age)})'}.',
        'Rien à faire : la mère l\'applique dès qu\'elle est joignable. Le travail courant n\'est pas bloqué.'));
  }
  final quand = valInstant(maintenant);
  final lib = valFamille(famille)!.libelle;
  return VerdictDepotValidation.ok({
    'id': 'DV$etiquette${maintenant.microsecondsSinceEpoch}${lire(valCollectionDemandes).length}',
    'statut': 'actif',
    'famille': famille,
    'cible': id,
    'libelle': lib,
    'etat': valEtatDeposee,
    'demandePar': acteur,
    'demandeRole': role,
    'demandeLe': quand,
    if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim(),
  });
}

/// Ce que la mère rend après avoir rejoué une demande : le verdict de validation à ÉCRIRE (refus nommé ou marquage) et les champs du verdict à poser sur la demande.
class ApplicationDemandeValidation {
  const ApplicationDemandeValidation({required this.verdict, required this.champsDemande});
  final VerdictValidation verdict;

  /// À fusionner dans la fiche de la demande : `etat`, `traiteLe`, et, en cas de refus, `resultatCode`, `resultatMotif`, `resultatGeste`.
  final Map<String, Object?> champsDemande;
}

/// Le contrôle du compte signataire d'une décision déposée par un fileul (lot CLO-3 point 6) : le compte nommé par la demande ([demandePar], par `nom` ou `nomComplet`) EXISTE à la mère,
/// porte le rôle SIGNÉ ([demandeRole]) et n'a été ni créé après la signature ni archivé avant elle. Refus nommés : `SIGNATAIRE_INCONNU`, `SIGNATAIRE_AUTRE_ROLE`,
/// `SIGNATAIRE_CREE_APRES_SIGNATURE`, `SIGNATAIRE_ARCHIVE`. `null` : le compte est recevable. LIMITE DITE : le compte ne garde pas l'historique de ses changements de rôle ; c'est le
/// rôle porté par le compte à la mère au moment de l'application qui est comparé (un changement de rôle entre la signature et l'application n'est pas détecté).
RefusValidation? valControleSignataire(Map<String, Object?> demande, Iterable<Map<String, Object?>> comptes, DateTime signeLe) {
  final nom = '${demande['demandePar']}', role = '${demande['demandeRole']}';
  final memes = [
    for (final c in comptes)
      if ('${c['nom']}' == nom || '${c['nomComplet'] ?? ''}' == nom) c
  ];
  if (memes.isEmpty) {
    return RefusValidation('SIGNATAIRE_INCONNU', 'La décision est signée par « $nom » : aucun compte de ce nom n\u2019existe à la mère.', 'Faire créer le compte à la mère, puis redéposer la décision.');
  }
  final avecRole = [for (final c in memes) if ('${c['role']}' == role) c];
  if (avecRole.isEmpty) {
    return RefusValidation('SIGNATAIRE_AUTRE_ROLE', 'Le compte de « $nom » ne porte pas le rôle « $role » signé sur la décision.', 'Redéposer la décision sous le rôle que le compte porte réellement.');
  }
  DateTime? lu(Object? v) => v == null ? null : DateTime.tryParse('$v');
  final recevables = [
    for (final c in avecRole)
      if (!((lu(c['_creeLe']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)).toUtc().isAfter(signeLe.toUtc())) &&
          !(c['statut'] == 'archive' && (lu(c['_archiveLe'])?.toUtc().isBefore(signeLe.toUtc()) ?? false)))
        c
  ];
  if (recevables.isEmpty) {
    final cree = avecRole.any((c) => (lu(c['_creeLe'])?.toUtc().isAfter(signeLe.toUtc()) ?? false));
    return cree
        ? RefusValidation('SIGNATAIRE_CREE_APRES_SIGNATURE', 'Le compte de « $nom » a été créé après la signature de la décision : elle ne peut pas lui être attribuée.', 'Redéposer la décision depuis le compte.')
        : RefusValidation('SIGNATAIRE_ARCHIVE', 'Le compte de « $nom » était archivé à la date de la signature.', 'Faire rétablir le compte, puis redéposer la décision.');
  }
  return null;
}

/// La MÈRE applique une demande « déposée » : mêmes contrôles que le geste direct, sous le rôle et le nom de l'AUTEUR, à la date de sa SIGNATURE. `null` si la demande n'est pas
/// « déposée » (idempotence : un rejeu, une demande déjà appliquée ou refusée, ne se retraite jamais). Ne modifie rien.
ApplicationDemandeValidation? valAppliquerDemande(
  Map<String, Object?> demande, {
  required DateTime maintenant,
  required LectureValidation lire,
  required Map<String, String> libelles,
  Iterable<Map<String, Object?>>? comptes,
}) {
  if (demande['etat'] != valEtatDeposee) return null;
  final signeLe = DateTime.tryParse('${demande['demandeLe']}') ?? maintenant;
  // Lot CLO-3 point 6 : la mère ne fait pas confiance à un nom et un rôle écrits sur la demande : le COMPTE signataire doit exister, porter ce rôle, et n'avoir été ni créé après la
  // signature ni archivé avant. [comptes] null : aucun registre de comptes connu (outil, banc du protocole), le contrôle n'est pas tenu ; fourni (même vide) : il est tenu.
  final refusSignataire = comptes == null ? null : valControleSignataire(demande, comptes, signeLe);
  if (refusSignataire != null) {
    return ApplicationDemandeValidation(verdict: VerdictValidation.refus(refusSignataire), champsDemande: {
      'etat': valEtatRefusee,
      'traiteLe': valInstant(maintenant),
      'resultatCode': refusSignataire.code,
      'resultatMotif': refusSignataire.motif,
      'resultatGeste': refusSignataire.geste,
    });
  }
  final v = valValiderReferentiel('${demande['famille']}', '${demande['cible']}',
      role: '${demande['demandeRole']}',
      acteur: '${demande['demandePar']}',
      maintenant: signeLe,
      lire: lire,
      libelles: libelles,
      fileul: false,
      motif: demande['motif'] as String?);
  return ApplicationDemandeValidation(
      verdict: v,
      champsDemande: {
        'etat': v.ok ? valEtatAppliquee : valEtatRefusee,
        'traiteLe': valInstant(maintenant),
        if (!v.ok) ...{'resultatCode': v.refus!.code, 'resultatMotif': v.refus!.motif, 'resultatGeste': v.refus!.geste},
      });
}

/// Le compte lu des décisions en attente de la mère : le nombre et l'âge de la plus ancienne (`null` quand il n'y en a aucune). Jamais un zéro quand il y en a.
class SyntheseDecisionsEnAttente {
  const SyntheseDecisionsEnAttente({required this.nombre, required this.plusAncienne});
  final int nombre;
  final Duration? plusAncienne;

  /// « 2 décisions en attente de la mère, la plus ancienne depuis 3 h 10 min », ou le texte court s'il n'y en a qu'une.
  String get libelle {
    if (nombre == 0) return '';
    final age = plusAncienne == null ? '' : ' · la plus ancienne depuis ${valDureeLisible(plusAncienne!)}';
    return nombre == 1 ? '1 décision en attente de la mère$age' : '$nombre décisions en attente de la mère$age';
  }
}

SyntheseDecisionsEnAttente valSyntheseEnAttente(List<Map<String, Object?>> demandes, DateTime maintenant) {
  final en = valDemandesEnAttente(demandes);
  Duration? max;
  for (final d in en) {
    final a = valAgeDemande(d, maintenant);
    if (a != null && (max == null || a > max)) max = a;
  }
  return SyntheseDecisionsEnAttente(nombre: en.length, plusAncienne: max);
}

/// TOUTES les décisions et demandes de ce poste qui attendent la mère, pour la pastille de la barre : les décisions de validation (`demandesValidation`, « déposée »), les demandes de prix
/// (`propositionsTarif`, « déposée ») et les demandes d'import (`demandesImport`, « en_attente »). Les noms de collection et d'état sont ceux des moteurs qui les écrivent. L'âge ne se calcule
/// que sur une date AVEC heure (une demande datée du seul jour compte, mais ne donne pas d'âge : jamais un âge inventé).
SyntheseDecisionsEnAttente valSyntheseToutesAttentes(Map<String, List<Map<String, Object?>>> collections, DateTime maintenant) {
  const etats = {valCollectionDemandes: valEtatDeposee, 'propositionsTarif': 'deposee', 'demandesImport': 'en_attente'};
  var n = 0;
  Duration? max;
  etats.forEach((nom, etat) {
    for (final d in collections[nom] ?? const <Map<String, Object?>>[]) {
      if (d['statut'] == 'archive' || d['etat'] != etat) continue;
      n++;
      if (!'${d['demandeLe']}'.contains('T')) continue;
      final a = valAgeDemande(d, maintenant);
      if (a != null && (max == null || a > max!)) max = a;
    }
  });
  return SyntheseDecisionsEnAttente(nombre: n, plusAncienne: max);
}

/// Les demandes dont l'attente dépasse le délai d'alerte (en HEURES, lu de la base). Un délai absent ou nul n'alerte pas (jamais un délai inventé). Aucune de ces demandes
/// n'est validée, ni bloquée, ni refusée pour autant : l'alerte est un avertissement.
List<Map<String, Object?>> valDemandesEnRetard(List<Map<String, Object?>> demandes, DateTime maintenant, int? delaiHeures) {
  if (delaiHeures == null || delaiHeures < 1) return const [];
  return [
    for (final d in valDemandesEnAttente(demandes))
      if ((valAgeDemande(d, maintenant) ?? Duration.zero) >= Duration(hours: delaiHeures)) d
  ];
}

/// Une durée en français court : « 12 min », « 3 h 10 min », « 2 jours 4 h ».
String valDureeLisible(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} jour${d.inDays > 1 ? 's' : ''} ${d.inHours % 24} h';
  if (d.inMinutes >= 60) return '${d.inHours} h ${d.inMinutes % 60} min';
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds < 0 ? 0 : d.inSeconds} s';
}
