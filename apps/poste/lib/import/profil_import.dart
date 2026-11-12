import 'package:sigh_domaine/sigh_domaine.dart';

import '../shell/contexte_ecran.dart';

/// Le PROFIL qui importe, tel que le moteur du domaine le lit (`ProfilImport`) : le rôle de la session, son libellé, la matrice d'import EN FORCE (celle de `rbac.json`,
/// superposée à chaud par les fiches RBAC : jamais un nom de rôle en dur) et le réglage `importBornes` (taille maximale d'un fichier par jeu, lue en base).
/// Sans matrice branchée (un écran monté sans coque), le profil n'a AUCUN droit : le moteur refuse.
ProfilImport profilImportDe(ContexteEcran c) {
  final m = c.donnees?.matrice;
  final f = c.magasin.collection('reglages').parId('importBornes');
  final v = f?['valeur'];
  final bornes = <String, int>{};
  if (v is Map) {
    for (final e in v.entries) {
      final n = e.value;
      if (n is num && n > 0 && n.isFinite) bornes['${e.key}'] = n.floor();
    }
  }
  return ProfilImport(role: c.role, libelleRole: m?.libelle(c.role) ?? c.role, matrice: m?.matriceImport ?? MatriceImport.vide, bornes: bornes);
}
