import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpb_commun.dart';

/// `m12-compte-resultat` (feuillet 7/51) et `m12-flux-tresorerie` (feuillet 8/51) — la liasse déposée à la DGI, déposée OU calculée.
///
/// Les écrans reproduisent LE FORMULAIRE : mêmes références, mêmes libellés, même ordre, mêmes sous-totaux, mêmes colonnes — un comptable rapproche
/// l'écran du dépôt ligne à ligne. DEUX sources, JAMAIS dans la même colonne : « déposé » CITE `cpbLiasse` ; « calculé » vient des écritures
/// VALIDÉES (préfixe de compte le plus long), et reste « — » là où le journal ne porte rien. Les règles sont dans le domaine (`cpb_feuillets.dart`).
///
/// Écart E770 : le sélecteur d'exercice de la coque (`SIGH.exercice`) n'est pas porté (E717) ; les écrans gardent le leur, comme la maquette, et la
/// liste d'exercices est celle du journal (année de l'horloge comprise) plus l'exercice déposé.
/// Écart E779 : la pièce A4 du poste n'a qu'UNE rangée d'en-tête de colonnes (la maquette en imprime deux, avec fusions) : la source de chaque colonne
/// (« calculé — arrêté au … » / « déposé — liasse … ») est portée par l'intitulé de colonne et par le cartouche.
abstract class _EcranFeuillet extends StatefulWidget with EcranMaquette {
  const _EcranFeuillet({super.key});

  /// `resultat` ou `flux`.
  String get genre;

  @override
  State<_EcranFeuillet> createState() => _EtatFeuillet();
}

class EcranCompteResultat extends _EcranFeuillet {
  const EcranCompteResultat({super.key});

  @override
  String get genre => 'resultat';

  @override
  String get titre => 'Compte de résultat';

  @override
  String get description =>
      'Le compte de résultat au format du feuillet 7/51 de la liasse DGI : déposé ou calculé depuis le journal.';

  @override
  String get regle =>
      'L’écran reproduit le formulaire déposé le 15/05/2026 (feuillet 7/51) : références TA à XI, libellés, colonne (2), notes et sous-totaux, au même ordre. Un exercice déposé se cite ; un exercice du journal se calcule — chaque écriture validée va à la ligne de son compte SYSCOHADA, et les sous-totaux suivent les formules imprimées sur le formulaire. Seules les écritures validées sont retenues, et le nombre de brouillons écartés est annoncé.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Tableau des flux',
          icone: LucideIcons.arrowLeftRight,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m12-flux-tresorerie')),
      BoutonSigh(
          libelle: 'Seuil de rentabilité',
          icone: LucideIcons.target,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m12-seuil-rentabilite')),
    ];
  }
}

class EcranFluxTresorerie extends _EcranFeuillet {
  const EcranFluxTresorerie({super.key});

  @override
  String get genre => 'flux';

  @override
  String get titre => 'Tableau des flux de trésorerie';

  @override
  String get description =>
      'Le tableau des flux au format du feuillet 8/51 de la liasse DGI : déposé ou calculé depuis le journal, contrôle compris.';

  @override
  String get regle =>
      'L’écran reproduit le formulaire déposé (feuillet 8/51) : trésorerie au 1er janvier (ZA), flux opérationnels (FA à FE, ZB), d’investissement (FF à FJ, ZC), de financement (FK à FQ, ZD à ZF), variation (ZG) et trésorerie au 31 décembre (ZH). Un exercice du journal se calcule par la méthode indirecte et se termine par le contrôle du formulaire — trésorerie-actif moins trésorerie-passif. Un écart ne se corrige pas : il nomme les comptes que le tableau ne classe pas. Les écarts internes du document déposé sont signalés, jamais arbitrés.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Compte de résultat',
          icone: LucideIcons.chartNoAxesCombined,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m12-compte-resultat')),
      BoutonSigh(
          libelle: 'Bilan d’ouverture',
          icone: LucideIcons.calendarPlus,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m12-ouverture')),
    ];
  }
}

class _EtatFeuillet extends State<_EcranFeuillet> {
  ControleurFormulaire? _exercice, _arrete;
  String _dernierExercice = '';

  bool get _resultat => widget.genre == 'resultat';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_exercice != null) return;
    final c = ContexteEcran.of(context);
    final annees = cpbExercicesDuJournal(ecrituresToutes(c), c.aujourdhui);
    _exercice = champUnique(
        ChampDef(nom: 'exercice', libelle: 'Exercice', type: TypeChamp.select, col: ColChamp.plein, requis: true, options: [
          for (final a in annees) OptionChamp('$a', 'Exercice $a — calculé depuis le journal'),
          OptionChamp('depose', 'Exercice $cpbExerciceN — liasse déposée (${cpbDepot['code']})'),
        ]),
        '${c.aujourdhui.year}');
    _dernierExercice = '${c.aujourdhui.year}';
    _arrete = champUnique(ChampDef(nom: 'arrete', libelle: 'Arrêté au', type: TypeChamp.date, col: ColChamp.plein), iso(c.aujourdhui));
    _exercice!.addListener(_surExercice);
    _arrete!.addListener(_rafraichir);
  }

  /// Changer d'exercice replace la date d'arrêt : le jour même pour l'exercice en cours, le 31 décembre pour un exercice passé.
  void _surExercice() {
    final v = '${_exercice!['exercice']}';
    if (v == _dernierExercice) return;
    _dernierExercice = v;
    if (v != 'depose') {
      final c = ContexteEcran.of(context);
      final a = int.parse(v);
      _arrete!.poser('arrete', a == c.aujourdhui.year ? iso(c.aujourdhui) : '$a-12-31');
    }
    _rafraichir();
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _exercice?.removeListener(_surExercice);
    _arrete?.removeListener(_rafraichir);
    _exercice?.dispose();
    _arrete?.dispose();
    super.dispose();
  }

  List<CpbColonne> _colonnes(ContexteEcran c) {
    final choix = '${_exercice!['exercice']}';
    final arrete = choix == 'depose' ? null : DateTime.tryParse('${_arrete!['arrete'] ?? ''}');
    return cpbColonnesFeuillet(widget.genre, choix, arrete, ecrituresToutes(c));
  }

  List<CpbLigneFormulaire> get _lignes => _resultat ? cpbLignesResultat : cpbLignesFlux;

  // --- Rendu du formulaire ---------------------------------------------------------------------------------------------------------------------

  static const _bord = BorderSide(color: JetonsShell.slate200);

  Widget _cel(Widget w, {Alignment al = Alignment.centerLeft, Color? fond}) => Container(
      color: fond,
      alignment: al,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: w);

  Widget _txt(String s, {bool gras = false, bool italique = false, Color couleur = JetonsShell.slate800, double taille = 14, bool mono = false}) => Text(s,
      style: TextStyle(
          color: couleur,
          fontSize: taille,
          height: 20 / 14,
          fontWeight: gras ? FontWeight.w600 : FontWeight.w400,
          fontStyle: italique ? FontStyle.italic : FontStyle.normal,
          fontFamily: mono ? 'monospace' : null,
          fontFeatures: const [FontFeature.tabularFigures()]));

  Widget _montant(CpbColonne col, CpbLigneFormulaire l) {
    final s = cpbMontantFeuillet(col, l);
    if (s == null) return const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 14, height: 20 / 14));
    final v = col.valeurs[l.cle] ?? 0;
    return _txt(s, gras: l.t != null, couleur: v < 0 ? JetonsShell.danger700 : JetonsShell.slate800);
  }

  Widget _formulaire(List<CpbColonne> cols) {
    final nbFixes = _resultat ? 5 : 4;
    final largeurs = <int, TableColumnWidth>{
      0: const FixedColumnWidth(56),
      1: const FlexColumnWidth(1),
      2: const FixedColumnWidth(40),
      if (_resultat) 3: const FixedColumnWidth(48),
      nbFixes - 1: const FixedColumnWidth(56),
      nbFixes: const FixedColumnWidth(190),
      nbFixes + 1: const FixedColumnWidth(190),
    };
    TableRow tete1() => TableRow(decoration: const BoxDecoration(color: JetonsShell.slate100), children: [
          _cel(_txt('RÉF', gras: true, couleur: JetonsShell.slate700), al: Alignment.center),
          _cel(_txt('LIBELLÉS', gras: true, couleur: JetonsShell.slate700), al: Alignment.center),
          _cel(const SizedBox.shrink()),
          if (_resultat) _cel(_txt('(2)', gras: true, couleur: JetonsShell.slate700), al: Alignment.center),
          _cel(_txt('NOTE', gras: true, couleur: JetonsShell.slate700), al: Alignment.center),
          for (final (i, c) in cols.indexed)
            _cel(_txt('${c.titre.toUpperCase()}${i == 0 ? ' (N)' : ' (N-1)'}', gras: true, couleur: JetonsShell.slate700), al: Alignment.center),
        ]);
    TableRow tete2() => TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
          for (var i = 0; i < nbFixes; i++) _cel(const SizedBox.shrink()),
          for (final c in cols)
            _cel(_txt('${_resultat ? 'NET (1) — ' : ''}${c.sous}', couleur: JetonsShell.slate500, taille: 12), al: Alignment.center),
        ]);
    final rows = <TableRow>[tete1(), tete2()];
    for (final l in _lignes) {
      if (l.section != null) {
        rows.add(TableRow(children: [
          _cel(const SizedBox.shrink()),
          _cel(_txt(l.section!, gras: true)),
          for (var i = 2; i < nbFixes + 2; i++) _cel(const SizedBox.shrink()),
        ]));
        continue;
      }
      final grand = l.t == 'grand', total = l.t == 'total';
      final fond = grand ? JetonsShell.navy50 : (total ? JetonsShell.slate50 : null);
      final coulTexte = grand ? JetonsShell.navy900 : JetonsShell.slate800;
      Widget lib;
      if (l.cle == 'BF') {
        lib = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _txt('Variation du BF lié aux activités opérationnelles', gras: true, couleur: coulTexte),
          _txt('FB+FC+FD+FE :', italique: true, couleur: coulTexte),
        ]);
      } else {
        lib = Text(l.libelle,
            style: TextStyle(
                color: l.t != null ? coulTexte : JetonsShell.slate700,
                fontSize: 14,
                height: 20 / 14,
                fontWeight: l.t != null ? FontWeight.w600 : FontWeight.w400));
      }
      final ec = l.ecart == null ? null : cpbEcart(l.ecart!);
      if (ec != null) {
        lib = Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: lib),
          const SizedBox(width: 8),
          Tooltip(message: '${ec['constat']}', child: const BadgeSigh('écart du document', ton: TonSigh.attention)),
        ]);
      }
      rows.add(TableRow(decoration: BoxDecoration(color: fond), children: [
        _cel(_txt(l.ref ?? '', taille: 12, mono: true, couleur: coulTexte, gras: grand), al: Alignment.center),
        Padding(padding: EdgeInsets.only(left: l.t == null ? 8 : 0), child: _cel(lib)),
        _cel(_txt(l.repere ?? '', gras: true, couleur: coulTexte), al: Alignment.center),
        if (_resultat) _cel(_txt(l.signe ?? '', couleur: coulTexte), al: Alignment.center),
        _cel(_txt(l.note ?? '', couleur: coulTexte), al: Alignment.center),
        for (final c in cols) _cel(_montant(c, l), al: Alignment.centerRight),
      ]));
      // Le CONTRÔLE qui clôt le tableau des flux, tel que le formulaire le porte sous ZH : trésorerie-actif N − trésorerie-passif N.
      if (!_resultat && l.ref == 'ZH') {
        rows.add(TableRow(children: [
          _cel(const SizedBox.shrink()),
          _cel(_txt('Contrôle : Trésorerie actif N - Trésorerie passif N', italique: true)),
          _cel(const SizedBox.shrink()),
          _cel(const SizedBox.shrink()),
          for (final c in cols)
            c.depose
                ? Container(height: 28, color: JetonsShell.slate700)
                : _cel(
                    _txt(money(c.controle, avecDevise: false),
                        gras: true, couleur: c.ecart.abs() < 1 ? JetonsShell.success700 : JetonsShell.danger700),
                    al: Alignment.centerRight),
        ]));
      }
    }
    return LayoutBuilder(builder: (_, k) {
      final minW = 56.0 + 40 + 48 + 56 + 380 + 380 + 120;
      final t = Table(
          border: const TableBorder(
              top: _bord, bottom: _bord, left: _bord, right: _bord, horizontalInside: _bord, verticalInside: _bord),
          columnWidths: largeurs,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows);
      return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: k.maxWidth > minW ? k.maxWidth : minW), child: t));
    });
  }

  Widget _entete(List<CpbColonne> cols, String titre) {
    Widget ligne(String l, String v, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 160, child: Text(l, style: const TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14))),
          Expanded(
              child: Text(v,
                  style: TextStyle(
                      color: JetonsShell.slate800,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: mono ? FontWeight.w400 : FontWeight.w500,
                      fontFamily: mono ? 'monospace' : null))),
        ]));
    final depose = cols[0].depose;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (_, k) {
        final l = k.maxWidth >= 640 ? (k.maxWidth - 32) / 2 : k.maxWidth;
        return Wrap(spacing: 32, runSpacing: 4, children: [
          SizedBox(width: l, child: ligne('Date de dépôt :', depose ? dateFR(DateTime.parse('${cpbDepot['dateDepot']}')) : 'Non déposé — exercice calculé')),
          SizedBox(width: l, child: ligne('Code de dépôt :', depose ? '${cpbDepot['code']}' : '—', mono: true)),
          SizedBox(width: l, child: ligne('Dénomination sociale :', '${cpbDepot['denomination']}')),
          SizedBox(width: l, child: ligne('IFU :', '${cpbDepot['ifu']}', mono: true)),
        ]);
      }),
      const SizedBox(height: 12),
      Center(
          child: Text(titre.toUpperCase(),
              style: const TextStyle(color: JetonsShell.navy900, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700, letterSpacing: 0.4))),
    ]);
  }

  /// `noteSourceFeuillet`.
  Widget _noteSource(List<CpbColonne> cols) {
    final brouillons = cpbBrouillonsEcartes(cols);
    final morceaux = [
      for (final c in cols) '${c.titre} : ${c.sous}${c.depose ? '' : ' (${nombre(c.nbLignes)} ligne(s) d’écriture validée(s) retenue(s))'}'
    ];
    return NoteSigh(
        '${morceaux.join(' · ')}${brouillons > 0 ? '. ${nombre(brouillons)} brouillon(s) écarté(s) : un brouillon n’est pas un fait comptable, et le compter donnerait un résultat qui change quand le comptable rectifie une saisie.' : '.'}',
        ton: brouillons > 0 ? TonSigh.attention : TonSigh.info,
        icone: LucideIcons.bookOpenText);
  }

  Widget _controles(List<CpbColonne> cols) {
    final notes = <Widget>[];
    final lignes = _lignes;
    final formules = _resultat ? cpbFormulesResultat : cpbFormulesFlux;
    for (final c in cols) {
      if (c.depose) {
        final ctl = cpbControleSousTotaux(lignes, formules, c.annee);
        final faux = ctl.where((x) => x.ecart.abs() > 0.5).toList();
        final String texte;
        if (_resultat) {
          texte = '${c.titre} (déposé) — ${faux.isNotEmpty ? '${nombre(faux.length)} sous-total(aux) ne se recalcule(nt) pas depuis ses lignes : ${faux.map((x) => '${x.ref} (écart ${money(x.ecart)})').join(', ')}. Écart du document, conservé et non arbitré.' : 'les ${nombre(ctl.length)} sous-totaux déposés (XA à XI) se recalculent à l’identique depuis leurs lignes par les formules du formulaire.'}';
        } else {
          texte = '${c.titre} (déposé) — ${faux.isNotEmpty ? '${nombre(faux.length)} sous-total(aux) déposé(s) ne se recalcule(nt) pas depuis ses lignes : ${faux.map((x) => '${x.ref == 'BF' ? 'Variation du BF' : x.ref} (déposé ${money(x.depose)}, recalculé ${money(x.recalcule)})').join(' ; ')}. Écarts du document, conservés et non arbitrés.' : 'les sous-totaux déposés se recalculent à l’identique depuis leurs lignes.'}';
        }
        notes.add(NoteSigh(texte,
            ton: faux.isNotEmpty ? TonSigh.attention : TonSigh.succes,
            icone: faux.isNotEmpty ? LucideIcons.triangleAlert : LucideIcons.circleCheck));
      } else if (_resultat) {
        final orph = c.orphelins.keys.toList();
        notes.add(NoteSigh(
            '${c.titre} (calculé) — ${orph.isNotEmpty ? '${nombre(orph.length)} compte(s) de gestion sans ligne du formulaire : ${orph.map((k) => '$k (${money(c.orphelins[k])})').join(', ')}. Ils ne sont PAS comptés — les rattacher au plan comptable.' : 'toutes les écritures de gestion retenues se rattachent à une ligne du formulaire. Les lignes vides (—) sont celles que le journal n’alimente pas.'}',
            ton: orph.isNotEmpty ? TonSigh.attention : TonSigh.succes,
            icone: orph.isNotEmpty ? LucideIcons.triangleAlert : LucideIcons.circleCheck));
      } else {
        final ok = c.ecart.abs() < 1;
        final nc = c.nonClasses.keys.toList();
        notes.add(NoteSigh(
            '${c.titre} (calculé) — contrôle du formulaire : trésorerie des comptes de classe 5 au ${dateFR(c.bornes!.fin)} = ${money(c.controle)}, trésorerie par les flux (ZH) = ${money(c.val('ZH'))}. ${ok ? 'Les deux concordent : chaque mouvement de trésorerie est expliqué par une ligne du tableau.' : 'Écart de ${money(c.ecart)}${nc.isNotEmpty ? ', porté par des comptes que le tableau ne classe pas : ${nc.map((k) => '$k (${money(c.nonClasses[k])})').join(', ')}' : ''}. Il se lève en complétant les écritures, pas en retouchant le tableau.'}',
            ton: ok ? TonSigh.succes : TonSigh.danger,
            icone: ok ? LucideIcons.circleCheck : LucideIcons.triangleAlert));
        if (c.val('ZA') == 0) {
          final zh = cpbLignesFlux.firstWhere((x) => x.ref == 'ZH');
          notes.add(NoteSigh(
              'La trésorerie au 1er janvier ${c.annee} se lit dans le journal : sans à-nouveaux (bilan d’ouverture), elle vaut zéro. La liasse déposée porte ${money(zh.n)} au 31/12/$cpbExerciceN — reporter les soldes par le bilan d’ouverture pour les faire coïncider.',
              ton: TonSigh.info,
              icone: LucideIcons.calendarPlus));
        }
      }
    }
    return CarteSigh(titre: 'Contrôles', child: pile(notes, ecart: 8));
  }

  Widget _source(String texte) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        const Icon(LucideIcons.fileCheck2, size: 14, color: JetonsShell.slate400),
        const SizedBox(width: 6),
        Flexible(child: Text('Source : $texte', style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
      ]));

  // --- Impression ------------------------------------------------------------------------------------------------------------------------------

  void _imprimer(BuildContext ctx, ContexteEcran c, List<CpbColonne> cols) {
    final lignes = <Map<String, Object?>>[];
    for (final l in _lignes) {
      if (l.section != null) {
        lignes.add({'ref': '', 'lib': l.section, 'repere': '', 'signe': '', 'note': '', 'n': '', 'n1': ''});
        continue;
      }
      lignes.add({
        'ref': l.ref ?? '',
        'lib': l.cle == 'BF' ? 'Variation du BF lié aux activités opérationnelles FB+FC+FD+FE :' : l.libelle,
        'repere': l.repere ?? '',
        'signe': l.signe ?? '',
        'note': l.note ?? '',
        'n': cpbMontantFeuillet(cols[0], l) ?? '',
        'n1': cpbMontantFeuillet(cols[1], l) ?? '',
      });
      if (!_resultat && l.ref == 'ZH') {
        lignes.add({
          'ref': '',
          'lib': 'Contrôle : Trésorerie actif N - Trésorerie passif N',
          'repere': '',
          'signe': '',
          'note': '',
          'n': cols[0].depose ? '' : money(cols[0].controle, avecDevise: false),
          'n1': cols[1].depose ? '' : money(cols[1].controle, avecDevise: false),
        });
      }
    }
    final depose = cols[0].depose;
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: _resultat ? 'Compte de résultat' : 'Tableau des flux de trésorerie',
            sousTitre: '${cols[0].titre} — ${cols[0].sous}',
            cartouche: [
              ('Dénomination sociale', '${cpbDepot['denomination']}'),
              ('IFU', '${cpbDepot['ifu']}'),
              ('Date de dépôt', depose ? dateFR(DateTime.parse('${cpbDepot['dateDepot']}')) : 'Non déposé'),
              ('Code de dépôt', depose ? '${cpbDepot['code']}' : '—'),
              ('Colonne N', '${cols[0].titre} — ${cols[0].sous}'),
              ('Colonne N-1', '${cols[1].titre} — ${cols[1].sous}'),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'RÉF', valeur: (x) => x['ref']),
                ColonneEtat(libelle: 'LIBELLÉS', valeur: (x) => x['lib']),
                ColonneEtat(libelle: 'Repère', valeur: (x) => x['repere']),
                if (_resultat) ColonneEtat(libelle: '(2)', valeur: (x) => x['signe']),
                ColonneEtat(libelle: 'NOTE', valeur: (x) => x['note']),
                ColonneEtat(libelle: '${cols[0].titre} (N)', droite: true, valeur: (x) => x['n']),
                ColonneEtat(libelle: '${cols[1].titre} (N-1)', droite: true, valeur: (x) => x['n1']),
              ], lignes: lignes),),
              BlocTexte(
                  _resultat
                      ? '(1) Montants nets. (2) + produit, - charge, -/+ variation. Formulaire au format du feuillet 7/51 de la liasse DGI ; sous-totaux calculés par les formules du formulaire.'
                      : '(1) À l’exclusion des variations des créances et dettes liées aux activités d’investissement et de financement. Formulaire au format du feuillet 8/51 de la liasse DGI.',
                  italique: true),
            ],
            signatures: const [signComptable, signDafFinances]));
  }

  // --- Écran -----------------------------------------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecouteCompta(c),
      builder: (context, _) {
        final cc = _colonnes(c);
        final n = cc[0], n1 = cc[1];
        final depose = '${_exercice!['exercice']}' == 'depose';

        String evolution(String ref) {
          final a = n.val(ref), b = n1.val(ref);
          return b != 0 ? 'N-1 : ${money(b)} (${a - b >= 0 ? '+' : ''}${pourcent((a - b) / b.abs() * 100)})' : 'N-1 : ${money(b)}';
        }

        final kpis = _resultat
            ? [
                KpiSigh(libelle: 'Chiffre d’affaires (XB)', valeur: money(n.val('XB')), indice: evolution('XB'), icone: LucideIcons.trendingUp, ton: TonSigh.navy),
                KpiSigh(libelle: 'Valeur ajoutée (XC)', valeur: money(n.val('XC')), indice: evolution('XC'), icone: LucideIcons.sparkles, ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Excédent brut d’exploitation (XD)',
                    valeur: money(n.val('XD')),
                    indice: evolution('XD'),
                    icone: LucideIcons.activity,
                    ton: n.val('XD') >= 0 ? TonSigh.succes : TonSigh.danger),
                KpiSigh(
                    libelle: 'Résultat net (XI)',
                    valeur: money(n.val('XI')),
                    indice: evolution('XI'),
                    icone: n.val('XI') >= 0 ? LucideIcons.smile : LucideIcons.frown,
                    ton: n.val('XI') >= 0 ? TonSigh.succes : TonSigh.danger),
              ]
            : [
                KpiSigh(libelle: 'Trésorerie au 1er janvier (ZA)', valeur: money(n.val('ZA')), icone: LucideIcons.wallet, ton: TonSigh.neutre),
                KpiSigh(
                    libelle: 'Flux opérationnels (ZB)',
                    valeur: money(n.val('ZB')),
                    indice: 'CAFG : ${money(n.val('FA'))}',
                    icone: LucideIcons.activity,
                    ton: n.val('ZB') >= 0 ? TonSigh.succes : TonSigh.danger),
                KpiSigh(
                    libelle: 'Variation de la trésorerie (ZG)',
                    valeur: money(n.val('ZG')),
                    indice: 'Investissement ${money(n.val('ZC'))} · financement ${money(n.val('ZF'))}',
                    icone: LucideIcons.arrowLeftRight,
                    ton: n.val('ZG') >= 0 ? TonSigh.succes : TonSigh.danger),
                KpiSigh(
                    libelle: 'Trésorerie au 31 décembre (ZH)',
                    valeur: money(n.val('ZH')),
                    indice: n.depose ? 'Égale au total trésorerie-actif du bilan (BT)' : (n.ecart.abs() < 1 ? 'Contrôle concordant' : 'Écart au contrôle : ${money(n.ecart)}'),
                    icone: LucideIcons.landmark,
                    ton: TonSigh.navy),
              ];

        final carteFeuillet = CarteSigh(
            titre: _resultat ? 'Compte de résultat — feuillet 7/51' : 'Tableau des flux de trésorerie — feuillet 8/51',
            child: pile([
              _entete(cc, _resultat ? 'Compte de résultat' : 'Tableau des flux de trésorerie'),
              _formulaire(cc),
              Text(
                  _resultat
                      ? '(1) Montants nets. (2) Signe de la ligne : + produit, - charge, -/+ variation. Les charges figurent en négatif, comme sur le formulaire déposé.'
                      : '(1) À l’exclusion des variations des créances et dettes liées aux activités d’investissement (variation des créances sur cession d’immobilisation et des dettes sur acquisition ou production d’immobilisation) et de financement (par exemple variation des créances sur subventions d’investissement reçues).',
                  style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
            ], ecart: 12));

        final ecarts = (!_resultat && cc.any((x) => x.depose))
            ? () {
                final cles = cc.any((x) => x.depose && x.annee == cpbExerciceN1) ? ['bf', 'zb', 'cafg'] : ['bf', 'zb'];
                final sel = cpbEcarts.where((x) => cles.contains(x['cle'])).toList();
                return CarteSigh(
                    titre: 'Écarts internes du document déposé — conservés, non arbitrés',
                    child: pile([
                      const NoteSigh(
                          'Le formulaire déposé ne se recoupe pas partout. Ces écarts sont ceux du document remis à l’administration : les corriger ici ferait diverger le logiciel de ce que la clinique a réellement déposé — précisément ce qu’un contrôle vient comparer.',
                          ton: TonSigh.attention,
                          icone: LucideIcons.triangleAlert),
                      MiniTableauSigh(colonnes: [
                        ColonneMini('Ligne', (x) => '${x['titre']}'),
                        ColonneMini('Constat', (x) => '${x['constat']}'),
                        ColonneMini('Lecture', (x) => '${x['lecture']}'),
                      ], lignes: sel),
                    ], ecart: 8));
              }()
            : null;

        final graphique = _resultat
            ? CarteSigh(
                titre: 'De la valeur ajoutée au résultat net — N et N-1',
                child: GraphiqueBarres(
                    hauteur: 260,
                    etiquettes: const ['Valeur ajoutée', 'EBE', 'Résultat d’exploitation', 'Activités ordinaires', 'Résultat net'],
                    series: [
                      SerieGraphique(n.titre, [for (final r in ['XC', 'XD', 'XE', 'XG', 'XI']) n.val(r)], couleur: tonNavy),
                      SerieGraphique(n1.titre, [for (final r in ['XC', 'XD', 'XE', 'XG', 'XI']) n1.val(r)], couleur: tonCiel),
                    ]))
            : CarteSigh(
                titre: 'Composantes de la variation de trésorerie — ${n.titre}',
                child: GraphiqueBarres(
                    hauteur: 240,
                    etiquettes: const ['Opérationnels (ZB)', 'Investissement (ZC)', 'Financement (ZF)', 'Variation (ZG)'],
                    series: [
                      SerieGraphique(n.titre, [for (final r in ['ZB', 'ZC', 'ZF', 'ZG']) n.val(r)], couleur: tonNavy),
                    ]));

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            commande(_exercice!, largeur: 360),
            if (!depose) commande(_arrete!, largeur: 200),
            BoutonSigh(
                libelle: _resultat ? 'Imprimer le compte de résultat' : 'Imprimer le tableau des flux',
                icone: LucideIcons.printer,
                onPressed: () => _imprimer(context, c, cc)),
          ])),
          const SizedBox(height: 16),
          pile([
            _noteSource(cc),
            KpiGrilleSigh(kpis: kpis),
            carteFeuillet,
            if (_resultat)
              CarteSigh(
                  titre: 'Lecture du formulaire',
                  child: pile(const [
                    NoteSigh(
                        'MARGE COMMERCIALE (XA) — RG-02 facture les médicaments au prix d’achat, sans marge : ce solde doit être nul ou quasi nul, et il l’est à la liasse déposée. S’il cessait de l’être, ce serait un signal, pas une bonne nouvelle.',
                        ton: TonSigh.succes,
                        icone: LucideIcons.circleCheck),
                    NoteSigh(
                        'EXCÉDENT BRUT D’EXPLOITATION (XD) — ce qui reste après avoir payé les hommes et l’État. Il ignore les amortissements et le financement, qui dépendent de décisions passées : c’est lui qu’on regarde pour savoir si l’exploitation tient debout.',
                        ton: TonSigh.info,
                        icone: LucideIcons.activity),
                    NoteSigh(
                        'RÉSULTAT FINANCIER (XF) — les intérêts d’emprunt (RM) sont ici, PAS dans l’exploitation : les y mettre ferait juger l’activité sur des choix de financement.',
                        ton: TonSigh.info,
                        icone: LucideIcons.landmark),
                  ], ecart: 8)),
            _controles(cc),
            ecarts,
            grilleCartes([graphique]),
            _source(_resultat
                ? '${cpbDepot['source']} — feuillet 7/51. Les exercices non déposés sont calculés depuis les écritures validées du journal, par les préfixes de comptes SYSCOHADA de chaque ligne.'
                : '${cpbDepot['source']} — feuillet 8/51. Les exercices non déposés sont calculés depuis les écritures validées du journal ; les à-nouveaux (journal AN) forment l’ouverture, jamais un flux.'),
          ]),
        ]);
      },
    );
  }
}
