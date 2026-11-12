/* =============================================================================
 * DES FICHIERS DE TEST FABRIQUÉS PAR CHROME (lot DOCS-1)
 * -----------------------------------------------------------------------------
 * Aucun binaire n'est versionné : les scénarios de dépôt fabriquent leurs scans au moment de jouer, avec le navigateur du banc.
 *   pdfTexte(variante)  un PDF qui porte une COUCHE TEXTE (rendu de la page par Chrome) ;
 *   pdfPages(v, n)      un PDF de n pages, un mot unique par page ;
 *   pdfScan(variante)   un PDF qui ne contient qu'une IMAGE (aucune couche texte : un scan) ;
 *   image(format, v)    un PNG, JPEG ou WEBP de 600 x 400 (trame non uniforme, donc de quoi peser) ;
 *   octets(n)           un faux fichier quelconque (refus de format).
 * `variante` change le contenu, donc l'empreinte : deux appels différents ne donnent jamais le même fichier.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');

async function fabriquer(browser, dossier) {
  fs.mkdirSync(dossier, { recursive: true });
  const page = await browser.newPage();
  const ecrire = (nom, tampon) => { const f = path.join(dossier, nom); fs.writeFileSync(f, tampon); return f; };

  async function image(format, variante) {
    const mime = { png: 'image/png', jpeg: 'image/jpeg', webp: 'image/webp' }[format];
    const b64 = await page.evaluate(async (mime, v) => {
      const c = document.createElement('canvas'); c.width = 600; c.height = 400;
      const x = c.getContext('2d');
      x.fillStyle = '#fff'; x.fillRect(0, 0, 600, 400);
      for (let i = 0; i < 400; i++) { x.fillStyle = 'hsl(' + ((i * 37 + v * 53) % 360) + ',60%,50%)'; x.fillRect((i * 97 + v * 31) % 560, (i * 61 + v * 17) % 360, 40, 30); }
      x.fillStyle = '#000'; x.font = '28px sans-serif'; x.fillText('Scan de test ' + v, 30, 200);
      return c.toDataURL(mime, 0.92).split(',')[1];
    }, mime, variante || 1);
    return ecrire('scan-' + format + '-' + (variante || 1) + '.' + (format === 'jpeg' ? 'jpg' : format), Buffer.from(b64, 'base64'));
  }

  async function pdf(html, nom) {
    await page.setContent('<!doctype html><html><head><meta charset="utf-8"></head><body style="font-family:sans-serif;font-size:14px">' + html + '</body></html>');
    const tampon = await page.pdf({ format: 'A4', printBackground: true });
    return ecrire(nom, Buffer.from(tampon));
  }

  return {
    image,
    pdfTexte: (variante, phrase) => pdf('<h1>Compte rendu numérisé ' + (variante || 1) + '</h1><p>' + (phrase || 'Le patient présente une hyperglycémie majeure, amoxicilline prescrite, aucune allergie connue.') + '</p><p>Mot unique du corps : zebraforte' + (variante || 1) + '</p>', 'texte-' + (variante || 1) + '.pdf'),
    /** Un PDF de `n` pages, chacune portant son mot unique (« page<k>mot<variante> ») : le texte de CHAQUE page doit s'indexer. */
    pdfPages: (variante, n) => pdf(Array.from({ length: n }, (_, k) => '<div style="page-break-after:always"><h1>Page ' + (k + 1) + '</h1><p>Mot propre à la page : page' + (k + 1) + 'mot' + variante + '</p></div>').join(''), 'pages-' + variante + '.pdf'),
    async pdfScan(variante) {
      const png = fs.readFileSync(await image('png', 100 + (variante || 1))).toString('base64');
      return pdf('<img src="data:image/png;base64,' + png + '" style="width:600px">', 'scan-' + (variante || 1) + '.pdf');
    },
    octets: (n, nom) => ecrire(nom || 'faux.exe', Buffer.alloc(n || 2048, 7)),
    fermer: () => page.close(),
  };
}
module.exports = { fabriquer };
