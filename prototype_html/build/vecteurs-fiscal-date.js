/* =============================================================================
 * VECTEURS DE LA CONFIGURATION FISCALE DATÉE (Direction, 06/11/2026)
 * -----------------------------------------------------------------------------
 * Quatre cas, TIRÉS DU MOTEUR RÉEL de la maquette (SIGH.configurationFiscale,
 * S.identiteALaDate, D.obligationsALaDate, S.genEcheances, calculOrtb de
 * m11-paie.js) monté dans Chrome sur la base jetable, jamais recopiés :
 *   identiteALaDate   : deux versions de l'identité, quatre dates ;
 *   obligationsALaDate: CCIB-2 passe du 10 au 15 à effet du 01/06/2026, trois dates ;
 *   echeancesVersion  : l'exercice avec changement en cours d'année (payée conservée,
 *                       non payée régénérée), et la génération complète ;
 *   calculOrtbDate    : seuil télé relevé à 80 000 au 01/08/2026, bulletins avant / après.
 * Horloge figée au 16/08/2026 10 h (la date du jeu de démonstration).
 *   SIGH_PORT_PHP=10398 SIGH_BASE_TEST=sigh_prototype_test_vf node build/vecteurs-fiscal-date.js
 *   → packages/domaine/test/vecteurs/fiscal-date.json
 * Rejoués par packages/domaine/test/cfb_regles_test.dart (cfbIdentiteALaDate,
 * cfbObligationsALaDate, cfbOrtbALaDate) et test/paie_test.dart (paiCalculOrtb daté).
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la configuration fiscale datée');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Vrai = Date;
      window.__Vrai = Vrai;
      window.__FIXE = new Vrai(2026, 7, 16, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      window.__erreurs = []; window.addEventListener('error', (e) => window.__erreurs.push(String(e.message)));
      SIGH.ui.sonner = () => {};
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m11-paie.js') });

    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, C = SIGH.core, D = SIGH.data, CF = SIGH.configurationFiscale, PA = SIGH.paie;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const net = (x) => { const c = Object.assign({}, x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'creeLe', 'creePar', 'modifieLe', 'modifiePar'].forEach((k) => delete c[k]); return propre(c); };
      const out = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-fiscal-date.js, ne pas éditer. Horloge : 16/08/2026 10 h. Moteur : SIGH.configurationFiscale, S.identiteALaDate, D.obligationsALaDate, S.genEcheances, SIGH.paie.calculOrtb.' };
      out.aujourdhui = C.iso(C.aujourdhui());

      /* 1. identiteALaDate : la semence (v1, depuis l'ouverture), une version 2 au 01/09/2026 (RCCM et adresse fiscale), quatre dates. */
      out.identiteALaDate = {};
      out.identiteALaDate.semence = net(S.collection('identiteLegale').active()[0]);
      const r1 = CF.nouvelleVersionIdentite({ rccm: 'RB/NAT/2026-B-999', bp: 'BP : 999 NATITINGOU (Rép. du Bénin)' }, { dateEffet: '2026-09-01', motif: 'Vecteur : nouveau RCCM et nouvelle adresse fiscale' });
      out.identiteALaDate.creation = { ok: r1.ok, version: r1.version, enForceAujourdhui: r1.enForceAujourdhui };
      out.identiteALaDate.versions = S.collection('identiteLegale').active().map((v) => ({ version: v.version, debut: v.debut || null, fin: v.fin || null, rccm: v.rccm, bp: v.bp, ifu: v.ifu, valideLe: v.valideLe || null }));
      out.identiteALaDate.dates = ['2020-01-01', '2026-08-16', '2026-08-31', '2026-09-01', '2026-12-31'].map((d) => {
        const i = C.identiteALaDate(d), v = S.identiteALaDate(d);
        return { date: d, version: v.version, rccm: i.rccm, bp: i.bp, ifu: i.ifu, nom: i.nom };
      });
      out.identiteALaDate.brandAujourdhui = { rccm: C.BRAND.rccm, bp: C.BRAND.bp };
      out.identiteALaDate.refus = {
        sansMotif: CF.nouvelleVersionIdentite({ rccm: 'X' }, { dateEffet: '2026-10-01' }).code,
        exerciceClos: CF.nouvelleVersionIdentite({ rccm: 'X' }, { dateEffet: '2025-10-01', motif: 'v' }).code,
        ifuFormat: CF.nouvelleVersionIdentite({ ifu: '123' }, { dateEffet: '2026-10-01', motif: 'v' }).code,
        memeDate: CF.nouvelleVersionIdentite({ rccm: 'X' }, { dateEffet: '2026-09-01', motif: 'v' }).code,
      };
      out.identiteALaDate.etat = propre(CF.etatConfigurationFiscale('identite'));

      /* 2. obligationsALaDate : CCIB-2 du 10 au 15 juin à effet du 01/06/2026 ; CCIB-2 remise due pour que la régénération ait une échéance à reprendre. */
      const col = S.collection('echeancesFiscales');
      const ccib2 = col.active().filter((e) => e.code === 'CCIB-2')[0];
      col.update(ccib2.id, { paye: false, datePaiement: null, reference: null, valideePar: null });
      out.obligationsALaDate = {};
      out.obligationsALaDate.avant = (function (o) { return { code: o.code, jour: o.jour, mois: o.mois, periodicite: o.periodicite, part: o.part, dateEffet: o.dateEffet || null }; })(CF.obligationsEnVigueur('2026-05-15').filter((o) => o.code === 'CCIB-2')[0]);
      out.obligationsALaDate.refus = {
        exerciceClos: CF.modifierObligation({ code: 'CCIB-2', valeurs: { jour: 15 }, dateEffet: '2025-06-01', motif: 'v' }).code,
        sansMotif: CF.modifierObligation({ code: 'CCIB-2', valeurs: { jour: 15 }, dateEffet: '2026-06-01' }).code,
        jourInvalide: CF.modifierObligation({ code: 'CCIB-2', valeurs: { jour: 40 }, dateEffet: '2026-06-01', motif: 'v' }).code,
        codeExistant: CF.creerObligation({ valeurs: { code: 'TVM', libelle: 'x', periodicite: 'annuelle', jour: 1, mois: 0 }, dateEffet: '2026-06-01', motif: 'v' }).code,
      };
      const r2 = CF.modifierObligation({ code: 'CCIB-2', valeurs: { jour: 15 }, dateEffet: '2026-06-01', motif: 'Vecteur : la DGI reporte la 2e tranche au 15' });
      out.obligationsALaDate.modification = { ok: r2.ok, code: 'CCIB-2', jour: 15, dateEffet: '2026-06-01' };
      out.obligationsALaDate.dates = ['2026-05-15', '2026-06-01', '2026-12-31'].map((d) => {
        const liste = CF.obligationsEnVigueur(d);
        const o = liste.filter((x) => x.code === 'CCIB-2')[0];
        return { date: d, jour: o.jour, dateEffet: o.dateEffet || null, nombreObligations: liste.length, codes: liste.map((x) => x.code) };
      });
      out.obligationsALaDate.historique = S.collection('historiqueObligations').active().filter((h) => h.code === 'CCIB-2')
        .map((h) => ({ jour: h.jour, dateEffet: h.dateEffet || null, dateFin: h.dateFin, retiree: !!h.retiree }));
      out.obligationsALaDate.fiche = (function (o) { return { jour: o.jour, dateEffet: o.dateEffet, valideLe: o.valideLe || null }; })(S.collection('obligationsFiscales').active().filter((o) => o.code === 'CCIB-2')[0]);

      /* 3. echeancesVersion : la régénération (payée conservée / non payée régénérée) et la génération complète de l'exercice. */
      out.echeancesVersion = {
        regeneration: propre(r2.echeances),
        magasinCcib: S.collection('echeancesFiscales').all().filter((e) => e.code === 'CCIB-1' || e.code === 'CCIB-2')
          .map((e) => ({ code: e.code, echeance: e.echeance, statut: e.statut, versionObligation: e.versionObligation || null, paye: !!e.paye, reference: e.reference || null }))
          .sort((a, b) => (a.code + a.echeance + a.statut).localeCompare(b.code + b.echeance + b.statut)),
        engendrees2026: S.genEcheances(2026, { aujourdhui: '2026-08-16' }).map((e) => ({ code: e.code, echeance: e.echeance, echeanceTheorique: e.echeanceTheorique, reportee: e.reportee, versionObligation: e.versionObligation || null, paye: e.paye, periode: e.periode })),
        engendrees2027: S.genEcheances(2027, { aujourdhui: '2026-08-16', sansReglement: true }).filter((e) => e.famille === 'CCIB').map((e) => ({ code: e.code, echeance: e.echeance, versionObligation: e.versionObligation || null })),
        retrait: (function () {
          const r = CF.retirerObligation({ code: 'TVM', dateEffet: '2026-07-01', motif: 'Vecteur : TVM retirée' });
          return { ok: r.ok, echeances: propre(r.echeances), enVigueurApres: CF.obligationsEnVigueur('2026-08-01').some((o) => o.code === 'TVM'), enVigueurAvant: CF.obligationsEnVigueur('2026-06-30').some((o) => o.code === 'TVM'),
            historique: S.collection('historiqueObligations').active().filter((h) => h.code === 'TVM').map((h) => ({ dateFin: h.dateFin, retiree: !!h.retiree })) };
        })(),
      };

      /* 4. calculOrtbDate : seuil 80 000 au 01/08/2026 ; un bulletin de juin reste à 3 000, un bulletin de septembre ne doit plus la télé. */
      const r3 = CF.modifierOrtb({ valeurs: { seuilTele: 80000 }, dateEffet: '2026-08-01', motif: 'Vecteur : seuil relevé' });
      const cas = [[70000, 5, '2026-06-01'], [70000, 5, '2026-09-01'], [70000, 2, '2026-06-01'], [70000, 2, '2026-09-01'],
        [50000, 5, '2026-06-01'], [60000, 5, '2026-06-01'], [60001, 5, '2026-06-01'], [80000, 5, '2026-09-01'], [80001, 5, '2026-09-01'], [90000, 2, '2026-09-01'], [70000, 5, null]];
      out.calculOrtbDate = {
        modification: { ok: r3.ok, seuilTele: 80000, dateEffet: '2026-08-01' },
        parametresAvant: propre(D.ortbALaDate('2026-07-31')), parametresApres: propre(D.ortbALaDate('2026-08-01')),
        cas: cas.map(([brut, mois, date]) => {
          const c = date ? PA.calculOrtb(brut, mois, date) : PA.calculOrtb(brut, mois);
          return { brut, mois, date, montant: c.montant, montantAnnuel: c.montantAnnuel, du: c.du, lignes: c.lignes.map((l) => ({ id: l.id, montant: l.montant, montantAnnuel: l.montantAnnuel, du: l.du })) };
        }),
        historique: S.collection('historiqueObligations').active().filter((h) => h.code === 'ORTB-PARAMETRES').map((h) => ({ seuilTele: h.seuilTele, dateFin: h.dateFin, cumulMaximum: h.cumulMaximum })),
      };

      /* 5. validation : réservée aux rôles de la Direction, et l'état qui en découle. */
      const sess = S.session();
      S.setSession(Object.assign({}, sess, { role: 'reception' }));
      out.validation = { reception: propre(CF.validerIdentite()).code };
      S.setSession(Object.assign({}, sess, { role: 'da', nom: 'TAKI Alimatou' }));
      const v = CF.validerObligations();
      out.validation.da = { ok: v.ok, nombre: v.nombre, validePar: v.validePar };
      out.validation.etatObligations = propre(CF.etatConfigurationFiscale('obligations')).etat;
      const r4 = CF.modifierObligation({ code: 'ITS', valeurs: { jour: 12 }, dateEffet: '2026-09-01', motif: 'Vecteur : après validation' });
      out.validation.apresModification = { ok: r4.ok, etat: propre(CF.etatConfigurationFiscale('obligations')).etat, regeneration: propre(r4.echeances) };
      S.setSession(sess);
      out.roles = CF.ROLES_VALIDATION;
      return out;
    });
    sortie.erreurs = await m.page.evaluate(() => window.__erreurs);
    ecrire('packages/domaine/test/vecteurs/fiscal-date.json', sortie);
    console.log('  erreurs de page : ' + sortie.erreurs.length);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
