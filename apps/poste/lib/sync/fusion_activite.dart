import 'dart:convert';

import '../donnees/magasin.dart';

/// LES RÈGLES DE FUSION DE L'ACTIVITÉ QUI NE SE LAISSE PAS ÉCRASER (limites levées le 03/11/2026).
///
/// « Le dernier geste gagne » corromprait une facture (un encaissement perdu), un stock (une sortie perdue), une numérotation (deux pièces au même numéro).
/// Chaque famille de données a donc SA règle, toutes pures et testées sans réseau :
///
/// * **compteurs** (stock des produits, quantité restante des lots) : jamais remplacés, jamais écrasés : chaque poste publie ses VARIATIONS, et chaque poste
///   les additionne. Deux sorties simultanées de deux postes se retranchent toutes les deux (commutatif). Le seul risque, un stock devenu négatif par deux
///   sorties hors ligne du dernier exemplaire, est DÉTECTÉ et dit (RG-03), jamais corrigé en silence.
/// * **factures** : un règlement ne se perd pas. Une ligne réglée l'emporte sur une ligne due ; le montant payé ne recule jamais ; le statut avance, il ne
///   recule pas. Une ligne réglée par DEUX postes à la fois est signalée (`encaissementEnDoublon`).
/// * **numéros** (facture, avoir, pièce comptable, dossier) : jamais renumérotés (une pièce émise ne se réécrit jamais, RG-01), deux pièces au même numéro sont
///   MARQUÉES et comptées ; la Direction tranche.
/// * **lits** : une admission active par lit ; deux admissions actives sur le même lit sont marquées `litEnConflit`.

/// Les champs d'une fiche qui sont des COMPTEURS (additionnés, jamais remplacés).
const Map<String, Set<String>> champsCompteurs = {
  'produits': {'stockGros', 'stockDetail', 'stock'},
  'lots': {'quantiteRestante'},
  // Les règlements d'une facture s'additionnent : deux guichets qui encaissent deux lignes en même temps ne s'effacent pas.
  'factures': {'montantPaye', 'reliquat'},
};

/// Le statut de paiement qui découle des compteurs d'une facture : soldée quand plus rien n'est dû, partielle dès qu'un règlement existe. Il ne RECULE jamais
/// (une facture soldée ne redevient pas partielle parce qu'une version plus ancienne arrive). `null` : rien à changer.
String? statutPaiementDepuis(Fiche f) {
  if (!f.containsKey('montantPaye') || !f.containsKey('reliquat')) return null;
  final paye = _n(f['montantPaye']), reste = _n(f['reliquat']);
  final voulu = reste <= 0 && paye > 0 ? 'soldee' : (paye > 0 ? 'partielle' : null);
  if (voulu == null) return null;
  final actuel = _ordreStatutPaiement['${f['statutPaiement']}'] ?? -1;
  return _ordreStatutPaiement[voulu]! > actuel ? voulu : null;
}

/// Le champ qui porte le NUMÉRO d'une pièce, par collection, et le nom du marqueur posé en cas de doublon.
const Map<String, ({String champ, String marqueur})> champsNumero = {
  'patients': (champ: 'code', marqueur: 'codeEnDoublon'),
  'factures': (champ: 'numero', marqueur: 'numeroEnDoublon'),
  'avoirs': (champ: 'reference', marqueur: 'numeroEnDoublon'),
  'ecritures': (champ: 'numero', marqueur: 'numeroEnDoublon'),
};

String _j(Object? o) => jsonEncode(o);

const _ordreStatutPaiement = {'impayee': 0, 'partielle': 1, 'soldee': 2};

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// Fusion d'une FACTURE : [fusion] est la fusion champ à champ déjà faite (ce que l'agent a changé ici est gardé, le reste suit le journal) ; cette fonction
/// la corrige pour qu'aucun règlement ne se perde. [local] et [recu] sont les deux versions face à face.
Map<String, Object?> fusionnerFacture(Map<String, Object?> fusion, Fiche local, Map<String, Object?> recu) {
  final r = {...fusion};
  // Les lignes : par identifiant de ligne ; la ligne RÉGLÉE l'emporte (le règlement le plus ancien est conservé, il est celui qui a libéré la prestation).
  final a = [for (final l in (local['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final b = [for (final l in (recu['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  if (a.isNotEmpty || b.isNotEmpty) {
    final parId = <String, Map<String, Object?>>{for (final l in a) '${l['id']}': l};
    final doublons = <String>[];
    final ordre = [for (final l in a) '${l['id']}'];
    for (final l in b) {
      final id = '${l['id']}';
      final ici = parId[id];
      if (ici == null) {
        parId[id] = l;
        ordre.add(id);
        continue;
      }
      final iciPaye = ici['statutPaiement'] == 'paye', laPaye = l['statutPaiement'] == 'paye';
      if (iciPaye && laPaye && '${ici['payePar']}${ici['payeLe']}' != '${l['payePar']}${l['payeLe']}') {
        doublons.add(id);
        // Les deux ont encaissé : on garde le plus ancien et on SIGNALE.
        final dIci = DateTime.tryParse('${ici['payeLe'] ?? ''}'), dLa = DateTime.tryParse('${l['payeLe'] ?? ''}');
        if (dIci != null && dLa != null && dLa.isBefore(dIci)) parId[id] = l;
      } else if (!iciPaye && laPaye) {
        parId[id] = l;
      }
    }
    r['lignes'] = [for (final id in ordre) parId[id]!];
    if (doublons.isNotEmpty) r['encaissementEnDoublon'] = doublons;
  }
  // Le montant payé et le reliquat sont des COMPTEURS (voir `champsCompteurs`) : ils s'additionnent par leurs variations ; le statut en est DÉDUIT ensuite
  // (`statutPaiementDepuis`), il ne se choisit pas entre deux versions.
  // Le dernier règlement : le plus récent.
  final dl = local['dernierReglement'], dr = recu['dernierReglement'];
  if (dl is Map && dr is Map) {
    final tl = DateTime.tryParse('${dl['date']}'), tr = DateTime.tryParse('${dr['date']}');
    r['dernierReglement'] = (tl != null && tr != null && tr.isAfter(tl)) ? dr : dl;
  }
  return r;
}

/// Les groupes de fiches qui portent le même NUMÉRO alors qu'elles ne sont pas la même pièce. [identite] : ce qui distingue deux pièces (`pieceId` pour deux
/// lignes d'une même écriture comptable, l'identité de synchronisation sinon).
List<List<Fiche>> numerosEnDoublon(Iterable<Fiche> fiches, String champ, String Function(Fiche) identite) {
  final par = <String, Map<String, List<Fiche>>>{};
  for (final f in fiches) {
    final num = '${f[champ] ?? ''}';
    if (num.isEmpty || CollectionMagasin.estArchivee(f)) continue;
    ((par[num] ??= {})[identite(f)] ??= []).add(f);
  }
  return [
    for (final g in par.values)
      if (g.length > 1) [for (final l in g.values) ...l]
  ];
}

/// Les groupes d'admissions ACTIVES qui occupent le même lit (un lit ne porte qu'une admission active).
List<List<Fiche>> litsEnConflit(Iterable<Fiche> admissions) {
  final par = <String, List<Fiche>>{};
  for (final a in admissions) {
    if (a['statut'] != 'en_cours') continue;
    final lit = '${a['lit'] ?? ''}'.trim();
    if (lit.isEmpty) continue;
    (par[lit] ??= []).add(a);
  }
  return [
    for (final g in par.values)
      if (g.length > 1) g
  ];
}
