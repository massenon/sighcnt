/// LECTURES DES REGISTRES DE LA CONSULTATION — les calculs que les écrans `m2-pathologies`, `m2-dossiers-consultation`, `m2-ordonnances`,
/// `m2-prescriptions` et `m2-salle-soins` affichent, rejoués sur les vecteurs de ces écrans réels.
library;

import '../format/format_fr.dart';
import 'cs_referentiels.dart';

/// `comptage()` de `m2-pathologies` : le nombre de cas par code de pathologie, lu sur les consultations ACTIVES. Une consultation d'avant le
/// référentiel ne porte qu'un diagnostic rédigé : elle n'est pas comptée rétrospectivement.
Map<String, int> csComptagePathologies(Iterable<FicheCs> consultations) {
  final sortie = <String, int>{};
  for (final c in consultations) {
    for (final code in (c['pathologies'] as List? ?? const [])) {
      sortie['$code'] = (sortie['$code'] ?? 0) + 1;
    }
  }
  return sortie;
}

/// Une ligne du tableau de morbidité / du référentiel : la pathologie, son chapitre lisible et son nombre de cas.
FicheCs csLignePathologie(FicheCs x, Map<String, int> cas) {
  final ch = csChapitresPathologie.where((y) => y['id'] == x['chapitre']).firstOrNull;
  return {
    ...x,
    'cas': cas['${x['code']}'] ?? 0,
    'chapitreLabel': ch != null ? ch['label'] : x['chapitre'],
  };
}

/// Le tableau de morbidité : les pathologies qui ont au moins un cas, du plus fréquent au moins fréquent (tri stable).
List<FicheCs> csMorbidite(Iterable<FicheCs> pathologies, Map<String, int> cas) {
  final l = [
    for (final x in pathologies) csLignePathologie(x, cas)
  ].where((x) => (x['cas'] as int) > 0).toList();
  // `Array.prototype.sort` est stable : à égalité de cas, l'ordre du référentiel est conservé.
  final indexe = [for (var i = 0; i < l.length; i++) (i, l[i])];
  indexe.sort((a, b) {
    final c = (b.$2['cas'] as int).compareTo(a.$2['cas'] as int);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexe) e.$2];
}

/// Les indicateurs du registre des dossiers : comptes par état et venues du [jour] (`YYYY-MM-DD`).
({int attente, int consultation, int attenteLabo, int cloture, int duJour})
    csKpisDossiers(Iterable<FicheCs> actifs, String jour) {
  int c(String etat) => actifs.where((r) => r['etat'] == etat).length;
  return (
    attente: c('attente'),
    consultation: c('consultation'),
    attenteLabo: c('attente_labo'),
    cloture: c('cloture'),
    duJour: actifs
        .where((r) => '${r['dateArrivee'] ?? ''}'.padRight(10).substring(0, 10).trim() == jour)
        .length,
  );
}

/// La période « Aujourd'hui / 7 derniers jours » du registre des dossiers.
bool csDansPeriode(FicheCs r, String valeur, DateTime maintenant) {
  final d = '${r['dateArrivee'] ?? ''}';
  final jour = d.length >= 10 ? d.substring(0, 10) : d;
  final auj = iso(maintenant);
  if (valeur == 'jour') return jour == auj;
  final s = DateTime(maintenant.year, maintenant.month, maintenant.day - 7);
  return jour.compareTo(iso(s)) >= 0 && jour.compareTo(auj) <= 0;
}

/// Les indicateurs du registre des ordonnances.
({int emises, int enAttente, int aDelivrer, num valeur}) csKpisOrdonnances(
    Iterable<FicheCs> actives) {
  num v = 0;
  for (final r in actives) {
    final m = r['montant'];
    if (m is num) v += m;
  }
  return (
    emises: actives.length,
    enAttente: actives.where((r) => r['statutPaiement'] != 'soldee').length,
    aDelivrer: actives.where((r) => r['statutDispensation'] == 'en_attente').length,
    valeur: v,
  );
}

/// Les indicateurs du registre des prescriptions.
({int total, int ordonnances, int soins, int attenteReglement}) csKpisPrescriptions(
        Iterable<FicheCs> rows) =>
    (
      total: rows.length,
      ordonnances: rows.where((r) => r['type'] == 'ordonnance').length,
      soins: rows.where((r) => r['type'] == 'soins').length,
      attenteReglement: rows.where((r) => r['statutPaiement'] != 'payee').length,
    );
