'use strict';
/* Scénario FIC1 (lot D5, EF-SYNC-18) : les FICHIERS NUMÉRISÉS par la synchronisation. Les métadonnées (la fiche d'un courrier ou d'un document du patient, le registre `fichiers`) voyagent par le journal comme
   toute fiche ; le BINAIRE voyage à part, par son empreinte SHA-256, en morceaux dont chacun porte la sienne, avec reprise.

   Ce que ce banc éprouve : le PROTOCOLE, avec la mère de référence (Node, `fichiers.js`) et des fileuls de référence (Node). Le code Dart (`sync_dart/lib/src/fichiers_mere.dart`, `stockage_fichiers.dart`, poste
   `sync/service_fichiers.dart`) est éprouvé par `apps/poste/test/fichiers_direct_sync_test.dart` (VRAIE mère Dart, trois VRAIS fileuls, mère arrêtée pour de vrai) ; la règle pure par `packages/domaine/test/
   fichiers_transfert_test.dart` et `fichiers_test.dart`. Ici, à DEUX postes (et un troisième quand il le faut) :

     1. les métadonnées D'ABORD : la fiche et le registre arrivent chez B pendant que le binaire n'y est pas, la mère n'a RIEN rangé ;
     2. une COUPURE au milieu de l'envoi : la mère ne range rien tant que l'ensemble n'est pas vérifié ; la mère est TUÉE puis relancée ; la REPRISE n'envoie que les morceaux manquants ;
     3. un morceau ALTÉRÉ en route est refusé (409 MORCEAU_ALTERE) et renvoyé, à l'envoi comme à la réception ; la reprise à la RÉCEPTION ne redemande pas ce que B a déjà ;
     4. le MÊME fichier déposé des deux côtés : une copie, une fiche de registre, aucun refus bruyant à « traiter » ;
     5. un poste dont le rôle ne lit pas la zone ne reçoit PAS le binaire (403 ZONE_REFUSEE, aucun octet) et ne peut pas non plus le déposer (RG-13) ;
     6. JAMAIS vers un téléphone : les cinq routes lui sont refusées, et le lot de sa tournée ne porte aucune fiche de fichier ;
     7. le relais ne voit RIEN du binaire (aucune fenêtre d'octets d'un fichier, aucun mot du texte, entropie d'un chiffrement) et n'a aucune enveloppe de fichier. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { dechiffrer } = require('./crypto');

const FIX = path.join(__dirname, '..', '..', '..', 'apps', 'poste', 'test', 'fixtures', 'fichiers');
const fx = (n) => fs.readFileSync(path.join(FIX, n));
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };
const TM = 4096;
const SECRET = 'Hyperglycémie-Secrète-FIC1';

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async FIC1() {
    if (process.env.SIGH_FILEUL === 'dart') { console.log('  (FIC1 non joué : le fileul Dart du banc n\'a pas de commandes de fichiers ; le code Dart est éprouvé par apps/poste/test/fichiers_direct_sync_test.dart)'); return; }
    titre('FICHIERS-FIC1 · métadonnées d\'abord, binaire par morceaux avec reprise, morceau altéré renvoyé, une copie, zone de lecture, jamais un téléphone, le relais ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2'); const f3 = await m.fileul('F3');
    const dossierMere = path.join(m.dir, 'fichiers-mere');
    const copiesMere = () => { let n = 0; for (const a of fs.existsSync(dossierMere) ? fs.readdirSync(dossierMere) : []) { if (a.length !== 2) continue; n += fs.readdirSync(path.join(dossierMere, a)).filter((f) => /^[0-9a-f]{64}\.(pdf|jpg|png|webp)$/.test(f)).length; } return n; };
    const partielsMere = (s) => { const p = path.join(dossierMere, '_partiels', s); return fs.existsSync(p) ? fs.readdirSync(p).length : 0; };
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const ecrireMeta = async (poste, ficheId, ref, nom, sha256, taille, mime, texte) => {
      await poste.ecrire({ type: 'creer', collection: 'courriers', fiche: ficheId, champs: { reference: ref, fichier: { sha256, nom, nomNormalise: `2026-08-20_ARR_${ref.slice(-4)}.${nom.split('.').pop()}`, mime, taille, texteIndexe: !!texte } } });
      return poste.ecrire({ type: 'creer', collection: 'fichiers', fiche: 'FIC-' + sha256.slice(0, 16), champs: { sha256, taille, mime, texteIndexe: !!texte, texte: texte || '' } });
    };
    const jpg = fx('scan.jpg'); const shaJpg = sha(jpg); const nJpg = Math.ceil(jpg.length / TM);

    /* 1. LES MÉTADONNÉES D'ABORD : la fiche et le registre sont chez B, le binaire n'y est pas, la mère n'a rien rangé. */
    const r1 = await f1.post('/fichier/ranger', { chemin: path.join(FIX, 'scan.jpg'), famille: 'courrier', zone: 0 });
    verifier('F1 range le scan dans SON stockage sous son empreinte SHA-256', r1.json.sha256 === shaJpg && r1.json.nouveau === true, r1.json);
    await ecrireMeta(f1, 'C1', 'ARR-2026-0001', 'scan.jpg', shaJpg, jpg.length, 'image/jpeg', SECRET);
    verifier('la fiche du courrier et le registre par empreinte arrivent chez F2 (métadonnées d\'abord)', await attendre(async () => (await f2.liste('courriers')).length === 1 && (await f2.liste('fichiers')).length === 1, 15000));
    verifier('chez F2 le binaire N\'EST PAS là (état absent) : jamais un fichier fantôme, et la mère n\'a rien rangé', (await f2.get('/fichier/etat?sha256=' + shaJpg)).etat === 'absent' && copiesMere() === 0);
    verifier('le texte indexé du registre voyage avec les métadonnées : la recherche marche avant le binaire', (await f2.liste('fichiers'))[0].data.texte === SECRET);

    /* 2. LA COUPURE au milieu : la mère ne range rien tant que l'ensemble n'est pas vérifié ; elle est TUÉE puis relancée ; la REPRISE n'envoie que ce qui manque. */
    const c1 = await f1.post('/fichier/envoyer', { sha256: shaJpg, famille: 'courrier', role: 'admin', tailleMorceau: TM, coupureApres: 5 });
    verifier('l\'envoi est coupé après cinq morceaux (réseau coupé au milieu)', c1.json.coupe === true && c1.json.envoyes === 5 && c1.json.complet === false, c1.json);
    verifier('la mère garde les cinq morceaux vérifiés, ne range PAS le fichier', partielsMere(shaJpg) === 5 && copiesMere() === 0);
    const b1 = await f2.post('/fichier/recevoir', { sha256: shaJpg, famille: 'courrier', role: 'admin', tailleMorceau: TM });
    verifier('F2 vient chercher le fichier : la mère ne l\'a pas encore (404), F2 attend sans erreur ni fichier vide', b1.json.absentMere === true && b1.json.present === false, b1.json);
    await m.mere.tuer(); await m.mere.demarrer();
    const c2 = await f1.post('/fichier/envoyer', { sha256: shaJpg, famille: 'courrier', role: 'admin', tailleMorceau: TM });
    verifier('REPRISE après SIGKILL de la mère : le dépôt est rouvert, SEULS les morceaux manquants repartent, l\'ensemble est vérifié et rangé', c2.json.complet === true && c2.json.envoyes === nJpg - 5 && c2.json.renvoyes === 0, [c2.json, nJpg]);
    verifier('la mère n\'a qu\'UNE copie, intacte (empreinte relue), et plus un seul morceau en attente', copiesMere() === 1 && partielsMere(shaJpg) === 0 && sha(fs.readFileSync(path.join(dossierMere, shaJpg.slice(0, 2), shaJpg + '.jpg'))) === shaJpg);
    const c3 = await f1.post('/fichier/envoyer', { sha256: shaJpg, famille: 'courrier', role: 'admin', tailleMorceau: TM });
    verifier('IDEMPOTENCE : un envoi rejoué après le rangement ne renvoie aucun morceau et ne crée pas de seconde copie', c3.json.complet === true && c3.json.envoyes === 0 && copiesMere() === 1, c3.json);

    /* 3. UN MORCEAU ALTÉRÉ est refusé et renvoyé, à l'envoi comme à la réception ; la reprise à la réception ne redemande pas ce que B a déjà. */
    const png = fx('scan.png'); const shaPng = sha(png); const nPng = Math.ceil(png.length / TM);
    await f1.post('/fichier/ranger', { chemin: path.join(FIX, 'scan.png'), famille: 'courrier', zone: 0 });
    const e1 = await f1.post('/fichier/envoyer', { sha256: shaPng, famille: 'courrier', role: 'admin', tailleMorceau: TM, alterer: 2 });
    verifier('un morceau altéré en route est refusé par la mère (409 MORCEAU_ALTERE) et RENVOYÉ : un renvoi, fichier complet', e1.json.complet === true && e1.json.renvoyes === 1 && e1.json.envoyes === nPng, e1.json);
    const e2 = await f2.post('/fichier/recevoir', { sha256: shaPng, famille: 'courrier', role: 'admin', tailleMorceau: TM, alterer: 1 });
    verifier('un morceau altéré à la réception est refusé par F2 et redemandé ; le fichier rangé est intact', e2.json.present === true && e2.json.renvoyes === 1 && (await f2.get('/fichier/etat?sha256=' + shaPng)).etat === 'present');
    const pdf = fx('courrier-texte.pdf'); const shaPdf = sha(pdf); const nPdf = Math.ceil(pdf.length / TM);
    await f1.post('/fichier/ranger', { chemin: path.join(FIX, 'courrier-texte.pdf'), famille: 'courrier', zone: 0 });
    await f1.post('/fichier/envoyer', { sha256: shaPdf, famille: 'courrier', role: 'admin', tailleMorceau: TM });
    const r3a = await f3.post('/fichier/recevoir', { sha256: shaPdf, famille: 'courrier', role: 'admin', tailleMorceau: TM, coupureApres: 2 });
    verifier('F3 coupé en pleine réception : deux morceaux reçus, rien de rangé', r3a.json.coupe === true && r3a.json.recus === 2 && (await f3.get('/fichier/etat?sha256=' + shaPdf)).etat === 'absent' && (await f3.get('/fichier/etat?sha256=' + shaPdf)).partiels === 2);
    const r3b = await f3.post('/fichier/recevoir', { sha256: shaPdf, famille: 'courrier', role: 'admin', tailleMorceau: TM });
    verifier('REPRISE à la réception : F3 ne redemande que les morceaux manquants et range le fichier vérifié', r3b.json.present === true && r3b.json.recus === nPdf - 2 && (await f3.get('/fichier/etat?sha256=' + shaPdf)).partiels === 0, r3b.json);

    /* 4. LE MÊME FICHIER des deux côtés : une copie, une fiche de registre, aucun refus bruyant. */
    const webp = fx('scan.webp'); const shaWebp = sha(webp);
    await f1.post('/fichier/ranger', { chemin: path.join(FIX, 'scan.webp'), famille: 'patient', zone: 1 });
    await f2.post('/fichier/ranger', { chemin: path.join(FIX, 'scan.webp'), famille: 'patient', zone: 1 });
    const avant = copiesMere();
    const d1 = await f1.post('/fichier/envoyer', { sha256: shaWebp, famille: 'patient', type: 'Pièce d’identité', role: 'reception', tailleMorceau: TM });
    const d2 = await f2.post('/fichier/envoyer', { sha256: shaWebp, famille: 'patient', type: 'Pièce d’identité', role: 'reception', tailleMorceau: TM });
    verifier('le même fichier déposé des deux côtés : le second envoi est COMPLET d\'emblée (aucun morceau), la mère a UNE copie de plus', d1.json.complet && d2.json.complet && d2.json.envoyes === 0 && copiesMere() === avant + 1, [d1.json, d2.json]);
    await f1.ecrire({ type: 'creer', collection: 'fichiers', fiche: 'FIC-' + shaWebp.slice(0, 16), champs: { sha256: shaWebp, taille: webp.length, texteIndexe: false, texte: '' } });
    await f2.ecrire({ type: 'creer', collection: 'fichiers', fiche: 'FIC-' + shaWebp.slice(0, 16), champs: { sha256: shaWebp, taille: webp.length, texteIndexe: false, texte: '' } });
    verifier('la seconde création de la fiche de registre est acceptée sans effet : une fiche par empreinte, aucun refus à « traiter »', await attendre(async () => (await compte('fichiers')) === 2 && (await f1.etat()).en_attente === 0 && (await f2.etat()).en_attente === 0, 15000)
      && !(await f1.etat()).a_traiter.some((x) => x.code === 'fiche_existe') && !(await f2.etat()).a_traiter.some((x) => x.code === 'fiche_existe'), [(await f1.etat()).a_traiter, (await f2.etat()).a_traiter]);
    const metaWebp = JSON.parse(fs.readFileSync(path.join(dossierMere, shaWebp.slice(0, 2), shaWebp + '.json'), 'utf8'));
    verifier('la fiche d\'accompagnement ne cumule qu\'UN usage (patient, zone 1) pour les deux déposants', metaWebp.usages.length === 1 && metaWebp.usages[0].famille === 'patient' && metaWebp.usages[0].zone === 1, metaWebp);

    /* 5. LA ZONE : un poste dont le rôle ne lit pas la zone ne reçoit PAS le binaire, et ne peut pas le déposer (RG-13). */
    const crOctets = Buffer.concat([png, Buffer.from('CR-ZONE-2')]); const cheminCr = path.join(m.dir, 'cr.png'); fs.writeFileSync(cheminCr, crOctets); const shaCr = sha(crOctets);
    await f1.post('/fichier/ranger', { chemin: cheminCr, famille: 'patient', zone: 2 });
    const z0 = await f1.post('/fichier/envoyer', { sha256: shaCr, famille: 'patient', type: 'Compte rendu médical', role: 'medecin', tailleMorceau: TM });
    verifier('un MÉDECIN dépose un compte rendu (zone 2)', z0.json.complet === true, z0.json);
    const z1 = await f2.post('/fichier/recevoir', { sha256: shaCr, famille: 'patient', role: 'reception', tailleMorceau: TM });
    verifier('l\'ACCUEIL ne reçoit PAS le compte rendu : 403 ZONE_REFUSEE (RG-13), aucun octet, rien de rangé', z1.json.refus && z1.json.refus.code === 'ZONE_REFUSEE' && /RG-13/.test(z1.json.refus.motif) && (await f2.get('/fichier/etat?sha256=' + shaCr)).etat === 'absent', z1.json);
    const z2 = await f3.post('/fichier/recevoir', { sha256: shaCr, famille: 'patient', role: 'infirmier', tailleMorceau: TM });
    verifier('un INFIRMIER (profil clinique) le reçoit', z2.json.present === true, z2.json);
    await f2.post('/fichier/ranger', { chemin: cheminCr, famille: 'patient', zone: 2 });
    const z3 = await f2.post('/fichier/envoyer', { sha256: shaCr, famille: 'patient', type: 'Compte rendu médical', role: 'reception', tailleMorceau: TM });
    verifier('l\'accueil ne peut pas non plus DÉPOSER un compte rendu à la mère : ZONE_REFUSEE', z3.json.refus && z3.json.refus.code === 'ZONE_REFUSEE', z3.json);
    const z4 = await f1.post('/fichier/recevoir', { sha256: shaCr, famille: 'courrier', role: 'admin', tailleMorceau: TM });
    verifier('une empreinte déposée comme document du patient ne se lit pas par la famille « courrier » (PIECE_NON_RATTACHEE)', z4.json.refus && z4.json.refus.code === 'PIECE_NON_RATTACHEE', z4.json);

    /* 6. JAMAIS VERS UN TÉLÉPHONE : les cinq routes lui sont refusées, et le lot de sa tournée ne porte aucune fiche de fichier. */
    const { json: cm } = await m.mere.admin('POST', '/admin/code', { etiquette: 'Tel-direct', role: 'mobile', profil: 'reception' });
    const app = (await m.mere.direct('POST', '/appairage', { code: cm.code, uuid: 'tel-direct-0001', plateforme: 'banc' })).json;
    const ent = { Authorization: 'Bearer ' + app.jeton, 'x-sigh-role': 'admin' };
    const refusees = [];
    for (const [meth, chemin, corps] of [['GET', `/fichiers/info?sha256=${shaJpg}&famille=courrier`], ['GET', `/fichiers/morceau?sha256=${shaJpg}&i=0&famille=courrier`], ['POST', '/fichiers/ouvrir', {}], ['PUT', `/fichiers/morceau?sha256=${shaJpg}&i=0`], ['POST', '/fichiers/terminer', { sha256: shaJpg }]]) {
      const r = await m.mere.direct(meth, chemin, corps, ent); refusees.push([r.status, r.json.code]);
    }
    verifier('un téléphone appairé à la mère : les cinq routes de fichiers répondent 403 FICHIERS_INTERDITS_AU_MOBILE', refusees.length === 5 && refusees.every(([s, c]) => s === 403 && c === 'FICHIERS_INTERDITS_AU_MOBILE'), refusees);
    const mob = await m.mobile('M1', { profil: 'reception' });
    const lotInterdit = await m.mere.admin('POST', '/admin/lot', { uuid: mob.uuid, fiches: [{ collection: 'courriers', id: 'C1' }, { collection: 'fichiers', id: 'FIC-' + shaJpg.slice(0, 16) }], ttl_ms: 60000 });
    verifier('un lot de tournée qui NOMME un courrier ou un registre de fichiers est REFUSÉ en nommant (422 fichiers_interdits_au_mobile) : rien n\'est publié', lotInterdit.status === 422 && lotInterdit.json.code === 'fichiers_interdits_au_mobile', lotInterdit);
    await dormir(2500);
    const versMobile = (await m.relais.direct('GET', '/banc/tout')).json.lignes.filter((l) => l.dir === 'vers_mobile' && l.appareil === mob.uuid);
    const collectionsMobile = versMobile.flatMap((l) => (dechiffrer(cleClinique, l).ops || []).map((o) => o.collection));
    verifier('le téléphone ne reçoit ni fiche de fichier, ni registre, ni binaire : aucune de ces collections ne figure dans ce que le relais lui a distribué',
      (await mob.liste('courriers')).length === 0 && (await mob.liste('fichiers')).length === 0 && !collectionsMobile.some((c) => ['courriers', 'fichiers', 'documentsPatient'].includes(c)), [collectionsMobile, (await mob.liste('courriers')).length]);

    /* 7. LE RELAIS NE VOIT RIEN du binaire. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = brut.lignes.map((l) => Buffer.from(l.ct, 'base64'));
    const fenetres = [['courrier-texte.pdf', pdf], ['scan.png', png], ['scan.jpg', jpg], ['scan.webp', webp]].map(([n, b]) => b.subarray(1000, 1064));
    verifier('le relais détient le journal chiffré de la mère (les métadonnées des fichiers y sont), pas un octet de binaire : aucune fenêtre de 64 octets d\'un fichier, ni en clair ni en base64',
      brut.lignes.length >= 3 && fenetres.every((w) => !octets.some((o) => o.includes(w)) && !tout.includes(w.toString('base64'))), brut.lignes.length);
    verifier('aucun mot du texte indexé, aucun nom de fichier, aucun type de pièce en clair, même après décodage base64', !new RegExp(SECRET + '|scan\\.jpg|%PDF|JFIF|courriers|fichiers').test(tout) && octets.every((o) => !new RegExp(SECRET + '|scan\\.jpg|%PDF|courriers|fichiers').test(o.toString('latin1'))));
    const gros = octets.filter((o) => o.length >= 250);
    verifier('chaque enveloppe a l\'entropie d\'un chiffrement (> 7 bits/octet), pas un simple encodage', gros.length >= 2 && gros.every((o) => entropie(o) > 7.0), octets.map((o) => [o.length, +entropie(o).toFixed(2)]));
    verifier('aucune enveloppe de FICHIER au relais (le binaire ne le traverse jamais) et rien d\'aussi gros qu\'un morceau', !brut.lignes.some((l) => /fichier/.test(l.dir)) && Math.max(...octets.map((o) => o.length)) < TM * 2, brut.lignes.map((l) => l.dir));
    verifier('le code du relais n\'a aucune route de fichier', !/fichiers?\//.test(fs.readFileSync(path.join(__dirname, 'relais.js'), 'utf8')));
    await m.fermer();
  },
});
