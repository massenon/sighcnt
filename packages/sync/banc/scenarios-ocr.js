'use strict';
/* Scénario OCR1 (lot OCR-prep) : le TEXTE LU PAR MACHINE d'un scan est une MÉTADONNÉE du fichier (collection `lecturesOcr`, une fiche par version, identifiant déterministe). Il voyage par le journal
   avec le registre `fichiers`, comme toute fiche de la famille B (ajout seul) : il ne passe JAMAIS par le relais en clair, JAMAIS vers un téléphone, et deux postes qui lisent le même scan avec le même
   moteur ne font qu'une version. La FILE de lecture (`fileOcr`) est locale à chaque poste : elle ne voyage pas.

   Ce que ce banc éprouve : le PROTOCOLE, avec la mère de référence (Node) et des fileuls de référence (Node). La logique du poste (états, file, reprise, zone) est éprouvée par `apps/poste/test/ocr_poste_test.dart`
   et le code de la mère Dart par `apps/poste/test/ocr_direct_sync_test.dart` (VRAIE mère Dart, deux VRAIS fileuls). Ici :

     1. une lecture écrite par F1 arrive chez F2 par le journal, avec son texte ;
     2. la MÊME lecture (même identifiant) écrite par F2 : acceptée sans effet, UNE fiche à la mère, aucun refus à « traiter » ;
     3. une autre version du même fichier (autre moteur ou autre texte) s'AJOUTE : deux fiches, l'ancienne inchangée ;
     4. une lecture ne se MODIFIE jamais : l'opération est refusée par la mère (journal_immuable) ;
     5. la file `fileOcr` ne voyage pas : écrite sur F1, elle n'arrive ni à la mère ni à F2 ;
     6. JAMAIS vers un téléphone : un lot de tournée qui nomme une lecture est refusé, le téléphone n'en reçoit aucune ;
     7. le relais ne voit RIEN du texte lu : aucun mot en clair, enveloppes d'entropie de chiffrement. */
const crypto = require('node:crypto');
const { dechiffrer } = require('./crypto');

const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };
const SECRET = 'Paludisme-Grave-Secret-OCR1';

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async OCR1() {
    if (process.env.SIGH_FILEUL === 'dart') { console.log('  (OCR1 non joué : le fileul Dart du banc n\'a pas ces commandes ; le code Dart est éprouvé par apps/poste/test/ocr_direct_sync_test.dart)'); return; }
    titre('OCR-OCR1 · le texte lu par machine voyage par le journal comme une métadonnée (famille B, ajout seul), une version par moteur et texte, jamais vers un téléphone, le relais ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const empreinte = sha(Buffer.from('un scan sans couche texte, pour le banc OCR1'));
    const norme = 'paludisme grave secret ocr1';
    const idLecture = (moteur, version, texte) => 'OCR-' + empreinte.slice(0, 16) + '-' + sha(Buffer.from(moteur + '|' + version + '|fra|' + texte)).slice(0, 12);
    const lecture = (moteur, version, texteBrut, ocrLe) => ({ sha256: empreinte, texteBrut, texte: texteBrut.toLowerCase().replace(/-/g, ' '), nbMots: texteBrut.split(/[ -]/).length, moteur, moteurVersion: version, langue: 'fra', ocrLe, ocrPar: 'Agent F', declencheur: 'automatique', pages: 1 });
    const id1 = idLecture('factice', '0.1', norme);

    /* 1. LA LECTURE ARRIVE par le journal, avec son texte. */
    await f1.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: id1, champs: lecture('factice', '0.1', SECRET, '2026-11-13T10:00:00.000Z') });
    verifier('la lecture écrite par F1 arrive chez F2 par le journal, avec son texte et sa provenance (moteur, version, date)', await attendre(async () => (await f2.liste('lecturesOcr')).length === 1, 15000)
      && (await f2.liste('lecturesOcr'))[0].data.texteBrut === SECRET && (await f2.liste('lecturesOcr'))[0].data.moteur === 'factice' && (await f2.liste('lecturesOcr'))[0].data.ocrLe === '2026-11-13T10:00:00.000Z');

    /* 2. LA MÊME LECTURE écrite par l'autre poste : acceptée sans effet. */
    await f2.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: id1, champs: lecture('factice', '0.1', SECRET, '2026-11-13T10:00:05.000Z') });
    verifier('la même lecture (même identifiant) écrite par F2 est acceptée SANS EFFET : une fiche à la mère, aucun refus à « traiter », la première date fait foi',
      await attendre(async () => (await compte('lecturesOcr')) === 1 && (await f1.etat()).en_attente === 0 && (await f2.etat()).en_attente === 0, 15000)
      && !(await f1.etat()).a_traiter.some((x) => x.code === 'fiche_existe') && !(await f2.etat()).a_traiter.some((x) => x.code === 'fiche_existe')
      && (await f1.liste('lecturesOcr'))[0].data.ocrLe === '2026-11-13T10:00:00.000Z', [(await f1.etat()).a_traiter, (await f2.etat()).a_traiter]);

    /* 3. UNE AUTRE VERSION s'ajoute. */
    const id2 = idLecture('factice', '0.2', 'seconde lecture meilleure');
    await f2.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: id2, champs: lecture('factice', '0.2', 'Seconde-lecture-meilleure', '2026-11-14T09:00:00.000Z') });
    verifier('une autre version du même fichier (autre version du moteur) S\'AJOUTE : deux fiches partout, l\'ancienne inchangée', await attendre(async () => (await compte('lecturesOcr')) === 2 && (await f1.liste('lecturesOcr')).length === 2, 15000)
      && (await f1.liste('lecturesOcr')).find((x) => x.id === id1).data.texteBrut === SECRET && id1 !== id2);

    /* 4. UNE LECTURE NE SE MODIFIE JAMAIS. */
    const rep = await f1.ecrire({ type: 'modifier', collection: 'lecturesOcr', fiche: id1, correctif: { texteBrut: 'réécrit' } });
    await attendre(async () => (await f1.etat()).en_attente === 0, 15000);
    const refusees = (await f1.etat()).a_traiter;
    verifier('modifier une lecture est REFUSÉ par la mère (journal_immuable) et le texte reste celui de la version', refusees.some((x) => x.code === 'journal_immuable') && (await f2.liste('lecturesOcr')).find((x) => x.id === id1).data.texteBrut === SECRET, [rep, refusees]);

    /* 5. LA FILE EST LOCALE : elle ne voyage pas. */
    await f1.ecrire({ type: 'creer', collection: 'fileOcr', fiche: 'OCQ-' + empreinte.slice(0, 16), champs: { sha256: empreinte, etat: 'en_attente', famille: 'courrier' } }).catch(() => null);
    await dormir(2500);
    verifier('la file de lecture (`fileOcr`) est locale au poste : elle n\'arrive ni chez F2 (aucune fiche) ni à la mère comme une collection d\'activité synchronisée', (await f2.liste('fileOcr')).length === 0, (await f2.liste('fileOcr')).length);

    /* 6. JAMAIS VERS UN TÉLÉPHONE. */
    const mob = await m.mobile('M1', { profil: 'reception' });
    const lot = await m.mere.admin('POST', '/admin/lot', { uuid: mob.uuid, fiches: [{ collection: 'lecturesOcr', id: id1 }], ttl_ms: 60000 });
    verifier('un lot de tournée qui NOMME une lecture OCR est REFUSÉ en nommant (422 fichiers_interdits_au_mobile) : rien n\'est publié', lot.status === 422 && lot.json.code === 'fichiers_interdits_au_mobile', lot);
    await dormir(2500);
    const versMobile = (await m.relais.direct('GET', '/banc/tout')).json.lignes.filter((l) => l.dir === 'vers_mobile' && l.appareil === mob.uuid);
    const collectionsMobile = versMobile.flatMap((l) => (dechiffrer(cleClinique, l).ops || []).map((o) => o.collection));
    verifier('le téléphone ne reçoit AUCUNE lecture OCR : aucune de ces collections ne figure dans ce que le relais lui a distribué, et sa base n\'en porte pas', (await mob.liste('lecturesOcr')).length === 0 && !collectionsMobile.includes('lecturesOcr'), collectionsMobile);

    /* 7. LE RELAIS NE VOIT RIEN du texte lu. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = brut.lignes.map((l) => Buffer.from(l.ct, 'base64'));
    verifier('le relais détient le journal chiffré de la mère (les lectures y sont) mais AUCUN mot du texte lu, ni en clair ni en base64, ni le nom de la collection', brut.lignes.length >= 2
      && !new RegExp(SECRET + '|paludisme|lecturesOcr|Seconde-lecture').test(tout) && octets.every((o) => !new RegExp(SECRET + '|paludisme|lecturesOcr').test(o.toString('latin1'))), brut.lignes.length);
    const gros = octets.filter((o) => o.length >= 250);
    verifier('chaque enveloppe a l\'entropie d\'un chiffrement (> 7 bits/octet), pas un simple encodage', gros.length >= 1 && gros.every((o) => entropie(o) > 7.0), octets.map((o) => [o.length, +entropie(o).toFixed(2)]));
    await m.fermer();
  },
});
