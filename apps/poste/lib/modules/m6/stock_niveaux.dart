import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'stock_commun.dart';

/// `m6-stock-gros` et `m6-stock-detail` : la SITUATION d'un stock (magasin central, pharmacie d'urgence) — KPI, tableau des articles présents,
/// fiche en tiroir, état imprimable — et, en dessous, les MOUVEMENTS d'une période. L'état se lit À UNE DATE, le flux SUR UNE PÉRIODE : les deux
/// ne se confondent pas, et l'écran le dit dans le titre du second tableau.
///
/// Le tableau n'est pas un registre : rien n'y est créé ni archivé. Les sorties se font par transfert (gros → détail) ou par dispensation (RG-03).
class EcranNiveauStock extends StatefulWidget with EcranMaquette {
  const EcranNiveauStock.gros({super.key})
      : id = 'm6-stock-gros',
        champ = 'stockGros',
        type = 'gros',
        titreEcran = 'Stock gros (magasin central)',
        descriptionEcran =
            'Situation du magasin central : réceptions fournisseurs et approvisionnement de la pharmacie de détail.',
        note =
            'Le magasin central reçoit les livraisons fournisseurs. Les sorties s’effectuent par transfert vers le stock de détail, chaque transfert étant tracé (RG-03).';

  const EcranNiveauStock.detail({super.key})
      : id = 'm6-stock-detail',
        champ = 'stockDetail',
        type = 'detail',
        titreEcran = 'Stock détail (pharmacie d’urgence)',
        descriptionEcran =
            'Situation de la pharmacie d’urgence : dispensation aux patients et aux services de soins.',
        note =
            'La pharmacie de détail dispense aux patients et aux services. Toute sortie est rattachée à une facture ou à un bon de service (RG-03).';

  final String id;
  final String champ;
  final String type;
  final String titreEcran;
  final String descriptionEcran;
  final String note;

  @override
  String get titre => titreEcran;

  @override
  String get description => descriptionEcran;

  @override
  State<EcranNiveauStock> createState() => _EtatNiveauStock();
}

class _EtatNiveauStock extends State<EcranNiveauStock> {
  ControleurFormulaire? _periode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_periode == null) {
      final auj = ContexteEcran.of(context).aujourdhui;
      _periode = ControleurFormulaire(const [
        ChampDef(
            nom: 'du',
            libelle: 'Mouvements du',
            type: TypeChamp.date,
            col: ColChamp.tiers),
        ChampDef(
            nom: 'au',
            libelle: 'au',
            type: TypeChamp.date,
            col: ColChamp.tiers),
      ], {
        'du': iso(ajouterJours(auj, -30)),
        'au': iso(auj)
      })
        ..addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _periode?.dispose();
    super.dispose();
  }

  List<Fiche> _lignes(List<Fiche> produits) => [
        for (final p in produits)
          if (qte(p[widget.champ]) > 0 || qte(p['stock']) == 0) p
      ];

  void _imprimer(BuildContext ctx, List<Fiche> rows) {
    final c = ContexteEcran.of(ctx);
    final auj = c.aujourdhui;
    final presents = trierStable([
      for (final p in rows)
        if (qte(p[widget.champ]) > 0) p
    ], (p) => p['designation']);
    afficherApercu(
        ctx,
        PieceA4(
            titre: 'État du ${widget.titreEcran.toLowerCase()}',
            sousTitre: 'Situation au ${dateFR(auj)}',
            cartouche: [
              ('Références', nombre(presents.length)),
              ('Quantité totale', nombre(sommeChamp(rows, widget.champ))),
              ('Valeur au CUMP', money(valeurStock(rows, widget.champ))),
              ('Date d’édition', dateFR(auj)),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Code', valeur: (p) => p['code']),
                ColonneEtat(
                    libelle: 'Désignation', valeur: (p) => p['designation']),
                ColonneEtat(
                    libelle: 'Catégorie',
                    valeur: (p) => libelleCategorie(p['categorie'])),
                ColonneEtat(libelle: 'Unité', valeur: (p) => p['unite']),
                ColonneEtat(
                    libelle: 'Quantité',
                    valeur: (p) => p[widget.champ],
                    droite: true),
                ColonneEtat(
                    libelle: 'CUMP',
                    valeur: (p) => mnt(p['cump']),
                    droite: true),
                ColonneEtat(
                    libelle: 'Valeur',
                    valeur: (p) => mnt(qte(p[widget.champ]) * qte(p['cump'])),
                    droite: true,
                    somme: (p) => qte(p[widget.champ]) * qte(p['cump'])),
              ], lignes: presents)),
            ],
            signatures: const [
              Signature('Le Gestionnaire de Stock', nom: gestionnaireStock),
              Signature('La Directrice Administrative',
                  nom: directriceAdministrative),
            ],
            reference:
                PieceA4.reference_(auj, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: auj));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final cp = c.magasin.collection('produits');
    final cm = c.magasin.collection('mouvements');
    return ListenableBuilder(
      listenable: Listenable.merge([cp, cm, c.magasin.collection('lots')]),
      builder: (context, _) {
        final champ = widget.champ;
        final rows = _lignes(cp.actives);
        final mvts = mouvementsDuStock(cm.actives, widget.type,
            '${_periode!['du']}', '${_periode!['au']}');
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Références présentes',
                    valeur: nombre(rows.where((p) => qte(p[champ]) > 0).length),
                    icone: LucideIcons.package),
                KpiSigh(
                    libelle: 'Quantité totale',
                    valeur: nombre(sommeChamp(rows, champ)),
                    icone: LucideIcons.boxes,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Valeur (CUMP)',
                    valeur: money(valeurStock(rows, champ)),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Sous le seuil',
                    valeur: nombre(rows
                        .where((p) => sousSeuil(p[champ], p['seuilAlerte']))
                        .length),
                    icone: LucideIcons.trendingDown,
                    ton: TonSigh.danger),
              ]),
              const SizedBox(height: 16),
              NoteSigh(widget.note),
              const SizedBox(height: 16),
              TableauSigh(
                titre: widget.titreEcran,
                lignes: rows,
                taillePage: 15,
                triInitial: champ,
                sensInitial: 'desc',
                nomExport: widget.id,
                filtres: [
                  FiltreTableau(
                      nom: 'categorie',
                      libelle: 'Catégorie',
                      options: optionsCategories())
                ],
                colonnes: [
                  colCode(),
                  colDesignation(),
                  const ColonneTableau(cle: 'unite', libelle: 'Unité'),
                  colStock(champ, 'Quantité'),
                  colSeuil(),
                  colMontant('cump', 'CUMP'),
                  ColonneTableau(
                      cle: 'valeur',
                      libelle: 'Valeur',
                      droite: true,
                      valeur: (p) => qte(p[champ]) * qte(p['cump']),
                      texte: (p) => mnt(qte(p[champ]) * qte(p['cump'])),
                      rendu: (_, p) => cellule(
                          mnt(qte(p[champ]) * qte(p['cump'])),
                          droite: true)),
                  const ColonneTableau(
                      cle: 'emplacement', libelle: 'Emplacement'),
                  colEtat(),
                ],
                alClicLigne: (p) => afficherTiroir<void>(context,
                    titre: '${p['designation']}',
                    sousTitre: '${p['code']}',
                    largeurMax: 768,
                    corps: detailProduit(context, p)),
                actions: [
                  BoutonSigh(
                      libelle: 'Éditer l’état',
                      taille: TailleBouton.sm,
                      icone: LucideIcons.printer,
                      onPressed: () => _imprimer(context, rows)),
                ],
              ),
              const SizedBox(height: 16),
              // LES MOUVEMENTS DE LA PÉRIODE : l'état ci-dessus reste à une date, c'est le flux qui prend la plage.
              CarteSigh(child: FormulaireSigh(controleur: _periode!)),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Mouvements de la période — le flux, pas l’état',
                lignes: mvts,
                taillePage: 10,
                nomExport: '${widget.id}-mouvements',
                messageVide:
                    'Aucun mouvement de ce stock sur la période choisie. Les mouvements s’enregistrent aux écrans de transfert, dispensation et pertes (M6).',
                colonnes: [
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      texte: (m) => dateFiche(m['date']),
                      valeur: (m) => m['date']),
                  const ColonneTableau(cle: 'produit', libelle: 'Produit'),
                  ColonneTableau(
                      cle: 'typeLabel',
                      libelle: 'Nature',
                      texte: (m) => '${m['typeLabel'] ?? m['type'] ?? ''}'),
                  ColonneTableau(
                      cle: 'quantite',
                      libelle: 'Quantité',
                      droite: true,
                      texte: (m) => '${m['quantite'] ?? ''}'),
                  const ColonneTableau(
                      cle: 'justificatif', libelle: 'Justificatif (RG-03)'),
                ],
              ),
            ]);
      },
    );
  }
}
