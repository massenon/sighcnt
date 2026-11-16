'use strict';
/* Scénario CFG1 (lot SYNC-CFG, décision 26 de la Direction du 15/11/2026) : les BUDGETS, les IMMOBILISATIONS et les COUVERTURES D'ASSURANCE se synchronisent (famille A, champ à champ,
   identité commune par le contenu posée par le poste : `identiteSyncGestion` du domaine). Jusqu'au lot, une saisie ou un import chez un fileul restait local à ce poste.

   Ce que ce banc éprouve : le PROTOCOLE, avec la mère de référence (Node) ou la mère Dart (`banc:cible`). Le câblage du poste (pont, identité par le contenu, garde d'exercice clos au
   rejeu) est éprouvé par `apps/poste/test/sync_cfg_sync_test.dart` (VRAIE mère Dart, deux VRAIS fileuls, mère arrêtée pour de vrai). Ici :

     1. un budget, un bien et une couverture écrits par F1 arrivent chez F2 ;
     2. une couverture se CLÔT sur sa propre fiche (la fin s'écrit, champ à champ) : famille A, jamais un refus `journal_immuable` ;
     3. mère TUÉE puis relancée : F1 et F2 écrivent le même budget (même identité de contenu) ; à la reprise, UNE fiche à la mère, aucun refus à « traiter » ;
     4. la réponse se perd après traitement : le rejeu ne crée aucun doublon ;
     5. JAMAIS vers un téléphone : un lot de tournée qui en nomme une est refusé (422 gestion_interdite_au_mobile), le téléphone n'en reçoit aucune ;
     6. le relais ne voit RIEN : aucun montant, aucune police, aucun nom de collection en clair. */
const { dechiffrer } = require('./crypto');

const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };
const POLICE = 'POLICE-SECRETE-CFG1';
const MONTANT = 7777001;
const COLS = ['budgets', 'immobilisations', 'couverturesAssurance'];

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async CFG1() {
    titre('SYNC-CFG1 · budgets, immobilisations et couvertures d\'assurance voyagent (famille A, identité commune par le contenu), mère coupée sans doublon, rejeu sans effet, jamais vers un téléphone, le relais ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const liste = async (poste, col) => (await poste.liste(col)).map((x) => Object.assign({}, x.data, { id: x.id }));
    const aTraiter = async () => [...(await f1.etat()).a_traiter, ...(await f2.etat()).a_traiter];

    /* 1. Écrits chez F1, reçus chez F2. Les identifiants sont ceux que le poste tire du contenu (BUD-, IMM-, COU-). */
    await f1.ecrire({ type: 'creer', collection: 'budgets', fiche: 'BUD-2026-labo', champs: { reference: 'BG-2026-001', exercice: 2026, centreCout: 'laboratoire', nature: 'Charges de fonctionnement', prevu: MONTANT } });
    await f1.ecrire({ type: 'creer', collection: 'immobilisations', fiche: 'IMM-echographe', champs: { reference: 'IM-002', designation: 'Échographe portable', dateAcquisition: '2026-02-01', valeurAcquisition: 4500000, dureeAmortissement: 5, compte: '241000' } });
    await f1.ecrire({ type: 'creer', collection: 'couverturesAssurance', fiche: 'COU-p3-20260101', champs: { patientId: 'PAT0003', assureur: 'AFR', numeroPolice: POLICE, tauxPriseEnCharge: 80, debut: '2026-01-01' } });
    verifier('le budget, le bien et la couverture écrits par F1 arrivent chez F2 par le journal (avant le lot : restés locaux au poste)',
      await attendre(async () => (await f2.liste('budgets')).length === 1 && (await f2.liste('immobilisations')).length === 1 && (await f2.liste('couverturesAssurance')).length === 1, 15000)
      && (await liste(f2, 'budgets'))[0].prevu === MONTANT && (await liste(f2, 'couverturesAssurance'))[0].numeroPolice === POLICE);

    /* 2. La couverture se CLÔT sur sa propre fiche (famille A), la suivante s'ajoute. */
    await f2.ecrire({ type: 'modifier', collection: 'couverturesAssurance', fiche: 'COU-p3-20260101', champs: { fin: '2026-10-31' } });
    await f2.ecrire({ type: 'creer', collection: 'couverturesAssurance', fiche: 'COU-p3-20261101', champs: { patientId: 'PAT0003', assureur: 'NSIA', numeroPolice: POLICE + '-2', tauxPriseEnCharge: 70, debut: '2026-11-01' } });
    verifier('la couverture en cours se CLÔT sur sa propre fiche (la fin s\'écrit, champ à champ) et la suivante s\'ajoute : deux versions chez F1, aucun refus « journal_immuable »',
      await attendre(async () => (await f1.liste('couverturesAssurance')).length === 2 && (await liste(f1, 'couverturesAssurance')).find((x) => x.id === 'COU-p3-20260101').fin === '2026-10-31', 15000)
      && !(await aTraiter()).some((x) => x.code === 'journal_immuable'), await aTraiter());

    /* 3. Mère TUÉE : F1 et F2 écrivent le MÊME budget (même identité de contenu). */
    await m.mere.tuer();
    await f1.ecrire({ type: 'creer', collection: 'budgets', fiche: 'BUD-2026-pharma', champs: { reference: 'BG-2026-002', exercice: 2026, centreCout: 'pharmacie', nature: 'Charges de fonctionnement', prevu: 700000 } });
    await f2.ecrire({ type: 'creer', collection: 'budgets', fiche: 'BUD-2026-pharma', champs: { reference: 'BG-2026-002', exercice: 2026, centreCout: 'pharmacie', nature: 'Charges de fonctionnement', prevu: 700000 } });
    /* Le même budget de la maternité, mais deux MONTANTS différents : un conflit nommé, jamais un écrasement silencieux ni deux fiches. */
    await f1.ecrire({ type: 'creer', collection: 'budgets', fiche: 'BUD-2026-mater', champs: { reference: 'BG-2026-003', exercice: 2026, centreCout: 'maternite', nature: 'Charges de fonctionnement', prevu: 100000 } });
    await f2.ecrire({ type: 'creer', collection: 'budgets', fiche: 'BUD-2026-mater', champs: { reference: 'BG-2026-003', exercice: 2026, centreCout: 'maternite', nature: 'Charges de fonctionnement', prevu: 150000 } });
    await dormir(800);
    await m.mere.demarrer();
    verifier('mère relancée : le même budget écrit par deux postes coupés ne fait qu\'UNE fiche à la mère et chez chacun, aucun refus à « traiter »',
      await attendre(async () => (await f1.vide()) && (await f2.vide()) && (await compte('budgets')) === 3 && (await f1.liste('budgets')).length === 3 && (await f2.liste('budgets')).length === 3, 20000)
      && (await aTraiter()).length === 0, [await compte('budgets'), await aTraiter()]);
    const conflits = (await m.mere.admin('GET', '/admin/conflits')).json.filter((x) => x.collection === 'budgets' && x.fiche === 'BUD-2026-mater');
    verifier('deux montants différents pour le même budget : UNE fiche, la première valeur gardée et un CONFLIT nommé sur le champ « prevu » (jamais un écrasement silencieux)',
      conflits.length === 1 && conflits[0].champ === 'prevu' && [100000, 150000].includes((await liste(f1, 'budgets')).find((x) => x.id === 'BUD-2026-mater').prevu)
      && (await liste(f1, 'budgets')).find((x) => x.id === 'BUD-2026-mater').prevu === (await liste(f2, 'budgets')).find((x) => x.id === 'BUD-2026-mater').prevu, conflits);

    /* 4. La réponse se perd après traitement : le rejeu ne crée aucun doublon. */
    m.reseau.regler('perd_reponse');
    await f1.ecrire({ type: 'creer', collection: 'immobilisations', fiche: 'IMM-autoclave2', champs: { reference: 'IM-003', designation: 'Autoclave 2', dateAcquisition: '2026-03-01', valeurAcquisition: 900000, dureeAmortissement: 5, compte: '241000' } });
    verifier('la mère TRAITE l\'opération dont la réponse est perdue', await attendre(async () => (await compte('immobilisations')) === 2, 15000));
    m.reseau.regler('ouvert');
    verifier('le rejeu aboutit sans doublon : deux biens à la mère et chez F2', await attendre(async () => (await f1.vide()) && (await f2.liste('immobilisations')).length === 2, 15000) && (await compte('immobilisations')) === 2);

    /* 5. JAMAIS VERS UN TÉLÉPHONE. */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    const refus = [];
    for (const [col, id] of [['budgets', 'BUD-2026-labo'], ['immobilisations', 'IMM-echographe'], ['couverturesAssurance', 'COU-p3-20260101']]) {
      const r = await m.mere.admin('POST', '/admin/lot', { uuid: mob.uuid, fiches: [{ collection: col, id }], ttl_ms: 60000 });
      refus.push([col, r.status, r.json.code]);
    }
    verifier('un lot de tournée qui nomme un budget, un bien ou une couverture est REFUSÉ en nommant (422 gestion_interdite_au_mobile) : rien n\'est publié', refus.every(([, s, c]) => s === 422 && c === 'gestion_interdite_au_mobile'), refus);
    await f1.ecrire({ type: 'modifier', collection: 'budgets', fiche: 'BUD-2026-labo', champs: { prevu: MONTANT + 1 } });
    await attendre(async () => f1.vide(), 15000);
    await dormir(2500);
    const versMobile = (await m.relais.direct('GET', '/banc/tout')).json.lignes.filter((l) => l.dir === 'vers_mobile' && l.appareil === mob.uuid);
    const collectionsMobile = versMobile.flatMap((l) => (dechiffrer(cleClinique, l).ops || dechiffrer(cleClinique, l).fiches || []).map((o) => o.collection));
    let rienChezMob = true;
    for (const col of COLS) if ((await mob.liste(col)).length) rienChezMob = false;
    verifier('le téléphone ne reçoit AUCUNE fiche des trois collections : rien dans ce que le relais lui a distribué, rien dans sa base', rienChezMob && !collectionsMobile.some((c) => COLS.includes(c)), collectionsMobile);

    /* 6. LE RELAIS NE VOIT RIEN. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = brut.lignes.map((l) => Buffer.from(l.ct, 'base64'));
    const motif = new RegExp(POLICE + '|' + MONTANT + '|couverturesAssurance|immobilisations|budgets|Échographe');
    verifier('le relais détient le journal chiffré (les trois collections y sont) mais AUCUN montant, aucune police, aucun nom de collection, ni en clair ni dans les octets', brut.lignes.length >= 2
      && !motif.test(tout) && octets.every((o) => !motif.test(o.toString('latin1'))), brut.lignes.length);
    const claires = brut.lignes.filter((l) => l.dir === 'journal').map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien les trois collections : l\'opacité ne vient pas d\'un contenu vide', COLS.every((c) => claires.some((o) => o.collection === c)), claires.length);
    const gros = octets.filter((o) => o.length >= 250);
    verifier('chaque enveloppe a l\'entropie d\'un chiffrement (> 7 bits/octet)', gros.length >= 1 && gros.every((o) => entropie(o) > 7.0), octets.map((o) => [o.length, +entropie(o).toFixed(2)]));
    await m.fermer();
  },
});
