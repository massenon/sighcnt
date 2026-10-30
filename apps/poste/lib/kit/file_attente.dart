import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';
import '../shell/contexte_ecran.dart';
import 'badge.dart';
import 'bouton.dart';
import 'carte.dart';
import 'tableau.dart';
import 'toast.dart';
import 'ton.dart';

/// `K.fileAttente(type, cfg)` : la file des tâches d'un poste. L'ORDRE EST CELUI DU TERRAIN : ce qui est PAYÉ d'abord (les plus anciennes en tête),
/// puis ce qui attend encore la caisse — visible (le laboratoire doit savoir ce qui arrive) mais après. Une tâche bloquée n'est pas exécutable ;
/// un profil qui LIT l'écran sans pouvoir écrire voit la file mais ne l'exécute pas (commande verrouillée et NOMMÉE, pas retirée).
class FileAttenteSigh extends StatelessWidget {
  const FileAttenteSigh({
    super.key,
    required this.type,
    this.titre = 'File d’attente',
    this.vide = 'Rien en attente — la file est vide.',
    this.icone = LucideIcons.check,
    this.action = 'Traiter',
    required this.surAction,
  });

  final String type;
  final String titre;
  final String vide;
  final IconData icone;
  final String action;
  final void Function(BuildContext, Fiche tache) surAction;

  static String _date(Fiche t) => '${t['date'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('taches');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final taches = [
          for (final t in col.actives)
            if (t['statut'] != 'fait' && t['type'] == type) t
        ]..sort((a, b) => (b['urgent'] == true ? 1 : 0)
                    .compareTo(a['urgent'] == true ? 1 : 0) !=
                0
            ? (b['urgent'] == true ? 1 : -1)
            : _date(a).compareTo(_date(b)));
        if (taches.isEmpty)
          return CarteSigh(
              titre: titre,
              child: VideSigh(vide, icone: LucideIcons.circleCheck));
        final pretes = [
          for (final t in taches)
            if (t['statut'] == 'en_attente') t
        ]..sort((a, b) => _date(a).compareTo(_date(b)));
        final bloquees = [
          for (final t in taches)
            if (t['statut'] == 'bloque') t
        ]..sort((a, b) => _date(a).compareTo(_date(b)));
        final ordonnees = [...pretes, ...bloquees];
        return CarteSigh(
          titre:
              '$titre — ${pretes.length} à traiter${bloquees.isNotEmpty ? ', ${bloquees.length} en attente de caisse' : ''}',
          sansRemplissage: true,
          child: TableauSigh(
            lignes: ordonnees,
            taillePage: 8,
            nomExport: 'file-$type',
            colonnes: [
              ColonneTableau(
                  cle: 'reference',
                  libelle: 'Origine',
                  sansCoupure: true,
                  texte: (r) => '${r['reference'] ?? ''}',
                  rendu: (_, r) =>
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${r['reference'] ?? ''}',
                            style: const TextStyle(
                                fontFamily: 'LiberationMono',
                                fontSize: 12,
                                color: JetonsShell.slate700)),
                        if (r['urgent'] == true)
                          const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: BadgeSigh('Urgent', ton: TonSigh.danger)),
                      ])),
              ColonneTableau(
                  cle: 'patient',
                  libelle: 'Patient',
                  texte: (r) =>
                      '${r['patient'] ?? ''} ${r['patientCode'] ?? ''}',
                  rendu: (_, r) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${r['patient'] ?? ''}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: JetonsShell.slate800,
                                    fontSize: 14,
                                    height: 20 / 14,
                                    fontWeight: FontWeight.w500)),
                            Text('${r['patientCode'] ?? ''}',
                                style: const TextStyle(
                                    fontFamily: 'LiberationMono',
                                    fontSize: 12,
                                    color: JetonsShell.slate400)),
                          ])),
              const ColonneTableau(cle: 'detail', libelle: 'À faire'),
              ColonneTableau(
                  cle: 'montant',
                  libelle: 'Montant',
                  droite: true,
                  texte: (r) => money(r['montant'] ?? 0, avecDevise: false)),
              ColonneTableau(
                  cle: 'statut',
                  libelle: 'État',
                  sansCoupure: true,
                  texte: (r) => r['statut'] == 'bloque'
                      ? 'Attente encaissement'
                      : 'À traiter',
                  rendu: (_, r) => r['statut'] == 'bloque'
                      ? const BadgeSigh('Attente encaissement',
                          ton: TonSigh.attention)
                      : const BadgeSigh('À traiter', ton: TonSigh.info)),
            ],
            actionsLigne: (ctx, r) {
              if (r['statut'] == 'bloque') {
                return [
                  BoutonIcone(
                      icone: LucideIcons.lock,
                      libelle: 'Bloquée jusqu’à l’encaissement',
                      onPressed: () => ToastsSigh.afficher(
                          ctx, 'Cette opération attend le passage en caisse.',
                          type: TypeToast.attention))
                ];
              }
              if (!c.droit.editer) {
                return [
                  BoutonIcone(
                      icone: LucideIcons.lock,
                      libelle:
                          'Votre profil consulte cette file sans l’exécuter',
                      onPressed: () => ToastsSigh.afficher(ctx,
                          'Votre profil consulte cette file sans pouvoir la traiter.',
                          type: TypeToast.attention))
                ];
              }
              return [
                BoutonIcone(
                    icone: icone,
                    libelle: action,
                    onPressed: () => surAction(ctx, r))
              ];
            },
          ),
        );
      },
    );
  }
}
