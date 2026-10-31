/// PILOTAGE — les huit écrans de STATISTIQUES (`dashboards.js`, vagues 8, 9, 46, 53, 60) : m5-stats-examens, m2-stats-echographie (imagerie médicale),
/// m2-stats-consultations, m3-stats-bloc, m3-stats-hospitalisations, m10-cout-agent, m12-rentabilite-groupes, m4-stats-maternite.
///
/// Rejoués sur `test/vecteurs/pilotage.json`, tiré des écrans réels pilotés dans Chrome (`prototype_html/build/vecteurs-pilotage.js`). Chaque fonction
/// reçoit les fiches ACTIVES des registres lus par l'écran et rend la [PilVue] qu'il dessine : rien n'est fourni, tout est recompté à chaque filtre.
library;

import '../comptabilite/cpa_referentiels.dart' show cpaCentresCout;
import '../comptabilite/cpc_bfr.dart' show cpcJoursEntre;
import '../format/format_fr.dart';
import '../format/js.dart';
import '../hospitalisation/hos_regles.dart' show hosChambres, hosTypesChambre;
import '../paie/pai_moteur.dart' show paiCnssOuvriere, paiCnssPatronale, paiVpsTaux, paiSeuilTele;
import '../referentiels/regles.dart' show resultatRendu, secteurNormalise;
import '../stock/points.dart' show groupePrestation, groupesPrestation;
import 'pil_vue.dart';

// =====================================================================================================================================================
// m5-stats-examens — les examens du laboratoire selon PLUSIEURS AXES, chaque axe est un FILTRE
// =====================================================================================================================================================

/// `TRANCHES_AGE_STATS` : (identifiant, libellé, de, à).
const List<(String, String, int, int)> pilTranchesAgeExamens = [
  ('0-4', '0–4 ans', 0, 4),
  ('5-14', '5–14 ans', 5, 14),
  ('15-24', '15–24 ans', 15, 24),
  ('25-44', '25–44 ans', 25, 44),
  ('45-64', '45–64 ans', 45, 64),
  ('65+', '65 ans et plus', 65, 200),
];

class PilFiltreExamens {
  const PilFiltreExamens({this.du = '', this.au = '', this.service = '', this.sexe = '', this.age = '', this.origine = ''});
  final String du, au, service, sexe, age, origine;
}

String _serviceDemandeur(PilFiche r) => pilVrai(r['secteurDemandeur']) ? '${r['secteurDemandeur']}' : (pilVrai(r['serviceDemandeur']) ? '${r['serviceDemandeur']}' : '');

/// Les services demandeurs proposés au filtre : ceux que portent les demandes, triés.
List<String> pilServicesExamens(Iterable<PilFiche> demandes) =>
    pilClesTriees({for (final r in demandes) if (_serviceDemandeur(r).isNotEmpty) _serviceDemandeur(r)});

/// `retenues()` : la population filtrée — chaque axe est un FILTRE.
List<PilFiche> pilExamensRetenus(Iterable<PilFiche> demandes, Iterable<PilFiche> patients, PilFiltreExamens f, DateTime auj) {
  final parPatient = <Object?, PilFiche>{for (final p in patients) p['id']: p};
  return [
    for (final r in demandes)
      if (_retenue(r, parPatient, f, auj)) r
  ];
}

bool _retenue(PilFiche r, Map<Object?, PilFiche> parPatient, PilFiltreExamens f, DateTime auj) {
  if (!pilDansPlage(r['dateHeure'], f.du, f.au)) return false;
  if (f.service.isNotEmpty && _serviceDemandeur(r) != f.service) return false;
  final p = parPatient[r['patientId']];
  if (f.sexe.isNotEmpty && (p == null || p['sexe'] != f.sexe)) return false;
  if (f.age.isNotEmpty) {
    final tr = pilTranchesAgeExamens.firstWhere((x) => x.$1 == f.age);
    final age = p != null && pilVrai(p['dateNaissance']) ? pilAge(p['dateNaissance'], auj) : null;
    if (age == null || age < tr.$3 || age > tr.$4) return false;
  }
  if (f.origine == 'externe' && r['origineDemande'] != 'externe') return false;
  if (f.origine == 'interne' && r['origineDemande'] == 'externe') return false;
  return true;
}

/// Le détail par examen : (examen, demandes), du plus demandé au moins demandé.
List<(String, int)> pilDetailExamens(Iterable<PilFiche> rows) {
  final g = pilGrouper(rows, (r) => pilCle(r['analyse']));
  return pilTriDesc([for (final e in g.entries) (e.key, e.value.length)], (x) => x.$2);
}

PilVue pilStatsExamens(Iterable<PilFiche> demandes, Iterable<PilFiche> patients, PilFiltreExamens f, DateTime auj) {
  final parPatient = <Object?, PilFiche>{for (final p in patients) p['id']: p};
  final rows = pilExamensRetenus(demandes, patients, f, auj);
  final rendus = rows.where((r) => resultatRendu(r['etatAnalyse'] as String?)).length;
  final v = PilVue(kpis: [
    PilKpi('Examens (population filtrée)', nombre(rows.length), ton: 'navy'),
    PilKpi('Résultats rendus', nombre(rendus), ton: 'succes'),
    PilKpi('Urgents', nombre(rows.where((r) => pilVrai(r['urgent'])).length), ton: 'attention'),
    PilKpi('Patients externes', nombre(rows.where((r) => r['origineDemande'] == 'externe').length), ton: 'info'),
  ]);
  final parCategorie = <String, int>{}, parService = <String, int>{};
  final parTranche = {for (final t in pilTranchesAgeExamens) t.$2: 0};
  for (final r in rows) {
    final c = pilVrai(r['categorie']) ? '${r['categorie']}' : 'Autres';
    parCategorie[c] = (parCategorie[c] ?? 0) + 1;
    final s = _serviceDemandeur(r).isNotEmpty ? _serviceDemandeur(r) : 'Non renseigné';
    parService[s] = (parService[s] ?? 0) + 1;
    final p = parPatient[r['patientId']];
    final age = p != null && pilVrai(p['dateNaissance']) ? pilAge(p['dateNaissance'], auj) : null;
    if (age != null) {
      for (final t in pilTranchesAgeExamens) {
        if (age >= t.$3 && age <= t.$4) {
          parTranche[t.$2] = parTranche[t.$2]! + 1;
          break;
        }
      }
    }
  }
  final cCat = pilTriDesc(parCategorie.entries, (e) => e.value), cSer = pilTriDesc(parService.entries, (e) => e.value);
  if (cCat.isNotEmpty) {
    v.graphiques.add(PilGraphique('barres', [for (final e in cCat) e.key], [PilSerie('Examens', [for (final e in cCat) e.value])], horizontal: true));
  }
  if (cSer.isNotEmpty) {
    v.graphiques.add(PilGraphique('barres', [for (final e in cSer) e.key], [PilSerie('Examens', [for (final e in cSer) e.value])], horizontal: true));
  }
  v.graphiques.add(PilGraphique('barres', [for (final t in pilTranchesAgeExamens) t.$2], [PilSerie('Examens', [for (final t in pilTranchesAgeExamens) parTranche[t.$2]!])]));
  v.tables.add(PilTable(null, ['EXAMEN', 'DEMANDES'], [for (final d in pilDetailExamens(rows)) [d.$1, nombre(d.$2)]]));
  return v;
}

// =====================================================================================================================================================
// m2-stats-echographie — « Statistiques de l'imagerie médicale »
// =====================================================================================================================================================

PilVue pilStatsImagerie(Iterable<PilFiche> demandes, Iterable<PilFiche> comptesRendus) {
  final crs = comptesRendus.toList();
  final rendus = crs.where((r) => r['statut'] == 'rendu').toList();
  final obst = crs.where((r) => RegExp('OBS').hasMatch(pilVrai(r['examenCode']) ? '${r['examenCode']}' : '')).length;
  final parId = <Object?, PilFiche>{for (final d in demandes) d['id']: d};
  // Le délai demande → rendu, sur les seules paires TRACÉES.
  final delais = <double>[];
  for (final r in rendus) {
    if (!pilVrai(r['demandeImagerieId'])) continue;
    final d = parId[r['demandeImagerieId']];
    if (d == null || !pilVrai(d['dateHeure']) || !pilVrai(r['renduLe'])) continue;
    final a = DateTime.tryParse('${d['dateHeure']}'), b = DateTime.tryParse('${r['renduLe']}');
    if (a == null || b == null) continue;
    final h = b.difference(a).inMilliseconds / 36e5;
    if (h >= 0 && h < 24 * 30) delais.add(h);
  }
  final delaiMoyen = delais.isNotEmpty ? arrondiJs(delais.fold(0.0, (a, x) => a + x) / delais.length).toInt() : null;
  final v = PilVue(kpis: [
    PilKpi('Comptes rendus émis', nombre(crs.length), ton: 'navy'),
    PilKpi('Rendus au prescripteur', nombre(rendus.length), ton: 'succes'),
    PilKpi('Part obstétricale', crs.isNotEmpty ? pourcent(obst / crs.length * 100) : '—', ton: 'info'),
    PilKpi('Délai moyen demande → rendu', delaiMoyen == null ? '—' : '${nombre(delaiMoyen)} h',
        indice: delaiMoyen == null ? 'Aucune paire demande/CR tracée' : '${delais.length} paire(s) tracée(s)'),
  ]);
  final parExamen = <String, int>{};
  for (final r in crs) {
    final k = pilVrai(r['examen']) ? '${r['examen']}' : (pilVrai(r['examenCode']) ? '${r['examenCode']}' : 'undefined');
    parExamen[k] = (parExamen[k] ?? 0) + 1;
  }
  final cles = pilTriDesc(parExamen.entries, (e) => e.value);
  final parMois = <String, int>{};
  for (final r in crs) {
    final m = pilMois(r['date']);
    if (m.isNotEmpty) parMois[m] = (parMois[m] ?? 0) + 1;
  }
  final mois = pilClesTriees(parMois.keys);
  final six = mois.length > 6 ? mois.sublist(mois.length - 6) : mois;
  if (cles.isNotEmpty) {
    v.graphiques.add(PilGraphique('barres', [for (final e in cles) e.key], [PilSerie('Comptes rendus', [for (final e in cles) e.value])], horizontal: true));
  }
  if (six.isNotEmpty) {
    v.graphiques.add(PilGraphique('barres', six, [PilSerie('Comptes rendus', [for (final m in six) parMois[m]!])]));
  }
  final parReal = <String, int>{};
  for (final r in crs) {
    final k = pilVrai(r['realisateur']) ? '${r['realisateur']}' : '—';
    parReal[k] = (parReal[k] ?? 0) + 1;
  }
  v.classements.add(PilClassement([for (final e in pilTriDesc(parReal.entries, (e) => e.value)) (e.key, e.value)]));
  return v;
}

// =====================================================================================================================================================
// m2-stats-consultations — par praticien (et son service à l'organigramme), par type, dans le temps
// =====================================================================================================================================================

PilVue pilStatsConsultations(Iterable<PilFiche> consultations, Iterable<PilFiche> personnel, String du, String au, DateTime auj) {
  final rows = [for (final r in consultations) if (pilDansPlage(r['date'], du, au)) r];
  final agents = <String, PilFiche>{for (final a in personnel) '${a['nomComplet']}': a};
  final moisCourant = iso(auj).substring(0, 7);
  final v = PilVue(kpis: [
    PilKpi('Consultations au registre', nombre(rows.length), ton: 'navy'),
    PilKpi('Ce mois-ci', nombre(rows.where((r) => pilMois(r['date']) == moisCourant).length), ton: 'info'),
    PilKpi('Praticiens actifs', nombre({for (final r in rows) pilCle(r['medecin'])}.length)),
    PilKpi('À domicile', nombre(rows.where((r) => r['type'] == 'Domicile').length)),
  ]);
  final parPraticien = <String, int>{};
  for (final r in rows) {
    final k = pilVrai(r['medecin']) ? '${r['medecin']}' : '—';
    parPraticien[k] = (parPraticien[k] ?? 0) + 1;
  }
  v.classements.add(PilClassement([
    for (final e in pilTriDesc(parPraticien.entries, (e) => e.value))
      (e.key + (agents[e.key] != null ? ' — ${pilVrai(agents[e.key]!['service']) ? agents[e.key]!['service'] : ''}' : ''), e.value)
  ]));
  final parType = <String, int>{};
  for (final r in rows) {
    final k = pilVrai(r['type']) ? '${r['type']}' : 'Consultation';
    parType[k] = (parType[k] ?? 0) + 1;
  }
  v.graphiques.add(PilGraphique('anneau', parType.keys.toList(), [PilSerie('', parType.values.toList())]));
  v.graphiques.add(_evolutionMensuelle(rows, 'date', 'Consultations'));
  return v;
}

/// « Évolution mensuelle » : les six derniers mois PORTANT des fiches (les clés `AAAA-MM`, triées).
PilGraphique _evolutionMensuelle(Iterable<PilFiche> rows, String champ, String libelle) {
  final parMois = <String, int>{};
  for (final r in rows) {
    final m = pilMois(r[champ]);
    if (m.isNotEmpty) parMois[m] = (parMois[m] ?? 0) + 1;
  }
  final mois = pilClesTriees(parMois.keys);
  final six = mois.length > 6 ? mois.sublist(mois.length - 6) : mois;
  return PilGraphique('barres', six, [PilSerie(libelle, [for (final m in six) parMois[m]!])]);
}

// =====================================================================================================================================================
// m3-stats-bloc — comptes rendus opératoires, d'anesthésie et CPA, calculés depuis les registres du bloc
// =====================================================================================================================================================

PilVue pilStatsBloc(Iterable<PilFiche> crOperatoires, Iterable<PilFiche> crAnesthesie, Iterable<PilFiche> cpa, String du, String au) {
  final cros = [for (final r in crOperatoires) if (pilDansPlage(r['dateOperation'], du, au)) r];
  final cras = [for (final r in crAnesthesie) if (pilDansPlage(r['dateOperation'], du, au)) r];
  final cpas = [for (final r in cpa) if (pilDansPlage(r['date'], du, au)) r];
  final avecCpa = {for (final r in cpas) pilCle(r['patientId'])};
  // Les interventions SANS CPA sont comptées — signalées, jamais bloquées : l'urgence n'attend pas une fiche.
  final sansCpa = cros.where((c) => pilVrai(c['patientId']) && !avecCpa.contains('${c['patientId']}')).length;
  // Un incident compte dès qu'il est NOMMÉ — « aucun incident » s'écrit et ne compte pas.
  final incidents = cras.where((r) => pilVrai(r['incidents']) && !RegExp(r'^aucun', caseSensitive: false).hasMatch('${r['incidents']}'.trim())).length;
  final v = PilVue(kpis: [
    PilKpi('Comptes rendus opératoires', nombre(cros.length), ton: 'navy'),
    PilKpi('Comptes rendus d’anesthésie', nombre(cras.length), ton: 'info'),
    PilKpi('CPA enregistrées', nombre(cpas.length)),
    PilKpi('Interventions sans CPA', nombre(sansCpa), indice: 'Signalées, jamais bloquées', ton: sansCpa > 0 ? 'danger' : 'succes'),
  ]);
  final parOp = <String, int>{};
  for (final r in cros) {
    final k = pilVrai(r['operateur']) ? '${r['operateur']}' : '—';
    parOp[k] = (parOp[k] ?? 0) + 1;
  }
  if (parOp.isNotEmpty) v.classements.add(PilClassement([for (final e in pilTriDesc(parOp.entries, (e) => e.value)) (e.key, e.value)]));
  final parTech = <String, int>{}, parConc = <String, int>{};
  for (final r in cras) {
    final k = pilVrai(r['technique']) ? '${r['technique']}' : '—';
    parTech[k] = (parTech[k] ?? 0) + 1;
  }
  for (final r in cpas) {
    final k = pilVrai(r['conclusion']) ? '${r['conclusion']}' : '—';
    parConc[k] = (parConc[k] ?? 0) + 1;
  }
  if (parTech.isNotEmpty) v.graphiques.add(PilGraphique('barres', parTech.keys.toList(), [PilSerie('CR', parTech.values.toList())], horizontal: true));
  if (parConc.isNotEmpty) v.graphiques.add(PilGraphique('anneau', parConc.keys.toList(), [PilSerie('', parConc.values.toList())]));
  v.kpis.addAll([
    PilKpi('Incidents per-opératoires NOMMÉS', nombre(incidents), ton: incidents > 0 ? 'attention' : 'succes'),
    PilKpi('Surveillances prolongées en réveil',
        nombre(cras.where((r) => r['decisionSortie'] == 'Surveillance prolongée en salle de réveil').length)),
  ]);
  return v;
}

// =====================================================================================================================================================
// m3-stats-hospitalisations — séjours, durée moyenne (séjours TERMINÉS), occupation (à une DATE)
// =====================================================================================================================================================

class PilHospitalisations {
  PilHospitalisations(this.vue, this.sejours, this.terminees, this.enCours, this.journees, this.dms, this.occupes, this.lits, this.parType);
  final PilVue vue;
  final int sejours, terminees, enCours, journees, occupes, lits;

  /// La durée moyenne de séjour (arrondie au dixième), sur les séjours TERMINÉS seulement.
  final num dms;
  final List<({String type, int tarif, int sejours, int journees, num dms, int produit})> parType;
}

num _dixieme(num x) => arrondiJs(x * 10) / 10;

/// Le parc de lits : celui du référentiel des chambres, jamais un nombre écrit à la main.
int pilTotalLits() => hosChambres.fold(0, (a, c) => a + c.lits.length);

/// [refMois] : l'ancre du graphique « Séjours par mois » (la maquette l'ancre au 1ᵉʳ août 2026 — E20 ; le poste passe son horloge).
PilHospitalisations pilStatsHospitalisations(Iterable<PilFiche> admissions, String du, String au, DateTime auj, {required DateTime refMois}) {
  final toutes = [for (final a in admissions) if (pilDansPlage(a['dateEntree'], du, au)) a];
  final terminees = toutes.where((a) => pilVrai(a['dateSortie'])).toList();
  final enCours = toutes.where((a) => !pilVrai(a['dateSortie'])).toList();
  int duree(PilFiche a) {
    final j = cpcJoursEntre(a['dateEntree'], pilVrai(a['dateSortie']) ? a['dateSortie'] : auj);
    return j < 1 ? 1 : j;
  }

  final journees = terminees.fold(0, (s, a) => s + duree(a));
  final dms = terminees.isNotEmpty ? _dixieme(journees / terminees.length) : 0;
  final lits = pilTotalLits();
  final occupes = admissions.where((a) => !pilVrai(a['dateSortie'])).length;
  final v = PilVue(kpis: [
    PilKpi('Séjours de la période', nombre(toutes.length), ton: 'navy'),
    PilKpi('Séjours terminés', nombre(terminees.length), ton: 'succes'),
    PilKpi('Journées d’hospitalisation', nombre(journees), indice: 'Sur les séjours terminés seulement', ton: 'info'),
    PilKpi('Durée moyenne de séjour', '${pilTexteNombre(dms)} j', indice: 'Séjours terminés — les séjours en cours en sont exclus', ton: 'attention'),
    PilKpi('Séjours en cours', nombre(enCours.length)),
    PilKpi('Taux d’occupation', lits > 0 ? pourcent(occupes / lits * 100) : '—',
        indice: '${nombre(occupes)} lit(s) occupé(s) sur ${nombre(lits)} — à ce jour', ton: occupes / (lits == 0 ? 1 : lits) > 0.8 ? 'danger' : 'succes'),
  ]);
  final parType = <({String type, int tarif, int sejours, int journees, num dms, int produit})>[];
  for (final t in hosTypesChambre) {
    final sel = toutes.where((a) => a['typeChambre'] == t.id).toList();
    final fin = sel.where((a) => pilVrai(a['dateSortie'])).toList();
    final j = fin.fold(0, (s, a) => s + duree(a));
    parType.add((type: t.label, tarif: t.tarif.toInt(), sejours: sel.length, journees: j, dms: fin.isNotEmpty ? _dixieme(j / fin.length) : 0, produit: j * t.tarif.toInt()));
  }
  v.tables.add(PilTable('Par type de chambre', ['TYPE', 'PRIX DE JOURNÉE', 'SÉJOURS', 'JOURNÉES', 'DURÉE MOYENNE', 'PRODUIT THÉORIQUE'], [
    for (final r in parType) [r.type, money(r.tarif, avecDevise: false), nombre(r.sejours), nombre(r.journees), '${pilTexteNombre(r.dms)} j', money(r.produit, avecDevise: false)]
  ]));
  final g = pilGrouper(toutes, (a) => pilVrai(a['diagnosticEntree']) ? '${a['diagnosticEntree']}' : 'Non renseigné');
  final rangs = pilTriDesc([
    for (final e in g.entries)
      (() {
        final fin = e.value.where((a) => pilVrai(a['dateSortie'])).toList();
        return (motif: e.key, nb: e.value.length, dms: fin.isNotEmpty ? _dixieme(fin.fold(0, (s, a) => s + duree(a)) / fin.length) : 0);
      })()
  ], (r) => r.nb);
  final huit = rangs.take(8).toList();
  if (rangs.isNotEmpty) {
    v.graphiques.add(PilGraphique('barres', [for (final r in huit) r.motif], [PilSerie('Séjours', [for (final r in huit) r.nb])], horizontal: true));
  }
  v.graphiques.add(pilSejoursParMois(toutes, refMois));
  v.tables.add(PilTable('Durée moyenne par diagnostic — sur les séjours terminés', ['DIAGNOSTIC D’ENTRÉE', 'SÉJOURS', 'DURÉE MOYENNE'], [
    for (final r in rangs.take(12)) [r.motif, nombre(r.nb), r.dms != 0 ? '${pilTexteNombre(r.dms)} j' : '—']
  ]));
  return PilHospitalisations(v, toutes.length, terminees.length, enCours.length, journees, dms, occupes, lits, parType);
}

/// Les graphiques « Séjours par mois » : [ref] est l'ancre du mois de référence (la maquette l'ancre au 1ᵉʳ août 2026 — E20).
PilGraphique pilSejoursParMois(Iterable<PilFiche> toutes, DateTime ref) {
  final m = pilParMois(toutes, 'dateEntree', nb: 8, ref: ref);
  return PilGraphique('ligne', m.etiquettes, [PilSerie('Séjours', m.valeurs)]);
}

/// Le cartouche de l'état imprimé « Statistiques des hospitalisations ».
List<(String, String)> pilCartoucheHospitalisations(PilHospitalisations h, String du, String au) => [
      ('Période', (du.isNotEmpty ? dateFR(DateTime.parse(du)) : 'Toute la période') + (au.isNotEmpty ? ' au ${dateFR(DateTime.parse(au))}' : '')),
      ('Séjours', nombre(h.sejours)),
      ('Séjours terminés', nombre(h.terminees)),
      ('Séjours en cours', nombre(h.enCours)),
      ('Journées d’hospitalisation', nombre(h.journees)),
      ('Durée moyenne de séjour', '${pilTexteNombre(h.dms)} jours'),
      ('Lits occupés', '${nombre(h.occupes)} / ${nombre(h.lits)}'),
    ];

// =====================================================================================================================================================
// m10-cout-agent — DEUX colonnes à ne JAMAIS additionner : le coût employeur et les retenues de l'agent
// =====================================================================================================================================================

class PilCoutAgent {
  PilCoutAgent(this.brut, this.patronale, this.vps, this.coutMensuel, this.ouvriere, this.ortbAnnuel, this.vue, this.bulletins);
  final num brut, patronale, vps, coutMensuel, ouvriere, ortbAnnuel;
  final PilVue vue;

  /// L'historique des paies : (période, brut, net payé).
  final List<(String, num, num)> bulletins;
}

bool _bulletinDe(PilFiche b, PilFiche a) =>
    (pilVrai(b['personnelId']) && b['personnelId'] == a['id']) ||
    (pilVrai(b['agentId']) && b['agentId'] == a['id']) ||
    (pilVrai(b['nomComplet']) && b['nomComplet'] == a['nomComplet']) ||
    (pilVrai(b['agent']) && b['agent'] == a['nomComplet']);

/// Le coût global d'un agent : le coût EMPLOYEUR (brut + CNSS patronale + VPS) et, à part, les retenues de l'AGENT (CNSS ouvrière, ORTB). L'ITS,
/// progressif, se lit sur le bulletin — le recalculer ici créerait une seconde vérité.
PilCoutAgent pilCoutAgent(PilFiche a, Iterable<PilFiche> bulletins, String du, String au) {
  final brut = pilN(a['salaireBase']);
  final patronale = arrondiJs(brut * paiCnssPatronale / 100);
  final vps = arrondiJs(brut * paiVpsTaux / 100);
  final cout = brut + patronale + vps;
  final ouvriere = arrondiJs(brut * paiCnssOuvriere / 100);
  final ortb = 1000 + (brut > paiSeuilTele ? 3000 : 0);
  final v = PilVue(kpis: [
    PilKpi('Salaire brut mensuel', money(brut), ton: 'navy'),
    PilKpi('Coût employeur mensuel', money(cout), indice: 'Brut + CNSS patronale + VPS', ton: 'info'),
    PilKpi('Coût employeur annuel', money(cout * 12)),
    PilKpi('ORTB annuel (retenue agent)', money(ortb), indice: brut > 60000 ? 'Radio 1 000 + Télé 3 000 — elles se CUMULENT' : 'Radio seule (brut ≤ 60 000)'),
  ]);
  v.tables.add(PilTable('Composition mensuelle', ['POSTE', 'QUI LE SUPPORTE', 'MONTANT'], [
    ['Salaire brut', 'Employeur', money(brut, avecDevise: false)],
    ['CNSS — part patronale ${pilTexteNombre(paiCnssPatronale)} %', 'Employeur', money(patronale, avecDevise: false)],
    ['VPS ${pilTexteNombre(paiVpsTaux)} %', 'Employeur', money(vps, avecDevise: false)],
    ['COÛT EMPLOYEUR', '', money(cout, avecDevise: false)],
    ['CNSS — part ouvrière ${pilTexteNombre(paiCnssOuvriere)} %', 'Retenue à l’agent', money(ouvriere, avecDevise: false)],
  ]));
  final lignes = <(String, num, num)>[];
  for (final b in bulletins) {
    if (!_bulletinDe(b, a)) continue;
    // La plage filtre l'historique : la période du bulletin (mois/année).
    String? d;
    if (pilVrai(b['date'])) {
      d = pilJour(b['date']);
    } else if (b['annee'] != null && b['mois'] != null) {
      d = '${b['annee']}-${(pilN(b['mois']).toInt() + 1).toString().padLeft(2, '0')}-01';
    }
    if (d != null && !pilDansPlage(d, du, au)) continue;
    final periode = pilVrai(b['periode'])
        ? '${b['periode']}'
        : (b['mois'] != null ? moisAnnee(DateTime(pilVrai(b['annee']) ? pilN(b['annee']).toInt() : 2026, pilN(b['mois']).toInt() + 1)) : '—');
    lignes.add((periode, pilN(b['brut']), pilN(b['net'])));
  }
  v.tables.add(PilTable(null, ['PÉRIODE', 'BRUT', 'NET PAYÉ'], [for (final l in lignes) [l.$1, money(l.$2, avecDevise: false), money(l.$3, avecDevise: false)]]));
  return PilCoutAgent(brut, patronale, vps, cout, ouvriere, ortb, v, lignes);
}

/// La note « N avance(s) sur salaire au dossier » (elles transitent : ni recette ni charge), ou `null`.
String? pilNoteAvances(Iterable<PilFiche> avances, PilFiche a) {
  final n = avances.where((x) => (pilVrai(x['personnelId']) && x['personnelId'] == a['id']) || (pilVrai(x['agent']) && x['agent'] == a['nomComplet'])).length;
  if (n == 0) return null;
  return '${nombre(n)} avance(s) sur salaire au dossier — elles transitent, elles ne sont ni recette ni charge : le détail vit à l’écran des avances (M11).';
}

// =====================================================================================================================================================
// m12-rentabilite-groupes — recettes par groupe de prestation FACE AUX charges par centre de coûts, rapprochement ARRÊTÉ
// =====================================================================================================================================================

/// `D.groupeDuSecteur(cle)` : le groupe de prestation portant ce libellé de secteur, ou `null` (un support — Direction, entretien, ambulance — n'est pas
/// un secteur : ses charges sont TRANSVERSES, jamais ventilées).
String? pilGroupeDuSecteur(Object? cle) {
  final lib = secteurNormalise(cle);
  if (lib == null) return null;
  for (final g in groupesPrestation) {
    if (g.label == lib) return g.id;
  }
  return null;
}

class PilRentabilite {
  PilRentabilite(this.vue, this.totalRecettes, this.totalCharges, this.transverses, this.brouillons);
  final PilVue vue;
  final double totalRecettes, totalCharges, transverses;
  final int brouillons;
}

PilRentabilite pilRentabilite({
  required Iterable<PilFiche> factures,
  required Iterable<PilFiche> ecritures,
  required Iterable<PilFiche> centresCouts,
  Map<String, String?> secteurParCode = const {},
  required String du,
  required String au,
}) {
  final parGroupe = {for (final g in groupesPrestation) g.id: 0.0};
  var horsGroupe = 0.0;
  for (final fa in factures) {
    if (!pilDansPlage(fa['date'], du, au)) continue;
    for (final raw in (fa['lignes'] as List? ?? const [])) {
      final l = (raw as Map).cast<String, Object?>();
      // LA LIGNE ENTIÈRE est passée au moteur : un accouchement et un pansement sont tous deux des « actes », seul le secteur du catalogue les sépare.
      final g = groupePrestation(l['categorie'], l, secteurParCode);
      if (g != null && parGroupe.containsKey(g.id)) {
        parGroupe[g.id] = parGroupe[g.id]! + pilN(l['montant']);
      } else {
        horsGroupe += pilN(l['montant']);
      }
    }
  }
  bool classe6(PilFiche e) => '${e['compte'] ?? ''}'.startsWith('6');
  final validees = [for (final e in ecritures) if (pilDansPlage(e['date'], du, au) && e['statut'] == 'validee' && classe6(e)) e];
  final brouillons = ecritures.where((e) => pilDansPlage(e['date'], du, au) && e['statut'] == 'brouillon' && classe6(e)).length;
  final parCentre = <String, double>{};
  for (final e in validees) {
    final c = pilVrai(e['centreCout']) ? '${e['centreCout']}' : 'non_impute';
    parCentre[c] = (parCentre[c] ?? 0) + pilN(e['debit']) - pilN(e['credit']);
  }
  // LE LIBELLÉ, PAS L'IDENTIFIANT : le centre se lit dans le référentiel administrable, celui-là même que le comptable choisit en saisissant son écriture.
  String libelleCentre(String cle) {
    if (cle == 'non_impute') return 'Non imputé';
    for (final c in centresCouts) {
      if (c['code'] == cle) return '${c['libelle']}';
    }
    for (final c in cpaCentresCout) {
      if (c.$1 == cle) return c.$2;
    }
    return cle;
  }

  final totalRecettes = parGroupe.values.fold(0.0, (a, x) => a + x) + horsGroupe;
  final totalCharges = parCentre.values.fold(0.0, (a, x) => a + x);
  final v = PilVue(kpis: [
    PilKpi('Recettes facturées (lignes)', money(totalRecettes), ton: 'navy'),
    PilKpi('Charges validées (classe 6)', money(totalCharges), ton: 'info'),
    PilKpi('Écart brut global', money(totalRecettes - totalCharges),
        indice: 'Deux registres distincts — la répartition se lit, pas le résultat', ton: totalRecettes - totalCharges >= 0 ? 'succes' : 'danger'),
    PilKpi('Brouillons écartés', nombre(brouillons), indice: 'Un brouillon n’est pas un fait comptable'),
  ]);
  v.tables.add(PilTable('Recettes par groupe de prestation', ['GROUPE', 'RECETTES'], [
    for (final g in groupesPrestation) [g.label, money(parGroupe[g.id], avecDevise: false)],
    if (horsGroupe != 0) ['Hors groupe (catégorie non classée)', money(horsGroupe, avecDevise: false)],
  ]));
  // LE RAPPROCHEMENT ARRÊTÉ (01/09/2026) : chaque centre est rattaché à un groupe par le LIBELLÉ qu'il porte réellement sur les écritures ; les supports
  // restent TRANSVERSES, non ventilés — leur répartir des quotes-parts inventerait une clé qu'aucun document ne donne.
  final chargesParGroupe = <String, double>{};
  var transverses = 0.0;
  final rattachements = <List<String>>[];
  for (final e in parCentre.entries) {
    final g = pilGroupeDuSecteur(e.key) ?? pilGroupeDuSecteur(libelleCentre(e.key));
    if (g != null) {
      chargesParGroupe[g] = (chargesParGroupe[g] ?? 0) + e.value;
    } else {
      transverses += e.value;
    }
    rattachements.add([
      libelleCentre(e.key),
      money(e.value, avecDevise: false),
      g != null ? groupesPrestation.firstWhere((x) => x.id == g).label : 'Transverse — non ventilé'
    ]);
  }
  v.tables.add(PilTable('Rapprochement ARRÊTÉ le 01/09/2026 — centre par centre, contestable ligne à ligne', ['CENTRE DE COÛTS', 'CHARGES', 'RATTACHÉ AU GROUPE'], rattachements));
  v.tables.add(PilTable('Bénéfice brut par groupe — avant charges transverses', ['GROUPE', 'RECETTES', 'CHARGES RATTACHÉES', 'BÉNÉFICE BRUT'], [
    for (final g in groupesPrestation)
      [
        g.label,
        money(parGroupe[g.id], avecDevise: false),
        money(chargesParGroupe[g.id] ?? 0, avecDevise: false),
        money(parGroupe[g.id]! - (chargesParGroupe[g.id] ?? 0), avecDevise: false)
      ]
  ]));
  v.notes.add(pilNoteTransverses(transverses));
  return PilRentabilite(v, totalRecettes, totalCharges, transverses, brouillons);
}

String pilNoteTransverses(double transverses) =>
    'Les charges transverses (${money(transverses, avecDevise: false)} — administration, entretien, ambulance, non imputé) ne sont PAS ventilées : les répartir exigerait une clé qu’aucun document ne donne. Le bénéfice brut se lit AVANT elles — la ligne globale de l’en-tête les inclut.';

// =====================================================================================================================================================
// m4-stats-maternite — les indicateurs DHIS2/SNIS, calculés depuis les registres
// =====================================================================================================================================================

PilVue pilStatsMaternite({
  required Iterable<PilFiche> grossesses,
  required Iterable<PilFiche> accouchements,
  required Iterable<PilFiche> naissances,
  required Iterable<PilFiche> planification,
  required Iterable<PilFiche> sonu,
  required Iterable<PilFiche> curatifs,
}) {
  bool aSp(PilFiche g, String k) => (g['sp'] as List? ?? const []).contains(k);
  final gros = grossesses.toList(), nns = naissances.toList(), pfs = planification.toList();
  final sp3 = gros.where((g) => aSp(g, 'SP3')).length, sp5 = gros.where((g) => aSp(g, 'SP5')).length;
  final milda = gros.where((g) => pilVrai(g['milda'])).length, gar = gros.where((g) => pilVrai(g['gar'])).length;
  final acceptA = pfs.where((p) => p['acceptante'] == 'A').length;
  final mortNes = nns.where((n) => !pilVrai(n['vivant'])).length;
  final refTravail = curatifs.where((r) => pilVrai(r['urgenceMaternite'])).length;
  final refPec = curatifs.where((r) => r['urgenceMaternite'] == 'referee_pec').length;
  final sonuc = sonu.where((s) => (s['fonctions'] as List? ?? const []).any((n) => n is num && n >= 8)).length;
  final v = PilVue(kpis: [
    PilKpi('Couverture SP3', pilPctDe(sp3, gros.length), indice: '$sp3 / ${gros.length} grossesses suivies', ton: 'info'),
    PilKpi('Couverture MILDA', pilPctDe(milda, gros.length), indice: 'Indicateur DHIS2', ton: 'succes'),
    PilKpi('Grossesses à risque (GAR)', pilPctDe(gar, gros.length), indice: '$gar fiche(s)', ton: 'danger'),
    PilKpi('Nouvelles acceptantes PF', pilPctDe(acceptA, pfs.length), indice: '$acceptA « A » / ${pfs.length}', ton: 'navy'),
    PilKpi('Couverture SP5', pilPctDe(sp5, gros.length), ton: 'info'),
    PilKpi('Mort-nés', nombre(mortNes), indice: 'sur ${nns.length} naissances', ton: mortNes > 0 ? 'danger' : 'succes'),
    PilKpi('Femmes en travail référées', nombre(refTravail), indice: '$refPec prise(s) en charge à l’arrivée', ton: 'attention'),
    PilKpi('Urgences SONUC', nombre(sonuc), ton: 'danger'),
  ]);
  final types = pilGrouper(accouchements, (a) => pilCle(pilVrai(a['type']) ? a['type'] : a['voie']));
  v.graphiques.add(PilGraphique('barres', types.keys.toList(), [PilSerie('Accouchements', [for (final e in types.values) e.length])]));
  final meth = pilGrouper(pfs, (p) => pilCle(p['methodeLabel']));
  v.graphiques.add(PilGraphique('barres', meth.keys.toList(), [PilSerie('Consultations', [for (final e in meth.values) e.length])], horizontal: true));
  v.tables.add(PilTable('Vaccination et soins de naissance (J0)', ['SOIN', 'FAITS', 'COUVERTURE'], [
    for (final s in const [('Vitamine K1', 'vitK1'), ('VPO0', 'vpo0'), ('BCG', 'bcg'), ('Hépatite B J0', 'hepB0')])
      (() {
        final n = nns.where((x) => pilVrai(x[s.$2])).length;
        return [s.$1, '$n', pilPctDe(n, nns.length)];
      })()
  ]));
  return v;
}
