/// RÉCEPTION, BONS DE LIVRAISON ET ÉCARTS (m7-receptions, m7-livraisons, m7-ecarts).
///
/// Réceptionner une commande : le bordereau est écrit (quantités commandées, reçues, écart), le stock gros reçoit les quantités, le CUMP est recalculé,
/// un mouvement d'entrée est écrit par article, la commande passe « Livrée ». Rejoué sur `test/vecteurs/achats-reception.json`.
///
/// Écarts de la maquette portés fidèlement et signalés :
///   · E80 la saisie est indexée par article : une commande qui porte DEUX FOIS le même article n'a qu'une saisie (la dernière), et le bordereau n'a
///     qu'une ligne pour lui ;
///   · E76 l'écran des écarts annonce que les manquants sont « reportés automatiquement sur la livraison suivante » : rien dans le code ne le fait ;
///     il compte aussi les SURPLUS (écart positif) en valeur absolue dans la « valeur des manquants » ;
///   · un article absent du référentiel est écrit sur le bordereau mais n'entre pas en stock.
library;

import '../format/js.dart';
import 'nombres.dart';
import 'besoins.dart';

typedef _Fiche = Map<String, Object?>;

num _n(Object? v) => nombreEntier(v);

List<_Fiche> _lignes(_Fiche b) => [
      for (final l in (b['lignes'] as List? ?? const []))
        (l as Map).cast<String, Object?>()
    ];

/// L'écart d'une ligne : reçu − commandé.
num ecartLigne(num recu, num commande) => recu - commande;

/// Ce que la réception produit, à appliquer par l'écran dans l'ordre : bordereau, produits, mouvements, commande.
class ReceptionCalculee {
  const ReceptionCalculee(
      {required this.livraison,
      required this.majProduits,
      required this.mouvements,
      required this.patchCommande,
      required this.nbEcarts,
      required this.message,
      required this.type});

  /// La fiche `livraisons` à insérer.
  final _Fiche livraison;

  /// (identifiant du produit, correctif) — stock gros, stock total, CUMP.
  final List<({Object? id, _Fiche patch})> majProduits;

  /// Les fiches `mouvements` à insérer, dans l'ordre d'écriture.
  final List<_Fiche> mouvements;
  final _Fiche patchCommande;
  final int nbEcarts;
  final String message;

  /// `success` (conforme) | `warning` (au moins un écart).
  final String type;
}

/// Calcule la réception d'une commande.
/// [recus] : quantité reçue par article (clé = `produitId`) ; un article non saisi est reçu pour sa quantité commandée.
/// [entete] : `referenceBL`, `date`, `controleur1`, `controleur2`, `controleur3` (facultatif), `observations`.
/// [produits] : les fiches du référentiel (stock, stockGros, cump) ; [mouvements] : tous les mouvements existants (pour la série `Mnnnnnn`).
ReceptionCalculee calculerReception(
    {required _Fiche commande,
    required Map<String, num> recus,
    required _Fiche entete,
    required Iterable<_Fiche> produits,
    required Iterable<_Fiche> mouvements}) {
  // E80 : la maquette indexe la saisie par article (la dernière ligne d'un article en double l'emporte).
  final saisies = <String, ({_Fiche ligne, num recu, num ecart})>{};
  for (final l in _lignes(commande)) {
    final id = '${l['produitId']}';
    final r = recus[id] ?? l['quantite'] as num? ?? 0;
    saisies[id] = (ligne: l, recu: r, ecart: ecartLigne(r, _n(l['quantite'])));
  }
  final vals = saisies.values.toList();
  final nbEcarts = vals.where((x) => x.ecart != 0).length;
  final controleurs = [
    for (final k in const ['controleur1', 'controleur2', 'controleur3'])
      if ('${entete[k] ?? ''}'.isNotEmpty) '${entete[k]}'
  ];
  final livraison = <String, Object?>{
    'reference': entete['referenceBL'],
    'commandeRef': commande['reference'],
    'date': entete['date'],
    'fournisseur': commande['fournisseur'],
    'fournisseurNom': commande['fournisseurNom'],
    'lignes': [
      for (final x in vals) {...x.ligne, 'quantiteLivree': x.recu, 'ecart': x.ecart}
    ],
    'montant': vals.fold<num>(0, (a, x) => a + x.recu * _n(x.ligne['prixUnitaire'])),
    'controlePar': controleurs,
    'statutReception': nbEcarts > 0 ? 'ecart' : 'conforme',
    'observations': entete['observations'],
  };

  final majProduits = <({Object? id, _Fiche patch})>[];
  final mvts = <_Fiche>[];
  final dejaEcrits = [...mouvements];
  for (final x in vals) {
    if (x.recu <= 0) continue;
    final p = produits.where((pp) => pp['id'] == x.ligne['produitId']).firstOrNull;
    if (p == null) continue; // hors référentiel : écrit au bordereau, sans entrée en stock
    // CUMP = (valeur du stock existant + valeur de l'entrée) / quantité totale.
    final nouvelleQte = _n(p['stock']) + x.recu;
    final nouveauCump = nouvelleQte > 0
        ? entierSiPossible(arrondiJs((_n(p['stock']) * _n(p['cump']) + x.recu * _n(x.ligne['prixUnitaire'])) / nouvelleQte))
        : _n(x.ligne['prixUnitaire']);
    majProduits.add((
      id: p['id'],
      patch: {
        'stockGros': _n(p['stockGros']) + x.recu,
        'stock': nouvelleQte,
        'cump': nouveauCump,
      }
    ));
    final mv = <String, Object?>{
      'reference': referenceAchatSuivante('M', 6, dejaEcrits),
      'date': entete['date'],
      'produitId': p['id'],
      'produit': p['designation'],
      'type': 'entree',
      'typeLabel': 'Entrée',
      'quantite': x.recu,
      'stockType': 'gros',
      'justificatif': 'Bon de livraison ${entete['referenceBL']}',
      'utilisateur': controleurs.isEmpty ? null : controleurs.first,
    };
    dejaEcrits.add(mv);
    mvts.add(mv);
  }
  return ReceptionCalculee(
      livraison: livraison,
      majProduits: majProduits,
      mouvements: mvts,
      patchCommande: {'statutCommande': 'livree'},
      nbEcarts: nbEcarts,
      message:
          'Réception enregistrée — ${nbEcarts > 0 ? '$nbEcarts écart(s) constaté(s).' : 'livraison conforme.'}',
      type: nbEcarts > 0 ? 'warning' : 'success');
}

/// La création manuelle d'un bon de livraison (`K.creer`) : numéro `BL-nnnnn`, fournisseur nommé, pas de lignes, montant 0 s'il est vide,
/// contrôleur en liste.
_Fiche livraisonCreee(
    {required _Fiche saisie,
    required Iterable<_Fiche> fournisseurs,
    required Iterable<_Fiche> livraisons}) {
  final v = {...saisie};
  v['reference'] = referenceAchatSuivante('BL-', 5, livraisons);
  final f = fournisseurs.where((x) => x['code'] == v['fournisseur']).firstOrNull;
  v['fournisseurNom'] = f != null ? f['nom'] : v['fournisseur'];
  v['lignes'] = v['lignes'] ?? const [];
  final m = v['montant'];
  v['montant'] = (m == null || m == '' || _n(m) == 0) ? 0 : _n(m);
  final c = v['controlePar'];
  v['controlePar'] = (c == null || c == '') ? <String>[] : ['$c'];
  return v;
}

/// La modification d'un bon de livraison (`K.modifier`) : le formulaire saisit les contrôleurs en TEXTE séparé par des virgules, l'écran lit une
/// LISTE — E78 corrigé dans la maquette (sans cette conversion, le détail du bon cassait au clic).
_Fiche livraisonModifiee(_Fiche saisie) {
  final v = {...saisie};
  v['controlePar'] = [
    for (final x in '${v['controlePar'] ?? ''}'.split(','))
      if (x.trim().isNotEmpty) x.trim()
  ];
  final m = v['montant'];
  v['montant'] = (m == null || m == '') ? 0 : _n(m);
  return v;
}

/// Les quatre indicateurs de l'écran des bons de livraison.
({int total, int conformes, int avecEcart, num valeur}) indicateursLivraisons(
        Iterable<_Fiche> actives) =>
    (
      total: actives.length,
      conformes: actives.where((l) => l['statutReception'] == 'conforme').length,
      avecEcart: actives.where((l) => l['statutReception'] == 'ecart').length,
      valeur: actives.fold<num>(0, (a, l) => a + _n(l['montant'])),
    );

/// Une ligne du registre des écarts (une par article en écart d'une livraison « avec écart »).
class LigneEcart {
  const LigneEcart(
      {required this.id,
      required this.bl,
      required this.commande,
      required this.date,
      required this.fournisseur,
      required this.produit,
      required this.unite,
      required this.commandee,
      required this.livree,
      required this.ecart,
      required this.valeur});
  final String id;
  final Object? bl;
  final Object? commande;
  final Object? date;
  final Object? fournisseur;
  final Object? produit;
  final Object? unite;
  final Object? commandee;
  final Object? livree;
  final num ecart;

  /// |écart| × prix unitaire — le surplus compte autant que le manquant (E76).
  final num valeur;

  _Fiche toFiche() => {
        'id': id,
        'bl': bl,
        'commande': commande,
        'date': date,
        'fournisseur': fournisseur,
        'produit': produit,
        'unite': unite,
        'commande_qte': commandee,
        'livree': livree,
        'ecart': ecart,
        'valeur': valeur,
        'regularise': false,
      };
}

/// Les livraisons « avec écart » et, pour chacune, ses lignes dont l'écart n'est pas nul.
({List<_Fiche> livraisons, List<LigneEcart> lignes}) registreEcarts(
    Iterable<_Fiche> livraisonsActives) {
  final livs = [
    for (final l in livraisonsActives)
      if (l['statutReception'] == 'ecart') l
  ];
  final rows = <LigneEcart>[];
  for (final l in livs) {
    for (final x in _lignes(l)) {
      final e = x['ecart'];
      if (e != null && e != 0 && _n(e) != 0) {
        rows.add(LigneEcart(
            id: '${l['id']}-${x['produitId']}',
            bl: l['reference'],
            commande: l['commandeRef'],
            date: l['date'],
            fournisseur: l['fournisseurNom'],
            produit: x['produit'],
            unite: x['unite'],
            commandee: x['quantite'],
            livree: x['quantiteLivree'],
            ecart: entierSiPossible(_n(e)),
            valeur: _n(e).abs() * _n(x['prixUnitaire'])));
      }
    }
  }
  return (livraisons: livs, lignes: rows);
}

/// Les quatre indicateurs de l'écran des écarts.
({int ecarts, int livraisons, num valeur, int fournisseurs}) indicateursEcarts(
    ({List<_Fiche> livraisons, List<LigneEcart> lignes}) r) {
  return (
    ecarts: r.lignes.length,
    livraisons: r.livraisons.length,
    valeur: r.lignes.fold<num>(0, (a, l) => a + l.valeur),
    fournisseurs: {for (final l in r.lignes) '${l.fournisseur}'}.length,
  );
}
