import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';
import 'factures.dart';
import 'impression.dart';

/// `m8-reliquats` — suivi des règlements différés. Le patient qui ne peut pas payer prend un ENGAGEMENT écrit ; faute de règlement, il bascule en
/// CLIENT INSOLVABLE : la créance reste due et tracée, elle n'est jamais effacée (RG-14).
class EcranReliquats extends StatelessWidget with EcranMaquette {
  const EcranReliquats({super.key});

  @override
  String get description =>
      'Suivi des règlements différés et des écarts à régulariser, y compris par Mobile Money.';

  @override
  String get regle =>
      'Le reliquat est enregistré à l’ouverture puis régularisé au règlement différé. Le patient qui ne peut pas payer prend un engagement écrit chez le comptable, avec une date ou un échéancier. Faute de règlement, il bascule en client insolvable : la créance reste due et tracée, elle n’est jamais effacée.';

  static int _jours(Fiche f, DateTime auj) {
    final d = DateTime.tryParse('${f['date']}');
    return d == null
        ? 0
        : DateTime(auj.year, auj.month, auj.day)
            .difference(DateTime(d.year, d.month, d.day))
            .inDays;
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('factures');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = [
          for (final f in col.actives)
            if (n(f['reliquat']) > 0) f
        ];
        final total = rows.fold<num>(0, (a, r) => a + n(r['reliquat']));
        final patients = {for (final r in rows) r['patientId']}.length;
        const tranches = [
          ('Moins de 30 jours', 0, 30),
          ('30 à 60 jours', 30, 60),
          ('60 à 90 jours', 60, 90),
          ('Plus de 90 jours', 90, 99999)
        ];
        final parNature = <String, num>{};
        for (final r in rows) {
          parNature['${r['type']}'] =
              (parNature['${r['type']}'] ?? 0) + n(r['reliquat']);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Factures avec reliquat',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Montant total des reliquats',
                    valeur: money(total),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Reliquat moyen',
                    valeur: money(rows.isEmpty ? 0 : total / rows.length),
                    icone: LucideIcons.calculator,
                    ton: TonSigh.neutre),
                KpiSigh(
                    libelle: 'Patients concernés',
                    valeur: nombre(patients),
                    icone: LucideIcons.users,
                    ton: TonSigh.info),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Reliquats en cours',
                colonnes: [
                  colNumero,
                  colDate,
                  colPatient,
                  ColonneTableau(cle: 'type', libelle: 'Nature'),
                  colMontant,
                  ColonneTableau(
                      cle: 'montantPaye',
                      libelle: 'Réglé',
                      droite: true,
                      texte: (f) => m(f['montantPaye'])),
                  colReliquat,
                  ColonneTableau(
                    cle: 'anciennete',
                    libelle: 'Ancienneté',
                    droite: true,
                    valeur: (f) => _jours(f, c.aujourdhui),
                    rendu: (_, f) {
                      final j = _jours(f, c.aujourdhui);
                      return Text('$j j',
                          style: TextStyle(
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight:
                                  j > 60 ? FontWeight.w600 : FontWeight.w400,
                              color: j > 60
                                  ? JetonsShell.danger600
                                  : (j > 30
                                      ? JetonsShell.warning600
                                      : JetonsShell.slate600),
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]));
                    },
                  ),
                ],
                lignes: rows,
                taillePage: 15,
                triInitial: 'reliquat',
                sensInitial: 'desc',
                nomExport: 'reliquats',
                messageVide:
                    'Aucun reliquat en cours : toutes les factures sont soldées.',
                filtres: [
                  FiltreTableau(nom: 'type', libelle: 'Nature', options: [
                    for (final x in const [
                      'Consultation',
                      'Hospitalisation',
                      'Laboratoire',
                      'Pharmacie',
                      'Soins à domicile'
                    ])
                      OptionChamp(x)
                  ])
                ],
                alClicLigne: (f) => afficherTiroir<void>(context,
                    titre: '${f['numero']}',
                    sousTitre: '${f['patient'] ?? ''}',
                    corps: detailFacture(f)),
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Encaisser un reliquat',
                        icone: LucideIcons.banknote,
                        taille: TailleBouton.sm,
                        onPressed: () => c.aller('m8-paiements')),
                ],
                actionsLigne: (ctx, f) => [
                  // Un engagement ENGAGE le patient et « insolvable » change le statut de la créance : ce sont des écritures.
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.handshake,
                        libelle: 'Engagement de paiement',
                        onPressed: () => _engagement(ctx, col, f)),
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.userRoundX,
                        libelle: 'Déclarer insolvable',
                        onPressed: () => _insolvable(ctx, col, f)),
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer la facture',
                      onPressed: () => imprimerFacture(ctx, f)),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, k) {
                final deux = k.maxWidth >= 1024;
                final l = deux ? (k.maxWidth - 16) / 2 : k.maxWidth;
                return Wrap(spacing: 16, runSpacing: 16, children: [
                  SizedBox(
                      width: l,
                      child: CarteSigh(
                          titre: 'Reliquats par ancienneté',
                          child: GraphiqueBarres(
                              horizontal: true,
                              hauteur: 240,
                              etiquettes: [
                                for (final t in tranches) t.$1
                              ],
                              series: [
                                SerieGraphique(
                                    'Montant',
                                    [
                                      for (final t in tranches)
                                        rows.where((f) {
                                          final j = _jours(f, c.aujourdhui);
                                          return j >= t.$2 && j < t.$3;
                                        }).fold<num>(
                                            0, (a, r) => a + n(r['reliquat']))
                                    ],
                                    couleur: JetonsShell.warning500)
                              ]))),
                  SizedBox(
                      width: l,
                      child: CarteSigh(
                          titre: 'Reliquats par nature de prestation',
                          child: GraphiqueAnneau(
                              etiquettes: parNature.keys.toList(),
                              valeurs: parNature.values.toList()))),
                ]);
              }),
            ]);
      },
    );
  }

  /// Engagement de paiement : écrit et signé, vaut reconnaissance de dette ; la créance reste inscrite jusqu'à son règlement effectif.
  void _engagement(BuildContext ctx, CollectionMagasin col, Fiche f) {
    final c = ContexteEcran.of(ctx);
    final dans30 = c.aujourdhui.add(const Duration(days: 30));
    final form = ControleurFormulaire(const [
      ChampDef(
          nom: 'modalite',
          libelle: 'Modalité',
          type: TypeChamp.select,
          requis: true,
          options: [
            OptionChamp('unique', 'Règlement en une seule tranche'),
            OptionChamp('echeancier', 'Échéancier en plusieurs tranches')
          ]),
      ChampDef(
          nom: 'dateEngagement',
          libelle: 'Date de règlement promise',
          type: TypeChamp.date,
          requis: true),
      ChampDef(
          nom: 'tranches',
          libelle: 'Nombre de tranches',
          type: TypeChamp.nombre),
      ChampDef(nom: 'recuPar', libelle: 'Engagement reçu par', requis: true),
      ChampDef(
          nom: 'observation',
          libelle: 'Observation',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
    ], {
      'dateEngagement': iso(dans30),
      'tranches': '1',
      'recuPar': c.utilisateur
    });
    afficherModale<void>(ctx,
        titre: 'Engagement de paiement',
        sousTitre: '${f['patient']} — ${money(f['reliquat'])} dus',
        taille: TailleModale.lg,
        corps: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DescListeSigh([
                ('Facture', f['numero']),
                ('Patient', f['patient']),
                ('Montant dû', money(f['reliquat'])),
                ('Ancienneté', '${_jours(f, c.aujourdhui)} jours')
              ]),
              const SizedBox(height: 12),
              FormulaireSigh(controleur: form),
              const SizedBox(height: 12),
              const NoteSigh(
                  'L’engagement est écrit et signé : il vaut reconnaissance de dette. La créance reste inscrite jusqu’à son règlement effectif.'),
            ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer et éditer',
                  icone: LucideIcons.handshake,
                  onPressed: () {
                    final v = form.valider();
                    if (v == null) return;
                    final echeancier = v['modalite'] == 'echeancier';
                    final annuler = col.mettreAJour(f['id'], {
                      'engagement': {
                        'date': v['dateEngagement'],
                        'modalite': v['modalite'],
                        'tranches': echeancier
                            ? (n(v['tranches']).toInt()).clamp(1, 12)
                            : 1,
                        'recuPar': v['recuPar'],
                        'observation': v['observation'],
                        'prisLe': iso(c.aujourdhui),
                        'montant': f['reliquat'],
                      },
                      'insolvable': false,
                    });
                    fermer();
                    ToastsSigh.afficher(ctx,
                        'Engagement enregistré pour le ${dateDe(v['dateEngagement'])}.',
                        type: TypeToast.succes, annuler: annuler);
                    imprimerEngagement(ctx, col.parId(f['id'])!);
                  }),
            ]);
  }

  /// Faute de règlement, la créance bascule en client insolvable : elle reste due et tracée (RG-14), le motif est obligatoire et journalisé.
  Future<void> _insolvable(
      BuildContext ctx, CollectionMagasin col, Fiche f) async {
    final c = ContexteEcran.of(ctx);
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Déclarer ${f['patient']} insolvable ?',
        message:
            'La créance de ${money(f['reliquat'])} reste inscrite et due : la déclaration ne l’efface pas. Elle signale que le recouvrement amiable a échoué et que le dossier passe au traitement contentieux. L’opération est journalisée (RG-12).',
        libelleOk: 'Déclarer insolvable',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = col.mettreAJour(f['id'], {
      'insolvable': true,
      'motifInsolvabilite': motif,
      'declareLe': iso(c.aujourdhui),
      'declarePar': c.utilisateur
    });
    ToastsSigh.afficher(ctx, '${f['patient']} déclaré(e) client insolvable.',
        type: TypeToast.attention,
        detail: 'La créance de ${money(f['reliquat'])} reste due.',
        annuler: annuler);
  }
}
