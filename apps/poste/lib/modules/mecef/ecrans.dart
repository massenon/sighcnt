import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../sync/configuration_sync.dart' show ApplicateurConfiguration;
import '../../donnees/mecef_caisse_poste.dart';
import '../../donnees/mecef_poste.dart';
import '../m14/commun_m14.dart' show libelleRole;
import '../../donnees/normalisation_mecef.dart';
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
                    libelle: 'Factures refusées',
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
                    libelle: 'Normalisées',
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
                filtres: [
                  FiltreTableau(
                      nom: 'statutMecef',
                      libelle: 'Statut fiscal',
                      options: optionsStatutMecef),
                  const FiltreTableau(nom: 'type', libelle: 'Nature', options: [
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
            NoteSigh(
                'Facture refusée${f['codeRetour'] != null ? ' (${f['codeRetour']})' : ''}${f['motifRefusMecef'] != null ? ' : ${f['motifRefusMecef']}' : ''}. Une correction puis une retransmission sont nécessaires avant archivage définitif.',
                ton: TonSigh.danger,
                icone: LucideIcons.fileX),
          ],
          if (f['statutMecef'] == 'a_verifier') ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Réponse perdue : la vente a peut-être été émise. « Reprendre sans doubler » lit l’appareil et ne rejoue jamais l’émission.',
                ton: TonSigh.attention,
                icone: LucideIcons.circleHelp),
          ],
          if (f['statutMecef'] == 'expiree') ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Facture expirée avant confirmation : la vente se renormalise.',
                ton: TonSigh.danger,
                icone: LucideIcons.clock),
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

  /// « Synchroniser maintenant » : tant qu'aucun adaptateur n'est configuré (lot L3), refuse en nommant et n'écrit rien (aucun numéro fabriqué).
  Future<void> _synchroniser(ContexteEcran c) async {
    final mag = c.magasin;
    final att = _par(mag, 'en_attente');
    if (att.isEmpty) {
      ToastsSigh.afficher(context, 'Aucune facture en attente de transmission.');
      return;
    }
    // Lot L3 : sans adaptateur configuré, AUCUN tirage et aucun numéro fabriqué ; les ventes restent en attente de certification. L'envoi d'un lot par un
    // adaptateur configuré (boîtier ou e-MECeF) est asynchrone et reste à écrire (lot M3).
    final ad = adaptateurDuPoste(mag, c.aujourdhui);
    final refus = ad.refus;
    if (refus != null) {
      ToastsSigh.afficher(context, '${refus.code} : ${refus.motif}',
          type: TypeToast.attention,
          detail: refus.geste,
          duree: const Duration(seconds: 9));
    }
  }

  /// « Normaliser » et « Corriger et retransmettre » : la NORMALISATION de la vente (E2299). Refus nommés du domaine (déjà normalisée, droit de
  /// retransmettre, acheteur, montants) ; aucun appareil n'est branché (lot L3) : la vente reste en attente de certification, sans numéro, et le refus
  /// `MECEF_NON_CONFIGURE` se dit.
  void _normaliser(ContexteEcran c, Fiche f, {required bool reemission}) {
    final mag = c.magasin;
    final refus = refusRetransmission(f, c.role);
    if (refus != null) {
      ToastsSigh.afficher(context, '${refus.code} : ${refus.motif}',
          type: TypeToast.erreur,
          detail: refus.geste,
          duree: const Duration(seconds: 9));
      return;
    }
    final col = mag.collection('factures');
    final annulations = <VoidCallback>[];
    if (f['statutMecef'] != 'en_attente') {
      annulations.add(col.mettreAJour(
          f['id'], {'retransmissions': (n(f['retransmissions']).toInt()) + 1}));
    }
    final r = normaliserVente(mag, '${f['id']}', maintenant: c.aujourdhui);
    if (!r.ok) {
      for (final u in annulations.reversed) {
        u();
      }
      // Un refus des montants a écrit la pièce « refusée » : la retransmission compte, le refus se dit.
      ToastsSigh.afficher(context, '${r.code} : ${r.motif}',
          type: TypeToast.erreur,
          detail: r.geste,
          duree: const Duration(seconds: 9));
      setState(() {});
      return;
    }
    annulations.add(r.annuler);
    if (reemission) annulations.add(col.mettreAJour(f['id'], {'reemise': true}));
    setState(() {});
    ToastsSigh.afficher(
        context,
        reemission ? 'Facture retransmise et normalisée.' : 'Facture normalisée.',
        type: TypeToast.succes,
        detail: r.numero,
        annuler: () {
          for (final u in annulations.reversed) {
            u();
          }
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
        ver = [..._par(mag, 'a_verifier'), ..._par(mag, 'expiree')],
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
            libelle: 'À vérifier',
            valeur: nombre(_par(mag, 'a_verifier').length),
            icone: LucideIcons.circleHelp,
            ton: TonSigh.attention),
        KpiSigh(
            libelle: 'Transmissions réussies',
            valeur: nombre(val.length),
            icone: LucideIcons.circleCheck,
            ton: TonSigh.succes),
        KpiSigh(
            libelle: 'Refusées à corriger',
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
                          libelle: 'Normaliser',
                          icone: LucideIcons.send,
                          taille: TailleBouton.sm,
                          onPressed: () => _normaliser(c, f, reemission: false))
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
                        nomExport: 'mecef-refusees',
                        messageVide: 'Aucune facture refusée à traiter.',
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
                                libelle: 'Corriger et retransmettre',
                                icone: LucideIcons.repeat,
                                taille: TailleBouton.sm,
                                variante: VarianteBouton.secondaire,
                                onPressed: () =>
                                    _normaliser(c, f, reemission: true))
                        ],
                      ),
                    ])),
        OngletDef(
            id: 'averifier',
            libelle: 'À vérifier',
            compte: ver.length,
            construire: (ctx) => TableauSigh(
                  lignes: ver,
                  taillePage: 12,
                  triInitial: 'date',
                  sensInitial: 'desc',
                  nomExport: 'mecef-a-verifier',
                  messageVide: 'Aucune vente à vérifier ni expirée.',
                  colonnes: [
                    colFacture(),
                    colDate(),
                    const ColonneTableau(cle: 'patient', libelle: 'Client'),
                    colMontantTtc(),
                    colStatut(),
                    ColonneTableau(
                        cle: 'codeRetour',
                        libelle: 'Motif',
                        texte: (f) =>
                            '${f['codeRetour'] ?? ''}${f['motifRefusMecef'] != null ? ' : ${f['motifRefusMecef']}' : ''}',
                        rendu: (_, f) => Text(
                            '${f['codeRetour'] ?? ''}${f['motifRefusMecef'] != null ? ' : ${f['motifRefusMecef']}' : ''}',
                            style: const TextStyle(
                                fontSize: 12, color: JetonsShell.slate600))),
                  ],
                  // Une vente EXPIRÉE se renormalise ; une vente À VÉRIFIER se reprend sans doubler : la reprise lit l'appareil, et ce poste n'a
                  // aucun appareil branché (journal des émissions de la maquette non porté). La commande est ABSENTE, pas grisée.
                  actionsLigne: (_, f) => [
                    if (c.droit.editer && f['statutMecef'] == 'expiree')
                      BoutonSigh(
                          libelle: 'Renormaliser',
                          icone: LucideIcons.repeat,
                          taille: TailleBouton.sm,
                          variante: VarianteBouton.secondaire,
                          onPressed: () => _normaliser(c, f, reemission: false))
                  ],
                )),
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
          utilisateur: acteur(c).nom,
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
                          utilisateur: acteur(c).nom);
                    } on RefusAvoirMecef catch (e) {
                      ToastsSigh.afficher(ctx, 'Avoir refusé.',
                          type: TypeToast.erreur,
                          detail: e.motif,
                          duree: const Duration(seconds: 9));
                      return;
                    }
                    // Lot L3 : sans adaptateur configuré, l'avoir est ÉMIS (la pièce existe, la contre-passation est écrite) mais n'a AUCUN numéro fiscal.
                    final ad = adaptateurDuPoste(mag, c.aujourdhui);
                    final refus = ad.refus;
                    final ecrit = ecrireAvoirEmis(mag, fac!, a.emission, idAvoir);
                    fermer();
                    if (refus == null) {
                      ToastsSigh.afficher(ctx,
                          'Avoir ${a.fiche['reference']} émis.',
                          type: TypeToast.succes, annuler: () {
                        for (final u in ecrit.annulations.reversed) {
                          u();
                        }
                      });
                    } else {
                      ToastsSigh.afficher(ctx,
                          'Avoir ${a.fiche['reference']} émis, en attente de certification.',
                          type: TypeToast.attention,
                          detail: '${refus.code} : ${refus.motif} ${refus.geste}',
                          duree: const Duration(seconds: 9),
                          annuler: () {
                        for (final u in ecrit.annulations.reversed) {
                          u();
                        }
                      });
                    }
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
                filtres: [
                  FiltreTableau(
                      nom: 'statut',
                      libelle: 'Statut',
                      options: optionsStatutMecef),
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

  /// Les rôles qui détiennent un geste réservé, nommés (liste DÉRIVÉE de la fiche RBAC, jamais recopiée).
  String _detenteurs(ContexteEcran c, String geste) {
    final ids = c.donnees?.matrice.matriceGestes.rolesAvec(geste) ?? const <String>[];
    return ids.isEmpty ? 'aucun rôle ne le détient' : ids.map((r) => libelleRole(c.magasin, r)).join(', ');
  }

  /// LE MODE DE CERTIFICATION (lot L3, décision de la Direction du 09/11/2026 ; lot MECEF-M) : boîtier physique (défaut) ou e-MECeF, paramètre `mecef.mode` du registre du
  /// lot L0 (en base, versionné par date, synchronisé par le journal). Réglé par le GESTE réservé `regler_mode_mecef` de la fiche RBAC (plus de liste de rôles), sur la
  /// mère ; un fileul le reçoit. Le moteur refuse aussi. Aucun adaptateur n'est branché : e-MECeF est « non configuré, dossier d'interface DGI requis » et le boîtier
  /// est « en attente des réponses du fournisseur » (lot M3).
  Widget _carteMode(ContexteEcran c) {
    final mag = c.magasin;
    final fileul = ServiceInstallation.de(mag).rattache;
    final peut = c.donnees?.matrice.droitGeste(c.role, mecefGesteMode) ?? false;
    return ListenableBuilder(
        listenable: mag.collection(parCollectionParametres),
        builder: (ctx, _) {
          final actuel = modeMecefDuPoste(mag, c.aujourdhui);
          return CarteSigh(
              titre: 'Mode de certification',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Mode en vigueur : '),
                  TextSpan(text: mecefLibellesModes[actuel] ?? actuel, style: const TextStyle(fontWeight: FontWeight.w600)),
                ])),
                const SizedBox(height: 12),
                if (actuel == 'emecef')
                  const NoteSigh(
                      'e-MECeF : non configuré, dossier d’interface DGI requis. Aucun document remis ne décrit le protocole (adresse, authentification, format des messages) : rien n’est supposé. Une vente est encaissée, reste en attente de certification et ne reçoit aucun numéro ; elle se retransmet quand l’interface sera branchée.',
                      ton: TonSigh.attention,
                      icone: LucideIcons.plugZap)
                else
                  const NoteSigh(
                      'Boîtier physique : en attente des réponses du fournisseur. Le modèle, l’interface et le protocole du boîtier ne figurent dans aucun document remis (dix questions au fournisseur et à la DGI restent à poser). Aucun numéro n’est fabriqué comme s’il était fiscal : tant que l’adaptateur du boîtier n’est pas branché, une vente reste en attente de certification.'),
                const SizedBox(height: 12),
                if (fileul)
                  const NoteSigh(ApplicateurConfiguration.motifGarde, icone: LucideIcons.lock)
                else if (!peut)
                  NoteSigh('Le mode se règle par un rôle qui détient le droit « Régler le mode de facturation normalisée » : ${_detenteurs(c, mecefGesteMode)}.', icone: LucideIcons.lock)
                else
                  Align(
                      alignment: Alignment.centerLeft,
                      child: BoutonSigh(libelle: 'Régler le mode', icone: LucideIcons.settings, onPressed: () => _ouvrirMode(ctx, c, actuel))),
              ]));
        });
  }

  void _ouvrirMode(BuildContext ctx, ContexteEcran c, String actuel) {
    final mag = c.magasin;
    final form = ControleurFormulaire([
      ChampDef(
          nom: 'mode',
          libelle: 'Mode de certification des factures',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [for (final k in mecefModes) OptionChamp(k, mecefLibellesModes[k])]),
    ], {'mode': actuel});
    afficherModale<void>(ctx,
        titre: 'Mode de certification',
        sousTitre: 'Boîtier physique ou e-MECeF',
        corps: FormulaireSigh(controleur: form),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer le mode',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = form.valider();
                    if (v == null) return;
                    final refus = reglerModeMecefDuPoste(mag,
                        mode: v['mode'],
                        gesteAccorde: c.donnees?.matrice.droitGeste(c.role, mecefGesteMode) ?? false,
                        fileul: ServiceInstallation.de(mag).rattache,
                        libelleRole: libelleRole(mag, c.role),
                        rolesQuiLeDetiennent: _detenteurs(c, mecefGesteMode),
                        horloge: () => c.aujourdhui);
                    if (refus != null) {
                      ToastsSigh.afficher(ctx, '${refus.code} : ${refus.motif}', type: TypeToast.erreur, detail: refus.geste, duree: const Duration(seconds: 9));
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Mode enregistré : ${mecefLibellesModes[v['mode']] ?? v['mode']}.', type: TypeToast.succes);
                  }),
            ]);
  }

  /// L'ÉTAT DE LA CAISSE (lot MECEF-M) : ce qui est encaissé sans être normalisé, les avoirs en attente À PART ; un montant qui ne se calcule pas se DIT (jamais zéro).
  Widget _carteEtatCaisse(ContexteEcran c) {
    final mag = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([mag.collection('factures'), mag.collection('avoirs')]),
        builder: (ctx, _) {
          final e = etatCaissePoste(mag);
          String montant(num? v, int nb) => nb == 0 ? money(0) : (v == null ? 'Non calculable' : money(v));
          return CarteSigh(
              titre: 'État de la caisse',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DescListeSigh([
                  ('Ventes encaissées non normalisées', '${e.ventes}'),
                  ('Montant encaissé non normalisé', montant(e.ventesMontant, e.ventes)),
                  ('Avoirs en attente de certification (à part)', '${e.avoirs}'),
                  ('Montant des avoirs en attente', montant(e.avoirsMontant, e.avoirs)),
                ]),
                if ((e.ventes > 0 && e.ventesMontant == null) || (e.avoirs > 0 && e.avoirsMontant == null)) ...[
                  const SizedBox(height: 12),
                  const NoteSigh('Non calculable : au moins une pièce n’a pas de montant connu. Le total n’est pas zéro, il n’est pas affirmé.',
                      ton: TonSigh.attention, icone: LucideIcons.circleHelp),
                ],
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: BoutonSigh(libelle: 'Voir la file', icone: LucideIcons.list, variante: VarianteBouton.secondaire, onPressed: () => c.aller('mecef-transmission'))),
              ]));
        });
  }

  /// L'IMPRIMANTE DE CAISSE (lot MECEF-M) : réglage daté du registre (famille `mecef`), par le geste réservé `regler_imprimante_caisse` ; commande ABSENTE sans le droit,
  /// fileul en lecture seule ; le moteur refuse aussi (six refus nommés).
  Widget _carteImprimante(ContexteEcran c) {
    final mag = c.magasin;
    final fileul = ServiceInstallation.de(mag).rattache;
    final peut = c.donnees?.matrice.droitGeste(c.role, mecefGesteImprimante) ?? false;
    return ListenableBuilder(
        listenable: mag.collection(parCollectionParametres),
        builder: (ctx, _) {
          final v = imprimanteDuPoste(mag, c.aujourdhui);
          return CarteSigh(
              titre: 'Imprimante de caisse',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DescListeSigh([
                  ('Nom', v.nom),
                  ('Modèle', v.modele),
                  ('Type', 'Thermique, rouleau ${v.largeurMm} mm'),
                  ('Liaison', v.liaisonLibelle),
                  ('En vigueur', v.dateEffet == null ? 'réglage semé par défaut' : 'depuis le ${dateFR(DateTime.parse(v.dateEffet!))}'),
                ]),
                if (v.liaison == 'a_verifier') ...[
                  const SizedBox(height: 12),
                  const NoteSigh('La liaison réelle n’est pas connue : à vérifier à l’arrière de l’appareil (USB ou Ethernet), puis à régler ici.',
                      ton: TonSigh.attention, icone: LucideIcons.cable),
                ],
                const SizedBox(height: 12),
                const NoteSigh('Cette imprimante sort les tickets de caisse (rouleau 80 mm). Elle ne remplace pas le boîtier de certification.', icone: LucideIcons.printer),
                const SizedBox(height: 12),
                if (fileul)
                  const NoteSigh(ApplicateurConfiguration.motifGarde, icone: LucideIcons.lock)
                else if (!peut)
                  NoteSigh('L’imprimante se règle par un rôle qui détient le droit « Régler l’imprimante de caisse » : ${_detenteurs(c, mecefGesteImprimante)}.', icone: LucideIcons.lock)
                else
                  Align(alignment: Alignment.centerLeft, child: BoutonSigh(libelle: 'Régler l’imprimante', icone: LucideIcons.settings, onPressed: () => _ouvrirImprimante(ctx, c, v))),
              ]));
        });
  }

  void _ouvrirImprimante(BuildContext ctx, ContexteEcran c, ImprimanteALaDate v) {
    final mag = c.magasin;
    final form = ControleurFormulaire([
      const ChampDef(nom: 'nom', libelle: 'Nom', requis: true),
      ChampDef(
          nom: 'liaison',
          libelle: 'Liaison',
          type: TypeChamp.select,
          options: [for (final l in liaisonsImprimante) if (l.choisissable) OptionChamp(l.id, l.libelle)]),
      const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, col: ColChamp.plein, lignes: 2),
    ], {'nom': v.nom, 'liaison': v.liaison == 'usb' || v.liaison == 'ethernet' ? v.liaison : '', 'dateEffet': parametreDateIso(c.aujourdhui)});
    afficherModale<void>(ctx,
        titre: 'Imprimante de caisse',
        sousTitre: '${v.modele}, thermique 80 mm',
        corps: FormulaireSigh(controleur: form),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer l’imprimante',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final date = '${form['dateEffet'] ?? ''}';
                    final refus = reglerImprimanteDuPoste(mag,
                        gesteAccorde: c.donnees?.matrice.droitGeste(c.role, mecefGesteImprimante) ?? false,
                        fileul: ServiceInstallation.de(mag).rattache,
                        libelleRole: libelleRole(mag, c.role),
                        rolesQuiLeDetiennent: _detenteurs(c, mecefGesteImprimante),
                        nom: '${form['nom'] ?? ''}',
                        liaison: '${form['liaison'] ?? ''}',
                        dateEffet: date.length >= 10 ? date.substring(0, 10) : date,
                        motif: '${form['motif'] ?? ''}',
                        horloge: () => c.aujourdhui);
                    if (refus != null) {
                      ToastsSigh.afficher(ctx, '${refus.code} : ${refus.motif}', type: TypeToast.erreur, detail: refus.geste, duree: const Duration(seconds: 9));
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Imprimante enregistrée : ${form['nom']}, ${libelleLiaisonImprimante('${form['liaison']}')}.', type: TypeToast.succes);
                  }),
            ]);
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
      final carteConfig = CarteSigh(
        titre: 'Paramètres fiscaux',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Lecture seule. Ces valeurs sont celles des référentiels du logiciel : les modifier ici ne conserverait rien. L’identité légale se règle à « Identité & papier à en-tête ».'),
          const SizedBox(height: 12),
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
                    // Aucune collection n'est écrite (écart E13) : le toast ne promet donc pas d'effet sur les factures à venir.
                    ToastsSigh.afficher(context, 'Saisie journalisée, non appliquée.',
                        type: TypeToast.attention,
                        detail:
                            'Simulation (E13) : les paramètres fiscaux ne sont pas conservés et les factures normalisées continuent d’utiliser les valeurs de référence.');
                  }),
            BoutonSigh(
                libelle: 'Tester la connexion au dispositif',
                icone: LucideIcons.plugZap,
                variante: VarianteBouton.secondaire,
                // Lot L3 : le test n'annonce plus une connexion qu'aucun appareil n'a établie (ni délai de réponse inventé) ; sans adaptateur il refuse en nommant.
                onPressed: () {
                  final refus = adaptateurDuPoste(mag, c.aujourdhui).refus;
                  if (refus != null) {
                    ToastsSigh.afficher(context, '${refus.code} : ${refus.motif}',
                        type: TypeToast.attention, detail: refus.geste, duree: const Duration(seconds: 9));
                  }
                }),
          ]),
        ]),
      );
      final gauche = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _carteMode(c),
        const SizedBox(height: 16),
        _carteEtatCaisse(c),
        const SizedBox(height: 16),
        _carteImprimante(c),
        const SizedBox(height: 16),
        carteConfig,
      ]);
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
