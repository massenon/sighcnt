import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import 'badge.dart';
import 'bouton.dart';
import 'carte.dart';
import 'formulaire.dart';
import 'modale.dart';
import 'sortie_tableau.dart';
import 'ton.dart';

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
      this.texte,
      this.somme = false});
  final String cle;
  final String libelle;
  final bool droite;
  final bool triable;
  final Object? Function(Ligne)? valeur;
  final Widget Function(BuildContext, Ligne)? rendu;
  final bool sansCoupure;

  /// Texte exporté / recherché quand la cellule est un widget.
  final String Function(Ligne)? texte;

  /// Lot EXP : l'impression des lignes porte un total CALCULÉ de cette colonne sur les lignes imprimées (« non calculable » si une valeur n'est pas un nombre).
  final bool somme;

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
/// colonnes configurables, sortie (.xlsx, CSV, impression) des lignes cochées, filtrées ou de tout le tableau (lot EXP), sélection multiple PAR DÉFAUT et
/// gardée d'une page à l'autre, pagination de 12, message d'état vide distinct selon qu'un filtre est actif.
class TableauSigh extends StatefulWidget {
  const TableauSigh({
    super.key,
    required this.colonnes,
    required this.lignes,
    this.titre,
    this.taillePage = 12,
    this.recherche = true,
    this.filtres = const [],
    this.selectionnable = true,
    this.cleLigne,
    this.actionsLigne,
    this.alClicLigne,
    this.messageVide = 'Aucun enregistrement.',
    this.indiceVide,
    this.triInitial,
    this.sensInitial = 'asc',
    this.nomExport = 'export',
    this.alExporter,
    this.actions = const [],
    this.actionsGroupe,
    this.libelleRecherche = 'Rechercher…',
    this.rechercheExtra,
    this.indiceRecherche,
    this.noteRecherche,
  });

  /// `searchExtra` de `U.dataTable` : ce que la recherche lit EN PLUS des colonnes (observations, nom d'un fichier, texte extrait d'un PDF : lot D5). Sans accent ni casse, comme les colonnes.
  final String Function(Ligne)? rechercheExtra;

  /// `indiceRecherche` : ce que la recherche ne lit PAS (une pièce numérisée sans couche texte), dit sous « Aucun résultat » : jamais un vide qui se lit « il n'y a rien ».
  final String? Function(String recherche)? indiceRecherche;

  /// `noteRecherche(q, lignes)` : ce que les résultats ont de particulier (lot OCR-prep : « N résultats trouvés dans un texte lu par machine »), dit AU-DESSUS du tableau.
  final String? Function(String recherche, List<Ligne> lignes)? noteRecherche;

  final List<ColonneTableau> colonnes;
  final List<Ligne> lignes;
  final String? titre;
  final int taillePage;
  final bool recherche;
  final List<FiltreTableau> filtres;

  /// Lot EXP : les cases sont posées PAR DÉFAUT (Direction, 15/11/2026) ; `false` se déclare (aucun écran ne le fait aujourd'hui).
  final bool selectionnable;

  /// La clé de sélection d'une ligne : à défaut `id`, puis `code`, puis une empreinte du contenu (stable d'un rendu à l'autre).
  final String Function(Ligne)? cleLigne;
  final List<Widget> Function(BuildContext, Ligne)? actionsLigne;
  final void Function(Ligne)? alClicLigne;
  final String messageVide;
  final String? indiceVide;
  final String? triInitial;
  final String sensInitial;
  final String nomExport;
  final String libelleRecherche;

  /// Reçoit `(nomDeFichier, contenuCsv)` d'un export CSV, APRÈS le contrôle et le journal du moteur de sortie ; sans lui, le kit enregistre le fichier
  /// lui-même (`SortieTableauxPoste.enregistrer`). Le .xlsx et l'impression passent toujours par le moteur.
  final void Function(String nom, String csv)? alExporter;
  final List<Widget> actions;

  /// Commandes de la barre de sélection (`bulkActions`) : reçoivent les lignes sélectionnées (y compris celles que le filtre actif cache) et la fonction qui
  /// désélectionne.
  final List<Widget> Function(
      BuildContext, List<Ligne> selection, VoidCallback effacer)? actionsGroupe;

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
  final Set<String> _selection = {};

  String _cle(Ligne r) {
    if (widget.cleLigne != null) return widget.cleLigne!(r);
    final id = r['id'];
    if (id != null && '$id'.isNotEmpty) return '$id';
    final code = r['code'];
    if (code != null && '$code'.isNotEmpty) return 'code:$code';
    final s = r.entries.where((e) => e.value is String || e.value is num || e.value is bool || e.value == null).map((e) => '${e.key}=${e.value}').join('|');
    var h = 5381;
    for (final u in s.codeUnits) {
      h = ((h * 33) ^ u) & 0xFFFFFFFF;
    }
    return 'h:${h.toRadixString(36)}:${s.length}';
  }

  @override
  void initState() {
    super.initState();
    _tri = widget.triInitial;
    _sens = widget.sensInitial;
  }

  List<ColonneTableau> get _visibles =>
      widget.colonnes.where((c) => !_caches.contains(c.cle)).toList();

  List<Ligne> _trier(List<Ligne> l) {
    if (_tri != null) {
      final c = widget.colonnes.where((c) => c.cle == _tri).firstOrNull;
      if (c != null) return trierPar(l, c.lire, descendant: _sens == 'desc');
    }
    return l;
  }

  /// Toutes les lignes que l'écran a construites pour ce profil (« en masse » : toutes pages, sans filtre), dans l'ordre du tri affiché.
  List<Ligne> get toutesTriees => _trier([...widget.lignes]);

  /// Les lignes COCHÉES, y compris celles que le filtre actif cache (la sélection se garde jusqu'à ce que l'agent la vide, et le compte le dit).
  List<Ligne> get lignesCochees => [for (final r in toutesTriees) if (_selection.contains(_cle(r))) r];

  /// Lignes après recherche, filtres et tri — c'est CE que l'état imprime et que l'export écrit.
  List<Ligne> get lignesFiltrees {
    var l = [...widget.lignes];
    if (_q.isNotEmpty) {
      l = l
          .where((r) =>
              widget.colonnes.any((c) => correspond(c.enTexte(r), _q)) ||
              (widget.rechercheExtra != null && correspond(widget.rechercheExtra!(r), _q)))
          .toList();
    }
    for (final e in _filtres.entries) {
      if (e.value.isEmpty) continue;
      final f = widget.filtres.firstWhere((x) => x.nom == e.key);
      l = l
          .where((r) => f.correspond != null
              ? f.correspond!(r, e.value)
              : '${r[e.key]}' == e.value)
          .toList();
    }
    return _trier(l);
  }

  /// La fenêtre de sortie (périmètre puis format) : moteur commun, droit, limite, journal (lot EXP).
  void _exporter([String? perimetre]) => afficherFenetreSortie(context,
      cochees: () => lignesCochees,
      filtrees: () => lignesFiltrees,
      toutes: () => toutesTriees,
      filtreActif: _filtreActif,
      colonnes: () => _visibles,
      nom: widget.nomExport,
      titre: widget.titre ?? widget.nomExport,
      cle: _cle,
      perimetre: perimetre,
      alExporterCsv: widget.alExporter);

  Future<void> _imprimerSelection() async {
    final r = await sortirLignesPoste(context,
        format: 'impression', colonnes: _visibles, lignes: lignesCochees, perimetre: tabPerimetreSelection, nom: widget.nomExport, titre: widget.titre ?? widget.nomExport, cle: _cle);
    if (mounted) direSortie(context, r);
  }

  /// La commande « Exporter » est ABSENTE sans le droit (fiche RBAC) ; droits illisibles (aucune coque) : visible, le moteur refuse.
  bool get _peutSortir => droitSortie(context) != false;

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
              if (toutes.isNotEmpty && _q.trim().isNotEmpty && widget.noteRecherche != null)
                if (widget.noteRecherche!(_q, toutes) case final note?)
                  Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: NoteSigh(note, key: const Key('kit:note-recherche'), ton: TonSigh.attention, icone: LucideIcons.scanText)),
              if (toutes.isEmpty)
                VideSigh(
                    _filtreActif
                        ? 'Aucun résultat pour cette recherche.'
                        : widget.messageVide,
                    indice: _filtreActif && widget.indiceRecherche != null ? (widget.indiceRecherche!(_q) ?? widget.indiceVide) : widget.indiceVide)
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
                            indicatif: widget.libelleRecherche,
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
              if (_peutSortir)
                BoutonSigh(
                    key: const Key('kit:tableau-exporter'),
                    libelle: 'Exporter',
                    icone: LucideIcons.download,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: _exporter),
              ...widget.actions,
            ]),
      );

  Widget _barreSelection() {
    final coches = lignesCochees, filtrees = lignesFiltrees;
    final n = coches.length;
    final visibles = {for (final r in filtrees) _cle(r)};
    final hors = coches.where((r) => !visibles.contains(_cle(r))).length;
    final nonCochees = filtrees.where((r) => !_selection.contains(_cle(r))).length;
    return Container(
        key: const Key('kit:tableau-selection'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
            color: JetonsShell.navy50,
            border: Border(bottom: BorderSide(color: JetonsShell.navy200))),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(
              '$n ligne${n > 1 ? 's' : ''} sélectionnée${n > 1 ? 's' : ''}${hors > 0 ? ' (dont $hors hors du filtre actif)' : ''}',
              key: const Key('kit:tableau-compte-selection'),
              style: const TextStyle(
                  color: JetonsShell.navy900,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w500)),
          if (nonCochees > 0)
            BoutonSigh(
                key: const Key('kit:tableau-cocher-filtrees'),
                libelle: 'Cocher les ${filtrees.length} ligne${filtrees.length > 1 ? 's' : ''} filtrée${filtrees.length > 1 ? 's' : ''}',
                variante: VarianteBouton.fantome,
                taille: TailleBouton.sm,
                onPressed: () => setState(() => _selection.addAll(visibles))),
          if (_peutSortir) ...[
            BoutonSigh(
                key: const Key('kit:tableau-exporter-selection'),
                libelle: 'Exporter la sélection',
                icone: LucideIcons.download,
                variante: VarianteBouton.secondaire,
                taille: TailleBouton.sm,
                onPressed: () => _exporter(tabPerimetreSelection)),
            BoutonSigh(
                key: const Key('kit:tableau-imprimer-selection'),
                libelle: 'Imprimer la sélection',
                icone: LucideIcons.printer,
                variante: VarianteBouton.secondaire,
                taille: TailleBouton.sm,
                onPressed: _imprimerSelection),
          ],
          if (widget.actionsGroupe != null)
            for (final a in widget.actionsGroupe!(context, coches, () => setState(_selection.clear))) a,
          BoutonSigh(
              libelle: 'Tout désélectionner',
              variante: VarianteBouton.fantome,
              taille: TailleBouton.sm,
              onPressed: () => setState(_selection.clear)),
        ]),
      );
  }

  Widget _table(List<ColonneTableau> cols, List<Ligne> page) {
    final colonnes = <int, TableColumnWidth>{};
    var i = 0;
    if (widget.selectionnable) colonnes[i++] = const FixedColumnWidth(40);
    for (var k = 0; k < cols.length; k++) {
      colonnes[i++] = const IntrinsicColumnWidth(flex: 1);
    }
    if (widget.actionsLigne != null) {
      colonnes[i++] = const IntrinsicColumnWidth();
    }
    return LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // Largeur imposée : comme une table CSS, les colonnes se resserrent (retour à la ligne) avant que la table ne déborde.
                constraints:
                    BoxConstraints(minWidth: c.maxWidth, maxWidth: c.maxWidth),
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
                                                _selection.contains(_cle(r))),
                                        'Tout sélectionner',
                                        (v) => setState(() {
                                              for (final r in page) {
                                                v
                                                    ? _selection.add(_cle(r))
                                                    : _selection
                                                        .remove(_cle(r));
                                              }
                                            }))),
                                tete: true),
                          for (final (i, col) in cols.indexed)
                            _tete(col,
                                cle: i == 0
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
                              color: _selection.contains(_cle(r))
                                  ? JetonsShell.navy50
                                  : null,
                              border: const Border(
                                  bottom:
                                      BorderSide(color: JetonsShell.slate100))),
                          children: [
                            if (widget.selectionnable)
                              _cellule(Center(
                                  child: _Cocher(
                                      _selection.contains(_cle(r)),
                                      'Sélectionner la ligne',
                                      (v) => setState(() => v
                                          ? _selection.add(_cle(r))
                                          : _selection.remove(_cle(r)))))),
                            for (final (i, col) in cols.indexed)
                              _cellule(
                                  cle: i == 0 &&
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
                                          child: _avecMarquesDeLaMere(i, r, col.rendu != null
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
                                                          : null)))))),
                            if (widget.actionsLigne != null)
                              _cellule(
                                  cle: identical(r, page.first)
                                      ? const Key('kit:tableau-ligne')
                                      : null,
                                  // Les boutons d'une ligne ne se coupent pas : leur largeur minimale déclarée est leur largeur réelle
                                  // (IntrinsicWidth), sinon un tableau serré (une colonne de cases en plus) resserre la colonne des actions
                                  // sous la largeur des boutons et la ligne déborde ; ce sont les colonnes de texte qui reviennent à la ligne.
                                  IntrinsicWidth(
                                      child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final a
                                            in widget.actionsLigne!(context, r))
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 4),
                                              child: a),
                                      ]))),
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

  /// LOT IMP-D : une fiche écrite par l'import d'un fileul que la mère n'a pas encore confirmée porte `enAttenteMere` ; une fiche que la mère a refusée mais qu'une pièce émise utilise
  /// porte `refuseeParMere`. Les deux se LISENT sur la première colonne de TOUT tableau qui les liste, sans que chaque écran de référentiel ait à les connaître.
  Widget _avecMarquesDeLaMere(int colonne, Ligne r, Widget w) {
    if (colonne != 0) return w;
    final attente = '${r['enAttenteMere'] ?? ''}'.isNotEmpty, refusee = '${r['refuseeParMere'] ?? ''}'.isNotEmpty;
    if (!attente && !refusee) return w;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
      w,
      if (attente) const BadgeSigh('En attente de la mère', key: Key('kit:marque-attente-mere'), ton: TonSigh.attention),
      if (refusee) const BadgeSigh('Refusée par la mère', key: Key('kit:marque-refusee-mere'), ton: TonSigh.danger),
    ]);
  }

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
                Flexible(
                    child: Text(col.libelle.toUpperCase(), style: _styleTete)),
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

  /// `select.w-auto.min-w-[9rem]` : largeur du contenu le plus large (libellé du filtre ou option), plus le retrait
  /// gauche (12), le chevron et la bordure (34), jamais sous 144 px. Sans largeur propre, le champ prend toute la
  /// largeur offerte par le `Wrap` de la barre et chaque filtre se retrouve seul sur sa ligne.
  double _largeur(BuildContext context) {
    var texte = 0.0;
    for (final t in [def.libelle, for (final o in def.options) o.libelle]) {
      final p = TextPainter(
          text: TextSpan(text: t, style: styleSaisie),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1)
        ..layout();
      if (p.width > texte) texte = p.width;
    }
    return (texte + 12 + 34).clamp(144.0, 320.0).toDouble();
  }

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
        child: SizedBox(
          width: _largeur(context),
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
