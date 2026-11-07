/// RÉFÉRENTIELS DE LA COMPTABILITÉ DE BASE (M12) — `D.JOURNAUX`, `D.CATEGORIES_DEPENSE`, `D.CENTRES_COUT` et le plan statique `D.PLAN_COMPTABLE`
/// (prototype_html/assets/js/data.js). Lus à la source par `build/vecteurs-comptabilite.js` : le test compare ces listes à ce que la maquette porte.
///
/// Symboles préfixés `cpa` : ils ne rencontrent aucun autre module du domaine.
library;

import '../format/format_fr.dart';
import 'cpa_plan.dart';

typedef CpaFiche = Map<String, Object?>;

/// `D.JOURNAUX` : (code, libellé, compte de contrepartie — `null` : « Variable »).
const List<(String, String, String?)> cpaJournaux = [
  ('ACH', 'Journal des achats', '401000'),
  ('VTE', 'Journal des ventes', '411000'),
  ('CAI', 'Journal de caisse-dépenses', '571000'),
  ('BQ', 'Journal de banque', '521000'),
  // E719 levé : une dépense réglée par banque s'écrit au journal BQE ; le code manquait au référentiel.
  ('BQE', 'Journal de banque, dépenses', '521000'),
  ('SAL', 'Journal des salaires', '422000'),
  ('IMM', 'Journal des immobilisations', '241000'),
  ('OD', 'Journal des opérations diverses', null),
  ('AN', 'Journal des à-nouveaux', null),
];

/// `D.CATEGORIES_DEPENSE` : (identifiant, libellé) — la lecture de GESTION, distincte du compte SYSCOHADA.
const List<(String, String)> cpaCategoriesDepense = [
  ('medical', 'Consommables et produits médicaux'),
  ('fonctionnement', 'Fonctionnement courant'),
  ('logistique', 'Logistique et transport'),
  ('entretien', 'Entretien, réparations et maintenance'),
  ('personnel', 'Personnel et prestations externes'),
  ('fiscal', 'Impôts, taxes et frais bancaires'),
  ('divers', 'Charges diverses'),
];

/// `D.CENTRES_COUT` : (identifiant, libellé, type).
const List<(String, String, String)> cpaCentresCout = [
  ('laboratoire', 'Laboratoire', 'exploitation'),
  ('pharmacie', 'Pharmacie', 'exploitation'),
  ('consultation', 'Consultation', 'exploitation'),
  ('imagerie', 'Imagerie médicale', 'exploitation'),
  ('maternite', 'Maternité', 'exploitation'),
  ('hospitalisation', 'Hospitalisation et soins', 'exploitation'),
  ('direction', 'Direction', 'support'),
];

/// `classeLibelle(n)`.
String cpaClasseLibelle(Object? n) =>
    const {
      1: 'Classe 1 — Ressources durables',
      2: 'Classe 2 — Actif immobilisé',
      3: 'Classe 3 — Stocks',
      4: 'Classe 4 — Tiers',
      5: 'Classe 5 — Trésorerie',
      6: 'Classe 6 — Charges',
      7: 'Classe 7 — Produits',
      8: 'Classe 8 — Autres charges et produits',
    }[n is num ? n.toInt() : int.tryParse('$n')] ??
    'Classe $n';

/// `compteLibelle(num)` : la collection `comptes` fait foi quand [comptes] est donnée (E715 levé : un compte créé à l'écran prime sur le plan
/// statique), puis le plan STATIQUE `D.PLAN_COMPTABLE` ; un numéro inconnu s'affiche tel quel.
String cpaCompteLibelle(Object? num, {Iterable<CpaFiche> comptes = const []}) {
  for (final c in comptes) {
    if ('${c['num']}' == '$num') return '${c['libelle']}';
  }
  for (final c in cpaPlanComptable) {
    if (c.$1 == '$num') return c.$2;
  }
  return '$num';
}

/// `journalLibelle(code)`.
String cpaJournalLibelle(Object? code) {
  for (final j in cpaJournaux) {
    if (j.$1 == '$code') return j.$2;
  }
  return '$code';
}

/// `libelleCategorieDepense(id)` : « — » si absent, l'identifiant s'il est inconnu.
String cpaCategorieDepenseLibelle(Object? id) {
  for (final c in cpaCategoriesDepense) {
    if (c.$1 == '$id') return c.$2;
  }
  return id == null || id == '' ? '—' : '$id';
}

/// `comptesCharge()` : les comptes de CHARGE (tout numéro commençant par 6). E715 levé : la collection `comptes` ([comptes], actifs) fait foi, de sorte
/// qu'un compte créé à l'écran est proposable en dépense ; le plan statique ne sert que si la collection est vide.
List<(String, String)> cpaComptesCharge({Iterable<CpaFiche> comptes = const []}) {
  final l = comptes.toList();
  if (l.isNotEmpty) {
    return [
      for (final c in l)
        if ('${c['num']}'.startsWith('6')) ('${c['num']}', '${c['libelle']}')
    ];
  }
  return [
    for (final c in cpaPlanComptable)
      if (c.$1.startsWith('6')) (c.$1, c.$2)
  ];
}

/// E724/E725 levés : le plan du jeu portait DEUX fiches au même numéro (244100, 631810). On garde la première fiche (celle du document) et on archive le
/// doublon avec son motif (RG-14). Renvoie (identifiant du doublon, motif) pour chaque fiche à archiver parmi [comptesActifs], dans l'ordre du plan.
List<(String, String)> cpaDoublonsDuPlan(Iterable<CpaFiche> comptesActifs) {
  final vus = <String, CpaFiche>{};
  final out = <(String, String)>[];
  for (final c in comptesActifs) {
    final n = '${c['num']}';
    final premier = vus[n];
    if (premier == null) {
      vus[n] = c;
      continue;
    }
    out.add(('${c['id']}', 'Doublon du plan comptable (numéro $n): la fiche conservée est « ${premier['libelle']} » (${premier['id']}).'));
  }
  return out;
}

/// `D.PLAN_COMPTABLE` vu comme fiches : pour comparer le plan engendré à celui que la maquette porte.
List<CpaFiche> cpaPlanEnFiches() => [
      for (final c in cpaPlanComptable)
        {'num': c.$1, 'libelle': c.$2, 'classe': c.$3, 'journal': c.$4, 'source': c.$5}
    ];

/// Aide d'affichage : `C.money(v, false)`.
String cpaMontant(Object? v) => money(v, avecDevise: false);

/// `beforeSave` du plan comptable : un message de refus, ou `null`. Le numéro compte six chiffres et il est UNIQUE (E724 levé), à la création comme
/// quand une modification change le numéro : [comptes] (actifs) et [archives] sont contrôlés, la fiche en cours d'édition ([idEnEdition]) exceptée. Un compte
/// archivé garde son numéro (RG-14) : il se restaure, il ne se recrée pas.
String? cpaVerifierNumeroCompte(Object? num, Iterable<CpaFiche> comptes,
    {required bool edition, Object? idEnEdition, Iterable<CpaFiche> archives = const []}) {
  if (!RegExp(r'^\d{6}$').hasMatch('$num')) return 'Le numéro de compte doit comporter 6 chiffres.';
  final pris = [...comptes, ...archives].where((c) => c['num'] == '$num' && (idEnEdition == null || c['id'] != idEnEdition)).firstOrNull;
  if (pris != null) {
    return pris['statut'] == 'archive'
        ? 'Ce numéro de compte existe déjà (compte archivé : le restaurer depuis la corbeille).'
        : 'Ce numéro de compte existe déjà.';
  }
  return null;
}

/// `transform` du plan comptable : la classe est un nombre ; un compte CRÉÉ à l'écran est un « Complément » (`source: 'CDCT'`). À la modification
/// la provenance est CONSERVÉE (E721 : la maquette la remettait à `CDCT`, un compte du document devenait un complément — corrigé d'abord).
CpaFiche cpaCompteDeSaisie(Map<String, Object?> saisie, {CpaFiche? record}) => {
      ...saisie,
      'classe': int.tryParse('${saisie['classe']}') ?? 0,
      if (record == null && (saisie['source'] == null || saisie['source'] == '')) 'source': 'CDCT',
    };
