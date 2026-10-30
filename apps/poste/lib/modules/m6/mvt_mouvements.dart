import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mvt_commun.dart';

/// `m6-mouvements` — « Mouvements de stock » : le registre chronologique de tous les mouvements (entrées, sorties, transferts, pertes, casses,
/// péremptions, régularisations). C'est le `K.crud` de la maquette : KPI, onglets « Tous les mouvements » / « Archivés », tableau trié/filtré,
/// création et modification en modale, archivage ANNULABLE (RG-14), fiche en tiroir.
///
/// RG-03 : une sortie (sens négatif) ne dépasse jamais le stock concerné, à la création comme à la modification — le refus dit le disponible.
/// Les règles sont dans `packages/domaine` (`controleMouvement`, `preparerMouvement`), rejouées sur des vecteurs de l'écran réel.
///
/// Écart assumé, signalé (docs/architecture/ECARTS-MAQUETTE.md, E20) : un mouvement SAISI ici s'écrit au registre mais ne modifie PAS le stock du
/// produit, comme dans la maquette — le stock bouge aux écrans de transfert, de dispensation, de pertes et d'inventaire, qui écrivent leurs mouvements.
class EcranMouvements extends StatelessWidget with EcranMaquette {
  const EcranMouvements({super.key});

  @override
  String get titre => 'Mouvements de stock';

  @override
  String get description =>
      'Registre chronologique de tous les mouvements : entrées, sorties, transferts, pertes, casses, péremptions et régularisations.';

  @override
  String get regle =>
      'RG-03 — chaque mouvement de sortie est rattaché à un justificatif (facture, bon de transfert, constat de perte ou retour de péremption).';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('mouvements');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final actives = col.actives;
        num somme(bool Function(Fiche) f) => actives.where(f).fold<num>(0, (a, r) => a + n(r['quantite']));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!c.droit.editer && c.droit.voir)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: NoteSigh(
                    'Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
                    ton: TonSigh.attention)),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Mouvements enregistrés', valeur: nombre(actives.length), icone: LucideIcons.arrowLeftRight),
            KpiSigh(libelle: 'Entrées', valeur: nombre(somme((r) => r['type'] == 'entree')), icone: LucideIcons.arrowDownLeft, ton: TonSigh.succes),
            KpiSigh(libelle: 'Sorties', valeur: nombre(somme((r) => r['type'] == 'sortie')), icone: LucideIcons.arrowUpRight, ton: TonSigh.info),
            KpiSigh(
                libelle: 'Pertes et casses',
                valeur: nombre(somme((r) => const ['perte', 'casse', 'peremption'].contains(r['type']))),
                icone: LucideIcons.trash2,
                ton: TonSigh.danger),
          ]),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(id: 'liste', libelle: 'Tous les mouvements', compte: actives.length, construire: (ctx) => _tableau(ctx, c, archive: false)),
            OngletDef(id: 'archives', libelle: 'Archivés', compte: col.archivees.length, construire: (ctx) => _tableau(ctx, c, archive: true)),
          ]),
        ]);
      },
    );
  }

  List<ColonneTableau> _colonnes() => [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, texte: (r) => '${r['reference']}', rendu: (_, r) => reference(r['reference'])),
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => dateDe(r['date'])),
        const ColonneTableau(cle: 'produit', libelle: 'Produit'),
        ColonneTableau(
            cle: 'type',
            libelle: 'Type',
            texte: (r) => _libelleType(r),
            rendu: (_, r) => BadgeSigh(_libelleType(r), ton: tonDe(typeMouvement(r['type'])?.ton))),
        ColonneTableau(
            cle: 'quantite',
            libelle: 'Quantité',
            droite: true,
            texte: (r) => '${_signe(r)}${nombre(r['quantite'])}',
            rendu: (_, r) {
              final s = typeMouvement(r['type'])?.sens ?? 0;
              return Text('${_signe(r)}${nombre(r['quantite'])}',
                  style: TextStyle(
                      color: s > 0 ? JetonsShell.success600 : (s < 0 ? JetonsShell.danger600 : JetonsShell.slate600),
                      fontSize: 14,
                      fontWeight: s != 0 ? FontWeight.w600 : null));
            }),
        ColonneTableau(
            cle: 'stockType',
            libelle: 'Stock',
            texte: (r) => stockLabel(r['stockType']),
            rendu: (_, r) => BadgeSigh(stockLabel(r['stockType']).split(' (').first)),
        const ColonneTableau(cle: 'justificatif', libelle: 'Justificatif (RG-03)'),
        const ColonneTableau(cle: 'utilisateur', libelle: 'Opérateur'),
      ];

  static String _libelleType(Fiche r) => '${r['typeLabel'] ?? typeMouvement(r['type'])?.libelle ?? r['type']}';
  static String _signe(Fiche r) {
    final s = typeMouvement(r['type'])?.sens ?? 0;
    return s > 0 ? '+' : (s < 0 ? '−' : '');
  }

  Widget _tableau(BuildContext ctx, ContexteEcran c, {required bool archive}) {
    final col = c.magasin.collection('mouvements');
    return TableauSigh(
      colonnes: _colonnes(),
      lignes: archive ? col.archivees : col.actives,
      taillePage: 15,
      triInitial: 'date',
      sensInitial: 'desc',
      selectionnable: !archive,
      nomExport: 'mouvements',
      libelleRecherche: 'Rechercher un mouvement…',
      messageVide: archive ? 'Aucun enregistrement archivé.' : 'Aucun mouvement enregistré.',
      indiceVide: archive ? null : 'Utiliser le bouton « Nouveau » pour créer le premier enregistrement.',
      filtres: [
        FiltreTableau(nom: 'type', libelle: 'Type', options: [for (final t in typesMouvement) OptionChamp(t.id, t.libelle)]),
        FiltreTableau(nom: 'stockType', libelle: 'Stock', options: [for (final s in typesStock) OptionChamp(s.$1, s.$2)]),
      ],
      alClicLigne: (r) => _detail(ctx, c, r),
      actions: [
        if (!archive && c.droit.editer)
          BoutonSigh(libelle: 'Nouveau', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _formulaire(ctx, c, null)),
      ],
      actionsGroupe: archive
          ? null
          : (context, sel, effacer) => [
                BoutonSigh(
                    libelle: 'Imprimer la sélection',
                    icone: LucideIcons.printer,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => afficherApercu(ctx, _pieceSelection(c, sel))),
                if (c.droit.annuler)
                  BoutonSigh(
                      libelle: 'Archiver',
                      icone: LucideIcons.archive,
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.danger,
                      onPressed: () async {
                        final ok = await confirmerSigh(ctx,
                            titre: 'Archiver ${sel.length} enregistrement(s) ?',
                            message: 'Archivage logique : les données restent consultables et l’opération est annulable.',
                            libelleOk: 'Archiver',
                            dangereux: true);
                        if (!ok || !ctx.mounted) return;
                        final undos = [for (final r in sel) col.archiver(r['id'])];
                        effacer();
                        annonce(ctx, '${sel.length} enregistrement(s) archivé(s).', annuler: () {
                          for (final u in undos) {
                            u();
                          }
                        });
                      }),
              ],
      actionsLigne: (context, r) => archive
          ? [
              if (c.droit.annuler)
                BoutonIcone(
                    icone: LucideIcons.archiveRestore,
                    libelle: 'Restaurer',
                    onPressed: () {
                      col.restaurer(r['id']);
                      annonce(ctx, 'Enregistrement restauré.');
                    }),
            ]
          : [
              BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _detail(ctx, c, r)),
              if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _formulaire(ctx, c, r)),
              if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(ctx, c, r)),
            ],
    );
  }

  PieceA4 _pieceSelection(ContexteEcran c, List<Fiche> sel) => PieceA4(
        titre: 'Sélection — mouvements',
        sousTitre: '${sel.length} enregistrement(s)',
        reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        tableaux: [
          TableauEtat(colonnes: [
            for (final col in _colonnes())
              ColonneEtat(libelle: col.libelle, valeur: (r) => col.enTexte(r), droite: col.droite),
          ], lignes: sel)
        ],
      );

  Future<void> _archiver(BuildContext ctx, ContexteEcran c, Fiche r) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Archiver cet enregistrement ?',
        message: 'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable dans l’onglet « Archivés ». L’opération est journalisée et peut être annulée.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final undo = c.magasin.collection('mouvements').archiver(r['id']);
    annonce(ctx, 'Enregistrement archivé.', annuler: undo, messageAnnulation: 'Archivage annulé.');
  }

  void _detail(BuildContext ctx, ContexteEcran c, Fiche r) {
    final p = c.magasin.collection('produits').actives.where((x) => x['id'] == r['produitId']).firstOrNull;
    afficherTiroir<void>(ctx,
        titre: '${r['reference']}',
        sousTitre: '${r['reference']}',
        largeurMax: 672,
        corps: DescListeSigh([
          ('N°', reference(r['reference'])),
          ('Date', dateDe(r['date'])),
          ('Produit', r['produit']),
          ('Type', BadgeSigh(_libelleType(r), ton: tonDe(typeMouvement(r['type'])?.ton))),
          ('Quantité', '${_signe(r)}${nombre(r['quantite'])}'),
          ('Stock', BadgeSigh(stockLabel(r['stockType']).split(' (').first)),
          ('Justificatif (RG-03)', r['justificatif']),
          ('Opérateur', r['utilisateur']),
          if (p != null) ('Produit', '${p['designation']} (stock : ${p['stock']})'),
        ]),
        pied: (fermer) => [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Modifier',
                    icone: LucideIcons.pencil,
                    onPressed: () {
                      fermer();
                      _formulaire(ctx, c, r);
                    }),
              if (c.droit.annuler)
                BoutonSigh(
                    libelle: 'Archiver',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () {
                      fermer();
                      _archiver(ctx, c, r);
                    }),
            ]);
  }

  // --------------------------------------------------------------------------
  // Création / modification
  // --------------------------------------------------------------------------
  void _formulaire(BuildContext ctx, ContexteEcran c, Fiche? existant) {
    final col = c.magasin.collection('mouvements');
    final produits = trierPar(c.magasin.collection('produits').actives, (p) => p['designation']);
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'produitId',
          libelle: 'Produit',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [for (final p in produits) OptionChamp('${p['id']}', '${p['designation']} (stock : ${p['stock']})')]),
      ChampDef(nom: 'type', libelle: 'Type de mouvement', type: TypeChamp.select, requis: true, options: [for (final t in typesMouvement) OptionChamp(t.id, t.libelle)]),
      ChampDef(nom: 'quantite', libelle: 'Quantité', type: TypeChamp.nombre, requis: true, valider: (v, _) => n(v) < 1 ? 'La valeur minimale est 1.' : null),
      const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
      ChampDef(nom: 'stockType', libelle: 'Stock concerné', type: TypeChamp.select, requis: true, options: [for (final s in typesStock) OptionChamp(s.$1, s.$2)]),
      const ChampDef(nom: 'justificatif', libelle: 'Justificatif', requis: true, col: ColChamp.plein, aide: 'RG-03 — obligatoire pour toute sortie de stock.'),
    ], {
      if (existant == null)
        ...{'date': iso(c.aujourdhui), 'type': 'entree', 'stockType': 'gros'}
      else
        for (final k in ['produitId', 'type', 'date', 'stockType', 'justificatif']) k: existant[k],
      if (existant != null) 'quantite': '${existant['quantite'] is num && (existant['quantite'] as num) == (existant['quantite'] as num).truncate() ? (existant['quantite'] as num).toInt() : existant['quantite']}',
    });
    afficherModale<void>(ctx,
        titre: existant != null ? 'Modifier l’enregistrement' : 'Nouveau mouvement',
        sousTitre: existant != null ? '${existant['reference']}' : 'Les champs marqués d’un astérisque sont obligatoires.',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: existant != null ? 'Enregistrer' : 'Créer',
                  icone: existant != null ? LucideIcons.save : LucideIcons.plus,
                  onPressed: () {
                    final saisie = f.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final valeurs = {...saisie, 'quantite': n(saisie['quantite'])};
                    final produit = c.magasin.collection('produits').actives.where((p) => p['id'] == valeurs['produitId']).firstOrNull;
                    // RG-03 à l'enregistrement : une sortie ne dépasse pas le stock CONCERNÉ.
                    final refus = controleMouvement(produit: produit, type: valeurs['type'], stockType: valeurs['stockType'], quantite: valeurs['quantite']);
                    if (refus != null) {
                      ToastsSigh.afficher(ctx, refus, type: TypeToast.erreur);
                      return;
                    }
                    final prepare = preparerMouvement(valeurs,
                        existant: existant, produits: c.magasin.collection('produits').actives, mouvements: col.toutes, utilisateur: c.utilisateur);
                    fermer();
                    if (existant != null) {
                      final undo = col.mettreAJour(existant['id'], prepare);
                      annonce(ctx, 'Modifications enregistrées.', detail: '${existant['reference']}', annuler: undo);
                    } else {
                      final r = col.inserer(prepare, prefixe: 'MVT');
                      annonce(ctx, 'Nouveau mouvement créé.', detail: '${r.fiche['reference']}', annuler: r.annuler);
                    }
                  }),
            ]);
  }
}
