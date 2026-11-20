// Outil de test : lit sur l'entrée standard {env, cle} et écrit la charge déchiffrée par le MÊME script que le navigateur.
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const code = readFileSync(new URL('../../public/js/consultation.js', import.meta.url), 'utf8');
const ctx = { globalThis: null, TextEncoder, TextDecoder, atob, btoa, crypto: globalThis.crypto };
ctx.globalThis = ctx;
vm.runInNewContext(code, ctx);
const S = ctx.SighConsultation;
const entree = JSON.parse(readFileSync(0, 'utf8'));
try {
  if (entree.action === 'coffre') {
    const coffre = await S.chiffrerCle(entree.cle, entree.phrase);
    process.stdout.write(JSON.stringify({ coffre }));
  } else if (entree.action === 'fiches') {
    process.stdout.write(JSON.stringify({ fiches: S.fichesDe(entree.charges, entree.collection) }));
  } else if (entree.action === 'convergence') {
    // toutes les permutations de lecture (n <= 7) : le résultat doit être UN SEUL (convergence indépendante de l'ordre de lecture)
    const perms = (a) => a.length <= 1 ? [a] : a.flatMap((x, i) => perms([...a.slice(0, i), ...a.slice(i + 1)]).map((p) => [x, ...p]));
    const issues = new Set(perms(entree.charges).map((p) => JSON.stringify(S.fichesDe(p, entree.collection))));
    process.stdout.write(JSON.stringify({ distincts: issues.size, permutations: perms(entree.charges).length, fiches: [...issues].map((x) => JSON.parse(x))[0] }));
  } else if (entree.action === 'ouvrir') {
    process.stdout.write(JSON.stringify({ cle: await S.dechiffrerCle(entree.coffre, entree.phrase) }));
  } else {
    const cle = await S.importerCle(entree.cle);
    process.stdout.write(JSON.stringify({ charge: await S.dechiffrer(entree.env, cle) }));
  }
} catch (e) {
  process.stdout.write(JSON.stringify({ erreur: String(e && e.message || e) }));
}
