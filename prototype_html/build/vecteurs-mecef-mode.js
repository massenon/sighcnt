/* =============================================================================
 * VECTEURS DU MODE DE CERTIFICATION MECeF (lot L3, 10/11/2026) : SIGH.mecef.mode, SIGH.mecef.adaptateur et la vente en mode e-MECeF
 * -----------------------------------------------------------------------------
 * Décision de la Direction du 09/11/2026 : aucun numéro simulé ne se présente comme fiscal ; le mode se choisit (boîtier par défaut, ou e-MECeF) ;
 * e-MECeF s'affiche « non configuré : dossier d'interface DGI requis ». La maquette est PILOTÉE : on enregistre la résolution du mode pour quelques
 * valeurs lues en base, l'adaptateur en mode e-MECeF, et ce que laisse l'encaissement d'une vente soldée sous ce mode (refus nommé, pièce en attente,
 * AUCUN numéro, aucun essai consommé). Le domaine Dart rejoue ces vecteurs ; il porte aussi le refus du mode boîtier (écart assumé : la maquette garde
 * son appareil de démonstration en mode boîtier, le poste n'a aucun adaptateur), éprouvé par un test propre.
 *   node build/vecteurs-mecef-mode.js   →   packages/domaine/test/vecteurs/mecef_mode.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du mode de certification MECeF');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, M = SIGH.mecef, PR = SIGH.parcours;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      S.setSession(Object.assign({}, S.session(), { role: 'admin' }));

      /* 1. la résolution du mode lu en base : défaut sans réglage, valeur connue, valeur inconnue ramenée au défaut */
      const modes = [undefined, 'boitier', 'emecef', 'inconnu'].map((v) => {
        S.setReglage('mecefMode', v);
        return { reglage: v === undefined ? null : v, mode: M.mode() };
      });

      /* 2. l'adaptateur de chaque mode proposé (le boîtier de démonstration est configuré dans la maquette seule : seul l'e-MECeF est un vecteur) */
      S.setReglage('mecefMode', 'emecef');
      const adaptateurEmecef = propre(M.adaptateur());

      /* 3. une vente soldée, encaissée sous le mode e-MECeF */
      const L = (id, brut) => ({ id, categorie: 'acte', designation: 'Acte ' + id, quantite: 1, prixUnitaire: brut, prixUnitaireNet: brut, montantBrut: brut, remise: 0, montant: brut,
        partAssureur: 0, partPersonnel: 0, partPatient: brut, statutPaiement: 'du', montantRegle: 0 });
      const fac = S.collection('factures', { module: 'M8', entite: 'Facture' }).insert({ numero: 'FN-2099-V105', patientId: 'P105', patient: 'TEST Mode', patientCode: 'CNT/105/26',
        date: '2026-12-31', type: 'Consultation', lignes: [L('L001', 10000), L('L002', 4000)], montantHT: 14000, montantTTC: 14000, montantRemises: 0, partAssurance: 0,
        partPatient: 14000, montantPaye: 0, reliquat: 14000, modePaiement: 'especes', statutPaiement: 'impayee', statutMecef: 'en_attente', proforma: false }).record;
      const initiale = propre(fac); delete initiale.id;
      const numeros0 = ['factures', 'avoirs'].reduce((n, c) => n + S.collection(c).all().filter((x) => x.numeroMecef).length, 0);
      const appareil0 = S.reglage('mecefBoitier', { compteur: 0, emissions: [] });
      const r = PR.encaisser(fac.id, { mode: 'especes', acheteur: { ifu: '3201642748214', nom: 'Acheteur L3' } });
      const apres = S.collection('factures').get(fac.id);
      const numeros1 = ['factures', 'avoirs'].reduce((n, c) => n + S.collection(c).all().filter((x) => x.numeroMecef).length, 0);
      const appareil1 = S.reglage('mecefBoitier', { compteur: 0, emissions: [] });
      const vente = {
        piece: initiale,
        acheteur: { ifu: '3201642748214', nom: 'Acheteur L3' },
        normalisation: propre({ ok: r.normalisation.ok, code: r.normalisation.code, motif: r.normalisation.motif, geste: r.normalisation.geste, etat: r.normalisation.etat }),
        facture: propre({ statutPaiement: apres.statutPaiement, montantPaye: apres.montantPaye, statutMecef: apres.statutMecef, numeroMecef: apres.numeroMecef === undefined ? null : apres.numeroMecef,
          codeRetour: apres.codeRetour, motifRefusMecef: apres.motifRefusMecef, modeMecef: apres.modeMecef }),
        numerosFabriques: numeros1 - numeros0,
        emissionsAppareil: (appareil1.emissions || []).length - (appareil0.emissions || []).length,
      };
      S.setReglage('mecefMode', 'boitier');
      return { modes, adaptateurEmecef, vente };
    });
    ecrire('packages/domaine/test/vecteurs/mecef_mode.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-mecef-mode.js : mode MECeF et vente sous e-MECeF (maquette). Ne pas éditer.' }, sortie));
    console.log('  modes : ' + sortie.modes.map((x) => x.reglage + ' -> ' + x.mode).join(', '));
    console.log('  vente : ' + JSON.stringify(sortie.vente.facture));
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
