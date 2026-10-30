import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import 'bouton.dart';
import 'carte.dart';
import 'formulaire.dart';
import 'modale.dart';

typedef Ligne = Map<String, Object?>;

class ColonneTableau {
  const ColonneTableau(
      {required this.cle,
      required this.libelle,
      this.droite = false,
      this.triable = true,
      this.valeur,
      this.rendu,
      this.sansCoupure = false,
      this.texte});
  final String cle;
  final String libelle;
  final bool droite;
  final bool triable;
  final Object? Function(Ligne)? valeur;
  final Widget Function(BuildContext, Ligne)? rendu;
  final bool sansCoupure;

  /// Texte exporté / recherché quand la cellule est un widget.
  final String Function(Ligne)? texte;

  Object? lire(Ligne l) => valeur != null ? valeur!(l) : l[cle];
  String enTexte(Ligne l) => texte != null ? texte!(l) : '${lire(l) ?? ''}';
}

class FiltreTableau {
  const FiltreTableau(
      {required this.nom,
      required this.libelle,
      required this.options,
      this.correspond});
  final String nom;
  final String libelle;
  final List<OptionChamp> options;
  final bool Function(Ligne, String)? correspond;
}

/// `U.dataTable` : carte `overflow-hidden` → barre d'outils → (barre de sélection) → tableau → pied (compteur + pagination).
/// Comportements repris de la maquette : recherche sans accents sur toutes les colonnes, filtres, tri à deux états,
/// colonnes configurables, export CSV, sélection multiple, pagination de 12, message d'état vide distinct selon qu'un filtre est actif.
class TableauSigh extends StatefulWidget {
  const TableauSigh({
    super.key,
    required this.colonnes,
    required this.lignes,
    this.titre,
    this.taillePage = 12,
    this.recherche = true,
    this.filtres = const [],
    this.selectionnable = false,
    this.actionsLigne,
    this.alClicLigne,
    this.messageVide = 'Aucun enregistrement.',
    this.indiceVide,
    this.triInitial,
    this.sensInitial = 'asc',
    this.nomExport = 'export',
    this.alExporter,
    this.actions = const [],
  });

  final List<ColonneTableau> colonnes;
  final List<Ligne> lignes;
  final String? titre;
  final int taillePage;
  final bool recherche;
  final List<FiltreTableau> filtres;
  final bool selectionnable;
  final List<Widget> Function(BuildContext, Ligne)? actionsLigne;
  final void Function(Ligne)? alClicLigne;
  final String messageVide;
  final String? indiceVide;
  final String? triInitial;
  final String sensInitial;
  final String nomExport;

  /// Reçoit `(nomDeFichier, contenuCsv)` : l'écriture du fichier appartient à la plateforme, pas au kit.
  final void Function(String nom, String csv)? alExporter;
  final List<Widget> actions;

  @override
  State<TableauSigh> createState() => TableauSighState();
}

class TableauSighState extends State<TableauSigh> {
  String _q = '';
  final Map<String, String> _filtres = {};
  String? _tri;
  String _sens = 'asc';
  int _page = 1;
  final Set<String> _caches = {};
  final Set<Object?> _selection = {};

  @override
  void initState() {
    super.initState();
    _tri = widget.triInitial;
    _sens = widget.sensInitial;
  }

  List<ColonneTableau> get _visibles =>
      widget.colonnes.where((c) => !_caches.contains(c.cle)).toList();

  /// Lignes après recherche, filtres et tri — c'est CE que l'état imprime et que l'export écrit.
  List<Ligne> get lignesFiltrees {
    var l = [...widget.lignes];
    if (_q.isNotEmpty)
      l = l
          .where(
              (r) => widget.colonnes.any((c) => correspond(c.enTexte(r), _q)))
          .toList();
    for (final e in _filtres.entries) {
      if (e.value.isEmpty) continue;
      final f = widget.filtres.firstWhere((x) => x.nom == e.key);
      l = l
          .where((r) => f.correspond != null
              ? f.correspond!(r, e.value)
              : '${r[e.key]}' == e.value)
          .toList();
    }
    if (_tri != null) {
      final c = widget.colonnes.where((c) => c.cle == _tri).firstOrNull;
      if (c != null) l = trierPar(l, c.lire, descendant: _sens == 'desc');
    }
    return l;
  }

  void _exporter() {
    final l = lignesFiltrees, v = _visibles;
    afficherModale<void>(context,
        titre: 'Exporter les données',
        taille: TailleModale.sm,
        corps: Text(
            'Choisir le format d’export des ${l.length} lignes filtrées.',
            style: const TextStyle(
                color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'CSV / Excel',
                  icone: LucideIcons.fileSpreadsheet,
                  variante: VarianteBouton.secondaire,
                  onPressed: () {
                    fermer();
                    widget.alExporter?.call(
                        '${widget.nomExport}-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
                        exporterCsv([
                          for (final c in v) c.libelle
                        ], [
                          for (final r in l) [for (final c in v) c.enTexte(r)]
                        ]));
                  }),
            ]);
  }

  void _colonnes() {
    afficherModale<void>(context,
        titre: 'Colonnes affichées',
        taille: TailleModale.sm,
        corps: StatefulBuilder(
            builder: (_, maj) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final c in widget.colonnes)
                    InkWell(
                      onTap: () {
                        setState(() => _caches.contains(c.cle)
                            ? _caches.remove(c.cle)
                            : _caches.add(c.cle));
                        maj(() {});
                      },
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                    color: _caches.contains(c.cle)
                                        ? Colors.white
                                        : JetonsShell.navy900,
                                    border: Border.all(
                                        color: _caches.contains(c.cle)
                                            ? JetonsShell.slate300
                                            : JetonsShell.navy900),
                                    borderRadius: BorderRadius.circular(4)),
                                child: _caches.contains(c.cle)
                                    ? null
                                    : const Icon(LucideIcons.check,
                                        size: 12, color: Colors.white)),
                            const SizedBox(width: 8),
                            Text(c.libelle,
                                style: const TextStyle(
                                    color: JetonsShell.slate700,
                                    fontSize: 14,
                                    height: 20 / 14)),
                          ])),
                    ),
                ])),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', onPressed: fermer)]);
  }

  bool get _filtreActif =>
      _q.isNotEmpty || _filtres.values.any((v) => v.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final toutes = lignesFiltrees;
    final pages = (toutes.length / widget.taillePage).ceil().clamp(1, 1 << 30);
    if (_page > pages) _page = pages;
    final debut = (_page - 1) * widget.taillePage;
    final page = toutes.skip(debut).take(widget.taillePage).toList();
    final cols = _visibles;

    return Container(
      key: const Key('kit:tableau'),
      decoration: decorationCarte(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _barre(),
              if (_selection.isNotEmpty) _barreSelection(),
              if (toutes.isEmpty)
                VideSigh(
                    _filtreActif
                        ? 'Aucun résultat pour cette recherche.'
                        : widget.messageVide,
                    indice: widget.indiceVide)
              else
                _table(cols, page),
              _pied(toutes.length, debut, pages),
            ]),
      ),
    );
  }

  Widget _barre() => Container(
        key: const Key('kit:tableau-barre'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: JetonsShell.slate200))),
        child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.titre != null)
                Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(widget.titre!,
                        style: const TextStyle(
                            color: JetonsShell.slate900,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w600))),
              if (widget.recherche)
                ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: 224,
                      maxWidth: widget.titre != null ? 320 : 480),
                  child: SizedBox(
                    width: 320,
                    child: Semantics(
                      textField: true,
                      label: 'Rechercher',
                      child: TextField(
                        key: const Key('kit:tableau-recherche'),
                        style: styleSaisie,
                        decoration: decorationChamp(
                            indicatif: 'Rechercher…',
                            prefixe: const Padding(
                                padding: EdgeInsets.only(left: 10, right: 6),
                                child: Icon(LucideIcons.search,
                                    size: 16, color: JetonsShell.slate400))),
                        onChanged: (v) => setState(() {
                          _q = v;
                          _page = 1;
                        }),
                      ),
                    ),
                  ),
                ),
              for (final f in widget.filtres)
                _FiltreListe(
                    f,
                    _filtres[f.nom] ?? '',
                    (v) => setState(() {
                          _filtres[f.nom] = v;
                          _page = 1;
                        })),
              BoutonSigh(
                  libelle: 'Colonnes',
                  icone: LucideIcons.columns3,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: _colonnes),
              BoutonSigh(
                  libelle: 'Exporter',
                  icone: LucideIcons.download,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: _exporter),
              ...widget.actions,
            ]),
      );

  Widget _barreSelection() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
            color: JetonsShell.navy50,
            border: Border(bottom: BorderSide(color: JetonsShell.navy200))),
        child: Row(children: [
          Text(
              '${_selection.length} ligne${_selection.length > 1 ? 's' : ''} sélectionnée${_selection.length > 1 ? 's' : ''}',
              style: const TextStyle(
                  color: JetonsShell.navy900,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          BoutonSigh(
              libelle: 'Tout désélectionner',
              variante: VarianteBouton.fantome,
              taille: TailleBouton.sm,
              onPressed: () => setState(_selection.clear)),
        ]),
      );

  Widget _table(List<ColonneTableau> cols, List<Ligne> page) {
    final colonnes = <int, TableColumnWidth>{};
    var i = 0;
    if (widget.selectionnable) colonnes[i++] = const FixedColumnWidth(40);
    for (var k = 0; k < cols.length; k++) {
      colonnes[i++] = const IntrinsicColumnWidth(flex: 1);
    }
    if (widget.actionsLigne != null)
      colonnes[i++] = const IntrinsicColumnWidth();
    return LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth),
                child: Table(
                  key: const Key('kit:tableau-table'),
                  columnWidths: colonnes,
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                        key: const ValueKey('kit:tableau-entete'),
                        decoration: const BoxDecoration(
                            color: JetonsShell.slate50,
                            border: Border(
                                bottom:
                                    BorderSide(color: JetonsShell.slate200))),
                        children: [
                          if (widget.selectionnable)
                            _cellule(
                                Center(
                                    child: _Cocher(
                                        page.isNotEmpty &&
                                            page.every((r) =>
                                                _selection.contains(r['id'])),
                                        'Tout sélectionner',
                                        (v) => setState(() {
                                              for (final r in page) {
                                                v
                                                    ? _selection.add(r['id'])
                                                    : _selection
                                                        .remove(r['id']);
                                              }
                                            }))),
                                tete: true),
                          for (final (i, col) in cols.indexed)
                            _tete(col,
                                cle: i == 0 && !widget.selectionnable
                                    ? const Key('kit:tableau-entete')
                                    : null),
                          if (widget.actionsLigne != null)
                            _cellule(
                                const Align(
                                    alignment: Alignment.centerRight,
                                    child: Text('ACTIONS', style: _styleTete)),
                                tete: true),
                        ]),
                    for (final r in page)
                      TableRow(
                          decoration: BoxDecoration(
                              color: _selection.contains(r['id'])
                                  ? JetonsShell.navy50
                                  : null,
                              border: const Border(
                                  bottom:
                                      BorderSide(color: JetonsShell.slate100))),
                          children: [
                            if (widget.selectionnable)
                              _cellule(Center(
                                  child: _Cocher(
                                      _selection.contains(r['id']),
                                      'Sélectionner la ligne',
                                      (v) => setState(() => v
                                          ? _selection.add(r['id'])
                                          : _selection.remove(r['id']))))),
                            for (final (i, col) in cols.indexed)
                              _cellule(
                                  cle: i == 0 &&
                                          !widget.selectionnable &&
                                          widget.actionsLigne == null &&
                                          identical(r, page.first)
                                      ? const Key('kit:tableau-ligne')
                                      : null,
                                  InkWell(
                                      onTap: widget.alClicLigne == null
                                          ? null
                                          : () => widget.alClicLigne!(r),
                                      child: Align(
                                          alignment: col.droite
                                              ? Alignment.centerRight
                                              : Alignment.centerLeft,
                                          child: col.rendu != null
                                              ? col.rendu!(context, r)
                                              : Text(
                                                  col.enTexte(r).isEmpty
                                                      ? '—'
                                                      : col.enTexte(r),
                                                  softWrap: !col.sansCoupure,
                                                  style: TextStyle(
                                                      color:
                                                          JetonsShell.slate700,
                                                      fontSize: 14,
                                                      height: 20 / 14,
                                                      fontFeatures: col.droite
                                                          ? const [
                                                              FontFeature
                                                                  .tabularFigures()
                                                            ]
                                                          : null))))),
                            if (widget.actionsLigne != null)
                              _cellule(
                                  cle: identical(r, page.first)
                                      ? const Key('kit:tableau-ligne')
                                      : null,
                                  Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final a
                                            in widget.actionsLigne!(context, r))
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 4),
                                              child: a),
                                      ])),
                          ]),
                  ],
                ),
              ),
            ));
  }

  static const _styleTete = TextStyle(
      color: JetonsShell.slate500,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6);

  /// Cellule : px 12, py 10 (`px-3 py-2.5`).
  Widget _cellule(Widget w, {bool tete = false, Key? cle}) => TableCell(
      child: Padding(
          key: cle,
          // py 10 + le filet de 1 px de `border-b` (CSS l'ajoute à la hauteur de la ligne, Flutter non).
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          child: w));

  Widget _tete(ColonneTableau col, {Key? cle}) {
    final actif = _tri == col.cle;
    return _cellule(
        Semantics(
          sortKey: null,
          label: col.libelle +
              (actif
                  ? (_sens == 'asc' ? ', tri croissant' : ', tri décroissant')
                  : ''),
          button: col.triable,
          excludeSemantics: true,
          child: InkWell(
            onTap: !col.triable
                ? null
                : () => setState(() {
                      if (_tri == col.cle) {
                        _sens = _sens == 'asc' ? 'desc' : 'asc';
                      } else {
                        _tri = col.cle;
                        _sens = 'asc';
                      }
                    }),
            child: Align(
              alignment:
                  col.droite ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(col.libelle.toUpperCase(), style: _styleTete),
                if (actif)
                  Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                          _sens == 'asc'
                              ? LucideIcons.chevronUp
                              : LucideIcons.chevronDown,
                          size: 14,
                          color: JetonsShell.slate500)),
              ]),
            ),
          ),
        ),
        tete: true,
        cle: cle);
  }

  Widget _pied(int total, int debut, int pages) => Container(
        key: const Key('kit:tableau-pied'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: JetonsShell.slate200))),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            spacing: 12,
            children: [
              Text(
                  total == 0
                      ? 'Aucun enregistrement'
                      : 'Affichage de ${debut + 1} à ${(debut + widget.taillePage).clamp(0, total)} sur $total enregistrement${total > 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: JetonsShell.slate500,
                      fontSize: 12,
                      height: 16 / 12)),
              if (pages > 1) _pagination(pages),
            ]),
      );

  Widget _pagination(int pages) {
    var de = (_page - 2).clamp(1, pages);
    final a = (de + 4).clamp(1, pages);
    de = (a - 4).clamp(1, pages);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      BoutonSigh(
          icone: LucideIcons.chevronLeft,
          libelle: 'Page précédente',
          libelleVisible: false,
          taille: TailleBouton.sm,
          variante: VarianteBouton.secondaire,
          onPressed: _page == 1 ? null : () => setState(() => _page--)),
      for (var p = de; p <= a; p++)
        Padding(
            padding: const EdgeInsets.only(left: 4),
            child: BoutonSigh(
                libelle: '$p',
                taille: TailleBouton.sm,
                variante: p == _page
                    ? VarianteBouton.primaire
                    : VarianteBouton.secondaire,
                onPressed: () => setState(() => _page = p))),
      Padding(
          padding: const EdgeInsets.only(left: 4),
          child: BoutonSigh(
              icone: LucideIcons.chevronRight,
              libelle: 'Page suivante',
              libelleVisible: false,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed:
                  _page == pages ? null : () => setState(() => _page++))),
    ]);
  }
}

class _Cocher extends StatelessWidget {
  const _Cocher(this.coche, this.libelle, this.alChangement);
  final bool coche;
  final String libelle;
  final ValueChanged<bool> alChangement;
  @override
  Widget build(BuildContext context) => Semantics(
        checked: coche,
        label: libelle,
        excludeSemantics: true,
        onTap: () => alChangement(!coche),
        child: InkWell(
          onTap: () => alChangement(!coche),
          child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  color: coche ? JetonsShell.navy900 : Colors.white,
                  border: Border.all(
                      color:
                          coche ? JetonsShell.navy900 : JetonsShell.slate300),
                  borderRadius: BorderRadius.circular(4)),
              child: coche
                  ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
                  : null),
        ),
      );
}

/// Filtre de la barre : liste déroulante de 9 rem minimum, première entrée = le libellé du filtre (« tous »).
class _FiltreListe extends StatelessWidget {
  const _FiltreListe(this.def, this.valeur, this.alChangement);
  final FiltreTableau def;
  final String valeur;
  final ValueChanged<String> alChangement;

  @override
  Widget build(BuildContext context) {
    final courant = def.options.where((o) => o.valeur == valeur).firstOrNull;
    return Semantics(
      button: true,
      label: '${def.libelle}, ${courant?.libelle ?? 'tous'}',
      excludeSemantics: true,
      child: PopupMenuButton<String>(
        tooltip: def.libelle,
        onSelected: alChangement,
        itemBuilder: (_) => [
          PopupMenuItem(value: '', child: Text(def.libelle)),
          for (final o in def.options)
            PopupMenuItem(value: o.valeur, child: Text(o.libelle)),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 144),
          child: InputDecorator(
            decoration: decorationChamp(
                suffixe: const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(LucideIcons.chevronDown,
                        size: 16, color: JetonsShell.slate400))),
            child: Text(courant?.libelle ?? def.libelle, style: styleSaisie),
          ),
        ),
      ),
    );
  }
}
