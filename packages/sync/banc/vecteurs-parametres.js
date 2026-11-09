'use strict';
/* Vecteurs des PARAMÈTRES VERSIONNÉS PAR DATE (lot L0) : `parametres.js` est l'exécutable de référence ; ce script engendre les cas que le domaine Dart rejoue
   (packages/domaine/test/parametres_test.dart). ENGENDRÉ : ne pas éditer le JSON.   node banc/vecteurs-parametres.js */
const fs = require('node:fs');
const path = require('node:path');
const P = require('./parametres.js');

const circuit = { cle: 'planning.circuit', famille: 'planning', type: 'choix', choix: ['surveillant', 'daf', 'surveillant_puis_daf'], defaut: 'surveillant', sensible: false, mobile: false, source: 'fixture' };
const bascule = { cle: 'accueil.affichage', famille: 'accueil', type: 'booleen', defaut: false, sensible: false, mobile: true, source: 'fixture' };
const entier = { cle: 'accueil.delai', famille: 'accueil', type: 'entier', defaut: 15, sensible: false, mobile: false, source: 'fixture' };
const nombre = { cle: 'accueil.ratio', famille: 'accueil', type: 'nombre', defaut: 0.5, sensible: false, mobile: false, source: 'fixture' };
const texte = { cle: 'accueil.mot', famille: 'accueil', type: 'texte', defaut: 'rien', sensible: true, mobile: false, source: 'fixture' };
const paie = { cle: 'paie.exemple', famille: 'paie', type: 'booleen', defaut: true, sensible: false, mobile: true, source: 'fixture' };
const sensible = { cle: 'accueil.confidentiel', famille: 'accueil', type: 'booleen', defaut: true, sensible: true, mobile: true, source: 'fixture' };
const AUT = { auteur: 'admin', creeLe: '2026-11-09T08:00:00Z', motif: 'vecteur' };

const cas = [];
const resoudre = (nom, definition, versions, date) => cas.push({ nom: `résoudre : ${nom}`, op: 'resoudre', cle: definition.cle, definition, versions, date, attendu: P.resoudre(definition.cle, versions, date, definition) });
const resoudreSans = (nom, cle, versions, date) => cas.push({ nom: `résoudre : ${nom}`, op: 'resoudre', cle, definition: null, versions, date, attendu: P.resoudre(cle, versions, date) });
const proposer = (nom, definition, versions, usages, valeur, dateEffet, extra = {}) => cas.push({ nom: `proposer : ${nom}`, op: 'proposer', definition, versions, usages, valeur, dateEffet, ...AUT, ...extra,
  attendu: P.proposer({ definition, versions, usages, valeur, dateEffet, ...AUT, ...extra }) });
const valider = (nom, fiche, existantes, usages) => cas.push({ nom: `valider : ${nom}`, op: 'valider', fiche, existantes, usages, attendu: P.validerFiche(fiche, existantes, usages) });
const semer = (nom, definition) => cas.push({ nom: `semer : ${nom}`, op: 'semer', definition, attendu: P.semer(definition) });

const v0 = P.semer(circuit).fiche;
const vDaf = P.proposer({ definition: circuit, versions: [v0], usages: [], valeur: 'daf', dateEffet: '2026-12-01', ...AUT }).fiche;
const vMix = P.proposer({ definition: circuit, versions: [v0, vDaf], usages: [], valeur: 'surveillant_puis_daf', dateEffet: '2026-12-01', ...AUT }).fiche;

resoudre('sans version, le défaut', circuit, [], '2026-11-09');
resoudre('version 0 semée', circuit, [v0], '2026-11-09');
resoudre('avant la date d\'effet', circuit, [v0, vDaf], '2026-11-30');
resoudre('à la date d\'effet', circuit, [v0, vDaf], '2026-12-01');
resoudre('après la date d\'effet', circuit, [v0, vDaf], '2027-06-01');
resoudre('à date égale la version la plus haute', circuit, [v0, vDaf, vMix], '2026-12-02');
resoudre('l\'ordre des versions ne compte pas', circuit, [vMix, vDaf, v0], '2026-12-02');
resoudre('date illisible', circuit, [v0], '9 novembre');
resoudre('date impossible', circuit, [v0], '2026-02-30');
resoudre('version sans version 0, avant la première : défaut de la définition', circuit, [vDaf], '2026-11-01');
resoudreSans('sans définition ni version', 'inconnu', [], '2026-11-09');
resoudreSans('sans définition, avant la première version', circuit.cle, [vDaf], '2026-11-01');
resoudre('une autre clé ne compte pas', entier, [v0, vDaf], '2026-12-05');

proposer('première version datée', circuit, [v0], [], 'daf', '2026-12-01');
proposer('sans version 0 connue', circuit, [], [], 'daf', '2026-12-01');
proposer('valeur hors des choix', circuit, [v0], [], 'personne', '2026-12-01');
proposer('mauvais type', circuit, [v0], [], true, '2026-12-01');
proposer('date impossible', circuit, [v0], [], 'daf', '2026-02-30');
proposer('sans date d\'effet', circuit, [v0], [], 'daf', null);
proposer('sans auteur', circuit, [v0], [], 'daf', '2026-12-01', { auteur: '' });
proposer('valeur déjà utilisée : même jour', circuit, [v0], [{ cle: circuit.cle, date: '2026-11-08', piece: 'F-1' }], 'daf', '2026-11-08');
proposer('valeur déjà utilisée : date antérieure', circuit, [v0], [{ cle: circuit.cle, date: '2026-11-08', piece: 'F-1' }], 'daf', '2026-11-01');
proposer('après la dernière pièce', circuit, [v0], [{ cle: circuit.cle, date: '2026-11-08', piece: 'F-1' }], 'daf', '2026-11-09');
proposer('plusieurs pièces : la dernière date compte', circuit, [v0], [{ cle: circuit.cle, date: '2026-10-01', piece: 'F-1' }, { cle: circuit.cle, date: '2026-11-20', piece: 'F-2' }, { cle: circuit.cle, date: '2026-11-02', piece: 'F-3' }], 'daf', '2026-11-10');
proposer('usage d\'une autre clé', circuit, [v0], [{ cle: 'autre', date: '2026-11-08', piece: 'F-1' }], 'daf', '2026-11-01');
proposer('version suivante numérotée', circuit, [v0, vDaf], [], 'surveillant_puis_daf', '2026-12-15');
proposer('booléen accepté', bascule, [P.semer(bascule).fiche], [], true, '2026-12-01');
proposer('entier non entier', entier, [P.semer(entier).fiche], [], 1.5, '2026-12-01');
proposer('entier accepté', entier, [P.semer(entier).fiche], [], 20, '2026-12-01');
proposer('nombre accepté', nombre, [P.semer(nombre).fiche], [], 0.25, '2026-12-01');
proposer('texte accepté', texte, [P.semer(texte).fiche], [], 'mot', '2026-12-01');
proposer('famille réservée déclarée mobile', paie, [], [], false, '2026-12-01');
proposer('paramètre sensible déclaré mobile', sensible, [], [], false, '2026-12-01');
proposer('sans définition', null, [], [], 'x', '2026-12-01');

valider('défaut semé', P.semer(circuit).fiche, [], []);
valider('version 0 avec une date d\'effet', { ...P.semer(circuit).fiche, dateEffet: '2026-12-01' }, [], []);
valider('version sans date autre que 0', { ...vDaf, dateEffet: null }, [v0], []);
valider('version 0 réservée', { ...vDaf, version: 0 }, [v0], []);
valider('numéro de version déjà pris', { ...vDaf, version: 1 }, [v0, { ...vDaf, version: 1, dateEffet: '2026-11-15' }], []);
valider('arrivée dans le désordre : v1 après v2', vDaf, [v0, { ...vMix, version: 2 }], []);
valider('type inconnu', { ...vDaf, type: 'liste' }, [v0], []);
valider('champ manquant', { ...vDaf, famille: '' }, [v0], []);
valider('défaut invalide', { ...vDaf, defaut: 12 }, [v0], []);
valider('version non entière', { ...vDaf, version: 1.5 }, [v0], []);
valider('paramètre réservé au mobile', { ...P.semer(paie).fiche }, [], []);
valider('usage postérieur à la date d\'effet', vDaf, [v0], [{ cle: circuit.cle, date: '2026-12-01', piece: 'F-9' }]);

semer('choix', circuit);
semer('booléen mobile', bascule);

const mob = (nom, champs) => cas.push({ nom: `téléphone : ${nom}`, op: 'mobile', champs, attendu: P.autoriseMobile(champs) });
mob('déclaré, non sensible, famille libre', P.semer(bascule).fiche);
mob('non déclaré', P.semer(circuit).fiche);
mob('sensible', { ...P.semer(bascule).fiche, sensible: true });
for (const f of P.FAMILLES_JAMAIS_MOBILE) mob(`famille réservée ${f}`, { ...P.semer(bascule).fiche, famille: f });
mob('mobile « oui » en chaîne', { ...P.semer(bascule).fiche, mobile: 'true' });

const sortie = path.join(__dirname, '..', '..', 'domaine', 'test', 'vecteurs', 'parametres.json');
fs.writeFileSync(sortie, JSON.stringify({ _doc: 'ENGENDRÉ par packages/sync/banc/vecteurs-parametres.js : l\'attendu est celui de banc/parametres.js. Ne pas éditer.', famillesJamaisMobile: P.FAMILLES_JAMAIS_MOBILE, cas }, null, 1) + '\n');
console.log(`  écrit : ${path.relative(process.cwd(), sortie)} · ${cas.length} cas`);
