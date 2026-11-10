/* =============================================================================
 * VECTEURS DU PLANNING RH (lots L4 à L6, 10/11/2026) : SIGH.planningRh, le moteur de la maquette, PILOTÉ dans Chrome
 * -----------------------------------------------------------------------------
 * Décisions de la Direction du 09/11/2026 : le régime individuel déroge champ par champ (versions datées immuables), le circuit de validation des présences,
 * congés et ordres de mission est un réglage (surveillant seul par défaut), l'agent propose et le surveillant valide. Chaque cas pose son état au magasin
 * (agents réels du jeu, régimes de la catégorie, versions individuelles, planning, pièces), appelle le moteur de la maquette et enregistre ce qu'il rend :
 * résolution du régime à une date, refus nommés (code, motif, geste) d'une dérogation, contrôle de repos, décision du circuit et patch écrit, contrôle des
 * propositions. Le domaine Dart (`packages/domaine/lib/src/rh/planning_rh.dart`) rejoue chaque cas sur les MÊMES entrées.
 * L'horloge est posée au 30/10/2026 (la date que les tests du poste utilisent) : le moteur lit « aujourd'hui » à chaque appel.
 *   node build/vecteurs-planning-rh.js   →   packages/domaine/test/vecteurs/planning_rh.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du planning RH (L4 à L6)');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      /* L'horloge : 30/10/2026, midi. */
      const Reel = window.Date;
      const decalage = new Reel(2026, 9, 30, 12, 0, 0).getTime() - Reel.now();
      const maintenant = () => Reel.now() + decalage;
      function Decalee() {
        if (!(this instanceof Decalee)) return String(new Reel(maintenant()));
        if (arguments.length === 0) return new Reel(maintenant());
        return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))();
      }
      Decalee.prototype = Reel.prototype; Decalee.now = maintenant; Decalee.UTC = Reel.UTC; Decalee.parse = Reel.parse;
      window.Date = Decalee;

      const S = SIGH.store, R = SIGH.planningRh, C = SIGH.core;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const sess0 = S.session();
      const seConnecter = (role, nom) => S.setSession(Object.assign({}, sess0, { role: role, nom: nom, nomComplet: nom }));
      const personnel = S.collection('personnel').active();
      const med = personnel.filter((e) => e.fonction === 'medecin');
      const inf = personnel.filter((e) => e.fonction === 'infirmier');
      const sf = personnel.filter((e) => e.fonction === 'sage_femme');
      const agents = [med[0], med[1], inf[0], sf[0]].map((e) => ({ id: e.id, nomComplet: e.nomComplet, fonction: e.fonction, matricule: e.matricule, service: e.service }));
      const [A, B, I, F] = agents;
      const regimesActifs = propre(S.collection('regimesTravail').active());

      /* --- l'état de départ : ni version individuelle, ni planning des agents de sonde, ni pièce --------------------------------------------------------- */
      const raw = S.raw();
      raw.regimesIndividuels = [];
      raw.planning = raw.planning.filter((p) => agents.every((a) => a.id !== p.employeId));
      raw.propositionsPlanning = [];
      const AUJ = '2026-10-30';
      const V = (employeId, dateEffet, champs, retour) => ({ id: 'RGI-' + employeId + '-' + dateEffet, statut: 'actif', employeId: employeId, dateEffet: dateEffet, champs: champs || {}, retourCategorie: retour === true, motif: 'vecteur', creePar: 'vecteur', creeLe: AUJ });
      const poserVersions = (versions) => { raw.regimesIndividuels = propre(versions); };
      const vac = (id, agent, date, type) => ({ id: id, statut: 'actif', employeId: agent.id, employe: agent.nomComplet, fonction: agent.fonction, service: agent.service, date: date, type: type });
      const poserPlanning = (liste) => { raw.planning = raw.planning.filter((p) => agents.every((a) => a.id !== p.employeId)).concat(propre(liste)); };

      /* ===== 1. le régime en vigueur à une date ============================================================================================================== */
      const casRegime = [
        { nom: 'sans version : la catégorie des médecins', agent: A, versions: [], date: '2026-11-10' },
        { nom: 'version à venir : pas encore en vigueur', agent: A, versions: [V(A.id, '2026-11-05', { repos: 'repos24', honoraire: 20000 })], date: '2026-11-04' },
        { nom: 'version atteinte le jour même : repos 24 h et honoraire, le reste de la catégorie', agent: A, versions: [V(A.id, '2026-11-05', { repos: 'repos24', honoraire: 20000 })], date: '2026-11-05' },
        { nom: 'retour à la catégorie : la dérogation s’arrête', agent: A, versions: [V(A.id, '2026-11-05', { repos: 'repos24' }), V(A.id, '2026-12-01', {}, true)], date: '2026-12-02' },
        { nom: 'entre la dérogation et le retour', agent: A, versions: [V(A.id, '2026-11-05', { repos: 'repos24' }), V(A.id, '2026-12-01', {}, true)], date: '2026-11-30' },
        { nom: '« aucun » repos : le repos codifié disparaît', agent: A, versions: [V(A.id, '2026-11-05', { repos: 'aucun' })], date: '2026-11-06' },
        { nom: 'vacations et cycle dérogés, honoraire de la catégorie conservé', agent: A, versions: [V(A.id, '2026-11-05', { vacations: ['garde', 'permanence'], cycle: 4, honorairePeriodicite: 'occurrence' })], date: '2026-11-06' },
        { nom: 'une version pose les champs dérogés, la suivante les REMPLACE (pas de cumul)', agent: A, versions: [V(A.id, '2026-11-05', { repos: 'repos24', honoraire: 20000 }), V(A.id, '2026-11-20', { cycle: 5 })], date: '2026-11-21' },
        { nom: 'les versions d’un autre agent ne comptent pas', agent: B, versions: [V(A.id, '2026-11-05', { repos: 'repos24' })], date: '2026-11-10' },
        { nom: 'infirmier sans dérogation', agent: I, versions: [], date: '2026-11-10' },
        { nom: 'sage-femme sans dérogation (repos 24 h de la catégorie)', agent: F, versions: [], date: '2026-11-10' },
      ].map((c) => {
        poserVersions(c.versions);
        return { nom: c.nom, fonction: c.agent.fonction, versions: propre(c.versions.filter((v) => v.employeId === c.agent.id)), date: c.date, attendu: propre(R.regimeALaDate(c.agent.id, c.agent.fonction, c.date)) };
      });
      /* fonction inconnue : aucun régime, rien d'inventé */
      poserVersions([]);
      casRegime.push({ nom: 'fonction sans régime : rien d’inventé', fonction: 'fonction_inconnue', versions: [], date: '2026-11-10', attendu: propre(R.regimeALaDate(A.id, 'fonction_inconnue', '2026-11-10')) });

      /* ===== 2. la pose d'une dérogation : refus nommés ====================================================================================================== */
      const derog = (o) => {
        const avant = raw.regimesIndividuels.length;
        seConnecter(o.role || 'admin', 'Vecteur ' + (o.role || 'admin'));
        poserVersions(o.versions || []);
        const n0 = raw.regimesIndividuels.length;
        const r = R.deroger({ employeId: o.employeId || A.id, dateEffet: o.dateEffet, champs: o.champs, retourCategorie: o.retour === true, motif: o.motif });
        const cas = { nom: o.nom, role: o.role || 'admin', versions: propre(o.versions || []), dateEffet: o.dateEffet === undefined ? null : o.dateEffet, champs: propre(o.champs || {}), retour: o.retour === true, motif: o.motif === undefined ? null : o.motif,
          agentExiste: (o.employeId || A.id) === A.id };
        if (r.ok) {
          const f = raw.regimesIndividuels[0];
          cas.attendu = { ok: true, champs: propre(f.champs), retourCategorie: f.retourCategorie, version: f.version };
        } else {
          cas.attendu = { ok: false, code: r.code, motif: r.motif, geste: r.geste };
        }
        void avant; void n0;
        return cas;
      };
      const casDeroger = [
        derog({ nom: 'repos 24 h et honoraire', dateEffet: AUJ, champs: { repos: 'repos24', honoraire: 20000 }, motif: 'Vecteur' }),
        derog({ nom: 'date à venir, vacations et cycle', dateEffet: '2026-11-15', champs: { vacations: ['garde', 'permanence'], cycle: 4 }, motif: 'Vecteur' }),
        derog({ nom: 'honoraire à zéro et périodicité', dateEffet: AUJ, champs: { honoraire: 0, honorairePeriodicite: 'occurrence' }, motif: 'Vecteur' }),
        derog({ nom: 'retour à la catégorie (aucun champ requis)', dateEffet: '2026-11-15', champs: {}, retour: true, motif: 'Vecteur', versions: [V(A.id, AUJ, { repos: 'repos24' })] }),
        derog({ nom: 'rôle caissier', role: 'caissier', dateEffet: AUJ, champs: { repos: 'repos24' }, motif: 'Vecteur' }),
        derog({ nom: 'rôle surveillant', role: 'surveillant', dateEffet: AUJ, champs: { repos: 'repos24' }, motif: 'Vecteur' }),
        derog({ nom: 'rôle DAF', role: 'da', dateEffet: AUJ, champs: { repos: 'repos48' }, motif: 'Vecteur' }),
        derog({ nom: 'date illisible', dateEffet: '30/10/2026', champs: { repos: 'repos24' }, motif: 'Vecteur' }),
        derog({ nom: 'date absente', dateEffet: '', champs: { repos: 'repos24' }, motif: 'Vecteur' }),
        derog({ nom: 'motif absent', dateEffet: AUJ, champs: { repos: 'repos24' }, motif: '   ' }),
        derog({ nom: 'date passée', dateEffet: '2026-10-29', champs: { repos: 'repos24' }, motif: 'Vecteur' }),
        derog({ nom: 'aucun champ dérogé', dateEffet: AUJ, champs: {}, motif: 'Vecteur' }),
        derog({ nom: 'champs vides ne dérogent pas', dateEffet: AUJ, champs: { repos: '', cycle: '', honoraire: null, vacations: [] }, motif: 'Vecteur' }),
        derog({ nom: 'repos inconnu', dateEffet: AUJ, champs: { repos: 'repos12' }, motif: 'Vecteur' }),
        derog({ nom: 'cycle nul', dateEffet: AUJ, champs: { cycle: 0 }, motif: 'Vecteur' }),
        derog({ nom: 'cycle décimal', dateEffet: AUJ, champs: { cycle: 2.5 }, motif: 'Vecteur' }),
        derog({ nom: 'honoraire négatif', dateEffet: AUJ, champs: { honoraire: -1 }, motif: 'Vecteur' }),
        derog({ nom: 'périodicité inconnue', dateEffet: AUJ, champs: { honorairePeriodicite: 'annuelle' }, motif: 'Vecteur' }),
        derog({ nom: 'vacations hors référentiel (un repos n’est pas une vacation travaillée)', dateEffet: AUJ, champs: { vacations: ['repos24'] }, motif: 'Vecteur' }),
        derog({ nom: 'date déjà prise par une version', dateEffet: '2026-11-05', champs: { cycle: 3 }, motif: 'Vecteur', versions: [V(A.id, '2026-11-05', { repos: 'repos24' })] }),
        derog({ nom: 'version insérée avant la plus récente', dateEffet: '2026-11-10', champs: { cycle: 3 }, motif: 'Vecteur', versions: [V(A.id, '2026-12-01', { repos: 'repos24' })] }),
      ];

      /* ===== 3. le contrôle de repos et de double affectation ====================================================================================================== */
      const controle = (o) => {
        poserVersions(o.versions || []);
        poserPlanning(o.planning || []);
        const r = R.controlerVacation({ employeId: o.agent.id, date: o.date, type: o.type, ignoreId: o.ignoreId });
        return { nom: o.nom, agent: o.agent, versions: propre(o.versions || []), planning: propre(o.planning || []), date: o.date, type: o.type, ignoreId: o.ignoreId || null,
          attendu: r.ok ? { ok: true, individuel: r.regime.individuel, repos: r.regime.repos } : { ok: false, code: r.code, motif: r.motif, geste: r.geste, reposHeures: r.reposHeures === undefined ? null : r.reposHeures, individuel: r.individuel === undefined ? null : r.individuel, autre: r.autre || r.existante || null, date: r.date || null } };
      };
      const g = (id, ag, d, t) => vac(id, ag, d, t || 'garde');
      const casControle = [
        controle({ nom: 'médecin : garde la veille, repos de 48 h', agent: A, planning: [g('P1', A, '2026-11-09')], date: '2026-11-10', type: 'garde' }),
        controle({ nom: 'médecin : garde deux jours avant, repos de 48 h', agent: A, planning: [g('P1', A, '2026-11-10')], date: '2026-11-12', type: 'garde' }),
        controle({ nom: 'médecin : garde trois jours avant, repos respecté', agent: A, planning: [g('P1', A, '2026-11-10')], date: '2026-11-13', type: 'garde' }),
        controle({ nom: 'médecin : garde deux jours APRÈS, le repos serait entamé', agent: A, planning: [g('P1', A, '2026-11-10')], date: '2026-11-08', type: 'garde' }),
        controle({ nom: 'médecin : garde la veille de la suivante, repos entamé', agent: A, planning: [g('P1', A, '2026-11-10')], date: '2026-11-09', type: 'garde' }),
        controle({ nom: 'garde hospitalisation après une garde', agent: A, planning: [g('P1', A, '2026-11-09')], date: '2026-11-10', type: 'garde_hospi' }),
        controle({ nom: 'dérogation de repos 24 h : garde à J+2 acceptée', agent: A, versions: [V(A.id, '2026-11-01', { repos: 'repos24' })], planning: [g('P1', A, '2026-11-10')], date: '2026-11-12', type: 'garde' }),
        controle({ nom: 'dérogation de repos 24 h : garde à J+1 refusée', agent: A, versions: [V(A.id, '2026-11-01', { repos: 'repos24' })], planning: [g('P1', A, '2026-11-10')], date: '2026-11-11', type: 'garde' }),
        controle({ nom: 'dérogation pas encore en vigueur à la date : le repos de la catégorie s’applique', agent: A, versions: [V(A.id, '2026-12-01', { repos: 'repos24' })], planning: [g('P1', A, '2026-11-10')], date: '2026-11-12', type: 'garde' }),
        controle({ nom: 'dérogation « aucun repos » : le contrôle retombe sur un jour', agent: A, versions: [V(A.id, '2026-11-01', { repos: 'aucun' })], planning: [g('P1', A, '2026-11-10')], date: '2026-11-11', type: 'garde' }),
        controle({ nom: 'sage-femme : repos de 24 h de la catégorie', agent: F, planning: [g('P1', F, '2026-11-10')], date: '2026-11-12', type: 'garde' }),
        controle({ nom: 'les gardes d’un autre agent ne comptent pas', agent: A, planning: [g('P1', B, '2026-11-09')], date: '2026-11-10', type: 'garde' }),
        controle({ nom: 'double affectation le même jour', agent: A, planning: [g('P1', A, '2026-11-10', 'permanence')], date: '2026-11-10', type: 'garde' }),
        controle({ nom: 'on remplace sa propre vacation : ignoreId la met de côté', agent: A, planning: [g('P1', A, '2026-11-10')], date: '2026-11-10', type: 'garde', ignoreId: 'P1' }),
        controle({ nom: 'une garde soins ne déclenche pas le repos', agent: I, planning: [g('P1', I, '2026-11-09', 'garde_soins')], date: '2026-11-10', type: 'garde_soins' }),
        controle({ nom: 'une permanence après une garde n’est pas contrôlée', agent: A, planning: [g('P1', A, '2026-11-09')], date: '2026-11-10', type: 'permanence' }),
        controle({ nom: 'type inconnu', agent: A, date: '2026-11-10', type: 'sieste' }),
        controle({ nom: 'date illisible', agent: A, date: '10/11/2026', type: 'garde' }),
      ];

      /* ===== 4. le circuit de validation =============================================================================================================================== */
      const cEtat = [
        { nom: 'pointage sans état : validé (avant le circuit)', coll: 'presences', rec: {} },
        { nom: 'pointage à valider', coll: 'presences', rec: { validationEtat: 'a_valider' } },
        { nom: 'pointage validé par le surveillant, DAF attendue', coll: 'presences', rec: { validationEtat: 'valide_surveillant' } },
        { nom: 'pointage refusé', coll: 'presences', rec: { validationEtat: 'refuse' } },
        { nom: 'congé en attente, sans état : à valider', coll: 'conges', rec: { statutConge: 'en_attente' } },
        { nom: 'congé accordé, sans état : validé', coll: 'conges', rec: { statutConge: 'valide' } },
        { nom: 'congé refusé, sans état : refusé', coll: 'conges', rec: { statutConge: 'refuse' } },
        { nom: 'congé en attente mais état explicite validé : l’état explicite l’emporte', coll: 'conges', rec: { statutConge: 'en_attente', validationEtat: 'valide' } },
        { nom: 'mission à valider, sans état', coll: 'missions', rec: { statutMission: 'a_valider' } },
        { nom: 'mission en projet, sans état : pas validée', coll: 'missions', rec: { statutMission: 'projet' } },
        { nom: 'mission en cours, sans état : validée', coll: 'missions', rec: { statutMission: 'en_cours' } },
        { nom: 'mission refusée, sans état', coll: 'missions', rec: { statutMission: 'refusee' } },
      ].map((c) => ({ nom: c.nom, collection: c.coll, rec: c.rec, attendu: { etat: R.etatValidation(c.coll, c.rec), compte: R.compte(c.coll, c.rec) } }));

      const tr = (o) => {
        S.setReglage('planningCircuitPresences', o.circuit);
        seConnecter(o.role, o.nom || ('Vecteur ' + o.role));
        const col = S.collection(o.collection);
        raw[o.collection] = (raw[o.collection] || []).filter((x) => x.id !== 'PIECE');
        const rec = Object.assign({ id: 'PIECE', statut: 'actif', employeId: A.id, agentId: A.id }, propre(o.rec));
        raw[o.collection].push(rec);
        const avant = propre(rec);
        const r = R.trancher({ collection: o.collection, id: o.id || 'PIECE', decision: o.decision, motif: o.motif });
        const apres = col.get('PIECE');
        const cles = ['etapesFaites', 'validationEtat', 'motifRefus', 'refuseePar', 'refuseeLe', 'circuitUtilise', 'statutConge', 'statutMission', 'validePar', 'valideLe', 'valideePar', 'valideeLe'];
        const patch = {};
        if (r.ok) cles.forEach((k) => { if (JSON.stringify(apres[k]) !== JSON.stringify(avant[k]) && apres[k] !== undefined) patch[k] = propre(apres[k]); });
        raw[o.collection] = raw[o.collection].filter((x) => x.id !== 'PIECE');
        const moi = S.collection('personnel').active().filter((e) => e.nomComplet === (o.nom || ('Vecteur ' + o.role)))[0] || null;
        return { nom: o.nom_cas, collection: o.collection, circuit: o.circuit, role: o.role, acteur: o.nom || ('Vecteur ' + o.role), moiId: moi ? moi.id : null, moiNom: moi ? moi.nomComplet : null,
          rec: propre(o.rec), decision: o.decision, motif: o.motif === undefined ? null : o.motif, id: o.id || 'PIECE',
          attendu: r.ok ? { ok: true, etat: r.etat, etape: r.etape, complet: r.complet, patch: patch } : { ok: false, code: r.code, motif: r.motif, geste: r.geste, etape: r.etape || null } };
      };
      const pres = { etat: 'retard', date: '2026-10-29' };
      const prem = { etapesFaites: [{ etape: 'surveillant', par: 'S1', role: 'surveillant', le: '2026-10-29', decision: 'valide', motif: null }], validationEtat: 'valide_surveillant' };
      const casCircuit = [
        tr({ nom_cas: 'surveillant seul : le surveillant valide', circuit: 'surveillant', role: 'surveillant', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'surveillant seul : l’administrateur valide aussi', circuit: 'surveillant', role: 'admin', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'surveillant seul : la DAF est refusée', circuit: 'surveillant', role: 'da', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'surveillant seul : le caissier est refusé', circuit: 'surveillant', role: 'caissier', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'DAF seule : la DAF valide', circuit: 'daf', role: 'da', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'DAF seule : le surveillant est refusé', circuit: 'daf', role: 'surveillant', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'deux étapes : le surveillant signe la première, la pièce n’est pas complète', circuit: 'surveillant_puis_daf', role: 'surveillant', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'deux étapes : la DAF ne signe pas la première', circuit: 'surveillant_puis_daf', role: 'da', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'deux étapes : la DAF achève', circuit: 'surveillant_puis_daf', role: 'da', collection: 'presences', rec: Object.assign({}, pres, prem), decision: 'valider' }),
        tr({ nom_cas: 'deux étapes : le surveillant ne signe pas la seconde', circuit: 'surveillant_puis_daf', role: 'surveillant', nom: 'Vecteur autre surveillant', collection: 'presences', rec: Object.assign({}, pres, prem), decision: 'valider' }),
        tr({ nom_cas: 'deux étapes : la même personne ne signe pas deux étapes', circuit: 'surveillant_puis_daf', role: 'admin', nom: 'S1', collection: 'presences', rec: Object.assign({}, pres, prem), decision: 'valider' }),
        tr({ nom_cas: 'circuit changé en cours de route : la pièce à mi-circuit se complète', circuit: 'surveillant', role: 'surveillant', nom: 'Vecteur autre surveillant', collection: 'presences', rec: Object.assign({}, pres, prem), decision: 'valider' }),
        tr({ nom_cas: 'refus sans motif', circuit: 'surveillant', role: 'surveillant', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'refuser' }),
        tr({ nom_cas: 'refus avec motif', circuit: 'surveillant', role: 'surveillant', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'refuser', motif: 'Pointage contesté' }),
        tr({ nom_cas: 'décision inconnue', circuit: 'surveillant', role: 'surveillant', collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'peut-etre' }),
        tr({ nom_cas: 'pièce déjà validée', circuit: 'surveillant', role: 'surveillant', collection: 'presences', rec: Object.assign({ validationEtat: 'valide' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'pointage d’avant le circuit : validé, ne se retranche pas', circuit: 'surveillant', role: 'surveillant', collection: 'presences', rec: pres, decision: 'valider' }),
        tr({ nom_cas: 'pièce déjà refusée', circuit: 'surveillant', role: 'surveillant', collection: 'presences', rec: Object.assign({ validationEtat: 'refuse' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'pièce introuvable', circuit: 'surveillant', role: 'surveillant', collection: 'presences', rec: pres, decision: 'valider', id: 'ABSENTE' }),
        tr({ nom_cas: 'collection inconnue', circuit: 'surveillant', role: 'surveillant', collection: 'factures', rec: { numero: 'X' }, decision: 'valider' }),
        tr({ nom_cas: 'nul ne valide sa propre pièce', circuit: 'surveillant', role: 'surveillant', nom: A.nomComplet, collection: 'presences', rec: Object.assign({ validationEtat: 'a_valider' }, pres), decision: 'valider' }),
        tr({ nom_cas: 'congé en attente (avant le circuit) : le surveillant accorde', circuit: 'surveillant', role: 'surveillant', collection: 'conges', rec: { statutConge: 'en_attente', dateDebut: '2026-11-02' }, decision: 'valider' }),
        tr({ nom_cas: 'congé : refus avec motif', circuit: 'surveillant', role: 'surveillant', collection: 'conges', rec: { statutConge: 'en_attente' }, decision: 'refuser', motif: 'Période de forte activité' }),
        tr({ nom_cas: 'congé déjà accordé', circuit: 'surveillant', role: 'surveillant', collection: 'conges', rec: { statutConge: 'valide' }, decision: 'valider' }),
        tr({ nom_cas: 'mission sans avis du chef de service', circuit: 'surveillant', role: 'surveillant', collection: 'missions', rec: { statutMission: 'a_valider' }, decision: 'valider' }),
        tr({ nom_cas: 'mission avec avis favorable : validée', circuit: 'surveillant', role: 'surveillant', collection: 'missions', rec: { statutMission: 'a_valider', avisChefService: { avis: 'favorable', chef: 'Chef', motif: null, le: '2026-10-29', consignePar: 'x' } }, decision: 'valider' }),
        tr({ nom_cas: 'mission avec avis défavorable, validée sans motif', circuit: 'surveillant', role: 'surveillant', collection: 'missions', rec: { statutMission: 'a_valider', avisChefService: { avis: 'defavorable', chef: 'Chef', motif: 'Charge', le: '2026-10-29', consignePar: 'x' } }, decision: 'valider' }),
        tr({ nom_cas: 'mission avec avis défavorable, validée avec motif', circuit: 'surveillant', role: 'surveillant', collection: 'missions', rec: { statutMission: 'a_valider', avisChefService: { avis: 'defavorable', chef: 'Chef', motif: 'Charge', le: '2026-10-29', consignePar: 'x' } }, decision: 'valider', motif: 'Mission indispensable' }),
        tr({ nom_cas: 'mission en projet : pas soumise', circuit: 'surveillant', role: 'surveillant', collection: 'missions', rec: { statutMission: 'projet', avisChefService: { avis: 'favorable', chef: 'Chef', le: '2026-10-29', consignePar: 'x' } }, decision: 'valider' }),
        tr({ nom_cas: 'mission refusée sans avis (le refus n’exige que son motif)', circuit: 'surveillant', role: 'surveillant', collection: 'missions', rec: { statutMission: 'a_valider' }, decision: 'refuser', motif: 'Pas de budget' }),
        tr({ nom_cas: 'mission : la DAF ne valide pas en surveillant seul', circuit: 'surveillant', role: 'da', collection: 'missions', rec: { statutMission: 'a_valider', avisChefService: { avis: 'favorable', chef: 'Chef', le: '2026-10-29', consignePar: 'x' } }, decision: 'valider' }),
      ];
      S.setReglage('planningCircuitPresences', 'surveillant');

      /* ===== 5. les propositions de planning =========================================================================================================================== */
      const prop = (o) => {
        poserVersions(o.versions || []);
        poserPlanning(o.planning || []);
        const r = R.controlerProposition(propre(o.proposition));
        return { nom: o.nom, versions: propre(o.versions || []), planning: propre(o.planning || []), proposition: propre(o.proposition),
          attendu: r.ok ? { ok: true } : { ok: false, code: r.code, motif: r.motif, geste: r.geste } };
      };
      const P0 = { type: 'ajout', employeId: A.id, employe: A.nomComplet, date: '2026-11-10', typeVacation: 'garde', motif: 'Vecteur' };
      const casProposition = [
        prop({ nom: 'ajout accepté', proposition: P0 }),
        prop({ nom: 'ajout refusé : repos de 48 h', proposition: P0, planning: [g('P1', A, '2026-11-09')] }),
        prop({ nom: 'ajout refusé : double affectation', proposition: P0, planning: [g('P1', A, '2026-11-10', 'permanence')] }),
        prop({ nom: 'modification acceptée (on déplace sa propre garde)', proposition: { type: 'modification', employeId: A.id, vacationId: 'P1', date: '2026-11-14', typeVacation: 'garde', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10')] }),
        prop({ nom: 'modification : la vacation est celle d’un autre agent', proposition: { type: 'modification', employeId: A.id, vacationId: 'P1', date: '2026-11-14', typeVacation: 'garde', motif: 'Vecteur' }, planning: [g('P1', B, '2026-11-10')] }),
        prop({ nom: 'modification : la vacation n’existe plus', proposition: { type: 'modification', employeId: A.id, vacationId: 'ABSENTE', date: '2026-11-14', typeVacation: 'garde', motif: 'Vecteur' } }),
        prop({ nom: 'modification : repos violé par le nouveau jour', proposition: { type: 'modification', employeId: A.id, vacationId: 'P1', date: '2026-11-13', typeVacation: 'garde', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10'), g('P2', A, '2026-11-15')] }),
        prop({ nom: 'retrait accepté', proposition: { type: 'retrait', employeId: A.id, vacationId: 'P1', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10')] }),
        prop({ nom: 'retrait : vacation d’autrui', proposition: { type: 'retrait', employeId: A.id, vacationId: 'P1', motif: 'Vecteur' }, planning: [g('P1', B, '2026-11-10')] }),
        prop({ nom: 'échange accepté entre deux médecins', proposition: { type: 'echange', employeId: A.id, vacationId: 'P1', contrepartieId: 'P2', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10'), g('P2', B, '2026-11-20')] }),
        prop({ nom: 'échange refusé : même agent', proposition: { type: 'echange', employeId: A.id, vacationId: 'P1', contrepartieId: 'P2', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10'), g('P2', A, '2026-11-20')] }),
        prop({ nom: 'échange refusé : contrepartie disparue', proposition: { type: 'echange', employeId: A.id, vacationId: 'P1', contrepartieId: 'ABSENTE', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10')] }),
        prop({ nom: 'échange refusé : une garde de médecin n’est pas une vacation d’infirmier', proposition: { type: 'echange', employeId: A.id, vacationId: 'P1', contrepartieId: 'P2', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10'), g('P2', I, '2026-11-20', 'garde_soins')] }),
        prop({ nom: 'échange refusé : le collègue enchaînerait deux gardes', proposition: { type: 'echange', employeId: A.id, vacationId: 'P1', contrepartieId: 'P2', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10'), g('P2', B, '2026-11-20'), g('P3', B, '2026-11-11')] }),
        prop({ nom: 'échange accepté avec dérogation de repos 24 h du collègue', proposition: { type: 'echange', employeId: A.id, vacationId: 'P1', contrepartieId: 'P2', motif: 'Vecteur' }, versions: [V(B.id, '2026-11-01', { repos: 'repos24' })], planning: [g('P1', A, '2026-11-10'), g('P2', B, '2026-11-20'), g('P3', B, '2026-11-12')] }),
        prop({ nom: 'type de proposition inconnu', proposition: { type: 'cession', employeId: A.id, vacationId: 'P1', motif: 'Vecteur' }, planning: [g('P1', A, '2026-11-10')] }),
      ];

      const decision = (o) => {
        const p = Object.assign({ id: 'PROP', statut: 'actif', etat: 'proposee', employeId: A.id, type: 'retrait', vacationId: 'P1', motif: 'Vecteur' }, propre(o.proposition || {}));
        raw.propositionsPlanning = o.absente ? [] : [p];
        poserVersions([]); poserPlanning([g('P1', A, '2026-11-10')]);
        seConnecter(o.role, o.nom || ('Vecteur ' + o.role));
        const r = R.trancherProposition({ id: 'PROP', decision: o.decision, motif: o.motif });
        const moi = S.collection('personnel').active().filter((e) => e.nomComplet === (o.nom || ('Vecteur ' + o.role)))[0] || null;
        const ret = { nom: o.nom_cas, role: o.role, decision: o.decision, motif: o.motif === undefined ? null : o.motif, absente: o.absente === true, proposition: propre(o.proposition || {}), moiId: moi ? moi.id : null,
          attendu: r.ok ? { ok: true } : { ok: false, code: r.code, motif: r.motif, geste: r.geste } };
        raw.propositionsPlanning = [];
        return ret;
      };
      const casDecision = [
        decision({ nom_cas: 'le surveillant valide (la décision est permise)', role: 'surveillant', decision: 'valider' }),
        decision({ nom_cas: 'un médecin ne valide pas', role: 'medecin', decision: 'valider' }),
        decision({ nom_cas: 'un caissier ne valide pas', role: 'caissier', decision: 'refuser', motif: 'x' }),
        decision({ nom_cas: 'décision inconnue', role: 'surveillant', decision: 'plus-tard' }),
        decision({ nom_cas: 'refus sans motif', role: 'surveillant', decision: 'refuser' }),
        decision({ nom_cas: 'refus motivé', role: 'surveillant', decision: 'refuser', motif: 'Effectif insuffisant' }),
        decision({ nom_cas: 'déjà validée', role: 'surveillant', decision: 'valider', proposition: { etat: 'validee' } }),
        decision({ nom_cas: 'déjà refusée', role: 'surveillant', decision: 'valider', proposition: { etat: 'refusee' } }),
        decision({ nom_cas: 'retirée par l’agent', role: 'surveillant', decision: 'valider', proposition: { etat: 'annulee' } }),
        decision({ nom_cas: 'proposition introuvable', role: 'surveillant', decision: 'valider', absente: true }),
        decision({ nom_cas: 'nul ne valide sa propre proposition', role: 'surveillant', nom: A.nomComplet, decision: 'valider' }),
      ];

      const visibles = ['surveillant', 'da', 'admin', 'medecin', 'caissier'].map((role) => {
        raw.propositionsPlanning = [
          { id: 'X1', statut: 'actif', etat: 'proposee', employeId: A.id }, { id: 'X2', statut: 'actif', etat: 'proposee', employeId: B.id }, { id: 'X3', statut: 'archive', etat: 'proposee', employeId: A.id },
        ];
        seConnecter(role, A.nomComplet);
        const ids = R.propositionsVisibles().map((x) => x.id);
        const sansAgent = (seConnecter(role, 'Vecteur sans agent'), R.propositionsVisibles().map((x) => x.id));
        raw.propositionsPlanning = [];
        return { role: role, moiId: A.id, avecAgent: ids, sansAgent: sansAgent, actives: [{ id: 'X1', employeId: A.id }, { id: 'X2', employeId: B.id }] };
      });

      seConnecter(sess0.role, sess0.nom);
      return { regimesActifs, agents, regime: casRegime, deroger: casDeroger, controle: casControle, etats: cEtat, circuit: casCircuit, propositions: casProposition, decisions: casDecision, visibles };
    });
    ecrire('packages/domaine/test/vecteurs/planning_rh.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-planning-rh.js : planning RH (régime individuel, circuit de validation, propositions), le moteur de la maquette piloté dans Chrome. Ne pas éditer.' }, sortie));
    ['regime', 'deroger', 'controle', 'etats', 'circuit', 'propositions', 'decisions', 'visibles'].forEach((k) => console.log('  ' + k + ' : ' + sortie[k].length + ' cas'));
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
