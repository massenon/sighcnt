import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';
import 'factures.dart';
import 'impression.dart';

/// `m8-proforma` — estimations remises avant réalisation des prestations. AUCUNE valeur fiscale : ni justificatif comptable, ni MECeF.
class EcranProforma extends StatelessWidget with EcranMaquette {
  const EcranProforma({super.key});

  @override
  String get description =>
      'Estimations remises au patient ou à l’assureur avant réalisation des prestations.';

  @override
  String get regle =>
      'La facture pro-forma n’a aucune valeur fiscale : elle ne peut ni servir de justificatif comptable ni être transmise au dispositif MECeF.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('factures');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final toutes = col.actives;
        final rows = [
          for (final f in toutes)
            if (f['proforma'] == true || '${f['numero']}'.startsWith('PRO-')) f
        ];
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Pro-forma établies',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.fileText),
                KpiSigh(
                    libelle: 'Montant estimé',
                    valeur: money(
                        rows.fold<num>(0, (a, r) => a + n(r['montantTTC']))),
                    icone: LucideIcons.calculator,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Converties en facture',
                    valeur: nombre(0),
                    icone: LucideIcons.fileCheck2,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Factures normalisées',
                    valeur: nombre(toutes.length - rows.length),
                    icone: LucideIcons.fileBadge,
                    ton: TonSigh.neutre),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Factures pro-forma',
                colonnes: [
                  colNumero,
                  colDate,
                  colPatient,
                  ColonneTableau(
                      cle: 'type',
                      libelle: 'Nature',
                      rendu: (_, f) =>
                          BadgeSigh('${f['type'] ?? ''}', ton: TonSigh.navy),
                      texte: (f) => '${f['type'] ?? ''}'),
                  colMontant,
                ],
                lignes: rows,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'proforma',
                messageVide: 'Aucune facture pro-forma établie.',
                indiceVide:
                    'Les pro-forma se créent depuis l’écran « Nouvelle facture ».',
                alClicLigne: (f) => afficherTiroir<void>(context,
                    titre: '${f['numero']}',
                    sousTitre: '${f['patient'] ?? ''}',
                    corps: detailFacture(f),
                    pied: (_) => [
                          BoutonSigh(
                              libelle: 'Imprimer',
                              icone: LucideIcons.printer,
                              onPressed: () =>
                                  imprimerFacture(context, f, proforma: true))
                        ]),
                actionsLigne: (ctx, f) => [
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer',
                      onPressed: () => imprimerFacture(ctx, f, proforma: true))
                ],
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouvelle pro-forma',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => c.aller('m8-facturation')),
                ],
              ),
            ]);
      },
    );
  }
}
