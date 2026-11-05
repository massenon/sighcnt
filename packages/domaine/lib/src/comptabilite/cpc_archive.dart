/// L'ARCHIVE LÉGALE D'UNE CLÔTURE (arbitrage du 05/11/2026), port de `deposerArchive` / `lireArchive` de la maquette (`parcours.js`).
///
/// Les écritures et la balance en CSV, les états de synthèse imprimables (HTML : « Enregistrer en PDF » se fait à l'impression), et un MANIFESTE portant
/// l'empreinte SHA-256 de chaque fichier. Immuable, jamais régénérée, vérifiée avant chaque téléchargement : un fichier altéré est un refus nommé.
///
/// LE FORMAT DU CSV DES ÉCRITURES est isolé ICI, en un seul point ([cpcFormatEcrituresCsv]) : colonnes du journal SYSCOHADA révisé, séparateur « ; », UTF-8
/// avec BOM, dates JJ/MM/AAAA, montants entiers en FCFA. Validé par la Direction le 05/11/2026.
library;

import 'cpa_ecritures.dart' show cpaAnnee;
import 'cpa_referentiels.dart';
import 'cpc_exercice.dart';

const List<String> cpcEnteteEcritures = [
  'Journal', 'Date', 'N° pièce', 'Compte', 'Intitulé du compte', 'Libellé de l’écriture', 'Centre de coûts', 'Débit', 'Crédit', 'Lettrage', 'Statut'
];

String _cellule(Object? v) {
  final t = v == null ? '' : '$v';
  return RegExp(r'[;"\n\r]').hasMatch(t) ? '"${t.replaceAll('"', '""')}"' : t;
}

String _jjmmaaaa(Object? d) {
  final x = DateTime.tryParse('$d');
  if (x == null) return '';
  return '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
}

int _entier(Object? v) => (v is num ? v : num.tryParse('${v ?? 0}') ?? 0).round();

/// CSV des écritures : BOM UTF-8, `;`, fins de ligne CRLF, tri par date, pièce, compte.
String cpcFormatEcrituresCsv(Iterable<CpaFiche> lignes) {
  final l = lignes.toList()
    ..sort((a, b) {
      final c = '${a['date']}'.compareTo('${b['date']}');
      if (c != 0) return c;
      final n = '${a['numero']}'.compareTo('${b['numero']}');
      return n != 0 ? n : '${a['compte']}'.compareTo('${b['compte']}');
    });
  final corps = [
    for (final e in l)
      [e['journal'], _jjmmaaaa(e['date']), e['numero'], e['compte'], e['compteLibelle'], e['libelle'], e['centreCout'], _entier(e['debit']), _entier(e['credit']), e['lettrage'], e['statut']]
          .map(_cellule)
          .join(';')
  ];
  return '﻿${[cpcEnteteEcritures.join(';'), ...corps].join('\r\n')}\r\n';
}

String cpcFormatBalanceCsv(Iterable<CpaFiche> soldes) =>
    '﻿${[
      'Compte;Intitulé;Débit;Crédit;Solde',
      for (final l in soldes) [l['compte'], l['libelle'], _entier(l['debit']), _entier(l['credit']), _entier(l['solde'])].map(_cellule).join(';')
    ].join('\r\n')}\r\n';

String _html(Object? v) => '${v ?? ''}'.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Les états de synthèse imprimables (HTML autonome).
String cpcEtatsHtml(int annee, CpaFiche exercice, Iterable<CpaFiche> soldes, Iterable<CpaFiche> lignes) {
  num somme(Iterable<CpaFiche> l, String k) => l.fold<num>(0, (a, x) => a + (x[k] as num));
  String bloc(String titre, List<CpaFiche> l) =>
      '<h2>${_html(titre)}</h2><table><tr><th>Compte</th><th>Intitulé</th><th>Débit</th><th>Crédit</th><th>Solde</th></tr>'
      '${l.map((x) => '<tr><td>${_html(x['compte'])}</td><td>${_html(x['libelle'])}</td><td>${_entier(x['debit'])}</td><td>${_entier(x['credit'])}</td><td>${_entier(x['solde'])}</td></tr>').join()}'
      '<tr><th colspan="2">Total</th><th>${_entier(somme(l, 'debit'))}</th><th>${_entier(somme(l, 'credit'))}</th><th>${_entier(somme(l, 'solde'))}</th></tr></table>';
  List<CpaFiche> classe(String c) => [for (final l in soldes) if ('${l['compte']}'.startsWith(c)) l];
  final res = exercice['resultat'] ?? cpcResultatDe(lignes);
  return '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>États de l’exercice $annee</title>'
      '<style>body{font-family:Arial,sans-serif;font-size:11pt}table{border-collapse:collapse;width:100%}td,th{border:1px solid #888;padding:3px 6px;text-align:right}'
      'td:nth-child(-n+2),th:nth-child(-n+2){text-align:left}h2{margin-top:18pt}</style></head><body>'
      '<h1>États de synthèse : exercice $annee</h1><p>Résultat net : <strong>${_entier(res)} FCFA</strong>. Journal arrêté, clôture ${_html(exercice['clNumero'])}. '
      'Les états de la liasse (bilan, compte de résultat, flux) se rééditent à l’identique depuis l’exercice figé ; « Enregistrer en PDF » se fait à l’impression.</p>'
      '${bloc('Classes 1 à 5 : bilan (soldes)', [for (final l in soldes) if ('12345'.contains('${l['compte']}'.isEmpty ? '-' : '${l['compte']}'[0])) l])}'
      '${bloc('Classes 6 et 7 : charges et produits', [...classe('6'), ...classe('7')])}'
      '${bloc('Classe 8 : hors activités ordinaires', classe('8'))}'
      '</body></html>';
}

/// Le contenu de l'archive d'une clôture : quatre fichiers (écritures, balance, états, manifeste), chacun avec sa taille et son empreinte SHA-256.
/// [actives] : les écritures actives APRÈS la pose des pièces de clôture.
List<CpaFiche> cpcFichiersArchive(int annee, CpaFiche exercice, Iterable<CpaFiche> actives) {
  final lignes = cpcEcrituresDe(actives, annee, brouillons: true, avecCL: true);
  final valides = cpcEcrituresDe(actives, annee);
  final soldes = cpcSoldesParCompte(valides);
  final bruts = <(String, String, String)>[
    ('ecritures-$annee.csv', 'text/csv;charset=utf-8', cpcFormatEcrituresCsv(lignes)),
    ('balance-$annee.csv', 'text/csv;charset=utf-8', cpcFormatBalanceCsv(soldes)),
    ('etats-$annee.html', 'text/html;charset=utf-8', cpcEtatsHtml(annee, exercice, soldes, valides)),
  ];
  final fichiers = <CpaFiche>[
    for (final b in bruts) {'nom': b.$1, 'type': b.$2, 'contenu': b.$3, 'taille': b.$3.length, 'empreinte': cpcSha256(b.$3)}
  ];
  final manifeste = '${fichiers.map((x) => '${x['empreinte']}  ${x['nom']}').join('\n')}\n';
  fichiers.add({'nom': 'manifeste-$annee.txt', 'type': 'text/plain;charset=utf-8', 'contenu': manifeste, 'taille': manifeste.length, 'empreinte': cpcSha256(manifeste)});
  return fichiers;
}

/// Le verdict d'un téléchargement.
class CpcLectureArchive {
  const CpcLectureArchive.ok(this.fichier)
      : ok = true,
        motif = null,
        altere = false;
  const CpcLectureArchive.refus(this.motif, {this.altere = false})
      : ok = false,
        fichier = null;
  final bool ok, altere;
  final String? motif;
  final CpaFiche? fichier;
}

/// TÉLÉCHARGEMENT : l'empreinte est RECALCULÉE et comparée à celle du manifeste avant de livrer. Un fichier altéré est refusé en le nommant.
CpcLectureArchive cpcLireArchive(Iterable<CpaFiche> archives, String reference, String nomFichier) {
  CpaFiche? a;
  for (final x in archives) {
    if (x['reference'] == reference) a = x;
  }
  if (a == null) return CpcLectureArchive.refus('Archive $reference introuvable.');
  final fichiers = [for (final f in (a['fichiers'] as List? ?? const [])) (f as Map).cast<String, Object?>()];
  CpaFiche? fich;
  for (final f in fichiers) {
    if (f['nom'] == nomFichier) fich = f;
  }
  if (fich == null) return CpcLectureArchive.refus('Le fichier « $nomFichier » ne figure pas dans l’archive $reference.');
  final recalc = cpcSha256('${fich['contenu']}');
  final attendue = '${fich['empreinte']}';
  if (recalc != attendue) {
    return CpcLectureArchive.refus(
        'Archive $reference, fichier $nomFichier : l’empreinte ne correspond plus (attendue ${attendue.substring(0, 12)}…, calculée ${recalc.substring(0, 12)}…). Le fichier a été altéré : téléchargement refusé.',
        altere: true);
  }
  CpaFiche? manifeste;
  for (final f in fichiers) {
    if ('${f['nom']}'.startsWith('manifeste-')) manifeste = f;
  }
  if (manifeste != null && nomFichier != manifeste['nom'] && !'${manifeste['contenu']}'.contains('$attendue  ${fich['nom']}')) {
    return CpcLectureArchive.refus('Archive $reference : le manifeste ne porte pas l’empreinte de $nomFichier. Téléchargement refusé.', altere: true);
  }
  return CpcLectureArchive.ok(fich);
}

/// La garde de la collection `archivesExercice` : immuable. Un dépôt n'est accepté qu'une fois par référence ; modifier ou archiver est refusé.
String? cpcGardeArchives(Iterable<CpaFiche> archives, String op, Object? reference) {
  if (op == 'inserer') {
    return archives.any((a) => a['reference'] == reference) ? 'L’archive $reference existe déjà : une archive de clôture n’est jamais régénérée.' : null;
  }
  return 'Une archive de clôture est immuable : elle ne se modifie ni ne s’archive. Une nouvelle clôture dépose une nouvelle archive.';
}

/// La garde du registre `clotures` : piste d'audit, jamais modifiée ni archivée.
String? cpcGardeClotures(String op) => op == 'inserer' ? null : 'Le registre des clôtures et réouvertures est une piste d’audit : il ne se modifie ni ne s’archive.';

/// Le numéro de version d'une clôture (n-ième clôture de l'année) et la référence de son archive.
int cpcVersionCloture(Iterable<CpaFiche> clotures, int annee) {
  final n = clotures.where((c) => c['annee'] == annee && c['type'] == 'cloture' && c['statut'] != 'archive').length;
  return n < 1 ? 1 : n;
}

String cpcReferenceArchive(int annee, int version) => 'ARC-$annee-${version.toString().padLeft(2, '0')}';

int? _anneeDe(Object? d) => cpaAnnee(d);

/// Utile aux appelants : l'année d'une date.
int? cpcAnneeArchive(Object? d) => _anneeDe(d);

/// LES ÉCRANS « À ANNÉE » (arbitrage du 05/11/2026), miroir de `N.aExercice` de la maquette (`nav.js`) : le sélecteur d'exercice de la barre supérieure
/// n'apparaît que sur les écrans qui ont une notion d'année ET qui la suivent. Les écrans du jour (caisse, points de vente, files, tableaux de bord) en sont exclus.
const List<String> cpcModulesAExercice = ['M12'];
const List<String> cpcEcransAExercice = [
  'mecef-factures', 'mecef-avoirs', 'mecef-transmission', 'mecef-journal', 'm9-factures-assureur', 'm9-historique',
  'm8-factures', 'm8-facture-avoir', 'm7-commandes', 'm7-factures-fournisseurs', 'm11-bulletins'
];
final RegExp _sauf = RegExp(r'dashboard|^dash-|^hub-|caisse$|point-ventes|point-stock|^m12-ouverture$');

bool cpcAExercice(String ecranId, String module) {
  if (ecranId.isEmpty || _sauf.hasMatch(ecranId)) return false;
  return cpcModulesAExercice.contains(module) || cpcEcransAExercice.contains(ecranId);
}
