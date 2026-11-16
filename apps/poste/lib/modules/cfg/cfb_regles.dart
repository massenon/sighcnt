import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart' show Fiche;
import '../../donnees/parametres_clinique_poste.dart';
import '../m14/commun_m14.dart' show libelleRole;
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';

/// `cfg-regles` — « Règles métier versionnées » : la matrice de traçabilité (chaque règle du système est rattachée au document de cadrage qui la fonde),
/// les règles de gestion RG-01 → RG-14, et le PARAMÈTRE de valorisation des sorties de stock (prix de vente ou CUMP) avec la mesure de ce qu'il change.
///
/// La méthode vit dans la collection `reglages` (fiche `valorisationSortie`) : une décision de la clinique, pas une préférence d'écran. Prix de vente par
/// défaut, comme l'annotation manuscrite du 30/12/2024 le demandait.
class EcranRegles extends StatelessWidget with EcranMaquette {
  const EcranRegles({super.key});
  @override
  String get titre => 'Règles métier versionnées';
  @override
  String get description => 'Matrice de traçabilité : chaque règle du système est rattachée au document de cadrage qui la fonde.';
  @override
  String get regle =>
      'Chaque donnée issue d’un document de cadrage est reliée à sa source (draf1 §23). Une nouvelle note de service crée une nouvelle version : l’historique antérieur demeure intact.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return cfaPile([
      cfaLectureSeule(c),
      const _CarteParametresClinique(),
      const _CarteValorisation(),
      _carteFamilles(c),
      cfaKpis(cfbKpisRegles()),
      _tableMatrice(context, c),
      _tableRegles(context, c),
      _carteVersions(c),
    ]);
  }

  Widget _carteFamilles(ContexteEcran c) => ListenableBuilder(
      listenable: c.magasin.collection('produits'),
      builder: (ctx, _) => CarteSigh(
          titre: 'Groupes et familles d’articles',
          child: cfaPile([
            cfbNote(
                'Les familles viennent du document : l’inventaire initial (reprise) « Grand Stock » classe ses articles en sept catégories. Les groupes, eux, ne figurent dans aucun document — ce regroupement en quatre ensembles est une proposition soumise à la Direction, et non une donnée reprise d’une source.',
                ton: 'warning',
                icone: LucideIcons.circleQuestionMark),
            MiniTableauSigh(colonnes: [
              ColonneMini('Groupe', (r) => '${r['groupe']}'),
              ColonneMini('Famille', (r) => '${r['famille']}'),
              ColonneMini('Articles', (r) => nombre(r['articles']), droite: true),
              ColonneMini('Quantité en stock', (r) => nombre(r['quantite']), droite: true),
              ColonneMini('Valeur', (r) => money(r['valeur'], avecDevise: false), droite: true),
            ], lignes: [
              for (final l in cfbParFamille(c.magasin.collection('produits').actives))
                {'groupe': l.groupe, 'famille': l.famille, 'articles': l.articles, 'quantite': l.quantite, 'valeur': l.valeur}
            ]),
          ], espace: 12)));

  Widget _tableMatrice(BuildContext context, ContexteEcran c) => TableauSigh(
        titre: 'Matrice « document collecté → rôle dans le logiciel »',
        lignes: [
          for (final s in cfbSourcesVerite) {'document': s.document, 'devient': s.devient, 'module': s.module, 'ecran': s.ecran, 'statut': s.statut}
        ],
        taillePage: 20,
        nomExport: 'sources-verite',
        colonnes: [
          const ColonneTableau(cle: 'document', libelle: 'Document collecté'),
          const ColonneTableau(cle: 'devient', libelle: 'Devient dans le logiciel'),
          ColonneTableau(cle: 'module', libelle: 'Module', rendu: (_, s) => BadgeSigh('${s['module']}', ton: TonSigh.navy)),
          ColonneTableau(
              cle: 'ecran',
              libelle: 'Écran',
              texte: (s) => cfaVrai(s['ecran']) ? 'Ouvrir' : '—',
              rendu: (_, s) => cfaVrai(s['ecran'])
                  ? BoutonSigh(libelle: 'Ouvrir', variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: () => c.aller('${s['ecran']}'))
                  : const Text('—', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400))),
          ColonneTableau(cle: 'statut', libelle: 'Statut', rendu: (_, s) => BadgeSigh('${s['statut']}', ton: cfaTon(cfbTonStatutSource('${s['statut']}')))),
        ],
      );

  Widget _tableRegles(BuildContext context, ContexteEcran c) => TableauSigh(
        titre: 'Règles de gestion transversales',
        lignes: [
          for (final r in cfbReglesGestion) {'code': r.code, 'regle': r.regle, 'module': r.module, 'ecran': r.ecran}
        ],
        taillePage: 20,
        nomExport: 'regles-gestion',
        colonnes: [
          ColonneTableau(
              cle: 'code',
              libelle: 'Code',
              sansCoupure: true,
              rendu: (_, r) => Text('${r['code']}',
                  style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.navy800))),
          const ColonneTableau(cle: 'regle', libelle: 'Règle appliquée'),
          ColonneTableau(cle: 'module', libelle: 'Module', rendu: (_, r) => BadgeSigh('${r['module']}', ton: TonSigh.navy)),
          ColonneTableau(
              cle: 'ecran',
              libelle: 'Écran d’application',
              texte: (r) => 'Voir',
              rendu: (_, r) => BoutonSigh(libelle: 'Voir', variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: () => c.aller('${r['ecran']}'))),
        ],
        actions: [
          BoutonSigh(
              libelle: 'Imprimer la matrice',
              icone: LucideIcons.printer,
              variante: VarianteBouton.secondaire,
              taille: TailleBouton.sm,
              onPressed: () => _imprimer(context, c)),
        ],
      );

  void _imprimer(BuildContext context, ContexteEcran c) => cfaImprimer(context,
      titre: 'Matrice de traçabilité des règles métier',
      sousTitre: 'Documents de cadrage et règles de gestion appliquées',
      cartouche: [
        ('Documents sources', nombre(cfbSourcesVerite.length)),
        ('Règles de gestion', nombre(cfbReglesGestion.length)),
        ('Date d’édition', dateFR(c.aujourdhui)),
        ('Établi par', acteur(c).nom),
      ],
      blocs: [
        BlocTableau(
            TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Document collecté', valeur: (l) => l['document']),
              ColonneEtat(libelle: 'Devient dans le logiciel', valeur: (l) => l['devient']),
              ColonneEtat(libelle: 'Module', valeur: (l) => l['module']),
              ColonneEtat(libelle: 'Statut', valeur: (l) => l['statut']),
            ], lignes: [
              for (final s in cfbSourcesVerite) {'document': s.document, 'devient': s.devient, 'module': s.module, 'statut': s.statut}
            ]),
            titre: 'Documents collectés et leur rôle dans le logiciel'),
        BlocTableau(
            TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Code', valeur: (l) => l['code']),
              ColonneEtat(libelle: 'Règle appliquée', valeur: (l) => l['regle']),
              ColonneEtat(libelle: 'Module', valeur: (l) => l['module']),
            ], lignes: [
              for (final r in cfbReglesGestion) {'code': r.code, 'regle': r.regle, 'module': r.module}
            ]),
            titre: 'Règles de gestion transversales'),
      ],
      signatures: const [cfaSignDa, cfaSignDm]);

  Widget _carteVersions(ContexteEcran c) {
    Fiche ligne(CfbNoteService n) => {'reference': n.reference, 'objet': n.objet, 'version': n.version, 'dateEffet': n.dateEffet, 'statut': n.statut, 'moteur': cfbMoteurPilote(n)};
    return CarteSigh(
        titre: 'Règles métier versionnées',
        actions: [cfbLien(c, 'm13-notes-service', 'Consulter les notes')],
        child: MiniTableauSigh(colonnes: [
          ColonneMini('Référence', (n) => '${n['reference']}',
              rendu: (n) => Text('${n['reference']}',
                  style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: JetonsShell.slate900))),
          ColonneMini('Objet', (n) => '${n['objet']}'),
          ColonneMini('Version', (n) => 'v${n['version']}', rendu: (n) => BadgeSigh('v${n['version']}', ton: TonSigh.navy)),
          ColonneMini('Date d’effet', (n) => dateFR(DateTime.parse('${n['dateEffet']}'))),
          ColonneMini('Statut', (n) => '${n['statut']}', rendu: (n) => BadgeSigh('${n['statut']}', ton: TonSigh.succes)),
          ColonneMini('Moteur piloté', (n) => '${n['moteur']}'),
        ], lignes: [
          ligne(cfbNs131),
          ligne(cfbNs132)
        ]));
  }
}

/// LOT PARAM-CLINIQUE (décisions 10 et 14 de la Direction du 15/11/2026) : la carte « Paramètres de clinique (datés) » de la maquette. Le préavis de péremption
/// (RG-05) et les deux bornes de la balance âgée, lus à la date au registre des paramètres (famille `clinique`, défauts semés) ; « Régler » est ABSENT sans le
/// geste réservé `regler_parametres_clinique` de la fiche RBAC, et le réglage refuse aussi (bornes, cohérence, motif, fileul : refus nommés).
class _CarteParametresClinique extends StatelessWidget {
  const _CarteParametresClinique();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection(parCollectionParametres);
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final auj = parametreDateIso(c.aujourdhui);
          final peut = c.donnees?.matrice.droitGeste(c.role, pcGesteRegler) ?? false;
          final versions = col.toutes;
          final lignes = <Fiche>[
            for (final d in pcDefinitions)
              {
                'id': d.cle,
                'libelle': d.libelle,
                'aide': d.aide,
                'valeur': pcValeur(versions, d.cle, auj),
                'depuis': _depuis(versions, d.cle, auj),
                'bornes': '${pcBornesDe(d.cle)!.min} à ${pcBornesDe(d.cle)!.max} jours',
                'aVenir': [
                  for (final v in versions)
                    if (v['cle'] == d.cle && v['statut'] != 'archive' && v['dateEffet'] != null && '${v['dateEffet']}'.compareTo(auj) > 0) '${v['valeur']} jours au ${dateFR(DateTime.parse('${v['dateEffet']}'))}'
                ].join(', '),
              }
          ];
          return CarteSigh(
              titre: 'Paramètres de clinique (datés)',
              child: cfaPile([
                cfbNote(
                    'Le préavis de péremption (RG-05) et les tranches de la balance âgée des créances sont des paramètres de la clinique, en base : une nouvelle valeur s’applique à partir de sa date d’effet, l’ancienne reste lisible ; alertes, tableaux de bord et états lisent la valeur en vigueur à leur date. Les bornes sont une proposition à valider. Réglage de la clinique, posé à la mère, jamais envoyé aux téléphones.${peut ? '' : ' Votre profil consulte sans régler (droit « Régler les paramètres de clinique » de la matrice).'}',
                    ton: 'info',
                    icone: LucideIcons.calendarClock),
                MiniTableauSigh(colonnes: [
                  ColonneMini('Paramètre', (r) => '${r['libelle']}',
                      rendu: (r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r['libelle']}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, fontWeight: FontWeight.w500)),
                            Text('${r['aide']}', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                          ])),
                  ColonneMini('En vigueur', (r) => '${nombre(r['valeur'])} jours', droite: true),
                  ColonneMini('Depuis', (r) => '${r['depuis']}'),
                  ColonneMini('Bornes', (r) => '${r['bornes']}'),
                  ColonneMini('Version à venir', (r) => '${r['aVenir']}'.isEmpty ? 'aucune' : '${r['aVenir']}'),
                  if (peut)
                    ColonneMini('', (r) => '',
                        rendu: (r) => BoutonSigh(
                            key: Key('regler-parametre:${r['id']}'),
                            libelle: 'Régler',
                            variante: VarianteBouton.secondaire,
                            taille: TailleBouton.sm,
                            onPressed: () => _regler(ctx, c, r))),
                ], lignes: lignes),
              ], espace: 12));
        });
  }

  /// « Depuis » : la date d'effet de la version en vigueur, ou « défaut semé » (version 0).
  static String _depuis(List<Fiche> versions, String cle, String auj) {
    final r = Parametres.resoudre(cle, [for (final f in versions) if (f['statut'] != 'archive' && f['cle'] == cle) Parametre.fromJson(f)], auj,
        definition: pcDefinitions.firstWhere((d) => d.cle == cle));
    final d = r.ok ? r.valeur!.dateEffet : null;
    return d == null ? 'défaut semé' : dateFR(DateTime.parse(d));
  }

  void _regler(BuildContext ctx, ContexteEcran c, Fiche r) {
    final form = ControleurFormulaire([
      ChampDef(nom: 'valeur', libelle: '${r['libelle']}', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'motif', libelle: 'Motif du changement (obligatoire)', type: TypeChamp.textarea, col: ColChamp.plein, lignes: 2),
    ], {'valeur': r['valeur'], 'dateEffet': parametreDateIso(c.aujourdhui)});
    afficherModale<void>(ctx,
        titre: 'Régler : ${r['libelle']}',
        sousTitre: 'Une NOUVELLE version, à partir de la date d’effet ; la version en vigueur reste lisible. ${r['aide']}',
        corps: FormulaireSigh(controleur: form),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: Key('enregistrer-parametre:${r['id']}'),
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final refus = reglerParametreClinique(c.magasin,
                        cle: '${r['id']}',
                        valeur: form['valeur'],
                        dateEffet: '${form['dateEffet'] ?? ''}'.length >= 10 ? '${form['dateEffet']}'.substring(0, 10) : '${form['dateEffet'] ?? ''}',
                        gesteAccorde: c.donnees?.matrice.droitGeste(c.role, pcGesteRegler) ?? false,
                        libelleRole: libelleRole(c.magasin, c.role),
                        motif: '${form['motif'] ?? ''}',
                        horloge: () => c.aujourdhui);
                    if (refus != null) {
                      ToastsSigh.afficher(ctx, 'Réglage refusé (${refus.code}).', type: TypeToast.erreur, detail: '${refus.motif} ${refus.geste}');
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Nouvelle version enregistrée.', type: TypeToast.succes);
                  }),
            ]);
  }
}

/// La carte « Valorisation des sorties de stock » : deux méthodes, celle en vigueur, la MESURE de ce qu'elle change sur le stock détenu.
class _CarteValorisation extends StatelessWidget {
  const _CarteValorisation();

  Future<void> _basculer(BuildContext ctx, ContexteEcran c, (String, String, String) o, String courante) async {
    if (o.$1 == courante || !c.droit.editer) return;
    final (titre, message) = cfbConfirmationValorisation(o);
    final ok = await confirmerSigh(ctx, titre: titre, message: message, libelleOk: 'Appliquer');
    if (!ok || !ctx.mounted) return;
    cfbPoserReglage(c.magasin, 'valorisationSortie', o.$1);
    c.magasin.journaliser('Paramétrage', 'M6', 'Valorisation des sorties', o.$1, {'methode': courante}, {'methode': o.$1});
    ToastsSigh.afficher(ctx, 'Sorties valorisées au ${o.$2.toLowerCase()}.', type: TypeToast.succes, detail: 'Applicable aux prochaines sorties de stock.');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final produits = c.magasin.collection('produits');
    return ListenableBuilder(
        listenable: Listenable.merge([c.magasin.collection('reglages'), produits]),
        builder: (ctx, _) {
          final methode = '${cfbReglage(c.magasin, 'valorisationSortie', cfbValorisationDefaut)}';
          final actifs = produits.actives;
          final (p1, p2) = cfbTextesEffet(cfbEffetValorisation(actifs), actifs.length);
          return CarteSigh(
              titre: 'Valorisation des sorties de stock',
              child: cfaPile([
                cfbNote(
                    'Annotation manuscrite de la réunion du 30/12/2024 : « Paramétrer pour que les produits sortent au Prix de Vente et non au CUMP ». La Direction demandait un paramètre — le voici, avec la mesure de ce qu’il change.',
                    icone: LucideIcons.fileCheck2),
                cfaPile([
                  for (final o in cfbOptionsValorisation) _ligneOption(ctx, c, o, methode),
                ], espace: 8),
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('EFFET MESURÉ SUR LE STOCK DÉTENU',
                          style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: JetonsShell.slate500)),
                      const SizedBox(height: 4),
                      Text(p1, style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
                      const SizedBox(height: 4),
                      Text(p2, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
                    ])),
              ], espace: 12));
        });
  }

  Widget _ligneOption(BuildContext ctx, ContexteEcran c, (String, String, String) o, String methode) {
    final actif = o.$1 == methode;
    return InkWell(
        key: Key('cfb:valo:${o.$1}'),
        borderRadius: BorderRadius.circular(8),
        // Sans le droit d'écrire, la méthode se LIT mais ne se bascule pas : la commande est absente (la maquette, elle, laisse tout profil la changer — E884).
        onTap: c.droit.editer ? () => _basculer(ctx, c, o, methode) : null,
        child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: actif ? JetonsShell.navy50 : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: actif ? JetonsShell.navy400 : JetonsShell.slate200)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: actif ? JetonsShell.navy700 : Colors.transparent, border: Border.all(color: actif ? JetonsShell.navy700 : JetonsShell.slate300, width: 2)),
                  child: actif ? const Icon(LucideIcons.check, size: 12, color: Colors.white) : null),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.$2, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
                const SizedBox(height: 2),
                Text(o.$3, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
              ])),
              if (actif) ...[const SizedBox(width: 12), const BadgeSigh('En vigueur', ton: TonSigh.succes)],
            ])));
  }
}
