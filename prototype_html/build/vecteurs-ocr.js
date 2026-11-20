/* =============================================================================
 * VECTEURS DE LA LECTURE OCR PRÉPARÉE (lot OCR-prep) : `modules/fichiers-ocr.js` de la maquette
 * -----------------------------------------------------------------------------
 * La maquette réelle est PILOTÉE dans Chrome (module chargé, serveur PHP et base du banc), et ce qu'elle répond est écrit en vecteurs. Rien n'est tiré de la lecture du code. AUCUN moteur
 * réel : un moteur FACTICE est branché dans la page, il rend le texte que le générateur lui donne. Ce qui est vectorisé, c'est tout ce qui l'entoure :
 *   - les mots normalisés, l'identifiant déterministe d'une lecture, la version courante et l'ordre des versions ;
 *   - les six états d'indexation (grille d'entrées) ;
 *   - le texte que la recherche lit (la couche native prime, la zone 2 reste de zone 2) ;
 *   - le réglage (qui peut régler, refus nommés, activer sans moteur) ;
 *   - la demande d'une lecture (idempotence, refus nommés), la reprise après arrêt, la relance ;
 *   - le message sous « Aucun résultat » et la note de recherche ;
 *   - la lecture d'un fichier de bout en bout : la fiche de la version écrite, et chaque refus nommé du moteur (illisible, délai, aucun texte, langue, format, PDF sans rendeur).
 *   node build/vecteurs-ocr.js   →   packages/domaine/test/vecteurs/ocr.json
 * Banc ISOLÉ : SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> SIGH_FICHIERS_DIR=<dossier à soi> CHROME_PATH=/opt/pw-browsers/chromium node build/vecteurs-ocr.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT, REPO } = require('./extraire');

const FIXT = path.join(REPO, 'apps/poste/test/fixtures/fichiers');

(async () => {
  console.log('▶ Vecteurs de la lecture OCR préparée');
  const m = await ouvrirMaquette();
  const out = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-ocr.js : ne pas éditer. Maquette réelle pilotée dans Chrome, moteur FACTICE, serveur PHP du banc. Aucun moteur réel, aucune qualité d’OCR mesurée.' };
  try {
    const page = m.page;
    await page.evaluate(() => {
      const Vrai = Date;
      window.__FIXE = new Vrai(2026, 9, 30, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      SIGH.ui.sonner = () => {};
      SIGH.ui.toast = () => {};
    });
    await page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/fichiers.js') });
    await page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/fichiers-ocr.js') });
    const sessionAdmin = { role: 'admin', nom: 'SONDE vec', nomComplet: 'SONDE vec', identifiant: 'vec.admin', fonction: 'admin' };
    await page.evaluate((s) => { SIGH.store.setSession(s); }, sessionAdmin);
    await page.waitForTimeout(500);

    /* --- 1. mots normalisés ------------------------------------------------------------------------------------------------------------------------- */
    const textesMots = [
      'Hyperglycémie sévère : père déjà traité à Natitingou, œuf de ç',
      'AMOXICILLINE 500 mg, deux fois par jour ; paracétamol 1 g.',
      'Le le LE la  l’ordonnance d’Aïssatou N’TCHA-OROU',
      'a b cd e fg  12 3 45',
      'Œdème, ÉCHOGRAPHIE, naïf, Noël, ÇA',
      '',
    ];
    out.mots = await page.evaluate((ts) => ts.map((t) => ({ texte: t, mots: SIGH.ocr.motsNormalises(t) })), textesMots);

    /* --- 2. identifiants de lecture --------------------------------------------------------------------------------------------------------------- */
    const sha0 = 'a'.repeat(64), sha1 = '0123456789abcdef'.repeat(4);
    const casIds = [
      { sha: sha0, moteur: 'factice', version: '0.1', langue: 'fra', texte: 'Hyperglycémie sévère' },
      { sha: sha0, moteur: 'factice', version: '0.2', langue: 'fra', texte: 'Hyperglycémie sévère' },
      { sha: sha0, moteur: 'autre', version: '0.1', langue: 'fra', texte: 'Hyperglycémie sévère' },
      { sha: sha0, moteur: 'factice', version: '0.1', langue: 'eng', texte: 'Hyperglycémie sévère' },
      { sha: sha1, moteur: 'factice', version: '0.1', langue: 'fra', texte: 'Hyperglycémie sévère' },
      { sha: sha0, moteur: 'factice', version: '0.1', langue: 'fra', texte: 'HYPERGLYCEMIE, sévère !' },
      { sha: sha0, moteur: 'factice', version: '0.1', langue: 'fra', texte: 'paludisme grave' },
    ];
    out.ids = await page.evaluate((cs) => cs.map((c) => Object.assign({}, c, { mots: SIGH.ocr.motsNormalises(c.texte).join(' '), id: SIGH.ocr.idLecture(c.sha, c.moteur, c.version, c.langue, SIGH.ocr.motsNormalises(c.texte).join(' ')) })), casIds);

    /* --- 3. états d'indexation : la grille ------------------------------------------------------------------------------------------------------- */
    const V = (nb, le, id) => ({ id: id || ('OCR-x-' + le), nbMots: nb, ocrLe: le });
    const grilleVersions = { aucune: [], une: [V(5, '2026-10-01T10:00:00.000Z')], deux: [V(5, '2026-10-01T10:00:00.000Z', 'OCR-a'), V(7, '2026-10-02T10:00:00.000Z', 'OCR-b')], videSeule: [V(0, '2026-10-01T10:00:00.000Z')] };
    const grilleFiles = { aucune: null, attente: { etat: 'en_attente' }, cours: { etat: 'en_cours' }, echec: { etat: 'echec', raison: 'le moteur n’a pas répondu en 120 s' }, echecSansRaison: { etat: 'echec' } };
    const grilleMoteur = [
      { moteurInstalle: false, actif: false, moteurActif: false }, { moteurInstalle: true, actif: false, moteurActif: false }, { moteurInstalle: true, actif: true, moteurActif: false },
      { moteurInstalle: true, actif: true, moteurActif: true }, { moteurInstalle: false, actif: true, moteurActif: false },
    ];
    const entrees = [];
    for (const natif of [false, true]) for (const kv of Object.keys(grilleVersions)) for (const kf of Object.keys(grilleFiles)) for (const mo of grilleMoteur) {
      entrees.push(Object.assign({ natif, versions: grilleVersions[kv], file: grilleFiles[kf], cleVersions: kv, cleFile: kf }, mo));
    }
    out.etats = await page.evaluate((es) => es.map((e) => ({ entree: e, sortie: SIGH.ocr.etatIndexation(e) })), entrees);

    /* --- 4. versions : ordre et version courante (le magasin réel) -------------------------------------------------------------------------- */
    out.courante = await page.evaluate(() => {
      const col = SIGH.store.collection('lecturesOcr', { module: 'M13', entite: 'lecture OCR', prefix: 'OCR' });
      const cas = [];
      const poser = (nom, sha, vs) => {
        vs.forEach((v) => col.insert(Object.assign({ sha256: sha, texte: 'mot' + v.id, texteBrut: 'x', moteur: 'factice', moteurVersion: '0.1', langue: 'fra' }, v)));
        cas.push({ nom: nom, versions: vs, ordre: SIGH.ocr.versionsDe(sha).map((x) => x.id), courante: (SIGH.ocr.versionCourante(sha) || {}).id || null });
      };
      poser('une seule', 'b'.repeat(64), [{ id: 'OCR-bbbb000000000000-111111111111', nbMots: 3, ocrLe: '2026-10-01T10:00:00.000Z' }]);
      poser('deux dates', 'c'.repeat(64), [{ id: 'OCR-cccc000000000000-aaaaaaaaaaaa', nbMots: 3, ocrLe: '2026-10-03T10:00:00.000Z' }, { id: 'OCR-cccc000000000000-bbbbbbbbbbbb', nbMots: 4, ocrLe: '2026-10-01T10:00:00.000Z' }]);
      poser('même instant, l’identifiant départage', 'd'.repeat(64), [{ id: 'OCR-dddd000000000000-ffffffffffff', nbMots: 3, ocrLe: '2026-10-01T10:00:00.000Z' }, { id: 'OCR-dddd000000000000-000000000000', nbMots: 3, ocrLe: '2026-10-01T10:00:00.000Z' }]);
      poser('la plus récente est vide : la courante est la précédente qui porte du texte', 'e'.repeat(64), [{ id: 'OCR-eeee000000000000-111111111111', nbMots: 3, ocrLe: '2026-10-01T10:00:00.000Z' }, { id: 'OCR-eeee000000000000-222222222222', nbMots: 0, ocrLe: '2026-10-02T10:00:00.000Z' }]);
      poser('aucune ne porte de texte', 'f'.repeat(64), [{ id: 'OCR-ffff000000000000-111111111111', nbMots: 0, ocrLe: '2026-10-01T10:00:00.000Z' }]);
      return cas;
    });

    /* --- 4b. LOT C : la CORRECTION SIGNÉE du texte lu (module réel, magasin réel, horloge figée) : identifiants, version courante et conflit (grille), états, refus nommés, fiche écrite ------------------- */
    out.corrections = await page.evaluate(() => {
      const O = SIGH.ocr, S = SIGH.store, N = SIGH.nav;
      const col = S.collection('lecturesOcr', { module: 'M13', entite: 'lecture OCR', prefix: 'OCR' });
      const res = { geste: O.GESTE_CORRECTION, ids: [], courant: [], corriger: [], droit: {} };
      const sha0 = 'a'.repeat(64);
      [[sha0, 'OCR-x', 'Texte corrigé'], [sha0, 'OCR-x', '  Texte   corrigé \n'], [sha0, 'OCR-y', 'Texte corrigé'], [sha0, 'OCR-x', 'Texte corrigé autrement'], ['b'.repeat(64), 'OCR-x', 'Texte corrigé']]
        .forEach((c) => res.ids.push({ sha: c[0], corrigeDe: c[1], texte: c[2], id: O.idCorrection(c[0], c[1], c[2]) }));
      /* La grille de la version courante, des têtes, du conflit et de l'état : toutes les listes sont données DANS L'ORDRE QUE LE MODULE TROUVE (date de lecture, puis identifiant). */
      const M = (id, le, nb) => ({ id: id, texteSource: 'ocr', nbMots: nb === undefined ? 4 : nb, ocrLe: le, texte: 'mot' + id, texteBrut: 'brut ' + id });
      const C = (id, le, remplace, par) => ({ id: id, texteSource: 'correction', nbMots: 5, ocrLe: le, corrigeLe: le, corrigePar: par || 'Agent A', corrigeDe: 'M1', remplace: remplace || [], texte: 'mot' + id, texteBrut: 'brut ' + id });
      const grilles = {
        'machine seule': [M('M1', '2026-10-01T10:00:00.000Z')],
        'deux machines, la plus récente courante': [M('M1', '2026-10-01T10:00:00.000Z'), M('M2', '2026-10-02T10:00:00.000Z')],
        'une correction': [M('M1', '2026-10-01T10:00:00.000Z'), C('C1', '2026-10-02T10:00:00.000Z')],
        'une machine plus récente que la correction : la correction reste courante': [M('M1', '2026-10-01T10:00:00.000Z'), C('C1', '2026-10-02T10:00:00.000Z'), M('M2', '2026-10-03T10:00:00.000Z')],
        'une correction qui remplace la première, partie de la nouvelle machine': [M('M1', '2026-10-01T10:00:00.000Z'), C('C1', '2026-10-02T10:00:00.000Z'), M('M2', '2026-10-03T10:00:00.000Z'), C('C2', '2026-10-04T10:00:00.000Z', ['C1'], 'Agent B')],
        'deux corrections concurrentes : conflit, la plus récente est courante': [M('M1', '2026-10-01T10:00:00.000Z'), C('C1', '2026-10-02T10:00:00.000Z', [], 'Agent A'), C('C2', '2026-10-02T11:00:00.000Z', [], 'Agent B')],
        'deux corrections au même instant : l’identifiant départage': [M('M1', '2026-10-01T10:00:00.000Z'), C('C1', '2026-10-02T10:00:00.000Z', [], 'Agent A'), C('C2', '2026-10-02T10:00:00.000Z', [], 'Agent B')],
        'une correction ultérieure remplace les deux : plus de conflit': [M('M1', '2026-10-01T10:00:00.000Z'), C('C1', '2026-10-02T10:00:00.000Z', [], 'Agent A'), C('C2', '2026-10-02T11:00:00.000Z', [], 'Agent B'), C('C3', '2026-10-03T10:00:00.000Z', ['C1', 'C2'], 'Agent C')],
        'une lecture machine vide ne compte pas': [M('M1', '2026-10-01T10:00:00.000Z'), M('M2', '2026-10-02T10:00:00.000Z', 0)],
      };
      Object.keys(grilles).forEach((nom) => {
        const vs = grilles[nom].slice().sort((a, b) => (a.ocrLe < b.ocrLe ? -1 : (a.ocrLe > b.ocrLe ? 1 : (a.id < b.id ? -1 : 1))));
        const cur = O.courantDe(vs);
        res.courant.push({ nom: nom, versions: grilles[nom], courant: cur ? cur.id : null, tetes: O.tetesDe(vs).map((x) => x.id),
          etats: [{ file: null }, { file: { etat: 'en_cours' } }, { file: { etat: 'en_attente' } }, { file: { etat: 'echec', raison: 'le moteur a échoué' } }].map((f) => {
            const e = O.etatIndexation({ natif: false, versions: grilles[nom], file: f.file, moteurInstalle: true, actif: true, moteurActif: true });
            return { file: f.file, code: e.code, court: e.court, libelle: e.libelle, source: e.source, marque: e.marque, disponible: e.disponible, conflit: e.conflit };
          }) });
      });
      /* La correction de bout en bout : droits, refus nommés, fiche écrite. Chaque cas part d'un scan LU par machine (une version) ; `suite` rejoue sur le même scan. */
      const sess = (role) => S.setSession({ role: role, nom: 'SONDE vec', nomComplet: 'SONDE vec', identifiant: 'vec.' + role, fonction: role });
      let n = 0;
      const scan = (machineTexte) => {
        n++;
        const sha = ('c' + n).padStart(2, '0').repeat(32).slice(0, 64);
        const id = O.idLecture(sha, 'factice', '0.1', 'fra', O.motsNormalises(machineTexte).join(' '));
        col.insert({ id: id, sha256: sha, texteBrut: machineTexte, texte: O.motsNormalises(machineTexte).join(' '), nbMots: O.motsNormalises(machineTexte).length, texteSource: 'ocr', moteur: 'factice', moteurVersion: '0.1', langue: 'fra', ocrLe: '2026-10-01T10:00:00.000Z', ocrPar: 'machine' });
        return { sha: sha, machine: id };
      };
      const essai = (nom, role, f, texte, ctx, avecNatif) => {
        sess(role);
        const avant = JSON.parse(JSON.stringify(O.versionsDe(f.sha)));
        const fichier = { sha256: f.sha }; if (avecNatif) fichier.texteIndexe = true;
        const zoneLue = ctx.famille !== 'patient' || SIGH.parcours.peutVoirDocument(ctx.type).autorise;
        let r; try { r = O.corriger(fichier, texte, ctx); } catch (e) { throw new Error(nom + ' : ' + e.stack); }
        const apres = O.versionsDe(f.sha);
        const nouvelle = apres.filter((x) => !avant.some((y) => y.id === x.id))[0];
        const cas = { nom: nom, role: role, sha: f.sha, texte: texte, corrigeDe: ctx.corrigeDe || null, peutDeposer: !!ctx.peutDeposer, zoneLue: zoneLue, geste: N.droitGeste(role, O.GESTE_CORRECTION), natif: !!avecNatif,
          versionsAvant: avant, ok: !!r.ok, code: r.code || null, motif: r.motif || null, nouvelle: r.ok ? r.nouvelle : null, id: r.ok ? r.id : null };
        if (nouvelle) cas.fiche = { id: nouvelle.id, texteBrut: nouvelle.texteBrut, texte: nouvelle.texte, nbMots: nouvelle.nbMots, texteSource: nouvelle.texteSource, corrigeDe: nouvelle.corrigeDe, remplace: nouvelle.remplace, corrigePar: nouvelle.corrigePar, corrigeLe: nouvelle.corrigeLe, ocrLe: nouvelle.ocrLe };
        res.corriger.push(cas);
        return r;
      };
      const courrier = { peutDeposer: true, famille: 'courrier', type: null };
      const cr = { peutDeposer: true, famille: 'patient', type: 'Compte rendu médical' };
      const a = scan('Ordonnance lue par machine, paracétamol 500 mg');
      essai('l’administrateur corrige un courrier : une version signée', 'admin', a, 'Ordonnance corrigée, paracétamol 1 g', courrier);
      essai('le même texte sur la même version : rejeu, aucune seconde version', 'admin', a, '  Ordonnance corrigée, paracétamol 1 g ', Object.assign({ corrigeDe: a.machine }, courrier));
      essai('une seconde correction remplace la première', 'admin', a, 'Ordonnance corrigée deux fois, paracétamol 1 g', courrier);
      essai('texte vide', 'admin', a, '  \n ', courrier);
      essai('texte identique à la version dont la correction part', 'admin', a, 'Ordonnance corrigée deux fois,   paracétamol 1 g ', courrier);
      essai('version de départ inconnue', 'admin', a, 'Un autre texte', Object.assign({ corrigeDe: 'OCR-inconnu' }, courrier));
      essai('scan sans aucune lecture', 'admin', { sha: 'e'.repeat(64) }, 'Un texte', courrier);
      const b = scan('Facture lue par machine');
      essai('couche texte native : elle prime, rien à corriger', 'admin', b, 'Un texte', courrier, true);
      essai('profil qui n’écrit pas sur l’écran de la pièce', 'admin', b, 'Un texte', { peutDeposer: false, famille: 'courrier', type: null });
      essai('rôle sans le geste réservé (comptable)', 'comptable', b, 'Un texte', courrier);
      const z = scan('Compte rendu lu par machine, hyperglycémie');
      essai('l’accueil écrit sur l’écran des documents mais ne lit pas la zone 2', 'reception', z, 'Un texte', cr);
      essai('l’anesthésiste lit la zone 2 mais n’écrit pas sur l’écran', 'anesthesiste', z, 'Un texte', { peutDeposer: false, famille: 'patient', type: 'Compte rendu médical' });
      essai('le médecin corrige le compte rendu de zone 2', 'medecin', z, 'Compte rendu corrigé, hyperglycémie sévère', cr);
      /* Le droit d'origine, rôle par rôle, tel que le manifeste le donne. */
      Object.keys(N.ROLES).forEach((r) => { res.droit[r] = N.droitGeste(r, O.GESTE_CORRECTION); });
      S.setSession({ role: 'admin', nom: 'SONDE vec', nomComplet: 'SONDE vec', identifiant: 'vec.admin', fonction: 'admin' });
      return res;
    });

    /* --- 5. texte lu pour la recherche : la couche native prime, la zone 2 reste de zone 2 --------------------------------------------------- */
    out.texteRecherche = await page.evaluate(() => {
      const reg = SIGH.store.collection('fichiers', { module: 'M13', entite: 'fichier', prefix: 'FIC' });
      const lec = SIGH.store.collection('lecturesOcr', { module: 'M13', entite: 'lecture OCR', prefix: 'OCR' });
      const cas = [];
      const roles = ['admin', 'medecin', 'reception', 'agentadmin', 'infirmier', 'comptable', 'da'];
      let n = 0;
      for (const natif of [false, true]) for (const lu of [false, true]) for (const famille of ['courrier', 'patient']) for (const type of (famille === 'patient' ? ['Compte rendu médical', 'Pièce d’identité', 'Type inconnu'] : [null])) {
        n++;
        const sha = ('7' + String(n)).padStart(2, '0').repeat(32).slice(0, 64);
        reg.insert({ id: 'FIC-' + sha.slice(0, 16), sha256: sha, texteIndexe: natif, texte: natif ? 'natifmot natif2' : '', nbReferences: 1 });
        if (lu) lec.insert({ id: 'OCR-' + sha.slice(0, 16) + '-000000000001', sha256: sha, texte: 'ocrmot ocr2', texteBrut: 'x', nbMots: 2, moteur: 'factice', moteurVersion: '0.1', langue: 'fra', ocrLe: '2026-10-01T10:00:00.000Z' });
        for (const role of roles) {
          SIGH.store.setSession({ role: role, nom: 'v', nomComplet: 'v', identifiant: 'v.' + role, fonction: role });
          cas.push({ natif: natif, lu: lu, famille: famille, type: type, role: role, texte: SIGH.fichiers.texteDe({ sha256: sha }, { famille: famille, type: type }) });
        }
      }
      SIGH.store.setSession({ role: 'admin', nom: 'SONDE vec', nomComplet: 'SONDE vec', identifiant: 'vec.admin', fonction: 'admin' });
      return cas;
    });

    /* --- 6. le réglage : qui règle, refus nommés ------------------------------------------------------------------------------------------------- */
    out.reglage = await page.evaluate(() => {
      const O = SIGH.ocr, cas = [];
      const sess = (role) => SIGH.store.setSession({ role: role, nom: 'v', nomComplet: 'v', identifiant: 'v.' + role, fonction: role });
      const essai = (nom, role, moteurs, v, motif) => {
        O.retirerMoteur();
        moteurs.forEach((x) => O.enregistrerMoteur(x));
        sess(role);
        const avant = O.reglage();
        const r = O.definirReglage(v, motif);
        cas.push({ nom: nom, role: role, moteurs: moteurs.map((x) => ({ id: x.id, langues: x.langues })), demande: v, motif: motif, ok: !!r.ok, code: r.code || null, avant: { actif: avant.actif, moteur: avant.moteur, langue: avant.langue }, apres: (() => { const a = O.reglage(); return { actif: a.actif, moteur: a.moteur, langue: a.langue, regle: a.regle }; })() });
      };
      const f = { id: 'factice', version: '0.1', langues: ['fra', 'eng'], lire: () => Promise.resolve({ texte: 'x' }) };
      const g = { id: 'autre', version: '1', langues: ['eng'], lire: () => Promise.resolve({ texte: 'x' }) };
      essai('défaut : rien n’est réglé', 'admin', [], { actif: false, moteur: null, langue: 'fra' }, 'remise à plat');
      essai('un profil non autorisé', 'agentadmin', [f], { actif: true, moteur: 'factice', langue: 'fra' }, 'essai');
      essai('le médecin non plus', 'medecin', [f], { actif: false, moteur: 'factice', langue: 'fra' }, 'essai');
      essai('activer sans aucun moteur installé', 'admin', [], { actif: true, moteur: 'factice', langue: 'fra' }, 'essai');
      essai('activer sans moteur choisi', 'admin', [f], { actif: true, moteur: null, langue: 'fra' }, 'essai');
      essai('activer avec un moteur inconnu', 'admin', [f], { actif: true, moteur: 'inconnu', langue: 'fra' }, 'essai');
      essai('sans motif', 'admin', [f], { actif: true, moteur: 'factice', langue: 'fra' }, '');
      essai('motif d’espaces', 'admin', [f], { actif: true, moteur: 'factice', langue: 'fra' }, '   ');
      essai('langue que le moteur ne lit pas', 'admin', [g], { actif: true, moteur: 'autre', langue: 'fra' }, 'essai');
      essai('activer, administrateur', 'admin', [f], { actif: true, moteur: 'factice', langue: 'fra' }, 'activation');
      essai('désactiver, administrateur', 'admin', [f], { actif: false, moteur: 'factice', langue: 'fra' }, 'désactivation');
      essai('activer, Directrice Administrative', 'da', [f], { actif: true, moteur: 'factice', langue: 'eng' }, 'activation DA');
      essai('désactiver sans moteur installé reste permis', 'admin', [], { actif: false, moteur: null, langue: 'fra' }, 'désactivation');
      sess('admin');
      return cas;
    });

    /* --- 7. demande, reprise, relance : la file ---------------------------------------------------------------------------------------------------- */
    out.file = await page.evaluate(() => {
      const O = SIGH.ocr, S = SIGH.store;
      const reg = S.collection('fichiers', { module: 'M13', entite: 'fichier', prefix: 'FIC' });
      const lec = S.collection('lecturesOcr', { module: 'M13', entite: 'lecture OCR', prefix: 'OCR' });
      S.setSession({ role: 'admin', nom: 'SONDE vec', nomComplet: 'SONDE vec', identifiant: 'vec.admin', fonction: 'admin' });
      const prets = (pret) => {
        O.retirerMoteur();
        if (pret.installe) O.enregistrerMoteur({ id: 'factice', version: '0.1', langues: ['fra'], lire: () => Promise.resolve({ texte: 'x' }) });
        S.setReglage('ocr', { actif: !!pret.actif, moteur: pret.choisi ? 'factice' : null, langue: 'fra', delaiMs: 1000 });
      };
      const demandes = [];
      let n = 0;
      const registres = { natif: { texteIndexe: true }, vide: {}, attente: { ocr: { etat: 'en_attente', demandeLe: '2026-10-01T09:00:00.000Z', famille: 'courrier', type: null, essais: 0 } },
        cours: { ocr: { etat: 'en_cours', demandeLe: '2026-10-01T09:00:00.000Z', debutLe: '2026-10-01T09:30:00.000Z', famille: 'courrier', type: null, essais: 1 } },
        echec: { ocr: { etat: 'echec', code: 'IMAGE_ILLISIBLE', raison: 'l’image est illisible', famille: 'courrier', type: null, essais: 1 } }, lu: {}, absent: null };
      const moteurs = { 'aucun moteur': { installe: false, actif: false, choisi: false }, 'installé, désactivé': { installe: true, actif: false, choisi: true }, 'installé, activé, non choisi': { installe: true, actif: true, choisi: false }, prêt: { installe: true, actif: true, choisi: true } };
      for (const kr of Object.keys(registres)) for (const km of Object.keys(moteurs)) for (const relance of [false, true]) {
        n++;
        const sha = ('9' + String(n)).padStart(2, '0').repeat(32).slice(0, 64);
        if (registres[kr] !== null) reg.insert(Object.assign({ id: 'FIC-' + sha.slice(0, 16), sha256: sha, texteIndexe: false, nbReferences: 1 }, JSON.parse(JSON.stringify(registres[kr]))));
        if (kr === 'lu') lec.insert({ id: 'OCR-' + sha.slice(0, 16) + '-000000000001', sha256: sha, texte: 'mot', texteBrut: 'mot', nbMots: 1, moteur: 'factice', moteurVersion: '0.1', langue: 'fra', ocrLe: '2026-10-01T10:00:00.000Z' });
        prets(moteurs[km]);
        const r = O.demander(sha, { famille: 'courrier', type: null, declencheur: relance ? 'relance' : 'automatique' });
        const f = reg.get('FIC-' + sha.slice(0, 16));
        const o = f && f.ocr ? Object.assign({}, f.ocr) : null;
        if (o) { delete o.demandeLe; delete o.demandePar; }
        demandes.push({ registre: kr, moteur: km, relance: relance, ok: !!r.ok, code: r.code || null, deja: !!r.deja, lu: !!r.lu, demande: !!r.demande, etatFile: o });
      }
      const reprises = [];
      const maintenant = Date.parse('2026-10-30T10:00:00.000Z');
      for (const c of [
        { nom: 'récent', debutLe: '2026-10-30T09:59:00.000Z', essais: 1, delaiMs: 120000 }, { nom: 'ancien', debutLe: '2026-10-30T09:00:00.000Z', essais: 1, delaiMs: 120000 },
        { nom: 'exactement deux délais', debutLe: '2026-10-30T09:56:00.000Z', essais: 1, delaiMs: 120000 }, { nom: 'trois essais', debutLe: '2026-10-30T09:00:00.000Z', essais: 3, delaiMs: 120000 },
        { nom: 'sans date de début', debutLe: null, essais: 0, delaiMs: 120000 },
      ]) {
        n++;
        const sha = ('8' + String(n)).padStart(2, '0').repeat(32).slice(0, 64);
        reg.insert({ id: 'FIC-' + sha.slice(0, 16), sha256: sha, texteIndexe: false, nbReferences: 1, ocr: { etat: 'en_cours', demandeLe: '2026-10-30T08:00:00.000Z', debutLe: c.debutLe, essais: c.essais, famille: 'courrier' } });
        prets({ installe: true, actif: true, choisi: true });
        S.setReglage('ocr', { actif: true, moteur: 'factice', langue: 'fra', delaiMs: c.delaiMs });
        const reel = Date.now;
        Date.now = () => maintenant;
        const nb = O.reprendre();
        Date.now = reel;
        const f = reg.get('FIC-' + sha.slice(0, 16));
        const o = Object.assign({}, f.ocr); delete o.finLe;
        reprises.push({ nom: c.nom, debutLe: c.debutLe, essais: c.essais, delaiMs: c.delaiMs, repris: nb, etatFile: o });
      }
      /* relance possible / refusée : le droit d'écrire, le moteur, la couche texte, la file */
      const relances = [];
      for (const peut of [false, true]) for (const km of Object.keys(moteurs)) for (const kr of ['natif', 'vide', 'attente', 'cours', 'echec', 'lu']) {
        n++;
        const sha = ('6' + String(n)).padStart(2, '0').repeat(32).slice(0, 64);
        reg.insert(Object.assign({ id: 'FIC-' + sha.slice(0, 16), sha256: sha, texteIndexe: false, nbReferences: 1 }, JSON.parse(JSON.stringify(registres[kr]))));
        if (kr === 'lu') lec.insert({ id: 'OCR-' + sha.slice(0, 16) + '-000000000001', sha256: sha, texte: 'mot', texteBrut: 'mot', nbMots: 1, moteur: 'factice', moteurVersion: '0.1', langue: 'fra', ocrLe: '2026-10-01T10:00:00.000Z' });
        prets(moteurs[km]);
        const possible = O.relancePossible({ sha256: sha }, peut);   /* AVANT la relance : relancer met le scan en file, et la commande n'est alors plus offerte */
        const refus = O.relancer({ sha256: sha }, { peutDeposer: peut, famille: 'courrier' });
        relances.push({ peutDeposer: peut, moteur: km, registre: kr, possible: possible, ok: !!refus.ok, code: refus.code || null, deja: !!refus.deja });
      }
      S.setReglage('ocr', { actif: false, moteur: null, langue: 'fra' });
      O.retirerMoteur();
      return { demandes: demandes, reprises: reprises, relances: relances };
    });

    /* --- 8. messages : sous « Aucun résultat », note de recherche ------------------------------------------------------------------------------- */
    out.messages = await page.evaluate(() => {
      const O = SIGH.ocr, S = SIGH.store;
      const reg = S.collection('fichiers', { module: 'M13', entite: 'fichier', prefix: 'FIC' });
      const lec = S.collection('lecturesOcr', { module: 'M13', entite: 'lecture OCR', prefix: 'OCR' });
      const moteursEtat = (installe, actif, choisi) => { O.retirerMoteur(); if (installe) O.enregistrerMoteur({ id: 'factice', version: '0.1', langues: ['fra'], lire: () => Promise.resolve({ texte: 'x' }) }); S.setReglage('ocr', { actif: actif, moteur: choisi ? 'factice' : null, langue: 'fra' }); };
      let n = 0;
      const fabrique = (genre) => {
        n++;
        const sha = ('5' + String(n)).padStart(2, '0').repeat(32).slice(0, 64);
        const base = { id: 'FIC-' + sha.slice(0, 16), sha256: sha, texteIndexe: genre === 'natif', nbReferences: 1 };
        if (genre === 'attente') base.ocr = { etat: 'en_attente' };
        if (genre === 'cours') base.ocr = { etat: 'en_cours' };
        if (genre === 'echec') base.ocr = { etat: 'echec', raison: 'l’image est illisible' };
        reg.insert(base);
        if (genre === 'lu') lec.insert({ id: 'OCR-' + sha.slice(0, 16) + '-000000000001', sha256: sha, texte: 'paludisme grave', texteBrut: 'paludisme grave', nbMots: 2, moteur: 'factice', moteurVersion: '0.1', langue: 'fra', ocrLe: '2026-10-01T10:00:00.000Z' });
        return { sha256: sha, texteIndexe: genre === 'natif' };
      };
      const vides = [];
      const compos = [['sans aucun', [], [false, false, false]], ['un scan sans moteur', ['non'], [false, false, false]], ['trois scans sans moteur', ['non', 'non', 'non'], [false, false, false]],
        ['scan, moteur installé mais lecture désactivée', ['non'], [true, false, true]], ['scan, moteur installé, lecture non choisie', ['non'], [true, true, false]],
        ['natif seul', ['natif'], [false, false, false]], ['un lu par machine', ['lu'], [true, true, true]], ['deux lus par machine', ['lu', 'lu'], [true, true, true]],
        ['en attente et en échec', ['attente', 'echec'], [true, true, true]], ['en cours', ['cours'], [true, true, true]], ['mélange', ['non', 'lu', 'natif', 'echec', 'attente'], [true, true, true]]];
      compos.forEach((c) => {
        moteursEtat(c[2][0], c[2][1], c[2][2]);
        const fs_ = c[1].map((g) => fabrique(g === 'non' ? 'vide' : g));
        vides.push({ nom: c[0], moteur: { installe: c[2][0], actif: c[2][1], choisi: c[2][2] }, genres: c[1], indice: O.indiceVide(fs_) });
      });
      /* note de recherche */
      moteursEtat(true, true, true);
      const a = fabrique('lu'), b = fabrique('lu'), c3 = fabrique('natif'), d = fabrique('vide');
      const note = (q, fs_) => { const x = O.noteRecherche(q, fs_); return x ? { texte: x.textContent.replace(/\s+/g, ' ').trim(), n: x.getAttribute('data-note-ocr') } : null; };
      const notes = [
        { nom: 'un résultat', q: 'paludisme', fichiers: 1, note: note('paludisme', [a, c3, d]) },
        { nom: 'deux résultats', q: 'paludisme', fichiers: 2, note: note('paludisme', [a, b, c3]) },
        { nom: 'recherche qui ne passe pas par le texte lu', q: 'autre', fichiers: 2, note: note('autre', [a, b]) },
        { nom: 'sans recherche', q: '', fichiers: 2, note: note('', [a, b]) },
        { nom: 'accents et casse', q: 'PALUDISMÉ', fichiers: 1, note: note('PALUDISMÉ', [a]) },
      ];
      S.setReglage('ocr', { actif: false, moteur: null, langue: 'fra' });
      O.retirerMoteur();
      return { vides: vides, notes: notes };
    });

    /* --- 9. la lecture d'un fichier, de bout en bout (serveur de fichiers réel, moteur factice) ------------------------------------------------- */
    const nomsScans = ['scan.png', 'scan.jpg', 'scan.webp', 'scan-image.pdf'];
    const octetsScans = {};
    nomsScans.forEach((n) => { octetsScans[n] = fs.readFileSync(path.join(FIXT, n)).toString('base64'); });
    out.lecture = await page.evaluate(async (octetsScans) => {
      const O = SIGH.ocr, S = SIGH.store, F = SIGH.fichiers;
      /* La session du SERVEUR suit celle de l'écran, mais pas au même instant (comme `poserSessionServeur` du banc) : on laisse passer les sessions des sections précédentes, puis on attend le jeton NEUF. */
      await new Promise((r) => setTimeout(r, 1500));
      const avantJeton = S.jetonServeur();
      S.setSession({ role: 'admin', nom: 'SONDE vec', nomComplet: 'SONDE vec', identifiant: 'vec.admin', fonction: 'admin' });
      for (let i = 0; i < 100 && (!S.jetonServeur() || S.jetonServeur() === avantJeton); i++) await new Promise((r) => setTimeout(r, 100));
      const reg = S.collection('fichiers', { module: 'M13', entite: 'fichier', prefix: 'FIC' });
      const docs = S.collection('documentsPatient', { module: 'M1', entite: 'document', prefix: 'DOC' });   /* WEBP n'est admis qu'au dossier du patient : tous les scans y sont déposés (pièce d'identité, zone 1) */
      const cas = [];
      let k = 0;
      const moteur = (cfg) => {
        O.retirerMoteur();
        O.enregistrerMoteur({ id: 'factice', version: '0.1', langues: cfg.langues || ['fra'], formats: cfg.formats || ['png', 'jpeg', 'webp'], lire: function (e) {
          if (cfg.refus) return Promise.reject(cfg.refus);
          if (cfg.jamais) return new Promise(function () {});
          const mots = String(cfg.texte).split(/\s+/).filter(Boolean).map((m) => ({ mot: m, confiance: cfg.confiance === undefined ? 0.9 : cfg.confiance }));
          return Promise.resolve({ texte: cfg.texte, mots: cfg.confiance === null ? mots.map((x) => ({ mot: x.mot })) : mots, langue: e.langue });
        } });
        S.setReglage('ocr', { actif: true, moteur: 'factice', langue: cfg.langueReglee || 'fra', delaiMs: cfg.delaiMs || 5000 });
      };
      const lire = async (nom, cfg, pdfSansRendeur) => {
        k++;
        moteur(cfg);
        const u8 = F.depuisBase64(octetsScans[nom] + '');
        const octets = new Uint8Array(u8.length + 8); octets.set(u8); octets.set([k, k, k, k, 0, 0, 0, 0], u8.length);  /* un fichier distinct par cas (même format : les octets en trop ne gênent ni PNG, ni JPEG, ni WEBP, ni PDF) */
        const rep = await F.deposerOctets(octets, { famille: 'patient', type: 'Pièce d’identité', nom: nom, sha256: F.sha256Octets(octets) });
        if (!rep.ok) throw new Error('dépôt refusé : ' + nom + ' ' + rep.code);
        S.setReglage('ocr', { actif: false, moteur: null, langue: 'fra' });   /* le dépôt ne met rien en file : la file est lancée à la main ci-dessous */
        const fiche = docs.insert({ reference: 'GED-VEC-' + k, patientId: 'PVEC', code: 'CNT/1/26', patient: 'Vecteur', type: 'Pièce d’identité', date: '2026-10-30', etat: 'valide', depose: 'v' }).record;
        F.rattacher(docs, docs.get(fiche.id), 'patient', rep, nom, { module: 'M1', entite: 'document' });
        moteur(cfg);
        O.demander(rep.sha256, { famille: 'patient', type: 'Pièce d’identité' });
        /* Les lignes de file fictives des sections précédentes (empreintes sans fichier) sont écartées une à une (FICHIER_ABSENT) avant d'arriver au scan de ce cas. */
        let t = await O.traiterSuivant();
        for (let i = 0; i < 40 && t.ecarte && !t.fait; i++) t = await O.traiterSuivant();
        const f = reg.get('FIC-' + rep.sha256.slice(0, 16));
        const vs = O.versionsDe(rep.sha256).map((v) => { const c = JSON.parse(JSON.stringify(v)); delete c.ocrLe; delete c.dureeMs; delete c.ocrPar; delete c.statut; delete c.sha256; delete c.id; delete c._modifiePar; delete c._modifieLe; delete c._creePar; delete c._creeLe; return Object.assign({ id: v.id.slice(-12) }, c); });
        const o = f.ocr ? { etat: f.ocr.etat, code: f.ocr.code, raison: f.ocr.raison, geste: f.ocr.geste } : null;
        return { fichier: nom, ok: !!t.ok, code: t.code || null, fait: !!t.fait, file: o, versions: vs, id: (O.versionCourante(rep.sha256) || {}).id || null, sha: rep.sha256 };
      };
      const defs = [
        ['lecture réussie, confiance donnée', 'scan.png', { texte: 'Hyperglycémie sévère : père déjà traité à Natitingou, œuf de ç' }],
        ['lecture réussie, JPEG', 'scan.jpg', { texte: 'Ordonnance du docteur ; amoxicilline 500 mg' }],
        ['lecture réussie, WEBP', 'scan.webp', { texte: 'Certificat médical établi le jour même' }],
        ['lecture réussie, confiance non donnée', 'scan.png', { texte: 'Convocation à la réunion de la Direction', confiance: null }],
        ['texte sur plusieurs lignes', 'scan.png', { texte: 'Première ligne\nDeuxième ligne avec accents éèêà\nTroisième' }],
        ['image illisible', 'scan.png', { texte: 'x', refus: { code: 'IMAGE_ILLISIBLE', motif: 'l’image est illisible' } }],
        ['langue absente (le moteur ne lit plus la langue réglée)', 'scan.png', { texte: 'x', langues: ['eng'] }],
        ['moteur absent au moment de lire', 'scan.png', { texte: 'x', refus: { code: 'MOTEUR_ABSENT', motif: 'le moteur a disparu' } }],
        ['délai dépassé', 'scan.png', { texte: 'x', jamais: true, delaiMs: 400 }],
        ['aucun texte', 'scan.png', { texte: '   ' }],
        ['échec que le moteur ne nomme pas', 'scan.png', { texte: 'x', refus: { code: 'INVENTE', message: 'plantage interne' } }],
        ['format que le moteur ne lit pas', 'scan.webp', { texte: 'x', formats: ['png', 'jpeg'] }],
        ['PDF sans couche texte, sans rendeur de pages', 'scan-image.pdf', { texte: 'x' }],
      ];
      for (const d of defs) { const r = await lire(d[1], d[2]); cas.push(Object.assign({ nom: d[0], moteur: { texte: d[2].texte, confiance: d[2].confiance === undefined ? 0.9 : d[2].confiance, refus: d[2].refus || null, jamais: !!d[2].jamais, langues: d[2].langues || ['fra'], formats: d[2].formats || ['png', 'jpeg', 'webp'], delaiMs: d[2].delaiMs || 5000 } }, r)); }
      /* La même lecture rejouée avec le même moteur et le même texte : la MÊME version (identifiant déterministe). */
      const a = await lire('scan.png', { texte: 'Texte identique rejoué' });
      if (!a.id) throw new Error('la lecture rejouée n’a produit aucune version');
      const idAvant = a.id, nAvant = a.versions.length;
      S.setReglage('ocr', { actif: true, moteur: 'factice', langue: 'fra', delaiMs: 5000 });
      O.relancer({ sha256: a.sha }, { peutDeposer: true, famille: 'patient', type: 'Pièce d’identité' });
      await O.vider(5);
      const rejoue = { idAvant: idAvant.slice(-12), idApres: O.versionCourante(a.sha).id.slice(-12), versionsAvant: nAvant, versionsApres: O.versionsDe(a.sha).length };
      S.setReglage('ocr', { actif: false, moteur: null, langue: 'fra' });
      O.retirerMoteur();
      return { cas: cas, rejoue: rejoue };
    }, octetsScans);

    /* --- 10. LES SCANS SYNTHÉTIQUES du banc de mesure : chaque transcription (`.txt`) est DESSINÉE dans l'image (texte noir sur fond blanc), de sorte que le dossier d'essai soit cohérent le jour
       où un vrai moteur y est branché. Aucun document de la clinique, aucune donnée de patient : des phrases de démonstration. -------------------------------------------------------------- */
    const dossierBanc = path.join(REPO, 'packages/domaine/test/fixtures/ocr_banc');
    const browser = page.context().browser();
    const pageFx = await browser.newPage();
    for (const [nom, format] of [['ordonnance-synthetique', 'png'], ['courrier-synthetique', 'jpeg'], ['certificat-synthetique', 'webp']]) {
      const texte = fs.readFileSync(path.join(dossierBanc, nom + '.txt'), 'utf8');
      const b64 = await pageFx.evaluate(async (a) => {
        const c = document.createElement('canvas'); c.width = 1100; c.height = 360;
        const x = c.getContext('2d');
        x.fillStyle = '#fff'; x.fillRect(0, 0, c.width, c.height);
        x.fillStyle = '#000'; x.font = '22px sans-serif';
        let y = 50;
        a.texte.split('\n').forEach((ligne) => {
          let courant = '';
          ligne.split(' ').forEach((mot) => { const essai = courant ? courant + ' ' + mot : mot; if (x.measureText(essai).width > 1040 && courant) { x.fillText(courant, 30, y); y += 34; courant = mot; } else courant = essai; });
          if (courant) { x.fillText(courant, 30, y); y += 34; }
        });
        return c.toDataURL(a.mime, 0.95).split(',')[1];
      }, { texte: texte, mime: { png: 'image/png', jpeg: 'image/jpeg', webp: 'image/webp' }[format] });
      fs.writeFileSync(path.join(dossierBanc, nom + '.' + { png: 'png', jpeg: 'jpg', webp: 'webp' }[format]), Buffer.from(b64, 'base64'));
    }
    await pageFx.close();

    ecrire('packages/domaine/test/vecteurs/ocr.json', out);
    console.log('  états : ' + out.etats.length + ', texte de recherche : ' + out.texteRecherche.length + ', demandes : ' + out.file.demandes.length + ', lectures : ' + out.lecture.cas.length);
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error('ÉCHEC :', e); process.exit(1); });
