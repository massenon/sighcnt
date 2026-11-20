/// Accueil M2 — l'agenda, les rendez-vous et visites, les interventions à domicile, le registre des appels, l'agenda du médecin.
///
/// Un rendez-vous HONORÉ n'est ni supprimé ni archivé : il change d'onglet (il EST la consultation). REPORTÉ et NON HONORÉ sont deux états distincts
/// (confondre les deux ferait disparaître l'absentéisme). Une personne NON ENREGISTRÉE a quatre champs — nom, prénom, quartier, téléphone — et
/// n'ouvre aucun dossier, ne consomme aucun code CNT (RG-01).
library;

import '../format/format_fr.dart';
import '../format/recherche.dart';
import '../referentiels/periodes.dart' show ajouterJours;
import 'ag_commun.dart';

// --- états et suites d'un rendez-vous ------------------------------------------------------------------------------------------

/// Un rendez-vous honoré a quitté l'agenda (il a son onglet) : l'état `terminee`.
bool agEstApure(AgFiche r) => r['statut'] == 'terminee';

/// Un rendez-vous PLANIFIÉ dont la date est passée : le logiciel le SIGNALE, il ne tranche pas (le décider tout seul inventerait une absence).
bool agEnSouffrance(AgFiche r, DateTime aujourdhui) =>
    r['statut'] == 'planifiee' && agJour(r['date']).compareTo(iso(aujourdhui)) < 0;

/// `marquerHonore` : l'état et l'instant du constat.
AgFiche agPatchHonore(DateTime maintenant) =>
    {'statut': 'terminee', 'honoreLe': agInstant(maintenant)};

/// `marquerNonHonore` : le motif est conservé (RG-12).
AgFiche agPatchNonHonore(String motif, DateTime maintenant) => {
      'statut': 'non_honore',
      'motifNonHonore': motif,
      'constateLe': agInstant(maintenant)
    };

/// Les motifs de report proposés.
const agMotifsReport = [
  'Indisponibilité du praticien',
  'Demande du patient',
  'Urgence prioritaire',
  'Examen non disponible',
  'Patient absent — nouvelle date convenue',
  'Autre motif'
];

/// `reporter` : une NOUVELLE date est fixée, l'ancienne reste écrite (`dateInitiale` : la première date, jamais écrasée par un second report).
AgFiche agPatchReport(AgFiche r, String nouvelleDate, String motif, DateTime maintenant) => {
      'statut': 'reporte',
      'dateInitiale': agVrai(r['dateInitiale']) ? r['dateInitiale'] : r['date'],
      'date': nouvelleDate,
      'motifReport': motif,
      'reporteLe': agInstant(maintenant)
    };

/// Les natures de venue.
const agTypesRdv = [
  'Consultation',
  'Contrôle',
  'Urgence',
  'Domicile',
  'Visite',
  'Affaire privée'
];

// --- la personne non enregistrée ------------------------------------------------------------------------------------------------

/// Nom affiché d'une personne non enregistrée : NOM en majuscules, prénom tel que saisi.
String agNomNonEnregistre(AgFiche v) {
  String t(Object? x) => agVrai(x) ? '$x'.trim() : '';
  return [t(v['visiteurNom']).toUpperCase(), t(v['visiteurPrenom'])]
      .where((s) => s.isNotEmpty)
      .join(' ');
}

/// `validerVenue` : un dossier du répertoire, OU le nom d'une personne non enregistrée. Rend le refus, ou `null`.
String? agValiderVenue(AgFiche v) {
  final aDossier = agVrai(v['patientCode']);
  final nom = agVrai(v['visiteurNom']) ? '${v['visiteurNom']}'.trim() : '';
  if (!aDossier && nom.isEmpty) {
    return 'Sélectionner un dossier patient, ou renseigner le nom de la personne non enregistrée.';
  }
  return null;
}

/// `completerPatient` : rattache la venue au dossier choisi et lui donne sa référence (la sienne à l'édition, la suivante de la série sinon).
AgFiche _completerPatient(AgFiche v, AgFiche? record, Iterable<AgFiche> patients,
    Iterable<AgFiche> existantes) {
  final r = {...v};
  for (final p in patients) {
    if (p['code'] == r['patientCode']) {
      r['patientId'] = p['id'];
      r['patient'] = '${p['nom']} ${p['prenom']}';
      break;
    }
  }
  if (!agVrai(r['reference'])) {
    r['reference'] = agVrai(record?['reference'])
        ? record!['reference']
        : agReferenceSuivante('C', 5, existantes);
  }
  return r;
}

/// `completerVenue` : un patient du répertoire, OU une personne non enregistrée — dont la venue porte l'identité, PAS un dossier : aucun code CNT
/// n'est consommé. « NON-PATIENT » relu à l'édition n'est pas le choix d'un dossier.
AgFiche agCompleterVenue(AgFiche v,
    {AgFiche? record,
    required Iterable<AgFiche> patients,
    required Iterable<AgFiche> existantes}) {
  final code = v['patientCode'];
  if (agVrai(code) && code != 'NON-PATIENT') {
    return _completerPatient(v, record, patients, existantes);
  }
  final r = {...v};
  r['patient'] = agNomNonEnregistre(r);
  r['patientCode'] = 'NON-PATIENT';
  r['patientId'] = null;
  r['nonPatient'] = true;
  if (!agVrai(r['reference'])) {
    r['reference'] = agVrai(record?['reference'])
        ? record!['reference']
        : agReferenceSuivante('C', 5, existantes);
  }
  return r;
}

/// `completerPatient` seul (interventions à domicile).
AgFiche agCompleterPatient(AgFiche v,
        {AgFiche? record,
        required Iterable<AgFiche> patients,
        required Iterable<AgFiche> existantes}) =>
    _completerPatient(v, record, patients, existantes);

/// Le « passage sans rendez-vous » : la venue est EN COURS, sans rendez-vous, à l'heure d'arrivée tracée (c'est elle qui mesure l'attente).
AgFiche agPassage(AgFiche saisie,
    {AgFiche? record,
    required Iterable<AgFiche> patients,
    required Iterable<AgFiche> existantes}) {
  final v = {...saisie}..remove('priorite');
  v['statut'] = 'en_cours';
  final d = agDate(v['date']);
  v['date'] = d == null ? 'Invalid Date' : agInstant(d);
  v['sansRendezVous'] = true;
  return agCompleterVenue(v,
      record: record, patients: patients, existantes: existantes);
}

/// Les orientations proposées au passage sans rendez-vous.
const agOrientations = [
  'Médecine générale',
  'Chirurgie',
  'Maternité',
  'Laboratoire',
  'Imagerie / Échographie',
  'Salle de soins',
  'Mise en observation',
  'Pharmacie',
  'Retour à domicile'
];

/// Le message qui suit l'enregistrement d'un passage : prioritaire → alerte, sinon confirmation.
({bool alerte, String message, String detail}) agMessagePassage(AgFiche v, bool prioritaire) =>
    prioritaire
        ? (
            alerte: true,
            message: 'Passage prioritaire — ${v['patient']} orienté vers ${v['orientation']}.',
            detail: agVrai(v['motif']) ? '${v['motif']}' : ''
          )
        : (
            alerte: false,
            message: 'Passage enregistré — ${v['patient']}.',
            detail: 'Orienté vers ${v['orientation']}'
          );

/// La prise de rendez-vous de l'AGENDA : planifiée, la date devient un instant ISO (UTC), le patient est obligatoire.
AgFiche agNouveauRendezVous(AgFiche saisie,
    {required Iterable<AgFiche> patients, required Iterable<AgFiche> existantes}) {
  final v = {...saisie}..remove('notifier');
  v['statut'] = 'planifiee';
  final d = agDate(v['date']);
  v['date'] = d == null ? 'Invalid Date' : agInstant(d);
  return _completerPatient(v, null, patients, existantes);
}

/// `U.alerter` de la prise de rendez-vous : transmis au praticien, avec le patient, la date et le motif.
({String message, String detail}) agMessageTransmis(AgFiche v) {
  final d = agDate(v['date']);
  return (
    message: 'Rendez-vous transmis à ${v['medecin']}.',
    detail:
        '${v['patient']} — ${d == null ? 'NaN/NaN/NaN' : dateFR(d)} à ${d == null ? 'NaNhNaN' : heure(d)} · ${v['motif']}'
  );
}

/// `U.toast` quand le praticien n'est pas notifié.
({String message, String detail}) agMessageEnregistre(AgFiche v) {
  final d = agDate(v['date']);
  return (
    message: 'Rendez-vous enregistré.',
    detail: '${v['patient']} — ${d == null ? 'NaN/NaN/NaN' : dateFR(d)}'
  );
}

// --- l'agenda ---------------------------------------------------------------------------------------------------------------------

/// Les quatre indicateurs de l'agenda : ils comptent TOUTES les consultations actives (honorées comprises), comme la maquette.
List<AgKpi> agKpisAgenda(List<AgFiche> actives, int nbPraticiens, DateTime aujourdhui) {
  final auj = iso(aujourdhui);
  return [
    AgKpi('Rendez-vous aujourd’hui',
        agNum(actives.where((c) => agJour(c['date']) == auj).length)),
    AgKpi(
        'Cette semaine',
        agNum(actives.where((c) {
          final n = agJoursEntre(aujourdhui, c['date']);
          return n != null && n.abs() <= 3;
        }).length)),
    AgKpi('À confirmer',
        agNum(actives.where((c) => c['statut'] == 'planifiee').length)),
    AgKpi('Praticiens', agNum(nbPraticiens)),
  ];
}

/// La plage affichée par défaut : deux jours avant, quatre jours après aujourd'hui (« Semaine en cours »).
({String debut, String fin}) agFenetreParDefaut(DateTime aujourdhui) =>
    (debut: iso(ajouterJours(aujourdhui, -2)), fin: iso(ajouterJours(aujourdhui, 4)));

/// Les jours de la plage (31 au plus, un au moins) ; des bornes illisibles retombent sur la plage par défaut.
List<DateTime> agJoursFenetre(String debut, String fin, DateTime aujourdhui) {
  var d = agDate(debut), f = agDate(fin);
  if (d == null || f == null) {
    final p = agFenetreParDefaut(aujourdhui);
    d = agDate(p.debut)!;
    f = agDate(p.fin)!;
  }
  final ecart = agJoursEntre(d, f)! + 1;
  final n = ecart < 1 ? 1 : (ecart > 31 ? 31 : ecart);
  return [for (var i = 0; i < n; i++) ajouterJours(d, i)];
}

/// Un jour de la grille : au plus six rendez-vous à venir (l'honoré a quitté l'agenda), le reste en « + n autre(s) ».
class AgJour {
  const AgJour(this.jour, this.rendezVous, this.autres, this.aujourdhui);
  final DateTime jour;
  final List<AgFiche> rendezVous;
  final int autres;
  final bool aujourdhui;
  String get entete => agEnteteJour(jour);
  String get mois => agMoisJour(jour);
}

/// La grille de la plage : par jour, les rendez-vous NON apurés triés par date.
List<AgJour> agGrille(
    List<AgFiche> actives, List<DateTime> jours, DateTime aujourdhui) {
  final auj = iso(aujourdhui);
  return [
    for (final jour in jours)
      () {
        final j = iso(jour);
        final duJour = agTrierTexte(
            actives.where((c) => agJour(c['date']) == j && !agEstApure(c)),
            (c) => '${c['date']}');
        return AgJour(jour, duJour.take(6).toList(),
            duJour.length > 6 ? duJour.length - 6 : 0, j == auj);
      }()
  ];
}

/// « Du 14/08/2026 au 20/08/2026 — 7 jour(s) ».
String agTitreFenetre(List<DateTime> jours) =>
    'Du ${dateFR(jours.first)} au ${dateFR(jours.last)} — ${agNum(jours.length)} jour(s)';

/// La fenêtre s'étend JUSQU'AU rendez-vous qu'on vient de prendre (enregistré mais introuvable, sinon) ; au-delà de trente et un jours, elle se
/// recentre sur lui.
({String debut, String fin}) agEtendreFenetre(String debut, String fin, String dateRdv) {
  var d = debut, f = fin;
  final jour = agJour(dateRdv);
  if (d.isEmpty || jour.compareTo(d) < 0) d = jour;
  if (f.isEmpty || jour.compareTo(f) > 0) f = jour;
  final ecart = agJoursEntre(d, f);
  if (ecart != null && ecart > 30) {
    final rdv = agDate(dateRdv)!;
    d = iso(ajouterJours(rdv, -2));
    f = iso(ajouterJours(rdv, 4));
  }
  return (debut: d, fin: f);
}

/// La charge par praticien sur les trente derniers jours, du plus chargé au moins chargé (à égalité, l'ordre d'apparition).
List<({String libelle, int valeur})> agChargeParPraticien(
    List<AgFiche> actives, DateTime aujourdhui) {
  final ordre = <String>[];
  final compte = <String, int>{};
  for (final c in actives) {
    final n = agJoursEntre(c['date'], aujourdhui);
    if (n == null || n > 30 || n < 0) continue;
    final k = agVrai(c['medecin']) ? '${c['medecin']}' : 'undefined';
    if (!compte.containsKey(k)) ordre.add(k);
    compte[k] = (compte[k] ?? 0) + 1;
  }
  final liste = [for (final k in ordre) (libelle: k, valeur: compte[k]!)];
  final tries = [for (final (i, e) in liste.indexed) (i, e)]
    ..sort((a, b) {
      final c = b.$2.valeur.compareTo(a.$2.valeur);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final e in tries) e.$2];
}

/// La répartition par type (tous les rendez-vous actifs), dans l'ordre d'apparition.
({List<String> libelles, List<int> valeurs}) agRepartitionParType(
    List<AgFiche> actives) {
  final ordre = <String>[];
  final compte = <String, int>{};
  for (final c in actives) {
    final k = agVrai(c['type']) ? '${c['type']}' : 'undefined';
    if (!compte.containsKey(k)) ordre.add(k);
    compte[k] = (compte[k] ?? 0) + 1;
  }
  return (libelles: ordre, valeurs: [for (final k in ordre) compte[k]!]);
}

/// Le rappel des échéances à l'ouverture de l'agenda : les rendez-vous planifiés dans les DEUX heures, les réunions du jour. Rien à dire → `null`.
({String message, String? detail})? agRappelEcheances(
    List<AgFiche> actives, int reunionsDuJour, DateTime aujourdhui) {
  final t0 = aujourdhui.millisecondsSinceEpoch;
  final proches = actives.where((c) {
    if (c['statut'] != 'planifiee') return false;
    final d = agDate(c['date']);
    if (d == null) return false;
    final t = d.millisecondsSinceEpoch;
    return t >= t0 && t - t0 <= 2 * 3600000;
  }).toList();
  if (proches.isEmpty && reunionsDuJour == 0) return null;
  final parts = <String>[
    if (proches.isNotEmpty) '${proches.length} consultation(s) dans les deux heures',
    if (reunionsDuJour > 0) '$reunionsDuJour réunion(s) aujourd’hui',
  ];
  final p = proches.isEmpty ? null : proches.first;
  final dp = p == null ? null : agDate(p['date']);
  return (
    message: 'Échéances du jour : ${parts.join(' · ')}',
    detail: p == null ? null : 'Prochaine : ${p['patient']} à ${dp == null ? 'NaNhNaN' : heure(dp)}'
  );
}

// --- rendez-vous & visites (le registre) ----------------------------------------------------------------------------------------------

/// Les indicateurs du registre : `rows` est la collection ENTIÈRE ; seul ce que l'agenda montre se compte (les honorés ont leur onglet).
List<AgKpi> agKpisRendezVous(List<AgFiche> rows, DateTime aujourdhui) => [
      AgKpi('Dans l’agenda', agNum(rows.where((r) => !agEstApure(r)).length),
          indice: 'à venir, reportés ou non honorés'),
      AgKpi(
          'À venir',
          agNum(rows
              .where((r) => r['statut'] == 'planifiee' && !agEnSouffrance(r, aujourdhui))
              .length)),
      AgKpi('Reportés', agNum(rows.where((r) => r['statut'] == 'reporte').length)),
      AgKpi(
          'Non honorés & à statuer',
          agNum(rows
              .where((r) => r['statut'] == 'non_honore' || agEnSouffrance(r, aujourdhui))
              .length),
          indice: 'patients à rappeler'),
    ];

/// Filtre « À statuer » : `oui` = date passée et rien de constaté, `non` = à jour.
bool agFiltreSouffrance(AgFiche r, String valeur, DateTime aujourdhui) =>
    valeur == 'oui' ? agEnSouffrance(r, aujourdhui) : !agEnSouffrance(r, aujourdhui);

/// Filtre « Venu » : `externe` = personne non enregistrée, sinon patient du répertoire.
bool agFiltreVenu(AgFiche r, String valeur) =>
    valeur == 'externe' ? agVrai(r['nonPatient']) : !agVrai(r['nonPatient']);

/// Filtre « Venue » : `sans` = passage sans rendez-vous, sinon sur rendez-vous.
bool agFiltreVenue(AgFiche r, String valeur) =>
    valeur == 'sans' ? agVrai(r['sansRendezVous']) : !agVrai(r['sansRendezVous']);

/// La plage de dates d'un registre : un FILTRE du/au (jamais un tri), sur le début BRUT du champ ; vide, elle laisse tout passer.
bool agDansPlage(AgFiche r, String champ, String du, String au) {
  final v = agDebutTexte(r[champ], 10);
  if (du.isNotEmpty && v.compareTo(du) < 0) return false;
  if (au.isNotEmpty && v.compareTo(au) > 0) return false;
  return true;
}

/// Les phrases du détail d'un rendez-vous (les notes), dans l'ordre où la fiche les pose.
List<({String ton, String texte})> agNotesDetail(AgFiche r, DateTime aujourdhui) {
  final d = agDate(r['dateInitiale']);
  return [
    if (agVrai(r['dateInitiale']))
      (
        ton: 'attention',
        texte:
            'Rendez-vous reporté — date initiale : ${d == null ? 'NaN/NaN/NaN' : dateFR(d)} à ${d == null ? 'NaNhNaN' : heure(d)}${agVrai(r['motifReport']) ? '. Motif : ${r['motifReport']}' : ''}.'
      ),
    if (r['statut'] == 'non_honore')
      (
        ton: 'danger',
        texte:
            'Non honoré${agVrai(r['motifNonHonore']) ? ' — ${r['motifNonHonore']}' : ''}. Le rendez-vous reste dans l’agenda : c’est là qu’on retrouve les patients à rappeler.'
      ),
    if (agEnSouffrance(r, aujourdhui))
      (
        ton: 'attention',
        texte:
            'La date de ce rendez-vous est passée et rien n’a été constaté. Le logiciel le signale ; c’est à l’accueil de dire s’il a été honoré, reporté ou non honoré — le décider tout seul inventerait une absence.'
      ),
  ];
}

/// La note d'assurance du détail : le patient couvert, le taux (RG-09 — la répartition se fait à la facturation).
String? agNoteAssurance(AgFiche? patient) {
  if (patient == null || !agVrai(patient['assureur'])) return null;
  return 'Patient couvert par ${patient['assureurNom']} à hauteur de ${patient['tauxPriseEnCharge']} %. La facturation appliquera la répartition patient / assureur (RG-09).';
}

// --- interventions à domicile, appels, agenda du médecin -----------------------------------------------------------------------------------

/// Indicateurs du domicile : `rows` est la collection entière ; seules les prestations de type Domicile se comptent.
List<AgKpi> agKpisDomicile(List<AgFiche> rows) {
  final dom = rows.where((r) => r['type'] == 'Domicile').toList();
  num somme = 0;
  for (final r in dom) {
    final t = r['tarif'];
    final n = t is num ? t : num.tryParse('${t ?? ''}');
    somme += (n == null || n.isNaN) ? 0 : n;
  }
  return [
    AgKpi('Interventions à domicile', agNum(dom.length)),
    AgKpi('Planifiées', agNum(dom.where((r) => r['statut'] == 'planifiee').length)),
    AgKpi('Réalisées', agNum(dom.where((r) => r['statut'] == 'terminee').length)),
    AgKpi('Recette domicile', money(somme)),
  ];
}

/// Les objets d'appel relevés au standard.
const agObjetsAppel = [
  'Prise de rendez-vous',
  'Report de rendez-vous',
  'Demande de résultat d’analyse',
  'Renseignement tarifaire',
  'Suivi post-hospitalisation',
  'Rappel de règlement',
  'Demande d’ambulance',
  'Information administrative'
];

/// Les suites données à un appel.
const agSuitesAppel = [
  'Rendez-vous fixé',
  'Information donnée',
  'Rappel à programmer',
  'Transféré au médecin',
  'Sans suite'
];

List<AgKpi> agKpisAppels(List<AgFiche> rows) => [
      AgKpi('Appels enregistrés', agNum(rows.length)),
      AgKpi('Entrants', agNum(rows.where((r) => r['sens'] == 'entrant').length)),
      AgKpi('Sortants', agNum(rows.where((r) => r['sens'] == 'sortant').length)),
      AgKpi('Rappels à programmer',
          agNum(rows.where((r) => r['suite'] == 'Rappel à programmer').length)),
    ];

/// Un appel saisi à la main reçoit la référence suivante de la série A00001… (le sien à l'édition).
AgFiche agCompleterAppel(AgFiche v, {AgFiche? record, required Iterable<AgFiche> existantes}) {
  final r = {...v};
  if (!agVrai(r['reference']) && !agVrai(record?['reference'])) {
    r['reference'] = agReferenceSuivante('A', 5, existantes);
  }
  return r;
}

/// Les indicateurs de l'agenda d'UN praticien, lus sur ses consultations (`rows`).
List<AgKpi> agKpisAgendaMedecin(List<AgFiche> rows, DateTime aujourdhui) {
  final auj = iso(aujourdhui);
  final duJour = rows.where((r) => agDebutTexte(r['date'], 10) == auj);
  final aVenir = rows.where(
      (r) => agDebutTexte(r['date'], 10).compareTo(auj) > 0 && r['statut'] == 'planifiee');
  final ceMois = rows.where((r) =>
      r['statut'] == 'terminee' && agDebutTexte(r['date'], 7) == auj.substring(0, 7));
  return [
    AgKpi('Consultations au registre', agNum(rows.length)),
    AgKpi('Aujourd’hui', agNum(duJour.length)),
    AgKpi('Planifiées à venir', agNum(aVenir.length)),
    // « Terminees » sans accent : le libellé est celui de la maquette (écart E330, porté tel quel).
    AgKpi('Terminees ce mois-ci', agNum(ceMois.length)),
  ];
}

/// Les consultations d'un praticien, la plus récente en tête.
List<AgFiche> agAgendaDuMedecin(List<AgFiche> actives, String praticien) =>
    trierPar([for (final r in actives) if (r['medecin'] == praticien) r],
            (r) => r['date'])
        .reversed
        .toList();
