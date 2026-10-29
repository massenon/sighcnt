'use strict';
/* =============================================================================
 * SIGH-CNT — LE BANC DE SYNCHRONISATION À PLUSIEURS PROCESSUS
 * -----------------------------------------------------------------------------
 * Une mère et des fileuls sont de VRAIS processus (fork), chacun avec sa base.
 * Un commutateur TCP coupe le réseau en cours de route ; la mère et les postes
 * sont tués sans préavis (SIGKILL) puis relancés sur leurs bases. Les scénarios
 * suivent docs/specs/SPEC-protocole-synchronisation.md §16 (SYNC-R1…R17).
 *
 * CE QUE CE BANC PROUVE : que le PROTOCOLE tient (idempotence, curseurs, conflits
 * nommés, bail de stock, époque, révocation, file persistée).
 * CE QU'IL NE PROUVE PAS : Dart, SQLCipher, le service Windows/Linux, PostgreSQL,
 * le relais en ligne et le chiffrement de bout en bout — voir README.md.
 *
 *   node --no-warnings banc/run.js            tous les scénarios
 *   node --no-warnings banc/run.js R4 R7      seulement ceux-là
 * ========================================================================== */
const { fork } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const net = require('node:net');
const path = require('node:path');
const { Commutateur } = require('./proxy');

const ADMIN = 'admin-banc';
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
async function attendre(cond, ms = 10000) {
  const t0 = Date.now();
  for (;;) {
    try { const v = await cond(); if (v) return v; } catch (e) { /* on réessaie */ }
    if (Date.now() - t0 > ms) return false;
    await dormir(60);
  }
}
function portLibre() { return new Promise((ok) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); }); }); }
async function appel(base, methode, chemin, corps, entetes) {
  const r = await fetch(base + chemin, { method: methode, headers: Object.assign({ 'Content-Type': 'application/json' }, entetes || {}), body: corps ? JSON.stringify(corps) : undefined });
  let j = {}; try { j = await r.json(); } catch (e) { /* vide */ }
  return { status: r.status, json: j };
}

const ouverts = [];
/* --- le monde d'un scénario ------------------------------------------------------ */
async function monde(opts = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sigh-banc-'));
  const m = { dir, fileuls: {}, nbFileuls: 0 };
  ouverts.push(m);
  const portMere = await portLibre();
  const lancer = (script, args) => new Promise((ok, ko) => {
    const p = fork(path.join(__dirname, script), args, { stdio: ['ignore', 'ignore', 'inherit', 'ipc'], execArgv: ['--no-warnings'] });
    p.once('message', () => ok(p)); p.once('error', ko);
  });
  m.mere = {
    port: portMere, proc: null,
    async demarrer() {
      m.mere.proc = await lancer('mere.js', [`--port=${portMere}`, `--db=${path.join(dir, 'mere.sqlite')}`, `--admin=${ADMIN}`,
        `--code-ttl=${opts.codeTtl || 900000}`, `--jeton-ttl=${opts.jetonTtl || 86400000}`]);
    },
    tuer() { if (m.mere.proc) { m.mere.proc.kill('SIGKILL'); m.mere.proc = null; } return dormir(80); },
    admin: (methode, chemin, corps) => appel(`http://127.0.0.1:${portMere}`, methode, chemin, corps, { 'x-admin': ADMIN }),
    direct: (methode, chemin, corps, entetes) => appel(`http://127.0.0.1:${portMere}`, methode, chemin, corps, entetes),
  };
  await m.mere.demarrer();
  m.reseau = new Commutateur(portMere);
  m.portReseau = await m.reseau.demarrer();

  m.fileul = async (nom, o = {}) => {
    const port = await portLibre();
    const fil = {
      nom, port, proc: null, base: `http://127.0.0.1:${port}`,
      async demarrer() {
        fil.proc = await lancer('fileul.js', [`--port=${port}`, `--mere=http://127.0.0.1:${m.portReseau}`, `--db=${path.join(dir, nom + '.sqlite')}`,
          `--nom=${nom}`, `--horloge-decalage-ms=${o.decalage || 0}`]);
      },
      tuer() { if (fil.proc) { fil.proc.kill('SIGKILL'); fil.proc = null; } return dormir(80); },
      get: (chemin) => appel(fil.base, 'GET', chemin).then((r) => r.json),
      post: (chemin, corps) => appel(fil.base, 'POST', chemin, corps),
      etat: () => fil.get('/etat'),
      vue: (collection, id) => fil.get(`/vue?collection=${collection}&id=${encodeURIComponent(id)}`),
      liste: (collection) => fil.get(`/liste?collection=${collection}`),
      ecrire: (cmd) => fil.post('/ecrire', cmd).then((r) => r.json),
      vide: async () => (await fil.etat()).en_attente === 0,
    };
    await fil.demarrer();
    if (!o.sansAppairage) {
      const { json: c } = await m.mere.admin('POST', '/admin/code', { etiquette: nom, role: 'fileul' });
      const r = await fil.post('/appairer', { code: c.code });
      if (r.status !== 200) throw new Error('appairage refusé : ' + JSON.stringify(r.json));
      fil.uuid = r.json.uuid;
      if (o.plage !== 0) await fil.post('/plage', { taille: o.plage || 50 });
      await attendre(async () => (await fil.etat()).cycles > 1 && !(await fil.etat()).hors_ligne);
    }
    m.fileuls[nom] = fil; m.nbFileuls++;
    return fil;
  };
  m.fermer = async () => {
    for (const f of Object.values(m.fileuls)) if (f.proc) f.proc.kill('SIGKILL');
    if (m.mere.proc) m.mere.proc.kill('SIGKILL');
    m.reseau.arreter(); await dormir(100);
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { /* tant pis */ }
  };
  return m;
}

/* --- verdicts ------------------------------------------------------------------------- */
const verdicts = [];
let courant = '';
function verifier(libelle, ok, detail) {
  verdicts.push({ scenario: courant, libelle, ok: !!ok, detail });
  console.log(`   ${ok ? '✓' : '✗'} ${libelle}${!ok && detail !== undefined ? '  → ' + JSON.stringify(detail) : ''}`);
}
const codes = (liste) => liste.map((p) => p.data.code).sort();

/* --- les scénarios -------------------------------------------------------------------------- */
const scenarios = {
  async R1() {
    courant = 'SYNC-R1 · mère arrêtée, deux fileuls créent un dossier chacun';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    await m.mere.tuer();
    await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Alpha' } });
    await f2.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Bêta' } });
    verifier('hors ligne, chaque poste voit SON dossier tout de suite', (await f1.liste('patients')).length === 1 && (await f2.liste('patients')).length === 1);
    verifier('le poste se déclare hors ligne', await attendre(async () => (await f1.etat()).hors_ligne));
    await m.mere.demarrer();
    verifier('au retour de la mère, les files se vident seules', await attendre(async () => (await f1.vide()) && (await f2.vide()), 15000));
    await attendre(async () => (await f1.liste('patients')).length === 2 && (await f2.liste('patients')).length === 2, 10000);
    const a = await f1.liste('patients'); const b = await f2.liste('patients');
    verifier('chaque poste voit les DEUX dossiers', a.length === 2 && b.length === 2, [a.length, b.length]);
    verifier('deux codes distincts, aucun doublon (RG-01)', new Set(codes(a)).size === 2 && codes(a).every((c) => /^CNT\/\d+\/26$/.test(c)), codes(a));
    verifier('les deux postes tiennent les mêmes codes', JSON.stringify(codes(a)) === JSON.stringify(codes(b)));
    verifier('la mère n\'en a que deux', (await m.mere.admin('GET', '/admin/compte?collection=patients')).json.n === 2);
    await m.fermer();
  },
  async R1b() {
    courant = 'SYNC-R1b · plage épuisée : numéro provisoire, réconcilié sans doublon';
    const m = await monde(); const f1 = await m.fileul('F1', { plage: 1 });
    await m.mere.tuer();
    await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Premier' } });
    const second = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Second' } });
    verifier('le second dossier reçoit un numéro PROVISOIRE', (await f1.vue('patients', second.fiche)).data.code.startsWith('PROV-'));
    await m.mere.demarrer();
    await attendre(async () => (await f1.vide()) && (await f1.liste('patients')).length === 2 && codes(await f1.liste('patients')).every((c) => c.startsWith('CNT/')), 15000);
    const l = await f1.liste('patients');
    verifier('plus aucun numéro provisoire après réconciliation', l.length === 2 && l.every((p) => /^CNT\/\d+\/26$/.test(p.data.code)), codes(l));
    verifier('les deux numéros sont distincts', new Set(codes(l)).size === 2);
    await m.fermer();
  },
  async R2() {
    courant = 'SYNC-R2 · la réponse se perd APRÈS traitement : le rejeu ne crée aucun doublon';
    const m = await monde(); const f1 = await m.fileul('F1');
    m.reseau.regler('perd_reponse');
    for (let i = 0; i < 3; i++) await f1.ecrire({ type: 'creer', collection: 'constantes', champs: { pouls: 70 + i } });
    verifier('la mère TRAITE le lot dont la réponse est perdue', await attendre(async () => (await m.mere.admin('GET', '/admin/etat')).json.nb_operations === 3));
    verifier('le poste, lui, ne le sait pas : 3 opérations restent en attente', (await f1.etat()).en_attente === 3);
    m.reseau.regler('ouvert');
    verifier('le rejeu aboutit', await attendre(async () => f1.vide(), 15000));
    verifier('toujours 3 opérations à la mère : aucun doublon', (await m.mere.admin('GET', '/admin/etat')).json.nb_operations === 3);
    verifier('le rejeu est reconnu comme tel', (await f1.etat()).resultats.some((r) => r.rejeu));
    await m.fermer();
  },
  async R3() {
    courant = 'SYNC-R3 · dernier lot sorti deux fois (sans bail) : refus nommé, jamais de stock négatif';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    await m.mere.admin('POST', '/admin/stock', { article: 'GANTS', qte: 10 });
    await attendre(async () => (await f1.vue('stock', 'GANTS')).data.qte === 10);
    m.reseau.regler('ferme');
    await f1.ecrire({ type: 'sortie', collection: 'stock', fiche: 'GANTS', champs: { qte: 6 } });
    await f2.ecrire({ type: 'sortie', collection: 'stock', fiche: 'GANTS', champs: { qte: 6 } });
    m.reseau.regler('ouvert');
    await attendre(async () => (await f1.vide()) && (await f2.vide()), 15000);
    const refus = [...(await f1.etat()).a_traiter, ...(await f2.etat()).a_traiter];
    verifier('un seul des deux gestes est refusé', refus.length === 1, refus.length);
    verifier('le refus NOMME l\'article et la règle', refus[0] && refus[0].code === 'invariant_viole' && /GANTS/.test(refus[0].motif) && /RG-03/.test(refus[0].motif), refus[0]);
    const stock = (await m.mere.admin('GET', '/admin/fiche?collection=stock&id=GANTS')).json.data.qte;
    verifier('stock final = 4, jamais négatif', stock === 4, stock);
    await m.fermer();
  },
  async R3b() {
    courant = 'SYNC-R3b · dernier lot avec BAIL : aucun conflit, aucun stock négatif';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    await m.mere.admin('POST', '/admin/stock', { article: 'GANTS', qte: 10 });
    await attendre(async () => (await f1.vue('stock', 'GANTS')).data.qte === 10);
    const b1 = (await f1.post('/bail', { article: 'GANTS', qte: 6 })).json; const b2 = (await f2.post('/bail', { article: 'GANTS', qte: 6 })).json;
    verifier('bail accordé sans dépasser le disponible (6 puis 4)', b1.accorde === 6 && b2.accorde === 4, [b1, b2]);
    m.reseau.regler('ferme');
    const ok1 = await f1.ecrire({ type: 'sortie', collection: 'stock', fiche: 'GANTS', champs: { qte: 6 }, bail: true });
    const ok2 = await f2.ecrire({ type: 'sortie', collection: 'stock', fiche: 'GANTS', champs: { qte: 4 }, bail: true });
    const trop = await f1.ecrire({ type: 'sortie', collection: 'stock', fiche: 'GANTS', champs: { qte: 1 }, bail: true });
    verifier('hors ligne, la sortie dans le bail est acceptée localement', !!ok1.id && !!ok2.id);
    verifier('hors ligne, la sortie qui dépasse le bail est refusée LOCALEMENT', trop.refus === 'bail_insuffisant', trop);
    m.reseau.regler('ouvert');
    await attendre(async () => (await f1.vide()) && (await f2.vide()), 15000);
    verifier('aucun refus, aucun conflit', (await f1.etat()).a_traiter.length + (await f2.etat()).a_traiter.length === 0);
    verifier('stock final = 0', (await m.mere.admin('GET', '/admin/fiche?collection=stock&id=GANTS')).json.data.qte === 0);
    await m.fermer();
  },
  async R4() {
    courant = 'SYNC-R4 · même champ modifié sur deux postes : conflit nommé, décision synchronisée';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const p = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Dossou', telephone: '111' } });
    await attendre(async () => (await f2.vue('patients', p.fiche)).data.telephone === '111');
    m.reseau.regler('ferme');
    await f1.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { telephone: '222' } });
    await f2.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { telephone: '333' } });
    m.reseau.regler('ouvert');
    await attendre(async () => (await f1.vide()) && (await f2.vide()), 15000);
    const cs = (await m.mere.admin('GET', '/admin/conflits')).json;
    verifier('exactement un conflit ouvert, avec les deux versions', cs.length === 1 && cs[0].etat === 'ouvert' && cs[0].champ === 'telephone' && cs[0].a && cs[0].b, cs);
    const fus = [...(await f1.etat()).fusionnees, ...(await f2.etat()).fusionnees];
    verifier('un des postes est informé : « fusionnée avec conflit »', fus.length === 1 && fus[0].conflits.length === 1, fus);
    const c = cs[0];
    await m.mere.admin('POST', '/admin/trancher', { id: c.id, decision: 'b' });
    const voulu = JSON.parse(c.b);
    verifier('après décision, les DEUX postes convergent sur la valeur tranchée',
      await attendre(async () => (await f1.vue('patients', p.fiche)).data.telephone === voulu && (await f2.vue('patients', p.fiche)).data.telephone === voulu), [voulu]);
    verifier('plus aucun conflit ouvert', (await m.mere.admin('GET', '/admin/etat')).json.conflits_ouverts === 0);
    verifier('un conflit déjà tranché ne se tranche pas deux fois', (await m.mere.admin('POST', '/admin/trancher', { id: c.id, decision: 'a' })).status === 422);
    await m.fermer();
  },
  async R5() {
    courant = 'SYNC-R5 · champs DIFFÉRENTS de la même fiche : les deux modifications sont conservées';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const p = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Gbèdji', telephone: '111', quartier: 'Nord' } });
    await attendre(async () => (await f2.vue('patients', p.fiche)).existe);
    m.reseau.regler('ferme');
    await f1.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { telephone: '222' } });
    await f2.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { quartier: 'Sud' } });
    m.reseau.regler('ouvert');
    await attendre(async () => (await f1.vide()) && (await f2.vide()), 15000);
    const ok = await attendre(async () => { const a = (await f1.vue('patients', p.fiche)).data; const b = (await f2.vue('patients', p.fiche)).data; return a.telephone === '222' && a.quartier === 'Sud' && b.telephone === '222' && b.quartier === 'Sud'; });
    verifier('téléphone ET quartier modifiés sont présents sur les deux postes', ok);
    verifier('aucun conflit', (await m.mere.admin('GET', '/admin/etat')).json.conflits_ouverts === 0);
    await m.fermer();
  },
  async R7() {
    courant = 'SYNC-R7 · poste révoqué pendant qu\'il travaille hors ligne';
    const m = await monde(); const f1 = await m.fileul('F1');
    m.reseau.regler('ferme');
    await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Hors-ligne' } });
    await m.mere.admin('POST', '/admin/revoquer', { uuid: f1.uuid });
    m.reseau.regler('ouvert');
    verifier('au retour, le poste reçoit 401 et se SUSPEND', await attendre(async () => (await f1.etat()).suspendu));
    verifier('il CONSERVE ses données locales (rien n\'est purgé)', (await f1.liste('patients')).length === 1);
    verifier('son opération reste en attente, rien n\'est perdu', (await f1.etat()).en_attente === 1);
    verifier('la mère n\'a rien reçu de lui', (await m.mere.admin('GET', '/admin/compte?collection=patients')).json.n === 0);
    await m.fermer();
  },
  async R8() {
    courant = 'SYNC-R9/R16/R17 · réinitialisation en production : fenêtre, second profil, sauvegarde, époque';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'À effacer' } });
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'tarifs', fiche: 'CONSULT', champs: { prix: 5000 } });
    await attendre(async () => (await f2.liste('patients')).length === 1 && (await f2.vue('tarifs', 'CONSULT')).existe);
    /* Un appareil ancien, qui n'a pas tiré avant d'envoyer, ne doit pas pouvoir ressusciter des données. */
    const brut = '00000000-0000-7000-8000-000000000001';
    const { json: cb } = await m.mere.admin('POST', '/admin/code', { etiquette: 'brut' });
    const jb = (await m.mere.direct('POST', '/appairage', { code: cb.code, uuid: brut })).json;
    const ferme = await m.mere.admin('POST', '/admin/reinitialiser', { confirmation: 'NASSIERA TOO', second: 'daf' });
    verifier('fenêtre fermée : réinitialisation refusée, nommée', ferme.status === 403 && ferme.json.code === 'reinit_fermee', ferme);
    await m.mere.admin('POST', '/admin/reinit-fenetre', { ouvrir: true });
    const sans2 = await m.mere.admin('POST', '/admin/reinitialiser', { confirmation: 'NASSIERA TOO' });
    verifier('sans second profil : refusée', sans2.status === 422 && sans2.json.code === 'second_profil_requis', sans2);
    const mauvaise = await m.mere.admin('POST', '/admin/reinitialiser', { confirmation: 'autre', second: 'daf' });
    verifier('mauvaise confirmation : refusée', mauvaise.status === 422, mauvaise);
    m.reseau.regler('ferme');
    await f2.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Non envoyé' } });
    const ok = await m.mere.admin('POST', '/admin/reinitialiser', { confirmation: 'NASSIERA TOO', second: 'daf' });
    verifier('réinitialisation acceptée, époque + 1', ok.status === 200 && ok.json.epoch === 2, ok);
    verifier('une SAUVEGARDE préalable existe', ok.json.sauvegarde && fs.existsSync(ok.json.sauvegarde), ok.json.sauvegarde);
    const perime = await m.mere.direct('POST', '/sync/push', { epoch: 1, horloge: Date.now(), ops: [{ id: 'ancien-1', appareil: brut, epoch: 1, collection: 'patients', fiche: 'zombie', type: 'creer', champs: { nom: 'Zombie', code: 'PROV-x' } }] },
      { Authorization: 'Bearer ' + jb.jeton });
    verifier('un envoi d\'une ANCIENNE époque est refusé (409), sans rien écrire', perime.status === 409 && perime.json.code === 'epoch_inconnue'
      && (await m.mere.admin('GET', '/admin/compte?collection=patients')).json.n === 0, perime);
    m.reseau.regler('ouvert');
    verifier('F2 EXPORTE ses opérations non envoyées avant de purger', await attendre(async () => (await f2.etat()).exports.length === 1));
    const exp = JSON.parse(fs.readFileSync((await f2.etat()).exports[0], 'utf8'));
    verifier('le fichier d\'export contient bien l\'opération', exp.operations.length === 1 && exp.operations[0].champs.nom === 'Non envoyé');
    verifier('les deux postes n\'ont plus aucun dossier', await attendre(async () => (await f1.liste('patients')).length === 0 && (await f2.liste('patients')).length === 0, 15000));
    verifier('les ESSENTIELS (tarifs) sont conservés partout', await attendre(async () => (await f1.vue('tarifs', 'CONSULT')).data.prix === 5000 && (await f2.vue('tarifs', 'CONSULT')).data.prix === 5000, 10000));
    verifier('les opérations d\'avant ne ressuscitent pas', (await m.mere.admin('GET', '/admin/compte?collection=patients')).json.n === 0);
    verifier('la fenêtre se referme d\'elle-même', (await m.mere.admin('GET', '/admin/etat')).json.reinit_ouverte === false);
    await m.fermer();
  },
  async R21() {
    courant = 'SYNC-R21 · un dossier qu\'on vient de créer ne DISPARAÎT pas de l\'écran entre l\'accusé et le tirage';
    const m = await monde(); const f1 = await m.fileul('F1');
    m.reseau.retardPull = 500;
    await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Clignote' } });
    let min = 99; const t0 = Date.now();
    while (Date.now() - t0 < 2500) { min = Math.min(min, (await f1.liste('patients')).length); await dormir(15); }
    verifier('le dossier reste visible en continu (2,5 s d\'échantillonnage, tirage ralenti)', min === 1, min);
    verifier('et finit confirmé avec son numéro réel', await attendre(async () => { const l = await f1.liste('patients'); return l.length === 1 && /^CNT\/\d+\/26$/.test(l[0].data.code) && (await f1.vide()); }, 10000));
    await m.fermer();
  },
  async R12() {
    courant = 'SYNC-R12 · horloge d\'un poste en avance de 10 min : l\'ordre vient de la mère';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2', { decalage: 10 * 60 * 1000 });
    const p = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Horloge', telephone: '000' } });
    await attendre(async () => (await f2.vue('patients', p.fiche)).existe);
    await f2.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { telephone: '111' } });
    await attendre(async () => (await f1.vue('patients', p.fiche)).data.telephone === '111');
    await f1.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { telephone: '222' } });
    await attendre(async () => (await f1.vide()) && (await f2.vue('patients', p.fiche)).data.telephone === '222', 15000);
    verifier('la modification POSTÉRIEURE gagne, malgré l\'horloge en avance de l\'autre', (await f2.vue('patients', p.fiche)).data.telephone === '222');
    verifier('aucun conflit (la seconde a vu la première)', (await m.mere.admin('GET', '/admin/etat')).json.conflits_ouverts === 0);
    const e = (await m.mere.admin('GET', '/admin/etat')).json;
    verifier('la dérive de F2 est SIGNALÉE, pas celle de F1', e.derives.includes(f2.uuid) && !e.derives.includes(f1.uuid), e.derives);
    await m.fermer();
  },
  async R14() {
    courant = 'SYNC-R14 · « Renvoyer vers tous » avec un poste éteint';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'X' } });
    await attendre(async () => (await f2.liste('patients')).length === 1);
    await f2.tuer();
    const { json } = await m.mere.admin('POST', '/admin/resync');
    verifier('F1, en ligne, acquitte la demande', await attendre(async () => (await m.mere.admin('GET', '/admin/etat')).json.resync.acks.includes(f1.uuid)));
    verifier('F2, éteint, n\'a pas acquitté : la console le montre en retard', !(await m.mere.admin('GET', '/admin/etat')).json.resync.acks.includes(f2.uuid));
    await f2.demarrer();
    verifier('F2 acquitte à sa reconnexion', await attendre(async () => (await m.mere.admin('GET', '/admin/etat')).json.resync.acks.includes(f2.uuid), 15000), json);
    verifier('F2 a toujours ses données après le tirage complet', (await f2.liste('patients')).length === 1);
    await m.fermer();
  },
  async R18() {
    courant = 'SYNC-R18 · appairage : code à usage unique, expiration, jeton qui expire, renouvellement rejoué';
    let m = await monde({ codeTtl: 300 });
    const f1 = await m.fileul('F1', { sansAppairage: true });
    const { json: c } = await m.mere.admin('POST', '/admin/code', { etiquette: 'F1' });
    await dormir(500);
    const exp = await f1.post('/appairer', { code: c.code });
    verifier('un code expiré est refusé', exp.status === 403 && exp.json.code === 'code_expire', exp.json);
    await m.fermer();

    m = await monde();
    const g1 = await m.fileul('G1', { sansAppairage: true }); const g2 = await m.fileul('G2', { sansAppairage: true });
    const { json: c2 } = await m.mere.admin('POST', '/admin/code', { etiquette: 'G' });
    const a = await g1.post('/appairer', { code: c2.code }); const b = await g2.post('/appairer', { code: c2.code });
    verifier('un code ne sert QU\'UNE fois', a.status === 200 && b.status === 403 && b.json.code === 'code_utilise', [a.status, b.json]);
    await m.fermer();

    m = await monde({ jetonTtl: 400 });
    const h = await m.fileul('H1');
    await dormir(800);
    await h.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Après expiration' } });
    verifier('un jeton expiré est renouvelé SANS que l\'agent le voie', await attendre(async () => h.vide(), 10000) && !(await h.etat()).suspendu);
    const ancien = (await h.get('/renouv')).renouvellement;
    await h.post('/renouveler-force');
    const rejeu = await m.mere.direct('POST', '/renouveler', { renouvellement: ancien });
    verifier('un renouvellement REJOUÉ révoque l\'appareil', rejeu.status === 401 && rejeu.json.code === 'appareil_revoque', rejeu);
    verifier('l\'appareil se suspend ensuite', await attendre(async () => { await h.ecrire({ type: 'creer', collection: 'notes', champs: { t: 1 } }); return (await h.etat()).suspendu; }, 10000));
    await m.fermer();
  },
  async R19() {
    courant = 'SYNC-R19 · file persistante : le poste est tué (SIGKILL) avec des opérations en attente';
    const m = await monde(); const f1 = await m.fileul('F1');
    await m.mere.tuer();
    await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Un' } });
    await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Deux' } });
    await f1.tuer();
    await f1.demarrer();
    verifier('après redémarrage brutal, les 2 opérations sont toujours en attente', (await f1.etat()).en_attente === 2);
    verifier('et les dossiers sont toujours visibles hors ligne', (await f1.liste('patients')).length === 2);
    await m.mere.demarrer();
    verifier('la mère revient : tout part, sans doublon', await attendre(async () => f1.vide(), 15000)
      && (await m.mere.admin('GET', '/admin/compte?collection=patients')).json.n === 2);
    await m.fermer();
  },
  async R20() {
    courant = 'SYNC-R20 · règles de famille : archivage (RG-14), pièce émise, journal, référentiel';
    const m = await monde(); const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const p = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Archivable' } });
    await attendre(async () => (await f2.vue('patients', p.fiche)).existe);
    await f1.ecrire({ type: 'supprimer', collection: 'patients', fiche: p.fiche });
    await attendre(async () => (await f1.etat()).a_traiter.length === 1);
    verifier('« supprimer » est REFUSÉ, avec le geste de remplacement', (await f1.etat()).a_traiter[0].code === 'suppression_interdite' && /Archiver/.test((await f1.etat()).a_traiter[0].geste));
    await f1.ecrire({ type: 'archiver', collection: 'patients', fiche: p.fiche });
    verifier('« archiver » se propage aux autres postes', await attendre(async () => (await f2.vue('patients', p.fiche)).archive === true));
    await f2.ecrire({ type: 'modifier', collection: 'patients', fiche: p.fiche, champs: { nom: 'Modifié' } });
    await attendre(async () => (await f2.etat()).a_traiter.some((r) => r.code === 'fiche_archivee'));
    verifier('une fiche archivée ne se modifie pas : refus nommé', (await f2.etat()).a_traiter.some((r) => r.code === 'fiche_archivee'));
    await f1.ecrire({ type: 'restaurer', collection: 'patients', fiche: p.fiche });
    verifier('« restaurer » rend la fiche', await attendre(async () => (await f2.vue('patients', p.fiche)).archive === false));

    const fa = await f1.ecrire({ type: 'creer', collection: 'factures', champs: { total: 100 } });
    await f1.ecrire({ type: 'modifier', collection: 'factures', fiche: fa.fiche, champs: { emise: true } });
    await f1.ecrire({ type: 'modifier', collection: 'factures', fiche: fa.fiche, champs: { total: 200 } });
    verifier('une pièce ÉMISE ne se réécrit pas', await attendre(async () => (await f1.etat()).a_traiter.some((r) => r.code === 'piece_emise_immuable')));
    verifier('la valeur de la pièce émise est intacte', (await m.mere.admin('GET', `/admin/fiche?collection=factures&id=${fa.fiche}`)).json.data.total === 100);

    const j = await f1.ecrire({ type: 'creer', collection: 'constantes', champs: { pouls: 80 } });
    await f1.ecrire({ type: 'modifier', collection: 'constantes', fiche: j.fiche, champs: { pouls: 120 } });
    verifier('un journal ne se modifie pas', await attendre(async () => (await f1.etat()).a_traiter.some((r) => r.code === 'journal_immuable')));

    await f1.ecrire({ type: 'creer', collection: 'tarifs', fiche: 'T1', champs: { prix: 1 } });
    verifier('un poste ne modifie pas un référentiel', await attendre(async () => (await f1.etat()).a_traiter.some((r) => r.code === 'droit_refuse')));
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'tarifs', fiche: 'T1', champs: { prix: 7000 } });
    verifier('la console de la mère, elle, le modifie : tous les postes le reçoivent', await attendre(async () => (await f1.vue('tarifs', 'T1')).data.prix === 7000 && (await f2.vue('tarifs', 'T1')).data.prix === 7000));
    await m.fermer();
  },
};

/* --- exécution ------------------------------------------------------------------------------ */
(async () => {
  const voulus = process.argv.slice(2);
  const noms = Object.keys(scenarios).filter((n) => !voulus.length || voulus.includes(n));
  const t0 = Date.now();
  for (const n of noms) {
    console.log(`\n▶ ${n}`);
    /* Garde-fou : un scénario qui se bloque ou qui lève une exception ne laisse ni processus
       orphelin ni banc suspendu — il échoue, nommé, et les processus sont tués. */
    let minuterie;
    try {
      await Promise.race([scenarios[n](), new Promise((_, ko) => { minuterie = setTimeout(() => ko(new Error('scénario bloqué (> 90 s)')), 90000); })]);
      console.log('  ' + courant);
    } catch (e) { verifier('le scénario s\'exécute sans erreur', false, String(e && e.message || e)); }
    finally { clearTimeout(minuterie); while (ouverts.length) await ouverts.pop().fermer().catch(() => {}); }
  }
  const ko = verdicts.filter((v) => !v.ok);
  console.log(`\n══ ${verdicts.length - ko.length}/${verdicts.length} vérifications ; ${noms.length} scénarios ; ${((Date.now() - t0) / 1000).toFixed(1)} s ══`);
  for (const v of ko) console.log(`   ✗ [${v.scenario}] ${v.libelle}`);
  process.exit(ko.length ? 1 : 0);
})();
