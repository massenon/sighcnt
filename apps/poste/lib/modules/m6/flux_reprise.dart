import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'flux_commun.dart';

/// `m6-reprise` — « Reprise SAGE 100 ». Le stock initial n'a pas été saisi : il provient de l'import de l'inventaire « Grand Stock » (SAGE 100, arrêté au 15/07/2026).
/// Chaque article conserve sa source, son lot d'import et sa quantité d'origine, afin de distinguer les données reprises des mouvements opérationnels ultérieurs.
///
/// Le document FAIT FOI sur ce qu'il porte ; la valorisation que la clinique saisit pour les références qu'il ne valorise pas est une SURCOUCHE (collection
/// `valorisationsSage`, datée et signée, source OBLIGATOIRE) — jamais une réécriture. Le référentiel (184 articles, catalogue tarifaire) est ENGENDRÉ depuis la
/// maquette (`ReferentielSage`) ; les prix ne sont jamais inventés.
class EcranReprise extends StatelessWidget with EcranMaquette {
  const EcranReprise({super.key});

  @override
  String get titre => 'Reprise SAGE 100';

  @override
  String get description =>
      'Traçabilité du lot de migration : inventaire « Grand Stock » repris comme situation initiale du stock.';

  @override
  String get regle =>
      'Le stock initial n’a pas été saisi manuellement : il provient de l’import de l’inventaire SAGE 100. Chaque article conserve sa source, son lot d’import et sa quantité d’origine, afin de distinguer les données reprises des mouvements opérationnels ultérieurs.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('valorisationsSage');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final ref = ReferentielSage.instance;
        final articles = ref.articles;
        final valo = col.actives;
        final k = kpisReprise(articles, valo);
        final lot = ref.lot;
        final concordant = ref.totalUnites == lot['totalUnites'];
        final tirage = DateTime.tryParse('${lot['dateTirage']}');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Articles repris',
                valeur: nombre(k.articles),
                icone: LucideIcons.package,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Unités en stock',
                valeur: nombre(k.unites),
                icone: LucideIcons.boxes,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Valeur reprise',
                valeur: money(k.valeur),
                icone: LucideIcons.wallet,
                ton: TonSigh.succes,
                indice: 'Valorisation CMUP'),
            KpiSigh(
                libelle: 'Articles non valorisés',
                valeur: nombre(k.nonValorises),
                icone: LucideIcons.circleHelp,
                ton: k.nonValorises > 0 ? TonSigh.attention : TonSigh.succes,
                indice: 'Prix de revient absent du document et non saisi'),
            KpiSigh(
                libelle: 'Valorisés par la clinique',
                valeur: nombre(k.valorisesParClinique),
                icone: LucideIcons.pencilLine,
                ton: k.valorisesParClinique > 0 ? TonSigh.info : TonSigh.neutre,
                indice: k.indiceValorises),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
            titre: 'Lot de migration',
            actions: [
              // La validation de la reprise ENGAGE le Gestionnaire de Stock et est journalisée : elle n'est pas offerte à qui ne fait que lire.
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Valider la reprise',
                    icone: LucideIcons.badgeCheck,
                    taille: TailleBouton.sm,
                    onPressed: () => _valider(context, c, articles.length, '${lot['reference']}')),
              BoutonSigh(
                  libelle: 'Éditer le bordereau',
                  icone: LucideIcons.printer,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => _bordereau(context, ref)),
            ],
            child: DescListeSigh([
              ('Référence du lot', cellMono('${lot['reference']}', taille: 14, couleur: JetonsShell.slate800)),
              ('Système d’origine', lot['source']),
              ('Document source', lot['document']),
              ('Date d’arrêté', dateDe(lot['dateArrete'])),
              ('Date de tirage', tirage == null ? '—' : dateHeure(tirage)),
              ('Tenue de compte', lot['devise']),
              ('Méthode de valorisation', '${lot['valorisation']} (coût unitaire moyen pondéré)'),
              ('Total du document', '${nombre(lot['totalUnites'])} unités — ${money(lot['totalValorise'])}'),
              (
                'Contrôle de cohérence',
                concordant
                    ? const BadgeSigh('Quantités concordantes', ton: TonSigh.succes)
                    : BadgeSigh('Écart de ${nombre((ref.totalUnites - n(lot['totalUnites'])).abs())} unités',
                        ton: TonSigh.danger)
              ),
              (
                'Validation Gestionnaire de Stock',
                lot['valideePar'] != null
                    ? BadgeSigh('${lot['valideePar']}', ton: TonSigh.succes)
                    : const BadgeSigh('En attente', ton: TonSigh.attention)
              ),
            ]),
          ),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(
                id: 'articles',
                libelle: 'Articles repris',
                compte: articles.length,
                construire: (ctx) => _articles(ref, valo)),
            OngletDef(
                id: 'anomalies',
                libelle: 'Points à traiter',
                compte: k.nonValorises,
                construire: (ctx) => _points(ctx, c, ref, valo)),
            OngletDef(
                id: 'rapprochement',
                libelle: 'Rapprochement au catalogue tarifaire',
                construire: (ctx) => _rapprochement(ref)),
          ]),
          const SourceFlux(
              'Inventaire « Grand Stock » — SAGE 100 Gestion commerciale 15.01, arrêté au 15/07/2026.'),
        ]);
      },
    );
  }

  Widget _articles(ReferentielSage ref, List<Fiche> valo) => TableauSigh(
        lignes: [
          for (final a in ref.articles)
            {
              'code': a.code,
              'designation': a.designation,
              'categorie': ref.categorieLabel(a.categorie),
              'idCategorie': a.categorie,
              'unite': a.unite,
              'quantite': a.quantite,
              'prUnitaire': a.prUnitaire,
              'prGlobal': a.prGlobal,
              'seuil': a.seuil,
              'valorise': a.valorise,
            }
        ],
        nomExport: 'reprise-sage',
        taillePage: 25,
        triInitial: 'code',
        filtres: [
          FiltreTableau(nom: 'idCategorie', libelle: 'Catégorie', options: [
            for (final e in ref.categories.entries) OptionChamp(e.key, e.value)
          ]),
          FiltreTableau(
              nom: 'valorise',
              libelle: 'Valorisation',
              options: const [OptionChamp('oui', 'Valorisés'), OptionChamp('non', 'Non valorisés')],
              correspond: (a, v) => v == 'oui' ? a['valorise'] == true : a['valorise'] != true),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'code',
              libelle: 'Référence SAGE',
              sansCoupure: true,
              texte: (a) => '${a['code']}',
              rendu: (_, a) => cellMono('${a['code']}', poids: FontWeight.w600, couleur: JetonsShell.navy800)),
          const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
          ColonneTableau(
              cle: 'categorie',
              libelle: 'Catégorie affectée',
              texte: (a) => '${a['categorie']}',
              rendu: (_, a) => BadgeSigh('${a['categorie']}', ton: TonSigh.navy)),
          const ColonneTableau(cle: 'unite', libelle: 'Unité'),
          const ColonneTableau(cle: 'quantite', libelle: 'Qté reprise', droite: true),
          ColonneTableau(
              cle: 'prUnitaire',
              libelle: 'P.R. unitaire (CMUP)',
              droite: true,
              texte: (a) => n(a['prUnitaire']) != 0 ? m(a['prUnitaire']) : '',
              rendu: (_, a) => n(a['prUnitaire']) != 0
                  ? Text(m(a['prUnitaire']), style: const TextStyle(fontSize: 14, color: JetonsShell.slate700))
                  : const BadgeSigh('À valoriser', ton: TonSigh.attention)),
          ColonneTableau(
              cle: 'prGlobal',
              libelle: 'P.R. global',
              droite: true,
              texte: (a) => m(a['prGlobal']),
              rendu: (_, a) => Text(m(a['prGlobal']),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800))),
          ColonneTableau(
              cle: 'seuil',
              libelle: 'Seuil proposé',
              droite: true,
              texte: (a) => nombre(a['seuil']),
              rendu: (_, a) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(nombre(a['seuil']), style: const TextStyle(fontSize: 14, color: JetonsShell.slate700)),
                    const SizedBox(width: 4),
                    const Tooltip(
                        message: 'Absent du document — à valider',
                        child: Icon(LucideIcons.circleHelp, size: 14, color: JetonsShell.warning500)),
                  ])),
        ],
      );

  Widget _points(BuildContext ctx, ContexteEcran c, ReferentielSage ref, List<Fiche> valo) {
    final aTraiter = ref.articles.where((a) => !a.valorise).toList();
    final unites = aTraiter.fold<num>(0, (t, a) => t + a.quantite);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          '${aTraiter.length} article(s) figurent à l’inventaire SAGE sans prix de revient unitaire, pour ${nombre(unites)} unités. Aucun document ne les tarife : le catalogue « Tarifs des médicaments » a lui aussi ses colonnes de prix vierges, et une seule de ces références y figure — sans montant. Les inventer fabriquerait une valeur de stock que personne n’a arrêtée.\nLa saisie est donc ouverte ici, référence par référence. Elle ne modifie pas le document SAGE, qui continue de faire foi sur ce qu’il porte : la valorisation est enregistrée à part, datée et signée.',
          ton: TonSigh.attention,
          icone: LucideIcons.circleHelp),
      const SizedBox(height: 12),
      TableauSigh(
        lignes: [
          for (final a in aTraiter)
            {
              'code': a.code,
              'designation': a.designation,
              'categorie': ref.categorieLabel(a.categorie),
              'quantite': a.quantite,
              'prixRevient': prixRevient(a, valo),
              'reste': resteSansPrix(a, valo),
              '_a': a,
            }
        ],
        nomExport: 'articles-non-valorises',
        taillePage: 20,
        filtres: [
          FiltreTableau(
              nom: 'traite',
              libelle: 'Traitement',
              options: const [OptionChamp('reste', 'Reste à valoriser'), OptionChamp('fait', 'Valorisé')],
              correspond: (a, v) => v == 'fait' ? a['reste'] != true : a['reste'] == true),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'code',
              libelle: 'Référence',
              sansCoupure: true,
              texte: (a) => '${a['code']}',
              rendu: (_, a) => cellMono('${a['code']}')),
          const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
          ColonneTableau(
              cle: 'categorie',
              libelle: 'Catégorie',
              texte: (a) => '${a['categorie']}',
              rendu: (_, a) => BadgeSigh('${a['categorie']}', ton: TonSigh.navy)),
          const ColonneTableau(cle: 'quantite', libelle: 'Quantité', droite: true),
          ColonneTableau(
              cle: 'prixRevient',
              libelle: 'Prix de revient',
              droite: true,
              valeur: (a) => a['prixRevient'] ?? -1,
              texte: (a) => a['prixRevient'] == null ? 'à saisir' : m(a['prixRevient']),
              rendu: (_, a) {
                final x = a['prixRevient'];
                if (x == null) return const BadgeSigh('à saisir', ton: TonSigh.attention);
                return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(m(x),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
                  Text('valeur : ${m(n(x) * n(a['quantite']))}',
                      style: const TextStyle(fontSize: 10, color: JetonsShell.slate400)),
                ]);
              }),
          ColonneTableau(
              cle: 'origine',
              libelle: 'Origine de la valeur',
              triable: false,
              texte: (a) {
                final v = valorisationDe(a['code'], valo);
                return v == null ? 'absente du document SAGE' : '${v['source'] ?? 'source non précisée'}';
              },
              rendu: (_, a) {
                final v = valorisationDe(a['code'], valo);
                if (v == null) {
                  return const Text('absente du document SAGE',
                      style: TextStyle(fontSize: 12, color: JetonsShell.slate400));
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${v['source'] ?? 'source non précisée'}',
                      style: const TextStyle(fontSize: 12, color: JetonsShell.slate600)),
                  Text('${v['auteur'] ?? 'inconnu'} — ${dateDe(v['date'])}',
                      style: const TextStyle(fontSize: 10, color: JetonsShell.slate400)),
                ]);
              }),
        ],
        actionsLigne: (cx, a) => [
          if (c.droit.editer)
            BoutonIcone(
                icone: a['reste'] == true ? LucideIcons.pencilLine : LucideIcons.rotateCcw,
                libelle: a['reste'] == true ? 'Valoriser' : 'Corriger la valorisation',
                onPressed: () => _saisirValorisation(cx, c, a['_a'] as ArticleSage)),
        ],
      ),
      const SizedBox(height: 12),
      const NoteSigh(
          'Le seuil d’alerte ne figure pas non plus dans le document SAGE. Le système propose 20 % de la quantité relevée (minimum 5 unités) ; ces valeurs doivent être arrêtées article par article avec le Gestionnaire de Stock et le Pharmacien avant la mise en service des alertes.',
          ton: TonSigh.info),
    ]);
  }

  Widget _rapprochement(ReferentielSage ref) {
    final lignes = ref.rapprochement();
    final absents = lignes.where((l) => l.correspondance == 'absente').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Désignations au catalogue',
            valeur: nombre(lignes.length),
            icone: LucideIcons.list,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Correspondances exactes',
            valeur: nombre(lignes.where((l) => l.correspondance == 'exacte').length),
            icone: LucideIcons.circleCheck,
            ton: TonSigh.succes),
        KpiSigh(
            libelle: 'Correspondances approchées',
            valeur: nombre(lignes.where((l) => l.correspondance == 'approchée').length),
            icone: LucideIcons.search,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Sans correspondance en stock',
            valeur: nombre(absents),
            icone: LucideIcons.circleHelp,
            ton: TonSigh.attention),
      ]),
      const SizedBox(height: 12),
      const NoteSigh(
          'Le catalogue « Tarifs des médicaments et accessoires » recense les articles vendables ; l’inventaire SAGE recense les articles détenus. Le rapprochement ci-dessous permet d’attribuer un prix à chaque désignation du catalogue à partir du CMUP relevé (RG-02 — vente au prix d’achat), et de repérer les articles du catalogue absents du stock.',
          ton: TonSigh.info),
      const SizedBox(height: 12),
      TableauSigh(
        lignes: [
          for (final l in lignes)
            {
              'n': l.n,
              'designation': l.designation,
              'article': l.article,
              'designationStock': l.designationStock,
              'cump': l.cump,
              'correspondance': l.correspondance,
            }
        ],
        nomExport: 'rapprochement-tarifs',
        taillePage: 25,
        filtres: const [
          FiltreTableau(nom: 'correspondance', libelle: 'Correspondance', options: [
            OptionChamp('exacte'),
            OptionChamp('approchée'),
            OptionChamp('absente'),
          ])
        ],
        colonnes: [
          const ColonneTableau(cle: 'n', libelle: 'N°', droite: true, sansCoupure: true),
          const ColonneTableau(cle: 'designation', libelle: 'Désignation au catalogue tarifaire'),
          ColonneTableau(
              cle: 'article',
              libelle: 'Réf. stock',
              sansCoupure: true,
              texte: (l) => l['article'] == null ? '—' : '${l['article']}',
              rendu: (_, l) => l['article'] != null
                  ? cellMono('${l['article']}')
                  : const Text('—', style: TextStyle(fontSize: 12, color: JetonsShell.slate400))),
          ColonneTableau(
              cle: 'designationStock',
              libelle: 'Désignation à l’inventaire',
              texte: (l) => '${l['designationStock'] ?? '—'}'),
          ColonneTableau(
              cle: 'cump',
              libelle: 'Prix proposé (CMUP)',
              droite: true,
              texte: (l) => l['cump'] != null ? m(l['cump']) : '',
              rendu: (_, l) => l['cump'] != null
                  ? Text(m(l['cump']),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800))
                  : const BadgeSigh('À fixer', ton: TonSigh.attention)),
          ColonneTableau(
              cle: 'correspondance',
              libelle: 'Correspondance',
              texte: (l) => switch (l['correspondance']) {
                    'exacte' => 'Exacte',
                    'approchée' => 'Approchée',
                    _ => 'Absente'
                  },
              rendu: (_, l) => switch (l['correspondance']) {
                    'exacte' => const BadgeSigh('Exacte', ton: TonSigh.succes),
                    'approchée' => const BadgeSigh('Approchée', ton: TonSigh.info),
                    _ => const BadgeSigh('Absente', ton: TonSigh.attention),
                  }),
        ],
      ),
    ]);
  }

  Future<void> _valider(BuildContext ctx, ContexteEcran c, int articles, String reference) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Valider la reprise du stock initial ?',
        message:
            'Cette validation atteste que le contrôle physique contradictoire a été réalisé et que les ${nombre(articles)} articles repris correspondent au stock effectivement détenu. Elle engage le Gestionnaire de Stock et est journalisée.',
        libelleOk: 'Valider la reprise');
    if (!ok || !ctx.mounted) return;
    c.magasin.journaliser('Validation', 'M6', 'LotImportStock', reference, null, {'valideePar': c.utilisateur});
    ToastsSigh.afficher(ctx, 'Reprise validée.',
        type: TypeToast.succes, detail: 'Le stock initial devient la situation de référence.');
  }

  /// Le bordereau : le total est refait depuis les lignes imprimées ; on ne totalise pas un prix de revient UNITAIRE (la somme de prix unitaires ne désigne aucune grandeur).
  PieceA4 pieceBordereau(ReferentielSage ref,
      {required String utilisateur, required DateTime edite, required String reference}) {
    final lot = ref.lot;
    return PieceA4(
      titre: 'Bordereau de reprise du stock initial',
      sousTitre: 'Import ${lot['reference']} — ${lot['document']}',
      reference: reference,
      utilisateur: utilisateur,
      edite: edite,
      cartouche: [
        ('Référence du lot', '${lot['reference']}'),
        ('Système d’origine', '${lot['source']}'),
        ('Date d’arrêté', dateDe(lot['dateArrete'])),
        ('Articles repris', nombre(ref.articles.length)),
        ('Unités', nombre(ref.totalUnites)),
        ('Valeur reprise', money(ref.totalValeur)),
      ],
      tableaux: [
        TableauEtat(
          libelleTotal: 'TOTAL GRAND STOCK',
          colonnes: [
            ColonneEtat(libelle: 'Référence', valeur: (a) => a['code']),
            ColonneEtat(libelle: 'Désignation', valeur: (a) => a['designation']),
            ColonneEtat(
                libelle: 'Qté en stock', valeur: (a) => a['quantite'], droite: true, somme: (a) => n(a['quantite'])),
            ColonneEtat(
                libelle: 'P.R. unitaire',
                valeur: (a) => n(a['prUnitaire']) != 0 ? m(a['prUnitaire']) : '',
                droite: true),
            ColonneEtat(
                libelle: 'P.R. global',
                valeur: (a) => n(a['prGlobal']) != 0 ? m(a['prGlobal']) : '',
                droite: true,
                somme: (a) => n(a['prGlobal'])),
          ],
          lignes: [
            for (final a in ref.articles)
              {
                'code': a.code,
                'designation': a.designation,
                'quantite': a.quantite,
                'prUnitaire': a.prUnitaire,
                'prGlobal': a.prGlobal,
              }
          ],
        ),
      ],
      signatures: const [
        Signature('Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri', mention: 'Contrôle physique'),
        Signature('Le Pharmacien', nom: 'DIEYABIDI Aïssatou'),
        Signature('La Directrice Administrative', nom: 'TAKI Alimatou', mention: 'Validation de la reprise'),
      ],
    );
  }

  Future<void> _bordereau(BuildContext ctx, ReferentielSage ref) {
    final c = ContexteEcran.of(ctx);
    return afficherApercu(
        ctx,
        pieceBordereau(ref,
            utilisateur: c.utilisateur,
            edite: c.aujourdhui,
            reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero())));
  }

  /// La saisie du prix de revient d'une référence que le document ne valorise pas. La SOURCE est obligatoire : un prix de revient sans origine est exactement le problème
  /// qu'on cherche à résoudre.
  void _saisirValorisation(BuildContext ctx, ContexteEcran c, ArticleSage article) {
    final col = c.magasin.collection('valorisationsSage');
    final ancienne = valorisationDe(article.code, col.actives);
    modaleSaisie(ctx,
        titre: '${ancienne != null ? 'Corriger la valorisation' : 'Valoriser'} — ${article.designation}',
        taille: TailleModale.md,
        entete: NoteSigh(
            '${article.designation} — ${nombre(article.quantite)} unité(s) en stock. Cette référence figure à l’inventaire SAGE sans prix de revient. La valeur saisie ici ne modifie pas le document : elle est enregistrée à part, avec son auteur et sa date, pour que l’audit distingue toujours ce que le document portait de ce que la clinique a décidé.',
            ton: TonSigh.info),
        champs: const [
          ChampDef(
              nom: 'prixRevient',
              libelle: 'Prix de revient unitaire (FCFA)',
              type: TypeChamp.nombre,
              requis: true,
              col: ColChamp.plein,
              aide: 'RG-02 — les médicaments se facturent au prix d’achat, sans marge.'),
          ChampDef(
              nom: 'source',
              libelle: 'Origine de la valeur',
              requis: true,
              col: ColChamp.plein,
              aide:
                  'Facture fournisseur, bon de commande, relevé de prix… Sans origine, la valeur ne se vérifie pas.'),
          ChampDef(
              nom: 'observation',
              libelle: 'Observation',
              type: TypeChamp.textarea,
              lignes: 2,
              col: ColChamp.plein),
        ],
        initial: ancienne ?? const {},
        libelleOk: ancienne != null ? 'Corriger' : 'Valoriser',
        icone: LucideIcons.check,
        surValider: (v) {
          final prix = n(v['prixRevient']);
          final fiche = ficheValorisation(article,
              prixRevient: prix,
              source: '${v['source']}',
              observation: '${v['observation'] ?? ''}',
              auteur: c.utilisateur,
              jour: iso(c.aujourdhui));
          if (ancienne != null) {
            col.mettreAJour(ancienne['id'], fiche);
          } else {
            col.inserer(fiche, prefixe: 'VSG');
          }
          ToastsSigh.afficher(ctx, 'Référence valorisée.',
              type: TypeToast.succes, detail: detailValorisation(article, prix));
          return true;
        });
  }
}
