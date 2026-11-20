/* Vecteurs de l'IMPRESSION : le ticket 80 mm (`SIGH.print.ticket`) rendu par la maquette pour des entrées fixes, réduit à la suite de ses
   lignes de texte (paire « gauche|droite » ou texte seul). Le portage Dart (packages/domaine/lib/src/impression) doit produire la même suite.
     node build/vecteurs-impression.js   →   packages/domaine/test/vecteurs/ticket.json */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');
const ENTREES = [
  { nom: 'comptant simple', o: { operateur: 'DIEYABIDI Aïssatou', numero: 'F-2026-00012', dossier: 'CNT/12/26', date: [2026, 9, 30, 14, 5], lignes: [{ designation: 'Consultation généraliste', quantite: 1, prixUnitaire: 3000, montant: 3000 }, { designation: 'Paracétamol 500 mg', quantite: 2, prixUnitaire: 150, montant: 300 }], total: 3300, partPatient: 3300, regle: 5000, rendu: 1700 } },
  { nom: 'assuré, part non assurée, règlement partiel', o: { operateur: 'DIEYABIDI Aïssatou', numero: 'F-2026-00013-A', typeVente: 'CRÉDIT', assureur: 'NSIA', assure: 'KPOSSOU Awa', dossier: 'CNT/13/26', date: [2026, 9, 30, 9, 40], lignes: [{ designation: 'Échographie pelvienne', quantite: 1, prixUnitaire: 9000, montant: 9000 }, { designation: 'Certificat médical', quantite: 1, prixUnitaire: 2000, montant: 2000 }], total: 11000, remise: 500, partAssureur: 6300, partNonAssuree: 2000, partPatient: 4200, regle: 2000, baseMecef: 4200 } },
  { nom: 'sans dossier, MECeF', o: { operateur: 'ADJAHO Rose', numero: 'F-2026-00014', date: [2026, 0, 5, 8, 0], mecef: { nim: 'ET01234567', code: 'ABCD-1234-EFGH-5678', compteurs: '12/34 FV', heure: '08:00:12' }, lignes: [{ designation: 'Carnet de santé', quantite: 3, prixUnitaire: 500, montant: 1500 }], total: 1500, partPatient: 1500 } },
];
(async () => {
  console.log('▶ Vecteurs de l\'impression (ticket 80 mm)');
  const m = await ouvrirMaquette();
  try {
    const cas = [];
    for (const e of ENTREES) {
      const lignes = await m.page.evaluate((o) => {
        const d = o.date; o.date = new Date(d[0], d[1], d[2], d[3], d[4]);
        SIGH.print.ticket(o);
        const tous = document.querySelectorAll('.print-sheet'); const sheet = tous[tous.length - 1]; document.querySelectorAll('.print-sheet').forEach((s) => { if (s !== sheet) s.remove(); });
        const sortie = [];
        const lire = (n) => {
          if (n.tagName === 'P') { const t = n.textContent; if (!/^Réf\. CNT-/.test(t)) sortie.push(t); return; }
          const sp = n.querySelectorAll(':scope > span');
          if (n.tagName === 'DIV' && sp.length === 2 && n.classList.contains('justify-between')) { sortie.push(sp[0].textContent + '|' + sp[1].textContent); return; }
          if (n.tagName === 'DIV') n.querySelectorAll('p').forEach((p) => sortie.push(p.textContent));
        };
        [...sheet.children].forEach(lire);
        return sortie;
      }, JSON.parse(JSON.stringify(e.o)));
      cas.push({ nom: e.nom, entree: e.o, lignes });
    }
    ecrire('packages/domaine/test/vecteurs/ticket.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-impression.js — SIGH.print.ticket. date = [année, mois0, jour, h, min]. Ne pas éditer.', cas });
    console.log('  ' + cas.map((c) => c.nom + ' : ' + c.lignes.length + ' lignes').join(' · '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
