/* =============================================================================
 * VECTEURS DU BARÈME DE L'AIB ET DES RÉGLAGES DE L'AIB (Direction, 09/11/2026, lots A1 et L2)
 * -----------------------------------------------------------------------------
 * Le MOTEUR RÉEL est piloté dans Chrome sur un magasin dont on pose les fiches (collections synthétiques, restituées à la fin) :
 *   SIGH.baremeAib        : taux d'une situation à une date (refus AIB_SANS_BAREME, jamais zéro), situation d'après l'IFU, taux proposés ;
 *   SIGH.reglagesAib      : les quatre réglages datés (charge des 5 %, branchement sur les achats, compte d'acompte, compte de contrepartie),
 *                           valeur à la date, charge, état du branchement, nouvelle version (refus nommés), liste « ce qu'il faudrait écrire »,
 *                           écriture (refusée tant que le branchement n'est pas actif).
 * Les gestes sont ENCHAÎNÉS sur un même magasin (la version d'un geste est l'entrée du suivant) : pour chacun, l'entrée, la sortie du moteur
 * (refus nommé ou succès), les versions du réglage APRÈS et, pour l'écriture, les lignes posées. Horloge figée au 16/08/2026 10 h.
 *
 *   SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> node build/vecteurs-aib.js
 *   →  packages/domaine/test/vecteurs/aib.json
 * Rejoués par packages/domaine/test/aib_test.dart sur packages/domaine/lib/src/comptabilite/aib.dart.
 * Non exporté : les identifiants et horodatages des fiches créées (seuls leur nombre et leurs champs métier le sont).
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du barème et des réglages de l’AIB');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Vrai = Date;
      window.__FIXE = new Vrai(2026, 7, 16, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      SIGH.ui.sonner = () => {};
    });
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, B = SIGH.baremeAib, RG = SIGH.reglagesAib, N = SIGH.nav;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const brut = () => S.raw();
      const net = (x) => { const c = propre(x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'creeLe', 'creePar', 'modifieLe', 'modifiePar', 'valideLe'].forEach((k) => { if (c && k in c) c[k] = c[k] ? '@' : c[k]; }); return c; };
      const SESSION = { role: 'comptable', fonction: 'comptable', nom: 'Comptable Vecteur', nomComplet: 'Comptable Vecteur', identifiant: 'comptable.vecteur', secteur: 'DIR' };
      S.setSession(SESSION);
      const NOMS = ['situationsAib', 'baremeAib', 'reglagesAib', 'comptes', 'fournisseurs', 'facturesFournisseurs', 'ecritures', 'validationsReferentiels'];
      const sauve = {};
      NOMS.forEach((n) => { S.collection(n).all(); sauve[n] = propre(brut()[n] || []); });
      const sous = (role, fileul, f) => {
        const avant = S.session(), reg = S.reglage('posteFileul', false);
        S.setSession(Object.assign({}, SESSION, { role }));
        S.setReglage('posteFileul', !!fileul);
        try { return f(); } finally { S.setSession(avant); S.setReglage('posteFileul', reg); }
      };
      const out = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-aib.js : SIGH.baremeAib et SIGH.reglagesAib pilotés dans Chrome, ne pas éditer. Horloge : 16/08/2026 10 h.' };
      out.aujourdhui = SIGH.core.iso(SIGH.core.aujourdhui());
      out.definitions = propre(SIGH.data.REGLAGES_AIB);
      out.semences = { situations: propre(brut().situationsAib), bareme: propre(brut().baremeAib), reglages: propre(brut().reglagesAib) };

      /* ---------- 1. le barème : taux à la date, situation d'après l'IFU, taux proposés ------------------------------------------------- */
      const nettoyer = (r) => { const c = propre(r); delete c.undo; return c; };
      out.tauxALaDate = [];
      ['ifu_actif', 'ifu_inactif_ou_absent', 'prestation_service', 'situation_inconnue'].forEach((s) => {
        ['2025-12-31', '2026-01-01', '2026-09-06', '2026-09-07', '2026-11-09'].forEach((d) => { out.tauxALaDate.push({ situation: s, date: d, sortie: nettoyer(B.aLaDate(s, d)) }); });
      });
      out.pourAcheteur = [];
      ['', '3201642748214', '123', ' 3201 6427 48214 ', '320164274821x'].forEach((ifu) => {
        ['2026-08-16', '2026-09-07'].forEach((d) => { out.pourAcheteur.push({ ifu, date: d, sortie: nettoyer(SIGH.parcours.tauxAibPourAcheteur({ ifu, date: d })) }); });
      });
      out.proposes = [['', '2026-11-09'], ['3201642748214', '2026-08-16'], ['', '2025-06-01']].map((a) => ({ ifu: a[0], date: a[1], sortie: nettoyer(SIGH.parcours.tauxAibProposes({ ifu: a[0], date: a[1] })) }));

      /* ---------- 2. les réglages : lecture, puis des gestes ENCHAÎNÉS ---------------------------------------------------------------- */
      brut().comptes = [{ id: 'CPT1', statut: 'actif', num: '447000', libelle: 'Etat impôts retenu à la source' }, { id: 'CPT2', statut: 'actif', num: '401110', libelle: 'Fournisseurs' },
        { id: 'CPT3', statut: 'archive', num: '411999', libelle: 'Compte archivé' }];
      brut().reglagesAib = propre(sauve.reglagesAib);
      const lire = (date) => ({ date, charge: nettoyer(RG.charge(date)), branchement: nettoyer(RG.branchement(date)),
        acompte: nettoyer(RG.aLaDate('compteAcompte', date)), contrepartie: nettoyer(RG.aLaDate('compteContrepartie', date)), inconnu: nettoyer(RG.aLaDate('inexistant', date)) });
      out.lectures = [];
      out.lectures.push(lire('2026-08-16'));
      out.gestes = [];
      out._ids = [];
      const geste = (nom, role, entree, opts) => {
        opts = opts || {};
        const r = sous(role, opts.fileul, () => RG.definir(entree));
        if (r && r.ok && r.id) out._ids.push(r.id);
        out.gestes.push({ nom, role, fileul: !!opts.fileul, entree: propre(entree), sortie: nettoyer(r), versions: propre(brut().reglagesAib.filter((x) => x.statut !== 'archive')).map(net) });
        return r;
      };
      const base = { dateEffet: '2026-08-16', motif: 'Vecteur' };
      geste('activation incomplète : ni comptes ni charge arrêtée', 'comptable', Object.assign({ cle: 'branchementAchats', valeur: 'actif' }, base));
      geste('réglage inconnu', 'comptable', Object.assign({ cle: 'inexistant', valeur: 'x' }, base));
      geste('valeur non admise', 'comptable', Object.assign({ cle: 'chargePrelevement', valeur: 'personne' }, base));
      geste('compte absent du plan', 'comptable', Object.assign({ cle: 'compteAcompte', valeur: '999999' }, base));
      geste('compte archivé du plan', 'comptable', Object.assign({ cle: 'compteAcompte', valeur: '411999' }, base));
      geste('motif absent', 'comptable', { cle: 'chargePrelevement', valeur: 'acheteur', dateEffet: '2026-08-16', motif: '  ' });
      geste('date illisible', 'comptable', { cle: 'chargePrelevement', valeur: 'acheteur', dateEffet: 'demain', motif: 'Vecteur' });
      geste('date d’effet déjà prise', 'comptable', { cle: 'chargePrelevement', valeur: 'acheteur', dateEffet: '2026-01-01', motif: 'Vecteur' });
      geste('la Direction n’écrit pas', 'direction', Object.assign({ cle: 'chargePrelevement', valeur: 'acheteur' }, base));
      geste('le caissier n’écrit pas', 'caissier', Object.assign({ cle: 'chargePrelevement', valeur: 'acheteur' }, base));
      geste('un fileul n’écrit pas', 'comptable', Object.assign({ cle: 'chargePrelevement', valeur: 'acheteur' }, base), { fileul: true });
      geste('la charge devient « acheteur » à effet du jour : l’ancienne se ferme à la veille, la nouvelle est arrêtée', 'comptable', Object.assign({ cle: 'chargePrelevement', valeur: 'acheteur', source: 'Vecteur' }, base));
      geste('compte d’acompte choisi', 'da', Object.assign({ cle: 'compteAcompte', valeur: '447000' }, base));
      geste('compte de contrepartie choisi', 'comptable', Object.assign({ cle: 'compteContrepartie', valeur: '401110' }, base));
      geste('date antérieure à la plus récente', 'comptable', { cle: 'compteAcompte', valeur: '447000', dateEffet: '2026-02-01', motif: 'Vecteur' });
      geste('activation : comptes et charge arrêtés, le branchement est actif', 'comptable', Object.assign({ cle: 'branchementAchats', valeur: 'actif' }, base));
      out.lectures.push(lire('2026-08-15'), lire('2026-08-16'), lire('2026-12-31'));

      /* ---------- 3. les achats : ce qu'il faudrait écrire, puis ce qui est écrit ------------------------------------------------------------ */
      brut().fournisseurs = [{ id: 'FO1', statut: 'actif', code: 'F-IFU', nom: 'Fournisseur avec IFU', ifu: '3201642748214' }, { id: 'FO2', statut: 'actif', code: 'F-SANS', nom: 'Fournisseur sans IFU' },
        { id: 'FO3', statut: 'actif', code: 'F-FAUX', nom: 'Fournisseur IFU illisible', ifu: '123' }];
      const FF = (id, ref, four, nom, date, montant, extra) => Object.assign({ id, statut: 'actif', reference: ref, fournisseur: four, fournisseurNom: nom, date, montantFacture: montant }, extra || {});
      brut().facturesFournisseurs = [
        FF('FF1', 'FF-A', 'F-IFU', 'Fournisseur avec IFU', '2026-06-10', 100000), FF('FF2', 'FF-B', 'F-SANS', 'Fournisseur sans IFU', '2026-06-10', 100000),
        FF('FF3', 'FF-C', 'F-SANS', 'Fournisseur sans IFU', '2026-10-10', 100000), FF('FF4', 'FF-D', 'F-IFU', 'Fournisseur avec IFU', '2026-10-10', 250050),
        FF('FF5', 'FF-E', 'F-SANS', 'Fournisseur sans IFU', '2025-03-10', 100000), FF('FF6', 'FF-F', 'F-FAUX', 'Fournisseur IFU illisible', '2026-06-10', 100000),
        FF('FF7', 'FF-G', 'F-IFU', 'Fournisseur avec IFU', '2026-07-01', 0), FF('FF8', 'FF-H', 'F-IFU', 'Fournisseur avec IFU', '2026-07-02', 100000, { statut: 'archive' }),
        FF('FF9', 'FF-I', 'INCONNU', 'Fournisseur absent du répertoire', '2026-07-03', 100000), FF('FF10', 'FF-J', 'F-IFU', 'Fournisseur avec IFU', '2027-01-05', 100000),
      ];
      brut().ecritures = [];
      const lignesEcrites = () => propre(brut().ecritures).map((e) => { const c = net(e); delete c.id; return c; });
      out.achats = {};
      const apercu = (o) => { const r = RG.achatsAEcrire(o); return nettoyer(r); };
      out.achats.apercuActif = { entree: { du: '2026-01-01', au: '2026-12-31' }, sortie: apercu({ du: '2026-01-01', au: '2026-12-31' }) };
      out.achats.apercuAvant2026 = { entree: { du: '2025-01-01', au: '2025-12-31' }, sortie: apercu({ du: '2025-01-01', au: '2025-12-31' }) };
      /* Le branchement est désactivé par un geste daté du 01/12 : la période arrêtée au 31/12 est alors sans écriture. */
      geste('désactivation à effet du 01/12/2026', 'comptable', { cle: 'branchementAchats', valeur: 'desactive', dateEffet: '2026-12-01', motif: 'Vecteur : retour au différé' });
      out.achats.apercuDesactive = { entree: { du: '2026-01-01', au: '2026-12-31' }, sortie: apercu({ du: '2026-01-01', au: '2026-12-31' }) };
      out.achats.refusDesactive = { entree: { du: '2026-01-01', au: '2026-12-31' }, sortie: nettoyer(sous('comptable', false, () => RG.ecrireAchats({ du: '2026-01-01', au: '2026-12-31' }))), ecritures: lignesEcrites() };
      out.achats.refusRole = { entree: { du: '2026-01-01', au: '2026-11-30' }, sortie: nettoyer(sous('caissier', false, () => RG.ecrireAchats({ du: '2026-01-01', au: '2026-11-30' }))), ecritures: lignesEcrites() };
      const ecrit = sous('comptable', false, () => RG.ecrireAchats({ du: '2026-01-01', au: '2026-11-30' }));
      const e1 = nettoyer(ecrit); if (e1.pieces) e1.pieces = e1.pieces.map((p) => ({ factureId: p.factureId, numero: p.numero, montant: p.montant }));
      out.achats.ecriture = { entree: { du: '2026-01-01', au: '2026-11-30' }, sortie: e1, ecritures: lignesEcrites() };
      const rejeu = sous('comptable', false, () => RG.ecrireAchats({ du: '2026-01-01', au: '2026-11-30' }));
      out.achats.rejeu = { sortie: { ok: rejeu.ok, pieces: (rejeu.pieces || []).length, refusees: rejeu.refusees }, nbEcritures: lignesEcrites().length };
      out.achats.apercuApresEcriture = { entree: { du: '2026-01-01', au: '2026-11-30' }, sortie: apercu({ du: '2026-01-01', au: '2026-11-30' }) };
      /* Une fiche de version ne se réécrit pas : la garde du magasin refuse la valeur, le réglage ou la date d'effet. */
      const v0 = brut().reglagesAib[0];
      const modif = S.collection('reglagesAib').update(v0.id, { valeur: 'acheteur' });
      out.versionFigee = { refusee: !modif || modif.ok === false || (S.collection('reglagesAib').get(v0.id) || {}).valeur === v0.valeur, valeurApres: S.collection('reglagesAib').get(v0.id).valeur === v0.valeur };

      NOMS.forEach((n) => { brut()[n] = sauve[n]; });
      S.save();
      return out;
    });
    /* Les identifiants des fiches CRÉÉES sont aléatoires : renommés dans l'ordre de leur CRÉATION (RAI-1, RAI-2…), comme le fait le test Dart. */
    let texte = JSON.stringify(sortie);
    sortie._ids.forEach((x, i) => { texte = texte.split(x).join('RAI-' + (i + 1)); });
    const final = JSON.parse(texte);
    delete final._ids;
    const nb = sortie.tauxALaDate.length + sortie.pourAcheteur.length + sortie.proposes.length + sortie.lectures.length + sortie.gestes.length + Object.keys(sortie.achats).length;
    console.log(`  ${nb} cas : ${sortie.tauxALaDate.length} taux, ${sortie.pourAcheteur.length} acheteurs, ${sortie.gestes.length} gestes, ${Object.keys(sortie.achats).length} états des achats`);
    if (m.erreurs.length) console.log('  avertissements de chargement : ' + m.erreurs.length);
    ecrire('packages/domaine/test/vecteurs/aib.json', final);
    /* Les SEMENCES du barème (situations et versions, `D.SITUATIONS_AIB`, `D.BAREME_AIB`) : lues sur le magasin amorcé, écrites en constantes Dart pour que
       le poste les sème telles quelles (une copie à la main divergerait au premier correctif). */
    const champs = (l, ks) => l.map((f) => '  {' + ks.filter((k) => f[k] !== undefined).map((k) => `'${k}': ${typeof f[k] === 'string' ? "'" + f[k].replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'" : f[k] === null ? 'null' : f[k]}`).join(', ') + '},').join('\n');
    const entete = '// ENGENDRÉ par prototype_html/build/vecteurs-aib.js (SIGH.data.SITUATIONS_AIB et BAREME_AIB, tels que la maquette les sème au socle), ne pas éditer.\n'
      + '// Les semences du barème de l\'AIB : trois situations de l\'acheteur et quatre versions datées, toutes « à valider » (aucun texte réglementaire au dépôt, Direction 09/11/2026).\n\n';
    const sit = final.semences.situations, bar = final.semences.bareme;
    const src = entete
      + 'const List<Map<String, Object?>> aibSituationsSemees = [\n' + champs(sit, ['id', 'code', 'libelle', 'declencheur', 'ordre', 'description']) + '\n];\n\n'
      + 'const List<Map<String, Object?>> aibBaremeSeme = [\n' + champs(bar, ['id', 'situation', 'taux', 'dateEffet', 'dateFin', 'source', 'motif']) + '\n];\n';
    ecrire('packages/domaine/lib/src/comptabilite/aib_donnees.dart', src);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
