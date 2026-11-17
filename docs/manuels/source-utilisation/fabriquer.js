/* Fabrique le manuel d'utilisation : contenu.js ➔ manuel.html (+ style.css) ➔ PDF par Chromium (Playwright).
   Deux passes : la première mesure la page de chaque titre (pdftotext), la seconde écrit les numéros dans le sommaire.
   node fabriquer.js  ➔  docs/manuels/MANUEL-UTILISATION-SIGH-CNT.pdf */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const ICI = __dirname;
const SORTIE = path.resolve(ICI, '../MANUEL-UTILISATION-SIGH-CNT.pdf');
const TITRE = 'Manuel d’utilisation SIGH-CNT';
const DATE = '17 novembre 2026';
const CHAPITRES = require('./contenu.js');

function echapper(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function texteBrut(html) { return html.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim(); }

function assembler(pages) {
  const entrees = [];
  let corps = '';
  CHAPITRES.forEach((ch, i) => {
    const n = ch.annexe ? ch.annexe : String(i + 1 - CHAPITRES.slice(0, i).filter((c) => c.horsNumero).length);
    const num = ch.horsNumero ? '' : n;
    const idc = 'ch-' + (i + 1);
    entrees.push({ niveau: 1, id: idc, num, titre: ch.titre });
    let k = 0;
    const html = ch.html.replace(/<h2( class="[^"]*")?>([\s\S]*?)<\/h2>/g, (m, cl, t) => {
      k++; const id = idc + '-' + k; const nn = num ? num + '.' + k : '';
      entrees.push({ niveau: 2, id, num: nn, titre: texteBrut(t) });
      return `<h2 id="${id}"${cl || ''}>${nn ? '<span class="num">' + nn + '</span> ' : ''}${t}</h2>`;
    });
    corps += `<section class="chapitre${ch.classe ? ' ' + ch.classe : ''}"><h1 id="${idc}">${num ? '<span class="num-ch">' + (ch.annexe ? 'Annexe ' : 'Chapitre ') + num + '</span>' : ''}${echapper(ch.titre)}</h1>${ch.chapeau ? '<p class="chapeau">' + ch.chapeau + '</p>' : ''}${html}</section>`;
  });
  const sommaire = entrees.map((e) => `<li class="n${e.niveau}"><a href="#${e.id}"><span class="t">${e.num ? '<span class="sn">' + e.num + '</span>' : ''}${echapper(e.titre)}</span><span class="p">${pages && pages[e.id] ? pages[e.id] : ''}</span></a></li>`).join('');
  const couverture = `<section class="couverture">
    <img class="logo" src="../../../prototype_html/assets/img/logo.jpeg" alt="">
    <div class="clinique">CLINIQUE NASSIERA TOO SARL<br><span>BP 507 Natitingou, République du Bénin</span></div>
    <h1 class="titre-couv">Manuel d’utilisation</h1>
    <div class="sous-couv">SIGH-CNT, Système Intégré de Gestion Hospitalière</div>
    <div class="public">Pour les agents de la clinique : poste de travail, application mobile et relais web</div>
    <div class="devise">« Votre santé, notre raison de vivre »</div>
    <div class="edition">Édition du ${DATE} · Version de la maquette de référence : schéma 97</div>
  </section>`;
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>${TITRE}</title><link rel="stylesheet" href="style.css"></head><body>
  ${couverture}<section class="sommaire"><h1 class="titre-sommaire">Sommaire</h1><ol>${sommaire}</ol></section>${corps}</body></html>`;
}

/** Les captures restent en PNG dans les sources ; le PDF embarque une copie JPEG (qualité 84) pour rester léger. */
const JPG = path.join(require('os').tmpdir(), 'manuel-util-jpg');
function preparerJpeg() {
  fs.rmSync(JPG, { recursive: true, force: true }); fs.mkdirSync(JPG, { recursive: true });
  execFileSync('python3', ['-c', `import os,sys
from PIL import Image
s,d=sys.argv[1],sys.argv[2]
for f in os.listdir(s):
    if f.endswith('.png'): Image.open(os.path.join(s,f)).convert('RGB').save(os.path.join(d,f[:-4]+'.jpg'),quality=84,optimize=True)`, path.join(ICI, 'captures'), JPG]);
}

async function imprimer(html, pdf) {
  const fichier = path.join(ICI, 'manuel.html');
  fs.writeFileSync(fichier, html);
  const fichierPdf = path.join(JPG, 'manuel-pdf.html');
  fs.writeFileSync(fichierPdf, html.replace(/src="captures\/([^"]+)\.png"/g, (m, n) => 'src="' + path.join(JPG, n + '.jpg') + '"')
    .replace('href="style.css"', 'href="' + path.join(ICI, 'style.css') + '"').replace('src="../../../prototype_html', 'src="' + path.resolve(ICI, '../../../prototype_html')));
  const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const page = await browser.newPage();
  await page.goto('file://' + fichierPdf, { waitUntil: 'load' });
  await page.pdf({ path: pdf, format: 'A4', printBackground: true, displayHeaderFooter: true,
    margin: { top: '18mm', bottom: '18mm', left: '17mm', right: '17mm' },
    headerTemplate: '<span></span>',
    footerTemplate: `<div style="width:100%;font:9px Arial,'Liberation Sans',sans-serif;color:#64748b;padding:0 17mm;display:flex;justify-content:space-between"><span>${TITRE} · Clinique NASSIERA TOO</span><span>${DATE}</span><span>Page <span class="pageNumber"></span> / <span class="totalPages"></span></span></div>` });
  await browser.close();
}

/** Page de chaque titre : on cherche son texte (numéro compris) dans le texte de chaque page, après le sommaire. */
function mesurerPages(pdf, html) {
  const nb = Number(/Pages:\s+(\d+)/.exec(execFileSync('pdfinfo', [pdf]).toString())[1]);
  const textes = [];
  for (let p = 1; p <= nb; p++) textes.push(execFileSync('pdftotext', ['-f', String(p), '-l', String(p), '-layout', pdf, '-']).toString().replace(/\s+/g, ' ').toLowerCase());
  const debutCorps = textes.findIndex((t, i) => i > 1 && /chapitre 1 /.test(t));
  const pages = {};
  const re = /<h([12]) id="([^"]+)"[^>]*>([\s\S]*?)<\/h\1>/g; let m; let depuis = Math.max(debutCorps, 0);
  while ((m = re.exec(html))) {
    const cle = texteBrut(m[3].replace(/<span class="num-ch">[\s\S]*?<\/span>/, '')).replace(/\s+/g, ' ').toLowerCase().slice(0, 40);
    for (let p = depuis; p < nb; p++) { if (textes[p].includes(cle)) { pages[m[2]] = p + 1; depuis = p; break; } }
  }
  return { pages, nb };
}

(async () => {
  const brouillon = path.join(require('os').tmpdir(), 'manuel-util-brouillon.pdf');
  preparerJpeg();
  let html = assembler(null);
  await imprimer(html, brouillon);
  const { pages } = mesurerPages(brouillon, html);
  html = assembler(pages);
  await imprimer(html, SORTIE);
  fs.unlinkSync(brouillon);
  fs.rmSync(JPG, { recursive: true, force: true });
  const { nb } = mesurerPages(SORTIE, html);
  const ids = [...html.matchAll(/<h[12] id="([^"]+)"/g)].map((x) => x[1]);
  const manquants = ids.filter((i) => !pages[i]);
  console.log('PDF : ' + SORTIE + ' (' + nb + ' pages ; titres non repérés au sommaire : ' + manquants + ')');
})();
