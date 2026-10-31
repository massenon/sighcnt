import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';
import 'adm_commun.dart';

/// Les quatre écrans de M13 construits à la main (`U.dataTable` + `K.creer` + `K.actionsLigne` dans la maquette) : événements & notifications, plan annuel
/// de travail, notes de service, répertoire des ambulances.

const _signDa = Signature('La Directrice Administrative', nom: 'TAKI Alimatou');

const TextStyle _petit = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12);

/// Grille de cartes : trois colonnes dès 1024 px, deux dès 640 px, une en dessous (`sm:grid-cols-2 lg:grid-cols-3`), espace 12.
Widget _grille(List<Widget> cartes) => LayoutBuilder(builder: (_, c) {
      final n = c.maxWidth >= 1024 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
      final l = (c.maxWidth - 12 * (n - 1)) / n;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final k in cartes) SizedBox(width: l, child: k)]);
    });

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m13-evenements
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranEvenements extends StatefulWidget with EcranMaquette {
  const EcranEvenements({super.key});
  @override
  String get titre => 'Événements & notifications';
  @override
  String get description => 'Événements de la clinique et paramétrage des notifications adressées au personnel.';
  @override
  String get regle =>
      'Un événement inscrit ici est annoncé au personnel concerné : la notification sonore prévient le poste au moment voulu, sans que l’agent ait à surveiller l’écran.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(libelle: 'Réunions', icone: LucideIcons.usersRound, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m13-reunions')),
      BoutonSigh(libelle: 'Plan annuel', icone: LucideIcons.calendarRange, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m13-plan-annuel')),
    ];
  }

  @override
  State<EcranEvenements> createState() => _EcranEvenementsState();
}

class _EcranEvenementsState extends State<EcranEvenements> {
  bool _amorce = false;

  List<ChampDef> _champs(Magasin m) => [
        const ChampDef(nom: 'libelle', libelle: 'Intitulé de l’événement', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'categorie', libelle: 'Catégorie', type: TypeChamp.select, requis: true, options: admOptions(admCategoriesEvenement)),
        const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
        admChampHeure('heure', 'Heure'),
        const ChampDef(nom: 'lieu', libelle: 'Lieu', col: ColChamp.plein),
        ChampDef(nom: 'responsable', libelle: 'Responsable', type: TypeChamp.select, options: [
          for (final e in m.collection('personnel').actives) OptionChamp('${e['nomComplet']}')
        ]),
        const ChampDef(nom: 'notifier', libelle: 'Notifier le personnel', type: TypeChamp.case_),
        const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ];

  void _saisir(BuildContext ctx, ContexteEcran c, CollectionMagasin col, {Fiche? existante}) => admSaisir(ctx,
      col: col,
      champs: _champs(c.magasin),
      existante: existante,
      titreCreation: 'Nouvel événement de la clinique',
      entite: 'Événement',
      prefixeId: 'EVT',
      initiales: {'categorie': 'Santé publique', 'date': iso(c.aujourdhui), 'heure': '09:00', 'notifier': true},
      detailToast: (f) => '${f['libelle'] ?? ''}',
      fiche: (v, e) {
        v['heure'] = admHeure(v['heure']);
        if (e == null) {
          // Création : référence EVT-NNNN (le préfixe diffère de celui du jeu, E532 porté fidèlement) et canal « In-app » si l'événement est annoncé.
          v['reference'] = admReferenceEvenement(col.toutes.length);
          v['canaux'] = v['notifier'] == true ? ['In-app'] : <String>[];
        } else {
          // E532 : cocher « Notifier le personnel » pose un canal, le décocher les retire.
          v['canaux'] = admCanauxEvenement(v['notifier'], e['canaux']);
        }
        return admSansNuls(v);
      },
      apres: (_) => Future<void>.delayed(const Duration(milliseconds: 600), () {
            // `U.alerter(…, { son: 'information', type: 'success' })` : l'annonce suit le message de création.
            if (ctx.mounted) ToastsSigh.afficher(ctx, 'Événement inscrit au calendrier de la clinique.', type: TypeToast.succes);
          }));

  Widget _carte(Fiche e, DateTime now) {
    final j = admJoursAvant(now, e['date']);
    final canaux = e['canaux'] is List ? [for (final x in e['canaux'] as List) '$x'] : <String>[];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: JetonsShell.slate200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Flexible(child: BadgeSigh('${e['categorie'] ?? ''}', ton: TonSigh.navy)),
          const SizedBox(width: 8),
          Text(admDelaiEvenement(j),
              style: TextStyle(color: admDelaiUrgent(j) ? JetonsShell.danger600 : JetonsShell.slate400, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text('${e['libelle'] ?? ''}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('${dateJour(admDate(e['date'])!)} à ${e['heure'] ?? ''}', style: _petit),
        Text('${e['lieu'] ?? ''} — ${e['responsable'] ?? ''}', style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
        if (matVrai(e['notifier'])) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [for (final k in canaux) BadgeSigh(k, ton: TonSigh.info)]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('evenementsEtablissement');
    if (!_amorce) {
      _amorce = true;
      if (col.toutes.isEmpty) {
        final noms = [for (final p in c.magasin.collection('personnel').actives) '${p['nomComplet']}'];
        if (noms.isNotEmpty) {
          for (final f in admAmorcerEvenements(c.aujourdhui, noms).reversed) {
            col.inserer(f);
          }
        }
      }
    }
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final prochains = admProchainsEvenements(rows, c.aujourdhui);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            admLectureSeule(c),
            admKpis(admKpisEvenements(rows, c.aujourdhui)),
            const SizedBox(height: 16),
            if (prochains.isNotEmpty) ...[
              CarteSigh(titre: 'Prochains événements', child: _grille([for (final e in prochains) _carte(e, c.aujourdhui)])),
              const SizedBox(height: 16),
            ],
            TableauSigh(
              titre: 'Tous les événements',
              lignes: rows,
              taillePage: 15,
              nomExport: 'evenements',
              triInitial: 'date',
              sensInitial: 'desc',
              filtres: [FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: admOptions(admCategoriesPresentes(rows)))],
              actions: [
                if (c.droit.editer)
                  BoutonSigh(libelle: 'Nouveau', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _saisir(context, c, col)),
              ],
              actionsLigne: (ctx, f) => admActionsLigne(ctx, c, col, f, modifier: (x) => _saisir(ctx, c, col, existante: x)),
              colonnes: [
                ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
                const ColonneTableau(cle: 'libelle', libelle: 'Événement'),
                ColonneTableau(cle: 'categorie', libelle: 'Catégorie', rendu: (_, r) => BadgeSigh('${r['categorie'] ?? ''}', ton: TonSigh.navy)),
                ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => admDateFR(r['date'])),
                const ColonneTableau(cle: 'heure', libelle: 'Heure', sansCoupure: true),
                const ColonneTableau(cle: 'lieu', libelle: 'Lieu'),
                const ColonneTableau(cle: 'responsable', libelle: 'Responsable'),
                ColonneTableau(
                    cle: 'notifier',
                    libelle: 'Notification',
                    texte: (r) => matVrai(r['notifier']) ? [for (final k in (r['canaux'] as List? ?? const [])) '$k'].join(', ') : 'Aucune',
                    rendu: (_, r) => !matVrai(r['notifier'])
                        ? const Text('Aucune', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))
                        : Wrap(spacing: 4, runSpacing: 4, children: [for (final k in (r['canaux'] as List? ?? const [])) BadgeSigh('$k', ton: TonSigh.info)])),
              ],
            ),
            const SizedBox(height: 16),
            CarteSigh(
              titre: 'Paramétrage des notifications système',
              actions: [
                BoutonSigh(libelle: 'Modifier le paramétrage', icone: LucideIcons.settings, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => c.aller('cfg-notifications')),
              ],
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Événement déclencheur', (x) => '${x['n']}'),
                ColonneMini('Description', (x) => '${x['d']}'),
                ColonneMini('Canaux actifs', (x) => '', rendu: (x) => Wrap(spacing: 4, runSpacing: 4, children: [for (final k in (x['c'] as List)) BadgeSigh('$k', ton: TonSigh.succes)])),
              ], lignes: [
                for (final n in admNotificationsSysteme) {'n': n.$1, 'd': n.$2, 'c': n.$3}
              ]),
            ),
          ]);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m13-plan-annuel
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranPlanAnnuel extends StatefulWidget with EcranMaquette {
  const EcranPlanAnnuel({super.key});
  @override
  String get titre => 'Plan annuel de travail';
  @override
  String get description => 'Programmation annuelle des activités de la clinique, par axe et par trimestre.';

  @override
  State<EcranPlanAnnuel> createState() => _EcranPlanAnnuelState();
}

class _EcranPlanAnnuelState extends State<EcranPlanAnnuel> {
  bool _amorce = false;

  TonSigh _ton(Object? a) => matTon(admTonAvancement(a));

  void _imprimer(BuildContext ctx, ContexteEcran c, List<Fiche> rows) => matImprimer(ctx,
      titre: 'Plan annuel de travail',
      sousTitre: 'Exercice 2026',
      cartouche: [
        ('Exercice', '2026'),
        ('Actions programmées', nombre(rows.length)),
        ('Réalisées', nombre(rows.where((r) => r['avancement'] == 'Réalisée').length)),
        ('Date d’édition', dateFR(c.aujourdhui)),
      ],
      blocs: [
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'N°', valeur: (r) => r['reference']),
          ColonneEtat(libelle: 'Action', valeur: (r) => r['action']),
          ColonneEtat(libelle: 'Axe', valeur: (r) => r['axe']),
          ColonneEtat(libelle: 'Période', valeur: (r) => 'T${matTexteNombre(r['trimestreDebut'])} à T${matTexteNombre(r['trimestreFin'])}'),
          ColonneEtat(libelle: 'Responsable', valeur: (r) => r['responsable']),
          ColonneEtat(libelle: 'Avancement', valeur: (r) => r['avancement']),
        ], lignes: admTrierPlan(rows))),
      ],
      signatures: const [_signDa, Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko')]);

  Widget _gantt(List<Fiche> rows) {
    const entete = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600);
    Widget h(String t, {bool centre = false}) => Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), child: Align(alignment: centre ? Alignment.center : Alignment.centerLeft, child: Text(t, style: entete)));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 768),
        child: SizedBox(
          width: 768,
          child: Table(
            columnWidths: const {0: FlexColumnWidth(3.2), 1: FlexColumnWidth(1.6), 2: FlexColumnWidth(0.9), 3: FlexColumnWidth(0.9), 4: FlexColumnWidth(0.9), 5: FlexColumnWidth(0.9), 6: FlexColumnWidth(1.3)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: const TableBorder(horizontalInside: BorderSide(color: JetonsShell.slate100)),
            children: [
              TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
                h('Action'), h('Axe'), h('T1', centre: true), h('T2', centre: true), h('T3', centre: true), h('T4', centre: true), h('Avancement'),
              ]),
              for (final r in admTrierPlan(rows))
                TableRow(children: [
                  Padding(padding: const EdgeInsets.all(12), child: Text('${r['action'] ?? ''}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14))),
                  Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerLeft, child: BadgeSigh('${r['axe'] ?? ''}', ton: TonSigh.navy))),
                  for (var q = 1; q <= 4; q++)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                        child: Container(
                            key: Key('adm:barre:${r['reference']}:T$q'),
                            height: 12,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9999),
                                color: admTrimestreActif(r, q)
                                    ? switch (admTonAvancement(r['avancement'])) {
                                        'success' => JetonsShell.success400,
                                        'info' => JetonsShell.info400,
                                        _ => JetonsShell.warning400,
                                      }
                                    : JetonsShell.slate100))),
                  Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerLeft, child: BadgeSigh('${r['avancement'] ?? ''}', ton: _ton(r['avancement'])))),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('planAnnuel');
    if (!_amorce) {
      _amorce = true;
      if (col.toutes.isEmpty) {
        for (final f in admAmorcerPlan().reversed) {
          col.inserer(f);
        }
      }
    }
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            admLectureSeule(c),
            admKpis(admKpisPlan(rows)),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Plan annuel de travail 2026',
                sansRemplissage: true,
                actions: [BoutonSigh(libelle: 'Imprimer le plan', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimer(context, c, rows))],
                child: _gantt(rows)),
            const SizedBox(height: 16),
            TableauSigh(
              titre: 'Détail des actions',
              lignes: rows,
              taillePage: 15,
              nomExport: 'plan-annuel',
              filtres: [
                FiltreTableau(nom: 'axe', libelle: 'Axe', options: admOptions(({for (final r in rows) '${r['axe']}'}.toList()..sort()))),
                FiltreTableau(nom: 'avancement', libelle: 'Avancement', options: admOptions(admAvancementsPlan)),
              ],
              actionsLigne: (ctx, f) => admActionsLigne(ctx, c, col, f, modifier: (x) => _modifier(ctx, c, col, x)),
              colonnes: [
                ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
                const ColonneTableau(cle: 'action', libelle: 'Action'),
                ColonneTableau(cle: 'axe', libelle: 'Axe', rendu: (_, r) => BadgeSigh('${r['axe'] ?? ''}', ton: TonSigh.navy)),
                ColonneTableau(
                    cle: 'trimestreDebut',
                    libelle: 'Période',
                    droite: true,
                    texte: (r) => 'T${matTexteNombre(r['trimestreDebut'])} – T${matTexteNombre(r['trimestreFin'])}'),
                const ColonneTableau(cle: 'responsable', libelle: 'Responsable'),
                ColonneTableau(cle: 'avancement', libelle: 'Avancement', rendu: (_, r) => BadgeSigh('${r['avancement'] ?? ''}', ton: _ton(r['avancement']))),
              ],
            ),
          ]);
        });
  }

  void _modifier(BuildContext ctx, ContexteEcran c, CollectionMagasin col, Fiche existante) => admSaisir(ctx,
      col: col,
      existante: existante,
      titreCreation: 'Nouvelle action',
      entite: 'Action',
      // E533 : l'ÉTAT (Réalisée / En cours / Planifiée) et le POURCENTAGE sont deux champs — le pourcentage écrasait l'état.
      champs: [
        const ChampDef(nom: 'action', libelle: 'Action', requis: true, col: ColChamp.plein),
        const ChampDef(nom: 'responsable', libelle: 'Responsable'),
        const ChampDef(nom: 'echeance', libelle: 'Échéance', type: TypeChamp.date),
        ChampDef(nom: 'avancement', libelle: 'État d’avancement', type: TypeChamp.select, requis: true, options: admOptions(admAvancementsPlan)),
        const ChampDef(nom: 'tauxAvancement', libelle: 'Avancement (%)', type: TypeChamp.nombre),
        const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ],
      fiche: (v, e) {
        v['tauxAvancement'] = admNombre(v['tauxAvancement']);
        return v;
      });
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m13-notes-service
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranNotesService extends StatelessWidget with EcranMaquette {
  const EcranNotesService({super.key});
  @override
  String get titre => 'Notes de service';
  @override
  String get description => 'Notes de service en vigueur, versions et dates d’effet — sources des règles métier du système.';
  @override
  String get regle =>
      'Les notes de service ne sont pas de simples documents archivés : elles constituent les règles métier versionnées qui pilotent les moteurs d’évaluation (NS 131) et de primes (NS 132).';

  Widget _note(BuildContext context, AdmNoteService n, {required String moteur, required Widget table}) {
    final c = ContexteEcran.of(context);
    return Container(
      decoration: decorationCarte(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate100))),
            child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, spacing: 12, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(n.reference, style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(n.objet, style: _petit)),
              ]),
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                BadgeSigh('Version ${n.version}', ton: TonSigh.navy),
                BadgeSigh(n.statut, ton: TonSigh.succes),
                BoutonSigh(libelle: 'Ouvrir le moteur', icone: LucideIcons.arrowRight, taille: TailleBouton.sm, variante: VarianteBouton.fantome, onPressed: () => c.aller(moteur)),
              ]),
            ]),
          ),
          Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DescListeSigh([
                  ('Référence', n.reference),
                  ('Objet', n.objet),
                  ('Date de signature', admDateFR(n.dateSignature)),
                  ('Date d’effet', admDateFR(n.dateEffet)),
                  ('Signataire', n.signataire),
                  ('Statut', BadgeSigh(n.statut, ton: TonSigh.succes)),
                  ('Mention', n.mention),
                  ('Provenance', n.source),
                ]),
                const SizedBox(height: 12),
                table,
              ])),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final agents = c.magasin.collection('personnel').actives.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      admKpis(admKpisNotesService(agents)),
      const SizedBox(height: 16),
      _note(context, admNs131,
          moteur: 'm10-evaluations',
          table: MiniTableauSigh(colonnes: [
            ColonneMini('N°', (x) => '${x['num']}'),
            ColonneMini('Élément d’évaluation', (x) => '${x['label']}'),
            ColonneMini('Moyenne', (x) => '− ${x['moyenne']} %', droite: true),
            ColonneMini('Faible à mauvaise', (x) => '− ${x['faible']} %', droite: true),
          ], lignes: [
            for (final k in admCriteresNs131) {'num': k.numero, 'label': k.libelle, 'moyenne': k.moyenne, 'faible': k.faible}
          ])),
      const SizedBox(height: 16),
      _note(context, admNs132,
          moteur: 'm10-primes',
          table: MiniTableauSigh(colonnes: [
            ColonneMini('Prime', (x) => '${x['label']}'),
            ColonneMini('Mode', (x) => admModePrime('${x['mode']}')),
            ColonneMini('Fonctions concernées', (x) => '',
                rendu: (x) => Wrap(spacing: 4, runSpacing: 4, children: [for (final f in (x['fonctions'] as List)) BadgeSigh(admLibelleCourtFonction('$f'), ton: TonSigh.neutre)])),
          ], lignes: [
            for (final p in admPrimesNs132) {'label': p.libelle, 'mode': p.mode, 'fonctions': p.montants.keys.toList()}
          ])),
      const SizedBox(height: 16),
      const NoteSigh(
          'Une nouvelle note de service crée une nouvelle version de la règle, avec sa propre date d’effet. L’historique demeure intact : les paies et évaluations antérieures conservent le barème qui leur était applicable.',
          ton: TonSigh.info,
          icone: LucideIcons.history),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m13-repertoire-ambulances
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// On vient ici DANS UNE URGENCE : les disponibles remontent en tête, le numéro se lit en grand, la dernière vérification est datée, et JAMAIS un numéro
/// d'urgence n'est inventé — une structure dont le numéro n'est pas relevé a une fiche vide qui le dit.
class EcranRepertoireAmbulances extends StatefulWidget with EcranMaquette {
  const EcranRepertoireAmbulances({super.key});
  @override
  String get titre => 'Répertoire des ambulances';
  @override
  String get description => 'Numéros d’ambulance tenus à jour par l’accueil, avec appel rapide et disponibilité.';
  @override
  String get regle =>
      'On vient ici dans une urgence. Les ambulances disponibles remontent en tête, le numéro se lit d’un coup d’œil, et la date de dernière vérification est affichée : un répertoire d’urgence dont on ignore l’âge est un répertoire qu’on n’ose pas utiliser. Un numéro périmé est signalé, jamais masqué — un vieux numéro vaut mieux que rien.';

  @override
  State<EcranRepertoireAmbulances> createState() => _EcranRepertoireState();
}

class _EcranRepertoireState extends State<EcranRepertoireAmbulances> {
  bool _amorce = false;

  List<ChampDef> get _champs => [
        const ChampDef(nom: 'libelle', libelle: 'Désignation', requis: true),
        ChampDef(nom: 'type', libelle: 'Type', type: TypeChamp.select, requis: true, options: [for (final t in admTypesAmbulance) OptionChamp(t.code, t.libelle)]),
        // E535 : jamais obligatoire — « laisser la fiche à compléter », exiger un numéro forcerait à en inventer un.
        const ChampDef(nom: 'telephone', libelle: 'Téléphone', aide: 'Le numéro que l’accueil compose. Ne rien inventer : laisser la fiche à compléter.'),
        const ChampDef(nom: 'telephone2', libelle: 'Second numéro'),
        const ChampDef(nom: 'contact', libelle: 'Personne à demander'),
        const ChampDef(nom: 'base', libelle: 'Base ou localisation'),
        ChampDef(nom: 'disponibilite', libelle: 'Disponibilité', type: TypeChamp.select, requis: true, options: [for (final d in admDisponibilites) OptionChamp(d.code, d.libelle)]),
        const ChampDef(nom: 'capacite', libelle: 'Capacité et équipement', aide: 'Brancard, oxygène, accompagnant possible…'),
        const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2),
      ];

  void _saisir(BuildContext ctx, ContexteEcran c, CollectionMagasin col, {Fiche? existante}) => admSaisir(ctx,
      col: col,
      champs: _champs,
      existante: existante,
      titreCreation: 'Fiche ambulance',
      entite: 'Ambulance',
      prefixeId: 'AMB',
      detailToast: (f) => '${f['libelle'] ?? ''}',
      fiche: (v, e) => e == null ? admSansNuls(admFicheAmbulance(v, c.aujourdhui)) : v);

  void _verifier(BuildContext ctx, ContexteEcran c, CollectionMagasin col, Fiche r) {
    col.mettreAJour(r['id'], {'verifieLe': iso(c.aujourdhui), 'verifiePar': c.utilisateur});
    ToastsSigh.afficher(ctx, 'Numéro confirmé à jour.', type: TypeToast.succes, detail: '${r['libelle']}');
  }

  void _basculer(BuildContext ctx, CollectionMagasin col, Fiche r) {
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'disponibilite', libelle: 'Disponibilité', type: TypeChamp.select, requis: true, options: [for (final d in admDisponibilites) OptionChamp(d.code, d.libelle)]),
      const ChampDef(nom: 'observations', libelle: 'Précision'),
    ], {'disponibilite': r['disponibilite']});
    afficherModale<void>(ctx,
        titre: 'Disponibilité — ${r['libelle']}',
        taille: TailleModale.sm,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Appliquer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    col.mettreAJour(r['id'], v);
                    fermer();
                    ToastsSigh.afficher(ctx, 'Disponibilité mise à jour.', type: TypeToast.succes, detail: '${r['libelle']} — ${admDisponibilite(v['disponibilite']).libelle}');
                  }),
            ]);
  }

  void _detail(BuildContext ctx, Fiche x) {
    afficherTiroir<void>(ctx,
        titre: '${x['libelle']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Désignation', '${x['libelle'] ?? ''}'),
            ('Type', admTypeAmbulance(x['type']).libelle),
            ('Téléphone', matVrai(x['telephone']) ? '${x['telephone']}' : 'à renseigner'),
            ('Second numéro', matVrai(x['telephone2']) ? '${x['telephone2']}' : '—'),
            ('Personne à demander', matVrai(x['contact']) ? '${x['contact']}' : '—'),
            ('Base', matVrai(x['base']) ? '${x['base']}' : '—'),
            ('Disponibilité', admDisponibilite(x['disponibilite']).libelle),
            ('Capacité', matVrai(x['capacite']) ? '${x['capacite']}' : '—'),
            ('Vérifié le', matVrai(x['verifieLe']) ? admDateFR(x['verifieLe']) : 'jamais'),
            ('Origine de la fiche', matVrai(x['source']) ? '${x['source']}' : '—'),
          ]),
          if (matVrai(x['observations'])) ...[
            const SizedBox(height: 16),
            const Text('Observations', style: TextStyle(color: JetonsShell.slate900, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${x['observations']}', style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
          ],
          if (!matVrai(x['telephone'])) ...[
            const SizedBox(height: 16),
            NoteSigh('Le numéro de cette structure n’a pas été relevé. La fiche reste vide plutôt que de porter une valeur inventée.', ton: TonSigh.attention, icone: LucideIcons.phoneOff),
          ],
        ]));
  }

  Widget _cartes(List<Fiche> rows, DateTime now) {
    final cartes = <Widget>[];
    for (final r in admOrdreAppelRapide(rows)) {
      final d = admDisponibilite(r['disponibilite']);
      final t = admTypeAmbulance(r['type']);
      final joignable = r['disponibilite'] == 'disponible' && matVrai(r['telephone']);
      final alerte = admAlerteVerification(r, now);
      cartes.add(Container(
        key: Key('adm:appel:${r['id']}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: joignable ? JetonsShell.success50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: joignable ? JetonsShell.success200 : JetonsShell.slate200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text('${r['libelle'] ?? ''}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            admBadge(d.libelle, d.ton),
          ]),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('${t.libelle}${matVrai(r['base']) ? ' — ${r['base']}' : ''}', style: _petit)),
          if (matVrai(r['telephone'])) ...[
            // Le numéro EN GRAND : à l'accueil, on compose sur un téléphone posé à côté — il doit se lire d'un coup d'œil, sans loupe.
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Tooltip(
                    message: admHrefTel(r['telephone']),
                    child: Text('${r['telephone']}',
                        style: const TextStyle(fontFamily: matPoliceMono, fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w700, color: JetonsShell.navy900)))),
            if (matVrai(r['telephone2']))
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Tooltip(
                      message: admHrefTel(r['telephone2']),
                      child: Text('${r['telephone2']}', style: const TextStyle(fontFamily: matPoliceMono, fontSize: 14, height: 20 / 14, color: JetonsShell.slate600)))),
          ] else
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Numéro à renseigner', style: TextStyle(color: JetonsShell.warning700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic))),
          if (matVrai(r['contact'])) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Demander : ${r['contact']}', style: _petit)),
          if (alerte != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(alerte, style: const TextStyle(color: JetonsShell.warning700, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500))),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(admNoteAppelRapide, ton: TonSigh.info, icone: LucideIcons.ambulance),
      const SizedBox(height: 12),
      _grille(cartes),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('ambulances');
    if (!_amorce) {
      _amorce = true;
      if (col.toutes.isEmpty) {
        final chauffeur = c.magasin.collection('personnel').actives.where((a) => a['fonction'] == 'chauffeur').firstOrNull;
        for (final f in admAmorcerRepertoire(c.aujourdhui, IdentiteClinique.telephones, chauffeur == null ? 'Chauffeur de garde' : '${chauffeur['nomComplet']}')) {
          col.inserer(f, prefixe: 'AMB');
        }
      }
    }
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final sansNumero = admNoteSansNumero(rows);
          final now = c.aujourdhui;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            admLectureSeule(c),
            admKpis(admKpisRepertoire(rows, now)),
            const SizedBox(height: 16),
            if (sansNumero != null) ...[
              NoteSigh(sansNumero, ton: TonSigh.attention, icone: LucideIcons.phoneOff),
              const SizedBox(height: 16),
            ],
            CarteSigh(titre: 'Appel rapide', child: _cartes(rows, now)),
            const SizedBox(height: 16),
            TableauSigh(
              lignes: admTrierRepertoire(rows),
              messageVide: 'Aucune ambulance répertoriée.',
              nomExport: 'ambulances',
              actions: [
                if (c.droit.editer)
                  BoutonSigh(libelle: 'Ajouter une ambulance', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _saisir(context, c, col)),
              ],
              colonnes: [
                const ColonneTableau(cle: 'libelle', libelle: 'Désignation'),
                ColonneTableau(cle: 'type', libelle: 'Type', texte: (r) => admTypeAmbulance(r['type']).libelle, rendu: (_, r) => admBadge(admTypeAmbulance(r['type']).libelle, admTypeAmbulance(r['type']).ton)),
                ColonneTableau(
                    cle: 'telephone',
                    libelle: 'Téléphone',
                    texte: (r) => matVrai(r['telephone']) ? '${r['telephone']}' : 'à renseigner',
                    rendu: (_, r) => !matVrai(r['telephone'])
                        ? const Text('à renseigner', style: TextStyle(color: JetonsShell.warning700, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic))
                        : Text('${r['telephone']}', style: const TextStyle(fontFamily: matPoliceMono, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800))),
                ColonneTableau(cle: 'contact', libelle: 'Demander', texte: (r) => matVrai(r['contact']) ? '${r['contact']}' : '—'),
                ColonneTableau(cle: 'base', libelle: 'Base', texte: (r) => matVrai(r['base']) ? '${r['base']}' : '—'),
                ColonneTableau(cle: 'disponibilite', libelle: 'Disponibilité', texte: (r) => admDisponibilite(r['disponibilite']).libelle, rendu: (_, r) => admBadge(admDisponibilite(r['disponibilite']).libelle, admDisponibilite(r['disponibilite']).ton)),
                ColonneTableau(
                    cle: 'verifieLe',
                    libelle: 'Vérifié le',
                    texte: (r) {
                      final j = admJoursDepuis(r['verifieLe'], now);
                      return j == null ? 'jamais' : '${admDateFR(r['verifieLe'])} ($j j)';
                    },
                    rendu: (_, r) {
                      final j = admJoursDepuis(r['verifieLe'], now);
                      if (j == null) return const Text('jamais', style: TextStyle(color: JetonsShell.warning700, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic));
                      return Text('${admDateFR(r['verifieLe'])} ($j j)',
                          style: TextStyle(color: j > admJoursVerification ? JetonsShell.warning700 : JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: j > admJoursVerification ? FontWeight.w500 : FontWeight.w400));
                    }),
              ],
              actionsLigne: (ctx, f) => admActionsLigne(ctx, c, col, f,
                  modifier: (x) => _saisir(ctx, c, col, existante: x),
                  avant: [
                    if (c.droit.editer) ...[
                      BoutonIcone(icone: LucideIcons.circleCheck, libelle: 'Confirmer que ce numéro est à jour', onPressed: () => _verifier(ctx, c, col, f)),
                      BoutonIcone(icone: LucideIcons.repeat, libelle: 'Changer la disponibilité', onPressed: () => _basculer(ctx, col, f)),
                    ],
                    BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _detail(ctx, f)),
                  ]),
            ),
          ]);
        });
  }
}
