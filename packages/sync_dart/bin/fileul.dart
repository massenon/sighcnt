import 'package:sigh_sync/sigh_sync.dart';

/// Lancement : `fileul --port=9101 --mere=http://127.0.0.1:9000 --db=f1.sqlite --nom=F1 [--horloge-decalage-ms=0]`.
Future<void> main(List<String> args) async {
  final f = Fileul(ConfigFileul(
    port: int.tryParse(arg(args, 'port', '0')) ?? 0,
    mere: arg(args, 'mere', 'http://127.0.0.1:9000'),
    dbChemin: arg(args, 'db', ':memory:'),
    nom: arg(args, 'nom', 'poste'),
    decalageMs: int.tryParse(arg(args, 'horloge-decalage-ms', '0')) ?? 0,
    intervalleMs: int.tryParse(arg(args, 'intervalle', '150')) ?? 150,
  ));
  await f.demarrer();
}
