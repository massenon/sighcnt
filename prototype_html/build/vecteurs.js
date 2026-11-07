/* =============================================================================
 * VECTEURS DE TESTS — la maquette parle, la cible écoute
 * -----------------------------------------------------------------------------
 * « Une règle sans vecteur n'est pas portée. » Ce script interroge les fonctions PURES de la maquette
 * (formats, nombres en lettres, code patient, secteurs, périodes, états de résultat) sur des entrées
 * choisies, et enregistre les SORTIES TELLES QUE LA MAQUETTE LES DONNE — sans les juger. Le paquet Dart
 * `packages/domaine` rejoue les mêmes cas (`dart test`) : toute divergence est un défaut du portage, ou de la
 * maquette — et dans les deux cas elle se voit.
 *
 *   node build/vecteurs.js
 *
 * Sorties (ENGENDRÉES, versionnées) : packages/domaine/test/vecteurs/*.json
 * Ce qui n'est PAS encore exporté (il exige un magasin amorcé, donc un instantané complet) : PR.repartir,
 * PR.encaisser, SIGH.emettreAvoir, SIGH.exercice, SIGH.bfr — voir packages/domaine/test/vecteurs/README.md.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire } = require('./extraire');

const VALEURS = [0, 1, 7, 12, 999, 1000, 1001, 9999, 10000, 12345, 100000, 999999, 1000000, 1234567, 190830994, 2147483647,
  -1, -1500, -1234567, 0.4, 0.5, 1.5, 2.5, 999.5, 1e9, 3e9 + 5, '12000', '', null, undefined, 'abc', NaN];

(async () => {
  console.log('▶ Vecteurs de tests');
  const m = await ouvrirMaquette();
  try {
    const r = await m.page.evaluate((VALEURS) => {
      const C = SIGH.core, D = SIGH.data;
      const v = (x) => (x === undefined ? { indefini: true } : (typeof x === 'number' && !isFinite(x) ? { nombre: String(x) } : x));
      const dec = (x) => (x && x.indefini ? undefined : (x && x.nombre ? Number(x.nombre) : x));
      const cas = (entree, f) => { let sortie; try { sortie = f(); } catch (e) { sortie = { erreur: String(e.message) }; } return { entree, sortie }; };
      const sortieMoney = (s) => Array.from(s).map((c) => c.codePointAt(0).toString(16)).join(' '); // les espaces comptent : on garde les points de code
      const d = (a) => new Date(a[0], a[1], a[2], a[3] || 0, a[4] || 0, 0);
      const date = (dt) => dt.getFullYear() + '-' + String(dt.getMonth() + 1).padStart(2, '0') + '-' + String(dt.getDate()).padStart(2, '0') + 'T' + String(dt.getHours()).padStart(2, '0') + ':' + String(dt.getMinutes()).padStart(2, '0');

      const out = {};
      out['money'] = VALEURS.flatMap((x) => [true, false].map((devise) => {
        const e = { valeur: v(x), devise };
        return cas(e, () => { const s = C.money(dec(e.valeur), devise ? undefined : false); return { texte: s, pointsDeCode: sortieMoney(s) }; });
      }));
      out['num'] = [0, 1, 1234.5678, 1234567.891, -2.5, 0.005, 1.005, 2.675, 1e6, null, '3.14159'].flatMap((x) => [0, 1, 2, 3, undefined].map((dc) => {
        const e = { valeur: v(x), decimales: dc === undefined ? null : dc };
        return cas(e, () => C.num(dec(e.valeur), dc));
      }));
      out['pct'] = [0, 5, 12.345, 100, 0.04, -3].flatMap((x) => [undefined, 0, 2].map((dc) => cas({ valeur: x, decimales: dc === undefined ? null : dc }, () => C.pct(x, dc))));
      const nb = [0, 1, 2, 10, 11, 16, 17, 19, 20, 21, 22, 30, 31, 60, 61, 70, 71, 72, 77, 79, 80, 81, 90, 91, 99, 100, 101, 110, 180, 199, 200, 201, 280, 300, 999,
        1000, 1001, 1080, 1100, 2000, 2001, 21000, 80000, 80001, 100000, 101000, 200000, 999999, 1000000, 1000001, 2000000, 2500000, 21000000, 80000000, 190830994,
        1000000000, 2000000000, 3000000005, -5, 12.6, 12.4, '45', null];
      out['nombreEnLettres'] = nb.map((x) => cas({ valeur: x }, () => C.nombreEnLettres(x)));
      out['montantEnLettres'] = [0, 1, 1500, 5000, 21000, 80000, 123456, 1000000, 190830994].map((x) => cas({ valeur: x }, () => C.montantEnLettres(x)));
      out['codePatient'] = [[1, 2026], [530, 2025], [1234, 2099], [7, 1999], [10, 2000], [99999, 2026], [5, '2026'], [12, 26], [3, 5]].map((a) => cas({ ordre: a[0], annee: a[1] }, () => C.codePatient(a[0], a[1])));
      const dates = [[2026, 7, 16, 9, 5], [2026, 0, 1, 0, 0], [2025, 11, 31, 23, 59], [2024, 1, 29, 12, 0], [2026, 2, 8, 7, 30], [2000, 5, 15, 18, 45]];
      out['dates'] = dates.map((a) => cas({ date: a }, () => ({ dateFR: C.dateFR(d(a)), dateLong: C.dateLong(d(a)), dateJour: C.dateJour(d(a)), heure: C.heure(d(a)), dateHeure: C.dateHeure(d(a)), iso: C.iso(d(a)), moisAnnee: C.moisAnnee(d(a)) })));
      out['periodes'] = ['jour', 'semaine', 'mois', 'trimestre', 'semestre', 'annee', 'inconnue'].flatMap((p) => [[2026, 7, 16, 12, 0], [2026, 0, 3, 8, 0], [2024, 2, 1, 0, 0], [2025, 11, 31, 23, 0]].map((a) => cas({ periode: p, fin: a }, () => {
        const b = C.bornes(p, d(a)); return { debut: date(b.debut), fin: date(b.fin), label: b.label, jours: b.jours, libelle: C.libellePeriode(b) };
      })));
      out['periodesLibres'] = [[[2026, 7, 1], [2026, 7, 31]], [[2026, 7, 31], [2026, 7, 1]], [[2026, 0, 1], [2026, 0, 1]], [[2025, 11, 25], [2026, 0, 5]]].map((a) => cas({ du: a[0], au: a[1] }, () => {
        const b = C.bornesLibres(d(a[0]), d(a[1])); return { debut: date(b.debut), fin: date(b.fin), jours: b.jours, libelle: C.libellePeriode(b) };
      }));
      out['dansBornes'] = [[[2026, 7, 10], [2026, 7, 1], [2026, 7, 31]], [[2026, 7, 1], [2026, 7, 1], [2026, 7, 31]], [[2026, 7, 31, 0, 0], [2026, 7, 1], [2026, 7, 31, 0, 0]], [[2026, 8, 1], [2026, 7, 1], [2026, 7, 31]], [[2026, 6, 31], [2026, 7, 1], [2026, 7, 31]]]
        .map((a) => cas({ date: a[0], debut: a[1], fin: a[2] }, () => C.dansBornes(d(a[0]), { debut: d(a[1]), fin: d(a[2]) })));
      const cles = ['laboratoire', 'LABO', 'Laboratoire', 'pharmacie', 'Pharmacie', 'dispensation', 'medicament', 'médicament', 'maternité', 'Maternité', 'maternite', 'obstétrique', 'gynéco-obstétrique', 'Gynéco-obstétrique',
        'accouchement', 'cpn', 'PF', 'pf', 'imagerie', 'Imagerie médicale', 'échographie', 'Échographie', 'radiographie', 'ECG', 'scanner', 'IRM', 'mammographie',
        'consultation', 'Consultation', 'médecine générale', 'accueil', 'hospitalisation', 'Hospitalisation et soins', 'observation', 'soins', 'Soins et observation', 'chirurgie', 'bloc', 'urgence',
        'direction', 'Direction', 'entretien', 'ambulance', 'administration', '', null, undefined, 'xyz', 'LABORATOIRE D\'ANALYSES', 'Hôpital de jour'];
      out['secteurNormalise'] = cles.map((k) => cas({ cle: v(k) }, () => D.secteurNormalise(dec(v(k)))));
      out['resultatRendu'] = D.ETATS_RESULTAT.map((e) => e.id).concat(['inconnu', '', null]).map((id) => cas({ etat: id }, () => D.resultatRendu(id)));
      out['etatsResultat'] = [cas({}, () => D.ETATS_RESULTAT.map((e) => ({ id: e.id, label: e.label })))];
      return out;
    }, VALEURS);
    const dir = 'packages/domaine/test/vecteurs/';
    let total = 0;
    for (const [nom, cas] of Object.entries(r)) {
      total += cas.length;
      ecrire(dir + nom + '.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs.js — sorties de la MAQUETTE, telles quelles. Ne pas éditer.', cas });
    }
    console.log(`  ${Object.keys(r).length} familles · ${total} cas`);
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
