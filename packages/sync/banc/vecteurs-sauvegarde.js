'use strict';
/* Vecteurs de la SAUVEGARDE HORS SITE (lot 5, ADR-0007) : `sauvegarde-regles.js` et `sauvegarde-hs.js` sont les exécutables de référence ; ce script engendre ce que le domaine Dart
   (packages/domaine/test/sauvegarde_horssite_test.dart) et le moteur Dart (packages/sync_dart/test/sauvegarde_horssite_test.dart) rejouent.
   ENGENDRÉ : ne pas éditer les JSON.   node banc/vecteurs-sauvegarde.js */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const R = require('./sauvegarde-regles.js');
const { Chiffreur, sha } = require('./sauvegarde-hs.js');

const cas = [];
const ajouter = (nom, op, entree, attendu) => cas.push({ nom, op, entree, attendu });
const MO = 1024 * 1024;

for (const [l, t] of [[0, 512], [1, 512], [511, 512], [512, 512], [513, 512], [1024, 512], [3 * MO + 17, MO], [5, 2]]) ajouter(`découper ${l} octets par blocs de ${t}`, 'decouper', { longueur: l, tailleBloc: t }, R.decouper(l, t));
for (const [l, t] of [[0, 512], [513, 512], [3 * MO, MO]]) ajouter(`taille chiffrée de ${l} octets par blocs de ${t}`, 'tailleChiffree', { longueur: l, tailleBloc: t }, R.tailleChiffree(l, t));

const ok = { actif: true, destination: 'relais', dossier: '', tailleBloc: MO, copies: 7, frequenceMinutes: 60, heureControle: 2, blocsControles: 10 };
const reglage = (nom, plus) => ajouter(`réglage : ${nom}`, 'verifierReglage', { ...ok, ...plus }, R.verifierReglage({ ...ok, ...plus }));
reglage('valide', {}); reglage('activer sans destination', { destination: 'aucune' }); reglage('désactivé sans destination', { destination: 'aucune', actif: false });
reglage('destination inconnue', { destination: 'sftp' }); reglage('dossier sans chemin', { destination: 'dossier', dossier: '  ' }); reglage('dossier avec chemin', { destination: 'dossier', dossier: '/mnt/sauvegardes' });
reglage('bloc trop petit', { tailleBloc: 1000 }); reglage('bloc trop gros', { tailleBloc: 5 * MO }); reglage('bloc à la borne basse', { tailleBloc: 64 * 1024 }); reglage('bloc à la borne haute', { tailleBloc: 4 * MO });
reglage('une seule copie (sous le plancher)', { copies: 1 }); reglage('deux copies (plancher)', { copies: 2 }); reglage('soixante copies (plafond)', { copies: 60 }); reglage('soixante et une copies', { copies: 61 }); reglage('copies non entières', { copies: 7.5 });
reglage('fréquence trop courte', { frequenceMinutes: 5 }); reglage('fréquence à la borne', { frequenceMinutes: 15 }); reglage('fréquence trop longue', { frequenceMinutes: 2000 });
reglage('heure 24', { heureControle: 24 }); reglage('heure 0', { heureControle: 0 }); reglage('blocs contrôlés négatifs', { blocsControles: -1 }); reglage('blocs contrôlés 200', { blocsControles: 200 });

const lim = { tailleMaxCopie: 100, quotaOctets: 1000, tailleBlocMax: 50 };
const plan = (nom, octetsCopie, etat) => ajouter(`plan : ${nom}`, 'verifierPlan', { octetsCopie, etat }, R.verifierPlan({ octetsCopie, etat }));
plan('tient', 80, { limites: lim, utilise: 500, liberable: 0 }); plan('trop grosse pour une copie', 101, { limites: lim, utilise: 0, liberable: 0 }); plan('à la limite de la copie', 100, { limites: lim, utilise: 0, liberable: 0 });
plan('manque de place', 90, { limites: lim, utilise: 950, liberable: 0 }); plan('manque de place mais archive libérable', 90, { limites: lim, utilise: 950, liberable: 60 });
plan('à la place exacte', 100, { limites: lim, utilise: 900, liberable: 0 }); plan('un octet de trop', 101, { limites: { ...lim, tailleMaxCopie: 200 }, utilise: 900, liberable: 0 });
plan('quota inconnu : la limite ne s\'applique pas (jamais zéro)', 10000, { limites: { tailleMaxCopie: 100000 }, utilise: 0 }); plan('état absent', 10, null);
plan('espace utilisé inconnu : pas de refus d\'espace', 900, { limites: lim, liberable: 0 });

const C = (id, type, etat, date) => ({ id, type, etat, date });
const rot = (nom, copies, garder, plancher, plafond) => ajouter(`rotation : ${nom}`, 'rotation', { copies, garder, plancher, plafond }, R.rotation(copies, garder, plancher, plafond));
const cinq = [C('a', 'magasin', 'complete', 1), C('b', 'magasin', 'complete', 2), C('c', 'magasin', 'complete', 3), C('d', 'magasin', 'complete', 4), C('e', 'magasin', 'complete', 5)];
rot('cinq copies, garder trois', cinq, 3, 2, 60); rot('garder autant que de copies', cinq, 5, 2, 60); rot('garder plus que de copies', cinq, 9, 2, 60);
rot('sous le plancher', cinq, 1, 2, 60); rot('au plancher', cinq, 2, 2, 60); rot('au-dessus du plafond', cinq, 61, 2, 60); rot('garder non entier', cinq, 2.5, 2, 60);
rot('une copie ouverte ou purgée ne compte pas', [...cinq, C('f', 'magasin', 'ouverte', 9), C('g', 'magasin', 'purgee', 8), C('h', 'magasin', 'archivee', 0)], 3, 2, 60);
rot('dates égales : l\'identifiant départage', [C('x', 'magasin', 'complete', 7), C('y', 'magasin', 'complete', 7), C('z', 'magasin', 'complete', 7)], 2, 2, 60); rot('aucune copie', [], 7, 2, 60);

const purge = (nom, copies, plancher) => ajouter(`purge : ${nom}`, 'ordrePurge', { copies, plancher }, R.ordrePurge(copies, plancher));
purge('l\'archive la plus ancienne d\'abord', [C('a', 'magasin', 'archivee', 1), C('b', 'magasin', 'archivee', 2), C('c', 'magasin', 'archivee', 3), C('d', 'magasin', 'complete', 4), C('e', 'magasin', 'complete', 5)], 2);
purge('jamais une copie courante ni une copie ouverte', [C('d', 'magasin', 'complete', 4), C('e', 'magasin', 'complete', 5), C('f', 'magasin', 'ouverte', 6)], 2);
purge('le plancher protège les plus récentes même archivées', [C('a', 'magasin', 'archivee', 1), C('b', 'magasin', 'archivee', 2), C('c', 'magasin', 'archivee', 3)], 2);
purge('une copie abandonnée est candidate', [C('a', 'magasin', 'abandonnee', 1), C('b', 'magasin', 'complete', 2), C('c', 'magasin', 'complete', 3)], 2);
purge('le plancher se compte par type', [C('a', 'magasin', 'archivee', 1), C('b', 'fichiers', 'archivee', 2), C('c', 'fichiers', 'complete', 3), C('d', 'magasin', 'complete', 4), C('e', 'magasin', 'complete', 5)], 2);
purge('une copie courante au-delà du plancher n\'est jamais candidate (le plancher n\'est pas la seule garde)', [C('a', 'magasin', 'archivee', 1), C('b', 'magasin', 'complete', 2), C('c', 'magasin', 'complete', 3), C('d', 'magasin', 'complete', 4), C('e', 'magasin', 'complete', 5)], 2);
purge('une copie en cours (ouverte) n\'est jamais candidate', [C('a', 'magasin', 'ouverte', 1), C('b', 'magasin', 'archivee', 2), C('c', 'magasin', 'complete', 3), C('d', 'magasin', 'complete', 4)], 2);
purge('aucune copie', [], 2);

const bl = (id, taille, clair) => ({ id, taille, clair });
const h = (c) => c.repeat(64);
const e1 = { ref: 'magasin', taille: 10, sha256: h('a'), blocs: [bl(h('1'), 38, 6), bl(h('2'), 32, 4)] };
const e2 = { ref: 'zz.pdf', taille: 3, sha256: h('b'), meta: { ext: 'pdf' }, blocs: [bl(h('3'), 31, 3)] };
ajouter('manifeste : éléments triés par référence, total calculé, sans date', 'manifeste', { type: 'fichiers', tailleBloc: 512, elements: [e2, e1] }, R.manifeste({ type: 'fichiers', tailleBloc: 512, elements: [e2, e1] }));
const bon = R.manifeste({ type: 'fichiers', tailleBloc: 512, elements: [e1, e2] });
const verifM = (nom, m) => ajouter(`manifeste lu : ${nom}`, 'verifierManifeste', { manifeste: m }, R.verifierManifeste(m));
verifM('valide', bon); verifM('format inconnu', { ...bon, format: 9 }); verifM('type inconnu', { ...bon, type: 'autre' }); verifM('pas de liste d\'éléments', { format: 1, type: 'magasin' });
verifM('somme des blocs incohérente', { ...bon, elements: [{ ...bon.elements[0], taille: 11 }, bon.elements[1]] }); verifM('total incohérent', { ...bon, total: 99 });
verifM('empreinte du clair mal formée', { ...bon, elements: [{ ...bon.elements[0], sha256: 'xyz' }, bon.elements[1]] }); verifM('rien', null);

fs.writeFileSync(path.join(__dirname, '..', '..', 'domaine', 'test', 'vecteurs', 'sauvegarde_horssite.json'), JSON.stringify({ engendre: 'packages/sync/banc/vecteurs-sauvegarde.js', cas }, null, 1) + '\n');

/* Les vecteurs de CHIFFREMENT (moteur Dart) : clé fixe, clairs fixes, blocs attendus au bit près. Le moteur Dart doit produire exactement les mêmes octets (nonce dérivé) et rouvrir ceux du banc. */
const cle = Buffer.from(Array.from({ length: 32 }, (_, i) => (i * 7 + 3) & 0xff));
const ch = new Chiffreur(cle);
const chif = [];
for (const [genre, type, clair] of [['bloc', 'magasin', Buffer.from('SQLite format 3\0 contenu de démonstration')], ['bloc', 'fichiers', Buffer.alloc(2000, 0xab)], ['manifeste', 'magasin', Buffer.from('{"format":1,"type":"magasin"}')], ['bloc', 'magasin', Buffer.from([0])]]) {
  const b = ch.sceller(genre, type, clair);
  chif.push({ genre, type, clairSha256: sha(clair), clairHex: clair.length <= 64 ? clair.toString('hex') : null, clairRepete: clair.length > 64 ? { octet: clair[0], longueur: clair.length } : null, id: b.id, blobHex: b.blob.toString('hex'), longueur: b.blob.length });
}
fs.mkdirSync(path.join(__dirname, '..', '..', 'sync_dart', 'test', 'vecteurs'), { recursive: true });
fs.writeFileSync(path.join(__dirname, '..', '..', 'sync_dart', 'test', 'vecteurs', 'sauvegarde_chiffrement.json'), JSON.stringify({ engendre: 'packages/sync/banc/vecteurs-sauvegarde.js', cleHex: cle.toString('hex'), cas: chif }, null, 1) + '\n');
console.log(`${cas.length} cas de règles, ${chif.length} cas de chiffrement`);
void crypto;
