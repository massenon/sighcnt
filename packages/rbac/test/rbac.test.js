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
  /* L'accueil : le répertoire seulement. L'agent administratif : le répertoire ET le registre du courrier (lot IMP-B2). */
  for (const j of jeuxImp.filter((x) => x !== 'patients')) assert.equal(di('reception', j)[0], 0, 'reception ' + j);
  assert.deepEqual(di('reception', 'patients'), [1, 1, 1]); assert.deepEqual(di('agentadmin', 'patients'), [1, 1, 1]);
  for (const j of jeuxImp.filter((x) => x !== 'patients' && x !== 'courriers')) assert.equal(di('agentadmin', j)[0], 0, 'agentadmin ' + j);
  for (const j of ['plan-comptable', 'soldes-ouverture', 'fournisseurs', 'assureurs', 'souscripteurs']) assert.deepEqual(di('comptable', j), [1, 1, 1], j);
  assert.deepEqual(di('comptable', 'grand-stock'), [1, 0, 0]);
  for (const j of ['patients', 'personnel', 'tarifs']) assert.deepEqual(di('comptable', j), [0, 0, 0], j);
  assert.deepEqual(di('laborantin', 'analyses-modele'), [1, 1, 1]);
  assert.deepEqual(di('laborantin', 'tarifs'), [0, 0, 0]);
});
const jeuxStock = ['produits-referentiel', 'emplacements', 'stock-detail-initial', 'transfert-lignes', 'inventaire-comptage'];
/* Lot T5 : les prix d'achat des produits : le gestionnaire de stock, la DAF et l'administrateur importent ; le comptable lit ; la Direction n'a pas la lecture de ce jeu (consigne du lot, comme pour les jeux du stock). */
const jeuxPrixAchat = ['tarifs-produits'];
test('la Direction arrête les prix (voir, importer, annuler sur tarifs) et lit le reste sans l\'importer, SAUF les cinq jeux du stock (lot IMP-B1 : aucun autre profil que le gestionnaire, la DAF et l\'administrateur) ; la DAF et l\'administrateur détiennent tout', () => {
  assert.deepEqual(di('direction', 'tarifs'), [1, 1, 1]);
  for (const j of jeuxImp.filter((x) => x !== 'tarifs' && jeuxStock.indexOf(x) < 0 && jeuxPrixAchat.indexOf(x) < 0)) assert.deepEqual(di('direction', j), [1, 0, 0], j);
  for (const j of jeuxStock.concat(jeuxPrixAchat)) assert.deepEqual(di('direction', j), [0, 0, 0], j);
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
test('I8 et RG-13 : « ignorer les existants » sur les fournisseurs, le référentiel produits, les emplacements et les courriers SEULEMENT (liste fermée), les prix et les garanties se versionnent, patients, personnel, soldes d\'ouverture, les trois jeux du stock qui écrivent des mouvements et les quatre jeux du lot IMP-B2 (couvertures, immobilisations, budgets, courriers) sont des jeux restreints', () => {
  const doublon = (id) => imp.jeux.find((j) => j.id === id).doublon;
  assert.equal(doublon('fournisseurs'), 'ignorer'); assert.equal(doublon('tarifs'), 'versionner'); assert.equal(doublon('patients'), 'refuser');
  assert.deepEqual(imp.jeux.filter((j) => j.doublon === 'ignorer').map((j) => j.id).sort(), ['courriers', 'emplacements', 'fournisseurs', 'produits-referentiel']);
  assert.deepEqual(imp.jeux.filter((j) => j.doublon === 'versionner').map((j) => j.id).sort(), ['garanties', 'tarifs', 'tarifs-produits']);
  assert.deepEqual(imp.jeux.filter((j) => j.sensibilite === 'restreinte').map((j) => j.id).sort(), ['budgets', 'courriers', 'couvertures-assurance', 'immobilisations', 'inventaire-comptage', 'patients', 'personnel', 'soldes-ouverture', 'stock-detail-initial', 'transfert-lignes']);
});
test('IMP-B1 (I6, I8, I13) : le gestionnaire de stock importe les cinq jeux du stock (référentiel produits, emplacements, stock détail initial, bon de transfert, comptage d\'inventaire), la DAF et l\'administrateur aussi ; le comptable ne lit que le Grand Stock ; aucun autre profil', () => {
  for (const r of ['stock', 'da', 'admin']) for (const j of jeuxStock) assert.deepEqual(di(r, j), [1, 1, 1], r + ' ' + j);
  assert.deepEqual(di('comptable', 'grand-stock'), [1, 0, 0]);
  for (const r of rbac.roles.map((x) => x.id).filter((x) => ['stock', 'da', 'admin'].indexOf(x) < 0)) for (const j of jeuxStock) assert.deepEqual(di(r, j), [0, 0, 0], r + ' ' + j);
  const hote = (id) => imp.jeux.find((j) => j.id === id).hotes;
  assert.deepEqual(hote('produits-referentiel'), ['m6-produits']); assert.deepEqual(hote('emplacements'), ['m6-etiquetage']); assert.deepEqual(hote('stock-detail-initial'), ['m6-stock-detail']);
  assert.deepEqual(hote('transfert-lignes'), ['m6-transferts']); assert.deepEqual(hote('inventaire-comptage'), ['m6-inventaire']);
});
test('T5 : le jeu des prix d\'achat (tarifs-produits) : le gestionnaire de stock, la DAF et l\'administrateur ont VIA, le comptable lit seulement, personne d\'autre ; hôtes : Tarifs et prix et Référentiel produits', () => {
  for (const r of ['stock', 'da', 'admin']) assert.deepEqual(di(r, 'tarifs-produits'), [1, 1, 1], r);
  assert.deepEqual(di('comptable', 'tarifs-produits'), [1, 0, 0]);
  for (const r of rbac.roles.map((x) => x.id).filter((x) => ['stock', 'da', 'admin', 'comptable'].indexOf(x) < 0)) assert.deepEqual(di(r, 'tarifs-produits'), [0, 0, 0], r);
  assert.deepEqual(imp.jeux.find((j) => j.id === 'tarifs-produits').hotes, ['cfg-tarifs', 'm6-produits']);
  assert.equal(imp.jeux.find((j) => j.id === 'tarifs-produits').doublon, 'versionner');
});
/* ---- Lot IMP-B2 (12/11/2026) : les dix autres référentiels, une ligne par décision --------------------------------------------------------------------------------------------- */
const jeuxB2 = ['natures-facture', 'centres-couts', 'catalogue-imagerie', 'unites-labo', 'prestataires', 'garanties', 'couvertures-assurance', 'immobilisations', 'budgets', 'courriers'];
const jeuxComptable = ['centres-couts', 'garanties', 'couvertures-assurance', 'immobilisations', 'budgets'];
test('IMP-B2 : les dix jeux sont déclarés avec leur page et leur hôte, un hôte par jeu', () => {
  assert.deepEqual(jeuxB2.filter((j) => jeuxImp.indexOf(j) < 0), []);
  const hote = (id) => imp.jeux.find((j) => j.id === id).hotes;
  assert.deepEqual(hote('natures-facture'), ['cfg-natures-facture']); assert.deepEqual(hote('centres-couts'), ['cfg-centres-couts']); assert.deepEqual(hote('catalogue-imagerie'), ['cfg-imagerie-catalogue']);
  assert.deepEqual(hote('unites-labo'), ['m5-unites']); assert.deepEqual(hote('prestataires'), ['m10-prestataires']); assert.deepEqual(hote('garanties'), ['m9-conventions']);
  assert.deepEqual(hote('couvertures-assurance'), ['m9-assures']); assert.deepEqual(hote('immobilisations'), ['m12-immobilisations']); assert.deepEqual(hote('budgets'), ['m12-budgets']); assert.deepEqual(hote('courriers'), ['m13-courriers']);
});
test('IMP-B2 : l\'administrateur et la DAF importent et annulent les dix jeux (VIA) ; la Direction les VOIT seulement (V) : elle voit le modèle et ses propres lots, jamais elle n\'importe', () => {
  for (const r of ['admin', 'da']) for (const j of jeuxB2) assert.deepEqual(di(r, j), [1, 1, 1], r + ' ' + j);
  for (const j of jeuxB2) assert.deepEqual(di('direction', j), [1, 0, 0], 'direction ' + j);
});
test('IMP-B2 : le comptable détient VIA sur centres de coûts, garanties, couvertures, immobilisations et budgets, et rien sur les cinq autres', () => {
  for (const j of jeuxComptable) assert.deepEqual(di('comptable', j), [1, 1, 1], j);
  for (const j of jeuxB2.filter((x) => jeuxComptable.indexOf(x) < 0)) assert.deepEqual(di('comptable', j), [0, 0, 0], j);
});
test('IMP-B2 (I7) : l\'assistant comptable VOIT les jeux du comptable et n\'importe aucun des dix, la matrice pouvant le lui ouvrir plus tard sans code', () => {
  for (const j of jeuxComptable) assert.deepEqual(di('aide_comptable', j), [1, 0, 0], j);
  for (const j of jeuxB2.filter((x) => jeuxComptable.indexOf(x) < 0)) assert.deepEqual(di('aide_comptable', j), [0, 0, 0], j);
});
test('IMP-B2 : le biologiste détient les unités de mesure (VIA) et rien d\'autre ; l\'agent administratif détient les courriers (VIA) et le répertoire ; l\'échographiste n\'écrit pas le catalogue de l\'imagerie', () => {
  assert.deepEqual(di('laborantin', 'unites-labo'), [1, 1, 1]);
  for (const j of jeuxB2.filter((x) => x !== 'unites-labo')) assert.deepEqual(di('laborantin', j), [0, 0, 0], 'laborantin ' + j);
  assert.deepEqual(di('agentadmin', 'courriers'), [1, 1, 1]);
  for (const j of jeuxB2.filter((x) => x !== 'courriers')) assert.deepEqual(di('agentadmin', j), [0, 0, 0], 'agentadmin ' + j);
  assert.deepEqual(di('echographiste', 'catalogue-imagerie'), [0, 0, 0]);
});
test('IMP-B2 : natures de facture, catalogue de l\'imagerie et prestataires : la DAF et l\'administrateur seulement (la Direction lit) ; aucun autre profil des dix ne reçoit un droit sur eux', () => {
  for (const j of ['natures-facture', 'catalogue-imagerie', 'prestataires']) for (const r of rbac.roles.map((x) => x.id).filter((x) => ['da', 'admin', 'direction'].indexOf(x) < 0)) assert.deepEqual(di(r, j), [0, 0, 0], r + ' ' + j);
});
test('IMP-B2 : aucun autre profil (gestionnaire de stock, accueil, caissier, médecin, assistant de direction, rôles archivés) ne détient un des dix jeux', () => {
  for (const r of ['stock', 'reception', 'caissier', 'medecin', 'infirmier', 'assistant_comptable', 'ambulancier', 'surveillant', 'chirurgien', 'anesthesiste', 'dm', 'pharmacien', 'rh']) for (const j of jeuxB2) assert.deepEqual(di(r, j), [0, 0, 0], r + ' ' + j);
});
test('IMP-B2 : les modes de doublon et les sensibilités : garanties versionnent, courriers ignorent, les quatre jeux restreints (couvertures, immobilisations, budgets, courriers) ne recopient aucune valeur', () => {
  const j = (id) => imp.jeux.find((x) => x.id === id);
  assert.equal(j('garanties').doublon, 'versionner'); assert.equal(j('courriers').doublon, 'ignorer');
  for (const id of ['natures-facture', 'centres-couts', 'catalogue-imagerie', 'unites-labo', 'prestataires', 'couvertures-assurance', 'immobilisations', 'budgets']) assert.equal(j(id).doublon, 'refuser', id);
  for (const id of ['couvertures-assurance', 'immobilisations', 'budgets', 'courriers']) assert.equal(j(id).sensibilite, 'restreinte', id);
  for (const id of ['natures-facture', 'centres-couts', 'catalogue-imagerie', 'unites-labo', 'prestataires', 'garanties']) assert.equal(j(id).sensibilite, 'courante', id);
});
test('une page de jeu `imp-*` est visible de qui détient le droit VOIR du jeu (une seule vérité), et la page d\'accueil de qui détient un jeu au moins', () => {
  for (const r of rbac.roles) {
    let un = false;
    for (const j of imp.jeux.filter((x) => /^imp-/.test(x.ecran))) { const v = di(r.id, j.id)[0] === 1; if (v) un = true; assert.equal(!!droit(r.id, j.ecran), v, r.id + ' ' + j.ecran); }
    assert.equal(!!droit(r.id, 'imp-accueil'), un || imp.jeux.some((x) => di(r.id, x.id)[0] === 1), r.id + ' imp-accueil');
  }
});

test('lot C : le geste « corriger le texte lu » est donné D\'ORIGINE aux seuls rôles qui écrivent sur l\'écran d\'une pièce (M13 courriers, M1 documents du patient) : liste dérivée de la matrice, jamais écrite deux fois ; ni pharmacien, ni comptable, ni caissier ; aucun rôle archivé', () => {
  const g = rbac.gestes.jeux.find((x) => x.id === 'corriger_texte_ocr');
  assert.ok(g, 'le geste est déclaré');
  assert.deepEqual(g.defautSiEcritSur, ['M13', 'M1']);
  const attendus = rbac.roles.filter((r) => !r.archive && g.defautSiEcritSur.some((m) => rbac.matriceModules[r.id] && rbac.matriceModules[r.id][m] && rbac.matriceModules[r.id][m].editer)).map((r) => r.id).sort();
  const detenus = Object.keys(rbac.gestes.parRole).filter((r) => rbac.gestes.parRole[r].corriger_texte_ocr === 1).sort();
  assert.deepEqual(detenus, attendus, 'la liste d\'origine du manifeste = les rôles qui écrivent M13 ou M1');
  assert.deepEqual([...g.rolesDefaut].sort(), attendus);
  for (const r of ['pharmacien', 'comptable', 'caissier', 'rh', 'stock', 'aide_soignant']) assert.equal(rbac.gestes.parRole[r].corriger_texte_ocr, 0, r);
  for (const r of rbac.roles.filter((x) => x.archive)) assert.equal(rbac.gestes.parRole[r.id].corriger_texte_ocr, 0, r.id);
  for (const r of ['admin', 'da', 'medecin', 'infirmier', 'reception', 'agentadmin']) assert.equal(rbac.gestes.parRole[r].corriger_texte_ocr, 1, r);
});
