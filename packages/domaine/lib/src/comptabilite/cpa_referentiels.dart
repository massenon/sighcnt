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

/// `compteLibelle(num)` : le plan STATIQUE `D.PLAN_COMPTABLE` ; un numéro inconnu s'affiche tel quel.
String cpaCompteLibelle(Object? num) {
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

/// `comptesCharge()` : les comptes de CHARGE du plan statique (tout numéro commençant par 6).
List<(String, String)> cpaComptesCharge() => [
      for (final c in cpaPlanComptable)
        if (c.$1.startsWith('6')) (c.$1, c.$2)
    ];

/// `D.PLAN_COMPTABLE` vu comme fiches : pour comparer le plan engendré à celui que la maquette porte.
List<CpaFiche> cpaPlanEnFiches() => [
      for (final c in cpaPlanComptable)
        {'num': c.$1, 'libelle': c.$2, 'classe': c.$3, 'journal': c.$4, 'source': c.$5}
    ];

/// Aide d'affichage : `C.money(v, false)`.
String cpaMontant(Object? v) => money(v, avecDevise: false);

/// `beforeSave` du plan comptable : un message de refus, ou `null`. Le numéro compte six chiffres ; à la CRÉATION, il ne doit pas déjà exister parmi
/// les comptes actifs (à la modification, la maquette ne contrôle pas l'unicité — porté fidèlement).
String? cpaVerifierNumeroCompte(Object? num, Iterable<CpaFiche> comptesActifs, {required bool edition}) {
  if (!RegExp(r'^\d{6}$').hasMatch('$num')) return 'Le numéro de compte doit comporter 6 chiffres.';
  if (!edition && comptesActifs.any((c) => c['num'] == '$num')) return 'Ce numéro de compte existe déjà.';
  return null;
}

/// `transform` du plan comptable : la classe est un nombre ; un compte CRÉÉ à l'écran est un « Complément » (`source: 'CDCT'`). À la modification
/// la provenance est CONSERVÉE (E721 : la maquette la remettait à `CDCT`, un compte du document devenait un complément — corrigé d'abord).
CpaFiche cpaCompteDeSaisie(Map<String, Object?> saisie, {CpaFiche? record}) => {
      ...saisie,
      'classe': int.tryParse('${saisie['classe']}') ?? 0,
      if (record == null && (saisie['source'] == null || saisie['source'] == '')) 'source': 'CDCT',
    };
