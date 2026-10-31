/* Moteur du mobile (prototype) : état local simulé, navigation, composants. Les écrans sont dans ecrans.js.
   L'état vit dans localStorage sous le préfixe « sighm: » : il est partagé entre les écrans d'un même téléphone simulé
   et avec le simulateur (index.php) — c'est ce qui fait qu'une saisie faite hors ligne apparaît à l'écran Synchronisation. */
(function (global) {
  'use strict';
  var M = global.SIGHM_MANIFESTE;
  var PREFIXE = 'sighm:';
  var q = new URLSearchParams(global.location.search);

  function lire(k, defaut) { try { var v = global.localStorage.getItem(PREFIXE + k); return v == null ? defaut : JSON.parse(v); } catch (e) { return defaut; } }
  function ecrire(k, v) { try { global.localStorage.setItem(PREFIXE + k, JSON.stringify(v)); } catch (e) { /* stockage refusé : l écran fonctionne sans mémoire */ } }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', '\'': '&#39;' }[c]; }); }

  var ctx = { os: q.get('os') === 'android' ? 'android' : 'ios', profil: q.get('profil') || lire('profil', 'soignant'), p: q.get('p') };
  if (!M.PROFILS[ctx.profil]) ctx.profil = 'soignant';
  ecrire('profil', ctx.profil);

  function lien(id, extra) {
    var u = id + '.php?os=' + ctx.os + '&profil=' + ctx.profil;
    Object.keys(extra || {}).forEach(function (k) { u += '&' + k + '=' + encodeURIComponent(extra[k]); });
    return u;
  }
  function entree(id) { return M.ECRANS.filter(function (e) { return e.id === id; })[0]; }
  function ouvert(id) { var e = entree(id); return !!e && e.profils.indexOf(ctx.profil) >= 0; }

  /* --- file d'envoi : en attente → acceptée dès que le réseau est là --------------------------------------------- */
  function enLigne() { return lire('reseau', 'en-ligne') === 'en-ligne'; }
  function file() { return lire('file', []); }
  function vider() {
    if (!enLigne()) return;
    var f = file(), change = false;
    f.forEach(function (o) { if (o.etat === 'en_attente') { o.etat = 'acceptee'; o.accuse = Date.now(); change = true; } });
    if (change) ecrire('file', f);
  }
  function enfiler(type, libelle, detail) {
    var f = file();
    f.unshift({ id: 'op-' + Date.now().toString(36), type: type, libelle: libelle, detail: detail || '', quand: Date.now(), etat: 'en_attente', profil: ctx.profil });
    ecrire('file', f);
    if (enLigne()) setTimeout(function () { vider(); majBandeau(); }, 1200);
    majBandeau();
    return f[0];
  }
  function dossiers() { return lire('dossiers', []); }
  function ajouterDossier(d) { var l = dossiers(); l.unshift(d); ecrire('dossiers', l); }
  function prochainCode() {
    var p = lire('plage', { prochain: 1241, fin: 1243 });
    if (p.prochain > p.fin) return { code: 'PROV-' + (lire('prov', 0) + 1), provisoire: true };
    return { code: 'CNT/' + p.prochain + '/26', provisoire: false };
  }
  function consommerCode() {
    var p = lire('plage', { prochain: 1241, fin: 1243 });
    if (p.prochain > p.fin) { ecrire('prov', lire('prov', 0) + 1); return; }
    p.prochain++; ecrire('plage', p);
  }

  /* --- composants ---------------------------------------------------------------------------------------------------- */
  function icone(n) { return '<i data-lucide="' + n + '"></i>'; }
  function badge(t, ton) { return '<span class="badge ' + (ton || '') + '">' + esc(t) + '</span>'; }
  function note(html, ton, ic) { return '<div class="note ' + (ton || '') + '">' + icone(ic || 'info') + '<div>' + html + '</div></div>'; }
  function carte(titre, html, classe) { return '<section class="carte ' + (classe || '') + '">' + (titre ? '<h2>' + esc(titre) + '</h2>' : '') + html + '</section>'; }
  function item(o) {
    var t = '<div class="pastille">' + icone(o.icone || 'circle') + '</div><div class="texte"><div class="titre">' + esc(o.titre) + '</div>' + (o.detail ? '<div class="detail">' + o.detail + '</div>' : '') + '</div>' + (o.fin ? '<div class="fin">' + o.fin + '</div>' : '<div class="fin">' + icone('chevron-right') + '</div>');
    return o.href ? '<a class="item" href="' + o.href + '">' + t + '</a>' : '<div class="item">' + t + '</div>';
  }
  function liste(items) { return '<div class="carte liste">' + items.join('') + '</div>'; }
  function vide(ic, texte) { return '<div class="vide">' + icone(ic) + esc(texte) + '</div>'; }
  function champ(id, label, o) {
    o = o || {};
    var ctrl;
    if (o.type === 'select') ctrl = '<select id="' + id + '">' + o.options.map(function (x) { return '<option value="' + esc(x) + '">' + esc(x) + '</option>'; }).join('') + '</select>';
    else if (o.type === 'textarea') ctrl = '<textarea id="' + id + '" placeholder="' + esc(o.ph || '') + '"></textarea>';
    else ctrl = '<input id="' + id + '" type="' + (o.type || 'text') + '"' + (o.inputmode ? ' inputmode="' + o.inputmode + '"' : '') + ' placeholder="' + esc(o.ph || '') + '"' + (o.valeur != null ? ' value="' + esc(o.valeur) + '"' : '') + '>';
    return '<label class="champ" data-champ="' + id + '"><span>' + esc(label) + (o.requis ? ' <em>*</em>' : '') + '</span>' + ctrl + '<div class="erreur" hidden></div></label>';
  }
  function valeur(id) { var e = global.document.getElementById(id); return e ? e.value.trim() : ''; }
  function erreur(id, msg) {
    var c = global.document.querySelector('[data-champ="' + id + '"]'); if (!c) return;
    c.classList.toggle('invalide', !!msg); var e = c.querySelector('.erreur'); e.hidden = !msg; e.textContent = msg || '';
  }
  /* Valide une liste de règles { id, requis, nombre:[min,max], libelle } ; rend true si tout est bon. Une valeur hors
     bornes est REFUSÉE EN LA NOMMANT : mieux vaut une erreur ici qu une valeur absurde au dossier. */
  function valider(regles) {
    var ok = true;
    regles.forEach(function (r) {
      var v = valeur(r.id), m = '';
      if (r.requis && !v) m = r.libelle + ' obligatoire.';
      else if (v && r.nombre) {
        var n = Number(v.replace(',', '.'));
        if (isNaN(n)) m = r.libelle + ' doit être un nombre.';
        else if (n < r.nombre[0] || n > r.nombre[1]) m = r.libelle + ' : valeur improbable (' + r.nombre[0] + ' à ' + r.nombre[1] + ').';
      }
      erreur(r.id, m); if (m) ok = false;
    });
    return ok;
  }
  function toast(msg) {
    var t = global.document.createElement('div'); t.className = 'toast'; t.textContent = msg; global.document.getElementById('app').appendChild(t);
    setTimeout(function () { t.remove(); }, 2600);
  }
  function hms() { var d = new Date(); return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2); }
  function il(ts) { var m = Math.round((Date.now() - ts) / 60000); return m < 1 ? 'à l’instant' : (m < 60 ? 'il y a ' + m + ' min' : 'il y a ' + Math.round(m / 60) + ' h'); }

  /* --- montage ------------------------------------------------------------------------------------------------------- */
  var SCREENS = {};
  function bandeauHtml() {
    if (lire('suspendu', false)) return '<div class="bandeau suspendu" id="bandeau">' + icone('ban') + 'Téléphone suspendu — contactez la clinique</div>';
    var n = file().filter(function (o) { return o.etat === 'en_attente'; }).length;
    return enLigne() ? '<div class="bandeau en-ligne" id="bandeau">' + icone('wifi') + 'Connecté' + (n ? ' · ' + n + ' en cours d’envoi' : '') + '</div>'
      : '<div class="bandeau hors" id="bandeau">' + icone('wifi-off') + 'Hors ligne' + (n ? ' · ' + n + ' en attente d’envoi' : ' · vos saisies sont conservées') + '</div>';
  }
  function majBandeau() {
    var b = global.document.getElementById('bandeau'); if (!b) return;
    var nouveau = global.document.createElement('div'); nouveau.innerHTML = bandeauHtml();
    b.replaceWith(nouveau.firstChild); if (global.lucide) global.lucide.createIcons();
  }
  function statutHtml() {
    var ios = ctx.os === 'ios';
    return '<div class="statut"><span>' + hms() + '</span><span class="droite">' + (ios ? icone('signal') + icone('wifi') + icone('battery-full') : icone('wifi') + icone('signal') + icone('battery-full')) + '</span></div>';
  }
  function ongletsHtml(id) {
    var accueil = M.PROFILS[ctx.profil].accueil;
    var t = [[accueil, 'house', 'Accueil'], ['sync', 'refresh-cw', 'Synchro'], ['a-traiter', 'octagon-alert', 'À traiter'], ['parametres', 'settings', 'Réglages']];
    return '<nav class="onglets">' + t.map(function (x) { return '<a href="' + lien(x[0]) + '" class="' + (x[0] === id ? 'actif' : '') + '">' + icone(x[1]) + x[2] + '</a>'; }).join('') + '</nav>';
  }
  function mount(id) {
    var e = entree(id), app = global.document.getElementById('app');
    global.document.body.classList.toggle('android', ctx.os === 'android');
    var def = SCREENS[id];
    var html;
    if (!e || !def) html = '<div class="contenu">' + vide('circle-help', 'Écran inconnu.') + '</div>';
    else if (!ouvert(id) && !e.avantSession) {
      /* Une commande refusée est ABSENTE ; un écran refusé se NOMME, il ne s ouvre pas à moitié. */
      html = '<header class="barre"><h1>' + esc(e.label) + '</h1></header><div class="contenu">' + note('Écran <strong>fermé au profil « ' + esc(M.PROFILS[ctx.profil].label) + ' »</strong>. Ce profil ne couvre pas cette fonction ; la clinique le refuserait aussi côté serveur.', 'err', 'lock') + '<a class="btn sec" href="' + lien(M.PROFILS[ctx.profil].accueil) + '">Retour à l’accueil</a></div>';
    } else {
      var r = def(ctx) || {};
      var retour = r.retour ? '<a class="retour" href="' + lien(r.retour, r.retourExtra) + '">' + icone('chevron-left') + '</a>' : '';
      html = '<header class="barre"><div class="ligne">' + retour + '<div><h1>' + esc(r.titre || e.label) + '</h1>' + (r.sous ? '<div class="sous">' + esc(r.sous) + '</div>' : '') + '</div></div></header>'
        + (e.avantSession ? '' : bandeauHtml()) + '<main class="contenu">' + (r.html || '') + '</main>' + (r.sansOnglets || e.avantSession ? '' : ongletsHtml(id));
      app.innerHTML = statutHtml() + html + '<div class="geste"></div>';
      if (global.lucide) global.lucide.createIcons();
      if (r.apres) r.apres();
      return;
    }
    app.innerHTML = statutHtml() + html + '<div class="geste"></div>';
    if (global.lucide) global.lucide.createIcons();
  }
  /* Le simulateur (ou un autre écran) change le réseau : on le répercute tout de suite. */
  global.addEventListener('storage', function (ev) { if (ev.key === PREFIXE + 'reseau') { vider(); majBandeau(); } if (ev.key === PREFIXE + 'file') majBandeau(); });
  global.addEventListener('message', function (ev) { if (ev.data && ev.data.sighm === 'reseau') { ecrire('reseau', ev.data.valeur); vider(); majBandeau(); } });
  vider();

  global.SIGHM = {
    ctx: ctx, lire: lire, ecrire: ecrire, esc: esc, lien: lien, entree: entree, enLigne: enLigne, file: file, enfiler: enfiler, vider: vider,
    dossiers: dossiers, ajouterDossier: ajouterDossier, prochainCode: prochainCode, consommerCode: consommerCode,
    icone: icone, badge: badge, note: note, carte: carte, item: item, liste: liste, vide: vide, champ: champ, valeur: valeur, erreur: erreur, valider: valider,
    toast: toast, il: il, hms: hms, ecran: function (id, f) { SCREENS[id] = f; }, mount: mount, aller: function (id, extra) { global.location.href = lien(id, extra); },
  };
})(window);
