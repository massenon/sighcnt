import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/donnees_navigation.dart';
import '../../core/icones.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../cfg/cfa_commun.dart' show cfaNavigation, cfaNavigationChargee;

/// Briques communes des tableaux de bord « B » (`K.dash`, `K.parcours`, le bandeau du premier regard, `K.ranking`). Symboles préfixés `Tbb`.
/// L'ordre de lecture est celui de la maquette — la seule chose qu'un tableau de bord contrôle vraiment : premier regard → accès rapides →
/// parcours → indicateurs → le reste.

/// Les icônes que `iconesLucide` (engendré) ne porte pas encore : retombées explicites plutôt que le cercle de repli.
const Map<String, IconData> _iconesTbb = {
  'house-plus': LucideIcons.housePlus,
  'route': LucideIcons.route,
  'calendar': LucideIcons.calendar,
  'list': LucideIcons.list,
  'clock-alert': LucideIcons.clockAlert,
  'palmtree': LucideIcons.palmtree,
  'user-minus': LucideIcons.userMinus,
  'file-clock': LucideIcons.fileClock,
  'book-open': LucideIcons.bookOpen,
  'alert-triangle': LucideIcons.triangleAlert,
  'user': LucideIcons.user,
  'plus': LucideIcons.plus,
  'check-check': LucideIcons.checkCheck,
  'eye': LucideIcons.eye,
  'arrow-right': LucideIcons.arrowRight,
  'check-circle-2': LucideIcons.circleCheck,
};

IconData iconeTbb(String nom) => _iconesTbb[nom] ?? icone(nom);

TonSigh tonDe(String ton) => switch (ton) {
      'danger' => TonSigh.danger,
      'warning' => TonSigh.attention,
      'success' => TonSigh.succes,
      'info' => TonSigh.info,
      'navy' => TonSigh.navy,
      _ => TonSigh.neutre,
    };

KpiSigh kpiDe(TbbKpi k) => KpiSigh(
    libelle: k.libelle, valeur: k.valeur, icone: iconeTbb(k.icone), ton: tonDe(k.ton), indice: k.indice);

/// `K.lien(id, label, {size: 'sm', icon})` : bouton secondaire qui mène à un écran.
Widget lienIcone(String libelle, String icone, VoidCallback f) =>
    BoutonSigh(libelle: libelle, icone: iconeTbb(icone), taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: f);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le premier regard
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `bandeauPremierRegard` : UNE question, son compte, le lien qui y mène. À zéro il énonce une phrase (« Rien ne vous attend » est une information),
/// en vert, sans lien ; la note dit d'où vient la question. (L'annonce SONORE d'un premier regard grave n'est pas portée : aucun moteur audio au poste.)
class PremierRegardSigh extends StatelessWidget {
  const PremierRegardSigh(this.regard, {super.key, required this.aller});
  final TbbRegard regard;
  final void Function(String id) aller;

  @override
  Widget build(BuildContext context) {
    final rien = regard.valeur == 0;
    final ton = rien ? TonSigh.succes : tonDe(regard.ton);
    final texte = ton.texteBadge;
    return Container(
      key: const Key('tbb:premier-regard'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
          color: ton.fond50, borderRadius: BorderRadius.circular(12), border: Border.all(color: ton.bordure200)),
      child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Icon(rien ? LucideIcons.checkCheck : iconeTbb(regard.icone), size: 28, color: texte),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('À regarder en premier'.toUpperCase(),
                style: TextStyle(color: texte, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: rien
                  ? Text(regard.vide,
                      key: const Key('tbb:regard-ligne'),
                      style: TextStyle(color: ton.texte900, fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600))
                  : Text.rich(
                      key: const Key('tbb:regard-ligne'),
                      TextSpan(children: [
                        TextSpan(
                            text: nombre(regard.valeur),
                            style: const TextStyle(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w700)),
                        TextSpan(text: ' ${regard.unite} — ${regard.question}'),
                      ]),
                      style: TextStyle(color: ton.texte900, fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(regard.note,
                  key: const Key('tbb:regard-note'), style: TextStyle(color: texte, fontSize: 12, height: 16 / 12)),
            ),
          ]),
        ),
        if (!rien)
          BoutonSigh(
              libelle: regard.lienLabel,
              icone: LucideIcons.arrowRight,
              taille: TailleBouton.sm,
              onPressed: () => aller(regard.ecran)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les parcours
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EtapeDef {
  const EtapeDef(this.label, {this.ecran, this.poste, this.detail});
  final String label;
  final String? ecran, poste, detail;
}

class ParcoursDef {
  const ParcoursDef(this.titre, this.icone, this.etapes, {this.action, this.detail});
  final String titre, icone;
  final String? action, detail;
  final List<EtapeDef> etapes;
}

/// `K.parcours` : une chaîne numérotée par poste de travail. Une étape dont l'écran est fermé au profil reste VISIBLE mais non cliquable (« — fermé à votre
/// profil ») ; une étape d'un AUTRE poste est nommée par une pastille ; le bouton porte la première action, seulement si son écran est ouvert.
class ParcoursSigh extends StatelessWidget {
  const ParcoursSigh(this.parcours, {super.key});
  final List<ParcoursDef> parcours;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return FutureBuilder<DonneesNavigation>(
      future: cfaNavigation(),
      initialData: cfaNavigationChargee,
      builder: (context, snap) {
        final nav = snap.data;
        // Un identifiant inconnu de la matrice est fermé : mieux vaut ne rien promettre. Tant que les données de navigation ne sont pas chargées (une image,
        // au démarrage), rien n'est retiré : la coque refuse de toute façon d'ouvrir un écran fermé au rôle (`aller`).
        bool ouvert(String? id) => id == null || nav == null || nav.matrice.peutVoir(c.role, id);
        return LayoutBuilder(builder: (context, k) {
          final deux = k.maxWidth >= 1024;
          final l = deux ? (k.maxWidth - 16) / 2 : k.maxWidth;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final p in parcours) SizedBox(width: l, child: _Carte(p, c, ouvert)),
          ]);
        });
      },
    );
  }
}

class _Carte extends StatelessWidget {
  const _Carte(this.p, this.c, this.ouvert);
  final ParcoursDef p;
  final ContexteEcran c;
  final bool Function(String?) ouvert;

  @override
  Widget build(BuildContext context) {
    final premiere = p.etapes.isEmpty ? null : p.etapes.first;
    return Container(
      key: Key('tbb:parcours:${p.titre}'),
      padding: const EdgeInsets.all(16),
      decoration: decorationCarte(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
                child: Icon(iconeTbb(p.icone), size: 16, color: JetonsShell.navy700)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.titre,
                  style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
              if (p.detail != null)
                Text(p.detail!, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
            ])),
          ]),
        ),
        for (var i = 0; i < p.etapes.length; i++) _Etape(i, p.etapes[i], c, ouvert(p.etapes[i].ecran)),
        if (premiere != null && premiere.ecran != null && ouvert(premiere.ecran))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: BoutonSigh(
                  libelle: p.action ?? 'Commencer',
                  icone: LucideIcons.arrowRight,
                  taille: TailleBouton.sm,
                  onPressed: () => c.aller(premiere.ecran!)),
            ),
          ),
      ]),
    );
  }
}

class _Etape extends StatelessWidget {
  const _Etape(this.rang, this.e, this.c, this.ouvert);
  final int rang;
  final EtapeDef e;
  final ContexteEcran c;
  final bool ouvert;

  @override
  Widget build(BuildContext context) {
    final lien = e.ecran != null && ouvert;
    final label = Text(e.label,
        key: Key('tbb:etape:${e.label}'),
        style: TextStyle(
            color: lien ? JetonsShell.navy800 : (ouvert ? JetonsShell.slate700 : JetonsShell.slate400),
            fontSize: 14,
            height: 20 / 14,
            fontWeight: lien ? FontWeight.w500 : FontWeight.w400));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 2, right: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: rang == 0 ? JetonsShell.navy700 : JetonsShell.slate100, shape: BoxShape.circle),
            child: Text('${rang + 1}',
                style: TextStyle(
                    color: rang == 0 ? Colors.white : JetonsShell.slate500, fontSize: 10, fontWeight: FontWeight.w700))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              lien ? InkWell(onTap: () => c.aller(e.ecran!), child: label) : label,
              if (e.poste != null)
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: JetonsShell.slate100, borderRadius: BorderRadius.circular(4)),
                    child: Text(e.poste!,
                        style: const TextStyle(color: JetonsShell.slate500, fontSize: 10, fontWeight: FontWeight.w500))),
              if (!ouvert)
                const Text('— fermé à votre profil',
                    style: TextStyle(color: JetonsShell.slate400, fontSize: 10, fontStyle: FontStyle.italic)),
            ]),
            if (e.detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(e.detail!, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le classement (K.ranking) et la grille de cartes (K.charts)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `K.ranking` : libellé → valeur, avec une barre de proportion (au moins 2 %).
class ClassementSigh extends StatelessWidget {
  const ClassementSigh(this.items, {super.key});
  final List<(String, int)> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const VideSigh('Aucune donnée.', icone: LucideIcons.chartColumn);
    final max = items.fold<int>(1, (a, x) => x.$2 > a ? x.$2 : a);
    return Column(children: [
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(
                  child: Text(i.$1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              const SizedBox(width: 12),
              Text(nombre(i.$2),
                  style: const TextStyle(
                      color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(9999),
              child: Container(
                height: 6,
                color: JetonsShell.slate100,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                    widthFactor: ((i.$2 / max * 100).round().clamp(2, 100)) / 100,
                    child: Container(color: JetonsShell.navy500)),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Deux cartes côte à côte en large, empilées en dessous de 1024 px (`grid gap-4 lg:grid-cols-2`).
Widget deuxColonnes(List<Widget> cartes) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [for (final c in cartes) SizedBox(width: l, child: c)]);
    });

/// `U.empty` dans une carte de tableau de bord.
Widget videCarte(String message, String icone) => VideSigh(message, icone: iconeTbb(icone));

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le gabarit
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `K.dash` : premier regard, puis les accès rapides, puis les parcours, puis les indicateurs, puis le reste — jamais dans un autre ordre.
class TableauTbb extends StatelessWidget {
  const TableauTbb({
    super.key,
    required this.collections,
    required this.construire,
  });

  /// Les collections lues : le tableau se recalcule quand l'une d'elles change.
  final List<String> collections;

  /// Reçoit le magasin, l'horloge du poste et le contexte de l'écran.
  final TbbDisposition Function(ContexteEcran c) construire;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([for (final n in collections) c.magasin.collection(n)]),
      builder: (context, _) {
        final d = construire(c);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (d.releve != null) ...[PremierRegardSigh(d.releve!.regard, aller: c.aller), const SizedBox(height: 20)],
          if (d.raccourcis.isNotEmpty) ...[
            CarteSigh(titre: 'Accès rapides', child: RaccourcisSigh(items: d.raccourcis, aller: c.aller)),
            const SizedBox(height: 20),
          ],
          if (d.parcours.isNotEmpty) ...[
            CarteSigh(titre: 'Ce que vous faites ici — vos parcours', child: ParcoursSigh(d.parcours)),
            const SizedBox(height: 20),
          ],
          if (d.releve != null) KpiGrilleSigh(kpis: [for (final k in d.releve!.kpis) kpiDe(k)]),
          for (final s in d.sections) ...[const SizedBox(height: 20), s],
        ]);
      },
    );
  }
}

/// Ce qu'un tableau de bord compose : sa lecture, ses accès rapides, ses parcours, puis les sections qui suivent les indicateurs.
class TbbDisposition {
  const TbbDisposition({this.releve, this.raccourcis = const [], this.parcours = const [], this.sections = const []});
  final TbbReleve? releve;
  final List<RaccourciDef> raccourcis;
  final List<ParcoursDef> parcours;
  final List<Widget> sections;
}

RaccourciDef raccourci(String id, String icone, String libelle, [String? detail]) =>
    RaccourciDef(id: id, icone: iconeTbb(icone), libelle: libelle, detail: detail);

/// Lecture d'une collection du magasin (toutes les fiches, archivées comprises : les règles du domaine filtrent elles-mêmes).
List<Fiche> lire(ContexteEcran c, String nom) => c.magasin.collection(nom).toutes;
