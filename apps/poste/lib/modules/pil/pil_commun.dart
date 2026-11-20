import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Briques communes des treize écrans de PILOTAGE (PIL). Les règles vivent dans `packages/domaine/lib/src/pilotage/` (symboles `pil*`, rejoués sur les
/// vecteurs tirés des écrans réels de la maquette) ; ici, ce que l'agent VOIT : la [PilVue] calculée par le domaine est peinte telle quelle, sans rien
/// recalculer. Tout est CALCULÉ depuis les registres, rien n'est fourni, et chaque proxy ou proposition SE DIT.

/// Les fiches actives (non archivées) d'un registre.
List<Fiche> pilActives(ContexteEcran c, String nom) => c.magasin.collection(nom).actives.toList();

/// Toutes les fiches (archivées comprises) d'un registre.
List<Fiche> pilToutes(ContexteEcran c, String nom) => c.magasin.collection(nom).toutes.toList();

/// Le repaint suit les registres que lit l'écran.
Listenable pilEcoute(ContexteEcran c, List<String> noms) => Listenable.merge([for (final n in noms) c.magasin.collection(n)]);

TonSigh pilTon(String t) => switch (t) {
      'navy' => TonSigh.navy,
      'succes' => TonSigh.succes,
      'info' => TonSigh.info,
      'attention' => TonSigh.attention,
      'danger' => TonSigh.danger,
      _ => TonSigh.neutre,
    };

/// La grille d'indicateurs (`U.kpiGrid`) : une icône par indicateur, dans l'ordre.
Widget pilKpis(List<PilKpi> kpis, List<IconData> icones, {int? colonnes}) => KpiGrilleSigh(colonnes: colonnes, kpis: [
      for (final (i, k) in kpis.indexed)
        KpiSigh(libelle: k.libelle, valeur: k.valeur, indice: k.indice, ton: pilTon(k.ton), icone: i < icones.length ? icones[i] : null)
    ]);

/// Un graphique du domaine, peint avec le kit (palette de la maquette).
Widget pilGraphique(PilGraphique g, {double hauteur = 260}) {
  final s = [
    for (final (i, x) in g.series.indexed)
      SerieGraphique(x.libelle, x.donnees, couleur: g.series.length > 1 ? paletteGraphique[(i * 3) % paletteGraphique.length] : null)
  ];
  switch (g.type) {
    case 'anneau':
      return GraphiqueAnneau(etiquettes: g.etiquettes, valeurs: g.series.isEmpty ? const [] : g.series.first.donnees, hauteur: hauteur);
    case 'ligne':
      return GraphiqueLigne(etiquettes: g.etiquettes, series: s, hauteur: hauteur);
    default:
      return GraphiqueBarres(etiquettes: g.etiquettes, series: s, hauteur: hauteur, horizontal: g.horizontal);
  }
}

/// `K.charts` : deux cartes côte à côte en large, empilées en dessous de 1024 px.
Widget pilDeux(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [SizedBox(width: l, child: a), SizedBox(width: l, child: b)]);
    });

const double pilEcart = 16;

/// Les enfants séparés d'un espace de 16 (`space-y-4`).
Widget pilPile(List<Widget> l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final (i, w) in l.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : pilEcart), child: w)]);

/// `K.ranking` : une barre par entrée, la plus longue vaut 100 %, jamais moins de 2 %.
class PilClassementSigh extends StatelessWidget {
  const PilClassementSigh(this.items, {super.key, this.format});
  final List<(String, num)> items;
  final String Function(num)? format;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const VideSigh('Aucune donnée.', icone: LucideIcons.chartColumn);
    final max = items.fold<num>(1, (a, e) => e.$2 > a ? e.$2 : a);
    return Column(key: const Key('pil:classement'), children: [
      for (final (i, e) in items.indexed)
        Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(child: Text(e.$1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
                const SizedBox(width: 12),
                Text(format != null ? format!(e.$2) : nombre(e.$2),
                    style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                      height: 6,
                      child: LayoutBuilder(
                          builder: (_, k) => Stack(children: [
                                Container(color: JetonsShell.slate100),
                                Container(width: k.maxWidth * ((e.$2 / max * 100).round().clamp(2, 100)) / 100, color: JetonsShell.navy500),
                              ])))),
            ])),
    ]);
  }
}

String _capitale(String h) => h.isEmpty ? h : h[0].toUpperCase() + h.substring(1).toLowerCase();

/// `K.miniTable` : un tableau du domaine (en-têtes en capitale initiale, la première colonne à gauche, les autres à droite).
Widget pilMiniTable(PilTable t, {String vide = 'Aucune donnée.', List<int> aGauche = const [0]}) {
  final lignes = <Fiche>[
    for (final l in t.lignes) {for (final (i, v) in l.indexed) '$i': v}
  ];
  return MiniTableauSigh(vide: vide, lignes: lignes, colonnes: [
    for (final (i, h) in t.entetes.indexed) ColonneMini(_capitale(h), (r) => '${r['$i']}', droite: !aGauche.contains(i))
  ]);
}

/// Une carte portant un tableau du domaine.
Widget pilCarteTable(PilTable t, {String? titre, String vide = 'Aucune donnée.'}) =>
    CarteSigh(titre: titre ?? t.titre, sansRemplissage: true, child: pilMiniTable(t, vide: vide));

/// Un champ du bandeau de filtres, relié au contrôleur commun : un `FormulaireSigh` à UN champ qui lit et écrit la valeur du contrôleur partagé.
class PilChamp extends StatefulWidget {
  const PilChamp(this.maitre, this.nom, {super.key});
  final ControleurFormulaire maitre;
  final String nom;
  @override
  State<PilChamp> createState() => _EtatPilChamp();
}

class _EtatPilChamp extends State<PilChamp> {
  late ControleurFormulaire _local;

  @override
  void initState() {
    super.initState();
    _local = ControleurFormulaire([widget.maitre.champs.firstWhere((x) => x.nom == widget.nom)], {widget.nom: widget.maitre[widget.nom]});
    _local.addListener(_versMaitre);
    widget.maitre.addListener(_depuisMaitre);
  }

  void _versMaitre() {
    final v = _local[widget.nom];
    if (widget.maitre[widget.nom] != v) widget.maitre.poser(widget.nom, v);
  }

  void _depuisMaitre() {
    final v = widget.maitre[widget.nom];
    if (_local[widget.nom] != v) {
      _local.removeListener(_versMaitre);
      _local.poser(widget.nom, v);
      _local.addListener(_versMaitre);
    }
  }

  @override
  void dispose() {
    widget.maitre.removeListener(_depuisMaitre);
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormulaireSigh(controleur: _local);
}

/// Le bandeau de filtres : une carte, une rangée de champs puis les commandes. [colonnes] : la largeur d'un champ est celle d'une grille de [colonnes]
/// colonnes (`lg:grid-cols-6`, 3 en dessous de 1024 px, 1 sous 768 px) ; sinon [largeur] fixe.
Widget pilBandeau(ControleurFormulaire f, List<String> noms, {double largeur = 200, int? colonnes, List<Widget> commandes = const []}) => CarteSigh(
    child: LayoutBuilder(builder: (_, k) {
      final n = colonnes == null ? 0 : (k.maxWidth >= 1024 ? colonnes : (k.maxWidth >= 768 ? (colonnes ~/ 2).clamp(1, colonnes) : 1));
      final l = colonnes == null ? largeur : (k.maxWidth - 12 * (n - 1)) / n;
      return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
        for (final nom in noms) SizedBox(width: l, child: PilChamp(f, nom)),
        ...commandes,
      ]);
    }));

/// La plage de dates « Du / au » des écrans de statistiques, avec « Toute la période » : une plage vide n'a pas de borne.
ControleurFormulaire pilControleurPlage({String du = 'Du', String au = 'au'}) => ControleurFormulaire([
      ChampDef(nom: 'du', libelle: du, type: TypeChamp.date),
      ChampDef(nom: 'au', libelle: au, type: TypeChamp.date),
    ]);

Widget pilBandeauPlage(ControleurFormulaire f) => pilBandeau(f, const ['du', 'au'], commandes: [
      BoutonSigh(
          key: const Key('pil:toute-periode'),
          libelle: 'Toute la période',
          icone: LucideIcons.x,
          taille: TailleBouton.sm,
          variante: VarianteBouton.secondaire,
          onPressed: () {
            f.poser('du', '');
            f.poser('au', '');
          }),
    ]);

/// Les bornes saisies (vides si la saisie n'est pas une date ISO).
String pilBorne(ControleurFormulaire f, String nom) => '${f[nom] ?? ''}';

/// Une note d'encadré (`K.note`), le texte étant celui du domaine.
Widget pilNote(String t, {TonSigh ton = TonSigh.info, IconData icone = LucideIcons.info}) => NoteSigh(t, ton: ton, icone: icone);

/// Un titre de source (`K.source`) : d'où viennent les chiffres.
Widget pilSource(String t) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(t, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)));
