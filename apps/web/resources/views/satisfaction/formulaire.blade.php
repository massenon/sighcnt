<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>{{ $charge['titre'] ?? 'Votre avis' }}</title>
<style>
{!! file_get_contents(public_path('css/jetons.css')) !!}
:root{--fond:var(--navy-50);--carte:white;--texte:var(--navy-950);--doux:var(--navy-700);--accent:var(--navy-900);--accent-texte:white;--bord:var(--navy-500);--erreur:var(--danger-700)}
@media (prefers-color-scheme:dark){:root{--fond:var(--navy-950);--carte:var(--navy-900);--texte:var(--navy-50);--doux:var(--navy-200);--accent:var(--navy-200);--accent-texte:var(--navy-950);--bord:var(--navy-400);--erreur:var(--danger-200)}}
*{box-sizing:border-box}
body{font-family:var(--police-sans);margin:0;padding:1rem;background:var(--fond);color:var(--texte);line-height:1.5}
main{max-width:36rem;margin:0 auto;background:var(--carte);border-radius:12px;padding:1.25rem;box-shadow:var(--ombre-card)}
h1{font-size:1.35rem;margin:0 0 .5rem}
.mention{font-size:.9rem;color:var(--doux);border-left:3px solid var(--accent);padding-left:.75rem;margin:.75rem 0 1.25rem}
fieldset{border:0;padding:0;margin:0 0 1.25rem}
legend{font-weight:600;margin-bottom:.5rem;padding:0}
.rangee{display:flex;flex-wrap:wrap;gap:.5rem}
.rangee label,.liste label{display:inline-flex;align-items:center;justify-content:center;min-width:2.75rem;min-height:2.75rem;padding:.25rem .75rem;border:1px solid var(--bord);border-radius:8px;cursor:pointer}
.liste label{display:flex;justify-content:flex-start;margin-bottom:.4rem;gap:.5rem}
input[type=radio]{position:absolute;opacity:0;width:1px;height:1px}
input[type=radio]:checked+span,label:has(input:checked){background:var(--accent);color:var(--accent-texte);border-color:var(--accent)}
label:has(input:focus-visible){outline:3px solid var(--accent);outline-offset:2px}
textarea{width:100%;min-height:5rem;padding:.5rem;border:1px solid var(--bord);border-radius:8px;background:var(--carte);color:var(--texte);font:inherit}
.bornes{display:flex;justify-content:space-between;font-size:.8rem;color:var(--doux);margin-top:.25rem}
button{width:100%;min-height:3rem;border:0;border-radius:10px;background:var(--accent);color:var(--accent-texte);font:inherit;font-weight:600;cursor:pointer}
button[disabled]{opacity:.6;cursor:wait}
#message{margin-top:1rem;min-height:1.5rem}
.erreur{color:var(--erreur)}
.piege{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
</style>
</head>
<body>
<main>
<h1>{{ $charge['titre'] ?? 'Votre avis' }}</h1>
@if(!empty($charge['intro']))<p>{{ $charge['intro'] }}</p>@endif
<p class="mention" id="mention">Ce questionnaire est ANONYME : il ne demande ni votre nom, ni un numéro de dossier, et aucune question ne porte sur votre santé. Votre réponse est chiffrée dans votre navigateur avant d’être envoyée : l’hébergeur ne peut pas la lire. Elle sert à améliorer l’accueil et les soins de la clinique et se conserve trois ans.</p>
<form id="formulaire" novalidate>
<div id="questions"></div>
<div class="piege" aria-hidden="true"><label>Ne pas remplir<input type="text" id="piege" name="site_web" tabindex="-1" autocomplete="off"></label></div>
<button type="submit" id="envoyer">Envoyer ma réponse</button>
<div id="message" role="status" aria-live="polite"></div>
</form>
</main>
<script>
(function () {
  'use strict';
  var CHARGE = {!! \Illuminate\Support\Js::from($charge) !!};
  var CLE = {!! \Illuminate\Support\Js::from($cle) !!};
  var BUCKETS = [1024, 2048, 4096, 8192];
  var enc = new TextEncoder();
  function b64e(u8) { var s = ''; for (var i = 0; i < u8.length; i++) s += String.fromCharCode(u8[i]); return btoa(s); }
  function b64d(s) { var b = atob(s), u = new Uint8Array(b.length); for (var i = 0; i < b.length; i++) u[i] = b.charCodeAt(i); return u; }
  function hex(u8) { return Array.prototype.map.call(u8, function (x) { return ('0' + x.toString(16)).slice(-2); }).join(''); }
  function concat(a, b) { var u = new Uint8Array(a.length + b.length); u.set(a, 0); u.set(b, a.length); return u; }

  /* L'enveloppe : X25519 éphémère, HKDF-SHA-256 (sel = clé éphémère puis clé de la clinique), AES-256-GCM, le texte clair rembourré à 1, 2, 4 ou 8 Kio. */
  async function sceller(cleClinique, donnees, id) {
    var pub = b64d(cleClinique);
    var eph = await crypto.subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);
    var epk = new Uint8Array(await crypto.subtle.exportKey('raw', eph.publicKey));
    var clinique = await crypto.subtle.importKey('raw', pub, { name: 'X25519' }, false, []);
    var secret = await crypto.subtle.deriveBits({ name: 'X25519', public: clinique }, eph.privateKey, 256);
    var ikm = await crypto.subtle.importKey('raw', secret, 'HKDF', false, ['deriveKey']);
    var cle = await crypto.subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt: concat(epk, pub), info: enc.encode('sigh-satisfaction-v1') }, ikm, { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
    var clair = enc.encode(JSON.stringify(donnees));
    var taille = 0;
    for (var i = 0; i < BUCKETS.length; i++) { if (clair.length + 2 <= BUCKETS[i]) { taille = BUCKETS[i]; break; } }
    if (!taille) throw new Error('trop_long');
    var rembourre = new Uint8Array(taille);
    rembourre[0] = (clair.length >> 8) & 255; rembourre[1] = clair.length & 255;
    rembourre.set(clair, 2);
    var iv = crypto.getRandomValues(new Uint8Array(12));
    var ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv, additionalData: enc.encode(id) }, cle, rembourre));
    return { v: 1, id: id, epk: b64e(epk), iv: b64e(iv), ct: b64e(ct) };
  }
  window.__sceller = sceller;

  var zone = document.getElementById('questions');
  var message = document.getElementById('message');
  function el(nom, attrs, texte) { var e = document.createElement(nom); for (var k in (attrs || {})) e.setAttribute(k, attrs[k]); if (texte != null) e.textContent = texte; return e; }
  function groupe(q, valeurs, classe) {
    var f = el('fieldset'); f.appendChild(el('legend', {}, q.libelle + (q.obligatoire === false ? ' (facultatif)' : '')));
    var c = el('div', { 'class': classe });
    valeurs.forEach(function (v) {
      var l = el('label'); var i = el('input', { type: 'radio', name: q.code, value: String(v) });
      l.appendChild(i); l.appendChild(el('span', {}, String(v))); c.appendChild(l);
    });
    f.appendChild(c); return f;
  }
  (CHARGE.questions || []).forEach(function (q) {
    var f;
    if (q.type === 'note') { f = groupe(q, [1, 2, 3, 4, 5], 'rangee'); var b = el('div', { 'class': 'bornes' }); b.appendChild(el('span', {}, '1 : pas du tout satisfait')); b.appendChild(el('span', {}, '5 : très satisfait')); f.appendChild(b); }
    else if (q.type === 'nps') { f = groupe(q, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 'rangee'); }
    else if (q.type === 'choix') { f = groupe(q, q.options || [], 'liste'); }
    else { f = el('fieldset'); var lg = el('label', { 'for': 'q_' + q.code, style: 'font-weight:600;display:block;margin-bottom:.5rem;min-height:0;border:0;padding:0' }, q.libelle + (q.obligatoire ? '' : ' (facultatif)')); f.appendChild(lg); f.appendChild(el('textarea', { id: 'q_' + q.code, name: q.code, maxlength: '1000' })); }
    zone.appendChild(f);
  });

  function lire() {
    var rep = {}, manque = [];
    (CHARGE.questions || []).forEach(function (q) {
      var v;
      if (q.type === 'texte') { v = (document.getElementById('q_' + q.code).value || '').trim(); }
      else { var c = document.querySelector('input[name="' + q.code + '"]:checked'); v = c ? c.value : ''; }
      if (v === '') { if (q.obligatoire !== false && q.type !== 'texte') manque.push(q.libelle); return; }
      rep[q.code] = (q.type === 'note' || q.type === 'nps') ? Number(v) : v;
    });
    return { rep: rep, manque: manque };
  }
  var idReponse = hex(crypto.getRandomValues(new Uint8Array(16)));
  document.getElementById('formulaire').addEventListener('submit', async function (ev) {
    ev.preventDefault();
    var bouton = document.getElementById('envoyer');
    var l = lire();
    message.className = '';
    if (l.manque.length) { message.className = 'erreur'; message.textContent = 'Merci de répondre à : ' + l.manque.join(' ; '); return; }
    if (!Object.keys(l.rep).length) { message.className = 'erreur'; message.textContent = 'Merci de répondre à au moins une question.'; return; }
    bouton.disabled = true; message.textContent = 'Envoi en cours…';
    try {
      var donnees = { id: idReponse, enquete: CHARGE.enquete, version: CHARGE.version, point: CHARGE.point && CHARGE.point.code, langue: 'fr', reponses: l.rep };
      var env = await sceller(CLE, donnees, idReponse);
      env.piege = document.getElementById('piege').value;
      var r = await fetch(location.pathname, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(env), credentials: 'omit', referrerPolicy: 'no-referrer' });
      if (r.status === 429) throw new Error('debit');
      if (!r.ok) throw new Error('refus');
      document.getElementById('formulaire').replaceWith(el('p', { id: 'merci', role: 'status' }, 'Merci, votre réponse a bien été enregistrée.'));
    } catch (e) {
      bouton.disabled = false; message.className = 'erreur';
      message.textContent = e.message === 'debit' ? 'Trop de réponses envoyées depuis cette connexion. Réessayez dans quelques minutes.'
        : (e.name === 'NotSupportedError' || e.name === 'TypeError' && !window.crypto) ? 'Ce navigateur ne sait pas chiffrer la réponse : mettez-le à jour ou utilisez un autre navigateur.'
        : 'L’envoi a échoué. Vérifiez la connexion et réessayez : la même réponse ne sera comptée qu’une fois.';
    }
  });
})();
</script>
</body>
</html>
