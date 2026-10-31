import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/flux_commun.dart' show SourceFlux;
import '../m6/points_commun.dart' show champUnique, commande;
import 'cat_commun.dart';

String _en(Object? v) => v == null ? '' : (v is num ? catNombreJs(v) : '$v');

String _libelleCategorieCourt(Fiche p) =>
    p['categorie'] == 'reactif' ? 'Réactif' : 'Consommable labo';

/// `m5-reactifs` — « Réactifs & consommables de laboratoire » : le stock des réactifs et consommables du labo, sa valeur au CUMP, ce qui passe sous le
/// SEUIL D'ALERTE, la consommation par période et le bon de demande. Le seuil est FIXÉ PAR LA CLINIQUE, référence par référence (le document SAGE ne le
/// renseigne pas) : un seuil absent n'est pas un seuil de zéro — l'article est signalé À PART, et aucune alerte ne peut être émise sur lui. Les produits
/// sont ceux du module M6 (une seule fiche d'article) : ici on les lit, on en crée et on en corrige la fiche.
class EcranReactifsLabo extends StatefulWidget with EcranMaquette {
  const EcranReactifsLabo({super.key});

  @override
  String get titre => 'Réactifs & consommables de laboratoire';

  @override
  String get description =>
      'Suivi des stocks de réactifs, consommation rattachée aux analyses réalisées et carnet de demande.';

  @override
  String get regle =>
      'Le coût unitaire moyen pondéré (CUMP) est calculé automatiquement pour les réactifs et consommables de laboratoire (CDCT §10.1). Le seuil d’alerte est fixé par la clinique, référence par référence : le document SAGE d’origine ne le renseigne pas, et un seuil unique n’aurait aucun sens entre un réactif à péremption courte et un consommable de fond de rayon.';

  @override
  State<EcranReactifsLabo> createState() => _EtatReactifs();
}

class _EtatReactifs extends State<EcranReactifsLabo> {
  late final ControleurFormulaire _periode;
  bool _pret = false;

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    _periode = champUnique(
        ChampDef(
            nom: 'periode',
            libelle: 'Période de consommation',
            type: TypeChamp.select,
            col: ColChamp.plein,
            options: [
              for (final p in catPeriodesLabo) OptionChamp(p.id, p.libelle)
            ]),
        'mois');
    _periode.addListener(_maj);
    _pret = true;
  }

  @override
  void dispose() {
    if (_pret) {
      _periode.removeListener(_maj);
      _periode.dispose();
    }
    super.dispose();
  }

  ({String id, String libelle, int? jours}) get _per => catPeriodesLabo
      .firstWhere((x) => x.id == _periode['periode'], orElse: () => catPeriodesLabo[1]);

  // -------------------------------------------------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final produits = c.magasin.collection('produits');
    final mouvements = c.magasin.collection('mouvements');
    return ListenableBuilder(
      listenable: Listenable.merge([produits, mouvements]),
      builder: (context, _) {
        final prods = catReactifs(produits.actives);
        final k = catKpisReactifs(prods);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Références suivies',
                valeur: nombre(k.references),
                icone: LucideIcons.testTube),
            KpiSigh(
                libelle: 'Valeur du stock',
                valeur: money(k.valeur),
                icone: LucideIcons.wallet,
                ton: TonSigh.info,
                indice: 'Valorisation au CUMP'),
            KpiSigh(
                libelle: 'Sous le seuil d’alerte',
                valeur: nombre(k.sousSeuil),
                icone: LucideIcons.trendingDown,
                ton: TonSigh.danger,
                indice: 'Seuils fixés par la clinique'),
            KpiSigh(
                libelle: 'En rupture',
                valeur: nombre(k.rupture),
                icone: LucideIcons.circleX,
                ton: TonSigh.danger),
          ]),
          if (k.sansSeuil.isNotEmpty) ...[
            const SizedBox(height: 12),
            NoteSigh(
                '${nombre(k.sansSeuil.length)} référence(s) sans seuil d’alerte. Tant qu’un seuil n’est pas fixé, aucune alerte ne peut être émise sur ces articles — le document SAGE d’origine ne renseigne pas cette colonne, c’est à la clinique de l’arrêter.',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert),
          ],
          const SizedBox(height: 16),
          _tableau(context, c, prods),
          const SizedBox(height: 16),
          _consommation(context, c, prods, mouvements),
          const SizedBox(height: 16),
          const SourceFlux(
              'Inventaire SAGE « Grand Stock » — les seuils d’alerte y sont absents et se définissent ici, référence par référence.'),
        ]);
      },
    );
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // Le stock
  // -------------------------------------------------------------------------------------------------------------------------------------------

  Widget _tableau(BuildContext ctx, ContexteEcran c, List<Fiche> prods) {
    Color teinte(Fiche p) => switch (catTeinteStock(p)) {
          'danger' => JetonsShell.danger600,
          'attention' => JetonsShell.warning600,
          _ => JetonsShell.slate700,
        };
    return TableauSigh(
      titre: 'Stock des réactifs et consommables',
      lignes: prods,
      taillePage: 15,
      nomExport: 'reactifs-laboratoire',
      filtres: [
        const FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [
          OptionChamp('reactif', 'Réactifs'),
          OptionChamp('conso_labo', 'Consommables de laboratoire'),
        ]),
        FiltreTableau(
            nom: 'alerte',
            libelle: 'Niveau de stock',
            options: const [
              OptionChamp('rupture', 'En rupture'),
              OptionChamp('alerte', 'Sous le seuil'),
              OptionChamp('ok', 'Stock suffisant'),
              OptionChamp('sansSeuil', 'Sans seuil défini'),
            ],
            correspond: catNiveauCorrespond),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'code',
            libelle: 'Code',
            sansCoupure: true,
            texte: (p) => '${p['code'] ?? ''}',
            rendu: (_, p) => Text('${p['code'] ?? ''}',
                style: monoCode.copyWith(
                    color: JetonsShell.slate700, fontWeight: FontWeight.w400))),
        const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
        ColonneTableau(
            cle: 'categorie',
            libelle: 'Catégorie',
            texte: _libelleCategorieCourt,
            rendu: (_, p) => BadgeSigh(
                p['categorie'] == 'reactif' ? 'Réactif' : 'Consommable',
                ton: TonSigh.navy)),
        const ColonneTableau(cle: 'unite', libelle: 'Unité'),
        ColonneTableau(
            cle: 'stock',
            libelle: 'Stock',
            droite: true,
            valeur: (p) => nombreOuZero(p['stock']),
            texte: (p) => nombre(p['stock']),
            rendu: (_, p) => Text(nombre(p['stock']),
                textAlign: TextAlign.right,
                style: styleCat(
                    couleur: teinte(p),
                    poids: catTeinteStock(p).isEmpty
                        ? FontWeight.w400
                        : FontWeight.w600))),
        ColonneTableau(
            cle: 'seuilAlerte',
            libelle: 'Seuil',
            droite: true,
            valeur: (p) => catSansSeuil(p) ? null : nombreOuZero(p['seuilAlerte']),
            texte: (p) => catSansSeuil(p) ? '—' : _en(p['seuilAlerte']),
            rendu: (_, p) => Text(catSansSeuil(p) ? '—' : _en(p['seuilAlerte']),
                textAlign: TextAlign.right,
                style: styleCat(
                    couleur: catSansSeuil(p)
                        ? JetonsShell.slate300
                        : JetonsShell.slate700))),
        ColonneTableau(
            cle: 'cump',
            libelle: 'CUMP',
            droite: true,
            valeur: (p) => nombreOuZero(p['cump']),
            texte: (p) => money(p['cump'], avecDevise: false)),
        ColonneTableau(
            cle: 'valeur',
            libelle: 'Valeur',
            droite: true,
            valeur: catValeurReactif,
            texte: (p) => money(catValeurReactif(p), avecDevise: false)),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            valeur: catEtatReactif,
            texte: (p) => statutsMetier[catEtatReactif(p)]?.$1 ?? '',
            rendu: (_, p) => statutBadge(catEtatReactif(p))),
      ],
      actions: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau réactif',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => _saisir(ctx, null)),
        BoutonSigh(
            libelle: 'Bon de demande de réactifs',
            icone: LucideIcons.clipboardList,
            taille: TailleBouton.sm,
            onPressed: () => _bon(ctx, prods)),
      ],
      actionsLigne: (context, p) => [
        if (c.droit.editer)
          BoutonIcone(
              icone: LucideIcons.pencil,
              libelle: 'Modifier',
              onPressed: () => _saisir(ctx, p)),
      ],
    );
  }

  List<ChampDef> _champs(Magasin m) => [
        const ChampDef(
            nom: 'designation',
            libelle: 'Désignation',
            requis: true,
            col: ColChamp.plein),
        const ChampDef(
            nom: 'categorie',
            libelle: 'Catégorie',
            type: TypeChamp.select,
            requis: true,
            options: [
              OptionChamp('reactif', 'Réactif'),
              OptionChamp('conso_labo', 'Consommable de laboratoire'),
            ]),
        const ChampDef(
            nom: 'unite', libelle: 'Unité de conditionnement', requis: true),
        const ChampDef(
            nom: 'stock',
            libelle: 'Stock actuel',
            type: TypeChamp.nombre,
            requis: true),
        const ChampDef(
            nom: 'seuilAlerte',
            libelle: 'Seuil d’alerte',
            type: TypeChamp.nombre,
            requis: true,
            aide:
                'À partir de quelle quantité la clinique veut être prévenue. Absent du document SAGE : c’est à l’établissement de l’arrêter.'),
        const ChampDef(
            nom: 'seuilCritique',
            libelle: 'Seuil critique',
            type: TypeChamp.nombre,
            aide: 'Quantité au-dessous de laquelle l’activité s’arrête. Facultatif.'),
        const ChampDef(
            nom: 'cump', libelle: 'CUMP (FCFA)', type: TypeChamp.nombre),
        const ChampDef(nom: 'emplacement', libelle: 'Emplacement'),
        const ChampDef(nom: 'fournisseur', libelle: 'Fournisseur habituel'),
        ChampDef(
            nom: 'examensLies',
            libelle: 'Examens desservis',
            type: TypeChamp.multiselect,
            col: ColChamp.plein,
            aide: 'Sert à rattacher la consommation aux examens réalisés.',
            options: [
              for (final e in m.collection('examensLabo').actives)
                OptionChamp('${e['code']}', '${e['designation']}')
            ]),
      ];

  /// « Nouveau réactif » et « Modifier » : une modale, le refus se DIT (RG-03 : le stock ne devient jamais négatif).
  void _saisir(BuildContext ctx, Fiche? p) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final creation = p == null;
    final ctl = ControleurFormulaire(
        _champs(m),
        creation
            ? {'categorie': 'reactif', 'stock': '0', 'seuilAlerte': '10', 'cump': '0'}
            : {
                for (final e in p.entries)
                  e.key: e.value is List ? e.value : _en(e.value)
              });
    afficherModale<void>(ctx,
        titre: creation
            ? 'Nouveau réactif ou consommable'
            : 'Modifier l’enregistrement ${p['code']}',
        sousTitre: creation
            ? 'Les champs marqués d’un astérisque sont obligatoires.'
            : null,
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: creation ? 'Créer' : 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(
                          ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final refus = catRefuserReactif(saisie);
                    if (refus != null) {
                      ToastsSigh.afficher(ctx, refus.message,
                          type: TypeToast.erreur, detail: refus.detail);
                      return;
                    }
                    final col = m.collection('produits');
                    if (creation) {
                      final fiche = catNouveauReactif(saisie,
                          produits: col.toutes,
                          utilisateur: c.utilisateur,
                          maintenant: c.aujourdhui);
                      final r = col.inserer({'statut': 'actif', ...fiche}, prefixe: 'PRO');
                      fermer();
                      ToastsSigh.afficher(ctx, 'Référence créé.',
                          type: TypeToast.succes,
                          detail: '${fiche['designation']}',
                          annuler: r.annuler);
                    } else {
                      final annuler =
                          col.mettreAJour(p['id'], catTransformReactif(saisie));
                      fermer();
                      ToastsSigh.afficher(ctx, 'Modifications enregistrées.',
                          type: TypeToast.succes, annuler: annuler);
                    }
                  }),
            ]);
  }

  /// « Bon de demande de réactifs » : les références dont le stock a atteint le seuil FIXÉ. Un seuil non fixé n'est pas un seuil de zéro — l'article
  /// est signalé à part, jamais passé sous silence.
  void _bon(BuildContext ctx, List<Fiche> prods) {
    final c = ContexteEcran.of(ctx);
    final manquants = catManquants(prods);
    final sans = prods.where(catSansSeuil).toList();
    if (manquants.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucune référence sous son seuil d’alerte.',
          type: sans.isNotEmpty ? TypeToast.attention : TypeToast.succes,
          detail: sans.isNotEmpty
              ? '${nombre(sans.length)} référence(s) n’ont pas de seuil défini : elles ne peuvent pas être surveillées tant que la clinique ne l’a pas fixé.'
              : 'Le stock de réactifs et consommables est au-dessus des seuils fixés.');
      return;
    }
    afficherApercu(
        ctx,
        pieceCat(ctx,
            titre: 'Bon d’expression de besoins — Laboratoire',
            sousTitre: 'Réactifs et consommables sous le seuil d’alerte',
            cartouche: [
              ('Service demandeur', 'Laboratoire'),
              ('Date', dateFR(c.aujourdhui)),
              ('Références concernées', nombre(manquants.length)),
              ('Établi par', laborantinChef),
            ],
            filtres: [('Période de consommation', _per.libelle)],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Code', valeur: (p) => p['code']),
                ColonneEtat(libelle: 'Désignation', valeur: (p) => p['designation']),
                ColonneEtat(libelle: 'Unité', valeur: (p) => p['unite']),
                ColonneEtat(
                    libelle: 'Stock actuel',
                    valeur: (p) => _en(p['stock']),
                    droite: true),
                ColonneEtat(
                    libelle: 'Seuil',
                    valeur: (p) => _en(p['seuilAlerte']),
                    droite: true),
                ColonneEtat(
                    libelle: 'Qté demandée',
                    valeur: catQuantiteDemandee,
                    droite: true),
                ColonneEtat(libelle: 'Qté accordée', valeur: (_) => ''),
              ], lignes: manquants)),
            ],
            signatures: const [
              Signature('Le Laborantin chef', nom: laborantinChef),
              Signature('Le Gestionnaire de Stock', nom: gestionnaireStockLabo),
              Signature('La Directrice Administrative',
                  nom: directriceAdministrativeLabo, mention: 'Validation'),
            ]));
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // La consommation
  // -------------------------------------------------------------------------------------------------------------------------------------------

  Widget _consommation(BuildContext ctx, ContexteEcran c, List<Fiche> prods,
      CollectionMagasin mouvements) {
    final per = _per;
    final depuis = catDepuis(c.aujourdhui, per.jours);
    final ids = {for (final p in prods) p['id']};
    final nomDe = {for (final p in prods) p['id']: '${p['designation']}'};
    final top = catPlusConsommes(mouvements.actives, ids, depuis);
    final classement = catClasserParValeur(prods);
    final parCategorie = <String, int>{};
    for (final p in prods) {
      final l = catLibelleCategorieReactif(p['categorie']);
      parCategorie[l] = (parCategorie[l] ?? 0) + 1;
    }
    final sorties = [
      for (final x in mouvements.actives)
        if (x['type'] == 'sortie' &&
            ids.contains(x['produitId']) &&
            (depuis == null ||
                ('${x['date'] ?? ''}'.length > 10
                        ? '${x['date']}'.substring(0, 10)
                        : '${x['date'] ?? ''}')
                        .compareTo(depuis) >=
                    0))
          x
    ];
    final serie = parMois(sorties, 'date', champValeur: 'quantite', ref: c.aujourdhui);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
            commande(_periode, largeur: 220),
            BoutonSigh(
                libelle: 'Bon d’expression de besoins',
                icone: LucideIcons.printer,
                variante: VarianteBouton.secondaire,
                onPressed: () => c.aller('m7-besoins')),
          ])),
      const SizedBox(height: 16),
      troisColonnes([
        CarteSigh(
            titre: 'Les plus consommés — ${per.libelle.toLowerCase()}',
            child: top.isEmpty
                ? const VideSigh('Aucune sortie sur la période.',
                    icone: LucideIcons.packageX)
                : ClassementCat(
                    lignes: [
                      for (final t in top)
                        (
                          libelle: nomDe[t.produitId] ?? t.produitId,
                          valeur: t.quantite,
                          alerte: false
                        )
                    ],
                    format: (v) => '${nombre(v)} unité(s)')),
        CarteSigh(
            titre: 'Valeur du stock par référence',
            child: ClassementCat(
                lignes: [
                  for (final p in classement)
                    (
                      libelle: '${p['designation']}',
                      valeur: catValeurReactif(p),
                      alerte: catSousSeuilTeinte(p)
                    )
                ],
                format: (v) => money(v, avecDevise: false))),
        CarteSigh(
            titre: 'Réactifs et consommables',
            child: GraphiqueAnneau(
                etiquettes: parCategorie.keys.toList(),
                valeurs: parCategorie.values.toList(),
                couleurs: const [JetonsShell.navy900, JetonsShell.navy400])),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Consommation au fil des mois',
          child: GraphiqueBarres(
              etiquettes: serie.etiquettes,
              hauteur: 240,
              series: [
                SerieGraphique('Unités consommées', serie.valeurs,
                    couleur: JetonsShell.navy600)
              ])),
      const SizedBox(height: 16),
      const NoteSigh(
          'Une référence dont le classement de valeur apparaît en rouge est sous son seuil d’alerte : c’est du stock immobilisé sur un article qui va manquer. Le rapprochement des deux classements — le plus consommé et le plus immobilisé — désigne les réapprovisionnements à passer en premier.'),
    ]);
  }
}
