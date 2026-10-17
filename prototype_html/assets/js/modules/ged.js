/* =============================================================================
 * GED — Gestion documentaire & digitalisation des processus
 * -----------------------------------------------------------------------------
 * CDCT §10.12 — numérisation et rattachement des documents au dossier patient,
 * fournisseur ou employé : bons de commande et de livraison, factures,
 * ordonnances, résultats de laboratoire, rapports médicaux, contrats RH,
 * bulletins de paie et courriers administratifs.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  /* Référentiel partagé avec le peuplement du socle — voir D.GED_CATEGORIES. */
  var CATEGORIES = D.GED_CATEGORIES;
  function categorieLabel(id) {
    var c = CATEGORIES.filter(function (x) { return x.id === id; })[0];
    return c ? c.label : id;
  }
  function categorieIcon(id) {
    var c = CATEGORIES.filter(function (x) { return x.id === id; })[0];
    return c ? c.icon : 'file';
  }

  function amorcer() {
    /* La bibliothèque est PEUPLÉE AU SOCLE (data-seed.js, section
       administration) : le tableau de bord de l'assistant de direction la lit
       aussi, et une collection amorcée par son écran affiche zéro partout
       ailleurs — le piège documenté du prototype. Ici, on ne fait qu'ouvrir. */
    return S.collection('documents', { module: 'GED', entite: 'Document' });
  }

  /* ==========================================================================
   * BIBLIOTHÈQUE DOCUMENTAIRE
   * ======================================================================== */
  global.SIGH.screen('ged-bibliotheque', {
    title: 'Bibliothèque documentaire',
    regle: 'Bibliothèque de l’<strong>établissement</strong> — contrats, pièces fournisseurs, dossiers du '
      + 'personnel, procédures. Les documents du dossier patient vivent dans leur propre bibliothèque, '
      + 'sous le module M1. <strong>RG-14</strong> — retirer une pièce l’archive, elle reste restaurable.',
    description: 'Ensemble des documents numérisés, indexés et rattachés à leur dossier patient, fournisseur ou employé.',
    render: function (root) {
      var col = amorcer();
      var rows = col.active();
      var host = el('div.space-y-4');

      var stockage = C.sum(rows, 'taille');
      host.appendChild(U.kpiGrid([
        { label: 'Documents numérisés', value: C.num(rows.length), icon: 'files', tone: 'navy' },
        { label: 'Validés', value: C.num(rows.filter(function (d) { return d.etatValidation === 'valide'; }).length), icon: 'file-check-2', tone: 'success' },
        { label: 'En attente de validation', value: C.num(rows.filter(function (d) { return d.etatValidation === 'en_attente'; }).length), icon: 'file-clock', tone: 'warning' },
        { label: 'Rejetés', value: C.num(rows.filter(function (d) { return d.etatValidation === 'rejete'; }).length), icon: 'file-x', tone: 'danger' },
        { label: 'Documents signés', value: C.num(rows.filter(function (d) { return d.signe; }).length), icon: 'pen-tool', tone: 'info' },
        { label: 'Archivés', value: C.num(rows.filter(function (d) { return d.archive; }).length), icon: 'archive', tone: 'neutral' },
        { label: 'Volume de stockage', value: (stockage / 1024).toFixed(1) + ' Mo', icon: 'hard-drive', tone: 'neutral' },
        { label: 'Consultations cumulées', value: C.num(C.sum(rows, 'consultations')), icon: 'eye', tone: 'info' },
      ]));

      /* Explorateur par nature de rattachement */
      var explorateur = el('div.grid.gap-3.sm\\:grid-cols-2.lg\\:grid-cols-4');
      ['Patient', 'Employé', 'Fournisseur', 'Administration'].forEach(function (r) {
        var sel = rows.filter(function (d) { return d.rattachement === r; });
        var carte = el('div.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card');
        carte.appendChild(el('div.mb-2.flex.items-center.gap-2', null, [
          el('span.grid.h-8.w-8.place-items-center.rounded-lg.bg-navy-50.text-navy-700', null,
            C.icon({ Patient: 'user', 'Employé': 'id-card', Fournisseur: 'truck', Administration: 'building-2' }[r], 'h-4 w-4')),
          el('span.text-sm.font-semibold.text-slate-800', { text: 'Dossiers ' + r.toLowerCase() }),
        ]));
        carte.appendChild(el('p.text-2xl.font-semibold.num.text-slate-900', { text: C.num(sel.length) }));
        carte.appendChild(el('p.text-xs.text-slate-400', { text: 'documents rattachés' }));
        var ul = el('ul.mt-2.space-y-0\\.5');
        CATEGORIES.filter(function (c) { return c.rattachement === r; }).forEach(function (c) {
          var n = sel.filter(function (d) { return d.categorie === c.id; }).length;
          ul.appendChild(el('li.flex.items-center.justify-between.text-xs', null, [
            el('span.text-slate-500', { text: c.label }),
            el('span.num.font-medium.text-slate-700', { text: String(n) }),
          ]));
        });
        carte.appendChild(ul);
        explorateur.appendChild(carte);
      });
      host.appendChild(U.card('Explorateur par nature de rattachement', explorateur));

      host.appendChild(U.dataTable({
        title: 'Documents', rows: rows, exportName: 'ged-documents', pageSize: 20,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'categorie', label: 'Catégorie', options: CATEGORIES.map(function (c) { return { value: c.id, label: c.label }; }) },
          { name: 'rattachement', label: 'Rattachement', options: ['Patient', 'Employé', 'Fournisseur', 'Administration'] },
          { name: 'etatValidation', label: 'Validation', options: [{ value: 'valide', label: 'Validé' }, { value: 'en_attente', label: 'En attente' }, { value: 'rejete', label: 'Rejeté' }] },
          { name: 'format', label: 'Format', options: ['PDF', 'JPEG', 'DOCX', 'XLSX'] },
        ],
        columns: [
          { key: 'reference', label: 'Référence', nowrap: true, render: function (d) { return el('span.font-mono.text-xs.font-semibold', { text: d.reference }); } },
          {
            key: 'libelle', label: 'Document',
            render: function (d) {
              return el('div.flex.items-center.gap-2', null, [
                el('span.grid.h-7.w-7.shrink-0.place-items-center.rounded-lg.bg-slate-100.text-slate-500', null, C.icon(categorieIcon(d.categorie), 'h-3.5 w-3.5')),
                el('div.min-w-0', null, [
                  el('p.truncate.text-sm.text-slate-800', { text: d.libelle }),
                  el('p.text-xs.text-slate-400', { text: categorieLabel(d.categorie) }),
                ]),
              ]);
            },
          },
          { key: 'rattacheA', label: 'Rattaché à' },
          { key: 'codeRattachement', label: 'Code', nowrap: true, render: function (d) { return el('span.font-mono.text-xs.text-slate-500', { text: d.codeRattachement }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (d) { return C.dateFR(d.date); }, render: function (d) { return C.dateFR(d.date); } },
          { key: 'format', label: 'Format', render: function (d) { return U.badge(d.format, 'neutral'); } },
          { key: 'taille', label: 'Taille', align: 'right', render: function (d) { return d.taille + ' Ko'; } },
          { key: 'version', label: 'Version', align: 'right', render: function (d) { return 'v' + d.version; } },
          {
            key: 'etatValidation', label: 'Validation',
            render: function (d) {
              var m = { valide: ['Validé', 'success'], en_attente: ['En attente', 'warning'], rejete: ['Rejeté', 'danger'] };
              var x = m[d.etatValidation] || ['—', 'neutral'];
              return U.badge(x[0], x[1]);
            },
          },
          {
            key: 'signe', label: 'Signature',
            text: function (d) { return d.signe ? 'Signé' : 'Non signé'; },
            render: function (d) { return d.signe ? U.badge('Signé', 'info') : el('span.text-xs.text-slate-400', { text: '—' }); },
          },
        ],
        onRowClick: function (d) { consulter(d); },
        rowActions: function (d) {
          return [
            K.iconBtn('eye', 'Prévisualiser', function () { consulter(d); }),
            K.iconBtn('printer', 'Imprimer la fiche', function () { fiche(d); }),
          ];
        },
      }));
      root.appendChild(host);
      return null;

      function consulter(d) {
        U.drawer({
          title: d.libelle, subtitle: d.reference + ' — ' + categorieLabel(d.categorie), width: 'max-w-2xl',
          body: el('div.space-y-4', null, [
            el('div.flex.h-56.flex-col.items-center.justify-center.gap-2.rounded-lg.border.border-dashed.border-slate-300.bg-slate-50', null, [
              C.icon(categorieIcon(d.categorie), 'h-10 w-10 text-slate-300'),
              el('p.text-sm.text-slate-500', { text: 'Prévisualisation du document ' + d.format }),
              el('p.text-xs.text-slate-400', { text: d.taille + ' Ko — version ' + d.version }),
            ]),
            U.descList([
              ['Référence', d.reference], ['Libellé', d.libelle],
              ['Catégorie', categorieLabel(d.categorie)],
              ['Rattaché à', d.rattacheA + ' (' + d.codeRattachement + ')'],
              ['Nature du rattachement', d.rattachement],
              ['Date du document', C.dateFR(d.date)],
              ['Format', d.format], ['Taille', d.taille + ' Ko'],
              ['Version', 'v' + d.version],
              ['Déposé par', d.deposePar],
              ['Consultations', String(d.consultations)],
              ['Durée de conservation', d.conservation + ' ans'],
              ['Signature électronique', d.signe ? U.badge('Signé', 'success') : U.badge('Non signé', 'neutral')],
              ['Archivage', d.archive ? U.badge('Archivé', 'neutral') : U.badge('Actif', 'success')],
            ]),
            U.card('Traçabilité', U.timeline([
              { title: 'Document déposé', detail: 'Par ' + d.deposePar, date: C.dateFR(d.date), tone: 'success' },
              { title: 'Indexation automatique', detail: 'Rattaché au dossier ' + d.codeRattachement, date: C.dateFR(d.date), tone: 'info' },
              d.etatValidation === 'valide' ? { title: 'Document validé', detail: 'Workflow de validation clôturé', date: C.dateFR(C.addDays(d.date, 2)), tone: 'success' } : null,
              d.etatValidation === 'rejete' ? { title: 'Document rejeté', detail: 'À corriger et redéposer', date: C.dateFR(C.addDays(d.date, 2)), tone: 'danger' } : null,
              d.archive ? { title: 'Archivage', detail: 'Conservation ' + d.conservation + ' ans', date: C.dateFR(C.addDays(d.date, 30)), tone: 'neutral' } : null,
            ].filter(Boolean))),
          ]),
          footer: [K.btn('Imprimer la fiche', { variant: 'primary', icon: 'printer', onclick: function () { fiche(d); } })],
        });
      }

      function fiche(d) {
        P.etat({
          titre: 'Fiche documentaire',
          sousTitre: d.reference,
          cartouche: [['Référence', d.reference], ['Libellé', d.libelle],
            ['Catégorie', categorieLabel(d.categorie)], ['Rattaché à', d.rattacheA],
            ['Code de rattachement', d.codeRattachement], ['Date', C.dateFR(d.date)]],
          contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
            { k: 'Format', v: d.format },
            { k: 'Taille', v: d.taille + ' Ko' },
            { k: 'Version', v: 'v' + d.version },
            { k: 'Déposé par', v: d.deposePar },
            { k: 'État de validation', v: { valide: 'Validé', en_attente: 'En attente', rejete: 'Rejeté' }[d.etatValidation] },
            { k: 'Signature électronique', v: d.signe ? 'Oui' : 'Non' },
            { k: 'Archivage', v: d.archive ? 'Archivé' : 'Actif' },
            { k: 'Durée de conservation', v: d.conservation + ' ans' },
            { k: 'Consultations', v: String(d.consultations) },
          ]),
          signatures: [{ role: 'L’Agent administratif' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * WORKFLOW DE VALIDATION
   * ======================================================================== */
  global.SIGH.screen('ged-workflow', {
    title: 'Workflow de validation',
    regle: 'Écran de <strong>file de validation</strong> : on y valide ou l’on rejette, on n’y crée pas. '
      + 'Un document se dépose depuis la bibliothèque ; un rejet le renvoie à son déposant avec son motif.',
    description: 'Circuit de validation des documents déposés : contrôle, signature et classement.',
    render: function (root) {
      var col = amorcer();
      var host = el('div.space-y-4');
      var table;

      var etapes = [
        { id: 'depot', label: 'Dépôt', tone: 'neutral' },
        { id: 'indexation', label: 'Indexation', tone: 'info' },
        { id: 'controle', label: 'Contrôle', tone: 'info' },
        { id: 'validation', label: 'Validation', tone: 'warning' },
        { id: 'signature', label: 'Signature', tone: 'navy' },
        { id: 'classement', label: 'Classement', tone: 'success' },
      ];

      function enAttente() { return col.active().filter(function (d) { return d.etatValidation === 'en_attente'; }); }
      function rejetes() { return col.active().filter(function (d) { return d.etatValidation === 'rejete'; }); }

      host.appendChild(U.kpiGrid([
        { label: 'Documents à valider', value: C.num(enAttente().length), icon: 'file-clock', tone: 'warning' },
        { label: 'Rejetés à corriger', value: C.num(rejetes().length), icon: 'file-x', tone: 'danger' },
        { label: 'Validés', value: C.num(col.active().filter(function (d) { return d.etatValidation === 'valide'; }).length), icon: 'file-check-2', tone: 'success' },
        { label: 'Délai moyen de validation', value: '2 jours', icon: 'timer', tone: 'info' },
      ]));

      /* Circuit */
      var circuit = el('div.flex.flex-wrap.items-center.gap-1\\.5');
      etapes.forEach(function (e, i) {
        circuit.appendChild(el('span.inline-flex.items-center.gap-2.rounded-lg.border.px-3.py-2', {
          class: 'border-' + e.tone + '-200 bg-' + e.tone + '-50',
        }, [
          el('span', { class: 'text-' + e.tone + '-600' }, C.icon(['upload', 'tags', 'search-check', 'badge-check', 'pen-tool', 'folder-check'][i], 'h-4 w-4')),
          el('span.text-xs.font-medium', { class: 'text-' + e.tone + '-900', text: e.label }),
        ]));
        if (i < etapes.length - 1) circuit.appendChild(C.icon('chevron-right', 'h-3.5 w-3.5 text-slate-300'));
      });
      host.appendChild(U.card('Circuit de validation documentaire', circuit));

      table = U.dataTable({
        title: 'Documents en attente de validation',
        rows: enAttente, exportName: 'ged-a-valider', pageSize: 15,
        emptyMessage: 'Aucun document en attente de validation.',
        defaultSort: 'date', defaultDir: 'desc',
        columns: [
          { key: 'reference', label: 'Référence', nowrap: true, render: function (d) { return el('span.font-mono.text-xs', { text: d.reference }); } },
          { key: 'libelle', label: 'Document' },
          { key: 'categorie', label: 'Catégorie', text: categorieLabel, render: function (d) { return U.badge(categorieLabel(d.categorie), 'navy'); } },
          { key: 'rattacheA', label: 'Rattaché à' },
          { key: 'date', label: 'Date de dépôt', nowrap: true, text: function (d) { return C.dateFR(d.date); }, render: function (d) { return C.dateFR(d.date); } },
          { key: 'deposePar', label: 'Déposé par' },
          {
            key: 'anciennete', label: 'En attente depuis', align: 'right',
            value: function (d) { return C.daysBetween(d.date, AUJ); },
            render: function (d) {
              var j = C.daysBetween(d.date, AUJ);
              return el('span.num', { class: j > 15 ? 'font-semibold text-danger-600' : '', text: j + ' j' });
            },
          },
        ],
        bulkActions: function (getSelected, clear) {
          return [K.btn('Valider la sélection', {
            size: 'sm', variant: 'success', icon: 'badge-check',
            onclick: function () {
              var sel = getSelected();
              var majs = sel.map(function (d) { return col.update(d.id, { etatValidation: 'valide' }); });
              clear(); table.refresh();
              U.toast(sel.length + ' document(s) validé(s).', {
                type: 'success', undo: function () { majs.forEach(function (m) { m.undo(); }); table.refresh(); },
              });
            },
          })];
        },
        selectable: true,
        rowActions: function (d) {
          return [
            K.btn('Valider', {
              size: 'sm', variant: 'success', icon: 'check',
              onclick: function () {
                var res = col.update(d.id, { etatValidation: 'valide', signe: true });
                table.refresh();
                U.toast('Document validé et signé.', { type: 'success', undo: function () { res.undo(); table.refresh(); } });
              },
            }),
            K.iconBtn('x', 'Rejeter', function () {
              U.confirm({
                title: 'Rejeter ce document ?', message: 'Le document sera renvoyé à son déposant pour correction.',
                confirmLabel: 'Rejeter', danger: true, requireMotif: true,
              }).then(function (r) {
                if (!r) return;
                var res = col.update(d.id, { etatValidation: 'rejete', motifRejet: r.motif });
                table.refresh();
                U.toast('Document rejeté.', { type: 'warning', undo: function () { res.undo(); table.refresh(); } });
              });
            }, 'ghost'),
          ];
        },
      });
      host.appendChild(table);

      host.appendChild(K.note('La validation appose une <strong>signature électronique</strong> et verrouille le document : toute modification ultérieure crée une nouvelle version.', { tone: 'info', icon: 'pen-tool' }));

      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * ARCHIVAGE & CONSERVATION
   * ======================================================================== */
  global.SIGH.screen('ged-archives', {
    title: 'Archivage & conservation',
    description: 'Cycle de vie documentaire : archives actives, archives définitives et durées de conservation.',
    regle: 'Les durées de conservation appliquées sont : <strong>20 ans</strong> pour les documents patients, <strong>10 ans</strong> pour les documents RH et <strong>5 ans</strong> pour les documents administratifs et fournisseurs.',
    render: function (root) {
      var col = amorcer();
      var rows = col.active();
      var host = el('div.space-y-4');

      function echeance(d) { return C.addDays(d.date, d.conservation * 365); }
      function expire(d) { return echeance(d) < AUJ; }

      var archives = rows.filter(function (d) { return d.archive; });
      var actives = rows.filter(function (d) { return !d.archive; });
      var expires = rows.filter(expire);

      host.appendChild(U.kpiGrid([
        { label: 'Archives actives', value: C.num(actives.length), icon: 'folder-open', tone: 'success' },
        { label: 'Archives définitives', value: C.num(archives.length), icon: 'archive', tone: 'navy' },
        { label: 'Conservation échue', value: C.num(expires.length), icon: 'calendar-x', tone: expires.length ? 'danger' : 'neutral' },
        { label: 'Volume total', value: (C.sum(rows, 'taille') / 1024).toFixed(1) + ' Mo', icon: 'hard-drive', tone: 'info' },
      ]));

      host.appendChild(K.charts([
        {
          title: 'Répartition par durée de conservation',
          render: function () {
            var g = C.groupBy(rows, 'conservation');
            var keys = C.sortBy(Object.keys(g).map(Number));
            return G.anneau(keys.map(function (k) { return k + ' ans'; }), keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
          },
        },
        {
          title: 'Volume documentaire par catégorie',
          render: function () {
            var g = C.groupBy(rows, 'categorie');
            var keys = Object.keys(g);
            return G.barres(keys.map(categorieLabel),
              [{ label: 'Documents', data: keys.map(function (k) { return g[k].length; }) }],
              { horizontal: true, height: 320 });
          },
        },
      ]));

      host.appendChild(U.dataTable({
        title: 'Cycle de vie des documents', rows: rows, exportName: 'ged-archives', pageSize: 20,
        rowActions: K.actionsLigne(col, [
          { name: 'titre', label: 'Titre du document', required: true, col: 'full' },
          { name: 'categorie', label: 'Catégorie' },
          { name: 'dureeConservation', label: 'Durée de conservation (années)', type: 'number', min: 0 },
          { name: 'emplacement', label: 'Emplacement physique' },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ]),
        defaultSort: 'date',
        filters: [
          { name: 'archive', label: 'Statut d’archivage', options: [{ value: 'oui', label: 'Archivés' }, { value: 'non', label: 'Actifs' }], match: function (d, v) { return v === 'oui' ? !!d.archive : !d.archive; } },
          { name: 'conservation', label: 'Durée de conservation', options: [{ value: '5', label: '5 ans' }, { value: '10', label: '10 ans' }, { value: '20', label: '20 ans' }], match: function (d, v) { return String(d.conservation) === v; } },
        ],
        columns: [
          { key: 'reference', label: 'Référence', nowrap: true, render: function (d) { return el('span.font-mono.text-xs', { text: d.reference }); } },
          { key: 'libelle', label: 'Document' },
          { key: 'categorie', label: 'Catégorie', text: categorieLabel, render: function (d) { return U.badge(categorieLabel(d.categorie), 'navy'); } },
          { key: 'date', label: 'Date du document', nowrap: true, text: function (d) { return C.dateFR(d.date); }, render: function (d) { return C.dateFR(d.date); } },
          { key: 'conservation', label: 'Conservation', align: 'right', render: function (d) { return d.conservation + ' ans'; } },
          {
            key: 'echeance', label: 'Échéance', nowrap: true,
            value: function (d) { return echeance(d).getTime(); },
            text: function (d) { return C.dateFR(echeance(d)); },
            render: function (d) {
              return expire(d)
                ? U.badge('Échue le ' + C.dateFR(echeance(d)), 'danger')
                : C.dateFR(echeance(d));
            },
          },
          {
            key: 'archive', label: 'Statut',
            text: function (d) { return d.archive ? 'Archivé' : 'Actif'; },
            render: function (d) { return d.archive ? U.badge('Archive définitive', 'neutral') : U.badge('Archive active', 'success'); },
          },
        ],
        actions: [K.btn('Éditer le bordereau d’archivage', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Bordereau d’archivage documentaire',
              sousTitre: 'Situation au ' + C.dateFR(AUJ),
              cartouche: [['Documents', C.num(rows.length)],
                ['Archives actives', C.num(actives.length)],
                ['Archives définitives', C.num(archives.length)],
                ['Conservation échue', C.num(expires.length)],
                ['Volume', (C.sum(rows, 'taille') / 1024).toFixed(1) + ' Mo'],
                ['Date d’édition', C.dateFR(AUJ)]],
              contenu: P.tableau([
                { label: 'Référence', key: 'reference' },
                { label: 'Document', key: 'libelle' },
                { label: 'Catégorie', value: categorieLabel },
                { label: 'Date', value: function (d) { return C.dateFR(d.date); } },
                { label: 'Conservation', value: function (d) { return d.conservation + ' ans'; } },
                { label: 'Échéance', value: function (d) { return C.dateFR(echeance(d)); } },
                { label: 'Statut', value: function (d) { return d.archive ? 'Archive définitive' : 'Archive active'; } },
              ], C.sortBy(rows, 'date').slice(0, 80)),
              signatures: [{ role: 'L’Agent administratif' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
            });
          },
        })],
      }));

      if (expires.length) {
        host.appendChild(K.note('<strong>' + expires.length + ' document(s)</strong> ont atteint leur durée légale de conservation. '
          + 'Leur destruction doit faire l’objet d’une procédure encadrée et d’un procès-verbal signé.', { tone: 'warning', icon: 'calendar-x' }));
      }

      root.appendChild(host);
      return null;
    },
  });
})(window);
