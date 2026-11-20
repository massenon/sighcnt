import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';
import 'bouton.dart';
import 'carte.dart';
import 'sortie_tableau.dart';
import 'tableau.dart' show ColonneTableau;

/// `K.shortcuts` : cartes d'accès (icône 36 px sur navy-50, libellé 14 en 500, détail 12), 1 / 2 / 4 colonnes selon la largeur.
class RaccourciDef {
  const RaccourciDef(
      {required this.id,
      required this.icone,
      required this.libelle,
      this.detail});
  final String id;
  final IconData icone;
  final String libelle;
  final String? detail;
}

class RaccourcisSigh extends StatelessWidget {
  const RaccourcisSigh({super.key, required this.items, required this.aller});
  final List<RaccourciDef> items;
  final void Function(String id) aller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1024 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        final l = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final i in items)
            SizedBox(
              width: l,
              child: Semantics(
                button: true,
                label: i.libelle + (i.detail != null ? ', ${i.detail}' : ''),
                excludeSemantics: true,
                onTap: () => aller(i.id),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  hoverColor: JetonsShell.navy50,
                  onTap: () => aller(i.id),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: decorationCarte(),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color: JetonsShell.navy50,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Icon(i.icone,
                                  size: 16, color: JetonsShell.navy700)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(i.libelle,
                                    style: const TextStyle(
                                        color: JetonsShell.slate800,
                                        fontSize: 14,
                                        height: 20 / 14,
                                        fontWeight: FontWeight.w500)),
                                if (i.detail != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(i.detail!,
                                          style: const TextStyle(
                                              color: JetonsShell.slate500,
                                              fontSize: 12,
                                              height: 16 / 12))),
                              ])),
                        ]),
                  ),
                ),
              ),
            ),
        ]);
      });
}

class ColonneMini {
  const ColonneMini(this.libelle, this.valeur,
      {this.droite = false, this.rendu});
  final String libelle;
  final String Function(Fiche) valeur;
  final bool droite;
  final Widget Function(Fiche)? rendu;
}

/// `K.miniTable` : petit tableau de lecture (en-têtes 12 en 600 majuscules, lignes à filet), sans tri ni pagination. Lot EXP : l'encart a ses cases et sa
/// commande « Exporter » (lignes cochées ou tout l'encart ; .xlsx, CSV, impression) par le moteur commun de sortie (droit, limite, journal). Une cellule sort
/// sous le texte montré (`tabCelluleTexte` : une date jj/mm/aaaa en date, un nombre d'une colonne à droite en nombre).
class MiniTableauSigh extends StatefulWidget {
  const MiniTableauSigh(
      {super.key,
      required this.colonnes,
      required this.lignes,
      this.vide = 'Aucune donnée.',
      this.nomExport = 'encart'});
  final List<ColonneMini> colonnes;
  final List<Fiche> lignes;
  final String vide;
  final String nomExport;

  @override
  State<MiniTableauSigh> createState() => _MiniTableauSighState();
}

class _MiniTableauSighState extends State<MiniTableauSigh> {
  final Set<int> _coches = {};

  List<ColonneTableau> get _colonnesSortie => [
        for (var i = 0; i < widget.colonnes.length; i++)
          ColonneTableau(
              cle: 'c$i',
              libelle: widget.colonnes[i].libelle,
              droite: widget.colonnes[i].droite,
              valeur: (l) => tabCelluleTexte(widget.colonnes[i].valeur(l), droite: widget.colonnes[i].droite)),
      ];

  @override
  Widget build(BuildContext context) {
    final colonnes = widget.colonnes, lignes = widget.lignes, vide = widget.vide;
    if (_coches.any((i) => i >= lignes.length)) _coches.removeWhere((i) => i >= lignes.length);
    if (lignes.isEmpty) {
      return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text(vide,
                  style: const TextStyle(
                      color: JetonsShell.slate500, fontSize: 14))));
    }
    Widget cel(Widget w, {bool tete = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: w);
    Widget caseDe(bool coche, String libelle, ValueChanged<bool> changer) => Semantics(
        checked: coche,
        label: libelle,
        excludeSemantics: true,
        onTap: () => changer(!coche),
        child: InkWell(
            onTap: () => changer(!coche),
            child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                    color: coche ? JetonsShell.navy900 : Colors.white,
                    border: Border.all(color: coche ? JetonsShell.navy900 : JetonsShell.slate300),
                    borderRadius: BorderRadius.circular(4)),
                child: coche ? const Icon(LucideIcons.check, size: 12, color: Colors.white) : null)));
    final peut = droitSortie(context) != false;
    final n = _coches.length;
    final barre = Padding(
        key: const Key('kit:mini-barre'),
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (n > 0)
            Text('$n ligne${n > 1 ? 's' : ''} sélectionnée${n > 1 ? 's' : ''}',
                style: const TextStyle(color: JetonsShell.navy900, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500)),
          if (peut)
            BoutonSigh(
                key: const Key('kit:mini-exporter'),
                libelle: 'Exporter',
                icone: LucideIcons.download,
                taille: TailleBouton.sm,
                variante: VarianteBouton.fantome,
                onPressed: () => afficherFenetreSortie(context,
                    cochees: () => [for (var i = 0; i < lignes.length; i++) if (_coches.contains(i)) lignes[i]],
                    filtrees: () => lignes,
                    toutes: () => lignes,
                    filtreActif: false,
                    colonnes: () => _colonnesSortie,
                    nom: widget.nomExport,
                    cle: (l) => '${l['id'] ?? lignes.indexOf(l) + 1}')),
        ]));
    // Un encart posé dans un défilement horizontal reçoit une largeur INFINIE, qu'un étirement transformerait en contrainte impossible
    // (« BoxConstraints forces an infinite width ») : `_LargeurBornee` la ramène à la plus grande de sa largeur minimale et de sa largeur
    // intrinsèque, comme le faisait le tableau seul avant la barre d'export. Sous une largeur bornée, rien ne change.
    return _LargeurBornee(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      barre,
      Table(
        columnWidths: {
          0: const FixedColumnWidth(40),
          for (var i = 0; i < colonnes.length; i++)
            i + 1: const IntrinsicColumnWidth(flex: 1)
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
              decoration: const BoxDecoration(
                  color: JetonsShell.slate50,
                  border:
                      Border(bottom: BorderSide(color: JetonsShell.slate200))),
              children: [
                cel(Center(
                    child: caseDe(lignes.isNotEmpty && n == lignes.length, 'Tout sélectionner',
                        (v) => setState(() => v ? _coches.addAll([for (var i = 0; i < lignes.length; i++) i]) : _coches.clear())))),
                for (final c in colonnes)
                  cel(Align(
                      alignment: c.droite
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(c.libelle.toUpperCase(),
                          style: const TextStyle(
                              color: JetonsShell.slate500,
                              fontSize: 12,
                              height: 16 / 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6))))
              ]),
          for (final (k, r) in lignes.indexed)
            TableRow(
                decoration: BoxDecoration(
                    color: _coches.contains(k) ? JetonsShell.navy50 : null,
                    border: const Border(
                        bottom: BorderSide(color: JetonsShell.slate100))),
                children: [
                  cel(Center(child: caseDe(_coches.contains(k), 'Sélectionner la ligne', (v) => setState(() => v ? _coches.add(k) : _coches.remove(k))))),
                  for (final c in colonnes)
                    cel(Align(
                        alignment: c.droite
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: c.rendu != null
                            ? c.rendu!(r)
                            : Text(c.valeur(r),
                                style: const TextStyle(
                                    color: JetonsShell.slate700,
                                    fontSize: 14,
                                    height: 20 / 14,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ])))),
                ]),
        ]),
    ]));
  }
}

/// Sous une largeur infinie (défilement horizontal), borne la largeur de l'enfant à max(largeur minimale, largeur intrinsèque) ; sous une
/// largeur bornée, transmet les contraintes telles quelles. Les mesures intrinsèques traversent (aucun `LayoutBuilder`).
class _LargeurBornee extends SingleChildRenderObjectWidget {
  const _LargeurBornee({required Widget super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenduLargeurBornee();
}

class _RenduLargeurBornee extends RenderProxyBox {
  @override
  void performLayout() {
    var c = constraints;
    final enfant = child;
    if (enfant == null) {
      size = c.smallest;
      return;
    }
    if (!c.hasBoundedWidth) {
      final h = c.hasBoundedHeight ? c.maxHeight : double.infinity;
      final w = enfant.getMaxIntrinsicWidth(h);
      c = c.copyWith(maxWidth: w > c.minWidth ? w : c.minWidth);
    }
    enfant.layout(c, parentUsesSize: true);
    size = constraints.constrain(enfant.size);
  }
}

/// `K.parMois` : somme (ou compte) par mois sur les `nb` derniers mois, le mois de référence en dernier. Étiquettes « janv. 26 » (4 lettres + point).
({List<String> etiquettes, List<num> valeurs}) parMois(
    List<Fiche> rows, String champDate,
    {String? champValeur, int nb = 12, required DateTime ref}) {
  final etiq = <String>[];
  for (var i = nb - 1; i >= 0; i--) {
    final d = DateTime(ref.year, ref.month - i, 1);
    final mois = dateLong(d).split(' ')[1];
    etiq.add(
        '${mois.substring(0, mois.length < 4 ? mois.length : 4)}. ${(d.year % 100).toString().padLeft(2, '0')}');
  }
  final b = List<num>.filled(nb, 0);
  for (final r in rows) {
    final d = DateTime.tryParse('${r[champDate]}');
    if (d == null) continue;
    final diff = (ref.year - d.year) * 12 + (ref.month - d.month);
    final idx = nb - 1 - diff;
    if (idx >= 0 && idx < nb) {
      b[idx] += champValeur != null
          ? (r[champValeur] is num
              ? r[champValeur] as num
              : num.tryParse('${r[champValeur]}') ?? 0)
          : 1;
    }
  }
  return (etiquettes: etiq, valeurs: b);
}

/// Intitulé d'une section de tableau de bord avec action(s) à droite (`K.dash` : `title` + `actions`).
class SectionSigh extends StatelessWidget {
  const SectionSigh(
      {super.key,
      required this.titre,
      required this.child,
      this.actions = const []});
  final String titre;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => CarteSigh(
      titre: titre, actions: actions, sansRemplissage: true, child: child);
}

Widget lienVers(String libelle, VoidCallback f) => BoutonSigh(
    libelle: libelle,
    icone: LucideIcons.arrowRight,
    taille: TailleBouton.sm,
    variante: VarianteBouton.secondaire,
    onPressed: f);
