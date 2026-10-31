/// RAP — Rapports, impression & états officiels (`prototype_html/assets/js/modules/rapports.js`) : les règles des quatre écrans
/// `rapports-bibliotheque`, `rapports-direction`, `rapports-generateur`, `rapports-historique`. Symboles préfixés `rap` / `Rap`.
///
/// Rejouées sur les vecteurs tirés des écrans RÉELS pilotés dans Chrome (`prototype_html/build/vecteurs-rapports.js` → `test/vecteurs/rap.json`).
/// Rien n'est inventé : le catalogue des états et le rattachement état → écran producteur sont EXTRAITS de la maquette.
library;

import '../administration/adm_regles.dart' show admAleatoire;
import '../configuration/cfb_donnees.dart' show cfbGroupesArticles;
import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart';
import '../impression/etat.dart';
import '../stock/points.dart' show familleDe;

typedef RapFiche = Map<String, Object?>;

/// Vrai au sens de JavaScript (`||`, `!!`).
bool rapVrai(Object? v) =>
    !(v == null || v == false || v == '' || (v is num && (v == 0 || v.isNaN)));

/// `x || repli` pour une clé de texte.
String rapOu(Object? v, String repli) => rapVrai(v) ? '$v' : repli;

/// `C.toDate(d).getTime()` : une date seule (AAAA-MM-JJ) est lue à minuit UTC, comme `new Date('AAAA-MM-JJ')` ; `null` = date invalide (NaN : toute comparaison est fausse).
int? rapMs(Object? v) {
  if (v is DateTime) return v.millisecondsSinceEpoch;
  final s = '${v ?? ''}'.trim();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m != null) {
    return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)).millisecondsSinceEpoch;
  }
  return DateTime.tryParse(s)?.millisecondsSinceEpoch;
}

DateTime _jourUtc(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

/// Un nombre au sens de `Number(v)` ; absent ou non numérique → NaN (toute comparaison est fausse).
double _nombre(Object? v) {
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? 0 : (double.tryParse(t) ?? double.nan);
  }
  return double.nan;
}

double _somme(Iterable<RapFiche> l, Object? Function(RapFiche) f) {
  var t = 0.0;
  for (final x in l) {
    t += nombreOuZero(f(x));
  }
  return t;
}

// ----------------------------------------------------------------------------------------------------------------------------------------------
// Bibliothèque des états
// ----------------------------------------------------------------------------------------------------------------------------------------------

/// Un état du catalogue, avec l'écran producteur s'il existe (« Éditer » ; sinon « À venir »).
class RapEtat {
  const RapEtat(this.domaine, this.etat, this.ecran);
  final String domaine, etat;
  final String? ecran;
  bool get disponible => ecran != null;
}

/// `catalogue()` : tous les états, domaine par domaine, dans l'ordre du catalogue.
List<RapEtat> rapCatalogue() {
  final ecrans = {for (final (k, e) in rapEcransProducteurs) k: e};
  return [
    for (final (dom, etats) in rapCatalogueEtats)
      for (final e in etats) RapEtat(dom, e, ecrans[e])
  ];
}

/// Les indicateurs de la bibliothèque.
({int etats, int domaines, int editables}) rapStatsBibliotheque() {
  final c = rapCatalogue();
  return (etats: c.length, domaines: rapCatalogueEtats.length, editables: c.where((r) => r.disponible).length);
}

/// Le pied de page normalisé (cinq mentions, dans l'ordre de la maquette).
const rapMentionsPied = [
  'Dénomination, RCCM et IFU de l’établissement',
  'Nom de l’utilisateur ayant généré le document',
  'Date et heure d’impression',
  'Identifiant unique du document (traçabilité)',
  'Mention « Édité depuis le SIGH-CNT »',
];

// ----------------------------------------------------------------------------------------------------------------------------------------------
// États de la Direction : une PÉRIODE et un AXE
// ----------------------------------------------------------------------------------------------------------------------------------------------

class RapPeriode {
  const RapPeriode(this.id, this.libelle, this.jours);
  final String id, libelle;
  final int jours;
}

const rapPeriodesDirection = [
  RapPeriode('jour', 'Journalier', 1),
  RapPeriode('semaine', 'Hebdomadaire', 7),
  RapPeriode('mois', 'Mensuel', 30),
  RapPeriode('trimestre', 'Trimestriel', 91),
  RapPeriode('semestre', 'Semestriel', 182),
  RapPeriode('annee', 'Annuel', 365),
];

class RapAxe {
  const RapAxe(this.id, this.libelle, this.detail);
  final String id, libelle, detail;

  /// Le libellé sans « Par » (`label.replace('Par ', '')`).
  String get sansPar => libelle.replaceFirst('Par ', '');

  /// Libellé de la colonne de l'écran : premier caractère en majuscule.
  String get colonne => sansPar.isEmpty ? sansPar : sansPar[0].toUpperCase() + sansPar.substring(1);

  /// Le libellé du poste du quatrième indicateur (« Postes — client »).
  String get libellePostes => libelle.replaceFirst('Par ', 'Postes — ');
  bool get niveauPiece => const {'client', 'nature', 'assureur'}.contains(id);
}

const rapAxesDirection = [
  RapAxe('client', 'Par client', 'Un patient, une ligne'),
  RapAxe('nature', 'Par nature de facture', 'Consultation, maternité, pharmacie…'),
  RapAxe('assureur', 'Par assureur', 'Compagnies conventionnées'),
  RapAxe('article', 'Par article', 'Chaque produit ou prestation vendu'),
  RapAxe('famille', 'Par famille d’articles', 'Sept familles de l’inventaire SAGE'),
  RapAxe('groupe', 'Par groupe d’articles', 'Regroupement proposé — à valider'),
];

RapPeriode rapPeriode(String id) => rapPeriodesDirection.firstWhere((p) => p.id == id, orElse: () => rapPeriodesDirection[2]);
RapAxe rapAxe(String id) => rapAxesDirection.firstWhere((a) => a.id == id, orElse: () => rapAxesDirection.first);

/// `bornes()` : la fenêtre se termine à la date d'arrêt (incluse) et remonte de `jours − 1` jours. `fin` invalide → `null` (aucune pièce ne passe).
class RapBornes {
  const RapBornes(this.debutMs, this.finMs, this.libelle);
  final int? debutMs, finMs;
  final String libelle;
  String get debutFR => debutMs == null ? '—' : dateFR(_jourUtc(debutMs!));
  String get finFR => finMs == null ? '—' : dateFR(_jourUtc(finMs!));
}

RapBornes rapBornes(String periodeId, Object? arrete) {
  final p = rapPeriode(periodeId);
  final f = rapMs(arrete);
  return RapBornes(f == null ? null : f - (p.jours - 1) * 86400000, f, p.libelle);
}

/// Les factures de la fenêtre : date comprise entre les bornes (incluses), avoirs (TTC négatif) écartés.
List<RapFiche> rapFacturesPeriode(Iterable<RapFiche> factures, RapBornes b) {
  if (b.debutMs == null || b.finMs == null) return const [];
  return [
    for (final f in factures)
      if (() {
        final t = rapMs(f['date']);
        return t != null && t >= b.debutMs! && t <= b.finMs! && _nombre(f['montantTTC']) >= 0;
      }())
        f
  ];
}

/// Un poste du point : un client, une nature, un assureur, un article, une famille ou un groupe.
class RapPoste {
  RapPoste(this.cle, this.libelle);
  final String cle, libelle;
  double montant = 0, quantite = 0, assureur = 0, patient = 0;
  int pieces = 0;
}

/// `agreger()` : regroupement selon l'axe. Les axes « article », « famille » et « groupe » descendent au niveau des LIGNES (là sont les quantités
/// vendues) ; client / nature / assureur restent au niveau de la pièce. Trié par montant décroissant (les ex æquo gardent l'ordre d'apparition).
List<RapPoste> rapAgreger(List<RapFiche> factures, Iterable<RapFiche> produits, String axe) {
  final groupes = <String, RapPoste>{};
  RapPoste ajouter(String cle, double montant, double quantite) {
    final g = groupes.putIfAbsent(cle, () => RapPoste(cle, cle));
    g.montant += montant;
    g.quantite += quantite;
    return g;
  }

  List<RapFiche> lignes(RapFiche f) => [
        for (final l in (f['lignes'] is List ? f['lignes'] as List : const []))
          if (l is Map) l.cast<String, Object?>()
      ];

  if (rapAxe(axe).niveauPiece) {
    for (final f in factures) {
      final v = switch (axe) {
        'client' => rapOu(f['patient'], '—'),
        'nature' => rapOu(f['type'], '—'),
        _ => rapOu(f['assureur'], 'Sans assurance'),
      };
      final g = ajouter(v, nombreOuZero(f['montantTTC']), (f['lignes'] is List ? (f['lignes'] as List).length : 0).toDouble());
      g.pieces++;
      g.assureur += nombreOuZero(f['partAssurance']);
      g.patient += f['partPatient'] != null ? nombreOuZero(f['partPatient']) : nombreOuZero(f['montantTTC']);
    }
  } else {
    final parId = <String, RapFiche>{};
    for (final p in produits) {
      parId.putIfAbsent('${p['id']}', () => p); // `filter(...)[0]` : le premier gagne
    }
    final groupesArticles = {for (final (id, lab) in cfbGroupesArticles) id: lab};
    for (final f in factures) {
      for (final l in lignes(f)) {
        final q = rapVrai(l['quantite']) ? nombreOuZero(l['quantite']) : 1.0;
        final montant = l['montant'] != null ? nombreOuZero(l['montant']) : q * nombreOuZero(l['prixUnitaire']);
        if (axe == 'article') {
          final cle = rapVrai(l['designation']) ? '${l['designation']}' : rapOu(l['produit'], '—');
          ajouter(cle, montant, q).pieces++;
          continue;
        }
        // Familles et groupes : on remonte par le produit quand la ligne en désigne un ; les prestations sans article vont en « Actes ».
        final prod = rapVrai(l['produitId']) ? parId['${l['produitId']}'] : null;
        final cat = prod?['categorie'];
        final fam = rapVrai(cat) ? familleDe(cat) : null;
        final lib = axe == 'famille' ? fam?.label : (fam == null ? null : groupesArticles[fam.groupe]);
        ajouter(lib ?? 'Actes et prestations', montant, q).pieces++;
      }
    }
  }
  return trierPar(groupes.values.toList(), (g) => g.montant, descendant: true);
}

/// Le cumul global affiché sous le tableau et au cartouche.
({double montant, double quantite, int postes}) rapCumul(List<RapPoste> rows) =>
    (montant: rows.fold(0.0, (s, r) => s + r.montant), quantite: rows.fold(0.0, (s, r) => s + r.quantite), postes: rows.length);

// ----------------------------------------------------------------------------------------------------------------------------------------------
// Générateur de rapports
// ----------------------------------------------------------------------------------------------------------------------------------------------

class RapSection {
  const RapSection(this.id, this.libelle);
  final String id, libelle;

  /// Intitulé imprimé : ce qui précède « — ».
  String get intitule => libelle.split(' — ').first;
}

const rapSections = [
  RapSection('activite', 'Activité — patients, consultations, hospitalisations'),
  RapSection('financier', 'Financier — chiffre d’affaires, encaissements, créances'),
  RapSection('stock', 'Stock — valeur, alertes, péremptions'),
  RapSection('laboratoire', 'Laboratoire — analyses réalisées, réactifs'),
  RapSection('rh', 'Ressources humaines — effectif, masse salariale, présences'),
  RapSection('comptable', 'Comptabilité — journaux, balance, résultat'),
  RapSection('assurances', 'Assurances — prises en charge et créances'),
];

/// Un modèle enregistré : titre, destinataire, sections cochées.
class RapModele {
  const RapModele(this.nom, this.destinataire, this.sections);
  final String nom, destinataire;
  final List<String> sections;
}

const rapModeles = [
  RapModele('Rapport d’activité mensuel', 'Direction', ['activite', 'financier']),
  RapModele('Situation des stocks', 'Gestion des stocks', ['stock']),
  RapModele('Rapport financier trimestriel', 'Direction', ['financier', 'comptable']),
  RapModele('Bilan social', 'Ressources humaines', ['rh']),
];

/// Ce que le chargement d'un modèle pose dans le formulaire. Le destinataire d'un modèle qui n'est PAS dans la liste (« Gestion des stocks »,
/// « Ressources humaines ») laisse la liste VIDE — c'est le comportement de la liste native de la maquette (écart E1040) ; le rapport sort alors
/// pour « Usage interne ».
({String titre, String destinataire, List<String> sections}) rapChargerModele(RapModele m) =>
    (titre: m.nom, destinataire: rapDestinataires.contains(m.destinataire) ? m.destinataire : '', sections: m.sections);

const rapDestinataires = ['Direction', 'Conseil de gestion', 'Partenaire technique', 'Usage interne'];
const rapPeriodesRapport = ['Journalière', 'Hebdomadaire', 'Mensuelle', 'Trimestrielle', 'Annuelle'];
const rapFiligranes = ['Document officiel', 'Confidentiel', 'Brouillon'];

/// Les registres que lisent les sections (collections ACTIVES du poste) et deux effectifs de référentiel (catalogue des analyses, compagnies).
class RapSources {
  const RapSources({
    this.patients = const [],
    this.consultations = const [],
    this.admissions = const [],
    this.factures = const [],
    this.produits = const [],
    this.lots = const [],
    this.personnel = const [],
    this.ecritures = const [],
    this.demandesAnalyses = const [],
    this.nbAnalyses = 0,
    this.nbAssureurs = 0,
  });
  final List<RapFiche> patients, consultations, admissions, factures, produits, lots, personnel, ecritures, demandesAnalyses;
  final int nbAnalyses, nbAssureurs;
}

bool _infEgal(Object? a, Object? b) {
  final x = _nombre(a), y = _nombre(b);
  return !x.isNaN && !y.isNaN && x <= y;
}

/// `donnees(id)` : les indicateurs (libellé, valeur formatée) de la section.
List<(String, String)> rapDonneesSection(String id, RapSources s) {
  int n(Iterable l) => l.length;
  String num_(Object? v) => nombre(v);
  switch (id) {
    case 'activite':
      return [
        ('Patients au répertoire', num_(n(s.patients))),
        ('Consultations réalisées', num_(n(s.consultations))),
        ('Hospitalisations', num_(n(s.admissions))),
        ('Hospitalisations en cours', num_(n(s.admissions.where((a) => a['statut'] == 'en_cours')))),
        ('Interventions à domicile', num_(n(s.consultations.where((c) => c['type'] == 'Domicile')))),
      ];
    case 'financier':
      return [
        ('Chiffre d’affaires', money(_somme(s.factures, (f) => f['montantTTC']))),
        ('Montant encaissé', money(_somme(s.factures, (f) => f['montantPaye']))),
        ('Reste à recouvrer', money(_somme(s.factures, (f) => f['reliquat']))),
        ('Nombre de factures', num_(n(s.factures))),
        ('Factures impayées', num_(n(s.factures.where((f) => f['statutPaiement'] == 'impayee')))),
      ];
    case 'stock':
      return [
        ('Références gérées', num_(n(s.produits))),
        ('Valeur du stock (CUMP)', money(_somme(s.produits, (p) => nombreOuZero(p['stock']) * nombreOuZero(p['cump'])))),
        ('Produits sous le seuil d’alerte', num_(n(s.produits.where((p) => _infEgal(p['stock'], p['seuilAlerte']))))),
        ('Lots périmés', num_(n(s.lots.where((l) => l['statut'] == 'perime')))),
        ('Lots à péremption proche', num_(n(s.lots.where((l) => l['statut'] == 'alerte')))),
      ];
    case 'laboratoire':
      return [
        ('Analyses au catalogue', num_(s.nbAnalyses)),
        ('Demandes enregistrées', num_(n(s.demandesAnalyses))),
        ('Résultats validés', num_(n(s.demandesAnalyses.where((d) => d['etatAnalyse'] == 'valide')))),
        (
          'Réactifs sous seuil',
          num_(n(s.produits.where((p) => (p['categorie'] == 'reactif' || p['categorie'] == 'conso_labo') && _infEgal(p['stock'], p['seuilAlerte']))))
        ),
      ];
    case 'rh':
      final masse = _somme(s.personnel, (p) => p['salaireBase']);
      return [
        ('Effectif total', num_(n(s.personnel))),
        ('Masse salariale de base', money(masse)),
        ('Salaire moyen', money(s.personnel.isEmpty ? 0 : masse / s.personnel.length)),
        ('Services représentés', num_({for (final p in s.personnel) '${p['service']}'}.length)),
      ];
    case 'comptable':
      final d = _somme(s.ecritures, (e) => e['debit']), c = _somme(s.ecritures, (e) => e['credit']);
      return [
        ('Écritures enregistrées', num_(n(s.ecritures))),
        ('Total débit', money(d)),
        ('Total crédit', money(c)),
        ('Équilibre', d == c ? 'Équilibré' : 'Écart de ${money((d - c).abs())}'),
      ];
    case 'assurances':
      return [
        ('Compagnies partenaires', num_(s.nbAssureurs)),
        ('Patients assurés', num_(n(s.patients.where((p) => rapVrai(p['assureur']))))),
        ('Créances assureurs', money(_somme(s.factures.where((f) => rapVrai(f['assureur'])), (f) => f['partAssurance']))),
      ];
  }
  return const [];
}

/// Les contrôles de `generer()` AVANT de produire le rapport : un refus se nomme. `null` = rien à refuser.
String? rapRefusGeneration({required String titre, required List<String> sectionsCochees}) {
  if (titre.trim().isEmpty) return 'Le formulaire comporte des erreurs.';
  if (sectionsCochees.isEmpty) return 'Sélectionner au moins une section.';
  return null;
}

// ----------------------------------------------------------------------------------------------------------------------------------------------
// Historique des éditions
// ----------------------------------------------------------------------------------------------------------------------------------------------

const rapModulesDemo = ['M1', 'M6', 'M8', 'M10', 'M11', 'M12', 'RAP'];
const rapFormatsDemo = ['PDF', 'PDF', 'PDF', 'Impression directe', 'CSV'];
const rapPostesDemo = ['ACCUEIL', 'CAISSE', 'PHARMA', 'COMPTA', 'DIR'];
const rapFormats = ['PDF', 'Impression directe', 'CSV'];
const rapNombreEditionsDemo = 60;

String _p(int n, int l) => n.toString().padLeft(l, '0');

/// Les éditions : celles que le journal a retenues (action « Impression », archivées depuis l'aperçu) PUIS un complément de démonstration jusqu'à
/// soixante lignes (graine 3221, comme la maquette) ; triées de la plus récente à la plus ancienne.
/// [audit] est le journal dans l'ordre où le magasin le tient (le plus récent en tête) ; [noms] les noms des agents actifs.
List<RapFiche> rapEditions(Iterable<RapFiche> audit, List<String> noms, DateTime aujourdhui) {
  final rnd = admAleatoire(3221);
  int entre(int a, int b) => (rnd() * (b - a + 1)).floor() + a;
  T pick<T>(List<T> l) => l[(rnd() * l.length).floor() % l.length];
  final etats = [for (final (k, _) in rapEcransProducteurs) k];
  final rows = <RapFiche>[];
  var i = 0;
  for (final a in audit.where((a) => a['action'] == 'Impression')) {
    rows.add({
      'id': a['id'],
      'reference': rapVrai(a['reference']) ? a['reference'] : 'CNT-${_p(i + 1, 5)}',
      'dateHeure': a['dateHeure'],
      'utilisateur': a['utilisateur'],
      'etat': pick(etats),
      'module': a['module'],
      'format': 'PDF',
      'poste': a['poste'],
    });
    i++;
  }
  for (var k = rows.length; k < rapNombreEditionsDemo; k++) {
    var d = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day - entre(0, 60), aujourdhui.hour, aujourdhui.minute, aujourdhui.second,
        aujourdhui.millisecond);
    final h = entre(7, 19), mn = entre(0, 59);
    d = DateTime(d.year, d.month, d.day, h, mn, d.second, d.millisecond);
    rows.add({
      'id': 'ED$k',
      'reference': 'CNT-${iso(d).replaceAll('-', '')}-${_p(k, 4)}',
      'dateHeure': d.toUtc().toIso8601String(),
      'utilisateur': pick(noms),
      'etat': pick(etats),
      'module': pick(rapModulesDemo),
      'format': pick(rapFormatsDemo),
      'poste': 'POSTE-${pick(rapPostesDemo)}',
    });
  }
  return trierPar(rows, (r) => r['dateHeure'], descendant: true);
}

/// `C.toDate(dateHeure)` en heure locale.
DateTime? rapDateHeure(Object? v) {
  final ms = rapMs(v);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Les quatre indicateurs de l'historique.
({int editions, int ceMois, int pdf, int utilisateurs}) rapStatsHistorique(List<RapFiche> rows, DateTime aujourdhui) {
  var mois = 0;
  for (final r in rows) {
    final d = rapDateHeure(r['dateHeure']);
    if (d != null && d.month == aujourdhui.month && d.year == aujourdhui.year) mois++;
  }
  return (
    editions: rows.length,
    ceMois: mois,
    pdf: rows.where((r) => r['format'] == 'PDF').length,
    utilisateurs: {for (final r in rows) '${r['utilisateur']}'}.length,
  );
}

/// `C.groupBy(rows, cle)` : l'ordre de première apparition.
Map<String, List<RapFiche>> rapGrouper(List<RapFiche> rows, String cle) {
  final m = <String, List<RapFiche>>{};
  for (final r in rows) {
    (m['${r[cle]}'] ??= []).add(r);
  }
  return m;
}

/// « États les plus édités » : les huit premiers, du plus édité au moins édité (les ex æquo gardent l'ordre de première apparition).
List<(String, int)> rapEtatsLesPlusEdites(List<RapFiche> rows) {
  final g = rapGrouper(rows, 'etat');
  final l = trierPar([for (final e in g.entries) (e.key, e.value.length)], (e) => e.$2, descendant: true);
  return l.take(8).toList();
}

/// `D.CATALOGUE_ETATS` (CDCT §21 + draf1 « Bibliothèque des États »), tiré de la maquette : (domaine, états).
const rapCatalogueEtats = <(String, List<String>)>[
  ('Patients / Soins', [
    'Carte patient',
    'Fiche patient',
    'Historique médical',
    'Parcours de soins',
    'Compte rendu de consultation',
    'Ordonnance',
    'Certificat médical',
    'Bon d’examen',
  ]),
  ('Hospitalisation', [
    'Bon d’admission',
    'Feuille de température',
    'Feuille de soins',
    'Bon de sortie',
    'Sortie contre avis médical',
    'Rapport d’hospitalisation',
  ]),
  ('Maternité & Décès', [
    'Fiche d’accouchement',
    'Acte de naissance',
    'Registre des naissances',
    'Déclaration de décès',
    'Registre des décès',
  ]),
  ('Laboratoire', [
    'Résultat d’analyse',
    'Rapport biologique',
    'Bon de prélèvement',
    'Registre des analyses',
    'Bon de demande de sang',
  ]),
  ('Stock / Pharmacie', [
    'Bon d’expression de besoins',
    'Bon de commande',
    'Bon de livraison',
    'Bon de sortie de stock',
    'État d’inventaire',
    'État des produits périmés',
    'État des alertes de stock',
    'Étiquettes produits',
  ]),
  ('Facturation', [
    'Facture normalisée MECeF',
    'Facture pro-forma',
    'Reçu de paiement',
    'Avoir',
    'État de caisse journalier',
    'Historique des paiements',
  ]),
  ('Assurances', [
    'Facture mensuelle par assureur',
    'État des créances',
    'Lettre de relance',
    'État des prises en charge',
  ]),
  ('RH', [
    'Contrat de travail',
    'Fiche employé',
    'Fiche d’évaluation (NS 131)',
    'Planning de garde/permanence',
    'État des présences',
    'État des congés',
    'Notification de sanction',
  ]),
  ('Paie', [
    'Bulletin de paie',
    'Fiche de solde mensuelle',
    'Journal de paie',
    'État des cotisations CNSS',
    'État ITS',
    'État VPS',
    'État des primes',
  ]),
  ('Comptabilité', [
    'Journaux comptables',
    'Grand livre',
    'Balance générale',
    'Balance âgée',
    'Tableau d’amortissement',
    'État de rapprochement bancaire',
    'Bilan',
    'Compte de résultat',
    'Tableau des flux de trésorerie',
  ]),
  ('Administration', [
    'Registre des courriers',
    'Compte rendu de réunion',
    'Plan annuel de travail',
    'Note de service',
  ]),
  ('Pilotage', [
    'Tableau de bord financier',
    'Tableau de bord stock',
    'Tableau de bord RH',
    'Tableau de bord d’activité',
    'Rapport d’activité',
  ]),
  ('Sécurité', [
    'Journal d’audit',
    'Liste des comptes utilisateurs et rôles',
  ]),
];

/// `ECRANS` de `rapports.js` : état → écran qui sait le produire (l'ordre des clés EST celui de la maquette : l'historique de démonstration y pioche).
const rapEcransProducteurs = <(String, String)>[
  ('Fiche patient', 'm1-patients'),
  ('Carte patient', 'm1-patients'),
  ('Historique médical', 'm1-patient-profil'),
  ('Parcours de soins', 'm1-patient-profil'),
  ('Compte rendu de consultation', 'm2-consultations'),
  ('Ordonnance', 'm2-ordonnances'),
  ('Certificat médical', 'm2-consultation-fiche'),
  ('Bon d’examen', 'm2-consultation-fiche'),
  ('Bon d’admission', 'm3-admissions'),
  ('Feuille de température', 'm3-feuille-temperature'),
  ('Feuille de soins', 'm3-soins'),
  ('Bon de sortie', 'm3-sorties'),
  ('Sortie contre avis médical', 'm3-sortie-avis-medical'),
  ('Rapport d’hospitalisation', 'm3-admissions'),
  ('Fiche d’accouchement', 'm4-accouchements'),
  ('Acte de naissance', 'm4-naissances'),
  ('Registre des naissances', 'm4-naissances'),
  ('Déclaration de décès', 'm4-deces'),
  ('Registre des décès', 'm4-deces'),
  ('Résultat d’analyse', 'm5-resultats'),
  ('Rapport biologique', 'm5-resultats'),
  ('Bon de prélèvement', 'm5-demandes'),
  ('Registre des analyses', 'm5-catalogue'),
  ('Bon de demande de sang', 'm5-banque-sang'),
  ('Bon d’expression de besoins', 'm7-besoins'),
  ('Bon de commande', 'm7-commandes'),
  ('Bon de livraison', 'm7-livraisons'),
  ('Bon de sortie de stock', 'm6-dispensation'),
  ('État d’inventaire', 'm6-inventaire'),
  ('État des produits périmés', 'm6-lots'),
  ('État des alertes de stock', 'm6-alertes'),
  ('Étiquettes produits', 'm6-etiquetage'),
  ('Facture normalisée MECeF', 'mecef-factures'),
  ('Facture pro-forma', 'm8-proforma'),
  ('Reçu de paiement', 'm8-paiements'),
  ('Avoir', 'mecef-avoirs'),
  ('État de caisse journalier', 'm8-caisse'),
  ('Historique des paiements', 'm8-paiements'),
  ('Facture mensuelle par assureur', 'm9-factures-assureur'),
  ('État des créances', 'm9-creances'),
  ('Lettre de relance', 'm9-relances'),
  ('État des prises en charge', 'm9-prises-en-charge'),
  ('Contrat de travail', 'm10-contrats'),
  ('Fiche employé', 'm10-personnel'),
  ('Fiche d’évaluation (NS 131)', 'm10-evaluations'),
  ('Planning de garde/permanence', 'm10-planning'),
  ('État des présences', 'm10-presences'),
  ('État des congés', 'm10-conges'),
  ('Notification de sanction', 'm10-sanctions'),
  ('Bulletin de paie', 'm11-bulletins'),
  ('Fiche de solde mensuelle', 'm10-evaluations'),
  ('Journal de paie', 'm11-calcul'),
  ('État des cotisations CNSS', 'm11-cotisations'),
  ('État ITS', 'm11-cotisations'),
  ('État VPS', 'm11-cotisations'),
  ('État des primes', 'm10-primes'),
  ('Journaux comptables', 'm12-journaux'),
  ('Grand livre', 'm12-grand-livre'),
  ('Balance générale', 'm12-balance'),
  ('Balance âgée', 'm12-balance'),
  ('Tableau d’amortissement', 'm12-immobilisations'),
  ('État de rapprochement bancaire', 'm12-banques'),
  ('Bilan', 'm12-etats-financiers'),
  ('Compte de résultat', 'm12-compte-resultat'),
  ('Tableau des flux de trésorerie', 'm12-flux-tresorerie'),
  ('Registre des courriers', 'm13-courriers'),
  ('Compte rendu de réunion', 'm13-reunions'),
  ('Plan annuel de travail', 'm13-plan-annuel'),
  ('Note de service', 'm13-notes-service'),
  ('Tableau de bord financier', 'dash-direction'),
  ('Tableau de bord stock', 'm6-dashboard'),
  ('Tableau de bord RH', 'm10-dashboard'),
  ('Tableau de bord d’activité', 'dash-direction'),
  ('Rapport d’activité', 'dash-direction'),
  ('Journal d’audit', 'm14-audit'),
  ('Liste des comptes utilisateurs et rôles', 'm14-utilisateurs'),
];

// ----------------------------------------------------------------------------------------------------------------------------------------------
// Les pièces imprimées (`P.etat` + `P.tableau`) : cartouche et tableaux, dont les TOTAUX sont refaits depuis les lignes imprimées
// ----------------------------------------------------------------------------------------------------------------------------------------------

/// Le tableau imprimé du point de la Direction : première colonne = l'axe (en minuscules, comme la maquette), Pièces, Quantité vendue, Montant ;
/// pied « CUMUL GLOBAL » calculé par `somme`.
TableauEtat rapTableauDirection(List<RapPoste> rows, RapAxe axe) => TableauEtat(
      libelleTotal: 'CUMUL GLOBAL',
      lignes: [
        for (final r in rows) {'libelle': r.libelle, 'pieces': r.pieces, 'quantite': r.quantite, 'montant': r.montant}
      ],
      colonnes: [
        ColonneEtat(libelle: axe.sansPar, valeur: (r) => r['libelle']),
        ColonneEtat(libelle: 'Pièces', droite: true, valeur: (r) => nombre(r['pieces']), somme: (r) => r['pieces'] as num),
        ColonneEtat(libelle: 'Quantité vendue', droite: true, valeur: (r) => nombre(r['quantite']), somme: (r) => r['quantite'] as num),
        ColonneEtat(libelle: 'Montant', droite: true, valeur: (r) => money(r['montant'], avecDevise: false), somme: (r) => r['montant'] as num),
      ],
    );

/// Le cartouche de l'état de la Direction.
List<(String, String)> rapCartoucheDirection(RapBornes b, RapAxe axe, {required int pieces, required double cumul}) => [
      ('Périodicité', b.libelle),
      ('Du', b.debutFR),
      ('Au', b.finFR),
      ('Axe d’analyse', axe.libelle),
      ('Pièces émises', nombre(pieces)),
      ('Cumul global', money(cumul)),
    ];

/// Le rapport composé par le générateur : en-tête, cartouche et une table (libellé → valeur) par section cochée.
class RapRapport {
  const RapRapport(this.titre, this.sousTitre, this.filigrane, this.cartouche, this.sections);
  final String titre;
  final String? sousTitre, filigrane;
  final List<(String, String)> cartouche;

  /// (intitulé imprimé, indicateurs)
  final List<(String, List<(String, String)>)> sections;
}

/// `generer()` : [sectionsCochees] se rangent dans l'ordre des sections de la maquette (pas dans l'ordre des clics).
RapRapport rapComposerRapport({
  required String titre,
  String? sousTitre,
  String? destinataire,
  required String periode,
  Object? dateDebut,
  Object? dateFin,
  String? filigrane,
  required Iterable<String> sectionsCochees,
  required String utilisateur,
  required RapSources sources,
}) {
  final actives = [for (final s in rapSections) if (sectionsCochees.contains(s.id)) s];
  String jour(Object? d) {
    final ms = rapMs(d);
    return ms == null ? '—' : dateFR(_jourUtc(ms));
  }

  return RapRapport(
    titre,
    rapVrai(sousTitre) ? sousTitre : null,
    rapVrai(filigrane) ? filigrane : null,
    [
      ('Période', periode),
      ('Du', jour(dateDebut)),
      ('Au', jour(dateFin)),
      ('Destinataire', rapOu(destinataire, 'Usage interne')),
      ('Sections', nombre(actives.length)),
      ('Généré par', utilisateur),
    ],
    [for (final s in actives) (s.intitule, rapDonneesSection(s.id, sources))],
  );
}
