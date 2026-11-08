// LE MOTEUR DE VALIDATION COMMUN DES RÉFÉRENTIELS (Direction, 07/11/2026) : règles portées de `SIGH.validations` (parcours.js, vague 91).
//
// Tout ce qui porte un marquage « à valider » (modèle d'enquête, borne du laboratoire, pathologie, catalogue d'imagerie, check-liste du bloc, tarif
// d'attente, valorisation, objectif de pilotage, répartition des charges, modèle de badge, jeu d'import, modèle de message, barème de l'ITS) se valide
// par UN geste, le même partout : [validerReferentiel]. Doctrine : un refus se NOMME (code, motif, geste) ; le rôle vient de la SESSION, jamais de
// l'écran ; le geste est UNITAIRE (aucune validation en masse) ; une validation ne modifie AUCUN autre champ que le marquage et ses trois traces
// (`valideLe`, `validePar`, `valideRole`) ; modifier un élément validé le remet « à valider » ([remettreAValider]).
//
// Fonctions PURES : elles lisent les collections par [LectureValidation] et RENDENT ce qu'il faut écrire (patch, fiche à créer, ligne de journal). C'est
// l'appelant (le magasin du poste) qui écrit, journalise (RG-12) et notifie. Le compte est LU, jamais écrit : `referentielsAValider` relit les marquages
// à chaque appel.
//
// Deux formes d'artefact : (1) une FICHE du magasin qui porte son marquage (`aValider`, `tarifProvisoire`) ; (2) une CONSTANTE du code (check-listes du
// bloc, répartition fixe/variable, barème de l'ITS, jeu d'import) qui ne peut pas porter de marquage : sa validation vit dans une fiche de la collection
// `validationsReferentiels`, une par cible (`VRF-<cible>`).

/// Lit TOUTES les fiches d'une collection (archivées comprises) : le moteur ignore lui-même les archivées.
typedef LectureValidation = List<Map<String, Object?>> Function(String collection);

/// La collection qui porte les validations des artefacts du code (une fiche par cible).
const String valCollectionValidations = 'validationsReferentiels';

/// Les profils qui voient TOUTES les familles au centre des validations ; les autres voient leur ressort.
const List<String> valVueComplete = ['direction', 'da', 'admin'];

/// Une cible d'une famille de forme « fiche » : un artefact du code qui ne peut pas porter son propre marquage.
class CibleValidation {
  const CibleValidation(this.id, this.libelle);
  final String id;
  final String libelle;
}

/// Une famille du registre des validations.
class FamilleValidation {
  const FamilleValidation({
    required this.id,
    required this.libelle,
    required this.module,
    required this.roles,
    required this.ecran,
    this.collections = const [],
    this.champs = const [],
    this.cibles = const [],
  });
  final String id;
  final String libelle;
  final String module;

  /// Collections des fiches marquées (forme 1) ; vide pour la forme « fiche ».
  final List<String> collections;

  /// Champs de marquage (`aValider`, `tarifProvisoire`) ; vide pour la forme « fiche ».
  final List<String> champs;

  /// Artefacts du code (forme 2) ; vide pour la forme « fiche marquée ».
  final List<CibleValidation> cibles;
  final List<String> roles;
  final String ecran;

  /// `fiche-marquee` (le marquage est sur la fiche) ou `fiche` (la validation vit dans `validationsReferentiels`).
  String get mode => cibles.isEmpty ? 'fiche-marquee' : 'fiche';
}

/// Le registre des 14 familles (`FAMILLES_A_VALIDER`), dans l'ordre de la maquette.
const List<FamilleValidation> valFamilles = [
  FamilleValidation(
      id: 'enquetes',
      libelle: 'Modèles d’enquête',
      module: 'M13',
      collections: ['enquetes'],
      champs: ['aValider'],
      roles: ['direction', 'da', 'admin'],
      ecran: 'adm-enquetes'),
  FamilleValidation(
      id: 'labo_variables',
      libelle: 'Variables et unités du laboratoire (bornes suppléées)',
      module: 'M5',
      collections: ['variablesLabo', 'unitesLabo'],
      champs: ['aValider'],
      roles: ['laborantin'],
      ecran: 'm5-valeurs-reference'),
  FamilleValidation(
      id: 'pathologies',
      libelle: 'Pathologies (tableau de morbidité)',
      module: 'M2',
      collections: ['pathologies'],
      champs: ['aValider'],
      roles: ['dm', 'medecin'],
      ecran: 'm2-pathologies'),
  FamilleValidation(
      id: 'imagerie',
      libelle: 'Catalogue de l’imagerie (examens et variables)',
      module: 'CFG',
      collections: ['examensImagerie', 'variablesImagerie'],
      champs: ['aValider'],
      roles: ['echographiste', 'dm'],
      ecran: 'cfg-imagerie-catalogue'),
  FamilleValidation(
      id: 'checklists_bloc',
      libelle: 'Check-listes du bloc, échelles ASA et Mallampati',
      module: 'M3',
      cibles: [CibleValidation('checklist-bloc', 'Check-listes d’entrée et de sortie du bloc')],
      roles: ['chirurgien', 'anesthesiste'],
      ecran: 'm3-bloc-checklist'),
  FamilleValidation(
      id: 'actes',
      libelle: 'Tarifs des actes (valeurs d’attente)',
      module: 'CFG',
      collections: ['actes'],
      champs: ['tarifProvisoire'],
      roles: ['direction', 'da', 'admin'],
      ecran: 'cfg-tarifs'),
  FamilleValidation(
      id: 'analyses',
      libelle: 'Tarifs des analyses',
      module: 'CFG',
      collections: ['analyses'],
      champs: ['tarifProvisoire', 'aValider'],
      roles: ['direction', 'da', 'admin'],
      ecran: 'cfg-tarifs'),
  FamilleValidation(
      id: 'valorisation_sage',
      libelle: 'Valorisation des références SAGE',
      module: 'M6',
      collections: ['valorisationsSage'],
      champs: ['aValider'],
      roles: ['direction', 'da', 'admin'],
      ecran: 'm6-produits'),
  FamilleValidation(
      id: 'objectifs_pilotage',
      libelle: 'Objectifs de pilotage',
      module: 'M12',
      collections: ['objectifsPilotage'],
      champs: ['aValider'],
      roles: ['direction', 'da', 'admin'],
      ecran: 'm12-tableau-decisionnel'),
  FamilleValidation(
      id: 'repartition_charges',
      libelle: 'Répartition fixe et variable des charges',
      module: 'M12',
      cibles: [CibleValidation('repartition-fixe-variable', 'Répartition proposée des comptes de charge')],
      roles: ['comptable', 'direction', 'da', 'admin'],
      ecran: 'm12-seuil-rentabilite'),
  FamilleValidation(
      id: 'modeles_badge',
      libelle: 'Modèles de badge',
      module: 'M10',
      collections: ['modelesBadge'],
      champs: ['aValider'],
      roles: ['direction', 'da', 'admin'],
      ecran: 'm10-badges-modeles'),
  FamilleValidation(
      id: 'jeux_import',
      libelle: 'Jeux d’import en proposition',
      module: 'IMP',
      cibles: [CibleValidation('imp-analyses', 'Importation du catalogue des analyses')],
      roles: ['direction', 'da', 'admin'],
      ecran: 'imp-analyses'),
  FamilleValidation(
      id: 'modeles_messages',
      libelle: 'Modèles de messages',
      module: 'CFG',
      collections: ['modelesMessage'],
      champs: ['aValider'],
      roles: ['direction', 'da', 'admin'],
      ecran: 'cfg-notifications'),
  FamilleValidation(
      id: 'bareme_its',
      libelle: 'Barème de l’ITS',
      module: 'M11',
      cibles: [CibleValidation('bareme-its', 'Barème de l’impôt sur les traitements et salaires')],
      roles: ['direction', 'da', 'admin'],
      ecran: 'cfg-comptabilite'),
];

/// Les collections que le moteur lit (celles des familles marquées, plus [valCollectionValidations]) : ce que le poste doit garder en magasin.
List<String> valCollectionsLues() => [
      for (final f in valFamilles) ...f.collections,
      valCollectionValidations,
    ];

FamilleValidation? valFamille(String id) {
  for (final f in valFamilles) {
    if (f.id == id) return f;
  }
  return null;
}

/// `libelleRole` : le libellé d'un rôle, ou « aucun » quand la session n'en porte pas. [libelles] vient du manifeste (rôles renommés compris).
String valLibelleRole(String? role, Map<String, String> libelles) {
  if (role == null || role.isEmpty) return 'aucun';
  final l = libelles[role];
  return (l == null || l.isEmpty) ? role : l;
}

/// Un refus NOMMÉ : le code, le motif lisible et le geste qui corrige (le même triplet que `refusCfg` de la maquette).
class RefusValidation {
  const RefusValidation(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String? geste;
}

/// La ligne de journal d'un geste (RG-12). [avant] et [apres] sont les valeurs ; la maquette en écrit un extrait JSON de 100 caractères.
class JournalValidation {
  const JournalValidation(this.action, this.module, this.entite, this.reference, this.avant, this.apres);
  final String action;
  final String module;
  final String entite;
  final String reference;
  final Map<String, Object?> avant;
  final Map<String, Object?> apres;
}

/// Un artefact d'une famille avec son état LU.
class ArtefactValidation {
  const ArtefactValidation(
      {required this.id, required this.libelle, required this.enAttente, required this.valideLe, required this.rec, required this.collection});
  final String id;
  final String libelle;
  final bool enAttente;
  final Object? valideLe;

  /// La fiche (marquée, ou la fiche `VRF-<cible>`) ; `null` pour une constante du code jamais validée.
  final Map<String, Object?>? rec;

  /// La collection de la fiche ; `null` pour une constante du code (la fiche de validation vit dans [valCollectionValidations]).
  final String? collection;
}

/// Le compte RÉEL d'une famille (`referentielsAValider`).
class CompteFamille {
  const CompteFamille(
      {required this.famille,
      required this.libelle,
      required this.module,
      required this.mode,
      required this.collections,
      required this.champs,
      required this.roles,
      required this.profil,
      required this.ecran,
      required this.enAttente,
      required this.total,
      required this.nonAmorce,
      required this.ids});
  final String famille;
  final String libelle;
  final String module;
  final String mode;
  final List<String> collections;
  final List<String> champs;
  final List<String> roles;
  final String profil;
  final String ecran;

  /// `null` : famille non amorcée (aucune fiche), le compte serait un mensonge.
  final int? enAttente;
  final int? total;
  final bool nonAmorce;
  final List<String> ids;
}

/// L'état LU d'un artefact (`etatValidation`, jamais stocké) : sert les badges et les boutons des écrans.
class EtatValidation {
  const EtatValidation(
      {required this.famille,
      required this.id,
      required this.libelle,
      required this.enAttente,
      required this.valideLe,
      required this.validePar,
      required this.valideRole,
      required this.roles,
      required this.profil});
  final String famille;
  final String id;
  final String libelle;
  final bool enAttente;
  final String? valideLe;
  final String? validePar;
  final String? valideRole;
  final List<String> roles;
  final String profil;
}

/// Ce que le geste de validation rend : un refus nommé, ou ce qu'il faut ÉCRIRE.
class VerdictValidation {
  const VerdictValidation.refus(RefusValidation r)
      : refus = r,
        famille = null,
        id = null,
        valideLe = null,
        validePar = null,
        valideRole = null,
        collection = null,
        patch = const {},
        creation = null,
        journal = null;
  const VerdictValidation.ok({
    required this.famille,
    required this.id,
    required this.valideLe,
    required this.validePar,
    required this.valideRole,
    required this.collection,
    required this.patch,
    required this.creation,
    required this.journal,
  }) : refus = null;
  final RefusValidation? refus;
  bool get ok => refus == null;
  final String? famille;
  final String? id;
  final String? valideLe;
  final String? validePar;
  final String? valideRole;

  /// La collection à écrire : celle de la fiche marquée, ou [valCollectionValidations] pour une constante du code.
  final String? collection;

  /// Les champs à poser sur la fiche (`id`), ou, si [creation] n'est pas nul, la fiche entière à INSÉRER (cette fiche porte son `id` `VRF-<cible>`).
  final Map<String, Object?> patch;
  final Map<String, Object?>? creation;
  final JournalValidation? journal;
}

/// Ce que la remise à valider rend.
class VerdictRemise {
  const VerdictRemise({required this.ok, this.refus, this.remis = false, this.famille, this.id, this.collection, this.patch = const {}, this.journal});
  final bool ok;
  final RefusValidation? refus;
  final bool remis;
  final String? famille;
  final String? id;
  final String? collection;
  final Map<String, Object?> patch;
  final JournalValidation? journal;
}

// --- Lectures -------------------------------------------------------------------------------------------------------------------------------------

/// La vérité d'un champ au sens de la maquette (`x || y`) : ni nul, ni faux, ni vide, ni zéro.
bool _vrai(Object? v) => v != null && v != false && v != '' && v != 0;

String _premier(Map<String, Object?> rec, List<String> cles) {
  for (final c in cles) {
    if (_vrai(rec[c])) return '${rec[c]}';
  }
  return '';
}

/// Les libellés des rôles d'une famille, séparés par une virgule (`profilsFamille`).
String valProfilsFamille(FamilleValidation f, Map<String, String> libelles) => f.roles.map((r) => valLibelleRole(r, libelles)).join(', ');

Map<String, Object?>? _ficheDeValidation(LectureValidation lire, String cible) {
  for (final x in lire(valCollectionValidations)) {
    if (x['id'] == 'VRF-$cible' && x['statut'] != 'archive') return x;
  }
  return null;
}

/// Les artefacts d'une famille, chacun avec son état LU.
List<ArtefactValidation> valArtefactsDe(FamilleValidation f, LectureValidation lire) {
  if (f.mode == 'fiche') {
    return [
      for (final c in f.cibles)
        () {
          final fiche = _ficheDeValidation(lire, c.id);
          final valide = fiche != null && _vrai(fiche['valideLe']);
          return ArtefactValidation(
              id: c.id,
              libelle: c.libelle,
              enAttente: !valide,
              valideLe: fiche?['valideLe'],
              rec: fiche,
              collection: null);
        }()
    ];
  }
  final out = <ArtefactValidation>[];
  for (final nom in f.collections) {
    for (final rec in lire(nom)) {
      if (rec['statut'] == 'archive') continue;
      out.add(ArtefactValidation(
          id: '${rec['id']}',
          collection: nom,
          rec: rec,
          valideLe: _vrai(rec['valideLe']) ? rec['valideLe'] : null,
          libelle: _premier(rec, const ['libelle', 'label', 'designation', 'nom', 'reference', 'id']),
          enAttente: f.champs.any((c) => rec[c] == true)));
    }
  }
  return out;
}

/// Les familles avec leur compte RÉEL. [role] non nul : seules les familles que ce profil valide (`referentielsAValider({role})`).
/// [amorcable] dit si une collection vide peut encore être amorcée (`S.amorcable`) : une famille vide et amorçable est « non amorcée ».
List<CompteFamille> valReferentielsAValider(LectureValidation lire, Map<String, String> libelles,
    {String? role, bool Function(String collection)? amorcable}) {
  final peut = amorcable ?? (_) => true;
  return [
    for (final f in valFamilles)
      if (role == null || role.isEmpty || f.roles.contains(role))
        () {
          final arts = valArtefactsDe(f, lire);
          final nonAmorce =
              f.mode != 'fiche' && arts.isEmpty && f.collections.every((n) => lire(n).isEmpty) && peut(f.collections.first);
          final attente = [for (final a in arts) if (a.enAttente) a];
          return CompteFamille(
              famille: f.id,
              libelle: f.libelle,
              module: f.module,
              mode: f.mode,
              collections: f.mode == 'fiche' ? const [valCollectionValidations] : f.collections,
              champs: f.mode == 'fiche' ? const ['valideLe'] : f.champs,
              roles: f.roles,
              profil: valProfilsFamille(f, libelles),
              ecran: f.ecran,
              enAttente: nonAmorce ? null : attente.length,
              total: nonAmorce ? null : arts.length,
              nonAmorce: nonAmorce,
              ids: [for (final a in attente) a.id]);
        }()
  ];
}

/// Les familles qu'un profil VOIT au centre des validations : la Direction, la DAF et l'administrateur voient tout, les autres leur ressort.
List<CompteFamille> valReferentielsVisiblesPar(String role, LectureValidation lire, Map<String, String> libelles,
        {bool Function(String collection)? amorcable}) =>
    valReferentielsAValider(lire, libelles, role: valVueComplete.contains(role) ? null : role, amorcable: amorcable);

/// `etatValidation` : l'état LU d'un artefact, ou `null` (famille ou élément inconnu).
EtatValidation? valEtatValidation(String familleId, String id, LectureValidation lire, Map<String, String> libelles) {
  final f = valFamille(familleId);
  if (f == null) return null;
  ArtefactValidation? a;
  for (final x in valArtefactsDe(f, lire)) {
    if (x.id == id) {
      a = x;
      break;
    }
  }
  if (a == null) return null;
  final rec = a.rec ?? const <String, Object?>{};
  String? t(Object? v) => _vrai(v) ? '$v' : null;
  return EtatValidation(
      famille: f.id,
      id: id,
      libelle: a.libelle,
      enAttente: a.enAttente,
      valideLe: t(a.valideLe),
      validePar: t(rec['validePar']),
      valideRole: t(rec['valideRole']),
      roles: f.roles,
      profil: valProfilsFamille(f, libelles));
}

/// Le profil peut-il valider cette famille ? (`K.peutValider` : le rôle de la SESSION est un des rôles de la famille.)
bool valPeutValider(String familleId, String role) => valFamille(familleId)?.roles.contains(role) ?? false;

// --- Gestes ---------------------------------------------------------------------------------------------------------------------------------------

String _dateFr(Object? iso) {
  final s = '$iso';
  final j = s.length >= 10 ? s.substring(0, 10) : s;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(j);
  return m == null ? j : '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}

/// L'horloge de la maquette : `new Date().toISOString()` (millisecondes, UTC).
String valInstant(DateTime maintenant) =>
    DateTime.fromMillisecondsSinceEpoch(maintenant.millisecondsSinceEpoch, isUtc: true).toIso8601String();

/// `validerReferentiel` : UN geste valide UNE fiche. Refus NOMMÉS : `INTROUVABLE`, `VALIDATION_RESERVEE`, `DEJA_VALIDE`, `TARIF_ABSENT`. Ne modifie
/// rien : rend ce qu'il faut écrire. [role] est celui de la SESSION (jamais fourni par l'écran).
VerdictValidation valValiderReferentiel(
  String familleId,
  String id, {
  required String role,
  required String acteur,
  required DateTime maintenant,
  required LectureValidation lire,
  required Map<String, String> libelles,
}) {
  final f = valFamille(familleId);
  if (f == null) {
    return VerdictValidation.refus(RefusValidation(
        'INTROUVABLE', 'Famille de référentiel inconnue : $familleId.', 'Choisir une famille du registre des validations.'));
  }
  if (!f.roles.contains(role)) {
    return VerdictValidation.refus(RefusValidation(
        'VALIDATION_RESERVEE',
        'La validation de « ${f.libelle} » est réservée à : ${valProfilsFamille(f, libelles)}. Profil : ${valLibelleRole(role, libelles)}.',
        'Demander à ${valLibelleRole(f.roles.first, libelles)} de valider depuis son poste.'));
  }
  ArtefactValidation? cible;
  for (final a in valArtefactsDe(f, lire)) {
    if (a.id == id) {
      cible = a;
      break;
    }
  }
  if (cible == null) {
    return VerdictValidation.refus(RefusValidation(
        'INTROUVABLE', 'Aucun élément « $id » dans « ${f.libelle} ».', 'Ouvrir l’écran de la famille et choisir l’élément à valider.'));
  }
  if (!cible.enAttente) {
    return VerdictValidation.refus(RefusValidation(
        'DEJA_VALIDE',
        _vrai(cible.valideLe)
            ? '« ${cible.libelle} » est déjà validé (${_dateFr(cible.valideLe)}).'
            : '« ${cible.libelle} » ne porte aucun marquage à valider.',
        'Rien à faire : toute modification ultérieure le remettra à valider.'));
  }
  // Un tarif ABSENT ne se valide pas : le tiret n'est ni un zéro ni un tarif arrêté.
  if ((f.id == 'actes' || f.id == 'analyses') && cible.rec != null && cible.rec!['prix'] == null) {
    return VerdictValidation.refus(RefusValidation(
        'TARIF_ABSENT', '« ${cible.libelle} » n’a aucun tarif : il n’y a rien à valider.', 'Saisir le tarif d’attente, puis le valider.'));
  }
  final quand = valInstant(maintenant);
  final libRole = valLibelleRole(role, libelles);
  final traces = <String, Object?>{'valideLe': quand, 'validePar': acteur, 'valideRole': libRole};
  if (f.mode == 'fiche') {
    final fiche = cible.rec;
    final avant = <String, Object?>{if (fiche != null && fiche.containsKey('valideLe')) 'valideLe': fiche['valideLe']};
    if (fiche == null) {
      avant['valideLe'] = null;
    }
    return VerdictValidation.ok(
        famille: f.id,
        id: id,
        valideLe: quand,
        validePar: acteur,
        valideRole: libRole,
        collection: valCollectionValidations,
        patch: traces,
        creation: fiche == null
            ? {'id': 'VRF-$id', 'statut': 'actif', 'famille': f.id, 'cible': id, 'libelle': cible.libelle, ...traces}
            : null,
        journal: JournalValidation('Validation', f.module, f.libelle, id, avant, traces));
  }
  final rec = cible.rec!;
  final avant = <String, Object?>{};
  final patch = <String, Object?>{};
  for (final c in f.champs) {
    if (rec[c] == true) {
      avant[c] = true;
      patch[c] = false;
    }
  }
  patch.addAll(traces);
  return VerdictValidation.ok(
      famille: f.id,
      id: id,
      valideLe: quand,
      validePar: acteur,
      valideRole: libRole,
      collection: cible.collection!,
      patch: patch,
      creation: null,
      journal: JournalValidation('Validation', f.module, f.libelle, id, avant, traces));
}

/// `remettreAValider` : appelé par l'écran qui MODIFIE un artefact validé : le marquage revient, les traces de validation tombent. Un artefact déjà
/// « à valider » ne bouge pas (`remis: false`, aucune écriture, aucune ligne de journal).
VerdictRemise valRemettreAValider(String familleId, String id, {required LectureValidation lire}) {
  final f = valFamille(familleId);
  if (f == null) {
    return VerdictRemise(
        ok: false,
        refus: RefusValidation(
            'INTROUVABLE', 'Famille de référentiel inconnue : $familleId.', 'Choisir une famille du registre des validations.'));
  }
  ArtefactValidation? cible;
  for (final a in valArtefactsDe(f, lire)) {
    if (a.id == id) {
      cible = a;
      break;
    }
  }
  if (cible == null) {
    return VerdictRemise(
        ok: false, refus: RefusValidation('INTROUVABLE', 'Aucun élément « $id » dans « ${f.libelle} ».', 'Ouvrir l’écran de la famille.'));
  }
  if (cible.enAttente) return VerdictRemise(ok: true, remis: false, famille: f.id, id: id);
  final traces = <String, Object?>{'valideLe': null, 'validePar': null, 'valideRole': null};
  return VerdictRemise(
      ok: true,
      remis: true,
      famille: f.id,
      id: id,
      collection: f.mode == 'fiche' ? valCollectionValidations : cible.collection,
      patch: f.mode == 'fiche' ? traces : {f.champs.first: true, ...traces},
      journal: JournalValidation(
          'Remise à valider', f.module, f.libelle, id, {'valideLe': cible.valideLe}, {'motif': 'modifié depuis la validation'}));
}
