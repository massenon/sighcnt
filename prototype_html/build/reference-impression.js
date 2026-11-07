/* Références de l'IMPRESSION : géométrie du ticket 80 mm et de la feuille A4 rendus par la maquette (`SIGH.print`).
     node build/reference-impression.js → apps/poste/test/references/kit/impression.json */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');
(async () => {
  const m = await ouvrirMaquette();
  try {
    const r = await m.page.evaluate(() => {
      const rect = (e) => { if (!e) return null; const b = e.getBoundingClientRect(); return { x: +b.left.toFixed(1), y: +b.top.toFixed(1), l: +b.width.toFixed(1), h: +b.height.toFixed(1) }; };
      const hors = {};
      SIGH.print.ticket({ operateur: 'A', numero: 'F-1', date: new Date(2026, 9, 30, 14, 5), dossier: 'CNT/12/26', lignes: [{ designation: 'Consultation', quantite: 1, prixUnitaire: 3000, montant: 3000 }], total: 3000, partPatient: 3000, regle: 3000 });
      const t = [...document.querySelectorAll('.print-sheet')].pop();
      hors.ticket = rect(t);
      hors.ticketLignes = t.children.length;
      document.querySelectorAll('.print-sheet').forEach((s) => { if (s !== t) s.remove(); });
      t.remove();
      SIGH.print.etat({ titre: 'État de test', contenu: SIGH.print.tableau([{ label: 'Désignation' }, { label: 'Montant', align: 'right', somme: true, key: 'm' }], [{ m: 1000 }, { m: 250 }], { total: true }), signatures: [{ role: 'Le Caissier' }, { role: 'La DAF' }], filtres: false });
      const a = [...document.querySelectorAll('.print-sheet')].pop();
      hors.a4 = rect(a);
      hors.entete = rect(a.querySelector('.print-entete'));
      hors.titre = rect(a.querySelector('h1'));
      hors.pied = rect(a.querySelector('.print-pied'));
      hors.tableau = rect(a.querySelector('table'));
      hors.lignesTableau = a.querySelectorAll('table tr').length;
      return hors;
    });
    ecrire('apps/poste/test/references/kit/impression.json', { _doc: 'ENGENDRÉ par prototype_html/build/reference-impression.js — géométrie des gabarits imprimés de la maquette.', ...r });
    console.log(JSON.stringify(r));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
