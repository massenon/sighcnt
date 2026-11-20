'use strict';
/* Scénario TIERS1 (lot TIERS, Direction, 16/11/2026, section AQ point 36) : la FACTURE À UN TIERS PAYEUR et ses quatre pièces (fiche du tiers, avoir, règlement, lettrage) voyagent entre postes
   (famille A, identité commune par le contenu posée par le poste : `identiteSyncGestion` du domaine), jamais vers un téléphone ; une pièce ÉMISE ne se réécrit jamais au rejeu.

   Ce que ce banc éprouve : le PROTOCOLE, avec la mère de référence (Node) ou la mère Dart (`banc:cible`). Ici :
     1. la fiche d'un tiers, une facture en brouillon, un règlement et un lettrage écrits par F1 arrivent chez F2 ;
     2. le brouillon devient une pièce ÉMISE (champ à champ) : la décision de l'AIB et le numéro arrivent chez F2 ;
     3. une pièce émise ne se réécrit PAS : F2 qui change la base, l'IFU de l'acheteur ou le numéro MECeF est refusé au rejeu en nommant (FACTURE_TIERS_FIGEE) ; une trace MECeF nouvelle passe ;
     4. mère TUÉE : F1 et F2 écrivent la MÊME facture (même identité de contenu) ; à la reprise UNE fiche, aucun refus à « traiter » ;
     5. JAMAIS vers un téléphone : un lot de tournée qui en nomme une est refusé (422 gestion_interdite_au_mobile), le téléphone n'en reçoit aucune ;
     6. le relais ne voit RIEN : aucun IFU, aucun nom d'acheteur, aucun nom de collection en clair. */
const { dechiffrer } = require('./crypto');

const NOM = 'SOCIETE-SECRETE-TIERS1';
const COLS = ['tiersPayeurs', 'facturesTiers', 'avoirsTiers', 'reglementsTiers', 'lettragesTiers'];
const facture = (extra) => Object.assign({ statut: 'brouillon', tiersCode: 'TP-001', tiersNom: NOM, ifuAcheteur: '3201642748214', nomAcheteur: NOM, patientId: 'PAT0003', date: '2026-11-16',
  lignes: [{ factureId: 'FAC1', factureNumero: 'FAC-2026-0001', ligneId: 'L001', designation: 'Séjour', montant: 100000 }], base: 100000, ht: 100000, tva: 0, sourcesCle: 'FAC-2026-0001#L001:100000', numero: null, aibDecision: null }, extra || {});

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async TIERS1() {
    titre('TIERS1 · la facture à un tiers payeur voyage (famille A, identité par le contenu), une pièce émise ne se réécrit pas au rejeu, mère coupée sans doublon, jamais vers un téléphone, le relais ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const liste = async (poste, col) => (await poste.liste(col)).map((x) => Object.assign({}, x.data, { id: x.id }));
    const aTraiter = async () => [...(await f1.etat()).a_traiter, ...(await f2.etat()).a_traiter];

    /* 1. Écrits chez F1, reçus chez F2. */
    await f1.ecrire({ type: 'creer', collection: 'tiersPayeurs', fiche: 'TPY-a', champs: { code: 'TP-001', version: 1, dateEffet: '2026-01-05', nom: NOM, ifu: '3201642748214', type: 'entreprise' } });
    await f1.ecrire({ type: 'creer', collection: 'facturesTiers', fiche: 'FTP-a', champs: facture() });
    await f1.ecrire({ type: 'creer', collection: 'reglementsTiers', fiche: 'RTP-a', champs: { numero: 'RGT-2026-0001', tiersCode: 'TP-001', date: '2026-11-17', montant: 100000, mode: 'virement', referencePaiement: 'VIR-T1-1' } });
    verifier('la fiche du tiers, le brouillon et le règlement écrits par F1 arrivent chez F2 par le journal',
      await attendre(async () => (await f2.liste('tiersPayeurs')).length === 1 && (await f2.liste('facturesTiers')).length === 1 && (await f2.liste('reglementsTiers')).length === 1, 15000));

    /* 2. Le brouillon devient une pièce émise (champ à champ). */
    await f1.ecrire({ type: 'modifier', collection: 'facturesTiers', fiche: 'FTP-a', champs: { aibDecision: { appliquer: true, taux: 1, situation: 'ifu_actif' } } });
    await f1.ecrire({ type: 'modifier', collection: 'facturesTiers', fiche: 'FTP-a', champs: { statut: 'emise', numero: 'FT-2026-0001', aibTaux: 1, aibMontant: 1000, net: 101000, statutMecef: 'en_attente' } });
    await f1.ecrire({ type: 'creer', collection: 'lettragesTiers', fiche: 'LTP-a', champs: { reglementId: 'RTP-a', reglementNumero: 'RGT-2026-0001', reglementRef: 'VIR-T1-1', factureTiersId: 'FTP-a', factureNumero: 'FT-2026-0001', tiersCode: 'TP-001', montant: 101000 } });
    verifier('la décision de l\'AIB, le numéro FT-2026-0001 et le lettrage arrivent chez F2 : la pièce y est émise',
      await attendre(async () => { const x = (await liste(f2, 'facturesTiers')).find((y) => y.id === 'FTP-a'); return x && x.statut === 'emise' && x.numero === 'FT-2026-0001' && x.net === 101000 && (await f2.liste('lettragesTiers')).length === 1; }, 15000));

    /* 3. Une pièce émise ne se réécrit pas au rejeu. */
    await f2.ecrire({ type: 'modifier', collection: 'facturesTiers', fiche: 'FTP-a', champs: { base: 1 } });
    verifier('la mère REFUSE au rejeu la réécriture de la base d\'une pièce émise, en nommant (FACTURE_TIERS_FIGEE)',
      await attendre(async () => (await aTraiter()).some((x) => x.code === 'FACTURE_TIERS_FIGEE'), 15000), await aTraiter());
    await f2.ecrire({ type: 'modifier', collection: 'facturesTiers', fiche: 'FTP-a', champs: { ifuAcheteur: '0000000000000' } });
    await dormir(1500);
    await f1.ecrire({ type: 'modifier', collection: 'facturesTiers', fiche: 'FTP-a', champs: { statutMecef: 'valide', numeroMecef: 'MECEF2000001', codeRetour: 'OK-200' } });
    verifier('une trace MECeF nouvelle (statut, numéro de l\'appareil) passe et arrive chez F2 : le fileul n\'est pas bloqué',
      await attendre(async () => { const x = (await liste(f2, 'facturesTiers')).find((y) => y.id === 'FTP-a'); return x && x.numeroMecef === 'MECEF2000001' && x.statutMecef === 'valide'; }, 15000));
    const x1 = (await liste(f1, 'facturesTiers')).find((y) => y.id === 'FTP-a');
    verifier('la pièce reste intacte chez F1 (base 100 000, IFU de l\'acheteur d\'origine) : la réécriture n\'est jamais entrée', x1.base === 100000 && x1.ifuAcheteur === '3201642748214', x1);
    await f2.ecrire({ type: 'modifier', collection: 'facturesTiers', fiche: 'FTP-a', champs: { numeroMecef: 'MECEF9999999' } });
    verifier('un numéro MECeF déjà posé ne se réécrit pas (FACTURE_TIERS_NUMERO_MECEF_FIGE)',
      await attendre(async () => (await aTraiter()).some((x) => x.code === 'FACTURE_TIERS_NUMERO_MECEF_FIGE' || x.code === 'FACTURE_TIERS_FIGEE'), 15000) && (await liste(f1, 'facturesTiers')).find((y) => y.id === 'FTP-a').numeroMecef === 'MECEF2000001', await aTraiter());

    /* 4. Mère TUÉE : F1 et F2 écrivent la MÊME facture (même identité de contenu). */
    await m.mere.tuer();
    const b = facture({ sourcesCle: 'FAC-2026-0002#L001:50000', base: 50000, lignes: [{ factureId: 'FAC2', factureNumero: 'FAC-2026-0002', ligneId: 'L001', designation: 'Analyse', montant: 50000 }] });
    await f1.ecrire({ type: 'creer', collection: 'facturesTiers', fiche: 'FTP-b', champs: b });
    await f2.ecrire({ type: 'creer', collection: 'facturesTiers', fiche: 'FTP-b', champs: b });
    await dormir(800);
    await m.mere.demarrer();
    verifier('mère relancée : la même facture écrite par deux postes coupés ne fait qu\'UNE fiche à la mère et chez chacun, aucun refus à « traiter »',
      await attendre(async () => (await f1.vide()) && (await f2.vide()) && (await compte('facturesTiers')) === 2 && (await f1.liste('facturesTiers')).length === 2 && (await f2.liste('facturesTiers')).length === 2, 20000)
      && !(await aTraiter()).some((x) => x.code === 'fiche_existe'), [await compte('facturesTiers'), await aTraiter()]);

    /* 5. JAMAIS VERS UN TÉLÉPHONE. */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    const refus = [];
    for (const [col, id] of [['tiersPayeurs', 'TPY-a'], ['facturesTiers', 'FTP-a'], ['reglementsTiers', 'RTP-a'], ['lettragesTiers', 'LTP-a']]) {
      const r = await m.mere.admin('POST', '/admin/lot', { uuid: mob.uuid, fiches: [{ collection: col, id }], ttl_ms: 60000 });
      refus.push([col, r.status, r.json.code]);
    }
    verifier('un lot de tournée qui nomme un tiers, une facture, un règlement ou un lettrage est REFUSÉ en nommant (422 gestion_interdite_au_mobile) : rien n\'est publié',
      refus.every(([, s, c]) => s === 422 && c === 'gestion_interdite_au_mobile'), refus);
    await f1.ecrire({ type: 'modifier', collection: 'reglementsTiers', fiche: 'RTP-a', champs: { mode: 'cheque' } });
    await attendre(async () => f1.vide(), 15000);
    await dormir(2500);
    const versMobile = (await m.relais.direct('GET', '/banc/tout')).json.lignes.filter((l) => l.dir === 'vers_mobile' && l.appareil === mob.uuid);
    const collectionsMobile = versMobile.flatMap((l) => (dechiffrer(cleClinique, l).ops || dechiffrer(cleClinique, l).fiches || []).map((o) => o.collection));
    let rienChezMob = true;
    for (const col of COLS) if ((await mob.liste(col)).length) rienChezMob = false;
    verifier('le téléphone ne reçoit AUCUNE fiche des cinq collections : rien dans ce que le relais lui a distribué, rien dans sa base', rienChezMob && !collectionsMobile.some((c) => COLS.includes(c)), collectionsMobile);

    /* 6. LE RELAIS NE VOIT RIEN. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = brut.lignes.map((l) => Buffer.from(l.ct, 'base64'));
    const motif = new RegExp(NOM + '|3201642748214|facturesTiers|tiersPayeurs|reglementsTiers|lettragesTiers');
    verifier('le relais détient le journal chiffré mais AUCUN IFU, aucun nom d\'acheteur, aucun nom de collection, ni en clair ni dans les octets', brut.lignes.length >= 2
      && !motif.test(tout) && octets.every((o) => !motif.test(o.toString('latin1'))), brut.lignes.length);
    const claires = brut.lignes.filter((l) => l.dir === 'journal').map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien les collections du lot : l\'opacité ne vient pas d\'un contenu vide', ['tiersPayeurs', 'facturesTiers', 'reglementsTiers', 'lettragesTiers'].every((c) => claires.some((o) => o.collection === c)));
    await m.fermer();
  },
});
