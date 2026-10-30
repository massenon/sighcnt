/* =============================================================================
 * VECTEURS DE m6-reprise — « Reprise SAGE 100 » PILOTÉ comme le fait l'agent
 * -----------------------------------------------------------------------------
 * 1. Le RÉFÉRENTIEL (inventaire « Grand Stock » du 15/07/2026, lot d'import, catalogue tarifaire, rapprochement) est un référentiel statique de
 *    la maquette (`SIGH.sage`) : il est ENGENDRÉ en Dart (packages/domaine/lib/src/stock/donnees_sage.dart), jamais recopié.
 * 2. L'écran est monté pour de bon, avec la surcouche de valorisation du jeu (34 fiches) PUIS vide : KPI, lot, trois onglets, saisie d'une
 *    valorisation (modale, source obligatoire), correction, validation de la reprise, bordereau imprimé.
 *   node build/vecteurs-reprise.js   →   packages/domaine/test/vecteurs/reprise.json + lib/src/stock/donnees_sage.dart
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la reprise SAGE 100');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m6-stock.js') });
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, SG = SIGH.sage, D = SIGH.data;
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const META = ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statutAvantArchivage', '_archivePar', '_archiveLe'];
      const net = (x, retirer) => { const c = propre(x); META.concat(retirer || []).forEach((k) => delete c[k]); if (c.statut === 'actif') delete c.statut; return c; };
      const V = S.collection('valorisationsSage', { module: 'M6', entite: 'ValorisationSage', prefix: 'VSG' });
      const out = {};
      out.referentiel = {
        lot: propre(SG.LOT_IMPORT),
        articles: propre(SG.INVENTAIRE_SAGE.map((a) => Object.assign({}, a, { unite: SG.uniteDe(a.designation), seuil: SG.seuilPropose(a.quantite) }))),
        rapprochement: propre(SG.rapprochement()),
        categories: propre(D.CATEGORIES_PRODUIT.map((c) => ({ id: c.id, label: c.label }))),
      };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((d) => [...d.querySelectorAll('p')].map((p) => p.textContent.trim()));
      const vider = () => document.querySelectorAll('#toast-host > div').forEach((d) => d.remove());
      const fermer = () => document.querySelectorAll('.modal-root, [role=dialog]').forEach((x) => x.remove());
      const tables = (r) => [...r.querySelectorAll('table')].map((t) => ({
        entetes: [...t.querySelectorAll('thead th')].map((th) => th.innerText.replace(/\s+/g, ' ').trim()),
        lignes: [...t.querySelectorAll('tbody tr')].map((tr) => ({ cellules: [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim()), actions: [...tr.querySelectorAll('button')].map((b) => (b.title || b.getAttribute('aria-label') || '') + '|' + b.textContent.trim()) })),
      }));
      const texte = (r) => r.innerText.split('\n').map((x) => x.trim()).filter(Boolean);
      const clicOnglet = async (r, debut) => { const b = [...r.querySelectorAll('button')].find((x) => x.textContent.trim().startsWith(debut)); b.click(); await dormir(60); };
      const monter = async () => { const r = document.createElement('div'); document.body.appendChild(r); SIGH.screens['m6-reprise'].render(r); await dormir(150); return r; };
      const KPI = ['Articles repris', 'Unités en stock', 'Valeur reprise', 'Articles non valorisés', 'Valorisés par la clinique'];
      const lireKpi = (txt) => KPI.map((lab) => ({ libelle: lab, valeur: txt[txt.indexOf(lab) + 1], indice: /^(Prix de revient|Valorisation|aucune|\d)/.test(txt[txt.indexOf(lab) + 2] || '') || /ajoutés|saisie|Prix de revient|CMUP/.test(txt[txt.indexOf(lab) + 2] || '') ? txt[txt.indexOf(lab) + 2] : null }));
      async function lireTout(r) {
        const t0 = texte(r);
        const cas = { kpi: lireKpi(t0), lot: (() => { const d = t0.findIndex((x) => /^Éditer le bordereau/.test(x)) + 1; const f = t0.findIndex((x, i) => i > d && /^Articles repris/.test(x)); return t0.slice(d, f); })(), boutons: [...r.querySelectorAll('button')].map((b) => b.textContent.trim()).filter(Boolean).slice(0, 12) };
        cas.onglets = [...r.querySelectorAll('[role=tab], .tab, button')].map((b) => b.textContent.trim()).filter((x) => /^(Articles repris|Points à traiter|Rapprochement)/.test(x));
        cas.articles = { tables: tables(r), filtres: [...r.querySelectorAll('select')].map((s) => [...s.options].map((o) => o.textContent.trim())) };
        cas.articles.pied = t0.filter((x) => /Inventaire « Grand Stock »/.test(x));
        await clicOnglet(r, 'Points à traiter');
        const t1 = texte(r);
        cas.points = { texte: t1.filter((x) => /article\(s\)|Aucun document|seuil d’alerte/.test(x)), tables: tables(r) };
        await clicOnglet(r, 'Rapprochement');
        const t2 = texte(r);
        cas.rapprochement = { texte: t2, tables: tables(r) };
        return cas;
      }
      /* --- 1. L'état du jeu : la surcouche de valorisation est semée (34 fiches). --- */
      out.valorisationsSemees = V.active().length;
      let r = await monter();
      out.avecSurcouche = await lireTout(r);
      r.remove();
      /* --- 2. Surcouche vide : 34 références restent à valoriser. --- */
      const fiches = propre(V.active());
      V.all().forEach((v) => V.archive(v.id));
      r = await monter();
      out.sansSurcouche = await lireTout(r);
      await clicOnglet(r, 'Points à traiter');

      /* --- 3. La saisie d'une valorisation. --- */
      const premiere = () => [...r.querySelectorAll('tbody tr')].find((tr) => [...tr.querySelectorAll('button')].some((b) => (b.title || b.getAttribute('aria-label') || '') === 'Valoriser'));
      const champ = (id, v) => { const x = document.getElementById('f_' + id); x.value = v; x.dispatchEvent(new Event('input')); x.dispatchEvent(new Event('change')); };
      const bModale = (lib) => [...document.querySelectorAll('.modal-root button, [role=dialog] button')].find((b) => b.textContent.trim() === lib);
      const tr1 = premiere();
      const code1 = tr1.children[0].innerText.trim();
      [...tr1.querySelectorAll('button')].find((b) => (b.title || b.getAttribute('aria-label')) === 'Valoriser').click(); await dormir(50);
      const modale = document.querySelector('.modal-root, [role=dialog]');
      out.saisie = { code: code1, modale: modale.innerText.replace(/\s+/g, ' ').trim(), champs: [...modale.querySelectorAll('input, textarea')].map((x) => x.id + '=' + x.value) };
      vider(); bModale('Valoriser').click(); await dormir(50);
      out.saisie.videEncore = { modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]'), toasts: toasts(), fiches: V.active().length };
      champ('prixRevient', '850'); bModale('Valoriser').click(); await dormir(50);
      out.saisie.sansSource = { modaleOuverte: !!document.querySelector('.modal-root, [role=dialog]'), fiches: V.active().length };
      champ('source', 'Facture UBIPHARM n° 4471'); champ('observation', 'Relevé du 28/10');
      vider(); bModale('Valoriser').click(); await dormir(80);
      out.saisie.ok = { toasts: toasts(), fiche: net(V.active()[0], ['id']), fiches: V.active().length, lu: await lireTout(r) };
      vider(); fermer();
      /* --- 4. La correction (modale préremplie, « Corriger »). --- */
      await clicOnglet(r, 'Points à traiter');
      const trC = [...r.querySelectorAll('tbody tr')].find((tr) => tr.children[0].innerText.trim() === code1);
      [...trC.querySelectorAll('button')].find((b) => (b.title || b.getAttribute('aria-label')) === 'Corriger la valorisation').click(); await dormir(50);
      const modaleC = document.querySelector('.modal-root, [role=dialog]');
      out.correction = { modale: modaleC.innerText.replace(/\s+/g, ' ').trim(), champs: [...modaleC.querySelectorAll('input, textarea')].map((x) => x.id + '=' + x.value) };
      champ('prixRevient', '900'); vider(); bModale('Corriger').click(); await dormir(80);
      out.correction.apres = { toasts: toasts(), fiches: V.active().length, fiche: net(V.active().find((v) => v.code === code1), ['id']) };
      vider(); fermer();
      /* --- 5. La validation de la reprise. --- */
      const bVal = [...r.querySelectorAll('button')].find((b) => b.textContent.includes('Valider la reprise'));
      bVal.click(); await dormir(50);
      const modaleV = document.querySelector('.modal-root, [role=dialog]');
      out.validation = { modale: modaleV.innerText.replace(/\s+/g, ' ').trim() };
      const auditAvant = S.collection('audit').all().length;
      vider(); [...modaleV.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Valider la reprise').click(); await dormir(80);
      out.validation.apres = { toasts: toasts(), audit: S.collection('audit').all().slice(0, S.collection('audit').all().length - auditAvant || 3).slice(0, 2).map((a) => ({ action: a.action, module: a.module, entite: a.entite, reference: a.reference })) };
      vider(); fermer();
      /* --- 6. Le bordereau imprimé. --- */
      [...r.querySelectorAll('button')].find((b) => b.textContent.includes('Éditer le bordereau')).click(); await dormir(120);
      const ov = document.querySelector('.print-chrome');
      out.bordereau = { titre: ov.querySelector('.text-white').innerText.trim(), texte: ov.innerText.split('\n').map((x) => x.trim()).filter(Boolean) };
      out.bordereau.table = tables(ov)[0] ? { entetes: tables(ov)[0].entetes, lignes: tables(ov)[0].lignes.length, premieres: tables(ov)[0].lignes.slice(0, 3).map((l) => l.cellules), pied: [...ov.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.innerText.trim())) } : null;
      [...ov.querySelectorAll('button')].find((b) => b.textContent.includes('Fermer')).click();
      r.remove();
      /* La surcouche du jeu est rendue au magasin. */
      V.all().forEach((v) => V.archive(v.id));
      out.fichesDuJeu = fiches.length;
      return out;
    });
    ecrire('packages/domaine/test/vecteurs/reprise.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-reprise.js — m6-reprise piloté. Ne pas éditer.', ...Object.assign({}, sortie, { referentiel: undefined }) });
    const ref = sortie.referentiel;
    const dart = `/// ENGENDRÉ par prototype_html/build/vecteurs-reprise.js depuis \`SIGH.sage\` (data-sage.js) — ne pas éditer.
/// Référentiel STATIQUE de la reprise de l'inventaire « Grand Stock » (SAGE 100, arrêté au 15/07/2026) : lot d'import, ${ref.articles.length} articles,
/// ${ref.rapprochement.length} désignations du catalogue tarifaire déjà rapprochées, catégories de produit. Ce ne sont pas des collections : on ne les écrit pas.
library;

const donneesSageJson = r\'\'\'${JSON.stringify({ lot: ref.lot, articles: ref.articles, rapprochement: ref.rapprochement, categories: ref.categories })}\'\'\';
`;
    fs.mkdirSync(path.join(ROOT, '..', 'packages/domaine/lib/src/stock'), { recursive: true });
    fs.writeFileSync(path.join(ROOT, '..', 'packages/domaine/lib/src/stock/donnees_sage.dart'), dart);
    console.log('  écrit : packages/domaine/lib/src/stock/donnees_sage.dart (' + (dart.length / 1024).toFixed(0) + ' Ko)');
    console.log('  surcouche semée : ' + sortie.valorisationsSemees + ' · kpi avec ' + JSON.stringify(sortie.avecSurcouche.kpi.map((k) => k.valeur)) + ' · sans ' + JSON.stringify(sortie.sansSurcouche.kpi.map((k) => k.valeur)));
    console.log('  saisie : ' + JSON.stringify(sortie.saisie.ok.toasts) + ' · correction ' + JSON.stringify(sortie.correction.apres.toasts) + ' · validation ' + JSON.stringify(sortie.validation.apres.toasts));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
