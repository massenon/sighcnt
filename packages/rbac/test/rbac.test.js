'use strict';
/* Garde-fous de la matrice engendrée : chaque ligne encode une DÉCISION de la Direction écrite dans CLAUDE.md.
 * Si ce test échoue après une régénération (`node prototype_html/build/extraire.js rbac`), soit la maquette a
 * changé — et la décision doit être revue —, soit l'extraction est cassée. Ne jamais « corriger » le test seul. */
const test = require('node:test');
const assert = require('node:assert/strict');
const rbac = require('../data/rbac.json');
const manifeste = require('../../referentiels/data/manifeste.json');
const droit = (role, ecran) => (rbac.parRole[role] || {})[ecran] || null;
const ecransConnus = new Set(manifeste.ecrans.map((e) => e.id));

test('chaque écran cité existe au manifeste', () => {
  for (const [role, ecrans] of Object.entries(rbac.parRole)) for (const id of Object.keys(ecrans)) assert.ok(ecransConnus.has(id), `${role} → ${id}`);
});
test('chaque rôle de la matrice est déclaré', () => {
  const ids = new Set(rbac.roles.map((r) => r.id));
  for (const role of Object.keys(rbac.parRole)) assert.ok(ids.has(role), role);
});
test('Pharmacie et RH sont archivés (RG-14) : aucun écran, jamais supprimés', () => {
  for (const r of ['pharmacien', 'rh']) { assert.ok(rbac.roles.find((x) => x.id === r).archive, r); assert.equal(Object.keys(rbac.parRole[r]).length, 0, r); }
});
test('caissier : ni stock en gros, ni dépenses ; avoir en lecture seule ; caisse en écriture sans annulation', () => {
  assert.equal(droit('caissier', 'm6-stock-gros'), null);
  assert.equal(droit('caissier', 'm12-depenses'), null);
  assert.deepEqual(droit('caissier', 'm8-facture-avoir'), [1, 0, 0]);
  assert.deepEqual(droit('caissier', 'm8-caisse'), [1, 1, 0]);
});
test('biologiste (id laborantin) : pas de bon de livraison', () => { assert.equal(droit('laborantin', 'm7-livraisons'), null); });
test('échographiste : exécute l\'imagerie sans prescrire, aucun accès financier', () => {
  assert.equal(droit('echographiste', 'm2-imagerie')[1], 1);
  assert.equal(droit('echographiste', 'm2-ordonnances'), null);
  for (const [id] of Object.entries(rbac.parRole.echographiste)) assert.ok(!/^m(8|9|12)-/.test(id) && !id.startsWith('mecef-'), id);
});
test('assistant de direction : pas de résultats de laboratoire, mais l\'inventaire des réactifs', () => {
  assert.equal(droit('assistant_comptable', 'm5-resultats'), null);
  assert.ok(droit('assistant_comptable', 'm5-reactifs'));
});
test('la Direction signe la paie (surcharge d\'écran), signer n\'est pas saisir', () => { assert.equal(droit('direction', 'm11-validation')[1], 1); });
test('A2 : le comptable génère les bulletins, il ne valide pas la paie (lecture seule de m11-validation)', () => {
  assert.deepEqual(droit('comptable', 'm11-validation'), [1, 0, 0]);
  assert.equal(droit('comptable', 'm11-calcul')[1], 1, 'il garde la génération');
});
test('écran universel : exprimer un besoin est ouvert à tout rôle actif, mais jamais annulable par le passant', () => {
  for (const r of rbac.roles.filter((x) => !x.archive)) { const d = droit(r.id, 'm7-besoins'); assert.ok(d && d[0] === 1 && d[1] === 1, r.id); }
  for (const r of ['medecin', 'caissier', 'reception']) assert.equal(droit(r, 'm7-besoins')[2], 0, r);
});
test('une page de saisie hérite des droits du registre qu\'elle alimente (servant)', () => {
  for (const e of manifeste.ecrans.filter((x) => x.servant)) {
    for (const role of Object.keys(rbac.parRole)) {
      const page = droit(role, e.id); const registre = droit(role, e.servant);
      assert.equal(!!page, !!registre, `${role} : ${e.id} ≠ ${e.servant}`);
    }
  }
});
