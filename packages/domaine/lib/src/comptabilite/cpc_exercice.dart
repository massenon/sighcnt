/// EXERCICES COMPTABLES, CLÔTURE EN DEUX GESTES, À-NOUVEAUX ET LETTRAGE (M12) — port de `SIGH.exercice` (`prototype_html/assets/js/parcours.js`, vague 69) et du
/// bilan d'ouverture de `m12-comptabilite.js` (m12-cloture, m12-ouverture).
///
/// Le moteur est PUR : il lit des listes de fiches et rend soit un verdict, soit un PLAN D'ÉCRITURES (les lignes à insérer, le patch de l'exercice) que le
/// poste applique au magasin — là où se trouvent la journalisation (RG-12) et l'annulation. Les règles se rejouent sur `test/vecteurs/exercice.json`, tiré
/// des écrans et du moteur réels de la maquette dans Chrome.
///
///  * Une clôture est DÉFINITIVE (obligation légale) : un exercice clos ne se rouvre pas, il se corrige par une écriture de l'exercice en cours.
///  * Elle se fait en DEUX GESTES : le comptable DEMANDE (les contrôles bloquants refusent en nommant), la Direction ou la DAF VALIDE avec un motif —
///    jamais le demandeur lui-même (« signer n'est pas saisir »).
///  * La garde de lecture seule se pose SUR LA COLLECTION `ecritures` (voir `CollectionMagasin.garder`) : masquer un bouton ne protège rien.
///
/// HORS DU POSTE (ce que ce fichier ne porte pas) : l'archive de clôture dans la GED (`SIGH.exercice.archiver`), l'export CSV, le sélecteur d'exercice de
/// la coque (le poste lit l'exercice de l'horloge — E717) et les colonnes N-1 tirées du journal sur les états.
library;

import 'dart:convert';

import '../format/format_fr.dart';
import '../format/js.dart';
import 'cpa_ecritures.dart' show cpaAnnee;
import 'cpa_referentiels.dart';
import 'cpc_liasse.dart';

double _n(Object? v) => nombreOuZero(v);
double _som(Iterable<CpaFiche> l, String k) => l.fold<double>(0, (a, x) => a + _n(x[k]));

/// Les comptes de tiers : les seuls LETTRABLES, et les seuls repris ligne à ligne aux à-nouveaux.
const List<String> cpcLettrables = ['40', '41', '42', '43', '44', '47'];

/// Les rôles qui valident une clôture, et ceux qui la demandent (en plus du droit d'édition de M12).
const List<String> cpcRolesValidation = ['da', 'direction', 'admin'];
const List<String> cpcRolesDemande = ['comptable', 'da', 'admin'];

Map<String, Object?>? _liasse;
Map<String, Object?> get cpcLiasse => _liasse ??= (jsonDecode(cpcLiasseJson) as Map).cast<String, Object?>();
Map<String, Object?> get cpcDepot => (cpcLiasse['DEPOT'] as Map).cast<String, Object?>();

bool cpcLettrable(Object? compte) => cpcLettrables.any((p) => '$compte'.startsWith(p));

bool _estDeLiasse(int annee) => cpcDepot['exerciceN'] == annee || cpcDepot['exerciceN1'] == annee;

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// EXERCICES — une fiche par année portée par les écritures, plus l'année courante, plus celles de la liasse déposée (closes d'office)
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// Les fiches d'exercice À AMORCER (`exercices()`), dans l'ordre où la maquette les insère EN TÊTE : années croissantes, donc la plus récente finit première.
/// [exercices] : TOUTES les fiches de la collection (archivées comprises) ; [ecritures] : TOUTES les écritures (archivées comprises).
List<CpaFiche> cpcExercicesAAmorcer(Iterable<CpaFiche> exercices, Iterable<CpaFiche> ecritures, DateTime auj) {
  final annees = <int>{};
  for (final e in ecritures) {
    final a = cpaAnnee(e['date']);
    if (a != null) annees.add(a);
  }
  annees
    ..add(auj.year)
    ..add(cpcDepot['exerciceN'] as int)
    ..add(cpcDepot['exerciceN1'] as int);
  final tries = annees.toList()..sort();
  return [
    for (final a in tries)
      if (!exercices.any((x) => x['annee'] == a))
        () {
          final deposee = _estDeLiasse(a);
          return <String, Object?>{
            'id': 'EXO-$a',
            'annee': a,
            'debut': '$a-01-01',
            'fin': '$a-12-31',
            'statut': 'actif',
            'etat': deposee ? 'clos' : 'ouvert',
            'source': deposee ? 'liasse' : 'journal',
            'valideLe': deposee ? cpcDepot['dateDepot'] : null,
            'validePar': deposee ? 'Liasse déposée à la DGI' : null,
            'motif': deposee ? 'Exercice antérieur à la mise en service : fait par la liasse déposée.' : null,
          };
        }(),
  ];
}

/// `exercices()` : les exercices non archivés, du plus récent au plus ancien.
List<CpaFiche> cpcListeExercices(Iterable<CpaFiche> exercices) {
  final l = [for (final x in exercices) if (x['statut'] != 'archive') x];
  l.sort((a, b) => (_n(b['annee']) - _n(a['annee'])).sign.toInt());
  return l;
}

CpaFiche? cpcExercice(Iterable<CpaFiche> exercices, int annee) {
  for (final x in cpcListeExercices(exercices)) {
    if (x['annee'] == annee) return x;
  }
  return null;
}

/// `etatExercice(annee)` : `clos` (clôturé) · `en_cloture` · `ouvert` (l'ancien `en_attente_cloture` se lit `en_cloture`). Sans fiche amorcée, c'est ce que l'amorçage donnerait : clos pour la liasse déposée.
/// Une fiche ARCHIVÉE ne ferme rien (RG-14) : l'exercice se lit ouvert.
String cpcEtatExercice(Iterable<CpaFiche> exercices, int annee) {
  final x = cpcExercice(exercices, annee);
  if (x != null) return x['etat'] == 'en_attente_cloture' ? 'en_cloture' : '${x['etat'] ?? 'ouvert'}';
  final archivee = exercices.any((f) => f['annee'] == annee && f['statut'] == 'archive');
  if (archivee) return 'ouvert';
  return _estDeLiasse(annee) ? 'clos' : 'ouvert';
}

/// La GARDE posée sur la collection `ecritures` : le motif du refus (nommé) ou `null`.
///  * exercice CLÔTURÉ : lecture seule, y compris pour le comptable (seule la réouverture permet de corriger) ;
///  * exercice EN CLÔTURE : les modules n'écrivent plus ; seul le comptable (ou l'administrateur) y passe ses écritures d'inventaire, en SAISIE MANUELLE ;
///  * les pièces de la clôture elle-même (CL, AN, contre-passations : `origineCloture`) passent à l'INSERTION, jamais à la modification ni à l'archivage.
String? cpcGardeEcritures(Iterable<CpaFiche> exercices, Object? date, {String op = 'inserer', Object? origineCloture, Object? origine, String role = ''}) {
  final a = cpaAnnee(date);
  if (a == null) return null;
  if (origineCloture != null && '$origineCloture'.isNotEmpty && op == 'inserer') return null;
  final etat = cpcEtatExercice(exercices, a);
  if (etat == 'clos') {
    final x = cpcExercice(exercices, a);
    final valideLe = x?['valideLe'] ?? (_estDeLiasse(a) ? cpcDepot['dateDepot'] : null);
    final d = valideLe == null ? null : DateTime.tryParse('$valideLe')?.toLocal();
    return 'Exercice $a clôturé${d != null ? ' le ${dateFR(d)}' : ''} : lecture seule. La correction passe par la réouverture par le comptable (motif obligatoire), ou par une écriture de l’exercice en cours.';
  }
  if (etat == 'en_cloture') {
    if ('$origine' == 'Saisie manuelle' && (role == 'comptable' || role == 'admin')) return null;
    return 'Exercice $a en clôture : les modules n’y écrivent plus. Seul le comptable y passe ses écritures d’inventaire (saisie manuelle) ; sinon dater la pièce de l’exercice ouvert.';
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LECTURES D'UN EXERCICE
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// `ecrituresDe(annee, inclureBrouillons)` : les écritures ACTIVES de l'année — VALIDÉES seulement par défaut (un brouillon n'est pas un fait comptable).
///
/// Le journal CL (clôture) est EXCLU par défaut : les états de N restent ceux d'AVANT la clôture, le compte de résultat montre le résultat de l'année et non
/// zéro. [avecCL] le rétablit (empreinte du journal arrêté, calcul des à-nouveaux).
List<CpaFiche> cpcEcrituresDe(Iterable<CpaFiche> actives, int annee, {bool brouillons = false, bool avecCL = false}) => [
      for (final e in actives)
        if (cpaAnnee(e['date']) == annee && (brouillons || e['statut'] == 'validee') && (avecCL || e['journal'] != 'CL')) e
    ];

/// `soldesParCompte(lignes)` : une ligne par numéro de compte, triées par numéro (ordre des chaînes, comme `Object.keys().sort()`).
List<CpaFiche> cpcSoldesParCompte(Iterable<CpaFiche> lignes) {
  final m = <String, CpaFiche>{};
  for (final e in lignes) {
    final k = '${e['compte']}';
    final x = m.putIfAbsent(k, () => {'compte': k, 'libelle': _libelleCompte(e, k), 'debit': 0.0, 'credit': 0.0});
    x['debit'] = (x['debit'] as double) + _n(e['debit']);
    x['credit'] = (x['credit'] as double) + _n(e['credit']);
  }
  final cles = m.keys.toList()..sort();
  return [
    for (final k in cles) {...m[k]!, 'solde': (m[k]!['debit'] as double) - (m[k]!['credit'] as double)}
  ];
}

String _libelleCompte(CpaFiche e, String k) {
  final l = e['compteLibelle'];
  return l is String && l.isNotEmpty ? l : k;
}

/// `resultatDe(lignes)` : classes 7 (+) moins 6 (−), HAO (8) compris. Positif = bénéfice.
double cpcResultatDe(Iterable<CpaFiche> lignes) {
  var r = 0.0;
  for (final e in lignes) {
    final cl = '${e['compte']}'.isEmpty ? '' : '${e['compte']}'[0];
    if (cl == '6' || cl == '7' || cl == '8') r += _n(e['credit']) - _n(e['debit']);
  }
  return r;
}

/// `lignesDeReport(lignes)` : le report des classes 1 à 5 vers N+1. Comptes NON lettrables : un SOLDE global. Comptes de TIERS : ligne par ligne, seulement
/// les lignes NON lettrées — c'est ce qui permet de suivre sur le nouvel exercice les factures en attente.
List<CpaFiche> cpcLignesDeReport(Iterable<CpaFiche> lignes) {
  final out = <CpaFiche>[];
  final bilan = [
    for (final e in lignes)
      if ('12345'.contains('${e['compte']}'.isEmpty ? '' : '${e['compte']}'[0])) e
  ];
  final tiers = [for (final e in bilan) if (cpcLettrable(e['compte'])) e];
  final autres = [for (final e in bilan) if (!cpcLettrable(e['compte'])) e];
  for (final s in cpcSoldesParCompte(autres)) {
    final solde = s['solde'] as double;
    if (solde.abs() < 1) continue;
    out.add({
      'compte': s['compte'],
      'compteLibelle': s['libelle'],
      'debit': solde > 0 ? solde : 0.0,
      'credit': solde < 0 ? -solde : 0.0,
      'lettrable': false,
    });
  }
  for (final e in tiers) {
    if (_lettre(e) != null) continue;
    final net = _n(e['debit']) - _n(e['credit']);
    if (net.abs() < 1) continue;
    out.add({
      'compte': '${e['compte']}',
      'compteLibelle': e['compteLibelle'],
      'debit': net > 0 ? net : 0.0,
      'credit': net < 0 ? -net : 0.0,
      'lettrable': true,
      'pieceOrigine': e['numero'],
      'libelle': 'Report — ${(e['libelle'] is String && (e['libelle'] as String).isNotEmpty) ? e['libelle'] : e['numero']}',
    });
  }
  return out;
}

String? _lettre(CpaFiche e) {
  final l = e['lettrage'];
  return l is String && l.isNotEmpty ? l : null;
}

/// `aNouveauxProvisoires(annee)` : tant que N-1 n'est pas clos, N voit un report CALCULÉ des soldes validés de N-1 — recalculé à chaque lecture, JAMAIS
/// stocké. Le résultat de N-1 (non encore soldé) est porté au compte 131 / 139. Vide si N-1 est clos ou issu de la liasse.
List<CpaFiche> cpcANouveauxProvisoires(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee, {Iterable<CpaFiche> comptesResultat = const []}) {
  final prec = annee - 1;
  final ex = cpcExercice(exercices, prec);
  if (ex == null || ex['etat'] == 'clos' || ex['source'] == 'liasse') return [];
  final base = cpcEcrituresDe(actives, prec);
  final lignes = cpcLignesDeReport(base);
  final res = cpcResultatDe(base);
  if (res.abs() >= 1) {
    final cr = cpcCompteResultatDe(res, comptesResultat);
    lignes.add({
      'compte': cr.compte,
      'compteLibelle': cr.libelle,
      'debit': res < 0 ? -res : 0.0,
      'credit': res > 0 ? res : 0.0,
      'lettrable': false,
    });
  }
  return [
    for (final l in lignes)
      {
        'id': 'PROV-$annee-${l['compte']}-${l['pieceOrigine'] ?? 'S'}',
        'numero': 'AN-PROV-$annee',
        'date': '$annee-01-01',
        'journal': 'AN',
        'journalLibelle': 'Journal des à-nouveaux (provisoire)',
        'libelle': l['libelle'] ?? 'À-nouveau provisoire',
        'statut': 'validee',
        'provisoire': true,
        'origine': 'Provisoire — calculé',
        ...l,
      }
  ];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// PRÉ-CLÔTURE — des contrôles nommés, chacun avec l'écran où corriger
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpcControle {
  const CpcControle(this.id, this.bloquant, this.ok, this.libelle, this.ecran, this.detail);
  final String id, libelle, ecran, detail;
  final bool bloquant, ok;
}

class CpcPreCloture {
  const CpcPreCloture(this.annee, this.controles, this.resultat, this.nbEcritures);
  final int annee;
  final List<CpcControle> controles;
  final double resultat;
  final int nbEcritures;
  List<CpcControle> get bloquants => [for (final c in controles) if (c.bloquant && !c.ok) c];
}

/// Contrôle d'une modification de la table des comptes de résultat (miroir de `controleCompteResultat` de la maquette) : un compte de bénéfice est un 131,
/// un compte de perte un 139 (SYSCOHADA), six chiffres, libellé obligatoire. Retourne le motif du refus, ou null.
String? cpcControleCompteResultat(CpaFiche fiche, {required Object? compte, required Object? libelle}) {
  final c = '${compte ?? ''}'.trim();
  final l = '${libelle ?? ''}'.trim();
  final benefice = fiche['sens'] == 'benefice';
  final prefixe = benefice ? '131' : '139';
  final nom = benefice ? 'bénéfice' : 'perte';
  if (!RegExp(r'^\d{6}$').hasMatch(c)) return 'Le compte de $nom doit comporter six chiffres (reçu « $c »).';
  if (!c.startsWith(prefixe)) return 'Le compte de $nom doit appartenir au compte $prefixe du SYSCOHADA (reçu $c).';
  if (l.length < 3) return 'Le libellé du compte de $nom est obligatoire.';
  return null;
}

/// Le compte de résultat (131 bénéfice, 139 perte) lu de la table PARAMÉTRABLE `comptesResultat` : jamais deux constantes dans le moteur. Sans table (ou sans
/// fiche pour le sens), le repli est le plan SYSCOHADA : 131000 et 139000.
({String compte, String libelle}) cpcCompteResultatDe(num resultat, [Iterable<CpaFiche> table = const []]) {
  final sens = resultat >= 0 ? 'benefice' : 'perte';
  for (final f in table) {
    if (f['statut'] != 'archive' && f['sens'] == sens && '${f['compte']}'.isNotEmpty) {
      return (compte: '${f['compte']}', libelle: '${f['libelle'] ?? (resultat >= 0 ? 'Résultat net : bénéfice' : 'Résultat net : perte')}');
    }
  }
  return resultat >= 0
      ? (compte: '131000', libelle: 'Résultat net : bénéfice')
      : (compte: '139000', libelle: 'Résultat net : perte');
}

/// Les fiches de la table `comptesResultat` à AMORCER quand elle est vide.
const List<CpaFiche> cpcComptesResultatDefaut = [
  {'id': 'CR-BEN', 'statut': 'actif', 'sens': 'benefice', 'compte': '131000', 'libelle': 'Résultat net : bénéfice'},
  {'id': 'CR-PER', 'statut': 'actif', 'sens': 'perte', 'compte': '139000', 'libelle': 'Résultat net : perte'},
];

/// Prochain rang d'une pièce de clôture (`CL-2026-00001`, `AN-2027-00001`, `…-C00001` pour les contre-passations) : lu du journal ENTIER (archivées comprises).
int cpcRangPiece(Iterable<CpaFiche> toutes, String prefixe, int annee) {
  final motif = RegExp('^$prefixe-$annee-?[A-Z]?(\\d+)\$');
  var rang = 0;
  for (final e in toutes) {
    final m = motif.firstMatch('${e['numero'] ?? ''}');
    if (m != null) rang = rang > int.parse(m.group(1)!) ? rang : int.parse(m.group(1)!);
  }
  return rang + 1;
}

String _pad5(int n) => n.toString().padLeft(5, '0');

/// `preCloture(annee)` : les contrôles de la clôture définitive. BLOQUANTS : brouillons, journal équilibré, pièces équilibrées, exercice N-1 déjà clôturé,
/// exercice N+1 non clôturé, à-nouveaux déjà écrits (hors ceux contre-passés), écritures validées. INFORMENT : compte 47, opérations en attente d'envoi.
CpcPreCloture cpcPreCloture(Iterable<CpaFiche> actives, int annee, {Iterable<CpaFiche> exercices = const [], int enAttente = 0}) {
  final tous = cpcEcrituresDe(actives, annee, brouillons: true);
  final validees = [for (final e in tous) if (e['statut'] == 'validee') e];
  final brouillons = [for (final e in tous) if (e['statut'] == 'brouillon') e];
  final controles = <CpcControle>[];
  final dejaVus = <String>[];
  for (final e in brouillons.take(4)) {
    final num = '${e['numero']}';
    if (!dejaVus.contains(num)) dejaVus.add(num);
  }
  controles.add(CpcControle('brouillons', true, brouillons.isEmpty, 'Aucune écriture en brouillon', 'm12-ecritures',
      brouillons.isNotEmpty ? '${brouillons.length} ligne(s) en brouillon, dont ${dejaVus.join(', ')}.' : ''));
  final d = _som(validees, 'debit'), c = _som(validees, 'credit');
  controles.add(CpcControle('equilibre', true, (d - c).abs() < 1, 'Journal équilibré (RG-10)', 'm12-balance',
      (d - c).abs() < 1 ? '' : 'Écart de ${money((d - c).abs())} entre débit et crédit.'));
  final pieces = <String, List<double>>{};
  for (final e in validees) {
    final p = pieces.putIfAbsent('${e['numero']}', () => [0, 0]);
    p[0] += _n(e['debit']);
    p[1] += _n(e['credit']);
  }
  final boiteuses = [for (final k in pieces.keys) if ((pieces[k]![0] - pieces[k]![1]).abs() >= 1) k];
  controles.add(CpcControle('pieces', true, boiteuses.isEmpty, 'Chaque pièce validée est équilibrée', 'm12-ecritures',
      boiteuses.isNotEmpty ? '${boiteuses.length} pièce(s) déséquilibrée(s) : ${boiteuses.take(4).join(', ')}.' : ''));
  final prec = cpcExercice(exercices, annee - 1), suiv = cpcExercice(exercices, annee + 1);
  final precOk = prec == null || cpcEtatExercice(exercices, annee - 1) == 'clos';
  controles.add(CpcControle('precedent-clos', true, precOk, 'Exercice ${annee - 1} déjà clôturé', 'm12-cloture',
      precOk ? '' : 'L’exercice ${annee - 1} est ${cpcEtatExercice(exercices, annee - 1) == 'en_cloture' ? 'en clôture' : 'ouvert'} : le clôturer d’abord.'));
  final suivOk = suiv == null || cpcEtatExercice(exercices, annee + 1) != 'clos';
  controles.add(CpcControle('suivant-non-clos', true, suivOk, 'Exercice ${annee + 1} non clôturé', 'm12-cloture',
      suivOk ? '' : 'L’exercice ${annee + 1} est déjà clôturé : impossible de clôturer $annee après lui.'));
  controles.add(CpcControle('postes-a-envoyer', false, enAttente == 0, 'Aucune opération en attente d’envoi sur ce poste', 'm12-cloture',
      enAttente == 0
          ? ''
          : '$enAttente opération(s) à envoyer : synchroniser d’abord, car une fois $annee en clôture la mère refuse les pièces datées de $annee. Les autres postes sont à vérifier de la même façon.'));
  final contrePassees = <String>{for (final e in actives) if (e['contrePasseDe'] != null) '${e['contrePasseDe']}'};
  final an = [
    for (final e in actives)
      if (cpaAnnee(e['date']) == annee + 1 &&
          e['journal'] == 'AN' &&
          e['contrePasseDe'] == null &&
          !contrePassees.contains('${e['numero']}') &&
          e['provisoire'] != true)
        e
  ];
  controles.add(CpcControle('an-existants', true, an.isEmpty, 'Aucun à-nouveau déjà écrit sur ${annee + 1}', 'm12-ouverture',
      an.isNotEmpty ? 'Des à-nouveaux existent (${an.first['numero']}) : les archiver avant de clôturer, la clôture écrit les définitifs.' : ''));
  final attente = [for (final e in validees) if ('${e['compte']}'.startsWith('47')) e];
  final solde47 = _som(attente, 'debit') - _som(attente, 'credit');
  controles.add(CpcControle('compte-47', false, solde47.abs() < 1, 'Comptes d’attente (47x) soldés', 'm12-grand-livre',
      solde47.abs() < 1 ? '' : 'Solde de ${money(solde47.abs())} à régulariser.'));
  controles.add(CpcControle('ecritures', true, validees.isNotEmpty, 'L’exercice porte des écritures validées', 'm12-ecritures',
      validees.isNotEmpty ? '' : 'Aucune écriture validée en $annee.'));
  return CpcPreCloture(annee, controles, cpcResultatDe(validees), validees.length);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LES QUATRE TRANSITIONS : démarrer · reprendre la saisie · clôturer définitivement · rouvrir
// ---------------------------------------------------------------------------------------------------------------------------------------------------

String _iso(DateTime d) => d.toUtc().toIso8601String();

/// Le verdict d'une transition simple (démarrer, reprendre) : refusé EN NOMMANT, ou accepté avec le PATCH à porter sur la fiche d'exercice.
class CpcDemande {
  const CpcDemande.refus(this.motif, [this.pre])
      : ok = false,
        patch = null;
  const CpcDemande.ok(this.pre, this.patch)
      : ok = true,
        motif = null;
  final bool ok;
  final String? motif;
  final CpcPreCloture? pre;
  final CpaFiche? patch;
}

/// TRANSITION 1 : démarrer la clôture (ouvert vers en clôture). Les modules n'écrivent plus dans N ; le comptable passe ses écritures d'inventaire.
CpcDemande cpcDemarrerCloture(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee,
    {required String acteur, String? acteurId, required String role, required DateTime maintenant, int enAttente = 0}) {
  final x = cpcExercice(exercices, annee);
  if (x == null) return CpcDemande.refus('Exercice $annee inconnu.');
  if (x['source'] == 'liasse') {
    return CpcDemande.refus('L’exercice $annee est celui de la liasse déposée : il est clôturé et ne se rouvre pas ici.');
  }
  final etat = cpcEtatExercice(exercices, annee);
  if (etat == 'clos') return CpcDemande.refus('Exercice $annee déjà clôturé : le rouvrir (comptable, motif obligatoire) pour le corriger.');
  if (etat == 'en_cloture') return CpcDemande.refus('L’exercice $annee est déjà en clôture.');
  if (!cpcRolesDemande.contains(role)) {
    return const CpcDemande.refus('Démarrer la clôture est réservé au comptable, à la Directrice Administrative et à l’administrateur.');
  }
  final pre = cpcPreCloture(actives, annee, exercices: exercices, enAttente: enAttente);
  return CpcDemande.ok(pre, {
    'etat': 'en_cloture',
    'demandeLe': _iso(maintenant),
    'demandePar': acteur,
    // A1 : l'IDENTIFIANT de l'agent. Le contrôle « celui qui clôture n'est pas celui qui a démarré » le compare, jamais le libellé.
    if (acteurId != null) 'demandeParId': acteurId,
    'resultatPrevu': pre.resultat,
  });
}

/// Ancien nom du geste 1 (la maquette garde `demander` comme alias).
CpcDemande cpcDemanderCloture(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee,
        {required String acteur, String? acteurId, String role = 'comptable', required DateTime maintenant}) =>
    cpcDemarrerCloture(exercices, actives, annee, acteur: acteur, acteurId: acteurId, role: role, maintenant: maintenant);

/// TRANSITION 2 : reprendre la saisie (en clôture vers ouvert), tant que rien n'est clôturé.
CpcDemande cpcReprendreSaisie(Iterable<CpaFiche> exercices, int annee, {required String acteur, required String role, required DateTime maintenant}) {
  final x = cpcExercice(exercices, annee);
  if (x == null || cpcEtatExercice(exercices, annee) != 'en_cloture') {
    return CpcDemande.refus('L’exercice $annee n’est pas en clôture : rien à reprendre.');
  }
  if (!cpcRolesDemande.contains(role)) {
    return const CpcDemande.refus('Reprendre la saisie est réservé au comptable, à la Directrice Administrative et à l’administrateur.');
  }
  return CpcDemande.ok(null, {'etat': 'ouvert', 'demandeLe': null, 'demandePar': null, 'demandeParId': null, 'reprisLe': _iso(maintenant), 'reprisPar': acteur});
}

/// Le verdict de la clôture définitive : les lignes à INSÉRER (pièce CL puis pièce AN, dans l'ordre), le patch de l'exercice, la fiche du registre des
/// clôtures, l'exercice N+1 s'il manque. Tout est CALCULÉ avant que le poste n'écrive quoi que ce soit : un refus ne laisse rien derrière lui.
class CpcValidation {
  const CpcValidation.refus(this.motif)
      : ok = false,
        lignesCL = const [],
        lignesAN = const [],
        patch = null,
        exerciceSuivant = null,
        cloture = null,
        resultat = 0,
        empreinte = null,
        nbArchivees = 0,
        clNumero = null,
        anNumero = null;
  const CpcValidation.ok(this.lignesCL, this.lignesAN, this.patch, this.exerciceSuivant, this.cloture, this.resultat, this.empreinte, this.nbArchivees,
      this.clNumero, this.anNumero)
      : ok = true,
        motif = null;
  final bool ok;
  final String? motif;
  final List<CpaFiche> lignesCL, lignesAN;
  final CpaFiche? patch, cloture;

  /// La fiche de N+1 à insérer si elle n'existe pas encore.
  final CpaFiche? exerciceSuivant;
  final double resultat;
  final String? empreinte, clNumero, anNumero;
  final int nbArchivees;
}

/// TRANSITION 3 : clôturer définitivement (en clôture vers clôturé). Par la Direction, la DAF ou l'administrateur, une AUTRE personne que celle qui a démarré,
/// avec un motif. Dans l'ordre : (1) PIÈCE CL au 31/12/N, journal CL, classes 6, 7 et 8 soldées centre de coûts par centre de coûts, contrepartie en 131
/// ou 139 (table `comptesResultat`) ; (2) PIÈCE AN au 01/01/N+1 (classes 1 à 5, résultat compris, calculées APRÈS la pièce CL) ; (3) empreinte du journal arrêté,
/// puis le verrou. Refus nommés : état, rôle, motif, signataire identique, contrôles bloquants, pièces déséquilibrées (RG-10).
CpcValidation cpcValiderCloture(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee,
    {required String motif,
    required String acteur,
    String? acteurId,
    required String role,
    required DateTime maintenant,
    Iterable<CpaFiche> toutesEcritures = const [],
    Iterable<CpaFiche> comptesResultat = const [],
    int enAttente = 0}) {
  final x = cpcExercice(exercices, annee);
  if (x == null || cpcEtatExercice(exercices, annee) != 'en_cloture') {
    return CpcValidation.refus('L’exercice $annee n’est pas en clôture : démarrer la clôture d’abord.');
  }
  if (!cpcRolesValidation.contains(role)) {
    return const CpcValidation.refus('La clôture définitive est prononcée par la Direction ou la Directrice Administrative.');
  }
  if (motif.trim().length < 3) return const CpcValidation.refus('Un motif est obligatoire pour clôturer un exercice.');
  // A1 : l'identifiant décide quand les DEUX côtés en portent un ; une demande antérieure (sans identifiant) retombe sur le nom.
  final demandeurId = x['demandeParId'];
  final memePersonne = (demandeurId != null && acteurId != null) ? demandeurId == acteurId : x['demandePar'] == acteur;
  if (memePersonne) {
    return CpcValidation.refus(
        'Signer n’est pas saisir : la clôture définitive doit venir d’une autre personne que celle qui a démarré la clôture (${x['demandePar']}).');
  }
  final pre = cpcPreCloture(actives, annee, exercices: exercices, enAttente: enAttente);
  if (pre.bloquants.isNotEmpty) {
    return CpcValidation.refus(
        'Contrôles bloquants en échec : ${pre.bloquants.map((b) => b.libelle + (b.detail.isNotEmpty ? ' (${b.detail})' : '')).join(' ; ')}');
  }
  final base = cpcEcrituresDe(actives, annee);
  final res = cpcResultatDe(base);
  final journal = toutesEcritures.isEmpty ? actives : toutesEcritures;

  // (1) la pièce de clôture, centre de coûts par centre de coûts
  final numCL = 'CL-$annee-${_pad5(cpcRangPiece(journal, 'CL', annee))}';
  final clBase = <String, Object?>{
    'numero': numCL,
    'date': '$annee-12-31',
    'journal': 'CL',
    'journalLibelle': 'Journal de clôture',
    'libelle': 'Clôture de l’exercice $annee : détermination du résultat',
    'origine': 'Clôture : résultat',
    'statut': 'validee',
    'origineCloture': 'cl',
  };
  final parCentre = <String, List<CpaFiche>>{};
  for (final e in base) {
    final cl = '${e['compte']}'.isEmpty ? '' : '${e['compte']}'[0];
    if ('678'.contains(cl) && cl.isNotEmpty) parCentre.putIfAbsent('${e['centreCout'] ?? ''}', () => []).add(e);
  }
  final lignesCL = <CpaFiche>[];
  for (final centre in (parCentre.keys.toList()..sort())) {
    var resCentre = 0.0;
    for (final s in cpcSoldesParCompte(parCentre[centre]!)) {
      final solde = s['solde'] as double;
      if (solde.abs() < 1) continue;
      resCentre += -solde;
      lignesCL.add({
        ...clBase,
        'compte': s['compte'],
        'compteLibelle': s['libelle'],
        'centreCout': centre.isEmpty ? null : centre,
        'debit': solde < 0 ? -solde : 0.0,
        'credit': solde > 0 ? solde : 0.0,
      });
    }
    if (resCentre.abs() >= 1) {
      final cr = cpcCompteResultatDe(resCentre, comptesResultat);
      lignesCL.add({
        ...clBase,
        'compte': cr.compte,
        'compteLibelle': cr.libelle,
        'centreCout': centre.isEmpty ? null : centre,
        'debit': resCentre < 0 ? -resCentre : 0.0,
        'credit': resCentre > 0 ? resCentre : 0.0,
      });
    }
  }
  final dCL = _som(lignesCL, 'debit'), cCL = _som(lignesCL, 'credit');
  if ((dCL - cCL).abs() >= 1) {
    return CpcValidation.refus('Pièce de clôture déséquilibrée (${money((dCL - cCL).abs())}) : clôture refusée (RG-10). L’exercice reste en clôture, rien n’a été écrit.');
  }

  // (2) les à-nouveaux définitifs, sur le journal APRÈS la pièce CL
  final report = cpcLignesDeReport([...base, ...lignesCL]);
  final anNumero = 'AN-${annee + 1}-${_pad5(cpcRangPiece(journal, 'AN', annee + 1))}';
  final anBase = <String, Object?>{
    'numero': anNumero,
    'date': '${annee + 1}-01-01',
    'journal': 'AN',
    'journalLibelle': 'Journal des à-nouveaux',
    'libelle': 'À-nouveaux au 1er janvier ${annee + 1}',
    'origine': 'Clôture : à-nouveaux',
    'statut': 'validee',
    'origineCloture': 'an',
    'centreCout': null,
  };
  final dAN = report.fold<double>(0, (a, l) => a + _n(l['debit']));
  final cAN = report.fold<double>(0, (a, l) => a + _n(l['credit']));
  if ((dAN - cAN).abs() >= 1) {
    return CpcValidation.refus(
        'À-nouveaux déséquilibrés (${money((dAN - cAN).abs())}) : vérifier les lettrages. L’exercice reste en clôture, rien n’a été écrit.');
  }
  final lignesAN = [
    for (final l in report)
      {
        ...anBase,
        'compte': l['compte'],
        'compteLibelle': l['compteLibelle'],
        'debit': l['debit'],
        'credit': l['credit'],
        'libelle': l['libelle'] ?? anBase['libelle'],
        'pieceOrigine': l['pieceOrigine'],
      }
  ];

  // (3) l'empreinte du journal ARRÊTÉ (l'exercice N, pièce CL comprise), puis le verrou
  final arret = cpcEcrituresDe([...actives, ...lignesCL], annee, avecCL: true);
  final empreinte = cpcSha256(([
    for (final e in arret)
      [e['numero'], e['date'], e['journal'], e['compte'], _js(e['debit']), _js(e['credit'])].join('|')
  ]..sort())
      .join('\n'));
  final patch = <String, Object?>{
    'etat': 'clos',
    'valideLe': _iso(maintenant),
    'validePar': acteur,
    if (acteurId != null) 'valideParId': acteurId,
    'motif': motif.trim(),
    'resultat': res,
    'empreinte': empreinte,
    'nbEcrituresArchivees': arret.length,
    'clNumero': numCL,
    'anNumero': anNumero,
  };
  final suivant = cpcExercice(exercices, annee + 1) != null
      ? null
      : <String, Object?>{
          'id': 'EXO-${annee + 1}',
          'annee': annee + 1,
          'debut': '${annee + 1}-01-01',
          'fin': '${annee + 1}-12-31',
          'statut': 'actif',
          'etat': 'ouvert',
          'source': 'journal',
        };
  final cloture = <String, Object?>{
    'annee': annee,
    'type': 'cloture',
    'clNumero': numCL,
    'anNumero': anNumero,
    'resultat': res,
    'par': acteur,
    'le': _iso(maintenant),
    'motif': motif.trim(),
    'empreinte': empreinte,
  };
  return CpcValidation.ok(lignesCL, lignesAN, patch, suivant, cloture, res, empreinte, arret.length, numCL, anNumero);
}

/// Le verdict de la réouverture : les pièces de CONTRE-PASSATION à insérer, le patch de l'exercice, la fiche du registre des clôtures.
class CpcReouverture {
  const CpcReouverture.refus(this.motif)
      : ok = false,
        lignes = const [],
        patch = null,
        cloture = null,
        pieces = const [];
  const CpcReouverture.ok(this.lignes, this.patch, this.cloture, this.pieces)
      : ok = true,
        motif = null;
  final bool ok;
  final String? motif;
  final List<CpaFiche> lignes;
  final CpaFiche? patch, cloture;
  final List<String> pieces;
}

/// TRANSITION 4 : rouvrir (clôturé vers en clôture). Le COMPTABLE seul, motif d'au moins DIX caractères. Rien ne s'efface : la pièce CL et la pièce AN sont
/// CONTRE-PASSÉES (mêmes lignes, sens inversé, `contrePasseDe`). Refusée pour l'exercice de la liasse déposée, et si N+1 n'est plus ouvert.
CpcReouverture cpcRouvrirExercice(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee,
    {required String motif,
    required String acteur,
    String? acteurId,
    required String role,
    required DateTime maintenant,
    Iterable<CpaFiche> toutesEcritures = const []}) {
  final x = cpcExercice(exercices, annee);
  if (x == null || cpcEtatExercice(exercices, annee) != 'clos') return CpcReouverture.refus('L’exercice $annee n’est pas clôturé : rien à rouvrir.');
  if (x['source'] == 'liasse') {
    return CpcReouverture.refus('L’exercice $annee est celui de la liasse déposée à la DGI : il ne se rouvre pas dans le logiciel.');
  }
  if (role != 'comptable' && role != 'admin') return const CpcReouverture.refus('La réouverture est réservée au comptable.');
  if (motif.trim().length < 10) return const CpcReouverture.refus('Le motif de réouverture doit compter au moins dix caractères.');
  final suivEtat = cpcExercice(exercices, annee + 1) == null ? 'ouvert' : cpcEtatExercice(exercices, annee + 1);
  if (suivEtat != 'ouvert') {
    return CpcReouverture.refus(
        'L’exercice ${annee + 1} est ${suivEtat == 'clos' ? 'clôturé' : 'en clôture'} : il a consommé les à-nouveaux de $annee. Le rouvrir ou le reprendre d’abord.');
  }
  final origines = [
    for (final e in actives)
      if ((e['numero'] == x['clNumero'] || e['numero'] == x['anNumero']) && e['contrePasseDe'] == null) e
  ];
  if (origines.isEmpty) return CpcReouverture.refus('Les pièces de clôture de $annee sont introuvables : réouverture refusée.');
  final journal = toutesEcritures.isEmpty ? actives : toutesEcritures;
  final nCL = 'CL-$annee-C${_pad5(cpcRangPiece(journal, 'CL', annee))}';
  final nAN = 'AN-${annee + 1}-C${_pad5(cpcRangPiece(journal, 'AN', annee + 1))}';
  final lignes = <CpaFiche>[];
  for (final o in origines) {
    final estCL = o['numero'] == x['clNumero'];
    lignes.add({
      'numero': estCL ? nCL : nAN,
      'date': o['date'],
      'journal': o['journal'],
      'journalLibelle': o['journalLibelle'],
      'compte': o['compte'],
      'compteLibelle': o['compteLibelle'],
      'centreCout': o['centreCout'],
      'debit': _n(o['credit']),
      'credit': _n(o['debit']),
      'statut': 'validee',
      'libelle': 'Contre-passation de ${o['numero']} : réouverture de $annee',
      'origine': 'Clôture : contre-passation',
      'origineCloture': estCL ? 'cl-contre' : 'an-contre',
      'contrePasseDe': o['numero'],
      'pieceOrigine': o['pieceOrigine'],
    });
  }
  return CpcReouverture.ok(lignes, {
    'etat': 'en_cloture',
    'rouvertLe': _iso(maintenant),
    'rouvertPar': acteur,
    if (acteurId != null) 'rouvertParId': acteurId,
    'motifReouverture': motif.trim(),
    'valideLe': null,
    'validePar': null,
    'resultat': null,
  }, {
    'annee': annee,
    'type': 'reouverture',
    'clNumero': nCL,
    'anNumero': nAN,
    'contrePasse': [x['clNumero'], x['anNumero']],
    'par': acteur,
    'le': _iso(maintenant),
    'motif': motif.trim(),
  }, [nCL, nAN]);
}

/// Le choix d'exercice par DÉFAUT : l'exercice OUVERT le plus récent, sinon le plus récent tout court.
int cpcExerciceParDefaut(Iterable<CpaFiche> exercices, DateTime auj) {
  final liste = cpcListeExercices(exercices);
  for (final x in liste) {
    if (cpcEtatExercice(exercices, x['annee'] as int) == 'ouvert') return x['annee'] as int;
  }
  return liste.isNotEmpty ? liste.first['annee'] as int : auj.year;
}

/// Le choix mémorisé s'il désigne un exercice qui existe, sinon le défaut.
int cpcExerciceChoisi(Iterable<CpaFiche> exercices, int? memorise, DateTime auj) =>
    memorise != null && cpcExercice(exercices, memorise) != null ? memorise : cpcExerciceParDefaut(exercices, auj);

/// La date de référence des périodes relatives (« ce mois », « ce trimestre ») : aujourd'hui si l'exercice consulté le contient, sinon son dernier jour.
DateTime cpcDateReference(int exerciceChoisi, DateTime auj) => auj.year == exerciceChoisi ? auj : DateTime(exerciceChoisi, 12, 31);

/// L'exercice voisin (sens -1 ou +1), ou `null` aux bornes : le bouton est ABSENT, pas grisé.
int? cpcExerciceVoisin(Iterable<CpaFiche> exercices, int choisi, int sens) => cpcExercice(exercices, choisi + sens) != null ? choisi + sens : null;

String _js(Object? v) {
  if (v == null) return '';
  if (v is int) return '$v';
  if (v is double) return v == v.truncateToDouble() && v.abs() < 1e15 ? '${v.toInt()}' : '$v';
  return '$v';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LETTRAGE — un ensemble de lignes d'UN compte de tiers dont le total s'annule
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpcLettrage {
  const CpcLettrage.refus(this.motif)
      : ok = false,
        code = null,
        ids = const [];
  const CpcLettrage.ok(this.code, this.ids)
      : ok = true,
        motif = null;
  final bool ok;
  final String? motif;
  final String? code;
  final List<Object?> ids;
}

/// `lettrer(compte, ids)` : deux lignes au moins, du même compte, non encore lettrées, dont le total s'annule. [toutes] : toutes les écritures
/// (le code suivant compte les codes DISTINCTS déjà posés).
CpcLettrage cpcLettrer(Iterable<CpaFiche> toutes, String compte, List<Object?> ids) {
  if (!cpcLettrable(compte)) return CpcLettrage.refus('Le compte $compte n’est pas lettrable (comptes de tiers seulement).');
  final lignes = [for (final id in ids) toutes.where((e) => e['id'] == id).firstOrNull];
  if (lignes.length < 2 || lignes.any((l) => l == null || '${l['compte']}' != compte || _lettre(l) != null)) {
    return const CpcLettrage.refus('Sélection invalide : au moins deux lignes, du même compte, non encore lettrées.');
  }
  final net = _som(lignes.cast<CpaFiche>(), 'debit') - _som(lignes.cast<CpaFiche>(), 'credit');
  if (net.abs() >= 1) return CpcLettrage.refus('Lettrage refusé — l’ensemble ne s’annule pas (écart ${money(net.abs())}).');
  final distincts = {for (final e in toutes) if (_lettre(e) != null) _lettre(e)!};
  return CpcLettrage.ok(String.fromCharCode(65 + distincts.length % 26), [for (final l in lignes) l!['id']]);
}

/// `delettrer(compte, code, motif)` : le motif est OBLIGATOIRE ; rend les identifiants des lignes à dé-lettrer.
CpcLettrage cpcDelettrer(Iterable<CpaFiche> toutes, String compte, String code, String motif) {
  if (motif.trim().length < 3) return const CpcLettrage.refus('Un motif est obligatoire pour dé-lettrer.');
  final ids = [for (final e in toutes) if ('${e['compte']}' == compte && e['lettrage'] == code) e['id']];
  return ids.isEmpty
      ? CpcLettrage.refus('Aucune ligne lettrée « $code » sur ce compte.')
      : CpcLettrage.ok(code, ids);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// BILAN D'OUVERTURE — les à-nouveaux de l'écran « Bilan d'ouverture & à-nouveaux » (classes 1 à 5 seulement)
// ---------------------------------------------------------------------------------------------------------------------------------------------------

class CpcSoldesCloture {
  const CpcSoldesCloture(this.comptes, this.resultat);
  final List<CpaFiche> comptes; // {compte, libelle, solde}
  final double resultat;
  double get totalDebiteurs => comptes.fold(0.0, (a, c) => (c['solde'] as double) > 0 ? a + (c['solde'] as double) : a);
  double get totalCrediteurs => comptes.fold(0.0, (a, c) => (c['solde'] as double) < 0 ? a - (c['solde'] as double) : a);

  /// Le résultat vient ÉQUILIBRER : bénéfice au crédit, perte au débit.
  double get ecart => totalDebiteurs - (totalCrediteurs + resultat);
  bool get equilibre => ecart.abs() < 1;
}

/// `soldesDeCloture(annee)` : les soldes de bilan (classes 1 à 5) cumulés jusqu'à la fin de l'exercice, VALIDÉS seulement, et le résultat de CET exercice
/// (classe 7 − classe 6 ; la classe 8 n'y entre pas, contrairement à `resultatDe`) qui entre au passif : c'est lui qui équilibre le report.
CpcSoldesCloture cpcSoldesDeCloture(Iterable<CpaFiche> actives, int annee) {
  final parCompte = <String, List<double>>{};
  for (final x in actives) {
    if (x['statut'] != 'validee') continue;
    final a = cpaAnnee(x['date']);
    if (a == null || a > annee) continue;
    final num = '${x['compte'] ?? ''}';
    if (num.isEmpty || !'12345'.contains(num[0])) continue;
    final p = parCompte.putIfAbsent(num, () => [0, 0]);
    p[0] += _n(x['debit']);
    p[1] += _n(x['credit']);
  }
  var resultat = 0.0;
  for (final x in actives) {
    if (x['statut'] != 'validee' || cpaAnnee(x['date']) != annee) continue;
    final cl = '${x['compte'] ?? ''}'.isEmpty ? '' : '${x['compte']}'[0];
    if (cl == '7') resultat += _n(x['credit']) - _n(x['debit']);
    if (cl == '6') resultat -= _n(x['debit']) - _n(x['credit']);
  }
  final out = [
    for (final k in parCompte.keys)
      if (parCompte[k]![0] - parCompte[k]![1] != 0)
        {'compte': k, 'libelle': cpaCompteLibelle(k), 'solde': parCompte[k]![0] - parCompte[k]![1]}
  ]..sort((a, b) => '${a['compte']}'.compareTo('${b['compte']}'));
  return CpcSoldesCloture(out, resultat);
}

/// UN SEUL compte de résultat (E813 levé) : le report manuel écrit, comme la clôture en deux gestes, au 131000 (bénéfice) ou au 139000 (perte). Le 130000
/// ne subsiste que dans les reports manuels antérieurs, signalés à l'écran.
String cpcCompteResultat(num resultat) => resultat >= 0 ? '131000' : '139000';

/// Les lignes du bilan d'ouverture : les comptes reportés, puis le résultat au compte de résultat (bénéfice au crédit).
List<CpaFiche> cpcLignesOuverture(CpcSoldesCloture s, int annee) => [
      ...s.comptes,
      {'compte': cpcCompteResultat(s.resultat), 'libelle': 'Résultat net de l’exercice $annee', 'solde': -s.resultat},
    ];

class CpcReport {
  const CpcReport.refus(String this.message, String this.detail)
      : ok = false,
        lignes = const [],
        numero = null;
  const CpcReport.ok(this.numero, this.lignes)
      : ok = true,
        message = null,
        detail = null;
  final bool ok;

  /// Un refus se dit en deux temps, comme le toast de l'écran : ce qui est refusé, puis pourquoi.
  final String? message, detail;
  String? get motif => message == null ? null : '$message $detail';
  final String? numero;
  final List<CpaFiche> lignes; // dans l'ordre des insertions
}

/// Le report des à-nouveaux (geste de `m12-ouverture`) : REFUSÉ s'il ne s'équilibre pas (RG-10), REFUSÉ une seconde fois (double à-nouveau) ; la pièce
/// naît en BROUILLON, au journal AN. [dejaEcrits] : les lignes du journal AN déjà portées sur N+1.
CpcReport cpcReporterANouveaux(CpcSoldesCloture s, int annee, {required int dejaEcrits}) {
  if (!s.equilibre) {
    return CpcReport.refus('Report refusé — écart de ${money(s.ecart)} (RG-10).',
        'Un à-nouveau boiteux propagerait le déséquilibre à toutes les années suivantes.');
  }
  if (dejaEcrits > 0) {
    return CpcReport.refus('Les à-nouveaux du 1ᵉʳ janvier ${annee + 1} existent déjà.', 'Les réécrire créerait un double report.');
  }
  final numero = 'AN-${annee + 1}-00001';
  final base = <String, Object?>{
    'numero': numero,
    'date': '${annee + 1}-01-01',
    'journal': 'AN',
    'journalLibelle': 'Journal des à-nouveaux',
    'libelle': 'À-nouveaux au 1er janvier ${annee + 1}',
    'origine': 'Automatique — report d’exercice',
    'statut': 'brouillon',
    'centreCout': null,
  };
  final lignes = [
    for (final c in s.comptes)
      {
        ...base,
        'compte': c['compte'],
        'compteLibelle': c['libelle'],
        'debit': (c['solde'] as double) > 0 ? c['solde'] : 0.0,
        'credit': (c['solde'] as double) < 0 ? -(c['solde'] as double) : 0.0,
      },
    {
      ...base,
      'compte': cpcCompteResultat(s.resultat),
      'compteLibelle': s.resultat >= 0 ? 'Résultat net : bénéfice' : 'Résultat net : perte',
      'debit': s.resultat < 0 ? -s.resultat : 0.0,
      'credit': s.resultat > 0 ? s.resultat : 0.0,
    },
  ];
  return CpcReport.ok(numero, lignes);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// SHA-256 (FIPS 180-4) — l'empreinte du journal arrêté, sans dépendance
// ---------------------------------------------------------------------------------------------------------------------------------------------------
const List<int> _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

/// SHA-256 hexadécimal du texte encodé en UTF-8 (`SIGH.exercice.sha256`).
String cpcSha256(String texte) {
  const m = 0xffffffff;
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & m;
  final octets = utf8.encode(texte);
  final l = octets.length;
  final total = (((l + 8) >> 6) + 1) * 16;
  final w = List<int>.filled(total, 0);
  for (var i = 0; i < l; i++) {
    w[i >> 2] |= octets[i] << (24 - (i % 4) * 8);
  }
  w[l >> 2] |= 0x80 << (24 - (l % 4) * 8);
  w[total - 1] = l * 8;
  var h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  for (var i = 0; i < total; i += 16) {
    final s = List<int>.filled(64, 0);
    for (var j = 0; j < 16; j++) {
      s[j] = w[i + j] & m;
    }
    for (var j = 16; j < 64; j++) {
      final s0 = rotr(s[j - 15], 7) ^ rotr(s[j - 15], 18) ^ (s[j - 15] >> 3);
      final s1 = rotr(s[j - 2], 17) ^ rotr(s[j - 2], 19) ^ (s[j - 2] >> 10);
      s[j] = (s[j - 16] + s0 + s[j - 7] + s1) & m;
    }
    var a = List<int>.from(h);
    for (var j = 0; j < 64; j++) {
      final s1 = rotr(a[4], 6) ^ rotr(a[4], 11) ^ rotr(a[4], 25);
      final ch = (a[4] & a[5]) ^ ((~a[4] & m) & a[6]);
      final t1 = (a[7] + s1 + ch + _k[j] + s[j]) & m;
      final s0 = rotr(a[0], 2) ^ rotr(a[0], 13) ^ rotr(a[0], 22);
      final mj = (a[0] & a[1]) ^ (a[0] & a[2]) ^ (a[1] & a[2]);
      final t2 = (s0 + mj) & m;
      a = [(t1 + t2) & m, a[0], a[1], a[2], (a[3] + t1) & m, a[4], a[5], a[6]];
    }
    for (var j = 0; j < 8; j++) {
      h[j] = (h[j] + a[j]) & m;
    }
  }
  return h.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
}
