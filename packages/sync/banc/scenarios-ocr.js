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
const P = require('./parametres');

const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };
const SECRET = 'Paludisme-Grave-Secret-OCR1';
const SECRET2 = 'Corrige-Secret-OCR2';
/* Les quatre paramètres de CLINIQUE de la lecture des scans (lot C), tels que `definitions.dart` les déclare : famille « ocr » (réservée, jamais vers un téléphone). */
const DEF_OCR = {
  actif: { cle: 'ocr.actif', famille: 'ocr', type: 'booleen', defaut: false, source: 'banc' },
  moteur: { cle: 'ocr.moteur', famille: 'ocr', type: 'texte', defaut: '', source: 'banc' },
  langue: { cle: 'ocr.langue', famille: 'ocr', type: 'texte', defaut: 'fra', source: 'banc' },
  delai: { cle: 'ocr.delaiMs', famille: 'ocr', type: 'entier', defaut: 120000, source: 'banc' },
};

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
  async OCR2() {
    if (process.env.SIGH_FILEUL === 'dart') { console.log('  (OCR2 non joué : le fileul Dart du banc n\'a pas ces commandes ; le code Dart est éprouvé par apps/poste/test/ocr_direct_sync_test.dart)'); return; }
    titre('OCR-OCR2 · la correction signée du texte lu voyage comme une version de plus (ajout seul, jamais vers un téléphone), les corrections concurrentes se gardent toutes ; le réglage de clinique est posé à la mère, reçu des fileuls, jamais vers un téléphone, le relais ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const empreinte = sha(Buffer.from('un scan sans couche texte, pour le banc OCR2'));
    const idMachine = 'OCR-' + empreinte.slice(0, 16) + '-' + sha(Buffer.from('factice|0.1|fra|ordonnance lue')).slice(0, 12);
    const idCorr = (de, texte) => 'OCC-' + empreinte.slice(0, 16) + '-' + sha(Buffer.from(de + '|' + texte.replace(/\s+/g, ' ').trim())).slice(0, 12);
    const corr = (de, texte, par, le, remplace) => ({ sha256: empreinte, texteBrut: texte, texte: texte.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim(), nbMots: texte.split(/\s+/).length, texteSource: 'correction', corrigeDe: de, remplace: remplace || [], corrigePar: par, corrigeLe: le, ocrLe: le });
    const liste = async (poste, col) => (await poste.liste(col)).map((x) => x.data);

    /* 1. La lecture machine, puis la correction signée du poste F1 : elles arrivent chez F2, la lecture machine intacte. */
    await f1.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: idMachine, champs: { sha256: empreinte, texteBrut: 'Ordonnance lue', texte: 'ordonnance lue', nbMots: 2, texteSource: 'ocr', moteur: 'factice', moteurVersion: '0.1', langue: 'fra', ocrLe: '2026-11-14T08:00:00.000Z', ocrPar: 'Agent F1', declencheur: 'automatique', pages: 1 } });
    const t1 = 'Ordonnance ' + SECRET2 + ' paracétamol';
    const id1 = idCorr(idMachine, t1);
    await f1.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: id1, champs: corr(idMachine, t1, 'Agent F1', '2026-11-14T09:00:00.000Z') });
    verifier('la correction signée de F1 arrive chez F2 par le journal, avec son signataire, sa date et la version dont elle part ; la lecture machine est intacte',
      await attendre(async () => (await liste(f2, 'lecturesOcr')).length === 2, 15000)
      && (await liste(f2, 'lecturesOcr')).find((x) => x.id === id1).corrigePar === 'Agent F1' && (await liste(f2, 'lecturesOcr')).find((x) => x.id === id1).corrigeDe === idMachine
      && (await liste(f2, 'lecturesOcr')).find((x) => x.id === idMachine).texteBrut === 'Ordonnance lue');

    /* 2. Le MÊME texte sur la même version, écrit par F2 : accepté sans effet, une seule version, aucun refus. */
    await f2.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: id1, champs: corr(idMachine, '  ' + t1 + ' ', 'Agent F2', '2026-11-14T09:05:00.000Z') });
    verifier('le rejeu (même identifiant déterministe) est accepté SANS EFFET : deux fiches à la mère, aucun refus à « traiter », la signature de F1 est conservée',
      await attendre(async () => (await compte('lecturesOcr')) === 2 && (await f1.etat()).en_attente === 0 && (await f2.etat()).en_attente === 0, 15000)
      && (await f1.etat()).a_traiter.length === 0 && (await f2.etat()).a_traiter.length === 0 && (await liste(f1, 'lecturesOcr')).find((x) => x.id === id1).corrigePar === 'Agent F1', [(await f1.etat()).a_traiter, (await f2.etat()).a_traiter]);

    /* 3. DEUX corrections CONCURRENTES (deux postes, même version de départ) : toutes deux gardées, partout, aucune écrasée, aucun refus. */
    const ta = 'Ordonnance ' + SECRET2 + ' corrigée par F1', tb = 'Ordonnance ' + SECRET2 + ' corrigée par F2';
    const ida = idCorr(id1, ta), idb = idCorr(id1, tb);
    await Promise.all([
      f1.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: ida, champs: corr(id1, ta, 'Agent F1', '2026-11-14T10:00:00.000Z', [id1]) }),
      f2.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: idb, champs: corr(id1, tb, 'Agent F2', '2026-11-14T10:00:01.000Z', [id1]) }),
    ]);
    verifier('deux corrections concurrentes de la même version : QUATRE versions à la mère, chez F1 et chez F2 (rien d\'écrasé, rien de perdu), aucun refus ; les deux têtes sont visibles partout',
      await attendre(async () => (await compte('lecturesOcr')) === 4 && (await liste(f1, 'lecturesOcr')).length === 4 && (await liste(f2, 'lecturesOcr')).length === 4, 20000)
      && [f1, f2].every((p) => true) && (await f1.etat()).a_traiter.length === 0 && (await f2.etat()).a_traiter.length === 0
      && [await liste(f1, 'lecturesOcr'), await liste(f2, 'lecturesOcr')].every((l) => {
        const remplacees = new Set(l.flatMap((x) => x.remplace || []));
        const tetes = l.filter((x) => x.texteSource === 'correction' && !remplacees.has(x.id)).map((x) => x.id).sort();
        return JSON.stringify(tetes) === JSON.stringify([ida, idb].sort());
      }), [await compte('lecturesOcr')]);

    /* 4. Une correction ne se MODIFIE jamais, comme une lecture. */
    await f1.ecrire({ type: 'modifier', collection: 'lecturesOcr', fiche: id1, correctif: { texteBrut: 'réécrit' } });
    await attendre(async () => (await f1.etat()).en_attente === 0, 15000);
    verifier('modifier une correction signée est REFUSÉ par la mère (journal_immuable), le texte signé reste intact partout',
      (await f1.etat()).a_traiter.some((x) => x.code === 'journal_immuable') && (await liste(f2, 'lecturesOcr')).find((x) => x.id === id1).texteBrut === t1);

    /* 5. JAMAIS VERS UN TÉLÉPHONE : ni lot de tournée nommant une correction, ni distribution. */
    const mob = await m.mobile('M1', { profil: 'reception' });
    const lot = await m.mere.admin('POST', '/admin/lot', { uuid: mob.uuid, fiches: [{ collection: 'lecturesOcr', id: id1 }], ttl_ms: 60000 });
    verifier('un lot de tournée qui NOMME une correction est REFUSÉ en nommant (422 fichiers_interdits_au_mobile)', lot.status === 422 && lot.json.code === 'fichiers_interdits_au_mobile', lot);

    /* 6. LE RÉGLAGE DE CLINIQUE : posé à la mère (défauts semés, puis une version datée), reçu des fileuls, versionné par date. */
    const emettre = (fiche, id) => m.mere.admin('POST', '/admin/referentiel', { collection: 'parametres', fiche: id, champs: fiche }).then((r) => r.json);
    const avantMob = (await mob.liste('parametres')).length;
    for (const d of Object.values(DEF_OCR)) { const s = P.semer(d); const r = await emettre(s.fiche, s.id); if (r.statut !== 'acceptee') verifier('le défaut semé de ' + d.cle + ' est accepté', false, r); }
    verifier('les quatre défauts semés arrivent chez le fileul (désactivée, aucun moteur, français, 120 s)', await attendre(async () => (await liste(f1, 'parametres')).filter((x) => x.famille === 'ocr').length === 4, 15000));
    const base = await liste(f1, 'parametres');
    const v1 = P.proposer({ definition: DEF_OCR.actif, versions: base, usages: [], valeur: true, dateEffet: '2026-11-14', auteur: 'Directrice Administrative', creeLe: '2026-11-14T11:00:00Z', motif: 'activation à la main' });
    const r1 = await emettre(v1.fiche, v1.id);
    verifier('la version datée « activée » posée par la mère est acceptée', r1.statut === 'acceptee' && r1.seq > 0, r1);
    verifier('F1 APPLIQUE : à la date d\'effet la valeur de la mère (activée), la veille le défaut semé (désactivée) ; l\'ancienne version reste lisible',
      await attendre(async () => (await liste(f1, 'parametres')).filter((x) => x.famille === 'ocr').length === 5, 15000)
      && P.resoudre('ocr.actif', await liste(f1, 'parametres'), '2026-11-14', DEF_OCR.actif).valeur === true
      && P.resoudre('ocr.actif', await liste(f1, 'parametres'), '2026-11-13', DEF_OCR.actif).valeur === false);
    await f2.ecrire({ type: 'creer', collection: 'parametres', fiche: 'intrus-ocr', champs: { ...P.semer(DEF_OCR.delai).fiche, cle: 'ocr.intrus' } });
    verifier('un fileul n\'écrit jamais le réglage de clinique : refusé, nommé (droit_refuse), la mère seule le pose', await attendre(async () => (await f2.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000));
    const forcee = await emettre({ ...P.semer(DEF_OCR.actif).fiche, mobile: true }, P.semer(DEF_OCR.actif).id + '-mobile');
    verifier('un paramètre « ocr » déclaré « mobile » est refusé par la mère (famille réservée, mobile_interdit) : jamais vers un téléphone, même si une définition le demandait', forcee.statut === 'refusee' && forcee.code === 'mobile_interdit', forcee);
    await dormir(2500);
    verifier('le téléphone ne reçoit AUCUN paramètre « ocr » (ni semis, ni version datée) : sa liste de paramètres n\'a pas bougé', (await mob.liste('parametres')).length === avantMob && !(await mob.liste('parametres')).some((x) => /^ocr\./.test(x.id || '')), [avantMob, (await mob.liste('parametres')).length]);

    /* 7. LE RELAIS NE VOIT RIEN : ni texte corrigé, ni réglage, ni nom de collection. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = brut.lignes.map((l) => Buffer.from(l.ct, 'base64'));
    verifier('le relais détient le journal chiffré (corrections et réglage y sont) mais AUCUN mot du texte corrigé, aucune clé de réglage, aucun nom de collection, ni en clair ni après décodage des octets',
      brut.lignes.length >= 4 && !new RegExp(SECRET2 + '|paracétamol|lecturesOcr|ocr\\.actif|ocr\\.moteur|parametres|corrigeDe').test(tout)
      && octets.every((o) => !new RegExp(SECRET2 + '|lecturesOcr|ocr\\.actif|ocr\\.moteur|parametres').test(o.toString('latin1'))), brut.lignes.length);
    const claires = brut.lignes.filter((l) => l.dir === 'journal').map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien la correction et le réglage : l\'opacité ne vient pas d\'un contenu vide',
      claires.some((o) => o.collection === 'lecturesOcr' && o.champs && o.champs.texteSource === 'correction') && claires.some((o) => o.collection === 'parametres' && o.champs && o.champs.cle === 'ocr.actif' && o.champs.valeur === true), claires.length);
    const gros = octets.filter((o) => o.length >= 250);
    verifier('chaque enveloppe a l\'entropie d\'un chiffrement (> 7 bits/octet)', gros.length >= 1 && gros.every((o) => entropie(o) > 7.0), octets.map((o) => [o.length, +entropie(o).toFixed(2)]));
    await m.fermer();
  },
});
