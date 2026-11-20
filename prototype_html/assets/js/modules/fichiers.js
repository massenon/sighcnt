/* =============================================================================
 * SIGH-CNT : les FICHIERS numérisés (courriers M13, dossier patient M1) : dépôt, lecture, aperçu, téléchargement, visionneuse
 * -----------------------------------------------------------------------------
 * Chargé par les écrans qui portent une pièce numérisée (`scripts` du manifeste), jamais par les 300 autres. Le fichier lui-même vit sur le serveur
 * (`api/fichiers.php`, sous sa clé d'empreinte SHA-256) ; le magasin ne garde que ses métadonnées, dans le champ `fichier` de la fiche. Une pièce rattachée ne se
 * supprime jamais (RG-14) : on la RETIRE de la fiche (historique `fichiersRetires`), le fichier reste sur le disque, l'empreinte reste au journal.
 *
 * DEUX RÈGLES QUI NE SE DEVINENT PAS :
 *   - l'empreinte est calculée ICI avant l'envoi puis RECALCULÉE par le serveur, qui refuse un fichier dont l'empreinte diffère ; elle est recalculée de
 *     nouveau à la relecture (migration, aperçu, téléchargement). Une copie qui n'a pas la même empreinte n'est jamais présentée comme la pièce ;
 *   - le repli est ce que fait toute écriture sans serveur : le dépôt est REFUSÉ en le nommant (store.js : plus de seconde destination dans le navigateur).
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, S = global.SIGH.store, D = global.SIGH.data, U = global.SIGH.ui;
  var el = C.el;
  var DOC = D.DOCUMENTS;

  /* ==========================================================================
   * 1. OUTILS : empreinte SHA-256 des OCTETS, format par les premiers octets, base64
   * ======================================================================== */
  var K256 = new Int32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]);

  /** SHA-256 (FIPS 180-4) d'un tableau d'octets, synchrone, en hexadécimal. Fonctionne aussi hors contexte sécurisé (http sur le réseau local), où `crypto.subtle` n'existe pas. */
  function sha256Octets(u8) {
    var len = u8.length, total = Math.ceil((len + 9) / 64) * 64;
    var h = new Int32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
    var w = new Int32Array(64);
    var bitsHaut = Math.floor(len / 0x20000000), bitsBas = (len << 3);
    for (var off = 0; off < total; off += 64) {
      var t;
      for (t = 0; t < 16; t++) {
        var p = off + t * 4;
        if (p + 3 < len) { w[t] = (u8[p] << 24) | (u8[p + 1] << 16) | (u8[p + 2] << 8) | u8[p + 3]; }
        else {
          var v = 0;
          for (var k = 0; k < 4; k++) { var q = p + k; v = (v << 8) | (q < len ? u8[q] : (q === len ? 0x80 : 0)); }
          w[t] = v;
        }
      }
      if (off === total - 64) { w[14] = bitsHaut; w[15] = bitsBas; }
      for (t = 16; t < 64; t++) {
        var a15 = w[t - 15], a2 = w[t - 2];
        var s0 = ((a15 >>> 7) | (a15 << 25)) ^ ((a15 >>> 18) | (a15 << 14)) ^ (a15 >>> 3);
        var s1 = ((a2 >>> 17) | (a2 << 15)) ^ ((a2 >>> 19) | (a2 << 13)) ^ (a2 >>> 10);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0;
      }
      var A = h[0], B = h[1], Cc = h[2], Dd = h[3], E = h[4], F = h[5], G = h[6], H = h[7];
      for (t = 0; t < 64; t++) {
        var S1 = ((E >>> 6) | (E << 26)) ^ ((E >>> 11) | (E << 21)) ^ ((E >>> 25) | (E << 7));
        var ch = (E & F) ^ (~E & G);
        var t1 = (H + S1 + ch + K256[t] + w[t]) | 0;
        var S0 = ((A >>> 2) | (A << 30)) ^ ((A >>> 13) | (A << 19)) ^ ((A >>> 22) | (A << 10));
        var mj = (A & B) ^ (A & Cc) ^ (B & Cc);
        var t2 = (S0 + mj) | 0;
        H = G; G = F; F = E; E = (Dd + t1) | 0; Dd = Cc; Cc = B; B = A; A = (t1 + t2) | 0;
      }
      h[0] = (h[0] + A) | 0; h[1] = (h[1] + B) | 0; h[2] = (h[2] + Cc) | 0; h[3] = (h[3] + Dd) | 0;
      h[4] = (h[4] + E) | 0; h[5] = (h[5] + F) | 0; h[6] = (h[6] + G) | 0; h[7] = (h[7] + H) | 0;
    }
    var hex = '';
    for (var i = 0; i < 8; i++) hex += ('00000000' + (h[i] >>> 0).toString(16)).slice(-8);
    return hex;
  }

  /** Le format d'un fichier lu par ses premiers octets (jamais par ce qu'il prétend être). */
  function formatDesOctets(u8) {
    function egal(a, off) { for (var i = 0; i < a.length; i++) if (u8[off + i] !== a[i]) return false; return true; }
    if (egal([0x25, 0x50, 0x44, 0x46, 0x2d], 0)) return 'pdf';
    if (egal([0xff, 0xd8, 0xff], 0)) return 'jpeg';
    if (egal([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0)) return 'png';
    if (egal([0x52, 0x49, 0x46, 0x46], 0) && egal([0x57, 0x45, 0x42, 0x50], 8)) return 'webp';
    return null;
  }

  function depuisBase64(b64) {
    var bin = global.atob(b64), u8 = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    return u8;
  }

  function poids(o) {
    if (o == null) return 'non renseignée';
    return o >= 1024 * 1024 ? (o / 1024 / 1024).toFixed(1).replace('.', ',') + ' Mo' : Math.max(1, Math.round(o / 1024)) + ' Ko';
  }

  function refus(code, motif, geste) { return { ok: false, code: code, motif: motif, geste: geste }; }

  /* ==========================================================================
   * 2. RÉGLAGE : la taille maximale d'un fichier (EF-DOC-2), en base, avec un défaut « à valider »
   * ======================================================================== */
  function tailleMax() {
    var r = S.reglage('documentsBornes', null);
    var v = r && Number(r.tailleMax);
    return v > 0 && isFinite(v) ? Math.min(Math.floor(v), DOC.TAILLE_PLAFOND) : DOC.TAILLE_DEFAUT;
  }
  function tailleMaxReglee() {
    var r = S.reglage('documentsBornes', null);
    return !!(r && Number(r.tailleMax) > 0);
  }
  /* Lot CLO-3 : le réglage est le geste réservé `regler_fichiers` de la fiche RBAC (défaut : administrateur et Directrice Administrative), jamais une liste de rôles écrite ici. */
  function peutRegler() { var s = S.session() || {}, N = global.SIGH.nav; return !!(N && N.droitGeste && N.droitGeste(s.role, 'regler_fichiers')); }
  /** Pose la taille maximale (en octets). Réservé à l'administrateur et à la Directrice Administrative, motivé, borné, journalisé. */
  function definirTailleMax(octets, motif) {
    if (!peutRegler()) return refus('REGLAGE_RESERVE', 'la taille maximale des fichiers se règle par l’administrateur ou la Directrice Administrative', 'Demander le réglage à l’un d’eux.');
    var n = Number(octets);
    if (octets === '' || octets == null || !isFinite(n) || n !== Math.floor(n) || n < DOC.TAILLE_PLANCHER || n > DOC.TAILLE_PLAFOND) {
      return refus('TAILLE_INVALIDE', 'la taille maximale est un nombre entier d’octets, de ' + poids(DOC.TAILLE_PLANCHER) + ' à ' + poids(DOC.TAILLE_PLAFOND), 'Saisir une taille en mégaoctets dans cette plage.');
    }
    if (!String(motif || '').trim()) return refus('MOTIF_REQUIS', 'un réglage de taille se motive', 'Saisir le motif du réglage.');
    var avant = tailleMax();
    S.log('Taille maximale d’un fichier numérisé', 'M14', 'reglage', 'documentsBornes', { tailleMax: avant }, { tailleMax: n, motif: String(motif).slice(0, 60) });
    S.setReglage('documentsBornes', { tailleMax: n, regleLe: new Date().toISOString(), reglePar: S.currentUser() });
    return { ok: true, avant: avant, tailleMax: n };
  }

  /** Le bouton « Taille maximale » : absent sans le droit de régler. */
  function boutonReglage() {
    if (!peutRegler()) return null;
    var K = global.SIGH.kit;
    return K.btn('Taille maximale des fichiers', { icon: 'sliders-horizontal', size: 'sm', onclick: function () { ouvrirReglage(); } });
  }
  function ouvrirReglage() {
    var K = global.SIGH.kit;
    var champ = el('input.input', { type: 'number', min: String(DOC.TAILLE_PLANCHER / 1048576), max: String(DOC.TAILLE_PLAFOND / 1048576), step: '0.1', 'aria-label': 'Taille maximale en mégaoctets' });
    champ.value = String(Math.round(tailleMax() / 104857.6) / 10);
    var motif = el('textarea.textarea', { rows: 2, placeholder: 'Motif du réglage', 'aria-label': 'Motif' });
    var msg = el('p.text-xs.text-danger-700', { role: 'alert' });
    var corps = el('div.space-y-3', null, [
      K.note('Taille maximale d’UN fichier déposé (courrier ou document du dossier patient). ' + (tailleMaxReglee() ? 'Valeur réglée par la clinique.' : 'Valeur de départ de 10 Mo : <strong>à valider</strong> par la Direction.')
        + ' Au delà, le dépôt est refusé en le nommant.', { tone: 'info' }),
      el('div', null, [el('label.label', { text: 'Taille maximale (Mo)' }), champ]),
      el('div', null, [el('label.label', { text: 'Motif (consigné dans le journal)' }), motif]),
      msg,
    ]);
    var m = U.modal({ title: 'Taille maximale des fichiers numérisés', size: 'sm', body: corps, footer: [
      K.btn('Annuler', { onclick: function () { m.close(); } }),
      K.btn('Enregistrer', { variant: 'primary', icon: 'check', onclick: function () {
        var r = definirTailleMax(Math.round(Number(String(champ.value).replace(',', '.')) * 1048576), motif.value);
        if (!r.ok) { msg.textContent = r.motif + ' ' + r.geste; return; }
        m.close();
        U.toast('Taille maximale réglée à ' + poids(r.tailleMax) + '.', { type: 'success', detail: 'Elle s’applique aux prochains dépôts.' });
      } }),
    ] });
  }

  /* ==========================================================================
   * 3. DÉPÔT
   * ======================================================================== */
  /** Contrôle SANS réseau : format (extension ou type déclaré) et taille. Le serveur refait le contrôle sur les octets. */
  function controler(file, famille) {
    var fmt = DOC.formatDe(file.name, file.type, famille);
    if (!fmt) {
      return refus('FORMAT_REFUSE', 'le format de « ' + file.name + ' » n’est pas admis (' + DOC.FORMATS.filter(function (f) { return f.familles.indexOf(famille) >= 0; }).map(function (f) { return f.libelle; }).join(', ') + ')',
        'Enregistrer la numérisation en PDF, JPEG ou PNG' + (famille === 'patient' ? ' (WEBP admis au dossier patient)' : '') + '.');
    }
    if (!file.size) return refus('FICHIER_VIDE', '« ' + file.name + ' » ne contient aucun octet', 'Choisir un fichier numérisé non vide.');
    var max = tailleMax();
    if (file.size > max) {
      return refus('TAILLE_DEPASSEE', 'le fichier pèse ' + poids(file.size) + ', le maximum réglé est ' + poids(max),
        'Numériser en résolution plus basse, ou demander à l’administrateur de relever la taille maximale.');
    }
    return { ok: true, format: fmt };
  }

  function entetesApi() { return { 'X-Sigh-Jeton': S.jetonServeur() || '' }; }
  function urlApi(q) {
    var racine = '';
    try { racine = (global.document.documentElement.getAttribute('data-root')) || ''; } catch (e) { racine = ''; }
    return racine + 'api/fichiers.php?' + q;
  }
  function qs(o) { return Object.keys(o).filter(function (k) { return o[k] != null && o[k] !== ''; }).map(function (k) { return k + '=' + encodeURIComponent(o[k]); }).join('&'); }

  function serveurPret() {
    return !!(S.surServeur && S.surServeur() && S.jetonServeur());
  }
  var REFUS_SANS_SERVEUR = function () {
    return refus('SERVEUR_INJOIGNABLE', 'aucun serveur de fichiers joignable ou aucune session ouverte : un scan ne se range pas dans le magasin du navigateur',
      'Rétablir la connexion au serveur du poste, puis déposer de nouveau le fichier.');
  };

  /** Envoie des octets au serveur et rend sa réponse (empreinte recalculée, pages, texte indexé). */
  function deposerOctets(u8, opts) {
    if (!serveurPret()) return global.Promise.resolve(REFUS_SANS_SERVEUR());
    var sha = opts.sha256 || sha256Octets(u8);
    var url = urlApi(qs({ action: 'deposer', famille: opts.famille, type: opts.type, nom: opts.nom, sha256: sha }));
    return global.fetch(url, { method: 'POST', headers: Object.assign({ 'Content-Type': 'application/octet-stream' }, entetesApi()), body: u8 })
      .then(function (r) { return r.json().catch(function () { return { ok: false, code: 'REPONSE_ILLISIBLE', motif: 'le serveur a répondu hors format', geste: 'Réessayer.' }; }); })
      .catch(function () { return REFUS_SANS_SERVEUR(); });
  }

  /** Relit un fichier du serveur, vérifie son empreinte, rend { ok, u8, url }. */
  function lire(fichier, famille, usage, nom) {
    if (!serveurPret()) return global.Promise.resolve(REFUS_SANS_SERVEUR());
    var url = urlApi(qs({ action: 'lire', sha256: fichier.sha256, famille: famille, usage: usage || 'apercu', nom: nom }));
    return global.fetch(url, { headers: entetesApi() }).then(function (r) {
      if (!r.ok) return r.json().catch(function () { return { code: 'REPONSE_ILLISIBLE', motif: 'le serveur a répondu hors format', geste: 'Réessayer.' }; }).then(function (j) { return { ok: false, code: j.code, motif: j.motif, geste: j.geste }; });
      return r.arrayBuffer().then(function (buf) {
        var u8 = new Uint8Array(buf);
        if (sha256Octets(u8) !== fichier.sha256) {
          return refus('EMPREINTE_RELUE_DIFFERENTE', 'le fichier relu n’a pas l’empreinte de la pièce (' + DOC.abrege(fichier.sha256) + ')', 'Ne pas utiliser cette copie ; redéposer le scan depuis la fiche.');
        }
        return { ok: true, u8: u8, mime: fichier.mime, blob: new global.Blob([u8], { type: fichier.mime || 'application/octet-stream' }) };
      });
    }).catch(function () { return REFUS_SANS_SERVEUR(); });
  }

  /** Où le fichier est rangé sur CE poste (EF-DOC-3b). */
  function chemin(fichier, famille) {
    if (!serveurPret()) return global.Promise.resolve(REFUS_SANS_SERVEUR());
    return global.fetch(urlApi(qs({ action: 'chemin', sha256: fichier.sha256, famille: famille })), { headers: entetesApi() })
      .then(function (r) { return r.json(); })
      .catch(function () { return REFUS_SANS_SERVEUR(); });
  }

  /* --- La collection `fichiers` : un registre par empreinte (taille, première date, références, texte indexé) --------- */
  function colFichiers() { return S.collection('fichiers', { module: 'M13', entite: 'fichier', prefix: 'FIC' }); }
  function normaliserMots(mots) {
    var vus = {}, out = [];
    (mots || []).forEach(function (m) { var n = C.norm(m); if (n.length >= 2 && !vus[n]) { vus[n] = true; out.push(n); } });
    return out.join(' ');
  }
  /** `ctx` : { famille, type } de la fiche qui reçoit la pièce (lot OCR-prep) : un scan sans couche texte entre dans la file de lecture SI un moteur est prêt. */
  function noterFichier(depot, delta, ctx) {
    var col = colFichiers();
    var ex = col.get('FIC-' + depot.sha256.slice(0, 16));
    if (ex) {
      col.update(ex.id, { nbReferences: Math.max(0, (ex.nbReferences || 0) + delta) });
    } else {
      col.insert({ id: 'FIC-' + depot.sha256.slice(0, 16), sha256: depot.sha256, taille: depot.taille, mime: depot.mime, pages: depot.pages || null,
        premiereDate: new Date().toISOString(), nbReferences: Math.max(0, delta), texteIndexe: !!depot.texteIndexe,
        texteSource: depot.texteIndexe ? 'couche_texte' : null,
        texte: depot.texteIndexe ? normaliserMots(depot.mots) : '', motsTronques: !!depot.motsTronques });
    }
    if (delta > 0 && global.SIGH.ocr) global.SIGH.ocr.apresDepot(depot, ctx);
  }
  /** Le texte indexé d'une empreinte (mots normalisés), ou ''. LA COUCHE TEXTE NATIVE PRIME TOUJOURS : l'OCR ne parle que là où le fichier n'en porte pas. `ctx` : { famille, type } pour tenir la zone
   *  (le texte d'un scan de zone 2 est de zone 2 : un profil qui ne lit pas la zone n'en reçoit rien). */
  function texteDe(fichier, ctx) {
    if (!fichier || !fichier.sha256) return '';
    var ex = colFichiers().get('FIC-' + fichier.sha256.slice(0, 16));
    if (ex && ex.texteIndexe) return ex.texte || '';
    if (!global.SIGH.ocr) return '';
    return global.SIGH.ocr.texteLisible(fichier.sha256, ctx && ctx.famille, ctx && ctx.type);
  }

  /** Le fichier de la fiche, ou null. */
  function fichierDe(fiche) { return fiche && fiche.fichier && typeof fiche.fichier === 'object' && fiche.fichier.sha256 ? fiche.fichier : null; }
  /** `numerise` d'un courrier est DÉRIVÉ : vrai quand un fichier est rattaché, jamais saisi. */
  function numerise(fiche) { return !!fichierDe(fiche); }

  /** Le doublon : { memeFiche } refus, ou { autre } avertissement, ou null. `portee(f)` dit si une autre fiche est « la même » (le même dossier patient). */
  function doublon(col, sha, ficheCourante, portee) {
    var memes = col.all().filter(function (f) { var x = fichierDe(f); return f.statut !== 'archive' && x && x.sha256 === sha; });
    for (var i = 0; i < memes.length; i++) {
      var f = memes[i];
      var memeFiche = (ficheCourante && f.id === ficheCourante.id) || (portee && portee(f));
      if (memeFiche) return { memeFiche: f };
    }
    return memes.length ? { autre: memes[0] } : null;
  }
  function nomPiece(f) { var x = fichierDe(f); return (f.reference || f.id) + ' (' + (x ? x.nomNormalise || x.nom : 'sans fichier') + ')'; }

  /** LE GESTE DE DÉPÔT, un seul pour les deux familles. `ctx` : { famille, col, fiche, type, portee, journal:{module,entite,patientId?}, apres(res) }.
   *  Rend une promesse { ok:true, fichier } ou le refus nommé. */
  function deposerSurFiche(file, ctx) {
    var c = controler(file, ctx.famille);
    if (!c.ok) return global.Promise.resolve(c);
    return file.arrayBuffer().then(function (buf) {
      var u8 = new Uint8Array(buf);
      var reel = formatDesOctets(u8);
      if (!reel || reel !== c.format.id) {
        return refus('FORMAT_REFUSE', 'le contenu de « ' + file.name + ' » n’est pas un ' + c.format.libelle + ' (l’extension ne suffit pas)', 'Enregistrer de nouveau la numérisation dans ce format.');
      }
      var sha = sha256Octets(u8);
      var d = doublon(ctx.col, sha, ctx.fiche, ctx.portee);
      if (d && d.memeFiche) {
        return refus('DOUBLON_MEME_FICHE', 'ce fichier est déjà rattaché à ' + (ctx.portee ? 'ce dossier' : 'cette fiche') + ' : pièce ' + nomPiece(d.memeFiche), 'Ouvrir la pièce existante plutôt que de la déposer deux fois.');
      }
      var confirmer = d && d.autre
        ? U.confirm({ title: 'Ce fichier est déjà rattaché ailleurs', message: 'Le même fichier (empreinte ' + DOC.abrege(sha) + ') est déjà la pièce ' + nomPiece(d.autre) + '. Le rattacher aussi à cette fiche ?', confirmLabel: 'Rattacher quand même' })
        : global.Promise.resolve({});
      return confirmer.then(function (ok) {
        if (!ok) return refus('DEPOT_ANNULE', 'dépôt annulé après l’avertissement de doublon', 'Choisir un autre fichier si besoin.');
        return deposerOctets(u8, { famille: ctx.famille, type: ctx.type, nom: file.name, sha256: sha }).then(function (rep) {
          if (!rep || !rep.ok) return refus((rep && rep.code) || 'DEPOT_REFUSE', (rep && rep.motif) || 'le serveur a refusé le fichier', (rep && rep.geste) || 'Réessayer.');
          if (rep.sha256 !== sha) return refus('EMPREINTE_DIVERGENTE', 'le serveur a rangé un fichier d’une autre empreinte', 'Déposer de nouveau le fichier.');
          return { ok: true, depot: rep, nomOrigine: file.name, avertissementDoublon: d && d.autre ? d.autre : null };
        });
      });
    });
  }

  /** Construit l'objet `fichier` de la fiche. */
  function construireFichier(famille, fiche, depot, nomOrigine) {
    return { sha256: depot.sha256, nom: nomOrigine, nomNormalise: DOC.nomNormalise(famille, fiche, depot.ext), mime: depot.mime, taille: depot.taille,
      pages: depot.pages || null, texteIndexe: !!depot.texteIndexe, deposePar: S.currentUser(), deposeLe: new Date().toISOString() };
  }

  /** Rattache un dépôt réussi à une fiche existante (écriture, journal RG-12, registre des empreintes). Rend le résultat de `update`. */
  function rattacher(col, fiche, famille, depot, nomOrigine, journal) {
    var f = construireFichier(famille, fiche, depot, nomOrigine);
    var res = col.update(fiche.id, { fichier: f }, { journal: { action: 'Dépôt d’un fichier numérisé', module: journal.module, entite: journal.entite,
      avant: { fichier: null }, apres: { empreinte: DOC.abrege(depot.sha256), nom: f.nomNormalise, taille: depot.taille } } });
    if (!res) return null;
    noterFichier(depot, 1, { famille: famille, type: famille === 'patient' ? fiche.type : null });
    /* L'ANNULATION DOIT REMETTRE LA FICHE « SANS PIÈCE ». Le magasin annule en réaffectant les valeurs d'AVANT : une clé qui n'existait pas avant (`fichier` d'une fiche jamais numérisée) resterait
       posée. On la remet donc à vide explicitement, et le registre des empreintes suit. */
    return { res: res, fichier: f, undo: function () { res.undo(); col.update(fiche.id, { fichier: null }); noterFichier(depot, -1); } };
  }

  /** Retire la pièce de la fiche (RG-14 : archivage annulable, le fichier reste, l'historique garde l'empreinte). */
  function retirer(col, fiche, famille, motif, journal) {
    var x = fichierDe(fiche);
    if (!x) return null;
    var histo = (fiche.fichiersRetires || []).concat([Object.assign({}, x, { retireLe: new Date().toISOString(), retirePar: S.currentUser(), motif: String(motif || '').slice(0, 200) })]);
    var res = col.update(fiche.id, { fichier: null, fichiersRetires: histo }, { journal: { action: 'Pièce numérisée retirée de la fiche', module: journal.module, entite: journal.entite,
      avant: { empreinte: DOC.abrege(x.sha256), nom: x.nomNormalise }, apres: { fichier: null, motif: String(motif || '').slice(0, 60) } } });
    if (!res) return null;
    noterFichier({ sha256: x.sha256, taille: x.taille, mime: x.mime, pages: x.pages, texteIndexe: x.texteIndexe }, -1);
    var ancien = (fiche.fichiersRetires || []).slice(0, histo.length - 1);
    /* Même précaution : `fichiersRetires` n'existait peut-être pas, l'annulation du magasin ne retire pas une clé ajoutée. L'historique est remis EXPLICITEMENT à ce qu'il était. */
    return { undo: function () { res.undo(); col.update(fiche.id, { fichiersRetires: ancien }); noterFichier({ sha256: x.sha256, taille: x.taille, mime: x.mime, pages: x.pages, texteIndexe: x.texteIndexe }, 1); } };
  }

  /* ==========================================================================
   * 4. JOURNAL RG-12 : consultation et téléchargement (le dépôt est journalisé par l'écriture de la fiche)
   * ======================================================================== */
  function journaliser(action, fiche, fichier, journal) {
    S.journaliserAcces({ action: action, module: journal.module, entite: journal.entite, reference: fiche.reference || fiche.id,
      cible: 'empreinte ' + DOC.abrege(fichier.sha256) + ' (' + (fichier.nomNormalise || fichier.nom) + ')', patientId: journal.patientId || fiche.patientId || null,
      ecran: journal.ecran || null });
  }

  /* ==========================================================================
   * 5. VISIONNEUSE D'IMAGES : écrite pour le projet (réponse Q3), sans dépendance : zoom, rotation, déplacement, ajustement
   * ======================================================================== */
  function visionneuse(url, alt) {
    var etat = { zoom: 1, rot: 0, x: 0, y: 0, ajuste: true };
    var img = el('img.select-none', { src: url, alt: alt || 'Pièce numérisée', draggable: 'false', style: 'transform-origin:center center;max-width:100%;max-height:100%;' });
    var cadre = el('div.relative.flex.h-\\[60vh\\].w-full.items-center.justify-center.overflow-hidden.rounded-lg.border.border-slate-200.bg-slate-50.cursor-grab', { 'data-visionneuse-cadre': '1' });
    cadre.appendChild(img);
    var racine = el('div.space-y-2', { 'data-visionneuse': '1' });
    function appliquer() {
      img.style.transform = 'translate(' + etat.x + 'px,' + etat.y + 'px) rotate(' + etat.rot + 'deg) scale(' + etat.zoom + ')';
      racine.setAttribute('data-zoom', String(Math.round(etat.zoom * 100) / 100));
      racine.setAttribute('data-rotation', String(((etat.rot % 360) + 360) % 360));
      racine.setAttribute('data-ajuste', etat.ajuste ? '1' : '0');
      lib.textContent = Math.round(etat.zoom * 100) + ' %';
    }
    function zoomer(f) { etat.zoom = Math.max(0.1, Math.min(8, etat.zoom * f)); etat.ajuste = false; appliquer(); }
    function bouton(action, libelle, icone, fn) {
      return el('button.btn.btn-secondary.btn-sm', { type: 'button', 'data-action': action, 'aria-label': libelle, title: libelle, onclick: fn }, [C.icon(icone, 'h-4 w-4')]);
    }
    var lib = el('span.num.text-xs.text-slate-500.w-12.text-center');
    var barre = el('div.flex.flex-wrap.items-center.gap-1', null, [
      bouton('zoom-avant', 'Agrandir', 'zoom-in', function () { zoomer(1.25); }),
      bouton('zoom-arriere', 'Réduire', 'zoom-out', function () { zoomer(0.8); }),
      lib,
      bouton('rotation-gauche', 'Tourner à gauche', 'rotate-ccw', function () { etat.rot -= 90; appliquer(); }),
      bouton('rotation-droite', 'Tourner à droite', 'rotate-cw', function () { etat.rot += 90; appliquer(); }),
      bouton('ajuster', 'Ajuster à la fenêtre', 'minimize', function () { etat.zoom = 1; etat.x = 0; etat.y = 0; etat.ajuste = true; appliquer(); }),
      bouton('taille-reelle', 'Taille réelle', 'maximize', function () {
        var nat = img.naturalWidth || 1, aff = img.clientWidth || nat;
        etat.zoom = Math.max(0.1, nat / aff); etat.ajuste = false; appliquer();
      }),
    ]);
    var d0 = null;
    cadre.addEventListener('pointerdown', function (e) { d0 = { x: e.clientX - etat.x, y: e.clientY - etat.y }; try { cadre.setPointerCapture(e.pointerId); } catch (x) { /* sans capture */ } });
    cadre.addEventListener('pointermove', function (e) { if (!d0) return; etat.x = e.clientX - d0.x; etat.y = e.clientY - d0.y; etat.ajuste = false; appliquer(); });
    cadre.addEventListener('pointerup', function () { d0 = null; });
    cadre.addEventListener('wheel', function (e) { e.preventDefault(); zoomer(e.deltaY < 0 ? 1.1 : 0.9); }, { passive: false });
    racine.appendChild(barre);
    racine.appendChild(cadre);
    appliquer();
    racine.etat = etat;
    return racine;
  }

  /* ==========================================================================
   * 6. APERÇU, TÉLÉCHARGEMENT, CHEMIN
   * ======================================================================== */
  function apercu(o) {
    var K = global.SIGH.kit;
    var fichier = fichierDe(o.fiche);
    if (!fichier) return global.Promise.resolve(null);
    var nom = DOC.nomNormalise(o.famille, o.fiche, extDe(fichier));
    var corps = el('div', { 'data-apercu': '1' }, [el('p.text-sm.text-slate-500', { text: 'Chargement de la pièce…' })]);
    var pied = [];
    var m = U.modal({ title: o.titre || 'Pièce numérisée', subtitle: nom, size: 'lg', body: corps, footer: pied.length ? pied : null });
    return lire(fichier, o.famille, 'apercu', nom).then(function (r) {
      C.clear(corps);
      if (!r.ok) { corps.appendChild(el('div', { 'data-apercu-refus': r.code }, [K.note('<strong>' + r.code + '</strong> : ' + r.motif + ' ' + r.geste, { tone: 'warning', icon: 'triangle-alert' })])); return null; }
      var url = global.URL.createObjectURL(r.blob);
      corps.setAttribute('data-apercu-url', url);
      if (fichier.mime === 'application/pdf') {
        corps.appendChild(el('iframe.h-\\[70vh\\].w-full.rounded-lg.border.border-slate-200', { src: url, title: o.titre || 'Pièce numérisée', 'data-apercu-pdf': '1' }));
      } else {
        corps.appendChild(visionneuse(url, o.titre));
      }
      journaliser('Consultation d’un document numérisé', o.fiche, fichier, o.journal);
      return url;
    });
  }

  function extDe(fichier) { return { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }[fichier.mime] || 'bin'; }

  function telecharger(o) {
    var fichier = fichierDe(o.fiche);
    if (!fichier) return global.Promise.resolve(refus('SANS_PIECE', 'cette fiche ne porte aucun fichier', 'Déposer d’abord le scan.'));
    var nom = DOC.nomNormalise(o.famille, o.fiche, extDe(fichier));
    return lire(fichier, o.famille, 'telechargement', nom).then(function (r) {
      if (!r.ok) return r;
      var url = global.URL.createObjectURL(r.blob);
      var a = el('a', { href: url, download: nom });
      a.style.display = 'none';
      global.document.body.appendChild(a);
      a.click();
      global.setTimeout(function () { a.remove(); global.URL.revokeObjectURL(url); }, 4000);
      journaliser('Téléchargement d’un document numérisé', o.fiche, fichier, o.journal);
      global.SIGH.fichiers.dernierTelechargement = { nom: nom, sha256: fichier.sha256, taille: r.u8.length };
      return { ok: true, nom: nom, taille: r.u8.length };
    });
  }

  function copier(texte) {
    try {
      if (global.navigator.clipboard && global.navigator.clipboard.writeText) return global.navigator.clipboard.writeText(texte).then(function () { return true; }, function () { return repliCopie(texte); });
    } catch (e) { /* repli */ }
    return global.Promise.resolve(repliCopie(texte));
  }
  function repliCopie(texte) {
    var t = el('textarea', { 'aria-hidden': 'true' }); t.value = texte; t.style.position = 'fixed'; t.style.opacity = '0';
    global.document.body.appendChild(t); t.select();
    var ok = false; try { ok = global.document.execCommand('copy'); } catch (e) { ok = false; }
    t.remove();
    return ok;
  }

  /* ==========================================================================
   * 7. LA CARTE « PIÈCE NUMÉRISÉE » d'une fiche (courrier ou document patient) et la ZONE D'IMPORT
   * ======================================================================== */
  function zoneImport(o) {
    var K = global.SIGH.kit;
    var accept = DOC.FORMATS.filter(function (f) { return f.familles.indexOf(o.famille) >= 0; }).map(function (f) { return '.' + f.ext.join(',.') + ',' + f.mime; }).join(',');
    var entree = el('input.sr-only', { type: 'file', accept: accept, 'aria-label': 'Fichier numérisé à déposer', 'data-zone-fichier': '1' });
    var msg = el('div', { 'data-zone-message': '1', role: 'status', 'aria-live': 'polite' });
    var zone = el('div.rounded-lg.border-2.border-dashed.border-slate-300.bg-slate-50.p-4.text-center', { 'data-zone-import': o.famille });
    var libelle = el('p.text-sm.text-slate-600', { text: 'Glisser le scan ici, ou choisir un fichier (' + DOC.FORMATS.filter(function (f) { return f.familles.indexOf(o.famille) >= 0; }).map(function (f) { return f.libelle; }).join(', ') + ', ' + poids(tailleMax()) + ' au plus).' });
    var choisir = K.btn('Choisir un fichier', { icon: 'upload', size: 'sm', variant: 'primary', onclick: function () { entree.click(); } });
    zone.appendChild(libelle);
    zone.appendChild(el('div.mt-2', null, choisir));
    zone.appendChild(entree);
    function dire(r) {
      C.clear(msg);
      if (r && r.ok) { return; }
      if (!r) return;
      msg.appendChild(el('div.mt-2', { 'data-refus-code': r.code }, [K.note('<strong>' + r.code + '</strong> : ' + r.motif + ' <em>' + r.geste + '</em>', { tone: 'warning', icon: 'triangle-alert' })]));
    }
    function traiter(file) {
      if (!file) return;
      C.clear(msg);
      msg.appendChild(el('p.mt-2.text-xs.text-slate-500', { text: 'Dépôt de « ' + file.name + ' » (' + poids(file.size) + ')…' }));
      o.traiter(file).then(dire, function (e) { dire(refus('DEPOT_EN_ECHEC', String((e && e.message) || e), 'Réessayer.')); });
    }
    entree.addEventListener('change', function () { var f = entree.files && entree.files[0]; entree.value = ''; traiter(f); });
    ['dragenter', 'dragover'].forEach(function (n) { zone.addEventListener(n, function (e) { e.preventDefault(); zone.classList.add('border-navy-400', 'bg-navy-50'); }); });
    ['dragleave', 'drop'].forEach(function (n) { zone.addEventListener(n, function (e) { e.preventDefault(); zone.classList.remove('border-navy-400', 'bg-navy-50'); }); });
    zone.addEventListener('drop', function (e) { var f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0]; traiter(f); });
    var racine = el('div', null, [zone, msg]);
    racine.traiter = traiter;
    return racine;
  }

  /** La carte de la pièce numérisée dans la fiche. `o` : { famille, col, fiche, titre, journal, peutDeposer, peutRetirer, peutVoir, type, portee, refresh, motifLecture? }. */
  function cartePiece(o) {
    var K = global.SIGH.kit;
    var fichier = fichierDe(o.fiche);
    var corps = el('div.space-y-3', { 'data-carte-piece': o.famille });
    if (!o.peutVoir) {
      corps.appendChild(K.note('Pièce non affichée à votre profil : ' + (o.motifLecture || 'les pièces médicales du dossier ne se lisent que par les profils cliniques (RG-13).'), { tone: 'info', icon: 'lock' }));
      return U.card('Pièce numérisée', corps);
    }
    if (fichier) {
      var lignes = [
        ['Nom de téléchargement', el('span.font-mono.text-xs', { text: DOC.nomNormalise(o.famille, o.fiche, extDe(fichier)), 'data-piece-nom': '1' })],
        ['Fichier d’origine', fichier.nom],
        ['Format', (fichier.mime || '').replace('application/', '').replace('image/', '').toUpperCase() + ' · ' + poids(fichier.taille) + (fichier.pages ? ' · ' + fichier.pages + ' page' + (fichier.pages > 1 ? 's' : '') : '')],
        ['Empreinte SHA-256', el('span.font-mono.text-xs', { text: DOC.abrege(fichier.sha256) + '…', title: fichier.sha256, 'data-piece-empreinte': '1' })],
        ['Recherche dans le texte', global.SIGH.ocr ? global.SIGH.ocr.ligneEtat(fichier) : (fichier.texteIndexe ? U.badge('Texte indexé', 'success') : U.badge('Texte non indexé', 'neutral'))],
        ['Déposé', (fichier.deposePar || 'auteur inconnu') + ', le ' + C.dateFR(String(fichier.deposeLe || '').slice(0, 10))],
      ];
      corps.appendChild(U.descList(lignes));
      if (global.SIGH.ocr) {
        if (!fichier.texteIndexe) corps.appendChild(global.SIGH.ocr.blocCarte({ fichier: fichier, famille: o.famille, type: o.type || o.fiche.type || null, peutDeposer: !!o.peutDeposer, refresh: o.refresh }));
      } else if (!fichier.texteIndexe) corps.appendChild(el('p.text-xs.text-slate-500', { text: 'Texte non indexé : la recherche par le contenu ne trouve pas cette pièce (image sans couche texte). Elle reste retrouvable par ses données de fiche.' }));
      var actes = el('div.flex.flex-wrap.items-center.gap-2');
      actes.appendChild(K.btn('Aperçu', { icon: 'eye', size: 'sm', onclick: function () { apercu({ famille: o.famille, fiche: o.fiche, titre: o.titre, journal: o.journal }); } }));
      actes.appendChild(K.btn('Télécharger', { icon: 'download', size: 'sm', onclick: function () {
        telecharger({ famille: o.famille, fiche: o.fiche, journal: o.journal }).then(function (r) {
          if (!r.ok) U.toast('Téléchargement refusé : ' + r.code, { type: 'error', detail: r.motif + ' ' + r.geste });
        });
      } }));
      if (o.peutRetirer) {
        actes.appendChild(K.btn('Retirer la pièce', { icon: 'archive', size: 'sm', variant: 'danger', onclick: function () {
          U.confirm({ title: 'Retirer la pièce de la fiche ?', message: 'La pièce est retirée de la fiche, non supprimée (RG-14) : le fichier et son empreinte restent conservés, l’opération est journalisée et annulable.',
            confirmLabel: 'Retirer', danger: true, requireMotif: true }).then(function (ok) {
            if (!ok) return;
            var r = retirer(o.col, o.fiche, o.famille, ok.motif, o.journal);
            if (!r) { U.toast('Retrait impossible.', { type: 'error' }); return; }
            if (o.refresh) o.refresh();
            U.toast('Pièce retirée de la fiche.', { type: 'success', undo: function () { r.undo(); if (o.refresh) o.refresh(); } });
          });
        } }));
      }
      corps.appendChild(actes);
      /* REMPLACER la pièce (un mauvais scan) : le même fichier est refusé en nommant la pièce existante (doublon sur la MÊME fiche) ; un autre fichier prend la place et l'ancien est RETIRÉ
         de la fiche, jamais supprimé (RG-14 : il reste au disque, son empreinte au journal et à l'historique de la fiche). */
      if (o.peutDeposer) {
        var det = el('details.rounded-lg.border.border-slate-200.p-2', { 'data-remplacer': '1' });
        det.appendChild(el('summary.cursor-pointer.text-sm.text-slate-700', { text: 'Remplacer la pièce par un autre fichier' }));
        det.appendChild(el('div.mt-2', null, zoneImport({ famille: o.famille, traiter: function (file) {
          return deposerSurFiche(file, { famille: o.famille, col: o.col, fiche: o.fiche, type: o.type, portee: o.portee, journal: o.journal }).then(function (r) {
            if (!r.ok) return r;
            var ret = retirer(o.col, o.fiche, o.famille, 'Remplacée par un autre fichier', o.journal);
            var rat = rattacher(o.col, o.col.get(o.fiche.id), o.famille, r.depot, r.nomOrigine, o.journal);
            if (!rat) { if (ret) ret.undo(); return refus('ECRITURE_REFUSEE', 'la fiche n’a pas pu recevoir la nouvelle pièce', 'Vérifier les droits sur cet écran.'); }
            if (o.refresh) o.refresh();
            U.toast('Pièce remplacée.', { type: 'success', detail: rat.fichier.nomNormalise, undo: function () { rat.undo(); if (ret) ret.undo(); if (o.refresh) o.refresh(); } });
            return { ok: true };
          });
        } })));
        corps.appendChild(det);
      }
      /* Le chemin du fichier sur CE poste, ou la mention qu'il n'est pas encore arrivé. */
      var ch = el('div.rounded-lg.bg-slate-50.p-2.text-xs.text-slate-600', { 'data-piece-chemin': '1' }, [el('span', { text: 'Chemin sur ce poste : recherche…' })]);
      corps.appendChild(ch);
      chemin(fichier, o.famille).then(function (r) {
        C.clear(ch);
        if (!r || r.ok === false) { ch.appendChild(el('span', { text: 'Chemin indisponible : ' + ((r && r.motif) || 'serveur injoignable') + '.' })); return; }
        if (!r.present) { ch.setAttribute('data-piece-chemin-etat', 'absent'); ch.appendChild(el('span', { text: 'Fichier pas encore reçu sur ce poste.' })); return; }
        ch.setAttribute('data-piece-chemin-etat', 'present');
        ch.appendChild(el('span', { text: 'Chemin sur ce poste : ' }));
        ch.appendChild(el('span.font-mono.break-all', { text: r.chemin, 'data-piece-chemin-valeur': '1' }));
        ch.appendChild(K.btn('Copier le chemin', { icon: 'copy', size: 'sm', onclick: function () {
          copier(r.chemin).then(function (ok) { U.toast(ok ? 'Chemin copié.' : 'Copie impossible : sélectionner le chemin à la main.', { type: ok ? 'success' : 'warning' }); });
        } }));
        U.icons(ch);
      });
    } else {
      corps.appendChild(el('p.text-sm.text-slate-600', { text: 'Aucune pièce numérisée rattachée à cette fiche.' }));
      if (o.peutDeposer) {
        corps.appendChild(zoneImport({ famille: o.famille, traiter: function (file) {
          return deposerSurFiche(file, { famille: o.famille, col: o.col, fiche: o.fiche, type: o.type, portee: o.portee, journal: o.journal }).then(function (r) {
            if (!r.ok) return r;
            var rat = rattacher(o.col, o.fiche, o.famille, r.depot, r.nomOrigine, o.journal);
            if (!rat) return refus('ECRITURE_REFUSEE', 'la fiche n’a pas pu recevoir la pièce', 'Vérifier les droits sur cet écran.');
            if (o.refresh) o.refresh();
            U.toast('Pièce numérisée rattachée.', { type: 'success', detail: rat.fichier.nomNormalise, undo: function () { rat.undo(); if (o.refresh) o.refresh(); } });
            return { ok: true };
          });
        } }));
      } else {
        corps.appendChild(K.note('Votre profil consulte cette fiche sans pouvoir y déposer de pièce.', { tone: 'info' }));
      }
    }
    if ((o.fiche.fichiersRetires || []).length) {
      corps.appendChild(U.descList(o.fiche.fichiersRetires.map(function (x, i) {
        return ['Pièce retirée ' + (i + 1), (x.nomNormalise || x.nom) + ' · empreinte ' + DOC.abrege(x.sha256) + ' · retirée par ' + (x.retirePar || 'auteur inconnu') + ', motif : ' + (x.motif || 'non renseigné')];
      })));
    }
    var carte = U.card('Pièce numérisée', corps);
    U.icons(carte);
    return carte;
  }

  /* ==========================================================================
   * 8. MIGRATION du base64 de `documentsPatient` vers le dossier de fichiers (D1)
   * --------------------------------------------------------------------------
   * Pour chaque fiche qui porte encore `donnees` : déposer les octets, RELIRE le fichier rangé et comparer son empreinte AVANT de retirer le base64. Une copie qui ne
   * relit pas à l'identique n'autorise rien : la fiche garde son base64 et la migration le dit (code, fiche). Jamais de base64 retiré sur la foi de la seule réponse du dépôt.
   * ======================================================================== */
  function migrerBase64() {
    var col = S.collection('documentsPatient', { module: 'M1', entite: 'document', prefix: 'DOC' });
    var aMigrer = col.all().filter(function (d) { return typeof d.donnees === 'string' && d.donnees.indexOf('data:') === 0 && !fichierDe(d); });
    var rapport = { candidats: aMigrer.length, migres: 0, refuses: [] };
    if (!aMigrer.length) return global.Promise.resolve(rapport);
    if (!serveurPret()) { rapport.refuses.push({ reference: null, code: 'SERVEUR_INJOIGNABLE' }); return global.Promise.resolve(rapport); }
    var chaine = global.Promise.resolve();
    aMigrer.forEach(function (d) {
      chaine = chaine.then(function () {
        var virgule = d.donnees.indexOf(',');
        var u8;
        try { u8 = depuisBase64(d.donnees.slice(virgule + 1)); } catch (e) { rapport.refuses.push({ reference: d.reference, code: 'BASE64_ILLISIBLE' }); return null; }
        var sha = sha256Octets(u8);
        return deposerOctets(u8, { famille: 'patient', type: d.type, nom: typeof d.fichier === 'string' ? d.fichier : d.reference, sha256: sha }).then(function (rep) {
          if (!rep || !rep.ok) { rapport.refuses.push({ reference: d.reference, code: (rep && rep.code) || 'DEPOT_REFUSE' }); return null; }
          return lire({ sha256: sha, mime: rep.mime }, 'patient', 'migration', null).then(function (relu) {
            /* LA VÉRIFICATION D'EMPREINTE AVANT RETRAIT : `lire` rend ok:false si l'empreinte de la copie relue diffère. */
            if (!relu.ok) { rapport.refuses.push({ reference: d.reference, code: relu.code || 'RELECTURE_REFUSEE' }); return null; }
            var f = construireFichier('patient', d, rep, typeof d.fichier === 'string' ? d.fichier : d.reference);
            f.deposePar = d.depose || f.deposePar;
            col.update(d.id, { fichier: f, donnees: null }, { journal: { action: 'Fichier migré du magasin vers le dossier de fichiers', module: 'M1', entite: 'document',
              avant: { base64Octets: u8.length }, apres: { empreinte: DOC.abrege(sha), verifiee: true } } });
            noterFichier(rep, 1, { famille: 'patient', type: d.type });
            rapport.migres++;
            return null;
          });
        });
      });
    });
    return chaine.then(function () { return rapport; });
  }

  global.SIGH.fichiers = {
    sha256Octets: sha256Octets, formatDesOctets: formatDesOctets, depuisBase64: depuisBase64, poids: poids,
    tailleMax: tailleMax, tailleMaxReglee: tailleMaxReglee, peutRegler: peutRegler, definirTailleMax: definirTailleMax, boutonReglage: boutonReglage,
    controler: controler, deposerOctets: deposerOctets, deposerSurFiche: deposerSurFiche, rattacher: rattacher, retirer: retirer,
    lire: lire, chemin: chemin, apercu: apercu, telecharger: telecharger, visionneuse: visionneuse, zoneImport: zoneImport, cartePiece: cartePiece,
    fichierDe: fichierDe, numerise: numerise, doublon: doublon, texteDe: texteDe, noterFichier: noterFichier, colFichiers: colFichiers, extDe: extDe,
    fichierPour: construireFichier, migrerBase64: migrerBase64, copier: copier, dernierTelechargement: null,
  };
})(window);
