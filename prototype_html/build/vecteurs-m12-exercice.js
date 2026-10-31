/* =============================================================================
 * VECTEURS DE M12 — EXERCICES & CLÔTURES et BILAN D'OUVERTURE (m12-cloture, m12-ouverture) : le MOTEUR `SIGH.exercice` appelé tel quel et les deux
 * ÉCRANS réels pilotés dans Chrome.
 * -----------------------------------------------------------------------------
 *   node build/vecteurs-m12-exercice.js      (sous flock /tmp/sigh-banc.lock ; SIGH_PORT_PHP=<port inhabituel 101xx>)
 *
 * Le JEU du poste (apps/poste/assets/donnees/jeu) est posé dans le magasin de la maquette, l'horloge est décalée au 30/10/2026 10 h.
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/exercice.json
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');
const JEU_DIR = path.join(ROOT, '..', 'apps/poste/assets/donnees/jeu');
const NOMS = ['ecritures', 'exercices', 'comptes', 'documents', 'notifications', 'centresCouts'];
const jeu = {};
NOMS.forEach((n) => { jeu[n] = JSON.parse(fs.readFileSync(path.join(JEU_DIR, n + '.json'), 'utf8')); });

(async () => {
  console.log('▶ Vecteurs de M12 — exercices, clôture, ouverture');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(__dirname, '_m12-outils.js') });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m12-comptabilite.js') });
    const sortie = await m.page.evaluate(async (jeu) => {
      const S = SIGH.store, C = SIGH.core, X = SIGH.exercice;
      const O = window.__O;
      const { propre, texte, dormir, db } = O;
      const poserJeu = () => { Object.keys(jeu).forEach((n) => { db()[n] = propre(jeu[n]); }); };
      const session = (role, nom) => { const s = S.session() || {}; S.setSession(Object.assign({}, s, { role, nom })); };
      const base = S.session();
      const rep = {};
      const COL = ['ecritures', 'exercices', 'documents', 'notifications'];
      poserJeu();

      /* ---------- 1. exercices : amorçage et liste ------------------------------------------------------------------------------- */
      {
        db().exercices = [];
        const liste = propre(X.liste());
        rep.amorcage = { exercices: propre(db().exercices), liste: liste.map((x) => x.annee) };
        poserJeu();
        rep.liste = propre(X.liste());
        rep.choisi = X.choisi();
      }

      /* ---------- 2. états et garde de lecture seule ------------------------------------------------------------------------------ */
      {
        rep.etats = {};
        [2022, 2023, 2024, 2025, 2026, 2027].forEach((a) => { rep.etats[a] = X.etat(a); });
        const essais = {};
        const colE = S.collection('ecritures');
        const tenter = (nom, op) => {
          const t0 = O.toasts.length, n0 = colE.all().length;
          let r; try { r = op(); } catch (e) { r = { erreur: String(e && e.message || e) }; }
          essais[nom] = { toast: O.toasts.slice(t0).map((t) => t.detail), nbApres: colE.all().length - n0, rendu: r === null ? null : typeof r };
        };
        tenter('inserer-2025', () => colE.insert({ numero: 'T-1', date: '2025-03-01', journal: 'OD', compte: '411100', debit: 10, credit: 0, statut: 'brouillon' }));
        tenter('inserer-2026', () => colE.insert({ numero: 'T-2', date: '2026-03-01', journal: 'OD', compte: '411100', debit: 10, credit: 0, statut: 'brouillon' }));
        tenter('inserer-2024', () => colE.insert({ numero: 'T-3', date: '2024-12-31', journal: 'OD', compte: '411100', debit: 10, credit: 0, statut: 'brouillon' }));
        tenter('inserer-sans-date', () => colE.insert({ numero: 'T-4', journal: 'OD', compte: '411100', debit: 10, credit: 0, statut: 'brouillon' }));
        const ligne = colE.active()[0];
        tenter('modifier-date-vers-2025', () => colE.update(ligne.id, { date: '2025-06-01' }));
        tenter('modifier-2026', () => colE.update(ligne.id, { libelle: 'Libellé modifié' }));
        rep.garde = essais;
        poserJeu();
      }

      rep.nbEcrituresBrut = { validees: X.ecrituresDe(2026).length, avecBrouillons: X.ecrituresDe(2026, true).length, resultat: X.resultat(X.ecrituresDe(2026)) };

      /* ---------- 3. pré-clôture -------------------------------------------------------------------------------------------------- */
      const pre = (a) => { const p = X.preCloture(a); return { annee: p.annee, controles: propre(p.controles), nbBloquants: p.bloquants.length, resultat: p.resultat, nbEcritures: p.nbEcritures }; };
      const valideTout = () => db().ecritures.forEach((e) => { if (e.statut === 'brouillon') e.statut = 'validee'; });
      rep.preCloture = {};
      rep.preCloture.jeu2026 = pre(2026);
      rep.preCloture.jeu2025 = pre(2025);
      valideTout();
      rep.preCloture.valide2026 = pre(2026);
      {
        const e0 = propre(db().ecritures);
        db().ecritures.unshift({ id: 'X-DESEQ', numero: 'ODX', date: '2026-05-05', journal: 'OD', compte: '661100', compteLibelle: 'Charge test', debit: 5000, credit: 0, statut: 'validee' });
        rep.preCloture.desequilibre2026 = pre(2026);
        db().ecritures = propre(e0);
        db().ecritures.unshift({ id: 'X-AN', numero: 'AN-2027-00001', date: '2027-01-01', journal: 'AN', compte: '571000', debit: 100, credit: 0, statut: 'validee' });
        rep.preCloture.anExistant2026 = pre(2026);
        db().ecritures = propre(e0);
        db().ecritures.unshift({ id: 'X-47A', numero: 'OD47', date: '2026-05-05', journal: 'OD', compte: '471000', debit: 7000, credit: 0, statut: 'validee' });
        db().ecritures.unshift({ id: 'X-47B', numero: 'OD47', date: '2026-05-05', journal: 'OD', compte: '571000', debit: 0, credit: 7000, statut: 'validee' });
        rep.preCloture.compte47 = pre(2026);
        db().ecritures = propre(e0);
      }

      /* ---------- 4. à-nouveaux provisoires, soldes, résultat ---------------------------------------------------------------------- */
      {
        const prov = X.provisoires(2027);
        rep.provisoires2027 = propre(prov.map((p) => ({ compte: p.compte, compteLibelle: p.compteLibelle || null, debit: p.debit, credit: p.credit, lettrable: p.lettrable, id: p.id, libelle: p.libelle })));
        rep.provisoires2026 = propre(X.provisoires(2026));
        const e26 = X.ecrituresDe(2026);
        rep.soldes2026 = propre(X.soldes(e26));
        rep.resultat2026 = X.resultat(e26);
        rep.nbEcritures2026 = { validees: e26.length, avecBrouillons: X.ecrituresDe(2026, true).length };
        rep.sha = { abc: X.sha256('abc'), vide: X.sha256(''), accents: X.sha256('Résultat net — 12 345,6 €'), long: X.sha256('a'.repeat(1000)) };
      }

      /* ---------- 5. lettrage ------------------------------------------------------------------------------------------------------ */
      {
        const e0 = propre(db().ecritures);
        const ins = (id, compte, debit, credit) => db().ecritures.unshift({ id, numero: 'LT-' + id, date: '2026-06-01', journal: 'OD', compte, compteLibelle: 'Clients', debit, credit, statut: 'validee' });
        ins('L1', '411100', 5000, 0); ins('L2', '411100', 0, 5000); ins('L3', '411100', 0, 3000); ins('L4', '421000', 100, 0); ins('L5', '411200', 0, 5000);
        const r = {};
        r.nonLettrable = propre(X.lettrer('571000', ['L1', 'L2']));
        r.uneLigne = propre(X.lettrer('411100', ['L1']));
        r.autreCompte = propre(X.lettrer('411100', ['L1', 'L5']));
        r.nonNul = propre(X.lettrer('411100', ['L1', 'L3']));
        r.inconnue = propre(X.lettrer('411100', ['L1', 'ZZZ']));
        r.valide = propre(X.lettrer('411100', ['L1', 'L2']));
        r.dejaLettree = propre(X.lettrer('411100', ['L1', 'L2']));
        r.lignesApres = propre(db().ecritures.filter((e) => ['L1', 'L2'].includes(e.id)).map((e) => ({ id: e.id, lettrage: e.lettrage })));
        r.delettrerSansMotif = propre(X.delettrer('411100', 'A', ''));
        r.delettrerCourt = propre(X.delettrer('411100', 'A', 'ab'));
        r.delettrerInconnu = propre(X.delettrer('411100', 'Z', 'Erreur de saisie'));
        r.delettrer = propre(X.delettrer('411100', 'A', 'Erreur de saisie'));
        r.lignesDelettrees = propre(db().ecritures.filter((e) => ['L1', 'L2'].includes(e.id)).map((e) => ({ id: e.id, lettrage: e.lettrage || null, motif: e.delettreMotif || null })));
        // un second lettrage : le code suit le nombre de codes DISTINCTS déjà posés
        ins('L6', '411100', 200, 0); ins('L7', '411100', 0, 200);
        ins('L8', '411100', 50, 0); ins('L9', '411100', 0, 50);
        r.premier = propre(X.lettrer('411100', ['L6', 'L7']));
        r.second = propre(X.lettrer('411100', ['L8', 'L9']));
        rep.lettrage = r;
        db().ecritures = propre(e0);
      }

      /* ---------- 6. les deux gestes de la clôture --------------------------------------------------------------------------------- */
      {
        poserJeu();
        valideTout();
        const avant = O.instantane(COL);
        const cl = {};
        session('comptable', 'KASSA Augustin');
        const t0 = O.toasts.length;
        cl.demandeSansDroitDirection = null;
        cl.inconnue = propre(X.demander(2031));
        cl.dejaClos = propre(X.demander(2025));
        // une demande refusée par les contrôles bloquants (un brouillon)
        db().ecritures.unshift({ id: 'X-BR', numero: 'BR1', date: '2026-04-04', journal: 'OD', compte: '661100', debit: 10, credit: 0, statut: 'brouillon' });
        cl.refusBrouillon = propre(X.demander(2026));
        db().ecritures = db().ecritures.filter((e) => e.id !== 'X-BR');
        const a1 = O.instantane(COL);
        cl.demande = propre(X.demander(2026));
        cl.ecartDemande = O.ecart(a1, O.instantane(COL));
        cl.secondeDemande = propre(X.demander(2026));
        cl.validerTropTot = null;
        // geste 2 : refus nommés
        cl.validerMemePersonne = propre(X.valider(2026, 'Conforme'));            // rôle comptable : refusé par le rôle
        session('direction', 'KASSA Augustin');
        cl.validerDemandeur = propre(X.valider(2026, 'Conforme'));               // même nom que le demandeur
        session('direction', 'BASSONGUI Chabi Séko');
        cl.validerSansMotif = propre(X.valider(2026, ''));
        cl.validerMotifCourt = propre(X.valider(2026, 'ok'));
        cl.validerInconnue = propre(X.valider(2030, 'Conforme'));
        const a2 = O.instantane(COL);
        const v = propre(X.valider(2026, '  Exercice 2026 conforme  '));
        cl.valider = v;
        cl.ecartValidation = O.ecart(a2, O.instantane(COL));
        cl.etatApres = X.etat(2026);
        cl.fiche = propre(X.de(2026));
        cl.fiche2027 = propre(X.de(2027));
        cl.provisoires2027 = X.provisoires(2027).length;
        // la lecture seule joue désormais sur 2026
        const colE = S.collection('ecritures');
        const g0 = O.toasts.length;
        const res = colE.insert({ numero: 'T-9', date: '2026-07-01', journal: 'OD', compte: '411100', debit: 10, credit: 0, statut: 'brouillon' });
        cl.ecritureApresCloture = { rendu: res === null ? null : typeof res, toast: O.toasts.slice(g0).map((t) => t.detail) };
        cl.seconde = propre(X.valider(2026, 'Conforme'));
        cl.demandeApres = propre(X.demander(2026));
        cl.preApres = pre(2026);
        cl.journal = propre(S.collection('audit').all().slice(0, 12).map((a) => ({ action: a.action, entite: a.entite, reference: a.reference, utilisateur: a.utilisateur })));
        cl.nbOD = db().ecritures.filter((e) => e.numero === 'OD-2026-RES').length;
        cl.nbAN = db().ecritures.filter((e) => e.journal === 'AN' && e.date === '2027-01-01').length;
        cl.ecritureArchive = propre(db().documents.filter((d) => d.codeRattachement === 'EX2026').map((d) => ({ libelle: d.libelle, categorie: d.categorie, conservation: d.conservation, contenu: d.contenu })));
        cl.toasts = O.toasts.slice(t0).map((t) => ({ message: t.message, type: t.type, detail: t.detail }));
        session(base.role, base.nom);
        rep.cloture = cl;
      }

      /* ---------- 7. l'écran « Exercices & clôtures » -------------------------------------------------------------------------------- */
      {
        poserJeu(); valideTout();
        const ecr = {};
        const lire = async (role, nom) => {
          session(role, nom);
          const root = await O.monter('m12-cloture');
          const r = O.releve(root);
          r.lignes = O.lignesDe(root, 0);
          root.remove();
          return r;
        };
        ecr.admin = await lire('admin', 'BASSONGUI Chabi Séko');
        ecr.comptable = await lire('comptable', 'KASSA Augustin');
        ecr.directionAvantDemande = await lire('direction', 'BASSONGUI Chabi Séko');
        ecr.aideComptable = await lire('aide_comptable', 'AGBO Estelle');
        // pré-clôture (modale) et demande
        session('comptable', 'KASSA Augustin');
        {
          const root = await O.monter('m12-cloture');
          if (!O.bouton(root, /Pré-clôture/)) throw new Error('DEBUG ' + JSON.stringify({ etat: X.etat(2026), liste: X.liste().map((x) => [x.annee, x.etat]), boutons: O.releve(root).boutons, role: (S.session() || {}).role }));
          await O.cliquer(root, /Pré-clôture/);
          const d = O.dialogue();
          ecr.preModale = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean),
            lignes: [...d.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map(texte)) };
          await O.cliquer(d, /Demander la clôture/);
          const d2 = O.dialogue();
          ecr.confirmationDemande = { texte: texte(d2), boutons: [...d2.querySelectorAll('button')].map(texte).filter(Boolean) };
          root.remove(); O.fermerDialogues();
        }
        // exercice en attente : affichage direction (bouton « Valider la clôture »)
        X.demander(2026);
        ecr.directionEnAttente = await lire('direction', 'BASSONGUI Chabi Séko');
        ecr.comptableEnAttente = await lire('comptable', 'KASSA Augustin');
        {
          session('direction', 'BASSONGUI Chabi Séko');
          const root = await O.monter('m12-cloture');
          await O.cliquer(root, /Valider la clôture/);
          const d = O.dialogue();
          ecr.modaleValidation = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean) };
          const t0 = O.toasts.length;
          // sans motif : refus
          await O.cliquer(d, /Valider et clôturer/);
          ecr.validationSansMotif = O.toasts.slice(t0).map((t) => ({ message: t.message, detail: t.detail }));
          root.remove(); O.fermerDialogues();
        }
        // périodes et lettrage
        session('admin', 'BASSONGUI Chabi Séko');
        {
          const root = await O.monter('m12-cloture');
          await O.onglet(root, /Périodes/);
          ecr.periodes = { lignes: O.lignesDe(root, 0), titre: texte(root.querySelector('.card-title')) };
          await O.onglet(root, /Lettrage/);
          ecr.lettrage = { texte: texte(root), boutons: [...root.querySelectorAll('button')].map(texte).filter(Boolean),
            options: [...root.querySelectorAll('select option')].map((o) => [o.value, texte(o)]),
            lignes: O.lignesDe(root, 0).slice(0, 5), nbLignes: O.lignesDe(root, 0).length };
          root.remove();
        }
        rep.ecranCloture = ecr;
        poserJeu(); session(base.role, base.nom);
      }

      /* ---------- 8. l'écran « Bilan d'ouverture & à-nouveaux » -------------------------------------------------------------------- */
      {
        poserJeu();
        const ec = {};
        const root = await O.monter('m12-ouverture');
        ec.initial = O.releve(root);
        ec.selecteur = [...root.querySelectorAll('select option')].map((o) => [o.value, texte(o)]);
        ec.lignes = O.lignesDe(root, 0);
        ec.boutons = [...root.querySelectorAll('button')].map(texte).filter(Boolean);
        const pa = O.pieces.length;
        await O.cliquer(root, /Imprimer le bilan d’ouverture/);
        ec.piece = O.pieces.length > pa ? O.pieces[O.pieces.length - 1] : null;
        // report : confirmation puis écriture
        const a0 = O.instantane(['ecritures']);
        const t0 = O.toasts.length;
        await O.cliquer(root, /Écrire les à-nouveaux/);
        const d = O.dialogue();
        ec.confirmation = { texte: texte(d), boutons: [...d.querySelectorAll('button')].map(texte).filter(Boolean) };
        const ok = [...d.querySelectorAll('button')].find((b) => /Écrire le report/.test(texte(b)));
        ok.click(); await dormir(300);
        ec.ecart = O.ecart(a0, O.instantane(['ecritures']));
        ec.toast = O.toasts.slice(t0).map((t) => ({ message: t.message, type: t.type, detail: t.detail }));
        ec.apres = O.releve(root);
        ec.notesApres = ec.apres.notes;
        // seconde écriture : refusée
        const t1 = O.toasts.length;
        await O.cliquer(root, /Écrire les à-nouveaux/);
        ec.secondReport = O.toasts.slice(t1).map((t) => ({ message: t.message, type: t.type, detail: t.detail }));
        root.remove(); O.fermerDialogues();
        // déséquilibre : une ligne validée sans contrepartie
        poserJeu();
        db().ecritures.unshift({ id: 'X-DESEQ', numero: 'ODX', date: '2026-05-05', journal: 'OD', compte: '571000', compteLibelle: 'Caisse', debit: 5000, credit: 0, statut: 'validee' });
        const r2 = await O.monter('m12-ouverture');
        ec.deseq = O.releve(r2);
        const t2 = O.toasts.length;
        await O.cliquer(r2, /Écrire les à-nouveaux/);
        ec.deseqRefus = O.toasts.slice(t2).map((t) => ({ message: t.message, type: t.type, detail: t.detail }));
        r2.remove();
        // l'engin de report : les droits (commande d'écriture absente sans droit d'éditer)
        poserJeu();
        for (const [role, nom] of [['direction', 'BASSONGUI Chabi Séko'], ['comptable', 'KASSA Augustin'], ['aide_comptable', 'AGBO Estelle']]) {
          session(role, nom);
          const r3 = await O.monter('m12-ouverture');
          (ec.parRole = ec.parRole || {})[role] = [...r3.querySelectorAll('button')].map(texte).filter(Boolean);
          r3.remove();
        }
        session(base.role, base.nom);
        rep.ecranOuverture = ec;
      }
      rep.toastsTotal = O.toasts.length;
      return rep;
    }, jeu);
    if (m.erreurs.length) console.log('  ⚠ erreurs JS de la page : ' + m.erreurs.slice(0, 5).join(' | '));
    ecrire('packages/domaine/test/vecteurs/exercice.json', sortie);
    console.log('  ✓ ' + Object.keys(sortie).length + ' blocs');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
