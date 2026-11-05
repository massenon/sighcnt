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

  /* Le dernier état de chaque fiche d'une collection, du rang le plus ancien au plus récent : une copie plus récente remplace la précédente. */
  function fichesDe(charges, collection) {
    var out = {};
    /* Une charge est une fiche {collection, fiche, data, archive} OU un lot {lot: [fiches…]} (copie consolidée de la mère). */
    var plat = [];
    charges.forEach(function (c) { if (c && Array.isArray(c.lot)) c.lot.forEach(function (x) { plat.push(x); }); else plat.push(c); });
    plat.forEach(function (c) { if (c && c.collection === collection) out[c.fiche] = c; });
    return Object.keys(out).map(function (k) { return out[k]; });
  }

  racine.SighConsultation = { importerCle: importerCle, dechiffrer: dechiffrer, chiffrerCle: chiffrerCle, dechiffrerCle: dechiffrerCle, fichesDe: fichesDe, octetsDeCle: octetsDeCle };
})(typeof window !== 'undefined' ? window : globalThis);
