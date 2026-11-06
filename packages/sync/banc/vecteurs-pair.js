'use strict';
/* Vecteurs de la RÈGLE DE FUSION ENTRE PAIRS (ADR-0006) : `pair.js` est l'exécutable de référence ; ce script engendre les cas que le domaine Dart rejoue
   (packages/domaine/test/pair_test.dart). ENGENDRÉ : ne pas éditer le JSON.   node banc/vecteurs-pair.js */
const fs = require('node:fs');
const path = require('node:path');
const { etat, droitsBanc, DROITS_BANC } = require('./pair.js');

let n = 0;
const op = (appareil, hlc, collection, fiche, type, champs = {}, extra = {}) => ({ id: `${appareil}-${++n}`, appareil, hlc, collection, fiche, type, champs, role: 'x', ...extra });
const ser = (e) => JSON.parse(JSON.stringify({ fiches: e.fiches, stock: e.stock, besoins: e.besoins, conflits: e.conflits, tranches: e.tranches, refusees: e.refusees.map((r) => ({ id: r.id, appareil: r.appareil, code: r.code })), provisoire: [...e.provisoire].sort() }));
const cas = [];
const ajouter = (nom, ops) => cas.push({ nom, ops, attendu: ser(etat(ops, droitsBanc)) });

ajouter('scénario mixte : stock avec parts, fiche patient, sortie hors part', [
  op('mere', 10, 'stock', 'para', 'creer', { qte: 100 }, { role: 'stock' }), op('mere', 11, 'stock', 'para', 'bail', { appareil: 'F1', qte: 30 }, { role: 'stock' }),
  op('mere', 12, 'stock', 'para', 'bail', { appareil: 'F2', qte: 20 }, { role: 'stock' }), op('F1', 20, 'stock', 'para', 'sortie', { qte: 25 }, { role: 'infirmier' }),
  op('F2', 21, 'stock', 'para', 'sortie', { qte: 25 }, { role: 'infirmier' }), op('F1', 22, 'patients', 'p1', 'creer', { nom: 'KOUA', tel: '1' }, { role: 'reception' }),
  op('F2', 23, 'patients', 'p1', 'modifier', { tel: '2' }, { role: 'reception', vu: { tel: 22 } }),
]);
ajouter('écritures concurrentes du même champ : conflit marqué', [
  op('F1', 1, 'patients', 'q', 'creer', { nom: 'A' }, { role: 'reception' }), op('F1', 5, 'patients', 'q', 'modifier', { nom: 'B' }, { role: 'reception', vu: { nom: 1 } }),
  op('F2', 6, 'patients', 'q', 'modifier', { nom: 'C' }, { role: 'reception', vu: { nom: 1 } }),
]);
ajouter('pièce émise : la modification après émission est marquée, celle d\'avant s\'applique', [
  op('F1', 1, 'factures', 'f1', 'creer', { total: 100 }, { role: 'caissier' }), op('F2', 3, 'factures', 'f1', 'modifier', { total: 120 }, { role: 'caissier', vu: { total: 1 } }),
  op('F1', 4, 'factures', 'f1', 'emettre', {}, { role: 'caissier' }), op('F2', 6, 'factures', 'f1', 'modifier', { total: 999 }, { role: 'caissier', vu: { total: 3 } }),
]);
ajouter('journal : ajout seul', [
  op('F1', 1, 'constantes', 'c1', 'creer', { t: 37 }, { role: 'infirmier' }), op('F2', 2, 'constantes', 'c2', 'creer', { t: 38 }, { role: 'infirmier' }), op('F1', 3, 'constantes', 'c1', 'modifier', { t: 40 }, { role: 'infirmier' }),
]);
ajouter('flux de travail : seule la DA valide, une décision sans demande est écartée', [
  op('F3', 1, 'besoins', 'b1', 'valider', {}, { role: 'da' }), op('F1', 2, 'besoins', 'b1', 'soumettre', { article: 'gants' }, { role: 'stock' }),
  op('F2', 3, 'besoins', 'b1', 'valider', {}, { role: 'infirmier' }), op('F3', 4, 'besoins', 'b1', 'valider', {}, { role: 'da' }), op('F3', 5, 'besoins', 'b1', 'rejeter', {}, { role: 'da' }),
]);
ajouter('suppression physique refusée, collection inconnue refusée', [
  op('F1', 1, 'patients', 'p', 'creer', { nom: 'A' }, { role: 'reception' }), op('F1', 2, 'patients', 'p', 'supprimer', {}, { role: 'reception' }), op('F1', 3, 'inconnue', 'z', 'creer', {}, { role: 'x' }),
]);
ajouter('provisoire : avec seq de la mère la fiche fait foi', [
  op('F1', 1, 'patients', 'p', 'creer', { nom: 'A' }, { role: 'reception', seq: 7 }), op('F2', 2, 'patients', 'r', 'creer', { nom: 'B' }, { role: 'reception' }),
]);
ajouter('archiver, restaurer, modifier une fiche archivée', [
  op('F1', 1, 'patients', 'p', 'creer', { nom: 'A' }, { role: 'reception' }), op('F1', 2, 'patients', 'p', 'archiver', {}, { role: 'reception' }),
  op('F2', 3, 'patients', 'p', 'modifier', { nom: 'B' }, { role: 'reception', vu: { nom: 1 } }), op('F1', 4, 'patients', 'p', 'restaurer', {}, { role: 'reception' }),
  op('F2', 5, 'patients', 'p', 'modifier', { nom: 'C' }, { role: 'reception', vu: { nom: 1 } }),
]);

ajouter('trancher : le conflit est levé, un conflit postérieur reste marqué, refus sans droit', [
  op('F1', 1, 'patients', 'q', 'creer', { nom: 'A' }, { role: 'reception' }), op('F1', 5, 'patients', 'q', 'modifier', { nom: 'B' }, { role: 'reception', vu: { nom: 1 } }),
  op('F2', 6, 'patients', 'q', 'modifier', { nom: 'C' }, { role: 'reception', vu: { nom: 1 } }), op('mere', 10, 'patients', 'q', 'trancher', { nom: 'B' }, { role: 'mere', seq: 4 }),
  op('F3', 12, 'patients', 'q', 'modifier', { nom: 'D' }, { role: 'reception', vu: { nom: 1 } }), op('F2', 13, 'patients', 'q', 'trancher', { nom: 'C' }, { role: 'infirmier' }),
]);
ajouter('trancher refusé sur pièce émise et sur fiche archivée', [
  op('F1', 1, 'factures', 'f', 'creer', { total: 1 }, { role: 'caissier' }), op('F1', 2, 'factures', 'f', 'emettre', {}, { role: 'caissier' }), op('mere', 3, 'factures', 'f', 'trancher', { total: 9 }, { role: 'mere' }),
  op('F1', 4, 'patients', 'z', 'creer', { nom: 'A' }, { role: 'reception' }), op('F1', 5, 'patients', 'z', 'archiver', {}, { role: 'reception' }), op('mere', 6, 'patients', 'z', 'trancher', { nom: 'B' }, { role: 'mere' }),
]);

/* chaque collection ajoutée a SES cas : écriture concurrente (famille A) ou ajout seul (famille B), rôle sans droit refusé, décision de la personne habilitée */
for (const [col, role, intrus] of [['consultations', 'medecin', 'caissier'], ['dossiersConsultation', 'medecin', 'reception'], ['antecedents', 'infirmier', 'caissier'], ['appels', 'reception', 'medecin'], ['observations', 'infirmier', 'caissier']]) {
  ajouter('collection ' + col + ' : concurrence marquée, décision, rôle sans droit refusé', [
    op('F1', 1, col, 'k', 'creer', { v: 'a' }, { role }), op('F1', 5, col, 'k', 'modifier', { v: 'b' }, { role, vu: { v: 1 } }),
    op('F2', 6, col, 'k', 'modifier', { v: 'c' }, { role, vu: { v: 1 } }), op('F3', 7, col, 'k', 'modifier', { v: 'x' }, { role: intrus, vu: { v: 6 } }),
    op('F1', 9, col, 'k', 'trancher', { v: 'b' }, { role: 'da' }),
  ]);
}
ajouter('collection releves (journal) : ajout seul, deux postes, rôle sans droit refusé', [
  op('F1', 1, 'releves', 'r1', 'creer', { t: 37 }, { role: 'infirmier' }), op('F2', 1, 'releves', 'r2', 'creer', { t: 38 }, { role: 'medecin' }),
  op('F3', 2, 'releves', 'r3', 'creer', { t: 39 }, { role: 'caissier' }), op('F1', 3, 'releves', 'r1', 'modifier', { t: 40 }, { role: 'infirmier' }),
]);

/* pièces certifiantes (famille C) : numérotation, doublon marqué, avoir, écriture équilibrée */
const lg = [{ compte: '571', debit: 100, credit: 0 }, { compte: '706', debit: 0, credit: 100 }];
ajouter('numéros en double : marqués sur les deux pièces, jamais renumérotés', [
  op('F1', 1, 'factures', 'f1', 'creer', { total: 10 }, { role: 'caissier' }), op('F1', 2, 'factures', 'f1', 'emettre', { numero: 'FAC-1' }, { role: 'caissier' }),
  op('F2', 1, 'factures', 'f2', 'creer', { total: 20 }, { role: 'caissier' }), op('F2', 3, 'factures', 'f2', 'emettre', { numero: 'FAC-1' }, { role: 'caissier' }),
  op('F2', 4, 'factures', 'f2', 'emettre', { numero: 'FAC-9' }, { role: 'caissier' }),
]);
ajouter('écriture : émission refusée si déséquilibrée, acceptée équilibrée ; une seule ligne refusée', [
  op('F1', 1, 'ecritures', 'e1', 'creer', { lignes: [{ compte: '571', debit: 100, credit: 0 }, { compte: '706', debit: 0, credit: 90 }] }, { role: 'comptable' }), op('F1', 2, 'ecritures', 'e1', 'emettre', { numero: 'OD-1' }, { role: 'comptable' }),
  op('F1', 3, 'ecritures', 'e2', 'creer', { lignes: lg }, { role: 'comptable' }), op('F1', 4, 'ecritures', 'e2', 'emettre', { numero: 'OD-2' }, { role: 'comptable' }),
  op('F2', 5, 'ecritures', 'e3', 'creer', { lignes: [{ compte: '571', debit: 5, credit: 5 }] }, { role: 'comptable' }), op('F2', 6, 'ecritures', 'e3', 'emettre', {}, { role: 'comptable' }),
]);
ajouter('avoir : facture non émise refusée, cumul plafonné, canal de correction d\'une pièce émise', [
  op('F1', 1, 'factures', 'f1', 'creer', { total: 100 }, { role: 'caissier' }), op('F2', 2, 'avoirs', 'a0', 'creer', { facture: 'f1', montant: 5 }, { role: 'comptable' }),
  op('F1', 3, 'factures', 'f1', 'emettre', { numero: 'FAC-1' }, { role: 'caissier' }),
  op('F2', 4, 'avoirs', 'a1', 'creer', { facture: 'f1', montant: 60 }, { role: 'comptable' }), op('F3', 5, 'avoirs', 'a2', 'creer', { facture: 'f1', montant: 50 }, { role: 'comptable' }),
  op('F1', 6, 'factures', 'f1', 'modifier', { total: 1 }, { role: 'caissier', vu: { total: 1 } }),
]);

/* stock : lots (famille D, distincts du stock de même nom), mouvements (journal, justificatif RG-03), produits (fiche) */
ajouter('lots : parts, sorties hors part refusées, indépendants du stock de même identifiant', [
  op('mere', 1, 'lots', 'L1', 'creer', { qte: 50 }, { role: 'stock' }), op('mere', 2, 'lots', 'L1', 'bail', { appareil: 'F1', qte: 30 }, { role: 'stock' }), op('mere', 3, 'lots', 'L1', 'bail', { appareil: 'F2', qte: 20 }, { role: 'stock' }),
  op('F1', 4, 'lots', 'L1', 'sortie', { qte: 25 }, { role: 'infirmier' }), op('F2', 5, 'lots', 'L1', 'sortie', { qte: 25 }, { role: 'infirmier' }), op('F1', 6, 'lots', 'L1', 'sortie', { qte: 10 }, { role: 'infirmier' }),
  op('mere', 7, 'stock', 'L1', 'creer', { qte: 7 }, { role: 'stock' }),
]);
ajouter('mouvements : sortie sans justificatif refusée, journal immuable', [
  op('F1', 1, 'mouvements', 'm1', 'creer', { sens: 'sortie', qte: 2, justificatif: 'ORD-12' }, { role: 'pharmacien' }), op('F1', 2, 'mouvements', 'm2', 'creer', { sens: 'sortie', qte: 1 }, { role: 'pharmacien' }),
  op('F2', 3, 'mouvements', 'm3', 'creer', { sens: 'entree', qte: 5 }, { role: 'stock' }), op('F2', 4, 'mouvements', 'm1', 'modifier', { qte: 99 }, { role: 'stock' }),
]);
ajouter('produits : concurrence marquée, décision de la personne habilitée', [
  op('F1', 1, 'produits', 'p1', 'creer', { prix: 100 }, { role: 'stock' }), op('F1', 5, 'produits', 'p1', 'modifier', { prix: 110 }, { role: 'stock', vu: { prix: 1 } }),
  op('F2', 6, 'produits', 'p1', 'modifier', { prix: 120 }, { role: 'stock', vu: { prix: 1 } }), op('mere', 8, 'produits', 'p1', 'trancher', { prix: 110 }, { role: 'mere' }),
]);

ajouter('admissions : deux admissions actives sur un même lit marquées sur les deux, la sortie de l\'une lève la marque', [
  op('F1', 1, 'admissions', 'a1', 'creer', { lit: 'Ch2-L1', statut: 'en_cours' }, { role: 'reception' }), op('F2', 1, 'admissions', 'a2', 'creer', { lit: 'Ch2-L1', statut: 'en_cours' }, { role: 'infirmier' }),
  op('F1', 2, 'admissions', 'a3', 'creer', { lit: 'Ch2-L2', statut: 'en_cours' }, { role: 'reception' }),
]);
ajouter('admissions : le transfert de l\'une lève la marque', [
  op('F1', 1, 'admissions', 'a1', 'creer', { lit: 'Ch2-L1', statut: 'en_cours' }, { role: 'reception' }), op('F2', 1, 'admissions', 'a2', 'creer', { lit: 'Ch2-L1', statut: 'en_cours' }, { role: 'infirmier' }),
  op('F1', 5, 'admissions', 'a2', 'modifier', { lit: 'Ch2-L3' }, { role: 'reception', vu: { lit: 1 } }),
]);

/* cas engendrés (graine fixe) : mélange de familles, rôles valides ou non, hlc égaux entre appareils, doublons */
let s = 20261105;
const alea = (m) => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s % m; };
const choix = (l) => l[alea(l.length)];
const ROLES = ['stock', 'da', 'infirmier', 'reception', 'caissier', 'medecin', 'pharmacien', 'x', 'inconnu'];
/* 85 % des opérations portent un rôle HABILITÉ (sinon la suite ne testerait que des refus) ; le reste, un rôle quelconque. */
const roleDe = (collection, type) => { const c = DROITS_BANC[collection] || {}; const ok = c[type] || c['*'] || ROLES; return alea(100) < 85 ? choix(ok) : choix(ROLES); };
const APP = ['F1', 'F2', 'F3', 'mere'];
for (let k = 0; k < 60; k++) {
  const ops = [];
  const fiches = ['p1', 'p2']; const articles = ['a', 'b'];
  ops.push(op('mere', 1, 'stock', 'a', 'creer', { qte: 40 + alea(30) }, { role: 'stock' }), op('mere', 2, 'stock', 'b', 'creer', { qte: 10 + alea(30) }, { role: 'da' }),
    op('F1', 2, 'patients', 'p1', 'creer', { nom: 'N', tel: '0' }, { role: 'reception' }), op('F2', 2, 'patients', 'p2', 'creer', { nom: 'M', tel: '0' }, { role: 'infirmier' }),
    op('F3', 2, 'factures', 'f1', 'creer', { total: 10 }, { role: 'caissier' }), op('F3', 2, 'factures', 'f2', 'creer', { total: 20 }, { role: 'da' }));
  let hlc = 3;
  const total = 10 + alea(14);
  for (let i = 0; i < total; i++) {
    hlc += alea(3);
    const a = choix(APP); const dernierVu = Math.max(0, hlc - 1 - alea(6));
    const t = alea(9);
    if (t === 0) ops.push(op(a, hlc, 'stock', choix(articles), 'bail', { appareil: choix(APP), qte: 1 + alea(15) }, { role: roleDe('stock', 'bail') }));
    else if (t === 1) ops.push(op(a, hlc, 'stock', choix(articles), 'sortie', { qte: 1 + alea(12) }, { role: roleDe('stock', 'sortie') }));
    else if (t === 2) ops.push(op(a, hlc, 'stock', choix(articles), 'entree', { qte: 1 + alea(8) }, { role: roleDe('stock', 'entree') }));
    else if (t === 3) ops.push(op(a, hlc, 'patients', choix(fiches), 'creer', { nom: 'N' + alea(5), tel: String(alea(9)) }, { role: roleDe('patients', 'creer') }));
    else if (t === 4) ops.push(op(a, hlc, 'patients', choix(fiches), 'modifier', { tel: String(alea(9)) }, { role: roleDe('patients', 'modifier'), vu: { tel: dernierVu } }));
    else if (t === 5) { const ty = choix(['soumettre', 'valider', 'rejeter']); ops.push(op(a, hlc, 'besoins', choix(['b1', 'b2']), ty, {}, { role: roleDe('besoins', ty) })); }
    else if (t === 6) ops.push(op(a, hlc, 'factures', choix(['f1', 'f2']), choix(['modifier', 'modifier', 'emettre', 'creer']), { total: 10 * (1 + alea(9)) }, { role: roleDe('factures', 'modifier'), vu: { total: dernierVu } }));
    else if (t === 7) { const ty = choix(['archiver', 'restaurer', 'trancher']); ops.push(op(a, hlc, 'patients', choix(fiches), ty, ty === 'trancher' ? { tel: String(alea(9)) } : {}, { role: roleDe('patients', ty) })); }
    else ops.push(op(a, hlc, 'constantes', 'c' + alea(3), choix(['creer', 'modifier']), { t: 36 + alea(5) }, { role: roleDe('constantes', 'creer') }));
    if (alea(7) === 0) ops.push(ops[ops.length - 1]); // doublon livré deux fois
  }
  ajouter(`engendré ${k + 1}`, ops);
}
const sortie = path.join(__dirname, '..', '..', 'domaine', 'test', 'vecteurs', 'pair.json');
fs.writeFileSync(sortie, JSON.stringify({ _doc: 'ENGENDRÉ par packages/sync/banc/vecteurs-pair.js : l\'état attendu est celui de banc/pair.js. Ne pas éditer.', droits: DROITS_BANC, cas }, null, 1) + '\n');
console.log(`  écrit : ${path.relative(process.cwd(), sortie)} · ${cas.length} cas · ${cas.reduce((a, c) => a + c.ops.length, 0)} opérations`);
