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

/// `etatExercice(annee)` : `clos` · `en_attente_cloture` · `ouvert`. Sans fiche amorcée, c'est ce que l'amorçage donnerait : clos pour la liasse déposée.
/// Une fiche ARCHIVÉE ne ferme rien (RG-14) : l'exercice se lit ouvert.
String cpcEtatExercice(Iterable<CpaFiche> exercices, int annee) {
  final x = cpcExercice(exercices, annee);
  if (x != null) return '${x['etat'] ?? 'ouvert'}';
  final archivee = exercices.any((f) => f['annee'] == annee && f['statut'] == 'archive');
  if (archivee) return 'ouvert';
  return _estDeLiasse(annee) ? 'clos' : 'ouvert';
}

/// La GARDE posée sur la collection `ecritures` : le motif du refus (nommé) ou `null`. Toute écriture dont la date tombe dans un exercice clos est refusée.
String? cpcGardeEcritures(Iterable<CpaFiche> exercices, Object? date) {
  final a = cpaAnnee(date);
  if (a == null || cpcEtatExercice(exercices, a) != 'clos') return null;
  final x = cpcExercice(exercices, a);
  final valideLe = x?['valideLe'] ?? (_estDeLiasse(a) ? cpcDepot['dateDepot'] : null);
  final d = valideLe == null ? null : DateTime.tryParse('$valideLe')?.toLocal();
  return 'Exercice $a clos${d != null ? ' le ${dateFR(d)}' : ''} — lecture seule. La correction passe par une écriture de l’exercice en cours.';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LECTURES D'UN EXERCICE
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// `ecrituresDe(annee, inclureBrouillons)` : les écritures ACTIVES de l'année — VALIDÉES seulement par défaut (un brouillon n'est pas un fait comptable).
List<CpaFiche> cpcEcrituresDe(Iterable<CpaFiche> actives, int annee, {bool brouillons = false}) => [
      for (final e in actives)
        if (cpaAnnee(e['date']) == annee && (brouillons || e['statut'] == 'validee')) e
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
List<CpaFiche> cpcANouveauxProvisoires(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee) {
  final prec = annee - 1;
  final ex = cpcExercice(exercices, prec);
  if (ex == null || ex['etat'] == 'clos' || ex['source'] == 'liasse') return [];
  final base = cpcEcrituresDe(actives, prec);
  final lignes = cpcLignesDeReport(base);
  final res = cpcResultatDe(base);
  if (res.abs() >= 1) {
    lignes.add({
      'compte': res >= 0 ? '131000' : '139000',
      'compteLibelle': res >= 0 ? 'Résultat net : bénéfice' : 'Résultat net : perte',
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

/// `preCloture(annee)` : six contrôles. Brouillons, à-nouveaux déjà écrits, équilibre, pièces et absence d'écritures BLOQUENT ; le compte 47 INFORME.
CpcPreCloture cpcPreCloture(Iterable<CpaFiche> actives, int annee) {
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
  final an = [for (final e in actives) if (cpaAnnee(e['date']) == annee + 1 && e['journal'] == 'AN') e];
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
// LES DEUX GESTES
// ---------------------------------------------------------------------------------------------------------------------------------------------------

String _iso(DateTime d) => d.toUtc().toIso8601String();

/// Le verdict du geste 1 : refusé EN NOMMANT, ou accepté avec le PATCH à porter sur la fiche d'exercice.
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

/// GESTE 1 — la demande (comptable). Les contrôles bloquants refusent EN LES NOMMANT.
CpcDemande cpcDemanderCloture(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee,
    {required String acteur, required DateTime maintenant}) {
  final x = cpcExercice(exercices, annee);
  if (x == null) return CpcDemande.refus('Exercice $annee inconnu.');
  if (x['etat'] == 'clos') return CpcDemande.refus('Exercice $annee déjà clos.');
  if (x['etat'] == 'en_attente_cloture') {
    return CpcDemande.refus('La clôture de $annee attend déjà la validation de la Direction.');
  }
  final pre = cpcPreCloture(actives, annee);
  if (pre.bloquants.isNotEmpty) {
    return CpcDemande.refus(
        'Pré-clôture refusée — ${pre.bloquants.map((b) => b.libelle + (b.detail.isNotEmpty ? ' (${b.detail})' : '')).join(' ; ')}', pre);
  }
  return CpcDemande.ok(pre, {
    'etat': 'en_attente_cloture',
    'demandeLe': _iso(maintenant),
    'demandePar': acteur,
    'resultatPrevu': pre.resultat,
  });
}

/// Le verdict du geste 2 : les lignes à INSÉRER (dans l'ordre des appels `insert` de la maquette), le patch de l'exercice, et ce qu'il faut créer après.
class CpcValidation {
  const CpcValidation.refus(this.motif)
      : ok = false,
        lignesOD = const [],
        lignesAN = const [],
        patch = null,
        exerciceSuivant = null,
        resultat = 0,
        empreinte = null,
        nbArchivees = 0;
  const CpcValidation.ok(this.lignesOD, this.lignesAN, this.patch, this.exerciceSuivant, this.resultat, this.empreinte, this.nbArchivees)
      : ok = true,
        motif = null;
  final bool ok;
  final String? motif;
  final List<CpaFiche> lignesOD, lignesAN;
  final CpaFiche? patch;

  /// La fiche de N+1 à insérer si elle n'existe pas encore.
  final CpaFiche? exerciceSuivant;
  final double resultat;
  final String? empreinte;
  final int nbArchivees;
}

/// GESTE 2 — la validation (Direction / DAF), par une personne DIFFÉRENTE de celle qui a demandé : (1) détermination du résultat — chaque compte 6/7/8
/// est soldé vers 131 / 139, UNE pièce équilibrée ; (2) à-nouveaux DÉFINITIFS au 1er janvier N+1, calculés APRÈS la pièce de résultat ; (3) empreinte du
/// journal ARRÊTÉ, puis état « clos » — en dernier. Refus nommés : demande absente, rôle, motif, signataire identique, contrôles à nouveau en échec,
/// pièces déséquilibrées (RG-10).
CpcValidation cpcValiderCloture(Iterable<CpaFiche> exercices, Iterable<CpaFiche> actives, int annee,
    {required String motif, required String acteur, required String role, required DateTime maintenant}) {
  final x = cpcExercice(exercices, annee);
  if (x == null || x['etat'] != 'en_attente_cloture') {
    return CpcValidation.refus('Aucune demande de clôture en attente pour $annee.');
  }
  if (!cpcRolesValidation.contains(role)) {
    return const CpcValidation.refus('La clôture est validée par la Direction ou la Directrice Administrative.');
  }
  if (motif.trim().length < 3) return const CpcValidation.refus('Un motif est obligatoire pour valider une clôture.');
  if (x['demandePar'] == acteur) {
    return CpcValidation.refus(
        'Signer n’est pas saisir : la validation doit venir d’une autre personne que le demandeur (${x['demandePar']}).');
  }
  final pre = cpcPreCloture(actives, annee);
  if (pre.bloquants.isNotEmpty) {
    return CpcValidation.refus('Contrôles bloquants à nouveau en échec : ${pre.bloquants.map((b) => b.libelle).join(' ; ')}');
  }
  final base = cpcEcrituresDe(actives, annee);
  final res = cpcResultatDe(base);

  // (1) la pièce de résultat
  final numOD = 'OD-$annee-RES';
  final odBase = <String, Object?>{
    'numero': numOD,
    'date': '$annee-12-31',
    'journal': 'OD',
    'journalLibelle': 'Journal des opérations diverses',
    'libelle': 'Détermination du résultat $annee',
    'origine': 'Clôture — résultat',
    'statut': 'validee',
    'origineCloture': 'resultat',
    'centreCout': null,
  };
  final lignesOD = <CpaFiche>[];
  for (final s in cpcSoldesParCompte([for (final e in base) if ('678'.contains('${e['compte']}'.isEmpty ? '' : '${e['compte']}'[0])) e])) {
    final solde = s['solde'] as double;
    if (solde.abs() < 1) continue;
    lignesOD.add({
      ...odBase,
      'compte': s['compte'],
      'compteLibelle': s['libelle'],
      'debit': solde < 0 ? -solde : 0.0,
      'credit': solde > 0 ? solde : 0.0,
    });
  }
  if (res.abs() >= 1) {
    lignesOD.add({
      ...odBase,
      'compte': res >= 0 ? '131000' : '139000',
      'compteLibelle': res >= 0 ? 'Résultat net : bénéfice' : 'Résultat net : perte',
      'debit': res < 0 ? -res : 0.0,
      'credit': res > 0 ? res : 0.0,
    });
  }
  final dOD = _som(lignesOD, 'debit'), cOD = _som(lignesOD, 'credit');
  if ((dOD - cOD).abs() >= 1) {
    return CpcValidation.refus('Pièce de résultat déséquilibrée (${money((dOD - cOD).abs())}) — clôture refusée (RG-10).');
  }

  // (2) les à-nouveaux définitifs, sur le journal APRÈS la pièce de résultat
  final apres = [...base, ...lignesOD];
  final report = cpcLignesDeReport(apres);
  final anNumero = 'AN-${annee + 1}-00001';
  final anBase = <String, Object?>{
    'numero': anNumero,
    'date': '${annee + 1}-01-01',
    'journal': 'AN',
    'journalLibelle': 'Journal des à-nouveaux',
    'libelle': 'À-nouveaux au 1er janvier ${annee + 1}',
    'origine': 'Clôture — à-nouveaux',
    'statut': 'validee',
    'origineCloture': 'an',
    'centreCout': null,
  };
  final dAN = report.fold<double>(0, (a, l) => a + _n(l['debit']));
  final cAN = report.fold<double>(0, (a, l) => a + _n(l['credit']));
  if ((dAN - cAN).abs() >= 1) {
    return CpcValidation.refus(
        'À-nouveaux déséquilibrés (${money((dAN - cAN).abs())}) : vérifier les lettrages. L’exercice reste ouvert.');
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

  // (3) l'empreinte du journal ARRÊTÉ (l'exercice N, pièce de résultat comprise), puis « clos »
  final empreinte = cpcSha256(([
    for (final e in apres)
      [e['numero'], e['date'], e['journal'], e['compte'], _js(e['debit']), _js(e['credit'])].join('|')
  ]..sort())
      .join('\n'));
  final patch = <String, Object?>{
    'etat': 'clos',
    'valideLe': _iso(maintenant),
    'validePar': acteur,
    'motif': motif.trim(),
    'resultat': res,
    'empreinte': empreinte,
    'nbEcrituresArchivees': apres.length,
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
  return CpcValidation.ok(lignesOD, lignesAN, patch, suivant, res, empreinte, apres.length);
}

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

/// Les lignes du bilan d'ouverture : les comptes reportés, puis le résultat au compte 13 (bénéfice au crédit).
List<CpaFiche> cpcLignesOuverture(CpcSoldesCloture s, int annee, {String compteResultat = '13'}) => [
      ...s.comptes,
      {'compte': compteResultat, 'libelle': 'Résultat net de l’exercice $annee', 'solde': -s.resultat},
    ];

class CpcReport {
  const CpcReport.refus(this.motif)
      : ok = false,
        lignes = const [],
        numero = null;
  const CpcReport.ok(this.numero, this.lignes)
      : ok = true,
        motif = null;
  final bool ok;
  final String? motif;
  final String? numero;
  final List<CpaFiche> lignes; // dans l'ordre des insertions
}

/// Le report des à-nouveaux (geste de `m12-ouverture`) : REFUSÉ s'il ne s'équilibre pas (RG-10), REFUSÉ une seconde fois (double à-nouveau) ; la pièce
/// naît en BROUILLON, au journal AN. [dejaEcrits] : les lignes du journal AN déjà portées sur N+1.
CpcReport cpcReporterANouveaux(CpcSoldesCloture s, int annee, {required int dejaEcrits}) {
  if (!s.equilibre) {
    return CpcReport.refus(
        'Report refusé — écart de ${money(s.ecart)} (RG-10). Un à-nouveau boiteux propagerait le déséquilibre à toutes les années suivantes.');
  }
  if (dejaEcrits > 0) {
    return CpcReport.refus('Les à-nouveaux du 1ᵉʳ janvier ${annee + 1} existent déjà. Les réécrire créerait un double report.');
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
      'compte': '130000',
      'compteLibelle': 'Résultat net de l’exercice $annee',
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
