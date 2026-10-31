/* =============================================================================
 * M9 — Assurances, Créances & Relances
 * -----------------------------------------------------------------------------
 * CDCT §10.8 — fiche assuré complète, vérification de la validité de la carte,
 * taux de prise en charge, gestion des 13 compagnies partenaires, facture
 * normalisée mensuelle par assureur, créances et relances.
 * RG-09 — la prise en charge n'est appliquée que si la carte est valide.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  function assureurs() { return S.collection('assureurs').active(); }
  function patients() { return S.collection('patients').active(); }
  function assures() { return patients().filter(function (p) { return !!p.assureur; }); }
  function factures() { return S.collection('factures').active(); }
  function facturesAssurance() { return factures().filter(function (f) { return !!f.assureur; }); }

  /* UNE SEULE VÉRITÉ : la validité se lit au moteur, qui connaît
     l’historique des couvertures. Une copie locale divergerait le jour où
     un assuré changerait de compagnie en cours d’année. */
  function carteValide(p) {
    return PR.carteValide(p, AUJ);
  }
  function assureurNom(code) {
    var a = D.ASSUREURS.filter(function (x) { return x.code === code; })[0];
    return a ? a.nom : code;
  }
  function creanceAssureur(code) {
    return C.sum(facturesAssurance().filter(function (f) { return f.assureur === code; }), 'partAssurance');
  }

  /* ==========================================================================
   * TABLEAU DE BORD ASSURANCES
   * ======================================================================== */
  global.SIGH.screen('m9-dashboard', {
    title: 'Tableau de bord — Assurances',
    description: 'Assurés, validité des cartes, prises en charge, créances par compagnie et relances.',
    render: K.dash({
      alerte: function () {
        var expirees = assures().filter(function (p) { return !carteValide(p); });
        if (!expirees.length) return null;
        return K.note('<strong>' + expirees.length + ' carte(s) d’assurance expirée(s)</strong>. '
          + 'En application de la règle RG-09, la facturation de ces patients doit être <strong>intégrale</strong> tant que la carte n’est pas renouvelée.',
          { tone: 'danger', icon: 'shield-alert' });
      },
      kpis: function () {
        var a = assures(), fa = facturesAssurance();
        return [
          { label: 'Compagnies partenaires', value: C.num(assureurs().length), icon: 'building-2', tone: 'navy', hint: 'Référentiel de la clinique' },
          { label: 'Patients assurés', value: C.num(a.length), icon: 'users', tone: 'info' },
          { label: 'Cartes valides', value: C.num(a.filter(carteValide).length), icon: 'shield-check', tone: 'success' },
          { label: 'Cartes expirées', value: C.num(a.filter(function (p) { return !carteValide(p); }).length), icon: 'shield-alert', tone: 'danger' },
          { label: 'Factures avec prise en charge', value: C.num(fa.length), icon: 'receipt', tone: 'navy' },
          { label: 'Créances assureurs', value: C.money(C.sum(fa, 'partAssurance')), icon: 'hand-coins', tone: 'warning' },
          { label: 'Montant total pris en charge', value: C.money(C.sum(fa, 'partAssurance')), icon: 'wallet', tone: 'info' },
          { label: 'Taux moyen de prise en charge', value: C.pct(a.length ? C.sum(a, 'tauxPriseEnCharge') / a.length : 0), icon: 'percent', tone: 'neutral' },
        ];
      },
      sections: [
        {
          render: function () {
            return K.charts([
              {
                title: 'Créances par compagnie',
                render: function () {
                  var data = D.ASSUREURS.map(function (a) { return { label: a.code, value: creanceAssureur(a.code) }; })
                    .filter(function (x) { return x.value > 0; })
                    .sort(function (a, b) { return b.value - a.value; });
                  return K.ranking(data, { format: function (v) { return C.money(v, false); }, tone: 'warning' });
                },
              },
              {
                title: 'Répartition des assurés par compagnie',
                render: function () {
                  var g = C.groupBy(assures(), 'assureur');
                  var keys = Object.keys(g);
                  return G.anneau(keys, keys.map(function (k) { return g[k].length; }), { legend: 'right' });
                },
              },
            ]);
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Prises en charge (12 mois)',
                render: function () {
                  var s = K.parMois(facturesAssurance(), 'date', 'partAssurance');
                  return G.barres(s.labels, [{ label: 'Part assurance', data: s.data, color: G.TONES.bleu }]);
                },
              },
              {
                title: 'Validité des cartes',
                render: function () {
                  var a = assures();
                  var valides = a.filter(carteValide).length;
                  return G.anneau(['Cartes valides', 'Cartes expirées'], [valides, a.length - valides],
                    { legend: 'bottom', colors: [G.TONES.vert, G.TONES.rouge] });
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm9-compagnies', icon: 'building-2', label: 'Compagnies', detail: 'Référentiel et conventions' },
              { id: 'm9-assures', icon: 'id-card', label: 'Assurés & cartes', detail: 'Vérification de validité' },
              { id: 'm9-factures-assureur', icon: 'file-text', label: 'Facture mensuelle', detail: 'Par assureur' },
              { id: 'm9-relances', icon: 'send', label: 'Relances', detail: 'Créances en souffrance' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * COMPAGNIES PARTENAIRES
   * ======================================================================== */
  /* L'ANCIENNETÉ D'UNE DETTE EST UNE FABRIQUE UNIQUE : la balance âgée de
     `m9-creances` et le filtre du référentiel doivent découper les mêmes
     tranches, sinon une compagnie « au-delà de 90 jours » ici ne l'est pas
     là — et c'est le genre d'écart qu'on ne voit qu'en réunion. */
  function ancienneteAssureur(code, tranche) {
    var f = facturesAssurance().filter(function (x) { return x.assureur === code; });
    return C.sum(f.filter(function (x) {
      var j = C.daysBetween(x.date, AUJ);
      if (tranche === 'moins30') return j <= 30;
      if (tranche === '30a90') return j > 30 && j <= 90;
      return j > 90;
    }), 'partAssurance');
  }

  global.SIGH.screen('m9-compagnies', {
    title: 'Compagnies d’assurance partenaires',
    description: 'Référentiel des compagnies conventionnées avec la clinique : coordonnées, convention, assurés et créances.',
    render: K.crud({
      collection: 'assureurs', entite: 'compagnie', entiteP: 'compagnies', module: 'M9',
      defaultSort: 'n', pageSize: 15, drawerWidth: 'max-w-3xl',
      source: 'Liste et contacts des assurances partenaires de la Clinique NASSIERA TOO.',
      columns: [
        { key: 'n', label: 'N°', align: 'right', nowrap: true },
        { key: 'code', label: 'Code', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: a.code }); } },
        { key: 'nom', label: 'Compagnie' },
        {
          key: 'tel', label: 'Téléphones',
          text: function (a) { return (a.tel || []).join(' / '); },
          render: function (a) {
            return el('div', null, (a.tel || []).map(function (t) {
              return el('p.font-mono.text-xs.text-slate-600', { text: t });
            }));
          },
        },
        { key: 'email', label: 'Adresse électronique', render: function (a) { return el('span.text-xs.text-slate-600', { text: a.email }); } },
        { key: 'convention', label: 'Convention', render: function (a) { return U.badge(a.convention || 'Signée', 'success'); } },
        {
          key: 'nbAssures', label: 'Assurés', align: 'right',
          value: function (a) { return assures().filter(function (p) { return p.assureur === a.code; }).length; },
          render: function (a) { return String(assures().filter(function (p) { return p.assureur === a.code; }).length); },
        },
        {
          key: 'creance', label: 'Créances', align: 'right',
          value: function (a) { return creanceAssureur(a.code); },
          text: function (a) { return C.money(creanceAssureur(a.code), false); },
          render: function (a) {
            var v = creanceAssureur(a.code);
            return v > 0 ? el('span.font-semibold.text-warning-700', { text: C.money(v, false) }) : el('span.text-xs.text-slate-400', { text: '—' });
          },
        },
      ],
      /* FILTRES AVANCÉS. Treize compagnies tiennent dans un écran ; ce qui
         ne s'y lit pas d'un coup d'œil, c'est LAQUELLE doit de l'argent
         depuis plus de trois mois, et laquelle n'a plus de convention en
         cours. Chaque filtre répond à une question posée au bureau de la
         Directrice, pas à une colonne du tableau. */
      filters: [
        { name: 'convention', label: 'Convention',
          options: ['Signée', 'En cours de renouvellement', 'Suspendue'],
          match: function (a, v) { return (a.convention || 'Signée') === v; } },
        { name: 'creanceEtat', label: 'Créances', options: [
          { value: 'avec', label: 'Avec créance ouverte' },
          { value: 'sans', label: 'Sans créance' },
          { value: 'grosse', label: 'Créance > 500 000 F' },
        ], match: function (a, v) {
          var c = creanceAssureur(a.code);
          if (v === 'avec') return c > 0;
          if (v === 'sans') return !c;
          return c > 500000;
        } },
        { name: 'anciennete', label: 'Ancienneté de la dette', options: [
          { value: 'plus90', label: 'Au-delà de 90 jours' },
          { value: '30a90', label: 'De 30 à 90 jours' },
          { value: 'moins30', label: 'Moins de 30 jours' },
        ], match: function (a, v) { return ancienneteAssureur(a.code, v) > 0; } },
        { name: 'portefeuille', label: 'Portefeuille d’assurés', options: [
          { value: 'aucun', label: 'Aucun assuré rattaché' },
          { value: 'petit', label: '1 à 9 assurés' },
          { value: 'grand', label: '10 assurés et plus' },
        ], match: function (a, v) {
          var n = assures().filter(function (x) { return x.assureur === a.code; }).length;
          if (v === 'aucun') return n === 0;
          if (v === 'petit') return n >= 1 && n <= 9;
          return n >= 10;
        } },
        { name: 'carte', label: 'Cartes des assurés', options: [
          { value: 'expiree', label: 'Au moins une carte expirée' },
          { value: 'toutes', label: 'Toutes les cartes valides' },
        ], match: function (a, v) {
          var mes = assures().filter(function (x) { return x.assureur === a.code; });
          if (!mes.length) return false;
          var expirees = mes.filter(function (x) { return !carteValide(x); }).length;
          return v === 'expiree' ? expirees > 0 : expirees === 0;
        } },
      ],
      fields: [
        { name: 'code', label: 'Code', required: true },
        { name: 'nom', label: 'Raison sociale', required: true, col: 'full' },
        { name: 'email', label: 'Adresse électronique', type: 'email' },
        { name: 'convention', label: 'État de la convention', type: 'select', options: ['Signée', 'En cours de renouvellement', 'Suspendue'] },
        { name: 'contact', label: 'Personne de contact' },
        { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
      ],
      kpis: function (rows) {
        return [
          { label: 'Compagnies partenaires', value: C.num(rows.length), icon: 'building-2', tone: 'navy' },
          { label: 'Conventions actives', value: C.num(rows.filter(function (a) { return (a.convention || 'Signée') === 'Signée'; }).length), icon: 'file-check-2', tone: 'success' },
          { label: 'Assurés couverts', value: C.num(assures().length), icon: 'users', tone: 'info' },
          { label: 'Créances totales', value: C.money(C.sum(rows, function (a) { return creanceAssureur(a.code); })), icon: 'hand-coins', tone: 'warning' },
        ];
      },
      detail: function (a) {
        var mesAssures = assures().filter(function (p) { return p.assureur === a.code; });
        var mesFactures = facturesAssurance().filter(function (f) { return f.assureur === a.code; });
        return el('div.space-y-4', null, [
          U.kpiGrid([
            { label: 'Assurés', value: C.num(mesAssures.length), icon: 'users', tone: 'navy' },
            { label: 'Créances', value: C.money(creanceAssureur(a.code)), icon: 'hand-coins', tone: 'warning' },
          ], 'grid-cols-2'),
          U.tabs([
            {
              id: 'infos', label: 'Coordonnées',
              render: function () {
                return U.descList([
                  ['Code', a.code], ['Raison sociale', a.nom],
                  ['Téléphones', (a.tel || []).join(' / ')],
                  ['Adresse électronique', a.email],
                  ['Convention', U.badge(a.convention || 'Signée', 'success')],
                  ['Personne de contact', a.contact || '—'],
                ]);
              },
            },
            {
              id: 'assures', label: 'Assurés', badge: mesAssures.length,
              render: function () {
                if (!mesAssures.length) return U.empty('Aucun assuré rattaché à cette compagnie.', { icon: 'users' });
                return K.miniTable([
                  { label: 'Dossier', render: function (p) { return el('span.font-mono.text-xs', { text: p.code }); } },
                  { label: 'Assuré', render: function (p) { return p.nom + ' ' + p.prenom; } },
                  { label: 'Police', key: 'numeroPolice' },
                  { label: 'Taux', align: 'right', render: function (p) { return p.tauxPriseEnCharge + ' %'; } },
                  { label: 'Carte', render: function (p) { return carteValide(p) ? U.badge('Valide', 'success') : U.badge('Expirée', 'danger'); } },
                ], mesAssures.slice(0, 25));
              },
            },
            {
              id: 'factures', label: 'Factures', badge: mesFactures.length,
              render: function () {
                if (!mesFactures.length) return U.empty('Aucune facture avec prise en charge.', { icon: 'receipt' });
                return K.miniTable([
                  { label: 'N°', render: function (f) { return el('span.font-mono.text-xs', { text: f.numero }); } },
                  { label: 'Date', render: function (f) { return C.dateFR(f.date); } },
                  { label: 'Patient', key: 'patient' },
                  { label: 'Total', align: 'right', render: function (f) { return C.money(f.montantTTC, false); } },
                  { label: 'Part assureur', align: 'right', render: function (f) { return C.money(f.partAssurance, false); } },
                ], C.sortBy(mesFactures, 'date', 'desc').slice(0, 25));
              },
            },
          ]),
        ]);
      },
      etat: function (a) {
        var mesAssures = assures().filter(function (p) { return p.assureur === a.code; });
        P.etat({
          titre: 'Fiche compagnie d’assurance',
          sousTitre: a.nom,
          cartouche: [['Code', a.code], ['Raison sociale', a.nom],
            ['Téléphones', (a.tel || []).join(' / ')], ['Courriel', a.email],
            ['Convention', a.convention || 'Signée'], ['Assurés', C.num(mesAssures.length)]],
          contenu: mesAssures.length
            ? P.tableau([
              { label: 'Dossier', key: 'code' },
              { label: 'Assuré', value: function (p) { return p.nom + ' ' + p.prenom; } },
              { label: 'N° police', key: 'numeroPolice' },
              { label: 'Taux', align: 'right', value: function (p) { return p.tauxPriseEnCharge + ' %'; } },
              { label: 'Expiration', value: function (p) { return C.dateFR(p.carteExpiration); } },
            ], mesAssures)
            : el('p.italic', { text: 'Aucun assuré rattaché.' }),
          signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      },
    }),
  });

  /* ==========================================================================
   * ASSURÉS & CARTES
   * ======================================================================== */
  /* ==========================================================================
   * CHANGER D’ASSUREUR SANS PERDRE CE QUI PRÉCÈDE
   * --------------------------------------------------------------------------
   * Un assuré change de compagnie d’une année à l’autre — l’employeur change
   * de convention, un particulier de contrat. Le dossier ne portait qu’un
   * ÉTAT : le mettre à jour effaçait la couverture sous laquelle les factures
   * de l’année précédente avaient été émises, et la créance de l’ancienne
   * compagnie devenait injustifiable.
   *
   * Le geste passe donc par `PR.changerCouverture` : la couverture en cours
   * est CLOSE à la veille de la date d’effet, une nouvelle est ouverte, et
   * la fiche du dossier reflète celle qui est en force AUJOURD’HUI. Motif et
   * date d’effet sont obligatoires — un changement sans motif ne se relit pas
   * (RG-12), et sans date d’effet il ne se distingue pas de l’ancien.
   * ======================================================================== */
  function champsCouverture(p) {
    return [
      { name: 'dateEffet', label: 'Date d’effet du changement', type: 'date', required: true,
        value: C.iso(AUJ), hint: 'La couverture précédente est close la veille de cette date.' },
      { name: 'motif', label: 'Motif du changement', type: 'select', required: true, col: 'full',
        options: ['Changement d’employeur', 'Changement de compagnie par l’assuré',
          'Convention non reconduite', 'Renouvellement de carte', 'Changement de police',
          'Fin de couverture — patient redevenu non assuré', 'Correction d’une saisie erronée'] },
      { type: 'section', label: 'Nouvelle couverture' },
      { name: 'assureur', label: 'Compagnie', type: 'select', col: 'full',
        value: p.assureur || '',
        options: [{ value: '', label: '— Aucune : patient non assuré —' }].concat(
          D.ASSUREURS.map(function (a) { return { value: a.code, label: a.code + ' — ' + a.nom }; })) },
      { name: 'numeroPolice', label: 'Numéro de police', value: p.numeroPolice || '' },
      { name: 'categorieAssurance', label: 'Catégorie', type: 'select',
        value: p.categorieAssurance || 'entreprise',
        options: [{ value: 'entreprise', label: 'Assurance entreprise' },
          { value: 'particulier', label: 'Assurance particulier' },
          { value: 'personnel', label: 'Assurance personnel' }] },
      { name: 'tauxPriseEnCharge', label: 'Taux de prise en charge (%)', type: 'number',
        min: 0, max: 100, value: p.tauxPriseEnCharge || 0 },
      { name: 'carteExpiration', label: 'Expiration de la nouvelle carte', type: 'date',
        value: p.carteExpiration || '' },
    ];
  }

  function majCouverture(p, apres) {
    var f = U.form(champsCouverture(p), {});
    var m = U.modal({
      title: 'Mettre à jour la couverture',
      subtitle: p.nom + ' ' + p.prenom + ' — ' + p.code,
      size: 'lg',
      body: el('div.space-y-3', null, [
        K.note('La couverture actuelle n’est pas écrasée : elle est <strong>close à la veille de la date d’effet</strong> et reste lisible sur les factures déjà émises. C’est le même mécanisme que la grille des primes et les plages par lot de réactif.', { tone: 'info', icon: 'history' }),
        f,
      ]),
      footer: [
        K.btn('Annuler', { onclick: function () { m.close(); } }),
        K.btn('Enregistrer le changement', { variant: 'primary', icon: 'save', onclick: function () {
          var v = f.collect();
          if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
          var a = D.ASSUREURS.filter(function (x) { return x.code === v.assureur; })[0];
          var res = PR.changerCouverture(p, {
            dateEffet: v.dateEffet, motif: v.motif,
            assureur: v.assureur || null, assureurNom: a ? a.nom : null,
            numeroPolice: v.numeroPolice, categorieAssurance: v.categorieAssurance,
            tauxPriseEnCharge: v.tauxPriseEnCharge, carteExpiration: v.carteExpiration,
            souscripteurId: p.souscripteurId,
          });
          if (!res.ok) { U.toast(res.motif, { type: 'error' }); return; }
          m.close();
          U.toast('Couverture mise à jour — l’historique conserve la précédente.', { type: 'success' });
          if (apres) apres();
        } }),
      ],
    });
  }

  /** L’historique, tel qu’il se relit : la période, la compagnie, le motif. */
  function tableHistorique(p) {
    var hist = PR.historiqueCouverture(p);
    if (!hist.length) {
      return K.note('Aucun changement enregistré : la couverture portée par le dossier vaut <strong>depuis son ouverture</strong>. L’historique commence au premier changement — il ne peut pas inventer une date d’effet que personne n’a saisie.', { tone: 'info', icon: 'history' });
    }
    return K.miniTable([
      { label: 'Période', render: function (c) {
        return (c.debut ? 'Depuis le ' + C.dateFR(c.debut) : 'Depuis l’ouverture du dossier')
          + (c.fin ? ' au ' + C.dateFR(c.fin) : ' — en cours');
      } },
      { label: 'Compagnie', render: function (c) {
        return c.assureur ? U.badge(c.assureurNom || c.assureur, 'navy') : U.badge('Non assuré', 'neutral');
      } },
      { label: 'Police', render: function (c) { return el('span.font-mono.text-xs', { text: c.numeroPolice || '—' }); } },
      { label: 'Taux', align: 'right', render: function (c) { return (c.tauxPriseEnCharge || 0) + ' %'; } },
      { label: 'Carte jusqu’au', render: function (c) { return c.carteExpiration ? C.dateFR(c.carteExpiration) : '—'; } },
      { label: 'Motif', key: 'motif' },
      { label: 'État', render: function (c) { return c.fin ? U.badge('Close', 'neutral') : U.badge('En cours', 'success'); } },
    ], hist);
  }

  global.SIGH.screen('m9-assures', {
    title: 'Assurés & cartes',
    description: 'Fiche assuré : compagnie, numéro de police, catégorie de carte, taux et date d’expiration.',
    regle: '<strong>RG-09</strong> — la prise en charge n’est appliquée que si la carte est <strong>valide au moment de la facturation</strong>. '
      + 'À défaut, la facturation est intégrale au patient.',
    render: function (root) {
      var rows = assures();
      var host = el('div.space-y-4');
      var expirees = rows.filter(function (p) { return !carteValide(p); });

      host.appendChild(U.kpiGrid([
        { label: 'Assurés enregistrés', value: C.num(rows.length), icon: 'id-card', tone: 'navy' },
        { label: 'Cartes valides', value: C.num(rows.length - expirees.length), icon: 'shield-check', tone: 'success' },
        { label: 'Cartes expirées', value: C.num(expirees.length), icon: 'shield-alert', tone: 'danger', hint: 'Facturation intégrale (RG-09)' },
        { label: 'Taux moyen', value: C.pct(rows.length ? C.sum(rows, 'tauxPriseEnCharge') / rows.length : 0), icon: 'percent', tone: 'info' },
      ]));

      if (expirees.length) {
        host.appendChild(K.note('<strong>' + expirees.length + ' carte(s) expirée(s)</strong> — la caisse doit facturer intégralement ces patients jusqu’au renouvellement de leur carte.', { tone: 'danger', icon: 'shield-alert' }));
      }

      host.appendChild(U.dataTable({
        title: 'Fiches assurés', rows: rows, exportName: 'assures', pageSize: 15,
        filters: [
          { name: 'assureur', label: 'Compagnie', options: D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom }; }) },
          {
            name: 'categorieAssurance', label: 'Catégorie',
            options: [{ value: 'entreprise', label: 'Assurance entreprise' },
              { value: 'particulier', label: 'Assurance particulier' },
              { value: 'personnel', label: 'Assurance personnel' }],
          },
          {
            name: 'validite', label: 'Validité de la carte',
            options: [{ value: 'valide', label: 'Cartes valides' }, { value: 'expiree', label: 'Cartes expirées' }],
            match: function (p, v) { return v === 'valide' ? carteValide(p) : !carteValide(p); },
          },
        ],
        columns: [
          { key: 'code', label: 'Dossier', nowrap: true, render: function (p) { return el('span.font-mono.text-xs', { text: p.code }); } },
          {
            key: 'nom', label: 'Bénéficiaire',
            value: function (p) { return p.nom + ' ' + p.prenom; },
            render: function (p) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: p.nom + ' ' + p.prenom }),
                el('p.text-xs.text-slate-400', { text: (p.sexe === 'F' ? 'Femme' : 'Homme') + ' — né(e) le ' + C.dateFR(p.dateNaissance) }),
              ]);
            },
          },
          {
            key: 'assureur', label: 'Compagnie',
            text: function (p) { return p.assureurNom || assureurNom(p.assureur); },
            render: function (p) { return U.badge(p.assureur, 'navy'); },
          },
          {
            /* Le niveau que les pièces réelles imposent : c'est le contrat de
               l'employeur, sous la compagnie, qui porte la grille. */
            key: 'souscripteur', label: 'Souscripteur',
            text: function (p) { return p.souscripteur || ''; },
            render: function (p) {
              if (!p.souscripteur) return el('span.text-xs.text-warning-600', { text: 'non rattaché' });
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.text-slate-700', { text: p.souscripteur }),
                el('p.font-mono.text-xs.text-slate-400', { text: p.numeroPolice || '' }),
              ]);
            },
          },
          {
            key: 'categorieAssurance', label: 'Catégorie',
            text: function (p) { return p.categorieAssurance || ''; },
            render: function (p) {
              var m = { entreprise: ['Entreprise', 'info'], particulier: ['Particulier', 'neutral'], personnel: ['Personnel', 'success'] };
              var x = m[p.categorieAssurance];
              return x ? U.badge(x[0], x[1]) : el('span.text-xs.text-slate-300', { text: '—' });
            },
          },
          { key: 'numeroPolice', label: 'N° police', nowrap: true, render: function (p) { return el('span.font-mono.text-xs', { text: p.numeroPolice }); } },
          {
            key: 'tauxPriseEnCharge', label: 'Taux', align: 'right',
            render: function (p) { return el('span.font-semibold', { text: p.tauxPriseEnCharge + ' %' }); },
          },
          {
            key: 'carteExpiration', label: 'Expiration', nowrap: true,
            text: function (p) { return C.dateFR(p.carteExpiration); },
            render: function (p) { return C.dateFR(p.carteExpiration); },
          },
          {
            key: 'validite', label: 'Validité (RG-09)',
            value: function (p) { return carteValide(p) ? 'valide' : 'expiree'; },
            text: function (p) { return carteValide(p) ? 'Valide' : 'Expirée'; },
            render: function (p) {
              if (!carteValide(p)) return U.badge('Expirée', 'danger');
              var j = C.daysBetween(AUJ, p.carteExpiration);
              return j <= 30 ? U.badge('Expire dans ' + j + ' j', 'warning') : U.badge('Valide', 'success');
            },
          },
        ],
        onRowClick: function (p) { verifier(p); },
        rowActions: function (p) {
          return [
            K.btn('Vérifier la carte', { size: 'sm', icon: 'scan-line', onclick: function () { verifier(p); } }),
            /* Une commande d’ÉCRITURE se déclare comme telle : refusée, elle est
               ABSENTE et non grisée (doctrine de la vague 37). */
            K.commandeIcone('id-card', 'Mettre à jour la couverture', function () {
              majCouverture(p, function () { global.location.reload(); });
            }, { moduleCode: 'M9' }),
            K.iconBtn('printer', 'Attestation de prise en charge', function () { attestation(p); }),
          ];
        },
      }));
      root.appendChild(host);
      return null;

      function verifier(p) {
        var valide = carteValide(p);
        var body = el('div.space-y-4');
        body.appendChild(el('div.flex.items-center.gap-3.rounded-lg.p-4', {
          class: valide ? 'bg-success-50 border border-success-200' : 'bg-danger-50 border border-danger-200',
        }, [
          el('span.grid.h-12.w-12.shrink-0.place-items-center.rounded-full', {
            class: valide ? 'bg-success-100 text-success-700' : 'bg-danger-100 text-danger-700',
          }, C.icon(valide ? 'shield-check' : 'shield-x', 'h-6 w-6')),
          el('div', null, [
            el('p.text-sm.font-semibold', { class: valide ? 'text-success-900' : 'text-danger-900', text: valide ? 'Carte valide — prise en charge applicable' : 'Carte expirée — prise en charge refusée' }),
            el('p.text-xs', { class: valide ? 'text-success-700' : 'text-danger-700',
              text: valide ? 'Taux applicable : ' + p.tauxPriseEnCharge + ' % — expire le ' + C.dateFR(p.carteExpiration)
                : 'Expirée depuis le ' + C.dateFR(p.carteExpiration) + '. Facturation intégrale au patient (RG-09).' }),
          ]),
        ]));
        body.appendChild(U.descList([
          ['Bénéficiaire', p.nom + ' ' + p.prenom],
          ['Dossier', el('span.font-mono', { text: p.code })],
          ['Date de naissance', p.dateNaissance ? C.dateFR(p.dateNaissance) : 'Inconnue — ' + C.ageTexte(p)],
          ['Sexe', p.sexe === 'F' ? 'Féminin' : 'Masculin'],
          ['Compagnie', p.assureurNom || assureurNom(p.assureur)],
          ['Numéro de police', p.numeroPolice],
          ['Taux de prise en charge', p.tauxPriseEnCharge + ' %'],
          ['Date d’expiration', C.dateFR(p.carteExpiration)],
        ]));
        body.appendChild(U.card('Historique des couvertures', tableHistorique(p)));
        var mesF = facturesAssurance().filter(function (f) { return f.patientId === p.id; });
        if (mesF.length) {
          body.appendChild(U.card('Prises en charge accordées', K.miniTable([
            { label: 'Facture', render: function (f) { return el('span.font-mono.text-xs', { text: f.numero }); } },
            { label: 'Date', render: function (f) { return C.dateFR(f.date); } },
            { label: 'Total', align: 'right', render: function (f) { return C.money(f.montantTTC, false); } },
            { label: 'Part assureur', align: 'right', render: function (f) { return C.money(f.partAssurance, false); } },
          ], C.sortBy(mesF, 'date', 'desc').slice(0, 10))));
        }
        U.drawer({
          title: 'Vérification de carte', subtitle: p.nom + ' ' + p.prenom + ' — ' + p.assureur,
          body: body, width: 'max-w-2xl',
          footer: [
            K.commande('Mettre à jour la couverture', { icon: 'id-card', moduleCode: 'M9',
              onclick: function () { majCouverture(p, function () { global.location.reload(); }); } }),
            K.btn('Attestation', { variant: 'primary', icon: 'printer', onclick: function () { attestation(p); } })],
        });
      }

      function attestation(p) {
        P.etat({
          titre: 'Attestation de prise en charge',
          sousTitre: p.assureurNom || assureurNom(p.assureur),
          cartouche: [['Bénéficiaire', p.nom + ' ' + p.prenom], ['Dossier', p.code],
            ['Âge', C.ageTexte(p)], ['Compagnie', p.assureurNom || assureurNom(p.assureur)],
            ['N° police', p.numeroPolice], ['Taux', p.tauxPriseEnCharge + ' %']],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Compagnie d’assurance', v: p.assureurNom || assureurNom(p.assureur) },
              { k: 'Numéro de police', v: p.numeroPolice },
              { k: 'Taux de prise en charge', v: p.tauxPriseEnCharge + ' %' },
              { k: 'Date d’expiration de la carte', v: C.dateFR(p.carteExpiration) },
              { k: 'Validité au ' + C.dateFR(AUJ), v: carteValide(p) ? 'CARTE VALIDE' : 'CARTE EXPIRÉE' },
            ]),
            el('p.mt-3.text-\\[10px\\].italic', {
              text: carteValide(p)
                ? 'La prise en charge est appliquée au taux ci-dessus pour les prestations réalisées jusqu’à la date d’expiration de la carte.'
                : 'La carte étant expirée, aucune prise en charge ne peut être appliquée : la facturation est intégrale au patient (règle RG-09).',
            }),
          ]),
          signatures: [{ role: 'Le Caissier' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * PRISES EN CHARGE
   * ======================================================================== */
  /* ==========================================================================
   * CONVENTIONS & GARANTIES
   * --------------------------------------------------------------------------
   * Le cahier de charge du 30/12/2024 : « appliquer des pourcentages par article
   * et par prestation », le taux variant « d'une assurance à l'autre et, pour un
   * même assuré, selon la nature de l'article ». Un taux unique par patient ne
   * peut pas exprimer cela — c'est pourtant tout ce que le prototype savait
   * faire jusqu'ici.
   *
   * Trois niveaux, tels que les pièces réelles les montrent :
   *   compagnie  →  souscripteur (n° de police)  →  assuré
   * et c'est le SOUSCRIPTEUR qui porte la grille : le barème versé au dossier
   * est celui d'un employeur, pas d'une compagnie.
   * ======================================================================== */
  function colSous() { return S.collection('souscripteurs', { module: 'M9', entite: 'souscripteur', prefix: 'SOU' }); }
  function colGaranties() { return S.collection('garanties', { module: 'M9', entite: 'garantie', prefix: 'GAR' }); }

  function souscripteurs() { return colSous().active(); }
  function assuresDe(sousId) {
    return S.collection('patients').active().filter(function (p) { return p.souscripteurId === sousId; });
  }
  function garantiesDuSouscripteur(sousId) {
    return colGaranties().active().filter(function (g) { return g.souscripteurId === sousId; });
  }
  function libelleCategorie(id) {
    var c = D.CATEGORIES_GARANTIE.filter(function (x) { return x.id === id; })[0];
    return c ? c.label : id;
  }

  global.SIGH.screen('m9-conventions', {
    title: 'Conventions & garanties',
    description: 'Grille de prise en charge par souscripteur : taux et plafonds par catégorie, exclusions et accords préalables.',
    regle: 'Le taux de couverture <strong>n’est pas unique par patient</strong> : il varie d’une convention à l’autre '
      + 'et, pour un même assuré, selon la nature de la prestation. Tant qu’une convention n’est pas saisie, '
      + 'la facturation reste <strong>intégralement à la charge du patient</strong> — et l’écran le dit. '
      + '<strong>RG-09</strong> — la prise en charge ne s’applique que si la carte est valide à la date de facturation.',
    actions: function () {
      return [
        K.btn('Assurés & cartes', { icon: 'id-card', onclick: function () { global.SIGH.app.go('m9-assures'); } }),
        K.btn('Compagnies', { icon: 'building-2', onclick: function () { global.SIGH.app.go('m9-compagnies'); } }),
        K.btn('Prises en charge', { icon: 'shield-check', onclick: function () { global.SIGH.app.go('m9-prises-en-charge'); } }),
      ];
    },
    render: function (root) {
      var host = el('div.space-y-4');
      var sous = souscripteurs();
      var avecGrille = sous.filter(function (s) { return garantiesDuSouscripteur(s.id).length > 0; });

      host.appendChild(U.kpiGrid([
        { label: 'Souscripteurs', value: C.num(sous.length), icon: 'file-signature', tone: 'navy', hint: 'Contrats sous ' + D.ASSUREURS.length + ' compagnies' },
        { label: 'Conventions saisies', value: C.num(avecGrille.length), icon: 'check-circle-2', tone: avecGrille.length ? 'success' : 'warning' },
        { label: 'Conventions à collecter', value: C.num(sous.length - avecGrille.length), icon: 'help-circle', tone: 'warning' },
        { label: 'Lignes de garantie', value: C.num(colGaranties().active().length), icon: 'percent', tone: 'info' },
      ]));

      if (sous.length - avecGrille.length > 0) {
        host.appendChild(K.note('<strong>' + (sous.length - avecGrille.length) + ' convention(s) non saisie(s).</strong> '
          + 'Un seul barème figure au dossier — celui d’un régime employeur, versé le 18/06/2026 — et il ne vaut que '
          + 'pour son souscripteur. Les grilles des autres compagnies restent à collecter. En attendant, leurs assurés '
          + 'sont facturés intégralement : mieux vaut une facture juste qu’une prise en charge supposée.',
        { tone: 'warning', icon: 'help-circle' }));
      }

      host.appendChild(U.tabs([
        { id: 'souscripteurs', label: 'Souscripteurs', badge: sous.length, render: ongletSouscripteurs },
        { id: 'garanties', label: 'Grilles de garanties', badge: colGaranties().active().length, render: ongletGaranties },
        { id: 'simulateur', label: 'Simulateur de répartition', render: ongletSimulateur },
      ]));

      root.appendChild(host);
      return null;
    },
  });

  /* --- Souscripteurs -------------------------------------------------------- */
  function champsSouscripteur() {
    return [
      { name: 'nom', label: 'Souscripteur', required: true, col: 'full', help: 'Employeur, groupe ou particulier signataire du contrat.' },
      {
        name: 'assureur', label: 'Compagnie', type: 'select', required: true,
        options: D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom }; }),
      },
      { name: 'police', label: 'N° de police', required: true },
      {
        name: 'categorie', label: 'Catégorie', type: 'select', required: true,
        options: [{ value: 'entreprise', label: 'Assurance entreprise' },
          { value: 'particulier', label: 'Assurance particulier' },
          { value: 'personnel', label: 'Assurance personnel de la clinique' }],
      },
      { name: 'effectif', label: 'Bénéficiaires déclarés', type: 'number', min: 0 },
      { name: 'contact', label: 'Interlocuteur', col: 'full' },
      { name: 'dateDebut', label: 'Début de validité', type: 'date' },
      { name: 'dateFin', label: 'Fin de validité', type: 'date', help: 'Laisser vide si la convention est en cours.' },
    ];
  }

  function ongletSouscripteurs(panneau) {
    dessiner();
    return null;

    function dessiner() {
      C.clear(panneau);
      var rows = souscripteurs();
      panneau.appendChild(U.dataTable({
        rows: rows, exportName: 'souscripteurs', pageSize: 15, searchable: true, defaultSort: 'nom',
        filters: [
          {
            name: 'categorie', label: 'Catégorie',
            options: [{ value: 'entreprise', label: 'Entreprise' }, { value: 'particulier', label: 'Particulier' },
              { value: 'personnel', label: 'Personnel de la clinique' }],
          },
          {
            name: 'grille', label: 'Convention',
            options: [{ value: 'oui', label: 'Saisie' }, { value: 'non', label: 'À collecter' }],
            match: function (r, v) {
              var a = garantiesDuSouscripteur(r.id).length > 0;
              return v === 'oui' ? a : !a;
            },
          },
        ],
        columns: [
          {
            key: 'nom', label: 'Souscripteur',
            render: function (s) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: s.nom }),
                el('p.font-mono.text-xs.text-slate-400', { text: s.police }),
              ]);
            },
          },
          { key: 'assureurNom', label: 'Compagnie', render: function (s) { return U.badge(s.assureur, 'navy'); } },
          {
            key: 'categorie', label: 'Catégorie',
            render: function (s) {
              var m = { entreprise: ['Entreprise', 'info'], particulier: ['Particulier', 'neutral'], personnel: ['Personnel', 'success'] };
              var x = m[s.categorie] || m.particulier;
              return U.badge(x[0], x[1]);
            },
          },
          {
            key: 'assures', label: 'Assurés', align: 'right',
            value: function (s) { return assuresDe(s.id).length; },
            render: function (s) { return String(assuresDe(s.id).length); },
          },
          {
            key: 'grille', label: 'Convention',
            value: function (s) { return garantiesDuSouscripteur(s.id).length; },
            render: function (s) {
              var n = garantiesDuSouscripteur(s.id).length;
              return n ? U.badge(n + ' garanties', 'success') : U.badge('À collecter', 'warning');
            },
          },
        ],
        onRowClick: fiche,
        rowActions: function (s) {
          return [
            K.iconBtn('percent', 'Saisir la grille', function () { fiche(s); }),
            K.iconBtn('pencil', 'Modifier', function () { K.modifier(colSous(), champsSouscripteur, s, dessiner); }),
          ];
        },
        actions: [K.creer(colSous(), champsSouscripteur, {
          titre: 'Nouveau souscripteur', entite: 'Souscripteur',
          defauts: function () { return { categorie: 'entreprise', assureur: D.ASSUREURS[0].code }; },
          transform: function (v) {
            var a = D.ASSUREURS.filter(function (x) { return x.code === v.assureur; })[0];
            v.assureurNom = a ? a.nom : v.assureur;
            v.actesExclus = []; v.produitsExclus = []; v.accordPrealable = [];
            v.source = 'Convention saisie par la clinique';
            return v;
          },
          apres: dessiner,
        })],
      }));
      U.icons(panneau);
    }

    /* La fiche d'un souscripteur : sa grille, ses exclusions, ses accords. */
    function fiche(s) {
      var corps = el('div.space-y-4');
      corps.appendChild(U.descList([
        ['Compagnie', s.assureurNom], ['N° de police', s.police],
        ['Catégorie', s.categorie], ['Bénéficiaires déclarés', s.effectif != null ? C.num(s.effectif) : '—'],
        ['Assurés rattachés', C.num(assuresDe(s.id).length)],
        ['Interlocuteur', s.contact || '—'],
        ['Validité', C.dateFR(s.dateDebut) + (s.dateFin ? ' → ' + C.dateFR(s.dateFin) : ' → en cours')],
      ]));

      var g = garantiesDuSouscripteur(s.id);
      if (g.length) {
        corps.appendChild(U.card('Grille de garanties', K.miniTable([
          { label: 'Garantie', key: 'libelle' },
          { label: 'Catégorie', render: function (x) { return libelleCategorie(x.categorie); } },
          { label: 'Taux', align: 'right', render: function (x) { return x.taux + ' %'; } },
          {
            label: 'Plafond', align: 'right',
            render: function (x) {
              return x.plafond == null ? '—' : C.money(x.plafond, false) + ' ' + PR.libelleUnite(x.unitePlafond);
            },
          },
        ], g)));
      } else {
        corps.appendChild(U.card('Grille de garanties', el('div.space-y-3', null, [
          U.empty('Convention non saisie — les assurés de ce souscripteur sont facturés intégralement.', { icon: 'file-question' }),
          K.btn('Saisir la grille depuis le barème de référence', {
            variant: 'primary', icon: 'file-plus',
            onclick: function () { proposerBareme(s); },
          }),
        ])));
      }

      corps.appendChild(U.card('Exclusions et accords préalables', el('div.space-y-3', null, [
        blocListe('Actes exclus', s.actesExclus, 'ban'),
        blocListe('Produits exclus', s.produitsExclus, 'package-x'),
        blocListe('Soumis à accord préalable', s.accordPrealable, 'shield-question'),
      ]), [
        K.btn('Modifier', { size: 'sm', icon: 'pencil', onclick: function () { editerExclusions(s); } }),
      ]));

      U.drawer({
        title: s.nom, subtitle: s.assureurNom + ' — ' + s.police, width: 'max-w-3xl', body: corps,
        footer: [
          K.btn('Modifier la grille', { icon: 'percent', onclick: function () { editerGrille(s); } }),
          K.btn('Imprimer la convention', { variant: 'primary', icon: 'printer', onclick: function () { imprimer(s); } }),
        ],
      });
    }

    function blocListe(titre, liste, icone) {
      var d = el('div');
      d.appendChild(el('p.mb-1.text-xs.font-semibold.uppercase.tracking-wide.text-slate-500', { text: titre }));
      if (!liste || !liste.length) {
        d.appendChild(el('p.text-xs.text-slate-400', { text: 'Aucune — tout est couvert dans cette catégorie.' }));
        return d;
      }
      d.appendChild(el('div.flex.flex-wrap.gap-1', null, liste.map(function (x) {
        return el('span.inline-flex.items-center.gap-1.rounded-lg.border.border-slate-200.bg-slate-50.px-2.py-1.text-xs.text-slate-600', null, [
          C.icon(icone, 'h-3 w-3'), x,
        ]);
      })));
      return d;
    }

    /* Le barème versé au dossier sert de MODÈLE : on le propose, on ne l'impose
       pas. La clinique ajuste chaque taux avant d'enregistrer. */
    function proposerBareme(s) {
      var lignes = D.BAREME_REFERENCE.garanties.map(function (g) { return Object.assign({}, g); });
      var champs = [];
      lignes.forEach(function (g, i) {
        champs.push({ name: 'taux_' + i, label: g.libelle + ' — taux (%)', type: 'number', min: 0, max: 100, value: g.taux });
        champs.push({ name: 'plafond_' + i, label: 'Plafond (FCFA)', type: 'money', min: 0, value: g.plafond });
      });
      var f = U.form(champs, {});
      var corps = el('div.space-y-3', null, [
        K.note('Barème proposé d’après <strong>' + D.BAREME_REFERENCE.reference + '</strong> ('
          + D.BAREME_REFERENCE.lieu + ', ' + C.dateFR(D.BAREME_REFERENCE.date) + '). '
          + 'Ce document est celui d’un régime employeur : il donne la structure, pas les taux de cette convention. '
          + 'Ajuster avant d’enregistrer.', { tone: 'warning', icon: 'help-circle' }),
        f,
      ]);
      var m = U.modal({
        title: 'Saisir la grille de ' + s.nom, size: 'xl', body: corps,
        footer: [
          K.btn('Annuler', { onclick: function () { m.close(); } }),
          K.btn('Enregistrer la convention', {
            variant: 'primary', icon: 'save',
            onclick: function () {
              var v = f.collect();
              if (!v) return;
              lignes.forEach(function (g, i) {
                colGaranties().insert({
                  souscripteurId: s.id, assureur: s.assureur,
                  code: g.code, libelle: g.libelle, categorie: g.categorie,
                  taux: Number(v['taux_' + i]) || 0,
                  plafond: v['plafond_' + i] === '' || v['plafond_' + i] == null ? null : Number(v['plafond_' + i]),
                  unitePlafond: g.unitePlafond, zone: g.zone,
                  source: D.BAREME_REFERENCE.reference + ' — ajusté par la clinique',
                });
              });
              colSous().update(s.id, {
                grilleSaisie: true,
                actesExclus: D.BAREME_REFERENCE.actesExclus.slice(),
                produitsExclus: D.BAREME_REFERENCE.produitsExclus.slice(),
                accordPrealable: D.BAREME_REFERENCE.accordPrealable.slice(),
              });
              m.close();
              U.toast('Convention de ' + s.nom + ' enregistrée.', {
                type: 'success', detail: lignes.length + ' garanties, exclusions et accords préalables repris.',
              });
              dessiner();
            },
          }),
        ],
      });
    }

    function editerGrille(s) {
      var g = garantiesDuSouscripteur(s.id);
      if (!g.length) { proposerBareme(s); return; }
      var champs = [];
      g.forEach(function (x, i) {
        champs.push({ name: 'taux_' + i, label: x.libelle + ' — taux (%)', type: 'number', min: 0, max: 100, value: x.taux });
        champs.push({ name: 'plafond_' + i, label: 'Plafond (FCFA)', type: 'money', min: 0, value: x.plafond });
      });
      var f = U.form(champs, {});
      var m = U.modal({
        title: 'Grille de ' + s.nom, size: 'xl', body: f,
        footer: [
          K.btn('Annuler', { onclick: function () { m.close(); } }),
          K.btn('Enregistrer', {
            variant: 'primary', icon: 'save',
            onclick: function () {
              var v = f.collect();
              if (!v) return;
              g.forEach(function (x, i) {
                colGaranties().update(x.id, {
                  taux: Number(v['taux_' + i]) || 0,
                  plafond: v['plafond_' + i] === '' || v['plafond_' + i] == null ? null : Number(v['plafond_' + i]),
                });
              });
              m.close();
              U.toast('Grille mise à jour.', { type: 'success' });
              dessiner();
            },
          }),
        ],
      });
    }

    function editerExclusions(s) {
      var f = U.form([
        {
          name: 'actesExclus', label: 'Actes exclus', type: 'multiselect', col: 'full',
          options: D.BAREME_REFERENCE.actesExclus.concat(
            S.collection('actes').active().map(function (a) { return a.libelle; })),
          value: s.actesExclus || [],
        },
        {
          name: 'produitsExclus', label: 'Produits exclus', type: 'multiselect', col: 'full',
          options: D.BAREME_REFERENCE.produitsExclus,
          value: s.produitsExclus || [],
        },
        {
          name: 'accordPrealable', label: 'Soumis à accord préalable', type: 'multiselect', col: 'full',
          options: D.BAREME_REFERENCE.accordPrealable,
          value: s.accordPrealable || [],
        },
      ], {});
      var m = U.modal({
        title: 'Exclusions et accords — ' + s.nom, size: 'lg',
        body: el('div.space-y-3', null, [
          K.note('Une ligne exclue est facturée <strong>intégralement au patient</strong>, avec son motif. '
            + 'Un acte soumis à accord préalable l’est aussi tant que l’accord n’est pas obtenu.', { tone: 'info' }),
          f,
        ]),
        footer: [
          K.btn('Annuler', { onclick: function () { m.close(); } }),
          K.btn('Enregistrer', {
            variant: 'primary', icon: 'save',
            onclick: function () {
              var v = f.collect();
              if (!v) return;
              colSous().update(s.id, v);
              m.close();
              U.toast('Exclusions et accords enregistrés.', { type: 'success' });
              dessiner();
            },
          }),
        ],
      });
    }

    function imprimer(s) {
      var g = garantiesDuSouscripteur(s.id);
      P.etat({
        titre: 'Convention de prise en charge',
        sousTitre: s.nom + ' — ' + s.assureurNom,
        cartouche: [['Compagnie', s.assureurNom], ['N° de police', s.police],
          ['Catégorie', s.categorie], ['Assurés rattachés', C.num(assuresDe(s.id).length)],
          ['Validité', C.dateFR(s.dateDebut) + (s.dateFin ? ' → ' + C.dateFR(s.dateFin) : ' → en cours')],
          ['Date d’édition', C.dateFR(AUJ)]],
        contenu: g.length ? P.tableau([
          { label: 'Garantie', key: 'libelle' },
          { label: 'Catégorie', value: function (x) { return libelleCategorie(x.categorie); } },
          { label: 'Taux', align: 'right', value: function (x) { return x.taux + ' %'; } },
          { label: 'Plafond', align: 'right', value: function (x) { return x.plafond == null ? '—' : C.money(x.plafond, false); } },
          { label: 'Unité', value: function (x) { return x.plafond == null ? '—' : PR.libelleUnite(x.unitePlafond); } },
        ], g) : null,
        signatures: [{ role: 'Pour la clinique', nom: 'La Directrice Administrative' },
          { role: 'Pour le souscripteur', nom: s.contact || '' }],
      });
    }
  }

  /* --- Grilles de garanties, toutes conventions confondues ------------------ */
  function ongletGaranties(panneau) {
    var rows = colGaranties().active().map(function (g) {
      var s = colSous().get(g.souscripteurId);
      return Object.assign({}, g, { souscripteur: s ? s.nom : '—', compagnie: s ? s.assureurNom : g.assureur });
    });
    if (!rows.length) {
      panneau.appendChild(U.empty('Aucune convention saisie. Ouvrir un souscripteur pour saisir sa grille.', { icon: 'percent' }));
      U.icons(panneau);
      return null;
    }
    panneau.appendChild(U.dataTable({
      rows: rows, exportName: 'garanties', pageSize: 20, searchable: true, defaultSort: 'souscripteur',
      filters: [
        { name: 'souscripteur', label: 'Souscripteur', options: Object.keys(C.groupBy(rows, 'souscripteur')).sort() },
        {
          name: 'categorie', label: 'Catégorie',
          options: D.CATEGORIES_GARANTIE.map(function (c) { return { value: c.id, label: c.label }; }),
        },
      ],
      columns: [
        { key: 'souscripteur', label: 'Souscripteur' },
        { key: 'compagnie', label: 'Compagnie', render: function (g) { return U.badge(g.compagnie, 'navy'); } },
        { key: 'libelle', label: 'Garantie' },
        { key: 'categorie', label: 'Catégorie', text: libelleCategorie, render: function (g) { return libelleCategorie(g.categorie); } },
        {
          key: 'taux', label: 'Taux', align: 'right',
          render: function (g) { return el('span.font-semibold', { text: g.taux + ' %' }); },
        },
        {
          key: 'plafond', label: 'Plafond', align: 'right',
          text: function (g) { return g.plafond == null ? '' : String(g.plafond); },
          render: function (g) {
            return g.plafond == null
              ? el('span.text-xs.text-slate-300', { text: 'sans plafond' })
              : el('span', { text: C.money(g.plafond, false) + ' ' + PR.libelleUnite(g.unitePlafond) });
          },
        },
      ],
    }));
    U.icons(panneau);
    return null;
  }

  /* --- Simulateur ---------------------------------------------------------- */
  function ongletSimulateur(panneau) {
    var assures = S.collection('patients').active().filter(function (p) { return !!p.assureur; });
    var resultat = el('div');

    var selPatient = U.combo(C.sortBy(assures, 'nom').map(function (p) {
      return { value: p.id, label: p.nom + ' ' + p.prenom, detail: p.code + ' — ' + (p.souscripteur || p.assureurNom) };
    }), { placeholder: '— Assuré —' });

    var lignes = [
      { libelle: 'Consultation généraliste', categorie: 'consultation', montant: 5000 },
      { libelle: 'NFS complète', categorie: 'analyse', montant: 4000 },
      { libelle: 'Artésunate 60 mg injectable', categorie: 'medicament', montant: 1100 },
      { libelle: 'Vitamine C 500 mg', categorie: 'vitamine', montant: 500 },
      { libelle: 'Journée d’hospitalisation', categorie: 'hospitalisation', montant: 25000 },
    ];

    var f = U.form(lignes.map(function (l, i) {
      return { name: 'm' + i, label: l.libelle + ' (FCFA)', type: 'money', min: 0, value: l.montant };
    }), {});

    panneau.appendChild(el('div.space-y-4', null, [
      K.note('Le simulateur applique la <strong>convention réelle</strong> de l’assuré choisi, ligne par ligne, '
        + 'avec ses taux, ses plafonds, ses exclusions et la validité de sa carte. C’est exactement le calcul '
        + 'que la facturation appliquera.', { tone: 'info' }),
      U.card('Assuré', el('div.space-y-3', null, [selPatient])),
      U.card('Lignes à simuler', f),
      resultat,
    ]));

    selPatient.addEventListener('change', simuler);
    f.addEventListener('change', simuler);
    f.addEventListener('input', C.debounce(simuler, 250));
    if (assures.length) { selPatient.value = assures[0].id; simuler(); }
    U.icons(panneau);
    return null;

    function simuler() {
      C.clear(resultat);
      var p = S.collection('patients').get(selPatient.value);
      if (!p) return;
      var v = {};
      lignes.forEach(function (l, i) { v[i] = Number(f.controls['m' + i].value) || 0; });
      var r = PR.repartir(p, lignes.map(function (l, i) {
        return { libelle: l.libelle, categorie: l.categorie, montant: v[i] };
      }));

      var entete = U.descList([
        ['Assuré', p.nom + ' ' + p.prenom + ' (' + p.code + ')'],
        ['Compagnie', p.assureurNom || '—'],
        ['Souscripteur', r.souscripteur ? r.souscripteur.nom + ' — ' + r.souscripteur.police : 'non rattaché'],
        ['Carte', r.carteValide
          ? 'valide jusqu’au ' + C.dateFR(p.carteExpiration)
          : 'NON VALIDE — expirée le ' + C.dateFR(p.carteExpiration)],
        ['Convention', r.grilleSaisie ? 'saisie' : 'à collecter'],
      ]);

      resultat.appendChild(U.card('Répartition ligne par ligne', el('div.space-y-3', null, [
        entete,
        K.miniTable([
          { label: 'Prestation', key: 'libelle' },
          { label: 'Montant', align: 'right', render: function (l) { return C.money(l.montant, false); } },
          { label: 'Part assureur', align: 'right', render: function (l) { return C.money(l.partAssureur, false); } },
          { label: 'Part patient', align: 'right', render: function (l) { return C.money(l.partPatient, false); } },
          {
            label: 'Motif',
            render: function (l) {
              return el('span.text-xs', {
                class: l.partAssureur ? 'text-slate-500' : 'text-warning-700', text: l.motif,
              });
            },
          },
        ], r.lignes),
        el('div.flex.flex-wrap.justify-end.gap-6.border-t.border-slate-200.pt-3', null, [
          bloc('Total', C.money(r.total), 'text-slate-800'),
          bloc('Part assureur', C.money(r.partAssureur), 'text-info-600'),
          bloc('Part patient', C.money(r.partPatient), 'text-navy-900'),
        ]),
      ])));
      U.icons(resultat);
    }

    function bloc(libelle, valeur, classe) {
      return el('div.text-right', null, [
        el('p.text-xs.text-slate-500', { text: libelle }),
        el('p.text-base.font-semibold', { class: classe, text: valeur }),
      ]);
    }
  }

  global.SIGH.screen('m9-prises-en-charge', {
    title: 'Prises en charge',
    description: 'Factures comportant une part assurance, avec répartition entre le patient et le tiers payeur.',
    render: function (root) {
      var rows = facturesAssurance();
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Prises en charge', value: C.num(rows.length), icon: 'shield-check', tone: 'navy' },
        { label: 'Montant total facturé', value: C.money(C.sum(rows, 'montantTTC')), icon: 'receipt', tone: 'info' },
        { label: 'Part assureurs', value: C.money(C.sum(rows, 'partAssurance')), icon: 'building-2', tone: 'warning' },
        { label: 'Part patients', value: C.money(C.sum(rows, 'partPatient')), icon: 'users', tone: 'success' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Factures avec prise en charge', rows: rows, exportName: 'prises-en-charge', pageSize: 15,
        rowActions: K.actionsLigne(S.collection('factures', { module: 'M8', entite: 'Facture' }), [
          {
            name: 'assureur', label: 'Compagnie', type: 'select',
            options: D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom }; }),
          },
          { name: 'tauxPriseEnCharge', label: 'Taux de prise en charge (%)', type: 'number', min: 0, max: 100 },
          { name: 'partAssurance', label: 'Part assurance (FCFA)', type: 'number', min: 0 },
          { name: 'partPatient', label: 'Part patient (FCFA)', type: 'number', min: 0 },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ], { archivable: false }),
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'assureur', label: 'Compagnie', options: D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom }; }) },
          {
            name: 'niveau', label: 'Niveau de prise en charge',
            options: [{ value: 'totale', label: 'Totale (100 %)' }, { value: 'partielle', label: 'Partielle' }],
            match: function (f, v) { return v === 'totale' ? f.tauxPriseEnCharge === 100 : f.tauxPriseEnCharge < 100; },
          },
        ],
        columns: [
          { key: 'numero', label: 'N° facture', nowrap: true, render: function (f) { return el('span.font-mono.text-xs', { text: f.numero }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (f) { return C.dateFR(f.date); }, render: function (f) { return C.dateFR(f.date); } },
          { key: 'patient', label: 'Assuré' },
          { key: 'assureur', label: 'Compagnie', render: function (f) { return U.badge(f.assureur, 'navy'); } },
          {
            key: 'tauxPriseEnCharge', label: 'Taux', align: 'right',
            render: function (f) { return U.badge(f.tauxPriseEnCharge + ' %', f.tauxPriseEnCharge === 100 ? 'success' : 'info'); },
          },
          { key: 'montantTTC', label: 'Total', align: 'right', text: function (f) { return C.money(f.montantTTC, false); }, render: function (f) { return C.money(f.montantTTC, false); } },
          {
            key: 'partAssurance', label: 'Part assureur', align: 'right',
            text: function (f) { return C.money(f.partAssurance, false); },
            render: function (f) { return el('span.font-semibold.text-warning-700', { text: C.money(f.partAssurance, false) }); },
          },
          {
            key: 'partPatient', label: 'Part patient', align: 'right',
            text: function (f) { return C.money(f.partPatient, false); },
            render: function (f) { return C.money(f.partPatient, false); },
          },
          { key: 'statutPaiement', label: 'Règlement patient', render: function (f) { return U.statut(f.statutPaiement); } },
        ],
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * FACTURE MENSUELLE PAR ASSUREUR
   * ======================================================================== */
  /* ==========================================================================
   * RELEVÉ DES PRESTATIONS ET FACTURE MENSUELLE
   * --------------------------------------------------------------------------
   * Les deux pièces que la clinique émet réellement chaque mois, et qui vont
   * ensemble : le RELEVÉ détaille, souscripteur par souscripteur, ce qu'a
   * consommé chaque patient ; la FACTURE MENSUELLE récapitule par souscripteur
   * et sert de demande de règlement à la compagnie.
   *
   * Structure relevée sur les pièces de juillet 2026 : colonnes consultations
   * (date et montant), analyses, soins, total, part assurée, part assureur.
   * Les deux documents étant deux vues du même mois, l'écran vérifie qu'ils se
   * recoupent — c'est le contrôle qui a validé l'audit des pièces réelles.
   * ======================================================================== */
  global.SIGH.screen('m9-factures-assureur', {
    title: 'Relevé & facture mensuelle assureur',
    description: 'Relevé détaillé des prestations par souscripteur et facture consolidée transmise à la compagnie.',
    regle: 'Deux pièces, une seule vérité : le <strong>relevé</strong> détaille patient par patient, la '
      + '<strong>facture mensuelle</strong> récapitule par souscripteur. L’écran contrôle qu’elles se recoupent '
      + 'avant transmission. L’échange reste fondé sur l’édition de pièces — aucun interfaçage automatisé '
      + 'avec les systèmes des compagnies n’est au périmètre.',
    actions: function () {
      return [
        K.btn('Conventions', { icon: 'file-signature', onclick: function () { global.SIGH.app.go('m9-conventions'); } }),
        K.btn('Créances', { icon: 'hourglass', onclick: function () { global.SIGH.app.go('m9-creances'); } }),
      ];
    },
    render: function (root) {
      var host = el('div.space-y-4');
      var selAssureur = U.combo(D.ASSUREURS.map(function (a) {
        return { value: a.code, label: a.nom, detail: a.code, icon: 'shield-check' };
      }), {
        value: D.ASSUREURS.length ? D.ASSUREURS[0].code : '',
        searchPlaceholder: 'Nom de la compagnie…', placeholder: 'Choisir une compagnie',
      });
      var selMois = el('select.select');
      /* L'année suit l'EXERCICE choisi (sélecteur de l'en-tête) : la facture mensuelle de juillet 2025 n'est pas celle de juillet 2026. */
      var ANNEE = global.SIGH.exercice ? global.SIGH.exercice.choisi() : AUJ.getFullYear();
      for (var m = 0; m < 12; m++) selMois.appendChild(el('option', { value: String(m) }, C.MOIS[m] + ' ' + ANNEE));
      selMois.value = String(AUJ.getMonth());

      var barre = el('div.card');
      var bbody = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      bbody.appendChild(el('div.min-w-\\[16rem\\]', null, [el('label.label', { text: 'Compagnie' }), selAssureur]));
      bbody.appendChild(el('div', null, [el('label.label', { text: 'Mois' }), selMois]));
      bbody.appendChild(K.btn('Éditer le relevé', { icon: 'printer', onclick: function () { imprimerReleve(); } }));
      bbody.appendChild(K.btn('Éditer la facture mensuelle', { variant: 'primary', icon: 'file-text', onclick: function () { imprimerFacture(); } }));
      barre.appendChild(bbody);
      host.appendChild(barre);

      var vue = el('div.space-y-4');
      host.appendChild(vue);
      selAssureur.addEventListener('change', afficher);
      selMois.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;

      /* --- Données du mois, ventilées comme sur les pièces réelles --------- */
      function selection() {
        var code = selAssureur.value, mois = Number(selMois.value);
        return facturesAssurance().filter(function (f) {
          var d = C.toDate(f.date);
          return f.assureur === code && d.getMonth() === mois && d.getFullYear() === ANNEE;
        });
      }

      /* Ventilation d'une facture en consultations / analyses / soins.
         Les factures nées du parcours portent leurs lignes catégorisées ; les
         plus anciennes n'ont que leur nature — on retombe sur elle. */
      function ventiler(f) {
        var v = { consultation: 0, analyse: 0, soin: 0 };
        if (f.lignes && f.lignes.length && f.lignes[0].categorie) {
          f.lignes.forEach(function (l) {
            var montant = l.montant != null ? l.montant : l.quantite * l.prixUnitaire;
            if (l.categorie === 'consultation' || l.categorie === 'certificat') v.consultation += montant;
            else if (l.categorie === 'analyse') v.analyse += montant;
            else v.soin += montant;
          });
          return v;
        }
        var t = String(f.type || '');
        if (/Consultation/i.test(t)) v.consultation = f.montantTTC;
        else if (/Laboratoire/i.test(t)) v.analyse = f.montantTTC;
        else v.soin = f.montantTTC;
        return v;
      }

      /* Un patient = une ligne du relevé ; un souscripteur = un tableau. */
      function parSouscripteur() {
        var rows = selection();
        var groupes = {};
        rows.forEach(function (f) {
          var p = patients().filter(function (x) { return x.id === f.patientId; })[0];
          var sid = (p && p.souscripteurId) || 'SANS';
          var s = sid === 'SANS' ? null : S.collection('souscripteurs').get(sid);
          if (!groupes[sid]) {
            groupes[sid] = {
              id: sid, nom: s ? s.nom : 'Sans souscripteur rattaché',
              police: s ? s.police : '—', lignes: {},
            };
          }
          var g = groupes[sid];
          var k = f.patientId;
          if (!g.lignes[k]) {
            g.lignes[k] = {
              patient: f.patient, patientCode: f.patientCode || '—',
              dates: [], consultation: 0, analyse: 0, soin: 0,
              total: 0, assure: 0, assureur: 0,
            };
          }
          var l = g.lignes[k], v = ventiler(f);
          l.dates.push(C.dateFR(f.date));
          l.consultation += v.consultation; l.analyse += v.analyse; l.soin += v.soin;
          l.total += f.montantTTC; l.assure += f.partPatient; l.assureur += f.partAssurance;
        });
        return Object.keys(groupes).map(function (k) {
          var g = groupes[k];
          g.patients = Object.keys(g.lignes).map(function (x) { return g.lignes[x]; });
          g.total = C.sum(g.patients, 'total');
          g.assure = C.sum(g.patients, 'assure');
          g.assureur = C.sum(g.patients, 'assureur');
          g.consultation = C.sum(g.patients, 'consultation');
          g.analyse = C.sum(g.patients, 'analyse');
          g.soin = C.sum(g.patients, 'soin');
          return g;
        }).sort(function (a, b) { return b.assureur - a.assureur; });
      }

      function afficher() {
        var groupes = parSouscripteur();
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Souscripteurs du mois', value: C.num(groupes.length), icon: 'file-signature', tone: 'navy' },
          { label: 'Assurés concernés', value: C.num(C.sum(groupes, function (g) { return g.patients.length; })), icon: 'users', tone: 'info' },
          { label: 'Montant total facturé', value: C.money(C.sum(groupes, 'total')), icon: 'calculator', tone: 'neutral' },
          { label: 'Réclamé à la compagnie', value: C.money(C.sum(groupes, 'assureur')), icon: 'hand-coins', tone: 'warning' },
        ]));

        if (!groupes.length) {
          vue.appendChild(U.empty('Aucune prestation assurée pour cette compagnie sur le mois choisi.', { icon: 'files' }));
          U.icons(vue);
          return;
        }

        vue.appendChild(U.tabs([
          { id: 'releve', label: 'Relevé des prestations', badge: groupes.length, render: ongletReleve },
          { id: 'facture', label: 'Facture mensuelle', render: ongletFacture },
        ]));
        U.icons(vue);

        function ongletReleve(panneau) {
          var box = el('div.space-y-4');
          box.appendChild(K.note('Un tableau <strong>par souscripteur</strong>, patient par patient, avec la date de '
            + 'consultation — structure du relevé réellement transmis aux compagnies.', { tone: 'info' }));
          groupes.forEach(function (g) {
            box.appendChild(U.dataTable({
              title: g.nom + ' — police ' + g.police,
              rows: g.patients, exportName: 'releve-' + g.id, pageSize: 12, searchable: g.patients.length > 12,
              columns: [
                { key: 'patientCode', label: 'Dossier', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.patientCode }); } },
                { key: 'patient', label: 'Patient' },
                {
                  key: 'dates', label: 'Dates', nowrap: true,
                  text: function (r) { return r.dates.join(', '); },
                  render: function (r) {
                    return el('span.text-xs.text-slate-500', {
                      text: r.dates.length > 2 ? r.dates.slice(0, 2).join(', ') + ' +' + (r.dates.length - 2) : r.dates.join(', '),
                    });
                  },
                },
                { key: 'consultation', label: 'Consultations', align: 'right', text: mt, render: function (r) { return mt(r, 'consultation'); } },
                { key: 'analyse', label: 'Analyses', align: 'right', text: mt, render: function (r) { return mt(r, 'analyse'); } },
                { key: 'soin', label: 'Soins', align: 'right', text: mt, render: function (r) { return mt(r, 'soin'); } },
                { key: 'total', label: 'Total', align: 'right', text: mt, render: function (r) { return el('span.font-semibold', { text: C.money(r.total, false) }); } },
                { key: 'assure', label: 'Assuré', align: 'right', text: mt, render: function (r) { return mt(r, 'assure'); } },
                {
                  key: 'assureur', label: 'Assureur', align: 'right', text: mt,
                  render: function (r) { return el('span.font-semibold.text-warning-700', { text: C.money(r.assureur, false) }); },
                },
              ],
            }));
          });
          panneau.appendChild(box);
          U.icons(panneau);
          return null;

          function mt(r, k) {
            if (typeof k !== 'string') return String(r);
            return r[k] ? C.money(r[k], false) : el('span.text-slate-300', { text: '—' });
          }
        }

        function ongletFacture(panneau) {
          var box = el('div.space-y-4');

          /* Contrôle de cohérence : les deux pièces doivent se recouper. */
          var ecarts = groupes.filter(function (g) {
            return Math.abs(g.total - (g.assure + g.assureur)) > 1
              || Math.abs(g.total - (g.consultation + g.analyse + g.soin)) > 1;
          });
          box.appendChild(ecarts.length
            ? K.note('<strong>' + ecarts.length + ' souscripteur(s) en écart</strong> entre le relevé et la facture : '
              + ecarts.map(function (g) { return g.nom; }).join(', ')
              + '. Ne pas transmettre avant correction.', { tone: 'danger', icon: 'alert-triangle' })
            : K.note('<strong>Relevé et facture se recoupent</strong> pour les ' + groupes.length
              + ' souscripteur(s) du mois : ventilation, total et répartition concordent. '
              + 'La pièce peut être transmise.', { tone: 'success', icon: 'check-circle-2' }));

          box.appendChild(U.dataTable({
            title: 'Facture mensuelle — ' + assureurNom(selAssureur.value) + ', ' + C.MOIS[Number(selMois.value)] + ' ' + ANNEE,
            rows: groupes, exportName: 'facture-mensuelle', pageSize: 20,
            columns: [
              {
                key: 'nom', label: 'Souscripteur',
                render: function (g) {
                  return el('div.min-w-0', null, [
                    el('p.truncate.text-sm.font-medium.text-slate-800', { text: g.nom }),
                    el('p.font-mono.text-xs.text-slate-400', { text: g.police }),
                  ]);
                },
              },
              {
                key: 'nb', label: 'Assurés', align: 'right',
                value: function (g) { return g.patients.length; },
                render: function (g) { return String(g.patients.length); },
              },
              { key: 'consultation', label: 'Consultations', align: 'right', text: function (g) { return String(g.consultation); }, render: function (g) { return C.money(g.consultation, false); } },
              { key: 'analyse', label: 'Analyses', align: 'right', text: function (g) { return String(g.analyse); }, render: function (g) { return C.money(g.analyse, false); } },
              { key: 'soin', label: 'Soins', align: 'right', text: function (g) { return String(g.soin); }, render: function (g) { return C.money(g.soin, false); } },
              { key: 'total', label: 'Total', align: 'right', text: function (g) { return String(g.total); }, render: function (g) { return el('span.font-semibold', { text: C.money(g.total, false) }); } },
              { key: 'assure', label: 'Assuré', align: 'right', text: function (g) { return String(g.assure); }, render: function (g) { return C.money(g.assure, false); } },
              {
                key: 'assureur', label: 'Assureur', align: 'right',
                text: function (g) { return String(g.assureur); },
                render: function (g) { return el('span.font-semibold.text-warning-700', { text: C.money(g.assureur, false) }); },
              },
            ],
          }));
          panneau.appendChild(box);
          U.icons(panneau);
          return null;
        }
      }

      /* --- Éditions ------------------------------------------------------- */
      function imprimerReleve() {
        var groupes = parSouscripteur();
        if (!groupes.length) { U.toast('Aucune prestation à relever sur ce mois.', { type: 'warning' }); return; }
        var contenu = el('div.space-y-4');
        groupes.forEach(function (g) {
          contenu.appendChild(el('p.mt-3.text-\\[10px\\].font-bold.text-navy-900', {
            text: g.nom + ' — police ' + g.police,
          }));
          contenu.appendChild(P.tableau([
            { label: 'Dossier', key: 'patientCode' },
            { label: 'Patient', key: 'patient' },
            { label: 'Dates', value: function (r) { return r.dates.join(', '); } },
            /* LE RELEVÉ EST LA PIÈCE OPPOSÉE À LA COMPAGNIE : ses totaux
               doivent être ceux de son propre détail. Le pied recevait les
               totaux du GROUPE sous des clés qu’aucune colonne ne portait —
               il cherchait `total[undefined]` et sortait vide. Chaque colonne
               refait donc sa somme depuis les lignes imprimées. */
            { label: 'Consultations', align: 'right', value: function (r) { return r.consultation ? C.money(r.consultation, false) : ''; }, somme: function (r) { return r.consultation; } },
            { label: 'Analyses', align: 'right', value: function (r) { return r.analyse ? C.money(r.analyse, false) : ''; }, somme: function (r) { return r.analyse; } },
            { label: 'Soins', align: 'right', value: function (r) { return r.soin ? C.money(r.soin, false) : ''; }, somme: function (r) { return r.soin; } },
            { label: 'Total', align: 'right', value: function (r) { return C.money(r.total, false); }, somme: function (r) { return r.total; } },
            { label: 'Assuré', align: 'right', value: function (r) { return C.money(r.assure, false); }, somme: function (r) { return r.assure; } },
            { label: 'Assureur', align: 'right', value: function (r) { return C.money(r.assureur, false); }, somme: function (r) { return r.assureur; } },
          ], g.patients, { total: true, totalLabel: 'TOTAL' }));
        });
        P.etat({
          titre: 'Relevé des prestations de la clinique',
          sousTitre: assureurNom(selAssureur.value) + ' — ' + C.MOIS[Number(selMois.value)] + ' ' + ANNEE,
          cartouche: [['Compagnie', assureurNom(selAssureur.value)],
            ['Période', C.MOIS[Number(selMois.value)] + ' ' + ANNEE],
            ['Souscripteurs', C.num(groupes.length)],
            ['Assurés', C.num(C.sum(groupes, function (g) { return g.patients.length; }))],
            ['Total facturé', C.money(C.sum(groupes, 'total'))],
            ['Part assureur', C.money(C.sum(groupes, 'assureur'))]],
          contenu: contenu,
          signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
            { role: 'Pour la compagnie', mention: 'Réception' }],
        });
      }

      function imprimerFacture() {
        var groupes = parSouscripteur();
        if (!groupes.length) { U.toast('Aucune prestation à facturer sur ce mois.', { type: 'warning' }); return; }
        var mois = Number(selMois.value);
        var numero = 'FA ' + C.pad(groupes.length + 140, 3) + '/' + C.pad(mois + 1, 2) + '/CNT/' + ANNEE;
        var totalAssureur = C.sum(groupes, 'assureur');
        P.etat({
          titre: 'Facture — prestations de santé',
          sousTitre: numero + ' — ' + assureurNom(selAssureur.value),
          cartouche: [['Facture n°', numero],
            ['Compagnie', assureurNom(selAssureur.value)],
            ['Période', C.MOIS[mois] + ' ' + ANNEE],
            ['Souscripteurs', C.num(groupes.length)],
            ['Assurés concernés', C.num(C.sum(groupes, function (g) { return g.patients.length; }))],
            ['RCCM', C.BRAND.rccm]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Souscripteur', key: 'nom' },
              { label: 'Police', key: 'police' },
              { label: 'Assurés', align: 'right', value: function (g) { return String(g.patients.length); }, somme: function (g) { return g.patients.length; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Consultations', align: 'right', value: function (g) { return C.money(g.consultation, false); }, somme: function (g) { return g.consultation; } },
              { label: 'Analyses', align: 'right', value: function (g) { return C.money(g.analyse, false); }, somme: function (g) { return g.analyse; } },
              { label: 'Soins', align: 'right', value: function (g) { return C.money(g.soin, false); }, somme: function (g) { return g.soin; } },
              { label: 'Total', align: 'right', value: function (g) { return C.money(g.total, false); }, somme: function (g) { return g.total; } },
              { label: 'Assuré', align: 'right', value: function (g) { return C.money(g.assure, false); }, somme: function (g) { return g.assure; } },
              /* La part assureur est le montant réclamé : elle se refait
                 depuis les souscripteurs imprimés, jamais depuis une variable
                 calculée à côté du tableau. */
              { label: 'Assureur', align: 'right', value: function (g) { return C.money(g.assureur, false); }, somme: function (g) { return g.assureur; } },
            ], groupes, { total: true, totalLabel: 'TOTAL' }),
            el('p.mt-4.text-\\[10px\\].font-semibold.text-slate-800', {
              text: C.BRAND.formuleArrete + ' : ' + C.montantEnLettres(totalAssureur) + '.',
            }),
            el('p.mt-3.text-\\[9px\\].text-slate-600', {
              text: 'Le relevé détaillé des prestations, patient par patient, accompagne la présente facture.',
            }),
          ]),
          signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
            { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
        });
      }
    },
  });

  /* ==========================================================================
   * HISTORIQUE PAR ASSUREUR
   * --------------------------------------------------------------------------
   * Demande de la Direction : retrouver, compagnie par compagnie, le détail de
   * ce qui a été consommé — pour répondre à une contestation, préparer une
   * renégociation ou extraire librement les données d'un assuré.
   * ======================================================================== */
  global.SIGH.screen('m9-historique', {
    title: 'Historique par assureur',
    description: 'Détail des prestations consommées par compagnie, souscripteur et assuré, sur une plage libre.',
    regle: 'Cet écran <strong>extrait</strong>, il ne modifie rien. Il répond à la demande d’extraction libre des '
      + 'données des assurés : filtrer, consulter le détail d’une prestation, exporter la sélection.',
    actions: function () {
      return [
        K.btn('Relevé & facture mensuelle', { icon: 'files', onclick: function () { global.SIGH.app.go('m9-factures-assureur'); } }),
        K.btn('Conventions', { icon: 'file-signature', onclick: function () { global.SIGH.app.go('m9-conventions'); } }),
      ];
    },
    render: function (root) {
      var selAssureur = U.combo([{ value: '', label: 'Toutes les compagnies' }].concat(
        D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom, detail: a.code }; })
      ), { value: '', placeholder: 'Toutes les compagnies' });
      /* Un exercice AUTRE que l'année en cours ouvre l'historique sur cet exercice entier. */
      var fx = global.SIGH.exercice ? global.SIGH.exercice.fenetre() : null;
      var horsCourant = fx && fx.annee !== AUJ.getFullYear();
      var debut = el('input.input', { type: 'date', value: horsCourant ? fx.debut : C.iso(C.addDays(AUJ, -180)) });
      var fin = el('input.input', { type: 'date', value: horsCourant ? fx.fin : C.iso(AUJ) });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div.min-w-\\[16rem\\]', null, [el('label.label', { text: 'Compagnie' }), selAssureur]),
        el('div', null, [el('label.label', { text: 'Du' }), debut]),
        el('div', null, [el('label.label', { text: 'Au' }), fin]),
      ]));

      [selAssureur, debut, fin].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function selection() {
        var code = selAssureur.value;
        var d1 = C.toDate(debut.value).getTime(), d2 = C.toDate(fin.value).getTime();
        return facturesAssurance().filter(function (f) {
          var d = C.toDate(f.date).getTime();
          if (d < d1 || d > d2) return false;
          return !code || f.assureur === code;
        }).map(function (f) {
          var p = patients().filter(function (x) { return x.id === f.patientId; })[0];
          var s = p && p.souscripteurId ? S.collection('souscripteurs').get(p.souscripteurId) : null;
          return Object.assign({}, f, {
            souscripteurNom: s ? s.nom : '—',
            police: s ? s.police : '—',
            assureurNom: assureurNom(f.assureur),
          });
        });
      }

      function afficher() {
        var rows = selection();
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Prestations', value: C.num(rows.length), icon: 'history', tone: 'navy', hint: C.dateFR(debut.value) + ' → ' + C.dateFR(fin.value) },
          { label: 'Assurés distincts', value: C.num(Object.keys(C.groupBy(rows, 'patientId')).length), icon: 'users', tone: 'info' },
          { label: 'Total facturé', value: C.money(C.sum(rows, 'montantTTC')), icon: 'receipt', tone: 'neutral' },
          { label: 'Part assureurs', value: C.money(C.sum(rows, 'partAssurance')), icon: 'hand-coins', tone: 'warning' },
        ]));

        if (!rows.length) {
          vue.appendChild(U.empty('Aucune prestation assurée sur la plage choisie.', { icon: 'history' }));
          U.icons(vue);
          return;
        }

        /* Répartition par compagnie, pour situer d'un coup d'œil. */
        var parCompagnie = C.groupBy(rows, 'assureurNom');
        vue.appendChild(U.card('Répartition par compagnie', K.ranking(
          Object.keys(parCompagnie).map(function (k) {
            return { label: k, value: C.sum(parCompagnie[k], 'partAssurance') };
          }).sort(function (a, b) { return b.value - a.value; }),
          { format: function (v) { return C.money(v, false); } }
        )));

        vue.appendChild(U.dataTable({
          title: 'Détail des prestations', rows: rows, exportName: 'historique-assureur',
          pageSize: 20, searchable: true, defaultSort: 'date', defaultDir: 'desc',
          filters: [
            { name: 'souscripteurNom', label: 'Souscripteur', options: Object.keys(C.groupBy(rows, 'souscripteurNom')).sort() },
            { name: 'type', label: 'Nature', options: Object.keys(C.groupBy(rows, 'type')).sort() },
            {
              name: 'reglement', label: 'Règlement',
              options: [{ value: 'soldee', label: 'Soldée' }, { value: 'due', label: 'Reste dû' }],
              match: function (f, v) { return v === 'soldee' ? f.reliquat === 0 : f.reliquat > 0; },
            },
          ],
          columns: [
            { key: 'date', label: 'Date', nowrap: true, text: function (f) { return C.dateFR(f.date); }, render: function (f) { return C.dateFR(f.date); } },
            { key: 'numero', label: 'Pièce', nowrap: true, render: function (f) { return el('span.font-mono.text-xs', { text: f.numero }); } },
            {
              key: 'patient', label: 'Assuré',
              render: function (f) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.text-slate-800', { text: f.patient }),
                  el('p.font-mono.text-xs.text-slate-400', { text: f.patientCode || '—' }),
                ]);
              },
            },
            {
              key: 'souscripteurNom', label: 'Souscripteur',
              render: function (f) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.text-slate-700', { text: f.souscripteurNom }),
                  el('p.font-mono.text-xs.text-slate-400', { text: f.police }),
                ]);
              },
            },
            { key: 'assureurNom', label: 'Compagnie', render: function (f) { return U.badge(f.assureur, 'navy'); } },
            { key: 'type', label: 'Nature' },
            { key: 'montantTTC', label: 'Montant', align: 'right', text: function (f) { return String(f.montantTTC); }, render: function (f) { return C.money(f.montantTTC, false); } },
            {
              key: 'partAssurance', label: 'Part assureur', align: 'right',
              text: function (f) { return String(f.partAssurance); },
              render: function (f) { return el('span.font-semibold.text-warning-700', { text: C.money(f.partAssurance, false) }); },
            },
          ],
          onRowClick: function (f) {
            U.drawer({
              title: f.numero, subtitle: f.patient + ' — ' + C.dateFR(f.date), width: 'max-w-2xl',
              body: el('div.space-y-4', null, [
                U.descList([
                  ['Assuré', f.patient], ['Dossier', f.patientCode || '—'],
                  ['Compagnie', f.assureurNom], ['Souscripteur', f.souscripteurNom],
                  ['N° de police', f.police], ['Nature', f.type],
                  ['Montant', C.money(f.montantTTC)], ['Part assureur', C.money(f.partAssurance)],
                  ['Part patient', C.money(f.partPatient)], ['Reste dû', C.money(f.reliquat)],
                ]),
                (f.lignes && f.lignes.length)
                  ? U.card('Lignes de la prestation', K.miniTable([
                    { label: 'Désignation', key: 'designation' },
                    { label: 'Qté', align: 'right', key: 'quantite' },
                    { label: 'Montant', align: 'right', render: function (l) { return C.money(l.montant != null ? l.montant : l.quantite * l.prixUnitaire, false); } },
                    { label: 'Part ass.', align: 'right', render: function (l) { return C.money(l.partAssureur || 0, false); } },
                    { label: 'Motif', render: function (l) { return l.motifCouverture || '—'; } },
                  ], f.lignes))
                  : K.lectureSeule('Cette facture est antérieure au détail par ligne : seul son total est connu.'),
              ]),
            });
          },
        }));
        U.icons(vue);
      }
    },
  });

  /* ==========================================================================
   * CRÉANCES
   * ======================================================================== */
  global.SIGH.screen('m9-creances', {
    title: 'Créances assureurs',
    description: 'Suivi des montants dus par les compagnies, par ancienneté et par compagnie.',
    regle: 'Écran en lecture seule. Les créances sont le <strong>reliquat des factures prises en charge</strong> : elles évoluent avec les règlements des compagnies, jamais par saisie directe.',
    render: function (root) {
      /* FILTRES AVANCÉS DE LA BALANCE ÂGÉE.
         --------------------------------------------------------------
         Une balance âgée sans bornes de dates est une photographie de
         TOUT l'historique : la question posée au recouvrement est presque
         toujours « ce qui reste dû sur les factures de tel trimestre ».
         Les bornes portent donc sur la DATE DE LA FACTURE, l'ancienneté
         restant comptée par rapport à aujourd'hui — ce sont deux choses
         différentes, et les confondre ferait vieillir une créance parce
         qu'on a rétréci la fenêtre.

         Les filtres sont RELEVÉS SUR LA PAGE par `print.js` : l'état édité
         retrace de lui-même la sélection, sans être recâblé ici. */
      var fDu = el('input.input', { type: 'date' });
      var fAu = el('input.input', { type: 'date' });
      var fCompagnie = el('select.select');
      var fAnciennete = el('select.select');
      var fSeuil = el('select.select');
      fCompagnie.appendChild(el('option', { value: '', text: 'Toutes les compagnies' }));
      D.ASSUREURS.forEach(function (a) {
        fCompagnie.appendChild(el('option', { value: a.code, text: a.code + ' — ' + a.nom }));
      });
      [['', 'Toutes anciennetés'], ['moins30', 'Moins de 30 jours'], ['30a90', 'De 30 à 90 jours'],
        ['plus90', 'Au-delà de 90 jours']].forEach(function (o) {
        fAnciennete.appendChild(el('option', { value: o[0], text: o[1] }));
      });
      [['', 'Tout montant'], ['50000', 'Au moins 50 000 F'], ['200000', 'Au moins 200 000 F'],
        ['500000', 'Au moins 500 000 F'], ['1000000', 'Au moins 1 000 000 F']].forEach(function (o) {
        fSeuil.appendChild(el('option', { value: o[0], text: o[1] }));
      });

      var host = el('div.space-y-4');
      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Factures émises du' }), fDu]),
        el('div', null, [el('label.label', { text: 'au' }), fAu]),
        el('div', null, [el('label.label', { text: 'Compagnie' }), fCompagnie]),
        el('div', null, [el('label.label', { text: 'Ancienneté retenue' }), fAnciennete]),
        el('div', null, [el('label.label', { text: 'Créance minimale' }), fSeuil]),
        K.btn('Réinitialiser', { icon: 'rotate-ccw', onclick: function () {
          fDu.value = ''; fAu.value = ''; fCompagnie.value = '';
          fAnciennete.value = ''; fSeuil.value = ''; peindre();
        } }),
      ]));
      root.appendChild(barre);
      [fDu, fAu, fCompagnie, fAnciennete, fSeuil].forEach(function (x) {
        x.addEventListener('change', peindre);
      });
      root.appendChild(host);
      peindre();
      return null;

      function dansPlage(f) {
        var d = String(f.date || '').slice(0, 10);
        if (fDu.value && d < fDu.value) return false;
        if (fAu.value && d > fAu.value) return false;
        return true;
      }

      function peindre() {
      C.clear(host);
      var rows = D.ASSUREURS.map(function (a) {
        var f = facturesAssurance().filter(function (x) { return x.assureur === a.code && dansPlage(x); });
        var recent = f.filter(function (x) { return C.daysBetween(x.date, AUJ) <= 30; });
        var moyen = f.filter(function (x) { var j = C.daysBetween(x.date, AUJ); return j > 30 && j <= 90; });
        var ancien = f.filter(function (x) { return C.daysBetween(x.date, AUJ) > 90; });
        return {
          id: a.code, code: a.code, nom: a.nom,
          nbFactures: f.length,
          total: C.sum(f, 'partAssurance'),
          moins30: C.sum(recent, 'partAssurance'),
          de30a90: C.sum(moyen, 'partAssurance'),
          plus90: C.sum(ancien, 'partAssurance'),
        };
      }).filter(function (r) { return r.total > 0; })
        .filter(function (r) { return !fCompagnie.value || r.code === fCompagnie.value; })
        .filter(function (r) {
          if (!fAnciennete.value) return true;
          return (r[fAnciennete.value === 'moins30' ? 'moins30'
            : (fAnciennete.value === '30a90' ? 'de30a90' : 'plus90')] || 0) > 0;
        })
        .filter(function (r) { return !fSeuil.value || r.total >= +fSeuil.value; });

      host.appendChild(U.kpiGrid([
        { label: 'Créances totales', value: C.money(C.sum(rows, 'total')), icon: 'hand-coins', tone: 'warning' },
        { label: 'Moins de 30 jours', value: C.money(C.sum(rows, 'moins30')), icon: 'clock', tone: 'success' },
        { label: '30 à 90 jours', value: C.money(C.sum(rows, 'de30a90')), icon: 'clock-alert', tone: 'warning' },
        { label: 'Plus de 90 jours', value: C.money(C.sum(rows, 'plus90')), icon: 'alert-octagon', tone: 'danger', hint: 'Relance impérative' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Balance âgée des créances par compagnie', rows: rows, exportName: 'creances-assureurs', pageSize: 15,
        defaultSort: 'total', defaultDir: 'desc',
        columns: [
          { key: 'code', label: 'Code', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold', { text: r.code }); } },
          { key: 'nom', label: 'Compagnie' },
          { key: 'nbFactures', label: 'Factures', align: 'right' },
          { key: 'moins30', label: '< 30 j', align: 'right', text: function (r) { return C.money(r.moins30, false); }, render: function (r) { return C.money(r.moins30, false); } },
          { key: 'de30a90', label: '30 – 90 j', align: 'right', text: function (r) { return C.money(r.de30a90, false); }, render: function (r) { return el('span', { class: r.de30a90 > 0 ? 'text-warning-700' : '', text: C.money(r.de30a90, false) }); } },
          { key: 'plus90', label: '> 90 j', align: 'right', text: function (r) { return C.money(r.plus90, false); }, render: function (r) { return el('span', { class: r.plus90 > 0 ? 'font-semibold text-danger-600' : '', text: C.money(r.plus90, false) }); } },
          { key: 'total', label: 'Total dû', align: 'right', text: function (r) { return C.money(r.total, false); }, render: function (r) { return el('span.font-bold.text-navy-900', { text: C.money(r.total, false) }); } },
        ],
        actions: [K.btn('Éditer l’état des créances', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'État des créances — tiers payeurs',
              sousTitre: 'Balance âgée au ' + C.dateFR(AUJ),
              cartouche: [['Créances totales', C.money(C.sum(rows, 'total'))],
                ['Compagnies concernées', C.num(rows.length)],
                ['Dont plus de 90 jours', C.money(C.sum(rows, 'plus90'))],
                ['Date d’édition', C.dateFR(AUJ)]],
              contenu: P.tableau([
                { label: 'Code', key: 'code' }, { label: 'Compagnie', key: 'nom' },
                { label: 'Factures', key: 'nbFactures', align: 'right' },
                { label: '< 30 j', align: 'right', value: function (r) { return C.money(r.moins30, false); },
                  somme: function (r) { return r.moins30 || 0; } },
                { label: '30-90 j', align: 'right', value: function (r) { return C.money(r.de30a90, false); },
                  somme: function (r) { return r.de30a90 || 0; } },
                { label: '> 90 j', align: 'right', value: function (r) { return C.money(r.plus90, false); },
                  somme: function (r) { return r.plus90 || 0; } },
                { label: 'Total', align: 'right', value: function (r) { return C.money(r.total, false); },
                  somme: function (r) { return r.total || 0; } },
              ], C.sortBy(rows, 'total', 'desc'), { total: true }),
              signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
            });
          },
        })],
      }));

      host.appendChild(K.charts([
        {
          title: 'Créances par compagnie',
          render: function () {
            return K.ranking(C.sortBy(rows, 'total', 'desc').map(function (r) { return { label: r.nom, value: r.total }; }),
              { format: function (v) { return C.money(v, false); }, tone: 'warning' });
          },
        },
        {
          title: 'Répartition par ancienneté',
          render: function () {
            return G.anneau(['Moins de 30 jours', '30 à 90 jours', 'Plus de 90 jours'],
              [C.sum(rows, 'moins30'), C.sum(rows, 'de30a90'), C.sum(rows, 'plus90')],
              { legend: 'bottom', colors: [G.TONES.vert, G.TONES.orange, G.TONES.rouge] });
          },
        },
      ]));
      if (!rows.length) {
        host.appendChild(K.note('Aucune créance ne répond à cette sélection. Les filtres portent sur '
          + 'la <strong>date des factures</strong> ; l’ancienneté, elle, se compte toujours par rapport '
          + 'à aujourd’hui.', { tone: 'info', icon: 'filter' }));
      }
      U.icons(host);
      }
    },
  });

  /* ==========================================================================
   * RELANCES
   * ======================================================================== */
  global.SIGH.screen('m9-relances', {
    title: 'Relances',
    description: 'Suivi des relances adressées aux compagnies pour les créances en souffrance.',
    render: function (root) {
      var col = S.collection('relances', { module: 'M9', entite: 'Relance' });
      var host = el('div.space-y-4');
      var table;
      /* LES INDICATEURS SUIVENT LE REGISTRE (30/10/2026) : ils étaient construits UNE fois à l'ouverture — une relance créée, corrigée ou
         archivée rafraîchissait le tableau et laissait les quatre compteurs à leur valeur d'origine (constaté en pilotant l'écran). */
      var kpiHost = el('div');
      host.appendChild(kpiHost);
      function peindreKpis() {
        C.clear(kpiHost);
        kpiHost.appendChild(U.kpiGrid([
        { label: 'Relances émises', value: C.num(col.active().length), icon: 'send', tone: 'navy' },
        { label: 'En attente de réponse', value: C.num(col.active().filter(function (r) { return r.statutRelance === 'en_attente'; }).length), icon: 'clock', tone: 'warning' },
        { label: 'Régularisées', value: C.num(col.active().filter(function (r) { return r.statutRelance === 'regularisee'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Montant relancé', value: C.money(C.sum(col.active(), 'montant')), icon: 'hand-coins', tone: 'info' },
      ]));
        U.icons(kpiHost);
      }
      peindreKpis();

      table = U.dataTable({
        title: 'Registre des relances',
        rows: function () { return col.active(); },
        exportName: 'relances', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        emptyMessage: 'Aucune relance enregistrée.',
        emptyHint: 'Établir une relance pour une compagnie dont la créance est en souffrance.',
        actions: [K.commande('Nouvelle relance', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(); } })].filter(Boolean),
        filters: [
          { name: 'assureur', label: 'Compagnie', options: D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom }; }) },
          { name: 'niveau', label: 'Niveau', options: ['1re relance', '2e relance', 'Mise en demeure'] },
        ],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'assureurNom', label: 'Compagnie' },
          { key: 'periode', label: 'Période concernée' },
          { key: 'montant', label: 'Montant réclamé', align: 'right', text: function (r) { return C.money(r.montant, false); }, render: function (r) { return el('span.font-semibold', { text: C.money(r.montant, false) }); } },
          {
            key: 'niveau', label: 'Niveau',
            render: function (r) {
              var t = { '1re relance': 'info', '2e relance': 'warning', 'Mise en demeure': 'danger' };
              return U.badge(r.niveau, t[r.niveau] || 'neutral');
            },
          },
          { key: 'canal', label: 'Canal' },
          {
            key: 'statutRelance', label: 'Suite',
            render: function (r) {
              var m = { en_attente: ['En attente', 'warning'], regularisee: ['Régularisée', 'success'], contestee: ['Contestée', 'danger'] };
              var x = m[r.statutRelance] || ['—', 'neutral'];
              return U.badge(x[0], x[1]);
            },
          },
        ],
        rowActions: function (r) {
          return [
            K.iconBtn('printer', 'Imprimer la lettre', function () { etat(r); }),
            /* Une relance se corrige : montant réévalué, niveau qui monte,
               suite donnée par la compagnie. */
            K.iconBtn('pencil', 'Modifier la relance', function () {
              K.modifier(col, champsRelance(), r, function () { table.refresh(); peindreKpis(); });
            }),
            K.iconBtn('archive', 'Archiver', function () {
              var res = col.archive(r.id);
              table.refresh(); peindreKpis();
              U.toast('Relance archivée.', { type: 'success', undo: function () { res.undo(); table.refresh(); peindreKpis(); } });
            }, 'ghost'),
          ];
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      /* Champs partagés par la création et la correction d'une relance. */
      function champsRelance() {
        return [
          {
            name: 'assureur', label: 'Compagnie', type: 'select', required: true, col: 'full',
            options: D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom }; }),
          },
          { name: 'date', label: 'Date de la relance', type: 'date', required: true },
          { name: 'periode', label: 'Période concernée', required: true },
          { name: 'montant', label: 'Montant réclamé (FCFA)', type: 'money', required: true, min: 1 },
          { name: 'niveau', label: 'Niveau de relance', type: 'select', required: true, options: ['1re relance', '2e relance', 'Mise en demeure'] },
          { name: 'canal', label: 'Canal de transmission', type: 'select', required: true, options: ['Courrier remis en main propre', 'Courrier électronique', 'Courrier recommandé', 'Appel téléphonique'] },
          {
            name: 'statutRelance', label: 'Suite donnée', type: 'select', required: true,
            options: [{ value: 'en_attente', label: 'En attente' }, { value: 'regularisee', label: 'Régularisée' },
              { value: 'contestee', label: 'Contestée' }],
          },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ];
      }

      function ouvrir() {
        var f = U.form([
          {
            name: 'assureur', label: 'Compagnie', type: 'select', required: true, col: 'full',
            options: D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom + ' — créance : ' + C.money(creanceAssureur(a.code)) }; }),
          },
          { name: 'date', label: 'Date de la relance', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'periode', label: 'Période concernée', required: true, placeholder: 'ex. juin – juillet 2026' },
          { name: 'montant', label: 'Montant réclamé (FCFA)', type: 'money', required: true, min: 1 },
          { name: 'niveau', label: 'Niveau de relance', type: 'select', required: true, options: ['1re relance', '2e relance', 'Mise en demeure'] },
          { name: 'canal', label: 'Canal de transmission', type: 'select', required: true, options: ['Courrier remis en main propre', 'Courrier électronique', 'Courrier recommandé', 'Appel téléphonique'] },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ], {});

        var selAss = f.controls.assureur;
        selAss.addEventListener('change', function () {
          f.controls.montant.value = creanceAssureur(selAss.value) || 0;
        });
        f.controls.montant.value = creanceAssureur(selAss.value) || 0;

        var m = U.modal({
          title: 'Nouvelle relance', size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer et éditer', {
              variant: 'primary', icon: 'send',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                v.assureurNom = assureurNom(v.assureur);
                v.reference = C.nextRef('REL-', 4);
                v.statutRelance = 'en_attente';
                var res = col.insert(v);
                m.close(); table.refresh(); peindreKpis();
                U.toast('Relance ' + v.reference + ' enregistrée.', { type: 'success', undo: function () { res.undo(); table.refresh(); peindreKpis(); } });
                etat(res.record);
              },
            }),
          ],
        });
      }

      function etat(r) {
        var a = D.ASSUREURS.filter(function (x) { return x.code === r.assureur; })[0] || {};
        P.etat({
          titre: r.niveau === 'Mise en demeure' ? 'Mise en demeure de payer' : 'Lettre de relance',
          sousTitre: r.reference + ' — ' + r.assureurNom,
          cartouche: [['Destinataire', r.assureurNom], ['Courriel', a.email || '—'],
            ['Référence', r.reference], ['Date', C.dateFR(r.date)],
            ['Période concernée', r.periode], ['Montant réclamé', C.money(r.montant)]],
          contenu: el('div.space-y-3', null, [
            el('p', { text: 'Madame, Monsieur,' }),
            el('p.mt-2', {
              text: 'Sauf erreur ou omission de notre part, nous constatons que la somme de '
                + C.money(r.montant) + ', correspondant aux prestations réalisées au profit de vos assurés '
                + 'au titre de la période ' + r.periode + ', demeure impayée à ce jour.',
            }),
            el('p.mt-2', {
              text: r.niveau === 'Mise en demeure'
                ? 'En conséquence, nous vous mettons en demeure de procéder au règlement de cette somme dans un délai de quinze (15) jours '
                  + 'à compter de la réception de la présente. À défaut, nous nous réservons le droit de suspendre la prise en charge '
                  + 'de vos assurés et d’engager toute procédure utile au recouvrement de notre créance.'
                : 'Nous vous saurions gré de bien vouloir procéder au règlement dans les meilleurs délais. '
                  + 'Si ce règlement a été effectué entre-temps, nous vous prions de ne pas tenir compte de la présente.',
            }),
            r.observations ? el('p.mt-2.italic', { text: r.observations }) : null,
            el('p.mt-3', { text: 'Nous vous prions d’agréer, Madame, Monsieur, l’expression de nos salutations distinguées.' }),
          ]),
          signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou', mention: 'Signature et cachet' }],
        });
      }
    },
  });

  /* ==========================================================================
   * FACTURE MÈRE D'ASSURANCE
   * --------------------------------------------------------------------------
   * Demandée par la Direction le 25/08/2026 : « ajouter Facture Mère
   * assurances — relevé et facture par ligne d'assurance sur tous les états ».
   *
   * CE QU'ELLE EST. La facture mensuelle existante s'adresse à UN souscripteur —
   * un employeur, une mutuelle. La compagnie, elle, en reçoit plusieurs et n'a
   * aucune pièce unique à rapprocher de son règlement. La facture MÈRE
   * consolide, pour une compagnie et une période, toutes ses factures filles.
   *
   * CE QUI FAIT SA VALEUR : LE RAPPROCHEMENT. Une mère qui ne se recoupe pas
   * avec la somme de ses filles est pire qu'aucune mère — elle donne à la
   * compagnie un montant que la clinique ne saura pas justifier ligne à ligne
   * le jour du litige. L'écran REFUSE donc d'émettre tant que l'écart n'est pas
   * nul, et il nomme la fille en cause.
   *
   * TROIS NIVEAUX, comme la prise en charge : compagnie → souscripteur →
   * assuré. La mère porte le premier, les filles le deuxième, le relevé le
   * troisième. Aucun des trois n'est redondant.
   *
   * Une mère ÉMISE ne se modifie plus : elle a été transmise. Une correction
   * passe par un avoir, jamais par une réécriture — sans quoi la compagnie et
   * la clinique n'auraient plus le même document sous les yeux.
   * ======================================================================== */
  function colFactureMere() {
    return S.collection('facturesMere', { module: 'M9', entite: 'facture mère', prefix: 'FM' });
  }

  var PERIODES_MERE = [
    { code: 'mois', label: 'Mensuelle', jours: 30 },
    { code: 'trimestre', label: 'Trimestrielle', jours: 90 },
    { code: 'semestre', label: 'Semestrielle', jours: 180 },
    { code: 'annee', label: 'Annuelle', jours: 365 },
  ];

  global.SIGH.screen('m9-facture-mere', {
    title: 'Facture mère assurance',
    description: 'Pièce unique adressée à une compagnie, consolidant toutes ses factures par souscripteur.',
    regle: 'La facture mère <strong>consolide</strong> les factures filles d’une compagnie. Elle n’est '
      + 'émise que si elle <strong>se recoupe exactement</strong> avec elles : une mère qui ne concorde pas '
      + 'donnerait à la compagnie un montant que la clinique ne saurait pas justifier le jour du litige. '
      + 'Une mère émise ne se modifie plus — une correction passe par un <strong>avoir</strong>.',
    actions: function () {
      return [
        K.btn('Relevé & facture mensuelle', { icon: 'files',
          onclick: function () { global.SIGH.app.go('m9-factures-assureur'); } }),
        K.btn('Créances', { icon: 'hourglass', onclick: function () { global.SIGH.app.go('m9-creances'); } }),
      ];
    },
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);

      var etat = {
        compagnie: (D.ASSUREURS[0] || {}).code || '',
        periode: 'mois',
      };
      afficher();
      return null;

      function compagnie() {
        return D.ASSUREURS.filter(function (a) { return a.code === etat.compagnie; })[0] || D.ASSUREURS[0];
      }
      function pe() {
        return PERIODES_MERE.filter(function (x) { return x.code === etat.periode; })[0];
      }
      function depuis() { return C.iso(C.addDays(AUJ, -pe().jours)); }

      /* --------------------------------------------------------------------
       * LES FILLES : une par souscripteur, construites depuis les factures
       * patients réellement émises sur la période. On ne recopie rien — on
       * agrège ce qui existe, ce qui est la seule façon de garantir que la
       * mère se recoupe.
       * ------------------------------------------------------------------ */
      function filles() {
        var comp = compagnie();
        if (!comp) return [];
        var d1 = depuis();
        /* La facture porte tantôt le CODE de l'assureur (jeu amorcé), tantôt son
           NOM (pièces nées du parcours). Comparer à l'un seulement affichait
           « 0 souscripteur » sur une compagnie qui compte des dizaines de
           pièces — et le rapprochement à zéro se déclarait concordant, ce qui
           est le plus trompeur : un contrôle qui passe faute d'avoir quelque
           chose à contrôler. */
        var factures = S.collection('factures').active().filter(function (f) {
          var a = String(f.assureur || '');
          var correspond = a === comp.code || a === comp.nom;
          return correspond && (f.partAssurance || 0) > 0
            && String(f.date).slice(0, 10) >= d1;
        });

        var parSous = {};
        factures.forEach(function (f) {
          var sous = f.souscripteur || 'Sans souscripteur désigné';
          if (!parSous[sous]) {
            parSous[sous] = { souscripteur: sous, factures: [], montant: 0, assureur: 0, patient: 0, lignes: 0 };
          }
          var g = parSous[sous];
          g.factures.push(f);
          g.montant += f.montantTTC || 0;
          g.assureur += f.partAssurance || 0;
          g.patient += f.partPatient || 0;
          g.lignes += (f.lignes || []).length;
        });
        return Object.keys(parSous).sort().map(function (k) { return parSous[k]; });
      }

      /* --------------------------------------------------------------------
       * LE RAPPROCHEMENT — le contrôle qui donne son sens à la pièce.
       * Trois totaux doivent coïncider : la somme des filles, la somme des
       * factures patients, et la somme des LIGNES d'assurance. Si l'un des
       * trois s'écarte, la mère n'est pas émise et l'écart est nommé.
       * ------------------------------------------------------------------ */
      function rapprocher(fs2) {
        var totalFilles = fs2.reduce(function (n, g) { return n + g.assureur; }, 0);
        var toutesFactures = fs2.reduce(function (acc, g) { return acc.concat(g.factures); }, []);
        var totalFactures = toutesFactures.reduce(function (n, f) { return n + (f.partAssurance || 0); }, 0);
        /* Le troisième contrôle descend à la LIGNE : c'est le niveau auquel la
           compagnie contestera, donc celui qu'il faut savoir justifier. */
        var totalLignes = toutesFactures.reduce(function (n, f) {
          return n + (f.lignes || []).reduce(function (m, l) { return m + (l.partAssureur || 0); }, 0);
        }, 0);

        var ecarts = [];
        if (totalFilles !== totalFactures) {
          ecarts.push('Le total des souscripteurs (' + C.money(totalFilles)
            + ') diffère du total des factures patients (' + C.money(totalFactures) + ').');
        }
        if (totalFactures !== totalLignes) {
          ecarts.push('Le total des factures (' + C.money(totalFactures)
            + ') diffère du détail ligne à ligne (' + C.money(totalLignes) + ') — '
            + 'c’est le niveau auquel la compagnie contestera.');
          /* On nomme la pièce en cause : un écart global n'aide personne. */
          toutesFactures.forEach(function (f) {
            var somme = (f.lignes || []).reduce(function (m, l) { return m + (l.partAssureur || 0); }, 0);
            if (somme !== (f.partAssurance || 0)) {
              ecarts.push('Pièce ' + f.numero + ' — ' + f.patient + ' : part assureur '
                + C.money(f.partAssurance) + ' pour ' + C.money(somme) + ' au détail.');
            }
          });
        }
        return {
          totalFilles: totalFilles, totalFactures: totalFactures, totalLignes: totalLignes,
          ecarts: ecarts,
          /* Un rapprochement SANS PIÈCE n'est pas concordant, il est vide.
             Les confondre laisserait émettre une facture mère à zéro franc. */
          concorde: ecarts.length === 0 && toutesFactures.length > 0,
          vide: toutesFactures.length === 0,
          nbFactures: toutesFactures.length,
        };
      }

      function afficher() {
        var comp = compagnie();
        var fs2 = filles();
        var rap = rapprocher(fs2);
        var emises = colFactureMere().active().filter(function (m) {
          return m.compagnieCode === etat.compagnie;
        });

        C.clear(vue);
        vue.appendChild(commandes());

        vue.appendChild(U.kpiGrid([
          { label: 'Souscripteurs facturés', value: C.num(fs2.length), icon: 'building-2', tone: 'navy',
            hint: comp ? comp.nom : '—' },
          { label: 'Pièces filles', value: C.num(rap.nbFactures), icon: 'files', tone: 'info',
            hint: 'factures patients de la période' },
          { label: 'Total à réclamer', value: C.money(rap.totalFilles), icon: 'hand-coins', tone: 'success' },
          { label: 'Rapprochement',
            value: rap.vide ? 'Aucune pièce'
              : (rap.concorde ? 'Concordant' : C.num(rap.ecarts.length) + ' écart(s)'),
            icon: rap.vide ? 'inbox' : (rap.concorde ? 'check-check' : 'triangle-alert'),
            tone: rap.vide ? 'neutral' : (rap.concorde ? 'success' : 'danger') },
        ]));

        if (!rap.concorde) {
          vue.appendChild(K.note('<strong>La facture mère ne peut pas être émise.</strong> '
            + rap.ecarts.map(function (x) { return x; }).join('<br>')
            + '<br>Une mère qui ne se recoupe pas avec ses filles donnerait à la compagnie un montant '
            + 'que la clinique ne saurait pas justifier ligne à ligne le jour du litige.',
          { tone: 'danger', icon: 'triangle-alert' }));
        } else if (rap.vide) {
          vue.appendChild(K.note('Aucune prestation assurée pour cette compagnie sur la période. '
            + 'Élargir la périodicité, ou vérifier que les pièces portent bien le code de la compagnie.',
          { tone: 'neutral', icon: 'inbox' }));
        } else if (fs2.length) {
          vue.appendChild(K.note('Les trois niveaux concordent : <strong>' + C.money(rap.totalFilles)
            + '</strong> au total des souscripteurs, des factures patients et du détail ligne à ligne. '
            + 'La pièce peut être émise.', { tone: 'success', icon: 'check-check' }));
        }

        vue.appendChild(U.tabs([
          { id: 'consolidation', label: 'Consolidation', badge: fs2.length,
            render: function () { return ongletConsolidation(fs2, rap); } },
          { id: 'lignes', label: 'Détail par ligne d’assurance', badge: rap.nbFactures,
            render: function () { return ongletLignes(fs2); } },
          { id: 'emises', label: 'Factures mères émises', badge: emises.length,
            render: function () { return ongletEmises(emises); } },
        ]));
        U.icons(vue);
      }

      function commandes() {
        var selComp = U.combo(D.ASSUREURS.map(function (a) {
          return { value: a.code, label: a.nom, detail: a.code, icon: 'shield-check' };
        }), { value: etat.compagnie, placeholder: 'Choisir une compagnie' });
        selComp.addEventListener('change', function () { etat.compagnie = selComp.value; afficher(); });

        var selPer = el('select.h-10.rounded-lg.border.border-slate-300.px-3.text-sm');
        PERIODES_MERE.forEach(function (x) {
          var o = el('option', { value: x.code, text: x.label });
          if (x.code === etat.periode) o.selected = true;
          selPer.appendChild(o);
        });
        selPer.addEventListener('change', function () { etat.periode = selPer.value; afficher(); });

        var fs2 = filles();
        var rap = rapprocher(fs2);

        return U.card('Compagnie et périodicité',
          el('div.flex.flex-wrap.items-end.gap-3', null, [
            el('div.min-w-\\[16rem\\]', null, [
              el('label.mb-1.block.text-xs.font-medium.text-slate-500', { text: 'Compagnie' }), selComp,
            ]),
            el('div', null, [
              el('label.mb-1.block.text-xs.font-medium.text-slate-500', { text: 'Périodicité' }), selPer,
            ]),
            K.btn('Aperçu de la facture mère', { icon: 'eye',
              onclick: function () { imprimerMere(null); } }),
            /* L'émission n'est offerte que si le rapprochement est bon : un
               bouton grisé inviterait à chercher pourquoi, un bouton absent
               dit que la pièce n'est pas en état. */
            (rap.concorde && fs2.length && K.droits('M9').editer)
              ? K.btn('Émettre la facture mère', { variant: 'primary', icon: 'send',
                onclick: emettre })
              : null,
          ].filter(Boolean)));
      }

      function ongletConsolidation(fs2, rap) {
        if (!fs2.length) {
          return U.card(null, U.empty('Aucune prestation assurée sur la période.', {
            icon: 'layers',
            hint: 'Élargir la périodicité, ou choisir une autre compagnie.',
          }));
        }
        return U.dataTable({
          rows: fs2,
          empty: 'Aucun souscripteur.',
          columns: [
            { key: 'souscripteur', label: 'Souscripteur (n° de police)' },
            { key: 'nb', label: 'Pièces filles', align: 'right',
              somme: function (r) { return r.factures.length; },
              render: function (r) { return C.num(r.factures.length); } },
            { key: 'lignes', label: 'Prestations', align: 'right', somme: true,
              render: function (r) { return C.num(r.lignes); } },
            { key: 'montant', label: 'Montant total', align: 'right', somme: true,
              render: function (r) { return C.money(r.montant); } },
            { key: 'patient', label: 'Part patient', align: 'right', somme: true,
              render: function (r) { return C.money(r.patient); } },
            { key: 'assureur', label: 'Part à réclamer', align: 'right', somme: true,
              render: function (r) { return el('span.font-semibold', { text: C.money(r.assureur) }); } },
          ],
          rowActions: function (r) {
            return [K.iconBtn('eye', 'Voir les pièces filles de ce souscripteur', function () {
              U.drawer({
                title: r.souscripteur,
                subtitle: C.num(r.factures.length) + ' pièce(s) — ' + C.money(r.assureur) + ' à réclamer',
                body: K.miniTable(['Pièce', 'Date', 'Patient', 'Total', 'Part assureur'],
                  C.sortBy(r.factures, 'date').map(function (f) {
                    return [f.numero, C.dateFR(f.date), f.patient,
                      C.money(f.montantTTC), C.money(f.partAssurance)];
                  })),
              });
            })];
          },
        });
      }

      /* Le détail par LIGNE d'assurance : ce que la Direction demande de voir
         « sur tous les états ». C'est le niveau auquel une compagnie conteste. */
      function ongletLignes(fs2) {
        var rows = [];
        fs2.forEach(function (g) {
          g.factures.forEach(function (f) {
            (f.lignes || []).forEach(function (l) {
              if (!(l.partAssureur > 0)) return;
              rows.push({
                souscripteur: g.souscripteur, piece: f.numero, date: f.date,
                patient: f.patient, patientCode: f.patientCode,
                categorie: l.categorie, designation: l.designation,
                quantite: l.quantite, montant: l.montant,
                partAssureur: l.partAssureur, partPatient: l.partPatient,
              });
            });
          });
        });
        return el('div.space-y-3', null, [
          K.note('Chaque ligne d’assurance est reprise ici, patient par patient et prestation par '
            + 'prestation. C’est le niveau auquel une compagnie conteste — il doit donc être produit '
            + 'sans reconstruction, à partir des pièces elles-mêmes.', { tone: 'info', icon: 'list' }),
          U.dataTable({
            rows: C.sortBy(rows, 'date'),
            empty: 'Aucune ligne d’assurance sur la période.',
            columns: [
              { key: 'date', label: 'Date', render: function (r) { return C.dateFR(r.date); } },
              { key: 'souscripteur', label: 'Souscripteur' },
              { key: 'piece', label: 'Pièce' },
              { key: 'patient', label: 'Assuré',
                render: function (r) { return r.patient + ' — ' + r.patientCode; } },
              { key: 'designation', label: 'Prestation' },
              { key: 'quantite', label: 'Qté', align: 'right' },
              { key: 'montant', label: 'Montant', align: 'right', somme: true,
                render: function (r) { return C.money(r.montant); } },
              { key: 'partAssureur', label: 'Part assureur', align: 'right', somme: true,
                render: function (r) { return el('span.font-semibold', { text: C.money(r.partAssureur) }); } },
            ],
          }),
        ]);
      }

      function ongletEmises(emises) {
        return U.dataTable({
          rows: C.sortBy(emises, 'dateEmission').reverse(),
          empty: 'Aucune facture mère émise pour cette compagnie.',
          columns: [
            { key: 'numero', label: 'Numéro' },
            { key: 'dateEmission', label: 'Émise le',
              render: function (r) { return C.dateFR(r.dateEmission); } },
            { key: 'periodeLabel', label: 'Périodicité' },
            { key: 'nbSouscripteurs', label: 'Souscripteurs', align: 'right' },
            { key: 'nbFactures', label: 'Pièces filles', align: 'right' },
            { key: 'montantReclame', label: 'Réclamé', align: 'right',
              render: function (r) { return C.money(r.montantReclame); } },
            { key: 'etat', label: 'État', render: function (r) {
              return r.etat === 'reglee' ? U.badge('Réglée', 'success')
                : U.badge('Transmise', 'warning');
            } },
          ],
          rowActions: function (r) {
            var actes = [K.iconBtn('printer', 'Réimprimer la facture mère', function () { imprimerMere(r); })];
            if (r.etat !== 'reglee' && K.droits('M9').editer) {
              actes.push(K.btn('Enregistrer le règlement', { variant: 'primary', size: 'sm', icon: 'banknote',
                onclick: function () { regler(r); } }));
            }
            actes.push(K.iconBtn('eye', 'Détail', function () {
              U.drawer({
                title: r.numero, subtitle: r.compagnie + ' — ' + r.periodeLabel,
                body: el('div.space-y-4', null, [
                  K.grid([
                    ['Numéro', r.numero], ['Compagnie', r.compagnie],
                    ['Périodicité', r.periodeLabel],
                    ['Période', C.dateFR(r.debut) + ' au ' + C.dateFR(r.fin)],
                    ['Émise le', C.dateFR(r.dateEmission)],
                    ['Souscripteurs', C.num(r.nbSouscripteurs)],
                    ['Pièces filles', C.num(r.nbFactures)],
                    ['Montant réclamé', C.money(r.montantReclame)],
                    ['État', r.etat === 'reglee' ? 'Réglée le ' + C.dateFR(r.dateReglement) : 'Transmise'],
                  ]),
                  K.section('Souscripteurs consolidés',
                    K.miniTable(['Souscripteur', 'Pièces', 'Part réclamée'],
                      (r.souscripteurs || []).map(function (x) {
                        return [x.souscripteur, C.num(x.nbFactures), C.money(x.assureur)];
                      }))),
                  K.note('Cette pièce a été <strong>transmise</strong> : elle ne se modifie plus. '
                    + 'Une correction passe par un <strong>avoir</strong>, sans quoi la compagnie et la '
                    + 'clinique n’auraient plus le même document sous les yeux.',
                  { tone: 'info', icon: 'lock' }),
                ]),
              });
            }));
            return actes;
          },
        });
      }

      function emettre() {
        var comp = compagnie();
        var fs2 = filles();
        var rap = rapprocher(fs2);
        /* Second contrôle avant écriture : les pièces ont pu bouger. */
        if (!rap.concorde) {
          U.toast('Émission refusée — le rapprochement ne concorde plus.', { type: 'error' });
          afficher();
          return;
        }
        U.confirm({
          title: 'Émettre la facture mère ?',
          message: 'La pièce consolidera <strong>' + C.num(fs2.length) + ' souscripteur(s)</strong> et '
            + C.num(rap.nbFactures) + ' facture(s) fille(s), pour <strong>' + C.money(rap.totalFilles)
            + '</strong> réclamés à ' + comp.nom + '.<br><br>Une fois émise, elle <strong>ne se modifie '
            + 'plus</strong> : une correction passera par un avoir.',
          confirmLabel: 'Émettre et transmettre',
        }).then(function (ok) {
          if (!ok) return;
          var rec = colFactureMere().insert({
            numero: 'FM-' + new Date().getFullYear() + '-' + C.pad(colFactureMere().all().length + 1, 4),
            compagnieCode: comp.code, compagnie: comp.nom,
            periode: etat.periode, periodeLabel: pe().label,
            debut: depuis(), fin: C.iso(AUJ),
            dateEmission: C.iso(AUJ),
            nbSouscripteurs: fs2.length, nbFactures: rap.nbFactures,
            montantReclame: rap.totalFilles,
            souscripteurs: fs2.map(function (g) {
              return { souscripteur: g.souscripteur, nbFactures: g.factures.length,
                montant: g.montant, assureur: g.assureur, patient: g.patient };
            }),
            /* Les numéros des filles sont figés sur la mère : c'est ce qui
               permettra, dans six mois, de refaire le rapprochement même si
               une pièce a été archivée depuis. */
            piecesFilles: fs2.reduce(function (acc, g) {
              return acc.concat(g.factures.map(function (f) { return f.numero; }));
            }, []),
            controle: { totalFilles: rap.totalFilles, totalFactures: rap.totalFactures,
              totalLignes: rap.totalLignes, concordant: true },
            etat: 'transmise',
            emisePar: S.currentUser(),
          }).record;
          afficher();
          U.toast('Facture mère ' + rec.numero + ' émise.', {
            type: 'success',
            detail: comp.nom + ' — ' + C.money(rap.totalFilles),
            undo: function () { colFactureMere().archive(rec.id); afficher(); },
            undoMessage: 'Émission annulée — la pièce est archivée.',
          });
          imprimerMere(rec);
        });
      }

      function regler(r) {
        var f = U.form([
          { name: 'dateReglement', label: 'Date du règlement', type: 'date', required: true },
          { name: 'montantRegle', label: 'Montant réglé (FCFA)', type: 'money', required: true,
            value: r.montantReclame,
            hint: 'Un règlement partiel se saisit tel quel : le reliquat reste en créance.' },
          { name: 'reference', label: 'Référence du virement ou du chèque', type: 'text', required: true },
        ], { dateReglement: C.iso(AUJ) });
        var m = U.modal({
          title: 'Règlement de ' + r.numero,
          subtitle: r.compagnie + ' — ' + C.money(r.montantReclame) + ' réclamés',
          body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var reste = r.montantReclame - v.montantRegle;
                colFactureMere().update(r.id, {
                  dateReglement: v.dateReglement, montantRegle: v.montantRegle,
                  referenceReglement: v.reference,
                  reliquat: reste,
                  /* Une pièce n'est « réglée » que si elle l'est entièrement :
                     un règlement partiel laisse la créance ouverte. */
                  etat: reste <= 0 ? 'reglee' : 'transmise',
                });
                m.close(); afficher();
                U.toast(reste <= 0 ? 'Facture mère soldée.'
                  : 'Règlement partiel enregistré — ' + C.money(reste) + ' restent en créance.',
                { type: reste <= 0 ? 'success' : 'warning', detail: r.numero });
              } }),
          ],
        });
      }

      function imprimerMere(r) {
        var comp = compagnie();
        var fs2 = filles();
        var rap = rapprocher(fs2);
        var lignes = r ? (r.souscripteurs || []) : fs2.map(function (g) {
          return { souscripteur: g.souscripteur, nbFactures: g.factures.length,
            montant: g.montant, assureur: g.assureur, patient: g.patient };
        });
        var total = r ? r.montantReclame : rap.totalFilles;

        P.etat({
          titre: 'FACTURE MÈRE — ' + (r ? r.compagnie : comp.nom).toUpperCase(),
          sousTitre: r ? r.numero : 'Aperçu — pièce non émise',
          cartouche: [
            ['Compagnie', r ? r.compagnie : comp.nom],
            ['Périodicité', r ? r.periodeLabel : pe().label],
            ['Période', C.dateFR(r ? r.debut : depuis()) + ' au ' + C.dateFR(r ? r.fin : C.iso(AUJ))],
            ['Souscripteurs consolidés', C.num(lignes.length)],
            ['Pièces filles', C.num(r ? r.nbFactures : rap.nbFactures)],
            ['Émise le', r ? C.dateFR(r.dateEmission) : '— aperçu —'],
            ['RCCM', C.BRAND.rccm],
          ],
          contenu: el('div', null, [
            el('p.mb-2.text-\\[10px\\].font-bold.uppercase', { text: 'Consolidation par souscripteur' }),
            P.tableau([
              { label: 'Souscripteur (n° de police)', key: 'souscripteur' },
              { label: 'Pièces', align: 'right', somme: function (x) { return x.nbFactures; },
                formatTotal: function (v) { return C.num(v); },
                value: function (x) { return C.num(x.nbFactures); } },
              { label: 'Montant total', align: 'right', somme: function (x) { return x.montant; },
                value: function (x) { return C.money(x.montant, false); } },
              { label: 'Part patient', align: 'right', somme: function (x) { return x.patient; },
                value: function (x) { return C.money(x.patient, false); } },
              { label: 'PART RÉCLAMÉE', align: 'right', somme: function (x) { return x.assureur; },
                value: function (x) { return C.money(x.assureur, false); } },
            ], lignes, { total: true, totalLabel: 'TOTAL GÉNÉRAL' }),
            el('p.mt-4.text-\\[10px\\]', null, [
              el('span.font-semibold', { text: 'Montant réclamé à la compagnie : ' }),
              el('span.font-bold', { text: C.money(total, false) }),
            ]),
            el('p.mt-1.text-\\[10px\\]', {
              text: C.BRAND.formuleArrete + ' : ' + C.montantEnLettres(total) + '.',
            }),
            /* Le rapprochement est PORTÉ SUR LA PIÈCE : la compagnie doit
               pouvoir constater que la mère et le détail concordent sans
               demander un second document. */
            el('p.mt-4.text-\\[9px\\].italic.text-slate-600', {
              text: 'Contrôle de concordance — total des souscripteurs : '
                + C.money(r ? r.controle.totalFilles : rap.totalFilles, false)
                + '   ·   total des pièces filles : '
                + C.money(r ? r.controle.totalFactures : rap.totalFactures, false)
                + '   ·   total du détail ligne à ligne : '
                + C.money(r ? r.controle.totalLignes : rap.totalLignes, false)
                + '. Les trois montants coïncident.',
            }),
            el('p.mt-2.text-\\[9px\\].italic.text-slate-500', {
              text: 'Le relevé détaillé par assuré et par prestation accompagne la présente facture. '
                + 'Toute contestation portant sur une ligne s’y rapporte.',
            }),
          ]),
          signatures: [
            { role: 'La Directrice de l’Administration et des Finances', mention: 'Signature et cachet' },
            { role: 'Pour la compagnie', mention: 'Reçu le / Signature' },
          ],
        });
      }
    },
  });

})(window);