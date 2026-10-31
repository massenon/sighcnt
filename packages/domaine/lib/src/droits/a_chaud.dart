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

/// Le résultat d'un calcul complet : tout ce qu'une matrice porte.
typedef _Calcul = ({
  Map<String, Map<String, Droit>> parRole,
  Set<String> archives,
  Map<String, String> libelles,
  Map<String, String> accueils,
  List<Map<String, Object?>> roles,
  CfbFermetures fermetures
});

/// Calcule la matrice COMPLÈTE depuis le manifeste et les fiches. `base` ne fournit que la liste des rôles (libellés d'origine, couleurs, accueils).
_Calcul _calculer(MatriceDroits base, Manifeste manifeste, Iterable<Map<String, Object?>> rbac, Iterable<Map<String, Object?>> modulesActifs) {
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
  return (parRole: parRole, archives: archives, libelles: libelles, accueils: accueils, roles: roles, fermetures: ferm);
}

MatriceDroits _assembler(_Calcul c) => MatriceDroits.assemblee(
    parRole: c.parRole, archives: c.archives, libelles: c.libelles, accueils: c.accueils, rolesBruts: c.roles, fermetures: c.fermetures);

/// Superpose les fiches à la matrice.
///
///  * SANS référence (`referenceRbac` et `referenceModules` absents) : la matrice est entièrement RECALCULÉE depuis le manifeste et les fiches ;
///  * AVEC référence : les fiches qu'a connues l'extraction de la matrice engendrée (le jeu livré). La matrice engendrée reste la BASE : seules les
///    cases (rôle, écran) que les fiches d'aujourd'hui font changer par rapport à celles de l'extraction sont remplacées, de même que les rôles
///    dont l'archivage, le libellé ou l'accueil a changé. Fiches inchangées, matrice inchangée, case pour case. C'est ce qui rend effective une décision
///    saisie depuis (m14-roles, cfg-modules) sans jamais réécrire ce que la maquette a extrait.
MatriceDroits superposerDroits(MatriceDroits base, Manifeste manifeste,
    {Iterable<Map<String, Object?>> rbac = const [],
    Iterable<Map<String, Object?>> modulesActifs = const [],
    Iterable<Map<String, Object?>>? referenceRbac,
    Iterable<Map<String, Object?>>? referenceModules}) {
  final maintenant = _calculer(base, manifeste, rbac, modulesActifs);
  if (referenceRbac == null && referenceModules == null) return _assembler(maintenant);
  final ref = _calculer(base, manifeste, referenceRbac ?? const [], referenceModules ?? const []);

  final parRole = <String, Map<String, Droit>>{};
  final archives = <String>{};
  final libelles = <String, String>{};
  final accueils = <String, String>{};
  final connus = <String>{for (final r in base.rolesBruts) '${r['id']}'};
  for (final r in maintenant.roles) {
    final id = '${r['id']}';
    if (!connus.contains(id)) {
      // Un rôle CRÉÉ depuis l'extraction : rien dans la matrice engendrée, tout vient des fiches.
      parRole[id] = maintenant.parRole[id] ?? {};
      libelles[id] = maintenant.libelles[id] ?? id;
      if (maintenant.accueils[id] != null) accueils[id] = maintenant.accueils[id]!;
      if (maintenant.archives.contains(id)) archives.add(id);
      continue;
    }
    final n = maintenant.parRole[id] ?? const <String, Droit>{};
    final e = ref.parRole[id] ?? const <String, Droit>{};
    final b = base.parRoleBrut(id);
    final cases = <String, Droit>{...b};
    for (final ecran in {...n.keys, ...e.keys}) {
      final dn = n[ecran] ?? Droit.aucun, de = e[ecran] ?? Droit.aucun;
      if (dn == de) continue;
      if (dn == Droit.aucun || !dn.voir) {
        cases.remove(ecran);
      } else {
        cases[ecran] = dn;
      }
    }
    parRole[id] = cases;
    final archiveChange = maintenant.archives.contains(id) != ref.archives.contains(id);
    if (archiveChange ? maintenant.archives.contains(id) : base.estArchive(id)) archives.add(id);
    libelles[id] = maintenant.libelles[id] != ref.libelles[id] ? maintenant.libelles[id]! : (base.libelle(id) ?? maintenant.libelles[id]!);
    final acc = maintenant.accueils[id] != ref.accueils[id] ? maintenant.accueils[id] : base.accueil(id);
    if (acc != null) accueils[id] = acc;
  }
  return MatriceDroits.assemblee(
      parRole: parRole,
      archives: archives,
      libelles: libelles,
      accueils: accueils,
      rolesBruts: maintenant.roles,
      fermetures: maintenant.fermetures);
}
