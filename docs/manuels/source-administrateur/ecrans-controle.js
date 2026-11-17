/* Contrôle du manuel fabriqué : chaque écran du manifeste, chaque geste réservé, chaque paramètre du registre, chaque entrée du panneau du relais et chaque image
 * référencée doivent se retrouver dans le PDF (texte extrait par pdftotext) ou sur le disque. Imprime les manquants ; sort en erreur s'il y en a.
 * Usage : node ecrans-controle.js [chemin du PDF] */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const PDF = process.argv[2] || path.join(__dirname, '..', 'MANUEL-ADMINISTRATEUR-SIGH-CNT.pdf');
const RACINE = path.resolve(__dirname, '../../..');
const texte = execFileSync('pdftotext', ['-raw', PDF, '-'], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
/* Les retours à la ligne et les espaces d'une cellule ne comptent pas : on compare sans aucun blanc, avec les apostrophes ramenées à une seule. */
const norm = (s) => s.replace(/[’']/g, "'").replace(/\s+/g, '').replace(/-\n/g, '');
const T = norm(texte);
const manquants = [];
const verifier = (genre, valeurs) => { let n = 0; for (const v of valeurs) { n++; if (!T.includes(norm(v))) manquants.push(genre + ' : ' + v); } return n; };

const manifeste = JSON.parse(fs.readFileSync(path.join(RACINE, 'packages/referentiels/data/manifeste.json'), 'utf8'));
const rbac = JSON.parse(fs.readFileSync(path.join(RACINE, 'packages/rbac/data/rbac.json'), 'utf8'));
const params = JSON.parse(fs.readFileSync(path.join(__dirname, 'parametres.json'), 'utf8'));
const panneau = fs.readFileSync(path.join(RACINE, 'apps/web/resources/views/layouts/panneau.blade.php'), 'utf8');

const nEcransId = verifier('écran (identifiant)', manifeste.ecrans.map((e) => e.id));
const nEcransLib = verifier('écran (libellé)', manifeste.ecrans.map((e) => e.label));
const nGestes = verifier('geste réservé (code)', rbac.gestes.jeux.map((g) => g.id));
const nGestesLib = verifier('geste réservé (libellé)', rbac.gestes.jeux.map((g) => g.libelle));
const nParams = verifier('paramètre (clé)', params.params.map((p) => p.cle));
const entrees = [...panneau.matchAll(/'panneau\.[a-z]+' => '([^']+)'/g)].map((m) => m[1]);
const nPanneau = verifier('entrée du panneau du relais', entrees);

/* images référencées par le modèle : présentes sur le disque */
const html = fs.readFileSync(path.join(__dirname, 'manuel-administrateur.html'), 'utf8');
const images = [...html.matchAll(/src="(captures\/[^"]+)"/g)].map((m) => m[1]);
let nImg = 0;
for (const i of images) { nImg++; if (!fs.existsSync(path.join(__dirname, i))) manquants.push('image absente : ' + i); }
/* secrets : aucun motif de secret dans le texte du PDF */
for (const motif of [/-----BEGIN [A-Z ]*KEY/, /sk_live_/, /AKIA[0-9A-Z]{16}/, /DB_PASSWORD=[^\s]{4,}/]) if (motif.test(texte)) manquants.push('motif de secret trouvé : ' + motif);
/* ponctuation interdite dans la prose : tiret cadratin et demi-cadratin (hors libellés d'écrans, qui sont des identifiants) */
const prose = html.replace(/<code>[\s\S]*?<\/code>/g, '').replace(/<[^>]+>/g, ' ');
const libelles = new Set(manifeste.ecrans.map((e) => e.label).concat(manifeste.modules.map((m) => m.label)));
const cadratins = (prose.match(/[^.\n]{0,40}[—–][^.\n]{0,40}/g) || []).filter((l) => ![...libelles].some((lb) => l.includes(lb.replace(/&amp;/g, '&')) || lb.includes(l.trim())));
const pages = execFileSync('pdfinfo', [PDF], { encoding: 'utf8' }).match(/Pages:\s+(\d+)/)[1];
console.log(`PDF : ${PDF} (${pages} pages, ${Math.round(fs.statSync(PDF).size / 1024 / 1024 * 10) / 10} Mo)`);
console.log(`écrans : ${nEcransId} identifiants et ${nEcransLib} libellés vérifiés sur ${manifeste.ecrans.length} du manifeste`);
console.log(`gestes réservés : ${nGestes} codes et ${nGestesLib} libellés vérifiés sur ${rbac.gestes.jeux.length}`);
console.log(`paramètres : ${nParams} sur ${params.params.length} ; panneau du relais : ${nPanneau} entrées sur ${entrees.length} ; images : ${nImg}`);
if (cadratins.length) console.log('tirets cadratins ou demi-cadratins dans la prose (à corriger) :\n  ' + cadratins.slice(0, 40).join('\n  '));
console.log('MANQUANTS : ' + manquants.length);
for (const m of manquants.slice(0, 80)) console.log('  ' + m);
process.exit(manquants.length || cadratins.length ? 1 : 0);
