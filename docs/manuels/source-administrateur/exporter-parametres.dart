/* Exporte le registre des paramètres du domaine (cle, famille, defaut, libelle, aide) en JSON pour le chapitre « Registre des paramètres » du manuel.
 * Usage (depuis docs/manuels/source-administrateur, aucun `pub get` requis : le domaine n'a aucune dépendance d'exécution) :
 *   dart --packages=<package_config.json qui mappe sigh_domaine> exporter-parametres.dart > parametres.json
 * où package_config.json contient : {"configVersion":2,"packages":[{"name":"sigh_domaine","rootUri":"file://<arbre>/packages/domaine","packageUri":"lib/","languageVersion":"3.4"}]} */
import 'dart:convert';
import 'package:sigh_domaine/src/parametres/definitions.dart';
void main() {
  final out = [for (final d in definitionsParametres) {'cle': d.cle, 'famille': d.famille, 'type': d.type.name, 'defaut': d.defaut is String && (d.defaut as String).length > 120 ? '(valeur JSON)' : d.defaut, 'libelle': d.libelle, 'aide': d.aide, 'choix': d.choix, 'mobile': d.mobile, 'sensible': d.sensible, 'branche': d.branche, 'source': d.source}];
  print(jsonEncode({'familles': libellesFamillesParametres, 'params': out}));
}
