'use strict';
/* Lot RLS-SYNC : la liste blanche des indicateurs de synchronisation (banc Node), rejouée sur les vecteurs PARTAGÉS avec le domaine Dart et le relais Laravel.
   node --no-warnings --test banc/synchro.test.js */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const S = require('./synchro');

const V = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'domaine', 'test', 'vecteurs', 'synchro_fileuls.json'), 'utf8'));
const developper = (x) => (x === 'GENERER_201' ? Array.from({ length: 201 }, (_, i) => ({ poste: 'F' + i })) : x);

test('les cinq clés et la borne sont celles du vecteur', () => {
  assert.deepEqual(S.CLES, V.cles);
  assert.equal(S.MAX, V.max);
});

test('nom technique du poste : valides et invalides', () => {
  for (const s of V.poste.valides) assert.ok(S.POSTE.test(s), s);
  for (const s of V.poste.invalides) assert.ok(!S.POSTE.test(s), JSON.stringify(s));
});

for (const c of V.valider) {
  test('valider : ' + c.nom, () => {
    const charge = Object.fromEntries(Object.entries(c.charge).map(([k, x]) => [k, developper(x)]));
    const refus = S.valider(charge);
    if (c.ok) assert.equal(refus, null, refus && refus.motif);
    else {
      assert.ok(refus, 'un refus était attendu');
      assert.equal(refus.code, c.code);
      assert.equal(refus.chemin, c.chemin);
      assert.ok(refus.motif && refus.geste);
    }
  });
}

test('un refus ne recopie jamais la valeur ni une clé de forme douteuse', () => {
  const r = S.valider({ fileuls: [{ poste: 'F1', 'KOUASSI Awa': 1 }] });
  assert.ok(!JSON.stringify(r).includes('KOUASSI'));
  const r2 = S.valider({ fileuls: [{ poste: 'CNT/12/26' }] });
  assert.ok(!JSON.stringify(r2).includes('CNT/12'));
});

for (const c of V.construire) {
  test('construire : ' + c.nom, () => {
    const s = S.construire(c.entree);
    assert.deepEqual(s, c.sortie);
    assert.deepEqual(Object.keys(s), S.CLES);
    assert.equal(S.valider({ fileuls: [s] }), null);
  });
}

for (const c of V.assainir) {
  test('assainir : ' + c.nom, () => {
    const r = S.assainir(developper(c.entree));
    if ('longueur' in c) assert.equal(r.length, c.longueur);
    else assert.deepEqual(r, c.sortie);
    assert.equal(S.valider({ fileuls: r }), null);
  });
}
