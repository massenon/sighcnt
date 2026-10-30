import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'points_commun.dart';

/// `m6-point-ventes` — « Suivi des ventes ». Un écran CALCULÉ : le point se lit selon QUATRE axes (période, client, article, groupe) sur la MÊME
/// population de lignes de facture. Les états imprimés portent les trois parts : celle de l'assureur (une créance sur un tiers), celle que la
/// clinique supporte pour ses agents (que personne ne doit) et la remise (qui diminue la base). Toute la règle vit dans `packages/domaine`
/// (`points.dart`), rejouée sur les vecteurs de la maquette ; cet écran ne fait que filtrer, afficher et imprimer.
class EcranPointVentes extends StatefulWidget with EcranMaquette {
  const EcranPointVentes({super.key});

  @override
  String get titre => 'Suivi des ventes';

  @override
  String get description =>
      'Ventes de la caisse par période, par client, par article et par groupe de prestation, avec impression détaillée ou globale.';

  @override
  String get regle =>
      'Le point se lit selon quatre axes — période, client, article, groupe — sur la même population de lignes. Les états imprimés portent les trois parts : celle de l’assureur (une créance sur un tiers), celle prise en charge par l’établissement pour ses agents (que personne ne doit) et la remise accordée (qui diminue la base). Les confondre empêcherait de répondre à la question du guichet.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Point du stock',
          icone: LucideIcons.warehouse,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m6-point-stock')),
    ];
  }

  @override
  State<EcranPointVentes> createState() => _EtatPointVentes();
}

class _EtatPointVentes extends State<EcranPointVentes> {
  ControleurFormulaire? _periode, _date, _libre, _du, _au;
  ControleurFormulaire? _clients, _groupes, _articles;
  Map<String, String> _libellesClients = {}, _libellesArticles = {};
  List<ControleurFormulaire> get _tous =>
      [_periode!, _date!, _libre!, _du!, _au!, _clients!, _groupes!, _articles!];

  void _surChangement() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_periode != null) return;
    final c = ContexteEcran.of(context);
    final auj = c.aujourdhui;
    final jourAuj = DateTime(auj.year, auj.month, auj.day);

    // Les listes de choix viennent des factures (clients et désignations réellement vendus), triées comme `C.sortBy(…, 'label')`.
    final factures = c.magasin.collection('factures').actives;
    final clients = <String, String>{};
    final articles = <String, String>{};
    for (final f in factures) {
      final pid = f['patientId'];
      if (pid != null && pid != '' && !clients.containsKey('$pid')) {
        clients['$pid'] = '${f['patient'] ?? ''}';
      }
      for (final l in (f['lignes'] as List? ?? const [])) {
        final d = (l as Map)['designation'];
        if (d != null && d != '' && !articles.containsKey('$d')) {
          articles['$d'] = '$d';
        }
      }
    }
    final optClients = trierStable(clients.entries.toList(), (e) => e.value);
    final optArticles = trierStable(articles.entries.toList(), (e) => e.value);
    _libellesClients = clients;
    _libellesArticles = articles;

    ChampDef def(String nom, String libelle, TypeChamp type,
            {List<OptionChamp> options = const [], String? indicatif}) =>
        ChampDef(
            nom: nom,
            libelle: libelle,
            type: type,
            options: options,
            indicatif: indicatif,
            col: ColChamp.plein);

    _periode = champUnique(
        def('periode', 'Périodicité', TypeChamp.select, options: [
          for (final p in periodes) OptionChamp(p.id, p.label)
        ]),
        'mois');
    _date = champUnique(
        def('date', 'Arrêté au', TypeChamp.date), iso(jourAuj));
    _libre = champUnique(def('libre', 'Plage libre', TypeChamp.case_), false);
    _du = champUnique(
        def('du', 'Du', TypeChamp.date), iso(ajouterJours(jourAuj, -29)));
    _au = champUnique(def('au', 'Au', TypeChamp.date), iso(jourAuj));
    _clients = champUnique(
        def('clients', 'Client (un ou plusieurs)', TypeChamp.multiselect,
            options: [for (final e in optClients) OptionChamp(e.key, e.value)],
            indicatif: 'Tous les clients'),
        <String>[]);
    _groupes = champUnique(
        def('groupes', 'Groupe de prestation', TypeChamp.multiselect,
            options: [
              for (final g in groupesPrestation) OptionChamp(g.id, g.label)
            ],
            indicatif: 'Tous les groupes'),
        <String>[]);
    _articles = champUnique(
        def('articles', 'Article / prestation', TypeChamp.multiselect,
            options: [
              for (final e in optArticles) OptionChamp(e.key, e.value)
            ],
            indicatif: 'Tous les articles et prestations'),
        <String>[]);
    for (final k in _tous) {
      k.addListener(_surChangement);
    }
  }

  @override
  void dispose() {
    if (_periode != null) {
      for (final k in _tous) {
        k.removeListener(_surChangement);
        k.dispose();
      }
    }
    super.dispose();
  }

  // --- Les données ---------------------------------------------------------------------------------------------------

  bool get _modeLibre => _libre!['libre'] == true;

  Bornes _bornes(DateTime auj) => _modeLibre
      ? bornesLibres(jourSaisi(_du!['du'], auj), jourSaisi(_au!['au'], auj))
      : bornes('${_periode!['periode']}', jourSaisi(_date!['date'], auj));

  List<String> get _selClients => choix(_clients!['clients']);
  List<String> get _selGroupes => choix(_groupes!['groupes']);
  List<String> get _selArticles => choix(_articles!['articles']);

  List<LigneVendue> _lignes(ContexteEcran c, Bornes b) {
    final secteurs = secteursDesActes(c.magasin.collection('actes').toutes);
    final toutes = lignesVendues(c.magasin.collection('factures').actives, b,
        secteurParCode: secteurs);
    return filtrerVentes(toutes,
        clients: _selClients, groupes: _selGroupes, articles: _selArticles);
  }

  void _reinitialiser() {
    _clients!.poser('clients', <String>[]);
    _groupes!.poser('groupes', <String>[]);
    _articles!.poser('articles', <String>[]);
  }

  /// Les filtres EN FORCE, relevés comme `P.etat` les relève sur la page : listes, dates et listes à choix retenues.
  List<(String, String)> _filtresEnForce(DateTime auj) {
    final p = periodes.firstWhere((x) => x.id == '${_periode!['periode']}');
    return [
      ('Périodicité', p.label),
      if ('${_date!['date']}'.isNotEmpty)
        ('Arrêté au', dateFR(jourSaisi(_date!['date'], auj))),
      if ('${_du!['du']}'.isNotEmpty)
        ('Du', dateFR(jourSaisi(_du!['du'], auj))),
      if ('${_au!['au']}'.isNotEmpty)
        ('Au', dateFR(jourSaisi(_au!['au'], auj))),
      if (_selClients.isNotEmpty)
        ('Client (un ou plusieurs)', resumeChoix(_selClients, _libellesClients)),
      if (_selGroupes.isNotEmpty)
        (
          'Groupe de prestation',
          resumeChoix(_selGroupes,
              {for (final g in groupesPrestation) g.id: g.label})
        ),
      if (_selArticles.isNotEmpty)
        (
          'Article / prestation',
          resumeChoix(_selArticles, _libellesArticles)
        ),
    ];
  }

  void _imprimer(BuildContext ctx, String mode, List<LigneVendue> lignes,
      Bornes b, DateTime auj) {
    final e = etatVentes(mode, lignes, b,
        clients: _selClients.length,
        groupes: _selGroupes.length,
        articles: _selArticles.length);
    imprimerPoint(ctx, e, filtres: _filtresEnForce(auj));
  }

  // --- L'écran -------------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final auj = c.aujourdhui;
    final jourAuj = DateTime(auj.year, auj.month, auj.day);
    return ListenableBuilder(
      listenable: c.magasin.collection('factures'),
      builder: (context, _) {
        final b = _bornes(jourAuj);
        final lignes = _lignes(c, b);
        final t = cumuler(lignes);
        final libre = _modeLibre;

        Widget barre() => CarteSigh(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          commande(_periode!, largeur: 190, inactive: libre),
                          commande(_date!, largeur: 160, inactive: libre),
                          SizedBox(width: 130, child: commande(_libre!)),
                          commande(_du!, largeur: 160, inactive: !libre),
                          commande(_au!, largeur: 160, inactive: !libre),
                        ]),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (_, k) {
                      final trois = k.maxWidth >= 768;
                      final l = trois ? (k.maxWidth - 24) / 3 : k.maxWidth;
                      return Wrap(spacing: 12, runSpacing: 12, children: [
                        commande(_clients!, largeur: l),
                        commande(_groupes!, largeur: l),
                        commande(_articles!, largeur: l),
                      ]);
                    }),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      BoutonSigh(
                          libelle: 'Point détaillé',
                          icone: LucideIcons.printer,
                          onPressed: () =>
                              _imprimer(context, 'detaille', lignes, b, jourAuj)),
                      BoutonSigh(
                          libelle: 'Point global',
                          icone: LucideIcons.printer,
                          variante: VarianteBouton.secondaire,
                          onPressed: () =>
                              _imprimer(context, 'global', lignes, b, jourAuj)),
                      BoutonSigh(
                          libelle: 'Point par patient',
                          icone: LucideIcons.users,
                          variante: VarianteBouton.secondaire,
                          onPressed: () =>
                              _imprimer(context, 'patient', lignes, b, jourAuj)),
                      BoutonSigh(
                          libelle: 'Réinitialiser les filtres',
                          icone: LucideIcons.rotateCcw,
                          variante: VarianteBouton.secondaire,
                          taille: TailleBouton.sm,
                          onPressed: _reinitialiser),
                    ]),
                  ]),
            );

        const tons = {
          'Facturé brut': (LucideIcons.receipt, TonSigh.navy),
          'Remises accordées': (LucideIcons.percent, TonSigh.neutre),
          'Facturé net': (LucideIcons.wallet, TonSigh.info),
          'Part assureur': (LucideIcons.shield, TonSigh.info),
          'Prise en charge du personnel':
              (LucideIcons.badgeCheck, TonSigh.neutre),
          'Encaissé': (LucideIcons.coins, TonSigh.succes),
          'Reste dû par les patients': (LucideIcons.hourglass, TonSigh.succes),
          'Articles vendus': (LucideIcons.package, TonSigh.navy),
        };
        final kpis = [
          for (final k in indicateursVentes(t))
            () {
              final base = tons[k.libelle]!;
              var ton = base.$2;
              if (k.libelle == 'Remises accordées' && t.remise != 0) {
                ton = TonSigh.attention;
              }
              if (k.libelle == 'Reste dû par les patients' && t.resteDu > 0) {
                ton = TonSigh.attention;
              }
              return KpiSigh(
                  libelle: k.libelle,
                  valeur: k.valeur,
                  icone: base.$1,
                  ton: ton,
                  indice: k.indice);
            }()
        ];

        // La maquette refait ses onglets à chaque filtre : on revient au premier (écart E43, porté fidèlement).
        final signature = [
          for (final k in _tous) '${k[k.champs.first.nom]}'
        ].join('|');

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              barre(),
              const SizedBox(height: 16),
              NoteSigh(
                  sansBalises(noteVentes(b, t,
                      clients: _selClients.length,
                      groupes: _selGroupes.length,
                      articles: _selArticles.length)),
                  icone: LucideIcons.calendarRange),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: kpis),
              const SizedBox(height: 16),
              OngletsSigh(key: ValueKey(signature), onglets: [
                OngletDef(
                    id: 'journal',
                    libelle: 'Journal des ventes',
                    compte: t.pieces,
                    construire: (_) => _journal(lignes)),
                OngletDef(
                    id: 'clients',
                    libelle: 'Par client',
                    construire: (_) => _clientsTab(lignes)),
                OngletDef(
                    id: 'patients',
                    libelle: 'Par patient',
                    compte: _selClients.isEmpty ? null : _selClients.length,
                    construire: (_) => _patients(lignes)),
                OngletDef(
                    id: 'articles',
                    libelle: 'Par article',
                    construire: (_) => _articlesTab(lignes)),
                OngletDef(
                    id: 'groupes',
                    libelle: 'Par groupe et famille',
                    construire: (_) => _groupesTab(lignes)),
                OngletDef(
                    id: 'evolution',
                    libelle: 'Évolution',
                    construire: (_) => _evolution(lignes, b)),
              ]),
            ]);
      },
    );
  }

  // --- 1. Le journal — une ligne par pièce ----------------------------------------------------------------------------

  Widget _journal(List<LigneVendue> lignes) => TableauSigh(
        lignes: journalVentes(lignes),
        taillePage: 20,
        nomExport: 'point-ventes-journal',
        colonnes: [
          ColonneTableau(
              cle: 'numero',
              libelle: 'Pièce',
              sansCoupure: true,
              texte: (r) => '${r['numero'] ?? ''}',
              rendu: (_, r) => Text('${r['numero'] ?? ''}',
                  style: styleTexte(
                      taille: 12,
                      police: 'LiberationMono',
                      couleur: JetonsShell.slate700))),
          ColonneTableau(
              cle: 'date',
              libelle: 'Date',
              sansCoupure: true,
              texte: (r) => dateTexte(r['date'])),
          _colClient(),
          const ColonneTableau(cle: 'nbLignes', libelle: 'Lignes', droite: true),
          colMontant('brut', 'Brut'),
          colMontantPc('remise', 'Remise',
              texte: (r) => n(r['remise']) != 0
                  ? '${m(r['remise'])} (${texteNombreJs(n(r['pcRemise']))} %)'
                  : '—',
              couleur: JetonsShell.warning700,
              pc: (r) => '${texteNombreJs(n(r['pcRemise']))} %'),
          colMontantPc('assureurM', 'Part assureur',
              texte: (r) => n(r['assureurM']) != 0
                  ? '${m(r['assureurM'])} (${texteNombreJs(n(r['pcAssureur']))} %)'
                  : '—',
              couleur: JetonsShell.info700,
              pc: (r) =>
                  '${texteNombreJs(n(r['pcAssureur']))} % · ${r['assureur'] ?? ''}'),
          colMontantPc('personnelM', 'Personnel',
              texte: (r) => n(r['personnelM']) != 0
                  ? '${m(r['personnelM'])} (${texteNombreJs(n(r['pcPersonnel']))} %)'
                  : '—',
              couleur: JetonsShell.slate700,
              pc: (r) => '${texteNombreJs(n(r['pcPersonnel']))} % — agent'),
          colMontant('encaisse', 'Payé',
              couleur: JetonsShell.success700, poids: FontWeight.w600),
          _colReste(),
        ],
      );

  ColonneTableau _colClient({bool agentOuAssureur = false}) => ColonneTableau(
      cle: 'patient',
      libelle: 'Client',
      texte: (r) => '${r['patient'] ?? ''}',
      rendu: (_, r) {
        final bas = agentOuAssureur
            ? '${r['code'] ?? ''}${r['agent'] == true ? ' · agent de la clinique' : (_vrai(r['assureur']) ? ' · ${r['assureur']}' : '')}'
            : '${r['code'] ?? ''}';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${r['patient'] ?? ''}',
                  style: styleTexte(
                      couleur: JetonsShell.slate800, poids: FontWeight.w500)),
              Text(bas,
                  style: styleTexte(taille: 10, couleur: JetonsShell.slate400)),
            ]);
      });

  ColonneTableau _colReste() => ColonneTableau(
      cle: 'reste',
      libelle: 'Reste dû',
      droite: true,
      texte: (r) => m(r['reste']),
      rendu: (_, r) => n(r['reste']) > 0
          ? Text(m(r['reste']),
              style: styleTexte(
                  couleur: JetonsShell.danger600, poids: FontWeight.w600))
          : tiret());

  static bool _vrai(Object? v) => v != null && v != '' && v != false;

  // --- 2. Par client ----------------------------------------------------------------------------------------------------

  Widget _clientsTab(List<LigneVendue> lignes) => TableauSigh(
        lignes: clientsVentes(lignes),
        taillePage: 20,
        nomExport: 'point-ventes-clients',
        colonnes: [
          _colClient(agentOuAssureur: true),
          const ColonneTableau(cle: 'pieces', libelle: 'Pièces', droite: true),
          const ColonneTableau(
              cle: 'quantite', libelle: 'Quantité', droite: true),
          colMontant('brut', 'Brut'),
          colMontantPc('remise', 'Remise',
              texte: (r) => '${texteNombreJs(n(r['pcRemise']))} %',
              couleur: JetonsShell.warning700,
              pc: (r) => '${texteNombreJs(n(r['pcRemise']))} %'),
          colMontantPc('assureurM', 'Assureur',
              texte: (r) => '${texteNombreJs(n(r['pcAssureur']))} %',
              couleur: JetonsShell.info700,
              pc: (r) => '${texteNombreJs(n(r['pcAssureur']))} %'),
          colMontantPc('personnelM', 'Personnel',
              texte: (r) => '${texteNombreJs(n(r['pcPersonnel']))} %',
              couleur: JetonsShell.slate700,
              pc: (r) => '${texteNombreJs(n(r['pcPersonnel']))} %'),
          colMontant('encaisse', 'Payé',
              couleur: JetonsShell.success700, poids: FontWeight.w600),
          _colReste(),
        ],
      );

  // --- 3. Par article — la QUANTITÉ vendue d'abord : c'est la question posée ---------------------------------------------

  Widget _articlesTab(List<LigneVendue> lignes) => TableauSigh(
        lignes: articlesVentes(lignes),
        taillePage: 25,
        nomExport: 'point-ventes-articles',
        filtres: [
          FiltreTableau(nom: 'groupe', libelle: 'Groupe', options: [
            for (final g in groupesPrestation) OptionChamp(g.label)
          ]),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'quantite',
              libelle: 'Quantité vendue',
              droite: true,
              texte: (r) => nombre(r['quantite']),
              rendu: (_, r) => Text(nombre(r['quantite']),
                  style: styleTexte(
                      couleur: JetonsShell.navy800, poids: FontWeight.w700))),
          const ColonneTableau(cle: 'designation', libelle: 'Article / prestation'),
          ColonneTableau(
              cle: 'categorie',
              libelle: 'Catégorie',
              texte: (r) => '${r['categorie']}',
              rendu: (_, r) => Align(
                  alignment: Alignment.centerLeft,
                  child: BadgeSigh('${r['categorie']}', ton: TonSigh.navy))),
          const ColonneTableau(cle: 'groupe', libelle: 'Groupe'),
          const ColonneTableau(cle: 'clients', libelle: 'Clients', droite: true),
          const ColonneTableau(cle: 'pieces', libelle: 'Pièces', droite: true),
          colMontant('pu', 'P.U.'),
          colMontant('brut', 'Brut'),
          colMontant('net', 'Net facturé', poids: FontWeight.w600),
          colMontant('encaisse', 'Encaissé', couleur: JetonsShell.success700),
        ],
      );

  // --- 4. Par groupe et par famille de catégorie ----------------------------------------------------------------------

  Widget _groupesTab(List<LigneVendue> lignes) {
    final rowsG = groupesVentes(lignes);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Par groupe de prestation',
          sansRemplissage: true,
          child: TableauSigh(
            lignes: rowsG,
            taillePage: 10,
            recherche: false,
            nomExport: 'point-ventes-groupes',
            colonnes: [
              const ColonneTableau(cle: 'groupe', libelle: 'Groupe'),
              ColonneTableau(
                  cle: 'quantite',
                  libelle: 'Quantité',
                  droite: true,
                  texte: (r) => nombre(r['quantite'])),
              const ColonneTableau(
                  cle: 'pieces', libelle: 'Pièces', droite: true),
              colMontant('brut', 'Brut'),
              colMontant('remise', 'Remise'),
              colMontant('net', 'Net', poids: FontWeight.w600),
              colMontant('encaisse', 'Encaissé',
                  couleur: JetonsShell.success700),
            ],
          )),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Par catégorie de prestation',
          sansRemplissage: true,
          child: TableauSigh(
            lignes: categoriesVentes(lignes),
            taillePage: 10,
            recherche: false,
            nomExport: 'point-ventes-categories',
            colonnes: [
              const ColonneTableau(cle: 'categorie', libelle: 'Catégorie'),
              ColonneTableau(
                  cle: 'quantite',
                  libelle: 'Quantité',
                  droite: true,
                  texte: (r) => nombre(r['quantite'])),
              colMontant('net', 'Net facturé'),
              colMontant('encaisse', 'Encaissé'),
            ],
          )),
      if (rowsG.isNotEmpty) ...[
        const SizedBox(height: 16),
        deuxColonnes([
          CarteSigh(
              titre: 'Poids des groupes dans le chiffre net',
              child: GraphiqueAnneau(
                  etiquettes: [for (final r in rowsG) '${r['groupe']}'],
                  valeurs: [for (final r in rowsG) n(r['net'])])),
        ]),
      ],
    ]);
  }

  // --- 5. L'évolution — le pas de découpage suit l'étendue demandée -----------------------------------------------------

  Widget _evolution(List<LigneVendue> lignes, Bornes b) {
    final ev = evolutionVentes(lignes, b);
    if (ev.vide) {
      return const VideSigh('Aucune vente sur la période retenue.',
          icone: LucideIcons.chartColumn);
    }
    return deuxColonnes([
      CarteSigh(
          titre: ev.titre,
          child: GraphiqueBarres(etiquettes: ev.etiquettes, series: [
            SerieGraphique('Net facturé', ev.net,
                couleur: JetonsShell.navy900),
            SerieGraphique('Encaissé', ev.encaisse,
                couleur: JetonsShell.success500),
          ])),
    ]);
  }

  // --- 6. Par patient — ce qui a été VENDU à chaque patient retenu, secteur par secteur -------------------------------------

  Widget _patients(List<LigneVendue> lignes) {
    if (_selClients.isEmpty) {
      return const NoteSigh(
          'Choisissez un ou plusieurs clients dans le filtre ci-dessus : cet onglet détaille, pour chacun, ce qui lui a été vendu secteur par secteur.',
          icone: LucideIcons.userSearch);
    }
    final blocs = blocsParPatient(lignes);
    if (blocs.isEmpty) {
      return const NoteSigh('Aucune vente sur la période pour les clients retenus.',
          ton: TonSigh.attention, icone: LucideIcons.inbox);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, p) in blocs.indexed) ...[
        if (i > 0) const SizedBox(height: 16),
        _carteSecteur(p),
      ]
    ]);
  }

  Widget _carteSecteur(BlocPatient p) {
    return Container(
      decoration: decorationCarte(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: JetonsShell.slate200))),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${p.patient}',
                        style: styleTexte(
                            couleur: JetonsShell.slate900,
                            poids: FontWeight.w600)),
                    Text(p.sousTitre,
                        style: styleTexte(
                            taille: 12, couleur: JetonsShell.slate500)),
                  ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Net facturé',
                    style: styleTexte(
                        taille: 12, couleur: JetonsShell.slate500)),
                Text(money(p.total.net),
                    style: styleTexte(
                        couleur: JetonsShell.slate900, poids: FontWeight.w600)),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, sec) in p.secteurs.indexed) ...[
                    if (i > 0) const SizedBox(height: 16),
                    Row(children: [
                      const Icon(LucideIcons.tag,
                          size: 16, color: JetonsShell.navy600),
                      const SizedBox(width: 8),
                      Text(sec.groupe.label,
                          style: styleTexte(
                              couleur: JetonsShell.slate800,
                              poids: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text(resumeSecteur(sec),
                          style: styleTexte(
                              taille: 12, couleur: JetonsShell.slate500)),
                    ]),
                    if (sec.lignes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      MiniTableauSigh(colonnes: [
                        for (final (j, e) in const [
                          'Date',
                          'Pièce',
                          'Désignation',
                          'Qté',
                          'Net',
                          'Part assureur',
                          'Payé',
                          'Reste dû'
                        ].indexed)
                          ColonneMini(e, (f) => (f['c'] as List)[j] as String,
                              droite: j >= 3),
                      ], lignes: [
                        for (final l in sec.lignes) {'c': cellulesLignePatient(l)}
                      ]),
                    ],
                  ],
                ]),
          ),
        ]),
      ),
    );
  }
}
