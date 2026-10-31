import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpc_commun.dart';

/// `m12-bfr` — « Besoin en fonds de roulement » : créances clients, valorisation des stocks et dettes fournisseurs — le besoin de financement du cycle
/// d'exploitation, calculé en continu.
///
/// Le BFR est AGRÉGÉ, JAMAIS SAISI : créances (M9) + stocks (M6) − dettes fournisseurs (M7), chaque composante gardant la définition de son registre d'origine.
/// Un composant NON AMORCÉ SE DIT : un BFR amputé de ses dettes est surestimé. L'encours se lit À UNE DATE, le flux SUR UNE PÉRIODE. Chaque composante se
/// redescend à sa source. Le moteur est dans `cpc_bfr.dart` du domaine (rejoué sur les vecteurs de `SIGH.bfr`).
///
/// Écart E808 : la méthode de valorisation des stocks (prix de vente ou CUMP) est un réglage d'exploitation que le jeu du poste ne porte pas : le poste
/// applique le défaut, le prix de vente (= prix d'achat, RG-02), et l'annonce.
class EcranBfr extends StatefulWidget with EcranMaquette {
  const EcranBfr({super.key});

  @override
  String get titre => 'Besoin en fonds de roulement';

  @override
  String get description =>
      'Créances clients, valorisation des stocks et dettes fournisseurs — le besoin de financement du cycle d’exploitation, calculé en continu.';

  @override
  String get regle =>
      'Le BFR est agrégé, jamais saisi : créances (M9) + stocks (M6) − dettes fournisseurs (M7). Chaque composante garde la définition de son registre d’origine — deux définitions du même encours se contrediraient en réunion. Un composant non amorcé se dit : un BFR amputé de ses dettes est surestimé, et un chiffre faux qui a l’air juste est pire qu’une case vide.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'Tableau décisionnel',
            icone: LucideIcons.gauge,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('m12-tableau-decisionnel')),
        BoutonSigh(
            libelle: 'Créances assureurs',
            icone: LucideIcons.hourglass,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('m9-creances')),
      ];

  @override
  State<EcranBfr> createState() => _EtatBfr();
}

class _EtatBfr extends State<EcranBfr> {
  ControleurFormulaire? _date, _periode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_date != null) return;
    final c = ContexteEcran.of(context);
    _date = champUnique(const ChampDef(nom: 'fin', libelle: 'Encours arrêtés au', type: TypeChamp.date, col: ColChamp.plein), iso(c.aujourdhui));
    _periode = champUnique(
        const ChampDef(nom: 'jours', libelle: 'Chiffre d’affaires observé sur', type: TypeChamp.select, col: ColChamp.plein, options: [
          OptionChamp('30', '30 derniers jours'),
          OptionChamp('90', '90 derniers jours'),
          OptionChamp('180', '6 derniers mois'),
          OptionChamp('365', '12 derniers mois'),
        ]),
        '90');
    for (final x in [_date!, _periode!]) {
      x.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  CpcBfr _calcul(ContexteEcran c) => cpcBfr(
      factures: c.magasin.collection('factures').actives,
      produits: c.magasin.collection('produits').actives,
      facturesFournisseurs: c.magasin.collection('facturesFournisseurs').actives,
      auj: c.aujourdhui,
      fin: '${_date!['fin'] ?? ''}'.isEmpty ? iso(c.aujourdhui) : _date!['fin'],
      jours: int.tryParse('${_periode!['jours']}') ?? 90);

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final b = _calcul(c);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Besoin en fonds de roulement',
            sousTitre: 'Encours arrêtés au ${dateDe(b.arrete)}',
            cartouche: [
              ('En-cours clients', money(b.creances)),
              ('dont part assureurs', money(b.creancesAssureurs)),
              ('Valorisation des stocks', money(b.stocks)),
              ('Dettes fournisseurs', money(b.dettes)),
              ('Besoin en fonds de roulement', money(b.bfr)),
              ('En jours de chiffre d’affaires', b.bfrJours != null ? '${nombre(b.bfrJours)} jours' : '—'),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Composante', valeur: (r) => r['quoi']),
                ColonneEtat(libelle: 'Registre d’origine', valeur: (r) => r['ou']),
                ColonneEtat(libelle: 'Montant', droite: true, valeur: (r) => m(r['montant']), somme: (r) => n(r['montant'])),
              ], lignes: cpcLignesBfr(b))
            ],
            signatures: [const Signature('Le Comptable'), signDafCompta]));
  }

  Widget _vue(BuildContext ctx, ContexteEcran c) {
    final b = _calcul(c);
    final fin = '${_date!['fin'] ?? ''}'.isEmpty ? iso(c.aujourdhui) : '${_date!['fin']}';
    final alertes = cpcAlertesRecouvrement(
        factures: c.magasin.collection('factures').actives,
        objectifs: c.magasin.collection('objectifsPilotage').toutes,
        auj: c.aujourdhui,
        fin: fin);
    String nomCompagnie(String code) {
      for (final a in c.magasin.collection('assureurs').toutes) {
        if (a['code'] == code) return '${a['nom']}';
      }
      return code;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // L'ENCOURS SE LIT À UNE DATE, LE FLUX SUR UNE PÉRIODE : les afficher sous le même filtre sans le dire ferait croire que le stock détenu dépend de la fenêtre.
      NoteSigh(
          'Les trois encours sont arrêtés au ${dateDe(b.arrete)} — ils ne dépendent pas de la fenêtre choisie. Seul le chiffre d’affaires, et donc le BFR exprimé en jours, se lit sur la période du ${dateDe(b.fenetre.debut)} au ${dateDe(b.fenetre.fin)}.',
          icone: LucideIcons.calendarRange),
      if (b.incomplet.isNotEmpty) ...[
        const SizedBox(height: 16),
        NoteSigh(
            'Calcul incomplet — ${b.incomplet.join(' et ')} ne sont pas amorcés sur ce poste. Le BFR affiché est donc surestimé de la dette qui manque : ouvrez le registre concerné pour que la composante entre dans le calcul.',
            ton: TonSigh.danger,
            icone: LucideIcons.triangleAlert),
      ],
      const SizedBox(height: 16),
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'En-cours clients',
            valeur: money(b.creances),
            icone: LucideIcons.handCoins,
            ton: TonSigh.attention,
            indice: '${m(b.creancesAssureurs)} assureurs · ${m(b.restesACharge)} patients'),
        KpiSigh(
            libelle: 'Valorisation des stocks',
            valeur: money(b.stocks),
            icone: LucideIcons.package,
            ton: TonSigh.info,
            indice: 'méthode en vigueur : prix de vente'),
        KpiSigh(
            libelle: 'Dettes fournisseurs',
            valeur: money(b.dettes),
            icone: LucideIcons.fileMinus2,
            ton: TonSigh.succes,
            indice: '${nombre(b.nbDettes)} facture(s) non réglée(s)'),
        KpiSigh(
            libelle: 'Besoin en fonds de roulement',
            valeur: money(b.bfr),
            icone: LucideIcons.scale,
            ton: b.bfr > 0 ? TonSigh.danger : TonSigh.succes,
            indice: b.bfrJours != null ? '${nombre(b.bfrJours)} jours de chiffre d’affaires' : 'CA nul sur la période'),
      ]),
      const SizedBox(height: 16),
      b.bfr > 0
          ? NoteSigh(
              '${money(b.bfr)} que la clinique finance sur sa propre trésorerie : elle a payé ses fournisseurs et constitué son stock avant d’être réglée par ses clients et par les compagnies. C’est ce montant qu’un découvert ou un fonds de roulement doit couvrir.',
              ton: TonSigh.attention,
              icone: LucideIcons.wallet)
          : const NoteSigh(
              'Le cycle d’exploitation dégage de la trésorerie : les dettes fournisseurs financent à elles seules les créances et le stock. C’est une situation favorable, et rare.',
              ton: TonSigh.succes,
              icone: LucideIcons.wallet),
      const SizedBox(height: 16),
      deuxCartes(
        CarteSigh(
            titre: 'Composition du besoin',
            child: GraphiqueAnneau(
                etiquettes: const ['Créances assureurs', 'Restes à charge patients', 'Stocks'],
                valeurs: [b.creancesAssureurs, b.restesACharge, b.stocks],
                hauteur: 240)),
        CarteSigh(
            titre: 'Ce que le cycle finance',
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Composante', (r) => '${r['quoi']}'),
              ColonneMini('Registre d’origine', (r) => '${r['ou']}'),
              ColonneMini('Montant', (r) => m(r['montant']), droite: true),
            ], lignes: cpcLignesBfr(b))),
      ),
      const SizedBox(height: 16),
      // LES TROIS SOURCES SONT OUVRABLES : un agrégat qu'on ne peut pas redescendre est un agrégat qu'on ne vérifie jamais.
      CarteSigh(
          titre: 'Redescendre à la source',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in const [
              ('m9-creances', 'Ouvrir la balance âgée des créances', LucideIcons.hourglass),
              ('m6-point-stock', 'Ouvrir le point de stock', LucideIcons.package),
              ('m7-factures-fournisseurs', 'Ouvrir les factures fournisseurs', LucideIcons.fileText),
            ])
              BoutonSigh(
                  libelle: s.$2,
                  icone: s.$3,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => c.aller(s.$1)),
          ])),
      const SizedBox(height: 16),
      if (alertes.isNotEmpty)
        TableauSigh(
          titre: 'Créances au-delà de ${nombre(alertes.first.seuil)} jours — le levier le plus court',
          lignes: [
            for (final (i, a) in alertes.indexed)
              {'id': '$i', 'assureur': a.assureur, 'nb': a.nb, 'jours': a.jours, 'montant': a.montant}
          ],
          nomExport: 'creances-agees-bfr',
          taillePage: 10,
          triInitial: 'montant',
          sensInitial: 'desc',
          actions: [
            BoutonSigh(
                libelle: 'Ouvrir les relances',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.send,
                onPressed: () => c.aller('m9-relances')),
          ],
          colonnes: [
            ColonneTableau(cle: 'assureur', libelle: 'Compagnie', texte: (r) => nomCompagnie('${r['assureur']}')),
            const ColonneTableau(cle: 'nb', libelle: 'Factures', droite: true),
            ColonneTableau(
                cle: 'jours',
                libelle: 'Ancienneté maximale',
                droite: true,
                texte: (r) => '${r['jours']} j',
                rendu: (_, r) => Text('${r['jours']} jours',
                    style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
            ColonneTableau(
                cle: 'montant',
                libelle: 'Montant dû',
                droite: true,
                texte: (r) => m(r['montant']),
                rendu: (_, r) => Text(m(r['montant']),
                    style: const TextStyle(color: JetonsShell.navy900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700))),
          ],
        )
      else
        const VideSigh('Aucune créance au-delà du seuil retenu.', icone: LucideIcons.circleCheck),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([for (final k in ['factures', 'produits', 'facturesFournisseurs', 'objectifsPilotage', 'assureurs']) c.magasin.collection(k)]),
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CarteSigh(
            child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          commande(_date!, largeur: 220),
          commande(_periode!, largeur: 260),
          BoutonSigh(libelle: 'Imprimer l’état du BFR', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c)),
        ])),
        const SizedBox(height: 16),
        _vue(context, c),
      ]),
    );
  }
}
