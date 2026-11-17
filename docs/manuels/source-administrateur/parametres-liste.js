/* Registre des paramètres de clinique : engendré depuis `parametres.json` (sortie de `exporter-parametres.dart`, qui lit le registre du domaine). */
'use strict';
const fs = require('fs');
const path = require('path');
const d = JSON.parse(fs.readFileSync(path.join(__dirname, 'parametres.json'), 'utf8'));
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
function valeur(p) {
  if (p.type === 'booleen') return p.defaut ? 'Oui' : 'Non';
  if (p.defaut === '' || p.defaut === null) return 'Vide (à régler)';
  if (p.defaut === '(valeur JSON)') return 'Valeur structurée, voir l’écran';
  return String(p.defaut).length > 60 ? String(p.defaut).slice(0, 57) + '…' : String(p.defaut);
}
function html() {
  let out = '';
  const familles = [...new Set(d.params.map((p) => p.famille))];
  for (const f of familles) {
    const lot = d.params.filter((p) => p.famille === f);
    out += '<h3>' + esc(d.familles[f] || f) + ' (' + lot.length + ')</h3>\n<table class="tab param"><tr><th style="width:30%">Paramètre</th><th style="width:26%">Clé</th><th style="width:20%">Défaut semé</th><th>Ce qu’il règle</th></tr>\n';
    for (const p of lot) out += '<tr><td><strong>' + esc(p.libelle || p.cle) + '</strong></td><td><code>' + esc(p.cle) + '</code></td><td>' + esc(valeur(p)) + '</td><td>' + esc(p.aide || '') + '</td></tr>\n';
    out += '</table>\n';
  }
  return { html: out, nombre: d.params.length };
}
module.exports = { html };
if (require.main === module) console.log(html().nombre + ' paramètres.');
