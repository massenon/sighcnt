/* =============================================================================
 * VECTEURS DE L'ORGANIGRAMME ET DU VERROU D'UN POSTE DE SECOURS (lot ORG2, 11/11/2026) : SIGH.organigramme, S.migrerOrganigramme, P.organigramme et SIGH.verrouSecours,
 * les moteurs de la maquette, PILOTÉS dans Chrome
 * -----------------------------------------------------------------------------
 * Décisions de la Direction du 11/11/2026 (O1 à O5, P3) : l'organigramme suit la photo du papier mais n'est pas figé (réaffecter, renommer le titulaire, poser le titre de l'agent,
 * archiver), le titre est porté par l'agent, aucune étoile ; le verrou d'un poste de secours est un réglage en base de 5 minutes à valider. Chaque cas pose son monde au magasin
 * (postes, personnel, session de l'acteur), appelle le moteur de la maquette et enregistre ce qu'il rend ET ce qu'il a écrit (champs, journal). Le domaine Dart
 * (`organigramme.dart`, `verrou_secours.dart`) rejoue chaque cas sur les MÊMES entrées.
 * L'horloge est posée au 30/10/2026 (la date que les tests du poste utilisent).
 *   node build/vecteurs-organigramme.js   →   packages/domaine/test/vecteurs/organigramme.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de l’organigramme et du verrou d’un poste de secours (ORG2)');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, D = SIGH.data, P = SIGH.print, ORG = SIGH.organigramme, VS = SIGH.verrouSecours, N = SIGH.nav;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const sess0 = S.session();
      const seConnecter = (role, nom) => S.setSession(Object.assign({}, sess0, { role: role, nom: nom || 'Vecteur ' + role, nomComplet: nom || 'Vecteur ' + role }));
      const raw = S.raw();
      S.collection('postes').all();

      /* ===================================================== le monde ===================================================== */
      const agent = (id, nom, extra) => Object.assign({ id: id, nomComplet: nom, statut: 'actif' }, extra || {});
      const personnelMonde = () => [
        agent('E1', 'GARBA Yahouza', { titreOrganigramme: 'SG' }), agent('E2', 'AHOHOU Rodrigue'), agent('E3', 'TAKI Alimatou'), agent('E4', 'KASSA Augustin'),
        agent('E5', 'Aïssatou DIEYABIDI'), agent('E6', 'ARCHIVÉ Ancien', { statut: 'archive', titreOrganigramme: 'XX' }),
      ];
      const postesMonde = () => D.postesDeLaSemence().concat([{ id: 'PSTA', statut: 'archive', parentId: 'PST001', poste: 'Ancien service', effectif: 1, titulaire: null, chef: false, role: 'agentadmin', source: 'Vecteur', _archiveLe: '2026-01-01T08:00:00.000Z' }]);
      const poserMonde = () => {
        raw.postes = propre(postesMonde()); raw.personnel = propre(personnelMonde());
        raw.audit.length = 0;
      };
      const champsPoste = (p) => ({ id: p.id, statut: p.statut, parentId: p.parentId === undefined ? null : p.parentId, poste: p.poste, effectif: p.effectif, titulaire: p.titulaire === undefined ? null : p.titulaire, chef: !!p.chef, role: p.role });
      const resume = () => ({ postes: raw.postes.map(champsPoste), titres: raw.personnel.filter((a) => a.titreOrganigramme !== undefined && a.titreOrganigramme !== null).map((a) => [a.id, a.titreOrganigramme]) });
      const refus = (r) => ({ ok: false, code: r.code, motif: r.motif, geste: r.geste });
      const sortieCas = (r, avant) => {
        const apres = resume();
        const ajoutes = raw.audit.length;
        const journal = raw.audit.slice(0, ajoutes).reverse().map((l) => ({ action: l.action, module: l.module, entite: l.entite,
          ancienne: ['Réaffectation d’un poste', 'Changement de titulaire d’un poste', 'Modification d’un poste', 'Titre d’un agent dans l’organigramme', 'Archivage'].indexOf(l.action) >= 0 ? l.ancienneValeur : null,
          nouvelle: ['Réaffectation d’un poste', 'Changement de titulaire d’un poste', 'Modification d’un poste', 'Titre d’un agent dans l’organigramme', 'Archivage'].indexOf(l.action) >= 0 ? l.nouvelleValeur : null }));
        const base = r.ok ? { ok: true, inchange: r.inchange === true, titre: r.titre === undefined ? null : r.titre } : refus(r);
        /* Par IDENTIFIANT, jamais par rang : une création s'insère en tête de la collection et décalerait tous les rangs. */
        const parId = {}; avant.postes.forEach((p) => { parId[p.id] = JSON.stringify(p); });
        const diff = apres.postes.filter((p) => parId[p.id] !== undefined && parId[p.id] !== JSON.stringify(p)).map((p) => p.id);
        const nouveaux = apres.postes.filter((p) => parId[p.id] === undefined).map((p) => Object.assign({}, p, { id: null }));
        return Object.assign(base, { postesChanges: diff, nouveaux: nouveaux, titres: apres.titres, journal: journal, nbPostes: apres.postes.length });
      };

      /* ===================================================== la semence et l'arbre ===================================================== */
      const semence = propre(D.postesDeLaSemence());
      const precedent = propre(D.ORGANIGRAMME_PRECEDENT);
      poserMonde();
      seConnecter('admin');
      const aplatir = (noeuds, niveau, out) => { noeuds.forEach((n) => { out.push({ id: n.id, poste: n.poste, parentId: n.parentId === undefined ? null : n.parentId, niveau: niveau, titreAgent: n.titreAgent || null, enfants: n.enfants.map((e) => e.id) }); aplatir(n.enfants, niveau + 1, out); }); return out; };
      const arbre = aplatir(ORG.arbre(), 0, []);

      /* ===================================================== les cas de l'écran (moteur) ===================================================== */
      const cas = [];
      const jouer = (nom, role, appel, f) => {
        poserMonde();
        if (appel.ajout) appel.ajout.forEach((x) => raw.postes.push(propre(x)));
        seConnecter(role);
        const avant = resume();
        const r = f();
        cas.push({ nom: nom, role: role, appel: appel, attendu: propre(sortieCas(r, avant)) });
      };
      const A = 'admin';
      jouer('réaffecter les Sages-Femmes sous le Directeur Médical', A, { fn: 'reaffecter', posteId: 'PST015', parentId: 'PST001' }, () => ORG.reaffecter('PST015', 'PST001'));
      jouer('réaffecter les Sages-Femmes au sommet', A, { fn: 'reaffecter', posteId: 'PST015', parentId: null }, () => ORG.reaffecter('PST015', null));
      jouer('réaffecter sous le même parent : rien ne change', A, { fn: 'reaffecter', posteId: 'PST015', parentId: 'PST014' }, () => ORG.reaffecter('PST015', 'PST014'));
      jouer('cycle : un poste sous lui-même', A, { fn: 'reaffecter', posteId: 'PST002', parentId: 'PST002' }, () => ORG.reaffecter('PST002', 'PST002'));
      jouer('cycle : la DA sous l’Assistant comptable', A, { fn: 'reaffecter', posteId: 'PST002', parentId: 'PST004' }, () => ORG.reaffecter('PST002', 'PST004'));
      jouer('cycle : le sommet sous le bout de la chaîne', A, { fn: 'reaffecter', posteId: 'PST001', parentId: 'PST005' }, () => ORG.reaffecter('PST001', 'PST005'));
      jouer('parent inconnu', A, { fn: 'reaffecter', posteId: 'PST013', parentId: 'PSTxxx' }, () => ORG.reaffecter('PST013', 'PSTxxx'));
      jouer('parent archivé', A, { fn: 'reaffecter', posteId: 'PST013', parentId: 'PSTA' }, () => ORG.reaffecter('PST013', 'PSTA'));
      jouer('poste inconnu', A, { fn: 'reaffecter', posteId: 'PSTxxx', parentId: 'PST001' }, () => ORG.reaffecter('PSTxxx', 'PST001'));
      jouer('poste archivé', A, { fn: 'reaffecter', posteId: 'PSTA', parentId: 'PST001' }, () => ORG.reaffecter('PSTA', 'PST001'));
      jouer('renommer le titulaire des Laborantins', A, { fn: 'renommerTitulaire', posteId: 'PST013', nom: 'NOUVEAU Titulaire' }, () => ORG.renommerTitulaire('PST013', 'NOUVEAU Titulaire'));
      jouer('vider le titulaire : le poste devient vacant', A, { fn: 'renommerTitulaire', posteId: 'PST013', nom: '' }, () => ORG.renommerTitulaire('PST013', ''));
      jouer('poser le titre ECH à l’échographiste', A, { fn: 'poserTitre', posteId: 'PST012', titre: 'ECH' }, () => ORG.poserTitre('PST012', 'ECH'));
      jouer('retirer le titre du surveillant général', A, { fn: 'poserTitre', posteId: 'PST014', titre: '' }, () => ORG.poserTitre('PST014', ''));
      jouer('poser le même titre : rien ne change', A, { fn: 'poserTitre', posteId: 'PST014', titre: 'SG' }, () => ORG.poserTitre('PST014', 'SG'));
      jouer('titre sur une titulaire qui porte « épse » : retrouvée par son nom', A, { fn: 'poserTitre', posteId: 'PST002', titre: 'DA' }, () => ORG.poserTitre('PST002', 'DA'));
      jouer('titre : titulaire absent du personnel', A, { fn: 'poserTitre', posteId: 'PST013', titre: 'XX' }, () => ORG.poserTitre('PST013', 'XX'));
      jouer('titre : poste vacant', A, { fn: 'poserTitre', posteId: 'PST015', titre: 'SF' }, () => ORG.poserTitre('PST015', 'SF'));
      jouer('titre de plus de douze caractères', A, { fn: 'poserTitre', posteId: 'PST012', titre: 'TITRE BEAUCOUP TROP LONG' }, () => ORG.poserTitre('PST012', 'TITRE BEAUCOUP TROP LONG'));
      jouer('modifier : intitulé vide', A, { fn: 'modifier', posteId: 'PST012', champs: { poste: '   ' } }, () => ORG.modifier('PST012', { poste: '   ' }));
      jouer('modifier : effectif fractionnaire', A, { fn: 'modifier', posteId: 'PST012', champs: { effectif: 1.5 } }, () => ORG.modifier('PST012', { effectif: 1.5 }));
      jouer('modifier : rôle inconnu', A, { fn: 'modifier', posteId: 'PST012', champs: { role: 'inconnu' } }, () => ORG.modifier('PST012', { role: 'inconnu' }));
      jouer('modifier plusieurs champs d’un coup (intitulé, rattachement, effectif, chef, titulaire, titre)', A,
        { fn: 'modifier', posteId: 'PST012', champs: { poste: 'Echographiste (chef)', parentId: 'PST014', effectif: '2', titulaire: 'GARBA Yahouza', chef: true, titreAgent: 'SG2' } },
        () => ORG.modifier('PST012', { poste: 'Echographiste (chef)', parentId: 'PST014', effectif: '2', titulaire: 'GARBA Yahouza', chef: true, titreAgent: 'SG2' }));
      jouer('une autre personne est affectée : le titre se pose sur le NOUVEAU titulaire', A, { fn: 'modifier', posteId: 'PST012', champs: { titulaire: 'KASSA Augustin', titreAgent: 'CPT' } },
        () => ORG.modifier('PST012', { titulaire: 'KASSA Augustin', titreAgent: 'CPT' }));
      jouer('rien d’écrit si un seul champ est refusé (cycle + intitulé valide)', A, { fn: 'modifier', posteId: 'PST002', champs: { poste: 'Autre', parentId: 'PST004' } }, () => ORG.modifier('PST002', { poste: 'Autre', parentId: 'PST004' }));
      jouer('créer un poste sous le Directeur Médical', A, { fn: 'creer', champs: { poste: 'Service Neuf', parentId: 'PST001', effectif: '3', role: 'agentadmin' } }, () => ORG.creer({ poste: 'Service Neuf', parentId: 'PST001', effectif: '3', role: 'agentadmin' }));
      jouer('créer un poste sans rattachement : un sommet', A, { fn: 'creer', champs: { poste: 'Poste isolé', effectif: 1, titulaire: 'Un Nom', chef: true, role: 'infirmier' } }, () => ORG.creer({ poste: 'Poste isolé', effectif: 1, titulaire: 'Un Nom', chef: true, role: 'infirmier' }));
      jouer('créer sous un poste archivé', A, { fn: 'creer', champs: { poste: 'Sous archivé', parentId: 'PSTA', effectif: 1, role: 'agentadmin' } }, () => ORG.creer({ poste: 'Sous archivé', parentId: 'PSTA', effectif: 1, role: 'agentadmin' }));
      jouer('créer sans intitulé', A, { fn: 'creer', champs: { effectif: 1, role: 'agentadmin' } }, () => ORG.creer({ effectif: 1, role: 'agentadmin' }));
      jouer('archiver une feuille', A, { fn: 'archiver', posteId: 'PST015', motif: 'Vecteur' }, () => ORG.archiver('PST015', 'Vecteur'));
      /* ORG3 (11/11/2026) : archiver un poste qui porte des postes les RÉAFFECTE (au parent par défaut, au choix à un autre poste), tout ou rien, journal 1 + N. */
      const accueil = { id: 'PSTS', statut: 'actif', parentId: null, poste: 'Direction générale', effectif: 1, titulaire: null, chef: false, role: 'direction' };
      jouer('archiver un poste qui porte des postes : ils remontent sous son parent', A, { fn: 'archiver', posteId: 'PST014', motif: 'Vecteur' }, () => ORG.archiver('PST014', 'Vecteur'));
      jouer('archiver un poste qui porte des postes sous une autre cible', A, { fn: 'archiver', posteId: 'PST014', motif: 'Vecteur', cibleId: 'PST012' }, () => ORG.archiver('PST014', 'Vecteur', { cibleId: 'PST012' }));
      jouer('archiver sans motif : le journal porte un motif vide', A, { fn: 'archiver', posteId: 'PST014', motif: null }, () => ORG.archiver('PST014', null));
      jouer('archiver la DA : trois postes remontent sous le Directeur Médical', A, { fn: 'archiver', posteId: 'PST002', motif: 'Vecteur' }, () => ORG.archiver('PST002', 'Vecteur'));
      jouer('sommet qui porte des postes sans cible et sans poste d’accueil : refusé', A, { fn: 'archiver', posteId: 'PST001', motif: 'Vecteur' }, () => ORG.archiver('PST001', 'Vecteur'));
      jouer('sommet qui porte des postes sans cible alors qu’un poste d’accueil existe : refusé', A, { fn: 'archiver', posteId: 'PST001', motif: 'Vecteur', ajout: [accueil] }, () => ORG.archiver('PST001', 'Vecteur'));
      jouer('sommet qui porte des postes, cible choisie : ses sept postes passent sous elle', A, { fn: 'archiver', posteId: 'PST001', motif: 'Vecteur', cibleId: 'PSTS', ajout: [accueil] }, () => ORG.archiver('PST001', 'Vecteur', { cibleId: 'PSTS' }));
      jouer('cible : le poste lui-même', A, { fn: 'archiver', posteId: 'PST002', motif: 'Vecteur', cibleId: 'PST002' }, () => ORG.archiver('PST002', 'Vecteur', { cibleId: 'PST002' }));
      jouer('cible : un descendant (cycle)', A, { fn: 'archiver', posteId: 'PST002', motif: 'Vecteur', cibleId: 'PST004' }, () => ORG.archiver('PST002', 'Vecteur', { cibleId: 'PST004' }));
      jouer('cible : un poste porté (cycle)', A, { fn: 'archiver', posteId: 'PST014', motif: 'Vecteur', cibleId: 'PST015' }, () => ORG.archiver('PST014', 'Vecteur', { cibleId: 'PST015' }));
      jouer('cible : un poste archivé', A, { fn: 'archiver', posteId: 'PST014', motif: 'Vecteur', cibleId: 'PSTA' }, () => ORG.archiver('PST014', 'Vecteur', { cibleId: 'PSTA' }));
      jouer('cible : un poste inconnu', A, { fn: 'archiver', posteId: 'PST014', motif: 'Vecteur', cibleId: 'PSTxxx' }, () => ORG.archiver('PST014', 'Vecteur', { cibleId: 'PSTxxx' }));
      jouer('une feuille s’archive sans cible, la cible demandée est sans objet', A, { fn: 'archiver', posteId: 'PST015', motif: 'Vecteur', cibleId: 'PST012' }, () => ORG.archiver('PST015', 'Vecteur', { cibleId: 'PST012' }));
      jouer('un sommet dont le parent est archivé : la cible est exigée', A, { fn: 'archiver', posteId: 'PSTQ', motif: 'Vecteur', ajout: [{ id: 'PSTP', statut: 'archive', parentId: null, poste: 'Parent archivé', effectif: 1, titulaire: null, chef: false, role: 'agentadmin' }, { id: 'PSTQ', statut: 'actif', parentId: 'PSTP', poste: 'Poste sous archivé', effectif: 1, titulaire: null, chef: false, role: 'agentadmin' }, { id: 'PSTT', statut: 'actif', parentId: 'PSTQ', poste: 'Poste porté par lui', effectif: 1, titulaire: null, chef: false, role: 'agentadmin' }] }, () => ORG.archiver('PSTQ', 'Vecteur'));
      jouer('archiver un poste déjà archivé', A, { fn: 'archiver', posteId: 'PSTA', motif: 'Vecteur' }, () => ORG.archiver('PSTA', 'Vecteur'));
      jouer('archiver un poste inconnu', A, { fn: 'archiver', posteId: 'PSTxxx', motif: 'Vecteur' }, () => ORG.archiver('PSTxxx', 'Vecteur'));
      /* annuler SANS écrire (matrice modifiée) : un poste sans poste porté s'archive, un poste qui en porte exige AUSSI d'écrire (réaffecter est une modification) */
      const sansEcrire = (f) => () => {
        const fiche = S.collection('rbac').all().filter((x) => x.role === 'direction')[0], copie = JSON.stringify(fiche.droitsEcrans || null);
        fiche.droitsEcrans = Object.assign({}, fiche.droitsEcrans || {}, { 'cfg-organisation': { voir: true, editer: false, annuler: true } });
        SIGH.nav.invaliderRbac();
        try { return f(); } finally { if (copie === 'null') delete fiche.droitsEcrans; else fiche.droitsEcrans = JSON.parse(copie); SIGH.nav.invaliderRbac(); }
      };
      jouer('droit : annuler sans écrire archive une feuille', 'direction', { fn: 'archiver', posteId: 'PST015', motif: 'Vecteur', droits: { editer: false, annuler: true } }, sansEcrire(() => ORG.archiver('PST015', 'Vecteur')));
      jouer('droit : annuler sans écrire n’archive pas un poste qui porte des postes', 'direction', { fn: 'archiver', posteId: 'PST014', motif: 'Vecteur', droits: { editer: false, annuler: true } }, sansEcrire(() => ORG.archiver('PST014', 'Vecteur')));
      ['caissier', 'medecin', 'da', 'direction'].forEach((role) => {
        jouer('droit : ' + role + ' réaffecte', role, { fn: 'reaffecter', posteId: 'PST015', parentId: 'PST001' }, () => ORG.reaffecter('PST015', 'PST001'));
        jouer('droit : ' + role + ' archive', role, { fn: 'archiver', posteId: 'PST015', motif: 'Vecteur' }, () => ORG.archiver('PST015', 'Vecteur'));
      });
      jouer('droit : sans session, rien ne s’écrit', A, { fn: 'reaffecter', posteId: 'PST015', parentId: 'PST001', sansRole: true }, () => {
        const s = S.session(); S.setSession(Object.assign({}, s, { role: '' }));
        return ORG.reaffecter('PST015', 'PST001');
      });
      /* L'ANNULATION d'un archivage qui a réaffecté : l'archivage, puis ce qui s'est passé entre-temps (un poste déplacé, archivé, ou le poste déjà restauré), puis l'annulation. */
      const annulations = [];
      const journalBrut = () => raw.audit.slice().reverse().map((l) => ({ action: l.action, entite: l.entite, reference: l.reference, ancienne: l.ancienneValeur, nouvelle: l.nouvelleValeur }));
      const annuler = (nom, appel) => {
        poserMonde();
        (appel.ajout || []).forEach((x) => raw.postes.push(propre(x)));
        seConnecter('admin');
        raw.audit.length = 0;
        const r = ORG.archiver(appel.posteId, appel.motif === undefined ? 'Vecteur' : appel.motif, appel.cibleId ? { cibleId: appel.cibleId } : undefined);
        const out = { archivage: r.ok ? { ok: true, reaffectes: r.reaffectes.map((x) => x.id), cible: r.cible ? r.cible.id : null } : refus(r) };
        (appel.entreTemps || []).forEach((g) => {
          if (g.fn === 'reaffecter') ORG.reaffecter(g.posteId, g.parentId);
          else if (g.fn === 'archiver') ORG.archiver(g.posteId, 'entre temps');
          else if (g.fn === 'restaurer') S.collection('postes', { module: 'CFG', entite: 'poste', prefix: 'PST' }).restore(g.posteId);
        });
        if (appel.roleAnnulation) seConnecter(appel.roleAnnulation);
        const u = r.ok ? r.undo() : null;
        out.annulation = u ? (u.ok ? { ok: true, restaures: u.restaures.map((x) => x.id), laisses: u.laisses.map((x) => ({ id: x.id, motif: x.motif })) } : refus(u)) : null;
        out.postes = raw.postes.map(champsPoste);
        out.journal = journalBrut();
        annulations.push({ nom: nom, appel: appel, attendu: propre(out) });
      };
      annuler('annuler : le poste revient et chaque poste porté retrouve son ancien parent', { posteId: 'PST014' });
      annuler('annuler : un poste déplacé depuis est laissé où il est, et dit', { posteId: 'PST014', entreTemps: [{ fn: 'reaffecter', posteId: 'PST016', parentId: 'PST012' }] });
      annuler('annuler : un poste archivé depuis est laissé, et dit', { posteId: 'PST014', entreTemps: [{ fn: 'archiver', posteId: 'PST015' }] });
      annuler('annuler : le poste est déjà restauré, annulation refusée en le nommant', { posteId: 'PST014', entreTemps: [{ fn: 'restaurer', posteId: 'PST014' }] });
      annuler('annuler : sans le droit au moment d’annuler, refusé en le nommant', { posteId: 'PST014', roleAnnulation: 'caissier' });
      annuler('annuler : remettre un poste sous l’ancien parent ferait une boucle, il est laissé et dit', { posteId: 'PST014', cibleId: 'PSTS', ajout: [accueil], entreTemps: [{ fn: 'reaffecter', posteId: 'PST001', parentId: 'PST015' }] });
      annuler('annuler : un poste sans poste porté revient seul', { posteId: 'PST015' });
      annuler('annuler : un sommet archivé vers un poste d’accueil, ses sept postes reviennent', { posteId: 'PST001', cibleId: 'PSTS', ajout: [accueil] });

      /* contrôle sans écriture : la saisie d'un formulaire, avant le bouton « Enregistrer » */
      const controles = [
        ['création : sous archivé', null, { parentId: 'PSTA' }], ['création : intitulé vide', null, { poste: ' ' }], ['création : tout va bien', null, { poste: 'X', parentId: 'PST001', effectif: 2 }],
        ['modification : cycle', 'PST002', { parentId: 'PST004' }], ['modification : titre sans agent', 'PST013', { titreAgent: 'ZZ' }], ['modification : tout va bien', 'PST012', { effectif: 2 }],
      ].map((c) => { poserMonde(); seConnecter('admin'); const r = ORG.controler(c[1], c[2]); return { nom: c[0], posteId: c[1], champs: c[2], attendu: r ? refus(r) : null }; });

      /* ===================================================== la reprise ===================================================== */
      const fiche = (i, extra) => Object.assign({ id: precedent[i].id, statut: 'actif', source: 'Organigramme de la Clinique NASSIERA TOO' }, precedent[i], extra || {});
      const nettoyer = (f) => { Object.keys(f).forEach((k) => { if (f[k] === null) delete f[k]; }); return f; };
      const reprises = [];
      const reprise = (nom, postes) => {
        const base = { postes: propre(postes.map(nettoyer)) };
        const bilan = S.migrerOrganigramme(base);
        const second = S.migrerOrganigramme(base);
        reprises.push({ nom: nom, entree: propre(postes.map(nettoyer)), attendu: { bilan: bilan, second: second, postes: propre(base.postes) } });
      };
      reprise('une fiche intacte est réécrite, une fiche modifiée par l’écran ne l’est jamais', [fiche(1), fiche(2, { _modifieLe: '2026-11-01T08:00:00.000Z' }), fiche(3, { effectif: 2 }), fiche(4, { statut: 'archive', _archiveLe: '2026-11-02T08:00:00.000Z' }), fiche(5, { etoile: true })]);
      reprise('toute la semence d’avant est reprise', precedent.map((_, i) => fiche(i)));
      reprise('une semence déjà reprise n’est pas retouchée', D.postesDeLaSemence().map((p) => Object.assign({}, p, p.id === 'PST002' ? { poste: 'Directrice (nom choisi par la clinique)' } : {})));
      reprise('un champ étoile est retiré de toute fiche', [Object.assign(fiche(12), { etoile: true }), Object.assign(fiche(13), { etoile: false, _modifieLe: '2026-11-03T08:00:00.000Z' })]);
      reprise('un identifiant inconnu n’est pas touché', [{ id: 'PSTzz', statut: 'actif', poste: 'Autre', effectif: 1, role: 'agentadmin' }]);

      /* ===================================================== la mise en page de l'organigramme (P.organigramme) ===================================================== */
      const lire = (racines, options) => {
        const cadre = P.organigramme(racines, options);
        const style = (e) => { const o = {}; (e.getAttribute('style') || '').split(';').forEach((p) => { const i = p.indexOf(':'); if (i > 0) o[p.slice(0, i).trim()] = p.slice(i + 1).trim(); }); return o; };
        const mmv = (v) => Number(String(v).replace('mm', ''));
        const st = style(cadre);
        const boites = [...cadre.querySelectorAll('.org-boite')].map((b) => { const s = style(b); return { poste: b.getAttribute('data-poste'), gauche: mmv(s.left), haut: mmv(s.top), largeur: mmv(s.width), hauteur: mmv(s.height),
          lignes: [...b.querySelectorAll('span')].map((x) => x.textContent) }; });
        const svg = cadre.querySelector('svg');
        const traits = [...svg.querySelectorAll('line')].map((l) => ['x1', 'y1', 'x2', 'y2'].map((a) => Number(l.getAttribute(a))));
        const fleches = [...svg.querySelectorAll('path')].map((p) => p.getAttribute('d'));
        return { largeur: mmv(st.width), hauteur: mmv(st.height), niveaux: Number(cadre.getAttribute('data-niveaux')), boites: boites, traits: traits, fleches: fleches };
      };
      poserMonde(); seConnecter('admin');
      const mises = [];
      const arbreDe = () => ORG.arbre();
      const miseEnPage = (nom, racines, options) => { mises.push({ nom: nom, options: options || null, entree: propre(racines), attendu: propre(lire(racines, options)) }); };
      miseEnPage('la semence de la photo', arbreDe());
      ORG.reaffecter('PST015', 'PST001');
      miseEnPage('les Sages-Femmes réaffectées sous le Directeur Médical', arbreDe());
      poserMonde(); seConnecter('admin');
      const foret = arbreDe(); foret.push({ id: 'PSTX', poste: 'Poste isolé', effectif: 2, titulaire: 'Un Nom', chef: true, role: 'agentadmin', enfants: [], titreAgent: null });
      miseEnPage('une forêt : le sommet de la photo et un poste isolé', foret);
      miseEnPage('une chaîne unique', [{ id: 'a', poste: 'Premier', effectif: 1, enfants: [{ id: 'b', poste: 'Deuxième', effectif: 2, titulaire: 'X', enfants: [{ id: 'c', poste: 'Troisième', effectif: 3, enfants: [] }] }] }]);
      miseEnPage('un seul poste', [{ id: 'a', poste: 'Seul', effectif: 1, titulaire: 'Y', titreAgent: 'ZZ', chef: true, enfants: [] }]);
      miseEnPage('largeur et hauteur d’une autre feuille', arbreDe(), { largeur: 200, hauteurMax: 100 });
      const vide = P.organigramme([]);
      const miseVide = { texte: vide.textContent };

      /* ===================================================== le verrou d'un poste de secours ===================================================== */
      const secours = { cas: [], poste: [], delais: [] };
      const reinit = () => { S.setReglage('verrouDelaiSecoursMinutes', undefined); delete raw._reglages.verrouDelaiSecoursMinutes; S.storage.remove('sigh-cnt:poste-secours'); raw.politiqueSecurite = []; };
      reinit(); seConnecter('admin');
      secours.defauts = { delaiSecours: VS.delaiSecours(), ordinaire: VS.delaiOrdinaire(), posteDeSecours: VS.posteDeSecours(), delaiPoste: VS.delaiPoste(), defautMin: VS.DEFAUT_MIN, bornes: VS.BORNES };
      ['admin', 'da', 'direction', 'medecin', 'surveillant', 'caissier'].forEach((role) => {
        reinit(); seConnecter(role);
        const r = VS.definirDelai({ minutes: 7, motif: 'Vecteur' });
        const enBase = S.reglage('verrouDelaiSecoursMinutes', null);
        secours.cas.push({ role: role, minutes: 7, attendu: r.ok ? { ok: true, minutes: r.minutes, avant: r.avant, enBase: enBase } : { ok: false, code: r.code, motif: r.motif, geste: r.geste, enBase: enBase } });
        const p = VS.definirPoste(true, 'Vecteur');
        secours.poste.push({ role: role, attendu: p.ok ? { ok: true, secours: p.secours, avant: p.avant, delaiMinutes: p.delaiMinutes, drapeau: S.storage.get('sigh-cnt:poste-secours') } : { ok: false, code: p.code, motif: p.motif, geste: p.geste, drapeau: S.storage.get('sigh-cnt:poste-secours') || null } });
      });
      ['', '2.5', '0', '121', '-1', 'abc', null, '1', '120', 7.0].forEach((minutes) => {
        reinit(); seConnecter('admin');
        const r = VS.definirDelai({ minutes: minutes });
        secours.cas.push({ role: 'admin', minutes: minutes, attendu: r.ok ? { ok: true, minutes: r.minutes, avant: r.avant, enBase: S.reglage('verrouDelaiSecoursMinutes', null) } : { ok: false, code: r.code, motif: r.motif, geste: r.geste, enBase: S.reglage('verrouDelaiSecoursMinutes', null) } });
      });
      [[null, null, false], [null, null, true], [10, null, false], [10, null, true], [10, 3, false], [10, 3, true], [null, 'abc', true], [null, 0, true], [null, 121, true]].forEach((c) => {
        reinit(); seConnecter('admin');
        raw.politiqueSecurite = c[0] === null ? [] : [{ id: 'POL-001', statut: 'actif', inactiviteMin: c[0] }];
        if (c[1] !== null) S.setReglage('verrouDelaiSecoursMinutes', c[1]);
        if (c[2]) S.storage.set('sigh-cnt:poste-secours', '1');
        secours.delais.push({ politiqueInactiviteMin: c[0], reglageSecours: c[1], posteDeSecours: c[2], attendu: { ordinaire: VS.delaiOrdinaire(), secours: VS.delaiSecours(), poste: VS.delaiPoste(), verrouMs: SIGH.app.delaiVerrou() } });
      });
      reinit();
      S.setSession(sess0);
      return { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-organigramme.js : organigramme (lot ORG2) et verrou d’un poste de secours (P3), tirés des moteurs de la maquette. Ne pas éditer à la main.',
        semence: semence, precedent: precedent, monde: { postes: propre(postesMonde()), personnel: propre(personnelMonde()) }, arbre: arbre, cas: cas, controles: controles, annulations: annulations, reprises: reprises, mises: mises, miseVide: miseVide, secours: secours };
    });
    ecrire('packages/domaine/test/vecteurs/organigramme.json', sortie);
    console.log('  semence : ' + sortie.semence.length + ' postes ; cas : ' + sortie.cas.length + ' ; annulations : ' + sortie.annulations.length + ' ; contrôles : ' + sortie.controles.length + ' ; reprises : ' + sortie.reprises.length + ' ; mises en page : ' + sortie.mises.length
      + ' ; secours : ' + sortie.secours.cas.length + ' cas, ' + sortie.secours.delais.length + ' délais');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
