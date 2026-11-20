import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../kit/validation_poste.dart';
import '../../shell/contexte_ecran.dart';
import '../cfg/tarifs_ecran.dart';
import 'stock_commun.dart';
import 'stock_crud.dart';
import 'stock_prix_achat.dart';

/// `m6-produits` — « Référentiel produits » : le catalogue de tous les articles gérés. Création et modification en modale (RG-02 : un médicament se
/// vend au prix d'achat, sans marge ; RG-03 : le stock ne devient jamais négatif), archivage annulable (RG-14), fiche en tiroir (fiche, lots FEFO,
/// mouvements), fiche article imprimable. Lecture seule sans le droit d'écrire.
///
/// LOT TFIN-2 : le prix d'achat est VERSIONNÉ. À la création il pose la version 1 (`TarifsPoste.creerPrixProduit`) ; à la modification il se LIT (la fiche ne le reçoit plus de ce formulaire) et se change
/// par « Changer le prix d'achat » (date d'effet, motif, Oui ou Non), commande ABSENTE sans le droit d'écrire. La colonne lit la version en vigueur AUJOURD'HUI, jamais la fiche ; un article sans prix en
/// vigueur est « à valoriser » (filtre dédié) et ne se facture pas.
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
    // La valorisation d'une référence SAGE (surcouche `valorisationsSage`) se valide ICI, au produit qu'elle concerne.
    Fiche? valorisationDe(Object? code) => c.magasin
        .collection('valorisationsSage')
        .actives
        .where((v) => v['code'] == code)
        .firstOrNull;
    final vp = ValidationPoste(c);
    return ListenableBuilder(
      // la fiche d'un produit lit aussi ses lots et ses mouvements
      listenable: Listenable.merge([
        c.magasin.collection('lots'),
        c.magasin.collection('mouvements'),
        c.magasin.collection('valorisationsSage'),
        c.magasin.collection('tarifs'),
        c.magasin.collection('versionsTarif'),
      ]),
      builder: (context, _) => CrudStock(
        collection: c.magasin.collection('produits'),
        // Modifier le prix d'achat ou le CUMP d'une référence valorisée la remet à valider.
        validation: ValidationCrud('valorisation_sage',
            cible: (p) => valorisationDe(p['code'])?['id'],
            siChange: (avant, apres) =>
                avant['prixAchat'] != apres['prixAchat'] ||
                avant['cump'] != apres['cump']),
        entite: 'produit',
        entiteP: 'produits',
        prefixeId: 'PRD',
        triInitial: 'designation',
        referenceToast: (p) => '${p['code'] ?? ''}',
        colonnes: [
          colCode(),
          colDesignation(),
          const ColonneTableau(cle: 'unite', libelle: 'Unité'),
          // Le prix d'achat EN VIGUEUR aujourd'hui (la version), jamais la fiche ; absent = « à valoriser », jamais zéro.
          ColonneTableau(
              cle: 'prixAchat',
              libelle: 'Prix d’achat',
              droite: true,
              texte: (p) =>
                  aValoriser(c, p) ? 'à valoriser' : mnt(achatDuJour(c, p)),
              valeur: (p) =>
                  aValoriser(c, p) ? null : nombreOuZero(achatDuJour(c, p)),
              rendu: (_, p) => aValoriser(c, p)
                  ? const Tooltip(
                      message:
                          'Prix d’achat non renseigné : l’article ne se facture pas.',
                      child: BadgeSigh('à valoriser', ton: TonSigh.attention))
                  : cellule(mnt(achatDuJour(c, p)), droite: true)),
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
          ColonneTableau(
              cle: 'valorisation',
              libelle: 'Valorisation',
              triable: false,
              texte: (p) {
                final v = valorisationDe(p['code']);
                return v == null
                    ? ''
                    : (v['aValider'] == true ? 'à valider' : 'validée');
              },
              rendu: (_, p) {
                final v = valorisationDe(p['code']);
                final b =
                    v == null ? null : vp.badge('valorisation_sage', v['id']);
                return b ??
                    Text('sans objet',
                        style: TextStyle(
                            fontSize: 12,
                            height: 16 / 12,
                            color: JetonsShell.slate300));
              }),
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
          // LA LISTE « À VALORISER » : les articles repris avec leur stock mais sans prix d'achat en vigueur.
          FiltreTableau(
              nom: 'valoriser',
              libelle: 'À valoriser',
              options: const [
                OptionChamp('oui', 'À valoriser (prix d’achat non renseigné)')
              ],
              correspond: (p, v) => aValoriser(c, p)),
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
        champs: (m) => _champs(m, false),
        champsPour: (m, f) => _champs(m, f != null),
        valeursInitiales: () => {
          'categorie': 'medicament',
          'stockGros': '0',
          'stockDetail': '0',
          'seuilAlerte': '10',
          'unite': 'Unité'
        },
        transformer: (_, v) => transformerProduit(v),
        // À la MODIFICATION la fiche ne reçoit NI prix d'achat NI prix de vente de ce formulaire (ils se proposent : version ajoutée, jamais réécriture). Le calcul du CUMP part du prix tenu.
        transformerExistante: (_, v, existante) {
          if (existante == null) return transformerProduit(v);
          final f = {
            ...transformerProduit({
              ...v,
              'prixAchat': existante['prixAchat'],
              'prixVente': existante['prixVente']
            })
          };
          f.remove('prixAchat');
          f.remove('prixVente');
          return f;
        },
        refuserExistante: (v, existante) =>
            existante == null ? _refuserCreation(v) : refuserProduit(v),
        // La version 1 du prix d'achat naît AVEC la fiche, par la MÊME voie que tout changement de prix.
        apresCreation: (ctx, fiche) {
          final r = tarifsDeEcran(c).creerPrixProduit(fiche,
              source: 'Saisi à l’écran « Référentiel produits »');
          if (!r.ok) {
            return 'attention, le prix d’achat n’a pas pu être versionné (${r.refus!.motif})';
          }
          return null;
        },
        // Deux gestes de ligne : l'HISTORIQUE (une lecture) et le CHANGEMENT du prix d'achat (une écriture, ABSENTE sans le droit de modifier l'écran).
        actionsLigneSup: (context, p) => [
          BoutonIcone(
              icone: LucideIcons.history,
              libelle: 'Historique de prix',
              onPressed: () => modaleHistoriquePrixAchat(context, c, p)),
          if (c.droit.editer)
            BoutonIcone(
                icone: LucideIcons.banknote,
                libelle: 'Changer le prix d’achat',
                onPressed: () => modaleChangerPrixAchat(context, c, p)),
        ],
        detail: detailProduit,
        titreDetail: (p) => '${p['designation']}',
        sousTitreDetail: (p) => '${p['code']}',
        etat: imprimerFicheArticle,
      ),
    );
  }
}

/// Les champs du formulaire : à la création le prix d'achat se saisit (il pose la version 1) ; à la MODIFICATION il est absent (il se propose par « Changer le prix d'achat »).
List<ChampDef> _champs(Magasin m, bool edition) => [
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
      ChampDef.section(edition
          ? 'Tarification : le prix d’achat se change par « Changer le prix d’achat »'
          : 'Tarification'),
      // Lot TFIN-2 : à la MODIFICATION le prix d'achat et le prix de vente ne se saisissent plus ici (la fiche ne les reçoit pas) : ils se PROPOSENT, datés, motivés, soumis au Oui ou au Non.
      if (!edition) ...[
        const ChampDef(
            nom: 'prixAchat',
            libelle: 'Prix d’achat (FCFA)',
            type: TypeChamp.nombre,
            requis: true,
            aide:
                'Obligatoire, strictement positif. RG-02 : sert également de prix de vente pour les médicaments. Un article sans prix d’achat ne se crée pas.'),
        const ChampDef(
            nom: 'prixVente',
            libelle: 'Prix de vente (FCFA)',
            type: TypeChamp.nombre,
            aide: 'Hors médicament seulement. Vide : égal au prix d’achat.'),
      ],
      const ChampDef(
          nom: 'cump',
          libelle: 'CUMP (FCFA)',
          type: TypeChamp.nombre,
          aide: 'Calculé automatiquement à chaque entrée en stock.'),
      const ChampDef.section('Stock et rangement'),
      const ChampDef(
          nom: 'stockGros', libelle: 'Stock gros', type: TypeChamp.nombre),
      const ChampDef(
          nom: 'stockDetail', libelle: 'Stock détail', type: TypeChamp.nombre),
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
    ];

/// À la CRÉATION : le prix d'achat est obligatoire (absent, tiret ou nul : refus NOMMÉ, `PRIX_ACHAT_ABSENT`) et RG-02 s'écrit (un médicament avec un prix de vente différent est refusé en le nommant). Un
/// refus de stock négatif (RG-03) passe avant, comme au registre.
String? _refuserCreation(Map<String, Object?> v) {
  final stock = refuserProduit(v);
  if (stock != null) return stock;
  num? n(Object? x) => x == null || '$x'.trim().isEmpty ? null : num.tryParse('$x'.trim());
  final achat = n(v['prixAchat']), vente = n(v['prixVente']);
  if (achat == null || achat <= 0) {
    final r = tarRefusPrixAchatAbsent(v['code'], v['designation']);
    return '${r.code} : ${r.motif}. ${r.geste}';
  }
  if (v['categorie'] == tarCategorieSansMarge && vente != null && vente != achat) {
    return 'RG-02 : un médicament se facture au prix d’achat, sans marge : son prix de vente (${nombre(vente)}) ne peut pas différer de son prix d’achat (${nombre(achat)}). Laisser le prix de vente vide.';
  }
  return null;
}
