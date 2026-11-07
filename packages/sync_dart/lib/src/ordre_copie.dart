/// L'ORDRE D'UNE VERSION DE FICHE DANS LA COPIE CONSULTABLE (PRD relais consultable) : deux appareils déposent chacun SA version d'une même fiche, et la page ne doit pas
/// retenir « la dernière lue » : elle retient la version qui SAIT LE PLUS, quel que soit l'ordre de lecture.
///
/// `ordre = [nOps, hlc, appareil, idOp]` : [nOps] est le nombre d'opérations connues de la fiche (un poste qui a relevé davantage sait davantage : son jeu d'opérations
/// CONTIENT celui de l'autre, donc sa version est la plus récente), puis la dernière opération de l'ordre total de la règle de fusion ([comparerOperationsPair] :
/// hlc, appareil, id) pour départager deux postes qui ne se sont pas encore vus. Le `seq` de la mère, quand il existe, est porté à titre INFORMATIF : le comparer
/// aurait mêlé deux ordres (celui de la mère, celui des horloges) et cassé la transitivité, donc la convergence. Une enveloppe sans `ordre` (ancienne) est la plus ancienne.
library;

import 'package:sigh_domaine/sigh_domaine.dart';

/// La clé d'une fiche : « collection/identifiant ».
String cleFiche(OperationPair o) => '${o.collection}/${o.fiche}';

/// Compare deux ordres de copie (listes JSON `[n, hlc, appareil, id]`) ; `null` = ordre inconnu = le plus ancien. Total : lexicographique.
int comparerOrdreCopie(List<Object?>? a, List<Object?>? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  for (var i = 0; i < 4; i++) {
    final x = a[i], y = b[i];
    final c = x is num && y is num ? x.compareTo(y) : '$x'.compareTo('$y');
    if (c != 0) return c;
  }
  return 0;
}

/// La charge de copie d'UNE fiche, calculée depuis SES opérations seules (famille A : les fiches sont indépendantes les unes des autres). `null` si la règle de
/// fusion ne retient aucune fiche (opérations toutes refusées). [ops] : toutes les opérations connues de CETTE fiche, doublons tolérés.
Map<String, Object?>? chargeCopieDeFiche(String collection, String fiche, Iterable<OperationPair> ops, {DroitsOperation? droits}) {
  final uniques = {for (final o in ops) o.id: o}.values.toList();
  if (uniques.isEmpty) return null;
  final etat = etatPair(uniques, droits: droits);
  final f = etat.fiches['$collection/$fiche'];
  if (f == null) return null;
  final derniere = (uniques..sort(comparerOperationsPair)).last;
  int? seq;
  for (final o in uniques) {
    if (o.seq != null && (seq == null || o.seq! > seq)) seq = o.seq;
  }
  return {
    'collection': collection,
    'fiche': fiche,
    'data': f['data'],
    'archive': f['archive'] == true,
    'ordre': [uniques.length, derniere.hlc, derniere.appareil, derniere.id],
    if (seq != null) 'seq': seq,
  };
}

/// Ce qui décide de redéposer : le CONTENU (données et archivage), jamais l'ordre ni le seq. Une version qui ne change rien n'est pas redéposée.
Map<String, Object?> contenuCopie(Map<String, Object?> charge) =>
    {'collection': charge['collection'], 'fiche': charge['fiche'], 'data': charge['data'], 'archive': charge['archive']};
