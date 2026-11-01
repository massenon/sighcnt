/// MOBILE SOIGNANT : les règles que l'application `apps/mobile` applique AVANT d'écrire une opération (spec §11, ADR-0005).
///
/// Sources, une par règle, aucune devinée :
///  - les messages de saisie, les bornes, les listes de choix et les écrans ouverts par profil sont RELEVÉS sur les pages du simulateur
///    (`prototype_html/mobile/`, piloté dans Chrome : `test/vecteurs/mobile.json`, `mob_donnees.dart`) ;
///  - « prescription selon droits » rejoue `PR.peutPrescrire` de la maquette complète (`D.CAPACITES`, matrice dans le même vecteur) ;
///  - l'orientation et les quatre temps de l'examen sont ceux de la FICHE de consultation (`cs_referentiels.dart`), la copie des constantes de
///    l'accueil est celle de la fiche (`csCopieReleve`), RG-09 se lit par le moteur de la caisse (`carteValide`).
///
/// Un refus est NOMMÉ (code, motif, geste). Une commande interdite est ABSENTE : les fonctions `mobPeut…` servent à ne pas la dessiner,
/// les fonctions `mobControler…` refont le contrôle au moteur (un bouton absent ne protège rien).
library;

import '../caisse/prise_en_charge.dart' show carteValide;
import '../consultation/ag_commun.dart' show agDate, agIsoLocal, agJour, agVrai;
import '../consultation/cs_moteur.dart' show csCopieReleve;
import '../consultation/cs_referentiels.dart' show csLibelleOrientation, csOrientations, csTempsExamen;
import '../format/format_fr.dart' show dateFR, heure, iso;
import '../labo/res_saisie.dart' show agePatient;
import '../patients/pat_patients.dart' show patListe;
import '../patients/pat_releves.dart' show patAnormale;
import '../securite/sec_donnees.dart' show secDonnees;
import 'mob_donnees.dart';

/// Fiche d'une collection telle que le lot la livre (`data` du journal).
typedef MobFiche = Map<String, Object?>;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le refus nommé
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un refus du mobile : un `code` stable, un `motif` lisible, un `geste` de correction ; `champs` porte les erreurs par champ d'un formulaire.
class RefusMobile implements Exception {
  const RefusMobile(this.code, this.motif, this.geste, {this.champs = const {}});
  final String code;
  final String motif;
  final String geste;
  final Map<String, String> champs;
  @override
  String toString() => '$code : $motif';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Fonction du soignant, écrans ouverts, droit de prescrire
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les fonctions que le profil « soignant » du mobile peut porter (celles du simulateur : médecin, sage-femme, infirmier ; l'aide-soignant lit
/// comme l'infirmier, sans exécuter ni prescrire : `D.CAPACITES`).
const mobFonctions = ['medecin', 'sage_femme', 'infirmier', 'aide_soignant'];

Map<String, Object?> get _capacites => (secDonnees['capacites'] as Map).cast<String, Object?>();

/// Le libellé de la fonction (`D.CAPACITES[f].label`), ou son code si elle est inconnue.
String mobLibelleFonction(String fonction) {
  final c = _capacites[fonction];
  return c is Map ? '${c['label']}' : fonction;
}

/// Le profil du SIMULATEUR qui porte cette fonction (le simulateur distingue trois profils cliniques).
String mobProfilSimulateur(String fonction) => switch (fonction) {
      'medecin' => 'medecin',
      'sage_femme' => 'sagefemme',
      _ => 'soignant',
    };

/// Les écrans que le simulateur ouvre à cette fonction.
List<String> mobEcransOuverts(String fonction) {
  final p = ((mobDonnees['profils'] as Map)[mobProfilSimulateur(fonction)] as Map);
  return [for (final e in (p['ecrans'] as List)) '$e'];
}

bool mobEcranOuvert(String fonction, String ecran) => mobEcransOuverts(fonction).contains(ecran);

/// `PR.peutPrescrire(nature, session)` : la capacité de la FONCTION, rien d'autre. Une fonction inconnue ne prescrit rien (ce qu'on ne sait pas
/// n'ouvre rien).
bool mobPeutPrescrire(String fonction, String nature) {
  final c = _capacites[fonction];
  if (c is! Map) return false;
  return ((c['prescrire'] as List?) ?? const []).contains(nature);
}

/// Les natures que le mobile sait prescrire, et l'écran qui les porte.
const mobNaturesMobile = {'medicament': 'prescription', 'analyse': 'demande-analyse'};

String mobLibelleNature(String nature) {
  for (final n in (secDonnees['naturesPrescription'] as List)) {
    if ((n as Map)['id'] == nature) return '${n['label']}';
  }
  return nature;
}

/// Les natures que la commande « prescrire » propose : la capacité de la fonction ET l'écran ouvert au profil (le plus restrictif des deux).
/// Vide = la commande est ABSENTE.
List<String> mobNaturesPrescriptibles(String fonction) => [
      for (final e in mobNaturesMobile.entries)
        if (mobPeutPrescrire(fonction, e.key) && mobEcranOuvert(fonction, e.value)) e.key
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Saisie : les règles de `mobile.js` (valider)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class MobRegle {
  const MobRegle(this.champ, this.libelle, {this.requis = false, this.min, this.max});
  final String champ;
  final String libelle;
  final bool requis;
  final num? min, max;
}

String _nombre(num n) => n == n.truncate() ? '${n.truncate()}' : '$n';

/// `Number(v.replace(',', '.'))` : la conversion de JavaScript (hexadécimal, exposant, signe, `Infinity` compris).
num? _nombreJs(String v) {
  final n = num.tryParse(v.replaceFirst(',', '.'));
  return (n == null || (n is double && n.isNaN)) ? null : n;
}

/// La conversion de JavaScript, publique : les écrans de la suite du mobile (CPN, CPoN, surveillance) lisent les mêmes nombres que `valider`.
num? mobNombreJs(String v) => _nombreJs(v);

/// `valider(regles)` du simulateur : requis → « X est obligatoire. » ; non numérique → « X doit être un nombre. » ; hors bornes → « X : valeur
/// improbable (a à b). ». Une valeur hors bornes est REFUSÉE EN LA NOMMANT. Rend les erreurs par champ (vide = tout est bon).
Map<String, String> mobValider(List<MobRegle> regles, Map<String, String> saisie) {
  final erreurs = <String, String>{};
  for (final r in regles) {
    final v = (saisie[r.champ] ?? '').trim();
    if (r.requis && v.isEmpty) {
      erreurs[r.champ] = '${r.libelle} est obligatoire.';
    } else if (v.isNotEmpty && r.min != null && r.max != null) {
      final n = _nombreJs(v);
      if (n == null) {
        erreurs[r.champ] = '${r.libelle} doit être un nombre.';
      } else if (n < r.min! || n > r.max!) {
        erreurs[r.champ] = '${r.libelle} : valeur improbable (${_nombre(r.min!)} à ${_nombre(r.max!)}).';
      }
    }
  }
  return erreurs;
}

/// Écran « Constantes » : la température est la seule obligatoire.
const mobReglesConstantes = [
  MobRegle('temperature', 'La température', requis: true, min: 30, max: 45),
  MobRegle('sys', 'La systolique', min: 50, max: 260),
  MobRegle('dia', 'La diastolique', min: 30, max: 160),
  MobRegle('pouls', 'Le pouls', min: 20, max: 250),
  MobRegle('fr', 'La FR', min: 5, max: 80),
  MobRegle('spo2', 'La SpO₂', min: 50, max: 100),
  MobRegle('poids', 'Le poids', min: 0.5, max: 300),
];

/// Écran « Consultation à domicile » : le motif est obligatoire (le diagnostic est un choix, il a toujours une valeur).
const mobReglesNote = [MobRegle('motif', 'Le motif', requis: true)];

/// Écran « Prescription ».
const mobReglesPrescription = [
  MobRegle('med', 'Le médicament', requis: true),
  MobRegle('poso', 'La posologie', requis: true),
  MobRegle('duree', 'La durée', requis: true, min: 1, max: 90),
];

/// Le choix « Autre » du diagnostic : il exige sa précision (la FICHE refuse un diagnostic vide : « Rédiger le diagnostic retenu. »).
const mobDiagnosticAutre = 'Autre (à préciser)';
const mobMessageDiagnosticVide = 'Rédiger le diagnostic retenu.';

RefusMobile _refusSaisie(Map<String, String> erreurs) => RefusMobile(
    'SAISIE_INVALIDE', erreurs.values.first, 'Corriger le champ indiqué', champs: erreurs);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Lot et patient
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le lot de la tournée a-t-il expiré ? `lotExpire` en millisecondes d'époque (0 ou null : aucun lot reçu).
bool mobLotExpire(int? lotExpire, DateTime maintenant) =>
    lotExpire != null && lotExpire > 0 && maintenant.millisecondsSinceEpoch >= lotExpire;

/// Toute écriture sur un dossier du lot est refusée une fois le lot expiré : on le DIT, avec la date et le geste.
void mobControlerLot(int? lotExpire, DateTime maintenant) {
  if (!mobLotExpire(lotExpire, maintenant)) return;
  final fin = DateTime.fromMillisecondsSinceEpoch(lotExpire!);
  throw RefusMobile(
      'LOT_EXPIRE',
      'Le lot de la tournée a expiré le ${dateFR(fin)} à ${heure(fin)}. Passé ce délai, les dossiers s’effacent du téléphone, sauf ce qui n’est pas encore parti.',
      'Se connecter pour recevoir le lot du jour');
}

String mobNomPatient(MobFiche p) => '${p['nom'] ?? ''} ${p['prenom'] ?? ''}'.trim();

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------------------------------------------------------------------------

Map<String, String> mobErreursConstantes(Map<String, String> saisie) => mobValider(mobReglesConstantes, saisie);

/// La fiche des constantes que le mobile écrit (collection `constantes`, famille B : une LIGNE de plus, jamais une modification). Mêmes champs que
/// le relevé de l'accueil du poste (`tensionSys`, `tensionDia`, `tension`, `fr`, `spo2`) : la mère les range avec les siens.
Map<String, Object?> mobChampsConstantes({
  required MobFiche patient,
  required String patientId,
  required Map<String, String> saisie,
  required String acteur,
  required DateTime maintenant,
}) {
  final erreurs = mobErreursConstantes(saisie);
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  num? n(String k) {
    final v = (saisie[k] ?? '').trim();
    return v.isEmpty ? null : _nombreJs(v);
  }

  final sys = n('sys'), dia = n('dia');
  return {
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'dateHeure': agIsoLocal(maintenant),
    'temperature': n('temperature'),
    if (sys != null) 'tensionSys': sys,
    if (dia != null) 'tensionDia': dia,
    if (sys != null && dia != null) 'tension': '${_nombre(sys)}/${_nombre(dia)}',
    if (n('pouls') != null) 'pouls': n('pouls'),
    if (n('fr') != null) 'fr': n('fr'),
    if (n('spo2') != null) 'spo2': n('spo2'),
    if (n('poids') != null) 'poids': n('poids'),
    'releveePar': acteur,
    'origine': 'mobile',
  };
}

/// Une fièvre se signale avec la saisie (seuil du simulateur : 38 °C).
bool mobFievre(Map<String, String> saisie) {
  final t = _nombreJs((saisie['temperature'] ?? '').trim());
  return t != null && t >= 38;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Note de consultation (« fiche » du mobile)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les quatre temps de l'examen, dans l'ordre de la fiche : inspection, palpation, percussion, auscultation.
List<({String code, String libelle})> get mobTempsExamen => [
      for (final t in csTempsExamen) (code: '${t['code']}', libelle: '${t['label']}')
    ];

/// Les orientations de la fiche (codées : la mère les range avec celles du poste).
List<({String valeur, String libelle})> get mobOrientations => csOrientations;

List<String> get mobDiagnostics => [for (final d in (mobDonnees['diagnostics'] as List)) '$d'];

/// La dernière constante de ce patient (la plus récente par `dateHeure`, comme `dernierReleve`).
MobFiche? mobDernierReleve(Iterable<MobFiche> constantes, String patientId, Object? patientCode) {
  final l = [
    for (final r in constantes)
      if (r['patientId'] == patientId || (agVrai(patientCode) && r['patientCode'] == patientCode)) r
  ]..sort((a, b) => '${b['dateHeure'] ?? ''}'.compareTo('${a['dateHeure'] ?? ''}'));
  return l.firstOrNull;
}

/// La fiche de consultation à domicile. Les constantes relevées sont REPRISES (copie datée, `csCopieReleve`), jamais ressaisies.
/// `saisie` : motif, anamnese, inspection, palpation, percussion, auscultation, diagnostic, precision (si « Autre »), orientation.
Map<String, Object?> mobChampsNote({
  required MobFiche patient,
  required String patientId,
  required Map<String, String> saisie,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
  Iterable<MobFiche> constantes = const [],
}) {
  final erreurs = mobValider(mobReglesNote, saisie);
  final diagnostic = (saisie['diagnostic'] ?? '').trim();
  final precision = (saisie['precision'] ?? '').trim();
  final retenu = diagnostic == mobDiagnosticAutre ? precision : diagnostic;
  if (retenu.isEmpty) erreurs['diagnostic'] = mobMessageDiagnosticVide;
  final orientation = (saisie['orientation'] ?? '').trim();
  if (orientation.isNotEmpty && !csOrientations.any((o) => o.valeur == orientation)) {
    erreurs['orientation'] = 'L’orientation « $orientation » n’est pas dans la liste de la fiche.';
  }
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  final releve = csCopieReleve(mobDernierReleve(constantes, patientId, patient['code']));
  return {
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'type': 'Domicile',
    'motif': (saisie['motif'] ?? '').trim(),
    if ((saisie['anamnese'] ?? '').trim().isNotEmpty) 'anamnese': saisie['anamnese']!.trim(),
    'examenClinique': {
      for (final t in csTempsExamen)
        if ((saisie['${t['code']}'] ?? '').trim().isNotEmpty) '${t['code']}': saisie['${t['code']}']!.trim()
    },
    'diagnostic': retenu,
    if (orientation.isNotEmpty) 'orientation': orientation,
    if (orientation.isNotEmpty) 'orientationLabel': csLibelleOrientation(orientation),
    if (releve != null) 'constantesAccueil': releve,
    'redigePar': acteur,
    'fonction': fonction,
    'origine': 'mobile',
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Prescription
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<String> get mobExamensAnalyses => [for (final e in ((mobDonnees['analyses'] as Map)['examens'] as List)) '$e'];
List<String> get mobUrgencesAnalyses => [for (final e in ((mobDonnees['analyses'] as Map)['urgences'] as List)) '$e'];

/// Une note de consultation de CE patient, écrite le jour même (jour local) : la prescription se fait après l'enregistrement de la fiche
/// (« Dossier → fiche → prescription »). Le jour même est une PROPOSITION : le simulateur dit « après l'enregistrement de la fiche », sans durée.
MobFiche? mobNoteDuJour(Iterable<MobFiche> notes, String patientId, DateTime maintenant) {
  final jour = iso(maintenant);
  final l = [
    for (final n in notes)
      if (n['patientId'] == patientId && agJour(n['date']) == jour) n
  ]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  return l.firstOrNull;
}

/// Le contrôle de la prescription, REFAIT au moteur (un bouton absent ne protège rien). Dans l'ordre : lot expiré, fonction habilitée, écran ouvert
/// au profil, note enregistrée. Lève un [RefusMobile] nommé ; ne rend rien quand tout est bon.
void mobControlerPrescription({
  required String fonction,
  required String nature,
  required String patientId,
  required Iterable<MobFiche> notes,
  required DateTime maintenant,
  int? lotExpire,
}) {
  mobControlerLot(lotExpire, maintenant);
  if (!mobNaturesMobile.containsKey(nature)) {
    throw RefusMobile('NATURE_NON_PORTEE', 'Le mobile ne prescrit pas « ${mobLibelleNature(nature)} ».', 'Prescrire depuis un poste de la clinique');
  }
  if (!mobPeutPrescrire(fonction, nature)) {
    throw RefusMobile(
        'FONCTION_NON_HABILITEE',
        '${mobLibelleFonction(fonction)} : la prescription de « ${mobLibelleNature(nature)} » n’est pas dans ses habilitations.',
        'Demander la prescription à un médecin');
  }
  if (!mobEcranOuvert(fonction, mobNaturesMobile[nature]!)) {
    final profil = ((mobDonnees['profils'] as Map)[mobProfilSimulateur(fonction)] as Map)['label'];
    throw RefusMobile(
        'ECRAN_FERME_AU_PROFIL',
        'Écran fermé au profil « $profil » : le simulateur ne l’ouvre pas, même si l’habilitation de la fonction le permet.',
        'Prescrire depuis un poste de la clinique');
  }
  if (mobNoteDuJour(notes, patientId, maintenant) == null) {
    throw const RefusMobile(
        'SANS_NOTE',
        'Aucune note de consultation du jour pour ce patient : la prescription se fait après l’enregistrement de la fiche (dossier, fiche, prescription).',
        'Enregistrer d’abord la note de consultation');
  }
}

/// Les champs d'une ordonnance de médicaments (collection `prescriptions`, famille C : pièce ÉMISE, immuable ; une correction est une pièce de plus).
Map<String, Object?> mobChampsOrdonnance({
  required MobFiche patient,
  required String patientId,
  required String noteId,
  required Map<String, String> saisie,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
}) {
  final erreurs = mobValider(mobReglesPrescription, saisie);
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  return {
    'nature': 'medicament',
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'noteId': noteId,
    'lignes': [
      {
        'medicament': saisie['med']!.trim(),
        'posologie': saisie['poso']!.trim(),
        'dureeJours': _nombreJs(saisie['duree']!.trim()),
      }
    ],
    'prescripteur': acteur,
    'fonction': fonction,
    'emise': true,
    'origine': 'mobile',
  };
}

/// Les champs d'une demande d'analyses : au moins un examen. Rien ne se prélève avant le paiement (le texte du simulateur le dit).
Map<String, Object?> mobChampsDemandeAnalyses({
  required MobFiche patient,
  required String patientId,
  required String noteId,
  required List<String> examens,
  required String urgence,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
}) {
  if (examens.isEmpty) {
    final m = '${(mobDonnees['analyses'] as Map)['aucunExamen']}';
    throw RefusMobile('SAISIE_INVALIDE', m, 'Corriger le champ indiqué', champs: {'examens': m});
  }
  final inconnus = [for (final e in examens) if (!mobExamensAnalyses.contains(e)) e];
  if (inconnus.isNotEmpty) {
    throw RefusMobile('EXAMEN_INCONNU', 'Examen hors catalogue du mobile : ${inconnus.join(', ')}.', 'Choisir dans la liste');
  }
  final u = urgence.isEmpty ? mobUrgencesAnalyses.first : urgence;
  if (!mobUrgencesAnalyses.contains(u)) {
    throw RefusMobile('SAISIE_INVALIDE', 'Degré d’urgence inconnu : $u.', 'Choisir dans la liste', champs: {'urgence': 'Degré d’urgence inconnu : $u.'});
  }
  return {
    'nature': 'analyse',
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'noteId': noteId,
    'examens': examens,
    'urgence': u,
    'prescripteur': acteur,
    'fonction': fonction,
    'emise': true,
    'origine': 'mobile',
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Agenda du jour
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les rendez-vous du lot pour aujourd'hui (jour LOCAL, comme l'agenda du poste), du plus tôt au plus tard ; les rendez-vous PLANIFIÉS d'un jour
/// passé sont SIGNALÉS à part, jamais tranchés (le décider tout seul inventerait une absence : même règle que l'agenda du poste).
class MobAgenda {
  const MobAgenda(this.duJour, this.enSouffrance);
  final List<MobFiche> duJour;
  final List<MobFiche> enSouffrance;
}

MobAgenda mobAgendaDuJour(Iterable<MobFiche> rendezVous, DateTime maintenant) {
  final jour = iso(maintenant);
  final jourDe = <MobFiche, String>{};
  final auJour = <MobFiche>[], retard = <MobFiche>[];
  for (final r in rendezVous) {
    final j = agJour(r['date']);
    jourDe[r] = j;
    if (j == jour) {
      auJour.add(r);
    } else if (r['statut'] == 'planifiee' && j.compareTo(jour) < 0 && agDate(r['date']) != null) {
      retard.add(r);
    }
  }
  int parDate(MobFiche a, MobFiche b) => agDate(a['date'])!.compareTo(agDate(b['date'])!);
  auJour.sort(parDate);
  retard.sort(parDate);
  return MobAgenda(auJour, retard);
}

/// L'heure d'un rendez-vous, « 09h30 » (heure locale), 
String mobHeureRendezVous(MobFiche r) {
  final d = agDate(r['date']);
  return d == null ? '' : heure(d);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Dossier en lecture
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les trois états de la couverture au bandeau du dossier (RG-09 se lit À LA DATE, par le moteur de la caisse).
enum MobCouverture { carteValide, carteNonValide, nonAssure }

const mobLibellesCouverture = {
  MobCouverture.carteValide: 'Carte valide',
  MobCouverture.carteNonValide: 'CARTE NON VALIDE',
  MobCouverture.nonAssure: 'Non assuré',
};

/// Le texte qui accompagne une carte non valide : la facturation sera intégrale au patient.
const mobExplicationCarteNonValide = 'La prise en charge ne s’applique pas : facturation intégrale au patient (RG-09).';

MobCouverture mobCouvertureDe(MobFiche patient, DateTime maintenant) {
  if (!agVrai(patient['assureur'])) return MobCouverture.nonAssure;
  return carteValide(patient, const [], iso(maintenant)) ? MobCouverture.carteValide : MobCouverture.carteNonValide;
}

class MobDossier {
  const MobDossier({
    required this.nom,
    required this.code,
    required this.age,
    required this.quartier,
    required this.telephone,
    required this.couverture,
    required this.allergies,
    required this.dernierReleve,
    required this.horsBornes,
    required this.notes,
    required this.prescriptions,
  });
  final String nom, code;
  final int? age;
  final String? quartier, telephone;
  final MobCouverture couverture;

  /// Vide = « Aucune connue. »
  final List<String> allergies;
  final MobFiche? dernierReleve;

  /// Les mesures hors des bornes de la feuille de température (`patAnormale`) : le logiciel signale, il ne diagnostique pas.
  final List<String> horsBornes;
  final List<MobFiche> notes, prescriptions;
}

/// Le dossier d'un patient du lot, en LECTURE. Notes et prescriptions : les plus récentes en tête.
MobDossier mobDossier({
  required MobFiche patient,
  required String patientId,
  required DateTime maintenant,
  Iterable<MobFiche> constantes = const [],
  Iterable<MobFiche> notes = const [],
  Iterable<MobFiche> prescriptions = const [],
}) {
  List<MobFiche> siens(Iterable<MobFiche> l) => [
        for (final x in l)
          if (x['patientId'] == patientId) x
      ]..sort((a, b) => '${b['date'] ?? b['dateHeure'] ?? ''}'.compareTo('${a['date'] ?? a['dateHeure'] ?? ''}'));
  final releve = mobDernierReleve(constantes, patientId, patient['code']);
  final age = agePatient({...patient, if (!agVrai(patient['age']) && agVrai(patient['ageDeclare'])) 'age': patient['ageDeclare']}, maintenant);
  return MobDossier(
    nom: mobNomPatient(patient),
    code: '${patient['code'] ?? 'en attente de numéro'}',
    age: age,
    quartier: agVrai(patient['quartier']) ? '${patient['quartier']}' : null,
    telephone: agVrai(patient['telephone']) ? '${patient['telephone']}' : null,
    couverture: mobCouvertureDe(patient, maintenant),
    allergies: patListe(patient['allergies']),
    dernierReleve: releve,
    horsBornes: releve == null ? const [] : patAnormale(releve),
    notes: siens(notes),
    prescriptions: siens(prescriptions),
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Textes relevés sur les écrans du simulateur
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un texte de `mob_donnees.dart` (consultation, prescription, analyses, lot, allergiesAucune, constantesAucune, carteNonValide).
String mobTexte(String cle) => '${(mobDonnees['textes'] as Map)[cle]}';

/// Le libellé d'un écran du simulateur (« Consultation à domicile », « Dossier du patient »…).
String mobLibelleEcran(String id) => '${(mobDonnees['libellesEcrans'] as Map)[id] ?? id}';
