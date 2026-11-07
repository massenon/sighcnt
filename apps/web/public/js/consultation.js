/* CONSULTATION DES COPIES (PRD relais consultable, option B) : TOUT le chiffrement se fait ICI, dans le navigateur (Web Crypto). Le serveur n'importe aucune
   fonction de chiffrement et ne reçoit jamais la clé de clinique ni la phrase secrète. Format des enveloppes = celui des postes :
   nonce de 12 octets, ct = chiffré || étiquette GCM de 16 octets, données authentifiées (AAD) = « id|appareil|dir|n ». */
(function (racine) {
  'use strict';
  var enc = new TextEncoder(), dec = new TextDecoder();

  function deBase64(s) { var b = atob(s), o = new Uint8Array(b.length); for (var i = 0; i < b.length; i++) o[i] = b.charCodeAt(i); return o; }
  function enBase64(o) { var s = ''; for (var i = 0; i < o.length; i++) s += String.fromCharCode(o[i]); return btoa(s); }

  /* La clé de clinique se saisit en hexadécimal (64 caractères) ou en base64 (32 octets) ; toute autre forme est refusée en le disant. */
  function octetsDeCle(texte) {
    var t = String(texte || '').trim();
    if (/^[0-9a-fA-F]{64}$/.test(t)) { var o = new Uint8Array(32); for (var i = 0; i < 32; i++) o[i] = parseInt(t.substr(i * 2, 2), 16); return o; }
    try { var b = deBase64(t); if (b.length === 32) return b; } catch (e) { /* tombe sur le refus */ }
    throw new Error('Clé invalide : 64 caractères hexadécimaux ou 32 octets en base64 attendus.');
  }

  function importerCle(texte) { return racine.crypto.subtle.importKey('raw', octetsDeCle(texte), { name: 'AES-GCM' }, false, ['decrypt']); }

  /* Déchiffre UNE enveloppe ; une enveloppe déplacée, rejouée sous un autre rang ou altérée échoue (GCM + AAD). */
  async function dechiffrer(env, cle) {
    var brut = deBase64(env.ct);
    var clair = await racine.crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: deBase64(env.nonce), additionalData: enc.encode(env.id + '|' + env.appareil + '|' + env.dir + '|' + env.n), tagLength: 128 }, cle, brut);
    return JSON.parse(dec.decode(clair));
  }

  /* Récupération de la clé par courriel : la clé n'est JAMAIS stockée en clair. Elle est chiffrée ICI par une phrase secrète (PBKDF2-SHA256, AES-GCM) ;
     le serveur ne garde et n'envoie que ce coffre, inutile sans la phrase. */
  var ITERATIONS = 310000;
  async function cleDePhrase(phrase, sel, iterations, usages) {
    var base = await racine.crypto.subtle.importKey('raw', enc.encode(phrase), 'PBKDF2', false, ['deriveKey']);
    return racine.crypto.subtle.deriveKey({ name: 'PBKDF2', salt: sel, iterations: iterations, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, usages);
  }
  async function chiffrerCle(cleTexte, phrase) {
    if (String(phrase || '').length < 12) throw new Error('La phrase secrète doit faire 12 caractères au moins.');
    var cle = octetsDeCle(cleTexte), sel = racine.crypto.getRandomValues(new Uint8Array(16)), nonce = racine.crypto.getRandomValues(new Uint8Array(12));
    var k = await cleDePhrase(phrase, sel, ITERATIONS, ['encrypt']);
    var ct = new Uint8Array(await racine.crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: enc.encode('cle-clinique-v1'), tagLength: 128 }, k, cle));
    return { v: 1, kdf: 'PBKDF2-SHA256', iter: ITERATIONS, sel: enBase64(sel), nonce: enBase64(nonce), ct: enBase64(ct) };
  }
  async function dechiffrerCle(coffre, phrase) {
    var k = await cleDePhrase(phrase, deBase64(coffre.sel), coffre.iter, ['decrypt']);
    var clair = await racine.crypto.subtle.decrypt({ name: 'AES-GCM', iv: deBase64(coffre.nonce), additionalData: enc.encode('cle-clinique-v1'), tagLength: 128 }, k, deBase64(coffre.ct));
    return Array.prototype.map.call(new Uint8Array(clair), function (x) { return ('0' + x.toString(16)).slice(-2); }).join('');
  }

  /* L'ORDRE D'UNE VERSION : [nOps, hlc, appareil, id] (voir packages/sync_dart/lib/src/ordre_copie.dart). Sans `ordre` (ancienne enveloppe) = la plus ancienne.
     Total et indépendant de l'ordre de lecture : une version plus ancienne qui arrive après une plus récente ne la remplace jamais. */
  function comparerOrdre(a, b) {
    if (!a && !b) return 0; if (!a) return -1; if (!b) return 1;
    for (var i = 0; i < 4; i++) { if (a[i] < b[i]) return -1; if (a[i] > b[i]) return 1; }
    return 0;
  }
  /* Deux versions de même ordre (ou sans ordre) : départage déterministe par le contenu, jamais par l'ordre de lecture. */
  function plusRecente(x, y) {
    var c = comparerOrdre(x.ordre, y.ordre);
    if (c !== 0) return c > 0 ? x : y;
    return JSON.stringify(x.data) + (x.archive ? '1' : '0') >= JSON.stringify(y.data) + (y.archive ? '1' : '0') ? x : y;
  }
  /* Range UNE charge (fiche seule ou lot) dans la table {collection/fiche → version retenue}. Rend le nombre de fiches modifiées. */
  function retenir(table, charge) {
    var plat = charge && Array.isArray(charge.lot) ? charge.lot : [charge], n = 0;
    plat.forEach(function (c) {
      if (!c || !c.collection) return;
      var k = c.collection + '/' + c.fiche, d = table[k], v = d ? plusRecente(d, c) : c;
      if (v !== d) { table[k] = v; n++; }
    });
    return n;
  }
  /* Les fiches d'une collection : la version retenue de chacune, dans un ordre stable (par identifiant), quel que soit l'ordre des charges. */
  function fichesDe(charges, collection) {
    var table = {};
    charges.forEach(function (c) { retenir(table, c); });
    return Object.keys(table).filter(function (k) { return table[k].collection === collection; }).sort().map(function (k) { return table[k]; });
  }
  /* Déchiffre les enveloppes PAR LOTS en rendant la main au navigateur entre deux lots : la page reste utilisable pendant un gros chargement. [surLot](n) rend compte. */
  async function dechiffrerParLots(enveloppes, cle, table, surLot, taille) {
    taille = taille || 200;
    for (var i = 0; i < enveloppes.length; i += taille) {
      var lot = enveloppes.slice(i, i + taille);
      var clairs = await Promise.all(lot.map(function (e) { return dechiffrer(e, cle); }));
      clairs.forEach(function (c) { retenir(table, c); });
      if (surLot) surLot(Math.min(i + taille, enveloppes.length), enveloppes.length);
      await new Promise(function (r) { setTimeout(r, 0); });
    }
  }

  racine.SighConsultation = { importerCle: importerCle, dechiffrer: dechiffrer, chiffrerCle: chiffrerCle, dechiffrerCle: dechiffrerCle, fichesDe: fichesDe, retenir: retenir, comparerOrdre: comparerOrdre, dechiffrerParLots: dechiffrerParLots, octetsDeCle: octetsDeCle };
})(typeof window !== 'undefined' ? window : globalThis);
