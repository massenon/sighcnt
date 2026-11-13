'use strict';
/* =============================================================================
 * LOT RLS-SYNC : la liste BLANCHE des indicateurs de synchronisation (banc, référence Node).
 * Même règle que packages/domaine/lib/src/mere/synchro_fileuls.dart et que le relais Laravel (apps/web, App\Relais\Synchro\ListeBlanche),
 * éprouvée sur les MÊMES vecteurs : packages/domaine/test/vecteurs/synchro_fileuls.json (banc/synchro.test.js).
 *
 * La mère publie, dans ses indicateurs de battement, un tableau `fileuls` de COMPTEURS ET D'HORODATAGES (décision de la Direction du 13/11/2026) : jamais un identifiant de patient, un nom,
 * un libellé de pièce ni un motif. Le seul texte permis est le nom technique du poste (l'étiquette de l'appairage). La mère OMET ce qui sort de la liste ; le relais REFUSE en nommant.
 * ========================================================================== */
const MAX = 200;
const CLES = ['poste', 'dernierContact', 'retardJournal', 'conflitsOuverts', 'demandesImportEnAttente'];
const NULLABLES = ['dernierContact', 'retardJournal'];
const POSTE = /^[A-Za-z0-9À-ÿ][A-Za-z0-9À-ÿ _.:-]{0,39}$/;
const CLE_SURE = /^[a-z][A-Za-z0-9_]{0,39}$/;
const entier = (v) => typeof v === 'number' && Number.isInteger(v) && v >= 0;
const objet = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/** Rend `null` si la partie « synchronisation » d'un envoi d'indicateurs est permise, sinon le premier refus { code, motif, geste, chemin }. */
function valider(indicateurs) {
  const ind = objet(indicateurs) ? indicateurs : {};
  if ('protocole' in ind) {
    const p = ind.protocole;
    if (!(Number.isInteger(p) && p >= 1 && p <= 9999)) return { code: 'indicateur_valeur_invalide', motif: 'La version du protocole est un entier de 1 à 9999.', geste: 'Publier un entier, ou ne rien publier.', chemin: 'protocole' };
  }
  if (!('fileuls' in ind)) return null;
  const liste = ind.fileuls;
  if (!Array.isArray(liste) || liste.length > MAX) return { code: 'indicateur_forme_invalide', motif: `fileuls doit être une liste de ${MAX} éléments au plus.`, geste: "Publier un tableau d'objets de cinq clés permises.", chemin: 'fileuls' };
  for (let i = 0; i < liste.length; i++) {
    const f = liste[i];
    if (!objet(f)) return { code: 'indicateur_forme_invalide', motif: 'Chaque élément de fileuls doit être un objet.', geste: 'Publier un objet par fileul.', chemin: `fileuls[${i}]` };
    for (const cle of Object.keys(f)) {
      if (!CLES.includes(cle)) {
        const nom = CLE_SURE.test(cle) ? cle : '(cle non conforme)';
        return { code: 'indicateur_cle_inconnue', motif: `La clé « ${nom === '(cle non conforme)' ? 'non conforme' : nom} » n'est pas permise : seuls un nom de poste, des compteurs et des horodatages sont publiés.`,
          geste: `Retirer la clé ; les clés permises sont ${CLES.join(', ')}.`, chemin: `fileuls[${i}].${nom}` };
      }
    }
    if (typeof f.poste !== 'string' || !POSTE.test(f.poste)) return { code: 'indicateur_valeur_invalide', motif: "Le nom du poste est absent ou n'est pas un nom technique (40 caractères, lettres, chiffres, espace, point, deux-points, tiret).", geste: "Publier l'étiquette de l'appairage du poste.", chemin: `fileuls[${i}].poste` };
    for (const cle of CLES.slice(1)) {
      if (!(cle in f)) continue;
      const v = f[cle];
      if (v === null && NULLABLES.includes(cle)) continue;
      if (!entier(v)) return { code: 'indicateur_valeur_invalide', motif: `La valeur de ${cle} doit être un entier positif ou nul${NULLABLES.includes(cle) ? " (ou null quand elle n'est pas calculable)" : ''}.`, geste: 'Publier un compteur numérique.', chemin: `fileuls[${i}].${cle}` };
    }
  }
  return null;
}

/** Le nom technique publié : l'étiquette rognée et tronquée à 40 caractères ; à défaut, le début de l'identifiant d'appareil. */
function nomPoste(etiquette, uuid) {
  let e = String(etiquette == null ? '' : etiquette).trim();
  if (e.length > 40) e = e.slice(0, 40).trimEnd();
  if (e && POSTE.test(e)) return e;
  const repli = `Poste ${String(uuid).slice(0, 8)}`;
  return POSTE.test(repli) ? repli : 'Poste inconnu';
}

/** Ce que la mère publie d'un fileul : compteurs et horodatages. Jamais vu : contact et retard null (un retard n'est pas calculable sans curseur connu, et n'est pas zéro). */
function construire({ etiquette, uuid, dernierContact, dernierSeq, seqMax, conflitsOuverts, demandesEnAttente }) {
  return {
    poste: nomPoste(etiquette, uuid),
    dernierContact: dernierContact == null ? null : dernierContact,
    retardJournal: dernierContact == null ? null : Math.max(0, seqMax - dernierSeq),
    conflitsOuverts, demandesImportEnAttente: demandesEnAttente,
  };
}

/** Dernière barrière côté mère : clé hors liste et valeur invalide OMISES, fileul sans nom technique écarté, 200 au plus. */
function assainir(brut) {
  if (!Array.isArray(brut)) return [];
  const out = [];
  for (const f of brut) {
    if (out.length >= MAX) break;
    if (!objet(f) || typeof f.poste !== 'string' || !POSTE.test(f.poste)) continue;
    const propre = { poste: f.poste };
    for (const cle of CLES.slice(1)) {
      if (!(cle in f)) continue;
      const v = f[cle];
      if (v === null && NULLABLES.includes(cle)) propre[cle] = null;
      else if (entier(v)) propre[cle] = v;
    }
    out.push(propre);
  }
  return out;
}

module.exports = { MAX, CLES, POSTE, valider, nomPoste, construire, assainir };
