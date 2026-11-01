/* =============================================================================
 * VECTEURS DE LA TRANSCRIPTION D'UNE PRESCRIPTION DU MOBILE (E1559, E1561)
 * -----------------------------------------------------------------------------
 * Une pièce `prescriptions` émise par le téléphone d'un soignant devient, au POSTE, une ordonnance + une facture de caisse + les files d'aval, par
 * `PR.prescrire` (le moteur de la fiche de consultation). `PR.transcrireMobile` y ajoute les refus nommés. Ce script PILOTE la maquette dans Chrome :
 * fixtures posées (patients, produits au stock connu, catalogue des analyses), pièces rejouées, ce que le moteur ÉCRIT (fiches nouvelles et champs
 * modifiés) ou le refus (code, motif, geste) est relevé tel quel.
 *   node build/vecteurs-transcription-mobile.js   →   packages/domaine/test/vecteurs/transcription_mobile.json
 *                                                     packages/domaine/lib/src/mobile/mob_transcription_donnees.dart
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

function litteralDart(x, indent) {
  const pad = '  '.repeat(indent || 0);
  if (x === null || x === undefined) return 'null';
  if (typeof x === 'string') return "'" + x.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n') + "'";
  if (typeof x === 'number' || typeof x === 'boolean') return String(x);
  if (Array.isArray(x)) {
    if (!x.length) return '<Object?>[]';
    return '[\n' + x.map((v) => pad + '  ' + litteralDart(v, (indent || 0) + 1) + ',').join('\n') + '\n' + pad + ']';
  }
  const ks = Object.keys(x);
  if (!ks.length) return '<String, Object?>{}';
  return '{\n' + ks.map((k) => pad + '  ' + litteralDart(k) + ': ' + litteralDart(x[k], (indent || 0) + 1) + ',').join('\n') + '\n' + pad + '}';
}

(async () => {
  console.log('▶ Vecteurs de la transcription d’une prescription du mobile');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, D = SIGH.data, PR = SIGH.parcours;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const db = () => S.raw();
      const WATCH = ['ordonnances', 'demandesAnalyses', 'factures', 'taches', 'notifications', 'prescriptions', 'demandesImagerie'];
      const poser = (nom, fiches) => { db()[nom] = propre(fiches); };
      const instantane = () => { const o = {}; WATCH.forEach((n) => { o[n] = propre(db()[n] || []); }); return o; };
      const IGN = new Set(['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe']);
      const net = (f) => { const c = propre(f); IGN.forEach((k) => delete c[k]); return c; };
      function ecart(avant, apres) {
        const inserts = {}, modifs = {};
        WATCH.forEach((n) => {
          const a = new Map((avant[n] || []).map((f) => [f.id, f]));
          (apres[n] || []).forEach((f) => {
            if (!a.has(f.id)) { (inserts[n] = inserts[n] || []).push(net(f)); return; }
            const b = a.get(f.id), patch = {};
            Object.keys(f).forEach((k) => { if (!IGN.has(k) && JSON.stringify(f[k]) !== JSON.stringify(b[k])) patch[k] = f[k]; });
            if (Object.keys(patch).length) (modifs[n] = modifs[n] || []).push({ id: f.id, patch: propre(patch) });
          });
        });
        return { inserts, modifs };
      }

      /* --- catalogues posés : produits au stock CONNU, patients de toutes les couvertures ----------------------------------------------- */
      const produits = S.collection('produits').active().filter((p) => p.categorie === 'medicament' && p.prixAchat > 0).slice(0, 3).map((p, i) => Object.assign(propre(p), { stockDetail: [10, 2, 50][i], stock: [10, 2, 50][i] }));
      const analyses = propre(D.ANALYSES);
      const PATS = [
        { id: 'PATX1', code: 'CNT/1001/26', nom: 'ALPHA', prenom: 'Une', sexe: 'F', dateNaissance: '1990-01-01', statut: 'actif' },
        { id: 'PATX2', code: 'CNT/1002/26', nom: 'BETA', prenom: 'Deux', sexe: 'M', dateNaissance: '1985-05-05', statut: 'actif', assureur: 'NSIA', assureurNom: 'NSIA', tauxPriseEnCharge: 80, carteExpiration: '2099-12-31' },
        { id: 'PATX3', code: 'CNT/1003/26', nom: 'GAMMA', prenom: 'Trois', sexe: 'F', dateNaissance: '1992-02-02', statut: 'actif', assureur: 'NSIA', assureurNom: 'NSIA', tauxPriseEnCharge: 80, carteExpiration: '2020-01-01' },
        { id: 'PATX4', code: 'CNT/1004/26', nom: 'DELTA', prenom: 'Quatre', sexe: 'M', dateNaissance: '1980-04-04', statut: 'actif', personnelId: 'EMP01' },
        /* carte valide au 20/08/2026 mais expirée au 05/09/2026 : RG-09 se lit à la DATE DE LA PRESCRIPTION, pas à celle de la transcription. */
        { id: 'PATX5', code: 'CNT/1005/26', nom: 'EPSILON', prenom: 'Cinq', sexe: 'F', dateNaissance: '1995-05-05', statut: 'actif', assureur: 'NSIA', assureurNom: 'NSIA', tauxPriseEnCharge: 80, carteExpiration: '2026-08-31' },
      ];
      function monter() {
        WATCH.forEach((n) => poser(n, []));
        poser('patients', PATS); poser('produits', produits); poser('couverturesAssurance', []);
      }
      async function essayer(f) { try { return { resultat: await f() }; } catch (e) { return { erreur: e.message, code: e.code || null, geste: e.geste || null }; } }

      const DATE = '2026-08-20T09:00:00.000Z';
      const ordo = (extra) => Object.assign({
        id: 'PIECE-1', nature: 'medicament', patientId: 'PATX1', patientCode: 'CNT/1001/26', patient: 'ALPHA Une', date: DATE, noteId: 'NOTE-1',
        lignes: [{ produitId: produits[0].id, medicament: produits[0].designation, quantite: 2, posologie: '1 cp x 3/j', dureeJours: 5 }],
        prescripteur: 'Dr YENI M’PO Florent', fonction: 'medecin', emise: true, origine: 'mobile',
      }, extra || {});
      const analyse = (extra) => Object.assign({
        id: 'PIECE-2', nature: 'analyse', patientId: 'PATX1', patientCode: 'CNT/1001/26', patient: 'ALPHA Une', date: DATE, noteId: 'NOTE-1',
        examens: ['NFS', 'Glycémie'], urgence: 'Non urgent', prescripteur: 'Dr YENI M’PO Florent', fonction: 'medecin', emise: true, origine: 'mobile',
      }, extra || {});
      const note = { id: 'NOTE-1', diagnostic: 'Paludisme simple', patientId: 'PATX1' };
      const lignesDe = (...qs) => qs.map(([i, q]) => ({ produitId: produits[i].id, medicament: produits[i].designation, quantite: q, posologie: '1 cp', dureeJours: 3 }));

      const cas = [];
      async function jouer(nom, piece, opts) {
        opts = opts || {};
        monter();
        if (opts.avant) await opts.avant();
        const avant = instantane();
        const r = await essayer(() => PR.transcrireMobile(propre(piece), { note: opts.sansNote ? null : note }));
        const e = ecart(avant, instantane());
        cas.push({
          nom, params: { piece: propre(piece), note: opts.sansNote ? null : propre(note) }, preparation: opts.preparation || null,
          sortie: Object.assign({ erreur: r.erreur || null, code: r.code || null, geste: r.geste || null,
            retour: r.resultat ? { deja: r.resultat.deja, ordonnanceNumero: r.resultat.ordonnance.numero, factureNumero: r.resultat.facture ? r.resultat.facture.numero : null, taches: r.resultat.taches.map((t) => t.type), demandes: r.resultat.demandes.length } : null }, e),
        });
      }

      await jouer('médecin, patient non assuré : ordonnance, facture, tâches encaissement et dispensation, au PRIX D’ACHAT du catalogue (RG-02)', ordo({ lignes: lignesDe([0, 2], [2, 3]) }));
      await jouer('patient assuré, carte valide : parts assureur et patient sur chaque ligne', ordo({ patientId: 'PATX2', patientCode: 'CNT/1002/26', lignes: lignesDe([0, 2]) }));
      await jouer('carte EXPIRÉE : facturation intégrale au patient (RG-09)', ordo({ patientId: 'PATX3', patientCode: 'CNT/1003/26' }));
      await jouer('RG-09 à la DATE de la prescription : carte valide au 20/08, transcrite plus tard, la part assureur est maintenue', ordo({ patientId: 'PATX5', patientCode: 'CNT/1005/26' }));
      await jouer('RG-09 à la date : prescription du 05/09, carte expirée depuis le 31/08 : intégral au patient', ordo({ patientId: 'PATX5', patientCode: 'CNT/1005/26', date: '2026-09-05T09:00:00.000Z' }));
      await jouer('agent de la clinique : prise en charge du personnel, jamais une créance', ordo({ patientId: 'PATX4', patientCode: 'CNT/1004/26' }));
      await jouer('analyses : une demande au laboratoire par examen, prélèvement bloqué jusqu’à la caisse', analyse());
      await jouer('analyses urgentes : l’ordonnance est urgente', analyse({ urgence: 'Urgent — bilan entier', examens: ['CRP'] }));
      await jouer('sage-femme : prescrit des analyses, secteur de la maternité', analyse({ fonction: 'sage_femme', prescripteur: 'Sage-femme X', examens: ['Test de grossesse (TBG)'] }));
      await jouer('sans note rattachée : le diagnostic est vide, la transcription se fait', ordo(), { sansNote: true });
      await jouer('infirmier : fonction non habilitée à prescrire des médicaments', ordo({ fonction: 'infirmier', prescripteur: 'Infirmière X' }));
      await jouer('aide-soignant : fonction non habilitée', analyse({ fonction: 'aide_soignant' }));
      await jouer('fonction absente de la pièce', ordo({ fonction: '' }));
      await jouer('nature « acte » : le mobile ne prescrit pas', ordo({ nature: 'acte', lignes: undefined }));
      await jouer('patient inconnu de la clinique : refusé en le disant, rien d’écrit', ordo({ patientCode: 'CNT/9999/26', patientId: 'PATZ' }));
      await jouer('médicament hors catalogue : refusé en le nommant', ordo({ lignes: [{ produitId: 'PRD-INCONNU', medicament: 'Inconnomol 500', quantite: 1, posologie: '1', dureeJours: 1 }] }));
      await jouer('ligne sans produit (texte libre de l’ancienne pièce) : refusée', ordo({ lignes: [{ medicament: 'Paracétamol 500 mg', posologie: '1 cp x 3/j', dureeJours: 5 }] }));
      await jouer('stock insuffisant : refus nommé (RG-03), jamais un stock négatif', ordo({ lignes: lignesDe([1, 3]) }));
      await jouer('stock insuffisant sur DEUX lignes du même produit : le cumul est refusé', ordo({ lignes: lignesDe([1, 2], [1, 1]) }));
      await jouer('stock exactement épuisé : accepté', ordo({ lignes: lignesDe([1, 2]) }));
      await jouer('quantité nulle : refusée', ordo({ lignes: lignesDe([0, 0]) }));
      await jouer('quantité non entière : refusée', ordo({ lignes: lignesDe([0, 1.5]) }));
      await jouer('ordonnance sans ligne', ordo({ lignes: [] }));
      await jouer('examen sans correspondance au catalogue du laboratoire : refusé', analyse({ examens: ['NFS', 'IRM cérébrale'] }));
      await jouer('demande sans examen', analyse({ examens: [] }));
      await jouer('pièce déjà transcrite : rien n’est réécrit', ordo(), {
        preparation: 'transcrite une première fois',
        avant: async () => { PR.transcrireMobile(propre(ordo()), { note: propre(note) }); },
      });

      return {
        _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-transcription-mobile.js : la transcription d’une prescription du mobile par PR.prescrire. Ne pas éditer.',
        catalogues: { produits, analyses, patients: PATS, correspondance: propre(PR.CORRESPONDANCE_EXAMENS_MOBILE) },
        cas,
      };
    });
    ecrire('packages/domaine/test/vecteurs/transcription_mobile.json', sortie);
    const corps = [
      '// ENGENDRÉ par prototype_html/build/vecteurs-transcription-mobile.js : la correspondance entre les examens du simulateur mobile et le catalogue',
      '// des analyses du laboratoire (PROPOSITION à valider par le biologiste). Ne pas éditer à la main : relancer le script.',
      '// ignore_for_file: prefer_single_quotes',
      'library;',
      '',
      '/// Examen du simulateur mobile -> code de l\'analyse du catalogue du laboratoire (`PR.CORRESPONDANCE_EXAMENS_MOBILE`).',
      'const Map<String, String> mobCorrespondanceExamens = ' + litteralDart(sortie.catalogues.correspondance, 0) + ';',
      '',
    ].join('\n');
    fs.writeFileSync(path.join(ROOT, '..', 'packages/domaine/lib/src/mobile/mob_transcription_donnees.dart'), corps);
    console.log('  cas : ' + sortie.cas.length + ' · refus : ' + sortie.cas.filter((c) => c.sortie.erreur).length);
    for (const c of sortie.cas) console.log('   ' + (c.sortie.erreur ? '✗ ' + c.sortie.code : '✓ ' + (c.sortie.retour && c.sortie.retour.ordonnanceNumero)) + '  ' + c.nom);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
