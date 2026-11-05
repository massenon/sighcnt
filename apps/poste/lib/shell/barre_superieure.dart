import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config_poste.dart';
import '../core/jetons_shell.dart';
import '../sync/etat_sync.dart';
import 'centre_notifications.dart';
import 'logo_clinique.dart';
import 'menus_barre.dart' show initialesDe;

/// Barre supérieure de la maquette (`#app-topbar`, 56 px, fond navy-950) : marque, recherche globale (Ctrl K), Actions, plein écran, pastille d'état,
/// cloche, profil. Même ordre, mêmes gabarits. Chaque bouton AGIT : la barre ne décide de rien, elle appelle ce que la coque lui donne (recherche,
/// actions rapides, plein écran, centre de notifications, menu du profil). Un bouton sans geste branché est ABSENT de l'arbre de gestes, jamais un décor.
class BarreSuperieure extends StatelessWidget {
  const BarreSuperieure(
      {super.key,
      required this.config,
      required this.etatSync,
      required this.nomRole,
      this.nomAgent,
      this.surAccueil,
      this.nombreAlertes = 0,
      this.centre,
      this.surRecherche,
      this.surActions,
      this.surPleinEcran,
      this.pleinEcran,
      this.surNotifications,
      this.surProfil,
      this.installation,
      this.surInstallation,
      this.selecteurExercice});
  final ConfigPoste config;
  final SourceEtatSync etatSync;
  final String nomRole;

  /// Le nom de l'agent connecté (session nominative) ; à défaut, le nom du poste.
  final String? nomAgent;
  final VoidCallback? surAccueil;

  /// Compte de la cloche quand aucun [centre] n'est branché (compat.).
  final int nombreAlertes;

  /// Le moteur de notifications : le badge de la cloche en est le compte RÉEL des alertes non acquittées, routées pour ce rôle.
  final CentreNotifications? centre;
  final VoidCallback? surRecherche, surActions, surPleinEcran, surNotifications, surProfil;

  /// L'assistant de première installation : tant qu'il est en cours, une pastille « Configurations à faire » rouvre sa modale (administrateur seulement).
  final ValueListenable<bool>? installation;
  final VoidCallback? surInstallation;

  /// Le sélecteur d'exercice, posé SEULEMENT sur les écrans qui ont une notion d'année (règle `cpcAExercice`).
  final Widget? selecteurExercice;

  /// L'état réel du plein écran (suit F11 et la sortie par le système) ; absent = fenêtre.
  final ValueListenable<bool>? pleinEcran;

  @override
  Widget build(BuildContext context) {
    final nom = nomAgent ?? config.nomPoste;
    return Container(
      key: const Key('barre-superieure'),
      height: 56,
      color: JetonsShell.navy950,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: InkWell(
            key: const Key('barre-marque'),
            onTap: surAccueil,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                Container(
                  key: const Key('barre-logo'),
                  width: 52,
                  height: 36,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: const LogoClinique(largeur: 46, hauteur: 32),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('NASSIERA TOO',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.2)),
                    Text(config.estMere ? 'SIGH — poste mère' : 'SIGH — Gestion hospitalière',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.navy300, fontSize: 11, height: 1.2)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Semantics(
              button: true,
              label: 'Recherche globale',
              child: InkWell(
                key: const Key('recherche-globale'),
                onTap: surRecherche,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF), border: Border.all(color: const Color(0x26FFFFFF)), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(LucideIcons.search, size: 16, color: JetonsShell.navy200),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('Rechercher un patient, un produit, un employé, un écran…',
                            overflow: TextOverflow.ellipsis, style: TextStyle(color: JetonsShell.navy200, fontSize: 14))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0x33FFFFFF)), borderRadius: BorderRadius.circular(4)),
                      child: const Text('Ctrl K', style: TextStyle(color: JetonsShell.navy200, fontSize: 10, fontWeight: FontWeight.w500)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        if (selecteurExercice != null) selecteurExercice!,
        _Outil(cle: 'barre-actions', icone: LucideIcons.zap, libelle: 'Actions', info: 'Actions rapides', surTap: surActions),
        if (pleinEcran != null)
          ValueListenableBuilder<bool>(
              valueListenable: pleinEcran!,
              builder: (_, on, __) => _Outil(
                  cle: 'barre-plein-ecran',
                  icone: on ? LucideIcons.minimize : LucideIcons.maximize,
                  info: on ? 'Quitter le plein écran (Échap)' : 'Plein écran (F11)',
                  surTap: surPleinEcran))
        else
          _Outil(cle: 'barre-plein-ecran', icone: LucideIcons.maximize, info: 'Plein écran (F11)', surTap: surPleinEcran),
        const SizedBox(width: 6),
        if (installation != null)
          ValueListenableBuilder<bool>(
              valueListenable: installation!,
              builder: (_, on, __) => on
                  ? Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _Outil(cle: 'barre-installation', icone: LucideIcons.listChecks, info: 'Configurations à faire avant l’utilisation', surTap: surInstallation))
                  : const SizedBox.shrink()),
        PastilleSync(source: etatSync),
        const SizedBox(width: 6),
        _Cloche(centre: centre, repli: nombreAlertes, surTap: surNotifications),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Profil utilisateur',
          child: InkWell(
            key: const Key('barre-profil'),
            onTap: surProfil,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(children: [
                CircleAvatar(
                    radius: 17,
                    backgroundColor: JetonsShell.navy700,
                    child: Text(initialesDe(nom), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(nom,
                          key: const Key('nom-courant'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2))),
                  Text(nomRole, key: const Key('role-courant'), style: const TextStyle(color: JetonsShell.navy300, fontSize: 10.5, height: 1.2)),
                ]),
                const SizedBox(width: 4),
                const Icon(LucideIcons.chevronDown, size: 14, color: JetonsShell.navy300),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// La cloche : le badge est le compte RÉEL des alertes non acquittées routées pour le rôle (jamais un chiffre écrit en dur : un badge qui compte ce qu'on ne
/// compte pas est pire qu'un badge absent). Il se met à jour à chaque écriture d'une collection que le moteur lit.
class _Cloche extends StatelessWidget {
  const _Cloche({required this.centre, required this.repli, required this.surTap});
  final CentreNotifications? centre;
  final int repli;
  final VoidCallback? surTap;

  @override
  Widget build(BuildContext context) {
    Widget corps(int n) => Stack(clipBehavior: Clip.none, children: [
          _Outil(
              cle: 'barre-cloche',
              icone: LucideIcons.bell,
              info: n > 0 ? '$n alerte(s) en attente' : 'Notifications : aucune alerte en attente',
              surTap: surTap),
          if (n > 0)
            Positioned(
              right: 2,
              top: 2,
              child: IgnorePointer(
                child: Container(
                    key: const Key('cloche-badge'),
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(8)),
                    child: Text(n > 99 ? '99+' : '$n',
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
              ),
            ),
        ]);
    final c = centre;
    if (c == null) return corps(repli);
    return ListenableBuilder(listenable: c, builder: (_, __) => corps(c.enAttente().length));
  }
}

class _Outil extends StatelessWidget {
  const _Outil({required this.cle, required this.icone, required this.surTap, this.libelle, this.info});
  final String cle;
  final IconData icone;
  final String? libelle;
  final String? info;
  final VoidCallback? surTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message: info ?? libelle ?? '',
          child: Semantics(
            button: true,
            label: info ?? libelle,
            excludeSemantics: true,
            onTap: surTap,
            child: InkWell(
              key: Key(cle),
              onTap: surTap,
              borderRadius: BorderRadius.circular(8),
              hoverColor: const Color(0x1AFFFFFF),
              child: Container(
                height: 36,
                constraints: const BoxConstraints(minWidth: 36),
                padding: EdgeInsets.symmetric(horizontal: libelle == null ? 0 : 12),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icone, size: libelle == null ? 20 : 16, color: JetonsShell.navy100),
                  if (libelle != null) ...[const SizedBox(width: 8), Text(libelle!, style: const TextStyle(color: JetonsShell.navy100, fontSize: 14))],
                ]),
              ),
            ),
          ),
        ),
      );
}
