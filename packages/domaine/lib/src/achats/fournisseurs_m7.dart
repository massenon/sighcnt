/// Fournisseurs (M7) — `m7-fournisseurs` de `prototype_html/assets/js/modules/m7-achats.js` (un `K.crud`). Règles rejouées sur
/// `test/vecteurs/fournisseurs_m7.json`, tiré de l'écran réel piloté dans la maquette (`build/vecteurs-m7-achats.js`).
library;

import '../format/js.dart';
import '../format/recherche.dart';

typedef FicheFournisseur = Map<String, Object?>;

/// Un formulaire dont des champs obligatoires sont vides : les erreurs sont portées par les champs, la maquette n'émet que
/// « Le formulaire comporte des erreurs. ».
class FormulaireInvalide implements Exception {
  const FormulaireInvalide(this.champs);
  final List<String> champs;
  @override
  String toString() => 'FormulaireInvalide($champs)';
}

/// Les six types de la liste du formulaire.
const typesFournisseur = [
  'Grossiste pharmaceutique',
  'Centrale d’achat',
  'Réactifs & consommables labo',
  'Matériel médical',
  'Fournitures & entretien',
  'Prestataire de services',
];

double _n(Object? v) => nombreOuZero(v);

/// Les commandes passées auprès du fournisseur : la clé est le CODE (modifiable, écart signalé : changer un code orpheline ses commandes).
List<FicheFournisseur> commandesDuFournisseur(
        String? code, Iterable<FicheFournisseur> commandes) =>
    [
      for (final c in commandes)
        if (c['fournisseur'] == code) c
    ];

/// Historique du tiroir : du plus récent au plus ancien, douze au plus.
List<FicheFournisseur> historiqueDuTiroir(
        Iterable<FicheFournisseur> commandesDuFournisseur) =>
    trierPar(commandesDuFournisseur.toList(), (c) => c['date'],
            descendant: true)
        .take(12)
        .toList();

/// Les quatre indicateurs. Le VOLUME d'achats somme TOUTES les commandes actives — pas seulement celles des fournisseurs listés —, et le
/// délai moyen divise par le nombre de fournisseurs, ceux sans délai comptant pour 0.
class KpisFournisseurs {
  const KpisFournisseurs(
      {required this.references,
      required this.habilites,
      required this.volumeAchats,
      required this.delaiMoyen});
  final int references, habilites, delaiMoyen;
  final double volumeAchats;
}

KpisFournisseurs kpisFournisseurs(Iterable<FicheFournisseur> fournisseurs,
    Iterable<FicheFournisseur> commandes) {
  final l = fournisseurs.toList();
  final somme = l.fold<double>(0, (a, f) => a + _n(f['delai']));
  return KpisFournisseurs(
    references: l.length,
    habilites: l.where((f) => f['habilite'] == true).length,
    volumeAchats: commandes.fold<double>(0, (a, c) => a + _n(c['montant'])),
    delaiMoyen: l.isEmpty ? 0 : arrondiJs(somme / l.length).toInt(),
  );
}

/// Ce que le formulaire (« Nouveau » comme « Modifier ») écrit : les sept champs, `delai` en nombre (absent s'il est vide), `habilite` en
/// booléen. AUCUN contrôle d'unicité du code (écart signalé). Lève [FormulaireInvalide].
FicheFournisseur valeursFournisseur(Map<String, Object?> saisie) {
  final manquants = [
    for (final k in const ['code', 'nom', 'type'])
      if ('${saisie[k] ?? ''}'.isEmpty) k
  ];
  if (manquants.isNotEmpty) throw FormulaireInvalide(manquants);
  final delai = num.tryParse('${saisie['delai'] ?? ''}');
  return {
    'code': saisie['code'],
    'nom': saisie['nom'],
    'type': saisie['type'],
    'ville': saisie['ville'] ?? '',
    'tel': saisie['tel'] ?? '',
    'delai': delai,
    'habilite': saisie['habilite'] == true,
  };
}
