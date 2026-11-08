/* =============================================================================
 * VECTEURS DU MOTEUR DE VALIDATION COMMUN DES RÉFÉRENTIELS (`SIGH.validations`, parcours.js, vague 91 ; boutons de la vague 92)
 * -----------------------------------------------------------------------------
 * Le MOTEUR RÉEL est piloté dans Chrome sur un magasin dont on pose les fiches (collections synthétiques, restituées à la fin) : le registre des 14
 * familles, le compte lu (`referentielsAValider`), l'état lu (`etatValidation`), le geste (`validerReferentiel`), la remise à valider
 * (`remettreAValider`) et la vue d'un profil (`referentielsVisiblesPar`). Pour chaque cas : les fiches d'ENTRÉE, la SORTIE du moteur (refus nommé
 * ou validation), l'état du magasin APRÈS et la ligne de journal écrite (RG-12). Le portage Dart
 * (`packages/domaine/lib/src/validation/validation.dart`) reçoit ces mêmes fiches.
 *
 *   SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> node build/vecteurs-validation.js
 *   →  packages/domaine/test/vecteurs/validation.json
 *
 * Non exporté (horloge) : la valeur de `valideLe` posée par le geste (seule sa PRÉSENCE et son format ISO sont enregistrés) ; les fiches d'entrée
 * qui portent déjà une validation ont une date FIXE, pour que le motif de `DEJA_VALIDE` soit reproductible.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du moteur de validation des référentiels');
  const m = await ouvrirMaquette();
  try {
    /* Le centre des validations est monté TEL QUE l'agent le voit : son module n'est chargé que sur ses pages. */
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m13-administration.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, V = SIGH.validations, N = SIGH.nav;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const brut = () => S.raw();
      const SESSION = { role: 'direction', fonction: 'direction', nom: 'OROU YO Marguerite', nomComplet: 'OROU YO Marguerite', identifiant: 'm.orouyo', secteur: 'DIR' };
      S.setSession(SESSION);

      /* Toutes les collections que le moteur lit : sauvegardées, vidées, restituées à la fin. */
      const NOMS = [];
      V.FAMILLES_A_VALIDER.forEach((f) => (f.collections || []).forEach((c) => { if (NOMS.indexOf(c) < 0) NOMS.push(c); }));
      NOMS.push('validationsReferentiels');
      const sauve = {};
      NOMS.forEach((n) => { S.collection(n).all(); sauve[n] = propre(brut()[n] || []); });
      const poser = (entree) => { NOMS.forEach((n) => { brut()[n] = propre((entree && entree[n]) || []); }); };

      const libelles = {};
      Object.keys(N.ROLES).forEach((r) => { libelles[r] = N.ROLES[r].label; });

      const FIXE = '2026-09-01T09:00:00.000Z';
      const fiche = (id, extra) => Object.assign({ id, statut: 'actif', libelle: 'Élément ' + id }, extra || {});
      const vrf = (cible, famille, extra) => Object.assign({ id: 'VRF-' + cible, statut: 'actif', famille, cible, libelle: 'Validation ' + cible }, extra || {});

      /* Une entrée type par famille de la forme « fiche marquée » : (collection, champ du marquage). */
      const MARQUEES = {};
      V.FAMILLES_A_VALIDER.forEach((f) => { if (f.mode === 'fiche-marquee') MARQUEES[f.id] = { col: f.collections[0], champ: f.champs[0] }; });

      /* Une pièce de journal NOUVELLE se reconnaît à son identifiant, jamais à la longueur (le journal est plafonné à 400). */
      const dernierId = () => brut().audit[0] || null;   /* l'OBJET de tête : deux gestes dans la même milliseconde partagent un identifiant */
      const FORME_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

      /* ---------- registre ------------------------------------------------------------------------------------------------------------ */
      const registre = V.FAMILLES_A_VALIDER.map((f) => propre(f));

      /* ---------- comptes lus (referentielsAValider) ------------------------------------------------------------------------------------ */
      const comptes = [];
      const compter = (nom, entree, opts) => {
        poser(entree);
        const r = V.referentielsAValider(opts);
        comptes.push({ nom, entree: propre(entree), opts: opts || null, sortie: propre(r) });
      };
      compter('magasin vide : chaque famille de collections est « non amorcée », les fiches de validation comptent 1 à valider', {});
      compter('pathologies : une en attente, une validée, une archivée en attente (ignorée)', {
        pathologies: [fiche('P1', { aValider: true }), fiche('P2', { aValider: false, valideLe: FIXE }), fiche('P3', { aValider: true, statut: 'archive' })] });
      compter('actes : tarifProvisoire, et un acte sans marquage', {
        actes: [fiche('A1', { tarifProvisoire: true, prix: 5000 }), fiche('A2', { tarifProvisoire: false, prix: 7000 }), fiche('A3', { tarifProvisoire: true, prix: null })] });
      compter('analyses : tarifProvisoire OU aValider compte une fois', {
        analyses: [fiche('N1', { tarifProvisoire: true, aValider: true }), fiche('N2', { aValider: true }), fiche('N3', { tarifProvisoire: false, aValider: false })] });
      compter('deux collections : variables et unités du laboratoire', {
        variablesLabo: [fiche('VL1', { aValider: true }), fiche('VL2', { aValider: false })],
        unitesLabo: [fiche('UL1', { aValider: true }), fiche('UL2', { aValider: true })] });
      compter('constante du code : une validation écrite couvre la check-liste', {
        validationsReferentiels: [vrf('checklist-bloc', 'checklists_bloc', { valideLe: FIXE, validePar: 'Praticiens du bloc', valideRole: 'Chirurgien' })] });
      compter('constante du code : une fiche de validation SANS valideLe ne couvre rien', {
        validationsReferentiels: [vrf('bareme-its', 'bareme_its', {})] });
      compter('constante du code : une fiche de validation archivée ne couvre rien', {
        validationsReferentiels: [vrf('imp-analyses', 'jeux_import', { valideLe: FIXE, statut: 'archive' })] });
      compter('vue du biologiste : seules les familles de son rôle', { variablesLabo: [fiche('VL1', { aValider: true })] }, { role: 'laborantin' });
      compter('vue de l’échographiste', {}, { role: 'echographiste' });
      compter('vue du caissier : aucune famille', {}, { role: 'caissier' });

      /* ---------- vues par profil (referentielsVisiblesPar) -------------------------------------------------------------------------------- */
      poser({});
      const vues = {};
      ['direction', 'da', 'admin', 'laborantin', 'echographiste', 'chirurgien', 'anesthesiste', 'dm', 'medecin', 'comptable', 'caissier', 'reception', 'stock']
        .forEach((r) => { vues[r] = V.referentielsVisiblesPar(r).map((x) => x.famille); });

      /* ---------- état lu (etatValidation) ---------------------------------------------------------------------------------------------- */
      const etats = [];
      const etat = (nom, entree, famille, id) => {
        poser(entree);
        etats.push({ nom, entree: propre(entree), famille, id, sortie: propre(V.etatValidation(famille, id)) });
      };
      etat('pathologie en attente', { pathologies: [fiche('P1', { aValider: true })] }, 'pathologies', 'P1');
      etat('pathologie validée : trois traces lues', { pathologies: [fiche('P1', { aValider: false, valideLe: FIXE, validePar: 'Dr X', valideRole: 'Directeur Médical' })] }, 'pathologies', 'P1');
      etat('pathologie sans nom ni libellé : l’identifiant tient lieu de libellé', { pathologies: [{ id: 'P9', statut: 'actif', aValider: true }] }, 'pathologies', 'P9');
      etat('libellé : `label` avant `designation` avant `nom`', { modelesBadge: [{ id: 'MB1', statut: 'actif', designation: 'Désignation', nom: 'Nom', aValider: true }] }, 'modeles_badge', 'MB1');
      etat('constante du code non validée', {}, 'checklists_bloc', 'checklist-bloc');
      etat('constante du code validée par fiche', {
        validationsReferentiels: [vrf('checklist-bloc', 'checklists_bloc', { valideLe: FIXE, validePar: 'Praticiens du bloc', valideRole: 'Chirurgien' })] }, 'checklists_bloc', 'checklist-bloc');
      etat('élément inconnu', { pathologies: [fiche('P1', { aValider: true })] }, 'pathologies', 'NEXISTEPAS');
      etat('famille inconnue', {}, 'famille-inconnue', 'P1');
      etat('fiche archivée : introuvable', { pathologies: [fiche('P1', { aValider: true, statut: 'archive' })] }, 'pathologies', 'P1');

      /* ---------- le geste (validerReferentiel) ---------------------------------------------------------------------------------------- */
      const gestes = [];
      const valider = (nom, entree, famille, id, role, opts) => {
        opts = opts || {};
        poser(entree);
        const session = opts.session || { nomComplet: SESSION.nomComplet, nom: SESSION.nom };
        S.setSession(Object.assign({}, SESSION, session, { role: ('roleSession' in opts ? opts.roleSession : SESSION.role) }));
        const avantJournal = dernierId();
        const avantFiches = propre(NOMS.reduce((o, n) => { o[n] = brut()[n]; return o; }, {}));
        const r = V.validerReferentiel(famille, id, role ? { role } : {});
        const apres = propre(NOMS.reduce((o, n) => { o[n] = brut()[n]; return o; }, {}));
        const nouveau = dernierId() !== avantJournal;
        const journal = nouveau ? (() => { const e = brut().audit[0]; return { action: e.action, module: e.module, entite: e.entite, reference: e.reference,
          avant: e.ancienneValeur || null, apres: e.nouvelleValeur || null, utilisateur: e.utilisateur }; })() : null;
        const sortieBrute = propre(r);
        if (r.ok) {
          const ok = FORME_ISO.test(r.valideLe);
          sortieBrute.valideLeIso = ok;
          delete sortieBrute.valideLe;
          /* Le même instant est écrit PARTOUT : fiche, retour et journal. */
          const meme = JSON.stringify(apres).indexOf(r.valideLe) >= 0 && (journal ? String(journal.apres).indexOf(r.valideLe) >= 0 : false);
          sortieBrute.memeInstantPartout = meme;
          /* Les valeurs de date sont retirées de l'état après (non reproductibles) et remplacées par un marqueur. */
          const masque = (o) => JSON.parse(JSON.stringify(o).split(r.valideLe).join('@@MAINTENANT@@'));
          const apresM = masque(apres);
          if (journal) { journal.apres = journal.apres && journal.apres.split(r.valideLe).join('@@MAINTENANT@@'); }
          gestes.push({ nom, entree: propre(entree), famille, id, role: role || null, roleSession: ('roleSession' in opts ? opts.roleSession : SESSION.role), acteurSession: session.nomComplet || session.nom || null,
            avantFiches: propre(avantFiches), sortie: sortieBrute, apres: apresM, journal });
        } else {
          gestes.push({ nom, entree: propre(entree), famille, id, role: role || null, roleSession: ('roleSession' in opts ? opts.roleSession : SESSION.role), acteurSession: session.nomComplet || session.nom || null,
            avantFiches: propre(avantFiches), sortie: sortieBrute, apres, journal, inchange: JSON.stringify(apres) === JSON.stringify(avantFiches) });
        }
        S.setSession(SESSION);
      };
      const ENT_PATHO = { pathologies: [fiche('P1', { aValider: true, code: 'PAL-S', chapitre: 'infectieuses' }), fiche('P2', { aValider: true })] };
      valider('valider sous le bon rôle (dm) : marquage retiré, trois traces, UNE ligne de journal, aucun autre champ touché', ENT_PATHO, 'pathologies', 'P1', 'dm');
      valider('valider sous le rôle de la SESSION (medecin), sans rôle passé par l’écran', ENT_PATHO, 'pathologies', 'P1', null, { roleSession: 'medecin' });
      valider('le rôle passé l’emporte sur celui de la session', ENT_PATHO, 'pathologies', 'P1', 'dm', { roleSession: 'caissier' });
      valider('rôle interdit (caissier) : VALIDATION_RESERVEE, rien d’écrit', ENT_PATHO, 'pathologies', 'P1', 'caissier');
      valider('rôle de la session interdit (reception) : VALIDATION_RESERVEE', ENT_PATHO, 'pathologies', 'P1', null, { roleSession: 'reception' });
      valider('profil sans rôle de session : refusé, « aucun » nommé', ENT_PATHO, 'pathologies', 'P1', null, { roleSession: '' });
      valider('déjà validé : DEJA_VALIDE (date de la validation citée)', { pathologies: [fiche('P1', { aValider: false, valideLe: FIXE })] }, 'pathologies', 'P1', 'dm');
      valider('aucun marquage ni validation : DEJA_VALIDE sans date', { pathologies: [fiche('P1', {})] }, 'pathologies', 'P1', 'dm');
      valider('élément introuvable : INTROUVABLE', ENT_PATHO, 'pathologies', 'N-EXISTE-PAS', 'dm');
      valider('élément archivé : INTROUVABLE', { pathologies: [fiche('P1', { aValider: true, statut: 'archive' })] }, 'pathologies', 'P1', 'dm');
      valider('famille inconnue : INTROUVABLE', ENT_PATHO, 'famille-inconnue', 'P1', 'dm');
      valider('acte sans tarif : TARIF_ABSENT (le tiret n’est ni un zéro ni un tarif arrêté)', { actes: [fiche('A1', { tarifProvisoire: true, prix: null })] }, 'actes', 'A1', 'direction');
      valider('acte au tarif d’attente : validé, tarifProvisoire retiré, prix intact', { actes: [fiche('A1', { tarifProvisoire: true, prix: 5000, designation: 'Pansement' })] }, 'actes', 'A1', 'da');
      valider('acte à tarif ZÉRO : validé (zéro est un tarif, null est un tiret)', { actes: [fiche('A1', { tarifProvisoire: true, prix: 0 })] }, 'actes', 'A1', 'admin');
      valider('analyse sans tarif : TARIF_ABSENT', { analyses: [fiche('N1', { tarifProvisoire: true, prix: null })] }, 'analyses', 'N1', 'direction');
      valider('analyse à double marquage : les DEUX marquages tombent', { analyses: [fiche('N1', { tarifProvisoire: true, aValider: true, prix: 2500 })] }, 'analyses', 'N1', 'direction');
      valider('analyse à marquage unique aValider : seul ce marquage tombe', { analyses: [fiche('N1', { aValider: true, prix: 2500 })] }, 'analyses', 'N1', 'da');
      valider('laboratoire : les unités se valident comme les variables (biologiste)', { unitesLabo: [fiche('UL1', { aValider: true })] }, 'labo_variables', 'UL1', 'laborantin');
      valider('laboratoire : la direction ne signe pas à la place du biologiste', { variablesLabo: [fiche('VL1', { aValider: true })] }, 'labo_variables', 'VL1', 'direction');
      valider('imagerie : l’échographiste valide une variable', { variablesImagerie: [fiche('VI1', { aValider: true })] }, 'imagerie', 'VI1', 'echographiste');
      valider('constante du code, première validation : une fiche VRF-<cible> naît', {}, 'repartition_charges', 'repartition-fixe-variable', 'comptable');
      valider('constante du code, fiche existante sans valideLe : elle est complétée, jamais doublée', {
        validationsReferentiels: [vrf('repartition-fixe-variable', 'repartition_charges', {})] }, 'repartition_charges', 'repartition-fixe-variable', 'direction');
      valider('constante du code déjà validée : DEJA_VALIDE', {
        validationsReferentiels: [vrf('checklist-bloc', 'checklists_bloc', { valideLe: FIXE, validePar: 'Praticiens du bloc', valideRole: 'Chirurgien' })] }, 'checklists_bloc', 'checklist-bloc', 'chirurgien');
      valider('constante du code : le caissier est refusé', {}, 'bareme_its', 'bareme-its', 'caissier');
      valider('barème de l’ITS par la DA', {}, 'bareme_its', 'bareme-its', 'da');
      valider('chaque famille à marquage se valide par son premier rôle', Object.assign({}, ...Object.keys(MARQUEES).map((id) => ({
        [MARQUEES[id].col]: [fiche('X-' + id, { [MARQUEES[id].champ]: true, prix: 1000 })] }))), 'enquetes', 'X-enquetes', 'direction');

      /* Une validation PAR FAMILLE (14 familles) sous le premier rôle du registre : le contrat de chaque famille. */
      const parFamille = [];
      V.FAMILLES_A_VALIDER.forEach((f) => {
        const entree = {};
        let id;
        if (f.mode === 'fiche') { id = f.cibles[0].id; } else {
          id = 'F-' + f.id;
          const champ = f.champs[0];
          entree[f.collections[0]] = [fiche(id, { [champ]: true, prix: 1000 })];
        }
        poser(entree);
        S.setSession(Object.assign({}, SESSION, { role: f.roles[0] }));
        const r = V.validerReferentiel(f.id, id);
        const apres = propre(NOMS.reduce((o, n) => { o[n] = brut()[n]; return o; }, {}));
        const autres = f.roles.length < 99 ? ['caissier', 'reception'].map((x) => { poser(entree); S.setSession(Object.assign({}, SESSION, { role: x })); const rr = V.validerReferentiel(f.id, id); return { role: x, code: rr.code }; }) : [];
        parFamille.push({ famille: f.id, id, role: f.roles[0], ok: r.ok === true, valideRole: r.valideRole || null, refusHorsFamille: autres,
          marquageApres: f.mode === 'fiche' ? null : f.champs.map((c) => apres[f.collections[0]][0][c]) });
      });
      S.setSession(SESSION);

      /* ---------- remise à valider (remettreAValider) ----------------------------------------------------------------------------------- */
      const remises = [];
      const remettre = (nom, entree, famille, id) => {
        poser(entree);
        const avantJournal = dernierId();
        const avantFiches = propre(NOMS.reduce((o, n) => { o[n] = brut()[n]; return o; }, {}));
        const r = V.remettreAValider(famille, id);
        const apres = propre(NOMS.reduce((o, n) => { o[n] = brut()[n]; return o; }, {}));
        const nouveau = dernierId() !== avantJournal;
        const journal = nouveau ? (() => { const e = brut().audit[0]; return { action: e.action, module: e.module, entite: e.entite, reference: e.reference,
          avant: e.ancienneValeur || null, apres: e.nouvelleValeur || null, utilisateur: e.utilisateur }; })() : null;
        remises.push({ nom, entree: propre(entree), famille, id, avantFiches, sortie: propre(r), apres, journal });
      };
      const VALIDEE = { aValider: false, valideLe: FIXE, validePar: 'Dr X', valideRole: 'Directeur Médical' };
      remettre('fiche validée : le marquage revient, les trois traces tombent à null, journal « Remise à valider »', { pathologies: [fiche('P1', VALIDEE)] }, 'pathologies', 'P1');
      remettre('fiche déjà en attente : rien n’est fait, rien n’est journalisé', { pathologies: [fiche('P1', { aValider: true })] }, 'pathologies', 'P1');
      remettre('acte validé : tarifProvisoire revient', { actes: [fiche('A1', { tarifProvisoire: false, prix: 5000, valideLe: FIXE, validePar: 'M', valideRole: 'Directeur' })] }, 'actes', 'A1');
      remettre('analyse validée (deux marquages) : le PREMIER champ du registre revient seul', { analyses: [fiche('N1', { tarifProvisoire: false, aValider: false, valideLe: FIXE, validePar: 'M', valideRole: 'Directeur' })] }, 'analyses', 'N1');
      remettre('constante du code validée : la fiche VRF perd ses traces', {
        validationsReferentiels: [vrf('checklist-bloc', 'checklists_bloc', { valideLe: FIXE, validePar: 'Praticiens du bloc', valideRole: 'Chirurgien' })] }, 'checklists_bloc', 'checklist-bloc');
      remettre('constante du code jamais validée : rien à remettre', {}, 'checklists_bloc', 'checklist-bloc');
      remettre('élément inconnu : INTROUVABLE', { pathologies: [fiche('P1', VALIDEE)] }, 'pathologies', 'NEXISTEPAS');
      remettre('famille inconnue : INTROUVABLE', {}, 'famille-inconnue', 'P1');

      /* ---------- le centre des validations (adm-validations) : lu comme l'agent le lit -------------------------------------------------- */
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const norm = (t) => String(t || '').replace(/\s+/g, ' ').trim();
      const centre = [];
      const lireCentre = async (nom, role, entree) => {
        poser(entree);
        S.setSession(Object.assign({}, SESSION, { role }));
        const root = document.createElement('div'); document.body.appendChild(root);
        SIGH.screens['adm-validations'].render(root);
        await dormir(80);
        const kpis = [...root.querySelectorAll('.kpi')].map((k) => ({ label: norm(k.querySelector('.kpi-label').textContent), valeur: norm(k.querySelector('.kpi-value').textContent) }));
        const cartes = [...root.querySelectorAll('.card')].map((c) => norm((c.querySelector('.card-title') || {}).textContent)).filter(Boolean);
        const familles = [...root.querySelectorAll('[data-famille]')].map((n) => ({
          famille: n.getAttribute('data-famille'), enAttente: n.getAttribute('data-en-attente'), texte: norm(n.textContent),
          ouvrir: [...n.querySelectorAll('button')].some((b) => norm(b.textContent) === 'Ouvrir'),
        }));
        const boutons = [...root.querySelectorAll('button')].map((b) => norm(b.textContent)).filter(Boolean);
        const vide = norm((root.querySelector('p.text-sm.text-slate-500') || {}).textContent);
        root.remove();
        centre.push({ nom, role, entree: propre(entree), kpis, cartes, familles, boutons, vide });
      };
      await lireCentre('direction : toutes les familles, comptes lus au magasin', 'direction', {
        pathologies: [fiche('P1', { aValider: true }), fiche('P2', { aValider: true }), fiche('P3', { aValider: false, valideLe: FIXE })],
        actes: [fiche('A1', { tarifProvisoire: true, prix: 5000 })],
        validationsReferentiels: [vrf('checklist-bloc', 'checklists_bloc', { valideLe: FIXE, validePar: 'Praticiens du bloc', valideRole: 'Chirurgien' })] });
      await lireCentre('biologiste : QUE les familles du laboratoire, aucune file de poste', 'laborantin', {
        variablesLabo: [fiche('VL1', { aValider: true }), fiche('VL2', { aValider: false, valideLe: FIXE })] });
      await lireCentre('échographiste : QUE l\u2019imagerie, jamais lue (non amorcée)', 'echographiste', {});
      await lireCentre('chirurgien : QUE les check-listes du bloc', 'chirurgien', {});
      await lireCentre('comptable : la répartition des charges, avec les files de son poste', 'comptable', {});

      /* ---------- restitution ---------------------------------------------------------------------------------------------------------- */
      NOMS.forEach((n) => { brut()[n] = sauve[n]; });
      S.save();

      S.setSession(SESSION);
      return { registre, vueComplete: V.VUE_COMPLETE.slice(), libelles, comptes, vues, etats, gestes, parFamille, remises, centre,
        sessionActeur: SESSION.nomComplet };
    });

    sortie._doc = 'ENGENDRÉ par prototype_html/build/vecteurs-validation.js : le moteur de validation commun (SIGH.validations) piloté dans Chrome, ne pas éditer.';
    const nb = sortie.centre.length + sortie.comptes.length + sortie.etats.length + sortie.gestes.length + sortie.remises.length;
    console.log(`  ${sortie.registre.length} familles · ${sortie.comptes.length} comptes · ${sortie.etats.length} états · ${sortie.gestes.length} gestes · ${sortie.remises.length} remises (${nb} cas)`);
    if (m.erreurs.length) console.log('  avertissements de chargement : ' + m.erreurs.length);
    ecrire('packages/domaine/test/vecteurs/validation.json', sortie);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
