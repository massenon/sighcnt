/* =============================================================================
 * SIGH-CNT — Bibliothèque de composants
 * -----------------------------------------------------------------------------
 * Standard UX commun à tous les modules (draf1 « STANDARD UX COMMUN ») :
 * bloc KPI, cartes, graphiques, filtres, tableau interactif, CRUD complet,
 * drawer de détail, modales standardisées, timeline, audit, états vides,
 * chargement, erreurs, exports et impression.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core;
  var el = C.el, $ = C.$, $$ = C.$$;

  /* ==========================================================================
   * TOASTS — chaque mutation propose son annulation (undo)
   * ======================================================================== */
  /**
   * Les toasts s'empilent en haut à droite, sous la barre supérieure quand elle existe
   * (`#app-topbar`, hauteur h-14) et à 20 px du bord sur les écrans qui n'en portent pas
   * — connexion, verrouillage, pages d'erreur. Le décalage est posé en style en ligne :
   * aucune classe Tailwind supplémentaire à faire figurer dans la safelist.
   */
  function toastHost() {
    var host = $('#toast-host');
    if (!host) {
      host = el('div#toast-host.fixed.right-5.z-\\[60\\].flex.flex-col.gap-2.no-print', { role: 'status', 'aria-live': 'polite' });
      var bar = document.getElementById('app-topbar');
      host.style.top = (bar ? bar.getBoundingClientRect().height + 16 : 20) + 'px';
      document.body.appendChild(host);
    }
    return host;
  }

  var TOAST_STYLES = {
    success: { icon: 'check-circle-2', cls: 'border-success-200 bg-success-50', ico: 'text-success-600' },
    error: { icon: 'alert-circle', cls: 'border-danger-200 bg-danger-50', ico: 'text-danger-600' },
    warning: { icon: 'alert-triangle', cls: 'border-warning-200 bg-warning-50', ico: 'text-warning-600' },
    info: { icon: 'info', cls: 'border-slate-200 bg-white', ico: 'text-navy-700' },
  };

  /**
   * toast('Patient créé', { type:'success', undo: fn, duration: 6000 })
   * Si `undo` est fourni, un bouton « Annuler » est affiché.
   */
  function toast(message, opts) {
    opts = opts || {};
    var st = TOAST_STYLES[opts.type || 'info'] || TOAST_STYLES.info;
    var node = el('div.animate-pop-in.flex.w-\\[22rem\\].max-w-\\[90vw\\].items-start.gap-3.rounded-xl.border.p-3.shadow-pop',
      { class: st.cls });
    node.appendChild(el('span.mt-0\\.5.shrink-0', { class: st.ico }, C.icon(st.icon, 'h-5 w-5')));
    var body = el('div.min-w-0.flex-1');
    body.appendChild(el('p.text-sm.font-medium.text-slate-800', { text: message }));
    if (opts.detail) body.appendChild(el('p.mt-0\\.5.text-xs.text-slate-500', { text: opts.detail }));
    node.appendChild(body);

    var actions = el('div.flex.shrink-0.items-center.gap-1');
    var timer;
    function close() { clearTimeout(timer); node.remove(); }
    if (typeof opts.undo === 'function') {
      actions.appendChild(el('button.btn.btn-sm.btn-secondary', {
        type: 'button',
        onclick: function () {
          opts.undo();
          close();
          toast(opts.undoMessage || 'Action annulée.', { type: 'info' });
        },
      }, 'Annuler'));
    }
    actions.appendChild(el('button.btn.btn-ghost.btn-sm.px-1\\.5', {
      type: 'button', 'aria-label': 'Fermer', onclick: close,
    }, C.icon('x', 'h-4 w-4')));
    node.appendChild(actions);

    /* Empilement vers le bas : le message le plus récent reste en tête de pile. */
    var pile = toastHost();
    pile.insertBefore(node, pile.firstChild);
    icons(node);
    timer = setTimeout(close, opts.duration || (opts.undo ? 8000 : 4000));
    return { close: close };
  }

  /* ==========================================================================
   * MODALE
   * ======================================================================== */
  var openLayers = [];

  function modal(options) {
    var o = Object.assign({ title: '', size: 'md', body: null, footer: null, onClose: null }, options);
    var sizes = { sm: 'max-w-md', md: 'max-w-2xl', lg: 'max-w-4xl', xl: 'max-w-6xl' };

    var backdrop = el('div.drawer-backdrop.fixed.inset-0.z-50.flex.items-start.justify-center.overflow-y-auto.bg-navy-950\\/40.p-4.animate-fade-in.no-print',
      { role: 'dialog', 'aria-modal': 'true' });
    var panel = el('div.animate-pop-in.my-8.w-full.rounded-xl.bg-white.shadow-pop', { class: sizes[o.size] || sizes.md });

    var head = el('div.flex.items-start.justify-between.gap-4.border-b.border-slate-200.px-5.py-4');
    var titleWrap = el('div');
    titleWrap.appendChild(el('h2.text-base.font-semibold.text-slate-900', { text: o.title }));
    if (o.subtitle) titleWrap.appendChild(el('p.mt-0\\.5.text-xs.text-slate-500', { text: o.subtitle }));
    head.appendChild(titleWrap);
    head.appendChild(el('button.btn.btn-ghost.btn-icon', { type: 'button', 'aria-label': 'Fermer', onclick: close }, C.icon('x', 'h-4 w-4')));
    panel.appendChild(head);

    var bodyEl = el('div.px-5.py-4');
    C.append(bodyEl, o.body);
    panel.appendChild(bodyEl);

    if (o.footer) {
      var foot = el('div.flex.items-center.justify-end.gap-2.border-t.border-slate-200.bg-slate-50.px-5.py-3.rounded-b-xl');
      C.append(foot, o.footer);
      panel.appendChild(foot);
    }

    backdrop.appendChild(panel);
    backdrop.addEventListener('mousedown', function (e) { if (e.target === backdrop) close(); });
    document.body.appendChild(backdrop);
    document.body.style.overflow = 'hidden';
    icons(backdrop);
    openLayers.push(close);

    var first = backdrop.querySelector('input:not(.combo-search),select,textarea,button:not(.combo-input)');
    if (first && !first.classList.contains('btn-ghost')) setTimeout(function () { first.focus(); }, 30);

    function close() {
      var i = openLayers.indexOf(close); if (i >= 0) openLayers.splice(i, 1);
      nettoyerCombos(backdrop);
      backdrop.remove();
      if (!openLayers.length) document.body.style.overflow = '';
      if (o.onClose) o.onClose();
    }
    return { close: close, panel: panel, body: bodyEl };
  }

  /** Confirmation standardisée — retourne une promesse. */
  /* --------------------------------------------------------------------------
   * TEXTE ENRICHI SÛR — pour les messages de modale
   * --------------------------------------------------------------------------
   * Échappe TOUT, puis réactive un sous-ensemble fermé de balises de mise en
   * forme. L'ordre est ce qui rend la fonction sûre : comme l'échappement
   * précède, une donnée ne peut pas introduire de balise — seules celles
   * écrites dans le gabarit survivent.
   *
   * Rendre ces messages en innerHTML aurait réglé l'affichage et ouvert une
   * injection : ils portent des noms de patients, des libellés d'articles et
   * des motifs saisis par un agent.
   * ----------------------------------------------------------------------- */
  var BALISES_SURES = ['strong', 'b', 'em', 'i', 'u', 'code', 'small'];

  function texteEnrichi(source) {
    var t = String(source == null ? '' : source);
    /* 1. Tout échapper. */
    t = t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    /* 2. Réactiver les seules balises de mise en forme, sans attribut. */
    BALISES_SURES.forEach(function (b) {
      t = t.replace(new RegExp('&lt;' + b + '&gt;', 'gi'), '<' + b + '>')
        .replace(new RegExp('&lt;/' + b + '&gt;', 'gi'), '</' + b + '>');
    });
    t = t.replace(/&lt;br\s*\/?&gt;/gi, '<br>');
    return t;
  }

  /** Un nœud portant ce texte enrichi — l'usage courant. */
  function paragrapheEnrichi(source, classe) {
    var n = el(classe || 'p');
    n.innerHTML = texteEnrichi(source);
    return n;
  }

  function confirm(options) {
    var o = Object.assign({
      title: 'Confirmer l’action', message: '', confirmLabel: 'Confirmer',
      cancelLabel: 'Annuler', danger: false, requireMotif: false,
    }, options);
    return new Promise(function (resolve) {
      var body = el('div.space-y-3');
      /* Le message est rendu en TEXTE ENRICHI : les balises de mise en forme
         que le gabarit écrit s'appliquent, tout le reste est échappé. */
      body.appendChild(paragrapheEnrichi(o.message, 'p.text-sm.text-slate-600'));
      var motif = null;
      if (o.requireMotif) {
        var wrap = el('div');
        wrap.appendChild(el('label.label', { text: 'Motif (consigné dans le journal d’audit)' }));
        motif = el('textarea.textarea', { rows: 2, placeholder: 'Préciser le motif…' });
        wrap.appendChild(motif);
        body.appendChild(wrap);
      }

      /* La fermeture de la modale (bouton, clic hors cadre, touche Échap)
         déclenche `onClose`. Sans ce garde-fou, la promesse serait résolue à
         `null` avant la réponse effective de l'utilisateur et l'action
         confirmée ne s'exécuterait jamais. */
      var repondu = false;
      function repondre(valeur) {
        if (repondu) return;
        repondu = true;
        resolve(valeur);
      }

      var m = modal({
        title: o.title, size: 'sm', body: body,
        footer: [
          el('button.btn.btn-secondary', { type: 'button', onclick: function () { repondre(null); m.close(); } }, o.cancelLabel),
          el('button.btn', {
            type: 'button', class: o.danger ? 'btn-danger' : 'btn-primary',
            onclick: function () { repondre({ motif: motif ? motif.value : null }); m.close(); },
          }, o.confirmLabel),
        ],
        onClose: function () { repondre(null); },
      });
    });
  }

  /* ==========================================================================
   * TIROIR LATÉRAL (drawer) — vue détaillée
   * ======================================================================== */
  function drawer(options) {
    var o = Object.assign({ title: '', subtitle: '', body: null, footer: null, width: 'max-w-xl' }, options);
    var backdrop = el('div.drawer-backdrop.fixed.inset-0.z-50.bg-navy-950\\/40.animate-fade-in.no-print', { role: 'dialog', 'aria-modal': 'true' });
    var panel = el('div.animate-slide-in.absolute.right-0.top-0.flex.h-full.w-full.flex-col.bg-white.shadow-pop', { class: o.width });

    var head = el('div.flex.items-start.justify-between.gap-4.border-b.border-slate-200.px-5.py-4');
    var t = el('div.min-w-0');
    t.appendChild(el('h2.truncate.text-base.font-semibold.text-slate-900', { text: o.title }));
    if (o.subtitle) t.appendChild(el('p.mt-0\\.5.truncate.text-xs.text-slate-500', { text: o.subtitle }));
    head.appendChild(t);
    head.appendChild(el('button.btn.btn-ghost.btn-icon', { type: 'button', 'aria-label': 'Fermer', onclick: close }, C.icon('x', 'h-4 w-4')));
    panel.appendChild(head);

    var bodyEl = el('div.flex-1.overflow-y-auto.px-5.py-4');
    C.append(bodyEl, o.body);
    panel.appendChild(bodyEl);

    if (o.footer) {
      var foot = el('div.flex.items-center.justify-end.gap-2.border-t.border-slate-200.bg-slate-50.px-5.py-3');
      C.append(foot, o.footer);
      panel.appendChild(foot);
    }

    backdrop.appendChild(panel);
    backdrop.addEventListener('mousedown', function (e) { if (e.target === backdrop) close(); });
    document.body.appendChild(backdrop);
    document.body.style.overflow = 'hidden';
    icons(backdrop);
    openLayers.push(close);

    function close() {
      var i = openLayers.indexOf(close); if (i >= 0) openLayers.splice(i, 1);
      nettoyerCombos(backdrop);
      backdrop.remove();
      if (!openLayers.length) document.body.style.overflow = '';
      if (o.onClose) o.onClose();
    }
    return { close: close, body: bodyEl, panel: panel };
  }

  /** Ferme toutes les couches ouvertes (modales, tiroirs) et rend le défilement à la page.
   *  Appelée au démontage d'un écran : une modale encore ouverte pendant une navigation
   *  sans rechargement laissait `body { overflow: hidden }` et figeait la barre de défilement. */
  function fermerCouches() {
    openLayers.slice().reverse().forEach(function (c) { try { c(); } catch (e) { /* une couche ne bloque pas les autres */ } });
    openLayers.length = 0;
    document.body.style.overflow = '';
  }

  /* Échap ferme la couche la plus haute */
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && openLayers.length) openLayers[openLayers.length - 1]();
  });

  /* ==========================================================================
   * BLOCS D'AFFICHAGE
   * ======================================================================== */
  function kpi(spec) {
    var node = el('div.kpi');
    var top = el('div.flex.items-start.justify-between.gap-3');
    var left = el('div.min-w-0');
    left.appendChild(el('p.kpi-label', { text: spec.label }));
    left.appendChild(el('p.kpi-value.num', { text: spec.value }));
    if (spec.hint) left.appendChild(el('p.mt-1.text-xs.text-slate-400', { text: spec.hint }));
    top.appendChild(left);
    if (spec.icon) {
      var tone = spec.tone || 'navy';
      var tones = {
        navy: 'bg-navy-50 text-navy-700', success: 'bg-success-50 text-success-600',
        warning: 'bg-warning-50 text-warning-600', danger: 'bg-danger-50 text-danger-600',
        info: 'bg-info-50 text-info-600', neutral: 'bg-slate-100 text-slate-500',
      };
      top.appendChild(el('span.grid.h-9.w-9.shrink-0.place-items-center.rounded-lg', { class: tones[tone] || tones.navy }, C.icon(spec.icon, 'h-4.5 w-4.5')));
    }
    node.appendChild(top);
    if (spec.delta != null) {
      var up = spec.delta >= 0;
      var good = spec.invert ? !up : up;
      node.appendChild(el('p.mt-2.flex.items-center.gap-1.text-xs.font-medium', { class: good ? 'text-success-600' : 'text-danger-600' }, [
        C.icon(up ? 'trending-up' : 'trending-down', 'h-3.5 w-3.5'),
        el('span', { text: (up ? '+' : '') + spec.delta + '%' }),
        el('span.font-normal.text-slate-400', { text: spec.deltaLabel || 'vs mois dernier' }),
      ]));
    }
    return node;
  }

  function kpiGrid(specs, cols) {
    var grid = el('div.grid.gap-3', { class: cols || 'grid-cols-2 lg:grid-cols-4' });
    specs.forEach(function (s) { grid.appendChild(kpi(s)); });
    return grid;
  }

  function card(title, body, actions) {
    var node = el('div.card');
    if (title) {
      var head = el('div.card-head');
      head.appendChild(el('h3.card-title', { text: title }));
      if (actions) C.append(head, el('div.flex.items-center.gap-2', null, actions));
      node.appendChild(head);
    }
    var b = el('div.card-body');
    C.append(b, body);
    node.appendChild(b);
    return node;
  }

  function badge(label, tone) {
    return el('span.badge', { class: 'badge-' + (tone || 'neutral'), text: label });
  }

  /** Statuts métier normalisés → badge coloré. */
  var STATUTS = {
    actif: ['Actif', 'success'], archive: ['Archivé', 'neutral'], inactif: ['Inactif', 'neutral'],
    libre: ['Libre', 'success'], occupe: ['Occupé', 'danger'],
    soldee: ['Soldée', 'success'], partielle: ['Partielle', 'warning'], impayee: ['Impayée', 'danger'],
    valide: ['Validé', 'success'], validee: ['Validée', 'success'], en_attente: ['En attente', 'warning'],
    rejete: ['Rejeté', 'danger'], brouillon: ['Brouillon', 'neutral'],
    en_cours: ['En cours', 'info'], terminee: ['Terminée', 'success'], planifiee: ['Planifiée', 'navy'],
    /* L'agenda distingue le REPORT (une nouvelle date est fixée) du NON
       HONORÉ (le patient n'est pas venu) : les confondre ferait disparaître
       le taux d'absentéisme, qui est précisément ce qu'on veut suivre. */
    reporte: ['Reporté', 'warning'], non_honore: ['Non honoré', 'danger'],
    sortie: ['Sorti', 'neutral'], perime: ['Périmé', 'danger'], alerte: ['Péremption proche', 'warning'],
    rupture: ['Rupture', 'danger'], critique: ['Critique', 'warning'], normal: ['Normal', 'success'],
    moins_8h: ['Moins de 8h', 'info'], plus_8h: ['Plus de 8h', 'navy'],
  };
  function statut(key) {
    var s = STATUTS[key];
    return s ? badge(s[0], s[1]) : badge(String(key || '—'), 'neutral');
  }

  function empty(message, opts) {
    opts = opts || {};
    var node = el('div.flex.flex-col.items-center.justify-center.gap-3.px-6.py-14.text-center');
    node.appendChild(el('span.grid.h-12.w-12.place-items-center.rounded-full.bg-slate-100.text-slate-400', null, C.icon(opts.icon || 'inbox', 'h-6 w-6')));
    node.appendChild(el('p.text-sm.font-medium.text-slate-700', { text: message }));
    if (opts.hint) node.appendChild(el('p.max-w-sm.text-xs.text-slate-500', { text: opts.hint }));
    if (opts.action) node.appendChild(opts.action);
    return node;
  }

  function loading(rows) {
    var node = el('div.space-y-2.p-4');
    for (var i = 0; i < (rows || 5); i++) node.appendChild(el('div.skeleton.h-9.w-full'));
    return node;
  }

  function errorState(message, retry) {
    var node = el('div.flex.flex-col.items-center.gap-3.px-6.py-12.text-center');
    node.appendChild(el('span.grid.h-12.w-12.place-items-center.rounded-full.bg-danger-50.text-danger-600', null, C.icon('alert-triangle', 'h-6 w-6')));
    node.appendChild(el('p.text-sm.font-medium.text-slate-800', { text: message }));
    if (retry) node.appendChild(el('button.btn.btn-secondary.btn-sm', { type: 'button', onclick: retry }, 'Réessayer'));
    return node;
  }

  /** Onglets — `tabs([{id,label,badge,render:fn}])`. Rend le premier par défaut. */
  function tabs(items, opts) {
    opts = opts || {};
    var wrap = el('div');
    var bar = el('div.flex.gap-1.overflow-x-auto.border-b.border-slate-200');
    var panel = el('div', { class: opts.panelClass || 'pt-4' });
    var current = null;

    function select(item, btn) {
      $$('.tab', bar).forEach(function (b) { b.classList.remove('tab-active'); b.setAttribute('aria-selected', 'false'); });
      btn.classList.add('tab-active'); btn.setAttribute('aria-selected', 'true');
      C.clear(panel);
      current = item.id;
      try {
        var content = item.render ? item.render(panel) : null;
        if (content) C.append(panel, content);
      } catch (e) {
        console.error('[SIGH] Onglet « ' + item.label + ' » :', e);
        panel.appendChild(errorState('Impossible d’afficher cet onglet.'));
      }
      icons(panel);
      if (opts.onChange) opts.onChange(item.id);
    }

    /* Un lien peut viser une rubrique précise : `…/cfg-tarifs.html#onglet=actes`
       ouvre l'écran directement sur l'onglet demandé. C'est ce qui permet à la
       recherche globale de mener au bon tableau et non à la seule page. */
    var vise = (function () {
      var m = /(?:^|[#&])onglet=([^&]+)/.exec(global.location.hash || '');
      return m ? decodeURIComponent(m[1]) : null;
    })();
    var defaut = 0;
    if (vise) {
      items.forEach(function (item, i) { if (item.id === vise) defaut = i; });
    }

    items.forEach(function (item, i) {
      var btn = el('button.tab', { type: 'button', role: 'tab', dataset: { tab: item.id } });
      btn.appendChild(document.createTextNode(item.label));
      if (item.badge != null) btn.appendChild(el('span.ml-1.5.rounded-full.bg-slate-100.px-1\\.5.py-0\\.5.text-\\[10px\\].font-semibold.text-slate-600', { text: String(item.badge) }));
      btn.addEventListener('click', function () { select(item, btn); });
      bar.appendChild(btn);
      if (i === defaut) setTimeout(function () { select(item, btn); }, 0);
    });

    wrap.appendChild(bar);
    wrap.appendChild(panel);
    wrap.selectTab = function (id) {
      var btn = bar.querySelector('[data-tab="' + id + '"]');
      if (btn) btn.click();
    };
    return wrap;
  }

  /** Liste descriptive clé → valeur (fiches, profils). */
  function descList(pairs, cols) {
    var dl = el('dl.grid.gap-x-6.gap-y-3', { class: cols || 'grid-cols-1 sm:grid-cols-2' });
    pairs.forEach(function (p) {
      if (!p) return;
      var d = el('div');
      d.appendChild(el('dt.text-xs.text-slate-500', { text: p[0] }));
      var val = el('dd.mt-0\\.5.text-sm.font-medium.text-slate-800');
      /* Une liste de nœuds (badge + texte) se rend comme telle : String()
         l'aurait écrasée en « [object HTMLElement] ». */
      if (p[1] instanceof Node || Array.isArray(p[1])) C.append(val, p[1]);
      else val.textContent = p[1] == null || p[1] === '' ? '—' : String(p[1]);
      d.appendChild(val);
      dl.appendChild(d);
    });
    return dl;
  }

  /** Fil chronologique (timeline) — historique et journal. */
  function timeline(events) {
    var ul = el('ol.relative.space-y-4.border-l.border-slate-200.pl-5');
    if (!events.length) return empty('Aucun événement enregistré.', { icon: 'history' });
    events.forEach(function (ev) {
      var li = el('li.relative');
      li.appendChild(el('span.absolute.-left-\\[1\\.4rem\\].mt-1.grid.h-4.w-4.place-items-center.rounded-full.ring-4.ring-white',
        { class: 'bg-' + (ev.tone || 'navy') + '-' + (ev.tone === 'neutral' ? '300' : '500') }));
      li.appendChild(el('p.text-sm.font-medium.text-slate-800', { text: ev.title }));
      if (ev.detail) li.appendChild(el('p.text-xs.text-slate-500', { text: ev.detail }));
      li.appendChild(el('p.mt-0\\.5.text-xs.text-slate-400', { text: ev.date }));
      ul.appendChild(li);
    });
    return ul;
  }

  /* ==========================================================================
   * LISTE DÉROULANTE AVEC RECHERCHE (combo)
   * -------------------------------------------------------------------------
   * Une liste native devient inutilisable dès quelques dizaines d'entrées :
   * choisir un patient parmi 180, un article parmi 184 ou un compte parmi 93
   * oblige à faire défiler. Ce composant garde la même interface qu'un <select>
   * — propriété `value`, événement `change` — mais ouvre un panneau muni d'un
   * champ de recherche, d'une navigation au clavier et d'une ligne de détail
   * (code dossier, stock disponible, numéro de compte…).
   *
   * Le panneau est positionné en `fixed` : il ne peut donc pas être rogné par
   * le défilement d'une modale ou d'un tiroir.
   * ======================================================================== */
  var MAX_AFFICHE = 60;

  function normOptions(options) {
    return (options || []).map(function (o) {
      if (o == null) return null;
      if (typeof o === 'object') {
        return {
          value: String(o.value != null ? o.value : ''),
          label: String(o.label != null ? o.label : o.value),
          detail: o.detail != null ? String(o.detail) : null,
          icon: o.icon || null,
          groupe: o.groupe || null,
        };
      }
      return { value: String(o), label: String(o), detail: null, icon: null, groupe: null };
    }).filter(Boolean);
  }

  /**
   * combo([{value,label,detail,icon}], { value, placeholder, allowEmpty,
   *        emptyLabel, searchPlaceholder, onChange, compact })
   * Retourne l'élément conteneur, qui expose `value`, `options`, `setOptions()`
   * et émet `change` — il se substitue à un <select> partout où il est attendu.
   */
  function combo(options, opts) {
    opts = opts || {};
    var items = normOptions(options);
    var multiple = !!opts.multiple;
    var placeholder = opts.placeholder || (multiple ? '— Aucune sélection —' : '— Sélectionner —');
    var valeur = opts.value != null && !multiple ? String(opts.value) : '';
    /* En mode multiple, la sélection est une liste de valeurs. Le panneau reste
       ouvert d'un choix à l'autre : on coche, on décoche, on referme quand on
       a terminé. */
    var valeurs = multiple ? normValeurs(opts.value) : [];
    var actif = -1, visibles = [];

    function normValeurs(v) {
      if (v == null || v === '') return [];
      var t = Array.isArray(v) ? v : String(v).split(',');
      var out = [];
      t.forEach(function (x) {
        var s = String(x).trim();
        if (s && out.indexOf(s) < 0) out.push(s);
      });
      return out;
    }
    function estChoisi(v) { return multiple ? valeurs.indexOf(String(v)) >= 0 : String(v) === valeur; }
    function selectionnes() {
      return items.filter(function (it) { return valeurs.indexOf(it.value) >= 0; });
    }

    var wrap = el('div.combo');
    var btn = el('button.combo-input', {
      type: 'button', 'aria-haspopup': 'listbox', 'aria-expanded': 'false',
      class: opts.compact ? 'combo-input-sm' : '',
    });
    var txt = el('span.combo-value.truncate');
    btn.appendChild(txt);
    btn.appendChild(C.icon('chevron-down', 'h-4 w-4 shrink-0 text-slate-400'));
    wrap.appendChild(btn);

    var panneau = el('div.combo-panel', { hidden: true });
    var champ = el('input.combo-search', {
      type: 'search', autocomplete: 'off', spellcheck: 'false',
      placeholder: opts.searchPlaceholder || 'Rechercher…', 'aria-label': 'Rechercher dans la liste',
    });
    var barre = el('div.relative.border-b.border-slate-200.p-2', null, [
      el('span.pointer-events-none.absolute.left-4.top-1\\/2.-translate-y-1\\/2.text-slate-400', null, C.icon('search', 'h-4 w-4')),
      champ,
    ]);
    var liste = el('div.combo-list', { role: 'listbox' });
    var pied = el('p.border-t.border-slate-100.px-3.py-1\\.5.text-\\[11px\\].text-slate-400');
    panneau.appendChild(barre);
    panneau.appendChild(liste);
    panneau.appendChild(pied);
    document.body.appendChild(panneau);

    function courant() {
      for (var i = 0; i < items.length; i++) if (items[i].value === valeur) return items[i];
      return null;
    }

    function peindre() {
      if (multiple) {
        var sel = selectionnes();
        txt.textContent = !sel.length ? placeholder
          : (sel.length <= 2
            ? sel.map(function (it) { return it.label; }).join(', ')
            : sel.length + ' sélectionnées');
        txt.classList.toggle('text-slate-400', !sel.length);
        txt.classList.toggle('text-slate-900', !!sel.length);
        return;
      }
      var c = courant();
      txt.textContent = c ? c.label : placeholder;
      txt.classList.toggle('text-slate-400', !c);
      txt.classList.toggle('text-slate-900', !!c);
    }

    function ligne(it, index) {
      var o = el('div.combo-option', { role: 'option', 'data-value': it.value });
      if (it.icon) o.appendChild(el('span.shrink-0.text-slate-400', null, C.icon(it.icon, 'h-4 w-4')));
      var corps = el('span.min-w-0.flex-1', null, [el('span.block.truncate', { text: it.label })]);
      if (it.detail) corps.appendChild(el('span.block.truncate.text-\\[11px\\].text-slate-400', { text: it.detail }));
      o.appendChild(corps);
      if (estChoisi(it.value)) {
        o.classList.add('combo-option-selected');
        o.setAttribute('aria-selected', 'true');
        o.appendChild(C.icon(multiple ? 'check-square' : 'check', 'h-4 w-4 shrink-0 text-navy-700'));
      } else if (multiple) {
        o.setAttribute('aria-selected', 'false');
        o.appendChild(C.icon('square', 'h-4 w-4 shrink-0 text-slate-300'));
      }
      if (index === actif) o.classList.add('combo-option-active');
      o.addEventListener('mouseenter', function () { actif = index; marquer(); });
      o.addEventListener('click', function () { choisir(it.value); });
      return o;
    }

    function marquer() {
      $$('.combo-option', liste).forEach(function (n, i) {
        n.classList.toggle('combo-option-active', i === actif);
        if (i === actif && n.scrollIntoView) n.scrollIntoView({ block: 'nearest' });
      });
    }

    function rendre() {
      var q = champ.value.trim();
      visibles = items.filter(function (it) {
        return !q || C.matches(it.label + ' ' + (it.detail || ''), q);
      });
      if (opts.allowEmpty && !multiple) visibles = [{ value: '', label: opts.emptyLabel || placeholder, detail: null, icon: null }].concat(visibles);

      C.clear(liste);
      var montres = visibles.slice(0, MAX_AFFICHE);
      if (!montres.length) {
        liste.appendChild(el('p.px-3.py-6.text-center.text-xs.text-slate-400', { text: 'Aucun résultat pour « ' + q + ' ».' }));
      } else {
        montres.forEach(function (it, i) { liste.appendChild(ligne(it, i)); });
      }
      var compte = visibles.length > MAX_AFFICHE
        ? montres.length + ' entrées affichées sur ' + visibles.length + ' — affiner la recherche'
        : visibles.length + ' entrée(s)';
      if (multiple) {
        C.clear(pied);
        pied.className = 'flex items-center justify-between gap-2 border-t border-slate-100 px-3 py-1.5 text-[11px] text-slate-400';
        pied.appendChild(el('span', { text: valeurs.length + ' sélectionnée(s) · ' + compte }));
        if (valeurs.length) {
          pied.appendChild(el('button.text-\\[11px\\].font-medium.text-navy-700.underline', {
            type: 'button',
            onclick: function () { valeurs = []; peindre(); rendre(); notifier(); },
          }, 'Tout effacer'));
        }
      } else {
        pied.textContent = compte;
      }
      icons(liste);
    }

    function placer() {
      var r = btn.getBoundingClientRect();
      var dispoBas = global.innerHeight - r.bottom - 12;
      var hauteur = Math.min(320, Math.max(180, dispoBas));
      var versLeHaut = dispoBas < 200 && r.top > dispoBas;
      panneau.style.left = Math.max(8, Math.min(r.left, global.innerWidth - r.width - 8)) + 'px';
      panneau.style.width = Math.max(r.width, 240) + 'px';
      panneau.style.maxHeight = (versLeHaut ? Math.min(320, r.top - 12) : hauteur) + 'px';
      if (versLeHaut) {
        panneau.style.top = 'auto';
        panneau.style.bottom = (global.innerHeight - r.top + 4) + 'px';
      } else {
        panneau.style.bottom = 'auto';
        panneau.style.top = (r.bottom + 4) + 'px';
      }
    }

    function ouvrir() {
      if (wrap.hasAttribute('data-disabled')) return;
      champ.value = '';
      actif = 0;
      rendre();
      panneau.hidden = false;
      placer();
      btn.setAttribute('aria-expanded', 'true');
      champ.focus();
      global.addEventListener('resize', placer);
      global.addEventListener('scroll', placer, true);
      document.addEventListener('mousedown', dehors, true);
    }

    function fermer() {
      if (panneau.hidden) return;
      panneau.hidden = true;
      btn.setAttribute('aria-expanded', 'false');
      global.removeEventListener('resize', placer);
      global.removeEventListener('scroll', placer, true);
      document.removeEventListener('mousedown', dehors, true);
    }

    function dehors(e) {
      if (panneau.contains(e.target) || wrap.contains(e.target)) return;
      fermer();
    }

    function notifier() {
      wrap.dispatchEvent(new Event('change', { bubbles: true }));
      if (opts.onChange) opts.onChange(multiple ? valeurs.slice() : valeur, multiple ? selectionnes() : courant());
    }

    function choisir(v) {
      if (multiple) {
        var s = String(v), i = valeurs.indexOf(s);
        if (i >= 0) valeurs.splice(i, 1); else valeurs.push(s);
        peindre();
        rendre();
        notifier();
        return;
      }
      valeur = String(v);
      peindre();
      fermer();
      btn.focus();
      notifier();
    }

    btn.addEventListener('click', function () { panneau.hidden ? ouvrir() : fermer(); });
    btn.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') { e.preventDefault(); ouvrir(); }
    });
    champ.addEventListener('input', function () { actif = 0; rendre(); });
    champ.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown') { e.preventDefault(); actif = Math.min(actif + 1, Math.min(visibles.length, MAX_AFFICHE) - 1); marquer(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); actif = Math.max(actif - 1, 0); marquer(); }
      else if (e.key === 'Enter') {
        e.preventDefault();
        var it = visibles[actif];
        if (it) choisir(it.value);
      } else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); fermer(); btn.focus(); }
    });

    /* Le conteneur se comporte comme un <select> pour le reste du code. */
    Object.defineProperty(wrap, 'value', {
      get: function () { return multiple ? valeurs.slice() : valeur; },
      set: function (v) {
        if (multiple) { valeurs = normValeurs(v); } else { valeur = v == null ? '' : String(v); }
        peindre();
        if (!panneau.hidden) rendre();
      },
    });
    Object.defineProperty(wrap, 'disabled', {
      get: function () { return wrap.hasAttribute('data-disabled'); },
      set: function (v) {
        if (v) { wrap.setAttribute('data-disabled', ''); btn.disabled = true; }
        else { wrap.removeAttribute('data-disabled'); btn.disabled = false; }
      },
    });
    wrap.focus = function () { btn.focus(); };
    wrap.setOptions = function (nouvelles, garderValeur) {
      items = normOptions(nouvelles);
      if (multiple) {
        /* Une valeur qui n'existe plus dans la nouvelle liste est abandonnée. */
        valeurs = garderValeur === false ? [] : valeurs.filter(function (v) {
          return items.some(function (it) { return it.value === v; });
        });
      } else if (!garderValeur || !courant()) { valeur = ''; }
      peindre();
      if (!panneau.hidden) rendre();
    };
    wrap.options = function () { return items.slice(); };
    wrap.selected = function () { return multiple ? selectionnes() : courant(); };
    /* Le panneau vit dans <body> : il doit disparaître avec son déclencheur. */
    wrap.destroy = function () { fermer(); panneau.remove(); };

    peindre();
    return wrap;
  }

  /* Nettoie les panneaux orphelins quand une modale ou un tiroir se referme. */
  function nettoyerCombos(racine) {
    $$('.combo', racine).forEach(function (c) { if (c.destroy) c.destroy(); });
  }

  /* ==========================================================================
   * FORMULAIRES
   * ======================================================================== */
  /**
   * form([{name,label,type,required,options,value,help,col}], values)
   * types : text, number, date, time, select, multiselect, textarea, checkbox,
   *         money, tel, email
   * `multiselect` retourne un tableau de valeurs ; `required` y exige au moins
   * une entrée.
   */
  function form(fields, values) {
    values = values || {};
    /* SIX colonnes, parce que six se divise par deux ET par trois. Les
       largeurs se déclarent par `col` : absent = un demi (span 3),
       'third' = un tiers (span 2), 'full' = toute la largeur (span 6). */
    var node = el('form.grid.grid-cols-1.gap-4.sm\\:grid-cols-6', { novalidate: true });
    var LARGEURS = { full: 'sm:col-span-6', third: 'sm:col-span-2', half: 'sm:col-span-3' };
    var controls = {};
    /* Le conteneur de chaque champ : c'est LUI qu'on masque, et non le
       contrôle — masquer le contrôle seul laisserait son libellé orphelin. */
    var conteneurs = {};

    fields.forEach(function (f) {
      if (!f) return;
      var wrap = el('div', { class: LARGEURS[f.col] || LARGEURS.half });
      if (f.type === 'section') {
        wrap.className = 'sm:col-span-6 border-t border-slate-200 pt-3 first:border-0 first:pt-0';
        wrap.appendChild(el('p.text-xs.font-semibold.uppercase.tracking-wide.text-slate-500', { text: f.label }));
        node.appendChild(wrap); return;
      }

      var id = 'f_' + f.name;
      var lbl = el('label.label', { for: id, text: f.label + (f.required ? ' *' : '') });
      wrap.appendChild(lbl);

      var ctrl, val = values[f.name] != null ? values[f.name] : (f.value != null ? f.value : '');
      /* Au-delà d'une poignée d'entrées, la liste native devient pénible :
         on bascule sur la liste déroulante à recherche. `search: false` force
         le comportement natif, `search: true` l'impose sur une liste courte. */
      var longue = f.search === true || (f.search !== false && (f.options || []).length > 8);
      if (f.type === 'multiselect') {
        /* Sélection multiple : toujours le panneau à recherche. Le <select
           multiple> natif, qui exige de garder Ctrl enfoncé, est inutilisable
           sur une liste de quarante-huit analyses. La valeur est un tableau. */
        ctrl = combo(f.options, {
          multiple: true,
          value: val,
          placeholder: f.placeholder || '— Aucune sélection —',
          searchPlaceholder: f.searchPlaceholder || 'Rechercher…',
        });
        ctrl.id = id;
      } else if (f.type === 'select' && longue) {
        /* Une liste native sélectionne d'office sa première entrée : on
           conserve ce comportement pour les champs obligatoires, sans quoi une
           saisie déjà rodée se retrouverait bloquée sur un champ vide. */
        var premier = (f.options || [])[0];
        if (f.required && (val === '' || val == null) && premier != null) {
          val = typeof premier === 'object' ? premier.value : premier;
        }
        ctrl = combo(f.options, {
          value: val,
          placeholder: f.placeholder || '— Sélectionner —',
          allowEmpty: !f.required,
          emptyLabel: f.placeholder || '— Aucun —',
          searchPlaceholder: f.searchPlaceholder || 'Rechercher…',
        });
        ctrl.id = id;
      } else if (f.type === 'select') {
        ctrl = el('select.select', { id: id, name: f.name });
        if (!f.required) ctrl.appendChild(el('option', { value: '' }, f.placeholder || '— Sélectionner —'));
        (f.options || []).forEach(function (o) {
          var ov = typeof o === 'object' ? o.value : o;
          var ol = typeof o === 'object' ? o.label : o;
          var opt = el('option', { value: ov }, ol);
          if (String(ov) === String(val)) opt.selected = true;
          ctrl.appendChild(opt);
        });
      } else if (f.type === 'textarea') {
        ctrl = el('textarea.textarea', { id: id, name: f.name, rows: f.rows || 3, placeholder: f.placeholder || '' });
        ctrl.value = val;
      } else if (f.type === 'checkbox') {
        wrap.removeChild(lbl);
        var row = el('label.flex.cursor-pointer.items-center.gap-2.pt-5');
        ctrl = el('input.checkbox', { type: 'checkbox', id: id, name: f.name });
        ctrl.checked = !!val;
        row.appendChild(ctrl);
        row.appendChild(el('span.text-sm.text-slate-700', { text: f.label }));
        wrap.appendChild(row);
      } else {
        var t = f.type === 'money' ? 'number' : (f.type || 'text');
        /* E328 : un instant ISO avec fuseau (« …T09:00:00.000Z », la forme des dates écrites par l’agenda) est REFUSÉ par un champ
           datetime-local — il restait vide et l’édition échouait sur « Date et heure » obligatoire. On le relit à l’heure locale. */
        if (f.type === 'datetime-local' && val && /(Z|[+-]\d{2}:?\d{2})$/.test(String(val))) val = C.isoLocal(val);
        ctrl = el('input.input', {
          type: t, id: id, name: f.name, placeholder: f.placeholder || '',
          min: f.min, max: f.max, step: f.step || (f.type === 'money' ? 1 : null),
        });
        /* Un champ `datetime-local` ne reçoit que « AAAA-MM-JJThh:mm » : une date ISO complète (secondes, fuseau) y est REFUSÉE par le navigateur,
           le champ s'ouvre vide et, s'il est obligatoire, la fiche ne peut plus être corrigée sans ressaisir la date (écart E402). */
        ctrl.value = (t === 'datetime-local' && val && /(Z|[+-]\d\d:\d\d|:\d\d\.\d+)$/.test(String(val))) ? global.SIGH.core.isoLocal(val) : val;
      }
      if (f.readonly) {
        if (ctrl.classList.contains('combo')) ctrl.disabled = true;
        else { ctrl.setAttribute('readonly', ''); ctrl.classList.add('bg-slate-50'); }
      }
      if (f.disabled) ctrl.disabled = true;
      controls[f.name] = ctrl;

      if (f.type !== 'checkbox') wrap.appendChild(ctrl);
      if (f.help || f.hint) wrap.appendChild(el('p.mt-1.text-xs.text-slate-400', { text: f.help || f.hint }));
      wrap.appendChild(el('p.field-error', { dataset: { errorFor: f.name }, hidden: true }));
      conteneurs[f.name] = wrap;
      node.appendChild(wrap);
    });

    /* ======================================================================
     * LES CHAMPS CONDITIONNELS — AU SOCLE, PAS DANS CHAQUE ÉCRAN (21/09/2026)
     * ----------------------------------------------------------------------
     * Un champ qui porte `condition: { controle, quand }` n'apparaît que
     * lorsque le champ nommé prend l'une des valeurs nommées. La mécanique
     * existait déjà — écrite À LA MAIN dans la saisie des comptes rendus
     * d'imagerie, où elle sert les « Autre → préciser ». L'y laisser aurait
     * obligé chaque écran qui en veut à la réécrire, et la deuxième copie
     * aurait divergé de la première au premier correctif. Elle descend donc
     * là où tous les formulaires la trouvent.
     *
     * UN CHAMP MASQUÉ NE S'ENREGISTRE NI NE SE VALIDE. C'est la règle que la
     * saisie d'imagerie avait déjà posée : une valeur invisible est une
     * valeur qu'on ne relira jamais, et qu'on imprimerait pourtant. Un
     * `required` sur un champ masqué bloquerait le formulaire sur un champ
     * que l'utilisateur ne voit pas — le plus sûr moyen de le rendre fou.
     * ==================================================================== */
    function valeurCorrespond(cond, valeur) {
      var v = String(valeur == null ? '' : valeur).toLowerCase();
      return (cond.quand || []).some(function (q) { return String(q).toLowerCase() === v; });
    }
    function champMasque(f) {
      if (!f || !f.condition || !conteneurs[f.name]) return false;
      var c = controls[f.condition.controle];
      /* LE CONTRÔLANT EST AILLEURS : on ne décide pas à la place de
         l'appelant. La saisie des comptes rendus d'imagerie répartit ses
         champs sur PLUSIEURS formulaires — un bloc de sac répété est un
         formulaire à lui seul — et résout ses conditions d'un formulaire à
         l'autre. Masquer ici au motif que le champ nommé est introuvable
         ferait disparaître une précision que l'appelant vient d'afficher,
         et `collect()` la perdrait en silence. */
      if (!c) return false;
      return !valeurCorrespond(f.condition, c.value);
    }
    function actualiserConditions() {
      fields.forEach(function (f) {
        if (!f || !f.condition || !conteneurs[f.name]) return;
        conteneurs[f.name].classList.toggle('hidden', champMasque(f));
      });
    }
    var controlants = {};
    fields.forEach(function (f) { if (f && f.condition) controlants[f.condition.controle] = true; });
    Object.keys(controlants).forEach(function (nom) {
      var c = controls[nom];
      if (!c || !c.addEventListener) return;
      c.addEventListener('change', actualiserConditions);
      c.addEventListener('input', actualiserConditions);
    });
    actualiserConditions();

    node.addEventListener('submit', function (e) { e.preventDefault(); });

    /** Valide et retourne les valeurs, ou null si invalide (erreurs affichées). */
    node.collect = function () {
      var out = {}, ok = true;
      $$('[data-error-for]', node).forEach(function (p) { p.hidden = true; p.textContent = ''; });
      fields.forEach(function (f) {
        if (!f || f.type === 'section') return;
        var ctrl = controls[f.name];
        if (!ctrl) return;
        /* Masqué par sa condition : ni valeur, ni contrôle d'obligation. */
        if (champMasque(f)) return;
        ctrl.classList.remove('input-error');
        var v = f.type === 'checkbox' ? ctrl.checked : ctrl.value;
        if (f.type === 'number' || f.type === 'money') v = v === '' ? null : Number(v);
        var vide = Array.isArray(v) ? v.length === 0 : (v === '' || v == null || v === false);
        if (f.required && vide) {
          ok = false; ctrl.classList.add('input-error');
          var p = node.querySelector('[data-error-for="' + f.name + '"]');
          if (p) { p.textContent = 'Ce champ est obligatoire.'; p.hidden = false; }
        } else if (f.validate && v !== '' && v != null) {
          var msg = f.validate(v, out);
          if (msg) {
            ok = false; ctrl.classList.add('input-error');
            var p2 = node.querySelector('[data-error-for="' + f.name + '"]');
            if (p2) { p2.textContent = msg; p2.hidden = false; }
          }
        }
        out[f.name] = v;
      });
      if (!ok) {
        var firstErr = node.querySelector('.input-error');
        if (firstErr) firstErr.focus();
        return null;
      }
      return out;
    };
    node.controls = controls;
    node.conteneurs = conteneurs;
    node.actualiserConditions = actualiserConditions;
    return node;
  }

  /* ==========================================================================
   * TABLEAU DE DONNÉES
   * -------------------------------------------------------------------------
   * Tri, recherche, filtres, pagination, sélection multiple, colonnes
   * configurables, actions par ligne, exports CSV / impression.
   * ======================================================================== */
  function dataTable(config) {
    var cfg = Object.assign({
      columns: [], rows: [], pageSize: 12, searchable: true, selectable: false,
      filters: [], actions: null, rowActions: null, onRowClick: null,
      emptyMessage: 'Aucun enregistrement.', emptyHint: null, title: null,
      exportName: 'export', toolbar: null, dense: false,
    }, config);

    var state = { page: 1, sort: cfg.defaultSort || null, dir: cfg.defaultDir || 'asc', q: '', filters: {}, selected: {}, hidden: {} };
    var root = el('div.card.overflow-hidden');

    /* --- Barre d'outils --------------------------------------------------- */
    var toolbar = el('div.flex.flex-wrap.items-center.gap-2.border-b.border-slate-200.px-4.py-3');
    if (cfg.title) toolbar.appendChild(el('h3.mr-auto.text-sm.font-semibold.text-slate-900', { text: cfg.title }));

    var searchInput = null;
    if (cfg.searchable) {
      var sWrap = el('div.relative.min-w-\\[14rem\\].flex-1', { class: cfg.title ? 'max-w-xs' : '' });
      sWrap.appendChild(el('span.pointer-events-none.absolute.left-2\\.5.top-1\\/2.-translate-y-1\\/2.text-slate-400', null, C.icon('search', 'h-4 w-4')));
      searchInput = el('input.input.pl-8', { type: 'search', placeholder: cfg.searchPlaceholder || 'Rechercher…', 'aria-label': 'Rechercher' });
      searchInput.addEventListener('input', C.debounce(function () { state.q = searchInput.value; state.page = 1; render(); }, 180));
      sWrap.appendChild(searchInput);
      toolbar.appendChild(sWrap);
    }
    if (!cfg.title) toolbar.appendChild(el('div.flex-1'));

    cfg.filters.forEach(function (f) {
      var sel = el('select.select.w-auto.min-w-\\[9rem\\]', { 'aria-label': f.label });
      sel.appendChild(el('option', { value: '' }, f.label));
      (f.options || []).forEach(function (o) {
        var ov = typeof o === 'object' ? o.value : o;
        var ol = typeof o === 'object' ? o.label : o;
        sel.appendChild(el('option', { value: ov }, ol));
      });
      sel.addEventListener('change', function () { state.filters[f.name] = sel.value; state.page = 1; render(); });
      toolbar.appendChild(sel);
    });

    /* Colonnes configurables */
    var colBtn = el('button.btn.btn-secondary.btn-sm', { type: 'button', title: 'Colonnes affichées' }, [C.icon('columns-3', 'h-4 w-4'), 'Colonnes']);
    colBtn.addEventListener('click', function () {
      var list = el('div.space-y-2');
      cfg.columns.forEach(function (c) {
        if (c.key === '_actions') return;
        var row = el('label.flex.cursor-pointer.items-center.gap-2.text-sm');
        var cb = el('input.checkbox', { type: 'checkbox' });
        cb.checked = !state.hidden[c.key];
        cb.addEventListener('change', function () { state.hidden[c.key] = !cb.checked; render(); });
        row.appendChild(cb); row.appendChild(el('span', { text: c.label }));
        list.appendChild(row);
      });
      var m = modal({ title: 'Colonnes affichées', size: 'sm', body: list, footer: el('button.btn.btn-primary', { type: 'button', onclick: function () { m.close(); } }, 'Fermer') });
    });
    toolbar.appendChild(colBtn);

    /* Exports */
    var expBtn = el('button.btn.btn-secondary.btn-sm', { type: 'button' }, [C.icon('download', 'h-4 w-4'), 'Exporter']);
    expBtn.addEventListener('click', function () {
      var body = el('div.space-y-2');
      body.appendChild(el('p.text-sm.text-slate-600', { text: 'Choisir le format d’export des ' + filtered().length + ' lignes filtrées.' }));
      var m = modal({
        title: 'Exporter les données', size: 'sm', body: body,
        footer: [
          el('button.btn.btn-secondary', { type: 'button', onclick: function () { m.close(); exportCSV(filtered(), visibleColumns(), cfg.exportName); } }, [C.icon('file-spreadsheet', 'h-4 w-4'), 'CSV / Excel']),
          el('button.btn.btn-primary', { type: 'button', onclick: function () { m.close(); printTable(); } }, [C.icon('printer', 'h-4 w-4'), 'PDF / Impression']),
        ],
      });
    });
    toolbar.appendChild(expBtn);
    if (cfg.actions) C.append(toolbar, cfg.actions);
    root.appendChild(toolbar);

    /* --- Barre de sélection multiple -------------------------------------- */
    var selBar = el('div.hidden.items-center.gap-3.border-b.border-navy-200.bg-navy-50.px-4.py-2');
    var selCount = el('span.text-sm.font-medium.text-navy-900');
    selBar.appendChild(selCount);
    selBar.appendChild(el('div.flex-1'));
    if (cfg.bulkActions) C.append(selBar, cfg.bulkActions(function () { return selectedRows(); }, function () { state.selected = {}; render(); }));
    selBar.appendChild(el('button.btn.btn-ghost.btn-sm', { type: 'button', onclick: function () { state.selected = {}; render(); } }, 'Tout désélectionner'));
    root.appendChild(selBar);

    /* --- Corps ------------------------------------------------------------ */
    var scroller = el('div.overflow-x-auto');
    var tableWrap = el('div');
    scroller.appendChild(tableWrap);
    root.appendChild(scroller);

    var footer = el('div.flex.flex-wrap.items-center.justify-between.gap-3.border-t.border-slate-200.px-4.py-3');
    root.appendChild(footer);

    /* --- Logique ---------------------------------------------------------- */
    function visibleColumns() {
      return cfg.columns.filter(function (c) { return !state.hidden[c.key] && c.key !== '_actions'; });
    }
    function cellValue(row, col) {
      return col.value ? col.value(row) : row[col.key];
    }
    function filtered() {
      var rows = typeof cfg.rows === 'function' ? cfg.rows() : cfg.rows;
      rows = rows.slice();
      if (state.q) {
        rows = rows.filter(function (r) {
          return cfg.columns.some(function (c) {
            if (c.key === '_actions') return false;
            return C.matches(cellValue(r, c), state.q);
          });
        });
      }
      Object.keys(state.filters).forEach(function (k) {
        var v = state.filters[k];
        if (!v) return;
        var f = cfg.filters.filter(function (x) { return x.name === k; })[0];
        rows = rows.filter(function (r) {
          return f && f.match ? f.match(r, v) : String(r[k]) === String(v);
        });
      });
      if (state.sort) {
        var col = cfg.columns.filter(function (c) { return c.key === state.sort; })[0];
        if (col) rows = C.sortBy(rows, function (r) { return col.sortValue ? col.sortValue(r) : cellValue(r, col); }, state.dir);
      }
      return rows;
    }
    function selectedRows() {
      return filtered().filter(function (r) { return state.selected[r.id]; });
    }

    function render() {
      var rows = filtered();
      var pages = Math.max(1, Math.ceil(rows.length / cfg.pageSize));
      if (state.page > pages) state.page = pages;
      var start = (state.page - 1) * cfg.pageSize;
      var pageRows = rows.slice(start, start + cfg.pageSize);
      var cols = visibleColumns();

      C.clear(tableWrap);
      if (!rows.length) {
        tableWrap.appendChild(empty(state.q || Object.keys(state.filters).some(function (k) { return state.filters[k]; })
          ? 'Aucun résultat pour cette recherche.' : cfg.emptyMessage,
          { hint: cfg.emptyHint, icon: 'inbox' }));
      } else {
        var table = el('table.tbl');
        var thead = el('thead'), htr = el('tr');
        if (cfg.selectable) {
          var allCb = el('input.checkbox', { type: 'checkbox', 'aria-label': 'Tout sélectionner' });
          allCb.checked = pageRows.length > 0 && pageRows.every(function (r) { return state.selected[r.id]; });
          allCb.addEventListener('change', function () {
            pageRows.forEach(function (r) {
              if (allCb.checked) state.selected[r.id] = true; else delete state.selected[r.id];
            });
            render();
          });
          htr.appendChild(el('th.w-10', null, allCb));
        }
        cols.forEach(function (c) {
          var th = el('th', { class: (c.align === 'right' ? 'text-right' : '') + (c.sortable === false ? '' : ' th-sortable') });
          var inner = el('span.inline-flex.items-center.gap-1', null, [c.label]);
          if (c.sortable !== false) {
            if (state.sort === c.key) inner.appendChild(C.icon(state.dir === 'asc' ? 'chevron-up' : 'chevron-down', 'h-3.5 w-3.5'));
            th.addEventListener('click', function () {
              if (state.sort === c.key) state.dir = state.dir === 'asc' ? 'desc' : 'asc';
              else { state.sort = c.key; state.dir = 'asc'; }
              render();
            });
          }
          th.appendChild(inner);
          htr.appendChild(th);
        });
        if (cfg.rowActions) htr.appendChild(el('th.w-24.text-right', null, 'Actions'));
        thead.appendChild(htr); table.appendChild(thead);

        var tbody = el('tbody');
        pageRows.forEach(function (r) {
          var tr = el('tr', { dataset: { selected: state.selected[r.id] ? 'true' : 'false' } });
          if (cfg.onRowClick) {
            tr.classList.add('cursor-pointer');
            tr.addEventListener('click', function (e) {
              if (e.target.closest('button,input,a')) return;
              cfg.onRowClick(r);
            });
          }
          if (cfg.selectable) {
            var cb = el('input.checkbox', { type: 'checkbox', 'aria-label': 'Sélectionner la ligne' });
            cb.checked = !!state.selected[r.id];
            cb.addEventListener('change', function () {
              if (cb.checked) state.selected[r.id] = true; else delete state.selected[r.id];
              render();
            });
            var tdSel = el('td', null, cb);
            tdSel.addEventListener('click', function (e) { e.stopPropagation(); });
            tr.appendChild(tdSel);
          }
          cols.forEach(function (c) {
            var td = el('td', { class: (c.align === 'right' ? 'text-right num' : '') + (c.nowrap ? ' whitespace-nowrap' : '') });
            var content = c.render ? c.render(r) : cellValue(r, c);
            if (content instanceof Node) td.appendChild(content);
            else td.textContent = content == null || content === '' ? '—' : String(content);
            tr.appendChild(td);
          });
          if (cfg.rowActions) {
            var td2 = el('td.text-right');
            var wrap = el('div.flex.items-center.justify-end.gap-1');
            C.append(wrap, cfg.rowActions(r));
            /* Un clic dans la colonne Actions n'est JAMAIS un clic sur la
               ligne. Sans cet arrêt, le crayon ouvrait la modale d'édition ET
               le tiroir de consultation : à la souris, la cible du clic est le
               <svg> de l'icône, et la remontée par closest() ne rattrape pas
               le bouton comme elle le fait depuis un nœud HTML. Arrêter ici
               vaut pour tous les tableaux du prototype d'un seul coup. */
            td2.addEventListener('click', function (e) { e.stopPropagation(); });
            td2.appendChild(wrap);
            tr.appendChild(td2);
          }
          tbody.appendChild(tr);
        });
        table.appendChild(tbody);
        tableWrap.appendChild(table);
      }

      /* Pied : compteur + pagination */
      C.clear(footer);
      footer.appendChild(el('p.text-xs.text-slate-500', {
        text: rows.length ? ('Affichage de ' + (start + 1) + ' à ' + Math.min(start + cfg.pageSize, rows.length) + ' sur ' + rows.length + ' enregistrement' + (rows.length > 1 ? 's' : '')) : 'Aucun enregistrement',
      }));
      if (pages > 1) {
        var pager = el('div.flex.items-center.gap-1');
        pager.appendChild(el('button.btn.btn-secondary.btn-sm', {
          type: 'button', disabled: state.page === 1,
          onclick: function () { state.page--; render(); },
        }, C.icon('chevron-left', 'h-4 w-4')));
        var from = Math.max(1, state.page - 2), to = Math.min(pages, from + 4);
        from = Math.max(1, to - 4);
        for (var p = from; p <= to; p++) {
          (function (pp) {
            pager.appendChild(el('button.btn.btn-sm', {
              type: 'button', class: pp === state.page ? 'btn-primary' : 'btn-secondary',
              onclick: function () { state.page = pp; render(); },
            }, String(pp)));
          })(p);
        }
        pager.appendChild(el('button.btn.btn-secondary.btn-sm', {
          type: 'button', disabled: state.page === pages,
          onclick: function () { state.page++; render(); },
        }, C.icon('chevron-right', 'h-4 w-4')));
        footer.appendChild(pager);
      }

      /* Barre de sélection */
      var n = Object.keys(state.selected).length;
      selBar.className = n ? 'flex items-center gap-3 border-b border-navy-200 bg-navy-50 px-4 py-2' : 'hidden';
      selCount.textContent = n + ' ligne' + (n > 1 ? 's' : '') + ' sélectionnée' + (n > 1 ? 's' : '');

      icons(root);
    }

    function printTable() {
      var rows = filtered(), cols = visibleColumns();
      global.SIGH.print.etat({
        titre: cfg.title || cfg.exportName || 'État',
        contenu: printableTable(rows, cols),
      });
    }
    function printableTable(rows, cols) {
      var t = el('table.tbl.w-full');
      var thead = el('thead'), htr = el('tr');
      cols.forEach(function (c) { htr.appendChild(el('th', { class: c.align === 'right' ? 'text-right' : '', text: c.label })); });
      thead.appendChild(htr); t.appendChild(thead);
      var tb = el('tbody');
      rows.forEach(function (r) {
        var tr = el('tr');
        cols.forEach(function (c) {
          var v = c.text ? c.text(r) : cellValue(r, c);
          if (v instanceof Node) v = v.textContent;
          tr.appendChild(el('td', { class: c.align === 'right' ? 'text-right num' : '', text: v == null ? '—' : String(v) }));
        });
        tb.appendChild(tr);
      });
      t.appendChild(tb);
      return t;
    }

    root.refresh = render;
    /* Les lignes RETENUES par la recherche et les filtres : un état imprimé
       depuis le tableau doit porter ce que l'utilisateur voit, pas la
       collection entière. */
    root.lignesFiltrees = filtered;
    root.getFiltered = filtered;
    root.getSelected = selectedRows;
    render();
    return root;
  }

  /* ==========================================================================
   * EXPORTS
   * ======================================================================== */
  function exportCSV(rows, columns, name) {
    var sep = ';'; /* Excel FR */
    var head = columns.map(function (c) { return '"' + c.label.replace(/"/g, '""') + '"'; }).join(sep);
    var lines = rows.map(function (r) {
      return columns.map(function (c) {
        var v = c.text ? c.text(r) : (c.value ? c.value(r) : r[c.key]);
        if (v instanceof Node) v = v.textContent;
        if (v == null) v = '';
        return '"' + String(v).replace(/"/g, '""') + '"';
      }).join(sep);
    });
    var csv = '﻿' + [head].concat(lines).join('\r\n');
    var blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    var url = URL.createObjectURL(blob);
    var a = el('a', { href: url, download: (name || 'export') + '-' + C.iso(new Date()) + '.csv' });
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    toast('Export CSV généré (' + rows.length + ' lignes).', { type: 'success' });
  }

  /* ==========================================================================
   * ICÔNES — remplace les <i data-lucide> par des SVG
   * ======================================================================== */
  function icons(root) {
    try {
      if (global.lucide && typeof global.lucide.createIcons === 'function') {
        global.lucide.createIcons({ nameAttr: 'data-lucide', attrs: { 'stroke-width': 1.8 } });
      }
    } catch (e) { /* l'absence d'icônes ne doit jamais casser la page */ }
  }

  /* ==========================================================================
   * ALERTE SONORE
   * --------------------------------------------------------------------------
   * Un rendez-vous ou une réunion qui approche doit s'entendre : le personnel
   * ne regarde pas l'écran en permanence. Le son est synthétisé par l'API audio
   * du navigateur — pas de fichier à charger, donc rien à télécharger et rien à
   * casser hors ligne.
   *
   * Il reste discret et jamais bloquant : un navigateur qui refuse l'audio
   * avant interaction ne doit pas interrompre le traitement en cours.
   * ======================================================================== */
  var SONS = {
    information: [660, 0.12],
    rappel: [880, 0.16],
    alerte: [523, 0.22],
  };

  function sonner(type) {
    try {
      var Ctx = global.AudioContext || global.webkitAudioContext;
      if (!Ctx) return false;
      var spec = SONS[type] || SONS.information;
      var ctx = new Ctx();
      var osc = ctx.createOscillator(), gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = spec[0];
      gain.gain.setValueAtTime(0.0001, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.09, ctx.currentTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + spec[1]);
      osc.connect(gain); gain.connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + spec[1] + 0.02);
      setTimeout(function () { try { ctx.close(); } catch (e) { /* déjà fermé */ } }, 600);
      return true;
    } catch (e) {
      /* Audio indisponible ou refusé : l'information passe par le toast seul. */
      return false;
    }
  }

  /** Notification sonore et visuelle — réunion, consultation, rendez-vous. */
  function alerter(message, opts) {
    opts = opts || {};
    if (opts.silencieux !== true) sonner(opts.son || 'rappel');
    return toast(message, Object.assign({ type: 'info', duration: 7000 }, opts));
  }

  /* ==========================================================================
   * UN MESSAGE QUI SURVIT À LA NAVIGATION
   * --------------------------------------------------------------------------
   * Une page de saisie enregistre puis REVIENT au registre : un toast posé
   * juste avant le départ disparaît avec le document, et l'agent ne voit rien
   * — ni le numéro attribué, ni ce qui a été transmis aux autres postes.
   *
   * Le message est donc déposé dans `sessionStorage` (et non `localStorage` :
   * il appartient à l'onglet en cours, pas au poste) et consommé UNE fois au
   * chargement suivant — le mécanisme du drapeau de repli du ruban, appliqué
   * à un message. Un dépôt qui ne serait jamais consommé — parce que
   * l'utilisateur a fermé l'onglet — meurt avec la session.
   * ======================================================================== */
  var CLE_MESSAGE = 'sigh-cnt:message-differe';

  function toastDiffere(message, opts) {
    try {
      global.sessionStorage.setItem(CLE_MESSAGE, JSON.stringify({
        message: message, opts: opts || {},
      }));
    } catch (e) {
      /* Stockage indisponible : on montre le message tout de suite plutôt
         que de le perdre. Il vaut mieux un message fugace que pas de message. */
      toast(message, opts);
    }
  }

  function consommerMessageDiffere() {
    var brut = null;
    try {
      brut = global.sessionStorage.getItem(CLE_MESSAGE);
      if (brut) global.sessionStorage.removeItem(CLE_MESSAGE);
    } catch (e) { return; }
    if (!brut) return;
    try {
      var o = JSON.parse(brut);
      if (o && o.message) toast(o.message, o.opts || {});
    } catch (e) { /* dépôt illisible : on n'affiche rien */ }
  }

  global.SIGH.ui = {
    texteEnrichi: texteEnrichi, paragrapheEnrichi: paragrapheEnrichi,
    toast: toast, toastDiffere: toastDiffere, consommerMessageDiffere: consommerMessageDiffere,
    modal: modal, confirm: confirm, drawer: drawer, fermerCouches: fermerCouches,
    sonner: sonner, alerter: alerter,
    kpi: kpi, kpiGrid: kpiGrid, card: card, badge: badge, statut: statut, STATUTS: STATUTS,
    empty: empty, loading: loading, errorState: errorState,
    tabs: tabs, descList: descList, timeline: timeline,
    form: form, dataTable: dataTable, exportCSV: exportCSV, icons: icons,
    combo: combo, nettoyerCombos: nettoyerCombos,
  };
})(window);
