import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'stock_commun.dart';
import 'stock_crud.dart';

/// `m6-produits` — « Référentiel produits » : le catalogue de tous les articles gérés. Création et modification en modale (RG-02 : un médicament se
/// vend au prix d'achat, sans marge ; RG-03 : le stock ne devient jamais négatif), archivage annulable (RG-14), fiche en tiroir (fiche, lots FEFO,
/// mouvements), fiche article imprimable. Lecture seule sans le droit d'écrire.
class EcranProduitsStock extends StatelessWidget with EcranMaquette {
  const EcranProduitsStock({super.key});

  @override
  String get titre => 'Référentiel produits';

  @override
  String get description =>
      'Catalogue de tous les articles gérés : médicaments, réactifs, consommables, fournitures, entretien, petit matériel et immobilisations.';

  @override
  String get regle =>
      'RG-02 — le prix de vente des médicaments est égal au prix d’achat : aucune marge bénéficiaire n’est appliquée, sauf exception validée et tracée par la Direction.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      // la fiche d'un produit lit aussi ses lots et ses mouvements
      listenable: Listenable.merge(
          [c.magasin.collection('lots'), c.magasin.collection('mouvements')]),
      builder: (context, _) => CrudStock(
        collection: c.magasin.collection('produits'),
        entite: 'produit',
        entiteP: 'produits',
        prefixeId: 'PRD',
        triInitial: 'designation',
        referenceToast: (p) => '${p['code'] ?? ''}',
        colonnes: [
          colCode(),
          colDesignation(),
          const ColonneTableau(cle: 'unite', libelle: 'Unité'),
          colMontant('prixAchat', 'Prix d’achat'),
          colMontant('cump', 'CUMP'),
          colStock('stockGros', 'Stock gros'),
          colStock('stockDetail', 'Stock détail'),
          colStock('stock', 'Total'),
          colSeuil(),
          ColonneTableau(
              cle: 'valeur',
              libelle: 'Valeur',
              droite: true,
              valeur: (p) => qte(p['stock']) * qte(p['cump']),
              texte: (p) => mnt(qte(p['stock']) * qte(p['cump'])),
              rendu: (_, p) =>
                  cellule(mnt(qte(p['stock']) * qte(p['cump'])), droite: true)),
          colEtat(),
        ],
        filtres: [
          FiltreTableau(
              nom: 'categorie',
              libelle: 'Catégorie',
              options: optionsCategories()),
          FiltreTableau(
              nom: 'etat',
              libelle: 'État du stock',
              options: const [
                OptionChamp('rupture', 'En rupture'),
                OptionChamp('critique', 'Sous le seuil'),
                OptionChamp('normal', 'Normal'),
              ],
              correspond: (p, v) =>
                  etatStock(p['stock'], p['seuilAlerte']) == v),
        ],
        kpis: (ctx, rows) => [
          KpiSigh(
              libelle: 'Références',
              valeur: nombre(rows.length),
              icone: LucideIcons.package),
          KpiSigh(
              libelle: 'Valeur du stock',
              valeur: money(valeurStock(rows)),
              icone: LucideIcons.wallet,
              ton: TonSigh.info),
          KpiSigh(
              libelle: 'Sous le seuil',
              valeur: nombre(rows
                  .where(
                      (p) => sousSeuilHorsRupture(p['stock'], p['seuilAlerte']))
                  .length),
              icone: LucideIcons.trendingDown,
              ton: TonSigh.attention),
          KpiSigh(
              libelle: 'En rupture',
              valeur: nombre(rows.where((p) => qte(p['stock']) == 0).length),
              icone: LucideIcons.circleX,
              ton: TonSigh.danger),
        ],
        champs: (m) => [
          const ChampDef.section('Identification'),
          const ChampDef(nom: 'code', libelle: 'Code article', requis: true),
          const ChampDef(
              nom: 'designation',
              libelle: 'Désignation',
              requis: true,
              col: ColChamp.plein),
          ChampDef(
              nom: 'categorie',
              libelle: 'Catégorie',
              type: TypeChamp.select,
              requis: true,
              options: optionsCategories()),
          const ChampDef(
              nom: 'unite',
              libelle: 'Unité',
              requis: true,
              indicatif: 'Comprimé, Flacon, Boîte…'),
          const ChampDef.section('Tarification'),
          const ChampDef(
              nom: 'prixAchat',
              libelle: 'Prix d’achat (FCFA)',
              type: TypeChamp.nombre,
              requis: true,
              aide:
                  'RG-02 — sert également de prix de vente pour les médicaments.'),
          const ChampDef(
              nom: 'prixVente',
              libelle: 'Prix de vente (FCFA)',
              type: TypeChamp.nombre),
          const ChampDef(
              nom: 'cump',
              libelle: 'CUMP (FCFA)',
              type: TypeChamp.nombre,
              aide: 'Calculé automatiquement à chaque entrée en stock.'),
          const ChampDef.section('Stock et rangement'),
          const ChampDef(
              nom: 'stockGros', libelle: 'Stock gros', type: TypeChamp.nombre),
          const ChampDef(
              nom: 'stockDetail',
              libelle: 'Stock détail',
              type: TypeChamp.nombre),
          const ChampDef(
              nom: 'seuilAlerte',
              libelle: 'Seuil d’alerte',
              type: TypeChamp.nombre,
              requis: true),
          const ChampDef(
              nom: 'emplacement',
              libelle: 'Emplacement (rayon / casier)',
              col: ColChamp.plein),
          ChampDef(
              nom: 'fournisseur',
              libelle: 'Fournisseur habituel',
              type: TypeChamp.select,
              options: [
                for (final f in m.collection('fournisseurs').actives)
                  OptionChamp('${f['code']}', '${f['nom']}')
              ]),
        ],
        valeursInitiales: () => {
          'categorie': 'medicament',
          'stockGros': '0',
          'stockDetail': '0',
          'seuilAlerte': '10',
          'unite': 'Unité'
        },
        transformer: (_, v) => transformerProduit(v),
        refuser: refuserProduit,
        detail: detailProduit,
        titreDetail: (p) => '${p['designation']}',
        sousTitreDetail: (p) => '${p['code']}',
        etat: imprimerFicheArticle,
      ),
    );
  }
}
