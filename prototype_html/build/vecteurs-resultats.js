/* =============================================================================
 * VECTEURS DES RÉSULTATS DU LABORATOIRE — m5-resultats, m5-impression-resultats, m5-resultats-comparatif, m5-stats
 * -----------------------------------------------------------------------------
 * Deux familles, toutes deux TIRÉES DE LA MAQUETTE EN MARCHE (jamais de la lecture du code) :
 *   - les MOTEURS exposés (PR.capacites, PR.peutVoirResultat, PR.validerBiologique, PR.rectifierResultat, PR.validerTechnique,
 *     PR.continuiteRespectee, SIGH.laboPlages, D.resultatRendu, L.ecart) appelés sur des fiches posées au magasin jetable ;
 *   - les ÉCRANS rendus et lus (KPI, onglets, lignes, boutons, règlement, comparatif, statistiques), sous chaque profil.
 *   node build/vecteurs-resultats.js   →   packages/domaine/test/vecteurs/resultats.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des résultats du laboratoire');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m5-laboratoire.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, PR = SIGH.parcours, C = SIGH.core, D = SIGH.data, L = SIGH.labo, G = SIGH.charts, K = SIGH.kit, P = SIGH.print;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const colD = S.collection('demandesAnalyses'), colF = S.collection('factures'), colN = S.collection('notifications'), colPl = S.collection('plagesReactif');
      const colP = S.collection('patients');
      const colV = S.collection('variablesLabo');
      /* Les fiches du jeu sont ARCHIVÉES (jamais supprimées) : `amorcer()` ne ressème pas une collection non vide. */
      colD.all().forEach((r) => { r.statut = 'archive'; });
      colF.all().forEach((r) => { r.statut = 'archive'; });
      colPl.all().forEach((r) => { r.statut = 'archive'; });
      const retirerPose = [];
      let seq = 0;
      const poserDemande = (o) => { seq++; return colD.insert(Object.assign({ reference: 'LAB-9' + String(seq).padStart(4, '0'), codeAnalyse: String(seq).padStart(5, '0') + '-2026',
        patientId: 'PX1', patient: 'TEST Alpha', patientCode: 'CNT/901/26', analyseCode: 'L24', analyse: 'NFS COMPLETE (HEMOGRAMME)', examenCode: 'NFS',
        categorie: 'Hématologie', echantillon: 'Sang', prix: 4000, dateHeure: '2026-08-10T09:00:00.000Z', prescripteur: 'Dr TEST Prescripteur',
        laborantin: 'KINNOU Ganiou', urgent: false, etatAnalyse: 'valide', origine: 'ordonnance', secteurDemandeur: 'MÉDECINE GÉNÉRALE' }, o)).record; };
      const session = (o) => { localStorage.setItem('sigh-cnt:session', JSON.stringify(Object.assign({ role: 'admin', nom: 'BASSONGUI Chabi Séko', id: 'AG1' }, o))); };
      const net = (d) => {
        const c = propre(d);
        if (!c) return null;
        ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statut', 'valideLe', 'valideTechniqueLe', 'rectifieLe'].forEach((k) => delete c[k]);
        if (c.versions) c.versions = c.versions.map((v) => { const w = Object.assign({}, v); delete w.remplaceeLe; delete w.valideLe; return w; });
        return c;
      };
      const instantane = (col) => col.active().map((r) => { const c = propre(r); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe'].forEach((k) => delete c[k]); return c; });
      const entrees = {};
      const netNotif = (n) => { const c = propre(n); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statut', 'date', 'dateHeure', 'creeLe', 'horodatage'].forEach((k) => delete c[k]); return c; };

      /* ===== 1. États et capacités ===== */
      const etats = { liste: propre(D.ETATS_RESULTAT), rendu: {}, inconnu: propre(D.etatResultat('zz_inconnu')), vide: propre(D.etatResultat(undefined)) };
      D.ETATS_RESULTAT.map((e) => e.id).concat(['zz_inconnu', null]).forEach((id) => { etats.rendu[String(id)] = D.resultatRendu(id); });

      const sessions = [
        { nom: 'médecin', s: { role: 'medecin', fonction: 'medecin' } },
        { nom: 'sage-femme du secteur MAT', s: { role: 'infirmier', fonction: 'sage_femme', secteur: 'MAT' } },
        { nom: 'sage-femme sans secteur', s: { role: 'infirmier', fonction: 'sage_femme' } },
        { nom: 'infirmier', s: { role: 'infirmier', fonction: 'infirmier' } },
        { nom: 'aide-soignant', s: { role: 'infirmier', fonction: 'aide_soignant' } },
        { nom: 'TSL', s: { role: 'laborantin', fonction: 'tsl' } },
        { nom: 'biologiste', s: { role: 'laborantin', fonction: 'biologiste' } },
        { nom: 'accueil', s: { role: 'reception', fonction: 'accueil' } },
        { nom: 'direction', s: { role: 'direction', fonction: 'direction' } },
        { nom: 'fonction inconnue, rôle médecin', s: { role: 'medecin', fonction: 'zz_inconnue' } },
        { nom: 'fonction inconnue, rôle laborantin', s: { role: 'laborantin', fonction: 'zz_inconnue' } },
        { nom: 'rôle caissier sans fonction', s: { role: 'caissier' } },
        { nom: 'ni rôle ni fonction', s: {} },
      ];
      const toutesCapacites = propre(D.CAPACITES);
      const roleFonction = {};
      Object.keys(SIGH.nav.ROLES).concat(['zz_role_inconnu']).forEach((r) => { roleFonction[r] = PR.capacites({ role: r }).fonction; });
      const capacites = sessions.map((x) => {
        const c = PR.capacites(x.s);
        return { nom: x.nom, session: x.s, fonction: c.fonction, fonctionInconnue: c.fonctionInconnue, label: c.label, voirResultats: c.voirResultats,
          validerTechnique: !!c.validerTechnique, validerBiologique: c.validerBiologique === undefined ? null : c.validerBiologique,
          continuitePrelevement: !!c.continuitePrelevement, secteurs: c.secteurs || [], remettreResultats: !!c.remettreResultats };
      });

      /* ===== 2. Visibilité d'un résultat ===== */
      const dems = [
        { nom: 'validé, maternité', d: { etatAnalyse: 'valide', secteurDemandeur: 'MATERNITÉ' } },
        { nom: 'validé, chirurgie', d: { etatAnalyse: 'valide', secteurDemandeur: 'CHIRURGIE' } },
        { nom: 'validé, sans secteur', d: { etatAnalyse: 'valide' } },
        { nom: 'rectifié, hospitalisation', d: { etatAnalyse: 'rectifie', secteurDemandeur: 'HOSPI' } },
        { nom: 'validation technique, maternité', d: { etatAnalyse: 'valide_technique', secteurDemandeur: 'MATERNITÉ' } },
        { nom: 'saisi, médecine', d: { etatAnalyse: 'saisi' } },
        { nom: 'en attente', d: { etatAnalyse: 'en_attente' } },
        { nom: 'sans état', d: { secteurDemandeur: 'MATERNITÉ' } },
        { nom: 'secteur en minuscules', d: { etatAnalyse: 'valide', secteurDemandeur: 'maternité' } },
      ];
      const visibilite = [];
      sessions.forEach((x) => dems.forEach((dm) => {
        const r = PR.peutVoirResultat(dm.d, x.s);
        visibilite.push({ session: x.nom, sessionFiche: x.s, demande: dm.nom, demandeFiche: dm.d, autorise: r.autorise, motif: r.motif, enAttenteValidation: !!r.enAttenteValidation });
      }));

      /* ===== 3. Continuité du prélèvement ===== */
      const continuite = [];
      [
        ['préleveur identifié par id, même agent', { preleveParId: 'AG1', prelevePar: 'KINNOU Ganiou' }, { id: 'AG1', nomComplet: 'KINNOU Ganiou' }],
        ['préleveur identifié par id, autre agent', { preleveParId: 'AG2', prelevePar: 'IMOROU Choucouratou' }, { id: 'AG1', nomComplet: 'KINNOU Ganiou' }],
        ['même agent reconnu par son nom', { prelevePar: 'KINNOU Ganiou' }, { id: 'AG9', nomComplet: 'KINNOU Ganiou' }],
        ['autre agent, nom seul', { prelevePar: 'IMOROU Choucouratou' }, { id: 'AG1', nomComplet: 'KINNOU Ganiou' }],
        ['aucun prélèvement enregistré', {}, { id: 'AG1', nomComplet: 'KINNOU Ganiou' }],
        ['agent donné en chaîne (identifiant)', { preleveParId: 'AG1', prelevePar: 'KINNOU Ganiou' }, 'AG1'],
        ['agent donné en chaîne, autre', { preleveParId: 'AG2', prelevePar: 'IMOROU Choucouratou' }, 'AG1'],
        ['agent absent', { preleveParId: 'AG2', prelevePar: 'IMOROU Choucouratou' }, null],
        ['id de préleveur sans nom', { preleveParId: 'AG2' }, { id: 'AG1', nomComplet: 'X' }],
      ].forEach(([nom, d, agent]) => { const r = PR.continuiteRespectee(d, agent); continuite.push({ nom, demande: d, agent, ok: r.ok, motif: r.motif === undefined ? null : r.motif, preleveur: r.preleveur === undefined ? null : r.preleveur }); });
      const cInconnue = PR.continuiteRespectee(null, { id: 'AG1' });
      continuite.push({ nom: 'demande introuvable', demande: null, agent: { id: 'AG1' }, ok: cInconnue.ok, motif: cInconnue.motif, preleveur: null });

      /* ===== 4. Validation technique / biologique / rectification ===== */
      const valeursNfs = { GB: 5.5, GR: 4.2 };
      const verrous = [];
      async function geste(nom, fabriquer, appeler) {
        const avantN = new Set(colN.all().map((x) => x.id));
        const d0 = fabriquer();
        const entree = propre(d0);
        let erreur = null, res = null;
        try { res = appeler(d0); } catch (e) { erreur = e.message; }
        const apres = colD.get(d0.id);
        verrous.push({ nom, entree: net(entree), erreur, version: res && res.version !== undefined ? res.version : null, interim: res && res.interim !== undefined ? res.interim : null,
          apres: net(apres), notifications: colN.all().filter((x) => !avantN.has(x.id)).map(netNotif) });
      }
      const sTSL = { role: 'laborantin', fonction: 'tsl' }, sBio = { role: 'laborantin', fonction: 'biologiste' }, sMed = { role: 'medecin', fonction: 'medecin' };
      await geste('technique : valeurs saisies → validation technique', () => poserDemande({ etatAnalyse: 'saisi', valeurs: valeursNfs }), (d) => PR.validerTechnique(d.id, { utilisateur: 'KINNOU Ganiou' }));
      await geste('technique : aucune valeur saisie → refus', () => poserDemande({ etatAnalyse: 'saisi' }), (d) => PR.validerTechnique(d.id, { utilisateur: 'KINNOU Ganiou' }));
      await geste('technique : valeurs vides → refus', () => poserDemande({ etatAnalyse: 'saisi', valeurs: {} }), (d) => PR.validerTechnique(d.id, { utilisateur: 'KINNOU Ganiou' }));
      await geste('technique : demande introuvable', () => ({ id: 'INCONNUE', reference: 'X' }), (d) => PR.validerTechnique(d.id, {}));
      await geste('biologique : le biologiste valide, le prescripteur est notifié', () => poserDemande({ etatAnalyse: 'valide_technique', valeurs: valeursNfs }),
        (d) => PR.validerBiologique(d.id, { session: sBio, utilisateur: 'KINNOU Ganiou' }));
      await geste('biologique : le TSL valide par intérim, tracé sur la pièce', () => poserDemande({ etatAnalyse: 'valide_technique', valeurs: valeursNfs, version: 3 }),
        (d) => PR.validerBiologique(d.id, { session: sTSL, utilisateur: 'IMOROU Choucouratou' }));
      await geste('biologique : un médecin n\'y est pas habilité → refus', () => poserDemande({ etatAnalyse: 'valide_technique', valeurs: valeursNfs }),
        (d) => PR.validerBiologique(d.id, { session: sMed, utilisateur: 'Dr X' }));
      await geste('biologique : la validation technique doit précéder (saisi) → refus', () => poserDemande({ etatAnalyse: 'saisi', valeurs: valeursNfs }),
        (d) => PR.validerBiologique(d.id, { session: sBio, utilisateur: 'KINNOU Ganiou' }));
      await geste('biologique : déjà validé → refus', () => poserDemande({ etatAnalyse: 'valide', valeurs: valeursNfs }),
        (d) => PR.validerBiologique(d.id, { session: sBio, utilisateur: 'KINNOU Ganiou' }));
      await geste('biologique : demande introuvable', () => ({ id: 'INCONNUE', reference: 'X' }), (d) => PR.validerBiologique(d.id, { session: sBio }));
      await geste('biologique : prescripteur absent, notification sans destinataire', () => poserDemande({ etatAnalyse: 'valide_technique', valeurs: valeursNfs, prescripteur: undefined }),
        (d) => PR.validerBiologique(d.id, { session: sBio, utilisateur: 'KINNOU Ganiou' }));
      const nouv = { GB: 6.1, GR: 4.4, HB: 12.5 };
      await geste('rectification : première (v1 → v2), version sortante conservée', () => poserDemande({ etatAnalyse: 'valide', valeurs: valeursNfs, valideBiologiquePar: 'KINNOU Ganiou', valideLe: '2026-08-11T10:00:00.000Z', conclusion: 'Normal', commentaireGeneral: 'RAS' }),
        (d) => PR.rectifierResultat(d.id, nouv, { motif: 'Erreur de transcription du GB', commentaireGeneral: 'Corrigé', utilisateur: 'KINNOU Ganiou' }));
      await geste('rectification : seconde (v2 → v3), les deux versions sortantes sont conservées', () => poserDemande({ etatAnalyse: 'rectifie', version: 2, valeurs: nouv, versions: [{ numero: 1, valeurs: valeursNfs, commentaireGeneral: null, conclusion: 'Normal', valideLe: '2026-08-11T10:00:00.000Z', valideBiologiquePar: 'KINNOU Ganiou', remplaceeLe: '2026-08-12T10:00:00.000Z', motifRemplacement: 'Première correction' }] }),
        (d) => PR.rectifierResultat(d.id, { GB: 6.3 }, { motif: 'Second contrôle', utilisateur: 'IMOROU Choucouratou' }));
      await geste('rectification : commentaire général non fourni → l\'ancien est gardé', () => poserDemande({ etatAnalyse: 'valide', valeurs: valeursNfs, commentaireGeneral: 'Échantillon limpide' }),
        (d) => PR.rectifierResultat(d.id, nouv, { motif: 'Contre-expertise', utilisateur: 'KINNOU Ganiou' }));
      await geste('rectification : sans motif → refus', () => poserDemande({ etatAnalyse: 'valide', valeurs: valeursNfs }), (d) => PR.rectifierResultat(d.id, nouv, { utilisateur: 'KINNOU Ganiou' }));
      await geste('rectification : résultat non encore validé biologiquement → refus', () => poserDemande({ etatAnalyse: 'valide_technique', valeurs: valeursNfs }),
        (d) => PR.rectifierResultat(d.id, nouv, { motif: 'Erreur', utilisateur: 'KINNOU Ganiou' }));
      await geste('rectification : demande introuvable', () => ({ id: 'INCONNUE', reference: 'X' }), (d) => PR.rectifierResultat(d.id, nouv, { motif: 'Erreur' }));

      /* ===== 5. Plages par lot et écart ===== */
      const vNfs = colV.get('VAR-NFS-GB');
      const lib = (v) => L.libelleReference(v);
      const plages = { variable: propre(vNfs), cas: [], ecarts: [], references: [] };
      const poserPlage = (o) => colPl.insert(Object.assign({ variableId: 'VAR-NFS-GB', lot: 'LOT', dateDebut: '2026-01-01', min: 3, max: 9 }, o)).record;
      const pA = poserPlage({ lot: 'LOT-A', dateDebut: '2026-03-01', min: 3, max: 9 });
      const pB = poserPlage({ lot: 'LOT-B', dateDebut: '2026-09-01', min: 5, max: 7 });
      const pArchivee = poserPlage({ lot: 'LOT-ARCHIVÉ', dateDebut: '2026-10-01', min: 1, max: 2 }); pArchivee.statut = 'archive';
      const pSansDate = poserPlage({ lot: 'LOT-SANS-DATE', dateDebut: null, min: 0, max: 20, variableId: 'VAR-NFS-GR' });
      const pAutre = poserPlage({ lot: 'LOT-AUTRE', dateDebut: '2026-01-01', min: 1, max: 2, variableId: 'VAR-AUTRE' });
      const vGr = colV.get('VAR-NFS-GR');
      [['avant toute plage', '2026-02-28'], ['au jour d\'entrée du lot A', '2026-03-01'], ['sous le lot A', '2026-05-15T10:00:00.000Z'], ['la veille du lot B', '2026-08-31'],
        ['au jour d\'entrée du lot B', '2026-09-01'], ['sous le lot B', '2026-12-31'], ['plage archivée ignorée', '2026-10-15'], ['date vide : repli sur aujourd\'hui', '']].forEach(([nom, date]) => {
        const p = SIGH.laboPlages.plagePour(vNfs, date), v = SIGH.laboPlages.variableALaDate(vNfs, date), r = SIGH.laboPlages.referenceALaDate(vNfs, date);
        plages.cas.push({ nom, date, lot: p ? p.lot : null, min: v.min === undefined ? null : v.min, max: v.max === undefined ? null : v.max, reference: r });
      });
      plages.cas.push({ nom: 'plage sans date : vaut depuis toujours', date: '2026-02-01', lot: SIGH.laboPlages.plagePour(vGr, '2026-02-01') && SIGH.laboPlages.plagePour(vGr, '2026-02-01').lot,
        min: SIGH.laboPlages.variableALaDate(vGr, '2026-02-01').min, max: SIGH.laboPlages.variableALaDate(vGr, '2026-02-01').max, reference: SIGH.laboPlages.referenceALaDate(vGr, '2026-02-01') });
      plages.cas.push({ nom: 'variable sans plage : la borne de la variable fait foi', date: '2026-06-01', lot: SIGH.laboPlages.plagePour(colV.get('VAR-NFS-HB'), '2026-06-01') ? 'x' : null,
        min: SIGH.laboPlages.variableALaDate(colV.get('VAR-NFS-HB'), '2026-06-01').min, max: SIGH.laboPlages.variableALaDate(colV.get('VAR-NFS-HB'), '2026-06-01').max, reference: SIGH.laboPlages.referenceALaDate(colV.get('VAR-NFS-HB'), '2026-06-01') });
      plages.pose = [pA, pB, pSansDate, pAutre].map((p) => ({ variableId: p.variableId, lot: p.lot, dateDebut: p.dateDebut === undefined ? null : p.dateDebut, min: p.min, max: p.max })).concat([{ variableId: 'VAR-NFS-GB', lot: 'LOT-ARCHIVÉ', dateDebut: '2026-10-01', min: 1, max: 2, archive: true }]);
      const types = [
        { type: 'numerique', min: 4, max: 8 }, { type: 'numerique', max: 6 }, { type: 'numerique', min: 0.35 }, { type: 'numerique' },
        { type: 'binaire', normal: 'Négatif' }, { type: 'binaire' }, { type: 'ternaire', normal: 'Négatif' }, { type: 'liste', normal: 'Clair' },
        { type: 'titre', normal: 'Négatif' }, { type: 'texte' }, { type: 'reactif' }, { type: 'lot', min: 1, max: 2 }, { type: 'commentaire' }, { type: 'expiration' },
        { type: 'numerique', regle: 'Selon âge', min: 4, max: 8 },
      ];
      const valeurs = [3.9, 4, 6, 8, 8.1, '5,5', 'abc', '', null, 'Positif', 'Négatif', 'Clair', 'Trouble', '1/80', 0, '0.35', '0.3'];
      types.forEach((v) => valeurs.forEach((val) => plages.ecarts.push({ variable: v, valeur: val, ecart: L.ecart(v, val), reference: lib(v) })));
      plages.ecarts.push({ variable: null, valeur: 5, ecart: L.ecart(null, 5), reference: lib(null) });

      /* ===== 6. Écrans : outils de lecture ===== */
      const texte = (e) => (e ? e.textContent.replace(/\s+/g, ' ').trim() : '');
      const monter = async (id) => {
        const root = document.createElement('div'); document.body.appendChild(root);
        const jeux = []; G.__enregistrer = jeux;
        SIGH.screens[id].render(root);
        await dormir(40);
        return { root, jeux, demonter: () => { root.remove(); document.querySelectorAll('.modal-root,[role=dialog]').forEach((e) => e.remove()); } };
      };
      const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => ({ libelle: texte(k.querySelector('.kpi-label')), valeur: texte(k.querySelector('.kpi-value')), indice: texte(k.querySelector('.text-xs.text-slate-400')) }));
      const lignes = (root) => [...root.querySelectorAll('table tbody tr')].map((tr) => ({
        cellules: [...tr.querySelectorAll('td')].map((td) => texte(td)),
        boutons: [...tr.querySelectorAll('button')].map((b) => ({ t: b.getAttribute('title') || b.getAttribute('aria-label') || texte(b), lib: texte(b), verrou: b.getAttribute('aria-disabled') === 'true' })),
      }));
      const notes = (root) => [...root.querySelectorAll('div')].filter((e) => /^(rounded|flex)/.test(e.className) && e.className.includes('border-') && (e.className.includes('bg-info-50') || e.className.includes('bg-warning-50'))).map(texte);
      const onglets = (root) => [...root.querySelectorAll('.tab')].map((b) => texte(b));
      const cliquerOnglet = async (root, i) => { [...root.querySelectorAll('.tab')][i].click(); await dormir(40); };
      const tbody = (root) => [...root.querySelectorAll('table tbody tr')];

      /* Le jeu des écrans : dix demandes réparties sur tous les états, deux patients. */
      colD.all().forEach((r) => { r.statut = 'archive'; });
      const jeuEcran = () => {
        const A = { patientId: 'PX1', patient: 'TEST Alpha', patientCode: 'CNT/901/26' }, B = { patientId: 'PX2', patient: 'TEST Bravo', patientCode: 'CNT/902/26' };
        const prel = { prelevePar: 'KINNOU Ganiou', preleveParId: 'AG1', preleveLe: '2026-08-10T08:00:00.000Z' };
        const prel2 = { prelevePar: 'IMOROU Choucouratou', preleveParId: 'AG2', preleveLe: '2026-08-10T08:00:00.000Z' };
        return [
          poserDemande(Object.assign({ etatAnalyse: 'en_attente', dateHeure: '2026-08-10T09:00:00.000Z', bloqueParPaiement: true, factureNumero: 'FP-X-1' }, A)),
          poserDemande(Object.assign({ etatAnalyse: 'attente_prelevement', dateHeure: '2026-08-11T09:00:00.000Z' }, B)),
          poserDemande(Object.assign({ etatAnalyse: 'preleve', dateHeure: '2026-08-12T09:00:00.000Z' }, A, prel)),
          poserDemande(Object.assign({ etatAnalyse: 'en_cours', dateHeure: '2026-08-13T09:00:00.000Z', urgent: true }, B, prel)),
          poserDemande(Object.assign({ etatAnalyse: 'saisi', dateHeure: '2026-08-14T09:00:00.000Z', valeurs: { GB: 5 } }, A, prel)),
          poserDemande(Object.assign({ etatAnalyse: 'valide_technique', dateHeure: '2026-08-15T09:00:00.000Z', valeurs: { GB: 5, GR: 4 }, resultat: 'GB 5', conclusion: 'Normal', valideTechniquePar: 'KINNOU Ganiou' }, A, prel)),
          poserDemande(Object.assign({ etatAnalyse: 'valide_technique', dateHeure: '2026-08-16T09:00:00.000Z', valeurs: { GB: 12 }, resultat: 'GB 12', conclusion: 'Anormal', valideTechniquePar: 'IMOROU Choucouratou' }, B, prel2)),
          poserDemande(Object.assign({ etatAnalyse: 'valide', dateHeure: '2026-08-17T09:00:00.000Z', secteurDemandeur: 'MATERNITÉ', valeurs: { GB: 6 }, resultat: 'GB 6', conclusion: 'Normal', valideBiologiquePar: 'KINNOU Ganiou' }, A, prel)),
          poserDemande(Object.assign({ etatAnalyse: 'valide', dateHeure: '2026-08-18T09:00:00.000Z', secteurDemandeur: 'CHIRURGIE', valeurs: { GB: 9 }, resultat: 'GB 9', conclusion: 'À recontrôler', valideBiologiquePar: 'IMOROU Choucouratou', validationInterim: true }, B, prel2)),
          poserDemande(Object.assign({ etatAnalyse: 'rectifie', version: 2, dateHeure: '2026-08-19T09:00:00.000Z', secteurDemandeur: 'MATERNITÉ', valeurs: { GB: 7 }, resultat: 'GB 7', conclusion: 'Normal', valideBiologiquePar: 'KINNOU Ganiou' }, A, prel)),
        ];
      };
      const refs = jeuEcran().map((d) => d.reference);
      entrees.resultats = { demandes: instantane(colD) };

      /* ===== 7. m5-resultats ===== */
      const resultats = [];
      const profilsEcran = [
        { nom: 'médecin', s: { role: 'medecin', fonction: 'medecin', id: 'AG5', nom: 'Dr TEST' } },
        { nom: 'sage-femme MAT', s: { role: 'infirmier', fonction: 'sage_femme', secteur: 'MAT', id: 'AG6', nom: 'SF TEST' } },
        { nom: 'infirmier', s: { role: 'infirmier', fonction: 'infirmier', id: 'AG7', nom: 'Inf TEST' } },
        { nom: 'TSL', s: { role: 'laborantin', fonction: 'tsl', id: 'AG2', nom: 'IMOROU Choucouratou' } },
        { nom: 'biologiste (a prélevé AG1)', s: { role: 'laborantin', fonction: 'biologiste', id: 'AG1', nom: 'KINNOU Ganiou' } },
        { nom: 'biologiste (autre)', s: { role: 'laborantin', fonction: 'biologiste', id: 'AG3', nom: 'AUTRE Biologiste' } },
        { nom: 'direction', s: { role: 'direction', fonction: 'direction', id: 'AG8', nom: 'DIR TEST' } },
      ];
      const plagesDates = [{ nom: 'toutes les dates', du: '', au: '' }, { nom: '12 au 17 août', du: '2026-08-12', au: '2026-08-17' }, { nom: 'à partir du 18 août', du: '2026-08-18', au: '' }];
      for (const pr of profilsEcran) for (const pd of plagesDates) {
        session(pr.s);
        const ec = await monter('m5-resultats');
        const entrees = ec.root.querySelectorAll('input[type=date]');
        entrees[0].value = pd.du; entrees[0].dispatchEvent(new Event('change'));
        entrees[1].value = pd.au; entrees[1].dispatchEvent(new Event('change'));
        await dormir(40);
        const cas = { profil: pr.nom, session: pr.s, plage: pd, kpis: kpis(ec.root), onglets: onglets(ec.root), notes: notes(ec.root), tableaux: [] };
        cas.tableaux.push({ onglet: 0, lignes: lignes(ec.root) });
        await cliquerOnglet(ec.root, 1);
        cas.tableaux.push({ onglet: 1, lignes: lignes(ec.root), notes: notes(ec.root), selection: !!ec.root.querySelector('table thead input[type=checkbox]') });
        await cliquerOnglet(ec.root, 2);
        cas.tableaux.push({ onglet: 2, lignes: lignes(ec.root), selection: !!ec.root.querySelector('table thead input[type=checkbox]') });
        resultats.push(cas);
        ec.demonter();
      }

      /* ===== 7 bis. La modale de SAISIE, pilotée : quel examen, quelles variables, quels champs, quel écart À LA SAISIE ===== */
      const saisie = [];
      async function jouerSaisie(nom, extra, valeurs) {
        colD.all().forEach((r) => { r.statut = 'archive'; });
        const d = poserDemande(Object.assign({ etatAnalyse: 'en_cours', plan: 1, prelevePar: 'KINNOU Ganiou', preleveParId: 'AG1', preleveLe: '2026-08-10T08:00:00.000Z' }, extra));
        session({ role: 'laborantin', fonction: 'biologiste', id: 'AG1', nom: 'KINNOU Ganiou' });
        const ec = await monter('m5-resultats');
        const b = [...ec.root.querySelectorAll('button')].find((x) => texte(x) === 'Saisir le résultat');
        b.click();
        await dormir(60);
        const modale = document.querySelector('[role=dialog]');
        const cas = { nom, demande: net(d), ouverte: !!modale };
        if (modale) {
          cas.titre = texte(modale.querySelector('h2, h3, .modal-title') || modale.firstElementChild);
          const champs = (td) => {
            const e = td.querySelector('select, textarea, input');
            if (!e) return null;
            return { balise: e.tagName.toLowerCase(), type: e.getAttribute('type'), options: e.tagName === 'SELECT' ? [...e.options].map((o) => o.textContent) : null, libre: td.querySelectorAll('input').length > 1 };
          };
          const lire = () => [...modale.querySelectorAll('table tbody tr')].map((tr) => { const td = tr.querySelectorAll('td'); return { variable: texte(td[0]), champ: champs(td[1]), unite: texte(td[2]), reference: texte(td[3]), ecart: texte(td[4]) }; });
          cas.lignes = lire();
          if (valeurs) {
            [...modale.querySelectorAll('table tbody tr')].forEach((tr, i) => {
              const code = valeurs.__ordre[i];
              if (valeurs[code] === undefined) return;
              const e = tr.querySelector('td:nth-child(2) input, td:nth-child(2) select, td:nth-child(2) textarea');
              e.value = valeurs[code]; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change'));
            });
            await dormir(30);
            cas.apresSaisie = lire().map((l) => l.ecart);
          }
          cas.pied = [...modale.querySelectorAll('button')].map(texte).filter(Boolean);
        } else {
          cas.toasts = [...document.querySelectorAll('[role=status], [role=alert], .toast')].map(texte);
        }
        ec.demonter();
        saisie.push(cas);
      }
      const ordreNfs = SIGH.labo.variablesDe('NFS').filter((x) => x.actif !== false).map((x) => x.code);
      await jouerSaisie('par examenCode', { examenCode: 'NFS' });
      await jouerSaisie('par analyseCode (examenCode absent)', { examenCode: undefined, analyseCode: 'NFS', analyse: 'Libellé sans rapport' });
      await jouerSaisie('par désignation exacte', { examenCode: undefined, analyseCode: 'ZZ', analyse: 'NFS COMPLETE (HEMOGRAMME)' });
      await jouerSaisie('par début de désignation', { examenCode: undefined, analyseCode: 'ZZ', analyse: 'NFS COMPLETE' });
      await jouerSaisie('par code d\'examen en tête de la désignation', { examenCode: undefined, analyseCode: 'ZZ', analyse: 'NFS spécial urgent' });
      await jouerSaisie('examen inconnu : refus nommé', { examenCode: undefined, analyseCode: 'ZZ', analyse: 'EXAMEN INCONNU DU CATALOGUE' });
      await jouerSaisie('écart à la saisie, aux bornes du lot en service', { examenCode: 'NFS' }, Object.assign({ __ordre: ordreNfs }, { GB: '12', GR: '9', HB: '5', VGM: '85' }));
      const ordreVih = SIGH.labo.variablesDe('VIH').filter((x) => x.actif !== false).map((x) => x.code);
      await jouerSaisie('un examen à choix et à accompagnement (VIH)', { examenCode: 'VIH', analyse: 'VIH' }, Object.assign({ __ordre: ordreVih }, { [ordreVih[0]]: 'Positif' }));
      colD.all().forEach((r) => { r.statut = 'archive'; });

      /* ===== 8. m5-impression-resultats : le règlement se lit sur la LIGNE de facture ===== */
      colD.all().forEach((r) => { r.statut = 'archive'; });
      colF.all().forEach((r) => { r.statut = 'archive'; });
      const A = { patientId: 'PX1', patient: 'TEST Alpha', patientCode: 'CNT/901/26' };
      const dReg = (nom, o) => ({ nom, d: poserDemande(Object.assign({ etatAnalyse: 'valide', secteurDemandeur: 'MÉDECINE GÉNÉRALE' }, A, o)) });
      const reglements = [
        dReg('ligne payée', {}), dReg('ligne due', {}), dReg('deux lignes de factures, la dernière gagne', {}), dReg('bloquée par paiement, sans ligne', { bloqueParPaiement: true, factureNumero: 'FP-BLOQ-1' }),
        dReg('bloquée par paiement, sans numéro', { bloqueParPaiement: true }), dReg('sans pièce liée', {}), dReg('rectifié, payé', { etatAnalyse: 'rectifie', version: 2 }), dReg('non rendu (absent de l\'écran)', { etatAnalyse: 'valide_technique' }),
      ];
      const ligneF = (id, statutPaiement) => ({ id: 'L' + id, designation: 'NFS', quantite: 1, prixUnitaire: 4000, montant: 4000, partPatient: 4000, partAssureur: 0, demandeId: id, statutPaiement });
      colF.insert({ numero: 'FP-2026-P1', patient: 'TEST Alpha', lignes: [ligneF(reglements[0].d.id, 'paye'), ligneF(reglements[6].d.id, 'paye')], montantTTC: 8000 });
      colF.insert({ numero: 'FP-2026-D1', patient: 'TEST Alpha', lignes: [ligneF(reglements[1].d.id, 'du')], montantTTC: 4000 });
      colF.insert({ numero: 'FP-2026-D2', patient: 'TEST Alpha', lignes: [ligneF(reglements[2].d.id, 'du')], montantTTC: 4000 });
      colF.insert({ numero: 'FP-2026-P2', patient: 'TEST Alpha', lignes: [ligneF(reglements[2].d.id, 'paye')], montantTTC: 4000 });
      colF.insert({ numero: 'FP-2026-X0', patient: 'TEST Alpha', lignes: [{ id: 'LZ', designation: 'sans demande', montant: 100 }], montantTTC: 100 });
      const impression = [];
      for (const pr of [profilsEcran[0], profilsEcran[2], profilsEcran[3], profilsEcran[6]]) {
        session(pr.s);
        const ec = await monter('m5-impression-resultats');
        impression.push({ profil: pr.nom, session: pr.s, kpis: kpis(ec.root), lignes: lignes(ec.root), notes: notes(ec.root), selection: !!ec.root.querySelector('table thead input[type=checkbox]'),
          titreTableau: texte(ec.root.querySelector('.card-title')) });
        ec.demonter();
      }
      entrees.impression = { demandes: instantane(colD), factures: instantane(colF) };
      const reglementsPoses = reglements.map((r) => ({ nom: r.nom, reference: r.d.reference }));

      /* ===== 9. m5-resultats-comparatif ===== */
      colD.all().forEach((r) => { r.statut = 'archive'; });
      const mes = (date, valeurs, o) => poserDemande(Object.assign({ etatAnalyse: 'valide', dateHeure: date, valeurs, examenCode: 'NFS', secteurDemandeur: 'MÉDECINE GÉNÉRALE', patientId: 'PX1', patient: 'TEST Alpha', patientCode: 'CNT/901/26' }, o || {}));
      const m1 = mes('2026-03-05T09:00:00.000Z', { GB: 3.5, GR: 4.0, HB: 12, VGM: 85 });
      const m2 = mes('2026-06-10T09:00:00.000Z', { GB: 6.0, GR: 4.1, HB: 12 }, { etatAnalyse: 'rectifie', version: 2 });
      const m3 = mes('2026-09-20T09:00:00.000Z', { GB: 8.5, GR: 4.0, HB: 11.5 });
      mes('2026-09-21T09:00:00.000Z', { GB: 5 }, { etatAnalyse: 'valide_technique' });
      poserDemande({ etatAnalyse: 'valide', dateHeure: '2026-09-22T09:00:00.000Z', patientId: 'PX2', patient: 'TEST Bravo', patientCode: 'CNT/902/26', analyse: 'GLYCEMIE', analyseCode: 'L01', examenCode: 'GLY', valeurs: { GLY: 0.9 } });
      mes('2026-09-23T09:00:00.000Z', { GB: 5 }, { patientId: 'PX3', patient: 'TEST Charlie', patientCode: 'CNT/903/26', secteurDemandeur: 'CHIRURGIE' });
      const nfsPX2 = (date, analyse, valeurs) => poserDemande({ etatAnalyse: 'valide', dateHeure: date, patientId: 'PX2', patient: 'TEST Bravo', patientCode: 'CNT/902/26', analyse, analyseCode: 'L24', examenCode: undefined, valeurs });
      nfsPX2('2026-05-01T09:00:00.000Z', 'NFS COMPLETE (HEMOGRAMME)', { GB: 5, HB: 13 });
      nfsPX2('2026-07-01T09:00:00.000Z', 'NFS COMPLETE', { GB: 6.5, HB: 12.5 });
      mes('2026-04-01T09:00:00.000Z', {}, { patientId: 'PX3', patient: 'TEST Charlie', patientCode: 'CNT/903/26', valeurs: {} });
      entrees.comparatif = { demandes: instantane(colD), plages: instantane(colPl) };
      const ptr = pA; // les plages posées plus haut restent en service (lot A dès mars, lot B dès septembre)
      const comparatif = [];
      const choisirCombo = (ec, valeur) => { const c = ec.root.querySelector('[role=combobox], .combo, button[aria-haspopup]'); return c; };
      async function jouerComparatif(profil, patientValeur, examen, choixA, choixB) {
        session(profil.s);
        const ec = await monter('m5-resultats-comparatif');
        const cas = { profil: profil.nom, session: profil.s, patient: patientValeur, examen, notes: notes(ec.root), vide: texte(ec.root.querySelector('p.text-sm.font-medium.text-slate-700')) };
        cas.options = { patients: [], examens: [] };
        const cmb = ec.root.querySelector('.combo');
        if (cmb) cas.options.patients = cmb.options().map((o) => ({ value: o.value, libelle: o.label }));
        if (cmb && patientValeur) {
          cmb.value = patientValeur; cmb.dispatchEvent(new Event('change')); await dormir(40);
          cas.options.examens = [...ec.root.querySelectorAll('select')[0].options].map((o) => ({ value: o.value, libelle: o.textContent }));
          cas.videApresPatient = texte(ec.root.querySelector('p.text-sm.font-medium.text-slate-700'));
          if (examen) {
            const se = ec.root.querySelectorAll('select')[0];
            se.value = examen; se.dispatchEvent(new Event('change')); await dormir(40);
            cas.videApresExamen = texte(ec.root.querySelector('p.text-sm.font-medium.text-slate-700'));
            const deux = ec.root.querySelectorAll('select');
            if (deux.length >= 3) {
              cas.choixPossibles = [...deux[1].options].map((o) => ({ value: o.value, libelle: o.textContent }));
              cas.parDefaut = { a: deux[1].value, b: deux[2].value };
              if (choixA != null) { deux[1].value = String(choixA); deux[1].dispatchEvent(new Event('change')); }
              if (choixB != null) { deux[2].value = String(choixB); deux[2].dispatchEvent(new Event('change')); }
              await dormir(40);
              cas.choisi = { a: deux[1].value, b: deux[2].value };
              cas.entetes = [...ec.root.querySelectorAll('table thead th')].map(texte);
              cas.lignes = [...ec.root.querySelectorAll('table tbody tr')].map((tr) => ({ cellules: [...tr.querySelectorAll('td')].map(texte), gras: [...tr.querySelectorAll('td span')].map((s) => s.className.includes('font-bold')) }));
              cas.noteEvolution = texte([...ec.root.querySelectorAll('div')].filter((e) => e.className.includes('bg-info-50')).pop());
            }
          }
        }
        comparatif.push(cas);
        ec.demonter();
      }
      const toutes = { nom: 'direction', s: { role: 'direction', fonction: 'direction', id: 'AG8', nom: 'DIR TEST' } };
      await jouerComparatif(toutes, null, null);
      await jouerComparatif(toutes, 'PX1', 'NFS');
      await jouerComparatif(toutes, 'PX1', 'NFS', 0, 2);
      await jouerComparatif(toutes, 'PX1', 'NFS', 1, 2);
      await jouerComparatif(toutes, 'PX2', 'GLYAJ');
      await jouerComparatif(toutes, 'PX2', 'NFS');
      await jouerComparatif(profilsEcran[1], null, null);
      await jouerComparatif(profilsEcran[2], null, null);
      await jouerComparatif(profilsEcran[0], 'PX3', null);

      /* ===== 10. m5-stats ===== */
      colD.all().forEach((r) => { r.statut = 'archive'; });
      colPl.all().forEach((r) => { r.statut = 'archive'; });
      const pat = (id, sexe, naiss) => colP.insert({ id, nom: 'ST' + id, prenom: 'Stat', code: 'CNT/' + id + '/26', sexe, dateNaissance: naiss }).record;
      pat('SP1', 'F', '1990-05-01'); pat('SP2', 'M', '2020-03-01'); pat('SP3', 'M', '1950-01-01'); pat('SP4', 'F', null);
      const sd = (o) => poserDemande(Object.assign({ etatAnalyse: 'valide' }, o));
      sd({ patientId: 'SP1', patient: 'ST Stat', dateHeure: '2026-08-03T09:00:00.000Z', serviceDemandeur: 'Maternité', urgent: true, origineDemande: 'externe' });
      sd({ patientId: 'SP1', patient: 'ST Stat', dateHeure: '2026-08-04T09:00:00.000Z', serviceDemandeur: 'Maternité', analyse: 'GLYCEMIE', examenCode: 'GLY' });
      sd({ patientId: 'SP2', patient: 'ST Stat', dateHeure: '2026-08-04T10:00:00.000Z', serviceDemandeur: 'Médecine', etatAnalyse: 'en_attente' });
      sd({ patientId: 'SP3', patient: 'ST Stat', dateHeure: '2026-08-10T10:00:00.000Z', serviceDemandeur: 'Médecine', urgent: true, analyse: 'GLYCEMIE', examenCode: 'GLY', origineDemande: 'externe' });
      sd({ patientId: 'SP4', patient: 'ST Stat', dateHeure: '2026-08-20T10:00:00.000Z', analyse: 'EXAMEN INCONNU DU CATALOGUE', examenCode: undefined, analyseCode: 'ZZ' });
      sd({ patientId: 'SP1', patient: 'ST Stat', dateHeure: '2026-07-15T10:00:00.000Z', serviceDemandeur: 'Médecine et spécialité' });
      sd({ patientId: 'SP9', patient: 'ST Stat', dateHeure: '2026-08-05T10:00:00.000Z', serviceDemandeur: 'Hospitalisation et soins', etatAnalyse: 'rectifie' });
      entrees.stats = { demandes: instantane(colD), patients: instantane(colP).filter((p) => /^SP/.test(p.id)) };
      const stats = [];
      const enregistrer = (obj, nom) => { const o = obj[nom]; obj[nom] = function () { jeux.push({ fn: nom, a: propre([...arguments].slice(0, 2).map((x) => (x && x.nodeType ? null : x))) }); return o.apply(this, arguments); }; return () => { obj[nom] = o; }; };
      let jeux = [];
      const restaurer = [enregistrer(G, 'camembert'), enregistrer(G, 'barres'), enregistrer(G, 'anneau'), enregistrer(G, 'ligne'), enregistrer(K, 'ranking')];
      const oTab = P.tableau; P.tableau = function (cols, lg, opts) { jeux.push({ fn: 'tableau', cols: cols.map((c) => c.label), lignes: propre(lg), opts: propre(opts) }); return oTab.apply(this, arguments); };
      const oEtat = P.etat; P.etat = function (o) { jeux.push({ fn: 'etat', titre: o.titre, sousTitre: o.sousTitre, cartouche: propre(o.cartouche), signatures: propre(o.signatures) }); return oEtat.apply(this, arguments); };
      async function jouerStats(nom, filtres) {
        session(toutes.s);
        jeux = [];
        const ec = await monter('m5-stats');
        const champ = (i) => ec.root.querySelectorAll('select, input[type=date]')[i];
        const selects = [...ec.root.querySelectorAll('select')], dates = [...ec.root.querySelectorAll('input[type=date]')];
        const pose = (e, v) => { e.value = v; e.dispatchEvent(new Event('change')); };
        if (filtres.periode) pose(selects[0], filtres.periode);
        if (filtres.du !== undefined) pose(dates[0], filtres.du);
        if (filtres.au !== undefined) pose(dates[1], filtres.au);
        await dormir(30);
        if (filtres.section !== undefined) pose(selects[1], filtres.section);
        if (filtres.service !== undefined) pose(selects[2], filtres.service);
        if (filtres.origine !== undefined) pose(selects[3], filtres.origine);
        if (filtres.sexe !== undefined) pose(selects[4], filtres.sexe);
        await dormir(40);
        jeux.length = 0;
        [...ec.root.querySelectorAll('button')].find((b) => texte(b) === 'Appliquer').click();
        await dormir(50);
        const rendu = jeux.slice();
        const cas = { nom, filtres, options: selects.map((s) => [...s.options].map((o) => ({ value: o.value, libelle: o.textContent }))), kpis: kpis(ec.root), tableau: lignes(ec.root).map((l) => l.cellules),
          titreTableau: texte([...ec.root.querySelectorAll('.card-title')].pop()), cartes: [...ec.root.querySelectorAll('.card-title')].map(texte), vide: texte(ec.root.querySelector('p.text-sm.font-medium.text-slate-700')),
          graphiques: rendu.filter((j) => j.fn !== 'tableau' && j.fn !== 'etat') };
        if (filtres.imprimer) {
          jeux.length = 0;
          [...ec.root.querySelectorAll('button')].find((b) => texte(b) === 'Imprimer l’état').click();
          await dormir(80);
          cas.impression = jeux.slice();
        }
        stats.push(cas);
        ec.demonter();
      }
      const base = { periode: 'libre', du: '2026-08-01', au: '2026-08-31' };
      await jouerStats('août entier', Object.assign({ imprimer: true }, base));
      await jouerStats('juillet à août', Object.assign({}, base, { du: '2026-07-01' }));
      await jouerStats('service Maternité', Object.assign({}, base, { service: 'Maternité' }));
      await jouerStats('origine externe', Object.assign({}, base, { origine: 'externe' }));
      await jouerStats('origine interne', Object.assign({}, base, { origine: 'interne' }));
      await jouerStats('sexe féminin', Object.assign({}, base, { sexe: 'F' }));
      await jouerStats('sexe masculin', Object.assign({}, base, { sexe: 'M' }));
      await jouerStats('section hématologie', Object.assign({}, base, { section: 'hematologie' }));
      await jouerStats('période sans examen', { periode: 'libre', du: '2026-01-01', au: '2026-01-31' });
      await jouerStats('bornes inversées', { periode: 'libre', du: '2026-08-31', au: '2026-08-01' });
      await jouerStats('semaine glissante (jours libres)', { periode: 'semaine' });
      const constantes = { periodes: [], tranches: null };
      restaurer.forEach((f) => f()); P.tableau = oTab; P.etat = oEtat;

      return { saisie, entrees, etats, toutesCapacites, roleFonction, capacites, visibilite, continuite, verrous, plages, resultats, refs, impression: { cas: impression, poses: reglementsPoses }, comparatif, stats, nbSections: L.SECTIONS.length,
        sections: propre(L.SECTIONS), services: propre(L.SERVICES_DEMANDEURS), origines: propre(L.ORIGINES_PATIENT), motifs: propre(L.MOTIFS_COMMENTAIRE_GENERAL), types: propre(L.TYPES_VARIABLE) };
    });
    console.log('  états : ' + sortie.etats.liste.length + ' · capacités : ' + sortie.capacites.length + ' · visibilité : ' + sortie.visibilite.length + ' · continuité : ' + sortie.continuite.length
      + ' · gestes : ' + sortie.verrous.length + ' · plages : ' + sortie.plages.cas.length + '+' + sortie.plages.ecarts.length + ' · écrans résultats : ' + sortie.resultats.length
      + ' · impression : ' + sortie.impression.cas.length + ' · comparatif : ' + sortie.comparatif.length + ' · stats : ' + sortie.stats.length);
    sortie.verrous.forEach((v) => console.log('  ' + v.nom + ' → ' + (v.erreur ? 'REFUS ' + v.erreur.slice(0, 60) : v.apres.etatAnalyse + ' v' + (v.apres.version || 1) + ' notif ' + v.notifications.length)));
    ecrire('packages/domaine/test/vecteurs/resultats.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-resultats.js — moteurs et écrans du laboratoire (résultats). Ne pas éditer.', ...sortie });
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
