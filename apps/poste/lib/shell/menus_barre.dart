import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show rolesRubanSysteme;

import '../core/donnees_navigation.dart';
import '../core/icones.dart';
import '../core/jetons_shell.dart';
import '../kit/bouton.dart';
import '../kit/modale.dart';
import 'recherche_globale.dart' show ecranOuvertAuRole;

/// Les actions rapides OUVERTES à un rôle (`SIGH.app.actionsRapides`) : la liste du manifeste, filtrée par les droits : un raccourci vers un écran interdit
/// promet une porte fermée.
List<ActionRapideOuverte> actionsRapidesDuRole(DonneesNavigation nav, String role) => [
      for (final a in nav.barre.actions)
        if (ecranOuvertAuRole(nav, role, a.ecran)) ActionRapideOuverte(a.libelle, a.icone, a.ecran)
    ];

class ActionRapideOuverte {
  const ActionRapideOuverte(this.libelle, this.icone, this.ecran);
  final String libelle, icone, ecran;
}

/// Le modal « Actions rapides » : une grille de raccourcis, ou la phrase qui dit pourquoi elle est vide.
Future<void> ouvrirActionsRapides(BuildContext context, {required DonneesNavigation nav, required String role, required void Function(String ecran) aller}) {
  final actions = actionsRapidesDuRole(nav, role);
  void fermerPuis(String e) {
    Navigator.of(context, rootNavigator: true).pop();
    aller(e);
  }

  return afficherModale<void>(context,
      titre: 'Actions rapides',
      corps: actions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('Aucune action rapide ouverte à votre profil.',
                      key: Key('actions-vide'), style: TextStyle(color: JetonsShell.slate500, fontSize: 14))))
          : LayoutBuilder(
              builder: (_, c) => Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final a in actions)
                      SizedBox(
                        width: c.maxWidth >= 480 ? (c.maxWidth - 8) / 2 : c.maxWidth,
                        child: InkWell(
                          key: Key('action:${a.ecran}'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => fermerPuis(a.ecran),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(border: Border.all(color: JetonsShell.slate200), borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
                                  child: Icon(icone(a.icone), size: 16, color: JetonsShell.navy700)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(a.libelle, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, fontWeight: FontWeight.w500))),
                            ]),
                          ),
                        ),
                      ),
                  ])));
}

String initialesDe(String s) {
  final m = s.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (m.isEmpty) return '?';
  return (m.first[0] + (m.length > 1 ? m[1][0] : '')).toUpperCase();
}

/// Le modal « Profil utilisateur » : qui est connecté, son rôle, les écrans de son compte, le verrouillage et la déconnexion.
Future<void> ouvrirMenuProfil(
  BuildContext context, {
  required DonneesNavigation nav,
  required String role,
  required String nom,
  required String libelleRole,
  required void Function(String ecran) aller,
  VoidCallback? verrouiller,
  required VoidCallback deconnecter,
}) {
  void fermer() => Navigator.of(context, rootNavigator: true).pop();
  // Un lien vers un écran fermé au profil promet une porte fermée : il est absent. Les écrans d'accès (aide, contact) ne relèvent pas de la matrice.
  bool ouvert(String id) {
    final e = nav.manifeste.ecran(id);
    return e != null && (e.standalone || ecranOuvertAuRole(nav, role, id));
  }

  // « Paramètres système » : l'onglet Système du ruban n'est affiché qu'à l'administrateur et à la DA, qui ouvrent l'écran complet ; les autres profils ouvrent la
  // page de cartes réduite à ce que leurs droits permettent (arbitrage du 05/11/2026).
  final liens = [
    ('Paramètres système', rolesRubanSysteme.contains(role) ? 'cfg-systeme' : 'parametres-hub', LucideIcons.settings),
    ('Mon compte', 'cfg-compte', LucideIcons.userCog),
    ('Notifications', 'cfg-notifications', LucideIcons.bell),
    ('Aide & À propos', 'aide-apropos', LucideIcons.lifeBuoy),
    ('Contactez l’éditeur', 'contact-editeur', LucideIcons.mail),
    ('Journal d’audit', 'm14-audit', LucideIcons.scrollText),
  ];
  return afficherModale<void>(context,
      titre: 'Profil utilisateur',
      taille: TailleModale.sm,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            CircleAvatar(
                radius: 24,
                backgroundColor: JetonsShell.navy900,
                child: Text(initialesDe(nom), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom, key: const Key('profil-nom'), style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, fontWeight: FontWeight.w600)),
              Text(libelleRole, key: const Key('profil-role'), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
            builder: (_, c) => Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final l in liens)
                    if (ouvert(l.$2))
                      SizedBox(
                        width: (c.maxWidth - 8) / 2,
                        child: InkWell(
                          key: Key('profil-lien:${l.$2}'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            fermer();
                            aller(l.$2);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(border: Border.all(color: JetonsShell.slate200), borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              Icon(l.$3, size: 16, color: JetonsShell.slate400),
                              const SizedBox(width: 8),
                              Expanded(child: Text(l.$1, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14))),
                            ]),
                          ),
                        ),
                      ),
                ])),
      ]),
      pied: (f) => [
            // Sans session (poste ouvert d'office sous un rôle), il n'y a rien à verrouiller : la commande est ABSENTE, non grisée.
            if (verrouiller != null)
              BoutonSigh(
                  key: const Key('profil-verrouiller'),
                  libelle: 'Verrouiller l’écran',
                  icone: LucideIcons.lock,
                  variante: VarianteBouton.secondaire,
                  onPressed: () {
                    fermer();
                    verrouiller();
                  }),
            BoutonSigh(
                key: const Key('profil-deconnexion'),
                libelle: 'Se déconnecter',
                icone: LucideIcons.logOut,
                variante: VarianteBouton.secondaire,
                onPressed: () {
                  fermer();
                  deconnecter();
                }),
          ]);
}
