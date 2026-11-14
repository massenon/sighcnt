'use strict';
/* =============================================================================
 * SIGH-CNT : LES PARAMÈTRES VERSIONNÉS PAR DATE (lot L0, décision de la Direction du 09/11/2026)
 * -----------------------------------------------------------------------------
 * Règle de la Direction : tout ce qui est paramétrable se règle au poste, est ENREGISTRÉ EN BASE avec un DÉFAUT semé, et se VERSIONNE PAR DATE quand des pièces ont
 * été émises sous l'ancienne valeur. Ce module est la RÈGLE (référence exécutable, portée en Dart dans packages/domaine/lib/src/parametres/) ; le relais n'en contient aucune.
 *
 * Modèle : une VERSION = une fiche immuable de la collection `parametres` (famille R : la mère seule écrit). Une correction ne réécrit jamais une fiche : elle ajoute une
 * version. Champs : cle, famille, type, choix, valeur, defaut, dateEffet (ISO AAAA-MM-JJ, ou null pour la version 0 semée = « depuis toujours »), version (entier croissant
 * par clé), auteur, creeLe, motif, sensible, mobile, source.
 *
 * Résolution à la date D : parmi les versions de la clé dont dateEffet <= D (null = depuis toujours), celle qui porte la plus grande (dateEffet, version) ; sinon le défaut.
 * Un paramètre ne se réécrit JAMAIS sous une pièce émise : une nouvelle version dont la date d'effet est antérieure ou égale à la dernière date où une pièce a utilisé la
 * clé est REFUSÉE, nommée, avec son geste (`parametre_deja_utilise`).
 * Les USAGES sont une collection de famille B (`usagesParametres`, ajout seul) : {cle, date, piece}.
 * ========================================================================== */

/* Familles que RG-13 ferme au téléphone (financier, RH, fiscal, sécurité, secrets). Seconde barrière : un paramètre ne va à un mobile que si sa définition le DÉCLARE (`mobile: true`)
   ET que sa famille n'est pas ici ET qu'il n'est pas `sensible`. Liste prudentielle à valider par la Direction (aucun document ne la fixe). */
const FAMILLES_JAMAIS_MOBILE = ['paie', 'rh', 'fiscal', 'bareme_aib', 'comptabilite', 'mecef', 'securite', 'relais', 'courriel', 'sms', 'ocr', 'horssite'];
const TYPES = ['booleen', 'texte', 'choix', 'entier', 'nombre'];
const ISO = /^\d{4}-\d{2}-\d{2}$/;

const refus = (code, motif, geste) => ({ ok: false, code, motif, geste });
function dateValide(s) {
  if (typeof s !== 'string' || !ISO.test(s)) return false;
  const d = new Date(s + 'T00:00:00Z');
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}
function valeurValide(type, valeur, choix) {
  if (type === 'booleen') return typeof valeur === 'boolean';
  if (type === 'texte') return typeof valeur === 'string';
  if (type === 'choix') return Array.isArray(choix) && choix.includes(valeur);
  if (type === 'entier') return Number.isInteger(valeur);
  if (type === 'nombre') return typeof valeur === 'number' && Number.isFinite(valeur);
  return false;
}
/** Un paramètre part-il vers un téléphone ? Seule la liste blanche (`mobile: true` déclaré, famille non réservée, non sensible) répond oui. */
function autoriseMobile(champs) {
  return !!champs && champs.mobile === true && champs.sensible !== true && !FAMILLES_JAMAIS_MOBILE.includes(champs.famille);
}
const idVersion = (cle, dateEffet, version) => `${cle}@${dateEffet === null ? 'defaut' : dateEffet}@${version}`;
const cle = (v) => (v.dateEffet === null || v.dateEffet === undefined ? '' : v.dateEffet);
const plusRecente = (a, b) => (cle(a) !== cle(b) ? (cle(a) > cle(b) ? a : b) : (a.version >= b.version ? a : b));

/** Valeur en vigueur à `date` (AAAA-MM-JJ). `definition` (facultative) porte le défaut quand aucune version n'existe. */
function resoudre(nom, versions, date, definition) {
  if (!dateValide(date)) return refus('date_invalide', `Date « ${date} » illisible : attendu AAAA-MM-JJ.`, 'Fournir la date de la pièce au format AAAA-MM-JJ');
  const vs = (versions || []).filter((v) => v.cle === nom && (v.dateEffet === null || v.dateEffet === undefined || v.dateEffet <= date));
  if (vs.length) { const v = vs.reduce(plusRecente); return { ok: true, valeur: v.valeur, origine: 'version', version: v.version, dateEffet: v.dateEffet === undefined ? null : v.dateEffet }; }
  if (definition && definition.cle === nom) return { ok: true, valeur: definition.defaut, origine: 'defaut', version: 0, dateEffet: null };
  const autres = (versions || []).filter((v) => v.cle === nom);
  if (autres.length) return refus('aucune_version_en_vigueur', `« ${nom} » n'avait aucune valeur en vigueur au ${date} (première version au ${autres.map((v) => v.dateEffet).filter(Boolean).sort()[0]}).`, 'Déclarer un défaut ou choisir une date postérieure');
  return refus('parametre_inconnu', `Paramètre « ${nom} » inconnu : ni définition ni version.`, 'Déclarer le paramètre dans le registre des paramètres');
}

const dernierUsage = (usages, nom) => (usages || []).filter((u) => u.cle === nom && dateValide(u.date)).map((u) => u.date).sort().pop() || null;

/** Contrôle d'une fiche de version, à l'ÉMISSION (poste) comme à la RÉCEPTION (mère) : même fonction, mêmes refus. Rend { ok: true } ou un refus nommé. */
function validerFiche(c, existantes, usages) {
  for (const k of ['cle', 'famille', 'type', 'auteur']) if (typeof c[k] !== 'string' || !c[k].trim()) return refus(k === 'auteur' ? 'auteur_manquant' : 'champ_manquant', `Le champ « ${k} » est obligatoire${k === 'auteur' ? ' (RG-12 : aucune action anonyme)' : ''}.`, 'Renseigner le champ');
  if (!TYPES.includes(c.type)) return refus('type_inconnu', `Type « ${c.type} » inconnu.`, 'Choisir : ' + TYPES.join(', '));
  if (!valeurValide(c.type, c.valeur, c.choix)) return refus('valeur_invalide', `La valeur de « ${c.cle} » n'est pas de type ${c.type}${c.type === 'choix' ? ' (' + (c.choix || []).join(' / ') + ')' : ''}.`, 'Saisir une valeur du bon type');
  if (c.defaut !== undefined && !valeurValide(c.type, c.defaut, c.choix)) return refus('defaut_invalide', `Le défaut de « ${c.cle} » n'est pas de type ${c.type}.`, 'Corriger la définition du paramètre');
  if (!Number.isInteger(c.version) || c.version < 0) return refus('version_invalide', 'Le numéro de version est un entier positif ou nul.', 'Laisser le poste numéroter');
  const propres = (existantes || []).filter((v) => v.cle === c.cle);
  if (c.dateEffet === null) {
    if (c.version !== 0) return refus('date_effet_manquante', 'Une nouvelle version porte une date d\'effet : seule la version 0 (le défaut semé) en est dépourvue.', 'Fixer une date d\'effet');
  } else {
    if (!dateValide(c.dateEffet)) return refus('date_invalide', `Date d'effet « ${c.dateEffet} » illisible : attendu AAAA-MM-JJ.`, 'Saisir la date d\'effet');
    if (c.version === 0) return refus('version_invalide', 'La version 0 est réservée au défaut semé.', 'Laisser le poste numéroter');
    const u = dernierUsage(usages, c.cle);
    if (u !== null && c.dateEffet <= u) return refus('parametre_deja_utilise', `La valeur de « ${c.cle} » a déjà servi à une pièce du ${u} : une version effective au ${c.dateEffet} la réécrirait.`, `Fixer une date d'effet postérieure au ${u}`);
    /* Une seule fiche par (clé, version). L'ORDRE d'arrivée ne compte pas : le poste publie du plus récent au plus ancien (le magasin insère en tête), la mère doit
       accepter v2 puis v1. Seul un NUMÉRO DÉJÀ PRIS par une autre fiche est refusé (deux postes qui auraient numéroté de leur côté). */
    if (propres.some((v) => v.version === c.version)) return refus('version_deja_prise', `La version ${c.version} de « ${c.cle} » existe déjà.`, 'Rafraîchir le poste puis recommencer');
  }
  if (c.mobile === true && (c.sensible === true || FAMILLES_JAMAIS_MOBILE.includes(c.famille))) return refus('mobile_interdit', `« ${c.cle} » ne peut pas aller sur un téléphone : ${c.sensible === true ? 'paramètre sensible' : 'famille « ' + c.famille + ' » réservée'} (RG-13).`, 'Retirer l\'envoi au téléphone de la définition');
  return { ok: true };
}

/** Le geste de l'administrateur : proposer une nouvelle valeur pour une définition, avec une date d'effet. Rend { ok: true, fiche } ou un refus nommé. */
function proposer({ definition, versions, usages, valeur, dateEffet, auteur, creeLe, motif }) {
  if (!definition) return refus('parametre_inconnu', 'Aucune définition pour ce paramètre.', 'Déclarer le paramètre dans le registre des paramètres');
  const propres = (versions || []).filter((v) => v.cle === definition.cle);
  const version = propres.reduce((m, v) => Math.max(m, v.version), 0) + 1;
  const fiche = { cle: definition.cle, famille: definition.famille, type: definition.type, ...(definition.choix ? { choix: definition.choix } : {}), valeur, defaut: definition.defaut,
    dateEffet: dateEffet === undefined ? null : dateEffet, version, auteur: auteur || '', creeLe: creeLe || null, motif: motif || null, sensible: !!definition.sensible, mobile: !!definition.mobile, source: definition.source || null };
  const r = validerFiche(fiche, versions, usages);
  if (!r.ok) return r;
  return { ok: true, id: idVersion(fiche.cle, fiche.dateEffet, fiche.version), fiche };
}

/** La version 0 : le défaut SEMÉ, identique sur tous les postes (aucune date ni auteur variables), de sorte que deux semis indépendants ne divergent pas. */
function semer(definition) {
  const fiche = { cle: definition.cle, famille: definition.famille, type: definition.type, ...(definition.choix ? { choix: definition.choix } : {}), valeur: definition.defaut, defaut: definition.defaut,
    dateEffet: null, version: 0, auteur: 'semis', creeLe: null, motif: 'Défaut semé', sensible: !!definition.sensible, mobile: !!definition.mobile, source: definition.source || null };
  return { id: idVersion(fiche.cle, null, 0), fiche };
}

module.exports = { FAMILLES_JAMAIS_MOBILE, TYPES, dateValide, valeurValide, autoriseMobile, idVersion, resoudre, validerFiche, proposer, semer, dernierUsage };
