/* =============================================================================
 * VECTEURS DE M10 (C) — m10-badges, -verification, -modeles, -impression, m10-evenements, m10-participations, m10-assurance-personnel, m10-securite-entretien
 * -----------------------------------------------------------------------------
 * Les huit écrans RÉELS montés dans Chrome sur le JEU DU POSTE (horloge figée 30/10/2026 10 h), lus comme l agent les lit et PILOTÉS
 * (émission, retrait, vérification, planche, événement, règlement, rotation…) ; les gabarits d impression, la navigation et les états sont CAPTURÉS.
 *   node build/vecteurs-rh-c.js   →   packages/domaine/test/vecteurs/rhc.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU = path.resolve(ROOT, '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
const COLLECTIONS = ['personnel', 'planning', 'regimesTravail', 'patients', 'consultations', 'demandesAnalyses', 'admissions', 'evenements', 'participations', 'badges', 'modelesBadge'];

(async () => {
  console.log('▶ Vecteurs de M10 (RH)');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Vrai = Date;
      window.__FIXE = new Vrai(2026, 9, 30, 10, 0, 0).getTime(); window.__Vrai = Vrai;
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      window.__etats = []; window.__erreurs = []; window.addEventListener('error', (e) => window.__erreurs.push(String(e.message)));
      const setTimeoutReel = window.setTimeout.bind(window);
      window.setTimeout = (fn, ms, ...a) => (String(fn).includes('location.reload') ? 0 : setTimeoutReel(fn, ms, ...a));
      SIGH.ui.sonner = () => {};
      window.__alertes = [];
      SIGH.ui.alerter = (msg, o) => { window.__alertes.push({ message: msg, type: (o || {}).type || null, son: (o || {}).son || null }); return { close() {} }; };
      SIGH.print.etat = function (o) {
        const tab = [];
        const c = o.contenu;
        if (c && c.querySelectorAll) {
          (c.tagName === 'TABLE' ? [c] : [...c.querySelectorAll('table')]).forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
            pied: [...t.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({
          titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null,
          texte: c && c.innerText ? c.innerText.replace(/\s+/g, ' ').trim() : null, tableaux: tab,
        })));
      };
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m10-rh.js') });

    await m.page.evaluate(() => {
      const norm = (t) => String(t == null ? '' : t).replace(/[\n\t\r]+/g, ' ').replace(/\s+/g, ' ').trim();
      window.H = {
        norm,
        propre: (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)),
        dormir: (ms) => new Promise((r) => setTimeout(r, ms)),
        net: (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return JSON.parse(JSON.stringify(c)); },
        kpis: (root) => [...root.querySelectorAll('.kpi')].map((k) => {
          const p = k.querySelectorAll('p');
          return { libelle: norm(p[0].innerText), valeur: norm(p[1].innerText), indice: p[2] ? norm(p[2].innerText) : null };
        }),
        tableaux: (root) => [...root.querySelectorAll('table')].map((t) => ({
          entetes: [...t.querySelectorAll('thead th')].map((x) => norm(x.innerText)).filter((s) => s !== ''),
          lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.innerText)).filter((s, i) => i > 0 || s !== '')),
        })),
        cartes: (root) => [...root.querySelectorAll('.card')].map((c) => {
          const h = c.querySelector('.card-header, .card-head, h3, h2');
          return h ? norm(h.innerText) : null;
        }).filter(Boolean),
        onglets: (root) => [...root.querySelectorAll('.tab')].map((t) => norm(t.innerText)),
        notes: (root) => [...root.querySelectorAll('.rounded-lg.border')].map((n) => norm(n.innerText)).filter((t) => t.length > 20),
        fermerTout: () => document.querySelectorAll('[role=dialog], .modal-root, .drawer-root, .drawer-backdrop').forEach((x) => x.remove()),
        toasts: () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim())),
        viderToasts: () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; window.__alertes.length = 0; },
        bouton: (racine, texte) => [...racine.querySelectorAll('button')].find((b) => b.textContent.trim() === texte || b.getAttribute('aria-label') === texte || b.title === texte),
        poser: (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); },
        champs: () => [...document.querySelectorAll('[role=dialog] label, .modal-root label')].map((l) => norm(l.innerText)),
        optsDe: (id) => { const e = document.getElementById('f_' + id); if (!e) return null; if (typeof e.options === 'function') return e.options().map((o) => [o.value, norm(o.label)]); return [...e.options].map((o) => [o.value, norm(o.textContent)]); },
        valeur: (id) => { const e = document.getElementById('f_' + id); return e ? (e.type === 'checkbox' ? e.checked : e.value) : '(absent)'; },
        cliquer: (texte) => { const bs = [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === texte); bs[bs.length - 1].click(); },
        icone: (ligne, nom) => [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === nom),
        boutons: (racine) => [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
        tiroir: () => { const t = document.querySelector('[role=dialog], .drawer-root') || document.body; return { texte: norm(t.innerText), boutons: [...t.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean) }; },
        modale: () => norm((document.querySelector('.modal-root, [role=dialog]') || { innerText: '' }).innerText),
        monter: async (id) => {
          const root = document.createElement('div'); document.body.appendChild(root);
          window.__etats.length = 0;
          SIGH.screens[id].render(root);
          await new Promise((r) => setTimeout(r, 300));
          return root;
        },
        retirer: (root) => { root.remove(); H.fermerTout(); },
        vider: (col) => { col.all().splice(0); },
        ligne: (racine, texte) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(texte)),
        confirmer: async (motif) => {
          await H.dormir(250);
          const zone = document.querySelector('[role=dialog], .modal-root');
          const ta = zone && (zone.querySelector('textarea') || zone.querySelector('input[type=text]'));
          if (ta) { ta.value = motif; ta.dispatchEvent(new Event('input')); }
          const btns = zone ? [...zone.querySelectorAll('button')] : [];
          const ok = btns.find((b) => b.textContent.trim() === 'Archiver');
          if (ok) ok.click();
          await H.dormir(250);
        },
        lireEcran: (root) => ({ kpis: H.kpis(root), onglets: H.onglets(root), cartes: H.cartes(root), tableaux: H.tableaux(root), notes: H.notes(root), boutons: H.boutons(root).slice(0, 14) }),
        // jours relatifs à AUJ (30/10/2026), en date ISO locale
        J: (n) => { const d = new Date(2026, 9, 30 + n); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); },
      };
    });


    await m.page.evaluate(() => {
      window.__graphes = [];
      const G = SIGH.charts;
      ['anneau', 'barres', 'camembert', 'ligne'].forEach((nom) => {
        const f = G[nom];
        G[nom] = function (etiq, donnees, opts) {
          window.__graphes.push(JSON.parse(JSON.stringify({ type: nom, etiquettes: etiq, donnees: donnees })));
          return f.apply(this, arguments);
        };
      });
      const norm = window.H.norm;
      Object.assign(window.H, {
        chercher: async (root, txt) => { const i = root.querySelector('input[aria-label="Rechercher"]'); i.value = txt; i.dispatchEvent(new Event('input')); await H.dormir(500); return root; },
        graphes: () => JSON.parse(JSON.stringify(window.__graphes)),
        lignesPage: (root) => [...root.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.innerText))),
        ranking: (root) => [...root.querySelectorAll('.card')].filter((c) => c.querySelector('[style*="width"]') && !c.querySelector('table')).map((c) => norm(c.innerText)),
        cartesTexte: (root) => [...root.querySelectorAll('.card')].map((c) => norm(c.innerText)),
        // sélecteurs de filtre d'un tableau : [libellé, [[valeur, libellé]…]]
        filtres: (root) => [...root.querySelectorAll('select')].map((s) => [s.getAttribute('aria-label'), [...s.options].map((o) => [o.value, norm(o.textContent)])]),
        // les onglets : on clique chacun et on lit le contenu rendu
        parOnglet: async (root) => {
          const sortie = {};
          const onglets = [...root.querySelectorAll('.tab')];
          for (const t of onglets) {
            t.click(); await H.dormir(120);
            const lab = norm(t.innerText);
            const corps = t.closest('[role=tablist]') ? t.closest('[role=tablist]').parentElement : root;
            sortie[lab] = { texte: norm((corps || root).innerText), kpis: H.kpis(corps || root), tableaux: H.tableaux(corps || root), notes: H.notes(corps || root) };
          }
          return sortie;
        },
      });
    });
    await m.page.evaluate((jeu) => {
      const S = SIGH.store;
      for (const [nom, lignes] of Object.entries(jeu)) {
        const col = S.collection(nom);
        col.all().splice(0);
        lignes.forEach((x) => col.all().push(x));
      }
    }, Object.fromEntries(COLLECTIONS.map((n) => [n, JSON.parse(fs.readFileSync(path.join(JEU, n + '.json'), 'utf8'))])));

    /* Relais : les gabarits d'impression (badge, planche), la navigation et le temps réel sont CAPTURÉS, pas exécutés. */
    await m.page.evaluate(() => {
      window.__badges = []; window.__planches = []; window.__go = [];
      SIGH.print.badge = function (o) {
        window.__badges.push(JSON.parse(JSON.stringify({ numero: o.badge.numero, modele: o.modele && o.modele.libelle, orientation: o.modele && o.modele.orientation, zones: o.modele && o.modele.zones, mentionsVerso: o.modele && o.modele.mentionsVerso, agentId: o.agent ? o.agent.id : null })));
      };
      SIGH.print.planche = function (o) {
        window.__planches.push(JSON.parse(JSON.stringify({ modele: o.modele && o.modele.libelle, zones: o.modele && o.modele.zones, badges: o.badges.map((b) => ({ numero: b.badge.numero, agentId: b.agent ? b.agent.id : null })) })));
      };
      SIGH.app.go = function (id, o) { window.__go.push([id, o || null]); };
      const norm = window.H.norm;
      Object.assign(window.H, {
        // le bouton de libellé exact DANS la dernière boîte de dialogue ouverte
        dans: (texte) => { const z = [...document.querySelectorAll('[role=dialog]')].pop(); return z ? [...z.querySelectorAll('button')].find((b) => norm(b.textContent) === texte || b.getAttribute('aria-label') === texte) : null; },
        confirmerBtn: async (libelle, motif) => {
          await H.dormir(250);
          const zone = [...document.querySelectorAll('[role=dialog]')].pop();
          const ta = zone && (zone.querySelector('textarea') || zone.querySelector('input[type=text]'));
          if (ta && motif != null) { ta.value = motif; ta.dispatchEvent(new Event('input')); }
          const ok = zone && [...zone.querySelectorAll('button')].filter((b) => norm(b.textContent) === libelle).pop();
          if (!ok) throw new Error('bouton de confirmation absent : ' + libelle);
          ok.click(); await H.dormir(300);
        },
        selects: (root) => [...root.querySelectorAll('label.label')].map((l) => { const s = l.parentElement.querySelector('select'); return s ? [norm(l.innerText), s.value, [...s.options].map((o) => [o.value, norm(o.textContent)])] : null; }).filter(Boolean),
        regler: async (root, libelle, valeur) => {
          const l = [...root.querySelectorAll('label.label')].find((x) => norm(x.innerText) === libelle);
          const s = l.parentElement.querySelector('select, input'); s.value = valeur;
          s.dispatchEvent(new Event('input', { bubbles: true })); s.dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(200);
        },
        ligneDe: (root, texte) => [...root.querySelectorAll('tbody tr')].find((tr) => norm(tr.innerText).includes(texte)),
        boutonsDe: (tr) => [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title || norm(b.textContent)),
        sansMeta: (x) => { const c = H.net(x); return c; },
        audit0: () => { const a = H.propre(SIGH.store.raw().audit[0]); delete a.id; delete a.dateHeure; return a; },
        carteTexte: (root, titre) => { const c = [...root.querySelectorAll('.card')].find((k) => { const h = k.querySelector('.card-title, .card-header, h3, h2'); return h && norm(h.innerText) === titre; }); return c ? norm(c.innerText) : null; },
      });
    });

    await m.page.evaluate((jeu) => {
      window.__jeu = jeu;
      window.H.reposer = () => {
        for (const [nom, lignes] of Object.entries(window.__jeu)) { const col = SIGH.store.collection(nom); col.all().splice(0); lignes.forEach((x) => col.all().push(JSON.parse(JSON.stringify(x)))); }
        SIGH.store.raw().audit.splice(0); window.__etats.length = 0;
      };
    }, Object.fromEntries(COLLECTIONS.map((n) => [n, JSON.parse(fs.readFileSync(path.join(JEU, n + '.json'), 'utf8'))])));

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-rh-c.js — ne pas éditer. Horloge : 30/10/2026 10 h. Jeu : apps/poste/assets/donnees/jeu.' };

    /* ------------------------------------------------------------------ FABRIQUE DES BADGES (parcours.js) */
    sortie.fabrique = await m.page.evaluate(() => {
      const PR = SIGH.parcours; const S = SIGH.store;
      const b = S.collection('badges').all();
      return {
        numeros: ['2026-10-30', '2026-01-01', '2025-06-01', '2024-12-31', '2027-03-03'].map((d) => [d, PR.numeroBadge(d)]),
        parAnnee: [2025, 2026].map((a) => [a, b.filter((x) => String(x.numero).endsWith('-' + a)).map((x) => x.numero)]),
        qr: b.slice(0, 3).map((x) => [x.matricule, x.numero, PR.badgeQR(x)]),
        qrSansChamps: PR.badgeQR({}),
        lecture: ['CNT-BDG|MAT:1|SER:BDG-00001-2026', 'BDG-00001-2026', '  bdg-00001-2026  ', 'CNT-BDG|MAT:|SER:BDG-00002-2026', 'CNT-BDG|MAT:7', '', '   ', 'Jean Dupont', 'CNT-BDG|MAT:1|SER: BDG-00001-2026 '].map((t) => [t, PR.lireBadgeQR(t)]),
      };
    });

    /* ------------------------------------------------------------------ VÉRIFIER UN BADGE */
    sortie.verification = await m.page.evaluate(async () => { try { H.reposer();
      const S = SIGH.store; const col = S.collection('badges');
      const out = { cas: [] };
      const root = await H.monter('m10-badges-verification');
      out.ecran = { onglets: H.onglets(root), cartes: H.cartes(root), notes: H.notes(root), boutons: H.boutons(root), champs: [...root.querySelectorAll('label.label')].map((l) => H.norm(l.innerText)), indice: root.querySelector('input').placeholder, retires: H.tableaux(root), texte: H.norm(root.innerText) };
      const champ = root.querySelector('input'); const verifier = H.bouton(root, 'Vérifier');
      const lire = () => { const c = root.querySelector('.rounded-xl.border'); return c ? { texte: H.norm(c.innerText), classe: c.className.match(/border-(success|warning|danger)-300/)[1], img: !!c.querySelector('img') } : null; };
      async function cas(nom, saisie, avant, apres) {
        const restaure = avant ? avant() : null;
        champ.value = saisie; champ.dispatchEvent(new Event('input'));
        H.viderToasts(); verifier.click(); await H.dormir(150);
        out.cas.push({ nom, saisie, reponse: lire(), toasts: H.toasts(), audit: saisie.trim() ? H.audit0() : null });
        if (restaure) restaure();
      }
      const un = (n) => col.all().find((b) => b.numero === n);
      await cas('valide, par le numéro', 'BDG-00001-2026');
      await cas('valide, par la charge utile du QR', 'CNT-BDG|MAT:1|SER:BDG-00001-2026');
      await cas('valide, numéro en minuscules et espaces', '  bdg-00002-2026 ');
      await cas('inconnu', 'BDG-99999-2026');
      await cas('texte quelconque', 'Jean Dupont');
      await cas('QR incohérent : matricule contredit', 'CNT-BDG|MAT:999|SER:BDG-00001-2026');
      await cas('QR sans matricule', 'CNT-BDG|MAT:|SER:BDG-00001-2026');
      const e1 = un('BDG-00003-2026') || col.all()[2];
      await cas('expiré', e1.numero, () => { const o = e1.expireLe; e1.expireLe = '2026-10-29'; return () => { e1.expireLe = o; }; });
      await cas('expire aujourd’hui : encore valide', e1.numero, () => { const o = e1.expireLe; e1.expireLe = '2026-10-30'; return () => { e1.expireLe = o; }; });
      const e2 = col.all().find((b) => b.etat === 'a_editer');
      await cas('non remis (à éditer)', e2.numero);
      const e3 = col.all().find((b) => b.etat === 'edite');
      await cas('édité mais non remis : valide', e3.numero);
      const e4 = col.all().find((b) => b.etat === 'remis' && b.numero !== 'BDG-00001-2026');
      await cas('retiré — perte', e4.numero, () => { const a = [e4.etat, e4.motifRetrait, e4.retireLe]; e4.etat = 'perdu'; e4.motifRetrait = 'Perte'; e4.retireLe = '2026-10-01'; return () => { [e4.etat, e4.motifRetrait, e4.retireLe] = a; }; });
      await cas('retiré — sans motif ni date', e4.numero, () => { const a = [e4.etat, e4.motifRetrait, e4.retireLe]; e4.etat = 'retire'; e4.motifRetrait = null; e4.retireLe = null; return () => { [e4.etat, e4.motifRetrait, e4.retireLe] = a; }; });
      await cas('retiré ET expiré : le retrait prime', e4.numero, () => { const a = [e4.etat, e4.expireLe]; e4.etat = 'retire'; e4.expireLe = '2020-01-01'; return () => { [e4.etat, e4.expireLe] = a; }; });
      await cas('badge photographié (photo)', e4.numero, () => { e4.photo = 'data:image/png;base64,AAAA'; return () => { delete e4.photo; }; });
      await cas('saisie vide', '');
      await cas('saisie d’espaces', '   ');
      // le journal : plafonné à 400, la sonde lit la dernière entrée
      out.journalLongueur = S.raw().audit.length;
      // la carte des retirés, avec trois badges retirés (ordre par date de retrait, plus récent d'abord, dix au plus)
      const sauve = col.all().map((b) => [b, b.etat, b.motifRetrait, b.retireLe]);
      const retire = (b, m, d) => { b.etat = 'retire'; b.motifRetrait = m; b.retireLe = d; };
      const [b1, b2, b3] = col.all().slice(3, 6); retire(b1, 'Vol', '2026-09-01'); retire(b2, 'Départ de l’agent', '2026-10-15'); retire(b3, null, null);
      H.retirer(root);
      const root2 = await H.monter('m10-badges-verification');
      out.retiresTrois = H.tableaux(root2);
      sauve.forEach(([b, e, mo, d]) => { b.etat = e; b.motifRetrait = mo; b.retireLe = d; });
      H.retirer(root2);
      return out;
      } catch (e) { return { erreur: String(e && e.stack || e) }; }
    });

    /* ------------------------------------------------------------------ PLANCHE D'IMPRESSION */
    sortie.impression = await m.page.evaluate(async () => { try { H.reposer();
      const S = SIGH.store; const col = S.collection('badges');
      const out = {};
      const root = await H.monter('m10-badges-impression');
      out.ecran = H.lireEcran(root);
      out.lignes = H.lignesPage(root);
      out.filtres = H.filtres(root);
      out.boutonsLigne = H.boutonsDe(root.querySelector('tbody tr'));
      // sélection : onze badges → deux feuilles (dix puis un)
      const cases = () => [...root.querySelectorAll('tbody input[type=checkbox]')];
      for (let i = 0; i < 14; i++) { cases()[i].click(); await H.dormir(60); }
      await H.dormir(200);
      out.apresSelection = { boutons: H.boutons(root), texte: H.norm(root.innerText).slice(0, 400), cochees: cases().filter((c) => c.checked).length };
      window.__planches.length = 0;
      H.bouton(root, 'Imprimer la planche').click(); await H.dormir(250);
      out.planches = H.propre(window.__planches);
      // ordre : « dans l'ordre du tableau » ; cases cochées sur la page 1 seulement (douze lignes par page, quinze demandées → toutes)
      out.ordreTableau = H.lignesPage(root).map((l) => l.filter(Boolean)[0]);
      window.__badges.length = 0;
      H.icone(H.ligneDe(root, 'BDG-00005'), 'Imprimer la carte seule').click(); await H.dormir(150);
      out.carteSeule = H.propre(window.__badges);
      // un badge retiré n'est jamais proposé ; une photo fait passer « À coller » à « Oui »
      const b = col.all().find((x) => x.numero === 'BDG-00002-2026'); b.photo = 'data:image/png;base64,AAAA'; const e = b.etat; b.etat = 'retire';
      H.retirer(root);
      const root2 = await H.monter('m10-badges-impression');
      out.sansRetire = { lignes: H.lignesPage(root2).length, texte: H.norm(root2.innerText).includes('BDG-00002-2026') };
      b.etat = e; H.retirer(root2);
      const root3 = await H.monter('m10-badges-impression');
      out.avecPhoto = H.lignesPage(root3).find((l) => l.join(' ').includes('BDG-00002-2026'));
      H.retirer(root3); delete b.photo;
      return out;
      } catch (e) { return { erreur: String(e && e.stack || e) }; }
    });

    /* ------------------------------------------------------------------ MODÈLES DE BADGE */
    sortie.modeles = await m.page.evaluate(async () => { try { H.reposer();
      const S = SIGH.store; const col = S.collection('modelesBadge');
      const out = { jeu: H.propre(col.all()) };
      const root = await H.monter('m10-badges-modeles');
      out.ecran = H.lireEcran(root);
      out.lignes = H.lignesPage(root);
      out.boutonsLigne = H.boutonsDe(root.querySelector('tbody tr'));
      H.icone(root.querySelector('tbody tr'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      H.bouton(root, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, formats: H.optsDe('format'), orientations: H.optsDe('orientation'), zones: H.optsDe('zones') };
      ['libelle', 'format', 'orientation', 'zones', 'mentionsVerso', 'defaut'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(250);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('libelle', 'Badge visiteur — portrait'); H.poser('orientation', 'portrait'); H.poser('zones', ['photo', 'nom', 'qr']);
      H.poser('mentionsVerso', 'Badge à restituer en sortant.\n\n  À porter visiblement.  ');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      const nouv = col.all().find((x) => x.libelle === 'Badge visiteur — portrait');
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(nouv), total: col.all().length };
      await H.chercher(root, 'visiteur');
      out.creation.apres = { lignes: H.lignesPage(root), onglets: H.onglets(root) };
      H.icone(H.ligneDe(root, 'visiteur'), 'Consulter').click(); await H.dormir(300);
      out.creation.detail = H.tiroir(); H.fermerTout();
      // zones vides : refus (required sur le multiselect)
      H.icone(H.ligneDe(root, 'visiteur'), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['libelle', 'format', 'orientation', 'zones', 'mentionsVerso', 'defaut'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('zones', []); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(250);
      out.modification.refusZones = { toasts: H.toasts(), fiche: H.net(nouv) };
      H.poser('zones', ['nom', 'fonction']); H.poser('defaut', true); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.id === nouv.id)), autres: col.all().filter((x) => x.id !== nouv.id).map((x) => [x.id, x.defaut]) };
      H.icone(H.ligneDe(root, 'visiteur'), 'Archiver').click(); await H.confirmer('Doublon');
      await H.chercher(root, '');
      out.archivage = { fiche: H.net(col.all().find((x) => x.id === nouv.id)), onglets: H.onglets(root), lignes: H.lignesPage(root) };
      H.retirer(root);
      return out;
      } catch (e) { return { erreur: String(e && e.stack || e) }; }
    });

    /* ------------------------------------------------------------------ REGISTRE DES BADGES */
    sortie.badges = await m.page.evaluate(async () => { try { H.reposer();
      const S = SIGH.store; const col = S.collection('badges');
      const out = {};
      let root = await H.monter('m10-badges');
      out.ecran = H.lireEcran(root);
      out.lignes = H.lignesPage(root);
      out.filtres = H.filtres(root);
      out.boutonsParEtat = {};
      for (const tr of root.querySelectorAll('tbody tr')) {
        const n = H.norm(tr.children[0].innerText).split(' ')[0]; const b = col.all().find((x) => x.numero === n);
        if (b && !out.boutonsParEtat[b.etat]) out.boutonsParEtat[b.etat] = H.boutonsDe(tr);
      }
      out.parOnglet = await H.parOnglet(root);
      root.querySelector('.tab').click(); await H.dormir(150);
      // consultation (tiroir) : un badge remis
      H.icone(H.ligneDe(root, 'BDG-00014'), 'Consulter le badge').click(); await H.dormir(300);
      out.tiroir = H.tiroir(); out.tiroirSvg = !!document.querySelector('[role=dialog] svg'); H.fermerTout();
      window.__badges.length = 0;
      H.icone(H.ligneDe(root, 'BDG-00014'), 'Imprimer la carte').click(); await H.dormir(150);
      out.impression = H.propre(window.__badges);
      // marquer remis (état « édité »)
      const edite = col.all().find((b) => b.etat === 'edite');
      H.viderToasts();
      H.icone(H.ligneDe(root, edite.numero), 'Marquer remis à l’agent').click(); await H.dormir(250);
      out.remis = { modale: H.modale() };
      await H.confirmerBtn('Remis');
      out.remis.toasts = H.toasts(); out.remis.fiche = H.net(col.all().find((b) => b.id === edite.id)); out.remis.numero = edite.numero;
      // retrait : perte → « perdu » ; départ → « retiré »
      const retire = async (numero, motif) => {
        H.icone(H.ligneDe(root, numero), 'Retirer le badge').click(); await H.dormir(300);
        const r = { champs: H.champs(), motifs: H.optsDe('motifRetrait'), defaut: H.valeur('retireLe'), modale: H.modale().slice(0, 230) };
        r.motifDefaut = H.valeur('motifRetrait');
        H.poser('motifRetrait', motif); H.poser('observation', 'Signalé à la RH.');
        H.viderToasts(); H.cliquer('Retirer le badge'); await H.dormir(300);
        r.fiche = H.net(col.all().find((b) => b.numero.startsWith(numero))); r.toasts = H.toasts();
        return r;
      };
      out.retraitPerte = await retire('BDG-00013', 'Perte');
      out.retraitDepart = await retire('BDG-00012', 'Départ de l’agent');
      out.retraitVol = await retire('BDG-00011', 'Vol');
      out.retraitReedition = await retire('BDG-00010', 'Réédition — remplacement');
      out.apresRetraits = H.lireEcran(root);
      // onglet des retirés
      [...root.querySelectorAll('.tab')][1].click(); await H.dormir(200);
      out.retires = { lignes: H.lignesPage(root), boutons: H.boutonsDe(root.querySelector('tbody tr')), tableaux: H.tableaux(root), filtres: H.filtres(root), texte: H.norm(root.innerText).slice(0, 300) };
      // émission refusée : l'agent porte déjà un badge (le premier est NOMMÉ)
      [...root.querySelectorAll('.tab')][0].click(); await H.dormir(200);
      H.bouton(root, 'Émettre un badge').click(); await H.dormir(300);
      out.emission = { modale: H.modale().slice(0, 200), champs: H.champs(), defauts: {}, modeles: H.optsDe('modeleId'), etats: H.optsDe('etat'), agents: (H.optsDe('personnelId') || []).length, premier: (H.optsDe('personnelId') || [])[0] };
      ['personnelId', 'modeleId', 'emisLe', 'expireLe', 'etat'].forEach((n) => { out.emission.defauts[n] = H.valeur(n); });
      const porteur = col.all().find((b) => b.etat === 'remis' && b.numero === 'BDG-00002-2026');
      H.poser('personnelId', porteur.personnelId); H.viderToasts(); H.cliquer('Émettre le badge'); await H.dormir(250);
      out.emission.refusDejaPorteur = { toasts: H.toasts(), total: col.all().length, premier: porteur.numero };
      // émission acceptée : un agent SANS badge (celui du badge perdu, BDG-00013)
      const perdu = col.all().find((b) => b.numero.startsWith('BDG-00013'));
      H.poser('personnelId', perdu.personnelId); H.poser('emisLe', '2026-10-30'); H.poser('expireLe', '2028-10-30'); H.poser('etat', 'remis');
      const avant = new Set(col.all().map((b) => b.id));
      H.viderToasts(); H.cliquer('Émettre le badge'); await H.dormir(300);
      const nouveau = col.all().find((b) => !avant.has(b.id));
      out.emission.reussie = { toasts: H.toasts(), fiche: nouveau ? H.net(nouveau) : null, total: col.all().length };
      // émission d'un remplacement depuis l'onglet des retirés : l'agent est pré-sélectionné
      [...root.querySelectorAll('.tab')][1].click(); await H.dormir(200);
      H.icone(H.ligneDe(root, 'BDG-00012'), 'Émettre un remplacement').click(); await H.dormir(300);
      out.remplacement = { personnelId: H.valeur('personnelId'), attendu: col.all().find((b) => b.numero.startsWith('BDG-00012')).personnelId, etat: H.valeur('etat'), expireLe: H.valeur('expireLe') };
      H.fermerTout();
      // émission depuis « Agents sans badge »
      [...root.querySelectorAll('.tab')][2].click(); await H.dormir(200);
      out.sansBadge = { lignes: H.lignesPage(root), boutons: H.boutonsDe(root.querySelector('tbody tr')), tableaux: H.tableaux(root) };
      const premierSans = root.querySelector('tbody tr'); const bouton = [...premierSans.querySelectorAll('button')].find((b) => /Émettre/.test(b.textContent));
      bouton.click(); await H.dormir(300);
      out.sansBadge.preselection = H.valeur('personnelId'); out.sansBadge.agentLigne = H.norm(premierSans.innerText);
      H.fermerTout();
      out.final = col.all().map((b) => H.net(b));
      H.retirer(root);
      return out;
      } catch (e) { return { erreur: String(e && e.stack || e) }; }
    });

    /* ------------------------------------------------------------------ ÉVÉNEMENTS DU PERSONNEL */
    sortie.evenements = await m.page.evaluate(async () => { try { H.reposer();
      const S = SIGH.store; const col = S.collection('evenements'); const parts = S.collection('participations');
      const out = {};
      let root = await H.monter('m10-evenements');
      window.__graphes.length = 0;
      H.retirer(root); root = await H.monter('m10-evenements');
      out.ecran = H.lireEcran(root); out.lignes = H.lignesPage(root); out.graphes = H.graphes(); out.cartesTexte = H.cartesTexte(root).map((t) => t.slice(0, 80));
      out.filtres = H.filtres(root); out.boutonsLigne = H.boutonsDe(root.querySelector('tbody tr'));
      out.source = H.norm(root.innerText).slice(-170);
      // lien profond
      window.__go.length = 0; H.icone(root.querySelector('tbody tr'), 'Voir les participations').click(); await H.dormir(100);
      out.go = H.propre(window.__go);
      // impression de la liste de collecte
      window.__etats.length = 0; H.icone(root.querySelector('tbody tr'), 'Imprimer la liste de collecte').click(); await H.dormir(200);
      out.collecte = H.propre(window.__etats[0]);
      // création : tout le personnel hors bénéficiaire
      H.bouton(root, 'Nouvel événement').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 420), champs: H.champs(), defauts: {}, natures: H.optsDe('nature'), beneficiaires: (H.optsDe('beneficiaireId') || []).length, premier: (H.optsDe('beneficiaireId') || [])[0], portees: H.optsDe('portee'), modes: H.optsDe('modeParDefaut') };
      ['nature', 'libelle', 'beneficiaireId', 'portee', 'participants', 'date', 'montantParAgent', 'periodePaiement', 'modeParDefaut', 'observation'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer et engendrer les participations'); await H.dormir(250);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('nature', 'mariage'); H.poser('libelle', 'Mariage de KORA Salifou'); H.poser('beneficiaireId', 'EMP05'); H.poser('montantParAgent', '1500');
      H.poser('periodePaiement', '2026-12'); H.poser('modeParDefaut', 'comptant'); H.poser('observation', 'Cotisation de service.');
      const avantE = new Set(col.all().map((x) => x.id)); const avantP = new Set(parts.all().map((x) => x.id));
      H.viderToasts(); H.cliquer('Créer et engendrer les participations'); await H.dormir(400);
      const evt = col.all().find((x) => !avantE.has(x.id)); const nouvelles = parts.all().filter((x) => !avantP.has(x.id));
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(evt), nbParticipations: nouvelles.length, premiere: H.net(nouvelles[0]), agents: nouvelles.map((p) => p.employeId), beneficiaireAbsent: !nouvelles.some((p) => p.employeId === 'EMP05'), audit: H.audit0() };
      // création à sélection d'agents
      H.bouton(root, 'Nouvel événement').click(); await H.dormir(300);
      H.poser('nature', 'deces'); H.poser('libelle', 'Décès du père de TEPA Séraphine'); H.poser('beneficiaireId', 'EMP10'); H.poser('portee', 'selection'); H.poser('participants', ['EMP10', 'EMP11', 'EMP12']);
      H.poser('montantParAgent', '0'); H.poser('periodePaiement', '2026-11');
      const avantE2 = new Set(col.all().map((x) => x.id)); const avantP2 = new Set(parts.all().map((x) => x.id));
      H.cliquer('Créer et engendrer les participations'); await H.dormir(400);
      const evt2 = col.all().find((x) => !avantE2.has(x.id)); const n2 = parts.all().filter((x) => !avantP2.has(x.id));
      out.selection = { fiche: H.net(evt2), participants: n2.map((p) => [p.employeId, p.montant]), toasts: H.toasts() };
      // sélection vide : tout le personnel cotise (repli du moteur)
      H.bouton(root, 'Nouvel événement').click(); await H.dormir(300);
      H.poser('nature', 'bapteme'); H.poser('libelle', 'Baptême test'); H.poser('beneficiaireId', 'EMP11'); H.poser('portee', 'selection'); H.poser('periodePaiement', '2026-11');
      const avantP3 = new Set(parts.all().map((x) => x.id)); const avantE3 = new Set(col.all().map((x) => x.id));
      H.cliquer('Créer et engendrer les participations'); await H.dormir(400);
      out.selectionVide = { participants: parts.all().filter((x) => !avantP3.has(x.id)).length, fiche: H.net(col.all().find((x) => !avantE3.has(x.id))) };
      // modification : des participations déjà réglées sont intactes
      const sur = col.all().find((x) => x.libelle === 'Mariage de KORA Salifou');
      const miens = parts.all().filter((p) => p.evenementId === sur.id);
      miens[0].statutPaiement = 'paye'; miens[0].datePaiement = '2026-10-30'; miens[1].statutPaiement = 'paye'; miens[1].datePaiement = '2026-10-30';
      H.retirer(root); root = await H.monter('m10-evenements');
      await H.chercher(root, 'KORA');
      out.apresReglements = { lignes: H.lignesPage(root), kpis: H.kpis(root) };
      H.icone(H.ligneDe(root, 'KORA'), 'Modifier l’événement').click(); await H.dormir(300);
      out.modification = { modale: H.modale().slice(0, 520), valeurs: {} };
      ['nature', 'libelle', 'beneficiaireId', 'portee', 'participants', 'date', 'montantParAgent', 'periodePaiement', 'modeParDefaut', 'observation'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('montantParAgent', '2000'); H.poser('periodePaiement', '2027-01'); H.poser('libelle', 'Mariage de KORA S.');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(400);
      out.modification.resultat = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.id === sur.id)),
        reglees: parts.all().filter((p) => p.evenementId === sur.id && p.statutPaiement === 'paye').map((p) => [p.montant, p.periodeRetenue, p.evenementLibelle]),
        dues: parts.all().filter((p) => p.evenementId === sur.id && p.statutPaiement !== 'paye').slice(0, 2).map((p) => [p.montant, p.periodeRetenue, p.evenementLibelle, p.nature]),
        nbDues: parts.all().filter((p) => p.evenementId === sur.id && p.statutPaiement !== 'paye').length };
      // annulation : trois situations
      // (1) des participations réglées
      await H.chercher(root, 'KORA');
      H.icone(H.ligneDe(root, 'KORA'), 'Annuler l’événement').click(); await H.dormir(300);
      out.annulationReglee = { modale: H.modale() };
      H.viderToasts(); await H.confirmerBtn('Annuler l’événement', 'Doublon');
      out.annulationReglee.resultat = { toasts: H.toasts(), evenement: H.net(col.all().find((x) => x.id === sur.id)), archivees: parts.all().filter((p) => p.evenementId === sur.id && p.statut === 'archive').length, reglees: parts.all().filter((p) => p.evenementId === sur.id && p.statut !== 'archive').length };
      // (2) aucune réglée
      await H.chercher(root, 'Baptême');
      H.icone(H.ligneDe(root, 'Baptême'), 'Annuler l’événement').click(); await H.dormir(300);
      out.annulationDue = { modale: H.modale() };
      H.viderToasts(); await H.confirmerBtn('Annuler l’événement', 'Erreur');
      out.annulationDue.resultat = { toasts: H.toasts() };
      // (3) aucune participation
      col.insert({ reference: 'EVT-9999', nature: 'autre', libelle: 'Sans participation', beneficiaireId: 'EMP01', beneficiaire: 'BASSONGUI Chabi Séko', date: '2026-10-01', montantParAgent: 1000, periodePaiement: '2026-10', modeParDefaut: 'salaire', portee: 'tous' });
      H.retirer(root); root = await H.monter('m10-evenements'); await H.chercher(root, 'Sans participation');
      out.sansParticipation = { ligne: H.lignesPage(root), kpis: H.kpis(root) };
      H.icone(H.ligneDe(root, 'Sans participation'), 'Annuler l’événement').click(); await H.dormir(300);
      out.annulationVide = { modale: H.modale() };
      H.viderToasts(); await H.confirmerBtn('Annuler l’événement', 'Doublon');
      out.annulationVide.resultat = { toasts: H.toasts() };
      // filtre de nature et vide
      await H.chercher(root, '');
      out.apresAnnulations = H.lireEcran(root);
      out.final = col.all().map((x) => H.net(x));
      H.retirer(root);
      return out;
      } catch (e) { return { erreur: String(e && e.stack || e) }; }
    });

    /* ------------------------------------------------------------------ FRAIS DE PARTICIPATION */
    sortie.participations = await m.page.evaluate(async () => { try { H.reposer();
      const S = SIGH.store; const col = S.collection('participations'); const evts = S.collection('evenements');
      const out = {};
      window.__graphes.length = 0;
      let root = await H.monter('m10-participations');
      const L = async (t) => { await H.chercher(root, t); return H.ligneDe(root, t); };
      out.ouverture = { ecran: H.lireEcran(root), lignes: H.lignesPage(root), selects: H.selects(root), graphes: H.graphes(), cartes: H.cartesTexte(root).map((t) => t.slice(0, 90)), boutonsLigne: H.boutonsDe(root.querySelector('tbody tr')) };
      const premierEvt = evts.all().find((e) => col.all().filter((p) => p.evenementId === e.id && p.mode === 'comptant').length >= 2 && col.all().some((p) => p.evenementId === e.id && p.mode === 'salaire'));
      // filtres : événement, mode, état
      const filtre = async (o) => {
        for (const k of Object.keys(o)) await H.regler(root, k, o[k]);
        const r = { regles: o, kpis: H.kpis(root), lignes: H.lignesPage(root).length, premiere: H.lignesPage(root)[0] || null, texte: H.norm(root.innerText).slice(0, 700), cartes: H.cartes(root) };
        return r;
      };
      out.parEvenement = await filtre({ 'Événement': premierEvt.id });
      out.parMode = await filtre({ 'Événement': '', 'Mode de règlement': 'comptant' });
      out.parEtat = await filtre({ 'Mode de règlement': '', 'État': 'paye' });
      out.videEtat = await filtre({ 'État': 'paye' });
      await H.regler(root, 'État', '');
      // des états variés : on pose deux participations réglées, une au comptant avec reçu, une retenue
      const evt = premierEvt; const mes = col.all().filter((p) => p.evenementId === evt.id);
      const nom = (p) => p.agent;
      const du_salaire = mes.find((p) => p.mode === 'salaire'); const du_comptant = mes.find((p) => p.mode === 'comptant');
      await H.regler(root, 'Événement', evt.id);
      // lien profond : la sélection se lit à l'ouverture
      H.retirer(root); location.hash = '#evenement=' + evt.id; root = await H.monter('m10-participations');
      out.lienProfond = H.selects(root).map((s) => [s[0], s[1]]); location.hash = '';
      H.retirer(root); root = await H.monter('m10-participations');
      await H.regler(root, 'Événement', evt.id);
      await H.chercher(root, nom(du_salaire)); const bs = H.boutonsDe((await L(nom(du_salaire))));
      await H.chercher(root, nom(du_comptant)); const bc = H.boutonsDe((await L(nom(du_comptant))));
      out.boutonsParEtat = { salaire: bs, comptant: bc };
      // changer de mode : salaire → comptant
      await H.chercher(root, nom(du_salaire));
      H.icone((await L(nom(du_salaire))), 'Changer de mode de règlement').click(); await H.dormir(300);
      out.changerMode = { modale: H.modale().slice(0, 400), champs: H.champs(), defauts: { mode: H.valeur('mode'), periodeRetenue: H.valeur('periodeRetenue') }, modes: H.optsDe('mode') };
      H.poser('mode', 'comptant'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.changerMode.versComptant = { toasts: H.toasts(), fiche: H.net(col.all().find((p) => p.id === du_salaire.id)) };
      H.icone((await L(nom(du_salaire))), 'Changer de mode de règlement').click(); await H.dormir(300);
      H.poser('mode', 'salaire'); H.poser('periodeRetenue', '2026-12'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.changerMode.versSalaire = { toasts: H.toasts(), fiche: H.net(col.all().find((p) => p.id === du_salaire.id)) };
      H.icone((await L(nom(du_salaire))), 'Changer de mode de règlement').click(); await H.dormir(300);
      H.poser('mode', 'salaire'); H.poser('periodeRetenue', ''); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.changerMode.salaireSansMois = { toasts: H.toasts(), fiche: H.net(col.all().find((p) => p.id === du_salaire.id)) };
      // encaisser au comptant
      await H.chercher(root, nom(du_comptant));
      H.icone((await L(nom(du_comptant))), 'Encaisser au comptant').click(); await H.dormir(300);
      out.encaisser = { modale: H.modale().slice(0, 500), champs: H.champs(), defauts: { montantVerse: H.valeur('montantVerse'), datePaiement: H.valeur('datePaiement'), observation: H.valeur('observation') } };
      H.poser('montantVerse', ''); H.viderToasts(); H.cliquer('Valider l’encaissement'); await H.dormir(250);
      out.encaisser.refus = { toasts: H.toasts(), fiche: H.net(col.all().find((p) => p.id === du_comptant.id)) };
      H.poser('montantVerse', '1200'); H.poser('observation', 'Versé en main propre.');
      H.viderToasts(); H.cliquer('Valider l’encaissement'); await H.dormir(300);
      out.encaisser.reussi = { toasts: H.toasts(), fiche: H.net(col.all().find((p) => p.id === du_comptant.id)), audit: H.audit0(), ligne: H.lignesPage(root)[0], boutons: H.boutonsDe((await L(nom(du_comptant)))) };
      // second encaissement : le reçu suit la série
      const autre = mes.find((p) => p.mode === 'comptant' && p.id !== du_comptant.id && p.statutPaiement !== 'paye');
      if (autre) {
        await H.chercher(root, nom(autre));
        H.icone((await L(nom(autre))), 'Encaisser au comptant').click(); await H.dormir(300);
        H.cliquer('Valider l’encaissement'); await H.dormir(300);
        out.encaisser.second = { fiche: H.net(col.all().find((p) => p.id === autre.id)) };
      }
      // confirmer la retenue sur salaire
      await H.chercher(root, nom(du_salaire));
      H.icone((await L(nom(du_salaire))), 'Confirmer la retenue sur salaire').click(); await H.dormir(300);
      out.retenue = { modale: H.modale() };
      H.viderToasts(); await H.confirmerBtn('Confirmer la retenue');
      out.retenue.resultat = { toasts: H.toasts(), fiche: H.net(col.all().find((p) => p.id === du_salaire.id)), ligne: H.lignesPage(root)[0] };
      // reçu imprimable
      window.__etats.length = 0;
      await H.chercher(root, nom(du_comptant));
      H.icone((await L(nom(du_comptant))), 'Imprimer le reçu').click(); await H.dormir(200);
      out.recu = H.propre(window.__etats[0]);
      window.__etats.length = 0;
      await H.chercher(root, nom(du_salaire));
      H.icone((await L(nom(du_salaire))), 'Imprimer le reçu').click(); await H.dormir(200);
      out.recuRetenue = H.propre(window.__etats[0]);
      // annuler le règlement : motif obligatoire
      await H.chercher(root, nom(du_comptant));
      H.icone((await L(nom(du_comptant))), 'Annuler le règlement').click(); await H.dormir(300);
      out.annulation = { modale: H.modale() };
      H.viderToasts(); await H.confirmerBtn('Annuler le règlement', 'Erreur de caisse');
      out.annulation.resultat = { toasts: H.toasts(), fiche: H.net(col.all().find((p) => p.id === du_comptant.id)), audit: H.audit0() };
      // état imprimé : filtré sur l'événement
      await H.chercher(root, '');
      window.__etats.length = 0; H.bouton(root, 'Imprimer l’état').click(); await H.dormir(200);
      out.etatEvenement = H.propre(window.__etats[0]);
      await H.regler(root, 'Événement', '');
      window.__etats.length = 0; H.bouton(root, 'Imprimer l’état').click(); await H.dormir(200);
      const e = H.propre(window.__etats[0]); out.etatTous = { titre: e.titre, sousTitre: e.sousTitre, cartouche: e.cartouche, signatures: e.signatures, nb: e.tableaux[0].lignes.length, premieres: e.tableaux[0].lignes.slice(0, 3), pied: e.tableaux[0].pied, entetes: e.tableaux[0].entetes, texte: e.texte };
      out.final = H.lireEcran(root).kpis;
      H.retirer(root);
      return out;
      } catch (e) { return { erreur: String(e && e.stack || e) }; }
    });

    /* ------------------------------------------------------------------ ASSURANCE DU PERSONNEL */
    sortie.assurance = await m.page.evaluate(async () => { try { H.reposer();
      const S = SIGH.store;
      const out = { periodes: {} };
      window.__graphes.length = 0;
      let root = await H.monter('m10-assurance-personnel');
      out.ouverture = { ecran: H.lireEcran(root), selects: H.selects(root), graphes: H.graphes(), cartes: H.cartesTexte(root).map((t) => t.slice(0, 120)), boutonsLigne: H.boutonsDe(root.querySelector('tbody tr')), filtres: H.filtres(root), lignes: H.lignesPage(root), source: H.norm(root.innerText).slice(-300) };
      for (const p of ['', '30', '90', '180', '365']) {
        await H.regler(root, 'Période', p);
        window.__graphes.length = 0;
        const cas = { kpis: H.kpis(root), lignes: H.lignesPage(root), nb: [...root.querySelectorAll('tbody tr')].length, cartes: H.cartes(root), texte: H.norm(root.innerText).slice(0, 900) };
        out.periodes[p || 'toujours'] = cas;
        window.__etats.length = 0; H.bouton(root, 'Imprimer l’état').click(); await H.dormir(200);
        out.periodes[p || 'toujours'].etat = H.propre(window.__etats[0]);
      }
      await H.regler(root, 'Période', '');
      out.parFonction = {};
      for (const f of ['medecin', 'infirmier', 'securite', 'sage_femme']) {
        await H.regler(root, 'Fonction', f);
        out.parFonction[f] = { kpis: H.kpis(root), lignes: H.lignesPage(root), texte: H.norm(root.innerText).slice(0, 500) };
      }
      await H.regler(root, 'Fonction', 'caissiere');
      out.vide = { texte: H.norm(root.innerText).slice(0, 600), kpis: H.kpis(root), cartes: H.cartes(root) };
      await H.regler(root, 'Fonction', '');
      // filtre de nature dans le tableau
      const sel = [...root.querySelectorAll('select')].find((s) => s.getAttribute('aria-label') === 'Nature');
      if (sel) { sel.value = 'Analyse'; sel.dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(200); out.natureAnalyse = { lignes: H.lignesPage(root), nb: root.querySelectorAll('tbody tr').length }; }
      if (sel) { sel.value = ''; sel.dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(200); }
      // ouvrir le dossier : navigation vers le répertoire
      window.__go.length = 0; H.icone(root.querySelector('tbody tr'), 'Ouvrir le dossier du patient').click(); await H.dormir(100);
      out.go = H.propre(window.__go);
      // sans saisie : aucune commande d'écriture
      out.commandes = H.boutons(root);
      H.retirer(root);
      return out;
      } catch (e) { return { erreur: String(e && e.stack || e) }; }
    });

    /* ------------------------------------------------------------------ SÉCURITÉ & ENTRETIEN */
    sortie.securite = await m.page.evaluate(async () => { try { H.reposer();
      const S = SIGH.store; const plan = S.collection('planning'); const pers = S.collection('personnel');
      const out = {};
      window.__graphes.length = 0;
      let root = await H.monter('m10-securite-entretien');
      const tables = [...root.querySelectorAll('table')];
      out.ecran = H.lireEcran(root);
      out.grille = { entetes: [...tables[0].querySelectorAll('thead th')].map((t) => H.norm(t.innerText)), lignes: [...tables[0].querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => H.norm(td.innerText))), titres: [...tables[0].querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => { const b = td.querySelector('button, span.inline-block'); return b ? (b.title || '') : ''; })) };
      out.agents = { lignes: H.lignesPage(tables[1].closest('.card')), boutons: H.boutonsDe(tables[1].querySelector('tbody tr')) };
      out.graphes = H.graphes(); out.cartesTexte = H.cartesTexte(root).map((t) => t.slice(0, 160));
      out.texte = H.norm(root.innerText);
      // cellules : les types proposés suivent la FONCTION
      const agentSec = pers.all().find((e) => e.fonction === 'securite'); const agentEnt = pers.all().find((e) => e.fonction === 'entretien');
      const cellule = (nom, i) => { const tr = [...root.querySelectorAll('tbody tr')].find((x) => H.norm(x.children[0].innerText) === nom); return tr.children[2 + i].querySelector('button'); };
      const ouvrir = async (agent, i) => { cellule(agent.nomComplet, i).click(); await H.dormir(300); };
      const aujourdhui = 3;
      await ouvrir(agentSec, 12);
      out.modaleSecurite = { modale: H.modale().slice(0, 380), champs: H.champs(), types: H.optsDe('type'), defaut: H.valeur('type'), boutons: [...document.querySelectorAll('[role=dialog] button')].map((b) => H.norm(b.textContent || b.getAttribute('aria-label'))).filter(Boolean) };
      H.fermerTout();
      await ouvrir(agentEnt, 12);
      out.modaleEntretien = { types: H.optsDe('type'), defaut: H.valeur('type'), modale: H.modale().slice(0, 300) };
      H.fermerTout();
      // affecter une vacation sur une case vide, puis la modifier, puis la retirer
      const vide = (agent) => { for (let i = 0; i < 14; i++) { const j = new Date(2026, 9, 27 + i); const d = j.getFullYear() + '-' + String(j.getMonth() + 1).padStart(2, '0') + '-' + String(j.getDate()).padStart(2, '0'); if (!plan.all().some((p) => p.employeId === agent.id && p.date === d && p.statut !== 'archive')) return [i, d]; } return null; };
      const [iv, dv] = vide(agentSec);
      out.caseVide = { indice: iv, date: dv, texteCellule: H.norm(cellule(agentSec.nomComplet, iv).textContent) };
      await ouvrir(agentSec, iv);
      const avantP = new Set(plan.all().map((p) => p.id));
      H.poser('type', 'soiree'); H.poser('observation', 'Remplacement.'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      const cree = plan.all().find((p) => !avantP.has(p.id));
      out.affectation = { toasts: H.toasts(), fiche: H.net(cree), texteCellule: H.norm(cellule(agentSec.nomComplet, iv).textContent) };
      await ouvrir(agentSec, iv);
      out.modification = { modale: H.modale().slice(0, 300), defaut: H.valeur('type'), boutons: [...document.querySelectorAll('[role=dialog] button')].map((b) => H.norm(b.textContent || b.getAttribute('aria-label'))).filter(Boolean) };
      H.poser('type', 'repos24'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.resultat = { toasts: H.toasts(), fiche: H.net(plan.all().find((p) => p.id === cree.id)), texteCellule: H.norm(cellule(agentSec.nomComplet, iv).textContent) };
      await ouvrir(agentSec, iv);
      H.viderToasts(); H.dans('Retirer').click(); await H.dormir(300);
      out.retrait = { modale: H.modale() };
      await H.confirmerBtn('Retirer');
      out.retrait.resultat = { toasts: H.toasts(), fiche: H.net(plan.all().find((p) => p.id === cree.id)), texteCellule: H.norm(cellule(agentSec.nomComplet, iv).textContent) };
      // repos de 24 h qui suit une garde : une garde la veille interdit la suivante
      const [ig, dg] = (() => { for (let i = 1; i < 14; i++) { const [, d] = [0, (() => { const j = new Date(2026, 9, 27 + i); return j.getFullYear() + '-' + String(j.getMonth() + 1).padStart(2, '0') + '-' + String(j.getDate()).padStart(2, '0'); })()]; const v = new Date(2026, 9, 27 + i - 1); const dv2 = v.getFullYear() + '-' + String(v.getMonth() + 1).padStart(2, '0') + '-' + String(v.getDate()).padStart(2, '0'); if (!plan.all().some((p) => p.employeId === agentSec.id && (p.date === d || p.date === dv2))) return [i, d]; } return [null, null]; })();
      const veille = new Date(2026, 9, 27 + ig - 1); const dveille = veille.getFullYear() + '-' + String(veille.getMonth() + 1).padStart(2, '0') + '-' + String(veille.getDate()).padStart(2, '0');
      plan.insert({ date: dveille, employeId: agentSec.id, employe: agentSec.nomComplet, fonction: 'securite', service: 'Direction', type: 'garde', statut: 'validee' });
      H.retirer(root); root = await H.monter('m10-securite-entretien');
      const cell2 = (nom, i) => { const tr = [...root.querySelectorAll('tbody tr')].find((x) => H.norm(x.children[0].innerText) === nom); return tr.children[2 + i].querySelector('button'); };
      cell2(agentSec.nomComplet, ig).click(); await H.dormir(300);
      H.poser('type', 'garde'); H.viderToasts(); const nAvant = plan.all().length; H.cliquer('Enregistrer'); await H.dormir(250);
      out.incompatibilite = { jour: dg, veille: dveille, toasts: H.toasts(), ecrit: plan.all().length - nAvant, modaleOuverte: !!document.querySelector('[role=dialog]') };
      H.poser('type', 'soiree'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.incompatibilite.soireeApres = { toasts: H.toasts(), ecrit: plan.all().length - nAvant };
      // un agent d'entretien peut enchaîner (la règle ne vise que les gardes)
      // nouvel agent (K.creer sur la collection du personnel)
      H.bouton(root, 'Nouvel agent').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 200), champs: H.champs(), defauts: {}, fonctions: H.optsDe('fonction') };
      ['nomComplet', 'fonction', 'poste', 'dateEmbauche', 'salaireBase', 'telephone'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(250);
      out.creation.refus = { toasts: H.toasts() };
      H.poser('nomComplet', 'ADAM Ibrahim'); H.poser('fonction', 'entretien'); H.poser('salaireBase', '45000'); H.poser('telephone', '0190000000');
      const avantA = new Set(pers.all().map((e) => e.id));
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      const ag = pers.all().find((e) => !avantA.has(e.id));
      out.creation.creee = { toasts: H.toasts(), fiche: ag ? H.net(ag) : null, lignes: H.lignesPage(root).length };
      // second : la référence suit la série
      H.bouton(root, 'Nouvel agent').click(); await H.dormir(300);
      H.poser('nomComplet', 'BIO Mama'); const avantB = new Set(pers.all().map((e) => e.id)); H.cliquer('Créer'); await H.dormir(300);
      const ag2 = pers.all().find((e) => !avantB.has(e.id));
      out.creation.seconde = { fiche: ag2 ? H.net(ag2) : null };
      out.apresCreation = { kpis: H.kpis(root), grille: [...root.querySelectorAll('tbody tr')].length };
      // modification et archivage d'un agent
      const tabAgents = [...root.querySelectorAll('table')][1];
      const ligneAg = [...tabAgents.querySelectorAll('tbody tr')].find((tr) => H.norm(tr.innerText).includes('ADAM Ibrahim'));
      out.boutonsAgent = H.boutonsDe(ligneAg);
      H.icone(ligneAg, 'Modifier').click(); await H.dormir(300);
      out.modificationAgent = { valeurs: {} };
      ['nomComplet', 'fonction', 'poste', 'dateEmbauche', 'salaireBase', 'telephone'].forEach((n) => { out.modificationAgent.valeurs[n] = H.valeur(n); });
      H.poser('salaireBase', '47000'); H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modificationAgent.resultat = { toasts: H.toasts(), fiche: H.net(pers.all().find((e) => e.id === ag.id)) };
      const ligneAg2 = [...[...root.querySelectorAll('table')][1].querySelectorAll('tbody tr')].find((tr) => H.norm(tr.innerText).includes('ADAM Ibrahim'));
      H.icone(ligneAg2, 'Archiver').click(); await H.confirmer('Doublon');
      out.archivageAgent = { fiche: H.net(pers.all().find((e) => e.id === ag.id)), kpis: H.kpis(root) };
      // impression du planning
      window.__etats.length = 0; H.bouton(root, 'Imprimer le planning').click(); await H.dormir(250);
      out.impression = H.propre(window.__etats[0]);
      H.retirer(root);
      return out;
      } catch (e) { return { erreur: String(e && e.stack || e) }; }
    });

    sortie.erreurs = await m.page.evaluate(() => window.__erreurs);
    ecrire('packages/domaine/test/vecteurs/rhc.json', sortie);
    console.log('  erreurs de page : ' + sortie.erreurs.length);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
