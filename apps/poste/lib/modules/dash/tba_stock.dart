import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// `dash-stock` — « Tableau de bord — Gestion des stocks » : RG-05 (FEFO et alertes de péremption) et RG-03. Le gestionnaire regarde d'abord ce qui
/// va manquer ou périmer — pas l'inventaire. Un seuil NON FIXÉ n'est pas un seuil de zéro : l'article est compté à part.
class EcranDashStock extends StatelessWidget with EcranMaquette {
  const EcranDashStock({super.key});

  @override
  String get titre => 'Tableau de bord — Gestion des stocks';

  @override
  String get description =>
      'Stock gros et détail, mouvements, cycle d’achat, inventaires et suivi des écarts.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['produits', 'lots', 'mouvements']),
      builder: (context, _) {
        final d = tbaStock(
            produits: tbaActives(c, 'produits'),
            lots: tbaActives(c, 'lots'),
            mouvements: tbaActives(c, 'mouvements'),
            categories: {for (final k in categoriesProduit) k.id: k.label},
            auj: c.aujourdhui);
        return TbaDash(
          alerte: d.alertes.isEmpty ? null : BandeauAlertesTba(d.alertes),
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m7-besoins', 'clipboard-list', 'Bons d’expression de besoins', 'Quantité demandée / accordée'),
              ('m7-commandes', 'truck', 'Bons de commande', 'Validation DA requise (RG-04)'),
              ('m6-inventaire', 'clipboard-check', 'Inventaire', 'Écarts physique / théorique'),
              ('m6-pertes', 'trash-2', 'Pertes et casses', 'Valorisation comptable'),
            ]),
            tbaCarte('Ce que vous faites ici — vos parcours', const ParcoursSigh(_parcours)),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte(
                'Derniers mouvements',
                tbaMiniTableau([
                  ColonneMini('Date', (m) => tbaDate(m['date'])),
                  ColonneMini('Produit', (m) => '${m['produit'] ?? ''}'),
                  ColonneMini('Type', (m) => '${m['typeLabel'] ?? ''}', rendu: (m) {
                    final t = typesMouvement.where((x) => x.id == m['type']).firstOrNull;
                    return BadgeSigh('${m['typeLabel'] ?? ''}', ton: tbaTon(t?.badge ?? 'neutral'));
                  }),
                  ColonneMini('Quantité', (m) => '${m['quantite'] ?? ''}', droite: true),
                  ColonneMini('Justificatif', (m) => '${m['justificatif'] ?? ''}'),
                  ColonneMini('Opérateur', (m) => '${m['utilisateur'] ?? ''}'),
                ], d.derniers),
                actions: [tbaLien(c, 'm6-mouvements', 'Registre complet', 'arrow-right')],
                sansRemplissage: true),
            tbaDeuxCartes(
              CarteSigh(
                  titre: 'Valeur du stock par catégorie',
                  child: GraphiqueBarres(
                      horizontal: true,
                      hauteur: 300,
                      etiquettes: d.valeurParCategorie.etiquettes,
                      series: [SerieGraphique('Valeur (FCFA)', d.valeurParCategorie.series.first.donnees)])),
              CarteSigh(
                  titre: 'Répartition des mouvements',
                  child: GraphiqueAnneau(etiquettes: d.repartitionMouvements.etiquettes, valeurs: d.repartitionMouvements.series.first.donnees)),
            ),
          ],
        );
      },
    );
  }
}

const _parcours = [
  ParcoursTba('Faire le point du jour', 'coins', 'Point des ventes', 'Le geste quotidien : ce qui a été vendu, par qui, à qui.', [
    EtapeTba('Point journalier des ventes',
        ecran: 'm6-point-ventes', detail: 'Détail par client, par article, par groupe. Six périodicités et une plage libre.'),
    EtapeTba('Imprimer le point détaillé ou global',
        ecran: 'm6-point-ventes', detail: 'Les états portent les trois parts : assureur, personnel pris en charge, remises.'),
    EtapeTba('Point du stock valorisé',
        ecran: 'm6-point-stock', detail: 'Restant, reçu, entré, sorti — au magasin et à la pharmacie, avec leur montant.'),
    EtapeTba('Remettre à la Direction', poste: 'DAF'),
  ]),
  ParcoursTba('Réapprovisionner', 'package-x', 'Voir les alertes', 'Un article est passé sous son seuil.', [
    EtapeTba('Lire les alertes de rupture',
        ecran: 'm6-alertes', detail: 'Une sortie qui fait passer sous le seuil ouvre la tâche AU MOMENT où elle a lieu.'),
    EtapeTba('Établir le bon d’expression de besoins',
        ecran: 'm7-besoins', detail: 'Quantité demandée et quantité accordée sont deux colonnes distinctes.'),
    EtapeTba('Faire valider par la Direction', poste: 'DAF', detail: 'RG-04.'),
    EtapeTba('Passer commande', ecran: 'm7-commandes'),
    EtapeTba('Réceptionner et mettre à jour le CUMP', ecran: 'm7-receptions'),
  ]),
  ParcoursTba('Transférer vers la pharmacie', 'arrow-left-right', 'Nouveau transfert', 'Le magasin approvisionne le détail.', [
    EtapeTba('Composer le bon multi-articles', ecran: 'm6-transferts', detail: 'Un seul bon pour tout le voyage — pas un bon par référence.'),
    EtapeTba('Le stock de détail est crédité', ecran: 'm6-produits'),
    EtapeTba('La pharmacie délivre', poste: 'Caisse'),
  ]),
  ParcoursTba('Surveiller les péremptions', 'calendar-x', 'FEFO', 'Premier périmé, premier sorti.', [
    EtapeTba('Contrôler les lots proches de péremption', ecran: 'm6-lots', detail: 'RG-05.'),
    EtapeTba('Déclarer les pertes constatées',
        ecran: 'm6-pertes', detail: 'Une perte s’enregistre comme un mouvement : elle n’existe qu’une fois.'),
  ]),
  ParcoursTba('Inventaire', 'clipboard-list', 'Inventorier', 'Comptage périodique.', [
    EtapeTba('Saisir le comptage', ecran: 'm6-inventaire'),
    EtapeTba('Expliquer les écarts', ecran: 'm6-inventaire'),
    EtapeTba('La Direction valide', poste: 'DAF'),
  ]),
];
