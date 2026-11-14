'use strict';
/* SIGH-CNT : le PROCESSUS de sauvegarde de la mère de référence (lot 5), lancé et TUÉ par le banc. Un seul dépôt, puis la sortie.
   Argument : un JSON { relais, secret, cle (hex), type, source, tailleBloc, garder, lentMs, coupureApres }.
   `source` : un fichier (type magasin, un seul élément « magasin ») ou un dossier (type fichiers, un élément par fichier, la référence est le nom du fichier). */
const fs = require('node:fs');
const path = require('node:path');
const { DestRelais, sauvegarder, ErreurSauvegarde } = require('./sauvegarde-hs');
const a = JSON.parse(process.argv[2]);
const elements = fs.statSync(a.source).isDirectory()
  ? fs.readdirSync(a.source).sort().map((n) => ({ ref: n, taille: fs.statSync(path.join(a.source, n)).size, lire: () => fs.readFileSync(path.join(a.source, n)) }))
  : [{ ref: 'magasin', taille: fs.statSync(a.source).size, lire: () => fs.readFileSync(a.source) }];
sauvegarder({ dest: new DestRelais(a.relais, a.secret), cle: Buffer.from(a.cle, 'hex'), type: a.type, elements, tailleBloc: a.tailleBloc, garder: a.garder, lentMs: a.lentMs || 0, coupureApres: a.coupureApres ?? null })
  .then((r) => { process.send({ ok: true, ...r }, () => process.exit(0)); })
  .catch((e) => { process.send({ ok: false, refus: e instanceof ErreurSauvegarde ? e.refus : { code: 'ERREUR', motif: String(e && e.message) } }, () => process.exit(1)); });
