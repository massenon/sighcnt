import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/icones.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';
import 'factures.dart';
import 'impression.dart';

/// `m8-paiements` — écran de travail de la caisse : il ne crée pas de facture, il ENCAISSE celles qui sont dues.
class EcranPaiements extends StatefulWidget with EcranMaquette {
  const EcranPaiements({super.key});

  @override
  String get description =>
      'Encaissements par espèces, terminal de paiement électronique, MTN Mobile Money et Moov Money.';

  @override
  String get regle =>
      'Écran de travail de la caisse : il ne crée pas de facture mais encaisse celles qui sont dues. Une facture se corrige depuis l’émission ou par un avoir — jamais par retouche d’un règlement déjà passé (RG-12).';

  @override
  State<EcranPaiements> createState() => _EcranPaiementsState();
}

class _EcranPaiementsState extends State<EcranPaiements> {
  CollectionMagasin? _col;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final col = ContexteEcran.of(context).magasin.collection('factures');
    if (!identical(col, _col)) {
      _col?.removeListener(_maj);
      _col = col..addListener(_maj);
    }
  }

  @override
  void dispose() {
    _col?.removeListener(_maj);
    super.dispose();
  }

  void _maj() => setState(() {});

  List<Fiche> get _aRegler => [
        for (final f in _col!.actives)
          if (n(f['reliquat']) > 0) f
      ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final actives = _col!.actives;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        for (final mode in modesPaiement.take(4))
          () {
            final f = [
              for (final x in actives)
                if (x['modePaiement'] == mode.$1) x
            ];
            return KpiSigh(
                libelle: mode.$2,
                valeur:
                    money(f.fold<num>(0, (a, r) => a + n(r['montantPaye']))),
                icone: icone(mode.$3),
                indice: '${nombre(f.length)} opération(s)');
          }(),
      ]),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'aregler',
            libelle: 'À encaisser',
            compte: _aRegler.length,
            construire: (ctx) => TableauSigh(
                  colonnes: [
                    colNumero,
                    colDate,
                    colPatient,
                    colMontant,
                    ColonneTableau(
                        cle: 'montantPaye',
                        libelle: 'Déjà réglé',
                        droite: true,
                        texte: (f) => m(f['montantPaye'])),
                    colReliquat,
                    colStatutPaiement,
                  ],
                  lignes: _aRegler,
                  triInitial: 'date',
                  sensInitial: 'desc',
                  nomExport: 'factures-a-encaisser',
                  messageVide: 'Aucune facture en attente de règlement.',
                  actionsLigne: (context, f) => [
                    // Encaisser est une ÉCRITURE : la commande est absente sans le droit d'éditer (jamais grisée).
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Encaisser',
                          icone: LucideIcons.banknote,
                          taille: TailleBouton.sm,
                          onPressed: () => _encaisser(context, f)),
                  ],
                )),
        OngletDef(
            id: 'historique',
            libelle: 'Historique des règlements',
            construire: (ctx) => TableauSigh(
                  colonnes: [
                    colNumero,
                    colDate,
                    colPatient,
                    ColonneTableau(
                        cle: 'modePaiement',
                        libelle: 'Mode de règlement',
                        texte: (f) => modeLabel(f['modePaiement']),
                        rendu: (_, f) => BadgeSigh(modeLabel(f['modePaiement']),
                            ton: TonSigh.navy)),
                    ColonneTableau(
                        cle: 'montantPaye',
                        libelle: 'Montant réglé',
                        droite: true,
                        texte: (f) => m(f['montantPaye']),
                        rendu: (_, f) => Text(m(f['montantPaye']),
                            style: const TextStyle(
                                color: JetonsShell.success700,
                                fontSize: 14,
                                height: 20 / 14,
                                fontWeight: FontWeight.w600))),
                    colReliquat,
                    colStatutPaiement,
                  ],
                  lignes: [
                    for (final f in actives)
                      if (n(f['montantPaye']) > 0) f
                  ],
                  taillePage: 15,
                  triInitial: 'date',
                  sensInitial: 'desc',
                  nomExport: 'paiements',
                  filtres: [
                    FiltreTableau(
                        nom: 'modePaiement',
                        libelle: 'Mode',
                        options: [
                          for (final x in modesPaiement) OptionChamp(x.$1, x.$2)
                        ])
                  ],
                  actionsLigne: (context, f) => [
                    BoutonIcone(
                        icone: LucideIcons.printer,
                        libelle: 'Reçu de paiement',
                        onPressed: () => imprimerRecu(context, f))
                  ],
                )),
      ]),
    ]);
  }

  void _encaisser(BuildContext ctx, Fiche f) {
    final reste = n(f['reliquat']);
    final form = ControleurFormulaire(const [
      ChampDef(
          nom: 'montant',
          libelle: 'Montant encaissé (FCFA)',
          type: TypeChamp.nombre,
          requis: true),
      ChampDef(
          nom: 'modePaiement',
          libelle: 'Mode de règlement',
          type: TypeChamp.select,
          requis: true,
          options: [
            OptionChamp('especes', 'Espèces'),
            OptionChamp('tpe', 'TPE (carte bancaire)'),
            OptionChamp('mtn', 'MTN Mobile Money'),
            OptionChamp('moov', 'Moov Money'),
          ]),
      ChampDef(
          nom: 'reference',
          libelle: 'Référence de la transaction',
          aide:
              'N° de transaction Mobile Money ou ticket TPE, le cas échéant.'),
      ChampDef(
          nom: 'observation',
          libelle: 'Observation',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
    ], {
      'montant': '${reste.round()}',
      'modePaiement':
          '${f['modePaiement']}' == 'assurance' ? 'especes' : f['modePaiement'],
    });
    afficherModale<void>(ctx,
        titre: 'Encaissement',
        sousTitre: '${f['numero']} — ${f['patient']}',
        corps: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DescListeSigh([
                ('Facture', f['numero']),
                ('Patient', f['patient']),
                ('Montant total', money(f['montantTTC'])),
                ('Part patient', money(f['partPatient'])),
                ('Déjà réglé', money(f['montantPaye'])),
                ('Reste à payer', money(f['reliquat'])),
              ]),
              const SizedBox(height: 12),
              FormulaireSigh(controleur: form),
            ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Valider l’encaissement',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = form.valider();
                    if (v == null) {
                      ToastsSigh.afficher(
                          ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final montant = n(v['montant']);
                    if (montant <= 0) {
                      ToastsSigh.afficher(
                          ctx, 'Le montant doit être supérieur à zéro.',
                          type: TypeToast.erreur);
                      return;
                    }
                    // Refus nommé : on n'encaisse jamais plus que le reste dû.
                    if (montant > reste) {
                      ToastsSigh.afficher(ctx,
                          'Le montant dépasse le reste dû (${money(reste)}).',
                          type: TypeToast.erreur);
                      return;
                    }
                    final nouveau = n(f['montantPaye']) + montant;
                    final restant = n(f['partPatient']) - nouveau;
                    final c = ContexteEcran.of(ctx);
                    final annuler = _col!.mettreAJour(f['id'], {
                      'montantPaye': nouveau,
                      'reliquat': restant,
                      'modePaiement': v['modePaiement'],
                      'statutPaiement': restant <= 0 ? 'soldee' : 'partielle',
                      'dernierReglement': {
                        'montant': montant,
                        'encaissePar': c.utilisateur,
                        'le': iso(c.aujourdhui)
                      },
                    });
                    fermer();
                    ToastsSigh.afficher(
                        ctx, 'Encaissement de ${money(montant)} enregistré.',
                        type: TypeToast.succes,
                        detail: restant > 0
                            ? 'Reliquat de ${money(restant)}.'
                            : 'Facture soldée.',
                        annuler: annuler);
                    imprimerRecu(ctx, _col!.parId(f['id'])!,
                        versement: {'montant': montant, ...v});
                  }),
            ]);
  }
}
