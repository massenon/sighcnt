import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/sauvegarde_fichiers_poste.dart';
import '../shell/contexte_ecran.dart';
import 'bouton.dart';
import 'carte.dart';
import 'detail.dart';
import 'fichiers_ui.dart' show noteRefus;
import 'modale.dart';
import 'toast.dart';
import 'ton.dart';

/// LA CARTE « SAUVEGARDE DES FICHIERS NUMÉRISÉS » (lot D5, étape 7) : la destination réglée, ce que la dernière passe a fait, le contrôle et la restauration. Les commandes de réglage et
/// de restauration sont ABSENTES sans le droit (administrateur et Directrice Administrative). Sans service installé (poste non préparé), la carte n'existe pas.
class CarteSauvegardeFichiers extends StatelessWidget {
  const CarteSauvegardeFichiers({super.key, required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.maybeOf(context);
    final s = c == null ? null : SauvegardeFichiersPoste.de(c.magasin);
    if (s == null) return const SizedBox.shrink();
    return ListenableBuilder(listenable: s, builder: (context, _) => _corps(context, s));
  }

  Widget _corps(BuildContext context, SauvegardeFichiersPoste s) {
    final d = s.destination;
    final r = s.dernier;
    final regle = s.peutRegler(role);
    final disque = switch (s.memeDisque) {
      MemeDisque.certain => 'MÊME DISQUE que les données : une panne du disque emporte les fichiers et leur copie. Choisir un autre disque.',
      MemeDisque.indetermine => 'Disque non déterminé par le poste : confirmer que ce dossier est sur un autre disque que les données (disque externe ou serveur).',
      MemeDisque.sansDestination => 'Aucune destination réglée : les fichiers numérisés ne sont sauvegardés nulle part (la sauvegarde du magasin ne les couvre pas).',
    };
    return CarteSigh(
        key: const Key('sauvfic:carte'),
        titre: 'Sauvegarde des fichiers numérisés',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Destination', d ?? 'Aucune'),
            if (s.reglePar != null) ('Réglée par', '${s.reglePar}'),
            (
              'Dernière passe',
              s.derniereErreur != null
                  ? 'EN ERREUR : ${s.derniereErreur!.code}'
                  : (r == null
                      ? 'Aucune passe depuis le démarrage'
                      : '${r.copies} copié${r.copies > 1 ? 's' : ''}, ${r.dejaCopies} déjà à la destination${r.restants > 0 ? ', ${r.restants} à la passe suivante' : ''}${r.alteres.isNotEmpty ? ', ${r.alteres.length} ALTÉRÉ${r.alteres.length > 1 ? 'S' : ''} à la source' : ''}')
            ),
            ('Conservation', 'Illimitée : la sauvegarde ne supprime ni ne remplace jamais une copie (RG-14).'),
          ]),
          const SizedBox(height: 8),
          NoteSigh(disque, key: const Key('sauvfic:disque'), ton: s.memeDisque == MemeDisque.sansDestination || s.memeDisque == MemeDisque.certain ? TonSigh.attention : TonSigh.info, icone: LucideIcons.hardDrive),
          if (s.derniereErreur != null) Padding(padding: const EdgeInsets.only(top: 8), child: noteRefus(s.derniereErreur!, key: const Key('sauvfic:erreur'))),
          if (r != null && (r.alteres.isNotEmpty || r.erreurs.isNotEmpty))
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: NoteSigh('Fichiers non copiés : ${[...r.alteres.map((x) => '${docAbrege(x)} (altéré à la source)'), ...r.erreurs].join(' ; ')}', ton: TonSigh.danger, icone: LucideIcons.triangleAlert)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (regle)
              BoutonSigh(key: const Key('sauvfic:regler'), libelle: 'Régler la destination', icone: LucideIcons.folderCog, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _regler(context, s)),
            if (d != null)
              BoutonSigh(
                  key: const Key('sauvfic:lancer'),
                  libelle: s.enCours ? 'Sauvegarde en cours…' : 'Sauvegarder maintenant',
                  icone: LucideIcons.databaseBackup,
                  taille: TailleBouton.sm,
                  onPressed: s.enCours ? null : () => s.lancer(manuel: true)),
            if (d != null && regle) ...[
              BoutonSigh(key: const Key('sauvfic:controler'), libelle: 'Contrôler la copie', icone: LucideIcons.shieldCheck, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _controler(context, s)),
              BoutonSigh(key: const Key('sauvfic:restaurer'), libelle: 'Restaurer les fichiers', icone: LucideIcons.rotateCcw, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _restaurer(context, s)),
            ],
          ]),
        ]));
  }

  Future<void> _regler(BuildContext context, SauvegardeFichiersPoste s) async {
    final chemin = TextEditingController(text: s.destination ?? '');
    final motif = TextEditingController();
    final refus = ValueNotifier<RefusFichier?>(null);
    await afficherModale<void>(context,
        titre: 'Destination de la sauvegarde des fichiers',
        taille: TailleModale.sm,
        corps: ValueListenableBuilder<RefusFichier?>(
            valueListenable: refus,
            builder: (_, r, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const NoteSigh(
                      'Le dossier doit exister (le poste ne le crée jamais), être inscriptible et se trouver, de préférence, sur un AUTRE disque que les données. Ce réglage est propre à ce poste.'),
                  const SizedBox(height: 12),
                  const Text('Chemin complet du dossier', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                  TextField(key: const Key('sauvfic:chemin'), controller: chemin),
                  const SizedBox(height: 12),
                  const Text('Motif (consigné dans le journal)', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                  TextField(key: const Key('sauvfic:motif'), controller: motif, maxLines: 2),
                  if (r != null) Padding(padding: const EdgeInsets.only(top: 8), child: noteRefus(r)),
                ])),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('sauvfic:enregistrer'),
                  libelle: 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () async {
                    final r = await s.definirDestination(role: role, chemin: chemin.text, motif: motif.text);
                    if (r != null) {
                      refus.value = r;
                      return;
                    }
                    fermer();
                    if (context.mounted) ToastsSigh.afficher(context, 'Destination réglée.', type: TypeToast.succes, detail: 'La première passe part dans l’heure, ou sur « Sauvegarder maintenant ».');
                  }),
            ]);
  }

  Future<void> _controler(BuildContext context, SauvegardeFichiersPoste s) async {
    final (rapport, refus) = await s.controler();
    if (!context.mounted) return;
    if (refus != null) {
      ToastsSigh.afficher(context, 'Contrôle impossible : ${refus.code}', type: TypeToast.erreur, detail: '${refus.motif} ${refus.geste}');
      return;
    }
    final r = rapport!;
    ToastsSigh.afficher(context, r.sain ? 'Copie intacte : ${r.intacts} fichier${r.intacts > 1 ? 's' : ''} relus.' : 'Copie à reprendre : ${r.manquants.length} manquant${r.manquants.length > 1 ? 's' : ''}, ${r.alteres.length} altéré${r.alteres.length > 1 ? 's' : ''}.',
        type: r.sain ? TypeToast.succes : TypeToast.erreur, detail: 'Chaque copie a été déchiffrée et son empreinte recalculée.');
  }

  Future<void> _restaurer(BuildContext context, SauvegardeFichiersPoste s) async {
    final (sim, refus) = await s.restaurer(role: role);
    if (!context.mounted) return;
    if (refus != null) {
      ToastsSigh.afficher(context, 'Restauration impossible : ${refus.code}', type: TypeToast.erreur, detail: '${refus.motif} ${refus.geste}');
      return;
    }
    final r = sim!;
    if (r.aRestaurer == 0) {
      ToastsSigh.afficher(context, 'Rien à restaurer.', type: r.sain ? TypeToast.succes : TypeToast.erreur, detail: '${r.dejaIntacts} fichier${r.dejaIntacts > 1 ? 's' : ''} intact${r.dejaIntacts > 1 ? 's' : ''} sur ce poste${r.copiesAlterees.isEmpty ? '' : ' ; ${r.copiesAlterees.length} copie(s) de la sauvegarde altérée(s), jamais posée(s)'}.');
      return;
    }
    final ok = await confirmerSigh(context,
        titre: 'Restaurer ${r.aRestaurer} fichier${r.aRestaurer > 1 ? 's' : ''} ?',
        message: 'Simulation faite : ${r.aRestaurer} fichier${r.aRestaurer > 1 ? 's' : ''} manquant${r.aRestaurer > 1 ? 's' : ''} ou altéré${r.aRestaurer > 1 ? 's' : ''} sur ce poste seront reposés depuis la sauvegarde. Un fichier intact n’est jamais écrasé ; un fichier altéré est mis de côté (dossier _alteres) avant d’être remplacé.',
        libelleOk: 'Restaurer');
    if (!ok || !context.mounted) return;
    final (reel, refus2) = await s.restaurer(role: role, simulation: false);
    if (!context.mounted) return;
    if (refus2 != null || reel == null) {
      ToastsSigh.afficher(context, 'Restauration impossible : ${refus2?.code}', type: TypeToast.erreur, detail: '${refus2?.motif} ${refus2?.geste}');
      return;
    }
    ToastsSigh.afficher(context, '${reel.restaures} fichier${reel.restaures > 1 ? 's' : ''} restauré${reel.restaures > 1 ? 's' : ''}.',
        type: reel.sain ? TypeToast.succes : TypeToast.erreur,
        detail: '${reel.misDeCote} mis de côté${reel.copiesAlterees.isEmpty ? '' : ' ; ${reel.copiesAlterees.length} copie(s) altérée(s) jamais posée(s)'}${reel.erreurs.isEmpty ? '' : ' ; ${reel.erreurs.length} erreur(s)'}.');
  }
}
