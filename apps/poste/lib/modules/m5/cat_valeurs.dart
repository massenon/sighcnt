import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cat_commun.dart';

const _noteFermeture =
    'Une variable d’accompagnement — réactif, lot, expiration, commentaire — se ferme sans se supprimer : le jour où un changement de réactif rend l’interprétation inutile, elle disparaît du compte rendu et les résultats déjà rendus la conservent. C’est la demande du biologiste, mot pour mot : « on peut les fermer ».';

String _enTexte(Object? v) => v == null ? '' : (v is num ? catNombreJs(v) : '$v');

/// `m5-valeurs-reference` — « Valeurs de référence » : les bornes de normalité, l'unité et le type de chaque variable de résultat, modifiables
/// (elles dépendent du réactif), puis les plages par lot de réactif, VERSIONNÉES par date d'entrée en service : un résultat se compare aux bornes du lot
/// en service à SA date, relever une borne ne change pas un compte rendu rendu. Trois provenances qui ne se confondent jamais : documentée (fiche du
/// 21/08/2026), validée par le biologiste (01/09/2026), à valider. Une variable d'accompagnement se FERME, elle ne se supprime pas.
class EcranValeursReference extends StatefulWidget with EcranMaquette {
  const EcranValeursReference({super.key});

  @override
  String get titre => 'Valeurs de référence';

  @override
  String get description =>
      'Bornes de normalité, unités et type de chaque variable de résultat. Modifiables : elles dépendent du réactif.';

  @override
  String get regle =>
      'Les bornes dépendent du réactif et de l’automate : elles se modifient ici, sans toucher au code. Celles reprises de la fiche de résultats du 21/08/2026 sont marquées documentées ; les valeurs usuelles suppléées ont reçu la validation écrite du biologiste médical le 01/09/2026 et le portent — les deux provenances ne se confondent jamais. Une variable créée ou modifiée depuis repart « à valider ».';

  @override
  State<EcranValeursReference> createState() => _EtatValeurs();
}

class _EtatValeurs extends State<EcranValeursReference> {
  late final ControleurFormulaire _section;
  late final ControleurFormulaire _etat;
  late ControleurFormulaire _examen;
  String _sectionExamen = '';
  bool _pret = false;

  ChampDef _def(String nom, String libelle, List<OptionChamp> options) =>
      ChampDef(
          nom: nom,
          libelle: libelle,
          type: TypeChamp.select,
          options: options,
          col: ColChamp.plein);

  void _maj() {
    if (mounted) setState(() {});
  }

  List<OptionChamp> _optionsExamen(Magasin m, String section) => [
        const OptionChamp('', 'Tous les examens'),
        for (final e in catExamensDeSection(
            m.collection('examensLabo').actives, section))
          OptionChamp('${e['code']}', '${e['designation']}')
      ];

  void _nouvelExamen(Magasin m, String section) {
    if (_pret) {
      _examen.removeListener(_maj);
      _examen.dispose();
    }
    _sectionExamen = section;
    _examen = champUnique(
        _def('examen', 'Examen', _optionsExamen(m, section)), '');
    _examen.addListener(_maj);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    final m = ContexteEcran.of(context).magasin;
    _section = champUnique(
        _def('section', 'Section', [
          const OptionChamp('', 'Toutes les sections'),
          for (final s in catSections) OptionChamp(s.id, s.libelle)
        ]),
        '');
    _etat = champUnique(
        _def('etat', 'État', const [
          OptionChamp('', 'Toutes les variables'),
          OptionChamp('documente', 'Documentées'),
          OptionChamp('valider', 'À valider'),
          OptionChamp('ferme', 'Fermées'),
        ]),
        '');
    _nouvelExamen(m, '');
    _pret = true;
    _section.addListener(_surSection);
    _etat.addListener(_maj);
  }

  /// Changer de section REPART des examens de cette section (la liste se refait, « Tous les examens » est de nouveau retenu).
  void _surSection() {
    final m = ContexteEcran.of(context).magasin;
    final s = '${_section['section']}';
    if (s != _sectionExamen) _nouvelExamen(m, s);
    _maj();
  }

  @override
  void dispose() {
    if (_pret) {
      _section.removeListener(_surSection);
      _etat.removeListener(_maj);
      _examen.removeListener(_maj);
      _section.dispose();
      _etat.dispose();
      _examen.dispose();
    }
    super.dispose();
  }

  List<Fiche> _lignes(Magasin m) => catLignesVariables(
      m.collection('variablesLabo').toutes,
      section: '${_section['section']}',
      examen: '${_examen['examen']}',
      etat: '${_etat['etat']}');

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // Affichage
  // -------------------------------------------------------------------------------------------------------------------------------------------

  Widget _etatCellule(Fiche v) => switch (catProvenance(v)) {
        'fermée' => const BadgeSigh('Fermée', ton: TonSigh.neutre),
        'à valider' => const BadgeSigh('À valider', ton: TonSigh.attention),
        'validée' => const BadgeSigh('Validée (biologiste)', ton: TonSigh.info),
        _ => const BadgeSigh('Documentée', ton: TonSigh.succes),
      };

  static const _libelleEtat = {
    'fermée': 'Fermée',
    'à valider': 'À valider',
    'validée': 'Validée (biologiste)',
    'documentée': 'Documentée'
  };

  List<ColonneTableau> _colonnes(Magasin m) {
    String unite(Fiche v) =>
        catSymboleUnite(m.collection('unitesLabo').toutes, v['unite']);
    return [
      ColonneTableau(
          cle: 'examenLibelle',
          libelle: 'Examen',
          texte: (v) =>
              '${v['examenLibelle'] ?? ''} ${catLibelleSection(v['section'])}',
          rendu: (_, v) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${v['examenLibelle'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: styleCat(
                            couleur: JetonsShell.slate800,
                            poids: FontWeight.w500)),
                    Text(catLibelleSection(v['section']),
                        style: styleCat(
                            taille: 12, couleur: JetonsShell.slate400)),
                  ])),
      ColonneTableau(
          cle: 'libelle',
          libelle: 'Variable',
          texte: (v) =>
              '${_enfant(v) ? '↳ ' : ''}${v['libelle'] ?? ''} ${v['code'] ?? ''}',
          rendu: (_, v) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                        padding: EdgeInsets.only(left: _enfant(v) ? 16 : 0),
                        child: Text(
                            '${_enfant(v) ? '↳ ' : ''}${v['libelle'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            style: styleCat(
                                couleur: _enfant(v)
                                    ? JetonsShell.slate600
                                    : JetonsShell.slate800,
                                poids: _enfant(v)
                                    ? FontWeight.w400
                                    : FontWeight.w500))),
                    Text('${v['code'] ?? ''}',
                        style: monoCode.copyWith(
                            color: JetonsShell.slate400,
                            fontWeight: FontWeight.w400)),
                  ])),
      ColonneTableau(
          cle: 'type',
          libelle: 'Type',
          texte: (v) => catLibelleType(v['type']),
          rendu: (_, v) => BadgeSigh(catLibelleType(v['type']),
              ton: v['accompagnement'] == true
                  ? TonSigh.neutre
                  : TonSigh.info)),
      ColonneTableau(
          cle: 'unite',
          libelle: 'Unité',
          droite: true,
          texte: unite,
          rendu: (_, v) => Text(unite(v),
              textAlign: TextAlign.right,
              style: monoCode.copyWith(
                  color: JetonsShell.slate700, fontWeight: FontWeight.w400))),
      ColonneTableau(
          cle: 'reference',
          libelle: 'Référence',
          droite: true,
          valeur: catLibelleReference,
          texte: catLibelleReference,
          rendu: (_, v) {
            final t = catLibelleReference(v);
            return t.isEmpty
                ? Text('—',
                    textAlign: TextAlign.right,
                    style: styleCat(couleur: JetonsShell.slate300))
                : Text(t,
                    textAlign: TextAlign.right,
                    style: styleCat(
                        couleur: catProvenance(v) == 'à valider'
                            ? JetonsShell.warning700
                            : JetonsShell.slate700));
          }),
      ColonneTableau(
          cle: 'etat',
          libelle: 'État',
          droite: true,
          valeur: catProvenance,
          texte: (v) => _libelleEtat[catProvenance(v)]!,
          rendu: (_, v) => _etatCellule(v)),
    ];
  }

  static bool _enfant(Fiche v) =>
      v['parent'] != null && v['parent'] != '' && v['parent'] != false;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final variables = c.magasin.collection('variablesLabo');
    final plages = c.magasin.collection('plagesReactif');
    return ListenableBuilder(
      listenable: Listenable.merge([
        variables,
        plages,
        c.magasin.collection('unitesLabo'),
        c.magasin.collection('examensLabo')
      ]),
      builder: (context, _) {
        final lignes = _lignes(c.magasin);
        final k = catKpisVariables(variables.actives);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                commande(_section, largeur: 220),
                commande(_examen, largeur: 300),
                commande(_etat, largeur: 220),
                BoutonSigh(
                    libelle: 'Imprimer le référentiel',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _imprimer(context, lignes)),
              ])),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Variables paramétrées',
                valeur: nombre(k.variables),
                icone: LucideIcons.target),
            KpiSigh(
                libelle: 'Documentées',
                valeur: nombre(k.documentees),
                icone: LucideIcons.fileCheck2,
                ton: TonSigh.succes,
                indice: 'Fiche de résultats du 21/08/2026'),
            KpiSigh(
                libelle: 'Validées par le biologiste',
                valeur: nombre(k.validees),
                icone: LucideIcons.shieldCheck,
                ton: TonSigh.info,
                indice: 'Validation écrite du 01/09/2026'),
            KpiSigh(
                libelle: 'Variables fermées',
                valeur: nombre(k.fermees),
                icone: LucideIcons.eyeOff,
                ton: TonSigh.neutre,
                indice: 'Retirées du compte rendu'),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(_noteFermeture, icone: LucideIcons.eyeOff),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Variables et valeurs de référence',
            colonnes: _colonnes(c.magasin),
            lignes: lignes,
            taillePage: 25,
            nomExport: 'valeurs-reference',
            actions: [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Nouvelle variable',
                    icone: LucideIcons.plus,
                    taille: TailleBouton.sm,
                    onPressed: () => _saisirVariable(context, null)),
            ],
            actionsLigne: (ctx, v) => [
              if (c.droit.editer) ...[
                BoutonIcone(
                    icone: LucideIcons.pencil,
                    libelle: 'Modifier les paramètres',
                    onPressed: () => _saisirVariable(context, v)),
                if (v['retractable'] == true)
                  BoutonIcone(
                      icone: v['actif'] == false
                          ? LucideIcons.eye
                          : LucideIcons.eyeOff,
                      libelle: v['actif'] == false
                          ? 'Rouvrir cette variable'
                          : 'Fermer cette variable',
                      onPressed: () => _basculer(context, v)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _tablePlages(context, c, plages),
        ]);
      },
    );
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // Variables : création, modification, fermeture
  // -------------------------------------------------------------------------------------------------------------------------------------------

  List<ChampDef> _champsVariable(Magasin m) => [
        ChampDef(
            nom: 'examen',
            libelle: 'Examen',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [
              for (final e in m.collection('examensLabo').actives)
                OptionChamp('${e['code']}', '${e['designation']}')
            ]),
        const ChampDef(nom: 'code', libelle: 'Code de la variable', requis: true),
        const ChampDef(
            nom: 'libelle',
            libelle: 'Intitulé',
            requis: true,
            col: ColChamp.plein),
        ChampDef(
            nom: 'type',
            libelle: 'Type de résultat',
            type: TypeChamp.select,
            requis: true,
            aide: 'Le type commande la saisie et le contrôle de normalité.',
            options: [
              for (final t in catTypesVariable) OptionChamp(t.id, t.libelle)
            ]),
        ChampDef(
            nom: 'unite',
            libelle: 'Unité',
            type: TypeChamp.select,
            options: [
              for (final u in m.collection('unitesLabo').actives)
                OptionChamp('${u['id']}', '${u['symbole']} — ${u['libelle']}')
            ]),
        const ChampDef(
            nom: 'min',
            libelle: 'Borne basse',
            type: TypeChamp.nombre,
            aide: 'Vide si la référence n’a pas de borne basse'),
        const ChampDef(
            nom: 'max',
            libelle: 'Borne haute',
            type: TypeChamp.nombre,
            aide: 'Vide si la référence n’a pas de borne haute'),
        const ChampDef(
            nom: 'normal',
            libelle: 'Issue attendue',
            aide: 'Pour un résultat qualitatif : Négatif, Absent…'),
        const ChampDef(
            nom: 'decimales', libelle: 'Décimales', type: TypeChamp.nombre),
        const ChampDef(
            nom: 'ordre',
            libelle: 'Rang de rendu',
            type: TypeChamp.nombre,
            requis: true),
        const ChampDef(
            nom: 'parent',
            libelle: 'Sous-variable de',
            aide: 'Code de la variable parente, si applicable'),
        const ChampDef(
            nom: 'regle',
            libelle: 'Référence exprimée par une règle',
            col: ColChamp.plein,
            aide:
                'Quand la borne n’est pas un nombre — par exemple « inférieure à la moitié de la glycémie ».'),
      ];

  void _saisirVariable(BuildContext ctx, Fiche? v) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final creation = v == null;
    final ctl = ControleurFormulaire(
        _champsVariable(m),
        creation
            ? {'type': 'numerique', 'ordre': '99', 'unite': 'sans'}
            : {for (final e in v.entries) e.key: _enTexte(e.value)});
    afficherModale<void>(ctx,
        titre: creation
            ? 'Nouvelle variable de résultat'
            : 'Paramètres de « ${v['libelle']} »',
        sousTitre: creation ? null : '${v['examenLibelle'] ?? ''}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!creation && v['aValider'] != true)
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoteSigh(
                    'Cette borne est reprise de la fiche de résultats du 21/08/2026. La modifier fera diverger le logiciel du document de référence — à ne faire que sur décision du biologiste, par exemple après un changement de réactif.',
                    ton: TonSigh.attention,
                    icone: LucideIcons.fileCheck2)),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: creation ? 'Créer' : 'Enregistrer',
                  icone: creation ? LucideIcons.plus : LucideIcons.check,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) return;
                    final col = m.collection('variablesLabo');
                    final val = catTransformVariable(saisie,
                        existante: v,
                        examensActifs: m.collection('examensLabo').actives,
                        utilisateur: c.utilisateur,
                        maintenant: c.aujourdhui);
                    if (creation) {
                      col.inserer({'statut': 'actif', ...val}, prefixe: 'VAR');
                    } else {
                      col.mettreAJour(v['id'], val);
                    }
                    m.journaliser(
                        creation
                            ? 'Création d’une variable de résultat'
                            : 'Modification d’une valeur de référence',
                        'M5',
                        'Variable',
                        '${val['code']}',
                        v == null ? null : {'min': v['min'], 'max': v['max']},
                        {'min': val['min'], 'max': val['max']});
                    fermer();
                    final ref = catLibelleReference(val);
                    ToastsSigh.afficher(
                        ctx, creation ? 'Variable créée.' : 'Paramètres enregistrés.',
                        type: TypeToast.succes,
                        detail:
                            '${val['libelle']} — ${ref.isEmpty ? 'sans référence' : ref}');
                  }),
            ]);
  }

  /// Fermer / rouvrir : la variable n'est jamais supprimée, elle disparaît des comptes rendus À VENIR.
  Future<void> _basculer(BuildContext ctx, Fiche v) async {
    final c = ContexteEcran.of(ctx);
    final fermer = v['actif'] != false;
    final ok = await confirmerSigh(ctx,
        titre: fermer
            ? 'Fermer « ${v['libelle']} » ?'
            : 'Rouvrir « ${v['libelle']} » ?',
        message: fermer
            ? 'Cette variable disparaîtra des nouvelles saisies et des comptes rendus à venir. Les résultats déjà rendus la conservent — un compte rendu ancien doit rester reproductible.\n\nC’est le geste prévu pour un changement de réactif qui rend l’interprétation inutile. La variable n’est pas supprimée : elle se rouvre d’un clic.'
            : 'La variable réapparaîtra dans les saisies et les comptes rendus à venir.',
        libelleOk: fermer ? 'Fermer la variable' : 'Rouvrir',
        dangereux: fermer);
    if (!ok || !ctx.mounted) return;
    c.magasin.collection('variablesLabo').mettreAJour(
        v['id'],
        catPatchBascule(v,
            utilisateur: c.utilisateur, maintenant: c.aujourdhui));
    ToastsSigh.afficher(ctx, fermer ? 'Variable fermée.' : 'Variable rouverte.',
        type: TypeToast.succes,
        detail: fermer
            ? 'Retirée des comptes rendus à venir ; les anciens la conservent.'
            : null);
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // Plages par lot de réactif
  // -------------------------------------------------------------------------------------------------------------------------------------------

  Widget _tablePlages(BuildContext ctx, ContexteEcran c, CollectionMagasin plages) =>
      TableauSigh(
        titre: 'Plages de référence par lot de réactif',
        colonnes: [
          ColonneTableau(
              cle: 'variableLibelle',
              libelle: 'Variable',
              texte: (p) => '${p['variableLibelle'] ?? ''} ${p['examenLibelle'] ?? ''}',
              rendu: (_, p) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${p['variableLibelle'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            style: styleCat(
                                couleur: JetonsShell.slate800,
                                poids: FontWeight.w500)),
                        Text('${p['examenLibelle'] ?? ''}',
                            style: styleCat(
                                taille: 12, couleur: JetonsShell.slate400)),
                      ])),
          ColonneTableau(
              cle: 'lot',
              libelle: 'Lot du réactif',
              texte: (p) => '${p['lot'] ?? ''}',
              rendu: (_, p) => Text('${p['lot'] ?? ''}',
                  style: monoCode.copyWith(
                      fontSize: 14, height: 20 / 14, color: JetonsShell.slate700, fontWeight: FontWeight.w400))),
          ColonneTableau(
              cle: 'bornes',
              libelle: 'Bornes du lot',
              droite: true,
              texte: catBornesPlage,
              valeur: catBornesPlage),
          ColonneTableau(
              cle: 'dateDebut',
              libelle: 'En service depuis',
              texte: (p) => _dateFr(p['dateDebut']),
              valeur: (p) => p['dateDebut']),
          const ColonneTableau(cle: 'source', libelle: 'Source'),
        ],
        lignes: plages.actives,
        taillePage: 10,
        nomExport: 'plages-reactif',
        messageVide:
            'Aucune plage par lot enregistrée : les bornes des variables ci-dessus font foi. À l’arrivée d’un lot dont la notice déplace les bornes, l’enregistrer ici — les saisies à venir s’y compareront, les résultats déjà rendus gardent leurs références.',
        actions: [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Nouvelle plage de lot',
                icone: LucideIcons.plus,
                taille: TailleBouton.sm,
                onPressed: () => _saisirPlage(ctx, null)),
        ],
        actionsLigne: (context, p) => [
          if (c.droit.editer) ...[
            BoutonIcone(
                icone: LucideIcons.pencil,
                libelle: 'Modifier la plage',
                onPressed: () => _saisirPlage(ctx, p)),
            BoutonIcone(
                icone: LucideIcons.archive,
                libelle: 'Archiver la plage',
                onPressed: () => _archiverPlage(ctx, p)),
          ],
        ],
      );

  static String _dateFr(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}');
    return d == null ? '' : dateFR(d);
  }

  void _saisirPlage(BuildContext ctx, Fiche? p) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final creation = p == null;
    final numeriques = catVariablesDePlage(m.collection('variablesLabo').actives);
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'variableId',
          libelle: 'Variable concernée',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            for (final v in numeriques)
              OptionChamp('${v['id']}', '${v['examenLibelle']} — ${v['libelle']}')
          ]),
      const ChampDef(
          nom: 'lot',
          libelle: 'Lot du réactif',
          requis: true,
          aide: 'Tel qu’il figure sur le flacon et la notice'),
      const ChampDef(
          nom: 'dateDebut',
          libelle: 'En service depuis le',
          type: TypeChamp.date,
          requis: true),
      const ChampDef(
          nom: 'min', libelle: 'Borne basse du lot', type: TypeChamp.nombre),
      const ChampDef(
          nom: 'max', libelle: 'Borne haute du lot', type: TypeChamp.nombre),
      const ChampDef(
          nom: 'source',
          libelle: 'Source des bornes',
          requis: true,
          col: ColChamp.plein,
          aide:
              'La notice du réactif, la validation de méthode… Une borne sans origine est le problème qu’on cherche à éviter.'),
    ],
        creation
            ? {'dateDebut': iso(DateTime(c.aujourdhui.year, c.aujourdhui.month, c.aujourdhui.day))}
            : {for (final e in p.entries) e.key: _enTexte(e.value)});
    afficherModale<void>(ctx,
        titre: creation
            ? 'Nouvelle plage par lot de réactif'
            : 'Plage du lot ${p['lot']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: NoteSigh(
                  'La plage s’applique aux demandes à compter de sa date d’entrée en service. Les résultats déjà rendus gardent les références de leur époque — c’est le même principe que la grille des primes datée.',
                  icone: LucideIcons.calendar)),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: creation ? 'Enregistrer la plage' : 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) return;
                    final val = catTransformPlage(saisie, numeriques);
                    if (catRefuserPlage(val) case final motif?) {
                      ToastsSigh.afficher(ctx, motif,
                          type: TypeToast.erreur,
                          detail:
                              'Renseigner au moins une borne, ou ne pas enregistrer de plage.');
                      return;
                    }
                    final col = m.collection('plagesReactif');
                    if (creation) {
                      col.inserer({'statut': 'actif', ...val}, prefixe: 'PLG');
                    } else {
                      col.mettreAJour(p['id'], val);
                    }
                    m.journaliser(
                        creation ? 'Plage par lot créée' : 'Plage par lot modifiée',
                        'M5',
                        'PlageReactif',
                        '${val['lot']}',
                        p == null ? null : {'min': p['min'], 'max': p['max']},
                        {'min': val['min'], 'max': val['max']});
                    fermer();
                    ToastsSigh.afficher(
                        ctx, creation ? 'Plage enregistrée.' : 'Plage modifiée.',
                        type: TypeToast.succes,
                        detail:
                            '${val['variableLibelle'] ?? ''} — lot ${val['lot']}, en service depuis le ${_dateFr(val['dateDebut'])}');
                  }),
            ]);
  }

  Future<void> _archiverPlage(BuildContext ctx, Fiche p) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Archiver la plage du lot ${p['lot']} ?',
        message:
            'Les saisies à venir se compareront de nouveau aux bornes de la variable (ou à la plage antérieure). Les résultats déjà rendus ne changent pas.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    ContexteEcran.of(ctx).magasin.collection('plagesReactif').archiver(p['id']);
    ToastsSigh.afficher(ctx, 'Plage archivée.', type: TypeToast.succes);
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // Impression
  // -------------------------------------------------------------------------------------------------------------------------------------------

  void _imprimer(BuildContext ctx, List<Fiche> lignes) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final unites = m.collection('unitesLabo').toutes;
    final rows = trierPar([...lignes], (v) => v['examenLibelle']);
    String provenance(Fiche v) => v['aValider'] == true
        ? 'À valider'
        : (_valideeParBiologiste(v)
            ? 'Validée (biologiste, 01/09/2026)'
            : 'Documentée');
    final filtres = <(String, String)>[
      if ('${_section['section']}'.isNotEmpty)
        (
          'Section',
          catLibelleSection(_section['section'])
        ),
      if ('${_examen['examen']}'.isNotEmpty)
        (
          'Examen',
          '${m.collection('examensLabo').actives.where((e) => e['code'] == _examen['examen']).map((e) => e['designation']).firstOrNull ?? _examen['examen']}'
        ),
      if ('${_etat['etat']}'.isNotEmpty)
        (
          'État',
          const {
            'documente': 'Documentées',
            'valider': 'À valider',
            'ferme': 'Fermées'
          }['${_etat['etat']}']!
        ),
    ];
    afficherApercu(
        ctx,
        pieceCat(ctx,
            titre: 'Référentiel des valeurs de référence',
            sousTitre:
                'Laboratoire d’analyses biomédicales — situation au ${dateFR(c.aujourdhui)}',
            cartouche: [
              ('Variables', nombre(rows.length)),
              ('Documentées', nombre(rows.where((v) => v['aValider'] != true).length)),
              ('À valider', nombre(rows.where((v) => v['aValider'] == true).length)),
              ('Établi par', c.utilisateur),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            filtres: filtres,
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(
                    libelle: 'Section',
                    valeur: (v) => catLibelleSection(v['section'])),
                ColonneEtat(libelle: 'Examen', valeur: (v) => v['examenLibelle']),
                ColonneEtat(libelle: 'Variable', valeur: (v) => v['libelle']),
                ColonneEtat(libelle: 'Type', valeur: (v) => catLibelleType(v['type'])),
                ColonneEtat(
                    libelle: 'Unité',
                    droite: true,
                    valeur: (v) => catSymboleUnite(unites, v['unite'])),
                ColonneEtat(
                    libelle: 'Références',
                    droite: true,
                    valeur: (v) {
                      final r = catLibelleReference(v);
                      return r.isEmpty ? '—' : r;
                    }),
                ColonneEtat(libelle: 'Provenance', valeur: provenance),
              ], lignes: rows)),
              const BlocTexte(
                  'Les valeurs marquées « documentées » sont reprises de la fiche de résultats de la clinique éditée le 21/08/2026. Celles marquées « à valider » sont des valeurs usuelles de la biologie médicale, portées à titre d’attente : elles dépendent du réactif et de l’automate employés et doivent être arrêtées par le biologiste médical avant mise en service.',
                  italique: true),
            ],
            signatures: const [
              Signature('Le Biologiste médical'),
              Signature('Le Directeur Médical', nom: directeurMedicalLabo),
            ]));
  }
}

/// Une variable portant `valideLe` est « validée par le biologiste » (JS : la valeur est vraie).
bool _valideeParBiologiste(Fiche v) =>
    v['valideLe'] != null && v['valideLe'] != '' && v['valideLe'] != false;
