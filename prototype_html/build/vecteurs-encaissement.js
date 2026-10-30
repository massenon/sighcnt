/* =============================================================================
 * VECTEURS DE L'ENCAISSEMENT — PR.encaisser (allocation, solde, base MECeF) et l'écriture comptable (RG-10)
 * -----------------------------------------------------------------------------
 * Le moteur de la maquette est appelé sur des factures posées au magasin jetable ; chaque cas est une SÉQUENCE de
 * versements (partiel, puis solde…) dont on enregistre l'état de la facture et les écritures APRÈS CHAQUE PAS.
 * Seul le cœur arithmétique est exporté : les effets sur le laboratoire, l'imagerie et les tâches d'aval (déblocage)
 * restent de l'orchestration du poste, couverte par les scénarios de la maquette.
 *
 *   node build/vecteurs-encaissement.js     →  packages/domaine/test/vecteurs/encaissement.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de l\'encaissement');
  const m = await ouvrirMaquette();
  try {
    const cas = await m.page.evaluate(() => {
      const S = SIGH.store, PR = SIGH.parcours;
      const colF = S.collection('factures');
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const ligne = (id, libelle, partPatient, partAssureur, categorie) => ({ id, libelle, categorie: categorie || 'consultation', montant: partPatient + (partAssureur || 0), partPatient, partAssureur: partAssureur || 0, statutPaiement: 'du' });
      let n = 0;
      const poser = (lignes, extra) => {
        n++;
        const dus = lignes.reduce((a, l) => a + l.partPatient, 0);
        const ass = lignes.reduce((a, l) => a + (l.partAssureur || 0), 0);
        return colF.insert(Object.assign({
          numero: 'FC-2026-' + String(900 + n).padStart(5, '0'), patient: 'TEST Patient', lignes,
          montantTTC: dus + ass, partPatient: dus, partAssureur: ass, montantPaye: 0, reliquat: dus,
          statutPaiement: 'impayee', statutMecef: 'en_attente', assureur: ass ? 'ASS-A' : null,
        }, extra || {})).record;
      };
      const trois = () => [ligne('L1', 'Consultation', 5000), ligne('L2', 'Glycémie', 3000, 0, 'analyse'), ligne('L3', 'Pansement', 2000, 0, 'soin')];
      /* Les écritures d'une facture se retrouvent par leur pièce, jamais par leur rang : la collection est amorcée à la demande. */
      const ecrituresDe = (id) => S.collection('ecritures').all().filter((e) => e.pieceId === id).map((e) => e.id);

      const defs = [
        ['une ligne nommée (la 2e) : partiel', trois(), [{ lignes: ['L2'] }]],
        ['toutes les lignes nommées : soldée, base MECeF = tout le versé', trois(), [{ lignes: ['L1', 'L2', 'L3'] }]],
        ['nommées en deux fois : partielle puis soldée, le cumul se lit sur la facture', trois(), [{ lignes: ['L3'] }, { lignes: ['L1'] }, { lignes: ['L2'] }]],
        ['montant 6000 : la 1re ligne (5000) passe, les autres (3000, 2000) ne tiennent pas dans 1000', trois(), [{ montant: 6000 }]],
        ['montant 8000 : 5000 + 3000, la 3e ne tient pas', trois(), [{ montant: 8000 }]],
        ['montant 7000 : 5000, la 2e (3000) saute, la 3e (2000) tient dans le reste', trois(), [{ montant: 7000 }]],
        ['montant 4000 : aucune ligne n\'est couverte ENTIÈREMENT : rien n\'est réglé', trois(), [{ montant: 4000 }]],
        ['montant omis : le dû total', trois(), [{}]],
        ['mode de règlement transmis', trois(), [{ lignes: ['L1'], mode: 'mobile_money' }]],
        ['ligne inconnue : rien réglé, aucune écriture', trois(), [{ lignes: ['ZZ'] }]],
        ['une ligne déjà réglée n\'est pas réglée deux fois', trois(), [{ lignes: ['L1'] }, { lignes: ['L1', 'L2'] }]],
        ['facture déjà soldée : « deja », rien ne bouge', trois(), [{ lignes: ['L1', 'L2', 'L3'] }, { lignes: ['L1'] }]],
        ['assuré : part assureur 7000 → écriture 571 + 411 / 706 équilibrée', [ligne('A1', 'Consultation', 2000, 8000), ligne('A2', 'Analyse', 1000, 6000, 'analyse')], [{ lignes: ['A1'] }, { lignes: ['A2'] }]],
        ['ligne 100 % assureur (part patient 0) : réglée par un versement nul', [ligne('B1', 'Consultation', 0, 5000), ligne('B2', 'Pansement', 1500)], [{ montant: 1500 }]],
        ['facture sans lignes (pièce antérieure au modèle) : partiel puis solde par montant', [], [{ montant: 3000 }, { montant: 99999 }], { montantTTC: 8000, partPatient: 8000, reliquat: 8000 }],
        ['facture sans lignes, sans partPatient : le TTC fait le dû', [], [{}], { montantTTC: 4500, partPatient: null, reliquat: 4500 }],
        ['numéro de facture sans chiffres : la pièce prend le rang suivant de la série annuelle', [ligne('C1', 'Consultation', 1000)], [{ lignes: ['C1'] }], { numero: null }],
      ];

      const out = [];
      for (const d of defs) {
        const [nom, lignes, pas, extra] = d;
        const f = poser(lignes, extra);
        const initiale = propre(f);
        /* Les écritures DÉJÀ au journal (série annuelle des numéros, créance assureur déjà constatée) font partie de l'entrée. */
        const existantes = propre(S.collection('ecritures').all().filter((e) => e.journal === 'CAI').map((e) => ({ numero: e.numero, pieceId: e.pieceId, compte: e.compte, statut: e.statut, journal: e.journal })));
        const etapes = [];
        for (const opts of pas) {
          const avant = new Set(ecrituresDe(f.id));
          const r = PR.encaisser(f.id, opts);
          const apres = S.collection('factures').get(f.id);
          const ecr = S.collection('ecritures').all().filter((e) => e.pieceId === f.id && !avant.has(e.id));
          etapes.push({
            opts: propre(opts),
            deja: !!r.deja,
            lignesReglees: (r.lignesReglees || []).map((l) => l.id),
            montantRegle: r.montantRegle === undefined ? null : r.montantRegle,
            restantDu: r.restantDu === undefined ? null : r.restantDu,
            facture: propre({
              lignes: (apres.lignes || []).map((l) => ({ id: l.id, statutPaiement: l.statutPaiement, montantRegle: l.montantRegle === undefined ? null : l.montantRegle })),
              montantPaye: apres.montantPaye, reliquat: apres.reliquat, modePaiement: apres.modePaiement, statutPaiement: apres.statutPaiement,
              statutMecef: apres.statutMecef, baseMecef: apres.baseMecef === undefined ? null : apres.baseMecef,
              dernierReglement: apres.dernierReglement ? { montant: apres.dernierReglement.montant, mode: apres.dernierReglement.mode, lignes: apres.dernierReglement.lignes } : null,
            }),
            ecritures: propre(ecr.map((e) => ({ numero: e.numero, date: e.date, journal: e.journal, compte: e.compte, libelle: e.libelle, debit: e.debit, credit: e.credit, statut: e.statut, origine: e.origine, pieceNumero: e.pieceNumero === undefined ? null : e.pieceNumero }))),
          });
        }
        out.push({ nom, ecrituresExistantes: existantes, facture: propre({ numero: initiale.numero === undefined ? null : initiale.numero, id: initiale.id, patient: initiale.patient, assureur: initiale.assureur, lignes: initiale.lignes, montantTTC: initiale.montantTTC, partPatient: initiale.partPatient, partAssureur: initiale.partAssureur, montantPaye: initiale.montantPaye, statutPaiement: initiale.statutPaiement }), etapes });
      }
      return out;
    });
    ecrire('packages/domaine/test/vecteurs/encaissement.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-encaissement.js — séquences de PR.encaisser (maquette). Ne pas éditer.', cas });
    console.log(`  ${cas.length} séquences, ${cas.reduce((a, c) => a + c.etapes.length, 0)} versements`);
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
