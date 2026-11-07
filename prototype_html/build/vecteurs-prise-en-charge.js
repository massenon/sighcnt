/* =============================================================================
 * VECTEURS DE LA PRISE EN CHARGE (RG-09) — PR.repartir interrogé sur des situations CONNUES
 * -----------------------------------------------------------------------------
 * `PR.repartir` lit le magasin (couvertures datées, souscripteurs, garanties). On ne peut donc pas l'appeler « à vide » :
 * ce script POSE des fiches de test dans le magasin jetable de la maquette (assureurs ASS-A…ASS-E, jamais ceux du jeu),
 * appelle le moteur de la maquette, et enregistre pour chaque cas **les fiches d'entrée ET la sortie**. Le portage Dart
 * (`packages/domaine/lib/src/caisse/prise_en_charge.dart`) reçoit ces mêmes fiches en argument — il ne lit aucun magasin.
 *
 *   node build/vecteurs-prise-en-charge.js
 *
 * Sortie (ENGENDRÉE) : packages/domaine/test/vecteurs/prise_en_charge.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la prise en charge (RG-09)');
  const m = await ouvrirMaquette();
  try {
    const cas = await m.page.evaluate(() => {
      const S = SIGH.store, PR = SIGH.parcours;
      const colSous = S.collection('souscripteurs'), colGar = S.collection('garanties'), colCou = S.collection('couverturesAssurance');
      const propre = (x) => JSON.parse(JSON.stringify(x));
      const poser = (col, fiche) => col.insert(fiche).record;

      /* --- fiches de test ------------------------------------------------------------------ */
      const sA = poser(colSous, { nom: 'Employeur A', assureur: 'ASS-A', numeroPolice: 'PA-1', actesExclus: ['Hydrotubation'], produitsExclus: ['Vitamine C'], accordPrealable: ['Scanner'] });
      const sB = poser(colSous, { nom: 'Employeur B', assureur: 'ASS-B', numeroPolice: 'PB-1' });
      const sC = poser(colSous, { nom: 'Employeur C sans convention', assureur: 'ASS-C', numeroPolice: 'PC-1' });
      const sD = poser(colSous, { nom: 'Employeur D', assureur: 'ASS-D', numeroPolice: 'PD-1' });
      const gar = [
        poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-A', categorie: 'consultation', libelle: 'Consultation généraliste', taux: 80, plafond: 5000, unitePlafond: 'acte' }),
        poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-A', categorie: 'consultation', libelle: 'Consultation spécialiste ou professeur', taux: 80, plafond: 10000, unitePlafond: 'acte' }),
        poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-A', categorie: 'medicament', libelle: 'Médicaments', taux: 70, plafond: null }),
        poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-A', categorie: 'analyse', libelle: 'Analyses biologiques', taux: 100, plafond: 20000, unitePlafond: 'personne_an' }),
        poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-A', categorie: 'imagerie', libelle: 'Imagerie médicale', taux: 33, plafond: 50000, unitePlafond: 'personne_2ans' }),
        poser(colGar, { souscripteurId: sA.id, assureur: 'ASS-A', categorie: 'soin', libelle: 'Soins infirmiers', taux: 50, plafond: null }),
        poser(colGar, { souscripteurId: sB.id, assureur: 'ASS-B', categorie: 'consultation', libelle: 'Consultation', taux: 100, plafond: null }),
        /* garanties de la COMPAGNIE (sans souscripteur) : repli pour Employeur D */
        poser(colGar, { assureur: 'ASS-D', categorie: 'consultation', libelle: 'Consultation (compagnie)', taux: 60, plafond: 3000, unitePlafond: 'jour' }),
        /* une garantie ARCHIVÉE ne compte pas */
        Object.assign(poser(colGar, { souscripteurId: sB.id, assureur: 'ASS-B', categorie: 'analyse', libelle: 'Analyses (archivée)', taux: 100, plafond: null }), {}),
      ];
      const archivee = gar[gar.length - 1];
      S.collection('garanties').archive(archivee.id);
      /* Les fiches d'ENTRÉE sont relues APRÈS l'archivage : l'indicateur d'archive fait partie de ce que le moteur lit. */
      const garRelues = colGar.all().filter((g) => gar.some((x) => x.id === g.id));

      const patient = (id, extra) => Object.assign({ id, code: 'CNT/' + id + '/26', nom: 'TEST', prenom: id }, extra);
      const assure = (id, sous, expiration, extra) => patient(id, Object.assign({ assureur: sous.assureur, souscripteurId: sous.id, carteExpiration: expiration, tauxPriseEnCharge: 80 }, extra || {}));

      /* historique datés : P-HIST a changé d'employeur le 2026-06-01 (A avant, B après) */
      const pHist = assure('P-HIST', sB, '2027-12-31');
      const cou1 = poser(colCou, { patientId: 'P-HIST', patientCode: pHist.code, assureur: 'ASS-A', souscripteurId: sA.id, carteExpiration: '2026-12-31', debut: null, fin: '2026-05-31' });
      const cou2 = poser(colCou, { patientId: 'P-HIST', patientCode: pHist.code, assureur: 'ASS-B', souscripteurId: sB.id, carteExpiration: '2027-12-31', debut: '2026-06-01', fin: null });

      const L = (libelle, categorie, montant, extra) => Object.assign({ libelle, categorie, montant }, extra || {});
      const lignesA = [L('Consultation généraliste', 'consultation', 10000), L('Consultation spécialiste ou professeur', 'consultation', 20000), L('Paracétamol 500', 'medicament', 1500), L('Glycémie', 'analyse', 2000)];
      const defs = [
        ['non assuré : tout au patient', patient('P-NA'), '2026-08-16', lignesA],
        ['assuré, carte valide : deux consultations, deux plafonds différents (généraliste 5000, spécialiste 10000)', assure('P-1', sA, '2026-12-31'), '2026-08-16', lignesA],
        ['carte qui expire LE JOUR même : encore valide (comparaison à la date)', assure('P-2', sA, '2026-08-16'), '2026-08-16', lignesA],
        ['carte expirée la veille : facturation intégrale au patient (RG-09)', assure('P-3', sA, '2026-08-15'), '2026-08-16', lignesA],
        ['carte sans date d\'expiration : non valide', assure('P-4', sA, null), '2026-08-16', lignesA],
        ['assureur sans souscripteur rattaché', patient('P-5', { assureur: 'ASS-A', carteExpiration: '2026-12-31' }), '2026-08-16', lignesA],
        ['souscripteur sans aucune garantie saisie : « convention non saisie »', assure('P-6', sC, '2026-12-31'), '2026-08-16', lignesA],
        ['actes et produits exclus de la convention', assure('P-7', sA, '2026-12-31'), '2026-08-16', [L('Hydrotubation', 'soin', 30000), L('Vitamine C 500 mg', 'vitamine', 2500), L('Consultation généraliste', 'consultation', 10000)]],
        ['accord préalable requis et non obtenu / obtenu', assure('P-8', sA, '2026-12-31'), '2026-08-16', [L('Scanner cérébral', 'imagerie', 80000), L('Scanner cérébral', 'imagerie', 80000, { accordObtenu: true })]],
        ['catégorie sans garantie : motif nommé', assure('P-9', sA, '2026-12-31'), '2026-08-16', [L('Césarienne', 'chirurgie', 150000), L('Pansement', 'autre', 1000)]],
        ['arrondis : taux 33 % (330,33), taux 50 % sur 5 F (2,5 → 3), plafond atteint ou non', assure('P-10', sA, '2026-12-31'), '2026-08-16', [L('Échographie', 'imagerie', 1001), L('Pansement', 'soin', 5), L('Pansement', 'soin', 3), L('Échographie', 'imagerie', 400000), L('Bilan', 'analyse', 25000)]],
        ['historique datés : AVANT le changement d\'employeur (2026-05-15) → grille A', pHist, '2026-05-15', lignesA],
        ['historique datés : APRÈS le changement (2026-06-01) → grille B (100 %, sans plafond)', pHist, '2026-06-01', lignesA],
        ['historique datés : la veille du changement (2026-05-31) → encore A', pHist, '2026-05-31', lignesA],
        ['historique datés : une date avant toute période (couverture ouverte à debut:null → A)', pHist, '2020-01-01', lignesA],
        ['garanties de la COMPAGNIE en repli (souscripteur sans garantie propre)', assure('P-11', sD, '2026-12-31'), '2026-08-16', [L('Consultation', 'consultation', 10000), L('Analyse', 'analyse', 5000)]],
        ['la garantie archivée de B ne couvre rien', assure('P-12', sB, '2026-12-31'), '2026-08-16', [L('Glycémie', 'analyse', 2000), L('Consultation', 'consultation', 4000)]],
        ['montants texte, absents ou nuls : traités comme nombre ou zéro', assure('P-13', sA, '2026-12-31'), '2026-08-16', [L('Consultation généraliste', 'consultation', '10000'), L('Consultation généraliste', 'consultation', null), L('Consultation généraliste', 'consultation', 'abc'), { libelle: 'Sans catégorie', montant: 1000 }]],
        ['liste de lignes vide', assure('P-14', sA, '2026-12-31'), '2026-08-16', []],
        ['date avec heure (UTC) : la carte qui expire le jour même devient non valide à midi', assure('P-15', sA, '2026-08-16'), '2026-08-16T12:00:00Z', lignesA],
      ];

      const out = [];
      for (const [nom, p, date, lignes] of defs) {
        const idsP = p.id;
        const couvertures = colCou.all().filter((c) => c.patientId === idsP);
        /* Les ids du magasin servent à relier garanties et souscripteurs : on les conserve tels quels. */
        const r = PR.repartir(p, lignes, { date });
        out.push({
          entree: { nom, patient: propre(p), couvertures: propre(couvertures), souscripteurs: propre([sA, sB, sC, sD]), garanties: propre(garRelues), lignes: propre(lignes), date },
          sortie: propre({ lignes: r.lignes, souscripteurId: r.souscripteur ? r.souscripteur.id : null, carteValide: r.carteValide, grilleSaisie: r.grilleSaisie, total: r.total, partAssureur: r.partAssureur, partPatient: r.partPatient }),
        });
      }
      /* pas de patient du tout */
      const r0 = PR.repartir(null, [L('Consultation', 'consultation', 5000)], { date: '2026-08-16' });
      out.push({ entree: { nom: 'aucun patient', patient: null, couvertures: [], souscripteurs: [], garanties: [], lignes: [L('Consultation', 'consultation', 5000)], date: '2026-08-16' },
        sortie: propre({ lignes: r0.lignes, souscripteurId: null, carteValide: r0.carteValide, grilleSaisie: r0.grilleSaisie, total: r0.total, partAssureur: r0.partAssureur, partPatient: r0.partPatient }) });
      return out;
    });
    ecrire('packages/domaine/test/vecteurs/prise_en_charge.json', { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-prise-en-charge.js — sorties de PR.repartir (maquette) sur des fiches posées. Ne pas éditer.', cas });
    console.log(`  ${cas.length} cas`);
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
