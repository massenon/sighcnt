/* =============================================================================
 * SIGH-CNT — Trousse à outils des écrans
 * -----------------------------------------------------------------------------
 * Fabrique les deux gabarits qui structurent la quasi-totalité du prototype :
 *   kit.crud()  — écran de gestion : onglets, KPI, tableau, création, édition,
 *                 archivage annulable, duplication, fiche détaillée, impression.
 *   kit.dash()  — tableau de bord : KPI, graphiques, cartes, actions rapides.
 * Conformité transverse : RG-12 (journalisation) et RG-14 (archivage logique)
 * sont assurées par le magasin de données ; l'annulation est proposée sur
 * chaque mutation via les toasts.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store,
      P = global.SIGH.print, G = global.SIGH.charts, N = global.SIGH.nav;
  var el = C.el;

  function A() { return global.SIGH.app; }

  /* --- Boutons usuels ------------------------------------------------------ */
  function btn(label, opts) {
    opts = opts || {};
    var b = el('button.btn', {
      type: 'button',
      class: (opts.variant ? 'btn-' + opts.variant : 'btn-secondary') + (opts.size ? ' btn-' + opts.size : ''),
      onclick: opts.onclick, title: opts.title,
    });
    if (opts.icon) b.appendChild(C.icon(opts.icon, 'h-4 w-4'));
    if (label) b.appendChild(document.createTextNode(label));
    return b;
  }
  function iconBtn(icon, title, onclick, variant) {
    return el('button.btn.btn-icon.btn-sm', {
      type: 'button', title: title, 'aria-label': title, onclick: onclick,
      class: variant ? 'btn-' + variant : 'btn-ghost',
    }, C.icon(icon, 'h-4 w-4'));
  }
  function lien(id, label, opts) {
    opts = opts || {};
    return el('a.btn', {
      href: A().href(id),
      class: (opts.variant ? 'btn-' + opts.variant : 'btn-secondary') + (opts.size ? ' btn-' + opts.size : ''),
    }, [opts.icon ? C.icon(opts.icon, 'h-4 w-4') : null, label]);
  }

  /* --- Mise en page -------------------------------------------------------- */
  function section(title, subtitle) {
    var d = el('div.mb-3.mt-6');
    d.appendChild(el('h2.text-sm.font-semibold.text-slate-900', { text: title }));
    if (subtitle != null && subtitle !== false) {
      /* DEUX FORMES : une chaîne est un sous-titre ; un NŒUD est le CONTENU
         de la section. Une trentaine d'appelants passent un nœud (miniTable,
         paragraphe), et `{text: nœud}` l'avalait en « [object HTMLElement] » —
         le tiroir montrait son titre et perdait son tableau, sans un mot.
         C'est la sonde du scénario 46 qui l'a pris sur le fait. */
      if (typeof subtitle === 'string' || typeof subtitle === 'number') {
        d.appendChild(el('p.text-xs.text-slate-500', { text: subtitle }));
      } else {
        d.appendChild(subtitle);
      }
    }
    return d;
  }
  /* DEUX FORMES, comme `miniTable` (vague 62). Trente et une vues de détail
     appelaient `K.grid([[libellé, valeur], …])` — la forme « fiche » — alors
     que la fonction n'acceptait qu'une classe et des nœuds : le tableau de
     paires partait dans l'attribut `class`, et le tiroir s'ouvrait VIDE, titre
     seul. Le défaut est corrigé ICI, une fois, et non sur trente et un écrans.
       grid([[libellé, valeur], …])  → fiche libellé / valeur sur deux colonnes
       grid(classe | nombre, nœuds)  → grille de mise en page */
  function grid(cols, children) {
    if (Array.isArray(cols) && children === undefined) {
      var dl = el('dl.grid.grid-cols-1.gap-x-6.gap-y-3.sm:grid-cols-2');
      cols.forEach(function (p) {
        if (!p) return;
        if (!Array.isArray(p)) { C.append(dl, p); return; }
        var v = p[1];
        var dd = el('dd.mt-0\\.5.text-sm.text-slate-800.break-words');
        if (v == null || v === '') dd.textContent = '—';
        else if (typeof v === 'string' || typeof v === 'number') dd.textContent = String(v);
        else C.append(dd, v);
        dl.appendChild(el('div.min-w-0', null, [
          el('dt.text-xs.font-medium.uppercase.tracking-wide.text-slate-500', { text: p[0] }), dd,
        ]));
      });
      return dl;
    }
    var classe = typeof cols === 'number' ? 'grid-cols-1 sm:grid-cols-' + cols : cols;
    return el('div.grid.gap-4', { class: classe }, children);
  }
  function row(children) { return el('div.flex.flex-wrap.items-center.gap-2', null, children); }

  /** Bandeau d'information rattaché à une règle de gestion ou à un document. */
  function note(texte, opts) {
    opts = opts || {};
    var tone = opts.tone || 'info';
    var d = el('div.flex.items-start.gap-2.rounded-lg.border.px-3.py-2', {
      class: 'border-' + tone + '-200 bg-' + tone + '-50',
    });
    d.appendChild(el('span.shrink-0', { class: 'text-' + tone + '-600' }, C.icon(opts.icon || 'info', 'h-4 w-4')));
    /* LA NOTE ÉCHAPPE D'ABORD, PUIS RÉACTIVE UN SOUS-ENSEMBLE FERMÉ de balises
       de mise en forme — le mécanisme déjà posé sur les modales. Le texte
       d'une note paraît statique, mais plusieurs y interpolent une donnée
       saisie : le libellé d'un rôle, que l'administrateur renomme depuis
       `m14-roles`, le nom d'un patient, un motif d'archivage. C'est l'ORDRE
       qui rend la fonction sûre, et toutes les balises réellement employées
       dans les notes du prototype — strong, em, br, code — sont dans
       l'ensemble autorisé. */
    d.appendChild(el('p.text-xs', { class: 'text-' + tone + '-900', html: U.texteEnrichi(texte) }));
    return d;
  }

  /** Mention de provenance : rattache un écran à son document de cadrage. */
  function source(texte) {
    return el('p.mt-2.flex.items-center.gap-1\\.5.text-xs.text-slate-400', null, [
      C.icon('file-check-2', 'h-3.5 w-3.5'),
      el('span', { text: 'Source : ' + texte }),
    ]);
  }

  /* ==========================================================================
   * GABARIT « ÉCRAN DE GESTION »
   * -------------------------------------------------------------------------
   * config = {
   *   collection : nom de la collection du magasin
   *   entite     : libellé au singulier (« patient »)
   *   module     : code module (M1…)
   *   columns    : colonnes du tableau (cf. ui.dataTable)
   *   fields     : champs du formulaire de création / édition
   *   filters    : filtres du tableau
   *   kpis(rows) : blocs KPI calculés
   *   detail(r)  : contenu de la fiche détaillée (drawer)
   *   etat(r)    : état imprimable d'un enregistrement
   *   onCreate   : valeurs par défaut à la création
   *   extraTabs  : onglets additionnels
   *   readonly   : masque les actions de modification
   * }
   * ======================================================================== */
  /* ==========================================================================
   * DROITS DU PROFIL SUR L'ÉCRAN COURANT
   * --------------------------------------------------------------------------
   * La matrice RBAC ne décide pas seulement des écrans VISIBLES : elle décide
   * aussi de ce qu'on peut y FAIRE. Plutôt que de protéger chaque bouton sur
   * chaque écran — cent trente-cinq fois la même ligne, et autant d'oublis —
   * les fabriques du kit consultent ce point unique.
   *
   *   editer  absent → pas de bouton « Nouveau », pas de crayon ;
   *   annuler absent → pas d'archivage ;
   *   les deux absents → l'écran le DIT, il ne se contente pas de masquer.
   * ======================================================================== */
  function droits(code) {
    var app = global.SIGH && global.SIGH.app;
    if (app && typeof app.droits === 'function') return app.droits(code);
    return { voir: true, editer: true, annuler: true, lectureSeule: false };
  }

  /* ==========================================================================
   * UNE COMMANDE D'ÉCRITURE SE DÉCLARE COMME TELLE.
   * --------------------------------------------------------------------------
   * `crud`, `creer` et `actionsLigne` consultent déjà les droits ; les écrans
   * construits à la main, non — et l'audit en a relevé trente-quatre. Un
   * assistant de direction se voyait offrir « Nouvelle commande » et
   * « Valider (DA) », une aide-soignante « Nouvelle ordonnance », un
   * technicien d'échographie « Enregistrer et prescrire ».
   *
   * On ne devine pas ce qui est une écriture à partir du libellé : une
   * protection qui dépend d'un mot change de sens le jour où quelqu'un
   * renomme un bouton. C'est l'AUTEUR qui le déclare, en appelant `commande`
   * au lieu de `btn`.
   *
   * La commande refusée est ABSENTE, non grisée — un bouton grisé invite à
   * chercher pourquoi, un bouton absent dit que ce n'est pas ici que cela se
   * règle. `C.append` ignore les `null` : elle peut donc rester en place dans
   * un tableau d'actions sans que l'appelant ait à filtrer.
   * ======================================================================== */
  function commande(label, opts) {
    var o = opts || {};
    var d = droits(o.moduleCode);
    var accorde = o.droit === 'annuler' ? d.annuler : d.editer;
    return accorde ? btn(label, o) : null;
  }

  /** Même règle pour une commande rendue par une icône seule. */
  function commandeIcone(icone, titre, onclick, opts) {
    var o = typeof opts === 'string' ? { variant: opts } : (opts || {});
    var d = droits(o.moduleCode);
    var accorde = o.droit === 'annuler' ? d.annuler : d.editer;
    return accorde ? iconBtn(icone, titre, onclick, o.variant) : null;
  }

  /** Bandeau affiché quand le profil n'a qu'un droit de lecture sur l'écran. */
  function bandeauLectureSeule(d) {
    var session = S.session() || {};
    var role = N.ROLES[session.role] ? N.ROLES[session.role].label : session.role;
    return note('<strong>Lecture seule</strong> — le profil « ' + role + ' » consulte cet écran sans '
      + 'pouvoir y créer, modifier ni archiver. Ce périmètre est fixé par la matrice des droits '
      + 'd’accès (écran <em>Rôles & permissions</em>) et non par l’écran lui-même.',
    { tone: 'warning', icon: 'lock' });
  }

  function crud(config) {
    var cfg = Object.assign({
      entite: 'enregistrement', entiteP: null, module: '—',
      columns: [], fields: [], filters: [], readonly: false,
      pageSize: 12, selectable: true,
    }, config);
    cfg.entiteP = cfg.entiteP || cfg.entite + 's';

    return function (root) {
      var col = S.collection(cfg.collection, { module: cfg.module, entite: cfg.entite });
      var host = el('div.space-y-4');
      var tableRef = { current: null };
      /* Les droits du profil sur le module de cet écran. Le readonly déclaré
         par l'écran l'emporte toujours : une règle métier prime sur un droit. */
      var D_ = droits(cfg.module);
      var peutEditer = !cfg.readonly && D_.editer;
      var peutAnnuler = !cfg.readonly && D_.annuler;

      function refresh() {
        if (tableRef.current) tableRef.current.refresh();
        if (kpiHost) renderKpis();
      }

      /* Une annulation doit être VISIBLE : le magasin restaure la donnée, mais
         c'est ici que la vue est réaffichée. Sans cette enveloppe, l'utilisateur
         cliquerait « Annuler » sans rien voir revenir dans le tableau. */
      function annulable(undo) {
        return function () { undo(); refresh(); };
      }

      /* --- Formulaire de création / édition ------------------------------- */
      function openForm(record) {
        var isEdit = !!record;
        var f = U.form(typeof cfg.fields === 'function' ? cfg.fields(record) : cfg.fields, record || (cfg.onCreate ? cfg.onCreate() : {}));
        var m = U.modal({
          title: (isEdit ? 'Modifier ' : 'Nouveau ') + (isEdit ? 'l’enregistrement' : cfg.entite),
          subtitle: isEdit ? (record.code || record.reference || record.numero || record.id) : 'Les champs marqués d’un astérisque sont obligatoires.',
          size: cfg.formSize || 'lg',
          body: f,
          footer: [
            btn('Annuler', { onclick: function () { m.close(); } }),
            btn(isEdit ? 'Enregistrer' : 'Créer', {
              variant: 'primary', icon: isEdit ? 'save' : 'plus',
              onclick: function () {
                var values = f.collect();
                if (!values) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (cfg.beforeSave) {
                  var err = cfg.beforeSave(values, record);
                  if (err) { U.toast(err, { type: 'error' }); return; }
                }
                if (cfg.transform) values = cfg.transform(values, record);
                var res = isEdit ? col.update(record.id, values) : col.insert(values);
                m.close(); refresh();
                U.toast(isEdit ? 'Modifications enregistrées.' : 'Nouveau ' + cfg.entite + ' créé.', {
                  type: 'success', undo: annulable(res.undo),
                  detail: res.record.code || res.record.reference || res.record.numero || null,
                });
              },
            }),
          ],
        });
      }

      /* --- Archivage annulable (RG-14) ------------------------------------- */
      function askArchive(record) {
        U.confirm({
          title: 'Archiver cet enregistrement ?',
          message: 'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable dans l’onglet « Archivés ». '
            + 'L’opération est journalisée et peut être annulée.',
          confirmLabel: 'Archiver', danger: true, requireMotif: true,
        }).then(function (r) {
          if (!r) return;
          var res = col.archive(record.id, r.motif);
          refresh();
          U.toast('Enregistrement archivé.', { type: 'success', undo: annulable(res.undo), undoMessage: 'Archivage annulé.' });
        });
      }

      /* --- Fiche détaillée --------------------------------------------------*/
      /* Fiche PAR DÉFAUT d'un écran qui ne déclare pas `detail`. Elle vidait
         l'enregistrement brut : noms de champs techniques (« mereCode »,
         « dateHeure ») et tout objet imbriqué rendu « [object Object] » —
         la fiche du registre des naissances en affichait plusieurs. Elle se
         compose désormais de ce que l'écran déclare DÉJÀ : les colonnes du
         tableau (avec leur rendu), puis les champs du formulaire (avec leur
         libellé et le libellé de l'option choisie). Le vidage brut ne reste
         qu'en dernier recours, valeurs rendues lisibles. */
      function lisible(v) {
        if (v == null || v === '') return null;
        if (v instanceof Node) return v;
        if (typeof v === 'boolean') return v ? 'Oui' : 'Non';
        if (v instanceof Date) return C.dateFR(v);
        if (Array.isArray(v)) {
          var items = v.map(lisible).filter(function (x) { return x != null; });
          if (items.every(function (x) { return typeof x === 'string' || typeof x === 'number'; })) return items.join(', ') || null;
          return items.map(function (x) { return typeof x === 'string' ? el('div', { text: x }) : el('div', null, x); });
        }
        if (typeof v === 'object') {
          return Object.keys(v).filter(function (k) { return k[0] !== '_' && v[k] != null && v[k] !== ''; })
            .map(function (k) { var x = lisible(v[k]); return k + ' : ' + (typeof x === 'string' || typeof x === 'number' ? x : '…'); })
            .join(' · ') || null;
        }
        return v;
      }
      function valeurChamp(f, v) {
        if (f.type === 'checkbox') return v ? 'Oui' : 'Non';
        if (v == null || v === '') return null;
        if (f.options) {
          var opts = typeof f.options === 'function' ? f.options() : f.options;
          var libelle = function (x) {
            var o = (opts || []).filter(function (op) { return (op && typeof op === 'object' ? op.value : op) === x; })[0];
            return o == null ? x : (typeof o === 'object' ? (o.label != null ? o.label : o.value) : o);
          };
          return Array.isArray(v) ? v.map(libelle).join(', ') : libelle(v);
        }
        if (f.type === 'date') return C.dateFR(v);
        if (f.type === 'datetime-local') return C.dateHeure(v);
        return lisible(v);
      }
      function detailParDefaut(record) {
        var vus = {}, paires = [];
        var cols = typeof cfg.columns === 'function' ? cfg.columns() : (cfg.columns || []);
        cols.forEach(function (c) {
          if (!c || !c.label) return;
          var v;
          try { v = c.render ? c.render(record) : (c.text ? c.text(record) : record[c.key]); } catch (e) { v = record[c.key]; }
          if (c.key) vus[c.key] = true;
          paires.push([c.label, lisible(v)]);
        });
        var champs = [];
        try { champs = typeof cfg.fields === 'function' ? cfg.fields(record) : (cfg.fields || []); } catch (e) { champs = []; }
        champs.forEach(function (f) {
          if (!f || !f.name || vus[f.name] || f.type === 'section' || f.type === 'hidden' || f.type === 'file') return;
          vus[f.name] = true;
          paires.push([f.label || f.name, valeurChamp(f, record[f.name])]);
        });
        if (!paires.length) {
          paires = Object.keys(record).filter(function (k) { return k[0] !== '_'; })
            .map(function (k) { return [k, lisible(record[k])]; });
        }
        return U.descList(paires);
      }

      function openDetail(record) {
        var body = cfg.detail ? cfg.detail(record, { refresh: refresh, edit: function () { openForm(record); } })
          : detailParDefaut(record);
        var footer = [];
        if (cfg.etat) footer.push(btn('Imprimer', { icon: 'printer', onclick: function () { cfg.etat(record); } }));
        if (peutEditer) footer.push(btn('Modifier', { variant: 'primary', icon: 'pencil', onclick: function () { d.close(); openForm(record); } }));
        /* Le pied de la fiche porte AUSSI l'archivage (Bug 10 des Instructions) :
           consulter puis devoir refermer pour retrouver la ligne et son icône
           faisait faire le tour de l'écran pour un geste. Même garde que
           partout : la commande est ABSENTE sans le droit, jamais grisée. */
        if (peutAnnuler) footer.push(btn('Archiver', {
          variant: 'danger', icon: 'archive',
          onclick: function () { d.close(); askArchive(record); },
        }));
        var d = U.drawer({
          title: record.nomComplet || record.designation || record.libelle || record.patient || record.code || record.reference || record.numero || 'Détail',
          subtitle: cfg.detailSubtitle ? cfg.detailSubtitle(record) : (record.code || record.reference || record.numero || ''),
          body: body, footer: footer.length ? footer : null,
          width: cfg.drawerWidth || 'max-w-2xl',
        });
        return d;
      }

      /* --- KPI --------------------------------------------------------------*/
      var kpiHost = cfg.kpis ? el('div') : null;
      function renderKpis() {
        C.clear(kpiHost);
        try {
          var specs = cfg.kpis(col.active(), col);
          if (specs && specs.length) kpiHost.appendChild(U.kpiGrid(specs, cfg.kpiCols));
        } catch (e) { console.error('[SIGH] KPI ' + cfg.collection + ' :', e); }
        U.icons(kpiHost);
      }
      /* Une restriction s’annonce : masquer sans le dire ferait croire à une
         panne. Le bandeau nomme le profil et renvoie à la matrice des droits. */
      if (!cfg.readonly && D_.lectureSeule) host.appendChild(bandeauLectureSeule(D_));
      if (kpiHost) { renderKpis(); host.appendChild(kpiHost); }

      if (cfg.intro) host.appendChild(cfg.intro());

      /* --- Tableau ----------------------------------------------------------*/
      function makeTable(rowsFn, archived) {
        var columns = (typeof cfg.columns === 'function' ? cfg.columns() : cfg.columns).slice();
        var t = U.dataTable({
          columns: columns,
          rows: rowsFn,
          filters: cfg.filters,
          pageSize: cfg.pageSize,
          selectable: cfg.selectable && !archived,
          exportName: cfg.collection,
          searchPlaceholder: 'Rechercher un ' + cfg.entite + '…',
          emptyMessage: archived ? 'Aucun enregistrement archivé.' : 'Aucun ' + cfg.entite + ' enregistré.',
          emptyHint: archived ? null : 'Utiliser le bouton « Nouveau » pour créer le premier enregistrement.',
          onRowClick: openDetail,
          defaultSort: cfg.defaultSort, defaultDir: cfg.defaultDir,
          /* `creerVers` : certains écrans ne peuvent pas créer avec le formulaire
             générique — une facture se compose de lignes, de remises et d'une
             répartition. Le bouton conduit alors à l'écran de saisie complet
             plutôt que d'ouvrir une modale qui perdrait l'essentiel. */
          actions: archived ? null : (!peutEditer ? null : [
            cfg.creerVers
              ? btn('Nouveau', {
                variant: 'primary', size: 'sm', icon: 'plus',
                onclick: function () { A().go(cfg.creerVers); },
              })
              : btn('Nouveau', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { openForm(null); } }),
          ]),
          bulkActions: archived ? null : function (getSelected, clear) {
            return [
              btn('Imprimer la sélection', {
                size: 'sm', icon: 'printer',
                onclick: function () {
                  var sel = getSelected();
                  P.etat({
                    titre: 'Sélection — ' + cfg.entiteP,
                    sousTitre: sel.length + ' enregistrement(s)',
                    contenu: P.tableau(
                      (typeof cfg.columns === 'function' ? cfg.columns() : cfg.columns)
                        .filter(function (c) { return c.key !== '_actions'; })
                        .map(function (c) { return { label: c.label, align: c.align, value: function (r) { return textOf(c, r); } }; }),
                      sel),
                  });
                },
              }),
              !peutAnnuler ? null : btn('Archiver', {
                size: 'sm', variant: 'danger', icon: 'archive',
                onclick: function () {
                  var sel = getSelected();
                  U.confirm({
                    title: 'Archiver ' + sel.length + ' enregistrement(s) ?',
                    message: 'Archivage logique : les données restent consultables et l’opération est annulable.',
                    confirmLabel: 'Archiver', danger: true,
                  }).then(function (ok) {
                    if (!ok) return;
                    var undos = sel.map(function (r) { return col.archive(r.id).undo; });
                    clear(); refresh();
                    U.toast(sel.length + ' enregistrement(s) archivé(s).', {
                      type: 'success',
                      undo: function () { undos.forEach(function (u) { u(); }); refresh(); },
                    });
                  });
                },
              }),
            ].filter(Boolean);
          },
          rowActions: function (r) {
            if (archived) {
              return [iconBtn('archive-restore', 'Restaurer', function () {
                col.restore(r.id); refresh();
                U.toast('Enregistrement restauré.', { type: 'success' });
              }, 'ghost')];
            }
            var acts = [];
            acts.push(iconBtn('eye', 'Consulter', function () { openDetail(r); }));
            if (cfg.etat) acts.push(iconBtn('printer', 'Imprimer l’état', function () { cfg.etat(r); }));
            /* Pas de duplication : un doublon que rien ne distingue de
               l'original est un doublon que quelqu'un modifiera par erreur.
               Retirée sur décision de la Direction. */
            if (peutEditer) {
              acts.push(iconBtn('pencil', 'Modifier', function () { openForm(r); }));
            }
            if (peutAnnuler) {
              acts.push(iconBtn('archive', 'Archiver', function () { askArchive(r); }, 'ghost'));
            }
            return acts;
          },
        });
        return t;
      }

      function textOf(c, r) {
        var v = c.text ? c.text(r) : (c.value ? c.value(r) : r[c.key]);
        if (v instanceof Node) v = v.textContent;
        return v == null ? '' : String(v);
      }

      /* --- Plage de dates (optionnelle) -------------------------------------
         `plageDates: { champ: 'date', aujourdhui?: Date }` — un FILTRE du/au
         avec raccourcis, jamais un tri (la doctrine du laboratoire, portée au
         kit) : « montrez-moi les rendez-vous du 21 août » ne se répond pas en
         triant. Vide, la plage laisse tout passer. */
      /* `filtreBase(r)` — LA LISTE PRINCIPALE EST UNE VUE, pas la collection.
         Un agenda qui empile les rendez-vous honorés cesse d’être un agenda :
         ce qu’on y cherche, c’est ce qui reste à faire. Le filtre ne porte
         QUE sur l’onglet principal — les archivés gardent leur vue entière,
         et RIEN N’EST RETIRÉ de la collection (RG-14 : un rendez-vous honoré
         EST la consultation, l’archiver effacerait l’acte). */
      function filtreBase(r) {
        return typeof cfg.filtreBase === 'function' ? cfg.filtreBase(r) : true;
      }

      var duPlage = '', auPlage = '';
      function dansPlage(r) {
        if (!cfg.plageDates) return true;
        var v = String(r[cfg.plageDates.champ] || '').slice(0, 10);
        if (duPlage && v < duPlage) return false;
        if (auPlage && v > auPlage) return false;
        return true;
      }
      if (cfg.plageDates) {
        var AUJP = cfg.plageDates.aujourdhui || new Date();
        var duSel = el('input.input', { type: 'date' });
        var auSel = el('input.input', { type: 'date' });
        function poserPlage(du, au) {
          duSel.value = du; auSel.value = au;
          duPlage = du; auPlage = au; refresh();
        }
        [duSel, auSel].forEach(function (x) {
          x.addEventListener('change', function () { duPlage = duSel.value; auPlage = auSel.value; refresh(); });
        });
        var barrePlage = el('div.card');
        barrePlage.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
          el('div', null, [el('label.label', { text: 'Du' }), duSel]),
          el('div', null, [el('label.label', { text: 'Au' }), auSel]),
          btn('Aujourd’hui', { icon: 'calendar', onclick: function () { poserPlage(C.iso(AUJP), C.iso(AUJP)); } }),
          btn('Sept derniers jours', { icon: 'calendar-days', onclick: function () { poserPlage(C.iso(C.addDays(AUJP, -6)), C.iso(AUJP)); } }),
          btn('Toute la période', { icon: 'calendar-off', onclick: function () { poserPlage('', ''); } }),
        ]));
        host.appendChild(barrePlage);
      }

      /* --- Onglets ----------------------------------------------------------*/
      var onglets = [{
        id: 'liste', label: cfg.tabLabel || ('Tous les ' + cfg.entiteP),
        badge: col.active().filter(filtreBase).length,
        render: function () {
          var t = makeTable(function () {
            return col.active().filter(dansPlage).filter(filtreBase);
          }, false);
          tableRef.current = t;
          return t;
        },
      }];
      /* `extraTabs` accepte une FONCTION : un onglet gardé par un droit se
         décide au rendu, pas à l'enregistrement de l'écran. */
      var extras = typeof cfg.extraTabs === 'function' ? (cfg.extraTabs() || []) : (cfg.extraTabs || []);
      extras.forEach(function (t) { onglets.push(t); });
      onglets.push({
        id: 'archives', label: 'Archivés', badge: col.archived().length,
        render: function () { return makeTable(function () { return col.archived().filter(dansPlage); }, true); },
      });

      host.appendChild(U.tabs(onglets));
      /* Bloc libre sous le tableau : la lecture graphique vient APRÈS les
         données, jamais à leur place. */
      if (cfg.apresTableau) host.appendChild(cfg.apresTableau(col));
      if (cfg.source) host.appendChild(source(cfg.source));
      root.appendChild(host);

      /* Exposé pour les actions d'en-tête de page. */
      root._crud = { openForm: openForm, refresh: refresh, collection: col };
      return null;
    };
  }

  /* ==========================================================================
   * GABARIT « REGISTRE »
   * -------------------------------------------------------------------------
   * Même chose qu'un écran de gestion, pour les registres tenus au fil de l'eau
   * (soins, visites, appels, pertes, réactifs…). La seule différence : à la
   * première ouverture, la collection est amorcée par le jeu de démonstration
   * déclaré dans `seed()`. Les enregistrements deviennent alors de vraies
   * données — consultables, modifiables, archivables et journalisées — au lieu
   * d'une liste régénérée à chaque affichage, donc figée en lecture.
   * ======================================================================== */
  function amorcer(nom, seed) {
    var db = S.raw();
    /* Un magasin volontairement vidé ne se ré-amorce pas écran par écran. */
    if (seed && (!db[nom] || !db[nom].length) && S.amorcable(nom)) {
      db[nom] = seed() || [];
      S.save();
    }
  }

  function registre(config) {
    var rendu = crud(config);
    return function (root) {
      amorcer(config.collection, config.seed);
      return rendu(root);
    };
  }

  /* ==========================================================================
   * FILE D'ATTENTE INTER-MODULES
   * --------------------------------------------------------------------------
   * Ce que la prescription a adressé à ce poste de travail. Le même bloc sert
   * à la caisse, à la pharmacie, au laboratoire et à la salle de soins : chacun
   * voit ce qui l'attend, sans avoir à chercher dans le module d'origine.
   *
   * Une tâche « bloquée » est affichée mais non exécutable : elle attend
   * l'encaissement. C'est la traduction visible de la règle posée par la
   * Direction — rien n'est délivré ni prélevé avant le passage en caisse.
   * ======================================================================== */
  function fileAttente(type, cfg) {
    cfg = cfg || {};
    var PR = global.SIGH.parcours;
    var host = el('div');
    host.refresh = dessiner;
    dessiner();
    return host;

    function dessiner() {
      C.clear(host);
      var taches = PR.aFaire(null, type);
      var pretes = taches.filter(function (t) { return t.statut === 'en_attente'; });
      var bloquees = taches.filter(function (t) { return t.statut === 'bloque'; });

      if (!taches.length) {
        host.appendChild(U.card(cfg.titre || 'File d’attente',
          U.empty(cfg.vide || 'Rien en attente — la file est vide.', { icon: 'check-circle-2' })));
        U.icons(host);
        return;
      }

      /* L'ORDRE DE LA FILE : CE QUI EST PAYÉ D'ABORD.
         Une tâche bloquée par la caisse ne peut PAS être traitée : la laisser
         remonter par sa date fait perdre du temps à chaque coup d'œil, et fait
         appeler un patient qu'on devra renvoyer au guichet. Les tâches prêtes
         passent donc devant, les plus anciennes en tête ; les bloquées suivent,
         visibles — le laboratoire doit savoir ce qui arrive — mais après. */
      var ordonnees = pretes.slice().sort(function (a, b) {
        return String(a.date || '').localeCompare(String(b.date || ''));
      }).concat(bloquees.slice().sort(function (a, b) {
        return String(a.date || '').localeCompare(String(b.date || ''));
      }));

      var t = U.dataTable({
        /* Vague 53 : la recherche est TOUJOURS offerte sur une file — même
           courte, on y cherche un nom au guichet. */
        rows: ordonnees, pageSize: 8, searchable: true,
        exportName: 'file-' + type,
        columns: [
          {
            key: 'reference', label: 'Origine', nowrap: true,
            render: function (r) {
              return el('div', null, [
                el('span.font-mono.text-xs', { text: r.reference }),
                r.urgent ? el('span.ml-1', null, U.badge('Urgent', 'danger')) : null,
              ]);
            },
          },
          {
            key: 'patient', label: 'Patient',
            render: function (r) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
                el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
              ]);
            },
          },
          { key: 'detail', label: 'À faire' },
          {
            key: 'montant', label: 'Montant', align: 'right',
            text: function (r) { return C.money(r.montant || 0, false); },
            render: function (r) { return C.money(r.montant || 0, false); },
          },
          {
            key: 'statut', label: 'État', nowrap: true,
            render: function (r) {
              return r.statut === 'bloque'
                ? U.badge('Attente encaissement', 'warning')
                : U.badge('À traiter', 'info');
            },
          },
        ],
        rowActions: function (r) {
          if (r.statut === 'bloque') {
            return [iconBtn('lock', 'Bloquée jusqu’à l’encaissement', function () {
              U.toast('Cette opération attend le passage en caisse.', { type: 'warning' });
            })];
          }
          /* LA FILE OBÉIT AUX DROITS, ET DEPUIS LE KIT. Cinq écrans affichent
             cette même file — caisse, pharmacie, laboratoire, salle de soins,
             tableaux de bord ; écrire la protection cinq fois aurait garanti
             autant d'oublis. Un profil qui LIT l'écran voit la file, ce qui
             est utile (le magasinier a besoin de savoir ce qui attend en
             caisse), mais ne l'exécute pas.
             Le bouton est VERROUILLÉ, pas retiré : le retirer ferait croire
             que la tâche n'existe pas, et il faut au contraire qu'on voie ce
             qui attend. Il dit pourquoi. */
          if (!droits().editer) {
            return [iconBtn('lock', 'Votre profil consulte cette file sans l’exécuter', function () {
              U.toast('Votre profil consulte cette file sans pouvoir la traiter.', { type: 'warning' });
            })];
          }
          return [iconBtn(cfg.icon || 'check', cfg.action || 'Traiter', function () {
            if (cfg.onAction) cfg.onAction(r, dessiner);
          })];
        },
      });

      host.appendChild(U.card(
        (cfg.titre || 'File d’attente') + ' — ' + pretes.length + ' à traiter'
          + (bloquees.length ? ', ' + bloquees.length + ' en attente de caisse' : ''),
        t));
      U.icons(host);
    }
  }

  /** Mention expliquant qu'un écran est, à dessein, non modifiable. */
  function lectureSeule(raison) {
    return note('<strong>État calculé — lecture seule.</strong> ' + raison, { tone: 'neutral', icon: 'lock' });
  }

  /**
   * modifier(col, champs, record, apres) — modale d'édition standard sur un
   * enregistrement d'une collection existante. Sert aux écrans qui présentent
   * une vue d'une collection tenue ailleurs (pertes issues des mouvements,
   * prises en charge issues des factures…) : la donnée y reste corrigible,
   * l'opération est journalisée et annulable.
   */
  function modifier(col, champs, record, apres, avant, transform) {
    var f = U.form(typeof champs === 'function' ? champs(record) : champs, record);
    var m = U.modal({
      title: 'Modifier l’enregistrement',
      subtitle: record.reference || record.numero || record.code || record.id,
      size: 'lg', body: f,
      footer: [
        btn('Annuler', { onclick: function () { m.close(); } }),
        btn('Enregistrer', {
          variant: 'primary', icon: 'save',
          onclick: function () {
            var v = f.collect();
            if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
            /* Le contrôle métier de l'appelant : il refuse EN LE DISANT
               (son propre toast) et retourne false — rien n'est écrit. */
            if (typeof avant === 'function' && avant(v, record) === false) return;
            if (typeof transform === 'function') v = transform(v, record);   /* E364 : la fiche corrigée est transmise */
            var res = col.update(record.id, v);
            m.close();
            if (apres) apres();
            U.toast('Modifications enregistrées.', {
              type: 'success',
              undo: function () { res.undo(); if (apres) apres(); },
            });
          },
        }),
      ],
    });
    return m;
  }

  /**
   * creer(col, champs, opts) — bouton « Nouveau » pour un tableau adossé à une
   * collection mais construit à la main (onglets d'un référentiel, par exemple),
   * là où `kit.crud()` ne s'applique pas. Complète `actionsLigne` : ensemble,
   * les deux donnent un CRUD entier à un tableau existant.
   */
  function creer(col, champs, opts) {
    opts = opts || {};
    if (!droits(opts.module).editer) return null;
    return btn(opts.label || 'Nouveau', {
      variant: 'primary', size: 'sm', icon: 'plus',
      onclick: function () {
        var f = U.form(typeof champs === 'function' ? champs(null) : champs, opts.defauts ? opts.defauts() : {});
        var m = U.modal({
          title: opts.titre || 'Nouvel enregistrement',
          subtitle: 'Les champs marqués d’un astérisque sont obligatoires.',
          size: opts.size || 'lg', body: f,
          footer: [
            btn('Annuler', { onclick: function () { m.close(); } }),
            btn('Créer', {
              variant: 'primary', icon: 'plus',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                /* `avant` : contrôle métier de l'appelant — refus dit par lui,
                   retour false, rien n'est écrit. */
                if (typeof opts.avant === 'function' && opts.avant(v, null) === false) return;
                if (opts.transform) v = opts.transform(v);
                var res = col.insert(v);
                m.close();
                if (opts.apres) opts.apres();
                U.toast((opts.entite || 'Enregistrement') + ' créé.', {
                  type: 'success',
                  detail: res.record.libelle || res.record.designation || res.record.code || null,
                  undo: function () { col.archive(res.record.id); if (opts.apres) opts.apres(); },
                  undoMessage: 'Création annulée — la fiche est archivée.',
                });
              },
            }),
          ],
        });
      },
    });
  }

  /**
   * actionsLigne(col, champs, opts) — jeu d'actions « consulter / modifier /
   * archiver » à brancher sur le `rowActions` d'un tableau adossé à une
   * collection. Le rafraîchissement se débrouille seul : il remonte du bouton
   * jusqu'au tableau qui le contient, de sorte qu'un écran existant devient
   * modifiable en une seule ligne.
   */
  function actionsLigne(col, champs, opts) {
    opts = opts || {};

    function rafraichirDepuis(noeud) {
      if (opts.refresh) { opts.refresh(); return; }
      var t = noeud && noeud.closest ? noeud.closest('.card') : null;
      while (t && typeof t.refresh !== 'function') t = t.parentElement && t.parentElement.closest ? t.parentElement.closest('.card') : null;
      if (t && typeof t.refresh === 'function') t.refresh();
    }

    return function (r) {
      var actes = [];
      var rafraichir = function () { rafraichirDepuis(actes[actes.length - 1]); };
      if (opts.detail) {
        actes.push(iconBtn('eye', 'Consulter', function () {
          U.drawer({
            title: opts.titre ? opts.titre(r) : (r.reference || r.numero || r.code || 'Détail'),
            subtitle: opts.sousTitre ? opts.sousTitre(r) : '',
            body: opts.detail(r), width: opts.width || 'max-w-2xl',
          });
        }));
      }
      if (opts.etat) actes.push(iconBtn('printer', 'Imprimer l’état', function () { opts.etat(r); }));
      var dr = droits(opts.module);
      if (dr.editer) actes.push(iconBtn('pencil', 'Modifier', function () { modifier(col, champs, r, rafraichir, opts.avant, opts.transform); }));
      if (opts.archivable !== false && dr.annuler) {
        actes.push(iconBtn('archive', 'Archiver', function () {
          U.confirm({
            title: 'Archiver cet enregistrement ?',
            message: 'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
            confirmLabel: 'Archiver', danger: true, requireMotif: true,
          }).then(function (rep) {
            if (!rep) return;
            var res = col.archive(r.id, rep.motif);
            if (rafraichir) rafraichir();
            U.toast('Enregistrement archivé.', {
              type: 'success',
              undo: function () { res.undo(); if (rafraichir) rafraichir(); },
              undoMessage: 'Archivage annulé.',
            });
          });
        }, 'ghost'));
      }
      return actes;
    };
  }

  /* ==========================================================================
   * GABARIT « TABLEAU DE BORD »
   * ======================================================================== */
  /** Une section est-elle un bloc d'accès rapides ? */
  function estAccesRapide(s) { return s && (s.rapide === true || s.title === 'Accès rapides'); }

  /**
   * Le bandeau du premier regard.
   *
   * { question, valeur, unite, ton, icone, ecran, lienLabel, vide, note }
   *
   * `vide` est le texte affiché quand le compte est nul. Il est OBLIGATOIRE et
   * doit être positif : « rien ne vous attend » est une information, pas un
   * vide — laisser un bandeau gris sans phrase ferait douter de l'écran.
   */
  /**
   * Annonce sonore d'un premier regard grave.
   *
   * Le drapeau vit dans la SESSION du navigateur, non dans le magasin : il doit
   * se remettre à zéro quand l'agent revient le lendemain, mais pas d'un écran
   * à l'autre dans la même journée.
   */
  function annoncer(o) {
    try {
      var cle = 'sigh-cnt:annonce:' + (o.ecran || 'general') + ':' + C.iso(new Date());
      if (global.sessionStorage && global.sessionStorage.getItem(cle)) return;
      if (global.sessionStorage) global.sessionStorage.setItem(cle, '1');
      /* Un navigateur qui refuse l'audio retombe sur le bandeau, qui reste
         lisible : le son ajoute, il ne remplace pas. */
      U.alerter(C.num(o.valeur) + ' ' + (o.unite || '') + ' — ' + (o.question || ''),
        { type: 'error', son: 'alerte', duration: 9000 });
    } catch (e) { /* l'audio ou le stockage de session est indisponible */ }
  }

  function bandeauPremierRegard(o) {
    var rien = !o.valeur;
    var ton = rien ? 'success' : (o.ton || 'navy');
    var TONS = {
      navy: ['border-navy-200', 'bg-navy-50', 'text-navy-900', 'text-navy-700'],
      danger: ['border-rose-200', 'bg-rose-50', 'text-rose-900', 'text-rose-700'],
      warning: ['border-amber-200', 'bg-amber-50', 'text-amber-900', 'text-amber-700'],
      info: ['border-sky-200', 'bg-sky-50', 'text-sky-900', 'text-sky-700'],
      success: ['border-emerald-200', 'bg-emerald-50', 'text-emerald-900', 'text-emerald-700'],
    };
    var t = TONS[ton] || TONS.navy;

    var bloc = el('div.flex.flex-wrap.items-center.gap-4.rounded-xl.border.px-5.py-4', {
      class: t[0] + ' ' + t[1],
    });
    bloc.appendChild(el('span.shrink-0', { class: t[3] },
      C.icon(rien ? 'check-check' : (o.icone || 'eye'), 'h-7 w-7')));

    var texte = el('div.min-w-0.flex-1');
    texte.appendChild(el('p.text-xs.font-semibold.uppercase.tracking-wide', {
      class: t[3], text: 'À regarder en premier',
    }));
    if (rien) {
      texte.appendChild(el('p.mt-0\\.5.text-lg.font-semibold', { class: t[2], text: o.vide }));
    } else {
      texte.appendChild(el('p.mt-0\\.5.text-lg.font-semibold', { class: t[2] }, [
        el('span.text-2xl.font-bold', { text: C.num(o.valeur) }),
        el('span', { text: ' ' + (o.unite || '') + ' — ' + o.question }),
      ]));
    }
    if (o.note) {
      texte.appendChild(el('p.mt-1.text-xs', { class: t[3], text: o.note }));
    }
    bloc.appendChild(texte);

    if (o.ecran && !rien) {
      bloc.appendChild(lien(o.ecran, o.lienLabel || 'Y aller', {
        variant: 'primary', icon: 'arrow-right', size: 'sm',
      }));
    }
    return bloc;
  }

  function dash(config) {
    return function (root) {
      var host = el('div.space-y-5');

      function poser(s) {
        try {
          var content = s.render();
          if (!content) return;
          if (s.title) {
            host.appendChild(U.card(s.title, content, s.actions ? s.actions() : null));
          } else {
            host.appendChild(content);
          }
        } catch (e) {
          console.error('[SIGH] Section « ' + (s.title || '?') + ' » :', e);
          host.appendChild(U.card(s.title || 'Section', U.errorState('Cette section n’a pas pu être affichée.')));
        }
      }

      /* Un crochet AVANT le rendu : un poste peut vouloir dire quelque chose
         à l'ouverture — un rappel du matin, par exemple — que le bandeau du
         premier regard ne saurait pas porter, parce qu'il ne porte qu'UNE
         question. Un crochet qui échoue ne doit pas empêcher le tableau de
         s'afficher. */
      if (typeof config.avant === 'function') {
        try { config.avant(); } catch (e) { console.error('[SIGH] Rappel d ouverture :', e); }
      }

      if (config.alerte) {
        var a = config.alerte();
        if (a) host.appendChild(a);
      }

      /* LE PREMIER REGARD — la chose que ce profil vérifie en arrivant.
         Posé AVANT tout le reste : l'ordre de lecture est la seule chose qu'un
         tableau de bord contrôle vraiment. Il porte UNE question, son compte et
         le lien qui y mène — un bandeau de quatre indicateurs demande à être lu
         et comparé, celui-ci demande à être vu. */
      if (config.premierRegard) {
        try {
          var pr = config.premierRegard();
          if (pr) {
            host.appendChild(bandeauPremierRegard(pr));
            /* Le son porte l'attention sur ce qui est GRAVE, et seulement là.
               Une fois par session et par écran : rouvrir la même page dix
               fois dans la journée ne doit pas sonner dix fois, sinon on coupe
               le son et l'alerte suivante passe inaperçue. */
            if (pr.valeur && pr.ton === 'danger') annoncer(pr);
          }
        } catch (e) { console.error('[SIGH] Premier regard :', e); }
      }

      /* Les accès rapides ouvrent le tableau de bord : sur ces postes, l'écran
         d'accueil sert d'abord de rampe de lancement vers les écrans de travail
         du profil ; les indicateurs viennent ensuite. */
      var sections = config.sections || [];
      /* DANS LE GROUPE RAPIDE, LES RACCOURCIS PASSENT DEVANT. Les accès
         rapides et les parcours portent tous deux `rapide`, et l'ordre de
         déclaration mettait les parcours en tête. Ce qu'on cherche en
         arrivant, ce sont les raccourcis ; le mode d'emploi se lit ensuite. */
      var rapides = sections.filter(estAccesRapide);
      rapides.filter(function (s) { return s.title === 'Accès rapides'; }).forEach(poser);
      rapides.filter(function (s) { return s.title !== 'Accès rapides'; }).forEach(poser);

      if (config.kpis) {
        try {
          host.appendChild(U.kpiGrid(config.kpis(), config.kpiCols || 'grid-cols-2 lg:grid-cols-4'));
        } catch (e) { console.error('[SIGH] KPI tableau de bord :', e); }
      }

      sections.filter(function (s) { return !estAccesRapide(s); }).forEach(poser);

      root.appendChild(host);
      return null;
    };
  }

  /** Grille de graphiques à deux colonnes. */
  function charts(items) {
    var g = el('div.grid.gap-4.lg\\:grid-cols-2');
    items.forEach(function (it) {
      if (!it) return;
      g.appendChild(U.card(it.title, it.render(), it.actions || null));
    });
    return g;
  }

  /** Liste compacte « libellé → valeur » avec barre de proportion. */
  function ranking(items, opts) {
    opts = opts || {};
    var max = Math.max.apply(null, items.map(function (i) { return i.value; }).concat([1]));
    var list = el('div.space-y-2\\.5');
    if (!items.length) return U.empty('Aucune donnée.', { icon: 'bar-chart-3' });
    items.forEach(function (i) {
      var r = el('div');
      var top = el('div.mb-1.flex.items-baseline.justify-between.gap-3');
      top.appendChild(el('span.truncate.text-sm.text-slate-700', { text: i.label }));
      top.appendChild(el('span.shrink-0.text-sm.font-semibold.num.text-slate-900', { text: opts.format ? opts.format(i.value) : C.num(i.value) }));
      r.appendChild(top);
      var bar = el('div.h-1\\.5.w-full.overflow-hidden.rounded-full.bg-slate-100');
      bar.appendChild(el('div.h-full.rounded-full', {
        class: 'bg-' + (i.tone || opts.tone || 'navy') + '-500',
        style: 'width:' + Math.max(2, Math.round(i.value / max * 100)) + '%;',
      }));
      r.appendChild(bar);
      list.appendChild(r);
    });
    return list;
  }

  /** Tableau simple, sans interaction — pour les encarts de tableau de bord.
      Deux formes de colonnes : objets {key,label,align,render,value}, ou simples
      chaînes — une chaîne devient {label, key: rang} et les lignes sont alors des
      tableaux de valeurs. Sans cette normalisation, un appel en colonnes-chaînes
      rendait un tableau aux en-têtes vides et aux cellules « — », sans un mot. */
  function miniTable(columns, rows, opts) {
    opts = opts || {};
    if (!rows.length) return U.empty(opts.empty || 'Aucune donnée.', { icon: 'inbox' });
    columns = columns.map(function (c, i) {
      return typeof c === 'string' ? { label: c, key: i } : c;
    });
    var t = el('table.tbl');
    var thead = el('thead'), htr = el('tr');
    columns.forEach(function (c) { htr.appendChild(el('th', { class: c.align === 'right' ? 'text-right' : '', text: c.label })); });
    thead.appendChild(htr); t.appendChild(thead);
    var tb = el('tbody');
    rows.forEach(function (r) {
      var tr = el('tr');
      columns.forEach(function (c) {
        var td = el('td', { class: c.align === 'right' ? 'text-right num' : '' });
        var v = c.render ? c.render(r) : (c.value ? c.value(r) : r[c.key]);
        /* Une cellule peut recevoir une LISTE de nœuds (badge + texte) :
           String() l'aurait rendue « [object HTMLElement],… ». */
        if (v instanceof Node || Array.isArray(v)) C.append(td, v); else td.textContent = v == null ? '—' : String(v);
        tr.appendChild(td);
      });
      tb.appendChild(tr);
    });
    t.appendChild(tb);
    return el('div.-mx-5.-mb-5.overflow-x-auto', null, t);
  }

  /* --- Raccourcis d'accès à d'autres écrans -------------------------------- */
  function shortcuts(items) {
    var g = el('div.grid.gap-3.sm\\:grid-cols-2.lg\\:grid-cols-4');
    items.forEach(function (i) {
      var a = el('a.group.flex.items-start.gap-3.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card.transition-colors.hover\\:border-navy-300.hover\\:bg-navy-50',
        { href: A().href(i.id) });
      a.appendChild(el('span.grid.h-9.w-9.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700', null, C.icon(i.icon, 'h-4 w-4')));
      a.appendChild(el('span.min-w-0', null, [
        el('span.block.text-sm.font-medium.text-slate-800', { text: i.label }),
        i.detail ? el('span.mt-0\\.5.block.text-xs.text-slate-500', { text: i.detail }) : null,
      ]));
      g.appendChild(a);
    });
    return g;
  }

  /* ==========================================================================
   * PARCOURS MÉTIER
   * --------------------------------------------------------------------------
   * parcours([{ titre, icone, ton, etapes: [{ label, ecran, poste, detail }] }])
   *
   * Une grille de liens dit OÙ aller ; elle ne dit pas CE QU'IL FAUT FAIRE ni
   * DANS QUEL ORDRE. Un parcours affiche la chaîne complète : première action
   * en bouton, étapes suivantes visibles.
   *
   * Une étape dont l'écran est fermé au profil reste VISIBLE mais non
   * cliquable : promettre une porte fermée est pire que ne rien promettre, et
   * masquer l'étape ferait croire qu'elle n'existe pas.
   * ======================================================================== */
  function parcours(groupes) {
    var g = el('div.grid.gap-4.lg\\:grid-cols-2');
    (groupes || []).forEach(function (p2) {
      var carte = el('div.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card');

      var tete = el('div.mb-3.flex.items-center.gap-2.5');
      tete.appendChild(el('span.grid.h-9.w-9.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700',
        null, C.icon(p2.icone || 'route', 'h-4 w-4')));
      tete.appendChild(el('div.min-w-0', null, [
        el('p.text-sm.font-semibold.text-slate-800', { text: p2.titre }),
        p2.detail ? el('p.text-xs.text-slate-500', { text: p2.detail }) : null,
      ]));
      carte.appendChild(tete);

      var chaine = el('ol.space-y-1\.5');
      (p2.etapes || []).forEach(function (e, i) {
        var ouvert = !e.ecran || ecranOuvert(e.ecran);
        var li = el('li.flex.items-start.gap-2');

        li.appendChild(el('span.mt-0\.5.grid.h-5.w-5.shrink-0.place-items-center.rounded-full.text-\\[10px\\].font-bold', {
          class: i === 0 ? 'bg-navy-700 text-white' : 'bg-slate-100 text-slate-500',
          text: String(i + 1),
        }));

        var corps = el('span.min-w-0.flex-1');
        if (e.ecran && ouvert) {
          corps.appendChild(el('a.text-sm.font-medium.text-navy-800.hover\\:underline', {
            href: A().href(e.ecran), text: e.label,
          }));
        } else {
          corps.appendChild(el('span.text-sm', {
            class: ouvert ? 'text-slate-700' : 'text-slate-400',
            text: e.label,
          }));
        }
        /* Le poste qui prend la suite est nommé : l'accueil doit savoir que la
           caisse enchaîne, sans croire que c'est à lui de le faire. */
        if (e.poste) {
          corps.appendChild(el('span.ml-1\.5.rounded.bg-slate-100.px-1\.5.py-0\.5.text-\\[10px\\].font-medium.text-slate-500',
            { text: e.poste }));
        }
        if (!ouvert) {
          corps.appendChild(el('span.ml-1\.5.text-\\[10px\\].italic.text-slate-400',
            { text: '— fermé à votre profil' }));
        }
        if (e.detail) {
          corps.appendChild(el('span.mt-0\.5.block.text-xs.text-slate-500', { text: e.detail }));
        }
        li.appendChild(corps);
        chaine.appendChild(li);
      });
      carte.appendChild(chaine);

      /* Le bouton porte la PREMIÈRE action : c'est par là qu'on commence. */
      var premiere = (p2.etapes || [])[0];
      if (premiere && premiere.ecran && ecranOuvert(premiere.ecran)) {
        carte.appendChild(el('div.mt-3', null,
          lien(premiere.ecran, p2.action || 'Commencer', {
            variant: 'primary', size: 'sm', icon: 'arrow-right',
          })));
      }
      g.appendChild(carte);
    });
    return g;
  }

  /* L écran est-il ouvert au profil courant ? N.can attend une ENTRÉE du
     manifeste, non un identifiant : on la résout d abord. Un identifiant
     inconnu est traité comme fermé — mieux vaut ne rien promettre. */
  function ecranOuvert(id) {
    if (!id) return true;
    var e = N.get(id);
    if (!e) return false;
    return N.can(sessionRole(), e);
  }

  function sessionRole() {
    var s2 = S.session();
    return (s2 && s2.role) || 'admin';
  }

  /* --- Agrégations fréquentes ---------------------------------------------- */
  function parMois(rows, dateKey, valueKey, nbMois) {
    var n = nbMois || 12, labels = G.moisGlissants(n), buckets = new Array(n).fill(0);
    var ref = new Date(2026, 7, 1);
    rows.forEach(function (r) {
      var d = C.toDate(r[dateKey]);
      if (isNaN(d)) return;
      var diff = (ref.getFullYear() - d.getFullYear()) * 12 + (ref.getMonth() - d.getMonth());
      var idx = n - 1 - diff;
      if (idx >= 0 && idx < n) buckets[idx] += valueKey ? (Number(r[valueKey]) || 0) : 1;
    });
    return { labels: labels, data: buckets };
  }

  function repartition(rows, key, labelFn) {
    var g = C.groupBy(rows, key);
    var keys = Object.keys(g);
    return {
      labels: keys.map(function (k) { return labelFn ? labelFn(k) : k; }),
      data: keys.map(function (k) { return g[k].length; }),
      keys: keys,
    };
  }

  /* ==========================================================================
   * PAGES D'ACCUEIL DE MODULE (hubs)
   * -------------------------------------------------------------------------
   * Une page par module, engendrée depuis le manifeste : chaque écran y est
   * présenté par une carte — icône, titre, description reprise de sa propre
   * déclaration. C'est le point d'entrée du module, atteint depuis le fil
   * d'Ariane, l'intitulé du module dans le ruban et les raccourcis permanents.
   * ======================================================================== */
  function hubCartes(mod, role) {
    var grille = el('div.grid.gap-3.sm\\:grid-cols-2.xl\\:grid-cols-3');
    /* L'IDENTIFIANT DE L'ÉCRAN DOIT ÊTRE PASSÉ. `N.can` interroge
       `ecranActif(entry.id, code)` pour savoir si l'activité est fermée ; une
       entrée synthétique sans `id` faisait manquer ce contrôle, et un écran
       fermé partout ailleurs restait offert sur le hub. Un écran fermé qu'on
       peut encore atteindre n'est pas fermé. */
    var visibles = mod.items.filter(function (it) {
      return N.can(role, {
        id: it.id,
        roles: it.roles || mod.roles || N.ALL,
        module: mod.code,
      });
    });
    visibles.forEach(function (it) {
      var def = global.SIGH.screens[it.id] || {};
      var carte = el('a.hub-card.group.flex.gap-3.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card.transition-all.hover\\:-translate-y-0\\.5.hover\\:border-navy-300.hover\\:shadow-raise',
        { href: A().href(it.id) });
      carte.appendChild(el('span.grid.h-10.w-10.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700.transition-colors.group-hover\\:bg-navy-900.group-hover\\:text-white',
        null, C.icon(it.icon || mod.icon, 'h-5 w-5')));
      var corps = el('span.min-w-0.flex-1');
      corps.appendChild(el('span.block.text-sm.font-semibold.text-slate-900', { text: def.title || it.label }));
      corps.appendChild(el('span.mt-1.block.text-xs.leading-relaxed.text-slate-500', {
        text: def.description || 'Écran du module ' + mod.label + '.',
      }));
      carte.appendChild(corps);
      carte.appendChild(C.icon('arrow-right', 'h-4 w-4 shrink-0 text-slate-300 transition-colors group-hover:text-navy-700'));
      grille.appendChild(carte);
    });
    if (!visibles.length) return U.empty('Aucun écran de ce module n’est accessible à votre profil.', { icon: 'lock' });
    return grille;
  }

  function hub(mod) {
    return function (root) {
      var role = S.session() ? S.session().role : 'admin';
      var host = el('div.space-y-4');
      host.appendChild(hubCartes(mod, role));

      /* Passage direct vers les autres modules du même domaine. */
      var voisins = (N.tree(role).filter(function (d) { return d.domain === mod.domain; })[0] || { modules: [] })
        .modules.filter(function (m) { return m.code !== mod.code; });
      if (voisins.length) {
        var l = el('div.flex.flex-wrap.items-center.gap-2');
        l.appendChild(el('span.text-xs.text-slate-500', { text: 'Autres modules du domaine ' + mod.domain + ' :' }));
        voisins.forEach(function (m) {
          l.appendChild(el('a.inline-flex.items-center.gap-1\\.5.rounded-lg.border.border-slate-200.bg-white.px-2\\.5.py-1\\.5.text-xs.font-medium.text-slate-600.hover\\:border-navy-300.hover\\:text-navy-800',
            { href: A().href(m.hub) }, [C.icon(m.icon, 'h-3.5 w-3.5'), m.label]));
        });
        host.appendChild(l);
      }
      root.appendChild(host);
      return null;
    };
  }

  /* Enregistrement des hubs — le manifeste en est la seule source. */
  N.NAV.forEach(function (domaine) {
    domaine.modules.forEach(function (m) {
      var mod = N.module(m.code);
      global.SIGH.screen(N.hubId(m.code), {
        title: mod.label,
        description: 'Tous les écrans du module ' + mod.code + ' — ' + mod.label + '.',
        render: hub(mod),
      });
    });
  });

  /* ==========================================================================
   * LE PRESCRIPTEUR EXTÉRIEUR À LA CLINIQUE (21/09/2026)
   * --------------------------------------------------------------------------
   * Un patient arrive avec une demande d'imagerie ou d'analyse signée
   * ailleurs — un cabinet, un centre de santé périphérique, un autre
   * hôpital. Le champ « Prescripteur » n'offrait que la liste des soignants
   * DE LA MAISON : il fallait donc désigner un médecin de la clinique qui
   * n'avait rien prescrit. Le compte rendu partait alors sous une signature
   * d'emprunt, et la pièce devenait fausse — c'est la seule chose qu'un
   * compte rendu ne doit jamais être.
   *
   * TROIS DÉCISIONS, et la troisième commande les deux autres :
   *
   *   - LA LISTE INTERNE RESTE PREMIÈRE. Le cas courant est un prescripteur
   *     de la clinique ; le rendre libre pour tout le monde ferait ressaisir
   *     à la main un nom que le logiciel connaît, avec ses fautes de frappe,
   *     et aucune statistique par praticien ne tiendrait plus.
   *   - L'EXTÉRIEUR EST UNE ENTRÉE DE LA LISTE, pas une case à cocher. Elle
   *     se lit dans le même geste que les autres et ouvre son champ texte.
   *   - ON DEMANDE LE NOM, LA QUALIFICATION ET LA STRUCTURE, car c'est ce
   *     qui permet de RENVOYER le compte rendu à son auteur. Un nom seul
   *     dans une ville qu'on ne connaît pas ne sert à rien.
   *
   * L'identifiant `EXTERNE` n'est le matricule de personne : `nomPrescripteur`
   * le résout, et `prescripteurId` reste nul au dossier — rattacher la pièce
   * à un soignant de la maison serait précisément l'erreur qu'on corrige.
   * ======================================================================== */
  var PRESCRIPTEUR_EXTERNE = 'EXTERNE';

  /**
   * Les DEUX champs du prescripteur : la liste interne augmentée de
   * l'entrée « extérieur », et le champ libre qui ne paraît que pour elle.
   * @param {Array} internes options {value,label} des soignants de la maison
   * @param {Object} [opts] {name, label, required, col}
   */
  function champsPrescripteur(internes, opts) {
    var o = opts || {};
    var nom = o.name || 'prescripteurId';
    var nomLibre = nom + 'Externe';
    return [
      { name: nom, label: o.label || 'Prescripteur', type: 'select',
        required: o.required !== false, col: o.col,
        options: (internes || []).concat([
          { value: PRESCRIPTEUR_EXTERNE, label: '— Prescripteur extérieur à la clinique —' },
        ]) },
      { name: nomLibre, label: 'Prescripteur extérieur — nom, qualification et structure',
        type: 'text', col: o.colExterne || 'full',
        condition: { controle: nom, quand: [PRESCRIPTEUR_EXTERNE] },
        help: 'Ex. : Dr SALIFOU Aminou, médecin généraliste, Centre de santé de Perma. '
          + 'C’est ce qui permet de lui renvoyer le compte rendu.' },
    ];
  }

  /** Vrai si la saisie désigne un prescripteur du dehors. */
  function prescripteurEstExterne(v, nom) {
    return String((v || {})[nom || 'prescripteurId'] || '') === PRESCRIPTEUR_EXTERNE;
  }

  /**
   * Le nom à porter sur la pièce. `interne` est la fonction qui sait nommer
   * un soignant de la maison : on ne la duplique pas ici, chaque module a la
   * sienne et elles ne lisent pas toutes la même collection.
   */
  function nomPrescripteur(v, interne, nom) {
    var cle = nom || 'prescripteurId';
    if (prescripteurEstExterne(v, cle)) {
      var libre = String((v || {})[cle + 'Externe'] || '').trim();
      return libre ? libre + ' (extérieur)' : 'Prescripteur extérieur';
    }
    return interne ? interne((v || {})[cle]) : (v || {})[cle];
  }

  /** L'identifiant à ENREGISTRER : nul pour un prescripteur du dehors. */
  function idPrescripteur(v, nom) {
    var cle = nom || 'prescripteurId';
    return prescripteurEstExterne(v, cle) ? null : (v || {})[cle];
  }

  /* ==========================================================================
   * « JE NE CONNAIS PAS MA DATE DE NAISSANCE » (21/09/2026)
   * --------------------------------------------------------------------------
   * C'est la réponse ordinaire au guichet, pas l'exception. Le dossier exigeait
   * pourtant une date : l'accueil inscrivait donc un 1er janvier de fantaisie,
   * qui ressortait ensuite sur chaque pièce imprimée comme un fait établi.
   * Inventer une date pour satisfaire un champ obligatoire, c'est écrire au
   * dossier quelque chose que personne n'a dit.
   *
   * LE CHOIX EST EXPLICITE, ET C'EST VOLONTAIRE. Un simple champ « âge » posé
   * à côté de la date aurait laissé remplir les deux, ou aucun des deux, sans
   * que rien ne tranche lequel fait foi. La liste pose la question une fois —
   * la date est-elle connue ? — et n'ouvre que le champ qui correspond.
   * `U.form` masque l'autre ET cesse d'en exiger la saisie : un `required` sur
   * un champ invisible bloquerait le formulaire sans dire pourquoi.
   *
   * `ageReferenceLe` EST LA PIÈCE MAÎTRESSE : sans lui, « 45 ans » saisi
   * aujourd'hui se lirait encore « 45 ans » dans cinq ans. Il est posé à
   * l'enregistrement par `valeursAge()`, jamais demandé à l'agent — on ne fait
   * pas saisir la date du jour à quelqu'un qui est devant son clavier.
   * ======================================================================== */
  function champsAge(opts) {
    var o = opts || {};
    var r = o.record || {};
    /* La branche par défaut se LIT SUR LA FICHE : rouvrir un dossier sans
       date de naissance doit proposer « Inconnue », sans quoi l'agent
       verrait un champ date vide et croirait la donnée perdue. */
    var branche = (!r.dateNaissance && r.age != null && r.age !== '') ? 'age' : 'date';
    return [
      { name: 'naissanceConnue', label: 'Date de naissance', type: 'select', required: true,
        search: false, value: branche,
        options: [
          { value: 'date', label: 'Connue — la saisir' },
          { value: 'age', label: 'Inconnue — indiquer l’âge déclaré' },
        ] },
      { name: 'dateNaissance', label: 'Date de naissance', type: 'date',
        required: o.required !== false,
        condition: { controle: 'naissanceConnue', quand: ['date'] },
        validate: function (v) { return C.toDate(v) > new Date() ? 'La date ne peut pas être dans le futur.' : null; } },
      { name: 'age', label: 'Âge déclaré (ans)', type: 'number', min: 0, max: 120,
        required: o.required !== false, value: r.age != null ? r.age : '',
        condition: { controle: 'naissanceConnue', quand: ['age'] } },
    ];
  }

  /**
   * Les valeurs à ENREGISTRER. Elle date l'âge déclaré et efface l'autre
   * branche : garder les deux laisserait une date de naissance périmée sous
   * un âge qu'on vient de déclarer, et `C.ageDe` donnerait la priorité à la
   * date — c'est-à-dire à celle qu'on voulait abandonner.
   */
  function valeursAge(v, ancien) {
    var out = {};
    if (String((v || {}).naissanceConnue || 'date') === 'age') {
      out.dateNaissance = '';
      out.age = v.age;
      /* L'âge déjà déclaré ne se re-date pas : le re-dater le rajeunirait
         d'autant à chaque ouverture de la fiche. */
      var inchange = ancien && ancien.ageReferenceLe && String(ancien.age) === String(v.age);
      out.ageReferenceLe = inchange ? ancien.ageReferenceLe : C.iso(new Date());
    } else {
      out.dateNaissance = (v || {}).dateNaissance;
      out.age = '';
      out.ageReferenceLe = '';
    }
    return out;
  }

  /* ==========================================================================
   * UNE PAGE DE SAISIE, UN SEUL GABARIT (22/09/2026)
   * --------------------------------------------------------------------------
   * Les grandes saisies quittent les modales une à une — dossier de
   * consultation, ordonnance, compte rendu d'imagerie, feuille d'inventaire,
   * nouveau patient, dossier obstétrical. Écrire six fois la même géométrie,
   * c'est obtenir six géométries : six gouttières, six largeurs de colonne,
   * six barres de pied. La Direction a demandé l'inverse — « cohérence de la
   * grille, des marges, des espacements et des proportions ».
   *
   * LE GABARIT EST DONC ICI, ET UNE SEULE FOIS :
   *
   *   grid gap-4 lg:grid-cols-3
   *     ├─ space-y-4 lg:col-span-2   la saisie, EN CARTES
   *     └─ space-y-4                 l'enchaînement du parcours, puis les
   *                                  rappels de règle
   *
   * IL PARTAGE LA DÉCLARATION DE CHAMPS DE « crud » : c'est la même liste qui
   * sert la modale d'édition et la page de création. Deux listes auraient
   * divergé au premier champ ajouté — on l'aurait mis à l'une, pas à l'autre,
   * et personne ne l'aurait vu avant la recette.
   *
   * L'ADRESSE porte le contexte (« #id=…&retour=… ») : une page se charge à
   * froid et ne sait rien de l'écran qui l'a appelée.
   * ======================================================================== */
  function pageFormulaire(cfg) {
    return function (root) {
      var C2 = global.SIGH.core, S2 = global.SIGH.store;
      var p = C2.params();
      var col = S2.collection(cfg.collection, { module: cfg.module, entite: cfg.entite });
      var retour = p.retour || cfg.retour;
      var record = p.id ? col.get(p.id) : null;
      var edition = !!record;

      function revenir() { global.SIGH.app.go(retour); }

      /* Une adresse qui vise une fiche disparue ne doit pas ouvrir un
         formulaire VIERGE : on créerait un second enregistrement en croyant
         corriger le premier. */
      if (p.id && !record) {
        root.appendChild(note('Cet enregistrement est introuvable — il a pu être archivé depuis que '
          + 'le lien a été ouvert. Revenez au registre pour le retrouver.',
        { tone: 'warning', icon: 'alert-triangle' }));
        root.appendChild(global.SIGH.core.el('div.mt-3', null,
          btn('Revenir au registre', { variant: 'primary', icon: 'arrow-left', onclick: revenir })));
        return null;
      }

      var dr = droits(cfg.module);
      if (!dr.editer) {
        root.appendChild(note(cfg.refus || ('Votre profil consulte ces enregistrements sans les '
          + 'modifier. La saisie appartient au poste qui en répond.'), { tone: 'warning', icon: 'lock' }));
        root.appendChild(global.SIGH.core.el('div.mt-3', null,
          btn('Revenir au registre', { icon: 'arrow-left', onclick: revenir })));
        return null;
      }

      var el2 = global.SIGH.core.el;
      var U2 = global.SIGH.ui;
      var champs = typeof cfg.fields === 'function' ? cfg.fields(record) : cfg.fields;
      var f = U2.form(champs, record || (cfg.onCreate ? cfg.onCreate() : {}));

      var host = el2('div.grid.gap-4.lg\\:grid-cols-3');
      var principal = el2('div.space-y-4.lg\\:col-span-2');
      var aside = el2('div.space-y-4');

      if (cfg.avantFormulaire) {
        var tete = cfg.avantFormulaire(record);
        if (tete) principal.appendChild(tete);
      }

      /* LA SAISIE EST DANS UNE CARTE — en-tête et corps, comme partout
         ailleurs : un formulaire nu au milieu d'une page n'a ni titre, ni
         bord, et ne se distingue pas de ce qui l'entoure. */
      principal.appendChild(U2.card(
        edition ? (cfg.titreEdition || 'Modifier la fiche') : (cfg.titreCarte || ('Nouveau ' + cfg.entite)),
        f));

      if (cfg.apresFormulaire) {
        var pied = cfg.apresFormulaire(record);
        if (pied) principal.appendChild(pied);
      }

      if (cfg.parcours && cfg.parcours.length) {
        aside.appendChild(U2.card('Enchaînement du parcours', U2.timeline(cfg.parcours)));
      }
      (cfg.rappels || []).forEach(function (r) {
        aside.appendChild(U2.card(r.titre, el2('div.space-y-3', null,
          (r.notes || []).map(function (n) { return note(n.texte, { tone: n.tone, icon: n.icon }); }))));
      });

      host.appendChild(principal);
      host.appendChild(aside);
      root.appendChild(host);

      root.appendChild(el2('div.mt-4.flex.flex-wrap.items-center.justify-end.gap-2.border-t.border-slate-200.pt-4', null, [
        btn('Annuler', { icon: 'x', onclick: revenir }),
        btn(edition ? 'Enregistrer' : (cfg.libelleValider || 'Créer'), {
          variant: 'primary', icon: edition ? 'save' : 'plus', onclick: enregistrer,
        }),
      ]));
      root.__enregistrerPage = enregistrer;
      return null;

      function enregistrer() {
        var values = f.collect();
        if (!values) { U2.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
        if (cfg.beforeSave) {
          var err = cfg.beforeSave(values, record);
          if (err) { U2.toast(err, { type: 'error' }); return; }
        }
        if (cfg.transform) values = cfg.transform(values, record);
        var res;
        try {
          res = edition ? col.update(record.id, values) : col.insert(values);
        } catch (e) {
          U2.toast('Enregistrement refusé.', { type: 'error', detail: e.message, duration: 9000 });
          return;
        }
        /* DIFFÉRÉ : on revient au registre juste après, et un toast posé
           ici partirait avec le document. */
        U2.toastDiffere(edition ? 'Modifications enregistrées.'
          : ((cfg.entite.charAt(0).toUpperCase() + cfg.entite.slice(1)) + ' créé.'), {
          type: 'success', duration: 7000,
          detail: res.record.code || res.record.reference || res.record.numero || null,
        });
        if (cfg.apres) cfg.apres(res.record, edition);
        /* On repart vers le registre : rester sur un formulaire déjà
           enregistré invite à l'enregistrer une seconde fois. */
        revenir();
      }
    };
  }

  /** La commande du bandeau, jumelle du bouton du pied de page. */
  function actionsPageFormulaire(module, libelle) {
    return function () {
      if (!droits(module).editer) return null;
      return [btn(libelle || 'Enregistrer', {
        variant: 'primary', size: 'sm', icon: 'save',
        onclick: function () {
          var c = document.getElementById('page-content');
          if (c && c.__enregistrerPage) c.__enregistrerPage();
        },
      })];
    };
  }

  global.SIGH.kit = {
    btn: btn, iconBtn: iconBtn, lien: lien,
    commande: commande, commandeIcone: commandeIcone,
    section: section, grid: grid, row: row, note: note, source: source,
    crud: crud, registre: registre, lectureSeule: lectureSeule, fileAttente: fileAttente,
    pageFormulaire: pageFormulaire, actionsPageFormulaire: actionsPageFormulaire,
    droits: droits, bandeauLectureSeule: bandeauLectureSeule,
    modifier: modifier, actionsLigne: actionsLigne, creer: creer,
    dash: dash, charts: charts, ranking: ranking, miniTable: miniTable,
    bandeauPremierRegard: bandeauPremierRegard, parcours: parcours,
    shortcuts: shortcuts, parMois: parMois, repartition: repartition,
    champsAge: champsAge, valeursAge: valeursAge,
    champsPrescripteur: champsPrescripteur, nomPrescripteur: nomPrescripteur,
    idPrescripteur: idPrescripteur, prescripteurEstExterne: prescripteurEstExterne,
    PRESCRIPTEUR_EXTERNE: PRESCRIPTEUR_EXTERNE,
  };
})(window);
