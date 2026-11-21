import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';

/// LOT PAIE-V (Direction, 20/11/2026) : la saisie de PLUSIEURS versements dans une seule fenêtre (type, modalité, opérateur du mobile money, référence de la transaction saisie
/// à la main, montant). Les listes viennent de `modalitesVersement` (en base, versions datées) : rien n'est écrit en dur. Le reste dû après ces versements se calcule en direct.
/// Le contrôle (refus nommés) est celui du MOTEUR, appelé à la validation : cette saisie ne décide de rien.
class ControleurSaisieVersements {
  List<Map<String, Object?>>? Function()? _lire;

  /// Les versements saisis, ou null si une ligne comporte une erreur (les champs fautifs sont marqués).
  List<Map<String, Object?>>? lire() => _lire?.call();
}

class SaisieVersements extends StatefulWidget {
  const SaisieVersements({super.key, required this.fiches, required this.jour, required this.reste, required this.controleur});
  final List<Fiche> fiches;
  final String jour;
  final num reste;
  final ControleurSaisieVersements controleur;

  @override
  State<SaisieVersements> createState() => _SaisieVersementsState();
}

class _SaisieVersementsState extends State<SaisieVersements> {
  final List<ControleurFormulaire> _lignes = [];

  List<Fiche> _actives(String famille) => d.modalitesVersementActives(widget.fiches, famille, widget.jour);

  ControleurFormulaire _nouvelle({String? type, num? montant}) {
    final types = _actives('type'), modalites = _actives('modalite'), operateurs = _actives('operateur');
    final exigeOperateur = [for (final x in modalites) if (x['exigeOperateur'] == true) '${x['code']}'];
    final c = ControleurFormulaire([
      ChampDef(nom: 'type', libelle: 'Type', type: TypeChamp.select, requis: true, options: [for (final x in types) OptionChamp('${x['code']}', '${x['libelle']}')]),
      ChampDef(nom: 'modalite', libelle: 'Modalité', type: TypeChamp.select, requis: true, options: [for (final x in modalites) OptionChamp('${x['code']}', '${x['libelle']}')]),
      ChampDef(
          nom: 'operateur',
          libelle: 'Opérateur',
          type: TypeChamp.select,
          requis: true,
          options: [for (final x in operateurs) OptionChamp('${x['code']}', '${x['libelle']}')],
          condition: (controle: 'modalite', quand: exigeOperateur)),
      const ChampDef(nom: 'referenceTransaction', libelle: 'Référence de la transaction', aide: 'Obligatoire pour le mobile money : à relever sur le message de l’opérateur.'),
      const ChampDef(nom: 'montant', libelle: 'Montant (FCFA)', type: TypeChamp.nombre, requis: true),
    ], {
      if (type != null) 'type': type,
      if (montant != null) 'montant': '${montant.round()}',
    });
    c.addListener(_maj);
    return c;
  }

  void _maj() => setState(() {});

  @override
  void initState() {
    super.initState();
    final types = _actives('type');
    _lignes.add(_nouvelle(type: types.any((t) => t['code'] == 'solde') ? 'solde' : (types.isEmpty ? null : '${types.first['code']}'), montant: widget.reste > 0 ? widget.reste : null));
    widget.controleur._lire = _lire;
  }

  @override
  void dispose() {
    for (final c in _lignes) {
      c.removeListener(_maj);
    }
    super.dispose();
  }

  List<Map<String, Object?>>? _lire() {
    final sortie = <Map<String, Object?>>[];
    var ok = true;
    for (final c in _lignes) {
      final v = c.valider();
      if (v == null) {
        ok = false;
        continue;
      }
      final ref = '${v['referenceTransaction'] ?? ''}'.trim();
      final montant = num.tryParse('${v['montant']}'.trim());
      sortie.add({
        'type': v['type'],
        'modalite': v['modalite'],
        if (v['operateur'] != null && '${v['operateur']}'.isNotEmpty) 'operateur': v['operateur'],
        if (ref.isNotEmpty) 'referenceTransaction': ref,
        'montant': montant ?? '${v['montant']}',
      });
    }
    return ok ? sortie : null;
  }

  num get _total => _lignes.fold<num>(0, (a, c) => a + (num.tryParse('${c['montant'] ?? ''}'.trim()) ?? 0));

  @override
  Widget build(BuildContext context) {
    final apres = widget.reste - _total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < _lignes.length; i++)
        Container(
          key: ValueKey('versement-ligne-$i'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: JetonsShell.slate300), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormulaireSigh(controleur: _lignes[i]),
            if (_lignes.length > 1)
              Align(
                  alignment: Alignment.centerRight,
                  child: BoutonSigh(
                      key: ValueKey('versement-retirer-$i'),
                      libelle: 'Retirer ce versement',
                      variante: VarianteBouton.secondaire,
                      taille: TailleBouton.sm,
                      onPressed: () => setState(() {
                            _lignes[i].removeListener(_maj);
                            _lignes.removeAt(i);
                          }))),
          ]),
        ),
      Align(
          alignment: Alignment.centerLeft,
          child: BoutonSigh(
              key: const ValueKey('versement-ajouter'),
              libelle: 'Ajouter un versement',
              icone: LucideIcons.plus,
              variante: VarianteBouton.secondaire,
              taille: TailleBouton.sm,
              onPressed: () => setState(() => _lignes.add(_nouvelle(type: 'solde'))))),
      const SizedBox(height: 8),
      Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: JetonsShell.slate50, border: Border.all(color: JetonsShell.slate300), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total saisi : ${d.money(_total)}', key: const ValueKey('versement-total-saisi')),
            Text(apres < 0 ? 'Dépasse le dû de ${d.money(-apres)}' : 'Reste dû après ces versements : ${d.money(apres)}',
                key: const ValueKey('versement-reste-apres'), style: TextStyle(fontWeight: FontWeight.w600, color: apres < 0 ? JetonsShell.danger600 : null)),
            if (apres > 0 && _total > 0)
              const Text('Le reste se règle le jour même. Une prestation n’est exécutée que lorsque sa ligne est entièrement payée.', style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
          ])),
    ]);
  }
}
