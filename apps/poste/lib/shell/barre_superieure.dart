import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config_poste.dart';
import '../core/jetons_shell.dart';
import '../sync/etat_sync.dart';

/// Barre supérieure de la maquette (`#app-topbar`, 56 px, fond navy-950) : marque, recherche globale (Ctrl K),
/// Actions, plein écran, pastille d'état, cloche, profil. Même ordre, mêmes gabarits.
class BarreSuperieure extends StatelessWidget {
  const BarreSuperieure(
      {super.key,
      required this.config,
      required this.etatSync,
      required this.nomRole,
      this.surAccueil,
      this.nombreAlertes = 0});
  final ConfigPoste config;
  final SourceEtatSync etatSync;
  final String nomRole;
  final VoidCallback? surAccueil;
  final int nombreAlertes;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('barre-superieure'),
      height: 56,
      color: JetonsShell.navy950,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: InkWell(
            onTap: surAccueil,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset('assets/img/logo.jpeg',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NASSIERA TOO',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.2)),
                        Text(
                            config.estMere
                                ? 'SIGH — poste mère'
                                : 'SIGH — Gestion hospitalière',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: JetonsShell.navy300,
                                fontSize: 11,
                                height: 1.2)),
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
            child: Container(
              key: const Key('recherche-globale'),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF),
                  border: Border.all(color: const Color(0x26FFFFFF)),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(LucideIcons.search,
                    size: 16, color: JetonsShell.navy200),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text(
                        'Rechercher un patient, un produit, un employé, un écran…',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: JetonsShell.navy200, fontSize: 14))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x33FFFFFF)),
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('Ctrl K',
                      style: TextStyle(
                          color: JetonsShell.navy200,
                          fontSize: 10,
                          fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          ),
        ),
        const Spacer(),
        const _Outil(icone: LucideIcons.zap, libelle: 'Actions'),
        const _Outil(icone: LucideIcons.maximize, libelle: null),
        const SizedBox(width: 6),
        PastilleSync(source: etatSync),
        const SizedBox(width: 6),
        Stack(clipBehavior: Clip.none, children: [
          const _Outil(icone: LucideIcons.bell, libelle: null),
          if (nombreAlertes > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('$nombreAlertes',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
            ),
        ]),
        const SizedBox(width: 8),
        Row(children: [
          CircleAvatar(
              radius: 17,
              backgroundColor: JetonsShell.navy700,
              child: Text(_initiales(config.nomPoste),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config.nomPoste,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.2)),
                Text(nomRole,
                    key: const Key('role-courant'),
                    style: const TextStyle(
                        color: JetonsShell.navy300,
                        fontSize: 10.5,
                        height: 1.2)),
              ]),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevronDown,
              size: 14, color: JetonsShell.navy300),
        ]),
      ]),
    );
  }

  static String _initiales(String s) {
    final m =
        s.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (m.isEmpty) return '?';
    return (m.first[0] + (m.length > 1 ? m[1][0] : '')).toUpperCase();
  }
}

class _Outil extends StatelessWidget {
  const _Outil({required this.icone, required this.libelle});
  final IconData icone;
  final String? libelle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 36),
          padding: EdgeInsets.symmetric(horizontal: libelle == null ? 0 : 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icone,
                    size: libelle == null ? 20 : 16,
                    color: JetonsShell.navy100),
                if (libelle != null) ...[
                  const SizedBox(width: 8),
                  Text(libelle!,
                      style: const TextStyle(
                          color: JetonsShell.navy100, fontSize: 14))
                ],
              ]),
        ),
      );
}
