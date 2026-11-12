'use strict';
/* Scénario IMP1 (lot IMP-C, réponse Q5 de la Direction du 10/11/2026) : la DEMANDE D'IMPORT d'un fileul à la mère. Un référentiel de configuration (famille R) importé à un fileul est refusé
   par la règle existante ; le fileul dépose une demande (`demandesImport`, famille A : champ à champ, dans les deux sens), la mère la reçoit, rejoue l'analyse sous le rôle de l'auteur
   (règle de référence : `packages/domaine/lib/src/import/demande_import.dart`, éprouvée par `demande_import_test.dart` et `apps/poste/test/demandes_import_sync_test.dart`) et écrit le verdict nommé
   sur la même fiche, qui revient au fileul. Ici, le PROTOCOLE : le relais ne voit que du chiffré (les lignes du fichier portent des valeurs de cellule), la fiche voyage dans les deux sens, les lignes
   sont effacées au verdict, et un téléphone ne l'écrit ni ne la reçoit. */
const { dechiffrer } = require('./crypto');

const SECRET = 'CELLULE-SECRETE-IMP1-Zébulon';
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async IMP1() {
    titre('IMPORT-IMP1 · le fileul dépose une demande, la mère répond sur la même fiche, le relais ne voit que du chiffré, le téléphone ne la voit pas');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1');
    const etatMere = () => m.mere.admin('GET', '/admin/etat').then((r) => r.json);
    const demande = {
      etat: 'en_attente', jeu: 'assureurs', jeuLibelle: 'Importation des compagnies d’assurance', fichier: 'compagnies.xlsx', demandePar: 'GESTIONNAIRE', demandeRole: 'stock', demandeLe: '2026-11-12',
      lignes: [['Code', 'Nom'], ['SUNU', SECRET]], nbLignes: 1, aEcrire: 1,
    };

    /* 1. le fileul dépose : la collection est de famille A, la mère accepte avec un seq */
    const r = await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-1', champs: demande });
    verifier('la mère accepte la demande d\'un fileul (famille A) et lui donne un seq', r.fiche === 'DIM-F1-1' && await attendre(async () => (await etatMere()).seq_max >= 1, 15000), r);
    verifier('elle la détient avec ses lignes (la mère doit pouvoir rejouer)', await attendre(async () => (await m.mere.admin('GET', '/admin/compte?collection=demandesImport')).json.n === 1, 15000));

    /* 2. le verdict est écrit par la mère sur la MÊME fiche, les lignes sont effacées ; il revient au fileul */
    const verdict = { etat: 'refusee', resultatCode: 'DOUBLON_MAGASIN', resultatMotif: 'rejoué à la mère, le fichier est refusé : une fiche équivalente est déjà tenue', resultatGeste: 'Retirez la ligne.', traitePar: 'Mère', traiteLe: '2026-11-12', lignes: [] };
    const rv = await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F1-1', champs: verdict }).then((x) => x.json);
    verifier('la mère écrit son verdict sur la fiche de la demande', rv.statut === 'acceptee', rv);
    verifier('le fileul reçoit le verdict nommé (code, motif, geste) sur SA demande', await attendre(async () => {
      const l = (await f1.liste('demandesImport'))[0];
      return !!l && l.data.etat === 'refusee' && l.data.resultatCode === 'DOUBLON_MAGASIN' && /rejoué à la mère/.test(l.data.resultatMotif);
    }, 15000), (await f1.liste('demandesImport')).map((x) => x.data));
    const apres = (await f1.liste('demandesImport'))[0].data;
    verifier('les lignes du fichier sont effacées de la demande, la demande garde son auteur et son jeu', Array.isArray(apres.lignes) && apres.lignes.length === 0 && apres.demandePar === 'GESTIONNAIRE' && apres.jeu === 'assureurs', apres);

    /* 3. le relais ne voit que du chiffré : on DÉCODE chaque enveloppe, on cherche la cellule dans les octets et on mesure l'entropie */
    await attendre(async () => { const e = await etatMere(); return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const journal = brut.lignes.filter((l) => l.dir === 'journal');
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = journal.map((l) => Buffer.from(l.ct, 'base64'));
    verifier('le relais détient le journal de la mère en enveloppes', journal.length >= 1, journal.length);
    verifier('ni la cellule, ni le nom de la collection, ni le code du verdict ne sont lisibles au relais, même après décodage des octets',
      !/Zébulon|CELLULE-SECRETE|demandesImport|DOUBLON_MAGASIN/.test(tout) && octets.every((b) => !/Z\xc3\xa9bulon|CELLULE-SECRETE|demandesImport|DOUBLON_MAGASIN/.test(b.toString('latin1'))), tout.length);
    const gros = octets.filter((b) => b.length >= 250);
    verifier('chaque enveloppe porteuse a l\'entropie d\'un chiffrement (> 7 bits/octet)', gros.length >= 1 && gros.every((b) => entropie(b) > 7.0), octets.map((b) => [b.length, +entropie(b).toFixed(2)]));
    const claires = journal.map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien la demande et ses lignes : l\'opacité ne vient pas d\'un contenu vide',
      claires.some((o) => o.collection === 'demandesImport' && JSON.stringify(o.champs || {}).includes(SECRET)), claires.length);
    verifier('la clé de clinique n\'est nulle part au relais', !tout.includes(m.mere.opts.cle) && !tout.includes(m.clePair));

    /* 4. un téléphone ne la dépose pas (liste blanche du profil) et ne la reçoit pas : les fiches sont créées APRÈS l'appairage */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    await mob.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-M1-1', champs: { ...demande, demandeRole: 'medecin' } });
    verifier('le téléphone qui tente de déposer une demande d\'import est refusé, nommé (droit_refuse)', await attendre(async () => (await mob.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000));
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-2', champs: { ...demande, fichier: 'autre.xlsx' } });
    await attendre(async () => (await m.mere.admin('GET', '/admin/compte?collection=demandesImport')).json.n === 2, 15000);
    await dormir(900);
    verifier('le téléphone ne reçoit AUCUNE demande d\'import (ni lignes, ni verdict)', (await mob.liste('demandesImport')).length === 0, (await mob.liste('demandesImport')).length);
    verifier('la mère n\'a pas écrit la demande du téléphone', (await m.mere.admin('GET', '/admin/compte?collection=demandesImport')).json.n === 2);
    await m.fermer();
  },
});
