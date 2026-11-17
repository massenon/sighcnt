/* Catalogue des écrans : TOUS les écrans du manifeste de navigation (packages/referentiels/data/manifeste.json, engendré par prototype_html/build/extraire.js),
 * rangés par domaine puis par module, avec le libellé exact du ruban, l'identifiant et les rôles qui l'ouvrent d'origine. Engendré, jamais écrit à la main. */
'use strict';
const fs = require('fs');
const path = require('path');
const RACINE = path.resolve(__dirname, '../../..');
const manifeste = JSON.parse(fs.readFileSync(path.join(RACINE, 'packages/referentiels/data/manifeste.json'), 'utf8'));
const rbac = JSON.parse(fs.readFileSync(path.join(RACINE, 'packages/rbac/data/rbac.json'), 'utf8'));
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const roles = Object.fromEntries(rbac.roles.map((r) => [r.id, r]));
const actifs = rbac.roles.filter((r) => !r.archive);
const ecrans = Object.fromEntries(manifeste.ecrans.map((e) => [e.id, e]));

function ouvertA(e) {
  if (e.roles === '*' || e.roles === 'ALL') return 'Tous les rôles';
  const ids = e.roles.filter((id) => roles[id] && !roles[id].archive);
  if (!ids.length) return 'Aucun rôle d’origine';
  if (actifs.every((r) => ids.includes(r.id))) return 'Tous les rôles';
  if (ids.length >= actifs.length - 4) return 'Tous sauf : ' + actifs.filter((r) => !ids.includes(r.id)).map((r) => r.short).join(', ');
  return ids.map((id) => roles[id].short).join(', ');
}
function remarques(e) {
  const r = [];
  if (e.hub) r.push('page d’accueil du module');
  if (e.standalone) r.push('écran de saisie' + (e.servant && ecrans[e.servant] ? ', ouvert depuis « ' + esc(ecrans[e.servant].label) + ' »' : ''));
  else if (e.servant && ecrans[e.servant]) r.push('sert « ' + esc(ecrans[e.servant].label) + ' »');
  if (e.universel) r.push('ouvert à tout agent connecté');
  if (e.parGeste) r.push('ouvert par le geste réservé <code>' + e.parGeste + '</code>');
  if (e.sousReglage) r.push('offert si le réglage <code>' + e.sousReglage + '</code> l’affiche');
  if (e.jeuImport) r.push('jeu d’import <code>' + esc(e.jeuImport) + '</code>');
  return r.join(' ; ');
}
function html() {
  let out = '';
  let nb = 0;
  for (const d of manifeste.domaines) {
    const duDomaine = manifeste.ecrans.filter((e) => e.domaine === d.nom);
    if (!duDomaine.length) continue;
    out += '<h3 class="dom">' + esc(d.nom) + ' (' + duDomaine.length + ' écrans)</h3>\n';
    const ordre = [];
    for (const e of duDomaine) { const k = e.module + '|' + e.moduleLabel; if (!ordre.includes(k)) ordre.push(k); }
    for (const k of ordre) {
      const [code, lib] = k.split('|');
      const lignes = duDomaine.filter((e) => e.module + '|' + e.moduleLabel === k);
      out += '<table class="tab ecrans"><tr><th colspan="3">' + esc(lib) + ' <span class="code">' + esc(code) + '</span></th></tr>\n<tr class="sous"><td style="width:36%">Écran (libellé du ruban)</td><td style="width:22%">Ouvert d’origine à</td><td>Identifiant et remarques</td></tr>\n';
      for (const e of lignes) {
        nb++;
        const rem = remarques(e);
        out += '<tr><td><strong>' + esc(e.label) + '</strong></td><td>' + esc(ouvertA(e)) + '</td><td><code>' + e.id + '</code>' + (rem ? '<br><span class="note">' + rem + '</span>' : '') + '</td></tr>\n';
      }
      out += '</table>\n';
    }
  }
  return { html: out, nombre: nb, ecrans: manifeste.ecrans, total: manifeste.ecrans.length };
}
module.exports = { html, manifeste };
if (require.main === module) { const r = html(); console.log(r.nombre + ' écrans rendus sur ' + r.total + ' du manifeste.'); }
