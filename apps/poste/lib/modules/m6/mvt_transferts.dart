import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/stock/mouvements_stock.dart' as mv show typesStock, categoriesProduit, typesMouvement;

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mvt_commun.dart';

const _destinations = [
  'Pharmacie d’urgence',
  'Pharmacie externe',
  'Laboratoire',
  'Hospitalisation',
  'Maternité',
  'Bloc opératoire',
  'Salle de soins',
];

/// `m6-transferts` — « Transferts gros → détail ». Un bon porte PLUSIEURS lignes (un réapprovisionnement de pharmacie porte sur quinze à vingt
/// références : les transférer une à une produisait vingt bons là où le magasinier fait un seul voyage).
///
/// Les règles — RG-03 contrôlé ligne par ligne en NOMMANT l'article, disponible net de ce qui est déjà posé sur le bon, deux mouvements symétriques
/// par ligne, numéro `TR-NNNNN` lu sur le registre, annulation qui restitue TOUTES les lignes — vivent dans `packages/domaine`
/// (`mouvements_stock.dart`), rejouées sur des vecteurs tirés de l'écran réel de la maquette.
///
/// « Modifier » REFUSE en expliquant : le bon a déjà déplacé le stock ; le corriger laisserait les deux magasins faux sans qu'aucun mouvement ne le dise.
class EcranTransferts extends StatefulWidget with EcranMaquette {
  const EcranTransferts({super.key});

  @override
  String get titre => 'Transferts gros → détail';

  @override
  String get description =>
      'Approvisionnement de la pharmacie d’urgence depuis le magasin central, avec traçabilité complète.';

  @override
  String get regle =>
      'RG-03 — chaque transfert génère un bon numéroté et deux mouvements de stock symétriques ; le stock du magasin ne peut jamais devenir négatif.';

  @override
  State<EcranTransferts> createState() => _EtatTransferts();
}

class _EtatTransferts extends State<EcranTransferts> {
  final _cleBons = GlobalKey<TableauSighState>();
  final _cleLignes = GlobalKey<TableauSighState>();

  /// Les lignes à PLAT — une ligne par article transféré, portant le bon dont elle vient. La même donnée que le bon, lue autrement : jamais une
  /// seconde collection.
  List<Ligne> _toutesLignes(Magasin mag, List<Fiche> bons) {
    final produits = mag.collection('produits');
    return [
      for (final t in bons)
        for (final (i, l) in lignesDeBon(t).indexed)
          () {
            final pr = l['produitId'] != null ? produits.parId(l['produitId']) : null;
            final valeur = valeurLigne(l);
            return <String, Object?>{
              'id': '${t['id']}-$i',
              'bonId': t['id'],
              'reference': t['reference'],
              'date': t['date'],
              'demandeur': t['demandeur'] ?? '—',
              'operateur': t['operateur'] ?? '—',
              'code': l['code'] ?? pr?['code'] ?? '',
              'produit': l['produit'],
              'categorie': l['categorie'] ?? pr?['categorie'] ?? '',
              'unite': l['unite'] ?? '',
              'quantite': n(l['quantite']),
              'cump': n(l['cump']),
              'lot': l['lot'] ?? '',
              'peremption': l['peremption'] ?? '',
              'valeur': valeur,
            };
          }()
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('transferts');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final bons = col.actives;
        final lg = _toutesLignes(c.magasin, bons);
        final aujourdhui = c.aujourdhui;
        final duMois = bons.where((t) {
          final d = DateTime.tryParse('${t['date']}');
          return d != null && d.month == aujourdhui.month && d.year == aujourdhui.year;
        }).length;
        final destinations = ({for (final t in bons) if (t['demandeur'] != null && '${t['demandeur']}'.isNotEmpty) '${t['demandeur']}'}.toList()..sort());
        final filtreDestination = FiltreTableau(nom: 'demandeur', libelle: 'Destination', options: [for (final d in destinations) OptionChamp(d)]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Bons de transfert', valeur: nombre(bons.length), icone: LucideIcons.arrowLeftRight),
            KpiSigh(libelle: 'Articles transférés (lignes)', valeur: nombre(lg.length), icone: LucideIcons.list, ton: TonSigh.info),
            // La valeur se lit sur les LIGNES : l'en-tête d'un bon multi-lignes ne porte pas de CUMP.
            KpiSigh(libelle: 'Valeur transférée', valeur: money(lg.fold<num>(0, (a, r) => a + n(r['valeur']))), icone: LucideIcons.wallet, ton: TonSigh.succes),
            KpiSigh(libelle: 'Bons du mois', valeur: nombre(duMois), icone: LucideIcons.calendar, ton: TonSigh.neutre),
          ]),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(id: 'bons', libelle: 'Bons de transfert', construire: (ctx) => _tableBons(ctx, c, bons, filtreDestination)),
            OngletDef(id: 'articles', libelle: 'Vue détaillée par article', construire: (ctx) => _tableArticles(ctx, c, col, lg, filtreDestination)),
          ]),
        ]);
      },
    );
  }

  Widget _tableBons(BuildContext ctx, ContexteEcran c, List<Fiche> bons, FiltreTableau filtreDestination) {
    final col = c.magasin.collection('transferts');
    return TableauSigh(
      key: _cleBons,
      titre: 'Bons de transfert',
      lignes: bons,
      taillePage: 12,
      triInitial: 'date',
      sensInitial: 'desc',
      nomExport: 'transferts',
      messageVide: 'Aucun transfert enregistré.',
      indiceVide: 'Un transfert déplace une quantité du magasin central vers la pharmacie de détail.',
      filtres: [filtreDestination],
      alClicLigne: (t) => _detail(ctx, t),
      actions: [
        BoutonSigh(
            libelle: 'Imprimer le registre détaillé',
            icone: LucideIcons.printer,
            taille: TailleBouton.sm,
            variante: VarianteBouton.secondaire,
            onPressed: () => _imprimer(ctx, _pieceRegistre(ctx, _cleBons.currentState?.lignesFiltrees ?? bons))),
        // Le bouton OBÉIT AUX DROITS : le Caissier-Dispensateur voit les transferts (il reçoit la marchandise) mais ne les émet pas.
        if (c.droit.editer)
          BoutonSigh(libelle: 'Nouveau transfert', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _ouvrir(ctx, c)),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'reference', libelle: 'N° bon', sansCoupure: true, texte: (t) => '${t['reference']}', rendu: (_, t) => reference(t['reference'], gras: true)),
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (t) => dateDe(t['date'])),
        const ColonneTableau(cle: 'demandeur', libelle: 'Destination'),
        // CE QUE LE BON TRANSPORTE, lisible sans l'ouvrir : les trois premières désignations, puis le reste compté.
        ColonneTableau(
            cle: 'articles',
            libelle: 'Articles transférés',
            valeur: (t) => lignesDeBon(t).map((l) => '${l['produit']}').join(' · '),
            texte: (t) => lignesDeBon(t).map((l) => '${l['produit']} (${l['quantite']})').join(' · '),
            rendu: (_, t) {
              final lg = lignesDeBon(t);
              final vus = lg.take(3).map((l) => '${l['produit']} ×${nombre(l['quantite'])}');
              return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(vus.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate700, fontSize: 12, height: 16 / 12)),
                    if (lg.length > 3)
                      Text('+ ${lg.length - 3} autre(s) article(s)', style: const TextStyle(color: JetonsShell.slate400, fontSize: 11, height: 15 / 11)),
                  ]));
            }),
        ColonneTableau(cle: 'nbLignes', libelle: 'Lignes', droite: true, valeur: (t) => lignesDeBon(t).length, texte: (t) => nombre(lignesDeBon(t).length)),
        ColonneTableau(cle: 'quantite', libelle: 'Quantité', droite: true, valeur: (t) => totalQuantite(lignesDeBon(t)), texte: (t) => nombre(totalQuantite(lignesDeBon(t)))),
        ColonneTableau(cle: 'valeur', libelle: 'Valeur', droite: true, valeur: (t) => totalValeur(lignesDeBon(t)), texte: (t) => m(totalValeur(lignesDeBon(t)))),
        ColonneTableau(cle: 'receptionnaire', libelle: 'Réceptionnaire', texte: (t) => '${t['receptionnaire'] ?? '—'}'),
        const ColonneTableau(cle: 'operateur', libelle: 'Opérateur'),
      ],
      actionsLigne: (ctx2, t) => [
        BoutonIcone(icone: LucideIcons.eye, libelle: 'Voir les articles du bon', onPressed: () => _detail(ctx, t)),
        BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer le bon', onPressed: () => _imprimer(ctx, _pieceBon(ctx, t))),
        if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier le bon', onPressed: () => _refusModification(ctx, c, t)),
        if (c.droit.annuler)
          BoutonIcone(
              icone: LucideIcons.archive,
              libelle: 'Archiver',
              onPressed: () {
                final undo = col.archiver(t['id']);
                annonce(ctx, 'Transfert archivé.', annuler: undo);
              }),
      ],
    );
  }

  Widget _tableArticles(BuildContext ctx, ContexteEcran c, CollectionMagasin col, List<Ligne> lg, FiltreTableau filtreDestination) {
    return TableauSigh(
      key: _cleLignes,
      titre: 'Articles transférés — une ligne par article',
      lignes: lg,
      taillePage: 15,
      triInitial: 'date',
      sensInitial: 'desc',
      nomExport: 'transferts-articles',
      libelleRecherche: 'Article, code, lot, n° de bon…',
      messageVide: 'Aucun article transféré.',
      filtres: [
        FiltreTableau(nom: 'categorie', libelle: 'Famille', options: [for (final f in mv.categoriesProduit) OptionChamp(f.$1, f.$2)]),
        filtreDestination,
      ],
      actions: [
        BoutonSigh(
            libelle: 'Imprimer l’état détaillé',
            icone: LucideIcons.printer,
            taille: TailleBouton.sm,
            variante: VarianteBouton.secondaire,
            onPressed: () => _imprimer(ctx, _pieceLignes(ctx, _cleLignes.currentState?.lignesFiltrees ?? lg))),
      ],
      alClicLigne: (r) {
        final t = col.parId(r['bonId']);
        if (t != null) _detail(ctx, t);
      },
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N° bon', sansCoupure: true, texte: (r) => '${r['reference']}', rendu: (_, r) => reference(r['reference'], gras: true)),
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => dateDe(r['date'])),
        ColonneTableau(cle: 'code', libelle: 'Code', texte: (r) => '${r['code'] == '' ? '—' : r['code']}', rendu: (_, r) => reference(r['code'] == '' ? '—' : r['code'])),
        const ColonneTableau(cle: 'produit', libelle: 'Article'),
        ColonneTableau(cle: 'categorie', libelle: 'Famille', texte: (r) => r['categorie'] == '' ? '—' : categorieLabel(r['categorie'])),
        ColonneTableau(cle: 'lot', libelle: 'Lot', texte: (r) => r['lot'] == '' ? '—' : '${r['lot']}'),
        ColonneTableau(cle: 'peremption', libelle: 'Péremption', sansCoupure: true, texte: (r) => r['peremption'] == '' ? '—' : dateDe(r['peremption'])),
        ColonneTableau(cle: 'quantite', libelle: 'Quantité', droite: true, texte: (r) => nombre(r['quantite'])),
        const ColonneTableau(cle: 'unite', libelle: 'Unité'),
        ColonneTableau(cle: 'cump', libelle: 'CUMP', droite: true, texte: (r) => m(r['cump'])),
        ColonneTableau(cle: 'valeur', libelle: 'Valeur', droite: true, texte: (r) => m(r['valeur'])),
        ColonneTableau(cle: 'demandeur', libelle: 'Magasin → destination', texte: (r) => 'Magasin → ${r['demandeur']}'),
      ],
      actionsLigne: (ctx2, r) => [
        BoutonIcone(
            icone: LucideIcons.eye,
            libelle: 'Voir le bon ${r['reference']}',
            onPressed: () {
              final t = col.parId(r['bonId']);
              if (t != null) _detail(ctx, t);
            }),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Tiroir du bon : le bon ENTIER, ligne par ligne, avec ses totaux.
  // --------------------------------------------------------------------------
  void _detail(BuildContext ctx, Fiche t) {
    final lg = lignesDeBon(t);
    afficherTiroir<void>(ctx,
        titre: 'Bon de transfert ${t['reference']}',
        sousTitre: '${dateDe(t['date'])} — ${t['demandeur'] ?? ''}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Référence', reference(t['reference'])),
            ('Date', dateDe(t['date'])),
            ('Origine', 'Magasin central (stock gros)'),
            ('Destination', t['demandeur'] ?? '—'),
            ('Opérateur', t['operateur'] ?? '—'),
            ('Réceptionnaire', t['receptionnaire'] ?? '—'),
            ('Motif', (t['motif'] == null || t['motif'] == '') ? '—' : t['motif']),
            ('Articles', nombre(lg.length)),
            ('Quantité totale', nombre(totalQuantite(lg))),
            ('Valeur totale', money(totalValeur(lg))),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Articles transférés — du magasin de gros vers le détail',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _tableLignesBon(ctx, lg),
                const SizedBox(height: 8),
                Align(
                    alignment: Alignment.centerRight,
                    child: Text('${nombre(lg.length)} article(s) — ${nombre(totalQuantite(lg))} unité(s), valeur totale ${money(totalValeur(lg))}',
                        style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, fontWeight: FontWeight.w600))),
              ])),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Imprimer le bon', icone: LucideIcons.printer, onPressed: () => _imprimer(ctx, _pieceBon(ctx, t))),
            ]);
  }

  /// Le tableau des lignes d'UN bon : pied de TOTAL calculé depuis les lignes affichées, comme sur la pièce imprimée — les deux doivent dire la même chose.
  Widget _tableLignesBon(BuildContext ctx, List<Fiche> lg) {
    final produits = ContexteEcran.of(ctx).magasin.collection('produits');
    const entetes = ['Article', 'Famille', 'Lot / péremption', 'Quantité', 'CUMP', 'Valeur'];
    Widget cel(Widget w, {bool droite = false}) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Align(alignment: droite ? Alignment.centerRight : Alignment.centerLeft, child: w));
    Text txt(String s, {bool gras = false, double taille = 14, Color couleur = JetonsShell.slate700}) =>
        Text(s, style: TextStyle(color: couleur, fontSize: taille, height: 1.4, fontWeight: gras ? FontWeight.w600 : null, fontFeatures: const [FontFeature.tabularFigures()]));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
                decoration: const BoxDecoration(color: JetonsShell.slate50, border: Border(bottom: BorderSide(color: JetonsShell.slate200))),
                children: [
                  for (final (i, h) in entetes.indexed)
                    cel(Text(h.toUpperCase(), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)), droite: i >= 3)
                ]),
            for (final l in lg)
              () {
                final pr = l['produitId'] != null ? produits.parId(l['produitId']) : null;
                final cat = '${l['categorie'] ?? pr?['categorie'] ?? ''}';
                final code = '${l['code'] ?? pr?['code'] ?? ''}';
                return TableRow(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate100))), children: [
                  cel(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    txt('${l['produit']}', gras: true, couleur: JetonsShell.slate800),
                    if (code.isNotEmpty) Text(code, style: styleMono.copyWith(fontSize: 11, color: JetonsShell.slate400)),
                  ])),
                  cel(txt(cat.isEmpty ? '—' : categorieLabel(cat), taille: 12)),
                  cel(txt(l['lot'] != null ? '${l['lot']}${l['peremption'] != null ? ' — ${dateDe(l['peremption'])}' : ''}' : '—', taille: 12)),
                  cel(txt('${nombre(l['quantite'])} ${l['unite'] ?? ''}'), droite: true),
                  cel(txt(m(l['cump'] ?? 0)), droite: true),
                  cel(txt(m(valeurLigne(l))), droite: true),
                ]);
              }(),
            TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
              cel(txt('TOTAL — ${nombre(lg.length)} article(s)', gras: true)),
              cel(const SizedBox()),
              cel(const SizedBox()),
              cel(txt(nombre(totalQuantite(lg)), gras: true), droite: true),
              cel(const SizedBox()),
              cel(txt(m(totalValeur(lg)), gras: true), droite: true),
            ]),
          ]),
    );
  }

  /// Un transfert VALIDÉ a déjà déplacé le stock : le modifier laisserait les deux magasins faux sans qu'aucun mouvement ne le dise.
  /// On le refuse EN EXPLIQUANT le chemin — archiver, puis réémettre.
  Future<void> _refusModification(BuildContext ctx, ContexteEcran c, Fiche t) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Un bon de transfert ne se modifie pas',
        message: 'Le bon ${t['reference']} a déjà déplacé le stock : deux mouvements symétriques ont été écrits, le magasin débité et la pharmacie créditée. '
            'Le corriger ici laisserait les deux stocks faux sans qu’aucun mouvement ne le dise (RG-03).\n\n'
            'Pour corriger : archiver ce bon, puis en émettre un nouveau avec les bonnes quantités.',
        libelleOk: 'Archiver ce bon',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    final undo = c.magasin.collection('transferts').archiver(t['id']);
    annonce(ctx, 'Bon archivé — émettre le bon corrigé.', annuler: undo);
  }

  // --------------------------------------------------------------------------
  // Impressions
  // --------------------------------------------------------------------------
  Future<void> _imprimer(BuildContext ctx, PieceA4 p) => afficherApercu(ctx, p);

  PieceA4 _pieceBon(BuildContext ctx, Fiche t) {
    final c = ContexteEcran.of(ctx);
    final lg = lignesDeBon(t);
    return PieceA4(
      titre: 'Bon de transfert de stock',
      sousTitre: '${t['reference']}',
      reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
      utilisateur: c.utilisateur,
      edite: c.aujourdhui,
      cartouche: [
        ('Référence', '${t['reference']}'),
        ('Date', dateDe(t['date'])),
        ('Origine', 'Magasin central (stock gros)'),
        ('Destination', '${t['demandeur'] ?? ''}'),
        ('Opérateur', '${t['operateur'] ?? ''}'),
        ('Réceptionnaire', '${t['receptionnaire'] ?? '—'}'),
        ('Motif', (t['motif'] == null || t['motif'] == '') ? '—' : '${t['motif']}'),
        ('Articles transférés', nombre(lg.length)),
      ],
      // LE DÉTAIL, ET LE TOTAL CALCULÉ depuis les lignes imprimées : on ne signe pas un bon qui ne dit pas ce qu'il transporte.
      tableaux: [
        TableauEtat(libelleTotal: 'TOTAL DU BON', colonnes: [
          ColonneEtat(libelle: 'Code', valeur: (x) => x['code'] ?? ''),
          ColonneEtat(libelle: 'Article', valeur: (x) => x['produit']),
          ColonneEtat(libelle: 'Famille', valeur: (x) => x['categorie'] != null && x['categorie'] != '' ? categorieLabel(x['categorie']) : ''),
          ColonneEtat(libelle: 'Lot', valeur: (x) => x['lot'] ?? ''),
          ColonneEtat(libelle: 'Péremption', valeur: (x) => x['peremption'] != null && x['peremption'] != '' ? dateDe(x['peremption']) : ''),
          ColonneEtat(libelle: 'Unité', valeur: (x) => x['unite']),
          ColonneEtat(libelle: 'Quantité transférée', valeur: (x) => nombre(x['quantite']), droite: true, somme: (x) => n(x['quantite'])),
          ColonneEtat(libelle: 'CUMP', valeur: (x) => m(x['cump'] ?? 0), droite: true),
          ColonneEtat(libelle: 'Valeur', valeur: (x) => m(valeurLigne(x)), droite: true, somme: valeurLigne),
        ], lignes: lg),
      ],
      signatures: [
        Signature('Le Gestionnaire de Stock', nom: '${t['operateur'] ?? 'MAMAN Zoukanéri'}', mention: 'Sortie magasin'),
        Signature('Le Service demandeur', nom: t['receptionnaire'] as String?, mention: 'Réception'),
      ],
    );
  }

  /// Colonnes communes aux deux états détaillés : une ligne par article, avec le bon dont elle vient. Quantité et valeur se TOTALISENT ; le CUMP,
  /// prix unitaire, non — additionner des prix unitaires ne produit aucune grandeur.
  List<ColonneEtat> _colonnesLignes() => [
        ColonneEtat(libelle: 'N° bon', valeur: (x) => x['reference']),
        ColonneEtat(libelle: 'Date', valeur: (x) => dateDe(x['date'])),
        ColonneEtat(libelle: 'Destination', valeur: (x) => x['demandeur']),
        ColonneEtat(libelle: 'Article', valeur: (x) => x['produit']),
        ColonneEtat(libelle: 'Famille', valeur: (x) => x['categorie'] != null && x['categorie'] != '' ? categorieLabel(x['categorie']) : ''),
        ColonneEtat(libelle: 'Lot', valeur: (x) => x['lot'] ?? ''),
        ColonneEtat(libelle: 'Qté', valeur: (x) => '${nombre(x['quantite'])}${x['unite'] != null && x['unite'] != '' ? ' ${x['unite']}' : ''}', droite: true, somme: (x) => n(x['quantite'])),
        ColonneEtat(libelle: 'CUMP', valeur: (x) => m(x['cump'] ?? 0), droite: true),
        ColonneEtat(libelle: 'Valeur', valeur: (x) => m(x['valeur']), droite: true, somme: (x) => n(x['valeur'])),
      ];

  List<Ligne> _trierLignes(List<Ligne> lg) => [...lg]..sort((a, b) {
      final d = '${a['date']}'.compareTo('${b['date']}');
      return d != 0 ? d : '${a['reference']}'.compareTo('${b['reference']}');
    });

  /// LE REGISTRE : les bons retenus par la recherche et les filtres, et CE QU'ILS TRANSPORTENT — ligne par ligne, puis le récapitulatif par bon.
  PieceA4 _pieceRegistre(BuildContext ctx, List<Fiche> bons) {
    final c = ContexteEcran.of(ctx);
    final tries = [...bons]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final lg = _trierLignes(_toutesLignes(c.magasin, tries));
    return PieceA4(
      titre: 'Registre des transferts gros → détail',
      sousTitre: 'Détail des articles transférés — ${nombre(bons.length)} bon(s), ${nombre(lg.length)} ligne(s)',
      reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
      utilisateur: c.utilisateur,
      edite: c.aujourdhui,
      cartouche: [
        ('Origine', 'Magasin central (stock gros)'),
        ('Période', tries.isEmpty ? '—' : '${dateDe(tries.first['date'])} au ${dateDe(tries.last['date'])}'),
        ('Bons', nombre(bons.length)),
        ('Lignes d’articles', nombre(lg.length)),
      ],
      blocs: [
        const BlocTexte('DÉTAIL DES ARTICLES TRANSFÉRÉS', gras: true),
        BlocTableau(TableauEtat(libelleTotal: 'TOTAL GÉNÉRAL', colonnes: _colonnesLignes(), lignes: lg)),
        const BlocTexte('RÉCAPITULATIF PAR BON', gras: true),
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'N° bon', valeur: (t) => t['reference']),
          ColonneEtat(libelle: 'Date', valeur: (t) => dateDe(t['date'])),
          ColonneEtat(libelle: 'Destination', valeur: (t) => t['demandeur']),
          ColonneEtat(libelle: 'Réceptionnaire', valeur: (t) => t['receptionnaire'] ?? ''),
          ColonneEtat(libelle: 'Lignes', valeur: (t) => nombre(lignesDeBon(t).length), droite: true, somme: (t) => lignesDeBon(t).length),
          ColonneEtat(libelle: 'Quantité', valeur: (t) => nombre(totalQuantite(lignesDeBon(t))), droite: true, somme: (t) => totalQuantite(lignesDeBon(t))),
          ColonneEtat(libelle: 'Valeur', valeur: (t) => m(totalValeur(lignesDeBon(t))), droite: true, somme: (t) => totalValeur(lignesDeBon(t))),
        ], lignes: tries)),
      ],
      signatures: const [Signature('Le Gestionnaire de Stock', mention: 'Sorties magasin'), Signature('La Directrice Administrative', mention: 'Visa')],
    );
  }

  /// L'état de la vue par article : les lignes retenues, telles quelles.
  PieceA4 _pieceLignes(BuildContext ctx, List<Ligne> lignes) {
    final c = ContexteEcran.of(ctx);
    final lg = _trierLignes(lignes);
    return PieceA4(
      titre: 'État détaillé des articles transférés',
      sousTitre: 'Magasin central → services — ${nombre(lg.length)} ligne(s)',
      reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
      utilisateur: c.utilisateur,
      edite: c.aujourdhui,
      cartouche: [
        ('Origine', 'Magasin central (stock gros)'),
        ('Lignes d’articles', nombre(lg.length)),
        ('Bons concernés', nombre({for (final r in lg) r['reference']}.length)),
      ],
      tableaux: [TableauEtat(libelleTotal: 'TOTAL', colonnes: _colonnesLignes(), lignes: lg)],
      signatures: const [Signature('Le Gestionnaire de Stock', mention: 'Certifié exact')],
    );
  }

  // --------------------------------------------------------------------------
  // Nouveau transfert (modale multi-lignes)
  // --------------------------------------------------------------------------
  void _ouvrir(BuildContext ctx, ContexteEcran c) {
    final dispo = c.magasin.collection('produits').actives.where((p) => n(p['stockGros']) > 0).toList();
    if (dispo.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucun produit disponible au magasin central.', type: TypeToast.attention);
      return;
    }
    final bon = _BonEnCours(c, ctx, trierPar(dispo, (p) => p['designation']));
    afficherModale<void>(ctx,
        titre: 'Nouveau transfert de stock',
        sousTitre: 'Magasin central → pharmacie de détail. Plusieurs articles sur un même bon.',
        taille: TailleModale.xl,
        corps: _CorpsTransfert(bon: bon),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(libelle: 'Valider le transfert', icone: LucideIcons.arrowLeftRight, onPressed: () => bon.valider(fermer)),
            ]);
  }
}

/// Le bon en cours de construction : les lignes, l'en-tête, la ligne de saisie. Un objet à part pour que le pied de la modale (« Valider ») et
/// son corps parlent au même état.
class _BonEnCours extends ChangeNotifier {
  _BonEnCours(this.c, this.ecran, this.dispo)
      : entete = ControleurFormulaire([
          const ChampDef(nom: 'date', libelle: 'Date du transfert', type: TypeChamp.date, requis: true),
          ChampDef(nom: 'demandeur', libelle: 'Service demandeur', type: TypeChamp.select, requis: true, options: [for (final d in _destinations) OptionChamp(d)]),
          const ChampDef(nom: 'motif', libelle: 'Motif du transfert', col: ColChamp.plein),
        ], {
          'date': iso(c.aujourdhui)
        }),
        article = ControleurFormulaire([
          ChampDef(
              nom: 'article',
              libelle: 'Article',
              type: TypeChamp.select,
              col: ColChamp.plein,
              recherche: true,
              indicatif: 'Choisir un article…',
              options: [
                for (final p in dispo) OptionChamp('${p['id']}', '${p['designation']} (disponible : ${nombre(p['stockGros'])} ${p['unite']})')
              ])
        ]),
        quantite = ControleurFormulaire([const ChampDef(nom: 'quantite', libelle: 'Quantité', type: TypeChamp.nombre, indicatif: 'Qté', col: ColChamp.plein)]);

  final ContexteEcran c;

  /// Le contexte de l'ÉCRAN : une modale vit au-dessus de la coque, hors du `ContexteEcran` — messages et impressions passent par lui.
  final BuildContext ecran;
  final List<Fiche> dispo;
  final ControleurFormulaire entete;
  final ControleurFormulaire article;
  final ControleurFormulaire quantite;
  List<Fiche> lignes = [];

  List<Fiche> get _produits => c.magasin.collection('produits').actives;
  List<Fiche> get _lots => c.magasin.collection('lots').actives;

  void _refus(RefusStock e) => ToastsSigh.afficher(ecran, e.motif, type: TypeToast.erreur, detail: e.detail);

  void ajouter() {
    try {
      lignes = ajouterLigneTransfert(
          lignes: lignes, produitId: '${article['article']}', quantite: quantite['quantite'], produits: _produits, lots: _lots);
    } on RefusStock catch (e) {
      _refus(e);
      return;
    }
    article.poser('article', '');
    quantite.poser('quantite', '');
    notifyListeners();
  }

  double reste(int k) => disponibleRestant(_produits.where((p) => p['id'] == lignes[k]['produitId']).firstOrNull, lignes, lignes[k]['produitId'], saufIndex: k);

  void modifier(BuildContext contexte, int k) {
    final l = lignes[k];
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'quantite',
          libelle: 'Quantité',
          type: TypeChamp.nombre,
          requis: true,
          col: ColChamp.plein,
          aide: '${nombre(reste(k))} ${l['unite']} disponible(s) au magasin.',
          valider: (v, _) => n(v) < 1 ? 'La valeur minimale est 1.' : null)
    ], {
      'quantite': '${l['quantite'] is num && (l['quantite'] as num) == (l['quantite'] as num).truncate() ? (l['quantite'] as num).toInt() : l['quantite']}'
    });
    afficherModale<void>(contexte,
        titre: 'Modifier — ${l['produit']}',
        taille: TailleModale.sm,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Appliquer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    try {
                      lignes = modifierQuantiteLigne(lignes: lignes, rang: k, quantite: v['quantite'], produits: _produits);
                    } on RefusStock catch (e) {
                      _refus(e);
                      return;
                    }
                    fermer();
                    notifyListeners();
                  }),
            ]);
  }

  void retirer(int k) {
    final l = lignes[k];
    lignes = [...lignes]..removeAt(k);
    notifyListeners();
    annonce(ecran, 'Ligne retirée — ${l['produit']}.', type: TypeToast.info, messageAnnulation: 'Ligne rétablie.', annuler: () {
      lignes = [...lignes]..insert(k.clamp(0, lignes.length), l);
      notifyListeners();
    });
  }

  void valider(VoidCallback fermer) {
    final v = entete.valider();
    if (v == null) {
      ToastsSigh.afficher(ecran, 'L’en-tête du bon comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    // Dernier contrôle RG-03 avant écriture : le stock a pu bouger pendant la saisie. Le refus nomme la ligne fautive.
    try {
      controlerBonAvantEcriture(lignes, _produits);
    } on RefusStock catch (e) {
      _refus(e);
      return;
    }
    final col = c.magasin.collection('transferts');
    final emis = emettreTransfert(
        date: '${v['date']}',
        demandeur: '${v['demandeur']}',
        motif: '${v['motif'] ?? ''}',
        lignes: lignes,
        produits: _produits,
        bons: col.toutes,
        utilisateur: c.utilisateur);
    final produits = c.magasin.collection('produits');
    final mouvements = c.magasin.collection('mouvements');
    final annulations = <VoidCallback>[];
    // Pour chaque ligne : le produit, puis les DEUX mouvements symétriques.
    for (final p in emis.produits) {
      produits.mettreAJour(p.id, p.patch);
    }
    for (final mv in emis.mouvements) {
      annulations.add(mouvements.inserer(mv, prefixe: 'MVT').annuler);
    }
    final ins = col.inserer(emis.bon, prefixe: 'TRF');
    annulations.add(ins.annuler);
    final nb = lignes.length;
    fermer();
    annonce(ecran, 'Transfert de ${nombre(nb)} article(s) enregistré.',
        detail: '${emis.reference} — ${v['demandeur']}',
        // L'annulation restitue TOUTES les lignes : un transfert partiellement annulé laisserait le stock faux.
        messageAnnulation: 'Transfert annulé — les ${nombre(nb)} lignes sont restituées.',
        annuler: () {
          for (final a in emis.avant) {
            produits.mettreAJour(a.id, a.patch);
          }
          for (final u in annulations) {
            u();
          }
        });
  }
}

class _CorpsTransfert extends StatelessWidget {
  const _CorpsTransfert({required this.bon});
  final _BonEnCours bon;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: bon,
        builder: (context, _) {
          final lg = bon.lignes;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormulaireSigh(controleur: bon.entete),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Articles à transférer',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: FormulaireSigh(controleur: bon.article)),
                    const SizedBox(width: 8),
                    SizedBox(width: 120, child: FormulaireSigh(controleur: bon.quantite)),
                    const SizedBox(width: 8),
                    BoutonSigh(libelle: 'Ajouter', icone: LucideIcons.plus, variante: VarianteBouton.secondaire, onPressed: bon.ajouter),
                  ]),
                  const SizedBox(height: 12),
                  if (lg.isEmpty)
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                        decoration: BoxDecoration(border: Border.all(color: JetonsShell.slate300), borderRadius: BorderRadius.circular(8)),
                        child: const Center(
                            child: Text('Aucune ligne sur ce bon. Choisir un article et une quantité, puis « Ajouter ».',
                                style: TextStyle(color: JetonsShell.slate400, fontSize: 14))))
                  else ...[
                    _tableLignes(context, lg),
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                            alignment: Alignment.centerRight,
                            child: Text('${nombre(lg.length)} ligne(s) — valeur totale ${money(totalValeur(lg))}',
                                style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, fontWeight: FontWeight.w600)))),
                  ],
                ])),
          ]);
        },
      );

  Widget _tableLignes(BuildContext context, List<Fiche> lg) {
    Widget cel(Widget w, {bool droite = false}) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Align(alignment: droite ? Alignment.centerRight : Alignment.centerLeft, child: w));
    Text txt(String s, {bool gras = false}) =>
        Text(s, style: TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: gras ? FontWeight.w600 : null, fontFeatures: const [FontFeature.tabularFigures()]));
    final produits = bon.c.magasin.collection('produits');
    return Table(columnWidths: const {
      0: FlexColumnWidth(3),
      1: FlexColumnWidth(2),
      2: FlexColumnWidth(2.5),
      3: FlexColumnWidth(2),
      4: IntrinsicColumnWidth()
    }, defaultVerticalAlignment: TableCellVerticalAlignment.middle, children: [
      TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50, border: Border(bottom: BorderSide(color: JetonsShell.slate200))), children: [
        for (final (i, h) in ['Article', 'Quantité', 'Restera au magasin', 'Valeur (CUMP)', 'Actions'].indexed)
          cel(Text(h.toUpperCase(), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)), droite: i >= 1 && i <= 3)
      ]),
      for (final (k, l) in lg.indexed)
        TableRow(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate100))), children: [
          cel(txt('${l['produit']}')),
          cel(txt('${nombre(l['quantite'])} ${l['unite']}'), droite: true),
          cel(txt('${nombre(n(produits.parId(l['produitId'])?['stockGros']) - n(l['quantite']))} ${l['unite']}'), droite: true),
          cel(txt(money(n(l['quantite']) * n(l['cump']))), droite: true),
          cel(Row(mainAxisSize: MainAxisSize.min, children: [
            BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier la quantité', onPressed: () => bon.modifier(context, k)),
            BoutonIcone(icone: LucideIcons.trash2, libelle: 'Retirer la ligne', onPressed: () => bon.retirer(k)),
          ])),
        ]),
      TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
        cel(txt('TOTAL', gras: true)),
        cel(const SizedBox()),
        cel(const SizedBox()),
        cel(txt(money(totalValeur(lg)), gras: true), droite: true),
        cel(const SizedBox()),
      ]),
    ]);
  }
}
