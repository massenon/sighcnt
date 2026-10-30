/* =============================================================================
 * M6 — Pharmacie & Gestion des Stocks
 * -----------------------------------------------------------------------------
 * CDCT §10.1 — distinction stock gros (magasin central) / stock détail
 * (pharmacie d'urgence) avec traçabilité des transferts, gestion différenciée
 * par catégorie, CUMP sur consommables, alertes de péremption et de seuil,
 * inventaire automatisé, pertes et casses, FEFO, rayons et casiers.
 *
 * Règles appliquées :
 *   RG-02 — médicaments facturés au prix d'achat, sans marge.
 *   RG-03 — toute sortie rattachée à un justificatif ; stock jamais négatif.
 *   RG-05 — rangement FEFO, alertes de péremption paramétrables.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */
  var SEUIL_PEREMPTION = 90; /* jours — paramétrable (RG-05) */

  /* ==========================================================================
   * VALORISATION DES ARTICLES QUE LE DOCUMENT SAGE NE VALORISE PAS
   * --------------------------------------------------------------------------
   * Trente-deux références figurent à l'inventaire sans prix de revient. Aucun
   * document ne les tarife : le catalogue des médicaments a ses colonnes de
   * prix vierges. Les inventer fabriquerait une valeur de stock que personne
   * n'a arrêtée — c'est au gestionnaire de stock de les saisir.
   *
   * LA CORRECTION EST UNE SURCOUCHE. Le document reste ce qu'il est et fait foi
   * sur ce qu'il porte ; la valorisation vit à part, datée et signée. Écraser
   * l'inventaire ferait perdre la distinction entre ce que le document disait
   * et ce que la clinique a décidé — précisément ce qu'un audit demande.
   * ======================================================================== */
  function colValorisations() {
    return S.collection('valorisationsSage', { module: 'M6', entite: 'ValorisationSage', prefix: 'VSG' });
  }
  function valorisationDe(code) {
    return colValorisations().active().filter(function (v) { return v.code === code; })[0] || null;
  }
  /* Le prix retenu : celui du document s'il existe, sinon celui qu'on a saisi. */
  function prixRevient(a) {
    if (a.valorise) return a.cump;
    var v = valorisationDe(a.code);
    return v ? v.prixRevient : null;
  }
  function resteSansPrix(a) {
    return !a.valorise && !valorisationDe(a.code);
  }

  /**
   * Saisie du prix de revient d'une référence que le document ne valorise pas.
   *
   * La SOURCE est obligatoire. Un prix de revient sans origine est exactement
   * le problème qu'on cherche à résoudre : dans six mois, personne ne saura
   * s'il vient d'une facture fournisseur ou d'une estimation de couloir.
   */
  function saisirValorisation(article, apres) {
    var ancienne = valorisationDe(article.code);
    var f = U.form([
      { name: 'prixRevient', label: 'Prix de revient unitaire (FCFA)', type: 'number', min: 0,
        required: true, col: 'full',
        help: 'RG-02 — les médicaments se facturent au prix d’achat, sans marge.' },
      { name: 'source', label: 'Origine de la valeur', required: true, col: 'full',
        help: 'Facture fournisseur, bon de commande, relevé de prix… Sans origine, la valeur '
          + 'ne se vérifie pas.' },
      { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
    ], ancienne || {});

    var m = U.modal({
      title: (ancienne ? 'Corriger la valorisation — ' : 'Valoriser — ') + article.designation,
      size: 'md',
      body: el('div.space-y-3', null, [
        K.note('<strong>' + article.designation + '</strong> — ' + C.num(article.quantite) + ' unité(s) en stock. '
          + 'Cette référence figure à l’inventaire SAGE <strong>sans prix de revient</strong>. La valeur saisie '
          + 'ici <strong>ne modifie pas le document</strong> : elle est enregistrée à part, avec son auteur et sa '
          + 'date, pour que l’audit distingue toujours ce que le document portait de ce que la clinique a décidé.',
          { tone: 'info' }),
        f,
      ]),
      footer: [
        K.btn('Annuler', { onclick: function () { m.close(); } }),
        K.btn(ancienne ? 'Corriger' : 'Valoriser', {
          variant: 'primary', icon: 'check',
          onclick: function () {
            var v = f.collect();
            if (!v) return;
            var sess = S.session() || {};
            var fiche = {
              code: article.code, designation: article.designation,
              prixRevient: Number(v.prixRevient),
              source: v.source, observation: v.observation || null,
              auteur: sess.nomComplet || sess.identifiant || 'inconnu',
              date: C.iso(AUJ),
            };
            if (ancienne) colValorisations().update(ancienne.id, fiche);
            else colValorisations().insert(fiche);
            m.close();
            if (apres) apres();
            U.toast('Référence valorisée.', {
              type: 'success',
              detail: article.designation + ' — ' + C.money(fiche.prixRevient, false) + ' l’unité, soit '
                + C.money(fiche.prixRevient * article.quantite, false) + ' de stock.',
            });
          },
        }),
      ],
    });
  }

  function produits() { return S.collection('produits').active(); }
  function lots() { return S.collection('lots').active(); }
  function mouvements() { return S.collection('mouvements').active(); }

  function categorieLabel(id) {
    var c = D.CATEGORIES_PRODUIT.filter(function (x) { return x.id === id; })[0];
    return c ? c.label : id;
  }
  function optionsCategories() {
    return D.CATEGORIES_PRODUIT.map(function (c) { return { value: c.id, label: c.label }; });
  }
  function etatStock(p) {
    if (p.stock === 0) return 'rupture';
    if (p.stock <= p.seuilAlerte) return 'critique';
    return 'normal';
  }
  function valeurStock(rows) {
    return C.sum(rows, function (p) { return p.stock * p.cump; });
  }
  function joursAvantPeremption(l) { return C.daysBetween(AUJ, l.datePeremption); }

  /* --- Cellules réutilisables ---------------------------------------------- */
  var colCode = {
    key: 'code', label: 'Code', nowrap: true,
    render: function (p) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: p.code }); },
  };
  var colDesignation = {
    key: 'designation', label: 'Désignation',
    render: function (p) {
      return el('div.min-w-0', null, [
        el('p.truncate.text-sm.font-medium.text-slate-800', { text: p.designation }),
        el('p.text-xs.text-slate-400', { text: categorieLabel(p.categorie) + ' — ' + p.unite }),
      ]);
    },
  };
  function colStock(key, label) {
    return {
      key: key, label: label, align: 'right',
      render: function (p) {
        var v = p[key];
        var cls = v === 0 ? 'font-semibold text-danger-600' : (v <= p.seuilAlerte ? 'font-semibold text-warning-600' : '');
        return el('span', { class: cls, text: C.num(v) });
      },
    };
  }
  var colEtat = {
    key: 'etat', label: 'État',
    value: etatStock, text: function (p) { return etatStock(p); },
    render: function (p) { return U.statut(etatStock(p)); },
  };

  /* ==========================================================================
   * TABLEAU DE BORD STOCK
   * ======================================================================== */
  global.SIGH.screen('m6-dashboard', {
    title: 'Tableau de bord — Stocks',
    description: 'Valeur du stock, produits critiques, péremptions, rotation et visualisation par catégorie.',
    render: K.dash({
      alerte: function () {
        var r = produits().filter(function (p) { return p.stock <= p.seuilAlerte; });
        var pe = lots().filter(function (l) { return l.statut === 'perime'; });
        if (!r.length && !pe.length) return null;
        var wrap = el('div.grid.gap-2.sm\\:grid-cols-2');
        if (r.length) {
          wrap.appendChild(K.note('<strong>' + r.length + ' produit(s)</strong> sous le seuil d’alerte — établir un bon de commande (validation DA requise, RG-04).', { tone: 'danger', icon: 'trending-down' }));
        }
        if (pe.length) {
          wrap.appendChild(K.note('<strong>' + pe.length + ' lot(s) périmé(s)</strong> — retour aux fournisseurs habilités (CAME, SoBAPS) et valorisation de la perte.', { tone: 'danger', icon: 'alert-octagon' }));
        }
        return wrap;
      },
      kpis: function () {
        var p = produits(), l = lots();
        return [
          { label: 'Valeur totale du stock', value: C.money(valeurStock(p)), icon: 'wallet', tone: 'navy', hint: 'Valorisation au CUMP' },
          { label: 'Références gérées', value: C.num(p.length), icon: 'package', tone: 'info' },
          { label: 'Produits critiques', value: C.num(p.filter(function (x) { return x.stock <= x.seuilAlerte; }).length), icon: 'trending-down', tone: 'danger' },
          { label: 'Produits périmés', value: C.num(l.filter(function (x) { return x.statut === 'perime'; }).length), icon: 'calendar-x', tone: 'danger' },
          { label: 'Valeur stock gros', value: C.money(C.sum(p, function (x) { return x.stockGros * x.cump; })), icon: 'warehouse', tone: 'neutral' },
          { label: 'Valeur stock détail', value: C.money(C.sum(p, function (x) { return x.stockDetail * x.cump; })), icon: 'pill', tone: 'neutral' },
          { label: 'Mouvements du mois', value: C.num(mouvements().filter(function (m) { var d = C.toDate(m.date); return d.getMonth() === AUJ.getMonth() && d.getFullYear() === AUJ.getFullYear(); }).length), icon: 'arrow-left-right', tone: 'success' },
          { label: 'Péremption sous 90 j', value: C.num(l.filter(function (x) { return x.statut === 'alerte'; }).length), icon: 'clock', tone: 'warning', hint: 'Application du FEFO' },
        ];
      },
      kpiCols: 'grid-cols-2 lg:grid-cols-4',
      sections: [
        {
          render: function () {
            return K.charts([
              {
                title: 'Valeur du stock par catégorie',
                render: function () {
                  var g = C.groupBy(produits(), 'categorie');
                  var keys = Object.keys(g);
                  return G.barres(keys.map(categorieLabel),
                    [{ label: 'Valeur (FCFA)', data: keys.map(function (k) { return valeurStock(g[k]); }) }],
                    { horizontal: true, height: 320 });
                },
              },
              {
                title: 'Répartition gros / détail',
                render: function () {
                  var p = produits();
                  return G.anneau(['Stock gros (magasin)', 'Stock détail (pharmacie)'],
                    [C.sum(p, function (x) { return x.stockGros * x.cump; }), C.sum(p, function (x) { return x.stockDetail * x.cump; })],
                    { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Mouvements de stock (12 mois)',
                render: function () {
                  var m = mouvements();
                  var e = K.parMois(m.filter(function (x) { return x.type === 'entree'; }), 'date', 'quantite');
                  var s = K.parMois(m.filter(function (x) { return x.type === 'sortie'; }), 'date', 'quantite');
                  var pertes = K.parMois(m.filter(function (x) { return ['perte', 'casse', 'peremption'].indexOf(x.type) !== -1; }), 'date', 'quantite');
                  return G.barres(e.labels, [
                    { label: 'Entrées', data: e.data, color: G.TONES.vert },
                    { label: 'Sorties', data: s.data, color: G.TONES.navy },
                    { label: 'Pertes', data: pertes.data, color: G.TONES.rouge },
                  ]);
                },
              },
              {
                title: 'État des péremptions',
                render: function () {
                  var l = lots();
                  var perimes = l.filter(function (x) { return x.statut === 'perime'; }).length;
                  var alerte = l.filter(function (x) { return x.statut === 'alerte'; }).length;
                  return G.anneau(['Périmés', 'Sous 90 jours', 'Au-delà de 90 jours'],
                    [perimes, alerte, l.length - perimes - alerte],
                    { legend: 'bottom', colors: [G.TONES.rouge, G.TONES.orange, G.TONES.vert] });
                },
              },
            ]);
          },
        },
        {
          title: 'Produits à réapprovisionner en priorité',
          actions: function () { return [K.lien('m6-alertes', 'Toutes les alertes', { size: 'sm', icon: 'arrow-right' })]; },
          render: function () {
            var r = C.sortBy(produits().filter(function (p) { return p.stock <= p.seuilAlerte; }), 'stock').slice(0, 10);
            if (!r.length) return U.empty('Aucun produit sous le seuil d’alerte.', { icon: 'check-circle-2' });
            return K.miniTable([
              { label: 'Code', render: function (p) { return el('span.font-mono.text-xs', { text: p.code }); } },
              { label: 'Désignation', key: 'designation' },
              { label: 'Catégorie', render: function (p) { return categorieLabel(p.categorie); } },
              { label: 'Stock', align: 'right', key: 'stock' },
              { label: 'Seuil', align: 'right', key: 'seuilAlerte' },
              { label: 'Emplacement', key: 'emplacement' },
              { label: 'État', render: function (p) { return U.statut(etatStock(p)); } },
            ], r);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm6-inventaire', icon: 'clipboard-check', label: 'Inventaire', detail: 'Physique contre théorique' },
              { id: 'm6-transferts', icon: 'arrow-left-right', label: 'Transferts', detail: 'Gros vers détail' },
              { id: 'm6-lots', icon: 'calendar-x', label: 'Lots & péremptions', detail: 'Principe FEFO' },
              { id: 'm7-besoins', icon: 'clipboard-list', label: 'Expression de besoins', detail: 'Demande interne' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * RÉFÉRENTIEL PRODUITS
   * ======================================================================== */
  function detailProduit(p) {
    var mvts = C.sortBy(mouvements().filter(function (m) { return m.produitId === p.id; }), 'date', 'desc');
    var lotsP = C.sortBy(lots().filter(function (l) { return l.produitId === p.id; }), 'datePeremption');
    var wrap = el('div.space-y-4');

    wrap.appendChild(U.kpiGrid([
      { label: 'Stock total', value: C.num(p.stock) + ' ' + p.unite, icon: 'package', tone: etatStock(p) === 'normal' ? 'success' : 'danger' },
      { label: 'Valeur au CUMP', value: C.money(p.stock * p.cump), icon: 'wallet', tone: 'navy' },
    ], 'grid-cols-2'));

    wrap.appendChild(U.tabs([
      {
        id: 'fiche', label: 'Fiche produit',
        render: function () {
          return U.descList([
            ['Code article', el('span.font-mono', { text: p.code })],
            ['Désignation', p.designation],
            ['Catégorie', categorieLabel(p.categorie)],
            ['Unité', p.unite],
            ['Prix d’achat', C.money(p.prixAchat)],
            ['Prix de vente', el('span', null, [
              document.createTextNode(C.money(p.prixVente)),
              p.categorie === 'medicament' ? el('span.ml-2.badge.badge-info', { text: 'Sans marge (RG-02)' }) : null,
            ])],
            ['CUMP', C.money(p.cump)],
            ['Stock gros', C.num(p.stockGros) + ' ' + p.unite],
            ['Stock détail', C.num(p.stockDetail) + ' ' + p.unite],
            ['Seuil d’alerte', C.num(p.seuilAlerte)],
            ['Emplacement', p.emplacement],
            ['Fournisseur habituel', p.fournisseur],
          ]);
        },
      },
      {
        id: 'lots', label: 'Lots (FEFO)', badge: lotsP.length,
        render: function () {
          if (!lotsP.length) return U.empty('Aucun lot enregistré pour ce produit.', { icon: 'boxes' });
          return K.miniTable([
            { label: 'N° lot', render: function (l) { return el('span.font-mono.text-xs', { text: l.numeroLot }); } },
            { label: 'Péremption', render: function (l) { return C.dateFR(l.datePeremption); } },
            { label: 'Reste', align: 'right', render: function (l) { return C.num(l.quantiteRestante); } },
            {
              label: 'État',
              render: function (l) {
                var j = joursAvantPeremption(l);
                return j < 0 ? U.badge('Périmé', 'danger') : (j <= SEUIL_PEREMPTION ? U.badge('Dans ' + j + ' j', 'warning') : U.badge('Valide', 'success'));
              },
            },
            { label: 'Emplacement', key: 'emplacement' },
          ], lotsP);
        },
      },
      {
        id: 'mouvements', label: 'Mouvements', badge: mvts.length,
        render: function () {
          if (!mvts.length) return U.empty('Aucun mouvement enregistré.', { icon: 'arrow-left-right' });
          return K.miniTable([
            { label: 'Date', render: function (m) { return C.dateFR(m.date); } },
            {
              label: 'Type',
              render: function (m) {
                var t = D.TYPES_MOUVEMENT.filter(function (x) { return x.id === m.type; })[0];
                return U.badge(m.typeLabel, t ? t.badge : 'neutral');
              },
            },
            { label: 'Quantité', align: 'right', key: 'quantite' },
            { label: 'Justificatif', key: 'justificatif' },
            { label: 'Opérateur', key: 'utilisateur' },
          ], mvts.slice(0, 20));
        },
      },
    ]));
    return wrap;
  }

  global.SIGH.screen('m6-produits', {
    title: 'Référentiel produits',
    description: 'Catalogue de tous les articles gérés : médicaments, réactifs, consommables, fournitures, entretien, petit matériel et immobilisations.',
    regle: '<strong>RG-02</strong> — le prix de vente des médicaments est égal au prix d’achat : aucune marge bénéficiaire n’est appliquée, sauf exception validée et tracée par la Direction.',
    render: K.crud({
      collection: 'produits', entite: 'produit', entiteP: 'produits', module: 'M6',
      defaultSort: 'designation', pageSize: 15, drawerWidth: 'max-w-3xl',
      source: 'Inventaire « Grand Stock » SAGE 100 et tarifs médicaments de la clinique.',
      columns: [
        colCode, colDesignation,
        { key: 'unite', label: 'Unité' },
        { key: 'prixAchat', label: 'Prix d’achat', align: 'right', text: function (p) { return C.money(p.prixAchat, false); }, render: function (p) { return C.money(p.prixAchat, false); } },
        { key: 'cump', label: 'CUMP', align: 'right', text: function (p) { return C.money(p.cump, false); }, render: function (p) { return C.money(p.cump, false); } },
        colStock('stockGros', 'Stock gros'), colStock('stockDetail', 'Stock détail'),
        colStock('stock', 'Total'),
        { key: 'seuilAlerte', label: 'Seuil', align: 'right' },
        {
          key: 'valeur', label: 'Valeur', align: 'right',
          value: function (p) { return p.stock * p.cump; },
          text: function (p) { return C.money(p.stock * p.cump, false); },
          render: function (p) { return C.money(p.stock * p.cump, false); },
        },
        colEtat,
      ],
      fields: [
        { type: 'section', label: 'Identification' },
        { name: 'code', label: 'Code article', required: true },
        { name: 'designation', label: 'Désignation', required: true, col: 'full' },
        { name: 'categorie', label: 'Catégorie', type: 'select', required: true, options: optionsCategories() },
        { name: 'unite', label: 'Unité', required: true, placeholder: 'Comprimé, Flacon, Boîte…' },
        { type: 'section', label: 'Tarification' },
        {
          name: 'prixAchat', label: 'Prix d’achat (FCFA)', type: 'money', required: true, min: 0,
          help: 'RG-02 — sert également de prix de vente pour les médicaments.',
        },
        { name: 'prixVente', label: 'Prix de vente (FCFA)', type: 'money', min: 0 },
        { name: 'cump', label: 'CUMP (FCFA)', type: 'money', min: 0, help: 'Calculé automatiquement à chaque entrée en stock.' },
        { type: 'section', label: 'Stock et rangement' },
        { name: 'stockGros', label: 'Stock gros', type: 'number', min: 0 },
        { name: 'stockDetail', label: 'Stock détail', type: 'number', min: 0 },
        { name: 'seuilAlerte', label: 'Seuil d’alerte', type: 'number', min: 0, required: true },
        { name: 'emplacement', label: 'Emplacement (rayon / casier)', col: 'full' },
        {
          name: 'fournisseur', label: 'Fournisseur habituel', type: 'select',
          options: D.FOURNISSEURS.map(function (f) { return { value: f.code, label: f.nom }; }),
        },
      ],
      onCreate: function () {
        return { categorie: 'medicament', stockGros: 0, stockDetail: 0, stock: 0, seuilAlerte: 10, unite: 'Unité' };
      },
      transform: function (v) {
        v.stockGros = Number(v.stockGros) || 0;
        v.stockDetail = Number(v.stockDetail) || 0;
        v.stock = v.stockGros + v.stockDetail;
        /* RG-02 : sans marge sur les médicaments. */
        if (v.categorie === 'medicament' || !v.prixVente) v.prixVente = v.prixAchat;
        if (!v.cump) v.cump = v.prixAchat;
        return v;
      },
      beforeSave: function (v) {
        if (Number(v.stockGros) < 0 || Number(v.stockDetail) < 0) return 'RG-03 — le stock ne peut pas devenir négatif.';
        return null;
      },
      filters: [
        { name: 'categorie', label: 'Catégorie', options: optionsCategories() },
        {
          name: 'etat', label: 'État du stock',
          options: [{ value: 'rupture', label: 'En rupture' }, { value: 'critique', label: 'Sous le seuil' }, { value: 'normal', label: 'Normal' }],
          match: function (p, v) { return etatStock(p) === v; },
        },
      ],
      kpis: function (rows) {
        return [
          { label: 'Références', value: C.num(rows.length), icon: 'package', tone: 'navy' },
          { label: 'Valeur du stock', value: C.money(valeurStock(rows)), icon: 'wallet', tone: 'info' },
          { label: 'Sous le seuil', value: C.num(rows.filter(function (p) { return p.stock <= p.seuilAlerte && p.stock > 0; }).length), icon: 'trending-down', tone: 'warning' },
          { label: 'En rupture', value: C.num(rows.filter(function (p) { return p.stock === 0; }).length), icon: 'x-circle', tone: 'danger' },
        ];
      },
      detail: detailProduit,
      etat: function (p) {
        var lotsP = C.sortBy(lots().filter(function (l) { return l.produitId === p.id; }), 'datePeremption');
        P.etat({
          titre: 'Fiche article',
          sousTitre: p.code + ' — ' + p.designation,
          cartouche: [['Code', p.code], ['Désignation', p.designation], ['Catégorie', categorieLabel(p.categorie)],
            ['Unité', p.unite], ['Emplacement', p.emplacement], ['Fournisseur', p.fournisseur]],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Valeur', key: 'v', align: 'right' }], [
              { k: 'Prix d’achat', v: C.money(p.prixAchat, false) },
              { k: 'Prix de vente', v: C.money(p.prixVente, false) },
              { k: 'Coût unitaire moyen pondéré (CUMP)', v: C.money(p.cump, false) },
              { k: 'Stock gros', v: C.num(p.stockGros) },
              { k: 'Stock détail', v: C.num(p.stockDetail) },
              { k: 'Stock total', v: C.num(p.stock) },
              { k: 'Seuil d’alerte', v: C.num(p.seuilAlerte) },
              { k: 'Valeur du stock', v: C.money(p.stock * p.cump, false) },
            ]),
            lotsP.length ? el('div', null, [
              el('p.mb-1.mt-4.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Lots en stock (classement FEFO)' }),
              P.tableau([
                { label: 'N° lot', key: 'numeroLot' },
                { label: 'Péremption', value: function (l) { return C.dateFR(l.datePeremption); } },
                { label: 'Quantité restante', key: 'quantiteRestante', align: 'right' },
                { label: 'Emplacement', key: 'emplacement' },
              ], lotsP),
            ]) : null,
          ]),
          signatures: [{ role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' }],
        });
      },
    }),
  });

  /* ==========================================================================
   * STOCK GROS / STOCK DÉTAIL
   * ======================================================================== */
  function ecranStock(id, titre, description, champStock, note) {
    global.SIGH.screen(id, {
      title: titre,
      description: description,
      render: function (root) {
        var rows = produits().filter(function (p) { return p[champStock] > 0 || p.stock === 0; });
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Références présentes', value: C.num(rows.filter(function (p) { return p[champStock] > 0; }).length), icon: 'package', tone: 'navy' },
          { label: 'Quantité totale', value: C.num(C.sum(rows, champStock)), icon: 'boxes', tone: 'info' },
          { label: 'Valeur (CUMP)', value: C.money(C.sum(rows, function (p) { return p[champStock] * p.cump; })), icon: 'wallet', tone: 'success' },
          { label: 'Sous le seuil', value: C.num(rows.filter(function (p) { return p[champStock] <= p.seuilAlerte; }).length), icon: 'trending-down', tone: 'danger' },
        ]));
        host.appendChild(K.note(note, { tone: 'info' }));

        host.appendChild(U.dataTable({
          title: titre, rows: rows, exportName: id, pageSize: 15, searchable: true,
          defaultSort: champStock, defaultDir: 'desc',
          filters: [{ name: 'categorie', label: 'Catégorie', options: optionsCategories() }],
          columns: [
            colCode, colDesignation,
            { key: 'unite', label: 'Unité' },
            colStock(champStock, 'Quantité'),
            { key: 'seuilAlerte', label: 'Seuil', align: 'right' },
            { key: 'cump', label: 'CUMP', align: 'right', text: function (p) { return C.money(p.cump, false); }, render: function (p) { return C.money(p.cump, false); } },
            {
              key: 'valeur', label: 'Valeur', align: 'right',
              value: function (p) { return p[champStock] * p.cump; },
              text: function (p) { return C.money(p[champStock] * p.cump, false); },
              render: function (p) { return C.money(p[champStock] * p.cump, false); },
            },
            { key: 'emplacement', label: 'Emplacement' },
            colEtat,
          ],
          onRowClick: function (p) { U.drawer({ title: p.designation, subtitle: p.code, body: detailProduit(p), width: 'max-w-3xl' }); },
          actions: [K.btn('Éditer l’état', {
            size: 'sm', icon: 'printer',
            onclick: function () {
              P.etat({
                titre: 'État du ' + titre.toLowerCase(),
                sousTitre: 'Situation au ' + C.dateFR(AUJ),
                cartouche: [['Références', C.num(rows.filter(function (p) { return p[champStock] > 0; }).length)],
                  ['Quantité totale', C.num(C.sum(rows, champStock))],
                  ['Valeur au CUMP', C.money(C.sum(rows, function (p) { return p[champStock] * p.cump; }))],
                  ['Date d’édition', C.dateFR(AUJ)]],
                contenu: P.tableau([
                  { label: 'Code', key: 'code' }, { label: 'Désignation', key: 'designation' },
                  { label: 'Catégorie', value: function (p) { return categorieLabel(p.categorie); } },
                  { label: 'Unité', key: 'unite' },
                  { label: 'Quantité', key: champStock, align: 'right' },
                  { label: 'CUMP', align: 'right', value: function (p) { return C.money(p.cump, false); } },
                  { label: 'Valeur', align: 'right', value: function (p) { return C.money(p[champStock] * p.cump, false); },
                    somme: function (p) { return p[champStock] * p.cump; } },
                ], C.sortBy(rows.filter(function (p) { return p[champStock] > 0; }), 'designation'), { total: true }),
                signatures: [{ role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' },
                  { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
              });
            },
          })],
        }));

        /* ------------------------------------------------------------------
         * LES MOUVEMENTS DE LA PÉRIODE (demande du 02/09/2026 : une plage de
         * dates sur les écrans de stock). L'ÉTAT ci-dessus reste À UNE DATE
         * — la doctrine tient — ; c'est le FLUX qui prend la période : ce
         * qui est entré et sorti de ce stock entre deux dates.
         * ---------------------------------------------------------------- */
        var dDebut = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, -30)) });
        var dFin = el('input.input', { type: 'date', value: C.iso(AUJ) });
        var typeStock = champStock === 'stockGros' ? 'gros' : 'detail';
        var zoneMvts = el('div');

        function peindreMvts() {
          C.clear(zoneMvts);
          var mvts = S.collection('mouvements').active().filter(function (m) {
            var d = String(m.date || '').slice(0, 10);
            if (m.stockType && m.stockType !== typeStock) return false;
            if (dDebut.value && d < dDebut.value) return false;
            if (dFin.value && d > dFin.value) return false;
            return true;
          });
          zoneMvts.appendChild(U.dataTable({
            title: 'Mouvements de la période — le flux, pas l’état',
            rows: C.sortBy(mvts, 'date').reverse(), pageSize: 10, searchable: true,
            exportName: id + '-mouvements',
            emptyMessage: 'Aucun mouvement de ce stock sur la période choisie. Les mouvements '
              + 's’enregistrent aux écrans de transfert, dispensation et pertes (M6).',
            columns: [
              { key: 'date', label: 'Date', render: function (m) { return C.dateFR(m.date); } },
              { key: 'produit', label: 'Produit' },
              { key: 'typeLabel', label: 'Nature', render: function (m) { return m.typeLabel || m.type; } },
              { key: 'quantite', label: 'Quantité', align: 'right' },
              { key: 'justificatif', label: 'Justificatif (RG-03)' },
            ],
          }));
        }
        var barreMvts = el('div.card');
        barreMvts.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
          el('div', null, [el('label.label', { text: 'Mouvements du' }), dDebut]),
          el('div', null, [el('label.label', { text: 'au' }), dFin]),
        ]));
        [dDebut, dFin].forEach(function (x) { x.addEventListener('change', peindreMvts); });
        host.appendChild(barreMvts);
        host.appendChild(zoneMvts);
        peindreMvts();

        root.appendChild(host);
        return null;
      },
    });
  }

  ecranStock('m6-stock-gros', 'Stock gros (magasin central)',
    'Situation du magasin central : réceptions fournisseurs et approvisionnement de la pharmacie de détail.',
    'stockGros',
    'Le magasin central reçoit les livraisons fournisseurs. Les sorties s’effectuent par <strong>transfert vers le stock de détail</strong>, chaque transfert étant tracé (RG-03).');

  ecranStock('m6-stock-detail', 'Stock détail (pharmacie d’urgence)',
    'Situation de la pharmacie d’urgence : dispensation aux patients et aux services de soins.',
    'stockDetail',
    'La pharmacie de détail dispense aux patients et aux services. Toute sortie est rattachée à une facture ou à un bon de service (RG-03).');

  /* ==========================================================================
   * TRANSFERTS GROS → DÉTAIL
   * ======================================================================== */
  global.SIGH.screen('m6-transferts', {
    title: 'Transferts gros → détail',
    description: 'Approvisionnement de la pharmacie d’urgence depuis le magasin central, avec traçabilité complète.',
    regle: '<strong>RG-03</strong> — chaque transfert génère un bon numéroté et deux mouvements de stock symétriques ; le stock du magasin ne peut jamais devenir négatif.',
    render: function (root) {
      var col = S.collection('transferts', { module: 'M6', entite: 'Transfert' });
      var host = el('div.space-y-4');
      var zoneKpi = el('div');
      var table, tableLignes;

      /* ------------------------------------------------------------------
       * LES LIGNES À PLAT — une ligne par article transféré, portant le bon
       * dont elle vient. C'est la même donnée que le bon, lue autrement :
       * « qu'est-ce qui est parti du magasin ? » se répond article par
       * article, pas bon par bon. Jamais une seconde collection.
       * ---------------------------------------------------------------- */
      function toutesLignes(bons) {
        var out = [];
        (bons || col.active()).forEach(function (t) {
          lignesDe(t).forEach(function (l, i) {
            var pr = l.produitId ? S.collection('produits').get(l.produitId) : null;
            out.push({
              id: t.id + '-' + i, bonId: t.id, reference: t.reference, date: t.date,
              demandeur: t.demandeur || '—', operateur: t.operateur || '—',
              code: l.code || (pr ? pr.code : ''),
              produit: l.produit, categorie: l.categorie || (pr ? pr.categorie : ''),
              unite: l.unite || '', quantite: Number(l.quantite) || 0, cump: Number(l.cump) || 0,
              lot: l.lot || '', peremption: l.peremption || '',
              valeur: valeurLigne(l),
            });
          });
        });
        return out;
      }

      function peindreKpi() {
        C.clear(zoneKpi);
        var bons = col.active(), lg = toutesLignes(bons);
        zoneKpi.appendChild(U.kpiGrid([
          { label: 'Bons de transfert', value: C.num(bons.length), icon: 'arrow-left-right', tone: 'navy' },
          { label: 'Articles transférés (lignes)', value: C.num(lg.length), icon: 'list', tone: 'info' },
          /* La valeur se lit sur les LIGNES : l'en-tête d'un bon multi-lignes
             ne porte pas de CUMP, et « quantité × CUMP de l'en-tête » valait
             zéro pour tous les bons à plusieurs articles. */
          { label: 'Valeur transférée', value: C.money(C.sum(lg, 'valeur')), icon: 'wallet', tone: 'success' },
          { label: 'Bons du mois', value: C.num(bons.filter(function (t) { var d = C.toDate(t.date); return d.getMonth() === AUJ.getMonth() && d.getFullYear() === AUJ.getFullYear(); }).length), icon: 'calendar', tone: 'neutral' },
        ]));
      }
      function rafraichir() {
        peindreKpi();
        table.refresh();
        tableLignes.refresh();
      }

      function optionsDestinations() {
        var vus = {};
        col.active().forEach(function (t) { if (t.demandeur) vus[t.demandeur] = true; });
        return Object.keys(vus).sort();
      }

      table = U.dataTable({
        title: 'Bons de transfert',
        rows: function () { return col.active(); },
        exportName: 'transferts', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        emptyMessage: 'Aucun transfert enregistré.',
        emptyHint: 'Un transfert déplace une quantité du magasin central vers la pharmacie de détail.',
        filters: [{ name: 'demandeur', label: 'Destination', options: optionsDestinations() }],
        /* LE BOUTON OBÉIT AUX DROITS. Le Caissier-Dispensateur voit les
           transferts — il reçoit la marchandise, il doit pouvoir vérifier le
           bon — mais il ne les émet pas : le mouvement part du magasin. Un
           bouton offert sans le droit mène à un refus, ou pire, à une saisie
           qui ne s'enregistre pas. */
        actions: [
          K.btn('Imprimer le registre détaillé', { size: 'sm', icon: 'printer',
            onclick: function () { etatRegistre(table.lignesFiltrees()); } }),
          K.commande('Nouveau transfert', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(); } }),
        ],
        onRowClick: function (t) { detail(t); },
        columns: [
          { key: 'reference', label: 'N° bon', nowrap: true, render: function (t) { return el('span.font-mono.text-xs.font-semibold', { text: t.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (t) { return C.dateFR(t.date); }, render: function (t) { return C.dateFR(t.date); } },
          { key: 'demandeur', label: 'Destination' },
          /* CE QUE LE BON TRANSPORTE, lisible sans l'ouvrir : les premières
             désignations, puis le reste compté. « 7 articles » ne répondait
             à aucune question ; la liste entière est au tiroir. */
          {
            key: 'articles', label: 'Articles transférés',
            value: function (t) { return lignesDe(t).map(function (l) { return l.produit; }).join(' · '); },
            text: function (t) { return lignesDe(t).map(function (l) { return l.produit + ' (' + l.quantite + ')'; }).join(' · '); },
            render: function (t) {
              var lg = lignesDe(t);
              var vus = lg.slice(0, 3).map(function (l) { return l.produit + ' ×' + C.num(l.quantite); });
              return el('div.max-w-md', null, [
                el('p.truncate.text-xs.text-slate-700', { text: vus.join(' · '), title: lg.map(function (l) { return l.produit + ' ×' + l.quantite; }).join('\n') }),
                lg.length > 3 ? el('p.text-\\[11px\\].text-slate-400', { text: '+ ' + (lg.length - 3) + ' autre(s) article(s)' }) : null,
              ]);
            },
          },
          { key: 'nbLignes', label: 'Lignes', align: 'right', value: function (t) { return lignesDe(t).length; }, render: function (t) { return C.num(lignesDe(t).length); } },
          { key: 'quantite', label: 'Quantité', align: 'right', value: function (t) { return totalQuantite(lignesDe(t)); }, render: function (t) { return C.num(totalQuantite(lignesDe(t))); } },
          {
            key: 'valeur', label: 'Valeur', align: 'right',
            value: function (t) { return totalValeur(lignesDe(t)); },
            text: function (t) { return C.money(totalValeur(lignesDe(t)), false); },
            render: function (t) { return C.money(totalValeur(lignesDe(t)), false); },
          },
          { key: 'receptionnaire', label: 'Réceptionnaire', render: function (t) { return t.receptionnaire || '—'; } },
          { key: 'operateur', label: 'Opérateur' },
        ],
        rowActions: function (t) {
          return [
            /* LE DÉTAIL DES ARTICLES : le tiroir porte le bon ENTIER, ligne
               par ligne, avec ses totaux — c'est la première question du
               magasinier comme du réceptionnaire. */
            K.iconBtn('eye', 'Voir les articles du bon', function () { detail(t); }),
            K.iconBtn('printer', 'Imprimer le bon', function () { etat(t); }),
            K.commandeIcone('pencil', 'Modifier le bon', function () { refusModification(t); }),
            K.commandeIcone('archive', 'Archiver', function () {
              var res = col.archive(t.id);
              rafraichir();
              U.toast('Transfert archivé.', { type: 'success', undo: function () { res.undo(); rafraichir(); } });
            }, { variant: 'ghost', droit: 'annuler' }),
          ];
        },
      });

      /* ------------------------------------------------------------------
       * VUE DÉTAILLÉE PAR ARTICLE — une ligne par article transféré.
       * Recherche, filtres (famille, destination), export et impression
       * portent sur les LIGNES : c'est ici qu'on répond à « combien de
       * paracétamol est parti vers la maternité ce trimestre ? ».
       * ---------------------------------------------------------------- */
      tableLignes = U.dataTable({
        title: 'Articles transférés — une ligne par article',
        rows: function () { return toutesLignes(); },
        exportName: 'transferts-articles', pageSize: 15,
        defaultSort: 'date', defaultDir: 'desc',
        searchPlaceholder: 'Article, code, lot, n° de bon…',
        emptyMessage: 'Aucun article transféré.',
        filters: [
          { name: 'categorie', label: 'Famille', options: optionsCategories() },
          { name: 'demandeur', label: 'Destination', options: optionsDestinations() },
        ],
        actions: [
          K.btn('Imprimer l’état détaillé', { size: 'sm', icon: 'printer',
            onclick: function () { etatLignes(tableLignes.lignesFiltrees()); } }),
        ],
        onRowClick: function (r) { var t = col.get(r.bonId); if (t) detail(t); },
        columns: [
          { key: 'reference', label: 'N° bon', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold', { text: r.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'code', label: 'Code', render: function (r) { return el('span.font-mono.text-xs', { text: r.code || '—' }); } },
          { key: 'produit', label: 'Article' },
          { key: 'categorie', label: 'Famille', text: function (r) { return categorieLabel(r.categorie); }, render: function (r) { return r.categorie ? categorieLabel(r.categorie) : '—'; } },
          { key: 'lot', label: 'Lot', render: function (r) { return r.lot || '—'; } },
          { key: 'peremption', label: 'Péremption', nowrap: true, text: function (r) { return r.peremption ? C.dateFR(r.peremption) : ''; }, render: function (r) { return r.peremption ? C.dateFR(r.peremption) : '—'; } },
          { key: 'quantite', label: 'Quantité', align: 'right', render: function (r) { return C.num(r.quantite); } },
          { key: 'unite', label: 'Unité' },
          { key: 'cump', label: 'CUMP', align: 'right', text: function (r) { return C.money(r.cump, false); }, render: function (r) { return C.money(r.cump, false); } },
          { key: 'valeur', label: 'Valeur', align: 'right', text: function (r) { return C.money(r.valeur, false); }, render: function (r) { return C.money(r.valeur, false); } },
          { key: 'demandeur', label: 'Magasin → destination', text: function (r) { return 'Magasin → ' + r.demandeur; }, render: function (r) { return 'Magasin → ' + r.demandeur; } },
        ],
        rowActions: function (r) {
          return [K.iconBtn('eye', 'Voir le bon ' + r.reference, function () { var t = col.get(r.bonId); if (t) detail(t); })];
        },
      });

      peindreKpi();
      host.appendChild(zoneKpi);
      host.appendChild(U.tabs([
        { id: 'bons', label: 'Bons de transfert', render: function () { table.refresh(); return table; } },
        { id: 'articles', label: 'Vue détaillée par article', render: function () { tableLignes.refresh(); return tableLignes; } },
      ]));
      root.appendChild(host);
      return null;

      /* ======================================================================
       * TRANSFERT MULTI-LIGNES
       * ----------------------------------------------------------------------
       * Un réapprovisionnement de pharmacie porte sur quinze à vingt
       * références. Les transférer une à une obligeait à rouvrir la modale
       * vingt fois et produisait vingt bons là où il n'y a qu'un seul voyage
       * de caisses. La modale porte donc un tableau de lignes qu'on remplit
       * sans la fermer.
       * ==================================================================== */
      function ouvrir() {
        var dispo = produits().filter(function (p) { return p.stockGros > 0; });
        if (!dispo.length) {
          U.toast('Aucun produit disponible au magasin central.', { type: 'warning' });
          return;
        }

        /* Les lignes du bon en cours de construction. */
        var lignes = [];

        /* --- L'en-tête du bon, commun à toutes les lignes ------------------ */
        var entete = U.form([
          { name: 'date', label: 'Date du transfert', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'demandeur', label: 'Service demandeur', type: 'select', required: true,
            options: ['Pharmacie d’urgence', 'Pharmacie externe', 'Laboratoire',
              'Hospitalisation', 'Maternité', 'Bloc opératoire', 'Salle de soins'] },
          { name: 'motif', label: 'Motif du transfert', col: 'full' },
        ], {});

        /* --- La ligne de saisie -------------------------------------------- */
        var selProduit = U.combo(C.sortBy(dispo, 'designation').map(function (p2) {
          return {
            value: p2.id,
            label: p2.designation,
            detail: 'disponible : ' + C.num(p2.stockGros) + ' ' + p2.unite,
          };
        }), { placeholder: 'Choisir un article…' });

        var champQte = el('input#transfert-quantite.h-10.w-28.rounded-lg.border.border-slate-300.px-3.text-sm', {
          type: 'number', min: '1', placeholder: 'Qté',
        });

        var hoteTable = el('div');

        function produitDe(id2) {
          return produits().filter(function (x) { return x.id === id2; })[0] || null;
        }

        /* Ce qui reste disponible pour un article, une fois déduit ce qui est
           DÉJÀ posé sur le bon en cours. Sans cette déduction, on pourrait
           inscrire deux fois la totalité du stock sur le même bon. */
        function disponibleRestant(produitId, saufIndex) {
          var pr = produitDe(produitId);
          if (!pr) return 0;
          var pose = lignes.reduce(function (n, l, k) {
            return n + (l.produitId === produitId && k !== saufIndex ? l.quantite : 0);
          }, 0);
          return pr.stockGros - pose;
        }

        function ajouter() {
          var pid = selProduit.value;
          var qte = Number(champQte.value) || 0;
          if (!pid) { U.toast('Choisir un article.', { type: 'error' }); return; }
          if (qte <= 0) { U.toast('Indiquer une quantité supérieure à zéro.', { type: 'error' }); return; }
          var pr = produitDe(pid);
          var reste = disponibleRestant(pid, -1);
          /* RG-03, ligne par ligne, en NOMMANT l'article. */
          if (qte > reste) {
            U.toast('RG-03 — « ' + pr.designation + ' » : ' + C.num(reste) + ' ' + pr.unite
              + ' encore disponible(s) au magasin' + (reste < pr.stockGros
                ? ' (déjà ' + C.num(pr.stockGros - reste) + ' sur ce bon)' : '') + '.',
            { type: 'error' });
            return;
          }
          /* Le même article deux fois sur un bon se cumule au lieu de faire
             deux lignes : le magasinier compte des caisses, pas des lignes. */
          var existante = lignes.filter(function (l) { return l.produitId === pid; })[0];
          if (existante) {
            existante.quantite += qte;
          } else {
            /* Lot FEFO (RG-05) et famille voyagent avec la ligne : le bon
               imprimé et la vue par article les lisent sans refaire la
               recherche, et un lot épuisé plus tard ne réécrit pas le bon. */
            var lotF = lots().filter(function (x) {
              return x.produitId === pid && x.statut !== 'perime' && (x.quantiteRestante || 0) > 0;
            }).sort(function (a, b) { return String(a.datePeremption).localeCompare(String(b.datePeremption)); })[0];
            lignes.push({
              produitId: pid, code: pr.code, produit: pr.designation, categorie: pr.categorie,
              unite: pr.unite, cump: pr.cump, quantite: qte,
              lot: lotF ? lotF.numeroLot : null, peremption: lotF ? lotF.datePeremption : null,
            });
          }
          champQte.value = '';
          /* U.combo n'a pas de clear() : il expose un accesseur value, et
             C.clear() sur lui viderait son bouton au lieu de sa sélection. */
          selProduit.value = '';
          rendreTable();
        }

        champQte.addEventListener('keydown', function (ev) {
          if (ev.key === 'Enter') { ev.preventDefault(); ajouter(); }
        });

        function modifier(k) {
          var l = lignes[k];
          var f2 = U.form([
            { name: 'quantite', label: 'Quantité', type: 'number', min: 1, required: true,
              value: l.quantite,
              hint: C.num(disponibleRestant(l.produitId, k)) + ' ' + l.unite + ' disponible(s) au magasin.' },
          ], {});
          var m2 = U.modal({
            title: 'Modifier — ' + l.produit, size: 'sm', body: f2,
            footer: [
              K.btn('Annuler', { onclick: function () { m2.close(); } }),
              K.btn('Appliquer', { variant: 'primary', icon: 'check',
                onclick: function () {
                  var v2 = f2.collect();
                  if (!v2) return;
                  var reste = disponibleRestant(l.produitId, k);
                  if (v2.quantite > reste) {
                    U.toast('RG-03 — « ' + l.produit + ' » : ' + C.num(reste) + ' ' + l.unite
                      + ' disponible(s) seulement.', { type: 'error' });
                    return;
                  }
                  l.quantite = v2.quantite;
                  m2.close(); rendreTable();
                } }),
            ],
          });
        }

        function retirer(k) {
          var l = lignes[k];
          lignes.splice(k, 1);
          rendreTable();
          U.toast('Ligne retirée — ' + l.produit + '.', {
            type: 'info',
            undo: function () { lignes.splice(k, 0, l); rendreTable(); },
            undoMessage: 'Ligne rétablie.',
          });
        }

        function rendreTable() {
          C.clear(hoteTable);
          if (!lignes.length) {
            hoteTable.appendChild(el('p.rounded-lg.border.border-dashed.border-slate-300.px-4.py-6.text-center.text-sm.text-slate-400',
              { text: 'Aucune ligne sur ce bon. Choisir un article et une quantité, puis « Ajouter ».' }));
            return;
          }
          hoteTable.appendChild(U.dataTable({
            rows: lignes.map(function (l, k) { return Object.assign({ _k: k }, l); }),
            columns: [
              { key: 'produit', label: 'Article' },
              { key: 'quantite', label: 'Quantité', align: 'right',
                render: function (r) { return C.num(r.quantite) + ' ' + r.unite; } },
              { key: 'reste', label: 'Restera au magasin', align: 'right',
                render: function (r) {
                  var pr = produitDe(r.produitId);
                  return C.num((pr ? pr.stockGros : 0) - r.quantite) + ' ' + r.unite;
                } },
              { key: 'valeur', label: 'Valeur (CUMP)', align: 'right',
                somme: function (r) { return r.quantite * (r.cump || 0); },
                render: function (r) { return C.money(r.quantite * (r.cump || 0)); } },
            ],
            rowActions: function (r) {
              return [
                K.iconBtn('pencil', 'Modifier la quantité', function () { modifier(r._k); }),
                K.iconBtn('trash-2', 'Retirer la ligne', function () { retirer(r._k); }, 'ghost'),
              ];
            },
          }));
          hoteTable.appendChild(el('p.mt-2.text-right.text-sm.font-semibold.text-slate-700', {
            text: C.num(lignes.length) + ' ligne(s) — valeur totale '
              + C.money(lignes.reduce(function (n, l) { return n + l.quantite * (l.cump || 0); }, 0)),
          }));
          U.icons(hoteTable);
        }

        var corps = el('div.space-y-4', null, [
          entete,
          U.card('Articles à transférer',
            el('div.space-y-3', null, [
              el('div.flex.flex-wrap.items-end.gap-2', null, [
                el('div.min-w-\\[16rem\\].flex-1', null, [
                  el('label.mb-1.block.text-xs.font-medium.text-slate-500', { text: 'Article' }),
                  selProduit,
                ]),
                el('div', null, [
                  el('label.mb-1.block.text-xs.font-medium.text-slate-500', { text: 'Quantité' }),
                  champQte,
                ]),
                K.btn('Ajouter', { variant: 'secondary', icon: 'plus', onclick: ajouter }),
              ]),
              hoteTable,
            ])),
        ]);
        rendreTable();

        var m = U.modal({
          title: 'Nouveau transfert de stock',
          subtitle: 'Magasin central → pharmacie de détail. Plusieurs articles sur un même bon.',
          size: 'xl', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Valider le transfert', {
              variant: 'primary', icon: 'arrow-left-right',
              onclick: function () {
                var v = entete.collect();
                if (!v) { U.toast('L’en-tête du bon comporte des erreurs.', { type: 'error' }); return; }
                if (!lignes.length) {
                  U.toast('Ajouter au moins un article au bon.', { type: 'error' });
                  return;
                }
                /* Dernier contrôle RG-03 avant écriture : le stock a pu bouger
                   pendant la saisie. Le refus nomme la ligne fautive. */
                var faute = null;
                lignes.forEach(function (l) {
                  var pr = produitDe(l.produitId);
                  if (!pr || l.quantite > pr.stockGros) faute = l;
                });
                if (faute) {
                  U.toast('RG-03 — « ' + faute.produit + ' » : le stock du magasin ne couvre plus '
                    + C.num(faute.quantite) + ' ' + faute.unite + '.', { type: 'error' });
                  return;
                }

                /* LE NUMÉRO SUIT LE REGISTRE, pas un compteur de page :
                   `C.nextRef` repart de 1 à chaque chargement et aurait
                   réémis TR-00001 par-dessus un bon existant. */
                var dernier = col.all().reduce(function (mx, x) {
                  var mm = /^TR-(\d+)$/.exec(x.reference || '');
                  return mm ? Math.max(mx, Number(mm[1])) : mx;
                }, 0);
                var reference = 'TR-' + C.pad(dernier + 1, 5);
                var etats = [], mvts = [];
                var colMvt = S.collection('mouvements', { module: 'M6', entite: 'MouvementStock' });
                lignes.forEach(function (l) {
                  var pr = produitDe(l.produitId);
                  etats.push({ id: pr.id, gros: pr.stockGros, detail: pr.stockDetail });
                  S.collection('produits').update(pr.id, {
                    stockGros: pr.stockGros - l.quantite,
                    stockDetail: pr.stockDetail + l.quantite,
                  });
                  /* DEUX MOUVEMENTS SYMÉTRIQUES (RG-03) : le magasin débité,
                     la pharmacie créditée. Un seul mouvement « détail »
                     laissait la sortie du magasin invisible au point des
                     stocks, qui la cherche du côté gros. */
                  mvts.push(colMvt.insert({
                    reference: reference, date: v.date, produitId: pr.id, produit: pr.designation,
                    type: 'transfert', typeLabel: 'Transfert — sortie magasin', quantite: l.quantite,
                    stockType: 'gros', justificatif: 'Bon de transfert ' + reference,
                    utilisateur: S.currentUser(),
                  }));
                  mvts.push(colMvt.insert({
                    reference: reference, date: v.date, produitId: pr.id, produit: pr.designation,
                    type: 'transfert', typeLabel: 'Transfert — entrée pharmacie', quantite: l.quantite,
                    stockType: 'detail', justificatif: 'Bon de transfert ' + reference,
                    utilisateur: S.currentUser(),
                  }));
                });

                var res = col.insert(Object.assign({}, v, {
                  reference: reference,
                  lignes: lignes.slice(),
                  nbLignes: lignes.length,
                  quantiteTotale: lignes.reduce(function (n, l) { return n + l.quantite; }, 0),
                  valeur: lignes.reduce(function (n, l) { return n + l.quantite * (l.cump || 0); }, 0),
                  operateur: S.currentUser(),
                  etat: 'receptionne', dateReception: v.date,
                  /* Compatibilité avec les bons antérieurs, qui ne portaient
                     qu'un produit : le tableau du registre lit ces champs. */
                  produit: lignes.length === 1 ? lignes[0].produit
                    : lignes.length + ' articles',
                  unite: lignes.length === 1 ? lignes[0].unite : '',
                  quantite: lignes.reduce(function (n, l) { return n + l.quantite; }, 0),
                }));

                m.close(); rafraichir();
                U.toast('Transfert de ' + C.num(lignes.length) + ' article(s) enregistré.', {
                  type: 'success', detail: reference + ' — ' + v.demandeur,
                  /* L'annulation restitue TOUTES les lignes : un transfert
                     partiellement annulé laisserait le stock faux. */
                  undo: function () {
                    etats.forEach(function (e) {
                      S.collection('produits').update(e.id, { stockGros: e.gros, stockDetail: e.detail });
                    });
                    mvts.forEach(function (x) { x.undo(); });
                    res.undo(); rafraichir();
                  },
                  undoMessage: 'Transfert annulé — les ' + C.num(lignes.length) + ' lignes sont restituées.',
                });
              },
            }),
          ],
        });
      }

      /* --------------------------------------------------------------------
       * LES LIGNES D'UN BON — deux générations cohabitent
       * --------------------------------------------------------------------
       * Les bons émis avant le passage au multi-lignes ne portent qu'un
       * produit, à plat sur l'en-tête. Les lire comme une liste vide aurait
       * fait sortir un bon sans un seul article ; les convertir en base aurait
       * réécrit des pièces déjà signées. On les ADAPTE à la lecture.
       * ------------------------------------------------------------------ */
      function lignesDe(t) {
        if (t.lignes && t.lignes.length) return t.lignes;
        return [{ produitId: t.produitId, produit: t.produit, unite: t.unite,
          quantite: t.quantite, cump: t.cump }];
      }
      function valeurLigne(l) { return (Number(l.quantite) || 0) * (Number(l.cump) || 0); }
      function totalQuantite(lg) {
        return lg.reduce(function (n, l) { return n + (Number(l.quantite) || 0); }, 0);
      }
      function totalValeur(lg) {
        return lg.reduce(function (n, l) { return n + valeurLigne(l); }, 0);
      }

      function detail(t) {
        var lg = lignesDe(t);
        U.drawer({
          title: 'Bon de transfert ' + t.reference,
          subtitle: C.dateFR(t.date) + ' — ' + (t.demandeur || ''),
          width: 'max-w-2xl',
          body: el('div.space-y-4', null, [
            U.descList([
              ['Référence', el('span.font-mono', { text: t.reference })],
              ['Date', C.dateFR(t.date)],
              ['Origine', 'Magasin central (stock gros)'],
              ['Destination', t.demandeur || '—'],
              ['Opérateur', t.operateur || '—'],
              ['Réceptionnaire', t.receptionnaire || '—'],
              ['Motif', t.motif || '—'],
              ['Articles', C.num(lg.length)],
              ['Quantité totale', C.num(totalQuantite(lg))],
              ['Valeur totale', C.money(totalValeur(lg))],
            ]),
            U.card('Articles transférés — du magasin de gros vers le détail',
              el('div.space-y-2', null, [
                tableLignesBon(lg),
                el('p.text-right.text-sm.font-semibold.text-slate-700', {
                  text: C.num(lg.length) + ' article(s) — ' + C.num(totalQuantite(lg))
                    + ' unité(s), valeur totale ' + C.money(totalValeur(lg)),
                }),
              ])),
          ]),
          footer: [K.btn('Imprimer le bon', { variant: 'primary', icon: 'printer',
            onclick: function () { etat(t); } })],
        });
      }

      /* Un transfert VALIDÉ a déjà déplacé le stock : le modifier laisserait
         les deux magasins faux sans qu'aucun mouvement ne le dise. On le
         refuse EN EXPLIQUANT le chemin — archiver, puis réémettre. */
      function refusModification(t) {
        U.confirm({
          title: 'Un bon de transfert ne se modifie pas',
          message: 'Le bon <strong>' + C.escapeHtml(t.reference) + '</strong> a déjà déplacé le stock : '
            + 'deux mouvements symétriques ont été écrits, le magasin débité et la pharmacie créditée. '
            + 'Le corriger ici laisserait les deux stocks faux sans qu’aucun mouvement ne le dise '
            + '(RG-03).<br><br>Pour corriger : <strong>archiver ce bon</strong>, puis en émettre un '
            + 'nouveau avec les bonnes quantités.',
          confirmLabel: 'Archiver ce bon', danger: true,
        }).then(function (rep) {
          if (!rep) return;
          var res = col.archive(t.id, rep.motif);
          rafraichir();
          U.toast('Bon archivé — émettre le bon corrigé.', {
            type: 'success',
            undo: function () { res.undo(); rafraichir(); },
          });
        });
      }

      /* Le tableau des lignes d'UN bon, au tiroir : pied de TOTAL calculé
         depuis les lignes affichées, comme sur la pièce imprimée — les deux
         doivent dire la même chose. */
      function tableLignesBon(lg) {
        var t2 = el('table.tbl');
        var entetes = ['Article', 'Famille', 'Lot / péremption', 'Quantité', 'CUMP', 'Valeur'];
        var htr = el('tr');
        entetes.forEach(function (h, i) {
          htr.appendChild(el('th', { class: i >= 3 ? 'text-right' : '', text: h }));
        });
        t2.appendChild(el('thead', null, htr));
        var tb = el('tbody');
        lg.forEach(function (l) {
          var pr = l.produitId ? S.collection('produits').get(l.produitId) : null;
          var cat = l.categorie || (pr ? pr.categorie : '');
          tb.appendChild(el('tr', null, [
            el('td', null, [
              el('p.font-medium.text-slate-800', { text: l.produit }),
              (l.code || pr) ? el('p.font-mono.text-\\[11px\\].text-slate-400', { text: l.code || pr.code }) : null,
            ]),
            el('td.text-xs', { text: cat ? categorieLabel(cat) : '—' }),
            el('td.text-xs', { text: l.lot ? l.lot + (l.peremption ? ' — ' + C.dateFR(l.peremption) : '') : '—' }),
            el('td.text-right.num', { text: C.num(l.quantite) + ' ' + (l.unite || '') }),
            el('td.text-right.num', { text: C.money(l.cump || 0, false) }),
            el('td.text-right.num', { text: C.money(valeurLigne(l), false) }),
          ]));
        });
        t2.appendChild(tb);
        t2.appendChild(el('tfoot', null, el('tr.bg-slate-50.font-semibold', null, [
          el('td', { text: 'TOTAL — ' + C.num(lg.length) + ' article(s)' }),
          el('td'), el('td'),
          el('td.text-right.num', { text: C.num(totalQuantite(lg)) }),
          el('td'),
          el('td.text-right.num', { text: C.money(totalValeur(lg), false) }),
        ])));
        return el('div.overflow-x-auto.transfert-lignes', null, t2);
      }

      function etat(t) {
        var lg = lignesDe(t);
        P.etat({
          titre: 'Bon de transfert de stock',
          sousTitre: t.reference,
          /* Une pièce unique : les filtres de la page ne la concernent pas. */
          filtres: false,
          cartouche: [['Référence', t.reference], ['Date', C.dateFR(t.date)],
            ['Origine', 'Magasin central (stock gros)'], ['Destination', t.demandeur],
            ['Opérateur', t.operateur], ['Réceptionnaire', t.receptionnaire || '—'],
            ['Motif', t.motif || '—'], ['Articles transférés', C.num(lg.length)]],
          /* LE DÉTAIL, ET LE TOTAL CALCULÉ depuis les lignes imprimées : le
             bon ne portait que sa ligne d'en-tête — « 4 articles » — et aucun
             total. On ne signe pas un bon qui ne dit pas ce qu'il transporte. */
          contenu: P.tableau([
            { label: 'Code', value: function (x) { return x.code || ''; } },
            { label: 'Article', key: 'produit' },
            { label: 'Famille', value: function (x) { return x.categorie ? categorieLabel(x.categorie) : ''; } },
            { label: 'Lot', value: function (x) { return x.lot || ''; } },
            { label: 'Péremption', value: function (x) { return x.peremption ? C.dateFR(x.peremption) : ''; } },
            { label: 'Unité', key: 'unite' },
            { label: 'Quantité transférée', align: 'right',
              value: function (x) { return C.num(x.quantite); },
              somme: function (x) { return Number(x.quantite) || 0; },
              formatTotal: function (v) { return C.num(v); } },
            { label: 'CUMP', align: 'right', value: function (x) { return C.money(x.cump || 0, false); } },
            { label: 'Valeur', align: 'right',
              value: function (x) { return C.money(valeurLigne(x), false); },
              somme: valeurLigne },
          ], lg, { total: true, totalLabel: 'TOTAL DU BON' }),
          signatures: [{ role: 'Le Gestionnaire de Stock', nom: t.operateur || 'MAMAN Zoukanéri', mention: 'Sortie magasin' },
            { role: 'Le Service demandeur', nom: t.receptionnaire || null, mention: 'Réception' }],
        });
      }

      /* Colonnes communes aux deux états détaillés : une ligne par article,
         avec le bon dont elle vient. Quantité et valeur se TOTALISENT (somme
         refaite sur les lignes imprimées) ; le CUMP, prix unitaire, non —
         additionner des prix unitaires ne produit aucune grandeur. */
      function colonnesEtatLignes() {
        return [
          { label: 'N° bon', key: 'reference' },
          { label: 'Date', value: function (x) { return C.dateFR(x.date); } },
          { label: 'Destination', key: 'demandeur' },
          { label: 'Article', key: 'produit' },
          { label: 'Famille', value: function (x) { return x.categorie ? categorieLabel(x.categorie) : ''; } },
          { label: 'Lot', value: function (x) { return x.lot || ''; } },
          { label: 'Qté', align: 'right',
            value: function (x) { return C.num(x.quantite) + (x.unite ? ' ' + x.unite : ''); },
            somme: function (x) { return Number(x.quantite) || 0; },
            formatTotal: function (v) { return C.num(v); } },
          { label: 'CUMP', align: 'right', value: function (x) { return C.money(x.cump || 0, false); } },
          { label: 'Valeur', align: 'right',
            value: function (x) { return C.money(x.valeur, false); },
            somme: function (x) { return Number(x.valeur) || 0; } },
        ];
      }
      function trierLignes(lg) {
        return lg.slice().sort(function (a, b) {
          return String(a.date).localeCompare(String(b.date))
            || String(a.reference).localeCompare(String(b.reference));
        });
      }

      /* LE REGISTRE : les bons retenus par la recherche et les filtres, et
         CE QU'ILS TRANSPORTENT — ligne par ligne, puis le récapitulatif par
         bon. Un registre qui ne compterait que des bons ne dirait pas ce qui
         est sorti du magasin. */
      function etatRegistre(bons) {
        bons = C.sortBy(bons, 'date');
        var lg = trierLignes(toutesLignes(bons));
        P.etat({
          titre: 'Registre des transferts gros → détail',
          sousTitre: 'Détail des articles transférés — ' + C.num(bons.length) + ' bon(s), ' + C.num(lg.length) + ' ligne(s)',
          cartouche: [['Origine', 'Magasin central (stock gros)'],
            ['Période', bons.length ? C.dateFR(bons[0].date) + ' au ' + C.dateFR(bons[bons.length - 1].date) : '—'],
            ['Bons', C.num(bons.length)], ['Lignes d’articles', C.num(lg.length)]],
          contenu: el('div.space-y-4', null, [
            el('p.text-\\[11px\\].font-semibold.uppercase.text-slate-700', { text: 'Détail des articles transférés' }),
            P.tableau(colonnesEtatLignes(), lg, { total: true, totalLabel: 'TOTAL GÉNÉRAL' }),
            el('p.text-\\[11px\\].font-semibold.uppercase.text-slate-700', { text: 'Récapitulatif par bon' }),
            P.tableau([
              { label: 'N° bon', key: 'reference' },
              { label: 'Date', value: function (t) { return C.dateFR(t.date); } },
              { label: 'Destination', key: 'demandeur' },
              { label: 'Réceptionnaire', value: function (t) { return t.receptionnaire || ''; } },
              { label: 'Lignes', align: 'right', value: function (t) { return C.num(lignesDe(t).length); },
                somme: function (t) { return lignesDe(t).length; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Quantité', align: 'right', value: function (t) { return C.num(totalQuantite(lignesDe(t))); },
                somme: function (t) { return totalQuantite(lignesDe(t)); }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Valeur', align: 'right', value: function (t) { return C.money(totalValeur(lignesDe(t)), false); },
                somme: function (t) { return totalValeur(lignesDe(t)); } },
            ], bons, { total: true }),
          ]),
          signatures: [{ role: 'Le Gestionnaire de Stock', mention: 'Sorties magasin' },
            { role: 'La Directrice Administrative', mention: 'Visa' }],
        });
      }

      /* L'état de la vue par article : les lignes retenues, telles quelles. */
      function etatLignes(lg) {
        lg = trierLignes(lg);
        P.etat({
          titre: 'État détaillé des articles transférés',
          sousTitre: 'Magasin central → services — ' + C.num(lg.length) + ' ligne(s)',
          cartouche: [['Origine', 'Magasin central (stock gros)'], ['Lignes d’articles', C.num(lg.length)],
            ['Bons concernés', C.num(Object.keys(C.groupBy(lg, 'reference')).length)]],
          contenu: P.tableau(colonnesEtatLignes(), lg, { total: true, totalLabel: 'TOTAL' }),
          signatures: [{ role: 'Le Gestionnaire de Stock', mention: 'Certifié exact' }],
        });
      }
    },
  });

  /* ==========================================================================
   * MOUVEMENTS DE STOCK
   * ======================================================================== */
  global.SIGH.screen('m6-mouvements', {
    title: 'Mouvements de stock',
    description: 'Registre chronologique de tous les mouvements : entrées, sorties, transferts, pertes, casses, péremptions et régularisations.',
    regle: '<strong>RG-03</strong> — chaque mouvement de sortie est rattaché à un justificatif (facture, bon de transfert, constat de perte ou retour de péremption).',
    render: K.crud({
      collection: 'mouvements', entite: 'mouvement', entiteP: 'mouvements', module: 'M6',
      defaultSort: 'date', defaultDir: 'desc', pageSize: 15,
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (m) { return el('span.font-mono.text-xs', { text: m.reference }); } },
        { key: 'date', label: 'Date', nowrap: true, text: function (m) { return C.dateFR(m.date); }, render: function (m) { return C.dateFR(m.date); } },
        { key: 'produit', label: 'Produit' },
        {
          key: 'type', label: 'Type',
          render: function (m) {
            var t = D.TYPES_MOUVEMENT.filter(function (x) { return x.id === m.type; })[0];
            return U.badge(m.typeLabel || (t && t.label) || m.type, t ? t.badge : 'neutral');
          },
        },
        {
          key: 'quantite', label: 'Quantité', align: 'right',
          render: function (m) {
            var t = D.TYPES_MOUVEMENT.filter(function (x) { return x.id === m.type; })[0];
            var sens = t ? t.sens : 0;
            var cls = sens > 0 ? 'font-semibold text-success-600' : (sens < 0 ? 'font-semibold text-danger-600' : 'text-slate-600');
            return el('span', { class: cls, text: (sens > 0 ? '+' : (sens < 0 ? '−' : '')) + C.num(m.quantite) });
          },
        },
        {
          key: 'stockType', label: 'Stock',
          text: function (m) { var t = D.TYPES_STOCK.filter(function (x) { return x.id === m.stockType; })[0]; return t ? t.label : m.stockType; },
          render: function (m) {
            var t = D.TYPES_STOCK.filter(function (x) { return x.id === m.stockType; })[0];
            return U.badge(t ? t.label.split(' (')[0] : m.stockType, 'neutral');
          },
        },
        { key: 'justificatif', label: 'Justificatif (RG-03)' },
        { key: 'utilisateur', label: 'Opérateur' },
      ],
      fields: function () {
        return [
          {
            name: 'produitId', label: 'Produit', type: 'select', required: true, col: 'full',
            options: C.sortBy(produits(), 'designation').map(function (p) { return { value: p.id, label: p.designation + ' (stock : ' + p.stock + ')' }; }),
          },
          { name: 'type', label: 'Type de mouvement', type: 'select', required: true, options: D.TYPES_MOUVEMENT.map(function (t) { return { value: t.id, label: t.label }; }) },
          { name: 'quantite', label: 'Quantité', type: 'number', min: 1, required: true },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'stockType', label: 'Stock concerné', type: 'select', required: true, options: D.TYPES_STOCK.map(function (t) { return { value: t.id, label: t.label }; }) },
          { name: 'justificatif', label: 'Justificatif', required: true, col: 'full', help: 'RG-03 — obligatoire pour toute sortie de stock.' },
        ];
      },
      onCreate: function () { return { date: C.iso(AUJ), type: 'entree', stockType: 'gros' }; },
      transform: function (v) {
        var p = produits().filter(function (x) { return x.id === v.produitId; })[0];
        if (p) v.produit = p.designation;
        var t = D.TYPES_MOUVEMENT.filter(function (x) { return x.id === v.type; })[0];
        if (t) v.typeLabel = t.label;
        v.utilisateur = S.currentUser();
        if (!v.reference) v.reference = C.nextRef('M', 6);
        return v;
      },
      beforeSave: function (v) {
        var p = produits().filter(function (x) { return x.id === v.produitId; })[0];
        var t = D.TYPES_MOUVEMENT.filter(function (x) { return x.id === v.type; })[0];
        if (p && t && t.sens < 0) {
          var dispo = v.stockType === 'gros' ? p.stockGros : p.stockDetail;
          if (Number(v.quantite) > dispo) {
            return 'RG-03 — sortie de ' + v.quantite + ' impossible : stock disponible de ' + dispo + ' seulement.';
          }
        }
        return null;
      },
      filters: [
        { name: 'type', label: 'Type', options: D.TYPES_MOUVEMENT.map(function (t) { return { value: t.id, label: t.label }; }) },
        { name: 'stockType', label: 'Stock', options: D.TYPES_STOCK.map(function (t) { return { value: t.id, label: t.label }; }) },
      ],
      kpis: function (rows) {
        var e = rows.filter(function (m) { return m.type === 'entree'; });
        var s = rows.filter(function (m) { return m.type === 'sortie'; });
        var pertes = rows.filter(function (m) { return ['perte', 'casse', 'peremption'].indexOf(m.type) !== -1; });
        return [
          { label: 'Mouvements enregistrés', value: C.num(rows.length), icon: 'arrow-left-right', tone: 'navy' },
          { label: 'Entrées', value: C.num(C.sum(e, 'quantite')), icon: 'arrow-down-left', tone: 'success' },
          { label: 'Sorties', value: C.num(C.sum(s, 'quantite')), icon: 'arrow-up-right', tone: 'info' },
          { label: 'Pertes et casses', value: C.num(C.sum(pertes, 'quantite')), icon: 'trash-2', tone: 'danger' },
        ];
      },
    }),
  });

  /* ==========================================================================
   * LOTS & PÉREMPTIONS (FEFO)
   * ======================================================================== */
  global.SIGH.screen('m6-lots', {
    title: 'Lots & péremptions (FEFO)',
    description: 'Suivi des lots par date de péremption, application du principe « premier périmé, premier sorti ».',
    regle: '<strong>RG-05</strong> — le rangement applique le principe <strong>FEFO</strong> (premier périmé, premier sorti). '
      + 'Les alertes sont déclenchées automatiquement ' + SEUIL_PEREMPTION + ' jours avant échéance. '
      + 'Les produits périmés sont retournés aux fournisseurs habilités (CAME, SoBAPS) et la perte est valorisée en comptabilité.',
    render: K.crud({
      collection: 'lots', entite: 'lot', entiteP: 'lots', module: 'M6',
      defaultSort: 'datePeremption', pageSize: 15,
      columns: [
        { key: 'numeroLot', label: 'N° lot', nowrap: true, render: function (l) { return el('span.font-mono.text-xs.font-semibold', { text: l.numeroLot }); } },
        { key: 'produit', label: 'Produit' },
        { key: 'datePeremption', label: 'Péremption', nowrap: true, text: function (l) { return C.dateFR(l.datePeremption); }, render: function (l) { return C.dateFR(l.datePeremption); } },
        {
          key: 'restant', label: 'Échéance', align: 'right',
          value: joursAvantPeremption,
          text: function (l) { return joursAvantPeremption(l) + ' j'; },
          render: function (l) {
            var j = joursAvantPeremption(l);
            if (j < 0) return U.badge('Périmé depuis ' + Math.abs(j) + ' j', 'danger');
            if (j <= 30) return U.badge('Dans ' + j + ' j', 'danger');
            if (j <= SEUIL_PEREMPTION) return U.badge('Dans ' + j + ' j', 'warning');
            return el('span.num.text-slate-600', { text: j + ' j' });
          },
        },
        { key: 'quantiteRestante', label: 'Quantité', align: 'right' },
        { key: 'emplacement', label: 'Emplacement' },
        {
          key: 'statut2', label: 'État FEFO',
          value: function (l) { return l.statut; },
          text: function (l) { return l.statut; },
          render: function (l) { return U.statut(l.statut === 'actif' ? 'normal' : l.statut); },
        },
      ],
      fields: function () {
        return [
          {
            name: 'produitId', label: 'Produit', type: 'select', required: true, col: 'full',
            options: C.sortBy(produits(), 'designation').map(function (p) { return { value: p.id, label: p.designation }; }),
          },
          { name: 'numeroLot', label: 'Numéro de lot', required: true },
          { name: 'datePeremption', label: 'Date de péremption', type: 'date', required: true },
          { name: 'quantiteRestante', label: 'Quantité restante', type: 'number', min: 0, required: true },
          { name: 'emplacement', label: 'Emplacement (rayon / casier)', col: 'full' },
        ];
      },
      transform: function (v) {
        var p = produits().filter(function (x) { return x.id === v.produitId; })[0];
        if (p) v.produit = p.designation;
        var j = C.daysBetween(AUJ, v.datePeremption);
        v.statut = j < 0 ? 'perime' : (j <= SEUIL_PEREMPTION ? 'alerte' : 'actif');
        return v;
      },
      filters: [
        {
          name: 'statut', label: 'État',
          options: [{ value: 'perime', label: 'Périmés' }, { value: 'alerte', label: 'Péremption proche' }, { value: 'actif', label: 'Valides' }],
        },
      ],
      kpis: function (rows) {
        var perimes = rows.filter(function (l) { return l.statut === 'perime'; });
        var alerte = rows.filter(function (l) { return l.statut === 'alerte'; });
        return [
          { label: 'Lots suivis', value: C.num(rows.length), icon: 'boxes', tone: 'navy' },
          { label: 'Périmés', value: C.num(perimes.length), icon: 'calendar-x', tone: 'danger', hint: C.num(C.sum(perimes, 'quantiteRestante')) + ' unités à retourner' },
          { label: 'Péremption sous ' + SEUIL_PEREMPTION + ' j', value: C.num(alerte.length), icon: 'clock', tone: 'warning', hint: 'Prioriser en sortie (FEFO)' },
          { label: 'Lots valides', value: C.num(rows.filter(function (l) { return l.statut === 'actif'; }).length), icon: 'check-circle-2', tone: 'success' },
        ];
      },
      extraTabs: [{
        id: 'fefo', label: 'Ordre de sortie FEFO',
        render: function () {
          var actifs = C.sortBy(lots().filter(function (l) { return l.quantiteRestante > 0; }), 'datePeremption');
          var wrap = el('div.space-y-3');
          wrap.appendChild(K.note('Les lots sont présentés dans l’ordre imposé par le principe FEFO : le lot dont la date de péremption est la plus proche doit être servi en premier.', { tone: 'info' }));
          wrap.appendChild(U.dataTable({
            rows: actifs, exportName: 'ordre-fefo', pageSize: 20, searchable: true,
            columns: [
              { key: 'rang', label: 'Rang', align: 'right', sortable: false, render: function (l) { return String(actifs.indexOf(l) + 1); } },
              { key: 'produit', label: 'Produit' },
              { key: 'numeroLot', label: 'N° lot', render: function (l) { return el('span.font-mono.text-xs', { text: l.numeroLot }); } },
              { key: 'datePeremption', label: 'Péremption', text: function (l) { return C.dateFR(l.datePeremption); }, render: function (l) { return C.dateFR(l.datePeremption); } },
              { key: 'quantiteRestante', label: 'Quantité', align: 'right' },
              { key: 'emplacement', label: 'Emplacement' },
            ],
          }));
          return wrap;
        },
      }],
      etat: function (l) {
        P.etat({
          titre: 'Fiche de lot',
          sousTitre: l.numeroLot + ' — ' + l.produit,
          cartouche: [['Produit', l.produit], ['N° lot', l.numeroLot],
            ['Date de péremption', C.dateFR(l.datePeremption)],
            ['Quantité restante', C.num(l.quantiteRestante)],
            ['Emplacement', l.emplacement],
            ['État', l.statut === 'perime' ? 'PÉRIMÉ' : (l.statut === 'alerte' ? 'Péremption proche' : 'Valide')]],
          contenu: el('p', { text: l.statut === 'perime'
            ? 'Ce lot est périmé. Il doit être retiré de la vente, retourné au fournisseur habilité (CAME ou SoBAPS) et la perte valorisée en comptabilité.'
            : 'Ce lot doit être servi selon le principe FEFO (premier périmé, premier sorti).' }),
          signatures: [{ role: 'Le Pharmacien', nom: 'DIEYABIDI Aïssatou' }, { role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' }],
        });
      },
    }),
    actions: function () {
      return [K.btn('État des produits périmés', {
        icon: 'printer',
        onclick: function () {
          var perimes = C.sortBy(lots().filter(function (l) { return l.statut === 'perime'; }), 'datePeremption');
          var prods = produits();
          P.etat({
            titre: 'État des produits périmés',
            sousTitre: 'Situation au ' + C.dateFR(AUJ) + ' — retour fournisseur et valorisation de la perte',
            cartouche: [['Lots concernés', C.num(perimes.length)],
              ['Unités totales', C.num(C.sum(perimes, 'quantiteRestante'))],
              ['Date d’édition', C.dateFR(AUJ)],
              ['Établi par', S.currentUser()]],
            contenu: P.tableau([
              { label: 'Produit', key: 'produit' },
              { label: 'N° lot', key: 'numeroLot' },
              { label: 'Péremption', value: function (l) { return C.dateFR(l.datePeremption); } },
              { label: 'Quantité', key: 'quantiteRestante', align: 'right' },
              {
                label: 'Valeur perdue', align: 'right',
                value: function (l) {
                  var p = prods.filter(function (x) { return x.id === l.produitId; })[0];
                  return C.money(l.quantiteRestante * (p ? p.cump : 0), false);
                },
                somme: function (l) {
                  var p = prods.filter(function (x) { return x.id === l.produitId; })[0];
                  return l.quantiteRestante * (p ? p.cump : 0);
                },
              },
              { label: 'Emplacement', key: 'emplacement' },
            ], perimes, { total: true }),
            signatures: [{ role: 'Le Pharmacien', nom: 'DIEYABIDI Aïssatou' },
              { role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })];
    },
  });

  /* ==========================================================================
   * ALERTES & SEUILS
   * ======================================================================== */
  global.SIGH.screen('m6-alertes', {
    title: 'Alertes & seuils',
    description: 'Centralisation des alertes de rupture, de seuil minimal et de péremption imminente.',
    regle: 'Écran en lecture seule. Les alertes sont <strong>recalculées en continu</strong> à partir des stocks, des seuils et des dates de péremption. Pour les faire évoluer, ajuster le seuil de l’article ou régulariser le stock.',
    render: function (root) {
      var host = el('div.space-y-4');
      var prods = produits();
      var ruptures = prods.filter(function (p) { return p.stock === 0; });
      var critiques = prods.filter(function (p) { return p.stock > 0 && p.stock <= p.seuilAlerte; });
      var perimes = lots().filter(function (l) { return l.statut === 'perime'; });
      var proches = lots().filter(function (l) { return l.statut === 'alerte'; });

      host.appendChild(U.kpiGrid([
        { label: 'Ruptures de stock', value: C.num(ruptures.length), icon: 'x-circle', tone: 'danger' },
        { label: 'Sous le seuil d’alerte', value: C.num(critiques.length), icon: 'trending-down', tone: 'warning' },
        { label: 'Lots périmés', value: C.num(perimes.length), icon: 'calendar-x', tone: 'danger' },
        { label: 'Péremption sous ' + SEUIL_PEREMPTION + ' j', value: C.num(proches.length), icon: 'clock', tone: 'warning' },
      ]));

      host.appendChild(U.tabs([
        {
          id: 'rupture', label: 'Ruptures', badge: ruptures.length,
          render: function () {
            return tableProduits(ruptures, 'Produits en rupture de stock', 'Aucune rupture de stock.');
          },
        },
        {
          id: 'seuil', label: 'Sous le seuil', badge: critiques.length,
          render: function () {
            return tableProduits(critiques, 'Produits sous le seuil d’alerte', 'Aucun produit sous le seuil.');
          },
        },
        {
          id: 'peremption', label: 'Péremptions', badge: perimes.length + proches.length,
          render: function () {
            var rows = C.sortBy(perimes.concat(proches), 'datePeremption');
            return U.dataTable({
              title: 'Lots périmés ou à péremption proche', rows: rows, exportName: 'alertes-peremption', pageSize: 15,
              emptyMessage: 'Aucune alerte de péremption.',
              columns: [
                { key: 'produit', label: 'Produit' },
                { key: 'numeroLot', label: 'N° lot', render: function (l) { return el('span.font-mono.text-xs', { text: l.numeroLot }); } },
                { key: 'datePeremption', label: 'Péremption', nowrap: true, text: function (l) { return C.dateFR(l.datePeremption); }, render: function (l) { return C.dateFR(l.datePeremption); } },
                {
                  key: 'restant', label: 'Échéance', align: 'right', value: joursAvantPeremption,
                  render: function (l) {
                    var j = joursAvantPeremption(l);
                    return j < 0 ? U.badge('Périmé', 'danger') : U.badge('Dans ' + j + ' j', j <= 30 ? 'danger' : 'warning');
                  },
                },
                { key: 'quantiteRestante', label: 'Quantité', align: 'right' },
                { key: 'emplacement', label: 'Emplacement' },
              ],
            });
          },
        },
      ]));

      host.appendChild(K.note('Le seuil d’alerte est paramétrable par article dans le référentiel produits. Le délai de préavis de péremption est de <strong>'
        + SEUIL_PEREMPTION + ' jours</strong> et se règle dans la configuration du module (RG-05).', { tone: 'info' }));

      root.appendChild(host);
      return null;

      function tableProduits(rows, titre, vide) {
        return U.dataTable({
          title: titre, rows: rows, exportName: 'alertes-stock', pageSize: 15,
          emptyMessage: vide,
          columns: [colCode, colDesignation,
            colStock('stockGros', 'Gros'), colStock('stockDetail', 'Détail'), colStock('stock', 'Total'),
            { key: 'seuilAlerte', label: 'Seuil', align: 'right' },
            {
              key: 'aCommander', label: 'À commander', align: 'right',
              value: function (p) { return Math.max(p.seuilAlerte * 2 - p.stock, 0); },
              render: function (p) { return el('span.font-semibold.text-navy-800', { text: C.num(Math.max(p.seuilAlerte * 2 - p.stock, 0)) }); },
            },
            { key: 'fournisseur', label: 'Fournisseur' },
            colEtat,
          ],
          /* Décision du 02/09/2026 : le bon de commande NE S'ÉTABLIT PLUS
             depuis les alertes — la commande suit son circuit M7 (bon
             d'expression de besoins → validation DA RG-04 → bon de
             commande), et un raccourci qui l'imprimait ici court-circuitait
             ce circuit. L'alerte SIGNALE, le circuit COMMANDE. */
          actions: [K.btn('Ouvrir les bons de besoins (M7)', {
            size: 'sm', icon: 'clipboard-list',
            onclick: function () { global.SIGH.app.go('m7-besoins'); },
          })],
        });
      }
    },
  });

  /* ==========================================================================
   * INVENTAIRE
   * ======================================================================== */
  global.SIGH.screen('m6-inventaire', {
    title: 'Inventaires',
    description: 'Inventaire mensuel et annuel : comparaison automatique entre stock physique saisi et stock théorique du système.',
    regle: 'L’inventaire remplace la comparaison manuelle actuelle : les écarts sont calculés automatiquement et valorisés au CUMP avant régularisation.',
    render: function (root) {
      var col = S.collection('inventaires', { module: 'M6', entite: 'Inventaire' });
      var host = el('div.space-y-4');
      var table;

      host.appendChild(U.kpiGrid([
        { label: 'Inventaires réalisés', value: C.num(col.active().length), icon: 'clipboard-check', tone: 'navy' },
        { label: 'Références à inventorier', value: C.num(produits().length), icon: 'package', tone: 'info' },
        { label: 'Valeur théorique', value: C.money(valeurStock(produits())), icon: 'wallet', tone: 'success' },
        { label: 'Dernier inventaire', value: col.active().length ? C.dateFR(C.sortBy(col.active(), 'date', 'desc')[0].date) : 'Aucun', icon: 'calendar-check', tone: 'neutral' },
      ]));

      table = U.dataTable({
        title: 'Historique des inventaires',
        rows: function () { return col.active(); },
        exportName: 'inventaires', pageSize: 10,
        defaultSort: 'date', defaultDir: 'desc',
        emptyMessage: 'Aucun inventaire enregistré.',
        emptyHint: 'Lancer un inventaire pour comparer le stock physique au stock théorique.',
        actions: [K.commande('Lancer un inventaire', { variant: 'primary', size: 'sm', icon: 'play', onclick: function () { lancer(); } })].filter(Boolean),
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (i) { return el('span.font-mono.text-xs', { text: i.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (i) { return C.dateFR(i.date); }, render: function (i) { return C.dateFR(i.date); } },
          { key: 'type', label: 'Type', render: function (i) { return U.badge(i.type, 'navy'); } },
          { key: 'perimetre', label: 'Périmètre' },
          { key: 'nbArticles', label: 'Articles', align: 'right' },
          { key: 'nbEcarts', label: 'Écarts', align: 'right', render: function (i) { return i.nbEcarts ? el('span.font-semibold.text-danger-600', { text: String(i.nbEcarts) }) : U.badge('Aucun', 'success'); } },
          {
            key: 'valeurEcart', label: 'Valeur des écarts', align: 'right',
            text: function (i) { return C.money(i.valeurEcart || 0, false); },
            render: function (i) {
              var v = i.valeurEcart || 0;
              return el('span', { class: v < 0 ? 'font-semibold text-danger-600' : (v > 0 ? 'font-semibold text-success-600' : ''), text: C.money(v, false) });
            },
          },
          { key: 'operateur', label: 'Réalisé par' },
          { key: 'statutInv', label: 'Statut', render: function (i) { return U.statut(i.statutInv === 'valide' ? 'valide' : 'brouillon'); } },
        ],
        onRowClick: function (i) { consulter(i); },
        rowActions: function (i) {
          return [
            K.iconBtn('eye', 'Consulter', function () { consulter(i); }),
            K.iconBtn('printer', 'Imprimer l’état', function () { etat(i); }),
          ];
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      /* ======================================================================
       * UN INVENTAIRE PORTE SUR UN MAGASIN NOMMÉ (21/09/2026)
       * ----------------------------------------------------------------------
       * Il comptait le stock TOTAL et régularisait systématiquement le stock
       * GROS. Compter les rayons de la pharmacie d’urgence faisait donc
       * apparaître un écart sur tout ce que le magasin central détenait —
       * c’est-à-dire l’essentiel — et la régularisation le retranchait au
       * mauvais endroit. Les deux stocks se comptent séparément parce qu’ils
       * se tiennent dans deux pièces différentes, et qu’on ne les compte
       * jamais le même jour.
       * ==================================================================== */
      function lancer() {
        var f = U.form([
          /* DEUX MAGASINS ET NON TROIS : un article porte `stockGros` et
             `stockDetail`, rien d'autre. Offrir « Stock laboratoire » ferait
             compter une quantité qui n'existe sur aucune fiche, et la
             régularisation retomberait sur le magasin central — l'erreur même
             qu'on vient de corriger. Les réactifs se comptent ici, dans le
             magasin qui les détient, en choisissant leur périmètre. */
          { name: 'magasin', label: 'Magasin inventorié', type: 'select', required: true, search: false,
            options: [{ value: 'gros', label: 'Stock gros (magasin central)' },
              { value: 'detail', label: 'Stock détail (pharmacie d’urgence)' }],
            help: 'Le comptage et la régularisation portent sur CE stock seulement.' },
          { name: 'type', label: 'Type d’inventaire', type: 'select', required: true, options: ['Hebdomadaire', 'Mensuel', 'Annuel', 'Tournant', 'Ponctuel'] },
          { name: 'date', label: 'Date', type: 'date', required: true, value: C.iso(AUJ) },
          {
            name: 'perimetre', label: 'Périmètre', type: 'select', required: true,
            options: ['Tous les articles'].concat(D.CATEGORIES_PRODUIT.map(function (c) { return c.label; })),
          },
          { name: 'operateur', label: 'Réalisé par', required: true, value: S.currentUser() },
        ], {});

        var m = U.modal({
          title: 'Lancer un inventaire', size: 'md', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Ouvrir la feuille de saisie', {
              variant: 'primary', icon: 'clipboard-list',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                m.close();
                /* La feuille a QUITTÉ la modale (21/09/2026) : on y compte
                   deux cents articles, un par un, la main sur le rayon. Une
                   fenêtre qu’un clic à côté referme n’est pas le bon cadre
                   pour un comptage qui dure une heure. */
                global.SIGH.app.go('m6-inventaire-feuille', {
                  magasin: v.magasin, type: v.type, date: v.date,
                  perimetre: v.perimetre, operateur: v.operateur,
                });
              },
            }),
          ],
        });
      }

      /* La feuille de comptage a QUITTÉ la modale le 21/09/2026 : elle vit
         désormais à l’écran `m6-inventaire-feuille`. La fonction locale qui
         la portait a été retirée plutôt que laissée en place — une modale
         que plus personne n’ouvre est une seconde voie de saisie qui
         divergera au premier correctif. */

      function consulter(i) {
        U.drawer({
          title: 'Inventaire ' + i.reference,
          subtitle: i.type + ' — ' + C.dateFR(i.date),
          width: 'max-w-3xl',
          body: el('div.space-y-4', null, [
            U.descList([['Référence', i.reference], ['Type', i.type], ['Périmètre', i.perimetre],
              ['Date', C.dateFR(i.date)], ['Réalisé par', i.operateur],
              ['Articles inventoriés', C.num(i.nbArticles)], ['Écarts', C.num(i.nbEcarts)],
              ['Valeur des écarts', C.money(i.valeurEcart || 0)]]),
            (i.lignes || []).filter(function (l) { return l.ecart !== 0; }).length
              ? U.card('Écarts constatés', K.miniTable([
                { label: 'Article', key: 'designation' },
                { label: 'Théorique', align: 'right', key: 'theorique' },
                { label: 'Physique', align: 'right', key: 'physique' },
                { label: 'Écart', align: 'right', render: function (l) { return el('span', { class: l.ecart < 0 ? 'font-semibold text-danger-600' : 'font-semibold text-success-600', text: (l.ecart > 0 ? '+' : '') + l.ecart }); } },
                { label: 'Valeur', align: 'right', render: function (l) { return C.money(l.valeur, false); } },
              ], (i.lignes || []).filter(function (l) { return l.ecart !== 0; })))
              : U.empty('Aucun écart constaté : stock physique conforme au stock théorique.', { icon: 'check-circle-2' }),
          ]),
          footer: [K.btn('Imprimer l’état', { variant: 'primary', icon: 'printer', onclick: function () { etat(i); } })],
        });
      }

      function etat(i) {
        P.etat({
          titre: 'État d’inventaire',
          sousTitre: i.reference + ' — ' + i.type,
          cartouche: [['Référence', i.reference], ['Type', i.type], ['Périmètre', i.perimetre],
            ['Date', C.dateFR(i.date)], ['Réalisé par', i.operateur],
            ['Valeur des écarts', C.money(i.valeurEcart || 0)]],
          contenu: P.tableau([
            { label: 'Code', key: 'code' }, { label: 'Désignation', key: 'designation' },
            { label: 'Unité', key: 'unite' },
            { label: 'Stock théorique', key: 'theorique', align: 'right' },
            { label: 'Stock physique', key: 'physique', align: 'right' },
            { label: 'Écart', align: 'right', value: function (l) { return (l.ecart > 0 ? '+' : '') + l.ecart; } },
            { label: 'Valeur écart', align: 'right', value: function (l) { return C.money(l.valeur, false); },
              somme: function (l) { return l.valeur || 0; } },
          ], i.lignes || [], { total: true }),
          signatures: [{ role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' },
            { role: 'Le Pharmacien', nom: 'DIEYABIDI Aïssatou' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * FEUILLE DE COMPTAGE — UNE PAGE, PAS UNE FENÊTRE (21-22/09/2026)
   * --------------------------------------------------------------------------
   * On y compte deux cents articles, un par un, la main sur le rayon : une
   * fenêtre qu'un clic à côté referme n'est pas le cadre d'un travail qui
   * dure une heure. La page reçoit son contexte par l'ADRESSE
   * (`#magasin=gros&type=Mensuel…`) — une modale tient son contexte de
   * l'écran qui l'ouvre, une page se charge à froid et ne sait rien.
   *
   * ELLE PORTE SUR UN MAGASIN NOMMÉ. Le stock théorique lu, l'écart calculé
   * et la régularisation écrite portent tous sur CE stock : compter les
   * rayons de la pharmacie d'urgence et régulariser le magasin central était
   * le défaut corrigé la veille, et il se rejouerait ici si la page
   * retombait sur `stock`, le total des deux.
   * ======================================================================== */
  global.SIGH.screen('m6-inventaire-feuille', {
    title: 'Feuille d’inventaire',
    description: 'Comptage physique article par article sur un magasin nommé, écarts calculés en direct et valorisés au CUMP.',
    regle: 'Le comptage porte sur <strong>un magasin nommé</strong> : le stock théorique, l’écart et la '
      + 'régularisation ne concernent que lui. La validation écrit un '
      + '<strong>mouvement de régularisation</strong> par écart (RG-03, justificatif = référence de '
      + 'l’inventaire) — le stock ne se corrige jamais sans laisser de trace, et jamais en dessous de zéro.',
    render: function (root) {
      var p = C.params();
      var col = S.collection('inventaires', { module: 'M6', entite: 'Inventaire' });
      var retour = p.retour || 'm6-inventaire';

      var entete = {
        magasin: p.magasin === 'detail' ? 'detail' : 'gros',
        type: p.type || 'Ponctuel',
        date: p.date || C.iso(AUJ),
        perimetre: p.perimetre || 'Tous les articles',
        operateur: p.operateur || S.currentUser(),
      };
      var magasinLabel = entete.magasin === 'detail'
        ? 'Stock détail (pharmacie d’urgence)' : 'Stock gros (magasin central)';

      if (!K.droits('M6').editer) {
        root.appendChild(K.note('Votre profil consulte les inventaires sans les saisir. Le comptage '
          + 'appartient au gestionnaire de stock et au pharmacien.', { tone: 'warning', icon: 'lock' }));
        root.appendChild(el('div.mt-3', null, K.btn('Revenir au registre', { icon: 'arrow-left',
          onclick: function () { global.SIGH.app.go(retour); } })));
        return;
      }

      /* Le stock du magasin compté, jamais le total des deux. */
      function theorique(pr) {
        return (entete.magasin === 'detail' ? pr.stockDetail : pr.stockGros) || 0;
      }

      var cible = entete.perimetre === 'Tous les articles'
        ? produits()
        : produits().filter(function (pr) { return categorieLabel(pr.categorie) === entete.perimetre; });
      cible = C.sortBy(cible, 'designation');

      var saisies = {};
      var host = el('div.grid.gap-4.lg\\:grid-cols-3');
      var principal = el('div.space-y-4.lg\\:col-span-2');
      var aside = el('div.space-y-4');

      /* --- Le comptage ---------------------------------------------------- */
      var recherche = el('input.input', { type: 'search', placeholder: 'Filtrer par désignation ou code…' });
      var corps = el('div.space-y-3');
      corps.appendChild(K.note('Saisir le <strong>stock physique compté</strong> pour chaque article. '
        + 'Les écarts avec le stock théorique du <strong>' + magasinLabel + '</strong> sont calculés en '
        + 'direct et valorisés au CUMP.', { tone: 'info', icon: 'clipboard-list' }));
      corps.appendChild(recherche);

      var t = el('table.tbl');
      var thead = el('thead');
      thead.appendChild(el('tr', null, [
        el('th', { text: 'Article' }), el('th.text-right', { text: 'Théorique' }),
        el('th.text-right', { text: 'Physique' }), el('th.text-right', { text: 'Écart' }),
        el('th.text-right', { text: 'Valeur' }),
      ]));
      t.appendChild(thead);
      var tb = el('tbody');

      cible.forEach(function (pr) {
        var th = theorique(pr);
        var tr = el('tr');
        tr.dataset.cle = (pr.designation + ' ' + pr.code).toLowerCase();
        tr.appendChild(el('td', null, el('div', null, [
          el('p.text-sm.text-slate-700', { text: pr.designation }),
          el('p.font-mono.text-xs.text-slate-400', { text: pr.code }),
        ])));
        tr.appendChild(el('td.text-right.num', { text: C.num(th) }));
        var input = el('input.input.w-24.text-right', { type: 'number', min: 0, value: th });
        tr.appendChild(el('td.text-right', null, input));
        var ecart = el('td.text-right.num', { text: '0' });
        var val = el('td.text-right.num', { text: C.money(0, false) });
        tr.appendChild(ecart); tr.appendChild(val);
        input.addEventListener('input', function () {
          var phys = Number(input.value) || 0;
          var e = phys - th;
          saisies[pr.id] = { produit: pr, theorique: th, physique: phys, ecart: e, valeur: e * pr.cump };
          ecart.textContent = (e > 0 ? '+' : '') + C.num(e);
          ecart.className = 'text-right num ' + (e === 0 ? '' : (e < 0 ? 'font-semibold text-danger-600' : 'font-semibold text-success-600'));
          val.textContent = C.money(e * pr.cump, false);
          majResume();
        });
        saisies[pr.id] = { produit: pr, theorique: th, physique: th, ecart: 0, valeur: 0 };
        tb.appendChild(tr);
      });
      t.appendChild(tb);

      var scroller = el('div.max-h-\\[32rem\\].overflow-y-auto.rounded-lg.border.border-slate-200');
      scroller.appendChild(t);
      corps.appendChild(scroller);

      recherche.addEventListener('input', function () {
        var q = recherche.value.trim().toLowerCase();
        Array.prototype.forEach.call(tb.children, function (tr) {
          tr.style.display = !q || tr.dataset.cle.indexOf(q) !== -1 ? '' : 'none';
        });
      });

      principal.appendChild(U.card('Comptage — ' + entete.perimetre, corps));

      /* --- L'enchaînement, et ce que la validation va écrire --------------- */
      aside.appendChild(U.card('Enchaînement du parcours', U.timeline([
        { title: 'Lancement', detail: entete.type + ' — ' + magasinLabel, date: 'Étape 1', tone: 'success' },
        { title: 'Comptage physique', detail: C.num(cible.length) + ' article(s) au périmètre « ' + entete.perimetre + ' »', date: 'Étape 2', tone: 'navy' },
        { title: 'Validation', detail: 'L’inventaire est enregistré et les écarts régularisés', date: 'Étape 3', tone: 'info' },
        { title: 'Mouvements de régularisation', detail: 'Un mouvement par écart, justificatif = n° d’inventaire (M6)', date: 'Étape 4', tone: 'warning' },
        { title: 'État d’inventaire', detail: 'Pièce signée magasinier, pharmacien et DAF', date: 'Étape 5', tone: 'neutral' },
      ])));

      var resume = el('div.space-y-3');
      aside.appendChild(U.card('Écarts constatés', resume));

      aside.appendChild(U.card('La feuille en cours', U.descList([
        ['Magasin', magasinLabel], ['Type', entete.type],
        ['Date', C.dateFR(entete.date)], ['Périmètre', entete.perimetre],
        ['Réalisé par', entete.operateur],
      ])));

      aside.appendChild(U.card('Ce que la validation écrit', el('div.space-y-3', null, [
        K.note('<strong>RG-03</strong> — chaque écart engendre un <strong>mouvement de stock</strong> '
          + 'portant la référence de l’inventaire en justificatif. Le stock ne peut pas devenir négatif.',
        { tone: 'info', icon: 'shield-check' }),
        K.note('La régularisation porte sur le <strong>magasin compté</strong> et sur lui seul.',
          { tone: 'warning', icon: 'package' }),
      ])));

      host.appendChild(principal);
      host.appendChild(aside);
      root.appendChild(host);

      root.appendChild(el('div.mt-4.flex.flex-wrap.items-center.justify-end.gap-2.border-t.border-slate-200.pt-4', null, [
        K.btn('Annuler', { icon: 'x', onclick: function () { global.SIGH.app.go(retour); } }),
        K.btn('Valider l’inventaire', { variant: 'primary', icon: 'check', onclick: valider }),
      ]));
      root.__validerInventaire = valider;

      majResume();
      return null;

      function toutes() { return Object.keys(saisies).map(function (k) { return saisies[k]; }); }

      function majResume() {
        var vals = toutes();
        var ecarts = vals.filter(function (x) { return x.ecart !== 0; });
        C.clear(resume);
        resume.appendChild(U.kpi({ label: 'Articles inventoriés', value: C.num(vals.length), icon: 'package', tone: 'navy' }));
        resume.appendChild(U.kpi({ label: 'Écarts constatés', value: C.num(ecarts.length), icon: 'triangle-alert', tone: ecarts.length ? 'warning' : 'success' }));
        resume.appendChild(U.kpi({ label: 'Valeur des écarts', value: C.money(C.sum(ecarts, 'valeur')), icon: 'wallet', tone: C.sum(ecarts, 'valeur') < 0 ? 'danger' : 'success' }));
        U.icons(resume);
      }

      function valider() {
        var vals = toutes();
        var ecarts = vals.filter(function (x) { return x.ecart !== 0; });
        var enr = {
          reference: C.nextRef('INV-', 4),
          date: entete.date, type: entete.type, perimetre: entete.perimetre,
          magasin: entete.magasin, magasinLabel: magasinLabel,
          operateur: entete.operateur, statutInv: 'valide',
          nbArticles: vals.length, nbEcarts: ecarts.length,
          valeurEcart: C.sum(ecarts, 'valeur'),
          lignes: vals.map(function (x) {
            return {
              code: x.produit.code, designation: x.produit.designation, unite: x.produit.unite,
              theorique: x.theorique, physique: x.physique, ecart: x.ecart,
              cump: x.produit.cump, valeur: x.valeur,
            };
          }),
        };
        var res = col.insert(enr);

        /* La régularisation : le magasin compté, et le total qui en découle. */
        var annulations = [];
        ecarts.forEach(function (x) {
          var pr = x.produit;
          var avant = { stockGros: pr.stockGros, stockDetail: pr.stockDetail, stock: pr.stock };
          var maj = { stock: Math.max(0, (pr.stock || 0) + x.ecart) };
          if (entete.magasin === 'detail') maj.stockDetail = Math.max(0, (pr.stockDetail || 0) + x.ecart);
          else maj.stockGros = Math.max(0, (pr.stockGros || 0) + x.ecart);
          S.collection('produits').update(pr.id, maj);
          var mv = S.collection('mouvements', { module: 'M6', entite: 'MouvementStock' }).insert({
            reference: C.nextRef('M', 6), date: entete.date,
            produitId: pr.id, produit: pr.designation,
            type: 'inventaire', typeLabel: 'Régularisation inventaire',
            quantite: Math.abs(x.ecart), stockType: entete.magasin,
            justificatif: 'Inventaire ' + enr.reference,
            utilisateur: entete.operateur,
          });
          annulations.push(function () {
            S.collection('produits').update(pr.id, avant);
            mv.undo();
          });
        });

        /* ON NE QUITTE PAS LA PAGE ICI, et c'est délibéré : l'annulation est
           une FONCTION — elle restitue les stocks et retire les mouvements —
           et une fonction ne traverse pas une navigation. Partir au registre
           afficherait un message d'où le bouton « Annuler » aurait disparu,
           juste après l'opération qui en a le plus besoin. La feuille se
           referme donc sur son résultat, et c'est l'agent qui repart. */
        U.toast('Inventaire ' + enr.reference + ' validé — ' + ecarts.length
          + ' écart(s) régularisé(s) sur le ' + magasinLabel.toLowerCase() + '.', {
          type: 'success', duration: 12000,
          undo: function () { annulations.forEach(function (u) { u(); }); res.undo(); },
        });
        C.clear(principal);
        principal.appendChild(U.card('Inventaire ' + enr.reference + ' — validé', el('div.space-y-3', null, [
          U.descList([
            ['Référence', enr.reference], ['Magasin', magasinLabel],
            ['Type', enr.type], ['Périmètre', enr.perimetre],
            ['Articles inventoriés', C.num(enr.nbArticles)],
            ['Écarts régularisés', C.num(enr.nbEcarts)],
            ['Valeur des écarts', C.money(enr.valeurEcart || 0)],
          ]),
          K.note('Les mouvements de régularisation sont écrits (RG-03). Tant que le message est '
            + 'affiché, <strong>« Annuler » revient sur l’opération entière</strong> — stocks et '
            + 'mouvements compris.', { tone: 'info', icon: 'undo-2' }),
          el('div.flex.flex-wrap.gap-2', null, [
            K.btn('Revenir au registre des inventaires', { variant: 'primary', icon: 'arrow-left',
              onclick: function () { global.SIGH.app.go(retour); } }),
          ]),
        ])));
        U.icons(principal);
      }
    },
    actions: function () {
      if (!K.droits('M6').editer) return null;
      return [K.btn('Valider l’inventaire', { variant: 'primary', size: 'sm', icon: 'check', onclick: function () {
        var c = document.getElementById('page-content');
        if (c && c.__validerInventaire) c.__validerInventaire();
      } })];
    },
  });

  /* ==========================================================================
   * PERTES, CASSES & REBUTS
   * ======================================================================== */
  global.SIGH.screen('m6-pertes', {
    title: 'Pertes, casses & rebuts',
    description: 'Traçabilité des pertes, bris de flacons, flacons vides et rebuts de stock, avec valorisation comptable de la perte.',
    regle: 'Une perte se déclare ici, mais elle s’enregistre comme un <strong>mouvement de stock</strong> — '
      + 'jamais dans un registre parallèle. <strong>RG-03</strong> : chaque sortie porte son justificatif, '
      + 'le stock décroît, et la perte apparaît aussi bien ici qu’aux mouvements parce qu’elle n’existe '
      + 'qu’une fois. Elle est <strong>valorisée au CUMP</strong> et se répercute en comptabilité.',
    render: function (root) {
      var host = el('div.space-y-4');
      var vue = el('div.space-y-4');
      root.appendChild(host);
      host.appendChild(vue);
      afficherPertes();
      return null;

      function colMouvements() {
        return S.collection('mouvements', { module: 'M6', entite: 'MouvementStock', prefix: 'MVT' });
      }

      function pertesDuStock() {
        return mouvements().filter(function (m) { return ['perte', 'casse', 'peremption'].indexOf(m.type) !== -1; });
      }

      function declarer() {
        var prods = produits();
        var f = U.form([
          {
            name: 'produitId', label: 'Article', type: 'select', required: true, col: 'full',
            options: prods.map(function (x) {
              return {
                value: x.id, label: x.designation,
                detail: 'Stock ' + C.num(x.stock != null ? x.stock : 0) + ' ' + (x.unite || '')
                  + ' — CUMP ' + C.money(x.cump, false),
              };
            }),
          },
          {
            name: 'type', label: 'Nature de la perte', type: 'select', required: true,
            options: [{ value: 'casse', label: 'Casse ou bris' },
              { value: 'peremption', label: 'Péremption' },
              { value: 'perte', label: 'Perte ou disparition' }],
          },
          { name: 'quantite', label: 'Quantité perdue', type: 'number', required: true, min: 1 },
          { name: 'date', label: 'Date du constat', type: 'date', required: true },
          {
            name: 'justificatif', label: 'Justificatif', type: 'text', required: true, col: 'full',
            hint: 'RG-03 — toute sortie porte son justificatif : n° de constat, procès-verbal, lot périmé.',
          },
          { name: 'constatePar', label: 'Constaté par', type: 'text', required: true },
          { name: 'observation', label: 'Circonstances', type: 'textarea', rows: 2, col: 'full' },
        ], { date: C.iso(AUJ), type: 'casse', quantite: 1, constatePar: S.currentUser() });

        var m = U.modal({
          title: 'Déclarer une perte', size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('La déclaration écrit un <strong>mouvement de sortie</strong> : le stock décroît d’autant, '
              + 'la perte est valorisée au CUMP et se retrouve aux « Mouvements de stock ». '
              + 'Elle n’est pas consignée dans un registre séparé — il divergerait au premier écart.',
            { tone: 'warning', icon: 'trash-2' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Déclarer la perte', {
              variant: 'danger', icon: 'trash-2',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var prod = prods.filter(function (x) { return x.id === v.produitId; })[0];
                if (!prod) return;
                var q = Number(v.quantite) || 0;
                var dispo = prod.stock != null ? prod.stock : 0;
                /* RG-03 : le stock ne peut jamais devenir négatif. Refuser en
                   NOMMANT la ligne, plutôt que de laisser passer un stock
                   impossible qu'un inventaire découvrirait des mois plus tard. */
                if (q > dispo) {
                  U.toast('Perte supérieure au stock.', {
                    type: 'error',
                    detail: prod.designation + ' — ' + C.num(dispo) + ' en stock, ' + C.num(q) + ' déclaré(s). '
                      + 'RG-03 : le stock ne peut pas devenir négatif.',
                  });
                  return;
                }
                var valeurPerte = q * (prod.cump || 0);
                var res = colMouvements().insert({
                  reference: C.nextRef('MVT-', 5),
                  date: v.date, type: v.type,
                  produitId: prod.id, produit: prod.designation, unite: prod.unite,
                  quantite: q, sens: 'sortie',
                  valeur: valeurPerte, cump: prod.cump || 0,
                  justificatif: v.justificatif, constatePar: v.constatePar,
                  observation: v.observation || null,
                  utilisateur: S.currentUser(),
                });
                S.collection('produits').update(prod.id, { stock: dispo - q });
                S.log('Déclaration de perte', 'M6', 'MouvementStock', res.record.reference,
                  { stock: dispo }, { stock: dispo - q, type: v.type, valeur: valeurPerte });
                m.close();
                afficherPertes();
                U.toast('Perte déclarée.', {
                  type: 'success', duration: 8000,
                  detail: prod.designation + ' — ' + C.num(q) + ' ' + (prod.unite || '')
                    + ', ' + C.money(valeurPerte) + ' au CUMP. Stock ramené à ' + C.num(dispo - q) + '.',
                  undo: function () {
                    res.undo();
                    S.collection('produits').update(prod.id, { stock: dispo });
                    afficherPertes();
                  },
                  undoMessage: 'Déclaration annulée — le stock est rétabli.',
                });
              },
            }),
          ],
        });
      }

      function afficherPertes() {
      C.clear(vue);
      var mvts = pertesDuStock();
      var prods = produits();
      function valeur(m) {
        if (m.valeur != null) return m.valeur;
        var p = prods.filter(function (x) { return x.id === m.produitId; })[0];
        return m.quantite * (p ? p.cump : 0);
      }

      vue.appendChild(U.kpiGrid([
        { label: 'Événements enregistrés', value: C.num(mvts.length), icon: 'trash-2', tone: 'navy' },
        { label: 'Unités perdues', value: C.num(C.sum(mvts, 'quantite')), icon: 'package-x', tone: 'danger' },
        { label: 'Valeur des pertes', value: C.money(C.sum(mvts, valeur)), icon: 'wallet', tone: 'danger', hint: 'Valorisation au CUMP' },
        { label: 'Dont péremptions', value: C.num(mvts.filter(function (m) { return m.type === 'peremption'; }).length), icon: 'calendar-x', tone: 'warning' },
      ]));

      vue.appendChild(K.note('Chaque perte est valorisée au CUMP et génère une écriture comptable au débit du compte de charges correspondant (module M12).', { tone: 'warning', icon: 'book-open-check' }));

      vue.appendChild(U.dataTable({
        title: 'Registre des pertes et casses', rows: mvts, exportName: 'pertes-casses', pageSize: 15,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [{
          name: 'type', label: 'Nature',
          options: [{ value: 'perte', label: 'Perte' }, { value: 'casse', label: 'Casse / bris' }, { value: 'peremption', label: 'Péremption' }],
        }],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (m) { return el('span.font-mono.text-xs', { text: m.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (m) { return C.dateFR(m.date); }, render: function (m) { return C.dateFR(m.date); } },
          { key: 'produit', label: 'Produit' },
          {
            key: 'type', label: 'Nature',
            render: function (m) {
              var t = D.TYPES_MOUVEMENT.filter(function (x) { return x.id === m.type; })[0];
              return U.badge(m.typeLabel, t ? t.badge : 'danger');
            },
          },
          { key: 'quantite', label: 'Quantité', align: 'right' },
          {
            key: 'valeur', label: 'Valeur perdue', align: 'right',
            value: valeur, text: function (m) { return C.money(valeur(m), false); },
            render: function (m) { return el('span.font-semibold.text-danger-600', { text: C.money(valeur(m), false) }); },
          },
          { key: 'justificatif', label: 'Justificatif (RG-03)' },
          { key: 'utilisateur', label: 'Constaté par' },
        ],
        actions: [
          K.droits('M6').editer ? K.btn('Déclarer une perte', {
            variant: 'danger', size: 'sm', icon: 'trash-2', onclick: declarer,
          }) : null,
          K.btn('Éditer le constat', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Constat de pertes et casses',
              sousTitre: 'Période cumulée — situation au ' + C.dateFR(AUJ),
              cartouche: [['Événements', C.num(mvts.length)], ['Unités perdues', C.num(C.sum(mvts, 'quantite'))],
                ['Valeur totale', C.money(C.sum(mvts, valeur))], ['Date d’édition', C.dateFR(AUJ)]],
              contenu: P.tableau([
                { label: 'Date', value: function (m) { return C.dateFR(m.date); } },
                { label: 'Produit', key: 'produit' },
                { label: 'Nature', key: 'typeLabel' },
                { label: 'Quantité', key: 'quantite', align: 'right' },
                { label: 'Valeur', align: 'right', value: function (m) { return C.money(valeur(m), false); },
                  somme: function (m) { return valeur(m); } },
                { label: 'Justificatif', key: 'justificatif' },
              ], C.sortBy(mvts, 'date', 'desc').slice(0, 60), { total: true }),
              signatures: [{ role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' },
                { role: 'Le Comptable', nom: 'KASSA Augustin' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
            });
          },
        })].filter(Boolean),
      }));
      U.icons(vue);
      }
    },
  });

  /* ==========================================================================
   * DISPENSATION
   * ======================================================================== */
  global.SIGH.screen('m6-dispensation', {
    title: 'Dispensation',
    description: 'Délivrance des médicaments aux patients : décompte du stock de détail et rattachement à la facturation.',
    regle: '<strong>Aucune dispensation manuelle</strong> (décision du 02/09/2026) : toute délivrance '
      + 'naît d’une <strong>ordonnance du médecin</strong>, passée en <strong>caisse</strong> — le '
      + 'justificatif de sortie est le numéro d’ordonnance (RG-03). Cet écran est le REGISTRE des '
      + 'délivrances faites ; le geste se fait sur la file de la pharmacie, débloquée par '
      + 'l’encaissement. <strong>RG-02</strong> — prix d’achat sans marge ; <strong>RG-05</strong> — FEFO.',
    render: function (root) {
      var col = S.collection('dispensations', { module: 'M6', entite: 'Dispensation' });
      var host = el('div.space-y-4');
      var panier = [];
      var table;

      /* --- Ce que les prescriptions ont adressé à la pharmacie ------------- */
      var file = K.fileAttente('dispensation', {
        titre: 'Ordonnances à délivrer',
        vide: 'Aucune ordonnance en attente de délivrance.',
        icon: 'pill', action: 'Délivrer',
        onAction: function (tache, refresh) { delivrer(tache, refresh); },
      });
      host.appendChild(file);

      function delivrer(tache, refresh) {
        var ord = S.collection('ordonnances').get(tache.ordonnanceId);
        if (!ord) { U.toast('Ordonnance introuvable.', { type: 'error' }); return; }
        var etat = PR.verifierStock(ord.id);
        var manque = etat.filter(function (e) { return !e.suffisant; });

        var corps = el('div.space-y-3', null, [
          U.descList([
            ['Patient', ord.patient], ['Dossier', ord.patientCode],
            ['Prescripteur', ord.medecin], ['Ordonnance', ord.numero],
            ['Règlement', ord.statutPaiement === 'soldee' ? 'Encaissé' : 'NON ENCAISSÉ'],
          ]),
          U.card('Lignes à servir', K.miniTable([
            { label: 'Produit', render: function (e) { return e.ligne.produit; } },
            { label: 'Posologie', render: function (e) { return e.ligne.posologie || '—'; } },
            { label: 'Demandé', align: 'right', render: function (e) { return String(e.ligne.quantite); } },
            { label: 'En pharmacie', align: 'right', render: function (e) { return String(e.disponible); } },
            {
              label: 'Servable', render: function (e) {
                return e.suffisant ? U.badge('Oui', 'success') : U.badge('Stock insuffisant', 'danger');
              },
            },
          ], etat)),
          manque.length
            ? K.note('<strong>RG-03</strong> — le stock ne peut pas devenir négatif. '
              + 'La délivrance est refusée tant qu’une ligne n’est pas couverte : approvisionner la pharmacie '
              + 'par un transfert depuis le magasin, puis revenir ici.', { tone: 'danger', icon: 'alert-triangle' })
            : K.note('La sortie portera le numéro d’ordonnance comme justificatif (RG-03) et sera valorisée '
              + 'au prix d’achat (RG-02).', { tone: 'info' }),
        ]);

        var m = U.modal({
          title: 'Délivrer ' + ord.numero, subtitle: ord.patient, size: 'lg', body: corps,
          footer: [
            K.btn('Fermer', { onclick: function () { m.close(); } }),
            manque.length
              ? K.btn('Aller aux transferts', { icon: 'arrow-left-right', onclick: function () { global.SIGH.app.go('m6-transferts'); } })
              : K.btn('Confirmer la délivrance', {
                variant: 'primary', icon: 'check',
                onclick: function () {
                  var res;
                  try { res = PR.delivrer(ord.id); }
                  catch (e) { U.toast('Délivrance impossible : ' + e.message, { type: 'error' }); return; }
                  m.close(); refresh();
                  if (table && table.refresh) table.refresh();
                  U.toast('Médicaments délivrés — ' + res.mouvements.length + ' sortie(s) de stock.', {
                    type: 'success', detail: 'Justificatif : ' + ord.numero,
                  });
                },
              }),
          ],
        });
      }

      host.appendChild(U.kpiGrid([
        { label: 'Dispensations enregistrées', value: C.num(col.active().length), icon: 'hand-heart', tone: 'navy' },
        { label: 'Valeur dispensée', value: C.money(C.sum(col.active(), 'montant')), icon: 'coins', tone: 'success' },
        { label: 'Références en pharmacie', value: C.num(produits().filter(function (p) { return p.stockDetail > 0; }).length), icon: 'pill', tone: 'info' },
        { label: 'Ruptures en pharmacie', value: C.num(produits().filter(function (p) { return p.stockDetail === 0; }).length), icon: 'x-circle', tone: 'danger' },
      ]));

      table = U.dataTable({
        title: 'Historique des dispensations',
        rows: function () { return col.active(); },
        exportName: 'dispensations', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        emptyMessage: 'Aucune dispensation enregistrée.',
        /* Décision du 02/09/2026 : AUCUNE dispensation manuelle — la
           délivrance naît d'une ORDONNANCE du médecin, passée en CAISSE
           (RG-03 : le justificatif est le numéro d'ordonnance). Le seul
           chemin est la file des délivrances, débloquée par l'encaissement.
           La commande de création directe est RETIRÉE, pas grisée. */
        actions: [K.btn('File des délivrances (ordonnances encaissées)', {
          size: 'sm', icon: 'list-ordered',
          onclick: function () { global.SIGH.app.go('m6-pharmacie-externe'); },
        })],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (d) { return el('span.font-mono.text-xs', { text: d.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (d) { return C.dateFR(d.date); }, render: function (d) { return C.dateFR(d.date); } },
          { key: 'patient', label: 'Patient' },
          { key: 'nbLignes', label: 'Produits', align: 'right', value: function (d) { return (d.lignes || []).length; }, render: function (d) { return String((d.lignes || []).length); } },
          {
            key: 'montant', label: 'Montant', align: 'right',
            text: function (d) { return C.money(d.montant, false); },
            render: function (d) { return C.money(d.montant, false); },
          },
          { key: 'dispensePar', label: 'Dispensé par' },
        ],
        onRowClick: function (d) {
          U.drawer({
            title: 'Dispensation ' + d.reference, subtitle: d.patient + ' — ' + C.dateFR(d.date),
            body: el('div.space-y-4', null, [
              U.descList([['Référence', d.reference], ['Patient', d.patient], ['Dossier', d.patientCode],
                ['Date', C.dateFR(d.date)], ['Dispensé par', d.dispensePar], ['Montant', C.money(d.montant)]]),
              U.card('Produits délivrés', K.miniTable([
                { label: 'Produit', key: 'produit' },
                { label: 'Quantité', align: 'right', render: function (l) { return l.quantite + ' ' + l.unite; } },
                { label: 'P.U.', align: 'right', render: function (l) { return C.money(l.prix, false); } },
                { label: 'Montant', align: 'right', render: function (l) { return C.money(l.quantite * l.prix, false); } },
              ], d.lignes || [])),
            ]),
            footer: [K.btn('Imprimer le bon', { variant: 'primary', icon: 'printer', onclick: function () { etat(d); } })],
          });
        },
        rowActions: function (d) { return [K.iconBtn('printer', 'Imprimer', function () { etat(d); })]; },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function ouvrir() {
        panier = [];
        var pats = S.collection('patients').active();
        var dispo = produits().filter(function (p) { return p.stockDetail > 0; });

        var body = el('div.space-y-4');
        var listePats = C.sortBy(pats, 'code');
        var selPatient = U.combo(listePats.map(function (p) {
          return { value: p.id, label: p.nom + ' ' + p.prenom, detail: p.code, icon: 'user' };
        }), {
          value: listePats.length ? listePats[0].id : '',
          searchPlaceholder: 'Nom, prénom ou code CNT…',
          placeholder: 'Choisir un patient',
        });
        body.appendChild(el('div', null, [el('label.label', { text: 'Patient' }), selPatient]));

        /* Ajout de ligne */
        var ligneWrap = el('div.flex.flex-wrap.items-end.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.p-3');
        var listeDispo = C.sortBy(dispo, 'designation');
        var selProduit = U.combo(listeDispo.map(function (p) {
          return {
            value: p.id, label: p.designation, icon: 'pill',
            detail: p.stockDetail + ' ' + p.unite + ' en rayon — ' + C.money(p.prixVente, false),
          };
        }), {
          value: listeDispo.length ? listeDispo[0].id : '',
          searchPlaceholder: 'Désignation ou code article…',
          placeholder: 'Choisir un produit',
        });
        var qte = el('input.input.w-24', { type: 'number', min: 1, value: 1 });
        ligneWrap.appendChild(el('div.min-w-\\[16rem\\].flex-1', null, [el('label.label', { text: 'Produit' }), selProduit]));
        ligneWrap.appendChild(el('div', null, [el('label.label', { text: 'Quantité' }), qte]));
        ligneWrap.appendChild(K.btn('Ajouter', {
          variant: 'primary', icon: 'plus',
          onclick: function () {
            var p = dispo.filter(function (x) { return x.id === selProduit.value; })[0];
            var q = Number(qte.value) || 0;
            if (!p || q <= 0) { U.toast('Sélectionner un produit et une quantité.', { type: 'error' }); return; }
            var dejaPris = C.sum(panier.filter(function (l) { return l.produitId === p.id; }), 'quantite');
            if (q + dejaPris > p.stockDetail) {
              U.toast('RG-03 — stock insuffisant en pharmacie (' + p.stockDetail + ' ' + p.unite + ' disponibles).', { type: 'error' });
              return;
            }
            panier.push({ produitId: p.id, produit: p.designation, unite: p.unite, quantite: q, prix: p.prixVente });
            qte.value = 1;
            majPanier();
          },
        }));
        body.appendChild(ligneWrap);

        var panierHost = el('div');
        body.appendChild(panierHost);

        function majPanier() {
          C.clear(panierHost);
          if (!panier.length) {
            panierHost.appendChild(U.empty('Aucun produit ajouté.', { icon: 'shopping-basket' }));
            U.icons(panierHost);
            return;
          }
          var t = el('table.tbl');
          var thead = el('thead');
          thead.appendChild(el('tr', null, [
            el('th', { text: 'Produit' }), el('th.text-right', { text: 'Qté' }),
            el('th.text-right', { text: 'P.U.' }), el('th.text-right', { text: 'Montant' }), el('th', { text: '' }),
          ]));
          t.appendChild(thead);
          var tb = el('tbody');
          panier.forEach(function (l, i) {
            tb.appendChild(el('tr', null, [
              el('td', { text: l.produit }),
              el('td.text-right.num', { text: l.quantite + ' ' + l.unite }),
              el('td.text-right.num', { text: C.money(l.prix, false) }),
              el('td.text-right.num.font-semibold', { text: C.money(l.quantite * l.prix, false) }),
              el('td.text-right', null, K.iconBtn('x', 'Retirer', function () { panier.splice(i, 1); majPanier(); }, 'ghost')),
            ]));
          });
          t.appendChild(tb);
          var tfoot = el('tfoot');
          tfoot.appendChild(el('tr', null, [
            el('td.font-semibold', { colspan: 3, text: 'TOTAL' }),
            el('td.text-right.num.text-base.font-bold.text-navy-900', { text: C.money(C.sum(panier, function (l) { return l.quantite * l.prix; }), false) }),
            el('td'),
          ]));
          t.appendChild(tfoot);
          panierHost.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));
          panierHost.appendChild(K.note('<strong>RG-02</strong> — montant calculé au prix d’achat, sans marge bénéficiaire.', { tone: 'info' }));
          U.icons(panierHost);
        }
        majPanier();

        var m = U.modal({
          title: 'Nouvelle dispensation', subtitle: 'Pharmacie d’urgence — stock de détail',
          size: 'lg', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Valider la dispensation', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                if (!panier.length) { U.toast('Ajouter au moins un produit.', { type: 'error' }); return; }
                var p = pats.filter(function (x) { return x.id === selPatient.value; })[0];
                var enr = {
                  reference: C.nextRef('DISP-', 5), date: C.iso(C.aujourdhui()),
                  patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
                  lignes: panier.slice(), montant: C.sum(panier, function (l) { return l.quantite * l.prix; }),
                  dispensePar: S.currentUser(),
                };
                var res = col.insert(enr);
                var annulations = [];
                panier.forEach(function (l) {
                  var prod = produits().filter(function (x) { return x.id === l.produitId; })[0];
                  if (!prod) return;
                  var avant = { stockDetail: prod.stockDetail, stock: prod.stock };
                  S.collection('produits').update(prod.id, {
                    stockDetail: Math.max(0, prod.stockDetail - l.quantite),
                    stock: Math.max(0, prod.stock - l.quantite),
                  });
                  var mv = S.collection('mouvements', { module: 'M6', entite: 'MouvementStock' }).insert({
                    reference: C.nextRef('M', 6), date: enr.date,
                    produitId: prod.id, produit: prod.designation,
                    type: 'sortie', typeLabel: 'Sortie', quantite: l.quantite, stockType: 'detail',
                    justificatif: 'Dispensation ' + enr.reference,
                    utilisateur: enr.dispensePar,
                  });
                  annulations.push(function () { S.collection('produits').update(prod.id, avant); mv.undo(); });
                });
                m.close(); table.refresh();
                U.toast('Dispensation ' + enr.reference + ' enregistrée — ' + C.money(enr.montant) + '.', {
                  type: 'success',
                  undo: function () { annulations.forEach(function (u) { u(); }); res.undo(); table.refresh(); },
                });
              },
            }),
          ],
        });
      }

      function etat(d) {
        P.etat({
          titre: 'Bon de sortie de stock — dispensation',
          sousTitre: d.reference,
          cartouche: [['Patient', d.patient], ['Dossier', d.patientCode], ['Date', C.dateFR(d.date)],
            ['Dispensé par', d.dispensePar], ['Référence', d.reference], ['Stock', 'Pharmacie de détail']],
          contenu: P.tableau([
            { label: 'Produit', key: 'produit' },
            { label: 'Unité', key: 'unite' },
            { label: 'Quantité', key: 'quantite', align: 'right' },
            { label: 'Prix unitaire', align: 'right', value: function (l) { return C.money(l.prix, false); } },
            {
              label: 'Montant', align: 'right',
              value: function (l) { return C.money(l.quantite * l.prix, false); },
              /* Le total est refait depuis les lignes imprimées : le bon ne
                 peut plus annoncer un montant que son propre détail ne
                 justifie pas. */
              somme: function (l) { return l.quantite * l.prix; },
            },
          ], d.lignes || [], { total: true }),
          signatures: [{ role: 'Le Pharmacien', nom: d.dispensePar }, { role: 'Le Patient', mention: 'Réception' }],
        });
      }
    },
  });

  /* ==========================================================================
   * ÉTIQUETAGE & EMPLACEMENTS
   * ======================================================================== */
  global.SIGH.screen('m6-etiquetage', {
    title: 'Étiquetage & emplacements',
    description: 'Organisation des rayons et casiers, classement par date de péremption et édition des étiquettes produits.',
    render: function (root) {
      var host = el('div.space-y-4');
      var blocPlan = el('div.space-y-4');
      var blocRef = el('div');

      root.appendChild(host);
      host.appendChild(blocRef);
      host.appendChild(blocPlan);
      rendreReferentiel();
      dessinerPlan();
      return null;

      function colEmplacements() {
        return S.collection('emplacements', { module: 'M6', entite: 'emplacement', prefix: 'EMP' });
      }

      function champsEmplacement() {
        return [
          { name: 'code', label: 'Code du casier', type: 'text', required: true,
            hint: 'Court et stable — c’est lui qui figure sur l’étiquette.' },
          { name: 'libelle', label: 'Intitulé', type: 'text', required: true, col: 'full' },
          {
            name: 'zone', label: 'Zone', type: 'select', required: true,
            options: ['Rayonnage sec', 'Chaîne du froid', 'Armoire sécurisée', 'Réserve', 'Salle de soins'],
          },
          {
            name: 'temperature', label: 'Température de conservation', type: 'select',
            options: ['Ambiante', '2 à 8 °C', '− 20 °C', 'Sous clé, ambiante'],
          },
          { name: 'capacite', label: 'Capacité (références)', type: 'number', min: 0 },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ];
      }

      function rendreReferentiel() {
        C.clear(blocRef);
        var rows = colEmplacements().active().map(function (e) {
          var n = produits().filter(function (p) { return p.emplacement === e.code; }).length;
          return Object.assign({}, e, { articles: n });
        });
        blocRef.appendChild(U.dataTable({
          title: 'Référentiel des emplacements', rows: rows, exportName: 'emplacements',
          pageSize: 15, searchable: true, defaultSort: 'code',
          emptyMessage: 'Aucun emplacement défini.',
          actions: [K.creer(colEmplacements(), champsEmplacement(), {
            module: 'M6', label: 'Nouvel emplacement', titre: 'Nouvel emplacement de rangement',
            entite: 'Emplacement',
            defauts: function () { return { zone: 'Rayonnage sec', temperature: 'Ambiante' }; },
            transform: function (v) {
              v.capacite = v.capacite === '' ? null : Number(v.capacite);
              v.source = 'Créé dans l’application le ' + C.dateFR(AUJ);
              return v;
            },
            apres: function () { rendreReferentiel(); dessinerPlan(); },
          })].filter(Boolean),
          rowActions: K.actionsLigne(colEmplacements(), champsEmplacement(), {
            module: 'M6',
            refresh: function () { rendreReferentiel(); dessinerPlan(); },
          }),
          filters: [{
            name: 'zone', label: 'Zone',
            options: ['Rayonnage sec', 'Chaîne du froid', 'Armoire sécurisée', 'Réserve', 'Salle de soins'],
          }],
          columns: [
            { key: 'code', label: 'Casier', nowrap: true, render: function (e) { return el('span.font-mono.text-sm.font-semibold.text-navy-800', { text: e.code }); } },
            { key: 'libelle', label: 'Intitulé' },
            { key: 'zone', label: 'Zone', render: function (e) { return U.badge(e.zone, e.zone === 'Chaîne du froid' ? 'info' : 'navy'); } },
            { key: 'temperature', label: 'Conservation' },
            {
              key: 'articles', label: 'Articles rangés', align: 'right',
              render: function (e) {
                if (!e.articles) return el('span.text-xs.text-slate-300', { text: 'vide' });
                var plein = e.capacite && e.articles >= e.capacite;
                return el('span', {
                  class: plein ? 'font-semibold text-warning-700' : '',
                  text: C.num(e.articles) + (e.capacite ? ' / ' + C.num(e.capacite) : ''),
                });
              },
            },
          ],
        }));
        U.icons(blocRef);
      }

      function dessinerPlan() {
      C.clear(blocPlan);
      var prods = produits();
      var parEmplacement = C.groupBy(prods, 'emplacement');

      blocPlan.appendChild(U.kpiGrid([
        { label: 'Emplacements définis', value: C.num(colEmplacements().active().length), icon: 'grid-3x3', tone: 'navy' },
        { label: 'Articles rangés', value: C.num(prods.length), icon: 'package', tone: 'info' },
        { label: 'Articles sans emplacement', value: C.num(prods.filter(function (p) { return !p.emplacement; }).length), icon: 'help-circle', tone: 'warning' },
        { label: 'Lots classés FEFO', value: C.num(lots().length), icon: 'sort-asc', tone: 'success' },
      ]));

      blocPlan.appendChild(K.note('Le rangement suit le principe <strong>FEFO</strong> : à l’intérieur de chaque casier, les lots sont classés par date de péremption croissante. '
        + 'Les sérums sont rangés par planches avec identification du type par emplacement.', { tone: 'info' }));

      /* Plan des rayons */
      var grille = el('div.grid.gap-3', { class: 'sm:grid-cols-2 lg:grid-cols-3' });
      C.sortBy(Object.keys(parEmplacement).map(function (k) { return { k: k, items: parEmplacement[k] }; }), 'k').forEach(function (x) {
        var carte = el('div.rounded-xl.border.border-slate-200.bg-white.p-3.shadow-card');
        /* `groupBy` fait de l'absence d'emplacement la CHAÎNE « undefined » : la carte s'intitulait « undefined » (écart E48, corrigé le 30/10/2026). */
        var casier = (x.k && x.k !== 'undefined') ? x.k : 'Sans emplacement';
        carte.appendChild(el('div.mb-2.flex.items-center.justify-between', null, [
          el('span.text-sm.font-semibold.text-slate-800', { text: casier }),
          U.badge(x.items.length + ' article' + (x.items.length > 1 ? 's' : ''), 'navy'),
        ]));
        var ul = el('ul.space-y-1');
        x.items.slice(0, 6).forEach(function (p) {
          ul.appendChild(el('li.flex.items-baseline.justify-between.gap-2.text-xs', null, [
            el('span.truncate.text-slate-600', { text: p.designation }),
            el('span.shrink-0.num.font-medium', { class: p.stock <= p.seuilAlerte ? 'text-danger-600' : 'text-slate-700', text: C.num(p.stock) }),
          ]));
        });
        if (x.items.length > 6) ul.appendChild(el('li.text-xs.text-slate-400', { text: '+ ' + (x.items.length - 6) + ' autre(s)' }));
        carte.appendChild(ul);
        carte.appendChild(K.btn('Étiquettes', {
          size: 'sm', icon: 'tag', onclick: function () { etiquettes(x.items, casier); },
        }));
        grille.appendChild(carte);
      });
      blocPlan.appendChild(U.card('Plan des rayons et casiers', grille));

      blocPlan.appendChild(U.dataTable({
        title: 'Articles par emplacement', rows: prods, exportName: 'emplacements', pageSize: 15,
        rowActions: K.actionsLigne(S.collection('produits', { module: 'M6', entite: 'Produit' }), [
          { name: 'designation', label: 'Désignation', required: true, col: 'full' },
          { name: 'emplacement', label: 'Emplacement (rayon / casier)', required: true },
          { name: 'unite', label: 'Unité' },
          { name: 'seuilAlerte', label: 'Seuil d’alerte', type: 'number', min: 0 },
        ], { archivable: false }),
        defaultSort: 'emplacement',
        columns: [
          { key: 'emplacement', label: 'Emplacement' },
          colCode, colDesignation,
          { key: 'unite', label: 'Unité' },
          colStock('stock', 'Stock'),
          colEtat,
        ],
        actions: [K.btn('Éditer toutes les étiquettes', { size: 'sm', icon: 'printer', onclick: function () { etiquettes(prods, 'Tous les emplacements'); } })],
      }));
      U.icons(blocPlan);
      }

      function etiquettes(items, emplacement) {
        var grille2 = el('div.grid.grid-cols-3.gap-2');
        items.forEach(function (p) {
          var lotsP = C.sortBy(lots().filter(function (l) { return l.produitId === p.id; }), 'datePeremption');
          var prochain = lotsP[0];
          var e = el('div.rounded.border.border-slate-400.p-2');
          e.appendChild(el('p.text-\\[9px\\].font-bold.uppercase.text-navy-900', { text: C.BRAND.sigle }));
          e.appendChild(el('p.mt-0\\.5.text-\\[10px\\].font-semibold.leading-tight', { text: p.designation }));
          e.appendChild(el('p.text-\\[9px\\].text-slate-600', { text: 'Code : ' + p.code }));
          e.appendChild(el('p.text-\\[9px\\].text-slate-600', { text: 'Emplacement : ' + (p.emplacement || '—') }));
          if (prochain) {
            e.appendChild(el('p.text-\\[9px\\].font-semibold.text-slate-800', { text: 'Lot : ' + prochain.numeroLot }));
            e.appendChild(el('p.text-\\[9px\\].font-semibold', { text: 'Péremption : ' + C.dateFR(prochain.datePeremption) }));
          }
          e.appendChild(el('p.mt-1.text-\\[9px\\]', { text: 'P.U. : ' + C.money(p.prixVente, false) }));
          grille2.appendChild(e);
        });
        P.etat({
          titre: 'Étiquettes produits',
          sousTitre: emplacement + ' — ' + items.length + ' étiquette(s)',
          lieuDate: false,
          contenu: grille2,
        });
      }
    },
  });

  /* ==========================================================================
   * REPRISE SAGE 100 — traçabilité du stock initial
   * ======================================================================== */
  global.SIGH.screen('m6-reprise', {
    title: 'Reprise SAGE 100',
    description: 'Traçabilité du lot de migration : inventaire « Grand Stock » repris comme situation initiale du stock.',
    regle: 'Le stock initial n’a pas été saisi manuellement : il provient de l’<strong>import de l’inventaire SAGE 100</strong>. '
      + 'Chaque article conserve sa source, son lot d’import et sa quantité d’origine, afin de distinguer les données reprises '
      + 'des mouvements opérationnels ultérieurs.',
    render: function (root) {
      /* L'écran se redessine après une valorisation : sans cela le compteur
         resterait à 32 alors que la référence vient d'être tarifée, et l'agent
         croirait sa saisie perdue. */
      dessiner();
      return null;

      function dessiner() {
      C.clear(root);
      var SG = global.SIGH.sage;
      var lot = SG.LOT_IMPORT;
      var articles = SG.INVENTAIRE_SAGE;
      var prods = produits();
      var host = el('div.space-y-4');

      var valorises = articles.filter(function (a) { return a.valorise; });
      /* « Non valorisé » veut dire : ni par le document, ni par la clinique.
         Compter ceux que le gestionnaire a déjà tarifés ferait croire que rien
         n'avance. */
      var nonValorises = articles.filter(resteSansPrix);
      var repris = articles.filter(function (a) { return !a.valorise && !resteSansPrix(a); });
      var valeurAjoutee = repris.reduce(function (t, a) {
        return t + (prixRevient(a) || 0) * a.quantite;
      }, 0);

      host.appendChild(U.kpiGrid([
        { label: 'Articles repris', value: C.num(articles.length), icon: 'package', tone: 'navy' },
        { label: 'Unités en stock', value: C.num(C.sum(articles, 'quantite')), icon: 'boxes', tone: 'info' },
        { label: 'Valeur reprise', value: C.money(C.sum(articles, 'prGlobal')), icon: 'wallet', tone: 'success', hint: 'Valorisation CMUP' },
        { label: 'Articles non valorisés', value: C.num(nonValorises.length),
          icon: 'help-circle', tone: nonValorises.length ? 'warning' : 'success',
          hint: 'Prix de revient absent du document et non saisi' },
        { label: 'Valorisés par la clinique', value: C.num(repris.length),
          icon: 'pencil-line', tone: repris.length ? 'info' : 'neutral',
          hint: repris.length ? C.money(valeurAjoutee) + ' ajoutés à la valeur du stock' : 'aucune saisie à ce jour' },
      ]));

      /* Cartouche du lot d'import */
      host.appendChild(U.card('Lot de migration', U.descList([
        ['Référence du lot', el('span.font-mono', { text: lot.reference })],
        ['Système d’origine', lot.source],
        ['Document source', lot.document],
        ['Date d’arrêté', C.dateFR(lot.dateArrete)],
        ['Date de tirage', C.dateHeure(lot.dateTirage)],
        ['Tenue de compte', lot.devise],
        ['Méthode de valorisation', lot.valorisation + ' (coût unitaire moyen pondéré)'],
        ['Total du document', C.num(lot.totalUnites) + ' unités — ' + C.money(lot.totalValorise)],
        ['Contrôle de cohérence', C.sum(articles, 'quantite') === lot.totalUnites
          ? U.badge('Quantités concordantes', 'success')
          : U.badge('Écart de ' + C.num(Math.abs(C.sum(articles, 'quantite') - lot.totalUnites)) + ' unités', 'danger')],
        ['Validation Gestionnaire de Stock', lot.valideePar ? U.badge(lot.valideePar, 'success') : U.badge('En attente', 'warning')],
      ], 'grid-cols-1 sm:grid-cols-2'), [
        /* La validation de la reprise ENGAGE le Gestionnaire de Stock et
           est journalisée : elle n'est pas offerte à qui ne fait que lire. */
        K.commande('Valider la reprise', {
          size: 'sm', variant: 'primary', icon: 'badge-check',
          onclick: function () {
            U.confirm({
              title: 'Valider la reprise du stock initial ?',
              message: 'Cette validation atteste que le contrôle physique contradictoire a été réalisé et que les '
                + C.num(articles.length) + ' articles repris correspondent au stock effectivement détenu. '
                + 'Elle engage le Gestionnaire de Stock et est journalisée.',
              confirmLabel: 'Valider la reprise',
            }).then(function (ok) {
              if (!ok) return;
              S.log('Validation', 'M6', 'LotImportStock', lot.reference, null, { valideePar: S.currentUser() });
              U.toast('Reprise validée.', { type: 'success', detail: 'Le stock initial devient la situation de référence.' });
            });
          },
        }),
        K.btn('Éditer le bordereau', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Bordereau de reprise du stock initial',
              sousTitre: 'Import ' + lot.reference + ' — ' + lot.document,
              cartouche: [
                ['Référence du lot', lot.reference],
                ['Système d’origine', lot.source],
                ['Date d’arrêté', C.dateFR(lot.dateArrete)],
                ['Articles repris', C.num(articles.length)],
                ['Unités', C.num(C.sum(articles, 'quantite'))],
                ['Valeur reprise', C.money(C.sum(articles, 'prGlobal'))],
              ],
              contenu: P.tableau([
                { label: 'Référence', key: 'code' },
                { label: 'Désignation', key: 'designation' },
                { label: 'Qté en stock', key: 'quantite', align: 'right', somme: true, formatTotal: function (v) { return C.num(v); } },
                /* On ne totalise pas un prix de revient UNITAIRE : la somme
                   de prix unitaires ne désigne aucune grandeur. */
                { label: 'P.R. unitaire', align: 'right', value: function (a) { return a.prUnitaire ? C.money(a.prUnitaire, false) : ''; } },
                {
                  label: 'P.R. global', align: 'right',
                  value: function (a) { return a.prGlobal ? C.money(a.prGlobal, false) : ''; },
                  somme: function (a) { return a.prGlobal; },
                },
              ], articles, { total: true, totalLabel: 'TOTAL GRAND STOCK' }),
              signatures: [
                { role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri', mention: 'Contrôle physique' },
                { role: 'Le Pharmacien', nom: 'DIEYABIDI Aïssatou' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou', mention: 'Validation de la reprise' },
              ],
            });
          },
        }),
      ]));

      host.appendChild(U.tabs([
        {
          id: 'articles', label: 'Articles repris', badge: articles.length,
          render: function () {
            return U.dataTable({
              rows: articles, exportName: 'reprise-sage', pageSize: 25,
              defaultSort: 'code',
              filters: [
                { name: 'categorie', label: 'Catégorie', options: optionsCategories() },
                {
                  name: 'valorise', label: 'Valorisation',
                  options: [{ value: 'oui', label: 'Valorisés' }, { value: 'non', label: 'Non valorisés' }],
                  match: function (a, v) { return v === 'oui' ? a.valorise : !a.valorise; },
                },
              ],
              columns: [
                { key: 'code', label: 'Référence SAGE', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: a.code }); } },
                { key: 'designation', label: 'Désignation' },
                {
                  key: 'categorie', label: 'Catégorie affectée',
                  text: categorieLabel,
                  render: function (a) { return U.badge(categorieLabel(a.categorie), 'navy'); },
                },
                { key: 'unite', label: 'Unité', value: function (a) { return SG.uniteDe(a.designation); }, render: function (a) { return SG.uniteDe(a.designation); } },
                { key: 'quantite', label: 'Qté reprise', align: 'right' },
                {
                  key: 'prUnitaire', label: 'P.R. unitaire (CMUP)', align: 'right',
                  text: function (a) { return a.prUnitaire ? C.money(a.prUnitaire, false) : ''; },
                  render: function (a) {
                    return a.prUnitaire
                      ? C.money(a.prUnitaire, false)
                      : U.badge('À valoriser', 'warning');
                  },
                },
                {
                  key: 'prGlobal', label: 'P.R. global', align: 'right',
                  text: function (a) { return C.money(a.prGlobal, false); },
                  render: function (a) { return el('span.font-semibold', { text: C.money(a.prGlobal, false) }); },
                },
                {
                  key: 'seuil', label: 'Seuil proposé', align: 'right',
                  value: function (a) { return SG.seuilPropose(a.quantite); },
                  render: function (a) {
                    return el('span.inline-flex.items-center.gap-1', null, [
                      el('span.num', { text: C.num(SG.seuilPropose(a.quantite)) }),
                      el('span.text-warning-500', { title: 'Absent du document — à valider' }, C.icon('help-circle', 'h-3.5 w-3.5')),
                    ]);
                  },
                },
              ],
            });
          },
        },
        {
          id: 'anomalies', label: 'Points à traiter', badge: nonValorises.length,
          render: function () {
            var wrap = el('div.space-y-3');
            var aTraiter = articles.filter(function (a) { return !a.valorise; });

            wrap.appendChild(K.note('<strong>' + aTraiter.length + ' article(s)</strong> figurent à l’inventaire SAGE '
              + 'sans prix de revient unitaire, pour ' + C.num(C.sum(aTraiter, 'quantite')) + ' unités. '
              + '<strong>Aucun document ne les tarife</strong> : le catalogue « Tarifs des médicaments » a lui aussi '
              + 'ses colonnes de prix vierges, et une seule de ces références y figure — sans montant. Les inventer '
              + 'fabriquerait une valeur de stock que personne n’a arrêtée.<br>'
              + '<strong>La saisie est donc ouverte ici</strong>, référence par référence. Elle ne modifie pas le '
              + 'document SAGE, qui continue de faire foi sur ce qu’il porte : la valorisation est enregistrée à '
              + 'part, datée et signée.', { tone: 'warning', icon: 'help-circle' }));

            wrap.appendChild(U.dataTable({
              rows: aTraiter, exportName: 'articles-non-valorises', pageSize: 20,
              filters: [{
                name: 'traite', label: 'Traitement',
                options: [{ value: 'reste', label: 'Reste à valoriser' }, { value: 'fait', label: 'Valorisé' }],
                match: function (a, v) { return v === 'fait' ? !resteSansPrix(a) : resteSansPrix(a); },
              }],
              columns: [
                { key: 'code', label: 'Référence', nowrap: true, render: function (a) { return el('span.font-mono.text-xs', { text: a.code }); } },
                { key: 'designation', label: 'Désignation' },
                { key: 'categorie', label: 'Catégorie', text: categorieLabel, render: function (a) { return U.badge(categorieLabel(a.categorie), 'navy'); } },
                { key: 'quantite', label: 'Quantité', align: 'right' },
                {
                  key: 'prixRevient', label: 'Prix de revient', align: 'right',
                  text: function (a) { var x = prixRevient(a); return x == null ? 'à saisir' : C.money(x, false); },
                  sortValue: function (a) { var x = prixRevient(a); return x == null ? -1 : x; },
                  render: function (a) {
                    var x = prixRevient(a);
                    if (x == null) return U.badge('à saisir', 'warning');
                    return el('div', null, [
                      el('span.font-semibold.text-slate-800', { text: C.money(x, false) }),
                      el('p.text-[10px].text-slate-400', { text: 'valeur : ' + C.money(x * a.quantite, false) }),
                    ]);
                  },
                },
                {
                  key: 'origine', label: 'Origine de la valeur', sortable: false,
                  render: function (a) {
                    var v = valorisationDe(a.code);
                    if (!v) return el('span.text-xs.text-slate-400', { text: 'absente du document SAGE' });
                    return el('div', null, [
                      el('p.text-xs.text-slate-600', { text: v.source || 'source non précisée' }),
                      el('p.text-[10px].text-slate-400', {
                        text: (v.auteur || 'inconnu') + ' — ' + C.dateFR(v.date),
                      }),
                    ]);
                  },
                },
              ],
              rowActions: function (a) {
                return [K.iconBtn(resteSansPrix(a) ? 'pencil-line' : 'rotate-ccw',
                  resteSansPrix(a) ? 'Valoriser' : 'Corriger la valorisation', function () {
                    saisirValorisation(a, function () { dessiner(); });
                  })];
              },
            }));
            wrap.appendChild(K.note('Le <strong>seuil d’alerte</strong> ne figure pas non plus dans le document SAGE. '
              + 'Le système propose 20 % de la quantité relevée (minimum 5 unités) ; ces valeurs doivent être arrêtées article par article '
              + 'avec le Gestionnaire de Stock et le Pharmacien avant la mise en service des alertes.', { tone: 'info' }));
            return wrap;
          },
        },
        {
          id: 'rapprochement', label: 'Rapprochement au catalogue tarifaire',
          render: function () {
            var lignes = SG.rapprochement();
            var absents = lignes.filter(function (l) { return l.correspondance === 'absente'; });
            var wrap = el('div.space-y-3');
            wrap.appendChild(U.kpiGrid([
              { label: 'Désignations au catalogue', value: C.num(lignes.length), icon: 'list', tone: 'navy' },
              { label: 'Correspondances exactes', value: C.num(lignes.filter(function (l) { return l.correspondance === 'exacte'; }).length), icon: 'check-circle-2', tone: 'success' },
              { label: 'Correspondances approchées', value: C.num(lignes.filter(function (l) { return l.correspondance === 'approchée'; }).length), icon: 'search', tone: 'info' },
              { label: 'Sans correspondance en stock', value: C.num(absents.length), icon: 'help-circle', tone: 'warning' },
            ]));
            wrap.appendChild(K.note('Le catalogue « Tarifs des médicaments et accessoires » recense les articles <strong>vendables</strong> ; '
              + 'l’inventaire SAGE recense les articles <strong>détenus</strong>. Le rapprochement ci-dessous permet d’attribuer un prix à chaque '
              + 'désignation du catalogue à partir du CMUP relevé (RG-02 — vente au prix d’achat), et de repérer les articles du catalogue absents du stock.',
              { tone: 'info' }));
            wrap.appendChild(U.dataTable({
              rows: lignes, exportName: 'rapprochement-tarifs', pageSize: 25,
              filters: [{ name: 'correspondance', label: 'Correspondance', options: ['exacte', 'approchée', 'absente'] }],
              columns: [
                { key: 'n', label: 'N°', align: 'right', nowrap: true },
                { key: 'designation', label: 'Désignation au catalogue tarifaire' },
                { key: 'article', label: 'Réf. stock', nowrap: true, render: function (l) { return l.article ? el('span.font-mono.text-xs', { text: l.article }) : el('span.text-xs.text-slate-400', { text: '—' }); } },
                { key: 'designationStock', label: 'Désignation à l’inventaire' },
                {
                  key: 'cump', label: 'Prix proposé (CMUP)', align: 'right',
                  text: function (l) { return l.cump ? C.money(l.cump, false) : ''; },
                  render: function (l) { return l.cump ? el('span.font-semibold', { text: C.money(l.cump, false) }) : U.badge('À fixer', 'warning'); },
                },
                {
                  key: 'correspondance', label: 'Correspondance',
                  render: function (l) {
                    var m = { exacte: ['Exacte', 'success'], 'approchée': ['Approchée', 'info'], absente: ['Absente', 'warning'] };
                    var x = m[l.correspondance] || ['—', 'neutral'];
                    return U.badge(x[0], x[1]);
                  },
                },
              ],
            }));
            return wrap;
          },
        },
      ]));

      host.appendChild(K.source('Inventaire « Grand Stock » — SAGE 100 Gestion commerciale 15.01, arrêté au 15/07/2026.'));
      root.appendChild(host);
      }
    },
  });

  /* ==========================================================================
   * DEUX PHARMACIES, DEUX CIRCUITS
   * --------------------------------------------------------------------------
   * La Direction a tranché le 25/08/2026 : la clinique distingue DEUX
   * ordonnances, et donc deux pharmacies.
   *
   *   - LA PHARMACIE INTERNE sert les soins d'URGENCE administrés sur place —
   *     l'injectable, la perfusion, le soluté. Le produit ne quitte pas la
   *     clinique : il est délivré à la salle de soins, qui l'administre. Il n'y
   *     a donc pas de vente au comptoir, et la sortie de stock est justifiée
   *     par une prescription de soins, non par un ticket de caisse.
   *
   *   - LA PHARMACIE EXTERNE sert les traitements par VOIE ORALE que le patient
   *     emporte. Là, il y a délivrance au comptoir, et le patient repart avec
   *     son ordonnance.
   *
   * POURQUOI DEUX ÉCRANS ET NON UN FILTRE : les deux circuits n'ont ni le même
   * justificatif de sortie, ni le même destinataire, ni le même rythme. Les
   * mélanger obligerait le dispensateur à trier lui-même, à chaque délivrance,
   * ce que le logiciel sait déjà.
   *
   * RG-03 s'applique aux deux : toute sortie porte son justificatif et le stock
   * ne devient jamais négatif.
   * ======================================================================== */
  function colOrdonnances6() {
    return S.collection('ordonnances', { module: 'M2', entite: 'ordonnance', prefix: 'ORD' });
  }

  /* La voie d'administration décide de la pharmacie. Elle est portée par la
     ligne d'ordonnance ; à défaut, la forme du produit la révèle — un
     injectable ne se prend pas par la bouche. */
  function voieDe(ligne, produit) {
    if (ligne && ligne.voie) return ligne.voie;
    var f = String((produit && (produit.forme || produit.designation)) || '').toLowerCase();
    /* « inj » : c'est ainsi que le catalogue désigne un injectable (48 désignations sur 184). Sans lui, aucun injectable n'arrivait en
       pharmacie interne — ils tombaient tous en voie orale (écart E41, corrigé le 30/10/2026). */
    if (/inject|\binj\b|amp\.|ampoule|perfus|solut|iv\b|im\b|flacon/.test(f)) return 'parenterale';
    return 'orale';
  }

  function ecranPharmacie(id, voie, titre, description, regle, note) {
    global.SIGH.screen(id, {
      title: titre, description: description, regle: regle,
      render: function (root) {
        var vue = el('div.space-y-4');
        root.appendChild(vue);
        afficher();
        return null;

        function produits6() { return S.collection('produits').active(); }
        function produitDe(id2) {
          return produits6().filter(function (x) { return x.id === id2; })[0] || null;
        }

        /* Les lignes d'ordonnance qui relèvent de CETTE pharmacie. */
        function lignes() {
          var out = [];
          colOrdonnances6().active().forEach(function (o) {
            (o.medicaments || []).forEach(function (l, i) {
              var pr = produitDe(l.produitId);
              if (voieDe(l, pr) !== voie) return;
              out.push({
                id: o.id + ':' + i, ordonnance: o, index: i, ligne: l, produit: pr,
                numero: o.numero, date: o.date, patient: o.patient, patientCode: o.patientCode,
                designation: l.produit, quantite: l.quantite, posologie: l.posologie,
                /* Les états que le parcours ÉCRIT sont « soldee » (PR.encaisser) et « servie » (PR.delivrer) : comparer à « payee » /
                   « delivree » laissait toute ordonnance réglée « Non réglée » à jamais (écart E40, corrigé le 30/10/2026). */
                paye: o.statutPaiement === 'soldee',
                delivre: o.statutDispensation === 'servie',
                stock: pr ? pr.stock : null,
                couvert: pr ? pr.stock >= l.quantite : false,
              });
            });
          });
          return out;
        }

        function afficher() {
          var ls = lignes();
          var aDelivrer = ls.filter(function (x) { return !x.delivre; });
          var bloquees = aDelivrer.filter(function (x) { return !x.paye; });
          var decouvertes = aDelivrer.filter(function (x) { return !x.couvert; });

          C.clear(vue);
          vue.appendChild(U.kpiGrid([
            { label: 'Lignes de cette pharmacie', value: C.num(ls.length), icon: 'pill', tone: 'navy' },
            { label: 'À délivrer', value: C.num(aDelivrer.length), icon: 'package-open', tone: 'info' },
            { label: 'Bloquées faute de règlement', value: C.num(bloquees.length), icon: 'lock',
              tone: bloquees.length ? 'warning' : 'success' },
            { label: 'Non couvertes par le stock', value: C.num(decouvertes.length), icon: 'triangle-alert',
              tone: decouvertes.length ? 'danger' : 'success', hint: 'RG-03 : refus nommé' },
          ]));

          vue.appendChild(K.note(note, { tone: 'info', icon: 'route' }));

          vue.appendChild(U.dataTable({
            rows: C.sortBy(aDelivrer, 'date').reverse(),
            empty: 'Aucune ligne à délivrer pour cette pharmacie.',
            columns: [
              { key: 'numero', label: 'Ordonnance' },
              { key: 'date', label: 'Date', render: function (r) { return C.dateFR(r.date); } },
              { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
              { key: 'designation', label: 'Produit' },
              { key: 'quantite', label: 'Quantité', align: 'right' },
              { key: 'posologie', label: 'Posologie' },
              { key: 'stock', label: 'Stock', align: 'right',
                render: function (r) {
                  if (r.stock == null) return el('span.text-xs.italic.text-slate-400', { text: 'produit inconnu' });
                  return el('span', { class: r.couvert ? '' : 'font-semibold text-rose-700',
                    text: C.num(r.stock) });
                } },
              { key: 'etat', label: 'État',
                render: function (r) {
                  if (!r.paye) return U.badge('Non réglée', 'warning');
                  if (!r.couvert) return U.badge('Stock insuffisant', 'danger');
                  return U.badge('Délivrable', 'success');
                } },
            ],
            rowActions: function (r) {
              if (!K.droits('M6').editer) return [];
              if (!r.paye) {
                return [K.iconBtn('lock', 'Bloquée : l’ordonnance n’est pas réglée', function () {
                  U.toast('Délivrance bloquée — l’ordonnance ' + r.numero + ' n’est pas réglée.',
                    { type: 'warning' });
                })];
              }
              return [K.btn('Délivrer', { variant: 'primary', size: 'sm', icon: 'check',
                onclick: function () { delivrer(r); } })];
            },
          }));
          U.icons(vue);
        }

        function delivrer(r) {
          /* RG-03 : le refus NOMME l'article. Un refus muet ferait chercher la
             panne du côté du logiciel. */
          if (!r.couvert) {
            U.toast('Délivrance refusée — stock insuffisant sur « ' + r.designation + ' » : '
              + C.num(r.stock) + ' en rayon pour ' + C.num(r.quantite) + ' demandé(s).',
            { type: 'error' });
            return;
          }
          U.confirm({
            title: 'Délivrer ' + r.designation + ' ?',
            message: C.num(r.quantite) + ' unité(s) sortiront du stock au titre de l’ordonnance <strong>'
              + r.numero + '</strong>' + (voie === 'parenterale'
                ? ', à destination de la <strong>salle de soins</strong> qui les administrera.'
                : ', remises au patient au comptoir.'),
            confirmLabel: 'Délivrer',
          }).then(function (ok) {
            if (!ok) return;
            var avant = r.produit.stock;
            S.collection('produits').update(r.produit.id, { stock: avant - r.quantite });
            S.collection('mouvements', { module: 'M6', entite: 'MouvementStock', prefix: 'MVT' }).insert({
              reference: C.referenceSuivante('MVT-', 5, S.collection('mouvements').all()), date: C.iso(new Date()),
              type: voie === 'parenterale' ? 'delivrance_interne' : 'delivrance_externe',
              produitId: r.produit.id, produit: r.designation,
              quantite: r.quantite, sens: 'sortie',
              valeur: r.quantite * (r.produit.prixAchat || 0),
              /* RG-03 : le justificatif est le numéro d'ordonnance. */
              justificatif: 'Ordonnance ' + r.numero,
              destination: voie === 'parenterale' ? 'Salle de soins' : 'Patient',
            });
            colOrdonnances6().update(r.ordonnance.id, { statutDispensation: 'servie' });
            /* `alerterStock` attend une LISTE d'identifiants : passer l'identifiant nu levait « forEach is not a function » APRÈS l'écriture du
               mouvement — la vue ne se rafraîchissait pas et le message de succès ne paraissait jamais (écart E44, corrigé le 30/10/2026). */
            if (PR.alerterStock) PR.alerterStock([r.produit.id], r.numero);
            afficher();
            U.toast('Délivré — stock ramené à ' + C.num(avant - r.quantite) + '.', {
              type: 'success', detail: r.designation + ' — ' + r.patient,
            });
          });
        }
      },
    });
  }

  ecranPharmacie('m6-pharmacie-interne', 'parenterale',
    'Pharmacie interne — urgences',
    'Produits administrés sur place : injectables, perfusions et solutés remis à la salle de soins.',
    'Le produit <strong>ne quitte pas la clinique</strong> : il est délivré à la salle de soins, qui '
      + 'l’administre. Il n’y a pas de vente au comptoir — la sortie de stock est justifiée par une '
      + '<strong>prescription</strong>, pas par un ticket. RG-03 s’applique : le refus nomme l’article.',
    'Cette pharmacie sert les <strong>soins d’urgence administrés sur place</strong>. Les produits partent '
      + 'vers la <strong>salle de soins</strong>, jamais vers le patient directement — c’est le personnel '
      + 'soignant qui les administre, et la traçabilité de l’administration relève de la prescription de soins.');

  ecranPharmacie('m6-pharmacie-externe', 'orale',
    'Pharmacie externe — voie orale',
    'Traitements par voie orale que le patient emporte : délivrance au comptoir sur ordonnance réglée.',
    'Le patient <strong>emporte</strong> son traitement. La délivrance suppose une ordonnance '
      + '<strong>réglée</strong> — c’est la même règle qu’au laboratoire et en salle de soins. RG-03 : toute '
      + 'sortie porte son justificatif, et le stock ne devient jamais négatif.',
    'Cette pharmacie sert les <strong>traitements par voie orale</strong> que le patient emporte. La '
      + 'distinction avec la pharmacie interne n’est pas administrative : les deux circuits n’ont ni le même '
      + 'justificatif de sortie, ni le même destinataire.');

  /* ==========================================================================
   * POINT DES VENTES — la caisse vue par le gestionnaire de stock
   * --------------------------------------------------------------------------
   * Quatorze exigences de la Direction, un seul principe : LA MÊME POPULATION
   * DE LIGNES, lue selon quatre axes — la période, le client, l'article, le
   * groupe de prestation. Écrire un écran par exigence aurait produit quatorze
   * façons de compter la même chose, qui auraient divergé au premier
   * correctif.
   *
   * POURQUOI ICI ET NON DANS M8. « m8-recettes » répond à « combien a-t-on
   * encaissé cette semaine ? » — un axe, le temps. Le gestionnaire de stock
   * demande autre chose : « combien ce client a-t-il payé », « combien de fois
   * cet article est-il sorti », « que pèse le groupe analyses ». Ce sont des
   * axes ANALYTIQUES, et les plaquer sur l'écran des recettes l'aurait rendu
   * illisible pour le caissier, qui n'en a pas besoin.
   *
   * TROIS PARTS SUR LES ÉTATS IMPRIMÉS. La Direction demande « le pourcentage
   * payé par l'assuré, par le personnel ayant bénéficié de remise ou un client
   * ayant bénéficié de remise ». Ce sont trois grandeurs distinctes et il ne
   * faut pas les confondre : la part assureur est une CRÉANCE sur un tiers, la
   * prise en charge du personnel n'en est pas une (la clinique la supporte,
   * personne ne la doit), et la remise n'est due par personne — elle diminue
   * la base.
   * ======================================================================== */
  function facturesM6() { return S.collection('factures').active(); }

  /** Toutes les lignes de la période, aplaties, chacune sachant sa pièce. */
  function lignesVendues(b) {
    var out = [];
    facturesM6().forEach(function (f) {
      if (!C.dansBornes(f.date, b)) return;
      (f.lignes || []).forEach(function (l) {
        out.push({
          date: f.date, factureId: f.id, numero: f.numero, type: f.type,
          patientId: f.patientId, patient: f.patient, patientCode: f.patientCode,
          assureur: f.assureur || null,
          agent: !!f.priseEnChargePersonnel,
          categorie: l.categorie,
          /* La LIGNE entière : c'est le secteur de l'acte qui distingue la
             maternité du reste des soins, pas sa catégorie. */
          groupe: (D.groupePrestation(l.categorie, l) || {}).id || 'autre',
          designation: l.designation,
          quantite: Number(l.quantite) || 0,
          prixUnitaire: Number(l.prixUnitaire) || 0,
          montantBrut: Number(l.montantBrut != null ? l.montantBrut : l.montant) || 0,
          remise: Number(l.remise) || 0,
          motifRemise: l.motifRemise || null,
          montant: Number(l.montant) || 0,
          partAssureur: Number(l.partAssureur) || 0,
          partPersonnel: Number(l.partPersonnel) || 0,
          partPatient: Number(l.partPatient) || 0,
          regle: l.statutPaiement === 'paye',
          montantRegle: Number(l.montantRegle) || 0,
        });
      });
    });
    return out;
  }

  /** Les cinq totaux d'un jeu de lignes. Un seul endroit qui additionne. */
  function cumuler(lignes) {
    return {
      pieces: Object.keys(C.groupBy(lignes, 'factureId')).length,
      lignes: lignes.length,
      quantite: C.sum(lignes, 'quantite'),
      brut: C.sum(lignes, 'montantBrut'),
      remise: C.sum(lignes, 'remise'),
      net: C.sum(lignes, 'montant'),
      assureur: C.sum(lignes, 'partAssureur'),
      personnel: C.sum(lignes, 'partPersonnel'),
      patient: C.sum(lignes, 'partPatient'),
      encaisse: C.sum(lignes.filter(function (l) { return l.regle; }), 'montantRegle'),
    };
  }

  /** Les trois pourcentages demandés, calculés sur le BRUT — c'est la seule
      base commune aux trois : la remise s'y compare, les parts aussi. */
  function pourcentages(t) {
    var base = t.brut || 0;
    function pc(x) { return base ? Math.round(x / base * 1000) / 10 : 0; }
    return { assureur: pc(t.assureur), personnel: pc(t.personnel), remise: pc(t.remise), patient: pc(t.patient) };
  }

  global.SIGH.screen('m6-point-ventes', {
    title: 'Suivi des ventes',
    description: 'Ventes de la caisse par période, par client, par article et par groupe de prestation, avec impression détaillée ou globale.',
    regle: 'Le point se lit selon <strong>quatre axes</strong> — période, client, article, groupe — sur '
      + '<strong>la même population de lignes</strong>. Les états imprimés portent les <strong>trois '
      + 'parts</strong> : celle de l’assureur (une créance sur un tiers), celle prise en charge par '
      + 'l’établissement pour ses agents (que personne ne doit) et la remise accordée (qui diminue la '
      + 'base). Les confondre empêcherait de répondre à la question du guichet.',
    actions: function () {
      return [
        K.btn('Point du stock', { icon: 'warehouse', onclick: function () { global.SIGH.app.go('m6-point-stock'); } }),
      ];
    },
    render: function (root) {
      /* --- Les commandes ------------------------------------------------- */
      var selPeriode = el('select.select');
      C.PERIODES.forEach(function (x) { selPeriode.appendChild(el('option', { value: x.id }, x.label)); });
      selPeriode.value = 'mois';
      var inDate = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var inDu = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, -29)) });
      var inAu = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var chkLibre = el('input.checkbox', { type: 'checkbox', id: 'pv_libre' });

      var comboClient = U.combo(optionsClients(), {
        multiple: true, placeholder: 'Tous les clients',
        search: true,
      });
      var comboGroupe = U.combo(D.GROUPES_PRESTATION.map(function (g) {
        return { value: g.id, label: g.label };
      }), { multiple: true, placeholder: 'Tous les groupes' });
      var comboArticle = U.combo(optionsArticles(), {
        multiple: true, placeholder: 'Tous les articles et prestations', search: true,
      });

      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.space-y-3', null, [
        el('div.flex.flex-wrap.items-end.gap-3', null, [
          el('div', null, [el('label.label', { text: 'Périodicité' }), selPeriode]),
          el('div', null, [el('label.label', { text: 'Arrêté au' }), inDate]),
          el('label.flex.cursor-pointer.items-center.gap-2.pb-2', { for: 'pv_libre' }, [
            chkLibre, el('span.text-xs.text-slate-600', { text: 'Plage libre' }),
          ]),
          el('div', null, [el('label.label', { text: 'Du' }), inDu]),
          el('div', null, [el('label.label', { text: 'Au' }), inAu]),
        ]),
        el('div.grid.gap-3.md\\:grid-cols-3', null, [
          el('div', null, [el('label.label', { text: 'Client (un ou plusieurs)' }), comboClient]),
          el('div', null, [el('label.label', { text: 'Groupe de prestation' }), comboGroupe]),
          el('div', null, [el('label.label', { text: 'Article / prestation' }), comboArticle]),
        ]),
        el('div.flex.flex-wrap.gap-2', null, [
          K.btn('Point détaillé', { variant: 'primary', icon: 'printer', onclick: function () { imprimer(true); } }),
          K.btn('Point global', { icon: 'printer', onclick: function () { imprimer(false); } }),
          K.btn('Point par patient', { icon: 'users', onclick: function () { imprimer('patient'); } }),
          K.btn('Réinitialiser les filtres', { icon: 'rotate-ccw', size: 'sm', onclick: reinit }),
        ]),
      ]));

      [selPeriode, inDate, inDu, inAu, chkLibre, comboClient, comboGroupe, comboArticle]
        .forEach(function (c) { c.addEventListener('change', afficher); });

      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      /* --- Les données --------------------------------------------------- */
      function optionsClients() {
        var vus = {};
        facturesM6().forEach(function (f) {
          if (f.patientId && !vus[f.patientId]) {
            vus[f.patientId] = { value: f.patientId, label: f.patient, detail: f.patientCode || '' };
          }
        });
        return C.sortBy(Object.keys(vus).map(function (k) { return vus[k]; }), 'label');
      }
      function optionsArticles() {
        var vus = {};
        facturesM6().forEach(function (f) {
          (f.lignes || []).forEach(function (l) {
            if (!l.designation || vus[l.designation]) return;
            vus[l.designation] = {
              value: l.designation, label: l.designation,
              detail: D.libelleCategorieLigne(l.categorie),
            };
          });
        });
        return C.sortBy(Object.keys(vus).map(function (k) { return vus[k]; }), 'label');
      }
      function valeurs(combo) {
        var v = combo.value;
        if (!v) return [];
        return Array.isArray(v) ? v : [v];
      }
      function bornesCourantes() {
        return chkLibre.checked ? C.bornesLibres(inDu.value, inAu.value)
          : C.bornes(selPeriode.value, inDate.value);
      }
      function filtrees() {
        var b = bornesCourantes();
        var clients = valeurs(comboClient), groupes = valeurs(comboGroupe), articles = valeurs(comboArticle);
        return lignesVendues(b).filter(function (l) {
          if (clients.length && clients.indexOf(l.patientId) < 0) return false;
          if (groupes.length && groupes.indexOf(l.groupe) < 0) return false;
          if (articles.length && articles.indexOf(l.designation) < 0) return false;
          return true;
        });
      }
      function reinit() {
        /* `U.combo` expose `value` en lecture ET en écriture ; il n'a pas de
           setValue. Le traiter comme un <select> est exactement ce pour quoi
           l'accesseur existe. */
        comboClient.value = [];
        comboGroupe.value = [];
        comboArticle.value = [];
        afficher();
      }

      /* --- L'affichage --------------------------------------------------- */
      function afficher() {
        C.clear(vue);
        var libre = chkLibre.checked;
        selPeriode.disabled = libre; inDate.disabled = libre;
        inDu.disabled = !libre; inAu.disabled = !libre;

        var b = bornesCourantes();
        var lignes = filtrees();
        var t = cumuler(lignes);
        var pc = pourcentages(t);

        vue.appendChild(K.note('<strong>' + C.libellePeriode(b) + '</strong> — ' + C.num(t.pieces)
          + ' pièce(s), ' + C.num(t.lignes) + ' ligne(s) de vente.'
          + (valeurs(comboClient).length ? ' Filtré sur ' + valeurs(comboClient).length + ' client(s).' : '')
          + (valeurs(comboGroupe).length ? ' Groupe(s) : ' + valeurs(comboGroupe).length + '.' : '')
          + (valeurs(comboArticle).length ? ' Article(s) : ' + valeurs(comboArticle).length + '.' : ''),
          { tone: 'info', icon: 'calendar-range' }));

        vue.appendChild(U.kpiGrid([
          { label: 'Facturé brut', value: C.money(t.brut), icon: 'receipt', tone: 'navy' },
          { label: 'Remises accordées', value: C.money(t.remise), icon: 'percent',
            tone: t.remise ? 'warning' : 'neutral', hint: pc.remise + ' % du brut' },
          { label: 'Facturé net', value: C.money(t.net), icon: 'wallet', tone: 'info' },
          { label: 'Part assureur', value: C.money(t.assureur), icon: 'shield',
            tone: 'info', hint: pc.assureur + ' % — créance à recouvrer' },
          { label: 'Prise en charge du personnel', value: C.money(t.personnel), icon: 'badge-check',
            tone: 'neutral', hint: pc.personnel + ' % — supportée par la clinique' },
          { label: 'Encaissé', value: C.money(t.encaisse), icon: 'coins', tone: 'success' },
          { label: 'Reste dû par les patients', value: C.money(t.patient - t.encaisse),
            icon: 'hourglass', tone: (t.patient - t.encaisse) > 0 ? 'warning' : 'success' },
          { label: 'Articles vendus', value: C.num(t.quantite), icon: 'package', tone: 'navy',
            hint: 'toutes prestations confondues' },
        ]));

        vue.appendChild(U.tabs([
          { id: 'journal', label: 'Journal des ventes', badge: t.pieces, render: function () { return ongletJournal(lignes); } },
          { id: 'clients', label: 'Par client', render: function () { return ongletClients(lignes); } },
          { id: 'patients', label: 'Par patient', badge: valeurs(comboClient).length || undefined, render: function () { return ongletPatients(lignes); } },
          { id: 'articles', label: 'Par article', render: function () { return ongletArticles(lignes); } },
          { id: 'groupes', label: 'Par groupe et famille', render: function () { return ongletGroupes(lignes); } },
          { id: 'evolution', label: 'Évolution', render: function () { return ongletEvolution(lignes, b); } },
        ]));
      }

      /* 6. PAR PATIENT — ce qui a été VENDU à chaque patient sélectionné, secteur par
            secteur : quelles analyses, quels articles, quelles consultations, quels examens
            d'imagerie médicale. C'est la désignation FACTURÉE (libellé de catalogue), jamais
            ce qui a été trouvé : un état de ventes ne porte aucune donnée médicale (RG-13).
            Le rattachement au secteur passe par la fabrique unique du référentiel
            (`D.groupePrestation`, déjà posée sur chaque ligne) — jamais une seconde règle. */
      function resteLigne(l) { return Math.max(0, l.partPatient - (l.regle ? l.montantRegle : 0)); }
      function blocsParPatient(lignes) {
        var parPatient = C.groupBy(lignes.filter(function (l) { return l.patientId; }), 'patientId');
        return C.sortBy(Object.keys(parPatient).map(function (id) {
          var g = parPatient[id], parGroupe = C.groupBy(g, 'groupe');
          return {
            id: id, patient: g[0].patient, code: g[0].patientCode, assureur: g[0].assureur,
            total: cumuler(g),
            secteurs: D.GROUPES_PRESTATION.map(function (gr) {
              var l = C.sortBy(parGroupe[gr.id] || [], 'date');
              return { groupe: gr, lignes: l, total: cumuler(l) };
            }),
          };
        }), 'patient');
      }
      function ongletPatients(lignes) {
        var choisis = valeurs(comboClient);
        var host = el('div.space-y-4');
        if (!choisis.length) {
          host.appendChild(K.note('<strong>Choisissez un ou plusieurs clients</strong> dans le filtre ci-dessus : cet onglet détaille, pour '
            + 'chacun, ce qui lui a été vendu <em>secteur par secteur</em>.', { tone: 'info', icon: 'user-search' }));
          return host;
        }
        var blocs = blocsParPatient(lignes);
        if (!blocs.length) { host.appendChild(K.note('Aucune vente sur la période pour les clients retenus.', { tone: 'warning', icon: 'inbox' })); return host; }
        blocs.forEach(function (p) {
          var carte = el('div.card');
          carte.appendChild(el('div.card-head', null, [
            el('div', null, [el('h3.text-sm.font-semibold.text-slate-900', { text: p.patient }),
              el('p.text-xs.text-slate-500', { text: (p.code || '—') + (p.assureur ? ' — assuré ' + p.assureur : ' — non assuré') })]),
            el('div.text-right', null, [el('p.text-xs.text-slate-500', { text: 'Net facturé' }), el('p.text-sm.font-semibold', { text: C.money(p.total.net) })]),
          ]));
          var corps = el('div.card-body.space-y-4');
          p.secteurs.forEach(function (sec) {
            var entete = el('div.flex.items-center.gap-2', null, [C.icon(sec.groupe.icone || 'tag', 'h-4 w-4 text-navy-600'),
              el('h4.text-sm.font-semibold.text-slate-800', { text: sec.groupe.label }),
              el('span.text-xs.text-slate-500', { text: sec.lignes.length ? sec.lignes.length + ' ligne(s) — ' + C.money(sec.total.net) : 'aucune vente' })]);
            corps.appendChild(entete);
            if (sec.lignes.length) {
              corps.appendChild(K.miniTable(['Date', 'Pièce', 'Désignation', 'Qté', 'Net', 'Part assureur', 'Payé', 'Reste dû'],
                sec.lignes.map(function (l) {
                  return [C.dateFR(l.date), l.numero, l.designation, C.num(l.quantite), C.money(l.montant, false),
                    C.money(l.partAssureur, false), C.money(l.regle ? l.montantRegle : 0, false), C.money(resteLigne(l), false)];
                })));
            }
          });
          carte.appendChild(corps);
          host.appendChild(carte);
        });
        return host;
      }
      /* Les pages imprimées : une par patient, six blocs, les secteurs vides DITS. */
      function pagesPatients(lignes) {
        var racine = el('div.space-y-4');
        var blocs = blocsParPatient(lignes);
        if (!blocs.length) { racine.appendChild(el('p', { text: 'Aucune vente sur la période pour les clients retenus.' })); return racine; }
        blocs.forEach(function (p) {
          var page = el('div.space-y-2', { style: 'page-break-before: always' });
          page.appendChild(el('h3.text-base.font-semibold', { text: 'Patient : ' + p.patient + ' (' + (p.code || '—') + ')' }));
          page.appendChild(el('p.text-xs', { text: (p.assureur ? 'Assuré ' + p.assureur : 'Non assuré') + ' — ' + p.total.lignes + ' ligne(s), net facturé '
            + C.money(p.total.net, false) + ', encaissé ' + C.money(p.total.encaisse, false) + '.' }));
          p.secteurs.forEach(function (sec) {
            page.appendChild(el('p.font-semibold.mt-2', { text: sec.groupe.label }));
            if (!sec.lignes.length) { page.appendChild(el('p.text-xs', { text: 'Aucune vente.' })); return; }
            page.appendChild(P.tableau([
              { label: 'Date', value: function (l) { return C.dateFR(l.date); } },
              { label: 'Pièce', value: function (l) { return l.numero; } },
              { label: 'Désignation', value: function (l) { return l.designation; } },
              { label: 'Qté', align: 'right', value: function (l) { return C.num(l.quantite); }, somme: function (l) { return l.quantite; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Brut', align: 'right', value: function (l) { return C.money(l.montantBrut, false); }, somme: function (l) { return l.montantBrut; } },
              { label: 'Remise', align: 'right', value: function (l) { return C.money(l.remise, false); }, somme: function (l) { return l.remise; } },
              { label: 'Part assureur', align: 'right', value: function (l) { return C.money(l.partAssureur, false); }, somme: function (l) { return l.partAssureur; } },
              { label: 'Payé', align: 'right', value: function (l) { return C.money(l.regle ? l.montantRegle : 0, false); }, somme: function (l) { return l.regle ? l.montantRegle : 0; } },
              { label: 'Reste dû', align: 'right', value: function (l) { return C.money(resteLigne(l), false); }, somme: function (l) { return resteLigne(l); } },
            ], sec.lignes, { total: true }));
          });
          racine.appendChild(page);
        });
        return racine;
      }

      /* 1. Le journal — une ligne par pièce, avec le détail des montants payés
            par chaque client. C'est la demande n° 2 de la Direction. */
      function ongletJournal(lignes) {
        var parPiece = C.groupBy(lignes, 'factureId');
        var rows = Object.keys(parPiece).map(function (k) {
          var g = parPiece[k], t = cumuler(g), p2 = pourcentages(t);
          return {
            id: k, numero: g[0].numero, date: g[0].date, patient: g[0].patient,
            code: g[0].patientCode, type: g[0].type,
            assureur: g[0].assureur, agent: g[0].agent,
            nbLignes: g.length,
            brut: t.brut, remise: t.remise, net: t.net,
            assureurM: t.assureur, personnelM: t.personnel, patientM: t.patient,
            encaisse: t.encaisse, reste: t.patient - t.encaisse,
            pcAssureur: p2.assureur, pcPersonnel: p2.personnel, pcRemise: p2.remise,
          };
        });
        return U.dataTable({
          rows: C.sortBy(rows, 'date', 'desc'), exportName: 'point-ventes-journal', pageSize: 20, searchable: true,
          columns: [
            { key: 'numero', label: 'Pièce', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.numero }); } },
            { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
            { key: 'patient', label: 'Client', render: function (r) {
              return el('div', null, [
                el('p.font-medium', { text: r.patient }),
                el('p.text-[10px].text-slate-400', { text: r.code || '' }),
              ]);
            } },
            { key: 'nbLignes', label: 'Lignes', align: 'right' },
            { key: 'brut', label: 'Brut', align: 'right', text: function (r) { return C.money(r.brut, false); }, render: function (r) { return C.money(r.brut, false); } },
            { key: 'remise', label: 'Remise', align: 'right',
              text: function (r) { return r.remise ? C.money(r.remise, false) + ' (' + r.pcRemise + ' %)' : '—'; },
              render: function (r) {
                if (!r.remise) return el('span.text-slate-300', { text: '—' });
                return el('div', null, [
                  el('span.text-warning-700', { text: C.money(r.remise, false) }),
                  el('p.text-[10px].text-slate-400', { text: r.pcRemise + ' %' }),
                ]);
              } },
            { key: 'assureurM', label: 'Part assureur', align: 'right',
              text: function (r) { return r.assureurM ? C.money(r.assureurM, false) + ' (' + r.pcAssureur + ' %)' : '—'; },
              render: function (r) {
                if (!r.assureurM) return el('span.text-slate-300', { text: '—' });
                return el('div', null, [
                  el('span.text-info-700', { text: C.money(r.assureurM, false) }),
                  el('p.text-[10px].text-slate-400', { text: r.pcAssureur + ' % · ' + (r.assureur || '') }),
                ]);
              } },
            { key: 'personnelM', label: 'Personnel', align: 'right',
              text: function (r) { return r.personnelM ? C.money(r.personnelM, false) + ' (' + r.pcPersonnel + ' %)' : '—'; },
              render: function (r) {
                if (!r.personnelM) return el('span.text-slate-300', { text: '—' });
                return el('div', null, [
                  el('span.text-slate-700', { text: C.money(r.personnelM, false) }),
                  el('p.text-[10px].text-slate-400', { text: r.pcPersonnel + ' % — agent' }),
                ]);
              } },
            { key: 'encaisse', label: 'Payé', align: 'right',
              text: function (r) { return C.money(r.encaisse, false); },
              render: function (r) { return el('span.font-semibold.text-success-700', { text: C.money(r.encaisse, false) }); } },
            { key: 'reste', label: 'Reste dû', align: 'right',
              text: function (r) { return C.money(r.reste, false); },
              render: function (r) {
                return r.reste > 0 ? el('span.font-semibold.text-danger-600', { text: C.money(r.reste, false) })
                  : el('span.text-slate-300', { text: '—' });
              } },
          ],
        });
      }

      /* 2. Par client — le point de caisse « pour un client choisi ». */
      function ongletClients(lignes) {
        var parClient = C.groupBy(lignes, 'patientId');
        var rows = Object.keys(parClient).map(function (k) {
          var g = parClient[k], t = cumuler(g), p2 = pourcentages(t);
          return {
            id: k, patient: g[0].patient, code: g[0].patientCode,
            assureur: g[0].assureur, agent: g[0].agent,
            pieces: t.pieces, quantite: t.quantite,
            brut: t.brut, remise: t.remise, net: t.net,
            assureurM: t.assureur, personnelM: t.personnel,
            encaisse: t.encaisse, reste: t.patient - t.encaisse,
            pcAssureur: p2.assureur, pcPersonnel: p2.personnel, pcRemise: p2.remise,
          };
        });
        return U.dataTable({
          rows: C.sortBy(rows, 'net', 'desc'), exportName: 'point-ventes-clients', pageSize: 20, searchable: true,
          columns: [
            { key: 'patient', label: 'Client', render: function (r) {
              return el('div', null, [
                el('p.font-medium', { text: r.patient }),
                el('p.text-[10px].text-slate-400', { text: (r.code || '') + (r.agent ? ' · agent de la clinique' : (r.assureur ? ' · ' + r.assureur : '')) }),
              ]);
            } },
            { key: 'pieces', label: 'Pièces', align: 'right' },
            { key: 'quantite', label: 'Quantité', align: 'right' },
            { key: 'brut', label: 'Brut', align: 'right', text: function (r) { return C.money(r.brut, false); }, render: function (r) { return C.money(r.brut, false); } },
            { key: 'remise', label: 'Remise', align: 'right',
              text: function (r) { return r.pcRemise + ' %'; },
              render: function (r) {
                return r.remise ? el('div', null, [
                  el('span.text-warning-700', { text: C.money(r.remise, false) }),
                  el('p.text-[10px].text-slate-400', { text: r.pcRemise + ' %' }),
                ]) : el('span.text-slate-300', { text: '—' });
              } },
            { key: 'assureurM', label: 'Assureur', align: 'right',
              text: function (r) { return r.pcAssureur + ' %'; },
              render: function (r) {
                return r.assureurM ? el('div', null, [
                  el('span.text-info-700', { text: C.money(r.assureurM, false) }),
                  el('p.text-[10px].text-slate-400', { text: r.pcAssureur + ' %' }),
                ]) : el('span.text-slate-300', { text: '—' });
              } },
            { key: 'personnelM', label: 'Personnel', align: 'right',
              text: function (r) { return r.pcPersonnel + ' %'; },
              render: function (r) {
                return r.personnelM ? el('div', null, [
                  el('span.text-slate-700', { text: C.money(r.personnelM, false) }),
                  el('p.text-[10px].text-slate-400', { text: r.pcPersonnel + ' %' }),
                ]) : el('span.text-slate-300', { text: '—' });
              } },
            { key: 'encaisse', label: 'Payé', align: 'right',
              text: function (r) { return C.money(r.encaisse, false); },
              render: function (r) { return el('span.font-semibold.text-success-700', { text: C.money(r.encaisse, false) }); } },
            { key: 'reste', label: 'Reste dû', align: 'right',
              text: function (r) { return C.money(r.reste, false); },
              render: function (r) {
                return r.reste > 0 ? el('span.font-semibold.text-danger-600', { text: C.money(r.reste, false) })
                  : el('span.text-slate-300', { text: '—' });
              } },
          ],
        });
      }

      /* 3. Par article — « totaliser le nombre d'un article vendu ». La
            QUANTITÉ est la première colonne : c'est la question posée. */
      function ongletArticles(lignes) {
        var parArticle = C.groupBy(lignes, 'designation');
        var rows = Object.keys(parArticle).map(function (k) {
          var g = parArticle[k], t = cumuler(g);
          return {
            id: k, designation: k,
            categorie: D.libelleCategorieLigne(g[0].categorie),
            groupe: (D.GROUPES_PRESTATION.filter(function (x) { return x.id === g[0].groupe; })[0] || {}).label || '—',
            quantite: t.quantite, pieces: t.pieces, clients: Object.keys(C.groupBy(g, 'patientId')).length,
            pu: g[0].prixUnitaire, brut: t.brut, remise: t.remise, net: t.net, encaisse: t.encaisse,
          };
        });
        return U.dataTable({
          rows: C.sortBy(rows, 'quantite', 'desc'), exportName: 'point-ventes-articles', pageSize: 25, searchable: true,
          filters: [{ name: 'groupe', label: 'Groupe', options: D.GROUPES_PRESTATION.map(function (g) { return g.label; }) }],
          columns: [
            { key: 'quantite', label: 'Quantité vendue', align: 'right',
              render: function (r) { return el('span.font-bold.text-navy-800', { text: C.num(r.quantite) }); } },
            { key: 'designation', label: 'Article / prestation' },
            { key: 'categorie', label: 'Catégorie', render: function (r) { return U.badge(r.categorie, 'navy'); } },
            { key: 'groupe', label: 'Groupe' },
            { key: 'clients', label: 'Clients', align: 'right' },
            { key: 'pieces', label: 'Pièces', align: 'right' },
            { key: 'pu', label: 'P.U.', align: 'right', text: function (r) { return C.money(r.pu, false); }, render: function (r) { return C.money(r.pu, false); } },
            { key: 'brut', label: 'Brut', align: 'right', text: function (r) { return C.money(r.brut, false); }, render: function (r) { return C.money(r.brut, false); } },
            { key: 'net', label: 'Net facturé', align: 'right',
              text: function (r) { return C.money(r.net, false); },
              render: function (r) { return el('span.font-semibold', { text: C.money(r.net, false) }); } },
            { key: 'encaisse', label: 'Encaissé', align: 'right',
              text: function (r) { return C.money(r.encaisse, false); },
              render: function (r) { return el('span.text-success-700', { text: C.money(r.encaisse, false) }); } },
          ],
        });
      }

      /* 4. Par groupe et par famille de catégorie. */
      function ongletGroupes(lignes) {
        var wrap = el('div.space-y-4');

        var parGroupe = C.groupBy(lignes, 'groupe');
        var rowsG = D.GROUPES_PRESTATION.map(function (g) {
          var t = cumuler(parGroupe[g.id] || []);
          return { id: g.id, groupe: g.label, quantite: t.quantite, pieces: t.pieces,
            brut: t.brut, remise: t.remise, net: t.net, encaisse: t.encaisse };
        }).filter(function (r) { return r.net || r.quantite; });

        wrap.appendChild(U.card('Par groupe de prestation', U.dataTable({
          rows: rowsG, exportName: 'point-ventes-groupes', pageSize: 10, searchable: false,
          columns: [
            { key: 'groupe', label: 'Groupe' },
            { key: 'quantite', label: 'Quantité', align: 'right' },
            { key: 'pieces', label: 'Pièces', align: 'right' },
            { key: 'brut', label: 'Brut', align: 'right', text: function (r) { return C.money(r.brut, false); }, render: function (r) { return C.money(r.brut, false); } },
            { key: 'remise', label: 'Remise', align: 'right', text: function (r) { return C.money(r.remise, false); }, render: function (r) { return C.money(r.remise, false); } },
            { key: 'net', label: 'Net', align: 'right', text: function (r) { return C.money(r.net, false); },
              render: function (r) { return el('span.font-semibold', { text: C.money(r.net, false) }); } },
            { key: 'encaisse', label: 'Encaissé', align: 'right', text: function (r) { return C.money(r.encaisse, false); },
              render: function (r) { return el('span.text-success-700', { text: C.money(r.encaisse, false) }); } },
          ],
        })));

        var parCat = C.groupBy(lignes, 'categorie');
        var rowsC = D.CATEGORIES_LIGNE.map(function (c) {
          var t = cumuler(parCat[c.id] || []);
          return { id: c.id, categorie: c.label, quantite: t.quantite, net: t.net, encaisse: t.encaisse };
        }).filter(function (r) { return r.net || r.quantite; });

        wrap.appendChild(U.card('Par catégorie de prestation', U.dataTable({
          rows: rowsC, exportName: 'point-ventes-categories', pageSize: 10, searchable: false,
          columns: [
            { key: 'categorie', label: 'Catégorie' },
            { key: 'quantite', label: 'Quantité', align: 'right' },
            { key: 'net', label: 'Net facturé', align: 'right', text: function (r) { return C.money(r.net, false); }, render: function (r) { return C.money(r.net, false); } },
            { key: 'encaisse', label: 'Encaissé', align: 'right', text: function (r) { return C.money(r.encaisse, false); }, render: function (r) { return C.money(r.encaisse, false); } },
          ],
        })));

        if (rowsG.length) {
          wrap.appendChild(K.charts([{
            title: 'Poids des groupes dans le chiffre net',
            render: function () {
              return G.anneau(rowsG.map(function (r) { return r.groupe; }),
                rowsG.map(function (r) { return r.net; }));
            },
          }]));
        }
        return wrap;
      }

      /* 5. L'évolution — le pas de découpage suit l'étendue demandée. */
      function ongletEvolution(lignes, b) {
        var parJour = b.jours <= 62;
        var cles = {}, ordre = [];
        lignes.forEach(function (l) {
          var d = C.toDate(l.date);
          var k = parJour ? C.iso(d) : (d.getFullYear() + '-' + C.pad(d.getMonth() + 1));
          if (!cles[k]) { cles[k] = []; ordre.push(k); }
          cles[k].push(l);
        });
        ordre.sort();
        if (!ordre.length) return U.empty('Aucune vente sur la période retenue.', { icon: 'chart-column' });

        var labels = ordre.map(function (k) {
          return parJour ? C.dateFR(k).slice(0, 5) : (C.MOIS[Number(k.split('-')[1]) - 1] || k).slice(0, 4) + ' ' + k.slice(2, 4);
        });
        return K.charts([{
          title: parJour ? 'Ventes par jour' : 'Ventes par mois',
          render: function () {
            return G.barres(labels, [
              { label: 'Net facturé', data: ordre.map(function (k) { return cumuler(cles[k]).net; }), color: G.TONES.navy },
              { label: 'Encaissé', data: ordre.map(function (k) { return cumuler(cles[k]).encaisse; }), color: G.TONES.vert },
            ]);
          },
        }]);
      }

      /* --- L'impression -------------------------------------------------- */
      function imprimer(detaille) {
        var b = bornesCourantes();
        var lignes = filtrees();
        var t = cumuler(lignes);
        var pc = pourcentages(t);

        var contenu = el('div.space-y-3');

        if (detaille === 'patient') {
          contenu.appendChild(pagesPatients(lignes));
        } else if (detaille) {
          /* Le point DÉTAILLÉ : une ligne par pièce, avec le détail des
             montants payés par chaque client — demande n° 2. */
          var parPiece = C.groupBy(lignes, 'factureId');
          var rows = C.sortBy(Object.keys(parPiece).map(function (k) {
            var g = parPiece[k], tt = cumuler(g), pp = pourcentages(tt);
            return {
              date: C.dateFR(g[0].date), numero: g[0].numero, client: g[0].patient,
              brut: tt.brut, remise: tt.remise, assureur: tt.assureur,
              personnel: tt.personnel, paye: tt.encaisse, reste: tt.patient - tt.encaisse,
              pcRemise: pp.remise, pcAssureur: pp.assureur, pcPersonnel: pp.personnel,
            };
          }), 'date');
          /* La cellule imprime son texte, la colonne sait rendre son nombre :
             c'est ce couple qui laisse le pied totaliser ce qui est REELLEMENT
             imprimé, sans que l'appelant fournisse un total. */
          function colMontant(label, champ) {
            return {
              label: label, align: 'right',
              value: function (r) { return C.money(r[champ], false); },
              somme: function (r) { return r[champ]; },
            };
          }
          contenu.appendChild(P.tableau([
            { label: 'Date', value: function (r) { return r.date; } },
            { label: 'Pièce', value: function (r) { return r.numero; } },
            { label: 'Client', value: function (r) { return r.client; } },
            colMontant('Brut', 'brut'),
            colMontant('Remise', 'remise'),
            { label: '% remise', align: 'right', value: function (r) { return r.pcRemise + ' %'; } },
            colMontant('Part assureur', 'assureur'),
            { label: '% assureur', align: 'right', value: function (r) { return r.pcAssureur + ' %'; } },
            colMontant('Personnel', 'personnel'),
            { label: '% personnel', align: 'right', value: function (r) { return r.pcPersonnel + ' %'; } },
            colMontant('Payé', 'paye'),
            colMontant('Reste dû', 'reste'),
          ], rows, { total: true }));
        } else {
          /* Le point GLOBAL : les groupes, puis la synthèse. */
          var parGroupe = C.groupBy(lignes, 'groupe');
          var rowsG = D.GROUPES_PRESTATION.map(function (g) {
            var tt = cumuler(parGroupe[g.id] || []);
            return { groupe: g.label, quantite: tt.quantite, brut: tt.brut,
              remise: tt.remise, net: tt.net, paye: tt.encaisse };
          }).filter(function (r) { return r.net || r.quantite; });
          contenu.appendChild(P.tableau([
            { label: 'Groupe de prestation', value: function (r) { return r.groupe; } },
            /* Une quantité ne se formate pas comme un montant : son total
               passe par formatTotal, sans quoi le pied afficherait des FCFA
               sous une colonne de comptes. */
            { label: 'Quantité', align: 'right',
              value: function (r) { return C.num(r.quantite); },
              somme: function (r) { return r.quantite; },
              formatTotal: function (v) { return C.num(v); } },
            { label: 'Brut', align: 'right',
              value: function (r) { return C.money(r.brut, false); },
              somme: function (r) { return r.brut; } },
            { label: 'Remise', align: 'right',
              value: function (r) { return C.money(r.remise, false); },
              somme: function (r) { return r.remise; } },
            { label: 'Net facturé', align: 'right',
              value: function (r) { return C.money(r.net, false); },
              somme: function (r) { return r.net; } },
            { label: 'Encaissé', align: 'right',
              value: function (r) { return C.money(r.paye, false); },
              somme: function (r) { return r.paye; } },
          ], rowsG, { total: true }));
        }

        /* Les trois pourcentages, énoncés en toutes lettres sous le tableau :
           c'est la demande explicite de la Direction, et un pourcentage perdu
           dans une colonne se lit moins bien qu'une phrase. */
        contenu.appendChild(el('div.mt-4.space-y-1', null, [
          el('p.font-semibold', { text: 'Répartition de la charge' }),
          el('p', { text: 'Part réglée par les assureurs : ' + C.money(t.assureur, false)
            + ' — ' + pc.assureur + ' % du brut facturé. Cette part est une créance : elle se recouvre.' }),
          el('p', { text: 'Part prise en charge par la clinique pour ses agents : ' + C.money(t.personnel, false)
            + ' — ' + pc.personnel + ' % du brut. Aucun tiers ne la doit ; elle ne remonte ni aux recettes '
            + 'ni à la comptabilité.' }),
          el('p', { text: 'Remises accordées aux clients : ' + C.money(t.remise, false)
            + ' — ' + pc.remise + ' % du brut. Une remise diminue la base facturée ; elle n’est due par personne.' }),
          el('p', { text: 'Reste à la charge des patients : ' + C.money(t.patient, false)
            + ' — ' + pc.patient + ' %, dont ' + C.money(t.encaisse, false) + ' déjà encaissés et '
            + C.money(t.patient - t.encaisse, false) + ' encore dus.' }),
        ]));

        /* Le point GLOBAL avec des clients retenus : le récapitulatif reste la première page, les pages patient suivent. */
        if (detaille === false && valeurs(comboClient).length) contenu.appendChild(pagesPatients(lignes));

        P.etat({
          titre: detaille === 'patient' ? 'Point des ventes par patient' : (detaille ? 'Point détaillé des ventes' : 'Point global des ventes'),
          sousTitre: C.libellePeriode(b),
          cartouche: [
            ['Période', C.libellePeriode(b)],
            ['Pièces', C.num(t.pieces)],
            ['Lignes de vente', C.num(t.lignes)],
            ['Quantité totale', C.num(t.quantite)],
            ['Clients retenus', valeurs(comboClient).length ? C.num(valeurs(comboClient).length) : 'tous'],
            ['Groupes retenus', valeurs(comboGroupe).length ? C.num(valeurs(comboGroupe).length) : 'tous'],
            ['Articles retenus', valeurs(comboArticle).length ? C.num(valeurs(comboArticle).length) : 'tous'],
            ['Brut facturé', C.money(t.brut)],
          ],
          contenu: contenu,
          signatures: [{ role: 'Le Gestionnaire de Stock' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * POINT DU STOCK VALORISÉ
   * --------------------------------------------------------------------------
   * Cinq vues demandées, et le même mot les commande toutes : « ET LEUR
   * MONTANT ». Un état de stock qui donne des quantités sans valeur ne se
   * rapproche d'aucune écriture — c'est ce qui oblige à recompter à la main
   * avant chaque arrêté.
   *
   *   1. le stock RESTANT à la pharmacie        (état à date)
   *   2. le stock REÇU par la pharmacie          (flux : transferts entrants)
   *   3. le stock NOUVEAU enregistré au magasin  (flux : entrées fournisseur)
   *   4. le stock SORTI par le magasin           (flux : sorties et transferts)
   *   5. le stock RESTANT au magasin             (état à date)
   *
   * DEUX NATURES, ET IL NE FAUT PAS LES MÉLANGER : un ÉTAT se lit à une date,
   * un FLUX se lit sur une période. Les afficher sous le même filtre sans le
   * dire ferait croire que le stock restant dépend de la période choisie.
   *
   * LA VALORISATION SUIT LE PARAMÈTRE DE LA CLINIQUE — prix de vente ou CUMP,
   * comme l'annotation manuscrite le demandait. Chaque ligne porte les DEUX,
   * faute de quoi changer de méthode rendrait l'historique incomparable.
   * ======================================================================== */
  var VUES_STOCK = [
    { id: 'pharmacie_restant', label: 'Stock restant à la pharmacie', nature: 'etat', icone: 'store' },
    { id: 'pharmacie_recu', label: 'Stock reçu par la pharmacie', nature: 'flux', icone: 'download' },
    { id: 'magasin_nouveau', label: 'Stock nouveau enregistré au magasin', nature: 'flux', icone: 'package-plus' },
    { id: 'magasin_sorti', label: 'Stock sorti par le magasin', nature: 'flux', icone: 'package-minus' },
    { id: 'magasin_restant', label: 'Stock restant au magasin', nature: 'etat', icone: 'warehouse' },
  ];

  global.SIGH.screen('m6-point-stock', {
    title: 'Point du stock valorisé',
    description: 'Stock restant, reçu, entré et sorti — au magasin et à la pharmacie — avec sa valeur en francs.',
    regle: 'Chaque vue porte <strong>sa quantité ET son montant</strong> : un état de stock sans valeur ne se '
      + 'rapproche d’aucune écriture. Un <strong>état</strong> se lit à une date (ce qui reste), un '
      + '<strong>flux</strong> se lit sur une période (ce qui est entré ou sorti) — les confondre ferait '
      + 'croire que le stock restant dépend de la période choisie.',
    actions: function () {
      return [
        K.btn('Point des ventes', { icon: 'coins', onclick: function () { global.SIGH.app.go('m6-point-ventes'); } }),
      ];
    },
    render: function (root) {
      var selVue = el('select.select');
      VUES_STOCK.forEach(function (v) { selVue.appendChild(el('option', { value: v.id }, v.label)); });
      var selPeriode = el('select.select');
      C.PERIODES.forEach(function (x) { selPeriode.appendChild(el('option', { value: x.id }, x.label)); });
      selPeriode.value = 'mois';
      var inDate = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var comboFamille = U.combo(D.FAMILLES_ARTICLES.map(function (f) {
        return { value: f.id, label: f.label };
      }), { multiple: true, placeholder: 'Toutes les familles' });

      var vue = el('div.space-y-4');
      var barre = el('div.card');
      barre.appendChild(el('div.card-body.space-y-3', null, [
        el('div.flex.flex-wrap.items-end.gap-3', null, [
          el('div', null, [el('label.label', { text: 'Vue' }), selVue]),
          el('div', null, [el('label.label', { text: 'Périodicité (flux)' }), selPeriode]),
          el('div', null, [el('label.label', { text: 'Arrêté au' }), inDate]),
          el('div.min-w-\\[16rem\\]', null, [el('label.label', { text: 'Famille d’articles' }), comboFamille]),
        ]),
        el('div.flex.flex-wrap.gap-2', null, [
          K.btn('Imprimer le point', { variant: 'primary', icon: 'printer', onclick: imprimer }),
        ]),
      ]));

      [selVue, selPeriode, inDate, comboFamille].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      /* --- Les données --------------------------------------------------- */
      function vueCourante() {
        return VUES_STOCK.filter(function (v) { return v.id === selVue.value; })[0] || VUES_STOCK[0];
      }
      function famillesRetenues() {
        var v = comboFamille.value;
        return Array.isArray(v) ? v : (v ? [v] : []);
      }
      function produitsRetenus() {
        var fam = famillesRetenues();
        return produits().filter(function (x) { return !fam.length || fam.indexOf(x.categorie) >= 0; });
      }
      /* La valorisation suit le paramètre de la clinique, lu au SOCLE. Les deux
         valeurs restent affichées côte à côte : changer de méthode ne doit pas
         rendre les états passés incomparables. */
      function prixDe(prod) { return S.valeurUnitaire(prod); }

      /** Les lignes d'un ÉTAT : ce qui reste, à la date, dans le stock visé. */
      function lignesEtat(champ) {
        return produitsRetenus().map(function (x) {
          var q = Number(x[champ]) || 0;
          var pu = prixDe(x);
          return {
            id: x.id, code: x.code, designation: x.designation, unite: x.unite,
            famille: (D.familleDe(x.categorie) || {}).label || x.categorie,
            quantite: q, pu: pu, montant: q * pu,
            cump: Math.round(x.cump || 0), montantCump: Math.round(q * (x.cump || 0)),
            seuil: x.seuilAlerte,
            sousSeuil: x.seuilAlerte != null && q <= x.seuilAlerte,
          };
        }).filter(function (r) { return r.quantite > 0 || r.sousSeuil; });
      }

      /** Les lignes d'un FLUX : ce qui a bougé, sur la période. */
      function lignesFlux(predicat) {
        var b = C.bornes(selPeriode.value, inDate.value);
        var fam = famillesRetenues();
        var index = {};
        produits().forEach(function (x) { index[x.id] = x; });

        var parProduit = {};
        mouvements().forEach(function (m) {
          if (!C.dansBornes(m.date, b)) return;
          if (!predicat(m)) return;
          var prod = index[m.produitId];
          if (!prod) return;
          if (fam.length && fam.indexOf(prod.categorie) < 0) return;
          if (!parProduit[m.produitId]) {
            parProduit[m.produitId] = {
              id: m.produitId, code: prod.code, designation: prod.designation, unite: prod.unite,
              famille: (D.familleDe(prod.categorie) || {}).label || prod.categorie,
              quantite: 0, mouvements: 0, pu: prixDe(prod), cump: Math.round(prod.cump || 0),
            };
          }
          parProduit[m.produitId].quantite += Number(m.quantite) || 0;
          parProduit[m.produitId].mouvements++;
        });

        return Object.keys(parProduit).map(function (k) {
          var r = parProduit[k];
          r.montant = r.quantite * r.pu;
          r.montantCump = r.quantite * r.cump;
          return r;
        });
      }

      function lignesCourantes() {
        var v = vueCourante();
        if (v.id === 'pharmacie_restant') return lignesEtat('stockDetail');
        if (v.id === 'magasin_restant') return lignesEtat('stockGros');
        if (v.id === 'pharmacie_recu') {
          /* Ce que la pharmacie a REÇU : les transferts, qui l'alimentent
             depuis le magasin, et les entrées portées au stock de détail. */
          return lignesFlux(function (m) {
            /* Le transfert écrit deux mouvements symétriques : seul le côté
               « détail » est une réception — compter aussi la sortie du
               magasin doublerait ce que la pharmacie a reçu. */
            return (m.type === 'transfert' && m.stockType !== 'gros')
              || (m.type === 'entree' && m.stockType === 'detail');
          });
        }
        if (v.id === 'magasin_nouveau') {
          /* Ce qui est NOUVEAU au magasin : les entrées fournisseur du stock
             gros. Un transfert n'est pas une entrée nouvelle — il déplace ce
             que la clinique possède déjà, et le compter deux fois gonflerait
             la valeur du stock. */
          return lignesFlux(function (m) { return m.type === 'entree' && m.stockType === 'gros'; });
        }
        /* Ce qui est SORTI du magasin : les sorties, plus les transferts, qui
           en sortent réellement même s'ils restent dans la clinique. */
        return lignesFlux(function (m) {
          return m.stockType === 'gros' && (m.type === 'sortie' || m.type === 'transfert'
            || m.type === 'perte' || m.type === 'casse' || m.type === 'peremption');
        });
      }

      /* --- L'affichage --------------------------------------------------- */
      function afficher() {
        C.clear(vue);
        var v = vueCourante();
        var flux = v.nature === 'flux';
        selPeriode.disabled = !flux;

        var lignes = lignesCourantes();
        var qte = C.sum(lignes, 'quantite');
        var montant = C.sum(lignes, 'montant');
        var montantCump = C.sum(lignes, 'montantCump');
        var b = C.bornes(selPeriode.value, inDate.value);

        vue.appendChild(K.note(flux
          ? '<strong>' + v.label + '</strong> — flux de la période : ' + C.libellePeriode(b) + '.'
          : '<strong>' + v.label + '</strong> — <strong>état à date</strong>, indépendant de la '
            + 'périodicité choisie : ce qui reste en rayon ne dépend pas de la fenêtre qu’on regarde.',
          { tone: 'info', icon: flux ? 'calendar-range' : 'camera' }));

        vue.appendChild(U.kpiGrid([
          { label: 'Références concernées', value: C.num(lignes.length), icon: 'list', tone: 'navy' },
          { label: 'Quantité', value: C.num(qte), icon: 'boxes', tone: 'info',
            hint: flux ? 'mouvements de la période' : 'unités en rayon' },
          { label: 'Montant', value: C.money(montant), icon: 'wallet', tone: 'success',
            hint: 'valorisé au prix de vente' },
          { label: 'Valorisation au CUMP', value: C.money(montantCump), icon: 'scale', tone: 'neutral',
            hint: 'écart : ' + C.money(montant - montantCump, false) },
        ]));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(lignes, 'montant', 'desc'),
          exportName: 'point-stock-' + v.id, pageSize: 25, searchable: true,
          filters: [{ name: 'famille', label: 'Famille',
            options: Object.keys(C.groupBy(lignes, 'famille')).sort() }],
          columns: [
            { key: 'code', label: 'Réf.', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.code }); } },
            { key: 'designation', label: 'Article' },
            { key: 'famille', label: 'Famille', render: function (r) { return U.badge(r.famille, 'navy'); } },
            { key: 'quantite', label: flux ? 'Quantité mouvementée' : 'Quantité en stock', align: 'right',
              render: function (r) {
                var q = el('span.font-semibold', { text: C.num(r.quantite) + ' ' + (r.unite || '') });
                if (!r.sousSeuil) return q;
                return el('div', null, [q, el('p.text-[10px].text-danger-600', { text: 'sous le seuil' })]);
              } },
            { key: 'pu', label: 'P.U.', align: 'right', text: function (r) { return C.money(r.pu, false); }, render: function (r) { return C.money(r.pu, false); } },
            { key: 'montant', label: 'Montant', align: 'right',
              text: function (r) { return C.money(r.montant, false); },
              render: function (r) { return el('span.font-bold.text-navy-800', { text: C.money(r.montant, false) }); } },
            { key: 'montantCump', label: 'Montant au CUMP', align: 'right',
              text: function (r) { return C.money(r.montantCump, false); },
              render: function (r) { return el('span.text-slate-500', { text: C.money(r.montantCump, false) }); } },
          ],
        }));

        /* La lecture par famille : c'est le cumul « par familles d'articles »
           que la Direction demande, sur la vue affichée. */
        var parFamille = C.groupBy(lignes, 'famille');
        var rowsF = Object.keys(parFamille).map(function (k) {
          return { id: k, famille: k,
            references: parFamille[k].length,
            quantite: C.sum(parFamille[k], 'quantite'),
            montant: C.sum(parFamille[k], 'montant') };
        });
        if (rowsF.length > 1) {
          vue.appendChild(U.card('Cumul par famille d’articles', U.dataTable({
            rows: C.sortBy(rowsF, 'montant', 'desc'), exportName: 'point-stock-familles',
            pageSize: 10, searchable: false,
            columns: [
              { key: 'famille', label: 'Famille' },
              { key: 'references', label: 'Références', align: 'right' },
              { key: 'quantite', label: 'Quantité', align: 'right' },
              { key: 'montant', label: 'Montant', align: 'right',
                text: function (r) { return C.money(r.montant, false); },
                render: function (r) { return el('span.font-semibold', { text: C.money(r.montant, false) }); } },
            ],
          })));
          vue.appendChild(K.charts([{
            title: 'Répartition de la valeur par famille',
            render: function () {
              return G.barres(rowsF.map(function (r) { return r.famille; }),
                [{ label: 'Montant', data: rowsF.map(function (r) { return r.montant; }), color: G.TONES.navy }],
                { horizontal: true, height: 260 });
            },
          }]));
        }
      }

      /* --- L'impression -------------------------------------------------- */
      function imprimer() {
        var v = vueCourante();
        var flux = v.nature === 'flux';
        var lignes = C.sortBy(lignesCourantes(), 'montant', 'desc');
        var b = C.bornes(selPeriode.value, inDate.value);

        P.etat({
          titre: v.label,
          sousTitre: flux ? C.libellePeriode(b) : 'État arrêté au ' + C.dateFR(inDate.value),
          cartouche: [
            ['Vue', v.label],
            ['Nature', flux ? 'Flux de période' : 'État à date'],
            [flux ? 'Période' : 'Arrêté au', flux ? C.libellePeriode(b) : C.dateFR(inDate.value)],
            ['Références', C.num(lignes.length)],
            ['Quantité totale', C.num(C.sum(lignes, 'quantite'))],
            ['Familles retenues', famillesRetenues().length ? C.num(famillesRetenues().length) : 'toutes'],
            ['Méthode de valorisation', S.valorisationSortie() === 'cump'
              ? 'Coût unitaire moyen pondéré' : 'Prix de vente'],
            ['Montant total', C.money(C.sum(lignes, 'montant'))],
          ],
          contenu: P.tableau([
            { label: 'Réf.', value: function (r) { return r.code; } },
            { label: 'Article', value: function (r) { return r.designation; } },
            { label: 'Famille', value: function (r) { return r.famille; } },
            { label: 'Quantité', align: 'right',
              value: function (r) { return C.num(r.quantite) + ' ' + (r.unite || ''); },
              somme: function (r) { return r.quantite; },
              formatTotal: function (x) { return C.num(x); } },
            { label: 'P.U.', align: 'right', value: function (r) { return C.money(r.pu, false); } },
            { label: 'Montant', align: 'right',
              value: function (r) { return C.money(r.montant, false); },
              somme: function (r) { return r.montant; } },
            { label: 'Montant au CUMP', align: 'right',
              value: function (r) { return C.money(r.montantCump, false); },
              somme: function (r) { return r.montantCump; } },
          ], lignes, { total: true }),
          signatures: [{ role: 'Le Gestionnaire de Stock' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

})(window);
