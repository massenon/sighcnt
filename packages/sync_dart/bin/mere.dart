import 'package:sigh_sync/sigh_sync.dart';

/// Lancement : `mere --port=9000 --db=mere.sqlite --admin=secret [--relais=URL --cle=BASE64 --restaurer=1]`.
/// Écrit `PRET <port>` sur la sortie standard dès que le service écoute.
Future<void> main(List<String> args) async {
  final m = await Mere.creer(ConfigMere(
    port: int.tryParse(arg(args, 'port', '0')) ?? 0,
    dbChemin: arg(args, 'db', ':memory:'),
    admin: arg(args, 'admin', 'admin-banc'),
    codeTtl: int.tryParse(arg(args, 'code-ttl', '900000')) ?? 900000,
    jetonTtl: int.tryParse(arg(args, 'jeton-ttl', '86400000')) ?? 86400000,
    relais: arg(args, 'relais', ''),
    secretRelais: arg(args, 'secret-relais', 'secret-mere'),
    restaurer: arg(args, 'restaurer', '0') == '1',
    cleBase64: arg(args, 'cle', ''),
    dossierSauvegardes: arg(args, 'sauvegardes', 'sauvegardes'),
    heureSauvegarde: int.tryParse(arg(args, 'sauvegarde-heure', '2')) ?? 2,
    conservation: int.tryParse(arg(args, 'conservation', '7')) ?? 7,
  ));
  await m.demarrer();
}
