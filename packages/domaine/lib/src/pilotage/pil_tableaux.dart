/// PILOTAGE — les TABLEAUX de la Direction et de l'administration : dash-direction, dash-admin, dash-da (« Statistiques de la Direction »), dash-croise
/// (« Tableau de bord dynamique croisé ») et m12-tableau-decisionnel (la grille objectif fixé / réel atteint).
///
/// AUCUN OBJECTIF N'EST DOCUMENTÉ : ni le cahier des charges, ni le rapport de cadrage, ni la liasse déposée ne fixent de cible de DSO, de taux
/// d'occupation ou de rotation. Les huit cibles de `D.OBJECTIFS_PILOTAGE` sont des PROPOSITIONS (`aValider`), corrigeables à l'onglet « Objectifs &
/// seuils » ; corriger une cible l'ARRÊTE. `sens` dit de quel côté se trouve la réussite. « Non calculable » (`indisponible`) n'est JAMAIS zéro : un
/// indicateur dont la donnée manque le dit, il ne se colore pas en échec.
///
/// Rejoués sur `test/vecteurs/pilotage.json` (écrans réels pilotés dans Chrome + moteur `PR.indicateursPilotage`).
library;

import 'dart:convert';

import '../comptabilite/cpc_bfr.dart';
import '../comptabilite/cpc_donnees.dart' show cpcObjectifsPilotageJson;
import '../format/format_fr.dart';
import '../format/js.dart';
import '../hospitalisation/hos_regles.dart' show hosChambres;
import '../referentiels/regles.dart' show secteurNormalise;
import '../stock/points.dart' show MethodeValorisation, valeurUnitaire;
import 'pil_vue.dart';

// =====================================================================================================================================================
// LES INDICATEURS DE PILOTAGE (PR.indicateursPilotage) — la grille « objectif fixé / réel atteint »
// =====================================================================================================================================================

/// `D.AXES_PILOTAGE` : (identifiant, libellé).
const List<(String, String)> pilAxesPilotage = [
  ('tresorerie', 'Trésorerie & BFR'),
  ('activite', 'Activité clinique'),
  ('logistique', 'Logistique & pharmacie'),
  ('administratif', 'Performance administrative'),
];

String pilLibelleAxe(Object? id) {
  for (final a in pilAxesPilotage) {
    if (a.$1 == id) return a.$2;
  }
  return '$id';
}

class PilIndicateur {
  const PilIndicateur({
    required this.id,
    required this.axe,
    required this.label,
    required this.unite,
    required this.cible,
    required this.alerte,
    required this.sens,
    required this.aValider,
    required this.reel,
    required this.etat,
    required this.ecart,
    this.source,
    this.aide,
  });
  final String id, axe, label, unite, sens, etat;
  final num cible, alerte;
  final bool aValider;
  final String? source, aide;

  /// `null` = non calculable (la donnée manque) — jamais zéro.
  final num? reel, ecart;
}

bool _dans(Object? d, ({String debut, String fin, int jours}) f) {
  final x = pilJour(d);
  return x.isNotEmpty && x.compareTo(f.debut) >= 0 && x.compareTo(f.fin) <= 0;
}

/// `PR.sortiesValorisees(f)` : les sorties valorisées de la période — le dénominateur de la rotation.
double pilSortiesValorisees({
  required Iterable<PilFiche> mouvements,
  required Iterable<PilFiche> produits,
  required ({String debut, String fin, int jours}) fenetre,
  MethodeValorisation methode = MethodeValorisation.prixVente,
}) {
  final prods = {for (final p in produits) p['id']: p};
  var s = 0.0;
  for (final m in mouvements) {
    if (!cpcSortiesStock.contains(m['type']) || !_dans(m['date'], fenetre)) continue;
    final p = prods[m['produitId']];
    s += pilN(m['quantite']) * (p != null ? valeurUnitaire(p, methode) : 0);
  }
  return s;
}

/// `PR.delaiTransmission()` : le délai moyen de transmission des pièces assureur, en jours ; `null` sans facture mère datée.
int? pilDelaiTransmission(Iterable<PilFiche> facturesMere) {
  final meres = [for (final m in facturesMere) if (pilVrai(m['dateEmission']) && pilVrai(m['fin'])) m];
  if (meres.isEmpty) return null;
  final s = meres.fold(0.0, (a, m) {
    final j = cpcJoursEntre(m['fin'], m['dateEmission']);
    return a + (j > 0 ? j : 0);
  });
  return arrondiJs(s / meres.length).toInt();
}

/// `PR.indicateursPilotage({fin, jours})` : chaque ligne porte son état — atteint · vigilance · alerte · indisponible. INDISPONIBLE N'EST PAS ZÉRO.
List<PilIndicateur> pilIndicateurs({
  required Iterable<PilFiche> factures,
  required Iterable<PilFiche> produits,
  required Iterable<PilFiche> facturesFournisseurs,
  required Iterable<PilFiche> mouvements,
  required Iterable<PilFiche> admissions,
  required Iterable<PilFiche> facturesMere,
  required Iterable<PilFiche> objectifs,
  required DateTime auj,
  Object? fin,
  int? jours,
  MethodeValorisation methode = MethodeValorisation.prixVente,
}) {
  final f = cpcFenetre(fin: fin, jours: jours, auj: auj);
  final b = cpcBfr(factures: factures, produits: produits, facturesFournisseurs: facturesFournisseurs, auj: auj, fin: fin, jours: jours, methode: methode);
  final reels = <String, num?>{};
  reels['dso'] = b.caPeriode > 0 ? arrondiJs(b.creances / (b.caPeriode / f.jours)).toInt() : null;
  reels['bfr_jours'] = b.bfrJours;
  // L'ancienneté de la créance la plus vieille encore ouverte : c'est elle qui déclenche la relance, pas la moyenne.
  final assurees = [for (final x in factures) if (pilVrai(x['assureur']) && pilN(x['partAssurance']) > 0) x];
  reels['creance_agee'] = assurees.isNotEmpty ? assurees.map((x) => cpcJoursEntre(x['date'], f.fin)).reduce((a, c) => a > c ? a : c) : null;
  final lits = hosChambres.fold(0, (n, ch) => n + ch.lits.length);
  final occupes = admissions.where((a) => a['statut'] == 'en_cours').length;
  reels['occupation_lits'] = lits > 0 ? arrondiJs(occupes / lits * 1000) / 10 : null;
  final sorties = pilSortiesValorisees(mouvements: mouvements, produits: produits, fenetre: f, methode: methode);
  reels['rotation_stock'] = b.stocks > 0 && sorties > 0 ? arrondiJs(sorties * (365 / f.jours) / b.stocks * 10) / 10 : null;
  reels['couverture_stock'] = sorties > 0 ? arrondiJs(b.stocks / (sorties / f.jours)).toInt() : null;
  reels['delai_transmission'] = pilDelaiTransmission(facturesMere);
  final normalisables = [for (final x in factures) if (pilVrai(x['numeroMecef'])) x];
  reels['facturation_normalisee'] =
      normalisables.isNotEmpty ? arrondiJs(normalisables.where((x) => x['statutMecef'] == 'valide').length / normalisables.length * 1000) / 10 : null;
  return [
    for (final o in cpcObjectifsPilotage(objectifs))
      (() {
        final reel = reels['${o['id']}'];
        final cible = pilN(o['cible']), alerte = pilN(o['alerte']);
        final haut = o['sens'] == 'haut';
        var etat = 'indisponible';
        if (reel != null) {
          final atteint = haut ? reel >= cible : reel <= cible;
          final franchi = haut ? reel < alerte : reel > alerte;
          etat = atteint ? 'atteint' : (franchi ? 'alerte' : 'vigilance');
        }
        return PilIndicateur(
          id: '${o['id']}',
          axe: '${o['axe']}',
          label: '${o['label']}',
          unite: '${o['unite']}',
          cible: cible,
          alerte: alerte,
          sens: '${o['sens']}',
          aValider: pilVrai(o['aValider']),
          source: o['source'] as String?,
          aide: o['aide'] as String?,
          reel: reel,
          etat: etat,
          // L'écart n'a de sens que rapporté au bon côté : un DSO de 30 jours pour une cible de 45 est une AVANCE, pas un retard.
          ecart: reel == null ? null : (haut ? reel - cible : cible - reel),
        );
      })()
  ];
}

/// Le ton d'une ligne de la grille — vert atteint, orange vigilance, rouge alerte.
String pilTonIndicateur(String etat) => etat == 'atteint' ? 'succes' : (etat == 'vigilance' ? 'attention' : (etat == 'alerte' ? 'danger' : 'neutre'));

String pilLibelleEtat(String etat) =>
    etat == 'atteint' ? 'Objectif atteint' : (etat == 'vigilance' ? 'Sous surveillance' : (etat == 'alerte' ? 'Seuil d’alerte franchi' : 'Non calculable'));

/// La valeur, dans l'unité de son objectif.
String pilValeurIndicateur(PilIndicateur x) {
  if (x.reel == null) return '—';
  if (x.unite == '%') return pourcent(x.reel);
  if (x.unite == 'jours') return '${nombre(x.reel)} j';
  return '${nombre(x.reel, 1)} ${x.unite}';
}

/// L'objectif, dans l'unité de son indicateur.
String pilObjectifTexte(PilIndicateur x) => x.unite == '%' ? pourcent(x.cible) : '${nombre(x.cible)} ${x.unite}';

/// L'écart : signé, une décimale ; « — » si l'indicateur est non calculable.
String pilEcartTexte(PilIndicateur x) => x.ecart == null ? '—' : '${x.ecart! > 0 ? '+' : ''}${nombre(x.ecart, 1)}';

class PilCompteGrille {
  const PilCompteGrille(this.atteints, this.vigilance, this.alertes, this.indisponibles);
  final int atteints, vigilance, alertes, indisponibles;
}

PilCompteGrille pilCompteGrille(Iterable<PilIndicateur> ind) => PilCompteGrille(ind.where((x) => x.etat == 'atteint').length,
    ind.where((x) => x.etat == 'vigilance').length, ind.where((x) => x.etat == 'alerte').length, ind.where((x) => x.etat == 'indisponible').length);

/// La correction d'une cible : elle est ARRÊTÉE par la Direction (la mention « à valider » tombe, la date et l'auteur sont portés).
Map<String, Object?> pilArreterObjectif(Map<String, Object?> valeurs, {required DateTime auj, required String par}) =>
    {...valeurs, 'aValider': false, 'arreteLe': iso(auj), 'arretePar': par};

/// La semence des objectifs (les huit propositions).
List<PilFiche> pilObjectifsSemence() => [for (final o in (jsonDecode(cpcObjectifsPilotageJson) as List)) (o as Map).cast<String, Object?>()];

// =====================================================================================================================================================
// dash-direction — pilotage stratégique
// =====================================================================================================================================================

class PilDirection {
  PilDirection({
    required this.vue,
    required this.bfr,
    required this.ruptures,
    required this.perimes,
    required this.peremptionProche,
    required this.echeancesDepassees,
    required this.enAlerte,
    required this.indisponibles,
    required this.caMois,
    required this.encaisseMois,
    required this.lignesRapport,
  });

  /// Les douze indicateurs (huit du tableau, quatre du BFR), les quatre graphiques et le classement par service.
  final PilVue vue;
  final CpcBfr bfr;
  final int ruptures, perimes, peremptionProche, echeancesDepassees;

  /// Les libellés des indicateurs au-delà de leur seuil d'alerte.
  final List<String> enAlerte;
  final int indisponibles;
  final double caMois, encaisseMois;

  /// Le tableau de l'état « Rapport d'activité — Direction » : (indicateur, valeur).
  final List<(String, String)> lignesRapport;
}

PilDirection pilDirection({
  required Iterable<PilFiche> factures,
  required Iterable<PilFiche> consultations,
  required Iterable<PilFiche> produits,
  required Iterable<PilFiche> patients,
  required Iterable<PilFiche> admissions,
  required Iterable<PilFiche> personnel,
  required Iterable<PilFiche> lots,
  required Iterable<PilFiche> echeances,
  required Iterable<PilFiche> facturesFournisseurs,
  required Iterable<PilFiche> mouvements,
  required Iterable<PilFiche> facturesMere,
  required Iterable<PilFiche> objectifs,
  required DateTime auj,
  required String Function(String) libelleMode,
  required DateTime refMois,
  MethodeValorisation methode = MethodeValorisation.prixVente,
}) {
  bool duMois(PilFiche r, String k) {
    final d = DateTime.tryParse('${r[k]}');
    return d != null && d.year == auj.year && d.month == auj.month;
  }

  final fm = [for (final x in factures) if (duMois(x, 'date')) x];
  final ca = pilSomme(fm, 'montantTTC'), enc = pilSomme(fm, 'montantPaye');
  final valeurStock = produits.fold(0.0, (a, p) => a + pilN(p['stock']) * pilN(p['cump']));
  final lits = hosChambres.fold(0, (n, ch) => n + ch.lits.length);
  final occupes = admissions.where((a) => a['statut'] == 'en_cours').length;
  final masse = pilSomme(personnel, 'salaireBase');
  final consMois = consultations.where((c) => duMois(c, 'date')).length;
  final reste = pilSomme(factures, 'reliquat');
  final ruptures = produits.where((p) => p['seuilAlerte'] != null && pilN(p['stock']) <= pilN(p['seuilAlerte'])).length;
  final perimes = lots.where((l) => l['statut'] == 'perime').length, proches = lots.where((l) => l['statut'] == 'alerte').length;
  final jour = iso(auj);
  final echeancesDepassees = echeances.where((e) => !pilVrai(e['paye']) && (pilVrai(e['echeance']) ? '${e['echeance']}' : '').compareTo(jour) < 0).length;

  final b = cpcBfr(factures: factures, produits: produits, facturesFournisseurs: facturesFournisseurs, auj: auj, methode: methode);
  final ind = pilIndicateurs(
      factures: factures,
      produits: produits,
      facturesFournisseurs: facturesFournisseurs,
      mouvements: mouvements,
      admissions: admissions,
      facturesMere: facturesMere,
      objectifs: objectifs,
      auj: auj,
      methode: methode);
  final v = PilVue(kpis: [
    PilKpi('Chiffre d’affaires du mois', money(ca), ton: 'succes'),
    PilKpi('Montant encaissé', money(enc), indice: '${pourcent(ca != 0 ? enc / ca * 100 : 0)} du facturé', ton: 'navy'),
    PilKpi('Reste à recouvrer', money(reste), ton: 'attention'),
    PilKpi('Valeur du stock', money(valeurStock), ton: 'info'),
    PilKpi('Patients au répertoire', nombre(patients.length), ton: 'navy'),
    PilKpi('Consultations du mois', nombre(consMois), ton: 'info'),
    PilKpi('Lits occupés', '$occupes / $lits', indice: '${pourcent(occupes / lits * 100)} d’occupation', ton: 'navy'),
    PilKpi('Effectif', nombre(personnel.length), indice: 'Masse salariale ${money(masse)}'),
    ...pilKpisBfr(b),
  ]);
  // Évolution du chiffre d'affaires (12 mois) : facturé / encaissé.
  final s = pilParMois(factures, 'date', champValeur: 'montantTTC', ref: refMois);
  final e = pilParMois(factures, 'date', champValeur: 'montantPaye', ref: refMois);
  v.graphiques.add(PilGraphique('ligne', s.etiquettes, [PilSerie('Facturé', s.valeurs), PilSerie('Encaissé', e.valeurs)]));
  final parType = pilGrouper(factures, (x) => pilCle(x['type']));
  v.graphiques.add(PilGraphique('anneau', parType.keys.toList(), [PilSerie('', [for (final l in parType.values) pilSomme(l, 'montantTTC')])]));
  final c = pilParMois(consultations, 'date', ref: refMois), a = pilParMois(admissions, 'dateEntree', ref: refMois);
  v.graphiques.add(PilGraphique('barres', c.etiquettes, [PilSerie('Consultations', c.valeurs), PilSerie('Hospitalisations', a.valeurs)]));
  final parMode = pilGrouper(factures, (x) => pilCle(x['modePaiement']));
  v.graphiques.add(PilGraphique('anneau', [for (final k in parMode.keys) libelleMode(k)], [PilSerie('', [for (final l in parMode.values) pilSomme(l, 'montantPaye')])]));
  v.classements.add(PilClassement([for (final k in pilTriDesc(parType.entries, (x) => pilSomme(x.value, 'montantTTC'))) (k.key, pilSomme(k.value, 'montantTTC'))]));
  return PilDirection(
    vue: v,
    bfr: b,
    ruptures: ruptures,
    perimes: perimes,
    peremptionProche: proches,
    echeancesDepassees: echeancesDepassees,
    enAlerte: [for (final x in ind) if (x.etat == 'alerte') x.label],
    indisponibles: ind.where((x) => x.etat == 'indisponible').length,
    caMois: ca,
    encaisseMois: enc,
    lignesRapport: [
      ('Patients au répertoire', nombre(patients.length)),
      ('Consultations du mois', nombre(consMois)),
      ('Hospitalisations en cours', nombre(occupes)),
      ('Taux d’occupation des lits', pourcent(occupes / lits * 100)),
      ('Chiffre d’affaires du mois', money(ca)),
      ('Montant encaissé', money(enc)),
      ('Reste à recouvrer', money(reste)),
      ('Valeur du stock', money(valeurStock)),
      ('Produits sous seuil d’alerte', nombre(ruptures)),
      ('Effectif', '${nombre(personnel.length)} agents'),
      ('Masse salariale mensuelle', money(masse)),
    ],
  );
}

/// Le widget BFR posé sur les deux tableaux de la Direction (`widgetBFR`) : les quatre composantes.
List<PilKpi> pilKpisBfr(CpcBfr b) => [
      PilKpi('Besoin en fonds de roulement', money(b.bfr),
          indice: b.bfrJours != null ? '${nombre(b.bfrJours)} jours de CA' : 'CA nul sur la période', ton: b.bfr > 0 ? 'attention' : 'succes'),
      PilKpi('En-cours clients', money(b.creances), ton: 'info'),
      PilKpi('Stocks', money(b.stocks), ton: 'info'),
      PilKpi('Dettes fournisseurs', money(b.dettes)),
    ];

// =====================================================================================================================================================
// dash-admin — supervision technique
// =====================================================================================================================================================

PilVue pilAdmin({
  required Iterable<PilFiche> personnel,
  required Iterable<PilFiche> audit,
  required int patients,
  required int produits,
  required int analyses,
  required int assureurs,
  required int comptes,
}) {
  final echecs = audit.where((a) => a['succes'] == false).length;
  final v = PilVue(kpis: [
    PilKpi('Comptes utilisateurs', nombre(personnel.length), ton: 'navy'),
    PilKpi('Actions journalisées', nombre(audit.length), indice: 'RG-12 — aucune action anonyme', ton: 'info'),
    PilKpi('Tentatives infructueuses', nombre(echecs), ton: echecs > 0 ? 'attention' : 'succes'),
    // La maquette ÉCRIT « Aujourd'hui · 02h00 — automatique » : une constante, pas un état de sauvegarde (écart E1003).
    const PilKpi('Dernière sauvegarde', 'Aujourd’hui', indice: '02h00 — automatique', ton: 'succes'),
  ]);
  v.classements.add(PilClassement([
    ('Patients', patients),
    ('Produits', produits),
    ('Analyses de laboratoire', analyses),
    ('Compagnies d’assurance', assureurs),
    ('Comptes SYSCOHADA', comptes),
    ('Agents', personnel.length),
  ]));
  final g = pilGrouper(audit, (a) => pilCle(a['module']));
  v.graphiques.add(PilGraphique('anneau', g.keys.toList(), [PilSerie('', [for (final l in g.values) l.length])]));
  return v;
}

// =====================================================================================================================================================
// dash-da — « Statistiques de la Direction » : la caisse du jour et les cumuls par périodicité
// =====================================================================================================================================================

/// `PERIODICITES_DA` : (code, libellé).
const List<(String, String)> pilPeriodicitesDa = [
  ('jour', 'Jour'),
  ('semaine', 'Semaine'),
  ('mois', 'Mois'),
  ('trimestre', 'Trimestre'),
  ('semestre', 'Semestre'),
  ('annee', 'Année'),
];

DateTime _jourSeul(DateTime d) => DateTime(d.year, d.month, d.day);

/// Les bornes CALENDAIRES de la période qui CONTIENT la date d'ancrage (la semaine ouvrée commence le lundi).
({DateTime debut, DateTime fin}) pilBornesDa(String code, DateTime ancre) {
  final an = ancre.year, m = ancre.month;
  switch (code) {
    case 'jour':
      return (debut: DateTime(an, m, ancre.day), fin: DateTime(an, m, ancre.day));
    case 'semaine':
      final j = _jourSeul(ancre);
      final l = DateTime(j.year, j.month, j.day - ((j.weekday - 1) % 7));
      return (debut: l, fin: DateTime(l.year, l.month, l.day + 6));
    case 'mois':
      return (debut: DateTime(an, m, 1), fin: DateTime(an, m + 1, 0));
    case 'trimestre':
      final t = (m - 1) ~/ 3;
      return (debut: DateTime(an, t * 3 + 1, 1), fin: DateTime(an, t * 3 + 4, 0));
    case 'semestre':
      final se = m <= 6 ? 0 : 1;
      return (debut: DateTime(an, se * 6 + 1, 1), fin: DateTime(an, se * 6 + 7, 0));
    default:
      return (debut: DateTime(an, 1, 1), fin: DateTime(an, 12, 31));
  }
}

/// La période de MÊME NATURE qui précède — jamais « la même durée avant ».
({DateTime debut, DateTime fin}) pilBornesPrecedenteDa(String code, DateTime ancre) {
  final b = pilBornesDa(code, ancre);
  return pilBornesDa(code, DateTime(b.debut.year, b.debut.month, b.debut.day - 1));
}

/// L'intitulé exact de la période, celui qu'on relit sur un état.
String pilLibelleDa(String code, ({DateTime debut, DateTime fin}) b) {
  const mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  final d = b.debut;
  if (code == 'jour') return 'journée du ${dateFR(b.debut)}';
  if (code == 'mois') return '${mois[d.month - 1]} ${d.year}';
  if (code == 'trimestre') return 'T${(d.month - 1) ~/ 3 + 1} ${d.year}';
  if (code == 'semestre') return 'S${d.month <= 6 ? 1 : 2} ${d.year}';
  if (code == 'annee') return 'année ${d.year}';
  return 'semaine du ${dateFR(b.debut)} au ${dateFR(b.fin)}';
}

/// Les grandeurs suivies sur UNE période (`mesures(filtre)`).
class PilMesuresDa {
  PilMesuresDa(this.caFacture, this.encaisse, this.reliquat, this.pieces, this.medicaments, this.medicamentsMontant, this.actes, this.actesMontant,
      this.analyses, this.analysesMontant, this.consultations, this.consultationsMontant, this.hospitalisation, this.hospitalisationMontant);
  final double caFacture, encaisse, reliquat, medicamentsMontant, actesMontant, analysesMontant, consultationsMontant, hospitalisationMontant;
  final int pieces, medicaments, actes, analyses, consultations, hospitalisation;
}

PilMesuresDa pilMesuresDa({
  required Iterable<PilFiche> factures,
  required Iterable<PilFiche> demandesAnalyses,
  required Iterable<PilFiche> consultations,
  required bool Function(Object?) filtre,
}) {
  final fs = [for (final f in factures) if (filtre(f['date'])) f];
  final lignes = <PilFiche>[
    for (final f in fs) for (final l in (f['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()
  ];
  List<PilFiche> cat(String c) => [for (final l in lignes) if (l['categorie'] == c) l];
  double som(List<PilFiche> l) => l.fold(0.0, (a, x) => a + pilN(x['montant']));
  return PilMesuresDa(
    pilSomme(fs, 'montantTTC'),
    pilSomme(fs, 'montantPaye'),
    pilSomme(fs, 'reliquat'),
    fs.length,
    cat('medicament').length,
    som(cat('medicament')),
    cat('acte').length,
    som(cat('acte')),
    demandesAnalyses.where((x) => filtre(x['dateHeure'])).length,
    som(cat('analyse')),
    consultations.where((x) => filtre(x['date'])).length,
    som(cat('consultation')),
    cat('hospitalisation').length,
    som(cat('hospitalisation')),
  );
}

/// `entre(d1, d2)` : la date (10 premiers caractères) est dans [d1, d2[.
bool Function(Object?) pilEntre(String d1, String d2) => (dt) {
      final x = pilJour(dt);
      return x.compareTo(d1) >= 0 && x.compareTo(d2) < 0;
    };

class PilLigneDa {
  const PilLigneDa(this.grandeur, this.courant, this.precedent, this.argent, this.variation);
  final String grandeur;
  final num courant, precedent;
  final bool argent;

  /// Variation en pour cent (un dixième près) ; `null` sans base de comparaison (période précédente nulle).
  final num? variation;
  String get texteCourant => argent ? money(courant) : nombre(courant);
  String get textePrecedent => argent ? money(precedent) : nombre(precedent);
  String get texteVariation => variation == null ? 'pas de base de comparaison' : '${variation! > 0 ? '+' : ''}${pilTexteNombre(variation!)} %';
}

num? pilVariation(num actuel, num precedent) => precedent == 0 ? null : arrondiJs((actuel - precedent) / precedent * 1000) / 10;

class PilPanneauDa {
  PilPanneauDa(this.note, this.lignes, this.repartition, this.libelleCourant);
  final String note, libelleCourant;
  final List<PilLigneDa> lignes;
  final PilGraphique repartition;
}

/// Un onglet de périodicité : le total de sa période, sa variation, et la répartition du chiffre d'affaires.
PilPanneauDa pilPanneauDa({
  required String code,
  required DateTime ancre,
  required Iterable<PilFiche> factures,
  required Iterable<PilFiche> demandesAnalyses,
  required Iterable<PilFiche> consultations,
}) {
  final bc = pilBornesDa(code, ancre), bp = pilBornesPrecedenteDa(code, ancre);
  PilMesuresDa mes(({DateTime debut, DateTime fin}) b) => pilMesuresDa(
      factures: factures,
      demandesAnalyses: demandesAnalyses,
      consultations: consultations,
      filtre: pilEntre(iso(b.debut), iso(DateTime(b.fin.year, b.fin.month, b.fin.day + 1))));
  final c = mes(bc), p = mes(bp);
  PilLigneDa l(String g, num a, num b, bool argent) => PilLigneDa(g, a, b, argent, pilVariation(a, b));
  final lignes = [
    l('Chiffre d’affaires facturé', c.caFacture, p.caFacture, true),
    l('Montant encaissé', c.encaisse, p.encaisse, true),
    l('Reste dû', c.reliquat, p.reliquat, true),
    l('Pièces émises', c.pieces, p.pieces, false),
    l('Médicaments vendus (lignes)', c.medicaments, p.medicaments, false),
    l('Médicaments — montant', c.medicamentsMontant, p.medicamentsMontant, true),
    l('Actes vendus (lignes)', c.actes, p.actes, false),
    l('Actes — montant', c.actesMontant, p.actesMontant, true),
    l('Analyses réalisées', c.analyses, p.analyses, false),
    l('Analyses — montant', c.analysesMontant, p.analysesMontant, true),
    l('Consultations', c.consultations, p.consultations, false),
    l('Consultations — montant', c.consultationsMontant, p.consultationsMontant, true),
    l('Journées d’hospitalisation', c.hospitalisation, p.hospitalisation, false),
    l('Hospitalisation — montant', c.hospitalisationMontant, p.hospitalisationMontant, true),
  ];
  final note = 'Période retenue : ${pilLibelleDa(code, bc)} — du ${dateFR(bc.debut)} au ${dateFR(bc.fin)}. Comparée à ${pilLibelleDa(code, bp)} (du ${dateFR(bp.debut)} au ${dateFR(bp.fin)}).';
  return PilPanneauDa(
      note,
      lignes,
      PilGraphique(
          'barres',
          const ['Médicaments', 'Actes', 'Analyses', 'Consultations', 'Hospitalisation'],
          [PilSerie('Montant facturé', [c.medicamentsMontant, c.actesMontant, c.analysesMontant, c.consultationsMontant, c.hospitalisationMontant])],
          horizontal: true),
      pilLibelleDa(code, bc));
}

/// La caisse du jour : ce qui est RENTRÉ (encaissé) face au facturé — deux grandeurs distinctes.
List<PilKpi> pilKpisCaisseDuJour(PilMesuresDa jour) => [
      PilKpi('Encaissé aujourd’hui', money(jour.encaisse), indice: '${nombre(jour.pieces)} pièce(s) émise(s)', ton: 'succes'),
      PilKpi('Facturé aujourd’hui', money(jour.caFacture), indice: 'chiffre d’affaires, encaissé ou non', ton: 'navy'),
      PilKpi('Reste dû du jour', money(jour.reliquat), ton: jour.reliquat != 0 ? 'attention' : 'succes'),
      PilKpi('Analyses du jour', nombre(jour.analyses), ton: 'info'),
    ];

/// La plage libre (demande du 02/09/2026) : pièces émises dans la plage, montants réellement encaissés dessus.
List<PilKpi> pilKpisPlageDa(Iterable<PilFiche> factures, Iterable<PilFiche> depenses, String du, String au) {
  final fs = [for (final f in factures) if (pilDansPlage(f['date'], du, au)) f];
  final deps = [for (final d in depenses) if (pilDansPlage(d['date'], du, au)) d];
  return [
    PilKpi('Pièces émises sur la plage', nombre(fs.length), ton: 'navy'),
    PilKpi('Facturé (lignes)', money(pilSomme(fs, 'montantTTC')), ton: 'info'),
    PilKpi('Encaissé sur ces pièces', money(pilSomme(fs, 'montantPaye')), ton: 'succes'),
    PilKpi('Dépenses de la plage', money(pilSomme(deps, 'montant')), ton: 'attention'),
  ];
}

// =====================================================================================================================================================
// dash-croise — le tableau de bord dynamique croisé : une SOURCE, deux AXES, une MESURE, une période
// =====================================================================================================================================================

/// `CROISE_PERIODES` : (code, libellé, jours ; `null` = tout l'historique).
const List<(String, String, int?)> pilPeriodesCroise = [
  ('jour', 'Aujourd’hui', 1),
  ('semaine', '7 derniers jours', 7),
  ('mois', '30 derniers jours', 30),
  ('trimestre', '90 derniers jours', 90),
  ('semestre', '180 derniers jours', 180),
  ('annee', '12 derniers mois', 365),
  ('tout', 'Tout l’historique', null),
];

/// Ce que lisent les sources : les fiches ACTIVES des registres et l'horloge.
class PilDonneesCroise {
  PilDonneesCroise({
    required this.auj,
    this.consultations = const [],
    this.prescriptions = const [],
    this.demandesAnalyses = const [],
    this.mouvements = const [],
    this.produits = const [],
    this.factures = const [],
    this.patients = const [],
    this.personnel = const [],
    this.actes = const [],
    this.administrations = const [],
    this.planning = const [],
  });
  final DateTime auj;
  final Iterable<PilFiche> consultations, prescriptions, demandesAnalyses, mouvements, produits, factures, patients, personnel, actes, administrations, planning;

  PilFiche? agent(Object? id) {
    for (final a in personnel) {
      if (a['id'] == id) return a;
    }
    return null;
  }

  PilFiche? agentParNom(Object? nom) {
    for (final a in personnel) {
      if (a['nomComplet'] == nom) return a;
    }
    return null;
  }
}

class PilAxe {
  const PilAxe(this.libelle, this.valeur);
  final String libelle;
  final Object? Function(PilFiche r, PilDonneesCroise d) valeur;
}

class PilMesure {
  const PilMesure(this.libelle, this.unite, this.valeur);
  final String libelle;
  final String? unite;
  final num Function(PilFiche r) valeur;
}

class PilSource {
  const PilSource(this.code, this.libelle, this.lire, this.date, this.axes, this.mesures);
  final String code, libelle;
  final List<PilFiche> Function(PilDonneesCroise d) lire;
  final Object? Function(PilFiche r) date;
  final Map<String, PilAxe> axes;
  final Map<String, PilMesure> mesures;
}

String _moisCroise(Object? d) {
  if (!pilVrai(d)) return '—';
  final x = DateTime.tryParse('$d');
  return x == null ? '—' : moisAnnee(x);
}

String _trancheCroise(int? n) {
  if (n == null) return 'Non renseigné';
  if (n < 5) return '0 – 4 ans';
  if (n < 15) return '5 – 14 ans';
  if (n < 25) return '15 – 24 ans';
  if (n < 45) return '25 – 44 ans';
  if (n < 65) return '45 – 64 ans';
  return '65 ans et plus';
}

Object? _ou(Object? a, Object? b) => pilVrai(a) ? a : b;
num _un(PilFiche r) => 1;
num _nb(Object? v) => pilN(v);

PilFiche _ligneMap(Object? l) => (l as Map).cast<String, Object?>();

/// Les sources du croisement (`sourcesCroise()`), chacune avec ses axes et ses mesures — un montant ne s'additionne pas avec un effectif.
final List<PilSource> pilSourcesCroise = [
  PilSource(
    'consultations',
    'Consultations',
    (d) => d.consultations.toList(),
    (r) => r['date'],
    {
      'mois': PilAxe('Mois', (r, d) => _moisCroise(r['date'])),
      'medecin': PilAxe('Médecin', (r, d) => _ou(r['medecin'], '—')),
      'service': PilAxe('Service', (r, d) => _ou(r['service'], _ou(r['type'], '—'))),
      'motif': PilAxe('Motif', (r, d) => _ou(r['motif'], '—')),
    },
    {'nombre': PilMesure('Nombre de consultations', null, _un), 'montant': PilMesure('Montant facturé', 'FCFA', (r) => _nb(r['montant']))},
  ),
  PilSource(
    'prescriptionsSoins',
    'Soins prescrits',
    (d) => [for (final r in d.prescriptions) if (r['type'] == 'soins') r],
    (r) => r['date'],
    {
      'mois': PilAxe('Mois', (r, d) => _moisCroise(r['date'])),
      'secteur': PilAxe('Secteur destinataire', (r, d) => _ou(r['secteurDestinataire'], '—')),
      // Le SECTEUR d'origine, dit dans le vocabulaire des six.
      'origine': PilAxe('Secteur d’origine de la prescription', (r, d) => _ou(secteurNormalise(r['origine']), _ou(r['origine'], '—'))),
      'prescripteur': PilAxe('Prescripteur', (r, d) => _ou(r['prescripteur'], '—')),
      'modalite': PilAxe('Modalité', (r, d) => _ou(r['modalite'], '—')),
    },
    {
      'nombre': PilMesure('Nombre de prescriptions', null, _un),
      'lignes': PilMesure('Nombre d’actes', null, (r) => (r['lignes'] as List? ?? const []).length),
      'montant': PilMesure('Montant', 'FCFA', (r) => _nb(r['montant'])),
    },
  ),
  PilSource(
    'analyses',
    'Analyses de laboratoire',
    (d) => d.demandesAnalyses.toList(),
    (r) => r['dateHeure'],
    {
      'mois': PilAxe('Mois', (r, d) => _moisCroise(r['dateHeure'])),
      'analyse': PilAxe('Analyse', (r, d) => _ou(r['analyse'], '—')),
      'categorie': PilAxe('Section', (r, d) => _ou(r['categorie'], '—')),
      'prescripteur': PilAxe('Prescripteur', (r, d) => _ou(r['prescripteur'], '—')),
      'origine': PilAxe('Interne ou externe', (r, d) => RegExp('externe', caseSensitive: false).hasMatch(pilVrai(r['origineDemande']) ? '${r['origineDemande']}' : '') ? 'Externe' : 'Interne'),
      'etat': PilAxe('État', (r, d) => _ou(r['etatAnalyse'], '—')),
    },
    {'nombre': PilMesure('Nombre d’analyses', null, _un), 'montant': PilMesure('Montant', 'FCFA', (r) => _nb(r['prix']))},
  ),
  PilSource(
    'mouvements',
    'Mouvements de stock',
    (d) => d.mouvements.toList(),
    (r) => r['date'],
    {
      'mois': PilAxe('Mois', (r, d) => _moisCroise(r['date'])),
      'sens': PilAxe('Sens', (r, d) => r['sens'] == 'entree' ? 'Entrée' : 'Sortie'),
      'type': PilAxe('Type de mouvement', (r, d) => _ou(r['type'], '—')),
      'produit': PilAxe('Article', (r, d) => _ou(r['produit'], '—')),
      'famille': PilAxe('Famille d’article', (r, d) {
        for (final p in d.produits) {
          if (p['id'] == r['produitId']) return _ou(p['famille'], '—');
        }
        return '—';
      }),
    },
    {
      'nombre': PilMesure('Nombre de mouvements', null, _un),
      'quantite': PilMesure('Quantité', 'unités', (r) => _nb(r['quantite'])),
      'valeur': PilMesure('Valeur', 'FCFA', (r) => _nb(r['valeur'])),
    },
  ),
  PilSource(
    'factures',
    'Facturation',
    (d) => d.factures.toList(),
    (r) => r['date'],
    {
      'mois': PilAxe('Mois', (r, d) => _moisCroise(r['date'])),
      'nature': PilAxe('Nature', (r, d) => _ou(r['type'], _ou(r['nature'], '—'))),
      'assureur': PilAxe('Assureur', (r, d) => _ou(r['assureur'], 'Non assuré')),
      'statut': PilAxe('État du règlement', (r, d) => _ou(r['statut'], '—')),
    },
    {
      'nombre': PilMesure('Nombre de factures', null, _un),
      'montant': PilMesure('Montant total', 'FCFA', (r) => _nb(r['montantTTC'])),
      'encaisse': PilMesure('Montant encaissé', 'FCFA', (r) => _nb(r['montantPaye'])),
      'assureur': PilMesure('Part assureur', 'FCFA', (r) => _nb(r['partAssurance'])),
    },
  ),
  PilSource(
    'patients',
    'Patients',
    (d) => d.patients.toList(),
    (r) => _ou(r['creeLe'], r['dateCreation']),
    {
      'sexe': PilAxe('Sexe', (r, d) => r['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
      'age': PilAxe('Tranche d’âge', (r, d) => _trancheCroise(pilAge(r['dateNaissance'], d.auj))),
      'quartier': PilAxe('Quartier', (r, d) => _ou(r['quartier'], '—')),
      'assurance': PilAxe('Couverture', (r, d) => _ou(r['assureurNom'], _ou(r['assureur'], 'Non assuré'))),
      'groupe': PilAxe('Groupe sanguin', (r, d) => _ou(r['groupeSanguin'], '—')),
    },
    {'nombre': PilMesure('Nombre de patients', null, _un)},
  ),
  PilSource(
    'personnel',
    'Personnel',
    (d) => d.personnel.toList(),
    (r) => r['dateEmbauche'],
    {
      'service': PilAxe('Service', (r, d) => _ou(r['service'], '—')),
      'fonction': PilAxe('Fonction', (r, d) => _ou(r['fonction'], '—')),
      'sexe': PilAxe('Sexe', (r, d) => r['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
      'categorie': PilAxe('Catégorie', (r, d) => _ou(r['categorie'], '—')),
    },
    {'nombre': PilMesure('Effectif', null, _un), 'masse': PilMesure('Masse salariale de base', 'FCFA', (r) => _nb(r['salaireBase']))},
  ),
  // LES ACTES — la LIGNE, pas la pièce : une prescription porte plusieurs actes.
  PilSource(
    'actes',
    'Actes réalisés',
    (d) {
      final out = <PilFiche>[];
      final parCode = <Object?, PilFiche>{for (final a in d.actes) a['code']: a};
      for (final f in d.factures) {
        for (final raw in (f['lignes'] as List? ?? const [])) {
          final l = _ligneMap(raw);
          if (l['categorie'] != 'acte' && l['categorie'] != 'consultation') continue;
          final ref = pilVrai(l['acteCode']) ? parCode[l['acteCode']] : null;
          out.add({
            'date': f['date'],
            'acte': l['designation'],
            'secteur': ref != null ? ref['secteur'] : 'Non rattaché',
            'quantite': _nbOu1(l['quantite']),
            'montant': _nb(l['montant']),
            'praticien': _ou(f['medecin'], f['prescripteur']),
            'patientId': f['patientId'],
            'origine': 'Facturé',
          });
        }
      }
      for (final pr in d.prescriptions) {
        if (pr['type'] != 'soins') continue;
        for (final raw in (pr['lignes'] as List? ?? const [])) {
          final l = _ligneMap(raw);
          out.add({
            'date': pr['date'],
            'acte': _ou(l['libelle'], _ou(l['designation'], '—')),
            'secteur': _ou(pr['secteurDestinataire'], 'Non rattaché'),
            'quantite': _nbOu1(l['nbAdministrations']),
            'montant': _nb(l['montant']),
            'praticien': pr['prescripteur'],
            'patientId': pr['patientId'],
            'origine': 'Prescrit',
          });
        }
      }
      return out;
    },
    (r) => r['date'],
    {
      'acte': PilAxe('Acte', (r, d) => _ou(r['acte'], '—')),
      'secteur': PilAxe('Secteur', (r, d) => _ou(r['secteur'], '—')),
      'praticien': PilAxe('Médecin / prescripteur', (r, d) => _ou(r['praticien'], 'Non renseigné')),
      'serviceP': PilAxe('Service du praticien', (r, d) {
        if (!pilVrai(r['praticien'])) return 'Non renseigné';
        final a = d.agentParNom(r['praticien']);
        return a != null ? a['service'] : 'Hors effectif';
      }),
      'origine': PilAxe('Facturé ou prescrit', (r, d) => r['origine']),
      'mois': PilAxe('Mois', (r, d) => _moisCroise(r['date'])),
    },
    {
      'nombre': PilMesure('Nombre d’actes', null, (r) => pilVrai(r['quantite']) ? _nb(r['quantite']) : 1),
      'lignes': PilMesure('Nombre de lignes', null, _un),
      'montant': PilMesure('Montant', 'FCFA', (r) => _nb(r['montant'])),
    },
  ),
  // LES SOINS EXÉCUTÉS — ce qui a été fait, et par qui.
  PilSource(
    'soinsExecutes',
    'Soins exécutés',
    (d) => d.administrations.toList(),
    (r) => r['dateHeure'],
    {
      'executant': PilAxe('Exécutant (infirmier / sage-femme)', (r, d) => _ou(r['executant'], 'Non renseigné')),
      'soin': PilAxe('Soin', (r, d) => _ou(r['libelle'], '—')),
      'secteur': PilAxe('Secteur qui a servi', (r, d) {
        const lib = {'salle_soins': 'Salle de soins', 'hospitalisation': 'Hospitalisation', 'maternite': 'Maternité', 'bloc': 'Bloc opératoire'};
        return lib['${r['secteur']}'] ?? _ou(r['secteur'], '—');
      }),
      'modalite': PilAxe('Modalité', (r, d) => r['modalite'] == 'ambulatoire' ? 'Ambulatoire' : (r['modalite'] == 'hospitalier' ? 'Hospitalier' : _ou(r['modalite'], '—'))),
      'serviceE': PilAxe('Service de l’exécutant', (r, d) {
        final a = d.agentParNom(r['executant']);
        return a != null ? a['service'] : 'Non renseigné';
      }),
      'mois': PilAxe('Mois', (r, d) => _moisCroise(r['dateHeure'])),
    },
    {'nombre': PilMesure('Nombre d’administrations', null, _un), 'patients': PilMesure('Passages', null, _un)},
  ),
  PilSource(
    'gardes',
    'Gardes et vacations',
    (d) => [
      for (final r in d.planning)
        if (!RegExp(r'repos|cong', caseSensitive: false).hasMatch('${_ou(r['regimeLibelle'], _ou(r['type'], ''))}')) r
    ],
    (r) => r['date'],
    {
      'mois': PilAxe('Mois', (r, d) => _moisCroise(r['date'])),
      'agent': PilAxe('Agent', (r, d) {
        final a = d.agent(_ou(r['employeId'], r['personnelId']));
        return a != null ? a['nomComplet'] : _ou(r['agent'], '—');
      }),
      'service': PilAxe('Service', (r, d) {
        final a = d.agent(_ou(r['employeId'], r['personnelId']));
        return a != null ? a['service'] : '—';
      }),
      'regime': PilAxe('Type de vacation', (r, d) => _ou(r['regimeLibelle'], _ou(r['type'], '—'))),
    },
    {'nombre': PilMesure('Nombre de vacations', null, _un)},
  ),
];

num _nbOu1(Object? v) {
  final n = nombreOuZero(v);
  return n != 0 ? n : 1;
}

/// Le résultat d'un croisement.
class PilCroise {
  PilCroise(this.lignes, this.colonnes, this.table, this.totauxColonnes, this.total, this.effectif, this.mesure);
  final List<String> lignes, colonnes;
  final Map<String, Map<String, double>> table;
  final Map<String, double> totauxColonnes;
  final double total;
  final int effectif;
  final PilMesure mesure;

  double totalLigne(String l) => colonnes.fold(0.0, (a, c) => a + (table[l]![c] ?? 0));
}

/// `croiser()` : deux axes, une mesure, une période. [colonnes] vide : un seul total par ligne.
PilCroise pilCroiser({
  required PilSource source,
  required PilDonneesCroise donnees,
  required String lignes,
  String? colonnes,
  required String mesure,
  required String periode,
}) {
  final jours = pilPeriodesCroise.firstWhere((x) => x.$1 == periode).$3;
  final depuis = jours == null ? null : iso(DateTime(donnees.auj.year, donnees.auj.month, donnees.auj.day - jours));
  final rows = [
    for (final r in source.lire(donnees))
      if (depuis == null || (pilVrai(source.date(r)) && pilJour(source.date(r)).compareTo(depuis) >= 0)) r
  ];
  final axL = source.axes[lignes]!, axC = colonnes == null || colonnes.isEmpty ? null : source.axes[colonnes];
  final mes = source.mesures[mesure]!;
  final table = <String, Map<String, double>>{};
  final cols = <String, double>{};
  var total = 0.0;
  String t(Object? v) => pilVrai(v) ? '$v' : '—';
  for (final r in rows) {
    final l = t(axL.valeur(r, donnees));
    final c = axC != null ? t(axC.valeur(r, donnees)) : 'Total';
    final v = mes.valeur(r).toDouble();
    final ligne = table[l] ??= {};
    ligne[c] = (ligne[c] ?? 0) + v;
    cols[c] = (cols[c] ?? 0) + v;
    total += v;
  }
  return PilCroise(pilClesTriees(table.keys), pilClesTriees(cols.keys), table, cols, total, rows.length, mes);
}

/// Les lignes du tableau croisé, du total le plus grand au plus petit (les ex æquo gardent l'ordre alphabétique des lignes).
List<String> pilCroiseOrdre(PilCroise r) => pilTriDesc(r.lignes, (l) => r.totalLigne(l));

/// Les douze premières valeurs de l'axe en lignes.
List<(String, double)> pilCroiseTop(PilCroise r) => [for (final l in pilCroiseOrdre(r).take(12)) (l, r.totalLigne(l))];

String pilTexteMesure(PilMesure m, num v) => m.unite == 'FCFA' ? money(v) : nombre(v);
