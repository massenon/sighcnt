'use strict';
/* Tests du MODE PAIR (ADR-0006) : la règle de fusion converge, quel que soit l'ordre d'arrivée, avec la mère éteinte. */
const test = require('node:test');
const assert = require('node:assert/strict');
const { etat, comparer, Horloge, JournalRelais } = require('./pair.js');

const ser = (e) => JSON.stringify({ ...e, provisoire: [...e.provisoire].sort() });
let n = 0;
const op = (appareil, hlc, collection, fiche, type, champs = {}, extra = {}) => ({ id: `${appareil}-${++n}`, appareil, hlc, collection, fiche, type, champs, role: 'x', ...extra });

function permutations(a) { if (a.length <= 1) return [a]; const out = []; a.forEach((x, i) => permutations([...a.slice(0, i), ...a.slice(i + 1)]).forEach((p) => out.push([x, ...p]))); return out; }
function melange(a, graine) { const r = [...a]; let s = graine; for (let i = r.length - 1; i > 0; i--) { s = (s * 1103515245 + 12345) & 0x7fffffff; const j = s % (i + 1); [r[i], r[j]] = [r[j], r[i]]; } return r; }

const scenario = () => [
  op('mere', 10, 'stock', 'para', 'creer', { qte: 100 }),
  op('mere', 11, 'stock', 'para', 'bail', { appareil: 'F1', qte: 30 }),
  op('mere', 12, 'stock', 'para', 'bail', { appareil: 'F2', qte: 20 }),
  op('F1', 20, 'stock', 'para', 'sortie', { qte: 25 }),
  op('F2', 21, 'stock', 'para', 'sortie', { qte: 25 }), // hors part (20) : marquée, jamais appliquée
  op('F1', 22, 'patients', 'p1', 'creer', { nom: 'KOUA', tel: '1' }),
  op('F2', 23, 'patients', 'p1', 'modifier', { tel: '2' }, { vu: { tel: 22 } }),
];

test('convergence : les 5040 ordres d\'arrivée de 7 opérations donnent le MÊME état', () => {
  const ops = scenario();
  const ref = ser(etat(ops));
  for (const p of permutations(ops)) assert.equal(ser(etat(p)), ref);
});

test('convergence : doublons et rejeux ne changent rien (idempotence par id)', () => {
  const ops = scenario();
  assert.equal(ser(etat([...ops, ...ops, ...ops.slice(2)])), ser(etat(ops)));
});

test('stock : jamais négatif, une sortie hors de la part est marquée et non appliquée (RG-03)', () => {
  for (let graine = 1; graine <= 200; graine++) {
    const ops = [op('mere', 1, 'stock', 'a', 'creer', { qte: 50 }), op('mere', 2, 'stock', 'a', 'bail', { appareil: 'F1', qte: 20 }), op('mere', 3, 'stock', 'a', 'bail', { appareil: 'F2', qte: 20 })];
    let h = 10;
    for (let i = 0; i < 12; i++) ops.push(op(i % 2 ? 'F1' : 'F2', h++, 'stock', 'a', i % 5 === 0 ? 'entree' : 'sortie', { qte: 1 + ((graine + i * 7) % 9) }));
    const e = etat(melange(ops, graine));
    assert.ok(e.stock.a.qte >= 0, `stock négatif (graine ${graine})`);
    assert.equal(ser(etat(melange(ops, graine + 1000))), ser(e));
  }
  const e = etat(scenario());
  assert.equal(e.stock.para.qte, 75);
  assert.deepEqual(e.refusees.map((r) => r.code), ['hors_part']);
});

test('fiche A : deux écritures concurrentes du même champ sont MARQUÉES, la plus récente de l\'ordre total l\'emporte, sur tous les appareils', () => {
  const e = etat(scenario());
  assert.equal(e.fiches['patients/p1'].data.tel, '2');
  assert.equal(e.conflits.length, 0, 'F2 avait vu la version de F1 : pas de conflit');
  const concurrentes = [op('F1', 1, 'patients', 'q', 'creer', { nom: 'A' }), op('F1', 5, 'patients', 'q', 'modifier', { nom: 'B' }, { vu: { nom: 1 } }), op('F2', 6, 'patients', 'q', 'modifier', { nom: 'C' }, { vu: { nom: 1 } })];
  const r = etat(concurrentes);
  assert.equal(r.fiches['patients/q'].data.nom, 'C');
  assert.equal(r.conflits.length, 1);
  assert.equal(r.conflits[0].champ, 'nom');
  for (const p of permutations(concurrentes)) assert.equal(ser(etat(p)), ser(r));
});

test('pièce C : une modification APRÈS l\'émission est marquée ; une modification d\'avant, arrivée en retard, s\'applique', () => {
  const ops = [op('F1', 1, 'factures', 'f1', 'creer', { total: 100 }), op('F2', 3, 'factures', 'f1', 'modifier', { total: 120 }, { vu: { total: 1 } }), op('F1', 4, 'factures', 'f1', 'emettre'), op('F2', 6, 'factures', 'f1', 'modifier', { total: 999 }, { vu: { total: 3 } })];
  const e = etat(ops);
  assert.equal(e.fiches['factures/f1'].data.total, 120);
  assert.deepEqual(e.refusees.map((r) => r.code), ['piece_emise_immuable']);
  for (const p of permutations(ops)) assert.equal(ser(etat(p)), ser(e));
});

test('TRANCHER : la décision lève le conflit marqué et fixe la valeur ; un conflit né après elle reste marqué ; refusée sans le droit, sur pièce émise ou fiche archivée', () => {
  const droits = (o) => !(o.type === 'trancher' && !['da', 'mere'].includes(o.role));
  const base = [op('F1', 1, 'patients', 'q', 'creer', { nom: 'A' }), op('F1', 5, 'patients', 'q', 'modifier', { nom: 'B' }, { vu: { nom: 1 } }), op('F2', 6, 'patients', 'q', 'modifier', { nom: 'C' }, { vu: { nom: 1 } })];
  assert.equal(etat(base, droits).conflits.length, 1);
  const tr = op('mere', 10, 'patients', 'q', 'trancher', { nom: 'B' }, { role: 'mere', seq: 4 });
  const e = etat([...base, tr], droits);
  assert.equal(e.conflits.length, 0);
  assert.equal(e.fiches['patients/q'].data.nom, 'B');
  assert.deepEqual(e.tranches.map((t) => [t.champ, t.valeur, t.par]), [['nom', 'B', 'mere']]);
  const tard = op('F3', 12, 'patients', 'q', 'modifier', { nom: 'D' }, { vu: { nom: 1 } });
  assert.equal(etat([...base, tr, tard], droits).conflits.length, 1, 'un conflit postérieur à la décision reste marqué');
  for (const p of permutations([...base, tr, tard])) assert.equal(ser(etat(p, droits)), ser(etat([...base, tr, tard], droits)));
  const sansDroit = op('F2', 11, 'patients', 'q', 'trancher', { nom: 'C' }, { role: 'infirmier' });
  assert.deepEqual(etat([...base, sansDroit], droits).refusees.map((r) => r.code), ['droit_refuse']);
  const piece = [op('F1', 1, 'factures', 'f', 'creer', { total: 1 }), op('F1', 2, 'factures', 'f', 'emettre'), op('mere', 3, 'factures', 'f', 'trancher', { total: 9 }, { role: 'mere' })];
  assert.deepEqual(etat(piece).refusees.map((r) => r.code), ['piece_emise_immuable']);
  const arch = [op('F1', 1, 'patients', 'z', 'creer', { nom: 'A' }), op('F1', 2, 'patients', 'z', 'archiver'), op('mere', 3, 'patients', 'z', 'trancher', { nom: 'B' }, { role: 'mere' })];
  assert.deepEqual(etat(arch).refusees.map((r) => r.code), ['fiche_archivee']);
});

test('journal B : ajout seul, union commutative', () => {
  const ops = [op('F1', 1, 'constantes', 'c1', 'creer', { t: 37 }), op('F2', 2, 'constantes', 'c2', 'creer', { t: 38 }), op('F1', 3, 'constantes', 'c1', 'modifier', { t: 40 })];
  const e = etat(ops);
  assert.equal(Object.keys(e.fiches).length, 2);
  assert.deepEqual(e.refusees.map((r) => r.code), ['journal_immuable']);
});

test('RBAC à la réception : l\'opération d\'un rôle sans droit est écartée de la même façon sur tous les appareils', () => {
  const droits = (o) => !(o.collection === 'besoins' && (o.type === 'valider' || o.type === 'rejeter') && o.role !== 'da');
  const ops = [
    op('F1', 1, 'besoins', 'b1', 'soumettre', { article: 'gants' }, { role: 'stock' }),
    op('F2', 2, 'besoins', 'b1', 'valider', {}, { role: 'infirmier' }), // pas le rôle validateur
    op('F3', 3, 'besoins', 'b1', 'valider', {}, { role: 'da' }),
  ];
  const e = etat(ops, droits);
  assert.equal(e.besoins.b1.etat, 'valide');
  assert.deepEqual(e.refusees.map((r) => r.code), ['droit_refuse']);
  for (const p of permutations(ops)) assert.equal(ser(etat(p, droits)), ser(e));
});

test('flux de travail : la validation d\'une demande non soumise est écartée ; une seule décision compte', () => {
  const ops = [op('F3', 1, 'besoins', 'b2', 'valider', {}, { role: 'da' }), op('F1', 2, 'besoins', 'b2', 'soumettre', {}, { role: 'stock' }), op('F3', 3, 'besoins', 'b2', 'valider', {}, { role: 'da' }), op('F3', 4, 'besoins', 'b2', 'rejeter', {}, { role: 'da' })];
  const e = etat(ops);
  assert.equal(e.besoins.b2.etat, 'valide');
  assert.deepEqual(e.refusees.map((r) => r.code).sort(), ['deja_decide', 'demande_inconnue']);
});

test('suppression physique refusée (RG-14)', () => {
  const e = etat([op('F1', 1, 'patients', 'p', 'creer', { nom: 'A' }), op('F1', 2, 'patients', 'p', 'supprimer')]);
  assert.deepEqual(e.refusees.map((r) => r.code), ['suppression_interdite']);
  assert.ok(e.fiches['patients/p']);
});

test('provisoire : une fiche touchée sans seq de la mère l\'est ; avec seq, elle fait foi', () => {
  assert.ok(etat([op('F1', 1, 'patients', 'p', 'creer', { nom: 'A' })]).provisoire.has('patients/p'));
  assert.equal(etat([op('F1', 1, 'patients', 'p', 'creer', { nom: 'A' }, { seq: 7 })]).provisoire.size, 0);
});

test('horloge : strictement croissante, la dérive au-delà de 2 minutes est SIGNALÉE', () => {
  let t = 1000; const h = new Horloge(() => t);
  const a = h.emettre(); const b = h.emettre(); assert.ok(b > a);
  h.recevoir((t + 5 * 60 * 1000) * 1000);
  assert.equal(h.derive, true);
  assert.ok(h.emettre() > (t + 5 * 60 * 1000) * 1000);
});

test('journal au relais : rang contigu, dépôt idempotent, un trou est détecté', () => {
  const j = new JournalRelais();
  assert.equal(j.deposer('F1', 1, 'e1'), 'ok');
  assert.equal(j.deposer('F1', 1, 'e1'), 'deja');
  assert.throws(() => j.deposer('F1', 3, 'e3'), /trou de rang/);
  assert.equal(j.releve('F1', 0).length, 1);
});

test('SCÉNARIO : mère éteinte, trois fileuls s\'échangent par le relais et convergent ; la mère revient, rejoue, et l\'état est le même mais fait foi', () => {
  const relais = new JournalRelais();
  const appareils = ['F1', 'F2', 'F3'];
  const locaux = Object.fromEntries(appareils.map((a) => [a, { ops: [], rang: 0, curseurs: {} }]));
  const horloges = Object.fromEntries(appareils.map((a) => [a, new Horloge(() => 5000)]));
  const emettre = (a, collection, fiche, type, champs, extra = {}) => {
    const o = { id: `${a}-${++n}`, appareil: a, hlc: horloges[a].emettre(), collection, fiche, type, champs, role: extra.role || 'x', ...extra };
    locaux[a].ops.push(o); locaux[a].rang += 1; relais.deposer(a, locaux[a].rang, o); // publié à l'émission (réseau coupé : serait différé, jamais perdu)
  };
  const echanger = (a, partiel) => {
    for (const b of appareils.filter((x) => x !== a)) {
      const depuis = locaux[a].curseurs[b] || 0;
      const lot = relais.releve(b, depuis, partiel ? 1 : 100);
      for (const { n: rang, enveloppe } of lot) { assert.equal(rang, (locaux[a].curseurs[b] || 0) + 1); locaux[a].ops.push(enveloppe); horloges[a].recevoir(enveloppe.hlc); locaux[a].curseurs[b] = rang; }
    }
  };
  emettre('F1', 'stock', 'para', 'creer', { qte: 40 }, { role: 'stock' });
  emettre('F1', 'stock', 'para', 'bail', { appareil: 'F2', qte: 10 }, { role: 'stock' });
  emettre('F2', 'patients', 'p1', 'creer', { nom: 'AKPO', tel: '1' });
  echanger('F3', true); echanger('F1'); echanger('F2', true);
  emettre('F3', 'besoins', 'b1', 'soumettre', { article: 'gants' }, { role: 'stock' });
  emettre('F2', 'stock', 'para', 'sortie', { qte: 6 });
  const creation = locaux.F2.ops.find((o) => o.type === 'creer' && o.collection === 'patients').hlc; // la version que F1 et F3 ont vue
  emettre('F1', 'patients', 'p1', 'modifier', { tel: '9' }, { vu: { tel: creation } });
  emettre('F3', 'patients', 'p1', 'modifier', { tel: '7' }, { vu: { tel: creation } });
  for (let tour = 0; tour < 6; tour++) for (const a of appareils) echanger(a, tour < 2);
  const droits = () => true;
  const etats = appareils.map((a) => ser(etat(locaux[a].ops, droits)));
  assert.equal(new Set(etats).size, 1, 'les trois fileuls divergent');
  const E = etat(locaux.F1.ops, droits);
  assert.equal(E.stock.para.qte, 34);
  assert.equal(E.conflits.length, 1, 'le conflit sur le téléphone reste MARQUÉ pour être tranché');
  assert.ok(E.provisoire.has('patients/p1'));
  // retour de la mère : elle relève tous les journaux, attribue un seq, rejoue : mêmes valeurs, plus provisoire
  const tous = []; relais.appareils().forEach((a) => relais.releve(a, 0).forEach((x) => tous.push(x.enveloppe)));
  let seq = 0; const faisantFoi = tous.sort(comparer).map((o) => ({ ...o, seq: ++seq }));
  const M = etat(faisantFoi, droits);
  assert.equal(JSON.stringify(M.fiches), JSON.stringify(E.fiches));
  assert.equal(JSON.stringify(M.stock), JSON.stringify(E.stock));
  assert.equal(M.provisoire.size, 0);
});

/* --- pièces certifiantes (famille C) : numérotation, avoir, écriture équilibrée --------------------------------------------------------------------------- */
const codes = (e) => e.refusees.map((r) => r.code).sort();
const lignesOk = [{ compte: '571', debit: 100, credit: 0 }, { compte: '706', debit: 0, credit: 100 }];

test('numérotation : un numéro porté par deux pièces émises est MARQUÉ sur les deux, jamais renuméroté, quel que soit l\'ordre d\'arrivée', () => {
  const ops = [
    op('F1', 1, 'factures', 'f1', 'creer', { total: 10 }), op('F1', 2, 'factures', 'f1', 'emettre', { numero: 'FAC-0042' }),
    op('F2', 1, 'factures', 'f2', 'creer', { total: 20 }), op('F2', 3, 'factures', 'f2', 'emettre', { numero: 'FAC-0042' }),
    op('F2', 4, 'factures', 'f3', 'creer', { total: 5 }), op('F2', 5, 'factures', 'f3', 'emettre', { numero: 'FAC-0043' }),
  ];
  const e = etat(ops);
  assert.equal(e.fiches['factures/f1'].doublon, true);
  assert.equal(e.fiches['factures/f2'].doublon, true);
  assert.equal(e.fiches['factures/f3'].doublon, undefined);
  assert.equal(e.fiches['factures/f2'].numero, 'FAC-0042', 'jamais renuméroté');
  for (const p of permutations(ops).slice(0, 200)) assert.equal(ser(etat(p)), ser(e));
});

test('numérotation : le numéro d\'une pièce émise ne se réécrit jamais, la ré-émission identique est inoffensive', () => {
  const e = etat([op('F1', 1, 'factures', 'f1', 'creer', { total: 10 }), op('F1', 2, 'factures', 'f1', 'emettre', { numero: 'A' }), op('F2', 3, 'factures', 'f1', 'emettre', { numero: 'B' }), op('F2', 4, 'factures', 'f1', 'emettre', { numero: 'A' })]);
  assert.equal(e.fiches['factures/f1'].numero, 'A');
  assert.deepEqual(codes(e), ['numero_immuable']);
});

test('écriture : RG-10, elle ne s\'émet que ÉQUILIBRÉE ; brouillon déséquilibré toléré, émission refusée', () => {
  const desequilibre = etat([op('F1', 1, 'ecritures', 'e1', 'creer', { lignes: [{ compte: '571', debit: 100, credit: 0 }, { compte: '706', debit: 0, credit: 90 }] }), op('F1', 2, 'ecritures', 'e1', 'emettre', { numero: 'OD-1' })]);
  assert.deepEqual(codes(desequilibre), ['ecriture_desequilibree']);
  assert.equal(desequilibre.fiches['ecritures/e1'].emise, false);
  const seule = etat([op('F1', 1, 'ecritures', 'e2', 'creer', { lignes: [{ compte: '571', debit: 100, credit: 100 }] }), op('F1', 2, 'ecritures', 'e2', 'emettre')]);
  assert.deepEqual(codes(seule), ['ecriture_desequilibree'], 'une seule ligne n\'est pas une pièce');
  const bonne = etat([op('F1', 1, 'ecritures', 'e3', 'creer', { lignes: lignesOk }), op('F1', 2, 'ecritures', 'e3', 'emettre', { numero: 'OD-2' })]);
  assert.equal(bonne.fiches['ecritures/e3'].emise, true);
  assert.equal(codes(bonne).length, 0);
});

test('avoir : seul canal de correction ; il vise une facture ÉMISE et le cumul ne dépasse jamais la facture', () => {
  const base = [op('F1', 1, 'factures', 'f1', 'creer', { total: 100 })];
  assert.deepEqual(codes(etat([...base, op('F2', 3, 'avoirs', 'a1', 'creer', { facture: 'f1', montant: 10 })])), ['avoir_sans_facture_emise'], 'facture non émise');
  const emise = [...base, op('F1', 2, 'factures', 'f1', 'emettre', { numero: 'FAC-1' })];
  const ok = etat([...emise, op('F2', 3, 'avoirs', 'a1', 'creer', { facture: 'f1', montant: 60 }), op('F3', 4, 'avoirs', 'a2', 'creer', { facture: 'f1', montant: 40 })]);
  assert.equal(codes(ok).length, 0);
  assert.equal(ok.fiches['factures/f1'].avoirs, 100);
  const trop = etat([...emise, op('F2', 3, 'avoirs', 'a1', 'creer', { facture: 'f1', montant: 60 }), op('F3', 4, 'avoirs', 'a2', 'creer', { facture: 'f1', montant: 50 })]);
  assert.deepEqual(codes(trop), ['avoir_depasse']);
  assert.equal(trop.fiches['avoirs/a2'], undefined, 'l\'avoir refusé n\'existe pas');
  assert.equal(trop.fiches['factures/f1'].data.total, 100, 'la pièce émise n\'est jamais réécrite');
  const ops = [...emise, op('F2', 3, 'avoirs', 'a1', 'creer', { facture: 'f1', montant: 60 }), op('F3', 4, 'avoirs', 'a2', 'creer', { facture: 'f1', montant: 50 })];
  const ref = etat(ops);
  for (const p of permutations(ops)) assert.equal(ser(etat(p)), ser(ref));
});

/* --- stock : lots, mouvements, produits (famille D, B, A) ------------------------------------------------------------------------------------------------ */
test('lots : sorties dans la PART de l\'appareil, jamais de stock négatif (RG-03), indépendants du stock de même nom', () => {
  const ops = [
    op('mere', 1, 'lots', 'L1', 'creer', { qte: 50 }), op('mere', 2, 'lots', 'L1', 'bail', { appareil: 'F1', qte: 30 }), op('mere', 3, 'lots', 'L1', 'bail', { appareil: 'F2', qte: 20 }),
    op('F1', 4, 'lots', 'L1', 'sortie', { qte: 25 }), op('F2', 5, 'lots', 'L1', 'sortie', { qte: 25 }), op('F1', 6, 'lots', 'L1', 'sortie', { qte: 10 }),
    op('mere', 7, 'stock', 'L1', 'creer', { qte: 7 }),
  ];
  const e = etat(ops);
  assert.equal(e.stock['lots/L1'].qte, 25);
  assert.equal(e.stock.L1.qte, 7, 'le stock historique de même identifiant reste distinct');
  assert.deepEqual(codes(e), ['hors_part', 'hors_part']);
  assert.ok(Object.values(e.stock).every((s) => s.qte >= 0));
  for (const p of permutations(ops).slice(0, 300)) assert.equal(ser(etat(p)), ser(e));
});

test('mouvements : un journal ; une SORTIE sans justificatif est refusée (RG-03), une entrée n\'en demande pas', () => {
  const e = etat([
    op('F1', 1, 'mouvements', 'm1', 'creer', { sens: 'sortie', produit: 'para', qte: 2, justificatif: 'ORD-12' }),
    op('F1', 2, 'mouvements', 'm2', 'creer', { sens: 'sortie', produit: 'para', qte: 1 }),
    op('F2', 3, 'mouvements', 'm3', 'creer', { sens: 'entree', produit: 'para', qte: 5 }),
    op('F2', 4, 'mouvements', 'm1', 'modifier', { qte: 99 }),
  ]);
  assert.deepEqual(codes(e), ['journal_immuable', 'justificatif_manquant']);
  assert.deepEqual(Object.keys(e.fiches).sort(), ['mouvements/m1', 'mouvements/m3']);
});

test('produits : fiche à fusion par champ, la concurrence est marquée', () => {
  const e = etat([op('F1', 1, 'produits', 'p1', 'creer', { prix: 100 }), op('F1', 5, 'produits', 'p1', 'modifier', { prix: 110 }, { vu: { prix: 1 } }), op('F2', 6, 'produits', 'p1', 'modifier', { prix: 120 }, { vu: { prix: 1 } })]);
  assert.equal(e.conflits.length, 1);
  assert.equal(e.fiches['produits/p1'].data.prix, 120);
});

test('admissions : deux admissions actives sur un même lit sont MARQUÉES, aucune refusée ; transférer l\'une lève la marque ; indépendant de l\'ordre', () => {
  const ops = [
    op('F1', 1, 'admissions', 'a1', 'creer', { lit: 'Ch2-L1', statut: 'en_cours' }), op('F2', 1, 'admissions', 'a2', 'creer', { lit: 'Ch2-L1', statut: 'en_cours' }),
    op('F1', 2, 'admissions', 'a3', 'creer', { lit: 'Ch2-L2', statut: 'en_cours' }),
  ];
  const e = etat(ops);
  assert.equal(e.fiches['admissions/a1'].litEnConflit, true);
  assert.equal(e.fiches['admissions/a2'].litEnConflit, true);
  assert.equal(e.fiches['admissions/a3'].litEnConflit, undefined);
  assert.equal(codes(e).length, 0, 'aucune refusée');
  for (const p of permutations(ops)) assert.equal(ser(etat(p)), ser(e));
  const apres = etat([...ops, op('F1', 5, 'admissions', 'a2', 'modifier', { lit: 'Ch2-L3' }, { vu: { lit: 1 } })]);
  assert.equal(apres.fiches['admissions/a1'].litEnConflit, undefined, 'le transfert lève la marque');
  const sortie = etat([...ops, op('F1', 5, 'admissions', 'a2', 'modifier', { statut: 'terminee' }, { vu: { statut: 1 } })]);
  assert.equal(sortie.fiches['admissions/a1'].litEnConflit, undefined, 'la sortie lève la marque');
});
