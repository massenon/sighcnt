/* Captures annotées du manuel administrateur.
 * Maquette : `node serveur-maquette.js` (PHP 8327, HTTP 8328, base jetable à soi). Relais : copie locale de apps/web lancée avec APP_BASE_PATH sur CET arbre (SQLite à soi, compte
 * superadmin de démonstration), port PORT_RELAIS. JETON est lu de api/auth.php au lancement. Ordre : MAQUETTE d'abord (`node captures.js m-`), puis le relais (`node captures.js p-`),
 * le relais réutilisant le port de la maquette une fois celle-ci arrêtée. Les PNG bruts vont dans OUT, puis sont réduits par optimiser-captures.py (256 couleurs). */
const { chromium } = require('/opt/node-tools/node_modules/playwright');
const http = require('http');
const path = require('path');
const OUT = process.env.OUT || path.join(__dirname, 'captures-brutes');
const PORT_M = Number(process.env.PORT_MAQUETTE || 8328);
const PORT_R = Number(process.env.PORT_RELAIS || 8328);
const M = 'http://127.0.0.1:' + PORT_M + '/pages/';
const R = 'http://127.0.0.1:' + PORT_R + '/panneau/';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome';
const COURRIEL_RELAIS = process.env.COURRIEL_RELAIS || 'admin@demo.local';
const MDP_RELAIS = process.env.MDP_RELAIS; /* jamais écrit dans le dépôt : passé par l'environnement */
const seul = process.argv.slice(2);
function jeton() {
  return new Promise((res) => {
    const c = JSON.stringify({ action: 'connexion', identifiant: 'c.bassongui', motDePasse: 'demonstration', poste: 'manuel-adm' });
    const q = http.request({ host: '127.0.0.1', port: PORT_M, path: '/api/auth.php', method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(c) } },
      (r) => { let d = ''; r.on('data', (x) => { d += x; }); r.on('end', () => { try { res(JSON.parse(d).jeton); } catch (e) { res(null); } }); });
    q.on('error', () => res(null)); q.end(c);
  });
}

/* Cadre rouge numéroté autour d'un élément, posé en coordonnées de la page. */
async function cadre(p, loc, n, opts = {}) {
  const l = loc.first();
  await l.scrollIntoViewIfNeeded().catch(() => {});
  const bb = await l.boundingBox();
  if (!bb) throw new Error('élément introuvable pour le cadre ' + n);
  await p.evaluate(({ bb, n, pad }) => {
    const sx = window.scrollX, sy = window.scrollY;
    const d = document.createElement('div');
    d.className = '__annot';
    Object.assign(d.style, { position: 'absolute', left: (bb.x + sx - pad) + 'px', top: (bb.y + sy - pad) + 'px', width: (bb.width + 2 * pad) + 'px',
      height: (bb.height + 2 * pad) + 'px', border: '3px solid #E30613', borderRadius: '9px', boxShadow: '0 0 0 4px rgba(227,6,19,.22)', zIndex: 2147483646, pointerEvents: 'none' });
    if (n) {
      const b = document.createElement('div');
      b.textContent = n;
      Object.assign(b.style, { position: 'absolute', left: '-15px', top: '-15px', width: '26px', height: '26px', borderRadius: '50%', background: '#E30613', color: '#fff',
        font: '700 15px/26px Arial, sans-serif', textAlign: 'center', boxShadow: '0 1px 3px rgba(0,0,0,.35)' });
      d.appendChild(b);
    }
    document.body.appendChild(d);
  }, { bb, n, pad: opts.pad ?? 4 });
}

/* Remplace les noms de personnes par des noms de démonstration (aucun nom réel du personnel dans le manuel). */
async function anonymiser(p) {
  await p.evaluate(() => {
    const re = /(?:Dr\.? |Mme |M\. )?[A-ZÀ-ÖØ-Þ][A-ZÀ-ÖØ-Þ’'\-]+(?: [A-ZÀ-ÖØ-Þ][A-ZÀ-ÖØ-Þ’'\-]+)*(?: (?:[A-ZÀ-ÖØ-Þ]\.|[A-ZÀ-ÖØ-Þ][a-zà-öø-ÿ’'.\-]+))+/g;
    const garder = /^(NASSIERA|CLINIQUE|SIGH|CNT|MECEF|RCCM|IFU|TVA|AIB|CNSS|OK|PDF|CSV)/;
    const map = new Map(); let k = 0;
    const reDr = /Dr\.? [A-ZÀ-ÖØ-Þ][A-ZÀ-ÖØ-Þ’'\-]+(?: [A-ZÀ-ÖØ-Þ][A-ZÀ-ÖØ-Þ’'\-]+)*/g;
    const racines = [...document.querySelectorAll('main, [role=dialog], .modal, #modal-host')];
    for (const r of racines) {
      const w = document.createTreeWalker(r, NodeFilter.SHOW_TEXT);
      let t; while ((t = w.nextNode())) {
        if (reDr.test(t.nodeValue)) { reDr.lastIndex = 0; t.nodeValue = t.nodeValue.replace(reDr, 'Dr DÉMO'); }
        reDr.lastIndex = 0;
        const v = t.nodeValue;
        if (!re.test(v)) { re.lastIndex = 0; continue; }
        re.lastIndex = 0;
        t.nodeValue = v.replace(re, (m) => {
          if (garder.test(m)) return m;
          if (!map.has(m)) map.set(m, 'AGENT Démo ' + (++k));
          return map.get(m);
        });
      }
    }
  });
}

async function nettoyer(p) {
  await p.addStyleTag({ content: '#toast-host{display:none!important}' });
  await p.evaluate(() => {
    for (const e of document.querySelectorAll('main div, main p')) {
      const t = (e.innerText || '').trim();
      if (/^Prototype( de la cible)? ?:/.test(t) && e.getBoundingClientRect().height < 90) e.style.display = 'none';
    }
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let t;
    while ((t = w.nextNode())) if (t.nodeValue.includes('/tmp/claude-0')) t.nodeValue = t.nodeValue.replace(/\/tmp\/claude-0\/[^\s]*?manadmin\//g, 'api/');
  });
}

async function ouvrirMaquette(p, id) {
  await p.goto(M + id + '.php', { waitUntil: 'networkidle', timeout: 120000 });
  await p.waitForTimeout(1300);
  await p.keyboard.press('Escape');
  await p.mouse.move(720, 890);
  await p.waitForTimeout(300);
  await nettoyer(p);
}

/* Capture : clip vertical [y0, y0+h] sur toute la largeur, en coordonnées de la page. */
async function prendre(p, nom, { y0 = 92, h = 820, x0 = 0, w, sel } = {}) {
  w = w || p.viewportSize().width;
  await p.evaluate(() => window.scrollTo(0, 0)); await p.waitForTimeout(200);
  let clip = { x: x0, y: y0, width: w, height: h };
  if (sel) {
    const bb = await p.locator(sel).first().boundingBox();
    const sy = await p.evaluate(() => window.scrollY);
    clip = { x: Math.max(0, bb.x - 12), y: Math.max(0, bb.y + sy - 12), width: Math.min(1440, bb.width + 24), height: Math.min(h, bb.height + 24) };
  }
  await p.screenshot({ path: path.join(OUT, nom + '.png'), clip, fullPage: true });
  console.log('ok ' + nom);
}

const btn = (p, t) => p.locator('main button, [role=dialog] button').filter({ hasText: t });

const MAQ = {
  async 'ruban-systeme'(p) {
    await ouvrirMaquette(p, 'cfg-poste');
    await p.locator('header button, nav button, header a, nav a').filter({ hasText: /^\s*Système\s*$/ }).first().click();
    await p.waitForTimeout(500);
    await cadre(p, p.getByText('Ce poste (mode fileul / mère)', { exact: true }), 1);
    await cadre(p, p.locator('header button, nav button, header a, nav a').filter({ hasText: /^\s*Système\s*$/ }), null, { pad: 2 });
    await prendre(p, 'ruban-systeme', { y0: 0, h: 460 });
  },
  async 'cfg-poste'(p) {
    await ouvrirMaquette(p, 'cfg-poste');
    await cadre(p, btn(p, 'Activer le mode mère'), 1);
    await prendre(p, 'cfg-poste', { h: 760 });
  },
  async 'cfg-poste-modale'(p) {
    await ouvrirMaquette(p, 'cfg-poste');
    await btn(p, 'Activer le mode mère').first().click();
    await p.waitForTimeout(700);
    await prendre(p, 'cfg-poste-modale', { y0: 0, h: 900 });
  },
  async 'mere-mise-en-service'(p) {
    await ouvrirMaquette(p, 'mere-mise-en-service');
    await prendre(p, 'mere-mise-en-service', { h: 800 });
  },
  async 'mere-appareils'(p) {
    await ouvrirMaquette(p, 'mere-appareils');
    await anonymiser(p);
    await cadre(p, btn(p, 'Appairer un poste'), 1);
    await cadre(p, btn(p, 'Appairer un mobile'), 2);
    await cadre(p, btn(p, 'Révoquer'), 3);
    await prendre(p, 'mere-appareils', { h: 760 });
  },
  async 'mere-appareils-mobile'(p) {
    await ouvrirMaquette(p, 'mere-appareils');
    await btn(p, 'Appairer un mobile').first().click();
    await p.waitForTimeout(700);
    await anonymiser(p);
    await prendre(p, 'mere-appareils-mobile', { y0: 0, h: 900 });
  },
  async 'mere-supervision'(p) {
    await ouvrirMaquette(p, 'mere-supervision');
    await anonymiser(p);
    await cadre(p, btn(p, 'Sauvegarder maintenant'), 1);
    await prendre(p, 'mere-supervision', { h: 800 });
  },
  async 'mere-relais'(p) {
    await ouvrirMaquette(p, 'mere-relais');
    await cadre(p, btn(p, 'Tester la liaison'), 1);
    await cadre(p, btn(p, 'Faire tourner le secret de la mère'), 2);
    await prendre(p, 'mere-relais', { h: 760 });
  },
  async 'mere-cle-clinique'(p) {
    await ouvrirMaquette(p, 'mere-cle-clinique');
    await anonymiser(p);
    await cadre(p, btn(p, 'Imprimer la copie papier'), 1);
    await cadre(p, btn(p, 'Faire tourner la clé'), 2);
    await prendre(p, 'mere-cle-clinique', { h: 760 });
  },
  async 'mere-sauvegardes'(p) {
    await ouvrirMaquette(p, 'mere-sauvegardes');
    await cadre(p, btn(p, 'Sauvegarder maintenant'), 1);
    await cadre(p, btn(p, 'Vérifier la dernière'), 2);
    await cadre(p, btn(p, /^\s*Restaurer\s*$/), 3);
    await prendre(p, 'mere-sauvegardes', { h: 760 });
  },
  async 'm14-utilisateurs'(p) {
    await ouvrirMaquette(p, 'm14-utilisateurs');
    await anonymiser(p);
    await cadre(p, btn(p, /^\s*Nouveau\s*$/), 1);
    await prendre(p, 'm14-utilisateurs', { h: 640 });
  },
  async 'm14-utilisateurs-form'(p) {
    await ouvrirMaquette(p, 'm14-utilisateurs');
    await btn(p, /^\s*Nouveau\s*$/).first().click();
    await p.waitForTimeout(800);
    await anonymiser(p);
    await cadre(p, btn(p, /^\s*Créer\s*$/), 1);
    await prendre(p, 'm14-utilisateurs-form', { y0: 0, h: 900 });
  },
  async 'm14-roles'(p) {
    await ouvrirMaquette(p, 'm14-roles');
    await cadre(p, btn(p, 'Matrice des droits'), 1);
    await cadre(p, btn(p, 'Détail par rôle'), 2);
    await cadre(p, btn(p, 'Habilitations métier'), 3);
    await prendre(p, 'm14-roles', { h: 620 });
  },
  async 'm14-roles-detail'(p) {
    await ouvrirMaquette(p, 'm14-roles');
    await btn(p, 'Détail par rôle').first().click();
    await p.waitForTimeout(800);
    await nettoyer(p);
    await anonymiser(p);
    await prendre(p, 'm14-roles-detail', { h: 900 });
  },
  async 'm14-roles-gestes'(p) {
    await ouvrirMaquette(p, 'm14-roles');
    const b = p.locator('main [title="Régler les gestes réservés de ce rôle"], main [aria-label="Régler les gestes réservés de ce rôle"]').first();
    await cadre(p, b, 1, { pad: 3 });
    await prendre(p, 'm14-roles-ligne', { h: 520 });
    await p.evaluate(() => document.querySelectorAll('.__annot').forEach((e) => e.remove()));
    await b.click();
    await p.waitForTimeout(900);
    await nettoyer(p);
    await prendre(p, 'm14-roles-gestes', { y0: 0, h: 900 });
  },
  async 'm14-roles-droits'(p) {
    await ouvrirMaquette(p, 'm14-roles');
    await btn(p, 'Détail par rôle').first().click();
    await p.waitForTimeout(700);
    await btn(p, /^\s*Droits\s*$/).first().click();
    await p.waitForTimeout(900);
    await nettoyer(p);
    await anonymiser(p);
    await prendre(p, 'm14-roles-droits', { y0: 0, h: 900 });
  },
  async 'cfg-branding'(p) {
    await ouvrirMaquette(p, 'cfg-branding');
    await cadre(p, btn(p, /^\s*Enregistrer\s*$/), 1);
    await cadre(p, btn(p, 'Prévisualiser un état'), 2);
    await prendre(p, 'cfg-branding', { h: 1500 });
  },
  async 'cfg-fiscalite'(p) {
    await ouvrirMaquette(p, 'cfg-fiscalite');
    await cadre(p, btn(p, /^\s*Enregistrer\s*$/), 1);
    await cadre(p, btn(p, 'Valider l’identité légale'), 2);
    await prendre(p, 'cfg-fiscalite', { h: 1150 });
  },
  async 'cfg-regles'(p) {
    await ouvrirMaquette(p, 'cfg-regles');
    await cadre(p, btn(p, /^\s*Régler\s*$/), 1);
    await prendre(p, 'cfg-regles', { h: 560 });
  },
  async 'm14-taches'(p) {
    await ouvrirMaquette(p, 'm14-taches');
    await cadre(p, btn(p, 'Destination de la sauvegarde'), 1);
    await prendre(p, 'm14-taches', { h: 800 });
  },
  async 'm14-sauvegardes'(p) {
    await ouvrirMaquette(p, 'm14-sauvegardes');
    await cadre(p, btn(p, 'Générer une sauvegarde'), 1);
    await cadre(p, btn(p, /^\s*Restaurer\s*$/), 2);
    await prendre(p, 'm14-sauvegardes', { h: 900 });
  },
  async 'imp-accueil'(p) {
    await ouvrirMaquette(p, 'imp-accueil');
    await cadre(p, btn(p, 'Historique des lots'), 1);
    await cadre(p, btn(p, 'Tailles maximales'), 2);
    await prendre(p, 'imp-accueil', { h: 700 });
  },
  async 'imp-patients'(p) {
    await ouvrirMaquette(p, 'imp-patients');
    await prendre(p, 'imp-patients', { h: 820 });
  },
  async 'm12-cloture'(p) {
    await ouvrirMaquette(p, 'm12-cloture');
    await cadre(p, btn(p, 'Circuit de clôture'), 1);
    await cadre(p, btn(p, 'Pré-clôture'), 2);
    await prendre(p, 'm12-cloture', { h: 640 });
  },
  async 'm12-circuit'(p) {
    await ouvrirMaquette(p, 'm12-cloture');
    await btn(p, 'Circuit de clôture').first().click();
    await p.waitForTimeout(800);
    await nettoyer(p);
    const e = btn(p, 'Enregistrer le circuit');
    if (await e.count()) await cadre(p, e, 1);
    await prendre(p, 'm12-circuit', { h: 900 });
  },
  async 'mecef-config'(p) {
    await ouvrirMaquette(p, 'mecef-config');
    await cadre(p, btn(p, 'Régler le mode'), 1);
    await cadre(p, btn(p, 'Tester la connexion au dispositif'), 2);
    await prendre(p, 'mecef-config', { h: 1500 });
  },
  async 'cfg-pair'(p) {
    await ouvrirMaquette(p, 'cfg-pair');
    await cadre(p, btn(p, 'Enregistrer la configuration'), 1);
    await cadre(p, btn(p, 'Générer la clé'), 2);
    await prendre(p, 'cfg-pair', { h: 1100 });
  },
  /* ---- Écrans nouveaux ou changés depuis la première édition (17/11/2026) ---- */
  async 'cfg-sms'(p) {
    await ouvrirMaquette(p, 'cfg-sms');
    await cadre(p, btn(p, 'Enregistrer la passerelle'), 1);
    await cadre(p, btn(p, 'Tester l’envoi'), 2);
    await prendre(p, 'cfg-sms', { h: 1500 });
  },
  async 'm13-sms-journal'(p) {
    await ouvrirMaquette(p, 'm13-sms-journal');
    await prendre(p, 'm13-sms-journal', { h: 820 });
  },
  async 'cfg-smtp'(p) {
    await ouvrirMaquette(p, 'cfg-smtp');
    await prendre(p, 'cfg-smtp', { h: 900 });
  },
  async 'cfg-bareme-aib'(p) {
    await ouvrirMaquette(p, 'cfg-bareme-aib');
    await cadre(p, btn(p, 'Nouvelle version'), 1);
    await prendre(p, 'cfg-bareme-aib', { h: 1100 });
  },
  async 'cfg-bareme-aib-imputations'(p) {
    await ouvrirMaquette(p, 'cfg-bareme-aib');
    await p.locator('main button, main [role=tab]').filter({ hasText: /^\s*Imputations/ }).first().click();
    await p.waitForTimeout(900);
    await nettoyer(p);
    await prendre(p, 'cfg-bareme-aib-imputations', { h: 900 });
  },
  async 'm12-echeances'(p) {
    await ouvrirMaquette(p, 'm12-echeances');
    await prendre(p, 'm12-echeances', { h: 900 });
  },
  async 'm13-plan-annuel'(p) {
    await ouvrirMaquette(p, 'm13-plan-annuel');
    await prendre(p, 'm13-plan-annuel', { h: 1000 });
  },
  async 'm8-factures-tiers'(p) {
    await ouvrirMaquette(p, 'm8-factures-tiers');
    await prendre(p, 'm8-factures-tiers', { h: 820 });
  },
  async 'adm-validations'(p) {
    await ouvrirMaquette(p, 'adm-validations');
    await prendre(p, 'adm-validations', { h: 900 });
  },
  async 'cfg-systeme'(p) {
    await ouvrirMaquette(p, 'cfg-systeme');
    await prendre(p, 'cfg-systeme', { h: 900 });
  },
  async 'cfg-modules'(p) {
    await ouvrirMaquette(p, 'cfg-modules');
    await prendre(p, 'cfg-modules', { h: 900 });
  },
  async 'm14-securite-utilisateurs'(p) {
    await ouvrirMaquette(p, 'm14-securite-utilisateurs');
    await anonymiser(p);
    await prendre(p, 'm14-securite-utilisateurs', { h: 800 });
  },
  async 'm14-audit'(p) {
    await ouvrirMaquette(p, 'm14-audit');
    await anonymiser(p);
    await prendre(p, 'm14-audit', { h: 800 });
  },
  async 'mere-journal-operations'(p) {
    await ouvrirMaquette(p, 'mere-journal-operations');
    await prendre(p, 'mere-journal-operations', { h: 800 });
  },
};

const REL = {
  async 'p-connexion'(p) {
    await p.goto(R + 'connexion');
    await cadre(p, p.locator('button[type=submit]'), 1);
    await prendre(p, 'p-connexion', { y0: 0, h: 520 });
  },
  async 'p-tableau'(p) {
    await p.goto(R); await p.waitForLoadState('networkidle');
    await cadre(p, p.locator('main h2').filter({ hasText: /^Mère$/ }).first().locator('xpath=..'), 1);
    await prendre(p, 'p-tableau', { y0: 0, h: 900 });
  },
  async 'p-appareils'(p) {
    await p.goto(R + 'appareils'); await p.waitForLoadState('networkidle');
    await cadre(p, p.locator('main button').filter({ hasText: 'Révoquer' }), 1);
    await prendre(p, 'p-appareils', { y0: 0, h: 620 });
  },
  async 'p-codes'(p) { await p.goto(R + 'codes'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-codes', { y0: 0, h: 700 }); },
  async 'p-synchronisation'(p) { await p.goto(R + 'synchronisation'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-synchronisation', { y0: 0, h: 900 }); },
  async 'p-parametres'(p) { await p.goto(R + 'parametres'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-parametres', { y0: 0, h: 900 }); },
  async 'p-hebergement'(p) {
    await p.goto(R + 'hebergement'); await p.waitForLoadState('networkidle');
    await cadre(p, p.locator('main tr').filter({ hasText: 'Cron schedule:run' }), 1);
    await prendre(p, 'p-hebergement', { y0: 0, h: 700 });
  },
  async 'p-sauvegarde'(p) {
    await p.goto(R + 'sauvegarde'); await p.waitForLoadState('networkidle');
    await cadre(p, p.locator('main button').filter({ hasText: 'Exporter maintenant' }), 1);
    await prendre(p, 'p-sauvegarde', { y0: 0, h: 900 });
  },
  async 'p-opacite'(p) { await p.goto(R + 'opacite'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-opacite', { y0: 0, h: 900 }); },
  async 'p-superadmin'(p) {
    await p.goto(R + 'superadmin'); await p.waitForLoadState('networkidle');
    await cadre(p, p.locator('main button').filter({ hasText: 'Changer le mot de passe' }), 1);
    await prendre(p, 'p-superadmin', { y0: 0, h: 760 });
  },
  async 'p-sms'(p) {
    await p.goto(R + 'sms'); await p.waitForLoadState('networkidle');
    await p.waitForFunction(() => { const i = document.getElementById('limite-sms-plafond_jour'); return i && i.value !== ''; }, null, { timeout: 15000 }).catch(() => {});
    await cadre(p, p.locator('main button').filter({ hasText: 'Tester l’envoi' }), 1);
    await prendre(p, 'p-sms', { y0: 0, h: 1500 });
  },
  async 'p-boites'(p) { await p.goto(R + 'boites'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-boites', { y0: 0, h: 700 }); },
  async 'p-indicateurs'(p) { await p.goto(R + 'indicateurs'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-indicateurs', { y0: 0, h: 700 }); },
  async 'p-journal'(p) { await p.goto(R + 'journal'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-journal', { y0: 0, h: 700 }); },
  async 'p-consultation'(p) { await p.goto(R + 'consultation'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-consultation', { y0: 0, h: 800 }); },
  async 'p-satisfaction-publique'(p) { await p.goto(R.replace('/panneau/', '/s/' + (process.env.JETON_SAT || 'inconnu'))); await p.waitForLoadState('networkidle'); await prendre(p, 'p-satisfaction-publique', { y0: 0, h: 900 }); },
  async 'p-alertes'(p) { await p.goto(R + 'alertes'); await p.waitForLoadState('networkidle'); await prendre(p, 'p-alertes', { y0: 0, h: 640 }); },
};

(async () => {
  const JETON = (seul.length && seul.every((n) => n.startsWith('p-'))) ? null : await jeton();
  const b = await chromium.launch({ executablePath: CHROME, args: ['--no-sandbox'] });
  const ctxM = await b.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, locale: 'fr-FR' });
  await ctxM.addInitScript(([j]) => {
    localStorage.setItem('sigh-cnt:session', JSON.stringify({ role: 'admin', nom: 'ADMINISTRATEUR Démonstration', poste: 'Administrateur système', identifiant: 'c.bassongui', fonction: 'direction', secteur: 'ADM' }));
    localStorage.setItem('sigh-cnt:jeton', j);
  }, [JETON]);
  const pm = await ctxM.newPage();
  for (const [nom, f] of Object.entries(MAQ)) {
    if (seul.length && !seul.includes(nom)) continue;
    try { await f(pm); } catch (e) { console.log('ÉCHEC ' + nom + ' : ' + e.message.split('\n')[0]); }
  }
  await ctxM.close();
  if (!seul.length || seul.some((s) => s.startsWith('p-'))) {
    const ctxR = await b.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2, locale: 'fr-FR' });
    const pr = await ctxR.newPage();
    await pr.goto(R + 'connexion');
    await pr.fill('input[type=email], input[name=courriel], input[name=email]', COURRIEL_RELAIS);
    await pr.fill('input[type=password]', MDP_RELAIS);
    await pr.click('button[type=submit]');
    await pr.waitForLoadState('networkidle');
    for (const [nom, f] of Object.entries(REL)) {
      if (seul.length && !seul.includes(nom)) continue;
      if (nom === 'p-connexion') { const c2 = await b.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2 }); const p2 = await c2.newPage(); try { await f(p2); } catch (e) { console.log('ÉCHEC ' + nom + ' : ' + e.message); } await c2.close(); continue; }
      try { await f(pr); } catch (e) { console.log('ÉCHEC ' + nom + ' : ' + e.message.split('\n')[0]); }
    }
    await ctxR.close();
  }
  await b.close();
})();
