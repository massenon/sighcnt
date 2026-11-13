'use strict';
/* Scénario IMP1 (lot IMP-C, réponse Q5 du 10/11/2026, réécrit et complété au lot IMP-D, décision N du 12/11/2026) : un FILEUL importe directement dans son propre magasin ET la mère en est
   avertie par une DEMANDE automatique (`demandesImport`, famille A : champ à champ, dans les deux sens). La mère reste l'AUTORITÉ de la configuration (famille R).

   Ce que ce banc éprouve : le PROTOCOLE. Il tient la place de la mère de référence (Node) et de fileuls de référence (Node) ; il ne fait PAS tourner le poste Flutter. La logique du poste (écriture
   directe, garde, restitution, marquage) est éprouvée par `apps/poste/test/demandes_import_direct_test.dart` (magasin du poste) et `demandes_import_direct_sync_test.dart` (VRAIE mère Dart, deux VRAIS
   moteurs de fileul, mère arrêtée pour de vrai) ; la règle pure par `packages/domaine/test/demande_import_test.dart`. Ici on prouve ce qui dépend du protocole :

     1. l'écriture directe du fileul reste LOCALE : si le fileul tente de la publier, la mère refuse en nommant (la mère reste l'autorité) ;
     2. la demande directe voyage avec ce que la mère doit reproduire (série des identifiants, lignes écrites), la mère l'applique et ses fiches portent LES MÊMES identifiants que celles du fileul ;
     3. un refus de la mère revient sur la même fiche, le fileul y ajoute SA restitution, et les deux écritures se FUSIONNENT champ à champ : aucune ne détruit l'autre ;
     4. deux fileuls qui importent le même code : la mère applique la première demande, refuse la seconde en nommant ;
     5. la mère INJOIGNABLE (réseau coupé, puis processus tué) : la demande attend dans la file du fileul et arrive UNE seule fois au retour ;
     6. un fileul retire sa demande avant la réponse ; la mère ne l'applique plus ;
     7. le relais ne voit que du chiffré, et un téléphone ne la dépose pas, ne la reçoit pas (RG-13).

   Scénario IMP2 (lot IMP-E, décision de la Direction du 13/11/2026) : le GRAND STOCK s'écrit chez le gestionnaire de stock (fileul). Même nature de preuve : le banc tient la place de la mère de référence
   (qui range `lots`, `mouvements` et `deltasCompteurs` comme la mère Dart) ; ce que le poste fait de ses fiches en attente (propres à lui, jamais publiées, valeur de départ, restitution par mouvements
   inverses) est éprouvé par `apps/poste/test/grand_stock_*_test.dart` (VRAIE mère Dart) et par `packages/domaine/test/demande_import_test.dart`. Ici : l'IDENTITÉ COMMUNE des fiches (une seule fiche par
   identifiant, jamais deux), les VARIATIONS ajoutées une fois, la demande qui voyage, le refus et la restitution partielle fusionnés champ à champ, la mère injoignable puis tuée, deux fileuls, le relais
   opaque, et RIEN vers un téléphone. */
const { dechiffrer } = require('./crypto');

const SECRET = 'CELLULE-SECRETE-IMP1-Zébulon';
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };

/* La collection de famille R du banc qui tient la place des référentiels de configuration (le banc ne connaît pas `fournisseurs`) : une fiche par ligne importée. */
const R = 'chambres';

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async IMP1() {
    titre('IMPORT-IMP1 · le fileul écrit chez lui ET dépose une demande ; la mère applique (mêmes identifiants), refuse (le fileul restitue), ou est injoignable ; le relais ne voit que du chiffré ; le téléphone ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const etatMere = () => m.mere.admin('GET', '/admin/etat').then((r) => r.json);
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const demande = (serie, extra) => ({
      etat: 'en_attente', jeu: 'assureurs', jeuLibelle: 'Importation des compagnies d’assurance', fichier: 'compagnies.xlsx', demandePar: 'GESTIONNAIRE', demandeRole: 'stock', demandeLe: '2026-11-12',
      lignes: [['Code', 'Nom'], ['SUNU', SECRET]], nbLignes: 1, aEcrire: 1,
      ecritureDirecte: true, serieIdentifiants: serie, lotLocal: 'IMP-2026-001', lotLocalId: 'LOT-' + serie + '-1', rangsEcrits: [2], ...extra,
    });
    const ligne = (serie, rang) => ({ code: 'SUNU', nom: 'Compagnie ' + rang, lotImport: 'IMP-MERE-' + serie });

    /* 1. L'ÉCRITURE DIRECTE RESTE LOCALE : le fileul a écrit la fiche chez lui ; s'il tentait de la publier, la mère refuserait en nommant (famille R : la mère seule écrit). */
    const idLocal = 'CHA-DIMF1-1';
    await f1.ecrire({ type: 'creer', collection: R, fiche: idLocal, champs: ligne('DIMF1', 1) });
    verifier('une fiche de configuration écrite chez le fileul n\'est JAMAIS acceptée par la mère : refus nommé (droit_refuse), elle reste l\'autorité', await attendre(async () => (await f1.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000), (await f1.etat()).a_traiter);
    verifier('la mère ne détient aucune fiche de configuration du fileul', (await compte(R)) === 0);

    /* 2. LA DEMANDE DIRECTE voyage avec ce que la mère doit reproduire ; la mère applique ; ses fiches portent les MÊMES identifiants que celles du fileul */
    const r = await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-1', champs: demande('DIMF1') });
    verifier('la mère accepte la demande directe d\'un fileul (famille A) et lui donne un seq', r.fiche === 'DIM-F1-1' && await attendre(async () => (await etatMere()).seq_max >= 1, 15000), r);
    verifier('elle la détient avec ses lignes, sa série d\'identifiants et les lignes écrites (la mère doit pouvoir rejouer ET reproduire)', await attendre(async () => (await compte('demandesImport')) === 1, 15000));
    for (const [i, id] of ['CHA-DIMF1-1', 'CHA-DIMF1-2'].entries()) {
      const rr = await m.mere.admin('POST', '/admin/referentiel', { collection: R, fiche: id, champs: ligne('DIMF1', i + 1) }).then((x) => x.json);
      verifier('la mère écrit la fiche ' + id + ' (rejeu de la demande : même identifiant que chez le fileul)', rr.statut === 'acceptee', rr);
    }
    const verdict1 = { etat: 'appliquee', resultatCode: '', resultatLot: 'IMP-MERE-DIMF1', resultatEcrits: 2, traitePar: 'Mère', traiteLe: '2026-11-12', lignes: [] };
    verifier('la mère confirme sur la MÊME fiche', (await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F1-1', champs: verdict1 }).then((x) => x.json)).statut === 'acceptee');
    verifier('le fileul reçoit les fiches de la mère sous les identifiants qu\'il a lui-même posés : elles remplacent les siennes, aucun doublon', await attendre(async () => {
      const ids = (await f1.liste(R)).map((x) => x.id).sort();
      return ids.length === 2 && ids[0] === 'CHA-DIMF1-1' && ids[1] === 'CHA-DIMF1-2';
    }, 15000), (await f1.liste(R)).map((x) => x.id));
    verifier('le fileul reçoit la confirmation, les lignes du fichier sont effacées', await attendre(async () => {
      const l = (await f1.liste('demandesImport')).find((x) => x.id === 'DIM-F1-1');
      return !!l && l.data.etat === 'appliquee' && Array.isArray(l.data.lignes) && l.data.lignes.length === 0;
    }, 15000));
    /* le fileul lève le marquage « en attente de la mère » : il l'écrit sur la même fiche (champ à champ) ; la confirmation de la mère n'en est pas écrasée */
    await f1.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F1-1', champs: { marquageLeve: true } });
    verifier('la fiche porte la confirmation de la mère ET le suivi du fileul : champ à champ, aucune des deux écritures ne détruit l\'autre', await attendre(async () => {
      const l = (await f2.liste('demandesImport')).find((x) => x.id === 'DIM-F1-1');
      return !!l && l.data.etat === 'appliquee' && l.data.marquageLeve === true && l.data.resultatLot === 'IMP-MERE-DIMF1' && l.data.serieIdentifiants === 'DIMF1';
    }, 15000), (await f2.liste('demandesImport')).map((x) => x.data));

    /* 4. DEUX FILEULS IMPORTENT LE MÊME CODE : la mère refuse la seconde demande en nommant ; le second fileul ajoute SA restitution sur la même fiche */
    await f2.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F2-1', champs: demande('DIMF2', { demandePar: 'GESTIONNAIRE DEUX', lotLocalId: 'LOT-DIMF2-1' }) });
    verifier('la seconde demande (même code) arrive à la mère', await attendre(async () => (await compte('demandesImport')) === 2, 15000));
    const verdict2 = { etat: 'refusee', resultatCode: 'DOUBLON_MAGASIN', resultatMotif: 'rejoué à la mère, le fichier est refusé (ligne 2, Code) : une fiche équivalente est déjà tenue', resultatGeste: 'Retirez la ligne.', traitePar: 'Mère', traiteLe: '2026-11-12', lignes: [] };
    verifier('la mère refuse la seconde demande en nommant le code', (await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F2-1', champs: verdict2 }).then((x) => x.json)).statut === 'acceptee');
    verifier('le second fileul reçoit le refus nommé (code, motif, geste)', await attendre(async () => {
      const l = (await f2.liste('demandesImport')).find((x) => x.id === 'DIM-F2-1');
      return !!l && l.data.etat === 'refusee' && l.data.resultatCode === 'DOUBLON_MAGASIN' && /rejoué à la mère/.test(l.data.resultatMotif) && !!l.data.resultatGeste;
    }, 15000));
    await f2.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F2-1', champs: { restitution: 'faite', restitutionLe: '2026-11-12', restitutionArchives: 1, restitutionGardees: [] } });
    verifier('la restitution du fileul s\'ajoute au refus de la mère sur la MÊME fiche : la mère garde les deux, le verdict et la restitution',
      await attendre(async () => {
        const l = (await f1.liste('demandesImport')).find((x) => x.id === 'DIM-F2-1');
        return !!l && l.data.etat === 'refusee' && l.data.resultatCode === 'DOUBLON_MAGASIN' && l.data.restitution === 'faite' && l.data.restitutionArchives === 1;
      }, 15000), (await f1.liste('demandesImport')).map((x) => x.data));
    verifier('la mère n\'a écrit AUCUNE fiche pour le refusé : la configuration reste celle de la première demande (la mère l\'emporte)', (await compte(R)) === 2);

    /* 5. LA MÈRE EST INJOIGNABLE : la demande attend dans la file du fileul (hors ligne d'abord), sans rien perdre ; elle arrive UNE fois au retour */
    m.reseau.regler('ferme');
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-3', champs: demande('DIMF3', { fichier: 'hors-ligne.xlsx', lotLocalId: 'LOT-DIMF3-1' }) });
    await dormir(700);
    verifier('mère injoignable : la demande reste dans la file du fileul (en attente), la mère ne l\'a pas', (await f1.etat()).en_attente >= 1 && (await compte('demandesImport')) === 2, await f1.etat());
    m.reseau.regler('ouvert');
    verifier('le réseau revient : la demande arrive à la mère, une seule fois', await attendre(async () => (await compte('demandesImport')) === 3 && await f1.vide(), 20000));
    /* ... puis la mère elle-même est TUÉE (SIGKILL) avec une demande en file, et relancée sur sa base */
    await m.mere.tuer();
    await f2.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F2-2', champs: demande('DIMF4', { demandePar: 'GESTIONNAIRE DEUX', fichier: 'mere-tuee.xlsx', lotLocalId: 'LOT-DIMF4-1' }) });
    await dormir(700);
    await m.mere.demarrer();
    verifier('mère tuée puis relancée : la demande de la file arrive, sans doublon', await attendre(async () => (await compte('demandesImport')) === 4 && await f2.vide(), 25000), await compte('demandesImport'));

    /* 6. LE FILEUL RETIRE SA DEMANDE avant la réponse : elle passe à « retirée » et ses lignes sont effacées */
    await f1.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F1-3', champs: { etat: 'retiree', retireePar: 'GESTIONNAIRE', retireeLe: '2026-11-12', lignes: [] } });
    verifier('la mère voit la demande retirée (elle ne l\'applique plus) et sans ses lignes', await attendre(async () => {
      const l = (await f2.liste('demandesImport')).find((x) => x.id === 'DIM-F1-3');
      return !!l && l.data.etat === 'retiree' && Array.isArray(l.data.lignes) && l.data.lignes.length === 0;
    }, 15000));

    /* 7. le relais ne voit que du chiffré : on DÉCODE chaque enveloppe, on cherche la cellule dans les octets et on mesure l'entropie */
    await attendre(async () => { const e = await etatMere(); return e.rep_seq === e.seq_max; }, 20000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const journal = brut.lignes.filter((l) => l.dir === 'journal');
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = journal.map((l) => Buffer.from(l.ct, 'base64'));
    const mots = /Zébulon|CELLULE-SECRETE|demandesImport|DOUBLON_MAGASIN|serieIdentifiants|restitution|CHA-DIMF1/;
    const motsOctets = /Z\xc3\xa9bulon|CELLULE-SECRETE|demandesImport|DOUBLON_MAGASIN|serieIdentifiants|restitution|CHA-DIMF1/;
    verifier('le relais détient le journal de la mère en enveloppes', journal.length >= 1, journal.length);
    verifier('ni la cellule, ni le nom de la collection, ni les identifiants, ni le code du verdict, ni la restitution ne sont lisibles au relais, même après décodage des octets',
      !mots.test(tout) && octets.every((b) => !motsOctets.test(b.toString('latin1'))), tout.length);
    const gros = octets.filter((b) => b.length >= 250);
    verifier('chaque enveloppe porteuse a l\'entropie d\'un chiffrement (> 7 bits/octet)', gros.length >= 1 && gros.every((b) => entropie(b) > 7.0), octets.map((b) => [b.length, +entropie(b).toFixed(2)]));
    const claires = journal.map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien la demande directe et ses lignes : l\'opacité ne vient pas d\'un contenu vide',
      claires.some((o) => o.collection === 'demandesImport' && JSON.stringify(o.champs || {}).includes(SECRET) && JSON.stringify(o.champs || {}).includes('serieIdentifiants')), claires.length);
    verifier('la clé de clinique n\'est nulle part au relais', !tout.includes(m.mere.opts.cle) && !tout.includes(m.clePair));

    /* 8. un téléphone ne la dépose pas (liste blanche du profil) et ne reçoit NI la demande, NI son verdict, NI la restitution, NI les fiches écrites : créés APRÈS l'appairage */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    await mob.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-M1-1', champs: demande('DIMM1', { demandeRole: 'medecin' }) });
    verifier('le téléphone qui tente de déposer une demande d\'import est refusé, nommé (droit_refuse)', await attendre(async () => (await mob.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000));
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-5', champs: demande('DIMF5', { fichier: 'apres-appairage.xlsx', lotLocalId: 'LOT-DIMF5-1' }) });
    await attendre(async () => (await compte('demandesImport')) === 5, 15000);
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F1-5', champs: { etat: 'refusee', resultatCode: 'RESULTAT_DIFFERENT', lignes: [] } });
    await m.mere.admin('POST', '/admin/referentiel', { collection: R, fiche: 'CHA-DIMF5-1', champs: ligne('DIMF5', 1) });
    await f1.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F1-5', champs: { restitution: 'faite' } });
    await dormir(1200);
    verifier('le téléphone ne reçoit AUCUNE demande d\'import (ni lignes, ni verdict, ni restitution) ni aucune fiche de configuration écrite par une demande', (await mob.liste('demandesImport')).length === 0 && (await mob.liste(R)).length === 0,
      [(await mob.liste('demandesImport')).length, (await mob.liste(R)).length]);
    verifier('la mère n\'a pas écrit la demande du téléphone', (await compte('demandesImport')) === 5);
    await m.fermer();
  },
  async IMP2() {
    titre('IMPORT-IMP2 · le Grand Stock chez le fileul : identité commune (une fiche par identifiant), variations ajoutées une fois, demande, refus partiel, mère coupée puis tuée, deux fileuls, relais opaque, rien vers un téléphone');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const etatMere = () => m.mere.admin('GET', '/admin/etat').then((r) => r.json);
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const refus = async (f, code) => (await f.etat()).a_traiter.some((x) => x.code === code);
    const STOCK_SECRET = 'ARTICLE-SECRET-IMP2-Quinquina';
    const ligneGS = [['Code article', 'Désignation', 'Catégorie', 'Unité', 'Quantité', 'N° de lot', 'Date de péremption'], ['MED1', STOCK_SECRET, 'Médicaments', 'Boîte', 100, 'L1', '2028-06-30'], ['MED1', STOCK_SECRET, 'Médicaments', 'Boîte', 50, 'L2', '2029-01-31']];
    const demande = (serie, extra) => ({
      etat: 'en_attente', jeu: 'grand-stock', jeuLibelle: 'Importation Grand Stock', fichier: 'inventaire.xlsx', demandePar: 'GESTIONNAIRE', demandeRole: 'stock', demandeLe: '2026-11-13',
      lignes: ligneGS, nbLignes: 2, aEcrire: 2,
      ecritureDirecte: true, serieIdentifiants: serie, lotLocal: 'IMP-2026-001', lotLocalId: 'LOT-' + serie + '-1', rangsEcrits: [2, 3], ...extra,
    });
    /* Les fiches d'une demande portent une identité déterministe `<COL>-<demande>-<rang>`, sa série et, pour un compteur, sa valeur de DÉPART (jamais le compteur lui-même : il voyage par ses variations). */
    const lot = (serie, rang, q) => ({ produitId: 'PRO-' + serie + '-1', numeroLot: 'L' + rang, serieDemande: serie, departCompteurs: { quantiteRestante: q }, statut: 'actif', lotImport: 'IMP-MERE-' + serie });
    const mouvement = (serie, rang, q) => ({ produitId: 'PRO-' + serie + '-1', type: 'entree', quantite: q, serieDemande: serie, reference: 'M00000' + rang, statut: 'actif' });

    /* 1. LE CATALOGUE NE S'ÉCRIT QUE PAR LA MÈRE : même une fiche née d'une demande est refusée au fileul (famille R) ; ses lots et mouvements, fiches descriptives, sont acceptés. */
    await f1.ecrire({ type: 'creer', collection: 'produits', fiche: 'PRO-DIMG1-1', champs: { code: 'MED1', serieDemande: 'DIMG1', departCompteurs: { stockGros: 150 } } });
    verifier('le catalogue des produits n\'est JAMAIS accepté d\'un fileul, même une fiche née d\'une demande : refus nommé (droit_refuse), la mère reste l\'autorité', await attendre(() => refus(f1, 'droit_refuse'), 15000), (await f1.etat()).a_traiter);
    verifier('la mère ne détient aucun produit du fileul', (await compte('produits')) === 0);

    /* 2. LA DEMANDE voyage avec ce que la mère doit reproduire ; la mère applique : MÊMES identifiants, UNE fiche par identifiant (pas de lot doublé) */
    const rd = await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1G-1', champs: demande('DIMG1') });
    verifier('la mère accepte la demande du Grand Stock (famille A) avec sa série et les lignes écrites', rd.fiche === 'DIM-F1G-1' && await attendre(async () => (await compte('demandesImport')) === 1, 15000), rd);
    for (const [i, q] of [100, 50].entries()) {
      const rl = await m.mere.admin('POST', '/admin/referentiel', { collection: 'lots', fiche: 'LOT-DIMG1-' + (i + 1), champs: lot('DIMG1', i + 1, q) }).then((x) => x.json);
      const rm = await m.mere.admin('POST', '/admin/referentiel', { collection: 'mouvements', fiche: 'MOU-DIMG1-' + (i + 1), champs: mouvement('DIMG1', i + 1, q) }).then((x) => x.json);
      verifier('la mère écrit le lot et le mouvement ' + (i + 1) + ' de la demande sous leurs identifiants communs', rl.statut === 'acceptee' && rm.statut === 'acceptee', [rl, rm]);
    }
    /* Le fileul PUBLIE à son tour (la mère a confirmé : sa fiche cesse d'être propre au poste) la fiche qu'il tient sous le MÊME identifiant : un seul lot, jamais deux. */
    await f1.ecrire({ type: 'creer', collection: 'lots', fiche: 'LOT-DIMG1-1', champs: lot('DIMG1', 1, 100) });
    verifier('la même identité écrite une seconde fois est refusée (fiche_existe) : un lot n\'existe jamais en double', await attendre(() => refus(f1, 'fiche_existe'), 15000), (await f1.etat()).a_traiter);
    verifier('la mère tient exactement DEUX lots et DEUX mouvements pour la demande (pas quatre)', (await compte('lots')) === 2 && (await compte('mouvements')) === 2, [await compte('lots'), await compte('mouvements')]);
    /* ... et corrige un champ d'une fiche tenue : champ à champ, jamais une seconde fiche. */
    await f1.ecrire({ type: 'modifier', collection: 'lots', fiche: 'LOT-DIMG1-1', champs: { emplacement: 'Rayon A' } });
    verifier('un champ ajouté par le fileul à une fiche que la mère détient se fusionne (champ à champ), toujours deux lots', await attendre(async () => {
      const l = (await f2.liste('lots')).find((x) => x.id === 'LOT-DIMG1-1');
      return !!l && l.data.emplacement === 'Rayon A' && l.data.lotImport === 'IMP-MERE-DIMG1' && (await f2.liste('lots')).length === 2;
    }, 15000), (await f2.liste('lots')).map((x) => x.id));
    const verdict = { etat: 'appliquee', resultatCode: '', resultatLot: 'IMP-MERE-DIMG1', resultatEcrits: 7, traitePar: 'Mère', traiteLe: '2026-11-13', lignes: [] };
    verifier('la mère confirme sur la MÊME fiche', (await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F1G-1', champs: verdict }).then((x) => x.json)).statut === 'acceptee');

    /* 3. LES VARIATIONS s'ajoutent UNE fois : une fiche par variation, jamais modifiée ; la même variation rejouée est refusée, elle ne compte pas deux fois */
    await f1.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F1~1~0', champs: { cle: 'lots/LOT-DIMG1-1/quantiteRestante', delta: -10, poste: 'F1' } });
    verifier('la variation de sortie du fileul est acceptée par la mère (une fiche ajoutée)', await attendre(async () => (await compte('deltasCompteurs')) === 1, 15000));
    await f1.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F1~1~0', champs: { cle: 'lots/LOT-DIMG1-1/quantiteRestante', delta: -10, poste: 'F1' } });
    verifier('la même variation rejouée est refusée (fiche_existe) : une sortie ne se compte jamais deux fois', await attendre(async () => (await f1.etat()).a_traiter.filter((x) => x.code === 'fiche_existe').length >= 2, 15000), (await f1.etat()).a_traiter);
    verifier('la mère ne détient qu\'UNE variation', (await compte('deltasCompteurs')) === 1);

    /* 4. DEUX FILEULS IMPORTENT LE MÊME INVENTAIRE : la mère refuse la seconde demande en nommant ; le second fileul ajoute SA restitution PARTIELLE (un article déjà sorti reste) sur la même fiche */
    await f2.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F2G-1', champs: demande('DIMG2', { demandePar: 'GESTIONNAIRE DEUX', lotLocalId: 'LOT-DIMG2-1' }) });
    verifier('la seconde demande (même inventaire) arrive à la mère', await attendre(async () => (await compte('demandesImport')) === 2, 15000));
    const verdict2 = { etat: 'refusee', resultatCode: 'DOUBLON_MAGASIN', resultatMotif: 'rejoué à la mère, le fichier est refusé (ligne 2, Code article) : l’article « MED1 » existe déjà dans le référentiel', resultatGeste: 'Retirez la ligne du fichier.', traitePar: 'Mère', traiteLe: '2026-11-13', lignes: [] };
    verifier('la mère refuse la seconde demande en nommant le code', (await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F2G-1', champs: verdict2 }).then((x) => x.json)).statut === 'acceptee');
    verifier('le second fileul reçoit le refus nommé (code, motif, geste)', await attendre(async () => {
      const l = (await f2.liste('demandesImport')).find((x) => x.id === 'DIM-F2G-1');
      return !!l && l.data.etat === 'refusee' && l.data.resultatCode === 'DOUBLON_MAGASIN' && /rejoué à la mère/.test(l.data.resultatMotif) && !!l.data.resultatGeste;
    }, 15000));
    await f2.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F2G-1', champs: { restitution: 'partielle', restitutionLe: '2026-11-13', restitutionArchives: 1, restitutionGardees: [{ collection: 'produits', id: 'PRO-DIMG2-1', code: 'STOCK_DEJA_SORTI', motif: 'une pièce émise ne se réécrit jamais' }] } });
    verifier('la restitution PARTIELLE du fileul s\'ajoute au refus de la mère sur la MÊME fiche : la mère garde le verdict ET la liste des fiches gardées',
      await attendre(async () => {
        const l = (await f1.liste('demandesImport')).find((x) => x.id === 'DIM-F2G-1');
        return !!l && l.data.etat === 'refusee' && l.data.resultatCode === 'DOUBLON_MAGASIN' && l.data.restitution === 'partielle' && l.data.restitutionGardees.length === 1 && l.data.restitutionGardees[0].code === 'STOCK_DEJA_SORTI';
      }, 15000), (await f1.liste('demandesImport')).map((x) => x.data));
    verifier('la mère n\'a écrit AUCUN lot pour le refusé : le stock reste celui de la première demande (150, deux lots), la mère l\'emporte', (await compte('lots')) === 2 && (await compte('mouvements')) === 2);

    /* 5. LA MÈRE EST INJOIGNABLE : la demande ET la variation du fileul attendent dans sa file (hors ligne d'abord), puis arrivent UNE fois ; la mère est ensuite TUÉE, relancée sur sa base */
    m.reseau.regler('ferme');
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1G-3', champs: demande('DIMG3', { fichier: 'hors-ligne.xlsx', lotLocalId: 'LOT-DIMG3-1' }) });
    await f1.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F1~2~0', champs: { cle: 'lots/LOT-DIMG1-2/quantiteRestante', delta: -5, poste: 'F1' } });
    await dormir(700);
    verifier('mère injoignable : la demande et la sortie restent dans la file du fileul, la mère ne les a pas', (await f1.etat()).en_attente >= 2 && (await compte('demandesImport')) === 2 && (await compte('deltasCompteurs')) === 1, await f1.etat());
    m.reseau.regler('ouvert');
    verifier('le réseau revient : la demande et la sortie arrivent à la mère, UNE fois chacune', await attendre(async () => (await compte('demandesImport')) === 3 && (await compte('deltasCompteurs')) === 2 && await f1.vide(), 20000), [await compte('demandesImport'), await compte('deltasCompteurs')]);
    await m.mere.tuer();
    await f2.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F2~1~0', champs: { cle: 'lots/LOT-DIMG1-1/quantiteRestante', delta: -3, poste: 'F2' } });
    await dormir(700);
    await m.mere.demarrer();
    verifier('mère tuée puis relancée : la sortie de la file arrive, sans doublon', await attendre(async () => (await compte('deltasCompteurs')) === 3 && await f2.vide(), 25000), await compte('deltasCompteurs'));
    verifier('les lots et mouvements de la mère n\'ont pas bougé : deux lots, deux mouvements', (await compte('lots')) === 2 && (await compte('mouvements')) === 2);

    /* 6. LE RELAIS ne voit que du chiffré : ni la désignation de l'article, ni les noms de collections de stock, ni la série, ni les identifiants */
    await attendre(async () => { const e = await etatMere(); return e.rep_seq === e.seq_max; }, 20000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const journal = brut.lignes.filter((l) => l.dir === 'journal');
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = journal.map((l) => Buffer.from(l.ct, 'base64'));
    const mots = /Quinquina|ARTICLE-SECRET|demandesImport|deltasCompteurs|departCompteurs|serieDemande|LOT-DIMG1|DOUBLON_MAGASIN|STOCK_DEJA_SORTI/;
    const motsOctets = /Quinquina|ARTICLE-SECRET|demandesImport|deltasCompteurs|departCompteurs|serieDemande|LOT-DIMG1|DOUBLON_MAGASIN|STOCK_DEJA_SORTI/;
    verifier('le relais détient le journal de la mère en enveloppes', journal.length >= 1, journal.length);
    verifier('ni la désignation de l\'article, ni les collections du stock, ni les identifiants, ni le code du verdict ne sont lisibles au relais, même après décodage des octets', !mots.test(tout) && octets.every((b) => !motsOctets.test(b.toString('latin1'))), tout.length);
    const gros = octets.filter((b) => b.length >= 250);
    verifier('chaque enveloppe porteuse a l\'entropie d\'un chiffrement (> 7 bits/octet)', gros.length >= 1 && gros.every((b) => entropie(b) > 7.0), octets.map((b) => [b.length, +entropie(b).toFixed(2)]));
    const claires = journal.map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien la demande du Grand Stock et ses lignes : l\'opacité ne vient pas d\'un contenu vide',
      claires.some((o) => o.collection === 'demandesImport' && JSON.stringify(o.champs || {}).includes(STOCK_SECRET)), claires.length);

    /* 7. UN TÉLÉPHONE ne dépose pas la demande et ne reçoit NI la demande, NI ses lignes, NI les variations, NI les lots et mouvements écrits par une demande (hors de sa portée : le stock voyage aux
       mobiles selon leurs règles actuelles, non changées par ce lot) */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    await mob.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-M1G-1', champs: demande('DIMGM', { demandeRole: 'medecin' }) });
    verifier('le téléphone qui tente de déposer une demande de Grand Stock est refusé, nommé (droit_refuse)', await attendre(async () => (await mob.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000));
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1G-5', champs: demande('DIMG5', { fichier: 'apres-appairage.xlsx', lotLocalId: 'LOT-DIMG5-1' }) });
    await attendre(async () => (await compte('demandesImport')) === 4, 15000);
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'lots', fiche: 'LOT-DIMG5-1', champs: lot('DIMG5', 1, 100) });
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'mouvements', fiche: 'MOU-DIMG5-1', champs: mouvement('DIMG5', 1, 100) });
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F1G-5', champs: { etat: 'refusee', resultatCode: 'RESULTAT_DIFFERENT', lignes: [] } });
    await f1.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F1~3~0', champs: { cle: 'lots/LOT-DIMG5-1/quantiteRestante', delta: -1, poste: 'F1' } });
    await dormir(1200);
    const recu = async (col) => (await mob.liste(col)).length;
    verifier('le téléphone ne reçoit AUCUNE demande d\'import, AUCUNE variation, AUCUN lot ni mouvement écrit par une demande', (await recu('demandesImport')) === 0 && (await recu('deltasCompteurs')) === 0 && (await recu('lots')) === 0 && (await recu('mouvements')) === 0,
      [await recu('demandesImport'), await recu('deltasCompteurs'), await recu('lots'), await recu('mouvements')]);
    verifier('la mère n\'a pas écrit la demande du téléphone', (await compte('demandesImport')) === 4);
    await m.fermer();
  },
});
