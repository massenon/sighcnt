'use strict';
/* Scénarios SAUVHS (lot 5, ADR-0007) : la SAUVEGARDE HORS SITE par blocs opaques. Le relais de référence (`relais.js`) ET le relais Laravel (`SIGH_RELAIS=laravel`) rejouent les mêmes scénarios.

   Ce que ce banc éprouve : le PROTOCOLE (client de référence `sauvegarde-hs.js`, règles `sauvegarde-regles.js`, relais `/sauvegarde/*`). Le code Dart (`sync_dart/lib/src/sauvegarde_horssite.dart`, la mère,
   le poste) est éprouvé par `packages/sync_dart/test/sauvegarde_horssite_test.dart` (contre ce même relais de référence) et par les tests du poste ; les règles pures par `packages/domaine/test/sauvegarde_horssite_test.dart`.

     1. SAUVHS1 : dépôt, dédoublonnage, rejeu idempotent, deux types indépendants, la clé ne part jamais, le relais ne voit RIEN (entropie, signatures, mots), un téléphone est refusé (403 nommé) ;
     2. SAUVHS2 : dépôt coupé au milieu puis repris (mère TUÉE, réseau coupé, relais redémarré), aucun bloc en double, aucune copie en double ;
     3. SAUVHS3 : limites et quota (refus nommés avec geste), rotation (archive, plancher, plafond), purge à la demande de l'espace sans toucher une copie courante, rien d'actuel détruit ;
     4. SAUVHS4 : restauration complète vers une base et un dossier NEUFS octet par octet, bloc altéré nommé, rien restauré à moitié, mauvaise clé, cible existante, copie purgée. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { fork } = require('node:child_process');
const { DestRelais, ErreurSauvegarde, sauvegarder, restaurer, sha } = require('./sauvegarde-hs');

const FIX = path.join(__dirname, '..', '..', '..', 'apps', 'poste', 'test', 'fixtures', 'fichiers');
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };
const SECRET = 'Hyperglycemie-Secrete-SAUVHS';
const MO = 1024 * 1024;

/* Octets pseudo-aléatoires reproductibles : le même graine donne le même contenu (un contenu à entropie élevée, pour que « le chiffré est haut » ne soit pas trivial). */
function alea(graine, n) { const out = Buffer.alloc(n); let x = 0; for (let i = 0; i < n; i += 32) { crypto.createHash('sha256').update(graine + ':' + i).digest().copy(out, i, 0, Math.min(32, n - i)); x++; } void x; return out; }
/* Un « magasin » de démonstration : de l'entête SQLite, du texte lisible (le secret), puis du bruit. */
function faux(graine, n) { const t = Buffer.from(`SQLite format 3\0 ${SECRET} patient AKPO ${graine} `.repeat(4)); return Buffer.concat([t, alea(graine, n - t.length)]); }

module.exports = ({ monde, verifier, attendre, dormir, titre }) => {
  const ecrire = (f, b) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, b); return f; };
  const refusDe = async (p) => { try { await p; return null; } catch (e) { if (e instanceof ErreurSauvegarde) return e.refus; throw e; } };
  async function cadre(opts = {}) {
    const m = await monde({ relais: true });
    const cle = crypto.randomBytes(32);
    const dest = new DestRelais(`http://127.0.0.1:${m.relais.port}`, 'secret-mere');
    const corps = [];
    const enregistre = new DestRelais(dest.base, dest.secret); /* écoute : tout ce que le client envoie au relais, pour prouver que la clé ne part jamais */
    const appel = enregistre.appel.bind(enregistre);
    enregistre.appel = async (methode, chemin, c, octets) => { corps.push(Buffer.from(JSON.stringify({ methode, chemin, c })), octets || Buffer.alloc(0)); return appel(methode, chemin, c, octets); };
    const src = path.join(m.dir, 'src');
    const regler = (cle2, valeur) => m.relais.direct('POST', '/banc/sauvegarde/reglage', { cle: cle2, valeur });
    const etat = () => m.relais.direct('GET', '/sauvegarde/etat').then((r) => r.json);
    const tout = () => m.relais.direct('GET', '/banc/sauvegarde/tout').then((r) => r.json);
    const magasin = (graine, n = 3 * MO) => ecrire(path.join(src, 'magasin-' + graine + '.sqlite'), faux(graine, n));
    const copierDe = (fichier) => ({ ref: 'magasin', taille: fs.statSync(fichier).size, lire: () => fs.readFileSync(fichier) });
    const sauvMagasin = (fichier, o = {}) => sauvegarder(Object.assign({ dest: o.dest || enregistre, cle: o.cle || cle, type: 'magasin', elements: [copierDe(fichier)], tailleBloc: 512 * 1024, garder: 7 }, o));
    /* le dossier de fichiers numérisés de démonstration : trois vrais formats (jpg, png, pdf) et un gros pdf de bruit ; chaque fichier est nommé par son empreinte */
    const dossierFichiers = (nom, extra = 0) => {
      const d = path.join(src, nom); const liste = [];
      const poser = (octets, ext) => { const f = path.join(d, sha(octets) + '.' + ext); ecrire(f, octets); liste.push({ ref: path.basename(f), octets }); };
      poser(fs.readFileSync(path.join(FIX, 'scan.jpg')), 'jpg'); poser(fs.readFileSync(path.join(FIX, 'scan.png')), 'png'); poser(fs.readFileSync(path.join(FIX, 'courrier-texte.pdf')), 'pdf');
      poser(Buffer.concat([Buffer.from('%PDF-1.4\n' + SECRET + '\n'), alea('gros-pdf' + extra, 2 * MO + 12345)]), 'pdf');
      return { d, liste };
    };
    const elementsDossier = (d) => fs.readdirSync(d).sort().map((n) => ({ ref: n, taille: fs.statSync(path.join(d, n)).size, lire: () => fs.readFileSync(path.join(d, n)) }));
    const sauvFichiers = (d, o = {}) => sauvegarder(Object.assign({ dest: o.dest || enregistre, cle: o.cle || cle, type: 'fichiers', elements: elementsDossier(d), tailleBloc: 512 * 1024, garder: 14 }, o));
    const processus = (o) => new Promise((ok) => {
      const p = fork(path.join(__dirname, 'sauvegarde-proc.js'), [JSON.stringify(Object.assign({ relais: dest.base, secret: 'secret-mere', cle: cle.toString('hex') }, o))], { stdio: ['ignore', 'ignore', 'inherit', 'ipc'], execArgv: ['--no-warnings'] });
      const r = { p, fini: null };
      r.attente = new Promise((fin) => { p.on('message', (msg) => { r.fini = msg; }); p.on('exit', (code) => fin({ code, msg: r.fini })); });
      ok(r);
    });
    return { m, cle, dest, enregistre, corps, src, regler, etat, tout, magasin, copierDe, sauvMagasin, dossierFichiers, elementsDossier, sauvFichiers, processus, opts };
  }

  return {
    async SAUVHS1() {
      titre('SAUVEGARDE-SAUVHS1 · dépôt par blocs, dédoublonnage, rejeu idempotent, deux types indépendants, la clé ne part jamais, le relais ne voit rien, un téléphone est refusé');
      const c = await cadre();
      const { m } = c;
      const f1 = c.magasin('A');
      const e0 = await c.etat();
      verifier('le relais dit ses limites (bloc, copie, quota, rotation) et son espace avant tout dépôt', e0.limites.tailleBlocMax > 0 && e0.limites.quotaOctets > 0 && e0.limites.rotationPlancher >= 1 && e0.utilise === 0 && e0.copies.magasin.completes === 0, e0.limites);
      const r1 = await c.sauvMagasin(f1);
      const e1 = await c.etat();
      verifier('un dépôt du magasin : 6 blocs de 512 Kio plus le manifeste, une copie COMPLÈTE', r1.deposes >= 7 && r1.rejeu === false && e1.copies.magasin.completes === 1 && e1.nb_blocs === r1.deposes, [r1, e1.nb_blocs]);
      verifier('l\'autre type n\'est pas touché : aucune copie des fichiers', e1.copies.fichiers.completes === 0 && e1.copies.fichiers.derniere === null);
      const r2 = await c.sauvMagasin(f1);
      const e2 = await c.etat();
      verifier('le REJEU du même état est la même copie : aucun octet déposé, aucune copie en plus, aucun bloc en plus', r2.rejeu === true && r2.deposes === 0 && e2.copies.magasin.completes === 1 && e2.nb_blocs === e1.nb_blocs, [r2, e2.nb_blocs]);
      const modifie = Buffer.from(fs.readFileSync(f1)); modifie[modifie.length - 5] ^= 0xff; const f1b = ecrire(path.join(c.src, 'magasin-A2.sqlite'), modifie);
      const r3 = await c.sauvMagasin(f1b);
      verifier('un octet change dans le dernier bloc : seuls le bloc touché et le manifeste sont déposés (dédoublonnage), les 5 autres sont déjà là', r3.deposes <= 2 && r3.dejaLa >= 5, r3);
      /* un bloc déposé deux fois : le relais le reconnaît (rejeu), n'en garde qu'un */
      const bloc = (await c.tout()).blocs[0];
      const avant = (await c.etat()).nb_blocs;
      const octets = await c.dest.bloc(bloc.id);
      const rb = await c.dest.deposerBloc(bloc.id, octets);
      verifier('un bloc DUPLIQUÉ est reconnu (rejeu) et n\'est pas gardé deux fois', rb.rejeu === true && (await c.etat()).nb_blocs === avant, rb);
      const d = c.dossierFichiers('fichiers-A');
      const rf = await c.sauvFichiers(d.d);
      const e3 = await c.etat();
      verifier('le type « fichiers » est une copie à part (sa propre rotation, ses propres compteurs) : trois formats et un gros pdf', rf.rejeu === false && e3.copies.fichiers.completes === 1 && e3.copies.magasin.completes === 2, [rf.deposes, e3.copies]);
      /* la clé ne part jamais : ni en octets, ni en hexadécimal, ni en base64, dans AUCUNE requête du client */
      const tous = Buffer.concat(c.corps);
      verifier('la clé de la clinique n\'apparaît dans AUCUNE requête envoyée au relais (octets, hexadécimal, base64)', !tous.includes(c.cle) && !tous.includes(Buffer.from(c.cle.toString('hex'))) && !tous.includes(Buffer.from(c.cle.toString('base64'))) && tous.length > 3 * MO);
      /* le relais ne voit RIEN */
      const dossierRelais = path.join(m.dir, 'sauvegardes-relais', 'blocs');
      const fichiers = []; for (const a of fs.readdirSync(dossierRelais)) for (const n of fs.readdirSync(path.join(dossierRelais, a))) if (!n.endsWith('.tmp')) fichiers.push(fs.readFileSync(path.join(dossierRelais, a, n)));
      const gros = fichiers.filter((b) => b.length > 100 * 1024);
      const signatures = [Buffer.from('SQLite format 3'), Buffer.from('%PDF-'), Buffer.from([0xff, 0xd8, 0xff]), Buffer.from([0x89, 0x50, 0x4e, 0x47]), Buffer.from('RIFF')];
      verifier('les blocs du relais sont des chiffrés : entropie > 7,99 bits par octet sur chaque bloc de plus de 100 Kio', gros.length >= 6 && gros.every((b) => entropie(b) > 7.99), gros.map((b) => entropie(b).toFixed(4)).slice(0, 4));
      verifier('aucune signature de fichier (SQLite, PDF, JPEG, PNG, RIFF) au début ni ailleurs dans les blocs, aucun mot du texte (« Hyperglycemie », « AKPO », « patient »)',
        fichiers.every((b) => signatures.every((s) => !b.includes(s)) && !b.includes(Buffer.from('Hyperglycemie')) && !b.includes(Buffer.from('AKPO')) && !b.includes(Buffer.from('patient'))));
      const lignes = JSON.stringify(await c.tout());
      verifier('les tables du relais ne portent que des identifiants, des tailles, des dates, des compteurs : aucun nom de fichier, aucun mot du texte, aucune clé', !/\.(jpg|png|pdf|sqlite)|Hyperglycemie|AKPO|patient|magasin-A/.test(lignes) && !lignes.includes(c.cle.toString('hex')) && !lignes.includes(c.cle.toString('base64')));
      /* un téléphone (ou un fileul) appairé n'y voit RIEN */
      const code = 'code-tel-' + Math.random().toString(36).slice(2);
      await m.relais.direct('POST', '/mere/code', { hash: crypto.createHash('sha256').update(code).digest('hex') });
      const ap = await m.relais.brut('POST', '/appairage', { code, uuid: 'telephone-sauv' });
      const jeton = { Authorization: 'Bearer ' + ap.json.jeton };
      const avantTel = await c.etat();
      const refus = [
        await m.relais.brut('GET', '/sauvegarde/etat', undefined, jeton),
        await m.relais.brut('GET', '/sauvegarde/copies', undefined, jeton),
        await m.relais.brut('POST', '/sauvegarde/manquants', { ids: [] }, jeton),
        await m.relais.brut('POST', '/sauvegarde/copie', { id: 'a'.repeat(64), type: 'magasin', garder: 7 }, jeton),
        await fetch(c.dest.base + '/sauvegarde/bloc/' + 'b'.repeat(64), { method: 'PUT', headers: Object.assign({ 'Content-Type': 'application/octet-stream' }, jeton), body: Buffer.from('x') }).then(async (r) => ({ status: r.status, json: await r.json() })),
        await fetch(c.dest.base + '/sauvegarde/bloc/' + bloc.id, { headers: jeton }).then(async (r) => ({ status: r.status, json: await r.json() })),
      ];
      verifier('un téléphone appairé est REFUSÉ sur les six routes (403 sauvegarde_reservee_mere, avec le geste)', refus.every((r) => r.status === 403 && r.json.code === 'sauvegarde_reservee_mere' && /poste mère/.test(r.json.geste || '')), refus.map((r) => [r.status, r.json.code]));
      const sans = await m.relais.brut('GET', '/sauvegarde/etat');
      const apres = await c.etat();
      verifier('sans identité : 403 mere_requise ; aucun refus n\'a rien changé au relais', sans.status === 403 && sans.json.code === 'mere_requise' && apres.nb_blocs === avantTel.nb_blocs && apres.utilise === avantTel.utilise);
      await m.fermer();
    },

    async SAUVHS2() {
      titre('SAUVEGARDE-SAUVHS2 · dépôt coupé au milieu puis repris (mère tuée, réseau coupé, relais redémarré), aucun bloc ni copie en double');
      const c = await cadre();
      const { m } = c;
      const f = c.magasin('B', 3 * MO);
      const attendus = Math.ceil(fs.statSync(f).size / (128 * 1024));
      /* 1. la mère est TUÉE au milieu du dépôt (SIGKILL) */
      const p1 = await c.processus({ type: 'magasin', source: f, tailleBloc: 128 * 1024, garder: 7, lentMs: 40 });
      const milieu = await attendre(async () => (await c.etat()).nb_blocs >= 6, 20000);
      p1.p.kill('SIGKILL'); await p1.attente;
      const e1 = await c.etat();
      verifier('la mère tuée au milieu : des blocs sont au relais (orphelins), AUCUNE copie n\'est complète, rien n\'est compté comme sauvegarde', milieu && e1.nb_blocs >= 6 && e1.nb_blocs < attendus && e1.copies.magasin.completes === 0 && p1.fini === null, [e1.nb_blocs, attendus]);
      const deja = e1.nb_blocs;
      /* 2. la reprise n'envoie que ce qui manque */
      const p2 = await c.processus({ type: 'magasin', source: f, tailleBloc: 128 * 1024, garder: 7 });
      const fin2 = await p2.attente;
      const e2 = await c.etat();
      verifier('la REPRISE ne renvoie que les blocs manquants : les blocs déjà là ne sont pas redéposés, la copie devient complète', fin2.msg && fin2.msg.ok === true && fin2.msg.dejaLa >= deja && fin2.msg.deposes + fin2.msg.dejaLa >= attendus && e2.copies.magasin.completes === 1, [fin2.msg && fin2.msg.deposes, fin2.msg && fin2.msg.dejaLa]);
      const blocsApres = (await c.tout()).blocs;
      verifier('aucun bloc en double (identifiants distincts) et le nombre de blocs est celui d\'un dépôt sans coupure', new Set(blocsApres.map((b) => b.id)).size === blocsApres.length && blocsApres.length === e2.nb_blocs && e2.nb_blocs === attendus + 1, [blocsApres.length, attendus]);
      /* 3. le réseau est COUPÉ au milieu (commutateur), pour un autre état du magasin */
      const f2 = c.magasin('C', 3 * MO);
      const lent = await c.processus({ relais: `http://127.0.0.1:${m.portInternet}`, type: 'magasin', source: f2, tailleBloc: 128 * 1024, garder: 7, lentMs: 50 });
      await attendre(async () => (await c.etat()).nb_blocs >= e2.nb_blocs + 5, 20000);
      m.internet.regler('ferme');
      const fin3 = await lent.attente;
      m.internet.regler('ouvert');
      const e3 = await c.etat();
      verifier('réseau coupé au milieu : le dépôt échoue (sorti en erreur), rien n\'est compté, les blocs déposés restent', fin3.msg && fin3.msg.ok === false && e3.copies.magasin.completes === 1 && e3.nb_blocs > e2.nb_blocs, [fin3.msg && fin3.msg.refus && fin3.msg.refus.code, e3.nb_blocs]);
      const p3 = await c.processus({ relais: `http://127.0.0.1:${m.portInternet}`, type: 'magasin', source: f2, tailleBloc: 128 * 1024, garder: 7 });
      const fin4 = await p3.attente;
      verifier('réseau rétabli : la reprise aboutit sans redéposer les blocs déjà là', fin4.msg && fin4.msg.ok === true && fin4.msg.dejaLa >= 5 && (await c.etat()).copies.magasin.completes === 2, fin4.msg);
      /* 4. le RELAIS est tué et redémarré (ses blocs sont sur disque, ses lignes en base) */
      const f3 = c.magasin('D', 2 * MO);
      const coupe = await refusDe(c.sauvMagasin(f3, { tailleBloc: 128 * 1024, coupureApres: 6 }));
      const avantRelais = await c.etat();
      await m.relais.tuer(); await m.relais.demarrer();
      const apresRelais = await attendre(async () => { try { return await c.etat(); } catch (e) { return false; } }, 15000);
      verifier('dépôt COUPÉ par le banc après 6 blocs (refus nommé DEPOT_COUPE), puis le relais est tué et redémarré : ses blocs et ses copies sont intacts', coupe && coupe.code === 'DEPOT_COUPE' && apresRelais && apresRelais.nb_blocs === avantRelais.nb_blocs && apresRelais.copies.magasin.completes === 2, [coupe && coupe.code, apresRelais && apresRelais.nb_blocs, avantRelais.nb_blocs]);
      const fin5 = await c.sauvMagasin(f3, { tailleBloc: 128 * 1024 });
      verifier('relais restauré : la reprise termine la copie, les blocs d\'avant la panne ne sont pas redéposés', fin5.rejeu === false && fin5.dejaLa >= 6 && (await c.etat()).copies.magasin.completes === 3, fin5);
      await m.fermer();
    },

    async SAUVHS3() {
      titre('SAUVEGARDE-SAUVHS3 · limites et quota (refus nommés), rotation (archive, plancher, plafond), purge à la demande de l\'espace sans toucher une copie courante');
      const c = await cadre();
      const { m } = c;
      /* 1. limite par copie : refus avant tout dépôt, et refus du relais si on contourne le contrôle du client */
      const f = c.magasin('E', 3 * MO);
      await c.regler('tailleMaxCopie', 1 * MO);
      const avant0 = await c.etat();
      const refus1 = await refusDe(c.sauvMagasin(f));
      verifier('copie plus grosse que la limite par copie : refus nommé SAUVEGARDE_TROP_GROSSE avec le geste, AVANT tout dépôt', refus1 && refus1.code === 'SAUVEGARDE_TROP_GROSSE' && /limite par copie/.test(refus1.geste) && (await c.etat()).nb_blocs === avant0.nb_blocs, refus1 && refus1.code);
      await c.regler('tailleMaxCopie', 100 * MO);
      const dest = c.dest;
      const prep = await c.sauvMagasin(c.magasin('E2', 2 * MO), { tailleBloc: 512 * 1024 }); // une vraie copie complète sous les limites relevées
      const gros = alea('contournement', 600 * 1024); const idg = sha(gros);
      await c.regler('tailleBlocMax', 256 * 1024);
      const trop = await refusDe(dest.deposerBloc(idg, gros));
      verifier('un bloc plus gros que la taille maximale du relais : refus nommé BLOC_TROP_GROS (413) avec la limite', trop && trop.code === 'BLOC_TROP_GROS' && trop.statut === 413 && trop.limite === 256 * 1024, trop && trop.code);
      await c.regler('tailleBlocMax', 2 * MO);
      const alt = Buffer.from(gros); const idAlt = sha(alt); alt[3] ^= 1;
      const altere = await refusDe(dest.deposerBloc(idAlt, alt));
      verifier('un bloc altéré en route (octets différents de l\'empreinte annoncée) : refus nommé BLOC_ALTERE_EN_ROUTE (422), rien de stocké', altere && altere.code === 'BLOC_ALTERE_EN_ROUTE' && (await dest.manquants([idAlt])).length === 1, altere && altere.code);
      await c.regler('tailleMaxCopie', 300 * 1024);
      const idCopie = 'c'.repeat(64);
      await dest.ouvrir(idCopie, 'magasin', Date.now(), 7);
      const tousBlocs = (await c.tout()).blocs.slice(0, 4).map((b) => b.id);
      const trop2 = await refusDe(dest.attacher(idCopie, tousBlocs));
      verifier('rattacher plus d\'octets que la limite par copie : refus nommé SAUVEGARDE_TROP_GROSSE (413) du relais lui-même', trop2 && trop2.code === 'SAUVEGARDE_TROP_GROSSE' && trop2.statut === 413, trop2 && trop2.code);
      await c.regler('tailleMaxCopie', 1024 * MO);
      /* 2. rotation : garder 2, quatre copies distinctes de plus */
      const copies = [];
      for (const g of ['F', 'G', 'H', 'I']) { await sleepDate(); copies.push((await c.sauvMagasin(c.magasin(g, 1 * MO), { garder: 2 })).copie); }
      async function sleepDate() { await dormir(15); }
      const liste = await dest.copies('magasin');
      const parEtat = (e) => liste.filter((x) => x.etat === e).length;
      verifier('rotation : garder 2 copies, les plus anciennes sont ARCHIVÉES (jamais supprimées) ; les deux plus récentes restent courantes', parEtat('complete') === 2 && parEtat('archivee') >= 3 && liste.filter((x) => x.etat === 'complete').every((x) => [copies[2], copies[3]].includes(x.id)), liste.map((x) => x.etat));
      const hors = await refusDe(dest.ouvrir('d'.repeat(64), 'magasin', Date.now(), 1));
      const hors2 = await refusDe(dest.ouvrir('d'.repeat(64), 'magasin', Date.now(), 99));
      verifier('garder 1 copie (sous le plancher du relais) ou 99 (au-dessus du plafond) : refus nommé ROTATION_HORS_BORNES avec les bornes', hors && hors.code === 'ROTATION_HORS_BORNES' && hors.plancher === 2 && hors2 && hors2.code === 'ROTATION_HORS_BORNES' && hors2.plafond === 60, [hors && hors.code, hors2 && hors2.code]);
      const archivee = liste.find((x) => x.etat === 'archivee');
      const lue = await dest.copie(archivee.id);
      verifier('une copie ARCHIVÉE reste lisible (restaurable) : sa racine est servie', lue.etat === 'archivee' && lue.racine.length >= 1);
      /* 3. purge à la demande de l'espace : la plus ancienne archivée d'abord, jamais une copie courante */
      const e1 = await c.etat();
      await c.regler('quotaOctets', e1.utilise + 200 * 1024);
      const nouveau = c.magasin('J', 1 * MO); // 2 blocs de 512 Kio distincts : il faudra libérer
      const avantPurge = (await dest.copies('magasin')).filter((x) => x.etat === 'archivee').map((x) => x.id);
      const r = await c.sauvMagasin(nouveau, { garder: 2 });
      const liste2 = await dest.copies('magasin');
      const purgees = liste2.filter((x) => x.etat === 'purgee');
      verifier('l\'espace manque : les copies archivées sont PURGÉES la plus ancienne d\'abord, la copie demandée est validée', r.rejeu === false && purgees.length >= 1 && purgees.every((x) => avantPurge.includes(x.id)) && purgees.every((x) => x.motif && /purgée/.test(x.motif)), purgees.map((x) => x.id.slice(0, 6)));
      const courantes = liste2.filter((x) => x.etat === 'complete');
      verifier('aucune des 2 copies courantes n\'a été touchée (la copie purgée garde sa ligne : RG-14)', courantes.length === 2 && courantes.some((x) => x.id === r.copie) && liste2.length === liste.length + 1);
      const gone = await refusDe(dest.copie(purgees[0].id));
      verifier('une copie purgée n\'est plus restaurable et le relais le DIT : 410 COPIE_PURGEE', gone && gone.code === 'COPIE_PURGEE' && gone.statut === 410, gone && gone.code);
      /* 4. un dépôt direct qui dépasse le quota fait d'abord libérer l'archive, jamais une copie courante */
      const e2 = await c.etat();
      await c.regler('quotaOctets', e2.utilise);
      const bloc300 = alea('direct', 300 * 1024);
      const ok300 = await dest.deposerBloc(sha(bloc300), bloc300);
      const liste3 = await dest.copies('magasin');
      verifier('quota atteint : un dépôt direct fait d\'abord PURGER une copie archivée (la plus ancienne) ; les 2 copies courantes sont intactes', ok300.taille === bloc300.length && liste3.filter((x) => x.etat === 'purgee').length > purgees.length && liste3.filter((x) => x.etat === 'complete').length === 2);
      /* 5. pression extrême (quota réduit de moitié) : toute l'archive est libérée, puis refus nommé ; les copies courantes sont INTACTES */
      const e3 = await c.etat();
      await c.regler('quotaOctets', Math.floor(e3.utilise / 2));
      const refus3 = await refusDe(c.sauvMagasin(c.magasin('K', 1 * MO), { garder: 2 }));
      const direct = await refusDe(dest.deposerBloc(sha(alea('direct2', 300 * 1024)), alea('direct2', 300 * 1024)));
      const apres = await dest.copies('magasin');
      verifier('quota insuffisant même après avoir tout libéré : refus nommé ESPACE_RELAIS_INSUFFISANT avec le geste (client), 507 du relais lui-même ; toute l\'archive est purgée, les 2 copies courantes SONT INTACTES',
        refus3 && refus3.code === 'ESPACE_RELAIS_INSUFFISANT' && /quota|dossier distant/.test(refus3.geste) && direct && direct.code === 'ESPACE_RELAIS_INSUFFISANT' && direct.statut === 507
        && apres.filter((x) => x.etat === 'complete').length === 2 && apres.filter((x) => x.etat === 'archivee').length === 0, [refus3 && refus3.code, direct && direct.code, apres.map((x) => x.etat).join()]);
      const pleine = await dest.copie(courantes.find((x) => x.id !== r.copie).id);
      verifier('la copie courante qui n\'est pas la dernière reste lisible après les refus (rien d\'actuel détruit)', pleine.etat === 'complete' && pleine.racine.length >= 1);
      /* 6. les blocs orphelins vieillis sont libérables */
      await c.regler('quotaOctets', 5 * 1024 * MO);
      const stray = alea('orphelin', 300 * 1024); await dest.deposerBloc(sha(stray), stray);
      const l0 = (await c.etat()).liberable;
      await m.relais.direct('POST', '/banc/sauvegarde/vieillir', { heures: 100 });
      const l1 = (await c.etat()).liberable;
      verifier('un bloc orphelin (jamais rattaché) devient libérable après le délai des orphelins, pas avant', l1 >= l0 + 300 * 1024);
      await m.fermer();
    },

    async SAUVHS4() {
      titre('SAUVEGARDE-SAUVHS4 · restauration complète vers une base et un dossier neufs octet par octet, bloc altéré nommé, rien restauré à moitié, mauvaise clé, cible existante');
      const c = await cadre();
      const { m } = c;
      const f = c.magasin('R', 3 * MO);
      const d = c.dossierFichiers('fichiers-R', 7);
      const rm = await c.sauvMagasin(f);
      const rf = await c.sauvFichiers(d.d);
      const cible = path.join(m.dir, 'restauration');
      const cm = path.join(cible, 'base'); const cf = path.join(cible, 'fichiers');
      fs.mkdirSync(cible, { recursive: true });
      const a = await restaurer({ dest: c.dest, cle: c.cle, copieId: rm.copie, cible: cm });
      const b = await restaurer({ dest: c.dest, cle: c.cle, copieId: rf.copie, cible: cf });
      const original = sha(fs.readFileSync(f));
      verifier('restauration du MAGASIN vers une cible neuve : le fichier restauré a le même SHA-256, octet par octet', a.elements === 1 && sha(fs.readFileSync(path.join(cm, 'magasin'))) === original && fs.statSync(path.join(cm, 'magasin')).size === fs.statSync(f).size, a);
      verifier('restauration des FICHIERS vers un dossier neuf : les quatre fichiers (jpg, png, pdf, gros pdf) ont le même SHA-256 que les originaux, aucun de plus', b.elements === 4 && fs.readdirSync(cf).length === 4 && d.liste.every((x) => sha(fs.readFileSync(path.join(cf, x.ref))) === sha(x.octets)), b);
      verifier('la restauration ne laisse aucun dossier de travail et ne touche pas la source', fs.readdirSync(cible).sort().join() === 'base,fichiers' && sha(fs.readFileSync(f)) === original);
      /* cible existante, mauvaise clé */
      const ex = await refusDe(restaurer({ dest: c.dest, cle: c.cle, copieId: rm.copie, cible: cm }));
      verifier('une cible qui existe déjà est REFUSÉE (CIBLE_EXISTE) : la restauration ne remplace jamais', ex && ex.code === 'CIBLE_EXISTE' && /NEUF/.test(ex.geste), ex && ex.code);
      const mauvaise = await refusDe(restaurer({ dest: c.dest, cle: crypto.randomBytes(32), copieId: rm.copie, cible: path.join(cible, 'mauvaise-cle') }));
      verifier('une mauvaise clé : refus nommé CLE_INCORRECTE (le bloc est intact mais ne s\'ouvre pas), rien n\'est écrit', mauvaise && mauvaise.code === 'CLE_INCORRECTE' && mauvaise.bloc && !fs.existsSync(path.join(cible, 'mauvaise-cle')) && fs.readdirSync(cible).every((n) => !/reprise/.test(n)), mauvaise && mauvaise.code);
      /* un bloc altéré AU RELAIS (disque du relais) : refusé et NOMMÉ, rien n'est restauré */
      const copie = await c.dest.copie(rm.copie);
      const blocsMere = (await c.tout()).blocs.map((x) => x.id).filter((x) => !copie.racine.includes(x));
      const victime = blocsMere[2];
      await m.relais.direct('POST', '/banc/sauvegarde/alterer', { id: victime });
      const al = await refusDe(restaurer({ dest: c.dest, cle: c.cle, copieId: rm.copie, cible: path.join(cible, 'altere') }));
      verifier('un bloc altéré sur le disque du relais : refus nommé BLOC_ALTERE avec l\'identifiant du bloc, RIEN n\'est restauré à moitié (ni cible, ni dossier de travail)', al && al.code === 'BLOC_ALTERE' && al.bloc === victime && !fs.existsSync(path.join(cible, 'altere')) && fs.readdirSync(cible).every((n) => !/reprise/.test(n)), al && [al.code, al.bloc]);
      /* un relais qui MENT (rend d'autres octets) : l'empreinte est vérifiée par le client lui-même */
      class Menteur extends DestRelais { async bloc(id) { const o = Buffer.from(await super.bloc(id)); o[o.length - 1] ^= 1; return o; } }
      const mensonge = await refusDe(restaurer({ dest: new Menteur(c.dest.base, c.dest.secret), cle: c.cle, copieId: rf.copie, cible: path.join(cible, 'menteur') }));
      verifier('un relais qui rend d\'autres octets que ceux déposés : le client revérifie l\'empreinte de CHAQUE bloc (BLOC_ALTERE nommé), rien n\'est écrit', mensonge && mensonge.code === 'BLOC_ALTERE' && !fs.existsSync(path.join(cible, 'menteur')), mensonge && mensonge.code);
      /* un bloc manquant */
      class Trou extends DestRelais { async bloc(id) { if (id === victime) throw new ErreurSauvegarde({ code: 'BLOC_ABSENT', motif: 'absent' }); return super.bloc(id); } }
      const trou = await refusDe(restaurer({ dest: new Trou(c.dest.base, c.dest.secret), cle: c.cle, copieId: rm.copie, cible: path.join(cible, 'trou') }));
      verifier('un bloc manquant : refus nommé BLOC_MANQUANT avec l\'identifiant, rien n\'est écrit', trou && trou.code === 'BLOC_MANQUANT' && trou.bloc === victime && !fs.existsSync(path.join(cible, 'trou')), trou && trou.code);
      await m.fermer();
    },
  };
};
