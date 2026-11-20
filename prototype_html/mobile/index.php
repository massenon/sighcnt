<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Simulateur mobile — SIGH-CNT</title>
  <link rel="icon" href="../assets/img/logo.jpeg">
  <link rel="stylesheet" href="mobile.css">
  <script src="../assets/js/vendor/lucide.min.js"></script>
  <script src="manifeste.js"></script>
</head>
<body>
<div class="sim">
  <aside>
    <h1>Simulateur mobile</h1>
    <div style="font-size:12px;color:var(--ink-2)">SIGH-CNT · prototype de l’application mobile (Flutter). Même design system que la maquette.</div>
    <h3>Appareil</h3>
    <div class="seg" id="seg-app"></div>
    <h3>Profil connecté</h3>
    <div class="seg" id="seg-profil"></div>
    <h3>Réseau</h3>
    <div class="seg" id="seg-reseau"></div>
    <h3>Écrans du profil</h3>
    <div id="liste"></div>
    <h3>Simulation</h3>
    <div style="font-size:12px;color:var(--ink-2)">Saisissez hors ligne, puis repassez « En ligne » : la file d’envoi se vide et les accusés arrivent. Un écran fermé au profil reste <b>visible mais grisé</b> (jamais caché).</div>
    <button class="btn sec petit" id="raz" style="margin-top:10px">Remettre le téléphone à zéro</button>
  </aside>
  <main id="scene"></main>
</div>
<script>
(function () {
  var M = window.SIGHM_MANIFESTE, P = 'sighm:';
  var etat = { appareil: 'iphone', profil: localStorage.getItem(P + 'profil') ? JSON.parse(localStorage.getItem(P + 'profil')) : 'soignant', ecran: null, reseau: 'en-ligne' };
  try { etat.reseau = JSON.parse(localStorage.getItem(P + 'reseau') || '"en-ligne"'); } catch (e) { /* par défaut */ }
  if (!M.PROFILS[etat.profil]) etat.profil = 'soignant';
  etat.ecran = M.PROFILS[etat.profil].accueil;

  function boutons(cible, items, actif, onclick) {
    var c = document.getElementById(cible); c.innerHTML = '';
    items.forEach(function (it) { var b = document.createElement('button'); b.textContent = it[1]; if (it[0] === actif) b.className = 'actif'; b.onclick = function () { onclick(it[0]); }; c.appendChild(b); });
  }
  function url(os) { return 'ecrans/' + etat.ecran + '.php?os=' + (os === 'iphone' ? 'ios' : 'android') + '&profil=' + etat.profil; }
  function appareil(cle) {
    var d = M.DEVICES[cle], coque = document.createElement('div'); coque.className = 'appareil';
    var pad = d.ios ? 12 : 10;
    coque.innerHTML = '<div class="coque ' + cle + '"><div class="ecran-vitre" style="width:' + d.w + 'px;height:' + d.h + 'px">' + (d.ios ? '<div class="ile"></div>' : '<div class="trou"></div>')
      + '<iframe title="' + d.label + '" width="' + d.w + '" height="' + d.h + '" src="' + url(cle) + '"></iframe></div></div><div class="legende">' + d.label + ' · ' + d.w + ' × ' + d.h + ' · ' + d.os + '</div>';
    return coque;
  }
  function peindre() {
    var scene = document.getElementById('scene'); scene.innerHTML = '';
    (etat.appareil === 'les-deux' ? ['iphone', 'pixel'] : [etat.appareil]).forEach(function (c) { scene.appendChild(appareil(c)); });
    boutons('seg-app', [['iphone', 'iPhone 14'], ['pixel', 'Pixel 8'], ['les-deux', 'Les deux']], etat.appareil, function (v) { etat.appareil = v; peindre(); });
    boutons('seg-profil', Object.keys(M.PROFILS).map(function (k) { return [k, M.PROFILS[k].label]; }), etat.profil, function (v) { etat.profil = v; localStorage.setItem(P + 'profil', JSON.stringify(v)); etat.ecran = M.PROFILS[v].accueil; peindre(); });
    boutons('seg-reseau', [['en-ligne', 'En ligne'], ['hors-ligne', 'Hors ligne']], etat.reseau, function (v) {
      etat.reseau = v; localStorage.setItem(P + 'reseau', JSON.stringify(v));
      Array.prototype.forEach.call(document.querySelectorAll('iframe'), function (f) { try { f.contentWindow.postMessage({ sighm: 'reseau', valeur: v }, '*'); } catch (e) { /* cadre pas prêt */ } });
      peindre();
    });
    var l = document.getElementById('liste'); l.innerHTML = ''; var groupe = '';
    M.ECRANS.forEach(function (e) {
      var ouvert = e.profils.indexOf(etat.profil) >= 0;
      if (e.groupe !== groupe) { groupe = e.groupe; var g = document.createElement('div'); g.style.cssText = 'font-size:11px;color:var(--ink-3);margin:8px 0 2px;text-transform:uppercase'; g.textContent = groupe; l.appendChild(g); }
      var b = document.createElement('button'); b.className = 'ecran' + (e.id === etat.ecran ? ' actif' : '') + (ouvert ? '' : ' ferme'); b.innerHTML = '<i data-lucide="' + e.icone + '"></i>' + e.label + (ouvert ? '' : ' <span style="margin-left:auto;font-size:11px">fermé</span>');
      b.title = ouvert ? '' : 'Fermé au profil « ' + M.PROFILS[etat.profil].label + ' »';
      b.onclick = function () { etat.ecran = e.id; peindre(); }; l.appendChild(b);
    });
    if (window.lucide) window.lucide.createIcons();
  }
  document.getElementById('raz').onclick = function () { Object.keys(localStorage).filter(function (k) { return k.indexOf(P) === 0; }).forEach(function (k) { localStorage.removeItem(k); }); etat.reseau = 'en-ligne'; peindre(); };
  peindre();
})();
</script>
</body>
</html>
