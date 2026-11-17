/* Contrôle de couverture : chaque écran de ecrans.js doit être nommé dans manuel.html (texte rendu). node controle.js ➔ « 0 manquant » ou la liste. */
'use strict';
const fs = require('fs');
const path = require('path');
const E = require('./ecrans.js');
const norm = (s) => String(s).replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&#39;|&apos;/g, '’').replace(/&quot;/g, '"').replace(/'/g, '’').replace(/\s+/g, ' ').toLowerCase();
const html = norm(fs.readFileSync(path.join(__dirname, 'manuel.html'), 'utf8'));
const manquants = E.tous.filter((e) => !html.includes(norm(e.nom)));
const par = {};
E.tous.forEach((e) => { par[e.groupe] = par[e.groupe] || { total: 0, manquants: 0 }; par[e.groupe].total++; });
manquants.forEach((e) => { par[e.groupe].manquants++; });
Object.keys(par).forEach((g) => console.log(g.padEnd(10), String(par[g].total).padStart(4), 'listés,', par[g].manquants, 'manquant(s)'));
console.log(E.tous.length + ' écrans listés, ' + manquants.length + ' manquant(s)');
manquants.forEach((e) => console.log('  MANQUANT ' + e.groupe + ' ' + e.id + ' : ' + e.nom));
const imgs = [...fs.readFileSync(path.join(__dirname, 'manuel.html'), 'utf8').matchAll(/src="captures\/([^"]+)"/g)].map((m) => m[1]);
const absentes = imgs.filter((f) => !fs.existsSync(path.join(__dirname, 'captures', f)));
console.log(imgs.length + ' captures référencées, ' + absentes.length + ' absente(s)' + (absentes.length ? ' : ' + absentes.join(', ') : ''));
process.exit(manquants.length || absentes.length ? 1 : 0);
