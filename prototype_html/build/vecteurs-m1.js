/* =============================================================================
 * VECTEURS M1 — Patients & Dossier médical : m1-patients, m1-patient-nouveau, m1-patient-profil, m1-antecedents, m1-constantes,
 * m1-reference, m1-contre-reference, m1-pieces, m1-externe, m1-documents.
 * -----------------------------------------------------------------------------
 * Les écrans RÉELS sont montés dans la page d'extraction, leurs formulaires remplis comme le fait l'agent, leurs boutons cliqués, et ce qui est né
 * au magasin (ou ce que l'écran affiche) est relu. Rien n'est tiré de la lecture du code.
 *   node build/vecteurs-m1.js [patients|antecedents|constantes|reference|pieces|externe|documents]
 *   →   packages/domaine/test/vecteurs/pat_*.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

/** Boîte à outils exécutée DANS la page (chaîne évaluée une fois par section). */
const OUTILS = `
  window.__go = [];
  SIGH.app.go = (id, o) => { window.__go.push(o ? [id, o] : id); };
  window.__O = (() => {
    const S = SIGH.store, C = SIGH.core, U = SIGH.ui;
    const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
    const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
    const net = (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', 'id'].forEach((k) => delete c[k]); return propre(c); };
    const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim()).join(' | '));
    const viderToasts = () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; try { sessionStorage.removeItem('sigh-cnt:message-differe'); } catch (e) {} };
    const differe = () => { try { const b = sessionStorage.getItem('sigh-cnt:message-differe'); return b ? JSON.parse(b) : null; } catch (e) { return null; } };
    const fermer = () => document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
    const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
    const monter = async (id, attente) => { const root = document.createElement('div'); document.body.appendChild(root); SIGH.screens[id].render(root); await dormir(attente || 80); return root; };
    const norm = (t) => String(t || '').replace(/\\s+/g, ' ').trim();
    const kpis = (root) => { const g = root.querySelector('.grid.gap-3'); return g ? [...g.children].map((n) => [...n.querySelectorAll('p,span,div')].filter((x) => !x.children.length).map((x) => norm(x.textContent)).filter(Boolean)) : []; };
    const lignes = (root, i) => { const t = root.querySelectorAll('table')[i || 0]; return t ? [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map((c) => norm(c.innerText))) : []; };
    const entetes = (root, i) => { const t = root.querySelectorAll('table')[i || 0]; return t ? [...t.querySelectorAll('thead th')].map((c) => norm(c.innerText)) : []; };
    const onglets = (root) => [...root.querySelectorAll('[role=tab]')].map((b) => norm(b.textContent));
    const ongletPar = async (root, debut) => { const b = [...root.querySelectorAll('[role=tab]')].find((x) => norm(x.textContent).startsWith(debut)); if (!b) throw new Error('onglet ' + debut); b.click(); await dormir(60); };
    const bouton = (racine, texte) => !racine ? (() => { throw new Error('ligne introuvable pour « ' + texte + ' »'); })() : [...racine.querySelectorAll('button')].find((b) => norm(b.textContent) === texte || b.getAttribute('aria-label') === texte || b.title === texte);
    const dernier = (texte) => [...document.querySelectorAll('button')].filter((b) => norm(b.textContent) === texte).pop();
    const diff = (a, b) => { const p = {}; Object.keys(Object.assign({}, a, b)).forEach((k) => { if (k[0] !== '_' && JSON.stringify(a[k]) !== JSON.stringify(b[k])) p[k] = b[k] === undefined ? null : b[k]; }); return p; };
    const echanger = (col, nouvelles) => { const sauve = col.all().splice(0); nouvelles.forEach((f) => col.all().push(f)); return () => { col.all().splice(0); sauve.forEach((f) => col.all().push(f)); }; };
    return { S, C, U, propre, dormir, net, toasts, viderToasts, differe, fermer, poser, monter, norm, kpis, lignes, entetes, onglets, ongletPar, bouton, dernier, diff, echanger };
  })();
`;

async function section(nom, fn) {
  console.log('▶ Vecteurs M1 — ' + nom);
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m1-patients.js') });
    await m.page.evaluate(OUTILS);
    const out = await fn(m.page);
    if (m.erreurs.length) console.log('  erreurs de page : ' + m.erreurs.slice(0, 3).join(' ; '));
    return out;
  } finally { await m.fermer(); }
}

const quoi = process.argv[2] || 'tout';
const veut = (n) => quoi === 'tout' || quoi === n;

(async () => {
  if (veut('patients')) {
    const out = await section('patients', (page) => page.evaluate(async () => {
      const { S, C, D, U, propre, dormir, net, toasts, viderToasts, differe, poser, monter, norm, kpis, lignes, entetes, onglets, bouton, dernier, diff, echanger } = Object.assign({ D: SIGH.data }, window.__O);
      const colP = S.collection('patients');
      const res = {};

      /* ---------------------------------------------------------------- prochain code */
      const fiche = (code, statut) => ({ id: 'T' + Math.random().toString(36).slice(2), statut: statut || 'actif', code, nom: 'N', prenom: 'P' });
      const cas = [];
      async function prochain(nomCas, codes) {
        const rendre = echanger(colP, codes.map((c) => (Array.isArray(c) ? fiche(c[0], c[1]) : fiche(c))));
        const root = await monter('m1-patient-nouveau');
        cas.push({ nom: nomCas, codes: codes.map((c) => (Array.isArray(c) ? c : [c, 'actif'])), attendu: document.getElementById('f_code').value });
        root.remove(); rendre();
      }
      await prochain('registre vide', []);
      await prochain('nouveau format seul : plus grand rang + 1', ['CNT/1/26', 'CNT/12/26', 'CNT/7/26']);
      await prochain('ancien format seul', ['CNT530/26', 'CNT12/26']);
      await prochain('les deux formats se lisent ensemble', ['CNT/1109/26', 'CNT530/26', 'CNT/20/26']);
      await prochain('une autre année est ignorée', ['CNT/900/25', 'CNT/4/26', 'CNT/50/27']);
      await prochain('un dossier archivé garde son rang (RG-01)', [['CNT/40/26', 'archive'], 'CNT/3/26']);
      await prochain('code illisible ignoré', ['CNT-X', 'CNT/8/26', '', 'CNT//26']);
      res.prochainCode = { _doc: 'm1-patient-nouveau : le champ « Code dossier » à l\'ouverture (prochainCode)', anneeCourante: new Date().getFullYear(), cas };

      /* ---------------------------------------------------------------- création par la page */
      const creations = [];
      const assureur = D.ASSUREURS[1];
      async function creer(nomCas, saisie, avant) {
        const root = await monter('m1-patient-nouveau');
        if (avant) avant();
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        const ids = new Set(colP.all().map((x) => x.id));
        window.__go.length = 0; viderToasts();
        root.__enregistrerPage();
        await dormir(80);
        const cree = colP.all().filter((x) => !ids.has(x.id)).map(net);
        creations.push({ nom: nomCas, saisie, codeAffiche: null, crees: cree, toasts: toasts(), differe: differe(), aller: propre(window.__go) });
        root.remove();
      }
      const base = { nom: 'Bio', prenom: 'Zakari', sexe: 'M', naissanceConnue: 'date', dateNaissance: '1990-05-12', telephone: '97000001' };
      await creer('patient sans assurance, date de naissance connue', base);
      await creer('âge déclaré : la date est effacée et l\'âge est daté du jour', Object.assign({}, base, { nom: 'Kora', naissanceConnue: 'age', age: '41' }));
      await creer('assuré : le nom de la compagnie est repris du référentiel', Object.assign({}, base, { nom: 'Assure', assureur: assureur.code, numeroPolice: 'P-1', tauxPriseEnCharge: 80, carteExpiration: '2027-01-31' }));
      await creer('éléments médicaux : listes multiples', Object.assign({}, base, { nom: 'Listes', antecedents: ['Asthme', 'Épilepsie'], allergies: ['Sulfamides'], groupeSanguin: 'O+', traitementEnCours: 'Salbutamol' }));
      await creer('champ obligatoire vide : le formulaire refuse', { prenom: 'Sans nom', sexe: 'F', naissanceConnue: 'date', dateNaissance: '1990-01-01', telephone: '1' });
      await creer('date de naissance dans le futur : refus', Object.assign({}, base, { nom: 'Futur', dateNaissance: '2999-01-01' }));
      // Deux guichets : le code réservé à l'ouverture est pris entre-temps.
      const racine2 = await monter('m1-patient-nouveau');
      const codeRes = document.getElementById('f_code').value;
      colP.insert({ code: codeRes, nom: 'Voleur', prenom: 'Code', sexe: 'M', statut: 'actif', dateNaissance: '1980-01-01', telephone: '1' });
      Object.entries(base).forEach(([k, v]) => poser(k, v));
      viderToasts(); racine2.__enregistrerPage(); await dormir(60);
      creations.push({ nom: 'le code a été pris entre-temps : refus nommé, rien d\'écrit', saisie: base, codeReserve: codeRes, crees: [], toasts: toasts(), differe: differe(), aller: propre(window.__go) });
      racine2.remove();
      res.creation = { _doc: 'm1-patient-nouveau : formulaire rempli, « Ouvrir le dossier »', jour: C.iso(C.aujourdhui()), assureur: { code: assureur.code, nom: assureur.nom }, cas: creations };

      /* ---------------------------------------------------------------- répertoire : KPI, filtres */
      const hier = (n) => C.iso(new Date(Date.now() - n * 864e5));
      const p = (code, o) => Object.assign({ id: 'R' + code.replace(/\W/g, ''), statut: 'actif', code, nom: 'NOM' + code.slice(-3), prenom: 'Prénom', sexe: 'F', dateNaissance: '1990-01-01', telephone: '9' + code.slice(-3), quartier: 'Tchirimina', dateCreation: '2026-05-01' }, o || {});
      const jeu = [
        p('CNT/1/26'), p('CNT/2/26', { sexe: 'M', quartier: 'Boriyoure' }),
        p('CNT/3/26', { assureur: 'NSIA', assureurNom: 'NSIA ASSURANCE', souscripteur: 'ACME', carteExpiration: '2027-12-31', dateCreation: '2025-02-01' }),
        p('CNT/4/26', { assureur: 'SOS', assureurNom: 'SOS ASSURANCE', carteExpiration: '2025-01-01' }),
        p('CNT/5/26', { assureur: 'OLEA', assureurNom: 'OLEA ASSURANCE', carteExpiration: hier(-3), quartier: 'Boriyoure', sexe: 'M' }),
        p('CNT/6/26', { assureur: 'OLEA', assureurNom: 'OLEA ASSURANCE', carteExpiration: hier(1) }),
        p('CNT/7/26', { statut: 'archive' }),
        p('CNT/8/26', { dateNaissance: '', age: 30, ageReferenceLe: '2020-01-01' }),
      ];
      const rendre = echanger(colP, jeu);
      const root = await monter('m1-patients', 150);
      res.repertoire = { _doc: 'm1-patients sur un jeu posé', jeu: propre(jeu), jour: C.iso(C.aujourdhui()), kpis: kpis(root), onglets: onglets(root), lignes: lignes(root), entetes: entetes(root) };
      // Filtres : un par un, via les listes de la barre d'outils.
      const filtres = [];
      const selects = [...root.querySelectorAll('select')];
      res.repertoire.filtresDisponibles = selects.map((s) => ({ nom: s.getAttribute('aria-label') || s.name || s.id, options: [...s.options].map((o) => norm(o.textContent)) }));
      for (const s of selects) {
        for (const o of [...s.options].slice(1)) {
          s.value = o.value; s.dispatchEvent(new Event('change')); await dormir(40);
          filtres.push({ filtre: s.getAttribute('aria-label') || s.name || s.id, valeur: norm(o.textContent), codes: lignes(root).map((l) => l[0]) });
        }
        s.value = ''; s.dispatchEvent(new Event('change')); await dormir(30);
      }
      res.repertoire.filtres = filtres;
      // La fiche (tiroir) : le statut d'assurance et l'âge.
      root.remove(); rendre();
      return propre(res);
    }));
    ecrire('packages/domaine/test/vecteurs/pat_patients.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-m1.js — sorties des écrans M1 de la MAQUETTE, telles quelles. Ne pas éditer.' }, out));
  }
  if (veut('antecedents')) {
    const out = await section('antécédents', (page) => page.evaluate(async () => {
      const { S, C, propre, dormir, net, toasts, viderToasts, poser, monter, norm, kpis, lignes, entetes, bouton, dernier, diff, echanger } = window.__O;
      const colP = S.collection('patients');
      const p = (n, o) => Object.assign({ id: 'A' + n, statut: 'actif', code: 'CNT/' + n + '/26', nom: 'Nom' + n, prenom: 'Pre' + n, sexe: 'F', dateNaissance: '1990-01-01', telephone: '9' + n, quartier: 'Perma', dateCreation: '2026-01-01' }, o || {});
      const jeu = [
        p(1), p(2, { antecedents: ['Asthme'], allergies: ['Sulfamides'], groupeSanguin: 'O+', traitementEnCours: 'Salbutamol' }),
        p(3, { antecedents: ['Drépanocytose', 'Asthme'] }), p(4, { antecedents: 'Épilepsie', allergies: 'Pénicilline', antecedentsAutres: 'Césarienne 2019' }),
        p(5, { antecedents: 'Aucun antécédent notable', allergies: 'Aucune allergie connue' }), p(6, { antecedents: [], allergies: [] }),
        p(7, { antecedents: ['Diabète de type 2'], allergies: ['Arachide', 'Iode'] }), p(8, { statut: 'archive', antecedents: ['Hépatite B'] }),
      ];
      const rendre = echanger(colP, jeu);
      const root = await monter('m1-antecedents', 120);
      const res = { _doc: 'm1-antecedents sur un jeu posé', jeu: propre(jeu), kpis: kpis(root), entetes: entetes(root), lignes: lignes(root) };
      const selects = [...root.querySelectorAll('select')];
      res.filtresDisponibles = selects.map((s) => ({ nom: s.getAttribute('aria-label') || s.name || s.id, options: [...s.options].map((o) => norm(o.textContent)) }));
      res.filtres = [];
      for (const s of selects) {
        for (const o of [...s.options].slice(1)) {
          s.value = o.value; s.dispatchEvent(new Event('change')); await dormir(40);
          res.filtres.push({ filtre: s.getAttribute('aria-label') || s.name || s.id, valeur: norm(o.textContent), codes: lignes(root).map((l) => l[0]) });
        }
        s.value = ''; s.dispatchEvent(new Event('change')); await dormir(30);
      }
      // Modification : le formulaire est rempli depuis la fiche, puis « Enregistrer ».
      async function modifier(nom, code, saisie) {
        const q = root.querySelector('input[placeholder^="Patient"]');
        q.value = code; q.dispatchEvent(new Event('input')); await dormir(380);
        const tr = [...root.querySelectorAll('tbody tr')].find((x) => x.textContent.includes(code));
        const avant = net(colP.all().find((x) => x.code === code));
        bouton(tr, 'Modifier les antécédents').click(); await dormir(80);
        const prerempli = {};
        [...document.querySelectorAll('[id^=f_]')].forEach((e) => { prerempli[e.id.slice(2)] = e.type === 'checkbox' ? e.checked : (e.value === undefined ? null : e.value); });
        const titre = norm((document.querySelector('.modal-root, [role=dialog]') || { innerText: '' }).innerText).slice(0, 120);
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        viderToasts(); dernier('Enregistrer').click(); await dormir(80);
        const apres = net(colP.all().find((x) => x.code === code));
        const rep = { nom, code, saisie, titre, prerempli, patch: diff(avant, apres), toasts: toasts(), kpisApres: kpis(root) };
        q.value = ''; q.dispatchEvent(new Event('input')); await dormir(60);
        return rep;
      }
      res.modifications = [];
      res.modifications.push(await modifier('un antécédent à risque et une allergie', 'CNT/1/26', { antecedents: ['Drépanocytose', 'Asthme'], allergies: ['Iode', 'Pénicilline'], traitementEnCours: 'Hydroxyurée', groupeSanguin: 'A+' }));
      res.modifications.push(await modifier('fiche à deux antécédents : enregistrer n\'efface aucune valeur', 'CNT/3/26', { antecedentsAutres: 'Appendicectomie' }));
      res.modifications.push(await modifier('retour à « Aucun antécédent notable »', 'CNT/4/26', { antecedents: [], allergies: [] }));
      root.remove(); rendre();
      return propre(res);
    }));
    ecrire('packages/domaine/test/vecteurs/pat_antecedents.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-m1.js — sorties de m1-antecedents de la MAQUETTE. Ne pas éditer.' }, out));
  }

  if (veut('constantes')) {
    const out = await section('constantes', (page) => page.evaluate(async () => {
      const { S, C, propre, dormir, net, toasts, viderToasts, poser, monter, norm, kpis, lignes, entetes, bouton, dernier, diff, echanger } = window.__O;
      const colP = S.collection('patients'), colC = S.collection('constantes');
      const pats = [1, 2, 3].map((n) => ({ id: 'K' + n, statut: 'actif', code: 'CNT/' + n + '/26', nom: 'Nom' + n, prenom: 'Pre' + n, sexe: 'F', dateNaissance: '1990-01-01', telephone: '9', quartier: 'Perma', dateCreation: '2026-01-01' }));
      const rP = echanger(colP, pats);
      const aujourdhui = C.iso(C.aujourdhui());
      const rel = (n, o) => Object.assign({ id: 'C' + n, statut: 'actif', reference: 'CST-' + String(n).padStart(5, '0'), patientCode: 'CNT/1/26', patientId: 'K1', patient: 'Nom1 Pre1', dateHeure: aujourdhui + 'T0' + (n % 9) + ':00', moment: 'matin', releveePar: 'Agent', origine: 'accueil' }, o || {});
      const jeu = [
        rel(1, { temperature: 36, pouls: 60, fr: 12, spo2: 94 }),
        rel(2, { temperature: 38, pouls: 100, fr: 20, spo2: 100, tension: '12/8', tensionSys: 12, tensionDia: 8, poids: 70, taille: 175, imc: 22.9 }),
        rel(3, { temperature: 35.9 }), rel(4, { temperature: 38.1 }), rel(5, { pouls: 59 }), rel(6, { pouls: 101 }),
        rel(7, { fr: 11 }), rel(8, { fr: 21 }), rel(9, { spo2: 93 }), rel(10, { temperature: 39, pouls: 130, fr: 30, spo2: 85, patientId: 'K2', patientCode: 'CNT/2/26', patient: 'Nom2 Pre2', dateHeure: '2026-08-01T10:00' }),
        rel(11, { moment: 'soir', patientId: 'K3', patientCode: 'CNT/3/26', patient: 'Nom3 Pre3', dateHeure: '2026-08-02T10:00' }), rel(12, { moment: 'midi' }),
        rel(13, { statut: 'archive' }),
      ];
      const rC = echanger(colC, jeu);
      const root = await monter('m1-constantes', 150);
      const res = { _doc: 'm1-constantes sur un jeu posé', jour: aujourdhui, jeu: propre(jeu), kpis: kpis(root), entetes: entetes(root), lignes: lignes(root) };
      // Création
      const creations = [];
      async function creer(nom, saisie) {
        bouton(root, 'Nouveau relevé').click(); await dormir(80);
        const ids = new Set(colC.all().map((x) => x.id));
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        viderToasts(); dernier('Créer').click(); await dormir(80);
        const c = colC.all().filter((x) => !ids.has(x.id)).map(net);
        const ouverte = !!document.querySelector('.modal-root, [role=dialog]');
        creations.push({ nom, saisie, crees: c, toasts: toasts(), modaleOuverte: ouverte });
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
      }
      const b = { patientCode: 'CNT/2/26', dateHeure: aujourdhui + 'T09:30', moment: 'midi', releveePar: 'SANNI Bibata' };
      await creer('relevé complet : tension et IMC calculés', Object.assign({}, b, { temperature: 37.2, tensionSys: 12, tensionDia: 8, pouls: 80, fr: 16, spo2: 98, diurese: 1.2, poids: 62.5, taille: 168 }));
      await creer('poids sans taille : pas d\'IMC', Object.assign({}, b, { poids: 62.5 }));
      await creer('une seule valeur de tension : pas de tension', Object.assign({}, b, { tensionSys: 12 }));
      await creer('IMC arrondi au dixième', Object.assign({}, b, { poids: 71, taille: 173 }));
      await creer('patient non choisi : la première entrée de la liste est présélectionnée', { dateHeure: aujourdhui + 'T09:30', moment: 'soir', releveePar: 'X' });
      await creer('relevé par vide : formulaire refusé', { patientCode: 'CNT/2/26', dateHeure: aujourdhui + 'T09:30', moment: 'soir' });
      res.creations = creations;
      // Consultation (tiroir) puis modification
      const q = root.querySelector('input[placeholder^="Rechercher"]');
      async function ligne(ref) { q.value = ref; q.dispatchEvent(new Event('input')); await dormir(380); res.debug = lignes(root).slice(0, 3); res.debugQ = q.value; return root.querySelector('tbody tr'); }
      const tr = await ligne(aujourdhui + 'T02:00'); if (!tr) return { debug: res.debug, debugQ: res.debugQ, html: root.innerText.slice(0, 600) };
      bouton(tr, 'Consulter').click(); await dormir(80);
      res.detail = norm(document.body.innerText).slice(-900);
      const tr2 = await ligne(aujourdhui + 'T02:00');
      const avant = net(colC.all().find((x) => x.reference === 'CST-00002'));
      bouton(tr2, 'Modifier').click(); await dormir(80);
      const prerempli = {};
      [...document.querySelectorAll('[id^=f_]')].forEach((e) => { prerempli[e.id.slice(2)] = e.type === 'checkbox' ? e.checked : (e.value === undefined ? null : e.value); });
      poser('poids', 80); poser('tensionSys', 15); poser('tensionDia', 9);
      viderToasts(); dernier('Enregistrer').click(); await dormir(80);
      const apres = net(colC.all().find((x) => x.reference === 'CST-00002'));
      res.modification = { nom: 'modifier poids et tension : le calculé suit-il ?', prerempli, avant, patch: diff(avant, apres), toasts: toasts() };
      root.remove(); rC(); rP();
      return propre(res);
    }));
    ecrire('packages/domaine/test/vecteurs/pat_constantes.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-m1.js — sorties de m1-constantes de la MAQUETTE. Ne pas éditer.' }, out));
  }

  if (veut('reference')) {
    const out = await section('référence et contre-référence', (page) => page.evaluate(async () => {
      const { S, C, propre, dormir, net, toasts, viderToasts, poser, monter, norm, kpis, lignes, entetes, onglets, ongletPar, bouton, dernier, diff, echanger } = window.__O;
      const colP = S.collection('patients'), colR = S.collection('fichesReference'), colK = S.collection('contreReferences');
      const pats = [1, 2, 3].map((n) => ({ id: 'K' + n, statut: 'actif', code: 'CNT/' + n + '/26', nom: 'Nom' + n, prenom: 'Pre' + n, sexe: n === 2 ? 'M' : 'F', dateNaissance: '1990-01-01', telephone: '9', quartier: 'Perma', dateCreation: '2026-01-01' }));
      const rP = echanger(colP, pats);
      const ref = (n, o) => Object.assign({ id: 'R' + n, statut: 'actif', numero: 'REF-' + String(n).padStart(5, '0'), sens: 'sortante', urgent: false, patientId: 'K1', patientCode: 'CNT/1/26', patient: 'Nom1 Pre1', formationSanitaire: 'CLINIQUE', centreDestination: 'CNHU Cotonou', dateReference: '2026-08-0' + n, agentReferent: 'Agent ' + n, symptomes: 'Symptômes ' + n, motifs: ['Absence de moyens de diagnostic'] }, o || {});
      const refs = [ref(1), ref(2, { urgent: true, patientId: 'K2', patientCode: 'CNT/2/26', patient: 'Nom2 Pre2', centreDestination: 'Hôpital de zone' }), ref(3, { sens: 'entrante', centreDestination: 'Centre de santé de Perma' }), ref(4), ref(5, { statut: 'archive' })];
      const crf = (n, num, o) => Object.assign({ id: 'C' + n, statut: 'actif', reference: 'CRF-' + String(n).padStart(5, '0'), numeroReference: num, patientId: 'K1', patient: 'Nom1 Pre1', patientCode: 'CNT/1/26', centreAccueil: 'CNHU', dateArrivee: '2026-08-1' + n, diagnosticEntree: 'DE', diagnosticSortie: 'DS', evolution: 'Guéri(e)', concordance: true, justifiee: true, chefService: 'Dr X' }, o || {});
      const crfs = [crf(1, 'REF-00001'), crf(2, 'REF-00002', { concordance: false, justifiee: false, evolution: 'Décédé(e)', motifNonJustifiee: 'Disponible sur place' })];
      const r1 = echanger(colR, refs), r2 = echanger(colK, crfs);
      const res = { _doc: 'm1-reference et m1-contre-reference sur un jeu posé', jeuRefs: propre(refs), jeuContre: propre(crfs) };

      // --- Fiches de référence
      const root = await monter('m1-reference', 150);
      res.reference = { kpis: kpis(root), onglets: onglets(root), entetes: entetes(root), lignes: lignes(root), parOnglet: {} };
      for (const o of ['Sortantes', 'Entrantes', 'Contre-référence attendue']) { await ongletPar(root, o); res.reference.parOnglet[o] = lignes(root).map((l) => l[0]); }
      await ongletPar(root, 'Toutes');
      const creations = [];
      async function creer(nom, saisie) {
        bouton(root, 'Nouvelle fiche de référence').click(); await dormir(100);
        const ids = new Set(colR.all().map((x) => x.id));
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        viderToasts(); dernier('Créer').click(); await dormir(100);
        creations.push({ nom, saisie, crees: colR.all().filter((x) => !ids.has(x.id)).map(net), toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]') });
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
      }
      const min = { sens: 'sortante', patientCode: 'CNT/2/26', formationSanitaire: 'CLINIQUE NASSIERA TOO', symptomes: 'Détresse respiratoire', motifs: ['Absence de personnel qualifié'], centreDestination: 'CNHU Parakou', dateReference: '2026-10-30', agentReferent: 'AHOHOU Rodrigue — IDE — 97000000' };
      await creer('fiche minimale : le numéro suit le registre (archivés compris)', min);
      await creer('fiche complète entrante, urgente', Object.assign({}, min, { sens: 'entrante', urgent: true, centreAlerte: true, pouls: 110, temperature: 38.5, tension: '10/6', abordVeineux: true, heureReference: '14h30', moyen: 'Ambulance', motifs: ['Autre (à préciser)'], motifAutre: 'Hémorragie', patientCode: 'CNT/3/26' }));
      await creer('motif de référence absent : refusé', Object.assign({}, min, { motifs: [] }));
      res.reference.creations = creations;
      // détail d'une fiche avec contre-référence puis sans
      async function detail(num) {
        const q = root.querySelector('input[type=search]'); q.value = num; q.dispatchEvent(new Event('input')); await dormir(380);
        const tr = root.querySelector('tbody tr'); bouton(tr, 'Consulter').click(); await dormir(100);
        const t = norm(document.body.innerText); const i = t.indexOf('N° de référence'); document.querySelectorAll('.modal-root, [role=dialog], aside').forEach((e) => e.remove());
        q.value = ''; q.dispatchEvent(new Event('input')); await dormir(300);
        return t.slice(Math.max(0, t.lastIndexOf('REF-0', i + 40) - 40), 1400 + Math.max(0, i - 40));
      }
      res.reference.details = { avecRetour: await detail('REF-00001'), sansRetourSortante: await detail('REF-00004'), entrante: await detail('REF-00003') };
      root.remove();

      // --- Contre-références
      const root2 = await monter('m1-contre-reference', 150);
      res.contre = { kpis: kpis(root2), entetes: entetes(root2), lignes: lignes(root2) };
      const cc = [];
      bouton(root2, 'Enregistrer une contre-référence').click(); await dormir(100);
      res.contre.optionsReference = [...document.querySelectorAll('#f_numeroReference option')].map((o) => norm(o.textContent));
      document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
      async function creerCR(nom, saisie) {
        bouton(root2, 'Enregistrer une contre-référence').click(); await dormir(100);
        const ids = new Set(colK.all().map((x) => x.id));
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        viderToasts(); dernier('Créer').click(); await dormir(100);
        cc.push({ nom, saisie, crees: colK.all().filter((x) => !ids.has(x.id)).map(net), toasts: toasts() });
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
      }
      const mc = { numeroReference: 'REF-00004', centreAccueil: 'CNHU Parakou', dateArrivee: '2026-10-30', diagnosticEntree: 'Détresse', diagnosticSortie: 'Pneumopathie', evolution: 'Guéri(e)', chefService: 'Dr Y' };
      await creerCR('retour d\'une fiche sortante : le patient vient de la fiche', mc);
      await creerCR('discordance, non justifiée, décès', Object.assign({}, mc, { numeroReference: 'REF-00002', concordance: false, justifiee: false, motifNonJustifiee: 'Plateau technique disponible', evolution: 'Décédé(e)' }));
      await creerCR('chef de service absent : refusé', Object.assign({}, mc, { chefService: '' }));
      res.contre.creations = cc; res.contre.kpisApres = kpis(root2);
      root2.remove(); r1(); r2(); rP();
      return propre(res);
    }));
    ecrire('packages/domaine/test/vecteurs/pat_reference.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-m1.js — sorties de m1-reference et m1-contre-reference de la MAQUETTE. Ne pas éditer.' }, out));
  }

  if (veut('pieces')) {
    const out = await section('certificats & attestations', (page) => page.evaluate(async () => {
      const { S, C, propre, dormir, net, toasts, viderToasts, differe, poser, monter, norm, kpis, lignes, entetes, onglets, ongletPar, bouton, dernier, diff, echanger } = window.__O;
      const D = SIGH.data, PR = SIGH.parcours;
      const colP = S.collection('patients'), colPc = S.collection('pieces'), colF = S.collection('factures');
      const pats = [
        { id: 'K1', statut: 'actif', code: 'CNT/1/26', nom: 'Nom1', prenom: 'Pre1', sexe: 'F', dateNaissance: '1990-01-01', telephone: '9', quartier: 'Perma', dateCreation: '2026-01-01' },
        { id: 'K2', statut: 'actif', code: 'CNT/2/26', nom: 'Nom2', prenom: 'Pre2', sexe: 'M', dateNaissance: '1985-01-01', telephone: '9', quartier: 'Perma', dateCreation: '2026-01-01', assureur: 'SOS', assureurNom: 'SOS ASSURANCE', tauxPriseEnCharge: 80, carteExpiration: '2027-12-31' },
        { id: 'K3', statut: 'actif', code: 'CNT/3/26', nom: 'Nom3', prenom: 'Pre3', sexe: 'F', dateNaissance: '1985-01-01', telephone: '9', quartier: 'Perma', dateCreation: '2026-01-01', assureur: 'NSIA', assureurNom: 'NSIA ASSURANCE', tauxPriseEnCharge: 80, carteExpiration: '2027-12-31' },
        { id: 'K4', statut: 'actif', code: 'CNT/4/26', nom: 'Nom4', prenom: 'Pre4', sexe: 'M', dateNaissance: '1985-01-01', telephone: '9', quartier: 'Perma', dateCreation: '2026-01-01', externe: true },
      ];
      const rP = echanger(colP, pats);
      const rF = echanger(colF, [
        { id: 'F1', statut: 'actif', numero: 'FC-2026-00001', lignes: [{ id: 'L001', statutPaiement: 'paye', montant: 5000 }], reliquat: 0, partPatient: 5000 },
        { id: 'F2', statut: 'actif', numero: 'FC-2026-00002', lignes: [{ id: 'L001', statutPaiement: 'du', montant: 7000 }], reliquat: 7000, partPatient: 7000 },
      ]);
      const types = S.collection('typesPiece').active().map((t) => ({ id: t.id, sigle: t.sigle, libelle: t.libelle, direction: t.direction, tarifCode: t.tarifCode, collision: t.collision || null, examens: t.examens || null }));
      const pc = (n, o) => Object.assign({ id: 'P' + n, statut: 'actif', numero: n, annee: 2026, reference: 'CMVC ' + String(n).padStart(3, '0') + '/' + String(n).padStart(3, '0') + '/CNT/DG/DE/2026', sigle: 'CMVC', libelle: 'Certificat médical de visite et de contre-visite', direction: 'DG/DE', typeId: 'TPC12', patientId: 'K1', patient: 'Nom1 Pre1', patientCode: 'CNT/1/26', medecin: 'Dr X', dateDelivrance: '2026-08-0' + n, montant: 5000 }, o || {});
      const posees = [
        pc(1, { factureId: 'F1', factureNumero: 'FC-2026-00001' }),
        pc(2, { factureId: 'F2', factureNumero: 'FC-2026-00002', montant: 7000, patientId: 'K4', patientCode: 'CNT/4/26', patient: 'Nom4 Pre4' }),
        pc(3, { montant: 8000 }), pc(4, { montant: null }), pc(5, { montant: 5000, factureId: 'F-INCONNUE' }),
        pc(6, { annee: 2025, reference: 'CMVC 001/001/CNT/DG/DE/2025' }), pc(7, { statut: 'archive' }),
      ];
      const rPc = echanger(colPc, posees);
      const res = { _doc: 'm1-pieces sur un jeu posé', jour: C.iso(C.aujourdhui()), types: propre(types), jeu: propre(posees), tarifs: {} };
      types.forEach((t) => { if (t.tarifCode) { const e = D.tarif(t.tarifCode); res.tarifs[t.tarifCode] = e ? { prixNonAssure: e.prixNonAssure, assurable: e.assurable, libelle: e.libelle } : null; } });
      const root = await monter('m1-pieces', 200);
      res.registre = { kpis: kpis(root), notes: norm(root.innerText).slice(0, 900), onglets: onglets(root), entetes: entetes(root), lignes: lignes(root), parOnglet: {} };
      for (const o of ['Patients de la clinique', 'Patients externes', 'Archives']) { await ongletPar(root, o); res.registre.parOnglet[o] = lignes(root).map((l) => l[0]); }
      await ongletPar(root, 'Toutes');
      // statuts de règlement lus par le moteur
      res.statuts = posees.map((p) => { const st = PR.statutPiece(p); return { numero: p.numero, statut: p.statut, code: st.code, label: st.label, ton: st.ton, detail: st.detail }; });
      // Délivrance
      const creations = [];
      async function delivrer(nom, saisie) {
        bouton(root, 'Délivrer une pièce').click(); await dormir(120);
        const ids = new Set(colPc.all().map((x) => x.id)), idsP = new Set(colP.all().map((x) => x.id)), idsF = new Set(colF.all().map((x) => x.id));
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        viderToasts(); dernier('Créer').click(); await dormir(120);
        creations.push({ nom, saisie, pieces: colPc.all().filter((x) => !ids.has(x.id)).map(net), patients: colP.all().filter((x) => !idsP.has(x.id)).map(net),
          factures: colF.all().filter((x) => !idsF.has(x.id)).map(net), taches: S.collection('taches').all().slice(0, 1).map(net), toasts: toasts(), modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]') });
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
      }
      const med = S.collection('personnel').active().find((a) => a.fonction === 'medecin').nomComplet;
      res.medecin = med;
      const idType = (sigle, libelleDebut) => types.find((t) => t.sigle === sigle && (!libelleDebut || t.libelle.startsWith(libelleDebut))).id;
      const base = { dateDelivrance: '2026-10-30', medecin: med };
      await delivrer('CMVC pour un patient non assuré : n° 7 de la série (le registre en compte 6 en 2026, dont un archivé)', Object.assign({}, base, { typeId: idType('CMVC'), patientCode: 'CNT/1/26', contenu: 'Visite.', remisA: 'L\'intéressée' }));
      await delivrer('CMVC pour un assuré SOS : couvert au taux du dossier', Object.assign({}, base, { typeId: idType('CMVC'), patientCode: 'CNT/2/26' }));
      await delivrer('CMVC pour un assuré NSIA : intégralement au patient', Object.assign({}, base, { typeId: idType('CMVC'), patientCode: 'CNT/3/26' }));
      await delivrer('pièce non tarifée (CMNI) : aucune pièce de caisse', Object.assign({}, base, { typeId: idType('CMNI'), patientCode: 'CNT/1/26' }));
      await delivrer('sigle différent : sa propre série', Object.assign({}, base, { typeId: idType('ATG'), patientCode: 'CNT/1/26' }));
      await delivrer('patient adressé de l\'extérieur : le dossier naît', Object.assign({}, base, { typeId: idType('CMNI'), patientCode: '', extNom: 'Gado', extPrenom: 'Issa', extSexe: 'M', extAge: 33, extTelephone: '96000000', extResidence: 'Natitingou' }));
      await delivrer('ni dossier ni identité : refus nommé', Object.assign({}, base, { typeId: idType('CMNI'), patientCode: '' }));
      res.delivrances = creations;
      res.kpisApres = kpis(root);
      // consulter une pièce
      const q = root.querySelector('input[type=search]'); q.value = 'CMVC 001/001/CNT/DG/DE/2026'; q.dispatchEvent(new Event('input')); await dormir(400);
      const tr = root.querySelector('tbody tr'); bouton(tr, 'Consulter').click(); await dormir(120);
      res.detail = norm(document.body.innerText).slice(-1100);
      document.querySelectorAll('.modal-root, [role=dialog], aside').forEach((e) => e.remove());
      root.remove(); rPc(); rF(); rP();
      return propre(res);
    }));
    ecrire('packages/domaine/test/vecteurs/pat_pieces.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-m1.js — sorties de m1-pieces (PR.facturerPiece, PR.statutPiece) de la MAQUETTE. Ne pas éditer.' }, out));
  }

  if (veut('externe')) {
    const out = await section('patient externe', (page) => page.evaluate(async () => {
      const { S, C, propre, dormir, net, toasts, viderToasts, poser, monter, norm, kpis, lignes, entetes, onglets, ongletPar, bouton, dernier, diff, echanger } = window.__O;
      const D = SIGH.data, L = SIGH.labo;
      const colP = S.collection('patients'), colD = S.collection('demandesAnalyses'), colI = S.collection('demandesImagerie'), colF = S.collection('factures'), colT = S.collection('taches');
      const res = { _doc: 'm1-externe : jeu posé, puis créations', jour: C.iso(C.aujourdhui()) };
      res.analysesCatalogue = S.collection('analyses').active().slice(0, 4).map((a) => ({ code: a.code, designation: a.designation, categorie: a.categorie, echantillon: a.echantillon, delai: a.delai, prix: a.prix }));
      res.examensImagerie = S.collection('examensImagerie').active().slice(0, 3).map((x) => ({ code: x.code, label: x.label, tarifCode: x.tarifCode || null }));
      res.servicesDemandeurs = L.SERVICES_DEMANDEURS.map((x) => x.label); res.niveauxUrgence = L.NIVEAUX_URGENCE.map((x) => ({ id: x.id, label: x.label }));
      res.assureurs = S.collection('assureurs').active().slice(0, 3).map((a) => a.nom);

      // --- Un jeu posé : le registre se lit
      const pats = [
        { id: 'E1', statut: 'actif', code: 'CNT/901/26', nom: 'EXT1', prenom: 'Un', sexe: 'M', externe: true, dateCreation: '2026-08-01' },
        { id: 'E2', statut: 'actif', code: 'CNT/902/26', nom: 'EXT2', prenom: 'Deux', sexe: 'F', externe: true, dateCreation: '2026-08-01' },
        { id: 'N1', statut: 'actif', code: 'CNT/1/26', nom: 'NOR', prenom: 'Mal', sexe: 'F', dateNaissance: '1990-01-01', dateCreation: '2026-08-01' },
      ];
      const dem = (n, o) => Object.assign({ id: 'D' + n, statut: 'actif', reference: 'LAB-' + String(n).padStart(5, '0'), codeAnalyse: String(n).padStart(5, '0') + '-2026', patientId: 'E1', patientCode: 'CNT/901/26', patient: 'EXT1 Un', analyseCode: 'L24', analyse: 'NFS', categorie: 'Hématologie', prix: 4000, dateHeure: '2026-08-0' + n + 'T10:00:00.000Z', prescripteur: 'Dr Ext', origine: 'accueil-externe', origineDemande: 'externe', etatAnalyse: 'en_attente', bloqueParPaiement: true, serviceDemandeur: null, secteurDemandeur: null, factureId: 'F1' }, o || {});
      const posees = [
        dem(1), dem(2, { bloqueParPaiement: false, etatAnalyse: 'attente_prelevement' }),
        dem(3, { bloqueParPaiement: false, etatAnalyse: 'preleve' }), dem(4, { bloqueParPaiement: false, etatAnalyse: 'en_cours', recuLaboLe: '2026-08-04T12:00:00.000Z' }),
        dem(5, { bloqueParPaiement: false, etatAnalyse: 'valide', recuLaboLe: '2026-08-05T12:00:00.000Z', patientId: 'E2', patientCode: 'CNT/902/26', patient: 'EXT2 Deux', serviceDemandeur: 'Maternité' }),
        dem(6, { bloqueParPaiement: false, etatAnalyse: 'valide_technique', recuLaboLe: '2026-08-06T12:00:00.000Z', secteurDemandeur: 'Hospitalisation et soins' }),
        dem(7, { origineDemande: 'service', origine: 'service', patientId: 'N1', patientCode: 'CNT/1/26', patient: 'NOR Mal' }),
      ];
      const im = (n, o) => Object.assign({ id: 'I' + n, statut: 'actif', reference: 'IME-' + String(n).padStart(5, '0'), dateHeure: '2026-08-0' + n + 'T10:00:00.000Z', patientId: 'E1', patientCode: 'CNT/901/26', patient: 'EXT1 Un', examenCode: 'IMG-ECHO-ABD', examen: 'Échographie abdominale', prescripteur: 'Dr Ext', origine: 'externe', statut_: 1, bloqueParPaiement: true }, o || {});
      const imgs = [im(1, { statut: 'demandee' }), im(2, { statut: 'payee', bloqueParPaiement: false, serviceDemandeur: 'Maternité' }), im(3, { statut: 'executee', bloqueParPaiement: false }), im(4, { statut: 'validee', bloqueParPaiement: false, secteurDemandeur: 'Hospitalisation et soins' }), im(5, { statut: 'demandee', origine: 'consultation', patientId: 'N1', patientCode: 'CNT/1/26', patient: 'NOR Mal' })];
      const rP = echanger(colP, pats), rD = echanger(colD, posees), rI = echanger(colI, imgs);
      let root = await monter('m1-externe', 250);
      res.registre = { kpis: kpis(root), onglets: onglets(root), entetes: entetes(root), lignes: lignes(root), boutonsLigne: [...root.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title || norm(b.textContent))), parOnglet: {} };
      for (const o of ['Demandes — maternité', 'Demandes — hospitalisation', 'Demandes — imagerie', 'Résultats']) {
        await ongletPar(root, o);
        res.registre.parOnglet[o] = { lignes: lignes(root).map((l) => [l[0], l[2], l[6]]), entetes: entetes(root), boutons: [...root.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title || norm(b.textContent))) };
      }
      root.remove(); rP(); rD(); rI();

      // --- Créations
      root = await monter('m1-externe', 250);
      const analyses = res.analysesCatalogue, exs = res.examensImagerie;
      const creations = [];
      async function creer(nom, saisie) {
        bouton(root, 'Nouvelle demande externe').click(); await dormir(150);
        const ids = { p: new Set(colP.all().map((x) => x.id)), d: new Set(colD.all().map((x) => x.id)), i: new Set(colI.all().map((x) => x.id)), f: new Set(colF.all().map((x) => x.id)), t: new Set(colT.all().map((x) => x.id)) };
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        viderToasts(); dernier('Enregistrer et envoyer à la caisse').click(); await dormir(200);
        const neuf = (col, s) => col.all().filter((x) => !s.has(x.id)).map(net);
        const modale = norm((document.querySelector('.modal-root, [role=dialog]') || { innerText: '' }).innerText);
        creations.push({ nom, saisie, patients: neuf(colP, ids.p), demandes: neuf(colD, ids.d), imagerie: neuf(colI, ids.i), factures: neuf(colF, ids.f), taches: neuf(colT, ids.t), toasts: toasts(), modale: modale.slice(0, 420) });
        document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
      }
      const id = { nom: 'Gado', prenom: 'Issa', sexe: 'M', naissanceConnue: 'age', age: '41', telephone: '97000000', residence: 'Boriyoure', prescripteur: 'Dr HOUNSOU Rémi', urgence: 'aucune', nature: 'analyses' };
      await creer('deux analyses, patient sans assurance', Object.assign({}, id, { analyses: [analyses[0].code, analyses[1].code] }));
      await creer('assuré à 80 % : la part assureur suit le taux', Object.assign({}, id, { nom: 'Assure', analyses: [analyses[2].code], assureur: res.assureurs[0], taux: 80, indication: 'Fièvre', serviceDemandeur: res.servicesDemandeurs[1] }));
      await creer('bilan urgent', Object.assign({}, id, { nom: 'Urgent', analyses: [analyses[0].code], urgence: 'bilan' }));
      await creer('imagerie : une échographie', Object.assign({}, id, { nom: 'Echo', nature: 'imagerie', examens: [exs[0].code], serviceDemandeur: res.servicesDemandeurs[0] }));
      await creer('aucun examen coché : refus nommé', Object.assign({}, id, { nom: 'Rien', analyses: [] }));
      await creer('identité manquante : le formulaire refuse', { nature: 'analyses', analyses: [analyses[0].code], prescripteur: 'Dr X', urgence: 'aucune' });
      res.creations = creations;
      res.kpisApres = kpis(root); res.ongletsApres = onglets(root);
      root.remove();
      return propre(res);
    }));
    ecrire('packages/domaine/test/vecteurs/pat_externe.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-m1.js — sorties de m1-externe (PR.ouvrirDemandeExterne) de la MAQUETTE. Ne pas éditer.' }, out));
  }

  if (veut('documents')) {
    const out = await section('documents numérisés', (page) => page.evaluate(async () => {
      const { S, C, propre, dormir, net, toasts, viderToasts, poser, monter, norm, kpis, lignes, entetes, bouton, dernier, diff, echanger } = window.__O;
      const colP = S.collection('patients'), colDoc = S.collection('documentsPatient');
      const pats = [1, 2].map((n) => ({ id: 'K' + n, statut: 'actif', code: 'CNT/' + n + '/26', nom: 'Nom' + n, prenom: 'Pre' + n, sexe: 'F', dateNaissance: '1990-01-01', dateCreation: '2026-01-01' }));
      const rP = echanger(colP, pats);
      const doc = (n, o) => Object.assign({ id: 'DOC' + n, statut: 'actif', reference: 'GED-' + String(n).padStart(5, '0'), patientId: 'K1', code: 'CNT/1/26', patient: 'Nom1 Pre1', type: 'Ordonnance', date: '2026-08-0' + n, fichier: null, format: 'PDF', taille: 2048 * n, donnees: null, etat: 'valide', depose: 'OROU YO Edmond' }, o || {});
      const posees = [doc(1), doc(2, { etat: 'en_attente', format: 'JPEG', type: 'Facture', taille: 3 * 1024 * 1024 }), doc(3, { patientId: 'K2', code: 'CNT/2/26', patient: 'Nom2 Pre2', donnees: 'data:image/png;base64,AAAA', fichier: 'scan.png', format: 'PNG', taille: 500 }), doc(4, { statut: 'archive' }), doc(5, { taille: null })];
      const rD = echanger(colDoc, posees);
      const root = await monter('m1-documents', 250);
      const res = { _doc: 'm1-documents sur un jeu posé', jeu: propre(posees), kpis: kpis(root), entetes: entetes(root), lignes: lignes(root) };
      res.boutonsLigne = [...root.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title || norm(b.textContent)));
      const selects = [...root.querySelectorAll('select')];
      res.filtres = [];
      for (const s of selects) {
        for (const o of [...s.options].slice(1)) {
          s.value = o.value; s.dispatchEvent(new Event('change')); await dormir(40);
          if (['Fichier déposé', 'Référencé seulement', 'Facture'].includes(norm(o.textContent))) res.filtres.push({ filtre: s.getAttribute('aria-label') || s.name, valeur: norm(o.textContent), refs: lignes(root).map((l) => l[0]) });
        }
        s.value = ''; s.dispatchEvent(new Event('change')); await dormir(30);
      }
      // Modifier puis retirer (motif obligatoire)
      const q = root.querySelector('input[type=search]'); q.value = 'GED-00001'; q.dispatchEvent(new Event('input')); await dormir(400);
      const tr = root.querySelector('tbody tr');
      const avant = net(colDoc.all().find((x) => x.reference === 'GED-00001'));
      bouton(tr, 'Modifier').click(); await dormir(100);
      const prerempli = {}; [...document.querySelectorAll('[id^=f_]')].forEach((e) => { prerempli[e.id.slice(2)] = e.value; });
      poser('type', 'Consentement éclairé'); poser('etat', 'en_attente'); poser('depose', 'GARBA Yahouza');
      viderToasts(); dernier('Enregistrer').click(); await dormir(100);
      res.modification = { prerempli, patch: diff(avant, net(colDoc.all().find((x) => x.reference === 'GED-00001'))), toasts: toasts() };
      const q2 = root.querySelector('input[type=search]'); q2.value = 'GED-00001'; q2.dispatchEvent(new Event('input')); await dormir(400); const tr2 = root.querySelector('tbody tr');
      bouton(tr2, 'Retirer du dossier').click(); await dormir(100);
      res.confirmation = norm((document.querySelector('.modal-root, [role=dialog]') || { innerText: '' }).innerText).slice(0, 400);
      res.champsConfirmation = [...document.querySelectorAll('.modal-root textarea, [role=dialog] textarea, .modal-root input, [role=dialog] input')].map((e) => e.placeholder || e.id || e.type);
      const motif = document.querySelector('.modal-root textarea, [role=dialog] textarea, .modal-root input[type=text], [role=dialog] input[type=text]');
      if (motif) { motif.value = 'Scan illisible'; motif.dispatchEvent(new Event('input')); }
      viderToasts(); (dernier('Retirer') || dernier('Confirmer')).click(); await dormir(120);
      const arch = colDoc.all().find((x) => x.reference === 'GED-00001');
      res.retrait = { statut: arch.statut, motif: arch._motifArchivage || null, toasts: toasts() };
      root.remove(); rD(); rP();
      return propre(res);
    }));
    ecrire('packages/domaine/test/vecteurs/pat_documents.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-m1.js — sorties de m1-documents de la MAQUETTE. Ne pas éditer.' }, out));
  }

  if (veut('profil')) {
    const out = await section('fiche patient', (page) => page.evaluate(async () => {
      const { S, C, propre, dormir, net, toasts, viderToasts, poser, monter, norm, kpis, lignes, entetes, onglets, ongletPar, bouton, dernier, diff, echanger } = window.__O;
      const res = { _doc: 'm1-patient-profil : jeu posé, rubrique par rubrique', jour: C.iso(C.aujourdhui()) };
      const mem = [];
      const poser_ = (nom, fiches) => { mem.push(echanger(S.collection(nom), fiches)); };
      const base = { statut: 'actif', patientId: 'P1', patientCode: 'CNT/1/26' };
      const f = (o) => Object.assign({}, base, o);
      const pats = [
        { id: 'P1', statut: 'actif', code: 'CNT/1/26', nom: 'TCHANE', prenom: 'Bertine', sexe: 'F', dateNaissance: '1985-03-10', telephone: '97000001', quartier: 'Perma', adresse: 'Rue 12', personneAPrevenir: 'Époux 96000000',
          groupeSanguin: 'O+', antecedents: ['Asthme', 'Épilepsie'], antecedentsAutres: 'Appendicectomie', allergies: ['Sulfamides'], traitementEnCours: 'Salbutamol', assureur: 'NSIA', assureurNom: 'NSIA ASSURANCE', numeroPolice: 'P-9', tauxPriseEnCharge: 80, carteExpiration: '2027-12-31', dateCreation: '2026-01-05' },
        { id: 'P2', statut: 'actif', code: 'CNT/2/26', nom: 'BAKO', prenom: 'Issa', sexe: 'M', dateNaissance: '', age: 40, ageReferenceLe: '2020-06-01', telephone: '1', quartier: 'Perma', dateCreation: '2026-01-06' },
      ];
      poser_('patients', pats);
      poser_('consultations', [f({ id: 'C1', type: 'Consultation', date: '2026-08-10', motif: 'Toux', diagnostic: 'Asthme', medecin: 'Dr A' }), f({ id: 'C2', type: 'Domicile', date: '2026-08-11', motif: 'Fièvre', diagnostic: 'Palu', medecin: 'Dr B', tarif: 15000 })]);
      poser_('soins', [f({ id: 'S1', date: '2026-08-12', heure: '09:30', acte: 'Pansement', produit: 'Compresses', soignant: 'IDE X', etat: 'realise' })]);
      poser_('admissions', [f({ id: 'A1', statut: 'en_cours', dateEntree: '2026-08-14', chambre: '3', lit: 'B', diagnosticEntree: 'Pneumonie' }), f({ id: 'A2', statut: 'sortie', dateEntree: '2026-05-01', dateSortie: '2026-05-04', chambre: '1', lit: 'A', diagnosticEntree: 'Paludisme grave', etatSortie: 'Guéri' })]);
      poser_('releves', [{ id: 'R1', statut: 'actif', admissionId: 'A1', date: '2026-08-15', heure: '08:00', temperature: 38.4, tension: '12/8', fc: 90, saisiPar: 'IDE X' }]);
      poser_('observations', [f({ id: 'O1', dateEntree: '2026-07-01T10:00:00', motif: 'Malaise', uniteLabel: 'Salle d’observation — urgences', constantes: [{}, {}], orientationLabel: 'Retour à domicile' })]);
      poser_('suiviMaternite', [f({ id: 'M1', dpa: '2026-12-01', termeSA: 30, observations: 'RAS', sageFemme: 'SF Y' })]);
      poser_('accouchements', [f({ id: 'AC1', dateHeure: '2026-02-01T08:00:00', type: 'Voie basse', issue: 'Vivant', sageFemme: 'SF Y' })]);
      poser_('naissances', [{ id: 'N1', statut: 'actif', mereId: 'P1', dateHeure: '2026-02-01T08:00:00', reference: 'NAI-1', sexe: 'F', poids: 3.2, apgar5: 9 }]);
      poser_('deces', []);
      poser_('demandesAnalyses', [f({ id: 'L1', dateHeure: '2026-08-10T10:00:00', analyse: 'NFS', prescripteur: 'Dr A', etatAnalyse: 'valide', resultat: 'GB 6', conclusion: 'Normal' }), f({ id: 'L2', dateHeure: '2026-08-11T10:00:00', analyse: 'Glycémie', prescripteur: 'Dr A', etatAnalyse: 'valide', resultat: '1.4', conclusion: 'Élevé' }), f({ id: 'L3', dateHeure: '2026-08-12T10:00:00', analyse: 'CRP', prescripteur: 'Dr A', etatAnalyse: 'en_attente' })]);
      poser_('demandesImagerie', [f({ id: 'I1', dateHeure: '2026-08-13T10:00:00', examen: 'Échographie pelvienne', examenCode: 'IMG-ECHO-PEL', prescripteur: 'Dr A', statut: 'validee', modalite: 'echographie' }), f({ id: 'I2', dateHeure: '2026-08-14T10:00:00', examen: 'Radio thorax', examenCode: 'IMG-RX-THO', prescripteur: 'Dr A', statut: 'demandee' })]);
      poser_('resultatsImagerie', [f({ id: 'X1', demandeImagerieId: 'I1', date: '2026-08-13', examen: 'Échographie pelvienne', examenCode: 'IMG-ECHO-PEL', statut: 'rendu', realisateur: 'ECHO', conclusion: 'Normale' })]);
      poser_('ordonnances', [f({ id: 'OR1', numero: 'ORD-2026-00001', date: '2026-08-10', medecin: 'Dr A', diagnostic: 'Asthme', medicaments: [{}, {}], analyses: [{}], actes: [], montant: 12500, statutDispensation: 'servie' })]);
      poser_('factures', [f({ id: 'F1', numero: 'FA-1-A', date: '2026-08-10', type: 'Consultation', volet: 'couvert', montantTTC: 10000, partAssurance: 8000, partPatient: 2000, statutPaiement: 'soldee', reliquat: 0 }), f({ id: 'F2', numero: 'FA-1-B', date: '2026-08-10', type: 'Consultation', volet: 'non_couvert', montantTTC: 5000, partPatient: 5000, statutPaiement: 'impayee', reliquat: 5000 }), f({ id: 'F3', numero: 'FA-2', date: '2026-08-11', type: 'Pharmacie', montantTTC: 3000, statutPaiement: 'partielle', reliquat: 1000 })]);
      poser_('dossiersConsultation', [f({ id: 'DS1', reference: 'DOS-1', dateArrivee: '2026-08-10', heureArrivee: '09h00', ouvertLe: '2026-08-10T09:05:00', soignant: 'Dr A', motifVenue: 'Toux', typeVenue: 'premiere', histoire: 'Depuis 3 jours', traitementEnCours: 'Salbutamol',
        ant_medicaux: 'Asthme', ant_chirurgicaux: 'Appendicectomie', ant_gyneco_obstetricaux: 'G2P2', allergies: 'Sulfamides', statutVaccinal: 'À jour', constantesAccueil: { date: '2026-08-10T08:50:00', temperature: 37.2, tension: '12/8', poids: 62, pouls: 80 },
        examensPhysiques: { cardio_vasculaire: { inspection: 'RAS', palpation: 'RAS', percussion: 'RAS', auscultation: 'RAS' }, pleuro_pulmonaire: { inspection: 'RAS', auscultation: 'Sibilants bilatéraux' } } })]);
      poser_('visitesPatients', []); poser_('sortiesAvisMedical', []);

      const root = await monter('m1-patient-profil', 300);
      const lire = () => norm(root.innerText);
      res.entete = { boutons: [...root.querySelectorAll('button')].map((b) => norm(b.textContent)).filter(Boolean).slice(0, 12), texte: lire().slice(0, 1700) };
      res.menu = [...root.querySelectorAll('[role=tab]')].map((b) => norm(b.textContent));
      res.rubriques = {};
      for (const id of ['admin', 'medical', 'antecedents', 'soins', 'hospi', 'maternite', 'laboratoire', 'imagerie', 'ordonnances', 'domicile', 'financier', 'assurance', 'audit']) {
        const b = root.querySelector('[data-rubrique=' + id + ']'); b.click(); await dormir(120);
        const carte = [...root.querySelectorAll('.card')].find((c) => (c.querySelector('.card-title') || {}).textContent === norm(b.firstChild.textContent));
        res.rubriques[id] = { libelle: norm(b.firstChild.textContent), texte: carte ? norm(carte.innerText) : null };
      }
      // La carte « Dossier de consultation » du panneau gauche
      const dossier = [...root.querySelectorAll('.card')].find((c) => /Dossier de consultation/.test((c.querySelector('.card-title') || {}).textContent || ''));
      res.dossier = dossier ? norm(dossier.innerText) : null;
      // Second patient : âge déclaré
      const sel = root.querySelector('[id^=f_], .combo, button[aria-haspopup]');
      res.selecteur = sel ? sel.outerHTML.slice(0, 160) : null;
      // Modification : assurance changée, âge déclaré
      bouton(root, 'Modifier le dossier').click(); await dormir(150);
      const avant = net(S.collection('patients').all().find((p) => p.id === 'P1'));
      const prerempli = {}; [...document.querySelectorAll('[id^=f_]')].forEach((e) => { prerempli[e.id.slice(2)] = e.value === undefined ? null : e.value; });
      poser('assureur', 'OLEA'); poser('telephone', '97111111');
      viderToasts(); dernier('Enregistrer').click(); await dormir(120);
      const apres = net(S.collection('patients').all().find((p) => p.id === 'P1'));
      res.modification = { prerempli, patch: diff(avant, apres), toasts: toasts() };
      mem.reverse().forEach((r) => r()); root.remove();
      return propre(res);
    }));
    ecrire('packages/domaine/test/vecteurs/pat_profil.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-m1.js — sorties de m1-patient-profil de la MAQUETTE. Ne pas éditer.' }, out));
  }

})().catch((e) => { console.error(e); process.exit(1); });
