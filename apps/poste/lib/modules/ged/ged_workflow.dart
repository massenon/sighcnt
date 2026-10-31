import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'ged_commun.dart';

/// `ged-workflow` — « Workflow de validation » : la FILE de validation des documents déposés (contrôle, signature, classement). On y valide ou l'on
/// rejette, on n'y crée pas : un document se dépose depuis la bibliothèque, un rejet le renvoie à son déposant avec son motif.
///
/// Valider un document le SIGNE (signature électronique, qui verrouille la pièce) ; valider une SÉLECTION ne pose que l'état — la maquette ne signe
/// pas en masse (E561, porté fidèlement). Les commandes de validation et de rejet sont ABSENTES sans le droit d'écrire sur l'écran (E563) ; le rejet
/// exige son motif (E564). Archiver ne se fait pas ici : RG-14 vit à l'archivage.
class EcranWorkflowGed extends StatelessWidget with EcranMaquette {
  const EcranWorkflowGed({super.key});

  @override
  String get titre => 'Workflow de validation';

  @override
  String get description =>
      'Circuit de validation des documents déposés : contrôle, signature et classement.';

  @override
  String get regle =>
      'Écran de file de validation : on y valide ou l’on rejette, on n’y crée pas. Un document se dépose depuis la bibliothèque ; un rejet le renvoie à son déposant avec son motif.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = colDocuments(c.magasin);
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final actifs = col.actives;
          final enAttente = [
            for (final d in actifs)
              if (d['etatValidation'] == 'en_attente') d
          ];
          int nb(String e) => actifs.where((d) => d['etatValidation'] == e).length;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Les indicateurs se RECALCULENT à chaque geste (E562, corrigé dans la maquette).
                KpiGrilleSigh(kpis: [
                  KpiSigh(
                      libelle: 'Documents à valider',
                      valeur: nombre(enAttente.length),
                      icone: LucideIcons.fileClock,
                      ton: TonSigh.attention),
                  KpiSigh(
                      libelle: 'Rejetés à corriger',
                      valeur: nombre(nb('rejete')),
                      icone: LucideIcons.fileX,
                      ton: TonSigh.danger),
                  KpiSigh(
                      libelle: 'Validés',
                      valeur: nombre(nb('valide')),
                      icone: LucideIcons.fileCheck2,
                      ton: TonSigh.succes),
                  const KpiSigh(
                      libelle: 'Délai moyen de validation',
                      valeur: '2 jours',
                      icone: LucideIcons.timer,
                      ton: TonSigh.info),
                ]),
                const SizedBox(height: 16),
                CarteSigh(
                    titre: 'Circuit de validation documentaire',
                    child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final (i, e) in qualGedEtapes.indexed) ...[
                            _etape(e),
                            if (i < qualGedEtapes.length - 1)
                              const Icon(LucideIcons.chevronRight,
                                  size: 14, color: JetonsShell.slate300),
                          ],
                        ])),
                const SizedBox(height: 16),
                _tableau(context, c, col, enAttente),
                const SizedBox(height: 16),
                const NoteSigh(
                    'La validation appose une signature électronique et verrouille le document : toute modification ultérieure crée une nouvelle version.',
                    icone: LucideIcons.penTool),
              ]);
        });
  }

  Widget _etape((String, String, String, String) e) {
    final ton = tonDe(e.$3);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: ton.fond50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ton.bordure200)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(iconeGed(e.$4), size: 16, color: ton.icone600),
          const SizedBox(width: 8),
          Text(e.$2,
              style: TextStyle(
                  color: ton.texte900, fontSize: 12, fontWeight: FontWeight.w500)),
        ]));
  }

  Widget _tableau(BuildContext context, ContexteEcran c, CollectionMagasin col,
      List<Fiche> enAttente) {
    final peutEcrire = c.droit.editer;
    return TableauSigh(
      titre: 'Documents en attente de validation',
      lignes: enAttente,
      taillePage: 15,
      nomExport: 'ged-a-valider',
      triInitial: 'date',
      sensInitial: 'desc',
      selectionnable: peutEcrire,
      messageVide: 'Aucun document en attente de validation.',
      colonnes: [
        colonneReference(),
        const ColonneTableau(cle: 'libelle', libelle: 'Document'),
        colonneCategorie(),
        const ColonneTableau(cle: 'rattacheA', libelle: 'Rattaché à'),
        ColonneTableau(
            cle: 'date',
            libelle: 'Date de dépôt',
            sansCoupure: true,
            texte: (d) => dateDe(d['date'])),
        const ColonneTableau(cle: 'deposePar', libelle: 'Déposé par'),
        ColonneTableau(
            cle: 'anciennete',
            libelle: 'En attente depuis',
            droite: true,
            valeur: (d) => qualGedAnciennete(d, c.aujourdhui),
            texte: (d) => '${qualGedAnciennete(d, c.aujourdhui)} j',
            rendu: (_, d) {
              final j = qualGedAnciennete(d, c.aujourdhui);
              return Text('$j j',
                  style: TextStyle(
                      color: j > 15 ? JetonsShell.danger600 : JetonsShell.slate700,
                      fontSize: 14,
                      fontWeight: j > 15 ? FontWeight.w600 : FontWeight.w400));
            }),
      ],
      actionsGroupe: peutEcrire
          ? (ctx, sel, effacer) => [
                BoutonSigh(
                    libelle: 'Valider la sélection',
                    icone: LucideIcons.badgeCheck,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.succes,
                    onPressed: () {
                      // La sélection se valide SANS signature : l'état seul change (E561).
                      final annulations = [
                        for (final d in sel)
                          col.mettreAJour(d['id'], {...qualGedValidationSelection})
                      ];
                      effacer();
                      ToastsSigh.afficher(context, '${sel.length} document(s) validé(s).',
                          type: TypeToast.succes, annuler: () {
                        for (final u in annulations) {
                          u();
                        }
                      });
                    }),
              ]
          : null,
      actionsLigne: (ctx, d) => [
        if (peutEcrire) ...[
          BoutonSigh(
              libelle: 'Valider',
              icone: LucideIcons.check,
              taille: TailleBouton.sm,
              variante: VarianteBouton.succes,
              onPressed: () {
                final annuler = col.mettreAJour(d['id'], {...qualGedValidationSignee});
                ToastsSigh.afficher(context, 'Document validé et signé.',
                    type: TypeToast.succes, annuler: annuler);
              }),
          BoutonIcone(
              icone: LucideIcons.x,
              libelle: 'Rejeter',
              onPressed: () async {
                final motif = await confirmerAvecMotif(context,
                    titre: 'Rejeter ce document ?',
                    message: 'Le document sera renvoyé à son déposant pour correction.',
                    libelleOk: 'Rejeter',
                    dangereux: true);
                if (motif == null || !context.mounted) return;
                final annuler = col.mettreAJour(d['id'], qualGedRejet(motif));
                ToastsSigh.afficher(context, 'Document rejeté.',
                    type: TypeToast.attention, annuler: annuler);
              }),
        ],
      ],
    );
  }
}
