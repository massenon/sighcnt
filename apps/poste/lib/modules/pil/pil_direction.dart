import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m5/cat_commun.dart' show collectionAnalyses;
import 'pil_commun.dart';

/// Les TABLEAUX de la Direction : dash-direction (pilotage stratégique), dash-admin (supervision technique), dash-da (« Statistiques de la Direction ») et
/// dash-croise (« Tableau de bord dynamique croisé »). Les règles vivent dans `pilotage/pil_tableaux.dart` du domaine, rejouées sur les vecteurs des écrans
/// réels de la maquette ; le BFR vient de `cpcBfr`, qui fait foi ici comme en M12 (une seule définition).

const _registresBfr = ['factures', 'produits', 'facturesFournisseurs', 'mouvements', 'admissions', 'facturesMere', 'objectifsPilotage'];

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// Briques partagées
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// Le « premier regard » : UNE question, son compte et le lien qui y mène, posé avant les accès rapides et les indicateurs. À zéro, il énonce une phrase
/// (« Rien ne vous attend » est une information).
class PilPremierRegard extends StatelessWidget {
  const PilPremierRegard(
      {super.key, required this.valeur, required this.unite, required this.question, required this.vide, required this.ton, required this.icone, required this.ecran, required this.lienLibelle, this.note});
  final num valeur;
  final String unite, question, vide, ecran, lienLibelle;
  final String? note;
  final TonSigh ton;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final vide0 = valeur == 0;
    return Container(
      key: const Key('pil:premier-regard'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: vide0 ? Colors.white : ton.fond50, borderRadius: BorderRadius.circular(12), border: Border.all(color: vide0 ? JetonsShell.slate200 : ton.bordure200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: vide0 ? JetonsShell.slate100 : ton.fond50, borderRadius: BorderRadius.circular(10)),
            child: Icon(icone, size: 22, color: vide0 ? JetonsShell.slate500 : ton.icone600)),
        const SizedBox(width: 16),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('À REGARDER EN PREMIER', style: TextStyle(color: JetonsShell.slate500, fontSize: 11, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          if (vide0)
            Text(vide, style: const TextStyle(color: JetonsShell.slate800, fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600))
          else
            Text('${nombre(valeur)} $unite — $question', style: const TextStyle(color: JetonsShell.slate900, fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600)),
          if (note != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
        ])),
        const SizedBox(width: 12),
        BoutonSigh(key: Key('pil:regard-lien:$ecran'), libelle: lienLibelle, icone: LucideIcons.arrowRight, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => c.aller(ecran)),
      ]),
    );
  }
}

/// Le widget BFR posé sur les deux tableaux de la Direction (`widgetBFR`) : il ne calcule rien — `cpcBfr` fait foi, ici comme en M12. Un composant non
/// amorcé SE DIT : un BFR amputé de ses dettes est surestimé.
class PilWidgetBfr extends StatelessWidget {
  const PilWidgetBfr({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: pilEcoute(c, _registresBfr),
      builder: (context, _) {
        final b = cpcBfr(
            factures: pilActives(c, 'factures'),
            produits: pilActives(c, 'produits'),
            facturesFournisseurs: pilActives(c, 'facturesFournisseurs'),
            auj: c.aujourdhui);
        final ind = pilIndicateurs(
            factures: pilActives(c, 'factures'),
            produits: pilActives(c, 'produits'),
            facturesFournisseurs: pilActives(c, 'facturesFournisseurs'),
            mouvements: pilActives(c, 'mouvements'),
            admissions: pilActives(c, 'admissions'),
            facturesMere: pilActives(c, 'facturesMere'),
            objectifs: pilActives(c, 'objectifsPilotage'),
            auj: c.aujourdhui);
        final enAlerte = ind.where((x) => x.etat == 'alerte').toList();
        final indispo = ind.where((x) => x.etat == 'indisponible').length;
        return CarteSigh(
            titre: 'Trésorerie & besoin en fonds de roulement',
            child: pilPile([
              pilKpis(pilKpisBfr(b), const [LucideIcons.scale, LucideIcons.handCoins, LucideIcons.package, LucideIcons.fileMinus2]),
              if (enAlerte.isNotEmpty)
                pilNote('${enAlerte.length} indicateur(s) au-delà du seuil d’alerte : ${enAlerte.map((x) => x.label).join(' · ')}.', ton: TonSigh.danger, icone: LucideIcons.siren)
              else if (indispo == 0)
                pilNote('Tous les indicateurs suivis sont en deçà de leur seuil d’alerte.', ton: TonSigh.succes, icone: LucideIcons.checkCircle2),
              if (b.incomplet.isNotEmpty)
                pilNote('Calcul incomplet — ${b.incomplet.join(' et ')} ne sont pas amorcés sur ce poste : le BFR affiché est surestimé.',
                    ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
              Wrap(spacing: 8, runSpacing: 8, children: [
                BoutonSigh(key: const Key('pil:tableau-decisionnel'), libelle: 'Tableau décisionnel', icone: LucideIcons.gauge, taille: TailleBouton.sm, onPressed: () => c.aller('m12-tableau-decisionnel')),
                BoutonSigh(key: const Key('pil:detail-bfr'), libelle: 'Détail du BFR', icone: LucideIcons.scale, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m12-bfr')),
              ]),
            ]));
      },
    );
  }
}

Widget _acces(ContexteEcran c, List<RaccourciDef> items) => SectionSigh(titre: 'Accès rapides', child: Padding(padding: const EdgeInsets.all(20), child: RaccourcisSigh(items: items, aller: c.aller)));

// =====================================================================================================================================================
// dash-direction
// =====================================================================================================================================================

/// `dash-direction` — « Tableau de bord — Direction » : indicateurs financiers, activité, stock et ressources humaines. Ce que la Direction regarde en premier
/// n'est pas un chiffre d'affaires : c'est ce qui BLOQUE — une échéance fiscale dépassée engage la clinique.
///
/// Écarts E1001 à E1002 (docs/architecture/ECARTS-MAQUETTE.md) : le libellé « undefined » d'un mode de paiement absent est porté fidèlement ; les variations
/// « +8,4 % vs mois dernier » des trois indicateurs de la maquette sont des constantes écrites en dur, pas des calculs : NON portées.
class EcranDirection extends StatelessWidget with EcranMaquette {
  const EcranDirection({super.key});

  @override
  String get titre => 'Tableau de bord — Direction';

  @override
  String get description => 'Pilotage stratégique : indicateurs financiers, activité, stock et ressources humaines en temps réel.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(key: const Key('pil:rapport-direction'), libelle: 'Éditer le rapport de direction', icone: LucideIcons.printer, onPressed: () => _rapport(context)),
      ];

  static PilDirection calculer(ContexteEcran c) => pilDirection(
      factures: pilActives(c, 'factures'),
      consultations: pilActives(c, 'consultations'),
      produits: pilActives(c, 'produits'),
      patients: pilActives(c, 'patients'),
      admissions: pilActives(c, 'admissions'),
      personnel: pilActives(c, 'personnel'),
      lots: pilActives(c, 'lots'),
      echeances: pilActives(c, 'echeancesFiscales'),
      facturesFournisseurs: pilActives(c, 'facturesFournisseurs'),
      mouvements: pilActives(c, 'mouvements'),
      facturesMere: pilActives(c, 'facturesMere'),
      objectifs: pilActives(c, 'objectifsPilotage'),
      auj: c.aujourdhui,
      libelleMode: _libelleMode,
      refMois: c.aujourdhui);

  static const _modes = {'especes': 'Espèces', 'tpe': 'TPE (carte bancaire)', 'mtn': 'MTN Mobile Money', 'moov': 'Moov Money', 'assurance': 'Prise en charge assurance'};

  /// `D.MODES_PAIEMENT` : un mode inconnu (ou absent) s'affiche tel quel — « undefined » pour une facture sans mode (E1001, porté fidèlement).
  static String _libelleMode(String k) => _modes[k] ?? k;

  static void _rapport(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final d = calculer(c);
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Rapport d’activité — Direction',
          sousTitre: 'Période : ${moisAnnee(c.aujourdhui)}',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Période', moisAnnee(c.aujourdhui)),
            ('Chiffre d’affaires', money(d.caMois)),
            ('Encaissé', money(d.encaisseMois)),
            ('Nombre de factures', nombre(d.nbFacturesMois)),
          ],
          blocs: [
            BlocTableau(TableauEtat(
                colonnes: [
                  ColonneEtat(libelle: 'Indicateur', valeur: (r) => '${r['k']}'),
                  ColonneEtat(libelle: 'Valeur', valeur: (r) => '${r['v']}', droite: true),
                ],
                lignes: [for (final l in d.lignesRapport) {'k': l.$1, 'v': l.$2}])),
          ],
          signatures: const [Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko'), Signature('La Directrice Administrative', nom: 'TAKI Alimatou')],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: pilEcoute(c, ['factures', 'consultations', 'produits', 'patients', 'admissions', 'personnel', 'lots', 'echeancesFiscales', ..._registresBfr]),
      builder: (context, _) {
        final d = calculer(c);
        final v = d.vue;
        Widget alerte(String texte, String ecran, IconData ic, TonSigh ton) => InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => c.aller(ecran),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: ton.fond50, borderRadius: BorderRadius.circular(8), border: Border.all(color: ton.bordure200)),
                child: Row(children: [
                  Icon(ic, size: 16, color: ton.icone600),
                  const SizedBox(width: 10),
                  Expanded(child: Text(texte, style: TextStyle(color: ton.texte900, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500))),
                  Icon(LucideIcons.arrowRight, size: 14, color: ton.icone600),
                ])));
        final alertes = [
          if (d.ruptures > 0) alerte('${d.ruptures} produit(s) sous le seuil d’alerte', 'm6-alertes', LucideIcons.trendingDown, TonSigh.danger),
          if (d.perimes > 0) alerte('${d.perimes} lot(s) périmé(s) à retourner', 'm6-lots', LucideIcons.octagonAlert, TonSigh.danger),
          if (d.peremptionProche > 0) alerte('${d.peremptionProche} lot(s) à péremption proche (FEFO)', 'm6-lots', LucideIcons.clock, TonSigh.attention),
        ];
        return pilPile([
          if (alertes.isNotEmpty)
            LayoutBuilder(builder: (_, k) {
              final n = k.maxWidth >= 640 ? 3 : 1;
              final l = (k.maxWidth - 8 * (n - 1)) / n;
              return Wrap(spacing: 8, runSpacing: 8, children: [for (final a in alertes) SizedBox(width: l, child: a)]);
            }),
          PilPremierRegard(
              valeur: d.echeancesDepassees,
              unite: 'échéance(s) fiscale(s) dépassée(s)',
              question: 'engagent la clinique',
              vide: 'Aucune échéance fiscale en retard.',
              ton: TonSigh.danger,
              icone: LucideIcons.siren,
              ecran: 'm12-echeances',
              lienLibelle: 'Voir les échéances',
              note: 'Une échéance dépassée engage la clinique, elle ne se rattrape pas — c’est ce qui prime sur le chiffre du jour.'),
          _acces(c, const [
            RaccourciDef(id: 'm12-etats-financiers', icone: LucideIcons.bookOpenCheck, libelle: 'États financiers', detail: 'Bilan, compte de résultat'),
            RaccourciDef(id: 'm11-validation', icone: LucideIcons.badgeCheck, libelle: 'Validation de la paie', detail: 'Soumise par les RH'),
            RaccourciDef(id: 'm7-commandes', icone: LucideIcons.truck, libelle: 'Commandes à valider', detail: 'RG-04 — validation DA'),
            RaccourciDef(id: 'm14-audit', icone: LucideIcons.scrollText, libelle: 'Journal d’audit', detail: 'Traçabilité des actions'),
          ]),
          pilKpis(v.kpis.take(8).toList(), const [
            LucideIcons.trendingUp,
            LucideIcons.wallet,
            LucideIcons.handCoins,
            LucideIcons.package,
            LucideIcons.users,
            LucideIcons.stethoscope,
            LucideIcons.bedDouble,
            LucideIcons.usersRound,
          ]),
          // Le BFR précède les graphiques : la Direction décide d'un financement avant de commenter une courbe.
          const PilWidgetBfr(),
          pilDeux(CarteSigh(titre: 'Évolution du chiffre d’affaires (12 mois)', child: pilGraphique(v.graphiques[0])),
              CarteSigh(titre: 'Recettes par activité', child: pilGraphique(v.graphiques[1]))),
          pilDeux(CarteSigh(titre: 'Activité — consultations et hospitalisations', child: pilGraphique(v.graphiques[2])),
              CarteSigh(titre: 'Répartition des modes de paiement', child: pilGraphique(v.graphiques[3]))),
          CarteSigh(titre: 'Performance par service (centre de coûts)', child: PilClassementSigh(v.classements.first.items, format: (x) => money(x))),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// dash-admin
// =====================================================================================================================================================

/// `dash-admin` — « Tableau de bord — Administration système » : comptes, sessions, journal d'audit, sauvegardes et intégrité des référentiels. L'administrateur
/// veille sur les accès : une tentative de connexion refusée est le signal qu'il voit en premier.
///
/// Écart E1003 : la maquette ÉCRIT « Dernière sauvegarde — Aujourd'hui, 02h00 automatique » (une constante, pas un état de sauvegarde). Porté fidèlement ;
/// l'état réel des sauvegardes se lit à `m14-sauvegardes`.
class EcranAdmin extends StatelessWidget with EcranMaquette {
  const EcranAdmin({super.key});

  @override
  String get titre => 'Tableau de bord — Administration système';

  @override
  String get description => 'Supervision technique : comptes, sessions, journal d’audit, sauvegardes et intégrité des référentiels.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: pilEcoute(c, ['personnel', 'audit', 'patients', 'produits', 'assureurs', 'analyses', 'tentativesConnexion']),
      builder: (context, _) {
        final audit = pilActives(c, 'audit');
        final v = pilAdmin(
            personnel: pilActives(c, 'personnel'),
            audit: audit,
            patients: pilActives(c, 'patients').length,
            produits: pilActives(c, 'produits').length,
            analyses: collectionAnalyses(c.magasin).actives.length,
            assureurs: pilActives(c, 'assureurs').length,
            comptes: cpaPlanEnFiches().length);
        final tentatives = pilActives(c, 'tentativesConnexion').length;
        return pilPile([
          PilPremierRegard(
              valeur: tentatives,
              unite: 'tentative(s) de connexion refusée(s)',
              question: 'à examiner',
              vide: 'Aucune tentative de connexion refusée.',
              ton: TonSigh.attention,
              icone: LucideIcons.shieldAlert,
              ecran: 'm14-roles',
              lienLibelle: 'Rôles & permissions',
              note: 'Un rôle archivé n’ouvre plus de session, et la tentative est écrite. Aucune action n’est anonyme (RG-12).'),
          _acces(c, const [
            RaccourciDef(id: 'm14-utilisateurs', icone: LucideIcons.userCog, libelle: 'Utilisateurs', detail: 'Comptes et habilitations'),
            RaccourciDef(id: 'm14-roles', icone: LucideIcons.keyRound, libelle: 'Rôles & permissions', detail: 'Matrice RBAC'),
            RaccourciDef(id: 'm14-sauvegardes', icone: LucideIcons.databaseBackup, libelle: 'Sauvegardes', detail: 'Quotidienne et hebdomadaire'),
            RaccourciDef(id: 'cfg-organisation', icone: LucideIcons.network, libelle: 'Configuration clinique', detail: 'Organigramme et référentiels'),
          ]),
          pilKpis(v.kpis, const [LucideIcons.usersRound, LucideIcons.scrollText, LucideIcons.shieldAlert, LucideIcons.databaseBackup]),
          SectionSigh(
              titre: 'Journal d’audit — dernières actions',
              actions: [lienVers('Tout consulter', () => c.aller('m14-audit'))],
              child: MiniTableauSigh(lignes: audit.take(12).toList(), colonnes: [
                ColonneMini('Horodatage', (a) {
                  final d = DateTime.tryParse('${a['dateHeure']}');
                  return d == null ? '—' : dateHeure(d);
                }),
                ColonneMini('Utilisateur', (a) => '${a['utilisateur'] ?? ''}'),
                ColonneMini('Action', (a) => '${a['action'] ?? ''}',
                    rendu: (a) => BadgeSigh('${a['action'] ?? ''}', ton: a['succes'] == false ? TonSigh.danger : TonSigh.navy)),
                ColonneMini('Module', (a) => '${a['module'] ?? ''}'),
                ColonneMini('Entité', (a) => '${a['entite'] ?? ''}'),
                ColonneMini('Poste', (a) => '${a['poste'] ?? ''}'),
              ])),
          pilDeux(CarteSigh(titre: 'Intégrité des référentiels', child: PilClassementSigh(v.classements.first.items)),
              CarteSigh(titre: 'Répartition des actions par module', child: pilGraphique(v.graphiques.first))),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// dash-da
// =====================================================================================================================================================

/// `dash-da` — « Statistiques de la Direction » : la caisse du jour, puis les cumuls journaliers, hebdomadaires, mensuels, trimestriels, semestriels et annuels.
/// Chaque périodicité affiche le total de sa période et sa VARIATION par rapport à la période précédente de même nature : c'est la comparaison qui informe.
/// UNE PÉRIODE SE NOMME : les bornes sont CALENDAIRES, la période se choisit. Le facturé et l'encaissé sont deux grandeurs distinctes.
class EcranDa extends StatefulWidget with EcranMaquette {
  const EcranDa({super.key});

  @override
  String get titre => 'Statistiques de la Direction';

  @override
  String get description => 'Caisse du jour et cumuls par périodicité : médicaments, actes, analyses, soins, par service.';

  @override
  String get regle =>
      'Chaque périodicité affiche le total de sa période et sa variation par rapport à la période précédente de même durée : c’est la comparaison qui informe, pas le nombre nu. Les montants sont ceux réellement encaissés, distingués du chiffre d’affaires facturé — confondre les deux ferait prendre une créance pour de la trésorerie.';

  @override
  State<EcranDa> createState() => _EtatDa();
}

class _EtatDa extends State<EcranDa> {
  final ControleurFormulaire _plage = ControleurFormulaire([
    const ChampDef(nom: 'du', libelle: 'Analyse libre — du', type: TypeChamp.date),
    const ChampDef(nom: 'au', libelle: 'au', type: TypeChamp.date),
  ]);

  /// L'ancre courante par périodicité : elle survit au changement d'onglet — revenir sur « Mois » après avoir choisi juin rouvre juin.
  final Map<String, DateTime> _ancres = {};

  @override
  void dispose() {
    _plage.dispose();
    super.dispose();
  }

  static const _mois = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

  /// Le choix de la période, une commande par nature de périodicité : une date pour un jour ou une semaine, une liste pour le mois, le trimestre, le semestre
  /// et l'année. L'ANNÉE COURANTE est le défaut.
  Widget _selecteur(ContexteEcran c, String code, String libelle, DateTime ancre) {
    final an = ancre.year, mois = ancre.month - 1;
    final ChampDef champ;
    String valeur;
    if (code == 'jour' || code == 'semaine') {
      champ = ChampDef(nom: 'p', libelle: code == 'jour' ? 'Jour analysé' : 'Une date de la semaine analysée', type: TypeChamp.date);
      valeur = iso(ancre);
    } else {
      List<OptionChamp> opts;
      if (code == 'mois') {
        opts = [for (var i = 0; i < 12; i++) OptionChamp('$i', '${_mois[i]} $an')];
        valeur = '$mois';
      } else if (code == 'trimestre') {
        opts = [for (var t = 0; t < 4; t++) OptionChamp('${t * 3}', 'T${t + 1} $an')];
        valeur = '${(mois ~/ 3) * 3}';
      } else if (code == 'semestre') {
        opts = [for (var x = 0; x < 2; x++) OptionChamp('${x * 6}', 'S${x + 1} $an')];
        valeur = mois < 6 ? '0' : '6';
      } else {
        final ici = c.aujourdhui.year;
        opts = [for (final y in [ici - 2, ici - 1, ici, ici + 1]) OptionChamp('$y', '$y')];
        valeur = '$an';
      }
      champ = ChampDef(nom: 'p', libelle: '$libelle analysé${code == 'annee' ? 'e' : ''}', type: TypeChamp.select, options: opts);
    }
    final ctrl = ControleurFormulaire([champ], {'p': valeur});
    ctrl.addListener(() {
      final v = '${ctrl['p']}';
      if (v.isEmpty) return;
      setState(() => _ancres[code] = switch (code) {
            'jour' || 'semaine' => DateTime.parse(v),
            'annee' => DateTime(int.parse(v), 0 + 1, 15),
            _ => DateTime(an, int.parse(v) + 1, 15),
          });
    });
    return CarteSigh(
        child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
      SizedBox(width: 220, child: FormulaireSigh(key: ValueKey('da:$code:$valeur'), controleur: ctrl)),
      const Text('L’année courante est retenue par défaut.', style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
    ]));
  }

  Widget _panneau(ContexteEcran c, String code, String libelle) {
    final ancre = _ancres[code] ?? c.aujourdhui;
    final p = pilPanneauDa(
        code: code,
        ancre: ancre,
        factures: pilActives(c, 'factures'),
        demandesAnalyses: pilActives(c, 'demandesAnalyses'),
        consultations: pilActives(c, 'consultations'));
    return pilPile([
      _selecteur(c, code, libelle, ancre),
      pilNote(p.note, icone: LucideIcons.calendarRange),
      TableauSigh(
        taillePage: 12,
        nomExport: 'statistiques-direction',
        lignes: [
          for (final l in p.lignes) {'grandeur': l.grandeur, 'valeur': l.courant, 'precedent': l.precedent, 'ligne': l}
        ],
        colonnes: [
          const ColonneTableau(cle: 'grandeur', libelle: 'Grandeur'),
          ColonneTableau(cle: 'valeur', libelle: 'Période courante', droite: true, texte: (r) => (r['ligne'] as PilLigneDa).texteCourant),
          ColonneTableau(
              cle: 'precedent',
              libelle: 'Période précédente',
              droite: true,
              texte: (r) => (r['ligne'] as PilLigneDa).textePrecedent,
              rendu: (_, r) => Text((r['ligne'] as PilLigneDa).textePrecedent, style: const TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14))),
          ColonneTableau(
              cle: 'variation',
              libelle: 'Variation',
              droite: true,
              triable: false,
              texte: (r) => (r['ligne'] as PilLigneDa).texteVariation,
              rendu: (_, r) {
                final l = r['ligne'] as PilLigneDa;
                if (l.variation == null) {
                  return const Text('pas de base de comparaison', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic));
                }
                final col = l.variation! > 0 ? JetonsShell.success700 : (l.variation! < 0 ? JetonsShell.danger700 : JetonsShell.slate500);
                return Text(l.texteVariation, style: TextStyle(color: col, fontSize: 14, height: 20 / 14, fontWeight: l.variation == 0 ? FontWeight.w400 : FontWeight.w600));
              }),
        ],
      ),
      CarteSigh(titre: p.repartition.titre, child: pilGraphique(p.repartition, hauteur: 220)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([pilEcoute(c, ['factures', 'demandesAnalyses', 'consultations', 'depenses', ..._registresBfr]), _plage]),
      builder: (context, _) {
        final fs = pilActives(c, 'factures');
        final jourIso = iso(c.aujourdhui);
        final jour = pilMesuresDa(
            factures: fs,
            demandesAnalyses: pilActives(c, 'demandesAnalyses'),
            consultations: pilActives(c, 'consultations'),
            filtre: (d) => pilJour(d) == jourIso);
        final du = pilBorne(_plage, 'du'), au = pilBorne(_plage, 'au');
        return pilPile([
          CarteSigh(
              child: Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 220, child: PilChamp(_plage, 'du')),
            SizedBox(width: 220, child: PilChamp(_plage, 'au')),
          ])),
          if (du.isNotEmpty || au.isNotEmpty)
            pilKpis(pilKpisPlageDa(fs, pilActives(c, 'depenses'), du, au), const [LucideIcons.receipt, LucideIcons.fileText, LucideIcons.coins, LucideIcons.wallet]),
          // La caisse du jour dit ce qui est RENTRÉ ; le BFR dit ce qu'il reste à financer. La DAF a besoin des deux, et dans cet ordre.
          const PilWidgetBfr(),
          PilPremierRegard(
              valeur: jour.encaisse,
              unite: 'FCFA encaissés aujourd’hui',
              question: 'sur ${nombre(jour.pieces)} pièce(s) émise(s)',
              vide: 'Aucun encaissement enregistré aujourd’hui.',
              ton: TonSigh.navy,
              icone: LucideIcons.banknote,
              ecran: 'm8-caisse',
              lienLibelle: 'Point de caisse',
              note: 'Activité 25 de la description de poste : « faire le point journalier de la caisse en l’absence de la DA ou à sa demande ».'),
          pilKpis(pilKpisCaisseDuJour(jour), const [LucideIcons.banknote, LucideIcons.receipt, LucideIcons.handCoins, LucideIcons.flaskConical]),
          pilNote(
              'Le facturé et l’encaissé sont deux grandeurs distinctes : la première est un chiffre d’affaires, la seconde de la trésorerie. Les confondre ferait prendre une créance pour de l’argent en caisse.',
              icone: LucideIcons.arrowLeftRight),
          OngletsSigh(onglets: [
            for (final p in pilPeriodicitesDa) OngletDef(id: p.$1, libelle: p.$2, construire: (ctx) => _panneau(c, p.$1, p.$2)),
          ]),
        ]);
      },
    );
  }
}

// =====================================================================================================================================================
// dash-croise
// =====================================================================================================================================================

/// `dash-croise` — « Tableau de bord dynamique croisé » : ce que le TDR reproche à l'existant, c'est de ne pas pouvoir CROISER automatiquement données
/// financières et données opérationnelles. Trois choix (une SOURCE, deux AXES, une MESURE), le reste se calcule. Les axes dépendent de la source (croiser des
/// grandeurs sans rapport donnerait un tableau vide qu'on croirait faux) ; la mesure est déclarée par la source (un effectif ne s'additionne pas avec un montant).
class EcranCroise extends StatefulWidget with EcranMaquette {
  const EcranCroise({super.key});

  @override
  String get titre => 'Tableau de bord dynamique croisé';

  @override
  String get description => 'Croiser librement soins, actes, analyses, stock, facturation, patients, personnel et gardes.';

  @override
  String get regle =>
      'Les tableaux de bord par profil répondent chacun à une question fixe ; celui-ci laisse poser la question. Les axes proposés dépendent de la source — croiser des grandeurs sans rapport donnerait un tableau vide qu’on croirait faux. La mesure est déclarée par la source : un effectif ne s’additionne pas avec un montant.';

  @override
  State<EcranCroise> createState() => _EtatCroise();
}

class _EtatCroise extends State<EcranCroise> {
  late String _source, _lignes, _mesure, _periode;
  String? _colonnes;
  late ControleurFormulaire _f;

  PilSource get _src => pilSourcesCroise.firstWhere((s) => s.code == _source);

  @override
  void initState() {
    super.initState();
    _source = pilSourcesCroise.first.code;
    _periode = 'mois';
    _defauts();
    _f = _creer();
  }

  void _defauts() {
    final axes = _src.axes.keys.toList();
    _lignes = axes[0];
    _colonnes = axes.length > 1 ? axes[1] : null;
    _mesure = _src.mesures.keys.first;
  }

  ControleurFormulaire _creer() {
    final axes = [for (final a in _src.axes.entries) OptionChamp(a.key, a.value.libelle)];
    final f = ControleurFormulaire([
      ChampDef(nom: 'source', libelle: 'Source', type: TypeChamp.select, options: [for (final s in pilSourcesCroise) OptionChamp(s.code, s.libelle)]),
      ChampDef(nom: 'lignes', libelle: 'Lignes', type: TypeChamp.select, options: axes),
      ChampDef(nom: 'colonnes', libelle: 'Colonnes', type: TypeChamp.select, options: [const OptionChamp('', '— aucun —'), ...axes]),
      ChampDef(nom: 'mesure', libelle: 'Mesure', type: TypeChamp.select, options: [for (final m in _src.mesures.entries) OptionChamp(m.key, m.value.libelle)]),
      ChampDef(nom: 'periode', libelle: 'Période', type: TypeChamp.select, options: [for (final p in pilPeriodesCroise) OptionChamp(p.$1, p.$2)]),
    ], {'source': _source, 'lignes': _lignes, 'colonnes': _colonnes ?? '', 'mesure': _mesure, 'periode': _periode});
    f.addListener(_surChangement);
    return f;
  }

  void _surChangement() {
    final f = _f;
    final s = '${f['source']}';
    if (s != _source) {
      _source = s;
      _defauts();
      final ancien = _f;
      _f = _creer();
      WidgetsBinding.instance.addPostFrameCallback((_) => ancien.dispose());
    } else {
      _lignes = '${f['lignes']}';
      _colonnes = '${f['colonnes']}'.isEmpty ? null : '${f['colonnes']}';
      _mesure = '${f['mesure']}';
      _periode = '${f['periode']}';
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  static const _icones = {
    'consultations': LucideIcons.stethoscope,
    'prescriptionsSoins': LucideIcons.handHeart,
    'analyses': LucideIcons.flaskConical,
    'mouvements': LucideIcons.package,
    'factures': LucideIcons.receipt,
    'patients': LucideIcons.users,
    'personnel': LucideIcons.usersRound,
    'actes': LucideIcons.clipboardList,
    'soinsExecutes': LucideIcons.syringe,
    'gardes': LucideIcons.calendarClock,
  };

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: pilEcoute(c, ['consultations', 'prescriptions', 'demandesAnalyses', 'mouvements', 'produits', 'factures', 'patients', 'personnel', 'actes', 'administrations', 'planning']),
      builder: (context, _) {
        final s = _src;
        final d = PilDonneesCroise(
            auj: c.aujourdhui,
            consultations: pilActives(c, 'consultations'),
            prescriptions: pilActives(c, 'prescriptions'),
            demandesAnalyses: pilActives(c, 'demandesAnalyses'),
            mouvements: pilActives(c, 'mouvements'),
            produits: pilActives(c, 'produits'),
            factures: pilActives(c, 'factures'),
            patients: pilActives(c, 'patients'),
            personnel: pilActives(c, 'personnel'),
            actes: pilActives(c, 'actes'),
            administrations: pilActives(c, 'administrations'),
            planning: pilActives(c, 'planning'));
        final r = pilCroiser(source: s, donnees: d, lignes: _lignes, colonnes: _colonnes, mesure: _mesure, periode: _periode);
        final libPeriode = pilPeriodesCroise.firstWhere((p) => p.$1 == _periode).$2;
        String fmt(num x) => r.mesure.unite == 'FCFA' ? money(x) : nombre(x);
        final kpis = [
          PilKpi('Source', s.libelle, ton: 'navy'),
          PilKpi('Enregistrements retenus', nombre(r.effectif), indice: libPeriode, ton: 'info'),
          PilKpi(r.mesure.libelle, pilTexteMesure(r.mesure, r.total), ton: 'succes'),
          PilKpi('Croisement', '${nombre(r.lignes.length)} × ${nombre(r.colonnes.length)}', indice: 'lignes × colonnes'),
        ];
        return pilPile([
          CarteSigh(
              titre: 'Construire le croisement',
              child: LayoutBuilder(builder: (_, k) {
                final n = k.maxWidth >= 1024 ? 5 : (k.maxWidth >= 640 ? 2 : 1);
                final l = (k.maxWidth - 12 * (n - 1)) / n;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final nom in const ['source', 'lignes', 'colonnes', 'mesure', 'periode']) SizedBox(width: l, child: PilChamp(_f, nom, key: ValueKey('${identityHashCode(_f)}:$nom'))),
                ]);
              })),
          pilKpis(kpis, [_icones[s.code] ?? LucideIcons.filter, LucideIcons.filter, LucideIcons.calculator, LucideIcons.grid3x3]),
          if (r.lignes.isEmpty)
            const CarteSigh(
                child: VideSigh('Aucune donnée sur la période choisie.',
                    indice: 'Élargir la période, ou changer d’axe — la source ne porte peut-être rien sur cet intervalle.', icone: LucideIcons.chartScatter))
          else ...[
            _tableau(s, r, fmt),
            CarteSigh(
                titre: 'Les douze premières valeurs — ${s.axes[_lignes]!.libelle}',
                child: GraphiqueBarres(
                    horizontal: true,
                    hauteur: math.max(240, math.min(12, r.lignes.length) * 26).toDouble(),
                    etiquettes: [for (final x in pilCroiseTop(r)) x.$1],
                    series: [SerieGraphique(r.mesure.libelle, [for (final x in pilCroiseTop(r)) x.$2])])),
          ],
        ]);
      },
    );
  }

  Widget _tableau(PilSource s, PilCroise r, String Function(num) fmt) {
    final lignes = <Fiche>[
      for (final l in pilCroiseOrdre(r))
        {'ligne': l, for (final col in r.colonnes) 'c_$col': r.table[l]![col] ?? 0, 'total': r.totalLigne(l)},
      // La ligne de total est CALCULÉE depuis les lignes affichées : un total transmis peut diverger de son tableau.
      {'ligne': 'TOTAL', for (final col in r.colonnes) 'c_$col': r.totauxColonnes[col] ?? 0, 'total': r.total},
    ];
    return TableauSigh(
      titre: '${r.mesure.libelle} — ${s.axes[_lignes]!.libelle}${_colonnes != null ? ' × ${s.axes[_colonnes]!.libelle}' : ''}',
      nomExport: 'croisement',
      lignes: lignes,
      colonnes: [
        ColonneTableau(cle: 'ligne', libelle: s.axes[_lignes]!.libelle),
        for (final col in r.colonnes)
          ColonneTableau(
              cle: 'c_$col',
              libelle: col,
              droite: true,
              texte: (l) => (l['c_$col'] as num) != 0 ? fmt(l['c_$col'] as num) : '—',
              rendu: (_, l) => (l['c_$col'] as num) != 0
                  ? Text(fmt(l['c_$col'] as num), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))
                  : const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 14, height: 20 / 14))),
        ColonneTableau(
            cle: 'total',
            libelle: 'Total',
            droite: true,
            texte: (l) => fmt(l['total'] as num),
            rendu: (_, l) => Text(fmt(l['total'] as num), style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
