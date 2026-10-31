import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';

const _jours = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];

/// Les fonctions dont la grille de la semaine affiche les agents.
const _fonctionsGrille = ['medecin', 'infirmier', 'sage_femme', 'aide_soignant', 'tsl', 'securite', 'entretien'];

/// Les vacations que les graphiques de charge comptent (gardes, soirées, permanences, incinération — ni l'entretien général ni le remplacement : la maquette
/// n'en retient que six, là où les statistiques de garde en comptent huit ; écart E666).
const _vacationsGraphiques = ['garde', 'garde_hospi', 'garde_soins', 'soiree', 'permanence', 'incineration'];

/// `m10-planning` — « Planning & gardes » : les régimes de travail par catégorie (administrables), la grille de la semaine où l'on affecte une vacation, et le
/// registre. Le contrôle d'incompatibilité EMPÊCHE de programmer une garde pendant le repos obligatoire qui suit la précédente.
class EcranPlanning extends StatelessWidget with EcranMaquette {
  const EcranPlanning({super.key});

  @override
  String get description => 'Planification des gardes, permanences et repos, avec contrôle des incompatibilités.';

  @override
  String get regle =>
      'Chaque catégorie applique son propre régime, relevé sur les plannings de la clinique : garde de 24 h (08h→08h), garde soins de 08h à 18h30, permanence de 08h à 18h, soirée de 18h à 8h, entretien général de la journée, repos de 24 h ou 48 h. Le système empêche de programmer une garde incompatible avec le repos obligatoire qui la suit.';

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['planning', 'regimesTravail', 'personnel'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final planning = rhbActives(c, 'planning');
    final auj = planning.where((p) => p['date'] == iso(c.aujourdhui)).toList();
    final debut = ajouterJours(c.aujourdhui, -3);
    final jours = [for (var i = 0; i < 7; i++) ajouterJours(debut, i)];
    final agents = trierPar([for (final e in rhbActives(c, 'personnel')) if (_fonctionsGrille.contains(e['fonction'])) e], (e) => e['nomComplet']);
    return rhbEspace([
      _Regimes(contexte: context),
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
          child: Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Légende :', style: TextStyle(color: JetonsShell.slate500, fontSize: 12, fontWeight: FontWeight.w500)),
            for (final t in rhbTypesPlanning)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: _ton(t.couleur).icone600)),
                const SizedBox(width: 6),
                Text('${t.court} — ${t.label}', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)),
              ]),
          ])),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Vacations planifiées', valeur: nombre(planning.length), icone: LucideIcons.calendarDays, ton: TonSigh.navy),
        KpiSigh(libelle: 'De garde aujourd’hui', valeur: nombre(auj.where((p) => p['type'] == 'garde').length), icone: LucideIcons.moon, ton: TonSigh.danger),
        KpiSigh(libelle: 'En permanence', valeur: nombre(auj.where((p) => p['type'] == 'permanence').length), icone: LucideIcons.sun, ton: TonSigh.attention),
        KpiSigh(libelle: 'En repos', valeur: nombre(auj.where((p) => '${p['type']}'.startsWith('repos')).length), icone: LucideIcons.bed, ton: TonSigh.info),
      ]),
      CarteSigh(
          titre: 'Planning du ${dateFR(jours.first)} au ${dateFR(jours.last)}',
          sansRemplissage: true,
          actions: [BoutonSigh(libelle: 'Imprimer le planning', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimer(context, c, agents, jours))],
          child: _Grille(agents: agents, jours: jours, contexte: context)),
      _Registre(contexte: context),
      ..._graphes(planning),
    ]);
  }

  static TonSigh _ton(String t) => rhbTon(t);

  List<Widget> _graphes(List<Fiche> planning) {
    final v = [for (final p in planning) if (_vacationsGraphiques.contains(p['type'])) p];
    final parAgent = rhbGrouper(v, (p) => '${p['employe']}');
    final agents = trierPar([for (final e in parAgent.entries) (e.key, e.value.length)], (x) => x.$2, descendant: true).take(10).toList();
    final parService = rhbGrouper(v, (p) => p['service'] == null || p['service'] == '' ? 'Non renseigné' : '${p['service']}');
    final parType = rhbGrouper(v, (p) => '${p['type']}');
    Widget vide() => const VideSigh('Aucune vacation enregistrée.', icone: LucideIcons.calendarX);
    return [
      rhbTroisCartes([
        CarteSigh(
            titre: 'Gardes par agent — les dix premiers',
            child: agents.isEmpty
                ? vide()
                : GraphiqueBarres(horizontal: true, hauteur: 260, etiquettes: [for (final a in agents) a.$1], series: [SerieGraphique('Vacations', [for (final a in agents) a.$2], couleur: rhbTonNavy)])),
        CarteSigh(
            titre: 'Gardes par service',
            child: parService.isEmpty ? vide() : GraphiqueAnneau(trou: 0, hauteur: 260, etiquettes: parService.keys.toList(), valeurs: [for (final l in parService.values) l.length])),
        CarteSigh(
            titre: 'Gardes par type de vacation',
            child: parType.isEmpty
                ? vide()
                : GraphiqueBarres(
                    hauteur: 260,
                    etiquettes: [for (final k in parType.keys) rhbTypePlanningLabel(k)],
                    series: [SerieGraphique('Vacations', [for (final l in parType.values) l.length], couleur: rhbTonBleu)])),
      ]),
      const NoteSigh(
          'Ces répartitions portent sur les vacations travaillées — gardes, soirées, permanences et incinération. Les repos et congés en sont exclus : les compter ferait apparaître comme les plus chargés les agents les plus reposés. Le détail par période se consulte à l’écran Statistiques de garde.'),
    ];
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, List<Fiche> agents, List<DateTime> jours) {
    final planning = rhbActives(c, 'planning');
    String nomJour(DateTime j) => '${_jours[j.weekday % 7].substring(0, 3)}. ${j.day}';
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Planning de garde et de permanence',
            sousTitre: 'Semaine du ${dateFR(jours.first)} au ${dateFR(jours.last)}',
            cartouche: [
              ('Période', '${dateFR(jours.first)} – ${dateFR(jours.last)}'),
              ('Agents concernés', nombre(agents.length)),
              ('Établi par', c.utilisateur),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Agent', valeur: (r) => r['agent']),
                ColonneEtat(libelle: 'Fonction', valeur: (r) => r['fonction']),
                for (final (i, j) in jours.indexed) ColonneEtat(libelle: nomJour(j), valeur: (r) => r['j$i']),
              ], lignes: [
                for (final e in agents)
                  {
                    'agent': e['nomComplet'],
                    'fonction': rhbFonctionLabel(e['fonction']),
                    for (final (i, j) in jours.indexed)
                      'j$i': () {
                        final v = planning.where((p) => p['employeId'] == e['id'] && p['date'] == iso(j)).firstOrNull;
                        return v != null ? rhbTypePlanningLabel(v['type']) : '';
                      }(),
                  }
              ])
            ],
            signatures: const [rhbSignSurveillant, rhbSignDaf, rhbSignDm]));
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// La grille de la semaine
// ---------------------------------------------------------------------------------------------------------------------

class _Grille extends StatelessWidget {
  const _Grille({required this.agents, required this.jours, required this.contexte});
  final List<Fiche> agents;
  final List<DateTime> jours;
  final BuildContext contexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final planning = rhbActives(c, 'planning');
    const tete = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 960),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {0: const FixedColumnWidth(220), for (var i = 1; i <= 7; i++) i: const FixedColumnWidth(106)},
          children: [
            TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50, border: Border(bottom: BorderSide(color: JetonsShell.slate200))), children: [
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text('AGENT', style: tete)),
              for (final j in jours)
                Container(
                    color: iso(j) == iso(c.aujourdhui) ? JetonsShell.navy50 : null,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    // « jeu.<br>13/08 » de la maquette : le libellé est UN seul texte (« jeu.13/08 »), que la colonne étroite replie sur deux lignes.
                    child: Center(
                        child: SizedBox(
                            width: 40,
                            child: Text('${_jours[j.weekday % 7].substring(0, 3)}.${j.day}/${j.month.toString().padLeft(2, '0')}'.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: tete.copyWith(color: iso(j) == iso(c.aujourdhui) ? JetonsShell.navy800 : JetonsShell.slate500))))),
            ]),
            for (final e in agents)
              TableRow(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate100))), children: [
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: rhbAgentCellule('${e['nomComplet']}', rhbFonctionLabel(e['fonction']))),
                for (final j in jours)
                  Padding(
                      padding: const EdgeInsets.all(4),
                      child: _Cellule(
                          contexte: contexte,
                          agent: e,
                          jour: j,
                          vacation: planning.where((p) => p['employeId'] == e['id'] && p['date'] == iso(j)).firstOrNull)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _Cellule extends StatelessWidget {
  const _Cellule({required this.contexte, required this.agent, required this.jour, required this.vacation});
  final BuildContext contexte;
  final Fiche agent;
  final DateTime jour;
  final Fiche? vacation;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final t = vacation != null ? rhbTypePlanningTon('${vacation!['type']}') : null;
    final fond = switch (t) { 'danger' => JetonsShell.danger100, 'warning' => JetonsShell.warning100, 'info' => JetonsShell.info100, 'navy' => JetonsShell.navy100, 'success' => JetonsShell.success100, 'neutral' => JetonsShell.slate100, _ => null };
    final texte = switch (t) { 'danger' => JetonsShell.danger800, 'warning' => JetonsShell.warning800, 'info' => JetonsShell.info800, 'navy' => JetonsShell.navy800, 'success' => JetonsShell.success800, 'neutral' => JetonsShell.slate800, _ => JetonsShell.slate300 };
    final libelle = vacation != null ? rhbTypePlanningLabel(vacation!['type']).replaceAll('Permanence', 'Perm.').replaceAll('Remplacement', 'Rempl.') : '+';
    final corps = Container(
        key: Key('rhb:cellule:${agent['id']}:${iso(jour)}'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(4)),
        child: Text(libelle, textAlign: TextAlign.center, style: TextStyle(color: texte, fontSize: 10, height: 1.4, fontWeight: FontWeight.w500)));
    // Sans le droit d'écrire, la case se LIT mais ne s'ouvre pas : une commande interdite est ABSENTE (écart E665).
    if (!c.droit.editer) return corps;
    return InkWell(borderRadius: BorderRadius.circular(4), onTap: () => affecter(contexte, c, agent, jour, vacation), child: corps);
  }
}

/// `affecter` : l'affectation d'une vacation à un agent, un jour donné. Les vacations proposées sont celles du régime de la catégorie ; une garde de 24 h est refusée
/// pendant le repos qui suit la précédente.
void affecter(BuildContext ctx, ContexteEcran c, Fiche e, DateTime jour, Fiche? existant) {
  final col = c.magasin.collection('planning');
  final regime = rhbRegimeDe(rhbActives(c, 'regimesTravail'), '${e['fonction']}');
  final autorises = rhbVacationsAutorisees(regime);
  final ctl = ControleurFormulaire([
    ChampDef(nom: 'type', libelle: 'Type de vacation', type: TypeChamp.select, requis: true, col: ColChamp.demi, options: [
      for (final t in rhbTypesPlanning)
        if (autorises.contains(t.id)) OptionChamp(t.id, rhbLibelleVacation(t))
    ]),
    const ChampDef(nom: 'observation', libelle: 'Observation', col: ColChamp.plein),
  ], existant != null ? {'type': existant['type'], 'observation': existant['observation']} : {'type': regime != null && regime.vacations.isNotEmpty ? regime.vacations.first : 'permanence'});
  afficherModale<void>(ctx,
      titre: 'Affectation de vacation',
      sousTitre: '${e['nomComplet']} — ${dateJour(jour)}',
      taille: TailleModale.md,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        DescListeSigh([
          ('Agent', e['nomComplet']),
          ('Fonction', rhbFonctionLabel(e['fonction'])),
          ('Date', dateJour(jour)),
          ('Vacation actuelle', existant != null ? rhbTypePlanningLabel(existant['type']) : 'Aucune'),
        ]),
        if (regime != null) ...[const SizedBox(height: 12), NoteSigh('${regime.libelle} — ${regime.mention}')],
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            if (existant != null)
              BoutonSigh(
                  libelle: 'Retirer',
                  icone: LucideIcons.trash2,
                  variante: VarianteBouton.danger,
                  onPressed: () {
                    final annuler = col.archiver(existant['id']);
                    fermer();
                    ToastsSigh.afficher(ctx, 'Vacation retirée.', type: TypeToast.succes, annuler: annuler);
                  }),
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Enregistrer',
                icone: LucideIcons.save,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) return;
                  final conflit = rhbIncompatibiliteGarde(rhbActives(c, 'planning'), employeId: e['id'], jour: jour, type: '${v['type']}', repos: regime?.repos);
                  if (conflit != null) {
                    ToastsSigh.afficher(ctx, 'Incompatibilité — le repos de ${regime?.repos == 'repos48' ? 48 : 24} h qui suit une garde n’est pas respecté.',
                        type: TypeToast.erreur, detail: 'Garde déjà programmée le ${dateFR(DateTime.parse(conflit))} pour ${e['nomComplet']}.');
                    return;
                  }
                  // La vacation porte le régime sous lequel elle a été posée : sans cette trace, une modification ultérieure du régime rendrait l'historique illisible.
                  final fiche = <String, Object?>{
                    ...v,
                    'date': iso(jour),
                    'employeId': e['id'],
                    'employe': e['nomComplet'],
                    'fonction': e['fonction'],
                    'service': e['service'],
                    'statut': 'validee',
                    'regimeLibelle': regime?.libelle,
                  };
                  fermer();
                  VoidCallback annuler;
                  if (existant != null) {
                    annuler = col.mettreAJour(existant['id'], fiche);
                  } else {
                    annuler = col.inserer(fiche, prefixe: 'PLN').annuler;
                  }
                  ToastsSigh.afficher(ctx, 'Vacation enregistrée.', type: TypeToast.succes, annuler: annuler);
                }),
          ]);
}

// ---------------------------------------------------------------------------------------------------------------------
// Le registre des vacations
// ---------------------------------------------------------------------------------------------------------------------

class _Registre extends StatelessWidget {
  const _Registre({required this.contexte});
  final BuildContext contexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final regimes = rhbActives(c, 'regimesTravail');
    String regimeDe(Fiche p) {
      final lib = p['regimeLibelle'];
      if (lib != null && lib != '') return '$lib';
      return rhbRegimeDe(regimes, '${p['fonction']}')?.libelle ?? '—';
    }

    return TableauSigh(
      titre: 'Registre des vacations',
      lignes: rhbActives(c, 'planning'),
      taillePage: 15,
      triInitial: 'date',
      sensInitial: 'desc',
      nomExport: 'planning',
      selectionnable: true,
      filtres: [
        FiltreTableau(nom: 'type', libelle: 'Type de vacation', options: [for (final t in rhbTypesPlanning) OptionChamp(t.id, t.label)]),
        FiltreTableau(nom: 'service', libelle: 'Service', options: [for (final s in rhbServices) OptionChamp(s)]),
      ],
      colonnes: [
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (p) => dateFR(DateTime.parse('${p['date']}')), rendu: (_, p) => Text(dateFR(DateTime.parse('${p['date']}')))),
        const ColonneTableau(cle: 'employe', libelle: 'Agent'),
        ColonneTableau(cle: 'fonction', libelle: 'Fonction', texte: (p) => rhbFonctionLabel(p['fonction']), rendu: (_, p) => Text(rhbFonctionLabel(p['fonction']))),
        const ColonneTableau(cle: 'service', libelle: 'Service'),
        ColonneTableau(cle: 'type', libelle: 'Vacation', texte: (p) => rhbTypePlanningLabel(p['type']), rendu: (_, p) => BadgeSigh(rhbTypePlanningLabel(p['type']), ton: rhbTon(rhbTypePlanningTon('${p['type']}')))),
        ColonneTableau(
            cle: 'regime',
            libelle: 'Régime appliqué',
            valeur: regimeDe,
            texte: regimeDe,
            rendu: (_, p) {
              final l = regimeDe(p);
              return l == '—' ? const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 12)) : Text(l, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12));
            }),
        ColonneTableau(cle: 'statut2', libelle: 'Statut', valeur: (p) => p['statut'], texte: (p) => 'Validée', rendu: (_, p) => statutBadge('validee')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Les régimes de travail par catégorie
// ---------------------------------------------------------------------------------------------------------------------

class _Regimes extends StatelessWidget {
  const _Regimes({required this.contexte});
  final BuildContext contexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final regimes = rhbActives(c, 'regimesTravail');
    return CarteSigh(
      titre: 'Régimes de travail par catégorie',
      sansRemplissage: true,
      actions: [
        if (c.droit.editer) BoutonSigh(libelle: 'Nouveau régime', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _editer(context, c, null)),
      ],
      child: MiniTableauSigh(colonnes: [
        ColonneMini('Catégorie', (r) => '${r['libelle']}'),
        ColonneMini('Vacations', (r) => '', rendu: (r) => Wrap(spacing: 4, runSpacing: 4, children: [
              for (final v in (r['vacations'] as List? ?? const [])) BadgeSigh(rhbTypePlanning(v)?.label ?? '$v', ton: rhbTon(rhbTypePlanningTon('$v')))
            ])),
        ColonneMini('Horaires', (r) => '', rendu: (r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final v in (r['vacations'] as List? ?? const []))
                Text(rhbTypePlanning(v) != null ? '${rhbTypePlanning(v)!.court} : ${rhbTypePlanning(v)!.debut} → ${rhbTypePlanning(v)!.fin}' : '$v', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
            ])),
        ColonneMini('Repos', (r) => '', rendu: (r) {
          final rp = r['repos'];
          if (rp == null || rp == '') return const Text('Sans repos codifié', style: TextStyle(color: JetonsShell.slate400, fontSize: 12));
          return BadgeSigh(rhbTypePlanning(rp)?.label ?? '$rp');
        }),
        ColonneMini('Honoraire', (r) => '', droite: true, rendu: (r) {
          final h = r['honoraire'];
          if (h == null || h == 0 || h == '') return const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 12));
          return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Text(money(h, avecDevise: false), style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, fontWeight: FontWeight.w600)),
            Text('${r['honorairePeriodicite'] == null || r['honorairePeriodicite'] == '' ? 'mensuelle' : r['honorairePeriodicite']}', style: rhbPetit),
          ]);
        }),
        ColonneMini('Cycle', (r) => '${r['cycle']} jours', droite: true),
        ColonneMini('Source', (r) => '', rendu: (r) => Text('${r['source']}', style: rhbPetit)),
        ColonneMini('', (r) => '', droite: true, rendu: (r) => Row(mainAxisSize: MainAxisSize.min, children: [
              if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier ce régime', onPressed: () => _editer(context, c, r)),
              if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver ce régime', onPressed: () => _archiver(context, c, r)),
            ])),
      ], lignes: regimes),
    );
  }

  void _editer(BuildContext ctx, ContexteEcran c, Fiche? regime) {
    final creation = regime == null;
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'libelle', libelle: 'Catégorie', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'fonctions', libelle: 'Fonctions concernées', type: TypeChamp.multiselect, requis: true, col: ColChamp.plein, options: [for (final f in rhbFonctions) OptionChamp(f.id, f.label)]),
      ChampDef(nom: 'vacations', libelle: 'Vacations du régime', type: TypeChamp.multiselect, requis: true, col: ColChamp.plein, options: [
        for (final t in rhbTypesPlanning)
          if (t.duree > 0) OptionChamp(t.id, '${t.label} (${t.debut} → ${t.fin})')
      ]),
      ChampDef(nom: 'repos', libelle: 'Repos appliqué', type: TypeChamp.select, options: [
        const OptionChamp('', 'Sans repos codifié'),
        for (final t in rhbTypesPlanning)
          if (t.id.startsWith('repos')) OptionChamp(t.id, t.label)
      ]),
      const ChampDef(nom: 'cycle', libelle: 'Cycle (jours)', type: TypeChamp.nombre, requis: true, valider: _cycleValide),
      const ChampDef(nom: 'honoraire', libelle: 'Honoraire (FCFA)', type: TypeChamp.nombre, aide: 'Laisser vide si le régime ne porte pas d’honoraire propre'),
      const ChampDef(nom: 'honorairePeriodicite', libelle: 'Périodicité de l’honoraire', type: TypeChamp.select, options: [OptionChamp('mensuelle', 'Mensuelle'), OptionChamp('occurrence', 'Par occurrence')]),
      const ChampDef(nom: 'source', libelle: 'Document source', requis: true, col: ColChamp.plein),
      const ChampDef(nom: 'mention', libelle: 'Règle appliquée', type: TypeChamp.textarea, col: ColChamp.plein),
    ], creation
        ? {'cycle': '3', 'honorairePeriodicite': 'mensuelle'}
        : {
            ...regime,
            'cycle': '${regime['cycle']}',
            'honoraire': regime['honoraire'] == null ? '' : '${regime['honoraire']}',
            'repos': regime['repos'] ?? '',
            'fonctions': [for (final x in (regime['fonctions'] as List? ?? const [])) '$x'],
            'vacations': [for (final x in (regime['vacations'] as List? ?? const [])) '$x'],
          });
    afficherModale<void>(ctx,
        titre: creation ? 'Nouveau régime de travail' : 'Modifier le régime « ${regime['libelle']} »',
        sousTitre: creation ? 'Les champs marqués d’un astérisque sont obligatoires.' : '${regime['source']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (!creation) ...[
            const NoteSigh(
                'Modifier un régime touche les vacations qui s’y adossent — et donc, potentiellement, les primes déjà calculées. La portée de la modification vous sera demandée à l’enregistrement.',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert),
            const SizedBox(height: 12),
          ],
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: creation ? 'Créer le régime' : 'Enregistrer',
                  icone: creation ? LucideIcons.plus : LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final fiche = <String, Object?>{
                      ...v,
                      'cycle': (num.tryParse('${v['cycle']}'.replaceAll(',', '.')) ?? 1).toInt(),
                      'honoraire': '${v['honoraire'] ?? ''}'.isEmpty ? null : (num.tryParse('${v['honoraire']}'.replaceAll(',', '.')) ?? 0).toInt(),
                    };
                    fermer();
                    if (creation) {
                      c.magasin.collection('regimesTravail').inserer({'statut': 'actif', ...fiche}, prefixe: 'REG');
                      ToastsSigh.afficher(ctx, 'Régime créé.', type: TypeToast.succes, detail: '${v['libelle']}');
                      return;
                    }
                    _portee(ctx, c, regime, fiche);
                  }),
            ]);
  }

  static String? _cycleValide(Object? v, Map<String, Object?> _) => (num.tryParse('$v'.replaceAll(',', '.')) ?? 0) < 1 ? 'Le cycle est d’au moins un jour.' : null;

  /// LA QUESTION QUI COMPTE — la portée d'une modification de régime : les vacations passées ont donné lieu à des primes calculées, parfois payées.
  void _portee(BuildContext ctx, ContexteEcran c, Fiche regime, Map<String, Object?> valeurs) {
    final col = c.magasin.collection('planning');
    final r = rhbVacationsDuRegime(rhbActives(c, 'planning'), [for (final x in (regime['fonctions'] as List? ?? const [])) '$x'], iso(c.aujourdhui));
    rhbDemanderPortee(ctx,
        sousTitre: '${regime['libelle']}',
        alerteTitre: 'Cette modification a une portée à choisir.',
        alerteTexte:
            '${nombre(r.concernees.length)} vacation(s) s’adossent à ce régime — ${nombre(r.passees.length)} déjà effectuée(s) et ${nombre(r.futures.length)} à venir. Les vacations passées ont pu donner lieu à des primes calculées, voire payées.',
        tonAlerte: TonSigh.attention,
        futur: (
          'Vacations en cours et à venir seulement',
          'Les ${nombre(r.passees.length)} vacation(s) passées gardent le régime sous lequel elles ont été effectuées, et les primes déjà calculées restent inchangées. C’est le choix prudent.'
        ),
        tout: (
          'Y compris les vacations passées',
          'Les ${nombre(r.passees.length)} vacation(s) passées sont réétiquetées et les primes de garde associées seront recalculées au prochain calcul de paie. À réserver à la correction d’une erreur de saisie du régime.'
        ),
        appliquer: (portee) {
          final annuler = c.magasin.collection('regimesTravail').mettreAJour(regime['id'], {
            ...valeurs,
            'portee': portee,
            'modifieLe': iso(c.aujourdhui),
            'modifiePar': c.utilisateur,
          });
          var touchees = 0;
          if (portee == 'tout') {
            for (final v in r.passees) {
              col.mettreAJour(v['id'], {'regimeLibelle': valeurs['libelle'], 'regimeRevisee': true});
              touchees++;
            }
          }
          for (final v in r.futures) {
            col.mettreAJour(v['id'], {'regimeLibelle': valeurs['libelle']});
          }
          c.magasin.journaliser('Modification de régime', 'M10', 'Régime', '${regime['id']}', {'libelle': regime['libelle']}, {'libelle': valeurs['libelle'], 'portee': portee});
          ToastsSigh.afficher(ctx, 'Régime modifié.',
              type: TypeToast.succes,
              detail: portee == 'tout'
                  ? '${nombre(touchees)} vacation(s) passée(s) réétiquetée(s) — primes à recalculer.'
                  : '${nombre(r.futures.length)} vacation(s) à venir concernée(s) ; l’historique est préservé.',
              annuler: annuler);
        });
  }

  void _archiver(BuildContext ctx, ContexteEcran c, Fiche regime) async {
    final n = rhbVacationsDuRegime(rhbActives(c, 'planning'), [for (final x in (regime['fonctions'] as List? ?? const [])) '$x'], iso(c.aujourdhui)).concernees.length;
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Archiver le régime « ${regime['libelle']} » ?',
        message:
            'Attention. ${nombre(n)} vacation(s) s’adossent à ce régime. Elles ne sont pas supprimées, mais aucune nouvelle affectation ne pourra s’en réclamer, et les fonctions concernées (${(regime['fonctions'] as List? ?? const []).length}) se retrouveront sans régime codifié tant qu’un autre ne les couvre pas.\n\nConformément à RG-14, l’archivage est logique : le régime reste consultable, restaurable depuis la corbeille, et jamais supprimé définitivement.',
        libelleOk: 'Archiver le régime',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = c.magasin.collection('regimesTravail').archiver(regime['id']);
    ToastsSigh.afficher(ctx, 'Régime archivé.', type: TypeToast.succes, detail: 'Restaurable depuis la corbeille (RG-14).', annuler: annuler);
  }
}
