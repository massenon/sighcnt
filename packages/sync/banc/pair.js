'use strict';
/* =============================================================================
 * SIGH-CNT : LE MODE PAIR (ADR-0006), RÈGLE DE FUSION ENTRE FILEULS
 * -----------------------------------------------------------------------------
 * Quand la mère est éteinte, les fileuls échangent leurs opérations par le relais. Pour que deux appareils qui ont reçu LES MÊMES opérations aboutissent
 * au MÊME état, quel que soit l'ordre d'arrivée, l'état est une FONCTION PURE de l'ensemble des opérations :
 *
 *      etat(ops) = plier(trier(sans doublon(ops)))      ordre total : (hlc, appareil, id)
 *
 * Rien n'est appliqué « au fil de l'eau » avec un effet de bord : c'est ce qui rend la convergence évidente et testable par permutation.
 * Ce module est la RÈGLE MÉTIER (portée ensuite en Dart dans packages/domaine) ; le relais n'en contient aucune.
 *
 * Familles (spec §8) : A fiche descriptive (fusion par champ) · B journal (ajout seul) · C pièce émise (immuable une fois émise)
 *                      D stock (agrégat à invariant, sorties dans la PART de l'appareil) · W flux de travail (validations du rôle habilité).
 * Les droits (RBAC) sont vérifiés à la RÉCEPTION comme à l'émission : `droits(op)` est injecté (la matrice vit dans le domaine).
 * Ce qui est appliqué sans la mère est PROVISOIRE : une fiche touchée par une opération sans `seq` (attribué par la mère) l'est.
 * ========================================================================== */

const FAMILLES = { patients: 'A', rendezvous: 'A', constantes: 'B', notes: 'B', factures: 'C', avoirs: 'C', ecritures: 'C', prescriptions: 'C', stock: 'D', besoins: 'W',
  lots: 'D', mouvements: 'B', produits: 'A', admissions: 'A',
  consultations: 'A', dossiersConsultation: 'A', antecedents: 'A', appels: 'A', observations: 'A', releves: 'B' };

/** Ordre total identique sur tous les appareils. */
function comparer(a, b) {
  if (a.hlc !== b.hlc) return a.hlc < b.hlc ? -1 : 1;
  if (a.appareil !== b.appareil) return a.appareil < b.appareil ? -1 : 1;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/** Horloge logique hybride : toujours strictement supérieure à ce qu'on a vu ET à l'horloge murale ; la dérive est bornée. */
class Horloge {
  constructor(maintenant = () => Date.now(), deriveMax = 2 * 60 * 1000) { this.dernier = 0; this.maintenant = maintenant; this.deriveMax = deriveMax; this.derive = false; }
  emettre() { this.dernier = Math.max(this.dernier + 1, this.maintenant() * 1000); return this.dernier; }
  recevoir(hlc) {
    if (hlc / 1000 - this.maintenant() > this.deriveMax) this.derive = true; // dérive signalée (EF-SYNC-20), jamais ignorée en silence
    this.dernier = Math.max(this.dernier, hlc);
  }
}

const sans = (liste) => { const vu = new Set(); return liste.filter((o) => (vu.has(o.id) ? false : (vu.add(o.id), true))); };
const marque = (etat, op, code, motif) => etat.refusees.push({ id: op.id, appareil: op.appareil, code, motif });
const cle = (o) => `${o.collection}/${o.fiche}`;

/** L'état de tous les appareils qui ont reçu `ops`. `droits(op) -> true | false` (RBAC) ; `seqMere` n'intervient que pour le drapeau provisoire. */
function etat(ops, droits = () => true) {
  const E = { fiches: {}, stock: {}, besoins: {}, conflits: [], tranches: [], refusees: [], provisoire: new Set() };
  for (const op of sans(ops).sort(comparer)) {
    const fam = FAMILLES[op.collection];
    if (!fam) { marque(E, op, 'collection_inconnue', op.collection); continue; }
    if (op.type === 'supprimer') { marque(E, op, 'suppression_interdite', 'Aucune suppression physique (RG-14).'); continue; }
    if (!droits(op)) { marque(E, op, 'droit_refuse', `${op.role || '?'} ne peut pas ${op.type} sur ${op.collection}`); continue; }
    if (op.seq == null) E.provisoire.add(cle(op));

    if (fam === 'D') { stock(E, op); continue; }
    if (fam === 'W') { flux(E, op); continue; }
    const k = cle(op);
    let f = E.fiches[k];

    if (fam === 'B') {
      if (op.type !== 'creer') { marque(E, op, 'journal_immuable', 'Un journal ne se modifie pas.'); continue; }
      if (f) { marque(E, op, 'fiche_existe', 'Ligne déjà présente.'); continue; }
      // RG-03 : toute sortie de stock est rattachée à un justificatif
      if (op.collection === 'mouvements' && op.champs.sens === 'sortie' && !op.champs.justificatif) { marque(E, op, 'justificatif_manquant', 'Toute sortie de stock porte son justificatif (RG-03).'); continue; }
      E.fiches[k] = { data: { ...op.champs }, hlc: Object.fromEntries(Object.keys(op.champs).map((c) => [c, op.hlc])), archive: false };
      continue;
    }
    // A et C
    if (op.type === 'creer') {
      if (f) { marque(E, op, 'fiche_existe', 'Fiche déjà présente.'); continue; }
      // un AVOIR est le seul canal de correction d'une pièce émise : il vise une facture ÉMISE, et le cumul des avoirs ne dépasse jamais la facture
      if (op.collection === 'avoirs' && !avoirValide(E, op)) continue;
      E.fiches[k] = { data: { ...op.champs }, hlc: Object.fromEntries(Object.keys(op.champs).map((c) => [c, op.hlc])), archive: false, emise: false };
      continue;
    }
    if (!f) { marque(E, op, 'fiche_inconnue', k); continue; }
    if (op.type === 'archiver' || op.type === 'restaurer') { f.archive = op.type === 'archiver'; continue; }
    if (fam === 'C' && op.type === 'emettre') { emettre(E, op, f, k); continue; }
    /* TRANCHER (la personne habilitée, ou la mère à son retour) : la valeur choisie remplace celle retenue par l'ordre total et le conflit marqué est levé.
       Un conflit qui naît APRÈS cette décision dans l'ordre total reste marqué : on ne tranche que ce qui a été vu. */
    if (op.type === 'trancher') {
      if (f.archive) { marque(E, op, 'fiche_archivee', 'Restaurer d’abord (RG-14).'); continue; }
      if (fam === 'C' && f.emise) { marque(E, op, 'piece_emise_immuable', 'Une pièce émise ne se réécrit jamais : établir un avoir.'); continue; }
      for (const [champ, val] of Object.entries(op.champs)) {
        f.data[champ] = val; f.hlc[champ] = op.hlc; f.dernier = op.appareil;
        E.conflits = E.conflits.filter((c) => !(c.fiche === k && c.champ === champ));
        E.tranches.push({ fiche: k, champ, valeur: val, par: op.appareil, hlc: op.hlc });
      }
      continue;
    }
    if (op.type === 'modifier') {
      if (f.archive) { marque(E, op, 'fiche_archivee', 'Restaurer d’abord (RG-14).'); continue; }
      if (fam === 'C' && f.emise) { marque(E, op, 'piece_emise_immuable', 'Une pièce émise ne se réécrit jamais : établir un avoir.'); continue; }
      for (const [champ, val] of Object.entries(op.champs)) {
        const courant = f.hlc[champ] || 0;
        const vu = (op.vu && op.vu[champ]) || 0;
        // écriture CONCURRENTE : l'auteur n'avait pas vu la version courante et les valeurs diffèrent -> conflit marqué, la plus récente de l'ordre total l'emporte
        if (courant > vu && JSON.stringify(f.data[champ]) !== JSON.stringify(val)) E.conflits.push({ fiche: k, champ, a: f.data[champ] === undefined ? null : f.data[champ], b: val, appareils: [f.dernier || null, op.appareil] });
        f.data[champ] = val; f.hlc[champ] = op.hlc; f.dernier = op.appareil;
      }
    }
  }
  marquerLits(E);
  E.conflits.sort((x, y) => (x.fiche + x.champ).localeCompare(y.fiche + y.champ));
  return E;
}

/* A (admissions) : un lit ne porte qu'UNE admission active. Deux admissions `en_cours` sur le même lit, créées chacune hors ligne, sont MARQUÉES `litEnConflit` sur les deux :
   aucune n'est refusée ni déplacée (un patient est réellement là), l'établissement transfère l'un d'eux. Calculé sur l'état final, donc indépendant de l'ordre d'arrivée. */
function marquerLits(E) {
  const parLit = {};
  for (const [k, f] of Object.entries(E.fiches)) {
    if (!k.startsWith('admissions/') || f.archive || f.data.statut !== 'en_cours' || !f.data.lit) continue;
    (parLit[f.data.lit] = parLit[f.data.lit] || []).push(f);
  }
  for (const l of Object.values(parLit)) if (l.length > 1) for (const f of l) f.litEnConflit = true;
}

/* C : l'ÉMISSION d'une pièce certifiante. Le numéro, une fois posé, ne se réécrit jamais ; un numéro porté par deux pièces émises est MARQUÉ (`doublon`) sur les deux et
   n'est jamais renuméroté (RG-01, pièce émise intouchable) : la Direction ou le comptable tranche. Une écriture ne s'émet que ÉQUILIBRÉE (RG-10). */
function emettre(E, op, f, k) {
  const numero = op.champs && op.champs.numero !== undefined ? op.champs.numero : null;
  if (f.archive) return marque(E, op, 'fiche_archivee', 'Restaurer d’abord (RG-14).');
  if (f.emise) {
    if (numero !== null && numero !== f.numero) return marque(E, op, 'numero_immuable', 'Le numéro d’une pièce émise ne se réécrit jamais.');
    return;
  }
  if (op.collection === 'ecritures' && !equilibree(f.data.lignes)) return marque(E, op, 'ecriture_desequilibree', 'Débit et crédit doivent s’égaler (RG-10) avant l’émission.');
  f.emise = true;
  if (numero !== null) {
    f.numero = numero;
    for (const [autre, g] of Object.entries(E.fiches)) {
      if (autre !== k && autre.startsWith(op.collection + '/') && g.emise && g.numero === numero) { f.doublon = true; g.doublon = true; }
    }
  }
}
function equilibree(lignes) {
  if (!Array.isArray(lignes) || lignes.length < 2) return false;
  let d = 0, c = 0;
  for (const l of lignes) { d += +l.debit || 0; c += +l.credit || 0; }
  return d > 0 && Math.round(d * 100) === Math.round(c * 100);
}
function avoirValide(E, op) {
  const cibleK = 'factures/' + op.champs.facture;
  const facture = E.fiches[cibleK];
  if (!facture || !facture.emise) { marque(E, op, 'avoir_sans_facture_emise', 'Un avoir vise une facture émise : ' + cibleK); return false; }
  const montant = +op.champs.montant || 0;
  const deja = facture.avoirs || 0;
  if (montant <= 0 || deja + montant > (+facture.data.total || 0)) { marque(E, op, 'avoir_depasse', `Avoirs cumulés ${deja + montant} au-delà de la facture (${facture.data.total}).`); return false; }
  facture.avoirs = deja + montant;
  return true;
}

/* D : ouverture et entrées par un rôle habilité ; la PART d'un appareil est un bail accordé ; une sortie hors part n'est JAMAIS appliquée (RG-03). */
function stock(E, op) {
  const sk = op.collection === 'stock' ? op.fiche : `${op.collection}/${op.fiche}`; // le stock historique garde sa clé nue : les lots ne la partagent pas
  const s = (E.stock[sk] = E.stock[sk] || { qte: 0, ouvert: false, parts: {}, sorties: {} });
  const q = +(op.champs && op.champs.qte) || 0;
  if (op.type === 'creer') { if (s.ouvert) return marque(E, op, 'fiche_existe', 'Stock déjà ouvert.'); s.ouvert = true; s.qte += q; return; }
  if (!s.ouvert) return marque(E, op, 'fiche_inconnue', 'Stock non ouvert : ' + op.fiche);
  if (op.type === 'entree') { s.qte += q; return; }
  if (op.type === 'bail') { s.parts[op.champs.appareil] = (s.parts[op.champs.appareil] || 0) + q; return; }
  if (op.type === 'sortie') {
    const reste = (s.parts[op.appareil] || 0) - (s.sorties[op.appareil] || 0);
    if (q > reste || q > s.qte) return marque(E, op, 'hors_part', `Sortie de ${q} hors de la part de ${op.appareil} (reste ${reste}) : RG-03.`);
    s.sorties[op.appareil] = (s.sorties[op.appareil] || 0) + q; s.qte -= q; return;
  }
  marque(E, op, 'type_invalide', op.type);
}

/* W : soumettre (demandeur), valider ou rejeter (rôle habilité, déjà contrôlé par `droits`) ; une décision sans demande préalable dans l'ordre total est écartée. */
function flux(E, op) {
  const b = (E.besoins[op.fiche] = E.besoins[op.fiche] || { etat: null, historique: [] });
  if (op.type === 'soumettre') { if (b.etat) return marque(E, op, 'deja_soumis', op.fiche); b.etat = 'soumis'; b.historique.push([op.hlc, 'soumis', op.appareil]); return; }
  if (!b.etat) return marque(E, op, 'demande_inconnue', op.fiche);
  if (op.type === 'valider' || op.type === 'rejeter') {
    if (b.etat !== 'soumis') return marque(E, op, 'deja_decide', `${op.fiche} est ${b.etat}`);
    b.etat = op.type === 'valider' ? 'valide' : 'rejete'; b.historique.push([op.hlc, b.etat, op.appareil]); return;
  }
  marque(E, op, 'type_invalide', op.type);
}

/** Journal d'un appareil au relais : rang contigu, idempotence ; un trou est DÉTECTÉ, jamais comblé en silence. */
class JournalRelais {
  constructor() { this.parAppareil = {}; }
  deposer(appareil, n, enveloppe) {
    const l = (this.parAppareil[appareil] = this.parAppareil[appareil] || []);
    if (n <= l.length) return 'deja'; // idempotent
    if (n !== l.length + 1) throw new Error(`trou de rang pour ${appareil} : attendu ${l.length + 1}, reçu ${n}`);
    l.push(enveloppe); return 'ok';
  }
  releve(appareil, depuisN, limite = 100) { return (this.parAppareil[appareil] || []).slice(depuisN, depuisN + limite).map((e, i) => ({ n: depuisN + i + 1, enveloppe: e })); }
  appareils() { return Object.keys(this.parAppareil); }
}

/** Les droits du BANC (la matrice réelle vit dans le domaine : rbac.json). Une opération hors de ces droits est écartée à l'émission ET à la réception. */
const DROITS_BANC = {
  stock: { creer: ['stock', 'da'], entree: ['stock', 'da'], bail: ['stock', 'da'], sortie: ['stock', 'da', 'infirmier', 'pharmacien'] },
  besoins: { soumettre: ['stock', 'infirmier', 'medecin', 'da', 'caissier'], valider: ['da'], rejeter: ['da'] },
  patients: { '*': ['reception', 'infirmier', 'medecin', 'da', 'x'], trancher: ['da', 'mere'] },
  rendezvous: { '*': ['reception', 'infirmier', 'medecin', 'da', 'x'], trancher: ['da', 'mere'] },
  constantes: { '*': ['infirmier', 'medecin', 'x'] },
  notes: { '*': ['infirmier', 'medecin', 'x'] },
  factures: { '*': ['caissier', 'da', 'x'], trancher: ['da', 'mere'] },
  avoirs: { '*': ['comptable', 'da', 'x'], trancher: ['da', 'mere'] },
  ecritures: { '*': ['comptable', 'da', 'x'], trancher: ['da', 'mere'] },
  prescriptions: { '*': ['medecin', 'x'] },
  consultations: { '*': ['medecin', 'da', 'x'], trancher: ['da', 'mere'] },
  dossiersConsultation: { '*': ['medecin', 'x'], trancher: ['da', 'mere'] },
  antecedents: { '*': ['medecin', 'infirmier', 'x'], trancher: ['da', 'mere'] },
  appels: { '*': ['reception', 'da', 'x'], trancher: ['da', 'mere'] },
  observations: { '*': ['infirmier', 'medecin', 'x'], trancher: ['da', 'mere'] },
  releves: { '*': ['infirmier', 'medecin', 'x'] },
  lots: { creer: ['stock', 'da'], entree: ['stock', 'da'], bail: ['stock', 'da'], sortie: ['stock', 'da', 'infirmier', 'pharmacien'] },
  mouvements: { '*': ['stock', 'da', 'infirmier', 'pharmacien', 'x'] },
  produits: { '*': ['stock', 'da', 'x'], trancher: ['da', 'mere'] },
  admissions: { '*': ['reception', 'infirmier', 'medecin', 'da', 'x'], trancher: ['da', 'mere'] },
};
function droitsBanc(op) {
  const c = DROITS_BANC[op.collection]; if (!c) return false;
  const roles = c[op.type] || c['*']; return !!roles && roles.includes(op.role);
}

module.exports = { FAMILLES, comparer, Horloge, etat, JournalRelais, droitsBanc, DROITS_BANC };
