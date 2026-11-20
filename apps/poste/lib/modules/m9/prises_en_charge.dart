import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/pv_crud.dart';
import 'commun.dart';

/// `m9-prises-en-charge` — « Prises en charge » : les factures qui portent une part assurance, avec la répartition patient / tiers payeur.
/// La correction d'une fiche (compagnie, taux, parts) est offerte à qui a le droit d'écrire ; jamais d'archivage depuis cet écran.
class EcranPrisesEnCharge extends StatelessWidget with EcranMaquette {
  const EcranPrisesEnCharge({super.key});

  @override
  String get titre => 'Prises en charge';

  @override
  String get description =>
      'Factures comportant une part assurance, avec répartition entre le patient et le tiers payeur.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, ['assureurs', 'factures']),
      builder: (context, _) {
        final assureurs = actives(c, 'assureurs');
        final rows = assFacturesAssurance(actives(c, 'factures'));
        final champs = <ChampDef>[
          ChampDef(
              nom: 'assureur',
              libelle: 'Compagnie',
              type: TypeChamp.select,
              options: [
                for (final a in assureurs)
                  OptionChamp('${a['code']}', '${a['nom']}')
              ]),
          const ChampDef(
              nom: 'tauxPriseEnCharge',
              libelle: 'Taux de prise en charge (%)',
              type: TypeChamp.nombre),
          const ChampDef(
              nom: 'partAssurance',
              libelle: 'Part assurance (FCFA)',
              type: TypeChamp.nombre),
          const ChampDef(
              nom: 'partPatient',
              libelle: 'Part patient (FCFA)',
              type: TypeChamp.nombre),
          const ChampDef(
              nom: 'observations',
              libelle: 'Observations',
              type: TypeChamp.textarea,
              lignes: 2,
              col: ColChamp.plein),
        ];
        num? nb(Object? v) => num.tryParse('${v ?? ''}'.trim());

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Prises en charge',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.shieldCheck),
                KpiSigh(
                    libelle: 'Montant total facturé',
                    valeur: money(assSomme(rows, 'montantTTC')),
                    icone: LucideIcons.receipt,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Part assureurs',
                    valeur: money(assSomme(rows, 'partAssurance')),
                    icone: LucideIcons.building2,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Part patients',
                    valeur: money(assSomme(rows, 'partPatient')),
                    icone: LucideIcons.users,
                    ton: TonSigh.succes),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Factures avec prise en charge',
                lignes: rows,
                taillePage: 15,
                nomExport: 'prises-en-charge',
                triInitial: 'date',
                sensInitial: 'desc',
                filtres: [
                  FiltreTableau(nom: 'assureur', libelle: 'Compagnie', options: [
                    for (final a in assureurs)
                      OptionChamp('${a['code']}', '${a['nom']}')
                  ]),
                  FiltreTableau(
                      nom: 'niveau',
                      libelle: 'Niveau de prise en charge',
                      options: [
                        OptionChamp('totale', 'Totale (100 %)'),
                        OptionChamp('partielle', 'Partielle')
                      ],
                      correspond: assNiveau),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'numero',
                      libelle: 'N° facture',
                      sansCoupure: true,
                      texte: (f) => '${f['numero'] ?? ''}',
                      rendu: (_, f) => monoTexte(f['numero'])),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      valeur: (f) => f['date'],
                      texte: (f) => dateDe(f['date'])),
                  const ColonneTableau(cle: 'patient', libelle: 'Assuré'),
                  ColonneTableau(
                      cle: 'assureur',
                      libelle: 'Compagnie',
                      texte: (f) => '${f['assureur']}',
                      rendu: (_, f) =>
                          BadgeSigh('${f['assureur']}', ton: TonSigh.navy)),
                  ColonneTableau(
                      cle: 'tauxPriseEnCharge',
                      libelle: 'Taux',
                      droite: true,
                      texte: (f) => '${f['tauxPriseEnCharge']} %',
                      rendu: (_, f) => BadgeSigh('${f['tauxPriseEnCharge']} %',
                          ton: n(f['tauxPriseEnCharge']) == 100
                              ? TonSigh.succes
                              : TonSigh.info)),
                  ColonneTableau(
                      cle: 'montantTTC',
                      libelle: 'Total',
                      droite: true,
                      texte: (f) => m(f['montantTTC'])),
                  ColonneTableau(
                      cle: 'partAssurance',
                      libelle: 'Part assureur',
                      droite: true,
                      texte: (f) => m(f['partAssurance']),
                      rendu: (_, f) => montantFort(n(f['partAssurance']))),
                  ColonneTableau(
                      cle: 'partPatient',
                      libelle: 'Part patient',
                      droite: true,
                      texte: (f) => m(f['partPatient'])),
                  ColonneTableau(
                      cle: 'statutPaiement',
                      libelle: 'Règlement patient',
                      texte: (f) =>
                          '${statutsMetier['${f['statutPaiement']}']?.$1 ?? f['statutPaiement'] ?? ''}',
                      rendu: (_, f) => statutBadge(f['statutPaiement'])),
                ],
                actionsLigne: (ctx, f) => [
                  // « Modifier » est une commande d'ÉCRITURE : absente sans le droit ; jamais d'archivage depuis cet écran.
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.pencil,
                        libelle: 'Modifier',
                        onPressed: () => ouvrirFormulaireFiche(ctx,
                            collection: c.magasin.collection('factures'),
                            champs: champs,
                            entite: 'facture',
                            record: f,
                            identifiant: (x) => '${x['numero'] ?? ''}',
                            versFiche: (s) => {
                                  'assureur': s['assureur'],
                                  'tauxPriseEnCharge': nb(s['tauxPriseEnCharge']),
                                  'partAssurance': nb(s['partAssurance']),
                                  'partPatient': nb(s['partPatient']),
                                  'observations': s['observations'] ?? '',
                                },
                            detailMessage: false)),
                ],
              ),
            ]);
      },
    );
  }
}
