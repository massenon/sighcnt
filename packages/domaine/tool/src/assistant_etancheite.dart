/// Contrôle d'étanchéité des sources de l'outil de mesure de l'assistant (lot AST-0) : une source qui importe autre chose que `dart:core` et `dart:convert` (et `dart:io` pour le seul lanceur
/// qui lit des fichiers), qui dépend d'un paquet, ou qui nomme un client, un serveur, une socket ou un processus, est signalée. Ce fichier NOMME ces jetons : il n'est donc pas lui même
/// soumis au contrôle (il ne s'exécute que dans les tests et le lanceur).
library;


/// Les violations d'étanchéité d'une SOURCE : une importation hors de la liste permise, ou un jeton de réseau ou de processus. [dartIo] : le lanceur en ligne de commande lit et
/// écrit des fichiers, il a droit à `dart:io` (jamais aux sockets, clients et serveurs).
List<String> controleEtancheite(String source, {bool dartIo = false}) {
  final v = <String>[];
  final permis = <String>{'dart:core', 'dart:convert', if (dartIo) 'dart:io'};
  for (final m in RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''', multiLine: true).allMatches(source)) {
    final cible = m.group(1)!;
    if (cible.startsWith('dart:') && !permis.contains(cible)) v.add('importation interdite : $cible');
    if (cible.startsWith('package:') && !cible.startsWith('package:test/')) v.add('dépendance de paquet interdite : $cible');
  }
  const jetons = [
    'Socket', 'HttpClient', 'HttpServer', 'WebSocket', 'RawDatagramSocket', 'Process.', 'Isolate.', 'InternetAddress', 'HttpOverrides.global', 'http://', 'https://', 'package:http',
  ];
  // Les jetons se cherchent hors commentaires (une ligne commençant par `//`).
  final code = source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
  for (final j in jetons) {
    if (code.contains(j)) v.add('jeton réseau ou processus : $j');
  }
  return v;
}

