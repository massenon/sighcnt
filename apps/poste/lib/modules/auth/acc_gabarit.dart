import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_autonome.dart';

/// Le gabarit commun des écrans d'accès (`shell()` de `auth.js`) : une grande carte arrondie posée sur un fond clair — panneau institutionnel en dégradé
/// à gauche (au-delà de 1024 px), carte de saisie blanche détachée à droite. Il sert SIX écrans (connexion, verrou, mot de passe oublié, réinitialisation,
/// double facteur) : la porte d'entrée du logiciel a un seul visage.
class SceneAcces extends StatelessWidget {
  const SceneAcces({super.key, required this.titre, this.sousTitre, this.icone, required this.corps, this.pied});
  final String titre;
  final String? sousTitre;
  final IconData? icone;
  final Widget corps;
  final Widget? pied;

  static const _puces = [
    (LucideIcons.shieldCheck, 'Traçabilité intégrale des actions (journal d’audit)'),
    (LucideIcons.packageSearch, 'Alertes de rupture et de péremption automatiques (FEFO)'),
    (LucideIcons.fileBadge, 'Facture normalisée conforme au dispositif MECeF'),
    (LucideIcons.bookOpenCheck, 'Comptabilité SYSCOHADA alimentée automatiquement'),
  ];

  Widget _logo(double cote, Color fond, double interieur) => Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Image.asset('assets/img/logo.jpeg',
          width: interieur,
          height: interieur,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text(IdentiteClinique.sigle,
              style: TextStyle(color: fond == Colors.white ? JetonsShell.navy900 : Colors.white, fontWeight: FontWeight.w700))));

  Widget _panneau() => Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _logo(48, Colors.white, 36),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('CLINIQUE NASSIERA TOO',
                style: TextStyle(color: Colors.white, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            Text('Natitingou — République du Bénin', style: TextStyle(color: JetonsShell.navy200, fontSize: 12, height: 16 / 12)),
          ]),
        ]),
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Système Intégré de Gestion Hospitalière',
                  style: TextStyle(color: Colors.white, fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w600, letterSpacing: -0.75)),
              const SizedBox(height: 12),
              const Text(
                  'Dossier patient, hospitalisation, laboratoire, pharmacie et stocks, facturation normalisée, ressources humaines, paie et comptabilité SYSCOHADA.',
                  style: TextStyle(color: JetonsShell.navy100, fontSize: 14, height: 22.75 / 14)),
              const SizedBox(height: 28),
              for (final p in _puces)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(6)),
                          child: Icon(p.$1, size: 14, color: JetonsShell.navy100)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(p.$2, style: const TextStyle(color: JetonsShell.navy100, fontSize: 14, height: 20 / 14))),
                    ])),
              const SizedBox(height: 16),
              Container(
                  padding: const EdgeInsets.only(left: 16),
                  decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0x66FFFFFF), width: 2))),
                  child: const Text('« ${IdentiteClinique.slogan} »',
                      style: TextStyle(color: Colors.white, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic))),
            ])),
        const Text('${IdentiteClinique.nom} — IFU ${IdentiteClinique.ifu} — RCCM ${IdentiteClinique.rccm}',
            style: TextStyle(color: JetonsShell.navy300, fontSize: 12, height: 16 / 12)),
      ]));

  Widget _carte(bool large) => Padding(
      padding: EdgeInsets.all(large ? 40 : 24),
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                    key: const Key('acces:carte'),
                    padding: EdgeInsets.all(large ? 32 : 24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: JetonsShell.ombrePop),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (!large)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Row(children: [
                              _logo(44, JetonsShell.navy950, 32),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                                Text('CLINIQUE NASSIERA TOO',
                                    style: TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                                Text(IdentiteClinique.slogan,
                                    style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic)),
                              ])),
                            ])),
                      if (icone != null)
                        Container(
                            width: 48,
                            height: 48,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(12)),
                            child: Icon(icone, size: 24, color: JetonsShell.navy800)),
                      Semantics(
                          header: true,
                          child: Text(titre,
                              style: const TextStyle(
                                  color: JetonsShell.slate900, fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w600, letterSpacing: -0.6))),
                      if (sousTitre != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(sousTitre!, style: const TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14))),
                      const SizedBox(height: 24),
                      corps,
                      if (pied != null) Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: pied)),
                    ])),
                if (!large)
                  const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Text('${IdentiteClinique.nom} — IFU ${IdentiteClinique.ifu}',
                          textAlign: TextAlign.center, style: TextStyle(color: JetonsShell.navy200, fontSize: 12, height: 16 / 12))),
              ]))));

  Widget _halo(double d, Color c) => Container(
      width: d, height: d, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)])));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: JetonsShell.slate100,
        body: LayoutBuilder(builder: (context, c) {
          final large = c.maxWidth >= 1024;
          final scene = ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [JetonsShell.navy950, JetonsShell.navy800, JetonsShell.info800]),
                      boxShadow: JetonsShell.ombrePop),
                  child: Stack(children: [
                    // Décor : trois halos, hors flux et non cliquables.
                    Positioned(left: -96, top: -96, child: IgnorePointer(child: _halo(384, JetonsShell.info500.withValues(alpha: 0.25)))),
                    Positioned(left: -64, bottom: -176, child: IgnorePointer(child: _halo(384, JetonsShell.info400.withValues(alpha: 0.35)))),
                    Positioned(right: -96, top: 100, child: IgnorePointer(child: _halo(320, JetonsShell.info600.withValues(alpha: 0.3)))),
                    if (large)
                      LayoutBuilder(
                          builder: (context, k) => ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 640),
                              child: Stack(children: [
                                // Le panneau remplit la hauteur que la carte de saisie donne à la scène (la carte seule détermine la taille).
                                Positioned(left: 0, top: 0, bottom: 0, width: k.maxWidth / 2, child: _panneau()),
                                Padding(padding: EdgeInsets.only(left: k.maxWidth / 2), child: _carte(true)),
                              ])))
                    else
                      _carte(false),
                  ])));
          return SingleChildScrollView(
              child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: Center(
                      child: Padding(
                          padding: EdgeInsets.all(large ? 16 : 16),
                          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1152), child: scene)))));
        }));
  }
}

/// Un champ de saisie de la maquette (`.label` + `.input`) : libellé 12/16 en 500, saisie 14/20, bordure arrondie.
class ChampAcces extends StatelessWidget {
  const ChampAcces({
    super.key,
    required this.libelle,
    required this.controleur,
    this.indicatif,
    this.masque = false,
    this.suffixe,
    this.entete,
    this.surValidation,
    this.cle,
    this.autofocus = false,
  });
  final String libelle;
  final TextEditingController controleur;
  final String? indicatif;
  final bool masque;
  final Widget? suffixe;

  /// Un élément à droite du libellé (« Mot de passe oublié ? »).
  final Widget? entete;
  final VoidCallback? surValidation;
  final Key? cle;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        entete == null
            ? LibelleChamp(libelle)
            : Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(libelle,
                      style: const TextStyle(
                          color: JetonsShell.slate600, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500)),
                  entete!,
                ])),
        Semantics(
            textField: true,
            label: libelle,
            child: TextField(
                key: cle,
                controller: controleur,
                obscureText: masque,
                autofocus: autofocus,
                enableSuggestions: !masque,
                autocorrect: !masque,
                style: styleSaisie,
                decoration: decorationChamp(indicatif: indicatif, suffixe: suffixe),
                onSubmitted: surValidation == null ? null : (_) => surValidation!())),
      ]);
}

/// Le lien de pied de carte (`font-medium text-navy-700 hover:underline`).
class LienAcces extends StatelessWidget {
  const LienAcces(this.texte, {super.key, required this.onTap, this.petit = false});
  final String texte;
  final VoidCallback onTap;
  final bool petit;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Text(texte,
          style: TextStyle(
              color: JetonsShell.navy700, fontSize: petit ? 12 : 14, height: petit ? 16 / 12 : 20 / 14, fontWeight: FontWeight.w500)));
}

/// Le message rouge de la connexion (`border-danger-200 bg-danger-50`, icône `alert-circle`).
class MessageErreurAcces extends StatelessWidget {
  const MessageErreurAcces(this.texte, {super.key});
  final String texte;
  @override
  Widget build(BuildContext context) => Container(
      key: const Key('acces:erreur'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: JetonsShell.danger50, border: Border.all(color: JetonsShell.danger200), borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(LucideIcons.circleAlert, size: 16, color: JetonsShell.danger600),
        const SizedBox(width: 8),
        Expanded(child: Text(texte, style: const TextStyle(color: JetonsShell.danger900, fontSize: 12, height: 16 / 12))),
      ]));
}

/// Ce que le poste ne fait pas — dit à l'écran, comme la maquette dit ce qu'elle fait. Posé sous les écrans qui simulent.
class NoteSimulation extends StatelessWidget {
  const NoteSimulation(this.texte, {super.key});
  final String texte;
  @override
  Widget build(BuildContext context) => KeyedSubtree(key: const Key('acces:simulation'), child: NoteSigh(texte, ton: TonSigh.attention, icone: LucideIcons.triangleAlert));
}

/// Une police fixe (`font-mono text-xs`).
Widget mono(String texte) =>
    Text(texte, style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate700));

/// La date ISO d'une fiche en `jj/mm/aaaa`.
String dateIsoFr(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// Aller à l'accueil du profil, ou à la connexion quand personne n'est connecté (`url(N.ROLES[role].home)` / `url('index')`).
void allerAccueil(BuildContext c) {
  final x = ContexteAutonome.of(c);
  x.aller(x.accueil());
}
