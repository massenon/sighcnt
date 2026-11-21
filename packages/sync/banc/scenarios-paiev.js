'use strict';
/* Scénario PAIEV1 (lot PAIE-V, Direction, 20/11/2026, section BI) : le VERSEMENT DE CAISSE d'une pièce voyage entre postes (famille A, identité commune par le contenu posée par le poste :
   `identiteSyncGestion` du domaine), jamais vers un téléphone ; la mère REFUSE au rejeu un versement qui ferait dépasser le dû de la part du patient ; un versement enregistré ne se réécrit jamais.

   Ce que ce banc éprouve : le PROTOCOLE, avec la mère de référence (Node, qui tient le plafond) ou la mère Dart (`banc:cible`, qui refait le contrôle complet du domaine). Ici :
     1. deux versements (mobile money avec sa référence, espèces) écrits par F1 sur une pièce arrivent chez F2 ;
     2. DEUX FILEULS COUPÉS encaissent la même pièce : le second versement qui ferait dépasser le dû est REFUSÉ au rejeu en nommant (VERSEMENT_SUPERIEUR_AU_DU), le premier reste ;
     3. un versement enregistré ne se réécrit pas (VERSEMENT_FIGE) ;
     4. mère TUÉE : F1 et F2 écrivent le MÊME versement (même identité de contenu) : UNE fiche à la reprise, aucun refus à « traiter » ;
     5. JAMAIS vers un téléphone : un lot de tournée qui en nomme un est refusé (422 gestion_interdite_au_mobile), le téléphone n'en reçoit aucun ;
     6. le relais ne voit RIEN : aucune référence de transaction, aucun nom de collection en clair. */
const { dechiffrer } = require('./crypto');

const REF = 'REFERENCE-SECRETE-MOMO-PAIEV1';
const facture = () => ({ statut: 'actif', numero: 'FAC-2026-0900', date: '2026-11-20', patientId: 'PAT0003', patient: 'Patient Trois', montantTTC: 23500, partPatient: 23500, montantPaye: 0, reliquat: 23500, statutPaiement: 'impayee',
  lignes: [{ id: 'L001', designation: 'Acte 1', montant: 15000, partPatient: 15000, statutPaiement: 'du' }, { id: 'L002', designation: 'Acte 2', montant: 8500, partPatient: 8500, statutPaiement: 'du' }] });
const versement = (extra) => Object.assign({ statut: 'actif', factureId: 'FAC-P1', factureNumero: 'FAC-2026-0900', patientId: 'PAT0003', rang: 1, type: 'acompte', typeLibelle: 'Acompte', modalite: 'especes', modaliteLibelle: 'Espèces', compte: '571000',
  montant: 15000, date: '2026-11-20', horodatage: '2026-11-20T09:00:00.000Z', agent: 'Caissier', origine: 'caisse', resteApres: 8500, ecritureIds: [] }, extra || {});

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async PAIEV1() {
    titre('PAIEV1 · le versement de caisse voyage (famille A, identité par le contenu), la mère refuse au rejeu le dépassement du dû, un versement enregistré ne se réécrit pas, mère coupée sans doublon, jamais vers un téléphone, le relais ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const liste = async (poste, col) => (await poste.liste(col)).map((x) => Object.assign({}, x.data, { id: x.id }));
    const aTraiter = async () => [...(await f1.etat()).a_traiter, ...(await f2.etat()).a_traiter];

    /* 1. La pièce, puis deux versements de modes différents écrits chez F1, reçus chez F2. */
    await f1.ecrire({ type: 'creer', collection: 'factures', fiche: 'FAC-P1', champs: facture() });
    await f1.ecrire({ type: 'creer', collection: 'versementsCaisse', fiche: 'VRS-a', champs: versement({ modalite: 'mobile_money', modaliteLibelle: 'Mobile money', compte: '521000', operateur: 'mtn', operateurLibelle: 'MTN Mobile Money', referenceTransaction: REF }) });
    await f1.ecrire({ type: 'creer', collection: 'versementsCaisse', fiche: 'VRS-b', champs: versement({ rang: 2, type: 'solde', typeLibelle: 'Solde', montant: 8500, resteApres: 0, horodatage: '2026-11-20T09:05:00.000Z' }) });
    verifier('les deux versements (mobile money avec sa référence, espèces) écrits par F1 arrivent chez F2 par le journal',
      await attendre(async () => (await f2.liste('versementsCaisse')).length === 2 && (await f2.liste('factures')).length === 1, 15000));
    const chezF2 = (await liste(f2, 'versementsCaisse')).find((x) => x.id === 'VRS-a');
    verifier('le versement arrive intact (modalité, opérateur, référence, montant)', chezF2 && chezF2.operateur === 'mtn' && chezF2.referenceTransaction === REF && chezF2.montant === 15000, chezF2);

    /* 2. Deux fileuls encaissent la même pièce hors ligne : la mère refuse ce qui ferait dépasser le dû. */
    await f1.ecrire({ type: 'creer', collection: 'factures', fiche: 'FAC-P2', champs: Object.assign(facture(), { numero: 'FAC-2026-0901' }) });
    await attendre(async () => (await f2.liste('factures')).length === 2, 15000);
    await m.mere.tuer();
    await f1.ecrire({ type: 'creer', collection: 'versementsCaisse', fiche: 'VRS-c', champs: versement({ factureId: 'FAC-P2', factureNumero: 'FAC-2026-0901', montant: 20000, resteApres: 3500, horodatage: '2026-11-20T10:00:00.000Z' }) });
    await f2.ecrire({ type: 'creer', collection: 'versementsCaisse', fiche: 'VRS-d', champs: versement({ factureId: 'FAC-P2', factureNumero: 'FAC-2026-0901', montant: 20000, resteApres: 3500, horodatage: '2026-11-20T10:00:05.000Z' }) });
    await dormir(800);
    await m.mere.demarrer();
    verifier('mère relancée : le second versement de 20 000 sur une pièce de 23 500 est REFUSÉ au rejeu en nommant (VERSEMENT_SUPERIEUR_AU_DU) ; un seul des deux est entré à la mère',
      await attendre(async () => (await aTraiter()).some((x) => x.code === 'VERSEMENT_SUPERIEUR_AU_DU'), 20000) && (await compte('versementsCaisse')) === 3, [await compte('versementsCaisse'), await aTraiter()]);

    /* 3. Un versement enregistré ne se réécrit pas. */
    await f2.ecrire({ type: 'modifier', collection: 'versementsCaisse', fiche: 'VRS-a', champs: { montant: 1 } });
    verifier('la mère REFUSE au rejeu la réécriture du montant d\'un versement enregistré, en nommant (VERSEMENT_FIGE)',
      await attendre(async () => (await aTraiter()).some((x) => x.code === 'VERSEMENT_FIGE'), 15000), await aTraiter());
    const x1 = (await liste(f1, 'versementsCaisse')).find((y) => y.id === 'VRS-a');
    verifier('le versement reste intact chez F1 (15 000) : la réécriture n\'est jamais entrée', x1 && x1.montant === 15000, x1);

    /* 4. Mère TUÉE : F1 et F2 écrivent le MÊME versement (même identité de contenu, donc même identifiant de fiche). */
    await f1.ecrire({ type: 'creer', collection: 'factures', fiche: 'FAC-P3', champs: Object.assign(facture(), { numero: 'FAC-2026-0902' }) });
    await attendre(async () => (await f2.liste('factures')).length === 3, 15000);
    const avant = await compte('versementsCaisse');
    await m.mere.tuer();
    const meme = versement({ factureId: 'FAC-P3', factureNumero: 'FAC-2026-0902', montant: 5000, resteApres: 18500, horodatage: '2026-11-20T11:00:00.000Z' });
    await f1.ecrire({ type: 'creer', collection: 'versementsCaisse', fiche: 'VRS-e', champs: meme });
    await f2.ecrire({ type: 'creer', collection: 'versementsCaisse', fiche: 'VRS-e', champs: meme });
    await dormir(800);
    await m.mere.demarrer();
    verifier('mère relancée : le même versement écrit par deux postes coupés ne fait qu\'UNE fiche à la mère et chez chacun, aucun refus « fiche_existe » à « traiter »',
      await attendre(async () => (await f1.vide()) && (await f2.vide()) && (await compte('versementsCaisse')) === avant + 1 && (await f1.liste('versementsCaisse')).filter((x) => x.id === 'VRS-e').length === 1, 20000)
      && !(await aTraiter()).some((x) => x.code === 'fiche_existe'), [avant, await compte('versementsCaisse'), await aTraiter()]);

    /* 5. JAMAIS VERS UN TÉLÉPHONE. */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    const r = await m.mere.admin('POST', '/admin/lot', { uuid: mob.uuid, fiches: [{ collection: 'versementsCaisse', id: 'VRS-a' }], ttl_ms: 60000 });
    verifier('un lot de tournée qui nomme un versement est REFUSÉ en nommant (422 gestion_interdite_au_mobile) : rien n\'est publié', r.status === 422 && r.json.code === 'gestion_interdite_au_mobile', [r.status, r.json]);
    await dormir(2500);
    const versMobile = (await m.relais.direct('GET', '/banc/tout')).json.lignes.filter((l) => l.dir === 'vers_mobile' && l.appareil === mob.uuid);
    const collectionsMobile = versMobile.flatMap((l) => (dechiffrer(cleClinique, l).ops || dechiffrer(cleClinique, l).fiches || []).map((o) => o.collection));
    verifier('le téléphone ne reçoit AUCUN versement : rien dans ce que le relais lui a distribué, rien dans sa base', !collectionsMobile.includes('versementsCaisse') && (await mob.liste('versementsCaisse')).length === 0, collectionsMobile);

    /* 6. LE RELAIS NE VOIT RIEN. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = brut.lignes.map((l) => Buffer.from(l.ct, 'base64'));
    const motif = new RegExp(REF + '|versementsCaisse');
    verifier('le relais détient le journal chiffré mais AUCUNE référence de transaction, aucun nom de collection, ni en clair ni dans les octets', brut.lignes.length >= 2 && !motif.test(tout) && octets.every((o) => !motif.test(o.toString('latin1'))), brut.lignes.length);
    const claires = brut.lignes.filter((l) => l.dir === 'journal').map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien la collection du lot : l\'opacité ne vient pas d\'un contenu vide', claires.some((o) => o.collection === 'versementsCaisse'), claires.length);
    await m.fermer();
  },
});
