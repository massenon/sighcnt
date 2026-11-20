// Vérification d'intégration : la console parle au VRAI service de la mère (pas à un double).
//   (dans un autre terminal)  packages/sync_dart/build/mere_bundle/bundle/bin/mere --port=9000 --db=/tmp/mere.sqlite
//   dart run tool/verif_service.dart http://127.0.0.1:9000 admin-banc
import 'dart:io';

import 'package:sigh_poste/mere/client_mere.dart';

Future<void> main(List<String> args) async {
  final c = ClientMere(base: Uri.parse(args.isNotEmpty ? args[0] : 'http://127.0.0.1:9000'), secretAdmin: args.length > 1 ? args[1] : 'admin-banc');
  var echecs = 0;
  void verifier(String libelle, bool ok) {
    stdout.writeln('${ok ? '✓' : '✗'} $libelle');
    if (!ok) echecs++;
  }

  final e0 = await c.etat();
  verifier('état lu : époque ${e0.epoch}, ${e0.appareils.length} appareil(s)', e0.epoch >= 1);
  final code = await c.codeAppareil('Poste de vérification');
  verifier('code d\'appairage reçu (8 caractères) : $code', code.length == 8);
  verifier('aucun conflit ouvert sur une mère neuve', (await c.conflits()).isEmpty);
  try {
    await c.reinitialiser(confirmation: 'NASSIERA TOO', second: 'DAF');
    verifier('réinitialisation fenêtre fermée : doit être refusée', false);
  } on ErreurMere catch (e) {
    verifier('réinitialisation refusée avec la cause nommée : ${e.code}', e.code == 'reinit_fermee');
  }
  final mauvais = ClientMere(base: c.base, secretAdmin: 'faux');
  try {
    await mauvais.etat();
    verifier('mauvais secret : doit être refusé', false);
  } on ErreurMere catch (e) {
    verifier('mauvais secret refusé : ${e.code}', e.statut == 403);
  }
  exit(echecs == 0 ? 0 : 1);
}
