import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';

enum TypeChamp {
  texte,
  nombre,
  date,
  email,
  tel,
  textarea,
  select,
  multiselect,
  case_,
  section
}

/// Largeur d'un champ dans la grille à SIX colonnes : `demi` (3), `tiers` (2), `plein` (6). Six se divise par deux ET par trois.
enum ColChamp {
  demi(3),
  tiers(2),
  plein(6);

  const ColChamp(this.colonnes);
  final int colonnes;
}

class OptionChamp {
  const OptionChamp(this.valeur, [String? libelle])
      : libelle = libelle ?? valeur;
  final String valeur;
  final String libelle;
}

class ChampDef {
  const ChampDef({
    required this.nom,
    required this.libelle,
    this.type = TypeChamp.texte,
    this.requis = false,
    this.col = ColChamp.demi,
    this.options = const [],
    this.aide,
    this.indicatif,
    this.lignes = 3,
    this.condition,
    this.valider,
    this.recherche,
  });

  /// Séparateur de section : `col-span-6 border-t pt-3`, libellé 12/16 en 600, majuscules, interlettrage large.
  const ChampDef.section(this.libelle)
      : nom = '',
        type = TypeChamp.section,
        requis = false,
        col = ColChamp.plein,
        options = const [],
        aide = null,
        indicatif = null,
        lignes = 3,
        condition = null,
        valider = null,
        recherche = null;

  final String nom;
  final String libelle;
  final TypeChamp type;
  final bool requis;
  final ColChamp col;
  final List<OptionChamp> options;
  final String? aide;
  final String? indicatif;
  final int lignes;

  /// « N'apparaît que si le champ `controle` prend l'une des valeurs `quand` ». Un champ masqué ne se valide ni ne s'enregistre.
  final ({String controle, List<String> quand})? condition;
  final String? Function(Object? valeur, Map<String, Object?> valeurs)? valider;

  /// `null` : automatique (panneau à recherche dès 9 entrées, comme `U.combo`).
  final bool? recherche;
}

/// État d'un formulaire. Les valeurs sont des chaînes (texte, date ISO, nombre saisi), des `bool` (case) ou des `List<String>`.
class ControleurFormulaire extends ChangeNotifier {
  ControleurFormulaire(this.champs, [Map<String, Object?> initial = const {}]) {
    for (final c in champs) {
      if (c.type == TypeChamp.section) continue;
      var v = initial[c.nom];
      // Une liste native sélectionne d'office sa première entrée : conservé pour les champs obligatoires.
      if (c.type == TypeChamp.select &&
          c.requis &&
          (v == null || v == '') &&
          c.options.isNotEmpty) v = c.options.first.valeur;
      _valeurs[c.nom] = v ??
          (c.type == TypeChamp.multiselect
              ? <String>[]
              : c.type == TypeChamp.case_
                  ? false
                  : '');
    }
  }

  final List<ChampDef> champs;
  final Map<String, Object?> _valeurs = {};
  final Map<String, String> erreurs = {};

  Object? operator [](String nom) => _valeurs[nom];

  void poser(String nom, Object? v) {
    _valeurs[nom] = v;
    erreurs.remove(nom);
    notifyListeners();
  }

  bool visible(ChampDef c) {
    final cond = c.condition;
    if (cond == null) return true;
    final v = _valeurs[cond.controle];
    return v is List
        ? v.any((x) => cond.quand.contains(x))
        : cond.quand.contains('$v');
  }

  /// Valide les champs VISIBLES ; renvoie les valeurs enregistrables (champs masqués exclus) ou `null` si une erreur subsiste.
  Map<String, Object?>? valider() {
    erreurs.clear();
    final sortie = <String, Object?>{};
    for (final c in champs) {
      if (c.type == TypeChamp.section || !visible(c)) continue;
      final v = _valeurs[c.nom];
      final vide = v == null || v == '' || (v is List && v.isEmpty);
      if (c.requis && (vide || (c.type == TypeChamp.case_ && false))) {
        erreurs[c.nom] = 'Ce champ est obligatoire.';
      } else if (c.valider != null && !vide) {
        final m = c.valider!(v, _valeurs);
        if (m != null) erreurs[c.nom] = m;
      }
      sortie[c.nom] = v;
    }
    notifyListeners();
    return erreurs.isEmpty ? sortie : null;
  }
}

InputDecoration decorationChamp(
    {String? indicatif,
    bool erreur = false,
    Widget? prefixe,
    Widget? suffixe}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    hintText: indicatif,
    hintStyle: const TextStyle(
        color: JetonsShell.slate400, fontSize: 14, height: 20 / 14),
    // `.input` : px 12 py 8 + bordure de 1 px AUTOUR (h 38) — la bordure Flutter est intérieure, d'où 9.
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    prefixIcon: prefixe,
    suffixIcon: suffixe,
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    border: b(erreur ? JetonsShell.danger400 : JetonsShell.slate300),
    enabledBorder: b(erreur ? JetonsShell.danger400 : JetonsShell.slate300),
    focusedBorder: b(erreur ? JetonsShell.danger500 : JetonsShell.navy500, 2),
    disabledBorder: b(JetonsShell.slate300),
    errorText: null,
  );
}

const TextStyle styleSaisie =
    TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14);

/// `.label` : 12/16 en 500 slate-600, marge basse 6 ; « * » ajouté aux champs obligatoires.
class LibelleChamp extends StatelessWidget {
  const LibelleChamp(this.texte, {super.key});
  final String texte;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(texte,
          style: const TextStyle(
              color: JetonsShell.slate600,
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w500)));
}

/// `U.form(champs, valeurs)` : grille à six colonnes, espace 16. Sous 640 px, une colonne.
class FormulaireSigh extends StatelessWidget {
  const FormulaireSigh({super.key, required this.controleur});
  final ControleurFormulaire controleur;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controleur,
        builder: (context, _) => LayoutBuilder(builder: (context, c) {
          final large = c.maxWidth >= 640;
          final unite = (c.maxWidth - 5 * 16) / 6;
          double largeur(ChampDef f) => !large || f.col == ColChamp.plein
              ? c.maxWidth
              : f.col.colonnes * unite + (f.col.colonnes - 1) * 16 - 0.001;
          return Wrap(
            key: const Key('kit:formulaire'),
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final (i, f)
                  in controleur.champs.where(controleur.visible).indexed)
                SizedBox(
                    width: largeur(f),
                    child: _Champ(controleur, f, premier: i == 0)),
            ],
          );
        }),
      );
}

class _Champ extends StatelessWidget {
  const _Champ(this.ctl, this.def, {this.premier = false});
  final ControleurFormulaire ctl;
  final ChampDef def;

  /// `first:border-0 first:pt-0` : une section en tête de formulaire n'a ni filet ni marge.
  final bool premier;

  @override
  Widget build(BuildContext context) {
    if (def.type == TypeChamp.section) {
      return Container(
        key: const Key('kit:section'),
        padding: EdgeInsets.only(top: premier ? 0 : 12),
        decoration: premier
            ? null
            : const BoxDecoration(
                border: Border(top: BorderSide(color: JetonsShell.slate200))),
        child: Text(def.libelle.toUpperCase(),
            style: const TextStyle(
                color: JetonsShell.slate500,
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6)),
      );
    }
    final erreur = ctl.erreurs[def.nom];
    final corps = switch (def.type) {
      TypeChamp.case_ => _Case(ctl, def),
      TypeChamp.select ||
      TypeChamp.multiselect =>
        _Liste(ctl, def, erreur != null),
      TypeChamp.date => _Date(ctl, def, erreur != null),
      TypeChamp.textarea =>
        _Texte(ctl, def, erreur != null, lignes: def.lignes),
      _ => _Texte(ctl, def, erreur != null),
    };
    return Column(
        key: Key('kit:champ:${def.nom}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (def.type != TypeChamp.case_)
            LibelleChamp(def.libelle + (def.requis ? ' *' : '')),
          corps,
          if (def.aide != null)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(def.aide!,
                    style: const TextStyle(
                        color: JetonsShell.slate400,
                        fontSize: 12,
                        height: 16 / 12))),
          if (erreur != null)
            Semantics(
                liveRegion: true,
                child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(erreur,
                        style: const TextStyle(
                            color: JetonsShell.danger600,
                            fontSize: 12,
                            height: 16 / 12)))),
        ]);
  }
}

class _Texte extends StatefulWidget {
  const _Texte(this.ctl, this.def, this.erreur, {this.lignes});
  final ControleurFormulaire ctl;
  final ChampDef def;
  final bool erreur;
  final int? lignes;
  @override
  State<_Texte> createState() => _TexteState();
}

class _TexteState extends State<_Texte> {
  late final TextEditingController _t =
      TextEditingController(text: '${widget.ctl[widget.def.nom] ?? ''}');

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    final externe = '${widget.ctl[d.nom] ?? ''}';
    if (_t.text != externe) _t.text = externe;
    return Semantics(
      textField: true,
      label: d.libelle,
      child: TextField(
        controller: _t,
        minLines: widget.lignes,
        maxLines: widget.lignes ?? 1,
        keyboardType: switch (d.type) {
          TypeChamp.nombre =>
            const TextInputType.numberWithOptions(decimal: true),
          TypeChamp.email => TextInputType.emailAddress,
          TypeChamp.tel => TextInputType.phone,
          _ => widget.lignes != null
              ? TextInputType.multiline
              : TextInputType.text,
        },
        style: styleSaisie,
        decoration:
            decorationChamp(indicatif: d.indicatif, erreur: widget.erreur),
        onChanged: (v) => widget.ctl.poser(d.nom, v),
      ),
    );
  }
}

class _Case extends StatelessWidget {
  const _Case(this.ctl, this.def);
  final ControleurFormulaire ctl;
  final ChampDef def;
  @override
  Widget build(BuildContext context) {
    final coche = ctl[def.nom] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: InkWell(
        onTap: () => ctl.poser(def.nom, !coche),
        child: Semantics(
          checked: coche,
          label: def.libelle,
          excludeSemantics: true,
          onTap: () => ctl.poser(def.nom, !coche),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  color: coche ? JetonsShell.navy900 : Colors.white,
                  border: Border.all(
                      color:
                          coche ? JetonsShell.navy900 : JetonsShell.slate300),
                  borderRadius: BorderRadius.circular(4)),
              child: coche
                  ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(def.libelle,
                style: const TextStyle(
                    color: JetonsShell.slate700,
                    fontSize: 14,
                    height: 20 / 14)),
          ]),
        ),
      ),
    );
  }
}

class _Date extends StatelessWidget {
  const _Date(this.ctl, this.def, this.erreur);
  final ControleurFormulaire ctl;
  final ChampDef def;
  final bool erreur;

  @override
  Widget build(BuildContext context) {
    final v = '${ctl[def.nom] ?? ''}';
    return Semantics(
      button: true,
      label: '${def.libelle}, ${v.isEmpty ? 'non renseignée' : v}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () async {
          final base = DateTime.tryParse(v) ?? DateTime.now();
          final d = await showDatePicker(
              context: context,
              initialDate: base,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              locale: const Locale('fr'));
          if (d != null)
            ctl.poser(def.nom,
                '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
        },
        child: InputDecorator(
          decoration: decorationChamp(
              erreur: erreur,
              suffixe: const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(LucideIcons.calendar,
                      size: 16, color: JetonsShell.slate400))),
          child: Text(v.isEmpty ? 'jj/mm/aaaa' : _fr(v),
              style: v.isEmpty
                  ? styleSaisie.copyWith(color: JetonsShell.slate400)
                  : styleSaisie),
        ),
      ),
    );
  }

  static String _fr(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }
}

/// `U.combo` : liste simple, ou panneau à recherche dès NEUF entrées (ou `recherche: true`) ; `multiselect` : cases à cocher,
/// le panneau reste ouvert d'un choix à l'autre.
class _Liste extends StatelessWidget {
  const _Liste(this.ctl, this.def, this.erreur);
  final ControleurFormulaire ctl;
  final ChampDef def;
  final bool erreur;

  bool get _multi => def.type == TypeChamp.multiselect;

  String _resume() {
    final v = ctl[def.nom];
    if (_multi) {
      final l = (v as List).cast<String>();
      if (l.isEmpty) return '';
      return l
          .map((x) => def.options
              .firstWhere((o) => o.valeur == x, orElse: () => OptionChamp(x))
              .libelle)
          .join(', ');
    }
    return def.options
            .where((o) => o.valeur == v)
            .map((o) => o.libelle)
            .firstOrNull ??
        '';
  }

  @override
  Widget build(BuildContext context) {
    final resume = _resume();
    final vide = resume.isEmpty;
    return Semantics(
      button: true,
      label: '${def.libelle}, ${vide ? 'aucune sélection' : resume}',
      excludeSemantics: true,
      child: Builder(
        builder: (ctx) => InkWell(
          onTap: () => _ouvrir(ctx),
          child: InputDecorator(
            decoration: decorationChamp(
                erreur: erreur,
                suffixe: const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(LucideIcons.chevronDown,
                        size: 16, color: JetonsShell.slate400))),
            child: Text(
                vide
                    ? (def.indicatif ??
                        (_multi ? '— Aucune sélection —' : '— Sélectionner —'))
                    : resume,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: vide
                    ? styleSaisie.copyWith(color: JetonsShell.slate400)
                    : styleSaisie),
          ),
        ),
      ),
    );
  }

  void _ouvrir(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    showGeneralDialog<void>(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'Fermer la liste',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => Stack(children: [
        Positioned(
            left: pos.dx,
            top: pos.dy + box.size.height + 4,
            width: box.size.width,
            child: _PanneauListe(
                ctl, def, _multi, def.recherche ?? def.options.length >= 9)),
      ]),
    );
  }
}

class _PanneauListe extends StatefulWidget {
  const _PanneauListe(this.ctl, this.def, this.multi, this.recherche);
  final ControleurFormulaire ctl;
  final ChampDef def;
  final bool multi;
  final bool recherche;
  @override
  State<_PanneauListe> createState() => _PanneauListeState();
}

class _PanneauListeState extends State<_PanneauListe> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    final options = d.options.where((o) => correspond(o.libelle, _q)).toList();
    final valeur = widget.ctl[d.nom];
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: JetonsShell.slate200)),
      child: DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: JetonsShell.ombrePop),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.recherche)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      autofocus: true,
                      style: styleSaisie,
                      decoration: decorationChamp(
                          indicatif: 'Rechercher…',
                          prefixe: const Padding(
                              padding: EdgeInsets.only(left: 10, right: 6),
                              child: Icon(LucideIcons.search,
                                  size: 16, color: JetonsShell.slate400))),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 288),
                  child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        if (!widget.multi && !d.requis)
                          _Ligne(
                              libelle: d.indicatif ?? '— Aucun —',
                              actif: valeur == '',
                              multi: false,
                              surClic: () {
                                widget.ctl.poser(d.nom, '');
                                Navigator.of(context).pop();
                              }),
                        for (final o in options)
                          _Ligne(
                            libelle: o.libelle,
                            multi: widget.multi,
                            actif: widget.multi
                                ? (valeur as List).contains(o.valeur)
                                : valeur == o.valeur,
                            surClic: () {
                              if (widget.multi) {
                                final l = [...(valeur as List).cast<String>()];
                                l.contains(o.valeur)
                                    ? l.remove(o.valeur)
                                    : l.add(o.valeur);
                                widget.ctl.poser(d.nom, l);
                                setState(() {});
                              } else {
                                widget.ctl.poser(d.nom, o.valeur);
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        if (options.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('Aucun résultat',
                                  style: TextStyle(
                                      color: JetonsShell.slate500,
                                      fontSize: 14))),
                      ]),
                ),
              ]),
        ),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne(
      {required this.libelle,
      required this.actif,
      required this.multi,
      required this.surClic});
  final String libelle;
  final bool actif;
  final bool multi;
  final VoidCallback surClic;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: surClic,
        hoverColor: JetonsShell.slate50,
        child: Semantics(
          selected: actif,
          button: true,
          label: libelle,
          excludeSemantics: true,
          child: Container(
            color: actif && !multi ? JetonsShell.navy50 : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              if (multi) ...[
                Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                        color: actif ? JetonsShell.navy900 : Colors.white,
                        border: Border.all(
                            color: actif
                                ? JetonsShell.navy900
                                : JetonsShell.slate300),
                        borderRadius: BorderRadius.circular(4)),
                    child: actif
                        ? const Icon(LucideIcons.check,
                            size: 12, color: Colors.white)
                        : null),
                const SizedBox(width: 8),
              ],
              Expanded(
                  child: Text(libelle,
                      style: TextStyle(
                          color: JetonsShell.slate900,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: actif && !multi
                              ? FontWeight.w600
                              : FontWeight.w400))),
              if (actif && !multi)
                const Icon(LucideIcons.check,
                    size: 16, color: JetonsShell.navy900),
            ]),
          ),
        ),
      );
}
