/* =============================================================================
 * VECTEURS DES TABLEAUX DE BORD PAR POSTE (DASH) — tirés des ÉCRANS RÉELS pilotés dans Chrome
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-dash.js        (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel>)
 *
 * Dix écrans de LECTURE : dash-medecin, -infirmier, -pharmacien, -laborantin, -stock, -caissier, -comptable, -rh, -receptionniste, -admin-agent.
 * Chaque écran est monté SOUS LE RÔLE DE SON POSTE (c'est lui qui décide de l'ouverture des étapes d'un parcours), sur le jeu du poste
 * (apps/poste/assets/donnees/jeu) et l'horloge du banc (16/08/2026 midi). On LIT ce que l'agent lit : premier regard, indicateurs, tableaux,
 * classements, données des graphiques (Chart.getChart), parcours (étapes ouvertes / fermées / poste nommé), raccourcis.
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/tba_dash.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['demandesAnalyses', 'fileAttente', 'consultations', 'admissions', 'taches', 'produits', 'lots', 'mouvements', 'factures', 'ecritures',
  'personnel', 'planning', 'patients', 'courriers', 'reunions', 'documents', 'prescriptions', 'administrations', 'tentativesConnexion', 'rbac',
  'modulesManifeste'];
const jeu = {};
NOMS.forEach((n) => {
  const f = path.join(JEU_DIR, n + '.json');
  if (fs.existsSync(f)) jeu[n] = JSON.parse(fs.readFileSync(f, 'utf8'));
});

const ECRANS = [
  ['dash-medecin', 'medecin'], ['dash-infirmier', 'infirmier'], ['dash-pharmacien', 'pharmacien'], ['dash-laborantin', 'laborantin'],
  ['dash-stock', 'stock'], ['dash-caissier', 'caissier'], ['dash-comptable', 'comptable'], ['dash-rh', 'rh'],
  ['dash-receptionniste', 'reception'], ['dash-admin-agent', 'agentadmin'],
];

(async () => {
  console.log('▶ Vecteurs des tableaux de bord par poste (10 écrans)');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Reel = window.Date;
      const decalage = new Reel(2026, 7, 16, 12, 0, 0).getTime() - Reel.now();
      const maintenant = () => Reel.now() + decalage;
      function Decalee() {
        if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
        if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
      }
      Decalee.prototype = Reel.prototype; Decalee.now = maintenant; Decalee.UTC = Reel.UTC; Decalee.parse = Reel.parse;
      window.Date = Decalee;
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/dashboards.js') });
    const sortie = await m.page.evaluate(async ({ jeu, ECRANS }) => {
      const S = SIGH.store;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const texte = (e) => (e && e.innerText || e && e.textContent || '').replace(/\s+/g, ' ').trim();
      const db = () => S.raw();
      Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); });
      const sessionBase = JSON.parse(localStorage.getItem('sigh-cnt:session'));
      const idDe = (a) => { const h = a.getAttribute('href') || ''; return h.split('/').pop().replace(/\.(php|html).*$/, ''); };

      function lireCarte(carte) {
        const titre = texte(carte.querySelector('.card-title'));
        const tables = [...carte.querySelectorAll('table')].map((tb) => ({
          entetes: [...tb.querySelectorAll('thead th')].map(texte).filter((s) => s !== ''),
          lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)),
          boutons: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean)),
        }));
        const classement = [...carte.querySelectorAll('div.space-y-2\\.5 > div')].map((d) => {
          const sp = d.querySelectorAll('span');
          return [texte(sp[0]), texte(sp[1])];
        });
        const graphiques = [...carte.querySelectorAll('canvas')].map((cv) => {
          const ch = window.Chart && Chart.getChart(cv);
          return ch ? { type: ch.config.type, etiquettes: ch.data.labels, series: ch.data.datasets.map((d) => ({ libelle: d.label, donnees: d.data })) } : null;
        }).filter(Boolean);
        const notes = [...carte.querySelectorAll('.note, [class*="rounded-lg"][class*="border"]')].map(texte);
        const liens = [...carte.querySelectorAll(':scope > .card-head a, :scope .card-head a')].map((a) => ({ libelle: texte(a), ecran: idDe(a) }));
        return { genre: 'carte', titre, tables, classement, graphiques, notes, liens, vide: carte.querySelector('.empty, [class*="empty"]') ? texte(carte.querySelector('.empty, [class*="empty"]')) : null };
      }
      function lireParcours(grille) {
        return [...grille.children].map((g) => {
          const tete = g.querySelectorAll('p');
          const etapes = [...g.querySelectorAll('ol > li')].map((li) => {
            const a = li.querySelector('a');
            const corps = li.querySelector('span.min-w-0');
            const t = texte(corps);
            const poste = [...li.querySelectorAll('span')].find((s) => /rounded.*bg-slate-100/.test(s.className) && !/grid/.test(s.className));
            const detail = [...li.querySelectorAll('span.block')][0];
            return {
              rang: texte(li.querySelector('span.grid')),
              libelle: a ? texte(a) : texte([...corps.children].find((c) => !/rounded|italic|block/.test(c.className)) || corps),
              ecran: a ? idDe(a) : null,
              poste: poste ? texte(poste) : null,
              ferme: /fermé à votre profil/.test(t),
              detail: detail ? texte(detail) : null,
            };
          });
          const bouton = g.querySelector(':scope > div.mt-3 a');
          return { titre: texte(tete[0]), detail: tete[1] ? texte(tete[1]) : null, etapes, action: bouton ? { libelle: texte(bouton), ecran: idDe(bouton) } : null };
        });
      }
      function lireRaccourcis(grille) {
        return [...grille.children].map((a) => ({ libelle: texte(a.querySelector('.text-sm')), detail: a.querySelector('.text-xs') ? texte(a.querySelector('.text-xs')) : null, ecran: idDe(a) }));
      }
      function lireCarte(carte) {
        const titre = texte(carte.querySelector('.card-title'));
        const tables = [...carte.querySelectorAll('table')].map((tb) => ({
          entetes: [...tb.querySelectorAll('thead th')].map(texte).filter((s) => s !== ''),
          lignes: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)),
          boutons: [...tb.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('button')].map((b) => b.getAttribute('title') || b.getAttribute('aria-label') || texte(b)).filter(Boolean)),
        }));
        const classement = [...carte.querySelectorAll('div.space-y-2\\.5 > div')].map((d) => {
          const sp = d.querySelectorAll('span');
          return [texte(sp[0]), texte(sp[1])];
        });
        const graphiques = [...carte.querySelectorAll('canvas')].map((cv) => {
          const ch = window.Chart && Chart.getChart(cv);
          return ch ? { type: ch.config.type, etiquettes: ch.data.labels, series: ch.data.datasets.map((d) => ({ libelle: d.label, donnees: d.data })) } : null;
        }).filter(Boolean);
        const liens = [...carte.querySelectorAll('.card-head a')].map((a) => ({ libelle: texte(a), ecran: idDe(a) }));
        const ol = carte.querySelector('ol');
        const grp = carte.querySelector('a.group');
        const vide = carte.querySelector('.empty-state, [class*="empty"]');
        return { titre, tables, classement, graphiques, liens, vide: vide ? texte(vide) : null,
          parcours: ol ? lireParcours(ol.closest('.grid')) : null, raccourcis: grp ? lireRaccourcis(grp.parentElement) : null,
          sousCartes: [...carte.querySelectorAll('.card')].filter((c) => c !== carte).map((c) => ({ titre: texte(c.querySelector('.card-title')), lignes: [...c.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)), entetes: [...c.querySelectorAll('thead th')].map(texte).filter((x) => x !== '') })),
          texte: texte(carte) };
      }
      function lireBloc(b) {
        const o = { genre: 'bloc' };
        if (/à regarder en premier/i.test(texte(b))) {
          const ps = b.querySelectorAll('p');
          const lien = b.querySelector('a');
          o.premierRegard = { texte: texte(b), ligne: texte(ps[1]), valeur: b.querySelector('span.text-2xl') ? texte(b.querySelector('span.text-2xl')) : null,
            note: ps[2] ? texte(ps[2]) : null, lien: lien ? { libelle: texte(lien), ecran: idDe(lien) } : null, ton: b.className };
          return o;
        }
        const kp = [...b.querySelectorAll('.kpi')];
        if (kp.length) {
          o.kpis = kp.map((k) => ({ label: texte(k.querySelector('.kpi-label')), valeur: texte(k.querySelector('.kpi-value')),
            indice: (() => { const h = k.querySelector('p.mt-1.text-xs'); return h ? texte(h) : null; })() }));
          return o;
        }
        const cartes = b.classList.contains('card') ? [b] : [...b.querySelectorAll('.card')].filter((c) => !c.parentElement.closest('.card'));
        if (cartes.length) { o.cartes = cartes.map(lireCarte); return o; }
        const ancres = [...b.querySelectorAll('a[href]')];
        o.alertes = ancres.map((a) => ({ texte: texte(a), ecran: idDe(a) }));
        o.texte = texte(b);
        return o;
      }

      async function monter(id, role, nom) {
        document.querySelectorAll('[role=dialog], .modal-root').forEach((d) => d.remove());
        try { sessionStorage.removeItem('sigh-cnt:rappel-labo'); } catch (e) { /* rien */ }
        localStorage.setItem('sigh-cnt:session', JSON.stringify(Object.assign({}, sessionBase, { role }, nom ? { nom, nomComplet: nom } : {})));
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens[id].render(root); await dormir(150);
        const dialogue = [...document.querySelectorAll('[role=dialog], .modal-root')].map(texte);
        const hote = root.firstElementChild;
        const blocs = hote ? [...hote.children].map(lireBloc) : [];
        const res = { id, role, nom: nom || null, titre: SIGH.screens[id].title, description: SIGH.screens[id].description, blocs, dialogue };
        document.querySelectorAll('[role=dialog], .modal-root').forEach((d) => d.remove());
        root.remove();
        return res;
      }

      const out = {};
      for (const [id, role] of ECRANS) out[id] = await monter(id, role, null);
      // Le médecin, une seconde fois, SOUS LE NOM d'un praticien auquel un ticket est adressé nommément (la file « miens »).
      const nommes = (db().fileAttente || []).filter((t) => t.poste === 'consultation' && t.etat === 'attente' && t.praticien);
      if (nommes.length) out['dash-medecin#nomme'] = await monter('dash-medecin', 'medecin', nommes[0].praticien);
      // Le biologiste : second passage le même jour — le rappel ne se rouvre pas.
      out['dash-laborantin#secondPassage'] = await (async () => {
        try { sessionStorage.setItem('sigh-cnt:rappel-labo', SIGH.core.iso(new Date())); } catch (e) { /* rien */ }
        const root = document.createElement('div'); document.body.appendChild(root);
        localStorage.setItem('sigh-cnt:session', JSON.stringify(Object.assign({}, sessionBase, { role: 'laborantin' })));
        SIGH.screens['dash-laborantin'].render(root); await dormir(150);
        const d = [...document.querySelectorAll('[role=dialog], .modal-root')].map(texte);
        root.remove(); return { dialogue: d };
      })();
      localStorage.setItem('sigh-cnt:session', JSON.stringify(sessionBase));
      return out;
    }, { jeu, ECRANS });
    if (m.erreurs.length) console.log('  (avertissements de chargement : ' + m.erreurs.length + ')');
    const n = Object.keys(sortie).length;
    ecrire('packages/domaine/test/vecteurs/tba_dash.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-dash.js — ne pas éditer. Dix tableaux de bord par poste, lus dans Chrome sur le jeu du poste, horloge 16/08/2026 midi.', ecrans: sortie });
    console.log('  ' + n + ' relevés');
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error(e); process.exit(1); });
