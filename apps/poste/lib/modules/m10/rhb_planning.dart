import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/planning_rh_poste.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_circuit.dart';
import 'rhb_commun.dart';

const _jours = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];

/// Les fonctions dont la grille de la semaine affiche les agents.
const _fonctionsGrille = ['medecin', 'infirmier', 'sage_femme', 'aide_soignant', 'tsl', 'securite', 'entretien'];

/// Les vacations que les graphiques de charge comptent (gardes, soirées, permanences, incinération — ni l'entretien général ni le remplacement : la maquette
/// n'en retient que six, là où les statistiques de garde en comptent huit ; écart E666).
const _vacationsGraphiques = ['garde', 'garde_hospi', 'garde_soins', 'soiree', 'permanence', 'incineration'];

/// RG-11 : seul le planning VALIDÉ compte (primes, statistiques de garde, graphiques de charge). Une vacation d'avant le circuit (sans état) est lue validée.
bool rhbVacationCompte(Fiche p) => p['validationEtat'] == null || p['validationEtat'] == '' || p['validationEtat'] == 'validee';

/// `m10-planning` — « Planning & gardes » : les régimes de travail par catégorie (administrables), les régimes INDIVIDUELS (dérogations champ par champ,
/// versions datées, lot L4), la grille de la semaine où l'on affecte une vacation et le registre, tous deux lus à travers les FILTRES AVANCÉS. Le contrôle
/// d'incompatibilité EMPÊCHE de programmer une garde pendant le repos obligatoire qui suit la précédente : il vit au domaine (`controlerVacationRh`), une seule
/// règle quelle que soit la voie, la durée du repos étant celle du régime EN VIGUEUR À LA DATE, dérogation individuelle comprise.
class EcranPlanning extends StatefulWidget with EcranMaquette {
  const EcranPlanning({super.key});

  @override
  String get description => 'Planification des gardes, permanences et repos, avec contrôle des incompatibilités.';

  @override
  String get regle =>
      'Chaque catégorie applique son propre régime, relevé sur les plannings de la clinique : garde de 24 h (08h→08h), garde soins de 08h à 18h30, permanence de 08h à 18h, soirée de 18h à 8h, entretien général de la journée, repos de 24 h ou 48 h. Le système empêche de programmer une garde incompatible avec le repos obligatoire qui la suit.';

  @override
  State<EcranPlanning> createState() => _EtatPlanning();
}

class _EtatPlanning extends State<EcranPlanning> {
  // Les onze critères de la barre de filtres, dans l'ordre de la maquette.
  RhbFiltre? _q, _agent, _matricule, _service, _fonction, _regime, _type, _validation, _validePar, _du, _au;
  List<RhbFiltre> _tous = const [];
  bool _prepare = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prepare) return;
    _prepare = true;
    final c = ContexteEcran.of(context);
    final agents = trierPar([for (final e in rhbActives(c, 'personnel')) if (_fonctionsGrille.contains(e['fonction'])) e], (e) => e['nomComplet']);
    final validateurs = <String>{for (final p in rhbActives(c, 'planning')) if (p['validePar'] != null && p['validePar'] != '') '${p['validePar']}'}.toList()..sort();
    ChampDef liste(String nom, String libelle, String vide, List<OptionChamp> options) =>
        ChampDef(nom: nom, libelle: libelle, type: TypeChamp.select, options: [OptionChamp('', vide), ...options]);
    _q = RhbFiltre(const ChampDef(nom: 'pl_f_q', libelle: 'Recherche', indicatif: 'Agent, matricule, vacation, service'));
    _agent = RhbFiltre(liste('pl_f_agent', 'Agent', 'Tous les agents', [for (final e in agents) OptionChamp('${e['id']}', '${e['nomComplet']}')]));
    _matricule = RhbFiltre(liste('pl_f_matricule', 'Matricule', 'Tous les matricules', [for (final e in agents) OptionChamp('${e['matricule']}', '${e['matricule']} · ${e['nomComplet']}')]));
    _service = RhbFiltre(liste('pl_f_service', 'Service', 'Tous les services', [for (final s in rhbServices) OptionChamp(s)]));
    _fonction = RhbFiltre(liste('pl_f_fonction', 'Fonction', 'Toutes les fonctions', [for (final f in _fonctionsGrille) OptionChamp(f, rhbFonctionLabel(f))]));
    _regime = RhbFiltre(liste('pl_f_regime', 'Régime', 'Tous les régimes', [
      for (final r in rhbActives(c, 'regimesTravail')) OptionChamp('${r['libelle']}'),
      const OptionChamp('__individuel', 'Dérogation individuelle'),
    ]));
    _type = RhbFiltre(liste('pl_f_type', 'Type de vacation', 'Tous les types', [for (final t in rhbTypesPlanning) OptionChamp(t.id, t.label)]));
    _validation = RhbFiltre(liste('pl_f_validation', 'Validation', 'Validées ou non', const [OptionChamp('validee', 'Validées'), OptionChamp('a_valider', 'À valider')]));
    _validePar = RhbFiltre(liste('pl_f_validepar', 'Validé par', 'Tous les validateurs', [
      for (final n in validateurs) OptionChamp(n),
      const OptionChamp('__aucun', 'Validation non renseignée (avant le circuit)'),
    ]));
    _du = RhbFiltre(const ChampDef(nom: 'pl_f_du', libelle: 'Du', type: TypeChamp.date));
    _au = RhbFiltre(const ChampDef(nom: 'pl_f_au', libelle: 'Au', type: TypeChamp.date));
    _tous = [_q!, _agent!, _matricule!, _service!, _fonction!, _regime!, _type!, _validation!, _validePar!, _du!, _au!];
    for (final f in _tous) {
      f.controleur.addListener(_maj);
    }
  }

  @override
  void dispose() {
    for (final f in _tous) {
      f.controleur.removeListener(_maj);
      f.controleur.dispose();
    }
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  bool get _enForce => _tous.any((f) => f.valeur.isNotEmpty);

  void _effacer() {
    for (final f in _tous) {
      f.controleur.removeListener(_maj);
      f.poser('');
      f.controleur.addListener(_maj);
    }
    setState(() {});
  }

  // -------------------------------------------------------------------------------------------------------------------
  // Les filtres : une barre, deux lectures (la grille et le registre)
  // -------------------------------------------------------------------------------------------------------------------

  bool _agentRetenu(ContexteEcran c, PlanningRhPoste p, Fiche e, {bool pourVacation = false}) {
    if (_agent!.valeur.isNotEmpty && e['id'] != _agent!.valeur) return false;
    if (_matricule!.valeur.isNotEmpty && e['matricule'] != _matricule!.valeur) return false;
    if (_service!.valeur.isNotEmpty && e['service'] != _service!.valeur) return false;
    if (_fonction!.valeur.isNotEmpty && e['fonction'] != _fonction!.valeur) return false;
    if (pourVacation) return true;
    if (_regime!.valeur.isNotEmpty) {
      final r = p.regimeALaDate(e, iso(c.aujourdhui));
      if (_regime!.valeur == '__individuel' ? !r.individuel : r.categorie != _regime!.valeur) return false;
    }
    final q = _q!.valeur.trim().toLowerCase();
    if (q.isNotEmpty && !'${e['nomComplet']} ${e['matricule']} ${e['poste'] ?? ''}'.toLowerCase().contains(q)) return false;
    return true;
  }

  bool _vacationRetenue(ContexteEcran c, PlanningRhPoste p, Fiche v, Map<String, Fiche> personnel) {
    if (_type!.valeur.isNotEmpty && v['type'] != _type!.valeur) return false;
    final d = '${v['date']}';
    if (_du!.valeur.isNotEmpty && d.compareTo(_du!.valeur) < 0) return false;
    if (_au!.valeur.isNotEmpty && d.compareTo(_au!.valeur) > 0) return false;
    final etat = v['validationEtat'] == null || v['validationEtat'] == '' ? 'validee' : '${v['validationEtat']}';
    if (_validation!.valeur.isNotEmpty && etat != _validation!.valeur) return false;
    if (_validePar!.valeur.isNotEmpty && ((v['validePar'] == null || v['validePar'] == '') ? '__aucun' : '${v['validePar']}') != _validePar!.valeur) return false;
    if (_regime!.valeur.isNotEmpty) {
      final derog = (v['derogations'] as List?)?.isNotEmpty ?? false;
      final lib = (v['regimeLibelle'] != null && v['regimeLibelle'] != '') ? '${v['regimeLibelle']}' : rhbRegimeDe(rhbActives(c, 'regimesTravail'), '${v['fonction']}')?.libelle;
      if (_regime!.valeur == '__individuel' ? !derog : lib != _regime!.valeur) return false;
    }
    final e = personnel['${v['employeId']}'];
    if (e != null && !_agentRetenu(c, p, e, pourVacation: true)) return false;
    if (e == null && (_agent!.valeur.isNotEmpty || _matricule!.valeur.isNotEmpty || _service!.valeur.isNotEmpty || _fonction!.valeur.isNotEmpty)) return false;
    final q = _q!.valeur.trim().toLowerCase();
    if (q.isNotEmpty && !'${v['employe'] ?? ''} ${e?['matricule'] ?? ''} ${rhbTypePlanningLabel(v['type'])} ${v['service'] ?? ''}'.toLowerCase().contains(q)) return false;
    return true;
  }

  /// Les filtres EN FORCE, relevés comme `print.js` les relève sur la page : listes (libellé de l'option choisie), dates, recherche.
  List<(String, String)> _filtresEnForce() {
    final out = <(String, String)>[];
    void ajouter(String libelle, String valeur) {
      if (valeur.isEmpty) return;
      if (!out.any((x) => x.$1 == libelle && x.$2 == valeur)) out.add((libelle, valeur));
    }

    String lib(RhbFiltre f) => f.def.options.where((o) => o.valeur == f.valeur).map((o) => o.libelle).firstOrNull ?? f.valeur;
    for (final f in [_agent!, _matricule!, _service!, _fonction!, _regime!, _type!, _validation!, _validePar!]) {
      if (f.valeur.isNotEmpty) ajouter(f.def.libelle, lib(f));
    }
    for (final f in [_du!, _au!]) {
      if (f.valeur.isNotEmpty && DateTime.tryParse(f.valeur) != null) ajouter(f.def.libelle, dateFR(DateTime.parse(f.valeur)));
    }
    if (_q!.valeur.trim().isNotEmpty) ajouter('Recherche', _q!.valeur.trim());
    return out;
  }

  // -------------------------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => RhbEcoute(
      collections: const ['planning', 'regimesTravail', 'regimesIndividuels', 'personnel', 'parametres'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final p = rhbPlanningPoste(c);
    final planning = rhbActives(c, 'planning');
    final personnel = {for (final e in rhbActives(c, 'personnel')) '${e['id']}': e};
    final auj = planning.where((v) => v['date'] == iso(c.aujourdhui)).toList();
    final debut = _du!.valeur.isNotEmpty && DateTime.tryParse(_du!.valeur) != null ? DateTime.parse(_du!.valeur) : ajouterJours(c.aujourdhui, -3);
    final jours = [for (var i = 0; i < 7; i++) ajouterJours(debut, i)];
    final agents = trierPar(
        [for (final e in rhbActives(c, 'personnel')) if (_fonctionsGrille.contains(e['fonction']) && _agentRetenu(c, p, e)) e], (e) => e['nomComplet']);
    final retenues = [for (final v in planning) if (_vacationRetenue(c, p, v, personnel)) v];
    final modifiable = c.droit.editer && const ['admin', 'da', 'surveillant'].contains(c.role);
    return rhbEspace([
      _Regimes(contexte: context),
      _Individuels(contexte: context, p: p),
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
          child: Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Légende :', style: TextStyle(color: JetonsShell.slate500, fontSize: 12, fontWeight: FontWeight.w500)),
            for (final t in rhbTypesPlanning)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: rhbTon(t.couleur).icone600)),
                const SizedBox(width: 6),
                Text('${t.court} — ${t.label}', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)),
              ]),
          ])),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Vacations planifiées', valeur: nombre(planning.length), icone: LucideIcons.calendarDays, ton: TonSigh.navy),
        KpiSigh(libelle: 'De garde aujourd’hui', valeur: nombre(auj.where((v) => v['type'] == 'garde').length), icone: LucideIcons.moon, ton: TonSigh.danger),
        KpiSigh(libelle: 'En permanence', valeur: nombre(auj.where((v) => v['type'] == 'permanence').length), icone: LucideIcons.sun, ton: TonSigh.attention),
        KpiSigh(libelle: 'En repos', valeur: nombre(auj.where((v) => '${v['type']}'.startsWith('repos')).length), icone: LucideIcons.bed, ton: TonSigh.info),
      ]),
      const RhbCarteReglages(),
      _barre(),
      CarteSigh(
          titre: 'Planning du ${dateFR(jours.first)} au ${dateFR(jours.last)}',
          sansRemplissage: true,
          actions: [BoutonSigh(libelle: 'Imprimer le planning', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimer(context, c, agents, jours))],
          child: agents.isEmpty
              ? const VideSigh('Aucun agent ne correspond aux filtres.', indice: 'Effacer un filtre pour élargir la sélection.', icone: LucideIcons.users)
              : _Grille(agents: agents, jours: jours, contexte: context, p: p, modifiable: modifiable, retenue: (v) => _vacationRetenue(c, p, v, personnel))),
      _Registre(contexte: context, lignes: retenues, enForce: _enForce, imprimer: () => _imprimerRegistre(context, c, retenues)),
      ..._graphes(retenues),
    ]);
  }

  Widget _barre() => CarteSigh(
      titre: 'Filtres avancés du planning',
      child: LayoutBuilder(builder: (_, k) {
        final n = k.maxWidth >= 1024 ? 4 : (k.maxWidth >= 768 ? 3 : 1);
        final l = (k.maxWidth - 12 * (n - 1)) / n;
        return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          for (final f in _tous) SizedBox(width: f.def.nom == 'pl_f_q' && n > 1 ? l * 2 + 12 : l, child: FormulaireSigh(key: Key('rhb:filtre:${f.def.nom}'), controleur: f.controleur)),
          BoutonSigh(libelle: 'Effacer les filtres', icone: LucideIcons.filterX, variante: VarianteBouton.secondaire, onPressed: _effacer),
        ]);
      }));

  List<Widget> _graphes(List<Fiche> retenues) {
    // RG-11 : les graphiques de charge ne comptent que le planning VALIDÉ.
    final v = [for (final x in retenues) if (rhbVacationCompte(x) && _vacationsGraphiques.contains(x['type'])) x];
    final parAgent = rhbGrouper(v, (x) => '${x['employe']}');
    final agents = trierPar([for (final e in parAgent.entries) (e.key, e.value.length)], (x) => x.$2, descendant: true).take(10).toList();
    final parService = rhbGrouper(v, (x) => x['service'] == null || x['service'] == '' ? 'Non renseigné' : '${x['service']}');
    final parType = rhbGrouper(v, (x) => '${x['type']}');
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
            filtres: _filtresEnForce(),
            cartouche: [
              ('Période', '${dateFR(jours.first)} – ${dateFR(jours.last)}'),
              ('Agents concernés', nombre(agents.length)),
              ('Établi par', acteur(c).nom),
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

  /// « Imprimer l'état » du registre : l'extrait filtré, ses filtres retracés sur la pièce.
  void _imprimerRegistre(BuildContext ctx, ContexteEcran c, List<Fiche> retenues) {
    final rows = trierPar(retenues, (v) => '${v['date']}', descendant: true);
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Registre des vacations',
            sousTitre: _enForce ? 'Extrait filtré du registre' : 'Registre complet',
            filtres: _filtresEnForce(),
            cartouche: [('Vacations retenues', nombre(rows.length)), ('Établi par', acteur(c).nom), ('Date d’édition', dateFR(c.aujourdhui))],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Date', valeur: (v) => dateFR(DateTime.parse('${v['date']}'))),
                ColonneEtat(libelle: 'Agent', valeur: (v) => v['employe']),
                ColonneEtat(libelle: 'Fonction', valeur: (v) => rhbFonctionLabel(v['fonction'])),
                ColonneEtat(libelle: 'Service', valeur: (v) => v['service']),
                ColonneEtat(libelle: 'Vacation', valeur: (v) => rhbTypePlanningLabel(v['type'])),
                ColonneEtat(libelle: 'Régime', valeur: (v) => '${v['regimeLibelle'] == null || v['regimeLibelle'] == '' ? '—' : v['regimeLibelle']}${(v['derogations'] as List?)?.isNotEmpty ?? false ? ' (individuel)' : ''}'),
                ColonneEtat(libelle: 'Validation', valeur: (v) => v['validationEtat'] == 'a_valider' ? 'À valider' : 'Validée'),
                ColonneEtat(libelle: 'Validé par', valeur: (v) => v['validePar'] == null || v['validePar'] == '' ? '—' : v['validePar']),
              ], lignes: rows)
            ],
            signatures: const [rhbSignSurveillant, rhbSignDaf]));
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// La grille de la semaine
// ---------------------------------------------------------------------------------------------------------------------

class _Grille extends StatelessWidget {
  const _Grille({required this.agents, required this.jours, required this.contexte, required this.p, required this.modifiable, required this.retenue});
  final List<Fiche> agents;
  final List<DateTime> jours;
  final BuildContext contexte;
  final PlanningRhPoste p;
  final bool modifiable;
  final bool Function(Fiche) retenue;

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
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: rhbAgentCellule('${e['nomComplet']}', '${rhbFonctionLabel(e['fonction'])}${p.regimeALaDate(e, iso(c.aujourdhui)).individuel ? ' · régime individuel' : ''}')),
                for (final j in jours)
                  Padding(
                      padding: const EdgeInsets.all(4),
                      child: _Cellule(
                          contexte: contexte,
                          agent: e,
                          jour: j,
                          modifiable: modifiable,
                          vacation: planning.where((v) => v['employeId'] == e['id'] && v['date'] == iso(j)).firstOrNull,
                          retenue: retenue)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _Cellule extends StatelessWidget {
  const _Cellule({required this.contexte, required this.agent, required this.jour, required this.vacation, required this.modifiable, required this.retenue});
  final BuildContext contexte;
  final Fiche agent;
  final DateTime jour;
  final Fiche? vacation;
  final bool modifiable;
  final bool Function(Fiche) retenue;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final v = vacation;
    final masque = v != null && !retenue(v);
    final t = v != null && !masque ? rhbTypePlanningTon('${v['type']}') : null;
    final fond = switch (t) { 'danger' => JetonsShell.danger100, 'warning' => JetonsShell.warning100, 'info' => JetonsShell.info100, 'navy' => JetonsShell.navy100, 'success' => JetonsShell.success100, 'neutral' => JetonsShell.slate100, _ => null };
    final texte = switch (t) { 'danger' => JetonsShell.danger800, 'warning' => JetonsShell.warning800, 'info' => JetonsShell.info800, 'navy' => JetonsShell.navy800, 'success' => JetonsShell.success800, 'neutral' => JetonsShell.slate700, _ => JetonsShell.slate300 };
    final libelle = masque
        ? '·'
        : (v != null ? rhbTypePlanningLabel(v['type']).replaceAll('Permanence', 'Perm.').replaceAll('Remplacement', 'Rempl.') : (modifiable ? '+' : '·'));
    Widget corps = Container(
        key: Key('rhb:cellule:${agent['id']}:${iso(jour)}'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(4)),
        child: Text(libelle, textAlign: TextAlign.center, style: TextStyle(color: texte, fontSize: 10, height: 1.4, fontWeight: FontWeight.w500)));
    if (masque) corps = Tooltip(message: 'Masquée par les filtres', child: corps);
    // Sans le droit d'écrire (ou hors surveillant, DA et administrateur), la case se LIT mais ne s'ouvre pas : une commande interdite est ABSENTE.
    if (!modifiable) return corps;
    return InkWell(borderRadius: BorderRadius.circular(4), onTap: () => affecter(contexte, c, agent, jour, vacation), child: corps);
  }
}

String _textePeriodicite(Object? x) => x == 'occurrence' ? 'par occurrence' : 'mensuelle';

/// Ce que dit une dérogation, champ par champ (`texteDerogations`).
List<String> _textesDerogations(List<String> derog, {List<String> vacations = const [], String? repos, Object? cycle, Object? honoraire, String? periodicite}) => [
      if (derog.contains('vacations')) 'Vacations : ${vacations.map(rhbTypePlanningLabel).join(', ')}',
      if (derog.contains('repos')) 'Repos : ${repos != null && repos != '' ? rhbTypePlanningLabel(repos) : 'aucun codifié'}',
      if (derog.contains('cycle')) 'Cycle : $cycle jours',
      if (derog.contains('honoraire')) 'Honoraire : ${money(honoraire, avecDevise: false)}',
      if (derog.contains('honorairePeriodicite')) 'Périodicité : ${_textePeriodicite(periodicite)}',
    ];

List<String> _textesRegime(RegimeRhResolu r) =>
    _textesDerogations(r.derogations, vacations: r.vacations, repos: r.repos, cycle: r.cycle, honoraire: r.honoraire, periodicite: r.honorairePeriodicite);

/// `affecter` : l'affectation d'une vacation à un agent, un jour donné. Les vacations proposées sont celles du régime EN VIGUEUR À LA DATE (dérogation
/// individuelle comprise) ; le contrôle de repos et de double affectation est celui du domaine (une règle, une voie), refusé EN LE NOMMANT.
void affecter(BuildContext ctx, ContexteEcran c, Fiche e, DateTime jour, Fiche? existant) {
  final p = rhbPlanningPoste(c);
  final regime = p.regimeALaDate(e, iso(jour));
  final autorises = p.typesAutorises(e, iso(jour));
  final ctl = ControleurFormulaire([
    ChampDef(nom: 'type', libelle: 'Type de vacation', type: TypeChamp.select, requis: true, col: ColChamp.demi, options: [
      for (final t in rhbTypesPlanning)
        if (autorises.contains(t.id)) OptionChamp(t.id, rhbLibelleVacation(t))
    ]),
    const ChampDef(nom: 'observation', libelle: 'Observation', col: ColChamp.plein),
  ], existant != null ? {'type': existant['type'], 'observation': existant['observation']} : {'type': regime.vacations.isNotEmpty ? regime.vacations.first : 'permanence'});
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
        if (regime.categorie != null || regime.individuel) ...[
          const SizedBox(height: 12),
          NoteSigh('${regime.libelle ?? ''}${regime.individuel ? ' · dérogation individuelle (${_textesRegime(regime).join(' ; ')})' : ''}${(regime.mention ?? '').isNotEmpty ? ' — ${regime.mention}' : ''}'),
        ],
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
                    final r = p.retirerVacation(existant['id']);
                    if (r['ok'] != true) {
                      rhbToastRefus(ctx, r);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Vacation retirée.', type: TypeToast.succes, annuler: r['annuler'] as VoidCallback);
                  }),
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Enregistrer',
                icone: LucideIcons.save,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) return;
                  // Le contrôle d'incompatibilité vit au MOTEUR : une seule règle, quelle que soit la voie. La vacation porte le régime sous lequel elle est posée.
                  final r = p.poserVacation(employeId: e['id'], date: iso(jour), type: '${v['type']}', observation: v['observation'] as String?, existantId: existant?['id']);
                  if (r['ok'] != true) {
                    rhbToastRefus(ctx, r);
                    return;
                  }
                  fermer();
                  ToastsSigh.afficher(ctx, 'Vacation enregistrée.', type: TypeToast.succes, annuler: r['annuler'] as VoidCallback);
                }),
          ]);
}

// ---------------------------------------------------------------------------------------------------------------------
// Le registre des vacations
// ---------------------------------------------------------------------------------------------------------------------

class _Registre extends StatelessWidget {
  const _Registre({required this.contexte, required this.lignes, required this.enForce, required this.imprimer});
  final BuildContext contexte;
  final List<Fiche> lignes;
  final bool enForce;
  final VoidCallback imprimer;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final regimes = rhbActives(c, 'regimesTravail');
    final personnel = {for (final e in rhbActives(c, 'personnel')) '${e['id']}': e};
    String regimeDe(Fiche p) {
      final lib = p['regimeLibelle'];
      final base = (lib != null && lib != '') ? '$lib' : rhbRegimeDe(regimes, '${p['fonction']}')?.libelle;
      if (base == null) return '—';
      return '$base${(p['derogations'] as List?)?.isNotEmpty ?? false ? ' (individuel)' : ''}';
    }

    String validation(Fiche p) => p['validationEtat'] == 'a_valider' ? 'À valider' : 'Validée';
    return TableauSigh(
      titre: 'Registre des vacations${enForce ? ' (filtré)' : ''}',
      lignes: lignes,
      taillePage: 15,
      triInitial: 'date',
      sensInitial: 'desc',
      nomExport: 'planning',
      selectionnable: true,
      actions: [BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: imprimer)],
      colonnes: [
        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (p) => dateFR(DateTime.parse('${p['date']}')), rendu: (_, p) => Text(dateFR(DateTime.parse('${p['date']}')))),
        ColonneTableau(cle: 'matricule', libelle: 'Mat.', sansCoupure: true, valeur: (p) => personnel['${p['employeId']}']?['matricule'] ?? ''),
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
        ColonneTableau(
            cle: 'statut2',
            libelle: 'Validation',
            valeur: validation,
            texte: validation,
            rendu: (_, p) => p['validationEtat'] == 'a_valider' ? const BadgeSigh('À valider', ton: TonSigh.attention) : statutBadge('validee')),
        ColonneTableau(
            cle: 'validePar',
            libelle: 'Validé par',
            valeur: (p) => p['validePar'] ?? '',
            texte: (p) => '${p['validePar'] ?? ''}',
            rendu: (_, p) => Text('${p['validePar'] == null || p['validePar'] == '' ? '—' : p['validePar']}', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12))),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Les régimes INDIVIDUELS (lot L4) : une dérogation champ par champ, versionnée par date
// ---------------------------------------------------------------------------------------------------------------------

class _Individuels extends StatelessWidget {
  const _Individuels({required this.contexte, required this.p});
  final BuildContext contexte;
  final PlanningRhPoste p;

  bool _peutDeroger(ContexteEcran c) => (c.role == 'admin' || c.role == 'da') && c.droit.editer;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final ids = <Object?>{for (final v in rhbActives(c, 'regimesIndividuels')) v['employeId']};
    final personnel = {for (final e in rhbActives(c, 'personnel')) e['id']: e};
    final lignes = <Fiche>[
      for (final id in ids)
        if (personnel[id] != null)
          {'e': personnel[id], 'r': p.regimeALaDate(personnel[id]!, iso(c.aujourdhui)), 'versions': p.historique(id).length, 'id': id}
    ];
    return CarteSigh(
      titre: 'Régimes individuels (dérogations champ par champ)',
      actions: [
        if (_peutDeroger(c)) BoutonSigh(libelle: 'Déroger pour un agent', icone: LucideIcons.userCog, taille: TailleBouton.sm, onPressed: () => _deroger(contexte, c, null)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'Le régime de la catégorie reste la règle. Une dérogation individuelle ne change que les champs renseignés (vacations, repos, cycle, honoraire) : le reste suit la catégorie. Chaque dérogation est une version datée qui ne se réécrit pas ; les vacations déjà posées gardent le régime sous lequel elles l’ont été.'),
        const SizedBox(height: 12),
        MiniTableauSigh(
            vide: 'Aucun agent n’a de régime individuel : tous suivent le régime de leur catégorie.',
            colonnes: [
              ColonneMini('Agent', (l) => '', rendu: (l) {
                final e = l['e'] as Fiche;
                return rhbAgentCellule('${e['nomComplet']}', '${e['matricule']} · ${rhbFonctionLabel(e['fonction'])}');
              }),
              ColonneMini('Catégorie', (l) => (l['r'] as RegimeRhResolu).categorie ?? '—'),
              ColonneMini('Aujourd’hui', (l) => '', rendu: (l) {
                final r = l['r'] as RegimeRhResolu;
                return r.individuel
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        for (final t in _textesRegime(r)) Text(t, style: const TextStyle(color: JetonsShell.slate700, fontSize: 12, height: 16 / 12)),
                      ])
                    : const Text('Suit sa catégorie', style: TextStyle(color: JetonsShell.slate400, fontSize: 12));
              }),
              ColonneMini('Depuis', (l) {
                final d = (l['r'] as RegimeRhResolu).dateEffet;
                return d == null ? '—' : dateFR(DateTime.parse(d));
              }),
              ColonneMini('Versions', (l) => '${l['versions']}', droite: true),
              ColonneMini('', (l) => '', droite: true, rendu: (l) {
                final e = l['e'] as Fiche;
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  BoutonIcone(icone: LucideIcons.history, libelle: 'Historique des versions', onPressed: () => _historique(contexte, e)),
                  if (_peutDeroger(c)) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Nouvelle version pour cet agent', onPressed: () => _deroger(contexte, c, e)),
                ]);
              }),
            ],
            lignes: lignes),
      ]),
    );
  }

  void _historique(BuildContext ctx, Fiche e) {
    final h = p.historique(e['id']);
    afficherModale<void>(ctx,
        titre: 'Historique du régime de ${e['nomComplet']}',
        sousTitre: '${e['matricule']} · ${rhbFonctionLabel(e['fonction'])}',
        taille: TailleModale.lg,
        corps: MiniTableauSigh(vide: 'Aucune version.', colonnes: [
          ColonneMini('Version', (x) => '${x['version']}', droite: true),
          ColonneMini('Date d’effet', (x) => dateFR(DateTime.parse('${x['dateEffet']}'))),
          ColonneMini('Contenu', (x) => '', rendu: (x) {
            if (x['retourCategorie'] == true) return const Text('Retour au régime de la catégorie', style: TextStyle(color: JetonsShell.slate500, fontSize: 12));
            final ch = (x['champs'] as Map).cast<String, Object?>();
            final repos = ch['repos'] == 'aucun' ? null : ch['repos'] as String?;
            final textes = _textesDerogations(ch.keys.toList(),
                vacations: [for (final v in (ch['vacations'] as List? ?? const [])) '$v'], repos: repos, cycle: ch['cycle'], honoraire: ch['honoraire'], periodicite: ch['honorairePeriodicite'] as String?);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final t in textes) Text(t, style: const TextStyle(color: JetonsShell.slate700, fontSize: 12, height: 16 / 12)),
            ]);
          }),
          ColonneMini('Motif', (x) => '${x['motif'] == null || x['motif'] == '' ? '—' : x['motif']}'),
          ColonneMini('Posée par', (x) => '${x['creePar'] ?? '—'}${x['creeLe'] != null && x['creeLe'] != '' ? ' le ${dateFR(DateTime.parse('${x['creeLe']}'))}' : ''}'),
        ], lignes: h),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
  }

  void _deroger(BuildContext ctx, ContexteEcran c, Fiche? agent) {
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'employeId', libelle: 'Agent', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [
        for (final e in rhbPersonnelTrie(c)) OptionChamp('${e['id']}', '${e['matricule']} — ${e['nomComplet']} (${e['poste']})')
      ]),
      const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true),
      const ChampDef(nom: 'retourCategorie', libelle: 'Revenir au régime de la catégorie (retire la dérogation)', type: TypeChamp.case_, col: ColChamp.plein),
      const ChampDef.section('Champs dérogés (laisser vide pour suivre la catégorie)'),
      ChampDef(nom: 'vacations', libelle: 'Vacations', type: TypeChamp.multiselect, col: ColChamp.plein, options: [
        for (final t in rhbTypesPlanning)
          if (t.duree > 0) OptionChamp(t.id, '${t.label} (${t.debut} → ${t.fin})')
      ]),
      const ChampDef(nom: 'repos', libelle: 'Repos', type: TypeChamp.select, options: [
        OptionChamp('', 'Suit la catégorie'),
        OptionChamp('repos24', 'Repos 24h'),
        OptionChamp('repos48', 'Repos 48h'),
        OptionChamp('aucun', 'Aucun repos codifié'),
      ]),
      const ChampDef(nom: 'cycle', libelle: 'Cycle (jours)', type: TypeChamp.nombre),
      const ChampDef(nom: 'honoraire', libelle: 'Honoraire (FCFA)', type: TypeChamp.nombre),
      const ChampDef(nom: 'honorairePeriodicite', libelle: 'Périodicité de l’honoraire', type: TypeChamp.select, options: [
        OptionChamp('', 'Suit la catégorie'),
        OptionChamp('mensuelle', 'Mensuelle'),
        OptionChamp('occurrence', 'Par occurrence'),
      ]),
      const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
    ], {'employeId': agent == null ? '' : agent['id'], 'dateEffet': iso(c.aujourdhui), 'vacations': <String>[], 'repos': '', 'honorairePeriodicite': ''});
    afficherModale<void>(ctx,
        titre: 'Régime individuel',
        sousTitre: 'Une version datée : elle ne se réécrit pas.',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh('Seuls les champs renseignés dérogent à la catégorie. La date d’effet est aujourd’hui ou à venir : les vacations passées gardent leur régime.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer la version',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final r = p.deroger(
                        employeId: v['employeId'],
                        dateEffet: v['dateEffet'] as String?,
                        retourCategorie: v['retourCategorie'] == true,
                        motif: v['motif'] as String?,
                        champs: {
                          'vacations': v['vacations'],
                          'repos': v['repos'],
                          'cycle': v['cycle'],
                          'honoraire': v['honoraire'],
                          'honorairePeriodicite': v['honorairePeriodicite'],
                        });
                    if (r['ok'] != true) {
                      rhbToastRefus(ctx, r);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, r['retourCategorie'] == true ? 'Retour au régime de la catégorie enregistré.' : 'Dérogation enregistrée.',
                        type: TypeToast.succes, detail: 'Version ${r['version']} à compter du ${dateFR(DateTime.parse('${v['dateEffet']}'))}');
                  }),
            ]);
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
            'modifiePar': acteur(c).nom,
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
