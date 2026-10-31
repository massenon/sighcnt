import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/icones.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Gabarit commun des tableaux de bord par poste (`K.dash` de la maquette) : le premier regard, les parcours (`K.parcours`), les accès rapides
/// (`K.shortcuts`) et le bandeau d'alertes. Les dix écrans (`tba_*.dart`) ne portent que leur contenu.

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Icônes : celles de la maquette (Lucide) par leur NOM ; quelques-unes que le générateur d'icônes du poste n'a pas encore reprises.
// ---------------------------------------------------------------------------------------------------------------------------------------------

const _icones = <String, IconData>{
  'arrow-down-left': LucideIcons.arrowDownLeft,
  'arrow-right': LucideIcons.arrowRight,
  'arrow-up-right': LucideIcons.arrowUpRight,
  'book-open': LucideIcons.bookOpen,
  'calendar': LucideIcons.calendar,
  'calendar-x': LucideIcons.calendarX,
  'check': LucideIcons.check,
  'check-check': LucideIcons.checkCheck,
  'check-circle-2': LucideIcons.circleCheck,
  'download': LucideIcons.download,
  'file-clock': LucideIcons.fileClock,
  'file-pen-line': LucideIcons.filePenLine,
  'file-x': LucideIcons.fileX,
  'house-plus': LucideIcons.housePlus,
  'info': LucideIcons.info,
  'list': LucideIcons.list,
  'moon': LucideIcons.moon,
  'package-x': LucideIcons.packageX,
  'plus': LucideIcons.plus,
  'rotate-ccw': LucideIcons.rotateCcw,
  'tent': LucideIcons.tent,
  'test-tube': LucideIcons.testTube,
  'trending-down': LucideIcons.trendingDown,
  'user-minus': LucideIcons.userMinus,
  'alert-octagon': LucideIcons.octagonAlert,
  'scale-3d': LucideIcons.scale3d,
  'eye': LucideIcons.eye,
};

IconData tbaIcone(String nom) => _icones[nom] ?? iconesLucide[nom] ?? LucideIcons.circle;

TonSigh tbaTon(String ton) => switch (ton) {
      'success' => TonSigh.succes,
      'warning' => TonSigh.attention,
      'danger' => TonSigh.danger,
      'info' => TonSigh.info,
      'neutral' => TonSigh.neutre,
      _ => TonSigh.navy,
    };

KpiSigh tbaKpiWidget(TbaKpi k) =>
    KpiSigh(libelle: k.libelle, valeur: k.valeur, indice: k.indice, icone: tbaIcone(k.icone), ton: tbaTon(k.ton));

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Lecture des collections
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les fiches ACTIVES des collections [noms], et l'abonnement qui repeint l'écran quand l'une change.
Listenable tbaEcoute(ContexteEcran c, List<String> noms) => Listenable.merge([for (final n in noms) c.magasin.collection(n)]);

List<Fiche> tbaActives(ContexteEcran c, String nom) => c.magasin.collection(nom).actives;

String tbaDateHeure(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : '${dateFR(d)} ${heure(d)}';
}

String tbaDate(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

String tbaHeure(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : heure(d);
}

String tbaMontant(Object? v) => money(v, avecDevise: false);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le tableau de bord (K.dash)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `K.dash` : dans l'ordre — l'alerte du poste, le PREMIER REGARD, les sections RAPIDES (les accès rapides d'abord, puis le mode d'emploi), les
/// indicateurs, puis le reste. L'ordre de lecture est la seule chose qu'un tableau de bord contrôle vraiment.
class TbaDash extends StatelessWidget {
  const TbaDash({super.key, this.alerte, this.premier, required this.rapides, required this.kpis, this.sections = const []});
  final Widget? alerte;
  final TbaPremierRegard? premier;
  final List<Widget> rapides;
  final List<TbaKpi> kpis;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final blocs = <Widget>[
      if (alerte != null) alerte!,
      if (premier != null) BandeauPremierRegard(premier!, aller: c.aller),
      ...rapides,
      KpiGrilleSigh(kpis: [for (final k in kpis) tbaKpiWidget(k)]),
      ...sections,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < blocs.length; i++) ...[if (i > 0) const SizedBox(height: 20), blocs[i]]
    ]);
  }
}

/// Une carte de section (`U.card(title, content, actions)`).
Widget tbaCarte(String titre, Widget corps, {List<Widget> actions = const [], bool sansRemplissage = false}) =>
    CarteSigh(titre: titre, actions: actions, sansRemplissage: sansRemplissage, child: corps);

/// Deux cartes côte à côte au-delà de 1024 px (`K.charts`).
Widget tbaDeuxCartes(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [SizedBox(width: l, child: a), SizedBox(width: l, child: b)]);
    });

/// Un lien de carte (`K.lien`) : bouton secondaire petit vers un écran.
Widget tbaLien(ContexteEcran c, String ecran, String libelle, String icone, {bool primaire = false}) => BoutonSigh(
    libelle: libelle,
    icone: tbaIcone(icone),
    taille: TailleBouton.sm,
    variante: primaire ? VarianteBouton.primaire : VarianteBouton.secondaire,
    onPressed: () => c.aller(ecran));

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le premier regard
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le bandeau du premier regard : UNE question, son compte, le lien qui y mène. À zéro il énonce [TbaPremierRegard.vide] (phrase positive) et
/// n'offre aucun lien ; un compte fermé (écran nul) dit la décision et rien d'autre.
class BandeauPremierRegard extends StatelessWidget {
  const BandeauPremierRegard(this.p, {super.key, required this.aller});
  final TbaPremierRegard p;
  final void Function(String) aller;

  @override
  Widget build(BuildContext context) {
    final rien = p.valeur == 0;
    final ton = rien ? TonSigh.succes : tbaTon(p.ton);
    final couleurTexte = ton.texte900;
    final couleurAccent = ton.texteBadge;
    return Container(
      key: const Key('tba:premier-regard'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
          color: ton.fond50, border: Border.all(color: ton.bordure200), borderRadius: BorderRadius.circular(12)),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 12, children: [
        Icon(tbaIcone(rien ? 'check-check' : p.icone), size: 28, color: couleurAccent),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 760),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('À REGARDER EN PREMIER',
                style: TextStyle(color: couleurAccent, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
            const SizedBox(height: 2),
            if (rien)
              Text(p.vide, style: TextStyle(color: couleurTexte, fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600))
            else
              Text.rich(
                  TextSpan(children: [
                    TextSpan(text: nombre(p.valeur), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    TextSpan(text: ' ${p.unite} — ${p.question}'),
                  ]),
                  style: TextStyle(color: couleurTexte, fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600)),
            if (p.note.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(p.note, style: TextStyle(color: couleurAccent, fontSize: 12, height: 16 / 12))),
          ]),
        ),
        if (!rien && p.ecran != null)
          BoutonSigh(
              libelle: p.lienLabel ?? 'Y aller',
              icone: LucideIcons.arrowRight,
              taille: TailleBouton.sm,
              onPressed: () => aller(p.ecran!)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les parcours (K.parcours)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une étape : [ecran] (cliquable si ouvert au profil) ou [poste] (le poste qui prend la suite, nommé par une pastille).
class EtapeTba {
  const EtapeTba(this.libelle, {this.ecran, this.poste, this.detail});
  final String libelle;
  final String? ecran;
  final String? poste;
  final String? detail;
}

class ParcoursTba {
  const ParcoursTba(this.titre, this.icone, this.action, this.detail, this.etapes);
  final String titre;
  final String icone;
  final String action;
  final String detail;
  final List<EtapeTba> etapes;
}

/// `K.parcours` : une grille de liens dit OÙ aller ; un parcours dit CE QU'IL FAUT FAIRE et DANS QUEL ORDRE. Une étape dont l'écran est fermé au
/// profil reste VISIBLE mais non cliquable (« fermé à votre profil ») ; l'étape d'un autre poste est nommée par une pastille ; le bouton porte la
/// première action — et n'existe pas si cet écran-là est fermé.
class ParcoursSigh extends StatelessWidget {
  const ParcoursSigh(this.parcours, {super.key});
  final List<ParcoursTba> parcours;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    bool ouvert(String? id) => id == null || (c.ouvre?.call(id) ?? true);
    final cartes = [
      for (final p in parcours)
        Container(
          key: Key('tba:parcours:${p.titre}'),
          padding: const EdgeInsets.all(16),
          decoration: decorationCarte(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
                  child: Icon(tbaIcone(p.icone), size: 16, color: JetonsShell.navy700)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.titre, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                Text(p.detail, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
              ])),
            ]),
            const SizedBox(height: 12),
            for (final (i, e) in p.etapes.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: i == 0 ? JetonsShell.navy700 : JetonsShell.slate100, shape: BoxShape.circle),
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: i == 0 ? Colors.white : JetonsShell.slate500, fontSize: 10, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  Expanded(child: _Etape(e, ouvert: ouvert(e.ecran), aller: c.aller)),
                ]),
              ),
            if (p.etapes.isNotEmpty && p.etapes.first.ecran != null && ouvert(p.etapes.first.ecran))
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: BoutonSigh(
                          libelle: p.action,
                          icone: LucideIcons.arrowRight,
                          taille: TailleBouton.sm,
                          onPressed: () => c.aller(p.etapes.first.ecran!)))),
          ]),
        ),
    ];
    return LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [for (final x in cartes) SizedBox(width: l, child: x)]);
    });
  }
}

class _Etape extends StatelessWidget {
  const _Etape(this.e, {required this.ouvert, required this.aller});
  final EtapeTba e;
  final bool ouvert;
  final void Function(String) aller;

  @override
  Widget build(BuildContext context) {
    final cliquable = e.ecran != null && ouvert;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
        cliquable
            ? InkWell(
                key: Key('tba:etape:${e.ecran}'),
                onTap: () => aller(e.ecran!),
                child: Text(e.libelle,
                    style: const TextStyle(color: JetonsShell.navy800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)))
            : Text(e.libelle,
                style: TextStyle(color: ouvert ? JetonsShell.slate700 : JetonsShell.slate400, fontSize: 14, height: 20 / 14)),
        if (e.poste != null)
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: JetonsShell.slate100, borderRadius: BorderRadius.circular(4)),
              child: Text(e.poste!, style: const TextStyle(color: JetonsShell.slate500, fontSize: 10, fontWeight: FontWeight.w500))),
        if (!ouvert)
          const Text('— fermé à votre profil',
              style: TextStyle(color: JetonsShell.slate400, fontSize: 10, fontStyle: FontStyle.italic)),
      ]),
      if (e.detail != null)
        Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(e.detail!, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Accès rapides, classement, alertes
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// La section « Accès rapides » (`K.shortcuts`).
Widget tbaAccesRapides(ContexteEcran c, List<(String, String, String, String?)> items) => tbaCarte(
    'Accès rapides',
    RaccourcisSigh(aller: c.aller, items: [
      for (final i in items) RaccourciDef(id: i.$1, icone: tbaIcone(i.$2), libelle: i.$3, detail: i.$4)
    ]));

/// `K.ranking` : libellé → valeur avec barre de proportion ; [format] met la valeur en forme (`C.num` par défaut).
class ClassementTba extends StatelessWidget {
  const ClassementTba(this.lignes, {super.key, this.format});
  final List<(String, num)> lignes;
  final String Function(num)? format;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) return const VideSigh('Aucune donnée.', icone: LucideIcons.chartColumn);
    final max = lignes.fold<num>(1, (a, l) => l.$2 > a ? l.$2 : a);
    return Column(children: [
      for (final l in lignes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(l.$1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              const SizedBox(width: 12),
              Text(format != null ? format!(l.$2) : nombre(l.$2),
                  style: const TextStyle(
                      color: JetonsShell.slate900,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
                borderRadius: BorderRadius.circular(9999),
                child: LayoutBuilder(
                    builder: (_, k) => Stack(children: [
                          Container(height: 6, width: k.maxWidth, color: JetonsShell.slate100),
                          Container(
                              height: 6,
                              width: k.maxWidth * (l.$2 / max).clamp(0.02, 1.0),
                              color: JetonsShell.navy500),
                        ]))),
          ]),
        ),
    ]);
  }
}

/// Le bandeau d'alertes transverse (stock, pharmacie) : une pastille cliquable par alerte.
class BandeauAlertesTba extends StatelessWidget {
  const BandeauAlertesTba(this.alertes, {super.key});
  final List<TbaAlerte> alertes;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return LayoutBuilder(builder: (_, k) {
      final cols = k.maxWidth >= 640 ? 3 : 1;
      final l = (k.maxWidth - 8 * (cols - 1)) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in alertes)
          SizedBox(
            width: l,
            child: InkWell(
              key: Key('tba:alerte:${a.ecran}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => c.aller(a.ecran),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: tbaTon(a.ton).fond50,
                    border: Border.all(color: tbaTon(a.ton).bordure200),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(tbaIcone(a.icone), size: 16, color: tbaTon(a.ton).icone600),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(a.texte,
                          style: TextStyle(color: tbaTon(a.ton).texte900, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500))),
                  Icon(LucideIcons.arrowRight, size: 14, color: tbaTon(a.ton).icone600),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}

/// Cellule en police à chasse fixe (numéros, codes).
Widget tbaMono(Object? v, {double taille = 12}) => Text('${v ?? ''}',
    style: TextStyle(fontFamily: 'LiberationMono', fontSize: taille, color: JetonsShell.slate700));

/// `K.miniTable` dans une carte : le tableau affleure les bords de la carte.
Widget tbaMiniTableau(List<ColonneMini> colonnes, List<Fiche> lignes, {String vide = 'Aucune donnée.'}) =>
    MiniTableauSigh(colonnes: colonnes, lignes: lignes, vide: vide);

/// La file d'attente d'un poste (`fileDuPoste`) précédée, au besoin, du bandeau d'alertes.
Widget tbaFileDuPoste(ContexteEcran c, String type,
        {required String titre, required String vide, required String action, required String ecran, List<TbaAlerte> alertes = const []}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (alertes.isNotEmpty) ...[BandeauAlertesTba(alertes), const SizedBox(height: 12)],
      FileAttenteSigh(type: type, titre: titre, vide: vide, action: action, icone: LucideIcons.arrowRight, surAction: (_, __) => c.aller(ecran)),
    ]);
