/* Outils COMMUNS des scripts de vecteurs de M12 (tranche « synthèse, exercices, pilotage »). Injecté dans la page de la maquette par
 * `addScriptTag({path})` : pose l'horloge du 30/10/2026 10 h, capte les pièces imprimées, les toasts, les alertes sonores et les graphiques,
 * et expose `window.__O` (monter un écran, lire ses indicateurs et tableaux, cliquer, saisir, mesurer l'écart du magasin). */
(function () {
  'use strict';
  const Reel = window.Date;
  const decalage = new Reel(2026, 9, 30, 10, 0, 0).getTime() - Reel.now();
  const maintenant = () => Reel.now() + decalage;
  function Decalee() {
    if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
    if (arguments.length === 0) return new Reel(maintenant());
    return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
  }
  Decalee.prototype = Reel.prototype; Decalee.now = maintenant; Decalee.UTC = Reel.UTC; Decalee.parse = Reel.parse;
  window.Date = Decalee;

  const S = SIGH.store;
  const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
  const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
  const texte = (e) => ((e && e.innerText) || '').replace(/\s+/g, ' ').trim();
  const db = () => S.raw();
  const pieces = [], toasts = [], graphiques = [], alertes = [];
  SIGH.print.etat = function (o) {
    pieces.push({
      titre: o.titre, sousTitre: o.sousTitre || null, cartouche: propre(o.cartouche || []),
      contenu: o.contenu ? texte(o.contenu) : null,
      tables: o.contenu && o.contenu.querySelectorAll ? [...o.contenu.querySelectorAll('table')].map((tb) => ({
        entetes: [...tb.querySelectorAll('thead th')].map(texte),
        lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)),
        pied: [...tb.querySelectorAll('tfoot td, tfoot th')].map(texte),
      })) : [],
      signatures: propre(o.signatures || []),
    });
  };
  const toastReel = SIGH.ui.toast;
  SIGH.ui.toast = function (message, opts) { toasts.push({ message: String(message), type: (opts && opts.type) || null, detail: (opts && opts.detail) || null }); return toastReel.apply(this, arguments); };
  SIGH.ui.alerter = function (message, opts) { alertes.push({ message: String(message), son: (opts && opts.son) || null, type: (opts && opts.type) || null, detail: (opts && opts.detail) || null }); };
  ['ligne', 'anneau', 'barres'].forEach((k) => {
    const f = SIGH.charts[k];
    SIGH.charts[k] = function () {
      const a = [...arguments];
      graphiques.push({ type: k, etiquettes: propre(a[0]), series: k === 'anneau' ? propre(a[1]) : propre((a[1] || []).map((s) => ({ label: s.label, data: s.data }))) });
      return f.apply(this, arguments);
    };
  });

  function releve(root) {
    const kpis = [...root.querySelectorAll('.kpi')].map((k) => ({
      label: texte(k.querySelector('.kpi-label')), valeur: texte(k.querySelector('.kpi-value')),
      indice: (() => { const h = k.querySelector('p.mt-1.text-xs.text-slate-400'); return h ? texte(h) : null; })(),
    }));
    const tables = [...root.querySelectorAll('table')].map((tb) => {
      const carte = tb.closest('.card');
      const h = carte && carte.querySelector('.card-title');
      return {
        titre: h ? texte(h) : null,
        entetes: [...tb.querySelectorAll('thead th')].map(texte).filter((s) => s !== ''),
        lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => ({
          cellules: [...tr.querySelectorAll('td')].map(texte),
          boutons: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean),
        })),
        pied: [...tb.querySelectorAll('tfoot td, tfoot th')].map(texte),
      };
    });
    const onglets = [...root.querySelectorAll('button.tab')].map(texte);
    const cartes = [...root.querySelectorAll('.card-title')].map(texte);
    const boutons = [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean);
    const notes = [...root.querySelectorAll('.rounded-lg.border')].map(texte).filter(Boolean);
    return { kpis, tables, onglets, cartes, boutons, notes };
  }
  async function monter(id) {
    const root = document.createElement('div'); document.body.appendChild(root);
    const r = SIGH.screens[id].render(root); if (r && r.nodeType) root.appendChild(r); await dormir(200);
    return root;
  }
  const bouton = (portee, re) => [...portee.querySelectorAll('button')].find((b) => re.test(texte(b)) || re.test(b.getAttribute('title') || ''));
  async function cliquer(portee, re) { const b = bouton(portee, re); if (!b) throw new Error('bouton introuvable : ' + re); b.click(); await dormir(200); return b; }
  async function onglet(root, re) { const b = [...root.querySelectorAll('button.tab')].find((x) => re.test(texte(x))); if (!b) throw new Error('onglet introuvable ' + re); b.click(); await dormir(150); }
  function poser(portee, nom, valeur) {
    const e = portee.querySelector('#f_' + nom) || portee.querySelector('[name="' + nom + '"]');
    if (!e) throw new Error('champ introuvable : ' + nom);
    e.value = valeur; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
  }
  async function filtrer(root, label, valeur) {
    const s = [...root.querySelectorAll('select[aria-label]')].find((x) => x.getAttribute('aria-label') === label);
    if (!s) throw new Error('filtre introuvable : ' + label);
    s.value = valeur; s.dispatchEvent(new Event('change', { bubbles: true })); await dormir(100);
  }
  const lignesDe = (root, i) => [...(root.querySelectorAll('table')[i || 0] || { querySelectorAll: () => [] }).querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte));
  const fermerDialogues = () => { document.querySelectorAll('[role=dialog]').forEach((d) => d.remove()); };
  const dialogue = () => [...document.querySelectorAll('[role=dialog]')].pop();
  const instantane = (noms) => { const o = {}; noms.forEach((n) => { o[n] = propre(db()[n] || []); }); return o; };
  const IGN = new Set(['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe']);
  const net = (f) => { const c = propre(f); IGN.forEach((k) => delete c[k]); return c; };
  function ecart(avant, apres) {
    const inserts = {}, modifs = {};
    Object.keys(apres).forEach((n) => {
      const a = new Map((avant[n] || []).map((f) => [f.id, f]));
      apres[n].forEach((f) => {
        if (!a.has(f.id)) { (inserts[n] = inserts[n] || []).push(net(f)); return; }
        const b = a.get(f.id), patch = {};
        Object.keys(f).forEach((k) => { if (!IGN.has(k) && JSON.stringify(f[k]) !== JSON.stringify(b[k])) patch[k] = f[k]; });
        Object.keys(b).forEach((k) => { if (!IGN.has(k) && !(k in f)) patch[k] = null; });
        if (Object.keys(patch).length) (modifs[n] = modifs[n] || []).push({ cle: b.numero || b.reference || b.code || b.id, id: b.id, patch: propre(patch) });
      });
    });
    return { inserts, modifs };
  }
  async function chercher(portee, valeur) {
    const i = portee.querySelector('input[type=search], input[placeholder^="Rechercher"]');
    if (!i) throw new Error('recherche introuvable');
    i.value = valeur; i.dispatchEvent(new Event('input', { bubbles: true })); await dormir(250);
  }
  window.__O = { dormir, propre, texte, db, pieces, toasts, graphiques, alertes, releve, monter, bouton, cliquer, onglet, poser, filtrer, lignesDe,
    fermerDialogues, dialogue, instantane, ecart, chercher, net };
})();
