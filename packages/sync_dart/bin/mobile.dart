import 'package:sigh_sync/sigh_sync.dart';

/// Lancement : `mobile --port=9301 --relais=http://127.0.0.1:9200 --db=m1.sqlite --nom=M1`.
Future<void> main(List<String> args) async {
  final m = Mobile(ConfigMobile(
    port: int.tryParse(arg(args, 'port', '0')) ?? 0,
    relais: arg(args, 'relais', ''),
    dbChemin: arg(args, 'db', ':memory:'),
    nom: arg(args, 'nom', 'mobile'),
    intervalleMs: int.tryParse(arg(args, 'intervalle', '150')) ?? 150,
  ));
  await m.demarrer();
}
