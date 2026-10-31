import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';
import 'rhc_commun.dart';

/// `m10-securite-entretien` — « Sécurité & entretien » : le planning rotatif des agents de sécurité (garde 24 h, soirée 18 h → 8 h, repos) et d'entretien (permanence, entretien
/// général de la journée). Les légendes sont reprises TELLES QUELLES des plannings transmis lors du cadrage. La rotation se règle ICI MÊME (une case s'ouvre au clic) et les
/// vacations sont celles du PLANNING VALIDÉ — même collection que « Planning & gardes » : toute modification y est immédiatement visible. Les types proposés suivent la FONCTION de
/// l'agent ; une garde la veille interdit la suivante (le repos de 24 h reste opposable). Les repos sont exclus des comptages : ils ne sont pas des postes tenus.
///
/// E749 ✅ corrigé dans la maquette — la liste des agents était lue UNE fois au rendu : un agent créé ou archivé ici ne paraissait ni dans la grille de rotation ni aux indicateurs avant
/// le rechargement de la page.
class EcranSecuriteEntretien extends StatelessWidget with EcranMaquette {
  const EcranSecuriteEntretien({super.key});

  @override
  String get titre => 'Sécurité & entretien';
  @override
  String get description => 'Planning rotatif des agents de sécurité et d’entretien : permanence et entretien général de la journée.';
  @override
  String get regle =>
      'La rotation se règle ici même : une case du planning s’ouvre au clic. Les vacations restent celles du planning validé — même collection que « Planning & gardes », donc toute modification y est immédiatement visible. Le repos de 24 h qui suit une garde reste opposable.';

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['personnel', 'planning'], construire: _corps);

  static const _tonsCellule = {
    'danger': (JetonsShell.danger100, JetonsShell.danger800),
    'warning': (JetonsShell.warning100, JetonsShell.warning800),
    'info': (JetonsShell.info100, JetonsShell.info800),
    'navy': (JetonsShell.navy100, JetonsShell.navy800),
    'success': (JetonsShell.success100, JetonsShell.success800),
    'neutral': (JetonsShell.slate100, JetonsShell.slate800),
  };

  Widget _corps(BuildContext context, ContexteEcran c) {
    final agents = rhcAgentsRotation(rhcPersonnel(c));
    final planning = rhbActives(c, 'planning');
    final auj = DateTime(c.aujourdhui.year, c.aujourdhui.month, c.aujourdhui.day);
    final jours = [for (var i = 0; i < 14; i++) DateTime(auj.year, auj.month, auj.day + i - 3)];
    final enPoste = planning.where((p) => p['date'] == iso(auj) && (p['fonction'] == 'securite' || p['fonction'] == 'entretien') && p['type'] != 'repos24' && p['type'] != 'repos48').length;
    return rhbEspace([
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Agents de sécurité', valeur: nombre(agents.where((e) => e['fonction'] == 'securite').length), icone: LucideIcons.shield, ton: TonSigh.navy),
        KpiSigh(libelle: 'Agents d’entretien', valeur: nombre(agents.where((e) => e['fonction'] == 'entretien').length), icone: LucideIcons.sprayCan, ton: TonSigh.info),
        KpiSigh(libelle: 'En poste aujourd’hui', valeur: nombre(enPoste), icone: LucideIcons.userCheck, ton: TonSigh.succes),
        KpiSigh(libelle: 'Masse salariale', valeur: money(rhcSomme(agents, 'salaireBase')), icone: LucideIcons.banknote, ton: TonSigh.neutre),
      ]),
      // Légendes reprises telles quelles des plannings de la clinique.
      LayoutBuilder(builder: (_, k) {
        final deux = k.maxWidth >= 640;
        final l = deux ? (k.maxWidth - 12) / 2 : k.maxWidth;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
              width: l,
              child: CarteSigh(titre: 'Agents de sécurité', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _legende('G', 'Garde — 24 h', TonSigh.danger),
                _legende('S', 'Soirée — de 18h à 8h', TonSigh.navy),
                _legende('R', 'Repos', TonSigh.neutre),
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('Rotation à trois agents sur un cycle de 3 jours.', style: rhbPetit)),
              ]))),
          SizedBox(
              width: l,
              child: CarteSigh(titre: 'Agents d’entretien', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _legende('P', 'Permanence', TonSigh.info),
                _legende('EGJ', 'Entretien général de la journée', TonSigh.info),
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('Rotation à trois agents : une permanence, deux entretiens généraux.', style: rhbPetit)),
              ]))),
        ]);
      }),
      const NoteSigh(
          'Ces légendes sont reprises telles quelles des plannings transmis lors du cadrage : « G = GARDE 24H, S = SOIRÉE 18H à 8H, R = REPOS » pour la sécurité, « P = PERMANENCE, EGJ = ENTRETIEN GÉNÉRAL DE LA JOURNÉE » pour l’entretien.'),
      CarteSigh(
          titre: 'Planning rotatif sur 14 jours',
          actions: [BoutonSigh(libelle: 'Imprimer le planning', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimerPlanning(context, c, agents, planning, jours))],
          child: _grille(context, c, agents, planning, jours, auj)),
      _agents(context, c),
      _graphiques(planning),
      rhcSource('Plannings des agents d’entretien et des agents de sécurité de la clinique.'),
    ]);
  }

  static Widget _legende(String code, String libelle, TonSigh ton) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _fond100(ton), borderRadius: BorderRadius.circular(4)),
            child: Text(code, style: TextStyle(color: ton.texteBadge, fontSize: 11, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Text(libelle, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
      ]));

  static Color _fond100(TonSigh t) => switch (t) {
        TonSigh.danger => JetonsShell.danger100,
        TonSigh.navy => JetonsShell.navy100,
        TonSigh.info => JetonsShell.info100,
        TonSigh.succes => JetonsShell.success100,
        TonSigh.attention => JetonsShell.warning100,
        TonSigh.neutre => JetonsShell.slate100,
      };

  // ---- La grille de rotation ------------------------------------------------------------------------------------------------------------------------

  static String _jour2(DateTime j) => dateJour(j).split(' ').first.substring(0, 2);

  Widget _grille(BuildContext ctx, ContexteEcran c, List<Fiche> agents, List<Fiche> planning, List<DateTime> jours, DateTime auj) {
    const entete = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600);
    Widget cel(Widget w, {Alignment a = Alignment.centerLeft, Color? fond}) =>
        Container(color: fond, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), alignment: a, child: w);
    final lignes = <TableRow>[
      TableRow(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate200))), children: [
        cel(const Text('AGENT', style: entete)),
        cel(const Text('FONCTION', style: entete)),
        for (final j in jours)
          cel(
              // « ma » au-dessus de « 27 » : l'entête se lit « ma27 » (le libellé complet est aussi porté par l'infobulle).
              Tooltip(
                  message: '${_jour2(j)}${j.day}',
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_jour2(j).toUpperCase(), style: entete.copyWith(color: iso(j) == iso(auj) ? JetonsShell.navy800 : JetonsShell.slate500)),
                    Text('${j.day}', style: entete.copyWith(color: iso(j) == iso(auj) ? JetonsShell.navy800 : JetonsShell.slate500)),
                  ])),
              a: Alignment.center,
              fond: iso(j) == iso(auj) ? JetonsShell.navy50 : null),
      ]),
      for (final e in agents)
        TableRow(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate100))), children: [
          cel(Text('${e['nomComplet']}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14))),
          cel(BadgeSigh(rhbFonctionLabel(e['fonction']), ton: e['fonction'] == 'securite' ? TonSigh.navy : TonSigh.info)),
          for (final j in jours) cel(_cellule(ctx, c, e, j, planning.where((p) => p['employeId'] == e['id'] && p['date'] == iso(j)).firstOrNull), a: Alignment.center),
        ]),
    ];
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 960),
            child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: lignes)));
  }

  Widget _cellule(BuildContext ctx, ContexteEcran c, Fiche agent, DateTime jour, Fiche? vacation) {
    final t = vacation != null ? rhbTypePlanning(vacation['type']) : null;
    final ton = vacation != null ? _tonsCellule[rhbTypePlanningTon(vacation['type'])] : null;
    final modifiable = c.droit.editer;
    final corps = Container(
        key: Key('rhc:cellule:${agent['id']}:${iso(jour)}'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: ton?.$1, borderRadius: BorderRadius.circular(4)),
        child: Text(t != null ? t.court : (modifiable ? '+' : '—'),
            style: TextStyle(color: ton?.$2 ?? JetonsShell.slate300, fontSize: 10, height: 1.5, fontWeight: FontWeight.w600)));
    final titre = t != null ? t.label : (modifiable ? 'Affecter une vacation' : '');
    final avecInfo = titre.isEmpty ? corps : Tooltip(message: titre, child: corps);
    // Sans le droit d'écrire, la case se LIT mais ne s'ouvre pas : une commande interdite est ABSENTE.
    if (!modifiable) return avecInfo;
    return InkWell(borderRadius: BorderRadius.circular(4), onTap: () => _affecter(ctx, c, agent, jour, vacation), child: avecInfo);
  }

  // ---- Affectation d'une vacation de rotation -------------------------------------------------------------------------------------------------------

  void _affecter(BuildContext ctx, ContexteEcran c, Fiche agent, DateTime jour, Fiche? existant) {
    final col = c.magasin.collection('planning');
    final types = rhcTypesRotation(agent['fonction']);
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'type', libelle: 'Vacation', type: TypeChamp.select, requis: true, col: ColChamp.demi, options: [for (final t in types) OptionChamp(t.id, rhcLibelleRotation(t))]),
      const ChampDef(nom: 'observation', libelle: 'Observation', col: ColChamp.plein),
    ], existant != null ? {'type': existant['type'], 'observation': existant['observation']} : {'type': types.first.id});
    afficherModale<void>(ctx,
        titre: 'Rotation — ${agent['nomComplet']}',
        sousTitre: dateJour(jour),
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          DescListeSigh([
            ('Agent', agent['nomComplet']),
            ('Fonction', rhbFonctionLabel(agent['fonction'])),
            ('Date', dateJour(jour)),
            ('Vacation actuelle', existant != null ? rhbTypePlanningLabel(existant['type']) : 'Aucune'),
          ]),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              if (existant != null && c.droit.annuler)
                BoutonSigh(
                    libelle: 'Retirer',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () async {
                      final ok = await confirmerSigh(ctx,
                          titre: 'Retirer cette vacation ?',
                          message:
                              'La vacation est archivée, pas supprimée (RG-14) : elle reste consultable et l’opération est annulable. Le poste redevient vacant sur la rotation.',
                          libelleOk: 'Retirer',
                          dangereux: true);
                      if (!ok || !ctx.mounted) return;
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
                    // Le repos de 24 h qui suit une garde reste opposable ici comme au planning général : deux gardes consécutives pour un agent de sécurité sont refusées.
                    final conflit = rhcIncompatibiliteRotation(rhbActives(c, 'planning'), employeId: agent['id'], jour: jour, type: '${v['type']}');
                    if (conflit != null) {
                      ToastsSigh.afficher(ctx, 'Incompatibilité — le repos de 24 h qui suit une garde n’est pas respecté.',
                          type: TypeToast.erreur, detail: 'Garde déjà programmée le ${dateFR(DateTime.parse(conflit))} pour ${agent['nomComplet']}.');
                      return;
                    }
                    final obs = '${v['observation'] ?? ''}';
                    final fiche = <String, Object?>{
                      'type': v['type'],
                      if (obs.isNotEmpty || existant != null) 'observation': obs,
                      'date': iso(jour),
                      'employeId': agent['id'],
                      'employe': agent['nomComplet'],
                      'fonction': agent['fonction'],
                      'service': agent['service'],
                      'statut': 'validee',
                    };
                    fermer();
                    final VoidCallback annuler = existant != null ? col.mettreAJour(existant['id'], fiche) : col.inserer(fiche, prefixe: 'PLA').annuler;
                    ToastsSigh.afficher(ctx, 'Rotation enregistrée.',
                        type: TypeToast.succes, detail: '${agent['nomComplet']} — ${rhbTypePlanningLabel(v['type'])} le ${dateFR(jour)}', annuler: annuler);
                  }),
            ]);
  }

  // ---- Les agents ------------------------------------------------------------------------------------------------------------------------------------

  static List<ChampDef> _champsAgent() => const [
        ChampDef(nom: 'nomComplet', libelle: 'Nom et prénoms', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'fonction', libelle: 'Fonction', type: TypeChamp.select, requis: true, options: [OptionChamp('securite', 'Agent de sécurité'), OptionChamp('entretien', 'Agent d’entretien')]),
        ChampDef(nom: 'poste', libelle: 'Poste occupé'),
        ChampDef(nom: 'dateEmbauche', libelle: 'Date d’embauche', type: TypeChamp.date, requis: true),
        ChampDef(nom: 'salaireBase', libelle: 'Salaire de base (FCFA)', type: TypeChamp.nombre, requis: true),
        ChampDef(nom: 'telephone', libelle: 'Téléphone'),
      ];

  static num _nombre(Object? v) {
    final n = nombreOuZero(v);
    return n == n.roundToDouble() ? n.toInt() : n;
  }

  Widget _agents(BuildContext ctx, ContexteEcran c) {
    final col = c.magasin.collection('personnel');
    return TableauSigh(
      titre: 'Agents de sécurité et d’entretien',
      lignes: rhcAgentsRotation(rhcPersonnel(c)),
      taillePage: 15,
      nomExport: 'securite-entretien',
      actions: [
        if (c.droit.editer) BoutonSigh(libelle: 'Nouvel agent', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _saisir(ctx, c, null)),
      ],
      colonnes: [
        ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true, texte: (e) => '${e['matricule'] ?? ''}'),
        const ColonneTableau(cle: 'nomComplet', libelle: 'Agent'),
        ColonneTableau(
            cle: 'fonction',
            libelle: 'Fonction',
            texte: (e) => rhbFonctionLabel(e['fonction']),
            rendu: (_, e) => BadgeSigh(rhbFonctionLabel(e['fonction']), ton: e['fonction'] == 'securite' ? TonSigh.navy : TonSigh.info)),
        const ColonneTableau(cle: 'poste', libelle: 'Poste'),
        ColonneTableau(cle: 'dateEmbauche', libelle: 'Embauche', sansCoupure: true, texte: (e) => rhcDate(e['dateEmbauche'])),
        ColonneTableau(cle: 'salaireBase', libelle: 'Salaire', droite: true, texte: (e) => rhcMontant(e['salaireBase'])),
      ],
      actionsLigne: (_, e) => [
        if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _saisir(ctx, c, e)),
        if (c.droit.annuler) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(ctx, c, col, e)),
      ],
    );
  }

  void _saisir(BuildContext ctx, ContexteEcran c, Fiche? existant) {
    final col = c.magasin.collection('personnel');
    final ctl = ControleurFormulaire(_champsAgent(), existant != null ? rhcEnTexte(existant) : {'fonction': 'securite', 'dateEmbauche': iso(c.aujourdhui), 'salaireBase': '40000'});
    afficherModale<void>(ctx,
        titre: existant == null ? 'Nouvel agent de sécurité ou d’entretien' : 'Modifier l’enregistrement',
        sousTitre: existant == null ? 'Les champs marqués d’un astérisque sont obligatoires.' : '${existant['matricule'] ?? existant['id']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: existant == null ? 'Créer' : 'Enregistrer',
                  icone: existant == null ? LucideIcons.plus : LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final fiche = <String, Object?>{...v, 'salaireBase': _nombre(v['salaireBase'])};
                    fermer();
                    if (existant == null) {
                      // Sécurité, entretien et chauffeurs sont rattachés à la Direction : un seul intitulé de service. Le matricule SUIT la série du registre,
                      // archivés compris (E743 — `C.nextRef` repartait de SE-001 à chaque session).
                      final poste = '${fiche['poste'] ?? ''}'.isNotEmpty ? fiche['poste'] : rhbFonctionLabel(fiche['fonction']);
                      final r = col.inserer({
                        'statut': 'actif',
                        ...fiche,
                        'matricule': rhbReferenceSuivante('SE-', 3, [for (final e in col.toutes) {'reference': e['matricule']}]),
                        'service': 'Direction',
                        'poste': poste,
                        '_creePar': c.utilisateur,
                        '_creeLe': c.aujourdhui.toIso8601String(),
                      }, prefixe: 'PER');
                      ToastsSigh.afficher(ctx, 'Agent créé.', type: TypeToast.succes, annuler: r.annuler);
                    } else {
                      final annuler = col.mettreAJour(existant['id'], fiche);
                      ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler);
                    }
                  }),
            ]);
  }

  Future<void> _archiver(BuildContext ctx, ContexteEcran c, CollectionMagasin col, Fiche e) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Archiver cet enregistrement ?',
        message: 'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable. L’opération est journalisée et peut être annulée.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = col.archiver(e['id']);
    rhcMotifArchivage(c, 'Employé', '${e['matricule'] ?? e['id']}', motif);
    ToastsSigh.afficher(ctx, 'Enregistrement archivé.', type: TypeToast.succes, annuler: annuler);
  }

  // ---- La charge de rotation, vue d'ensemble ---------------------------------------------------------------------------------------------------------

  Widget _graphiques(List<Fiche> planning) {
    final vacations = rhcVacationsRotation(planning);
    if (vacations.isEmpty) {
      return const CarteSigh(titre: 'Statistiques de rotation', child: VideSigh('Aucune vacation de sécurité ou d’entretien enregistrée.', icone: LucideIcons.shield));
    }
    final parAgent = rhcGrouper(vacations, (v) => '${v['employe']}');
    final noms = trierPar(parAgent.keys.toList(), (k) => parAgent[k]!.length, descendant: true);
    final parType = rhcGrouper(vacations, (v) => '${v['type']}');
    final parFonction = rhcGrouper(vacations, (v) => '${v['fonction']}');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      rhbTroisCartes([
        CarteSigh(
            titre: 'Vacations par agent',
            child: GraphiqueBarres(horizontal: true, hauteur: 260, etiquettes: noms, series: [SerieGraphique('Vacations', [for (final n in noms) parAgent[n]!.length], couleur: rhbTonNavy)])),
        CarteSigh(
            titre: 'Répartition par type de poste',
            child: GraphiqueAnneau(trou: 0, hauteur: 260, etiquettes: [for (final k in parType.keys) rhbTypePlanningLabel(k)], valeurs: [for (final l in parType.values) l.length])),
        CarteSigh(
            titre: 'Sécurité et entretien',
            child: GraphiqueAnneau(
                hauteur: 260,
                etiquettes: [for (final k in parFonction.keys) rhbFonctionLabel(k)],
                valeurs: [for (final l in parFonction.values) l.length],
                couleurs: const [rhbTonNavy, Color(0xFF6C9ED4)])),
      ]),
      const SizedBox(height: 16),
      const NoteSigh(
          'Les repos sont exclus de ces comptages : ils figurent à la rotation mais ne sont pas des postes tenus. Un écart marqué entre agents d’une même fonction signale une rotation déséquilibrée — c’est précisément ce que le cycle à trois doit éviter.'),
    ]);
  }

  void _imprimerPlanning(BuildContext ctx, ContexteEcran c, List<Fiche> agents, List<Fiche> planning, List<DateTime> jours) {
    final lignes = <Fiche>[
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
    ];
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Planning des agents de sécurité et d’entretien',
            sousTitre: 'Du ${dateFR(jours.first)} au ${dateFR(jours.last)}',
            cartouche: [
              ('Période', '${dateFR(jours.first)} – ${dateFR(jours.last)}'),
              ('Agents', nombre(agents.length)),
              ('Établi par', c.utilisateur),
              ('Date', dateFR(c.aujourdhui)),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Agent', valeur: (r) => r['agent']),
                ColonneEtat(libelle: 'Fonction', valeur: (r) => r['fonction']),
                for (final (i, j) in jours.indexed) ColonneEtat(libelle: '${_jour2(j)} ${j.day}', valeur: (r) => r['j$i']),
              ], lignes: lignes)),
            ],
            signatures: const [Signature('Le Chef de service', nom: 'OURTCHA TEREYAMA'), rhbSignDaf]));
  }
}
