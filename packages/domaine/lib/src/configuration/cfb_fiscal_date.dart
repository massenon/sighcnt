/// CONFIGURATION FISCALE VALIDÉE ET DATÉE (Direction, 06/11/2026) : l'identité légale par VERSIONS, les obligations fiscales et les paramètres
/// ORTB DATÉS avec historique, les échéances d'un exercice engendrées depuis la version EN VIGUEUR, la validation RÉSERVÉE, et l'échéance payée
/// qui ne bouge jamais.
///
/// Port de `core.js` (`identiteALaDate`), `data.js` (`obligationsALaDate`, `ortbALaDate`, semences), `store.js` (`genEcheances`,
/// `regenererEcheances`) et `parcours.js` (`SIGH.configurationFiscale`), rejoué sur `test/vecteurs/fiscal-date.json` (ENGENDRÉ par
/// `prototype_html/build/vecteurs-fiscal-date.js`, tiré du moteur RÉEL de la maquette, jamais recopié).
///
/// Fonctions PURES : elles reçoivent les listes du magasin (versions, obligations, historique, échéances, exercices), l'horloge et l'acteur, et
/// rendent ce qu'il faut ÉCRIRE (fiche, patch, copie d'historique, échéances archivées et créées). C'est l'appelant (le magasin du poste) qui
/// écrit, journalise (RG-12) et notifie. Un refus se nomme : `code`, `motif`, `geste`. Symboles préfixés `cfb` / `Cfb`.
library;

import '../comptabilite/cpc_exercice.dart' show cpcEtatExercice;
import '../format/format_fr.dart' show dateFR, nombre;
import '../format/js.dart' show arrondiJs, nombreOuZero;
import '../impression/identite.dart';
import '../paie/pai_moteur.dart' show PaiParametresOrtb, paiCodeParametresOrtb, paiFicheOrtbALaDate, paiMois;
import '../referentiels/versions_datees.dart';
import 'cfa_regles.dart' show CfaFiche;
import 'cfb_donnees.dart';

export '../referentiels/versions_datees.dart' show isoJour, veilleIso, versionEnVigueur;

// =============================================================================================================================================
// Refus nommés et rôles
// =============================================================================================================================================

/// Un refus du moteur : son code (stable, sondé), son motif lisible et le geste qui corrige.
class CfbRefus {
  const CfbRefus(this.code, this.motif, [this.geste]);
  final String code, motif;
  final String? geste;

  @override
  String toString() => '$code : $motif';
}

/// Les rôles qui VALIDENT la configuration fiscale (`ROLES_VALIDATION` de parcours.js) : la Direction, la DAF, l'administrateur système.
const List<String> cfbRolesValidation = ['direction', 'da', 'admin'];

/// `FILEUL_LECTURE_SEULE` : un fileul ne modifie jamais la configuration de la clinique (famille R, publiée par la mère seule).
CfbRefus? cfbControleFileul(bool fileul) => fileul
    ? const CfbRefus('FILEUL_LECTURE_SEULE', 'Cette configuration est tenue par la mère ; modifiez-la sur le poste mère.',
        'Ouvrir le même écran sur le poste mère : la modification arrivera ici par la synchronisation.')
    : null;

/// `VALIDATION_RESERVEE` : qui peut valider. Le contrôle est REFAIT ici même si l'écran a masqué la commande (défense en profondeur).
CfbRefus? cfbControleValidation({required String? role, bool fileul = false, String Function(String?)? libelleRole}) {
  final f = cfbControleFileul(fileul);
  if (f != null) return f;
  if (role == null || !cfbRolesValidation.contains(role)) {
    final lib = libelleRole != null ? libelleRole(role) : (role ?? 'aucun');
    return CfbRefus('VALIDATION_RESERVEE',
        'La validation de la configuration fiscale est réservée à la Direction, à la DAF et à l’administrateur système. Profil : $lib.',
        'Demander à la Direction ou à la DAF de valider depuis son poste.');
  }
  return null;
}

String _dateFrIso(String iso) => dateFR(DateTime.parse(isoJour(iso)));

/// La date d'effet d'une version : obligatoire, hors exercice CLOS (`cpcEtatExercice`), jamais antérieure à la version en vigueur ([minimum]).
CfbRefus? cfbControleDateEffet(String? dateEffet, {String? minimum, required Iterable<CfaFiche> exercices, required DateTime aujourdhui}) {
  if (dateEffet == null || dateEffet.isEmpty) {
    return const CfbRefus('DATE_EFFET_REQUISE', 'La date d’effet est obligatoire.', 'Choisir la date à partir de laquelle la nouvelle version s’applique.');
  }
  final d = isoJour(dateEffet);
  final annee = int.tryParse(d.substring(0, 4)) ?? aujourdhui.year;
  if (cpcEtatExercice(exercices, annee) == 'clos') {
    return CfbRefus('EXERCICE_CLOS', 'La date d’effet tombe dans un exercice clos ($annee) ; choisissez une date de l’exercice ouvert.',
        'Choisir une date d’effet dans l’exercice ${aujourdhui.year}.');
  }
  if (minimum != null && minimum.isNotEmpty && d.compareTo(isoJour(minimum)) < 0) {
    return CfbRefus('DATE_EFFET_ANTERIEURE',
        'La date d’effet (${_dateFrIso(d)}) est antérieure à la version en vigueur (${_dateFrIso(minimum)}).',
        'Choisir une date d’effet au plus tôt le ${_dateFrIso(minimum)}.');
  }
  return null;
}

bool _actif(CfaFiche f) => f['statut'] != 'archive';
bool _vide(Object? v) => v == null || '$v'.trim().isEmpty;
String _horodatage(DateTime d) => d.toUtc().toIso8601String();

// =============================================================================================================================================
// Identité légale : versions datées
// =============================================================================================================================================

/// `C.BRAND_ORIGINE` : la semence, sur la forme d'une fiche (les seuls champs d'identité).
CfaFiche cfbIdentiteSemence() => IdentiteImprimee.semence.fiche;

/// `C.champsIdentite(fiche)` : les seuls champs d'identité (ni id, ni version, ni dates), sur la forme de la semence ; un champ absent retombe
/// sur la semence.
CfaFiche cfbChampsIdentite(CfaFiche? fiche) {
  final s = cfbIdentiteSemence();
  return {
    for (final k in champsIdentiteLegale)
      k: fiche != null && fiche.containsKey(k)
          ? (fiche[k] is List ? [...fiche[k] as List] : fiche[k])
          : (s[k] is List ? [...s[k] as List] : s[k]),
  };
}

/// La fiche SEMÉE de l'identité (version 1, depuis l'ouverture du dossier, non validée) : ce que `store.seed()` écrit.
CfaFiche cfbSemenceIdentite({String id = 'IDL001'}) => {
      'id': id,
      'statut': 'actif',
      'version': 1,
      'debut': null,
      'fin': null,
      'creeLe': '2026-08-31',
      'creePar': 'core.js (semence)',
      'motif': null,
      'valideLe': null,
      'validePar': null,
      'source': 'core.js, arbitrage du 31/08/2026',
      ...cfbIdentiteSemence(),
    };

/// `S.identiteALaDate(date)` : la version dont `debut <= date` (ou `debut` nul, « depuis l'ouverture du dossier ») et (`fin` nul ou
/// `date <= fin`), la plus haute d'abord ; une date antérieure à toute version rend la version 1 ; aucune version active : `null`.
CfaFiche? cfbIdentiteALaDate(Iterable<CfaFiche> versions, DateTime date) {
  final liste = versions.where(_actif).toList();
  if (liste.isEmpty) return null;
  final d = isoJour(date);
  int version(CfaFiche v) => nombreOuZero(v['version']).toInt();
  final couvrantes = [
    for (final v in liste)
      if ((v['debut'] == null || d.compareTo(isoJour(v['debut'])) >= 0) && (v['fin'] == null || d.compareTo(isoJour(v['fin'])) <= 0)) v
  ]..sort((a, b) => version(b).compareTo(version(a)));
  if (couvrantes.isNotEmpty) return couvrantes.first;
  liste.sort((a, b) => version(a).compareTo(version(b)));
  return liste.first;
}

/// `C.identiteALaDate(date)` : ce qu'une PIÈCE imprime à sa date : la version en force, sinon la semence.
IdentiteImprimee cfbIdentiteImprimee(Iterable<CfaFiche> versions, DateTime date) => IdentiteImprimee.depuisFiche(cfbIdentiteALaDate(versions, date));

/// Les champs saisis, normalisés : téléphones en liste (une chaîne se coupe sur « / », « , » ou « ; »), chaînes sans blancs aux bords ; seuls
/// les champs d'identité connus passent.
CfaFiche cfbNormaliserIdentite(Map<String, Object?> champs) {
  final c = <String, Object?>{};
  for (final k in champsIdentiteLegale) {
    if (!champs.containsKey(k)) continue;
    var v = champs[k];
    if (k == 'telephones') {
      final brut = v is List ? v : '${v ?? ''}'.split(RegExp(r'[/,;]'));
      v = [for (final t in brut) '$t'.trim()].where((t) => t.isNotEmpty).toList();
    } else if (v is String) {
      v = v.trim();
    }
    c[k] = v;
  }
  return c;
}

/// Les contrôles de l'identité AVANT écriture (sur les seuls champs présents) : dénomination, IFU à 13 chiffres, RCCM, au moins un téléphone.
CfbRefus? cfbControleIdentite(CfaFiche c) {
  if (c.containsKey('nom') && _vide(c['nom'])) {
    return const CfbRefus('NOM_REQUIS', 'La dénomination sociale est obligatoire.', 'Saisir la dénomination telle qu’elle figure au RCCM.');
  }
  if (c.containsKey('ifu') && !RegExp(r'^\d{13}$').hasMatch('${c['ifu'] ?? ''}'.replaceAll(RegExp(r'\s'), ''))) {
    return const CfbRefus('IFU_FORMAT', 'L’IFU compte 13 chiffres.', 'Relever l’IFU sur l’attestation d’immatriculation fiscale.');
  }
  if (c.containsKey('rccm') && _vide(c['rccm'])) {
    return const CfbRefus('RCCM_REQUIS', 'Le RCCM est obligatoire.', 'Relever le RCCM sur l’extrait du registre du commerce.');
  }
  if (c.containsKey('telephones') && (c['telephones'] is! List || (c['telephones'] as List).isEmpty)) {
    return const CfbRefus('TELEPHONE_REQUIS', 'Au moins un téléphone est requis sur l’en-tête.', 'Saisir le ou les numéros, séparés par « / ».');
  }
  return null;
}

/// Les versions que la validation vise et que l'état compte : en force ou à venir (`fin` nul ou postérieur à aujourd'hui), actives.
List<CfaFiche> cfbVersionsIdentiteAValider(Iterable<CfaFiche> versions, DateTime aujourdhui) {
  final a = isoJour(aujourdhui);
  return [for (final v in versions.where(_actif)) if (v['fin'] == null || isoJour(v['fin']).compareTo(a) >= 0) v];
}

/// L'identité a-t-elle déjà été validée une fois (toutes versions, archivées comprises) ? Si oui, toute modification crée une version datée.
bool cfbIdentiteExigeVersion(Iterable<CfaFiche> versions) => versions.any((v) => !_vide(v['valideLe']));

/// Ce qu'une écriture de l'identité rend : un refus, ou ce qu'il faut écrire.
class CfbEcritureIdentite {
  const CfbEcritureIdentite._({this.refus, this.mode, this.version, this.id, this.fiche, this.precedenteId, this.patchPrecedente, this.enForceAujourdhui = false});
  const CfbEcritureIdentite.refusee(CfbRefus refus) : this._(refus: refus);
  final CfbRefus? refus;
  bool get ok => refus == null;

  /// `en_place` (la version en force est corrigée) ou `version` (une version nouvelle naît).
  final String? mode;
  final int? version;

  /// `en_place` : l'identifiant de la version à corriger et le PATCH à lui appliquer. `version` : la fiche NOUVELLE (sans id : le magasin l'attribue).
  final String? id;
  final CfaFiche? fiche;

  /// `version` : la version couvrante qui se ferme (`fin` = veille de la date d'effet) et son patch ; `null` quand aucune ne couvrait la date.
  final String? precedenteId;
  final CfaFiche? patchPrecedente;

  /// `version` : la nouvelle version est-elle déjà en force aujourd'hui ?
  final bool enForceAujourdhui;
}

/// AVANT la première validation, « Enregistrer » CORRIGE la version en force : la première configuration est un brouillon. Après une validation,
/// `VERSION_REQUISE` renvoie à la modale « Portée de la modification ».
CfbEcritureIdentite cfbEnregistrerIdentite(Iterable<CfaFiche> versions, Map<String, Object?> champs,
    {required String acteur, required DateTime maintenant, required DateTime aujourdhui, bool fileul = false}) {
  final f = cfbControleFileul(fileul);
  if (f != null) return CfbEcritureIdentite.refusee(f);
  final c = cfbNormaliserIdentite(champs);
  final r = cfbControleIdentite(c);
  if (r != null) return CfbEcritureIdentite.refusee(r);
  final enForce = cfbIdentiteALaDate(versions, aujourdhui);
  if (enForce == null) {
    return const CfbEcritureIdentite.refusee(
        CfbRefus('IDENTITE_ABSENTE', 'Aucune version de l’identité légale au magasin.', 'Réinitialiser le jeu de démonstration (Paramètres système).'));
  }
  if (cfbIdentiteExigeVersion(versions)) {
    return const CfbEcritureIdentite.refusee(CfbRefus('VERSION_REQUISE', 'L’identité légale a déjà été validée : toute modification crée une version datée.',
        'Indiquer la date d’effet et le motif (modale « Portée de la modification »).'));
  }
  return CfbEcritureIdentite._(
      mode: 'en_place',
      version: nombreOuZero(enForce['version']).toInt(),
      id: '${enForce['id']}',
      fiche: {...c, 'modifieLe': _horodatage(maintenant), 'modifiePar': acteur});
}

/// APRÈS une validation : une version NOUVELLE, datée et motivée ; la version couvrante reçoit `fin` = veille de la date d'effet et RESTE. Les
/// champs non saisis sont copiés de la version couvrante (ou de la semence). Refus nommés : `MOTIF_REQUIS`, `IFU_FORMAT`…, `EXERCICE_CLOS`,
/// `DATE_EFFET_ANTERIEURE`, `VERSION_EXISTANTE`.
CfbEcritureIdentite cfbNouvelleVersionIdentite(Iterable<CfaFiche> versions, Map<String, Object?> champs,
    {Object? dateEffet,
    String? motif,
    required String acteur,
    required DateTime maintenant,
    required DateTime aujourdhui,
    Iterable<CfaFiche> exercices = const [],
    bool fileul = false,
    String origine = 'cfg-fiscalite'}) {
  final f = cfbControleFileul(fileul);
  if (f != null) return CfbEcritureIdentite.refusee(f);
  final c = cfbNormaliserIdentite(champs);
  var r = cfbControleIdentite(c);
  if (r != null) return CfbEcritureIdentite.refusee(r);
  if (_vide(motif)) {
    return const CfbEcritureIdentite.refusee(
        CfbRefus('MOTIF_REQUIS', 'Le motif est obligatoire dès la version 2.', 'Dire pourquoi l’identité change (changement de RCCM, nouvelle adresse…).'));
  }
  final d = isoJour(dateEffet ?? aujourdhui);
  final toutes = versions.where(_actif).toList();
  final couverte = cfbIdentiteALaDate(versions, DateTime.parse(d));
  r = cfbControleDateEffet(d, minimum: couverte?['debut'] == null ? null : isoJour(couverte!['debut']), exercices: exercices, aujourdhui: aujourdhui);
  if (r != null) return CfbEcritureIdentite.refusee(r);
  if (toutes.any((v) => v['debut'] != null && isoJour(v['debut']) == d)) {
    return CfbEcritureIdentite.refusee(CfbRefus('VERSION_EXISTANTE', 'Une version prend déjà effet le ${_dateFrIso(d)}.', 'Choisir une autre date d’effet.'));
  }
  final suivantes = [for (final v in toutes) if (v['debut'] != null && isoJour(v['debut']).compareTo(d) > 0) v]
    ..sort((a, b) => isoJour(a['debut']).compareTo(isoJour(b['debut'])));
  final suivante = suivantes.isEmpty ? null : suivantes.first;
  var numero = 0;
  for (final v in versions) {
    final n = nombreOuZero(v['version']).toInt();
    if (n > numero) numero = n;
  }
  numero++;
  final fiche = <String, Object?>{
    ...cfbChampsIdentite(couverte),
    ...c,
    'statut': 'actif',
    'version': numero,
    'debut': d,
    'fin': suivante == null ? null : veilleIso(suivante['debut']),
    'creeLe': _horodatage(maintenant),
    'creePar': acteur,
    'motif': motif!.trim(),
    'valideLe': null,
    'validePar': null,
    'source': 'Saisie à l’écran ($origine)',
  };
  return CfbEcritureIdentite._(
      mode: 'version',
      version: numero,
      fiche: fiche,
      precedenteId: couverte == null ? null : '${couverte['id']}',
      patchPrecedente: couverte == null ? null : {'fin': veilleIso(d), 'modifieLe': _horodatage(maintenant), 'modifiePar': acteur},
      enForceAujourdhui: d.compareTo(isoJour(aujourdhui)) <= 0);
}

// =============================================================================================================================================
// Validation et état affiché
// =============================================================================================================================================

/// Ce qu'une validation rend : un refus, ou le patch `{valideLe, validePar}` à poser d'un coup sur [ids] (UNE ligne de journal, pas vingt).
class CfbValidation {
  const CfbValidation._({this.refus, this.valideLe, this.validePar, this.ids = const [], this.versions = const []});
  const CfbValidation.refusee(CfbRefus refus) : this._(refus: refus);
  final CfbRefus? refus;
  bool get ok => refus == null;
  final String? valideLe, validePar;
  final List<String> ids;

  /// Identité : les numéros de version validés.
  final List<int> versions;
  int get nombre => ids.length;
  CfaFiche get patch => {'valideLe': valideLe, 'validePar': validePar};
}

/// `PR.validerIdentite()` : la version en force ET les versions à venir reçoivent `valideLe` / `validePar`. Valider ne modifie aucun autre champ.
CfbValidation cfbValiderIdentite(Iterable<CfaFiche> versions,
    {required String? role, required String acteur, required DateTime maintenant, required DateTime aujourdhui, bool fileul = false, String Function(String?)? libelleRole}) {
  final r = cfbControleValidation(role: role, fileul: fileul, libelleRole: libelleRole);
  if (r != null) return CfbValidation.refusee(r);
  final cibles = cfbVersionsIdentiteAValider(versions, aujourdhui);
  if (cibles.isEmpty) {
    return const CfbValidation.refusee(
        CfbRefus('IDENTITE_ABSENTE', 'Aucune version de l’identité légale à valider.', 'Réinitialiser le jeu de démonstration (Paramètres système).'));
  }
  return CfbValidation._(
      valideLe: _horodatage(maintenant),
      validePar: acteur,
      ids: [for (final v in cibles) '${v['id']}'],
      versions: [for (final v in cibles) nombreOuZero(v['version']).toInt()]);
}

/// `PR.validerObligations()` : toutes les fiches ACTIVES de `obligationsFiscales` (obligations et paramètres ORTB) d'un coup.
CfbValidation cfbValiderObligations(Iterable<CfaFiche> obligations,
    {required String? role, required String acteur, required DateTime maintenant, bool fileul = false, String Function(String?)? libelleRole}) {
  final r = cfbControleValidation(role: role, fileul: fileul, libelleRole: libelleRole);
  if (r != null) return CfbValidation.refusee(r);
  final cibles = obligations.where(_actif).toList();
  if (cibles.isEmpty) {
    return const CfbValidation.refusee(CfbRefus('OBLIGATIONS_ABSENTES', 'Aucune obligation à valider.', 'Réinitialiser le jeu de démonstration (Paramètres système).'));
  }
  return CfbValidation._(valideLe: _horodatage(maintenant), validePar: acteur, ids: [for (final v in cibles) '${v['id']}']);
}

/// L'état affiché par les bandeaux (`PR.etatConfigurationFiscale`) : `a_valider` (rien de validé, jamais), `valide` (toutes les fiches actives
/// portent `valideLe`), `modifie_depuis` (au moins une fiche active sans `valideLe` alors qu'une validation antérieure existe : le bandeau dit
/// « Modifiée le D par P depuis la validation du D0 par P0 », RG-12).
class CfbEtatConfiguration {
  const CfbEtatConfiguration(
      {required this.etat, required this.nombre, required this.nonValidees, this.valideLe, this.validePar, this.modifieLe, this.modifiePar, this.validationAnterieure});
  final String etat;
  final int nombre, nonValidees;
  final String? valideLe, validePar, modifieLe, modifiePar;

  /// `{valideLe, validePar}` de la dernière validation, quand l'état est `modifie_depuis`.
  final CfaFiche? validationAnterieure;

  Map<String, Object?> get fiche => {
        'etat': etat,
        'nombre': nombre,
        'nonValidees': nonValidees,
        'valideLe': valideLe,
        'validePar': validePar,
        'modifieLe': modifieLe,
        'modifiePar': modifiePar,
        'validationAnterieure': validationAnterieure,
      };
}

String? _horodatageModif(CfaFiche f) {
  for (final k in const ['_modifieLe', 'modifieLe', 'creeLe', '_creeLe']) {
    if (!_vide(f[k])) return '${f[k]}';
  }
  return null;
}

String? _auteurModif(CfaFiche f) {
  for (final k in const ['_modifiePar', 'modifiePar', 'creePar', '_creePar']) {
    if (!_vide(f[k])) return '${f[k]}';
  }
  return null;
}

/// [fiches] : ce que la validation vise (versions en force et à venir, ou obligations actives) ; [toutes] : tout ce qui a pu porter une
/// validation (archivées et historique compris), pour savoir si une validation antérieure existe.
CfbEtatConfiguration cfbEtatConfiguration(Iterable<CfaFiche> fiches, Iterable<CfaFiche> toutes) {
  final l = fiches.toList();
  final validees = [for (final f in l) if (!_vide(f['valideLe'])) f]..sort((a, b) => '${b['valideLe']}'.compareTo('${a['valideLe']}'));
  final nonValidees = [for (final f in l) if (_vide(f['valideLe'])) f];
  final anterieures = [for (final f in toutes) if (!_vide(f['valideLe'])) f]..sort((a, b) => '${b['valideLe']}'.compareTo('${a['valideLe']}'));
  final anterieure = anterieures.isEmpty ? null : anterieures.first;
  final dates = [for (final f in nonValidees) _horodatageModif(f)].whereType<String>().toList()..sort();
  final derniere = dates.isEmpty ? null : dates.last;
  final derniereModif = nonValidees.where((f) => _horodatageModif(f) == derniere).firstOrNull ?? nonValidees.firstOrNull;
  final etat = l.isNotEmpty && nonValidees.isEmpty ? 'valide' : (anterieure != null ? 'modifie_depuis' : 'a_valider');
  return CfbEtatConfiguration(
      etat: etat,
      nombre: l.length,
      nonValidees: nonValidees.length,
      valideLe: etat == 'valide' ? '${validees.first['valideLe']}' : null,
      validePar: etat == 'valide' ? '${validees.first['validePar']}' : null,
      modifieLe: derniere,
      modifiePar: derniereModif == null ? null : _auteurModif(derniereModif),
      validationAnterieure: anterieure == null ? null : {'valideLe': anterieure['valideLe'], 'validePar': anterieure['validePar']});
}

/// L'état de l'identité légale : les versions en force et à venir, face à toutes les versions (archivées comprises).
CfbEtatConfiguration cfbEtatIdentite(Iterable<CfaFiche> versions, DateTime aujourdhui) =>
    cfbEtatConfiguration(cfbVersionsIdentiteAValider(versions, aujourdhui), versions);

/// L'état des obligations : les fiches actives, face à toutes les fiches et à l'historique.
CfbEtatConfiguration cfbEtatObligations(Iterable<CfaFiche> obligations, Iterable<CfaFiche> historique) =>
    cfbEtatConfiguration(obligations.where(_actif), [...obligations, ...historique]);

/// Le texte du bandeau d'état, dans les termes de la maquette.
String cfbTexteEtat(CfbEtatConfiguration e, String objet, String Function(String iso) dateHeureFr) {
  switch (e.etat) {
    case 'valide':
      return 'Validé le ${dateHeureFr(e.valideLe!)} par ${e.validePar}.';
    case 'modifie_depuis':
      final a = e.validationAnterieure!;
      return 'Modifié le ${e.modifieLe == null ? '?' : dateHeureFr(e.modifieLe!)} par ${e.modifiePar ?? '?'} depuis la validation du ${dateHeureFr('${a['valideLe']}')} par ${a['validePar']}.';
    default:
      return '$objet à valider (première configuration) : vérifier chaque mention, corriger ce qui doit l’être, puis Valider. '
          'La validation appartient à la Direction, à la DAF ou à l’administrateur système.';
  }
}

// =============================================================================================================================================
// Obligations fiscales et paramètres ORTB : versions datées
// =============================================================================================================================================

const String cfbSourceObligations = 'Précisions du comptable (réunion du 19/08/2026) ; calendrier confirmé par la Direction le 25/08/2026';

/// La fiche d'une obligation de la SEMENCE (`D.semenceObligations()`) : `type: 'obligation'`, `dateEffet` nul (depuis l'ouverture), non validée.
CfaFiche cfbFicheDepuisObligation(CfbObligation o, {String? id}) => {
      'id': id ?? 'FIS${(cfbCalendrierFiscal.indexOf(o) + 1).toString().padLeft(2, '0')}',
      'statut': 'actif',
      'type': 'obligation',
      'code': o.code,
      'libelle': o.libelle,
      'famille': o.code.split('-').first,
      'periodicite': o.periodicite,
      'jour': o.jour,
      'mois': o.mois,
      'part': o.part,
      'declaration': o.declaration,
      'note': o.note,
      'source': cfbSourceObligations,
      'dateEffet': null,
      'modifieLe': null,
      'modifiePar': null,
      'motif': null,
      'valideLe': null,
      'validePar': null,
    };

/// Une fiche du magasin relue sur la forme du calendrier (pour les fonctions de `cfb_regles.dart` qui lisent des [CfbObligation]).
CfbObligation cfbObligationDepuisFiche(CfaFiche f) => CfbObligation(
    '${f['code']}',
    '${f['libelle'] ?? ''}',
    '${f['periodicite'] ?? 'annuelle'}',
    nombreOuZero(f['jour']).toInt(),
    f['mois'] == null ? null : nombreOuZero(f['mois']).toInt(),
    f['part'] == null ? null : nombreOuZero(f['part']).toInt(),
    f['declaration'] == null ? null : '${f['declaration']}',
    '${f['note'] ?? ''}',
    '${f['source'] ?? ''}');

/// `D.semenceOrtbParametres()` : la fiche `ORTB-PARAMETRES` semée depuis `D.PARAM_PAIE.ortb`.
CfaFiche cfbSemenceOrtbParametres() => {
      'id': paiCodeParametresOrtb,
      'statut': 'actif',
      'type': 'parametres',
      'code': paiCodeParametresOrtb,
      'libelle': 'Redevance ORTB',
      'famille': 'ORTB',
      ...PaiParametresOrtb.semence.fiche,
      'source': 'Direction — précision du 20/08/2026',
      'modifieLe': null,
      'modifiePar': null,
      'motif': null,
      'valideLe': null,
      'validePar': null,
    };

/// `D.semenceObligations()` : les 19 obligations du calendrier confirmé, puis la fiche des paramètres ORTB.
List<CfaFiche> cfbSemenceObligations() => [for (final o in cfbCalendrierFiscal) cfbFicheDepuisObligation(o), cfbSemenceOrtbParametres()];

bool _estObligation(CfaFiche f) => f['type'] != 'parametres' && _actif(f);

/// `D.obligationsALaDate(date)` : une fiche par code, la version en vigueur à la date (courante si sa date d'effet est nulle ou passée, sinon
/// celle de l'historique qui couvre la date). Un code sans version couvrante est ABSENT (créée plus tard, ou retirée avant). Magasin vide : la
/// semence. L'ordre est celui de la première apparition du code (fiches courantes, puis historique).
List<CfaFiche> cfbObligationsALaDate(Iterable<CfaFiche> obligations, Iterable<CfaFiche> historique, DateTime date) {
  final actives = obligations.where(_estObligation).toList();
  final hist = historique.where(_estObligation).toList();
  if (actives.isEmpty && hist.isEmpty) return [for (final f in cfbSemenceObligations()) if (f['type'] == 'obligation') f];
  final d = isoJour(date);
  final codes = <String>[];
  for (final o in [...actives, ...hist]) {
    final c = '${o['code'] ?? ''}';
    if (c.isNotEmpty && !codes.contains(c)) codes.add(c);
  }
  final out = <CfaFiche>[];
  for (final code in codes) {
    final courante = actives.where((o) => o['code'] == code).firstOrNull;
    final v = versionEnVigueur(courante, hist.where((h) => h['code'] == code), d);
    if (v != null) out.add(v);
  }
  return out;
}

/// `D.ortbALaDate(date)` : la fiche `ORTB-PARAMETRES` en vigueur (courante ou copie d'historique) ; sans fiche, la semence.
CfaFiche cfbOrtbALaDate(Iterable<CfaFiche> obligations, Iterable<CfaFiche> historique, DateTime date) =>
    paiFicheOrtbALaDate(obligations, historique, isoJour(date)) ?? cfbSemenceOrtbParametres();

/// `versionsObligation(code)` : les versions antérieures d'un code, par date d'effet croissante.
List<CfaFiche> cfbVersionsObligation(Iterable<CfaFiche> historique, String code) =>
    [for (final h in historique) if (_actif(h) && h['code'] == code) h]..sort((a, b) => isoJour(a['dateEffet']).compareTo(isoJour(b['dateEffet'])));

/// Les contrôles des valeurs d'une obligation : intitulé, périodicité, jour 1 à 31, mois 0 à 11 pour une annuelle, part 1 à 100 ou vide.
CfbRefus? cfbControleValeursObligation(Map<String, Object?> v) {
  if (_vide(v['libelle'])) return const CfbRefus('LIBELLE_REQUIS', 'L’intitulé de l’obligation est obligatoire.', 'Nommer l’obligation comme la déclaration la nomme.');
  if (!const ['mensuelle', 'annuelle'].contains(v['periodicite'])) {
    return const CfbRefus('PERIODICITE_INVALIDE', 'La périodicité est mensuelle ou annuelle.', 'Choisir l’une des deux.');
  }
  final jour = nombreOuZero(v['jour']);
  if (!(jour >= 1 && jour <= 31 && jour == jour.floorToDouble())) {
    return const CfbRefus('JOUR_INVALIDE', 'Le jour de l’échéance est compris entre 1 et 31.', 'Saisir le jour du mois.');
  }
  if (v['periodicite'] == 'annuelle') {
    final m = v['mois'];
    final mois = nombreOuZero(m);
    if (m == null || m == '' || !(mois >= 0 && mois <= 11)) {
      return const CfbRefus('MOIS_INVALIDE', 'Une obligation annuelle porte son mois (janvier à décembre).', 'Choisir le mois de l’échéance.');
    }
  }
  if (v['part'] != null && v['part'] != '') {
    final part = nombreOuZero(v['part']);
    if (!(part >= 1 && part <= 100)) {
      return const CfbRefus('PART_INVALIDE', 'La part est un pourcentage entre 1 et 100, ou vide.', 'Saisir la fraction réglée à cette échéance.');
    }
  }
  return null;
}

/// Les valeurs d'une obligation, normalisées (`valeursObligation`) : le mois d'une mensuelle est nul, la part vide est nulle.
CfaFiche cfbValeursObligation(Map<String, Object?> v) {
  final annuelle = v['periodicite'] == 'annuelle';
  return {
    'libelle': '${v['libelle']}'.trim(),
    'periodicite': v['periodicite'],
    'jour': nombreOuZero(v['jour']).toInt(),
    'mois': annuelle ? nombreOuZero(v['mois']).toInt() : null,
    'part': v['part'] == null || v['part'] == '' ? null : nombreOuZero(v['part']).toInt(),
    'declaration': _vide(v['declaration']) ? null : '${v['declaration']}'.trim(),
    'note': _vide(v['note']) ? null : '${v['note']}'.trim(),
  };
}

/// La copie d'une fiche AVANT modification, telle qu'elle entre dans `historiqueObligations` : sans id ni statut ni champs techniques, avec
/// `obligationId`, `dateFin` (veille de la date d'effet), `remplaceeLe`, `remplaceePar`, `motifRemplacement`, `retiree`.
CfaFiche cfbCopieHistorique(CfaFiche fiche, String dateEffet, {required String motif, required bool retiree, required String acteur, required DateTime maintenant}) {
  final copie = {...fiche};
  for (final k in const ['id', 'statut', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', '_motifArchivage']) {
    copie.remove(k);
  }
  return {
    ...copie,
    'statut': 'actif',
    'obligationId': fiche['id'],
    'dateFin': veilleIso(dateEffet),
    'remplaceeLe': _horodatage(maintenant),
    'remplaceePar': acteur,
    'motifRemplacement': motif,
    'retiree': retiree,
  };
}

/// Ce qu'une écriture d'obligation rend : un refus, ou la fiche APRÈS, la copie à insérer à l'historique, et si la fiche s'archive (retrait).
class CfbEcritureObligation {
  const CfbEcritureObligation._({this.refus, this.id, this.code, this.dateEffet, this.fiche, this.historique, this.archiver = false, this.creation = false});
  const CfbEcritureObligation.refusee(CfbRefus refus) : this._(refus: refus);
  final CfbRefus? refus;
  bool get ok => refus == null;

  /// L'identifiant de la fiche écrite (`null` à la création : le magasin l'attribue), son code, la date d'effet ISO.
  final String? id, code, dateEffet;

  /// La fiche telle qu'elle doit être APRÈS (modification : la fiche entière mise à jour ; création : la fiche nouvelle ; retrait : la fiche
  /// archivée, `statut: 'archive'`).
  final CfaFiche? fiche;

  /// La version sortante, à insérer dans `historiqueObligations` (`null` à la création).
  final CfaFiche? historique;
  final bool archiver, creation;
}

CfaFiche? _obligationActive(Iterable<CfaFiche> obligations, {String? id, String? code}) {
  for (final o in obligations) {
    if (!_estObligation(o)) continue;
    if (id != null && '${o['id']}' == id) return o;
  }
  if (code != null) {
    for (final o in obligations) {
      if (_estObligation(o) && o['code'] == code) return o;
    }
  }
  return null;
}

const CfbRefus _obligationInconnue = CfbRefus('OBLIGATION_INCONNUE', 'Aucune obligation en vigueur ne porte cette référence.', 'Choisir une obligation du tableau.');

/// `modifierObligation` : la version sortante va à l'historique, la fiche reçoit les valeurs, sa date d'effet, son motif, et PERD sa validation.
/// Ordre des refus (celui de la maquette) : fileul, obligation inconnue, motif, date d'effet (exercice clos, antérieure), valeurs.
CfbEcritureObligation cfbModifierObligation(Iterable<CfaFiche> obligations,
    {String? id,
    String? code,
    Map<String, Object?> valeurs = const {},
    Object? dateEffet,
    String? motif,
    required String acteur,
    required DateTime maintenant,
    required DateTime aujourdhui,
    Iterable<CfaFiche> exercices = const [],
    bool fileul = false}) {
  final f = cfbControleFileul(fileul);
  if (f != null) return CfbEcritureObligation.refusee(f);
  final fiche = _obligationActive(obligations, id: id, code: code);
  if (fiche == null) return const CfbEcritureObligation.refusee(_obligationInconnue);
  if (_vide(motif)) {
    return const CfbEcritureObligation.refusee(
        CfbRefus('MOTIF_REQUIS', 'Le motif de la modification est obligatoire.', 'Dire ce qui change et pourquoi (texte de loi, note de la DGI…).'));
  }
  final d = isoJour(dateEffet ?? aujourdhui);
  var r = cfbControleDateEffet(d, minimum: fiche['dateEffet'] == null ? null : isoJour(fiche['dateEffet']), exercices: exercices, aujourdhui: aujourdhui);
  if (r != null) return CfbEcritureObligation.refusee(r);
  final fusion = {...fiche, ...valeurs};
  r = cfbControleValeursObligation(fusion);
  if (r != null) return CfbEcritureObligation.refusee(r);
  final apres = cfbValeursObligation(fusion);
  final patch = {...apres, 'dateEffet': d, 'modifieLe': _horodatage(maintenant), 'modifiePar': acteur, 'motif': motif!.trim(), 'valideLe': null, 'validePar': null};
  return CfbEcritureObligation._(
      id: '${fiche['id']}',
      code: '${fiche['code']}',
      dateEffet: d,
      fiche: {...fiche, ...patch},
      historique: cfbCopieHistorique(fiche, d, motif: motif.trim(), retiree: false, acteur: acteur, maintenant: maintenant));
}

/// `creerObligation` : un code unique en majuscules (tous les codes connus, historique et archivées compris), une famille (préfixe), une date
/// d'effet hors exercice clos ; la fiche naît non validée.
CfbEcritureObligation cfbCreerObligation(Iterable<CfaFiche> obligations, Iterable<CfaFiche> historique,
    {required Map<String, Object?> valeurs,
    Object? dateEffet,
    String? motif,
    required String acteur,
    required DateTime maintenant,
    required DateTime aujourdhui,
    Iterable<CfaFiche> exercices = const [],
    bool fileul = false}) {
  final f = cfbControleFileul(fileul);
  if (f != null) return CfbEcritureObligation.refusee(f);
  final code = '${valeurs['code'] ?? ''}'.trim().toUpperCase();
  if (!RegExp(r'^[A-Z0-9][A-Z0-9-]*$').hasMatch(code)) {
    return const CfbEcritureObligation.refusee(CfbRefus('CODE_INVALIDE', 'Le code est en majuscules, chiffres et traits d’union (ex. : TPS-1).',
        'Choisir un code court et stable : il identifie l’obligation au journal.'));
  }
  if ([...obligations, ...historique].any((x) => x['code'] == code)) {
    return CfbEcritureObligation.refusee(CfbRefus('CODE_EXISTANT', 'Le code $code existe déjà.', 'Modifier l’obligation existante, ou choisir un autre code.'));
  }
  if (_vide(motif)) {
    return const CfbEcritureObligation.refusee(CfbRefus('MOTIF_REQUIS', 'Le motif de la création est obligatoire.', 'Citer le texte qui institue l’obligation.'));
  }
  final d = isoJour(dateEffet ?? aujourdhui);
  var r = cfbControleDateEffet(d, exercices: exercices, aujourdhui: aujourdhui);
  if (r != null) return CfbEcritureObligation.refusee(r);
  r = cfbControleValeursObligation(valeurs);
  if (r != null) return CfbEcritureObligation.refusee(r);
  return CfbEcritureObligation._(code: code, dateEffet: d, creation: true, fiche: {
    'statut': 'actif',
    'type': 'obligation',
    'code': code,
    'famille': code.split('-').first,
    ...cfbValeursObligation(valeurs),
    'source': 'Saisie à l’écran (cfg-comptabilite)',
    'dateEffet': d,
    'modifieLe': _horodatage(maintenant),
    'modifiePar': acteur,
    'motif': motif!.trim(),
    'valideLe': null,
    'validePar': null,
  });
}

/// `retirerObligation` : réservé au droit `annuler` de CFG (`RETRAIT_RESERVE` : la Direction édite et valide, ne retire pas) ; la dernière version
/// va à l'historique marquée `retiree`, la fiche s'archive (RG-14) ; les échéances payées restent.
CfbEcritureObligation cfbRetirerObligation(Iterable<CfaFiche> obligations,
    {String? id,
    String? code,
    Object? dateEffet,
    String? motif,
    required String acteur,
    required DateTime maintenant,
    required DateTime aujourdhui,
    Iterable<CfaFiche> exercices = const [],
    bool fileul = false,
    bool droitAnnuler = true,
    String? libelleRole}) {
  final f = cfbControleFileul(fileul);
  if (f != null) return CfbEcritureObligation.refusee(f);
  if (!droitAnnuler) {
    return CfbEcritureObligation.refusee(CfbRefus('RETRAIT_RESERVE',
        'Le retrait d’une obligation appartient à la DAF ou à l’administrateur système. Profil : ${libelleRole ?? 'aucun'}.', 'Demander à la DAF de retirer l’obligation.'));
  }
  final fiche = _obligationActive(obligations, id: id, code: code);
  if (fiche == null) return const CfbEcritureObligation.refusee(_obligationInconnue);
  if (_vide(motif)) {
    return const CfbEcritureObligation.refusee(CfbRefus('MOTIF_REQUIS', 'Le motif du retrait est obligatoire.', 'Citer le texte qui supprime l’obligation.'));
  }
  final d = isoJour(dateEffet ?? aujourdhui);
  final r = cfbControleDateEffet(d, minimum: fiche['dateEffet'] == null ? null : isoJour(fiche['dateEffet']), exercices: exercices, aujourdhui: aujourdhui);
  if (r != null) return CfbEcritureObligation.refusee(r);
  return CfbEcritureObligation._(
      id: '${fiche['id']}',
      code: '${fiche['code']}',
      dateEffet: d,
      archiver: true,
      fiche: {...fiche, 'statut': 'archive', '_archiveLe': _horodatage(maintenant), '_archivePar': acteur, '_motifArchivage': motif!.trim()},
      historique: cfbCopieHistorique(fiche, d, motif: motif.trim(), retiree: true, acteur: acteur, maintenant: maintenant));
}

/// `String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')` : les milliers séparés par une espace ORDINAIRE, comme l'assiette de la maquette.
String cfbEspaceMilliers(num n) {
  final s = arrondiJs(n.toDouble()).toInt().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    b.write(s[i]);
    final reste = s.length - i - 1;
    if (reste > 0 && reste % 3 == 0) b.write(' ');
  }
  return b.toString();
}

/// `modifierOrtb` : le seuil télé (la télé reçoit `seuilMin = seuil + 1` et son assiette réécrite), les montants et mois des deux redevances
/// (`valeurs['radio']`, `valeurs['tele']` : `{montant, mois}`), le cumul recalculé ; la version sortante va à l'historique.
CfbEcritureObligation cfbModifierOrtb(Iterable<CfaFiche> obligations,
    {Map<String, Object?> valeurs = const {},
    Object? dateEffet,
    String? motif,
    required String acteur,
    required DateTime maintenant,
    required DateTime aujourdhui,
    Iterable<CfaFiche> exercices = const [],
    bool fileul = false}) {
  final f = cfbControleFileul(fileul);
  if (f != null) return CfbEcritureObligation.refusee(f);
  final fiche = obligations.where((o) => _actif(o) && o['type'] == 'parametres' && o['code'] == paiCodeParametresOrtb).firstOrNull;
  if (fiche == null) {
    return const CfbEcritureObligation.refusee(
        CfbRefus('ORTB_ABSENT', 'La fiche des paramètres ORTB est absente du magasin.', 'Réinitialiser le jeu de démonstration (Paramètres système).'));
  }
  if (_vide(motif)) {
    return const CfbEcritureObligation.refusee(
        CfbRefus('MOTIF_REQUIS', 'Le motif de la modification est obligatoire.', 'Citer la décision ou le texte qui fixe le nouveau seuil.'));
  }
  final d = isoJour(dateEffet ?? aujourdhui);
  final r = cfbControleDateEffet(d, minimum: fiche['dateEffet'] == null ? null : isoJour(fiche['dateEffet']), exercices: exercices, aujourdhui: aujourdhui);
  if (r != null) return CfbEcritureObligation.refusee(r);
  final seuil = valeurs.containsKey('seuilTele') && valeurs['seuilTele'] != null && valeurs['seuilTele'] != '' ? nombreOuZero(valeurs['seuilTele']) : nombreOuZero(fiche['seuilTele']);
  if (!(seuil >= 0)) {
    return const CfbEcritureObligation.refusee(
        CfbRefus('SEUIL_INVALIDE', 'Le seuil de la redevance Télé est un montant positif ou nul.', 'Saisir le salaire brut au-delà duquel la télé est due.'));
  }
  final brut = fiche['redevances'];
  final redevances = [for (final x in (brut is List ? brut : const []).whereType<Map>()) <String, Object?>{...x.cast<String, Object?>()}];
  CfbRefus? invalide;
  for (final idRed in const ['radio', 'tele']) {
    final saisie = valeurs[idRed] is Map ? (valeurs[idRed] as Map).cast<String, Object?>() : const <String, Object?>{};
    final red = redevances.where((x) => x['id'] == idRed).firstOrNull;
    if (red == null) continue;
    if (saisie['montant'] != null && saisie['montant'] != '') red['montant'] = nombreOuZero(saisie['montant']);
    if (saisie['mois'] != null && saisie['mois'] != '') {
      red['mois'] = nombreOuZero(saisie['mois']).toInt();
      final m = red['mois'] as int;
      red['moisLabel'] = m >= 0 && m < paiMois.length ? paiMois[m] : null;
    }
    final montant = nombreOuZero(red['montant']);
    final mois = nombreOuZero(red['mois']);
    if (!(montant >= 0)) {
      invalide = CfbRefus('MONTANT_INVALIDE', 'Le montant de la redevance ${red['categorie']} est un montant positif ou nul.', 'Saisir le montant annuel par agent.');
    } else if (!(mois >= 0 && mois <= 11)) {
      invalide = CfbRefus('MOIS_INVALIDE', 'Le mois de prélèvement de la redevance ${red['categorie']} va de janvier à décembre.', 'Choisir le mois du bulletin qui porte la retenue.');
    }
    if (idRed == 'tele') {
      red['seuilMin'] = seuil + 1;
      red['assiette'] = 'Salaire brut supérieur à ${cfbEspaceMilliers(seuil)} FCFA';
    }
  }
  if (invalide != null) return CfbEcritureObligation.refusee(invalide);
  final cumul = redevances.fold<num>(0, (n, x) => n + nombreOuZero(x['montant']));
  final patch = {
    'seuilTele': seuil,
    'redevances': redevances,
    'cumulMaximum': cumul,
    'dateEffet': d,
    'modifieLe': _horodatage(maintenant),
    'modifiePar': acteur,
    'motif': motif!.trim(),
    'valideLe': null,
    'validePar': null,
  };
  return CfbEcritureObligation._(
      id: '${fiche['id']}',
      code: paiCodeParametresOrtb,
      dateEffet: d,
      fiche: {...fiche, ...patch},
      historique: cfbCopieHistorique(fiche, d, motif: motif.trim(), retiree: false, acteur: acteur, maintenant: maintenant));
}

// =============================================================================================================================================
// Échéances d'un exercice : engendrées depuis la version en vigueur, régénérées sans toucher une échéance payée
// =============================================================================================================================================

/// La date du jeu de démonstration (`new Date(2026, 7, 16)`), horloge par défaut de `genEcheances`.
final DateTime cfbDateJeu = DateTime(2026, 8, 16);

DateTime _jourOuvrableSuivant(DateTime d) {
  var x = d;
  while (x.weekday == DateTime.saturday || x.weekday == DateTime.sunday) {
    x = DateTime(x.year, x.month, x.day + 1);
  }
  return x;
}

/// `S.genEcheances(exercice, opts)` : pour CHAQUE mois de l'exercice, la version de chaque obligation EN VIGUEUR AU PREMIER DU MOIS fixe
/// l'échéance du mois ; une version qui change en cours d'exercice ne touche que les échéances postérieures à sa date d'effet. Chaque échéance
/// porte `echeanceTheorique`, `reportee` (jour ouvrable suivant) et `versionObligation` (la date d'effet de la version qui l'a engendrée, `null`
/// pour la version d'origine). [obligationsFixes] impose la liste (le semis la passe) ; sinon la version en vigueur se lit dans [obligations] et
/// [historique]. [aujourdhui] décide ce qui est réputé réglé (passée de plus de 25 jours) ; [sansReglement] n'invente aucune quittance.
/// Quirk conservé : une annuelle s'inscrit au `min(jour, 28)` (le 30 avril s'inscrit au 28), comme avant le chantier.
List<CfaFiche> cfbGenEcheances(int exercice,
    {Iterable<CfaFiche> obligations = const [],
    Iterable<CfaFiche> historique = const [],
    Iterable<CfaFiche>? obligationsFixes,
    DateTime? aujourdhui,
    bool sansReglement = false}) {
  final auj = aujourdhui ?? cfbDateJeu;
  final auj0 = DateTime(auj.year, auj.month, auj.day);
  List<CfaFiche> pour(DateTime premier) =>
      obligationsFixes != null ? [for (final o in obligationsFixes) if (_estObligation(o)) o] : cfbObligationsALaDate(obligations, historique, premier);
  final parCode = <String, List<(CfaFiche, DateTime)>>{};
  final ordre = <String>[];
  for (var m = 0; m < 12; m++) {
    for (final o in pour(DateTime(exercice, m + 1, 1))) {
      DateTime? d;
      final jour = nombreOuZero(o['jour']).toInt();
      if (o['periodicite'] == 'mensuelle') {
        d = DateTime(exercice, m + 1, jour);
      } else if (o['mois'] != null && nombreOuZero(o['mois']).toInt() == m) {
        d = DateTime(exercice, m + 1, jour < 28 ? jour : 28);
      }
      if (d == null) continue;
      final code = '${o['code']}';
      if (!parCode.containsKey(code)) {
        parCode[code] = [];
        ordre.add(code);
      }
      parCode[code]!.add((o, d));
    }
  }
  final out = <CfaFiche>[];
  var n = 0;
  for (final code in ordre) {
    for (final (o, d) in parCode[code]!) {
      n++;
      final echue = _jourOuvrableSuivant(d);
      final passee = echue.isBefore(auj0);
      final jours = arrondiJs(auj0.difference(echue).inMilliseconds / 86400000).toInt();
      final paye = !sansReglement && passee && jours > 25;
      final mensuelle = o['periodicite'] == 'mensuelle';
      out.add({
        'id': 'ECH${n.toString().padLeft(4, '0')}',
        'statut': 'actif',
        'code': code,
        'libelle': o['libelle'],
        'famille': o['famille'],
        'periodicite': o['periodicite'],
        'part': o['part'],
        'declaration': o['declaration'],
        'note': o['note'],
        'exercice': exercice,
        'periode': mensuelle ? '${paiMois[(d.month - 2) < 0 ? 0 : d.month - 2]} $exercice' : '$exercice',
        'echeance': isoJour(echue),
        'echeanceTheorique': isoJour(d),
        'reportee': isoJour(echue) != isoJour(d),
        'versionObligation': o['dateEffet'] == null ? null : isoJour(o['dateEffet']),
        'paye': paye,
        'datePaiement': paye ? isoJour(echue) : null,
        'montant': null,
        'reference': paye ? 'QUIT-$code-$exercice' : null,
        'valideePar': paye ? 'KASSA Augustin' : null,
      });
    }
  }
  return out;
}

/// UNE ÉCHÉANCE PAYÉE NE BOUGE JAMAIS : sa quittance ne se réécrit pas. Le refus nommé que la régénération et l'écran consultent avant de
/// toucher une échéance ; `null` si l'échéance est encore due.
CfbRefus? cfbRefusEcheancePayee(CfaFiche e) => e['paye'] == true
    ? CfbRefus('ECHEANCE_PAYEE', 'L’échéance ${e['code']} du ${_dateFrIso('${e['echeance']}')} est payée${_vide(e['reference']) ? '' : ' (quittance ${e['reference']})'} : elle ne se régénère pas.',
        'Une quittance ne se réécrit jamais ; une erreur de paiement se corrige par l’annulation du règlement, puis une nouvelle validation.')
    : null;

/// `echeancesImpactees(code, dateEffet)` : ce que la modale de portée annonce avant d'écrire : les échéances du code, à partir de la date
/// d'effet et de son exercice, payées (CONSERVÉES) et non payées (RÉGÉNÉRÉES).
({int payees, int nonPayees, int exercice}) cfbEcheancesImpactees(Iterable<CfaFiche> echeances, String code, Object dateEffet) {
  final d = isoJour(dateEffet);
  final ex = int.parse(d.substring(0, 4));
  final rows = [
    for (final e in echeances)
      if (_actif(e) && e['code'] == code && nombreOuZero(e['exercice']).toInt() >= ex && isoJour(e['echeanceTheorique'] ?? e['echeance']).compareTo(d) >= 0) e
  ];
  return (payees: rows.where((e) => cfbRefusEcheancePayee(e) != null).length, nonPayees: rows.where((e) => cfbRefusEcheancePayee(e) == null).length, exercice: ex);
}

/// Le texte de la modale de portée : « N échéance(s) payée(s) CONSERVÉE(S), M échéance(s) non payée(s) RÉGÉNÉRÉE(S) ».
String cfbAnnoncePortee(({int payees, int nonPayees, int exercice}) i) =>
    'Exercice ${i.exercice} : ${nombre(i.payees)} échéance(s) payée(s) CONSERVÉE(S), ${nombre(i.nonPayees)} échéance(s) non payée(s) RÉGÉNÉRÉE(S).';

/// Le résultat d'une régénération : les comptes, les deux listes de dates (pour le journal) et la liste COMPLÈTE des échéances après le geste.
class CfbRegeneration {
  const CfbRegeneration(
      {required this.code,
      required this.dateEffet,
      required this.conservees,
      required this.anterieures,
      required this.archivees,
      required this.creees,
      required this.avant,
      required this.apres,
      required this.echeances,
      required this.archiveesIds,
      required this.creeesFiches});
  final String code, dateEffet;
  final int conservees, anterieures, archivees, creees;

  /// Les dates des échéances archivées et des échéances créées (ce que le journal porte).
  final List<String> avant, apres;

  /// Toutes les échéances après le geste (les archivées marquées, les créées en tête, comme le magasin de la maquette).
  final List<CfaFiche> echeances;
  final List<String> archiveesIds;
  final List<CfaFiche> creeesFiches;

  Map<String, Object?> get comptes => {'code': code, 'dateEffet': dateEffet, 'conservees': conservees, 'anterieures': anterieures, 'archivees': archivees, 'creees': creees};

  /// Le détail de la tâche de poste adressée au Comptable (`annoncerRegeneration`).
  String get detail => '${nombre(conservees)} payée(s) conservée(s), ${nombre(archivees)} non payée(s) régénérée(s) à partir du ${_dateFrIso(dateEffet)}.';
  String get libelle => 'Échéances régénérées : $code, ${nombre(creees)}';
}

/// `S.regenererEcheances({code, dateEffet, auteur})` après une version datée : sur chaque exercice touché (à partir de celui de la date d'effet),
/// les échéances du code NON PAYÉES dont la date théorique est `>= dateEffet` sont ARCHIVÉES (RG-14) et recréées depuis la version en vigueur
/// ([obligations] et [historique] APRÈS la modification) ; les PAYÉES sont conservées ([cfbRefusEcheancePayee]) et le mois qu'elles couvrent n'est
/// pas recréé (il serait dû deux fois) ; les échéances antérieures à la date d'effet ne bougent pas, payées ou non. [identifiant] attribue
/// l'identifiant des échéances créées (`ECH` + uid dans la maquette).
CfbRegeneration cfbRegenererEcheances(Iterable<CfaFiche> echeances,
    {required String code,
    required Object dateEffet,
    required String auteur,
    required DateTime maintenant,
    required Iterable<CfaFiche> obligations,
    required Iterable<CfaFiche> historique,
    String Function(int rang)? identifiant}) {
  final d = isoJour(dateEffet);
  final quand = _horodatage(maintenant);
  final liste = [for (final e in echeances) <String, Object?>{...e}];
  final existantes = [for (final e in liste) if (e['code'] == code && _actif(e)) e];
  final anneeEffet = int.parse(d.substring(0, 4));
  final exercices = <int>{for (final e in existantes) nombreOuZero(e['exercice']).toInt(), anneeEffet}.where((a) => a >= anneeEffet).toList()..sort();
  var conservees = 0, anterieures = 0, archivees = 0, creees = 0, rang = 0;
  final avant = <String>[], apres = <String>[], archiveesIds = <String>[];
  final creeesFiches = <CfaFiche>[];
  for (final annee in exercices) {
    final moisConserves = <String>{};
    for (final e in existantes.where((e) => nombreOuZero(e['exercice']).toInt() == annee)) {
      final theorique = isoJour(e['echeanceTheorique'] ?? e['echeance']);
      if (theorique.compareTo(d) < 0) {
        anterieures++;
        continue;
      }
      if (cfbRefusEcheancePayee(e) != null) {
        conservees++;
        moisConserves.add(theorique.substring(0, 7));
        continue;
      }
      e['statut'] = 'archive';
      e['_archivePar'] = auteur;
      e['_archiveLe'] = quand;
      e['_motifArchivage'] = 'Régénérée : version de $code en vigueur au ${_dateFrIso(d)}';
      avant.add('${e['echeance']}');
      archiveesIds.add('${e['id']}');
      archivees++;
    }
    final nouvelles = cfbGenEcheances(annee, obligations: obligations, historique: historique, sansReglement: true).where((n) =>
        n['code'] == code && isoJour(n['echeanceTheorique']).compareTo(d) >= 0 && !moisConserves.contains(isoJour(n['echeanceTheorique']).substring(0, 7)));
    for (final n in nouvelles) {
      rang++;
      final f = <String, Object?>{
        ...n,
        'id': identifiant != null ? identifiant(rang) : 'ECH-${d.replaceAll('-', '')}-$code-${rang.toString().padLeft(3, '0')}',
        'versionObligation': d,
        'regenereeLe': quand,
        'regenereePar': auteur,
        '_creePar': auteur,
        '_creeLe': quand,
      };
      liste.insert(0, f);
      creeesFiches.add(f);
      apres.add('${f['echeance']}');
      creees++;
    }
  }
  return CfbRegeneration(
      code: code,
      dateEffet: d,
      conservees: conservees,
      anterieures: anterieures,
      archivees: archivees,
      creees: creees,
      avant: avant,
      apres: apres,
      echeances: liste,
      archiveesIds: archiveesIds,
      creeesFiches: creeesFiches);
}
