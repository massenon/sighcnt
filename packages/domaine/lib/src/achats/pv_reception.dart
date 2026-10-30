/// PV de réception (M7) — `ecranPV(nature)` de `prototype_html/assets/js/modules/m7-achats.js`. Règles rejouées sur les vecteurs
/// `test/vecteurs/pv_reception.json`, tirés des écrans RÉELS pilotés dans la maquette (`build/vecteurs-m7-achats.js`).
///
/// Le procès-verbal CONSTATE la réception (ce qui a été commandé, ce qui est arrivé, les réserves) et se signe à trois : magasinier, DAF,
/// représentant du fournisseur. Deux natures, une mécanique : les réactifs appellent en plus le contrôle de la chaîne du froid.
library;

import '../format/recherche.dart';

typedef FichePv = Map<String, Object?>;

const natureConsommables = 'consommables';
const natureReactifs = 'reactifs';

const conclusionConforme = 'Conforme';
const conclusionAvecReserves = 'Conforme avec réserves';
const conclusionNonConforme = 'Non conforme';
const conclusionsPv = [
  conclusionConforme,
  conclusionAvecReserves,
  conclusionNonConforme
];

/// Le toast de refus quand une conclusion n'est pas « Conforme » et que les réserves sont vides (après rognage).
const messageReservesExigees =
    'Une conclusion avec réserves ou non conforme EXIGE ses réserves écrites.';

/// La maquette lit `sess.nomComplet`, qui n'existe pas dans la session (écart E18) : le magasinier du PV est TOUJOURS ce défaut.
const magasinierParDefaut = 'MAMAN Zoukanéri';

/// Signataire écrit en dur sur la pièce imprimée (la DAF).
const dafSignataire = 'TAKI Alimatou';

/// Un refus du PV. [motif] est le message à afficher ; `null` signifie « formulaire en erreur » (champ obligatoire vide) : les erreurs sont
/// alors portées par les champs eux-mêmes, aucun message global n'est émis.
class RefusPv implements Exception {
  const RefusPv(this.motif);
  final String? motif;
  @override
  String toString() => 'RefusPv(${motif ?? 'champs obligatoires'})';
}

String libelleNature(String nature) =>
    nature == natureReactifs ? 'réactifs' : 'consommables';

/// Sigle de la série de références : `PV-REA-` ou `PV-CON-`.
String sigleNature(String nature) =>
    nature == natureReactifs ? 'REA' : 'CON';

/// Le toast quand aucune livraison ne porte de cette nature.
String messageSansLivraison(String nature) =>
    'Aucune livraison ne porte de ${libelleNature(nature)}.';

/// `estReactif(produitId)` : un produit de catégorie `reactif` ou `conso_labo`. Un article absent du catalogue n'est PAS un réactif — il se
/// range donc parmi les consommables.
bool estReactif(Object? produitId, Iterable<FichePv> produits) {
  for (final p in produits) {
    if (p['id'] == produitId) {
      final c = p['categorie'];
      return c == 'reactif' || c == 'conso_labo';
    }
  }
  return false;
}

/// `lignesDeNature(liv, nature)` : les lignes du bon qui relèvent de cette nature.
List<FichePv> lignesDeNature(
    FichePv livraison, String nature, Iterable<FichePv> produits) {
  final lignes = [
    for (final l in (livraison['lignes'] as List? ?? const []))
      (l as Map).cast<String, Object?>()
  ];
  return [
    for (final l in lignes)
      if (estReactif(l['produitId'], produits) == (nature == natureReactifs))
        l
  ];
}

/// Les bons proposés par « Nouveau PV » : ceux qui portent au moins une ligne de la nature, du plus récent au plus ancien.
List<FichePv> livraisonsPourPv(Iterable<FichePv> livraisonsActives,
        String nature, Iterable<FichePv> produits) =>
    trierPar([
      for (final l in livraisonsActives)
        if (lignesDeNature(l, nature, produits).isNotEmpty) l
    ], (l) => l['date'], descendant: true);

/// `C.referenceSuivante(prefixe, largeur, fiches)` : le plus grand rang déjà écrit pour ce préfixe, plus un — lu sur les PV EXISTANTS,
/// archivés compris (jamais sur un compteur de page : écart E17 corrigé dans la maquette le 30/10/2026).
String referencePvSuivante(
    String nature, String date, Iterable<String> references) {
  final annee = date.length >= 4 ? date.substring(0, 4) : date;
  final prefixe = 'PV-${sigleNature(nature)}-$annee-';
  var max = 0;
  for (final r in references) {
    if (r.startsWith(prefixe)) {
      final k = int.tryParse(r.substring(prefixe.length)) ?? 0;
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(4, '0')}';
}

/// La ligne reprise du bon de livraison : commandée = quantité, livrée = quantité livrée, écart tel que le bon le porte (0 s'il manque).
FichePv lignePv(FichePv l) => {
      'produit': l['produit'],
      'unite': l['unite'],
      'commandee': l['quantite'],
      'livree': l['quantiteLivree'],
      'ecart': l['ecart'] ?? 0,
    };

/// « Établir le PV » : contrôle puis fiche à insérer. [saisie] porte `livraisonRef`, `date`, `conclusion`, `reserves`,
/// `representantFournisseur` et, pour les réactifs, `chaineFroid` (booléen). Lève [RefusPv].
///
/// Deux faits de la maquette, portés fidèlement (E19) : la conclusion n'est dérivée NI des écarts du bon NI de la chaîne du froid — un bon
/// qui porte un écart peut être déclaré « Conforme » sans réserves, et une chaîne rompue n'oblige à rien.
FichePv etablirPv({
  required String nature,
  required Map<String, Object?> saisie,
  required Iterable<FichePv> livraisons,
  required Iterable<FichePv> produits,
  required Iterable<String> references,
  String? nomSession,
}) {
  // Champs obligatoires du formulaire (le panneau les signale lui-même, aucun message global).
  for (final k in const [
    'livraisonRef',
    'date',
    'conclusion',
    'representantFournisseur'
  ]) {
    if ('${saisie[k] ?? ''}'.isEmpty) throw const RefusPv(null);
  }
  final conclusion = '${saisie['conclusion']}';
  final reserves = '${saisie['reserves'] ?? ''}';
  if (conclusion != conclusionConforme && reserves.trim().isEmpty) {
    throw const RefusPv(messageReservesExigees);
  }
  final liv = livraisonsPourPv(livraisons, nature, produits)
      .where((l) => l['reference'] == saisie['livraisonRef'])
      .firstOrNull;
  if (liv == null) throw const RefusPv('Bon de livraison introuvable.');
  final date = '${saisie['date']}';
  return {
    'statut': 'actif',
    'reference': referencePvSuivante(nature, date, references),
    'nature': nature,
    'date': date,
    'livraisonRef': liv['reference'],
    if (liv['commandeRef'] != null) 'commandeRef': liv['commandeRef'],
    'fournisseurNom': liv['fournisseurNom'],
    'lignes': [
      for (final l in lignesDeNature(liv, nature, produits)) lignePv(l)
    ],
    if (nature == natureReactifs) 'chaineFroid': saisie['chaineFroid'] == true,
    'conclusion': conclusion,
    'reserves': reserves,
    'magasinier': (nomSession == null || nomSession.isEmpty)
        ? magasinierParDefaut
        : nomSession,
    'representantFournisseur': saisie['representantFournisseur'],
  };
}

/// Les quatre indicateurs du registre.
class ResumePv {
  const ResumePv(
      {required this.etablis,
      required this.conformes,
      required this.avecReserves,
      required this.nonConformes});
  final int etablis, conformes, avecReserves, nonConformes;
}

ResumePv resumerPv(Iterable<FichePv> pv) {
  final l = pv.toList();
  int n(String c) => l.where((r) => r['conclusion'] == c).length;
  return ResumePv(
      etablis: l.length,
      conformes: n(conclusionConforme),
      avecReserves: n(conclusionAvecReserves),
      nonConformes: n(conclusionNonConforme));
}

/// Ton du badge de conclusion : `succes`, `danger` ou `attention`.
String tonConclusionPv(Object? conclusion) => conclusion == conclusionConforme
    ? 'succes'
    : (conclusion == conclusionNonConforme ? 'danger' : 'attention');
