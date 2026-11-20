'use strict';
/* L'ORDRE D'UNE VERSION DE FICHE DANS LA COPIE CONSULTABLE : exécutable de référence de packages/sync_dart/lib/src/ordre_copie.dart.
   ordre = [nOps, hlc, appareil, idOp] : le nombre d'opérations connues de la fiche (qui sait plus est plus récent), puis la dernière opération de l'ordre total de la
   règle de fusion (hlc, appareil, id). Le seq de la mère est informatif (le comparer mêlerait deux ordres et casserait la transitivité). Sans ordre = le plus ancien. */
const { comparer } = require('./pair');

const cleDe = (o) => `${o.collection}/${o.fiche}`;

/* ordres [nOps, hlc, appareil, id] de chaque fiche, depuis TOUTES les opérations connues (doublons d'id tolérés). */
function ordresDesFiches(ops) {
  const parFiche = new Map();
  for (const o of ops) {
    const k = cleDe(o);
    if (!parFiche.has(k)) parFiche.set(k, new Map());
    parFiche.get(k).set(o.id, o);
  }
  const out = {};
  for (const [k, m] of parFiche) {
    const l = [...m.values()].sort(comparer);
    const d = l[l.length - 1];
    let seq = null; for (const o of l) if (o.seq != null && (seq == null || o.seq > seq)) seq = o.seq;
    out[k] = { ordre: [l.length, d.hlc, d.appareil, d.id], seq };
  }
  return out;
}

/* la charge de copie d'une fiche : contenu + ordre (+ seq informatif). */
function chargeCopie(cle, fiche, ordres) {
  const i = cle.indexOf('/'); const o = ordres[cle];
  return { collection: cle.slice(0, i), fiche: cle.slice(i + 1), data: fiche.data, archive: fiche.archive === true, ...(o ? { ordre: o.ordre } : {}), ...(o && o.seq != null ? { seq: o.seq } : {}) };
}

/* ce qui décide de redéposer : le contenu seul. */
const contenu = (c) => JSON.stringify({ collection: c.collection, fiche: c.fiche, data: c.data, archive: c.archive });

/* compare deux ordres ; null = le plus ancien. */
function comparerOrdre(a, b) {
  if (!a && !b) return 0; if (!a) return -1; if (!b) return 1;
  for (let i = 0; i < 4; i++) { if (a[i] < b[i]) return -1; if (a[i] > b[i]) return 1; }
  return 0;
}
module.exports = { ordresDesFiches, chargeCopie, contenu, comparerOrdre };
