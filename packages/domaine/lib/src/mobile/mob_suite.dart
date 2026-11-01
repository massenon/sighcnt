/// MOBILE, SUITE : visite prénatale (CPN), visite post-natale (CPoN), surveillance mère-bébé, orientation de la réception, réglages, lot de tournée.
///
/// Sources, une par règle, aucune devinée : les pages `prototype_html/mobile/ecrans/{cpn,cpon,surveillance,orientation,parametres,lot}.php` PILOTÉES dans
/// Chrome (`prototype_html/build/vecteurs-mobile-suite.js` : `test/vecteurs/mobile_suite.json`, `mob_suite_donnees.dart`). Les bornes et messages passent par
/// `mobValider` (le `valider` du simulateur), l'âge à risque CPN par la fenêtre du rapport de maternité (`AGES_RISQUE_CPN`), la lecture du dossier par
/// `mobDossier` : rien n'est recopié.
///
/// Un refus est NOMMÉ (code, motif, geste). Une commande interdite est ABSENTE : `mobEcranOuvertAuProfil` sert à ne pas la dessiner, `mobControlerEcran`
/// refait le contrôle au moteur. Chaque geste est UNE ligne de journal (famille B) : jamais une modification, jamais une suppression (RG-14), toujours
/// un acteur nommé (RG-12).
library;

import '../consultation/ag_commun.dart' show agIsoLocal;
import '../format/format_fr.dart' show dateFR, heure;
import '../maternite/mat_regles.dart' show matCarte;
import 'mob_regles.dart';
import 'mob_suite_donnees.dart';

/// Les collections où la suite du mobile écrit (journaux, famille B de la mère). `cpn`, `cpon` et `surveillances` sont celles du profil clinique,
/// `orientations` celle de la réception de secours.
const mobCollectionCpn = 'cpn';
const mobCollectionCpon = 'cpon';
const mobCollectionSurveillance = 'surveillances';
const mobCollectionOrientation = 'orientations';

Map<String, Object?> _m(Object? o) => (o as Map).cast<String, Object?>();
List<Object?> _l(Object? o) => (o as List).cast<Object?>();
Map<String, Object?> get _donnees => mobSuiteDonnees;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les champs d'un écran, tels que la page les rend
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un champ de la page du simulateur : libellé, obligatoire, type de contrôle, clavier, exemple, choix, carte qui le porte (`section`, `null` hors carte).
class MobChamp {
  const MobChamp({required this.id, required this.libelle, required this.requis, required this.type, this.saisie, this.clavier, this.placeholder, this.options, this.section});
  final String id, libelle, type;
  final bool requis;

  /// Le type du `<input>` (`text`, `date`, `tel`…), `null` pour une liste ou une zone de texte.
  final String? saisie;
  final String? clavier, placeholder, section;
  final List<String>? options;

  bool get liste => type == 'select';
  bool get date => saisie == 'date';
  bool get decimal => clavier == 'decimal';
  bool get numerique => clavier == 'numeric' || clavier == 'decimal';
}

MobChamp _champ(Map<String, Object?> c) => MobChamp(
      id: '${c['id']}',
      libelle: '${c['libelle']}',
      requis: c['requis'] == true,
      type: '${c['type']}',
      saisie: c['saisie'] as String?,
      clavier: c['clavier'] as String?,
      placeholder: c['placeholder'] as String?,
      options: c['options'] == null ? null : [for (final o in _l(c['options'])) '$o'],
      section: c['section'] as String?,
    );

/// Les champs d'un écran (`cpn`, `cpon`, `surveillance`, `orientation`), dans l'ordre de la page.
List<MobChamp> mobChampsEcran(String ecran) => [for (final c in _l(_m(_donnees[ecran])['champs'])) _champ(_m(c))];

/// Les cartes d'un écran, dans l'ordre (les titres `h2` de la page).
List<String> mobCartesEcran(String ecran) => [for (final c in _l(_m(_donnees[ecran])['cartes'] ?? const <Object?>[])) '$c'];

/// Le libellé de la commande d'enregistrement (« Enregistrer la visite », « Enregistrer », « Enregistrer ce temps », « Envoyer l’orientation »).
String mobBoutonEcran(String ecran) => '${_m(_donnees[ecran])['bouton']}';

String mobTitreEcranSuite(String ecran) => '${_m(_donnees[ecran])['titre']}';

/// La note posée en tête de l'écran, s'il y en a une (la surveillance : « Une seule grille de temps pour la mère ET le bébé… »).
String? mobNoteEcranSuite(String ecran) => _m(_donnees[ecran])['note'] as String?;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Droits : le profil du simulateur ouvre ou ferme l'écran
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le profil du simulateur d'un téléphone : la réception de secours, ou la fonction du soignant (`mobProfilSimulateur`).
String mobProfilDe({required bool reception, String fonction = ''}) => reception ? 'reception' : mobProfilSimulateur(fonction);

/// Les écrans que le simulateur ouvre à ce profil (`soignant`, `medecin`, `sagefemme`, `reception`).
List<String> mobEcransDuProfil(String profil) => [for (final e in _l(_m(_donnees['ecransProfils'])[profil])) '$e'];

bool mobEcranOuvertAuProfil(String profil, String ecran) => mobEcransDuProfil(profil).contains(ecran);

String mobLibelleProfil(String profil) => '${_m(_m(_donnees['profils'])[profil])['label']}';

/// Le profil du simulateur qui accueille le lot (écran « Lot de tournée » : les profils cliniques seulement).
String mobAccueilDuProfil(String profil) => '${_m(_m(_donnees['profils'])[profil])['accueil']}';

/// Le refus d'un écran fermé : il se NOMME, il ne s'ouvre pas à moitié. Le motif est celui de la page.
RefusMobile mobRefusEcranFerme(String profil, String ecran) => RefusMobile(
    'ECRAN_FERME_AU_PROFIL',
    'Écran fermé au profil « ${mobLibelleProfil(profil)} ». Ce profil ne couvre pas cette fonction ; la clinique le refuserait aussi côté serveur.',
    'Retour à l’accueil');

/// Le contrôle REFAIT au moteur : un bouton absent ne protège rien.
void mobControlerEcran(String profil, String ecran) {
  if (!mobEcranOuvertAuProfil(profil, ecran)) throw mobRefusEcranFerme(profil, ecran);
}

/// Aucune action anonyme (RG-12) : sans agent nommé sur ce téléphone, rien ne s'écrit.
void mobControlerActeur(String agent) {
  if (agent.trim().isEmpty) {
    throw const RefusMobile('ACTEUR_INCONNU', 'Aucune action anonyme : le nom de l’agent n’est pas renseigné sur ce téléphone (RG-12).', 'Réappairer le téléphone en indiquant l’agent');
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Saisie commune
// ---------------------------------------------------------------------------------------------------------------------------------------------

RefusMobile _refusSaisie(Map<String, String> erreurs) =>
    RefusMobile('SAISIE_INVALIDE', erreurs.values.first, 'Corriger le champ indiqué', champs: erreurs);

/// Une valeur lue comme `S.valeur(id)` : rognée ; une LISTE sans valeur prend sa première entrée, comme le `<select>` natif.
String _val(String ecran, Map<String, String> saisie, String id) {
  final v = (saisie[id] ?? '').trim();
  if (v.isNotEmpty) return v;
  final c = mobChampsEcran(ecran).where((x) => x.id == id).firstOrNull;
  return (c != null && c.liste) ? c.options!.first : '';
}

/// Chaque liste n'accepte que ses choix (le simulateur ne propose rien d'autre) : une valeur étrangère est refusée en la nommant.
Map<String, String> _choixInconnus(String ecran, Map<String, String> saisie) {
  final e = <String, String>{};
  for (final c in mobChampsEcran(ecran)) {
    if (!c.liste) continue;
    final v = (saisie[c.id] ?? '').trim();
    if (v.isNotEmpty && !c.options!.contains(v)) e[c.id] = '${c.libelle} : « $v » n’est pas dans la liste.';
  }
  return e;
}

String _nombreSaisi(String v) => v.trim();

// ---------------------------------------------------------------------------------------------------------------------------------------------
// CPN
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les bornes de la page : terme 4 à 45 SA, poids 30 à 200 kg, TA systolique 60 à 260, diastolique 30 à 160, BCF 60 à 220. La hauteur utérine n'a pas
/// de borne à la page (voir [mobErreursCpn] : elle doit au moins être un nombre).
const mobReglesCpn = [
  MobRegle('sa', 'Le terme', requis: true, min: 4, max: 45),
  MobRegle('poids', 'Le poids', requis: true, min: 30, max: 200),
  MobRegle('sys', 'La systolique', requis: true, min: 60, max: 260),
  MobRegle('dia', 'La diastolique', requis: true, min: 30, max: 160),
  MobRegle('bcf', 'Le BCF', min: 60, max: 220),
];

/// Les erreurs d'une visite prénatale. ÉCART porté et signalé (E1650) : le simulateur accepte une hauteur utérine « texte » ; on refuse ce qui n'est
/// pas un nombre, avec le message de `valider` (« doit être un nombre »), plutôt que d'écrire du texte dans une mesure.
Map<String, String> mobErreursCpn(Map<String, String> saisie) {
  final e = mobValider(mobReglesCpn, saisie);
  final hu = (saisie['hu'] ?? '').trim();
  if (hu.isNotEmpty && mobNombreJs(hu) == null) e['hu'] = 'La hauteur utérine doit être un nombre.';
  e.addAll({for (final x in _choixInconnus('cpn', saisie).entries) x.key: x.value});
  return e;
}

/// La fenêtre d'âge du rapport de maternité : hors de 18 à 35 ans, la grossesse est à évaluer. Le simulateur teste l'âge entier du dossier.
bool mobCpnAgeARisque(int? age) {
  if (age == null) return false;
  final b = matCarte('AGES_RISQUE_CPN');
  return age < (b['min'] as num) || age > (b['max'] as num);
}

/// La note de l'écran : « Âge à risque (hors 18–35 ans). », ou rien.
String? mobCpnNoteAge(int? age) {
  if (!mobCpnAgeARisque(age)) return null;
  final b = matCarte('AGES_RISQUE_CPN');
  return 'Âge à risque (hors ${b['min']}–${b['max']} ans).';
}

/// Texte du toast d'alerte : posé AVANT celui de l'enregistrement.
String get mobCpnToastAlerte => '${_m(_donnees['cpn'])['alerte']}';

/// Les deux toasts d'enregistrement de la page : connecté (« envoi en cours »), hors ligne (« part dès que le réseau revient »).
String get mobToastEnregistreEnLigne => '${_m(_donnees['toasts'])['enLigne']}';
String get mobToastEnregistreHorsLigne => '${_m(_donnees['toasts'])['horsLigne']}';

/// TA élevée (systolique ≥ 140 ou diastolique ≥ 90) ou protéinurie « ++ » / « +++ » : la grossesse est signalée à risque.
bool mobCpnAlerte(Map<String, String> saisie) {
  final sys = mobNombreJs((saisie['sys'] ?? '').trim()), dia = mobNombreJs((saisie['dia'] ?? '').trim());
  final prot = _val('cpn', saisie, 'proteinurie');
  return (sys != null && sys >= 140) || (dia != null && dia >= 90) || prot == '++' || prot == '+++';
}

/// Libellé et détail de l'opération tels que le simulateur les met en file.
({String libelle, String detail}) mobCpnResume(String nomPatient, Map<String, String> saisie) => (
      libelle: 'CPN — $nomPatient',
      detail: '${_nombreSaisi(saisie['sa'] ?? '')} SA · TA ${_nombreSaisi(saisie['sys'] ?? '')}/${_nombreSaisi(saisie['dia'] ?? '')}${mobCpnAlerte(saisie) ? ' · À RISQUE' : ''}',
    );

/// La ligne de journal d'une visite prénatale (collection `cpn`). Le simulateur n'en garde que le résumé ; la ligne garde TOUTES les mesures saisies
/// (E1651) : la mère les range avec les siennes, le poste les transcrira au dossier obstétrical.
Map<String, Object?> mobChampsCpn({
  required MobFiche patient,
  required String patientId,
  required Map<String, String> saisie,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
}) {
  final erreurs = mobErreursCpn(saisie);
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  num? n(String k) {
    final v = (saisie[k] ?? '').trim();
    return v.isEmpty ? null : mobNombreJs(v);
  }

  final r = mobCpnResume(mobNomPatient(patient), saisie);
  final rdv = (saisie['rdv'] ?? '').trim();
  return {
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'termeSA': n('sa'),
    'poids': n('poids'),
    'tensionSys': n('sys'),
    'tensionDia': n('dia'),
    'tension': '${_nombreSaisi(saisie['sys']!)}/${_nombreSaisi(saisie['dia']!)}',
    if (n('hu') != null) 'hauteurUterine': n('hu'),
    if (n('bcf') != null) 'bcf': n('bcf'),
    'presentation': _val('cpn', saisie, 'presentation'),
    'sp': _val('cpn', saisie, 'sp'),
    'milda': _val('cpn', saisie, 'milda'),
    'proteinurie': _val('cpn', saisie, 'proteinurie'),
    if (rdv.isNotEmpty) 'prochainRdv': rdv,
    'aRisque': mobCpnAlerte(saisie),
    'libelle': r.libelle,
    'detail': r.detail,
    'redigePar': acteur,
    'fonction': fonction,
    'origine': 'mobile',
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// CPoN
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les bornes de la page : la TA est obligatoire (texte libre, « 12/8 »), la température 34 à 43 °C, le poids du bébé 1000 à 6000 g.
const mobReglesCpon = [
  MobRegle('ta', 'La TA', requis: true),
  MobRegle('t', 'La température', requis: true, min: 34, max: 43),
  MobRegle('pb', 'Le poids du bébé', requis: true, min: 1000, max: 6000),
];

Map<String, String> mobErreursCpon(Map<String, String> saisie) => {...mobValider(mobReglesCpon, saisie), ..._choixInconnus('cpon', saisie)};

({String libelle, String detail}) mobCponResume(String nomPatient, Map<String, String> saisie) => (
      libelle: 'CPoN ${_val('cpon', saisie, 'jour')} — $nomPatient',
      detail: 'T° ${_nombreSaisi(saisie['t'] ?? '')} · cordon ${_val('cpon', saisie, 'cordon').toLowerCase()}',
    );

/// La ligne de journal d'une visite post-natale (collection `cpon`), mère et nouveau-né.
Map<String, Object?> mobChampsCpon({
  required MobFiche patient,
  required String patientId,
  required Map<String, String> saisie,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
}) {
  final erreurs = mobErreursCpon(saisie);
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  final r = mobCponResume(mobNomPatient(patient), saisie);
  return {
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'jourPostNatal': _val('cpon', saisie, 'jour'),
    'tension': saisie['ta']!.trim(),
    'temperature': mobNombreJs(saisie['t']!.trim()),
    'lochies': _val('cpon', saisie, 'lochies'),
    'involutionUterine': _val('cpon', saisie, 'uterus'),
    'poidsNouveauNe': mobNombreJs(saisie['pb']!.trim()),
    'cordon': _val('cpon', saisie, 'cordon'),
    'allaitement': _val('cpon', saisie, 'allait'),
    'libelle': r.libelle,
    'detail': r.detail,
    'redigePar': acteur,
    'fonction': fonction,
    'origine': 'mobile',
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Surveillance mère-bébé
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le pouls de la mère 30 à 220, la FR du bébé 10 à 100, sa température 34 à 41 °C : aucun champ n'est obligatoire à la page.
const mobReglesSurveillance = [
  MobRegle('mpouls', 'Le pouls', min: 30, max: 220),
  MobRegle('bfr', 'La FR du bébé', min: 10, max: 100),
  MobRegle('bt', 'La T° du bébé', min: 34, max: 41),
];

Map<String, String> mobErreursSurveillance(Map<String, String> saisie) =>
    {...mobValider(mobReglesSurveillance, saisie), ..._choixInconnus('surveillance', saisie)};

({String libelle, String detail}) mobSurveillanceResume(Map<String, String> saisie) {
  String ou(String k) => (saisie[k] ?? '').trim().isEmpty ? '—' : saisie[k]!.trim();
  return (libelle: 'Surveillance ${_val('surveillance', saisie, 'heure')}', detail: 'mère ${ou('mta')} · bébé FR ${ou('bfr')}');
}

/// La ligne de journal d'un temps de la fiche de surveillance intégrée (collection `surveillances`). ÉCART signalé (E1652) : la page du simulateur ne
/// désigne aucun patient ; une surveillance sans dossier ne se rattache à rien, le geste part donc du dossier de la femme.
Map<String, Object?> mobChampsSurveillance({
  required MobFiche patient,
  required String patientId,
  required Map<String, String> saisie,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
}) {
  final erreurs = mobErreursSurveillance(saisie);
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  num? n(String k) {
    final v = (saisie[k] ?? '').trim();
    return v.isEmpty ? null : mobNombreJs(v);
  }

  String? t(String k) => (saisie[k] ?? '').trim().isEmpty ? null : saisie[k]!.trim();
  final r = mobSurveillanceResume(saisie);
  return {
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'temps': _val('surveillance', saisie, 'heure'),
    if (t('mta') != null) 'mereTension': t('mta'),
    if (n('mpouls') != null) 'merePouls': n('mpouls'),
    'mereSaignement': _val('surveillance', saisie, 'saign'),
    if (n('bfr') != null) 'bebeFr': n('bfr'),
    if (n('bt') != null) 'bebeTemperature': n('bt'),
    'bebeCordon': _val('surveillance', saisie, 'bcordon'),
    'libelle': r.libelle,
    'detail': r.detail,
    'redigePar': acteur,
    'fonction': fonction,
    'origine': 'mobile',
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Orientation (réception de secours)
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<String> get mobOrientationDestinations => mobChampsEcran('orientation').firstWhere((c) => c.id == 'dest').options!;
List<String> get mobOrientationDegres => mobChampsEcran('orientation').firstWhere((c) => c.id == 'urg').options!;

/// Le texte quand aucun dossier n'a été ouvert depuis ce téléphone : « Ouvrez d’abord un dossier. »
String get mobOrientationVide => '${_m(_donnees['orientation'])['vide']}';

/// Le choix de la liste « Patient », tel que la page l'écrit : « NOM Prénom — code ».
String mobOrientationChoix(MobFiche dossier) => '${mobNomPatient(dossier)} — ${dossier['code'] ?? 'en attente de numéro'}';

/// Orienter sans dossier ouvert est refusé en le disant (la page ne propose alors que ce texte).
void mobControlerOrientation(Iterable<MobFiche> dossiers) {
  if (dossiers.isEmpty) throw RefusMobile('SANS_DOSSIER', mobOrientationVide, 'Ouvrir un dossier à l’accueil de secours');
}

/// La ligne de journal d'une orientation (collection `orientations`). Destination et degré sont des listes fermées : une valeur étrangère est
/// refusée en la nommant. Libellé et détail : ceux de la page.
Map<String, Object?> mobChampsOrientation({
  required MobFiche dossier,
  required String dossierId,
  required String destination,
  required String degre,
  required String acteur,
  required DateTime maintenant,
}) {
  final erreurs = <String, String>{};
  final dest = destination.trim().isEmpty ? mobOrientationDestinations.first : destination.trim();
  final urg = degre.trim().isEmpty ? mobOrientationDegres.first : degre.trim();
  if (!mobOrientationDestinations.contains(dest)) erreurs['dest'] = 'Orienter vers : « $dest » n’est pas dans la liste.';
  if (!mobOrientationDegres.contains(urg)) erreurs['urg'] = 'Degré : « $urg » n’est pas dans la liste.';
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  return {
    'patientId': dossierId,
    'patientCode': dossier['code'],
    'patient': mobNomPatient(dossier),
    'date': agIsoLocal(maintenant),
    'destination': dest,
    'degre': urg,
    'libelle': 'Orientation — ${mobNomPatient(dossier)}',
    'detail': '$dest · $urg',
    'orientePar': acteur,
    'origine': 'reception_secours',
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Lot de tournée
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// L'état du lot : aucun reçu (ou purgé), valide, ou expiré (les dossiers vont s'effacer, sauf ce qui n'est pas parti).
enum MobEtatLot { aucun, valide, expire }

class MobLotVue {
  const MobLotVue({required this.etat, required this.heures, required this.dossiers, this.expireLe});
  final MobEtatLot etat;

  /// La validité restante en heures pleines, arrondie comme la page (`Math.round`), jamais négative.
  final int heures;
  final int dossiers;
  final DateTime? expireLe;

  /// « 10 h » : la valeur du compteur « Validité restante ».
  String get validite => '$heures h';

  /// « Expire le 31/10/2026 à 20h30 » ou « A expiré le … » (PROPOSITION : la page ne donne que les heures restantes, E1653).
  String? get texteExpiration {
    final d = expireLe;
    if (d == null) return null;
    return '${etat == MobEtatLot.expire ? 'A expiré' : 'Expire'} le ${dateFR(d)} à ${heure(d)}';
  }
}

/// Les heures restantes, comme `Math.round((expire - Date.now()) / 3600000)` borné à 0.
int mobLotHeuresRestantes(int? expire, DateTime maintenant) {
  if (expire == null || expire <= 0) return 0;
  final h = ((expire - maintenant.millisecondsSinceEpoch) / 3600000 + 0.5).floor();
  return h < 0 ? 0 : h;
}

MobLotVue mobLotVue({required int? expire, required int dossiers, required DateTime maintenant}) {
  final fin = (expire == null || expire <= 0) ? null : DateTime.fromMillisecondsSinceEpoch(expire);
  final etat = fin == null ? MobEtatLot.aucun : (maintenant.millisecondsSinceEpoch >= expire! ? MobEtatLot.expire : MobEtatLot.valide);
  return MobLotVue(etat: etat, heures: mobLotHeuresRestantes(expire, maintenant), dossiers: dossiers, expireLe: fin);
}

String get mobLotCarte => '${_l(_m(_donnees['lot'])['cartes']).first}';
List<String> get mobLotCompteurs => [for (final k in _l(_m(_donnees['lot'])['kpis'])) '$k'];
String get mobLotNote => '${_l(_m(_donnees['lot'])['notes']).first}';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Réglages
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le délai de verrouillage automatique : « après 5 minutes d’inactivité » (la ligne de la page des réglages).
Duration get mobDelaiVerrouInactivite {
  final detail = mobReglagesLignes.firstWhere((l) => l.titre == 'Verrouillage automatique').detail;
  final m = RegExp(r'(\d+)\s*minutes?').firstMatch(detail);
  return Duration(minutes: m == null ? 5 : int.parse(m.group(1)!));
}

typedef MobLigneReglage = ({String titre, String detail, String fin});

List<MobLigneReglage> get mobReglagesLignes => [
      for (final i in _l(_m(_donnees['reglages'])['items'])) (titre: '${_l(i)[0]}', detail: '${_l(i)[1]}', fin: '${_l(i)[2]}')
    ];

String get mobReglagesCarte => 'Ce téléphone';
String get mobReglagesBouton => '${_m(_donnees['reglages'])['bouton']}';
String get mobReglagesConfirmation => '${_m(_donnees['reglages'])['confirmation']}';

/// La carte « Ce téléphone ». La page donne un numéro d'appareil, une version et un schéma de DÉMONSTRATION ; la ligne réelle porte ce que le
/// téléphone sait (E1654).
({String profil, String agent, String appareil}) mobReglagesTelephone({required String profil, required String agent, String? appareil, required String version}) => (
      profil: mobLibelleProfil(profil),
      agent: agent,
      appareil: 'Appareil ${appareil ?? 'non communiqué'} · version $version',
    );

/// Réinitialiser l'appairage ne perd rien : tant qu'une saisie n'est pas partie, la page promet de l'EXPORTER avant l'effacement. Cet export n'est pas
/// branché (E1655) : le refus est NOMMÉ plutôt que de promettre ce qu'on ne tient pas.
void mobControlerReinitialisation(int enAttente) {
  if (enAttente > 0) {
    throw RefusMobile(
        'SAISIES_NON_ENVOYEES',
        '${enAttente == 1 ? 'Une saisie n’est' : '$enAttente saisies ne sont'} pas encore parti${enAttente == 1 ? 'e' : 'es'} : l’export avant effacement n’est pas branché sur ce téléphone, réinitialiser les perdrait.',
        'Synchroniser d’abord (écran Synchronisation), puis réinitialiser');
  }
}
