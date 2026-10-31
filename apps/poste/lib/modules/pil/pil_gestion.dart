import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pil_commun.dart';

/// Le pilotage de GESTION : m10-cout-agent (coût global d'un agent), m12-rentabilite-groupes (recettes et charges par groupe) et m12-tableau-decisionnel
/// (la grille objectif fixé / réel atteint). Les règles vivent dans `pilotage/pil_stats.dart` et `pil_tableaux.dart` du domaine, rejouées sur les vecteurs
/// des écrans réels de la maquette.

// =====================================================================================================================================================
// m10-cout-agent
// =====================================================================================================================================================

/// `m10-cout-agent` — « Coût global de l'agent » : DEUX colonnes à ne JAMAIS additionner — le coût employeur (brut + CNSS patronale 16,4 % + VPS 4 %) et les
/// retenues de l'agent (CNSS ouvrière 3,6 %, ORTB), qui sortent de SON salaire, pas de la caisse de la clinique. L'ITS, progressif, se lit sur le bulletin :
/// le recalculer ici créerait une seconde vérité. Cet écran LIT, il ne génère pas la paie (M11).
class EcranCoutAgent extends StatefulWidget with EcranMaquette {
  const EcranCoutAgent({super.key});

  @override
  String get titre => 'Coût global de l’agent';

  @override
  String get description => 'Ce que coûte un agent à l’établissement — salaire et charges patronales — et l’historique de ses paies.';

  @override
  String get regle =>
      'Deux colonnes à ne jamais additionner : le coût employeur (brut + CNSS patronale 16,4 % + VPS 4 %) et les retenues de l’agent (CNSS ouvrière 3,6 %, ORTB), qui sortent de SON salaire, pas de la caisse de la clinique. L’ITS, progressif, se lit sur le bulletin — le recalculer ici créerait une seconde vérité.';

  @override
  State<EcranCoutAgent> createState() => _EtatCoutAgent();
}

class _EtatCoutAgent extends State<EcranCoutAgent> {
  ControleurFormulaire? _f;

  @override
  void dispose() {
    _f?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final agents = trierPar(pilActives(c, 'personnel'), (a) => a['nomComplet']);
    _f ??= ControleurFormulaire([
      ChampDef(nom: 'agent', libelle: 'Agent', type: TypeChamp.select, recherche: true, options: [
        const OptionChamp('', '— Choisir un agent —'),
        for (final a in agents) OptionChamp('${a['id']}', '${a['nomComplet']} — ${a['poste'] ?? ''}'),
      ]),
      const ChampDef(nom: 'du', libelle: 'Paies du', type: TypeChamp.date),
      const ChampDef(nom: 'au', libelle: 'au', type: TypeChamp.date),
    ]);
    final f = _f!;
    return ListenableBuilder(
      listenable: Listenable.merge([pilEcoute(c, ['personnel', 'bulletins', 'avances']), f]),
      builder: (context, _) {
        Fiche? a;
        for (final x in agents) {
          if ('${x['id']}' == '${f['agent']}') a = x;
        }
        return pilPile([
          CarteSigh(
              child: LayoutBuilder(builder: (_, k) {
            final large = k.maxWidth >= 640;
            return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
              SizedBox(width: large ? (k.maxWidth - 24 - 24) * 0.5 : k.maxWidth, child: PilChamp(f, 'agent')),
              SizedBox(width: 200, child: PilChamp(f, 'du')),
              SizedBox(width: 200, child: PilChamp(f, 'au')),
            ]);
          })),
          if (a == null)
            const CarteSigh(child: VideSigh('Choisir un agent pour lire son coût global et l’historique de ses paies.', icone: LucideIcons.user))
          else
            ..._corps(c, a, pilBorne(f, 'du'), pilBorne(f, 'au')),
        ]);
      },
    );
  }

  List<Widget> _corps(ContexteEcran c, Fiche a, String du, String au) {
    final r = pilCoutAgent(a, pilActives(c, 'bulletins'), du, au);
    final note = pilNoteAvances(pilActives(c, 'avances'), a);
    return [
      pilKpis(r.vue.kpis, const [LucideIcons.wallet, LucideIcons.building2, LucideIcons.calendar, LucideIcons.radio]),
      CarteSigh(titre: 'Composition mensuelle', sansRemplissage: true, child: pilMiniTable(r.vue.tables[0], aGauche: const [0, 1])),
      TableauSigh(
        titre: 'Historique des paies — ${a['nomComplet']}',
        taillePage: 12,
        nomExport: 'historique-paies',
        messageVide:
            'Aucun bulletin émis pour cet agent : la paie se génère à l’écran « Calcul de la paie » (M11). Cet écran LIT, il ne génère pas.',
        lignes: [for (final b in r.bulletins) {'periode': b.$1, 'brut': b.$2, 'net': b.$3}],
        colonnes: [
          const ColonneTableau(cle: 'periode', libelle: 'Période'),
          ColonneTableau(cle: 'brut', libelle: 'Brut', droite: true, texte: (l) => money(l['brut'], avecDevise: false)),
          ColonneTableau(cle: 'net', libelle: 'Net payé', droite: true, texte: (l) => money(l['net'], avecDevise: false)),
        ],
      ),
      if (note != null) pilNote(note, icone: LucideIcons.handCoins),
    ];
  }
}

// =====================================================================================================================================================
// m12-rentabilite-groupes
// =====================================================================================================================================================

/// `m12-rentabilite-groupes` — « Recettes & charges par groupe » : les recettes se lisent par groupe de prestation (lignes payables), les charges par centre
/// de coûts (écritures VALIDÉES de classe 6). Le rapprochement centre → groupe est ARRÊTÉ (01/09/2026), affiché centre par centre, contestable ligne à ligne.
/// Les charges TRANSVERSES (administration, entretien, ambulance) ne sont pas ventilées : les répartir exigerait une clé qu'aucun document ne donne.
class EcranRentabiliteGroupes extends StatefulWidget with EcranMaquette {
  const EcranRentabiliteGroupes({super.key});

  @override
  String get titre => 'Recettes & charges par groupe';

  @override
  String get description =>
      'Recettes par groupe de prestation, charges par centre de coûts, et le bénéfice brut par groupe — rapprochement arrêté.';

  @override
  String get regle =>
      'Les recettes se lisent par groupe de prestation (les catégories des lignes payables) ; les charges par centre de coûts (écritures VALIDÉES de classe 6). Le rapprochement centre → groupe a été ARRÊTÉ par la Direction le 01/09/2026 et s’affiche centre par centre, contestable ligne à ligne. Les charges transverses (administration, entretien, ambulance) ne sont pas ventilées : les répartir exigerait une clé qu’aucun document ne donne — le bénéfice brut se lit AVANT elles. Les deux colonnes viennent de DEUX registres : les recettes des lignes de facture (M8), les charges du journal (M12). Ils ne se calibrent pas l’un sur l’autre, et le jeu de démonstration en porte la marque — c’est la RÉPARTITION entre groupes qui s’y lit, pas le résultat de l’exercice, qui se lit au compte de résultat.';

  @override
  State<EcranRentabiliteGroupes> createState() => _EtatRentabilite();
}

class _EtatRentabilite extends State<EcranRentabiliteGroupes> {
  final ControleurFormulaire _f = pilControleurPlage();

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([pilEcoute(c, ['factures', 'ecritures', 'centresCouts', 'actes']), _f]),
      builder: (context, _) {
        final r = pilRentabilite(
            factures: pilActives(c, 'factures'),
            ecritures: pilActives(c, 'ecritures'),
            centresCouts: pilToutes(c, 'centresCouts'),
            secteurParCode: secteursDesActes(pilActives(c, 'actes')),
            du: pilBorne(_f, 'du'),
            au: pilBorne(_f, 'au'));
        final v = r.vue;
        return pilPile([
          pilBandeauPlage(_f),
          pilKpis(v.kpis, const [LucideIcons.receipt, LucideIcons.wallet, LucideIcons.scale, LucideIcons.fileQuestion]),
          pilCarteTable(v.tables[0], titre: 'Recettes par groupe de prestation'),
          pilCarteTable(v.tables[1],
              titre: 'Rapprochement ARRÊTÉ le 01/09/2026 — centre par centre, contestable ligne à ligne', vide: 'Aucune charge validée sur la période.'),
          CarteSigh(
              titre: 'Bénéfice brut par groupe — avant charges transverses',
              child: pilPile([
                pilMiniTable(v.tables[2]),
                pilNote(v.notes.first, icone: LucideIcons.scale),
              ])),
          pilSource('Lignes payables des factures et écritures validées du magasin.'),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// m12-tableau-decisionnel
// =====================================================================================================================================================

/// `m12-tableau-decisionnel` — « Tableau de bord décisionnel » : objectif fixé face au réel atteint, sur quatre axes (BFR_TABLEAU.txt §2.B). AUCUN OBJECTIF
/// N'EST DOCUMENTÉ : les huit cibles sont des PROPOSITIONS, marquées à valider ; corriger une cible l'ARRÊTE (la mention tombe, la date et l'auteur sont
/// portés). `sens` dit de quel côté se trouve la réussite. « Non calculable » n'est pas zéro.
class EcranTableauDecisionnel extends StatelessWidget with EcranMaquette {
  const EcranTableauDecisionnel({super.key});

  @override
  String get titre => 'Tableau de bord décisionnel';

  @override
  String get description =>
      'Objectif fixé face au réel atteint, sur quatre axes : trésorerie et BFR, activité clinique, logistique et pharmacie, performance administrative.';

  @override
  String get regle =>
      'Les cibles ne sont pas documentées : aucun document de cadrage n’en fixe. Elles sont proposées, marquées à valider et corrigeables à l’onglet « Objectifs & seuils ». Un indicateur dont la donnée manque affiche « non calculable » — jamais un zéro, qui se lirait comme un échec.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'Détail du BFR',
            icone: LucideIcons.scale,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('m12-bfr')),
        BoutonSigh(
            libelle: 'Coût à l’activité',
            icone: LucideIcons.calculator,
            variante: VarianteBouton.secondaire,
            onPressed: () => ContexteEcran.of(context).aller('m12-cout-activite')),
      ];

  @override
  Widget build(BuildContext context) => OngletsSigh(onglets: [
        OngletDef(id: 'grille', libelle: 'Grille objectif / réel', construire: (ctx) => const _GrilleObjectifReel()),
        OngletDef(id: 'objectifs', libelle: 'Objectifs & seuils', construire: (ctx) => const _ObjectifsSeuils()),
      ]);
}

const _registresPilotage = ['factures', 'produits', 'facturesFournisseurs', 'mouvements', 'admissions', 'facturesMere', 'objectifsPilotage', 'assureurs'];

List<PilIndicateur> _indicateurs(ContexteEcran c) => pilIndicateurs(
    factures: pilActives(c, 'factures'),
    produits: pilActives(c, 'produits'),
    facturesFournisseurs: pilActives(c, 'facturesFournisseurs'),
    mouvements: pilActives(c, 'mouvements'),
    admissions: pilActives(c, 'admissions'),
    facturesMere: pilActives(c, 'facturesMere'),
    objectifs: pilActives(c, 'objectifsPilotage'),
    auj: c.aujourdhui);

CpcBfr _bfr(ContexteEcran c) => cpcBfr(
    factures: pilActives(c, 'factures'),
    produits: pilActives(c, 'produits'),
    facturesFournisseurs: pilActives(c, 'facturesFournisseurs'),
    auj: c.aujourdhui);

class _GrilleObjectifReel extends StatelessWidget {
  const _GrilleObjectifReel();

  void _imprimer(BuildContext ctx, ContexteEcran c, List<PilIndicateur> ind, CpcBfr b) {
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Tableau de bord décisionnel',
          sousTitre: 'Objectif fixé / réel atteint — arrêté au ${dateFR(DateTime.parse(b.arrete))}',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Besoin en fonds de roulement', money(b.bfr)),
            ('En-cours clients', money(b.creances)),
            ('Stocks', money(b.stocks)),
            ('Dettes fournisseurs', money(b.dettes)),
            ('Objectifs en alerte', nombre(ind.where((x) => x.etat == 'alerte').length)),
            ('Cibles non arbitrées', nombre(ind.where((x) => x.aValider).length)),
          ],
          blocs: [
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Axe', valeur: (r) => pilLibelleAxe(r['axe'])),
              ColonneEtat(libelle: 'Indicateur', valeur: (r) => '${r['label']}'),
              ColonneEtat(libelle: 'Objectif', valeur: (r) => '${r['objectif']}', droite: true),
              ColonneEtat(libelle: 'Réel atteint', valeur: (r) => '${r['reel']}', droite: true),
              ColonneEtat(libelle: 'État', valeur: (r) => '${r['etat']}'),
            ], lignes: [
              for (final x in ind)
                {
                  'axe': x.axe,
                  'label': x.label,
                  'objectif': '${pilObjectifTexte(x)}${x.aValider ? ' (à valider)' : ''}',
                  'reel': pilValeurIndicateur(x),
                  'etat': pilLibelleEtat(x.etat),
                }
            ])),
          ],
          signatures: const [Signature('La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou'), Signature('La Direction')],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: pilEcoute(c, _registresPilotage),
      builder: (context, _) {
        final ind = _indicateurs(c);
        final b = _bfr(c);
        final aValider = ind.where((x) => x.aValider).length;
        final k = pilCompteGrille(ind);
        final alertes = cpcAlertesRecouvrement(factures: pilActives(c, 'factures'), objectifs: pilActives(c, 'objectifsPilotage'), auj: c.aujourdhui);
        final noms = {for (final a in pilActives(c, 'assureurs')) '${a['code']}': '${a['nom']}'};
        return pilPile([
          if (aValider > 0)
            pilNote(
                '$aValider cible(s) en attente d’arbitrage de la Direction. Aucun document de cadrage ne fixe d’objectif de DSO, de taux d’occupation ou de rotation : les valeurs affichées sont des propositions. L’onglet « Objectifs & seuils » les corrige.',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert),
          pilKpis([
            PilKpi('Objectifs atteints', nombre(k.atteints), ton: 'succes'),
            PilKpi('Sous surveillance', nombre(k.vigilance), ton: 'attention'),
            PilKpi('Seuils franchis', nombre(k.alertes), ton: 'danger'),
            PilKpi('Non calculables', nombre(k.indisponibles), indice: k.indisponibles > 0 ? 'donnée manquante, jamais un zéro' : null),
          ], const [LucideIcons.checkCircle2, LucideIcons.eye, LucideIcons.siren, LucideIcons.circleHelp]),
          pilNote(
              'Besoin en fonds de roulement au ${dateFR(DateTime.parse(b.arrete))} : ${money(b.bfr)}${b.bfrJours != null ? ', soit ${nombre(b.bfrJours)} jours de chiffre d’affaires' : ''}.',
              icone: LucideIcons.scale),
          // UNE CARTE PAR AXE — la grille du document : quatre postes différents les lisent.
          for (final axe in pilAxesPilotage)
            if (ind.any((x) => x.axe == axe.$1))
              CarteSigh(
                  titre: axe.$2,
                  sansRemplissage: true,
                  child: MiniTableauSigh(lignes: [
                    for (final x in ind.where((x) => x.axe == axe.$1)) {'x': x}
                  ], colonnes: [
                    ColonneMini('Indicateur', (r) => '', rendu: (r) {
                      final x = r['x'] as PilIndicateur;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.label, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                        if (x.aide != null) Text(x.aide!, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                      ]);
                    }),
                    ColonneMini('Objectif', (r) => '', droite: true, rendu: (r) {
                      final x = r['x'] as PilIndicateur;
                      return Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(pilObjectifTexte(x), style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
                        if (x.aValider)
                          const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text('À VALIDER', style: TextStyle(color: JetonsShell.warning600, fontSize: 10, height: 1.3))),
                      ]);
                    }),
                    ColonneMini('Réel atteint', (r) => '', droite: true, rendu: (r) {
                      final x = r['x'] as PilIndicateur;
                      return Text(pilValeurIndicateur(x),
                          style: TextStyle(color: x.reel == null ? JetonsShell.slate400 : JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600));
                    }),
                    ColonneMini('Écart', (r) => '', droite: true, rendu: (r) {
                      final x = r['x'] as PilIndicateur;
                      if (x.ecart == null) return const Text('—');
                      return Text(pilEcartTexte(x),
                          style: TextStyle(color: x.ecart! >= 0 ? JetonsShell.success600 : JetonsShell.danger600, fontSize: 14, height: 20 / 14));
                    }),
                    ColonneMini('État', (r) => '', rendu: (r) {
                      final x = r['x'] as PilIndicateur;
                      return BadgeSigh(pilLibelleEtat(x.etat), ton: pilTon(pilTonIndicateur(x.etat)));
                    }),
                  ])),
          if (alertes.isNotEmpty)
            TableauSigh(
              titre: 'Compagnies au-delà du seuil d’ancienneté',
              taillePage: 8,
              nomExport: 'alertes-recouvrement',
              triInitial: 'montant',
              sensInitial: 'desc',
              lignes: [for (final a in alertes) {'assureur': noms[a.assureur] ?? a.assureur, 'nb': a.nb, 'jours': a.jours, 'montant': a.montant}],
              colonnes: [
                const ColonneTableau(cle: 'assureur', libelle: 'Compagnie'),
                const ColonneTableau(cle: 'nb', libelle: 'Factures', droite: true),
                ColonneTableau(
                    cle: 'jours',
                    libelle: 'Ancienneté max.',
                    droite: true,
                    texte: (r) => '${r['jours']} j',
                    rendu: (_, r) => Text('${r['jours']} j',
                        style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
                ColonneTableau(cle: 'montant', libelle: 'Montant dû', droite: true, texte: (r) => money(r['montant'], avecDevise: false)),
              ],
              actions: [
                BoutonSigh(
                    libelle: 'Ouvrir les relances',
                    icone: LucideIcons.send,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => c.aller('m9-relances')),
              ],
            ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            BoutonSigh(key: const Key('pil:imprimer-grille'), libelle: 'Imprimer la grille', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c, ind, b)),
          ]),
        ]);
      },
    );
  }
}

/// LES OBJECTIFS SE CORRIGENT ICI, ET NULLE PART AILLEURS. Ils vivent au magasin (collection `objectifsPilotage`) : les écrire dans le code aurait obligé la
/// Direction à demander une livraison pour changer un seuil de relance. La commande de correction est ABSENTE sans le droit d'éditer (RG-13).
class _ObjectifsSeuils extends StatelessWidget {
  const _ObjectifsSeuils();

  void _consulter(BuildContext ctx, Fiche r) => afficherTiroir<void>(ctx,
      titre: '${r['label']}',
      sousTitre: 'Objectif de pilotage',
      corps: Padding(
          padding: const EdgeInsets.all(20),
          child: pilPile([
            DescListeSigh([
              ('Axe', pilLibelleAxe(r['axe'])),
              ('Objectif', '${nombre(r['cible'])} ${r['unite']}'),
              ('Seuil d’alerte', '${nombre(r['alerte'])} ${r['unite']}'),
              ('Réussite', r['sens'] == 'haut' ? 'valeur la plus haute' : 'valeur la plus basse'),
              ('Statut', pilVrai(r['aValider']) ? 'Proposition — non arbitrée' : 'Arrêté le ${r['arreteLe'] != null ? dateFR(DateTime.parse('${r['arreteLe']}')) : '—'}'),
            ]),
            if (r['source'] != null)
              pilNote('Origine de la valeur proposée : ${r['source']}',
                  ton: pilVrai(r['aValider']) ? TonSigh.attention : TonSigh.neutre, icone: LucideIcons.fileSearch),
          ])));

  Future<void> _modifier(BuildContext ecran, ContexteEcran c, Fiche r) => afficherModale<void>(ecran,
      titre: 'Modifier — ${r['label']}',
      corps: _ModaleObjectif(contexte: c, ecran: ecran, objectif: r),
      pied: null);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('objectifsPilotage');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) => pilPile([
        pilNote(
            'Une cible corrigée ici est arrêtée par la Direction : la mention « à valider » tombe d’elle-même. Le sens dit de quel côté se trouve la réussite — un DSO se veut bas, un taux d’occupation haut ; sans lui, la grille colorerait en rouge un indicateur excellent.',
            icone: LucideIcons.target),
        TableauSigh(
          titre: 'Objectifs et seuils d’alerte',
          taillePage: 12,
          nomExport: 'objectifs-pilotage',
          lignes: col.actives.toList(),
          alClicLigne: (r) => _consulter(context, r),
          colonnes: [
            ColonneTableau(cle: 'axe', libelle: 'Axe', texte: (r) => pilLibelleAxe(r['axe'])),
            const ColonneTableau(cle: 'label', libelle: 'Indicateur'),
            ColonneTableau(cle: 'cible', libelle: 'Objectif', droite: true, texte: (r) => '${nombre(r['cible'])} ${r['unite']}'),
            ColonneTableau(
                cle: 'alerte',
                libelle: 'Seuil d’alerte',
                droite: true,
                texte: (r) => '${nombre(r['alerte'])} ${r['unite']}',
                rendu: (_, r) =>
                    Text('${nombre(r['alerte'])} ${r['unite']}', style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, height: 20 / 14))),
            ColonneTableau(
                cle: 'sens',
                libelle: 'Réussite',
                texte: (r) => r['sens'] == 'haut' ? 'Le plus haut possible' : 'Le plus bas possible',
                rendu: (_, r) => BadgeSigh(r['sens'] == 'haut' ? 'Le plus haut possible' : 'Le plus bas possible',
                    ton: r['sens'] == 'haut' ? TonSigh.info : TonSigh.navy)),
            ColonneTableau(
                cle: 'aValider',
                libelle: 'Statut',
                texte: (r) => pilVrai(r['aValider']) ? 'Proposition' : 'Arrêté par la Direction',
                rendu: (_, r) => pilVrai(r['aValider']) ? const BadgeSigh('Proposition', ton: TonSigh.attention) : const BadgeSigh('Arrêté par la Direction', ton: TonSigh.succes)),
          ],
          actionsLigne: (ctx, r) => [
            BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _consulter(ctx, r)),
            if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _modifier(context, c, r)),
            if (c.droit.annuler)
              BoutonIcone(
                  icone: LucideIcons.archive,
                  libelle: 'Archiver',
                  onPressed: () {
                    final annuler = col.archiver(r['id']);
                    ToastsSigh.afficher(context, 'Objectif archivé.', annuler: annuler, messageAnnulation: 'Archivage annulé.');
                  }),
          ],
        ),
      ]),
    );
  }
}

class _ModaleObjectif extends StatefulWidget {
  const _ModaleObjectif({required this.contexte, required this.ecran, required this.objectif});
  final ContexteEcran contexte;

  /// Le contexte de l'ÉCRAN : une modale vit au-dessus de la coque, hors du `ContexteEcran` — messages et enregistrements passent par lui.
  final BuildContext ecran;
  final Fiche objectif;
  @override
  State<_ModaleObjectif> createState() => _EtatModaleObjectif();
}

class _EtatModaleObjectif extends State<_ModaleObjectif> {
  late final ControleurFormulaire _f;

  @override
  void initState() {
    super.initState();
    final o = widget.objectif;
    _f = ControleurFormulaire([
      const ChampDef(nom: 'label', libelle: 'Indicateur', requis: true, col: ColChamp.plein),
      const ChampDef(nom: 'cible', libelle: 'Objectif', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'alerte', libelle: 'Seuil d’alerte', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'unite', libelle: 'Unité', type: TypeChamp.select, requis: true, options: [OptionChamp('jours'), OptionChamp('%'), OptionChamp('tours')]),
      const ChampDef(nom: 'sens', libelle: 'La réussite est…', type: TypeChamp.select, requis: true, options: [
        OptionChamp('bas', 'la valeur la plus BASSE'),
        OptionChamp('haut', 'la valeur la plus HAUTE'),
      ]),
      const ChampDef(nom: 'aide', libelle: 'Ce que mesure l’indicateur', col: ColChamp.plein),
    ], {
      'label': '${o['label'] ?? ''}',
      'cible': pilTexteNombre(pilN(o['cible'])),
      'alerte': pilTexteNombre(pilN(o['alerte'])),
      'unite': '${o['unite'] ?? 'jours'}',
      'sens': '${o['sens'] ?? 'bas'}',
      'aide': '${o['aide'] ?? ''}',
    });
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _enregistrer() {
    final v = _f.valider();
    if (v == null) return;
    final cible = num.tryParse('${v['cible']}'.replaceAll(',', '.')), alerte = num.tryParse('${v['alerte']}'.replaceAll(',', '.'));
    if (cible == null || alerte == null) {
      ToastsSigh.afficher(widget.ecran, 'L’objectif et le seuil d’alerte doivent être des nombres.', type: TypeToast.attention);
      return;
    }
    final c = widget.contexte;
    // Corriger une cible, c'est l'ARRÊTER : la Direction vient de la décider, la marque de proposition n'a plus lieu d'être.
    final patch = pilArreterObjectif({...v, 'cible': cible, 'alerte': alerte}, auj: c.aujourdhui, par: c.utilisateur);
    final annuler = c.magasin.collection('objectifsPilotage').mettreAJour(widget.objectif['id'], patch);
    Navigator.of(context).pop();
    ToastsSigh.afficher(widget.ecran, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Modification annulée.');
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormulaireSigh(controleur: _f),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          BoutonSigh(key: const Key('pil:enregistrer-objectif'), libelle: 'Enregistrer', onPressed: _enregistrer),
        ]),
      ]));
}
