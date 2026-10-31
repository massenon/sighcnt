/// TABLEAUX DE BORD PAR POSTE (DASH) — dix écrans de LECTURE de `prototype_html/assets/js/modules/dashboards.js` : médecin, infirmier, pharmacien,
/// biologiste, gestionnaire de stock, caissier, comptable, RH, accueil, agent administratif.
///
/// Tout est CALCULÉ depuis les collections, rien n'est fourni — SAUF ce que la maquette fournit elle-même (deux compteurs du laboratoire écrits en dur,
/// deux séries tirées au hasard : voir `docs/architecture/ECARTS-MAQUETTE.md` E920+), porté fidèlement et dit. Les fonctions prennent les
/// fiches du magasin telles quelles et rendent des nombres, des listes et des libellés déjà formatés (`C.num`, `C.money`) : l'écran n'a plus qu'à
/// les dessiner. Rejouées sur `test/vecteurs/tba_dash.json`, engendré en PILOTANT les dix écrans réels dans Chrome.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart' show trierPar;
import '../hospitalisation/hos_regles.dart' show hosTousLits;
import '../referentiels/regles.dart' show joursEntre, resultatRendu;
import '../rh/rha_regles.dart' show rhaFonctionLabel, rhaTypePlanningLabel;
import '../comptabilite/cpa_referentiels.dart' show cpaCentresCout;
import '../administration/adm_notes_donnees.dart' show admNs131, admNs132, AdmNoteService;

typedef FicheTba = Map<String, Object?>;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Briques communes
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un indicateur du tableau (`U.kpiGrid`) : libellé, valeur déjà formatée, indice facultatif.
class TbaKpi {
  const TbaKpi(this.libelle, this.valeur, {this.indice, this.ton = 'navy', this.icone = ''});
  final String libelle;
  final String valeur;
  final String? indice;

  /// Ton de la tuile (`navy`, `success`, `info`, `warning`, `danger`, `neutral`) et nom de l'icône de la maquette.
  final String ton;
  final String icone;
}

/// Le PREMIER REGARD : UNE question, son compte, le lien qui y mène. À zéro, [vide] énonce une phrase (champ obligatoire). Un premier regard dont le
/// [ecran] est nul (compte fermé) n'a pas de lien : le bandeau dit la décision et rien d'autre.
class TbaPremierRegard {
  const TbaPremierRegard({
    required this.valeur,
    required this.unite,
    required this.question,
    required this.vide,
    required this.ton,
    required this.icone,
    required this.note,
    this.ecran,
    this.lienLabel,
  });
  final int valeur;
  final String unite;
  final String question;
  final String vide;
  final String ton;
  final String icone;
  final String note;
  final String? ecran;
  final String? lienLabel;

  /// La phrase du bandeau : le compte et la question, ou l'énoncé positif quand il n'y a rien.
  String get ligne => valeur == 0 ? vide : '${nombre(valeur)} $unite — $question';
}

num _n(Object? v) => nombreOuZero(v);

/// `C.sum(arr, key)`.
num tbaSomme(Iterable<FicheTba> rows, Object? Function(FicheTba) cle) =>
    rows.fold<num>(0, (a, x) => a + _n(cle(x)));

DateTime? _d(Object? v) => v is DateTime ? v : (v == null ? null : DateTime.tryParse('$v'));

/// `duJour(rows, key)` : `C.iso(r[key]) === C.iso(AUJ)`.
List<FicheTba> tbaDuJour(Iterable<FicheTba> rows, String cle, DateTime auj) {
  final j = iso(auj);
  return [
    for (final r in rows)
      if (_d(r[cle]) case final d? when iso(d) == j) r
  ];
}

/// `duMois(rows, key)` : même année et même mois que le jour.
List<FicheTba> tbaDuMois(Iterable<FicheTba> rows, String cle, DateTime auj) => [
      for (final r in rows)
        if (_d(r[cle]) case final d? when d.year == auj.year && d.month == auj.month) r
    ];

/// `C.groupBy(rows, key)` : l'ordre des clés est celui de la première apparition ; une clé absente s'écrit « undefined » comme en JavaScript.
Map<String, List<FicheTba>> tbaGrouper(Iterable<FicheTba> rows, Object? Function(FicheTba) cle) {
  final g = <String, List<FicheTba>>{};
  for (final r in rows) {
    final k = cle(r);
    (g[k == null ? 'undefined' : '$k'] ??= []).add(r);
  }
  return g;
}

/// Nombre de lits : `D.CHAMBRES` (12 chambres, 19 lits).
int tbaTotalLits() => hosTousLits().length;

/// `stock <= seuilAlerte` : un seuil ABSENT ne compare rien (undefined), un seuil explicitement nul vaut zéro — comme en JavaScript.
bool tbaSousSeuil(FicheTba p) {
  if (!p.containsKey('seuilAlerte')) return false;
  final s = p['seuilAlerte'];
  final stock = p['stock'];
  if (stock == null && !p.containsKey('stock')) return false;
  return _n(stock) <= (s == null ? 0 : _n(s));
}

List<FicheTba> tbaRuptures(Iterable<FicheTba> produits) => [for (final p in produits) if (tbaSousSeuil(p)) p];
List<FicheTba> tbaPerimes(Iterable<FicheTba> lots) => [for (final l in lots) if (l['statut'] == 'perime') l];
List<FicheTba> tbaPeremptionProche(Iterable<FicheTba> lots) => [for (final l in lots) if (l['statut'] == 'alerte') l];

/// Le bandeau d'alertes transverse (stock, pharmacie) : (texte, ton, icône, écran) — vide quand tout va bien.
class TbaAlerte {
  const TbaAlerte(this.ton, this.icone, this.texte, this.ecran);
  final String ton;
  final String icone;
  final String texte;
  final String ecran;
}

List<TbaAlerte> tbaBandeauAlertes(Iterable<FicheTba> produits, Iterable<FicheTba> lots) {
  final r = tbaRuptures(produits), pe = tbaPerimes(lots), pp = tbaPeremptionProche(lots);
  return [
    if (r.isNotEmpty) TbaAlerte('danger', 'trending-down', '${r.length} produit(s) sous le seuil d’alerte', 'm6-alertes'),
    if (pe.isNotEmpty) TbaAlerte('danger', 'alert-octagon', '${pe.length} lot(s) périmé(s) à retourner', 'm6-lots'),
    if (pp.isNotEmpty) TbaAlerte('warning', 'clock', '${pp.length} lot(s) à péremption proche (FEFO)', 'm6-lots'),
  ];
}

/// Une série de graphique : libellé + valeurs.
class TbaSerie {
  const TbaSerie(this.libelle, this.donnees);
  final String libelle;
  final List<num> donnees;
}

/// Un graphique en barres / anneau / ligne : étiquettes + séries.
class TbaGraphique {
  const TbaGraphique(this.etiquettes, this.series);
  final List<String> etiquettes;
  final List<TbaSerie> series;
}

TbaGraphique _comptes(Map<String, List<FicheTba>> g, String serie) =>
    TbaGraphique(g.keys.toList(), [TbaSerie(serie, [for (final v in g.values) v.length])]);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// MÉDECIN
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `fileDuPraticien(nom)` : les tickets de consultation en attente. `praticien` est FACULTATIF (la file est souvent commune) : un ticket sans
/// praticien est une information, pas un oubli.
class TbaFilePraticien {
  const TbaFilePraticien(this.miens, this.communs, this.autres);
  final List<FicheTba> miens, communs, autres;
}

TbaFilePraticien tbaFileDuPraticien(Iterable<FicheTba> fileAttente, String nom) {
  final tous = [
    for (final t in fileAttente)
      if (t['poste'] == 'consultation' && t['etat'] == 'attente') t
  ];
  bool nomme(FicheTba t) => t['praticien'] != null && t['praticien'] != '';
  return TbaFilePraticien(
    [for (final t in tous) if (nomme(t) && t['praticien'] == nom) t],
    [for (final t in tous) if (!nomme(t)) t],
    [for (final t in tous) if (nomme(t) && t['praticien'] != nom) t],
  );
}

/// L'ordre du couloir : priorité (urgence vitale, urgence, rendez-vous, ordre d'arrivée), puis heure d'arrivée.
List<FicheTba> tbaOrdreCouloir(Iterable<FicheTba> tickets) {
  const rang = {'urgence_vitale': 0, 'urgence': 1, 'rdv': 2, 'ordre_arrivee': 3};
  final liste = tickets.toList();
  final indexes = [for (var i = 0; i < liste.length; i++) i];
  indexes.sort((a, b) {
    final ra = rang[liste[a]['priorite']] ?? 9, rb = rang[liste[b]['priorite']] ?? 9;
    if (ra != rb) return ra - rb;
    final c = _comparer('${liste[a]['arriveeLe'] ?? ''}', '${liste[b]['arriveeLe'] ?? ''}');
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in indexes) liste[i]];
}

/// `String.localeCompare` (simple comparaison de chaînes ISO ici : les heures d'arrivée sont des horodatages ISO).
int _comparer(String a, String b) => a.compareTo(b);

/// Libellé et ton du badge de priorité d'un ticket.
({String libelle, String ton}) tbaPriorite(Object? p) => switch (p) {
      'urgence_vitale' => (libelle: 'Urgence vitale', ton: 'danger'),
      'urgence' => (libelle: 'Urgence', ton: 'warning'),
      'rdv' => (libelle: 'Rendez-vous', ton: 'info'),
      _ => (libelle: 'Ordre d’arrivée', ton: 'neutral'),
    };

class TbaMedecin {
  const TbaMedecin({
    required this.premier,
    required this.kpis,
    required this.file,
    required this.recentes,
    required this.motifs,
    required this.diagnostics,
  });
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;
  final TbaFilePraticien file;

  /// Les dix dernières consultations (date décroissante).
  final List<FicheTba> recentes;

  /// Motifs les plus fréquents (huit), (libellé, compte).
  final List<(String, int)> motifs;

  /// Diagnostics posés : les six premières clés de `groupBy(diagnostic)`.
  final List<(String, int)> diagnostics;
}

TbaMedecin tbaMedecin({
  required Iterable<FicheTba> demandesAnalyses,
  required Iterable<FicheTba> fileAttente,
  required Iterable<FicheTba> consultations,
  required Iterable<FicheTba> admissions,
  required String nom,
  required DateTime auj,
}) {
  final rendus = demandesAnalyses.where((d) => resultatRendu(d['etatAnalyse'] as String?)).length;
  final cs = consultations.toList();
  final occ = admissions.where((a) => a['statut'] == 'en_cours').length;
  final motifs = tbaGrouper(cs, (c) => c['motif']);
  final classes = trierPar(motifs.entries.toList(), (e) => e.value.length, descendant: true).take(8);
  final diag = tbaGrouper(cs, (c) => c['diagnostic']);
  return TbaMedecin(
    premier: TbaPremierRegard(
      valeur: rendus,
      unite: 'résultat(s) rendu(s)',
      question: 'vous attendent',
      vide: 'Aucun résultat en attente de lecture.',
      ton: 'info',
      icone: 'flask-conical',
      ecran: 'm5-resultats',
      lienLabel: 'Lire les résultats',
      note: 'Un résultat n’est visible qu’après validation biologique : ceux-ci le sont.',
    ),
    kpis: [
      TbaKpi('Consultations du jour', nombre(tbaDuJour(cs, 'date', auj).length), ton: 'navy', icone: 'stethoscope'),
      TbaKpi('En attente', nombre(cs.where((c) => c['statut'] == 'planifiee').length), ton: 'warning', icone: 'clock'),
      TbaKpi('Patients hospitalisés', nombre(occ), ton: 'info', icone: 'bed-double'),
      TbaKpi('Consultations du mois', nombre(tbaDuMois(cs, 'date', auj).length), ton: 'success', icone: 'calendar-check'),
    ],
    file: tbaFileDuPraticien(fileAttente, nom),
    recentes: trierPar(cs, (c) => c['date'], descendant: true).take(10).toList(),
    motifs: [for (final e in classes) (e.key, e.value.length)],
    diagnostics: [for (final e in diag.entries.take(6)) (e.key, e.value.length)],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// INFIRMIER / SAGE-FEMME
// ---------------------------------------------------------------------------------------------------------------------------------------------

class TbaInfirmier {
  const TbaInfirmier({required this.premier, required this.kpis, required this.hospitalises});
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;

  /// Les admissions en cours (`statut === 'en_cours'`), dans l'ordre du magasin.
  final List<FicheTba> hospitalises;
}

/// [administrationsDues] : le nombre d'administrations dues à la salle de soins (`PR.soinsDuSecteur('salle_soins')`, lignes cumulées) — la règle
/// de relais vit dans `csSoinsDuSecteur`, l'écran la calcule et la passe ici.
TbaInfirmier tbaInfirmier({required Iterable<FicheTba> admissions, required int administrationsDues, required DateTime auj}) {
  final occ = [for (final a in admissions) if (a['statut'] == 'en_cours') a];
  final aSortir = occ.where((a) {
    final e = _d(a['dateEntree']);
    return e != null && joursEntre(e, auj) > 5;
  }).length;
  return TbaInfirmier(
    premier: TbaPremierRegard(
      valeur: administrationsDues,
      unite: 'administration(s)',
      question: 'reviennent à votre poste',
      vide: 'Aucune administration due à votre poste.',
      ton: 'navy',
      icone: 'syringe',
      ecran: 'm2-salle-soins',
      lienLabel: 'Salle de soins',
      note: 'Le rang du passage décide du secteur : la première administration d’un traitement hospitalier revient à la salle de soins, les suivantes à l’hospitalisation.',
    ),
    kpis: [
      TbaKpi('Patients hospitalisés', nombre(occ.length), ton: 'navy', icone: 'bed-double'),
      TbaKpi('Lits libres', nombre(tbaTotalLits() - occ.length), ton: 'success', icone: 'bed'),
      TbaKpi('Relevés de constantes attendus', nombre(occ.length * 3), indice: '3 relevés par patient et par jour', ton: 'warning', icone: 'activity'),
      TbaKpi('Sorties à préparer', nombre(aSortir), ton: 'info', icone: 'door-open'),
    ],
    hospitalises: occ,
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// PHARMACIE
// ---------------------------------------------------------------------------------------------------------------------------------------------

class TbaPharmacien {
  const TbaPharmacien({
    required this.premier,
    required this.kpis,
    required this.aReapprovisionner,
    required this.entrees,
    required this.sorties,
    required this.peremptions,
  });
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;

  /// Les dix produits les plus bas (`C.sortBy(ruptures, 'stock')`).
  final List<FicheTba> aReapprovisionner;
  final List<num> entrees, sorties;

  /// Périmés, moins de 90 jours, au-delà.
  final List<num> peremptions;
}

TbaPharmacien tbaPharmacien({
  required Iterable<FicheTba> produits,
  required Iterable<FicheTba> lots,
  required Iterable<FicheTba> mouvements,
  required List<num> Function(List<FicheTba>) parMoisQuantite,
}) {
  final ps = produits.toList(), ls = lots.toList(), mv = mouvements.toList();
  final med = ps.where((p) => p['categorie'] == 'medicament').toList();
  final ruptures = tbaRuptures(ps);
  final proche = tbaPeremptionProche(ls);
  final perimes = tbaPerimes(ls);
  return TbaPharmacien(
    premier: const TbaPremierRegard(
      valeur: 0,
      unite: '',
      question: '',
      vide: 'Le compte Pharmacie a été fermé — la pharmacie est tenue par la caisse.',
      ton: 'warning',
      icone: 'info',
      note: 'Décision de la Direction du 24/08/2026 : le stock de détail et la pharmacie d’urgence sont rattachés au compte Caissier. Rien n’a été supprimé — les mouvements signés par ce rôle restent attribuables (RG-14).',
    ),
    kpis: [
      TbaKpi('Références en pharmacie', nombre(med.length), ton: 'navy', icone: 'pill'),
      TbaKpi('Valeur du stock détail', money(tbaSomme(med, (x) => _n(x['stockDetail']) * _n(x['cump']))), ton: 'info', icone: 'wallet'),
      TbaKpi('Produits sous seuil', nombre(ruptures.length), ton: 'danger', icone: 'trending-down'),
      TbaKpi('Lots à péremption proche', nombre(proche.length), indice: 'FEFO — RG-05', ton: 'warning', icone: 'clock'),
    ],
    aReapprovisionner: trierPar(ruptures, (p) => p['stock']).take(10).toList(),
    entrees: parMoisQuantite([for (final m in mv) if (m['type'] == 'entree') m]),
    sorties: parMoisQuantite([for (final m in mv) if (m['type'] == 'sortie') m]),
    peremptions: [perimes.length, proche.length, ls.length - perimes.length - proche.length],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// BIOLOGISTE MÉDICAL
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `C.seeded(seed)` : le PRNG déterministe de la maquette.
double Function() tbaAleatoire(int graine) {
  var s = graine == 0 ? 42 : graine;
  return () {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
}

/// `C.between(rnd, a, b)`.
int tbaEntre(double Function() rnd, int a, int b) => (rnd() * (b - a + 1)).floor() + a;

/// Le rappel du matin : analyses réglées à prélever / échantillons reçus à saisir. `null` quand il n'y a rien (« une modale qui annonce rien à
/// faire coûte un clic pour aucune information »).
({int aPrelever, int aSaisir})? tbaRappelBiologiste(Iterable<FicheTba> demandes) {
  final ds = demandes.toList();
  final aPrelever = ds.where((d) => d['etatAnalyse'] == 'attente_prelevement' && !_vrai(d['preleveLe'])).length;
  final aSaisir = ds.where((d) => _vrai(d['recuLaboLe']) && const ['en_cours', 'preleve'].contains(d['etatAnalyse'])).length;
  return aPrelever == 0 && aSaisir == 0 ? null : (aPrelever: aPrelever, aSaisir: aSaisir);
}

bool _vrai(Object? v) => v != null && v != false && v != '' && v != 0;

class TbaLaborantin {
  const TbaLaborantin({
    required this.premier,
    required this.kpis,
    required this.analysesDemandees,
    required this.analysesRealisees,
    required this.categories,
  });
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;

  /// Le classement « Analyses les plus demandées » : (désignation, valeur) — valeurs TIRÉES AU HASARD par la maquette (`C.seeded(31)`), écart E920.
  final List<(String, int)> analysesDemandees;

  /// « Analyses réalisées (12 mois) » : douze valeurs tirées au hasard (`C.seeded(53)`, 380 à 720), écart E920.
  final List<int> analysesRealisees;
  final TbaGraphique categories;
}

TbaLaborantin tbaLaborantin({
  required Iterable<FicheTba> demandes,
  required Iterable<FicheTba> produits,
  required List<FicheTba> analyses,
}) {
  final aValider = demandes.where((d) => d['etatAnalyse'] == 'valide_technique').length;
  final reactifs = produits.where((p) => p['categorie'] == 'reactif' || p['categorie'] == 'conso_labo');
  final rnd = tbaAleatoire(31);
  final dem = [for (final a in analyses.take(10)) ('${a['designation']}', tbaEntre(rnd, 20, 240))];
  final tries = trierPar(dem, (e) => e.$2, descendant: true);
  final rnd2 = tbaAleatoire(53);
  return TbaLaborantin(
    premier: TbaPremierRegard(
      valeur: aValider,
      unite: 'résultat(s)',
      question: 'attendent votre validation biologique',
      vide: 'Aucun résultat en attente de validation biologique.',
      ton: 'warning',
      icone: 'shield-check',
      ecran: 'm5-resultats',
      lienLabel: 'Valider',
      note: 'Entre la validation technique et la vôtre, le résultat existe mais le prescripteur ne le voit pas. C’est votre signature qui le rend opposable.',
    ),
    kpis: [
      TbaKpi('Analyses au catalogue', nombre(analyses.length), indice: 'Tarifs de la clinique', ton: 'navy', icone: 'flask-conical'),
      // Écart E921 : la maquette écrit ces deux compteurs EN DUR (28 et 42) — porté fidèlement, dit.
      TbaKpi('Demandes en attente', nombre(28), ton: 'warning', icone: 'inbox'),
      TbaKpi('Résultats du jour', nombre(42), ton: 'success', icone: 'file-check-2'),
      TbaKpi('Réactifs sous seuil', nombre(reactifs.where(tbaSousSeuil).length), ton: 'danger', icone: 'test-tube'),
    ],
    analysesDemandees: tries,
    analysesRealisees: [for (var i = 0; i < 12; i++) tbaEntre(rnd2, 380, 720)],
    categories: _comptes(tbaGrouper(analyses, (a) => a['categorie']), 'Analyses'),
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// GESTIONNAIRE DE STOCK
// ---------------------------------------------------------------------------------------------------------------------------------------------

class TbaStock {
  const TbaStock({
    required this.premier,
    required this.alertes,
    required this.kpis,
    required this.derniers,
    required this.valeurParCategorie,
    required this.repartitionMouvements,
  });
  final TbaPremierRegard premier;
  final List<TbaAlerte> alertes;
  final List<TbaKpi> kpis;

  /// Les dix premiers mouvements, dans l'ordre du magasin.
  final List<FicheTba> derniers;
  final TbaGraphique valeurParCategorie, repartitionMouvements;
}

String _libelleCategorie(String id, Map<String, String> categories) => categories[id] ?? id;

TbaStock tbaStock({
  required Iterable<FicheTba> produits,
  required Iterable<FicheTba> lots,
  required Iterable<FicheTba> mouvements,
  required Map<String, String> categories,
  required DateTime auj,
}) {
  final ps = produits.toList(), mv = mouvements.toList();
  final sous = ps.where((x) => x['seuilAlerte'] != null && _n(x['stock']) <= _n(x['seuilAlerte'])).length;
  final valeur = (FicheTba p) => _n(p['stock']) * _n(p['cump']);
  final g = tbaGrouper(ps, (p) => p['categorie']);
  return TbaStock(
    premier: TbaPremierRegard(
      valeur: sous,
      unite: 'article(s)',
      question: 'sont sous leur seuil d’alerte',
      vide: 'Aucun article sous son seuil d’alerte.',
      ton: 'danger',
      icone: 'package-x',
      ecran: 'm6-alertes',
      lienLabel: 'Voir les alertes',
      note: 'Un seuil NON FIXÉ n’est pas un seuil de zéro : les articles sans seuil sont comptés à part et ne peuvent déclencher aucune alerte.',
    ),
    alertes: tbaBandeauAlertes(ps, lots),
    kpis: [
      TbaKpi('Références gérées', nombre(ps.length), ton: 'navy', icone: 'package'),
      TbaKpi('Valeur totale du stock', money(tbaSomme(ps, valeur)), indice: 'Valorisation au CUMP', ton: 'info', icone: 'wallet'),
      TbaKpi('Mouvements du mois', nombre(tbaDuMois(mv, 'date', auj).length), ton: 'success', icone: 'arrow-left-right'),
      TbaKpi('Alertes actives', nombre(tbaRuptures(ps).length + tbaPerimes(lots).length), ton: 'danger', icone: 'triangle-alert'),
    ],
    derniers: mv.take(10).toList(),
    valeurParCategorie: TbaGraphique([for (final k in g.keys) _libelleCategorie(k, categories)],
        [TbaSerie('Valeur (FCFA)', [for (final v in g.values) tbaSomme(v, valeur)])]),
    repartitionMouvements: _comptes(tbaGrouper(mv, (m) => m['typeLabel']), 'Mouvements'),
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// CAISSIER
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `D.MODES_PAIEMENT` : (identifiant, libellé).
const tbaModesPaiement = <String, String>{
  'especes': 'Espèces',
  'tpe': 'TPE (carte bancaire)',
  'mtn': 'MTN Mobile Money',
  'moov': 'Moov Money',
  'assurance': 'Prise en charge assurance',
};

class TbaCaissier {
  const TbaCaissier({required this.premier, required this.kpis, required this.dernieres, required this.parMode, required this.recettesQuotidiennes});
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;
  final List<FicheTba> dernieres;
  final TbaGraphique parMode;

  /// « Recettes quotidiennes du mois » : un point par jour du 1ᵉʳ au jour courant.
  final TbaGraphique recettesQuotidiennes;
}

TbaCaissier tbaCaissier({required Iterable<FicheTba> taches, required Iterable<FicheTba> factures, required DateTime auj}) {
  final fs = factures.toList();
  final aEncaisser = taches.where((t) => t['type'] == 'encaissement' && t['statut'] != 'fait').length;
  final fj = tbaDuJour(fs, 'date', auj);
  final g = tbaGrouper(fs, (f) => f['modePaiement']);
  final jours = [for (var d = 1; d <= auj.day; d++) d];
  // Écart E922 : la maquette fixe le mois de la série à AOÛT 2026 (`new Date(2026, 7, d)`) ; portée sur le mois du poste, comme E20.
  final data = [
    for (final d in jours) tbaSomme(tbaDuJour(fs, 'date', DateTime(auj.year, auj.month, d)), (f) => f['montantPaye'])
  ];
  return TbaCaissier(
    premier: TbaPremierRegard(
      valeur: aEncaisser,
      unite: 'prescription(s)',
      question: 'attendent d’être encaissées',
      vide: 'Aucune prescription en attente de règlement.',
      ton: 'warning',
      icone: 'coins',
      ecran: 'm8-caisse',
      lienLabel: 'Encaisser',
      note: 'Chaque encaissement débloque aussitôt la délivrance en pharmacie et le prélèvement au laboratoire — tant qu’il n’a pas lieu, le patient attend à deux endroits.',
    ),
    kpis: [
      TbaKpi('Encaissé aujourd’hui', money(tbaSomme(fj, (f) => f['montantPaye'])), ton: 'success', icone: 'banknote'),
      TbaKpi('Factures du jour', nombre(fj.length), ton: 'navy', icone: 'receipt'),
      TbaKpi('Reliquats en cours', money(tbaSomme(fs, (f) => f['reliquat'])), ton: 'warning', icone: 'hand-coins'),
      TbaKpi('Factures impayées', nombre(fs.where((x) => x['statutPaiement'] == 'impayee').length), ton: 'danger', icone: 'file-x'),
    ],
    dernieres: fs.take(10).toList(),
    parMode: TbaGraphique([for (final k in g.keys) tbaModesPaiement[k] ?? k],
        [TbaSerie('Montant encaissé', [for (final v in g.values) tbaSomme(v, (f) => f['montantPaye'])])]),
    recettesQuotidiennes: TbaGraphique([for (final d in jours) '$d'], [TbaSerie('Encaissé', data)]),
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// COMPTABLE
// ---------------------------------------------------------------------------------------------------------------------------------------------

class TbaComptable {
  const TbaComptable({required this.premier, required this.kpis, required this.dernieres, required this.parJournal, required this.chargesParCentre});
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;
  final List<FicheTba> dernieres;
  final TbaGraphique parJournal, chargesParCentre;
}

TbaComptable tbaComptable({required Iterable<FicheTba> ecritures}) {
  final es = ecritures.toList();
  final brouillons = es.where((e) => e['statut'] == 'brouillon' || e['etat'] == 'brouillon').length;
  final debit = tbaSomme(es, (e) => e['debit']), credit = tbaSomme(es, (e) => e['credit']);
  final equilibre = debit == credit;
  final gj = tbaGrouper(es, (e) => e['journal']);
  final gc = tbaGrouper(es.where((e) => _n(e['debit']) > 0), (e) => e['centreCout']);
  String centre(String k) {
    for (final c in cpaCentresCout) {
      if (c.$1 == k) return c.$2;
    }
    return k;
  }

  return TbaComptable(
    premier: TbaPremierRegard(
      valeur: brouillons,
      unite: 'écriture(s) en brouillon',
      question: 'attendent votre validation',
      vide: 'Aucune écriture en attente de validation.',
      ton: 'warning',
      icone: 'file-check-2',
      ecran: 'm12-ecritures',
      lienLabel: 'Valider les écritures',
      note: 'L’encaissement pose l’écriture ; la valider reste un geste humain. Sans cela, la recette se ressaisirait à la main — ce que la clinique fait aujourd’hui entre PERFECTO et la caisse.',
    ),
    kpis: [
      TbaKpi('Écritures de l’exercice', nombre(es.length), ton: 'navy', icone: 'book-open-check'),
      TbaKpi('Total débit', money(debit), ton: 'info', icone: 'arrow-down-left'),
      TbaKpi('Total crédit', money(credit), ton: 'info', icone: 'arrow-up-right'),
      TbaKpi('Équilibre (RG-10)', equilibre ? 'Équilibré' : money((debit - credit).abs()),
          indice: equilibre ? 'Débit = Crédit' : 'Écart à régulariser', ton: equilibre ? 'success' : 'danger', icone: equilibre ? 'scale' : 'scale-3d'),
    ],
    dernieres: es.take(10).toList(),
    parJournal: _comptes(gj, 'Écritures'),
    chargesParCentre: TbaGraphique([for (final k in gc.keys) centre(k)], [TbaSerie('Charges', [for (final v in gc.values) tbaSomme(v, (e) => e['debit'])])]),
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// RESSOURCES HUMAINES
// ---------------------------------------------------------------------------------------------------------------------------------------------

class TbaRh {
  const TbaRh({required this.premier, required this.kpis, required this.parFonction, required this.parService, required this.planningDuJour});
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;

  /// (libellé de la fonction, effectif), décroissant.
  final List<(String, int)> parFonction;
  final TbaGraphique parService, planningDuJour;
}

TbaRh tbaRh({required Iterable<FicheTba> personnel, required Iterable<FicheTba> planning, required DateTime auj}) {
  final p = personnel.toList();
  final jour = iso(auj);
  final gardes = planning.where((x) => x['date'] == jour && x['type'] == 'garde').length;
  final g = tbaGrouper(p, (x) => x['fonction']);
  final pj = planning.where((x) => x['date'] == jour).toList();
  final gt = tbaGrouper(pj, (x) => x['type']);
  return TbaRh(
    premier: const TbaPremierRegard(
      valeur: 0,
      unite: '',
      question: '',
      vide: 'Le compte RH a été fermé — les ressources humaines relèvent de la DAF.',
      ton: 'warning',
      icone: 'info',
      note: 'Décision de la Direction du 24/08/2026. Le rôle est archivé, non supprimé : la Direction pourra le recréer depuis la matrice des droits sans retoucher le logiciel.',
    ),
    kpis: [
      TbaKpi('Effectif total', nombre(p.length), indice: 'Organigramme : 44 agents', ton: 'navy', icone: 'users-round'),
      TbaKpi('Masse salariale (base)', money(tbaSomme(p, (x) => x['salaireBase'])), ton: 'info', icone: 'banknote'),
      TbaKpi('Agents de garde aujourd’hui', nombre(gardes), ton: 'warning', icone: 'moon'),
      TbaKpi('Évaluations du mois', nombre(p.length), indice: 'Barème NS 131', ton: 'success', icone: 'clipboard-check'),
    ],
    parFonction: [
      for (final e in trierPar([for (final e in g.entries) (rhaFonctionLabel(e.key), e.value.length)], (e) => e.$2, descendant: true)) e
    ],
    parService: _comptes(tbaGrouper(p, (x) => x['service']), 'Effectif'),
    planningDuJour: TbaGraphique([for (final k in gt.keys) rhaTypePlanningLabel(k)], [TbaSerie('Agents', [for (final v in gt.values) v.length])]),
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// ACCUEIL / RÉCEPTION
// ---------------------------------------------------------------------------------------------------------------------------------------------

class TbaReception {
  const TbaReception({required this.premier, required this.kpis, required this.rendezVousDuJour});
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;

  /// Les consultations du jour, par date croissante.
  final List<FicheTba> rendezVousDuJour;
}

TbaReception tbaReception({
  required Iterable<FicheTba> fileAttente,
  required Iterable<FicheTba> patients,
  required Iterable<FicheTba> consultations,
  required DateTime auj,
}) {
  final ps = patients.toList();
  final attente = fileAttente.where((t) => t['etat'] == 'attente').length;
  final cj = trierPar(tbaDuJour(consultations, 'date', auj), (c) => c['date']);
  final expirees = ps.where((p) {
    final a = p['assureur'];
    if (a == null || a == '' || a == false) return false;
    final e = _d(p['carteExpiration']);
    return e != null && e.isBefore(auj);
  }).length;
  return TbaReception(
    premier: TbaPremierRegard(
      valeur: attente,
      unite: 'patient(s)',
      question: 'attendent d’être appelés',
      vide: 'Personne n’attend à l’accueil.',
      ton: 'navy',
      icone: 'users',
      ecran: 'm2-file-attente',
      lienLabel: 'File d’attente',
      note: 'L’ordre d’arrivée gouverne, sauf urgence. Vérifiez la validité de la carte d’assurance à l’enregistrement : c’est elle qui décide de la facturation (RG-09).',
    ),
    kpis: [
      TbaKpi('Dossiers créés ce mois', nombre(tbaDuMois(ps, 'dateCreation', auj).length), ton: 'success', icone: 'user-plus'),
      TbaKpi('Rendez-vous du jour', nombre(tbaDuJour(consultations, 'date', auj).length), ton: 'navy', icone: 'calendar-check'),
      TbaKpi('Patients au répertoire', nombre(ps.length), ton: 'info', icone: 'users'),
      TbaKpi('Cartes d’assurance expirées', nombre(expirees), ton: 'warning', icone: 'shield-alert'),
    ],
    rendezVousDuJour: cj,
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// AGENT ADMINISTRATIF
// ---------------------------------------------------------------------------------------------------------------------------------------------

class TbaAgentAdmin {
  const TbaAgentAdmin({required this.premier, required this.kpis, required this.notes});
  final TbaPremierRegard premier;
  final List<TbaKpi> kpis;
  final List<AdmNoteService> notes;
}

TbaAgentAdmin tbaAgentAdmin({
  required Iterable<FicheTba> courriers,
  required Iterable<FicheTba> reunions,
  required Iterable<FicheTba> documents,
  required DateTime auj,
}) {
  final aTraiter = courriers.where((x) => x['traitement'] != 'traite').length;
  final cour = tbaDuMois(courriers, 'date', auj);
  final arrivees = cour.where((c) => c['sens'] == 'arrivee').length;
  final aVenir = reunions.where((r) {
    final d = _d(r['date']);
    return d != null && !d.isBefore(auj);
  }).length;
  final aValider = documents.where((d) => d['etatValidation'] == 'en_attente').length;
  return TbaAgentAdmin(
    premier: TbaPremierRegard(
      valeur: aTraiter,
      unite: 'courrier(s)',
      question: 'restent à traiter',
      vide: 'Aucun courrier en attente.',
      ton: 'info',
      icone: 'mail',
      ecran: 'm13-courriers',
      lienLabel: 'Courriers',
      note: 'Proposition à valider par la Direction : ce que l’agent administratif regarde en premier n’a pas été précisé.',
    ),
    kpis: [
      TbaKpi('Courriers du mois', nombre(cour.length), indice: '$arrivees arrivée(s), ${cour.length - arrivees} départ(s)', ton: 'navy', icone: 'mail'),
      TbaKpi('Réunions planifiées', nombre(aVenir), ton: 'info', icone: 'users'),
      TbaKpi('Notes de service actives', nombre(2), indice: 'NS 131 et NS 132', ton: 'success', icone: 'file-text'),
      TbaKpi('Documents à valider', nombre(aValider), ton: 'warning', icone: 'file-clock'),
    ],
    notes: [admNs131, admNs132],
  );
}
