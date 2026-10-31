import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../shell/contexte_ecran.dart';

/// Aides communes aux sept écrans de M14 (sécurité). Les règles sont dans `packages/domaine/lib/src/securite/` ; ce fichier ne porte que ce qui
/// lit le magasin du poste.

/// `S.collection('rbac')` : une fiche par rôle (les doublons sont fusionnés par [secSurcharges]). On lit `toutes` : une fiche dont le rôle est
/// ARCHIVÉ porte `statut: 'archive'`, ce qui la range parmi les « archivées » du magasin — elle n'en reste pas moins la fiche du rôle.
List<Fiche> fichesRbac(Magasin m) => m.collection('rbac').toutes;

Map<String, Fiche> surchargesRbac(Magasin m) => secSurcharges(fichesRbac(m));

/// `N.ROLES` après `appliquerRenommages()` : les rôles de la matrice engendrée (`rolesBase`) puis ceux créés en exploitation.
List<RoleSec> rolesDe(Magasin m) =>
    secRoles(m.collection('rolesBase').toutes, surchargesRbac(m));

String libelleRole(Magasin m, Object? id) {
  for (final r in rolesDe(m)) {
    if (r.id == id) return r.label;
  }
  return '$id';
}

/// Les rangées du manifeste (`tousModules()` : une entrée PAR RANGÉE, des codes répétés quand un module a une rangée secondaire).
List<Fiche> rangeesManifeste(Magasin m) => m.collection('modulesManifeste').toutes;

/// Les droits effectifs d'un rôle sur un module, surcharges comprises (`N.droits`).
DroitSec droitModule(Magasin m, String role, String code) => secDroitModule(
      role,
      code,
      bases: {for (final b in m.collection('rolesBase').toutes) '${b['id']}': b},
      sur: surchargesRbac(m),
      rolesBase: m.collection('rolesBase').toutes,
    );

/// `permissionsRole(roleId)` : les codes de module (une entrée par rangée) que le rôle VOIT.
List<String> modulesOuverts(Magasin m, String role) {
  final bases = {for (final b in m.collection('rolesBase').toutes) '${b['id']}': b};
  final sur = surchargesRbac(m);
  final base = m.collection('rolesBase').toutes;
  return [
    for (final r in rangeesManifeste(m))
      if (secDroitModule(role, '${r['code']}', bases: bases, sur: sur, rolesBase: base).voir)
        '${r['code']}'
  ];
}

/// `C.initials` : les initiales des deux premiers mots.
String initiales(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((w) => w.isEmpty ? '' : w[0])
    .join()
    .toUpperCase();

/// `C.daysBetween(a, b)` : jours entiers arrondis.
int nbJoursEntre(DateTime a, DateTime b) =>
    (b.difference(a).inMilliseconds / 86400000).round();

DateTime? dateIso(Object? v) => DateTime.tryParse('${v ?? ''}');

String dateFrOuVide(Object? v) {
  final d = dateIso(v);
  return d == null ? '' : dateFR(d);
}

const styleMono = TextStyle(
    fontFamily: 'LiberationMono', fontSize: 12, height: 16 / 12, color: JetonsShell.slate700);

/// La référence d'un état imprimé (`CNT-AAAAMMJJ-NNNN`), comme les écrans de M8.
String referenceImpression(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

/// RG-12 : une action de M14 qui n'écrit pas dans une collection (clôture d'une session, restauration simulée…) se journalise explicitement.
void journaliserM14(ContexteEcran c, String action, String entite, String reference,
        {Object? avant, Object? apres}) =>
    c.magasin.journaliser(action, 'M14', entite, reference, avant, apres);
