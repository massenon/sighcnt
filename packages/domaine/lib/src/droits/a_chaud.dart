/// SUPERPOSITION À CHAUD des droits : la matrice du poste n'est plus figée au jour de l'extraction. Elle est RECALCULÉE à partir du manifeste de
/// navigation (les rôles que la maquette ouvre à chaque écran), des fiches de la collection `rbac` (une par rôle : `voir` / `editer` / `annuler` par
/// module et par écran, archivage, renommage, rôle créé) et de la collection `modulesActifs` (activités fermées), exactement comme `N.can()`,
/// `N.droits()` et `N.droitsEcran()` de `prototype_html/assets/js/nav.js`.
///
/// Règles reprises de la maquette (CLAUDE.md, vagues 15, 24, 50, 53, 67) :
///  * un écran l'emporte sur son module ; un écran non réglé suit son module ;
///  * une surcharge qui pose `voir: true` ACCORDE (un rôle créé part de zéro et s'ouvre par surcharge) ;
///  * une activité fermée se ferme pour TOUS les rôles, administrateur compris, et rien ne la rouvre, pas même une surcharge ;
///  * une fiche de fermeture ARCHIVÉE ne ferme plus rien (RG-14) ;
///  * le NOYAU (CFG, DASH) ne se ferme pas : une fiche qui fermerait le module entier est ignorée ;
///  * un écran universel est ouvert à tout poste (voir et éditer, jamais annuler), cède devant une surcharge d'écran explicite, ne rouvre pas
///    un module fermé ;
///  * un rôle archivé n'ouvre plus rien ; une page de saisie (`servant`) résout ses droits sur le registre qu'elle alimente.
library;

import '../configuration/cfb_donnees.dart' show cfbNoyau;
import '../configuration/cfb_regles.dart' show CfbFermetures;
import '../navigation/manifeste.dart';
import 'matrice.dart';

typedef _Fiche = Map<String, Object?>;

/// Fusion champ par champ des fiches d'un même rôle : la dernière l'emporte sur ce qu'elle définit seulement (`surcharges()` de la maquette).
Map<String, Map<String, Object?>> surchargesParRole(Iterable<Map<String, Object?>> fiches) {
  final out = <String, _Fiche>{};
  for (final f in fiches) {
    final role = f['role'];
    if (role == null || '$role'.isEmpty) continue;
    final deja = out['$role'];
    if (deja == null) {
      out['$role'] = {...f};
      continue;
    }
    final fusion = {...deja};
    f.forEach((k, v) {
      if (v == null) return;
      if (k == 'droits' || k == 'droitsEcrans') {
        fusion[k] = {
          ...((deja[k] as Map?)?.cast<String, Object?>() ?? const {}),
          ...((v as Map?)?.cast<String, Object?>() ?? const {})
        };
        return;
      }
      fusion[k] = v;
    });
    out['$role'] = fusion;
  }
  return out;
}

bool _fermeLeNoyau(_Fiche f) {
  final ids = f['ecrans'];
  if (ids is List && ids.isNotEmpty) return false;
  return cfbNoyau.containsKey('${f['module']}');
}

/// Les fermetures en vigueur, noyau protégé : une fiche qui fermerait le module CFG ou DASH en entier est ignorée.
CfbFermetures fermeturesEnVigueur(Iterable<Map<String, Object?>> modulesActifs) => CfbFermetures.depuis([
      for (final f in modulesActifs)
        if (!_fermeLeNoyau(f)) f
    ]);

/// Recalcule la matrice des droits. `base` ne fournit que la liste des rôles (libellés d'origine, couleurs, accueils) ; les droits ne viennent
/// que du manifeste et des fiches.
MatriceDroits superposerDroits(MatriceDroits base, Manifeste manifeste,
    {Iterable<Map<String, Object?>> rbac = const [], Iterable<Map<String, Object?>> modulesActifs = const []}) {
  final sur = surchargesParRole(rbac);
  final ferm = fermeturesEnVigueur(modulesActifs);

  // La rangée CANONIQUE de chaque code fait seule foi pour les droits d'origine (pas d'alias, pas de rangée secondaire).
  final canonique = <String, RangeeManifeste>{};
  for (final r in manifeste.rangees) {
    if (r.alias || r.secondaire) continue;
    canonique.putIfAbsent(r.code, () => r);
  }

  bool archive(String role) => sur[role]?['statut'] == 'archive';

  ({bool voir, bool editer, bool annuler, bool horsMatrice}) origine(String role, String code) {
    final mod = canonique[code];
    // Écran hors ruban (AUTH, SUP) : la matrice ne le gouverne pas.
    if (mod == null) return (voir: true, editer: true, annuler: true, horsMatrice: true);
    final ouvert = mod.ecrans.any((id) {
      final roles = manifeste.ecran(id)?.roles;
      return roles == null || roles.contains(role);
    });
    return (voir: ouvert, editer: ouvert, annuler: ouvert, horsMatrice: false);
  }

  Map<String, Object?>? mapDe(Object? v) => v is Map ? v.cast<String, Object?>() : null;
  bool? bool3(Object? v) => v == null ? null : v == true;

  Droit droitsModule(String role, String code) {
    final b = origine(role, code);
    if (b.horsMatrice) return const Droit(voir: true, editer: true, annuler: true);
    if (archive(role)) return Droit.aucun;
    final o = mapDe(mapDe(sur[role]?['droits'])?[code]);
    if (o == null) return Droit(voir: b.voir, editer: b.editer, annuler: b.annuler);
    final voir = bool3(o['voir']) ?? b.voir;
    final editer = voir && (bool3(o['editer']) ?? b.editer);
    final annuler = voir && (bool3(o['annuler']) ?? b.annuler);
    return Droit(voir: voir, editer: editer, annuler: annuler);
  }

  Droit droitsEcran(String role, EcranNav e) {
    final baseDroit = droitsModule(role, e.module);
    final o = mapDe(mapDe(sur[role]?['droitsEcrans'])?[e.id]);
    if (o == null && e.universel) {
      // Voir et écrire (exprimer un besoin) ; jamais ANNULER, qui reste ce que le module donne.
      return Droit(voir: true, editer: true, annuler: baseDroit.annuler);
    }
    if (o == null) return baseDroit;
    final voir = bool3(o['voir']) ?? baseDroit.voir;
    final editer = voir && (bool3(o['editer']) ?? baseDroit.editer);
    final annuler = voir && (bool3(o['annuler']) ?? baseDroit.annuler);
    return Droit(voir: voir, editer: editer, annuler: annuler);
  }

  bool? surchargeEcranExplicite(String role, String id) => bool3(mapDe(mapDe(sur[role]?['droitsEcrans'])?[id])?['voir']);
  bool? surchargeExplicite(String role, String id, String code) =>
      surchargeEcranExplicite(role, id) ?? bool3(mapDe(mapDe(sur[role]?['droits'])?[code])?['voir']);

  bool can(String role, EcranNav e) {
    if (archive(role)) return false;
    final s = e.servant;
    if (s != null && s != e.id) {
      final cible = manifeste.ecran(s);
      if (cible != null) return can(role, cible);
    }
    final code = e.module;
    if (!ferm.ecranActif(e.id, code)) return false;
    final explicite = e.universel ? surchargeEcranExplicite(role, e.id) : surchargeExplicite(role, e.id, code);
    if (explicite == false) return false;
    if (explicite == true) return true;
    if (e.universel) return true;
    final roles = e.roles;
    if (roles != null && !roles.contains(role)) return false;
    if (code.isEmpty) return true;
    return droitsEcran(role, e).voir;
  }

  // Les rôles : ceux de la matrice engendrée, puis ceux que l'administrateur a CRÉÉS (`nouveau`), qui partent de zéro.
  final connus = <String>{for (final r in base.rolesBruts) '${r['id']}'};
  final roles = <Map<String, Object?>>[
    for (final r in base.rolesBruts) {...r},
    for (final e in sur.entries)
      if (e.value['nouveau'] == true && !connus.contains(e.key))
        {
          'id': e.key,
          'label': e.value['libelle'] ?? e.key,
          'short': e.value['libelleCourt'] ?? e.value['libelle'] ?? e.key,
          'home': e.value['accueil'] ?? 'plan-du-site',
          'labelOrigine': e.value['libelle'] ?? e.key,
          'shortOrigine': e.value['libelle'] ?? e.key,
        }
  ];
  final libelles = <String, String>{};
  final accueils = <String, String>{};
  final archives = <String>{};
  final parRole = <String, Map<String, Droit>>{};
  for (final r in roles) {
    final id = '${r['id']}';
    final lib = sur[id]?['libelle'];
    final origine = r['labelOrigine'] ?? r['label'];
    libelles[id] = (lib != null && '$lib'.isNotEmpty) ? '$lib' : '$origine';
    if (r['home'] != null) accueils[id] = '${r['home']}';
    if (archive(id)) archives.add(id);
    final droits = <String, Droit>{};
    if (!archive(id)) {
      for (final e in manifeste.tousLesEcrans) {
        if (e.hub || !can(id, e)) continue;
        // Une page de saisie porte les droits du registre qu'elle alimente (`app.droits` : `N.ecranDesDroits`).
        final s = e.servant == null ? null : manifeste.ecran(e.servant!);
        droits[e.id] = droitsEcran(id, s ?? e);
      }
    }
    parRole[id] = droits;
  }
  return MatriceDroits.assemblee(
      parRole: parRole, archives: archives, libelles: libelles, accueils: accueils, rolesBruts: roles, fermetures: ferm);
}
