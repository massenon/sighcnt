import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m8/commun.dart' show ecrireAvoirEmis, idAvoirSuivant;
import 'commun.dart';

// =====================================================================================================================
// mecef-dashboard
// =====================================================================================================================

/// `mecef-dashboard` — « Tableau de bord fiscal — MECeF » : supervision de l'émission et de la transmission des factures normalisées. SIMULATION :
/// les échanges avec le dispositif fiscal sont ceux de la maquette ; le boîtier physique attend le protocole de la Direction.
class EcranMecefTableauDeBord extends StatelessWidget with EcranMaquette {
  const EcranMecefTableauDeBord({super.key});

  @override
  String get titre => 'Tableau de bord fiscal — MECeF';

  @override
  String get description =>
      'Supervision de l’émission et de la transmission des factures normalisées à l’administration fiscale.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('factures');
    final p = paramFiscal(c.magasin);
    final auj = c.aujourdhui;
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final nn = normalisees(c.magasin);
        int nb(String s) => nn.where((f) => f['statutMecef'] == s).length;
        final validees = nn.where((f) => f['statutMecef'] == 'valide').toList();
        final jour = iso(auj);
        final emisAujourdhui =
            nn.where((f) => '${f['date']}'.startsWith(jour)).length;
        final tva = validees.fold<num>(
            0, (a, f) => a + tvaRegistre(n(f['montantTTC']), p));
        final aib = validees.fold<num>(
            0, (a, f) => a + decomposer(n(f['montantTTC']), p).aib);
        final parNature = <String, int>{};
        for (final f in nn) {
          parNature['${f['type']}'] = (parNature['${f['type']}'] ?? 0) + 1;
        }
        final serie = parMois(nn, 'date', ref: auj);
        final declare = parMois(validees, 'date', champValeur: 'montantTTC', ref: auj);
        final tvaMois = [
          for (final v in declare.valeurs) arrondiJs(v * p.tauxTva / (100 + p.tauxTva))
        ];

        Widget deux(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
              final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                SizedBox(width: l, child: a),
                SizedBox(width: l, child: b)
              ]);
            });

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (nb('rejete') > 0 || nb('en_attente') > 0) ...[
                LayoutBuilder(builder: (_, k) {
                  final l = k.maxWidth >= 640 ? (k.maxWidth - 8) / 2 : k.maxWidth;
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    if (nb('rejete') > 0)
                      SizedBox(
                          width: l,
                          child: NoteSigh(
                              '${nb('rejete')} facture(s) rejetée(s) par le dispositif fiscal — correction et réémission requises.',
                              ton: TonSigh.danger,
                              icone: LucideIcons.fileX)),
                    if (nb('en_attente') > 0)
                      SizedBox(
                          width: l,
                          child: NoteSigh(
                              '${nb('en_attente')} facture(s) en attente de transmission.',
                              ton: TonSigh.attention,
                              icone: LucideIcons.clock)),
                  ]);
                }),
                const SizedBox(height: 16),
              ],
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Factures émises aujourd’hui',
                    valeur: nombre(emisAujourdhui),
                    icone: LucideIcons.filePlus),
                KpiSigh(
                    libelle: 'Factures validées',
                    valeur: nombre(validees.length),
                    icone: LucideIcons.fileCheck2,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'En attente de transmission',
                    valeur: nombre(nb('en_attente')),
                    icone: LucideIcons.clock,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Factures rejetées',
                    valeur: nombre(nb('rejete')),
                    icone: LucideIcons.fileX,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Montant total déclaré',
                    valeur: money(validees.fold<num>(0, (a, f) => a + n(f['montantTTC']))),
                    icone: LucideIcons.trendingUp,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: p.tauxTva != 0 ? 'TVA collectée' : 'AIB collecté',
                    valeur: money(p.tauxTva != 0 ? tva : aib),
                    icone: LucideIcons.landmark,
                    indice: p.tauxTva != 0
                        ? 'Taux ${p.tauxTva} %'
                        : 'AIB ${p.tauxAib} % — TVA exonérée'),
                KpiSigh(
                    libelle: 'Taux de validation',
                    valeur: pourcent(nn.isEmpty ? 0 : validees.length / nn.length * 100),
                    icone: LucideIcons.percent,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Dernière synchronisation',
                    valeur: 'Aujourd’hui',
                    icone: LucideIcons.refreshCw,
                    ton: TonSigh.neutre,
                    indice: heure(auj)),
              ]),
              const SizedBox(height: 16),
              deux(
                CarteSigh(
                    titre: 'Évolution des factures normalisées (12 mois)',
                    child: GraphiqueLigne(etiquettes: serie.etiquettes, series: [
                      SerieGraphique('Factures émises', serie.valeurs,
                          couleur: JetonsShell.navy900),
                    ])),
                CarteSigh(
                    titre: 'Statut des transmissions',
                    child: GraphiqueAnneau(
                        etiquettes: const ['Validées', 'En attente', 'Rejetées'],
                        valeurs: [nb('valide'), nb('en_attente'), nb('rejete')],
                        couleurs: const [
                          JetonsShell.success500,
                          JetonsShell.warning500,
                          JetonsShell.danger500
                        ])),
              ),
              const SizedBox(height: 16),
              deux(
                CarteSigh(
                    titre: 'Recettes déclarées et TVA (12 mois)',
                    child: GraphiqueBarres(etiquettes: declare.etiquettes, series: [
                      SerieGraphique('Montant déclaré', declare.valeurs,
                          couleur: JetonsShell.navy900),
                      SerieGraphique('TVA collectée', tvaMois,
                          couleur: JetonsShell.warning500),
                    ])),
                CarteSigh(
                    titre: 'Répartition par nature de facture',
                    child: GraphiqueAnneau(
                        etiquettes: parNature.keys.toList(),
                        valeurs: parNature.values.toList())),
              ),
              const SizedBox(height: 16),
              SectionSigh(
                titre: 'Accès rapides',
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: RaccourcisSigh(aller: c.aller, items: const [
                    RaccourciDef(
                        id: 'mecef-factures',
                        icone: LucideIcons.fileBadge,
                        libelle: 'Factures normalisées',
                        detail: 'Registre fiscal'),
                    RaccourciDef(
                        id: 'mecef-transmission',
                        icone: LucideIcons.send,
                        libelle: 'Transmission',
                        detail: 'File d’envoi et réponses'),
                    RaccourciDef(
                        id: 'mecef-avoirs',
                        icone: LucideIcons.undo2,
                        libelle: 'Avoirs & annulations',
                        detail: 'Rectifications'),
                    RaccourciDef(
                        id: 'mecef-config',
                        icone: LucideIcons.settings,
                        libelle: 'Configuration fiscale',
                        detail: 'IFU, RCCM, numérotation'),
                  ]),
                ),
              ),
            ]);
      },
    );
  }
}

// =====================================================================================================================
// mecef-factures
// =====================================================================================================================

/// `mecef-factures` — « Factures normalisées » : écran CALCULÉ. Une facture se corrige par un avoir, jamais par retouche.
class EcranMecefFactures extends StatelessWidget with EcranMaquette {
  const EcranMecefFactures({super.key});

  @override
  String get titre => 'Factures normalisées';

  @override
  String get description =>
      'Registre fiscal des factures normalisées, avec identifiant MECeF, montant déclaré et TVA collectée.';

  @override
  String get regle =>
      'Écran calculé : le registre reflète les factures émises et leur état de transmission. Une facture se corrige par un avoir, jamais par retouche — une pièce normalisée transmise à la DGI est définitive.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final p = paramFiscal(c.magasin);
    return ListenableBuilder(
      listenable: c.magasin.collection('factures'),
      builder: (context, _) {
        final rows = normalisees(c.magasin);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Factures normalisées',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.fileBadge),
                KpiSigh(
                    libelle: 'Montant déclaré',
                    valeur: money(rows.fold<num>(0, (a, f) => a + n(f['montantTTC']))),
                    icone: LucideIcons.trendingUp,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'TVA collectée',
                    valeur: money(rows.fold<num>(
                        0, (a, f) => a + tvaRegistre(n(f['montantTTC']), p))),
                    icone: LucideIcons.landmark,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Validées par l’administration',
                    valeur: nombre(
                        rows.where((f) => f['statutMecef'] == 'valide').length),
                    icone: LucideIcons.fileCheck2,
                    ton: TonSigh.succes),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Registre des factures normalisées',
                taillePage: 15,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'factures-normalisees',
                lignes: rows,
                filtres: const [
                  FiltreTableau(nom: 'statutMecef', libelle: 'Statut fiscal', options: [
                    OptionChamp('valide', 'Validée'),
                    OptionChamp('en_attente', 'En attente'),
                    OptionChamp('rejete', 'Rejetée'),
                  ]),
                  FiltreTableau(nom: 'type', libelle: 'Nature', options: [
                    OptionChamp('Consultation'),
                    OptionChamp('Hospitalisation'),
                    OptionChamp('Laboratoire'),
                    OptionChamp('Pharmacie'),
                    OptionChamp('Soins à domicile'),
                  ]),
                ],
                colonnes: [
                  colFacture(),
                  colDate(),
                  ColonneTableau(
                      cle: 'patient',
                      libelle: 'Client',
                      texte: (f) => '${f['patient'] ?? ''}',
                      rendu: (_, f) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${f['patient'] ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: JetonsShell.slate800, fontSize: 14)),
                                Text('${f['patientCode'] ?? ''}',
                                    style: const TextStyle(
                                        fontFamily: 'LiberationMono',
                                        color: JetonsShell.slate400,
                                        fontSize: 12)),
                              ])),
                  ColonneTableau(
                      cle: 'type',
                      libelle: 'Nature',
                      texte: (f) => '${f['type'] ?? ''}',
                      rendu: (_, f) => BadgeSigh('${f['type'] ?? ''}', ton: TonSigh.navy)),
                  ColonneTableau(
                      cle: 'montantHT',
                      libelle: 'Montant HT',
                      droite: true,
                      valeur: (f) => htRegistre(n(f['montantTTC']), p),
                      texte: (f) => m(htRegistre(n(f['montantTTC']), p))),
                  colTva(p),
                  colMontantTtc(),
                  colStatut(),
                ],
                alClicLigne: (f) => _consulter(context, f, p),
                actionsLigne: (ctx, f) => [
                  BoutonIcone(
                      icone: LucideIcons.eye,
                      libelle: 'Consulter',
                      onPressed: () => _consulter(ctx, f, p)),
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer la facture normalisée',
                      onPressed: () => imprimerFactureNormalisee(ctx, f)),
                ],
              ),
            ]);
      },
    );
  }

  void _consulter(BuildContext ctx, Fiche f, ParamFiscal p) {
    final ttc = n(f['montantTTC']);
    final ht = htRegistre(ttc, p);
    final tva = ttc - ht;
    afficherTiroir<void>(ctx,
        titre: '${f['numero']}',
        sousTitre: '${f['numeroMecef'] ?? 'Non transmise'} — ${dateDe(f['date'])}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(colonnes: 2, kpis: [
            KpiSigh(
                libelle: 'Montant TTC',
                valeur: money(ttc),
                icone: LucideIcons.receipt),
            KpiSigh(
                libelle: 'TVA collectée',
                valeur: money(tva),
                icone: LucideIcons.landmark,
                ton: TonSigh.attention),
          ]),
          const SizedBox(height: 16),
          DescListeSigh([
            ('N° facture', '${f['numero']}'),
            (
              'Identifiant MECeF',
              f['numeroMecef'] != null
                  ? '${f['numeroMecef']}'
                  : const BadgeSigh('Non attribué', ton: TonSigh.attention)
            ),
            ('Date d’émission', dateDe(f['date'])),
            ('Client', f['patient']),
            ('Dossier', f['patientCode']),
            ('Nature', f['type']),
            ('Montant HT', money(ht)),
            ('TVA (${p.tauxTva} %)', money(tva)),
            ('Montant TTC', money(ttc)),
            ('Statut de transmission', badgeStatut(f['statutMecef'])),
            ('IFU émetteur', IdentiteClinique.ifu),
            ('RCCM', IdentiteClinique.rccm),
          ]),
          if (f['statutMecef'] == 'rejete') ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Facture rejetée par le dispositif fiscal. Une correction puis une réémission sont nécessaires avant archivage définitif.',
                ton: TonSigh.danger,
                icone: LucideIcons.fileX),
          ],
        ]),
        pied: (_) => [
              BoutonSigh(
                  libelle: 'Imprimer',
                  icone: LucideIcons.printer,
                  onPressed: () => imprimerFactureNormalisee(ctx, f))
            ]);
  }
}

// =====================================================================================================================
// mecef-transmission
// =====================================================================================================================

/// `mecef-transmission` — « Transmission & réponses » : le journal de transmission est une PREUVE ; un rejet se traite en corrigeant puis en retransmettant.
class EcranMecefTransmission extends StatefulWidget with EcranMaquette {
  const EcranMecefTransmission({super.key});

  @override
  String get titre => 'Transmission & réponses';

  @override
  String get description =>
      'File d’envoi vers le dispositif fiscal, suivi des réponses, codes de retour et nouvelles tentatives.';

  @override
  String get regle =>
      'Écran calculé : le journal de transmission est une preuve. Il s’alimente des envois effectués et ne se modifie pas ; un rejet se traite en corrigeant la facture puis en retransmettant.';

  @override
  State<EcranMecefTransmission> createState() => _EtatTransmission();
}

class _EtatTransmission extends State<EcranMecefTransmission> {
  List<Fiche> _par(Magasin mag, String s) =>
      normalisees(mag).where((f) => f['statutMecef'] == s).toList();

  /// Transmet UN LOT : une réponse du dispositif par facture, tirée d'une graine (simulation). Annulable d'un geste.
  Future<void> _synchroniser(ContexteEcran c) async {
    final mag = c.magasin;
    final att = _par(mag, 'en_attente');
    if (att.isEmpty) {
      ToastsSigh.afficher(context, 'Aucune facture en attente de transmission.');
      return;
    }
    final ok = await confirmerSigh(context,
        titre: 'Transmettre ${att.length} facture(s) ?',
        message:
            'Les factures en attente seront transmises au dispositif fiscal. Un identifiant MECeF sera attribué à chaque facture acceptée.',
        libelleOk: 'Transmettre');
    if (!ok || !mounted) return;
    final reponses = synchroniser(att.length, iso(c.aujourdhui));
    final col = mag.collection('factures');
    final annulations = <VoidCallback>[];
    var acceptees = 0, refusees = 0;
    for (var i = 0; i < att.length; i++) {
      reponses[i].statutMecef == 'valide' ? acceptees++ : refusees++;
      annulations.add(col.mettreAJour(att[i]['id'], reponses[i].patch));
    }
    setState(() {});
    ToastsSigh.afficher(context,
        'Synchronisation terminée : $acceptees acceptée(s), $refusees rejetée(s).',
        type: refusees > 0 ? TypeToast.attention : TypeToast.succes,
        annuler: () {
      for (final u in annulations.reversed) {
        u();
      }
      setState(() {});
    });
  }

  void _transmettre(ContexteEcran c, Fiche f, {required bool reemission}) {
    final r = transmettreUne(
        c.aujourdhui.millisecondsSinceEpoch % (reemission ? 88888 : 99999),
        iso(c.aujourdhui));
    final undo = c.magasin.collection('factures').mettreAJour(f['id'], {
      ...r.patch,
      if (reemission) 'reemise': true,
    });
    setState(() {});
    ToastsSigh.afficher(
        context,
        reemission
            ? 'Facture corrigée et réémise avec succès.'
            : 'Facture transmise et validée.',
        type: TypeToast.succes,
        detail: reemission ? null : r.numeroMecef,
        annuler: () {
          undo();
          setState(() {});
        });
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final mag = c.magasin;
    final p = paramFiscal(mag);
    final att = _par(mag, 'en_attente'),
        rej = _par(mag, 'rejete'),
        val = _par(mag, 'valide');
    final total = normalisees(mag).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'En attente d’envoi',
            valeur: nombre(att.length),
            icone: LucideIcons.clock,
            ton: TonSigh.attention),
        KpiSigh(
            libelle: 'Transmissions réussies',
            valeur: nombre(val.length),
            icone: LucideIcons.circleCheck,
            ton: TonSigh.succes),
        KpiSigh(
            libelle: 'Rejets à corriger',
            valeur: nombre(rej.length),
            icone: LucideIcons.fileX,
            ton: TonSigh.danger),
        KpiSigh(
            libelle: 'Taux de réussite',
            valeur: pourcent(total == 0 ? 0 : val.length / total * 100),
            icone: LucideIcons.percent,
            ton: TonSigh.info),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Synchroniser maintenant',
              icone: LucideIcons.refreshCw,
              onPressed: () => _synchroniser(c)),
        lienVers('Journal des transactions', () => c.aller('mecef-journal')),
      ]),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'attente',
            libelle: 'En attente',
            compte: att.length,
            construire: (ctx) => TableauSigh(
                  lignes: att,
                  taillePage: 12,
                  triInitial: 'date',
                  sensInitial: 'desc',
                  nomExport: 'mecef-en-attente',
                  messageVide: 'Aucune facture en attente de transmission.',
                  colonnes: [
                    colFacture(),
                    colDate(),
                    const ColonneTableau(cle: 'patient', libelle: 'Client'),
                    colMontantTtc(),
                    colTva(p),
                    colStatut(),
                  ],
                  actionsLigne: (_, f) => [
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Transmettre',
                          icone: LucideIcons.send,
                          taille: TailleBouton.sm,
                          onPressed: () => _transmettre(c, f, reemission: false))
                  ],
                )),
        OngletDef(
            id: 'rejets',
            libelle: 'Rejets',
            compte: rej.length,
            construire: (ctx) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (rej.isNotEmpty) ...[
                        const NoteSigh(
                            'Chaque rejet doit être corrigé puis réémis. Le code de retour du dispositif fiscal précise la nature de l’anomalie.',
                            ton: TonSigh.danger,
                            icone: LucideIcons.fileX),
                        const SizedBox(height: 12),
                      ],
                      TableauSigh(
                        lignes: rej,
                        taillePage: 12,
                        triInitial: 'date',
                        sensInitial: 'desc',
                        nomExport: 'mecef-rejets',
                        messageVide: 'Aucun rejet à traiter.',
                        colonnes: [
                          colFacture(),
                          colDate(),
                          const ColonneTableau(cle: 'patient', libelle: 'Client'),
                          colMontantTtc(),
                          ColonneTableau(
                              cle: 'codeRetour',
                              libelle: 'Code de retour',
                              texte: (f) => '${f['codeRetour'] ?? 'E-000'}',
                              rendu: (_, f) {
                                final code = codesRejet
                                    .where((x) => x.$1 == f['codeRetour'])
                                    .firstOrNull;
                                return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${f['codeRetour'] ?? 'E-000'}',
                                          style: const TextStyle(
                                              fontFamily: 'LiberationMono',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: JetonsShell.danger700)),
                                      Text(code?.$2 ?? 'Anomalie non qualifiée',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: JetonsShell.slate500)),
                                    ]);
                              }),
                        ],
                        actionsLigne: (_, f) => [
                          if (c.droit.editer)
                            BoutonSigh(
                                libelle: 'Corriger et réémettre',
                                icone: LucideIcons.repeat,
                                taille: TailleBouton.sm,
                                variante: VarianteBouton.secondaire,
                                onPressed: () =>
                                    _transmettre(c, f, reemission: true))
                        ],
                      ),
                    ])),
        OngletDef(
            id: 'validees',
            libelle: 'Transmissions réussies',
            compte: val.length,
            construire: (ctx) => TableauSigh(
                  lignes: val,
                  taillePage: 12,
                  triInitial: 'date',
                  sensInitial: 'desc',
                  nomExport: 'mecef-validees',
                  colonnes: [
                    colFacture(),
                    colDate(),
                    const ColonneTableau(cle: 'patient', libelle: 'Client'),
                    colMontantTtc(),
                    colTva(p),
                    ColonneTableau(
                        cle: 'codeRetour',
                        libelle: 'Réponse',
                        texte: (f) => '${f['codeRetour'] ?? 'OK-200'}',
                        rendu: (_, f) => BadgeSigh('${f['codeRetour'] ?? 'OK-200'}',
                            ton: TonSigh.succes)),
                  ],
                )),
      ]),
    ]);
  }
}

// =====================================================================================================================
// mecef-avoirs
// =====================================================================================================================

/// `mecef-avoirs` — « Avoirs & annulations » : une facture normalisée transmise ne se supprime pas, sa rectification passe par un avoir. Troisième canal d'avoir de
/// la maquette (écart E12/E15) : transmis et validé d'office, sans contrôle du cumul.
class EcranMecefAvoirs extends StatelessWidget with EcranMaquette {
  const EcranMecefAvoirs({super.key});

  @override
  String get titre => 'Avoirs & annulations';

  @override
  String get description =>
      'Émission des avoirs rectificatifs et suivi des factures annulées auprès de l’administration fiscale.';

  @override
  String get regle =>
      'Une facture normalisée transmise ne peut être supprimée : sa rectification passe obligatoirement par l’émission d’un avoir.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('avoirs');
    final p = paramFiscal(c.magasin);
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final annulees = c.magasin
            .collection('factures')
            .actives
            .where((f) => f['annulee'] == true)
            .length;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Avoirs émis',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.undo2),
                KpiSigh(
                    libelle: 'Montant des avoirs',
                    valeur: money(rows.fold<num>(0, (a, r) => a + n(r['montant']))),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'TVA régularisée',
                    valeur: money(rows.fold<num>(
                        0, (a, r) => a + tvaRegistre(n(r['montant']), p))),
                    icone: LucideIcons.landmark,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Factures annulées',
                    valeur: nombre(annulees),
                    icone: LucideIcons.fileX,
                    ton: TonSigh.danger),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Registre des avoirs',
                taillePage: 12,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'avoirs-mecef',
                messageVide: 'Aucun avoir émis.',
                indiceVide: 'Un avoir rectifie une facture normalisée déjà transmise.',
                lignes: rows,
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N° avoir',
                      sansCoupure: true,
                      texte: (a) => '${a['reference']}',
                      rendu: (_, a) => Text('${a['reference']}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              fontWeight: FontWeight.w600))),
                  ColonneTableau(
                      cle: 'numeroMecef',
                      libelle: 'Identifiant MECeF',
                      sansCoupure: true,
                      texte: (a) => '${a['numeroMecef'] ?? '—'}',
                      rendu: (_, a) => Text('${a['numeroMecef'] ?? '—'}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              color: JetonsShell.slate500))),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (a) => dateDe(a['date'])),
                  ColonneTableau(
                      cle: 'factureNumero',
                      libelle: 'Facture rectifiée',
                      sansCoupure: true,
                      texte: (a) => '${a['factureNumero'] ?? ''}',
                      rendu: (_, a) => Text('${a['factureNumero'] ?? ''}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono', fontSize: 12))),
                  const ColonneTableau(cle: 'patient', libelle: 'Client'),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant',
                      droite: true,
                      texte: (a) => m(a['montant']),
                      rendu: (_, a) => Text('− ${m(a['montant'])}',
                          style: const TextStyle(
                              color: JetonsShell.danger600,
                              fontSize: 14,
                              fontWeight: FontWeight.w600))),
                  const ColonneTableau(cle: 'motif', libelle: 'Motif'),
                  ColonneTableau(
                      cle: 'statutMecef',
                      libelle: 'Statut',
                      texte: (a) => statutsMecef['${a['statutMecef']}']?.$1 ?? '—',
                      rendu: (_, a) => badgeStatut(a['statutMecef'])),
                ],
                actionsLigne: (ctx, a) => [
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer l’avoir',
                      onPressed: () => _imprimer(ctx, a, p)),
                ],
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Émettre un avoir',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => _ouvrir(context, c)),
                ],
              ),
            ]);
      },
    );
  }

  void _imprimer(BuildContext ctx, Fiche a, ParamFiscal p) {
    final c = ContexteEcran.of(ctx);
    final ttc = n(a['montant']);
    final ht = htRegistre(ttc, p);
    final tva = ttc - ht;
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Avoir sur facture normalisée',
          sousTitre: '${a['reference']} — rectifie la facture ${a['factureNumero']}',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('N° avoir', '${a['reference']}'),
            ('Identifiant MECeF', '${a['numeroMecef'] ?? '—'}'),
            ('Date', dateDe(a['date'])),
            ('Facture rectifiée', '${a['factureNumero']}'),
            ('Client', '${a['patient'] ?? ''}'),
            ('Motif', '${a['motif'] ?? ''}'),
          ],
          blocs: [
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
              ColonneEtat(libelle: 'Montant', valeur: (r) => r['v'], droite: true),
            ], lignes: [
              {'k': 'Montant hors taxes de l’avoir', 'v': '− ${m(ht)}'},
              {'k': 'TVA (${p.tauxTva} %)', 'v': '− ${m(tva)}'},
              {'k': 'TOTAL DE L’AVOIR (TTC)', 'v': '− ${m(ttc)}'},
            ])),
            BlocTexte(
                'Motif de la rectification : ${a['motif']}${'${a['observations'] ?? ''}'.isNotEmpty ? ' — ${a['observations']}' : ''}'),
            BlocTexte(
                'Le présent avoir rectifie la facture normalisée ${a['factureNumero']} et a été transmis au dispositif de facturation électronique. Il vaut régularisation de la TVA correspondante.',
                italique: true),
          ],
          signatures: const [
            Signature('Le Comptable', nom: 'KASSA Augustin'),
            Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
          ],
        ));
  }

  void _ouvrir(BuildContext ctx, ContexteEcran c) {
    final mag = c.magasin;
    final valides = trierPar(
            normalisees(mag).where((f) => f['statutMecef'] == 'valide').toList(),
            (f) => f['date'],
            descendant: true)
        .take(200)
        .toList();
    if (valides.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucune facture validée à rectifier.',
          type: TypeToast.attention);
      return;
    }
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'factureId',
          libelle: 'Facture à rectifier',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          recherche: true,
          options: [
            for (final x in valides)
              OptionChamp('${x['id']}',
                  '${x['numero']} — ${x['patient']} — ${money(x['montantTTC'])}')
          ]),
      const ChampDef(
          nom: 'date',
          libelle: 'Date de l’avoir',
          type: TypeChamp.date,
          requis: true),
      const ChampDef(
          nom: 'montant',
          libelle: 'Montant de l’avoir (FCFA)',
          type: TypeChamp.nombre,
          requis: true),
      ChampDef(
          nom: 'motif',
          libelle: 'Motif de la rectification',
          type: TypeChamp.select,
          requis: true,
          options: [for (final x in motifsAvoirMecef) OptionChamp(x)]),
      const ChampDef(
          nom: 'observations',
          libelle: 'Observations',
          type: TypeChamp.textarea,
          col: ColChamp.plein,
          lignes: 2),
    ], {
      'date': iso(c.aujourdhui)
    });
    afficherModale<void>(ctx,
        titre: 'Émettre un avoir',
        sousTitre: 'Rectification d’une facture normalisée transmise',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Émettre l’avoir',
                  icone: LucideIcons.undo2,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) {
                      ToastsSigh.afficher(
                          ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final fac = valides
                        .where((x) => '${x['id']}' == '${v['factureId']}')
                        .firstOrNull;
                    // B10 : l'avoir MECeF APPELLE le moteur unique (plafond cumulé, montant > 0, ligne nommée, contre-passation) ;
                    // la transmission (simulation) en est la SUITE : le moteur écrit la pièce, ce geste lui pose l'identifiant MECeF.
                    final AvoirMecefEmis a;
                    final idAvoir = idAvoirSuivant(mag);
                    try {
                      a = avoirMecef(
                          facture: fac,
                          saisie: v,
                          avoirs: mag.collection('avoirs').actives,
                          facturesMere: mag.collection('facturesMere').actives,
                          idAvoir: idAvoir,
                          jour: iso(c.aujourdhui),
                          utilisateur: c.utilisateur);
                    } on RefusAvoirMecef catch (e) {
                      ToastsSigh.afficher(ctx, 'Avoir refusé.',
                          type: TypeToast.erreur,
                          detail: e.motif,
                          duree: const Duration(seconds: 9));
                      return;
                    }
                    final complement = <String, Object?>{
                      'numeroMecef': numeroMecefSimule(
                          c.aujourdhui.millisecondsSinceEpoch % 77777),
                      'statutMecef': 'valide',
                      'dateTransmission': c.aujourdhui.toUtc().toIso8601String(),
                    };
                    final ecrit =
                        ecrireAvoirEmis(mag, fac!, a.emission, idAvoir, complement: complement);
                    fermer();
                    ToastsSigh.afficher(ctx,
                        'Avoir ${a.fiche['reference']} émis et transmis.',
                        type: TypeToast.succes, annuler: () {
                      for (final u in ecrit.annulations.reversed) {
                        u();
                      }
                    });
                    _imprimer(ctx, ecrit.fiche, paramFiscal(mag));
                  }),
            ]);
  }
}

// =====================================================================================================================
// mecef-journal
// =====================================================================================================================

/// `mecef-journal` — « Journal des transactions fiscales » : lecture seule et IMMUABLE ; une facture erronée se corrige par un avoir.
class EcranMecefJournal extends StatelessWidget with EcranMaquette {
  const EcranMecefJournal({super.key});

  @override
  String get titre => 'Journal des transactions fiscales';

  @override
  String get description =>
      'Historique horodaté des transmissions, réponses du dispositif et codes de retour.';

  @override
  String get regle =>
      'Écran en lecture seule. Le journal des transactions fiscales est immuable : chaque ligne est certifiée par la machine électronique. Une facture erronée se corrige par un avoir, jamais par modification.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: c.magasin.collection('factures'),
      builder: (context, _) {
        final rows = trierPar([
          for (final f in normalisees(c.magasin))
            <String, Object?>{
              'id': f['id'],
              'date': f['dateTransmission'] ?? f['date'],
              'facture': f['numero'],
              'numeroMecef': f['numeroMecef'],
              'patient': f['patient'],
              'montant': f['montantTTC'],
              'operation': f['reemise'] == true ? 'Réémission' : 'Transmission',
              'code': f['codeRetour'] ??
                  (f['statutMecef'] == 'valide'
                      ? 'OK-200'
                      : (f['statutMecef'] == 'rejete' ? 'E-000' : '—')),
              'statut': f['statutMecef'],
            }
        ], (r) => r['date'], descendant: true);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Transactions enregistrées',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.scrollText),
                KpiSigh(
                    libelle: 'Réussies',
                    valeur: nombre(rows.where((r) => r['statut'] == 'valide').length),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Échouées',
                    valeur: nombre(rows.where((r) => r['statut'] == 'rejete').length),
                    icone: LucideIcons.circleX,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Réémissions',
                    valeur: nombre(rows.where((r) => r['operation'] == 'Réémission').length),
                    icone: LucideIcons.repeat,
                    ton: TonSigh.attention),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Journal fiscal',
                taillePage: 20,
                nomExport: 'journal-mecef',
                lignes: rows,
                filtres: const [
                  FiltreTableau(nom: 'statut', libelle: 'Statut', options: [
                    OptionChamp('valide', 'Réussie'),
                    OptionChamp('rejete', 'Échouée'),
                    OptionChamp('en_attente', 'En attente'),
                  ]),
                  FiltreTableau(nom: 'operation', libelle: 'Opération', options: [
                    OptionChamp('Transmission'),
                    OptionChamp('Réémission'),
                  ]),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Horodatage',
                      sansCoupure: true,
                      texte: (r) => dateDe(r['date'])),
                  ColonneTableau(
                      cle: 'facture',
                      libelle: 'Facture',
                      sansCoupure: true,
                      texte: (r) => '${r['facture']}',
                      rendu: (_, r) => Text('${r['facture']}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono', fontSize: 12))),
                  ColonneTableau(
                      cle: 'numeroMecef',
                      libelle: 'Identifiant MECeF',
                      sansCoupure: true,
                      texte: (r) => '${r['numeroMecef'] ?? '—'}',
                      rendu: (_, r) => Text('${r['numeroMecef'] ?? '—'}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              color: JetonsShell.slate500))),
                  const ColonneTableau(cle: 'patient', libelle: 'Client'),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant',
                      droite: true,
                      texte: (r) => m(r['montant'])),
                  ColonneTableau(
                      cle: 'operation',
                      libelle: 'Opération',
                      texte: (r) => '${r['operation']}',
                      rendu: (_, r) => BadgeSigh('${r['operation']}',
                          ton: r['operation'] == 'Réémission'
                              ? TonSigh.attention
                              : TonSigh.navy)),
                  ColonneTableau(
                      cle: 'code',
                      libelle: 'Code de retour',
                      texte: (r) => '${r['code']}',
                      rendu: (_, r) => Text('${r['code']}',
                          style: TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: r['statut'] == 'valide'
                                  ? JetonsShell.success700
                                  : (r['statut'] == 'rejete'
                                      ? JetonsShell.danger700
                                      : JetonsShell.slate500)))),
                  ColonneTableau(
                      cle: 'statut',
                      libelle: 'Statut',
                      texte: (r) => statutsMecef['${r['statut']}']?.$1 ?? '—',
                      rendu: (_, r) => badgeStatut(r['statut'])),
                ],
              ),
            ]);
      },
    );
  }
}

// =====================================================================================================================
// mecef-config
// =====================================================================================================================

/// `mecef-config` — « Configuration fiscale » : identifiants légaux, numérotation, régime de TVA, transmission. SIMULATION : l'enregistrement est
/// journalisé mais n'est pas relu par les écrans (écart E13) — les taux restent ceux du référentiel.
class EcranMecefConfig extends StatefulWidget with EcranMaquette {
  const EcranMecefConfig({super.key});

  @override
  String get titre => 'Configuration fiscale';

  @override
  String get description =>
      'Paramètres d’émission : identifiants légaux, numérotation, taux de TVA et préfixes.';

  @override
  String get regle =>
      'Ces paramètres alimentent automatiquement toutes les factures normalisées : ils ne doivent jamais être saisis facture par facture.';

  @override
  State<EcranMecefConfig> createState() => _EtatConfig();
}

class _EtatConfig extends State<EcranMecefConfig> {
  ControleurFormulaire? _f;
  bool _pret = false;

  @override
  void dispose() {
    _f?.dispose();
    super.dispose();
  }

  Widget _controle(String libelle) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          const Icon(LucideIcons.circleCheck, size: 16, color: JetonsShell.success600),
          const SizedBox(width: 8),
          Expanded(
              child: Text(libelle,
                  style: const TextStyle(color: JetonsShell.slate700, fontSize: 14))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final mag = c.magasin;
    final p = paramFiscal(mag);
    if (!_pret) {
      _pret = true;
      _f = ControleurFormulaire([
        const ChampDef.section('Identification légale de l’émetteur'),
        const ChampDef(
            nom: 'raisonSociale',
            libelle: 'Raison sociale',
            requis: true,
            col: ColChamp.plein),
        const ChampDef(nom: 'ifu', libelle: 'IFU', requis: true),
        const ChampDef(nom: 'rccm', libelle: 'RCCM', requis: true),
        const ChampDef(
            nom: 'autorisation',
            libelle: 'N° d’autorisation d’ouverture',
            col: ColChamp.plein),
        const ChampDef(nom: 'adresse', libelle: 'Adresse', col: ColChamp.plein),
        const ChampDef(nom: 'telephone', libelle: 'Téléphones'),
        const ChampDef(nom: 'email', libelle: 'Adresse électronique'),
        const ChampDef.section('Paramètres d’émission'),
        const ChampDef(
            nom: 'prefixeFacture',
            libelle: 'Préfixe des factures',
            aide: 'La numérotation doit rester strictement séquentielle.'),
        const ChampDef(nom: 'prefixeAvoir', libelle: 'Préfixe des avoirs'),
        const ChampDef(nom: 'prefixeProforma', libelle: 'Préfixe des pro-forma'),
        const ChampDef(
            nom: 'prochainNumero',
            libelle: 'Prochain numéro',
            type: TypeChamp.nombre),
        ChampDef(
            nom: 'regimeTva',
            libelle: 'Régime de TVA',
            type: TypeChamp.select,
            requis: true,
            aide:
                'Le régime exonéré est celui relevé sur la facture de référence : à confirmer avec le service comptable.',
            options: [for (final r in p.regimes) OptionChamp(r.id, r.libelle)]),
        const ChampDef(
            nom: 'tauxAib',
            libelle: 'Taux d’AIB (%)',
            type: TypeChamp.nombre,
            aide: 'Acompte sur impôt assis sur les bénéfices, prélevé à la source.'),
        const ChampDef(nom: 'devise', libelle: 'Devise'),
        const ChampDef.section('Transmission'),
        const ChampDef(
            nom: 'modeTransmission',
            libelle: 'Mode de transmission',
            type: TypeChamp.select,
            options: [
              OptionChamp('Automatique à l’émission'),
              OptionChamp('Manuelle groupée'),
              OptionChamp('Différée en fin de journée'),
            ]),
        const ChampDef(
            nom: 'delaiRetransmission',
            libelle: 'Délai avant nouvelle tentative (minutes)',
            type: TypeChamp.nombre),
        const ChampDef(
            nom: 'archivageAuto',
            libelle: 'Archivage automatique des factures transmises',
            type: TypeChamp.case_,
            col: ColChamp.plein),
      ], {
        'raisonSociale': IdentiteClinique.nom,
        'ifu': IdentiteClinique.ifu,
        'rccm': IdentiteClinique.rccm,
        'autorisation': IdentiteClinique.autorisation,
        'adresse': IdentiteClinique.bp,
        'telephone': IdentiteClinique.telephones.join(' / '),
        'email': IdentiteClinique.email,
        'prefixeFacture': 'FN-2026-',
        'prefixeAvoir': 'AV-2026-',
        'prefixeProforma': 'PRO-2026-',
        'prochainNumero': '${normalisees(mag).length + 1}',
        'regimeTva': p.regimeTva,
        'tauxAib': '${p.tauxAib}',
        'devise': 'FCFA',
        'modeTransmission': 'Automatique à l’émission',
        'delaiRetransmission': '15',
        'archivageAuto': true,
      });
    }
    return LayoutBuilder(builder: (context, k) {
      final gauche = CarteSigh(
        titre: 'Paramètres fiscaux',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: _f!),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            // La configuration fiscale commande TOUTES les factures normalisées à venir : elle ne se règle pas depuis un profil qui ne fait que consulter.
            if (c.droit.editer)
              BoutonSigh(
                  libelle: 'Enregistrer les paramètres',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = _f!.valider();
                    if (v == null) {
                      ToastsSigh.afficher(
                          context, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    mag.journaliser('Modification', 'MECEF',
                        'ConfigurationFiscale', 'CONFIG', null, v);
                    ToastsSigh.afficher(context, 'Paramètres fiscaux enregistrés.',
                        type: TypeToast.succes,
                        detail:
                            'Ces valeurs alimenteront toutes les prochaines factures normalisées.');
                  }),
            BoutonSigh(
                libelle: 'Tester la connexion au dispositif',
                icone: LucideIcons.plugZap,
                variante: VarianteBouton.secondaire,
                onPressed: () => ToastsSigh.afficher(
                    context, 'Connexion au dispositif fiscal établie.',
                    type: TypeToast.succes, detail: 'Temps de réponse : 340 ms')),
          ]),
        ]),
      );
      final droite = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CarteSigh(
                titre: 'Mentions portées sur chaque facture',
                child: DescListeSigh([
                  ('Dénomination', IdentiteClinique.nom),
                  ('Adresse', IdentiteClinique.bp),
                  ('Téléphones', IdentiteClinique.telephones.join(' / ')),
                  ('Adresse électronique', IdentiteClinique.email),
                  ('IFU', IdentiteClinique.ifu),
                  ('RCCM', IdentiteClinique.rccm),
                  ('Autorisation d’ouverture', IdentiteClinique.autorisation),
                  ('Devise', 'FCFA'),
                  ('Régime de TVA', p.regime.libelle),
                  ('Taux de TVA appliqué', '${p.tauxTva} %'),
                  ('Acompte AIB', '${p.tauxAib} % du montant hors taxes'),
                ])),
            const SizedBox(height: 16),
            const NoteSigh(
                'Le régime exonéré est celui relevé sur la facture de référence certifiée MECeF, où la TVA est portée à zéro et le net à payer vaut le hors-taxes augmenté du seul AIB. Ce choix doit être confirmé par le service comptable pour les prestations de la clinique.',
                ton: TonSigh.attention,
                icone: LucideIcons.circleHelp),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Contrôles automatiques à l’émission',
                child: Column(children: [
                  _controle('Numérotation strictement séquentielle'),
                  _controle('IFU émetteur renseigné'),
                  _controle('RCCM renseigné'),
                  _controle('Montant de TVA cohérent avec le montant HT'),
                  _controle('Identification du client renseignée'),
                  _controle('QR code fiscal apposé sur le document'),
                ])),
            const SizedBox(height: 16),
            const NoteSigh(
                'Le prototype simule les échanges avec le dispositif fiscal. L’interfaçage réel s’effectuera avec la machine électronique certifiée de facturation lors de la mise en œuvre.'),
          ]);
      if (k.maxWidth < 1024) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          gauche,
          const SizedBox(height: 16),
          droite,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: gauche),
        const SizedBox(width: 16),
        Expanded(child: droite),
      ]);
    });
  }
}
