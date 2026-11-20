'use strict';
/* SIGH-CNT : la RESTAURATION de référence en ligne de commande (lot 5), pour prouver l'interopérabilité avec le moteur Dart (une copie faite par l'un se restaure par l'autre).
   Argument : un JSON { relais, secret, cle (hex), copie, cible }. Sortie : une ligne JSON { ok, ... } ou { ok: false, refus }. */
const { DestRelais, restaurer, ErreurSauvegarde } = require('./sauvegarde-hs');
const a = JSON.parse(process.argv[2]);
restaurer({ dest: new DestRelais(a.relais, a.secret), cle: Buffer.from(a.cle, 'hex'), copieId: a.copie, cible: a.cible })
  .then((r) => process.stdout.write(JSON.stringify({ ok: true, ...r }) + '\n', () => process.exit(0)))
  .catch((e) => process.stdout.write(JSON.stringify({ ok: false, refus: e instanceof ErreurSauvegarde ? e.refus : { code: 'ERREUR', motif: String(e && e.message) } }) + '\n', () => process.exit(1)));
