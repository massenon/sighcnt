/* Fabrique le PDF du manuel administrateur depuis manuel-administrateur.html.
 * Usage : node docs/manuels/source-administrateur/fabriquer.js
 * Deux passes : la première pose des repères invisibles sous chaque titre et lit, par pdftotext, la page où chacun tombe ;
 * la seconde écrit ces numéros dans le sommaire (liens cliquables) et produit le PDF définitif.
 * Prérequis : Playwright (Chromium), pdftotext et pdfinfo (poppler) ; pypdf (facultatif) retire le pied de page de la couverture. */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require('/opt/node-tools/node_modules/playwright'); }

const ICI = __dirname;
const SOURCE = path.join(ICI, 'manuel-administrateur.html');
const SORTIE = path.join(ICI, '..', 'MANUEL-ADMINISTRATEUR-SIGH-CNT.pdf');
const DATE = '16/11/2026';
const CHROME = process.env.CHROME_PATH || (fs.existsSync('/opt/pw-browsers/chromium-1194/chrome-linux/chrome') ? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' : undefined);

const pied = `<div style="width:100%;font-family:Arial,'Liberation Sans',sans-serif;font-size:8.5pt;color:#475569;padding:0 17mm;display:flex;justify-content:space-between;">
  <span>Manuel administrateur SIGH-CNT · ${DATE}</span><span>Page <span class="pageNumber"></span> / <span class="totalPages"></span></span></div>`;

async function construireSommaire(page, numeros) {
  await page.evaluate((numeros) => {
    const toc = document.getElementById('toc');
    toc.innerHTML = '';
    let courant = null;
    for (const h of document.querySelectorAll('h1[id], h2[id]')) {
      if (h.id === 'sommaire') continue;
      const li = document.createElement('li');
      li.className = h.tagName === 'H1' ? 'n1' : 'n2';
      const a = document.createElement('a');
      a.href = '#' + h.id;
      a.innerHTML = '<span class="tt"></span><span class="pts"></span><span class="pn"></span>';
      a.querySelector('.tt').textContent = h.textContent.trim();
      a.querySelector('.pn').textContent = (numeros && numeros[h.id]) || '';
      li.appendChild(a);
      toc.appendChild(li);
      courant = li;
    }
  }, numeros);
}

async function imprimer(page, fichier, extra = {}) {
  await page.pdf({ ...extra, path: fichier, format: 'A4', printBackground: true, displayHeaderFooter: true, headerTemplate: '<span></span>', footerTemplate: pied,
    margin: { top: '17mm', bottom: '19mm', left: '17mm', right: '17mm' }, preferCSSPageSize: true });
}

(async () => {
  const navigateur = await playwright.chromium.launch({ executablePath: CHROME, args: ['--no-sandbox'] });
  const page = await navigateur.newPage();
  await page.goto('file://' + SOURCE, { waitUntil: 'networkidle' });

  /* Un titre ne reste jamais seul en bas de page : titre, au plus deux paragraphes courts et la figure qui suit restent ensemble. */
  await page.evaluate(() => {
    for (const h of [...document.querySelectorAll('h2, h3')]) {
      const groupe = [h];
      let n = h.nextElementSibling;
      while (n && groupe.length < 3 && n.tagName === 'P') { groupe.push(n); n = n.nextElementSibling; }
      if (!n || n.tagName !== 'FIGURE') continue;
      groupe.push(n);
      const d = document.createElement('div');
      d.style.breakInside = 'avoid';
      h.parentNode.insertBefore(d, h);
      groupe.forEach((e) => d.appendChild(e));
    }
  });

  /* Passe 1 : repères invisibles (positionnés en absolu, ils ne déplacent rien). */
  await construireSommaire(page, null);
  await page.evaluate(() => {
    for (const h of document.querySelectorAll('h1[id], h2[id]')) {
      h.style.position = 'relative';
      const m = document.createElement('span');
      m.className = '__repere';
      m.textContent = 'QQREP' + h.id.replace(/-/g, 'X') + 'QQ';
      Object.assign(m.style, { position: 'absolute', left: '0', top: '0', fontSize: '2px', color: '#ffffff' });
      h.appendChild(m);
    }
  });
  const essai = path.join(os.tmpdir(), 'manuel-admin-passe1-' + process.pid + '.pdf');
  await imprimer(page, essai);
  const numeros = {};
  const texte = execFileSync('pdftotext', ['-layout', essai, '-'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  texte.split('\f').forEach((pg, i) => {
    for (const m of pg.matchAll(/QQREP([A-Za-z0-9]+)QQ/g)) {
      const id = m[1].replace(/X/g, '-');
      if (!numeros[id]) numeros[id] = String(i + 1);
    }
  });
  fs.unlinkSync(essai);

  /* Passe 2 : sommaire numéroté, repères retirés. */
  await page.evaluate(() => document.querySelectorAll('.__repere').forEach((e) => e.remove()));
  await construireSommaire(page, numeros);
  /* Le manuel complet (sommaire cliquable), puis la couverture nue posée sur la page 1 pour en retirer le pied de page (pypdf, si présent). */
  const complet = path.join(os.tmpdir(), 'manuel-admin-complet-' + process.pid + '.pdf');
  const couv = path.join(os.tmpdir(), 'manuel-admin-couv-' + process.pid + '.pdf');
  await imprimer(page, complet);
  await page.pdf({ path: couv, format: 'A4', printBackground: true, pageRanges: '1', preferCSSPageSize: true });
  try {
    execFileSync('python3', [path.join(ICI, 'couverture.py'), complet, couv, SORTIE], { stdio: 'pipe' });
  } catch (e) {
    console.log('pypdf absent : la couverture garde son pied de page.');
    fs.copyFileSync(complet, SORTIE);
  }
  fs.unlinkSync(complet); fs.unlinkSync(couv);
  await navigateur.close();
  const pages = execFileSync('pdfinfo', [SORTIE], { encoding: 'utf8' }).match(/Pages:\s+(\d+)/)[1];
  console.log('PDF : ' + SORTIE + ' (' + pages + ' pages, ' + Math.round(fs.statSync(SORTIE).size / 1024) + ' Ko) ; titres repérés : ' + Object.keys(numeros).length);
})();
