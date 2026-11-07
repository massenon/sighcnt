/* =============================================================================
 * VECTEURS DES DEMANDES D'ANALYSES — m5-demandes, m5-prelevement, m5-demandes-maternite / -hospitalisation, PR.codeAnalyse
 * -----------------------------------------------------------------------------
 * Les écrans réels sont montés dans la page d'extraction, leurs formulaires remplis comme le fait l'agent, leurs boutons cliqués, et ce qui est
 * né au magasin (ou ce que l'écran affiche) est relu.
 *   node build/vecteurs-demandes.js   →   packages/domaine/test/vecteurs/dem_*.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des demandes d’analyses');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m5-laboratoire.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, PR = SIGH.parcours;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const col = S.collection('demandesAnalyses');
      const colP = S.collection('patients');
      const colT = S.collection('taches');
      const net = (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return propre(c); };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim()));
      const viderToasts = () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; };
      const fermer = () => document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove());
      const bouton = (racine, texte) => [...racine.querySelectorAll('button')].find((b) => b.textContent.trim() === texte || (texte === 'Nouveau' && b.textContent.includes(texte)) || b.getAttribute('aria-label') === texte || b.title === texte);
      const poser = (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };

      const out = {};
      const analyses = D.ANALYSES.map((a) => ({ code: a.code, designation: a.designation, categorie: a.categorie, echantillon: a.echantillon, delai: a.delai, prix: a.prix }));
      out.catalogue = analyses.slice(0, 6);

      /* ------------------------------------------------------------------ codeAnalyse */
      const sauve = col.all().splice(0);
      const cas = [];
      function code(nom, fiches, date) {
        col.all().splice(0);
        fiches.forEach((c) => col.all().push({ id: 'X' + Math.random(), statut: 'actif', codeAnalyse: c }));
        cas.push({ nom, codes: fiches, date: date === undefined ? null : date, attendu: PR.codeAnalyse(date === undefined ? null : date) });
      }
      code('registre vide', [], '2026-10-30');
      code('série 2026 : le plus grand rang + 1 (pas le nombre de fiches)', ['00003-2026', '00012-2026', '00007-2026'], '2026-10-30T10:00:00');
      code('une autre année repart à 1', ['00003-2026', '00012-2026'], '2027-01-05');
      code('les rangs de l\'année demandée seuls comptent', ['00099-2025', '00004-2026', '00050-2027'], '2026-03-01');
      code('format invalide ignoré (4 chiffres, suffixe)', ['0012-2026', '00020-2026X', 'LAB-00030', '00005-2026'], '2026-06-01');
      code('fiche sans code ignorée', [''], '2026-06-01');
      code('date invalide : l\'année en cours', ['00001-2026'], 'pas une date');
      code('rang à 5 chiffres complété de zéros', ['00099-2026'], '2026-12-31');
      code('au-delà de 99999 : six chiffres (padStart ne tronque pas)', ['99999-2026'], '2026-12-31');
      col.all().splice(0); sauve.forEach((x) => col.all().push(x));
      out.codeAnalyse = { _doc: 'PR.codeAnalyse(date) : série annuelle NNNNN-AAAA', anneeCourante: new Date().getFullYear(), cas };

      /* ------------------------------------------------------------------ creation */
      const dem = (extra) => Object.assign({ id: 'DEMT' + Math.random().toString(36).slice(2), statut: 'actif', reference: 'LAB-' + String(col.all().length + 1).padStart(5, '0'), patientId: 'P1', patient: 'TEST Patient', patientCode: 'CNT/1/26',
        analyseCode: analyses[0].code, analyse: analyses[0].designation, categorie: analyses[0].categorie, echantillon: analyses[0].echantillon, prix: analyses[0].prix, dateHeure: '2026-10-30T09:00:00.000Z', urgent: false, etatAnalyse: 'en_attente' }, extra || {});
      const patientRep = colP.active()[0];
      const medecin = S.collection('personnel').active().find((e) => e.fonction === 'medecin');
      const labo = S.collection('personnel').active().find((e) => e.fonction === 'tsl');
      const creations = [];
      async function creer(nom, saisie, avant) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['m5-demandes'].render(root);
        await dormir(40);
        bouton(root, 'Nouveau').click();
        await dormir(60);
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        const avantD = new Set(col.all().map((x) => x.id)), avantP = new Set(colP.all().map((x) => x.id));
        const entree = { nom, saisie, refsExistantes: col.all().map((x) => x.reference).sort().slice(-3), nbDemandes: col.all().length, nbPatients: colP.all().length, jour: C.iso(C.aujourdhui()),
          codesAnalyse: col.all().map((x) => x.codeAnalyse).filter(Boolean).sort().slice(-3) };
        viderToasts();
        [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === 'Créer').pop().click();
        await dormir(80);
        const nD = col.all().filter((x) => !avantD.has(x.id)).map(net);
        const nP = colP.all().filter((x) => !avantP.has(x.id)).map(net);
        const t = toasts();
        const modaleOuverte = !!document.querySelector('.modal-root, [role=dialog]');
        fermer(); root.remove();
        creations.push({ entree, demandes: nD, patients: nP, toasts: t, modaleOuverte });
      }
      const ch = (extra) => Object.assign({ analyseCode: analyses[1].code, dateHeure: '2026-10-30T09:30', prescripteur: medecin.nomComplet, laborantin: labo.nomComplet, etatAnalyse: 'en_attente' }, extra || {});
      await creer('patient du répertoire, une analyse, urgente', ch({ patientCode: patientRep.code, urgent: true }));
      await creer('même écran, deuxième création : la référence suit le registre', ch({ patientCode: patientRep.code, analyseCode: analyses[2].code }));
      await creer('patient adressé de l\'extérieur : le dossier naît (âge déclaré)', ch({ nom: 'Kassa', prenom: 'Imorou', sexe: 'M', naissanceConnue: 'age', age: '41', telephone: '97000000', residence: 'Boriyoure' }));
      await creer('patient externe, date de naissance connue', ch({ nom: 'Boni', prenom: 'Yaya', sexe: 'F', naissanceConnue: 'date', dateNaissance: '1990-05-12', analyseCode: analyses[3].code }));
      await creer('dossier choisi ET identité saisie : le dossier du répertoire l\'emporte, l\'identité est ignorée', ch({ patientCode: patientRep.code, nom: 'Ignoré', prenom: 'Aussi' }));
      await creer('ni dossier ni identité : refus nommé', ch({ }));
      await creer('nom sans prénom : refus nommé', ch({ nom: 'Seul' }));
      await creer('demande datée de 2027 : le code repart à 00001-2027', ch({ patientCode: patientRep.code, dateHeure: '2027-02-03T08:15' }));
      /* modification : « Modifier » sur une ligne, formulaire pré-rempli, « Enregistrer » */
      const modifs = [];
      async function modifier(nom, ref, saisie) {
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['m5-demandes'].render(root);
        await dormir(40);
        const q = root.querySelector('input[placeholder^="Rechercher"]');
        q.value = ref; q.dispatchEvent(new Event('input')); await dormir(120);
        const tr = [...root.querySelectorAll('tbody tr')].find((x) => x.textContent.includes(ref));
        if (!tr) throw new Error('ligne ' + ref);
        const avant = net(col.all().find((x) => x.reference === ref));
        [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === 'Modifier').click();
        await dormir(80);
        const prerempli = {};
        [...document.querySelectorAll('[id^=f_]')].forEach((e) => { prerempli[e.id.slice(2)] = e.type === 'checkbox' ? e.checked : (e.value === undefined ? null : e.value); });
        Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        viderToasts();
        [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === 'Enregistrer').pop().click();
        await dormir(80);
        const apres = net(col.all().find((x) => x.id === avant.id));
        const patch = {};
        Object.keys(Object.assign({}, avant, apres)).forEach((k) => { if (JSON.stringify(avant[k]) !== JSON.stringify(apres[k])) patch[k] = apres[k] === undefined ? null : apres[k]; });
        fermer(); root.remove();
        modifs.push({ nom, ref, saisie, prerempli, avant, patch, toasts: toasts() });
      }
      await modifier('modifier : la référence et le code d\'analyse sont CONSERVÉS, l\'analyse est reprise du catalogue', creations[0].demandes[0].reference, { analyseCode: analyses[3].code, urgent: false });
      out.creation = { _doc: 'm5-demandes : « Nouveau » → « Enregistrer », formulaire rempli comme l\'agent', patientRepertoire: { code: patientRep.code, id: patientRep.id, nom: patientRep.nom, prenom: patientRep.prenom },
        medecin: medecin.nomComplet, laborantin: labo.nomComplet, cas: creations, modifications: modifs };

      /* ------------------------------------------------------------------ prélèvement */
      const sauve2 = col.all().splice(0);
      const sauveT = colT.all().splice(0);
      const base = (id, extra) => dem(Object.assign({ id, reference: 'LAB-9' + id.slice(-4), patient: 'PAT ' + id, patientCode: 'CNT/' + id.slice(-2) + '/26' }, extra));
      const fiches = [
        base('D0001', { etatAnalyse: 'en_attente', bloqueParPaiement: true }),
        base('D0002', { etatAnalyse: 'attente_prelevement', bloqueParPaiement: false, statutPaiement: 'soldee' }),
        base('D0003', { etatAnalyse: 'attente_prelevement', statutPaiement: 'soldee', urgent: true, origineDemande: 'externe' }),
        base('D0004', { etatAnalyse: 'en_attente', statutPaiement: 'impaye' }),
        base('D0005', { etatAnalyse: 'preleve', preleveLe: '2026-10-29T08:00:00.000Z', statutPaiement: 'soldee' }),
        base('D0006', { etatAnalyse: 'en_cours', preleveLe: '2026-10-29T08:00:00.000Z', recuLaboLe: '2026-10-29T09:00:00.000Z' }),
        base('D0007', { etatAnalyse: 'valide', preleveLe: '2026-10-28T08:00:00.000Z', recuLaboLe: '2026-10-28T09:00:00.000Z' }),
        base('D0008', { etatAnalyse: 'valide', preleveLe: '2026-10-28T08:00:00.000Z' }),
        base('D0009', { etatAnalyse: 'valide' }),
        base('D0010', { etatAnalyse: 'rectifie', preleveLe: '2026-10-27T08:00:00.000Z', recuLaboLe: '2026-10-27T09:00:00.000Z' }),
        base('D0011', { etatAnalyse: 'valide_technique', preleveLe: '2026-10-27T08:00:00.000Z', recuLaboLe: '2026-10-27T09:00:00.000Z' }),
        base('D0012', { etatAnalyse: 'attente_prelevement', statutPaiement: 'soldee', statut: 'archive' }),
        base('D0013', { etatAnalyse: 'saisi', preleveLe: '2026-10-26T08:00:00.000Z', recuLaboLe: '2026-10-26T09:00:00.000Z' }),
      ];
      fiches.forEach((f) => col.all().push(f));
      const lire = (root) => [...root.querySelectorAll('tbody tr')].map((tr) => {
        const cel = [...tr.querySelectorAll('td')];
        return { ref: (tr.querySelector('.font-mono') || {}).textContent, cellules: cel.map((c) => c.innerText.replace(/\s+/g, ' ').trim()),
          actions: [...tr.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title || b.textContent.trim()).filter(Boolean) };
      });
      const onglet = async (root, debut) => { const b = [...root.querySelectorAll('[role=tab]')].find((x) => x.textContent.trim().startsWith(debut)); b.click(); await dormir(40); };
      const montage = async (id) => { const root = document.createElement('div'); document.body.appendChild(root); SIGH.screens[id].render(root); await dormir(60); return root; };

      const rootP = await montage('m5-prelevement');
      const onglets = [...rootP.querySelectorAll('[role=tab]')].map((b) => b.textContent.trim());
      const tabs = {};
      for (const [cle, debut] of [['attente', 'À prélever'], ['transmettre', 'À transmettre'], ['labo', 'Reçus au laboratoire']]) {
        await onglet(rootP, debut);
        tabs[cle] = lire(rootP);
      }
      const kpiTexte = rootP.innerText.replace(/\s+/g, ' ').slice(0, 330);
      rootP.remove();
      const prel = { _doc: 'm5-prelevement : trois onglets sur des fiches posées', fiches: propre(fiches.map((f) => ({ id: f.id, reference: f.reference, etatAnalyse: f.etatAnalyse, bloqueParPaiement: f.bloqueParPaiement, statutPaiement: f.statutPaiement, preleveLe: f.preleveLe, recuLaboLe: f.recuLaboLe, statut: f.statut, urgent: f.urgent }))),
        onglets, kpiTexte, tabs, actions: [] };

      async function agir(nom, tab, ref, iconLabel, saisie, boutonFinal) {
        viderToasts();
        const rootA = await montage('m5-prelevement');
        await onglet(rootA, tab);
        const tr = [...rootA.querySelectorAll('tbody tr')].find((x) => x.textContent.includes(ref));
        if (!tr) throw new Error('ligne ' + ref);
        const avant = propre(col.all().find((x) => x.reference === ref));
        [...tr.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === iconLabel).click();
        await dormir(60);
        if (saisie) Object.entries(saisie).forEach(([k, v]) => poser(k, v));
        const champsModale = [...document.querySelectorAll('[id^=f_]')].map((e) => e.id);
        const texteModale = (document.querySelector('.modal-root, [role=dialog]') || { innerText: '' }).innerText.replace(/\s+/g, ' ').slice(0, 700);
        if (boutonFinal) { const bf = [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === boutonFinal).pop(); bf.click(); await dormir(80); }
        const apres = propre(col.all().find((x) => x.reference === ref));
        const patch = {};
        Object.keys(Object.assign({}, avant, apres)).forEach((k) => { if (JSON.stringify(avant[k]) !== JSON.stringify(apres[k]) && !k.startsWith('_')) patch[k] = apres[k] === undefined ? null : apres[k]; });
        const rep = { nom, tab, ref, action: iconLabel, saisie: saisie || null, champsModale, texteModale, patch, toasts: toasts(), modaleOuverteApres: !!document.querySelector('.modal-root, [role=dialog]'),
          audit: S.collection('audit').all().slice(-1).map((a) => ({ action: a.action, entite: a.entite })),
          ongletsApres: [...rootA.querySelectorAll('[role=tab]')].map((b) => b.textContent.trim()) };
        fermer(); rootA.remove();
        prel.actions.push(rep);
      }
      await agir('prélever une demande réglée', 'À prélever', 'LAB-90002', 'Enregistrer le prélèvement', { preleveur: labo.nomComplet, heurePrelevement: '08:45', natureEchantillon: 'Sang veineux', observationPrelevement: 'À jeun' }, 'Prélèvement effectué');
      await agir('prélever, nature de l\'échantillon vidée : formulaire en erreur', 'À prélever', 'LAB-90003', 'Enregistrer le prélèvement', { natureEchantillon: '' }, 'Prélèvement effectué');
      await agir('demande impayée (bloqueParPaiement) : le verrou parle, rien n\'est écrit', 'À prélever', 'LAB-90001', 'Règlement requis avant prélèvement', null, null);
      await agir('demande impayée (statutPaiement impaye) : verrou', 'À prélever', 'LAB-90004', 'Règlement requis avant prélèvement', null, null);
      await agir('transmettre au laboratoire (confirmation)', 'À transmettre', 'LAB-90005', 'Transmettre au laboratoire', null, 'Transmettre');
      out.prelevement = prel;

      /* ------------------------------------------------------------------ vues par service */
      col.all().splice(0);
      const svc = [
        base('S0001', { secteurDemandeur: 'MATERNITÉ', etatAnalyse: 'en_attente' }),
        base('S0002', { secteurDemandeur: 'Maternité', etatAnalyse: 'attente_prelevement' }),
        base('S0003', { serviceDemandeur: 'maternite', etatAnalyse: 'preleve' }),
        base('S0004', { serviceDemandeur: 'Maternité', etatAnalyse: 'valide' }),
        base('S0005', { serviceDemandeur: 'Médecine', etatAnalyse: 'valide' }),
        base('S0006', { hospitalise: true, etatAnalyse: 'en_attente' }),
        base('S0007', { secteurDemandeur: 'Hospitalisation et soins', etatAnalyse: 'rectifie' }),
        base('S0008', { secteurDemandeur: 'MISE EN OBSERVATION', etatAnalyse: 'attente_prelevement' }),
        base('S0009', { secteurDemandeur: 'MATERNITÉ', hospitalise: true, etatAnalyse: 'en_cours' }),
        base('S0010', { secteurDemandeur: 'CHIRURGIE', hospitalise: false, etatAnalyse: 'en_attente' }),
        base('S0011', { secteurDemandeur: 'MATERNITÉ', etatAnalyse: 'valide', statut: 'archive' }),
      ];
      svc.forEach((f) => col.all().push(f));
      const vues = {};
      for (const id of ['m5-demandes-maternite', 'm5-demandes-hospitalisation']) {
        const r = await montage(id);
        vues[id] = { kpiTexte: r.innerText.replace(/\s+/g, ' ').slice(0, 330), lignes: lire(r).map((l) => l.ref) };
        r.remove();
      }
      out.services = { _doc: 'vues par service demandeur sur des fiches posées', fiches: propre(svc.map((f) => ({ reference: f.reference, secteurDemandeur: f.secteurDemandeur, serviceDemandeur: f.serviceDemandeur, hospitalise: f.hospitalise, etatAnalyse: f.etatAnalyse, statut: f.statut }))), vues };

      /* ------------------------------------------------------------------ file « Prélèvements à réaliser » */
      const fileCas = [];
      async function file(nom, etats, tacheExtra) {
        col.all().splice(0); colT.all().splice(0);
        etats.forEach((e, i) => col.all().push(base('F' + String(i + 1).padStart(4, '0'), { ordonnanceId: 'ORD-F', etatAnalyse: e })));
        col.all().push(base('F0099', { ordonnanceId: 'ORD-AUTRE', etatAnalyse: 'en_attente' }));
        colT.all().push(Object.assign({ id: 'TCH-F1', statut: 'en_attente', type: 'prelevement', role: 'laborantin', module: 'M5', ecran: 'm5-demandes', titre: 'Prélever et analyser', reference: 'ORD-F', ordonnanceId: 'ORD-F', patient: 'TEST F', patientCode: 'CNT/1/26', date: '2026-10-29T08:00:00.000Z', detail: 'x', montant: 1000 }, tacheExtra || {}));
        viderToasts();
        const r = await montage('m5-demandes');
        const avantEtats = col.all().map((x) => x.etatAnalyse);
        const bt = [...r.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === 'Prendre en charge');
        const verrou = [...r.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === 'Bloquée jusqu’à l’encaissement');
        const present = !!bt;
        if (bt) { bt.click(); await dormir(80); } else if (verrou) { verrou.click(); await dormir(40); }
        fileCas.push({ nom, etats, tacheStatut: (tacheExtra && tacheExtra.statut) || 'en_attente', boutonPresent: present, verrouPresent: !!verrou, avant: avantEtats, apres: col.all().map((x) => x.etatAnalyse),
          tache: propre(colT.all()[0]), toasts: toasts(), titreFile: (r.querySelector('h3, h2, .card-title, .card-head') || {}).textContent || null });
        r.remove();
      }
      await file('trois demandes en attente : toutes passent « en cours »', ['en_attente', 'en_attente', 'en_attente']);
      await file('demandes déjà débloquées par la caisse (attente_prelevement) : aucune n\'est touchée, la tâche est pourtant close', ['attente_prelevement', 'attente_prelevement']);
      await file('mélange', ['en_attente', 'preleve', 'valide']);
      await file('tâche bloquée : verrou, rien ne bouge', ['en_attente'], { statut: 'bloque' });
      out.file = { _doc: 'm5-demandes : file des prélèvements à réaliser, action « Prendre en charge »', cas: fileCas };
      col.all().splice(0); sauve2.forEach((x) => col.all().push(x)); colT.all().splice(0); sauveT.forEach((x) => colT.all().push(x));

      return out;
    });
    ecrire('packages/domaine/test/vecteurs/dem_code_analyse.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-demandes.js — ne pas éditer.' }, sortie.codeAnalyse));
    ecrire('packages/domaine/test/vecteurs/dem_creation.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-demandes.js — ne pas éditer.', catalogue: sortie.catalogue }, sortie.creation));
    ecrire('packages/domaine/test/vecteurs/dem_prelevement.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-demandes.js — ne pas éditer.' }, sortie.prelevement));
    ecrire('packages/domaine/test/vecteurs/dem_services.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-demandes.js — ne pas éditer.' }, sortie.services));
    ecrire('packages/domaine/test/vecteurs/dem_file.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-demandes.js — ne pas éditer.' }, sortie.file));
    sortie.creation.cas.forEach((c) => console.log('  ' + c.entree.nom + ' → ' + JSON.stringify(c.demandes.map((d) => d.reference + ' ' + d.codeAnalyse)) + ' toasts=' + JSON.stringify(c.toasts)));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
