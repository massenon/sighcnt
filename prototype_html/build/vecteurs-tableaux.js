/* =============================================================================
 * VECTEURS DE LA SORTIE DES TABLEAUX (lot EXP, 16/11/2026) : U.celluleSortie, U.sortirLignes, U.definirLimiteSortie, journal, CSV, noms datés, totaux
 * -----------------------------------------------------------------------------
 * La maquette est PILOTÉE sur un écran réel (« Factures », m8-factures, composant commun) : trois lignes cochées à l'écran, export .xlsx et .csv des lignes
 * cochées (octets interceptés, classeur relu par SIGH.xlsx.lire), puis les cas du moteur (typage des cellules, refus nommés, réglage de la limite, totaux
 * d'impression) appelés dans la MÊME page. Le domaine Dart (`packages/domaine/lib/src/tableaux/sortie_tableau.dart`) rejoue ces vecteurs.
 *   node build/vecteurs-tableaux.js   →   packages/domaine/test/vecteurs/tableaux_sortie.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');
const BANC = require('./_banc');

(async () => {
  console.log('▶ Vecteurs de la sortie des tableaux');
  const m = await ouvrirMaquette();
  try {
    const page = m.page;
    await page.goto(`http://127.0.0.1:${BANC.PORT_PHP}/pages/m8-factures.php`);
    await page.waitForFunction(() => window.SIGH && SIGH.ui && SIGH.ui.sortirLignes && document.querySelector('[data-tableau="factures"] tbody tr'), null, { timeout: 120000 });
    await page.evaluate(() => {
      window.__sorties = [];
      const orig = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function () {
        if (this.download && /^blob:/.test(this.href)) { const nom = this.download; fetch(this.href).then((r) => r.arrayBuffer()).then((b) => { window.__sorties.push({ nom, octets: Array.from(new Uint8Array(b)) }); }); return; }
        return orig.apply(this, arguments);
      };
    });
    /* 1. l'écran réel : trois lignes cochées, export .xlsx puis .csv des lignes cochées */
    await page.evaluate(() => { const cs = [...document.querySelectorAll('[data-tableau="factures"] tbody td[data-case-selection="ligne"] input')]; cs[0].click(); });
    await page.evaluate(() => { const cs = [...document.querySelectorAll('[data-tableau="factures"] tbody td[data-case-selection="ligne"] input')]; cs[2].click(); });
    await page.evaluate(() => { const cs = [...document.querySelectorAll('[data-tableau="factures"] tbody td[data-case-selection="ligne"] input')]; cs[4].click(); });
    for (const fmt of ['xlsx', 'csv']) {
      await page.evaluate(() => document.querySelector('[data-tableau="factures"] button[data-commande="exporter"]').click());
      await page.waitForSelector('[role="dialog"] button[data-format]');
      await page.evaluate((f) => document.querySelector('[role="dialog"] button[data-format="' + f + '"]').click(), fmt);
      await page.waitForFunction((n) => window.__sorties.length >= n, fmt === 'xlsx' ? 1 : 2, { timeout: 15000 });
    }
    const sortie = await page.evaluate(async () => {
      const U = SIGH.ui, S = SIGH.store, X = SIGH.xlsx, el = SIGH.core.el, C = SIGH.core;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const [sx, sc] = window.__sorties;
      const f = X.lire(new Uint8Array(sx.octets)).feuilles[0];
      /* la matrice relue, remise sous la forme des cellules du moteur (une date relue au format 14 redevient { date }) */
      const matrice = f.lignes.map((l, i) => l.map((v, j) => (i > 0 && f.formats[i][j] === 14 ? { date: X.versDate(v) } : v)));
      const csv = new TextDecoder('utf-8', { ignoreBOM: true }).decode(new Uint8Array(sc.octets));
      const journal = S.collection('audit').all().filter((x) => x.entite === 'Tableau').slice(0, 2).map((e) => ({ action: e.action, module: e.module, entite: e.entite, reference: e.reference,
        format: e.format, perimetre: e.perimetre, lignes: e.lignes, references: e.references, referencesTotal: e.referencesTotal, role: e.role, ecran: e.ecran, cible: e.cible, succes: e.succes }));
      const ecranReel = { fichierXlsx: sx.nom, feuille: f.nom, fichierCsv: sc.nom, matrice, csv, journal };

      /* 2. le typage d'une cellule : (valeur brute, texte montré) -> cellule */
      const devise = (C.BRAND && C.BRAND.devise) || 'FCFA';
      const casCellules = [
        { brut: 12500, montre: C.money(12500, false) }, { brut: 12500, montre: C.money(12500) }, { brut: -3000, montre: C.money(-3000, false) },
        { brut: 12500.4, montre: C.money(12500.4, false) }, { brut: 12.5, montre: '12,5' }, { brut: 45, montre: '45 %' }, { brut: 0.45, montre: '45 %' },
        { brut: 12, montre: 'Lit 12' }, { brut: 0, montre: '' }, { brut: 0, montre: '—' }, { brut: 7, montre: null },
        { brut: '2026-08-14', montre: C.dateFR('2026-08-14T12:00:00') }, { brut: '2026-08-14', montre: null }, { brut: '2026-08-14T09:30', montre: C.dateHeure(new Date('2026-08-14T09:30')) },
        { brut: '2026-08-14T09:30', montre: C.dateFR(new Date('2026-08-14T09:30')) }, { brut: '2026-08-14', montre: 'août 2026' },
        { brut: '+229 97 00 12 34', montre: '•• •• 12 34' }, { brut: 'Consultation', montre: 'Consultation' }, { brut: 'en_attente', montre: 'En attente' },
        { brut: true, montre: null }, { brut: false, montre: null }, { brut: null, montre: null }, { brut: 'texte  sur   deux  lignes', montre: 'texte  sur\n   deux  lignes' },
        { brut: 1500, montre: '1 500 ' + devise }, { brut: 1500, montre: '1 500 mL' },
      ].map((c) => {
        const col = c.montre === null ? { key: 'v', label: 'V' } : { key: 'v', label: 'V', text: () => c.montre };
        return Object.assign({}, c, { aucunTexte: c.montre === null, cellule: propre(U.celluleSortie(col, { v: c.brut })) });
      });

      /* 3. les refus du moteur, dans l'ordre (format, droit, vide, colonnes, limite) */
      const lignes = (n) => Array.from({ length: n }, (_, i) => ({ id: 'L' + i, numero: 'N' + i }));
      const col1 = [{ key: 'numero', label: 'N°' }];
      const avantLimite = S.reglage('exportLimiteLignes', undefined);
      const essais = [];
      const essai = async (nom, o, limite) => {
        S.setReglage('exportLimiteLignes', limite);
        const r = await U.sortirLignes(Object.assign({ colonnes: col1, nom: 'vecteur' }, o));
        essais.push({ nom, format: o.format, lignes: (o.lignes || []).length, colonnes: (o.colonnes || col1).length, limiteReglee: limite === undefined ? null : limite, limite: U.limiteSortie(), droit: U.peutSortir(),
          role: (S.session() || {}).role, libelleRole: (SIGH.nav.ROLES[(S.session() || {}).role] || {}).label, resultat: r.ok ? { ok: true } : { ok: false, code: r.code, motif: r.motif, geste: r.geste } });
      };
      await essai('format inconnu', { format: 'pdf', lignes: lignes(1) });
      await essai('vide', { format: 'csv', lignes: [] });
      await essai('sans colonne', { format: 'csv', lignes: lignes(2), colonnes: [] });
      await essai('à la limite', { format: 'csv', lignes: lignes(3) }, 3);
      await essai('au-delà de la limite', { format: 'csv', lignes: lignes(4) }, 3);
      await essai('au-delà de la limite, milliers', { format: 'xlsx', lignes: lignes(2501) }, 2500);
      await essai('limite illisible, défaut', { format: 'csv', lignes: lignes(2) }, 'beaucoup');
      await essai('limite hors bornes, défaut', { format: 'csv', lignes: lignes(2) }, 0);
      /* sans le droit : la fiche RBAC du caissier retire le geste ; la session devient caissier le temps de l'essai */
      const sess = S.session();
      const col = S.collection('rbac'); let fiche = col.all().filter((x) => x.role === 'caissier')[0]; const existait = !!fiche, gAvant = fiche ? JSON.stringify(fiche.droitsGestes || {}) : '{}';
      const g = Object.assign({}, (fiche && fiche.droitsGestes) || {}, { exporter_donnees: false });
      if (fiche) col.update(fiche.id, { droitsGestes: g }); else fiche = col.insert({ role: 'caissier', statut: 'actif', droitsGestes: g }).record;
      SIGH.nav.invaliderRbac();
      S.setSession(Object.assign({}, sess, { role: 'caissier' }));
      await essai('sans le droit', { format: 'xlsx', lignes: lignes(1) });
      S.setSession(sess);
      if (existait) col.update(fiche.id, { droitsGestes: JSON.parse(gAvant) }); else col.archive(fiche.id);
      SIGH.nav.invaliderRbac();
      S.setReglage('exportLimiteLignes', avantLimite);

      /* 4. le réglage de la limite */
      const reglages = [[3, ''], [0, 'm'], [100001, 'm'], [2.5, 'm'], ['', 'm'], ['abc', 'm'], [500, 'Sonde vecteurs']].map(([n, motif]) => {
        const r = U.definirLimiteSortie(n, motif);
        return { lignes: n, motif, resultat: r.ok ? { ok: true, lignes: r.lignes } : { ok: false, code: r.code, motif: r.motif, geste: r.geste } };
      });
      S.setReglage('exportLimiteLignes', avantLimite);

      /* 5. les totaux d'une impression (colonnes `somme`), calculés sur les lignes imprimées ; « non calculable » n'est pas zéro */
      const totaux = [];
      for (const cas of [{ lignes: [{ id: 'a', m: 1000, q: 2 }, { id: 'b', m: 2500, q: 1 }], nom: 'nombres' }, { lignes: [{ id: 'a', m: 1000, q: 2 }, { id: 'b', m: 'à voir', q: 1 }], nom: 'texte dans la colonne' }, { lignes: [{ id: 'a', m: 1000, q: 2 }, { id: 'b', m: null, q: 3 }], nom: 'cellule vide' }]) {
        await U.sortirLignes({ format: 'impression', colonnes: [{ key: 'id', label: 'Réf.' }, { key: 'm', label: 'Montant', align: 'right', somme: true }, { key: 'q', label: 'Qté', align: 'right', somme: true }], lignes: cas.lignes, nom: 'vecteur-totaux' });
        const s = document.querySelector('.print-sheet tfoot tr');
        totaux.push({ nom: cas.nom, lignes: cas.lignes, pied: s ? [...s.cells].map((c) => c.textContent) : null });
        document.querySelectorAll('.print-chrome').forEach((o) => o.remove());
      }
      /* 6. la série Excel d'une date (heure locale, jamais de fuseau dans ces cas) */
      const series = ['2026-08-14', '2026-08-14T09:30', '2026-08-14T09:30:15', '2026-08-14 23:59', '1900-03-01', '1900-02-28', 'pas une date', '2026-13-45'].map((iso) => ({ iso, serie: X.versSerie(iso) }));
      /* 7. la cellule d'un tableau dont on ne connaît que le texte montré (encarts, tableaux à la main) */
      const textes = [['12 500', true], [C.money(12500), true], ['12 500', false], ['14/08/2026', false], ['14/08/2026', true], ['45 %', true], ['1.234,5', true], ['12,5', true],
        ['—', true], ['', false], ['Lit 12', true], ['-3 000', true], ['  deux   espaces ', false], ['1 500 mL', true]].map(([texte, droite]) => ({ texte, droite, cellule: propre(U.celluleTexte(texte, droite)) }));
      return { ecranReel, cellules: casCellules, essais, reglages, totaux, series, textes, limiteDefaut: U.LIMITE_SORTIE_DEFAUT, geste: U.GESTE_SORTIE };
    });
    ecrire('packages/domaine/test/vecteurs/tableaux_sortie.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-tableaux.js : sortie des tableaux (maquette pilotée sur l’écran Factures). Ne pas éditer.' }, sortie));
    console.log('  écran réel : ' + sortie.ecranReel.fichierXlsx + ', ' + (sortie.ecranReel.matrice.length - 1) + ' lignes cochées, feuille « ' + sortie.ecranReel.feuille + ' »');
    console.log('  cellules : ' + sortie.cellules.length + ' · refus : ' + sortie.essais.map((e) => e.resultat.code || 'ok').join(', '));
    console.log('  réglages : ' + sortie.reglages.map((r) => r.resultat.code || 'ok').join(', ') + ' · totaux : ' + sortie.totaux.map((t) => JSON.stringify(t.pied)).join(' '));
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
