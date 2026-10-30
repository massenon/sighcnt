import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'besoins_commun.dart';

const _libellesVues = {
  'miennes': 'Mes demandes',
  'arbitrage': 'Arbitrage & validation DAF',
  'achats': 'Besoins validés — achats & logistique',
  'tous': 'Tous les bons',
};

/// Le bon d'expression de besoins imprimé : quantité voulue, accordée, livrée, trois signatures (demandeur, gestionnaire de stock, DAF — RG-04).
PieceA4 pieceBon(Fiche b,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  return PieceA4(
    titre: 'Bon d’expression de besoins',
    sousTitre: '${b['reference']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Référence', '${b['reference']}'),
      ('Date', dateDe(b['date'])),
      ('Service demandeur', '${b['service'] ?? ''}'),
      ('Demandeur', '${b['demandeur'] ?? ''}'),
      ('Motif', '${(b['motif'] ?? '') == '' ? '—' : b['motif']}'),
      ('Étape', etatBesoin(b['etape']).libelle),
    ],
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Désignation', valeur: (l) => l['produit']),
        ColonneEtat(libelle: 'Unité', valeur: (l) => l['unite']),
        ColonneEtat(
            libelle: 'Quantité voulue',
            valeur: (l) => l['quantiteDemandee'],
            droite: true),
        ColonneEtat(
            libelle: 'Quantité accordée',
            valeur: (l) => l['quantiteAccordee'] ?? '',
            droite: true),
        ColonneEtat(
            libelle: 'Quantité livrée',
            valeur: (l) => l['quantiteLivree'] ?? '',
            droite: true),
      ], lignes: lignesDeBonAchat(b))),
    ],
    signatures: [
      Signature('Le Demandeur', nom: '${b['demandeur'] ?? ''}'),
      const Signature('Le Gestionnaire de Stock',
          nom: 'MAMAN Zoukanéri', mention: 'Contrôle de disponibilité'),
      Signature('La Directrice Administrative',
          nom: directriceAdministrative, mention: 'Validation (RG-04)'),
    ],
  );
}

/// `m7-besoins` — « Bons d’expression de besoins » : QUATRE vues sur UNE collection (une vue est un filtre, jamais une collection). Tout agent exprime un
/// besoin ; la DAF arbitre (valider, rejeter avec motif, demander un complément) et sa validation informe le comptable et le gestionnaire de stock.
/// Le moteur est dans `packages/domaine` (`achats/besoins.dart`).
class EcranBesoins extends StatelessWidget with EcranMaquette {
  const EcranBesoins({super.key});

  @override
  String get titre => 'Bons d’expression de besoins';

  @override
  String get description =>
      'Demandes internes des services : désignation, date, secteur demandeur, quantité voulue et quantité accordée.';

  @override
  String get regle =>
      'Tout agent exprime un besoin — papier, produits d’entretien, fournitures, petit matériel : l’écran est ouvert à tous les postes, chacun sur SA vue. La DAF arbitre (valider, rejeter avec motif, demander un complément) ; sa validation informe le comptable et le gestionnaire de stock, qui transforment le besoin en commande puis en distribution. Le bon distingue la quantité demandée de la quantité accordée, et le circuit reste : brouillon → soumis → contrôle stock → validation DA → accordé → préparation → livraison → clôture. Un bon rejeté n’est pas archivé : le service doit pouvoir en lire le motif.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('besoins');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final actifs = col.actives;
        final moi = c.utilisateur;
        final miennes = bonsMiens(actifs, moi);
        final aArbitrer = bonsAArbitrer(actifs);
        final pourAchat = bonsPourAchat(actifs);
        final vues = vuesOffertes(role: c.role, droitVoir: c.droit.voir);

        Widget tableau(String titre, List<Fiche> lignes, String vue) =>
            _TableauBesoins(
                titre: titre, lignes: lignes, vue: vue, contexteEcran: context);

        Widget contenu(String vue) {
          switch (vue) {
            case 'miennes':
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const NoteSigh(
                        'Exprimez ici vos besoins de fournitures — papier, produits d’entretien, stylos, petit matériel. La DAF arbitre, puis l’achat et la distribution suivent : vous voyez l’avancement sans avoir à le demander.',
                        icone: LucideIcons.clipboardPen),
                    const SizedBox(height: 16),
                    tableau('Mes demandes', miennes, 'miennes'),
                  ]);
            case 'arbitrage':
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const NoteSigh(
                        'Valider accorde le besoin et informe le comptable et le gestionnaire de stock. Rejeter et demander un complément exigent leur motif — un refus sans motif se représente la semaine suivante à l’identique.',
                        ton: TonSigh.attention,
                        icone: LucideIcons.gavel),
                    const SizedBox(height: 16),
                    tableau('Demandes à arbitrer', aArbitrer, 'arbitrage'),
                  ]);
            case 'achats':
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const NoteSigh(
                        'Ces besoins sont accordés par la DAF. Ils deviennent un bon de commande fournisseur (RG-04) ou une distribution directe si l’article est déjà au magasin.',
                        ton: TonSigh.succes,
                        icone: LucideIcons.packageCheck),
                    const SizedBox(height: 16),
                    tableau('Besoins accordés', pourAchat, 'achats'),
                  ]);
            default:
              return tableau('Bons d’expression de besoins', actifs, 'tous');
          }
        }

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Mes demandes',
                    valeur: nombre(miennes.length),
                    icone: LucideIcons.userPen,
                    indice: '${nombre(actifs.length)} bon(s) au registre'),
                KpiSigh(
                    libelle: 'En attente d’arbitrage DAF',
                    valeur: nombre(aArbitrer.length),
                    icone: LucideIcons.hourglass,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Livrés',
                    valeur: nombre(bonsLivres(actifs)),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Montant estimé cumulé',
                    valeur: money(actifs.fold<num>(
                        0, (a, b) => a + n(b['montantEstime']))),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.info),
              ]),
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Circuit de traitement',
                  child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final (i, (e, nb)) in compteCircuit(actifs).indexed) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: tonAchat(e.ton).fond50,
                                border:
                                    Border.all(color: tonAchat(e.ton).bordure200),
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(e.libelle,
                                  style: TextStyle(
                                      color: tonAchat(e.ton).texte900,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(width: 6),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(99)),
                                  child: Text('$nb',
                                      style: TextStyle(
                                          color: tonAchat(e.ton).icone600,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600))),
                            ]),
                          ),
                          if (i < etapesBesoin.length - 1)
                            const Icon(LucideIcons.chevronRight,
                                size: 14, color: JetonsShell.slate300),
                        ],
                      ])),
              const SizedBox(height: 16),
              OngletsSigh(onglets: [
                for (final v in vues)
                  OngletDef(
                      id: v,
                      libelle: _libellesVues[v]!,
                      compte: switch (v) {
                        'miennes' => miennes.length,
                        'arbitrage' => aArbitrer.length,
                        'achats' => pourAchat.length,
                        _ => actifs.length,
                      },
                      construire: (_) => contenu(v)),
              ]),
            ]);
      },
    );
  }
}

/// La fabrique de tableau — une seule, pour les quatre vues.
class _TableauBesoins extends StatelessWidget {
  const _TableauBesoins(
      {required this.titre,
      required this.lignes,
      required this.vue,
      required this.contexteEcran});
  final String titre;
  final List<Fiche> lignes;
  final String vue;

  /// Le contexte de l'ÉCRAN (les fenêtres vivent au-dessus de la coque).
  final BuildContext contexteEcran;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('besoins');
    return TableauSigh(
      titre: titre,
      lignes: lignes,
      taillePage: 12,
      triInitial: 'date',
      sensInitial: 'desc',
      nomExport: 'bons-expression-besoins',
      messageVide: 'Aucun enregistrement.',
      filtres: [
        FiltreTableau(nom: 'etape', libelle: 'Étape', options: [
          for (final e in etapesBesoin) OptionChamp(e.id, e.libelle)
        ]),
        FiltreTableau(nom: 'service', libelle: 'Service demandeur', options: [
          for (final s in servicesDemandeurs) OptionChamp(s)
        ]),
      ],
      actions: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau bon',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => _ouvrirBon(contexteEcran, null)),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'reference',
            libelle: 'N° bon',
            sansCoupure: true,
            texte: (b) => '${b['reference']}',
            rendu: (_, b) => refMono(b['reference'])),
        ColonneTableau(
            cle: 'date',
            libelle: 'Date',
            sansCoupure: true,
            texte: (b) => dateDe(b['date'])),
        const ColonneTableau(cle: 'service', libelle: 'Service demandeur'),
        const ColonneTableau(cle: 'demandeur', libelle: 'Demandeur'),
        ColonneTableau(
            cle: 'nbLignes',
            libelle: 'Articles',
            droite: true,
            valeur: (b) => lignesDeBonAchat(b).length,
            texte: (b) => '${lignesDeBonAchat(b).length}'),
        ColonneTableau(
            cle: 'quantites',
            libelle: 'Demandé / Accordé',
            droite: true,
            triable: false,
            texte: (b) =>
                '${quantiteDemandeeTotale(b)} / ${quantiteAccordeeTotale(b)}',
            rendu: (_, b) {
              final dem = quantiteDemandeeTotale(b),
                  acc = quantiteAccordeeTotale(b);
              return Text.rich(TextSpan(children: [
                TextSpan(
                    text: nombre(dem),
                    style: const TextStyle(
                        color: JetonsShell.slate700,
                        fontWeight: FontWeight.w500)),
                const TextSpan(
                    text: ' / ',
                    style: TextStyle(color: JetonsShell.slate400)),
                TextSpan(
                    text: acc != 0 ? nombre(acc) : '—',
                    style: TextStyle(
                        fontWeight:
                            acc == 0 ? FontWeight.w400 : FontWeight.w600,
                        color: acc == 0
                            ? JetonsShell.slate400
                            : (acc == dem
                                ? JetonsShell.success600
                                : JetonsShell.warning600))),
              ]));
            }),
        ColonneTableau(
            cle: 'montantEstime',
            libelle: 'Montant estimé',
            droite: true,
            texte: (b) => m(b['montantEstime'])),
        ColonneTableau(
            cle: 'etape',
            libelle: 'Étape',
            texte: (b) => etatBesoin(b['etape']).libelle,
            rendu: (_, b) => BadgeSigh(etatBesoin(b['etape']).libelle,
                ton: tonAchat(etatBesoin(b['etape']).ton))),
      ],
      alClicLigne: (b) => _consulter(contexteEcran, b),
      actionsLigne: (ctx, b) => [
        BoutonIcone(
            icone: LucideIcons.eye,
            libelle: 'Consulter',
            onPressed: () => _consulter(contexteEcran, b)),
        BoutonIcone(
            icone: LucideIcons.printer,
            libelle: 'Imprimer le bon',
            onPressed: () => _imprimer(contexteEcran, b)),
        // L'ARBITRAGE N'APPARAÎT QU'À SA VUE : proposer « Valider » sur un bon déjà accordé ferait douter de ce qui a été décidé.
        if (vue == 'arbitrage') ...[
          BoutonIcone(
              icone: LucideIcons.check,
              libelle: 'Valider le besoin',
              onPressed: () => _arbitrer(contexteEcran, b, Arbitrage.valider)),
          BoutonIcone(
              icone: LucideIcons.x,
              libelle: 'Rejeter avec motif',
              onPressed: () => _arbitrer(contexteEcran, b, Arbitrage.rejeter)),
          BoutonIcone(
              icone: LucideIcons.circleQuestionMark,
              libelle: 'Demander un complément',
              onPressed: () =>
                  _arbitrer(contexteEcran, b, Arbitrage.complement)),
        ],
        if (vue == 'achats') ...[
          BoutonIcone(
              icone: LucideIcons.shoppingCart,
              libelle: 'Transformer en bon de commande',
              onPressed: () => _versCommande(contexteEcran, b)),
          BoutonIcone(
              icone: LucideIcons.packageCheck,
              libelle: 'Marquer distribué au service',
              onPressed: () => _distribuer(contexteEcran, b)),
        ],
        if (vue != 'arbitrage' && vue != 'achats') ...[
          if (c.droit.editer)
            BoutonIcone(
                icone: LucideIcons.pencil,
                libelle: 'Modifier',
                onPressed: () => _ouvrirBon(contexteEcran, b)),
          if (c.droit.annuler)
            BoutonIcone(
                icone: LucideIcons.archive,
                libelle: 'Archiver',
                onPressed: () {
                  final annuler = col.archiver(b['id']);
                  dire(contexteEcran, 'Bon archivé.',
                      type: TypeToast.succes, annuler: annuler);
                }),
        ],
      ],
    );
  }
}

void _imprimer(BuildContext ctx, Fiche b) => imprimerPiece(
    ctx,
    (c) => pieceBon(b,
        utilisateur: c.utilisateur, edite: c.aujourdhui, reference: refEtat(c)));

void _consulter(BuildContext ctx, Fiche b) {
  final idx = [for (final e in etapesBesoin) e.id].indexOf('${b['etape']}');
  afficherTiroir<void>(ctx,
      titre: 'Bon ${b['reference']}',
      sousTitre: '${b['service']} — ${dateDe(b['date'])}',
      largeurMax: 768,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DescListeSigh([
          ('Référence', b['reference']),
          ('Date', dateDe(b['date'])),
          ('Service demandeur', b['service']),
          ('Demandeur', b['demandeur']),
          ('Motif', b['motif']),
          (
            'Étape',
            BadgeSigh(etatBesoin(b['etape']).libelle,
                ton: tonAchat(etatBesoin(b['etape']).ton))
          ),
          ('Validé par', b['valideePar'] ?? 'En attente'),
          ('Montant estimé', money(b['montantEstime'])),
        ]),
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Avancement du circuit',
            child: ChronologieSigh([
              for (final (i, e) in etapesBesoin.indexed)
                (
                  titre: e.libelle,
                  detail: i == idx
                      ? 'Étape courante'
                      : (i < idx ? 'Franchie' : 'À venir'),
                  date: i <= idx ? '✓' : '—',
                  ton: i < idx
                      ? TonSigh.succes
                      : (i == idx ? TonSigh.navy : TonSigh.neutre),
                )
            ])),
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Articles demandés',
            sansRemplissage: true,
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Article', (l) => '${l['produit']}'),
              ColonneMini('Unité', (l) => '${l['unite']}'),
              ColonneMini('Demandée', (l) => nombre(l['quantiteDemandee']),
                  droite: true),
              ColonneMini(
                  'Accordée',
                  (l) => l['quantiteAccordee'] != null
                      ? nombre(l['quantiteAccordee'])
                      : '—',
                  droite: true),
              ColonneMini(
                  'Livrée',
                  (l) => l['quantiteLivree'] != null
                      ? nombre(l['quantiteLivree'])
                      : '—',
                  droite: true),
            ], lignes: lignesDeBonAchat(b))),
      ]),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Imprimer',
                icone: LucideIcons.printer,
                variante: VarianteBouton.secondaire,
                onPressed: () => _imprimer(ctx, b)),
            if (ContexteEcran.of(ctx).droit.editer)
              BoutonSigh(
                  libelle: 'Modifier',
                  icone: LucideIcons.pencil,
                  onPressed: () {
                    fermer();
                    _ouvrirBon(ctx, b);
                  }),
          ]);
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// L'ARBITRAGE DE LA DAF
// ---------------------------------------------------------------------------------------------------------------------------------------

void _arbitrer(BuildContext ecran, Fiche b, Arbitrage quoi) {
  final titres = {
    Arbitrage.valider: 'Valider ce besoin ?',
    Arbitrage.rejeter: 'Rejeter ce besoin ?',
    Arbitrage.complement: 'Demander un complément d’information ?',
  };
  afficherModale<void>(ecran,
      titre: titres[quoi]!,
      sousTitre:
          '${b['reference']} — ${b['service']} · ${money(b['montantEstime'], avecDevise: false)}',
      corps: _ModaleArbitrage(
          contexte: ContexteEcran.of(ecran), ecran: ecran, bon: b, quoi: quoi),
      pied: null);
}

class _ModaleArbitrage extends StatefulWidget {
  const _ModaleArbitrage(
      {required this.contexte,
      required this.ecran,
      required this.bon,
      required this.quoi});
  final ContexteEcran contexte;
  final BuildContext ecran;
  final Fiche bon;
  final Arbitrage quoi;
  @override
  State<_ModaleArbitrage> createState() => _EtatModaleArbitrage();
}

class _EtatModaleArbitrage extends State<_ModaleArbitrage> {
  late final ControleurFormulaire _f;

  @override
  void initState() {
    super.initState();
    final valider = widget.quoi == Arbitrage.valider;
    _f = ControleurFormulaire([
      ChampDef(
          nom: 'motif',
          libelle: valider ? 'Observation (facultative)' : 'Motif — obligatoire',
          type: TypeChamp.textarea,
          lignes: 3,
          requis: !valider,
          col: ColChamp.plein,
          aide: valider
              ? 'Ce que la DAF souhaite porter à la connaissance de l’achat.'
              : 'Le service doit pouvoir lire POURQUOI : sans motif, la même demande revient à l’identique.')
    ]);
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _envoyer(VoidCallback fermer) {
    final c = widget.contexte;
    final v = _f.valider();
    if (v == null) {
      dire(widget.ecran, 'Le motif est obligatoire.', type: TypeToast.erreur);
      return;
    }
    final ArbitrageEnregistre r;
    try {
      r = arbitrerBon(
          bon: widget.bon,
          quoi: widget.quoi,
          motif: '${v['motif'] ?? ''}',
          utilisateur: c.utilisateur,
          maintenant: c.aujourdhui.toIso8601String());
    } on RefusAchat catch (e) {
      dire(widget.ecran, e.motif, type: TypeToast.erreur);
      return;
    }
    c.magasin.collection('besoins').mettreAJour(widget.bon['id'], r.patch);
    // La validation INFORME deux postes — par une notification de poste, née du geste, pas par un message à écrire à la main.
    for (final nt in r.notifications) {
      notifierPoste(c.magasin, nt, c.aujourdhui);
    }
    fermer();
    dire(widget.ecran, r.message,
        type: r.type == 'success' ? TypeToast.succes : TypeToast.attention,
        duree: const Duration(seconds: 8));
  }

  @override
  Widget build(BuildContext context) {
    final valider = widget.quoi == Arbitrage.valider;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiniTableauSigh(colonnes: [
            ColonneMini('Article', (l) => '${l['produit']}'),
            ColonneMini('Demandé', (l) => nombre(l['quantiteDemandee']),
                droite: true),
            ColonneMini(
                'Accordé',
                (l) => l['quantiteAccordee'] == null
                    ? '—'
                    : nombre(l['quantiteAccordee']),
                droite: true),
          ], lignes: lignesDeBonAchat(widget.bon)),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: _f),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: () => Navigator.of(context).pop()),
            const SizedBox(width: 8),
            BoutonSigh(
                libelle: valider
                    ? 'Valider et informer'
                    : (widget.quoi == Arbitrage.rejeter
                        ? 'Rejeter'
                        : 'Demander'),
                icone: valider ? LucideIcons.check : LucideIcons.send,
                onPressed: () => _envoyer(() => Navigator.of(context).pop())),
          ]),
        ]);
  }
}

/// Le besoin accordé devient une COMMANDE : on mène au bon écran plutôt que de fabriquer la commande à l'aveugle — RG-04 veut la validation de la DAF
/// sur la commande elle-même.
Future<void> _versCommande(BuildContext ecran, Fiche b) async {
  final c = ContexteEcran.of(ecran);
  final ok = await confirmerSigh(ecran,
      titre: 'Transformer en bon de commande ?',
      message:
          'Le besoin ${b['reference']} passe en préparation et l’écran des commandes s’ouvre. RG-04 : la commande devra être validée par la Directrice Administrative avant transmission au fournisseur.',
      libelleOk: 'Ouvrir les commandes');
  if (!ok) return;
  c.magasin.collection('besoins').mettreAJour(
      b['id'],
      versCommandeBesoin(
          utilisateur: c.utilisateur,
          maintenant: c.aujourdhui.toIso8601String()));
  c.aller('m7-commandes');
}

Future<void> _distribuer(BuildContext ecran, Fiche b) async {
  final c = ContexteEcran.of(ecran);
  final ok = await confirmerSigh(ecran,
      titre: 'Marquer le besoin distribué ?',
      message:
          'Le service ${b['service']} a reçu les articles du bon ${b['reference']}. Le bon sort du circuit d’achat.',
      libelleOk: 'Distribuer');
  if (!ok || !ecran.mounted) return;
  c.magasin.collection('besoins').mettreAJour(
      b['id'],
      distribuerBesoin(
          utilisateur: c.utilisateur,
          maintenant: c.aujourdhui.toIso8601String()));
  dire(ecran, messageDistribution(b), type: TypeToast.succes);
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// LA SAISIE : le formulaire s'adapte à qui l'ouvre
// ---------------------------------------------------------------------------------------------------------------------------------------

void _ouvrirBon(BuildContext ecran, Fiche? record) {
  final c = ContexteEcran.of(ecran);
  afficherModale<void>(ecran,
      titre: record != null
          ? 'Modifier le bon ${record['reference']}'
          : 'Nouveau bon d’expression de besoins',
      sousTitre:
          'La quantité accordée est renseignée après validation de la Directrice Administrative (RG-04).',
      taille: TailleModale.xl,
      corps: _ModaleBon(contexte: c, ecran: ecran, record: record),
      pied: null);
}

class _ModaleBon extends StatefulWidget {
  const _ModaleBon(
      {required this.contexte, required this.ecran, required this.record});
  final ContexteEcran contexte;
  final BuildContext ecran;
  final Fiche? record;
  @override
  State<_ModaleBon> createState() => _EtatModaleBon();
}

class _EtatModaleBon extends State<_ModaleBon> {
  late final ControleurFormulaire _f;
  late final List<Fiche> _lignes;
  late final List<Fiche> _produits;

  @override
  void initState() {
    super.initState();
    final c = widget.contexte;
    final r = widget.record;
    _lignes = r == null ? [] : lignesDeBonAchat(r);
    _produits = articlesDuReferentiel(c.magasin);
    // Seul celui qui tient le circuit choisit l'étape ; un agent qui exprime un besoin n'a pas à se placer lui-même en « validation DA ».
    final pilote = pilotageCircuit(role: c.role, droitEditer: c.droit.editer);
    _f = ControleurFormulaire([
      const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
      ChampDef(
          nom: 'service',
          libelle: 'Service demandeur',
          type: TypeChamp.select,
          requis: true,
          options: [for (final s in servicesDemandeurs) OptionChamp(s)]),
      const ChampDef(nom: 'demandeur', libelle: 'Demandeur', requis: true),
      ChampDef(
          nom: 'categorie',
          libelle: 'Catégorie du besoin',
          type: TypeChamp.select,
          requis: true,
          options: [for (final s in categoriesBesoin) OptionChamp(s)]),
      const ChampDef(nom: 'urgent', libelle: 'Besoin urgent', type: TypeChamp.case_),
      if (pilote)
        ChampDef(
            nom: 'etape',
            libelle: 'Étape du circuit',
            type: TypeChamp.select,
            requis: true,
            options: [
              for (final e in etapesBesoin) OptionChamp(e.id, e.libelle)
            ]),
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif de la demande',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein,
          aide: 'À quoi cela va servir : c’est ce que la DAF lit pour arbitrer.'),
    ], r ?? {
      'date': iso(c.aujourdhui),
      'etape': etapeParDefaut(pilote: pilote),
      'demandeur': c.utilisateur,
    });
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _enregistrer(VoidCallback fermer) {
    final c = widget.contexte;
    final v = _f.valider();
    if (v == null) {
      dire(widget.ecran, 'Le formulaire comporte des erreurs.',
          type: TypeToast.erreur);
      return;
    }
    final col = c.magasin.collection('besoins');
    final Fiche res;
    try {
      res = bonEnregistre(
          saisie: v, lignes: _lignes, existant: widget.record, bons: col.toutes);
    } on RefusAchat catch (e) {
      dire(widget.ecran, e.motif, type: TypeToast.erreur);
      return;
    }
    final VoidCallback annuler;
    final String message;
    if (widget.record != null) {
      annuler = col.mettreAJour(widget.record!['id'], res);
      message = 'Bon mis à jour.';
    } else {
      final ins = col.inserer({...res, 'statut': 'actif'}, prefixe: 'BES');
      annuler = ins.annuler;
      message = 'Bon créé — ${res['reference']}';
    }
    fermer();
    dire(widget.ecran, message, type: TypeToast.succes, annuler: annuler);
  }

  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormulaireSigh(controleur: _f),
            const SizedBox(height: 16),
            EditeurLignes(
                ecran: widget.ecran,
                produits: _produits,
                lignes: _lignes,
                commande: false,
                alChange: () {}),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              BoutonSigh(
                  libelle: widget.record != null ? 'Enregistrer' : 'Créer le bon',
                  icone: LucideIcons.save,
                  onPressed: () =>
                      _enregistrer(() => Navigator.of(context).pop())),
            ]),
          ]);
}
