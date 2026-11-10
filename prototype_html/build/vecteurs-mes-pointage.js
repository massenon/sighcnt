/* =============================================================================
 * VECTEURS DE L'ESPACE « MES » ET DU POINTAGE PAR BADGE (lots L7 et L8, 10/11/2026) : SIGH.espaceMes et SIGH.pointageBadge, les moteurs de la maquette, PILOTÉS dans Chrome
 * -----------------------------------------------------------------------------
 * Décisions de la Direction du 09/11/2026 : l'espace « Mes » lit les données de l'agent connecté et d'aucun autre (RG-13), la copie de la fiche de paie pour le téléphone ne
 * porte que les pièces émises de l'agent demandeur, « Mon assurance du personnel » dit « non renseigné » sans jamais prendre le prix courant, et le badge sert de pointage
 * (arrivée puis départ à valider, refus nommés, délai en base). Chaque cas pose son monde au magasin (agents, collections), ouvre la session de l'acteur, appelle le moteur de la
 * maquette et enregistre ce qu'il rend. Le domaine Dart (`espace_mes.dart`, `pointage_badge.dart`) rejoue chaque cas sur les MÊMES entrées.
 * L'horloge est posée au 30/10/2026 (la date que les tests du poste utilisent).
 *   node build/vecteurs-mes-pointage.js   →   packages/domaine/test/vecteurs/mes_pointage.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de l’espace « Mes » et du pointage par badge (L7, L8)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m10-rh.js') });
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, E = SIGH.espaceMes, PB = SIGH.pointageBadge, D = SIGH.data;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const sess0 = S.session();
      const seConnecter = (role, nom) => S.setSession(Object.assign({}, sess0, { role: role, nom: nom, nomComplet: nom }));
      const raw = S.raw();
      const pers = S.collection('personnel').active();
      const [A0, B0] = pers.filter((e) => e.fonction === 'infirmier');
      const C0 = pers.filter((e) => e.fonction === 'medecin')[0];
      const ag = (e, o) => Object.assign({ id: e.id, nomComplet: e.nomComplet, matricule: e.matricule, fonction: e.fonction, poste: e.poste, service: e.service, statut: 'actif' }, o || {});
      const A = ag(A0), B = ag(B0), Cm = ag(C0, { poste: null }), Dar = ag(pers.filter((e) => e.fonction === 'aide_soignant')[0], { statut: 'archive' });
      const personnel = [A, B, Cm, Dar];
      raw.personnel = propre(personnel);
      const f = (id, o) => Object.assign({ id: id, statut: 'actif' }, o);
      const archive = (id, o) => f(id, Object.assign({ statut: 'archive' }, o));

      /* ===================================================== L7 : l'espace « Mes » ===================================================== */
      const monde = {
        fichesPoste: [f('FDP1', { intitule: A.poste, rattachement: 'Soins' }), f('FDP2', { intitule: 'Un autre poste', rattachement: 'X' }), archive('FDP3', { intitule: A.poste })],
        bulletins: [f('BA1', { reference: 'BP-A1', employeId: A.id, statutBulletin: 'diffuse' }), f('BA2', { reference: 'BP-A2', employeId: A.id, statutBulletin: 'diffuse' }), f('BA3', { reference: 'BP-A3', employeId: A.id, statutBulletin: 'valide' }),
          f('BA4', { reference: 'BP-A4', employeId: A.id, statutBulletin: 'a_valider' }), archive('BA5', { reference: 'BP-A5', employeId: A.id, statutBulletin: 'diffuse' }), f('BB1', { reference: 'BP-B1', employeId: B.id, statutBulletin: 'diffuse' })],
        contrats: [f('CTA1', { employeId: A.id }), f('CTB1', { employeId: B.id }), archive('CTA2', { employeId: A.id })],
        planning: [f('PLA1', { employeId: A.id, type: 'garde', validationEtat: 'validee' }), f('PLA2', { employeId: A.id, type: 'garde' }), f('PLA3', { employeId: A.id, type: 'garde', validationEtat: 'a_valider' }),
          f('PLA4', { employeId: A.id, type: 'permanence', validationEtat: 'validee' }), f('PLA5', { employeId: A.id, type: 'repos', validationEtat: 'validee' }), f('PLA6', { employeId: A.id, type: 'garde_soins', validationEtat: 'validee' }),
          f('PLB1', { employeId: B.id, type: 'garde', validationEtat: 'validee' }), archive('PLA7', { employeId: A.id, type: 'garde', validationEtat: 'validee' })],
        presences: [f('PRA1', { employeId: A.id, etat: 'present' }), f('PRA2', { employeId: A.id, etat: 'retard', validationEtat: 'a_valider' }), f('PRA3', { employeId: A.id, etat: 'absent', validationEtat: 'valide' }),
          f('PRA4', { employeId: A.id, etat: 'retard', validationEtat: 'valide' }), f('PRB1', { employeId: B.id, etat: 'present' })],
        conges: [f('CGA1', { employeId: A.id }), f('CGB1', { employeId: B.id })],
        missions: [f('OMA1', { agentId: A.id }), f('OMB1', { agentId: B.id }), f('OMA2', { agentId: A.id })],
        evenements: [f('EV1', { beneficiaireId: A.id, portee: 'tous' }), f('EV2', { beneficiaireId: B.id, portee: 'tous' }), f('EV3', { beneficiaireId: Cm.id, portee: 'tous' }), f('EV4', { beneficiaireId: Cm.id, portee: 'tous' })],
        participations: [f('PAR1', { evenementId: 'EV3', employeId: A.id }), f('PAR2', { evenementId: 'EV2', employeId: B.id }), f('PAR3', { evenementId: 'EV1', employeId: B.id })],
        patients: [f('P1', { personnelId: A.id }), f('P2', { personnelId: B.id }), f('P3', {})],
        consultations: [f('CS1', { patientId: 'P1', date: '2026-01-06', tarif: 5000, medecinId: B.id }), f('CS2', { patientId: 'P1', date: '2026-01-07', medecinId: B.id }), f('CS3', { patientId: 'P2', date: '2026-01-08', tarif: 3000, medecinId: A.id }),
          f('CS4', { patientId: 'P3', date: '2026-01-09', tarif: 2000, medecinId: A.id }), f('CS5', { patientId: 'P1', date: '2026-01-10', tarif: '', medecinId: B.id })],
        demandesAnalyses: [f('DA1', { patientId: 'P1', prix: 2000, dateHeure: '2026-01-05T08:00:00' }), f('DA2', { patientId: 'P1', montant: 1500, prix: 2000, dateHeure: '2026-01-11T08:00:00' }), f('DA3', { patientId: 'P1', analyse: D.ANALYSES[0].code, dateHeure: '2026-01-12T08:00:00' }),
          f('DA4', { patientId: 'P1', montant: 0, dateHeure: '2026-01-13T08:00:00' }), f('DA5', { patientId: 'P2', prix: 900, dateHeure: '2026-01-14T08:00:00' })],
        admissions: [f('AD1', { patientId: 'P1', dateEntree: '2026-02-01', montant: 40000 }), f('AD2', { patientId: 'P1', dateEntree: '2026-02-05' })],
      };
      Object.keys(monde).forEach((k) => { raw[k] = propre(monde[k]); });
      const notes = [D.NS131.reference, D.NS132.reference];
      const lecture = (nom, acteur, rubrique) => {
        seConnecter('infirmier', acteur);
        const r = E.lire(rubrique);
        return { nom: nom, acteur: acteur, rubrique: rubrique, attendu: propre(r.ok ? { ok: true, rubrique: r.rubrique, agentId: r.agentId, lectureSeule: r.lectureSeule, ids: r.ids, total: r.total, valeur: r.valeur === undefined ? null : r.valeur,
          sansMontant: r.sansMontant === undefined ? null : r.sansMontant, presents: r.presents === undefined ? null : r.presents, retards: r.retards === undefined ? null : r.retards, absents: r.absents === undefined ? null : r.absents }
          : { ok: false, code: r.code, motif: r.motif, geste: r.geste }) };
      };
      const rubriques = E.RUBRIQUES.map((r) => ({ n: r.n, id: r.id, libelle: r.libelle, ecran: r.ecran, source: r.source || null, lien: r.lien || null, calcule: r.calcule || null, emise: !!r.emise, sensible: !!r.sensible, lectureSeule: !!r.lectureSeule }));
      const lectures = [];
      E.RUBRIQUES.forEach((r) => lectures.push(lecture('agent A : ' + r.libelle, A.nomComplet, r.id)));
      E.RUBRIQUES.forEach((r) => lectures.push(lecture('agent B : ' + r.libelle, B.nomComplet, r.id)));
      ['fiche_poste', 'fiche_paie', 'assurance', 'planning', 'rendez_vous'].forEach((id) => lectures.push(lecture('médecin sans poste ni dossier : ' + id, Cm.nomComplet, id)));
      ['fiche_paie', 'contrat', 'notes_service'].forEach((id) => lectures.push(lecture('compte du poste (non nominatif) : ' + id, 'Poste Accueil 1', id)));
      lectures.push(lecture('rubrique inconnue', A.nomComplet, 'rubrique_fantome'));
      lectures.push(lecture('rubrique inconnue pour un compte non nominatif (la rubrique est jugée d’abord)', 'Poste Accueil 1', 'rubrique_fantome'));

      const copie = (nom, actif, acteur, demande) => {
        S.setReglage('paieCopieTelephone', actif);
        seConnecter('infirmier', acteur);
        const r = demande === undefined ? E.copiePaie() : E.copiePaie({ agentId: demande });
        return { nom: nom, actif: actif, acteur: acteur, agentIdDemande: demande === undefined ? null : demande,
          attendu: propre(r.ok ? { ok: true, agentId: r.agentId, ids: r.ids, references: r.references, total: r.total, chiffree: r.chiffree, recalculee: r.recalculee } : { ok: false, code: r.code, motif: r.motif, geste: r.geste }) };
      };
      const copies = [
        copie('l’agent A, sans préciser : ses deux pièces émises', true, A.nomComplet),
        copie('l’agent A nomme sa propre fiche', true, A.nomComplet, A.id),
        copie('l’agent A demande celle de B : refus nommé', true, A.nomComplet, B.id),
        copie('l’agent B : sa seule pièce émise', true, B.nomComplet),
        copie('un médecin sans pièce émise : copie vide, pas un refus', true, Cm.nomComplet),
        copie('compte non nominatif', true, 'Poste Accueil 1'),
        copie('réglage coupé : refus nommé', false, A.nomComplet),
        copie('réglage coupé, compte non nominatif : le réglage est jugé d’abord', false, 'Poste Accueil 1'),
        copie('la demande d’un autre agent vaut refus même sans pièce', true, Cm.nomComplet, A.id),
      ];
      const reglagesCopie = ['admin', 'da', 'direction', 'medecin', 'surveillant', 'caissier', 'infirmier'].map((role) => {
        seConnecter(role, 'Vecteur ' + role);
        S.setReglage('paieCopieTelephone', true);
        const r = E.definirCopiePaie(false, 'Vecteur');
        const apres = S.reglage('paieCopieTelephone', null);
        S.setReglage('paieCopieTelephone', true);
        return { role: role, attendu: propre(r.ok ? { ok: true, valeur: r.valeur, avant: r.avant, enBase: apres } : { ok: false, code: r.code, motif: r.motif, geste: r.geste, enBase: apres }) };
      });

      /* ===================================================== L8 : le badge sert de pointage ===================================================== */
      const badge = (id, numero, personnelId, o) => f(id, Object.assign({ numero: numero, personnelId: personnelId, matricule: (personnel.filter((e) => e.id === personnelId)[0] || { matricule: '999' }).matricule, agent: 'X', etat: 'remis', expireLe: '2099-12-31' }, o));
      const badges = [badge('BDGA', 'BDG-V0001-2026', A.id), badge('BDGB', 'BDG-V0002-2026', B.id), badge('BDGX', 'BDG-V0003-2026', Cm.id, { expireLe: '2020-01-01' }),
        badge('BDGR', 'BDG-V0004-2026', Cm.id, { etat: 'retire', retireLe: '2026-06-01', motifRetrait: 'Perte' }), badge('BDGN', 'BDG-V0005-2026', Cm.id, { etat: 'a_editer' }),
        badge('BDGZ', 'BDG-V0006-2026', 'EMP-ABSENT', { matricule: '4242' }), badge('BDGD', 'BDG-V0007-2026', Dar.id), badge('BDGE', 'BDG-V0008-2026', B.id, { etat: 'edite' }),
        badge('BDGP', 'BDG-V0009-2026', Cm.id, { etat: 'perdu', retireLe: '2026-07-01', motifRetrait: 'Vol' }), Object.assign(badge('BDGH', 'BDG-V0010-2026', A.id, { etat: 'retire', retireLe: '2026-05-01', motifRetrait: 'Réédition — remplacement' }), { statut: 'archive' })];
      raw.badges = propre(badges);
      const JOUR = '2027-03-01';
      const pres = (id, agent, o) => f(id, Object.assign({ date: JOUR, employeId: agent.id, employe: agent.nomComplet, matricule: agent.matricule, service: agent.service, etat: 'present' }, o));
      const AUJ = '2026-10-30';
      const pointer = (o) => {
        const role = o.role || 'surveillant', nom = 'Vecteur ' + role;
        seConnecter(role, nom);
        S.setReglage('planningBadgeSertDePointage', o.actif !== false);
        S.setReglage('planningBadgeDelaiMinutes', o.delai === undefined ? 5 : o.delai);
        raw.presences = propre(o.presences || []);
        const r = PB.pointer(o.texte, { date: o.jour || JOUR, heure: o.heure });
        const cas = { nom: o.nom, role: role, acteur: nom, actif: o.actif !== false, delai: o.delai === undefined ? 5 : o.delai, texte: o.texte, jour: o.jour || JOUR, heure: o.heure, presences: propre(o.presences || []), aujourdhui: AUJ };
        if (r.ok) {
          const ecrite = raw.presences.filter((p) => p.id === r.presenceId)[0];
          cas.attendu = { ok: true, geste: r.geste, agentId: r.agentId, badgeId: r.badgeId, heure: r.heure, etat: r.etat };
          if (r.geste === 'arrivee') { const c = propre(ecrite); delete c.id; delete c.statut; delete c._creePar; delete c._creeLe; cas.attendu.creation = c; }
          else cas.attendu.patch = { heureDepart: ecrite.heureDepart, departParBadge: ecrite.departParBadge };
        } else {
          cas.attendu = { ok: false, code: r.code, motif: r.motif, geste: r.geste, delai: r.delai === undefined ? null : r.delai };
        }
        return propre(cas);
      };
      const aOuverte = pres('PA1', A, { heureArrivee: '08:00', validationEtat: 'a_valider', etapesFaites: [] });
      const pointages = [
        pointer({ nom: 'première arrivée du jour', texte: 'BDG-V0001-2026', heure: '08:00' }),
        pointer({ nom: 'le code QR complet vaut le numéro saisi', texte: 'CNT-BDG|MAT:' + A.matricule + '|SER:BDG-V0001-2026', heure: '08:00' }),
        pointer({ nom: 'le numéro se lit sans égard à la casse', texte: 'bdg-v0001-2026', heure: '08:00' }),
        pointer({ nom: 'badge « édité » : valable', texte: 'BDG-V0008-2026', heure: '07:45' }),
        pointer({ nom: 'départ sur la présence ouverte', texte: 'BDG-V0001-2026', heure: '17:30', presences: [aOuverte] }),
        pointer({ nom: 'trop rapproché (3 minutes, délai de 5)', texte: 'BDG-V0001-2026', heure: '08:03', presences: [aOuverte] }),
        pointer({ nom: 'à la limite (5 minutes) : passe', texte: 'BDG-V0001-2026', heure: '08:05', presences: [aOuverte] }),
        pointer({ nom: 'délai à 0 : ne refuse jamais', texte: 'BDG-V0001-2026', heure: '08:00', delai: 0, presences: [aOuverte] }),
        pointer({ nom: 'délai à 30 : vingt minutes après, refus', texte: 'BDG-V0001-2026', heure: '08:20', delai: 30, presences: [aOuverte] }),
        pointer({ nom: 'délai à 1 minute : pluriel', texte: 'BDG-V0001-2026', heure: '08:00', delai: 1, presences: [aOuverte] }),
        pointer({ nom: 'journée complète', texte: 'BDG-V0001-2026', heure: '18:00', presences: [Object.assign({}, aOuverte, { heureDepart: '17:00' })] }),
        pointer({ nom: 'présence du jour sans heure d’arrivée (absence déclarée)', texte: 'BDG-V0001-2026', heure: '09:00', presences: [pres('PA2', A, { etat: 'absent', validationEtat: 'a_valider' })] }),
        pointer({ nom: 'départ sur une présence déjà validée', texte: 'BDG-V0001-2026', heure: '17:00', presences: [Object.assign({}, aOuverte, { validationEtat: 'valide' })] }),
        pointer({ nom: 'départ sur une présence d’avant le circuit (sans état : validée)', texte: 'BDG-V0001-2026', heure: '17:00', presences: [(() => { const p = Object.assign({}, aOuverte); delete p.validationEtat; return p; })()] }),
        pointer({ nom: 'une présence archivée ne compte pas', texte: 'BDG-V0001-2026', heure: '08:00', presences: [Object.assign({}, aOuverte, { statut: 'archive' })] }),
        pointer({ nom: 'la présence d’un autre jour ne compte pas', texte: 'BDG-V0001-2026', heure: '08:00', presences: [Object.assign({}, aOuverte, { date: '2027-02-28' })] }),
        pointer({ nom: 'la présence d’un autre agent ne compte pas', texte: 'BDG-V0002-2026', heure: '08:01', presences: [aOuverte] }),
        pointer({ nom: 'badge inconnu', texte: 'BDG-INCONNU-0000', heure: '08:00' }),
        pointer({ nom: 'badge expiré', texte: 'BDG-V0003-2026', heure: '08:00' }),
        pointer({ nom: 'badge retiré', texte: 'BDG-V0004-2026', heure: '08:00' }),
        pointer({ nom: 'badge perdu', texte: 'BDG-V0009-2026', heure: '08:00' }),
        pointer({ nom: 'badge non remis', texte: 'BDG-V0005-2026', heure: '08:00' }),
        pointer({ nom: 'fiche archivée d’un badge retiré : la fiche se retrouve', texte: 'BDG-V0010-2026', heure: '08:00' }),
        pointer({ nom: 'code incohérent avec le matricule', texte: 'CNT-BDG|MAT:99999|SER:BDG-V0001-2026', heure: '08:00' }),
        pointer({ nom: 'numéro illisible (vide)', texte: '   ', heure: '08:00' }),
        pointer({ nom: 'agent du badge absent du personnel', texte: 'BDG-V0006-2026', heure: '08:00' }),
        pointer({ nom: 'agent du badge archivé', texte: 'BDG-V0007-2026', heure: '08:00' }),
        pointer({ nom: 'pointage désactivé', texte: 'BDG-V0001-2026', heure: '08:00', actif: false }),
        pointer({ nom: 'désactivé et badge inconnu : le réglage est jugé d’abord', texte: 'BDG-INCONNU-0000', heure: '08:00', actif: false }),
      ];
      ['da', 'admin', 'direction', 'rh', 'caissier', 'medecin', 'assistant_comptable', 'infirmier', 'aide_soignant', 'ambulancier'].forEach((role) => {
        pointages.push(pointer({ nom: 'rôle ' + role, role: role, texte: 'BDG-V0001-2026', heure: '08:00' }));
      });
      pointages.push(pointer({ nom: 'rôle caissier et badge inconnu : le rôle est jugé d’abord', role: 'caissier', texte: 'BDG-INCONNU-0000', heure: '08:00' }));

      const regler = (nom, role, o, courant) => {
        seConnecter(role, 'Vecteur ' + role);
        S.setReglage('planningBadgeSertDePointage', courant.actif);
        S.setReglage('planningBadgeDelaiMinutes', courant.delai);
        const r = PB.regler(o);
        const apres = { actif: S.reglage('planningBadgeSertDePointage', null), delai: S.reglage('planningBadgeDelaiMinutes', null) };
        return propre({ nom: nom, role: role, options: o, courant: courant, attendu: r.ok ? { ok: true, actif: r.actif, delai: r.delai, avant: r.avant, enBase: apres } : { ok: false, code: r.code, motif: r.motif, geste: r.geste, enBase: apres } });
      };
      const cu = { actif: true, delai: 5 };
      const reglages = [
        regler('l’administrateur coupe le pointage', 'admin', { actif: false }, cu),
        regler('la DAF règle le délai', 'da', { delai: 10, motif: 'Vecteur' }, cu),
        regler('délai à 0', 'admin', { delai: 0 }, cu),
        regler('délai à 720 (borne haute)', 'admin', { delai: 720 }, cu),
        regler('délai à 721', 'admin', { delai: 721 }, cu),
        regler('délai négatif', 'admin', { delai: -1 }, cu),
        regler('délai décimal', 'admin', { delai: 2.5 }, cu),
        regler('délai non numérique', 'admin', { delai: 'abc' }, cu),
        regler('délai texte numérique accepté', 'admin', { delai: '15' }, cu),
        regler('délai omis : le courant reste', 'admin', { actif: false }, { actif: true, delai: 12 }),
        regler('actif omis : le courant reste', 'admin', { delai: 7 }, { actif: false, delai: 5 }),
        regler('un médecin ne règle pas', 'medecin', { actif: false }, cu),
        regler('un surveillant ne règle pas', 'surveillant', { delai: 1 }, cu),
        regler('la Direction ne règle pas', 'direction', { delai: 1 }, cu),
        regler('rôle non habilité et délai invalide : le rôle est jugé d’abord', 'caissier', { delai: -5 }, cu),
      ];
      S.setReglage('planningBadgeSertDePointage', true); S.setReglage('planningBadgeDelaiMinutes', 5); S.setReglage('paieCopieTelephone', true);
      seConnecter(sess0.role, sess0.nom);
      return { monde: { personnel: propre(personnel), collections: propre(monde), notes: notes }, agents: { A: A.id, B: B.id, C: Cm.id }, rubriques: rubriques, lectures: lectures, copies: copies, reglagesCopie: reglagesCopie,
        pointage: { badges: propre(badges), personnel: propre(personnel), cas: pointages, reglages: reglages } };
    });
    ecrire('packages/domaine/test/vecteurs/mes_pointage.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-mes-pointage.js : espace « Mes » (lot L7) et pointage par badge (lot L8), tirés des moteurs de la maquette. Ne pas éditer à la main.' }, sortie));
    ['lectures', 'copies', 'reglagesCopie'].forEach((k) => console.log('  ' + k + ' : ' + sortie[k].length));
    console.log('  pointage.cas : ' + sortie.pointage.cas.length + ' ; pointage.reglages : ' + sortie.pointage.reglages.length);
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
