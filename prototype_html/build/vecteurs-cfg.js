/* =============================================================================
 * VECTEURS DE CFG (A) — organisation, identité, tarifs, catalogue, en-têtes, types de pièce, rappels, certificats,
 * natures de facture, catalogue de l'imagerie : les DIX écrans, PILOTÉS comme le fait l'agent.
 * -----------------------------------------------------------------------------
 * Le script monte les écrans réels de `assets/js/modules/configuration.js` (réponse du tableau, modales, filtres, onglets) et relit ce qui s'affiche
 * et ce qui naît au magasin. Rien n'est tiré de la lecture du code : une règle y est enregistrée parce que l'écran l'a RENDUE.
 *   SIGH_PORT_PHP=10211 flock /tmp/sigh-banc.lock node build/vecteurs-cfg.js   →   packages/domaine/test/vecteurs/cfg.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de CFG — dix écrans de configuration');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/configuration.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, N = SIGH.nav, D = SIGH.data, U = SIGH.ui;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const toasts = [];
      const toastOrig = U.toast;
      U.toast = function (msg, opts) { toasts.push({ message: msg, type: (opts && opts.type) || null, detail: (opts && opts.detail) || null }); return toastOrig.apply(U, arguments); };
      const nettoyer = () => document.querySelectorAll('.modal-root, [role=dialog], .drawer-root').forEach((e) => e.remove());
      const montrer = async (id) => { nettoyer(); document.querySelectorAll('[data-vecteur]').forEach((e) => e.remove()); const r = document.createElement('div'); r.setAttribute('data-vecteur', id); document.body.appendChild(r); SIGH.screens[id].render(r); await dormir(40); return r; };
      const texte = (e) => e.textContent.replace(/\s+/g, ' ').trim();
      const bouton = (txt, dans) => [...(dans || document).querySelectorAll('button')].find((b) => texte(b) === txt || texte(b).startsWith(txt) || (b.getAttribute('title') || b.getAttribute('aria-label')) === txt);
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else e.value = v; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true })); };
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => [texte(k.querySelector('.kpi-label')), texte(k.querySelector('.kpi-value')), k.querySelector('p.mt-1.text-xs.text-slate-400') ? texte(k.querySelector('p.mt-1.text-xs.text-slate-400')) : null]);
      const tableau = (root, n) => { const t = [...root.querySelectorAll('table')][n || 0]; if (!t) return null; return { entetes: [...t.querySelectorAll('thead th')].map(texte), lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) }; };
      const notes = (root) => [...root.querySelectorAll('div.flex.items-start.gap-2.rounded-lg.border.px-3.py-2')].map(texte);
      const onglets = (root) => [...root.querySelectorAll('[role=tab]')].map((b) => texte(b));
      const onglet = async (root, debut) => { const b = [...root.querySelectorAll('[role=tab]')].find((x) => texte(x).startsWith(debut)); if (!b) throw new Error('onglet ' + debut); b.click(); await dormir(60); };
      const compteur = (root) => { const p = [...root.querySelectorAll('p, span, div')].filter((e) => e.children.length === 0 && /\d+\s*(résultat|enregistrement|ligne)/i.test(e.textContent)); return p.map(texte).slice(0, 3); };
      const imprime = []; const etatOrig = SIGH.print.etat;
      SIGH.print.etat = function (o) { imprime.push({ titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null, texte: o.contenu && o.contenu.textContent ? texte(o.contenu).slice(0, 2500) : null }); };
      const sansBruit = (x) => { const c = Object.assign({}, x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statut'].forEach((k) => delete c[k]); return propre(c); };
      const creerPar = async (ecran, boutonTxt, saisie, validerTxt, col, ouvrirOnglet) => {
        const root = await montrer(ecran); if (ouvrirOnglet) await onglet(root, ouvrirOnglet);
        const avant = new Set(col().all().map((x) => x.id)); const nb = toasts.length;
        bouton(boutonTxt, root).click(); await dormir(40);
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        bouton(validerTxt || 'Créer', document.querySelector('.modal-root, [role=dialog]') || document).click(); await dormir(60);
        const nouveaux = col().all().filter((x) => !avant.has(x.id));
        return { saisie, creees: nouveaux.map(sansBruit), toasts: toasts.slice(nb).map((t) => t.message), nbAvant: avant.size };
      };
      /* Les créations de produit et d'analyse rechargent la PAGE (`location.reload()`) : le pilote le neutralise — l'écart est consigné (E840). */
      const creerOrig = SIGH.kit.creer; let rechargements = 0;
      SIGH.kit.creer = function (col, champs, opts) { if (opts && opts.apres && /reload/.test(String(opts.apres))) { opts.apres = function () { rechargements++; }; } return creerOrig.apply(this, arguments); };
      const sortie = {};

      /* ---------- Constantes tirées de la maquette (référentiels statiques lus par ces écrans) ---------- */
      sortie.constantes = propre({
        ns145: D.NS145, famillesTarif: D.FAMILLES_TARIF, secteursActivite: D.SECTEURS_ACTIVITE,
        brand: Object.assign({}, C.BRAND, {}), imagerieTypes: D.IMAGERIE.TYPES, modalites: D.IMAGERIE.MODALITES.map((x) => ({ code: x.code, label: x.label })),
        categoriesProduit: D.CATEGORIES_PRODUIT,
        roles: Object.keys(N.ROLES).map((r) => [r, N.ROLES[r].label, !!N.roleArchive(r)]),
        jour: C.iso(C.aujourdhui()),
      });

      /* ---------- 1. cfg-organisation ---------- */
      sortie.organisation = await (async () => {
        const root = await montrer('cfg-organisation');
        const o = { kpis: kpis(root), onglets: onglets(root), secteurs: tableau(root), notes: notes(root) };
        bouton('Imprimer la répartition', root).click(); await dormir(20);
        o.impressionRepartition = imprime.pop();
        await onglet(root, 'Organigramme');
        o.organigramme = tableau(root);
        o.arbre = [...root.querySelectorAll('div.mb-2.flex.flex-wrap.items-center.gap-2.rounded-lg.border')].map(texte);
        bouton('Imprimer l’organigramme', root).click(); await dormir(20);
        o.impressionOrganigramme = imprime.pop();
        await onglet(root, 'Poste');
        o.roles = tableau(root); o.notesRoles = notes(root);
        o.lectureSeule = texte(root.querySelector('.card') || root).slice(0, 10);
        return o;
      })();
      sortie.organisationCreations = {
        secteurSansCode: await creerPar('cfg-organisation', 'Nouveau', { libelle: 'Zone Test Alpha', role: 'infirmier' }, 'Créer', () => S.collection('secteurs')),
        secteurAvecCode: await creerPar('cfg-organisation', 'Nouveau', { libelle: 'Bloc Annexe', code: 'bka', role: 'da', responsable: 'TEST Responsable' }, 'Créer', () => S.collection('secteurs')),
        posteSommet: await creerPar('cfg-organisation', 'Nouveau', { poste: 'Poste Test Sommet', effectif: 2, role: 'infirmier', parentId: '' }, 'Créer', () => S.collection('postes'), 'Organigramme'),
      };

      /* ---------- 2. cfg-branding ---------- */
      sortie.branding = await (async () => {
        const root = await montrer('cfg-branding');
        const champs = {}; root.querySelectorAll('[id^=f_]').forEach((e) => { champs[e.id.slice(2)] = e.type === 'checkbox' ? e.checked : e.value; });
        const o = { champs, cartes: [...root.querySelectorAll('.card-head, .card h3, .card-title')].map(texte).slice(0, 6), commandes: [...root.querySelectorAll('button')].map(texte).filter(Boolean), notes: notes(root) };
        o.apercu = texte(root.querySelector('.rounded-lg.border.border-slate-300.bg-white.p-4'));
        o.ressources = [...root.querySelectorAll('div.flex.items-center.gap-3.rounded-lg.border.border-slate-200.px-3.py-2')].map(texte);
        bouton('Prévisualiser un état', root).click(); await dormir(20);
        o.impression = imprime.pop();
        const nbAudit = (S.raw().audit || []).length; const nb = toasts.length;
        bouton('Enregistrer', root).click(); await dormir(40);
        o.enregistrement = { toasts: toasts.slice(nb), audit: propre((S.raw().audit || [])[0] || null), nbAudit: (S.raw().audit || []).length - nbAudit };
        poser('nom', ''); poser('ifu', '');
        const nb2 = toasts.length; bouton('Enregistrer', root).click(); await dormir(40);
        o.refus = toasts.slice(nb2);
        return o;
      })();

      /* ---------- 3. cfg-tarifs ---------- */
      sortie.tarifs = await (async () => {
        const root = await montrer('cfg-tarifs');
        const o = { kpis: kpis(root), onglets: onglets(root), cartes: [...root.querySelectorAll('.card-head')].map(texte), flux: texte(root.querySelector('.card')).slice(0, 200) };
        o.produits = tableau(root); o.notesProduits = notes(root);
        await onglet(root, 'Analyses'); o.analyses = tableau(root); o.notesAnalyses = notes(root);
        await onglet(root, 'Actes'); o.actes = tableau(root); o.notesActes = notes(root);
        const selects = [...root.querySelectorAll('select')];
        o.filtres = [];
        for (const s of selects) {
          const opts = [...s.options].map((x) => [x.value, texte(x)]);
          const lib = texte(s.options[0]);
          if (!/Tarif/i.test(lib)) continue;
          for (const [v, l] of opts) { if (!v) continue; s.value = v; s.dispatchEvent(new Event('change')); await dormir(40); o.filtres.push({ valeur: v, libelle: l, compteur: compteur(root), premieres: ((tableau(root) || { lignes: [] }).lignes).slice(0, 3).map((r) => r[0]) }); }
          s.value = ''; s.dispatchEvent(new Event('change')); await dormir(30);
        }
        await onglet(root, 'Certificats'); o.certificats = tableau(root); o.notesCertificats = notes(root);
        return o;
      })();
      sortie.tarifsCreations = {
        medicament: await creerPar('cfg-tarifs', 'Nouveau', { designation: 'Médicament Test A', categorie: 'medicament', prixAchat: 700, prixVente: 900 }, 'Créer', () => S.collection('produits'), 'Produits'),
        consommable: await creerPar('cfg-tarifs', 'Nouveau', { designation: 'Consommable Test B', categorie: 'conso_medical', prixAchat: 300, prixVente: 450, code: 'CTB-1' }, 'Créer', () => S.collection('produits'), 'Produits'),
        analyse: await creerPar('cfg-tarifs', 'Nouveau', { designation: 'Analyse Test', categorie: 'Hématologie', prix: 2500 }, 'Créer', () => S.collection('analyses'), 'Analyses'),
        acteSansPrix: await creerPar('cfg-tarifs', 'Nouveau', { libelle: 'Acte Test Sans Prix', secteur: D.SECTEURS_ACTIVITE[0] }, 'Créer', () => S.collection('actes'), 'Actes'),
        acteAvecPrix: await creerPar('cfg-tarifs', 'Nouveau', { libelle: 'Acte Test Prix', secteur: D.SECTEURS_ACTIVITE[0], prix: 4000, code: 'TST-9' }, 'Créer', () => S.collection('actes'), 'Actes'),
      };

      /* ---------- 4. cfg-catalogue ---------- */
      sortie.catalogue = await (async () => {
        const root = await montrer('cfg-catalogue');
        const o = { kpis: kpis(root), notes: notes(root), onglets: onglets(root), familles: [] };
        const tabs = [...root.querySelectorAll('[role=tab]')];
        for (let i = 0; i < tabs.length; i++) {
          tabs[i].click(); await dormir(60);
          const t = tableau(root);
          const detail = [];
          // le détail (tiroir) de chaque ligne à marque : sans prix, non couvert, SOS, arbitré
          const lignes = [...root.querySelectorAll('tbody tr')];
          for (const tr of lignes) {
            const tx = texte(tr);
            if (/non renseigné|NON COUVERT|SOS seule|arbitré/.test(tx)) {
              const oeil = [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('title') || b.getAttribute('aria-label')) === 'Consulter');
              if (oeil) { oeil.click(); await dormir(40); const d = document.querySelector('.drawer-root, [role=dialog]'); detail.push({ ligne: [...tr.querySelectorAll('td')].map(texte), tiroir: d ? texte(d) : null }); nettoyer(); }
            }
          }
          o.familles.push({ onglet: texte(tabs[i]), tableau: t, detail });
        }
        return o;
      })();
      sortie.catalogueDetails = await (async () => {
        const root = await montrer('cfg-catalogue');
        const rows = S.collection('catalogueTarifs').active();
        const cibles = [].concat(rows.filter((r) => r.arbitrage).slice(0, 1), rows.filter((r) => r.nonCouvert).slice(0, 1), rows.filter((r) => r.aArbitrer).slice(0, 1), rows.filter((r) => r.motifPrix).slice(0, 1), rows.filter((r) => r.assurable === 'sos').slice(0, 1));
        const out = [];
        for (const r of cibles) {
          const bt = root.querySelector('[data-tab=' + r.famille.toLowerCase() + ']'); if (bt) { bt.click(); await dormir(120); }
          const champ = [...root.querySelectorAll('input')].find((i) => /echerch/i.test(i.placeholder || '') && i.offsetParent !== null) || root.querySelector('input[type=search]');
          champ.value = r.code; champ.dispatchEvent(new Event('input')); await dormir(300);
          const tr = [...root.querySelectorAll('tbody tr')].find((x) => texte(x).includes(r.code));
          if (!tr) { out.push({ code: r.code, absent: true }); continue; }
          const oeil = [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('title') || b.getAttribute('aria-label')) === 'Consulter');
          oeil.click(); await dormir(40); const d = document.querySelector('.drawer-root, [role=dialog]');
          out.push({ code: r.code, drapeaux: { arbitrage: !!r.arbitrage, nonCouvert: !!r.nonCouvert, aArbitrer: !!r.aArbitrer, motifPrix: !!r.motifPrix, assurable: r.assurable === undefined ? null : r.assurable }, ligne: [...tr.querySelectorAll('td')].map(texte), tiroir: d ? texte(d) : null }); nettoyer();
        }
        return out;
      })();
      sortie.catalogueCreations = {
        complet: await creerPar('cfg-catalogue', 'Nouvel acte', { code: 'TST-C1', libelle: 'Acte Test Complet', famille: D.FAMILLES_TARIF[0].code, prixNonAssure: 5000, prixAssure: 4000 }, 'Créer', () => S.collection('catalogueTarifs')),
        sansPrixAssure: await creerPar('cfg-catalogue', 'Nouvel acte', { code: 'TST-C2', libelle: 'Acte Test Sans Assuré', famille: D.FAMILLES_TARIF[0].code, prixNonAssure: 5000 }, 'Créer', () => S.collection('catalogueTarifs')),
        nonCouvert: await creerPar('cfg-catalogue', 'Nouvel acte', { code: 'TST-C3', libelle: 'Acte Test Non Couvert', famille: D.FAMILLES_TARIF[0].code, prixNonAssure: 5000, nonCouvert: true, source: 'Document test' }, 'Créer', () => S.collection('catalogueTarifs')),
        sansPrix: await creerPar('cfg-catalogue', 'Nouvel acte', { code: 'TST-C4', libelle: 'Acte Test Sans Prix', famille: D.FAMILLES_TARIF[0].code }, 'Créer', () => S.collection('catalogueTarifs')),
      };

      /* ---------- 5. cfg-entetes ---------- */
      sortie.entetes = await (async () => { const root = await montrer('cfg-entetes'); return { kpis: kpis(root), notes: notes(root), grille: [...root.querySelectorAll('dl, .desc-list, .grid')].map(texte).slice(0, 2), texte: texte(root) }; })();

      /* ---------- 6. cfg-types-piece ---------- */
      sortie.typesPiece = await (async () => {
        const root = await montrer('cfg-types-piece');
        const o = { kpis: kpis(root), notes: notes(root), tableau: tableau(root), details: [] };
        for (const tr of [...root.querySelectorAll('tbody tr')]) {
          const oeil = [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('title') || b.getAttribute('aria-label')) === 'Consulter');
          if (!oeil) continue;
          oeil.click(); await dormir(40); const d = document.querySelector('.drawer-root, [role=dialog]');
          o.details.push({ ligne: [...tr.querySelectorAll('td')].map(texte), tiroir: d ? texte(d) : null }); nettoyer();
        }
        return o;
      })();
      sortie.typesPieceCreations = { sansTarif: await creerPar('cfg-types-piece', 'Nouveau type de pièce', { sigle: 'TST', libelle: 'Pièce test', direction: 'DM' }, 'Créer', () => S.collection('typesPiece')) };

      /* ---------- 7. cfg-rappels ---------- */
      sortie.rappels = await (async () => {
        const root = await montrer('cfg-rappels');
        const o = { kpis: kpis(root), notes: notes(root), onglets: onglets(root), modeles: tableau(root), apercus: [] };
        for (const tr of [...root.querySelectorAll('tbody tr')]) {
          const oeil = [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('title') || b.getAttribute('aria-label')) === 'Consulter');
          oeil.click(); await dormir(40); const d = document.querySelector('.drawer-root, [role=dialog]');
          o.apercus.push({ ligne: [...tr.querySelectorAll('td')].map(texte), tiroir: d ? texte(d) : null }); nettoyer();
        }
        await onglet(root, 'Rappels'); o.rappelsVide = tableau(root);
        await onglet(root, 'Variables'); o.variables = [...root.querySelectorAll('table')].map((t) => ({ entetes: [...t.querySelectorAll('thead th')].map(texte), lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) })); o.notesVariables = notes(root);
        return o;
      })();
      sortie.rappelsAnniversaires = await (async () => {
        const auj = new Date(); const jour = String(auj.getMonth() + 1).padStart(2, '0') + '-' + String(auj.getDate()).padStart(2, '0');
        const patients = S.collection('patients').active();
        const p1 = patients[0], p2 = patients[1];
        const avant1 = p1.dateNaissance, avant2 = p2.dateNaissance;
        S.collection('patients').update(p1.id, { dateNaissance: '1990-' + jour });
        S.collection('patients').update(p2.id, { dateNaissance: '2001-' + jour });
        const root = await montrer('cfg-rappels'); await onglet(root, 'Rappels');
        const nb = toasts.length; const colR = S.collection('rappels'); const avant = colR.all().length;
        bouton('Préparer les anniversaires du jour', root).click(); await dormir(60);
        const premier = { toasts: toasts.slice(nb), rappels: colR.all().slice(avant).map((r) => sansBruit(r)), onglets: onglets(root), actif: texte(root.querySelector('.tab-active')) };
        const nb2 = toasts.length; await onglet(root, 'Rappels');
        bouton('Préparer les anniversaires du jour', root).click(); await dormir(60);
        const second = { toasts: toasts.slice(nb2), crees: colR.all().length - avant - premier.rappels.length };
        const modele = S.collection('modelesMessage').active().find((x) => x.occasion === 'anniversaire');
        S.collection('modelesMessage').update(modele.id, { actif: false });
        const root2 = await montrer('cfg-rappels'); await onglet(root2, 'Rappels'); const nb3 = toasts.length;
        bouton('Préparer les anniversaires du jour', root2).click(); await dormir(40);
        const sansModele = toasts.slice(nb3);
        S.collection('modelesMessage').update(modele.id, { actif: true });
        return { jour: C.iso(auj), patients: [{ nom: p1.nom + ' ' + p1.prenom, tel: p1.telephone || null, dateNaissance: '1990-' + jour }, { nom: p2.nom + ' ' + p2.prenom, tel: p2.telephone || null, dateNaissance: '2001-' + jour }], texteModele: modele.texte, premier, second, sansModele, avant: [avant1, avant2] };
      })();
      sortie.rappelsCreations = { modele: await creerPar('cfg-rappels', 'Nouveau modèle', { occasion: 'fete', libelle: 'Modèle test', texte: 'Bonjour {{nom}} — {{inconnu}} à {{clinique}}', actif: true }, 'Créer', () => S.collection('modelesMessage')) };

      /* ---------- 8. cfg-certificats ---------- */
      sortie.certificats = await (async () => {
        const root = await montrer('cfg-certificats');
        const o = { kpis: kpis(root), cartes: [...root.querySelectorAll('.card-head')].map(texte), cartesTypes: [...root.querySelectorAll('button.rounded-xl')].map(texte), tableau: tableau(root), composes: [] };
        const cartes = [...root.querySelectorAll('button.rounded-xl')];
        const patient = S.collection('patients').active().find((p) => p.dateNaissance) || S.collection('patients').active()[0];
        const praticien = S.collection('personnel').active().find((e) => e.fonction === 'medecin' || e.fonction === 'sage_femme');
        const valeursParChamp = { duree: '3', dateDebut: '2026-08-17', termeSemaines: '28', datePresumee: '2026-11-20', dateAccouchement: '2026-08-10', sexeEnfant: 'féminin', constatations: 'une plaie superficielle du bras', itt: '5', affection: 'un paludisme simple', dateGuerison: '2026-08-12', examens: 'NFS, groupe sanguin, sérologies', activite: 'la natation' };
        for (const carte of cartes) {
          carte.click(); await dormir(40);
          const modal = document.querySelector('.modal-root, [role=dialog]');
          const ids = [...modal.querySelectorAll('[id^=f_]')].map((e) => e.id.slice(2));
          const apercuVide = texte(modal.querySelector('.rounded-lg.border.border-slate-200.bg-slate-50'));
          poser('patientCode', patient.code); poser('praticien', praticien.nomComplet);
          ids.forEach((k) => { if (valeursParChamp[k] !== undefined) poser(k, valeursParChamp[k]); });
          const apercuRempli = texte(modal.querySelector('.rounded-lg.border.border-slate-200.bg-slate-50'));
          const champsLib = [...modal.querySelectorAll('label')].map(texte);
          o.composes.push({ carte: texte(carte), champs: ids, libelles: champsLib, apercuVide, apercuRempli });
          nettoyer();
        }
        o.patient = { code: patient.code, nom: patient.nom + ' ' + patient.prenom }; o.praticien = praticien.nomComplet; o.valeurs = valeursParChamp;
        // délivrance du premier type (repos) puis annulation motivée
        cartes[0].click(); await dormir(40);
        poser('patientCode', patient.code); poser('praticien', praticien.nomComplet); poser('date', '2026-08-16'); poser('duree', '3'); poser('dateDebut', '2026-08-17');
        const col = S.collection('certificats'); const avant = col.all().length; const nb = toasts.length;
        bouton('Délivrer le certificat', document.querySelector('.modal-root, [role=dialog]')).click(); await dormir(80);
        o.delivrance = { fiche: col.all().slice(avant).map(sansBruit), toasts: toasts.slice(nb), impression: imprime.pop(), journal: propre((S.raw().audit || [])[0]) };
        o.registre = tableau(await montrer('cfg-certificats'));
        o.kpisApres = kpis(document.querySelector('[data-vecteur=cfg-certificats]'));
        return o;
      })();

      /* ---------- 9. cfg-natures-facture ---------- */
      sortie.natures = await (async () => { const root = await montrer('cfg-natures-facture'); return { kpis: kpis(root), tableau: tableau(root), notes: notes(root) }; })();
      sortie.naturesCreations = {
        sansCode: await creerPar('cfg-natures-facture', 'Nouveau', { libelle: 'Soins externes test', secteur: D.SECTEURS_ACTIVITE[0] }, 'Créer', () => S.collection('naturesFacture')),
        avecCode: await creerPar('cfg-natures-facture', 'Nouveau', { libelle: 'Dentisterie', code: 'dent', secteur: D.SECTEURS_ACTIVITE[0], source: 'Note test' }, 'Créer', () => S.collection('naturesFacture')),
      };

      /* ---------- 10. cfg-imagerie-catalogue ---------- */
      sortie.imagerie = await (async () => {
        const root = await montrer('cfg-imagerie-catalogue');
        const o = { kpis: kpis(root), onglets: onglets(root), examens: tableau(root) };
        await onglet(root, 'Variables'); o.variables = tableau(root);
        return o;
      })();
      sortie.imagerieCreations = await (async () => {
        const ex = S.collection('examensImagerie').active()[0];
        const examen = await creerPar('cfg-imagerie-catalogue', 'Nouvel examen', { code: 'TST-IM1', label: 'Examen test', modalite: D.IMAGERIE.MODALITES[0].code, voie: 'sus-pubienne' }, 'Créer', () => S.collection('examensImagerie'));
        const variable = await creerPar('cfg-imagerie-catalogue', 'Nouvelle variable', { examen: ex.code, code: 'TST_V1', libelle: 'Variable test', type: D.IMAGERIE.TYPES[0].code, optionsTexte: ' homogène | hétérogène ||  ', rubrique: 'Résultat', ordre: '7' }, 'Créer', () => S.collection('variablesImagerie'), 'Variables');
        const sans = await creerPar('cfg-imagerie-catalogue', 'Nouvelle variable', { examen: ex.code, code: 'TST_V2', libelle: 'Variable sans choix', type: D.IMAGERIE.TYPES[0].code, rubrique: 'Résultat', ordre: '8', unite: 'mm' }, 'Créer', () => S.collection('variablesImagerie'), 'Variables');
        // fermeture / réouverture d'une variable
        const root = await montrer('cfg-imagerie-catalogue'); await onglet(root, 'Variables');
        const cible = S.collection('variablesImagerie').active().find((v) => v.code === 'TST_V2');
        const tr = [...root.querySelectorAll('tbody tr')].find((x) => texte(x).includes('Variable sans choix'));
        const nb = toasts.length;
        [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('title') || b.getAttribute('aria-label')) === 'Fermer la variable').click(); await dormir(40);
        const apresFermeture = { actif: S.collection('variablesImagerie').get(cible.id).actif, toasts: toasts.slice(nb) };
        return { examen, variable, sans, apresFermeture };
      })();

      sortie.rechargements = rechargements;
      return propre(sortie);
    });
    ecrire('packages/domaine/test/vecteurs/cfg.json', sortie);
    if (m.erreurs.length) console.log('  erreurs JS de la page :', m.erreurs.slice(0, 5));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
