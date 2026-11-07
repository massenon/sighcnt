import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'res_commun.dart';

/// `m5-impression-resultats` — « Impression des résultats », FILTRÉE PAR LE RÈGLEMENT. Le compte rendu ne sort que pour un examen RÉGLÉ à la
/// caisse. Un résultat non réglé reste VISIBLE — le masquer ferait croire à une analyse non faite — mais son impression est VERROUILLÉE, en le
/// disant : la balle est à la caisse, pas au laboratoire. Les demandes d'avant les lignes payables n'ont pas de pièce de caisse liée : elles sont
/// signalées « sans pièce liée », ce qui n'est ni réglé ni dû.
class EcranImpressionResultats extends StatelessWidget with EcranMaquette {
  const EcranImpressionResultats({super.key, this.fonction, this.secteur, this.agentId});
  final String? fonction;
  final String? secteur;
  final String? agentId;

  @override
  String get titre => 'Impression des résultats';

  @override
  String get description =>
      'Édition des comptes rendus, réservée aux examens réglés : un résultat dont l’examen n’est pas payé reste visible mais ne s’imprime pas.';

  @override
  String get regle =>
      'Le compte rendu ne sort que pour un examen réglé à la caisse. Un résultat non réglé reste visible — le masquer ferait croire à une analyse non faite — mais son impression est verrouillée, en le disant : la balle est à la caisse, pas au laboratoire. Les demandes antérieures aux lignes payables n’ont pas de pièce de caisse liée : elles sont signalées « sans pièce liée », ce qui n’est ni réglé ni dû.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final p = profilLabo(c, fonction: fonction, secteur: secteur, agentId: agentId);
    return ListenableBuilder(
      listenable: ecouteLabo(c),
      builder: (context, _) {
        final rows = filtrerResultats([
          for (final r in c.magasin.collection('demandesAnalyses').actives)
            if (estRendu(r['etatAnalyse'])) r
        ], p.session);
        final idx = indexReglements(c.magasin.collection('factures').actives);
        int compter(String s) => rows.where((r) => reglementDemande(r, idx).statut == s).length;
        final regles = compter('regle'), dus = compter('du'), sans = compter('non_trace');

        final colonnes = colonnesDemande();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Résultats rendus',
                valeur: nombre(rows.length),
                icone: LucideIcons.fileCheck2,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Imprimables (réglés)',
                valeur: nombre(regles),
                icone: LucideIcons.printer,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Verrouillés — règlement dû',
                valeur: nombre(dus),
                icone: LucideIcons.lock,
                ton: dus > 0 ? TonSigh.danger : TonSigh.neutre,
                indice: 'La balle est à la caisse'),
            KpiSigh(
                libelle: 'Sans pièce de caisse liée',
                valeur: nombre(sans),
                icone: LucideIcons.circleHelp,
                ton: TonSigh.neutre,
                indice: 'Antérieurs aux lignes payables'),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Comptes rendus à éditer',
            taillePage: 12,
            triInitial: 'dateHeure',
            sensInitial: 'desc',
            nomExport: 'impression-resultats',
            messageVide: 'Aucun résultat rendu dans votre périmètre.',
            lignes: rows,
            colonnes: [
              ...colonnes.take(5),
              ColonneTableau(
                  cle: 'reglement',
                  libelle: 'Règlement',
                  valeur: (r) => reglementDemande(r, idx).statut,
                  texte: (r) {
                    final g = reglementDemande(r, idx);
                    return '${g.libelle} ${g.facture ?? ''}';
                  },
                  rendu: (_, r) {
                    final g = reglementDemande(r, idx);
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          badgeReglement(g),
                          if (g.facture != null)
                            Text(g.facture!,
                                style: styleLabo(10,
                                    couleur: JetonsShell.slate400, police: 'monospace')),
                        ]);
                  }),
            ],
            alClicLigne: (r) => afficherTiroir<void>(context,
                titre: '${r['analyse']}',
                sousTitre:
                    '${r['patient']} — ${(r['codeAnalyse'] != null && r['codeAnalyse'] != '') ? r['codeAnalyse'] : r['reference']}',
                corps: detailDemande(r)),
            actionsLigne: (ctx, r) {
              final g = reglementDemande(r, idx);
              if (g.statut == 'du') {
                // Verrouillé et non masqué : le bouton dit pourquoi et chez qui.
                return [
                  commandeVerrouillee(
                      cle: Key('res:imprimer-verrou:${r['reference']}'),
                      libelle: 'Imprimer',
                      raison: motifImpressionVerrouillee(g),
                      alClic: () => ToastsSigh.afficher(
                          ctx, 'Impression verrouillée : examen non réglé.',
                          type: TypeToast.erreur,
                          detail:
                              'Le résultat existe et reste consultable, mais le compte rendu ne sort qu’après règlement${g.facture != null ? ' de la pièce ${g.facture}' : ''}. La balle est à la caisse.'))
                ];
              }
              return [
                commandeLigne(BoutonSigh(
                    key: Key('res:imprimer-resultat:${r['reference']}'),
                    libelle: 'Imprimer',
                    icone: LucideIcons.printer,
                    taille: TailleBouton.sm,
                    onPressed: () => imprimerResultat(ctx, r)))
              ];
            },
          ),
        ]);
      },
    );
  }
}
