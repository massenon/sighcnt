/* =============================================================================
 * VECTEURS DU LOT TARIF-FIX-2 : prescrire toujours, bloquer seulement l'encaissement d'une ligne sans prix (Direction, 16/11/2026)
 * -----------------------------------------------------------------------------
 * Le moteur de la maquette est appelé dans la page réelle (magasin jetable) :
 *   - `manque`     : ce que `manqueDePrix` écrit sur une ligne (prix d'achat, tarif ; motif et geste mot pour mot) ;
 *   - `totaux`     : `totauxPiece` (somme des lignes, ou NULS dès qu'une ligne est sans prix) ;
 *   - `reglage`    : `encaissementPartielALaDate` (versions datées, défaut semé « non ») ;
 *   - `mecef`      : la fonction unique des montants refuse une ligne sans prix (PRIX_MANQUANT) ;
 *   - `encaisser`  : SÉQUENCES de `PR.encaisser` sur des pièces en attente de prix, réglage « non » puis « oui » (refus nommé, lignes réglées, reste dû) ;
 *   - `valoriser`  : `valoriserFacture` quand le prix est en vigueur à la date de la pièce (lignes, parts, totaux), et quand il ne l'est pas.
 *
 *   node build/vecteurs-prix-manquant.js     →  packages/domaine/test/vecteurs/prix_manquant.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs du lot TARIF-FIX-2 (prix manquant)');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const S = SIGH.store, PR = SIGH.parcours, T = PR._tf2;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const out = { manque: [], totaux: [], reglage: [], mecef: [], encaisser: [], valoriser: [] };

      /* --- manque --- */
      [
        ['prix d’achat absent (motif de l’accesseur)', ['prix_achat', 'MED-1', 'Paracétamol 500', { motif: 'Le prix d’achat de « Paracétamol 500 » n’est pas renseigné (à valider) : l’article ne se facture jamais à zéro.' }]],
        ['prix d’achat : produit inconnu', ['prix_achat', 'MED-2', 'Article', { motif: 'Produit inconnu.' }]],
        ['prix d’achat sans motif', ['prix_achat', 'MED-3', null, null]],
        ['tarif lu au référentiel (cause, motif, geste, effectif le)', ['tarif', 'ACT-1', 'Acte', { cause: 'version-future', motif: '« ACT-1 » Acte : prix à définir, effectif le 20/08/2026', geste: 'Attendre.', effectifLe: '2026-08-20' }]],
        ['tarif sans lecture', ['tarif', 'ACT-2', 'Acte deux', null]],
      ].forEach(([nom, a]) => out.manque.push({ nom, entree: { nature: a[0], code: a[1], libelle: a[2], r: propre(a[3]) }, sortie: propre(T.manqueDePrix(a[0], a[1], a[2], a[3])) }));

      /* --- totaux --- */
      const L = (id, montant, pa, pp, statut, manque) => Object.assign({ id, montant, montantBrut: montant, partAssureur: pa, partPersonnel: 0, partPatient: pp, statutPaiement: statut || 'du' }, manque ? { prixManquant: manque } : {});
      const mq = T.manqueDePrix('tarif', 'ZZ1', 'Acte sans prix', null);
      [
        ['toutes tarifées, une réglée', [L('L001', 5000, 4000, 1000, 'paye'), L('L002', 3000, 0, 3000)]],
        ['une ligne sans prix : totaux nuls', [L('L001', 5000, 0, 5000), L('L002', null, null, null, 'du', mq)]],
        ['aucune ligne', []],
      ].forEach(([nom, lignes]) => out.totaux.push({ nom, lignes: propre(lignes), sortie: propre(T.totauxPiece(lignes)) }));

      /* --- reglage --- */
      const brut = S.reglage('caisseEncaissementPartielSansPrix', null);
      [
        ['aucune version écrite : défaut semé « non »', null, '2026-08-16'],
        ['une version « oui » datée du 10/08 : lue le 16/08', [{ valeur: 'non', dateEffet: '2026-01-01', source: 's', par: 'semence' }, { valeur: 'oui', dateEffet: '2026-08-10', source: 'motif' }], '2026-08-16'],
        ['une version « oui » future : la précédente fait foi', [{ valeur: 'non', dateEffet: '2026-01-01', source: 's', par: 'semence' }, { valeur: 'oui', dateEffet: '2026-09-01', source: 'motif' }], '2026-08-16'],
      ].forEach(([nom, versions, jour]) => {
        if (versions) S.setReglage('caisseEncaissementPartielSansPrix', versions); else { const d = S.raw(); if (d._reglages) delete d._reglages.caisseEncaissementPartielSansPrix; }
        out.reglage.push({ nom, versions: propre(versions), jour, sortie: propre(PR.encaissementPartielALaDate(jour)) });
      });

      /* --- mecef --- */
      [
        ['ligne marquée sans prix', [{ designation: 'Acte sans prix', quantite: 1, prixUnitaire: null, prixManquant: true }]],
        ['prix unitaire nul sans montant', [{ designation: 'Ligne nulle', quantite: 1, prixUnitaire: null }]],
        ['ligne tarifée : passe', [{ designation: 'Consultation', quantite: 1, prixUnitaire: 5000 }]],
      ].forEach(([nom, lignes]) => out.mecef.push({ nom, lignes: propre(lignes), sortie: propre(PR.mecef.montants({ lignes })) }));

      /* --- encaisser : pièces en attente de prix --- */
      const colF = S.collection('factures');
      let n = 0;
      const poser = (lignes) => {
        n++;
        const t = T.totauxPiece(lignes);
        return colF.insert(Object.assign({ numero: 'FP-2026-' + String(950 + n).padStart(5, '0'), date: '2026-08-14', patient: 'TEST Patient', lignes, montantPaye: 0, statutPaiement: 'impayee', statutMecef: 'en_attente' }, t)).record;
      };
      const mqA = Object.assign(T.manqueDePrix('tarif', 'ZZTF2A', 'Acte sonde', null), { voie: 'acte' });
      const mqM = T.manqueDePrix('prix_achat', 'ZZTF2M', 'Médicament sonde', { motif: 'Produit inconnu.' });
      const sansPrix = (id, cat, m0) => ({ id, categorie: cat, designation: m0.libelle, quantite: 1, prixUnitaire: null, prixUnitaireNet: null, montantBrut: null, remise: 0, motifRemise: null, montant: null,
        partAssureur: null, partPersonnel: null, partPatient: null, prixManquant: m0, demandeId: null, produitId: null, acteCode: cat === 'acte' ? m0.code : null, demandeImagerieId: null, statutPaiement: 'du', montantRegle: 0, payeLe: null, payePar: null });
      const tarifee = (id, montant) => ({ id, categorie: 'acte', designation: 'Consultation', quantite: 1, prixUnitaire: montant, prixUnitaireNet: montant, montantBrut: montant, remise: 0, motifRemise: null, montant,
        partAssureur: 0, partPersonnel: 0, partPatient: montant, demandeId: null, produitId: null, acteCode: 'CONS-X', demandeImagerieId: null, statutPaiement: 'du', montantRegle: 0, payeLe: null, payePar: null });
      const defs = [
        ['réglage « non » : par lignes, la pièce entière attend (refus nommé)', 'non', [tarifee('L001', 5000), sansPrix('L002', 'acte', mqA)], [{ lignes: ['L001', 'L002'] }, { lignes: ['L001'] }, { montant: 5000 }, {}]],
        ['réglage « non » : deux lignes sans prix (acte et médicament) nommées', 'non', [sansPrix('L001', 'acte', mqA), sansPrix('L002', 'medicament', mqM), tarifee('L003', 2000)], [{ lignes: ['L003'] }]],
        ['réglage « oui » : la ligne sans prix refusée, la tarifée réglée seule (pièce partielle, reste non calculable)', 'oui', [tarifee('L001', 5000), sansPrix('L002', 'acte', mqA)], [{ lignes: ['L002'] }, { lignes: ['L001'] }, { lignes: ['L002'] }]],
        ['réglage « oui » : par montant, seules les lignes tarifées sont allouées', 'oui', [tarifee('L001', 5000), sansPrix('L002', 'acte', mqA), tarifee('L003', 1500)], [{ montant: 99999 }, {}]],
        ['réglage « oui » : il ne reste que des lignes sans prix (refus nommé)', 'oui', [sansPrix('L001', 'acte', mqA)], [{}]],
      ];
      for (const [nom, reglage, lignes, pas] of defs) {
        S.setReglage('caisseEncaissementPartielSansPrix', [{ valeur: 'non', dateEffet: '2026-01-01', source: 's', par: 'semence' }].concat(reglage === 'oui' ? [{ valeur: 'oui', dateEffet: '2026-01-02', source: 'vecteur' }] : []));
        const f = poser(propre(lignes));
        PR.valoriserFacture(f.id);
        const initiale = propre(colF.get(f.id));
        const etapes = [];
        for (const opts of pas) {
          const r = PR.encaisser(f.id, opts);
          const apres = colF.get(f.id);
          etapes.push({ opts: propre(opts), refusCode: r.refusNomme ? r.refusNomme.code : null, refus: r.refus || null, lignesReglees: (r.lignesReglees || []).map((l) => l.id),
            montantRegle: r.montantRegle === undefined ? null : r.montantRegle, restantDu: r.restantDu === undefined ? null : r.restantDu,
            facture: propre({ statutPaiement: apres.statutPaiement, reliquat: apres.reliquat, montantPaye: apres.montantPaye, lignes: apres.lignes.map((l) => ({ id: l.id, statutPaiement: l.statutPaiement })) }) });
        }
        out.encaisser.push({ nom, partiel: reglage === 'oui', facture: propre({ id: initiale.id, numero: initiale.numero, date: initiale.date, patient: initiale.patient, lignes: initiale.lignes, montantTTC: initiale.montantTTC, partPatient: initiale.partPatient, montantPaye: 0, statutPaiement: 'impayee' }), etapes });
      }
      if (brut === null) { const d = S.raw(); if (d._reglages) delete d._reglages.caisseEncaissementPartielSansPrix; } else S.setReglage('caisseEncaissementPartielSansPrix', brut);

      /* --- valoriser : un acte tarifé APRÈS la pièce, à sa date ; un acte toujours sans prix ; le taux de la pièce --- */
      const jour = '2026-08-14';
      const code = 'ZZTF2V', codeNon = 'ZZTF2N';
      S.collection('tarifs').insert({ id: code, code, codeActe: code, libelle: 'Acte à valoriser', famille: 'ACTE', statut: 'actif' });
      S.collection('versionsTarif').insert({ id: code + '@' + jour + '@1', code, version: 1, dateEffet: jour, statut: 'valide', etatAssure: 'unique', prixNonAssure: 3700 });
      SIGH.data.TARIFS.invalider();
      const mV = Object.assign(T.manqueDePrix('tarif', code, 'Acte à valoriser', null), { voie: 'acte' });
      const mN = Object.assign(T.manqueDePrix('tarif', codeNon, 'Acte toujours sans prix', null), { voie: 'acte' });
      [
        ['prix en vigueur à la date de la pièce : valorisée, totaux calculés, part assureur au taux de la pièce', [tarifee('L001', 2000), sansPrix('L002', 'acte', mV)], { tauxPriseEnCharge: 80 }],
        ['un acte reste sans prix : la valorisation garde la pièce en attente', [sansPrix('L001', 'acte', mV), sansPrix('L002', 'acte', mN)], {}],
        ['agent de la clinique : la ligne valorisée va au personnel', [sansPrix('L001', 'acte', mV)], { personnelId: 'EMP01' }],
      ].forEach(([nom, lignes, extra]) => {
        n++;
        const t = T.totauxPiece(lignes);
        const f = colF.insert(Object.assign({ numero: 'FP-2026-' + String(950 + n).padStart(5, '0'), date: jour, patient: 'TEST Patient', lignes: propre(lignes), montantPaye: 0, statutPaiement: 'impayee', statutMecef: 'en_attente' }, t, extra)).record;
        const avant = propre(colF.get(f.id));
        const r = PR.valoriserFacture(f.id);
        const apres = colF.get(f.id);
        const net = (l) => { const c = propre(l); delete c.valoriseLe; return c; };
        out.valoriser.push({ nom, facture: { id: avant.id, numero: avant.numero, date: avant.date, lignes: avant.lignes, montantPaye: 0, tauxPriseEnCharge: avant.tauxPriseEnCharge === undefined ? null : avant.tauxPriseEnCharge, personnelId: avant.personnelId === undefined ? null : avant.personnelId },
          prix: { [code]: 3700 }, sortie: { valorisees: propre(r.valorisees), restantes: propre(r.restantes),
            facture: propre({ lignes: apres.lignes.map(net), montantTTC: apres.montantTTC, montantHT: apres.montantHT, montantBrut: apres.montantBrut, partAssurance: apres.partAssurance, partPersonnel: apres.partPersonnel, partPatient: apres.partPatient, reliquat: apres.reliquat, enAttentePrix: apres.enAttentePrix === undefined ? null : apres.enAttentePrix }) } });
      });
      return out;
    });
    ecrire('packages/domaine/test/vecteurs/prix_manquant.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-prix-manquant.js : lot TARIF-FIX-2 (maquette dans Chrome). Ne pas éditer.' }, sortie));
    console.log('  manque ' + sortie.manque.length + ' · totaux ' + sortie.totaux.length + ' · réglage ' + sortie.reglage.length + ' · MECeF ' + sortie.mecef.length + ' · encaisser ' + sortie.encaisser.length + ' séquences · valoriser ' + sortie.valoriser.length);
    if (m.erreurs.length) console.log('  avertissements : ' + m.erreurs.slice(0, 3).join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
