/* =============================================================================
 * VECTEURS DU LOT MECEF-M (16/11/2026) : le mode MECeF par geste réservé, l'imprimante de caisse datée, l'état de la caisse
 * -----------------------------------------------------------------------------
 * La maquette est PILOTÉE (poste d'extraction, horloge au 30/10/2026) : on enregistre (1) les gestes réservés `regler_mode_mecef` et `regler_imprimante_caisse`
 * (qui les détient, refus du mode pour un rôle sans le droit), (2) l'imprimante de caisse (défaut semé, version datée, lecture à la date, les six refus nommés
 * dans l'ordre où le moteur les rend), (3) l'état de la caisse : ventes encaissées non normalisées, avoirs en attente à part, montant non calculable = null.
 * Le domaine Dart rejoue ces vecteurs (`mecef_caisse_test.dart`).
 *   node build/vecteurs-mecef-m.js   →   packages/domaine/test/vecteurs/mecef_m.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs MECEF-M');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, M = SIGH.mecef, N = SIGH.nav;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const enRole = (role, f) => { const base = S.session(); S.setSession(Object.assign({}, base, { role })); try { return f(); } finally { S.setSession(base); } };
      const refus = (r) => propre({ ok: r.ok, code: r.code || null, motif: r.motif || null, geste: r.geste || null });
      S.setSession(Object.assign({}, S.session(), { role: 'admin' }));
      S.setReglage('mecefMode', 'boitier'); S.setReglage('imprimanteCaisse', null);

      /* 1. les gestes réservés : qui les détient d'origine */
      const gestes = {};
      ['regler_mode_mecef', 'regler_imprimante_caisse'].forEach((g) => { gestes[g] = { rolesDefaut: propre(N.geste(g).rolesDefaut), roles: N.rolesAvecGeste(g).slice().sort() }; });
      const modeRefus = enRole('caissier', () => refus(M.definirMode('emecef')));
      const modeInconnu = refus(M.definirMode('inconnu'));
      const modeOk = M.definirMode('emecef'); const modeApres = M.mode(); M.definirMode('boitier');

      /* 2. l'imprimante de caisse */
      const defaut = propre(M.imprimante.aLaDate('2026-10-30'));
      const refusI = {};
      const ok0 = { liaison: 'usb', nom: 'Caisse 1', dateEffet: '2026-11-15', motif: 'Branchement vérifié à l’arrière' };
      refusI.reserve = enRole('caissier', () => refus(M.imprimante.definir(ok0)));
      S.setReglage('posteFileul', true); refusI.fileul = refus(M.imprimante.definir(ok0)); S.setReglage('posteFileul', false);
      refusI.motif = refus(M.imprimante.definir(Object.assign({}, ok0, { motif: ' ' })));
      refusI.datePassee = refus(M.imprimante.definir(Object.assign({}, ok0, { dateEffet: '2026-10-01' })));
      refusI.nom = refus(M.imprimante.definir(Object.assign({}, ok0, { nom: '  ' })));
      refusI.liaison = refus(M.imprimante.definir(Object.assign({}, ok0, { liaison: 'bluetooth' })));
      refusI.liaisonAVerifier = refus(M.imprimante.definir(Object.assign({}, ok0, { liaison: 'a_verifier' })));
      const aucuneVersion = M.imprimante.versions().length;
      const r1 = M.imprimante.definir(ok0);
      const r2 = M.imprimante.definir({ liaison: 'ethernet', nom: 'Caisse 1 réseau', dateEffet: '2026-12-01', motif: 'Passage au réseau' });
      const lectures = ['2026-10-30', '2026-11-14', '2026-11-15', '2026-11-30', '2026-12-01', '2027-01-01'].map((d) => { const v = M.imprimante.aLaDate(d); return { date: d, source: v.source, nom: v.nom, liaison: v.liaison, modele: v.modele, dateEffet: v.dateEffet }; });
      const journal = (S.raw().audit || []).filter((x) => /Imprimante de caisse/.test(x.action || '')).length;
      const imprimante = { defaut, ok0, refus: refusI, aucuneVersionApresRefus: aucuneVersion, r1ok: r1.ok, r2ok: r2.ok, lectures, journal };

      /* 3. l'état de la caisse : la base d'extraction, puis des sondes */
      const fac = S.collection('factures', { module: 'M8', entite: 'Facture' });
      const av = S.collection('avoirs', { module: 'M8', entite: 'Avoir' });
      const minimal = () => ({
        factures: S.collection('factures').active().map((f) => ({ numero: f.numero, proforma: !!f.proforma, montantPaye: f.montantPaye === undefined ? null : f.montantPaye, statutPaiement: f.statutPaiement || null, statutMecef: f.statutMecef || null })),
        avoirs: S.collection('avoirs').active().map((a) => ({ reference: a.reference || null, montant: a.montant === undefined ? null : a.montant, statutMecef: a.statutMecef || null })),
      });
      const etat = () => { const e = M.etatCaisse(); return propre({ ventes: { nombre: e.ventes.nombre, parEtat: e.ventes.parEtat, incalculables: e.ventes.incalculables, montant: e.ventes.montant },
        avoirs: { nombre: e.avoirs.nombre, incalculables: e.avoirs.incalculables, montant: e.avoirs.montant } }); };
      const cas = [];
      const releve = (nom) => cas.push({ nom, entrees: propre(minimal()), attendu: etat() });
      releve('base');
      const sonde = (n, o) => fac.insert(Object.assign({ numero: 'FN-2099-M' + n, patientId: 'PM', patient: 'SONDE MECEF-M', date: '2026-10-30', type: 'Consultation', lignes: [], montantTTC: 5000, proforma: false }, o)).record;
      sonde('1', { montantPaye: 5000, statutPaiement: 'soldee', statutMecef: 'en_attente' });
      sonde('2', { montantPaye: 3000, statutPaiement: 'soldee', statutMecef: 'a_verifier' });
      sonde('3', { montantPaye: 0, statutPaiement: 'impayee', statutMecef: 'en_attente' });
      sonde('4', { montantPaye: 7000, statutPaiement: 'soldee', statutMecef: 'valide' });
      sonde('5', { montantPaye: 9000, statutPaiement: 'soldee', statutMecef: 'en_attente', proforma: true });
      av.insert({ reference: 'AV-2099-M1', montant: 2000, statutMecef: 'en_attente', date: '2026-10-30' });
      av.insert({ reference: 'AV-2099-M2', montant: 1500, statutMecef: 'valide', date: '2026-10-30' });
      releve('sondes');
      sonde('6', { statutPaiement: 'soldee', statutMecef: 'en_attente', montantPaye: undefined });
      releve('montant_inconnu_vente');
      av.insert({ reference: 'AV-2099-M3', statutMecef: 'en_attente', date: '2026-10-30' });
      releve('montant_inconnu_avoir');
      return { gestes, mode: { refus: modeRefus, inconnu: modeInconnu, ok: modeOk.ok, apres: modeApres }, imprimante, caisse: cas };
    });
    ecrire('packages/domaine/test/vecteurs/mecef_m.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-mecef-m.js : gestes MECeF, imprimante de caisse, état de la caisse (maquette). Ne pas éditer.' }, sortie));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
