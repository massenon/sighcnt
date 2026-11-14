'use strict';
/* =============================================================================
 * SIGH-CNT : SAUVEGARDE HORS SITE (lot 5, ADR-0007) : les RÈGLES PURES de référence.
 * Aucune clé, aucun réseau, aucun disque, aucune horloge : des fonctions de leurs arguments. Le relais de référence (`relais.js`), le client de référence
 * (`sauvegarde-hs.js`) et le générateur de vecteurs (`vecteurs-sauvegarde.js`) s'en servent ; le domaine Dart (`packages/domaine/lib/src/sauvegarde/`) les porte,
 * rejouées sur les vecteurs. Une règle écrite ici et ailleurs diverge au premier correctif : c'est pourquoi les vecteurs existent.
 *
 * Refus NOMMÉS (code, motif, geste) : jamais un message muet, jamais « non calculable » rendu pour zéro.
 * ========================================================================== */

const FORMAT = 1;
const TYPES = ['magasin', 'fichiers'];
/* Bornes d'un réglage (valeurs d'attente, à valider par la Direction : section AA). Un réglage hors bornes est REFUSÉ, jamais rogné en silence. */
const BORNES = {
  tailleBloc: [64 * 1024, 4 * 1024 * 1024],
  copies: [2, 60],
  frequenceMinutes: [15, 1440],
  heureControle: [0, 23],
  blocsControles: [0, 200],
};
const DEFAUTS = { tailleBloc: 1024 * 1024, copiesMagasin: 7, copiesFichiers: 14, frequenceMinutes: 60, heureControle: 2, blocsControles: 10 };
/* Les limites du RELAIS (en base chez lui, défauts semés) : le client les lit par `etat` et les respecte avant de déposer. */
const LIMITES_RELAIS = { tailleBlocMax: 2 * 1024 * 1024, tailleMaxCopie: 1024 * 1024 * 1024, quotaOctets: 5 * 1024 * 1024 * 1024, rotationPlancher: 2, rotationPlafond: 60, orphelinsHeures: 72 };

const refus = (code, motif, geste, plus) => Object.assign({ ok: false, code, motif, geste }, plus || {});
const octets = (n) => (n >= 1024 * 1024 * 1024 ? `${(n / 1024 / 1024 / 1024).toFixed(1)} Gio` : n >= 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)} Mio` : n >= 1024 ? `${(n / 1024).toFixed(0)} Kio` : `${n} o`);

/* Le découpage : des plages (début, longueur) de [tailleBloc] octets, la dernière plus courte. Un contenu vide n'a AUCUN bloc (un élément vide est refusé en amont). */
function decouper(longueur, tailleBloc) {
  if (!Number.isInteger(longueur) || longueur < 0) throw new Error('longueur invalide');
  if (!Number.isInteger(tailleBloc) || tailleBloc < 1) throw new Error('taille de bloc invalide');
  const plages = [];
  for (let d = 0; d < longueur; d += tailleBloc) plages.push({ debut: d, longueur: Math.min(tailleBloc, longueur - d) });
  return plages;
}

/* Le surcoût du chiffrement par bloc : nonce 12 + tag 16. */
const SURCOUT_BLOC = 28;
const tailleChiffree = (longueur, tailleBloc) => longueur + decouper(longueur, tailleBloc).length * SURCOUT_BLOC;

/* Le contrôle d'un RÉGLAGE (bornes, activation). `reglage` : { actif, destination, dossier, tailleBloc, copies, frequenceMinutes, heureControle, blocsControles }.
   Activer sans destination, ou une destination « dossier » sans chemin, est REFUSÉ en le nommant. */
function verifierReglage(reglage) {
  const r = reglage || {};
  const dansBornes = (v, [a, b]) => Number.isInteger(v) && v >= a && v <= b;
  if (!['aucune', 'relais', 'dossier'].includes(r.destination)) return refus('DESTINATION_INCONNUE', `la destination « ${r.destination} » n'existe pas`, 'Choisir : aucune, relais ou dossier distant.');
  if (r.actif && r.destination === 'aucune') return refus('DESTINATION_ABSENTE', 'la copie hors site ne peut pas être activée sans destination', 'Choisir le relais ou un dossier distant, puis activer.');
  if (r.destination === 'dossier' && !(typeof r.dossier === 'string' && r.dossier.trim() !== '')) return refus('DOSSIER_ABSENT', 'la destination « dossier distant » n\'a aucun chemin', 'Saisir le chemin complet du dossier monté.');
  if (r.tailleBloc !== undefined && !dansBornes(r.tailleBloc, BORNES.tailleBloc)) return refus('TAILLE_BLOC_HORS_BORNES', `la taille d'un bloc doit être de ${octets(BORNES.tailleBloc[0])} à ${octets(BORNES.tailleBloc[1])}`, 'Choisir une taille dans ces bornes (1 Mio par défaut).');
  if (r.copies !== undefined && !dansBornes(r.copies, BORNES.copies)) return refus('ROTATION_HORS_BORNES', `le nombre de copies gardées doit être de ${BORNES.copies[0]} à ${BORNES.copies[1]}`, 'Choisir un nombre dans ces bornes : le plancher protège la reprise, le plafond protège l\'espace.');
  if (r.frequenceMinutes !== undefined && !dansBornes(r.frequenceMinutes, BORNES.frequenceMinutes)) return refus('FREQUENCE_HORS_BORNES', `la fréquence doit être de ${BORNES.frequenceMinutes[0]} à ${BORNES.frequenceMinutes[1]} minutes`, 'Choisir une fréquence dans ces bornes (60 minutes par défaut).');
  if (r.heureControle !== undefined && !dansBornes(r.heureControle, BORNES.heureControle)) return refus('HEURE_HORS_BORNES', 'l\'heure du contrôle nocturne est un entier de 0 à 23', 'Choisir une heure de nuit (2 par défaut).');
  if (r.blocsControles !== undefined && !dansBornes(r.blocsControles, BORNES.blocsControles)) return refus('BLOCS_CONTROLES_HORS_BORNES', 'le nombre de blocs contrôlés chaque nuit est un entier de 0 à 200', 'Choisir un nombre dans ces bornes (10 par défaut).');
  return null;
}

/* Le contrôle du PLAN d'une copie AVANT tout dépôt : `etat` est ce que le relais dit de lui-même (limites, utilisé, libérable). Un champ absent de `etat` n'est PAS compté
   comme zéro : la limite ne s'applique pas, et le résultat le dit (`incalculable`). */
function verifierPlan({ octetsCopie, etat }) {
  const e = etat || {};
  const l = e.limites || {};
  if (Number.isInteger(l.tailleMaxCopie) && octetsCopie > l.tailleMaxCopie) {
    return refus('SAUVEGARDE_TROP_GROSSE', `la copie pèse ${octets(octetsCopie)} chiffrée, le maximum accepté par la destination est ${octets(l.tailleMaxCopie)}`,
      'Relever la limite par copie du relais (panneau), ou choisir un dossier distant pour ce type de copie.', { octetsCopie, limite: l.tailleMaxCopie });
  }
  if (Number.isInteger(l.quotaOctets) && Number.isInteger(e.utilise)) {
    const libre = l.quotaOctets - e.utilise + (Number.isInteger(e.liberable) ? e.liberable : 0);
    if (octetsCopie > libre) {
      return refus('ESPACE_RELAIS_INSUFFISANT', `la copie demande ${octets(octetsCopie)}, il reste ${octets(Math.max(0, libre))} sur le relais (anciennes copies libérables comprises)`,
        'Relever le quota du relais, réduire le nombre de copies gardées, ou choisir un dossier distant.', { octetsCopie, libre: Math.max(0, libre) });
    }
    return null;
  }
  return null;
}

/* La ROTATION d'un type : parmi les copies COMPLÈTES (la plus récente d'abord : date, puis identifiant), les `garder` premières restent courantes, les suivantes sont à
   ARCHIVER (jamais supprimées). `garder` hors bornes du relais : refus. Une copie qui n'est pas complète n'entre jamais dans le compte. */
function rotation(copies, garder, plancher, plafond) {
  if (!Number.isInteger(garder) || garder < plancher || garder > plafond) {
    return refus('ROTATION_HORS_BORNES', `garder ${garder} copie(s) est hors des bornes du relais (${plancher} à ${plafond})`,
      'Choisir un nombre de copies dans les bornes du relais.', { plancher, plafond });
  }
  const completes = copies.filter((c) => c.etat === 'complete').sort((a, b) => (b.date - a.date) || (a.id < b.id ? 1 : a.id > b.id ? -1 : 0));
  return { ok: true, gardees: completes.slice(0, garder).map((c) => c.id), archiver: completes.slice(garder).map((c) => c.id) };
}

/* L'ORDRE DE PURGE quand l'espace manque : parmi les copies ARCHIVÉES ou ABANDONNÉES, la plus ancienne d'abord. Une copie courante, en cours, ou l'une des `plancher` plus
   récentes copies complètes de son type n'est JAMAIS candidate (double garde : le plancher tient même si le réglage était mal posé). */
function ordrePurge(copies, plancher) {
  const protegees = new Set();
  for (const t of TYPES) {
    // une copie archivée est une complète que la rotation a écartée : on protège les `plancher` plus récentes copies restaurables du type (complètes ou archivées)
    const restaurables = copies.filter((c) => c.type === t && (c.etat === 'complete' || c.etat === 'archivee')).sort((a, b) => (b.date - a.date) || (a.id < b.id ? 1 : -1));
    for (const c of restaurables.slice(0, plancher)) protegees.add(c.id);
  }
  return copies.filter((c) => (c.etat === 'archivee' || c.etat === 'abandonnee') && !protegees.has(c.id)).sort((a, b) => (a.date - b.date) || (a.id < b.id ? -1 : 1)).map((c) => c.id);
}

/* Le MANIFESTE (clair, avant chiffrement) : format, type, éléments (référence, taille, empreinte du clair, blocs). Sans date ni auteur : l'identité d'une copie est celle de
   son CONTENU (un rejeu du même état est le même manifeste, donc la même copie). Les éléments sont triés par référence. */
function manifeste({ type, elements, tailleBloc }) {
  const els = elements.map((e) => ({ ref: e.ref, taille: e.taille, sha256: e.sha256, ...(e.meta === undefined ? {} : { meta: e.meta }), blocs: e.blocs.map((b) => ({ id: b.id, taille: b.taille, clair: b.clair })) }));
  els.sort((a, b) => (a.ref < b.ref ? -1 : a.ref > b.ref ? 1 : 0));
  return { format: FORMAT, type, tailleBloc, total: els.reduce((s, e) => s + e.taille, 0), elements: els };
}

/* Un manifeste lu : forme, cohérence (la somme des blocs en clair égale la taille de l'élément, le total égale la somme). Rend un refus nommé ou null. */
function verifierManifeste(m) {
  if (!m || typeof m !== 'object' || m.format !== FORMAT) return refus('MANIFESTE_ILLISIBLE', 'le manifeste n\'a pas le format attendu', 'Utiliser un logiciel de la même version que celui qui a fait la copie.');
  if (!TYPES.includes(m.type) || !Array.isArray(m.elements)) return refus('MANIFESTE_ILLISIBLE', 'le manifeste est incomplet', 'Choisir une autre copie.');
  let total = 0;
  for (const e of m.elements) {
    if (typeof e.ref !== 'string' || !Number.isInteger(e.taille) || !Array.isArray(e.blocs) || !/^[0-9a-f]{64}$/.test(e.sha256 || '')) return refus('MANIFESTE_ILLISIBLE', 'un élément du manifeste est incomplet', 'Choisir une autre copie.');
    const somme = e.blocs.reduce((s, b) => s + b.clair, 0);
    if (somme !== e.taille) return refus('MANIFESTE_INCOHERENT', `un élément annonce ${e.taille} octets et ses blocs en portent ${somme}`, 'Choisir une autre copie : celle-ci est incohérente.');
    total += e.taille;
  }
  if (total !== m.total) return refus('MANIFESTE_INCOHERENT', `le manifeste annonce ${m.total} octets et ses éléments en portent ${total}`, 'Choisir une autre copie : celle-ci est incohérente.');
  return null;
}

module.exports = { FORMAT, TYPES, BORNES, DEFAUTS, LIMITES_RELAIS, SURCOUT_BLOC, refus, octets, decouper, tailleChiffree, verifierReglage, verifierPlan, rotation, ordrePurge, manifeste, verifierManifeste };
