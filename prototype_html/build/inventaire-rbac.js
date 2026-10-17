/* INVENTAIRE DES ÉCRANS PAR RÔLE — pièce de validation.
 *
 * « FAIRE L'INVENTAIRE DES PAGES, menu du sidebar, sous menu du mega menu de
 * chaque role DOIT AVOIR REELLEMENT pour VALIDATION. »
 *
 * Ce script produit ce que CHAQUE rôle voit RÉELLEMENT dans le méga-menu,
 * domaine par domaine et module par module, avec pour chaque écran le droit
 * effectif — lecture, écriture, annulation. Il n'interroge pas le manifeste en
 * théorie : il ouvre le navigateur, charge le magasin avec ses surcharges
 * enregistrées, et appelle `N.tree(role)`, exactement ce que le ruban appelle.
 *
 * C'est la différence entre « ce que le manifeste déclare » et « ce que l'agent
 * voit » — et c'est la seconde qui compte.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const BANC = require('./_banc');
const http = require('http');
const puppeteer = require('puppeteer');
const ROOT = path.resolve(__dirname, '..');
const PORT = 8171;
function findBrowser() {
  const c = [process.env.CHROME_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe'].filter(Boolean);
  for (const x of c) if (fs.existsSync(x)) return x;
  return null;
}
const MIME = { '.php': 'text/html; charset=utf-8', '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.woff2': 'font/woff2',
  '.jpeg': 'image/jpeg', '.jpg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon' };
function serve() {
  return new Promise((r) => {
    const s = http.createServer((req, res) => {
      if (req.url.indexOf('/api/') === 0) { BANC.relayer(req, res); return; }
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.php';
      const f = path.join(ROOT, rel);
      if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
        res.writeHead(404); res.end('404'); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
      fs.createReadStream(f).pipe(res);
    });
    s.listen(PORT, () => r(s));
  });
}

(async () => {
  const server = await serve();
  /* Le sondage se fait CONTRE LA BASE : un écran vide ne promet rien, et
     l'audit conclurait à zéro promesse sans avoir rien éprouvé. */
  const php = await BANC.demarrerPhp(ROOT);
  if (!php.php) {
    console.error('\n  ÉCHEC — ' + php.raison + '\n');
    process.exit(1);
  }
  const vidage = await BANC.banc('reinitialiser');
  if (vidage.erreur) {
    console.error('\n  ÉCHEC — base du banc : ' + (vidage.detail || vidage.erreur) + '\n');
    try { php.php.kill(); } catch (e) { /* déjà mort */ }
    process.exit(1);
  }

  const browser = await puppeteer.launch({ executablePath: findBrowser(), headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] });
  const page = await browser.newPage();
  await BANC.poserSession(page);
  page.setDefaultNavigationTimeout(180000);
  page.setDefaultTimeout(180000);
  await page.goto('http://127.0.0.1:' + PORT + '/pages/dash-admin.php', { waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => {
        const c = document.getElementById('page-content');
        return !!(window.SIGH && window.SIGH.store && c && c.children.length > 0);
      }, { timeout: 180000 }).catch(() => null);
  await new Promise((r) => setTimeout(r, 800));

  const data = await page.evaluate(() => {
    const N = window.SIGH.nav;
    const roles = Object.keys(N.ROLES)
      .filter((r) => !N.ROLES[r].archive)
      .map((r) => ({ id: r, label: N.ROLES[r].label, home: N.ROLES[r].home }));

    const archives = Object.keys(N.ROLES).filter((r) => N.ROLES[r].archive)
      .map((r) => ({ id: r, label: N.ROLES[r].label }));

    /* Les écrans fermés par activité, pour les distinguer d'une restriction
       de droits : ce n'est pas la même chose et il ne faut pas les confondre. */
    const fermes = [];
    try {
      window.SIGH.store.collection('modulesActifs').all().forEach((m) => {
        if (m.actif === false) (m.ecrans || []).forEach((id) => fermes.push({ id, motif: m.libelle }));
      });
    } catch (e) { /* rien */ }

    const inventaire = roles.map((r) => {
      const arbre = N.tree(r.id);
      const domaines = arbre.map((d) => ({
        domaine: d.domain,
        modules: d.modules.map((m) => ({
          code: m.code, label: m.label,
          ecrans: m.items.map((it) => {
            const dr = N.droitsEcran(r.id, it.id, m.code);
            return {
              id: it.id, label: it.label,
              voir: !!dr.voir, editer: !!dr.editer, annuler: !!dr.annuler,
            };
          }),
        })),
      }));
      const total = domaines.reduce((n, d) => n + d.modules.reduce((k, m) => k + m.ecrans.length, 0), 0);
      const ecrivables = domaines.reduce((n, d) => n + d.modules.reduce(
        (k, m) => k + m.ecrans.filter((e) => e.editer).length, 0), 0);
      return { role: r, domaines, total, ecrivables };
    });

    return { inventaire, archives, fermes };
  });

  /* --- Restitution ------------------------------------------------------- */
  const L = [];
  L.push('# Inventaire des accès par rôle — SIGH-CNT');
  L.push('');
  L.push('Ce que **chaque rôle voit réellement** dans le méga-menu, produit en');
  L.push('interrogeant `N.tree(role)` — la fonction même qu\'appelle le ruban — avec le');
  L.push('magasin chargé et ses surcharges enregistrées. Ce n\'est pas ce que le');
  L.push('manifeste déclare : c\'est ce que l\'agent a sous les yeux.');
  L.push('');
  L.push('| Symbole | Signification |');
  L.push('|---|---|');
  L.push('| L | lecture seule |');
  L.push('| **E** | écriture |');
  L.push('| **EA** | écriture et annulation |');
  L.push('');

  L.push('## Synthèse');
  L.push('');
  L.push('| Rôle | Écrans visibles | Dont modifiables | Accueil |');
  L.push('|---|---:|---:|---|');
  data.inventaire.forEach((i) => {
    L.push('| ' + i.role.label + ' | ' + i.total + ' | ' + i.ecrivables + ' | `' + i.role.home + '` |');
  });
  L.push('');

  if (data.archives.length) {
    L.push('**Rôles archivés** (aucune session possible, droits transférés) : '
      + data.archives.map((a) => a.label).join(', ') + '.');
    L.push('');
  }
  if (data.fermes.length) {
    L.push('**Écrans fermés par activité** (pour tous les rôles, administrateur compris) : '
      + data.fermes.map((f) => '`' + f.id + '` — ' + f.motif).join(' · ') + '.');
    L.push('');
  }

  L.push('---');
  L.push('');
  data.inventaire.forEach((i) => {
    L.push('## ' + i.role.label + '  <small>`' + i.role.id + '`</small>');
    L.push('');
    L.push(i.total + ' écran(s) visible(s), dont ' + i.ecrivables + ' modifiable(s).');
    L.push('');
    if (!i.domaines.length) {
      L.push('*Aucun écran accessible.*');
      L.push('');
      return;
    }
    i.domaines.forEach((d) => {
      L.push('### ' + d.domaine);
      L.push('');
      d.modules.forEach((m) => {
        const cells = m.ecrans.map((e) => {
          const marque = e.annuler ? '**EA**' : (e.editer ? '**E**' : 'L');
          return e.label + ' ' + marque;
        });
        L.push('- **' + m.code + ' — ' + m.label + '** : ' + cells.join(' · '));
      });
      L.push('');
    });
  });

  const sortie = path.join(ROOT, '..', 'newdocs', 'INVENTAIRE-RBAC.md');
  fs.writeFileSync(sortie, L.join('\n'), 'utf8');
  console.log('Inventaire écrit : ' + sortie);
  console.log('');
  console.log('Rôle'.padEnd(34) + 'écrans'.padStart(8) + 'modifiables'.padStart(13));
  console.log('─'.repeat(56));
  data.inventaire.forEach((i) => {
    console.log(i.role.label.padEnd(34) + String(i.total).padStart(8) + String(i.ecrivables).padStart(13));
  });
  console.log('─'.repeat(56));
  console.log('Rôles archivés : ' + (data.archives.map((a) => a.label).join(', ') || 'aucun'));
  console.log('Écrans fermés  : ' + (data.fermes.map((f) => f.id).join(', ') || 'aucun'));

  await browser.close();
  server.close();
  try { php.php.kill(); } catch (e) { /* déjà mort */ }
})();
