'use strict';
/* Lot L0 : les paramètres versionnés par date. Règle de référence : banc/parametres.js (portée en Dart, vecteurs de banc/vecteurs-parametres.js). */
const test = require('node:test');
const assert = require('node:assert');
const P = require('./parametres');

const def = { cle: 'planning.circuit', famille: 'planning', type: 'choix', choix: ['surveillant', 'daf', 'surveillant_puis_daf'], defaut: 'surveillant', sensible: false, mobile: false, source: 'banc' };
const prop = (versions, valeur, dateEffet, usages = [], d = def) => P.proposer({ definition: d, versions, usages, valeur, dateEffet, auteur: 'admin', creeLe: '2026-11-09T08:00:00Z', motif: 'test' });

test('sans version : le défaut ; sans définition ni version : refus nommé', () => {
  assert.deepStrictEqual(P.resoudre(def.cle, [], '2026-11-09', def), { ok: true, valeur: 'surveillant', origine: 'defaut', version: 0, dateEffet: null });
  const r = P.resoudre('inconnu', [], '2026-11-09');
  assert.strictEqual(r.ok, false); assert.strictEqual(r.code, 'parametre_inconnu'); assert.ok(r.motif && r.geste);
  assert.strictEqual(P.resoudre(def.cle, [], '9 novembre', def).code, 'date_invalide');
});

test('la valeur en vigueur dépend de la date de la pièce, pas de la date du jour', () => {
  const v0 = P.semer(def).fiche;
  const a = prop([v0], 'daf', '2026-12-01'); assert.ok(a.ok);
  const vs = [v0, a.fiche];
  assert.strictEqual(P.resoudre(def.cle, vs, '2026-11-30', def).valeur, 'surveillant');
  assert.strictEqual(P.resoudre(def.cle, vs, '2026-12-01', def).valeur, 'daf');
  assert.strictEqual(P.resoudre(def.cle, vs, '2027-06-01', def).valeur, 'daf');
  assert.strictEqual(P.resoudre(def.cle, vs, '2026-11-30', def).origine, 'version');
});

test('dernière valeur par date d\'effet ; à date égale, la version la plus haute', () => {
  const v0 = P.semer(def).fiche; const a = prop([v0], 'daf', '2026-12-01').fiche; const b = prop([v0, a], 'surveillant_puis_daf', '2026-12-01').fiche;
  assert.strictEqual(b.version, 2);
  assert.strictEqual(P.resoudre(def.cle, [v0, a, b], '2026-12-02', def).valeur, 'surveillant_puis_daf');
  /* l'ordre de la liste ne change rien : la convergence ne dépend pas de l'ordre d'arrivée */
  for (const ordre of [[v0, a, b], [b, a, v0], [a, v0, b], [b, v0, a]]) assert.strictEqual(P.resoudre(def.cle, ordre, '2026-12-02', def).valeur, 'surveillant_puis_daf');
});

test('une valeur déjà utilisée par une pièce ne se réécrit jamais : refus nommé, avec le geste', () => {
  const v0 = P.semer(def).fiche;
  const usages = [{ cle: def.cle, date: '2026-11-08', piece: 'F-1' }];
  const r = prop([v0], 'daf', '2026-11-08', usages);
  assert.strictEqual(r.ok, false); assert.strictEqual(r.code, 'parametre_deja_utilise');
  assert.match(r.motif, /2026-11-08/); assert.match(r.geste, /postérieure au 2026-11-08/);
  assert.strictEqual(prop([v0], 'daf', '2026-11-01', usages).code, 'parametre_deja_utilise');
  assert.ok(prop([v0], 'daf', '2026-11-09', usages).ok);
  /* un usage d'une AUTRE clé ne gêne pas */
  assert.ok(prop([v0], 'daf', '2026-11-01', [{ cle: 'autre', date: '2026-11-08' }]).ok);
});

test('refus nommés : valeur hors choix, type, auteur, date, numéro de version déjà pris', () => {
  const v0 = P.semer(def).fiche;
  assert.strictEqual(prop([v0], 'personne', '2026-12-01').code, 'valeur_invalide');
  assert.strictEqual(prop([v0], true, '2026-12-01').code, 'valeur_invalide');
  assert.strictEqual(prop([v0], 'daf', '2026-02-30').code, 'date_invalide');
  assert.strictEqual(P.proposer({ definition: def, versions: [v0], usages: [], valeur: 'daf', dateEffet: '2026-12-01', auteur: '' }).code, 'auteur_manquant');
  const a = prop([v0], 'daf', '2026-12-01').fiche;
  assert.strictEqual(P.validerFiche({ ...a, dateEffet: '2027-01-01', version: 1 }, [v0, a], []).code, 'version_deja_prise');
  assert.strictEqual(P.validerFiche({ ...a, version: 0 }, [v0], []).code, 'version_invalide');
  assert.strictEqual(prop([v0], 'daf', null).code, 'date_effet_manquante');
});

test('le défaut semé est identique d\'un poste à l\'autre (deux semis indépendants ne divergent pas)', () => {
  assert.deepStrictEqual(P.semer(def), P.semer({ ...def }));
  assert.strictEqual(P.semer(def).id, 'planning.circuit@defaut@0');
  assert.ok(P.validerFiche(P.semer(def).fiche, [], []).ok);
});

test('liste blanche du téléphone : déclaré, non sensible, famille non réservée', () => {
  const ok = { ...def, famille: 'accueil', type: 'booleen', defaut: true, choix: undefined, mobile: true };
  assert.strictEqual(P.autoriseMobile(P.semer(ok).fiche), true);
  assert.strictEqual(P.autoriseMobile(P.semer({ ...ok, mobile: false }).fiche), false);
  assert.strictEqual(P.autoriseMobile(P.semer({ ...ok, sensible: true }).fiche), false);
  for (const f of P.FAMILLES_JAMAIS_MOBILE) assert.strictEqual(P.autoriseMobile(P.semer({ ...ok, famille: f }).fiche), false, f);
  /* une définition qui voudrait envoyer un paramètre réservé au téléphone est REFUSÉE à l'émission comme à la réception */
  const r = prop([], true, '2026-12-01', [], { ...ok, famille: 'paie' });
  assert.strictEqual(r.code, 'mobile_interdit'); assert.match(r.motif, /RG-13/);
  assert.strictEqual(P.validerFiche({ ...P.semer({ ...ok, famille: 'securite' }).fiche }, [], []).code, 'mobile_interdit');
});

test('l\'ordre d\'arrivée des versions ne compte pas : v2 puis v1 sont toutes deux acceptées', () => {
  const v0 = P.semer(def).fiche;
  const a = prop([v0], 'daf', '2026-12-01').fiche; const b = prop([v0, a], 'surveillant_puis_daf', '2027-01-01').fiche;
  assert.ok(P.validerFiche(b, [v0], []).ok);
  assert.ok(P.validerFiche(a, [v0, b], []).ok);
  assert.strictEqual(P.validerFiche(a, [v0, a], []).code, 'version_deja_prise');
});
