/* =============================================================================
 * VECTEURS DE CFG (B) — cfg-centres-couts, cfg-regles, cfg-fiscalite, cfg-comptabilite, cfg-notifications, cfg-compte, cfg-modules, cfg-systeme, cfg-poste
 * -----------------------------------------------------------------------------
 * Les neuf écrans RÉELS de `assets/js/modules/configuration.js`, montés dans Chrome sur le JEU DU POSTE (horloge figée 30/10/2026 10 h), lus comme l'agent
 * les lit et PILOTÉS (création, bascules, confirmations avec motif, saisies refusées…). Les référentiels statiques qu'ils lisent (`D.*`) sont TIRÉS de la
 * maquette, jamais recopiés.
 *   SIGH_PORT_PHP=10377 flock /tmp/sigh-banc.lock node build/vecteurs-cfg-b.js   →   packages/domaine/test/vecteurs/cfb.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU = path.resolve(ROOT, '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
const NOMS_JEU = fs.readdirSync(JEU).filter((f) => f.endsWith('.json') && f !== 'referentiels.json').map((f) => f.replace(/\.json$/, ''));

(async () => {
  console.log('▶ Vecteurs de CFG (B) — neuf écrans');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Vrai = Date;
      window.__Vrai = Vrai;
      window.__FIXE = new Vrai(2026, 9, 30, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      window.__etats = []; window.__erreurs = []; window.addEventListener('error', (e) => window.__erreurs.push(String(e.message)));
      const setTimeoutReel = window.setTimeout.bind(window);
      window.setTimeout = (fn, ms, ...a) => (String(fn).includes('location.reload') ? 0 : setTimeoutReel(fn, ms, ...a));
      SIGH.ui.sonner = () => {};
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
      window.__go = []; SIGH.app.go = function (id, o) { window.__go.push([id, o || null]); };
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/configuration.js') });
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
        cartesTexte: (root) => [...root.querySelectorAll('.card')].map((c) => norm(c.innerText)),
        notes: (root) => [...root.querySelectorAll('.rounded-lg.border')].map((n) => norm(n.innerText)).filter((t) => t.length > 20),
        onglets: (root) => [...root.querySelectorAll('[role=tab]')].map((t) => norm(t.innerText)),
        fermerTout: () => document.querySelectorAll('[role=dialog], .modal-root, .drawer-root, .drawer-backdrop').forEach((x) => x.remove()),
        toasts: () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim())),
        viderToasts: () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; },
        bouton: (racine, texte) => [...racine.querySelectorAll('button')].find((b) => norm(b.textContent) === texte || b.getAttribute('aria-label') === texte || b.title === texte),
        poser: (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true })); },
        cliquer: (texte) => { const bs = [...document.querySelectorAll('button')].filter((b) => norm(b.textContent) === texte); bs[bs.length - 1].click(); },
        icone: (ligne, nom) => [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === nom),
        boutons: (racine) => [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
        modale: () => norm((document.querySelector('.modal-root, [role=dialog]') || { innerText: '' }).innerText),
        monter: async (id) => {
          const root = document.createElement('div'); document.body.appendChild(root);
          window.__etats.length = 0;
          SIGH.screens[id].render(root);
          await new Promise((r) => setTimeout(r, 300));
          return root;
        },
        retirer: (root) => { root.remove(); H.fermerTout(); },
        ligne: (racine, texte) => [...racine.querySelectorAll('tbody tr')].find((tr) => norm(tr.innerText).includes(texte)),
        audit0: () => { const a = H.propre(SIGH.store.raw().audit[0]); delete a.id; delete a.dateHeure; return a; },
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
        lireEcran: (root) => ({ kpis: H.kpis(root), onglets: H.onglets(root), cartes: H.cartes(root), tableaux: H.tableaux(root), notes: H.notes(root), boutons: H.boutons(root).slice(0, 40) }),
        parOnglet: async (root) => {
          const sortie = {};
          for (const t of [...root.querySelectorAll('[role=tab]')]) {
            t.click(); await H.dormir(150);
            const lab = norm(t.innerText);
            sortie[lab] = { texte: norm(root.innerText), kpis: H.kpis(root), tableaux: H.tableaux(root), notes: H.notes(root), cartes: H.cartes(root), boutons: H.boutons(root) };
          }
          return sortie;
        },
      };
    });

    /* Le JEU DU POSTE entier est posé dans le magasin de la maquette : ce que l'écran lit est ce que le poste lit. */
    const jeu = Object.fromEntries(NOMS_JEU.map((n) => [n, JSON.parse(fs.readFileSync(path.join(JEU, n + '.json'), 'utf8'))]));
    await m.page.evaluate((j) => {
      const S = SIGH.store;
      window.__jeu = j;
      for (const [nom, lignes] of Object.entries(j)) {
        const col = S.collection(nom);
        col.all().splice(0);
        // `all()` ne rend que les actives : on pousse TOUT dans le tableau brut (archivées comprises).
        const brut = S.raw()[nom];
        if (Array.isArray(brut)) { brut.splice(0); lignes.forEach((x) => brut.push(JSON.parse(JSON.stringify(x)))); }
      }
      SIGH.nav.invaliderRbac && SIGH.nav.invaliderRbac();
      SIGH.nav.invaliderModules && SIGH.nav.invaliderModules();
    }, jeu);

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-cfg-b.js — ne pas éditer. Horloge : 30/10/2026 10 h. Jeu : apps/poste/assets/donnees/jeu.' };
    const essayer = async (nom, f) => { try { sortie[nom] = await f(); } catch (e) { sortie[nom] = { erreur: String(e && e.stack || e) }; console.log('  ERREUR ' + nom + ' : ' + String(e && e.message || e)); } };

    /* ---------------------------------------------------------------- constantes (D.*, C.BRAND, NT.*, store) */
    await essayer('constantes', () => m.page.evaluate(() => {
      const D = SIGH.data, C = SIGH.core, S = SIGH.store, NT = SIGH.notifications, N = SIGH.nav;
      const ns = (x) => ({ reference: x.reference, version: x.version, dateEffet: x.dateEffet, statut: x.statut, objet: x.objet });
      return JSON.parse(JSON.stringify({
        sourcesVerite: D.SOURCES_VERITE, paramStock: D.PARAM_STOCK, famillesArticles: D.FAMILLES_ARTICLES, groupesArticles: D.GROUPES_ARTICLES,
        ns131: ns(D.NS131), ns132: ns(D.NS132),
        calendrierFiscal: D.CALENDRIER_FISCAL, montantsFiscaux: D.MONTANTS_FISCAUX,
        paramPaie: { cnss: D.PARAM_PAIE.cnss, vps: D.PARAM_PAIE.vps, ortb: D.PARAM_PAIE.ortb },
        brand: { nom: C.BRAND.nom, forme: C.BRAND.forme, ifu: C.BRAND.ifu, rccm: C.BRAND.rccm, autorisation: C.BRAND.autorisation, bp: C.BRAND.bp, devise: C.BRAND.devise, codeDevise: C.BRAND.codeDevise },
        profilsAudio: NT.PROFILS_AUDIO, defautsNotif: NT.DEFAUTS,
        essentielles: S.COLLECTIONS_ESSENTIELLES,
        mois: C.MOIS,
        roles: Object.keys(N.ROLES).map((r) => [r, N.ROLES[r].label, !!N.roleArchive(r)]),
        libelles: Object.fromEntries(Object.keys(window.__jeu).map((k) => [k, S.libelleCollection(k)])),
      }));
    }));

    /* ---------------------------------------------------------------- 1. cfg-centres-couts */
    await essayer('centres', () => m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = () => S.collection('centresCouts');
      const out = {};
      let root = await H.monter('cfg-centres-couts');
      out.lecture = H.lireEcran(root);
      out.avant = H.propre(col().all().map((x) => ({ code: x.code, libelle: x.libelle, type: x.type, responsable: x.responsable || null })));
      out.nbActifs = col().all().length; out.nbTous = S.raw().centresCouts.length;
      const creer = async (saisie) => {
        const avant = new Set(col().all().map((x) => x.id));
        H.bouton(root, 'Nouveau').click(); await H.dormir(150);
        out.champs = out.champs || [...document.querySelectorAll('[role=dialog] label')].map((l) => H.norm(l.innerText));
        Object.entries(saisie).forEach(([k, v]) => H.poser(k, v));
        H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
        const nouveaux = col().all().filter((x) => !avant.has(x.id));
        return { saisie, fiche: nouveaux.map(H.net), toasts: H.toasts(), kpis: H.kpis(root) };
      };
      out.creationSansCode = await creer({ libelle: 'Centre Test Alpha', type: 'support' });
      out.creationAvecCode = await creer({ libelle: 'Centre Test Beta', code: 'XYZ', type: 'exploitation', responsable: 'TEST Resp' });
      out.apresTableau = H.tableaux(root)[0].lignes.slice(0, 6);
      H.retirer(root);
      return out;
    }));

    /* ---------------------------------------------------------------- 2. cfg-regles */
    await essayer('regles', () => m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core;
      const out = {};
      let root = await H.monter('cfg-regles');
      out.lecture = H.lireEcran(root);
      out.cartesTexte = H.cartesTexte(root);
      out.methode = S.valorisationSortie();
      window.__etats.length = 0; H.bouton(root, 'Imprimer la matrice').click(); await H.dormir(250);
      out.impression = H.propre(window.__etats[0]); window.__etats.length = 0;
      // basculer vers le CUMP (si le prix de vente est en vigueur) puis revenir
      const choix = () => [...root.querySelectorAll('button')].filter((b) => /^(Prix de vente|Coût unitaire)/.test(H.norm(b.textContent)));
      out.choix = choix().map((b) => H.norm(b.textContent));
      const cible = choix().find((b) => !/En vigueur/.test(b.textContent));
      cible.click(); await H.dormir(300);
      out.confirmation = H.modale();
      await H.confirmerBtn('Appliquer');
      out.apresCump = { methode: S.valorisationSortie(), toasts: H.toasts(), audit: H.audit0(), carte: H.cartesTexte(root)[0] };
      // cliquer l'option déjà en vigueur : rien ne se passe
      H.viderToasts(); const encore = choix().find((b) => /En vigueur/.test(b.textContent)); encore.click(); await H.dormir(200);
      out.dejaEnVigueur = { modale: H.modale(), toasts: H.toasts() };
      H.fermerTout();
      // refus : annuler la confirmation
      const autre = choix().find((b) => !/En vigueur/.test(b.textContent)); autre.click(); await H.dormir(300);
      const ann = H.dans('Annuler'); if (ann) ann.click(); await H.dormir(200);
      out.annule = { methode: S.valorisationSortie() };
      // retour au prix de vente
      const retour = choix().find((b) => !/En vigueur/.test(b.textContent)); retour.click(); await H.dormir(300); await H.confirmerBtn('Appliquer');
      out.retour = { methode: S.valorisationSortie(), carte: H.cartesTexte(root)[0], toasts: H.toasts() };
      // l'effet mesuré sur un stock de test (écart connu)
      const p = S.collection('produits').all();
      out.produitsEchantillon = p.slice(0, 3).map((x) => ({ prixVente: x.prixVente, prixAchat: x.prixAchat, cump: x.cump, stock: x.stock }));
      H.retirer(root);
      return out;
    }));

    /* ---------------------------------------------------------------- 3. cfg-fiscalite : à plusieurs dates */
    await essayer('fiscalite', async () => {
      const dates = [[2026, 9, 30], [2026, 9, 1], [2026, 11, 31], [2027, 0, 2], [2027, 0, 29], [2027, 2, 10], [2027, 4, 1], [2026, 1, 9], [2026, 3, 30]];
      const out = { dates: [] };
      for (const d of dates) {
        const r = await m.page.evaluate(async (d) => {
          window.__FIXE = new window.__Vrai(d[0], d[1], d[2], 10, 0, 0).getTime();
          const src = await (await fetch('assets/js/modules/configuration.js')).text();
          (0, eval)(src);
          const root = await H.monter('cfg-fiscalite');
          const o = { jour: d, kpis: H.kpis(root), notes: H.notes(root), tableaux: H.tableaux(root), cartes: H.cartes(root) };
          H.retirer(root);
          return o;
        }, d);
        out.dates.push(r);
      }
      // retour à l'horloge de référence
      await m.page.evaluate(async () => { window.__FIXE = new window.__Vrai(2026, 9, 30, 10, 0, 0).getTime(); const src = await (await fetch('assets/js/modules/configuration.js')).text(); (0, eval)(src); });
      out.reference = await m.page.evaluate(async () => {
        const root = await H.monter('cfg-fiscalite');
        const o = { cartesTexte: H.cartesTexte(root), lecture: H.lireEcran(root), boutons: H.boutons(root) };
        o.hrefs = [...root.querySelectorAll('a')].filter((x) => ['Éditer', 'Configuration MECeF'].includes(H.norm(x.textContent))).map((x) => [H.norm(x.textContent), x.getAttribute('href')]);
        o.go = window.__go.slice(); window.__go.length = 0;
        H.retirer(root);
        return o;
      });
      return out;
    });

    /* ---------------------------------------------------------------- 4. cfg-comptabilite */
    await essayer('comptabilite', () => m.page.evaluate(async () => {
      const root = await H.monter('cfg-comptabilite');
      const o = { lecture: H.lireEcran(root), cartesTexte: H.cartesTexte(root) };
      const b = H.bouton(root, 'Suivi nominatif'); b.click(); await H.dormir(80);
      o.go = window.__go.slice(); window.__go.length = 0;
      H.retirer(root);
      return o;
    }));

    /* ---------------------------------------------------------------- 5. cfg-notifications */
    await essayer('notifications', () => m.page.evaluate(async () => {
      const NT = SIGH.notifications, S = SIGH.store;
      const out = {};
      const etatsAudio = [[true, 0], [false, 3]];
      out.variantes = [];
      for (const [dispo, att] of etatsAudio) {
        NT.audioDisponible = () => dispo;
        NT.enAttente = () => new Array(att).fill({});
        const root = await H.monter('cfg-notifications');
        out.variantes.push({ dispo, att, lecture: H.lireEcran(root), texte: H.norm(root.innerText).slice(0, 3000), notes: H.notes(root) });
        H.retirer(root);
      }
      NT.audioDisponible = () => true; NT.enAttente = () => [];
      const root = await H.monter('cfg-notifications');
      out.params0 = H.propre(NT.params());
      const lignes = [...root.querySelectorAll('table tbody tr')].map((tr) => ({
        libelle: H.norm(tr.querySelector('td p.font-medium').innerText), detail: H.norm(tr.querySelector('td p.text-xs').innerText),
        dest: H.norm(tr.children[1].innerText), canaux: [...tr.querySelectorAll('input[type=checkbox]')].map((c) => c.checked),
      }));
      out.matrice = lignes;
      out.kpis = H.kpis(root);
      out.selects = [...root.querySelectorAll('select')].map((s) => ({ valeur: s.value, desactive: s.disabled, options: [...s.options].map((o) => [o.value, H.norm(o.textContent)]) }));
      out.profilNote = H.norm(root.innerText).includes(NT.profilAudio().note);
      // bascule du son : le profil et la temporisation se désactivent
      const cbs = [...root.querySelectorAll('input[type=checkbox]')].slice(0, 2);
      cbs[1].checked = false; cbs[1].dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(150);
      out.sonCoupe = { params: H.propre(NT.params()), selects: [...root.querySelectorAll('select')].map((s) => ({ valeur: s.value, desactive: s.disabled })) };
      const cbs2 = [...root.querySelectorAll('input[type=checkbox]')].slice(0, 2);
      cbs2[1].checked = true; cbs2[1].dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(150);
      const selProfil = root.querySelectorAll('select')[0];
      selProfil.value = 'critique'; selProfil.dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(150);
      out.profilCritique = { params: H.propre(NT.params()), note: NT.profilAudio().note, notePresente: H.norm(root.innerText).includes(NT.profilAudio().note) };
      const selTempo = root.querySelectorAll('select')[1];
      selTempo.value = '240'; selTempo.dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(150);
      out.tempo240 = H.propre(NT.params());
      const cbv = [...root.querySelectorAll('input[type=checkbox]')][0]; cbv.checked = false; cbv.dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(150);
      out.visuelCoupe = H.propre(NT.params());
      // tester : audio disponible joue, indisponible et refusé
      const stub = (r) => { NT.tester = () => r; };
      stub({ joue: true, motif: null }); H.viderToasts(); H.bouton(root, 'Tester la sonorisation').click(); await H.dormir(150);
      out.testOk = H.toasts();
      stub({ joue: false, motif: 'Aucun périphérique audio détecté.' }); H.viderToasts(); H.bouton(root, 'Tester la sonorisation').click(); await H.dormir(150);
      out.testKo = H.toasts();
      // décocher / cocher des canaux de la matrice puis enregistrer : le journal porte le NOMBRE de canaux actifs
      const cases = [...root.querySelectorAll('table tbody input[type=checkbox]')];
      cases[0].checked = false; cases[4].checked = true;
      H.viderToasts(); H.bouton(root, 'Enregistrer le paramétrage').click(); await H.dormir(200);
      out.enregistre = { toasts: H.toasts(), audit: H.audit0(), actifs: cases.filter((c) => c.checked).length };
      H.retirer(root);
      return out;
    }));

    /* ---------------------------------------------------------------- 6. cfg-compte : un rôle après l'autre */
    await essayer('compte', () => m.page.evaluate(async () => {
      const S = SIGH.store, N = SIGH.nav;
      const out = { parRole: {} };
      const sess0 = H.propre(S.session());
      out.session = sess0;
      for (const r of Object.keys(N.ROLES)) {
        S.setSession(Object.assign({}, sess0, { role: r, identifiant: sess0.identifiant, nom: sess0.nom }));
        const root = await H.monter('cfg-compte');
        const cartes = H.cartesTexte(root);
        const peri = [...root.querySelectorAll('.card')].find((c) => /Périmètre/.test(c.innerText));
        out.parRole[r] = { perimetre: [...peri.querySelectorAll('span')].map((x) => H.norm(x.textContent)).filter((t) => /^[A-Z]{1,5}\d*$/.test(t)), poste: H.norm(root.querySelector('p.text-xs.text-slate-500').innerText), mfa: (document.getElementById('f_mfa') || {}).checked };
        H.retirer(root);
      }
      S.setSession(sess0);
      const root = await H.monter('cfg-compte');
      out.lecture = { cartes: H.cartes(root), cartesTexte: H.cartesTexte(root), notes: H.notes(root), boutons: H.boutons(root), labels: [...root.querySelectorAll('label')].map((l) => H.norm(l.innerText)) };
      out.valeursInitiales = ['nom', 'identifiant', 'poste', 'telephone', 'email', 'mfa'].map((n) => { const e = document.getElementById('f_' + n); return [n, e ? (e.type === 'checkbox' ? e.checked : e.value) : null, e ? !!e.readOnly : null]; });
      out.avatar = H.norm(root.querySelector('span.rounded-full.bg-navy-900').innerText);
      out.activite = [...root.querySelectorAll('.card')].find((c) => /Activité récente/.test(c.innerText)) ? H.norm([...root.querySelectorAll('.card')].find((c) => /Activité récente/.test(c.innerText)).innerText) : null;
      out.auditUtilisateur = S.raw().audit.filter((a) => a.utilisateur === sess0.nom).slice(0, 6).map((a) => [a.action, a.entite, a.module, a.dateHeure]);
      // enregistrer le profil
      H.poser('nom', 'NOUVEAU Nom'); H.viderToasts(); H.bouton(root, 'Enregistrer').click(); await H.dormir(200);
      out.enregistrer = { toasts: H.toasts(), session: H.propre(S.session()) };
      H.poser('nom', ''); H.viderToasts(); H.bouton(root, 'Enregistrer').click(); await H.dormir(200);
      out.enregistrerVide = { toasts: H.toasts(), session: H.propre(S.session()) };
      S.setSession(sess0);
      // mot de passe : formulaire invalide, divergence, trop court, valide
      const mdp = async (a, n, c) => { H.poser('actuel', a); H.poser('nouveau', n); H.poser('confirmation', c); H.viderToasts(); const nbAudit = S.raw().audit.length; H.bouton(root, 'Modifier le mot de passe').click(); await H.dormir(200); return { toasts: H.toasts(), audit: S.raw().audit.length - nbAudit, premier: S.raw().audit.length ? H.audit0() : null }; };
      out.mdpVide = await mdp('', '', '');
      out.mdpDivergent = await mdp('ancien', 'MotDePasse#2026X', 'MotDePasse#2027X');
      out.mdpCourt = await mdp('ancien', 'Court#1', 'Court#1');
      out.mdpTreize = await mdp('ancien', 'Exact12Chars', 'Exact12Chars');
      out.mdpValide = await mdp('ancien', 'MotDePasse#2026X', 'MotDePasse#2026X');
      H.retirer(root);
      return out;
    }));

    /* ---------------------------------------------------------------- 7. cfg-modules */
    await essayer('modules', () => m.page.evaluate(async () => {
      const S = SIGH.store, N = SIGH.nav;
      const out = {};
      const col = () => S.collection('modulesActifs');
      const sauve = H.propre(S.raw().modulesActifs);
      let root = await H.monter('cfg-modules');
      out.lecture = H.lireEcran(root);
      out.cartesTexte = H.cartesTexte(root);
      out.notes = H.notes(root);
      // les cartes de modules : intitulé, ligne de détail, état, présence d'un bouton
      const grille = () => [...root.querySelectorAll('.grid .card')].map((c) => ({ texte: H.norm(c.innerText), boutons: [...c.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title) }));
      out.grille = grille();
      out.tousEcrans = (() => { let n = 0; N.NAV.forEach((d) => d.modules.forEach((mm) => { if (mm.alias) return; mm.items.forEach((it) => { if (!it.alias) n++; }); })); return n; })();
      out.modulesListe = (() => { const vus = {}, o = []; N.NAV.forEach((dom) => dom.modules.forEach((mm) => { if (mm.alias || vus[mm.code]) return; vus[mm.code] = true; o.push([mm.code, mm.label, mm.icon, dom.domain, mm.items.filter((it) => !it.alias).length]); })); return o; })();
      // 1. fermer M7 par la carte : confirmation avec motif obligatoire
      const carteM7 = () => [...root.querySelectorAll('.grid .card')].find((c) => H.norm(c.innerText).startsWith('M7 —'));
      const btnM7 = carteM7().querySelector('button');
      btnM7.click(); await H.dormir(300);
      out.fermerM7Confirmation = H.modale();
      await H.confirmerBtn('Fermer l’activité', 'Pas de service d’achats pour le test');
      const ficheM7 = col().all().find((x) => x.module === 'M7');
      out.fermerM7 = { fiche: ficheM7 ? H.net(ficheM7) : null, toasts: H.toasts(), audit: H.audit0(), kpis: H.kpis(root), ecransActifs: N.ecranActif('m7-commandes', 'M7'), tableaux: H.tableaux(root), grille: grille().find((g) => g.texte.startsWith('M7')) };
      out.retires = H.tableaux(root).slice(-1)[0];
      out.cartesApres = H.cartes(root);
      // 2. rouvrir M7
      H.viderToasts();
      const btnR = carteM7().querySelector('button'); btnR.click(); await H.dormir(300);
      out.rouvrirM7Confirmation = H.modale();
      await H.confirmerBtn('Rouvrir l’activité');
      const f2 = col().all().find((x) => x.module === 'M7');
      out.rouvrirM7 = { fiche: f2 ? H.net(f2) : null, toasts: H.toasts(), audit: H.audit0(), kpis: H.kpis(root), ecranActif: N.ecranActif('m7-commandes', 'M7') };
      // 3. le NOYAU : CFG et DASH sans bouton ; la déclaration puis la bascule d'un module noyau est refusée en le disant
      out.noyau = ['CFG', 'DASH'].map((c) => { const k = [...root.querySelectorAll('.grid .card')].find((x) => H.norm(x.innerText).startsWith(c + ' —')); return { code: c, texte: k ? H.norm(k.innerText) : null, boutons: k ? k.querySelectorAll('button').length : null }; });
      H.bouton(root, 'Piloter une activité').click(); await H.dormir(250);
      out.declarerForm = { modale: H.modale(), labels: [...document.querySelectorAll('[role=dialog] label')].map((l) => H.norm(l.innerText)), nbModules: (() => { const e = document.getElementById('f_module'); return e && typeof e.options === 'function' ? e.options().length : null; })(), optionsModule: (() => { const e = document.getElementById('f_module'); return e && typeof e.options === 'function' ? e.options().map((o) => [o.value, H.norm(o.label)]).slice(0, 40) : null; })(), nbEcrans: (() => { const e = document.getElementById('f_ecrans'); return e && typeof e.options === 'function' ? e.options().length : null; })() };
      H.poser('libelle', 'Activité noyau test'); H.poser('module', 'CFG'); H.poser('motif', 'Essai du noyau');
      H.viderToasts(); H.cliquer('Déclarer'); await H.dormir(300);
      const fCfg = col().all().find((x) => x.module === 'CFG');
      out.declarerCfg = { fiche: fCfg ? H.net(fCfg) : null, toasts: H.toasts() };
      const ligneCfg = H.ligne(root, 'Activité noyau test');
      out.boutonsLigneCfg = ligneCfg ? [...ligneCfg.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title) : null;
      H.viderToasts(); H.icone(ligneCfg, 'Fermer cette activité').click(); await H.dormir(300);
      out.fermerNoyau = { toasts: H.toasts(), modaleOuverte: !!document.querySelector('[role=dialog]'), actif: fCfg.actif };
      // 4. déclarer une activité sur DEUX écrans : motif obligatoire, créée ouverte, fermée en un second geste
      H.bouton(root, 'Piloter une activité').click(); await H.dormir(250);
      H.poser('libelle', 'Écrans de test'); H.poser('module', 'M6');
      const ecr = document.getElementById('f_ecrans'); ecr.value = ['m6-pertes', 'm6-lots']; ecr.dispatchEvent(new Event('change', { bubbles: true }));
      H.poser('motif', 'Deux écrans fermés pour le test');
      H.viderToasts(); H.cliquer('Déclarer'); await H.dormir(300);
      const fEc = col().all().find((x) => x.libelle === 'Écrans de test');
      out.declarerEcrans = { fiche: fEc ? H.net(fEc) : null, toasts: H.toasts(), valeurEcrans: fEc ? fEc.ecrans : null };
      const ligneEc = H.ligne(root, 'Écrans de test');
      H.icone(ligneEc, 'Fermer cette activité').click(); await H.dormir(300);
      await H.confirmerBtn('Fermer l’activité', '');
      const fEc2 = col().all().find((x) => x.libelle === 'Écrans de test');
      out.fermerEcrans = { fiche: H.net(fEc2), pertesActif: N.ecranActif('m6-pertes', 'M6'), lotsActif: N.ecranActif('m6-lots', 'M6'), autreActif: N.ecranActif('m6-stock', 'M6'), fermeturePour: (N.fermeturePour('m6-lots', 'M6') || {}).motif || null, kpis: H.kpis(root), retires: H.tableaux(root).slice(-1)[0], confirmation: null };
      // 5. une fiche ARCHIVÉE ne ferme plus rien (RG-14)
      col().archive(fEc2.id); N.invaliderModules();
      out.archivee = { pertesActif: N.ecranActif('m6-pertes', 'M6'), lotsActif: N.ecranActif('m6-lots', 'M6') };
      col().restore(fEc2.id); N.invaliderModules();
      out.restauree = { lotsActif: N.ecranActif('m6-lots', 'M6') };
      // 6. cas limite : fermer M7 entier ET un écran de M7
      S.raw().modulesActifs.splice(0); sauve.forEach((x) => S.raw().modulesActifs.push(x)); N.invaliderModules();
      out.final = { nbFiches: col().all().length };
      H.retirer(root);
      return out;
    }));

    /* ---------------------------------------------------------------- 8. cfg-systeme */
    await essayer('systeme', () => m.page.evaluate(async () => {
      const S = SIGH.store;
      const out = {};
      // Le magasin ne porte QUE les collections du jeu du poste (celles que le poste connaît) : les autres sont retirées pour la mesure.
      const nomsJeu = new Set(Object.keys(window.__jeu));
      Object.keys(S.raw()).forEach((k) => { if (k.charAt(0) !== '_' && Array.isArray(S.raw()[k]) && (!nomsJeu.has(k) || ['rolesBase', 'modulesManifeste'].includes(k))) delete S.raw()[k]; });
      out.nomsHorsJeu = [];
      const root = await H.monter('cfg-systeme');
      out.onglets = H.onglets(root);
      out.regleCartes = H.cartesTexte(root).slice(0, 4);
      out.installation = { kpis: H.kpis(root), tableaux: H.tableaux(root), cartes: H.cartes(root), notes: H.notes(root), boutons: H.boutons(root), cartesTexte: H.cartesTexte(root) };
      const brut = S.raw();
      out.collections = Object.keys(brut).filter((k) => k.charAt(0) !== '_' && Array.isArray(brut[k])).map((k) => [k, brut[k].length, brut[k].filter((r) => r && r.statut !== 'archive').length, brut[k].filter((r) => r && r.statut === 'archive').length]);
      out.persistance = S.storage.disponible;
      // Corbeille
      const tab = [...root.querySelectorAll('[role=tab]')];
      const tabDe = (d) => tab.find((t) => H.norm(t.innerText).startsWith(d));
      tabDe('Corbeille').click(); await H.dormir(200);
      out.corbeille = { kpis: H.kpis(root), tableaux: H.tableaux(root), notes: H.notes(root) };
      out.corbeilleBrute = H.propre(S.corbeille().map((r) => ({ id: r.id, collection: r.collection, module: r.module, entite: r.entite, libelle: r.libelle, archiveLe: r.archiveLe, archivePar: r.archivePar, motif: r.motif })));
      out.nbArchivesJeu = S.corbeille().length;
      // Restaurer : la ligne de la première fiche
      const premiere = S.corbeille()[0];
      if (premiere) {
        const ligne = [...root.querySelectorAll('tbody tr')].find((tr) => H.norm(tr.innerText).includes(premiere.refId));
        H.icone(ligne, 'Restaurer').click(); await H.dormir(300);
        out.restaurerConfirmation = H.modale();
        H.viderToasts(); await H.confirmerBtn('Restaurer');
        out.restaurer = { toasts: H.toasts(), audit: H.audit0(), reste: S.corbeille().length, statut: (S.raw()[premiere.collection].find((x) => x.id === premiere.refId) || {}).statut || null, premiere: { collection: premiere.collection, refId: premiere.refId } };
        // la restauration est annulable ? (on remet la fiche en archive pour la suite)
        S.collection(premiere.collection).archive(premiere.refId);
      }
      // Barème NS 131
      tabDe('Barème').click(); await H.dormir(200);
      out.bareme = { avant: { texte: H.norm(root.innerText), ouverte: SIGH.baremeModifiable(), boutons: H.boutons(root) } };
      H.bouton(root, 'Autoriser la modification').click(); await H.dormir(300);
      out.bareme.confirmation = H.modale();
      H.viderToasts(); await H.confirmerBtn('Autoriser la modification', 'Révision du barème');
      out.bareme.ouvert = { ouverte: SIGH.baremeModifiable(), toasts: H.toasts(), audit: H.audit0(), texte: H.norm(root.innerText), boutons: H.boutons(root) };
      H.viderToasts(); H.bouton(root, 'Refermer la modification').click(); await H.dormir(250);
      out.bareme.ferme = { ouverte: SIGH.baremeModifiable(), toasts: H.toasts(), audit: H.audit0(), texte: H.norm(root.innerText) };
      // Jeux de test
      tabDe('Jeux de test').click(); await H.dormir(200);
      out.reinit = { verrouillee: { kpis: H.kpis(root), cartesTexte: H.cartesTexte(root), notes: H.notes(root), boutons: H.boutons(root), texte: H.norm(root.innerText) } };
      const bascule = document.getElementById('f_reinit');
      bascule.checked = true; bascule.dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(300);
      out.reinit.autoriserConfirmation = H.modale();
      await H.confirmerBtn('Autoriser');
      out.reinit.autorisee = { cle: S.storage.get('sigh-cnt:reinit-autorisee'), kpis: H.kpis(root), boutons: H.boutons(root), audit: H.audit0(), cartesTexte: H.cartesTexte(root) };
      // le bilan d'un vidage, calculé sur le jeu — et le journal qui le porte
      const avant = H.propre(S.raw().audit.length);
      H.bouton(root, 'Vider les jeux de test').click(); await H.dormir(300);
      out.reinit.viderConfirmation = H.modale();
      const essentielles = new Set(S.COLLECTIONS_ESSENTIELLES);
      const attendu = Object.keys(S.raw()).filter((k) => k.charAt(0) !== '_' && Array.isArray(S.raw()[k]) && !essentielles.has(k)).map((k) => [k, S.raw()[k].length]);
      window.__setup = SIGH.store.raw();
      const clone = JSON.parse(JSON.stringify(S.raw()));
      window.__clone = clone;
      H.viderToasts(); await H.confirmerBtn('Vider les jeux de test', 'Fin de la recette');
      out.reinit.vider = { toasts: H.toasts(), audit0: H.audit0(), nbAudit: S.raw().audit.length, attenduTables: attendu.length, attenduLignes: attendu.reduce((n, a) => n + a[1], 0), videes: attendu.map((a) => a[0]), restantes: Object.keys(S.raw()).filter((k) => k.charAt(0) !== '_' && Array.isArray(S.raw()[k]) && S.raw()[k].length).map((k) => [k, S.raw()[k].length]), echeances: S.raw().echeancesFiscales.length, echeancesPayees: S.raw().echeancesFiscales.filter((e) => e.paye).length, jeuVide: S.raw()._jeuVide };
      // verrouiller de nouveau
      const bas2 = document.getElementById('f_reinit'); bas2.checked = false; bas2.dispatchEvent(new Event('change', { bubbles: true })); await H.dormir(250);
      out.reinit.reverrouillee = { cle: S.storage.get('sigh-cnt:reinit-autorisee'), audit: H.audit0(), cartesTexte: H.cartesTexte(root).slice(-1) };
      H.retirer(root);
      return out;
    }));

    /* ---------------------------------------------------------------- 9. cfg-poste */
    await essayer('poste', () => m.page.evaluate(async () => {
      const out = {};
      const root = await H.monter('cfg-poste');
      out.fileul = { kpis: H.kpis(root), notes: H.notes(root), boutons: H.boutons(root), texte: H.norm(root.innerText) };
      H.viderToasts(); H.bouton(root, 'Activer le mode mère').click(); await H.dormir(200);
      out.mere = { kpis: H.kpis(root), notes: H.notes(root), boutons: H.boutons(root), toasts: H.toasts(), texte: H.norm(root.innerText) };
      H.bouton(root, 'Désactiver le mode mère').click(); await H.dormir(200);
      out.retour = { kpis: H.kpis(root), boutons: H.boutons(root) };
      H.retirer(root);
      return out;
    }));

    sortie.erreurs = await m.page.evaluate(() => window.__erreurs);
    ecrire('packages/domaine/test/vecteurs/cfb.json', sortie);
    console.log('  erreurs de page : ' + sortie.erreurs.length);
    for (const k of Object.keys(sortie)) if (sortie[k] && sortie[k].erreur) console.log('  ÉCHEC ' + k + ' : ' + String(sortie[k].erreur).split('\n')[0]);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
