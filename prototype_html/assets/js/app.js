/* =============================================================================
 * SIGH-CNT — Coquille applicative
 * -----------------------------------------------------------------------------
 * Amorce chaque page : contrôle de session, méga-menu horizontal filtré par
 * rôle (RBAC), barre supérieure (recherche globale, plein écran, notifications,
 * profil), en-tête de page avec fil d'Ariane et actions rapides, puis montage
 * du contenu déclaré par la page.
 *
 * Une page se déclare ainsi :
 *   SIGH.page({ id:'m1-patients', render: function (root) { … } })
 * Tous les liens sont dérivés du manifeste `nav.js` : aucun lien en dur.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, N = global.SIGH.nav, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data;
  var el = C.el, $ = C.$;
  var PAGE = null;

  /* --- Résolution des liens ----------------------------------------------- */
  function base() { return document.documentElement.getAttribute('data-root') || ''; }
  /**
   * href('cfg-tarifs', { onglet: 'actes' }) — un lien peut viser une rubrique
   * précise d'un écran. La recherche globale s'en sert pour ouvrir la page ET
   * l'onglet concerné : chercher « actes » doit mener au bon tableau, pas
   * seulement à la bonne page.
   */
  function href(id, opts) {
    var e = N.get(id);
    if (!e) return base() + 'pages/error-404' + N.EXT;
    var u = id === 'index' ? base() + 'index' + N.EXT : base() + 'pages/' + e.id + N.EXT;
    /* Tous les paramètres, et non le seul onglet : une page qui remplace une
       modale reçoit ici le contexte que la modale tenait de son appelant. */
    return u + C.ancre(opts);
  }
  /* Toute navigation programmatique replie le méga-menu. C'est ici qu'il faut
     le faire, et non sur chaque bouton : go() est le point de passage obligé,
     les boutons des tableaux de bord ne sont pas des ancres et échappaient
     donc à la délégation posée sur les liens. Le drapeau reste à usage unique :
     la préférence durable de l'utilisateur n'est jamais écrasée. */
  function go(id, opts) {
    try { S.storage.set(RUBAN_TRANSIT, '1'); } catch (e) { /* stockage indisponible */ }
    if (naviguerSansRecharger(id, opts)) return;
    global.location.href = href(id, opts);
  }

  /* ==========================================================================
   * NAVIGATION SANS RECHARGEMENT (vague 69)
   * --------------------------------------------------------------------------
   * Le document reste le même d'un écran à l'autre : le magasin n'est pas
   * re-téléchargé, les scripts ne sont pas ré-évalués. Quatre garanties :
   *  - le module de l'écran visé se charge À LA DEMANDE, une seule fois ;
   *  - tout ce que l'écran précédent a posé (écouteurs du document, minuteries,
   *    tiroirs, modales, messages) est DÉMONTÉ avant de peindre le suivant ;
   *  - l'adresse change (pushState) : le retour arrière et les liens profonds
   *    gardent leur sens ;
   *  - au moindre doute — pas de session, écran autonome, module introuvable,
   *    fichier ouvert en local — on RECHARGE comme avant. Le repli est la règle.
   * ======================================================================== */
  var NETTOYAGES = [];
  var _spaOccupe = false;
  var _spaChargés = {};
  /** Pose un écouteur que le démontage retirera. */
  function ecoute(cible, ev, fn, opts) {
    cible.addEventListener(ev, fn, opts);
    NETTOYAGES.push(function () { cible.removeEventListener(ev, fn, opts); });
  }
  function enDernier(fn) { NETTOYAGES.push(fn); }
  function demonter() {
    var racine = document.getElementById('page-content');
    if (racine) { try { racine.dispatchEvent(new Event('sigh:unmount')); } catch (e) { /* sans importance */ } }
    var nets = NETTOYAGES; NETTOYAGES = [];
    nets.forEach(function (n) { try { n(); } catch (e) { /* un nettoyage ne bloque pas les autres */ } });
    Array.prototype.slice.call(document.body.children).forEach(function (n) {
      if (n.tagName !== 'SCRIPT') document.body.removeChild(n);
    });
  }
  function spaPermise() {
    if (global.__SIGH_SANS_SPA || _spaOccupe) return false;
    if (global.location.protocol === 'file:') return false;
    try { if (S.storage.get('sigh-cnt:spa') === 'off') return false; } catch (e) { /* stockage indisponible */ }
    return !!(PAGE && !PAGE.standalone && S.session() && global.fetch && global.history && global.history.pushState);
  }
  function chargerScript(src) {
    if (_spaChargés[src]) return _spaChargés[src];
    _spaChargés[src] = new Promise(function (ok, ko) {
      var deja = Array.prototype.some.call(document.scripts, function (x) { return x.src && x.src.replace(/\?.*$/, '').slice(-src.length) === src; });
      if (deja) return ok();
      var sc = document.createElement('script');
      sc.src = base() + src; sc.async = false;
      sc.onload = function () { ok(); };
      sc.onerror = function () { delete _spaChargés[src]; ko(new Error('module introuvable : ' + src)); };
      document.body.appendChild(sc);
    });
    return _spaChargés[src];
  }
  /** Le fichier de module d'un écran se lit dans SA page engendrée : une seule source (gen-pages). */
  function fichiersDeModule(id) {
    return global.fetch(href(id), { credentials: 'same-origin' }).then(function (r) {
      if (!r.ok) throw new Error('page ' + id + ' : ' + r.status);
      return r.text();
    }).then(function (html) {
      var out = [], re = /assets\/js\/(modules\/[\w-]+\.js)/g, m;
      while ((m = re.exec(html))) out.push(m[1]);
      return out;
    });
  }
  function ecranEntier(id, opts, pousser) {
    var entry = N.get(id);
    return fichiersDeModule(id).then(function (fichiers) {
      return fichiers.reduce(function (p, f) { return p.then(function () { return chargerScript('assets/js/' + f); }); }, Promise.resolve());
    }).then(function () {
      var def = SCREENS[id];
      if (def && def.standalone) throw new Error('écran autonome');
      if (!N.can(S.session().role, entry)) throw new Error('accès refusé');
      demonter();
      PAGE = null; _boote = false;
      if (pousser) global.history.pushState({ sigh: id }, '', href(id, opts));
      global.scrollTo(0, 0);
      monterVraiment(id);
      boot();
      return true;
    });
  }
  function naviguerSansRecharger(id, opts) {
    var entry = N.get(id);
    if (!entry || id === 'index' || !spaPermise()) return false;
    if (/^(auth-|error-|enquete-publique)/.test(id)) return false;
    _spaOccupe = true;
    ecranEntier(id, opts, true).then(function () { _spaOccupe = false; }, function (e) {
      _spaOccupe = false;
      if (global.console && global.console.warn) global.console.warn('[SIGH] Navigation sans rechargement impossible, rechargement :', e);
      global.location.href = href(id, opts);
    });
    return true;
  }
  function idDeLien(a) {
    var m = /\/pages\/([\w-]+)\.[a-z]+(?:[?#].*)?$/i.exec(a.pathname + (a.hash || ''));
    return m && N.get(m[1]) ? m[1] : null;
  }
  function optsDeLien(a) {
    var h = (a.hash || '').replace(/^#/, ''), o = {};
    h.split('&').forEach(function (kv) { var p = kv.split('='); if (p[0]) o[decodeURIComponent(p[0])] = decodeURIComponent(p[1] || ''); });
    return o;
  }
  /* Retour / avance du navigateur : l'écran de l'adresse revient, sans rechargement. */
  global.addEventListener('popstate', function (ev) {
    if (!(ev.state && ev.state.sigh) || !spaPermise()) return;
    _spaOccupe = true;
    ecranEntier(ev.state.sigh, optsDeLien(global.location), false).then(function () { _spaOccupe = false; }, function () {
      _spaOccupe = false; global.location.reload();
    });
  });

  /* --- Session ------------------------------------------------------------ */
  function requireSession() {
    var s = S.session();
    if (s && s.role && N.ROLES[s.role]) return s;
    /* Profil par défaut : le prototype reste explorable sans passer par le login. */
    var demo = { role: 'admin', nom: 'BASSONGUI Chabi Séko', poste: 'Directeur Médical', demo: true };
    S.setSession(demo);
    return demo;
  }

  /* ==========================================================================
   * MÉGA-MENU HORIZONTAL — présentation « ruban »
   * --------------------------------------------------------------------------
   * La navigation occupe le haut de l'écran, à la manière du ruban de Microsoft
   * Word : une barre de marque, une rangée d'onglets (les domaines
   * fonctionnels) et un grand panneau horizontal qui déploie les modules du
   * domaine en colonnes, chaque écran portant son icône.
   *
   * Le panneau est OUVERT PAR DÉFAUT, positionné sur le domaine de l'écran
   * courant. Un clic sur l'onglet actif le replie, un clic sur un autre onglet
   * le déplie sur ce domaine ; l'état est mémorisé d'un écran à l'autre, comme
   * le fait Word.
   * ======================================================================== */
  var RUBAN_KEY = 'sigh-cnt:ruban';
  /* Drapeau à usage unique posé au clic sur un lien du méga-menu : la page
     suivante s'ouvre panneau replié, puis le drapeau est consommé. Il ne touche
     pas à RUBAN_KEY — la préférence de l'utilisateur survit à la navigation. */
  /* ==========================================================================
   * VERROUILLAGE APRÈS INACTIVITÉ
   * --------------------------------------------------------------------------
   * Les postes de l'accueil et de la caisse sont partagés et restent ouverts
   * sur un dossier patient. Quinze minutes sans activité, et l'écran se
   * verrouille (CDCT §12.2).
   *
   * Deux exigences, dont la seconde est celle qui rend le dispositif
   * acceptable :
   *   — la session n'est PAS fermée : elle est suspendue. On ne déconnecte
   *     pas quelqu'un qui s'est absenté deux minutes de trop ;
   *   — au déverrouillage, l'utilisateur RETROUVE l'écran qu'il avait, à
   *     l'onglet près. Le retour à l'accueil ferait perdre le travail en
   *     cours, et le verrouillage serait désactivé dès la première semaine.
   * ======================================================================== */
  var VERROU_RETOUR = 'sigh-cnt:verrou-retour';
  var VERROU_DELAI = 'sigh-cnt:verrou-delai';
  var VERROU_DELAI_DEFAUT = 15 * 60 * 1000;

  function delaiVerrou() {
    var v = Number(S.storage.get(VERROU_DELAI));
    return v > 0 ? v : VERROU_DELAI_DEFAUT;
  }

  /** Arme la surveillance d'inactivité sur la page courante. */
  function armerVerrou(entry) {
    if (!entry || entry.standalone) return;
    var minuteur = null;
    function verrouiller() {
      var s2 = S.session();
      if (!s2) return;
      /* L'adresse complète, ancre comprise : c'est elle qui porte l'onglet. */
      S.storage.set(VERROU_RETOUR, global.location.pathname.split('/').pop() + global.location.hash);
      S.log('Verrouillage pour inactivité', 'M14', 'Session', s2.identifiant || s2.nom,
        null, { ecran: entry.id, delaiMinutes: Math.round(delaiVerrou() / 60000) });
      global.location.href = href('auth-lock');
    }
    function relancer() {
      if (minuteur) global.clearTimeout(minuteur);
      minuteur = global.setTimeout(verrouiller, delaiVerrou());
    }
    ['mousedown', 'keydown', 'touchstart', 'scroll', 'focus'].forEach(function (ev) {
      ecoute(global, ev, relancer, { passive: true, capture: true });
    });
    enDernier(function () { if (minuteur) global.clearTimeout(minuteur); });
    relancer();
  }

  var RUBAN_TRANSIT = 'sigh-cnt:ruban-transitoire';
  function replierApresNavigation() { S.storage.set(RUBAN_TRANSIT, '1'); }
  function rubanOuvert() {
    if (S.storage.get(RUBAN_TRANSIT)) { S.storage.remove(RUBAN_TRANSIT); return false; }
    var choix = S.storage.get(RUBAN_KEY);
    if (choix === 'ferme') return false;
    if (choix === 'ouvert') return true;
    /* Sans preference enregistree : deploye sur un poste de travail, replie
       sur telephone ou tablette en portrait, ou il occuperait la moitie de
       l ecran avant meme de commencer a travailler. */
    return (global.innerWidth || 1280) >= 768;
  }
  function setRubanOuvert(v) { S.storage.set(RUBAN_KEY, v ? 'ouvert' : 'ferme'); }

  /**
   * Un module = une rangée du ruban : son intitulé à gauche (qui ouvre la page
   * d'accueil du module), ses écrans à droite sous forme de pastilles qui
   * s'enroulent. Cette disposition en lignes tient en deux ou trois hauteurs de
   * texte là où des colonnes occupaient le tiers de l'écran.
   */
  function buildRangee(mod, currentId, alertes) {
    var r = el('div.ribbon-row');

    var head = el('a.ribbon-row-head', {
      href: href(mod.hub), title: 'Accueil du module ' + mod.label,
    }, [
      C.icon(mod.icon, 'h-4 w-4 shrink-0 text-navy-700'),
      el('span.truncate', { text: mod.label }),
    ]);
    var n = alertes[mod.code];
    if (n) {
      head.appendChild(el('span.shrink-0.rounded-full.bg-danger-500.px-1\\.5.py-0\\.5.text-\\[10px\\].font-semibold.text-white', {
        text: String(n), title: n + ' alerte(s) en cours',
      }));
    }
    r.appendChild(head);

    var chips = el('div.ribbon-chips');
    mod.items.forEach(function (it) {
      var a = el('a.ribbon-chip', { href: href(it.id), title: it.label }, [
        C.icon(it.icon || mod.icon, 'h-3.5 w-3.5 shrink-0'),
        el('span.truncate', { text: it.label }),
      ]);
      if (it.id === currentId) { a.classList.add('ribbon-chip-active'); a.setAttribute('aria-current', 'page'); }
      chips.appendChild(a);
    });
    r.appendChild(chips);
    return r;
  }

  /** Raccourcis permanents vers les quatre postes de travail les plus utilisés. */
  function buildRaccourcis(session) {
    var box = el('div.hidden.items-center.gap-1.border-l.border-white\\/10.pl-2.lg\\:flex');
    N.RACCOURCIS.forEach(function (r) {
      var mod = N.module(r.code);
      if (!mod || !N.can(session.role, { roles: mod.roles, module: mod.code })) return;
      box.appendChild(el('a.ribbon-shortcut', { href: href(mod.hub), title: mod.label }, [
        C.icon(mod.icon, 'h-4 w-4 shrink-0'),
        el('span.hidden.truncate.xl\\:block', { text: r.court }),
      ]));
    });
    return box.children.length ? box : null;
  }

  function buildMenubar(session, currentId) {
    var header = el('header#app-menubar.no-print.sticky.top-0.z-40.bg-navy-950.shadow-lg');
    header.appendChild(buildTopbar(session));

    var arbre = N.tree(session.role);
    if (!arbre.length) return header;

    var entry = N.get(currentId);
    var domaineCourant = (entry && arbre.some(function (d) { return d.domain === entry.domain; }))
      ? entry.domain : null;
    var actif = domaineCourant || arbre[0].domain;
    var alertes = computeBadges();

    var panneau = el('div#app-ribbon.border-b.border-slate-200.bg-white', {
      hidden: !rubanOuvert(), role: 'tabpanel', 'aria-label': 'Navigation du domaine',
    });
    var onglets = el('div.flex.min-w-0.flex-1.items-center.gap-0\\.5.overflow-x-auto', {
      role: 'tablist', 'aria-label': 'Domaines fonctionnels',
    });
    var boutons = {};
    var chev = C.icon('chevron-up', 'h-4 w-4 transition-transform');
    var replier = el('button.ribbon-tool', {
      type: 'button', 'aria-controls': 'app-ribbon',
      onclick: function () { basculer(!panneau.hidden ? false : true); },
    }, chev);

    function peindre() {
      var ouvert = !panneau.hidden;
      Object.keys(boutons).forEach(function (k) {
        boutons[k].classList.toggle('ribbon-tab-active', k === actif && ouvert);
        /* Le domaine de la page affichée reste signalé même panneau replié :
           sinon, sur un écran de sous-menu, plus aucun onglet n'est marqué. */
        boutons[k].classList.toggle('ribbon-tab-current', k === domaineCourant);
        boutons[k].setAttribute('aria-current', k === domaineCourant ? 'true' : 'false');
        boutons[k].setAttribute('aria-selected', k === actif ? 'true' : 'false');
        boutons[k].setAttribute('aria-expanded', k === actif && ouvert ? 'true' : 'false');
      });
      chev.style.transform = ouvert ? '' : 'rotate(180deg)';
      replier.title = ouvert ? 'Réduire le menu' : 'Afficher le menu';
      replier.setAttribute('aria-label', replier.title);
      replier.setAttribute('aria-expanded', ouvert ? 'true' : 'false');
    }

    function afficher(nom) {
      actif = nom;
      C.clear(panneau);
      var domaine = arbre.filter(function (d) { return d.domain === nom; })[0];
      var corps = el('div.mx-auto.w-full.max-w-\\[100rem\\].max-h-\\[55vh\\].overflow-y-auto.px-2.py-1.md\\:max-h-\\[40vh\\]');
      domaine.modules.forEach(function (mod) { corps.appendChild(buildRangee(mod, currentId, alertes)); });
      panneau.appendChild(corps);
      U.icons(panneau);
      peindre();
    }

    function basculer(ouvrir, memoriser) {
      panneau.hidden = !ouvrir;
      if (memoriser !== false) setRubanOuvert(ouvrir);
      if (ouvrir) afficher(actif); else peindre();
    }

    arbre.forEach(function (d) {
      var b = el('button.ribbon-tab', { type: 'button', role: 'tab' }, [
        C.icon(d.icon, 'h-4 w-4 shrink-0'),
        el('span.truncate', { text: d.domain }),
      ]);
      b.addEventListener('click', function () {
        if (actif === d.domain && !panneau.hidden) { basculer(false); return; }
        actif = d.domain;
        if (panneau.hidden) basculer(true); else afficher(d.domain);
      });
      boutons[d.domain] = b;
      onglets.appendChild(b);
    });

    /* Un lien choisi, le menu s'efface : le panneau se replie immédiatement et
       la page appelée s'ouvrira sans lui (FR-SYS-02). */
    panneau.addEventListener('click', function (e) {
      var lien = e.target && e.target.closest ? e.target.closest('a[href]') : null;
      if (!lien || !panneau.contains(lien)) return;
      replierApresNavigation();
      basculer(false, false);
    });

    var barre = el('div.flex.items-center.gap-2.border-t.border-white\\/10.px-2', null, [
      onglets,
      buildRaccourcis(session),
      el('a.ribbon-tool.hidden.sm\\:inline-flex', { href: href('plan-du-site'), title: 'Plan du site' },
        C.icon('map', 'h-4 w-4')),
      replier,
    ]);
    header.appendChild(barre);
    header.appendChild(panneau);

    if (!panneau.hidden) afficher(actif); else peindre();

    /* Le menu s'efface dès que la lecture commence : en descendant dans la
       page, le panneau se replie de lui-même et rend toute la hauteur au
       contenu. Ce repli automatique ne modifie pas la préférence enregistrée. */
    var dernierY = 0;
    ecoute(global, 'scroll', function () {
      var y = global.scrollY || document.documentElement.scrollTop || 0;
      if (y > 120 && y > dernierY && !panneau.hidden) basculer(false, false);
      dernierY = y;
    }, { passive: true });

    /* Échap referme le panneau — sauf si une boîte de dialogue est ouverte,
       auquel cas la touche lui revient. */
    ecoute(document, 'keydown', function (e) {
      if (e.key !== 'Escape' || panneau.hidden) return;
      if (document.querySelector('[role="dialog"]')) return;
      basculer(false);
    });

    return header;
  }

  /** Compteurs d'alerte affichés sur les groupes du méga-menu. */
  function computeBadges() {
    var out = {};
    try {
      var lots = S.collection('lots').active();
      out.M6 = lots.filter(function (l) { return l.statut === 'perime' || l.statut === 'alerte'; }).length;
      var fac = S.collection('factures').active();
      out.M9 = fac.filter(function (f) { return f.assureur && f.statutPaiement !== 'soldee'; }).length;
      out.MECEF = fac.filter(function (f) { return f.statutMecef === 'rejete' || f.statutMecef === 'en_attente'; }).length;
    } catch (e) { /* les badges ne doivent jamais bloquer le rendu */ }
    return out;
  }

  /* ==========================================================================
   * TOPBAR
   * ======================================================================== */
  function buildTopbar(session) {
    var bar = el('div#app-topbar.flex.h-14.items-center.gap-3.px-3');

    /* Marque */
    var brand = el('a.flex.shrink-0.items-center.gap-2\\.5.rounded-lg.px-1.py-1.transition-colors.hover\\:bg-white\\/10', {
      href: href(N.ROLES[session.role].home), title: C.BRAND.nom,
    });
    brand.appendChild(el('span.grid.h-9.w-9.shrink-0.place-items-center.overflow-hidden.rounded-lg.bg-white', null,
      el('img.h-7.w-7.object-contain', {
        src: base() + C.BRAND.logo, alt: 'CNT',
        onerror: function () { this.replaceWith(el('span.text-xs.font-bold.text-navy-900', { text: 'CNT' })); },
      })));
    brand.appendChild(el('span.hidden.min-w-0.lg\\:block', null, [
      el('span.block.truncate.text-sm.font-semibold.leading-tight.text-white', { text: 'NASSIERA TOO' }),
      el('span.block.truncate.text-\\[11px\\].leading-tight.text-navy-300', { text: 'SIGH — Gestion hospitalière' }),
    ]));
    bar.appendChild(brand);

    /* Recherche globale */
    var searchBtn = el('button.flex.h-9.w-auto.min-w-0.max-w-md.items-center.gap-2.rounded-lg.border.border-white\\/15.bg-white\\/10.px-3.text-left.text-sm.text-navy-200.transition-colors.hover\\:bg-white\\/20.sm\\:w-full', {
      type: 'button', onclick: openSearch,
    }, [
      C.icon('search', 'h-4 w-4'),
      el('span.hidden.flex-1.truncate.sm\\:block', { text: 'Rechercher un patient, un produit, un employé, un écran…' }),
      el('kbd.hidden.rounded.border.border-white\\/20.px-1\\.5.text-\\[10px\\].font-medium.text-navy-200.sm\\:block', { text: 'Ctrl K' }),
    ]);
    bar.appendChild(searchBtn);
    bar.appendChild(el('div.flex-1'));

    /* Actions rapides */
    bar.appendChild(el('button.ribbon-tool.hidden.lg\\:inline-flex.gap-2.px-3.w-auto.text-sm', {
      type: 'button', onclick: openQuickActions, title: 'Actions rapides',
    }, [C.icon('zap', 'h-4 w-4'), 'Actions']));

    /* Plein écran */
    bar.appendChild(buildFullscreenBtn());

    /* Notifications */
    /* LA CLOCHE COMPTE VRAIMENT. Elle portait « 4 » écrit en dur — quatre
       alertes, toujours, quel que soit le poste et quoi qu'il arrive. C'est
       pire qu'un badge absent : il donne à croire qu'on compte quelque chose.
       Le compte vient du moteur, qui route par poste et par droits. */
    var notifBtn = el('button.ribbon-tool.relative', {
      type: 'button', 'aria-label': 'Notifications', title: 'Notifications',
      onclick: openNotifications,
    }, C.icon('bell', 'h-5 w-5'));
    var badge = el('span.absolute.right-1.top-1.hidden.min-w-\\[1rem\\].place-items-center.rounded-full.bg-danger-500.px-1.text-\\[9px\\].font-bold.text-white');
    notifBtn.appendChild(badge);

    function peindreBadge(liste) {
      var n = (liste || []).length;
      badge.textContent = n > 99 ? '99+' : String(n);
      badge.classList.toggle('hidden', n === 0);
      badge.classList.toggle('grid', n > 0);
      notifBtn.setAttribute('title', n
        ? n + ' alerte(s) en attente' : 'Notifications — aucune alerte en attente');
    }
    var NT = global.SIGH.notifications;
    if (NT) {
      peindreBadge(NT.enAttente());
      /* La cloche suit le moteur en continu : elle ne se met pas à jour au
         seul rechargement de la page. */
      enDernier(NT.abonner(peindreBadge));
      NT.demarrer();
    }
    bar.appendChild(notifBtn);

    /* Profil */
    var role = N.ROLES[session.role];
    var profBtn = el('button.flex.shrink-0.items-center.gap-2.rounded-lg.py-1.pl-1.pr-2.transition-colors.hover\\:bg-white\\/10', { type: 'button', onclick: openProfile });
    profBtn.appendChild(el('span.grid.h-8.w-8.shrink-0.place-items-center.rounded-full.bg-white.text-xs.font-semibold.text-navy-900', { text: C.initials(session.nom) }));
    profBtn.appendChild(el('span.hidden.text-left.lg\\:block', null, [
      el('span.block.max-w-\\[10rem\\].truncate.text-xs.font-semibold.text-white', { text: session.nom }),
      el('span.block.text-\\[10px\\].text-navy-300', { text: role.label }),
    ]));
    profBtn.appendChild(C.icon('chevron-down', 'h-3.5 w-3.5 text-navy-300'));
    bar.appendChild(profBtn);

    return bar;
  }

  /* --- Plein écran ----------------------------------------------------------
   * Postes de saisie et écrans de garde : le mode plein écran libère la hauteur
   * utile pour les tableaux et les plannings. Le bouton suit l'état réel du
   * navigateur (touche F11 comprise) grâce à l'événement `fullscreenchange`.
   * ---------------------------------------------------------------------- */
  function plein() { return !!(document.fullscreenElement || document.webkitFullscreenElement); }

  function buildFullscreenBtn() {
    var b = el('button.ribbon-tool', { type: 'button' });

    function peindre() {
      var on = plein();
      C.clear(b);
      b.appendChild(C.icon(on ? 'minimize' : 'maximize', 'h-5 w-5'));
      b.title = on ? 'Quitter le plein écran (Échap)' : 'Plein écran (F11)';
      b.setAttribute('aria-label', b.title);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
      U.icons(b);
    }

    b.addEventListener('click', function () {
      try {
        if (!plein()) {
          var r = document.documentElement.requestFullscreen || document.documentElement.webkitRequestFullscreen;
          var p = r && r.call(document.documentElement);
          if (p && p.catch) p.catch(function () { U.toast('Le navigateur a refusé le passage en plein écran.', { type: 'error' }); });
        } else {
          var x = document.exitFullscreen || document.webkitExitFullscreen;
          if (x) x.call(document);
        }
      } catch (e) { U.toast('Plein écran indisponible sur ce poste.', { type: 'error' }); }
    });

    ecoute(document, 'fullscreenchange', peindre);
    peindre();
    return b;
  }

  /* --- Recherche globale --------------------------------------------------- */
  function openSearch() {
    var input = el('input.input', { type: 'search', placeholder: 'Patient, produit, employé, écran, acte, analyse, compte…', autocomplete: 'off' });
    var results = el('div.mt-3.max-h-\\[24rem\\].overflow-y-auto');

    function search() {
      var q = input.value.trim();
      C.clear(results);
      if (q.length < 2) {
        results.appendChild(el('p.px-1.py-6.text-center.text-xs.text-slate-400', { text: 'Saisir au moins 2 caractères.' }));
        return;
      }
      var groups = [];
      var role = (S.session() || {}).role;
      /* Un résultat ne doit jamais mener où le profil n'a pas accès (RG-13). */
      function autorise(id) {
        var e = N.get(id);
        /* L'IDENTIFIANT EST PASSÉ : sans lui, `ecranActif` ne sait pas de
           quel écran on parle et une activité fermée resterait proposée par
           la recherche. C'est le défaut déjà corrigé sur les cartes de hub
           et les accès rapides — il vivait encore ici. */
        return !!e && N.can(role, { id: e.id, roles: e.roles || N.ALL, module: e.module });
      }

      var ecrans = N.ids().map(N.get).filter(function (e) {
        return !e.standalone && C.matches(e.label + ' ' + e.moduleLabel, q) && autorise(e.id);
      }).slice(0, 6);
      if (ecrans.length) groups.push(['Écrans', ecrans.map(function (e) {
        return { label: e.label, detail: e.moduleLabel, icon: e.icon, go: function () { go(e.id); } };
      })]);

      /* Rubriques : la recherche ouvre la page ET l'onglet concerné. */
      var rubriques = N.RUBRIQUES.filter(function (r) {
        return C.matches(r.label + ' ' + r.motsCles, q) && autorise(r.ecran);
      }).slice(0, 6);
      if (rubriques.length) groups.push(['Rubriques', rubriques.map(function (r) {
        var e = N.get(r.ecran);
        return {
          label: r.label, detail: (e ? e.label : r.ecran) + ' — onglet', icon: e ? e.icon : 'panel-top',
          go: function () { go(r.ecran, { onglet: r.onglet }); },
        };
      })]);

      try {
        var pats = S.collection('patients').active().filter(function (p) {
          return C.matches(p.nom + ' ' + p.prenom + ' ' + p.code, q);
        }).slice(0, 5);
        if (pats.length) groups.push(['Patients', pats.map(function (p) {
          return { label: p.nom + ' ' + p.prenom, detail: p.code + ' — ' + p.quartier, icon: 'user', go: function () { go('m1-patients'); } };
        })]);

        var prods = S.collection('produits').active().filter(function (p) {
          return C.matches(p.designation + ' ' + p.code, q);
        }).slice(0, 5);
        if (prods.length) groups.push(['Produits', prods.map(function (p) {
          return { label: p.designation, detail: p.code + ' — stock ' + p.stock + ' ' + p.unite, icon: 'pill', go: function () { go('m6-produits'); } };
        })]);

        var emps = S.collection('personnel').active().filter(function (e) {
          return C.matches(e.nomComplet + ' ' + e.matricule + ' ' + e.poste, q);
        }).slice(0, 5);
        if (emps.length) groups.push(['Personnel', emps.map(function (e) {
          return { label: e.nomComplet, detail: 'Mat. ' + e.matricule + ' — ' + e.poste, icon: 'id-card', go: function () { go('m10-personnel'); } };
        })]);

        /* Les deux prix de la grille, en une ligne. C'est la question du
           guichet — « combien pour un assuré ? » — et y répondre par un seul
           chiffre oblige à ouvrir l'écran pour connaître l'autre. */
        function tarifCourt(a) {
          if (a.prix == null) return 'tarif à valider';
          var base = C.money(a.prix, false);
          if (a.tarifProvisoire) return base + ' (valeur d’attente)';
          if (a.nonCouvert) return base + ' · assuré : non couvert';
          if (a.prixAssure != null && a.prixAssure !== a.prix) {
            return base + ' · assuré ' + C.money(a.prixAssure, false);
          }
          return base;
        }

        /* Contenu des référentiels : ce que l'utilisateur cherche est souvent
           une ligne de catalogue, pas un écran. */
        /* Le catalogue administrable, pas la semence D.ACTES : un acte ajouté
           ou renommé dans cfg-tarifs doit se trouver par la recherche. */
        var actes = S.collection('actes').active().filter(function (a) {
          return C.matches(a.libelle + ' ' + a.secteur + ' ' + a.code, q);
        }).slice(0, 5);
        if (actes.length && autorise('cfg-tarifs')) groups.push(['Actes & prestations', actes.map(function (a) {
          return {
            label: a.libelle, icon: 'stethoscope',
            detail: a.secteur + ' — ' + tarifCourt(a),
            go: function () { go('cfg-tarifs', { onglet: 'actes' }); },
          };
        })]);

        var anas = D.ANALYSES.filter(function (a) {
          return C.matches(a.designation + ' ' + a.categorie + ' ' + a.code, q);
        }).slice(0, 5);
        if (anas.length && autorise('cfg-tarifs')) groups.push(['Analyses', anas.map(function (a) {
          return {
            label: a.designation, icon: 'flask-conical',
            detail: a.categorie + ' — ' + C.money(a.prix, false) + ' · ' + a.echantillon,
            go: function () { go('cfg-tarifs', { onglet: 'analyses' }); },
          };
        })]);

        var assur = S.collection('assureurs').active().filter(function (a) {
          return C.matches(a.nom + ' ' + (a.sigle || ''), q);
        }).slice(0, 4);
        if (assur.length && autorise('m9-compagnies')) groups.push(['Assureurs', assur.map(function (a) {
          return { label: a.nom, detail: 'Convention ' + (a.convention || '—'), icon: 'shield', go: function () { go('m9-compagnies'); } };
        })]);

        var cpts = S.collection('comptes').active().filter(function (c) {
          return C.matches(c.numero + ' ' + c.intitule, q);
        }).slice(0, 4);
        if (cpts.length && autorise('m12-plan-comptable')) groups.push(['Plan comptable', cpts.map(function (c) {
          return { label: c.numero + ' — ' + c.intitule, detail: 'SYSCOHADA', icon: 'book-open', go: function () { go('m12-plan-comptable'); } };
        })]);
      } catch (e) { /* recherche partielle acceptable */ }

      if (!groups.length) {
        results.appendChild(U.empty('Aucun résultat pour « ' + q + ' ».', { icon: 'search-x' }));
        return;
      }
      groups.forEach(function (g) {
        results.appendChild(el('p.px-1.pb-1.pt-3.text-\\[10px\\].font-semibold.uppercase.tracking-wider.text-slate-400', { text: g[0] }));
        g[1].forEach(function (r) {
          var row = el('button.flex.w-full.items-center.gap-3.rounded-lg.px-2.py-2.text-left.transition-colors.hover\\:bg-slate-100', { type: 'button', onclick: r.go });
          row.appendChild(el('span.grid.h-8.w-8.shrink-0.place-items-center.rounded-lg.bg-slate-100.text-slate-500', null, C.icon(r.icon, 'h-4 w-4')));
          row.appendChild(el('span.min-w-0.flex-1', null, [
            el('span.block.truncate.text-sm.font-medium.text-slate-800', { text: r.label }),
            el('span.block.truncate.text-xs.text-slate-500', { text: r.detail }),
          ]));
          row.appendChild(C.icon('arrow-right', 'h-4 w-4 text-slate-300'));
          results.appendChild(row);
        });
      });
      U.icons(results);
    }

    input.addEventListener('input', C.debounce(search, 150));
    var body = el('div', null, [input, results]);
    U.modal({ title: 'Recherche globale', size: 'md', body: body });
    search();
  }

  /* --- Actions rapides ----------------------------------------------------- */
  function openQuickActions() {
    var actions = [
      ['Nouveau dossier patient', 'user-plus', 'm1-patients'],
      ['Patient externe — analyses', 'user-round-plus', 'm1-externe'],
      ['Nouvelle consultation', 'stethoscope', 'm2-consultations'],
      ['Nouvelle admission', 'bed-double', 'm3-admissions'],
      ['Nouvelle facture', 'receipt', 'm8-facturation'],
      ['Encaisser un paiement', 'banknote', 'm8-paiements'],
      ['Assurés & cartes', 'id-card', 'm9-assures'],
      ['Demande d’analyse', 'flask-conical', 'm5-demandes'],
      ['Mouvement de stock', 'package', 'm6-mouvements'],
      ['Bon d’expression de besoins', 'clipboard-list', 'm7-besoins'],
      ['Éditer un état', 'printer', 'rapports-bibliotheque'],
    ];
    /* Un raccourci vers un écran interdit promet une porte fermée : la liste
       est filtrée par les droits du profil, comme le méga-menu. */
    var session = S.session() || {};
    actions = actions.filter(function (a) {
      var e = N.get(a[2]);
      return e && N.can(session.role, e);
    });
    var grid = el('div.grid.grid-cols-1.gap-2.sm\\:grid-cols-2');
    if (!actions.length) {
      U.modal({
        title: 'Actions rapides', size: 'md',
        body: U.empty('Aucune action rapide ouverte à votre profil.', { icon: 'lock' }),
      });
      return;
    }
    actions.forEach(function (a) {
      grid.appendChild(el('button.flex.items-center.gap-3.rounded-lg.border.border-slate-200.px-3.py-2\\.5.text-left.transition-colors.hover\\:border-navy-300.hover\\:bg-navy-50', {
        type: 'button', onclick: function () { go(a[2]); },
      }, [
        el('span.grid.h-8.w-8.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700', null, C.icon(a[1], 'h-4 w-4')),
        el('span.text-sm.font-medium.text-slate-700', { text: a[0] }),
      ]));
    });
    U.modal({ title: 'Actions rapides', size: 'md', body: grid });
  }

  /* --- Notifications ------------------------------------------------------- */
  /**
   * LE CENTRE DE NOTIFICATIONS — il AFFICHE, il ne décide pas.
   *
   * Il calculait ses propres règles ici même : seuils de stock, péremptions,
   * rejets MECeF. Deux défauts en découlaient. D'abord une seconde vérité —
   * changer un seuil dans le module n'aurait rien changé ici. Ensuite l'absence
   * de routage : un caissier lisait les alertes du magasin, sans filtre de
   * poste ni de droits.
   *
   * Il lit désormais le moteur, qui route par poste et par RBAC.
   */
  function openNotifications() {
    var NT = global.SIGH.notifications;
    var body = el('div');

    if (!NT) {
      body.appendChild(el('p.text-sm.text-slate-500', { text: 'Moteur de notification indisponible.' }));
      U.modal({ title: 'Notifications', size: 'md', body: body });
      return;
    }

    var liste = NT.collecter();
    var host = el('div.space-y-2');
    var m = null;

    function peindre() {
      C.clear(host);
      var actuelles = NT.collecter();

      if (!actuelles.length) {
        host.appendChild(el('div.flex.items-start.gap-3.rounded-lg.border.border-success-200.bg-success-50.p-3', null, [
          el('span.shrink-0.text-success-600', null, C.icon('check-circle-2', 'h-5 w-5')),
          el('div', null, [
            el('p.text-sm.font-medium.text-success-900', { text: 'Aucune alerte en cours' }),
            el('p.text-xs.text-success-700', { text: 'Rien ne requiert votre attention à ce poste.' }),
          ]),
        ]));
        return;
      }

      /* Métier et système restent SÉPARÉS : ce sont deux natures d'information,
         et les mélanger ferait chercher une panne de son parmi les ruptures de
         stock. C'est une classification d'affichage, pas une règle métier. */
      [['metier', 'Alertes métier'], ['systeme', 'Système']].forEach(function (grp) {
        var sous = actuelles.filter(function (n) { return n.categorie === grp[0]; });
        if (!sous.length) return;
        host.appendChild(el('p.mt-2.text-\\[10px\\].font-semibold.uppercase.tracking-wide.text-slate-400',
          { text: grp[1] + ' — ' + sous.length }));
        sous.forEach(function (n) {
          var p2 = NT.priorite(n.priorite);
          var row = el('div.flex.items-start.gap-3.rounded-lg.border.p-3', {
            class: n.acquitteeLe ? 'border-slate-200 bg-slate-50 opacity-70' : 'border-slate-200',
          });
          row.appendChild(el('span.grid.h-8.w-8.shrink-0.place-items-center.rounded-lg', {
            class: 'bg-' + p2.ton + '-50 text-' + p2.ton + '-600',
          }, C.icon(n.acquitteeLe ? 'bell-off' : 'bell-ring', 'h-4 w-4')));

          var b = el('div.min-w-0.flex-1');
          b.appendChild(el('p.text-sm.font-medium.text-slate-800', { text: n.titre }));
          b.appendChild(el('p.text-xs.text-slate-500', { text: n.detail }));
          b.appendChild(el('p.mt-1.flex.flex-wrap.items-center.gap-1\\.5', null, [
            U.badge(p2.label, p2.ton),
            el('span.text-\\[10px\\].text-slate-400', { text: n.domaine }),
            n.acquitteeLe ? el('span.text-\\[10px\\].italic.text-slate-400', { text: '· acquittée' }) : null,
          ].filter(Boolean)));
          row.appendChild(b);

          var actes = el('div.flex.shrink-0.flex-col.gap-1');
          if (n.lien) {
            actes.appendChild(el('a.btn.btn-secondary.btn-sm', { href: href(n.lien) }, 'Voir'));
          }
          /* ENTENDRE N'EST PAS TRAITER. L'acquittement fait taire l'alerte et
             la sort du badge ; il ne la résout pas. Elle disparaîtra quand sa
             CAUSE disparaîtra — c'est la source qui cesse de la produire. */
          actes.appendChild(el('button.btn.btn-ghost.btn-sm', {
            type: 'button',
            onclick: function () {
              if (n.acquitteeLe) NT.reprendre(n.cle, n.membres); else NT.acquitter(n.cle, n.membres);
              peindre();
              NT.tour(true);
            },
          }, n.acquitteeLe ? 'Reprendre' : 'Acquitter'));
          row.appendChild(actes);
          host.appendChild(row);
        });
      });
    }

    peindre();
    body.appendChild(host);

    var p = NT.params();
    body.appendChild(el('div.mt-3.flex.flex-wrap.items-center.justify-between.gap-2.border-t.border-slate-200.pt-3', null, [
      el('span.text-xs.text-slate-500', {
        text: NT.audioDisponible()
          ? (p.son ? 'Sonorisation active — profil ' + NT.profilAudio().label.toLowerCase()
            : 'Sonorisation désactivée. Les alertes restent visibles.')
          : 'Sonorisation indisponible sur ce poste. Les alertes restent visibles.',
      }),
      el('a.text-xs.font-medium.text-navy-700.hover\\:underline', { href: href('cfg-notifications') },
        'Paramétrer'),
    ]));

    m = U.modal({ title: 'Notifications', size: 'md', body: body });
    U.icons(body);
  }

  /* --- Profil -------------------------------------------------------------- */
  function openProfile() {
    var s = S.session();
    var body = el('div.space-y-4');
    var head = el('div.flex.items-center.gap-3.rounded-lg.bg-slate-50.p-3');
    head.appendChild(el('span.grid.h-12.w-12.place-items-center.rounded-full.bg-navy-900.text-sm.font-semibold.text-white', { text: C.initials(s.nom) }));
    head.appendChild(el('div', null, [
      el('p.text-sm.font-semibold.text-slate-900', { text: s.nom }),
      el('p.text-xs.text-slate-500', { text: N.ROLES[s.role].label }),
    ]));
    body.appendChild(head);

    /* Changement de rôle — permet de parcourir tous les tableaux de bord. */
    var sel = el('select.select');
    Object.keys(N.ROLES).forEach(function (r) {
      var o = el('option', { value: r }, N.ROLES[r].label);
      if (r === s.role) o.selected = true;
      sel.appendChild(o);
    });
    body.appendChild(el('div', null, [
      el('label.label', { text: 'Profil de connexion (démonstration)' }),
      sel,
      el('p.mt-1.text-xs.text-slate-400', { text: 'Change le périmètre RBAC : le méga-menu et les tableaux de bord sont filtrés en conséquence.' }),
    ]));

    var links = el('div.grid.grid-cols-2.gap-2');
    [['Mon compte', 'cfg-compte', 'user-cog'], ['Notifications', 'cfg-notifications', 'bell'],
     ['Aide & À propos', 'aide-apropos', 'life-buoy'], ['Contactez l’éditeur', 'contact-editeur', 'mail'],
     ['Journal d’audit', 'm14-audit', 'scroll-text'], ['Écran verrouillé', 'auth-lock', 'lock']].forEach(function (l) {
      links.appendChild(el('a.flex.items-center.gap-2.rounded-lg.border.border-slate-200.px-3.py-2.text-sm.text-slate-700.hover\\:bg-slate-50', { href: href(l[1]) },
        [C.icon(l[2], 'h-4 w-4 text-slate-400'), l[0]]));
    });
    body.appendChild(links);

    var m = U.modal({
      title: 'Profil utilisateur', size: 'sm', body: body,
      footer: [
        el('button.btn.btn-secondary', {
          type: 'button', onclick: function () { S.setSession(null); global.location.href = base() + 'index' + N.EXT; },
        }, [C.icon('log-out', 'h-4 w-4'), 'Se déconnecter']),
        el('button.btn.btn-primary', {
          type: 'button',
          onclick: function () {
            var r = sel.value;
            var role = N.ROLES[r];
            S.setSession({ role: r, nom: s.nom, poste: role.label });
            m.close();
            go(role.home);
          },
        }, 'Appliquer'),
      ],
    });
  }

  /* --------------------------------------------------------------------------
   * ACCÈS RAPIDES DÉDUITS DU MANIFESTE
   * --------------------------------------------------------------------------
   * Ce que l'utilisateur veut faire depuis un écran est presque toujours dans
   * le même module : consulter la liste voisine, revenir au tableau de bord du
   * module, ouvrir l'écran de saisie. Ces liens se déduisent — ils n'ont pas à
   * être écrits sur chaque écran, et le manifeste reste la source unique.
   *
   * Trois règles : jamais l'écran courant ; jamais un écran interdit au profil
   * (RG-13) ; et au plus deux liens déduits, pour ne pas noyer les actions que
   * l'écran a lui-même déclarées.
   * ----------------------------------------------------------------------- */
  function accesRapides(entry, dejaDeclarees, cibles) {
    if (!entry || entry.standalone || entry.module === 'AUTH') return [];
    var mod = N.module(entry.module);
    if (!mod) return [];
    var session = S.session() || {};
    var max = Math.max(0, 3 - dejaDeclarees);
    if (!max) return [];

    /* Les LIBELLÉS que les actions déclarées portent déjà. Reproposer le même
       texte en accès rapide met deux boutons identiques côte à côte, et deux
       boutons identiques ne sont pas une commodité : ils font douter qu'ils
       fassent la même chose. */
    function normaliser(x) {
      return String(x || '').toLowerCase()
        .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-z0-9]+/g, ' ').trim();
    }
    var deja = (cibles || []).map(normaliser).filter(Boolean);

    var voisins = mod.items.filter(function (it) {
      if (it.id === entry.id) return false;
      if (deja.indexOf(normaliser(it.label)) >= 0) return false;
      /* L'IDENTIFIANT DOIT ÊTRE PASSÉ : c'est lui que consulte le contrôle des
         activités fermées. Sans lui, un écran fermé pouvait être proposé en
         raccourci alors qu'il ne s'ouvre plus. */
      return N.can(session.role, {
        id: it.id,
        roles: it.roles || mod.roles || N.ALL,
        module: mod.code,
      });
    });

    var sorties = [];
    /* Le hub du module donne la vue d'ensemble : toujours utile, jamais en tête. */
    var candidats = voisins.slice(0, max - (max > 1 ? 1 : 0));
    candidats.forEach(function (it) {
      sorties.push(el('a.btn.btn-secondary', { href: href(it.id), title: it.label }, [
        C.icon(it.icon || mod.icon, 'h-4 w-4'),
        el('span.hidden.sm\\:inline', { text: it.label }),
      ]));
    });
    if (mod.hub && sorties.length < max) {
      sorties.push(el('a.btn.btn-secondary', { href: href(mod.hub), title: 'Accueil du module ' + mod.label }, [
        C.icon(mod.icon, 'h-4 w-4'),
        el('span.hidden.sm\\:inline', { text: mod.label }),
      ]));
    }
    return sorties;
  }

  /* ==========================================================================
   * EN-TÊTE DE PAGE
   * ======================================================================== */
  function buildPageHeader(entry, def) {
    var head = el('div.mb-5');

    /* Fil d'Ariane */
    var crumbs = el('nav.mb-2.flex.flex-wrap.items-center.gap-1\\.5.text-xs.text-slate-500', { 'aria-label': 'Fil d’Ariane' });
    var session = S.session();
    crumbs.appendChild(el('a.hover\\:text-navy-700', { href: href(N.ROLES[session.role].home), text: 'Accueil' }));
    crumbs.appendChild(C.icon('chevron-right', 'h-3 w-3 text-slate-300'));
    crumbs.appendChild(el('span', { text: entry.domain }));
    crumbs.appendChild(C.icon('chevron-right', 'h-3 w-3 text-slate-300'));
    /* L'intitulé du module ouvre sa page d'accueil : on circule d'un écran à
       l'autre du module sans repasser par le menu. */
    var hub = N.get(N.hubId(entry.module));
    if (hub && !entry.hub) {
      crumbs.appendChild(el('a.hover\\:text-navy-700.hover\\:underline', { href: href(hub.id), text: entry.moduleLabel }));
    } else {
      crumbs.appendChild(el('span', { text: entry.moduleLabel }));
    }
    if (!entry.hub) {
      crumbs.appendChild(C.icon('chevron-right', 'h-3 w-3 text-slate-300'));
      crumbs.appendChild(el('span.font-medium.text-slate-700', { text: entry.label }));
    }
    head.appendChild(crumbs);

    /* Titre + actions */
    var row = el('div.flex.flex-wrap.items-start.justify-between.gap-3');
    var left = el('div.min-w-0');
    left.appendChild(el('h1.flex.items-center.gap-2.text-xl.font-semibold.tracking-tight.text-slate-900', null, [
      el('span', { text: def.title || entry.label }),
      entry.module !== 'AUTH' ? el('span.badge.badge-navy.font-mono', { text: entry.module }) : null,
    ]));
    if (def.description) left.appendChild(el('p.mt-1.max-w-3xl.text-sm.text-slate-500', { text: def.description }));
    /* La devise de la clinique à l'en-tête de chaque module, demandée par la
       Direction le 24/08/2026. Discrète et masquée sous `sm` : elle
       accompagne le titre, elle ne lui dispute pas la place sur un écran
       étroit. L'écran de connexion en est dispensé — il porte déjà
       l'identité complète de la clinique. */
    if (entry.module !== 'AUTH') {
      left.appendChild(el('p.mt-1.text-xs.italic.text-slate-400', { text: C.BRAND.slogan }));
    }
    row.appendChild(left);

    /* Accès rapides du bandeau — déclarés par l'écran, ou déduits du manifeste.
       Écrire ces raccourcis un à un sur cent trente écrans serait à la fois
       fastidieux et fragile : le manifeste sait déjà à quel module appartient
       l'écran et quels sont ses voisins. On ne l'écrit donc nulle part, on le
       dérive — et un écran qui a mieux à proposer garde la main. */
    var declarees = def.actions ? (typeof def.actions === 'function' ? def.actions() : def.actions) : null;
    var liste = declarees ? (Array.isArray(declarees) ? declarees : [declarees]) : [];
    /* Les textes déjà proposés par l'écran, pour ne pas les redire. */
    var libellesDeclares = liste.map(function (b) {
      return (b && (b.textContent || b.getAttribute && b.getAttribute('title'))) || '';
    });
    var deduites = accesRapides(entry, liste.length, libellesDeclares);
    var selExo = selecteurExercice(entry);
    if (liste.length || deduites.length || selExo) {
      var acts = el('div#page-actions.flex.flex-wrap.items-center.gap-2');
      if (selExo) acts.appendChild(selExo);
      C.append(acts, liste);
      C.append(acts, deduites);
      row.appendChild(acts);
    }
    head.appendChild(row);

    /* ------------------------------------------------------------------
     * BANDEAU DE LECTURE SEULE — posé UNE FOIS, pour tous les écrans
     * ------------------------------------------------------------------
     * Un profil restreint sur un écran qui se modifie doit LE SAVOIR : sans
     * cela il voit un écran sans commandes et croit le logiciel incomplet
     * plutôt que son accès limité. Le kit le pose déjà sur ses propres
     * écrans ; les écrans construits à la main ne l'avaient pas, et les
     * écrire un à un aurait garanti autant d'oublis qu'il y a d'écrans.
     *
     * Il ne paraît QUE sur un écran qui se modifie : un tableau de bord ou
     * une statistique n'ont rien à modifier, et y annoncer une lecture seule
     * inquiéterait sans raison.
     * ---------------------------------------------------------------- */
    if (!def.lectureSeule && ecranModifiable(def)) {
      var dr = droitsCourants();
      if (dr && dr.voir && !dr.editer) {
        var session = S.session() || {};
        var role = (N.ROLES[session.role] && N.ROLES[session.role].label) || session.role || 'ce profil';
        head.appendChild(el('div.mt-3.flex.items-start.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.px-3.py-2', null, [
          el('span.shrink-0.text-slate-500', null, C.icon('lock', 'h-4 w-4')),
          el('p.text-xs.text-slate-700', {
            /* Le libellé du rôle est une donnée SAISIE : l'administrateur le
               renomme depuis la matrice. On échappe avant de réactiver la
               mise en forme, comme partout ailleurs. */
            html: '<strong>Lecture seule</strong> — le profil « ' + U.texteEnrichi(role) + ' » consulte cet écran sans '
              + 'pouvoir y créer, modifier ni archiver. Ce périmètre est fixé par la '
              + '<strong>matrice des droits</strong> (écran <em>Rôles & permissions</em>), '
              + 'non par l’écran lui-même.',
          }),
        ]));
      }
    }

    /* Un exercice CLOS est en lecture seule : l'écran le DIT, il n'attend pas qu'une écriture soit refusée. */
    if (selExo && global.SIGH.exercice) {
      var xc = global.SIGH.exercice.de(global.SIGH.exercice.choisi());
      if (xc && xc.etat === 'clos') {
        head.appendChild(el('div.mt-3.flex.items-start.gap-2.rounded-lg.border.border-warning-200.bg-warning-50.px-3.py-2', null, [
          el('span.shrink-0.text-warning-600', null, C.icon('lock', 'h-4 w-4')),
          el('p.text-xs.text-warning-900', { html: '<strong>Exercice ' + xc.annee + ' clos</strong>'
            + (xc.valideLe ? ' le ' + C.dateFR(xc.valideLe) : '') + (xc.validePar ? ' — ' + U.texteEnrichi(xc.validePar) : '')
            + ' — <strong>lecture seule</strong>. Les corrections passent par une écriture de l’exercice en cours, jamais par la réouverture.' }),
        ]));
      } else if (xc && xc.etat === 'en_attente_cloture') {
        head.appendChild(el('div.mt-3.flex.items-start.gap-2.rounded-lg.border.border-info-200.bg-info-50.px-3.py-2', null, [
          el('span.shrink-0.text-info-600', null, C.icon('hourglass', 'h-4 w-4')),
          el('p.text-xs.text-info-900', { html: '<strong>Exercice ' + xc.annee + ' en attente de clôture</strong> — la Direction doit valider la demande de '
            + U.texteEnrichi(xc.demandePar || 'le comptable') + '.' }),
        ]));
      } else if (xc && global.SIGH.exercice.provisoires(xc.annee).length) {
        head.appendChild(el('div.mt-3.flex.items-start.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.px-3.py-2', null, [
          el('span.shrink-0.text-slate-500', null, C.icon('info', 'h-4 w-4')),
          el('p.text-xs.text-slate-700', { html: '<strong>À-nouveaux provisoires</strong> — l’exercice ' + (xc.annee - 1)
            + ' n’est pas encore clos : le report est recalculé à chaque consultation et sera figé à la clôture.' }),
        ]));
      }
    }

    /* Rappel de règle métier, le cas échéant */
    if (def.regle) {
      head.appendChild(el('div.mt-3.flex.items-start.gap-2.rounded-lg.border.border-info-200.bg-info-50.px-3.py-2', null, [
        el('span.shrink-0.text-info-600', null, C.icon('info', 'h-4 w-4')),
        el('p.text-xs.text-info-900', { html: def.regle }),
      ]));
    }
    return head;
  }

  /**
   * SÉLECTEUR D'EXERCICE — dans la coquille de tout écran comptable (M12).
   * Un exercice par poste (mémorisé), l'exercice courant par défaut. Les
   * exercices clos sont marqués : le choix dit déjà ce qu'on pourra y faire.
   */
  function selecteurExercice(entry) {
    if (!global.SIGH.exercice || !entry || entry.module !== 'M12') return null;
    var X = global.SIGH.exercice, liste = X.liste(), courant = X.choisi();
    if (!liste.length) return null;
    var sel = el('select.select.w-auto', { id: 'selecteur-exercice', 'aria-label': 'Exercice comptable', title: 'Exercice comptable' });
    liste.forEach(function (x) {
      var et = { ouvert: 'ouvert', en_attente_cloture: 'en attente de clôture', clos: 'clos' }[x.etat] || x.etat;
      var o = el('option', { value: String(x.annee) }, 'Exercice ' + x.annee + ' — ' + et);
      if (x.annee === courant) o.selected = true;
      sel.appendChild(o);
    });
    sel.addEventListener('change', function () { X.choisir(sel.value); global.location.reload(); });
    return el('label.flex.items-center.gap-2.text-xs.text-slate-600', null, [C.icon('calendar', 'h-4 w-4'), sel]);
  }

  /**
   * Un écran « se modifie-t-il » ?
   *
   * Les tableaux de bord, les statistiques, les points et les états ne
   * modifient rien : y annoncer une lecture seule inquiéterait sans raison.
   * Le test porte sur le MODULE — DASH et RAP ne portent aucune écriture —
   * et sur le préfixe de l'écran, qui dit sa nature.
   */
  function ecranModifiable(def) {
    var e = PAGE ? N.get(PAGE.id) : null;
    if (!e) return false;
    if (e.module === 'DASH' || e.module === 'PIL' || e.module === 'RAP') return false;
    if (/^(dash-|rapports-)/.test(e.id)) return false;
    /* Les écrans d'analyse : ils lisent, ils ne modifient pas. */
    if (/-(stats|stats-[a-z]+|point-[a-z]+|baseline|analytique|grand-livre|balance)$/.test(e.id)) return false;
    return true;
  }

  /* ==========================================================================
   * AMORÇAGE
   * ======================================================================== */
  function page(def) { PAGE = def; }

  /* --- Registre d'écrans ---------------------------------------------------
   * Les modules métier enregistrent leurs écrans ici ; chaque page HTML se
   * contente d'appeler SIGH.mount('<id>'). Le HTML reste donc identique d'une
   * page à l'autre : aucune duplication de coquille, aucun lien en dur.
   * ---------------------------------------------------------------------- */
  var SCREENS = {};
  function screen(id, def) { SCREENS[id] = Object.assign({ id: id }, def); }

  /* ==========================================================================
   * LE MONTAGE ATTEND LE MAGASIN (23/09/2026)
   * --------------------------------------------------------------------------
   * Quand les données vivent sur le serveur, il faut les avoir AVANT qu'un
   * écran ne lise : `S.collection('patients').active()` est synchrone, et le
   * restera — c'est ce qui permet aux trois cents écrans de ne pas changer.
   *
   * L'ATTENTE EST ICI, ET NULLE PART AILLEURS. `mount()` est le point de
   * passage obligé de chaque page : une porte unique se tient, trois cents
   * ne se tiendraient pas. Sans serveur — ouverture par double-clic, serveurs
   * Node des bancs d'essai — l'hydratation rend `false` aussitôt et l'on
   * monte comme avant, sur le stockage du navigateur.
   * ======================================================================== */
  function mount(id) {
    /* Le montage ne doit JAMAIS être avalé par la porte : si l'hydratation
       échoue, on monte quand même sur le stockage du navigateur, et l'on DIT
       pourquoi. Une page blanche sans message ferait chercher le défaut dans
       l'écran pendant des heures. */
    /* `mount()` ne fait qu'ENREGISTRER la page ; c'est `boot()`, accroché au
       chargement du document, qui la rend. Tant que le montage était
       synchrone, l'ordre tombait juste. Avec l'attente du magasin, la page
       arrive APRÈS le départ de `boot` — qui trouvait alors `PAGE` vide et
       repartait sans rien afficher, en silence. On rend donc la main à `boot`
       une fois la page posée, si le document n'attend plus. */
    function poursuivre(origine) {
      try {
        monterVraiment(id);
        if (document.readyState !== 'loading') boot();
      } catch (e) {
        if (global.console && global.console.error) {
          global.console.error('[SIGH] Montage de « ' + id + ' » (' + origine + ') :', e);
        }
        throw e;
      }
    }
    if (S.hydraterServeur) {
      try {
        S.hydraterServeur().then(
          function () { poursuivre('après hydratation'); },
          function (e) {
            if (global.console && global.console.warn) {
              global.console.warn('[SIGH] Magasin distant indisponible, repli sur le navigateur :', e);
            }
            poursuivre('sans serveur');
          }
        );
        return;
      } catch (e) { /* pas de promesse disponible : on monte directement */ }
    }
    poursuivre('direct');
  }

  function monterVraiment(id) {
    /* Le jeu de démonstration se peuple UNE FOIS, au premier montage, et non
       dans store.seed() : le moteur de parcours n existe pas encore à cet
       instant. On rejoue de vrais parcours plutot que de fabriquer des listes
       independantes — c est la seule facon d obtenir des donnees coherentes
       entre modules. */
    /* Un stockage saturé se dit à l'écran : le repli en mémoire garde la page
       fonctionnelle mais perd les données au changement d'écran, et l'on
       chercherait le défaut ailleurs. */
    if (S.storage && S.storage.quotaSignale && !global.__quotaDit) {
      global.__quotaDit = true;
      setTimeout(function () { U.toast(S.storage.quotaMessage, { type: 'error', duree: 12000 }); }, 800);
    }

    /* LE PEUPLEMENT EXIGE UN MAGASIN, DONC UNE SESSION. Depuis que la donnée
       vit au serveur, un écran ouvert SANS session — la page de connexion —
       n'a pas de magasin où écrire : chaque lecture lui rend une coquille
       jetable, et le peuplement s'y cassait au premier agent lu
       (« Cannot read properties of undefined (reading 'nomComplet') »).
       On ne peuple donc qu'une fois l'agent connecté. */
    if (global.SIGH.peuplerParcours && S.session()) {
      try { global.SIGH.peuplerParcours(); } catch (e) { console.error('[SIGH] peuplement', e); }
    }

    var def = SCREENS[id];
    if (!def) {
      var entry = N.get(id);
      def = {
        id: id,
        title: entry ? entry.label : id,
        description: 'Cet écran est déclaré au périmètre mais son contenu n’est pas encore implémenté dans le prototype.',
        render: function (root) {
          root.appendChild(U.card(null, U.empty('Écran en cours de construction.', {
            icon: 'hammer',
            hint: entry ? ('Module ' + entry.module + ' — ' + entry.moduleLabel + '. Prévu au périmètre du cahier des charges.') : null,
          })));
        },
      };
    }
    page(def);
  }

  var _boote = false;
  function boot() {
    try {
      if (!PAGE) return;
      /* `boot` est appelé par le chargement du document ET par le montage,
         qui peut arriver après lui quand le magasin vient du serveur. Il ne
         doit peindre qu'UNE fois : deux appels superposeraient deux coquilles
         et deux jeux d'écouteurs sur la même page. */
      if (_boote) return;
      _boote = true;
      var entry = N.get(PAGE.id);
      if (!entry) {
        console.error('[SIGH] Écran inconnu dans le manifeste : ' + PAGE.id);
        entry = { id: PAGE.id, label: PAGE.title || PAGE.id, module: '—', moduleLabel: '—', domain: '—', icon: 'file' };
      }

      /* Écrans autonomes (connexion, erreurs) : pas de coquille. */
      if (PAGE.standalone) {
        var host0 = $('#page') || document.body;
        if (PAGE.render) PAGE.render(host0);
        U.icons(document.body);
        return;
      }

      var session = requireSession();

      /* Contrôle RBAC de l'écran demandé.
         Il passe par N.can() et non par une lecture directe de entry.roles :
         c'est can() qui applique les surcharges de la matrice administrable.
         Sans cela, un module fermé depuis « Rôles & permissions » disparaîtrait
         du menu mais resterait atteignable en tapant son adresse. */
      if (!N.can(session.role, entry)) {
        global.location.href = href('error-403');
        return;
      }

      /* Un rôle archivé ne travaille plus : la session ouverte avant
         l'archivage est refermée et la tentative est tracée. */
      if (N.roleArchive(session.role)) {
        S.collection('tentativesConnexion', { module: 'M14', entite: 'tentative', prefix: 'TNT' }).insert({
          identifiant: session.identifiant || session.nom, role: session.role,
          nom: session.nom, motif: 'Rôle archivé — session en cours interrompue',
          horodatage: new Date().toISOString(), ecran: entry.id, traitee: false,
        });
        S.setSession(null);
        global.location.href = href('index') + '?motif=role-archive';
        return;
      }

      document.body.className = 'min-h-screen bg-slate-100';
      document.body.appendChild(buildMenubar(session, PAGE.id));
      armerVerrou(entry);

      var main = el('div#app-main');

      var container = el('main.mx-auto.w-full.max-w-\\[100rem\\].px-4.py-5.sm\\:px-6');
      container.appendChild(buildPageHeader(entry, PAGE));

      var content = el('div#page-content');
      container.appendChild(content);

      /* TOUT lien interne referme le méga-menu : fil d'Ariane, accès rapides du
         bandeau, raccourcis permanents du ruban, cartes des tableaux de bord,
         liens d'un tableau. L'écouteur est posé sur le DOCUMENT et non sur le
         conteneur de page : les raccourcis permanents sont rendus hors de ce
         conteneur et lui échappaient, ce qui laissait le menu déployé sur
         Patients, Consultations, Pharmacie et Facturation.
         Les boutons, eux, sont couverts par go() — voir plus haut. */
      ecoute(document, 'click', function (ev) {
        var a = ev.target && ev.target.closest ? ev.target.closest('a[href]') : null;
        if (!a) return;
        var href_ = a.getAttribute('href') || '';
        /* Une ancre, un lien externe ou un téléchargement ne navigue pas
           vers une page du prototype : le ruban n'a pas à s'y replier. */
        if (!href_ || href_.charAt(0) === '#' || a.hasAttribute('download')) return;
        if (/^(https?:|mailto:|tel:|data:|blob:)/i.test(href_)) return;
        if (a.target && a.target !== '_self') return;
        replierApresNavigation();
        /* Un lien vers un écran du manifeste ne recharge pas le document. */
        if (ev.defaultPrevented || ev.button || ev.ctrlKey || ev.metaKey || ev.shiftKey || ev.altKey) return;
        var cible = idDeLien(a);
        if (cible && spaPermise() && naviguerSansRecharger(cible, optsDeLien(a))) ev.preventDefault();
      });

      main.appendChild(container);

      main.appendChild(el('footer.no-print.mx-auto.w-full.max-w-\\[100rem\\].px-4.pb-8.pt-4.sm\\:px-6', null,
        el('p.border-t.border-slate-200.pt-4.text-xs.text-slate-400', {
          text: C.BRAND.nom + ' — IFU ' + C.BRAND.ifu + ' — RCCM ' + C.BRAND.rccm + '. Prototype SIGH-CNT, jeu de données de démonstration.',
        })));
      document.body.appendChild(main);

      /* Contenu de la page */
      try {
        if (PAGE.render) {
          var out = PAGE.render(content);
          if (out) C.append(content, out);
        }
      } catch (e) {
        console.error('[SIGH] Rendu de « ' + PAGE.id + ' » :', e);
        C.clear(content);
        content.appendChild(U.errorState('Une erreur est survenue lors de l’affichage de cet écran.',
          function () { global.location.reload(); }));
      }

      U.icons(document.body);

      /* ====================================================================
       * LE MESSAGE SURVIT À LA NAVIGATION (22/09/2026)
       * --------------------------------------------------------------------
       * Depuis que les grandes saisies sont des PAGES, l'enregistrement
       * ramène au registre : le message de confirmation était affiché puis
       * emporté par le rechargement, en une fraction de seconde. L'agent
       * validait et ne voyait RIEN — ni le numéro attribué, ni ce qui avait
       * été transmis. On le dépose donc pour le chargement suivant, qui le
       * consomme UNE fois, comme le drapeau de repli du ruban.
       * ================================================================== */
      U.consommerMessageDiffere();

      /* Raccourcis clavier — postes à forte saisie (CDCT §10.3). */
      ecoute(document, 'keydown', function (e) {
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openSearch(); }
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'p' && PAGE.print) { e.preventDefault(); PAGE.print(); }
      });
    } catch (e) {
      console.error('[SIGH] Amorçage :', e);
      document.body.appendChild(el('div.p-8', null,
        U.errorState('Le chargement de l’application a échoué : ' + e.message)));
    }
  }

  try { if (global.history && global.history.replaceState && !(global.history.state && global.history.state.sigh)) {
    var _m = /\/pages\/([\w-]+)\.[a-z]+$/i.exec(global.location.pathname);
    if (_m) global.history.replaceState({ sigh: _m[1] }, '', global.location.href);
  } } catch (e) { /* historique indisponible */ }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else setTimeout(boot, 0);

  global.SIGH.page = page;
  global.SIGH.screen = screen;
  global.SIGH.mount = mount;
  global.SIGH.screens = SCREENS;
  /**
   * Droits du profil courant sur un module — par défaut celui de l'écran
   * affiché. C'est le point que consultent `kit.crud` et `kit.actionsLigne`
   * pour masquer ce que le rôle n'a pas le droit de faire : les commandes
   * n'ont pas à être protégées écran par écran.
   */
  function droitsCourants(code) {
    var session = S.session() || {};
    var e = PAGE ? N.get(PAGE.id) : null;
    var c = code || (e ? e.module : null);
    if (!c) return { voir: true, editer: true, annuler: true, lectureSeule: false };
    /* L’écran d’abord, le module ensuite : la matrice descend au niveau
       de l’écran, et une surcharge d’écran l’emporte sur celle de son module.
       Une PAGE DE SAISIE résout ses droits sur le REGISTRE qu’elle alimente
       (`servant`) : elle prolonge un geste, elle n’en ouvre pas un nouveau. */
    return N.droitsEcran(session.role, N.ecranDesDroits(e), c);
  }

  global.SIGH.app = {
    href: href, go: go, base: base,
    openSearch: openSearch, openProfile: openProfile, openNotifications: openNotifications,
    droits: droitsCourants,
    entry: function () { return PAGE ? N.get(PAGE.id) : null; },
    VERROU_RETOUR: VERROU_RETOUR, VERROU_DELAI: VERROU_DELAI,
    delaiVerrou: delaiVerrou,
    replierRuban: replierApresNavigation,
    ecoute: ecoute, enDernier: enDernier, sansRecharger: naviguerSansRecharger,
  };
})(window);
