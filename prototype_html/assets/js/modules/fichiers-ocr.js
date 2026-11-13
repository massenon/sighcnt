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
   * 2. RÉGLAGE : activer ou non, moteur choisi, langue ; en base ; administrateur et DAF ; DÉSACTIVÉ par défaut (à valider)
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
    S.log('Réglage de la lecture OCR des scans', 'M14', 'reglage', 'ocr', { actif: avant.actif, moteur: avant.moteur, langue: avant.langue }, { actif: actif, moteur: id, langue: langue, motif: String(motif).slice(0, 40) });
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
  /** La version COURANTE : la plus récente qui porte du texte. */
  function versionCourante(sha) {
    var v = versionsDe(sha).filter(function (x) { return (x.nbMots || 0) > 0; });
    return v.length ? v[v.length - 1] : null;
  }
  function natifDe(sha) { var f = fiche(sha); return !!(f && f.texteIndexe); }

  /** Le texte OCR (mots normalisés) de la version courante, ou ''. Jamais le natif : c'est `texteDe` de fichiers.js qui fait primer le natif. */
  function texteOcrDe(sha) { var v = versionCourante(sha); return v ? (v.texte || '') : ''; }

  /* ==========================================================================
   * 4. ÉTATS D'INDEXATION : six, jamais confondus
   * ======================================================================== */
  /** `o` : { natif, versions, file: {etat, code?, raison?}|null, moteurInstalle, actif, moteurActif }. Rend { code, court, libelle, raison, source, marque, disponible }. */
  function etatIndexation(o) {
    var cur = null;
    (o.versions || []).forEach(function (x) { if ((x.nbMots || 0) > 0 && (!cur || x.ocrLe >= cur.ocrLe)) cur = x; });
    var f = o.file || null;
    if (o.natif) return { code: 'indexe', court: 'texte indexé', libelle: 'Texte indexé (couche texte du fichier)', raison: null, source: 'couche_texte', marque: false, disponible: true };
    var source = cur ? 'ocr' : null, disponible = !!cur;
    if (f && f.etat === 'en_cours') return { code: 'ocr_en_cours', court: 'lecture OCR en cours', libelle: 'Lecture OCR en cours' + (cur ? ' (la version précédente reste lisible)' : ''), raison: null, source: source, marque: !!cur, disponible: disponible };
    if (f && f.etat === 'en_attente') return { code: 'ocr_en_attente', court: 'lecture OCR en attente', libelle: 'Lecture OCR en attente' + (cur ? ' (la version précédente reste lisible)' : ''), raison: null, source: source, marque: !!cur, disponible: disponible };
    if (f && f.etat === 'echec') return { code: 'ocr_echec', court: 'lecture OCR en échec', libelle: 'Lecture OCR en échec : ' + (f.raison || 'cause non renseignée'), raison: f.raison || null, source: source, marque: !!cur, disponible: disponible };
    if (cur) return { code: 'ocr_indexe', court: 'texte lu par machine, à vérifier', libelle: 'Texte lu par machine, à vérifier', raison: null, source: 'ocr', marque: true, disponible: true };
    var raison = !o.moteurInstalle ? RAISON_SANS_MOTEUR
      : (!o.actif ? 'la lecture OCR est désactivée au réglage'
        : (!o.moteurActif ? 'le moteur choisi au réglage n’est pas installé sur ce poste' : 'lecture OCR non encore demandée'));
    return { code: 'non_indexe', court: 'texte non indexé', libelle: 'Texte non indexé : ' + raison, raison: raison, source: null, marque: false, disponible: false };
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
  var TONS = { indexe: 'success', ocr_indexe: 'warning', ocr_en_attente: 'info', ocr_en_cours: 'info', ocr_echec: 'danger', non_indexe: 'neutral' };

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
    if (e.marque || cur) {
      bloc.appendChild(K.note('<strong>Texte lu par machine, à vérifier.</strong> La reconnaissance de caractères peut se tromper (accents, chiffres, mots coupés) : le texte sert à RETROUVER une pièce, jamais à la citer. Le scan reste la seule référence.', { tone: 'warning', icon: 'scan-text' }));
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
    if (actes.childNodes.length) bloc.appendChild(actes);
    if (versions.length) {
      var det = el('details.rounded-lg.border.border-slate-200.p-2', { 'data-ocr-historique': String(versions.length) });
      det.appendChild(el('summary.cursor-pointer.text-sm.text-slate-700', { text: 'Lectures de ce scan (' + versions.length + ')' }));
      var liste = el('div.mt-2.space-y-2');
      versions.slice().reverse().forEach(function (v, i) {
        var rang = versions.length - i;
        var courante = cur && v.id === cur.id;
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
    var motif = el('textarea.textarea', { rows: 2, placeholder: 'Motif du réglage', 'aria-label': 'Motif' });
    var msg = el('p.text-xs.text-danger-700', { role: 'alert' });
    var corps = el('div.space-y-3', null, [
      K.note(choix.length ? 'La lecture des scans est <strong>désactivée par défaut</strong> (à valider par la Direction). Le texte lu par machine est toujours marqué « à vérifier ».'
        : '<strong>' + RAISON_SANS_MOTEUR + '.</strong> Il n’y a rien à activer tant qu’un moteur n’est pas installé : la Direction a décidé de choisir le moteur après un essai sur trois vrais scans.', { tone: 'info' }),
      el('label.flex.items-center.gap-2.text-sm', null, [actif, 'Activer la lecture automatique des scans']),
      el('div', null, [el('label.label', { text: 'Moteur d’OCR' }), moteur]),
      el('div', null, [el('label.label', { text: 'Langue (code du moteur, « fra » pour le français)' }), langue]),
      el('div', null, [el('label.label', { text: 'Motif (consigné dans le journal)' }), motif]),
      msg,
    ]);
    var m = U.modal({ title: 'Lecture des scans (OCR)', size: 'sm', body: corps, footer: [
      K.btn('Annuler', { onclick: function () { m.close(); } }),
      K.btn('Enregistrer', { variant: 'primary', icon: 'check', onclick: function () {
        var x = definirReglage({ actif: actif.checked, moteur: moteur.value || null, langue: String(langue.value || '').trim() || LANGUE_DEFAUT }, motif.value);
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
    ligneEtat: ligneEtat, blocCarte: blocCarte, indiceVide: indiceVide, noteRecherche: noteRecherche, boutonReglage: boutonReglage,
  };
})(window);
