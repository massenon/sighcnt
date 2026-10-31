/* =============================================================================
 * VECTEURS DE M10 (B) — PLANNING, GARDES, PERMANENCES, PRÉSENCES, ÉVALUATIONS NS 131, SANCTIONS, PRIMES NS 132
 * -----------------------------------------------------------------------------
 * Huit écrans de `assets/js/modules/m10-rh.js` MONTÉS dans Chrome, filtres réglés comme le fait l'agent, modales et boutons PILOTÉS, et
 * ce qu'ils écrivent au magasin relevé. Deux sessions : l'horloge du 30/10/2026 10 h (celle des tests de parité du poste, où le jeu daté
 * d'août ne montre rien « aujourd'hui ») et celle du 16/08/2026 midi (la date du jeu, où les grilles et les primes portent des valeurs).
 * Le JEU du poste (apps/poste/assets/donnees/jeu) est posé dans le magasin : c'est lui que les tests Flutter chargent.
 *   node build/vecteurs-rh-b.js   →   packages/domaine/test/vecteurs/rhb.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['personnel', 'planning', 'regimesTravail', 'presences', 'evaluations', 'grillePrimes', 'historiquePrimes', 'baremeNS131', 'historiqueBareme'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

async function session(horloge, corps) {
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate((h) => {
      const Reel = window.Date;
      const decalage = new Reel(h[0], h[1], h[2], h[3], 0, 0).getTime() - Reel.now();
      const maintenant = () => Reel.now() + decalage;
      function Decalee() {
        if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
        if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
      }
      Decalee.prototype = Reel.prototype; Decalee.now = maintenant; Decalee.UTC = Reel.UTC; Decalee.parse = Reel.parse;
      window.Date = Decalee;
    }, horloge);
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m10-rh.js') });
    return await corps(m.page);
  } finally { await m.fermer(); }
}

/* Exécuté DANS la page. `complet` : filtres réglés et écritures accomplies ; sinon, la lecture à l'ouverture seulement. */
async function pilote([jeu, complet]) {
  const S = SIGH.store, C = SIGH.core, D = SIGH.data;
  const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
  const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
  const texte = (e) => (e.innerText || '').replace(/\s+/g, ' ').trim();
  const db = () => S.raw();
  Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); });
  const toasts = [];
  const toastOrig = SIGH.ui.toast;
  SIGH.ui.toast = function (msg, opts) { toasts.push({ message: msg, type: (opts && opts.type) || null, detail: (opts && opts.detail) || null }); return toastOrig.apply(SIGH.ui, arguments); };
  const pieces = [];
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
  const nettoyer = () => document.querySelectorAll('[role=dialog], .modal-root, .drawer-root').forEach((d) => d.remove());
  async function monter(id) {
    nettoyer(); document.querySelectorAll('[data-vecteur]').forEach((e) => e.remove());
    const root = document.createElement('div'); root.setAttribute('data-vecteur', id); document.body.appendChild(root);
    SIGH.screens[id].render(root); await dormir(150);
    return root;
  }
  const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => ({
    label: texte(k.querySelector('.kpi-label')), valeur: texte(k.querySelector('.kpi-value')),
    indice: (() => { const h = k.querySelector('p.mt-1.text-xs.text-slate-400'); return h ? texte(h) : null; })(),
  }));
  const tableau = (root, i) => {
    const tb = [...root.querySelectorAll('table')][i || 0];
    if (!tb) return null;
    const carte = tb.closest('.card'); const h = carte && carte.querySelector('.card-title');
    return {
      titre: h ? texte(h) : null,
      entetes: [...tb.querySelectorAll('thead th')].map(texte),
      lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)),
      pied: [...tb.querySelectorAll('tfoot td, tfoot th')].map(texte),
      boutons: [...tb.querySelectorAll('tbody tr')].slice(0, 1).map((tr) => [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b))),
    };
  };
  const cartes = (root) => [...root.querySelectorAll('.card-title')].map(texte);
  const bouton = (portee, re) => [...portee.querySelectorAll('button')].find((b) => re.test(texte(b)) || re.test(b.getAttribute('title') || ''));
  async function cliquer(portee, re) { const b = bouton(portee, re); if (!b) throw new Error('bouton introuvable : ' + re); b.click(); await dormir(150); return b; }
  function champ(root, libelle) {
    const l = [...root.querySelectorAll('label.label')].find((x) => texte(x) === libelle);
    if (!l) throw new Error('champ introuvable : ' + libelle);
    return l.parentElement.querySelector('select, input');
  }
  async function regler(root, o) {
    for (const k of Object.keys(o)) {
      const e = champ(root, k); e.value = o[k];
      e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
      await dormir(60);
    }
  }
  const options = (root, libelle) => [...champ(root, libelle).options].map((o) => [o.value, texte(o)]);
  function poser(portee, nom, valeur) {
    const e = portee.querySelector('#f_' + nom);
    if (!e) throw new Error('champ introuvable : ' + nom);
    e.value = valeur; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true }));
  }
  const dialogue = () => [...document.querySelectorAll('[role=dialog]')].pop();
  const net = (x) => { const c = propre(x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe'].forEach((k) => delete c[k]); return c; };
  const pieceDerniere = () => propre(pieces[pieces.length - 1] || null);
  const lignesDe = (root, i) => { const t = tableau(root, i); return t ? t.lignes : []; };
  const sortie = { auj: C.iso(C.aujourdhui()), complet: !!complet };

  /* ---------------- PLANNING : lecture ---------------- */
  {
    const root = await monter('m10-planning');
    const tables = [...root.querySelectorAll('table')];
    sortie.planning = {
      kpis: kpis(root), cartes: cartes(root),
      regimes: tableau(root, 0),
      grille: { entetes: [...tables[1].querySelectorAll('thead th')].map(texte), lignes: [...tables[1].querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) },
      registre: tableau(root, 2),
      legende: texte([...root.querySelectorAll('span')].find((s) => texte(s) === 'Légende :').parentElement),
      texteNote: texte(root).slice(-420),
    };
    pieces.length = 0;
    await cliquer(root, /^Imprimer le planning/);
    sortie.planning.impression = pieceDerniere();
  }

  /* ---------------- STATISTIQUES DE GARDE ---------------- */
  {
    const lire = async (root, etat) => {
      const t = [...root.querySelectorAll('table')][0] ? tableau(root, 0) : null;
      return {
        etat, du: champ(root, 'Du').value, au: champ(root, 'Au').value,
        reglages: ['Périodicité', 'Agent', 'Service', 'Type de vacation', 'Fonction'].map((k) => [k, champ(root, k).value]),
        kpis: kpis(root), cartes: cartes(root), table: t,
        vide: texte(root).includes('Aucune vacation sur la période et les filtres retenus.'),
      };
    };
    const root = await monter('m10-stats-gardes');
    const g = { options: { periode: options(root, 'Périodicité'), type: options(root, 'Type de vacation').map((o) => o[0]), fonction: options(root, 'Fonction').map((o) => o[0]), service: options(root, 'Service').map((o) => o[0]), agents: options(root, 'Agent').length }, cas: [] };
    g.cas.push(await lire(root, { defaut: true }));
    if (complet) {
      const plan = db().planning.filter((v) => !v.statut || v.statut !== 'archive');
      const agentVac = (() => { const m = {}; plan.forEach((v) => { if (['garde', 'garde_hospi', 'garde_soins', 'permanence', 'soiree', 'entretien_general', 'incineration', 'remplacement'].includes(v.type)) m[v.employeId] = (m[v.employeId] || 0) + 1; }); return Object.keys(m).sort((a, b) => m[b] - m[a])[0]; })();
      const services = [...new Set(plan.map((v) => v.service).filter(Boolean))];
      const essais = [
        { 'Périodicité': 'semaine' }, { 'Périodicité': 'trimestre' }, { 'Périodicité': 'semestre' }, { 'Périodicité': 'annee' },
        { 'Périodicité': 'libre', 'Du': '2026-08-01', 'Au': '2026-08-31' },
        { 'Périodicité': 'libre', 'Du': '2026-07-01', 'Au': '2026-12-31', 'Agent': agentVac },
        { 'Périodicité': 'libre', 'Du': '2026-07-01', 'Au': '2026-12-31', 'Service': services[0] },
        { 'Périodicité': 'libre', 'Du': '2026-07-01', 'Au': '2026-12-31', 'Type de vacation': 'permanence' },
        { 'Périodicité': 'libre', 'Du': '2026-07-01', 'Au': '2026-12-31', 'Type de vacation': 'garde_soins' },
        { 'Périodicité': 'libre', 'Du': '2026-07-01', 'Au': '2026-12-31', 'Fonction': 'infirmier' },
        { 'Périodicité': 'libre', 'Du': '2026-08-10', 'Au': '2026-08-16', 'Fonction': 'sage_femme', 'Service': services[0] },
        { 'Périodicité': 'libre', 'Du': '2030-01-01', 'Au': '2030-01-31' },
        { 'Périodicité': 'libre', 'Du': '2026-08-20', 'Au': '2026-08-01' },
        { 'Périodicité': 'libre', 'Du': '', 'Au': '' },
      ];
      for (const e of essais) { await regler(root, { 'Périodicité': 'mois', 'Agent': '', 'Service': '', 'Type de vacation': '', 'Fonction': '' }); await regler(root, e); g.cas.push(await lire(root, e)); }
      pieces.length = 0;
      await regler(root, { 'Périodicité': 'libre', 'Du': '2026-08-01', 'Au': '2026-08-31', 'Agent': '', 'Service': '', 'Type de vacation': '', 'Fonction': '' });
      await cliquer(root, /^Imprimer l’état/);
      g.impression = pieceDerniere();
    }
    sortie.gardes = g;
  }

  /* ---------------- STATISTIQUES DES PERMANENCES ---------------- */
  {
    const lire = async (root, etat) => ({
      etat, reglages: ['Périodicité', 'Arrêtée au', 'Service'].map((k) => [k, champ(root, k).value]), kpis: kpis(root), cartes: cartes(root), table: [...root.querySelectorAll('table')][0] ? tableau(root, 0) : null,
      note: texte(root.querySelector('[class*=bg-info-50]') || root),
    });
    const root = await monter('m10-stats-permanences');
    const p = { services: options(root, 'Service').map((o) => o[0]), cas: [] };
    p.cas.push(await lire(root, { defaut: true }));
    if (complet) {
      const essais = [
        { 'Périodicité': 'jour', 'Arrêtée au': '2026-08-16' }, { 'Périodicité': 'semaine', 'Arrêtée au': '2026-08-16' },
        { 'Périodicité': 'mois', 'Arrêtée au': '2026-08-16' }, { 'Périodicité': 'trimestre', 'Arrêtée au': '2026-08-31' },
        { 'Périodicité': 'semestre', 'Arrêtée au': '2026-12-31' }, { 'Périodicité': 'annee', 'Arrêtée au': '2026-12-31' },
        { 'Périodicité': 'mois', 'Arrêtée au': '2026-08-31', 'Service': p.services[1] },
        { 'Périodicité': 'mois', 'Arrêtée au': '2026-08-31', 'Service': p.services[2] },
        { 'Périodicité': 'mois', 'Arrêtée au': '2026-08-31', 'Service': p.services[p.services.length - 1] },
        { 'Périodicité': 'mois', 'Arrêtée au': '2026-08-31', 'Service': p.services[0] },
        { 'Périodicité': 'mois', 'Arrêtée au': '2031-01-31' },
      ];
      for (const e of essais) { await regler(root, { 'Service': p.services[0] }); await regler(root, e); p.cas.push(await lire(root, e)); }
      pieces.length = 0;
      await regler(root, { 'Périodicité': 'mois', 'Arrêtée au': '2026-08-31', 'Service': p.services[0] });
      await cliquer(root, /^Imprimer l’état/);
      p.impression = pieceDerniere();
    }
    sortie.permanences = p;
  }

  /* ---------------- TAUX DE PRÉSENCE PAR SERVICE ---------------- */
  {
    const lire = async (root, etat) => ({ etat, kpis: kpis(root), cartes: cartes(root), table: [...root.querySelectorAll('table')][0] ? tableau(root, 0) : null, note: texte(root.querySelector('[class*=bg-info-50]') || root) });
    const root = await monter('m10-stats-presence');
    const p = { cas: [] };
    p.cas.push(await lire(root, { defaut: true }));
    if (complet) {
      const essais = [
        { 'Du': '2026-08-01', 'Au': '2026-08-31' }, { 'Du': '2026-08-10', 'Au': '2026-08-16' }, { 'Du': '2026-07-01', 'Au': '2026-12-31' },
        { 'Du': '2030-01-01', 'Au': '2030-01-31' }, { 'Du': '2026-08-20', 'Au': '2026-08-01' },
      ];
      for (const e of essais) { await regler(root, e); p.cas.push(await lire(root, e)); }
      await regler(root, { 'Du': '2026-08-01', 'Au': '2026-08-31' });
      pieces.length = 0;
      await cliquer(root, /^Imprimer l’état/);
      p.impression = pieceDerniere();
      await cliquer(root, /^Trente derniers jours/);
      p.trente = await lire(root, { trente: true });
    }
    sortie.presenceService = p;
  }

  /* ---------------- PRÉSENCES & ABSENCES ---------------- */
  {
    const lire = async (root, etat) => ({ etat, du: champ(root, 'Du').value, au: champ(root, 'Au').value, kpis: kpis(root), cartes: cartes(root), table: tableau(root, 0), pagination: texte(root.querySelector('.card')).length > 0 ? null : null });
    const root = await monter('m10-presences');
    const p = { cas: [], boutons: [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || texte(b)).filter(Boolean).slice(0, 14) };
    p.cas.push(await lire(root, { defaut: true }));
    p.rangs = texte([...root.querySelectorAll('.card')].find((c) => c.querySelector('.card-title') && texte(c.querySelector('.card-title')) === 'Taux de présence par service') || root).slice(0, 700);
    if (complet) {
      await cliquer(root, /^Mois en cours/); p.cas.push(await lire(root, { mois: true }));
      await cliquer(root, /^Sept derniers jours/); p.cas.push(await lire(root, { sept: true }));
      for (const e of [{ 'Du': '2026-08-01', 'Au': '2026-08-10' }, { 'Du': '2026-08-16', 'Au': '2026-08-16' }, { 'Du': '2030-01-01', 'Au': '2030-01-02' }]) {
        await regler(root, e); await cliquer(root, /^Appliquer/); p.cas.push(await lire(root, e));
      }
      await regler(root, { 'Du': '2026-08-01', 'Au': '2026-08-31' }); await cliquer(root, /^Appliquer/);
      /* Un pointage créé par le formulaire de l'écran. */
      const avant = db().presences.length;
      const agent = db().personnel.find((e) => e.statut !== 'archive');
      await cliquer(root, /^Ajouter un pointage/);
      let d = dialogue();
      p.formulaire = { champs: [...d.querySelectorAll('[id^=f_]')].map((e) => [e.id.slice(2), e.type || e.tagName.toLowerCase(), e.value]), titre: texte(d.querySelector('h2, h3') || d).slice(0, 120) };
      poser(d, 'employeId', agent.id); poser(d, 'date', '2026-08-16'); poser(d, 'etat', 'retard'); poser(d, 'heureArrivee', '09:15'); poser(d, 'heureDepart', '17:00'); poser(d, 'motif', 'Embouteillage');
      toasts.length = 0;
      await cliquer(d, /^Créer/);
      p.creation = { agent: { id: agent.id, nomComplet: agent.nomComplet, matricule: agent.matricule, service: agent.service }, nouvelle: net(db().presences[0]), delta: db().presences.length - avant, toast: toasts[toasts.length - 1] };
      /* Un pointage sans agent : refusé. */
      await cliquer(root, /^Ajouter un pointage/);
      d = dialogue(); toasts.length = 0;
      await cliquer(d, /^Créer/);
      p.refus = { toast: toasts[toasts.length - 1], delta: db().presences.length - avant, dialogueOuvert: !!dialogue() };
      nettoyer();
    }
    sortie.presences = p;
  }

  /* ---------------- ÉVALUATIONS NS 131 ---------------- */
  {
    const root = await monter('m10-evaluations');
    const e = { kpis: kpis(root), cartes: cartes(root), bareme: tableau(root, 0), table: tableau(root, 1), notes: texte(root).slice(0, 700) };
    e.boutonsBareme = [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || texte(b)).filter(Boolean).slice(0, 8);
    e.prelevements = [];
    const niveaux = ['bonne', 'moyenne', 'faible'];
    for (const a of niveaux) for (const b of niveaux) for (const c2 of niveaux) for (const d2 of niveaux) {
      e.prelevements.push([a, b, c2, d2, D.NS131.prelevement({ ponctualite: a, execution: b, attitude: c2, hierarchie: d2 })]);
    }
    if (complet) {
      pieces.length = 0;
      await cliquer(root, /^Imprimer la note/);
      e.note = pieceDerniere();
      /* La fiche d'évaluation et de solde d'un agent qui a des gardes ce mois-ci. */
      const gardes = {}; db().planning.forEach((v) => { if (String(v.date).slice(0, 7) === '2026-08' && v.type === 'garde') gardes[v.employeId] = (gardes[v.employeId] || 0) + 1; });
      const choisis = db().evaluations.filter((x) => gardes[x.employeId]).slice(0, 2).concat(db().evaluations.slice(0, 1));
      e.fiches = [];
      for (const ev of choisis) {
        pieces.length = 0;
        const ligne = [...root.querySelectorAll('table')][1];
        const tr = [...ligne.querySelectorAll('tbody tr')].find((x) => texte(x).includes(ev.employe) && texte(x).includes(ev.periode));
        const b = [...tr.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Imprimer la fiche'); b.click(); await dormir(100);
        e.fiches.push({ evaluation: net(ev), piece: pieceDerniere(), gardes: gardes[ev.employeId] || 0 });
      }
      /* Consulter (tiroir). */
      {
        const ev = db().evaluations[1];
        const tr = [...[...root.querySelectorAll('table')][1].querySelectorAll('tbody tr')].find((x) => texte(x).includes(ev.employe));
        tr.click(); await dormir(120);
        const d = dialogue(); e.tiroir = { evaluation: net(ev), texte: texte(d), tables: [...d.querySelectorAll('table')].map((tb) => [...tb.querySelectorAll('tbody tr')].map((r) => [...r.querySelectorAll('td')].map(texte))) };
        nettoyer();
      }
      /* Nouvelle évaluation : agent, période, niveaux. */
      const agent = db().personnel.find((x) => x.nomComplet === 'TAKI Alimatou') || db().personnel[3];
      const avant = db().evaluations.length;
      await cliquer(root, /^Nouvelle évaluation/);
      let d = dialogue();
      e.formulaire = { champs: [...d.querySelectorAll('[id^=f_]')].map((x) => [x.id.slice(2), x.value]), apercu: texte(d).slice(0, 700) };
      poser(d, 'employeId', agent.id); poser(d, 'periode', 'Août 2026');
      poser(d, 'crit_ponctualite', 'moyenne'); poser(d, 'crit_execution', 'faible'); poser(d, 'crit_attitude', 'bonne'); poser(d, 'crit_hierarchie', 'moyenne');
      poser(d, 'observations', 'Retards répétés.'); await dormir(80);
      e.apercuModifie = texte(d).slice(texte(d).indexOf('Salaire brut de référence'), texte(d).indexOf('Salaire brut de référence') + 260);
      toasts.length = 0;
      await cliquer(d, /^Valider l’évaluation/);
      e.creation = { agent: { id: agent.id, nomComplet: agent.nomComplet, salaireBase: agent.salaireBase }, nouvelle: net(db().evaluations[0]), delta: db().evaluations.length - avant, toast: toasts[toasts.length - 1] };
      /* Modifier cette évaluation : tout repasse à « bonne ». */
      {
        const rech = [...root.querySelectorAll('input[type=search][aria-label=Rechercher]')].pop();
        rech.value = agent.nomComplet; rech.dispatchEvent(new Event('input', { bubbles: true })); await dormir(700);
        const ligne = [...[...root.querySelectorAll('table')][1].querySelectorAll('tbody tr')].find((x) => texte(x).includes(agent.nomComplet) && texte(x).includes('Août 2026'));
        if (!ligne) throw new Error('ligne absente ' + JSON.stringify(e.creation) + ' ' + JSON.stringify(lignesDe(root, 1).slice(0, 3)));
        [...ligne.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Modifier').click(); await dormir(120);
        const d2 = dialogue();
        ['ponctualite', 'execution', 'attitude', 'hierarchie'].forEach((k) => poser(d2, 'crit_' + k, 'bonne'));
        toasts.length = 0;
        await cliquer(d2, /^Enregistrer/);
        e.modification = { fiche: net(db().evaluations.find((x) => x.id === e.creation.nouvelle.id)), delta: db().evaluations.length - avant, toast: toasts[toasts.length - 1] };
      }
      nettoyer();
    }
    sortie.evaluations = e;
  }

  /* ---------------- SANCTIONS ---------------- */
  {
    const root = await monter('m10-sanctions');
    const s = { kpis: kpis(root), cartes: cartes(root), table: tableau(root, 0), notes: texte(root).slice(-380) };
    if (complet) {
      pieces.length = 0;
      const tr = [...root.querySelectorAll('table')][0].querySelector('tbody tr');
      [...tr.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Notification de sanction').click(); await dormir(100);
      s.notification = pieceDerniere();
    }
    sortie.sanctions = s;
  }

  /* ---------------- PRIMES NS 132 ---------------- */
  {
    const root = await monter('m10-primes');
    const p = { kpis: kpis(root), cartes: cartes(root), grille: tableau(root, 0), acquises: tableau(root, 1), boutons: [...root.querySelectorAll('button')].map((b) => b.getAttribute('title') || texte(b)).filter(Boolean).slice(0, 12) };
    p.montants = [];
    const fonctions = D.FONCTIONS.map((f) => f.id);
    D.NS132.primes.forEach((pr) => fonctions.forEach((f) => p.montants.push([pr.id, f, null, D.NS132.montant(pr.id, f)])));
    if (complet) {
      pieces.length = 0;
      await cliquer(root, /^Imprimer la note/); p.note = pieceDerniere();
      pieces.length = 0;
      await cliquer(root, /^Éditer l’état des primes/); p.etat = pieceDerniere();
    }
    sortie.primes = p;
  }
  if (!complet) return sortie;

  /* ================== PRIMES : écritures et portée ================== */
  {
    const root0 = await monter('m10-primes');
    const r = { cas: [] };
    const colG = () => db().grillePrimes, colH = () => db().historiquePrimes;
    const echantillons = () => {
      const o = [];
      [['garde', 'infirmier'], ['garde', 'aide_soignant'], ['permanence', 'aide_soignant'], ['permanence', 'infirmier'], ['caisse', 'caissiere'], ['accueil', 'accueil'], ['bonus', 'infirmier']].forEach(([p, f]) => {
        ['2026-07-01', '2026-07-12', '2026-07-13', '2026-08-01', '2026-08-15', '2026-08-16', '2026-09-01', null].forEach((dt) => o.push([p, f, dt, D.NS132.montant(p, f, dt || undefined)]));
      });
      return o;
    };
    r.avant = echantillons();
    async function modifier(lib, valeurs, portee) {
      const root = await monter('m10-primes');
      const tr = [...[...root.querySelectorAll('table')][0].querySelectorAll('tbody tr')].find((x) => texte(x).startsWith(lib));
      [...tr.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Modifier cette prime').click(); await dormir(120);
      let d = dialogue();
      const ouverture = [...d.querySelectorAll('[id^=f_]')].map((e) => [e.id.slice(2), e.value]);
      Object.keys(valeurs).forEach((k) => poser(d, k, valeurs[k]));
      await cliquer(d, /^Enregistrer/);
      d = dialogue();
      const demande = texte(d).slice(0, 1000);
      if (portee === 'tout') { d.querySelector('input[value=tout]').click(); await dormir(40); }
      toasts.length = 0;
      const nh = colH().length;
      await cliquer(d, /^Appliquer/);
      r.cas.push({ lib, valeurs, portee, ouverture, demande, toast: toasts[toasts.length - 1], fiche: net(colG().find((x) => x.label === (valeurs.label || lib))), historique: net(colH().slice(0, colH().length - nh)), audit: net((db().audit || [])[0] || null), echantillons: echantillons(), acquises: tableau(await monter('m10-primes'), 1), kpis: kpis(await monter('m10-primes')) });
    }
    await modifier('Garde', { m_infirmier: '2000', m_tsl: '1700' }, 'futur');
    await modifier('Permanence', { m_aide_soignant: '650', label: 'Permanence (révisée)' }, 'tout');
    await modifier('Aide bloc', { label: 'Aide bloc' }, 'futur'); // aucun montant modifié
    /* Une prime nouvelle. */
    {
      const root = await monter('m10-primes');
      await cliquer(root, /^Nouvelle prime/);
      const d = dialogue();
      poser(d, 'label', 'Prime de nuit'); poser(d, 'mode', 'occurrence'); poser(d, 'm_infirmier', '1200'); poser(d, 'm_sage_femme', '1300');
      toasts.length = 0;
      await cliquer(d, /^Créer la prime/);
      r.creation = { toast: toasts[toasts.length - 1], fiche: net(colG().find((x) => x.label === 'Prime de nuit')), echantillons: [D.NS132.montant('prime-de-nuit', 'infirmier'), D.NS132.montant('prime-de-nuit', 'sage_femme'), D.NS132.montant('prime-de-nuit', 'tsl')], acquises: tableau(await monter('m10-primes'), 1).lignes.length };
    }
    /* Retirer une prime : motif obligatoire ; ce que le moteur calcule ENSUITE. */
    {
      const root = await monter('m10-primes');
      const tr = [...[...root.querySelectorAll('table')][0].querySelectorAll('tbody tr')].find((x) => texte(x).startsWith('Caisse'));
      [...tr.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Retirer cette prime').click(); await dormir(120);
      const d = dialogue();
      const m = d.querySelector('textarea, input[type=text]'); m.value = 'Prime abrogée par note'; m.dispatchEvent(new Event('input', { bubbles: true }));
      const nh = colH().length;
      toasts.length = 0;
      await cliquer(d, /^Retirer la prime/);
      const apres = await monter('m10-primes');
      r.retrait = { toast: toasts[toasts.length - 1], archivee: net(colG().find((x) => x.label === 'Caisse')), historique: net(colH().slice(0, colH().length - nh)), montantCaisse: D.NS132.montant('caisse', 'caissiere'), grilleLignes: tableau(apres, 0).lignes.length, acquises: tableau(apres, 1), kpis: kpis(apres) };
    }
    sortie.primesEcritures = r;
  }

  /* ================== BARÈME NS 131 : la porte ================== */
  {
    const b = { ferme: {}, ouvert: {} };
    {
      const root = await monter('m10-evaluations');
      b.ferme = { boutons: [...root.querySelectorAll('button')].map((x) => x.getAttribute('title') || texte(x)).filter(Boolean).slice(0, 10), note: texte([...root.querySelectorAll('.space-y-3 > *')][0] || root).slice(0, 400), porte: SIGH.baremeModifiable() };
    }
    await SIGH.setBaremeModifiable(true); await dormir(200);
    const colB = () => db().baremeNS131, colH = () => db().historiqueBareme;
    const ligne = (root, num) => [...[...root.querySelectorAll('table')][0].querySelectorAll('tbody tr')].find((x) => texte(x).startsWith(num));
    {
      const root = await monter('m10-evaluations');
      b.ouvert = { porte: SIGH.baremeModifiable(), boutons: [...root.querySelectorAll('button')].map((x) => x.getAttribute('title') || texte(x)).filter(Boolean).slice(0, 14), note: texte(root).slice(0, 420), ligneBoutons: [...ligne(root, '01').querySelectorAll('button')].map((x) => x.getAttribute('title')) };
    }
    b.cas = [];
    async function modifier(num, valeurs, portee) {
      const root = await monter('m10-evaluations');
      [...ligne(root, num).querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Modifier ce critère').click(); await dormir(120);
      let d = dialogue();
      const ouverture = [...d.querySelectorAll('[id^=f_]')].map((e) => [e.id.slice(2), e.value]);
      Object.keys(valeurs).forEach((k) => poser(d, k, valeurs[k]));
      await cliquer(d, /^Enregistrer/);
      d = dialogue();
      const demande = texte(d).slice(0, 1000);
      if (portee === 'tout') { d.querySelector('input[value=tout]').click(); await dormir(40); }
      toasts.length = 0; const nh = colH().length;
      await cliquer(d, /^Appliquer/);
      const apres = await monter('m10-evaluations');
      b.cas.push({ num, valeurs, portee, ouverture, demande, toast: toasts[toasts.length - 1], critere: net(colB().find((x) => x.num === num)), historique: net(colH().slice(0, colH().length - nh)), table: tableau(apres, 0), historiqueAffiche: texte(apres).includes('Versions antérieures du barème'), audit: net((db().audit || [])[0] || null) });
    }
    await modifier('01', { moyenne: '7', faible: '12' }, 'futur');
    await modifier('02', { faible: '20', criteresTexte: 'Tâches non exécutées\nTâches mal exécutées\nTâches en retard' }, 'tout');
    /* Une évaluation créée APRÈS : quel barème applique-t-elle ? */
    {
      const root = await monter('m10-evaluations');
      const agent = db().personnel.find((x) => x.nomComplet === 'TAKI Alimatou');
      await cliquer(root, /^Nouvelle évaluation/);
      const d = dialogue();
      poser(d, 'employeId', agent.id); poser(d, 'periode', 'Juillet 2026');
      poser(d, 'crit_ponctualite', 'moyenne'); poser(d, 'crit_execution', 'faible'); poser(d, 'crit_attitude', 'bonne'); poser(d, 'crit_hierarchie', 'bonne'); await dormir(80);
      b.libellesFormulaire = [...d.querySelectorAll('label.label')].map(texte).slice(0, 12);
      b.optionsCritere = [...d.querySelector('#f_crit_ponctualite').options].map(texte);
      await cliquer(d, /^Valider l’évaluation/);
      b.evaluationApres = { nouvelle: net(db().evaluations[0]), bareme: net(colB().map((x) => ({ num: x.num, sanctions: x.sanctions }))) };
    }
    /* Un critère nouveau, puis retiré. */
    {
      const root = await monter('m10-evaluations');
      await cliquer(root, /^Nouveau critère/);
      const d = dialogue();
      b.formulaireCritere = [...d.querySelectorAll('[id^=f_]')].map((e) => [e.id.slice(2), e.value]);
      poser(d, 'label', 'Hygiène et tenue'); poser(d, 'criteresTexte', 'Tenue incorrecte\nMains non lavées'); poser(d, 'moyenne', '4'); poser(d, 'faible', '8');
      toasts.length = 0;
      await cliquer(d, /^Créer le critère/);
      b.creation = { toast: toasts[toasts.length - 1], critere: net(colB().find((x) => x.label === 'Hygiène et tenue')) };
      const root2 = await monter('m10-evaluations');
      [...ligne(root2, '05').querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Retirer ce critère').click(); await dormir(120);
      const d2 = dialogue(); const m = d2.querySelector('textarea, input[type=text]'); m.value = 'Critère abrogé'; m.dispatchEvent(new Event('input', { bubbles: true }));
      const nh = colH().length; toasts.length = 0;
      await cliquer(d2, /^Retirer le critère/);
      b.retrait = { toast: toasts[toasts.length - 1], archive: net(colB().find((x) => x.label === 'Hygiène et tenue')), historique: net(colH().slice(0, colH().length - nh)) };
    }
    await SIGH.setBaremeModifiable(false);
    sortie.bareme = b;
  }

  /* ================== ÉCRITURES ================== */
  /* ---- Régimes : la portée ---- */
  {
    const root = await monter('m10-planning');
    const colReg = () => db().regimesTravail;
    const ligneRegime = (lib) => [...root.querySelectorAll('table')][0] && [...[...root.querySelectorAll('table')][0].querySelectorAll('tbody tr')].find((tr) => texte(tr).startsWith(lib));
    const r = { cas: [] };
    async function modifier(lib, valeurs, portee) {
      const avant = { reg: propre(colReg()), plan: propre(db().planning) };
      const tr = ligneRegime(lib);
      [...tr.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Modifier ce régime').click(); await dormir(120);
      let d = dialogue();
      const ouverture = texte(d).slice(0, 400);
      Object.keys(valeurs).forEach((k) => poser(d, k, valeurs[k]));
      await cliquer(d, /^Enregistrer/);
      d = dialogue();
      const demande = texte(d).slice(0, 900);
      if (portee === 'tout') { d.querySelector('input[value=tout]').click(); await dormir(40); }
      toasts.length = 0;
      await cliquer(d, /^Appliquer/);
      const apres = { reg: propre(colReg()), plan: propre(db().planning) };
      const diffPlan = apres.plan.filter((v, i) => JSON.stringify(v) !== JSON.stringify(avant.plan[i])).map((v) => ({ date: v.date, fonction: v.fonction, regimeLibelle: v.regimeLibelle, regimeRevisee: v.regimeRevisee || null }));
      r.cas.push({ lib, valeurs, portee, ouverture, demande, toast: toasts[toasts.length - 1], regime: net(apres.reg.find((x) => x.libelle === (valeurs.libelle || lib))), nbDiffPlan: diffPlan.length, echantillon: diffPlan.slice(0, 3), audit: net((db().audit || [])[0] || null) });
    }
    await modifier('Infirmiers', { libelle: 'Infirmiers (cycle revu)', cycle: '4' }, 'futur');
    await modifier('Médecins', { libelle: 'Médecins de garde', cycle: '3' }, 'tout');
    /* Archiver un régime (motif obligatoire). */
    {
      const tr = ligneRegime('Agents de sécurité');
      [...tr.querySelectorAll('button')].find((x) => x.getAttribute('title') === 'Archiver ce régime').click(); await dormir(120);
      const d = dialogue(); r.archivage = { message: texte(d).slice(0, 700) };
      toasts.length = 0;
      await cliquer(d, /^Archiver le régime/); // sans motif
      r.archivage.sansMotif = { toast: toasts[toasts.length - 1] || null, dialogueOuvert: !!dialogue(), actifs: colReg().filter((x) => x.statut !== 'archive').length };
      if (dialogue()) {
        const m = dialogue().querySelector('textarea, input[type=text]');
        if (m) { m.value = 'Poste supprimé'; m.dispatchEvent(new Event('input', { bubbles: true })); }
        await cliquer(dialogue(), /^Archiver le régime/);
      }
      r.archivage.apres = { actifs: colReg().filter((x) => x.statut !== 'archive').length, fiche: net(colReg().find((x) => x.libelle === 'Agents de sécurité')) };
      nettoyer();
    }
    sortie.regimes = r;
  }

  /* ---- Planning : l'incompatibilité et l'affectation ---- */
  {
    const root = await monter('m10-planning');
    const grille = [...root.querySelectorAll('table')][1];
    const jours = [...grille.querySelectorAll('thead th')].slice(1).map(texte);
    const a = { jours, cas: [] };
    const personnes = db().personnel.filter((e) => e.statut !== 'archive');
    async function essayer(fonction, joursAvant, typeAvant, typeVoulu, colJour) {
      const agent = personnes.find((e) => e.fonction === fonction && !db().planning.some((v) => v.employeId === e.id && v.date >= '2026-08-10' && v.date <= '2026-08-20')) || (() => { const e = personnes.find((x) => x.fonction === fonction); db().planning = db().planning.filter((v) => !(v.employeId === e.id && v.date >= '2026-08-10' && v.date <= '2026-08-20')); return e; })();
      const jourIso = ['2026-08-13', '2026-08-14', '2026-08-15', '2026-08-16', '2026-08-17', '2026-08-18', '2026-08-19'][colJour];
      const prec = (() => { const d = new Date(jourIso + 'T12:00:00'); d.setDate(d.getDate() - joursAvant); return C.iso(d); })();
      const avant = db().planning.length;
      if (typeAvant) db().planning.unshift({ id: 'PLX' + fonction + joursAvant, employeId: agent.id, employe: agent.nomComplet, date: prec, type: typeAvant, fonction, service: agent.service, statut: 'validee' });
      const tr = [...grille.querySelectorAll('tbody tr')].find((x) => texte(x).startsWith(agent.nomComplet));
      const cell = [...tr.querySelectorAll('td')][colJour + 1].querySelector('button');
      cell.click(); await dormir(120);
      const d = dialogue();
      const offerts = [...d.querySelector('#f_type').options].map((o) => [o.value, texte(o)]);
      const note = texte(d).slice(0, 500);
      poser(d, 'type', typeVoulu);
      toasts.length = 0;
      const b = bouton(d, /^Enregistrer/);
      return { agent, jourIso, prec, offerts, note, b, toasts, d, avant };
    }
    for (const c of [
      { f: 'medecin', av: 1, ta: 'garde', tv: 'garde', col: 3 },
      { f: 'medecin', av: 2, ta: 'garde', tv: 'garde', col: 3 },
      { f: 'sage_femme', av: 1, ta: 'garde', tv: 'garde', col: 3 },
      { f: 'infirmier', av: 2, ta: 'garde_hospi', tv: 'garde_hospi', col: 4 },
    ]) {
      const x = await essayer(c.f, c.av, c.ta, c.tv, c.col);
      x.b.click(); await dormir(120);
      a.cas.push({ fonction: c.f, joursAvant: c.av, typeAvant: c.ta, typeVoulu: c.tv, jour: x.jourIso, offerts: x.offerts, note: x.note, toast: x.toasts[x.toasts.length - 1] || null, dialogueOuvert: !!dialogue(), ajoute: db().planning.length - x.avant - 1 });
      nettoyer();
    }
    sortie.affectation = a;
  }
  return sortie;
}

/* Le chemin qui RECHARGE la page (« global.location.reload() ») : on relève ce qu'il écrit avant que la page ne parte. */
async function affectations(page) {
  const trace = [];
  await page.exposeFunction('noter', (x) => trace.push(x));
  const info = await page.evaluate(async () => {
    const S = SIGH.store, C = SIGH.core;
    const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
    const texte = (e) => (e.innerText || '').replace(/\s+/g, ' ').trim();
    const orig = S.collection;
    S.collection = function (nom, o) {
      const col = orig.apply(S, arguments);
      if (nom === 'planning' && !col.__vecteur) {
        col.__vecteur = true;
        ['insert', 'update', 'archive'].forEach((k) => { const f = col[k]; col[k] = function () { window.noter({ op: k, args: JSON.parse(JSON.stringify(Array.prototype.slice.call(arguments))) }); return f.apply(col, arguments); }; });
      }
      return col;
    };
    document.querySelectorAll('[data-vecteur]').forEach((e) => e.remove());
    const root = document.createElement('div'); root.setAttribute('data-vecteur', 'x'); document.body.appendChild(root);
    SIGH.screens['m10-planning'].render(root); await dormir(150);
    const grille = [...root.querySelectorAll('table')][1];
    const agent = S.raw().personnel.find((e) => e.fonction === 'aide_soignant' && e.statut !== 'archive');
    S.raw().planning = S.raw().planning.filter((v) => !(v.employeId === agent.id && v.date >= '2026-08-10' && v.date <= '2026-08-20'));
    const tr = [...grille.querySelectorAll('tbody tr')].find((x) => texte(x).startsWith(agent.nomComplet));
    const cell = [...tr.querySelectorAll('td')][2].querySelector('button');
    cell.click(); await dormir(120);
    const d = [...document.querySelectorAll('[role=dialog]')].pop();
    const e = d.querySelector('#f_type'); e.value = 'garde'; e.dispatchEvent(new Event('change', { bubbles: true }));
    const o = d.querySelector('#f_observation'); o.value = 'Remplace A.'; o.dispatchEvent(new Event('input', { bubbles: true }));
    window.__agent = { id: agent.id, nomComplet: agent.nomComplet, fonction: agent.fonction, service: agent.service };
    setTimeout(() => { [...d.querySelectorAll('button')].find((b) => /^Enregistrer/.test(texte(b))).click(); }, 10);
    return window.__agent;
  });
  await new Promise((r) => setTimeout(r, 1500));
  return { agent: info, trace };
}

(async () => {
  console.log('▶ Vecteurs de M10 (B) — planning, gardes, permanences, présences, évaluations, sanctions, primes');
  const A = await session([2026, 9, 30, 10], (page) => page.evaluate(pilote, [jeu, false]));
  const Bsortie = {};
  let aff = null;
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate((h) => {
      const Reel = window.Date;
      const decalage = new Reel(h[0], h[1], h[2], h[3], 0, 0).getTime() - Reel.now();
      const maintenant = () => Reel.now() + decalage;
      function Decalee() {
        if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
        if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
      }
      Decalee.prototype = Reel.prototype; Decalee.now = maintenant; Decalee.UTC = Reel.UTC; Decalee.parse = Reel.parse;
      window.Date = Decalee;
    }, [2026, 7, 16, 12]);
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m10-rh.js') });
    Object.assign(Bsortie, await m.page.evaluate(pilote, [jeu, true]));
    aff = await affectations(m.page);
  } finally { await m.fermer(); }
  ecrire('packages/domaine/test/vecteurs/rhb.json', { ouverture: A, jeuDeLaMaquette: Bsortie, affectationReussie: aff });
})().catch((e) => { console.error(e); process.exit(1); });
