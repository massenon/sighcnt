// LES ENVOIS AUTOMATIQUES DE SMS (lot SMS-R, ADR-0008) : règles PURES, sans horloge, sans réseau, sans clé. La MÈRE calcule (agenda, dates de naissance, consentements), compose le texte,
// puis dépose au relais des messages DÉJÀ COMPOSÉS ; le relais les envoie par un cron. Le relais ne reçoit jamais l'annuaire, une date de naissance, un code patient ni un rendez-vous.
//
// Défauts VALIDÉS par la Direction (16/11/2026, section AQ, points 27 et 28) : rappel à 18 h la veille d'un rendez-vous, vœux d'anniversaire à 9 h (patients ET personnel), accord du
// personnel DÉCOCHÉ par défaut, modèles de message par défaut. Heures calmes de 21 h à 7 h (Direction, 07/11/2026). Tout est un PARAMÈTRE EN BASE (famille `sms`, versionné par date).
// Les valeurs marquées « à valider » ne sont fixées par aucun document : activation (désactivée par défaut), horizon de calcul, tolérance, 29 février.
//
// Un modèle n'a que cinq variables : {{nom}} {{date}} {{heure}} {{clinique}} {{telephone}}. Le médecin, le service et le motif n'ont AUCUNE variable : un rappel ne peut donc jamais les nommer.
// Le texte médical ne quitte jamais la clinique : un modèle qui contient un mot de la liste médicale (proposition à valider par un médecin nommé) est refusé à l'enregistrement.
library;

/// La famille de paramètres, réservée à la mère (jamais un téléphone) et réglée à son propre écran.
const String smsFamille = 'sms';

/// Le geste réservé de la fiche RBAC (défaut administrateur et DAF) : régler la passerelle, calculer et déposer maintenant, tester l'envoi.
const String smsGesteRegler = 'regler_passerelle_sms';

const String smsCleActif = 'sms.auto.actif';
const String smsCleRappelHeure = 'sms.rappel.heure';
const String smsCleRappelJoursAvant = 'sms.rappel.joursAvant';
/// Rappel du MATIN MÊME (lot SMS-R, Direction du 16/11/2026) : l'heure, réglable en base (défaut 7 h, à valider), et son modèle (qui porte le prénom).
const String smsCleRappelHeureMatin = 'sms.rappelRdv.heureMatin';
const String smsCleModeleRappelMatin = 'sms.rappelRdv.modeleMatin';
const String smsCleAnniversaireHeure = 'sms.anniversaire.heure';
const String smsCleCalmeDebut = 'sms.calme.debut';
const String smsCleCalmeFin = 'sms.calme.fin';
const String smsCleHorizonJours = 'sms.horizonJours';
const String smsCleToleranceMinutes = 'sms.toleranceMinutes';
const String smsCleModeleRappel = 'sms.modele.rappel';
const String smsCleModeleAnniversairePatient = 'sms.modele.anniversairePatient';
const String smsCleModeleAnniversairePersonnel = 'sms.modele.anniversairePersonnel';

const bool smsActifDefaut = false;
const int smsRappelHeureDefaut = 18;
const int smsRappelJoursAvantDefaut = 1;
const int smsRappelHeureMatinDefaut = 7;
const int smsAnniversaireHeureDefaut = 9;
const int smsCalmeDebutDefaut = 21;
const int smsCalmeFinDefaut = 7;
const int smsHorizonJoursDefaut = 2;
const int smsToleranceMinutesDefaut = 120;

/// Modèles par défaut, VALIDÉS par la Direction (16/11/2026) : sans mot médical, sans médecin ni service ni motif.
const String smsModeleRappelDefaut = '{{clinique}} : rappel de votre rendez-vous le {{date}} à {{heure}}. Pour le modifier, appelez le {{telephone}}.';
/// Le rappel du matin, PROPOSITION à valider : il porte le prénom ({{nom}}), jamais le médecin, le service ni le motif.
const String smsModeleRappelMatinDefaut = '{{clinique}} : bonjour {{nom}}, rappel de votre rendez-vous aujourd’hui à {{heure}}. Pour le modifier, appelez le {{telephone}}.';
const String smsModeleAnniversairePatientDefaut = '{{clinique}} vous souhaite un joyeux anniversaire, {{nom}}. Portez-vous bien.';
const String smsModeleAnniversairePersonnelDefaut = '{{clinique}} vous souhaite un joyeux anniversaire, {{nom}}. Merci pour votre engagement.';

/// Longueur maximale d'un message (la même que celle du relais).
const int smsTexteMax = 320;

/// Les cinq variables, et rien d'autre.
const List<String> smsVariables = ['nom', 'date', 'heure', 'clinique', 'telephone'];

/// LISTE MÉDICALE (PROPOSITION À VALIDER par un médecin nommé : aucun document ne la fournit). Un SMS ne dit jamais ce qu'un résultat contient ni de quoi souffre la personne.
const List<String> smsMotsMedicaux = [
  'diagnostic', 'pathologie', 'maladie', 'seropositif', 'seropositive', 'positif', 'positive', 'negatif', 'negative',
  'grossesse', 'enceinte', 'paludisme', 'palu', 'vih', 'sida', 'diabete', 'cancer', 'tuberculose', 'hepatite',
];

/// Un refus NOMMÉ : code, motif, geste.
class RefusSms {
  const RefusSms(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
  Map<String, Object?> toJson() => {'code': code, 'motif': motif, 'geste': geste};
  @override
  String toString() => '$code : $motif';
}

String _sansAccent(String s) {
  const de = 'àâäéèêëîïôöùûüç';
  const vers = 'aaaeeeeiioouuuc';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? vers[i] : c);
  }
  return b.toString();
}

/// Le premier mot médical d'un texte (mot entier, sans accent, sans casse), ou `null`.
String? smsMotMedical(String texte) {
  final t = _sansAccent(texte);
  for (final m in smsMotsMedicaux) {
    if (RegExp('(?<![a-z])${RegExp.escape(m)}(?![a-z])').hasMatch(t)) return m;
  }
  return null;
}

/// Contrôle d'un modèle à l'enregistrement : variables connues seulement, aucun mot médical, 320 caractères au plus une fois composé avec les valeurs les plus longues raisonnables
/// (le contrôle de la longueur réelle se refait à la composition). Rend le refus nommé ou `null`.
RefusSms? smsVerifierModele(String modele) {
  if (modele.trim().isEmpty) return const RefusSms('MODELE_VIDE', 'le modèle de message est vide', 'Écrire le texte du message.');
  for (final m in RegExp(r'\{\{\s*([^}]*?)\s*\}\}').allMatches(modele)) {
    final v = m.group(1)!;
    if (!smsVariables.contains(v)) {
      return RefusSms('VARIABLE_INCONNUE', 'la variable {{$v}} n\'existe pas (variables admises : ${smsVariables.map((x) => '{{$x}}').join(' ')})', 'Retirer la variable : un rappel ne nomme jamais le médecin, le service ni le motif.');
    }
  }
  final mot = smsMotMedical(modele);
  if (mot != null) return RefusSms('MOT_MEDICAL', 'le modèle contient un mot de la liste médicale : « $mot »', 'Réécrire le message sans diagnostic, résultat ni état de santé.');
  return null;
}

/// Compose un modèle : les cinq variables, rien d'autre ; une variable inconnue reste vide (elle est de toute façon refusée à l'enregistrement).
String smsComposer(String modele, Map<String, String> valeurs) =>
    modele.replaceAllMapped(RegExp(r'\{\{\s*([^}]*?)\s*\}\}'), (m) => smsVariables.contains(m.group(1)) ? (valeurs[m.group(1)] ?? '') : '');

/// Le numéro d'un dossier en E.164, ou `null` (même règle que la maquette : `+...` gardé, `00...` converti, dix chiffres commençant par 01 : indicatif +229).
String? smsNumeroE164(Object? brut) {
  final n = '${brut ?? ''}'.replaceAll(RegExp(r'[\s.\-()]'), '');
  String? r;
  if (RegExp(r'^\+').hasMatch(n)) {
    r = n;
  } else if (RegExp(r'^00[1-9]').hasMatch(n)) {
    r = '+${n.substring(2)}';
  } else if (RegExp(r'^01[0-9]{8}$').hasMatch(n)) {
    r = '+229$n';
  }
  return r != null && RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(r) ? r : null;
}

/// Le numéro masqué du journal : « •••• » et les quatre derniers chiffres.
String smsMasquer(String numero) => '••••${numero.length >= 4 ? numero.substring(numero.length - 4) : numero}';

/// Le réglage de clinique (lu de la base à la date du jour, jamais du code).
class ReglageSmsAuto {
  const ReglageSmsAuto({
    this.actif = smsActifDefaut,
    this.rappelHeure = smsRappelHeureDefaut,
    this.rappelJoursAvant = smsRappelJoursAvantDefaut,
    this.rappelHeureMatin = smsRappelHeureMatinDefaut,
    this.anniversaireHeure = smsAnniversaireHeureDefaut,
    this.calmeDebut = smsCalmeDebutDefaut,
    this.calmeFin = smsCalmeFinDefaut,
    this.horizonJours = smsHorizonJoursDefaut,
    this.toleranceMinutes = smsToleranceMinutesDefaut,
    this.modeleRappel = smsModeleRappelDefaut,
    this.modeleRappelMatin = smsModeleRappelMatinDefaut,
    this.modeleAnniversairePatient = smsModeleAnniversairePatientDefaut,
    this.modeleAnniversairePersonnel = smsModeleAnniversairePersonnelDefaut,
  });
  final bool actif;
  final int rappelHeure, rappelHeureMatin, rappelJoursAvant, anniversaireHeure, calmeDebut, calmeFin, horizonJours, toleranceMinutes;
  final String modeleRappel, modeleRappelMatin, modeleAnniversairePatient, modeleAnniversairePersonnel;
}

/// Un envoi calculé : une clé NATURELLE (qui reste à la mère : le relais ne reçoit que son HMAC), le type, le numéro E.164, le texte final, l'heure d'envoi (heure du Bénin).
class EnvoiSmsPlanifie {
  const EnvoiSmsPlanifie({required this.cle, required this.type, required this.numero, required this.texte, required this.heureEnvoi});
  final String cle, type, numero, texte;
  final DateTime heureEnvoi;
  Map<String, Object?> toJson() => {'cle': cle, 'type': type, 'numero': numero, 'texte': texte, 'heureEnvoi': _iso(heureEnvoi)};
}

/// Un candidat écarté, avec la RAISON nommée (jamais silencieux).
class SmsEcarte {
  const SmsEcarte(this.cle, this.raison);
  final String cle, raison;
  Map<String, Object?> toJson() => {'cle': cle, 'raison': raison};
}

class PlanSms {
  const PlanSms(this.envois, this.ecartes);
  final List<EnvoiSmsPlanifie> envois;
  final List<SmsEcarte> ecartes;
}

String _p2(int n) => n.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_p2(d.month)}-${_p2(d.day)}T${_p2(d.hour)}:${_p2(d.minute)}';
String _jour(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_p2(d.month)}-${_p2(d.day)}';

/// La date d'un champ (`AAAA-MM-JJ` ou `AAAA-MM-JJTHH:MM`) lue comme heure du Bénin, SANS conversion de fuseau, ou `null`.
DateTime? _lireDate(Object? v) {
  final s = '${v ?? ''}';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), int.parse(m.group(4) ?? '0'), int.parse(m.group(5) ?? '0'));
}

/// Les heures calmes : si l'heure d'envoi y tombe, rend la FIN (le report), sinon l'heure inchangée. Début et fin sont des heures entières (21 et 7 : à cheval sur minuit).
DateTime smsApresHeuresCalmes(DateTime t, int debut, int fin) {
  if (debut == fin) return t;
  final h = t.hour;
  final dedans = debut < fin ? (h >= debut && h < fin) : (h >= debut || h < fin);
  if (!dedans) return t;
  final jourFin = (debut > fin && h >= debut) ? DateTime(t.year, t.month, t.day + 1) : DateTime(t.year, t.month, t.day);
  return DateTime(jourFin.year, jourFin.month, jourFin.day, fin);
}

String _dateFr(DateTime d) => '${_p2(d.day)}/${_p2(d.month)}/${d.year}';

/// L'ANNIVERSAIRE d'une date de naissance dans une année : le 29 février des années non bissextiles est fêté le 28 février (hypothèse à valider).
DateTime? _anniversaireEn(DateTime naissance, int annee) {
  if (naissance.month == 2 && naissance.day == 29) {
    final bissextile = (annee % 4 == 0 && annee % 100 != 0) || annee % 400 == 0;
    return DateTime(annee, 2, bissextile ? 29 : 28);
  }
  return DateTime(annee, naissance.month, naissance.day);
}

/// CALCULE les envois automatiques. `maintenant` est l'heure du Bénin. Les fiches sont lues telles que la mère les tient (collections `consultations`, `patients`, `deces`, `employes`) ;
/// `clinique` et `telephone` viennent de l'identité imprimée (jamais écrits ici).
///
///  - RAPPEL : une consultation `planifiee` d'un patient connu, sans `nonPatient`, dont le jour est (jour d'envoi + joursAvant), part à `rappelHeure` le jour d'envoi.
///  - RAPPEL DU MATIN (Direction, 16/11/2026) : un rendez-vous encore à venir dont l'heure d'envoi de la veille est PASSÉE et dont la clé de la veille n'a JAMAIS été déposée ([dejaDeposes]) part le
///    matin du rendez-vous à `rappelHeureMatin` (7 h par défaut, après les heures calmes), jamais à l'heure du rendez-vous ni après (`MATIN_APRES_LE_RENDEZ_VOUS`), avec le modèle du matin (le prénom,
///    jamais le médecin, le service ni le motif). Clé `rappel_rdv_matin:<id>:<jour>` ; même type `rappel_rdv` ; le plafond du jour reste celui du relais (200).
///  - ANNIVERSAIRE : un patient (consentement `consentementSms != false`, ACTIVÉ par défaut), un agent (consentement `== true`, DÉCOCHÉ par défaut), à `anniversaireHeure` le jour même ; un patient
///    décédé n'en reçoit pas.
///  - sans consentement ou sans numéro valide : écarté et NOMMÉ ; jamais d'envoi.
///  - heure passée de plus de `toleranceMinutes` : écarté (`HEURE_PASSEE`) ; dans les heures calmes : reporté à leur fin ; texte > 320 ou mot médical : écarté.
///  - un horizon de `horizonJours` jours : on dépose à l'avance, le relais garde planifié.
PlanSms smsPlanifier({
  required DateTime maintenant,
  required ReglageSmsAuto reglage,
  required List<Map<String, Object?>> consultations,
  required List<Map<String, Object?>> patients,
  required List<Map<String, Object?>> deces,
  required List<Map<String, Object?>> employes,
  required String clinique,
  required String telephone,
  Set<String> dejaDeposes = const {},
}) {
  final envois = <EnvoiSmsPlanifie>[];
  final ecartes = <SmsEcarte>[];
  final decedes = {for (final d in deces) '${d['patientId'] ?? ''}'};
  final patientsParId = {for (final p in patients) '${p['id']}': p};

  void ajouter(String cle, String type, Object? tel, String texte, DateTime heure) {
    final numero = smsNumeroE164(tel);
    if (numero == null) return ecartes.add(SmsEcarte(cle, 'NUMERO_INVALIDE'));
    if (smsMotMedical(texte) != null) return ecartes.add(SmsEcarte(cle, 'MOT_MEDICAL'));
    if (texte.trim().isEmpty || texte.runes.length > smsTexteMax) return ecartes.add(SmsEcarte(cle, 'TEXTE_INVALIDE'));
    final h = smsApresHeuresCalmes(heure, reglage.calmeDebut, reglage.calmeFin);
    if (h.isBefore(maintenant.subtract(Duration(minutes: reglage.toleranceMinutes)))) return ecartes.add(SmsEcarte(cle, 'HEURE_PASSEE'));
    envois.add(EnvoiSmsPlanifie(cle: cle, type: type, numero: numero, texte: texte, heureEnvoi: h));
  }

  final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);

  // Le rendez-vous est encore à venir, l'heure d'envoi de la veille est PASSÉE et aucun rappel de la veille n'a jamais été déposé : c'est le cas du matin.
  bool rappelDuMatin(Map<String, Object?> c, DateTime quand) {
    if (!quand.isAfter(maintenant)) return false;
    final veille = DateTime(quand.year, quand.month, quand.day - reglage.rappelJoursAvant, reglage.rappelHeure);
    return !smsApresHeuresCalmes(veille, reglage.calmeDebut, reglage.calmeFin).isAfter(maintenant) && !dejaDeposes.contains('rappel_rdv:${c['id']}:${_jour(quand)}');
  }

  final jourRdvMax = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + reglage.horizonJours + reglage.rappelJoursAvant);
  for (final c in consultations) {
    final quand = _lireDate(c['date']);
    if (quand == null) continue;
    final jr = DateTime(quand.year, quand.month, quand.day);
    if (jr.isBefore(aujourdhui) || jr.isAfter(jourRdvMax) || !rappelDuMatin(c, quand)) continue;
    final cle = 'rappel_rdv_matin:${c['id']}:${_jour(quand)}';
    if (c['statut'] != 'planifiee' || c['nonPatient'] == true || '${c['patientId'] ?? ''}'.isEmpty) continue;
    final p = patientsParId['${c['patientId']}'];
    if (p == null) {
      ecartes.add(SmsEcarte(cle, 'PATIENT_INCONNU'));
      continue;
    }
    if (p['consentementSms'] == false) {
      ecartes.add(SmsEcarte(cle, 'CONSENTEMENT_RETIRE'));
      continue;
    }
    final matin = smsApresHeuresCalmes(DateTime(quand.year, quand.month, quand.day, reglage.rappelHeureMatin), reglage.calmeDebut, reglage.calmeFin);
    if (!matin.isBefore(quand)) {
      ecartes.add(SmsEcarte(cle, 'MATIN_APRES_LE_RENDEZ_VOUS'));
      continue;
    }
    final texte = smsComposer(reglage.modeleRappelMatin, {'nom': '${p['prenom'] ?? ''}'.trim(), 'date': _dateFr(quand), 'heure': '${_p2(quand.hour)}h${_p2(quand.minute)}', 'clinique': clinique, 'telephone': telephone});
    ajouter(cle, 'rappel_rdv', p['telephone'], texte, matin);
  }

  for (var k = 0; k <= reglage.horizonJours; k++) {
    final jourEnvoi = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + k);

    // RAPPELS : le rendez-vous tombe `joursAvant` jours après le jour d'envoi.
    final jourRdv = DateTime(jourEnvoi.year, jourEnvoi.month, jourEnvoi.day + reglage.rappelJoursAvant);
    for (final c in consultations) {
      final quand = _lireDate(c['date']);
      if (quand == null || _jour(quand) != _jour(jourRdv)) continue;
      if (rappelDuMatin(c, quand)) continue; // le matin du rendez-vous s'en charge (bloc ci-dessus)
      final cle = 'rappel_rdv:${c['id']}:${_jour(quand)}';
      if (c['statut'] != 'planifiee' || c['nonPatient'] == true || '${c['patientId'] ?? ''}'.isEmpty) continue;
      final p = patientsParId['${c['patientId']}'];
      if (p == null) {
        ecartes.add(SmsEcarte(cle, 'PATIENT_INCONNU'));
        continue;
      }
      if (p['consentementSms'] == false) {
        ecartes.add(SmsEcarte(cle, 'CONSENTEMENT_RETIRE'));
        continue;
      }
      final texte = smsComposer(reglage.modeleRappel, {'nom': '${p['prenom'] ?? ''}'.trim(), 'date': _dateFr(quand), 'heure': '${_p2(quand.hour)}h${_p2(quand.minute)}', 'clinique': clinique, 'telephone': telephone});
      ajouter(cle, 'rappel_rdv', p['telephone'], texte, DateTime(jourEnvoi.year, jourEnvoi.month, jourEnvoi.day, reglage.rappelHeure));
    }

    // ANNIVERSAIRES du jour d'envoi.
    for (final p in patients) {
      final n = _lireDate(p['dateNaissance']);
      if (n == null) continue;
      final f = _anniversaireEn(n, jourEnvoi.year);
      if (f == null || _jour(f) != _jour(jourEnvoi)) continue;
      final cle = 'anniversaire_patient:${p['id']}:${jourEnvoi.year}';
      if (decedes.contains('${p['id']}')) {
        ecartes.add(SmsEcarte(cle, 'PATIENT_DECEDE'));
        continue;
      }
      if (p['consentementSms'] == false) {
        ecartes.add(SmsEcarte(cle, 'CONSENTEMENT_RETIRE'));
        continue;
      }
      final texte = smsComposer(reglage.modeleAnniversairePatient, {'nom': '${p['prenom'] ?? ''}'.trim(), 'date': _dateFr(jourEnvoi), 'heure': '', 'clinique': clinique, 'telephone': telephone});
      ajouter(cle, 'anniversaire_patient', p['telephone'], texte, DateTime(jourEnvoi.year, jourEnvoi.month, jourEnvoi.day, reglage.anniversaireHeure));
    }
    for (final e in employes) {
      final n = _lireDate(e['dateNaissance']);
      if (n == null) continue;
      final f = _anniversaireEn(n, jourEnvoi.year);
      if (f == null || _jour(f) != _jour(jourEnvoi)) continue;
      final cle = 'anniversaire_personnel:${e['id']}:${jourEnvoi.year}';
      if (e['consentementSms'] != true) {
        ecartes.add(SmsEcarte(cle, 'CONSENTEMENT_ABSENT'));
        continue;
      }
      final texte = smsComposer(reglage.modeleAnniversairePersonnel, {'nom': '${e['prenom'] ?? ''}'.trim(), 'date': _dateFr(jourEnvoi), 'heure': '', 'clinique': clinique, 'telephone': telephone});
      ajouter(cle, 'anniversaire_personnel', e['telephone'], texte, DateTime(jourEnvoi.year, jourEnvoi.month, jourEnvoi.day, reglage.anniversaireHeure));
    }
  }
  envois.sort((a, b) => a.heureEnvoi.compareTo(b.heureEnvoi) != 0 ? a.heureEnvoi.compareTo(b.heureEnvoi) : a.cle.compareTo(b.cle));
  return PlanSms(envois, ecartes);
}

/// Le contrôle du réglage de clinique : heures de 0 à 23, jours avant de 0 à 7, horizon de 1 à 14 jours, tolérance de 0 à 180 minutes (sous la péremption du relais), modèles valides.
RefusSms? smsVerifierReglage(ReglageSmsAuto r) {
  for (final (nom, h) in [('rappel', r.rappelHeure), ('rappel du matin', r.rappelHeureMatin), ('anniversaire', r.anniversaireHeure), ('début des heures calmes', r.calmeDebut), ('fin des heures calmes', r.calmeFin)]) {
    if (h < 0 || h > 23) return RefusSms('HEURE_HORS_BORNES', 'l\'heure du réglage « $nom » doit être de 0 à 23', 'Saisir une heure entière de 0 à 23.');
  }
  if (r.rappelJoursAvant < 0 || r.rappelJoursAvant > 7) return const RefusSms('JOURS_HORS_BORNES', 'le rappel part de 0 à 7 jours avant le rendez-vous', 'Saisir un nombre de jours de 0 à 7.');
  if (r.horizonJours < 1 || r.horizonJours > 14) return const RefusSms('HORIZON_HORS_BORNES', 'l\'horizon de calcul est de 1 à 14 jours', 'Saisir un nombre de jours de 1 à 14.');
  if (r.toleranceMinutes < 0 || r.toleranceMinutes > 180) return const RefusSms('TOLERANCE_HORS_BORNES', 'la tolérance est de 0 à 180 minutes (le relais ne reprend pas un message resté planifié plus de 3 heures)', 'Saisir de 0 à 180 minutes.');
  for (final m in [r.modeleRappel, r.modeleRappelMatin, r.modeleAnniversairePatient, r.modeleAnniversairePersonnel]) {
    final x = smsVerifierModele(m);
    if (x != null) return x;
  }
  return null;
}

/// Le consentement SMS d'une FICHE (dossier patient, fiche du personnel), tracé à l'enregistrement : valeur booléenne, date et auteur posés à la création et à chaque CHANGEMENT (RG-12 : l'ancienne
/// valeur reste lisible au journal d'audit). `defautActif` : le patient est consentant PAR DÉFAUT (décision de la Direction, retirable) ; le personnel NE L'EST PAS (décoché par défaut, validé le 16/11/2026).
/// Retirer le consentement n'a pas d'autre geste : la mère retire au prochain calcul les envois planifiés de la personne.
Map<String, Object?> smsTracerConsentement(Map<String, Object?> saisie, Map<String, Object?>? existante, {required bool defautActif, required DateTime maintenant, required String par}) {
  bool lire(Map<String, Object?>? m) {
    final x = m?['consentementSms'];
    if (x is bool) return x;
    if (x is String && (x == 'true' || x == 'false')) return x == 'true';
    return defautActif;
  }

  final v = {...saisie};
  final voulu = lire(v);
  final avant = existante == null ? null : lire(existante);
  v['consentementSms'] = voulu;
  final dejaTrace = existante != null && '${existante['consentementSmsLe'] ?? ''}'.isNotEmpty;
  if (avant == null || avant != voulu || !dejaTrace) {
    v['consentementSmsLe'] = maintenant.toIso8601String();
    v['consentementSmsPar'] = par;
  } else {
    v['consentementSmsLe'] = existante['consentementSmsLe'];
    v['consentementSmsPar'] = existante['consentementSmsPar'] ?? par;
  }
  return v;
}
