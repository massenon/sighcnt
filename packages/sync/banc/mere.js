'use strict';
/* =============================================================================
 * SIGH-CNT — BANC DE SYNCHRONISATION : le POSTE MÈRE (implémentation de référence)
 * -----------------------------------------------------------------------------
 * Ce fichier n'est PAS le produit : c'est l'exécutable de référence du protocole
 * décrit dans docs/specs/SPEC-protocole-synchronisation.md. Il sert à éprouver
 * l'architecture (coupures, rejeux, conflits, bail de stock, époque) avant d'écrire
 * le service Dart. Stockage : SQLite pour le banc ; la cible est PostgreSQL derrière
 * la même interface de transactions. Aucune dépendance.
 *
 * Lancement : node mere.js --port=9000 --db=mere.sqlite --admin=secret
 * ========================================================================== */
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');

const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const PORT = +arg('port', 0);
const DB = arg('db', ':memory:');
const ADMIN = arg('admin', 'admin-banc');
const CODE_TTL = +arg('code-ttl', 15 * 60 * 1000);
const JETON_TTL = +arg('jeton-ttl', 24 * 3600 * 1000);
const CLINIQUE = 'NASSIERA TOO';
const DERIVE_MAX_MS = 2 * 60 * 1000;
const RELAIS = arg('relais', ''); const SECRET_RELAIS = arg('secret-relais', 'secret-mere');
const RESTAURER = arg('restaurer', '0') === '1'; const CLE_ARG = arg('cle', '');
/* Lot D5 : le dossier des fichiers numérisés de la mère (vide : la mère n'en tient pas, 503). */
const FICHIERS_DIR = arg('fichiers', '');

/* Une famille par collection (PRD §8) : A fiche descriptive · B journal · C pièce
   émise · D agrégat à invariant · R référentiel (la mère seule écrit). */
const FAMILLES = {
  patients: 'A', rendezvous: 'A',
  constantes: 'B', notes: 'B',
  cpn: 'B', cpon: 'B', surveillances: 'B', orientations: 'B', /* suite du mobile (E1650 à E1660) */
  factures: 'C', prescriptions: 'C',
  stock: 'D',
  tarifs: 'R', chambres: 'R', produits: 'R', transcriptions: 'B',
  /* L0 : les paramètres versionnés par date (R : la mère seule écrit, une fiche = une version immuable) et leurs usages par les pièces (B : ajout seul). */
  parametres: 'R', usagesParametres: 'B',
  /* Lot T6 : le référentiel de prix unique (versions immuables, R) et les demandes de prix d'un fileul (A : le fileul dépose, la mère complète du verdict). */
  versionsTarif: 'R', propositionsTarif: 'A',
  /* Lot IMP-C : la demande d'import d'un fileul (A : le fileul dépose, la mère complète du verdict ; jamais vers un téléphone). */
  demandesImport: 'A',
  /* Lot CONT : la décision de validation d'un fileul (A : le fileul dépose, la mère applique mécaniquement et complète du verdict ; jamais vers un téléphone). */
  demandesValidation: 'A',
  /* Lot IMP-E : le stock que le pont du poste synchronise comme la mère Dart (`sync_dart/lib/src/mere.dart`) : les lots et les mouvements sont des fiches descriptives (A, une identité par fiche,
     jamais dédoublée), les variations de stock sont des fiches AJOUTÉES (une par variation, jamais modifiées : `fiche_existe` à la seconde création du même identifiant). */
  lots: 'A', mouvements: 'A', deltasCompteurs: 'A',
  /* Lot D5 : les MÉTADONNÉES des fichiers numérisés (le courrier et le document du patient portent `fichier` ; le registre `fichiers` est une fiche par empreinte, ajout seul). Le binaire voyage
     à part (`fichiers.js`). Jamais vers un téléphone (RG-13). */
  courriers: 'A', documentsPatient: 'A', fichiers: 'B',
  /* Lot OCR-prep : une lecture OCR est une version immuable du texte d'un fichier (ajout seul, identité commune). */
  lecturesOcr: 'B',
  /* Lot SYNC-CFG (décision 26) : budgets, immobilisations et couvertures d'assurance, écrits à n'importe quel poste (A : champ à champ ; une couverture se clôt sur sa propre fiche quand
     la suivante prend effet). Identité commune par le contenu, posée par le poste. Jamais vers un téléphone (RG-13). Le refus au rejeu du budget d'un exercice clos est tenu par la mère
     Dart (`sync_dart`), comme celui des pièces (lot CLO-2) : cette mère de référence ne connaît pas les exercices. */
  budgets: 'A', immobilisations: 'A', couverturesAssurance: 'A',
  /* Lot CMD (AQ point 1) : la commande de stock gros voyage (A : champ à champ), identité commune par le contenu posée par le poste (`identiteSyncCommande` du domaine), référence provisoire par poste
     que la mère remplace par le rang définitif à l'adoption (`referenceCommandeDefinitive`), validation jamais écrite directement par un autre poste. Jamais vers un téléphone (RG-13). */
  commandes: 'A',
};
const FICHIERS_JAMAIS_MOBILE = new Set(['courriers', 'documentsPatient', 'fichiers', 'lecturesOcr']);
/* Lot SYNC-CFG : les trois collections de gestion (identité commune par le contenu, jamais vers un téléphone). */
const GESTION = new Set(['budgets', 'immobilisations', 'couverturesAssurance']);
/* Lot CMD : la commande de stock gros (jamais vers un téléphone ; mêmes règles que `commande_synchronisee.dart`, dont celle-ci est la copie de référence). */
const ACHATS = new Set(['commandes']);
const RE_PROV = /^BC-(\d{4})-P([A-Za-z0-9]+)-(\d+)$/; const RE_DEF = /^BC-(\d{4})-(\d+)$/;
const STATUTS_VALIDES = ['validee', 'transmise', 'livree', 'soldee'];
const validee = (c) => !!c && STATUTS_VALIDES.includes(c.statutCommande) && !!c.valideePar;
const ESSENTIELLES = new Set(['tarifs', 'versionsTarif', 'chambres']);

const PARAMETRES = require('./parametres');
const db = new DatabaseSync(DB);
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
  CREATE TABLE IF NOT EXISTS operations (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, appareil TEXT, epoch INTEGER,
    hlc INTEGER, collection TEXT, fiche TEXT, type TEXT, champs TEXT, famille TEXT);
  CREATE TABLE IF NOT EXISTS resultats (id TEXT PRIMARY KEY, json TEXT);
  CREATE TABLE IF NOT EXISTS fiches (collection TEXT, id TEXT, data TEXT, fieldseq TEXT, archive INTEGER, PRIMARY KEY (collection, id));
  CREATE TABLE IF NOT EXISTS appareils (uuid TEXT PRIMARY KEY, etiquette TEXT, role TEXT, etat TEXT, jeton_hash TEXT, jeton_expire INTEGER,
    renouv_hash TEXT, dernier_contact INTEGER, dernier_seq INTEGER DEFAULT 0, derive_ms INTEGER DEFAULT 0, profil TEXT, fonction TEXT);
  CREATE TABLE IF NOT EXISTS codes (code TEXT PRIMARY KEY, etiquette TEXT, role TEXT, expire INTEGER, utilise INTEGER DEFAULT 0, profil TEXT, fonction TEXT);
  CREATE TABLE IF NOT EXISTS conflits (id INTEGER PRIMARY KEY AUTOINCREMENT, collection TEXT, fiche TEXT, champ TEXT, a TEXT, b TEXT,
    appareil TEXT, etat TEXT DEFAULT 'ouvert', decision TEXT);
  CREATE TABLE IF NOT EXISTS plages (appareil TEXT, nom TEXT, debut INTEGER, fin INTEGER);
  CREATE TABLE IF NOT EXISTS baux (appareil TEXT, article TEXT, reste INTEGER, PRIMARY KEY (appareil, article));
  CREATE TABLE IF NOT EXISTS acks (marque TEXT, appareil TEXT, PRIMARY KEY (marque, appareil));
  CREATE TABLE IF NOT EXISTS portee (appareil TEXT, collection TEXT, fiche TEXT, PRIMARY KEY (appareil, collection, fiche));
  CREATE TABLE IF NOT EXISTS sortie (appareil TEXT, n INTEGER, enveloppe TEXT, depose INTEGER DEFAULT 0, PRIMARY KEY (appareil, n));
`);
/* Migration (E1600) : une base d'avant la fonction authentifiée reçoit les colonnes ; un appareil déjà appairé garde `fonction` NULL,
   et la mère refuse alors ses prescriptions en le disant (nouvel appairage). */
for (const [t, c] of [['codes', 'profil'], ['codes', 'fonction'], ['appareils', 'fonction']]) {
  try { db.exec(`ALTER TABLE ${t} ADD COLUMN ${c} TEXT`); } catch (e) { /* déjà présente */ }
}
const meta = (k, d) => { const r = db.prepare('SELECT v FROM meta WHERE k=?').get(k); return r ? r.v : d; };
const setMeta = (k, v) => db.prepare('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v').run(k, String(v));
if (meta('epoch') === undefined) setMeta('epoch', 1);
if (meta('next_patient') === undefined) setMeta('next_patient', 1000);
if (meta('reinit_ouverte') === undefined) setMeta('reinit_ouverte', 0);

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
let profondeur = 0;
const tx = (fn) => {
  if (profondeur) return fn(); /* transaction imbriquée : la plus extérieure décide */
  profondeur++; db.exec('BEGIN IMMEDIATE');
  try { const r = fn(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } finally { profondeur--; }
};
class Err extends Error { constructor(status, code, motif, extra) { super(motif || code); this.status = status; this.body = Object.assign({ code, motif }, extra || {}); } }

/* --- fiches ---------------------------------------------------------------- */
function lire(c, id) {
  const r = db.prepare('SELECT * FROM fiches WHERE collection=? AND id=?').get(c, id);
  return r ? { data: JSON.parse(r.data), fieldseq: JSON.parse(r.fieldseq), archive: !!r.archive } : null;
}
function ecrire(c, id, f) {
  db.prepare(`INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,?)
    ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data, fieldseq=excluded.fieldseq, archive=excluded.archive`)
    .run(c, id, JSON.stringify(f.data), JSON.stringify(f.fieldseq), f.archive ? 1 : 0);
}
function journaliser(op, champs, appareil) {
  const r = db.prepare('INSERT INTO operations(id,appareil,epoch,hlc,collection,fiche,type,champs,famille) VALUES(?,?,?,?,?,?,?,?,?)')
    .run(op.id, appareil, +meta('epoch'), op.hlc || 0, op.collection, op.fiche, op.type, JSON.stringify(champs || {}), FAMILLES[op.collection]);
  return Number(r.lastInsertRowid);
}
const reserve = (article) => db.prepare('SELECT COALESCE(SUM(reste),0) AS s FROM baux WHERE article=?').get(article).s;

/* --- le cœur : une opération → un résultat NOMMÉ ----------------------------- */
function traiter(op, app) {
  const fam = FAMILLES[op.collection];
  const refus = (code, motif, geste) => ({ id: op.id, statut: 'refusee', code, motif, geste });
  if (!fam) return refus('collection_inconnue', 'Collection inconnue : ' + op.collection, 'Mettre le poste à jour');
  if (op.type === 'supprimer') return refus('suppression_interdite', 'Aucune suppression physique (RG-14).', 'Archiver la fiche');
  if (fam === 'R' && app.role !== 'mere') return refus('droit_refuse', 'Un référentiel ne se modifie qu’à la console de la mère.', 'Demander la modification à l’administrateur');

  const f = lire(op.collection, op.fiche);

  /* L0 : une version de paramètre est une fiche IMMUABLE. La mère REFAIT le contrôle du poste (même fonction que l'émission) : version croissante, type, date d'effet,
     valeur déjà utilisée par une pièce (usages relevés des postes), téléphone interdit pour un paramètre réservé. Un refus est nommé, jamais avalé. */
  if (op.collection === 'parametres') {
    if (op.type !== 'creer') return refus('version_immuable', 'Une version de paramètre ne se réécrit jamais : on ajoute une version.', 'Ajouter une nouvelle version avec sa date d’effet');
    if (f) return refus('fiche_existe', 'Cette version existe déjà.', 'Aucun');
    const existantes = db.prepare("SELECT data FROM fiches WHERE collection='parametres'").all().map((r) => JSON.parse(r.data)).filter((d) => d.cle === op.champs.cle);
    const usages = db.prepare("SELECT data FROM fiches WHERE collection='usagesParametres'").all().map((r) => JSON.parse(r.data));
    const v = PARAMETRES.validerFiche(op.champs, existantes, usages);
    if (!v.ok) return refus(v.code, v.motif, v.geste);
  }

  if (fam === 'D') {
    if (op.type === 'creer') {
      if (app.role !== 'mere') return refus('droit_refuse', 'Le stock initial s’ouvre à la console de la mère.', 'Contacter l’administrateur');
      const seq = journaliser(op, op.champs, app.uuid);
      ecrire(op.collection, op.fiche, { data: { qte: +op.champs.qte || 0 }, fieldseq: { qte: seq }, archive: false });
      return { id: op.id, statut: 'acceptee', seq };
    }
    if (op.type === 'sortie') {
      if (!f) return refus('fiche_inconnue', 'Article inconnu : ' + op.fiche, 'Vérifier la référence');
      const q = +op.champs.qte;
      const bail = db.prepare('SELECT reste FROM baux WHERE appareil=? AND article=?').get(app.uuid, op.fiche);
      let surBail = false;
      if (op.bail && bail && bail.reste >= q) {
        db.prepare('UPDATE baux SET reste=reste-? WHERE appareil=? AND article=?').run(q, app.uuid, op.fiche);
        surBail = true;
      } else {
        const dispo = f.data.qte - reserve(op.fiche);
        if (dispo < q) return refus('invariant_viole', `Stock insuffisant pour ${op.fiche} : disponible ${dispo}, demandé ${q} (RG-03).`, 'Réduire la quantité ou attendre un réapprovisionnement');
      }
      f.data.qte -= q;
      const seq = journaliser(op, { qte: q }, app.uuid);
      f.fieldseq.qte = seq;
      ecrire(op.collection, op.fiche, f);
      return { id: op.id, statut: 'acceptee', seq, surBail };
    }
    return refus('type_invalide', 'Opération non prévue sur le stock : ' + op.type, 'Utiliser une sortie');
  }

  if (fam === 'B') {
    if (op.type !== 'creer') return refus('journal_immuable', 'Un journal ne se modifie pas : on ajoute une ligne.', 'Ajouter une nouvelle ligne');
    /* Lot D5 : deux postes qui déposent le même fichier créent la même fiche de registre (une par empreinte) : la seconde création est ACCEPTÉE SANS EFFET. */
    if (f && (op.collection === 'fichiers' || op.collection === 'lecturesOcr')) return { id: op.id, statut: 'acceptee', seq: Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s), rejeu: true };
    if (f) return refus('fiche_existe', 'Cette ligne existe déjà.', 'Aucun');
    const seq = journaliser(op, op.champs, app.uuid);
    ecrire(op.collection, op.fiche, { data: op.champs, fieldseq: Object.fromEntries(Object.keys(op.champs).map((k) => [k, seq])), archive: false });
    return { id: op.id, statut: 'acceptee', seq };
  }

  /* Lot CMD : une validation de commande écrite directement par un autre poste est REFUSÉE au rejeu (seule la mère en écrit une, en appliquant une décision signée). */
  if (op.collection === 'commandes' && app.role !== 'mere' && (op.type === 'creer' || op.type === 'modifier')) {
    const avant = f ? f.data : null; const apres = Object.assign({}, avant || {}, op.champs || {});
    const ref = apres.reference || '';
    if (validee(avant)) {
      if (String(avant.valideePar) !== String(apres.valideePar || '') || String(avant.dateValidation || '') !== String(apres.dateValidation || '')) return refus('COMMANDE_VALIDATION_FIGEE', `La validation de la commande ${ref} (${avant.valideePar}) ne se réécrit pas.`, 'Laisser la validation telle que la mère l\'a posée');
    } else if (STATUTS_VALIDES.includes(apres.statutCommande) || apres.valideePar) {
      return refus('COMMANDE_VALIDATION_DIRECTE', `Commande ${ref} : une validation écrite directement sur la fiche par un autre poste est REFUSÉE au rejeu (RG-04).`, 'Passer par le geste « Valider une commande de stock gros » (décision signée déposée à la mère)');
    }
  }

  /* A, C et R : fusion par champ */
  if (op.type === 'creer') {
    /* Lot SYNC-CFG : identité commune par le contenu (budget, bien, couverture) : la seconde création de la même fiche est une FUSION champ à champ (mêmes valeurs : sans effet ;
       valeur différente d'un champ déjà écrit : conflit nommé), jamais un refus bruyant à « traiter ». */
    if (f && (GESTION.has(op.collection) || ACHATS.has(op.collection))) {
      /* Lot CMD : la référence d'une commande déjà adoptée ne se réécrit jamais. */
      const differents = Object.fromEntries(Object.entries(op.champs || {}).filter(([k, v]) => !(op.collection === 'commandes' && k === 'reference' && f.data.reference) && JSON.stringify(f.data[k]) !== JSON.stringify(v)));
      if (!Object.keys(differents).length) return { id: op.id, statut: 'acceptee', seq: Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s), rejeu: true };
      return traiter(Object.assign({}, op, { type: 'modifier', champs: differents, vu: {} }), app);
    }
    if (f) return refus('fiche_existe', 'Cette fiche existe déjà.', 'Aucun');
    const champs = Object.assign({}, op.champs);
    let numero; let champNumero;
    /* Lot CMD : rang DÉFINITIF d'une commande créée sur un fileul (référence provisoire `BC-AAAA-P<poste>-nnnn`). */
    if (op.collection === 'commandes') {
      const pm = RE_PROV.exec(String(champs.reference || ''));
      if (pm) {
        let max = 0;
        for (const r of db.prepare("SELECT data FROM fiches WHERE collection='commandes'").all()) {
          const d = RE_DEF.exec(String(JSON.parse(r.data).reference || ''));
          if (d && d[1] === pm[1] && +d[2] > max) max = +d[2];
        }
        champs.reference = `BC-${pm[1]}-${String(max + 1).padStart(4, '0')}`; numero = champs.reference; champNumero = 'reference';
      }
    }
    if (op.collection === 'patients') {
      const m = /^CNT\/(\d+)\/26$/.exec(String(champs.code || ''));
      if (!champs.code || String(champs.code).startsWith('PROV-')) {
        const n = +meta('next_patient'); setMeta('next_patient', n + 1);
        champs.code = `CNT/${n}/26`; numero = champs.code;
      } else if (!m) {
        return refus('numero_invalide', 'Code patient mal formé : ' + champs.code, 'Laisser le poste attribuer le code');
      } else {
        const n = +m[1];
        const ok = db.prepare('SELECT 1 FROM plages WHERE appareil=? AND nom=? AND debut<=? AND fin>=?').get(app.uuid, 'patients', n, n);
        if (!ok) return refus('numero_hors_plage', `Le code ${champs.code} n’appartient pas à la plage de ce poste.`, 'Demander une nouvelle plage');
      }
      const dup = db.prepare("SELECT 1 FROM fiches WHERE collection='patients' AND json_extract(data,'$.code')=?").get(champs.code);
      if (dup) return refus('doublon_numero', 'Code patient déjà attribué : ' + champs.code, 'Demander une nouvelle plage');
    }
    let doublon = null;
    if (op.collection === 'patients' && champs.nom && champs.naissance) {
      const nomK = String(champs.nom).trim().toLowerCase();
      for (const r of db.prepare("SELECT id,data FROM fiches WHERE collection='patients'").all()) {
        const d = JSON.parse(r.data);
        if (String(d.nom || '').trim().toLowerCase() === nomK && String(d.naissance || '') === String(champs.naissance)) { doublon = r.id; break; }
      }
    }
    const seq = journaliser(op, champs, app.uuid);
    ecrire(op.collection, op.fiche, { data: champs, fieldseq: Object.fromEntries(Object.keys(champs).map((k) => [k, seq])), archive: false });
    if (doublon) db.prepare('INSERT INTO conflits(collection,fiche,champ,a,b,appareil) VALUES(?,?,?,?,?,?)').run(op.collection, op.fiche, 'doublon_possible', JSON.stringify(doublon), JSON.stringify(op.fiche), app.uuid);
    return Object.assign({ id: op.id, statut: 'acceptee', seq }, numero ? { numero } : {}, champNumero ? { champNumero } : {}, doublon ? { doublon_possible: doublon } : {});
  }
  if (!f) return refus('fiche_inconnue', 'Fiche inconnue : ' + op.fiche, 'Rafraîchir le poste');
  if (op.type === 'archiver' || op.type === 'restaurer') {
    f.archive = op.type === 'archiver';
    const seq = journaliser(op, {}, app.uuid);
    ecrire(op.collection, op.fiche, f);
    return { id: op.id, statut: 'acceptee', seq };
  }
  if (op.type === 'modifier') {
    if (f.archive) return refus('fiche_archivee', 'La fiche est archivée : restaurez-la d’abord (RG-14).', 'Restaurer la fiche');
    if (fam === 'C' && f.data.emise) return refus('piece_emise_immuable', 'Une pièce émise ne se réécrit jamais : émettre un avoir.', 'Établir une pièce de correction');
    const appliques = {}; const conflits = [];
    for (const [champ, val] of Object.entries(op.champs)) {
      const vu = (op.vu && op.vu[champ]) || 0;
      if ((f.fieldseq[champ] || 0) > vu && JSON.stringify(f.data[champ]) !== JSON.stringify(val)) {
        const r = db.prepare('INSERT INTO conflits(collection,fiche,champ,a,b,appareil) VALUES(?,?,?,?,?,?)')
          .run(op.collection, op.fiche, champ, JSON.stringify(f.data[champ] === undefined ? null : f.data[champ]), JSON.stringify(val), app.uuid);
        conflits.push({ conflit: Number(r.lastInsertRowid), champ });
      } else appliques[champ] = val;
    }
    let seq = null;
    if (Object.keys(appliques).length) {
      seq = journaliser(op, appliques, app.uuid);
      for (const k of Object.keys(appliques)) { f.data[k] = appliques[k]; f.fieldseq[k] = seq; }
      ecrire(op.collection, op.fiche, f);
    }
    return conflits.length ? { id: op.id, statut: 'fusionnee', seq, conflits } : { id: op.id, statut: 'acceptee', seq };
  }
  return refus('type_invalide', 'Type d’opération inconnu : ' + op.type, 'Mettre le poste à jour');
}

/* --- authentification ---------------------------------------------------------- */
function auth(req) {
  const m = /^Bearer ([^.]+)\.(.+)$/.exec(req.headers.authorization || '');
  if (!m) throw new Err(401, 'jeton_invalide', 'Jeton absent.');
  const a = db.prepare('SELECT * FROM appareils WHERE uuid=?').get(m[1]);
  if (!a) throw new Err(401, 'jeton_invalide', 'Appareil inconnu.');
  if (a.etat === 'revoque') throw new Err(401, 'appareil_revoque', 'Cet appareil a été révoqué.');
  if (sha(m[2]) !== a.jeton_hash) throw new Err(401, 'jeton_invalide', 'Jeton invalide.');
  if (Date.now() > a.jeton_expire) throw new Err(401, 'jeton_expire', 'Jeton expiré.');
  db.prepare('UPDATE appareils SET dernier_contact=? WHERE uuid=?').run(Date.now(), a.uuid);
  return a;
}
const adminOk = (req) => { if (req.headers['x-admin'] !== ADMIN) throw new Err(403, 'admin_requis', 'Accès administrateur requis.'); };
function emettreJetons(uuid) {
  const secret = crypto.randomBytes(24).toString('hex');
  const renouv = crypto.randomBytes(24).toString('hex');
  db.prepare('UPDATE appareils SET jeton_hash=?, jeton_expire=?, renouv_hash=? WHERE uuid=?').run(sha(secret), Date.now() + JETON_TTL, sha(renouv), uuid);
  return { jeton: uuid + '.' + secret, renouvellement: uuid + '.' + renouv };
}

/* --- l'envoi d'un lot, commun aux postes (P1) et aux mobiles (P2/P3) ------------------------- */
const AUTORISE = { reception: new Set(['patients', 'rendezvous', 'constantes', 'orientations']), soignant: new Set(['patients', 'constantes', 'notes', 'rendezvous', 'prescriptions', 'cpn', 'cpon', 'surveillances']) };
/* La prescription d'un mobile est une pièce ÉMISE : la mère REFAIT le contrôle d'habilitation. La règle n'est pas recopiée : elle est LUE dans les
   vecteurs de la maquette (PR.peutPrescrire, `mobile.json`), comme le fait le test du domaine Dart. La fonction est celle que la mère a FIXÉE à l'appairage (E1600). */
const PRESCRIPTION = (() => {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'domaine', 'test', 'vecteurs', 'mobile.json'), 'utf8')).droitsPrescription; } catch (e) { return null; }
})();
function refusPrescriptionMobile(op, app) {
  const fonction = String((app && app.fonction) || ''), nature = String((op.champs || {}).nature || '');
  const ligne = PRESCRIPTION && PRESCRIPTION.lignes.find((l) => l.fonction === fonction && l.nature === nature);
  if (ligne && ligne.autorise) return null;
  const libelle = PRESCRIPTION && PRESCRIPTION.labels[fonction];
  return { id: op.id, statut: 'refusee', code: 'droit_refuse',
    motif: `${libelle || fonction} n’est pas habilité à prescrire « ${nature} ».`,
    geste: 'Demander la prescription à un médecin' };
}

/* E1600 : la FONCTION du soignant est fixée par le code d'appairage que la console de la mère émet. Le téléphone ne la déclare plus : il la
   REÇOIT (bienvenue chiffrée) et la mère la relit dans sa propre table à chaque dépôt. Les fonctions du profil soignant sont celles de `mobFonctions`. */
const PROFILS_MOBILE = ['soignant', 'reception'];
const FONCTIONS_MOBILE = ['medecin', 'sage_femme', 'infirmier', 'aide_soignant'];
function affectationMobile(b) {
  const profil = String(b.profil || '');
  if (!PROFILS_MOBILE.includes(profil)) throw new Err(422, 'profil_requis', 'Choisir le profil du téléphone : soignant ou réception de secours.');
  const fonction = String(b.fonction || '');
  if (profil === 'reception') {
    if (fonction) throw new Err(422, 'fonction_non_applicable', 'La réception de secours n’a pas de fonction de soignant.');
    return { profil, fonction: null };
  }
  if (!FONCTIONS_MOBILE.includes(fonction)) throw new Err(422, 'fonction_inconnue', `Fonction « ${fonction || 'vide'} » inconnue : choisir parmi ${FONCTIONS_MOBILE.join(', ')}.`);
  return { profil, fonction };
}
/* Le contrôle de fonction d'une pièce émise par un mobile soignant : refus NOMMÉS, jamais une valeur du téléphone prise pour argent comptant. */
function refusFonctionMobile(app, op) {
  const champs = op.champs || {};
  const declaree = champs.fonction == null ? '' : String(champs.fonction);
  if (!app.fonction) {
    return { id: op.id, statut: 'refusee', code: 'fonction_non_fixee', motif: 'Cet appareil a été appairé avant que la clinique fixe la fonction du soignant : la mère ne peut pas vérifier son habilitation.', geste: 'Réappairer le téléphone avec un nouveau code émis par la console (Appareils)' };
  }
  if (declaree && declaree !== app.fonction) {
    return { id: op.id, statut: 'refusee', code: 'fonction_falsifiee', motif: `Le téléphone déclare « ${declaree} » mais la clinique l’a appairé comme « ${app.fonction} » : la fonction est fixée à l’appairage et ne se change pas depuis le téléphone.`, geste: 'Faire corriger la fonction par la console de la mère : nouveau code d’appairage (Appareils)' };
  }
  return null;
}
/* E1559 : une pièce du soignant ne se rattache qu'à un dossier DE SA TOURNÉE (le lot que la mère lui a déposé) : un patient hors lot est refusé en le disant. */
function refusHorsLot(app, op) {
  const patientId = String((op.champs || {}).patientId || '');
  if (patientId && db.prepare("SELECT 1 FROM portee WHERE appareil=? AND collection='patients' AND fiche=?").get(app.uuid, patientId)) return null;
  return { id: op.id, statut: 'refusee', code: 'patient_hors_lot', motif: 'Ce patient n’est pas dans le lot de ce téléphone.', geste: 'Recevoir le lot du jour à la prochaine synchronisation' };
}
function pousser(app, b) {
  if (b.epoch !== +meta('epoch')) throw new Err(409, 'epoch_inconnue', 'Époque inconnue de la mère.', { epoch_mere: +meta('epoch') });
  const derive = Math.abs(Date.now() - (b.horloge || Date.now()));
  db.prepare('UPDATE appareils SET derive_ms=? WHERE uuid=?').run(derive, app.uuid);
  const resultats = tx(() => (b.ops || []).map((op) => {
    const deja = db.prepare('SELECT json FROM resultats WHERE id=?').get(op.id);
    if (deja) return Object.assign(JSON.parse(deja.json), { rejeu: true });
    let r;
    if (app.role === 'mobile' && !(AUTORISE[app.profil] || new Set()).has(op.collection)) {
      r = { id: op.id, statut: 'refusee', code: 'droit_refuse', motif: `Le profil « ${app.profil} » ne couvre pas la collection ${op.collection}.`, geste: 'Utiliser un poste' };
    } else if (app.role === 'mobile' && app.profil === 'soignant' && ['notes', 'prescriptions'].includes(op.collection) && op.type === 'creer' && refusHorsLot(app, op)) {
      r = refusHorsLot(app, op);
    } else if (app.role === 'mobile' && app.profil === 'soignant' && ['notes', 'prescriptions'].includes(op.collection) && op.type === 'creer' && refusFonctionMobile(app, op)) {
      r = refusFonctionMobile(app, op);
    } else if (app.role === 'mobile' && op.collection === 'prescriptions' && op.type === 'creer' && refusPrescriptionMobile(op, app)) {
      r = refusPrescriptionMobile(op, app);
    } else {
      // La fonction ÉCRITE sur la pièce est celle que la mère tient pour l'appareil, jamais celle du téléphone.
      if (app.role === 'mobile' && app.profil === 'soignant' && ['notes', 'prescriptions'].includes(op.collection) && op.type === 'creer') op.champs = Object.assign({}, op.champs, { fonction: app.fonction });
      r = traiter(op, app);
    }
    if (app.role === 'mobile' && r.statut === 'acceptee' && op.type === 'creer') db.prepare('INSERT OR IGNORE INTO portee(appareil,collection,fiche) VALUES(?,?,?)').run(app.uuid, op.collection, op.fiche);
    /* E1559 : le COMPTE RENDU de la transcription (écrit par un poste) revient au téléphone qui a émis la prescription, et à lui seul. */
    if (r.statut === 'acceptee' && op.collection === 'transcriptions' && op.type === 'creer') {
      const src = db.prepare("SELECT appareil FROM operations WHERE collection='prescriptions' AND fiche=?").get(String((op.champs || {}).prescriptionId || ''));
      if (src) db.prepare('INSERT OR IGNORE INTO portee(appareil,collection,fiche) VALUES(?,?,?)').run(src.appareil, 'transcriptions', op.fiche);
    }
    db.prepare('INSERT INTO resultats(id,json) VALUES(?,?)').run(op.id, JSON.stringify(r));
    return r;
  }));
  return { resultats, seq_max: Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s) };
}

/* --- routes ------------------------------------------------------------------- */
const routes = {
  'POST /admin/code': (req, b) => {
    adminOk(req);
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    const code = Array.from(crypto.randomBytes(8)).map((x) => alphabet[x % alphabet.length]).join('');
    const role = b.role || 'fileul';
    const aff = role === 'mobile' ? affectationMobile(b) : { profil: null, fonction: null };
    db.prepare('INSERT INTO codes(code,etiquette,role,expire,profil,fonction) VALUES(?,?,?,?,?,?)').run(code, b.etiquette || '', role, Date.now() + CODE_TTL, aff.profil, aff.fonction);
    return { code };
  },
  'POST /appairage': (req, b) => {
    const c = db.prepare('SELECT * FROM codes WHERE code=?').get(String(b.code || ''));
    if (!c) throw new Err(403, 'code_invalide', 'Code d’appairage inconnu.');
    if (c.utilise) throw new Err(403, 'code_utilise', 'Ce code a déjà servi (usage unique).');
    if (Date.now() > c.expire) throw new Err(403, 'code_expire', 'Ce code a expiré.');
    db.prepare('UPDATE codes SET utilise=1 WHERE code=?').run(c.code);
    db.prepare('INSERT INTO appareils(uuid,etiquette,role,etat) VALUES(?,?,?,?)').run(b.uuid, c.etiquette, c.role, 'actif');
    return Object.assign({ epoch: +meta('epoch') }, emettreJetons(b.uuid));
  },
  'POST /renouveler': (req, b) => {
    const m = /^([^.]+)\.(.+)$/.exec(String(b.renouvellement || ''));
    const a = m && db.prepare('SELECT * FROM appareils WHERE uuid=?').get(m[1]);
    if (!a || a.etat === 'revoque') throw new Err(401, 'appareil_revoque', 'Appareil révoqué.');
    if (sha(m[2]) !== a.renouv_hash) {
      db.prepare("UPDATE appareils SET etat='revoque' WHERE uuid=?").run(a.uuid);
      throw new Err(401, 'appareil_revoque', 'Renouvellement rejoué : appareil révoqué par précaution.');
    }
    return emettreJetons(a.uuid);
  },
  'POST /sync/push': (req, b) => pousser(auth(req), b),
  'GET /sync/pull': (req, b, q) => {
    const app = auth(req);
    if (+q.epoch !== +meta('epoch')) throw new Err(409, 'epoch_inconnue', 'Époque inconnue de la mère.', { epoch_mere: +meta('epoch') });
    const depuis = +q.depuis || 0; const limite = Math.min(+q.limite || 500, 500);
    /* Lot SYNC-CFG : un mobile qui tire directement de la mère ne reçoit ni budget, ni immobilisation, ni couverture d'assurance (RG-13), comme la mère Dart. */
    const exclues = app.role === 'mobile' ? [...GESTION, ...ACHATS] : [];
    const ops = db.prepare(`SELECT seq,id,appareil,collection,fiche,type,champs FROM operations WHERE seq>?${exclues.length ? ` AND collection NOT IN (${exclues.map(() => '?').join(',')})` : ''} ORDER BY seq LIMIT ?`).all(depuis, ...exclues, limite)
      .map((o) => Object.assign({}, o, { champs: JSON.parse(o.champs) }));
    db.prepare('UPDATE appareils SET dernier_seq=MAX(dernier_seq,?) WHERE uuid=?').run(depuis, app.uuid);
    return { ops, fin: ops.length < limite, epoch: +meta('epoch'), resync: meta('resync') || null };
  },
  'POST /sync/plage': (req, b) => {
    const app = auth(req);
    const taille = Math.max(1, Math.min(+b.taille || 50, 1000));
    return tx(() => {
      const debut = +meta('next_patient'); const fin = debut + taille - 1; setMeta('next_patient', fin + 1);
      db.prepare('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)').run(app.uuid, b.nom || 'patients', debut, fin);
      return { debut, fin };
    });
  },
  'POST /sync/bail': (req, b) => {
    const app = auth(req);
    return tx(() => {
      const f = lire('stock', b.article);
      if (!f) throw new Err(422, 'fiche_inconnue', 'Article inconnu : ' + b.article);
      const dispo = f.data.qte - reserve(b.article);
      const accorde = Math.max(0, Math.min(+b.qte, dispo));
      db.prepare('INSERT INTO baux(appareil,article,reste) VALUES(?,?,?) ON CONFLICT(appareil,article) DO UPDATE SET reste=reste+excluded.reste').run(app.uuid, b.article, accorde);
      return { accorde, reste: db.prepare('SELECT reste FROM baux WHERE appareil=? AND article=?').get(app.uuid, b.article).reste };
    });
  },
  'POST /sync/ack-resync': (req, b) => { const app = auth(req); db.prepare('INSERT OR IGNORE INTO acks(marque,appareil) VALUES(?,?)').run(String(b.marque), app.uuid); return { ok: true }; },

  'POST /admin/revoquer': (req, b) => {
    adminOk(req); db.prepare("UPDATE appareils SET etat='revoque' WHERE uuid=?").run(b.uuid);
    if (RELAIS) rel('POST', '/mere/revoquer', { uuid: b.uuid }).catch(() => alerter({ type: 'revocation_relais_differee', appareil: b.uuid }));
    return { ok: true };
  },
  'POST /admin/code-mobile': async (req, b) => {
    adminOk(req);
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    const code = Array.from(crypto.randomBytes(8)).map((x) => alphabet[x % alphabet.length]).join('');
    const aff = affectationMobile(b);
    db.prepare('INSERT INTO codes(code,etiquette,role,expire,profil,fonction) VALUES(?,?,?,?,?,?)').run(code, b.etiquette || '', 'mobile', Date.now() + CODE_TTL, aff.profil, aff.fonction);
    // Le relais ne reçoit que l'empreinte ET, à titre d'étiquette d'affichage (jamais d'autorité), le profil et la fonction du code.
    await rel('POST', '/mere/code', { hash: sha(code), profil: aff.profil, fonction: aff.fonction });
    return { code, cle: CLE.toString('base64'), profil: aff.profil, fonction: aff.fonction };
  },
  'POST /admin/lot': (req, b) => {
    adminOk(req);
    const fiches = [];
    const lot = b.fiches.slice();
    /* Lot D5 : un lot de tournée ne porte JAMAIS une fiche de fichier numérisé (courrier, document du patient, registre par empreinte) : refus nommé, rien n'est publié (RG-13). */
    const interdite = lot.find((f) => FICHIERS_JAMAIS_MOBILE.has(f.collection));
    if (interdite) throw new Err(422, 'fichiers_interdits_au_mobile', `la collection « ${interdite.collection} » ne va jamais vers un téléphone (RG-13) : les fichiers numérisés se consultent depuis un poste`);
    /* Lot SYNC-CFG : ni budget, ni immobilisation, ni couverture d'assurance dans un lot de tournée (RG-13). */
    const gestion = lot.find((f) => GESTION.has(f.collection));
    const achats = lot.find((f) => ACHATS.has(f.collection));
    if (achats) throw new Err(422, 'achats_interdits_au_mobile', `la collection « ${achats.collection} » ne va jamais vers un téléphone (RG-13) : les achats se consultent depuis un poste`);
    if (gestion) throw new Err(422, 'gestion_interdite_au_mobile', `la collection « ${gestion.collection} » ne va jamais vers un téléphone (RG-13) : la comptabilité et l'assurance se consultent depuis un poste`);
    /* E1600/E1559 : le CATALOGUE des produits (prix d'achat, stock du jour, RG-02) part avec le lot d'un soignant habilité à prescrire des médicaments ;
       jamais à une infirmière ni à une réception. Ce n'est pas une donnée patient : il ne sort pas du périmètre de la tournée. */
    const dest = db.prepare('SELECT * FROM appareils WHERE uuid=?').get(b.uuid);
    if (b.catalogue !== false && dest && dest.profil === 'soignant' && PRESCRIPTION && PRESCRIPTION.lignes.some((l) => l.fonction === dest.fonction && l.nature === 'medicament' && l.autorise)) {
      for (const x of db.prepare("SELECT id FROM fiches WHERE collection='produits' AND archive=0").all()) lot.push({ collection: 'produits', id: x.id });
    }
    for (const f of lot) {
      const x = lire(f.collection, f.id); if (!x) continue;
      db.prepare('INSERT OR IGNORE INTO portee(appareil,collection,fiche) VALUES(?,?,?)').run(b.uuid, f.collection, f.id);
      fiches.push({ collection: f.collection, id: f.id, data: x.data, fieldseq: x.fieldseq, archive: x.archive });
    }
    publier(b.uuid, { type: 'lot', expire: Date.now() + (b.ttl_ms || 48 * 3600 * 1000), fiches });
    return { fiches: fiches.length };
  },
  'POST /admin/debloquer': (req, b) => { adminOk(req); setMeta('bloque:' + b.uuid, ''); return { ok: true }; },
  'POST /admin/resync': (req) => { adminOk(req); const m = String(Date.now()); setMeta('resync', m); return { marque: m }; },
  /* ADR-0006 : l'état pair vu par la mère (fonction pure des opérations relevées) et la décision de la personne habilitée sur un conflit marqué. */
  'GET /admin/pair/etat': (req) => {
    adminOk(req);
    const e = pairMod.etat(pairOps(), pairMod.droitsBanc);
    return { fiches: e.fiches, stock: e.stock, besoins: e.besoins, conflits: e.conflits, tranches: e.tranches, refusees: e.refusees, provisoire: [...e.provisoire].sort(), ops: pairOps().length, seq_max: +meta('pair_seq', 0) };
  },
  'POST /admin/pair/trancher': (req, b) => {
    adminOk(req);
    const [collection, fiche] = String(b.fiche || '').split('/');
    const e = pairMod.etat(pairOps(), pairMod.droitsBanc);
    if (!e.conflits.some((c) => c.fiche === b.fiche && c.champ === b.champ)) throw new Err(409, 'aucun_conflit', 'Aucun conflit marqué sur ce champ : rien à trancher.');
    const op = { id: 'mere-trancher-' + require('node:crypto').randomUUID(), appareil: 'mere', hlc: horlogePair.emettre(), collection, fiche, type: 'trancher', champs: { [b.champ]: b.valeur }, role: 'mere' };
    setMeta('pair_hlc', horlogePair.dernier);
    const seq = +meta('pair_seq', 0) + 1; setMeta('pair_seq', seq);
    tx(() => { db.prepare('INSERT INTO pair_ops(id,json,seq) VALUES(?,?,?)').run(op.id, JSON.stringify(op), seq); pairPublier({ type: 'op', op: Object.assign({}, op, { seq }) }); });
    return { ok: true, id: op.id, seq };
  },
  'GET /admin/etat': (req) => {
    adminOk(req);
    const marque = meta('resync') || null;
    return {
      epoch: +meta('epoch'),
      seq_max: Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s),
      appareils: db.prepare('SELECT uuid,etiquette,role,etat,dernier_contact,dernier_seq,derive_ms FROM appareils').all(),
      derives: db.prepare('SELECT uuid FROM appareils WHERE derive_ms>?').all(DERIVE_MAX_MS).map((x) => x.uuid),
      conflits_ouverts: db.prepare("SELECT COUNT(*) AS n FROM conflits WHERE etat='ouvert'").get().n,
      resync: { marque, acks: marque ? db.prepare('SELECT appareil FROM acks WHERE marque=?').all(marque).map((x) => x.appareil) : [] },
      reinit_ouverte: meta('reinit_ouverte') === '1',
      nb_operations: Number(db.prepare('SELECT COUNT(*) AS n FROM operations').get().n),
      rep_seq: +meta('rep_seq', 0), rep_n: +meta('rep_n', 0), alertes, restauration: meta('restauration') || null,
      bloques: db.prepare("SELECT k FROM meta WHERE k LIKE 'bloque:%' AND v<>''").all().map((x) => x.k.slice(7)),
    };
  },
  'GET /admin/fiche': (req, b, q) => { adminOk(req); return lire(q.collection, q.id) || { absente: true }; },
  'GET /admin/compte': (req, b, q) => { adminOk(req); return { n: db.prepare('SELECT COUNT(*) AS n FROM fiches WHERE collection=? AND archive=0').get(q.collection).n }; },
  'GET /admin/empreinte': (req) => { adminOk(req); const rows = db.prepare('SELECT collection,id,data,archive FROM fiches ORDER BY collection,id').all(); return { empreinte: sha(JSON.stringify(rows)), n: rows.length }; },
  'GET /admin/conflits': (req) => { adminOk(req); return db.prepare('SELECT * FROM conflits').all(); },
  'POST /admin/trancher': (req, b) => tx(() => {
    adminOk(req);
    const c = db.prepare('SELECT * FROM conflits WHERE id=?').get(b.id);
    if (!c || c.etat !== 'ouvert') throw new Err(422, 'conflit_inconnu', 'Conflit inexistant ou déjà tranché.');
    if (b.decision === 'b') {
      const f = lire(c.collection, c.fiche);
      const val = JSON.parse(c.b);
      const op = { id: 'tranche-' + c.id + '-' + crypto.randomUUID(), collection: c.collection, fiche: c.fiche, type: 'modifier', champs: { [c.champ]: val }, hlc: Date.now() };
      const seq = journaliser(op, op.champs, 'mere');
      f.data[c.champ] = val; f.fieldseq[c.champ] = seq; ecrire(c.collection, c.fiche, f);
    }
    db.prepare("UPDATE conflits SET etat='tranche', decision=? WHERE id=?").run(b.decision, c.id);
    return { ok: true };
  }),
  'POST /admin/referentiel': (req, b) => tx(() => {
    adminOk(req);
    const op = { id: 'ref-' + crypto.randomUUID(), collection: b.collection, fiche: b.fiche, type: lire(b.collection, b.fiche) ? 'modifier' : 'creer', champs: b.champs, hlc: Date.now(), vu: {} };
    if (op.type === 'modifier') { const f = lire(b.collection, b.fiche); op.vu = Object.fromEntries(Object.keys(b.champs).map((k) => [k, f.fieldseq[k] || 0])); }
    return traiter(op, { uuid: 'mere', role: 'mere' });
  }),
  'POST /admin/stock': (req, b) => tx(() => {
    adminOk(req);
    return traiter({ id: 'stk-' + crypto.randomUUID(), collection: 'stock', fiche: b.article, type: 'creer', champs: { qte: b.qte }, hlc: Date.now() }, { uuid: 'mere', role: 'mere' });
  }),
  'POST /admin/reinit-fenetre': (req, b) => { adminOk(req); setMeta('reinit_ouverte', b.ouvrir ? 1 : 0); return { ouverte: !!b.ouvrir }; },
  'POST /admin/reinitialiser': (req, b) => {
    adminOk(req);
    if (meta('reinit_ouverte') !== '1') throw new Err(403, 'reinit_fermee', 'La réinitialisation est fermée : l’administrateur doit ouvrir la fenêtre.');
    if (b.confirmation !== CLINIQUE) throw new Err(422, 'confirmation_invalide', 'Saisir le nom de la clinique pour confirmer.');
    if (!b.second) throw new Err(422, 'second_profil_requis', 'Un second profil (DAF ou Direction) doit confirmer.');
    const sauvegarde = `${DB === ':memory:' ? 'mere' : DB}.avant-reinit-${Date.now()}.bak`;
    db.exec(`VACUUM INTO '${sauvegarde.replace(/'/g, '')}'`);
    tx(() => {
      const liste = Array.from(ESSENTIELLES).map((c) => `'${c}'`).join(',');
      db.exec(`DELETE FROM operations WHERE collection NOT IN (${liste});
               DELETE FROM fiches WHERE collection NOT IN (${liste});
               DELETE FROM resultats; DELETE FROM conflits; DELETE FROM plages; DELETE FROM baux; DELETE FROM acks;`);
      db.exec('DELETE FROM portee;');
      setMeta('epoch', +meta('epoch') + 1); setMeta('reinit_ouverte', 0); setMeta('next_patient', 1000); setMeta('marqueur_epoch', 1);
    });
    return { sauvegarde, epoch: +meta('epoch') };
  },
};


/* =============================================================================
 * LE PONT VERS LE RELAIS (P2) ET LES MOBILES (P3)
 * Tout ce qui sort est chiffré de bout en bout ; la mère relève le relais, il ne la contacte jamais.
 * ========================================================================== */
const { chiffrer, dechiffrer, nouvelleCle } = require('./crypto');
let CLE;
{ const c = CLE_ARG || meta('cle'); CLE = c ? Buffer.from(c, 'base64') : nouvelleCle(); setMeta('cle', CLE.toString('base64')); }
const alertes = [];
const alerter = (a) => { alertes.push(Object.assign({ quand: Date.now() }, a)); };
async function rel(methode, chemin, corps) {
  const r = await fetch(RELAIS + chemin, { method: methode, headers: { 'Content-Type': 'application/json', 'x-mere': SECRET_RELAIS }, body: corps ? JSON.stringify(corps) : undefined, signal: AbortSignal.timeout(1500) });
  const j = await r.json();
  if (!r.ok) throw Object.assign(new Error(j.code || 'http_' + r.status), { code: j.code, status: r.status });
  return j;
}
/** Une charge pour un mobile : mise en file PERSISTANTE (rang contigu) puis déposée dans l'ordre. */
function publier(uuid, payload) {
  const n = +meta('sortie_n:' + uuid, 0) + 1; setMeta('sortie_n:' + uuid, n);
  db.prepare('INSERT INTO sortie(appareil,n,enveloppe) VALUES(?,?,?)').run(uuid, n, JSON.stringify(chiffrer(CLE, payload, { id: `m-${uuid}-${n}`, appareil: uuid, dir: 'vers_mobile', n })));
}
async function expedier() {
  for (const r of db.prepare('SELECT * FROM sortie WHERE depose=0 ORDER BY appareil, n').all()) {
    await rel('POST', '/depot', { enveloppe: JSON.parse(r.enveloppe) });
    db.prepare('UPDATE sortie SET depose=1 WHERE appareil=? AND n=?').run(r.appareil, r.n);
  }
}
async function repliquer() {
  if (meta('restauration') === 'en_cours') return;
  if (meta('marqueur_epoch')) {
    const n = +meta('rep_n', 0) + 1;
    await rel('POST', '/depot', { enveloppe: chiffrer(CLE, { type: 'epoch', epoch: +meta('epoch') }, { id: 'journal-' + n, appareil: 'mere', dir: 'journal', n }) });
    setMeta('rep_n', n); setMeta('marqueur_epoch', '');
  }
  const ops = db.prepare('SELECT seq,id,appareil,epoch,hlc,collection,fiche,type,champs,famille FROM operations WHERE seq>? ORDER BY seq LIMIT 100').all(+meta('rep_seq', 0))
    .map((o) => Object.assign({}, o, { seq: Number(o.seq), champs: JSON.parse(o.champs) }));
  if (!ops.length) return;
  const n = +meta('rep_n', 0) + 1;
  await rel('POST', '/depot', { enveloppe: chiffrer(CLE, { type: 'journal', ops }, { id: 'journal-' + n, appareil: 'mere', dir: 'journal', n }) });
  setMeta('rep_n', n); setMeta('rep_seq', ops[ops.length - 1].seq);
}
function diffuser() {
  for (const a of db.prepare("SELECT uuid FROM appareils WHERE role='mobile' AND etat='actif'").all()) {
    const cur = +meta('sortie_seq:' + a.uuid, -1); if (cur < 0) continue;
    const ops = db.prepare('SELECT seq,id,appareil,collection,fiche,type,champs FROM operations WHERE seq>? ORDER BY seq LIMIT 100').all(cur);
    if (!ops.length) continue;
    /* L0 : un mobile ne reçoit de la configuration que les paramètres de la LISTE BLANCHE (déclarés `mobile`, non sensibles, famille non réservée : RG-13) ; le reste de
       `parametres`, comme toute autre collection hors de sa portée, ne part pas. */
    const mine = ops.filter((o) => FICHIERS_JAMAIS_MOBILE.has(o.collection) || GESTION.has(o.collection) || ACHATS.has(o.collection) ? false : (o.collection === 'parametres' ? PARAMETRES.autoriseMobile(JSON.parse(o.champs)) : db.prepare('SELECT 1 FROM portee WHERE appareil=? AND collection=? AND fiche=?').get(a.uuid, o.collection, o.fiche)))
      .map((o) => Object.assign({}, o, { seq: Number(o.seq), champs: JSON.parse(o.champs) }));
    setMeta('sortie_seq:' + a.uuid, Number(ops[ops.length - 1].seq));
    if (mine.length) publier(a.uuid, { type: 'ops', ops: mine });
  }
}
function traiterEnveloppe(uuid, p) {
  if (p.type === 'hello') {
    const c = db.prepare('SELECT * FROM codes WHERE code=?').get(String(p.code || ''));
    if (db.prepare('SELECT 1 FROM appareils WHERE uuid=?').get(uuid)) return;
    if (!c || c.role !== 'mobile' || c.utilise || Date.now() > c.expire) { alerter({ type: 'appareil_inconnu', appareil: uuid }); setMeta('bloque:' + uuid, 'inconnu'); return; }
    db.prepare('UPDATE codes SET utilise=1 WHERE code=?').run(c.code);
    // Le profil et la fonction viennent du CODE (table de la mère), jamais du `hello` : un profil déclaré différent est signalé.
    if (p.profil && p.profil !== c.profil) alerter({ type: 'profil_declare_different', appareil: uuid, declare: String(p.profil), code: c.profil });
    db.prepare("INSERT INTO appareils(uuid,etiquette,role,etat,profil,fonction) VALUES(?,?,'mobile','actif',?,?)").run(uuid, c.etiquette, c.profil || 'soignant', c.fonction || null);
    const debut = +meta('next_patient'); const fin = debut + 19; setMeta('next_patient', fin + 1);
    db.prepare('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)').run(uuid, 'patients', debut, fin);
    setMeta('sortie_seq:' + uuid, Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s));
    publier(uuid, { type: 'bienvenue', epoch: +meta('epoch'), plage: { debut, fin }, profil: c.profil || 'soignant', fonction: c.fonction || null });
    return;
  }
  const app = db.prepare('SELECT * FROM appareils WHERE uuid=?').get(uuid);
  if (!app || app.etat === 'revoque') return;
  if (p.type === 'push') {
    try { publier(uuid, { type: 'accuse', resultats: pousser(app, p).resultats }); }
    catch (e) { if (e instanceof Err) publier(uuid, { type: 'accuse', erreur: e.body.code, epoch_mere: e.body.epoch_mere }); else throw e; }
  }
}
async function relever() {
  const { appareils } = await rel('GET', '/mere/appareils');
  for (const a of appareils) {
    if (meta('bloque:' + a.uuid)) continue;
    const dernier = +meta('recu_n:' + a.uuid, 0);
    if (a.max_n <= dernier) continue;
    const { env } = await rel('GET', `/releve?dir=vers_mere&appareil=${a.uuid}&depuis_n=${dernier}&limite=50`);
    for (const e of env) {
      const attendu = +meta('recu_n:' + a.uuid, 0) + 1;
      if (e.n < attendu) continue;
      if (e.n > attendu) { alerter({ type: 'trou', appareil: a.uuid, attendu, recu: e.n }); setMeta('bloque:' + a.uuid, 'trou'); break; }
      let p; try { p = dechiffrer(CLE, e); } catch (x) { alerter({ type: 'authentification', appareil: a.uuid, n: e.n }); setMeta('bloque:' + a.uuid, 'auth'); break; }
      tx(() => { traiterEnveloppe(a.uuid, p); setMeta('recu_n:' + a.uuid, e.n); });
    }
  }
}
/** Restauration depuis le relais : TOUT est déchiffré et vérifié AVANT la moindre écriture. */
async function restaurer() {
  setMeta('restauration', 'en_cours');
  try {
    const charges = []; let n = 0;
    for (;;) {
      const { env, fin } = await rel('GET', `/releve?dir=journal&appareil=mere&depuis_n=${n}&limite=100`);
      for (const e of env) { if (e.n !== n + 1) throw new Error('trou dans le journal au rang ' + (n + 1)); charges.push(dechiffrer(CLE, e)); n = e.n; }
      if (fin) break;
    }
    if (!charges.length) throw new Error('journal vide');
    let maxSeq = 0; let maxEpoch = 1;
    tx(() => {
      for (const p of charges) {
        if (p.type === 'epoch') {
          const liste = Array.from(ESSENTIELLES).map((c) => `'${c}'`).join(',');
          db.exec(`DELETE FROM operations WHERE collection NOT IN (${liste}); DELETE FROM fiches WHERE collection NOT IN (${liste});`);
          maxEpoch = Math.max(maxEpoch, p.epoch); continue;
        }
        for (const op of p.ops) {
          db.prepare('INSERT INTO operations(seq,id,appareil,epoch,hlc,collection,fiche,type,champs,famille) VALUES(?,?,?,?,?,?,?,?,?,?)')
            .run(op.seq, op.id, op.appareil, op.epoch, op.hlc, op.collection, op.fiche, op.type, JSON.stringify(op.champs), op.famille);
          const f = lire(op.collection, op.fiche) || { data: {}, fieldseq: {}, archive: false };
          if (op.type === 'creer' || op.type === 'modifier') { Object.assign(f.data, op.champs); for (const k of Object.keys(op.champs)) f.fieldseq[k] = op.seq; }
          else if (op.type === 'archiver') f.archive = true; else if (op.type === 'restaurer') f.archive = false;
          else if (op.type === 'sortie') { f.data.qte -= +op.champs.qte; f.fieldseq.qte = op.seq; }
          ecrire(op.collection, op.fiche, f);
          maxSeq = Math.max(maxSeq, op.seq); maxEpoch = Math.max(maxEpoch, op.epoch);
        }
      }
      const nums = db.prepare("SELECT json_extract(data,'$.code') AS c FROM fiches WHERE collection='patients'").all().map((r) => +((/^CNT\/(\d+)\/26$/.exec(r.c || '') || [])[1] || 0));
      setMeta('next_patient', Math.max(1000, ...nums) + 1);
      setMeta('rep_seq', maxSeq); setMeta('rep_n', n); setMeta('epoch', maxEpoch + 1);
      db.exec(`INSERT OR REPLACE INTO sqlite_sequence(name,seq) VALUES('operations',${maxSeq})`);
    });
    setMeta('restauration', 'terminee');
  } catch (e) { setMeta('restauration', 'echec: ' + e.message); }
}

/* =============================================================================
 * LE RETOUR DE LA MÈRE EN MODE PAIR (ADR-0006)
 * Pendant son absence, les fileuls se sont échangé leurs opérations dans leurs journaux « pair » au relais. À son retour, la mère les RELÈVE, les rejoue par la règle
 * de fusion de pair.js (même résultat que les fileuls), leur attribue un `seq` qui FAIT FOI (le provisoire tombe), et publie ce résultat dans SON journal pair
 * (appareil « mere ») : les fileuls le relèvent comme celui d'un pair. Les conflits restent MARQUÉS : la mère ne les tranche pas seule, la console (la personne
 * habilitée) le fait par une décision `trancher`, publiée de la même façon.
 * ========================================================================== */
const pairMod = require('./pair');
const copieOrdre = require('./copie-ordre');
db.exec(`CREATE TABLE IF NOT EXISTS pair_ops (id TEXT PRIMARY KEY, json TEXT, seq INTEGER);
  CREATE TABLE IF NOT EXISTS pair_curseurs (appareil TEXT PRIMARY KEY, n INTEGER);
  CREATE TABLE IF NOT EXISTS pair_sortie (n INTEGER PRIMARY KEY, enveloppe TEXT, depose INTEGER DEFAULT 0);`);
const horlogePair = new pairMod.Horloge(() => Date.now());
horlogePair.dernier = +meta('pair_hlc', 0);
function pairOps() { return db.prepare('SELECT json, seq FROM pair_ops').all().map((r) => Object.assign(JSON.parse(r.json), r.seq == null ? {} : { seq: Number(r.seq) })); }
function pairPublier(payload) {
  const n = +meta('pair_n', 0) + 1; setMeta('pair_n', n);
  db.prepare('INSERT INTO pair_sortie(n,enveloppe) VALUES(?,?)').run(n, JSON.stringify(chiffrer(CLE, payload, { id: `pair-mere-${n}`, appareil: 'mere', dir: 'pair', n })));
}
async function pairExpedier() {
  for (const r of db.prepare('SELECT n,enveloppe FROM pair_sortie WHERE depose=0 ORDER BY n').all()) {
    await rel('POST', '/depot', { enveloppe: JSON.parse(r.enveloppe) });
    db.prepare('UPDATE pair_sortie SET depose=1 WHERE n=?').run(r.n);
  }
}
async function pairRelever() {
  const { appareils } = await rel('GET', '/pair/appareils');
  for (const a of appareils.filter((x) => x.uuid !== 'mere')) {
    if (meta('pair_bloque:' + a.uuid)) continue;
    for (;;) {
      const depuis = (db.prepare('SELECT n FROM pair_curseurs WHERE appareil=?').get(a.uuid) || { n: 0 }).n;
      const { env, fin } = await rel('GET', `/releve?dir=pair&appareil=${encodeURIComponent(a.uuid)}&depuis_n=${depuis}&limite=50`);
      if (!env.length) break;
      let attendu = depuis + 1; const nouveaux = [];
      for (const e of env) {
        if (e.n !== attendu) { alerter({ type: 'trou_pair', appareil: a.uuid, attendu, recu: e.n }); setMeta('pair_bloque:' + a.uuid, 'trou'); break; }
        let op; try { op = dechiffrer(CLE, e); } catch (x) { alerter({ type: 'authentification_pair', appareil: a.uuid, n: e.n }); setMeta('pair_bloque:' + a.uuid, 'auth'); break; }
        tx(() => {
          const neuf = db.prepare('INSERT OR IGNORE INTO pair_ops(id,json) VALUES(?,?)').run(op.id, JSON.stringify(op));
          if (neuf.changes) nouveaux.push(op);
          db.prepare('INSERT INTO pair_curseurs(appareil,n) VALUES(?,?) ON CONFLICT(appareil) DO UPDATE SET n=excluded.n').run(a.uuid, e.n);
        });
        horlogePair.recevoir(op.hlc); setMeta('pair_hlc', horlogePair.dernier);
        attendu += 1;
      }
      // le seq qui FAIT FOI : attribué à l'acceptation, dans l'ordre total de la fusion, jamais l'horloge murale
      if (nouveaux.length) {
        const liste = [];
        for (const op of nouveaux.sort(pairMod.comparer)) {
          const seq = +meta('pair_seq', 0) + 1; setMeta('pair_seq', seq);
          db.prepare('UPDATE pair_ops SET seq=? WHERE id=?').run(seq, op.id); liste.push([op.id, seq]);
        }
        pairPublier({ type: 'foi', liste });
      }
      if (fin || attendu === depuis + 1) break;
    }
  }
}

/* PRD relais consultable : la COPIE consolidée de la mère (état fusionné des fiches de famille A, un lot par tour qui a des changements, sens « copie », appareil « mere »). */
db.exec(`CREATE TABLE IF NOT EXISTS copie_sortie (n INTEGER PRIMARY KEY, enveloppe TEXT, depose INTEGER DEFAULT 0);
  CREATE TABLE IF NOT EXISTS copie_etat (cle TEXT PRIMARY KEY, empreinte TEXT);`);
async function pairCopie() {
  const ops = pairOps(); const fiches = pairMod.etat(ops, pairMod.droitsBanc).fiches; const ordres = copieOrdre.ordresDesFiches(ops); const lot = []; const empreintes = [];
  for (const [cle, f] of Object.entries(fiches)) {
    const i = cle.indexOf('/'); const col = cle.slice(0, i);
    if (pairMod.FAMILLES[col] !== 'A') continue;
    const charge = copieOrdre.chargeCopie(cle, f, ordres); const texte = copieOrdre.contenu(charge);
    const deja = db.prepare('SELECT empreinte FROM copie_etat WHERE cle=?').get(cle);
    if (deja && deja.empreinte === texte) continue;
    lot.push(charge); empreintes.push([cle, texte]);
  }
  if (lot.length) {
    tx(() => {
      const n = +meta('copie_n', 0) + 1; setMeta('copie_n', n);
      db.prepare('INSERT INTO copie_sortie(n,enveloppe) VALUES(?,?)').run(n, JSON.stringify(chiffrer(CLE, { lot }, { id: `copie-mere-${n}`, appareil: 'mere', dir: 'copie', n })));
      for (const [cle, texte] of empreintes) db.prepare('INSERT INTO copie_etat(cle,empreinte) VALUES(?,?) ON CONFLICT(cle) DO UPDATE SET empreinte=excluded.empreinte').run(cle, texte);
    });
  }
  for (const r of db.prepare('SELECT n,enveloppe FROM copie_sortie WHERE depose=0 ORDER BY n').all()) {
    await rel('POST', '/depot', { enveloppe: JSON.parse(r.enveloppe) });
    db.prepare('UPDATE copie_sortie SET depose=1 WHERE n=?').run(r.n);
  }
}

function demarrerPont() {
  if (!RELAIS) return;
  const tour = (nom, f, ms) => { let occupe = false; setInterval(async () => { if (occupe) return; occupe = true; try { await f(); } catch (e) { /* relais injoignable : on réessaie */ } occupe = false; }, ms); };
  if (RESTAURER && !+db.prepare('SELECT COUNT(*) AS n FROM operations').get().n) restaurer();
  tour('relever', () => (meta('restauration') === 'en_cours' ? null : relever()), 250);
  tour('diffuser', () => { diffuser(); return expedier(); }, 250);
  tour('repliquer', repliquer, 250);
  tour('pair', async () => { await pairRelever(); await pairExpedier(); }, 250);
  tour('copie', pairCopie, 500);
  tour('battement', async () => {
    await rel('POST', '/mere/battement', {});
    const indicateurs = { patients_actifs: db.prepare("SELECT COUNT(*) AS n FROM fiches WHERE collection='patients' AND archive=0").get().n,
      seq_max: Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s), retard_replication: Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s) - +meta('rep_seq', 0) };
    /* Lot RLS-SYNC : l'état de synchronisation des fileuls (compteurs et horodatages seulement), au plus toutes les 2 s. Illisible : OMIS, le relais dit « non publié ». */
    const fileuls = fileulsPublies(); if (fileuls) indicateurs.fileuls = fileuls;
    await rel('POST', '/mere/indicateurs', { indicateurs });
  }, 300);
}

/* LOT RLS-SYNC : ce que la mère publie de ses fileuls : un poste par ligne, son nom technique, son dernier contact, son retard de journal, ses conflits ouverts, ses demandes d'import
   en attente. JAMAIS un identifiant de patient, un nom ni un libellé : la liste blanche est celle de synchro.js, appliquée une dernière fois par `assainir`. */
const SYNCHRO = require('./synchro');
const INTERVALLE_FILEULS_MS = 2000; let fileulsCache = null; let fileulsLe = 0;
function fileulsPublies() {
  const maintenant = Date.now();
  if (fileulsCache && maintenant - fileulsLe < INTERVALLE_FILEULS_MS) return fileulsCache;
  try {
    const seqMax = Number(db.prepare('SELECT COALESCE(MAX(seq),0) AS s FROM operations').get().s);
    const conflits = Object.fromEntries(db.prepare("SELECT appareil, COUNT(*) AS n FROM conflits WHERE etat='ouvert' GROUP BY appareil").all().map((c) => [c.appareil, Number(c.n)]));
    const demandes = {};
    for (const f of db.prepare("SELECT id, data FROM fiches WHERE collection='demandesImport' AND archive=0").all()) {
      const d = JSON.parse(f.data);
      if (d.statut === 'archive' || d.etat !== 'en_attente') continue;
      const o = db.prepare("SELECT appareil FROM operations WHERE collection='demandesImport' AND fiche=? ORDER BY seq LIMIT 1").get(f.id);
      if (o) demandes[o.appareil] = (demandes[o.appareil] || 0) + 1;
    }
    const brut = db.prepare("SELECT uuid, etiquette, dernier_contact, dernier_seq FROM appareils WHERE etat='actif' AND role<>'mobile' ORDER BY etiquette, uuid").all().map((p) => SYNCHRO.construire({
      etiquette: p.etiquette, uuid: p.uuid, dernierContact: p.dernier_contact == null ? null : Number(p.dernier_contact), dernierSeq: Number(p.dernier_seq || 0), seqMax,
      conflitsOuverts: conflits[p.uuid] || 0, demandesEnAttente: demandes[p.uuid] || 0 }));
    fileulsCache = SYNCHRO.assainir(brut); fileulsLe = maintenant;
    return fileulsCache;
  } catch (e) { return null; }
}

const FICHIERS = require('./fichiers');
const traiterFichiers = FICHIERS_DIR ? FICHIERS.mere(new FICHIERS.Stockage(FICHIERS_DIR), { auth }) : null;
const serveur = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', async () => {
    const u = new URL(req.url, 'http://x');
    /* Lot D5 : les routes de FICHIERS portent des octets, pas du JSON : leur propre lecture du corps. */
    if (u.pathname.startsWith('/fichiers/')) {
      if (!traiterFichiers) { const t = JSON.stringify({ code: 'FICHIERS_NON_ACTIVES', motif: 'cette mère ne tient pas de fichiers numérisés' }); res.writeHead(503, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(t) }); return res.end(t); }
      return traiterFichiers(req, res, Buffer.concat(chunks), u);
    }
    const q = Object.fromEntries(u.searchParams);
    let body = {};
    try { body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {}; } catch (e) { /* corps vide */ }
    const h = routes[req.method + ' ' + u.pathname];
    let status = 200; let out;
    try {
      if (!h) throw new Err(404, 'route_inconnue', 'Route inconnue.');
      out = await h(req, body, q);
    } catch (e) {
      if (e instanceof Err) { status = e.status; out = e.body; } else { status = 500; out = { code: 'erreur_interne', motif: String(e && e.message) }; }
    }
    const txt = JSON.stringify(out);
    res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(txt) });
    res.end(txt);
  });
});
serveur.listen(PORT, '127.0.0.1', () => { demarrerPont(); if (process.send) process.send({ pret: true, port: serveur.address().port }); });
process.on('SIGTERM', () => process.exit(0));
