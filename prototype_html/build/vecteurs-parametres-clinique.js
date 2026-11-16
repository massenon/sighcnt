/* =============================================================================
 * VECTEURS DES PARAMÈTRES DE CLINIQUE (lot PARAM-CLINIQUE, 16/11/2026, décisions 10 et 14 de la Direction du 15/11/2026)
 * -----------------------------------------------------------------------------
 * La maquette est PILOTÉE sur son écran réel « Règles métier versionnées » (cfg-regles) : la carte des paramètres de clinique est lue telle que
 * l'écran la peint (valeurs semées, bornes, « Régler »), une version est posée par le moteur de l'écran (`SIGH.parametresClinique.definir`), puis
 * les lectures du socle (`D.parametreCliniqueALaDate`, `D.statutLotALaDate`, `D.trancheCreance`, `D.libellesTranches`) et les refus du contrôle
 * (`SIGH.parametresClinique.controler`) sont relevés dans la MÊME page. Le domaine Dart
 * (`packages/domaine/lib/src/parametres/parametres_clinique.dart`) rejoue ces vecteurs.
 *   node build/vecteurs-parametres-clinique.js   →   packages/domaine/test/vecteurs/parametres_clinique.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');
const BANC = require('./_banc');

(async () => {
  console.log('▶ Vecteurs des paramètres de clinique');
  const m = await ouvrirMaquette();
  try {
    const page = m.page;
    await page.goto(`http://127.0.0.1:${BANC.PORT_PHP}/pages/cfg-regles.php`);
    await page.waitForFunction(() => window.SIGH && SIGH.parametresClinique && document.querySelector('#page-content [data-parametre-clinique]'), null, { timeout: 120000 });
    const sortie = await page.evaluate(() => {
      const PC = SIGH.parametresClinique, D = SIGH.data, S = SIGH.store;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const r = {};
      /* 1. l'écran réel : ce que la carte peint au défaut semé */
      r.ecran = [...document.querySelectorAll('#page-content [data-parametre-clinique]')].map((x) => ({ cle: x.getAttribute('data-parametre-clinique'), texte: x.textContent.trim() }));
      r.definitions = propre(PC.definitions().map((d) => ({ cle: d.cle, defaut: d.defaut, min: d.min, max: d.max, unite: d.unite, libelle: d.libelle })));
      r.semence = propre(D.semenceParametresClinique().map((v) => ({ id: v.id, cle: v.cle, valeur: v.valeur, dateEffet: v.dateEffet })));
      /* 2. contrôles (bornes, entier, vide, cohérence des tranches) */
      const essais = [
        ['stock.delaiPeremptionJours', 90, {}], ['stock.delaiPeremptionJours', 1, {}], ['stock.delaiPeremptionJours', 730, {}], ['stock.delaiPeremptionJours', 0, {}],
        ['stock.delaiPeremptionJours', 731, {}], ['stock.delaiPeremptionJours', 12.5, {}], ['stock.delaiPeremptionJours', '', {}], ['stock.delaiPeremptionJours', null, {}],
        ['stock.delaiPeremptionJours', '45', {}], ['stock.delaiPeremptionJours', 'abc', {}], ['stock.delaiPeremptionJours', -3, {}],
        ['creances.trancheCourteJours', 45, { 'creances.trancheLongueJours': 90 }], ['creances.trancheCourteJours', 90, { 'creances.trancheLongueJours': 90 }],
        ['creances.trancheCourteJours', 100, { 'creances.trancheLongueJours': 90 }], ['creances.trancheCourteJours', 366, { 'creances.trancheLongueJours': 400 }],
        ['creances.trancheLongueJours', 30, { 'creances.trancheCourteJours': 30 }], ['creances.trancheLongueJours', 31, { 'creances.trancheCourteJours': 30 }],
        ['creances.trancheLongueJours', 1, { 'creances.trancheCourteJours': 30 }], ['creances.trancheLongueJours', 731, { 'creances.trancheCourteJours': 30 }],
        ['stock.inconnu', 10, {}],
      ];
      r.controles = essais.map(([cle, valeur, autres]) => { const x = PC.controler(cle, valeur, autres); return { cle, valeur, autres, code: x ? x.code : null }; });
      /* 3. tranches et libellés */
      const tr = [{ courte: 30, longue: 90 }, { courte: 45, longue: 90 }, { courte: 1, longue: 2 }, { courte: 60, longue: 365 }];
      r.tranches = [];
      tr.forEach((t) => { [-2, 0, 1, 2, 29, 30, 31, 44, 45, 46, 59, 60, 61, 89, 90, 91, 364, 365, 366, 1000].forEach((j) => r.tranches.push({ t, jours: j, tranche: D.trancheCreance(j, t) })); });
      r.libelles = tr.map((t) => ({ t, libelles: propre(D.libellesTranches(t)) }));
      /* 4. résolution à la date et statut des lots, la collection posée à l'identique d'un jeu de versions */
      const col = S.raw().parametresClinique;
      const avant = propre(col);
      const versions = [
        { id: 'PCL-001', statut: 'actif', cle: 'stock.delaiPeremptionJours', valeur: 90, dateEffet: null, creeLe: '2026-11-16' },
        { id: 'PCL-002', statut: 'actif', cle: 'creances.trancheCourteJours', valeur: 30, dateEffet: null, creeLe: '2026-11-16' },
        { id: 'PCL-003', statut: 'actif', cle: 'creances.trancheLongueJours', valeur: 90, dateEffet: null, creeLe: '2026-11-16' },
        { id: 'PCL-004', statut: 'actif', cle: 'stock.delaiPeremptionJours', valeur: 120, dateEffet: '2026-11-20', creeLe: '2026-11-16T10:00:00.000Z' },
        { id: 'PCL-005', statut: 'actif', cle: 'stock.delaiPeremptionJours', valeur: 60, dateEffet: '2026-12-01', creeLe: '2026-11-16T10:05:00.000Z' },
        { id: 'PCL-006', statut: 'actif', cle: 'stock.delaiPeremptionJours', valeur: 75, dateEffet: '2026-12-01', creeLe: '2026-11-16T10:06:00.000Z' },
        { id: 'PCL-007', statut: 'archive', cle: 'stock.delaiPeremptionJours', valeur: 5, dateEffet: '2026-11-18', creeLe: '2026-11-16T10:07:00.000Z' },
        { id: 'PCL-008', statut: 'actif', cle: 'creances.trancheCourteJours', valeur: 45, dateEffet: '2026-11-25', creeLe: '2026-11-16T10:08:00.000Z' },
      ];
      col.length = 0; versions.forEach((v) => col.push(Object.assign({}, v)));
      r.versions = propre(versions);
      r.resolutions = [];
      ['2026-01-01', '2026-11-16', '2026-11-18', '2026-11-19', '2026-11-20', '2026-11-25', '2026-11-30', '2026-12-01', '2027-06-01'].forEach((d) => {
        ['stock.delaiPeremptionJours', 'creances.trancheCourteJours', 'creances.trancheLongueJours'].forEach((cle) => {
          const x = D.parametreCliniqueALaDate(cle, d);
          r.resolutions.push({ cle, date: d, valeur: x.valeur, dateEffet: x.dateEffet, origine: x.origine, versionId: x.version ? x.version.id : null });
        });
      });
      r.lots = [];
      ['2026-11-16', '2026-11-20', '2026-12-01'].forEach((d) => {
        ['2026-11-15', '2026-11-16', '2026-11-17', '2027-01-30', '2027-02-14', '2027-02-15', '2027-02-16', '2027-03-20', '2027-03-21', '2027-04-01', ''].forEach((p) => {
          const l = p ? { datePeremption: p, statut: 'actif' } : { statut: 'alerte' };
          r.lots.push({ date: d, datePeremption: p || null, statutEcrit: l.statut, statut: D.statutLotALaDate(l, d) });
        });
      });
      col.length = 0; avant.forEach((v) => col.push(v));
      return r;
    });
    if (m.erreurs.length) throw new Error('erreurs JavaScript : ' + m.erreurs.join(' | '));
    ecrire('packages/domaine/test/vecteurs/parametres_clinique.json', sortie);
    console.log(`  ${sortie.controles.length} contrôles, ${sortie.tranches.length} tranches, ${sortie.resolutions.length} résolutions, ${sortie.lots.length} statuts de lot`);
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error(e); process.exit(1); });
