/* =============================================================================
 * SIGH-CNT : la LECTURE OCR des scans, PRÉPARÉE (lot OCR-prep) : aucun moteur choisi, aucun moteur livré, aucune qualité promise
 * -----------------------------------------------------------------------------
 * Décision de la Direction (PRD DOCS, Q7) : OCR local en phase 2, APRÈS un essai sur trois vrais scans de la clinique. Ce module est tout ce qui ne dépend pas du moteur : l'interface qu'un moteur
 * remplira, les ÉTATS d'indexation, la FILE de traitement, le marquage « lu par machine, à vérifier », le réglage et la relance. Par défaut AUCUN moteur n'est branché, et l'état le dit
 * exactement : « aucun moteur d'OCR installé sur ce poste ». Jamais un échec muet, jamais « indexé » sans texte lu.
 *
 * LE CONTRAT D'UN MOTEUR (injectable, `SIGH.ocr.enregistrerMoteur`) :
 *   { id, version, langues: ['fra'], formats: ['png', 'jpeg', 'webp'], lire(entree) }   avec entree = { octets (Uint8Array d'une IMAGE), mime, format, langue, page }
 *   lire() rend une promesse { texte, mots: [{ mot, confiance? }], langue } ou la rejette avec { code, motif?, geste? } (MOTEUR_ABSENT, LANGUE_ABSENTE, IMAGE_ILLISIBLE, DELAI_DEPASSE...).
 *   Un PDF sans couche texte exige en plus un rendeur de pages (`SIGH.ocr.rendeur`, absent par défaut) : sans lui le refus est nommé (RENDU_PAGES_ABSENT).
 *
 * TROIS RÈGLES QUI NE SE DEVINENT PAS :
 *   - la couche texte NATIVE d'un PDF prime TOUJOURS sur l'OCR : un fichier qui en porte une n'entre jamais dans la file et son texte lu ne remplace jamais le natif ;
 *   - une lecture ne se RÉÉCRIT jamais : une relance ou un autre moteur AJOUTE une version datée (collection `lecturesOcr`, garde du magasin), l'ancienne reste lisible. Son identifiant est
 *     DÉTERMINISTE (empreinte du fichier, moteur, version du moteur, langue, texte normalisé) : deux postes qui lisent le même scan avec le même moteur ne font qu'une version ;
 *   - la file est UNE par empreinte (l'état de lecture vit sur la fiche du registre `fichiers`, qui est une fiche par empreinte) : deux dépôts du même scan ne font jamais deux files.
 *
 * LOT C (réponses de la Direction du 13/11/2026) : la CORRECTION MANUELLE du texte lu, par un agent habilité (geste réservé `corriger_texte_ocr`), SIGNÉE et JOURNALISÉE. Elle s'AJOUTE comme une
 * version de `lecturesOcr` (`texteSource: 'correction'`, signataire, date, version dont elle part `corrigeDe`, corrections qu'elle remplace `remplace`) ; la lecture machine reste lisible et intacte.
 *   - le TEXTE COURANT (recherche, affichage) est la correction signée la plus récente non remplacée ; SANS correction, la lecture machine la plus récente. Une relance de la lecture AJOUTE une version
 *     machine, elle ne détruit JAMAIS une correction signée : celle-ci reste le texte courant tant qu'un agent n'a pas décidé autrement, et il décide en SIGNANT une nouvelle correction (qui peut
 *     partir de la nouvelle lecture machine). Une lecture machine ne vaut pas la signature d'un agent : l'ordre des dates ne décide pas à sa place ;
 *   - deux corrections concurrentes de la même version (deux postes) ne s'écrasent pas : DEUX versions, le conflit est NOMMÉ et visible, le texte courant est la plus récente des deux (ordre que tous
 *     les postes retrouvent) en le disant, et une correction signée ultérieure remplace les deux ;
 *   - une correction de même contenu sur la même version est la MÊME version (identifiant déterministe) : le rejeu et le second poste ne la doublent pas ;
 *   - le journal (RG-12) ne porte que des identifiants et des comptes : la trace entière est la version immuable.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, S = global.SIGH.store, D = global.SIGH.data, U = global.SIGH.ui;
  var el = C.el;

  var RAISON_SANS_MOTEUR = 'aucun moteur d’OCR installé sur ce poste';
  var DELAI_DEFAUT_MS = 120000;
  var ESSAIS_MAX = 3;
  var BRUT_MAX = 20000;
  var MOTS_MAX = 4000;
  var ROLES_REGLAGE = ['admin', 'da'];
  var LANGUE_DEFAUT = 'fra';

  /** Les codes de refus nommés (le même vocabulaire au domaine Dart). */
  var CODES = {
    MOTEUR_ABSENT: 'MOTEUR_ABSENT', LANGUE_ABSENTE: 'LANGUE_ABSENTE', IMAGE_ILLISIBLE: 'IMAGE_ILLISIBLE', DELAI_DEPASSE: 'DELAI_DEPASSE', FORMAT_NON_LU: 'FORMAT_NON_LU',
    RENDU_PAGES_ABSENT: 'RENDU_PAGES_ABSENT', AUCUN_TEXTE: 'AUCUN_TEXTE', OCR_DESACTIVE: 'OCR_DESACTIVE', MOTEUR_EN_ECHEC: 'MOTEUR_EN_ECHEC', ESSAIS_EPUISES: 'ESSAIS_EPUISES',
    REGLAGE_RESERVE: 'REGLAGE_RESERVE', MOTIF_REQUIS: 'MOTIF_REQUIS', TEXTE_NATIF: 'TEXTE_NATIF', DROIT_REFUSE: 'DROIT_REFUSE',
    CORRECTION_RESERVEE: 'CORRECTION_RESERVEE', CORRECTION_TEXTE_VIDE: 'CORRECTION_TEXTE_VIDE', CORRECTION_SANS_BASE: 'CORRECTION_SANS_BASE', CORRECTION_IDENTIQUE: 'CORRECTION_IDENTIQUE',
  };
  var GESTES = {
    MOTEUR_ABSENT: 'Installer un moteur d’OCR sur ce poste, puis le choisir au réglage de la lecture des scans.',
    LANGUE_ABSENTE: 'Choisir une langue que le moteur sait lire, ou installer ses données de langue.',
    IMAGE_ILLISIBLE: 'Numériser de nouveau le scan, à plus forte résolution.',
    DELAI_DEPASSE: 'Relancer la lecture ; si elle se répète, numériser en résolution plus basse.',
    FORMAT_NON_LU: 'Déposer le scan en image (PNG, JPEG) ou brancher un moteur qui lit ce format.',
    RENDU_PAGES_ABSENT: 'Brancher un rendeur de pages PDF, ou déposer le scan en image.',
    AUCUN_TEXTE: 'Vérifier le scan ; la page est vierge ou trop pâle pour être lue.',
    OCR_DESACTIVE: 'Activer la lecture des scans au réglage (administrateur ou Directrice Administrative).',
    MOTEUR_EN_ECHEC: 'Relancer la lecture ; si elle se répète, le moteur est à vérifier.',
    ESSAIS_EPUISES: 'Relancer la lecture à la main une fois la cause levée.',
    REGLAGE_RESERVE: 'Demander le réglage à l’administrateur ou à la Directrice Administrative.',
    MOTIF_REQUIS: 'Saisir le motif du réglage.',
    TEXTE_NATIF: 'Ce fichier porte déjà une couche texte : elle prime, rien à lire.',
    DROIT_REFUSE: 'Demander ce droit à l’administrateur (« Rôles & permissions »).',
    CORRECTION_RESERVEE: 'Demander le droit « Corriger le texte lu par machine » à l’administrateur (« Rôles & permissions »), ou faire corriger la pièce par un agent habilité.',
    CORRECTION_TEXTE_VIDE: 'Saisir le texte corrigé : une correction ne peut pas être vide.',
    CORRECTION_SANS_BASE: 'Corriger à partir d’une lecture de ce scan : aucune lecture n’existe encore (lancer la lecture, ou saisir la pièce à la main hors de ce texte).',
    CORRECTION_IDENTIQUE: 'Modifier le texte avant d’enregistrer : il est identique à celui de la version dont la correction part.',
  };
  function refus(code, motif, geste) { return { ok: false, code: code, motif: motif, geste: geste || GESTES[code] || '' }; }

  /* ==========================================================================
   * 1. MOTEURS : injectables, AUCUN par défaut
   * ======================================================================== */
  var moteurs = {};
  var rendeur = null;
  function enregistrerMoteur(m) {
    if (!m || !m.id || typeof m.lire !== 'function') throw new Error('Un moteur d’OCR porte un identifiant et une fonction lire().');
    moteurs[m.id] = { id: m.id, version: m.version || '', langues: m.langues || [LANGUE_DEFAUT], formats: m.formats || ['png', 'jpeg'], lire: m.lire, libelle: m.libelle || m.id };
    return moteurs[m.id];
  }
  function retirerMoteur(id) { if (id) delete moteurs[id]; else moteurs = {}; }
  function moteurInstalle() { return Object.keys(moteurs).length > 0; }
  function listeMoteurs() { return Object.keys(moteurs).map(function (k) { return moteurs[k]; }); }
  function poserRendeur(r) { rendeur = r || null; }

  /* ==========================================================================
   * 2. RÉGLAGE : activer ou non, moteur choisi, langue, délai ; en base ; administrateur et DAF ; DÉSACTIVÉ par défaut (à valider)
   * Lot C : c'est un réglage de CLINIQUE (la maquette n'a qu'une clinique, donc un seul exemplaire, en base du serveur) ; à la cible il est posé à le poste mère, versionné par date, et reçu des
   * fileuls ; chaque poste ne garde en propre que ce qu'il a d'INSTALLÉ (le moteur disponible ou non). Il ne va jamais vers un téléphone.
   * ======================================================================== */
  function reglage() {
    var r = S.reglage('ocr', null) || {};
    return { actif: r.actif === true, moteur: r.moteur || null, langue: r.langue || LANGUE_DEFAUT, delaiMs: r.delaiMs > 0 ? r.delaiMs : DELAI_DEFAUT_MS,
      regleLe: r.regleLe || null, reglePar: r.reglePar || null, regle: !!(S.reglage('ocr', null)) };
  }
  function peutRegler() { var s = S.session() || {}; return ROLES_REGLAGE.indexOf(s.role) >= 0; }
  function moteurActif() {
    var r = reglage();
    return r.moteur && moteurs[r.moteur] ? moteurs[r.moteur] : null;
  }
  /** La lecture est-elle possible MAINTENANT sur ce poste : activée, moteur choisi et installé ? */
  function pret() { return reglage().actif && !!moteurActif(); }

  /** Pose le réglage. Réservé à l'administrateur et à la DAF, motivé ; activer sans moteur installé est REFUSÉ en le nommant. */
  function definirReglage(v, motif) {
    if (!peutRegler()) return refus(CODES.REGLAGE_RESERVE, 'la lecture des scans (OCR) se règle par l’administrateur ou la Directrice Administrative');
    if (!String(motif || '').trim()) return refus(CODES.MOTIF_REQUIS, 'un réglage de la lecture des scans se motive');
    var avant = reglage();
    var actif = v.actif === true, id = v.moteur || null, langue = v.langue || LANGUE_DEFAUT;
    if (actif) {
      if (!id || !moteurs[id]) return refus(CODES.MOTEUR_ABSENT, id ? 'le moteur « ' + id + ' » n’est pas installé sur ce poste' : RAISON_SANS_MOTEUR + ' : il n’y a rien à activer');
      if (moteurs[id].langues.indexOf(langue) < 0) return refus(CODES.LANGUE_ABSENTE, 'le moteur « ' + id + ' » ne lit pas la langue « ' + langue + ' » (langues : ' + moteurs[id].langues.join(', ') + ')');
    }
    var nouveau = { actif: actif, moteur: id, langue: langue, delaiMs: v.delaiMs > 0 ? v.delaiMs : avant.delaiMs, regleLe: new Date().toISOString(), reglePar: S.currentUser() };
    S.log('Réglage de la lecture OCR des scans', 'M14', 'reglage', 'ocr', { actif: avant.actif, moteur: avant.moteur, langue: avant.langue, delaiMs: avant.delaiMs }, { actif: actif, moteur: id, langue: langue, delaiMs: nouveau.delaiMs, motif: String(motif).slice(0, 40) });
    S.setReglage('ocr', nouveau);
    if (actif) { balayer(); demarrer(); }
    return { ok: true, avant: avant, reglage: reglage() };
  }

  /* ==========================================================================
   * 3. DONNÉES : le registre par empreinte porte la FILE (`ocr`), la collection `lecturesOcr` porte les VERSIONS
   * ======================================================================== */
  function registre() { return S.collection('fichiers', { module: 'M13', entite: 'fichier', prefix: 'FIC' }); }
  function lectures() { return S.collection('lecturesOcr', { module: 'M13', entite: 'lecture OCR', prefix: 'OCR' }); }
  function idRegistre(sha) { return 'FIC-' + String(sha).slice(0, 16); }
  function fiche(sha) { return registre().get(idRegistre(sha)); }

  /** Les mots d'un texte lu : normalisés (sans accent, minuscules), distincts, de deux lettres au moins, dans l'ordre de première apparition, séparés par une espace. */
  function motsNormalises(texte) {
    var vus = {}, out = [];
    String(texte || '').split(/[^\p{L}\p{N}]+/u).forEach(function (m) { var n = C.norm(m); if (n.length >= 2 && !vus[n]) { vus[n] = true; out.push(n); } });
    return out;
  }
  function utf8(t) { return new global.TextEncoder().encode(t); }
  function sha256Texte(t) { return global.SIGH.fichiers.sha256Octets(utf8(t)); }
  /** L'identifiant d'une lecture : DÉTERMINISTE, donc idempotent d'un poste à l'autre. */
  function idLecture(sha, moteur, version, langue, motsNorm) {
    return 'OCR-' + String(sha).slice(0, 16) + '-' + sha256Texte(moteur + '|' + version + '|' + langue + '|' + motsNorm).slice(0, 12);
  }

  /** Les versions lues d'une empreinte, de la plus ancienne à la plus récente (date de lecture, puis identifiant : un ordre que tous les postes retrouvent). */
  function versionsDe(sha) {
    return lectures().all().filter(function (x) { return x.sha256 === sha; }).sort(function (a, b) {
      return a.ocrLe < b.ocrLe ? -1 : (a.ocrLe > b.ocrLe ? 1 : (a.id < b.id ? -1 : (a.id > b.id ? 1 : 0)));
    });
  }
  function estCorrection(v) { return !!v && v.texteSource === 'correction'; }
  function plusRecente(liste) { return liste.length ? liste[liste.length - 1] : null; }
  /** Les corrections signées que NULLE autre ne remplace (les « têtes »), de la plus ancienne à la plus récente. `versions` : déjà triées par `versionsDe`. */
  function tetesDe(versions) {
    var remplacees = {};
    versions.forEach(function (x) { (x.remplace || []).forEach(function (id) { remplacees[id] = true; }); });
    return versions.filter(function (x) { return estCorrection(x) && !remplacees[x.id]; });
  }
  /** La version COURANTE d'une liste triée : la correction signée la plus récente non remplacée ; SANS correction, la lecture machine la plus récente qui porte du texte. Une lecture machine, même
   * plus récente, ne prend jamais la place d'une correction signée. */
  function courantDe(versions) {
    var t = tetesDe(versions);
    if (t.length) return plusRecente(t);
    return plusRecente(versions.filter(function (x) { return (x.nbMots || 0) > 0 && !estCorrection(x); }));
  }
  function versionCourante(sha) { return courantDe(versionsDe(sha)); }
  /** Les corrections CONCURRENTES (deux têtes ou plus) d'une empreinte, ou []. */
  function conflitDe(sha) { var t = tetesDe(versionsDe(sha)); return t.length > 1 ? t : []; }
  function natifDe(sha) { var f = fiche(sha); return !!(f && f.texteIndexe); }

  /** Le texte OCR (mots normalisés) de la version courante, ou ''. Jamais le natif : c'est `texteDe` de fichiers.js qui fait primer le natif. */
  function texteOcrDe(sha) { var v = versionCourante(sha); return v ? (v.texte || '') : ''; }

  /* ==========================================================================
   * 4. ÉTATS D'INDEXATION : six, jamais confondus
   * ======================================================================== */
  /** `o` : { natif, versions, file: {etat, code?, raison?}|null, moteurInstalle, actif, moteurActif }. Rend { code, court, libelle, raison, source, marque, disponible }. */
  function etatIndexation(o) {
    var vs = (o.versions || []).slice().sort(function (a, b) { return a.ocrLe < b.ocrLe ? -1 : (a.ocrLe > b.ocrLe ? 1 : (a.id < b.id ? -1 : (a.id > b.id ? 1 : 0))); });
    var cur = courantDe(vs), signe = estCorrection(cur), conflit = tetesDe(vs).length > 1;
    var f = o.file || null;
    if (o.natif) return { code: 'indexe', court: 'texte indexé', libelle: 'Texte indexé (couche texte du fichier)', raison: null, source: 'couche_texte', marque: false, disponible: true, conflit: false };
    var source = cur ? (signe ? 'correction' : 'ocr') : null, disponible = !!cur, marque = !!cur && !signe;
    var precedente = signe ? ' (la correction signée reste le texte courant)' : ' (la version précédente reste lisible)';
    if (f && f.etat === 'en_cours') return { code: 'ocr_en_cours', court: 'lecture OCR en cours', libelle: 'Lecture OCR en cours' + (cur ? precedente : ''), raison: null, source: source, marque: marque, disponible: disponible, conflit: conflit };
    if (f && f.etat === 'en_attente') return { code: 'ocr_en_attente', court: 'lecture OCR en attente', libelle: 'Lecture OCR en attente' + (cur ? precedente : ''), raison: null, source: source, marque: marque, disponible: disponible, conflit: conflit };
    if (f && f.etat === 'echec') return { code: 'ocr_echec', court: 'lecture OCR en échec', libelle: 'Lecture OCR en échec : ' + (f.raison || 'cause non renseignée') + (signe ? ' (la correction signée reste le texte courant)' : ''), raison: f.raison || null, source: source, marque: marque, disponible: disponible, conflit: conflit };
    if (signe) {
      var qui = cur.corrigePar || 'auteur inconnu';
      return { code: 'ocr_corrige', court: 'texte corrigé et signé par ' + qui, libelle: 'Texte corrigé et signé par ' + qui + (conflit ? ' (deux corrections concurrentes à départager)' : ''), raison: null, source: 'correction', marque: false, disponible: true, conflit: conflit };
    }
    if (cur) return { code: 'ocr_indexe', court: 'texte lu par machine, à vérifier', libelle: 'Texte lu par machine, à vérifier', raison: null, source: 'ocr', marque: true, disponible: true, conflit: false };
    var raison = !o.moteurInstalle ? RAISON_SANS_MOTEUR
      : (!o.actif ? 'la lecture OCR est désactivée au réglage'
        : (!o.moteurActif ? 'le moteur choisi au réglage n’est pas installé sur ce poste' : 'lecture OCR non encore demandée'));
    return { code: 'non_indexe', court: 'texte non indexé', libelle: 'Texte non indexé : ' + raison, raison: raison, source: null, marque: false, disponible: false, conflit: false };
  }
  function etatDe(fichier) {
    if (!fichier || !fichier.sha256) return null;
    var f = fiche(fichier.sha256);
    var r = reglage();
    return etatIndexation({ natif: !!(fichier.texteIndexe || (f && f.texteIndexe)), versions: versionsDe(fichier.sha256), file: f && f.ocr ? f.ocr : null,
      moteurInstalle: moteurInstalle(), actif: r.actif, moteurActif: !!moteurActif() });
  }
  /** Le petit mot de la ligne d'un registre. */
  function court(fichier) { var e = etatDe(fichier); return e ? e.court : ''; }
  /** Le texte du fichier est-il LISIBLE par la recherche (natif ou lu par machine) ? */
  function aUnTexte(fichier) { var e = etatDe(fichier); return !!(e && e.disponible); }

  /** `PR.peutVoirDocument` : le texte d'un scan de zone 2 est de zone 2. Rend le texte OCR seulement au profil qui lit la zone. */
  function texteLisible(sha, famille, type) {
    if (famille === 'patient' && global.SIGH.parcours && !global.SIGH.parcours.peutVoirDocument(type).autorise) return '';
    return texteOcrDe(sha);
  }

  /* ==========================================================================
   * 5. FILE DE TRAITEMENT : un fichier à la fois, bornée en temps, reprise après arrêt, UNE par empreinte
   * ======================================================================== */
  /** Un scan entre dans la file. Idempotent : un fichier déjà en attente ou en cours n'est pas remis ; un fichier qui porte du texte natif n'y entre jamais ; un fichier déjà lu n'y rentre que sur relance. */
  function demander(sha, ctx) {
    ctx = ctx || {};
    var f = fiche(sha);
    if (!f) return refus('REGISTRE_ABSENT', 'ce fichier n’est pas au registre des empreintes', 'Déposer le scan depuis sa fiche.');
    if (f.texteIndexe) return refus(CODES.TEXTE_NATIF, 'ce fichier porte déjà une couche texte');
    if (!pret()) return refus(!moteurInstalle() ? CODES.MOTEUR_ABSENT : CODES.OCR_DESACTIVE, !moteurInstalle() ? RAISON_SANS_MOTEUR : 'la lecture OCR est désactivée au réglage');
    var relance = ctx.declencheur === 'relance';
    if (f.ocr && (f.ocr.etat === 'en_attente' || f.ocr.etat === 'en_cours')) return { ok: true, deja: true };
    if (!relance && versionCourante(sha)) return { ok: true, deja: true, lu: true };
    if (!relance && f.ocr && f.ocr.etat === 'echec') return { ok: true, deja: true, echec: true };
    registre().update(f.id, { ocr: { etat: 'en_attente', demandeLe: new Date().toISOString(), demandePar: S.currentUser(), declencheur: relance ? 'relance' : 'automatique',
      famille: ctx.famille || (f.ocr && f.ocr.famille) || null, type: ctx.type || (f.ocr && f.ocr.type) || null, essais: 0 } },
    { journal: { action: relance ? 'Relance de la lecture OCR' : 'Lecture OCR demandée', module: 'M13', entite: 'lecture OCR', avant: { empreinte: D.DOCUMENTS.abrege(sha) }, apres: { etat: 'en_attente' } } });
    return { ok: true, demande: true };
  }

  /** Après un dépôt : le scan sans couche texte entre dans la file SI la lecture est possible ; sinon rien ne se met en file et l'état dit pourquoi. */
  function apresDepot(depot, ctx) {
    if (!depot || depot.texteIndexe) return null;
    var r = demander(depot.sha256, ctx || {});
    if (r && r.ok) demarrer();
    return r;
  }

  /** Les scans sans texte, sans lecture et hors file, qu'une activation du réglage doit rattraper. */
  function balayer() {
    var n = 0;
    if (!pret()) return n;
    registre().active().forEach(function (f) {
      if (f.texteIndexe || f.ocr || versionCourante(f.sha256) || (f.nbReferences || 0) <= 0) return;
      var ou = ficheQuiPorte(f.sha256);
      if (!ou) return;
      var r = demander(f.sha256, { famille: ou.famille, type: ou.type });
      if (r && r.demande) n++;
    });
    return n;
  }
  function ficheQuiPorte(sha) {
    var c = S.collection('courriers').active().filter(function (x) { return x.fichier && x.fichier.sha256 === sha; })[0];
    if (c) return { famille: 'courrier', type: null };
    var d = S.collection('documentsPatient').active().filter(function (x) { return x.fichier && x.fichier.sha256 === sha; })[0];
    return d ? { famille: 'patient', type: d.type } : null;
  }

  /** Reprise après arrêt : un traitement « en cours » depuis plus de deux délais est remis en attente (jamais perdu), ou en échec après trois essais. */
  function reprendre() {
    var n = 0, seuil = Date.now() - reglage().delaiMs * 2;
    registre().active().forEach(function (f) {
      if (!f.ocr || f.ocr.etat !== 'en_cours') return;
      if (Date.parse(f.ocr.debutLe || 0) > seuil) return;
      var essais = f.ocr.essais || 0;
      var o = essais >= ESSAIS_MAX
        ? Object.assign({}, f.ocr, { etat: 'echec', code: CODES.ESSAIS_EPUISES, raison: 'la lecture a été interrompue ' + essais + ' fois', geste: GESTES.ESSAIS_EPUISES, finLe: new Date().toISOString() })
        : Object.assign({}, f.ocr, { etat: 'en_attente' });
      registre().update(f.id, { ocr: o }, { journal: { action: 'Lecture OCR reprise après arrêt', module: 'M13', entite: 'lecture OCR', avant: { etat: 'en_cours' }, apres: { etat: o.etat } } });
      n++;
    });
    return n;
  }

  var occupe = false;
  /* Les fichiers que le PROFIL COURANT ne lit pas (droit, zone) : écartés pour lui, pas pour un autre. La clé porte le rôle de la session : changer de session ne laisse pas à l'agent suivant les écarts du précédent. */
  var ecartes = {};
  function cleEcart(sha) { return ((S.session() || {}).role || '') + '|' + sha; }

  function avecDelai(promesse, ms) {
    return new global.Promise(function (resolve, reject) {
      var t = global.setTimeout(function () { reject({ code: CODES.DELAI_DEPASSE, motif: 'le moteur n’a pas répondu en ' + (ms % 1000 === 0 ? ms / 1000 : (ms / 1000).toFixed(1).replace('.', ',')) + ' s' }); }, ms);
      promesse.then(function (x) { global.clearTimeout(t); resolve(x); }, function (e) { global.clearTimeout(t); reject(e); });
    });
  }
  function nommer(e) {
    var code = e && e.code && CODES[e.code] ? e.code : CODES.MOTEUR_EN_ECHEC;
    return { code: code, motif: (e && e.motif) || (e && e.message) || 'le moteur a échoué', geste: (e && e.geste) || GESTES[code] };
  }

  /** Lit UN fichier avec le moteur actif. Rend une promesse { ok:true, lecture } ou { ok:false, code, motif, geste, transitoire? }. */
  function lireAvecMoteur(octets, fichier, famille) {
    var m = moteurActif(), r = reglage();
    if (!m) return global.Promise.resolve(refus(CODES.MOTEUR_ABSENT, RAISON_SANS_MOTEUR));
    var fmt = global.SIGH.fichiers.formatDesOctets(octets);
    var entree = { octets: octets, mime: fichier.mime, format: fmt, langue: r.langue, page: 1 };
    if (fmt === 'pdf') {
      if (!rendeur) return global.Promise.resolve(refus(CODES.RENDU_PAGES_ABSENT, 'ce scan est un PDF sans couche texte : aucun rendeur de pages n’est installé pour en tirer des images'));
      return rendeur(octets).then(function (pages) { return lirePages(m, pages, r); });
    }
    if (m.formats.indexOf(fmt) < 0) return global.Promise.resolve(refus(CODES.FORMAT_NON_LU, 'le moteur « ' + m.id + ' » ne lit pas le format ' + String(fmt).toUpperCase()));
    if (m.langues.indexOf(r.langue) < 0) return global.Promise.resolve(refus(CODES.LANGUE_ABSENTE, 'le moteur « ' + m.id + ' » ne lit pas la langue « ' + r.langue + ' »'));
    return lirePages(m, [{ octets: octets, mime: fichier.mime, format: fmt }], r);
  }
  function lirePages(m, pages, r) {
    var debut = Date.now(), textes = [], mots = [];
    var chaine = global.Promise.resolve();
    pages.forEach(function (p, i) {
      chaine = chaine.then(function () {
        return avecDelai(global.Promise.resolve(m.lire({ octets: p.octets, mime: p.mime, format: p.format, langue: r.langue, page: i + 1 })), r.delaiMs).then(function (res) {
          textes.push(String((res && res.texte) || ''));
          ((res && res.mots) || []).forEach(function (x) { mots.push(x); });
        });
      });
    });
    return chaine.then(function () {
      var confs = mots.filter(function (x) { return typeof x.confiance === 'number'; }).map(function (x) { return x.confiance; });
      return { ok: true, texte: textes.join('\n'), pages: pages.length, dureeMs: Date.now() - debut,
        confiance: confs.length ? Math.round(confs.reduce(function (a, b) { return a + b; }, 0) / confs.length * 1000) / 1000 : null };
    }, function (e) { var n = nommer(e); return { ok: false, code: n.code, motif: n.motif, geste: n.geste }; });
  }

  /** Enregistre une lecture : AJOUTE une version (jamais une réécriture). Idempotent par identifiant. */
  function enregistrerLecture(sha, lu, declencheur) {
    var m = moteurActif(), r = reglage();
    var norm = motsNormalises(lu.texte);
    var id = idLecture(sha, m.id, m.version, r.langue, norm.join(' '));
    var dejaLa = lectures().get(id);
    if (!dejaLa) {
      lectures().insert({ id: id, sha256: sha, texteBrut: String(lu.texte).slice(0, BRUT_MAX), brutTronque: String(lu.texte).length > BRUT_MAX, texte: norm.slice(0, MOTS_MAX).join(' '),
        motsTronques: norm.length > MOTS_MAX, nbMots: norm.length, confiance: lu.confiance, texteSource: 'ocr', moteur: m.id, moteurVersion: m.version, langue: r.langue, ocrLe: new Date().toISOString(),
        ocrPar: S.currentUser(), declencheur: declencheur || 'automatique', pages: lu.pages, dureeMs: lu.dureeMs },
      { journal: { action: 'Lecture OCR d’un scan', module: 'M13', entite: 'lecture OCR', avant: null, apres: { empreinte: D.DOCUMENTS.abrege(sha), moteur: m.id, mots: norm.length, pages: lu.pages } } });
    }
    return { id: id, nouvelle: !dejaLa };
  }

  /** Traite UN fichier de la file. Rend une promesse { ok, fait, sha?, code? }. Jamais en parallèle d'un autre traitement. */
  function traiterSuivant() {
    if (occupe) return global.Promise.resolve({ ok: true, fait: false, occupe: true });
    if (!pret()) return global.Promise.resolve({ ok: false, fait: false, code: !moteurInstalle() ? CODES.MOTEUR_ABSENT : CODES.OCR_DESACTIVE });
    /* Le plus ancien d'abord ; à la même seconde, l'empreinte départage : tous les postes choisissent dans le même ordre. */
    var suivant = registre().active().filter(function (f) { return f.ocr && f.ocr.etat === 'en_attente' && !ecartes[cleEcart(f.sha256)]; })
      .sort(function (a, b) { return a.ocr.demandeLe < b.ocr.demandeLe ? -1 : (a.ocr.demandeLe > b.ocr.demandeLe ? 1 : (a.sha256 < b.sha256 ? -1 : 1)); })[0];
    if (!suivant) return global.Promise.resolve({ ok: true, fait: false });
    var sha = suivant.sha256, q = suivant.ocr;
    occupe = true;
    var fichier = { sha256: sha, mime: suivant.mime };
    return global.SIGH.fichiers.lire(fichier, q.famille || 'courrier', 'ocr', null).then(function (oct) {
      if (!oct.ok) {
        /* Un refus de DROIT ou de zone n'est pas un échec du fichier : ce profil ne le lit pas, un autre le traitera. Fichier absent ou serveur injoignable : on réessaiera. */
        ecartes[cleEcart(sha)] = true;
        return { ok: true, fait: false, ecarte: oct.code };
      }
      registre().update(suivant.id, { ocr: Object.assign({}, q, { etat: 'en_cours', debutLe: new Date().toISOString(), essais: (q.essais || 0) + 1 }) },
        { journal: { action: 'Lecture OCR commencée', module: 'M13', entite: 'lecture OCR', avant: { empreinte: D.DOCUMENTS.abrege(sha) }, apres: { etat: 'en_cours' } } });
      return lireAvecMoteur(oct.u8, fichier, q.famille).then(function (lu) {
        var courant = fiche(sha) || suivant;
        var essais = (courant.ocr && courant.ocr.essais) || 1;
        if (lu.ok && !String(lu.texte).trim()) lu = { ok: false, code: CODES.AUCUN_TEXTE, motif: 'le moteur n’a lu aucun mot', geste: GESTES.AUCUN_TEXTE };
        if (!lu.ok) {
          registre().update(courant.id, { ocr: Object.assign({}, courant.ocr, { etat: 'echec', code: lu.code, raison: lu.motif, geste: lu.geste, finLe: new Date().toISOString() }) },
            { journal: { action: 'Lecture OCR en échec', module: 'M13', entite: 'lecture OCR', avant: { empreinte: D.DOCUMENTS.abrege(sha) }, apres: { etat: 'echec', code: lu.code } } });
          return { ok: false, fait: true, sha: sha, code: lu.code, essais: essais };
        }
        var e = enregistrerLecture(sha, lu, courant.ocr && courant.ocr.declencheur);
        registre().update(courant.id, { ocr: null }, { journal: { action: 'Lecture OCR terminée', module: 'M13', entite: 'lecture OCR', avant: { etat: 'en_cours' }, apres: { etat: 'ocr_indexe', version: e.id } } });
        return { ok: true, fait: true, sha: sha, version: e.id, nouvelle: e.nouvelle };
      });
    }).then(function (x) { occupe = false; return x; }, function (e) { occupe = false; return { ok: false, fait: false, code: nommer(e).code }; });
  }

  var minuterie = null;
  /** Fait tourner la file sans bloquer la saisie : un fichier par passe, la main rendue au navigateur entre deux. */
  function demarrer() {
    if (minuterie || !pret()) return;
    minuterie = global.setTimeout(function pas() {
      minuterie = null;
      reprendre();
      traiterSuivant().then(function (r) {
        if (r && r.fait) { minuterie = global.setTimeout(pas, 50); } else { minuterie = null; }
      });
    }, 50);
    global.document.addEventListener('sigh:unmount', function () { if (minuterie) { global.clearTimeout(minuterie); minuterie = null; } }, { once: true });
  }
  /** Vide la file jusqu'à ce qu'il n'y ait plus rien à lire (tests et reprise à l'ouverture d'un écran). */
  function vider(max) {
    var faits = 0;
    function pas() {
      if (faits >= (max || 50)) return global.Promise.resolve(faits);
      return traiterSuivant().then(function (r) { if (r && r.fait) { faits++; return pas(); } return faits; });
    }
    reprendre();
    return pas();
  }

  /* ==========================================================================
   * 6bis. CORRECTION SIGNÉE du texte lu (lot C) : une version de plus, jamais une réécriture
   * ======================================================================== */
  var GESTE_CORRECTION = 'corriger_texte_ocr';
  /** Le texte d'une correction comparé à un autre : les blancs répétés et ceux des bords ne comptent pas. */
  function blancsNormalises(t) { return String(t || '').replace(/\s+/g, ' ').trim(); }
  /** L'identifiant d'une correction : DÉTERMINISTE (empreinte, version dont elle part, texte sans blancs superflus). Le même texte sur la même version est la MÊME version, d'un poste à l'autre. */
  function idCorrection(sha, corrigeDe, texte) {
    return 'OCC-' + String(sha).slice(0, 16) + '-' + sha256Texte(corrigeDe + '|' + blancsNormalises(texte)).slice(0, 12);
  }
  /** Ce profil peut-il corriger la pièce ? Écrire sur l'écran de la pièce (zone comprise, déjà portée par `peutDeposer`) ET détenir le geste réservé. Rend null, ou le refus NOMMÉ avec sa cause. */
  function refusDroitCorrection(ctx) {
    var s = S.session() || {};
    if (!ctx || !ctx.peutDeposer) return refus(CODES.CORRECTION_RESERVEE, 'votre profil n’écrit pas sur l’écran de cette pièce (ou la pièce est d’une zone qu’il ne lit pas) : il ne peut pas corriger son texte');
    if (ctx.famille === 'patient' && global.SIGH.parcours && !global.SIGH.parcours.peutVoirDocument(ctx.type).autorise) return refus(CODES.CORRECTION_RESERVEE, 'cette pièce médicale est d’une zone que votre profil ne lit pas (RG-13)');
    if (!global.SIGH.nav.droitGeste(s.role, GESTE_CORRECTION)) return refus(CODES.CORRECTION_RESERVEE, 'le droit « Corriger le texte lu par machine » n’est pas accordé à votre rôle');
    return null;
  }
  /** La commande « Corriger le texte lu » est-elle OFFERTE ? ABSENTE sinon, jamais grisée : droit, pas de couche texte native, une lecture à corriger. */
  function correctionPossible(fichier, ctx) {
    if (!fichier || !fichier.sha256 || refusDroitCorrection(ctx)) return false;
    var e = etatDe(fichier);
    return !!e && e.code !== 'indexe' && versionsDe(fichier.sha256).some(function (x) { return (x.nbMots || 0) > 0 || estCorrection(x); });
  }
  /** Corrige le texte lu d'un scan : AJOUTE une version signée (jamais une réécriture), journalisée. Le moteur refuse aussi : masquer le bouton ne protège rien.
   * `ctx` : { peutDeposer, famille, type, corrigeDe? (la version dont le texte sert de départ ; par défaut la courante) }. */
  function corriger(fichier, texte, ctx) {
    var d = refusDroitCorrection(ctx);
    if (d) return d;
    if (!fichier || !fichier.sha256) return refus('SANS_PIECE', 'cette fiche ne porte aucun fichier', 'Déposer d’abord le scan.');
    var sha = fichier.sha256;
    if (natifDe(sha) || fichier.texteIndexe) return refus(CODES.TEXTE_NATIF, 'ce fichier porte déjà une couche texte : elle prime, il n’y a rien à corriger');
    var propre = String(texte == null ? '' : texte);
    if (!propre.trim()) return refus(CODES.CORRECTION_TEXTE_VIDE, 'le texte corrigé est vide');
    var vs = versionsDe(sha);
    var base = ctx.corrigeDe ? vs.filter(function (x) { return x.id === ctx.corrigeDe; })[0] : courantDe(vs);
    if (!base) return refus(CODES.CORRECTION_SANS_BASE, ctx.corrigeDe ? 'la version « ' + ctx.corrigeDe + ' » n’est pas une lecture de ce scan' : 'ce scan n’a aucune lecture à corriger');
    if (blancsNormalises(propre) === blancsNormalises(base.texteBrut)) return refus(CODES.CORRECTION_IDENTIQUE, 'le texte est identique à celui de la version dont la correction part');
    var id = idCorrection(sha, base.id, propre);
    var dejaLa = lectures().get(id);
    if (!dejaLa) {
      var norm = motsNormalises(propre);
      var maintenant = new Date().toISOString();
      /* Elle remplace les corrections courantes qu'elle a sous les yeux : c'est ce qui départage un conflit, et ce qui fait qu'une correction ultérieure ferme les deux branches. */
      var remplace = tetesDe(vs).map(function (x) { return x.id; });
      var avant = courantDe(vs);
      var ecrit = lectures().insert({ id: id, sha256: sha, texteBrut: propre.slice(0, BRUT_MAX), brutTronque: propre.length > BRUT_MAX, texte: norm.slice(0, MOTS_MAX).join(' '),
        motsTronques: norm.length > MOTS_MAX, nbMots: norm.length, texteSource: 'correction', corrigeDe: base.id, remplace: remplace, corrigePar: S.currentUser(), corrigeLe: maintenant, ocrLe: maintenant },
      { journal: { action: 'Correction signée du texte lu d’un scan', module: 'M13', entite: 'lecture OCR', avant: { version: base.id, mots: base.nbMots || 0 }, apres: { version: id, mots: norm.length, remplace: remplace.length } } });
      if (!ecrit) return refus('CORRECTION_REFUSEE', 'le magasin a refusé l’écriture de la correction (voir la garde de la collection des lectures)', 'Vérifier la signature et le texte, puis recommencer.');
    }
    return { ok: true, id: id, nouvelle: !dejaLa, conflit: conflitDe(sha).length > 1 };
  }

  /* ==========================================================================
   * 6. RELANCE : absente sans le droit, sans moteur prêt, ou sur un fichier qui porte une couche texte
   * ======================================================================== */
  /** La commande « Relancer la lecture » est-elle OFFERTE ? Le droit d'écrire sur l'écran de la pièce (et la zone, déjà portée par `peutDeposer`), un moteur prêt, pas de couche texte native. */
  function relancePossible(fichier, peutDeposer) {
    if (!peutDeposer || !fichier || !fichier.sha256) return false;
    if (!pret()) return false;
    var e = etatDe(fichier);
    return !!e && e.code !== 'indexe' && e.code !== 'ocr_en_attente' && e.code !== 'ocr_en_cours';
  }
  /** La relance : le moteur la refuse aussi (masquer un bouton ne protège rien). */
  function relancer(fichier, ctx) {
    if (!ctx || !ctx.peutDeposer) return refus(CODES.DROIT_REFUSE, 'votre profil ne peut pas relancer la lecture de cette pièce');
    if (!fichier || !fichier.sha256) return refus('SANS_PIECE', 'cette fiche ne porte aucun fichier', 'Déposer d’abord le scan.');
    if (!pret()) return refus(!moteurInstalle() ? CODES.MOTEUR_ABSENT : CODES.OCR_DESACTIVE, !moteurInstalle() ? RAISON_SANS_MOTEUR : 'la lecture OCR est désactivée au réglage');
    var r = demander(fichier.sha256, { famille: ctx.famille, type: ctx.type, declencheur: 'relance' });
    if (r && r.ok && !r.deja) demarrer();
    return r;
  }

  /* ==========================================================================
   * 7. ÉCRANS : la ligne d'état de la carte, l'historique, le réglage, le message vide, la note de recherche
   * ======================================================================== */
  var TONS = { indexe: 'success', ocr_corrige: 'success', ocr_indexe: 'warning', ocr_en_attente: 'info', ocr_en_cours: 'info', ocr_echec: 'danger', non_indexe: 'neutral' };

  /** La ligne « Recherche dans le texte » de la carte. */
  function ligneEtat(fichier) {
    var e = etatDe(fichier);
    var b = U.badge(e.court.charAt(0).toUpperCase() + e.court.slice(1), TONS[e.code]);
    b.setAttribute('data-ocr-etat', e.code);
    if (e.marque) b.setAttribute('data-ocr-marque', '1');
    return b;
  }

  function dateHeure(iso) { return C.dateFR(String(iso || '').slice(0, 10)) + ' ' + String(iso || '').slice(11, 16); }
  function poidsConf(c) { return c == null ? 'non fournie par le moteur' : Math.round(c * 100) + ' % en moyenne'; }

  /** Le bloc de la carte « Pièce numérisée » sous les lignes : l'état en toutes lettres, le marquage, la relance, l'historique des lectures. */
  function blocCarte(o) {
    var K = global.SIGH.kit;
    var fichier = o.fichier, e = etatDe(fichier);
    var bloc = el('div.space-y-2', { 'data-ocr-bloc': e.code });
    if (e.code === 'indexe') return bloc;
    bloc.appendChild(el('p.text-xs.text-slate-600', { 'data-ocr-libelle': '1', text: e.libelle + '.' }));
    var versions = versionsDe(fichier.sha256);
    var cur = versionCourante(fichier.sha256);
    if (e.code === 'ocr_corrige' || (cur && estCorrection(cur))) {
      var nc = K.note('<strong>Texte corrigé et signé par ' + (cur.corrigePar || 'auteur inconnu') + ' le ' + dateHeure(cur.corrigeLe) + '.</strong> Une lecture machine plus récente ne le remplace pas : la lecture machine reste consultable ci-dessous. Le scan reste la seule référence.', { tone: 'info', icon: 'pen-line' });
      nc.setAttribute('data-ocr-corrige', '1');
      bloc.appendChild(nc);
    } else if (e.marque || cur) {
      bloc.appendChild(K.note('<strong>Texte lu par machine, à vérifier.</strong> La reconnaissance de caractères peut se tromper (accents, chiffres, mots coupés) : le texte sert à RETROUVER une pièce, jamais à la citer. Le scan reste la seule référence.', { tone: 'warning', icon: 'scan-text' }));
    }
    var concurrentes = conflitDe(fichier.sha256);
    if (concurrentes.length > 1) {
      var nk = K.note('<strong>Conflit : ' + concurrentes.length + ' corrections concurrentes de la même version</strong> (' + concurrentes.map(function (x) { return (x.corrigePar || '?') + ', ' + dateHeure(x.corrigeLe); }).join(' ; ') + '). Rien n’est perdu : le texte courant est la plus récente, une nouvelle correction signée les remplace toutes les deux.', { tone: 'danger', icon: 'git-merge' });
      nk.setAttribute('data-ocr-conflit', String(concurrentes.length));
      bloc.appendChild(nk);
    }
    if (e.code === 'ocr_echec') {
      bloc.appendChild(el('p.text-xs.text-danger-700', { 'data-ocr-echec': (fiche(fichier.sha256).ocr || {}).code || '', text: ((fiche(fichier.sha256).ocr || {}).geste || '') }));
    }
    if (e.code === 'non_indexe') {
      bloc.appendChild(el('p.text-xs.text-slate-500', { text: 'La recherche par le contenu ne lit pas cette pièce ; elle reste retrouvable par ses données de fiche.' }));
    }
    var actes = el('div.flex.flex-wrap.items-center.gap-2');
    if (relancePossible(fichier, o.peutDeposer)) {
      actes.appendChild(K.btn('Relancer la lecture', { icon: 'refresh-cw', size: 'sm', onclick: function () {
        var r = relancer(fichier, { peutDeposer: o.peutDeposer, famille: o.famille, type: o.type });
        if (!r.ok) { U.toast('Relance refusée : ' + r.code, { type: 'error', detail: r.motif + ' ' + r.geste }); return; }
        U.toast('Lecture relancée.', { type: 'success', detail: 'Une nouvelle version sera ajoutée ; l’ancienne reste lisible.' });
        if (o.refresh) o.refresh();
        vider(1).then(function () { if (o.refresh) o.refresh(); });
      } }));
      actes.lastChild.setAttribute('data-ocr-relancer', '1');
    }
    if (correctionPossible(fichier, o)) {
      var bc = K.btn('Corriger le texte lu', { icon: 'pen-line', size: 'sm', onclick: function () { ouvrirCorrection(fichier, o); } });
      bc.setAttribute('data-ocr-corriger', '1');
      actes.appendChild(bc);
    }
    if (actes.childNodes.length) bloc.appendChild(actes);
    if (versions.length) {
      var det = el('details.rounded-lg.border.border-slate-200.p-2', { 'data-ocr-historique': String(versions.length) });
      det.appendChild(el('summary.cursor-pointer.text-sm.text-slate-700', { text: 'Lectures de ce scan (' + versions.length + ')' }));
      var liste = el('div.mt-2.space-y-2');
      versions.slice().reverse().forEach(function (v, i) {
        var rang = versions.length - i;
        var courante = cur && v.id === cur.id;
        if (estCorrection(v)) {
          var deRang = versions.map(function (x) { return x.id; }).indexOf(v.corrigeDe) + 1;
          liste.appendChild(el('div.rounded.bg-slate-50.p-2.text-xs', { 'data-ocr-version': String(rang), 'data-ocr-signee': '1' }, [
            el('p.font-semibold', { text: 'Version ' + rang + (courante ? ' (courante)' : '') + ' : corrigée et signée par ' + (v.corrigePar || 'auteur inconnu') }),
            el('p.text-slate-500', { text: 'Signée le ' + dateHeure(v.corrigeLe) + ' · part de la version ' + (deRang || '?') + (v.remplace && v.remplace.length ? ' · remplace ' + v.remplace.length + ' correction' + (v.remplace.length > 1 ? 's' : '') : '') + ' · ' + v.nbMots + ' mots' }),
            el('details', null, [el('summary.cursor-pointer.text-slate-600', { text: 'Texte corrigé et signé' }), el('p.mt-1.whitespace-pre-wrap.text-slate-700', { 'data-ocr-texte': String(rang), text: v.texteBrut || '' })]),
          ]));
          return;
        }
        liste.appendChild(el('div.rounded.bg-slate-50.p-2.text-xs', { 'data-ocr-version': String(rang) }, [
          el('p.font-semibold', { text: 'Version ' + rang + (courante ? ' (courante)' : '') + ' : ' + v.moteur + (v.moteurVersion ? ' ' + v.moteurVersion : '') + ', langue ' + v.langue }),
          el('p.text-slate-500', { text: 'Lue le ' + dateHeure(v.ocrLe) + ' par ' + (v.ocrPar || 'auteur inconnu') + ' · ' + v.nbMots + ' mots · confiance ' + poidsConf(v.confiance) + (v.declencheur === 'relance' ? ' · relance' : '') }),
          el('details', null, [el('summary.cursor-pointer.text-slate-600', { text: 'Texte lu par machine, à vérifier' }), el('p.mt-1.whitespace-pre-wrap.text-slate-700', { 'data-ocr-texte': String(rang), text: v.texteBrut || '' })]),
        ]));
      });
      det.appendChild(liste);
      bloc.appendChild(det);
    }
    return bloc;
  }

  /** « Aucun résultat » dit ce que la recherche ne lit pas. `fichiers` : les objets `fichier` des pièces affichées. */
  function indiceVide(fichiers) {
    var etats = fichiers.map(etatDe).filter(Boolean);
    var sans = etats.filter(function (e) { return !e.disponible; });
    var out = [];
    if (sans.length) {
      out.push(sans.length + ' pièce' + (sans.length > 1 ? 's numérisées n’ont' : ' numérisée n’a') + ' pas de texte indexé (image sans couche texte) : la recherche par le contenu ne les lit pas, seules leurs données de fiche sont cherchées.');
      var nonLu = etats.filter(function (e) { return e.code === 'non_indexe'; });
      var attente = etats.filter(function (e) { return e.code === 'ocr_en_attente' || e.code === 'ocr_en_cours'; });
      var echec = etats.filter(function (e) { return e.code === 'ocr_echec'; });
      if (nonLu.length) out.push(nonLu.length + ' pièce' + (nonLu.length > 1 ? 's' : '') + ' sans texte lu : ' + nonLu[0].raison + '.');
      if (attente.length) out.push(attente.length + ' pièce' + (attente.length > 1 ? 's' : '') + ' en attente de lecture OCR.');
      if (echec.length) out.push(echec.length + ' pièce' + (echec.length > 1 ? 's' : '') + ' dont la lecture OCR a échoué.');
    }
    var lus = etats.filter(function (e) { return e.code === 'ocr_indexe'; }).length;
    if (lus) out.push(lus + ' pièce' + (lus > 1 ? 's' : '') + ' ne se cherche' + (lus > 1 ? 'nt' : '') + ' que par un texte lu par machine, à vérifier.');
    return out.length ? out.join(' ') : null;
  }

  /** Au-dessus des résultats : combien ont été trouvés par un texte lu par machine. `q` : la recherche ; `fichiers` : les objets `fichier` des lignes affichées. */
  function noteRecherche(q, fichiers) {
    if (!q) return null;
    var n = fichiers.filter(function (x) { return x && etatDe(x) && etatDe(x).code === 'ocr_indexe' && C.matches(texteOcrDe(x.sha256), q); }).length;
    if (!n) return null;
    var K = global.SIGH.kit;
    var note = K.note('<strong>' + n + ' résultat' + (n > 1 ? 's' : '') + ' trouvé' + (n > 1 ? 's' : '') + ' dans un texte lu par machine</strong> (OCR) : la reconnaissance peut se tromper, à vérifier sur la pièce.', { tone: 'warning', icon: 'scan-text' });
    note.setAttribute('data-note-ocr', String(n));
    return note;
  }

  /** La fenêtre de correction : le texte courant à corriger, la version de départ au choix (la dernière lecture machine après une relance), la signature rappelée. */
  function ouvrirCorrection(fichier, o) {
    var K = global.SIGH.kit;
    var vs = versionsDe(fichier.sha256).filter(function (x) { return (x.nbMots || 0) > 0 || estCorrection(x); });
    var cur = versionCourante(fichier.sha256);
    var depart = el('select.select', { 'aria-label': 'Version de départ' });
    vs.slice().reverse().forEach(function (v) {
      var rang = versionsDe(fichier.sha256).map(function (x) { return x.id; }).indexOf(v.id) + 1;
      depart.appendChild(el('option', { value: v.id, text: 'Version ' + rang + (estCorrection(v) ? ' (corrigée par ' + (v.corrigePar || '?') + ')' : ' (lue par machine)') + (cur && cur.id === v.id ? ', courante' : '') }));
    });
    depart.value = cur ? cur.id : '';
    var zone = el('textarea.textarea', { rows: 8, 'aria-label': 'Texte corrigé' });
    zone.value = cur ? (cur.texteBrut || '') : '';
    depart.addEventListener('change', function () { var v = vs.filter(function (x) { return x.id === depart.value; })[0]; zone.value = v ? (v.texteBrut || '') : ''; });
    var msg = el('p.text-xs.text-danger-700', { role: 'alert' });
    var corps = el('div.space-y-3', null, [
      K.note('Votre correction est <strong>signée à votre nom</strong>, datée et journalisée. Elle s’AJOUTE : la lecture machine reste lisible et intacte, et le texte corrigé devient le texte courant de la recherche.', { tone: 'info' }),
      el('div', null, [el('label.label', { text: 'Partir de' }), depart]),
      el('div', null, [el('label.label', { text: 'Texte corrigé' }), zone]),
      msg,
    ]);
    var m = U.modal({ title: 'Corriger le texte lu', size: 'md', body: corps, footer: [
      K.btn('Annuler', { onclick: function () { m.close(); } }),
      K.btn('Signer la correction', { variant: 'primary', icon: 'check', onclick: function () {
        var r = corriger(fichier, zone.value, { peutDeposer: o.peutDeposer, famille: o.famille, type: o.type, corrigeDe: depart.value || null });
        if (!r.ok) { msg.textContent = r.code + ' : ' + r.motif + ' ' + r.geste; return; }
        m.close();
        U.toast('Correction signée.', { type: 'success', detail: r.conflit ? 'Conflit : deux corrections concurrentes, à départager.' : 'La lecture machine reste lisible.' });
        if (o.refresh) o.refresh();
      } }),
    ] });
  }

  /** Le bouton de réglage : ABSENT hors administrateur et DAF. */
  function boutonReglage() {
    if (!peutRegler()) return null;
    var K = global.SIGH.kit;
    var b = K.btn('Lecture des scans (OCR)', { icon: 'scan-text', size: 'sm', onclick: function () { ouvrirReglage(); } });
    b.setAttribute('data-ocr-reglage', '1');
    return b;
  }
  function ouvrirReglage() {
    var K = global.SIGH.kit;
    var r = reglage();
    var choix = listeMoteurs();
    var actif = el('input.checkbox', { type: 'checkbox', 'aria-label': 'Activer la lecture des scans' });
    actif.checked = r.actif;
    var moteur = el('select.select', { 'aria-label': 'Moteur' });
    moteur.appendChild(el('option', { value: '', text: choix.length ? 'Choisir un moteur' : 'Aucun moteur installé' }));
    choix.forEach(function (m) { moteur.appendChild(el('option', { value: m.id, text: m.libelle + (m.version ? ' ' + m.version : '') })); });
    moteur.value = r.moteur || '';
    var langue = el('input.input', { type: 'text', 'aria-label': 'Langue', value: r.langue });
    var delai = el('input.input', { type: 'number', min: '1', step: '1', 'aria-label': 'Délai de lecture par page, en secondes', value: String(Math.round(r.delaiMs / 1000)) });
    var motif = el('textarea.textarea', { rows: 2, placeholder: 'Motif du réglage', 'aria-label': 'Motif' });
    var msg = el('p.text-xs.text-danger-700', { role: 'alert' });
    var corps = el('div.space-y-3', null, [
      K.note(choix.length ? 'Réglage de <strong>la clinique</strong> : il vaut pour tous les postes. La lecture des scans est <strong>désactivée par défaut</strong> (à valider par la Direction). Le texte lu par machine est toujours marqué « à vérifier ».'
        : '<strong>' + RAISON_SANS_MOTEUR + '.</strong> Il n’y a rien à activer tant qu’un moteur n’est pas installé : la Direction a décidé de choisir le moteur après un essai sur trois vrais scans.', { tone: 'info' }),
      el('label.flex.items-center.gap-2.text-sm', null, [actif, 'Activer la lecture automatique des scans']),
      el('div', null, [el('label.label', { text: 'Moteur d’OCR' }), moteur]),
      el('div', null, [el('label.label', { text: 'Langue (code du moteur, « fra » pour le français)' }), langue]),
      el('div', null, [el('label.label', { text: 'Délai de lecture par page (secondes, au-delà la lecture est arrêtée et se relance)' }), delai]),
      el('div', null, [el('label.label', { text: 'Motif (consigné dans le journal)' }), motif]),
      msg,
    ]);
    var m = U.modal({ title: 'Lecture des scans (OCR)', size: 'sm', body: corps, footer: [
      K.btn('Annuler', { onclick: function () { m.close(); } }),
      K.btn('Enregistrer', { variant: 'primary', icon: 'check', onclick: function () {
        var x = definirReglage({ actif: actif.checked, moteur: moteur.value || null, langue: String(langue.value || '').trim() || LANGUE_DEFAUT, delaiMs: Math.round(Number(delai.value) * 1000) || 0 }, motif.value);
        if (!x.ok) { msg.textContent = x.code + ' : ' + x.motif + ' ' + x.geste; return; }
        m.close();
        U.toast(x.reglage.actif ? 'Lecture des scans activée.' : 'Lecture des scans désactivée.', { type: 'success' });
      } }),
    ] });
  }

  global.SIGH.ocr = {
    CODES: CODES, GESTES: GESTES, RAISON_SANS_MOTEUR: RAISON_SANS_MOTEUR, DELAI_DEFAUT_MS: DELAI_DEFAUT_MS, ESSAIS_MAX: ESSAIS_MAX, LANGUE_DEFAUT: LANGUE_DEFAUT,
    enregistrerMoteur: enregistrerMoteur, retirerMoteur: retirerMoteur, moteurInstalle: moteurInstalle, moteurActif: moteurActif, listeMoteurs: listeMoteurs, poserRendeur: poserRendeur,
    reglage: reglage, peutRegler: peutRegler, definirReglage: definirReglage, pret: pret,
    motsNormalises: motsNormalises, idLecture: idLecture, versionsDe: versionsDe, versionCourante: versionCourante, texteOcrDe: texteOcrDe, texteLisible: texteLisible, natifDe: natifDe,
    etatIndexation: etatIndexation, etatDe: etatDe, court: court, aUnTexte: aUnTexte,
    demander: demander, apresDepot: apresDepot, balayer: balayer, reprendre: reprendre, traiterSuivant: traiterSuivant, vider: vider, demarrer: demarrer,
    relancePossible: relancePossible, relancer: relancer,
    GESTE_CORRECTION: GESTE_CORRECTION, estCorrection: estCorrection, tetesDe: tetesDe, courantDe: courantDe, conflitDe: conflitDe, idCorrection: idCorrection,
    refusDroitCorrection: refusDroitCorrection, correctionPossible: correctionPossible, corriger: corriger,
    ligneEtat: ligneEtat, blocCarte: blocCarte, indiceVide: indiceVide, noteRecherche: noteRecherche, boutonReglage: boutonReglage,
  };
})(window);
