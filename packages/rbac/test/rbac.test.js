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

/* ---- Le droit d'import, par jeu (lot IMP-A, 11/11/2026) : chaque ligne encode une décision de la Direction ------------------------------------------------------------------------- */
const imp = rbac.import;
const di = (role, jeu) => ((imp.parRole[role] || {})[jeu]) || [0, 0, 0];
const jeuxImp = imp.jeux.map((j) => j.id);
test('import : chaque jeu déclaré a son écran et ses hôtes au manifeste, et chaque rôle de la matrice a sa ligne', () => {
  for (const j of imp.jeux) { assert.ok(ecransConnus.has(j.ecran), j.id + ' → ' + j.ecran); for (const h of j.hotes) assert.ok(ecransConnus.has(h), j.id + ' → hôte ' + h); }
  for (const r of rbac.roles) assert.deepEqual(Object.keys(imp.parRole[r.id]).sort(), jeuxImp.slice().sort(), r.id);
});
test('I4 : le gestionnaire de stock importe le stock, les fournisseurs ET les prix des prestations (jeu tarifs) ; ni les patients ni le personnel', () => {
  for (const j of ['grand-stock', 'fournisseurs', 'tarifs']) assert.deepEqual(di('stock', j), [1, 1, 1], j);
  for (const j of ['patients', 'personnel', 'soldes-ouverture', 'plan-comptable']) assert.deepEqual(di('stock', j), [0, 0, 0], j);
});
test('I7 : l\'assistant comptable est en LECTURE SEULE à l\'import (voir, jamais importer ni annuler) ; la matrice peut le lui ouvrir plus tard sans code', () => {
  for (const j of jeuxImp) assert.equal(di('aide_comptable', j)[1] + di('aide_comptable', j)[2], 0, j);
  assert.deepEqual(di('aide_comptable', 'plan-comptable'), [1, 0, 0]);
  assert.deepEqual(di('aide_comptable', 'patients'), [0, 0, 0]);
});
test('accueil et agent administratif : le répertoire des patients seulement ; le comptable : ses jeux comptables, jamais les patients ni les prix ; le biologiste : le modèle des analyses, plus le prix (Q10)', () => {
  for (const r of ['reception', 'agentadmin']) { assert.deepEqual(di(r, 'patients'), [1, 1, 1], r); for (const j of jeuxImp.filter((x) => x !== 'patients')) assert.equal(di(r, j)[0], 0, r + ' ' + j); }
  for (const j of ['plan-comptable', 'soldes-ouverture', 'fournisseurs', 'assureurs', 'souscripteurs']) assert.deepEqual(di('comptable', j), [1, 1, 1], j);
  assert.deepEqual(di('comptable', 'grand-stock'), [1, 0, 0]);
  for (const j of ['patients', 'personnel', 'tarifs']) assert.deepEqual(di('comptable', j), [0, 0, 0], j);
  assert.deepEqual(di('laborantin', 'analyses-modele'), [1, 1, 1]);
  assert.deepEqual(di('laborantin', 'tarifs'), [0, 0, 0]);
});
test('la Direction arrête les prix (voir, importer, annuler sur tarifs) et lit le reste sans l\'importer ; la DAF et l\'administrateur détiennent tout', () => {
  assert.deepEqual(di('direction', 'tarifs'), [1, 1, 1]);
  for (const j of jeuxImp.filter((x) => x !== 'tarifs')) assert.deepEqual(di('direction', j), [1, 0, 0], j);
  for (const r of ['da', 'admin']) for (const j of jeuxImp) assert.deepEqual(di(r, j), [1, 1, 1], r + ' ' + j);
});
test('aucun import pour le médecin, le caissier, l\'infirmier, l\'ambulancier, l\'échographiste ni les rôles archivés', () => {
  for (const r of ['medecin', 'caissier', 'infirmier', 'aide_soignant', 'ambulancier', 'surveillant', 'chirurgien', 'anesthesiste', 'echographiste', 'assistant_comptable', 'dm', 'pharmacien', 'rh']) for (const j of jeuxImp) assert.deepEqual(di(r, j), [0, 0, 0], r + ' ' + j);
});
test('I11 : superviser (lire tous les lots) est TIRÉ DU DROIT d\'annuler sur chaque jeu : la DAF et l\'administrateur seuls ; I10 : la capacité paie est celle d\'écrire dans la paie', () => {
  assert.deepEqual(imp.superviseurs.slice().sort(), ['admin', 'da']);
  assert.ok(imp.capacitePaie.includes('da') && imp.capacitePaie.includes('admin'));
  for (const r of ['direction', 'stock', 'reception', 'laborantin', 'aide_comptable']) assert.ok(!imp.capacitePaie.includes(r), r);
});
test('I8 et RG-13 : « ignorer les existants » sur les fournisseurs seulement, les prix se versionnent, patients, personnel et soldes d\'ouverture sont des jeux restreints', () => {
  const doublon = (id) => imp.jeux.find((j) => j.id === id).doublon;
  assert.equal(doublon('fournisseurs'), 'ignorer'); assert.equal(doublon('tarifs'), 'versionner'); assert.equal(doublon('patients'), 'refuser');
  assert.deepEqual(imp.jeux.filter((j) => j.doublon === 'ignorer').map((j) => j.id), ['fournisseurs']);
  assert.deepEqual(imp.jeux.filter((j) => j.sensibilite === 'restreinte').map((j) => j.id).sort(), ['patients', 'personnel', 'soldes-ouverture']);
});
test('une page de jeu `imp-*` est visible de qui détient le droit VOIR du jeu (une seule vérité), et la page d\'accueil de qui détient un jeu au moins', () => {
  for (const r of rbac.roles) {
    let un = false;
    for (const j of imp.jeux.filter((x) => /^imp-/.test(x.ecran))) { const v = di(r.id, j.id)[0] === 1; if (v) un = true; assert.equal(!!droit(r.id, j.ecran), v, r.id + ' ' + j.ecran); }
    assert.equal(!!droit(r.id, 'imp-accueil'), un || imp.jeux.some((x) => di(r.id, x.id)[0] === 1), r.id + ' imp-accueil');
  }
});
