import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';

/// L'état imprimé d'une opération : avis d'annulation ou attestation de remboursement.
PieceA4 pieceOperation(Fiche r,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final annulation = r['nature'] == 'Annulation';
  return PieceA4(
    titre: annulation ? 'Avis d’annulation de facture' : 'Attestation de remboursement',
    sousTitre: '${r['reference']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Référence', '${r['reference']}'),
      ('Date', dateDe(r['date'])),
      ('Facture concernée', '${r['factureNumero'] ?? ''}'),
      ('Patient', '${r['patient'] ?? ''}'),
      ('Montant', money(r['montant'])),
      ('Autorisé par', '${r['autorisePar'] ?? ''}'),
    ],
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
        ColonneEtat(libelle: 'Information', valeur: (x) => x['v']),
      ], lignes: [
        {'k': 'Nature de l’opération', 'v': r['nature']},
        {'k': 'Facture concernée', 'v': r['factureNumero']},
        {'k': 'Montant', 'v': money(r['montant'])},
        {'k': 'Motif', 'v': r['motif']},
      ])),
      if (annulation)
        const BlocTexte(
            'Cette annulation donne lieu à l’émission d’un avoir transmis au dispositif MECeF.',
            italique: true),
    ],
    signatures: [
      const Signature('Le Caissier'),
      Signature('La Directrice Administrative',
          nom: '${r['autorisePar'] ?? ''}'),
    ],
  );
}

/// `m8-remboursements` — « Remboursements & annulations » : trois natures, trois effets, tous motivés et journalisés (RG-12). L'annulation ne supprime
/// jamais la facture (RG-14) : elle la repasse impayée, MECeF « rejeté ». Le moteur est dans `packages/domaine` (`enregistrerOperation`).
class EcranRemboursements extends StatelessWidget with EcranMaquette {
  const EcranRemboursements({super.key});

  @override
  String get titre => 'Remboursements & annulations';

  @override
  String get description =>
      'Traitement des remboursements de trop-perçus et des annulations de factures, avec motif obligatoire.';

  @override
  String get regle =>
      'Toute annulation ou tout remboursement est motivé et journalisé (RG-12). L’annulation d’une facture normalisée déclenche l’émission d’un avoir MECeF.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('remboursements');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        int nb(String nature) => rows.where((r) => r['nature'] == nature).length;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Opérations enregistrées',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.undo2),
                KpiSigh(
                    libelle: 'Remboursements',
                    valeur: nombre(nb('Remboursement')),
                    icone: LucideIcons.banknote,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Annulations',
                    valeur: nombre(nb('Annulation')),
                    icone: LucideIcons.fileX,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Montant total',
                    valeur: money(rows.fold<num>(0, (a, r) => a + n(r['montant']))),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.info),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Remboursements et annulations',
                taillePage: 12,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'remboursements-annulations',
                messageVide: 'Aucun remboursement ni annulation enregistré.',
                lignes: rows,
                filtres: const [
                  FiltreTableau(nom: 'nature', libelle: 'Nature', options: [
                    OptionChamp('Remboursement'),
                    OptionChamp('Annulation'),
                  ])
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N°',
                      sansCoupure: true,
                      texte: (r) => '${r['reference']}',
                      rendu: (_, r) => Text('${r['reference']}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: JetonsShell.slate900))),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (r) => dateDe(r['date'])),
                  ColonneTableau(
                      cle: 'factureNumero',
                      libelle: 'Facture',
                      sansCoupure: true,
                      texte: (r) => '${r['factureNumero'] ?? ''}',
                      rendu: (_, r) => Text('${r['factureNumero'] ?? ''}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: JetonsShell.slate500))),
                  const ColonneTableau(cle: 'patient', libelle: 'Patient'),
                  ColonneTableau(
                      cle: 'nature',
                      libelle: 'Nature',
                      texte: (r) => '${r['nature']}',
                      rendu: (_, r) => BadgeSigh('${r['nature']}',
                          ton: r['nature'] == 'Annulation'
                              ? TonSigh.danger
                              : TonSigh.attention)),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant',
                      droite: true,
                      texte: (r) => m(r['montant']),
                      rendu: (_, r) => Text(m(r['montant']),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600))),
                  const ColonneTableau(cle: 'motif', libelle: 'Motif'),
                  const ColonneTableau(
                      cle: 'autorisePar', libelle: 'Autorisé par'),
                ],
                actionsLigne: (ctx, r) => [
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer',
                      onPressed: () => _imprimer(ctx, r)),
                ],
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouvelle opération',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => _ouvrir(context)),
                ],
              ),
            ]);
      },
    );
  }

  void _imprimer(BuildContext ctx, Fiche r) {
    final c = ContexteEcran.of(ctx);
    afficherApercu(
        ctx,
        pieceOperation(r,
            utilisateur: c.utilisateur,
            edite: c.aujourdhui,
            reference: PieceA4.reference_(
                c.aujourdhui, ImpressionPoste.prochainNumero())));
  }

  void _ouvrir(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final factures = facturesConcernables(m.collection('factures').actives);
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'factureId',
          libelle: 'Facture concernée',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          recherche: true,
          options: [
            for (final x in factures)
              OptionChamp('${x['id']}',
                  '${x['numero']} — ${x['patient']} — ${money(x['montantTTC'])}')
          ]),
      ChampDef(
          nom: 'nature',
          libelle: 'Nature de l’opération',
          type: TypeChamp.select,
          requis: true,
          aide:
              'L’avoir corrige une facture déjà émise ; le remboursement rend un trop-perçu ; l’annulation retire la pièce.',
          options: [for (final x in naturesOperation) OptionChamp(x)]),
      const ChampDef(
          nom: 'motifAvoir',
          libelle: 'Cas de figure',
          type: TypeChamp.select,
          aide: 'Les quatre situations relevées par la Direction.',
          options: [
            OptionChamp('erreur', 'Erreur de facturation'),
            OptionChamp('non_rendu', 'Service facturé mais non rendu'),
            OptionChamp('remboursement', 'Remboursement au patient'),
            OptionChamp('annulation', 'Annulation de la prestation'),
          ]),
      const ChampDef(
          nom: 'refacturation',
          libelle: 'Suite donnée',
          type: TypeChamp.select,
          aide:
              'Un service non rendu peut être refait puis refacturé, ou ne donner lieu à rien.',
          options: [
            OptionChamp('aucune',
                'Aucune refacturation — le service n’est pas exécuté'),
            OptionChamp('refaire', 'Le service est refait et refacturé'),
          ]),
      const ChampDef(
          nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
      const ChampDef(
          nom: 'montant',
          libelle: 'Montant (FCFA)',
          type: TypeChamp.nombre,
          requis: true),
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif',
          type: TypeChamp.textarea,
          requis: true,
          col: ColChamp.plein,
          lignes: 2,
          aide: 'Obligatoire — consigné au journal d’audit (RG-12).'),
      const ChampDef(nom: 'autorisePar', libelle: 'Autorisé par', requis: true),
    ], {
      'date': iso(c.aujourdhui),
      'autorisePar': 'TAKI Alimatou',
    });
    afficherModale<void>(ctx,
        titre: 'Remboursement ou annulation',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.undo2,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) {
                      ToastsSigh.afficher(
                          ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final fac = m.collection('factures').parId(v['factureId']);
                    final OperationEnregistree op;
                    try {
                      op = enregistrerOperation(
                          saisie: v,
                          facture: fac,
                          remboursements:
                              m.collection('remboursements').actives,
                          avoirs: m.collection('avoirs').actives,
                          facturesMere: m.collection('facturesMere').actives,
                          idAvoir: idAvoirSuivant(m),
                          jour: iso(c.aujourdhui),
                          utilisateur: c.utilisateur);
                    } on RefusOperation catch (e) {
                      ToastsSigh.afficher(ctx, e.motif, type: TypeToast.erreur);
                      return;
                    }
                    final annulations = <VoidCallback>[];
                    // B10 : la nature « Facture avoir » n'écrit plus une pièce négative dans `factures` ; elle passe par le MOTEUR UNIQUE
                    // (collection `avoirs`, contre-passation en brouillon, cumul porté par la facture). L'opération garde le lien.
                    if (op.avoir != null && fac != null) {
                      final ecrit = ecrireAvoirEmis(
                          m, fac, op.avoir!, '${op.remboursement['avoirId']}');
                      annulations.addAll(ecrit.annulations);
                    }
                    annulations.add(m
                        .collection('remboursements')
                        .inserer({...op.remboursement, 'statut': 'actif'},
                            prefixe: 'RBT')
                        .annuler);
                    if (op.patchFacture != null && fac != null) {
                      annulations.add(m
                          .collection('factures')
                          .mettreAJour(fac['id'], op.patchFacture!));
                    }
                    fermer();
                    ToastsSigh.afficher(
                        ctx,
                        '${v['nature']} de ${money(op.remboursement['montant'])} enregistré(e).',
                        type: TypeToast.succes, annuler: () {
                      for (final u in annulations.reversed) {
                        u();
                      }
                    });
                  }),
            ]);
  }
}
