'use strict';
/* Scénario CMD1 (lot CMD, Direction, section AQ point 1 : « ELLE VOYAGE A LA SYNCHRONISATION ») : la COMMANDE DE STOCK GROS voyage entre postes (famille A, champ à champ, identité commune par le
   contenu posée par le poste : `identiteSyncCommande` du domaine). Avant le lot, `commandes` restait locale au poste de création.

   Ce que ce banc éprouve : le PROTOCOLE, avec la mère de référence (Node) ou la mère Dart (`banc:cible`). Le câblage du poste (pont, décision signée déposée dans `demandesValidation`, application
   sous le rôle de l'auteur, référence provisoire de l'écran) est éprouvé par `apps/poste/test/cmd_commande_sync_test.dart` (VRAIE mère Dart, deux VRAIS fileuls). Ici :

     1. une commande créée par F1 avec une référence PROVISOIRE (`BC-AAAA-P<poste>-nnnn`) reçoit à la mère son rang DÉFINITIF ; il revient à F1 et arrive à F2 ;
     2. deux postes qui tirent le même rang provisoire reçoivent deux rangs définitifs DISTINCTS ; une référence définitive déjà posée ne se réécrit jamais (refus nommé COMMANDE_REFERENCE_FIGEE, la numérotation des autres ne bouge pas) ;
     3. une VALIDATION écrite directement sur la fiche par un fileul est REFUSÉE au rejeu (COMMANDE_VALIDATION_DIRECTE) ; une autre correction passe ;
     4. mère TUÉE : F1 et F2 saisissent la MÊME commande (même identité de contenu, deux références provisoires) ; à la reprise, UNE fiche, UN rang, aucun refus à « traiter » ;
     5. la réponse se perd après traitement : le rejeu ne crée aucun doublon ni deuxième rang ;
     6. JAMAIS vers un téléphone : un lot de tournée qui la nomme est refusé (422 achats_interdits_au_mobile), le téléphone n'en reçoit aucune ;
     7. le relais ne voit RIEN : ni fournisseur, ni montant, ni nom de collection en clair. */
const { dechiffrer } = require('./crypto');

const FOURNISSEUR = 'GRIGRI-PHARMA-SECRET-CMD1';
const MONTANT = 8888003;
const ligne = (q) => [{ produitId: 'PRD1', produit: 'Gants', quantite: q, prixUnitaire: 100, montant: q * 100 }];
const cmd = (ref, date, q, f = FOURNISSEUR) => ({ reference: ref, date, fournisseur: f, fournisseurNom: f, statutCommande: 'attente_validation', statut: 'actif', montant: q * 100, lignes: ligne(q) });

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async CMD1() {
    titre('CMD1 · la commande de stock gros voyage (famille A, identité par le contenu), rang définitif de la mère, validation directe refusée au rejeu, mère coupée sans doublon, jamais vers un téléphone, le relais ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const liste = async (poste, col) => (await poste.liste(col)).map((x) => Object.assign({}, x.data, { id: x.id }));
    const ref = async (poste, id) => (await liste(poste, 'commandes')).find((x) => x.id === id)?.reference;
    const aTraiter = async () => [...(await f1.etat()).a_traiter, ...(await f2.etat()).a_traiter];

    /* 1. Créée par F1 (référence provisoire) : la mère attribue le rang DÉFINITIF, qui revient à F1 et arrive à F2. */
    await f1.ecrire({ type: 'creer', collection: 'commandes', fiche: 'CMD-a', champs: cmd('BC-2026-PF1-0001', '2026-11-16', 10) });
    verifier('la commande de F1 arrive à la mère et à F2 avec le rang DÉFINITIF de la mère (BC-2026-0001), pas la référence provisoire',
      await attendre(async () => (await ref(f2, 'CMD-a')) === 'BC-2026-0001', 15000), [await ref(f2, 'CMD-a')]);
    verifier('le rang définitif REVIENT à F1 sur sa propre fiche (la réponse de la mère le porte) : aucune référence provisoire ne survit',
      await attendre(async () => (await ref(f1, 'CMD-a')) === 'BC-2026-0001', 15000), [await ref(f1, 'CMD-a')]);

    /* 2. Un autre poste tire le MÊME rang provisoire : un rang définitif DISTINCT ; une référence définitive posée ne se réécrit pas. */
    await f2.ecrire({ type: 'creer', collection: 'commandes', fiche: 'CMD-b', champs: cmd('BC-2026-PF1-0001', '2026-11-17', 6, 'AUTRE-FOURNISSEUR') });
    verifier('deux postes qui ont tiré la même référence provisoire reçoivent deux rangs définitifs DISTINCTS (BC-2026-0002 pour le second)',
      await attendre(async () => (await ref(f1, 'CMD-b')) === 'BC-2026-0002' && (await ref(f2, 'CMD-b')) === 'BC-2026-0002', 15000), [await ref(f1, 'CMD-b'), await ref(f2, 'CMD-b')]);
    await f1.ecrire({ type: 'modifier', collection: 'commandes', fiche: 'CMD-a', champs: { reference: 'BC-2026-9999' } });
    await dormir(1500);
    verifier('une tentative de réécrire une référence définitive est REFUSÉE au rejeu en nommant (COMMANDE_REFERENCE_FIGEE) : la fiche garde BC-2026-0001 à la mère et chez F2',
      await attendre(async () => (await aTraiter()).some((x) => x.code === 'COMMANDE_REFERENCE_FIGEE'), 15000) && (await ref(f2, 'CMD-a')) === 'BC-2026-0001', [await aTraiter(), await ref(f2, 'CMD-a')]);
    verifier('elle ne change pas la numérotation des AUTRES commandes (le rang suivant reste BC-2026-0003)',
      (await ref(f2, 'CMD-b')) === 'BC-2026-0002', [await ref(f2, 'CMD-b')]);

    /* 3. Une validation écrite DIRECTEMENT par un fileul est refusée au rejeu ; une autre correction passe. */
    await f2.ecrire({ type: 'modifier', collection: 'commandes', fiche: 'CMD-a', champs: { statutCommande: 'validee', valideePar: 'Mme DAF', dateValidation: '2026-11-16' } });
    verifier('la mère REFUSE au rejeu la validation écrite directement, en nommant (COMMANDE_VALIDATION_DIRECTE)',
      await attendre(async () => (await aTraiter()).some((x) => x.code === 'COMMANDE_VALIDATION_DIRECTE'), 15000), await aTraiter());
    const apres = (await liste(f1, 'commandes')).find((x) => x.id === 'CMD-a');
    verifier('la commande reste « en attente de validation » chez F1 : la validation directe n\'est jamais entrée', apres.statutCommande === 'attente_validation' && !apres.valideePar, apres);
    await f1.ecrire({ type: 'modifier', collection: 'commandes', fiche: 'CMD-b', champs: { delaiLivraison: 7 } });
    verifier('une autre correction (délai de livraison) passe et arrive chez F2 : le fileul n\'est pas bloqué', await attendre(async () => (await liste(f2, 'commandes')).find((x) => x.id === 'CMD-b').delaiLivraison === 7, 15000));

    /* 4. Mère TUÉE : F1 et F2 saisissent la MÊME commande (même identité de contenu, deux références provisoires). */
    await m.mere.tuer();
    await f1.ecrire({ type: 'creer', collection: 'commandes', fiche: 'CMD-c', champs: cmd('BC-2026-PF1-0002', '2026-11-18', 3) });
    await f2.ecrire({ type: 'creer', collection: 'commandes', fiche: 'CMD-c', champs: cmd('BC-2026-PF2-0001', '2026-11-18', 3) });
    await dormir(800);
    await m.mere.demarrer();
    verifier('mère relancée : la même commande saisie par deux postes coupés ne fait qu\'UNE fiche à la mère et chez chacun, aucun refus à « traiter »',
      await attendre(async () => (await f1.vide()) && (await f2.vide()) && (await compte('commandes')) === 3 && (await f1.liste('commandes')).length === 3 && (await f2.liste('commandes')).length === 3, 20000)
      && (await aTraiter()).every((x) => x.code === 'COMMANDE_VALIDATION_DIRECTE' || x.code === 'COMMANDE_REFERENCE_FIGEE'), [await compte('commandes'), await aTraiter()]);
    verifier('UN seul rang définitif (BC-2026-0003) pour cette commande, identique à la mère, chez F1 et chez F2 (jamais deux rangs ni une référence qui bascule)',
      await attendre(async () => (await ref(f1, 'CMD-c')) === 'BC-2026-0003' && (await ref(f2, 'CMD-c')) === 'BC-2026-0003', 15000), [await ref(f1, 'CMD-c'), await ref(f2, 'CMD-c')]);

    /* 5. La réponse se perd après traitement : le rejeu ne crée aucun doublon ni deuxième rang. */
    m.reseau.regler('perd_reponse');
    await f1.ecrire({ type: 'creer', collection: 'commandes', fiche: 'CMD-d', champs: cmd('BC-2026-PF1-0003', '2026-11-19', 2) });
    verifier('la mère TRAITE la commande dont la réponse est perdue', await attendre(async () => (await compte('commandes')) === 4, 15000));
    m.reseau.regler('ouvert');
    verifier('le rejeu aboutit sans doublon : quatre commandes à la mère, rang BC-2026-0004 chez F1 et F2', await attendre(async () => (await f1.vide()) && (await ref(f1, 'CMD-d')) === 'BC-2026-0004' && (await ref(f2, 'CMD-d')) === 'BC-2026-0004', 20000) && (await compte('commandes')) === 4, [await compte('commandes'), await ref(f1, 'CMD-d')]);

    /* 6. JAMAIS VERS UN TÉLÉPHONE. */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    const r = await m.mere.admin('POST', '/admin/lot', { uuid: mob.uuid, fiches: [{ collection: 'commandes', id: 'CMD-a' }], ttl_ms: 60000 });
    verifier('un lot de tournée qui nomme une commande est REFUSÉ en nommant (422 achats_interdits_au_mobile) : rien n\'est publié', r.status === 422 && r.json.code === 'achats_interdits_au_mobile', [r.status, r.json]);
    await f1.ecrire({ type: 'modifier', collection: 'commandes', fiche: 'CMD-a', champs: { montant: MONTANT } });
    await attendre(async () => f1.vide(), 15000);
    await dormir(2500);
    const versMobile = (await m.relais.direct('GET', '/banc/tout')).json.lignes.filter((l) => l.dir === 'vers_mobile' && l.appareil === mob.uuid);
    const colsMobile = versMobile.flatMap((l) => (dechiffrer(cleClinique, l).ops || dechiffrer(cleClinique, l).fiches || []).map((o) => o.collection));
    verifier('le téléphone ne reçoit AUCUNE commande : rien dans ce que le relais lui a distribué, rien dans sa base', !(await mob.liste('commandes')).length && !colsMobile.includes('commandes'), colsMobile);

    /* 7. LE RELAIS NE VOIT RIEN. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = brut.lignes.map((l) => Buffer.from(l.ct, 'base64'));
    const motif = new RegExp(FOURNISSEUR + '|' + MONTANT + '|commandes|BC-2026');
    verifier('le relais détient le journal chiffré mais AUCUN fournisseur, aucun montant, aucun nom de collection, aucune référence, ni en clair ni dans les octets', brut.lignes.length >= 2
      && !motif.test(tout) && octets.every((o) => !motif.test(o.toString('latin1'))), brut.lignes.length);
    const claires = brut.lignes.filter((l) => l.dir === 'journal').map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien les commandes : l\'opacité ne vient pas d\'un contenu vide', claires.some((o) => o.collection === 'commandes'), claires.length);
    await m.fermer();
  },
});
