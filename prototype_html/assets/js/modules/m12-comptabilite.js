/* =============================================================================
 * M12 — Comptabilité SYSCOHADA
 * -----------------------------------------------------------------------------
 * CDCT §10.11 — plan comptable OHADA paramétrable, journaux, grand livre,
 * balance générale et âgée, immobilisations et amortissements, budgétisation,
 * comptabilité analytique par centre de coûts, rapprochements bancaires,
 * états financiers de synthèse et automatisation des écritures issues de la
 * caisse, de la pharmacie, des achats et de la paie.
 *
 * RG-10 — toute écriture est équilibrée (débit = crédit) avant validation.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit,
      PR = global.SIGH.parcours;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  /* Centres de coûts : référentiel administrable (écran cfg-centres-couts).
     La saisie comptable en propose la liste et permet d'en ouvrir un à la
     volée — attendre une livraison pour imputer une charge n'a pas de sens. */
  function colCentres() { return S.collection('centresCouts', { module: 'M12', entite: 'centre de coûts' }); }
  function optionsCentres() {
    return colCentres().active().map(function (c) { return { value: c.code, label: c.libelle, detail: c.type === 'support' ? 'Support' : 'Exploitation' }; });
  }

  /* L'EXERCICE CHOISI au sélecteur gouverne toute lecture comptable : aucune année en dur.
     `ecrituresToutes()` reste pour les écrans qui CHOISISSENT eux-mêmes une année
     (bilan d'ouverture, états à bornes) ; `ecritures()` porte l'exercice du sélecteur
     et, tant que le précédent n'est pas clos, ses à-nouveaux PROVISOIRES (calculés, jamais stockés). */
  function exo() { return global.SIGH.exercice.choisi(); }
  function ecrituresToutes() { return S.collection('ecritures').active(); }
  function ecritures() {
    var X = global.SIGH.exercice, a = X.choisi();
    return ecrituresToutes().filter(function (e) { return X.anneeDe(e.date) === a; }).concat(X.provisoires(a));
  }
  function comptes() { return S.collection('comptes').active(); }

  function compteLibelle(num) {
    var c = D.PLAN_COMPTABLE.filter(function (x) { return x.num === num; })[0];
    return c ? c.libelle : num;
  }
  function journalLibelle(code) {
    var j = D.JOURNAUX.filter(function (x) { return x.code === code; })[0];
    return j ? j.libelle : code;
  }
  function centreLabel(id) {
    /* La collection ADMINISTRABLE fait foi — c'est elle que l'administrateur
       renomme ; la semence ne sert que si elle n'est pas encore amorcée. */
    var v = colCentres().all().filter(function (x) { return x.code === id; })[0];
    if (v) return v.libelle;
    var c = D.CENTRES_COUT.filter(function (x) { return x.id === id; })[0];
    return c ? c.label : id;
  }
  function classeLibelle(n) {
    return {
      1: 'Classe 1 — Ressources durables', 2: 'Classe 2 — Actif immobilisé',
      3: 'Classe 3 — Stocks', 4: 'Classe 4 — Tiers', 5: 'Classe 5 — Trésorerie',
      6: 'Classe 6 — Charges', 7: 'Classe 7 — Produits', 8: 'Classe 8 — Autres charges et produits',
    }[n] || 'Classe ' + n;
  }
  function soldeCompte(num) {
    var e = ecritures().filter(function (x) { return x.compte === num; });
    return { debit: C.sum(e, 'debit'), credit: C.sum(e, 'credit'), solde: C.sum(e, 'debit') - C.sum(e, 'credit'), nb: e.length };
  }

  /* --- Colonnes réutilisables ---------------------------------------------- */
  var colNumeroEcr = {
    key: 'numero', label: 'N° pièce', nowrap: true,
    render: function (e) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: e.numero }); },
  };
  var colDateEcr = {
    key: 'date', label: 'Date', nowrap: true,
    text: function (e) { return C.dateFR(e.date); },
    render: function (e) { return C.dateFR(e.date); },
  };
  var colJournal = {
    key: 'journal', label: 'Journal', nowrap: true,
    render: function (e) { return U.badge(e.journal, 'navy'); },
  };
  var colCompte = {
    key: 'compte', label: 'Compte',
    render: function (e) {
      return el('div.min-w-0', null, [
        el('p.font-mono.text-xs.font-semibold.text-slate-700', { text: e.compte }),
        el('p.truncate.text-xs.text-slate-400', { text: e.compteLibelle || compteLibelle(e.compte) }),
      ]);
    },
  };
  var colDebit = {
    key: 'debit', label: 'Débit', align: 'right',
    text: function (e) { return e.debit ? C.money(e.debit, false) : ''; },
    render: function (e) { return e.debit ? el('span.font-medium', { text: C.money(e.debit, false) }) : el('span.text-slate-300', { text: '—' }); },
  };
  var colCredit = {
    key: 'credit', label: 'Crédit', align: 'right',
    text: function (e) { return e.credit ? C.money(e.credit, false) : ''; },
    render: function (e) { return e.credit ? el('span.font-medium', { text: C.money(e.credit, false) }) : el('span.text-slate-300', { text: '—' }); },
  };

  /* ==========================================================================
   * TABLEAU DE BORD COMPTABLE
   * ======================================================================== */
  global.SIGH.screen('m12-dashboard', {
    title: 'Tableau de bord — Comptabilité SYSCOHADA',
    description: 'Équilibre des journaux, trésorerie, charges et produits, créances et dettes.',
    render: K.dash({
      alerte: function () {
        var e = ecritures();
        var d = C.sum(e, 'debit'), c = C.sum(e, 'credit');
        var brouillons = e.filter(function (x) { return x.statut === 'brouillon'; });
        var wrap = el('div.grid.gap-2.sm\\:grid-cols-2');
        var a = false;
        if (Math.abs(d - c) > 0) {
          wrap.appendChild(K.note('<strong>RG-10 — déséquilibre constaté</strong> : écart de ' + C.money(Math.abs(d - c))
            + ' entre le total des débits et celui des crédits. À régulariser avant clôture.', { tone: 'danger', icon: 'scale-3d' }));
          a = true;
        }
        if (brouillons.length) {
          wrap.appendChild(K.note('<strong>' + brouillons.length + ' écriture(s) en brouillon</strong> à valider.', { tone: 'warning', icon: 'file-clock' }));
          a = true;
        }
        return a ? wrap : null;
      },
      kpis: function () {
        var e = ecritures();
        var charges = e.filter(function (x) { return String(x.compte)[0] === '6'; });
        var produits = e.filter(function (x) { return String(x.compte)[0] === '7'; });
        var caisse = soldeCompte('571000'), banque = soldeCompte('521000');
        var clients = soldeCompte('411000').solde + soldeCompte('411200').solde;
        var fournisseurs = soldeCompte('401000');
        var ca = C.sum(produits, 'credit');
        var ch = C.sum(charges, 'debit');
        return [
          { label: 'Trésorerie disponible', value: C.money(caisse.solde + banque.solde), icon: 'wallet', tone: 'navy' },
          { label: 'Chiffre d’affaires', value: C.money(ca), icon: 'trending-up', tone: 'success' },
          { label: 'Charges', value: C.money(ch), icon: 'trending-down', tone: 'warning' },
          { label: 'Résultat', value: C.money(ca - ch), icon: ca - ch >= 0 ? 'smile' : 'frown', tone: ca - ch >= 0 ? 'success' : 'danger' },
          { label: 'Créances clients', value: C.money(clients), icon: 'hand-coins', tone: 'info' },
          { label: 'Dettes fournisseurs', value: C.money(Math.abs(fournisseurs.solde)), icon: 'truck', tone: 'warning' },
          { label: 'Écritures de l’exercice', value: C.num(e.length), icon: 'book-open-check', tone: 'neutral' },
          {
            label: 'Équilibre (RG-10)',
            value: C.sum(e, 'debit') === C.sum(e, 'credit') ? 'Équilibré' : C.money(Math.abs(C.sum(e, 'debit') - C.sum(e, 'credit'))),
            icon: 'scale', tone: C.sum(e, 'debit') === C.sum(e, 'credit') ? 'success' : 'danger',
          },
        ];
      },
      sections: [
        {
          render: function () {
            return K.charts([
              {
                title: 'Produits et charges (12 mois)',
                render: function () {
                  var prod = K.parMois(ecritures().filter(function (e) { return String(e.compte)[0] === '7'; }), 'date', 'credit');
                  var ch = K.parMois(ecritures().filter(function (e) { return String(e.compte)[0] === '6'; }), 'date', 'debit');
                  return G.ligne(prod.labels, [
                    { label: 'Produits', data: prod.data, color: G.TONES.vert },
                    { label: 'Charges', data: ch.data, color: G.TONES.rouge },
                  ]);
                },
              },
              {
                title: 'Écritures par journal',
                render: function () {
                  var g = C.groupBy(ecritures(), 'journal');
                  var keys = Object.keys(g);
                  return G.anneau(keys.map(journalLibelle), keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Charges par centre de coûts',
                render: function () {
                  var g = C.groupBy(ecritures().filter(function (e) { return e.debit > 0 && String(e.compte)[0] === '6'; }), 'centreCout');
                  return K.ranking(Object.keys(g).map(function (k) {
                    return { label: centreLabel(k), value: C.sum(g[k], 'debit') };
                  }).sort(function (a, b) { return b.value - a.value; }), { format: function (v) { return C.money(v, false); } });
                },
              },
              {
                title: 'Origine des écritures',
                render: function () {
                  var g = C.groupBy(ecritures(), 'origine');
                  var keys = Object.keys(g);
                  return G.barres(keys, [{ label: 'Écritures', data: keys.map(function (k) { return g[k].length; }) }],
                    { horizontal: true, height: 260 });
                },
              },
            ]);
          },
        },
        {
          title: 'Automatisation des écritures',
          render: function () {
            return K.miniTable([
              { label: 'Opération métier', key: 'op' },
              { label: 'Module d’origine', key: 'mod' },
              { label: 'Journal', render: function (x) { return U.badge(x.journal, 'navy'); } },
              { label: 'Compte débité', render: function (x) { return el('span.font-mono.text-xs', { text: x.debit }); } },
              { label: 'Compte crédité', render: function (x) { return el('span.font-mono.text-xs', { text: x.credit }); } },
            ], [
              { op: 'Encaissement d’une facture patient', mod: 'M8 — Caisse', journal: 'CAI', debit: '571000', credit: '411000' },
              { op: 'Facturation d’une prestation', mod: 'M8 — Facturation', journal: 'VTE', debit: '411000', credit: '706000' },
              { op: 'Vente de médicaments', mod: 'M6 — Pharmacie', journal: 'VTE', debit: '411000', credit: '701000' },
              { op: 'Réception d’une commande', mod: 'M7 — Achats', journal: 'ACH', debit: '601100', credit: '401000' },
              { op: 'Facture assureur', mod: 'M9 — Assurances', journal: 'VTE', debit: '411200', credit: '706000' },
              { op: 'Salaires du mois', mod: 'M11 — Paie', journal: 'SAL', debit: '661100', credit: '422000' },
              { op: 'Cotisations CNSS', mod: 'M11 — Paie', journal: 'SAL', debit: '641200', credit: '431000' },
              { op: 'Perte ou casse de stock', mod: 'M6 — Stock', journal: 'OD', debit: '651100', credit: '311000' },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm12-ecritures', icon: 'pencil-line', label: 'Saisir une écriture', detail: 'Équilibre contrôlé (RG-10)' },
              { id: 'm12-grand-livre', icon: 'book-open', label: 'Grand livre', detail: 'Par compte' },
              { id: 'm12-balance', icon: 'scale', label: 'Balance', detail: 'Générale et âgée' },
              { id: 'm12-etats-financiers', icon: 'file-spreadsheet', label: 'États financiers', detail: 'Bilan et résultat' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * PLAN COMPTABLE
   * ======================================================================== */
  global.SIGH.screen('m12-plan-comptable', {
    title: 'Plan comptable OHADA',
    description: 'Référentiel des comptes du plan SYSCOHADA utilisés par la clinique, par classe.',
    regle: 'Les comptes marqués « document » proviennent du classeur comptable SYSCOHADA transmis lors du cadrage ; les autres complètent le plan pour permettre le bouclage des schémas d’écriture.',
    render: K.crud({
      collection: 'comptes', entite: 'compte', entiteP: 'comptes', module: 'M12',
      defaultSort: 'num', pageSize: 20,
      source: 'Classeur comptable SYSCOHADA — journal des comptes par mois.',
      columns: [
        { key: 'num', label: 'N° de compte', nowrap: true, render: function (c) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: c.num }); } },
        { key: 'libelle', label: 'Intitulé' },
        { key: 'classe', label: 'Classe', text: function (c) { return classeLibelle(c.classe); }, render: function (c) { return U.badge('Classe ' + c.classe, 'navy'); } },
        { key: 'journal', label: 'Journal usuel', render: function (c) { return U.badge(c.journal, 'neutral'); } },
        {
          key: 'source', label: 'Provenance',
          render: function (c) { return c.source === 'DOC' ? U.badge('Document clinique', 'success') : U.badge('Complément', 'neutral'); },
        },
        {
          key: 'mouvements', label: 'Écritures', align: 'right',
          value: function (c) { return soldeCompte(c.num).nb; },
          render: function (c) { return String(soldeCompte(c.num).nb); },
        },
        {
          key: 'solde', label: 'Solde', align: 'right',
          value: function (c) { return soldeCompte(c.num).solde; },
          text: function (c) { return C.money(soldeCompte(c.num).solde, false); },
          render: function (c) {
            var s = soldeCompte(c.num).solde;
            return el('span', { class: s < 0 ? 'font-semibold text-danger-600' : 'font-semibold', text: C.money(s, false) });
          },
        },
      ],
      fields: [
        { name: 'num', label: 'Numéro de compte', required: true, help: 'Format SYSCOHADA à 6 chiffres.' },
        { name: 'libelle', label: 'Intitulé', required: true, col: 'full' },
        { name: 'classe', label: 'Classe', type: 'select', required: true, options: [1, 2, 3, 4, 5, 6, 7, 8].map(function (n) { return { value: n, label: classeLibelle(n) }; }) },
        { name: 'journal', label: 'Journal usuel', type: 'select', required: true, options: D.JOURNAUX.map(function (j) { return { value: j.code, label: j.code + ' — ' + j.libelle }; }) },
      ],
      /* Écart E721 : la provenance était remise à « CDCT » à CHAQUE enregistrement — modifier un compte du document en faisait un
         « Complément ». Seule la création pose la provenance ; la modification la conserve. */
      transform: function (v, record) { v.classe = Number(v.classe); if (!v.source && !record) v.source = 'CDCT'; return v; },
      beforeSave: function (v, record) {
        if (!/^\d{6}$/.test(String(v.num))) return 'Le numéro de compte doit comporter 6 chiffres.';
        if (!record && comptes().some(function (c) { return c.num === v.num; })) return 'Ce numéro de compte existe déjà.';
        return null;
      },
      filters: [
        { name: 'classe', label: 'Classe', options: [1, 2, 3, 4, 5, 6, 7, 8].map(function (n) { return { value: String(n), label: classeLibelle(n) }; }), match: function (c, v) { return String(c.classe) === v; } },
        { name: 'journal', label: 'Journal', options: D.JOURNAUX.map(function (j) { return { value: j.code, label: j.libelle }; }) },
        { name: 'source', label: 'Provenance', options: [{ value: 'DOC', label: 'Document clinique' }, { value: 'CDCT', label: 'Complément' }] },
      ],
      kpis: function (rows) {
        return [
          { label: 'Comptes paramétrés', value: C.num(rows.length), icon: 'list-tree', tone: 'navy' },
          { label: 'Issus des documents', value: C.num(rows.filter(function (c) { return c.source === 'DOC'; }).length), icon: 'file-check-2', tone: 'success' },
          { label: 'Classes utilisées', value: C.num(Object.keys(C.groupBy(rows, 'classe')).length), icon: 'layers', tone: 'info' },
          { label: 'Comptes mouvementés', value: C.num(rows.filter(function (c) { return soldeCompte(c.num).nb > 0; }).length), icon: 'activity', tone: 'neutral' },
        ];
      },
      extraTabs: [{
        id: 'classes', label: 'Par classe',
        render: function () {
          var g = C.groupBy(comptes(), 'classe');
          var wrap = el('div.space-y-4');
          C.sortBy(Object.keys(g).map(Number)).forEach(function (cl) {
            wrap.appendChild(U.card(classeLibelle(cl), K.miniTable([
              { label: 'Compte', render: function (c) { return el('span.font-mono.text-xs', { text: c.num }); } },
              { label: 'Intitulé', key: 'libelle' },
              { label: 'Journal', render: function (c) { return U.badge(c.journal, 'neutral'); } },
              { label: 'Solde', align: 'right', render: function (c) { return C.money(soldeCompte(c.num).solde, false); } },
            ], C.sortBy(g[cl], 'num'))));
          });
          return wrap;
        },
      }],
    }),
    actions: function () {
      return [K.btn('Imprimer le plan comptable', {
        variant: 'primary', icon: 'printer',
        onclick: function () {
          P.etat({
            titre: 'Plan comptable SYSCOHADA',
            sousTitre: 'Référentiel des comptes utilisés par la clinique',
            cartouche: [['Comptes paramétrés', C.num(comptes().length)],
              ['Classes', C.num(Object.keys(C.groupBy(comptes(), 'classe')).length)],
              ['Exercice', String(exo())], ['Date d’édition', C.dateFR(AUJ)]],
            contenu: P.tableau([
              { label: 'N° de compte', key: 'num' },
              { label: 'Intitulé', key: 'libelle' },
              { label: 'Classe', key: 'classe', align: 'right' },
              { label: 'Journal', key: 'journal' },
            ], C.sortBy(comptes(), 'num')),
            signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })];
    },
  });

  /* ==========================================================================
   * JOURNAUX COMPTABLES
   * ======================================================================== */
  global.SIGH.screen('m12-journaux', {
    title: 'Journaux comptables',
    regle: 'Écran <strong>calculé</strong> : un journal est la vue des écritures d’une nature donnée. '
      + 'Il ne se saisit pas — les écritures se corrigent depuis la saisie comptable, seul endroit où '
      + 'l’équilibre débit / crédit est contrôlé (RG-10).',
    description: 'Journaux d’achats, ventes, caisse, banque, salaires, immobilisations et opérations diverses.',
    render: function (root) {
      var host = el('div.space-y-4');
      var e = ecritures();

      var lignes = D.JOURNAUX.map(function (j) {
        var sel = e.filter(function (x) { return x.journal === j.code; });
        return {
          id: j.code, code: j.code, libelle: j.libelle,
          contrepartie: j.contrepartie,
          nb: sel.length, debit: C.sum(sel, 'debit'), credit: C.sum(sel, 'credit'),
          equilibre: C.sum(sel, 'debit') === C.sum(sel, 'credit'),
        };
      });

      host.appendChild(U.kpiGrid([
        { label: 'Journaux ouverts', value: C.num(lignes.length), icon: 'book', tone: 'navy' },
        { label: 'Écritures totales', value: C.num(e.length), icon: 'file-text', tone: 'info' },
        { label: 'Total débit', value: C.money(C.sum(e, 'debit')), icon: 'arrow-down-left', tone: 'warning' },
        { label: 'Total crédit', value: C.money(C.sum(e, 'credit')), icon: 'arrow-up-right', tone: 'success' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Journaux comptables', rows: lignes, exportName: 'journaux', pageSize: 10,
        columns: [
          { key: 'code', label: 'Code', nowrap: true, render: function (j) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: j.code }); } },
          { key: 'libelle', label: 'Intitulé' },
          { key: 'contrepartie', label: 'Compte de contrepartie', render: function (j) { return j.contrepartie ? el('span.font-mono.text-xs', { text: j.contrepartie }) : el('span.text-xs.text-slate-400', { text: 'Variable' }); } },
          { key: 'nb', label: 'Écritures', align: 'right' },
          { key: 'debit', label: 'Total débit', align: 'right', text: function (j) { return C.money(j.debit, false); }, render: function (j) { return C.money(j.debit, false); } },
          { key: 'credit', label: 'Total crédit', align: 'right', text: function (j) { return C.money(j.credit, false); }, render: function (j) { return C.money(j.credit, false); } },
          {
            key: 'equilibre', label: 'Équilibre',
            text: function (j) { return j.equilibre ? 'Équilibré' : 'Déséquilibré'; },
            render: function (j) {
              return j.equilibre ? U.badge('Équilibré', 'success')
                : U.badge('Écart ' + C.money(Math.abs(j.debit - j.credit), false), 'danger');
            },
          },
        ],
        onRowClick: function (j) { consulter(j); },
        rowActions: function (j) {
          return [
            K.iconBtn('eye', 'Consulter le journal', function () { consulter(j); }),
            K.iconBtn('printer', 'Imprimer', function () { imprimer(j); }),
          ];
        },
      }));
      root.appendChild(host);
      return null;

      function consulter(j) {
        var sel = C.sortBy(e.filter(function (x) { return x.journal === j.code; }), 'date', 'desc');
        U.drawer({
          title: j.libelle, subtitle: 'Journal ' + j.code + ' — ' + sel.length + ' écriture(s)', width: 'max-w-4xl',
          body: el('div.space-y-4', null, [
            U.kpiGrid([
              { label: 'Total débit', value: C.money(j.debit), icon: 'arrow-down-left', tone: 'warning' },
              { label: 'Total crédit', value: C.money(j.credit), icon: 'arrow-up-right', tone: 'success' },
            ], 'grid-cols-2'),
            K.miniTable([
              { label: 'N° pièce', render: function (x) { return el('span.font-mono.text-xs', { text: x.numero }); } },
              { label: 'Date', render: function (x) { return C.dateFR(x.date); } },
              { label: 'Compte', render: function (x) { return el('span.font-mono.text-xs', { text: x.compte }); } },
              { label: 'Libellé', key: 'libelle' },
              { label: 'Débit', align: 'right', render: function (x) { return x.debit ? C.money(x.debit, false) : '—'; } },
              { label: 'Crédit', align: 'right', render: function (x) { return x.credit ? C.money(x.credit, false) : '—'; } },
            ], sel.slice(0, 40)),
          ]),
          footer: [K.btn('Imprimer le journal', { variant: 'primary', icon: 'printer', onclick: function () { imprimer(j); } })],
        });
      }

      function imprimer(j) {
        var sel = C.sortBy(e.filter(function (x) { return x.journal === j.code; }), 'date');
        P.etat({
          titre: 'Journal comptable — ' + j.libelle,
          sousTitre: 'Code journal ' + j.code + ' — exercice ' + exo(),
          cartouche: [['Journal', j.code + ' — ' + j.libelle], ['Écritures', C.num(sel.length)],
            ['Total débit', C.money(j.debit)], ['Total crédit', C.money(j.credit)],
            ['Équilibre', j.equilibre ? 'Équilibré' : 'Écart de ' + C.money(Math.abs(j.debit - j.credit))],
            ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'N° pièce', key: 'numero' },
            { label: 'Date', value: function (x) { return C.dateFR(x.date); } },
            { label: 'Compte', key: 'compte' },
            { label: 'Intitulé du compte', value: function (x) { return x.compteLibelle || compteLibelle(x.compte); } },
            { label: 'Libellé de l’opération', key: 'libelle' },
            /* LES TOTAUX DU JOURNAL SE REFONT DEPUIS SES PROPRES ÉCRITURES.
               Ils étaient transmis sous des clés qu'aucune colonne ne portait
               et ne s'imprimaient pas : un journal comptable dont le pied est
               vide ne prouve plus son équilibre (RG-10) au lecteur. */
            { label: 'Débit', align: 'right', value: function (x) { return x.debit ? C.money(x.debit, false) : ''; }, somme: function (x) { return x.debit; } },
            { label: 'Crédit', align: 'right', value: function (x) { return x.credit ? C.money(x.credit, false) : ''; }, somme: function (x) { return x.credit; } },
          ], sel, { total: true, totalLabel: 'TOTAUX' }),
          signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * ÉCRITURES COMPTABLES
   * ======================================================================== */
  global.SIGH.screen('m12-ecritures', {
    title: 'Écritures comptables',
    description: 'Saisie, consultation et validation des écritures, avec contrôle d’équilibre.',
    regle: '<strong>RG-10</strong> — toute écriture doit être équilibrée (total débit = total crédit) avant validation dans le journal correspondant.',
    render: function (root) {
      var col = S.collection('ecritures', { module: 'M12', entite: 'EcritureComptable' });
      var host = el('div.space-y-4');
      var table;

      host.appendChild(U.kpiGrid([
        { label: 'Écritures enregistrées', value: C.num(col.active().length), icon: 'file-text', tone: 'navy' },
        { label: 'Validées', value: C.num(col.active().filter(function (e) { return e.statut === 'validee'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'En brouillon', value: C.num(col.active().filter(function (e) { return e.statut === 'brouillon'; }).length), icon: 'file-clock', tone: 'warning' },
        { label: 'Automatiques', value: C.num(col.active().filter(function (e) { return String(e.origine).indexOf('Automatique') === 0; }).length), icon: 'zap', tone: 'info' },
      ]));

      table = U.dataTable({
        title: 'Écritures comptables',
        rows: function () { return col.active(); },
        exportName: 'ecritures', pageSize: 20,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'journal', label: 'Journal', options: D.JOURNAUX.map(function (j) { return { value: j.code, label: j.libelle }; }) },
          { name: 'statut', label: 'Statut', options: [{ value: 'validee', label: 'Validée' }, { value: 'brouillon', label: 'Brouillon' }] },
          { name: 'centreCout', label: 'Centre de coûts', options: optionsCentres() },
        ],
        actions: [K.commande('Nouvelle écriture', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(); } })].filter(Boolean),
        columns: [
          colNumeroEcr, colDateEcr, colJournal, colCompte,
          { key: 'libelle', label: 'Libellé de l’opération' },
          colDebit, colCredit,
          { key: 'centreCout', label: 'Centre de coûts', text: centreLabel, render: function (e) { return el('span.text-xs.text-slate-500', { text: centreLabel(e.centreCout) }); } },
          { key: 'origine', label: 'Origine', render: function (e) { return U.badge(e.origine, String(e.origine).indexOf('Automatique') === 0 ? 'info' : 'neutral'); } },
          { key: 'statut', label: 'Statut', render: function (e) { return U.statut(e.statut); } },
        ],
        onRowClick: function (e) { consulter(e); },
        rowActions: function (e) {
          var acts = [K.iconBtn('eye', 'Consulter', function () { consulter(e); })];
          if (e.statut === 'brouillon') {
            acts.push(K.iconBtn('check', 'Valider', function () {
              /* On valide la PIÈCE ENTIÈRE, jamais une ligne seule (écart E710) : valider une ligne coupait l'écriture en deux
                 et laissait la balance boiteuse. RG-10 est contrôlé sur l'ensemble des lignes de même numéro AVANT. */
              var piece = col.active().filter(function (x) { return x.numero === e.numero && x.statut === 'brouillon'; });
              var td = C.sum(piece, 'debit'), tc = C.sum(piece, 'credit');
              if (td !== tc) {
                U.toast('RG-10 — écriture déséquilibrée : validation impossible.', {
                  type: 'error', detail: 'Pièce ' + e.numero + ' : écart de ' + C.money(Math.abs(td - tc)) + '.',
                });
                return;
              }
              var res = piece.map(function (x) { return col.update(x.id, { statut: 'validee' }); });
              table.refresh();
              U.toast('Écriture validée.', { type: 'success', detail: piece.length + ' ligne(s).',
                undo: function () { res.forEach(function (r) { if (r) r.undo(); }); table.refresh(); } });
            }, 'ghost'));
          }
          acts.push(K.iconBtn('archive', 'Archiver', function () {
            /* On archive la PIÈCE ENTIÈRE (écart E716, même défaut que la validation) : archiver une ligne seule laissait
               l'autre au journal — une demi-écriture serait pire qu'aucune (RG-10, comme l'archivage d'une dépense). */
            var piece = col.active().filter(function (x) { return x.numero === e.numero; });
            var res = piece.map(function (x) { return col.archive(x.id); });
            table.refresh();
            U.toast('Écriture archivée.', { type: 'success', detail: piece.length + ' ligne(s).',
              undo: function () { res.forEach(function (r) { if (r) r.undo(); }); table.refresh(); } });
          }, 'ghost'));
          return acts;
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      /* Saisie en partie double : plusieurs lignes, contrôle d'équilibre. */
      function ouvrir() {
        var lignes = [];
        var body = el('div.space-y-4');

        var f = U.form([
          { name: 'date', label: 'Date de l’opération', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'journal', label: 'Journal', type: 'select', required: true, options: D.JOURNAUX.map(function (j) { return { value: j.code, label: j.code + ' — ' + j.libelle }; }) },
          { name: 'libelle', label: 'Libellé de l’opération', required: true, col: 'full' },
          {
            name: 'centreCout', label: 'Centre de coûts', type: 'select', options: optionsCentres(),
            help: 'Axe d’imputation analytique. Un centre manquant se crée depuis le bouton ci-dessous, sans quitter la saisie.',
          },
          { name: 'piece', label: 'Référence de la pièce justificative' },
        ], {});
        body.appendChild(f);

        var ajout = el('div.flex.flex-wrap.items-end.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.p-3');
        var listeComptes = C.sortBy(comptes(), 'num');
        var selCompte = U.combo(listeComptes.map(function (c) {
          return { value: c.num, label: c.libelle, detail: 'Compte ' + c.num, icon: 'hash' };
        }), {
          value: listeComptes.length ? listeComptes[0].num : '',
          searchPlaceholder: 'Numéro ou libellé du compte…',
          placeholder: 'Choisir un compte',
        });
        var debit = el('input.input.w-32', { type: 'number', min: 0, value: 0 });
        var credit = el('input.input.w-32', { type: 'number', min: 0, value: 0 });
        ajout.appendChild(el('div.min-w-\\[18rem\\].flex-1', null, [el('label.label', { text: 'Compte' }), selCompte]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Débit' }), debit]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Crédit' }), credit]));
        ajout.appendChild(K.btn('Ajouter la ligne', {
          variant: 'primary', icon: 'plus',
          onclick: function () {
            var d = Number(debit.value) || 0, cr = Number(credit.value) || 0;
            if (d === 0 && cr === 0) { U.toast('Renseigner un montant au débit ou au crédit.', { type: 'error' }); return; }
            if (d > 0 && cr > 0) { U.toast('Une ligne ne peut être simultanément au débit et au crédit.', { type: 'error' }); return; }
            lignes.push({ compte: selCompte.value, compteLibelle: compteLibelle(selCompte.value), debit: d, credit: cr });
            debit.value = 0; credit.value = 0;
            maj();
          },
        }));
        body.appendChild(ajout);

        var lignesHost = el('div');
        body.appendChild(lignesHost);

        function maj() {
          C.clear(lignesHost);
          var td = C.sum(lignes, 'debit'), tc = C.sum(lignes, 'credit');
          var equilibre = td === tc && td > 0;

          if (!lignes.length) {
            lignesHost.appendChild(U.empty('Aucune ligne saisie.', { icon: 'list' }));
          } else {
            var t = el('table.tbl');
            t.appendChild(el('thead', null, el('tr', null, [
              el('th', { text: 'Compte' }), el('th.text-right', { text: 'Débit' }),
              el('th.text-right', { text: 'Crédit' }), el('th'),
            ])));
            var tb = el('tbody');
            lignes.forEach(function (l, i) {
              tb.appendChild(el('tr', null, [
                el('td', null, el('div', null, [
                  el('p.font-mono.text-xs.font-semibold', { text: l.compte }),
                  el('p.text-xs.text-slate-400', { text: l.compteLibelle }),
                ])),
                el('td.text-right.num', { text: l.debit ? C.money(l.debit, false) : '—' }),
                el('td.text-right.num', { text: l.credit ? C.money(l.credit, false) : '—' }),
                el('td.text-right', null, K.iconBtn('x', 'Retirer', function () { lignes.splice(i, 1); maj(); }, 'ghost')),
              ]));
            });
            t.appendChild(tb);
            t.appendChild(el('tfoot', null, el('tr', null, [
              el('td.font-semibold', { text: 'TOTAUX' }),
              el('td.text-right.num.font-bold', { text: C.money(td, false) }),
              el('td.text-right.num.font-bold', { text: C.money(tc, false) }),
              el('td'),
            ])));
            lignesHost.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));
          }

          lignesHost.appendChild(equilibre
            ? K.note('<strong>RG-10 respectée</strong> — l’écriture est équilibrée : débit = crédit = ' + C.money(td) + '.', { tone: 'success', icon: 'scale' })
            : K.note('<strong>RG-10</strong> — l’écriture n’est pas équilibrée : écart de <strong>' + C.money(Math.abs(td - tc))
              + '</strong>. La validation est impossible tant que débit ≠ crédit.', { tone: 'danger', icon: 'scale-3d' }));
          U.icons(lignesHost);
        }
        maj();

        var m = U.modal({
          title: 'Nouvelle écriture comptable',
          subtitle: 'Saisie en partie double — contrôle d’équilibre appliqué (RG-10)',
          size: 'xl', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            /* Créer un centre de coûts sans quitter la saisie : attendre une
               livraison pour imputer une charge n'aurait pas de sens. */
            K.btn('Nouveau centre de coûts', {
              icon: 'target',
              onclick: function () {
                var cf = U.form([
                  { name: 'libelle', label: 'Intitulé du centre', required: true, col: 'full' },
                  {
                    name: 'type', label: 'Type', type: 'select', required: true,
                    options: [{ value: 'exploitation', label: 'Centre d’exploitation' }, { value: 'support', label: 'Centre de support' }],
                  },
                  { name: 'responsable', label: 'Responsable', col: 'full' },
                ], {});
                var mc = U.modal({
                  title: 'Nouveau centre de coûts', size: 'md', body: cf,
                  footer: [
                    K.btn('Annuler', { onclick: function () { mc.close(); } }),
                    K.btn('Créer', {
                      variant: 'primary', icon: 'plus',
                      onclick: function () {
                        var cv = cf.collect();
                        if (!cv) return;
                        cv.code = 'CC' + C.pad(colCentres().all().length + 1, 2);
                        cv.source = 'Créé depuis la saisie comptable';
                        var res = colCentres().insert(cv);
                        mc.close();
                        /* Le combo n'est pas un <select> : on renouvelle ses
                           entrées par setOptions, puis on choisit la nouvelle. */
                        var ctrl = f.controls.centreCout;
                        if (ctrl && ctrl.setOptions) { ctrl.setOptions(optionsCentres(), true); ctrl.value = res.record.code; }
                        U.toast('Centre « ' + cv.libelle + ' » créé et sélectionné.', { type: 'success' });
                      },
                    }),
                  ],
                });
              },
            }),
            K.btn('Enregistrer en brouillon', {
              onclick: function () { enregistrer('brouillon'); },
            }),
            K.btn('Valider l’écriture', {
              variant: 'primary', icon: 'check',
              onclick: function () { enregistrer('validee'); },
            }),
          ],
        });

        function enregistrer(statut) {
          var v = f.collect();
          if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
          if (!lignes.length) { U.toast('Ajouter au moins une ligne.', { type: 'error' }); return; }
          var td = C.sum(lignes, 'debit'), tc = C.sum(lignes, 'credit');
          if (statut === 'validee' && td !== tc) {
            U.toast('RG-10 — écriture déséquilibrée : validation impossible.', {
              type: 'error', detail: 'Écart de ' + C.money(Math.abs(td - tc)) + '.',
            });
            return;
          }
          /* Écart E711 : le rang était « nombre de lignes actives + 1 » — il repart en arrière à chaque archivage et redonne un numéro déjà
             attribué. Le rang est le plus grand déjà écrit pour ce journal et cet exercice, plus un (lu sur les fiches existantes). */
          var prefNum = v.journal + '-' + exo() + '-', maxNum = 0;
          col.all().forEach(function (x) {
            if (String(x.numero || '').indexOf(prefNum) === 0) maxNum = Math.max(maxNum, parseInt(String(x.numero).slice(prefNum.length), 10) || 0);
          });
          var num = prefNum + C.pad(maxNum + 1, 5);
          var crees = lignes.map(function (l) {
            return col.insert({
              numero: num, date: v.date, journal: v.journal, journalLibelle: journalLibelle(v.journal),
              compte: l.compte, compteLibelle: l.compteLibelle,
              libelle: v.libelle, debit: l.debit, credit: l.credit,
              centreCout: v.centreCout, piece: v.piece,
              origine: 'Saisie manuelle', statut: statut,
            });
          });
          /* Écart E713 : une écriture refusée par la garde de l'exercice clos rend null — la maquette annonçait « enregistrée » et
             fermait la saisie. On défait ce qui a pu être écrit et la saisie reste ouverte (le refus a déjà été dit). */
          if (crees.some(function (r) { return !r; })) {
            crees.forEach(function (r) { if (r) r.undo(); });
            table.refresh();
            return;
          }
          m.close(); table.refresh();
          U.toast('Écriture ' + num + ' enregistrée (' + crees.length + ' ligne(s)).', {
            type: 'success',
            detail: statut === 'validee' ? 'Validée et équilibrée.' : 'Enregistrée en brouillon.',
            undo: function () { crees.forEach(function (r) { r.undo(); }); table.refresh(); },
          });
        }
      }

      function consulter(e) {
        var memeNumero = col.active().filter(function (x) { return x.numero === e.numero; });
        var td = C.sum(memeNumero, 'debit'), tc = C.sum(memeNumero, 'credit');
        U.drawer({
          title: 'Écriture ' + e.numero, subtitle: e.libelle + ' — ' + C.dateFR(e.date), width: 'max-w-3xl',
          body: el('div.space-y-4', null, [
            U.descList([['N° de pièce', e.numero], ['Date', C.dateFR(e.date)],
              ['Journal', journalLibelle(e.journal)], ['Libellé', e.libelle],
              ['Centre de coûts', centreLabel(e.centreCout)], ['Origine', e.origine],
              ['Pièce justificative', e.piece || '—'], ['Statut', U.statut(e.statut)]]),
            U.card('Lignes de l’écriture', K.miniTable([
              { label: 'Compte', render: function (x) { return el('span.font-mono.text-xs', { text: x.compte }); } },
              { label: 'Intitulé', render: function (x) { return x.compteLibelle || compteLibelle(x.compte); } },
              { label: 'Débit', align: 'right', render: function (x) { return x.debit ? C.money(x.debit, false) : '—'; } },
              { label: 'Crédit', align: 'right', render: function (x) { return x.credit ? C.money(x.credit, false) : '—'; } },
            ], memeNumero)),
            td === tc
              ? K.note('Écriture équilibrée : débit = crédit = ' + C.money(td) + ' (RG-10).', { tone: 'success', icon: 'scale' })
              : K.note('Écart de ' + C.money(Math.abs(td - tc)) + ' entre débit et crédit (RG-10).', { tone: 'danger', icon: 'scale-3d' }),
          ]),
        });
      }
    },
  });

  /* ==========================================================================
   * GRAND LIVRE
   * ======================================================================== */
  global.SIGH.screen('m12-grand-livre', {
    title: 'Grand livre',
    description: 'Détail chronologique des mouvements par compte, avec solde progressif.',
    regle: 'Écran en lecture seule. Le grand livre est <strong>reconstitué depuis les écritures</strong> : il ne se modifie pas ici. Toute correction passe par l’écriture d’origine (Écritures comptables), qui doit rester équilibrée (RG-10).',
    render: function (root) {
      var host = el('div.space-y-4');
      /* Écart E724 : le plan porte deux fiches au même numéro (244100, 631810) — la liste proposait le compte deux fois. UNE entrée par numéro. */
      var numsVus = {};
      var mouvementes = comptes().filter(function (c) {
        if (soldeCompte(c.num).nb === 0 || numsVus[c.num]) return false;
        numsVus[c.num] = true; return true;
      });

      var listeMvt = C.sortBy(mouvementes, 'num');
      var selCompte = U.combo(listeMvt.map(function (c) {
        return { value: c.num, label: c.libelle, detail: 'Compte ' + c.num, icon: 'hash' };
      }), {
        value: listeMvt.length ? listeMvt[0].num : '',
        searchPlaceholder: 'Numéro ou libellé du compte…',
        placeholder: 'Choisir un compte',
      });
      selCompte.classList.add('max-w-lg');

      var barre = el('div.card');
      var bbody = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      bbody.appendChild(el('div.flex-1', null, [el('label.label', { text: 'Compte' }), selCompte]));
      bbody.appendChild(K.btn('Imprimer le grand livre', { variant: 'primary', icon: 'printer', onclick: imprimer }));
      bbody.appendChild(K.btn('Grand livre complet', { icon: 'book-open', onclick: imprimerComplet }));
      barre.appendChild(bbody);
      host.appendChild(barre);

      var vue = el('div.space-y-4');
      host.appendChild(vue);
      selCompte.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;

      function mouvements() {
        return C.sortBy(ecritures().filter(function (e) { return e.compte === selCompte.value; }), 'date');
      }

      function avecSolde() {
        var solde = 0;
        return mouvements().map(function (e) {
          solde += (e.debit || 0) - (e.credit || 0);
          return Object.assign({}, e, { soldeProgressif: solde });
        });
      }

      function afficher() {
        var rows = avecSolde();
        var s = soldeCompte(selCompte.value);
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Mouvements', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
          { label: 'Total débit', value: C.money(s.debit), icon: 'arrow-down-left', tone: 'warning' },
          { label: 'Total crédit', value: C.money(s.credit), icon: 'arrow-up-right', tone: 'success' },
          { label: 'Solde', value: C.money(s.solde), icon: 'scale', tone: s.solde >= 0 ? 'navy' : 'danger', hint: s.solde >= 0 ? 'Débiteur' : 'Créditeur' },
        ]));

        vue.appendChild(U.dataTable({
          title: selCompte.value + ' — ' + compteLibelle(selCompte.value),
          rows: rows, exportName: 'grand-livre-' + selCompte.value, pageSize: 20,
          emptyMessage: 'Aucun mouvement sur ce compte.',
          columns: [
            colNumeroEcr, colDateEcr, colJournal,
            { key: 'libelle', label: 'Libellé' },
            { key: 'piece', label: 'Pièce' },
            colDebit, colCredit,
            {
              key: 'soldeProgressif', label: 'Solde', align: 'right', sortable: false,
              text: function (e) { return C.money(e.soldeProgressif, false); },
              render: function (e) {
                return el('span.font-semibold', {
                  class: e.soldeProgressif < 0 ? 'text-danger-600' : 'text-navy-900',
                  text: C.money(e.soldeProgressif, false),
                });
              },
            },
          ],
        }));
        U.icons(vue);
      }

      function imprimer() {
        var rows = avecSolde();
        var s = soldeCompte(selCompte.value);
        P.etat({
          titre: 'Grand livre',
          sousTitre: 'Compte ' + selCompte.value + ' — ' + compteLibelle(selCompte.value),
          cartouche: [['Compte', selCompte.value], ['Intitulé', compteLibelle(selCompte.value)],
            ['Mouvements', C.num(rows.length)], ['Total débit', C.money(s.debit)],
            ['Total crédit', C.money(s.credit)], ['Solde', C.money(s.solde)]],
          contenu: P.tableau([
            { label: 'Date', value: function (e) { return C.dateFR(e.date); } },
            { label: 'N° pièce', key: 'numero' },
            { label: 'Journal', key: 'journal' },
            { label: 'Libellé', key: 'libelle' },
            { label: 'Débit', align: 'right', value: function (e) { return e.debit ? C.money(e.debit, false) : ''; },
              somme: function (e) { return e.debit || 0; } },
            { label: 'Crédit', align: 'right', value: function (e) { return e.credit ? C.money(e.credit, false) : ''; },
              somme: function (e) { return e.credit || 0; } },
            { label: 'Solde', align: 'right', value: function (e) { return C.money(e.soldeProgressif, false); } },
          ], rows, { total: true }),
          signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' }],
        });
      }

      function imprimerComplet() {
        var blocs = el('div.space-y-4');
        C.sortBy(mouvementes, 'num').forEach(function (c) {
          var s = soldeCompte(c.num);
          var mvts = C.sortBy(ecritures().filter(function (e) { return e.compte === c.num; }), 'date');
          blocs.appendChild(el('div', null, [
            el('p.mb-1.mt-3.text-\\[11px\\].font-bold.text-navy-900', { text: c.num + ' — ' + c.libelle + '  (solde : ' + C.money(s.solde, false) + ')' }),
            P.tableau([
              { label: 'Date', value: function (e) { return C.dateFR(e.date); } },
              { label: 'N° pièce', key: 'numero' },
              { label: 'Libellé', key: 'libelle' },
              { label: 'Débit', align: 'right', value: function (e) { return e.debit ? C.money(e.debit, false) : ''; } },
              { label: 'Crédit', align: 'right', value: function (e) { return e.credit ? C.money(e.credit, false) : ''; } },
            ], mvts.slice(0, 15)),
          ]));
        });
        P.etat({
          titre: 'Grand livre général',
          sousTitre: 'Exercice ' + exo() + ' — tous comptes mouvementés',
          cartouche: [['Comptes mouvementés', C.num(mouvementes.length)],
            ['Écritures', C.num(ecritures().length)],
            ['Total débit', C.money(C.sum(ecritures(), 'debit'))],
            ['Total crédit', C.money(C.sum(ecritures(), 'credit'))]],
          contenu: blocs,
          signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * BALANCE
   * ======================================================================== */
  global.SIGH.screen('m12-balance', {
    title: 'Balance générale & âgée',
    description: 'Balance des comptes, contrôle d’équilibre et balance âgée des comptes de tiers.',
    regle: 'Écran en lecture seule. La balance est <strong>calculée à partir des écritures validées</strong>. Elle ne se saisit pas : corriger l’écriture concernée pour la faire évoluer.',
    render: function (root) {
      var host = el('div.space-y-4');

      var lignes = comptes().map(function (c) {
        var s = soldeCompte(c.num);
        return {
          id: c.num, num: c.num, libelle: c.libelle, classe: c.classe,
          debit: s.debit, credit: s.credit,
          soldeDebiteur: s.solde > 0 ? s.solde : 0,
          soldeCrediteur: s.solde < 0 ? -s.solde : 0,
          nb: s.nb,
        };
      }).filter(function (l) { return l.nb > 0; });
      /* Écart E725 : deux fiches du plan au même numéro (631810) faisaient compter DEUX fois les mouvements du compte — la balance annonçait un
         déséquilibre RG-10 de 1 954 000 F qui n'existait pas dans le journal. UNE ligne par numéro de compte. */
      var numsVus = {};
      lignes = lignes.filter(function (l) { if (numsVus[l.num]) return false; numsVus[l.num] = true; return true; });

      var totalDebit = C.sum(lignes, 'debit');
      var totalCredit = C.sum(lignes, 'credit');
      var equilibre = totalDebit === totalCredit;

      host.appendChild(U.kpiGrid([
        { label: 'Comptes mouvementés', value: C.num(lignes.length), icon: 'list', tone: 'navy' },
        { label: 'Total débit', value: C.money(totalDebit), icon: 'arrow-down-left', tone: 'warning' },
        { label: 'Total crédit', value: C.money(totalCredit), icon: 'arrow-up-right', tone: 'success' },
        {
          label: 'Équilibre (RG-10)', value: equilibre ? 'Équilibrée' : C.money(Math.abs(totalDebit - totalCredit)),
          icon: equilibre ? 'scale' : 'scale-3d', tone: equilibre ? 'success' : 'danger',
        },
      ]));

      host.appendChild(equilibre
        ? K.note('La balance est <strong>équilibrée</strong> : le total des débits est égal au total des crédits (RG-10).', { tone: 'success', icon: 'scale' })
        : K.note('<strong>Balance déséquilibrée</strong> — écart de ' + C.money(Math.abs(totalDebit - totalCredit))
          + '. Ce contrôle doit être régularisé avant toute clôture (RG-10).', { tone: 'danger', icon: 'scale-3d' }));

      host.appendChild(U.tabs([
        {
          id: 'generale', label: 'Balance générale',
          render: function () {
            return U.dataTable({
              rows: lignes, exportName: 'balance-generale', pageSize: 25,
              defaultSort: 'num',
              filters: [{ name: 'classe', label: 'Classe', options: [1, 2, 3, 4, 5, 6, 7, 8].map(function (n) { return { value: String(n), label: classeLibelle(n) }; }), match: function (l, v) { return String(l.classe) === v; } }],
              columns: [
                { key: 'num', label: 'Compte', nowrap: true, render: function (l) { return el('span.font-mono.text-xs.font-semibold', { text: l.num }); } },
                { key: 'libelle', label: 'Intitulé' },
                { key: 'classe', label: 'Classe', align: 'right', render: function (l) { return U.badge('C' + l.classe, 'neutral'); } },
                { key: 'nb', label: 'Mvts', align: 'right' },
                { key: 'debit', label: 'Mouvement débit', align: 'right', text: function (l) { return C.money(l.debit, false); }, render: function (l) { return C.money(l.debit, false); } },
                { key: 'credit', label: 'Mouvement crédit', align: 'right', text: function (l) { return C.money(l.credit, false); }, render: function (l) { return C.money(l.credit, false); } },
                { key: 'soldeDebiteur', label: 'Solde débiteur', align: 'right', text: function (l) { return l.soldeDebiteur ? C.money(l.soldeDebiteur, false) : ''; }, render: function (l) { return l.soldeDebiteur ? el('span.font-semibold', { text: C.money(l.soldeDebiteur, false) }) : '—'; } },
                { key: 'soldeCrediteur', label: 'Solde créditeur', align: 'right', text: function (l) { return l.soldeCrediteur ? C.money(l.soldeCrediteur, false) : ''; }, render: function (l) { return l.soldeCrediteur ? el('span.font-semibold', { text: C.money(l.soldeCrediteur, false) }) : '—'; } },
              ],
              actions: [K.btn('Imprimer la balance', { size: 'sm', icon: 'printer', onclick: imprimerBalance })],
            });
          },
        },
        {
          id: 'agee', label: 'Balance âgée (tiers)',
          render: function () {
            var factures = S.collection('factures').active();
            var tranches = [
              { label: 'Moins de 30 jours', min: 0, max: 30 },
              { label: '30 à 60 jours', min: 30, max: 60 },
              { label: '60 à 90 jours', min: 60, max: 90 },
              { label: 'Plus de 90 jours', min: 90, max: 99999 },
            ];
            var rows = tranches.map(function (t) {
              var sel = factures.filter(function (f) {
                var j = C.daysBetween(f.date, AUJ);
                return f.reliquat > 0 && j >= t.min && j < t.max;
              });
              var selAss = factures.filter(function (f) {
                var j = C.daysBetween(f.date, AUJ);
                return f.assureur && j >= t.min && j < t.max;
              });
              return {
                id: t.label, tranche: t.label,
                nbPatients: sel.length, montantPatients: C.sum(sel, 'reliquat'),
                nbAssureurs: selAss.length, montantAssureurs: C.sum(selAss, 'partAssurance'),
                total: C.sum(sel, 'reliquat') + C.sum(selAss, 'partAssurance'),
              };
            });
            return el('div.space-y-3', null, [
              K.note('La balance âgée ventile les créances par ancienneté afin de piloter le recouvrement auprès des patients et des tiers payeurs.', { tone: 'info' }),
              U.dataTable({
                rows: rows, exportName: 'balance-agee', searchable: false, pageSize: 10,
                columns: [
                  { key: 'tranche', label: 'Ancienneté' },
                  { key: 'nbPatients', label: 'Factures patients', align: 'right' },
                  { key: 'montantPatients', label: 'Créances patients', align: 'right', text: function (r) { return C.money(r.montantPatients, false); }, render: function (r) { return C.money(r.montantPatients, false); } },
                  { key: 'nbAssureurs', label: 'Factures assureurs', align: 'right' },
                  { key: 'montantAssureurs', label: 'Créances assureurs', align: 'right', text: function (r) { return C.money(r.montantAssureurs, false); }, render: function (r) { return C.money(r.montantAssureurs, false); } },
                  { key: 'total', label: 'Total', align: 'right', text: function (r) { return C.money(r.total, false); }, render: function (r) { return el('span.font-bold.text-navy-900', { text: C.money(r.total, false) }); } },
                ],
                actions: [K.btn('Imprimer la balance âgée', {
                  size: 'sm', icon: 'printer',
                  onclick: function () {
                    P.etat({
                      titre: 'Balance âgée des comptes de tiers',
                      sousTitre: 'Situation au ' + C.dateFR(AUJ),
                      cartouche: [['Créances totales', C.money(C.sum(rows, 'total'))],
                        ['Dont patients', C.money(C.sum(rows, 'montantPatients'))],
                        ['Dont assureurs', C.money(C.sum(rows, 'montantAssureurs'))],
                        ['Date d’édition', C.dateFR(AUJ)]],
                      /* Les tranches d'ancienneté se totalisent : c'est la
                         somme des créances que le lecteur vient chercher, et
                         le tableau n'est ni tronqué ni hétérogène. */
                      contenu: P.tableau([
                        { label: 'Ancienneté', key: 'tranche' },
                        { label: 'Factures patients', key: 'nbPatients', align: 'right',
                          somme: function (r) { return r.nbPatients; },
                          formatTotal: function (v) { return C.num(v); } },
                        { label: 'Créances patients', align: 'right',
                          value: function (r) { return C.money(r.montantPatients, false); },
                          somme: function (r) { return r.montantPatients; } },
                        { label: 'Factures assureurs', key: 'nbAssureurs', align: 'right',
                          somme: function (r) { return r.nbAssureurs; },
                          formatTotal: function (v) { return C.num(v); } },
                        { label: 'Créances assureurs', align: 'right',
                          value: function (r) { return C.money(r.montantAssureurs, false); },
                          somme: function (r) { return r.montantAssureurs; } },
                        { label: 'Total', align: 'right',
                          value: function (r) { return C.money(r.total, false); },
                          somme: function (r) { return r.total; } },
                      ], rows, { total: true, totalLabel: 'TOTAL DES CRÉANCES' }),
                      signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
                        { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
                    });
                  },
                })],
              }),
            ]);
          },
        },
      ]));
      root.appendChild(host);
      return null;

      function imprimerBalance() {
        P.etat({
          titre: 'Balance générale des comptes',
          sousTitre: 'Exercice ' + exo() + ' — situation au ' + C.dateFR(AUJ),
          cartouche: [['Comptes mouvementés', C.num(lignes.length)],
            ['Total débit', C.money(totalDebit)], ['Total crédit', C.money(totalCredit)],
            ['Équilibre', equilibre ? 'Équilibrée' : 'Écart de ' + C.money(Math.abs(totalDebit - totalCredit))],
            ['Exercice', String(exo())], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'Compte', key: 'num' },
            { label: 'Intitulé', key: 'libelle' },
            { label: 'Mvt débit', align: 'right', value: function (l) { return C.money(l.debit, false); }, somme: function (l) { return l.debit; } },
            { label: 'Mvt crédit', align: 'right', value: function (l) { return C.money(l.credit, false); }, somme: function (l) { return l.credit; } },
            { label: 'Solde débiteur', align: 'right', value: function (l) { return l.soldeDebiteur ? C.money(l.soldeDebiteur, false) : ''; }, somme: function (l) { return l.soldeDebiteur; } },
            { label: 'Solde créditeur', align: 'right', value: function (l) { return l.soldeCrediteur ? C.money(l.soldeCrediteur, false) : ''; }, somme: function (l) { return l.soldeCrediteur; } },
          ], C.sortBy(lignes, 'num'), { total: true, totalLabel: 'TOTAUX' }),
          signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * COMPTABILITÉ ANALYTIQUE
   * ======================================================================== */
  global.SIGH.screen('m12-analytique', {
    title: 'Comptabilité analytique',
    description: 'Charges et produits ventilés par centre de coûts et par secteur d’activité.',
    regle: 'Écran en lecture seule. La ventilation analytique est <strong>déduite du centre de coûts porté par chaque écriture</strong>. Elle se corrige en modifiant l’écriture.',
    render: function (root) {
      var host = el('div.space-y-4');
      var e = ecritures();

      var rows = D.CENTRES_COUT.map(function (cc) {
        var sel = e.filter(function (x) { return x.centreCout === cc.id; });
        var charges = C.sum(sel.filter(function (x) { return String(x.compte)[0] === '6'; }), 'debit');
        var produits = C.sum(sel.filter(function (x) { return String(x.compte)[0] === '7'; }), 'credit');
        return {
          id: cc.id, centre: cc.label, nb: sel.length,
          charges: charges, produits: produits, resultat: produits - charges,
          marge: produits ? Math.round((produits - charges) / produits * 100) : 0,
        };
      });

      host.appendChild(U.kpiGrid([
        { label: 'Centres de coûts', value: C.num(rows.length), icon: 'layers', tone: 'navy' },
        { label: 'Produits analysés', value: C.money(C.sum(rows, 'produits')), icon: 'trending-up', tone: 'success' },
        { label: 'Charges analysées', value: C.money(C.sum(rows, 'charges')), icon: 'trending-down', tone: 'warning' },
        { label: 'Résultat analytique', value: C.money(C.sum(rows, 'resultat')), icon: 'scale', tone: C.sum(rows, 'resultat') >= 0 ? 'success' : 'danger' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Résultat par centre de coûts', rows: rows, exportName: 'analytique', pageSize: 15,
        defaultSort: 'resultat', defaultDir: 'desc', searchable: false,
        columns: [
          { key: 'centre', label: 'Centre de coûts / secteur' },
          { key: 'nb', label: 'Écritures', align: 'right' },
          { key: 'produits', label: 'Produits', align: 'right', text: function (r) { return C.money(r.produits, false); }, render: function (r) { return el('span.text-success-700', { text: C.money(r.produits, false) }); } },
          { key: 'charges', label: 'Charges', align: 'right', text: function (r) { return C.money(r.charges, false); }, render: function (r) { return el('span.text-danger-600', { text: C.money(r.charges, false) }); } },
          {
            key: 'resultat', label: 'Résultat', align: 'right',
            text: function (r) { return C.money(r.resultat, false); },
            render: function (r) {
              return el('span.font-bold', { class: r.resultat >= 0 ? 'text-success-700' : 'text-danger-600', text: C.money(r.resultat, false) });
            },
          },
          {
            key: 'marge', label: 'Marge', align: 'right',
            render: function (r) { return r.produits ? U.badge(r.marge + ' %', r.marge >= 0 ? 'success' : 'danger') : '—'; },
          },
        ],
        actions: [K.btn('Imprimer la balance analytique', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Balance analytique',
              sousTitre: 'Résultat par centre de coûts — exercice ' + exo(),
              cartouche: [['Centres de coûts', C.num(rows.length)],
                ['Produits', C.money(C.sum(rows, 'produits'))],
                ['Charges', C.money(C.sum(rows, 'charges'))],
                ['Résultat', C.money(C.sum(rows, 'resultat'))]],
              contenu: P.tableau([
                { label: 'Centre de coûts', key: 'centre' },
                { label: 'Écritures', key: 'nb', align: 'right' },
                { label: 'Produits', align: 'right', value: function (r) { return C.money(r.produits, false); },
                  somme: function (r) { return r.produits || 0; } },
                { label: 'Charges', align: 'right', value: function (r) { return C.money(r.charges, false); },
                  somme: function (r) { return r.charges || 0; } },
                { label: 'Résultat', align: 'right', value: function (r) { return C.money(r.resultat, false); },
                  somme: function (r) { return r.resultat || 0; } },
              ], rows, { total: true }),
              signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
                { role: 'La Direction', nom: 'BASSONGUI Chabi Séko' }],
            });
          },
        })],
      }));

      host.appendChild(K.charts([
        {
          title: 'Résultat par centre de coûts',
          render: function () {
            var tri = C.sortBy(rows, 'resultat', 'desc');
            return G.barres(tri.map(function (r) { return r.centre; }), [
              { label: 'Produits', data: tri.map(function (r) { return r.produits; }), color: G.TONES.vert },
              { label: 'Charges', data: tri.map(function (r) { return r.charges; }), color: G.TONES.rouge },
            ], { horizontal: true, height: 340 });
          },
        },
        {
          title: 'Poids des secteurs dans les produits',
          render: function () {
            var avec = rows.filter(function (r) { return r.produits > 0; });
            return G.anneau(avec.map(function (r) { return r.centre; }), avec.map(function (r) { return r.produits; }), { legend: 'bottom' });
          },
        },
      ]));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * BUDGETS
   * ======================================================================== */
  global.SIGH.screen('m12-budgets', {
    title: 'Budgets',
    description: 'Budgétisation par centre de coûts et suivi du réalisé par rapport au prévisionnel.',
    render: function (root) {
      var col = S.collection('budgets', { module: 'M12', entite: 'Budget' });
      if (!col.all().length && S.amorcable('budgets')) {
        var rnd = C.seeded(2213);
        D.CENTRES_COUT.forEach(function (cc, i) {
          var prevu = C.between(rnd, 3, 40) * 500000;
          col.all().push({
            id: 'BUD' + C.pad(i + 1, 3), statut: 'actif',
            reference: 'BG-2026-' + C.pad(i + 1, 3),
            exercice: 2026, centreCout: cc.id, centre: cc.label,
            nature: 'Charges de fonctionnement',
            prevu: prevu,
          });
        });
        S.save();
      }

      var e = ecritures();
      function realise(centreId) {
        return C.sum(e.filter(function (x) { return x.centreCout === centreId && String(x.compte)[0] === '6'; }), 'debit');
      }

      return K.crud({
        collection: 'budgets', entite: 'budget', entiteP: 'budgets', module: 'M12',
        defaultSort: 'prevu', defaultDir: 'desc', pageSize: 15,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (b) { return el('span.font-mono.text-xs', { text: b.reference }); } },
          { key: 'exercice', label: 'Exercice', align: 'right' },
          { key: 'centre', label: 'Centre de coûts' },
          { key: 'nature', label: 'Nature' },
          { key: 'prevu', label: 'Budget prévu', align: 'right', text: function (b) { return C.money(b.prevu, false); }, render: function (b) { return el('span.font-semibold', { text: C.money(b.prevu, false) }); } },
          {
            key: 'realise', label: 'Réalisé', align: 'right',
            value: function (b) { return realise(b.centreCout); },
            text: function (b) { return C.money(realise(b.centreCout), false); },
            render: function (b) { return C.money(realise(b.centreCout), false); },
          },
          {
            key: 'ecart', label: 'Disponible', align: 'right',
            value: function (b) { return b.prevu - realise(b.centreCout); },
            text: function (b) { return C.money(b.prevu - realise(b.centreCout), false); },
            render: function (b) {
              var d = b.prevu - realise(b.centreCout);
              return el('span.font-semibold', { class: d < 0 ? 'text-danger-600' : 'text-success-700', text: C.money(d, false) });
            },
          },
          {
            key: 'consommation', label: 'Consommation', align: 'right',
            value: function (b) { return b.prevu ? Math.round(realise(b.centreCout) / b.prevu * 100) : 0; },
            render: function (b) {
              var pct = b.prevu ? Math.round(realise(b.centreCout) / b.prevu * 100) : 0;
              var wrap = el('div.flex.items-center.justify-end.gap-2');
              wrap.appendChild(el('div.h-1\\.5.w-20.overflow-hidden.rounded-full.bg-slate-100', null,
                el('div.h-full.rounded-full', {
                  class: pct > 100 ? 'bg-danger-500' : (pct > 80 ? 'bg-warning-500' : 'bg-success-500'),
                  style: 'width:' + Math.min(100, Math.max(2, pct)) + '%;',
                })));
              wrap.appendChild(el('span.w-10.text-right.text-xs.num.font-medium', { text: pct + ' %' }));
              return wrap;
            },
          },
        ],
        fields: [
          { name: 'exercice', label: 'Exercice', type: 'number', required: true, value: 2026 },
          { name: 'centreCout', label: 'Centre de coûts', type: 'select', required: true, options: optionsCentres() },
          { name: 'nature', label: 'Nature budgétaire', type: 'select', required: true, options: ['Charges de fonctionnement', 'Investissements', 'Charges de personnel', 'Achats de marchandises'] },
          { name: 'prevu', label: 'Montant prévisionnel (FCFA)', type: 'money', required: true, min: 0 },
        ],
        transform: function (v) {
          v.centre = centreLabel(v.centreCout);
          if (!v.reference) v.reference = C.nextRef('BG-2026-', 3);
          return v;
        },
        kpis: function (rows) {
          var prevu = C.sum(rows, 'prevu');
          var real = C.sum(rows, function (b) { return realise(b.centreCout); });
          return [
            { label: 'Budget total prévu', value: C.money(prevu), icon: 'target', tone: 'navy' },
            { label: 'Budget consommé', value: C.money(real), icon: 'trending-down', tone: 'warning' },
            { label: 'Disponible', value: C.money(prevu - real), icon: 'wallet', tone: prevu - real >= 0 ? 'success' : 'danger' },
            { label: 'Taux de consommation', value: C.pct(prevu ? real / prevu * 100 : 0), icon: 'percent', tone: 'info' },
          ];
        },
        extraTabs: [{
          id: 'suivi', label: 'Budget vs réalisé',
          render: function () {
            var rows = col.active();
            return U.card('Comparaison budget prévisionnel et réalisé',
              G.barres(rows.map(function (b) { return b.centre; }), [
                { label: 'Prévu', data: rows.map(function (b) { return b.prevu; }), color: G.TONES.navy },
                { label: 'Réalisé', data: rows.map(function (b) { return realise(b.centreCout); }), color: G.TONES.orange },
              ], { horizontal: true, height: 380 }));
          },
        }],
      })(root);
    },
  });

  /* ==========================================================================
   * IMMOBILISATIONS & AMORTISSEMENTS
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * LE LIEN AVEC LE BILAN
   * --------------------------------------------------------------------------
   * Le registre des immobilisations n'est pas une liste à part : ses trois
   * colonnes SONT les colonnes BRUT / AMORT. / NET de l'actif immobilisé du
   * bilan (liasse DGI, rubriques AI et AZ). Les afficher séparément laissait
   * croire à deux comptes distincts, et personne ne pouvait vérifier que le
   * bilan disait ce que le registre porte.
   *
   * Le rattachement se fait par le COMPTE d'immobilisation, celui du plan
   * SYSCOHADA : 231/232 bâtiments, 241 matériel, 245 transport, 22 terrains.
   * ------------------------------------------------------------------------ */
  var RUBRIQUES_BILAN_IMMO = [
    /* Incorporelles — sous-total AD de la liasse. */
    { ref: 'AE', famille: 'AD', libelle: 'Frais de développement et de prospection', comptes: ['211'] },
    { ref: 'AF', famille: 'AD', libelle: 'Brevets, licences, logiciels et droits similaires', comptes: ['212', '213', '214'] },
    { ref: 'AG', famille: 'AD', libelle: 'Fonds commercial et droit au bail', comptes: ['215', '216'] },
    { ref: 'AH', famille: 'AD', libelle: 'Autres immobilisations incorporelles', comptes: ['217', '218'] },
    /* Corporelles — sous-total AI. « 229 Immobilisations en cours » n'est PAS
       un terrain : le préfixe 22 seul l'y aurait rangé. */
    { ref: 'AJ', famille: 'AI', libelle: 'Terrains', comptes: ['221', '222', '223', '224', '225', '226', '227', '228'] },
    { ref: 'AK', famille: 'AI', libelle: 'Bâtiments', comptes: ['231', '232', '233', '234'] },
    { ref: 'AL', famille: 'AI', libelle: 'Aménagements, agencements et installations', comptes: ['235', '237', '238'] },
    { ref: 'AM', famille: 'AI', libelle: 'Matériel, mobilier et actifs biologiques', comptes: ['241', '243', '244', '246', '247', '248'] },
    { ref: 'AN', famille: 'AI', libelle: 'Matériel de transport', comptes: ['245'] },
    /* Financières — sous-total AQ. */
    { ref: 'AR', famille: 'AQ', libelle: 'Titres de participation', comptes: ['26'] },
    { ref: 'AS', famille: 'AQ', libelle: 'Autres immobilisations financières', comptes: ['27'] },
  ];
  var FAMILLES_BILAN_IMMO = [
    { ref: 'AD', libelle: 'IMMOBILISATIONS INCORPORELLES' },
    { ref: 'AI', libelle: 'IMMOBILISATIONS CORPORELLES' },
    { ref: 'AQ', libelle: 'IMMOBILISATIONS FINANCIÈRES' },
  ];
  function rubriqueBilanDe(im) {
    var num = String(im.compte || '');
    for (var i = 0; i < RUBRIQUES_BILAN_IMMO.length; i++) {
      var r = RUBRIQUES_BILAN_IMMO[i];
      for (var j = 0; j < r.comptes.length; j++) {
        if (num.indexOf(r.comptes[j]) === 0) return r;
      }
    }
    return null;
  }

  global.SIGH.screen('m12-immobilisations', {
    title: 'Immobilisations & amortissements',
    description: 'Registre des immobilisations, plan d’amortissement SEMESTRIEL, cessions et report au bilan.',
    regle: 'L’amortissement court de la <strong>date d’acquisition</strong> à aujourd’hui, par pas de '
      + '<strong>six mois</strong> : l’annuité ne se constate qu’à la clôture et donnait le même '
      + 'amortissement à un bien acquis en février et à un bien acquis en novembre. Un bien '
      + '<strong>cédé</strong> cesse de s’amortir à sa date de sortie et quitte le bilan — sa fiche, '
      + 'elle, reste au registre. Les totaux du registre <strong>SONT</strong> les colonnes BRUT / '
      + 'AMORT. / NET de l’actif immobilisé du bilan.',
    render: function (root) {
      var col = S.collection('immobilisations', { module: 'M12', entite: 'Immobilisation' });
      if (!col.all().length && S.amorcable('immobilisations')) {
        var rnd = C.seeded(2311);
        var BIENS = [
          ['Échographe', 'Matériel médical', 8500000, 5, '241000'],
          ['Automate de biochimie', 'Matériel de laboratoire', 6200000, 5, '241000'],
          ['Groupe électrogène 30 kVA', 'Matériel technique', 4500000, 10, '241000'],
          ['Ambulance médicalisée', 'Matériel de transport', 18000000, 5, '245000'],
          ['Table d’opération', 'Matériel médical', 3200000, 10, '241000'],
          ['Lits d’hospitalisation (lot de 12)', 'Mobilier médical', 2400000, 10, '241000'],
          ['Onduleurs (lot)', 'Matériel technique', 1200000, 3, '241000'],
          ['Serveur et postes informatiques', 'Matériel informatique', 3800000, 3, '241000'],
          ['Climatiseurs (lot de 8)', 'Installations', 2800000, 5, '241000'],
          ['Stérilisateur autoclave', 'Matériel médical', 2100000, 8, '241000'],
        ];
        BIENS.forEach(function (b, i) {
          var acq = new Date(2020 + C.between(rnd, 0, 5), C.between(rnd, 0, 11), C.between(rnd, 1, 28));
          col.all().push({
            id: 'IMM' + C.pad(i + 1, 3), statut: 'actif',
            reference: 'IM-' + C.pad(i + 1, 3),
            designation: b[0], categorie: b[1],
            valeurAcquisition: b[2], dureeAmortissement: b[3], compte: b[4],
            dateAcquisition: C.iso(acq),
            fournisseur: C.pick(rnd, D.FOURNISSEURS).nom,
            etat: C.pick(rnd, ['En service', 'En service', 'En service', 'En maintenance']),
          });
        });
        S.save();
      }

      /* ------------------------------------------------------------------
       * AMORTISSEMENT PAR SEMESTRE, ET NON PAR ANNUITÉ (06/09/2026)
       * ------------------------------------------------------------------
       * L'annuité ne se constate qu'une fois l'exercice clos : un bien acquis
       * en février et un bien acquis en novembre portaient le même
       * amortissement au 31 décembre, ce qui surévaluait le second et
       * faussait la valeur nette au bilan. Le pas est donc le SEMESTRE, et il
       * court de la DATE D'ACQUISITION à la date du jour.
       *
       * Un bien CÉDÉ cesse de s'amortir à sa date de sortie : continuer
       * l'amortir ferait décroître un bien qui n'est plus au patrimoine.
       * ------------------------------------------------------------------ */
      /** Le report au bilan, rubrique par rubrique — et le TOTAL, calculé. */
      function blocReportBilan(rows) {
        var auBilan = rows.filter(function (i) { return !cede(i); });
        var sorties = rows.filter(cede);
        function chiffrer(sel) {
          return { nb: sel.length, brut: C.sum(sel, 'valeurAcquisition'),
            amort: C.sum(sel, amortiCumule), net: C.sum(sel, vnc) };
        }
        /* L'ordre de la LIASSE : chaque famille, son sous-total, puis le
           total de l'actif immobilisé (AZ). Une rubrique vide reste affichée —
           le formulaire officiel les porte toutes, et un lecteur qui compare
           au dépôt doit retrouver ses lignes. */
        var lignes = [];
        FAMILLES_BILAN_IMMO.forEach(function (f) {
          var deLaFamille = auBilan.filter(function (i) {
            var r = rubriqueBilanDe(i); return r && r.famille === f.ref;
          });
          lignes.push(Object.assign({ ref: f.ref, libelle: f.libelle, sousTotal: true }, chiffrer(deLaFamille)));
          RUBRIQUES_BILAN_IMMO.filter(function (r) { return r.famille === f.ref; }).forEach(function (r) {
            var sel = auBilan.filter(function (i) { return rubriqueBilanDe(i) === r; });
            lignes.push(Object.assign({ ref: r.ref, libelle: '   ' + r.libelle }, chiffrer(sel)));
          });
        });
        var horsRubrique = auBilan.filter(function (i) { return !rubriqueBilanDe(i); });
        if (horsRubrique.length) {
          lignes.push(Object.assign({ ref: '—',
            libelle: 'Compte non rattaché à une rubrique du bilan' }, chiffrer(horsRubrique)));
        }
        var totaux = chiffrer(auBilan);
        var totalBrut = totaux.brut, totalAmort = totaux.amort, totalNet = totaux.net;

        return el('div.space-y-3', null, [
          K.note('Ce tableau <strong>EST</strong> la rubrique « Immobilisations corporelles » (AI) de '
            + 'l’actif du bilan : ses trois colonnes sont celles de la liasse — BRUT, AMORT. et '
            + 'DÉPRÉC., NET. Le rattachement se fait par le <strong>compte SYSCOHADA</strong> porté par '
            + 'chaque bien, jamais par sa catégorie d’usage.', { tone: 'info', icon: 'link' }),
          U.card('Report à l’actif immobilisé — rubrique par rubrique',
            K.miniTable([
              { label: 'Réf.', key: 'ref' },
              { label: 'Rubrique du bilan', key: 'libelle' },
              { label: 'Biens', key: 'nb', align: 'right' },
              { label: 'Brut', align: 'right', render: function (l) { return C.money(l.brut, false); } },
              { label: 'Amort. et dépréc.', align: 'right', render: function (l) { return C.money(l.amort, false); } },
              { label: 'Net', align: 'right', render: function (l) { return C.money(l.net, false); } },
            ], lignes.concat([{
              ref: 'AZ', libelle: 'TOTAL ACTIF IMMOBILISÉ', nb: auBilan.length,
              brut: totalBrut, amort: totalAmort, net: totalNet,
            }]))),
          sorties.length
            ? K.note('<strong>' + C.num(sorties.length) + ' bien(s) sorti(s) du patrimoine</strong> ne '
              + 'figurent PAS dans ce report : un bien cédé n’est plus à l’actif. Ils restent au '
              + 'registre, avec leur date et leur motif de sortie.', { tone: 'warning', icon: 'log-out' })
            : null,
          el('div.flex.flex-wrap.gap-2', null, [
            K.btn('Ouvrir les états financiers', { icon: 'arrow-right', variant: 'primary',
              onclick: function () { global.SIGH.app.go('m12-etats-financiers'); } }),
            K.btn('Imprimer le report', { icon: 'printer', onclick: function () {
              P.etat({
                titre: 'Report des immobilisations à l’actif du bilan',
                sousTitre: 'Situation au ' + C.dateFR(AUJ),
                cartouche: [['Biens au patrimoine', C.num(auBilan.length)],
                  ['Biens sortis', C.num(sorties.length)],
                  ['Mode d’amortissement', 'Linéaire, pas semestriel']],
                contenu: P.tableau([
                  { label: 'Réf.', key: 'ref' }, { label: 'Rubrique', key: 'libelle' },
                  /* Le total ne compte QUE les lignes de détail : additionner
                     aussi les sous-totaux de famille doublerait la colonne. */
                  { label: 'Brut', align: 'right', value: function (l) { return C.money(l.brut, false); },
                    somme: function (l) { return l.sousTotal ? 0 : l.brut; } },
                  { label: 'Amort. et dépréc.', align: 'right', value: function (l) { return C.money(l.amort, false); },
                    somme: function (l) { return l.sousTotal ? 0 : l.amort; } },
                  { label: 'Net', align: 'right', value: function (l) { return C.money(l.net, false); },
                    somme: function (l) { return l.sousTotal ? 0 : l.net; } },
                ], lignes, { total: true, totalLabel: 'TOTAL ACTIF IMMOBILISÉ' }),
                signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
                  { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
              });
            } }),
          ]),
        ].filter(Boolean));
      }

      var MOIS_SEMESTRE = 6;
      function semestresTotal(im) { return Math.max(1, Math.round((im.dureeAmortissement || 1) * 12 / MOIS_SEMESTRE)); }
      function dotationSemestre(im) { return Math.round(im.valeurAcquisition / semestresTotal(im)); }
      /** Le terme du calcul : la date de cession si le bien est sorti, sinon aujourd'hui. */
      function borneAmortissement(im) { return im.dateCession ? C.toDate(im.dateCession) : AUJ; }
      function moisEcoules(im) {
        var d = C.toDate(im.dateAcquisition), f = borneAmortissement(im);
        var m = (f.getFullYear() - d.getFullYear()) * 12 + (f.getMonth() - d.getMonth());
        if (f.getDate() < d.getDate()) m--;
        return Math.max(0, m);
      }
      function semestresEcoules(im) {
        return Math.min(semestresTotal(im), Math.floor(moisEcoules(im) / MOIS_SEMESTRE));
      }
      function anneesEcoulees(im) { return Math.floor(moisEcoules(im) / 12); }
      /* Le dernier semestre solde le reliquat : la somme des dotations doit
         faire EXACTEMENT la valeur d'acquisition, à l'arrondi près. */
      function amortiCumule(im) {
        var n = semestresEcoules(im);
        if (n >= semestresTotal(im)) return im.valeurAcquisition;
        return dotationSemestre(im) * n;
      }
      function vnc(im) { return Math.max(0, im.valeurAcquisition - amortiCumule(im)); }
      function cede(im) { return !!im.dateCession || im.etat === 'Cédé'; }

      /** Le plan d'amortissement, semestre par semestre. */
      function planAmortissement(im) {
        var plan = [], reste = im.valeurAcquisition, total = semestresTotal(im);
        var d = C.toDate(im.dateAcquisition);
        for (var s = 1; s <= total; s++) {
          var dot = s === total ? reste : dotationSemestre(im);
          reste -= dot;
          var debut = new Date(d.getFullYear(), d.getMonth() + (s - 1) * MOIS_SEMESTRE, 1);
          plan.push({
            rang: s,
            periode: 'S' + (debut.getMonth() < 6 ? 1 : 2) + ' ' + debut.getFullYear(),
            base: im.valeurAcquisition, dotation: dot,
            cumul: im.valeurAcquisition - reste, vnc: reste,
            couru: s <= semestresEcoules(im),
          });
        }
        return plan;
      }

      return K.crud({
        collection: 'immobilisations', entite: 'immobilisation', entiteP: 'immobilisations', module: 'M12',
        defaultSort: 'valeurAcquisition', defaultDir: 'desc', pageSize: 15, drawerWidth: 'max-w-2xl',
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (i) { return el('span.font-mono.text-xs', { text: i.reference }); } },
          { key: 'designation', label: 'Désignation' },
          { key: 'categorie', label: 'Catégorie', render: function (i) { return U.badge(i.categorie, 'navy'); } },
          { key: 'dateAcquisition', label: 'Date d’acquisition', nowrap: true, text: function (i) { return C.dateFR(i.dateAcquisition); }, render: function (i) { return C.dateFR(i.dateAcquisition); } },
          { key: 'valeurAcquisition', label: 'Valeur d’acquisition', align: 'right', text: function (i) { return C.money(i.valeurAcquisition, false); }, render: function (i) { return el('span.font-semibold', { text: C.money(i.valeurAcquisition, false) }); } },
          { key: 'dureeAmortissement', label: 'Durée', align: 'right',
            render: function (i) { return i.dureeAmortissement + ' ans (' + semestresTotal(i) + ' sem.)'; } },
          /* CESSION / SORTIE : un bien sorti reste au registre — c'est la
             pièce qu'on ressort au contrôle — mais il cesse de s'amortir et
             sort du bilan. La colonne le dit plutôt que de le laisser deviner
             derrière un état. */
          { key: 'dateCession', label: 'Cession / sortie', nowrap: true,
            text: function (i) { return i.dateCession ? C.dateFR(i.dateCession) : ''; },
            render: function (i) {
              if (!i.dateCession) return el('span.text-slate-300', { text: '—' });
              return el('div', null, [
                el('p.text-xs.font-medium.text-slate-700', { text: C.dateFR(i.dateCession) }),
                el('p.text-xs.text-slate-400', { text: (i.motifSortie || 'Sortie')
                  + (i.valeurCession ? ' · ' + C.money(i.valeurCession, false) : '') }),
              ]);
            } },
          { key: 'cumul', label: 'Amort. cumulé', align: 'right', value: amortiCumule, text: function (i) { return C.money(amortiCumule(i), false); }, render: function (i) { return el('span.text-danger-600', { text: C.money(amortiCumule(i), false) }); } },
          {
            key: 'vnc', label: 'Valeur nette', align: 'right',
            value: vnc, text: function (i) { return C.money(vnc(i), false); },
            render: function (i) { return el('span.font-bold.text-navy-900', { text: C.money(vnc(i), false) }); },
          },
          { key: 'etat', label: 'État', render: function (i) { return U.badge(i.etat, i.etat === 'En service' ? 'success' : 'warning'); } },
        ],
        fields: [
          { name: 'designation', label: 'Désignation du bien', required: true, col: 'full' },
          { name: 'categorie', label: 'Catégorie', type: 'select', required: true, options: ['Matériel médical', 'Matériel de laboratoire', 'Matériel technique', 'Matériel de transport', 'Mobilier médical', 'Matériel informatique', 'Installations'] },
          { name: 'dateAcquisition', label: 'Date d’acquisition', type: 'date', required: true },
          { name: 'valeurAcquisition', label: 'Valeur d’acquisition (FCFA)', type: 'money', required: true, min: 0 },
          { name: 'dureeAmortissement', label: 'Durée d’amortissement (années)', type: 'number', required: true, min: 1, max: 30 },
          { name: 'compte', label: 'Compte d’immobilisation', type: 'select', options: D.PLAN_COMPTABLE.filter(function (c) { return c.classe === 2; }).map(function (c) { return { value: c.num, label: c.num + ' — ' + c.libelle }; }) },
          { name: 'fournisseur', label: 'Fournisseur' },
          { name: 'etat', label: 'État', type: 'select', options: ['En service', 'En maintenance', 'Hors service', 'Cédé'] },
          { name: '_sectionSortie', type: 'section', label: 'Cession ou sortie du patrimoine' },
          { name: 'dateCession', label: 'Date de cession / sortie', type: 'date',
            hint: 'Renseignée, elle ARRÊTE l’amortissement à cette date et sort le bien du bilan.' },
          { name: 'valeurCession', label: 'Prix de cession (FCFA)', type: 'money', min: 0 },
          { name: 'motifSortie', label: 'Motif de la sortie', type: 'select',
            options: ['Cession', 'Réforme', 'Destruction', 'Vol ou perte', 'Don'] },
        ],
        transform: function (v) { if (!v.reference) v.reference = C.nextRef('IM-', 3); return v; },
        onCreate: function () { return { dateAcquisition: C.iso(AUJ), dureeAmortissement: 5, etat: 'En service', compte: '241000' }; },
        filters: [
          { name: 'categorie', label: 'Catégorie', options: ['Matériel médical', 'Matériel de laboratoire', 'Matériel technique', 'Matériel de transport', 'Mobilier médical', 'Matériel informatique', 'Installations'] },
          { name: 'etat', label: 'État', options: ['En service', 'En maintenance', 'Hors service', 'Cédé'] },
        ],
        kpis: function (rows) {
          /* LE LIEN AVEC LE BILAN : ces trois totaux SONT les colonnes BRUT,
             AMORT. et NET de la rubrique AI « Immobilisations corporelles »
             du bilan (liasse DGI). Les biens SORTIS en sont exclus — un bien
             cédé n'est plus au patrimoine. */
          var auBilan = rows.filter(function (i) { return !cede(i); });
          return [
            { label: 'Immobilisations', value: C.num(rows.length), icon: 'building', tone: 'navy',
              hint: C.num(rows.length - auBilan.length) + ' sortie(s) du patrimoine' },
            { label: 'Valeur d’acquisition (BRUT)', value: C.money(C.sum(auBilan, 'valeurAcquisition')),
              icon: 'banknote', tone: 'info', hint: 'Colonne BRUT du bilan — rubrique AI' },
            { label: 'Amortissements cumulés', value: C.money(C.sum(auBilan, amortiCumule)),
              icon: 'trending-down', tone: 'warning', hint: 'Colonne AMORT. et DÉPRÉC. du bilan' },
            { label: 'Valeur nette comptable', value: C.money(C.sum(auBilan, vnc)),
              icon: 'wallet', tone: 'success', hint: 'Colonne NET du bilan — reportée à l’actif immobilisé' },
          ];
        },
        extraTabs: [{
          id: 'bilan', label: 'Report au bilan',
          render: function () { return blocReportBilan(col.active()); },
        }],
        detail: function (im) {
          var plan = planAmortissement(im);
          return el('div.space-y-4', null, [
            U.kpiGrid([
              { label: 'Valeur d’acquisition', value: C.money(im.valeurAcquisition), icon: 'banknote', tone: 'navy' },
              { label: 'Amortissements cumulés', value: C.money(amortiCumule(im)), icon: 'trending-down', tone: 'warning' },
              { label: 'Valeur nette comptable', value: C.money(vnc(im)), icon: 'wallet', tone: 'success' },
            ], 'grid-cols-3'),
            U.descList([['Référence', im.reference], ['Désignation', im.designation],
              ['Catégorie', im.categorie], ['Compte', im.compte],
              ['Date d’acquisition', C.dateFR(im.dateAcquisition)],
              ['Durée d’amortissement', im.dureeAmortissement + ' ans, soit ' + semestresTotal(im) + ' semestres'],
              ['Dotation semestrielle', C.money(dotationSemestre(im))],
              ['Semestres courus', semestresEcoules(im) + ' / ' + semestresTotal(im)
                + ' (' + anneesEcoulees(im) + ' an(s) écoulé(s))'],
              ['Cession / sortie', im.dateCession
                ? C.dateFR(im.dateCession) + ' — ' + (im.motifSortie || 'sortie')
                  + (im.valeurCession ? ', cédé ' + C.money(im.valeurCession) : '')
                : 'Au patrimoine'],
              ['Fournisseur', im.fournisseur],
              ['État', U.badge(im.etat, im.etat === 'En service' ? 'success' : 'warning')]]),
            cede(im)
              ? K.note('Bien <strong>SORTI du patrimoine</strong> le ' + C.dateFR(im.dateCession || '')
                + ' : son amortissement est ARRÊTÉ à cette date et il ne figure plus au bilan. '
                + 'La fiche reste au registre — c’est elle qu’on ressort au contrôle.',
              { tone: 'warning', icon: 'log-out' })
              : null,
            U.card('Plan d’amortissement — pas SEMESTRIEL', el('div.space-y-2', null, [
              K.miniTable([
                { label: 'Période', key: 'periode' },
                { label: 'Base amortissable', align: 'right', render: function (l) { return C.money(l.base, false); } },
                { label: 'Dotation', align: 'right', render: function (l) { return C.money(l.dotation, false); } },
                { label: 'Amort. cumulé', align: 'right', render: function (l) { return C.money(l.cumul, false); } },
                { label: 'Valeur nette', align: 'right', render: function (l) { return C.money(l.vnc, false); } },
                { label: 'Couru', render: function (l) {
                  return l.couru ? U.badge('Couru', 'success') : U.badge('À venir', 'neutral');
                } },
              ], plan),
              K.note('L’amortissement court de la <strong>date d’acquisition</strong> à aujourd’hui, '
                + 'par pas de <strong>six mois</strong> : l’annuité ne se constate qu’à la clôture, et '
                + 'elle donnait le même amortissement à un bien acquis en février et à un bien acquis '
                + 'en novembre.', { tone: 'info', icon: 'calendar-range' }),
            ])),
          ].filter(Boolean));
        },
        etat: function (im) {
          var plan = planAmortissement(im);
          P.etat({
            titre: 'Fiche d’immobilisation & plan d’amortissement',
            sousTitre: im.designation + ' — ' + im.reference,
            cartouche: [['Bien', im.designation], ['Référence', im.reference],
              ['Catégorie', im.categorie], ['Compte d’immobilisation', im.compte],
              ['Date d’acquisition', C.dateFR(im.dateAcquisition)],
              ['Valeur d’acquisition', C.money(im.valeurAcquisition)],
              ['Durée', im.dureeAmortissement + ' ans — linéaire, pas semestriel'],
              ['Dotation semestrielle', C.money(dotationSemestre(im))],
              ['Semestres courus', semestresEcoules(im) + ' / ' + semestresTotal(im)],
              ['Amortissements cumulés', C.money(amortiCumule(im))],
              ['VALEUR NETTE COMPTABLE', C.money(vnc(im))],
              ['Cession / sortie', im.dateCession
                ? C.dateFR(im.dateCession) + ' — ' + (im.motifSortie || 'sortie') : 'Au patrimoine']],
            contenu: el('div.space-y-3', null, [
              /* LE TOTAL EST CALCULÉ depuis les lignes imprimées : la somme
                 des dotations doit faire la valeur d'acquisition, et c'est
                 précisément ce que le lecteur vient vérifier. */
              P.tableau([
                { label: 'Période', key: 'periode' },
                { label: 'Dotation', align: 'right', value: function (l) { return C.money(l.dotation, false); },
                  somme: function (l) { return l.dotation; } },
                { label: 'Amortissement cumulé', align: 'right', value: function (l) { return C.money(l.cumul, false); } },
                { label: 'Valeur nette comptable', align: 'right', value: function (l) { return C.money(l.vnc, false); } },
                { label: 'État', value: function (l) { return l.couru ? 'Couru' : 'À venir'; } },
              ], plan, { total: true, totalLabel: 'TOTAL DES DOTATIONS' }),
              el('p.mt-2.text-\[10px\].italic', {
                text: 'Le total des dotations égale la valeur d’acquisition : le dernier semestre solde '
                  + 'le reliquat d’arrondi. La valeur nette comptable au ' + C.dateFR(AUJ) + ' est de '
                  + C.money(vnc(im)) + ' — c’est elle qui est reportée à l’actif immobilisé du bilan.',
              }),
            ]),
            signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * BANQUES & RAPPROCHEMENTS
   * ======================================================================== */
  global.SIGH.screen('m12-banques', {
    title: 'Banques & rapprochements',
    description: 'Comptes bancaires, relevés et rapprochement avec la comptabilité.',
    render: function (root) {
      var col = S.collection('rapprochements', { module: 'M12', entite: 'Rapprochement' });
      if (!col.all().length && S.amorcable('rapprochements')) {
        var rnd = C.seeded(2417);
        var BANQUES = ['ECOBANK Bénin', 'Bank Of Africa Bénin', 'Orabank Bénin'];
        BANQUES.forEach(function (b, i) {
          for (var m = 0; m < 6; m++) {
            var soldeCompta = C.between(rnd, 500, 9000) * 1000;
            var ecart = rnd() > 0.6 ? C.between(rnd, -400, 400) * 1000 : 0;
            col.all().push({
              id: 'RAP' + C.uid(), statut: 'actif',
              reference: 'RB-' + C.pad(col.all().length + 1, 4),
              banque: b, compte: '521000',
              periode: C.MOIS[m + 2].charAt(0).toUpperCase() + C.MOIS[m + 2].slice(1) + ' 2026',
              soldeComptable: soldeCompta,
              soldeReleve: soldeCompta + ecart,
              ecart: ecart,
              statutRappro: ecart === 0 ? 'rapproche' : 'ecart',
              operateur: 'KASSA Augustin',
            });
          }
        });
        S.save();
      }

      /* Les comptes bancaires deviennent un référentiel à part entière : la
         clinique doit pouvoir en ouvrir un nouveau sans attendre une livraison
         logicielle (demande de la Direction). Les rapprochements s'y adossent. */
      /* Les comptes de trésorerie sont amorcés AU SOCLE : la saisie des
         dépenses les lit aussi, et une page ne charge que le module de son
         écran. Les amorcer ici laissait la liste vide pour qui n'était pas
         passé par cet écran. */
      var colBanques = S.collection('banques', { module: 'M12', entite: 'compte bancaire', prefix: 'BQ' });

      var rows = col.active();
      var host = el('div.space-y-4');
      var banques = colBanques.active().map(function (b) { return b.banque; });

      function champsBanque() {
        return [
          { name: 'banque', label: 'Établissement bancaire', required: true, col: 'full' },
          { name: 'intitule', label: 'Intitulé du compte', required: true, col: 'full' },
          { name: 'numeroCompte', label: 'Numéro de compte', required: true },
          {
            name: 'compteComptable', label: 'Compte comptable (SYSCOHADA)', required: true,
            help: 'Classe 52 — banques. Sert à l’imputation automatique des mouvements.',
          },
          { name: 'devise', label: 'Devise', type: 'select', options: ['FCFA', 'EUR', 'USD'] },
          {
            name: 'statutCompte', label: 'État du compte', type: 'select', required: true,
            options: [{ value: 'actif', label: 'Actif' }, { value: 'cloture', label: 'Clôturé' }],
          },
        ];
      }

      host.appendChild(U.kpiGrid([
        { label: 'Comptes bancaires', value: C.num(colBanques.active().length), icon: 'landmark', tone: 'navy' },
        { label: 'Rapprochements effectués', value: C.num(rows.length), icon: 'check-circle-2', tone: 'info' },
        { label: 'Sans écart', value: C.num(rows.filter(function (r) { return r.statutRappro === 'rapproche'; }).length), icon: 'scale', tone: 'success' },
        { label: 'Avec écart', value: C.num(rows.filter(function (r) { return r.statutRappro === 'ecart'; }).length), icon: 'scale-3d', tone: 'danger' },
      ]));

      var tableBanques = U.dataTable({
        title: 'Comptes bancaires de la clinique',
        rows: function () { return colBanques.active(); },
        exportName: 'comptes-bancaires', pageSize: 10, searchable: true,
        emptyMessage: 'Aucun compte bancaire enregistré.',
        columns: [
          { key: 'banque', label: 'Établissement', render: function (b) { return el('span.font-medium.text-slate-800', { text: b.banque }); } },
          { key: 'intitule', label: 'Intitulé du compte' },
          { key: 'numeroCompte', label: 'N° de compte', nowrap: true, render: function (b) { return el('span.font-mono.text-xs', { text: b.numeroCompte }); } },
          { key: 'compteComptable', label: 'Compte SYSCOHADA', nowrap: true, render: function (b) { return U.badge(b.compteComptable, 'navy'); } },
          { key: 'devise', label: 'Devise', nowrap: true },
          {
            key: 'statutCompte', label: 'État',
            render: function (b) { return b.statutCompte === 'actif' ? U.badge('Actif', 'success') : U.badge('Clôturé', 'neutral'); },
          },
        ],
        rowActions: K.actionsLigne(colBanques, champsBanque, { entite: 'compte bancaire' }),
        actions: [K.creer(colBanques, champsBanque, {
          titre: 'Nouveau compte bancaire', entite: 'Compte',
          defauts: function () { return { devise: 'FCFA', statutCompte: 'actif', compteComptable: '521' }; },
          apres: function () { tableBanques.refresh(); },
        })],
      });
      host.appendChild(tableBanques);

      host.appendChild(U.dataTable({
        title: 'États de rapprochement bancaire', rows: rows, exportName: 'rapprochements', pageSize: 15,
        defaultSort: 'periode', defaultDir: 'desc',
        filters: [
          { name: 'banque', label: 'Banque', options: banques },
          { name: 'statutRappro', label: 'Résultat', options: [{ value: 'rapproche', label: 'Sans écart' }, { value: 'ecart', label: 'Avec écart' }] },
        ],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'banque', label: 'Banque' },
          { key: 'compte', label: 'Compte', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.compte }); } },
          { key: 'periode', label: 'Période', nowrap: true },
          { key: 'soldeComptable', label: 'Solde comptable', align: 'right', text: function (r) { return C.money(r.soldeComptable, false); }, render: function (r) { return C.money(r.soldeComptable, false); } },
          { key: 'soldeReleve', label: 'Solde relevé', align: 'right', text: function (r) { return C.money(r.soldeReleve, false); }, render: function (r) { return C.money(r.soldeReleve, false); } },
          {
            key: 'ecart', label: 'Écart', align: 'right',
            text: function (r) { return C.money(r.ecart, false); },
            render: function (r) {
              return r.ecart === 0 ? U.badge('Rapproché', 'success')
                : el('span.font-semibold.text-danger-600', { text: (r.ecart > 0 ? '+' : '') + C.money(r.ecart, false) });
            },
          },
          { key: 'operateur', label: 'Effectué par' },
        ],
        rowActions: function (r) {
          return [K.iconBtn('printer', 'Imprimer l’état', function () {
            P.etat({
              titre: 'État de rapprochement bancaire',
              sousTitre: r.banque + ' — ' + r.periode,
              cartouche: [['Banque', r.banque], ['Compte comptable', r.compte],
                ['Période', r.periode], ['Référence', r.reference],
                ['Effectué par', r.operateur], ['Date d’édition', C.dateFR(AUJ)]],
              contenu: el('div.space-y-3', null, [
                P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
                  { k: 'Solde du compte en comptabilité', v: C.money(r.soldeComptable, false) },
                  { k: 'Solde du relevé bancaire', v: C.money(r.soldeReleve, false) },
                  { k: 'ÉCART CONSTATÉ', v: C.money(r.ecart, false) },
                ]),
                el('p.mt-3.text-\\[10px\\].italic', {
                  text: r.ecart === 0
                    ? 'Le rapprochement ne fait apparaître aucun écart : la comptabilité et le relevé bancaire concordent.'
                    : 'Un écart de ' + C.money(Math.abs(r.ecart)) + ' est constaté. Il doit être justifié (chèques en circulation, '
                      + 'virements non encore comptabilisés, frais bancaires) puis régularisé par écriture d’opérations diverses.',
                }),
              ]),
              signatures: [{ role: 'Le Comptable', nom: r.operateur },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
            });
          })];
        },
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * ÉTATS FINANCIERS
   * ======================================================================== */
  /* ==========================================================================
   * ÉTATS FINANCIERS DE SYNTHÈSE — AU FORMAT DE LA LIASSE DÉPOSÉE
   * --------------------------------------------------------------------------
   * L'écran reproduit les CINQ feuillets de la liasse remise à la Direction
   * Générale des Impôts le 15/05/2026 : bilan, compte de résultat, tableau des
   * flux de trésorerie, note 11 « Disponibilités » et note 34 « Fiche de
   * synthèse des principaux indicateurs financiers ». Mêmes références (AD,
   * AI, XB, ZA…), mêmes libellés, même ordre, mêmes sous-totaux : un comptable
   * doit retrouver SES lignes, à LEUR place, pour rapprocher l'écran du dépôt.
   *
   * DEUX COLONNES DE NATURES DIFFÉRENTES, ET ELLES NE SE MÉLANGENT JAMAIS :
   *
   *   — « Exercice N (déposé) » et « N-1 » citent le document. Ce sont des
   *     faits : ils ne se recalculent pas.
   *   — « Exercice en cours » est CALCULÉ depuis le journal du logiciel, par
   *     les préfixes de comptes SYSCOHADA que chaque ligne déclare. Une ligne
   *     que le journal n'alimente pas reste vide — un zéro y ferait croire à
   *     un solde nul là où il n'y a pas de donnée.
   *
   * LES ÉCARTS INTERNES DU DOCUMENT SONT SIGNALÉS, NON ARBITRÉS : le
   * formulaire déposé ne se recoupe pas partout (voir `L.ECARTS`). Les
   * corriger ferait diverger le logiciel de ce que la clinique a réellement
   * remis à l'administration.
   * ======================================================================== */
  global.SIGH.screen('m12-etats-financiers', {
    title: 'États financiers de synthèse',
    description: 'Bilan, compte de résultat, flux de trésorerie, disponibilités et fiche de synthèse — au format de la liasse DGI.',
    regle: 'L’écran reproduit les <strong>cinq feuillets de la liasse déposée</strong> le 15/05/2026 '
      + '(code BK505416) : mêmes références, mêmes libellés, même ordre. La colonne '
      + '<strong>« déposé »</strong> CITE le document — elle ne se recalcule pas ; la colonne '
      + '<strong>« exercice en cours »</strong> est CALCULÉE depuis le journal, par les préfixes de '
      + 'comptes SYSCOHADA. Une ligne que le journal n’alimente pas reste <strong>vide</strong> : un '
      + 'zéro y ferait croire à un solde nul là où il n’y a pas de donnée. Les <strong>écarts internes '
      + 'du document</strong> sont signalés, jamais arbitrés.',
    render: function (root) {
      var L = global.SIGH.liasse;
      var host = el('div.space-y-4');
      var e = ecritures().filter(function (x) { return x.statut === 'validee'; });

      /* ------------------------------------------------------------------
       * LE CALCUL DE L'EXERCICE EN COURS
       * ------------------------------------------------------------------
       * Une ligne du formulaire déclare les PRÉFIXES de comptes qui
       * l'alimentent. Le sens dépend de la classe : un compte d'actif ou de
       * charge se lit au débit, un compte de passif ou de produit au crédit.
       * Sans cette règle, le passif sortirait en négatif et la lecture
       * s'inverserait d'une rubrique à l'autre.
       * ---------------------------------------------------------------- */
      /* L'EXERCICE PRÉCÉDENT, TIRÉ DU JOURNAL. Quand le précédent n'a pas été déposé (et que le journal
         le porte), sa colonne se CALCULE comme celle de l'exercice choisi, avec ses à-nouveaux
         provisoires s'il n'est pas encore clos. Un bilan sans sa colonne N-1 ne se compare à rien. */
      var anneeN1 = global.SIGH.exercice.choisi() - 1;
      var eN1 = ecrituresToutes().filter(function (x) { return x.statut === 'validee' && global.SIGH.exercice.anneeDe(x.date) === anneeN1; })
        .concat(global.SIGH.exercice.provisoires(anneeN1).filter(function (x) { return x.statut === 'validee'; }));
      var avecN1 = eN1.length > 0;
      function soldeDesComptes(prefixes, sens, source) {
        if (!prefixes || !prefixes.length) return null;
        var sel = (source || e).filter(function (x) {
          var num = String(x.compte || '');
          return prefixes.some(function (p) { return num.indexOf(p) === 0; });
        });
        if (!sel.length) return null;
        var d = C.sum(sel, 'debit'), c = C.sum(sel, 'credit');
        return sens === 'credit' ? c - d : d - c;
      }
      /* UN COMPTE DE TIERS CHANGE DE CÔTÉ SELON SON SENS. Le plan SYSCOHADA
         emploie les mêmes comptes de classe 4 pour les CRÉANCES et pour les
         DETTES : c'est le sens du solde qui décide. Un solde débiteur va à
         l'actif, un solde créditeur au passif. Sans cette règle, le même
         compte paraissait des deux côtés — et du côté où il n'a rien à faire,
         il sortait en NÉGATIF, ce qui ne veut rien dire sur un bilan. */
      function calculActif(l) {
        var v = soldeDesComptes(l.comptes, 'debit');
        return v == null || v < 0 ? null : v;
      }
      function calculPassif(l) {
        var v = soldeDesComptes(l.comptes, 'credit');
        return v == null || v < 0 ? null : v;
      }
      /* Au compte de résultat, le formulaire porte les charges en NÉGATIF :
         on suit sa convention, sinon la colonne calculée ne se compare pas
         à la colonne déposée. */
      function calculActifN1(l) {
        var v = soldeDesComptes(l.comptes, 'debit', eN1);
        return v == null || v < 0 ? null : v;
      }
      function calculPassifN1(l) {
        var v = soldeDesComptes(l.comptes, 'credit', eN1);
        return v == null || v < 0 ? null : v;
      }
      function colonneN1(calcul) {
        return avecN1 ? [{ label: 'Exercice ' + anneeN1 + ' (journal)', align: 'right',
          render: function (l) { return l.t ? el('span') : cellule(calcul(l), { vide: '—' }); } }] : [];
      }
      function calculResultat(l) {
        var v = soldeDesComptes(l.comptes, l.signe === '-' ? 'debit' : 'credit');
        if (v == null) return null;
        return l.signe === '-' ? -v : v;
      }

      var totalActifDepose = L.BILAN_ACTIF.filter(function (x) { return x.ref === 'BZ'; })[0];
      var totalPassifDepose = L.BILAN_PASSIF.filter(function (x) { return x.ref === 'DZ'; })[0];
      var resultatDepose = L.RESULTAT.filter(function (x) { return x.ref === 'XI'; })[0];
      var caDepose = L.RESULTAT.filter(function (x) { return x.ref === 'XB'; })[0];

      host.appendChild(U.kpiGrid([
        { label: 'Chiffre d’affaires déposé', value: C.money(caDepose.n), icon: 'trending-up', tone: 'navy',
          hint: 'Exercice ' + L.DEPOT.exerciceN + ' — liasse du ' + C.dateFR(L.DEPOT.dateDepot) },
        { label: 'Résultat net déposé', value: C.money(resultatDepose.n),
          icon: resultatDepose.n >= 0 ? 'smile' : 'frown', tone: resultatDepose.n >= 0 ? 'success' : 'danger',
          hint: 'N-1 : ' + C.money(resultatDepose.n1) },
        { label: 'Total du bilan', value: C.money(totalActifDepose.net), icon: 'layers', tone: 'info',
          hint: totalActifDepose.net === totalPassifDepose.net ? 'Actif = Passif — le bilan s’équilibre'
            : 'ACTIF ET PASSIF NE S’ÉQUILIBRENT PAS' },
        { label: 'Écarts internes du document', value: C.num(L.ECARTS.length), icon: 'alert-triangle',
          tone: 'warning', hint: 'Signalés, jamais arbitrés' },
      ]));

      host.appendChild(K.note('Liasse <strong>' + C.escapeHtml(L.DEPOT.denomination) + '</strong>, IFU '
        + C.escapeHtml(L.DEPOT.ifu) + ', déposée le <strong>' + C.dateFR(L.DEPOT.dateDepot)
        + '</strong> — code ' + C.escapeHtml(L.DEPOT.code) + '. ' + C.escapeHtml(L.DEPOT.administration)
        + '. Référentiel : <strong>plan comptable SYSCOHADA révisé</strong> (AUDCIF, applicable depuis '
        + 'le 1ᵉʳ janvier 2018).', { tone: 'info', icon: 'file-badge' }));

      /* --- La cellule d'un montant, avec sa convention d'affichage ------- */
      function cellule(v, opts) {
        var o = opts || {};
        if (v == null) {
          return el('span.text-slate-300', { text: o.vide || '' });
        }
        return el('span', {
          class: (o.gras ? 'font-semibold ' : '') + (v < 0 ? 'text-danger-700' : 'text-slate-800'),
          text: C.money(v, false),
        });
      }
      function classeLigne(l) {
        if (l.t === 'grand') return 'bg-navy-50 font-bold text-navy-900';
        if (l.t === 'total') return 'bg-slate-50 font-semibold';
        return '';
      }
      /* Le formulaire indente ses lignes de détail sous leur sous-total :
         c'est cette indentation qui rend la structure lisible. */
      function libelleDe(l) {
        return el('span', { class: l.t ? 'font-semibold' : 'pl-3 text-slate-700', text: l.libelle });
      }
      function badgeEcart(l) {
        if (!l.ecart) return null;
        var ec = L.ecart(l.ecart);
        return el('span.ml-2.cursor-help', { title: ec ? ec.constat : '' },
          [U.badge('écart du document', 'warning')]);
      }

      function tableLiasse(lignes, colonnes) {
        var t = el('table.w-full.text-sm');
        var thead = el('thead'), htr = el('tr.border-b.border-slate-200');
        colonnes.forEach(function (c) {
          htr.appendChild(el('th.px-2.py-2.text-xs.font-semibold.uppercase.tracking-wide.text-slate-500', {
            class: c.align === 'right' ? 'text-right' : 'text-left', text: c.label,
          }));
        });
        thead.appendChild(htr); t.appendChild(thead);
        var tb = el('tbody');
        lignes.forEach(function (l) {
          if (l.section || l.section2) {
            var str = el('tr');
            str.appendChild(el('td.bg-slate-100.px-2.py-1.text-xs.font-semibold.uppercase.tracking-wide.text-slate-600',
              { colspan: colonnes.length, text: l.section || l.section2 }));
            tb.appendChild(str);
            return;
          }
          var tr = el('tr.border-b.border-slate-100', { class: classeLigne(l) });
          colonnes.forEach(function (c) {
            var td = el('td.px-2.py-1.align-top', { class: c.align === 'right' ? 'text-right num' : '' });
            C.append(td, c.render(l));
            tr.appendChild(td);
          });
          tb.appendChild(tr);
        });
        t.appendChild(tb);
        return el('div.overflow-x-auto', null, t);
      }

      var onglets = [
        /* ---------------------------------------------------------------- 1 */
        {
          id: 'bilan', label: 'Bilan',
          render: function () {
            return el('div.space-y-4', null, [
              K.note('Le bilan déposé <strong>s’équilibre</strong> : total général de l’actif '
                + C.money(totalActifDepose.net) + ' = total général du passif '
                + C.money(totalPassifDepose.net) + '.', { tone: 'success', icon: 'scale' }),
              U.card('BILAN — ACTIF (feuillet 5/51)', tableLiasse(L.BILAN_ACTIF, [
                { label: 'Réf.', render: function (l) { return el('span.font-mono.text-xs.text-slate-500', { text: l.ref }); } },
                { label: 'Actif', render: libelleDe },
                { label: 'Note', render: function (l) { return el('span.text-xs.text-slate-400', { text: l.note || '' }); } },
                { label: 'Brut ' + L.DEPOT.exerciceN, align: 'right', render: function (l) { return cellule(l.brut); } },
                { label: 'Amort. et dépréc.', align: 'right', render: function (l) { return cellule(l.amort); } },
                { label: 'Net ' + L.DEPOT.exerciceN, align: 'right', render: function (l) { return cellule(l.net, { gras: !!l.t }); } },
                { label: 'Net ' + L.DEPOT.exerciceN1, align: 'right', render: function (l) { return cellule(l.netN1); } },
                { label: 'Exercice en cours', align: 'right',
                  render: function (l) { return l.t ? el('span') : cellule(calculActif(l), { vide: '—' }); } },
              ].concat(colonneN1(calculActifN1)))),
              U.card('BILAN — PASSIF (feuillet 6/51)', tableLiasse(L.BILAN_PASSIF, [
                { label: 'Réf.', render: function (l) { return el('span.font-mono.text-xs.text-slate-500', { text: l.ref }); } },
                { label: 'Passif', render: libelleDe },
                { label: 'Note', render: function (l) { return el('span.text-xs.text-slate-400', { text: l.note || '' }); } },
                { label: 'Net ' + L.DEPOT.exerciceN, align: 'right', render: function (l) { return cellule(l.net, { gras: !!l.t }); } },
                { label: 'Net ' + L.DEPOT.exerciceN1, align: 'right', render: function (l) { return cellule(l.netN1); } },
                { label: 'Exercice en cours', align: 'right',
                  render: function (l) { return l.t ? el('span') : cellule(calculPassif(l), { vide: '—' }); } },
              ].concat(colonneN1(calculPassifN1)))),
              K.note('La colonne <strong>« Exercice en cours »</strong> est calculée depuis les '
                + 'écritures VALIDÉES du journal, par les préfixes de comptes SYSCOHADA que chaque '
                + 'ligne déclare. Elle reste vide là où le journal ne porte rien — le prototype ne '
                + 'tient pas encore tous les comptes de la liasse. Un <strong>compte de tiers</strong> '
                + 'y paraît du côté où son solde le place : débiteur à l’actif, créditeur au passif — '
                + 'le plan SYSCOHADA emploie les mêmes comptes de classe 4 pour les créances et pour '
                + 'les dettes.', { tone: 'info' }),
            ]);
          },
        },
        /* ---------------------------------------------------------------- 2 */
        {
          id: 'resultat', label: 'Compte de résultat',
          render: function () {
            return el('div.space-y-4', null, [
              U.card('COMPTE DE RÉSULTAT (feuillet 7/51)', tableLiasse(L.RESULTAT, [
                { label: 'Réf.', render: function (l) { return el('span.font-mono.text-xs.text-slate-500', { text: l.ref }); } },
                { label: 'Libellés', render: libelleDe },
                { label: '(2)', render: function (l) { return el('span.text-xs.text-slate-400', { text: l.signe || '' }); } },
                { label: 'Note', render: function (l) { return el('span.text-xs.text-slate-400', { text: l.note || '' }); } },
                { label: 'Exercice ' + L.DEPOT.exerciceN, align: 'right', render: function (l) { return cellule(l.n, { gras: !!l.t }); } },
                { label: 'Exercice ' + L.DEPOT.exerciceN1, align: 'right', render: function (l) { return cellule(l.n1); } },
                { label: 'Exercice en cours', align: 'right',
                  render: function (l) { return l.t ? el('span') : cellule(calculResultat(l), { vide: '—' }); } },
              ])),
              K.note('La <strong>marge commerciale est nulle</strong> à la liasse déposée — et c’est '
                + 'la confirmation documentaire de <strong>RG-02</strong> : les médicaments sont '
                + 'facturés au prix d’achat, sans marge. Si elle cessait de l’être, ce serait un '
                + 'signal, pas une bonne nouvelle.', { tone: 'success', icon: 'check-circle-2' }),
            ]);
          },
        },
        /* ---------------------------------------------------------------- 3 */
        {
          id: 'flux', label: 'Tableau des flux de trésorerie',
          render: function () {
            return el('div.space-y-4', null, [
              U.card('TABLEAU DES FLUX DE TRÉSORERIE (feuillet 8/51)', tableLiasse(L.FLUX, [
                { label: 'Réf.', render: function (l) { return el('span.font-mono.text-xs.text-slate-500', { text: l.ref || '' }); } },
                { label: 'Libellés', render: function (l) {
                  return el('span', { class: l.t ? 'font-semibold' : 'pl-3 text-slate-700' }, [
                    el('span', { text: l.libelle }), badgeEcart(l),
                  ].filter(Boolean));
                } },
                { label: '', render: function (l) { return el('span.text-xs.font-bold.text-slate-500', { text: l.repere || '' }); } },
                { label: 'Exercice ' + L.DEPOT.exerciceN, align: 'right', render: function (l) { return cellule(l.n, { gras: !!l.t }); } },
                { label: 'Exercice ' + L.DEPOT.exerciceN1, align: 'right', render: function (l) { return cellule(l.n1); } },
              ])),
              blocEcarts(['bf', 'zb', 'cafg']),
            ]);
          },
        },
        /* ---------------------------------------------------------------- 4 */
        {
          id: 'disponibilites', label: 'Disponibilités',
          render: function () {
            var d = L.DISPONIBILITES;
            return el('div.space-y-4', null, [
              U.card(d.note + ' (feuillet 25/51)', tableLiasse(d.lignes, [
                { label: 'Libellés', render: libelleDe },
                { label: 'Année ' + L.DEPOT.exerciceN, align: 'right', render: function (l) { return cellule(l.n, { gras: !!l.t }); } },
                { label: 'Année ' + L.DEPOT.exerciceN1, align: 'right', render: function (l) { return cellule(l.n1); } },
                { label: 'Variation en %', align: 'right', render: function (l) {
                  if (l.n == null || !l.n1) return el('span.text-slate-300', { text: '' });
                  return el('span.text-slate-700', { text: C.pct((l.n - l.n1) / Math.abs(l.n1) * 100, 2) });
                } },
                { label: 'Exercice en cours', align: 'right',
                  render: function (l) { return l.t ? el('span') : cellule(soldeDesComptes(l.comptes, 'debit'), { vide: '—' }); } },
              ])),
              U.card('Commentaires demandés par le formulaire',
                el('ul.list-disc.space-y-1.pl-5.text-sm.text-slate-600', null,
                  d.commentaires.map(function (x) { return el('li', { text: x }); }))),
              K.note(C.escapeHtml(d.nb), { tone: 'neutral', icon: 'info' }),
            ]);
          },
        },
        /* ---------------------------------------------------------------- 5 */
        {
          id: 'synthese', label: 'Fiche de synthèse',
          render: function () {
            return el('div.space-y-4', null, [
              U.card('NOTE 34 : FICHE DE SYNTHÈSE DES PRINCIPAUX INDICATEURS FINANCIERS (feuillet 51/51)',
                tableLiasse(L.SYNTHESE, [
                  { label: 'Libellés', render: function (l) {
                    if (l.controle) return el('span.text-xs.italic.text-slate-500', { text: l.libelle });
                    return el('span', { class: l.t ? 'font-semibold' : 'pl-3 text-slate-700' }, [
                      el('span', { text: l.libelle }), badgeEcart(l),
                    ].filter(Boolean));
                  } },
                  { label: 'Année ' + L.DEPOT.exerciceN, align: 'right',
                    render: function (l) { return l.unite ? el('span.text-xs.text-slate-400', { text: l.unite }) : cellule(l.n, { gras: !!l.t }); } },
                  { label: 'Année ' + L.DEPOT.exerciceN1, align: 'right',
                    render: function (l) { return l.unite ? el('span.text-xs.text-slate-400', { text: l.unite }) : cellule(l.n1); } },
                  { label: 'Variation en %', align: 'right', render: function (l) {
                    if (l.variation == null) return el('span.text-slate-300', { text: '' });
                    return el('span', { class: l.variation < 0 ? 'text-danger-700' : 'text-slate-700',
                      text: C.num(l.variation, 2) + ' %' });
                  } },
                ])),
              U.card('Notes du formulaire',
                el('ul.list-disc.space-y-1.pl-5.text-xs.text-slate-500', null,
                  L.NOTES_SYNTHESE.map(function (x) { return el('li', { text: x }); }))),
              blocEcarts(['cafg', 'fluxOp', 'fluxFin', 'tresorerie']),
            ]);
          },
        },
      ];

      host.appendChild(U.tabs(onglets));

      host.appendChild(el('div.flex.flex-wrap.gap-2', null, [
        K.btn('Imprimer le bilan', { variant: 'primary', icon: 'printer', onclick: function () { imprimer('bilan'); } }),
        K.btn('Compte de résultat', { icon: 'printer', onclick: function () { imprimer('resultat'); } }),
        K.btn('Flux de trésorerie', { icon: 'printer', onclick: function () { imprimer('flux'); } }),
        K.btn('Disponibilités', { icon: 'printer', onclick: function () { imprimer('disponibilites'); } }),
        K.btn('Fiche de synthèse', { icon: 'printer', onclick: function () { imprimer('synthese'); } }),
        K.btn('Immobilisations', { icon: 'building',
          onclick: function () { global.SIGH.app.go('m12-immobilisations'); } }),
      ]));

      host.appendChild(K.source('Liasse fiscale déposée le ' + C.dateFR(L.DEPOT.dateDepot)
        + ' (code ' + L.DEPOT.code + ') — transcrite feuillet par feuillet. La colonne « exercice en '
        + 'cours » est calculée depuis les écritures validées du journal.'));

      root.appendChild(host);
      return null;

      /** Les écarts internes du document, énoncés — jamais corrigés. */
      function blocEcarts(cles) {
        var sel = L.ECARTS.filter(function (x) { return cles.indexOf(x.cle) !== -1; });
        if (!sel.length) return null;
        return U.card('Écarts internes du document déposé — conservés, non arbitrés',
          el('div.space-y-2', null, [
            K.note('Le formulaire déposé ne se recoupe pas partout. Ces écarts sont ceux du '
              + '<strong>document remis à l’administration</strong> : les corriger ici ferait diverger '
              + 'le logiciel de ce que la clinique a réellement déposé — précisément ce qu’un contrôle '
              + 'vient comparer.', { tone: 'warning', icon: 'alert-triangle' }),
            K.miniTable(['Ligne', 'Constat', 'Lecture'],
              sel.map(function (x) { return [x.titre, x.constat, x.lecture]; })),
          ]));
      }

      function imprimer(quoi) {
        var cartoucheCommun = [
          ['Dénomination sociale', L.DEPOT.denomination],
          ['IFU', L.DEPOT.ifu],
          ['Date de dépôt', C.dateFR(L.DEPOT.dateDepot)],
          ['Code de dépôt', L.DEPOT.code],
          ['Exercice', String(L.DEPOT.exerciceN) + ' (N) — comparé à ' + String(L.DEPOT.exerciceN1) + ' (N-1)'],
          ['Référentiel', 'Plan comptable SYSCOHADA révisé (AUDCIF)'],
        ];
        var signatures = [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
          { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' },
          { role: 'La Direction', nom: 'BASSONGUI Chabi Séko' }];

        if (quoi === 'bilan') {
          P.etat({
            titre: 'Bilan', sousTitre: 'Exercice au 31/12/' + L.DEPOT.exerciceN,
            cartouche: cartoucheCommun, filtres: false,
            contenu: el('div.space-y-3', null, [
              el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Actif' }),
              P.tableau([
                { label: 'Réf.', key: 'ref' }, { label: 'Actif', key: 'libelle' },
                { label: 'Note', key: 'note' },
                { label: 'Brut', align: 'right', value: function (l) { return l.brut == null ? '' : C.money(l.brut, false); } },
                { label: 'Amort. et dépréc.', align: 'right', value: function (l) { return l.amort == null ? '' : C.money(l.amort, false); } },
                { label: 'Net ' + L.DEPOT.exerciceN, align: 'right', value: function (l) { return l.net == null ? '' : C.money(l.net, false); } },
                { label: 'Net ' + L.DEPOT.exerciceN1, align: 'right', value: function (l) { return l.netN1 == null ? '' : C.money(l.netN1, false); } },
              ], L.BILAN_ACTIF),
              el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Passif' }),
              P.tableau([
                { label: 'Réf.', key: 'ref' }, { label: 'Passif', key: 'libelle' },
                { label: 'Note', key: 'note' },
                { label: 'Net ' + L.DEPOT.exerciceN, align: 'right', value: function (l) { return l.net == null ? '' : C.money(l.net, false); } },
                { label: 'Net ' + L.DEPOT.exerciceN1, align: 'right', value: function (l) { return l.netN1 == null ? '' : C.money(l.netN1, false); } },
              ], L.BILAN_PASSIF),
              el('p.mt-3.text-\\[10px\\].italic', {
                text: 'Contrôle : total général de l’actif ' + C.money(totalActifDepose.net)
                  + ' = total général du passif ' + C.money(totalPassifDepose.net) + '.',
              }),
            ]),
            signatures: signatures,
          });
          return;
        }
        if (quoi === 'resultat') {
          P.etat({
            titre: 'Compte de résultat', sousTitre: 'Exercice au 31/12/' + L.DEPOT.exerciceN,
            cartouche: cartoucheCommun, filtres: false,
            contenu: el('div.space-y-3', null, [
              P.tableau([
                { label: 'Réf.', key: 'ref' }, { label: 'Libellés', key: 'libelle' },
                { label: '(2)', key: 'signe' }, { label: 'Note', key: 'note' },
                { label: 'Exercice ' + L.DEPOT.exerciceN, align: 'right', value: function (l) { return l.n == null ? '' : C.money(l.n, false); } },
                { label: 'Exercice ' + L.DEPOT.exerciceN1, align: 'right', value: function (l) { return l.n1 == null ? '' : C.money(l.n1, false); } },
              ], L.RESULTAT),
              el('p.mt-3.text-\\[10px\\].italic', {
                text: 'La marge commerciale est nulle : les médicaments sont facturés au prix d’achat, '
                  + 'sans marge (RG-02). Résultat net de l’exercice : ' + C.money(resultatDepose.n) + '.',
              }),
            ]),
            signatures: signatures,
          });
          return;
        }
        if (quoi === 'flux') {
          P.etat({
            titre: 'Tableau des flux de trésorerie', sousTitre: 'Exercice au 31/12/' + L.DEPOT.exerciceN,
            cartouche: cartoucheCommun, filtres: false,
            contenu: el('div.space-y-3', null, [
              P.tableau([
                { label: 'Réf.', value: function (l) { return l.ref || ''; } },
                { label: 'Libellés', value: function (l) { return l.section || l.libelle || ''; } },
                { label: '', value: function (l) { return l.repere || ''; } },
                { label: 'Exercice ' + L.DEPOT.exerciceN, align: 'right', value: function (l) { return l.n == null ? '' : C.money(l.n, false); } },
                { label: 'Exercice ' + L.DEPOT.exerciceN1, align: 'right', value: function (l) { return l.n1 == null ? '' : C.money(l.n1, false); } },
              ], L.FLUX),
              el('p.mt-3.text-\\[10px\\].italic', {
                text: 'Écarts internes du document déposé, conservés et non arbitrés : '
                  + L.ECARTS.filter(function (x) { return ['bf', 'zb', 'cafg'].indexOf(x.cle) !== -1; })
                    .map(function (x) { return x.titre + ' — ' + x.constat; }).join(' ; '),
              }),
            ]),
            signatures: signatures,
          });
          return;
        }
        if (quoi === 'disponibilites') {
          P.etat({
            titre: L.DISPONIBILITES.note, sousTitre: 'Exercice au 31/12/' + L.DEPOT.exerciceN,
            cartouche: cartoucheCommun, filtres: false,
            contenu: el('div.space-y-3', null, [
              P.tableau([
                { label: 'Libellés', key: 'libelle' },
                { label: 'Année ' + L.DEPOT.exerciceN, align: 'right', value: function (l) { return l.n == null ? '' : C.money(l.n, false); } },
                { label: 'Année ' + L.DEPOT.exerciceN1, align: 'right', value: function (l) { return l.n1 == null ? '' : C.money(l.n1, false); } },
              ], L.DISPONIBILITES.lignes),
              el('p.mt-3.text-\\[10px\\].italic', { text: L.DISPONIBILITES.nb }),
            ]),
            signatures: signatures,
          });
          return;
        }
        P.etat({
          titre: 'Fiche de synthèse des principaux indicateurs financiers',
          sousTitre: 'Note 34 — exercice au 31/12/' + L.DEPOT.exerciceN,
          cartouche: cartoucheCommun, filtres: false,
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Libellés', value: function (l) { return l.section || l.section2 || l.libelle || ''; } },
              { label: 'Année ' + L.DEPOT.exerciceN, align: 'right', value: function (l) { return l.n == null ? '' : C.money(l.n, false); } },
              { label: 'Année ' + L.DEPOT.exerciceN1, align: 'right', value: function (l) { return l.n1 == null ? '' : C.money(l.n1, false); } },
              { label: 'Variation en %', align: 'right', value: function (l) { return l.variation == null ? '' : C.num(l.variation, 2) + ' %'; } },
            ], L.SYNTHESE),
            el('p.mt-3.text-\\[10px\\].italic', { text: L.NOTES_SYNTHESE.join(' ') }),
          ]),
          signatures: signatures,
        });
      }
    },
  });

  /* ==========================================================================
   * EXERCICES & CLÔTURES (PRD-M12-cloture-exercice)
   * --------------------------------------------------------------------------
   * La clôture se fait en DEUX GESTES par deux personnes : le comptable la
   * DEMANDE (les contrôles bloquants refusent en nommant), la Direction ou la
   * DAF la VALIDE avec un motif — signer n'est pas saisir. Elle solde les
   * classes 6, 7 et 8 vers le résultat, écrit les à-nouveaux de N+1 (au solde
   * pour les comptes sans lettrage, ligne à ligne pour les tiers non lettrés)
   * puis fige l'exercice : plus aucune écriture, aucune réouverture.
   * ======================================================================== */
  function telechargerCSV(nom, entetes, lignes) {
    var esc = function (v) { v = v == null ? '' : String(v); return /[;"\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
    var txt = '﻿' + [entetes].concat(lignes).map(function (l) { return l.map(esc).join(';'); }).join('\n');
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([txt], { type: 'text/csv;charset=utf-8' }));
    a.download = nom + '.csv'; document.body.appendChild(a); a.click(); a.remove();
  }

  /* L'archive de clôture dans la GED est tenue par le MOTEUR (SIGH.exercice.archiver) : elle naît avec la
     clôture. Ce bouton ne sert qu'à la déposer pour un exercice clos AVANT que le moteur ne le fasse. */
  function archiverDansGED(x) {
    var r = global.SIGH.exercice.archiver(x.annee);
    if (r.deja) U.toast('Cet exercice est déjà archivé dans la GED.', { type: 'info', detail: r.reference });
    else U.toast('Archive de l’exercice ' + x.annee + ' déposée dans la GED.', { type: 'success', detail: r.reference + ' — conservation 10 ans.' });
    return r;
  }

  function procesVerbalCloture(x) {
    var X = global.SIGH.exercice, lignes = X.soldes(X.ecrituresDe(x.annee));
    P.etat({
      titre: 'Procès-verbal de clôture — exercice ' + x.annee,
      sousTitre: 'Détermination du résultat et à-nouveaux de l’exercice ' + (x.annee + 1),
      cartouche: [['Exercice', x.debut + ' → ' + x.fin], ['Résultat net', C.money(x.resultat || 0)],
        ['Demandée par', x.demandePar || '—'], ['Validée par', x.validePar || '—'],
        ['Empreinte SHA-256', (x.empreinte || '').slice(0, 32) + '…'], ['Date d’édition', C.dateFR(AUJ)]],
      contenu: P.tableau([
        { label: 'Compte', key: 'compte' }, { label: 'Intitulé', key: 'libelle' },
        { label: 'Débit', value: function (l) { return C.money(l.debit, false); }, align: 'right', somme: function (l) { return l.debit; } },
        { label: 'Crédit', value: function (l) { return C.money(l.credit, false); }, align: 'right', somme: function (l) { return l.credit; } },
      ], lignes),
      signatures: [{ role: 'Le Comptable', nom: x.demandePar || '' }, { role: 'La Direction', nom: x.validePar || '' }],
    });
  }

  function ouvrirPreCloture(x, apresDemande) {
    var X = global.SIGH.exercice, pre = X.preCloture(x.annee);
    var corps = el('div.space-y-3');
    corps.appendChild(el('p.text-sm.text-slate-700', { html: 'Résultat provisoire de l’exercice ' + x.annee + ' : <strong>' + C.money(pre.resultat)
      + '</strong> sur ' + C.num(pre.nbEcritures) + ' ligne(s) validée(s).' }));
    corps.appendChild(K.miniTable(['Contrôle', 'Nature', 'État', 'Détail / où corriger'], pre.controles.map(function (c) {
      return [c.libelle, c.bloquant ? 'Bloquant' : 'Signalé', c.ok ? 'Conforme' : (c.bloquant ? 'ÉCHEC' : 'À voir'),
        c.ok ? '—' : (c.detail || '') + ' → ' + (global.SIGH.nav.get(c.ecran) ? global.SIGH.nav.get(c.ecran).label : c.ecran)];
    })));
    var pied = [K.btn('Fermer', { variant: 'secondary', onclick: function () { m.close(); } })];
    if (apresDemande && !pre.bloquants.length) pied.push(K.btn('Demander la clôture', { icon: 'lock', onclick: function () { m.close(); demander(x); } }));
    var m = U.modal({ title: 'Pré-clôture — exercice ' + x.annee, size: 'lg', body: corps, footer: pied });
  }

  function demander(x) {
    U.confirm({ title: 'Demander la clôture de l’exercice ' + x.annee + ' ?',
      message: 'Les contrôles bloquants sont rejoués. Si tout est conforme, la demande part à la <strong>Direction</strong> pour validation : '
        + 'tant qu’elle n’est pas validée, rien n’est figé.', confirmLabel: 'Demander la clôture' }).then(function (ok) {
      if (!ok) return;
      var r = global.SIGH.exercice.demander(x.annee);
      if (!r.ok) { U.toast('Demande refusée.', { type: 'error', detail: r.motif }); return; }
      U.toast('Clôture ' + x.annee + ' demandée.', { type: 'success', detail: 'La Direction doit la valider.' });
      global.location.reload();
    });
  }

  function valider(x) {
    var champ = el('textarea.input', { rows: 3, placeholder: 'Motif de la validation (obligatoire)', id: 'motif-cloture' });
    var m = U.modal({ title: 'Valider la clôture de l’exercice ' + x.annee, body: el('div.space-y-3', null, [
      el('p.text-sm.text-slate-700', { html: 'Demandée par <strong>' + U.texteEnrichi(x.demandePar || '—') + '</strong>. Cette validation est <strong>définitive</strong> : '
        + 'les classes 6, 7 et 8 seront soldées, les à-nouveaux de ' + (x.annee + 1) + ' écrits, l’exercice figé. Il ne se rouvre pas.' }), champ ]),
      footer: [K.btn('Annuler', { variant: 'secondary', onclick: function () { m.close(); } }),
        K.btn('Valider et clôturer', { icon: 'lock', variant: 'danger', onclick: function () {
          var r = global.SIGH.exercice.valider(x.annee, champ.value);
          if (!r.ok) { U.toast('Clôture refusée.', { type: 'error', detail: r.motif }); return; }
          m.close();
          U.toast('Exercice ' + x.annee + ' clos.', { type: 'success', detail: 'Résultat ' + C.money(r.resultat) + ' — ' + r.lignesAN + ' ligne(s) d’à-nouveau écrite(s).' });
          global.location.reload();
        } })] });
  }

  global.SIGH.screen('m12-cloture', {
    title: 'Exercices & clôtures',
    description: 'Sélecteur d’exercice, pré-clôture, clôture en deux gestes, à-nouveaux et lettrage des tiers.',
    regle: 'La clôture est <strong>définitive</strong> (obligation légale) : un exercice clos ne se rouvre pas, il se corrige par une écriture de '
      + 'l’exercice suivant. Le <strong>comptable demande</strong>, la <strong>Direction ou la DAF valide</strong> — une autre personne que le demandeur. '
      + 'La caisse continue d’encaisser : le logiciel ne s’arrête pas à la fin de l’année.',
    render: function () {
      var X = global.SIGH.exercice, host = el('div.space-y-4');
      var droits = K.droits('M12'), role = (S.session() || {}).role;
      var peutDemander = droits.editer && ['comptable', 'da', 'admin'].indexOf(role) >= 0;
      var peutValider = ['da', 'direction', 'admin'].indexOf(role) >= 0;
      var cur = X.de(X.choisi()), pre = X.preCloture(X.choisi());

      host.appendChild(U.kpiGrid([
        { label: 'Exercice affiché', value: String(X.choisi()), icon: 'calendar', tone: 'navy' },
        { label: 'État', value: ({ ouvert: 'Ouvert', en_attente_cloture: 'En attente', clos: 'Clos' })[cur ? cur.etat : 'ouvert'], icon: 'lock', tone: cur && cur.etat === 'clos' ? 'success' : 'info' },
        { label: cur && cur.etat === 'clos' ? 'Résultat net' : 'Résultat provisoire', value: C.money(cur && cur.etat === 'clos' ? cur.resultat : pre.resultat), icon: 'scale', tone: 'neutral' },
        { label: 'Contrôles bloquants en échec', value: C.num(pre.bloquants.length), icon: 'shield-alert', tone: pre.bloquants.length ? 'warning' : 'success' },
      ]));

      var onglets = [
        { id: 'exercices', label: 'Exercices', render: function () {
          return U.dataTable({
            title: 'Exercices comptables', rows: X.liste().map(function (x) { return Object.assign({}, x); }), exportName: 'exercices', pageSize: 10, searchable: false,
            columns: [
              { key: 'annee', label: 'Exercice', nowrap: true, text: function (x) { return 'Exercice ' + x.annee; }, render: function (x) { return 'Exercice ' + x.annee; } },
              { key: 'debut', label: 'Période', text: function (x) { return C.dateFR(x.debut) + ' → ' + C.dateFR(x.fin); }, render: function (x) { return C.dateFR(x.debut) + ' → ' + C.dateFR(x.fin); } },
              { key: 'etat', label: 'État', text: function (x) { return x.etat; }, render: function (x) {
                var t = { ouvert: ['Ouvert', 'success'], en_attente_cloture: ['En attente de clôture', 'warning'], clos: ['Clos', 'neutral'] }[x.etat] || [x.etat, 'neutral'];
                return U.badge(t[0], t[1]); } },
              { key: 'resultat', label: 'Résultat net', align: 'right', text: function (x) { return x.resultat == null ? '' : C.money(x.resultat, false); },
                render: function (x) { return x.resultat == null ? el('span.text-slate-400', { text: '—' }) : C.money(x.resultat); } },
              { key: 'validePar', label: 'Validée par', render: function (x) { return x.validePar ? x.validePar + ' — ' + C.dateFR(x.valideLe) : '—'; } },
              { key: 'empreinte', label: 'Empreinte', render: function (x) { return x.empreinte ? el('span.font-mono.text-xs', { text: x.empreinte.slice(0, 12) + '…' }) : '—'; } },
            ],
            rowActions: function (x) {
              var a = [];
              if (x.source === 'liasse') return [];
              if (x.etat === 'ouvert') {
                a.push(K.btn('Pré-clôture', { size: 'sm', variant: 'secondary', icon: 'list-checks', onclick: function () { ouvrirPreCloture(x, peutDemander); } }));
              }
              if (x.etat === 'en_attente_cloture' && peutValider) {
                a.push(K.btn('Valider la clôture', { size: 'sm', variant: 'primary', icon: 'lock', onclick: function () { valider(x); } }));
              }
              if (x.etat === 'clos') {
                a.push(K.btn('Procès-verbal', { size: 'sm', variant: 'secondary', icon: 'printer', onclick: function () { procesVerbalCloture(x); } }));
                a.push(K.commande('Archiver dans la GED', { size: 'sm', variant: 'secondary', icon: 'archive', onclick: function () { archiverDansGED(x); } }));
                a.push(K.btn('Exporter CSV', { size: 'sm', variant: 'secondary', icon: 'download', onclick: function () {
                  telechargerCSV('journal-' + x.annee, ['Pièce', 'Date', 'Journal', 'Compte', 'Libellé', 'Débit', 'Crédit'],
                    X.ecrituresDe(x.annee).map(function (e) { return [e.numero, e.date, e.journal, e.compte, e.libelle, e.debit, e.credit]; }));
                } }));
              }
              return a;
            },
          });
        } },
        { id: 'periodes', label: 'Périodes de l’exercice', render: function () {
          var e = ecritures().filter(function (x) { return !x.provisoire; });
          var rows = C.MOIS.map(function (m, i) {
            var sel = e.filter(function (x) { return C.toDate(x.date).getMonth() === i; });
            var d = C.sum(sel, 'debit'), c = C.sum(sel, 'credit');
            return { id: String(i), mois: m.charAt(0).toUpperCase() + m.slice(1) + ' ' + exo(), nb: sel.length, debit: d, credit: c,
              equilibre: d === c, brouillons: sel.filter(function (x) { return x.statut === 'brouillon'; }).length };
          });
          return U.dataTable({ title: 'Périodes comptables — exercice ' + exo(), rows: rows, exportName: 'periodes', pageSize: 12, searchable: false,
            columns: [
              { key: 'mois', label: 'Période', nowrap: true },
              { key: 'nb', label: 'Écritures', align: 'right' },
              { key: 'debit', label: 'Total débit', align: 'right', text: function (p) { return C.money(p.debit, false); }, render: function (p) { return C.money(p.debit, false); } },
              { key: 'credit', label: 'Total crédit', align: 'right', text: function (p) { return C.money(p.credit, false); }, render: function (p) { return C.money(p.credit, false); } },
              { key: 'equilibre', label: 'Équilibre', text: function (p) { return p.equilibre ? 'Équilibrée' : 'Déséquilibrée'; },
                render: function (p) { return !p.nb ? '—' : (p.equilibre ? U.badge('Équilibrée', 'success') : U.badge('Écart ' + C.money(Math.abs(p.debit - p.credit), false), 'danger')); } },
              { key: 'brouillons', label: 'Brouillons', align: 'right', render: function (p) { return p.brouillons ? el('span.font-semibold.text-warning-600', { text: String(p.brouillons) }) : '—'; } },
            ] });
        } },
        { id: 'lettrage', label: 'Lettrage des tiers', render: function () { return ecranLettrage(); } },
      ];
      host.appendChild(U.tabs(onglets));
      return host;
    },
  });

  /* LETTRAGE — un ensemble de lignes d'un compte de tiers dont le total s'annule.
     Seules les lignes NON lettrées sont reprises ligne à ligne aux à-nouveaux. */
  function ecranLettrage() {
    var X = global.SIGH.exercice, wrap = el('div.space-y-3');
    var tiers = Object.keys(C.groupBy(ecrituresToutes().filter(function (e) { return X.lettrable(e.compte); }), 'compte')).sort();
    var sel = el('select.select.w-auto');
    tiers.forEach(function (c) { sel.appendChild(el('option', { value: c }, c + ' — ' + compteLibelle(c))); });
    var zone = el('div');
    var droits = K.droits('M12');
    function dessiner() {
      C.clear(zone);
      var lignes = ecrituresToutes().filter(function (e) { return String(e.compte) === sel.value && X.anneeDe(e.date) === exo() && e.statut === 'validee'; });
      var coches = {};
      var tab = U.dataTable({ title: 'Lignes du compte ' + sel.value, rows: lignes.map(function (e) { return e; }), exportName: 'lettrage', pageSize: 10, searchable: true,
        columns: [
          { key: 'select', label: '', render: function (e) {
            if (e.lettrage || !droits.editer || X.etat(X.anneeDe(e.date)) === 'clos') return '';
            var cb = el('input', { type: 'checkbox', 'aria-label': 'Sélectionner ' + e.numero });
            cb.addEventListener('change', function () { if (cb.checked) coches[e.id] = true; else delete coches[e.id]; });
            return cb; } },
          { key: 'numero', label: 'Pièce', nowrap: true }, { key: 'date', label: 'Date', text: function (e) { return C.dateFR(e.date); }, render: function (e) { return C.dateFR(e.date); } },
          { key: 'libelle', label: 'Libellé' },
          { key: 'debit', label: 'Débit', align: 'right', text: function (e) { return C.money(e.debit, false); }, render: function (e) { return C.money(e.debit, false); } },
          { key: 'credit', label: 'Crédit', align: 'right', text: function (e) { return C.money(e.credit, false); }, render: function (e) { return C.money(e.credit, false); } },
          { key: 'lettrage', label: 'Lettrage', render: function (e) { return e.lettrage ? U.badge(e.lettrage, 'success') : el('span.text-slate-400', { text: 'non lettrée' }); } },
        ] });
      zone.appendChild(tab);
      if (droits.editer) {
        zone.appendChild(el('div.flex.gap-2.mt-3', null, [
          K.btn('Lettrer la sélection', { icon: 'link', onclick: function () {
            var r = X.lettrer(sel.value, Object.keys(coches));
            if (!r.ok) { U.toast('Lettrage refusé.', { type: 'error', detail: r.motif }); return; }
            U.toast('Lettrage « ' + r.code + ' » posé sur ' + r.lignes + ' ligne(s).', { type: 'success' }); dessiner(); } }),
          K.btn('Dé-lettrer un code…', { variant: 'secondary', icon: 'unlink', onclick: function () {
            var code = global.prompt('Code de lettrage à défaire sur le compte ' + sel.value + ' :'); if (!code) return;
            var motif = global.prompt('Motif (obligatoire) :'); var r = X.delettrer(sel.value, code.toUpperCase(), motif);
            if (!r.ok) { U.toast('Dé-lettrage refusé.', { type: 'error', detail: r.motif }); return; }
            U.toast(r.lignes + ' ligne(s) dé-lettrée(s).', { type: 'success' }); dessiner(); } }),
        ]));
      }
    }
    sel.addEventListener('change', dessiner);
    wrap.appendChild(K.note('Un lettrage rapproche des lignes d’un <strong>même compte de tiers</strong> dont le total s’annule (une facture et son règlement). '
      + 'À la clôture, seules les lignes <strong>non lettrées</strong> sont reprises une à une aux à-nouveaux.', { tone: 'info', icon: 'link' }));
    if (!tiers.length) { wrap.appendChild(el('p.text-sm.text-slate-500', { text: 'Aucun compte de tiers mouvementé.' })); return wrap; }
    wrap.appendChild(el('label.flex.items-center.gap-2.text-sm', null, [el('span', { text: 'Compte' }), sel]));
    wrap.appendChild(zone); dessiner();
    return wrap;
  }

  /* ==========================================================================
   * BILAN D'OUVERTURE
   * ======================================================================== */
  global.SIGH.screen('m12-ouverture', {
    title: 'Bilan d’ouverture & à-nouveaux',
    description: 'Report des soldes de bilan au 1ᵉʳ janvier — les à-nouveaux, écrits au journal AN.',
    regle: 'Seules les <strong>classes 1 à 5</strong> se reportent : un compte de charge ou de produit '
      + 'ne passe jamais à l’exercice suivant, il est soldé par le <strong>résultat</strong>, qui '
      + 's’inscrit au compte 13 du passif. Le reporter reviendrait à compter deux fois la même dépense. '
      + 'Le report est <strong>refusé s’il ne s’équilibre pas</strong> (RG-10) : un à-nouveau boiteux '
      + 'propagerait le déséquilibre à toutes les années suivantes. La pièce naît en '
      + '<strong>brouillon</strong> — la validation reste un geste humain.',
    render: ecranOuverture,
  });


  /* ==========================================================================
   * LE BILAN D'OUVERTURE — LES À-NOUVEAUX
   * --------------------------------------------------------------------------
   * Un exercice s'ouvrait sur un journal vide : les soldes de bilan de l'année
   * close ne se reportaient nulle part, et le bilan d'ouverture n'existait
   * pas. Il fallait donc relire tout l'historique pour connaître la situation
   * au 1ᵉʳ janvier — ce que la comptabilité s'interdit précisément de faire.
   *
   * LA RÈGLE, ET ELLE EST STRICTE : seules les classes 1 à 5 se reportent.
   * Un compte de CHARGE ou de PRODUIT ne passe JAMAIS à l'exercice suivant —
   * il est soldé par le résultat, qui s'inscrit au passif (compte 13). Le
   * reporter reviendrait à compter deux fois la même dépense.
   *
   * L'à-nouveau est UNE PIÈCE, équilibrée par construction (RG-10) : la somme
   * des soldes débiteurs égale la somme des soldes créditeurs si l'exercice
   * clos était lui-même équilibré. S'il ne l'est pas, on REFUSE en le disant —
   * un à-nouveau boiteux propagerait le déséquilibre à toutes les années
   * suivantes.
   * ======================================================================== */
  var CLASSES_REPORTABLES = ['1', '2', '3', '4', '5'];

  /** Les soldes de bilan à la clôture d'un exercice. */
  function soldesDeCloture(annee) {
    var lignes = ecrituresToutes().filter(function (x) {
      return x.statut === 'validee' && C.toDate(x.date).getFullYear() <= annee;
    });
    var parCompte = {};
    lignes.forEach(function (x) {
      var num = String(x.compte || '');
      if (CLASSES_REPORTABLES.indexOf(num.charAt(0)) === -1) return;
      if (!parCompte[num]) parCompte[num] = { compte: num, debit: 0, credit: 0 };
      parCompte[num].debit += Number(x.debit) || 0;
      parCompte[num].credit += Number(x.credit) || 0;
    });
    /* LE RÉSULTAT DE L'EXERCICE CLOS entre au passif : c'est lui qui équilibre
       le report, puisque les classes 6 et 7 ne se reportent pas. */
    var resultat = 0;
    ecrituresToutes().filter(function (x) {
      return x.statut === 'validee' && C.toDate(x.date).getFullYear() === annee;
    }).forEach(function (x) {
      var cl = String(x.compte || '').charAt(0);
      if (cl === '7') resultat += (Number(x.credit) || 0) - (Number(x.debit) || 0);
      if (cl === '6') resultat -= (Number(x.debit) || 0) - (Number(x.credit) || 0);
    });

    var out = Object.keys(parCompte).map(function (k) {
      var c = parCompte[k];
      return { compte: c.compte, libelle: compteLibelle(c.compte), solde: c.debit - c.credit };
    }).filter(function (c) { return c.solde !== 0; });

    return { comptes: C.sortBy(out, 'compte'), resultat: resultat };
  }

  function ecranOuverture(root) {
    var host = el('div.space-y-4');
    root.appendChild(host);
    var anneeSel = el('select.select.w-auto');
    var annees = {};
    ecrituresToutes().forEach(function (x) { annees[C.toDate(x.date).getFullYear()] = true; });
    var listeAnnees = Object.keys(annees).sort();
    listeAnnees.forEach(function (a) {
      anneeSel.appendChild(el('option', { value: a }, 'Exercice ' + a));
    });
    anneeSel.value = listeAnnees[listeAnnees.length - 1] || String(AUJ.getFullYear());
    anneeSel.addEventListener('change', afficher);

    var vue = el('div.space-y-4');
    host.appendChild(U.card('Exercice à reporter', el('div.flex.flex-wrap.items-end.gap-3', null, [
      el('div', null, [el('label.label', { text: 'Exercice clos' }), anneeSel]),
      K.commande('Écrire les à-nouveaux', {
        variant: 'primary', icon: 'file-plus', onclick: function () { ecrire(); },
      }),
      K.btn('Imprimer le bilan d’ouverture', { icon: 'printer', onclick: function () { imprimer(); } }),
    ].filter(Boolean))));
    host.appendChild(vue);
    afficher();
    U.icons(host);
    return null;

    function annee() { return Number(anneeSel.value); }
    function suivante() { return annee() + 1; }
    function dejaEcrit() {
      return ecrituresToutes().filter(function (x) {
        return x.journal === 'AN' && C.toDate(x.date).getFullYear() === suivante();
      });
    }

    function afficher() {
      C.clear(vue);
      var s = soldesDeCloture(annee());
      var debiteurs = s.comptes.filter(function (c) { return c.solde > 0; });
      var crediteurs = s.comptes.filter(function (c) { return c.solde < 0; });
      var totalD = C.sum(debiteurs, 'solde');
      var totalC = -C.sum(crediteurs, 'solde');
      /* Le résultat vient équilibrer : bénéfice au crédit, perte au débit. */
      var ecart = totalD - (totalC + s.resultat);
      var deja = dejaEcrit();

      vue.appendChild(U.kpiGrid([
        { label: 'Comptes à reporter', value: C.num(s.comptes.length), icon: 'list', tone: 'navy',
          hint: 'Classes 1 à 5 seulement' },
        { label: 'Total des soldes débiteurs', value: C.money(totalD), icon: 'arrow-down-right', tone: 'info' },
        { label: 'Total des soldes créditeurs', value: C.money(totalC), icon: 'arrow-up-right', tone: 'info' },
        { label: 'Résultat de l’exercice ' + annee(), value: C.money(s.resultat),
          icon: s.resultat >= 0 ? 'smile' : 'frown', tone: s.resultat >= 0 ? 'success' : 'danger',
          hint: 'Compte 13 — il équilibre le report' },
      ]));

      vue.appendChild(Math.abs(ecart) < 1
        ? K.note('Le report <strong>s’équilibre</strong> : soldes débiteurs '
          + C.money(totalD) + ' = soldes créditeurs ' + C.money(totalC) + ' + résultat '
          + C.money(s.resultat) + '. L’à-nouveau peut être écrit.', { tone: 'success', icon: 'scale' })
        : K.note('Le report <strong>NE S’ÉQUILIBRE PAS</strong> — écart de ' + C.money(ecart)
          + '. L’à-nouveau est refusé : un report boiteux propagerait le déséquilibre à toutes les '
          + 'années suivantes (RG-10). Vérifier les écritures de l’exercice ' + annee() + ' avant de '
          + 'reporter.', { tone: 'danger', icon: 'alert-triangle' }));

      if (deja.length) {
        vue.appendChild(K.note('Les à-nouveaux du <strong>1ᵉʳ janvier ' + suivante() + '</strong> sont '
          + 'DÉJÀ écrits : ' + C.num(deja.length) + ' ligne(s) au journal AN. Les réécrire créerait un '
          + 'double report — la pièce existante fait foi.', { tone: 'warning', icon: 'file-check' }));
      }

      vue.appendChild(U.card('Bilan d’ouverture au 1ᵉʳ janvier ' + suivante()
        + ' — à-nouveaux des classes 1 à 5',
        K.miniTable([
          { label: 'Compte', key: 'compte' },
          { label: 'Intitulé', key: 'libelle' },
          { label: 'Débit', align: 'right',
            render: function (c) { return c.solde > 0 ? C.money(c.solde, false) : ''; } },
          { label: 'Crédit', align: 'right',
            render: function (c) { return c.solde < 0 ? C.money(-c.solde, false) : ''; } },
        ], s.comptes.concat([
          { compte: '13', libelle: 'Résultat net de l’exercice ' + annee(),
            solde: -s.resultat },
        ]))));

      vue.appendChild(K.note('<strong>Seules les classes 1 à 5 se reportent.</strong> Un compte de '
        + 'charge (classe 6) ou de produit (classe 7) ne passe jamais à l’exercice suivant : il est '
        + 'soldé par le résultat, qui s’inscrit au compte 13 du passif. Le reporter reviendrait à '
        + 'compter deux fois la même dépense.', { tone: 'info', icon: 'book-open-check' }));
      U.icons(vue);
    }

    function ecrire() {
      var s = soldesDeCloture(annee());
      var totalD = C.sum(s.comptes.filter(function (c) { return c.solde > 0; }), 'solde');
      var totalC = -C.sum(s.comptes.filter(function (c) { return c.solde < 0; }), 'solde');
      var ecart = totalD - (totalC + s.resultat);
      if (Math.abs(ecart) >= 1) {
        U.toast('Report refusé — écart de ' + C.money(ecart) + ' (RG-10).', {
          type: 'error',
          detail: 'Un à-nouveau boiteux propagerait le déséquilibre à toutes les années suivantes.',
        });
        return;
      }
      if (dejaEcrit().length) {
        U.toast('Les à-nouveaux du 1ᵉʳ janvier ' + suivante() + ' existent déjà.', {
          type: 'error', detail: 'Les réécrire créerait un double report.',
        });
        return;
      }
      U.confirm({
        title: 'Écrire les à-nouveaux du 1ᵉʳ janvier ' + suivante() + ' ?',
        message: C.num(s.comptes.length) + ' compte(s) de bilan seront reportés, plus le résultat de '
          + 'l’exercice ' + annee() + ' (' + C.money(s.resultat) + ') au compte 13. La pièce naît en '
          + '<strong>brouillon</strong> : la validation reste un geste humain.',
        confirmLabel: 'Écrire le report',
      }).then(function (rep) {
        if (!rep) return;
        var col = S.collection('ecritures', { module: 'M12', entite: 'Écriture' });
        var numero = 'AN-' + suivante() + '-00001';
        var base = {
          numero: numero, date: suivante() + '-01-01',
          journal: 'AN', journalLibelle: 'Journal des à-nouveaux',
          libelle: 'À-nouveaux au 1er janvier ' + suivante(),
          origine: 'Automatique — report d’exercice', statut: 'brouillon',
          centreCout: null,
        };
        var ecrits = [];
        s.comptes.forEach(function (c) {
          ecrits.push(col.insert(Object.assign({}, base, {
            compte: c.compte, compteLibelle: c.libelle,
            debit: c.solde > 0 ? c.solde : 0,
            credit: c.solde < 0 ? -c.solde : 0,
          })));
        });
        ecrits.push(col.insert(Object.assign({}, base, {
          compte: '130000', compteLibelle: 'Résultat net de l’exercice ' + annee(),
          debit: s.resultat < 0 ? -s.resultat : 0,
          credit: s.resultat > 0 ? s.resultat : 0,
        })));
        afficher();
        U.toast('À-nouveaux écrits — ' + C.num(ecrits.length) + ' ligne(s) au journal AN.', {
          type: 'success', detail: 'Pièce ' + numero + ', en brouillon.',
          undo: function () { ecrits.forEach(function (x) { x.undo(); }); afficher(); },
          undoMessage: 'Report annulé.',
        });
      });
    }

    function imprimer() {
      var s = soldesDeCloture(annee());
      var lignes = s.comptes.concat([
        { compte: '130000', libelle: 'Résultat net de l’exercice ' + annee(), solde: -s.resultat },
      ]);
      P.etat({
        titre: 'Bilan d’ouverture — à-nouveaux',
        sousTitre: 'Au 1ᵉʳ janvier ' + suivante() + ', report de l’exercice ' + annee(),
        filtres: false,
        cartouche: [['Exercice clos', String(annee())],
          ['Ouverture au', '1ᵉʳ janvier ' + suivante()],
          ['Journal', 'AN — Journal des à-nouveaux'],
          ['Comptes reportés', C.num(s.comptes.length)],
          ['Résultat reporté', C.money(s.resultat)],
          ['Référentiel', 'Plan comptable SYSCOHADA révisé']],
        contenu: el('div.space-y-3', null, [
          P.tableau([
            { label: 'Compte', key: 'compte' },
            { label: 'Intitulé', key: 'libelle' },
            { label: 'Débit', align: 'right',
              value: function (c) { return c.solde > 0 ? C.money(c.solde, false) : ''; },
              somme: function (c) { return c.solde > 0 ? c.solde : 0; } },
            { label: 'Crédit', align: 'right',
              value: function (c) { return c.solde < 0 ? C.money(-c.solde, false) : ''; },
              somme: function (c) { return c.solde < 0 ? -c.solde : 0; } },
          ], lignes, { total: true, totalLabel: 'TOTAUX DU REPORT' }),
          el('p.mt-3.text-\\[10px\\].italic', {
            text: 'Seules les classes 1 à 5 sont reportées : un compte de charge ou de produit ne '
              + 'passe jamais à l’exercice suivant, il est soldé par le résultat. Les deux totaux '
              + 'doivent être égaux (RG-10).',
          }),
        ]),
        signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
          { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }],
      });
    }
  }

  /* ==========================================================================
   * LES DEUX ANOMALIES DU CLASSEUR 2025 — DIAGNOSTIC, PAS RÉPARATION
   * --------------------------------------------------------------------------
   * La Direction a demandé de corriger (26/08/2026). Corriger un écart, ce
   * n'est pas le gommer : c'est trouver la ligne qui l'explique et dire
   * laquelle des deux sources fait foi.
   *
   * Le diagnostic est CALCULÉ à chaque affichage, jamais écrit en dur :
   * `npm run compta` régénère data-compta.js depuis le classeur Excel, et un
   * montant codé ici serait faux à la première régénération.
   * ======================================================================== */

  /* Cherche la ligne dont une ÉCHÉANCE MENSUELLE vaut exactement l'écart.
     Un écart d'arrondi ne tombe pas sur un montant que le classeur porte par
     ailleurs : la coïncidence, si elle existe, est l'explication. */
  function expliquerEcart(E) {
    var ecart = Math.abs(E.controle.ecart || 0);
    if (!ecart) return null;

    var mensuelles = [], totales = [];
    (E.depenses || []).forEach(function (d) {
      var mois = [];
      (d.mois || []).forEach(function (m, i) { if (Math.round(m) === ecart) mois.push(i); });
      if (mois.length) mensuelles.push({ ligne: d, mois: mois });
      if (Math.round(d.total) === ecart) totales.push(d);
    });

    /* Contrôle préalable : chaque ligne du détail somme-t-elle à son propre
       total ? Si non, l'écart vient du détail et non de la ligne TOTAL. */
    var incoherentes = (E.depenses || []).filter(function (d) {
      var somme = (d.mois || []).reduce(function (a, b) { return a + b; }, 0);
      return Math.round((somme - d.total) * 100) !== 0;
    });

    return { ecart: ecart, mensuelles: mensuelles, totales: totales, incoherentes: incoherentes };
  }

  /* Rattachement PROPOSÉ des trois postes sans numéro de compte. Les trois
     relèvent du même emprunt bancaire ; le classeur porte déjà les comptes
     d'accueil, ce qui rend la proposition vérifiable plutôt qu'inventée. */
  var COMPTES_PROPOSES = {
    'FONDS DE GARANTIE': {
      compte: '275000', intitule: 'Dépôts et cautionnements versés',
      motif: 'Un fonds de garantie adossé à un emprunt est un dépôt, non une charge. '
        + 'Le classeur porte déjà ce compte pour ses autres cautionnements.',
    },
    'FRAIS DOSSIER SUR EMPRUNT': {
      compte: '631800', intitule: 'Autres frais bancaires',
      motif: 'Frais perçus par la banque à l’ouverture du dossier : même nature que les '
        + 'comptes 631810, 631820 et 631830 déjà utilisés par le classeur.',
    },
    'TAXE SUR EMPRUNT': {
      compte: '646800', intitule: 'Autres droits',
      motif: 'Droit assis sur l’emprunt, de même nature que la cotisation CCIB déjà '
        + 'imputée à ce compte dans le classeur.',
    },
  };

  function propositionCompte(libelle) {
    return COMPTES_PROPOSES[String(libelle || '').trim().toUpperCase()] || null;
  }

  /* ==========================================================================
   * BASELINE 2025 — compte de résultat réel de l'exercice précédent
   * ======================================================================== */
  global.SIGH.screen('m12-baseline-2025', {
    title: 'Baseline financière 2025',
    description: 'Compte de résultat réel de l’exercice 2025, servant de référence de comparaison à l’exercice courant.',
    regle: 'Le compte de résultat 2025 n’est pas un simple archivage : il constitue la <strong>référence de comparaison</strong> '
      + 'des tableaux de bord (2025 réel / 2026 réel / budget 2026), conformément au principe de reprise des documents de cadrage.',
    render: function (root) {
      var E = global.SIGH.compta.EXERCICE_2025;
      var host = el('div.space-y-4');
      var moisCourts = E.mois.map(function (m) { return m.slice(0, 4) + '. 25'; });

      host.appendChild(U.kpiGrid([
        { label: 'Chiffre d’affaires 2025', value: C.money(E.totalChiffreAffaires), icon: 'trending-up', tone: 'success' },
        { label: 'Charges d’exploitation', value: C.money(E.totalCharges), icon: 'trending-down', tone: 'warning' },
        {
          label: 'Résultat 2025', value: C.money(E.resultat),
          icon: E.resultat >= 0 ? 'smile' : 'frown', tone: E.resultat >= 0 ? 'success' : 'danger',
          hint: C.pct(E.totalChiffreAffaires ? E.resultat / E.totalChiffreAffaires * 100 : 0) + ' du chiffre d’affaires',
        },
        { label: 'Chiffre d’affaires moyen', value: C.money(E.totalChiffreAffaires / 12), icon: 'calendar', tone: 'navy', hint: 'par mois' },
        { label: 'Meilleur mois', value: C.MOIS[E.chiffreAffaires.indexOf(Math.max.apply(null, E.chiffreAffaires))], icon: 'award', tone: 'success', hint: C.money(Math.max.apply(null, E.chiffreAffaires)) },
        { label: 'Mois le plus faible', value: C.MOIS[E.chiffreAffaires.indexOf(Math.min.apply(null, E.chiffreAffaires))], icon: 'trending-down', tone: 'neutral', hint: C.money(Math.min.apply(null, E.chiffreAffaires)) },
        { label: 'Postes de charges', value: C.num(E.postesCharges().length), icon: 'list', tone: 'info' },
        { label: 'Hors exploitation', value: C.money(E.totalHorsExploitation), icon: 'landmark', tone: 'neutral', hint: 'Emprunt, cautionnements, immobilisation' },
      ]));

      /* Contrôles relevés sur le classeur source */
      var ctrl = E.controle;
      if (ctrl.postesSansCompte || ctrl.ecart) {
        var alertes = el('div.space-y-3');

        /* --- L'ÉCART, EXPLIQUÉ ----------------------------------------- */
        if (ctrl.ecart) {
          var diag = expliquerEcart(E);
          alertes.appendChild(K.note('<strong>Écart de ' + C.money(Math.abs(ctrl.ecart)) + '</strong> entre la ligne '
            + '« TOTAL » du classeur (' + C.money(ctrl.totalClasseur) + ') et la somme de son propre détail ('
            + C.money(ctrl.totalDetail) + ').', { tone: 'danger', icon: 'scale-3d' }));

          if (diag && !diag.incoherentes.length && diag.mensuelles.length) {
            var l = diag.mensuelles[0];
            var moisNoms = l.mois.map(function (i) { return C.MOIS[i]; }).join(' et ');
            alertes.appendChild(K.note('<strong>Diagnostic : l’écart n’est pas un arrondi.</strong> '
              + 'Les ' + (E.depenses || []).length + ' lignes du détail somment <strong>exactement</strong> à leur '
              + 'propre total — le détail est cohérent avec lui-même. Et le montant de l’écart, '
              + C.money(diag.ecart) + ', est <strong>précisément l’échéance mensuelle</strong> de la ligne '
              + '« ' + l.ligne.libelle + ' » (' + moisNoms + '). La ligne « TOTAL » du classeur '
              + '<strong>omet une échéance</strong> ; c’est elle qui est fautive, non le détail.<br>'
              + '<strong>Conséquence retenue :</strong> la baseline s’appuie sur le détail, soit '
              + C.money(ctrl.totalDetail) + '. Le service comptable est invité à corriger la formule de '
              + 'totalisation du classeur — la correction porte sur le document source, pas sur le logiciel.',
              { tone: 'info', icon: 'search-check' }));
          } else if (diag && diag.incoherentes.length) {
            alertes.appendChild(K.note('<strong>' + diag.incoherentes.length + ' ligne(s) ne somment pas à leur '
              + 'propre total</strong> : l’écart vient du détail lui-même et non de la ligne TOTAL. À reprendre '
              + 'ligne par ligne avec le service comptable.', { tone: 'warning', icon: 'triangle-alert' }));
          }
        }

        /* --- LES POSTES SANS COMPTE, AVEC LEUR RATTACHEMENT PROPOSÉ ----- */
        if (ctrl.postesSansCompte) {
          var sansCompte = (E.depenses || []).filter(function (d) { return !d.num; });
          alertes.appendChild(K.note('<strong>' + ctrl.postesSansCompte + ' poste(s) de dépense sans numéro de '
            + 'compte</strong> dans le classeur source, pour ' + C.money(ctrl.montantSansCompte) + '. Les trois '
            + 'relèvent du <strong>même emprunt bancaire</strong>. Un rattachement est proposé ci-dessous : '
            + 'c’est une <strong>proposition à valider</strong> par le service comptable, pas une imputation '
            + 'appliquée — rattacher d’office un montant à un compte fausserait la balance sans que personne '
            + 'ne l’ait décidé.', { tone: 'warning', icon: 'help-circle' }));

          alertes.appendChild(K.miniTable([
            { key: 'poste', label: 'Poste du classeur' },
            { key: 'montant', label: 'Montant 2025', align: 'right' },
            {
              key: 'compte', label: 'Compte proposé',
              render: function (r) {
                if (!r.compte) return el('span.text-xs.italic.text-slate-400', { text: 'à déterminer' });
                return el('div', null, [
                  el('span.font-mono.text-xs.font-semibold', { text: r.compte }),
                  el('p.text-[10px].text-slate-500', { text: r.intitule }),
                ]);
              },
            },
            {
              key: 'motif', label: 'Pourquoi ce compte',
              render: function (r) { return el('span.text-xs.text-slate-600', { text: r.motif }); },
            },
          ], sansCompte.map(function (d) {
            var pr = propositionCompte(d.libelle);
            return {
              poste: d.libelle,
              montant: C.money(d.total, false),
              compte: pr ? pr.compte : null,
              intitule: pr ? pr.intitule : '',
              motif: pr ? pr.motif : 'Aucune proposition : le libellé ne permet pas de trancher.',
            };
          })));
        }

        host.appendChild(U.card('Contrôles de cohérence du document source', alertes));
      }

      host.appendChild(K.charts([
        {
          title: 'Chiffre d’affaires mensuel 2025',
          render: function () {
            return G.barres(moisCourts, [{ label: 'Chiffre d’affaires', data: E.chiffreAffaires, color: G.TONES.vert }]);
          },
        },
        {
          title: 'Chiffre d’affaires, charges et résultat',
          render: function () {
            var charges = E.mois.map(function (_, i) { return Math.round(E.chargesDuMois(i)); });
            var resultats = E.mois.map(function (_, i) { return Math.round(E.resultatDuMois(i)); });
            return G.ligne(moisCourts, [
              { label: 'Chiffre d’affaires', data: E.chiffreAffaires, color: G.TONES.vert, fill: false },
              { label: 'Charges', data: charges, color: G.TONES.rouge, fill: false },
              { label: 'Résultat', data: resultats, color: G.TONES.navy, fill: false },
            ]);
          },
        },
      ]));

      host.appendChild(U.tabs([
        {
          id: 'mensuel', label: 'Détail mensuel',
          render: function () {
            var rows = E.mois.map(function (m, i) {
              return {
                id: String(i), mois: m.charAt(0).toUpperCase() + m.slice(1) + ' 2025',
                ca: E.chiffreAffaires[i],
                charges: Math.round(E.chargesDuMois(i)),
                resultat: Math.round(E.resultatDuMois(i)),
                marge: E.chiffreAffaires[i] ? Math.round(E.resultatDuMois(i) / E.chiffreAffaires[i] * 100) : 0,
              };
            });
            return U.dataTable({
              rows: rows, exportName: 'baseline-2025-mensuel', pageSize: 13, searchable: false,
              columns: [
                { key: 'mois', label: 'Mois', nowrap: true },
                { key: 'ca', label: 'Chiffre d’affaires', align: 'right', text: function (r) { return C.money(r.ca, false); }, render: function (r) { return el('span.font-semibold.text-success-700', { text: C.money(r.ca, false) }); } },
                { key: 'charges', label: 'Charges', align: 'right', text: function (r) { return C.money(r.charges, false); }, render: function (r) { return el('span.text-danger-600', { text: C.money(r.charges, false) }); } },
                {
                  key: 'resultat', label: 'Résultat', align: 'right',
                  text: function (r) { return C.money(r.resultat, false); },
                  render: function (r) {
                    return el('span.font-bold', { class: r.resultat >= 0 ? 'text-success-700' : 'text-danger-600', text: C.money(r.resultat, false) });
                  },
                },
                { key: 'marge', label: 'Marge', align: 'right', render: function (r) { return U.badge(r.marge + ' %', r.marge >= 0 ? 'success' : 'danger'); } },
              ],
            });
          },
        },
        {
          id: 'charges', label: 'Postes de charges', badge: E.postesCharges().length,
          render: function () {
            var postes = E.postesCharges();
            return el('div.space-y-3', null, [
              K.ranking(postes.slice(0, 12).map(function (p) {
                return { label: p.libelle, value: p.total };
              }), { format: function (v) { return C.money(v, false); }, tone: 'warning' }),
              U.dataTable({
                rows: postes, exportName: 'baseline-2025-charges', pageSize: 20,
                defaultSort: 'total', defaultDir: 'desc',
                columns: [
                  {
                    key: 'num', label: 'Compte', nowrap: true,
                    render: function (p) {
                      return p.num
                        ? el('span.font-mono.text-xs.font-semibold', { text: p.num })
                        : U.badge('À rattacher', 'warning');
                    },
                  },
                  { key: 'libelle', label: 'Poste de charge' },
                  {
                    key: 'total', label: 'Total 2025', align: 'right',
                    text: function (p) { return C.money(p.total, false); },
                    render: function (p) { return el('span.font-semibold', { text: C.money(p.total, false) }); },
                  },
                  {
                    key: 'moyenne', label: 'Moyenne mensuelle', align: 'right',
                    value: function (p) { return p.total / 12; },
                    text: function (p) { return C.money(p.total / 12, false); },
                    render: function (p) { return C.money(p.total / 12, false); },
                  },
                  {
                    key: 'poids', label: 'Poids', align: 'right',
                    value: function (p) { return p.total / E.totalCharges * 100; },
                    render: function (p) { return U.badge(C.pct(p.total / E.totalCharges * 100), 'neutral'); },
                  },
                ],
              }),
            ]);
          },
        },
        {
          id: 'comparaison', label: 'Comparaison 2025 / 2026',
          render: function () {
            var factures = S.collection('factures').active();
            var rows = E.mois.map(function (m, i) {
              var ca2026 = C.sum(factures.filter(function (f) {
                var d = C.toDate(f.date);
                return d.getFullYear() === 2026 && d.getMonth() === i;
              }), 'montantTTC');
              var ca2025 = E.chiffreAffaires[i];
              return {
                id: String(i), mois: m.charAt(0).toUpperCase() + m.slice(1),
                ca2025: ca2025, ca2026: ca2026,
                ecart: ca2026 - ca2025,
                evolution: ca2025 ? Math.round((ca2026 - ca2025) / ca2025 * 100) : 0,
              };
            });
            return el('div.space-y-3', null, [
              K.note('L’exercice 2026 est alimenté par le jeu de démonstration du prototype : la comparaison illustre le mécanisme, '
                + 'elle ne reflétera l’activité réelle qu’après la bascule en production.', { tone: 'info' }),
              U.card('Chiffre d’affaires 2025 et 2026',
                G.barres(moisCourts.map(function (m) { return m.slice(0, 4); }), [
                  { label: '2025 (réel)', data: rows.map(function (r) { return r.ca2025; }), color: G.TONES.navy },
                  { label: '2026 (prototype)', data: rows.map(function (r) { return r.ca2026; }), color: G.TONES.vert },
                ])),
              U.dataTable({
                rows: rows, exportName: 'comparaison-2025-2026', pageSize: 13, searchable: false,
                columns: [
                  { key: 'mois', label: 'Mois', nowrap: true },
                  { key: 'ca2025', label: 'CA 2025 (réel)', align: 'right', text: function (r) { return C.money(r.ca2025, false); }, render: function (r) { return C.money(r.ca2025, false); } },
                  { key: 'ca2026', label: 'CA 2026', align: 'right', text: function (r) { return C.money(r.ca2026, false); }, render: function (r) { return C.money(r.ca2026, false); } },
                  {
                    key: 'ecart', label: 'Écart', align: 'right',
                    text: function (r) { return C.money(r.ecart, false); },
                    render: function (r) {
                      return el('span', { class: r.ecart >= 0 ? 'text-success-700' : 'text-danger-600', text: (r.ecart > 0 ? '+' : '') + C.money(r.ecart, false) });
                    },
                  },
                  {
                    key: 'evolution', label: 'Évolution', align: 'right',
                    render: function (r) { return U.badge((r.evolution > 0 ? '+' : '') + r.evolution + ' %', r.evolution >= 0 ? 'success' : 'danger'); },
                  },
                ],
              }),
            ]);
          },
        },
      ]));

      host.appendChild(K.source('Classeur comptable SYSCOHADA et compte de résultat 2025 — feuilles « DEPENSES25 » et « Recette ».'));
      root.appendChild(host);
      return null;
    },
    actions: function () {
      return [K.btn('Imprimer le compte de résultat 2025', {
        variant: 'primary', icon: 'printer',
        onclick: function () {
          var E = global.SIGH.compta.EXERCICE_2025;
          P.etat({
            titre: 'Compte de résultat — exercice 2025',
            sousTitre: 'Baseline financière de référence',
            cartouche: [
              ['Exercice', '2025'],
              ['Chiffre d’affaires', C.money(E.totalChiffreAffaires)],
              ['Charges d’exploitation', C.money(E.totalCharges)],
              ['Résultat', C.money(E.resultat)],
              ['Hors exploitation', C.money(E.totalHorsExploitation)],
              ['Date d’édition', C.dateFR(AUJ)],
            ],
            contenu: el('div.space-y-4', null, [
              el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Chiffre d’affaires mensuel' }),
              P.tableau([
                { label: 'Mois', key: 'm' },
                { label: 'Chiffre d’affaires', key: 'ca', align: 'right' },
                { label: 'Charges', key: 'ch', align: 'right' },
                { label: 'Résultat', key: 'res', align: 'right' },
              ], E.mois.map(function (m, i) {
                return {
                  m: m.charAt(0).toUpperCase() + m.slice(1),
                  ca: C.money(E.chiffreAffaires[i], false),
                  ch: C.money(Math.round(E.chargesDuMois(i)), false),
                  res: C.money(Math.round(E.resultatDuMois(i)), false),
                };
              }), {
                total: {
                  m: 'TOTAL 2025', ca: C.money(E.totalChiffreAffaires, false),
                  ch: C.money(E.totalCharges, false), res: C.money(E.resultat, false),
                },
                totalLabel: '',
              }),
              el('p.mt-4.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Postes de charges' }),
              P.tableau([
                { label: 'Compte', value: function (p) { return p.num || '(à rattacher)'; } },
                { label: 'Libellé', key: 'libelle' },
                { label: 'Total 2025', align: 'right', value: function (p) { return C.money(p.total, false); },
                  somme: function (p) { return p.total || 0; } },
                { label: 'Poids', align: 'right', value: function (p) { return C.pct(p.total / E.totalCharges * 100); } },
              ], E.postesCharges(), { total: true }),
              el('p.mt-3.text-\\[9px\\].italic.text-slate-600', {
                text: 'Les postes « emprunt », « dépôts et cautionnements » et « matériel de bureau » figurant au classeur des '
                  + 'dépenses constituent des mouvements de bilan et sont exclus des charges d’exploitation retenues ci-dessus.',
              }),
            ]),
            signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
              { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
          });
        },
      })];
    },
  });
  /* ==========================================================================
   * ÉCHÉANCES FISCALES & PAIEMENTS
   * --------------------------------------------------------------------------
   * Demande de la Direction : que le logiciel prévienne des paiements à venir,
   * rappelle ceux qui approchent, et permette de valider un paiement effectué.
   *
   * Le calendrier fiscal donne les obligations ; cet écran les déroule sur
   * l'exercice, en fait des échéances datées, et suit leur état :
   *   à venir · déclaration attendue · à payer · en retard · payé.
   *
   * Une échéance dépassée et non payée est un risque de pénalité — elle est
   * donc signalée à l'ouverture, et pas seulement listée.
   * ======================================================================== */
  function colEcheances() { return S.collection('echeancesFiscales', { module: 'M12', entite: 'échéance fiscale', prefix: 'ECH' }); }

  var ETATS_ECHEANCE = [
    { id: 'payee', label: 'Payée', tone: 'success' },
    { id: 'en_retard', label: 'En retard', tone: 'danger' },
    { id: 'a_payer', label: 'À payer', tone: 'warning' },
    { id: 'declaration', label: 'Déclaration attendue', tone: 'info' },
    { id: 'a_venir', label: 'À venir', tone: 'neutral' },
  ];

  function etatEcheance(id) {
    return ETATS_ECHEANCE.filter(function (e) { return e.id === id; })[0] || ETATS_ECHEANCE[4];
  }

  /** Reporte au jour ouvrable suivant — précision du comptable. */
  function jourOuvrableSuivant(d) {
    var x = new Date(d.getTime());
    while (x.getDay() === 0 || x.getDay() === 6) x = C.addDays(x, 1);
    return x;
  }

  /* Déroule le calendrier sur l'exercice : chaque obligation mensuelle donne
     douze échéances, chaque obligation annuelle en donne une. */
  /* Le calendrier est désormais amorcé par le MAGASIN : trois modules le
     lisent. Cette fonction reste comme filet — elle ne fait rien si la
     collection est déjà là, ce qui est le cas normal. */
  function amorcerEcheances() {
    var db = S.raw();
    if (db.echeancesFiscales && db.echeancesFiscales.length) return;
    var annee = AUJ.getFullYear();
    var out = [], n = 0;
    D.CALENDRIER_FISCAL.forEach(function (o) {
      var dates = [];
      if (o.periodicite === 'mensuelle') {
        for (var m = 0; m < 12; m++) dates.push(new Date(annee, m, o.jour));
      } else {
        dates.push(new Date(annee, o.mois, Math.min(o.jour, 28)));
      }
      dates.forEach(function (d) {
        n++;
        var echue = jourOuvrableSuivant(d);
        var passee = echue < AUJ;
        out.push({
          id: 'ECH' + C.pad(n, 4), statut: 'actif',
          code: o.code, libelle: o.libelle, famille: o.famille,
          periodicite: o.periodicite, part: o.part, declaration: o.declaration, note: o.note,
          exercice: annee,
          periode: o.periodicite === 'mensuelle' ? C.MOIS[Math.max(0, d.getMonth() - 1)] + ' ' + annee : String(annee),
          echeance: C.iso(echue),
          reportee: C.iso(echue) !== C.iso(d),
          /* Les échéances passées sont réputées honorées, sauf les deux plus
             récentes — pour que l'écran ait quelque chose à montrer. */
          paye: !S.jeuVide() && passee && C.daysBetween(echue, AUJ) > 25,   /* jamais de quittance inventée après un vidage */
          datePaiement: null, montant: null, reference: null, valideePar: null,
        });
      });
    });
    out.forEach(function (e) {
      if (e.paye) {
        e.datePaiement = e.echeance;
        e.valideePar = 'KASSA Augustin';
        e.reference = 'QUIT-' + e.code + '-' + e.exercice;
      }
    });
    db.echeancesFiscales = out;
    S.save();
  }

  /** État calculé d'une échéance — jamais stocké, toujours recalculé. */
  function calculerEtat(e) {
    if (e.paye) return 'payee';
    var j = C.daysBetween(AUJ, e.echeance);
    if (j < 0) return 'en_retard';
    if (j <= 10) return 'a_payer';
    if (e.declaration && j <= 30) return 'declaration';
    return 'a_venir';
  }

  global.SIGH.screen('m12-echeances', {
    title: 'Échéances fiscales & paiements',
    description: 'Suivi des obligations fiscales et sociales : ce qui est dû, ce qui approche, ce qui est réglé.',
    regle: 'Chaque obligation du calendrier est déroulée sur l’exercice. Une échéance <strong>dépassée et non '
      + 'réglée</strong> est signalée à l’ouverture de l’écran — une pénalité se constate rarement à temps. '
      + 'La validation d’un paiement porte son auteur, sa date et sa référence de quittance (RG-12).',
    actions: function () {
      return [
        K.btn('Obligations & règles', { icon: 'book-open-check', onclick: function () { global.SIGH.app.go('cfg-comptabilite'); } }),
      ];
    },
    render: function (root) {
      amorcerEcheances();
      dessiner();
      return null;

      function lignes() {
        return colEcheances().active().map(function (e) {
          return Object.assign({}, e, {
            etat: calculerEtat(e),
            jours: C.daysBetween(AUJ, e.echeance),
          });
        });
      }

      function dessiner() {
        C.clear(root);
        var rows = lignes();
        var retard = rows.filter(function (e) { return e.etat === 'en_retard'; });
        var aPayer = rows.filter(function (e) { return e.etat === 'a_payer'; });
        var declarations = rows.filter(function (e) { return e.etat === 'declaration'; });
        var payees = rows.filter(function (e) { return e.etat === 'payee'; });
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          {
            label: 'En retard', value: C.num(retard.length), icon: 'alarm-clock',
            tone: retard.length ? 'danger' : 'success',
            hint: retard.length ? 'Risque de pénalité' : 'Aucun retard',
          },
          {
            label: 'À payer sous 10 jours', value: C.num(aPayer.length), icon: 'coins',
            tone: aPayer.length ? 'warning' : 'success',
          },
          { label: 'Déclarations attendues', value: C.num(declarations.length), icon: 'file-pen-line', tone: 'info' },
          {
            label: 'Réglées sur l’exercice', value: C.num(payees.length), icon: 'check-circle-2', tone: 'success',
            hint: C.num(rows.length) + ' échéances au total',
          },
        ]));

        /* --- Barre de notification --------------------------------------
           Ce que la Direction demandait : être prévenu, pas devoir chercher. */
        var barre = el('div.space-y-2');
        if (retard.length) {
          barre.appendChild(alerte('danger', 'alarm-clock',
            retard.length + ' échéance(s) dépassée(s) et non réglée(s)',
            retard.slice(0, 3).map(function (e) {
              return e.code + ' — ' + C.dateFR(e.echeance) + ' (' + Math.abs(e.jours) + ' j de retard)';
            }).join(' · ') + (retard.length > 3 ? ' …' : ''),
            retard[0]));
        }
        if (aPayer.length) {
          barre.appendChild(alerte('warning', 'coins',
            aPayer.length + ' paiement(s) à effectuer sous dix jours',
            aPayer.slice(0, 3).map(function (e) {
              return e.code + ' le ' + C.dateFR(e.echeance);
            }).join(' · ') + (aPayer.length > 3 ? ' …' : ''),
            aPayer[0]));
        }
        if (declarations.length) {
          barre.appendChild(alerte('info', 'file-pen-line',
            declarations.length + ' déclaration(s) à préparer',
            'Une déclaration précède le paiement : ' + declarations.slice(0, 2).map(function (e) {
              return e.code + ' — ' + e.declaration;
            }).join(' · '), null));
        }
        if (!retard.length && !aPayer.length && !declarations.length) {
          barre.appendChild(alerte('success', 'check-circle-2',
            'Aucune échéance en attente immédiate',
            'La prochaine obligation tombe le ' + (rows.filter(function (e) { return e.jours >= 0 && !e.paye; })
              .sort(function (a, b) { return a.jours - b.jours; })[0] || {}).echeance, null));
        }
        host.appendChild(barre);

        host.appendChild(U.dataTable({
          title: 'Échéances de l’exercice ' + AUJ.getFullYear(),
          rows: rows, exportName: 'echeances-fiscales', pageSize: 20, searchable: true,
          defaultSort: 'echeance',
          filters: [
            {
              name: 'etat', label: 'État',
              options: ETATS_ECHEANCE.map(function (e) { return { value: e.id, label: e.label }; }),
            },
            {
              name: 'famille', label: 'Obligation',
              options: Object.keys(C.groupBy(rows, 'famille')).sort(),
            },
            {
              name: 'periodicite', label: 'Périodicité',
              options: [{ value: 'mensuelle', label: 'Mensuelle' }, { value: 'annuelle', label: 'Annuelle' }],
            },
          ],
          columns: [
            { key: 'code', label: 'Code', nowrap: true, render: function (e) { return el('span.font-mono.text-xs.font-semibold', { text: e.code }); } },
            {
              key: 'libelle', label: 'Obligation',
              render: function (e) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.text-slate-800', { text: e.libelle }),
                  el('p.truncate.text-xs.text-slate-400', {
                    text: e.periode + (e.part && e.part < 100 ? ' · tranche de ' + e.part + ' %' : ''),
                  }),
                ]);
              },
            },
            {
              key: 'echeance', label: 'Échéance', nowrap: true,
              text: function (e) { return C.dateFR(e.echeance); },
              render: function (e) {
                return el('div', null, [
                  el('p.text-sm.text-slate-700', { text: C.dateFR(e.echeance) }),
                  e.reportee ? el('p.text-\\[10px\\].text-warning-600', { text: 'reportée — jour ouvrable' }) : null,
                ]);
              },
              sortValue: function (e) { return C.toDate(e.echeance).getTime(); },
            },
            {
              key: 'jours', label: 'Délai', align: 'right',
              render: function (e) {
                if (e.paye) return el('span.text-xs.text-slate-400', { text: '—' });
                if (e.jours < 0) return el('span.num.font-semibold.text-danger-600', { text: Math.abs(e.jours) + ' j de retard' });
                return el('span.num', {
                  class: e.jours <= 10 ? 'font-semibold text-warning-700' : 'text-slate-600',
                  text: 'dans ' + e.jours + ' j',
                });
              },
            },
            {
              key: 'etat', label: 'État',
              text: function (e) { return etatEcheance(e.etat).label; },
              render: function (e) {
                var s = etatEcheance(e.etat);
                return U.badge(s.label, s.tone);
              },
            },
            {
              key: 'montant', label: 'Montant réglé', align: 'right',
              text: function (e) { return e.montant ? String(e.montant) : ''; },
              render: function (e) {
                return e.montant
                  ? el('span.font-semibold', { text: C.money(e.montant, false) })
                  : el('span.text-xs.text-slate-300', { text: '—' });
              },
            },
            {
              key: 'valideePar', label: 'Validé par',
              render: function (e) {
                return e.valideePar
                  ? el('div', null, [
                    el('p.text-xs.text-slate-600', { text: e.valideePar }),
                    el('p.text-\\[10px\\].text-slate-400', { text: e.reference || '' }),
                  ])
                  : el('span.text-xs.text-slate-300', { text: 'non réglée' });
              },
            },
          ],
          onRowClick: fiche,
          rowActions: function (e) {
            if (e.paye) {
              return [
                K.iconBtn('printer', 'Éditer la quittance', function () { imprimerQuittance(e); }),
                K.iconBtn('undo-2', 'Annuler la validation', function () { annulerPaiement(e); }),
              ];
            }
            return [
              K.iconBtn('check', 'Valider le paiement effectué', function () { validerPaiement(e); }),
              K.iconBtn('bell', 'Rappeler cette échéance', function () { rappeler(e); }),
            ];
          },
        }));

        root.appendChild(host);
        U.icons(root);

        /* Notification sonore à l'ouverture — le comptable ne consulte pas
           l'écran tous les jours ; c'est l'écran qui doit l'avertir. */
        if (retard.length || aPayer.length) {
          setTimeout(function () {
            U.alerter(
              (retard.length ? retard.length + ' échéance(s) en retard' : aPayer.length + ' paiement(s) sous dix jours'),
              {
                son: retard.length ? 'alerte' : 'rappel',
                type: retard.length ? 'error' : 'warning',
                detail: (retard[0] || aPayer[0]).libelle + ' — ' + C.dateFR((retard[0] || aPayer[0]).echeance),
                duration: 9000,
              }
            );
          }, 800);
        }
      }

      function alerte(tone, icone, titre, detail, cible) {
        var d = el('div.flex.items-start.gap-3.rounded-lg.border.px-3.py-2\\.5', {
          class: 'border-' + tone + '-200 bg-' + tone + '-50',
        });
        d.appendChild(el('span.mt-0\\.5.shrink-0', { class: 'text-' + tone + '-600' }, C.icon(icone, 'h-4 w-4')));
        d.appendChild(el('div.min-w-0.flex-1', null, [
          el('p.text-sm.font-semibold', { class: 'text-' + tone + '-900', text: titre }),
          el('p.mt-0\\.5.text-xs', { class: 'text-' + tone + '-800', text: detail }),
        ]));
        if (cible) {
          d.appendChild(K.btn('Valider le paiement', {
            size: 'sm', variant: tone === 'danger' ? 'danger' : 'primary', icon: 'check',
            onclick: function () { validerPaiement(cible); },
          }));
        }
        return d;
      }

      /* --- Validation d'un paiement effectué ---------------------------- */
      function validerPaiement(e) {
        var f = U.form([
          { name: 'datePaiement', label: 'Date du paiement', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'montant', label: 'Montant réglé (FCFA)', type: 'money', required: true, min: 1 },
          {
            name: 'moyen', label: 'Moyen de règlement', type: 'select', required: true,
            options: ['Virement bancaire', 'Chèque', 'Espèces', 'Mobile Money'],
          },
          { name: 'reference', label: 'Référence de quittance', required: true, help: 'Numéro du reçu délivré par l’administration.' },
          { name: 'valideePar', label: 'Validé par', required: true, value: S.currentUser() },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ], {});

        var m = U.modal({
          title: 'Valider le paiement — ' + e.code,
          subtitle: e.libelle + ' · échéance du ' + C.dateFR(e.echeance),
          size: 'lg',
          body: el('div.space-y-3', null, [
            U.descList([
              ['Obligation', e.libelle],
              ['Période', e.periode],
              ['Échéance', C.dateFR(e.echeance) + (e.reportee ? ' (reportée au jour ouvrable)' : '')],
              ['Part', e.part ? e.part + ' %' : '—'],
              ['Déclaration préalable', e.declaration || 'aucune'],
            ]),
            f,
            e.jours < 0
              ? K.note('<strong>Échéance dépassée de ' + Math.abs(e.jours) + ' jour(s).</strong> '
                + 'Une pénalité de retard peut s’appliquer : la consigner en observation.', { tone: 'danger', icon: 'alarm-clock' })
              : K.note('La validation est <strong>journalisée</strong> avec son auteur, sa date et sa référence '
                + 'de quittance (RG-12). Elle reste annulable.', { tone: 'info' }),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Confirmer le paiement', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var res = colEcheances().update(e.id, {
                  paye: true, datePaiement: v.datePaiement, montant: v.montant,
                  moyen: v.moyen, reference: v.reference, valideePar: v.valideePar,
                  observation: v.observation || null,
                });
                S.log('Paiement fiscal validé', 'M12', e.libelle, e.code,
                  { etat: 'non réglée' }, { montant: v.montant, reference: v.reference });
                m.close(); dessiner();
                U.toast(e.code + ' — paiement de ' + C.money(v.montant) + ' validé.', {
                  type: 'success', detail: 'Quittance ' + v.reference,
                  undo: function () { res.undo(); dessiner(); },
                });
              },
            }),
          ],
        });
      }

      function annulerPaiement(e) {
        U.confirm({
          title: 'Annuler la validation du paiement ' + e.code + ' ?',
          message: 'L’échéance redeviendra due. L’annulation est journalisée — elle ne fait pas disparaître '
            + 'la trace du paiement initialement enregistré.',
          confirmLabel: 'Annuler la validation', danger: true, requireMotif: true,
        }).then(function (ok) {
          if (!ok) return;
          var res = colEcheances().update(e.id, {
            paye: false, datePaiement: null, montant: null, reference: null, valideePar: null,
            motifAnnulation: ok.motif,
          });
          dessiner();
          U.toast('Validation annulée — l’échéance redevient due.', {
            type: 'warning', undo: function () { res.undo(); dessiner(); },
          });
        });
      }

      function rappeler(e) {
        U.alerter('Rappel — ' + e.libelle, {
          son: 'rappel', type: 'info',
          detail: 'Échéance du ' + C.dateFR(e.echeance)
            + (e.declaration ? ' · ' + e.declaration : '')
            + (e.jours >= 0 ? ' · dans ' + e.jours + ' jour(s)' : ' · dépassée de ' + Math.abs(e.jours) + ' jour(s)'),
          duration: 9000,
        });
      }

      function fiche(e) {
        U.drawer({
          title: e.code + ' — ' + e.libelle,
          subtitle: e.periode + ' · échéance du ' + C.dateFR(e.echeance),
          width: 'max-w-2xl',
          body: el('div.space-y-4', null, [
            U.descList([
              ['Obligation', e.libelle], ['Périodicité', e.periodicite],
              ['Période concernée', e.periode],
              ['Échéance', C.dateFR(e.echeance) + (e.reportee ? ' — reportée au jour ouvrable suivant' : '')],
              ['Part', e.part ? e.part + ' %' : '—'],
              ['Déclaration préalable', e.declaration || 'aucune'],
              ['État', etatEcheance(e.etat).label],
              ['Montant réglé', e.montant ? C.money(e.montant) : '—'],
              ['Quittance', e.reference || '—'],
              ['Validé par', e.valideePar || '—'],
            ]),
            K.note(e.note, { tone: 'info' }),
          ]),
          footer: e.paye
            ? [K.btn('Éditer la quittance', { variant: 'primary', icon: 'printer', onclick: function () { imprimerQuittance(e); } })]
            : [K.btn('Valider le paiement', { variant: 'primary', icon: 'check', onclick: function () { validerPaiement(e); } })],
        });
      }

      function imprimerQuittance(e) {
        P.etat({
          titre: 'Justificatif de paiement — obligation fiscale',
          sousTitre: e.code + ' · ' + e.libelle,
          cartouche: [['Obligation', e.libelle], ['Code', e.code],
            ['Période', e.periode], ['Échéance', C.dateFR(e.echeance)],
            ['Date de paiement', e.datePaiement ? C.dateFR(e.datePaiement) : '—'],
            ['Montant réglé', e.montant ? C.money(e.montant) : '—'],
            ['Moyen', e.moyen || '—'], ['Quittance', e.reference || '—']],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Obligation', v: e.libelle },
              { k: 'Base réglementaire', v: e.note },
              { k: 'Part acquittée', v: e.part ? e.part + ' %' : 'Intégralité' },
              { k: 'Déclaration préalable', v: e.declaration || 'Sans objet' },
              { k: 'Référence de quittance', v: e.reference || '—' },
              { k: 'Validé par', v: e.valideePar || '—' },
              { k: 'Observation', v: e.observation || '—' },
            ]),
          ]),
          signatures: [{ role: 'Le Comptable', nom: e.valideePar || 'KASSA Augustin' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * DÉPENSES JOURNALIÈRES — saisie au fil de l'eau et historique
   * --------------------------------------------------------------------------
   * Une dépense de trésorerie directe est un décaissement qui constate une
   * charge sans passer par un compte fournisseur : on paie, et c'est fini.
   * Elle produit UNE écriture à deux lignes, toujours la même :
   *
   *     DÉBIT   compte de charge (classe 6)   — la charge est constatée
   *     CRÉDIT  compte de trésorerie (5xx)    — l'argent est sorti
   *
   * TROIS RÈGLES :
   *   1. RG-10 — l'écriture est contrôlée ÉQUILIBRÉE avant d'être posée. Le
   *      cas est trivial aujourd'hui ; le contrôle est là pour le jour où une
   *      dépense portera plusieurs lignes de charge.
   *   2. Elle naît EN BROUILLON. La validation comptable reste un geste
   *      humain, et d'autant plus qu'ici la saisie est ouverte à la caisse.
   *   3. Une dépense SANS JUSTIFICATIF est une charge contestable. Le reçu
   *      n'est pas bloquant — on n'empêche pas d'enregistrer une dépense
   *      réelle parce que le vendeur n'a pas de carnet — mais elle est
   *      comptée et signalée. C'est la première chose qu'un contrôle demande.
   * ======================================================================== */
  function colDepenses() {
    return S.collection('depenses', { module: 'M12', entite: 'dépense', prefix: 'DEP' });
  }
  function colTresorerie() {
    return S.collection('banques', { module: 'M12', entite: 'compte de trésorerie', prefix: 'BQ' });
  }

  /** Les comptes de charge du plan réel de la clinique — classe 6 et 671. */
  function comptesCharge() {
    return (D.PLAN_COMPTABLE || []).filter(function (c) {
      return /^6/.test(String(c.num));
    });
  }
  function categorieDepense(id) {
    return (D.CATEGORIES_DEPENSE || []).filter(function (c) { return c.id === id; })[0] || null;
  }
  function libelleCategorieDepense(id) {
    var c = categorieDepense(id);
    return c ? c.label : (id || '—');
  }
  function compteTresorerie(id) {
    return colTresorerie().active().filter(function (b) { return b.id === id; })[0] || null;
  }

  global.SIGH.screen('m12-depenses', {
    title: 'Dépenses journalières',
    description: 'Saisie au fil de l’eau des charges de trésorerie directes, avec justificatif, écriture automatique et historique.',
    regle: 'Une dépense de trésorerie constate une charge et sort de l’argent : elle produit une écriture '
      + '<strong>débit charge / crédit trésorerie</strong>, contrôlée <strong>équilibrée</strong> avant '
      + 'd’être posée (RG-10) et créée <strong>en brouillon</strong> — la validation comptable reste un '
      + 'geste humain. Le <strong>justificatif n’est pas bloquant mais il est compté</strong> : une charge '
      + 'sans reçu est une charge contestable.',
    actions: function () {
      return [
        K.btn('Écritures comptables', { icon: 'pencil-line',
          onclick: function () { global.SIGH.app.go('m12-ecritures'); } }),
      ];
    },
    render: function (root) {
      var vue = el('div.space-y-4');
      /* La plage de dates survit au redessin : la remettre à zéro à chaque
         saisie ferait perdre le filtre au moment où l'on s'en sert le plus. */
      var dDu = el('input.input', { type: 'date' });
      var dAu = el('input.input', { type: 'date' });
      dDu.addEventListener('change', function () { afficher(); });
      dAu.addEventListener('change', function () { afficher(); });

      root.appendChild(vue);
      amorcer();
      afficher();
      return null;

      function dansPlage(r) {
        var d = String(r.date || '').slice(0, 10);
        if (dDu.value && d < dDu.value) return false;
        if (dAu.value && d > dAu.value) return false;
        return true;
      }

      /* ------------------------------------------------------------------ */
      function amorcer() {
        var col = colDepenses();
        if (col.all().length || !S.amorcable('depenses')) return;
        /* Un historique de neuf mois : sans lui, les indicateurs et les
           graphiques seraient à zéro et on croirait l'écran cassé. Les
           libellés sont ceux d'une clinique, pas des chaînes de test. */
        var rnd = C.seeded(4417);
        var MODELES = [
          ['medical', '601100', 'Achat de gants d’examen — boîte de 100', 12000, 45000],
          ['medical', '604100', 'Compresses stériles et sparadrap', 8000, 32000],
          ['medical', '605600', 'Petit matériel de soins', 15000, 60000],
          ['fonctionnement', '605200', 'Facture d’électricité SBEE', 180000, 420000],
          ['fonctionnement', '605100', 'Facture d’eau SONEB', 25000, 75000],
          ['fonctionnement', '604700', 'Fournitures de bureau', 12000, 55000],
          ['fonctionnement', '604300', 'Produits d’entretien et désinfectants', 15000, 48000],
          ['logistique', '604200', 'Carburant — groupe électrogène', 30000, 90000],
          ['logistique', '616000', 'Transport de plis et courses', 3000, 12000],
          ['logistique', '618100', 'Déplacement à Cotonou — retrait de réactifs', 25000, 65000],
          ['entretien', '624100', 'Réparation de la plomberie du bloc', 20000, 85000],
          ['entretien', '624300', 'Maintenance du groupe électrogène', 35000, 120000],
          ['personnel', '637100', 'Vacation de personnel externe', 40000, 150000],
          ['personnel', '638400', 'Frais de mission — formation', 20000, 80000],
          ['fiscal', '631810', 'Frais bancaires BOA', 8000, 25000],
          ['fiscal', '646210', 'Droits de timbre', 2000, 8000],
          ['divers', '638300', 'Réception — visite de la zone sanitaire', 15000, 50000],
        ];
        var tresor = colTresorerie().active();
        var agents = S.collection('personnel').active()
          .filter(function (a) { return /comptab|caiss|direct/i.test(a.poste || ''); });

        S.enLot(function () {
          for (var k = 0; k < 190; k++) {
            var m = C.pick(rnd, MODELES);
            var jour = C.addDays(AUJ, -C.between(rnd, 0, 270));
            /* UNE PIÈCE SUR CINQ PORTE PLUSIEURS LIGNES (arbitrage du
               31/08/2026) : c'est la forme qu'exerce l'écran, et le total est
               LA SOMME des lignes — jamais un nombre tiré à part. */
            var lignes = [{ libelle: m[2], compteCharge: m[1], montant: C.between(rnd, m[3], m[4]) }];
            if (rnd() > 0.8) {
              var m2 = C.pick(rnd, MODELES);
              lignes.push({ libelle: m2[2], compteCharge: m2[1], montant: C.between(rnd, m2[3], m2[4]) });
              if (rnd() > 0.6) {
                var m3 = C.pick(rnd, MODELES);
                lignes.push({ libelle: m3[2], compteCharge: m3[1], montant: C.between(rnd, m3[3], m3[4]) });
              }
            }
            var montant = C.sum(lignes, 'montant');
            var compte = montant > 100000
              ? (tresor.filter(function (b) { return b.nature === 'banque'; })[0] || tresor[0])
              : (tresor.filter(function (b) { return b.nature === 'caisse'; })[0] || tresor[0]);
            var qui = agents.length ? C.pick(rnd, agents) : null;
            col.all().push({
              id: 'DEP' + C.pad(k + 1, 4), statut: 'actif',
              reference: 'DEP-' + String(C.toDate(jour).getFullYear()) + '-' + C.pad(k + 1, 4),
              date: C.iso(jour),
              lignes: lignes,
              montant: montant,
              libelle: lignes[0].libelle + (lignes.length > 1 ? ' (+' + (lignes.length - 1) + ' autre(s))' : ''),
              compteCharge: lignes[0].compteCharge,
              compteTresorerie: compte ? compte.id : null,
              categorie: m[0],
              /* Une dépense sur six n'a pas de reçu. C'est la réalité du
                 terrain, et c'est précisément ce que l'écran doit compter. */
              justificatif: rnd() > 0.17 ? {
                nom: 'recu-' + C.pad(k + 1, 4) + '.jpg', type: 'image/jpeg',
                taille: C.between(rnd, 60000, 240000),
              } : null,
              saisiPar: qui ? qui.nomComplet : 'Caisse',
              saisiLe: C.iso(jour),
              ecritureId: null,
            });
          }
        });
        S.save();
      }

      /* ------------------------------------------------------------------
       * L'ÉCRITURE. Débit charge, crédit trésorerie, contrôlée équilibrée.
       * ---------------------------------------------------------------- */
      /* Les lignes d'une dépense — héritage compris : une pièce d'avant
         l'arbitrage (libellé + compte + montant en tête) se lit comme UNE
         ligne, sans migration. */
      function lignesDe(dep) {
        if (dep.lignes && dep.lignes.length) return dep.lignes;
        return [{ libelle: dep.libelle, compteCharge: dep.compteCharge, montant: Number(dep.montant) || 0 }];
      }

      function poserEcriture(dep) {
        var tres = compteTresorerie(dep.compteTresorerie);
        var col = S.collection('ecritures', { module: 'M12', entite: 'écriture' });

        /* UNE ÉCRITURE PLATE PAR LIGNE, comme le moteur d'encaissement et le
           jeu de démonstration : même numéro de pièce, même date, un compte et
           un sens chacune. C'est cette forme que lisent le grand livre, la
           balance et le compte de résultat — en inventer une seconde rendrait
           la dépense invisible de tous les trois. */
        var base = {
          numero: dep.reference,
          date: dep.date,
          journal: tres && tres.nature === 'caisse' ? 'CAI' : 'BQE',
          journalLibelle: tres && tres.nature === 'caisse'
            ? 'Journal de caisse-dépenses' : 'Journal de banque',
          libelle: dep.libelle,
          pieceId: dep.id, pieceNumero: dep.reference,
          origine: 'Dépense journalière',
          /* EN BROUILLON : la validation comptable reste un geste humain, et
             d'autant plus qu'ici la saisie est ouverte à la caisse. */
          statut: 'brouillon',
        };
        /* ARBITRAGE DU 31/08/2026 : une facture porte UN OU PLUSIEURS libellés
           de dépense — un DÉBIT par ligne de charge, un crédit de trésorerie
           du TOTAL. C'est exactement le cas que le contrôle RG-10 attendait. */
        var lignes = lignesDe(dep).map(function (l) {
          return Object.assign({}, base, {
            compte: l.compteCharge, compteLibelle: compteLibelle(l.compteCharge),
            libelle: l.libelle,
            debit: Number(l.montant) || 0, credit: 0,
          });
        }).concat([
          Object.assign({}, base, {
            compte: tres ? tres.compteComptable : '571000',
            compteLibelle: tres ? tres.intitule : 'Caisse',
            libelle: 'Décaissement — ' + (tres ? tres.intitule : 'trésorerie'),
            debit: 0, credit: Number(dep.montant) || 0,
          }),
        ]);

        /* RG-10, contrôlé AVANT d'écrire : un déséquilibre ne doit pas entrer
           au journal, fût-il en brouillon. */
        var debit = C.sum(lignes, 'debit'), credit = C.sum(lignes, 'credit');
        if (debit !== credit) {
          U.toast('Écriture refusée.', { type: 'error',
            detail: 'RG-10 — débit ' + C.money(debit) + ' contre crédit ' + C.money(credit) + '.' });
          S.log('Écriture de dépense refusée — déséquilibre', 'M12', 'Ecriture', dep.reference,
            null, { debit: debit, credit: credit });
          return null;
        }

        var posees = lignes.map(function (l) { return col.insert(l).record; });
        S.log('Écriture de dépense', 'M12', 'Ecriture', dep.reference, null,
          { debit: debit, credit: credit, lignes: posees.length });
        /* On retient les DEUX identifiants : archiver la dépense doit archiver
           l'écriture entière, pas la moitié — une demi-écriture au journal
           serait pire qu'aucune. */
        return { id: posees[0].id, ids: posees.map(function (x) { return x.id; }) };
      }

      /* ------------------------------------------------------------------ */
      function champs() {
        var tresor = colTresorerie().active().map(function (b) {
          return { value: b.id, label: b.intitule,
            detail: (b.compteComptable || '') + (b.numeroCompte ? ' · ' + b.numeroCompte : '') };
        });
        return [
          { name: 'date', label: 'Date de la transaction', type: 'date', required: true },
          { name: 'compteTresorerie', label: 'Compte de trésorerie', type: 'select', required: true,
            options: tresor, help: 'D’où l’argent est sorti.' },
          { name: 'categorie', label: 'Catégorie de dépenses', type: 'select', required: true,
            options: (D.CATEGORIES_DEPENSE || []).map(function (c) {
              return { value: c.id, label: c.label };
            }),
            help: 'La lecture de gestion, distincte du compte : c’est elle que lit la Direction, '
              + 'qui ne raisonne pas en numéros de compte.' },
          { name: 'libelle', label: 'Objet de la pièce (facultatif)', col: 'full',
            placeholder: 'Repris de la première ligne si vide',
            help: 'La pièce porte SES LIGNES ci-dessous : le montant total est leur somme, jamais saisi à part.' },
        ];
      }

      /* --------------------------------------------------------------------
       * L'ÉDITEUR DE LIGNES — l'arbitrage du 31/08/2026
       * --------------------------------------------------------------------
       * « Une facture peut présenter un ou plusieurs libellés de dépenses » :
       * chaque ligne porte son libellé, son compte de charge et son montant,
       * avec ajout, édition et suppression DANS la modale. Le total de la
       * pièce est LA SOMME des lignes — le fournir à part, c'est le bug des
       * totaux, déjà payé deux fois sur ce prototype.
       * ------------------------------------------------------------------ */
      function editeurLignes(initiales) {
        var lignes = (initiales || []).map(function (l) { return Object.assign({}, l); });
        var bloc = el('div.rounded-lg.border.border-slate-200.p-3');
        bloc.appendChild(el('p.label', { text: 'Lignes de la dépense *' }));
        var zone = el('div');
        bloc.appendChild(zone);

        function formLigne(valeurs, surValide) {
          var fL = U.form([
            { name: 'libelle', label: 'Libellé de la ligne', required: true, col: 'full' },
            { name: 'compteCharge', label: 'Compte de charge (SYSCOHADA)', type: 'select', required: true,
              options: comptesCharge().map(function (c2) { return { value: c2.num, label: c2.num + ' — ' + c2.libelle }; }) },
            { name: 'montant', label: 'Montant (FCFA)', type: 'number', min: 1, required: true },
          ], valeurs || {});
          var mL = U.modal({
            title: valeurs ? 'Modifier la ligne' : 'Ajouter une ligne', size: 'lg', body: fL,
            footer: [
              K.btn('Annuler', { onclick: function () { mL.close(); } }),
              K.btn(valeurs ? 'Enregistrer' : 'Ajouter', { variant: 'primary', icon: 'check',
                onclick: function () {
                  var vL = fL.collect(); if (!vL) return;
                  vL.montant = Number(vL.montant);
                  surValide(vL); mL.close(); dessiner();
                } }),
            ],
          });
        }

        function dessiner() {
          C.clear(zone);
          if (!lignes.length) {
            zone.appendChild(el('p.py-2.text-xs.text-slate-400', { text: 'Aucune ligne — la pièce en exige au moins une.' }));
          } else {
            var t = el('table.tbl');
            var tb = el('tbody');
            lignes.forEach(function (l, i) {
              var tr = el('tr');
              tr.appendChild(el('td.text-sm', { text: l.libelle }));
              tr.appendChild(el('td.font-mono.text-xs.text-slate-500', { text: l.compteCharge }));
              tr.appendChild(el('td.num.text-right.text-sm', { text: C.money(l.montant, false) }));
              var actions = el('td.text-right');
              actions.appendChild(K.iconBtn('pencil', 'Modifier la ligne', function () {
                formLigne(l, function (vL) { lignes[i] = vL; });
              }));
              actions.appendChild(K.iconBtn('trash-2', 'Retirer la ligne', function () {
                lignes.splice(i, 1); dessiner();
              }, 'ghost'));
              tr.appendChild(actions);
              tb.appendChild(tr);
            });
            var pied = el('tr.border-t.border-slate-300');
            pied.appendChild(el('td.text-sm.font-semibold', { text: 'TOTAL — ' + lignes.length + ' ligne(s)' }));
            pied.appendChild(el('td'));
            pied.appendChild(el('td.num.text-right.text-sm.font-semibold',
              { text: C.money(C.sum(lignes, 'montant'), false) }));
            pied.appendChild(el('td'));
            tb.appendChild(pied);
            t.appendChild(tb);
            zone.appendChild(el('div.overflow-x-auto', null, t));
          }
          zone.appendChild(el('div.mt-2', null,
            K.btn('Ajouter une ligne', { size: 'sm', icon: 'plus',
              onclick: function () { formLigne(null, function (vL) { lignes.push(vL); }); } })));
          U.icons(zone);
        }
        dessiner();

        return {
          bloc: bloc,
          lire: function () { return lignes.slice(); },
          total: function () { return C.sum(lignes, 'montant'); },
        };
      }

      /* Le dépôt du reçu : U.form ne connaît pas de type « file ». Le champ se
         monte à côté, et le FileReader produit une donnée en base 64 conservée
         DANS LE POSTE — aucune requête réseau, comme le reste du logiciel. */
      function champFichier() {
        var input = el('input.input', {
          type: 'file', accept: '.pdf,.png,.jpg,.jpeg,image/png,image/jpeg,application/pdf',
          'aria-label': 'Reçu ou facture',
        });
        var apercu = el('div.mt-2');
        var meta = { valeur: null };
        input.addEventListener('change', function () {
          var file = input.files && input.files[0];
          C.clear(apercu);
          meta.valeur = null;
          if (!file) return;
          if (file.size > 2 * 1024 * 1024) {
            apercu.appendChild(K.note('Fichier de ' + Math.round(file.size / 1024) + ' Ko — au-delà de '
              + 'deux mégaoctets le stockage local sature vite. Photographier en résolution plus basse.',
            { tone: 'warning', icon: 'triangle-alert' }));
          }
          var lecteur = new FileReader();
          lecteur.onload = function () {
            meta.valeur = { nom: file.name, type: file.type, taille: file.size, donnees: lecteur.result };
            if (/pdf$/i.test(file.name)) {
              apercu.appendChild(el('p.mt-2.text-xs.text-slate-500',
                { text: file.name + ' — PDF prêt à être rattaché' }));
            } else {
              apercu.appendChild(el('img.mt-2.max-h-40.rounded-lg.border.border-slate-200.object-contain',
                { src: lecteur.result, alt: 'Aperçu du reçu' }));
            }
          };
          lecteur.readAsDataURL(file);
        });
        return {
          bloc: el('div', null, [
            el('label.label', { text: 'Reçu / facture (photo)' }), input, apercu,
            el('p.mt-1.text-xs.text-slate-500', {
              text: 'Facultatif, mais une dépense sans justificatif est signalée : c’est la première '
                + 'pièce qu’un contrôle réclame.' }),
          ]),
          lire: function () { return meta.valeur; },
        };
      }

      /* ------------------------------------------------------------------ */
      function totauxDepuisLignes(v, editeur) {
        var lignes = editeur.lire();
        if (!lignes.length) {
          U.toast('La pièce exige au moins une ligne de dépense.', { type: 'error' });
          return null;
        }
        return {
          lignes: lignes,
          /* LE TOTAL EST LEUR SOMME — jamais un nombre choisi à part. */
          montant: C.sum(lignes, 'montant'),
          libelle: (v.libelle || '').trim()
            || (lignes[0].libelle + (lignes.length > 1 ? ' (+' + (lignes.length - 1) + ' autre(s))' : '')),
          compteCharge: lignes[0].compteCharge,
        };
      }

      /* Écart E714 : la garde de l'exercice clos refuse l'écriture (insert rend null) — la maquette levait alors une TypeError dans
         poserEcriture APRÈS avoir écrit la dépense. Le refus est dit AVANT toute écriture, avec le motif du moteur. */
      function exerciceDeLaDateClos(date) {
        var a = global.SIGH.exercice.anneeDe(date);
        if (!a || global.SIGH.exercice.etat(a) !== 'clos') return false;
        var x = global.SIGH.exercice.de(a);
        U.toast('Écriture refusée.', { type: 'error', detail: 'Exercice ' + a + ' clos' + (x && x.valideLe ? ' le ' + C.dateFR(x.valideLe) : '')
          + ' — lecture seule. La correction passe par une écriture de l’exercice en cours.' });
        return true;
      }

      function nouvelle() {
        if (!K.droits('M12').editer) return;
        var f = U.form(champs(), { date: C.iso(AUJ), categorie: 'fonctionnement' });
        var editeur = editeurLignes([]);
        var fichier = champFichier();
        var m = U.modal({
          title: 'Nouvelle dépense',
          subtitle: 'Une pièce, une ou plusieurs lignes de charge — le total est leur somme.',
          size: 'lg', body: el('div.space-y-3', null, [f, editeur.bloc, fichier.bloc]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var t = totauxDepuisLignes(v, editeur);
                if (!t) return;
                if (exerciceDeLaDateClos(v.date)) return;
                var sess = S.session() || {};
                var rec = colDepenses().insert({
                  /* Écart E712 : C.nextRef est un compteur de PAGE (repart à 1 à chaque chargement) — la première dépense de la
                     session redonnait DEP-2026-0001, déjà attribuée. Le rang se lit sur les dépenses existantes (E8). */
                  reference: C.referenceSuivante('DEP-' + String(C.toDate(v.date).getFullYear()) + '-', 4, colDepenses().all()),
                  date: v.date,
                  lignes: t.lignes, montant: t.montant,
                  libelle: t.libelle, compteCharge: t.compteCharge,
                  compteTresorerie: v.compteTresorerie, categorie: v.categorie,
                  justificatif: fichier.lire(),
                  saisiPar: sess.nomComplet || sess.nom || 'Utilisateur',
                  saisiLe: C.iso(AUJ),
                }).record;
                var ec = poserEcriture(rec);
                if (ec) colDepenses().update(rec.id, { ecritureId: ec.id, ecritureIds: ec.ids });
                m.close(); afficher();
                U.toast('Dépense enregistrée.', { type: 'success',
                  detail: C.money(rec.montant) + ' en ' + t.lignes.length + ' ligne(s) — écriture '
                    + (ec ? 'en brouillon, à valider' : 'non posée')
                    + (rec.justificatif ? '' : ' · sans justificatif'),
                  undo: function () { colDepenses().archive(rec.id); afficher(); },
                  undoMessage: 'Dépense annulée.' });
              } }),
          ],
        });
      }

      function modifier(r) {
        var f = U.form(champs(), r);
        var editeur = editeurLignes(lignesDe(r));
        var fichier = champFichier();
        var m = U.modal({
          title: 'Modifier la dépense — ' + r.reference,
          subtitle: 'L’écriture liée sera refaite. Elle repart en brouillon.',
          size: 'lg',
          body: el('div.space-y-3', null, [
            f,
            editeur.bloc,
            /* Le reçu déjà joint reste, sauf si on en dépose un autre :
               rouvrir la fiche ne doit pas faire perdre la pièce. */
            r.justificatif ? K.note('Reçu déjà joint : <strong>' + r.justificatif.nom + '</strong>. '
              + 'Déposer un autre fichier le remplacera.', { tone: 'info', icon: 'paperclip' }) : null,
            fichier.bloc,
          ].filter(Boolean)),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var t = totauxDepuisLignes(v, editeur);
                if (!t) return;
                if (exerciceDeLaDateClos(v.date)) return;
                colDepenses().update(r.id, {
                  date: v.date,
                  lignes: t.lignes, montant: t.montant, libelle: t.libelle,
                  compteCharge: t.compteCharge, compteTresorerie: v.compteTresorerie,
                  categorie: v.categorie, justificatif: fichier.lire() || r.justificatif || null,
                });
                /* L'écriture suit la dépense : la laisser telle quelle
                   ferait diverger la comptabilité de la pièce qui la fonde. */
                /* TOUTES les lignes de l'ancienne écriture, pas la première :
                   en laisser une seule mettrait le journal en déséquilibre. */
                (r.ecritureIds || [r.ecritureId]).filter(Boolean).forEach(function (id) {
                  S.collection('ecritures').archive(id);
                });
                var ec = poserEcriture(colDepenses().get(r.id));
                if (ec) colDepenses().update(r.id, { ecritureId: ec.id, ecritureIds: ec.ids });
                m.close(); afficher();
                U.toast('Dépense modifiée.', { type: 'success',
                  detail: 'L’écriture a été refaite et repart en brouillon.' });
              } }),
          ],
        });
      }

      function supprimer(r) {
        U.confirm({
          title: 'Archiver la dépense ' + r.reference + ' ?',
          message: 'La dépense et son écriture sont archivées, jamais supprimées (RG-14). '
            + 'Elles restent consultables depuis la corbeille.',
          danger: true, confirmLabel: 'Archiver',
        }).then(function (ok) {
          if (!ok) return;
          var ids = (r.ecritureIds || [r.ecritureId]).filter(Boolean);
          colDepenses().archive(r.id);
          ids.forEach(function (id) { S.collection('ecritures').archive(id); });
          afficher();
          U.toast('Dépense archivée.', { type: 'success',
            undo: function () {
              colDepenses().restore(r.id);
              ids.forEach(function (id) { S.collection('ecritures').restore(id); });
              afficher();
            },
            undoMessage: 'Archivage annulé.' });
        });
      }

      function consulter(r) {
        var tres = compteTresorerie(r.compteTresorerie);
        U.drawer({
          title: r.libelle,
          subtitle: r.reference + ' — ' + C.dateFR(r.date),
          body: el('div.space-y-4', null, [
            U.descList([
              ['Référence', r.reference],
              ['Date de la transaction', C.dateFR(r.date)],
              ['Montant décaissé', C.money(r.montant) + ' — ' + lignesDe(r).length + ' ligne(s)'],
              ['Compte de trésorerie', tres ? tres.intitule + ' (' + tres.compteComptable + ')' : '—'],
              ['Catégorie de gestion', libelleCategorieDepense(r.categorie)],
              ['Justificatif', r.justificatif ? r.justificatif.nom : 'AUCUN — charge contestable'],
              ['Saisie par', (r.saisiPar || '—') + ' le ' + C.dateFR(r.saisiLe || r.date)],
              ['Écriture', r.ecritureId ? r.ecritureId + ' — en brouillon jusqu’à validation' : 'non posée'],
            ]),
            K.section('Lignes de la pièce',
              K.miniTable(['Libellé', 'Compte de charge', 'Montant'],
                lignesDe(r).map(function (l) {
                  return [l.libelle, l.compteCharge + ' — ' + compteLibelle(l.compteCharge), C.money(l.montant, false)];
                }))),
            K.note('Un <strong>débit par ligne de charge</strong>, un crédit de trésorerie du total ('
              + (tres ? tres.compteComptable : '571000') + '). Écriture équilibrée (RG-10), en brouillon : '
              + 'la validation comptable reste un geste humain.', { tone: 'info', icon: 'scale' }),
          ]),
          footer: [
            K.btn('Imprimer la pièce', { icon: 'printer', onclick: function () { imprimerPiece(r); } }),
          ],
        });
      }

      function imprimerPiece(r) {
        var tres = compteTresorerie(r.compteTresorerie);
        P.etat({
          titre: 'Pièce de dépense',
          sousTitre: r.reference + ' — ' + C.dateFR(r.date),
          cartouche: [
            ['Référence', r.reference], ['Date', C.dateFR(r.date)],
            ['Montant', C.money(r.montant) + ' (' + lignesDe(r).length + ' ligne(s))'],
            ['Trésorerie', tres ? tres.intitule : '—'],
            ['Catégorie', libelleCategorieDepense(r.categorie)],
            ['Justificatif', r.justificatif ? r.justificatif.nom : 'AUCUN'],
            ['Saisie par', r.saisiPar || '—'],
          ],
          contenu: el('div.space-y-3', null, [
            el('p.font-semibold', { text: 'Objet de la dépense' }),
            el('p', { text: r.libelle }),
            el('p.mt-3.font-semibold', { text: 'Écriture comptable' }),
            P.tableau([
              { label: 'Compte', value: function (x) { return x.compte; } },
              { label: 'Libellé', value: function (x) { return x.libelle; } },
              { label: 'Débit', align: 'right',
                value: function (x) { return x.debit ? C.money(x.debit, false) : ''; },
                somme: function (x) { return x.debit; } },
              { label: 'Crédit', align: 'right',
                value: function (x) { return x.credit ? C.money(x.credit, false) : ''; },
                somme: function (x) { return x.credit; } },
            ], lignesDe(r).map(function (l) {
              return { compte: l.compteCharge, libelle: l.libelle, debit: l.montant, credit: 0 };
            }).concat([
              { compte: tres ? tres.compteComptable : '571000',
                libelle: 'Décaissement — ' + (tres ? tres.intitule : 'trésorerie'),
                debit: 0, credit: r.montant },
            ]), { total: true }),
            r.justificatif ? null : el('p.mt-3.text-\\[10px\\].italic', {
              text: 'Aucun justificatif joint : cette charge est contestable en cas de contrôle.' }),
          ].filter(Boolean)),
          signatures: [{ role: 'Le bénéficiaire' }, { role: 'Le Comptable' },
            { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }],
        });
      }

      /* ------------------------------------------------------------------ */
      function afficher() {
        C.clear(vue);
        var rows = colDepenses().active().filter(dansPlage);
        var droits = K.droits('M12');

        var jour = C.iso(AUJ);
        var duJour = rows.filter(function (r) { return r.date === jour; });
        var duMois = rows.filter(function (r) { return String(r.date).slice(0, 7) === jour.slice(0, 7); });
        var sansRecu = rows.filter(function (r) { return !r.justificatif; });

        /* QUATRE indicateurs, pas cinq — arbitrage du 31/08/2026. La « dépense
           moyenne » est retirée : c'est le seul des cinq qui ne commande
           aucune action, et un bandeau se lit d'un regard. */
        vue.appendChild(U.kpiGrid([
          { label: 'Dépensé aujourd’hui', value: C.money(C.sum(duJour, 'montant')),
            icon: 'calendar', tone: 'navy', hint: C.num(duJour.length) + ' pièce(s)' },
          { label: 'Dépensé ce mois', value: C.money(C.sum(duMois, 'montant')),
            icon: 'calendar-range', tone: 'info', hint: C.num(duMois.length) + ' pièce(s)' },
          { label: 'Total enregistré', value: C.money(C.sum(rows, 'montant')),
            icon: 'wallet', tone: 'warning', hint: C.num(rows.length) + ' dépense(s)' },
          { label: 'Sans justificatif', value: C.num(sansRecu.length),
            icon: 'file-x', tone: sansRecu.length ? 'danger' : 'success',
            hint: sansRecu.length ? C.money(C.sum(sansRecu, 'montant')) + ' contestables' : 'toutes justifiées' },
        ]));

        if (sansRecu.length) {
          vue.appendChild(K.note('<strong>' + sansRecu.length + ' dépense(s) sans justificatif</strong>, '
            + 'pour ' + C.money(C.sum(sansRecu, 'montant')) + '. Le reçu n’est pas bloquant à la saisie — '
            + 'on n’empêche pas d’enregistrer une dépense réelle parce que le vendeur n’a pas de carnet — '
            + 'mais ces charges sont <strong>contestables en cas de contrôle</strong>. Le filtre '
            + '« Justificatif » les isole.', { tone: 'warning', icon: 'file-x' }));
        }

        /* Le filtre de date est un FILTRE, pas un tri : « du 1er au 15 août »
           ne se répond pas par un classement décroissant. */
        var barre = el('div.card');
        barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
          el('div', null, [el('label.label', { text: 'Du' }), dDu]),
          el('div', null, [el('label.label', { text: 'Au' }), dAu]),
          K.btn('Aujourd’hui', { size: 'sm', icon: 'calendar', onclick: function () {
            dDu.value = C.iso(AUJ); dAu.value = C.iso(AUJ); afficher();
          } }),
          K.btn('Ce mois', { size: 'sm', icon: 'calendar-range', onclick: function () {
            dDu.value = C.iso(AUJ).slice(0, 8) + '01'; dAu.value = C.iso(AUJ); afficher();
          } }),
          K.btn('Tout l’historique', { size: 'sm', icon: 'history', onclick: function () {
            dDu.value = ''; dAu.value = ''; afficher();
          } }),
        ]));
        vue.insertBefore(barre, vue.firstChild);

        vue.appendChild(U.dataTable({
          rows: rows, exportName: 'depenses-journalieres', pageSize: 15, searchable: true,
          defaultSort: 'date', defaultDir: 'desc',
          filters: [
            { name: 'categorie', label: 'Catégorie de dépenses',
              options: (D.CATEGORIES_DEPENSE || []).map(function (c) {
                return { value: c.id, label: c.label };
              }) },
            { name: 'compteCharge', label: 'Compte de charge',
              options: Object.keys(C.groupBy(rows, 'compteCharge')).sort().map(function (num) {
                return { value: num, label: num + ' — ' + compteLibelle(num) };
              }) },
            { name: 'compteTresorerie', label: 'Trésorerie',
              options: colTresorerie().active().map(function (b) {
                return { value: b.id, label: b.intitule };
              }) },
            { name: 'justificatif', label: 'Justificatif',
              options: [{ value: 'oui', label: 'Avec reçu' }, { value: 'non', label: 'Sans reçu' }],
              match: function (r, v) { return v === 'oui' ? !!r.justificatif : !r.justificatif; } },
          ],
          columns: [
            { key: 'date', label: 'Date', nowrap: true,
              text: function (r) { return C.dateFR(r.date); },
              render: function (r) { return C.dateFR(r.date); } },
            { key: 'reference', label: 'N°', nowrap: true,
              render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
            { key: 'libelle', label: 'Libellé de la dépense' },
            { key: 'categorie', label: 'Catégorie', text: function (r) { return libelleCategorieDepense(r.categorie); },
              render: function (r) { return U.badge(libelleCategorieDepense(r.categorie), 'navy'); } },
            { key: 'compteCharge', label: 'Compte SYSCOHADA',
              render: function (r) {
                return el('div', null, [
                  el('span.font-mono.text-xs', { text: r.compteCharge }),
                  el('p.text-[10px].text-slate-400', { text: compteLibelle(r.compteCharge) }),
                ]);
              } },
            { key: 'compteTresorerie', label: 'Sortie de',
              text: function (r) { var b = compteTresorerie(r.compteTresorerie); return b ? b.intitule : '—'; },
              render: function (r) {
                var b = compteTresorerie(r.compteTresorerie);
                return b ? U.badge(b.banque, b.nature === 'caisse' ? 'warning' : 'info')
                  : el('span.text-slate-300', { text: '—' });
              } },
            { key: 'justificatif', label: 'Reçu', align: 'center',
              text: function (r) { return r.justificatif ? 'oui' : 'non'; },
              render: function (r) {
                return r.justificatif ? U.badge('Joint', 'success') : U.badge('Absent', 'danger');
              } },
            { key: 'montant', label: 'Montant', align: 'right',
              text: function (r) { return C.money(r.montant, false); },
              render: function (r) {
                return el('span.font-bold.text-navy-800', { text: C.money(r.montant, false) });
              } },
          ],
          onRowClick: consulter,
          rowActions: function (r) {
            var actes = [K.iconBtn('eye', 'Consulter', function () { consulter(r); })];
            /* Les commandes suivent les DROITS du profil : proposer une
               modification qu'on refusera ensuite promet une porte fermée. */
            if (droits.editer) {
              actes.push(K.iconBtn('pencil-line', 'Modifier', function () { modifier(r); }));
            }
            if (droits.annuler) {
              actes.push(K.iconBtn('archive', 'Archiver', function () { supprimer(r); }));
            }
            actes.push(K.iconBtn('printer', 'Imprimer la pièce', function () { imprimerPiece(r); }));
            return actes;
          },
          actions: [
            droits.editer ? K.btn('Nouvelle dépense', { variant: 'primary', icon: 'plus',
              onclick: nouvelle }) : null,
            K.btn('État des dépenses', { icon: 'printer', onclick: function () { imprimerEtat(rows); } }),
          ].filter(Boolean),
        }));

        if (!droits.editer) {
          vue.appendChild(K.note('Votre profil consulte les dépenses sans les saisir. '
            + 'La matrice des droits (M14) décide de cette ouverture.', { tone: 'neutral', icon: 'lock' }));
        }

        /* --- Les lectures graphiques, APRÈS les données ------------------ */
        var parMois = {}, ordre = [];
        rows.forEach(function (r) {
          var k = String(r.date).slice(0, 7);
          if (!parMois[k]) { parMois[k] = 0; ordre.push(k); }
          parMois[k] += Number(r.montant) || 0;
        });
        ordre.sort();

        var parCat = C.groupBy(rows, 'categorie');
        var catsRows = Object.keys(parCat).map(function (k) {
          return { id: k, label: libelleCategorieDepense(k),
            total: C.sum(parCat[k], 'montant'), nombre: parCat[k].length };
        });
        catsRows = C.sortBy(catsRows, 'total', 'desc');

        vue.appendChild(K.charts([
          {
            title: 'Dépenses par mois',
            render: function () {
              return G.barres(ordre.map(function (k) {
                return (C.MOIS[Number(k.split('-')[1]) - 1] || k).slice(0, 4) + ' ' + k.slice(2, 4);
              }), [{ label: 'Décaissé', data: ordre.map(function (k) { return parMois[k]; }),
                color: G.TONES.rouge }]);
            },
          },
          {
            title: 'Répartition par catégorie de dépenses',
            render: function () {
              return G.anneau(catsRows.map(function (r) { return r.label; }),
                catsRows.map(function (r) { return r.total; }));
            },
          },
        ]));

        vue.appendChild(U.card('Cumul par catégorie', U.dataTable({
          rows: catsRows, exportName: 'depenses-categories', pageSize: 10, searchable: false,
          columns: [
            { key: 'label', label: 'Catégorie de dépenses' },
            { key: 'nombre', label: 'Pièces', align: 'right' },
            { key: 'total', label: 'Montant', align: 'right',
              text: function (r) { return C.money(r.total, false); },
              render: function (r) { return el('span.font-semibold', { text: C.money(r.total, false) }); } },
          ],
        })));
      }

      function imprimerEtat(rows) {
        var lignes = C.sortBy(rows.slice(), 'date');
        P.etat({
          titre: 'État des dépenses de trésorerie',
          sousTitre: C.num(lignes.length) + ' dépense(s) — ' + C.money(C.sum(lignes, 'montant')),
          cartouche: [
            ['Nombre de pièces', C.num(lignes.length)],
            ['Total décaissé', C.money(C.sum(lignes, 'montant'))],
            ['Sans justificatif', C.num(lignes.filter(function (r) { return !r.justificatif; }).length)],
            ['Édité le', C.dateFR(AUJ)],
          ],
          contenu: P.tableau([
            { label: 'Date', value: function (r) { return C.dateFR(r.date); } },
            { label: 'N°', value: function (r) { return r.reference; } },
            { label: 'Libellé', value: function (r) { return r.libelle; } },
            { label: 'Compte', value: function (r) { return r.compteCharge; } },
            { label: 'Catégorie', value: function (r) { return libelleCategorieDepense(r.categorie); } },
            { label: 'Reçu', value: function (r) { return r.justificatif ? 'oui' : 'NON'; } },
            { label: 'Montant', align: 'right',
              value: function (r) { return C.money(r.montant, false); },
              somme: function (r) { return r.montant; } },
          ], lignes, { total: true }),
          signatures: [{ role: 'Le Comptable' },
            { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * LE MOTEUR COMMUN AUX DEUX ÉCRANS
   * --------------------------------------------------------------------------
   * Le compte de résultat et le seuil de rentabilité lisent LES MÊMES
   * écritures et posent la même question — « combien de produits, combien de
   * charges » — pour en tirer deux lectures différentes. Deux moteurs auraient
   * divergé au premier correctif, et personne n'aurait su lequel croire.
   *
   * ON NE RETIENT QUE LES ÉCRITURES VALIDÉES. Un brouillon n'est pas un fait
   * comptable : le compter donnerait un résultat qui change quand le comptable
   * rectifie une saisie. Le nombre de brouillons écartés est ANNONCÉ — un
   * écart silencieux entre le journal et le résultat serait pire.
   * ======================================================================== */
  function ecrituresRetenues(bornes) {
    var brouillons = 0;
    var retenues = ecrituresToutes().filter(function (e) {
      if (bornes && !C.dansBornes(e.date, bornes)) return false;
      if (e.statut === 'brouillon') { brouillons++; return false; }
      return true;
    });
    return { lignes: retenues, brouillons: brouillons };
  }

  /** Le solde d'une rubrique : produits au crédit, charges au débit. */
  function soldeRubrique(lignes, rubrique) {
    var total = 0;
    lignes.forEach(function (e) {
      var r = D.rubriqueDuCompte(e.compte);
      if (!r || r.id !== rubrique.id) return;
      /* Un produit vit au CRÉDIT, une charge au DÉBIT. Prendre la différence
         dans le bon sens fait que les avoirs et les annulations se déduisent
         d'eux-mêmes, sans traitement particulier. */
      total += rubrique.sens === 'produit' ? (e.credit - e.debit) : (e.debit - e.credit);
    });
    return total;
  }

  /** La cascade SYSCOHADA — chaque solde retranche au précédent. */
  function soldesGestion(bornes) {
    var src = ecrituresRetenues(bornes);
    var r = {};
    (D.RUBRIQUES_RESULTAT || []).forEach(function (rub) { r[rub.id] = soldeRubrique(src.lignes, rub); });

    var margeCommerciale = r.ventes_march - r.achats_march;
    var production = r.production;
    var valeurAjoutee = margeCommerciale + production - r.consommations;
    var ebe = valeurAjoutee - r.personnel - r.impots;
    var exploitation = ebe - r.dotations - r.autres_charges;
    var financier = r.produits_fin - r.charges_fin;
    var net = exploitation + financier - r.impot_societes;

    return {
      rubriques: r,
      margeCommerciale: margeCommerciale,
      production: production,
      valeurAjoutee: valeurAjoutee,
      ebe: ebe,
      exploitation: exploitation,
      financier: financier,
      net: net,
      chiffreAffaires: r.ventes_march + production,
      brouillons: src.brouillons,
      nbLignes: src.lignes.length,
    };
  }

  /** Charges fixes et variables — le socle du seuil de rentabilité. */
  function chargesParNature(bornes) {
    var src = ecrituresRetenues(bornes);
    var fixe = 0, variable = 0, parCompte = {};
    src.lignes.forEach(function (e) {
      var num = String(e.compte || '');
      if (!/^6/.test(num)) return;
      var montant = (e.debit || 0) - (e.credit || 0);
      if (!montant) return;
      var nature = natureRetenue(num);
      if (nature === 'variable') variable += montant; else fixe += montant;
      if (!parCompte[num]) {
        parCompte[num] = { compte: num, libelle: compteLibelle(num), montant: 0, nature: nature };
      }
      parCompte[num].montant += montant;
    });
    return {
      fixe: fixe, variable: variable,
      comptes: C.sortBy(Object.keys(parCompte).map(function (k) { return parCompte[k]; }), 'montant', 'desc'),
      brouillons: src.brouillons,
    };
  }

  /* La nature retenue : celle du référentiel, sauf si la clinique l'a corrigée.
     La correction vit dans le magasin — c'est une décision de gestion, pas une
     donnée du plan comptable, et elle doit survivre au rechargement. */
  var CLE_NATURES = 'sigh-cnt:natures-charges';
  function naturesCorrigees() {
    /* Le rattachement d'une nature de charge à un compte décide où la
       dépense tombe dans la balance : c'est une décision comptable, donc
       partagée, donc en base. */
    return S.reglage('naturesCharges', {}) || {};
  }
  function natureRetenue(num) {
    var corr = naturesCorrigees();
    return corr[num] || D.natureCharge(num);
  }
  function corrigerNature(num, nature) {
    var corr = naturesCorrigees();
    corr[num] = nature;
    S.setReglage('naturesCharges', corr);
  }

  /* ==========================================================================
   * LES FEUILLETS DE LA LIASSE, DÉPOSÉS OU CALCULÉS (vague 61)
   * --------------------------------------------------------------------------
   * Le compte de résultat (feuillet 7/51) et le tableau des flux de trésorerie
   * (feuillet 8/51) s'affichent AU FORMAT DU FORMULAIRE DÉPOSÉ : mêmes
   * références, mêmes libellés, même ordre, mêmes sous-totaux, mêmes colonnes.
   * Un comptable rapproche l'écran du dépôt ligne à ligne ; une présentation
   * « maison », même juste, l'obligerait à retraduire.
   *
   * DEUX SOURCES POUR UNE COLONNE, JAMAIS MÉLANGÉES DANS LA MÊME :
   *   — un exercice DÉPOSÉ se CITE (`SIGH.liasse`) : des faits, qui ne se
   *     recalculent pas ;
   *   — un exercice du journal se CALCULE : chaque écriture validée va à la
   *     ligne dont le préfixe de compte est le PLUS LONG, puis les sous-totaux
   *     suivent les formules imprimées sur le formulaire (« XC = XB + RA + RB +
   *     somme TE à RJ »). Le sous-total n'est jamais saisi.
   *
   * Seules les écritures VALIDÉES comptent — un brouillon n'est pas un fait
   * comptable — et le nombre de brouillons écartés est annoncé.
   * ======================================================================== */
  function liasse() { return global.SIGH.liasse; }

  /* Les formules que le formulaire imprime dans ses libellés. */
  var FORMULES_RESULTAT = {
    XA: ['TA', 'RA', 'RB'],
    XB: ['TA', 'TB', 'TC', 'TD'],
    XC: ['XB', 'RA', 'RB', 'TE', 'TF', 'TG', 'TH', 'TI', 'RC', 'RD', 'RE', 'RF', 'RG', 'RH', 'RI', 'RJ'],
    XD: ['XC', 'RK'],
    XE: ['XD', 'TJ', 'RL'],
    XF: ['TK', 'TL', 'TM', 'RM', 'RN'],
    XG: ['XE', 'XF'],
    XH: ['TN', 'TO', 'RO', 'RP'],
    XI: ['XG', 'XH', 'RQ', 'RS'],
  };
  var FORMULES_FLUX = {
    BF: ['FB', 'FC', 'FD', 'FE'],
    ZB: ['FA', 'FB', 'FC', 'FD', 'FE'],
    ZC: ['FF', 'FG', 'FH', 'FI', 'FJ'],
    ZD: ['FK', 'FL', 'FM', 'FN'],
    ZE: ['FO', 'FP', 'FQ'],
    ZF: ['ZD', 'ZE'],
    ZG: ['ZB', 'ZC', 'ZF'],
    ZH: ['ZG', 'ZA'],
  };

  /* La ligne « Variation du BF » n'a pas de référence sur le formulaire : on
     lui donne une CLÉ interne, jamais affichée. */
  function cleLigne(l) { return l.ref || (l.ecart === 'bf' ? 'BF' : ''); }

  function appliquerFormules(lignes, formules, v) {
    lignes.forEach(function (l) {
      var cle = cleLigne(l), f = cle && formules[cle];
      if (!f) return;
      v[cle] = f.reduce(function (n, r) { return n + (v[r] || 0); }, 0);
    });
    return v;
  }

  /* Les valeurs d'un exercice DÉPOSÉ, lues telles quelles. */
  function valeursDeposees(lignes, annee) {
    var L = liasse(), cle = annee === L.DEPOT.exerciceN ? 'n' : 'n1', v = {};
    lignes.forEach(function (l) { if (cleLigne(l)) v[cleLigne(l)] = l[cle]; });
    return v;
  }

  /** Le contrôle du formulaire déposé : ses sous-totaux se recalculent-ils ? */
  function controleSousTotaux(lignes, formules, annee) {
    var dep = valeursDeposees(lignes, annee);
    /* Chaque sous-total se compare à SES composantes DÉPOSÉES, sans cascade :
       un écart en amont ne doit pas faire accuser à tort les totaux d'aval
       qui, eux, se recoupent (ZG = ZB + ZC + ZF avec le ZB déposé). */
    return Object.keys(formules).filter(function (k) { return dep[k] != null; }).map(function (k) {
      var recalcule = formules[k].reduce(function (n, r) { return n + (dep[r] || 0); }, 0);
      return { ref: k, depose: dep[k], recalcule: recalcule, ecart: dep[k] - recalcule };
    });
  }

  function exercicesDuJournal() {
    var annees = {};
    annees[AUJ.getFullYear()] = true;
    ecrituresToutes().forEach(function (e) { if (e.date) annees[C.toDate(e.date).getFullYear()] = true; });
    return Object.keys(annees).map(Number).sort(function (a, b) { return b - a; });
  }

  function bornesExercice(annee, arrete) {
    var debut = new Date(annee, 0, 1), finAn = new Date(annee, 11, 31);
    var fin = arrete ? C.toDate(arrete) : finAn;
    if (fin.getFullYear() !== annee || fin > finAn) fin = finAn;
    return { debut: debut, fin: fin, jours: C.daysBetween ? C.daysBetween(debut, fin) + 1 : 365,
      label: 'Exercice ' + annee };
  }

  /* --- Le compte de résultat calculé ------------------------------------- */
  function resultatCalcule(b) {
    var L = liasse();
    var prefixes = [];
    L.RESULTAT.forEach(function (l) {
      if (!l.t && l.comptes) l.comptes.forEach(function (p) { prefixes.push({ p: p, ref: l.ref }); });
    });
    /* LE PRÉFIXE LE PLUS LONG GAGNE : « 654 » (cessions) avant « 65 ». */
    prefixes.sort(function (x, y) { return y.p.length - x.p.length; });

    var src = ecrituresRetenues(b);
    var v = {}, alimentees = {}, orphelins = {};
    src.lignes.forEach(function (e) {
      var num = String(e.compte || '');
      if (!/^[678]/.test(num)) return;
      var hit = prefixes.filter(function (x) { return num.indexOf(x.p) === 0; })[0];
      /* Produit comme charge : crédit − débit. Le formulaire porte les charges
         en NÉGATIF, et c'est exactement ce que ce sens donne. */
      var montant = (e.credit || 0) - (e.debit || 0);
      if (!hit) { orphelins[num] = (orphelins[num] || 0) + montant; return; }
      v[hit.ref] = (v[hit.ref] || 0) + montant;
      alimentees[hit.ref] = true;
    });
    appliquerFormules(L.RESULTAT, FORMULES_RESULTAT, v);
    return { valeurs: v, alimentees: alimentees, orphelins: orphelins,
      brouillons: src.brouillons, nbLignes: src.lignes.length };
  }

  /* --- Le tableau des flux calculé ----------------------------------------
     Méthode indirecte du SYSCOHADA : la CAFG part des charges et produits
     DÉCAISSABLES ; la variation du besoin de financement se lit sur les
     soldes des stocks et des tiers ; investissements et financement se lisent
     sur les mouvements des comptes de classes 1 et 2. Le CONTRÔLE final est
     celui que le formulaire imprime : trésorerie nette au 31/12 calculée par
     les flux = trésorerie des comptes de classe 5. Un écart nomme les comptes
     que le tableau ne classe pas — il ne se corrige pas en silence. */
  var NON_DECAISSABLES = ['68', '69', '79', '81', '82', '654', '754'];
  var TIERS_HORS_BF = ['465', '481', '482', '485', '488'];

  function fluxCalcule(b) {
    var tDebut = C.toDate(b.debut).getTime(), tFin = C.toDate(b.fin).getTime();
    var annee = C.toDate(b.debut).getFullYear();
    var ouverture = {}, mouv = {}, debits = {}, credits = {}, brouillons = 0, nb = 0;
    ecrituresToutes().forEach(function (e) {
      if (!e.date) return;
      var t = C.toDate(e.date).getTime();
      if (t > tFin) return;
      var aNouveau = e.journal === 'AN' && C.toDate(e.date).getFullYear() === annee;
      if (e.statut === 'brouillon') { if (t >= tDebut) brouillons++; return; }
      var num = String(e.compte || ''), d = e.debit || 0, c = e.credit || 0;
      /* Les à-nouveaux SONT l'ouverture : les compter comme des flux ferait
         paraître le capital comme un apport de l'année. */
      if (t < tDebut || aNouveau) { ouverture[num] = (ouverture[num] || 0) + d - c; return; }
      nb++;
      mouv[num] = (mouv[num] || 0) + d - c;
      debits[num] = (debits[num] || 0) + d;
      credits[num] = (credits[num] || 0) + c;
    });

    function commence(num, liste) { return liste.some(function (p) { return num.indexOf(p) === 0; }); }
    function somme(obj, liste, exclus) {
      return Object.keys(obj).reduce(function (n, num) {
        return n + (commence(num, liste) && !(exclus && commence(num, exclus)) ? obj[num] : 0);
      }, 0);
    }
    function tresorerie(soldes) { return somme(soldes, ['5'], ['59']); }
    var comptes = {};
    Object.keys(ouverture).concat(Object.keys(mouv)).forEach(function (k) { comptes[k] = true; });
    var cloture = {};
    Object.keys(comptes).forEach(function (k) { cloture[k] = (ouverture[k] || 0) + (mouv[k] || 0); });

    /* Créances et dettes : un compte de tiers change de côté selon son solde
       (SYSCOHADA) ; on le suit compte par compte, à l'ouverture et à la date. */
    var dActif = 0, dPassif = 0;
    Object.keys(comptes).forEach(function (num) {
      if (!/^4/.test(num) || commence(num, TIERS_HORS_BF)) return;
      var o = ouverture[num] || 0, f = cloture[num];
      dActif += Math.max(f, 0) - Math.max(o, 0);
      dPassif += Math.max(-f, 0) - Math.max(-o, 0);
    });

    var v = {
      ZA: tresorerie(ouverture),
      FA: -somme(mouv, ['6', '7', '8'], NON_DECAISSABLES),
      FB: -somme(mouv, ['485', '488']),
      FC: -somme(mouv, ['3']),
      FD: -dActif,
      FE: dPassif,
      FF: -somme(debits, ['21']),
      FG: -somme(debits, ['22', '23', '24']),
      FH: -somme(debits, ['26', '27']),
      FI: somme(credits, ['82', '754']),
      FJ: 0,
      FK: somme(credits, ['101', '102', '103', '104']),
      FL: somme(credits, ['14']),
      FM: -somme(debits, ['101', '102', '103', '104', '109']),
      FN: -somme(debits, ['465']),
      FO: somme(credits, ['16', '17']),
      FP: somme(credits, ['18']),
      FQ: -somme(debits, ['16', '17', '18']),
    };
    appliquerFormules(liasse().FLUX, FORMULES_FLUX, v);

    var controle = tresorerie(cloture);
    /* Ce que le tableau ne classe pas : affectation du résultat, provisions,
       amortissements et cessions (neutres deux à deux quand la pièce est
       complète), dettes sur immobilisations. S'ils ne s'annulent pas, l'écart
       du contrôle les nomme. */
    var classes = ['5', '6', '7', '8', '3', '4', '21', '22', '23', '24', '26', '27', '10', '14', '16', '17', '18'];
    var nonClasses = {};
    Object.keys(mouv).forEach(function (num) {
      var classe = commence(num, classes) && !commence(num, ['59', '481', '482', '485', '488'].concat(NON_DECAISSABLES));
      if (commence(num, ['485', '488', '465'])) classe = true;
      if (/^(22|23|24|21|26|27|10|16|17|18)/.test(num) && credits[num] && !commence(num, ['16', '17', '18', '101', '102', '103', '104'])) {
        classe = false; /* la sortie d'une immobilisation n'est pas un flux : sa contrepartie est au 81 */
      }
      if (!classe && Math.abs(mouv[num]) > 0.5) nonClasses[num] = mouv[num];
    });

    return { valeurs: v, controle: controle, ecart: controle - v.ZH, nonClasses: nonClasses,
      brouillons: brouillons, nbLignes: nb };
  }

  /* --- Les colonnes d'un feuillet ----------------------------------------- */
  function sourceColonne(genre, annee, b) {
    var L = liasse();
    var lignes = genre === 'resultat' ? L.RESULTAT : L.FLUX;
    var depose = annee === L.DEPOT.exerciceN || annee === L.DEPOT.exerciceN1;
    if (b === null && depose) {
      return { depose: true, annee: annee, valeurs: valeursDeposees(lignes, annee), alimentees: null,
        titre: 'Exercice au 31/12/' + annee, sous: 'déposé — liasse ' + L.DEPOT.code };
    }
    var bb = b || bornesExercice(annee, null);
    var calc = genre === 'resultat' ? resultatCalcule(bb) : fluxCalcule(bb);
    return Object.assign(calc, { depose: false, annee: annee, bornes: bb,
      titre: 'Exercice ' + annee,
      sous: 'calculé — arrêté au ' + C.dateFR(bb.fin) });
  }

  /** Les deux colonnes N et N-1 selon l'exercice choisi. */
  function colonnesFeuillet(genre, choix, arrete) {
    var L = liasse();
    if (choix === 'depose') {
      return [sourceColonne(genre, L.DEPOT.exerciceN, null), sourceColonne(genre, L.DEPOT.exerciceN1, null)];
    }
    var annee = Number(choix);
    var n = sourceColonne(genre, annee, bornesExercice(annee, arrete));
    /* L'exercice précédent se CITE s'il a été déposé, sinon il se calcule. */
    var precedent = annee - 1;
    var n1 = (precedent === L.DEPOT.exerciceN || precedent === L.DEPOT.exerciceN1)
      ? sourceColonne(genre, precedent, null)
      : sourceColonne(genre, precedent, bornesExercice(precedent, null));
    return [n, n1];
  }

  /* --- Le rendu du formulaire, à l'écran et sur la pièce ------------------
     UNE fonction pour les deux supports : la pièce imprimée et l'écran ne
     doivent pas pouvoir montrer deux formulaires différents. */
  function montantFeuillet(col, l, imprime) {
    var cle = cleLigne(l);
    var v = col.valeurs[cle];
    /* Une ligne de détail que le journal n'alimente pas reste VIDE : un zéro
       y ferait croire à un solde nul là où il n'y a pas de donnée. Le
       formulaire déposé, lui, porte ses zéros — on les cite. */
    var vide = !col.depose && !l.t && col.alimentees && !col.alimentees[cle]
      && (col.valeurs[cle] == null || col.valeurs[cle] === 0) && l.comptes;
    if (v == null || vide) return imprime ? '' : el('span.text-slate-300', { text: '—' });
    var texte = C.money(v, false);
    if (imprime) return texte;
    return el('span', { class: (l.t ? 'font-semibold ' : '') + (v < 0 ? 'text-danger-700' : 'text-slate-800'), text: texte });
  }

  function tableFeuillet(genre, lignes, cols, imprime) {
    var L = liasse();
    var bord = imprime ? 'border border-slate-400 px-1.5 py-0.5' : 'border border-slate-200 px-2 py-1';
    var t = el('table', { class: 'w-full border-collapse ' + (imprime ? 'text-[9px]' : 'text-sm') });
    var thead = el('thead');
    var h1 = el('tr', { class: 'bg-slate-100 text-slate-700' });
    function th(txt, opts) {
      var o = opts || {};
      return el('th', { class: bord + ' font-semibold ' + (o.droite ? 'text-right' : 'text-center'),
        rowspan: o.rowspan || null, colspan: o.colspan || null, text: txt });
    }
    h1.appendChild(th('RÉF', { rowspan: 2 }));
    h1.appendChild(th('LIBELLÉS', { rowspan: 2 }));
    h1.appendChild(th('', { rowspan: 2 }));
    if (genre === 'resultat') h1.appendChild(th('(2)', { rowspan: 2 }));
    h1.appendChild(th('NOTE', { rowspan: 2 }));
    cols.forEach(function (c, i) { h1.appendChild(th(c.titre.toUpperCase() + (i === 0 ? ' (N)' : ' (N-1)'))); });
    var h2 = el('tr', { class: 'bg-slate-50 text-slate-500' });
    cols.forEach(function (c) {
      h2.appendChild(el('th', { class: bord + ' text-center font-normal ' + (imprime ? '' : 'text-xs'),
        text: (genre === 'resultat' ? 'NET (1) — ' : '') + c.sous }));
    });
    thead.appendChild(h1); thead.appendChild(h2); t.appendChild(thead);

    var tb = el('tbody');
    var nbCol = (genre === 'resultat' ? 5 : 4) + cols.length;
    lignes.forEach(function (l) {
      if (l.section) {
        tb.appendChild(el('tr', null, [
          el('td', { class: bord }),
          el('td', { class: bord + ' font-bold text-slate-800', colspan: nbCol - 1, text: l.section }),
        ]));
        return;
      }
      var fond = l.t === 'grand' ? 'bg-navy-50 font-bold text-navy-900' : (l.t === 'total' ? 'bg-slate-50 font-semibold' : '');
      var tr = el('tr', { class: fond });
      tr.appendChild(el('td', { class: bord + ' text-center font-mono ' + (imprime ? '' : 'text-xs'), text: l.ref || '' }));
      var lib = el('td', { class: bord + (l.t ? '' : (imprime ? ' pl-3' : ' pl-4 text-slate-700')) });
      if (cleLigne(l) === 'BF') {
        /* Le formulaire l'écrit sur deux lignes, la seconde nommant sa formule. */
        lib.appendChild(el('div', { text: 'Variation du BF lié aux activités opérationnelles' }));
        lib.appendChild(el('div', { class: 'font-normal italic', text: 'FB+FC+FD+FE :' }));
      } else {
        lib.appendChild(document.createTextNode(l.libelle));
      }
      if (!imprime && l.ecart) {
        var ec = L.ecart(l.ecart);
        lib.appendChild(el('span.ml-2.cursor-help', { title: ec ? ec.constat : '' }, [U.badge('écart du document', 'warning')]));
      }
      tr.appendChild(lib);
      tr.appendChild(el('td', { class: bord + ' text-center font-bold', text: l.repere || '' }));
      if (genre === 'resultat') tr.appendChild(el('td', { class: bord + ' text-center', text: l.signe || '' }));
      tr.appendChild(el('td', { class: bord + ' text-center', text: l.note || '' }));
      cols.forEach(function (c) {
        var td = el('td', { class: bord + ' text-right num whitespace-nowrap' });
        C.append(td, montantFeuillet(c, l, imprime));
        tr.appendChild(td);
      });
      tb.appendChild(tr);

      /* Le CONTRÔLE qui clôt le tableau des flux, tel que le formulaire le
         porte sous ZH : trésorerie-actif N − trésorerie-passif N. */
      if (genre === 'flux' && l.ref === 'ZH') {
        var trc = el('tr');
        trc.appendChild(el('td', { class: bord }));
        trc.appendChild(el('td', { class: bord + ' italic', text: 'Contrôle : Trésorerie actif N - Trésorerie passif N' }));
        trc.appendChild(el('td', { class: bord }));
        trc.appendChild(el('td', { class: bord }));
        cols.forEach(function (c) {
          var td = el('td', { class: bord + ' text-right num whitespace-nowrap' });
          if (c.depose) {
            td.className += ' bg-slate-700';
          } else if (imprime) {
            td.textContent = C.money(c.controle, false);
          } else {
            td.appendChild(el('span', { class: Math.abs(c.ecart) < 1 ? 'font-semibold text-success-700' : 'font-semibold text-danger-700',
              text: C.money(c.controle, false) }));
          }
          trc.appendChild(td);
        });
        tb.appendChild(trc);
      }
    });
    t.appendChild(tb);
    return imprime ? t : el('div.overflow-x-auto', null, t);
  }

  /** L'en-tête du feuillet : celui que la DGI imprime au-dessus du tableau. */
  function enteteFeuillet(titre, cols) {
    var L = liasse();
    var depose = cols[0].depose;
    return el('div.space-y-3', null, [
      el('div.grid.gap-x-8.gap-y-1.text-sm.sm:grid-cols-2', null, [
        el('div.flex.gap-3', null, [el('span.w-40.shrink-0.text-slate-500', { text: 'Date de dépôt :' }),
          el('span.font-medium.text-slate-800', { text: depose ? C.dateFR(L.DEPOT.dateDepot) : 'Non déposé — exercice calculé' })]),
        el('div.flex.gap-3', null, [el('span.w-40.shrink-0.text-slate-500', { text: 'Code de dépôt :' }),
          el('span.font-mono.text-slate-800', { text: depose ? L.DEPOT.code : '—' })]),
        el('div.flex.gap-3', null, [el('span.w-40.shrink-0.text-slate-500', { text: 'Dénomination sociale :' }),
          el('span.font-medium.text-slate-800', { text: L.DEPOT.denomination })]),
        el('div.flex.gap-3', null, [el('span.w-40.shrink-0.text-slate-500', { text: 'IFU :' }),
          el('span.font-mono.text-slate-800', { text: L.DEPOT.ifu })]),
      ]),
      el('h3.text-center.text-base.font-bold.uppercase.tracking-wide.text-navy-900', { text: titre }),
    ]);
  }

  /** La barre de choix commune aux deux feuillets. */
  function barreFeuillet(genre, surChangement, imprimer) {
    var L = liasse();
    var selEx = el('select.select', { id: 'feuillet-exercice-' + genre });
    exercicesDuJournal().forEach(function (a) {
      selEx.appendChild(el('option', { value: String(a) }, 'Exercice ' + a + ' — calculé depuis le journal'));
    });
    selEx.appendChild(el('option', { value: 'depose' },
      'Exercice ' + L.DEPOT.exerciceN + ' — liasse déposée (' + L.DEPOT.code + ')'));
    selEx.value = String(AUJ.getFullYear());
    var inDate = el('input.input', { type: 'date', id: 'feuillet-arrete-' + genre, value: C.iso(AUJ) });
    var blocDate = el('div', null, [el('label.label', { for: inDate.id, text: 'Arrêté au' }), inDate]);

    selEx.addEventListener('change', function () {
      if (selEx.value !== 'depose') {
        var a = Number(selEx.value);
        inDate.value = a === AUJ.getFullYear() ? C.iso(AUJ) : a + '-12-31';
      }
      blocDate.hidden = selEx.value === 'depose';
      surChangement();
    });
    inDate.addEventListener('change', surChangement);

    var carte = el('div.card', null, el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
      el('div', null, [el('label.label', { for: selEx.id, text: 'Exercice' }), selEx]),
      blocDate,
      K.btn(genre === 'resultat' ? 'Imprimer le compte de résultat' : 'Imprimer le tableau des flux',
        { variant: 'primary', icon: 'printer', onclick: imprimer }),
    ]));
    return { carte: carte, choix: function () { return selEx.value; }, arrete: function () { return inDate.value; } };
  }

  function signaturesFeuillet() {
    return [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
      { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }];
  }

  function cartoucheFeuillet(cols) {
    var L = liasse();
    return [
      ['Dénomination sociale', L.DEPOT.denomination],
      ['IFU', L.DEPOT.ifu],
      ['Date de dépôt', cols[0].depose ? C.dateFR(L.DEPOT.dateDepot) : 'Non déposé'],
      ['Code de dépôt', cols[0].depose ? L.DEPOT.code : '—'],
      ['Colonne N', cols[0].titre + ' — ' + cols[0].sous],
      ['Colonne N-1', cols[1].titre + ' — ' + cols[1].sous],
    ];
  }

  function noteSourceFeuillet(cols) {
    var calc = cols.filter(function (c) { return !c.depose; });
    var brouillons = calc.reduce(function (n, c) { return n + (c.brouillons || 0); }, 0);
    var morceaux = cols.map(function (c) {
      return '<strong>' + C.escapeHtml(c.titre) + '</strong> : ' + C.escapeHtml(c.sous)
        + (c.depose ? '' : ' (' + C.num(c.nbLignes) + ' ligne(s) d’écriture validée(s) retenue(s))');
    });
    return K.note(morceaux.join(' · ')
      + (brouillons ? '. <strong>' + C.num(brouillons) + ' brouillon(s) écarté(s)</strong> : un brouillon n’est pas '
        + 'un fait comptable, et le compter donnerait un résultat qui change quand le comptable rectifie une saisie.'
        : '.'),
    { tone: brouillons ? 'warning' : 'info', icon: 'book-open-text' });
  }

  /* ==========================================================================
   * COMPTE DE RÉSULTAT — feuillet 7/51
   * ======================================================================== */
  global.SIGH.screen('m12-compte-resultat', {
    title: 'Compte de résultat',
    description: 'Le compte de résultat au format du feuillet 7/51 de la liasse DGI : déposé ou calculé depuis le journal.',
    regle: 'L’écran reproduit <strong>le formulaire déposé</strong> le 15/05/2026 (feuillet 7/51) : références TA à XI, '
      + 'libellés, colonne (2), notes et sous-totaux, au même ordre. Un exercice <strong>déposé se cite</strong> ; un '
      + 'exercice du journal <strong>se calcule</strong> — chaque écriture validée va à la ligne de son compte '
      + 'SYSCOHADA, et les sous-totaux suivent les <strong>formules imprimées</strong> sur le formulaire. Seules les '
      + 'écritures <strong>validées</strong> sont retenues, et le nombre de brouillons écartés est annoncé.',
    actions: function () {
      return [
        K.btn('Tableau des flux', { icon: 'arrow-left-right',
          onclick: function () { global.SIGH.app.go('m12-flux-tresorerie'); } }),
        K.btn('Seuil de rentabilité', { icon: 'target',
          onclick: function () { global.SIGH.app.go('m12-seuil-rentabilite'); } }),
      ];
    },
    render: function (root) {
      var L = liasse();
      var vue = el('div.space-y-4');
      var barre = barreFeuillet('resultat', afficher, imprimer);
      root.appendChild(el('div.space-y-4', null, [barre.carte, vue]));
      afficher();
      return null;

      function cols() { return colonnesFeuillet('resultat', barre.choix(), barre.arrete()); }
      function val(c, ref) { return c.valeurs[ref] || 0; }

      function afficher() {
        C.clear(vue);
        var cc = cols(), n = cc[0], n1 = cc[1];
        vue.appendChild(noteSourceFeuillet(cc));

        function evolution(ref) {
          var a = val(n, ref), b = val(n1, ref);
          return b ? 'N-1 : ' + C.money(b) + ' (' + (a - b >= 0 ? '+' : '') + C.pct((a - b) / Math.abs(b) * 100) + ')' : 'N-1 : ' + C.money(b);
        }
        vue.appendChild(U.kpiGrid([
          { label: 'Chiffre d’affaires (XB)', value: C.money(val(n, 'XB')), icon: 'trending-up', tone: 'navy', hint: evolution('XB') },
          { label: 'Valeur ajoutée (XC)', value: C.money(val(n, 'XC')), icon: 'sparkles', tone: 'info', hint: evolution('XC') },
          { label: 'Excédent brut d’exploitation (XD)', value: C.money(val(n, 'XD')), icon: 'activity',
            tone: val(n, 'XD') >= 0 ? 'success' : 'danger', hint: evolution('XD') },
          { label: 'Résultat net (XI)', value: C.money(val(n, 'XI')), icon: val(n, 'XI') >= 0 ? 'smile' : 'frown',
            tone: val(n, 'XI') >= 0 ? 'success' : 'danger', hint: evolution('XI') },
        ]));

        vue.appendChild(U.card('Compte de résultat — feuillet 7/51', el('div.space-y-3', null, [
          enteteFeuillet('Compte de résultat', cc),
          tableFeuillet('resultat', L.RESULTAT, cc, false),
          el('p.text-xs.text-slate-500', {
            text: '(1) Montants nets. (2) Signe de la ligne : + produit, - charge, -/+ variation. Les charges '
              + 'figurent en négatif, comme sur le formulaire déposé.',
          }),
        ])));

        vue.appendChild(U.card('Lecture du formulaire', el('div.space-y-2', null, [
          K.note('<strong>MARGE COMMERCIALE (XA)</strong> — RG-02 facture les médicaments au prix d’achat, sans marge : '
            + 'ce solde doit être nul ou quasi nul, et il l’est à la liasse déposée. S’il cessait de l’être, ce serait '
            + 'un signal, pas une bonne nouvelle.', { tone: 'success', icon: 'check-circle-2' }),
          K.note('<strong>EXCÉDENT BRUT D’EXPLOITATION (XD)</strong> — ce qui reste après avoir payé les hommes et '
            + 'l’État. Il ignore les amortissements et le financement, qui dépendent de décisions passées : c’est lui '
            + 'qu’on regarde pour savoir si l’exploitation tient debout.', { tone: 'info', icon: 'activity' }),
          K.note('<strong>RÉSULTAT FINANCIER (XF)</strong> — les intérêts d’emprunt (RM) sont ici, PAS dans '
            + 'l’exploitation : les y mettre ferait juger l’activité sur des choix de financement.',
          { tone: 'info', icon: 'landmark' }),
        ])));

        vue.appendChild(blocControles(cc));

        vue.appendChild(K.charts([{
          title: 'De la valeur ajoutée au résultat net — N et N-1',
          render: function () {
            var refs = ['XC', 'XD', 'XE', 'XG', 'XI'];
            return G.barres(['Valeur ajoutée', 'EBE', 'Résultat d’exploitation', 'Activités ordinaires', 'Résultat net'], [
              { label: n.titre, data: refs.map(function (r) { return val(n, r); }), color: G.TONES.navy },
              { label: n1.titre, data: refs.map(function (r) { return val(n1, r); }), color: G.TONES.ciel },
            ], { height: 260 });
          },
        }]));

        vue.appendChild(K.source(L.DEPOT.source + ' — feuillet 7/51. Les exercices non déposés sont calculés depuis '
          + 'les écritures validées du journal, par les préfixes de comptes SYSCOHADA de chaque ligne.'));
      }

      function blocControles(cc) {
        var blocs = [];
        cc.forEach(function (c) {
          if (c.depose) {
            var ctl = controleSousTotaux(L.RESULTAT, FORMULES_RESULTAT, c.annee);
            var faux = ctl.filter(function (x) { return Math.abs(x.ecart) > 0.5; });
            blocs.push(K.note('<strong>' + C.escapeHtml(c.titre) + ' (déposé)</strong> — '
              + (faux.length
                ? C.num(faux.length) + ' sous-total(aux) ne se recalcule(nt) pas depuis ses lignes : '
                  + faux.map(function (x) { return x.ref + ' (écart ' + C.money(x.ecart) + ')'; }).join(', ')
                  + '. Écart du document, conservé et non arbitré.'
                : 'les ' + C.num(ctl.length) + ' sous-totaux déposés (XA à XI) se recalculent <strong>à l’identique</strong> '
                  + 'depuis leurs lignes par les formules du formulaire.'),
            { tone: faux.length ? 'warning' : 'success', icon: faux.length ? 'alert-triangle' : 'check-circle-2' }));
          } else {
            var orph = Object.keys(c.orphelins || {});
            blocs.push(K.note('<strong>' + C.escapeHtml(c.titre) + ' (calculé)</strong> — '
              + (orph.length
                ? C.num(orph.length) + ' compte(s) de gestion sans ligne du formulaire : '
                  + orph.map(function (k) { return k + ' (' + C.money(c.orphelins[k]) + ')'; }).join(', ')
                  + '. Ils ne sont PAS comptés — les rattacher au plan comptable.'
                : 'toutes les écritures de gestion retenues se rattachent à une ligne du formulaire. Les lignes '
                  + 'vides (—) sont celles que le journal n’alimente pas.'),
            { tone: orph.length ? 'warning' : 'success', icon: orph.length ? 'alert-triangle' : 'check-circle-2' }));
          }
        });
        return U.card('Contrôles', el('div.space-y-2', null, blocs));
      }

      function imprimer() {
        var cc = cols();
        P.etat({
          titre: 'Compte de résultat',
          sousTitre: cc[0].titre + ' — ' + cc[0].sous,
          cartouche: cartoucheFeuillet(cc),
          contenu: el('div.space-y-2', null, [
            tableFeuillet('resultat', L.RESULTAT, cc, true),
            el('p', { class: 'text-[9px] italic', text: '(1) Montants nets. (2) + produit, - charge, -/+ variation. '
              + 'Formulaire au format du feuillet 7/51 de la liasse DGI ; sous-totaux calculés par les formules du formulaire.' }),
          ]),
          signatures: signaturesFeuillet(),
        });
      }
    },
  });

  /* ==========================================================================
   * TABLEAU DES FLUX DE TRÉSORERIE — feuillet 8/51
   * ======================================================================== */
  global.SIGH.screen('m12-flux-tresorerie', {
    title: 'Tableau des flux de trésorerie',
    description: 'Le tableau des flux au format du feuillet 8/51 de la liasse DGI : déposé ou calculé depuis le journal, contrôle compris.',
    regle: 'L’écran reproduit <strong>le formulaire déposé</strong> (feuillet 8/51) : trésorerie au 1er janvier (ZA), '
      + 'flux opérationnels (FA à FE, ZB), d’investissement (FF à FJ, ZC), de financement (FK à FQ, ZD à ZF), '
      + 'variation (ZG) et trésorerie au 31 décembre (ZH). Un exercice du journal se calcule par la <strong>méthode '
      + 'indirecte</strong> et se termine par le <strong>contrôle</strong> du formulaire — trésorerie-actif moins '
      + 'trésorerie-passif. Un écart ne se corrige pas : il <strong>nomme</strong> les comptes que le tableau ne classe '
      + 'pas. Les écarts internes du document déposé sont signalés, jamais arbitrés.',
    actions: function () {
      return [
        K.btn('Compte de résultat', { icon: 'chart-no-axes-combined',
          onclick: function () { global.SIGH.app.go('m12-compte-resultat'); } }),
        K.btn('Bilan d’ouverture', { icon: 'calendar-plus',
          onclick: function () { global.SIGH.app.go('m12-ouverture'); } }),
      ];
    },
    render: function (root) {
      var L = liasse();
      var vue = el('div.space-y-4');
      var barre = barreFeuillet('flux', afficher, imprimer);
      root.appendChild(el('div.space-y-4', null, [barre.carte, vue]));
      afficher();
      return null;

      function cols() { return colonnesFeuillet('flux', barre.choix(), barre.arrete()); }
      function val(c, ref) { return c.valeurs[ref] || 0; }

      function afficher() {
        C.clear(vue);
        var cc = cols(), n = cc[0];
        vue.appendChild(noteSourceFeuillet(cc));

        vue.appendChild(U.kpiGrid([
          { label: 'Trésorerie au 1er janvier (ZA)', value: C.money(val(n, 'ZA')), icon: 'wallet', tone: 'neutral' },
          { label: 'Flux opérationnels (ZB)', value: C.money(val(n, 'ZB')), icon: 'activity',
            tone: val(n, 'ZB') >= 0 ? 'success' : 'danger', hint: 'CAFG : ' + C.money(val(n, 'FA')) },
          { label: 'Variation de la trésorerie (ZG)', value: C.money(val(n, 'ZG')), icon: 'arrow-left-right',
            tone: val(n, 'ZG') >= 0 ? 'success' : 'danger',
            hint: 'Investissement ' + C.money(val(n, 'ZC')) + ' · financement ' + C.money(val(n, 'ZF')) },
          { label: 'Trésorerie au 31 décembre (ZH)', value: C.money(val(n, 'ZH')), icon: 'landmark', tone: 'navy',
            hint: n.depose ? 'Égale au total trésorerie-actif du bilan (BT)'
              : (Math.abs(n.ecart) < 1 ? 'Contrôle concordant' : 'Écart au contrôle : ' + C.money(n.ecart)) },
        ]));

        vue.appendChild(U.card('Tableau des flux de trésorerie — feuillet 8/51', el('div.space-y-3', null, [
          enteteFeuillet('Tableau des flux de trésorerie', cc),
          tableFeuillet('flux', L.FLUX, cc, false),
          el('p.text-xs.text-slate-500', {
            text: '(1) À l’exclusion des variations des créances et dettes liées aux activités d’investissement '
              + '(variation des créances sur cession d’immobilisation et des dettes sur acquisition ou production '
              + 'd’immobilisation) et de financement (par exemple variation des créances sur subventions '
              + 'd’investissement reçues).',
          }),
        ])));

        vue.appendChild(blocControles(cc));

        if (cc.some(function (c) { return c.depose; })) {
          var cles = cc.some(function (c) { return c.depose && c.annee === L.DEPOT.exerciceN1; }) ? ['bf', 'zb', 'cafg'] : ['bf', 'zb'];
          var sel = L.ECARTS.filter(function (x) { return cles.indexOf(x.cle) !== -1; });
          vue.appendChild(U.card('Écarts internes du document déposé — conservés, non arbitrés', el('div.space-y-2', null, [
            K.note('Le formulaire déposé ne se recoupe pas partout. Ces écarts sont ceux du <strong>document remis à '
              + 'l’administration</strong> : les corriger ici ferait diverger le logiciel de ce que la clinique a '
              + 'réellement déposé — précisément ce qu’un contrôle vient comparer.', { tone: 'warning', icon: 'alert-triangle' }),
            K.miniTable(['Ligne', 'Constat', 'Lecture'], sel.map(function (x) { return [x.titre, x.constat, x.lecture]; })),
          ])));
        }

        vue.appendChild(K.charts([{
          title: 'Composantes de la variation de trésorerie — ' + n.titre,
          render: function () {
            return G.barres(['Opérationnels (ZB)', 'Investissement (ZC)', 'Financement (ZF)', 'Variation (ZG)'], [
              { label: n.titre, data: [val(n, 'ZB'), val(n, 'ZC'), val(n, 'ZF'), val(n, 'ZG')], color: G.TONES.navy },
            ], { height: 240 });
          },
        }]));

        vue.appendChild(K.source(L.DEPOT.source + ' — feuillet 8/51. Les exercices non déposés sont calculés depuis '
          + 'les écritures validées du journal ; les à-nouveaux (journal AN) forment l’ouverture, jamais un flux.'));
      }

      function blocControles(cc) {
        var blocs = [];
        cc.forEach(function (c) {
          if (c.depose) {
            var ctl = controleSousTotaux(L.FLUX, FORMULES_FLUX, c.annee);
            var faux = ctl.filter(function (x) { return Math.abs(x.ecart) > 0.5; });
            blocs.push(K.note('<strong>' + C.escapeHtml(c.titre) + ' (déposé)</strong> — '
              + (faux.length
                ? C.num(faux.length) + ' sous-total(aux) déposé(s) ne se recalcule(nt) pas depuis ses lignes : '
                  + faux.map(function (x) { return (x.ref === 'BF' ? 'Variation du BF' : x.ref) + ' (déposé '
                    + C.money(x.depose) + ', recalculé ' + C.money(x.recalcule) + ')'; }).join(' ; ')
                  + '. Écarts du document, conservés et non arbitrés.'
                : 'les sous-totaux déposés se recalculent à l’identique depuis leurs lignes.'),
            { tone: faux.length ? 'warning' : 'success', icon: faux.length ? 'alert-triangle' : 'check-circle-2' }));
          } else {
            var ok = Math.abs(c.ecart) < 1;
            var nc = Object.keys(c.nonClasses || {});
            blocs.push(K.note('<strong>' + C.escapeHtml(c.titre) + ' (calculé)</strong> — contrôle du formulaire : '
              + 'trésorerie des comptes de classe 5 au ' + C.dateFR(c.bornes.fin) + ' = <strong>'
              + C.money(c.controle) + '</strong>, trésorerie par les flux (ZH) = <strong>' + C.money(c.valeurs.ZH)
              + '</strong>. '
              + (ok ? 'Les deux concordent : chaque mouvement de trésorerie est expliqué par une ligne du tableau.'
                : 'Écart de <strong>' + C.money(c.ecart) + '</strong>'
                  + (nc.length ? ', porté par des comptes que le tableau ne classe pas : '
                    + nc.map(function (k) { return k + ' (' + C.money(c.nonClasses[k]) + ')'; }).join(', ') : '')
                  + '. Il se lève en complétant les écritures, pas en retouchant le tableau.'),
            { tone: ok ? 'success' : 'danger', icon: ok ? 'check-circle-2' : 'alert-triangle' }));
            if (!c.valeurs.ZA) {
              blocs.push(K.note('La trésorerie au 1er janvier ' + c.annee + ' se lit dans le journal : '
                + '<strong>sans à-nouveaux</strong> (bilan d’ouverture), elle vaut zéro. La liasse déposée porte '
                + C.money(L.FLUX.filter(function (x) { return x.ref === 'ZH'; })[0].n) + ' au 31/12/'
                + L.DEPOT.exerciceN + ' — reporter les soldes par le bilan d’ouverture pour les faire coïncider.',
              { tone: 'info', icon: 'calendar-plus' }));
            }
          }
        });
        return U.card('Contrôles', el('div.space-y-2', null, blocs));
      }

      function imprimer() {
        var cc = cols();
        P.etat({
          titre: 'Tableau des flux de trésorerie',
          sousTitre: cc[0].titre + ' — ' + cc[0].sous,
          cartouche: cartoucheFeuillet(cc),
          contenu: el('div.space-y-2', null, [
            tableFeuillet('flux', L.FLUX, cc, true),
            el('p', { class: 'text-[9px] italic', text: '(1) À l’exclusion des variations des créances et dettes liées '
              + 'aux activités d’investissement et de financement. Formulaire au format du feuillet 8/51 de la liasse DGI.' }),
          ]),
          signatures: signaturesFeuillet(),
        });
      }
    },
  });

  /* ==========================================================================
   * SEUIL DE RENTABILITÉ
   * ======================================================================== */
  global.SIGH.screen('m12-seuil-rentabilite', {
    title: 'Seuil de rentabilité',
    description: 'Charges fixes et variables, marge sur coût variable, seuil, point mort et marge de sécurité.',
    regle: 'Le seuil repose sur <strong>une distinction et une seule</strong> : les charges qui suivent '
      + 'l’activité et celles qui tombent qu’on travaille ou non. Cette répartition est un '
      + '<strong>jugement de gestion, pas une donnée du plan comptable</strong> : elle est proposée, '
      + 'affichée et corrigeable compte par compte. La cacher donnerait un seuil qui a l’air d’un fait '
      + 'alors qu’il dépend d’un choix.',
    actions: function () {
      return [
        K.btn('Compte de résultat', { icon: 'chart-no-axes-combined',
          onclick: function () { global.SIGH.app.go('m12-compte-resultat'); } }),
      ];
    },
    render: function (root) {
      var selPeriode = el('select.select');
      C.PERIODES.forEach(function (x) { selPeriode.appendChild(el('option', { value: x.id }, x.label)); });
      selPeriode.value = 'annee';
      var inDate = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Période' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Arrêté au' }), inDate]),
        K.btn('Imprimer l’analyse', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));
      [selPeriode, inDate].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function bornes() { return C.bornes(selPeriode.value, inDate.value); }

      function calcul() {
        var b = bornes();
        var s2 = soldesGestion(b);
        var ch = chargesParNature(b);
        var ca = s2.chiffreAffaires;
        var marge = ca - ch.variable;
        var taux = ca ? marge / ca : 0;
        var seuil = taux > 0 ? ch.fixe / taux : null;
        var securite = seuil != null ? ca - seuil : null;
        /* LE POINT MORT : la date à laquelle le seuil est atteint, en supposant
           l'activité régulière sur la période. C'est une approximation, et
           l'écran le dit — une clinique n'a pas un rythme constant. */
        var pointMort = (seuil != null && ca > 0 && seuil <= ca)
          ? C.addDays(b.debut, Math.round(seuil / ca * b.jours)) : null;
        return { b: b, ca: ca, fixe: ch.fixe, variable: ch.variable, marge: marge,
          taux: taux, seuil: seuil, securite: securite, pointMort: pointMort,
          comptes: ch.comptes, brouillons: ch.brouillons };
      }

      function afficher() {
        C.clear(vue);
        var r = calcul();

        vue.appendChild(K.note('La répartition <strong>fixe / variable</strong> est une '
          + '<strong>proposition</strong>. Aucun plan comptable ne la porte : elle relève de l’analyse '
          + 'de gestion. Elle est affichée compte par compte ci-dessous et se corrige d’un clic — '
          + 'le seuil se recalcule aussitôt.', { tone: 'warning', icon: 'triangle-alert' }));

        vue.appendChild(U.kpiGrid([
          { label: 'Chiffre d’affaires', value: C.money(r.ca), icon: 'trending-up', tone: 'success' },
          { label: 'Charges variables', value: C.money(r.variable), icon: 'activity', tone: 'info',
            hint: r.ca ? C.pct(r.variable / r.ca * 100) + ' du CA' : '' },
          { label: 'Charges fixes', value: C.money(r.fixe), icon: 'anchor', tone: 'warning' },
          { label: 'Marge sur coût variable', value: C.money(r.marge), icon: 'scale', tone: 'navy',
            hint: 'taux : ' + C.pct(r.taux * 100) },
          { label: 'Seuil de rentabilité', value: r.seuil != null ? C.money(r.seuil) : 'incalculable',
            icon: 'target', tone: 'navy',
            hint: r.seuil == null ? 'marge sur coût variable nulle ou négative' : 'CA à atteindre' },
          { label: 'Marge de sécurité',
            value: r.securite != null ? C.money(r.securite) : '—',
            icon: r.securite != null && r.securite >= 0 ? 'shield-check' : 'shield-alert',
            tone: r.securite != null && r.securite >= 0 ? 'success' : 'danger',
            hint: r.securite != null && r.ca
              ? C.pct(r.securite / r.ca * 100) + ' du CA' : '' },
        ]));

        if (r.seuil == null) {
          vue.appendChild(K.note('<strong>Le seuil ne peut pas être calculé.</strong> La marge sur coût '
            + 'variable est nulle ou négative : chaque prestation vendue coûte plus qu’elle ne rapporte, '
            + 'et aucun volume d’activité ne couvrirait les charges fixes. Ce n’est pas un défaut '
            + 'd’affichage, c’est le diagnostic.', { tone: 'danger', icon: 'triangle-alert' }));
        } else {
          vue.appendChild(K.note('<strong>' + C.money(r.seuil) + '</strong> de chiffre d’affaires '
            + 'couvrent les charges. Au-delà, chaque franc encaissé rapporte '
            + C.pct(r.taux * 100) + ' de marge.'
            + (r.pointMort ? ' <strong>Point mort atteint le ' + C.dateFR(r.pointMort) + '</strong> — '
              + 'en supposant l’activité régulière sur la période, ce qu’une clinique n’est jamais tout '
              + 'à fait.' : ' Le seuil n’est pas atteint sur la période retenue.')
            + '<br><em>Le seuil suppose la structure constante</em> : il vaut pour un niveau d’activité '
            + 'voisin de l’actuel. L’extrapoler au double serait faux — il faudrait embaucher, et les '
            + 'charges fixes changeraient de palier.',
          { tone: r.securite >= 0 ? 'success' : 'danger', icon: 'target' }));
        }

        vue.appendChild(K.charts([{
          title: 'Couverture des charges par le chiffre d’affaires',
          render: function () {
            return G.barres(['Chiffre d’affaires', 'Charges variables', 'Charges fixes',
              'Seuil de rentabilité'],
            [{ label: 'Montant', data: [r.ca, r.variable, r.fixe, r.seuil || 0],
              color: G.TONES.navy }], { horizontal: true, height: 240 });
          },
        }]));

        var droits = K.droits('M12');
        vue.appendChild(U.card('Nature des charges — proposition corrigeable', U.dataTable({
          rows: r.comptes, exportName: 'nature-charges', pageSize: 20, searchable: true,
          filters: [{ name: 'nature', label: 'Nature',
            options: [{ value: 'fixe', label: 'Fixe' }, { value: 'variable', label: 'Variable' }] }],
          columns: [
            { key: 'compte', label: 'Compte', nowrap: true,
              render: function (x) { return el('span.font-mono.text-xs', { text: x.compte }); } },
            { key: 'libelle', label: 'Intitulé' },
            { key: 'nature', label: 'Nature retenue',
              render: function (x) {
                return x.nature === 'variable'
                  ? U.badge('Variable — suit l’activité', 'info')
                  : U.badge('Fixe — tombe de toute façon', 'warning');
              } },
            { key: 'montant', label: 'Montant', align: 'right',
              text: function (x) { return C.money(x.montant, false); },
              render: function (x) { return el('span.font-semibold', { text: C.money(x.montant, false) }); } },
          ],
          rowActions: function (x) {
            if (!droits.editer) return [];
            return [K.iconBtn('repeat', 'Basculer en ' + (x.nature === 'variable' ? 'fixe' : 'variable'),
              function () {
                corrigerNature(x.compte, x.nature === 'variable' ? 'fixe' : 'variable');
                afficher();
                U.toast('Nature corrigée.', { type: 'success',
                  detail: x.compte + ' — ' + (x.nature === 'variable' ? 'désormais fixe' : 'désormais variable')
                    + '. Le seuil est recalculé.' });
              })];
          },
        })));

        if (!droits.editer) {
          vue.appendChild(K.note('Votre profil consulte l’analyse sans corriger la nature des charges. '
            + 'La matrice des droits (M14) décide de cette ouverture.', { tone: 'neutral', icon: 'lock' }));
        }
      }

      function imprimer() {
        var r = calcul();
        P.etat({
          titre: 'Seuil de rentabilité',
          sousTitre: C.libellePeriode(r.b),
          cartouche: [
            ['Période', C.libellePeriode(r.b)],
            ['Chiffre d’affaires', C.money(r.ca)],
            ['Charges variables', C.money(r.variable)],
            ['Charges fixes', C.money(r.fixe)],
            ['Marge sur coût variable', C.money(r.marge)],
            ['Taux de marge', C.pct(r.taux * 100)],
            ['Seuil de rentabilité', r.seuil != null ? C.money(r.seuil) : 'incalculable'],
            ['Point mort', r.pointMort ? C.dateFR(r.pointMort) : 'non atteint sur la période'],
          ],
          contenu: el('div.space-y-3', null, [
            el('p.font-semibold', { text: 'Méthode' }),
            el('p', { text: 'Marge sur coût variable = chiffre d’affaires − charges variables. '
              + 'Seuil de rentabilité = charges fixes ÷ taux de marge. Marge de sécurité = chiffre '
              + 'd’affaires − seuil : c’est ce que la clinique peut perdre avant de perdre de l’argent.' }),
            el('p.mt-2.font-semibold', { text: 'Réserve' }),
            el('p', { text: 'La répartition fixe / variable est une proposition de gestion, non une '
              + 'donnée du plan comptable. Le seuil suppose en outre la structure constante : il vaut '
              + 'pour un niveau d’activité voisin de l’actuel.' }),
            el('p.mt-3.font-semibold', { text: 'Détail des charges' }),
            P.tableau([
              { label: 'Compte', value: function (x) { return x.compte; } },
              { label: 'Intitulé', value: function (x) { return x.libelle; } },
              { label: 'Nature', value: function (x) { return x.nature === 'variable' ? 'Variable' : 'Fixe'; } },
              { label: 'Montant', align: 'right',
                value: function (x) { return C.money(x.montant, false); },
                somme: function (x) { return x.montant; } },
            ], r.comptes, { total: true }),
          ]),
          signatures: [{ role: 'Le Comptable' },
            { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * BESOIN EN FONDS DE ROULEMENT (BFR_TABLEAU.txt, 22/09/2026)
   * --------------------------------------------------------------------------
   * L'écran ne calcule RIEN : le moteur vit au socle (`PR.bfr`), parce que le
   * pilotage, les tableaux de bord de la Direction et les alertes le lisent
   * aussi. Ici on MONTRE — et surtout on montre D'OÙ VIENT chaque composante,
   * avec le lien vers le registre qui la tient. Un besoin de financement qui
   * tombe du ciel ne se discute pas en réunion ; celui dont on peut ouvrir
   * les trois sources, si.
   * ======================================================================== */
  global.SIGH.screen('m12-bfr', {
    title: 'Besoin en fonds de roulement',
    description: 'Créances clients, valorisation des stocks et dettes fournisseurs — le besoin de financement du cycle d’exploitation, calculé en continu.',
    regle: 'Le BFR est <strong>agrégé, jamais saisi</strong> : <strong>créances</strong> (M9) '
      + '+ <strong>stocks</strong> (M6) − <strong>dettes fournisseurs</strong> (M7). Chaque composante '
      + 'garde la définition de son registre d’origine — deux définitions du même encours se '
      + 'contrediraient en réunion. Un composant <strong>non amorcé se dit</strong> : un BFR amputé de '
      + 'ses dettes est surestimé, et un chiffre faux qui a l’air juste est pire qu’une case vide.',
    actions: function () {
      return [
        K.btn('Tableau décisionnel', { icon: 'gauge',
          onclick: function () { global.SIGH.app.go('m12-tableau-decisionnel'); } }),
        K.btn('Créances assureurs', { icon: 'hourglass',
          onclick: function () { global.SIGH.app.go('m9-creances'); } }),
      ];
    },
    render: function (root) {
      var selPeriode = el('select.select');
      [{ id: 30, label: '30 derniers jours' }, { id: 90, label: '90 derniers jours' },
        { id: 180, label: '6 derniers mois' }, { id: 365, label: '12 derniers mois' }]
        .forEach(function (x) { selPeriode.appendChild(el('option', { value: String(x.id) }, x.label)); });
      selPeriode.value = '90';
      var inDate = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Encours arrêtés au' }), inDate]),
        el('div', null, [el('label.label', { text: 'Chiffre d’affaires observé sur' }), selPeriode]),
        K.btn('Imprimer l’état du BFR', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));
      [selPeriode, inDate].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function calcul() {
        return PR.bfr({ fin: inDate.value || C.iso(AUJ), jours: Number(selPeriode.value) || 90 });
      }

      function afficher() {
        C.clear(vue);
        var b = calcul();

        /* L'ENCOURS SE LIT À UNE DATE, LE FLUX SUR UNE PÉRIODE. Les afficher
           sous le même filtre sans le dire ferait croire que le stock détenu
           dépend de la fenêtre qu'on regarde. */
        vue.appendChild(K.note('Les <strong>trois encours</strong> sont arrêtés au '
          + C.dateFR(b.arrete) + ' — ils ne dépendent pas de la fenêtre choisie. Seul le '
          + '<strong>chiffre d’affaires</strong>, et donc le BFR exprimé en jours, se lit '
          + 'sur la période du ' + C.dateFR(b.fenetre.debut) + ' au ' + C.dateFR(b.fenetre.fin) + '.',
        { tone: 'info', icon: 'calendar-range' }));

        if (b.incomplet.length) {
          vue.appendChild(K.note('<strong>Calcul incomplet</strong> — ' + b.incomplet.join(' et ')
            + ' ne sont pas amorcés sur ce poste. Le BFR affiché est donc '
            + '<strong>surestimé</strong> de la dette qui manque : ouvrez le registre concerné '
            + 'pour que la composante entre dans le calcul.', { tone: 'danger', icon: 'triangle-alert' }));
        }

        vue.appendChild(U.kpiGrid([
          { label: 'En-cours clients', value: C.money(b.creances), icon: 'hand-coins', tone: 'warning',
            hint: C.money(b.creancesAssureurs, false) + ' assureurs · ' + C.money(b.restesACharge, false) + ' patients' },
          { label: 'Valorisation des stocks', value: C.money(b.stocks), icon: 'package', tone: 'info',
            hint: 'méthode en vigueur : ' + (S.valorisationSortie() === 'cump' ? 'CUMP' : 'prix de vente') },
          { label: 'Dettes fournisseurs', value: C.money(b.dettes), icon: 'file-minus-2', tone: 'success',
            hint: C.num(b.nbDettes) + ' facture(s) non réglée(s)' },
          { label: 'Besoin en fonds de roulement', value: C.money(b.bfr), icon: 'scale',
            tone: b.bfr > 0 ? 'danger' : 'success',
            hint: b.bfrJours != null ? C.num(b.bfrJours) + ' jours de chiffre d’affaires' : 'CA nul sur la période' },
        ]));

        vue.appendChild(K.note(b.bfr > 0
          ? '<strong>' + C.money(b.bfr) + '</strong> que la clinique finance sur sa propre trésorerie : '
            + 'elle a payé ses fournisseurs et constitué son stock avant d’être réglée par ses clients '
            + 'et par les compagnies. C’est ce montant qu’un découvert ou un fonds de roulement doit couvrir.'
          : '<strong>Le cycle d’exploitation dégage de la trésorerie</strong> : les dettes fournisseurs '
            + 'financent à elles seules les créances et le stock. C’est une situation favorable, et rare.',
        { tone: b.bfr > 0 ? 'warning' : 'success', icon: 'wallet' }));

        /* La composition — un anneau dit mieux qu'un tableau ce qui pèse. */
        var comp = el('div.grid.gap-4.lg\\:grid-cols-2');
        comp.appendChild(U.card('Composition du besoin',
          G.anneau(['Créances assureurs', 'Restes à charge patients', 'Stocks'],
            [b.creancesAssureurs, b.restesACharge, b.stocks], { height: 240 })));
        comp.appendChild(U.card('Ce que le cycle finance', K.miniTable([
          { label: 'Composante', key: 'quoi' },
          { label: 'Registre d’origine', key: 'ou' },
          { label: 'Montant', align: 'right', render: function (r) { return C.money(r.montant, false); } },
        ], [
          { quoi: 'Part assureur des factures', ou: 'M9 — Créances assureurs', montant: b.creancesAssureurs },
          { quoi: 'Restes à charge non soldés', ou: 'M8 — Factures', montant: b.restesACharge },
          { quoi: 'Stock détenu', ou: 'M6 — Point de stock', montant: b.stocks },
          { quoi: 'Dettes fournisseurs (à déduire)', ou: 'M7 — Factures fournisseurs', montant: -b.dettes },
        ])));
        vue.appendChild(comp);

        /* LES TROIS SOURCES SONT OUVRABLES. Un agrégat qu'on ne peut pas
           redescendre est un agrégat qu'on ne vérifie jamais. */
        var liens = el('div.flex.flex-wrap.gap-2');
        [['m9-creances', 'Ouvrir la balance âgée des créances', 'hourglass'],
          ['m6-point-stock', 'Ouvrir le point de stock', 'package'],
          ['m7-factures-fournisseurs', 'Ouvrir les factures fournisseurs', 'file-text']]
          .forEach(function (x) {
            liens.appendChild(K.btn(x[1], { size: 'sm', icon: x[2],
              onclick: function () { global.SIGH.app.go(x[0]); } }));
          });
        vue.appendChild(U.card('Redescendre à la source', liens));

        /* Les compagnies au-delà du seuil : c'est là que le BFR se résorbe. */
        var alertes = PR.alertesRecouvrement({ fin: inDate.value || C.iso(AUJ) });
        if (alertes.length) {
          vue.appendChild(U.dataTable({
            title: 'Créances au-delà de ' + alertes[0].seuil + ' jours — le levier le plus court',
            rows: alertes, exportName: 'creances-agees-bfr', pageSize: 10, searchable: true,
            defaultSort: 'montant', defaultDir: 'desc',
            columns: [
              { key: 'assureur', label: 'Compagnie', render: function (r) {
                var a = (D.ASSUREURS || []).filter(function (x) { return x.code === r.assureur; })[0];
                return a ? a.nom : r.assureur;
              } },
              { key: 'nb', label: 'Factures', align: 'right' },
              { key: 'jours', label: 'Ancienneté maximale', align: 'right',
                text: function (r) { return r.jours + ' j'; },
                render: function (r) { return el('span.font-semibold.text-danger-600', { text: r.jours + ' jours' }); } },
              { key: 'montant', label: 'Montant dû', align: 'right',
                text: function (r) { return C.money(r.montant, false); },
                render: function (r) { return el('span.font-bold.text-navy-900', { text: C.money(r.montant, false) }); } },
            ],
            actions: [K.btn('Ouvrir les relances', { size: 'sm', icon: 'send',
              onclick: function () { global.SIGH.app.go('m9-relances'); } })],
          }));
        } else {
          vue.appendChild(U.empty('Aucune créance au-delà du seuil retenu.', { icon: 'check-circle-2' }));
        }
        U.icons(vue);
      }

      function imprimer() {
        var b = calcul();
        P.etat({
          titre: 'Besoin en fonds de roulement',
          sousTitre: 'Encours arrêtés au ' + C.dateFR(b.arrete),
          cartouche: [['En-cours clients', C.money(b.creances)],
            ['dont part assureurs', C.money(b.creancesAssureurs)],
            ['Valorisation des stocks', C.money(b.stocks)],
            ['Dettes fournisseurs', C.money(b.dettes)],
            ['Besoin en fonds de roulement', C.money(b.bfr)],
            ['En jours de chiffre d’affaires', b.bfrJours != null ? C.num(b.bfrJours) + ' jours' : '—']],
          contenu: P.tableau([
            { label: 'Composante', value: function (r) { return r.quoi; } },
            { label: 'Registre d’origine', value: function (r) { return r.ou; } },
            { label: 'Montant', align: 'right', value: function (r) { return C.money(r.montant, false); },
              somme: function (r) { return r.montant; } },
          ], [
            { quoi: 'Part assureur des factures', ou: 'M9 — Créances assureurs', montant: b.creancesAssureurs },
            { quoi: 'Restes à charge non soldés', ou: 'M8 — Factures', montant: b.restesACharge },
            { quoi: 'Stock détenu', ou: 'M6 — Point de stock', montant: b.stocks },
            { quoi: 'Dettes fournisseurs (à déduire)', ou: 'M7 — Factures fournisseurs', montant: -b.dettes },
          ], { total: true }),
          signatures: [{ role: 'Le Comptable' },
            { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * COÛT À L'ACTIVITÉ (BFR_TABLEAU.txt §2.C)
   * --------------------------------------------------------------------------
   * « Le SIGH associe chaque séjour patient ou acte technique aux consommables
   * réels utilisés […] et aux coûts de personnel imputés, pour calculer le
   * coût réel face au tarif de référence. »
   *
   * CE QUI EST CALCULABLE L'EST ; CE QUI NE L'EST PAS SE DIT. Le consommable
   * réel se lit : une dispensation porte son article, sa quantité et son
   * justificatif, donc son coût au CUMP. Le COÛT DE PERSONNEL, lui, n'est PAS
   * imputable à un séjour : aucun document ne donne la clé de répartition, et
   * le prototype refuse depuis toujours d'en inventer une (c'est la même
   * réserve qu'au rapprochement groupe ↔ centre de coûts). L'écran calcule
   * donc une MARGE SUR CONSOMMABLES, la nomme ainsi, et dit ce qu'elle ne
   * comprend pas. L'appeler « coût réel » ferait prendre une marge brute pour
   * un résultat.
   * ======================================================================== */
  global.SIGH.screen('m12-cout-activite', {
    title: 'Coût à l’activité',
    description: 'Consommables réellement sortis pour un séjour ou un acte, face au montant facturé — marge sur consommables par groupe de prestation.',
    regle: 'Le coût retenu est celui des <strong>consommables réellement sortis</strong>, valorisés au '
      + 'CUMP et rattachés par le <strong>justificatif de la sortie</strong> (RG-03). Le '
      + '<strong>coût de personnel n’est PAS imputé</strong> : aucun document ne fournit de clé de '
      + 'répartition par séjour, et en inventer une donnerait un coût de revient qui a l’air d’un fait. '
      + 'Ce qui est affiché est donc une <strong>marge sur consommables</strong>, jamais un résultat.',
    actions: function () {
      return [
        K.btn('Recettes & charges par groupe', { icon: 'scale',
          onclick: function () { global.SIGH.app.go('m12-rentabilite-groupes'); } }),
        K.btn('Coût global de l’agent', { icon: 'user-cog',
          onclick: function () { global.SIGH.app.go('m10-cout-agent'); } }),
      ];
    },
    render: function (root) {
      var inDu = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, -90)) });
      var inAu = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), inDu]),
        el('div', null, [el('label.label', { text: 'au' }), inAu]),
        K.btn('Imprimer l’analyse', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));
      [inDu, inAu].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function dans(d) {
        var x = String(d || '').slice(0, 10);
        return !!x && (!inDu.value || x >= inDu.value) && (!inAu.value || x <= inAu.value);
      }

      function calcul() {
        var prods = {};
        S.collection('produits').active().forEach(function (p) { prods[p.id] = p; });

        /* LA RECETTE PAR GROUPE — les lignes de facture, comme partout
           ailleurs : c'est la seule façon de comparer deux écrans. */
        var recettes = {};
        S.collection('factures').active().filter(function (f) { return dans(f.date); })
          .forEach(function (f) {
            (f.lignes || []).forEach(function (l) {
              var g = D.groupePrestation ? D.groupePrestation(l.categorie, l) : (l.categorie || 'autre');
              var cle = g && g.id ? g.id : String(g || 'autre');
              var lib = g && g.label ? g.label : cle;
              var e = recettes[cle] || (recettes[cle] = { id: cle, groupe: lib, recette: 0, cout: 0, nbLignes: 0 });
              e.recette += l.montant || 0;
              e.nbLignes += 1;
            });
          });

        /* LE COÛT — les sorties de stock de la période, valorisées au CUMP et
           rattachées au groupe par la CATÉGORIE de l'article. Un pansement
           sorti pour un séjour pèse sur l'hospitalisation, un réactif sur le
           laboratoire. */
        var sortantes = ['sortie', 'perte', 'casse', 'peremption'];
        var horsGroupe = 0;
        S.collection('mouvements').active()
          .filter(function (m) { return sortantes.indexOf(m.type) !== -1 && dans(m.date); })
          .forEach(function (m) {
            var p = prods[m.produitId];
            if (!p) return;
            var valeur = (m.quantite || 0) * (p.cump || p.prixAchat || 0);
            var cle = p.categorie === 'medicament' ? 'pharmacie'
              : (p.categorie === 'reactif' || p.categorie === 'conso_labo') ? 'laboratoire'
                : 'hospitalisation';
            var e = recettes[cle];
            if (!e) { horsGroupe += valeur; return; }
            e.cout += valeur;
          });

        var lignes = Object.keys(recettes).map(function (k) {
          var e = recettes[k];
          e.marge = e.recette - e.cout;
          e.taux = e.recette ? e.marge / e.recette * 100 : null;
          return e;
        }).sort(function (a, b) { return b.recette - a.recette; });

        return { lignes: lignes, horsGroupe: horsGroupe };
      }

      function afficher() {
        C.clear(vue);
        var r = calcul();

        vue.appendChild(K.note('<strong>Marge sur consommables, et non coût de revient.</strong> Le '
          + 'coût de personnel n’est pas réparti par séjour : aucun document de la clinique ne donne '
          + 'la clé qui le permettrait, et l’inventer donnerait un chiffre qui aurait l’air d’un fait. '
          + 'Le coût employeur se lit agent par agent au <em>Coût global de l’agent</em>, les charges '
          + 'par centre au <em>Recettes & charges par groupe</em>.', { tone: 'warning', icon: 'triangle-alert' }));

        var recette = C.sum(r.lignes, 'recette');
        var cout = C.sum(r.lignes, 'cout');
        vue.appendChild(U.kpiGrid([
          { label: 'Prestations facturées', value: C.money(recette), icon: 'receipt', tone: 'navy' },
          { label: 'Consommables sortis', value: C.money(cout), icon: 'package-minus', tone: 'warning' },
          { label: 'Marge sur consommables', value: C.money(recette - cout), icon: 'scale',
            tone: recette - cout >= 0 ? 'success' : 'danger' },
          { label: 'Taux de marge', value: recette ? C.pct((recette - cout) / recette * 100) : '—',
            icon: 'percent', tone: 'info', hint: 'hors personnel et charges de structure' },
        ]));

        if (r.lignes.length) {
          vue.appendChild(U.card('Recette et consommation par groupe',
            G.barres(r.lignes.map(function (x) { return x.groupe; }), [
              { label: 'Facturé', data: r.lignes.map(function (x) { return x.recette; }) },
              { label: 'Consommables', data: r.lignes.map(function (x) { return x.cout; }) },
            ], { height: 260 })));
        }

        vue.appendChild(U.dataTable({
          title: 'Marge sur consommables par groupe de prestation',
          rows: r.lignes, exportName: 'cout-activite', pageSize: 12, searchable: true,
          defaultSort: 'recette', defaultDir: 'desc',
          columns: [
            { key: 'groupe', label: 'Groupe de prestation' },
            { key: 'nbLignes', label: 'Lignes facturées', align: 'right' },
            { key: 'recette', label: 'Facturé', align: 'right',
              text: function (x) { return C.money(x.recette, false); },
              render: function (x) { return C.money(x.recette, false); } },
            { key: 'cout', label: 'Consommables', align: 'right',
              text: function (x) { return C.money(x.cout, false); },
              render: function (x) { return C.money(x.cout, false); } },
            { key: 'marge', label: 'Marge', align: 'right',
              text: function (x) { return C.money(x.marge, false); },
              render: function (x) {
                return el('span', { class: x.marge >= 0 ? 'font-semibold text-success-600' : 'font-semibold text-danger-600',
                  text: C.money(x.marge, false) });
              } },
            { key: 'taux', label: 'Taux', align: 'right',
              text: function (x) { return x.taux == null ? '—' : C.pct(x.taux); },
              render: function (x) { return x.taux == null ? '—' : C.pct(x.taux); } },
          ],
        }));

        if (r.horsGroupe > 0) {
          vue.appendChild(K.note('<strong>' + C.money(r.horsGroupe) + '</strong> de sorties ne se '
            + 'rattachent à aucun groupe facturé sur la période — fournitures, entretien, petit '
            + 'matériel. Elles sont <strong>comptées à part plutôt que réparties</strong> : les imputer '
            + 'à un groupe au prorata fabriquerait une clé que rien ne justifie.',
          { tone: 'info', icon: 'info' }));
        }

        /* LA PRÉVISION — l'historique des admissions donne un profil mensuel,
           et c'est tout ce qu'il donne. */
        vue.appendChild(previsionSaisonniere());
        U.icons(vue);
      }

      /**
       * L'impact saisonnier, DÉDUIT des admissions et annoncé comme tel.
       * Le document demande de « simuler l'impact budgétaire des variations
       * saisonnières sur le BFR » : l'indice est calculé, la projection est
       * une règle de trois, et l'écran ne prétend pas à davantage.
       */
      function previsionSaisonniere() {
        var MOIS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
          'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];
        var parMois = MOIS.map(function () { return 0; });
        var adm = S.collection('admissions').active();
        adm.forEach(function (a) {
          var d = String(a.dateEntree || '').slice(0, 10);
          if (!d) return;
          var m = Number(d.slice(5, 7)) - 1;
          if (m >= 0 && m < 12) parMois[m] += 1;
        });
        var observes = parMois.filter(function (n) { return n > 0; });
        if (observes.length < 3) {
          return U.card('Prévision saisonnière',
            U.empty('Moins de trois mois d’admissions renseignés : aucun profil saisonnier ne peut '
              + 'être déduit. Un indice calculé sur deux mois ne serait pas une prévision, ce serait '
              + 'une coïncidence.', { icon: 'calendar-off' }));
        }
        var moyenne = C.sum(observes, function (n) { return n; }) / observes.length;
        var b = PR.bfr({ fin: inAu.value || C.iso(AUJ) });
        var lignes = MOIS.map(function (lib, i) {
          var indice = parMois[i] && moyenne ? parMois[i] / moyenne : null;
          return {
            mois: lib, admissions: parMois[i],
            indice: indice == null ? null : Math.round(indice * 100) / 100,
            bfrProjete: indice == null ? null : Math.round(b.bfr * indice),
          };
        }).filter(function (x) { return x.admissions > 0; });

        return U.card('Prévision saisonnière du besoin de financement', el('div.space-y-3', null, [
          K.note('<strong>Une projection, pas une prévision budgétaire.</strong> L’indice est le '
            + 'rapport des admissions du mois à la moyenne des mois observés ; le BFR projeté applique '
            + 'cet indice au besoin constaté. Il suppose que le besoin suit l’activité '
            + '<em>proportionnellement</em>, ce qui est vrai des stocks et des créances, faux des '
            + 'charges fixes. À lire comme un ordre de grandeur.', { tone: 'info', icon: 'chart-line' }),
          K.miniTable([
            { label: 'Mois', key: 'mois' },
            { label: 'Admissions', align: 'right', key: 'admissions' },
            { label: 'Indice', align: 'right', render: function (x) { return x.indice == null ? '—' : C.num(x.indice, 2); } },
            { label: 'BFR projeté', align: 'right', render: function (x) { return x.bfrProjete == null ? '—' : C.money(x.bfrProjete, false); } },
          ], lignes),
        ]));
      }

      function imprimer() {
        var r = calcul();
        P.etat({
          titre: 'Coût à l’activité — marge sur consommables',
          sousTitre: 'Du ' + C.dateFR(inDu.value) + ' au ' + C.dateFR(inAu.value),
          cartouche: [['Prestations facturées', C.money(C.sum(r.lignes, 'recette'))],
            ['Consommables sortis', C.money(C.sum(r.lignes, 'cout'))],
            ['Marge sur consommables', C.money(C.sum(r.lignes, 'recette') - C.sum(r.lignes, 'cout'))],
            ['Coût de personnel', 'non imputé — aucune clé de répartition documentée']],
          contenu: P.tableau([
            { label: 'Groupe de prestation', key: 'groupe' },
            { label: 'Lignes', key: 'nbLignes', align: 'right' },
            { label: 'Facturé', align: 'right', value: function (x) { return C.money(x.recette, false); },
              somme: function (x) { return x.recette; } },
            { label: 'Consommables', align: 'right', value: function (x) { return C.money(x.cout, false); },
              somme: function (x) { return x.cout; } },
            { label: 'Marge', align: 'right', value: function (x) { return C.money(x.marge, false); },
              somme: function (x) { return x.marge; } },
          ], r.lignes, { total: true }),
          signatures: [{ role: 'Le Comptable' },
            { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

})(window);
