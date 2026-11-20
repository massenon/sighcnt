import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../kit/badge.dart';
import '../kit/bouton.dart';
import '../kit/modale.dart';
import '../kit/ton.dart';
import 'centre_notifications.dart';

TonSigh _ton(String priorite) => switch (priorite) { 'critique' => TonSigh.danger, 'important' => TonSigh.attention, _ => TonSigh.info };

/// Le CENTRE DE NOTIFICATIONS (la cloche) et, à l'ouverture de session, « À votre arrivée » : le MÊME modal, deux entrées.
///
///  - il AFFICHE ce que le moteur route (poste, droits, regroupement au-delà de trois) ; il ne décide de rien ;
///  - ENTENDRE N'EST PAS TRAITER : « Acquitter » sort l'alerte du badge, elle reste au centre tant que sa cause dure ;
///  - un modal vide et muet est interdit : rien à faire se DIT (« Rien ne vous attend ») ;
///  - à l'ouverture de session, le modal peut être lu par-dessus l'épaule : les notifications de poste, qui portent un nom de patient, n'y sont pas
///    détaillées (jamais de donnée médicale dans un message qui s'ouvre de lui-même). Le centre de la cloche, lui, les détaille.
Future<void> ouvrirCentreNotifications(
  BuildContext context, {
  required CentreNotifications centre,
  required void Function(String ecran) aller,
  bool ouverture = false,
}) =>
    afficherModale<void>(context,
        titre: ouverture ? 'À votre arrivée' : 'Notifications',
        sousTitre: ouverture ? 'Ce qui attend votre poste, d’après vos droits.' : null,
        corps: _CorpsNotifications(
            centre: centre,
            ouverture: ouverture,
            aller: (e) {
              Navigator.of(context, rootNavigator: true).pop();
              aller(e);
            }),
        pied: (fermer) => [BoutonSigh(libelle: ouverture ? 'J’ai pris connaissance' : 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);

class _CorpsNotifications extends StatelessWidget {
  const _CorpsNotifications({required this.centre, required this.ouverture, required this.aller});
  final CentreNotifications centre;
  final bool ouverture;
  final void Function(String ecran) aller;

  Map<String, Object?> _params() {
    final f = centre.magasin.collection('reglages').actives.where((x) => x['id'] == 'notificationsSon').firstOrNull;
    final v = f?['valeur'];
    return cfbParamsNotif(v is Map ? v.cast<String, Object?>() : null);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: centre,
      builder: (context, _) {
        final liste = centre.collecter();
        final p = _params();
        final audio = centre.audioDisponible;
        final texteSon = (audio != null && !audio())
            ? 'Sonorisation indisponible sur ce poste. Les alertes restent visibles.'
            : (p['son'] == true ? 'Sonorisation active, profil ${cfbProfilAudio(p['profil']).$2.toLowerCase()}' : 'Sonorisation désactivée. Les alertes restent visibles.');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (liste.isEmpty) _vide() else ..._groupes(liste),
          const SizedBox(height: 12),
          Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate200))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(texteSon, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12))),
                if (centre.donnees().matrice.peutVoir(centre.role(), 'cfg-notifications'))
                  InkWell(
                      key: const Key('notif-parametrer'),
                      onTap: () => aller('cfg-notifications'),
                      child: const Text('Paramétrer', style: TextStyle(color: JetonsShell.navy700, fontSize: 12, fontWeight: FontWeight.w500))),
              ])),
        ]);
      });

  Widget _vide() => Container(
      key: const Key('notif-vide'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: JetonsShell.success50, border: Border.all(color: JetonsShell.success200), borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(LucideIcons.circleCheck, size: 20, color: JetonsShell.success600),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ouverture ? 'Rien ne vous attend' : 'Aucune alerte en cours',
              style: const TextStyle(color: JetonsShell.success900, fontSize: 14, fontWeight: FontWeight.w500)),
          const Text('Rien ne requiert votre attention à ce poste.', style: TextStyle(color: JetonsShell.success700, fontSize: 12)),
        ])),
      ]));

  List<Widget> _groupes(List<AlerteNotif> liste) {
    // Métier et système restent SÉPARÉS ; à l'ouverture de session, le métier se range par FAMILLE (stock, comptabilité, à valider, laboratoire…).
    final groupes = <(String, List<AlerteNotif>)>[];
    if (ouverture) {
      final domaines = <String>[];
      for (final n in liste.where((n) => n.categorie == 'metier')) {
        if (!domaines.contains(n.domaine)) domaines.add(n.domaine);
      }
      for (final d in domaines) {
        groupes.add((d, [for (final n in liste) if (n.categorie == 'metier' && n.domaine == d) n]));
      }
      groupes.add(('Système', [for (final n in liste) if (n.categorie == 'systeme') n]));
    } else {
      groupes.add(('Alertes métier', [for (final n in liste) if (n.categorie == 'metier') n]));
      groupes.add(('Système', [for (final n in liste) if (n.categorie == 'systeme') n]));
    }
    return [
      for (final g in groupes)
        if (g.$2.isNotEmpty) ...[
          Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text('${g.$1.toUpperCase()} : ${g.$2.length}',
                  style: const TextStyle(color: JetonsShell.slate400, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.6))),
          for (final n in g.$2) _ligne(n),
        ]
    ];
  }

  Widget _ligne(AlerteNotif n) {
    final ton = _ton(n.priorite);
    // Un message d'ouverture de session reste générique pour les notifications de poste (elles nomment un patient).
    final masque = ouverture && n.source == 'poste' && !n.groupe;
    return Container(
      key: Key('notif-ligne:${n.cle}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: n.acquittee ? JetonsShell.slate50 : Colors.white, border: Border.all(color: JetonsShell.slate200), borderRadius: BorderRadius.circular(8)),
      child: Opacity(
        opacity: n.acquittee ? 0.7 : 1,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: ton.fond50, borderRadius: BorderRadius.circular(8)),
              child: Icon(n.acquittee ? LucideIcons.bellOff : LucideIcons.bellRing, size: 16, color: ton.icone600)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(masque ? 'Notification de poste' : n.titre, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, fontWeight: FontWeight.w500)),
            if (masque || n.detail.isNotEmpty)
              Text(masque ? 'Ouvrir l’écran concerné pour le détail.' : n.detail, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              BadgeSigh(libellePriorite(n.priorite), ton: ton),
              Text(n.domaine, style: const TextStyle(color: JetonsShell.slate400, fontSize: 10)),
              if (n.acquittee) const Text('· acquittée', style: TextStyle(color: JetonsShell.slate400, fontSize: 10, fontStyle: FontStyle.italic)),
            ]),
          ])),
          const SizedBox(width: 8),
          SizedBox(width: 92, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (n.lien != null)
              BoutonSigh(
                  key: Key('notif-voir:${n.cle}'), libelle: 'Voir', taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => aller(n.lien!)),
            const SizedBox(height: 4),
            BoutonSigh(
                key: Key('notif-acquitter:${n.cle}'),
                libelle: n.acquittee ? 'Reprendre' : 'Acquitter',
                taille: TailleBouton.sm,
                variante: VarianteBouton.fantome,
                onPressed: () => n.acquittee ? centre.reprendre(n) : centre.acquitter(n)),
          ])),
        ]),
      ),
    );
  }
}
