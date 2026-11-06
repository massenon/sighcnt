import 'package:sigh_sync/sigh_sync.dart';

/// Lancement : `pair --port=9201 --relais=http://127.0.0.1:8000 --db=f1.sqlite --nom=F1 --cle=<256 bits en hexadécimal> [--intervalle-ms=120]`.
Future<void> main(List<String> args) async {
  final p = FileulPair(ConfigPair(
    port: int.tryParse(arg(args, 'port', '0')) ?? 0,
    relais: arg(args, 'relais', ''),
    dbChemin: arg(args, 'db', ':memory:'),
    nom: arg(args, 'nom', 'poste'),
    cleHex: arg(args, 'cle', ''),
    decalageMs: int.tryParse(arg(args, 'horloge-decalage-ms', '0')) ?? 0,
    collectionsCopie: arg(args, 'copie', '').split(',').where((c) => c.isNotEmpty).toSet(),
    intervalleMs: int.tryParse(arg(args, 'intervalle-ms', '120')) ?? 120,
  ));
  await p.demarrer();
}
