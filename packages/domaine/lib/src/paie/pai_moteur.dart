/// M11 — PAIE & PRIMES : le moteur de calcul et les règles chiffrées des neuf écrans (`prototype_html/assets/js/modules/m11-paie.js`).
///
/// La maquette tient UN SEUL point d'entrée de calcul (`calculer`) que consomment le tableau de bord, le calcul, les bulletins, les cotisations et
/// l'état ORTB : cohérence garantie, et c'est ce qu'on conserve. Les fonctions reçoivent les fiches EN ARGUMENT (la maquette lisait le magasin) et
/// sont rejouées sur des vecteurs tirés des ÉCRANS RÉELS pilotés dans Chrome (`test/vecteurs/paie.json`, engendré par
/// `prototype_html/build/vecteurs-paie.js`) — plusieurs fonctions, bruts et mois, dont mars et juin pour l'ORTB. Aucun taux, barème ni montant n'est
/// inventé : tout vient de `D.PARAM_PAIE` et `D.NS132` de la maquette (constantes vérifiées contre elle par le test).
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../referentiels/regles.dart' show joursEntre;

typedef PaiFiche = Map<String, Object?>;

// --- les paramètres de la paie (`D.PARAM_PAIE`) — CDCT §10.10 ------------------------------------------------------------------------------
/// CNSS : part ouvrière 3,6 %, part patronale 16,4 % (sans plafond).
const double paiCnssOuvriere = 3.6;
const double paiCnssPatronale = 16.4;

/// VPS : 4 % du salaire brut (versement patronal de solidarité).
const double paiVpsTaux = 4;

/// Une tranche du barème ITS : de [de] à [a] (`null` = sans plafond), au taux [taux] (%).
class PaiTranche {
  const PaiTranche(this.de, this.a, this.taux);
  final num de;
  final num? a;
  final num taux;
}

/// Barème ITS « à confirmer par le service comptable » (source de la maquette, conservée).
const List<PaiTranche> paiBaremeIts = [
  PaiTranche(0, 60000, 0),
  PaiTranche(60001, 150000, 10),
  PaiTranche(150001, 250000, 15),
  PaiTranche(250001, 500000, 19),
  PaiTranche(500001, null, 30),
];

/// Une redevance ORTB annuelle : DEUX redevances qui SE CUMULENT (Direction, 20/08/2026).
class PaiRedevance {
  const PaiRedevance(
      {required this.id,
      required this.code,
      required this.categorie,
      required this.libelle,
      required this.montant,
      required this.mois,
      required this.moisLabel,
      required this.seuilMin,
      required this.seuilMax,
      required this.assiette});
  final String id, code, categorie, libelle, moisLabel, assiette;
  final num montant;

  /// Mois de prélèvement, de 0 (janvier) à 11.
  final int mois;
  final num? seuilMin, seuilMax;
}

/// Radio : 1 000 F pour TOUS les salariés, en mars. Télé : 3 000 F au-delà de 60 000 F de brut, en juin, EN SUS.
const List<PaiRedevance> paiRedevances = [
  PaiRedevance(
      id: 'radio',
      code: 'ORTB-RADIO',
      categorie: 'Radio',
      libelle: 'Redevance ORTB / Radio',
      montant: 1000,
      mois: 2,
      moisLabel: 'mars',
      seuilMin: null,
      seuilMax: null,
      assiette: 'Tous les salariés, sans exception'),
  PaiRedevance(
      id: 'tele',
      code: 'ORTB-TELE',
      categorie: 'Télé',
      libelle: 'Redevance ORTB / Télé',
      montant: 3000,
      mois: 5,
      moisLabel: 'juin',
      seuilMin: 60001,
      seuilMax: null,
      assiette: 'Salaire brut supérieur à 60 000 FCFA'),
];
const num paiSeuilTele = 60000;
const num paiCumulMaximum = 4000;

/// Une prime de la note NS 132/07/DM/DA/CNT/2026 : `fixe` = forfait mensuel, `occurrence` = selon le nombre de gardes / permanences.
class PaiPrime {
  const PaiPrime(this.id, this.libelle, this.mode, this.montants);
  final String id, libelle, mode;
  final Map<String, num> montants;
}

/// `D.NS132.primes` : le barème d'origine de la note (repli quand la grille n'est pas au magasin ; l'ORDRE des primes est celui du bulletin).
const List<PaiPrime> paiPrimesNs132 = [
  PaiPrime('permanence', 'Permanence', 'occurrence',
      {'aide_soignant': 600, 'caissiere': 600, 'accueil': 700, 'infirmier': 800, 'sage_femme': 800, 'tsl': 800}),
  PaiPrime('garde', 'Garde', 'occurrence',
      {'aide_soignant': 900, 'caissiere': 900, 'accueil': 900, 'infirmier': 1500, 'sage_femme': 1500, 'tsl': 1500}),
  PaiPrime('aide_bloc', 'Aide bloc', 'occurrence',
      {'aide_soignant': 500, 'caissiere': 500, 'accueil': 500, 'infirmier': 500, 'sage_femme': 500}),
  PaiPrime('bloc_fixe', 'Prime de bloc fixe', 'fixe', {'aide_soignant': 10000, 'infirmier': 10000}),
  PaiPrime('hydrotubation', 'Hydrotubation', 'occurrence', {'infirmier': 1300}),
  PaiPrime('accouchement', 'Accouchement', 'occurrence', {'sage_femme': 1000}),
  PaiPrime('caisse', 'Caisse', 'fixe', {'caissiere': 10000}),
  PaiPrime('urgence', 'Urgence', 'occurrence', {'tsl': 2500}),
  PaiPrime('incineration', 'Incinération', 'fixe', {'aide_soignant': 5000}),
  PaiPrime('accueil', 'Accueil', 'fixe', {'accueil': 7000}),
  PaiPrime('circoncision', 'Circoncision', 'occurrence', {'sage_femme': 1000}),
];

/// `D.FONCTIONS` (id → libellé) : les colonnes de la grille des primes et les fonctions du personnel.
const Map<String, String> paiFonctions = {
  'aide_soignant': 'Aide-soignant(e)',
  'caissiere': 'Caissière',
  'accueil': 'Accueil / Secrétaire médical',
  'infirmier': 'Infirmier(ère)',
  'sage_femme': 'Sage-femme',
  'tsl': 'TSL (Technicien Supérieur de Laboratoire)',
  'biomedical': 'Ingénieur biomédical',
  'medecin': 'Médecin',
  'direction': 'Direction',
  'comptable': 'Comptable',
  'stock': 'Gestionnaire de stock',
  'dispensatrice': 'Dispensatrice',
  'securite': 'Agent de sécurité',
  'entretien': 'Agent d’entretien',
  'chauffeur': 'Chauffeur coursier',
};

/// `fonctionLabel(id)` : le libellé, ou l'identifiant lui-même s'il est inconnu.
String paiFonctionLibelle(Object? id) => paiFonctions['$id'] ?? '${id ?? ''}';

/// `D.SERVICES`.
const List<String> paiServices = [
  'Médecine générale',
  'Maternité',
  'Chirurgie',
  'Laboratoire',
  'Pharmacie',
  'Imagerie / Échographie',
  'Soins infirmiers',
  'Accueil',
  'Direction',
  'Comptabilité',
];

/// `C.MOIS` (minuscules, comme la maquette) et sa forme capitalisée « Octobre ».
const List<String> paiMois = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre'
];
String paiMoisCap(int mois) => paiMois[mois][0].toUpperCase() + paiMois[mois].substring(1);

/// « Octobre 2026 » : le libellé de période des évaluations NS 131, des bulletins et des déclarations d'heures.
String paiPeriodeLibelle(int annee, int mois) => '${paiMoisCap(mois)} $annee';

// --- aides ---------------------------------------------------------------------------------------------------------------------------------
double _n(Object? v) => nombreOuZero(v);
bool _actif(PaiFiche f) => f['statut'] != 'archive';
bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;
String _p2(int n) => n.toString().padLeft(2, '0');
double _somme(Iterable<PaiFiche> l, String k) => l.fold(0.0, (a, x) => a + _n(x[k]));

final _dateSeule = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// `C.toDate` : `YYYY-MM-DD` seul = minuit UTC (la sémantique de `new Date(texte)`).
DateTime paiDate(Object? v) {
  if (v is DateTime) return v;
  final t = '${v ?? ''}';
  if (_dateSeule.hasMatch(t)) return DateTime.parse('${t}T00:00:00Z');
  return DateTime.tryParse(t) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// `Math.floor(C.daysBetween(e.dateEmbauche, AUJ) / 365.25)` : l'ancienneté en années entières.
int paiAnciennete(PaiFiche employe, DateTime aujourdhui) =>
    (joursEntre(paiDate(employe['dateEmbauche']), aujourdhui.toUtc()) / 365.25).floor();

/// `calculITS(base)` : barème progressif par tranches, arrondi au franc. `+ 1` sauf pour la première tranche (qui commence à 0).
int paiCalculIts(num base) {
  var impot = 0.0;
  for (final t in paiBaremeIts) {
    final plafond = t.a ?? double.infinity;
    final b = base.toDouble();
    final tranche = (b < plafond ? b : plafond.toDouble()) - t.de + (t.de == 0 ? 0 : 1);
    final positive = tranche > 0 ? tranche : 0;
    if (positive > 0) impot += positive * t.taux / 100;
  }
  return arrondiJs(impot).toInt();
}

// --- la redevance ORTB ---------------------------------------------------------------------------------------------------------------------
/// Une ligne de redevance applicable à un brut : [montant] n'est porté que sur le bulletin du mois de prélèvement ([du]), [montantAnnuel] toujours.
class PaiLigneOrtb {
  const PaiLigneOrtb(this.def, this.montant, this.du);
  final PaiRedevance def;
  final num montant;
  final bool du;
  String get id => def.id;
  String get categorie => def.categorie;
  String get libelle => def.libelle;
  String get moisLabel => def.moisLabel;
  int get mois => def.mois;
  num get montantAnnuel => def.montant;
}

class PaiOrtb {
  const PaiOrtb(this.lignes);
  final List<PaiLigneOrtb> lignes;
  PaiLigneOrtb? get radio => lignes.where((l) => l.id == 'radio').firstOrNull;
  PaiLigneOrtb? get tele => lignes.where((l) => l.id == 'tele').firstOrNull;
  PaiLigneOrtb? parCategorie(String id) => lignes.where((l) => l.id == id).firstOrNull;
  num get montant => lignes.fold<num>(0, (a, l) => a + l.montant);
  num get montantAnnuel => lignes.fold<num>(0, (a, l) => a + l.montantAnnuel);
  bool get du => montant > 0;
  String get resume => lignes.map((l) => '${l.categorie} ${money(l.montantAnnuel, avecDevise: false)} en ${l.moisLabel}').join(' · ');
}

/// `calculOrtb(brut, mois)` : UNE LIGNE PAR CATÉGORIE APPLICABLE, chacune ne portant son montant que sur le bulletin de SON mois — la compter chaque
/// mois majorerait les retenues de onze douzièmes. Les deux redevances se CUMULENT : filtrer pour n'en garder qu'une dispenserait de la radio les
/// salaires élevés. Le seuil se lit sur le BRUT (avant sanction).
PaiOrtb paiCalculOrtb(num brut, int mois) => PaiOrtb([
      for (final r in paiRedevances)
        if ((r.seuilMin == null || brut >= r.seuilMin!) && (r.seuilMax == null || brut <= r.seuilMax!)) PaiLigneOrtb(r, mois == r.mois ? r.montant : 0, mois == r.mois)
    ]);

/// Une ligne de retenue ORTB d'un bulletin (`lignesOrtb`) : une catégorie non prélevée ce mois-ci reste affichée (tiret) — le bulletin dit de quoi
/// l'agent est redevable, pas seulement ce qu'il paie ce mois.
class PaiLigneRetenueOrtb {
  const PaiLigneRetenueOrtb(this.libelle, this.base, this.montant);
  final String libelle, base, montant;
}

List<PaiLigneRetenueOrtb> paiLignesOrtb(PaiOrtb? d) {
  if (d == null || d.lignes.isEmpty) return [PaiLigneRetenueOrtb('Redevance ORTB', 'Non applicable', money(0, avecDevise: false))];
  return [
    for (final l in d.lignes)
      PaiLigneRetenueOrtb(l.libelle, l.du ? 'Annuelle, prélevée ce mois' : 'Annuelle, prélevée en ${l.moisLabel}', l.du ? money(l.montant, avecDevise: false) : '—')
  ];
}

/// Le détail ORTB tel que le bulletin STOCKÉ le porte (`detailOrtb` : lignes, id, libellé, mois, montants) — relu en [PaiOrtb].
PaiOrtb? paiOrtbDeFiche(Object? detail) {
  if (detail is! Map) return null;
  final lignes = detail['lignes'];
  if (lignes is! List) return null;
  return PaiOrtb([
    for (final l in lignes.whereType<Map>())
      if (paiRedevances.where((r) => r.id == l['id']).firstOrNull case final r?) PaiLigneOrtb(r, _n(l['montant']), l['du'] == true)
  ]);
}

/// Le détail ORTB d'un calcul, tel qu'il s'ÉCRIT dans le bulletin stocké.
Map<String, Object?> paiOrtbVersFiche(PaiOrtb d) {
  Map<String, Object?> ligne(PaiLigneOrtb l) => {
        'id': l.id,
        'code': l.def.code,
        'categorie': l.categorie,
        'libelle': l.libelle,
        'assiette': l.def.assiette,
        'moisLabel': l.moisLabel,
        'mois': l.mois,
        'montantAnnuel': l.montantAnnuel,
        'montant': l.montant,
        'du': l.du,
      };
  return {
      'lignes': [for (final l in d.lignes) ligne(l)],
      'parCategorie': {for (final l in d.lignes) l.id: ligne(l)},
      'montant': d.montant,
      'montantAnnuel': d.montantAnnuel,
      'du': d.du,
      'resume': d.resume,
    };
}

// --- la grille des primes NS 132, lue À LA DATE ---------------------------------------------------------------------------------------------
/// `D.NS132.montantOrigine(primeId, fonctionId)` : le barème d'origine de la note, indépendant du magasin.
num paiMontantOrigine(String primeId, String fonction) {
  final p = paiPrimesNs132.where((x) => x.id == primeId).firstOrNull;
  final m = p?.montants[fonction];
  return (m == null || m == 0) ? 0 : m;
}

num _montantDe(Object? montants, String fonction) {
  if (montants is! Map) return 0;
  final v = montants[fonction];
  return _vrai(v) ? (v as num) : 0;
}

/// `D.NS132.montant(primeId, fonctionId, date)` : la grille vit au magasin (`grillePrimes`), chaque prime porte sa date d'effet ; pour une date
/// ANTÉRIEURE on remonte `historiquePrimes` jusqu'à la version en vigueur ce jour-là. Une prime relevée en octobre ne gonfle pas le bulletin de
/// juillet, déjà calculé et souvent payé. Sans fiche courante pour cette prime, c'est le barème d'origine qui répond.
num paiMontantPrime(String primeId, String fonction, String? date, List<PaiFiche> grille, List<PaiFiche> historique) {
  final courant = grille.where(_actif).where((x) => x['primeId'] == primeId).firstOrNull;
  if (courant == null) return paiMontantOrigine(primeId, fonction);
  if (!_vrai(date) || !_vrai(courant['dateEffet']) || date!.compareTo('${courant['dateEffet']}') >= 0) {
    return _montantDe(courant['montants'], fonction);
  }
  final versions = historique.where(_actif).where((x) => x['primeId'] == primeId).where((v) {
    final debut = !_vrai(v['dateEffet']) || date.compareTo('${v['dateEffet']}') >= 0;
    final fin = !_vrai(v['dateFin']) || date.compareTo('${v['dateFin']}') <= 0;
    return debut && fin;
  }).toList();
  // `sort` décroissant sur la date d'effet : l'Array.prototype.sort de JS est stable, l'indice d'origine départage.
  final tries = [for (final (i, v) in versions.indexed) (i, v)]..sort((a, b) {
      final c = '${b.$2['dateEffet']}'.compareTo('${a.$2['dateEffet']}');
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  if (tries.isNotEmpty) return _montantDe(tries.first.$2['montants'], fonction);
  return paiMontantOrigine(primeId, fonction);
}

/// `C.referenceSuivante(prefixe, largeur, fiches)` : le plus grand rang déjà écrit pour ce préfixe — fiches archivées COMPRISES —, plus un. La série suit
/// le registre, jamais un compteur de page (E680 : `C.nextRef` redonnait « HS-0001 » à la première déclaration, déjà portée par une fiche du jeu).
String paiReferenceSuivante(String prefixe, int largeur, Iterable<PaiFiche> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final m = RegExp(r'^\s*[-+]?\d+').stringMatch(r.substring(prefixe.length));
      final k = m == null ? 0 : (int.tryParse(m.trim()) ?? 0);
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

// --- le moteur de calcul de la paie ----------------------------------------------------------------------------------------------------------
/// Ce que le moteur lit au magasin : planning validé, évaluations NS 131, avances, participations imputées sur salaire, grille des primes et son historique.
class PaiEntrees {
  const PaiEntrees(
      {this.planning = const [], this.evaluations = const [], this.avances = const [], this.participations = const [], this.grille = const [], this.historique = const []});
  final List<PaiFiche> planning, evaluations, avances, participations, grille, historique;
}

class PaiLignePrime {
  const PaiLignePrime(this.id, this.libelle, this.unitaire, this.nombre, this.total);
  final String id, libelle;
  final num unitaire, total;
  final int nombre;
}

/// Le résultat de `calculer(employe, annee, mois)`. [coutEmployeur] (brut après sanction + CNSS patronale + VPS) et les retenues de l'AGENT
/// (CNSS ouvrière, ITS, ORTB, avances, participations) sont DEUX grandeurs qui ne s'additionnent jamais.
class PaiCalcul {
  PaiCalcul(
      {required this.employe,
      required this.periode,
      required this.annee,
      required this.mois,
      required this.gardes,
      required this.permanences,
      required this.salaireBase,
      required this.anciennete,
      required this.primeAnciennete,
      required this.lignesPrimes,
      required this.totalPrimes,
      required this.brut,
      required this.pctSanction,
      required this.sanction,
      required this.brutApresSanction,
      required this.cnssOuvriere,
      required this.cnssPatronale,
      required this.vps,
      required this.its,
      required this.ortb,
      required this.detailOrtb,
      required this.ortbRadio,
      required this.ortbTele,
      required this.avances,
      required this.avancesDetail,
      required this.participations,
      required this.participationsDetail,
      required this.totalRetenues,
      required this.net,
      required this.coutEmployeur});
  final PaiFiche employe;
  final String periode;
  final int annee, mois, gardes, permanences, anciennete;
  final num salaireBase, primeAnciennete, totalPrimes, brut, pctSanction, sanction, brutApresSanction;
  final List<PaiLignePrime> lignesPrimes;
  final num cnssOuvriere, cnssPatronale, vps, its, ortb, ortbRadio, ortbTele, avances, participations, totalRetenues, net, coutEmployeur;
  final PaiOrtb detailOrtb;
  final List<PaiFiche> avancesDetail, participationsDetail;

  String get matricule => '${employe['matricule'] ?? ''}';
  String get nomComplet => '${employe['nomComplet'] ?? ''}';
}

int _compter(List<PaiFiche> planning, String employeId, int annee, int mois, String type) => planning.where(_actif).where((p) {
      if (p['employeId'] != employeId || p['type'] != type) return false;
      final d = paiDate(p['date']).toLocal();
      return d.year == annee && d.month - 1 == mois;
    }).length;

/// `calculer(employe, annee, mois)` — UN SEUL point d'entrée : toutes les vues consomment ce calcul.
///
/// La chaîne : planning validé → primes NS 132 (grille lue À LA DATE du bulletin, le 28 du mois) → prime d'ancienneté (2 % du salaire de base par
/// année, à partir de 2 ans) → sanction NS 131 de la période (pourcentage du BRUT) → cotisations (CNSS, VPS, ITS sur le brut après sanction moins
/// la part ouvrière) → ORTB (sur le brut AVANT sanction, une ligne par catégorie, au seul mois de prélèvement) → avances en cours → participations
/// imputées sur CE mois seulement. La sanction n'entre PAS dans les retenues : elle diminue le brut.
PaiCalcul paiCalculer(PaiFiche employe, int annee, int mois, PaiEntrees e, DateTime aujourdhui) {
  final id = employe['id'];
  final gardes = _compter(e.planning, '$id', annee, mois, 'garde');
  final permanences = _compter(e.planning, '$id', annee, mois, 'permanence');
  final fonction = '${employe['fonction'] ?? ''}';

  final dateBulletin = '${annee.toString().padLeft(4, '0')}-${_p2(mois + 1)}-28';
  final lignesPrimes = <PaiLignePrime>[];
  for (final pr in paiPrimesNs132) {
    final montant = paiMontantPrime(pr.id, fonction, dateBulletin, e.grille, e.historique);
    if (montant == 0) continue;
    final nb = pr.mode == 'fixe' ? 1 : (pr.id == 'garde' ? gardes : (pr.id == 'permanence' ? permanences : 0));
    if (nb == 0) continue;
    lignesPrimes.add(PaiLignePrime(pr.id, pr.libelle, montant, nb, montant * nb));
  }
  final totalPrimes = lignesPrimes.fold<num>(0, (a, l) => a + l.total);

  final ans = paiAnciennete(employe, aujourdhui);
  final salaireBase = _n(employe['salaireBase']);
  final primeAnciennete = ans >= 2 ? arrondiJs(salaireBase * 0.02 * ans) : 0.0;
  final brut = salaireBase + primeAnciennete + totalPrimes;

  final periode = paiPeriodeLibelle(annee, mois);
  final evaluation = e.evaluations.where(_actif).where((x) => x['employeId'] == id && x['periode'] == periode).firstOrNull;
  final pctSanction = evaluation == null ? 0 : _n(evaluation['prelevementPct']);
  final sanction = arrondiJs(brut * pctSanction / 100);
  final brutApresSanction = brut - sanction;

  final cnssOuvriere = arrondiJs(brutApresSanction * paiCnssOuvriere / 100);
  final cnssPatronale = arrondiJs(brutApresSanction * paiCnssPatronale / 100);
  final vps = arrondiJs(brutApresSanction * paiVpsTaux / 100);
  final its = paiCalculIts(brutApresSanction - cnssOuvriere);
  final detailOrtb = paiCalculOrtb(brut, mois);
  final ortb = detailOrtb.montant;

  final avancesEnCours = e.avances.where(_actif).where((a) => a['employeId'] == id && a['statutAvance'] == 'en_cours').toList();
  final totalAvances = _somme(avancesEnCours, 'mensualite');

  final moisRetenue = '${annee.toString().padLeft(4, '0')}-${_p2(mois + 1)}';
  final participationsMois = e.participations.where(_actif).where((x) => x['employeId'] == id && x['mode'] == 'salaire' && x['periodeRetenue'] == moisRetenue).toList();
  final totalParticipations = _somme(participationsMois, 'montant');

  final totalRetenues = cnssOuvriere + its + ortb + totalAvances + totalParticipations;
  return PaiCalcul(
      employe: employe,
      periode: periode,
      annee: annee,
      mois: mois,
      gardes: gardes,
      permanences: permanences,
      salaireBase: salaireBase,
      anciennete: ans,
      primeAnciennete: primeAnciennete,
      lignesPrimes: lignesPrimes,
      totalPrimes: totalPrimes,
      brut: brut,
      pctSanction: pctSanction,
      sanction: sanction,
      brutApresSanction: brutApresSanction,
      cnssOuvriere: cnssOuvriere,
      cnssPatronale: cnssPatronale,
      vps: vps,
      its: its,
      ortb: ortb,
      detailOrtb: detailOrtb,
      ortbRadio: detailOrtb.radio?.montant ?? 0,
      ortbTele: detailOrtb.tele?.montant ?? 0,
      avances: totalAvances,
      avancesDetail: avancesEnCours,
      participations: totalParticipations,
      participationsDetail: participationsMois,
      totalRetenues: totalRetenues,
      net: brutApresSanction - totalRetenues,
      coutEmployeur: brutApresSanction + cnssPatronale + vps);
}

/// `calculerTous(annee, mois)` : tout le personnel ACTIF, dans l'ordre de la collection.
List<PaiCalcul> paiCalculerTous(Iterable<PaiFiche> personnel, int annee, int mois, PaiEntrees e, DateTime aujourdhui) =>
    [for (final p in personnel.where(_actif)) paiCalculer(p, annee, mois, e, aujourdhui)];

/// `C.sum(calc, 'clé')` sur un champ numérique d'un calcul.
num paiSomme(Iterable<PaiCalcul> l, num Function(PaiCalcul) f) => l.fold<num>(0, (a, c) => a + f(c));

/// Le « reste » d'une avance affiché au calcul : la somme des restes dus des avances en cours (jamais négatif).
num paiResteAvances(Iterable<PaiFiche> avances) => avances.fold<num>(0, (a, x) {
      final r = _n(x['montant']) - _n(x['rembourse']);
      return a + (r > 0 ? r : 0);
    });

// --- le bulletin STOCKÉ --------------------------------------------------------------------------------------------------------------------
/// La fiche que « Générer les bulletins » insère, un bulletin par agent : AUCUN montant n'est saisi, tout découle du calcul. Statut `a_valider` :
/// aucun bulletin ne se diffuse sans la validation formelle de la Direction. Le détail ORTB et les participations voyagent avec la pièce (E682).
PaiFiche paiBulletinDe(PaiCalcul c, String reference) => {
      'reference': reference,
      'periode': c.periode,
      'annee': c.annee,
      'mois': c.mois,
      'employeId': c.employe['id'],
      'employe': c.employe['nomComplet'],
      'matricule': c.employe['matricule'],
      'fonction': c.employe['fonction'],
      'service': c.employe['service'],
      'categorie': c.employe['categorie'],
      'cnss': c.employe['cnss'],
      'situation': c.employe['situation'],
      'telephone': c.employe['telephone'],
      'salaireBase': c.salaireBase,
      'primeAnciennete': c.primeAnciennete,
      'lignesPrimes': [
        for (final l in c.lignesPrimes) {'id': l.id, 'label': l.libelle, 'unitaire': l.unitaire, 'nombre': l.nombre, 'total': l.total}
      ],
      'totalPrimes': c.totalPrimes,
      'brut': c.brut,
      'pctSanction': c.pctSanction,
      'sanction': c.sanction,
      'cnssOuvriere': c.cnssOuvriere,
      'cnssPatronale': c.cnssPatronale,
      'vps': c.vps,
      'its': c.its,
      'ortb': c.ortb,
      'avances': c.avances,
      'detailOrtb': paiOrtbVersFiche(c.detailOrtb),
      'participations': c.participations,
      'participationsDetail': [
        for (final x in c.participationsDetail) {'evenementLibelle': x['evenementLibelle'], 'montant': x['montant']}
      ],
      'totalRetenues': c.totalRetenues,
      'net': c.net,
      'coutEmployeur': c.coutEmployeur,
      'statutBulletin': 'a_valider',
    };

/// Un lot de paie par période (`parPeriode` de la validation) : l'ordre est celui de la PREMIÈRE apparition de la période dans la collection.
class PaiLot {
  const PaiLot(this.periode, this.nb, this.brut, this.net, this.cnss, this.aValider, this.valides);
  final String periode;
  final int nb, aValider, valides;
  final num brut, net, cnss;
}

List<PaiLot> paiLots(Iterable<PaiFiche> bulletinsActifs) {
  final g = <String, List<PaiFiche>>{};
  for (final b in bulletinsActifs) {
    g.putIfAbsent('${b['periode']}', () => []).add(b);
  }
  return [
    for (final k in g.keys)
      PaiLot(k, g[k]!.length, _somme(g[k]!, 'brut'), _somme(g[k]!, 'net'), _somme(g[k]!, 'cnssOuvriere') + _somme(g[k]!, 'cnssPatronale'),
          g[k]!.where((x) => x['statutBulletin'] == 'a_valider').length, g[k]!.where((x) => x['statutBulletin'] != 'a_valider').length)
  ];
}

// --- heures supplémentaires ---------------------------------------------------------------------------------------------------------------
/// Le taux horaire majoré : salaire de base / 173,33, majoré de `Number(majoration) || 25` %, arrondi au franc.
int paiTauxHoraire(num salaireBase, Object? majoration) {
  final m = _n(majoration);
  return arrondiJs(salaireBase / 173.33 * (1 + (m == 0 ? 25 : m) / 100)).toInt();
}

/// `transform` de la déclaration d'heures : l'agent, son taux horaire (recalculé à chaque enregistrement), le montant = heures × taux.
PaiFiche paiHeuresSupTransform(PaiFiche v, PaiFiche? employe, {required String Function() reference}) {
  final r = {...v};
  if (employe != null) {
    r['employe'] = employe['nomComplet'];
    r['matricule'] = employe['matricule'];
    r['service'] = employe['service'];
    r['tauxHoraire'] = paiTauxHoraire(_n(employe['salaireBase']), v['majoration']);
  }
  r['montant'] = _n(v['heures']) * _n(r['tauxHoraire']);
  if (!_vrai(r['reference'])) r['reference'] = reference();
  return r;
}

// --- avances sur salaire --------------------------------------------------------------------------------------------------------------------
/// `beforeSave` de l'avance : au plus TROIS mois de salaire. Un refus se nomme ; `null` = accepté (pile au plafond compris).
String? paiAvanceRefus(num montant, PaiFiche? employe) {
  if (employe == null) return null;
  final plafond = _n(employe['salaireBase']) * 3;
  if (montant > plafond) return 'Le montant de l’avance ne peut excéder trois mois de salaire (${money(plafond)}).';
  return null;
}

/// `transform` de l'avance : la mensualité = montant / nombre de mensualités (arrondi), remboursé à 0, statut « en cours ».
PaiFiche paiAvanceTransform(PaiFiche v, PaiFiche? employe, {required String Function() reference}) {
  final r = {...v};
  if (employe != null) {
    r['employe'] = employe['nomComplet'];
    r['matricule'] = employe['matricule'];
    r['service'] = employe['service'];
  }
  final nb = _n(v['nbMensualites']);
  r['mensualite'] = arrondiJs(_n(v['montant']) / (nb == 0 ? 1 : nb)).toInt();
  r['rembourse'] ??= 0;
  if (!_vrai(r['statutAvance'])) r['statutAvance'] = 'en_cours';
  if (!_vrai(r['reference'])) r['reference'] = reference();
  return r;
}

// --- prêts-études et avances ----------------------------------------------------------------------------------------------------------------
/// Une échéance du prêt : son rang, le mois de retenue (`AAAA-MM`), son montant, et si elle a DÉJÀ été retenue au bulletin de ce mois.
class PaiEcheance {
  const PaiEcheance(this.rang, this.mois, this.montant, this.retenue);
  final int rang;
  final String mois;
  final num montant;
  final bool retenue;
}

/// L'échéancier, CALCULÉ et jamais saisi : le total des échéances vaut exactement le montant accordé, au franc près (le reliquat d'arrondi tombe sur
/// la DERNIÈRE échéance). Une échéance n'est retenue qu'au bulletin du SEUL mois de son échéance.
List<PaiEcheance> paiEcheancier(PaiFiche p) {
  final nSaisi = _n(p['nbEcheances']).toInt();
  final n = nSaisi == 0 ? 1 : nSaisi;
  final montant = _n(p['montant']);
  final base = (montant / n).floorToDouble();
  final premiere = '${p['premiereEcheance'] ?? ''}';
  final an = int.tryParse(premiere.length >= 4 ? premiere.substring(0, 4) : '') ?? 0;
  final mo = (int.tryParse(premiere.length >= 7 ? premiere.substring(5, 7) : '') ?? 0) - 1;
  final retenues = (p['retenues'] as List?)?.map((x) => '$x').toList() ?? const <String>[];
  return [
    for (var i = 0; i < n; i++)
      () {
        final d = DateTime(an, mo + 1 + i, 1);
        final m = '${d.year}-${_p2(d.month)}';
        return PaiEcheance(i + 1, m, i == n - 1 ? montant - base * (n - 1) : base, retenues.contains(m));
      }()
  ];
}

/// Le reste à recouvrer : la somme des échéances pas encore retenues.
num paiSoldePret(PaiFiche p) => paiEcheancier(p).where((e) => !e.retenue).fold<num>(0, (a, e) => a + e.montant);

String paiNaturePret(Object? n) =>
    const {'pret_etudes': 'Prêt-études', 'avance': 'Avance sur salaire', 'pret_social': 'Prêt social'}['$n'] ?? '$n';

/// `transform` du prêt à la création : référence, agent et matricule recopiés du dossier, aucune échéance retenue.
PaiFiche paiPretTransform(PaiFiche v, PaiFiche? agent, {required String reference}) => {
      ...v,
      'reference': reference,
      'agent': agent == null ? '—' : agent['nomComplet'],
      'matricule': agent?['matricule'],
      'retenues': <String>[],
    };

// --- la redevance ORTB par agent (écran `m11-ortb`) -----------------------------------------------------------------------------------------
class PaiLigneOrtbAgent {
  const PaiLigneOrtbAgent(
      {required this.id,
      required this.matricule,
      required this.agent,
      required this.poste,
      required this.brut,
      required this.radio,
      required this.tele,
      required this.totalAnnuel,
      required this.categorie,
      required this.categorieLabel,
      required this.duCeMois,
      required this.libelleDuCeMois,
      required this.prelevee,
      required this.aPrelever,
      required this.resume});
  final Object? id;
  final String matricule, agent, poste, categorie, categorieLabel, libelleDuCeMois, resume;
  final num brut, radio, tele, totalAnnuel, duCeMois;
  final int prelevee, aPrelever;
}

/// `lignes()` de l'écran ORTB : un agent, ses deux parts, son état sur l'exercice (ce qui est prélevé, dû ce mois, à prélever).
List<PaiLigneOrtbAgent> paiLignesOrtbAgents(Iterable<PaiFiche> personnel, int annee, int mois, PaiEntrees e, DateTime aujourdhui) => [
      for (final p in personnel.where(_actif))
        () {
          final c = paiCalculer(p, annee, mois, e, aujourdhui);
          final d = c.detailOrtb;
          final radio = d.radio, tele = d.tele;
          return PaiLigneOrtbAgent(
              id: p['id'],
              matricule: '${p['matricule']}',
              agent: '${p['nomComplet']}',
              poste: '${p['poste'] ?? ''}',
              brut: c.brut,
              radio: radio?.montantAnnuel ?? 0,
              tele: tele?.montantAnnuel ?? 0,
              totalAnnuel: d.montantAnnuel,
              categorie: tele != null ? 'les_deux' : (radio != null ? 'radio' : 'aucune'),
              categorieLabel: tele != null ? 'Radio + Télé' : (radio != null ? 'Radio seule' : 'Non redevable'),
              duCeMois: d.montant,
              libelleDuCeMois: d.lignes.where((l) => l.du).map((l) => l.categorie).join(' + '),
              prelevee: d.lignes.where((l) => mois > l.mois).length,
              aPrelever: d.lignes.where((l) => mois < l.mois).length,
              resume: d.lignes.isEmpty ? '—' : d.resume);
        }()
    ];

// --- tableau de bord : l'évolution de la masse salariale -------------------------------------------------------------------------------------
/// `G.moisGlissants(12)` : DOUZE mois qui finissent en août 2026 (le point d'ancrage est celui de la maquette, pas l'horloge) — « sept. 25 »…
List<String> paiMoisGlissants([int n = 12]) => [
      for (var i = n - 1; i >= 0; i--)
        () {
          final m = DateTime(2026, 8 - i, 1);
          final nom = paiMois[m.month - 1];
          // `String.prototype.slice(0, 4)` : « mai » reste « mai » (Dart lèverait une erreur de bornes).
          return '${nom.length > 4 ? nom.substring(0, 4) : nom}. ${(m.year % 100).toString().padLeft(2, '0')}';
        }()
    ];

/// La courbe « Évolution de la masse salariale (12 mois) » : un tirage à graine (`C.seeded(1733)`) autour du total des salaires de base — une
/// ILLUSTRATION, non une série comptable ; l'écran la porte telle quelle (écart signalé).
List<int> paiEvolutionMasse(num base, [int n = 12]) {
  var s = 1733;
  double rnd() {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  }

  return [for (var i = 0; i < n; i++) arrondiJs(base * (0.93 + rnd() * 0.14)).toInt()];
}
