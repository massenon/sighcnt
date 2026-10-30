import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';
import 'bouton.dart';
import 'carte.dart';

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

/// `K.miniTable` : petit tableau de lecture (en-têtes 12 en 600 majuscules, lignes à filet), sans tri ni pagination.
class MiniTableauSigh extends StatelessWidget {
  const MiniTableauSigh(
      {super.key,
      required this.colonnes,
      required this.lignes,
      this.vide = 'Aucune donnée.'});
  final List<ColonneMini> colonnes;
  final List<Fiche> lignes;
  final String vide;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty)
      return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text(vide,
                  style: const TextStyle(
                      color: JetonsShell.slate500, fontSize: 14))));
    Widget cel(Widget w, {bool tete = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: w);
    return Table(
        columnWidths: {
          for (var i = 0; i < colonnes.length; i++)
            i: const IntrinsicColumnWidth(flex: 1)
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
              decoration: const BoxDecoration(
                  color: JetonsShell.slate50,
                  border:
                      Border(bottom: BorderSide(color: JetonsShell.slate200))),
              children: [
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
          for (final r in lignes)
            TableRow(
                decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: JetonsShell.slate100))),
                children: [
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
        ]);
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
    if (idx >= 0 && idx < nb)
      b[idx] += champValeur != null
          ? (r[champValeur] is num
              ? r[champValeur] as num
              : num.tryParse('${r[champValeur]}') ?? 0)
          : 1;
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
