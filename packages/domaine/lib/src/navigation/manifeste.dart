/// Manifeste de navigation de la maquette (`packages/referentiels/data/manifeste.json`, ENGENDRÉ par `nav.js`) et RUBAN
/// qu'il produit pour un rôle. La navigation est DÉRIVÉE : aucun lien écrit à la main, aucun écran affiché hors droits.
library;

import '../droits/matrice.dart';

class EcranNav {
  const EcranNav({required this.id, required this.label, required this.icone, required this.module, required this.moduleLabel, required this.domaine, required this.hub, required this.standalone});
  final String id;
  final String label;
  final String? icone;
  final String module;
  final String moduleLabel;
  final String domaine;
  final bool hub;
  final bool standalone;
}

class RangeeManifeste {
  const RangeeManifeste({required this.domaine, required this.code, required this.label, required this.icone, required this.alias, required this.secondaire, required this.ecrans});
  final String domaine;
  final String code;
  final String label;
  final String? icone;

  /// Alias : réunit des écrans d'un autre module sans les dupliquer. Secondaire : rangée de plus pour un module existant.
  final bool alias;
  final bool secondaire;
  final List<String> ecrans;
}

class DomaineManifeste {
  const DomaineManifeste(this.nom, this.icone);
  final String nom;
  final String? icone;
}

/// Une rangée du ruban APRÈS filtrage par les droits : seuls les écrans que le rôle voit.
class RangeeRuban {
  const RangeeRuban({required this.code, required this.label, required this.icone, required this.hub, required this.ecrans});
  final String code;
  final String label;
  final String? icone;

  /// Identifiant de la page d'accueil du module (cartes de ses écrans).
  final String hub;
  final List<EcranNav> ecrans;
}

class DomaineRuban {
  const DomaineRuban({required this.nom, required this.icone, required this.rangees});
  final String nom;
  final String? icone;
  final List<RangeeRuban> rangees;
  int get nombreEcrans => rangees.fold(0, (n, r) => n + r.ecrans.length);
}

/// Domaines réservés au mode MÈRE : ils n'existent pas sur un poste fileul, quels que soient les droits.
const domainesMere = {'Poste mère'};

/// Raccourci permanent du ruban (`N.RACCOURCIS`) : ouvre la page d'accueil d'un module, si le rôle en voit au moins un écran.
class RaccourciRuban {
  const RaccourciRuban({required this.court, required this.hub, required this.icone});
  final String court;
  final String hub;
  final String? icone;
}

class Manifeste {
  Manifeste._(this.domaines, this.rangees, this._ecrans, this._raccourcis);
  final List<DomaineManifeste> domaines;
  final List<({String code, String court})> _raccourcis;
  final List<RangeeManifeste> rangees;
  final Map<String, EcranNav> _ecrans;

  factory Manifeste.depuisJson(Map<String, Object?> j) {
    String? s(Object? v) => v == null ? null : '$v';
    final ecrans = <String, EcranNav>{};
    for (final raw in (j['ecrans'] as List)) {
      final e = (raw as Map).cast<String, Object?>();
      ecrans['${e['id']}'] = EcranNav(
        id: '${e['id']}', label: '${e['label']}', icone: s(e['icone']), module: '${e['module']}', moduleLabel: '${e['moduleLabel']}',
        domaine: '${e['domaine']}', hub: e['hub'] == true, standalone: e['standalone'] == true,
      );
    }
    return Manifeste._(
      [for (final d in (j['domaines'] as List)) DomaineManifeste('${(d as Map)['nom']}', s(d['icone']))],
      [
        for (final raw in (j['modules'] as List))
          () {
            final m = (raw as Map).cast<String, Object?>();
            return RangeeManifeste(
              domaine: '${m['domaine']}', code: '${m['code']}', label: '${m['label']}', icone: s(m['icone']),
              alias: m['alias'] == true, secondaire: m['secondaire'] == true, ecrans: ((m['ecrans'] ?? const []) as List).cast<String>(),
            );
          }(),
      ],
      ecrans,
      [for (final r in ((j['raccourcis'] ?? const []) as List)) (code: '${(r as Map)['code']}', court: '${r['court']}')],
    );
  }

  /// Les raccourcis permanents que ce ruban peut montrer : seulement ceux dont le module a un écran visible.
  List<RaccourciRuban> raccourcis(List<DomaineRuban> ruban) {
    final rangees = ruban.expand((d) => d.rangees).toList();
    return [
      for (final r in _raccourcis)
        if (rangees.any((x) => x.code == r.code)) RaccourciRuban(court: r.court, hub: 'hub-${r.code.toLowerCase()}', icone: rangees.firstWhere((x) => x.code == r.code).icone),
    ];
  }

  EcranNav? ecran(String id) => _ecrans[id];
  Iterable<EcranNav> get tousLesEcrans => _ecrans.values;

  /// Le ruban d'un rôle. `estMere` ouvre les domaines réservés à la mère ; il ne les OUVRE pas aux rôles sans droit :
  /// les droits restent ceux de la matrice.
  List<DomaineRuban> ruban(MatriceDroits matrice, String role, {required bool estMere}) {
    final out = <DomaineRuban>[];
    for (final d in domaines) {
      if (!estMere && domainesMere.contains(d.nom)) continue;
      final rangees = <RangeeRuban>[];
      for (final r in this.rangees.where((r) => r.domaine == d.nom)) {
        final visibles = [
          for (final id in r.ecrans)
            if (_ecrans[id] != null && matrice.peutVoir(role, id)) _ecrans[id]!,
        ];
        if (visibles.isEmpty) continue;
        rangees.add(RangeeRuban(code: r.code, label: r.label, icone: r.icone, hub: 'hub-${r.code.toLowerCase()}', ecrans: visibles));
      }
      if (rangees.isNotEmpty) out.add(DomaineRuban(nom: d.nom, icone: d.icone, rangees: rangees));
    }
    return out;
  }
}
