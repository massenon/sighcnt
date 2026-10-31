import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/stock/emplacements.dart' as emp show etatStock;

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'flux_commun.dart';

/// `m6-etiquetage` — « Étiquetage & emplacements ». Un casier est un RÉFÉRENTIEL (collection `emplacements`) ; l'emplacement d'un produit est le CODE du casier, porté par la
/// fiche produit. Le rangement suit le principe FEFO : à l'intérieur de chaque casier, les lots sont classés par date de péremption croissante.
///
/// Corrigé dans la maquette avant le portage (E48) : la carte des articles SANS emplacement s'intitulait « undefined ». Porté fidèlement (E47) : l'archivage « avec motif »
/// accepte un motif vide. Étiquettes : la maquette les dispose en grille de cadres sur la feuille ; ici, une étiquette par bloc de texte de la pièce A4 (mêmes lignes, même
/// ordre, mêmes valeurs) — la pièce commune ne porte pas de grille de cadres.
class EcranEtiquetage extends StatelessWidget with EcranMaquette {
  const EcranEtiquetage({super.key});

  @override
  String get titre => 'Étiquetage & emplacements';

  @override
  String get description =>
      'Organisation des rayons et casiers, classement par date de péremption et édition des étiquettes produits.';

  static List<ChampDef> champsEmplacement(Fiche? _) => [
        const ChampDef(
            nom: 'code',
            libelle: 'Code du casier',
            requis: true,
            aide: 'Court et stable — c’est lui qui figure sur l’étiquette.'),
        const ChampDef(nom: 'libelle', libelle: 'Intitulé', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'zone', libelle: 'Zone', type: TypeChamp.select, requis: true, options: [
          for (final z in zonesEmplacement) OptionChamp(z)
        ]),
        ChampDef(nom: 'temperature', libelle: 'Température de conservation', type: TypeChamp.select, options: [
          for (final t in temperaturesConservation) OptionChamp(t)
        ]),
        const ChampDef(nom: 'capacite', libelle: 'Capacité (références)', type: TypeChamp.nombre),
        const ChampDef(
            nom: 'observation',
            libelle: 'Observation',
            type: TypeChamp.textarea,
            lignes: 2,
            col: ColChamp.plein),
      ];

  static List<ChampDef> champsProduit(Fiche? _) => const [
        ChampDef(nom: 'designation', libelle: 'Désignation', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'emplacement', libelle: 'Emplacement (rayon / casier)', requis: true),
        ChampDef(nom: 'unite', libelle: 'Unité'),
        ChampDef(nom: 'seuilAlerte', libelle: 'Seuil d’alerte', type: TypeChamp.nombre),
      ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final mag = c.magasin;
    return ListenableBuilder(
      listenable: Listenable.merge([
        mag.collection('emplacements'),
        mag.collection('produits'),
        mag.collection('lots'),
      ]),
      builder: (context, _) {
        final emplacements = mag.collection('emplacements').actives;
        final produits = mag.collection('produits').actives;
        final lots = mag.collection('lots').actives;
        final k = kpisEtiquetage(emplacements: emplacements, produits: produits, lots: lots);
        final ref = ReferentielSage.instance;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TableauSigh(
            titre: 'Référentiel des emplacements',
            lignes: [
              for (final e in emplacements) {...e, 'articles': articlesRanges(e['code'], produits)}
            ],
            nomExport: 'emplacements',
            taillePage: 15,
            triInitial: 'code',
            messageVide: 'Aucun emplacement défini.',
            filtres: [
              FiltreTableau(
                  nom: 'zone',
                  libelle: 'Zone',
                  options: [for (final z in zonesEmplacement) OptionChamp(z)])
            ],
            actions: [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Nouvel emplacement',
                    icone: LucideIcons.plus,
                    taille: TailleBouton.sm,
                    onPressed: () => _creer(context, c)),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'code',
                  libelle: 'Casier',
                  sansCoupure: true,
                  texte: (e) => '${e['code']}',
                  rendu: (_, e) => Text('${e['code']}',
                      style: const TextStyle(
                          fontFamily: 'LiberationMono',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: JetonsShell.navy800))),
              const ColonneTableau(cle: 'libelle', libelle: 'Intitulé'),
              ColonneTableau(
                  cle: 'zone',
                  libelle: 'Zone',
                  texte: (e) => '${e['zone'] ?? ''}',
                  rendu: (_, e) => BadgeSigh('${e['zone'] ?? ''}',
                      ton: e['zone'] == 'Chaîne du froid' ? TonSigh.info : TonSigh.navy)),
              const ColonneTableau(cle: 'temperature', libelle: 'Conservation'),
              ColonneTableau(
                  cle: 'articles',
                  libelle: 'Articles rangés',
                  droite: true,
                  texte: (e) => occupationCasier(e['articles'] as int, e['capacite']).texte ?? 'vide',
                  rendu: (_, e) {
                    final o = occupationCasier(e['articles'] as int, e['capacite']);
                    if (o.texte == null) {
                      return const Text('vide',
                          style: TextStyle(fontSize: 12, color: JetonsShell.slate300));
                    }
                    return Text(o.texte!,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: o.plein ? FontWeight.w600 : FontWeight.w400,
                            color: o.plein ? JetonsShell.warning700 : JetonsShell.slate700));
                  }),
            ],
            actionsLigne: (ctx, e) => actionsFiche(ctx,
                collection: mag.collection('emplacements'),
                fiche: mag.collection('emplacements').parId(e['id'])!,
                champs: champsEmplacement),
          ),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Emplacements définis',
                valeur: nombre(k.emplacements),
                icone: LucideIcons.grid3x3,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Articles rangés',
                valeur: nombre(k.articlesRanges),
                icone: LucideIcons.package,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Articles sans emplacement',
                valeur: nombre(k.sansEmplacement),
                icone: LucideIcons.circleHelp,
                ton: TonSigh.attention),
            KpiSigh(
                libelle: 'Lots classés FEFO',
                valeur: nombre(k.lotsFefo),
                icone: LucideIcons.arrowUpNarrowWide,
                ton: TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(
              'Le rangement suit le principe FEFO : à l’intérieur de chaque casier, les lots sont classés par date de péremption croissante. Les sérums sont rangés par planches avec identification du type par emplacement.',
              ton: TonSigh.info),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Plan des rayons et casiers',
              child: LayoutBuilder(builder: (_, w) {
                final cols = w.maxWidth >= 1024 - 40 ? 3 : (w.maxWidth >= 640 - 40 ? 2 : 1);
                final largeur = (w.maxWidth - 12 * (cols - 1)) / cols;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final casier in planDesRayons(produits))
                    SizedBox(width: largeur, child: _carteCasier(context, casier, lots)),
                ]);
              })),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Articles par emplacement',
            lignes: [
              for (final p in produits)
                {...p, 'etat': emp.etatStock(p), 'emplacement': p['emplacement']}
            ],
            nomExport: 'emplacements',
            taillePage: 15,
            triInitial: 'emplacement',
            actions: [
              BoutonSigh(
                  libelle: 'Éditer toutes les étiquettes',
                  icone: LucideIcons.printer,
                  taille: TailleBouton.sm,
                  onPressed: () => _etiquettes(context, produits, lots, 'Tous les emplacements')),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'emplacement',
                  libelle: 'Emplacement',
                  texte: (p) => '${p['emplacement'] ?? '—'}'),
              ColonneTableau(
                  cle: 'code',
                  libelle: 'Code',
                  sansCoupure: true,
                  texte: (p) => '${p['code']}',
                  rendu: (_, p) => Text('${p['code']}',
                      style: const TextStyle(
                          fontFamily: 'LiberationMono',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JetonsShell.navy800))),
              ColonneTableau(
                  cle: 'designation',
                  libelle: 'Désignation',
                  texte: (p) => '${p['designation']} ${ref.categorieLabel(p['categorie'])} — ${p['unite']}',
                  rendu: (_, p) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${p['designation']}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    height: 20 / 14,
                                    fontWeight: FontWeight.w500,
                                    color: JetonsShell.slate800)),
                            Text('${ref.categorieLabel(p['categorie'])} — ${p['unite']}',
                                style: const TextStyle(
                                    fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
                          ])),
              const ColonneTableau(cle: 'unite', libelle: 'Unité'),
              ColonneTableau(
                  cle: 'stock',
                  libelle: 'Stock',
                  droite: true,
                  texte: (p) => nombre(p['stock']),
                  rendu: (_, p) {
                    final v = p['stock'];
                    final seuil = p['seuilAlerte'];
                    final rupture = v == 0;
                    final bas = v is num && seuil is num && v <= seuil;
                    return Text(nombre(v),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: rupture || bas ? FontWeight.w600 : FontWeight.w400,
                            color: rupture
                                ? JetonsShell.danger600
                                : (bas ? JetonsShell.warning600 : JetonsShell.slate700)));
                  }),
              ColonneTableau(
                  cle: 'etat',
                  libelle: 'État',
                  texte: (p) => '${p['etat']}',
                  rendu: (_, p) => statutBadge(p['etat'])),
            ],
            actionsLigne: (ctx, p) => actionsFiche(ctx,
                collection: mag.collection('produits'),
                fiche: mag.collection('produits').parId(p['id'])!,
                champs: champsProduit,
                archivable: false),
          ),
        ]);
      },
    );
  }

  Widget _carteCasier(BuildContext ctx, CarteCasier casier, List<Fiche> lots) {
    final produits = casier.articles;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: decorationCarte(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
              child: Text(casier.libelle,
                  style: const TextStyle(
                      fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800))),
          BadgeSigh('${produits.length} article${produits.length > 1 ? 's' : ''}', ton: TonSigh.navy),
        ]),
        const SizedBox(height: 8),
        for (final p in produits.take(6))
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(
                    child: Text('${p['designation']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate600))),
                const SizedBox(width: 8),
                Text(nombre(p['stock']),
                    style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: FontWeight.w500,
                        color: (p['stock'] is num && p['seuilAlerte'] is num && (p['stock'] as num) <= (p['seuilAlerte'] as num))
                            ? JetonsShell.danger600
                            : JetonsShell.slate700)),
              ])),
        if (produits.length > 6)
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('+ ${produits.length - 6} autre(s)',
                  style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400))),
        const SizedBox(height: 4),
        Align(
            alignment: Alignment.centerLeft,
            child: BoutonSigh(
                libelle: 'Étiquettes',
                icone: LucideIcons.tag,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () => _etiquettes(ctx, produits, lots, casier.libelle))),
      ]),
    );
  }

  /// Les étiquettes produits : code, emplacement, lot qui périme le premier (FEFO), prix unitaire.
  PieceA4 pieceEtiquettes(List<Fiche> items, List<Fiche> lots, String emplacement,
          {required String utilisateur, required DateTime edite, required String reference}) =>
      PieceA4(
        titre: 'Étiquettes produits',
        sousTitre: '$emplacement — ${items.length} étiquette(s)',
        reference: reference,
        utilisateur: utilisateur,
        edite: edite,
        lieuDate: false,
        blocs: [for (final p in items) BlocTexte(ligneEtiquette(p, lots).join('\n'))],
      );

  Future<void> _etiquettes(BuildContext ctx, List<Fiche> items, List<Fiche> lots, String emplacement) {
    final c = ContexteEcran.of(ctx);
    return afficherApercu(
        ctx,
        pieceEtiquettes(items, lots, emplacement,
            utilisateur: c.utilisateur,
            edite: c.aujourdhui,
            reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero())));
  }

  void _creer(BuildContext ctx, ContexteEcran c) {
    final col = c.magasin.collection('emplacements');
    modaleSaisie(ctx,
        titre: 'Nouvel emplacement de rangement',
        sousTitre: 'Les champs marqués d’un astérisque sont obligatoires.',
        champs: champsEmplacement(null),
        initial: const {'zone': 'Rayonnage sec', 'temperature': 'Ambiante'},
        libelleOk: 'Créer',
        icone: LucideIcons.plus,
        surValider: (v) {
          final r = col.inserer(nouvelEmplacement(v, c.aujourdhui), prefixe: 'EMP');
          ToastsSigh.afficher(ctx, 'Emplacement créé.',
              type: TypeToast.succes,
              detail: '${r.fiche['libelle']}',
              annuler: r.annuler,
              messageAnnulation: 'Création annulée — la fiche est archivée.');
          return true;
        });
  }
}
