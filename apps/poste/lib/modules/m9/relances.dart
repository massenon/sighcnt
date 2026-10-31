import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/pv_crud.dart';
import 'commun.dart';

String? _montantMin(Object? v, Map<String, Object?> _) =>
    (num.tryParse('${v ?? ''}'.trim()) ?? 0) >= 1 ? null : 'Valeur minimale : 1';

/// Les champs partagés par la création et la correction d'une relance.
List<ChampDef> champsRelance(List<Fiche> assureurs,
        {bool avecSuite = false, Map<String, String> creances = const {}}) =>
    [
      ChampDef(
          nom: 'assureur',
          libelle: 'Compagnie',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            for (final a in assureurs)
              OptionChamp(
                  '${a['code']}',
                  creances.isEmpty
                      ? '${a['nom']}'
                      : '${a['nom']} — créance : ${creances['${a['code']}']}')
          ]),
      const ChampDef(
          nom: 'date',
          libelle: 'Date de la relance',
          type: TypeChamp.date,
          requis: true),
      const ChampDef(
          nom: 'periode',
          libelle: 'Période concernée',
          requis: true,
          indicatif: 'ex. juin – juillet 2026'),
      ChampDef(
          nom: 'montant',
          libelle: 'Montant réclamé (FCFA)',
          type: TypeChamp.nombre,
          requis: true,
          valider: _montantMin),
      ChampDef(
          nom: 'niveau',
          libelle: 'Niveau de relance',
          type: TypeChamp.select,
          requis: true,
          options: [for (final x in assNiveauxRelance) OptionChamp(x)]),
      ChampDef(
          nom: 'canal',
          libelle: 'Canal de transmission',
          type: TypeChamp.select,
          requis: true,
          options: [for (final x in assCanauxRelance) OptionChamp(x)]),
      if (avecSuite)
        ChampDef(
            nom: 'statutRelance',
            libelle: 'Suite donnée',
            type: TypeChamp.select,
            requis: true,
            options: [for (final x in assSuitesRelance) OptionChamp(x.$1, x.$2)]),
      const ChampDef(
          nom: 'observations',
          libelle: 'Observations',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
    ];

/// `m9-relances` — « Relances » : le suivi des relances adressées aux compagnies pour les créances en souffrance. La lettre (relance ou mise en
/// demeure) s'imprime depuis le registre ; une relance se corrige (montant réévalué, niveau qui monte, suite donnée) et s'archive, jamais ne se supprime.
class EcranRelances extends StatelessWidget with EcranMaquette {
  const EcranRelances({super.key});

  @override
  String get titre => 'Relances';

  @override
  String get description =>
      'Suivi des relances adressées aux compagnies pour les créances en souffrance.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('relances');
    return ListenableBuilder(
      listenable: ecoute(c, ['relances', 'assureurs', 'factures']),
      builder: (context, _) {
        final rows = col.actives;
        final assureurs = actives(c, 'assureurs');
        final fa = assFacturesAssurance(actives(c, 'factures'));
        final enAttente =
            rows.where((r) => r['statutRelance'] == 'en_attente').length;
        final reg = rows.where((r) => r['statutRelance'] == 'regularisee').length;

        void lettre(BuildContext ctx, Fiche r) {
          final a = assureurs.where((x) => x['code'] == r['assureur']).firstOrNull ??
              const <String, Object?>{};
          afficherApercu(
              ctx,
              pieceM9(c,
                  titre: r['niveau'] == 'Mise en demeure'
                      ? 'Mise en demeure de payer'
                      : 'Lettre de relance',
                  sousTitre: '${r['reference']} — ${r['assureurNom']}',
                  cartouche: [
                    ('Destinataire', '${r['assureurNom']}'),
                    ('Courriel', '${a['email'] ?? '—'}'),
                    ('Référence', '${r['reference']}'),
                    ('Date', dateDe(r['date'])),
                    ('Période concernée', '${r['periode']}'),
                    ('Montant réclamé', money(r['montant'])),
                  ],
                  blocs: [
                    for (final p in assLettreRelance(r))
                      BlocTexte(p, italique: p == '${r['observations']}')
                  ],
                  signatures: const [
                    Signature('La Directrice Administrative',
                        nom: 'TAKI Alimatou', mention: 'Signature et cachet')
                  ]));
        }

        void ouvrir(BuildContext ctx) {
          final creances = {
            for (final a in assureurs)
              '${a['code']}': money(assCreance(fa, '${a['code']}'))
          };
          final premier = assureurs.isEmpty ? '' : '${assureurs.first['code']}';
          final ctl = ControleurFormulaire(
              champsRelance(assureurs, creances: creances), {
            'assureur': premier,
            'date': iso(c.aujourdhui),
            'montant': '${assCreance(fa, premier).round()}',
          });
          // Le montant proposé est la créance de la compagnie choisie.
          var dernier = premier;
          ctl.addListener(() {
            final a = '${ctl['assureur']}';
            if (a != dernier) {
              dernier = a;
              ctl.poser('montant', '${assCreance(fa, a).round()}');
            }
          });
          afficherModale<void>(ctx,
              titre: 'Nouvelle relance',
              sousTitre: 'Les champs marqués d’un astérisque sont obligatoires.',
              taille: TailleModale.lg,
              corps: FormulaireSigh(controleur: ctl),
              pied: (fermer) => [
                    BoutonSigh(
                        libelle: 'Annuler',
                        variante: VarianteBouton.secondaire,
                        onPressed: fermer),
                    BoutonSigh(
                        libelle: 'Enregistrer et éditer',
                        icone: LucideIcons.send,
                        onPressed: () {
                          final v = ctl.valider();
                          if (v == null) {
                            ToastsSigh.afficher(
                                ctx, 'Le formulaire comporte des erreurs.',
                                type: TypeToast.erreur);
                            return;
                          }
                          final ref = assReferenceRelance(col.toutes);
                          final r = col.inserer({
                            'statut': 'actif',
                            'assureur': v['assureur'],
                            'date': v['date'],
                            'periode': v['periode'],
                            'montant': num.tryParse('${v['montant']}'.trim()) ?? 0,
                            'niveau': v['niveau'],
                            'canal': v['canal'],
                            'observations': v['observations'] ?? '',
                            'assureurNom':
                                assNomAssureur('${v['assureur']}', assureurs),
                            'reference': ref,
                            'statutRelance': 'en_attente',
                          }, prefixe: 'REL');
                          fermer();
                          ToastsSigh.afficher(ctx, 'Relance $ref enregistrée.',
                              type: TypeToast.succes, annuler: r.annuler);
                          lettre(ctx, r.fiche);
                        }),
                  ]);
        }

        Fiche versFiche(Map<String, Object?> s) => {
              'assureur': s['assureur'],
              'assureurNom': assNomAssureur('${s['assureur']}', assureurs),
              'date': s['date'],
              'periode': s['periode'],
              'montant': num.tryParse('${s['montant']}'.trim()) ?? 0,
              'niveau': s['niveau'],
              'canal': s['canal'],
              'statutRelance': s['statutRelance'],
              'observations': s['observations'] ?? '',
            };

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Relances émises',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.send),
                KpiSigh(
                    libelle: 'En attente de réponse',
                    valeur: nombre(enAttente),
                    icone: LucideIcons.clock,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Régularisées',
                    valeur: nombre(reg),
                    icone: LucideIcons.checkCircle2,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Montant relancé',
                    valeur: money(assSomme(rows, 'montant')),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.info),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Registre des relances',
                lignes: rows,
                taillePage: 12,
                nomExport: 'relances',
                triInitial: 'date',
                sensInitial: 'desc',
                messageVide: 'Aucune relance enregistrée.',
                indiceVide:
                    'Établir une relance pour une compagnie dont la créance est en souffrance.',
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouvelle relance',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => ouvrir(context)),
                ],
                filtres: [
                  FiltreTableau(nom: 'assureur', libelle: 'Compagnie', options: [
                    for (final a in assureurs)
                      OptionChamp('${a['code']}', '${a['nom']}')
                  ]),
                  FiltreTableau(nom: 'niveau', libelle: 'Niveau', options: [
                    for (final x in assNiveauxRelance) OptionChamp(x)
                  ]),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N°',
                      sansCoupure: true,
                      texte: (r) => '${r['reference'] ?? ''}',
                      rendu: (_, r) => monoTexte(r['reference'])),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      valeur: (r) => r['date'],
                      texte: (r) => dateDe(r['date'])),
                  const ColonneTableau(cle: 'assureurNom', libelle: 'Compagnie'),
                  const ColonneTableau(
                      cle: 'periode', libelle: 'Période concernée'),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant réclamé',
                      droite: true,
                      texte: (r) => m(r['montant']),
                      rendu: (_, r) => Text(m(r['montant']),
                          style: const TextStyle(
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w600))),
                  ColonneTableau(
                      cle: 'niveau',
                      libelle: 'Niveau',
                      texte: (r) => '${r['niveau'] ?? ''}',
                      rendu: (_, r) => BadgeSigh('${r['niveau'] ?? ''}',
                          ton: switch ('${r['niveau']}') {
                            '1re relance' => TonSigh.info,
                            '2e relance' => TonSigh.attention,
                            'Mise en demeure' => TonSigh.danger,
                            _ => TonSigh.neutre
                          })),
                  const ColonneTableau(cle: 'canal', libelle: 'Canal'),
                  ColonneTableau(
                      cle: 'statutRelance',
                      libelle: 'Suite',
                      texte: (r) => assSuitesRelance
                          .where((x) => x.$1 == r['statutRelance'])
                          .map((x) => x.$2)
                          .firstOrNull ?? '—',
                      rendu: (_, r) {
                        const mp = {
                          'en_attente': ('En attente', TonSigh.attention),
                          'regularisee': ('Régularisée', TonSigh.succes),
                          'contestee': ('Contestée', TonSigh.danger)
                        };
                        final x = mp['${r['statutRelance']}'] ?? ('—', TonSigh.neutre);
                        return BadgeSigh(x.$1, ton: x.$2);
                      }),
                ],
                actionsLigne: (ctx, r) => [
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer la lettre',
                      onPressed: () => lettre(ctx, r)),
                  // Une relance se corrige : montant réévalué, niveau qui monte, suite donnée par la compagnie.
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.pencil,
                        libelle: 'Modifier la relance',
                        onPressed: () => ouvrirFormulaireFiche(ctx,
                            collection: col,
                            champs: champsRelance(assureurs, avecSuite: true),
                            entite: 'relance',
                            record: r,
                            identifiant: (x) => '${x['reference'] ?? ''}',
                            versFiche: versFiche,
                            detailMessage: false)),
                  if (c.droit.annuler)
                    BoutonIcone(
                        icone: LucideIcons.archive,
                        libelle: 'Archiver',
                        onPressed: () {
                          final annuler = col.archiver(r['id']);
                          ToastsSigh.afficher(ctx, 'Relance archivée.',
                              type: TypeToast.succes, annuler: annuler);
                        }),
                ],
              ),
            ]);
      },
    );
  }
}
