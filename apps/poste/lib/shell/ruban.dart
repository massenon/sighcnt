import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/icones.dart' as ic;
import '../core/jetons_shell.dart';

/// Le MÉGA-MENU HORIZONTAL EN RUBAN de la maquette : une rangée d'onglets (les domaines) et, dessous, un panneau blanc
/// avec UNE RANGÉE PAR MODULE dont les écrans sont des pastilles. Dérivé du manifeste et filtré par les droits : ni
/// domaine ni rangée vide. L'onglet du domaine de l'écran courant reste marqué même panneau replié.
class Ruban extends StatelessWidget {
  const Ruban(
      {super.key,
      required this.domaines,
      this.raccourcis = const [],
      required this.domaineOuvert,
      required this.ecranCourant,
      required this.panneauOuvert,
      required this.surDomaine,
      required this.surEcran,
      required this.surBascule});
  final List<DomaineRuban> domaines;

  /// Raccourcis permanents (Patients, Consultations, Pharmacie, Facturation) : un clic ouvre la page d'accueil du module.
  final List<RaccourciRuban> raccourcis;
  final String? domaineOuvert;
  final String? ecranCourant;
  final bool panneauOuvert;
  final ValueChanged<String> surDomaine;
  final ValueChanged<String> surEcran;
  final VoidCallback surBascule;

  @override
  Widget build(BuildContext context) {
    final ouvert = domaines.where((d) => d.nom == domaineOuvert).firstOrNull ??
        (domaines.isEmpty ? null : domaines.first);
    final domaineDeLEcran = domaines
        .where((d) =>
            d.rangees.any((r) => r.ecrans.any((e) => e.id == ecranCourant)))
        .firstOrNull;
    return Material(
      color: JetonsShell.navy950,
      elevation: 6,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // --- rangée d'onglets : un par domaine -------------------------------------------------------------------
        SizedBox(
          height: 40,
          child: Row(children: [
            Expanded(
              child: ListView(
                key: const Key('onglets-domaines'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 8, top: 4),
                children: [
                  for (final d in domaines)
                    _Onglet(
                      key: Key('domaine-${d.nom}'),
                      libelle: d.nom,
                      icone: d.icone,
                      actif: panneauOuvert && ouvert?.nom == d.nom,
                      courant: domaineDeLEcran?.nom == d.nom,
                      surTap: () => surDomaine(d.nom),
                    ),
                  if (raccourcis.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Container(
                            width: 1, color: const Color(0x33FFFFFF))),
                  for (final r in raccourcis)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: InkWell(
                        key: Key('raccourci-${r.court}'),
                        onTap: () => surEcran(r.hub),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(ic.icone(r.icone),
                                size: 15, color: JetonsShell.navy100),
                            const SizedBox(width: 6),
                            Text(r.court,
                                style: TextStyle(
                                    color: JetonsShell.navy100,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
                key: const Key('ruban-bascule'),
                onPressed: surBascule,
                icon: Icon(
                    panneauOuvert
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 18,
                    color: JetonsShell.navy100),
                tooltip: panneauOuvert ? 'Replier le menu' : 'Déplier le menu'),
          ]),
        ),
        // --- panneau : une rangée par module ----------------------------------------------------------------------
        if (panneauOuvert && ouvert != null)
          Container(
            key: const Key('panneau-ruban'),
            color: Colors.white,
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(children: [
                for (final r in ouvert.rangees)
                  _Rangee(
                      rangee: r, ecranCourant: ecranCourant, surEcran: surEcran)
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet(
      {super.key,
      required this.libelle,
      required this.icone,
      required this.actif,
      required this.courant,
      required this.surTap});
  final String libelle;
  final String? icone;
  final bool actif;
  final bool courant;
  final VoidCallback surTap;

  @override
  Widget build(BuildContext context) {
    final fond = actif ? Colors.white : Colors.transparent;
    final couleur = actif ? JetonsShell.navy900 : JetonsShell.navy100;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: InkWell(
        onTap: surTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: fond,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            // « ribbon-tab-current » : l'onglet du domaine de la page reste marqué même panneau replié.
            border: !actif && courant
                ? const Border(
                    bottom: BorderSide(color: Colors.white, width: 2))
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic.icone(this.icone), size: 16, color: couleur),
            const SizedBox(width: 8),
            Text(libelle,
                style: TextStyle(
                    color: couleur,
                    fontSize: 14,
                    fontWeight:
                        actif || courant ? FontWeight.w600 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

class _Rangee extends StatelessWidget {
  const _Rangee(
      {required this.rangee,
      required this.ecranCourant,
      required this.surEcran});
  final RangeeRuban rangee;
  final String? ecranCourant;
  final ValueChanged<String> surEcran;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: JetonsShell.slate100))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 240,
          child: InkWell(
            onTap: () => surEcran(rangee.hub),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                Icon(ic.icone(rangee.icone),
                    size: 15, color: JetonsShell.navy700),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(rangee.label.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: JetonsShell.slate500,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .3))),
              ]),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 2,
            runSpacing: 0,
            children: [
              for (final e in rangee.ecrans)
                _Pastille(
                    ecran: e,
                    courant: e.id == ecranCourant,
                    surTap: () => surEcran(e.id))
            ],
          ),
        ),
      ]),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille(
      {required this.ecran, required this.courant, required this.surTap});
  final EcranNav ecran;
  final bool courant;
  final VoidCallback surTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('pastille-${ecran.id}'),
      onTap: surTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: courant ? JetonsShell.navy900 : Colors.transparent,
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic.icone(ecran.icone),
              size: 15, color: courant ? Colors.white : JetonsShell.slate500),
          const SizedBox(width: 8),
          Text(ecran.label,
              style: TextStyle(
                  color: courant ? Colors.white : JetonsShell.slate700,
                  fontSize: 14,
                  fontWeight: FontWeight.w400)),
        ]),
      ),
    );
  }
}
