import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/donnees_navigation.dart';
import '../core/icones.dart';
import '../core/jetons_shell.dart';
import '../kit/kit.dart';
import 'contexte_ecran.dart';

/// Les pages d'accueil de module (hubs) du manifeste : `hub-m1`, `hub-m2`, … `hub-rls`. Liste DÉRIVÉE du manifeste par un test (jamais recopiée à la
/// main sans garde) : ajouter un module crée son hub côté maquette, et `parite_hubs_test.dart` échoue ici tant que le hub n'est pas déclaré.
const hubsDuManifeste = [
  'hub-m1', 'hub-m2', 'hub-m3', 'hub-m4', 'hub-m5', 'hub-m6', 'hub-m7', 'hub-m8', 'hub-m9', 'hub-mecef', 'hub-m12', 'hub-m10', 'hub-m11',
  'hub-m13', 'hub-ged', 'hub-rap', 'hub-m14', 'hub-cfg', 'hub-mere', 'hub-rls', 'hub-pil', 'hub-dash', 'hub-imp',
];

/// Un module tel que `N.module(code)` de la maquette le rend : la rangée CANONIQUE (ni alias, ni secondaire) le nomme et le situe ; les rangées
/// secondaires apportent leurs écrans (sans quoi le hub n'en montrerait qu'une partie et le module paraîtrait amputé) ; les alias ne comptent pas
/// (leurs écrans sont déjà dans leur module canonique).
class ModuleHub {
  const ModuleHub({required this.code, required this.label, required this.icone, required this.domaine, required this.ecrans});
  final String code;
  final String label;
  final String? icone;
  final String domaine;
  final List<String> ecrans;

  static ModuleHub? depuis(Manifeste m, String code) {
    RangeeManifeste? canonique;
    final tous = <String>[];
    for (final r in m.rangees) {
      if (r.alias || r.code != code) continue;
      tous.addAll(r.ecrans);
      if (r.secondaire || canonique != null) continue;
      canonique = r;
    }
    if (canonique == null) return null;
    return ModuleHub(code: canonique.code, label: canonique.label, icone: canonique.icone, domaine: canonique.domaine, ecrans: tous);
  }

  /// `hub(mod)` de la maquette : « Tous les écrans du module M1 (tiret cadratin) Patients & Dossier médical. » Le tiret est celui de la maquette : la
  /// parité N1 compare les libellés, on le reprend tel quel.
  String get description => 'Tous les écrans du module $code \u2014 $label.';
}

/// Une carte du hub : icône, titre, DESCRIPTION reprise de la déclaration de l'écran (`hubCartes()` de `_kit.js`).
class CarteHub {
  const CarteHub({required this.id, required this.titre, required this.description, required this.icone});
  final String id;
  final String titre;
  final String description;
  final String? icone;
}

/// Les cartes que le profil voit : un écran fermé au rôle (matrice, activité fermée) est ABSENT, jamais grisé (RG-13).
List<CarteHub> cartesDuHub(ModuleHub mod, DonneesNavigation nav, bool Function(String) ouvre) {
  final manifeste = nav.manifeste;
  return [
    for (final id in mod.ecrans)
      if (manifeste.ecran(id) != null && ouvre(id))
        CarteHub(
          id: id,
          titre: nav.titreDeclare(id) ?? manifeste.ecran(id)!.label,
          description: nav.descriptionDeclaree(id) ?? 'Écran du module ${mod.label}.',
          icone: manifeste.ecran(id)!.icone ?? mod.icone,
        ),
  ];
}

/// Page d'accueil d'un module : une carte par écran du module (filtrées par les droits du rôle, alias déjà résolus par `ModuleHub`), puis le passage
/// direct vers les autres modules du même domaine.
class EcranHub extends StatelessWidget with EcranMaquette {
  const EcranHub({super.key, required this.hub, this.estMere = false, this.descriptionDe});

  /// Construit le hub depuis le contexte de la coque : la coque lit la description du widget SANS contexte, on la calcule donc ici.
  factory EcranHub.depuis(BuildContext contexte, String hub, {bool estMere = false}) {
    final nav = ContexteEcran.maybeOf(contexte)?.donnees;
    final entree = nav?.manifeste.ecran(hub);
    final mod = nav == null || entree == null ? null : ModuleHub.depuis(nav.manifeste, entree.module);
    return EcranHub(hub: hub, estMere: estMere, descriptionDe: mod?.description);
  }

  final String hub;
  final bool estMere;
  final String? descriptionDe;

  @override
  String? get description => descriptionDe;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final nav = c.donnees;
    final entree = nav?.manifeste.ecran(hub);
    final mod = nav == null || entree == null ? null : ModuleHub.depuis(nav.manifeste, entree.module);
    if (nav == null || mod == null) {
      return const NoteSigh('Ce module n’est pas décrit par le manifeste de navigation.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert);
    }
    bool ouvre(String id) => c.ouvre?.call(id) ?? nav.matrice.peutVoir(c.role, id);
    final cartes = cartesDuHub(mod, nav, ouvre);
    final voisins = [
      for (final d in nav.manifeste.ruban(nav.matrice, c.role, estMere: estMere))
        if (d.nom == mod.domaine)
          for (final r in d.rangees)
            if (r.code != mod.code) r,
    ];
    return Column(key: const Key('hub'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (cartes.isEmpty)
        const NoteSigh('Aucun écran de ce module n’est accessible à votre profil.', ton: TonSigh.neutre, icone: LucideIcons.lock)
      else
        LayoutBuilder(builder: (_, w) {
          // `grid gap-3 sm:grid-cols-2 xl:grid-cols-3`.
          final n = w.maxWidth >= 1280 ? 3 : (w.maxWidth >= 640 ? 2 : 1);
          final large = (w.maxWidth - 12 * (n - 1)) / n;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final k in cartes) SizedBox(width: large, child: _CarteModule(carte: k, surClic: () => c.aller(k.id))),
          ]);
        }),
      if (voisins.isNotEmpty) ...[
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Autres modules du domaine ${mod.domaine} :', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
          for (final r in voisins) _Voisin(rangee: r, surClic: () => c.aller(r.hub)),
        ]),
      ],
    ]);
  }
}

class _CarteModule extends StatelessWidget {
  const _CarteModule({required this.carte, required this.surClic});
  final CarteHub carte;
  final VoidCallback surClic;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: JetonsShell.slate200)),
        elevation: 0,
        child: InkWell(
          key: Key('hub-carte:${carte.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: surClic,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
                child: Icon(icone(carte.icone), size: 20, color: JetonsShell.navy700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(carte.titre,
                      style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate900)),
                  const SizedBox(height: 4),
                  Text(carte.description, style: const TextStyle(fontSize: 12, height: 1.625, color: JetonsShell.slate500)),
                ]),
              ),
              const SizedBox(width: 12),
              const Icon(LucideIcons.arrowRight, size: 16, color: JetonsShell.slate300),
            ]),
          ),
        ),
      );
}

class _Voisin extends StatelessWidget {
  const _Voisin({required this.rangee, required this.surClic});
  final RangeeRuban rangee;
  final VoidCallback surClic;

  @override
  Widget build(BuildContext context) => InkWell(
        key: Key('hub-voisin:${rangee.hub}:${rangee.label}'),
        borderRadius: BorderRadius.circular(8),
        onTap: surClic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone(rangee.icone), size: 14, color: JetonsShell.slate600),
            const SizedBox(width: 6),
            Text(rangee.label, style: const TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
          ]),
        ),
      );
}

/// LES GROUPES DE CARTES DE « PARAMÈTRES SYSTÈME » (arbitrage du 05/11/2026), miroir de `K.groupesCartes` de la maquette : un groupe par module (titre, nombre
/// d'écrans, cartes en flex qui passent à la ligne). La matière vient de `Manifeste.cartesParametres`, déjà filtrée par les droits : jamais une carte vers
/// un écran interdit (RG-13).
class GroupesCartes extends StatelessWidget {
  const GroupesCartes({super.key, required this.domaines, required this.nav, required this.aller});
  final List<DomaineRuban> domaines;
  final DonneesNavigation nav;
  final void Function(String id) aller;

  @override
  Widget build(BuildContext context) {
    final groupes = [
      for (final d in domaines)
        for (final r in d.rangees) r,
    ];
    if (groupes.isEmpty) {
      return const NoteSigh('Aucun écran de cette rubrique n’est accessible à votre profil.', ton: TonSigh.neutre, icone: LucideIcons.lock);
    }
    return Column(key: const Key('groupes-cartes'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in groupes) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(icone(r.icone), size: 16, color: JetonsShell.navy700),
            const SizedBox(width: 8),
            // Un seul Text : la maquette concatène le titre et le compte dans le MÊME titre (la parité N1 compare le texte entier).
            Text.rich(TextSpan(children: [
              TextSpan(text: r.label, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate700)),
              const TextSpan(text: ' '),
              TextSpan(text: '${r.ecrans.length} écran(s)', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
            ])),
          ]),
        ),
        LayoutBuilder(builder: (_, w) {
          // `flex flex-wrap gap-3` avec `grow basis-72` (18 rem).
          final colonnes = (w.maxWidth / (288 + 12)).floor().clamp(1, 6);
          final large = (w.maxWidth - 12 * (colonnes - 1)) / colonnes;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final e in r.ecrans)
              SizedBox(
                  width: large,
                  child: _CarteModule(
                      carte: CarteHub(
                          id: e.id,
                          titre: nav.titreDeclare(e.id) ?? e.label,
                          description: nav.descriptionDeclaree(e.id) ?? 'Écran du module ${r.label}.',
                          icone: e.icone ?? r.icone),
                      surClic: () => aller(e.id))),
          ]);
        }),
        const SizedBox(height: 20),
      ],
    ]);
  }
}

/// `parametres-hub` : « Paramètres système » pour tout profil qui n'a pas l'onglet « Système » du ruban. Les écrans du système que SES droits ouvrent, en cartes,
/// et rien d'autre. Le poste mère et le relais ont leur propre place (ruban de l'administrateur, onglet « Relais en ligne » de cfg-systeme).
class EcranParametresHub extends StatelessWidget with EcranMaquette {
  const EcranParametresHub({super.key, this.estMere = false});
  final bool estMere;
  @override
  String get titre => 'Paramètres système';
  @override
  String get description => 'Les écrans du système que votre profil peut ouvrir, en cartes.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final nav = c.donnees;
    if (nav == null) return const NoteSigh('Le manifeste de navigation est indisponible.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert);
    final domaines = nav.manifeste.cartesParametres(nav.matrice, c.role, estMere: estMere, domaines: const {'Système'});
    return GroupesCartes(domaines: domaines, nav: nav, aller: c.aller);
  }
}
