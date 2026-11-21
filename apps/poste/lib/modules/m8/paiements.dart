import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d show iso;

import '../../core/icones.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/parcours_caisse.dart';
import '../../donnees/versements_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'acheteur_normalise.dart';
import 'commun.dart';
import 'factures.dart';
import 'impression.dart';
import 'saisie_versements.dart';

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

  // LOT TARIF-FIX-2 : une pièce en attente de prix reste VISIBLE parmi celles à encaisser (reste dû non calculable, jamais absente).
  List<Fiche> get _aRegler => [
        for (final f in _col!.actives)
          if (n(f['reliquat']) > 0 || (f['enAttentePrix'] == true && f['statutPaiement'] != 'soldee')) f
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
                  actionsLigne: (context, f) {
                    // LOT TARIF-FIX-2 : une pièce que le moteur refuserait d'encaisser (ligne sans prix) n'a PAS de commande « Encaisser » ; le motif est dit.
                    final ep = etatCaissePrix(c.magasin, f, c.aujourdhui);
                    return [
                      if (!ep.encaissable) motifSansPrix(ep.refus!),
                      // Encaisser est une ÉCRITURE : la commande est absente sans le droit d'éditer (jamais grisée).
                      if (c.droit.editer && ep.encaissable)
                        BoutonSigh(
                            libelle: 'Encaisser',
                            icone: LucideIcons.banknote,
                            taille: TailleBouton.sm,
                            onPressed: () => _encaisser(context, f)),
                    ];
                  },
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

  void _encaisser(BuildContext ctx, Fiche f0) {
    // LOT TARIF-FIX-2 : une ligne dont le prix est désormais en vigueur à la date de la pièce se valorise AVANT d'ouvrir l'encaissement.
    final c0 = ContexteEcran.of(ctx);
    if (lignesPrixManquant(f0).isNotEmpty) valoriserFacturePoste(c0.magasin, '${f0['id']}', c0.aujourdhui);
    final f = c0.magasin.collection('factures').parId(f0['id']) ?? f0;
    // Une pièce en attente de prix (encaissement du reste réglé) : le reste dû est celui des seules lignes valorisées.
    final reste = f['enAttentePrix'] == true
        ? ((f['lignes'] as List?) ?? const []).fold<num>(0, (a, x) {
            final l = (x as Map).cast<String, Object?>();
            return ligneSansPrix(l) || l['statutPaiement'] == 'paye' ? a : a + n(l['partPatient']);
          })
        : n(f['reliquat']);
    // LOT PAIE-V (Direction, 20/11/2026) : autant de versements que nécessaire, de modes différents, saisis dans UNE fenêtre. Le reste dû se calcule en direct ; le moteur
    // refuse un versement qui dépasse le dû, un mobile money sans référence, une modalité archivée, la part d'un assureur (refus nommés, rien n'est écrit).
    final saisie = ControleurSaisieVersements();
    final observation = ControleurFormulaire(const [
      ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ]);
    final jour = d.iso(c0.aujourdhui);
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
                ('Reste à payer', money(reste)),
              ]),
              if ('${f['assureur'] ?? ''}'.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Seule la part du patient se règle en caisse : la part de l’assureur (${money(f['partAssurance'])}) suit le circuit des règlements d’assureurs.')),
              const SizedBox(height: 12),
              SaisieVersements(fiches: modalitesVersementPoste(c0.magasin), jour: jour, reste: reste, controleur: saisie),
              const SizedBox(height: 8),
              FormulaireSigh(controleur: observation),
            ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              // Encaisser est une ÉCRITURE : la commande est absente sans le droit d'éditer (la liste ne l'offre pas) ; le moteur refuse aussi.
              BoutonSigh(
                  key: const ValueKey('valider-versements'),
                  libelle: 'Valider les versements',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final saisis = saisie.lire();
                    if (saisis == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    // L'encaissement passe par le MOTEUR : lignes réglées, analyses et imagerie libérées, tâches d'aval, base MECeF et ÉCRITURE comptable par versement.
                    // Un encaissement ne s'annule pas : remboursement ou avoir.
                    final c = ContexteEcran.of(ctx);
                    final ResultatCaisse res;
                    try {
                      res = encaisserFacture(c.magasin, '${f['id']}', versements: saisis, maintenant: c.aujourdhui);
                    } on RefusCaisse catch (e) {
                      ToastsSigh.afficher(ctx, 'Encaissement refusé.', type: TypeToast.erreur, detail: e.motif, duree: const Duration(seconds: 9));
                      return;
                    }
                    final obs = '${observation['observation'] ?? ''}'.trim();
                    if (obs.isNotEmpty) c.magasin.collection('factures').mettreAJour('${f['id']}', {'observationReglement': obs});
                    fermer();
                    annoncerNormalisation(ctx, res.normalisation);
                    ToastsSigh.afficher(ctx,
                        'Encaissement de ${money(res.montantRegle)} enregistré (${res.versements.length} versement${res.versements.length > 1 ? 's' : ''}).',
                        type: TypeToast.succes,
                        detail: (res.restantDu > 0
                                ? 'Reliquat de ${money(res.restantDu)}.'
                                : 'Facture soldée.') +
                            (res.ecritures.isNotEmpty
                                ? ' Une écriture comptable par versement, en brouillon.'
                                : ''));
                    imprimerRecu(ctx, _col!.parId(f['id'])!, lot: res.versements);
                  }),
            ]);
  }
}
