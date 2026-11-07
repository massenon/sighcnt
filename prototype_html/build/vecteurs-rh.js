/* =============================================================================
 * VECTEURS DE M10 (RH) — m10-fiches-poste, m10-dashboard, m10-personnel, m10-employe-profil, m10-contrats, m10-conges, m10-missions, m10-prestataires
 * -----------------------------------------------------------------------------
 * Les huit écrans RÉELS sont montés dans Chrome sur le JEU DU POSTE (apps/poste/assets/donnees/jeu/*.json, posé dans le magasin de la maquette) à une
 * HORLOGE FIGÉE (30/10/2026 10:00), LUS comme l'agent les lit (indicateurs, onglets, tableaux, cartes, graphiques interceptés, boutons) et PILOTÉS
 * (modales de création / modification, archivage, validation d'un ordre de mission, impressions).
 *   node build/vecteurs-rh.js   →   packages/domaine/test/vecteurs/rh.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU = path.resolve(ROOT, '..', 'apps', 'poste', 'assets', 'donnees', 'jeu');
const COLLECTIONS = ['personnel', 'contrats', 'conges', 'missions', 'prestataires', 'fichesPoste', 'planning', 'presences', 'evaluations', 'assurancesPersonnel', 'grillePrimes', 'historiquePrimes'];

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
          c.querySelectorAll('table').forEach((t) => tab.push({
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

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-rh.js — ne pas éditer. Horloge : 30/10/2026 10 h. Jeu : apps/poste/assets/donnees/jeu.' };

    /* ------------------------------------------------------------------ TABLEAU DE BORD RH */
    sortie.dashboard = await m.page.evaluate(async () => {
      window.__graphes.length = 0;
      const root = await H.monter('m10-dashboard');
      const out = { ecran: H.lireEcran(root), graphes: H.graphes(), cartes: H.cartesTexte(root), liens: [...root.querySelectorAll('a')].map((a) => [H.norm(a.innerText), a.getAttribute('href')]) };
      H.retirer(root);
      return out;
    });

    /* ------------------------------------------------------------------ FICHES DE POSTE */
    sortie.fichesPoste = await m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = S.collection('fichesPoste');
      const out = { jeu: H.propre(col.all()) };
      const racine = await H.monter('m10-fiches-poste');
      out.ecran = H.lireEcran(racine);
      out.lignes = H.lignesPage(racine);
      await H.chercher(racine, 'Infirmier Général'); out.boutonsLigne = [...H.ligne(racine, 'Infirmier Général (IG)').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      out.commandes = H.boutons(racine);
      H.icone(H.ligne(racine, 'Infirmier Général (IG)'), 'Consulter').click(); await H.dormir(300);
      out.detailIG = H.tiroir(); H.fermerTout();
      await H.chercher(racine, 'Comptable');
      H.icone(H.ligne(racine, 'Comptable'), 'Consulter').click(); await H.dormir(300);
      out.detailVide = H.tiroir(); H.fermerTout();
      await H.chercher(racine, 'Assistant');
      H.icone(H.ligne(racine, 'Assistant(e) de Direction'), 'Consulter').click(); await H.dormir(300);
      out.detailAssistant = H.tiroir(); H.fermerTout();
      await H.chercher(racine, 'Infirmier Général');
      window.__etats.length = 0;
      H.icone(H.ligne(racine, 'Infirmier Général (IG)'), 'Imprimer la fiche de poste').click(); await H.dormir(200);
      out.etatIG = H.propre(window.__etats[0]);
      await H.chercher(racine, 'Comptable');
      window.__etats.length = 0;
      H.icone(H.ligne(racine, 'Comptable'), 'Imprimer la fiche de poste').click(); await H.dormir(200);
      out.etatVide = H.propre(window.__etats[0]);
      // création
      H.bouton(racine, 'Nouvelle fiche de poste').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 200), champs: H.champs(), defauts: {} };
      ['intitule', 'archivage', 'elaboration', 'miseAJour', 'rattachement', 'niveauN', 'niveauSup', 'niveauInf', 'statut', 'textes', 'resume', 'relationsInternes', 'relationsExternes', 'environnement', 'diplomes', 'savoirFaire', 'savoirEtre'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('intitule', 'Responsable qualité'); H.poser('rattachement', 'Direction'); H.poser('resume', 'Suivre les indicateurs de qualité.');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(col.all()[col.all().length - 1]), total: col.all().length };
      await H.chercher(racine, '');
      out.creation.apres = H.lireEcran(racine);
      out.creation.lignes = H.lignesPage(racine);
      // modification
      await H.chercher(racine, 'Comptable');
      H.icone(H.ligne(racine, 'Comptable'), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['intitule', 'archivage', 'rattachement', 'statut', 'resume'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('resume', 'Tenir les livres.'); H.poser('archivage', '999/CNT');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.intitule === 'Comptable')) };
      // archivage
      await H.chercher(racine, 'Responsable qualité');
      H.icone(H.ligne(racine, 'Responsable qualité'), 'Archiver').click(); await H.confirmer('Doublon');
      out.archivage = { fiche: H.net(col.all().find((x) => x.intitule === 'Responsable qualité')), lignes: H.lignesPage(racine), kpis: H.kpis(racine), toasts: H.toasts() };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ PERSONNEL */
    sortie.personnel = await m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = S.collection('personnel');
      const out = { jeu: col.all().length };
      const racine = await H.monter('m10-personnel');
      out.ecran = H.lireEcran(racine);
      out.lignes = H.lignesPage(racine);
      out.filtres = H.filtres(racine);
      out.boutonsLigne = [...H.ligne(racine, 'BASSONGUI').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      // tiroir : fiche de l'agent, un onglet après l'autre
      await H.chercher(racine, 'BASSONGUI');
      { const b = H.icone(H.ligne(racine, 'BASSONGUI'), 'Consulter'); if (!b) return { erreur: H.boutons(racine), lignes: H.lignesPage(racine) }; b.click(); } await H.dormir(400);
      const tiroir = () => document.querySelector('[role=dialog], .drawer-root');
      out.tiroir = { entete: H.norm(tiroir().innerText).slice(0, 220), onglets: [...tiroir().querySelectorAll('.tab')].map((t) => H.norm(t.innerText)), parOnglet: await H.parOnglet(tiroir()), boutons: H.boutons(tiroir()) };
      H.fermerTout();
      // état imprimé
      window.__etats.length = 0;
      H.icone(H.ligne(racine, 'BASSONGUI'), 'Imprimer l’état').click(); await H.dormir(200);
      out.etat = H.propre(window.__etats[0]);
      // création
      await H.chercher(racine, '');
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: {} };
      ['matricule', 'nom', 'prenom', 'sexe', 'telephone', 'situation', 'fonction', 'poste', 'service', 'categorie', 'dateEmbauche', 'salaireBase', 'cnss'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      ['sexe', 'situation', 'fonction', 'service'].forEach((n) => { out.creation.options[n] = H.optsDe(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('matricule', '99'); H.poser('nom', 'AGBO'); H.poser('prenom', 'Rosine'); H.poser('fonction', 'infirmier'); H.poser('service', 'Soins infirmiers'); H.poser('poste', 'Infirmière'); H.poser('salaireBase', '120000');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      await H.chercher(racine, 'AGBO');
      out.creation.apres = { kpis: H.kpis(racine), lignes: H.lignesPage(racine), onglets: H.onglets(racine) };
      // modification
      H.icone(H.ligne(racine, 'AGBO'), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['matricule', 'nom', 'prenom', 'sexe', 'telephone', 'situation', 'fonction', 'poste', 'service', 'categorie', 'dateEmbauche', 'salaireBase', 'cnss'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('prenom', 'Rosine-Marie'); H.poser('telephone', '0197000000');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.matricule === '99')) };
      // archivage
      H.icone(H.ligne(racine, 'AGBO'), 'Archiver').click(); await H.confirmer('Départ');
      await H.chercher(racine, '');
      out.archivage = { fiche: H.net(col.all().find((x) => x.matricule === '99')), kpis: H.kpis(racine), onglets: H.onglets(racine), toasts: H.toasts() };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ FICHE EMPLOYÉ (à deux horloges : 30/10 sans planning, 20/08 avec) */
    const profil = async (agents) => m.page.evaluate(async (agents) => {
      const S = SIGH.store;
      const racine = await H.monter('m10-employe-profil');
      const out = { entete: H.norm(racine.querySelector('.card').innerText), combo: [], agents: {} };
      out.comboOptions = null;
      out.ecran = { cartes: H.cartes(racine), boutons: H.boutons(racine).slice(0, 12), liens: [...racine.querySelectorAll('a')].map((a) => [H.norm(a.innerText), a.getAttribute('href')]) };
      for (const id of agents) {
        // le combo expose `value` et émet `change`
        const cb = racine.querySelector('.combo');
        cb.value = id; cb.dispatchEvent(new Event('change')); await H.dormir(250);
        const corps = racine.querySelectorAll('.card')[1];
        const o = { bandeau: H.norm(corps.querySelector('.bg-navy-50').innerText), onglets: [...corps.querySelectorAll('.tab')].map((t) => H.norm(t.innerText)), parOnglet: await H.parOnglet(corps) };
        out.agents[id] = o;
      }
      H.retirer(racine);
      return out;
    }, agents);

    const AGENTS_PROFIL = ['EMP01', 'EMP10', 'EMP18', 'EMP29', 'EMP21', 'EMP44'];
    sortie.profil = { octobre: await profil(AGENTS_PROFIL) };
    /* Assurances du personnel : la saisie de l'onglet « Assurances » (K.creer) */
    sortie.profilAssurance = await m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = S.collection('assurancesPersonnel');
      const racine = await H.monter('m10-employe-profil');
      const cb = racine.querySelector('.combo');
      cb.value = 'EMP10'; cb.dispatchEvent(new Event('change')); await H.dormir(250);
      [...racine.querySelectorAll('.tab')].find((t) => H.norm(t.innerText) === 'Assurances').click(); await H.dormir(200);
      const out = { avant: { tableaux: H.tableaux(racine), notes: H.notes(racine), boutons: H.boutons(racine).slice(-8) } };
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: { type: H.optsDe('type') } };
      ['type', 'organisme', 'numeroAdhesion', 'taux', 'dateDebut', 'dateFin', 'beneficiaires', 'observation'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('organisme', 'CNSS Bénin'); H.poser('numeroAdhesion', 'ADH-7788');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      out.apres = { tableaux: H.tableaux(racine) };
      H.retirer(racine);
      col.all().splice(0);
      return out;
    });
    /* 20/08/2026 : le planning du jeu (27/07 → 05/09) couvre la date, les gardes, permanences et primes du mois se lisent */
    await m.page.evaluate(() => { window.__FIXE = new window.__Vrai(2026, 7, 20, 10, 0, 0).getTime(); });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m10-rh.js') });
    sortie.profil.aout = await profil(AGENTS_PROFIL);
    sortie.dashboardAout = await m.page.evaluate(async () => {
      window.__graphes.length = 0;
      const root = await H.monter('m10-dashboard');
      const out = { ecran: H.lireEcran(root), graphes: H.graphes(), cartes: H.cartesTexte(root) };
      H.retirer(root);
      return out;
    });
    await m.page.evaluate(() => { window.__FIXE = new window.__Vrai(2026, 9, 30, 10, 0, 0).getTime(); });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m10-rh.js') });

    /* ------------------------------------------------------------------ CONTRATS */
    sortie.contrats = await m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = S.collection('contrats');
      const out = { jeu: col.all().length };
      const racine = await H.monter('m10-contrats');
      out.ecran = H.lireEcran(racine);
      out.lignes = H.lignesPage(racine);
      out.filtres = H.filtres(racine);
      await H.chercher(racine, 'CT-0001');
      out.boutonsLigne = [...H.ligne(racine, 'CT-0001').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(H.ligne(racine, 'CT-0001'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      // états imprimés : un CDI et un CDD
      const cdd = col.all().find((c) => c.nature === 'CDD'), cdi = col.all().find((c) => c.nature === 'CDI');
      out.refCDD = cdd.reference; out.refCDI = cdi.reference;
      for (const [cle, c] of [['etatCDI', cdi], ['etatCDD', cdd]]) {
        await H.chercher(racine, c.reference);
        window.__etats.length = 0;
        H.icone(H.ligne(racine, c.reference), 'Imprimer l’état').click(); await H.dormir(200);
        out[cle] = H.propre(window.__etats[0]);
      }
      await H.chercher(racine, '');
      // création
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: {} };
      ['employeId', 'nature', 'dateDebut', 'dateFin', 'essai', 'salaire'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      ['employeId', 'nature', 'essai'].forEach((n) => { out.creation.options[n] = H.optsDe(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('employeId', 'EMP10'); H.poser('nature', 'CDD'); H.poser('dateDebut', '2026-10-01'); H.poser('dateFin', '2027-09-30'); H.poser('essai', '3 mois'); H.poser('salaire', '150000');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      const ref = col.all()[0].reference;
      await H.chercher(racine, ref);
      out.creation.apres = { kpis: H.kpis(racine), lignes: H.lignesPage(racine) };
      // modification : la référence est GARDÉE
      H.icone(H.ligne(racine, ref), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['employeId', 'nature', 'dateDebut', 'dateFin', 'essai', 'salaire'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('salaire', '160000'); H.poser('nature', 'CDI'); H.poser('dateFin', '');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.reference === ref)), nbSansRef: col.all().filter((x) => x.reference === 'CT-0001').length };
      // archivage
      H.icone(H.ligne(racine, ref), 'Archiver').click(); await H.confirmer('Erreur de saisie');
      await H.chercher(racine, '');
      out.archivage = { fiche: H.net(col.all().find((x) => x.reference === ref)), kpis: H.kpis(racine), onglets: H.onglets(racine) };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ CONGÉS */
    sortie.conges = await m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = S.collection('conges');
      const out = { jeu: col.all().length };
      window.__graphes.length = 0;
      const racine = await H.monter('m10-conges');
      out.ecran = H.lireEcran(racine);
      out.graphes = H.graphes();
      out.cartes = H.cartesTexte(racine);
      out.lignes = H.lignesPage(racine);
      out.filtres = H.filtres(racine);
      await H.chercher(racine, 'CG-0001');
      out.boutonsLigne = [...H.ligne(racine, 'CG-0001').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(H.ligne(racine, 'CG-0001'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      // états imprimés : une décision de chaque sorte
      out.etats = {};
      for (const dec of ['valide', 'refuse', 'en_attente']) {
        const c = col.all().find((x) => x.statutConge === dec && x.remplacant) || col.all().find((x) => x.statutConge === dec);
        await H.chercher(racine, c.reference);
        window.__etats.length = 0;
        H.icone(H.ligne(racine, c.reference), 'Imprimer l’état').click(); await H.dormir(200);
        out.etats[dec] = { reference: c.reference, etat: H.propre(window.__etats[0]) };
      }
      await H.chercher(racine, '');
      // création
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: {} };
      ['employeId', 'nature', 'dateDebut', 'dateFin', 'remplacant', 'statutConge', 'motif'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      ['employeId', 'nature', 'remplacant', 'statutConge'].forEach((n) => { out.creation.options[n] = H.optsDe(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('employeId', 'EMP10'); H.poser('dateDebut', '2026-11-10'); H.poser('dateFin', '2026-11-05');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refusDates = { toasts: H.toasts(), total: col.all().length };
      H.poser('dateFin', '2026-11-16'); H.poser('remplacant', 'GARBA Yahouza'); H.poser('motif', 'Repos annuel');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      const ref = col.all()[0].reference;
      await H.chercher(racine, ref);
      out.creation.apres = { kpis: H.kpis(racine), lignes: H.lignesPage(racine) };
      H.icone(H.ligne(racine, ref), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['employeId', 'nature', 'dateDebut', 'dateFin', 'remplacant', 'statutConge', 'motif'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('statutConge', 'valide'); H.poser('dateFin', '2026-11-20');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.reference === ref)) };
      H.icone(H.ligne(racine, ref), 'Archiver').click(); await H.confirmer('Annulé');
      await H.chercher(racine, '');
      out.archivage = { fiche: H.net(col.all().find((x) => x.reference === ref)), kpis: H.kpis(racine), onglets: H.onglets(racine) };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ ORDRES DE MISSION */
    sortie.missions = await m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = S.collection('missions');
      const out = { jeu: col.all().length };
      let racine = await H.monter('m10-missions');
      out.ecran = H.lireEcran(racine);
      out.lignes = H.lignesPage(racine);
      out.filtres = H.filtres(racine);
      const aValider = col.all().filter((x) => x.statutMission === 'a_valider');
      const validee = col.all().find((x) => x.statutMission === 'validee');
      const terminee = col.all().find((x) => x.statutMission === 'terminee');
      out.refs = { aValider: aValider.map((x) => x.reference), validee: validee && validee.reference, terminee: terminee && terminee.reference };
      const ligneDe = (ref) => H.ligne(racine, ref);
      out.boutonsAValider = [...ligneDe(aValider[0].reference).querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      out.boutonsTerminee = [...ligneDe(terminee.reference).querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      out.boutonsValidee = validee ? [...ligneDe(validee.reference).querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title) : null;
      // fiche (clic sur la ligne) et ordre imprimé
      ligneDe(terminee.reference).click(); await H.dormir(300);
      out.fiche = H.tiroir(); H.fermerTout();
      out.etats = {};
      for (const [cle, mi] of [['aValider', aValider[0]], ['terminee', terminee]]) {
        window.__etats.length = 0;
        H.icone(ligneDe(mi.reference), 'Imprimer l’ordre').click(); await H.dormir(200);
        out.etats[cle] = { reference: mi.reference, etat: H.propre(window.__etats[0]) };
      }
      // validation : confirmation, puis état « Validée »
      H.icone(ligneDe(aValider[0].reference), 'Valider (Directrice Administrative)').click(); await H.dormir(300);
      out.validation = { modale: H.modale() };
      H.viderToasts(); H.cliquer('Valider l’ordre'); await H.dormir(400);
      racine = document.getElementById('page-content') || racine;
      out.validation.apres = { fiche: H.net(col.all().find((x) => x.id === aValider[0].id)), toasts: H.toasts() };
      const racine2 = [...document.querySelectorAll('div')].find((d) => d.querySelector && d.querySelector('table') && d.innerText.includes('Registre des ordres de mission'));
      out.validation.ecran = H.lireEcran(racine2 || racine);
      // terminer
      const cible = col.all().find((x) => x.statutMission === 'validee');
      H.icone(H.ligne(racine2 || racine, cible.reference), 'Marquer terminée').click(); await H.dormir(300);
      out.terminer = { fiche: H.net(col.all().find((x) => x.id === cible.id)), toasts: H.toasts() };
      H.fermerTout();
      H.retirer(racine2 || racine);
      // création : écran neuf
      racine = await H.monter('m10-missions');
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: {} };
      ['libelle', 'nature', 'objet', 'agentId', 'structurePrise', 'destination', 'moyen', 'dateDepart', 'dateRetour', 'statutMission', 'observation'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      ['nature', 'agentId', 'moyen', 'statutMission'].forEach((n) => { out.creation.options[n] = H.optsDe(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('libelle', 'Formation en gestion de stock'); H.poser('objet', 'Se former à la gestion des stocks de médicaments.'); H.poser('agentId', 'EMP37'); H.poser('destination', 'Parakou');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      const racine3 = [...document.querySelectorAll('div')].find((d) => d.querySelector && d.querySelector('table') && d.innerText.includes('Registre des ordres de mission')) || racine;
      out.creation.apres = { kpis: H.kpis(racine3), note: H.notes(racine3) };
      // modification d'une ligne
      const nouvelle = col.all()[0];
      H.icone(H.ligne(racine3, nouvelle.reference), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['libelle', 'nature', 'objet', 'agentId', 'structurePrise', 'destination', 'moyen', 'dateDepart', 'dateRetour', 'statutMission', 'observation'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('destination', 'Djougou'); H.poser('statutMission', 'projet');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.id === nouvelle.id)) };
      // archivage
      H.icone(H.ligne(racine3, nouvelle.reference), 'Archiver').click(); await H.confirmer('Doublon');
      out.archivage = { fiche: H.net(col.all().find((x) => x.id === nouvelle.id)), kpis: H.kpis(racine3) };
      H.retirer(racine3);
      return out;
    });

    /* ------------------------------------------------------------------ PRESTATAIRES EXTERNES */
    sortie.prestataires = await m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = S.collection('prestataires');
      const out = { jeu: col.all().length };
      window.__graphes.length = 0;
      const racine = await H.monter('m10-prestataires');
      out.ecran = H.lireEcran(racine);
      out.graphes = H.graphes();
      out.cartes = H.cartesTexte(racine);
      out.lignes = H.lignesPage(racine);
      out.filtres = H.filtres(racine);
      out.boutonsLigne = [...H.ligne(racine, 'PE-0001').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(H.ligne(racine, 'PE-0001'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      out.etats = {};
      for (const [cle, p] of [['sansFacture', col.all().find((x) => !x.factureNormalisee)], ['avecFacture', col.all().find((x) => x.factureNormalisee && x.ifu)]]) {
        await H.chercher(racine, p.reference);
        window.__etats.length = 0;
        H.icone(H.ligne(racine, p.reference), 'Imprimer l’état').click(); await H.dormir(200);
        out.etats[cle] = { reference: p.reference, etat: H.propre(window.__etats[0]) };
      }
      await H.chercher(racine, '');
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: {} };
      ['nom', 'specialite', 'telephone', 'tarifActe', 'actesRealises', 'ifu', 'factureNormalisee'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      ['specialite'].forEach((n) => { out.creation.options[n] = H.optsDe(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('nom', 'Dr ZOUMAROU Ali'); H.poser('specialite', 'Échographie'); H.poser('tarifActe', '15000'); H.poser('actesRealises', '4');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      const ref = col.all()[0].reference;
      await H.chercher(racine, ref);
      out.creation.apres = { kpis: H.kpis(racine), lignes: H.lignesPage(racine) };
      H.icone(H.ligne(racine, ref), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['nom', 'specialite', 'telephone', 'tarifActe', 'actesRealises', 'ifu', 'factureNormalisee'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('actesRealises', '6'); H.poser('factureNormalisee', true); H.poser('ifu', '3201700000001');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.reference === ref)) };
      H.icone(H.ligne(racine, ref), 'Archiver').click(); await H.confirmer('Doublon');
      await H.chercher(racine, '');
      out.archivage = { fiche: H.net(col.all().find((x) => x.reference === ref)), kpis: H.kpis(racine), onglets: H.onglets(racine) };
      H.retirer(racine);
      return out;
    });

    sortie.erreurs = await m.page.evaluate(() => window.__erreurs);
    ecrire('packages/domaine/test/vecteurs/rh.json', sortie);
    console.log('  erreurs de page : ' + sortie.erreurs.length);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
