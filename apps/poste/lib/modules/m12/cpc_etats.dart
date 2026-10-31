import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/qual_commun.dart' show sourceQual;
import 'cpc_commun.dart';

/// `m12-etats-financiers` — « États financiers de synthèse » : les CINQ feuillets de la liasse déposée à la DGI le 15/05/2026 (code BK505416) — bilan,
/// compte de résultat, tableau des flux de trésorerie, note 11 « Disponibilités », note 34 « Fiche de synthèse » — avec les MÊMES références, libellés et
/// ordre : un comptable doit retrouver SES lignes, à LEUR place, pour rapprocher l'écran du dépôt.
///
/// Deux colonnes de natures différentes, qui ne se mélangent jamais : « déposé » CITE le document (la liasse est ENGENDRÉE, `cpc_liasse.dart`), « exercice en
/// cours » est CALCULÉE depuis les écritures validées du journal par les préfixes de comptes — vide là où le journal ne porte rien. Un compte de tiers change de
/// côté selon son sens. Les six écarts internes du document sont CONSERVÉS et signalés, jamais arbitrés. Règles dans `cpc_etats.dart` (rejouées sur l'écran réel).
///
/// Écart E809 : les écrans « Compte de résultat » (feuillet 7/51) et « Flux de trésorerie » (feuillet 8/51) ont leurs propres écrans ; l'onglet de celui-ci
/// reste la lecture du dépôt, comme dans la maquette — les deux ne se confondent pas.
class EcranEtatsFinanciers extends StatefulWidget with EcranMaquette {
  const EcranEtatsFinanciers({super.key});

  @override
  String get titre => 'États financiers de synthèse';

  @override
  String get description => 'Bilan, compte de résultat, flux de trésorerie, disponibilités et fiche de synthèse — au format de la liasse DGI.';

  @override
  String get regle =>
      'L’écran reproduit les cinq feuillets de la liasse déposée le 15/05/2026 (code BK505416) : mêmes références, mêmes libellés, même ordre. La colonne « déposé » CITE le document — elle ne se recalcule pas ; la colonne « exercice en cours » est CALCULÉE depuis le journal, par les préfixes de comptes SYSCOHADA. Une ligne que le journal n’alimente pas reste vide : un zéro y ferait croire à un solde nul là où il n’y a pas de donnée. Les écarts internes du document sont signalés, jamais arbitrés.';

  @override
  State<EcranEtatsFinanciers> createState() => _EtatEtats();
}

/// Une colonne d'une table de la liasse : son en-tête, sa largeur (`null` : elle prend le reste), son alignement.
class _Col {
  const _Col(this.entete, this.rendu, {this.largeur, this.droite = false});
  final String entete;
  final double? largeur;
  final bool droite;
  final Widget Function(Fiche l) rendu;
}

class _EtatEtats extends State<EcranEtatsFinanciers> {
  bool _amorce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    final c = ContexteEcran.of(context);
    amorcerExercices(c.magasin, c.aujourdhui);
  }

  CpcLiasseDonnees get _l => cpcLiasseDonnees;

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // LES CELLULES
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  /// La cellule d'un montant : `null` → [vide] (jamais un zéro) ; négatif en rouge ; [gras] pour les sous-totaux.
  static Widget cellule(num? v, {bool gras = false, String vide = ''}) {
    if (v == null) return Text(vide, style: const TextStyle(color: JetonsShell.slate300, fontSize: 14, height: 20 / 14));
    return Text(money(v, avecDevise: false),
        style: TextStyle(
            color: v < 0 ? JetonsShell.danger700 : JetonsShell.slate800,
            fontSize: 14,
            height: 20 / 14,
            fontWeight: gras ? FontWeight.w600 : FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()]));
  }

  static Widget _petit(String t) => Text(t, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));

  static Widget _libelle(Fiche l, {Widget? apres}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: Padding(
                padding: EdgeInsets.only(left: l['t'] != null ? 0 : 12),
                child: Text('${l['libelle']}',
                    style: TextStyle(
                        color: l['t'] != null ? JetonsShell.slate900 : JetonsShell.slate700,
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: l['t'] != null ? FontWeight.w600 : FontWeight.w400)))),
        if (apres != null) apres,
      ]);

  Widget? _badgeEcart(Fiche l) {
    if (l['ecart'] == null) return null;
    final e = _l.ecart(l['ecart']);
    return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Tooltip(message: e == null ? '' : '${e['constat']}', child: const BadgeSigh('écart du document', ton: TonSigh.attention)));
  }

  /// `tableLiasse(lignes, colonnes)` : l'en-tête, les rubriques (`section` / `section2`) sur toute la largeur, les lignes — un sous-total en gris, un total
  /// général en bleu, le détail indenté sous son sous-total (c'est cette indentation qui rend la structure lisible).
  Widget _table(List<Fiche> lignes, List<_Col> cols) {
    Widget cellule(_Col c, Widget w) => c.largeur != null
        ? SizedBox(width: c.largeur, child: Align(alignment: c.droite ? Alignment.centerRight : Alignment.centerLeft, child: w))
        : Expanded(child: Align(alignment: Alignment.centerLeft, child: w));
    final largeurMin = cols.fold<double>(0, (a, c) => a + (c.largeur ?? 360)) + 16 * cols.length;
    return LayoutBuilder(
        builder: (context, k) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: k.maxWidth > largeurMin ? k.maxWidth : largeurMin,
                child: Column(children: [
                  Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JetonsShell.slate200))),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(children: [
                        for (final c in cols)
                          cellule(
                              c,
                              Text(c.entete.toUpperCase(),
                                  textAlign: c.droite ? TextAlign.right : TextAlign.left,
                                  style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6))),
                      ])),
                  for (final l in lignes)
                    if (l['section'] != null || l['section2'] != null)
                      Container(
                          width: double.infinity,
                          color: JetonsShell.slate100,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text('${l['section'] ?? l['section2']}'.toUpperCase(),
                              style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)))
                    else
                      Container(
                          decoration: BoxDecoration(
                              color: l['t'] == 'grand' ? JetonsShell.navy50 : (l['t'] == 'total' ? JetonsShell.slate50 : null),
                              border: const Border(bottom: BorderSide(color: JetonsShell.slate100))),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in cols) cellule(c, c.rendu(l))])),
                ]))));
  }

  Widget _carte(String titre, Widget t) => CarteSigh(titre: titre, sansRemplissage: true, child: t);

  static const double _wRef = 56, _wNote = 56, _wMontant = 120;

  _Col _ref() => _Col('Réf.', (l) => monoTexte(l['ref'] ?? '', couleur: JetonsShell.slate500), largeur: _wRef);
  _Col _note() => _Col('Note', (l) => _petit('${l['note'] ?? ''}'), largeur: _wNote);

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // LES CINQ ONGLETS
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  Widget _bilan(ContexteEcran c, List<Fiche> courant, List<Fiche>? n1) {
    final ta = _l.ligne(_l.bilanActif, 'BZ')!, tp = _l.ligne(_l.bilanPassif, 'DZ')!;
    final n = _l.exerciceN, nn1 = _l.exerciceN1;
    final avecN1 = n1 != null;
    final annee1 = exerciceChoisi(c) - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          'Le bilan déposé s’équilibre : total général de l’actif ${money(ta['net'])} = total général du passif ${money(tp['net'])}.',
          ton: TonSigh.succes,
          icone: LucideIcons.scale),
      const SizedBox(height: 16),
      _carte(
          'BILAN — ACTIF (feuillet 5/51)',
          _table(_l.bilanActif, [
            _ref(),
            _Col('Actif', (l) => _libelle(l)),
            _note(),
            _Col('Brut $n', (l) => cellule(l['brut'] as num?), largeur: _wMontant, droite: true),
            _Col('Amort. et dépréc.', (l) => cellule(l['amort'] as num?), largeur: _wMontant, droite: true),
            _Col('Net $n', (l) => cellule(l['net'] as num?, gras: l['t'] != null), largeur: _wMontant, droite: true),
            _Col('Net $nn1', (l) => cellule(l['netN1'] as num?), largeur: _wMontant, droite: true),
            _Col('Exercice en cours', (l) => l['t'] != null ? const SizedBox.shrink() : cellule(cpcCalculActif(l, courant), vide: '—'), largeur: _wMontant, droite: true),
            if (avecN1)
              _Col('Exercice $annee1 (journal)', (l) => l['t'] != null ? const SizedBox.shrink() : cellule(cpcCalculActif(l, n1), vide: '—'),
                  largeur: _wMontant, droite: true),
          ])),
      const SizedBox(height: 16),
      _carte(
          'BILAN — PASSIF (feuillet 6/51)',
          _table(_l.bilanPassif, [
            _ref(),
            _Col('Passif', (l) => _libelle(l)),
            _note(),
            _Col('Net $n', (l) => cellule(l['net'] as num?, gras: l['t'] != null), largeur: _wMontant, droite: true),
            _Col('Net $nn1', (l) => cellule(l['netN1'] as num?), largeur: _wMontant, droite: true),
            _Col('Exercice en cours', (l) => l['t'] != null ? const SizedBox.shrink() : cellule(cpcCalculPassif(l, courant), vide: '—'), largeur: _wMontant, droite: true),
            if (avecN1)
              _Col('Exercice $annee1 (journal)', (l) => l['t'] != null ? const SizedBox.shrink() : cellule(cpcCalculPassif(l, n1), vide: '—'),
                  largeur: _wMontant, droite: true),
          ])),
      const SizedBox(height: 16),
      const NoteSigh(
          'La colonne « Exercice en cours » est calculée depuis les écritures VALIDÉES du journal, par les préfixes de comptes SYSCOHADA que chaque ligne déclare. Elle reste vide là où le journal ne porte rien — le prototype ne tient pas encore tous les comptes de la liasse. Un compte de tiers y paraît du côté où son solde le place : débiteur à l’actif, créditeur au passif — le plan SYSCOHADA emploie les mêmes comptes de classe 4 pour les créances et pour les dettes.'),
    ]);
  }

  Widget _resultat(List<Fiche> courant) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _carte(
            'COMPTE DE RÉSULTAT (feuillet 7/51)',
            _table(_l.resultat, [
              _ref(),
              _Col('Libellés', (l) => _libelle(l)),
              _Col('(2)', (l) => _petit('${l['signe'] ?? ''}'), largeur: 40),
              _note(),
              _Col('Exercice ${_l.exerciceN}', (l) => cellule(l['n'] as num?, gras: l['t'] != null), largeur: _wMontant, droite: true),
              _Col('Exercice ${_l.exerciceN1}', (l) => cellule(l['n1'] as num?), largeur: _wMontant, droite: true),
              _Col('Exercice en cours', (l) => l['t'] != null ? const SizedBox.shrink() : cellule(cpcCalculResultat(l, courant), vide: '—'), largeur: _wMontant, droite: true),
            ])),
        const SizedBox(height: 16),
        const NoteSigh(
            'La marge commerciale est nulle à la liasse déposée — et c’est la confirmation documentaire de RG-02 : les médicaments sont facturés au prix d’achat, sans marge. Si elle cessait de l’être, ce serait un signal, pas une bonne nouvelle.',
            ton: TonSigh.succes,
            icone: LucideIcons.circleCheck),
      ]);

  Widget _blocEcarts(List<String> cles) {
    final sel = _l.ecartsDe(cles);
    if (sel.isEmpty) return const SizedBox.shrink();
    return CarteSigh(
        titre: 'Écarts internes du document déposé — conservés, non arbitrés',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Le formulaire déposé ne se recoupe pas partout. Ces écarts sont ceux du document remis à l’administration : les corriger ici ferait diverger le logiciel de ce que la clinique a réellement déposé — précisément ce qu’un contrôle vient comparer.',
              ton: TonSigh.attention,
              icone: LucideIcons.triangleAlert),
          const SizedBox(height: 8),
          MiniTableauSigh(colonnes: [
            ColonneMini('Ligne', (x) => '${x['titre']}'),
            ColonneMini('Constat', (x) => '${x['constat']}'),
            ColonneMini('Lecture', (x) => '${x['lecture']}'),
          ], lignes: sel),
        ]));
  }

  Widget _flux() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _carte(
            'TABLEAU DES FLUX DE TRÉSORERIE (feuillet 8/51)',
            _table(_l.flux, [
              _Col('Réf.', (l) => monoTexte(l['ref'] ?? '', couleur: JetonsShell.slate500), largeur: _wRef),
              _Col('Libellés', (l) => _libelle(l, apres: _badgeEcart(l))),
              _Col('', (l) => Text('${l['repere'] ?? ''}', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w700)), largeur: 32),
              _Col('Exercice ${_l.exerciceN}', (l) => cellule(l['n'] as num?, gras: l['t'] != null), largeur: _wMontant, droite: true),
              _Col('Exercice ${_l.exerciceN1}', (l) => cellule(l['n1'] as num?), largeur: _wMontant, droite: true),
            ])),
        const SizedBox(height: 16),
        _blocEcarts(const ['bf', 'zb', 'cafg']),
      ]);

  Widget _disponibilites(List<Fiche> courant) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _carte(
            '${_l.dispoNote} (feuillet 25/51)',
            _table(_l.dispoLignes, [
              _Col('Libellés', (l) => _libelle(l)),
              _Col('Année ${_l.exerciceN}', (l) => cellule(l['n'] as num?, gras: l['t'] != null), largeur: _wMontant, droite: true),
              _Col('Année ${_l.exerciceN1}', (l) => cellule(l['n1'] as num?), largeur: _wMontant, droite: true),
              _Col('Variation en %', (l) {
                final p = cpcVariationDisponibilite(l);
                return p == null ? const SizedBox.shrink() : Text(pourcent(p, 2), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14));
              }, largeur: _wMontant, droite: true),
              _Col('Exercice en cours', (l) => l['t'] != null ? const SizedBox.shrink() : cellule(cpcCalculDisponibilite(l, courant), vide: '—'),
                  largeur: _wMontant, droite: true),
            ])),
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Commentaires demandés par le formulaire',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final x in _l.dispoCommentaires)
                Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('•  $x', style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14))),
            ])),
        const SizedBox(height: 16),
        NoteSigh(_l.dispoNb, ton: TonSigh.neutre),
      ]);

  Widget _synthese() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _carte(
            'NOTE 34 : FICHE DE SYNTHÈSE DES PRINCIPAUX INDICATEURS FINANCIERS (feuillet 51/51)',
            _table(_l.synthese, [
              _Col('Libellés', (l) {
                if (l['controle'] != null) {
                  return Text('${l['libelle']}', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic));
                }
                return _libelle(l, apres: _badgeEcart(l));
              }),
              _Col('Année ${_l.exerciceN}', (l) => l['unite'] != null ? _petit('${l['unite']}') : cellule(l['n'] as num?, gras: l['t'] != null), largeur: _wMontant, droite: true),
              _Col('Année ${_l.exerciceN1}', (l) => l['unite'] != null ? _petit('${l['unite']}') : cellule(l['n1'] as num?), largeur: _wMontant, droite: true),
              _Col('Variation en %', (l) {
                final p = l['variation'];
                if (p == null) return const SizedBox.shrink();
                return Text('${nombre(p, 2)} %',
                    style: TextStyle(color: (p as num) < 0 ? JetonsShell.danger700 : JetonsShell.slate700, fontSize: 14, height: 20 / 14));
              }, largeur: _wMontant, droite: true),
            ])),
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Notes du formulaire',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final x in _l.notesSynthese)
                Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('•  $x', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
            ])),
        const SizedBox(height: 16),
        _blocEcarts(const ['cafg', 'fluxOp', 'fluxFin', 'tresorerie']),
      ]);

  // ----------------------------------------------------------------------------------------------------------------------------------------------
  // L'IMPRESSION — cinq pièces, un cartouche et trois signatures
  // ----------------------------------------------------------------------------------------------------------------------------------------------
  static String _m(Object? v) => v == null ? '' : m(v);

  void _imprimer(BuildContext ctx, ContexteEcran c, String quoi) {
    final n = _l.exerciceN, nn1 = _l.exerciceN1;
    final cartouche = [
      ('Dénomination sociale', '${_l.depot['denomination']}'),
      ('IFU', '${_l.depot['ifu']}'),
      ('Date de dépôt', dateDe(_l.depot['dateDepot'])),
      ('Code de dépôt', '${_l.depot['code']}'),
      ('Exercice', '$n (N) — comparé à $nn1 (N-1)'),
      ('Référentiel', 'Plan comptable SYSCOHADA révisé (AUDCIF)'),
    ];
    final signatures = [
      signComptable,
      const Signature('La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou'),
      const Signature('La Direction', nom: 'BASSONGUI Chabi Séko'),
    ];
    TableauEtat t(List<ColonneEtat> cols, List<Fiche> l) => TableauEtat(colonnes: cols, lignes: l);
    ColonneEtat col(String lib, Object? Function(Fiche) v, {bool droite = false}) => ColonneEtat(libelle: lib, droite: droite, valeur: v);
    String titre, sous = 'Exercice au 31/12/$n';
    List<BlocPiece> blocs;
    switch (quoi) {
      case 'bilan':
        titre = 'Bilan';
        final ta = _l.ligne(_l.bilanActif, 'BZ')!, tp = _l.ligne(_l.bilanPassif, 'DZ')!;
        blocs = [
          const BlocTexte('Actif', gras: true),
          BlocTableau(t([
            col('Réf.', (l) => l['ref']),
            col('Actif', (l) => l['libelle']),
            col('Note', (l) => l['note']),
            col('Brut', (l) => _m(l['brut']), droite: true),
            col('Amort. et dépréc.', (l) => _m(l['amort']), droite: true),
            col('Net $n', (l) => _m(l['net']), droite: true),
            col('Net $nn1', (l) => _m(l['netN1']), droite: true),
          ], _l.bilanActif)),
          const BlocTexte('Passif', gras: true),
          BlocTableau(t([
            col('Réf.', (l) => l['ref']),
            col('Passif', (l) => l['libelle']),
            col('Note', (l) => l['note']),
            col('Net $n', (l) => _m(l['net']), droite: true),
            col('Net $nn1', (l) => _m(l['netN1']), droite: true),
          ], _l.bilanPassif)),
          BlocTexte('Contrôle : total général de l’actif ${money(ta['net'])} = total général du passif ${money(tp['net'])}.'),
        ];
      case 'resultat':
        titre = 'Compte de résultat';
        blocs = [
          BlocTableau(t([
            col('Réf.', (l) => l['ref']),
            col('Libellés', (l) => l['libelle']),
            col('(2)', (l) => l['signe']),
            col('Note', (l) => l['note']),
            col('Exercice $n', (l) => _m(l['n']), droite: true),
            col('Exercice $nn1', (l) => _m(l['n1']), droite: true),
          ], _l.resultat)),
          BlocTexte(
              'La marge commerciale est nulle : les médicaments sont facturés au prix d’achat, sans marge (RG-02). Résultat net de l’exercice : ${money(_l.ligne(_l.resultat, 'XI')!['n'])}.'),
        ];
      case 'flux':
        titre = 'Tableau des flux de trésorerie';
        blocs = [
          BlocTableau(t([
            col('Réf.', (l) => l['ref'] ?? ''),
            col('Libellés', (l) => l['section'] ?? l['libelle'] ?? ''),
            col('', (l) => l['repere'] ?? ''),
            col('Exercice $n', (l) => _m(l['n']), droite: true),
            col('Exercice $nn1', (l) => _m(l['n1']), droite: true),
          ], _l.flux)),
          BlocTexte(
              'Écarts internes du document déposé, conservés et non arbitrés : ${_l.ecartsDe(const ['bf', 'zb', 'cafg']).map((x) => '${x['titre']} — ${x['constat']}').join(' ; ')}'),
        ];
      case 'disponibilites':
        titre = _l.dispoNote;
        blocs = [
          BlocTableau(t([
            col('Libellés', (l) => l['libelle']),
            col('Année $n', (l) => _m(l['n']), droite: true),
            col('Année $nn1', (l) => _m(l['n1']), droite: true),
          ], _l.dispoLignes)),
          BlocTexte(_l.dispoNb),
        ];
      default:
        titre = 'Fiche de synthèse des principaux indicateurs financiers';
        sous = 'Note 34 — exercice au 31/12/$n';
        blocs = [
          BlocTableau(t([
            col('Libellés', (l) => l['section'] ?? l['section2'] ?? l['libelle'] ?? ''),
            col('Année $n', (l) => _m(l['n']), droite: true),
            col('Année $nn1', (l) => _m(l['n1']), droite: true),
            col('Variation en %', (l) => l['variation'] == null ? '' : '${nombre(l['variation'], 2)} %', droite: true),
          ], _l.synthese)),
          BlocTexte(_l.notesSynthese.join(' ')),
        ];
    }
    afficherApercu(ctx, pieceM9(c, titre: titre, sousTitre: sous, cartouche: cartouche, blocs: blocs, signatures: signatures));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.magasin.collection('ecritures'), c.magasin.collection('exercices'), c.magasin.collection('comptes')]),
      builder: (context, _) {
        final exos = c.magasin.collection('exercices').toutes;
        final actives = c.magasin.collection('ecritures').actives;
        final annee = exerciceChoisi(c);
        final courant = cpcSourceExercice(exos, actives, annee);
        // L'EXERCICE PRÉCÉDENT, TIRÉ DU JOURNAL : quand il n'a pas été déposé (et que le journal le porte), sa colonne se CALCULE comme celle de l'exercice choisi.
        final prec = cpcSourceExercice(exos, actives, annee - 1);
        final n1 = prec.isEmpty ? null : prec;
        final ca = _l.ligne(_l.resultat, 'XB')!, res = _l.ligne(_l.resultat, 'XI')!;
        final ta = _l.ligne(_l.bilanActif, 'BZ')!, tp = _l.ligne(_l.bilanPassif, 'DZ')!;
        final d = _l.depot;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Chiffre d’affaires déposé',
                valeur: money(ca['n']),
                icone: LucideIcons.trendingUp,
                indice: 'Exercice ${_l.exerciceN} — liasse du ${dateDe(d['dateDepot'])}'),
            KpiSigh(
                libelle: 'Résultat net déposé',
                valeur: money(res['n']),
                icone: (res['n'] as num) >= 0 ? LucideIcons.smile : LucideIcons.frown,
                ton: (res['n'] as num) >= 0 ? TonSigh.succes : TonSigh.danger,
                indice: 'N-1 : ${money(res['n1'])}'),
            KpiSigh(
                libelle: 'Total du bilan',
                valeur: money(ta['net']),
                icone: LucideIcons.layers,
                ton: TonSigh.info,
                indice: ta['net'] == tp['net'] ? 'Actif = Passif — le bilan s’équilibre' : 'ACTIF ET PASSIF NE S’ÉQUILIBRENT PAS'),
            KpiSigh(
                libelle: 'Écarts internes du document',
                valeur: nombre(_l.ecarts.length),
                icone: LucideIcons.triangleAlert,
                ton: TonSigh.attention,
                indice: 'Signalés, jamais arbitrés'),
          ]),
          const SizedBox(height: 16),
          NoteSigh(
              'Liasse ${d['denomination']}, IFU ${d['ifu']}, déposée le ${dateDe(d['dateDepot'])} — code ${d['code']}. ${d['administration']}. Référentiel : plan comptable SYSCOHADA révisé (AUDCIF, applicable depuis le 1ᵉʳ janvier 2018).',
              icone: LucideIcons.fileBadge),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(id: 'bilan', libelle: 'Bilan', construire: (_) => _bilan(c, courant, n1)),
            OngletDef(id: 'resultat', libelle: 'Compte de résultat', construire: (_) => _resultat(courant)),
            OngletDef(id: 'flux', libelle: 'Tableau des flux de trésorerie', construire: (_) => _flux()),
            OngletDef(id: 'disponibilites', libelle: 'Disponibilités', construire: (_) => _disponibilites(courant)),
            OngletDef(id: 'synthese', libelle: 'Fiche de synthèse', construire: (_) => _synthese()),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            BoutonSigh(libelle: 'Imprimer le bilan', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c, 'bilan')),
            for (final (lib, cle) in const [
              ('Compte de résultat', 'resultat'),
              ('Flux de trésorerie', 'flux'),
              ('Disponibilités', 'disponibilites'),
              ('Fiche de synthèse', 'synthese'),
            ])
              BoutonSigh(libelle: lib, icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _imprimer(context, c, cle)),
            BoutonSigh(
                libelle: 'Immobilisations',
                icone: LucideIcons.building,
                variante: VarianteBouton.secondaire,
                onPressed: () => c.aller('m12-immobilisations')),
          ]),
          sourceQual(
              'Liasse fiscale déposée le ${dateDe(d['dateDepot'])} (code ${d['code']}) — transcrite feuillet par feuillet. La colonne « exercice en cours » est calculée depuis les écritures validées du journal.'),
        ]);
      },
    );
  }
}
