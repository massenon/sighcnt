/* =============================================================================
 * M10 — Ressources Humaines
 * -----------------------------------------------------------------------------
 * CDCT §10.9 — dossiers du personnel, congés, présences, gardes et permanences,
 * évaluations mensuelles, primes diverses, prestataires externes, personnel de
 * sécurité et d'entretien.
 *
 * Deux moteurs métier versionnés, transcrits des notes de service réelles :
 *   NS 131/07/DM/DA/CNT/2026 — barème d'évaluation et de sanction (4 critères)
 *   NS 132/07/DM/DA/CNT/2026 — grille des primes diverses par fonction
 * RG-11 — les primes de garde et de permanence sont calculées à partir du
 * planning validé et de la grille en vigueur.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  function personnel() { return S.collection('personnel').active(); }
  function planning() { return S.collection('planning').active(); }

  function fonctionLabel(id) {
    var f = D.FONCTIONS.filter(function (x) { return x.id === id; })[0];
    return f ? f.label : id;
  }
  function optionsFonctions() {
    return D.FONCTIONS.map(function (f) { return { value: f.id, label: f.label }; });
  }
  function optionsEmployes() {
    return C.sortBy(personnel(), 'nomComplet').map(function (e) {
      return { value: e.id, label: e.matricule + ' — ' + e.nomComplet + ' (' + e.poste + ')' };
    });
  }
  function typePlanningLabel(id) {
    var t = D.TYPES_PLANNING.filter(function (x) { return x.id === id; })[0];
    return t ? t.label : id;
  }
  function typePlanningTone(id) {
    var t = D.TYPES_PLANNING.filter(function (x) { return x.id === id; })[0];
    return t ? t.couleur : 'neutral';
  }
  function anciennete(e) {
    var mois = Math.floor(C.daysBetween(e.dateEmbauche, AUJ) / 30.44);
    return { ans: Math.floor(mois / 12), mois: mois % 12 };
  }

  /* --- Comptage des vacations sur une période ------------------------------ */
  function vacations(employeId, annee, mois) {
    return planning().filter(function (p) {
      if (p.employeId !== employeId) return false;
      var d = C.toDate(p.date);
      return d.getFullYear() === annee && d.getMonth() === mois;
    });
  }
  function compter(employeId, annee, mois, type) {
    return vacations(employeId, annee, mois).filter(function (p) { return p.type === type; }).length;
  }

  /* ==========================================================================
   * TABLEAU DE BORD RH
   * ======================================================================== */
  global.SIGH.screen('m10-dashboard', {
    title: 'Tableau de bord — Ressources humaines',
    description: 'Effectif, plannings, présences, évaluations, primes et masse salariale.',
    render: K.dash({
      kpis: function () {
        var p = personnel();
        var auj = planning().filter(function (x) { return x.date === C.iso(AUJ); });
        return [
          { label: 'Effectif total', value: C.num(p.length), icon: 'users-round', tone: 'navy', hint: 'Organigramme de la clinique' },
          { label: 'Masse salariale (base)', value: C.money(C.sum(p, 'salaireBase')), icon: 'banknote', tone: 'info' },
          { label: 'Salaire moyen', value: C.money(p.length ? C.sum(p, 'salaireBase') / p.length : 0), icon: 'calculator', tone: 'neutral' },
          { label: 'Ancienneté moyenne', value: (p.length ? Math.round(C.sum(p, function (e) { return anciennete(e).ans; }) / p.length * 10) / 10 : 0) + ' ans', icon: 'award', tone: 'success' },
          { label: 'De garde aujourd’hui', value: C.num(auj.filter(function (x) { return x.type === 'garde'; }).length), icon: 'moon', tone: 'danger' },
          { label: 'En permanence', value: C.num(auj.filter(function (x) { return x.type === 'permanence'; }).length), icon: 'sun', tone: 'warning' },
          { label: 'En repos', value: C.num(auj.filter(function (x) { return x.type.indexOf('repos') === 0; }).length), icon: 'bed', tone: 'info' },
          { label: 'Agents à évaluer', value: C.num(p.length), icon: 'clipboard-check', tone: 'navy', hint: 'Barème NS 131' },
        ];
      },
      sections: [
        {
          render: function () {
            return K.charts([
              {
                title: 'Effectif par fonction',
                render: function () {
                  var g = C.groupBy(personnel(), 'fonction');
                  return K.ranking(Object.keys(g).map(function (k) {
                    return { label: fonctionLabel(k), value: g[k].length };
                  }).sort(function (a, b) { return b.value - a.value; }));
                },
              },
              {
                title: 'Répartition par service',
                render: function () {
                  var g = C.groupBy(personnel(), 'service');
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
                title: 'Masse salariale par service',
                render: function () {
                  var g = C.groupBy(personnel(), 'service');
                  var keys = Object.keys(g);
                  return G.barres(keys, [{ label: 'Masse salariale', data: keys.map(function (k) { return C.sum(g[k], 'salaireBase'); }) }],
                    { horizontal: true, height: 320 });
                },
              },
              {
                title: 'Planning du jour',
                render: function () {
                  var auj = planning().filter(function (x) { return x.date === C.iso(AUJ); });
                  var g = C.groupBy(auj, 'type');
                  var keys = Object.keys(g);
                  return G.anneau(keys.map(typePlanningLabel), keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          title: 'Règles métier en vigueur',
          render: function () {
            return K.miniTable([
              { label: 'Référence', render: function (n) { return el('span.font-mono.text-xs.font-semibold', { text: n.reference }); } },
              { label: 'Objet', key: 'objet' },
              { label: 'Version', render: function (n) { return 'v' + n.version; } },
              { label: 'Date d’effet', render: function (n) { return C.dateFR(n.dateEffet); } },
              { label: 'Statut', render: function (n) { return U.badge(n.statut, 'success'); } },
              { label: 'Signataire', key: 'signataire' },
            ], [D.NS131, D.NS132]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm10-planning', icon: 'calendar-days', label: 'Planning & gardes', detail: 'Garde 24h, permanence, repos' },
              { id: 'm10-evaluations', icon: 'clipboard-check', label: 'Évaluations', detail: 'Barème NS 131' },
              { id: 'm10-primes', icon: 'gift', label: 'Primes', detail: 'Grille NS 132' },
              { id: 'm11-calcul', icon: 'calculator', label: 'Calcul de la paie', detail: 'CNSS, ITS, VPS' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * PERSONNEL
   * ======================================================================== */
  function ficheEmploye(e) {
    var a = anciennete(e);
    var wrap = el('div.space-y-4');

    wrap.appendChild(el('div.flex.items-start.gap-3.rounded-lg.bg-navy-50.p-3', null, [
      el('span.grid.h-12.w-12.shrink-0.place-items-center.rounded-full.bg-navy-900.text-sm.font-semibold.text-white', { text: C.initials(e.nomComplet) }),
      el('div.min-w-0.flex-1', null, [
        el('p.text-sm.font-semibold.text-slate-900', { text: e.nomComplet }),
        el('p.text-xs.text-navy-700', { text: e.poste }),
        el('p.mt-1.text-xs.text-slate-500', { text: 'Matricule ' + e.matricule + ' — ' + e.service + ' — catégorie ' + e.categorie }),
      ]),
    ]));

    var mois = AUJ.getMonth(), annee = AUJ.getFullYear();
    var gardes = compter(e.id, annee, mois, 'garde');
    var permanences = compter(e.id, annee, mois, 'permanence');

    wrap.appendChild(U.tabs([
      {
        id: 'infos', label: 'Informations',
        render: function () {
          return U.descList([
            ['Matricule', e.matricule], ['Nom et prénoms', e.nomComplet],
            ['Sexe', e.sexe === 'F' ? 'Féminin' : 'Masculin'],
            ['Fonction', fonctionLabel(e.fonction)], ['Poste', e.poste],
            ['Service', e.service], ['Catégorie / échelon', e.categorie],
            ['Date d’embauche', C.dateFR(e.dateEmbauche)],
            ['Ancienneté', a.ans + ' an(s) ' + a.mois + ' mois'],
            ['Numéro CNSS', e.cnss], ['Téléphone', e.telephone],
            ['Situation matrimoniale', e.situation],
            ['Salaire de base', C.money(e.salaireBase)],
          ]);
        },
      },
      {
        id: 'planning', label: 'Planning du mois',
        render: function () {
          var v = C.sortBy(vacations(e.id, annee, mois), 'date');
          if (!v.length) return U.empty('Aucune vacation programmée ce mois-ci.', { icon: 'calendar' });
          return el('div.space-y-3', null, [
            U.kpiGrid([
              { label: 'Gardes', value: C.num(gardes), icon: 'moon', tone: 'danger' },
              { label: 'Permanences', value: C.num(permanences), icon: 'sun', tone: 'warning' },
            ], 'grid-cols-2'),
            K.miniTable([
              { label: 'Date', render: function (p) { return C.dateJour(p.date); } },
              { label: 'Vacation', render: function (p) { return U.badge(typePlanningLabel(p.type), typePlanningTone(p.type)); } },
              { label: 'Statut', render: function (p) { return U.statut(p.statut === 'validee' ? 'validee' : 'brouillon'); } },
            ], v),
          ]);
        },
      },
      {
        id: 'primes', label: 'Primes (NS 132)',
        render: function () {
          var lignes = D.NS132.primes.map(function (pr) {
            var montant = D.NS132.montant(pr.id, e.fonction);
            if (!montant) return null;
            var nb = pr.mode === 'fixe' ? 1 : (pr.id === 'garde' ? gardes : (pr.id === 'permanence' ? permanences : 0));
            return { prime: pr.label, mode: pr.mode === 'fixe' ? 'Forfait mensuel' : 'Par occurrence', montant: montant, nb: nb, total: montant * nb };
          }).filter(Boolean);
          if (!lignes.length) return U.empty('Aucune prime prévue pour cette fonction par la note NS 132.', { icon: 'gift' });
          return el('div.space-y-3', null, [
            K.note('Grille issue de la note de service <strong>' + D.NS132.reference + '</strong>, en vigueur depuis le ' + C.dateFR(D.NS132.dateEffet) + '.', { tone: 'info' }),
            K.miniTable([
              { label: 'Prime', key: 'prime' },
              { label: 'Mode', key: 'mode' },
              { label: 'Montant unitaire', align: 'right', render: function (l) { return C.money(l.montant, false); } },
              { label: 'Nombre', align: 'right', key: 'nb' },
              { label: 'Total du mois', align: 'right', render: function (l) { return el('span.font-semibold', { text: C.money(l.total, false) }); } },
            ], lignes),
          ]);
        },
      },
      {
        id: 'presences', label: 'Présences & congés',
        render: function () {
          var pres = S.collection('presences').active().filter(function (x) { return x.employeId === e.id; });
          var cong = S.collection('conges').active().filter(function (x) { return x.employeId === e.id; });
          var box = el('div.space-y-3');
          box.appendChild(U.card('Présences et absences', pres.length
            ? K.miniTable([
              { label: 'Date', render: function (x) { return C.dateFR(x.date); } },
              { label: 'État', render: function (x) { return U.statut(x.etat || x.statutPresence || 'valide'); } },
              { label: 'Arrivée', render: function (x) { return x.heureArrivee || '—'; } },
              { label: 'Observation', render: function (x) { return x.observation || '—'; } },
            ], C.sortBy(pres, 'date', 'desc').slice(0, 15))
            : U.empty('Aucun relevé de présence.', { icon: 'calendar-check' })));
          box.appendChild(U.card('Congés', cong.length
            ? K.miniTable([
              { label: 'Type', render: function (x) { return x.type || x.typeConge || '—'; } },
              { label: 'Du', render: function (x) { return C.dateFR(x.dateDebut); } },
              { label: 'Au', render: function (x) { return C.dateFR(x.dateFin); } },
              { label: 'Jours', align: 'right', render: function (x) { return String(x.jours || '—'); } },
              { label: 'État', render: function (x) { return U.statut(x.statutConge || 'valide'); } },
            ], C.sortBy(cong, 'dateDebut', 'desc'))
            : U.empty('Aucun congé enregistré.', { icon: 'palmtree' })));
          return box;
        },
      },
      {
        id: 'evaluations', label: 'Évaluations & sanctions',
        render: function () {
          var evs = S.collection('evaluations').active().filter(function (x) { return x.employeId === e.id; });
          if (!evs.length) return U.empty('Aucune évaluation NS 131 enregistrée.', { icon: 'clipboard-check' });
          var sanctions = evs.filter(function (x) { return (x.prelevementPct || 0) > 0; });
          return el('div.space-y-3', null, [
            sanctions.length
              ? K.note('<strong>' + sanctions.length + ' évaluation(s) ayant entraîné une retenue.</strong> '
                + 'La retenue découle du barème NS 131 ; elle se corrige en modifiant l’évaluation.',
              { tone: 'warning', icon: 'triangle-alert' })
              : K.note('Aucune retenue sur la période — évaluations conformes au barème NS 131.', { tone: 'success', icon: 'check-circle-2' }),
            K.miniTable([
              { label: 'Période', render: function (x) { return x.periode || C.dateFR(x.date); } },
              { label: 'Note', align: 'right', render: function (x) { return (x.note != null ? x.note : '—') + ' / 20'; } },
              {
                label: 'Retenue', align: 'right',
                render: function (x) {
                  return (x.prelevementPct || 0) > 0
                    ? el('span.font-semibold.text-danger-600', { text: x.prelevementPct + ' %' })
                    : U.badge('Aucune', 'success');
                },
              },
              { label: 'Évaluateur', render: function (x) { return x.evaluateur || '—'; } },
            ], C.sortBy(evs, 'date', 'desc').slice(0, 12)),
          ]);
        },
      },
      {
        id: 'assurances', label: 'Assurances',
        render: function () {
          /* Le personnel a ses propres couvertures — CNSS, mutuelle, accident du
             travail. Elles relèvent du dossier RH et n'ont rien à voir avec les
             recettes de la clinique : les y mêler fausserait les deux. */
          var col = S.collection('assurancesPersonnel', { module: 'M10', entite: 'assurance du personnel' });
          var champs = [
            {
              name: 'type', label: 'Type de couverture', type: 'select', required: true,
              options: ['CNSS — régime général', 'Mutuelle de santé', 'Assurance accident du travail',
                'Assurance maladie complémentaire', 'Assurance vie', 'Prise en charge clinique (personnel)'],
            },
            { name: 'organisme', label: 'Organisme', required: true, col: 'full' },
            { name: 'numeroAdhesion', label: 'N° d’adhésion', required: true },
            { name: 'taux', label: 'Taux de couverture (%)', type: 'number', min: 0, max: 100 },
            { name: 'dateDebut', label: 'Début de validité', type: 'date', required: true },
            { name: 'dateFin', label: 'Fin de validité', type: 'date' },
            { name: 'beneficiaires', label: 'Ayants droit couverts', type: 'number', min: 0 },
            { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
          ];
          var hote = el('div.space-y-3');
          dessinerAss();
          return hote;

          function dessinerAss() {
            C.clear(hote);
            var rows = col.active().filter(function (x) { return x.employeId === e.id; });
            hote.appendChild(K.note('Couvertures de l’agent — <strong>dossier RH</strong>. '
              + 'Elles ne figurent pas dans les recettes de la clinique.', { tone: 'info', icon: 'shield-check' }));
            hote.appendChild(U.dataTable({
              rows: rows, exportName: 'assurances-personnel', pageSize: 8,
              emptyMessage: 'Aucune couverture enregistrée pour cet agent.',
              columns: [
                { key: 'type', label: 'Couverture', render: function (x) { return U.badge(x.type, 'navy'); } },
                { key: 'organisme', label: 'Organisme' },
                { key: 'numeroAdhesion', label: 'N° d’adhésion', nowrap: true, render: function (x) { return el('span.font-mono.text-xs', { text: x.numeroAdhesion }); } },
                { key: 'taux', label: 'Taux', align: 'right', render: function (x) { return x.taux != null ? x.taux + ' %' : '—'; } },
                {
                  key: 'dateDebut', label: 'Validité', nowrap: true,
                  render: function (x) {
                    var expire = x.dateFin && C.toDate(x.dateFin) < AUJ;
                    return el('span', {
                      class: expire ? 'text-xs font-semibold text-danger-600' : 'text-xs text-slate-600',
                      text: C.dateFR(x.dateDebut) + (x.dateFin ? ' → ' + C.dateFR(x.dateFin) : ' → en cours'),
                    });
                  },
                },
                { key: 'beneficiaires', label: 'Ayants droit', align: 'right', render: function (x) { return x.beneficiaires != null ? String(x.beneficiaires) : '—'; } },
              ],
              rowActions: K.actionsLigne(col, champs, { entite: 'couverture' }),
              actions: [K.creer(col, champs, {
                titre: 'Nouvelle couverture', entite: 'Couverture',
                defauts: function () { return { dateDebut: C.iso(AUJ), taux: 80, beneficiaires: 0 }; },
                transform: function (v) { v.employeId = e.id; v.agent = e.nomComplet; return v; },
                apres: dessinerAss,
              })],
            }));
            U.icons(hote);
          }
        },
      },
    ]));
    return wrap;
  }

  global.SIGH.screen('m10-personnel', {
    title: 'Personnel',
    description: 'Dossiers des agents : identité, fonction, catégorie, ancienneté, numéro CNSS et rémunération de base.',
    render: K.crud({
      collection: 'personnel', entite: 'agent', entiteP: 'agents', module: 'M10',
      defaultSort: 'matricule', pageSize: 15, drawerWidth: 'max-w-3xl',
      source: 'Organigramme de la Clinique NASSIERA TOO.',
      columns: [
        { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true, render: function (e) { return el('span.font-mono.text-xs.font-semibold', { text: e.matricule }); } },
        {
          key: 'nomComplet', label: 'Agent',
          render: function (e) {
            return el('div.flex.items-center.gap-2', null, [
              el('span.grid.h-7.w-7.shrink-0.place-items-center.rounded-full.bg-slate-100.text-\\[10px\\].font-semibold.text-slate-600', { text: C.initials(e.nomComplet) }),
              el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: e.nomComplet }),
                el('p.truncate.text-xs.text-slate-400', { text: e.poste }),
              ]),
            ]);
          },
        },
        { key: 'fonction', label: 'Fonction', text: fonctionLabel, render: function (e) { return U.badge(fonctionLabel(e.fonction), 'navy'); } },
        { key: 'service', label: 'Service' },
        { key: 'categorie', label: 'Cat./Éch.', align: 'right' },
        {
          key: 'anciennete', label: 'Ancienneté', align: 'right',
          value: function (e) { return C.daysBetween(e.dateEmbauche, AUJ); },
          text: function (e) { var a = anciennete(e); return a.ans + ' ans ' + a.mois + ' mois'; },
          render: function (e) { var a = anciennete(e); return a.ans + ' a. ' + a.mois + ' m.'; },
        },
        { key: 'cnss', label: 'N° CNSS', nowrap: true, render: function (e) { return el('span.font-mono.text-xs.text-slate-500', { text: e.cnss }); } },
        {
          key: 'salaireBase', label: 'Salaire de base', align: 'right',
          text: function (e) { return C.money(e.salaireBase, false); },
          render: function (e) { return el('span.font-semibold', { text: C.money(e.salaireBase, false) }); },
        },
      ],
      fields: [
        { type: 'section', label: 'Identité' },
        { name: 'matricule', label: 'Matricule', required: true },
        { name: 'nom', label: 'Nom', required: true },
        { name: 'prenom', label: 'Prénom(s)', required: true },
        { name: 'sexe', label: 'Sexe', type: 'select', required: true, options: [{ value: 'M', label: 'Masculin' }, { value: 'F', label: 'Féminin' }] },
        { name: 'telephone', label: 'Téléphone', type: 'tel' },
        { name: 'situation', label: 'Situation matrimoniale', type: 'select', options: ['Célibataire', 'Marié(e)', 'Divorcé(e)', 'Veuf(ve)'] },
        { type: 'section', label: 'Affectation' },
        { name: 'fonction', label: 'Fonction', type: 'select', required: true, options: optionsFonctions() },
        { name: 'poste', label: 'Poste occupé', col: 'full' },
        { name: 'service', label: 'Service', type: 'select', required: true, options: D.SERVICES },
        { name: 'categorie', label: 'Catégorie / échelon', placeholder: 'ex. E3-1' },
        { name: 'dateEmbauche', label: 'Date d’embauche', type: 'date', required: true },
        { type: 'section', label: 'Rémunération et couverture sociale' },
        { name: 'salaireBase', label: 'Salaire de base (FCFA)', type: 'money', required: true, min: 0 },
        { name: 'cnss', label: 'Numéro CNSS' },
      ],
      transform: function (v) { v.nomComplet = v.nom + ' ' + v.prenom; return v; },
      onCreate: function () { return { dateEmbauche: C.iso(AUJ), salaireBase: 60000, categorie: 'E1-1', sexe: 'F' }; },
      filters: [
        { name: 'fonction', label: 'Fonction', options: optionsFonctions() },
        { name: 'service', label: 'Service', options: D.SERVICES },
        { name: 'sexe', label: 'Sexe', options: [{ value: 'M', label: 'Masculin' }, { value: 'F', label: 'Féminin' }] },
      ],
      kpis: function (rows) {
        return [
          { label: 'Effectif', value: C.num(rows.length), icon: 'users-round', tone: 'navy' },
          { label: 'Masse salariale', value: C.money(C.sum(rows, 'salaireBase')), icon: 'banknote', tone: 'info' },
          { label: 'Salaire moyen', value: C.money(rows.length ? C.sum(rows, 'salaireBase') / rows.length : 0), icon: 'calculator', tone: 'neutral' },
          { label: 'Femmes / Hommes', value: C.num(rows.filter(function (e) { return e.sexe === 'F'; }).length) + ' / ' + C.num(rows.filter(function (e) { return e.sexe === 'M'; }).length), icon: 'users', tone: 'success' },
        ];
      },
      detail: ficheEmploye,
      etat: function (e) {
        var a = anciennete(e);
        P.etat({
          titre: 'Fiche individuelle de l’agent',
          sousTitre: e.nomComplet + ' — matricule ' + e.matricule,
          cartouche: [['Matricule', e.matricule], ['Nom et prénoms', e.nomComplet],
            ['Fonction', fonctionLabel(e.fonction)], ['Service', e.service],
            ['Catégorie / échelon', e.categorie], ['Ancienneté', a.ans + ' an(s) ' + a.mois + ' mois']],
          contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
            { k: 'Sexe', v: e.sexe === 'F' ? 'Féminin' : 'Masculin' },
            { k: 'Situation matrimoniale', v: e.situation },
            { k: 'Téléphone', v: e.telephone },
            { k: 'Date d’embauche', v: C.dateFR(e.dateEmbauche) },
            { k: 'Poste occupé', v: e.poste },
            { k: 'Numéro CNSS', v: e.cnss },
            { k: 'Salaire de base', v: C.money(e.salaireBase) },
          ]),
          signatures: [{ role: 'L’Agent', nom: e.nomComplet }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      },
    }),
  });

  /* ==========================================================================
   * FICHE EMPLOYÉ (consultation dédiée)
   * ======================================================================== */
  global.SIGH.screen('m10-employe-profil', {
    title: 'Fiche employé',
    description: 'Vue consolidée d’un agent : informations, planning, primes applicables et historique.',
    render: function (root) {
      var agents = C.sortBy(personnel(), 'matricule');
      var host = el('div.space-y-4');
      var courant = agents[0];

      var barre = el('div.card');
      var bbody = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      var sel = U.combo(agents.map(function (e) {
        return { value: e.id, label: e.nomComplet, detail: 'Mat. ' + e.matricule + ' — ' + e.poste, icon: 'id-card' };
      }), {
        value: agents.length ? agents[0].id : '',
        searchPlaceholder: 'Nom, matricule ou poste…',
        placeholder: 'Choisir un agent',
      });
      sel.classList.add('max-w-lg');
      bbody.appendChild(el('div.flex-1', null, [el('label.label', { text: 'Agent' }), sel]));
      bbody.appendChild(K.lien('m10-personnel', 'Retour à la liste', { icon: 'arrow-left' }));
      barre.appendChild(bbody);
      host.appendChild(barre);

      var carte = el('div.card');
      var corps = el('div.card-body');
      carte.appendChild(corps);
      host.appendChild(carte);

      function afficher() {
        courant = agents.filter(function (e) { return e.id === sel.value; })[0] || agents[0];
        C.clear(corps);
        if (!courant) { corps.appendChild(U.empty('Aucun agent enregistré.', { icon: 'users' })); return; }
        corps.appendChild(ficheEmploye(courant));
        U.icons(corps);
      }
      sel.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;
    },
  });

  /* ==========================================================================
   * CONTRATS
   * ======================================================================== */
  global.SIGH.screen('m10-contrats', {
    title: 'Contrats',
    description: 'Contrats de travail des agents : nature, durée, période d’essai et échéances.',
    render: function (root) {
      var col = S.collection('contrats', { module: 'M10', entite: 'Contrat' });
      if (!col.all().length) {
        var rnd = C.seeded(1217);
        personnel().forEach(function (e, i) {
          var cdd = rnd() > 0.7;
          col.all().push({
            id: 'CTR' + C.pad(i + 1, 4), statut: 'actif',
            reference: 'CT-' + C.pad(i + 1, 4),
            employeId: e.id, employe: e.nomComplet, matricule: e.matricule,
            fonction: e.fonction, poste: e.poste,
            nature: cdd ? 'CDD' : 'CDI',
            dateDebut: e.dateEmbauche,
            dateFin: cdd ? C.iso(C.addDays(e.dateEmbauche, 365 * C.between(rnd, 1, 3))) : null,
            essai: C.pick(rnd, ['1 mois', '3 mois', '6 mois']),
            salaire: e.salaireBase,
            statutContrat: 'en_vigueur',
          });
        });
        S.save();
      }

      return K.crud({
        collection: 'contrats', entite: 'contrat', entiteP: 'contrats', module: 'M10',
        defaultSort: 'dateDebut', defaultDir: 'desc', pageSize: 15,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (c) { return el('span.font-mono.text-xs', { text: c.reference }); } },
          { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true },
          { key: 'employe', label: 'Agent' },
          { key: 'poste', label: 'Poste' },
          { key: 'nature', label: 'Nature', render: function (c) { return U.badge(c.nature, c.nature === 'CDI' ? 'success' : 'warning'); } },
          { key: 'dateDebut', label: 'Début', nowrap: true, text: function (c) { return C.dateFR(c.dateDebut); }, render: function (c) { return C.dateFR(c.dateDebut); } },
          {
            key: 'dateFin', label: 'Échéance', nowrap: true,
            text: function (c) { return c.dateFin ? C.dateFR(c.dateFin) : 'Indéterminée'; },
            render: function (c) {
              if (!c.dateFin) return el('span.text-xs.text-slate-400', { text: 'Indéterminée' });
              var j = C.daysBetween(AUJ, c.dateFin);
              if (j < 0) return U.badge('Échu', 'danger');
              if (j <= 90) return U.badge('Dans ' + j + ' j', 'warning');
              return C.dateFR(c.dateFin);
            },
          },
          { key: 'essai', label: 'Période d’essai' },
          { key: 'salaire', label: 'Salaire', align: 'right', text: function (c) { return C.money(c.salaire, false); }, render: function (c) { return C.money(c.salaire, false); } },
        ],
        fields: function () {
          return [
            { name: 'employeId', label: 'Agent', type: 'select', required: true, options: optionsEmployes(), col: 'full' },
            { name: 'nature', label: 'Nature du contrat', type: 'select', required: true, options: ['CDI', 'CDD', 'Stage', 'Prestation'] },
            { name: 'dateDebut', label: 'Date de début', type: 'date', required: true },
            { name: 'dateFin', label: 'Date de fin (CDD)', type: 'date' },
            { name: 'essai', label: 'Période d’essai', type: 'select', options: ['1 mois', '3 mois', '6 mois'] },
            { name: 'salaire', label: 'Salaire mensuel (FCFA)', type: 'money', required: true, min: 0 },
          ];
        },
        transform: function (v) {
          var e = personnel().filter(function (x) { return x.id === v.employeId; })[0];
          if (e) { v.employe = e.nomComplet; v.matricule = e.matricule; v.poste = e.poste; v.fonction = e.fonction; }
          if (!v.reference) v.reference = C.nextRef('CT-', 4);
          v.statutContrat = 'en_vigueur';
          return v;
        },
        filters: [{ name: 'nature', label: 'Nature', options: ['CDI', 'CDD', 'Stage', 'Prestation'] }],
        kpis: function (rows) {
          var echeance = rows.filter(function (c) { return c.dateFin && C.daysBetween(AUJ, c.dateFin) >= 0 && C.daysBetween(AUJ, c.dateFin) <= 90; });
          return [
            { label: 'Contrats en vigueur', value: C.num(rows.length), icon: 'file-signature', tone: 'navy' },
            { label: 'CDI', value: C.num(rows.filter(function (c) { return c.nature === 'CDI'; }).length), icon: 'shield-check', tone: 'success' },
            { label: 'CDD', value: C.num(rows.filter(function (c) { return c.nature === 'CDD'; }).length), icon: 'clock', tone: 'warning' },
            { label: 'Échéances sous 90 jours', value: C.num(echeance.length), icon: 'calendar-clock', tone: echeance.length ? 'danger' : 'neutral' },
          ];
        },
        etat: function (c) {
          P.etat({
            titre: 'Contrat de travail',
            sousTitre: c.nature + ' — ' + c.employe,
            cartouche: [['Référence', c.reference], ['Agent', c.employe], ['Matricule', c.matricule],
              ['Poste', c.poste], ['Nature', c.nature], ['Date de début', C.dateFR(c.dateDebut)]],
            contenu: el('div.space-y-3', null, [
              el('p', { text: 'Entre la CLINIQUE NASSIERA TOO SARL, représentée par sa Directrice Administrative, ci-après dénommée « l’Employeur », d’une part,' }),
              el('p', { text: 'Et ' + c.employe + ', matricule ' + c.matricule + ', ci-après dénommé(e) « l’Employé(e) », d’autre part,' }),
              el('p.mt-2.font-semibold', { text: 'Il a été convenu ce qui suit :' }),
              P.tableau([{ label: 'Article', key: 'k' }, { label: 'Disposition', key: 'v' }], [
                { k: 'Article 1 — Objet', v: 'Engagement au poste de ' + c.poste + '.' },
                { k: 'Article 2 — Nature', v: 'Contrat à durée ' + (c.nature === 'CDI' ? 'indéterminée' : 'déterminée') + (c.dateFin ? ', prenant fin le ' + C.dateFR(c.dateFin) : '') + '.' },
                { k: 'Article 3 — Prise d’effet', v: 'Le présent contrat prend effet le ' + C.dateFR(c.dateDebut) + '.' },
                { k: 'Article 4 — Période d’essai', v: (c.essai || '3 mois') + ', renouvelable une fois.' },
                { k: 'Article 5 — Rémunération', v: 'Salaire mensuel de base de ' + C.money(c.salaire) + ', auquel s’ajoutent les primes prévues par la note de service en vigueur (NS 132).' },
                { k: 'Article 6 — Obligations', v: 'L’Employé(e) est soumis(e) au règlement intérieur et au barème d’évaluation en vigueur (NS 131).' },
              ]),
            ]),
            signatures: [{ role: 'L’Employé(e)', nom: c.employe, mention: 'Lu et approuvé' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * PLANNING & GARDES
   * ======================================================================== */
  global.SIGH.screen('m10-planning', {
    title: 'Planning & gardes',
    description: 'Planification des gardes, permanences et repos, avec contrôle des incompatibilités.',
    regle: 'Chaque catégorie applique son propre régime, relevé sur les plannings de la clinique : '
      + 'garde de 24 h (08h→08h), garde soins de 08h à 18h30, permanence de 08h à 18h, soirée de 18h à 8h, '
      + 'entretien général de la journée, repos de 24 h ou 48 h. '
      + 'Le système <strong>empêche de programmer une garde incompatible</strong> avec le repos obligatoire qui la suit.',
    render: function (root) {
      var col = S.collection('planning', { module: 'M10', entite: 'Planning' });
      var host = el('div.space-y-4');
      var semaineDebut = C.addDays(AUJ, -3);
      var blocRegimes = el('div');
      var blocRegistre = el('div');
      var blocGraphes = el('div');

      host.appendChild(blocRegimes);
      rendreRegimes();

      /* Régimes de travail par catégorie, tels que relevés sur les plannings */
      function tableRegimes() {
        return K.miniTable([
        { label: 'Catégorie', key: 'libelle' },
        {
          label: 'Vacations',
          render: function (r) {
            return el('div.flex.flex-wrap.gap-1', null, r.vacations.map(function (v) {
              var t = D.TYPES_PLANNING.filter(function (x) { return x.id === v; })[0];
              return U.badge(t ? t.label : v, t ? t.couleur : 'neutral');
            }));
          },
        },
        {
          label: 'Horaires',
          render: function (r) {
            return el('div', null, r.vacations.map(function (v) {
              var t = D.TYPES_PLANNING.filter(function (x) { return x.id === v; })[0];
              return el('p.text-xs.text-slate-500', { text: t ? (t.court + ' : ' + t.debut + ' → ' + t.fin) : v });
            }));
          },
        },
        {
          label: 'Repos',
          render: function (r) {
            if (!r.repos) return el('span.text-xs.text-slate-400', { text: 'Sans repos codifié' });
            var t = D.TYPES_PLANNING.filter(function (x) { return x.id === r.repos; })[0];
            return U.badge(t ? t.label : r.repos, 'neutral');
          },
        },
          {
            label: 'Honoraire', align: 'right',
            render: function (r) {
              if (!r.honoraire) return el('span.text-xs.text-slate-300', { text: '—' });
              return el('div.text-right', null, [
                el('span.text-sm.font-semibold.text-slate-800', { text: C.money(r.honoraire, false) }),
                el('p.text-xs.text-slate-400', { text: r.honorairePeriodicite || 'mensuelle' }),
              ]);
            },
          },
          { label: 'Cycle', align: 'right', render: function (r) { return r.cycle + ' jours'; } },
          { label: 'Source', render: function (r) { return el('span.text-xs.text-slate-400', { text: r.source }); } },
          {
            label: '', align: 'right',
            render: function (r) {
              var actes = [];
              if (K.droits('M10').editer) {
                actes.push(K.iconBtn('pencil', 'Modifier ce régime', function () { editerRegime(r); }));
              }
              if (K.droits('M10').annuler) {
                actes.push(K.iconBtn('archive', 'Archiver ce régime', function () { archiverRegime(r); }, 'ghost'));
              }
              return el('div.flex.justify-end.gap-1', null, actes);
            },
          },
        ], colRegimes().active());
      }

      function rendreRegimes() {
        C.clear(blocRegimes);
        var actions = [];
        if (K.droits('M10').editer) {
          actions.push(K.btn('Nouveau régime', {
            variant: 'primary', size: 'sm', icon: 'plus',
            onclick: function () { editerRegime(null); },
          }));
        }
        blocRegimes.appendChild(U.card('Régimes de travail par catégorie', tableRegimes(), actions));
        U.icons(blocRegimes);
      }

      /* Légende des vacations */
      var legende = el('div.flex.flex-wrap.items-center.gap-4.rounded-lg.border.border-slate-200.bg-white.px-4.py-2\\.5');
      legende.appendChild(el('span.text-xs.font-medium.text-slate-500', { text: 'Légende :' }));
      D.TYPES_PLANNING.forEach(function (t) {
        legende.appendChild(el('span.flex.items-center.gap-1\\.5', null, [
          el('span.h-2\\.5.w-2\\.5.rounded-full', { class: 'bg-' + t.couleur + '-500' }),
          el('span.text-xs.text-slate-600', { text: t.court + ' — ' + t.label }),
        ]));
      });
      host.appendChild(legende);

      var auj = col.active().filter(function (p) { return p.date === C.iso(AUJ); });
      host.appendChild(U.kpiGrid([
        { label: 'Vacations planifiées', value: C.num(col.active().length), icon: 'calendar-days', tone: 'navy' },
        { label: 'De garde aujourd’hui', value: C.num(auj.filter(function (p) { return p.type === 'garde'; }).length), icon: 'moon', tone: 'danger' },
        { label: 'En permanence', value: C.num(auj.filter(function (p) { return p.type === 'permanence'; }).length), icon: 'sun', tone: 'warning' },
        { label: 'En repos', value: C.num(auj.filter(function (p) { return p.type.indexOf('repos') === 0; }).length), icon: 'bed', tone: 'info' },
      ]));

      /* Grille hebdomadaire */
      var jours = [];
      for (var i = 0; i < 7; i++) jours.push(C.addDays(semaineDebut, i));
      var agents = C.sortBy(personnel().filter(function (e) {
        return ['medecin', 'infirmier', 'sage_femme', 'aide_soignant', 'tsl', 'securite', 'entretien'].indexOf(e.fonction) !== -1;
      }), 'nomComplet');

      var grilleWrap = el('div.overflow-x-auto');
      var grille = el('table.tbl.min-w-\\[60rem\\]');
      var thead = el('thead'), htr = el('tr');
      htr.appendChild(el('th', { text: 'Agent' }));
      jours.forEach(function (j) {
        htr.appendChild(el('th.text-center', {
          class: C.iso(j) === C.iso(AUJ) ? 'bg-navy-50 text-navy-800' : '',
          html: C.JOURS[j.getDay()].slice(0, 3) + '.<br>' + j.getDate() + '/' + C.pad(j.getMonth() + 1),
        }));
      });
      thead.appendChild(htr); grille.appendChild(thead);
      var tb = el('tbody');
      agents.forEach(function (e) {
        var tr = el('tr');
        tr.appendChild(el('td', null, el('div.min-w-0', null, [
          el('p.truncate.text-sm.font-medium.text-slate-800', { text: e.nomComplet }),
          el('p.truncate.text-xs.text-slate-400', { text: fonctionLabel(e.fonction) }),
        ])));
        jours.forEach(function (j) {
          var v = col.active().filter(function (p) { return p.employeId === e.id && p.date === C.iso(j); })[0];
          var td = el('td.text-center');
          var btn = el('button.mx-auto.block.w-full.rounded.px-1.py-1.text-\\[10px\\].font-medium.transition-colors', {
            type: 'button',
            class: v ? ('bg-' + typePlanningTone(v.type) + '-100 text-' + typePlanningTone(v.type) + '-800 hover:bg-' + typePlanningTone(v.type) + '-200')
              : 'text-slate-300 hover:bg-slate-100',
            text: v ? typePlanningLabel(v.type).replace('Permanence', 'Perm.').replace('Remplacement', 'Rempl.') : '+',
            onclick: function () { affecter(e, j, v); },
          });
          td.appendChild(btn);
          tr.appendChild(td);
        });
        tb.appendChild(tr);
      });
      grille.appendChild(tb);
      grilleWrap.appendChild(grille);

      host.appendChild(U.card('Planning du ' + C.dateFR(jours[0]) + ' au ' + C.dateFR(jours[6]), grilleWrap, [
        K.btn('Imprimer le planning', { size: 'sm', icon: 'printer', onclick: imprimer }),
      ]));

      host.appendChild(blocRegistre);
      host.appendChild(blocGraphes);
      rendreRegistre();
      rendreGraphes();
      root.appendChild(host);
      return null;

      function colRegimes() {
        return S.collection('regimesTravail', { module: 'M10', entite: 'régime de travail', prefix: 'REG' });
      }

      /** Le régime applicable à une fonction, lu dans le magasin. */
      function regleDe(fonction) {
        var r = colRegimes().active().filter(function (x) {
          return (x.fonctions || []).indexOf(fonction) !== -1;
        })[0];
        return r || D.regleDe(fonction);
      }

      function rendreRegistre() {
        C.clear(blocRegistre);
        blocRegistre.appendChild(U.dataTable({
        title: 'Registre des vacations',
        rows: function () { return col.active(); },
        exportName: 'planning', pageSize: 15,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'type', label: 'Type de vacation', options: D.TYPES_PLANNING.map(function (t) { return { value: t.id, label: t.label }; }) },
          { name: 'service', label: 'Service', options: D.SERVICES },
        ],
        columns: [
          { key: 'date', label: 'Date', nowrap: true, text: function (p) { return C.dateFR(p.date); }, render: function (p) { return C.dateFR(p.date); } },
          { key: 'employe', label: 'Agent' },
          { key: 'fonction', label: 'Fonction', text: fonctionLabel, render: function (p) { return fonctionLabel(p.fonction); } },
          { key: 'service', label: 'Service' },
          { key: 'type', label: 'Vacation', text: typePlanningLabel, render: function (p) { return U.badge(typePlanningLabel(p.type), typePlanningTone(p.type)); } },
          {
            key: 'regime', label: 'Régime appliqué',
            value: function (p) { return p.regimeLibelle || (regleDe(p.fonction) || {}).libelle || '—'; },
            render: function (p) {
              var lib = p.regimeLibelle || (regleDe(p.fonction) || {}).libelle;
              if (!lib) return el('span.text-xs.text-slate-300', { text: '—' });
              return el('span.text-xs.text-slate-500', { text: lib });
            },
          },
          { key: 'statut2', label: 'Statut', value: function (p) { return p.statut; }, render: function (p) { return U.statut('validee'); } },
        ],
        }));
        U.icons(blocRegistre);
      }

      /* --------------------------------------------------------------------
       * Graphiques — la charge de garde vue sous trois angles.
       * ------------------------------------------------------------------ */
      function rendreGraphes() {
        C.clear(blocGraphes);
        var vacations = col.active().filter(function (v) {
          return ['garde', 'garde_hospi', 'garde_soins', 'soiree', 'permanence', 'incineration'].indexOf(v.type) !== -1;
        });

        var parAgent = C.groupBy(vacations, 'employe');
        var agentsTries = Object.keys(parAgent)
          .map(function (k) { return { label: k, n: parAgent[k].length }; })
          .sort(function (a, b) { return b.n - a.n; }).slice(0, 10);

        var parService = C.groupBy(vacations, function (v) { return v.service || 'Non renseigné'; });
        var parType = C.groupBy(vacations, 'type');

        var grille = el('div.grid.gap-4.lg\:grid-cols-3');
        grille.appendChild(U.card('Gardes par agent — les dix premiers',
          agentsTries.length
            ? G.barres(agentsTries.map(function (a) { return a.label; }),
              [{ label: 'Vacations', data: agentsTries.map(function (a) { return a.n; }), color: '#12315e' }],
              { horizontal: true, height: 260 })
            : U.empty('Aucune vacation enregistrée.', { icon: 'calendar-x' })));

        grille.appendChild(U.card('Gardes par service',
          Object.keys(parService).length
            ? G.camembert(Object.keys(parService),
              Object.keys(parService).map(function (k) { return parService[k].length; }), { height: 260 })
            : U.empty('Aucune vacation enregistrée.', { icon: 'calendar-x' })));

        grille.appendChild(U.card('Gardes par type de vacation',
          Object.keys(parType).length
            ? G.barres(Object.keys(parType).map(typePlanningLabel),
              [{ label: 'Vacations', data: Object.keys(parType).map(function (k) { return parType[k].length; }), color: '#3765a6' }],
              { height: 260 })
            : U.empty('Aucune vacation enregistrée.', { icon: 'calendar-x' })));

        blocGraphes.appendChild(grille);
        blocGraphes.appendChild(K.note('Ces répartitions portent sur les vacations <strong>travaillées</strong> — '
          + 'gardes, soirées, permanences et incinération. Les repos et congés en sont exclus : les compter '
          + 'ferait apparaître comme les plus chargés les agents les plus reposés. '
          + 'Le détail par période se consulte à l’écran <em>Statistiques de garde</em>.',
        { tone: 'info' }));
        U.icons(blocGraphes);
      }

      /* --------------------------------------------------------------------
       * CRUD des régimes de travail.
       * ------------------------------------------------------------------ */
      function champsRegime() {
        return [
          { name: 'libelle', label: 'Catégorie', type: 'text', required: true, col: 'full' },
          {
            name: 'fonctions', label: 'Fonctions concernées', type: 'multiselect', required: true,
            options: D.FONCTIONS.map(function (f) { return { value: f.id, label: f.label }; }),
            col: 'full',
          },
          {
            name: 'vacations', label: 'Vacations du régime', type: 'multiselect', required: true,
            options: D.TYPES_PLANNING.filter(function (t) { return t.duree > 0; })
              .map(function (t) { return { value: t.id, label: t.label + ' (' + t.debut + ' → ' + t.fin + ')' }; }),
            col: 'full',
          },
          {
            name: 'repos', label: 'Repos appliqué', type: 'select',
            options: [{ value: '', label: 'Sans repos codifié' }]
              .concat(D.TYPES_PLANNING.filter(function (t) { return t.id.indexOf('repos') === 0; })
                .map(function (t) { return { value: t.id, label: t.label }; })),
          },
          { name: 'cycle', label: 'Cycle (jours)', type: 'number', required: true, min: 1 },
          { name: 'honoraire', label: 'Honoraire (FCFA)', type: 'number', min: 0, hint: 'Laisser vide si le régime ne porte pas d’honoraire propre' },
          {
            name: 'honorairePeriodicite', label: 'Périodicité de l’honoraire', type: 'select',
            options: [{ value: 'mensuelle', label: 'Mensuelle' }, { value: 'occurrence', label: 'Par occurrence' }],
          },
          { name: 'source', label: 'Document source', type: 'text', required: true, col: 'full' },
          { name: 'mention', label: 'Règle appliquée', type: 'textarea', col: 'full' },
        ];
      }

      function editerRegime(regime) {
        var creation = !regime;
        var f = U.form(champsRegime(), regime || { cycle: 3, honorairePeriodicite: 'mensuelle' });
        var m = U.modal({
          title: creation ? 'Nouveau régime de travail' : 'Modifier le régime « ' + regime.libelle + ' »',
          subtitle: creation ? 'Les champs marqués d’un astérisque sont obligatoires.' : regime.source,
          size: 'lg',
          body: el('div.space-y-3', null, [
            creation ? null : K.note('Modifier un régime touche les vacations qui s’y adossent — et donc, '
              + 'potentiellement, les <strong>primes déjà calculées</strong>. La portée de la modification '
              + 'vous sera demandée à l’enregistrement.', { tone: 'warning', icon: 'alert-triangle' }),
            f,
          ].filter(Boolean)),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(creation ? 'Créer le régime' : 'Enregistrer', {
              variant: 'primary', icon: creation ? 'plus' : 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                v.cycle = Number(v.cycle) || 1;
                v.honoraire = v.honoraire ? Number(v.honoraire) : null;
                if (creation) {
                  colRegimes().insert(Object.assign({ statut: 'actif' }, v));
                  m.close(); rafraichirTout();
                  U.toast('Régime créé.', { type: 'success', detail: v.libelle });
                  return;
                }
                m.close();
                demanderPortee(regime, v);
              },
            }),
          ],
        });
      }

      /* --------------------------------------------------------------------
       * LA QUESTION QUI COMPTE — portée d'une modification de régime.
       * --------------------------------------------------------------------
       * Changer le régime de garde d'un médecin ne doit pas réécrire en silence
       * ses gardes passées : les primes correspondantes ont été calculées, et
       * pour certaines déjà payées. La Direction doit donc trancher, à chaque
       * modification, entre corriger l'historique et n'engager que l'avenir.
       * ------------------------------------------------------------------ */
      function demanderPortee(regime, valeurs) {
        var concernees = col.active().filter(function (v) {
          return (regime.fonctions || []).indexOf(v.fonction) !== -1;
        });
        var passees = concernees.filter(function (v) { return v.date < C.iso(AUJ); });
        var futures = concernees.filter(function (v) { return v.date >= C.iso(AUJ); });

        var choix = { portee: 'futur' };
        function option(id, titre, detail, tone) {
          var d = el('label.flex.cursor-pointer.items-start.gap-3.rounded-lg.border.p-3.transition-colors', {
            class: choix.portee === id ? 'border-navy-400 bg-navy-50' : 'border-slate-200 hover:bg-slate-50',
          });
          var r = el('input.mt-0\.5', { type: 'radio', name: 'portee-regime', value: id });
          r.checked = choix.portee === id;
          r.addEventListener('change', function () {
            choix.portee = id;
            [].forEach.call(corps.querySelectorAll('label[class*=border]'), function (x) {
              x.className = 'flex cursor-pointer items-start gap-3 rounded-lg border p-3 transition-colors '
                + (x.querySelector('input').checked ? 'border-navy-400 bg-navy-50' : 'border-slate-200 hover:bg-slate-50');
            });
          });
          d.appendChild(r);
          d.appendChild(el('div.min-w-0', null, [
            el('p.text-sm.font-semibold.text-slate-800', { text: titre }),
            el('p.mt-0\.5.text-xs.text-slate-500', { text: detail }),
          ]));
          if (tone) d.appendChild(U.badge(tone[0], tone[1]));
          return d;
        }

        var corps = el('div.space-y-3');
        corps.appendChild(el('div.flex.items-start.gap-3.rounded-lg.border.border-warning-200.bg-warning-50.p-3', null, [
          el('span.shrink-0.text-warning-600', null, C.icon('alert-triangle', 'h-5 w-5')),
          el('div.min-w-0', null, [
            el('p.text-sm.font-semibold.text-warning-900', { text: 'Cette modification a une portée à choisir.' }),
            el('p.mt-1.text-xs.text-warning-800', {
              text: C.num(concernees.length) + ' vacation(s) s’adossent à ce régime — '
                + C.num(passees.length) + ' déjà effectuée(s) et ' + C.num(futures.length) + ' à venir. '
                + 'Les vacations passées ont pu donner lieu à des primes calculées, voire payées.',
            }),
          ]),
        ]));
        corps.appendChild(option('futur', 'Vacations en cours et à venir seulement',
          'Les ' + C.num(passees.length) + ' vacation(s) passées gardent le régime sous lequel elles ont été '
          + 'effectuées, et les primes déjà calculées restent inchangées. C’est le choix prudent.',
          ['Recommandé', 'success']));
        corps.appendChild(option('tout', 'Y compris les vacations passées',
          'Les ' + C.num(passees.length) + ' vacation(s) passées sont réétiquetées et les primes de garde '
          + 'associées seront recalculées au prochain calcul de paie. À réserver à la correction d’une '
          + 'erreur de saisie du régime.',
          ['Rétroactif', 'danger']));
        U.icons(corps);

        var m = U.modal({
          title: 'Portée de la modification', subtitle: regime.libelle, size: 'lg', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Appliquer', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                var res = colRegimes().update(regime.id, Object.assign({}, valeurs, {
                  portee: choix.portee, modifieLe: C.iso(AUJ), modifiePar: S.currentUser(),
                }));
                var touchees = 0;
                if (choix.portee === 'tout') {
                  passees.forEach(function (v) {
                    col.update(v.id, { regimeLibelle: valeurs.libelle, regimeRevisee: true });
                    touchees++;
                  });
                }
                futures.forEach(function (v) { col.update(v.id, { regimeLibelle: valeurs.libelle }); });
                S.log('Modification de régime', 'M10', 'Régime', regime.id,
                  { libelle: regime.libelle }, { libelle: valeurs.libelle, portee: choix.portee });
                m.close();
                rafraichirTout();
                U.toast('Régime modifié.', {
                  type: 'success',
                  detail: choix.portee === 'tout'
                    ? C.num(touchees) + ' vacation(s) passée(s) réétiquetée(s) — primes à recalculer.'
                    : C.num(futures.length) + ' vacation(s) à venir concernée(s) ; l’historique est préservé.',
                  undo: function () { res.undo(); rafraichirTout(); },
                });
              },
            }),
          ],
        });
      }

      function archiverRegime(regime) {
        var concernees = col.active().filter(function (v) {
          return (regime.fonctions || []).indexOf(v.fonction) !== -1;
        });
        U.confirm({
          title: 'Archiver le régime « ' + regime.libelle + ' » ?',
          message: '<strong>Attention.</strong> ' + C.num(concernees.length) + ' vacation(s) s’adossent à ce régime. '
            + 'Elles ne sont pas supprimées, mais aucune nouvelle affectation ne pourra s’en réclamer, et les '
            + 'fonctions concernées (' + (regime.fonctions || []).length + ') se retrouveront sans régime codifié '
            + 'tant qu’un autre ne les couvre pas.<br><br>'
            + 'Conformément à <strong>RG-14</strong>, l’archivage est logique : le régime reste consultable, '
            + 'restaurable depuis la corbeille, et jamais supprimé définitivement.',
          confirmLabel: 'Archiver le régime', danger: true, requireMotif: true,
        }).then(function (rep) {
          if (!rep) return;
          var res = colRegimes().archive(regime.id, rep.motif);
          rafraichirTout();
          U.toast('Régime archivé.', {
            type: 'success', detail: 'Restaurable depuis la corbeille (RG-14).',
            undo: function () { res.undo(); rafraichirTout(); },
          });
        });
      }

      /** Le registre des vacations suit toute modification de régime. */
      function rafraichirTout() {
        rendreRegimes(); rendreRegistre(); rendreGraphes();
      }

      function affecter(e, jour, existant) {
        /* Les vacations proposées sont celles du régime de la catégorie, afin
           qu'aucun poste étranger à la fonction ne puisse être affecté. */
        var regle = regleDe(e.fonction);
        var autorises = regle
          ? regle.vacations.concat([regle.repos, 'conge', 'absence', 'remplacement'].filter(Boolean))
          : D.TYPES_PLANNING.map(function (t) { return t.id; });
        var options = D.TYPES_PLANNING
          .filter(function (t) { return autorises.indexOf(t.id) !== -1; })
          .map(function (t) { return { value: t.id, label: t.label + (t.debut ? ' (' + t.debut + ' → ' + t.fin + ')' : '') }; });

        var f = U.form([
          { name: 'type', label: 'Type de vacation', type: 'select', required: true, options: options },
          { name: 'observation', label: 'Observation', col: 'full' },
        ], existant || { type: (regle && regle.vacations[0]) || 'permanence' });

        var body = el('div.space-y-3', null, [
          U.descList([['Agent', e.nomComplet], ['Fonction', fonctionLabel(e.fonction)],
            ['Date', C.dateJour(jour)], ['Vacation actuelle', existant ? typePlanningLabel(existant.type) : 'Aucune']], 'grid-cols-2'),
          regle ? K.note('<strong>' + regle.libelle + '</strong> — ' + regle.mention, { tone: 'info' }) : null,
          f,
        ].filter(Boolean));

        var m = U.modal({
          title: 'Affectation de vacation', subtitle: e.nomComplet + ' — ' + C.dateJour(jour),
          size: 'md', body: body,
          footer: [
            existant ? K.btn('Retirer', {
              variant: 'danger', icon: 'trash-2',
              onclick: function () {
                var res = col.archive(existant.id);
                m.close(); global.location.reload();
                U.toast('Vacation retirée.', { type: 'success', undo: res.undo });
              },
            }) : null,
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                /* Contrôle d'incompatibilité : le repos qui suit une garde de
                   24 h interdit d'en programmer une nouvelle immédiatement.
                   La durée du repos dépend du régime de la catégorie. */
                var estGarde24 = ['garde', 'garde_hospi'].indexOf(v.type) !== -1;
                if (estGarde24) {
                  var joursRepos = (regle && regle.repos === 'repos48') ? 2 : 1;
                  for (var k = 1; k <= joursRepos; k++) {
                    var veille = col.active().filter(function (p) {
                      return p.employeId === e.id && p.date === C.iso(C.addDays(jour, -k))
                        && ['garde', 'garde_hospi'].indexOf(p.type) !== -1;
                    })[0];
                    if (veille) {
                      U.toast('Incompatibilité — le repos de ' + (joursRepos * 24) + ' h qui suit une garde n’est pas respecté.', {
                        type: 'error',
                        detail: 'Garde déjà programmée le ' + C.dateFR(C.addDays(jour, -k)) + ' pour ' + e.nomComplet + '.',
                      });
                      return;
                    }
                  }
                }
                v.date = C.iso(jour); v.employeId = e.id; v.employe = e.nomComplet;
                v.fonction = e.fonction; v.service = e.service; v.statut = 'validee';
                /* La vacation porte le régime sous lequel elle a été posée :
                   sans cette trace, une modification ultérieure du régime
                   rendrait l'historique illisible. */
                v.regimeLibelle = regle ? regle.libelle : null;
                var res = existant ? col.update(existant.id, v) : col.insert(v);
                m.close(); global.location.reload();
                U.toast('Vacation enregistrée.', { type: 'success', undo: res.undo });
              },
            }),
          ].filter(Boolean),
        });
      }

      function imprimer() {
        var lignes = [];
        agents.forEach(function (e) {
          var ligne = { agent: e.nomComplet, fonction: fonctionLabel(e.fonction) };
          jours.forEach(function (j, i) {
            var v = col.active().filter(function (p) { return p.employeId === e.id && p.date === C.iso(j); })[0];
            ligne['j' + i] = v ? typePlanningLabel(v.type) : '';
          });
          lignes.push(ligne);
        });
        P.etat({
          titre: 'Planning de garde et de permanence',
          sousTitre: 'Semaine du ' + C.dateFR(jours[0]) + ' au ' + C.dateFR(jours[6]),
          cartouche: [['Période', C.dateFR(jours[0]) + ' – ' + C.dateFR(jours[6])],
            ['Agents concernés', C.num(agents.length)],
            ['Établi par', S.currentUser()], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'Agent', key: 'agent' },
            { label: 'Fonction', key: 'fonction' },
          ].concat(jours.map(function (j, i) {
            return { label: C.JOURS[j.getDay()].slice(0, 3) + '. ' + j.getDate(), key: 'j' + i };
          })), lignes),
          signatures: [{ role: 'Le Surveillant Général', nom: 'GARBA Yahouza' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
            { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
        });
      }
    },
  });

  /* ==========================================================================
   * STATISTIQUES DE GARDE
   * --------------------------------------------------------------------------
   * La question posée par la Direction : « combien de gardes cet agent a-t-il
   * effectuées, entre telle et telle date ? » — au mois, à la semaine, au
   * trimestre, au semestre. C'est aussi la base de contrôle des primes NS 132,
   * dont le nombre de gardes est le multiplicateur.
   *
   * Les repos et les congés sont exclus des comptages : ce sont des vacations
   * au planning, mais pas du travail effectué. Les compter ferait apparaître
   * les agents les plus reposés comme les plus chargés.
   * ======================================================================== */
  var PERIODES_GARDE = [
    { id: 'semaine', label: 'Semaine', jours: 7 },
    { id: 'mois', label: 'Mois', jours: 30 },
    { id: 'trimestre', label: 'Trimestre', jours: 91 },
    { id: 'semestre', label: 'Semestre', jours: 182 },
    { id: 'annee', label: 'Année', jours: 365 },
    { id: 'libre', label: 'Plage libre', jours: null },
  ];

  /** Les types de vacation qui comptent comme du travail effectué. */
  var VACATIONS_TRAVAILLEES = ['garde', 'garde_hospi', 'garde_soins', 'permanence', 'soiree',
    'entretien_general', 'incineration', 'remplacement'];

  global.SIGH.screen('m10-stats-gardes', {
    title: 'Statistiques de garde',
    description: 'Nombre de gardes effectuées par agent, par service et par type de vacation, sur la période choisie.',
    regle: 'Le comptage porte sur les <strong>vacations travaillées</strong> — gardes, permanences, soirées, '
      + 'entretien et incinération. Les <strong>repos et congés en sont exclus</strong> : ils figurent au planning '
      + 'mais ne constituent pas du travail effectué, et les compter inverserait le classement. '
      + 'Ces nombres sont ceux qui multiplient les primes de la <strong>NS 132</strong>.',
    render: function (root) {
      var col = S.collection('planning', { module: 'M10', entite: 'Planning' });
      var vue = el('div.space-y-4');

      var selPeriode = el('select.select');
      PERIODES_GARDE.forEach(function (x) {
        selPeriode.appendChild(el('option', { value: x.id }, x.label));
      });
      selPeriode.value = 'mois';

      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var selAgent = el('select.select');
      var selService = el('select.select');
      var selType = el('select.select');
      var selFonction = el('select.select');

      remplirFiltres();
      appliquerPeriode();

      var barre = el('div.card');
      var bb = el('div.card-body.grid.gap-3.md\:grid-cols-3.lg\:grid-cols-6');
      bb.appendChild(el('div', null, [el('label.label', { text: 'Périodicité' }), selPeriode]));
      bb.appendChild(el('div', null, [el('label.label', { text: 'Du' }), dDebut]));
      bb.appendChild(el('div', null, [el('label.label', { text: 'Au' }), dFin]));
      bb.appendChild(el('div', null, [el('label.label', { text: 'Agent' }), selAgent]));
      bb.appendChild(el('div', null, [el('label.label', { text: 'Service' }), selService]));
      bb.appendChild(el('div', null, [el('label.label', { text: 'Type de vacation' }), selType]));
      bb.appendChild(el('div', null, [el('label.label', { text: 'Fonction' }), selFonction]));
      bb.appendChild(el('div.flex.items-end.gap-2.md\:col-span-2', null, [
        K.btn('Appliquer', { variant: 'primary', icon: 'filter', onclick: afficher }),
        K.btn('Imprimer l’état', { icon: 'printer', onclick: imprimer }),
      ]));
      barre.appendChild(bb);

      selPeriode.addEventListener('change', function () { appliquerPeriode(); afficher(); });
      [dDebut, dFin, selAgent, selService, selType, selFonction].forEach(function (x) {
        x.addEventListener('change', afficher);
      });

      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function remplirFiltres() {
        selAgent.appendChild(el('option', { value: '' }, 'Tous les agents'));
        C.sortBy(personnel(), 'nomComplet').forEach(function (e) {
          selAgent.appendChild(el('option', { value: e.id }, e.nomComplet));
        });
        selService.appendChild(el('option', { value: '' }, 'Tous les services'));
        D.SERVICES.forEach(function (x) {
          selService.appendChild(el('option', { value: x.value || x }, x.label || x));
        });
        selType.appendChild(el('option', { value: '' }, 'Toutes les vacations travaillées'));
        D.TYPES_PLANNING.filter(function (t) { return VACATIONS_TRAVAILLEES.indexOf(t.id) !== -1; })
          .forEach(function (t) { selType.appendChild(el('option', { value: t.id }, t.label)); });
        selFonction.appendChild(el('option', { value: '' }, 'Toutes les fonctions'));
        D.FONCTIONS.forEach(function (f) {
          selFonction.appendChild(el('option', { value: f.id }, f.label));
        });
      }

      /* La périodicité choisie POSITIONNE la plage ; « plage libre » la laisse
         à l'utilisateur. Sans ce lien, les deux réglages se contrediraient. */
      function appliquerPeriode() {
        var per = PERIODES_GARDE.filter(function (x) { return x.id === selPeriode.value; })[0];
        var libre = !per || per.jours == null;
        dDebut.disabled = false; dFin.disabled = false;
        if (libre) return;
        dFin.value = C.iso(AUJ);
        dDebut.value = C.iso(C.addDays(AUJ, -per.jours + 1));
      }

      function lignes() {
        var d1 = dDebut.value, d2 = dFin.value;
        return col.active().filter(function (v) {
          if (VACATIONS_TRAVAILLEES.indexOf(v.type) === -1) return false;
          if (d1 && v.date < d1) return false;
          if (d2 && v.date > d2) return false;
          if (selAgent.value && v.employeId !== selAgent.value) return false;
          if (selService.value && v.service !== selService.value) return false;
          if (selType.value && v.type !== selType.value) return false;
          if (selFonction.value && v.fonction !== selFonction.value) return false;
          return true;
        });
      }

      function parAgent(rows) {
        var g = C.groupBy(rows, 'employeId');
        return Object.keys(g).map(function (id) {
          var v = g[id];
          var gardes = v.filter(function (x) { return x.type.indexOf('garde') === 0; }).length;
          var heures = C.sum(v, function (x) {
            var t = D.TYPES_PLANNING.filter(function (y) { return y.id === x.type; })[0];
            return t ? t.duree : 0;
          });
          return {
            employeId: id, agent: v[0].employe, fonction: v[0].fonction,
            fonctionLabel: fonctionLabel(v[0].fonction),
            service: v[0].service || '—',
            total: v.length, gardes: gardes,
            permanences: v.filter(function (x) { return x.type === 'permanence'; }).length,
            soirees: v.filter(function (x) { return x.type === 'soiree'; }).length,
            autres: v.length - gardes - v.filter(function (x) { return x.type === 'permanence' || x.type === 'soiree'; }).length,
            heures: Math.round(heures * 10) / 10,
          };
        }).sort(function (a, b) { return b.total - a.total; });
      }

      function afficher() {
        var rows = lignes();
        var agents = parAgent(rows);
        C.clear(vue);

        var jours = (dDebut.value && dFin.value)
          ? Math.max(1, Math.round((new Date(dFin.value) - new Date(dDebut.value)) / 86400000) + 1) : 0;

        vue.appendChild(U.kpiGrid([
          { label: 'Vacations travaillées', value: C.num(rows.length), icon: 'calendar-check', tone: 'navy',
            hint: jours ? 'sur ' + C.num(jours) + ' jour(s)' : null },
          { label: 'Gardes', value: C.num(rows.filter(function (v) { return v.type.indexOf('garde') === 0; }).length),
            icon: 'moon', tone: 'danger', hint: 'multiplicateur des primes NS 132' },
          { label: 'Agents concernés', value: C.num(agents.length), icon: 'users', tone: 'info' },
          {
            label: 'Moyenne par agent',
            value: agents.length ? String(Math.round(rows.length / agents.length * 10) / 10) : '0',
            icon: 'scale', tone: 'neutral', hint: 'vacations sur la période',
          },
        ]));

        if (!rows.length) {
          vue.appendChild(U.card('Statistiques de garde',
            U.empty('Aucune vacation sur la période et les filtres retenus.', {
              icon: 'calendar-x',
              hint: 'Élargir la plage de dates ou retirer un filtre. Les repos et congés ne sont jamais comptés.',
            })));
          U.icons(vue);
          return;
        }

        vue.appendChild(U.dataTable({
          title: 'Gardes par agent — ' + libellePeriode(),
          rows: agents, exportName: 'statistiques-gardes', pageSize: 20, searchable: true,
          defaultSort: 'total', defaultDir: 'desc',
          columns: [
            {
              key: 'agent', label: 'Agent',
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.agent }),
                  el('p.truncate.text-xs.text-slate-400', { text: r.fonctionLabel + ' · ' + r.service }),
                ]);
              },
            },
            { key: 'gardes', label: 'Gardes', align: 'right', render: function (r) { return el('span.font-semibold.text-danger-700', { text: C.num(r.gardes) }); } },
            { key: 'permanences', label: 'Permanences', align: 'right' },
            { key: 'soirees', label: 'Soirées', align: 'right' },
            { key: 'autres', label: 'Autres', align: 'right' },
            { key: 'total', label: 'Total', align: 'right', render: function (r) { return el('span.font-semibold', { text: C.num(r.total) }); } },
            { key: 'heures', label: 'Heures', align: 'right', render: function (r) { return C.num(r.heures) + ' h'; } },
          ],
        }));

        /* --- Graphiques : agent, service, type de vacation --------------- */
        var top = agents.slice(0, 10);
        var parService = C.groupBy(rows, function (v) { return v.service || 'Non renseigné'; });
        var parType = C.groupBy(rows, 'type');

        vue.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Charge par agent — les dix premiers',
            G.barres(top.map(function (a) { return a.agent; }),
              [{ label: 'Vacations', data: top.map(function (a) { return a.total; }), color: '#12315e' }],
              { horizontal: true, height: 280 })),
          U.card('Répartition par service',
            G.camembert(Object.keys(parService),
              Object.keys(parService).map(function (k) { return parService[k].length; }), { height: 280 })),
          U.card('Répartition par type de vacation',
            G.barres(Object.keys(parType).map(typePlanningLabel),
              [{ label: 'Vacations', data: Object.keys(parType).map(function (k) { return parType[k].length; }), color: '#3765a6' }],
              { height: 280 })),
        ]));

        /* --- Évolution dans le temps ------------------------------------- */
        var parMois = C.groupBy(rows, function (v) { return String(v.date).slice(0, 7); });
        var mois = Object.keys(parMois).sort();
        if (mois.length > 1) {
          vue.appendChild(U.card('Évolution du nombre de vacations',
            G.ligne(mois.map(function (m) { return C.moisAnnee(new Date(m + '-01')); }),
              [{ label: 'Vacations', data: mois.map(function (m) { return parMois[m].length; }), color: '#22a170' }],
              { height: 240 })));
        }

        U.icons(vue);
      }

      function libellePeriode() {
        if (!dDebut.value || !dFin.value) return 'toutes périodes';
        return 'du ' + C.dateFR(dDebut.value) + ' au ' + C.dateFR(dFin.value);
      }

      function imprimer() {
        var agents = parAgent(lignes());
        P.etat({
          titre: 'État des gardes effectuées',
          sousTitre: libellePeriode(),
          cartouche: [['Période', libellePeriode()],
            ['Agents concernés', C.num(agents.length)],
            ['Vacations travaillées', C.num(C.sum(agents, 'total'))],
            ['Dont gardes', C.num(C.sum(agents, 'gardes'))],
            ['Établi par', S.currentUser()], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Agent', key: 'agent' },
              { label: 'Fonction', key: 'fonctionLabel' },
              { label: 'Service', key: 'service' },
              /* Des vacations et des heures, pas des francs : chaque colonne
                 porte sa somme et son format. */
              { label: 'Gardes', align: 'right', value: function (r) { return C.num(r.gardes); }, somme: function (r) { return r.gardes; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Permanences', align: 'right', value: function (r) { return C.num(r.permanences); }, somme: function (r) { return r.permanences; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Soirées', align: 'right', value: function (r) { return C.num(r.soirees); }, somme: function (r) { return r.soirees; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Total', align: 'right', value: function (r) { return C.num(r.total); }, somme: function (r) { return r.total; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Heures', align: 'right', value: function (r) { return C.num(r.heures) + ' h'; }, somme: function (r) { return r.heures; }, formatTotal: function (v) { return C.num(v) + ' h'; } },
            ], agents, {
              total: true,
              totalLabel: 'TOTAL',
            }),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Comptage des vacations travaillées : gardes, permanences, soirées, entretien général et '
                + 'incinération. Les repos et congés en sont exclus. Ce décompte est celui qui multiplie les '
                + 'primes de garde et de permanence de la note de service NS n° 132/07/DM/DA/CNT/2026.',
            }),
          ]),
          signatures: [{ role: 'Le Surveillant Général', nom: 'GARBA Yahouza' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * PRÉSENCES & ABSENCES
   * ======================================================================== */
  global.SIGH.screen('m10-presences', {
    title: 'Présences & absences',
    description: 'Pointage quotidien, retards et absences, avec incidence sur l’évaluation mensuelle.',
    render: function (root) {
      /* Le registre est amorcé AU SOCLE : trois écrans le lisent, et une page
         ne charge que le module de son écran. */
      var col = S.collection('presences', { module: 'M10', entite: 'Presence' });

      var host = el('div.space-y-4');
      var blocKpi = el('div'), blocTable = el('div'), blocGraphes = el('div');

      /* Plage de dates : le registre couvre vingt-cinq jours par agent, soit
         plus de mille lignes. Sans bornes, on ne trouve rien. */
      var dDebut = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, -30)) });
      var dFin = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'Au' }), dFin]),
        K.btn('Appliquer', { variant: 'primary', icon: 'filter', onclick: rafraichir }),
        K.btn('Mois en cours', {
          icon: 'calendar',
          onclick: function () {
            var d = new Date(AUJ.getFullYear(), AUJ.getMonth(), 1);
            dDebut.value = C.iso(d); dFin.value = C.iso(AUJ); rafraichir();
          },
        }),
        K.btn('Sept derniers jours', {
          icon: 'calendar-days',
          onclick: function () { dDebut.value = C.iso(C.addDays(AUJ, -6)); dFin.value = C.iso(AUJ); rafraichir(); },
        }),
      ]));
      host.appendChild(barre);
      host.appendChild(blocKpi);
      host.appendChild(blocTable);
      host.appendChild(blocGraphes);

      rafraichir();
      root.appendChild(host);
      return null;

      function dansPlage() {
        return col.active().filter(function (r) {
          if (dDebut.value && r.date < dDebut.value) return false;
          if (dFin.value && r.date > dFin.value) return false;
          return true;
        });
      }

      function rafraichir() { rendreKpi(); rendreTable(); rendreGraphes(); }

      function champsPointage() {
        return [
          { name: 'employeId', label: 'Agent', type: 'select', required: true, options: optionsEmployes(), col: 'full' },
          { name: 'date', label: 'Date du pointage', type: 'date', required: true },
          {
            name: 'etat', label: 'État', type: 'select', required: true,
            options: [{ value: 'present', label: 'Présent' }, { value: 'retard', label: 'Retard' },
              { value: 'absent', label: 'Absent' }, { value: 'conge', label: 'Congé' }],
          },
          { name: 'heureArrivee', label: 'Heure d’arrivée', type: 'time' },
          { name: 'heureDepart', label: 'Heure de départ', type: 'time' },
          { name: 'motif', label: 'Motif / justification', col: 'full' },
        ];
      }

      function rendreKpi() {
        var mois = dansPlage();
        C.clear(blocKpi);
        blocKpi.appendChild(U.kpiGrid([
          { label: 'Pointages de la période', value: C.num(mois.length), icon: 'clipboard-check', tone: 'navy' },
          { label: 'Présences', value: C.num(mois.filter(function (r) { return r.etat === 'present'; }).length), icon: 'check-circle-2', tone: 'success' },
          { label: 'Retards', value: C.num(mois.filter(function (r) { return r.etat === 'retard'; }).length), icon: 'clock-alert', tone: 'warning', hint: 'Critère NS 131' },
          { label: 'Absences', value: C.num(mois.filter(function (r) { return r.etat === 'absent'; }).length), icon: 'user-x', tone: 'danger' },
        ]));
        blocKpi.appendChild(K.note('Les retards et absences non justifiées alimentent le critère '
          + '<strong>« Ponctualité et assiduité »</strong> du barème NS 131, avec incidence directe sur la fiche '
          + 'd’évaluation et le solde du mois.', { tone: 'info' }));
        U.icons(blocKpi);
      }

      function rendreTable() {
        C.clear(blocTable);
        blocTable.appendChild(U.dataTable({
        title: 'Registre des présences — ' + C.dateFR(dDebut.value) + ' au ' + C.dateFR(dFin.value),
        rows: function () { return dansPlage(); }, exportName: 'presences', pageSize: 20,
        actions: [K.creer(col, champsPointage(), {
          module: 'M10', label: 'Ajouter un pointage', titre: 'Nouveau pointage', entite: 'Pointage',
          defauts: function () { return { date: C.iso(AUJ), etat: 'present', heureArrivee: '07:45' }; },
          transform: function (v) {
            var e = personnel().filter(function (x) { return x.id === v.employeId; })[0];
            if (e) { v.employe = e.nomComplet; v.matricule = e.matricule; v.service = e.service; }
            return v;
          },
          apres: rafraichir,
        })].filter(Boolean),
        rowActions: K.actionsLigne(col, champsPointage(), { module: 'M10', refresh: rafraichir }),
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'etat', label: 'État', options: [{ value: 'present', label: 'Présent' }, { value: 'retard', label: 'Retard' }, { value: 'absent', label: 'Absent' }] },
          { name: 'service', label: 'Service', options: D.SERVICES },
        ],
        columns: [
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true },
          { key: 'employe', label: 'Agent' },
          { key: 'service', label: 'Service' },
          {
            key: 'etat', label: 'État',
            render: function (r) {
              var m = { present: ['Présent', 'success'], retard: ['Retard', 'warning'], absent: ['Absent', 'danger'] };
              return U.badge(m[r.etat][0], m[r.etat][1]);
            },
          },
          { key: 'heureArrivee', label: 'Arrivée', align: 'right' },
          { key: 'heureDepart', label: 'Départ', align: 'right' },
          { key: 'motif', label: 'Motif' },
        ],
        }));
        U.icons(blocTable);
      }

      function rendreGraphes() {
        var mois = dansPlage();
        C.clear(blocGraphes);
        if (!mois.length) {
          blocGraphes.appendChild(U.card('Statistiques',
            U.empty('Aucun pointage sur la plage retenue.', { icon: 'calendar-x' })));
          return;
        }
        var parService = C.groupBy(mois, 'service');
        var parEtat = C.groupBy(mois, 'etat');
        var parJour = C.groupBy(mois, 'date');
        var jours = Object.keys(parJour).sort();

        blocGraphes.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Taux de présence par service',
            K.ranking(Object.keys(parService).map(function (k) {
              var t = parService[k];
              return {
                label: k,
                value: Math.round(t.filter(function (r) { return r.etat === 'present'; }).length / t.length * 100),
                tone: 'success',
              };
            }).sort(function (a, b) { return b.value - a.value; }), { format: function (v) { return v + ' %'; } })),
          U.card('Répartition des pointages',
            G.anneau(['Présences', 'Retards', 'Absences'], [
              (parEtat.present || []).length, (parEtat.retard || []).length, (parEtat.absent || []).length,
            ], { legend: 'bottom', colors: [G.TONES.vert, G.TONES.orange, G.TONES.rouge] })),
          U.card('Volume de pointages par service',
            G.barres(Object.keys(parService),
              [{ label: 'Pointages', data: Object.keys(parService).map(function (k) { return parService[k].length; }), color: G.TONES.navy }],
              { horizontal: true, height: 260 })),
        ]));

        if (jours.length > 1) {
          blocGraphes.appendChild(U.card('Retards et absences au fil des jours',
            G.ligne(jours.map(function (j) { return C.dateFR(j); }), [
              { label: 'Retards', data: jours.map(function (j) { return parJour[j].filter(function (r) { return r.etat === 'retard'; }).length; }), color: G.TONES.orange },
              { label: 'Absences', data: jours.map(function (j) { return parJour[j].filter(function (r) { return r.etat === 'absent'; }).length; }), color: G.TONES.rouge },
            ], { height: 240 })));
        }
        U.icons(blocGraphes);
      }
    },
  });

  /* ==========================================================================
   * CONGÉS
   * ======================================================================== */
  global.SIGH.screen('m10-conges', {
    title: 'Congés',
    description: 'Demandes, validation et suivi des congés annuels et exceptionnels.',
    regle: 'Le régime observé prévoit <strong>2 jours de repos hebdomadaire</strong> et <strong>10 jours de congés annuels</strong>.',
    render: function (root) {
      var col = S.collection('conges', { module: 'M10', entite: 'Conge' });
      if (!col.all().length) {
        var rnd = C.seeded(1423);
        personnel().slice(0, 22).forEach(function (e, i) {
          var debut = C.addDays(AUJ, C.between(rnd, -120, 60));
          var duree = C.between(rnd, 2, 10);
          col.all().push({
            id: 'CNG' + C.pad(i + 1, 4), statut: 'actif',
            reference: 'CG-' + C.pad(i + 1, 4),
            employeId: e.id, employe: e.nomComplet, matricule: e.matricule, service: e.service,
            nature: C.pick(rnd, ['Congé annuel', 'Congé annuel', 'Congé de maternité', 'Congé de maladie', 'Absence autorisée']),
            dateDebut: C.iso(debut), dateFin: C.iso(C.addDays(debut, duree)),
            duree: duree,
            statutConge: C.pick(rnd, ['valide', 'valide', 'en_attente', 'refuse']),
            remplacant: rnd() > 0.5 ? C.pick(rnd, personnel()).nomComplet : null,
          });
        });
        S.save();
      }

      /* Le kit place ce bloc sous le tableau : la lecture graphique vient
         APRÈS les données, jamais à leur place. */
      function graphiquesConges() {
        var rows = S.collection('conges').active();
        if (!rows.length) return U.card('Statistiques des congés', U.empty('Aucun congé enregistré.', { icon: 'plane' }));

        var parService = C.groupBy(rows, function (c) { return c.service || 'Non renseigné'; });
        var parNature = C.groupBy(rows, 'nature');
        var parDecision = C.groupBy(rows, 'statutConge');
        var parMois = C.groupBy(rows, function (c) { return String(c.dateDebut).slice(0, 7); });
        var mois = Object.keys(parMois).sort();
        var DECISIONS = { valide: 'Accordés', en_attente: 'En attente', refuse: 'Refusés' };

        var bloc = el('div.space-y-4');
        bloc.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Congés par service',
            G.barres(Object.keys(parService),
              [{ label: 'Congés', data: Object.keys(parService).map(function (k) { return parService[k].length; }), color: G.TONES.navy }],
              { horizontal: true, height: 260 })),
          U.card('Répartition par nature',
            G.camembert(Object.keys(parNature),
              Object.keys(parNature).map(function (k) { return parNature[k].length; }), { height: 260, legend: 'bottom' })),
          U.card('Décisions',
            G.anneau(Object.keys(parDecision).map(function (k) { return DECISIONS[k] || k; }),
              Object.keys(parDecision).map(function (k) { return parDecision[k].length; }),
              { legend: 'bottom', colors: [G.TONES.vert, G.TONES.orange, G.TONES.rouge] })),
        ]));

        if (mois.length > 1) {
          bloc.appendChild(U.card('Jours de congé accordés par mois',
            G.ligne(mois.map(function (m) { return C.moisAnnee(new Date(m + '-01')); }),
              [{
                label: 'Jours',
                data: mois.map(function (m) {
                  return C.sum(parMois[m].filter(function (c) { return c.statutConge === 'valide'; }), 'duree');
                }),
                color: G.TONES.bleu,
              }], { height: 240 })));
        }

        bloc.appendChild(K.note('La répartition par nature distingue le congé annuel des congés de maternité et '
          + 'de maladie : ces derniers ne s’imputent pas sur le solde annuel et ne se compensent pas de la même '
          + 'manière au planning.', { tone: 'info' }));
        return bloc;
      }

      return K.crud({
        collection: 'conges', entite: 'congé', entiteP: 'congés', module: 'M10',
        apresTableau: graphiquesConges,
        defaultSort: 'dateDebut', defaultDir: 'desc', pageSize: 15,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (c) { return el('span.font-mono.text-xs', { text: c.reference }); } },
          { key: 'employe', label: 'Agent' },
          { key: 'service', label: 'Service' },
          { key: 'nature', label: 'Nature', render: function (c) { return U.badge(c.nature, 'navy'); } },
          { key: 'dateDebut', label: 'Du', nowrap: true, text: function (c) { return C.dateFR(c.dateDebut); }, render: function (c) { return C.dateFR(c.dateDebut); } },
          { key: 'dateFin', label: 'Au', nowrap: true, text: function (c) { return C.dateFR(c.dateFin); }, render: function (c) { return C.dateFR(c.dateFin); } },
          { key: 'duree', label: 'Jours', align: 'right' },
          { key: 'remplacant', label: 'Remplaçant' },
          {
            key: 'statutConge', label: 'Décision',
            render: function (c) {
              var m = { valide: ['Accordé', 'success'], en_attente: ['En attente', 'warning'], refuse: ['Refusé', 'danger'] };
              var x = m[c.statutConge] || ['—', 'neutral'];
              return U.badge(x[0], x[1]);
            },
          },
        ],
        fields: function () {
          return [
            { name: 'employeId', label: 'Agent', type: 'select', required: true, options: optionsEmployes(), col: 'full' },
            { name: 'nature', label: 'Nature du congé', type: 'select', required: true, options: ['Congé annuel', 'Congé de maternité', 'Congé de maladie', 'Absence autorisée', 'Congé exceptionnel'] },
            { name: 'dateDebut', label: 'Date de début', type: 'date', required: true },
            { name: 'dateFin', label: 'Date de fin', type: 'date', required: true },
            {
              name: 'remplacant', label: 'Remplaçant désigné', type: 'select',
              options: personnel().map(function (e) { return { value: e.nomComplet, label: e.nomComplet }; }),
            },
            { name: 'statutConge', label: 'Décision', type: 'select', required: true, options: [{ value: 'en_attente', label: 'En attente' }, { value: 'valide', label: 'Accordé' }, { value: 'refuse', label: 'Refusé' }] },
            { name: 'motif', label: 'Motif', type: 'textarea', rows: 2, col: 'full' },
          ];
        },
        transform: function (v) {
          var e = personnel().filter(function (x) { return x.id === v.employeId; })[0];
          if (e) { v.employe = e.nomComplet; v.matricule = e.matricule; v.service = e.service; }
          v.duree = Math.max(1, C.daysBetween(v.dateDebut, v.dateFin));
          if (!v.reference) v.reference = C.nextRef('CG-', 4);
          return v;
        },
        beforeSave: function (v) {
          if (C.toDate(v.dateFin) < C.toDate(v.dateDebut)) return 'La date de fin doit être postérieure à la date de début.';
          return null;
        },
        onCreate: function () { return { statutConge: 'en_attente', nature: 'Congé annuel', dateDebut: C.iso(AUJ) }; },
        filters: [
          { name: 'nature', label: 'Nature', options: ['Congé annuel', 'Congé de maternité', 'Congé de maladie', 'Absence autorisée', 'Congé exceptionnel'] },
          { name: 'statutConge', label: 'Décision', options: [{ value: 'valide', label: 'Accordé' }, { value: 'en_attente', label: 'En attente' }, { value: 'refuse', label: 'Refusé' }] },
        ],
        kpis: function (rows) {
          var enCours = rows.filter(function (c) {
            return c.statutConge === 'valide' && C.toDate(c.dateDebut) <= AUJ && C.toDate(c.dateFin) >= AUJ;
          });
          return [
            { label: 'Demandes enregistrées', value: C.num(rows.length), icon: 'calendar-off', tone: 'navy' },
            { label: 'En congé aujourd’hui', value: C.num(enCours.length), icon: 'plane', tone: 'info' },
            { label: 'En attente de décision', value: C.num(rows.filter(function (c) { return c.statutConge === 'en_attente'; }).length), icon: 'hourglass', tone: 'warning' },
            { label: 'Jours accordés', value: C.num(C.sum(rows.filter(function (c) { return c.statutConge === 'valide'; }), 'duree')), icon: 'calendar-check', tone: 'success' },
          ];
        },
        etat: function (c) {
          P.etat({
            titre: 'Décision de congé',
            sousTitre: c.reference,
            cartouche: [['Agent', c.employe], ['Matricule', c.matricule], ['Service', c.service],
              ['Nature', c.nature], ['Période', C.dateFR(c.dateDebut) + ' au ' + C.dateFR(c.dateFin)],
              ['Durée', c.duree + ' jour(s)']],
            contenu: el('div.space-y-3', null, [
              el('p', { text: 'La Directrice Administrative de la CLINIQUE NASSIERA TOO SARL,' }),
              el('p.mt-2', {
                text: c.statutConge === 'valide'
                  ? 'Accorde à ' + c.employe + ', matricule ' + c.matricule + ', un ' + c.nature.toLowerCase()
                    + ' de ' + c.duree + ' jour(s), du ' + C.dateFR(c.dateDebut) + ' au ' + C.dateFR(c.dateFin) + ' inclus.'
                  : (c.statutConge === 'refuse'
                    ? 'Rejette la demande de ' + c.nature.toLowerCase() + ' formulée par ' + c.employe + ' pour la période du '
                      + C.dateFR(c.dateDebut) + ' au ' + C.dateFR(c.dateFin) + '.'
                    : 'Accuse réception de la demande de ' + c.nature.toLowerCase() + ' formulée par ' + c.employe + ', en cours d’instruction.'),
              }),
              c.remplacant ? el('p.mt-2', { text: 'Pendant cette période, l’intéressé(e) est remplacé(e) par ' + c.remplacant + '.' }) : null,
              c.motif ? el('p.mt-2.italic', { text: 'Motif : ' + c.motif }) : null,
            ]),
            signatures: [{ role: 'L’Agent', nom: c.employe }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * ÉVALUATIONS — moteur NS 131
   * ======================================================================== */
  /* ==========================================================================
   * LE BARÈME NS 131 — CONSULTATION ET MODIFICATION
   * --------------------------------------------------------------------------
   * Le barème vit dans le magasin. Sa modification n'est possible que si la
   * porte a été ouverte depuis « Paramètres système » : un barème de sanctions
   * ne se retouche pas au détour d'un écran d'évaluation.
   *
   * La PORTÉE reprend le mécanisme du NS 132 plutôt que d'en inventer un
   * second : une évaluation déjà prononcée garde le barème sous lequel elle
   * l'a été, sauf décision explicite. Deux mécanismes de portée auraient
   * divergé au premier correctif.
   * ======================================================================== */
  function colBareme() {
    return S.collection('baremeNS131', { module: 'M10', entite: 'critère', prefix: 'BAR' });
  }
  function colHistoriqueBareme() {
    return S.collection('historiqueBareme', { module: 'M10', entite: 'version de barème', prefix: 'HBA' });
  }

  function blocBaremeNS131(rafraichir) {
    var ouvert = global.SIGH.baremeModifiable && global.SIGH.baremeModifiable();
    var hote = el('div.space-y-3');
    dessiner();
    return hote;

    function dessiner() {
      C.clear(hote);
      var rows = colBareme().active();

      hote.appendChild(K.note(ouvert
        ? '<strong>Modification autorisée.</strong> La porte a été ouverte depuis « Paramètres système ». '
          + 'Chaque changement demandera sa portée — évaluations à venir seulement, ou évaluations déjà '
          + 'prononcées comprises. Penser à refermer la porte après usage.'
        : 'Le barème est <strong>consultable</strong>. Pour le modifier, ouvrir la porte depuis '
          + '« Paramètres système », onglet <em>Barème NS 131</em>. Un barème de sanctions ne se retouche '
          + 'pas au détour d’un écran d’évaluation.',
      { tone: ouvert ? 'warning' : 'info', icon: ouvert ? 'unlock' : 'lock' }));

      var actions = [];
      if (ouvert && K.droits('M10').editer) {
        actions.push(K.btn('Nouveau critère', {
          variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { editerCritere(null); },
        }));
      }
      actions.push(K.btn('Paramètres système', {
        size: 'sm', icon: 'settings',
        onclick: function () { global.SIGH.app.go('cfg-systeme', { onglet: 'bareme' }); },
      }));

      hote.appendChild(U.dataTable({
        title: 'Barème d’évaluation — ' + D.NS131.reference,
        rows: rows, exportName: 'bareme-ns131', pageSize: 10, defaultSort: 'num',
        actions: actions,
        columns: [
          { key: 'num', label: 'N°', nowrap: true, render: function (b) { return el('span.font-mono.text-xs', { text: b.num }); } },
          {
            key: 'label', label: 'Critère',
            render: function (b) {
              return el('div.min-w-0', null, [
                el('p.text-sm.font-medium.text-slate-800', { text: b.label }),
                el('p.text-xs.text-slate-400', { text: (b.criteres || []).join(' · ') }),
              ]);
            },
          },
          { key: 'bonne', label: 'Bonne', align: 'right', value: function (b) { return b.sanctions.bonne; }, render: function (b) { return (b.sanctions.bonne || 0) + ' %'; } },
          { key: 'moyenne', label: 'Moyenne', align: 'right', value: function (b) { return b.sanctions.moyenne; }, render: function (b) { return el('span.text-warning-700', { text: (b.sanctions.moyenne || 0) + ' %' }); } },
          { key: 'faible', label: 'Faible à mauvaise', align: 'right', value: function (b) { return b.sanctions.faible; }, render: function (b) { return el('span.font-semibold.text-danger-700', { text: (b.sanctions.faible || 0) + ' %' }); } },
          {
            key: 'dateEffet', label: 'En vigueur depuis', nowrap: true, align: 'right',
            render: function (b) { return el('span.text-xs.text-slate-500', { text: C.dateFR(b.dateEffet) }); },
          },
        ],
        rowActions: function (b) {
          if (!ouvert || !K.droits('M10').editer) return [];
          return [
            K.iconBtn('pencil', 'Modifier ce critère', function () { editerCritere(b); }),
            K.iconBtn('archive', 'Retirer ce critère', function () { archiverCritere(b); }, 'ghost'),
          ];
        },
      }));

      var anciennes = colHistoriqueBareme().active();
      if (anciennes.length) {
        hote.appendChild(U.card('Versions antérieures du barème', K.miniTable([
          { label: 'Critère', key: 'label' },
          { label: 'En vigueur du', render: function (v) { return C.dateFR(v.dateEffet); } },
          { label: 'au', render: function (v) { return v.dateFin ? C.dateFR(v.dateFin) : 'en cours'; } },
          {
            label: 'Taux', render: function (v) {
              return el('span.text-xs.text-slate-500', {
                text: 'bonne ' + (v.sanctions.bonne || 0) + ' % · moyenne ' + (v.sanctions.moyenne || 0)
                  + ' % · faible ' + (v.sanctions.faible || 0) + ' %',
              });
            },
          },
        ], C.sortBy(anciennes, 'dateFin').reverse())));
        hote.appendChild(K.note('Ces versions ne sont pas décoratives : c’est en elles qu’une évaluation '
          + 'prononcée sous l’ancien barème retrouve le taux qui lui a été appliqué.',
        { tone: 'info', icon: 'history' }));
      }
      U.icons(hote);
    }

    function champsCritere() {
      return [
        { name: 'num', label: 'Numéro', type: 'text', required: true },
        { name: 'label', label: 'Intitulé du critère', type: 'text', required: true, col: 'full' },
        {
          name: 'criteresTexte', label: 'Manquements retenus', type: 'textarea', rows: 3, col: 'full',
          hint: 'Un manquement par ligne — ils s’affichent sous l’intitulé.',
        },
        { name: 'bonne', label: 'Retenue — Bonne (%)', type: 'number', min: 0, max: 100, required: true },
        { name: 'moyenne', label: 'Retenue — Moyenne (%)', type: 'number', min: 0, max: 100, required: true },
        { name: 'faible', label: 'Retenue — Faible à mauvaise (%)', type: 'number', min: 0, max: 100, required: true },
      ];
    }

    function editerCritere(b) {
      var creation = !b;
      var valeurs = creation ? { bonne: 0, moyenne: 5, faible: 10, num: C.pad(colBareme().active().length + 1, 2) } : {
        num: b.num, label: b.label,
        criteresTexte: (b.criteres || []).join('\n'),
        bonne: b.sanctions.bonne, moyenne: b.sanctions.moyenne, faible: b.sanctions.faible,
      };
      var f = U.form(champsCritere(), valeurs);
      var m = U.modal({
        title: creation ? 'Nouveau critère d’évaluation' : 'Modifier « ' + b.label + ' »',
        subtitle: D.NS131.reference, size: 'lg',
        body: el('div.space-y-3', null, [
          K.note('Ces taux s’appliquent au <strong>salaire brut</strong> de l’agent. '
            + (creation ? 'Un critère créé hors note de service devra être couvert par un avenant.'
              : 'La portée de la modification vous sera demandée à l’enregistrement.'),
          { tone: 'warning', icon: 'shield-alert' }),
          f,
        ]),
        footer: [
          K.btn('Annuler', { onclick: function () { m.close(); } }),
          K.btn(creation ? 'Créer le critère' : 'Enregistrer', {
            variant: 'primary', icon: creation ? 'plus' : 'save',
            onclick: function () {
              var v = f.collect();
              if (!v) return;
              var sanctions = {
                bonne: Number(v.bonne) || 0,
                moyenne: Number(v.moyenne) || 0,
                faible: Number(v.faible) || 0,
              };
              var criteres = String(v.criteresTexte || '').split('\n')
                .map(function (x) { return x.trim(); }).filter(Boolean);
              if (creation) {
                colBareme().insert({
                  critereId: String(v.label).toLowerCase().replace(/[^a-z0-9]+/g, '_').slice(0, 20),
                  num: v.num, label: v.label, criteres: criteres, sanctions: sanctions,
                  dateEffet: C.iso(AUJ), version: 1,
                  source: 'Créé dans l’application le ' + C.dateFR(AUJ) + ' — à couvrir par un avenant',
                });
                m.close(); dessiner(); if (rafraichir) rafraichir();
                U.toast('Critère créé.', { type: 'success', detail: v.label });
                return;
              }
              m.close();
              demanderPorteeBareme(b, { num: v.num, label: v.label, criteres: criteres, sanctions: sanctions });
            },
          }),
        ],
      });
    }

    /* ----------------------------------------------------------------------
     * LA PORTÉE — reprise du mécanisme NS 132, non réinventée.
     * -------------------------------------------------------------------- */
    function demanderPorteeBareme(critere, valeurs) {
      var evals = S.collection('evaluations').active();
      var prononcees = evals.filter(function (e) { return (e.prelevementPct || 0) > 0; });
      var ecarts = ['bonne', 'moyenne', 'faible'].map(function (k) {
        return { niveau: k, avant: critere.sanctions[k] || 0, apres: valeurs.sanctions[k] || 0 };
      }).filter(function (x) { return x.avant !== x.apres; });

      var choix = { portee: 'futur' };
      var corps = el('div.space-y-3');
      corps.appendChild(el('div.flex.items-start.gap-3.rounded-lg.border.border-danger-200.bg-danger-50.p-3', null, [
        el('span.shrink-0.text-danger-600', null, C.icon('alert-triangle', 'h-5 w-5')),
        el('div.min-w-0', null, [
          el('p.text-sm.font-semibold.text-danger-900', { text: 'Cette modification touche des salaires.' }),
          el('p.mt-1.text-xs.text-danger-800', {
            text: C.num(prononcees.length) + ' évaluation(s) ont déjà donné lieu à une retenue. '
              + 'Les réévaluer changerait des sommes déjà prélevées.',
          }),
        ]),
      ]));

      if (ecarts.length) {
        corps.appendChild(K.miniTable([
          {
            label: 'Résultat', render: function (x) {
              var n = D.NS131.niveaux.filter(function (y) { return y.id === x.niveau; })[0];
              return n ? n.label : x.niveau;
            },
          },
          { label: 'Avant', align: 'right', render: function (x) { return x.avant + ' %'; } },
          { label: 'Après', align: 'right', render: function (x) { return x.apres + ' %'; } },
          {
            label: 'Écart', align: 'right',
            render: function (x) {
              var d = x.apres - x.avant;
              return el('span', {
                class: d > 0 ? 'font-semibold text-danger-700' : 'font-semibold text-success-700',
                text: (d > 0 ? '+' : '') + d + ' pt',
              });
            },
          },
        ], ecarts));
      }

      function option(id, titre, detail, badge) {
        var d = el('label.flex.cursor-pointer.items-start.gap-3.rounded-lg.border.p-3.transition-colors', {
          class: choix.portee === id ? 'border-navy-400 bg-navy-50' : 'border-slate-200 hover:bg-slate-50',
        });
        var r = el('input.mt-0\\.5', { type: 'radio', name: 'portee-bareme', value: id });
        r.checked = choix.portee === id;
        r.addEventListener('change', function () {
          choix.portee = id;
          [].forEach.call(corps.querySelectorAll('label[class*=border]'), function (x) {
            x.className = 'flex cursor-pointer items-start gap-3 rounded-lg border p-3 transition-colors '
              + (x.querySelector('input').checked ? 'border-navy-400 bg-navy-50' : 'border-slate-200 hover:bg-slate-50');
          });
        });
        d.appendChild(r);
        d.appendChild(el('div.min-w-0', null, [
          el('p.text-sm.font-semibold.text-slate-800', { text: titre }),
          el('p.mt-0\\.5.text-xs.text-slate-500', { text: detail }),
        ]));
        if (badge) d.appendChild(U.badge(badge[0], badge[1]));
        return d;
      }

      corps.appendChild(option('futur', 'Évaluations à venir seulement',
        'La version actuelle est archivée avec sa période de validité ; la nouvelle prend effet le '
        + C.dateFR(AUJ) + '. Les retenues déjà prélevées restent justifiables par le barème d’alors.',
        ['Recommandé', 'success']));
      corps.appendChild(option('tout', 'Y compris les évaluations déjà prononcées',
        'Le barème est réécrit depuis sa date d’effet d’origine. Les ' + C.num(prononcees.length)
        + ' évaluation(s) déjà prononcées seront recalculées à un taux différent de celui qui a été '
        + 'notifié aux agents. À réserver à la correction d’une erreur de saisie.',
        ['Rétroactif', 'danger']));
      U.icons(corps);

      var m = U.modal({
        title: 'Portée de la modification', subtitle: critere.label, size: 'lg', body: corps,
        footer: [
          K.btn('Annuler', { onclick: function () { m.close(); } }),
          K.btn('Appliquer', {
            variant: 'primary', icon: 'check',
            onclick: function () {
              if (choix.portee === 'futur') {
                colHistoriqueBareme().insert({
                  critereId: critere.critereId, num: critere.num, label: critere.label,
                  criteres: (critere.criteres || []).slice(),
                  sanctions: Object.assign({}, critere.sanctions),
                  dateEffet: critere.dateEffet, dateFin: C.iso(C.addDays(AUJ, -1)),
                  remplacePar: 'Version du ' + C.dateFR(AUJ), archivePar: S.currentUser(),
                });
              }
              var res = colBareme().update(critere.id, Object.assign({}, valeurs, {
                dateEffet: choix.portee === 'futur' ? C.iso(AUJ) : critere.dateEffet,
                version: (critere.version || 1) + 1,
                portee: choix.portee, modifieLe: C.iso(AUJ), modifiePar: S.currentUser(),
              }));
              S.log('Modification du barème NS 131', 'M10', 'Barème', critere.critereId,
                { sanctions: critere.sanctions }, { sanctions: valeurs.sanctions, portee: choix.portee });
              m.close(); dessiner(); if (rafraichir) rafraichir();
              U.toast('Barème modifié.', {
                type: choix.portee === 'tout' ? 'warning' : 'success', duration: 8000,
                detail: choix.portee === 'tout'
                  ? 'Application RÉTROACTIVE — les évaluations prononcées changeront de retenue.'
                  : 'Applicable à compter du ' + C.dateFR(AUJ) + ' ; l’historique est préservé.',
                undo: function () { res.undo(); dessiner(); if (rafraichir) rafraichir(); },
              });
            },
          }),
        ],
      });
    }

    function archiverCritere(b) {
      U.confirm({
        title: 'Retirer le critère « ' + b.label + ' » ?',
        message: 'Ce critère cesse d’être évalué. Les évaluations déjà prononcées ne changent pas — '
          + 'les versions antérieures du barème restent consultables.<br><br>'
          + 'Conformément à <strong>RG-14</strong>, le critère est <strong>archivé</strong> et non supprimé. '
          + 'Un critère institué par note de service ne peut être retiré que par une note qui l’abroge.',
        confirmLabel: 'Retirer le critère', danger: true, requireMotif: true,
      }).then(function (rep) {
        if (!rep) return;
        colHistoriqueBareme().insert({
          critereId: b.critereId, num: b.num, label: b.label,
          criteres: (b.criteres || []).slice(), sanctions: Object.assign({}, b.sanctions),
          dateEffet: b.dateEffet, dateFin: C.iso(C.addDays(AUJ, -1)),
          remplacePar: 'Critère retiré — ' + rep.motif, archivePar: S.currentUser(),
        });
        var res = colBareme().archive(b.id, rep.motif);
        dessiner(); if (rafraichir) rafraichir();
        U.toast('Critère retiré du barème.', {
          type: 'success', detail: 'Archivage logique (RG-14) — restaurable depuis la corbeille.',
          undo: function () { res.undo(); dessiner(); if (rafraichir) rafraichir(); },
        });
      });
    }
  }

  global.SIGH.screen('m10-evaluations', {
    title: 'Évaluations mensuelles (NS 131)',
    description: 'Évaluation du rendement selon les quatre critères de la note de service, avec calcul automatique du prélèvement sur salaire brut.',
    regle: 'Barème de la note <strong>' + D.NS131.reference + '</strong>, en vigueur depuis le ' + C.dateFR(D.NS131.dateEffet)
      + '. Le prélèvement total s’applique au <strong>salaire brut</strong> de l’agent.',
    render: function (root) {
      var col = S.collection('evaluations', { module: 'M10', entite: 'EvaluationPersonnel' });

      /* Le mois écoulé est déjà évalué : sans cela l'écran s'ouvrirait vide et
         la fiche d'évaluation resterait inaccessible tant qu'aucune n'aurait
         été saisie. */
      (function amorcer() {
        var db = S.raw();
        if (db.evaluations && db.evaluations.length) return;
        var rnd = C.seeded(1131), n = 0;
        var mois = C.MOIS[AUJ.getMonth() - 1 < 0 ? 11 : AUJ.getMonth() - 1];
        var periode = mois.charAt(0).toUpperCase() + mois.slice(1) + ' 2026';
        db.evaluations = personnel().slice(0, 24).map(function (e) {
          var criteres = {};
          D.NS131.criteres.forEach(function (c) {
            criteres[c.id] = C.pick(rnd, ['bonne', 'bonne', 'bonne', 'moyenne', 'faible']);
          });
          var pct = D.NS131.prelevement(criteres);
          return {
            id: 'EVAL' + C.pad(++n, 4),
            reference: 'EV-2026-' + C.pad(n, 4),
            employeId: e.id, employe: e.nomComplet, matricule: e.matricule,
            service: e.service, fonction: e.fonction, categorie: e.categorie,
            periode: periode, criteres: criteres,
            prelevementPct: pct,
            prelevementMontant: Math.round(e.salaireBase * pct / 100),
            salaireBrut: e.salaireBase,
            observations: '',
            evaluateur: 'TAKI Alimatou',
            statut: 'actif',
          };
        });
        S.save();
      })();
      var host = el('div.space-y-4');
      var table;

      /* Le barème, administrable — une seule représentation, sans quoi le
         rappel figé et le référentiel divergeraient au premier changement. */
      var blocBareme = el('div');
      host.appendChild(blocBareme);
      function rendreBareme() {
        C.clear(blocBareme);
        blocBareme.appendChild(blocBaremeNS131(function () { if (table) table.refresh(); }));
        blocBareme.appendChild(el('div.mt-2.flex.justify-end', null,
          K.btn('Imprimer la note', { size: 'sm', icon: 'printer', onclick: imprimerNote })));
        U.icons(blocBareme);
      }
      rendreBareme();


      host.appendChild(U.kpiGrid([
        { label: 'Évaluations enregistrées', value: C.num(col.active().length), icon: 'clipboard-check', tone: 'navy' },
        { label: 'Agents à évaluer', value: C.num(personnel().length), icon: 'users-round', tone: 'info' },
        { label: 'Avec prélèvement', value: C.num(col.active().filter(function (e) { return e.prelevementPct > 0; }).length), icon: 'trending-down', tone: 'danger' },
        { label: 'Montant prélevé', value: C.money(C.sum(col.active(), 'prelevementMontant')), icon: 'wallet', tone: 'warning' },
      ]));

      table = U.dataTable({
        title: 'Évaluations mensuelles',
        rows: function () { return col.active(); },
        exportName: 'evaluations', pageSize: 12,
        defaultSort: 'periode', defaultDir: 'desc',
        emptyMessage: 'Aucune évaluation enregistrée.',
        emptyHint: 'Établir une fiche d’évaluation mensuelle pour un agent.',
        actions: [K.commande('Nouvelle évaluation', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(); } })].filter(Boolean),
        columns: [
          { key: 'periode', label: 'Période', nowrap: true },
          { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true },
          { key: 'employe', label: 'Agent' },
          { key: 'service', label: 'Service' },
        ].concat(D.NS131.criteres.map(function (c) {
          return {
            key: 'crit_' + c.id, label: c.label.split(' ')[0],
            value: function (e) { return (e.criteres || {})[c.id]; },
            text: function (e) { return (e.criteres || {})[c.id] || ''; },
            render: function (e) {
              var n = (e.criteres || {})[c.id];
              var m = { bonne: ['Bonne', 'success'], moyenne: ['Moyenne', 'warning'], faible: ['Faible', 'danger'] };
              var x = m[n] || ['—', 'neutral'];
              return U.badge(x[0], x[1]);
            },
          };
        })).concat([
          {
            key: 'prelevementPct', label: 'Prélèvement', align: 'right',
            render: function (e) {
              return e.prelevementPct > 0
                ? el('span.font-semibold.text-danger-600', { text: '− ' + e.prelevementPct + ' %' })
                : U.badge('Aucun', 'success');
            },
          },
          {
            key: 'prelevementMontant', label: 'Montant', align: 'right',
            text: function (e) { return C.money(e.prelevementMontant || 0, false); },
            render: function (e) { return C.money(e.prelevementMontant || 0, false); },
          },
        ]),
        onRowClick: function (e) { consulter(e); },
        rowActions: function (e) {
          return [
            K.iconBtn('printer', 'Imprimer la fiche', function () { etatFiche(e); }),
            K.iconBtn('pencil', 'Modifier', function () { ouvrir(e); }),
          ];
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function ouvrir(record) {
        var champs = [
          { name: 'employeId', label: 'Agent', type: 'select', required: true, options: optionsEmployes(), col: 'full' },
          { name: 'periode', label: 'Période évaluée', type: 'select', required: true, options: C.MOIS.map(function (m) { return m.charAt(0).toUpperCase() + m.slice(1) + ' 2026'; }) },
          { type: 'section', label: 'Éléments d’évaluation — barème ' + D.NS131.reference },
        ];
        D.NS131.criteres.forEach(function (c) {
          champs.push({
            name: 'crit_' + c.id, label: c.num + ' — ' + c.label, type: 'select', required: true,
            options: D.NS131.niveaux.map(function (n) {
              return { value: n.id, label: n.label + (c.sanctions[n.id] ? ' (− ' + c.sanctions[n.id] + ' %)' : ' (aucune sanction)') };
            }),
            help: c.criteres.join(' · '),
            col: 'full',
          });
        });
        champs.push({ name: 'observations', label: 'Observations de l’évaluateur', type: 'textarea', rows: 2, col: 'full' });

        var valeurs = record ? Object.assign({}, record) : { periode: C.MOIS[AUJ.getMonth()].charAt(0).toUpperCase() + C.MOIS[AUJ.getMonth()].slice(1) + ' 2026' };
        if (record && record.criteres) {
          D.NS131.criteres.forEach(function (c) { valeurs['crit_' + c.id] = record.criteres[c.id]; });
        } else {
          D.NS131.criteres.forEach(function (c) { valeurs['crit_' + c.id] = 'bonne'; });
        }

        var f = U.form(champs, valeurs);
        var apercu = el('div.mt-3');

        function majApercu() {
          var evalv = {};
          D.NS131.criteres.forEach(function (c) {
            var ctrl = f.controls['crit_' + c.id];
            evalv[c.id] = ctrl ? ctrl.value : 'bonne';
          });
          var pct = D.NS131.prelevement(evalv);
          var emp = personnel().filter(function (x) { return x.id === f.controls.employeId.value; })[0];
          var brut = emp ? emp.salaireBase : 0;
          C.clear(apercu);
          apercu.appendChild(U.kpiGrid([
            { label: 'Salaire brut de référence', value: C.money(brut), icon: 'banknote', tone: 'navy' },
            { label: 'Prélèvement total', value: pct + ' %', icon: 'trending-down', tone: pct > 0 ? 'danger' : 'success' },
            { label: 'Montant prélevé', value: C.money(Math.round(brut * pct / 100)), icon: 'wallet', tone: pct > 0 ? 'danger' : 'success' },
            { label: 'Salaire brut restant', value: C.money(brut - Math.round(brut * pct / 100)), icon: 'check-circle-2', tone: 'success' },
          ], 'grid-cols-2 lg:grid-cols-4'));
          U.icons(apercu);
        }

        D.NS131.criteres.forEach(function (c) {
          var ctrl = f.controls['crit_' + c.id];
          if (ctrl) ctrl.addEventListener('change', majApercu);
        });
        f.controls.employeId.addEventListener('change', majApercu);

        var body = el('div.space-y-3', null, [f, apercu]);
        setTimeout(majApercu, 0);

        var m = U.modal({
          title: record ? 'Modifier l’évaluation' : 'Nouvelle fiche d’évaluation',
          subtitle: D.NS131.reference + ' — prélèvement calculé automatiquement sur le salaire brut',
          size: 'lg', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(record ? 'Enregistrer' : 'Valider l’évaluation', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var emp = personnel().filter(function (x) { return x.id === v.employeId; })[0];
                var criteres = {};
                D.NS131.criteres.forEach(function (c) { criteres[c.id] = v['crit_' + c.id]; });
                var pct = D.NS131.prelevement(criteres);
                var enr = {
                  employeId: v.employeId,
                  employe: emp ? emp.nomComplet : '', matricule: emp ? emp.matricule : '',
                  service: emp ? emp.service : '', fonction: emp ? emp.fonction : '',
                  categorie: emp ? emp.categorie : '',
                  periode: v.periode, criteres: criteres,
                  prelevementPct: pct,
                  prelevementMontant: emp ? Math.round(emp.salaireBase * pct / 100) : 0,
                  salaireBrut: emp ? emp.salaireBase : 0,
                  observations: v.observations,
                  reference: (record && record.reference) || C.nextRef('EV-', 4),
                  evaluateur: S.currentUser(),
                };
                var res = record ? col.update(record.id, enr) : col.insert(enr);
                m.close(); table.refresh();
                U.toast('Évaluation enregistrée — prélèvement de ' + pct + ' %.', {
                  type: pct > 0 ? 'warning' : 'success',
                  detail: pct > 0 ? C.money(enr.prelevementMontant) + ' seront retenus sur le salaire brut.' : 'Aucune sanction.',
                  undo: function () { res.undo(); table.refresh(); },
                });
              },
            }),
          ],
        });
      }

      function consulter(e) {
        var d = U.drawer({
          title: 'Évaluation — ' + e.employe, subtitle: e.periode + ' — ' + e.reference, width: 'max-w-2xl',
          body: el('div.space-y-4', null, [
            U.kpiGrid([
              { label: 'Prélèvement', value: e.prelevementPct + ' %', icon: 'trending-down', tone: e.prelevementPct > 0 ? 'danger' : 'success' },
              { label: 'Montant retenu', value: C.money(e.prelevementMontant || 0), icon: 'wallet', tone: e.prelevementPct > 0 ? 'danger' : 'success' },
            ], 'grid-cols-2'),
            U.descList([['Agent', e.employe], ['Matricule', e.matricule], ['Service', e.service],
              ['Catégorie', e.categorie], ['Période', e.periode], ['Évaluateur', e.evaluateur],
              ['Salaire brut', C.money(e.salaireBrut || 0)]]),
            U.card('Détail par critère', K.miniTable([
              { label: 'N°', key: 'num' },
              { label: 'Élément d’évaluation', key: 'label' },
              {
                label: 'Résultat',
                render: function (c) {
                  var n = (e.criteres || {})[c.id];
                  var m = { bonne: ['Bonne', 'success'], moyenne: ['Moyenne', 'warning'], faible: ['Faible à mauvaise', 'danger'] };
                  var x = m[n] || ['—', 'neutral'];
                  return U.badge(x[0], x[1]);
                },
              },
              {
                label: 'Prélèvement', align: 'right',
                render: function (c) {
                  var p = c.sanctions[(e.criteres || {})[c.id]] || 0;
                  return p ? el('span.font-semibold.text-danger-600', { text: '− ' + p + ' %' }) : '—';
                },
              },
            ], D.NS131.criteres)),
            e.observations ? U.card('Observations', el('p.text-sm.text-slate-700', { text: e.observations })) : null,
          ]),
          footer: [
            K.btn('Imprimer la fiche', { icon: 'printer', onclick: function () { etatFiche(e); } }),
            K.btn('Modifier l’évaluation', {
              variant: 'primary', icon: 'pencil',
              onclick: function () { d.close(); ouvrir(e); },
            }),
          ],
        });
      }

      /* Reproduction fidèle de la fiche d'évaluation et de solde de la clinique. */
      function etatFiche(e) {
        var emp = personnel().filter(function (x) { return x.id === e.employeId; })[0];
        var a = emp ? anciennete(emp) : { ans: 0, mois: 0 };
        var mois = AUJ.getMonth(), annee = AUJ.getFullYear();
        var gardes = emp ? compter(emp.id, annee, mois, 'garde') : 0;
        var permanences = emp ? compter(emp.id, annee, mois, 'permanence') : 0;
        var primeGarde = emp ? D.NS132.montant('garde', emp.fonction) * gardes : 0;
        var primePermanence = emp ? D.NS132.montant('permanence', emp.fonction) * permanences : 0;
        var primeAccueil = emp ? D.NS132.montant('accueil', emp.fonction) : 0;
        var brut = (e.salaireBrut || 0) + primeGarde + primePermanence + primeAccueil;
        var prelev = Math.round(brut * (e.prelevementPct || 0) / 100);

        /* Colonne gauche : éléments d'évaluation ; colonne droite : éléments de solde. */
        var deuxColonnes = el('div.grid.grid-cols-2.gap-3');

        var gauche = el('div');
        gauche.appendChild(P.tableau([
          { label: 'N°', key: 'num' },
          { label: 'Éléments d’évaluation', key: 'label' },
          { label: '1) Résultat  2) Sanction  3) Prélèvement', value: function (c) {
            var n = (e.criteres || {})[c.id];
            var lib = { bonne: 'Bonne', moyenne: 'Moyenne', faible: 'Faible à mauvaise' }[n] || '';
            var p = c.sanctions[n] || 0;
            return '1) ' + lib + '   2) ' + (p ? p + ' %' : 'Aucune') + '   3) ' + (p ? C.money(Math.round(brut * p / 100), false) : '0');
          } },
        ], D.NS131.criteres, {
          total: { num: '', label: '', '1) Résultat  2) Sanction  3) Prélèvement': '' },
          totalLabel: 'TOTAL À PRÉLEVER : ' + C.money(prelev, false),
        }));
        deuxColonnes.appendChild(gauche);

        var droite = el('div');
        droite.appendChild(P.tableau([
          { label: 'N°', key: 'n' },
          { label: 'Éléments de solde', key: 'libelle' },
          { label: 'Montant', key: 'montant', align: 'right' },
        ], [
          { n: '01', libelle: 'SALAIRE DE BASE', montant: C.money(e.salaireBrut || 0, false) },
          { n: '02', libelle: 'PRIME D’ANCIENNETÉ', montant: a.ans >= 2 ? C.money(Math.round((e.salaireBrut || 0) * 0.02 * a.ans), false) : '' },
          { n: '03', libelle: 'PRIME DE GARDE', montant: primeGarde ? C.money(primeGarde, false) : '' },
          { n: '04', libelle: 'PRIME DE PERMANENCE', montant: primePermanence ? C.money(primePermanence, false) : '' },
          { n: '05', libelle: 'PRIME D’ACCUEIL', montant: primeAccueil ? C.money(primeAccueil, false) : '' },
          { n: '', libelle: 'AUTRE PRIME', montant: '' },
          { n: '', libelle: 'SALAIRE BRUT', montant: C.money(brut, false) },
          { n: '', libelle: 'SALAIRE BRUT RESTANT', montant: C.money(brut - prelev, false) },
        ]));
        deuxColonnes.appendChild(droite);

        P.etat({
          titre: 'Fiche d’évaluation du mois de ' + (e.periode || '').toUpperCase(),
          cartouche: [
            ['Nom et prénoms', e.employe],
            ['Numéro matricule', e.matricule],
            ['Ancienneté', a.ans + ' ans ' + a.mois + ' mois'],
            ['Catégorie / Échelon', e.categorie],
            ['Service', e.service],
            ['Référence barème', D.NS131.reference],
          ],
          contenu: deuxColonnes,
          signatures: [{ role: 'L’Évaluateur', nom: e.evaluateur },
            { role: 'L’Agent', nom: e.employe },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou épse BASSONGUI' }],
        });
      }

      function imprimerNote() {
        P.etat({
          titre: 'Note de service',
          sousTitre: 'N/Réf. : ' + D.NS131.reference,
          cartouche: [['Référence', D.NS131.reference], ['Objet', 'Évaluation du rendement'],
            ['Date de signature', C.dateFR(D.NS131.dateSignature)], ['Date d’effet', C.dateFR(D.NS131.dateEffet)],
            ['Version', 'v' + D.NS131.version], ['Statut', D.NS131.statut]],
          contenu: el('div.space-y-3', null, [
            el('p', {
              text: 'Le Directeur Médical de la Clinique NASSIERA TOO informe tous ses Agents qu’il est procédé à la '
                + 'modification de l’évaluation du rendement entrant dans le compte de la rémunération salariale. '
                + 'La nouvelle formule d’évaluation est présentée dans le tableau ci-dessous.',
            }),
            P.tableau([
              { label: 'N°', key: 'num' },
              { label: 'Éléments d’évaluation', key: 'label' },
              { label: 'Critères', value: function (c) { return c.criteres.join(' ; '); } },
              { label: 'Bonne', value: function () { return 'Aucune'; } },
              { label: 'Moyenne (1er niveau)', value: function (c) { return '1 à 2 — moins ' + c.sanctions.moyenne + ' % du salaire brut'; } },
              { label: 'Faible à mauvaise (2e niveau)', value: function (c) { return '3 et plus — ' + c.sanctions.faible + ' % du salaire brut'; } },
            ], D.NS131.criteres),
            el('p.mt-3', { text: D.NS131.mention + ' Entre en vigueur à compter de sa date de signature.' }),
            el('p.mt-2.text-\\[10px\\]', { text: 'Ampliation : ' + D.NS131.ampliation }),
          ]),
          signatures: [{ role: 'Le Directeur Médical', nom: D.NS131.signataire }],
        });
      }
    },
  });

  /* ==========================================================================
   * SANCTIONS
   * ======================================================================== */
  global.SIGH.screen('m10-sanctions', {
    title: 'Sanctions',
    regle: 'Écran <strong>calculé</strong> : une sanction découle d’une évaluation NS 131 dont la retenue est '
      + 'supérieure à zéro. Elle ne se saisit pas ici — pour la corriger, modifier l’évaluation d’origine, '
      + 'ce qui recalcule la retenue et laisse trace du motif (RG-12).',
    description: 'Sanctions issues des évaluations mensuelles et sanctions disciplinaires, avec incidence sur le salaire.',
    render: function (root) {
      var evals = S.collection('evaluations').active().filter(function (e) { return e.prelevementPct > 0; });
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Sanctions prononcées', value: C.num(evals.length), icon: 'gavel', tone: 'danger' },
        { label: 'Agents concernés', value: C.num(Object.keys(C.groupBy(evals, 'employeId')).length), icon: 'users', tone: 'warning' },
        { label: 'Montant total retenu', value: C.money(C.sum(evals, 'prelevementMontant')), icon: 'wallet', tone: 'danger' },
        { label: 'Prélèvement moyen', value: (evals.length ? Math.round(C.sum(evals, 'prelevementPct') / evals.length) : 0) + ' %', icon: 'percent', tone: 'neutral' },
      ]));

      host.appendChild(K.note('Les sanctions sont exclusivement issues du barème <strong>' + D.NS131.reference
        + '</strong>. Aucune retenue ne peut être appliquée hors de ce cadre.', { tone: 'warning', icon: 'shield-alert' }));

      host.appendChild(U.dataTable({
        title: 'Registre des sanctions', rows: evals, exportName: 'sanctions', pageSize: 15,
        defaultSort: 'periode', defaultDir: 'desc',
        emptyMessage: 'Aucune sanction prononcée.',
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (e) { return el('span.font-mono.text-xs', { text: e.reference }); } },
          { key: 'periode', label: 'Période' },
          { key: 'employe', label: 'Agent' },
          { key: 'service', label: 'Service' },
          {
            key: 'motifs', label: 'Critères sanctionnés', sortable: false,
            text: function (e) {
              return D.NS131.criteres.filter(function (c) { return (c.sanctions[(e.criteres || {})[c.id]] || 0) > 0; })
                .map(function (c) { return c.label; }).join(', ');
            },
            render: function (e) {
              var liste = D.NS131.criteres.filter(function (c) { return (c.sanctions[(e.criteres || {})[c.id]] || 0) > 0; });
              if (!liste.length) return '—';
              return el('div.flex.flex-wrap.gap-1', null, liste.map(function (c) {
                return U.badge(c.label, 'danger');
              }));
            },
          },
          { key: 'prelevementPct', label: 'Retenue', align: 'right', render: function (e) { return el('span.font-semibold.text-danger-600', { text: e.prelevementPct + ' %' }); } },
          { key: 'prelevementMontant', label: 'Montant', align: 'right', text: function (e) { return C.money(e.prelevementMontant, false); }, render: function (e) { return C.money(e.prelevementMontant, false); } },
        ],
        rowActions: function (e) {
          return [K.iconBtn('printer', 'Notification de sanction', function () {
            P.etat({
              titre: 'Notification de sanction',
              sousTitre: e.reference + ' — ' + e.periode,
              cartouche: [['Agent', e.employe], ['Matricule', e.matricule], ['Service', e.service],
                ['Période', e.periode], ['Retenue', e.prelevementPct + ' %'], ['Montant', C.money(e.prelevementMontant)]],
              contenu: el('div.space-y-3', null, [
                el('p', { text: 'À la suite de l’évaluation du rendement du mois de ' + e.periode + ', et en application du barème '
                  + D.NS131.reference + ', il est procédé à une retenue de ' + e.prelevementPct + ' % sur votre salaire brut, '
                  + 'soit un montant de ' + C.money(e.prelevementMontant) + '.' }),
                P.tableau([
                  { label: 'Élément d’évaluation', key: 'label' },
                  { label: 'Résultat', value: function (c) {
                    return { bonne: 'Bonne', moyenne: 'Moyenne', faible: 'Faible à mauvaise' }[(e.criteres || {})[c.id]] || '—';
                  } },
                  { label: 'Retenue', align: 'right', value: function (c) {
                    var p = c.sanctions[(e.criteres || {})[c.id]] || 0;
                    return p ? p + ' %' : '—';
                  } },
                ], D.NS131.criteres),
                e.observations ? el('p.mt-2.italic', { text: 'Observations : ' + e.observations }) : null,
              ]),
              signatures: [{ role: 'L’Agent', nom: e.employe, mention: 'Pris connaissance' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
                { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
            });
          })];
        },
      }));

      /* --- Lecture graphique des sanctions ------------------------------ */
      if (evals.length) {
        var parService = C.groupBy(evals, function (e) { return e.service || serviceDe(e) || 'Non renseigné'; });

        /* Un critère est « sanctionné » quand son résultat entraîne une retenue.
           C'est le croisement qui intéresse la Direction : sur quel axe du
           barème NS 131 la clinique perd-elle le plus de points ? */
        var parCritere = D.NS131.criteres.map(function (c) {
          var touchees = evals.filter(function (e) {
            var r = (e.criteres || {})[c.id];
            return r && (c.sanctions[r] || 0) > 0;
          });
          return {
            label: c.label, n: touchees.length,
            montant: C.sum(touchees, 'prelevementMontant'),
          };
        }).sort(function (a, b) { return b.n - a.n; });

        var parPeriode = C.groupBy(evals, 'periode');
        var periodes = Object.keys(parPeriode);

        host.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Sanctions par direction et service',
            G.barres(Object.keys(parService),
              [{ label: 'Sanctions', data: Object.keys(parService).map(function (k) { return parService[k].length; }), color: G.TONES.rouge }],
              { horizontal: true, height: 260 })),
          U.card('Critères sanctionnés (NS 131)',
            G.barres(parCritere.map(function (c) { return c.label; }),
              [{ label: 'Agents concernés', data: parCritere.map(function (c) { return c.n; }), color: G.TONES.orange }],
              { horizontal: true, height: 260 })),
          U.card('Montant retenu par critère',
            G.camembert(parCritere.filter(function (c) { return c.montant > 0; }).map(function (c) { return c.label; }),
              parCritere.filter(function (c) { return c.montant > 0; }).map(function (c) { return c.montant; }),
              { height: 260, legend: 'bottom' })),
        ]));

        if (periodes.length > 1) {
          host.appendChild(U.card('Évolution des retenues',
            G.ligne(periodes, [
              { label: 'Sanctions', data: periodes.map(function (m) { return parPeriode[m].length; }), color: G.TONES.rouge },
            ], { height: 240 })));
        }

        host.appendChild(K.note('Les quatre axes du barème <strong>' + D.NS131.reference + '</strong> — ponctualité '
          + 'et assiduité, exécution des tâches, attitude envers les patients, respect de la hiérarchie — '
          + 'ne pèsent pas du même poids. Ce croisement montre lequel appelle une action de la Direction, '
          + 'plutôt que de traiter les sanctions une à une.', { tone: 'info' }));
      }

      root.appendChild(host);
      return null;

      /** Le service d'un agent, retrouvé depuis son évaluation. */
      function serviceDe(e) {
        var ag = personnel().filter(function (x) { return x.id === e.employeId; })[0];
        return ag ? ag.service : null;
      }
    },
  });

  /* ==========================================================================
   * PRIMES — moteur NS 132
   * ======================================================================== */
  global.SIGH.screen('m10-primes', {
    title: 'Primes diverses (NS 132)',
    description: 'Grille des primes par fonction et calcul des primes acquises à partir du planning validé.',
    regle: 'Grille de la note <strong>' + D.NS132.reference + '</strong>, en vigueur depuis le ' + C.dateFR(D.NS132.dateEffet)
      + '. <strong>RG-11</strong> — les primes de garde et de permanence sont calculées automatiquement à partir du planning validé.',
    render: function (root) {
      var host = el('div.space-y-4');
      var colonnes = ['aide_soignant', 'caissiere', 'accueil', 'infirmier', 'sage_femme', 'tsl'];
      var blocGrille = el('div');
      var blocAcquises = el('div');

      host.appendChild(blocGrille);
      host.appendChild(blocAcquises);
      rendreGrille();
      rendreAcquises();
      root.appendChild(host);
      return null;

      function colGrille() {
        return S.collection('grillePrimes', { module: 'M10', entite: 'prime', prefix: 'GPR' });
      }
      function colHistorique() {
        return S.collection('historiquePrimes', { module: 'M10', entite: 'version de prime', prefix: 'HPR' });
      }

      function rendreGrille() {
      C.clear(blocGrille);
      /* Grille NS 132 reproduite fidèlement */
      var grilleWrap = el('div.overflow-x-auto');
      var t = el('table.tbl');
      var thead = el('thead'), htr = el('tr');
      htr.appendChild(el('th', { text: 'Prime' }));
      htr.appendChild(el('th', { text: 'Mode' }));
      colonnes.forEach(function (f) {
        htr.appendChild(el('th.text-right', { text: fonctionLabel(f).toUpperCase() }));
      });
      htr.appendChild(el('th.text-right', { text: 'En vigueur' }));
      htr.appendChild(el('th.text-right', { text: '' }));
      thead.appendChild(htr); t.appendChild(thead);
      var tb = el('tbody');
      var lignesGrille = colGrille().active();
      lignesGrille.forEach(function (pr) {
        var tr = el('tr');
        tr.appendChild(el('td.text-sm.font-medium.text-slate-800', { text: pr.label }));
        tr.appendChild(el('td', null, U.badge(pr.mode === 'fixe' ? 'Forfait mensuel' : 'Par occurrence', pr.mode === 'fixe' ? 'navy' : 'info')));
        colonnes.forEach(function (f) {
          var v = (pr.montants || {})[f];
          tr.appendChild(el('td.text-right.num', null, v
            ? el('span.font-semibold.text-slate-800', { text: C.money(v, false) })
            : el('span.text-slate-300', { text: '—' })));
        });
        tr.appendChild(el('td.text-right', null,
          el('span.text-xs.text-slate-500', { text: pr.dateEffet ? C.dateFR(pr.dateEffet) : '—' })));
        var actes = [];
        if (K.droits('M10').editer) actes.push(K.iconBtn('pencil', 'Modifier cette prime', function () { editerPrime(pr); }));
        if (K.droits('M10').annuler) actes.push(K.iconBtn('archive', 'Retirer cette prime', function () { archiverPrime(pr); }, 'ghost'));
        tr.appendChild(el('td.text-right.whitespace-nowrap', null, el('div.flex.justify-end.gap-1', null, actes)));
        tb.appendChild(tr);
      });
      t.appendChild(tb);
      grilleWrap.appendChild(t);

      var actionsGrille = [
        U.badge('Version ' + D.NS132.version + ' — ' + D.NS132.statut, 'success'),
      ];
      if (K.droits('M10').editer) {
        actionsGrille.push(K.btn('Nouvelle prime', {
          variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { editerPrime(null); },
        }));
      }
      actionsGrille.push(K.btn('Imprimer la note', { size: 'sm', icon: 'printer', onclick: imprimerNote }));
      blocGrille.appendChild(U.card('Grille des primes — ' + D.NS132.reference, grilleWrap, actionsGrille));

      var anciennes = colHistorique().active();
      if (anciennes.length) {
        blocGrille.appendChild(U.card('Versions antérieures',
          K.miniTable([
            { label: 'Prime', key: 'label' },
            { label: 'En vigueur du', render: function (v) { return v.dateEffet ? C.dateFR(v.dateEffet) : '—'; } },
            { label: 'au', render: function (v) { return v.dateFin ? C.dateFR(v.dateFin) : 'en cours'; } },
            {
              label: 'Montants', render: function (v) {
                return el('span.text-xs.text-slate-500', {
                  text: Object.keys(v.montants || {}).map(function (f) {
                    return fonctionLabel(f) + ' ' + C.money(v.montants[f], false);
                  }).join(' · ') || '—',
                });
              },
            },
            { label: 'Remplacée par', render: function (v) { return el('span.text-xs.text-slate-400', { text: v.remplaceePar || '—' }); } },
          ], C.sortBy(anciennes, 'dateFin').reverse()),
        ));
        blocGrille.appendChild(K.note('Ces versions ne sont pas de l’archive décorative : c’est en elles que le '
          + 'bulletin de paie retrouve le montant applicable à un mois passé. Les retirer rendrait un bulletin '
          + 'ancien irreproductible.', { tone: 'info', icon: 'history' }));
      }
      U.icons(blocGrille);
      }

      /* --------------------------------------------------------------------
       * CRUD de la grille.
       * ------------------------------------------------------------------ */
      function champsPrime() {
        return [
          { name: 'label', label: 'Intitulé de la prime', type: 'text', required: true, col: 'full' },
          {
            name: 'mode', label: 'Mode de calcul', type: 'select', required: true,
            options: [{ value: 'fixe', label: 'Forfait mensuel' }, { value: 'occurrence', label: 'Par occurrence' }],
            hint: 'Le forfait s’applique chaque mois ; l’occurrence se multiplie par le nombre relevé au planning.',
          },
        ].concat(colonnes.map(function (f) {
          return { name: 'm_' + f, label: fonctionLabel(f), type: 'number', min: 0, hint: 'FCFA — vide si non éligible' };
        }));
      }

      function editerPrime(prime) {
        var creation = !prime;
        var valeurs = { mode: 'fixe' };
        if (prime) {
          valeurs = { label: prime.label, mode: prime.mode };
          colonnes.forEach(function (f) { valeurs['m_' + f] = (prime.montants || {})[f] || ''; });
        }
        var f = U.form(champsPrime(), valeurs);
        var m = U.modal({
          title: creation ? 'Nouvelle prime' : 'Modifier « ' + prime.label + ' »',
          subtitle: D.NS132.reference, size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('<strong>RG-11</strong> — les primes de garde et de permanence sont calculées à partir du '
              + 'planning validé ; ce que l’on règle ici, c’est le <strong>montant unitaire</strong> par fonction. '
              + (creation ? 'Une prime créée hors note de service devra être couverte par un avenant.'
                : 'La portée de la modification vous sera demandée à l’enregistrement.'),
            { tone: 'warning', icon: 'shield-alert' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(creation ? 'Créer la prime' : 'Enregistrer', {
              variant: 'primary', icon: creation ? 'plus' : 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var montants = {};
                colonnes.forEach(function (x) {
                  var n = Number(v['m_' + x]);
                  if (n > 0) montants[x] = n;
                });
                if (creation) {
                  colGrille().insert({
                    primeId: C.slug ? C.slug(v.label) : v.label.toLowerCase().replace(/[^a-z0-9]+/g, '_'),
                    label: v.label, mode: v.mode, montants: montants,
                    dateEffet: C.iso(AUJ), version: D.NS132.version + 1,
                    source: 'Créée dans l’application le ' + C.dateFR(AUJ),
                  });
                  m.close(); rendreGrille(); rendreAcquises();
                  U.toast('Prime créée.', { type: 'success', detail: v.label });
                  return;
                }
                m.close();
                demanderPorteePrime(prime, { label: v.label, mode: v.mode, montants: montants });
              },
            }),
          ],
        });
      }

      /* --------------------------------------------------------------------
       * LA QUESTION QUI ENGAGE — portée d'une modification de prime.
       * --------------------------------------------------------------------
       * Une prime de garde relevée de 2 000 à 2 500 FCFA change le bulletin du
       * mois. Vaut-elle aussi pour les gardes de juillet, déjà payées ? La
       * réponse n'appartient pas au logiciel : elle appartient à la Direction,
       * et elle doit être posée à CHAQUE modification.
       * ------------------------------------------------------------------ */
      function demanderPorteePrime(prime, valeurs) {
        var ecarts = colonnes.map(function (f) {
          var avant = (prime.montants || {})[f] || 0;
          var apres = valeurs.montants[f] || 0;
          return { fonction: f, label: fonctionLabel(f), avant: avant, apres: apres, delta: apres - avant };
        }).filter(function (x) { return x.delta !== 0; });

        var choix = { portee: 'futur' };
        var corps = el('div.space-y-3');

        corps.appendChild(el('div.flex.items-start.gap-3.rounded-lg.border.border-danger-200.bg-danger-50.p-3', null, [
          el('span.shrink-0.text-danger-600', null, C.icon('alert-triangle', 'h-5 w-5')),
          el('div.min-w-0', null, [
            el('p.text-sm.font-semibold.text-danger-900', { text: 'Cette modification touche des salaires.' }),
            el('p.mt-1.text-xs.text-danger-800', {
              text: ecarts.length
                ? C.num(ecarts.length) + ' montant(s) modifié(s). Les primes des mois déjà calculés — et pour '
                  + 'certaines déjà payées — dépendent de cette grille.'
                : 'Aucun montant n’est modifié ; seul l’intitulé ou le mode change.',
            }),
          ]),
        ]));

        if (ecarts.length) {
          corps.appendChild(K.miniTable([
            { label: 'Fonction', key: 'label' },
            { label: 'Avant', align: 'right', render: function (x) { return x.avant ? C.money(x.avant, false) : '—'; } },
            { label: 'Après', align: 'right', render: function (x) { return x.apres ? C.money(x.apres, false) : '—'; } },
            {
              label: 'Écart', align: 'right',
              render: function (x) {
                return el('span', {
                  class: x.delta > 0 ? 'font-semibold text-danger-700' : 'font-semibold text-success-700',
                  text: (x.delta > 0 ? '+' : '') + C.money(x.delta, false),
                });
              },
            },
          ], ecarts));
        }

        function option(id, titre, detail, badge) {
          var d = el('label.flex.cursor-pointer.items-start.gap-3.rounded-lg.border.p-3.transition-colors', {
            class: choix.portee === id ? 'border-navy-400 bg-navy-50' : 'border-slate-200 hover:bg-slate-50',
          });
          var r = el('input.mt-0\.5', { type: 'radio', name: 'portee-prime', value: id });
          r.checked = choix.portee === id;
          r.addEventListener('change', function () {
            choix.portee = id;
            [].forEach.call(corps.querySelectorAll('label[class*=border]'), function (x) {
              x.className = 'flex cursor-pointer items-start gap-3 rounded-lg border p-3 transition-colors '
                + (x.querySelector('input').checked ? 'border-navy-400 bg-navy-50' : 'border-slate-200 hover:bg-slate-50');
            });
          });
          d.appendChild(r);
          d.appendChild(el('div.min-w-0', null, [
            el('p.text-sm.font-semibold.text-slate-800', { text: titre }),
            el('p.mt-0\.5.text-xs.text-slate-500', { text: detail }),
          ]));
          if (badge) d.appendChild(U.badge(badge[0], badge[1]));
          return d;
        }

        corps.appendChild(option('futur', 'Primes en cours et à venir seulement',
          'La version actuelle est archivée avec sa période de validité, et la nouvelle prend effet le '
          + C.dateFR(AUJ) + '. Les bulletins déjà édités restent reproductibles à l’identique.',
          ['Recommandé', 'success']));
        corps.appendChild(option('tout', 'Y compris les primes déjà calculées',
          'La grille est réécrite depuis sa date d’effet d’origine (' + C.dateFR(prime.dateEffet || D.NS132.dateEffet)
          + '). Les bulletins passés recalculeront des montants différents de ceux qui ont été remis aux agents. '
          + 'À réserver à la correction d’une erreur de saisie.',
          ['Rétroactif', 'danger']));
        U.icons(corps);

        var m = U.modal({
          title: 'Portée de la modification', subtitle: prime.label, size: 'lg', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Appliquer', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                if (choix.portee === 'futur') {
                  /* On fige la version sortante avant de la remplacer : c'est
                     elle que le bulletin d'un mois passé ira relire. */
                  colHistorique().insert({
                    primeId: prime.primeId, label: prime.label, mode: prime.mode,
                    montants: Object.assign({}, prime.montants),
                    dateEffet: prime.dateEffet || D.NS132.dateEffet,
                    dateFin: C.iso(C.addDays(AUJ, -1)),
                    remplaceePar: 'Version du ' + C.dateFR(AUJ),
                    archiveePar: S.currentUser(),
                  });
                }
                var res = colGrille().update(prime.id, Object.assign({}, valeurs, {
                  dateEffet: choix.portee === 'futur' ? C.iso(AUJ) : (prime.dateEffet || D.NS132.dateEffet),
                  version: (prime.version || 1) + 1,
                  portee: choix.portee, modifieeLe: C.iso(AUJ), modifieePar: S.currentUser(),
                }));
                S.log('Modification de la grille des primes', 'M10', 'Prime', prime.primeId,
                  { montants: prime.montants }, { montants: valeurs.montants, portee: choix.portee });
                m.close(); rendreGrille(); rendreAcquises();
                U.toast('Grille des primes modifiée.', {
                  type: choix.portee === 'tout' ? 'warning' : 'success',
                  detail: choix.portee === 'tout'
                    ? 'Application RÉTROACTIVE — les bulletins passés changeront de montant.'
                    : 'Applicable à compter du ' + C.dateFR(AUJ) + ' ; l’historique est préservé.',
                  undo: function () { res.undo(); rendreGrille(); rendreAcquises(); },
                });
              },
            }),
          ],
        });
      }

      function archiverPrime(prime) {
        U.confirm({
          title: 'Retirer la prime « ' + prime.label + ' » ?',
          message: '<strong>Attention.</strong> Cette prime cesse d’être calculée sur les bulletins à venir. '
            + 'Les bulletins déjà édités ne changent pas — les versions antérieures de la grille restent '
            + 'consultables.<br><br>'
            + 'Conformément à <strong>RG-14</strong>, la prime est <strong>archivée</strong> et non supprimée : '
            + 'elle reste restaurable depuis la corbeille. Une prime instituée par note de service ne peut '
            + 'être retirée que par une note qui l’abroge.',
          confirmLabel: 'Retirer la prime', danger: true, requireMotif: true,
        }).then(function (rep) {
          if (!rep) return;
          colHistorique().insert({
            primeId: prime.primeId, label: prime.label, mode: prime.mode,
            montants: Object.assign({}, prime.montants),
            dateEffet: prime.dateEffet || D.NS132.dateEffet,
            dateFin: C.iso(C.addDays(AUJ, -1)),
            remplaceePar: 'Prime retirée — ' + rep.motif,
            archiveePar: S.currentUser(),
          });
          var res = colGrille().archive(prime.id, rep.motif);
          rendreGrille(); rendreAcquises();
          U.toast('Prime retirée de la grille.', {
            type: 'success', detail: 'Archivage logique (RG-14) — restaurable depuis la corbeille.',
            undo: function () { res.undo(); rendreGrille(); rendreAcquises(); },
          });
        });
      }

      function rendreAcquises() {
        C.clear(blocAcquises);

      /* Calcul des primes acquises sur le mois */
      var mois = AUJ.getMonth(), annee = AUJ.getFullYear();
      var lignes = personnel().map(function (e) {
        var gardes = compter(e.id, annee, mois, 'garde');
        var permanences = compter(e.id, annee, mois, 'permanence');
        var pGarde = D.NS132.montant('garde', e.fonction) * gardes;
        var pPerm = D.NS132.montant('permanence', e.fonction) * permanences;
        var fixes = D.NS132.primes.filter(function (p) { return p.mode === 'fixe'; })
          .reduce(function (s, p) { return s + D.NS132.montant(p.id, e.fonction); }, 0);
        return {
          id: e.id, matricule: e.matricule, employe: e.nomComplet,
          fonction: e.fonction, service: e.service,
          gardes: gardes, permanences: permanences,
          primeGarde: pGarde, primePermanence: pPerm, primesFixes: fixes,
          total: pGarde + pPerm + fixes,
        };
      }).filter(function (l) { return l.total > 0; });

      blocAcquises.appendChild(U.kpiGrid([
        { label: 'Agents primés', value: C.num(lignes.length), icon: 'gift', tone: 'navy' },
        { label: 'Primes de garde', value: C.money(C.sum(lignes, 'primeGarde')), icon: 'moon', tone: 'danger' },
        { label: 'Primes de permanence', value: C.money(C.sum(lignes, 'primePermanence')), icon: 'sun', tone: 'warning' },
        { label: 'Total des primes du mois', value: C.money(C.sum(lignes, 'total')), icon: 'wallet', tone: 'success' },
      ]));

      blocAcquises.appendChild(U.dataTable({
        title: 'Primes acquises — ' + C.moisAnnee(AUJ),
        rows: lignes, exportName: 'primes', pageSize: 20,
        defaultSort: 'total', defaultDir: 'desc',
        filters: [
          { name: 'fonction', label: 'Fonction', options: optionsFonctions() },
          { name: 'service', label: 'Service', options: D.SERVICES },
        ],
        columns: [
          { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true },
          { key: 'employe', label: 'Agent' },
          { key: 'fonction', label: 'Fonction', text: fonctionLabel, render: function (l) { return U.badge(fonctionLabel(l.fonction), 'navy'); } },
          { key: 'gardes', label: 'Gardes', align: 'right' },
          { key: 'primeGarde', label: 'Prime de garde', align: 'right', text: function (l) { return C.money(l.primeGarde, false); }, render: function (l) { return C.money(l.primeGarde, false); } },
          { key: 'permanences', label: 'Perm.', align: 'right' },
          { key: 'primePermanence', label: 'Prime de permanence', align: 'right', text: function (l) { return C.money(l.primePermanence, false); }, render: function (l) { return C.money(l.primePermanence, false); } },
          { key: 'primesFixes', label: 'Primes fixes', align: 'right', text: function (l) { return C.money(l.primesFixes, false); }, render: function (l) { return C.money(l.primesFixes, false); } },
          {
            key: 'total', label: 'Total', align: 'right',
            text: function (l) { return C.money(l.total, false); },
            render: function (l) { return el('span.font-bold.text-navy-900', { text: C.money(l.total, false) }); },
          },
        ],
        actions: [K.btn('Éditer l’état des primes', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'État des primes diverses',
              sousTitre: C.moisAnnee(AUJ) + ' — barème ' + D.NS132.reference,
              cartouche: [['Période', C.moisAnnee(AUJ)], ['Agents primés', C.num(lignes.length)],
                ['Total des primes', C.money(C.sum(lignes, 'total'))],
                ['Référence', D.NS132.reference]],
              contenu: P.tableau([
                { label: 'Mat.', key: 'matricule' },
                { label: 'Agent', key: 'employe' },
                { label: 'Fonction', value: function (l) { return fonctionLabel(l.fonction); } },
                { label: 'Gardes', key: 'gardes', align: 'right' },
                { label: 'Prime garde', align: 'right', value: function (l) { return C.money(l.primeGarde, false); },
                  somme: function (l) { return l.primeGarde || 0; } },
                { label: 'Perm.', key: 'permanences', align: 'right' },
                { label: 'Prime perm.', align: 'right', value: function (l) { return C.money(l.primePermanence, false); },
                  somme: function (l) { return l.primePermanence || 0; } },
                { label: 'Primes fixes', align: 'right', value: function (l) { return C.money(l.primesFixes, false); },
                  somme: function (l) { return l.primesFixes || 0; } },
                { label: 'Total', align: 'right', value: function (l) { return C.money(l.total, false); },
                  somme: function (l) { return l.total || 0; } },
              ], C.sortBy(lignes, 'employe'), { total: true }),
              signatures: [{ role: 'Le Responsable RH' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
                { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
            });
          },
        })],
      }));
        U.icons(blocAcquises);
      }

      function imprimerNote() {
        P.etat({
          titre: 'Note de service — primes diverses',
          sousTitre: D.NS132.reference,
          cartouche: [['Référence', D.NS132.reference], ['Objet', D.NS132.objet],
            ['Date de signature', C.dateFR(D.NS132.dateSignature)], ['Date d’effet', C.dateFR(D.NS132.dateEffet)],
            ['Version', 'v' + D.NS132.version], ['Statut', D.NS132.statut]],
          contenu: el('div.space-y-3', null, [
            el('p', {
              text: 'Le Directeur Médical de la Clinique NASSIERA TOO informe le personnel que les diverses primes '
                + 'attribuées se présentent comme ci-après. Cette note de service, qui abroge toute disposition '
                + 'antérieure contraire, sera appliquée à compter de sa date de signature.',
            }),
            P.tableau([
              { label: 'PRIMES DIVERSES', key: 'label' },
            ].concat(colonnes.map(function (f) {
              return {
                label: fonctionLabel(f).toUpperCase(), align: 'right',
                value: function (p) { return p.montants[f] ? C.num(p.montants[f]) : ''; },
              };
            })), D.NS132.primes),
            el('p.mt-3.text-\\[10px\\]', { text: '* Pour les primes qui varient en fonction du nombre — ✱ pour les primes fixes.' }),
            el('p.mt-1.text-\\[10px\\]', { text: 'Reçu par : ' + D.NS132.recuPar }),
          ]),
          signatures: [{ role: 'Le Directeur Médical', nom: D.NS132.signataire }],
        });
      }
    },
  });

  /* ==========================================================================
   * PRESTATAIRES EXTERNES
   * ======================================================================== */
  global.SIGH.screen('m10-prestataires', {
    title: 'Prestataires externes',
    description: 'Intervenants extérieurs rémunérés à l’acte : circoncision, hydrotubation, accouchement, analyses, hospitalisation.',
    render: function (root) {
      var col = S.collection('prestataires', { module: 'M10', entite: 'PrestataireExterne' });
      if (!col.all().length) {
        var rnd = C.seeded(1531);
        var ACTES = ['Circoncision', 'Hydrotubation', 'Accouchement', 'Analyses spécialisées', 'Chirurgie', 'Échographie', 'Anesthésie'];
        for (var i = 0; i < 14; i++) {
          col.all().push({
            id: 'PRE' + C.pad(i + 1, 4), statut: 'actif',
            reference: 'PE-' + C.pad(i + 1, 4),
            nom: C.pick(rnd, ['Dr ', 'Dr ', 'M. ', 'Mme ']) + C.pick(rnd, ['SANNI', 'KORA', 'DAOUDA', 'PARAISO', 'HOUNKPATIN', 'ZIME', 'BANI']) + ' ' + C.pick(rnd, ['Idrissou', 'Bertine', 'Moussa', 'Colette', 'Salifou']),
            specialite: C.pick(rnd, ACTES),
            telephone: '0' + C.between(rnd, 1, 9) + C.between(rnd, 10000000, 99999999),
            tarifActe: C.between(rnd, 5, 60) * 1000,
            actesRealises: C.between(rnd, 1, 24),
            ifu: rnd() > 0.4 ? '32' + C.between(rnd, 10000000000, 99999999999) : null,
            factureNormalisee: rnd() > 0.35,
          });
        }
        S.save();
      }

      /* --------------------------------------------------------------------
       * Les prestations externes vues d'ensemble.
       * La question posée par la Direction n'est pas « qui est référencé »
       * mais « combien nous coûtent les intervenants extérieurs, sur quels
       * actes, et lesquels ne fournissent pas de facture normalisée » — ce
       * dernier point ayant une conséquence fiscale directe.
       * ------------------------------------------------------------------ */
      function graphiquesPrestataires(collection) {
        var rows = collection.active();
        if (!rows.length) {
          return U.card('Statistiques des prestations externes',
            U.empty('Aucun prestataire référencé.', { icon: 'handshake' }));
        }
        var parSpecialite = C.groupBy(rows, 'specialite');
        var specialites = Object.keys(parSpecialite);
        var montant = function (x) { return (x.tarifActe || 0) * (x.actesRealises || 0); };

        var bloc = el('div.space-y-4');
        bloc.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Montant dû par spécialité',
            G.barres(specialites,
              [{ label: 'FCFA', data: specialites.map(function (k) { return C.sum(parSpecialite[k], montant); }), color: G.TONES.navy }],
              { horizontal: true, height: 260 })),
          U.card('Actes réalisés par spécialité',
            G.camembert(specialites,
              specialites.map(function (k) { return C.sum(parSpecialite[k], 'actesRealises'); }),
              { height: 260, legend: 'bottom' })),
          U.card('Facture normalisée',
            G.anneau(['Fournie', 'Manquante'], [
              rows.filter(function (x) { return x.factureNormalisee; }).length,
              rows.filter(function (x) { return !x.factureNormalisee; }).length,
            ], { legend: 'bottom', colors: [G.TONES.vert, G.TONES.rouge] })),
        ]));

        var top = C.sortBy(rows.slice(), montant).reverse().slice(0, 8);
        bloc.appendChild(U.card('Les huit prestataires les plus rémunérés',
          K.ranking(top.map(function (x) {
            return { label: x.nom + ' — ' + x.specialite, value: montant(x), tone: x.factureNormalisee ? 'navy' : 'danger' };
          }), { format: function (v) { return C.money(v, false); } })));

        bloc.appendChild(K.note('Un prestataire <strong>sans facture normalisée</strong> expose la clinique : '
          + 'la charge n’est pas déductible et la dépense reste hors du circuit MECeF. '
          + 'Ces lignes apparaissent en rouge au classement ci-dessus.',
        { tone: 'warning', icon: 'file-x' }));
        return bloc;
      }

      return K.crud({
        collection: 'prestataires', entite: 'prestataire', entiteP: 'prestataires', module: 'M10',
        defaultSort: 'nom', pageSize: 15,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (p) { return el('span.font-mono.text-xs', { text: p.reference }); } },
          { key: 'nom', label: 'Prestataire' },
          { key: 'specialite', label: 'Spécialité / acte', render: function (p) { return U.badge(p.specialite, 'navy'); } },
          { key: 'telephone', label: 'Téléphone', nowrap: true },
          { key: 'tarifActe', label: 'Tarif par acte', align: 'right', text: function (p) { return C.money(p.tarifActe, false); }, render: function (p) { return C.money(p.tarifActe, false); } },
          { key: 'actesRealises', label: 'Actes réalisés', align: 'right' },
          {
            key: 'montantDu', label: 'Montant dû', align: 'right',
            value: function (p) { return p.tarifActe * p.actesRealises; },
            text: function (p) { return C.money(p.tarifActe * p.actesRealises, false); },
            render: function (p) { return el('span.font-semibold', { text: C.money(p.tarifActe * p.actesRealises, false) }); },
          },
          { key: 'ifu', label: 'IFU', nowrap: true, render: function (p) { return p.ifu ? el('span.font-mono.text-xs', { text: p.ifu }) : U.badge('Non renseigné', 'warning'); } },
          {
            key: 'factureNormalisee', label: 'Facture normalisée',
            text: function (p) { return p.factureNormalisee ? 'Oui' : 'Non'; },
            render: function (p) { return p.factureNormalisee ? U.badge('Fournie', 'success') : U.badge('Manquante', 'danger'); },
          },
        ],
        fields: [
          { name: 'nom', label: 'Nom du prestataire', required: true, col: 'full' },
          { name: 'specialite', label: 'Spécialité / type d’acte', type: 'select', required: true, options: ['Circoncision', 'Hydrotubation', 'Accouchement', 'Analyses spécialisées', 'Chirurgie', 'Échographie', 'Anesthésie', 'Autre'] },
          { name: 'telephone', label: 'Téléphone', type: 'tel' },
          { name: 'tarifActe', label: 'Tarif par acte (FCFA)', type: 'money', required: true, min: 0 },
          { name: 'actesRealises', label: 'Actes réalisés (mois en cours)', type: 'number', min: 0 },
          { name: 'ifu', label: 'IFU du prestataire' },
          { name: 'factureNormalisee', label: 'Facture normalisée fournie', type: 'checkbox', col: 'full' },
        ],
        transform: function (v) { if (!v.reference) v.reference = C.nextRef('PE-', 4); return v; },
        onCreate: function () { return { actesRealises: 0, factureNormalisee: false }; },
        filters: [{ name: 'specialite', label: 'Spécialité', options: ['Circoncision', 'Hydrotubation', 'Accouchement', 'Analyses spécialisées', 'Chirurgie', 'Échographie', 'Anesthésie'] }],
        apresTableau: graphiquesPrestataires,
        kpis: function (rows) {
          return [
            { label: 'Prestataires référencés', value: C.num(rows.length), icon: 'user-check', tone: 'navy' },
            { label: 'Actes du mois', value: C.num(C.sum(rows, 'actesRealises')), icon: 'activity', tone: 'info' },
            { label: 'Montant à régler', value: C.money(C.sum(rows, function (p) { return p.tarifActe * p.actesRealises; })), icon: 'wallet', tone: 'warning' },
            { label: 'Sans facture normalisée', value: C.num(rows.filter(function (p) { return !p.factureNormalisee; }).length), icon: 'file-x', tone: 'danger' },
          ];
        },
        etat: function (p) {
          P.etat({
            titre: 'État de rémunération — prestataire externe',
            sousTitre: p.nom,
            cartouche: [['Prestataire', p.nom], ['Référence', p.reference], ['Spécialité', p.specialite],
              ['IFU', p.ifu || 'Non renseigné'], ['Tarif par acte', C.money(p.tarifActe)],
              ['Facture normalisée', p.factureNormalisee ? 'Fournie' : 'Manquante']],
            contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Valeur', key: 'v', align: 'right' }], [
              { k: 'Nombre d’actes réalisés', v: C.num(p.actesRealises) },
              { k: 'Tarif unitaire', v: C.money(p.tarifActe, false) },
              { k: 'MONTANT TOTAL DÛ', v: C.money(p.tarifActe * p.actesRealises, false) },
            ]),
            signatures: [{ role: 'Le Prestataire', nom: p.nom },
              { role: 'Le Comptable', nom: 'KASSA Augustin' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * FRAIS DE PARTICIPATION AUX ÉVÉNEMENTS — socle commun aux deux écrans
   * --------------------------------------------------------------------------
   * Un événement touchant un agent — mariage, naissance, décès — donne lieu à
   * une cotisation du personnel. Créer l'événement ENGENDRE une participation
   * par agent : c'est ce geste unique qui fait tenir le module, parce que la
   * question posée ensuite n'est plus « qui doit ? » mais seulement « comment
   * chacun règle-t-il ? ».
   *
   * Deux modes, et une conséquence à chaque fois :
   *   — imputation sur salaire → la ligne apparaît au bulletin du mois choisi ;
   *   — paiement au comptant   → un versement est enregistré, avec son reçu.
   *
   * Le bénéficiaire ne cotise pas à son propre événement : c'est l'usage, et
   * l'inverse se remarquerait immédiatement au premier décès.
   * ======================================================================== */
  function colEvenements() {
    return S.collection('evenements', { module: 'M10', entite: 'événement', prefix: 'EVT' });
  }
  function colParticipations() {
    return S.collection('participations', { module: 'M10', entite: 'participation', prefix: 'PAR' });
  }

  /** Les participations d'un événement. */
  function participationsDe(evenementId) {
    return colParticipations().active().filter(function (x) { return x.evenementId === evenementId; });
  }

  /**
   * Engendre une participation par agent actif, hors bénéficiaire.
   * Appelée à la création de l'événement — et seulement là : régénérer
   * écraserait les règlements déjà encaissés.
   */
  function engendrerParticipations(evenement) {
    /* Par défaut TOUT le personnel cotise ; une sélection restreint la liste.
       Le bénéficiaire est exclu dans les deux cas — c'est l'usage, et
       l'inverse se remarquerait au premier décès. */
    var agents = personnel().filter(function (e) { return e.id !== evenement.beneficiaireId; });
    if (evenement.portee === 'selection' && (evenement.participants || []).length) {
      var vises = {};
      evenement.participants.forEach(function (id) { vises[id] = true; });
      agents = agents.filter(function (e) { return vises[e.id]; });
    }
    agents.forEach(function (e) {
      colParticipations().insert({
        evenementId: evenement.id, evenementLibelle: evenement.libelle,
        nature: evenement.nature, dateEvenement: evenement.date,
        employeId: e.id, agent: e.nomComplet, matricule: e.matricule,
        fonction: e.fonction, service: e.service,
        montant: evenement.montantParAgent,
        mode: evenement.modeParDefaut || 'salaire',
        periodeRetenue: evenement.periodePaiement,
        statutPaiement: 'du',
      });
    });
    return agents.length;
  }

  /** Le total collecté et le total attendu, pour un événement. */
  function bilanEvenement(evenement) {
    var parts = participationsDe(evenement.id);
    var regles = parts.filter(function (x) { return x.statutPaiement === 'paye'; });
    return {
      attendus: parts.length, attendu: C.sum(parts, 'montant'),
      regles: regles.length, collecte: C.sum(regles, 'montant'),
      salaire: parts.filter(function (x) { return x.mode === 'salaire'; }).length,
      comptant: parts.filter(function (x) { return x.mode === 'comptant'; }).length,
    };
  }

  /* ==========================================================================
   * ÉVÉNEMENTS DU PERSONNEL
   * ======================================================================== */
  global.SIGH.screen('m10-evenements', {
    title: 'Événements du personnel',
    description: 'Mariages, naissances, décès et autres événements donnant lieu à une participation du personnel.',
    regle: 'Créer un événement <strong>engendre une participation par agent</strong>, au montant retenu pour cet '
      + 'événement — ' + C.money(D.PARAM_EVENEMENTS.montantStandard, false) + ' par défaut, modifiable. '
      + 'Le <strong>bénéficiaire ne cotise pas</strong> à son propre événement. '
      + 'Ces sommes <strong>transitent</strong> : elles ne sont ni une recette de la clinique ni une charge.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var evts = colEvenements().active();
        C.clear(vue);

        var tousBilans = evts.map(bilanEvenement);
        vue.appendChild(U.kpiGrid([
          { label: 'Événements enregistrés', value: C.num(evts.length), icon: 'calendar-heart', tone: 'navy' },
          {
            label: 'Participations attendues', value: C.num(C.sum(tousBilans, 'attendus')),
            icon: 'users', tone: 'info',
          },
          {
            label: 'Montant collecté', value: C.money(C.sum(tousBilans, 'collecte')),
            icon: 'hand-coins', tone: 'success',
            hint: 'sur ' + C.money(C.sum(tousBilans, 'attendu')) + ' attendus',
          },
          {
            label: 'Reste à collecter',
            value: C.money(C.sum(tousBilans, 'attendu') - C.sum(tousBilans, 'collecte')),
            icon: 'clock', tone: C.sum(tousBilans, 'attendu') > C.sum(tousBilans, 'collecte') ? 'warning' : 'success',
          },
        ]));

        var actions = [];
        if (K.droits('M10').editer) {
          actions.push(K.btn('Nouvel événement', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { creerEvenement(); },
          }));
        }

        if (!evts.length) {
          vue.appendChild(U.card('Événements du personnel',
            U.empty('Aucun événement enregistré.', {
              icon: 'calendar-heart',
              hint: 'Créer un événement engendre automatiquement une participation par agent.',
            }), actions));
          U.icons(vue);
          return;
        }

        vue.appendChild(U.dataTable({
          title: 'Événements', rows: evts.map(function (e) {
            var b = bilanEvenement(e);
            return Object.assign({}, e, {
              natureLabel: D.PARAM_EVENEMENTS.nature(e.nature),
              attendu: b.attendu, collecte: b.collecte,
              taux: b.attendu ? Math.round(b.collecte / b.attendu * 100) : 0,
              regles: b.regles, attendus: b.attendus,
            });
          }),
          exportName: 'evenements-personnel', pageSize: 15, searchable: true,
          defaultSort: 'date', defaultDir: 'desc',
          actions: actions,
          filters: [{
            name: 'nature', label: 'Nature',
            options: D.PARAM_EVENEMENTS.natures.map(function (n) { return { value: n.id, label: n.label }; }),
          }],
          columns: [
            { key: 'date', label: 'Date', nowrap: true, text: function (e) { return C.dateFR(e.date); }, render: function (e) { return C.dateFR(e.date); } },
            {
              key: 'libelle', label: 'Événement',
              render: function (e) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: e.libelle }),
                  el('p.truncate.text-xs.text-slate-400', { text: e.beneficiaire || '—' }),
                ]);
              },
            },
            {
              key: 'nature', label: 'Nature', text: function (e) { return e.natureLabel; },
              render: function (e) {
                var n = D.PARAM_EVENEMENTS.natures.filter(function (x) { return x.id === e.nature; })[0];
                return U.badge(e.natureLabel, n ? n.tone : 'neutral');
              },
            },
            { key: 'montantParAgent', label: 'Par agent', align: 'right', text: function (e) { return C.money(e.montantParAgent, false); }, render: function (e) { return C.money(e.montantParAgent, false); } },
            { key: 'periodePaiement', label: 'Période de paiement', nowrap: true, render: function (e) { return e.periodePaiement ? C.moisAnnee(new Date(e.periodePaiement + '-01')) : '—'; } },
            {
              key: 'taux', label: 'Collecte', align: 'right',
              text: function (e) { return String(e.taux); },
              render: function (e) {
                return el('div.text-right', null, [
                  el('span', {
                    class: e.taux >= 100 ? 'font-semibold text-success-700' : 'font-semibold text-warning-700',
                    text: e.taux + ' %',
                  }),
                  el('p.text-xs.text-slate-400', { text: C.money(e.collecte, false) + ' / ' + C.money(e.attendu, false) }),
                ]);
              },
            },
          ],
          rowActions: function (e) {
            var actes = [K.iconBtn('users', 'Voir les participations', function () {
              global.SIGH.app.go('m10-participations', { evenement: e.id });
            })];
            actes.push(K.iconBtn('printer', 'Imprimer la liste de collecte', function () { imprimerCollecte(e); }));
            if (K.droits('M10').editer) {
              actes.push(K.iconBtn('pencil', 'Modifier l’événement', function () { modifierEvenement(e); }));
            }
            if (K.droits('M10').annuler) {
              actes.push(K.iconBtn('archive', 'Annuler l’événement', function () { archiverEvenement(e); }, 'ghost'));
            }
            return actes;
          },
        }));

        /* --- Lecture graphique --------------------------------------------- */
        var parNature = C.groupBy(evts, function (e) { return D.PARAM_EVENEMENTS.nature(e.nature); });
        var parAnnee = C.groupBy(evts, function (e) { return String(e.date).slice(0, 7); });
        var mois = Object.keys(parAnnee).sort();

        vue.appendChild(el('div.grid.gap-4.lg\:grid-cols-2', null, [
          U.card('Événements par nature',
            G.camembert(Object.keys(parNature),
              Object.keys(parNature).map(function (k) { return parNature[k].length; }),
              { height: 260, legend: 'bottom' })),
          U.card('Montant collecté par événement',
            G.barres(evts.map(function (e) { return e.libelle; }),
              [
                { label: 'Collecté', data: evts.map(function (e) { return bilanEvenement(e).collecte; }), color: G.TONES.vert },
                { label: 'Reste dû', data: evts.map(function (e) { var b = bilanEvenement(e); return b.attendu - b.collecte; }), color: G.TONES.orange },
              ], { horizontal: true, stack: true, height: 260 })),
        ]));

        if (mois.length > 1) {
          vue.appendChild(U.card('Événements au fil des mois',
            G.ligne(mois.map(function (m) { return C.moisAnnee(new Date(m + '-01')); }),
              [{ label: 'Événements', data: mois.map(function (m) { return parAnnee[m].length; }), color: G.TONES.navy }],
              { height: 240 })));
        }

        vue.appendChild(K.source(D.PARAM_EVENEMENTS.source
          + ' — montant standard ' + C.money(D.PARAM_EVENEMENTS.montantStandard, false) + ' par agent.'));
        U.icons(vue);
      }

      function champsEvenement() {
        return [
          {
            name: 'nature', label: 'Nature de l’événement', type: 'select', required: true,
            options: D.PARAM_EVENEMENTS.natures.map(function (n) { return { value: n.id, label: n.label }; }),
          },
          { name: 'libelle', label: 'Intitulé de l’événement', type: 'text', required: true, col: 'full',
            hint: 'Par exemple « Mariage de KORA Salifou » ou « Décès du père de TEPA Séraphine »' },
          {
            name: 'beneficiaireId', label: 'Agent bénéficiaire', type: 'select', required: true,
            options: optionsEmployes(), col: 'full',
            hint: 'Celui que l’événement concerne. Il ne cotise pas à son propre événement.',
          },
          {
            name: 'portee', label: 'Qui participe ?', type: 'select', required: true,
            options: [
              { value: 'tous', label: 'Tout le personnel, hors bénéficiaire' },
              { value: 'selection', label: 'Une sélection d’agents' },
            ],
            hint: 'Par défaut tout le personnel cotise ; la sélection sert aux événements de service.',
          },
          {
            name: 'participants', label: 'Agents participants', type: 'multiselect', col: 'full',
            options: optionsEmployes(),
            hint: 'À renseigner seulement si la participation ne concerne pas tout le personnel.',
          },
          { name: 'date', label: 'Date de l’événement', type: 'date', required: true },
          {
            name: 'montantParAgent', label: 'Participation par agent (FCFA)', type: 'number', required: true, min: 0,
            hint: 'Standard : ' + C.money(D.PARAM_EVENEMENTS.montantStandard, false) + '. Modifiable pour cet événement.',
          },
          {
            name: 'periodePaiement', label: 'Période de paiement', type: 'month', required: true,
            hint: 'Mois sur lequel la retenue est portée, pour les agents qui choisissent l’imputation sur salaire.',
          },
          {
            name: 'modeParDefaut', label: 'Mode de règlement par défaut', type: 'select', required: true,
            options: D.PARAM_EVENEMENTS.modes.map(function (m) { return { value: m.id, label: m.label }; }),
            hint: 'Chaque agent pourra en changer individuellement.',
          },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ];
      }

      function creerEvenement() {
        var f = U.form(champsEvenement(), {
          montantParAgent: D.PARAM_EVENEMENTS.montantStandard,
          date: C.iso(AUJ),
          periodePaiement: C.iso(AUJ).slice(0, 7),
          modeParDefaut: 'salaire',
          portee: 'tous',
        });
        var m = U.modal({
          title: 'Nouvel événement du personnel',
          subtitle: 'Une participation sera engendrée pour chaque agent, hors bénéficiaire.',
          size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('À l’enregistrement, <strong>une participation est créée pour chacun des '
              + C.num(personnel().length - 1) + ' autres agents</strong>. Chacun pourra ensuite régler '
              + 'au comptant ou par imputation sur son salaire. Ces sommes transitent par la clinique : '
              + 'elles ne sont ni une recette ni une charge.', { tone: 'info', icon: 'users' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Créer et engendrer les participations', {
              variant: 'primary', icon: 'plus',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                v.montantParAgent = Number(v.montantParAgent) || D.PARAM_EVENEMENTS.montantStandard;
                var ben = personnel().filter(function (e) { return e.id === v.beneficiaireId; })[0];
                v.beneficiaire = ben ? ben.nomComplet : null;
                v.reference = C.nextRef('EVT-', 4);
                var res = colEvenements().insert(v);
                var n = engendrerParticipations(res.record);
                S.log('Création d’un événement du personnel', 'M10', 'Événement', res.record.id, null,
                  { libelle: v.libelle, participations: n });
                m.close(); afficher();
                U.toast('Événement créé.', {
                  type: 'success',
                  detail: C.num(n) + ' participation(s) engendrée(s) — ' + C.money(v.montantParAgent * n) + ' attendus.',
                  undo: function () {
                    participationsDe(res.record.id).forEach(function (x) { colParticipations().archive(x.id); });
                    res.undo(); afficher();
                  },
                  undoMessage: 'Événement annulé — les participations sont archivées.',
                });
              },
            }),
          ],
        });
      }

      function modifierEvenement(evt) {
        var b = bilanEvenement(evt);
        var f = U.form(champsEvenement(), evt);
        var m = U.modal({
          title: 'Modifier « ' + evt.libelle + ' »', subtitle: evt.reference, size: 'lg',
          body: el('div.space-y-3', null, [
            b.regles ? K.note('<strong>' + C.num(b.regles) + ' participation(s) sont déjà réglées</strong> pour cet '
              + 'événement. Changer le montant ne modifiera <strong>que les participations encore dues</strong> : '
              + 'ce qui a été encaissé l’a été au montant annoncé, et le réécrire fausserait les reçus déjà remis.',
            { tone: 'warning', icon: 'alert-triangle' }) : null,
            f,
          ].filter(Boolean)),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                v.montantParAgent = Number(v.montantParAgent) || evt.montantParAgent;
                var ben = personnel().filter(function (e) { return e.id === v.beneficiaireId; })[0];
                v.beneficiaire = ben ? ben.nomComplet : null;
                colEvenements().update(evt.id, v);
                /* Seules les participations non réglées suivent le nouveau montant. */
                var touchees = 0;
                participationsDe(evt.id).forEach(function (x) {
                  if (x.statutPaiement === 'paye') return;
                  colParticipations().update(x.id, {
                    montant: v.montantParAgent, periodeRetenue: v.periodePaiement,
                    evenementLibelle: v.libelle, nature: v.nature,
                  });
                  touchees++;
                });
                m.close(); afficher();
                U.toast('Événement modifié.', {
                  type: 'success',
                  detail: C.num(touchees) + ' participation(s) non réglée(s) mise(s) à jour ; '
                    + C.num(b.regles) + ' déjà encaissée(s) laissée(s) intacte(s).',
                });
              },
            }),
          ],
        });
      }

      function archiverEvenement(evt) {
        var b = bilanEvenement(evt);
        /* Le message se règle sur ce qu'il y a réellement à perdre. Trois
           situations, trois avertissements — et aucune alarme pour rien. */
        var message;
        if (!b.attendus) {
          message = 'Aucune participation n’a encore été engendrée pour cet événement : '
            + 'l’annulation n’a donc aucune conséquence financière.<br><br>'
            + 'Conformément à <strong>RG-14</strong>, l’événement est archivé et non supprimé — '
            + 'il reste consultable et restaurable.';
        } else if (!b.regles) {
          message = C.num(b.attendus) + ' participation(s) ont été engendrées, <strong>aucune n’a encore '
            + 'été réglée</strong>. L’annulation les archive toutes : rien n’a été encaissé, rien n’est '
            + 'à restituer.<br><br>'
            + 'Conformément à <strong>RG-14</strong>, rien n’est supprimé : tout reste consultable et restaurable.';
        } else {
          message = '<strong>Attention.</strong> ' + C.num(b.regles) + ' participation(s) sur '
            + C.num(b.attendus) + ' ont <strong>déjà été réglées</strong>, pour ' + C.money(b.collecte) + '. '
            + 'L’annulation archive l’événement et ses participations non réglées ; '
            + '<strong>les sommes déjà encaissées restent tracées et devront être restituées hors '
            + 'application</strong>.<br><br>'
            + 'Conformément à <strong>RG-14</strong>, rien n’est supprimé : tout reste consultable et restaurable.';
        }
        U.confirm({
          title: 'Annuler l’événement « ' + evt.libelle + ' » ?',
          message: message,
          confirmLabel: 'Annuler l’événement',
          danger: b.regles > 0, requireMotif: true,
        }).then(function (rep) {
          if (!rep) return;
          var archivees = 0;
          participationsDe(evt.id).forEach(function (x) {
            if (x.statutPaiement === 'paye') return;
            colParticipations().archive(x.id, rep.motif); archivees++;
          });
          var res = colEvenements().archive(evt.id, rep.motif);
          afficher();
          U.toast('Événement annulé.', {
            type: 'success',
            detail: C.num(archivees) + ' participation(s) non réglée(s) archivée(s).',
            undo: function () { res.undo(); afficher(); },
          });
        });
      }

      function imprimerCollecte(evt) {
        var parts = C.sortBy(participationsDe(evt.id), 'agent');
        var b = bilanEvenement(evt);
        P.etat({
          titre: 'Liste de collecte — participation du personnel',
          sousTitre: evt.libelle,
          cartouche: [['Événement', evt.libelle], ['Nature', D.PARAM_EVENEMENTS.nature(evt.nature)],
            ['Date', C.dateFR(evt.date)], ['Bénéficiaire', evt.beneficiaire || '—'],
            ['Participation par agent', C.money(evt.montantParAgent)],
            ['Total attendu', C.money(b.attendu)], ['Déjà collecté', C.money(b.collecte)]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Matricule', key: 'matricule' },
              { label: 'Agent', key: 'agent' },
              { label: 'Montant', align: 'right', value: function (x) { return C.money(x.montant, false); }, somme: function (x) { return x.montant; } },
              { label: 'Mode', value: function (x) { return x.mode === 'salaire' ? 'Sur salaire' : 'Comptant'; } },
              {
                label: 'Réglé',
                value: function (x) { return x.statutPaiement === 'paye' ? 'Oui — ' + (x.datePaiement ? C.dateFR(x.datePaiement) : '') : 'Non'; },
                /* Le pied de cette colonne porte ce qui est DÉJÀ COLLECTÉ,
                   refait depuis les lignes imprimées : la liste de collecte
                   sert à retrouver qui reste à voir. */
                somme: function (x) { return x.statutPaiement === 'paye' ? x.montant : 0; },
              },
              { label: 'Émargement', value: function () { return ''; } },
            ], parts, { total: true, totalLabel: 'TOTAL' }),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Les participations aux événements du personnel transitent par la clinique pour le compte du '
                + 'collectif. Elles ne constituent ni une recette de l’établissement ni une charge, et ne '
                + 'figurent à ce titre ni au chiffre d’affaires ni en comptabilité.',
            }),
          ]),
          signatures: [{ role: 'Le Caissier' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * FRAIS DE PARTICIPATION — le registre agent par agent
   * ======================================================================== */
  global.SIGH.screen('m10-participations', {
    title: 'Frais de participation',
    description: 'Participations dues par chaque agent : mode de règlement, encaissement au comptant et retenue sur salaire.',
    regle: 'Deux modes de règlement, au choix de l’agent : <strong>imputation sur salaire</strong> — la retenue '
      + 'figure au bulletin du mois de paiement — ou <strong>paiement au comptant</strong>, avec reçu. '
      + 'Une participation déjà réglée ne se modifie plus : elle s’annule, et l’annulation est tracée (RG-12).',
    render: function (root) {
      var vue = el('div.space-y-4');
      var selEvenement = el('select.select');
      var selMode = el('select.select');
      var selStatut = el('select.select');

      remplir();
      /* Lien profond depuis l'écran des événements. */
      var cible = (global.location.hash.match(/evenement=([^&]+)/) || [])[1];
      if (cible && [].some.call(selEvenement.options, function (o) { return o.value === cible; })) {
        selEvenement.value = cible;
      }

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div.min-w-\[16rem\]', null, [el('label.label', { text: 'Événement' }), selEvenement]),
        el('div', null, [el('label.label', { text: 'Mode de règlement' }), selMode]),
        el('div', null, [el('label.label', { text: 'État' }), selStatut]),
        K.btn('Imprimer l’état', { icon: 'printer', onclick: imprimer }),
      ]));
      [selEvenement, selMode, selStatut].forEach(function (x) { x.addEventListener('change', afficher); });

      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function remplir() {
        selEvenement.appendChild(el('option', { value: '' }, 'Tous les événements'));
        colEvenements().active().forEach(function (e) {
          selEvenement.appendChild(el('option', { value: e.id }, e.libelle + ' — ' + C.dateFR(e.date)));
        });
        selMode.appendChild(el('option', { value: '' }, 'Tous les modes'));
        D.PARAM_EVENEMENTS.modes.forEach(function (m) {
          selMode.appendChild(el('option', { value: m.id }, m.label));
        });
        selStatut.appendChild(el('option', { value: '' }, 'Tous les états'));
        selStatut.appendChild(el('option', { value: 'du' }, 'Non réglée'));
        selStatut.appendChild(el('option', { value: 'paye' }, 'Réglée'));
      }

      function lignes() {
        return colParticipations().active().filter(function (x) {
          if (selEvenement.value && x.evenementId !== selEvenement.value) return false;
          if (selMode.value && x.mode !== selMode.value) return false;
          if (selStatut.value && x.statutPaiement !== selStatut.value) return false;
          return true;
        });
      }

      function afficher() {
        var rows = lignes();
        C.clear(vue);

        var payees = rows.filter(function (x) { return x.statutPaiement === 'paye'; });
        var surSalaire = rows.filter(function (x) { return x.mode === 'salaire' && x.statutPaiement !== 'paye'; });

        vue.appendChild(U.kpiGrid([
          { label: 'Participations', value: C.num(rows.length), icon: 'hand-coins', tone: 'navy',
            hint: C.money(C.sum(rows, 'montant')) + ' attendus' },
          { label: 'Réglées', value: C.num(payees.length), icon: 'check-circle-2', tone: 'success',
            hint: C.money(C.sum(payees, 'montant')) + ' encaissés' },
          {
            label: 'À retenir sur salaire', value: C.num(surSalaire.length), icon: 'wallet', tone: 'warning',
            hint: C.money(C.sum(surSalaire, 'montant')) + ' portés aux bulletins',
          },
          {
            label: 'Reste dû',
            value: C.money(C.sum(rows, 'montant') - C.sum(payees, 'montant')),
            icon: 'clock', tone: rows.length === payees.length ? 'success' : 'danger',
          },
        ]));

        if (!rows.length) {
          vue.appendChild(U.card('Participations',
            U.empty('Aucune participation pour ces critères.', {
              icon: 'hand-coins',
              hint: 'Les participations naissent de la création d’un événement, à l’écran « Événements du personnel ».',
            })));
          U.icons(vue);
          return;
        }

        vue.appendChild(U.dataTable({
          title: 'Registre des participations', rows: rows, exportName: 'participations',
          pageSize: 20, searchable: true, defaultSort: 'agent',
          columns: [
            {
              key: 'agent', label: 'Agent',
              render: function (x) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: x.agent }),
                  el('p.truncate.text-xs.text-slate-400', { text: (x.matricule || '—') + ' · ' + fonctionLabel(x.fonction) }),
                ]);
              },
            },
            { key: 'evenementLibelle', label: 'Événement' },
            { key: 'montant', label: 'Montant', align: 'right', text: function (x) { return C.money(x.montant, false); }, render: function (x) { return C.money(x.montant, false); } },
            {
              key: 'mode', label: 'Mode de règlement',
              text: function (x) { return x.mode === 'salaire' ? 'Sur salaire' : 'Comptant'; },
              render: function (x) {
                return x.mode === 'salaire'
                  ? U.badge('Sur salaire — ' + (x.periodeRetenue ? C.moisAnnee(new Date(x.periodeRetenue + '-01')) : '?'), 'navy')
                  : U.badge('Au comptant', 'info');
              },
            },
            {
              key: 'statutPaiement', label: 'État', align: 'right',
              text: function (x) { return x.statutPaiement === 'paye' ? 'réglée' : 'due'; },
              render: function (x) {
                if (x.statutPaiement !== 'paye') return U.badge('Due', 'warning');
                return el('div.text-right', null, [
                  U.badge('Réglée', 'success'),
                  el('p.mt-0\.5.text-xs.text-slate-400', {
                    text: (x.datePaiement ? C.dateFR(x.datePaiement) : '') + (x.recu ? ' · ' + x.recu : ''),
                  }),
                ]);
              },
            },
          ],
          rowActions: function (x) {
            var actes = [];
            if (x.statutPaiement === 'paye') {
              actes.push(K.iconBtn('printer', 'Imprimer le reçu', function () { imprimerRecu(x); }));
              if (K.droits('M10').annuler) {
                actes.push(K.iconBtn('rotate-ccw', 'Annuler le règlement', function () { annulerReglement(x); }, 'ghost'));
              }
              return actes;
            }
            if (K.droits('M10').editer) {
              actes.push(K.iconBtn('repeat', 'Changer de mode de règlement', function () { changerMode(x); }));
              if (x.mode === 'comptant') {
                actes.push(K.iconBtn('banknote', 'Encaisser au comptant', function () { encaisser(x); }));
              } else {
                actes.push(K.iconBtn('check', 'Confirmer la retenue sur salaire', function () { confirmerRetenue(x); }));
              }
            }
            return actes;
          },
        }));

        /* --- Lecture graphique --------------------------------------------- */
        var parMode = C.groupBy(rows, 'mode');
        var parService = C.groupBy(rows, function (x) { return x.service || 'Non renseigné'; });

        vue.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Modes de règlement',
            G.anneau(Object.keys(parMode).map(function (k) { return k === 'salaire' ? 'Sur salaire' : 'Au comptant'; }),
              Object.keys(parMode).map(function (k) { return parMode[k].length; }),
              { legend: 'bottom', colors: [G.TONES.navy, G.TONES.ciel] })),
          U.card('État du recouvrement',
            G.anneau(['Réglées', 'Dues'],
              [payees.length, rows.length - payees.length],
              { legend: 'bottom', colors: [G.TONES.vert, G.TONES.orange] })),
          U.card('Participations par service',
            G.barres(Object.keys(parService),
              [{ label: 'Agents', data: Object.keys(parService).map(function (k) { return parService[k].length; }), color: G.TONES.navy }],
              { horizontal: true, height: 260 })),
        ]));
        U.icons(vue);
      }

      function changerMode(x) {
        var f = U.form([
          {
            name: 'mode', label: 'Mode de règlement', type: 'select', required: true,
            options: D.PARAM_EVENEMENTS.modes.map(function (m) { return { value: m.id, label: m.label }; }),
          },
          {
            name: 'periodeRetenue', label: 'Mois de retenue', type: 'month',
            hint: 'Utile seulement pour l’imputation sur salaire.',
          },
        ], { mode: x.mode, periodeRetenue: x.periodeRetenue });

        var m = U.modal({
          title: 'Mode de règlement', subtitle: x.agent + ' — ' + x.evenementLibelle, size: 'md',
          body: el('div.space-y-3', null, [
            K.note('L’<strong>imputation sur salaire</strong> porte ' + C.money(x.montant, false) + ' en retenue '
              + 'au bulletin du mois choisi. Le <strong>paiement au comptant</strong> attend un versement à la '
              + 'caisse et donne lieu à un reçu.', { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                colParticipations().update(x.id, {
                  mode: v.mode,
                  periodeRetenue: v.mode === 'salaire' ? (v.periodeRetenue || x.periodeRetenue) : null,
                });
                m.close(); afficher();
                U.toast('Mode de règlement modifié.', {
                  type: 'success',
                  detail: v.mode === 'salaire'
                    ? 'Retenue portée au bulletin de ' + (v.periodeRetenue ? C.moisAnnee(new Date(v.periodeRetenue + '-01')) : 'la période choisie') + '.'
                    : 'Versement attendu à la caisse.',
                });
              },
            }),
          ],
        });
      }

      function encaisser(x) {
        var f = U.form([
          { name: 'montantVerse', label: 'Montant versé (FCFA)', type: 'number', required: true, min: 0 },
          { name: 'datePaiement', label: 'Date du versement', type: 'date', required: true },
          { name: 'observation', label: 'Observation', col: 'full' },
        ], { montantVerse: x.montant, datePaiement: C.iso(AUJ) });

        var m = U.modal({
          title: 'Encaisser la participation', subtitle: x.agent + ' — ' + x.evenementLibelle, size: 'md',
          body: el('div.space-y-3', null, [
            U.descList([['Agent', x.agent], ['Matricule', x.matricule || '—'],
              ['Événement', x.evenementLibelle], ['Montant dû', C.money(x.montant)]], 'grid-cols-2'),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Valider l’encaissement', {
              variant: 'primary', icon: 'banknote',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var recu = C.nextRef('REC-PART-', 4);
                var res = colParticipations().update(x.id, {
                  statutPaiement: 'paye', mode: 'comptant',
                  montantVerse: Number(v.montantVerse), datePaiement: v.datePaiement,
                  recu: recu, encaissePar: S.currentUser(), observation: v.observation,
                });
                S.log('Encaissement d’une participation', 'M10', 'Participation', x.id,
                  { statut: 'du' }, { statut: 'paye', recu: recu });
                m.close(); afficher();
                U.toast('Participation encaissée.', {
                  type: 'success', detail: 'Reçu ' + recu + ' — ' + C.money(Number(v.montantVerse)),
                  undo: function () { res.undo(); afficher(); },
                });
              },
            }),
          ],
        });
      }

      function confirmerRetenue(x) {
        U.confirm({
          title: 'Confirmer la retenue sur salaire ?',
          message: 'La participation de <strong>' + C.money(x.montant) + '</strong> due par ' + x.agent
            + ' est portée en retenue sur le bulletin de <strong>'
            + (x.periodeRetenue ? C.moisAnnee(new Date(x.periodeRetenue + '-01')) : 'la période retenue')
            + '</strong>.<br><br>Confirmer signifie que la retenue a bien été opérée sur la paie du mois. '
            + 'L’opération reste annulable et journalisée (RG-12).',
          confirmLabel: 'Confirmer la retenue',
        }).then(function (ok) {
          if (!ok) return;
          var res = colParticipations().update(x.id, {
            statutPaiement: 'paye', datePaiement: C.iso(AUJ),
            recu: 'Retenue sur salaire — ' + (x.periodeRetenue || ''),
            encaissePar: S.currentUser(),
          });
          afficher();
          U.toast('Retenue confirmée.', {
            type: 'success', detail: x.agent + ' — ' + C.money(x.montant),
            undo: function () { res.undo(); afficher(); },
          });
        });
      }

      function annulerReglement(x) {
        U.confirm({
          title: 'Annuler le règlement ?',
          message: 'Le règlement de <strong>' + C.money(x.montant) + '</strong> par ' + x.agent
            + (x.recu ? ' (reçu ' + x.recu + ')' : '') + ' est annulé et la participation redevient due.<br><br>'
            + 'Si des espèces ont été encaissées, leur restitution se fait hors application. '
            + 'L’annulation est journalisée (RG-12).',
          confirmLabel: 'Annuler le règlement', danger: true, requireMotif: true,
        }).then(function (rep) {
          if (!rep) return;
          colParticipations().update(x.id, {
            statutPaiement: 'du', datePaiement: null, recu: null,
            montantVerse: null, motifAnnulation: rep.motif, annulePar: S.currentUser(),
          });
          S.log('Annulation d’un règlement de participation', 'M10', 'Participation', x.id,
            { statut: 'paye' }, { statut: 'du', motif: rep.motif });
          afficher();
          U.toast('Règlement annulé.', { type: 'warning', detail: 'La participation redevient due.' });
        });
      }

      function imprimerRecu(x) {
        P.etat({
          titre: 'Reçu de participation',
          sousTitre: x.evenementLibelle,
          cartouche: [['Reçu n°', x.recu || '—'], ['Agent', x.agent], ['Matricule', x.matricule || '—'],
            ['Événement', x.evenementLibelle],
            ['Date du versement', x.datePaiement ? C.dateFR(x.datePaiement) : '—'],
            ['Encaissé par', x.encaissePar || '—']],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
              { k: 'Participation due', v: C.money(x.montant, false) },
              { k: 'MONTANT VERSÉ', v: C.money(x.montantVerse || x.montant, false) },
            ]),
            el('p.mt-2.text-\[11px\]', {
              text: 'Arrêté le présent reçu à la somme de ' + C.montantEnLettres(x.montantVerse || x.montant) + '.',
            }),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Participation du personnel à un événement. Cette somme transite par la clinique pour le '
                + 'compte du collectif : elle ne constitue ni une recette de l’établissement ni une charge.',
            }),
          ]),
          signatures: [{ role: 'L’Agent', nom: x.agent, mention: 'Versé' },
            { role: 'Le Caissier', nom: x.encaissePar || '' }],
        });
      }

      function imprimer() {
        var rows = C.sortBy(lignes(), 'agent');
        var payees = rows.filter(function (x) { return x.statutPaiement === 'paye'; });
        P.etat({
          titre: 'État des participations du personnel',
          sousTitre: selEvenement.value
            ? selEvenement.options[selEvenement.selectedIndex].text : 'Tous les événements',
          cartouche: [['Participations', C.num(rows.length)],
            ['Réglées', C.num(payees.length)],
            ['Montant attendu', C.money(C.sum(rows, 'montant'))],
            ['Montant encaissé', C.money(C.sum(payees, 'montant'))],
            ['Établi par', S.currentUser()], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'Matricule', key: 'matricule' },
            { label: 'Agent', key: 'agent' },
            { label: 'Événement', key: 'evenementLibelle' },
            { label: 'Montant', align: 'right', value: function (x) { return C.money(x.montant, false); }, somme: function (x) { return x.montant; } },
            { label: 'Mode', value: function (x) { return x.mode === 'salaire' ? 'Sur salaire' : 'Comptant'; } },
            {
              label: 'État', value: function (x) { return x.statutPaiement === 'paye' ? 'Réglée' : 'Due'; },
              /* Le pied porte le montant ENCAISSÉ, refait depuis les lignes. */
              somme: function (x) { return x.statutPaiement === 'paye' ? x.montant : 0; },
            },
            { label: 'Reçu', value: function (x) { return x.recu || ''; } },
          ], rows, { total: true, totalLabel: 'TOTAL' }),
          signatures: [{ role: 'Le Caissier' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * ASSURANCE DU PERSONNEL
   * --------------------------------------------------------------------------
   * La clinique soigne ses agents à 100 %. Ce n'est pas une assurance au sens
   * du module M9 : aucun tiers ne rembourse, aucune créance n'est ouverte, et
   * la prestation ne remonte NI aux recettes NI à la comptabilité. C'est un
   * avantage consenti par l'employeur — mais un avantage dont la Direction
   * doit connaître le volume, sans quoi il ne se pilote pas.
   *
   * D'où le parti pris : AUCUN CRUD. Rien ne se saisit ici. Le tableau se
   * remplit tout seul dès qu'un agent est reçu en consultation ou qu'un acte
   * lui est prescrit, parce que son dossier patient porte `personnelId`.
   * Ouvrir une saisie ici créerait une seconde vérité, divergente du dossier.
   * ======================================================================== */
  global.SIGH.screen('m10-assurance-personnel', {
    title: 'Assurance du personnel',
    description: 'Prestations dispensées aux agents de la clinique, prises en charge à 100 % — hors recettes et hors comptabilité.',
    regle: 'Prise en charge à <strong>100 %</strong>, sans tiers payeur. Ces prestations ne constituent '
      + '<strong>ni une recette ni une créance</strong> : elles ne figurent ni au relevé assureur, ni au chiffre '
      + 'd’affaires, ni en comptabilité. La valeur affichée mesure l’avantage consenti, elle ne s’encaisse pas. '
      + '<strong>Écran sans saisie</strong> — il se remplit depuis le dossier patient de l’agent.',
    render: function (root) {
      var vue = el('div.space-y-4');
      var selPeriode = el('select.select');
      [['', 'Depuis toujours'], ['30', '30 derniers jours'], ['90', 'Trois derniers mois'],
        ['180', 'Six derniers mois'], ['365', 'Douze derniers mois']].forEach(function (x) {
        selPeriode.appendChild(el('option', { value: x[0] }, x[1]));
      });
      selPeriode.value = '365';
      var selFonction = el('select.select');
      selFonction.appendChild(el('option', { value: '' }, 'Toutes les fonctions'));
      D.FONCTIONS.forEach(function (f) { selFonction.appendChild(el('option', { value: f.id }, f.label)); });

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Période' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Fonction' }), selFonction]),
        K.btn('Imprimer l’état', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));
      [selPeriode, selFonction].forEach(function (x) { x.addEventListener('change', afficher); });

      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      /** Les dossiers patients rattachés à un agent. */
      function agents() {
        return S.collection('patients').active().filter(function (p) { return !!p.personnelId; });
      }

      function borneMin() {
        var j = Number(selPeriode.value);
        return j ? C.iso(C.addDays(AUJ, -j)) : null;
      }

      /**
       * Les prestations d'un agent : consultations reçues et analyses
       * prescrites. Elles sont lues dans les collections d'origine — jamais
       * recopiées : une copie divergerait du dossier au premier changement.
       */
      function prestations() {
        var min = borneMin();
        var parPatient = {};
        agents().forEach(function (p) { parPatient[p.id] = p; });

        var out = [];
        S.collection('consultations').active().forEach(function (c) {
          var pat = parPatient[c.patientId];
          if (!pat) return;
          var d = String(c.date).slice(0, 10);
          if (min && d < min) return;
          out.push({
            id: c.id, date: d, agent: pat.nom + ' ' + pat.prenom,
            patientId: pat.id, code: pat.code, matricule: pat.matricule,
            fonction: pat.fonctionAgent, fonctionLabel: fonctionLabel(pat.fonctionAgent),
            nature: 'Consultation', detail: c.type + ' — ' + (c.motif || ''),
            praticien: c.medecin, valeur: Number(c.tarif) || 0,
          });
        });

        S.collection('demandesAnalyses').active().forEach(function (a) {
          var pat = parPatient[a.patientId];
          if (!pat) return;
          var d = String(a.date || a.dateDemande || '').slice(0, 10);
          if (!d || (min && d < min)) return;
          var analyse = D.ANALYSES.filter(function (x) { return x.code === a.analyse || x.libelle === a.analyse; })[0];
          out.push({
            id: a.id, date: d, agent: pat.nom + ' ' + pat.prenom,
            patientId: pat.id, code: pat.code, matricule: pat.matricule,
            fonction: pat.fonctionAgent, fonctionLabel: fonctionLabel(pat.fonctionAgent),
            nature: 'Analyse', detail: a.analyse || (analyse ? analyse.libelle : 'Analyse'),
            praticien: a.prescripteur || a.demandeur || '—',
            valeur: Number(a.montant) || (analyse ? Number(analyse.prix) || 0 : 0),
          });
        });

        S.collection('admissions').active().forEach(function (h) {
          var pat = parPatient[h.patientId];
          if (!pat) return;
          var d = String(h.dateEntree || '').slice(0, 10);
          if (!d || (min && d < min)) return;
          out.push({
            id: h.id, date: d, agent: pat.nom + ' ' + pat.prenom,
            patientId: pat.id, code: pat.code, matricule: pat.matricule,
            fonction: pat.fonctionAgent, fonctionLabel: fonctionLabel(pat.fonctionAgent),
            nature: 'Hospitalisation', detail: (h.service || '') + ' — lit ' + (h.lit || '—'),
            praticien: h.medecin || '—', valeur: Number(h.montant) || 0,
          });
        });

        if (selFonction.value) {
          out = out.filter(function (x) { return x.fonction === selFonction.value; });
        }
        return C.sortBy(out, 'date').reverse();
      }

      function afficher() {
        var rows = prestations();
        var couverts = agents();
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Agents ayant un dossier patient', value: C.num(couverts.length), icon: 'shield-check', tone: 'navy',
            hint: 'sur ' + C.num(personnel().length) + ' agents' },
          { label: 'Prestations prises en charge', value: C.num(rows.length), icon: 'stethoscope', tone: 'info' },
          {
            label: 'Valeur de l’avantage', value: C.money(C.sum(rows, 'valeur')), icon: 'gift', tone: 'success',
            hint: 'Ni recette, ni créance',
          },
          {
            label: 'Agents effectivement soignés',
            value: C.num(Object.keys(C.groupBy(rows, 'patientId')).length), icon: 'users', tone: 'neutral',
          },
        ]));

        vue.appendChild(K.note('<strong>Ce tableau ne se saisit pas.</strong> Il se remplit dès qu’un agent est '
          + 'reçu en consultation, qu’une analyse lui est prescrite ou qu’il est hospitalisé — parce que son '
          + 'dossier patient porte son matricule. Pour corriger une ligne, il faut corriger la prestation '
          + 'd’origine dans son module : une saisie ici créerait une seconde vérité, divergente du dossier.',
        { tone: 'warning', icon: 'lock' }));

        if (!rows.length) {
          vue.appendChild(U.card('Prestations au personnel',
            U.empty('Aucune prestation sur la période retenue.', {
              icon: 'shield-check',
              hint: 'Élargir la période, ou vérifier que l’agent dispose bien d’un dossier patient à son nom.',
            })));
          U.icons(vue);
          return;
        }

        vue.appendChild(U.dataTable({
          title: 'Prestations prises en charge — ' + (selPeriode.value ? selPeriode.options[selPeriode.selectedIndex].text : 'toutes périodes'),
          rows: rows, exportName: 'assurance-personnel', pageSize: 20, searchable: true,
          defaultSort: 'date', defaultDir: 'desc',
          filters: [
            {
              name: 'nature', label: 'Nature',
              options: [{ value: 'Consultation', label: 'Consultation' }, { value: 'Analyse', label: 'Analyse' },
                { value: 'Hospitalisation', label: 'Hospitalisation' }],
            },
          ],
          columns: [
            { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
            {
              key: 'agent', label: 'Agent',
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.agent }),
                  el('p.truncate.text-xs.text-slate-400', { text: (r.matricule || '—') + ' · ' + r.fonctionLabel }),
                ]);
              },
            },
            { key: 'code', label: 'Dossier', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.code }); } },
            { key: 'nature', label: 'Nature', render: function (r) { return U.badge(r.nature, r.nature === 'Consultation' ? 'info' : (r.nature === 'Analyse' ? 'navy' : 'warning')); } },
            { key: 'detail', label: 'Détail' },
            { key: 'praticien', label: 'Praticien' },
            {
              key: 'valeur', label: 'Valeur', align: 'right',
              text: function (r) { return C.money(r.valeur, false); },
              render: function (r) {
                return el('div.text-right', null, [
                  el('span.text-sm.text-slate-500', { text: C.money(r.valeur, false) }),
                  el('p.text-xs.font-semibold.text-success-700', { text: 'pris en charge 100 %' }),
                ]);
              },
            },
          ],
          rowActions: function (r) {
            return [K.iconBtn('folder-open', 'Ouvrir le dossier du patient', function () {
              global.SIGH.app.go('m1-dossier', { patient: r.patientId });
            })];
          },
        }));

        /* --- Lecture graphique ------------------------------------------- */
        var parNature = C.groupBy(rows, 'nature');
        var parFonction = C.groupBy(rows, 'fonctionLabel');
        var parAgent = C.groupBy(rows, 'agent');
        var noms = Object.keys(parAgent)
          .sort(function (a, b) { return C.sum(parAgent[b], 'valeur') - C.sum(parAgent[a], 'valeur'); })
          .slice(0, 10);

        vue.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Valeur par nature de prestation',
            G.camembert(Object.keys(parNature),
              Object.keys(parNature).map(function (k) { return C.sum(parNature[k], 'valeur'); }),
              { height: 260, legend: 'bottom' })),
          U.card('Prestations par fonction',
            G.barres(Object.keys(parFonction),
              [{ label: 'Prestations', data: Object.keys(parFonction).map(function (k) { return parFonction[k].length; }), color: G.TONES.navy }],
              { horizontal: true, height: 260 })),
          U.card('Les dix agents les plus pris en charge',
            K.ranking(noms.map(function (k) {
              return { label: k, value: C.sum(parAgent[k], 'valeur'), tone: 'success' };
            }), { format: function (v) { return C.money(v, false); } })),
        ]));

        var parMois = C.groupBy(rows, function (r) { return String(r.date).slice(0, 7); });
        var mois = Object.keys(parMois).sort();
        if (mois.length > 1) {
          vue.appendChild(U.card('Valeur mensuelle de l’avantage',
            G.ligne(mois.map(function (m) { return C.moisAnnee(new Date(m + '-01')); }),
              [{ label: 'FCFA', data: mois.map(function (m) { return C.sum(parMois[m], 'valeur'); }), color: G.TONES.vert }],
              { height: 240 })));
        }

        vue.appendChild(K.source('Prise en charge du personnel à 100 % — décision de la Direction. '
          + 'Ces montants sont volontairement absents du chiffre d’affaires, des relevés assureur et des '
          + 'écritures comptables : les y porter gonflerait des recettes qui n’ont jamais été encaissées.'));
        U.icons(vue);
      }

      function imprimer() {
        var rows = prestations();
        var parAgent = C.groupBy(rows, 'agent');
        var lignes = Object.keys(parAgent).map(function (k) {
          var v = parAgent[k];
          return {
            agent: k, matricule: v[0].matricule || '—', fonction: v[0].fonctionLabel,
            consultations: v.filter(function (x) { return x.nature === 'Consultation'; }).length,
            analyses: v.filter(function (x) { return x.nature === 'Analyse'; }).length,
            hospitalisations: v.filter(function (x) { return x.nature === 'Hospitalisation'; }).length,
            valeur: C.sum(v, 'valeur'),
          };
        }).sort(function (a, b) { return b.valeur - a.valeur; });

        P.etat({
          titre: 'État de la prise en charge du personnel',
          sousTitre: selPeriode.value ? selPeriode.options[selPeriode.selectedIndex].text : 'Depuis l’origine',
          cartouche: [['Période', selPeriode.options[selPeriode.selectedIndex].text],
            ['Agents concernés', C.num(lignes.length)],
            ['Prestations', C.num(rows.length)],
            ['Valeur totale', C.money(C.sum(rows, 'valeur'))],
            ['Établi par', S.currentUser()], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Matricule', key: 'matricule' },
              { label: 'Agent', key: 'agent' },
              { label: 'Fonction', key: 'fonction' },
              { label: 'Consult.', align: 'right', value: function (r) { return C.num(r.consultations); }, somme: function (r) { return r.consultations; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Analyses', align: 'right', value: function (r) { return C.num(r.analyses); }, somme: function (r) { return r.analyses; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Hospit.', align: 'right', value: function (r) { return C.num(r.hospitalisations); }, somme: function (r) { return r.hospitalisations; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Valeur prise en charge', align: 'right', value: function (r) { return C.money(r.valeur, false); }, somme: function (r) { return r.valeur; } },
            ], lignes, { total: true, totalLabel: 'TOTAL' }),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Les prestations dispensées au personnel de la clinique sont prises en charge à 100 % par '
                + 'l’établissement. Elles ne constituent ni une recette, ni une créance sur un tiers payeur, et '
                + 'ne donnent lieu à aucune écriture comptable. La valeur portée au présent état mesure '
                + 'l’avantage consenti au personnel ; elle ne correspond à aucun encaissement.',
            }),
          ]),
          signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
            { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
        });
      }
    },
  });

  /* ==========================================================================
   * SÉCURITÉ & ENTRETIEN
   * ======================================================================== */
  global.SIGH.screen('m10-securite-entretien', {
    title: 'Sécurité & entretien',
    description: 'Planning rotatif des agents de sécurité et d’entretien : permanence et entretien général de la journée.',
    regle: 'La rotation se règle <strong>ici même</strong> : une case du planning s’ouvre au clic. '
      + 'Les vacations restent celles du <strong>planning validé</strong> — même collection que « Planning & gardes », '
      + 'donc toute modification y est immédiatement visible. Le repos de 24 h qui suit une garde reste opposable.',
    render: function (root) {
      var agents = personnel().filter(function (e) { return e.fonction === 'securite' || e.fonction === 'entretien'; });
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Agents de sécurité', value: C.num(agents.filter(function (e) { return e.fonction === 'securite'; }).length), icon: 'shield', tone: 'navy' },
        { label: 'Agents d’entretien', value: C.num(agents.filter(function (e) { return e.fonction === 'entretien'; }).length), icon: 'spray-can', tone: 'info' },
        { label: 'En poste aujourd’hui', value: C.num(planning().filter(function (p) { return p.date === C.iso(AUJ) && (p.fonction === 'securite' || p.fonction === 'entretien') && p.type !== 'repos24' && p.type !== 'repos48'; }).length), icon: 'user-check', tone: 'success' },
        { label: 'Masse salariale', value: C.money(C.sum(agents, 'salaireBase')), icon: 'banknote', tone: 'neutral' },
      ]));

      /* Légendes reprises telles quelles des plannings de la clinique */
      var legendes = el('div.grid.gap-3.sm\\:grid-cols-2');
      legendes.appendChild(U.card('Agents de sécurité', el('div.space-y-1\\.5', null, [
        ligneLegende('G', 'Garde — 24 h', 'danger'),
        ligneLegende('S', 'Soirée — de 18h à 8h', 'navy'),
        ligneLegende('R', 'Repos', 'neutral'),
        el('p.mt-2.text-xs.text-slate-400', { text: 'Rotation à trois agents sur un cycle de 3 jours.' }),
      ])));
      legendes.appendChild(U.card('Agents d’entretien', el('div.space-y-1\\.5', null, [
        ligneLegende('P', 'Permanence', 'info'),
        ligneLegende('EGJ', 'Entretien général de la journée', 'info'),
        el('p.mt-2.text-xs.text-slate-400', { text: 'Rotation à trois agents : une permanence, deux entretiens généraux.' }),
      ])));
      host.appendChild(legendes);

      host.appendChild(K.note('Ces légendes sont reprises telles quelles des plannings transmis lors du cadrage : '
        + '« G = GARDE 24H, S = SOIRÉE 18H à 8H, R = REPOS » pour la sécurité, '
        + '« P = PERMANENCE, EGJ = ENTRETIEN GÉNÉRAL DE LA JOURNÉE » pour l’entretien.', { tone: 'info' }));

      /* Rotation sur 14 jours */
      var jours = [];
      for (var i = 0; i < 14; i++) jours.push(C.addDays(AUJ, i - 3));
      var blocGrille = el('div');
      var blocAgents = el('div');
      var blocGraphes = el('div');
      var colPlanning = S.collection('planning', { module: 'M10', entite: 'Planning' });

      host.appendChild(blocGrille);
      host.appendChild(blocAgents);
      host.appendChild(blocGraphes);
      rendreTout();
      host.appendChild(K.source('Plannings des agents d’entretien et des agents de sécurité de la clinique.'));
      root.appendChild(host);
      return null;

      function rendreTout() { rendreGrille(); rendreAgents(); rendreGraphes(); }

      function rendreGrille() {
      C.clear(blocGrille);
      var grilleWrap = el('div.overflow-x-auto');
      var t = el('table.tbl.min-w-\\[60rem\\]');
      var thead = el('thead'), htr = el('tr');
      htr.appendChild(el('th', { text: 'Agent' }));
      htr.appendChild(el('th', { text: 'Fonction' }));
      jours.forEach(function (j) {
        htr.appendChild(el('th.text-center', {
          class: C.iso(j) === C.iso(AUJ) ? 'bg-navy-50 text-navy-800' : '',
          html: C.JOURS[j.getDay()].slice(0, 2) + '<br>' + j.getDate(),
        }));
      });
      thead.appendChild(htr); t.appendChild(thead);
      var tb = el('tbody');
      agents.forEach(function (e) {
        var tr = el('tr');
        tr.appendChild(el('td.text-sm.text-slate-800', { text: e.nomComplet }));
        tr.appendChild(el('td', null, U.badge(fonctionLabel(e.fonction), e.fonction === 'securite' ? 'navy' : 'info')));
        jours.forEach(function (j) {
          var v = planning().filter(function (p) { return p.employeId === e.id && p.date === C.iso(j); })[0];
          var typ = v ? D.TYPES_PLANNING.filter(function (x) { return x.id === v.type; })[0] : null;
          var modifiable = K.droits('M10').editer;
          var cellule = el(modifiable ? 'button.inline-block.rounded.px-1\\.5.py-0\\.5.text-\\[10px\\].font-semibold.transition-colors'
            : 'span.inline-block.rounded.px-1\\.5.py-0\\.5.text-\\[10px\\].font-semibold', {
            type: modifiable ? 'button' : null,
            class: v ? 'bg-' + typePlanningTone(v.type) + '-100 text-' + typePlanningTone(v.type) + '-800'
              + (modifiable ? ' hover:bg-' + typePlanningTone(v.type) + '-200' : '')
              : 'text-slate-300' + (modifiable ? ' hover:bg-slate-100' : ''),
            title: typ ? typ.label : (modifiable ? 'Affecter une vacation' : ''),
            text: typ ? typ.court : (modifiable ? '+' : '—'),
            onclick: modifiable ? function () { affecterRotation(e, j, v); } : null,
          });
          tr.appendChild(el('td.text-center', null, cellule));
        });
        tb.appendChild(tr);
      });
      t.appendChild(tb);
      grilleWrap.appendChild(t);

      blocGrille.appendChild(U.card('Planning rotatif sur 14 jours', grilleWrap, [
        K.btn('Imprimer le planning', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            var lignes = agents.map(function (e) {
              var l = { agent: e.nomComplet, fonction: fonctionLabel(e.fonction) };
              jours.forEach(function (j, i) {
                var v = planning().filter(function (p) { return p.employeId === e.id && p.date === C.iso(j); })[0];
                l['j' + i] = v ? typePlanningLabel(v.type) : '';
              });
              return l;
            });
            P.etat({
              titre: 'Planning des agents de sécurité et d’entretien',
              sousTitre: 'Du ' + C.dateFR(jours[0]) + ' au ' + C.dateFR(jours[jours.length - 1]),
              cartouche: [['Période', C.dateFR(jours[0]) + ' – ' + C.dateFR(jours[jours.length - 1])],
                ['Agents', C.num(agents.length)], ['Établi par', S.currentUser()], ['Date', C.dateFR(AUJ)]],
              contenu: P.tableau([
                { label: 'Agent', key: 'agent' }, { label: 'Fonction', key: 'fonction' },
              ].concat(jours.map(function (j, i) {
                return { label: C.JOURS[j.getDay()].slice(0, 2) + ' ' + j.getDate(), key: 'j' + i };
              })), lignes),
              signatures: [{ role: 'Le Chef de service', nom: 'OURTCHA TEREYAMA' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
            });
          },
        }),
      ]));
      U.icons(blocGrille);
      }

      /* --------------------------------------------------------------------
       * Affectation d'une vacation de rotation.
       * Les types proposés sont ceux du régime de la fonction : un agent de
       * sécurité ne se voit pas proposer « entretien général », et
       * réciproquement — c'est ce qui distingue les deux rotations.
       * ------------------------------------------------------------------ */
      function affecterRotation(agent, jour, existant) {
        var vacations = agent.fonction === 'securite'
          ? ['garde', 'soiree', 'repos24']
          : ['permanence', 'entretien_general', 'incineration', 'repos24'];
        var options = D.TYPES_PLANNING.filter(function (t) { return vacations.indexOf(t.id) !== -1; })
          .map(function (t) {
            return { value: t.id, label: t.court + ' — ' + t.label + (t.debut ? ' (' + t.debut + ' → ' + t.fin + ')' : '') };
          });

        var f = U.form([
          { name: 'type', label: 'Vacation', type: 'select', required: true, options: options },
          { name: 'observation', label: 'Observation', col: 'full' },
        ], existant || { type: vacations[0] });

        var m = U.modal({
          title: 'Rotation — ' + agent.nomComplet, subtitle: C.dateJour(jour), size: 'md',
          body: el('div.space-y-3', null, [
            U.descList([['Agent', agent.nomComplet], ['Fonction', fonctionLabel(agent.fonction)],
              ['Date', C.dateJour(jour)],
              ['Vacation actuelle', existant ? typePlanningLabel(existant.type) : 'Aucune']], 'grid-cols-2'),
            f,
          ]),
          footer: [
            existant && K.droits('M10').annuler ? K.btn('Retirer', {
              variant: 'danger', icon: 'archive',
              onclick: function () {
                U.confirm({
                  title: 'Retirer cette vacation ?',
                  message: 'La vacation est <strong>archivée</strong>, pas supprimée (RG-14) : elle reste '
                    + 'consultable et l’opération est annulable. Le poste redevient vacant sur la rotation.',
                  confirmLabel: 'Retirer', danger: true,
                }).then(function (ok) {
                  if (!ok) return;
                  var res = colPlanning.archive(existant.id);
                  m.close(); rendreTout();
                  U.toast('Vacation retirée.', {
                    type: 'success',
                    undo: function () { res.undo(); rendreTout(); },
                  });
                });
              },
            }) : null,
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                /* Le repos de 24 h qui suit une garde reste opposable ici
                   comme au planning général : deux gardes consécutives pour un
                   agent de sécurité sont refusées. */
                if (v.type === 'garde') {
                  var veille = planning().filter(function (x) {
                    return x.employeId === agent.id && x.date === C.iso(C.addDays(jour, -1)) && x.type === 'garde';
                  })[0];
                  if (veille) {
                    U.toast('Incompatibilité — le repos de 24 h qui suit une garde n’est pas respecté.', {
                      type: 'error',
                      detail: 'Garde déjà programmée le ' + C.dateFR(C.addDays(jour, -1)) + ' pour ' + agent.nomComplet + '.',
                    });
                    return;
                  }
                }
                v.date = C.iso(jour); v.employeId = agent.id; v.employe = agent.nomComplet;
                v.fonction = agent.fonction; v.service = agent.service; v.statut = 'validee';
                var res = existant ? colPlanning.update(existant.id, v) : colPlanning.insert(v);
                m.close(); rendreTout();
                U.toast('Rotation enregistrée.', {
                  type: 'success',
                  detail: agent.nomComplet + ' — ' + typePlanningLabel(v.type) + ' le ' + C.dateFR(jour),
                  undo: function () { res.undo(); rendreTout(); },
                });
              },
            }),
          ].filter(Boolean),
        });
      }

      function rendreAgents() {
        C.clear(blocAgents);
        blocAgents.appendChild(U.dataTable({
        title: 'Agents de sécurité et d’entretien',
        rows: function () { return personnel().filter(function (e) {
          return ['securite', 'entretien'].indexOf(e.fonction) !== -1;
        }); },
        exportName: 'securite-entretien', pageSize: 15,
        actions: [K.creer(S.collection('personnel', { module: 'M10', entite: 'Employe' }), champsAgent(), {
          module: 'M10', label: 'Nouvel agent', titre: 'Nouvel agent de sécurité ou d’entretien',
          entite: 'Agent',
          defauts: function () { return { fonction: 'securite', dateEmbauche: C.iso(AUJ), salaireBase: 40000 }; },
          transform: function (v) {
            if (!v.matricule) v.matricule = C.nextRef('SE-', 3);
            /* Sécurité, entretien et chauffeurs sont rattachés à la Direction :
               un seul intitulé de service, comme partout ailleurs. */
            v.service = 'Direction';
            v.poste = v.poste || fonctionLabel(v.fonction);
            return v;
          },
          apres: rendreTout,
        })].filter(Boolean),
        rowActions: K.actionsLigne(S.collection('personnel', { module: 'M10', entite: 'Employe' }),
          champsAgent(), { module: 'M10', refresh: rendreTout }),
        columns: [
          { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true },
          { key: 'nomComplet', label: 'Agent' },
          { key: 'fonction', label: 'Fonction', text: fonctionLabel, render: function (e) { return U.badge(fonctionLabel(e.fonction), e.fonction === 'securite' ? 'navy' : 'info'); } },
          { key: 'poste', label: 'Poste' },
          { key: 'dateEmbauche', label: 'Embauche', nowrap: true, text: function (e) { return C.dateFR(e.dateEmbauche); }, render: function (e) { return C.dateFR(e.dateEmbauche); } },
          { key: 'salaireBase', label: 'Salaire', align: 'right', text: function (e) { return C.money(e.salaireBase, false); }, render: function (e) { return C.money(e.salaireBase, false); } },
        ],
        }));
        U.icons(blocAgents);
      }

      function champsAgent() {
        return [
          { name: 'nomComplet', label: 'Nom et prénoms', type: 'text', required: true, col: 'full' },
          {
            name: 'fonction', label: 'Fonction', type: 'select', required: true,
            options: [{ value: 'securite', label: 'Agent de sécurité' }, { value: 'entretien', label: 'Agent d’entretien' }],
          },
          { name: 'poste', label: 'Poste occupé', type: 'text' },
          { name: 'dateEmbauche', label: 'Date d’embauche', type: 'date', required: true },
          { name: 'salaireBase', label: 'Salaire de base (FCFA)', type: 'number', required: true, min: 0 },
          { name: 'telephone', label: 'Téléphone', type: 'text' },
        ];
      }

      /* --------------------------------------------------------------------
       * La charge de rotation, vue d'ensemble.
       * ------------------------------------------------------------------ */
      function rendreGraphes() {
        C.clear(blocGraphes);
        var vacations = planning().filter(function (v) {
          return ['securite', 'entretien'].indexOf(v.fonction) !== -1
            && String(v.type).indexOf('repos') !== 0;
        });
        if (!vacations.length) {
          blocGraphes.appendChild(U.card('Statistiques de rotation',
            U.empty('Aucune vacation de sécurité ou d’entretien enregistrée.', { icon: 'shield' })));
          return;
        }
        var parAgent = C.groupBy(vacations, 'employe');
        var noms = Object.keys(parAgent).sort(function (a, b) { return parAgent[b].length - parAgent[a].length; });
        var parType = C.groupBy(vacations, 'type');
        var parFonction = C.groupBy(vacations, 'fonction');

        blocGraphes.appendChild(el('div.grid.gap-4.lg\\:grid-cols-3', null, [
          U.card('Vacations par agent',
            G.barres(noms, [{ label: 'Vacations', data: noms.map(function (k) { return parAgent[k].length; }), color: G.TONES.navy }],
              { horizontal: true, height: 260 })),
          U.card('Répartition par type de poste',
            G.camembert(Object.keys(parType).map(typePlanningLabel),
              Object.keys(parType).map(function (k) { return parType[k].length; }), { height: 260, legend: 'bottom' })),
          U.card('Sécurité et entretien',
            G.anneau(Object.keys(parFonction).map(fonctionLabel),
              Object.keys(parFonction).map(function (k) { return parFonction[k].length; }),
              { legend: 'bottom', colors: [G.TONES.navy, G.TONES.ciel] })),
        ]));
        blocGraphes.appendChild(K.note('Les repos sont exclus de ces comptages : ils figurent à la rotation mais ne '
          + 'sont pas des postes tenus. Un écart marqué entre agents d’une même fonction signale une rotation '
          + 'déséquilibrée — c’est précisément ce que le cycle à trois doit éviter.', { tone: 'info' }));
        U.icons(blocGraphes);
      }

      function ligneLegende(code, libelle, tone) {
        return el('div.flex.items-center.gap-2', null, [
          el('span.inline-grid.h-6.min-w-\\[2rem\\].place-items-center.rounded.px-1\\.5.text-\\[11px\\].font-bold', {
            class: 'bg-' + tone + '-100 text-' + tone + '-800', text: code,
          }),
          el('span.text-sm.text-slate-700', { text: libelle }),
        ]);
      }
    },
  });
  /* ==========================================================================
   * ORDRES DE MISSION
   * --------------------------------------------------------------------------
   * Un agent envoyé en mission ou en formation part avec un ordre écrit : il
   * dit qui, pour quoi, où, quand, et surtout QUI PREND EN CHARGE. Le document
   * se signe au départ et au retour — c'est lui qui justifie l'absence au
   * planning et, le cas échéant, les frais engagés.
   *
   * La validation de la Directrice Administrative conditionne le départ.
   * ======================================================================== */
  function colMissions() { return S.collection('missions', { module: 'M10', entite: 'ordre de mission', prefix: 'OM' }); }

  var STATUTS_MISSION = [
    { id: 'projet', label: 'En projet', tone: 'neutral' },
    { id: 'a_valider', label: 'En attente de validation DA', tone: 'warning' },
    { id: 'validee', label: 'Validée', tone: 'info' },
    { id: 'en_cours', label: 'En cours', tone: 'info' },
    { id: 'terminee', label: 'Terminée', tone: 'success' },
    { id: 'reportee', label: 'Reportée', tone: 'warning' },
    { id: 'annulee', label: 'Annulée', tone: 'danger' },
  ];

  function statutMission(id) {
    return STATUTS_MISSION.filter(function (x) { return x.id === id; })[0] || STATUTS_MISSION[0];
  }

  function amorcerMissions() {
    var db = S.raw();
    if (db.missions && db.missions.length) return;
    var agents = S.collection('personnel').active();
    var rnd = C.seeded(1042);
    var OBJETS = [
      ['Formation en hygiène hospitalière', 'Formation', 'Ministère de la Santé'],
      ['Retrait de commande pharmaceutique', 'Mission', 'CLINIQUE NASSIERA TOO SARL'],
      ['Atelier de gestion des déchets biomédicaux', 'Formation', 'OMS Bénin'],
      ['Représentation à la réunion départementale', 'Mission', 'Direction Départementale de la Santé'],
      ['Formation au logiciel SIGH-CNT', 'Formation', 'CLINIQUE NASSIERA TOO SARL'],
      ['Convoyage de patient vers le CHU', 'Mission', 'CLINIQUE NASSIERA TOO SARL'],
      ['Recyclage en soins obstétricaux d’urgence', 'Formation', 'UNFPA'],
      ['Négociation de convention avec un assureur', 'Mission', 'CLINIQUE NASSIERA TOO SARL'],
    ];
    var VILLES = ['Cotonou', 'Parakou', 'Porto-Novo', 'Djougou', 'Kandi', 'Natitingou'];
    var out = [];
    for (var i = 0; i < 14; i++) {
      var o = C.pick(rnd, OBJETS);
      var agent = C.pick(rnd, agents);
      var depart = C.addDays(AUJ, C.between(rnd, -120, 30));
      var duree = C.between(rnd, 1, 6);
      var passe = depart < AUJ;
      out.push({
        id: 'OM' + C.pad(i + 1, 4), statut: 'actif',
        reference: 'OM-2026-' + C.pad(i + 1, 4),
        libelle: o[0], nature: o[1], objet: o[0],
        agentId: agent.id, agent: agent.nomComplet, fonction: agent.poste,
        structurePrise: o[2],
        destination: C.pick(rnd, VILLES),
        dateDepart: C.iso(depart), dateRetour: C.iso(C.addDays(depart, duree)),
        moyen: C.pick(rnd, ['Véhicule de service', 'Transport en commun', 'Ambulance', 'Moyen personnel']),
        observation: '',
        statutMission: passe
          ? C.pick(rnd, ['terminee', 'terminee', 'reportee'])
          : C.pick(rnd, ['a_valider', 'validee', 'projet']),
        valideePar: passe ? 'TAKI Alimatou' : null,
        valideeLe: passe ? C.iso(C.addDays(depart, -3)) : null,
      });
    }
    db.missions = out;
    S.save();
  }

  function champsMission() {
    return [
      { name: 'libelle', label: 'Libellé de la mission', required: true, col: 'full' },
      {
        name: 'nature', label: 'Nature', type: 'select', required: true,
        options: ['Mission', 'Formation', 'Représentation', 'Convoyage'],
      },
      { name: 'objet', label: 'Objet détaillé', type: 'textarea', rows: 2, col: 'full', required: true },
      {
        name: 'agentId', label: 'Agent affecté', type: 'select', required: true, col: 'full',
        options: C.sortBy(S.collection('personnel').active(), 'nomComplet').map(function (e) {
          return { value: e.id, label: e.nomComplet, detail: e.poste };
        }),
      },
      {
        name: 'structurePrise', label: 'Structure prenant en charge', required: true, col: 'full',
        help: 'Qui supporte les frais : la clinique, l’organisme de formation ou un tiers.',
      },
      { name: 'destination', label: 'Destination', required: true },
      { name: 'moyen', label: 'Moyen de déplacement', type: 'select', options: ['Véhicule de service', 'Transport en commun', 'Ambulance', 'Moyen personnel'] },
      { name: 'dateDepart', label: 'Date de départ', type: 'date', required: true },
      { name: 'dateRetour', label: 'Date de retour', type: 'date', required: true },
      {
        name: 'statutMission', label: 'État', type: 'select', required: true,
        options: STATUTS_MISSION.map(function (s) { return { value: s.id, label: s.label }; }),
      },
      { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
    ];
  }

  global.SIGH.screen('m10-missions', {
    title: 'Ordres de mission',
    description: 'Missions et formations du personnel : affectation, prise en charge, validation et états signés.',
    regle: 'Un départ en mission ou en formation suppose un <strong>ordre écrit</strong> précisant l’agent, '
      + 'l’objet, la destination, les dates et la <strong>structure qui prend en charge</strong>. '
      + 'La <strong>Directrice Administrative valide</strong> avant le départ ; l’ordre imprimé porte les '
      + 'signatures de départ et de retour, et justifie l’absence au planning.',
    render: function (root) {
      amorcerMissions();
      dessiner();
      return null;

      function dessiner() {
        C.clear(root);
        var rows = colMissions().active();
        var aValider = rows.filter(function (m) { return m.statutMission === 'a_valider'; });
        var enCours = rows.filter(function (m) { return m.statutMission === 'en_cours' || m.statutMission === 'validee'; });
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Ordres de mission', value: C.num(rows.length), icon: 'briefcase', tone: 'navy' },
          {
            label: 'En attente de validation', value: C.num(aValider.length), icon: 'stamp',
            tone: aValider.length ? 'warning' : 'success',
            hint: aValider.length ? 'Validation de la DA attendue' : 'Rien en attente',
          },
          { label: 'Missions en cours', value: C.num(enCours.length), icon: 'plane', tone: 'info' },
          { label: 'Terminées', value: C.num(rows.filter(function (m) { return m.statutMission === 'terminee'; }).length), icon: 'check-circle-2', tone: 'success' },
        ]));

        if (aValider.length) {
          host.appendChild(K.note('<strong>' + aValider.length + ' ordre(s) en attente de validation.</strong> '
            + 'Aucun départ ne devrait intervenir avant la signature de la Directrice Administrative.',
          { tone: 'warning', icon: 'stamp' }));
        }

        var creer = K.creer(colMissions(), champsMission, {
          titre: 'Nouvel ordre de mission', entite: 'Ordre de mission',
          defauts: function () {
            return {
              nature: 'Mission', statutMission: 'a_valider',
              dateDepart: C.iso(AUJ), dateRetour: C.iso(C.addDays(AUJ, 2)),
              structurePrise: C.BRAND.nom,
            };
          },
          transform: function (v) {
            var a = S.collection('personnel').get(v.agentId);
            v.reference = 'OM-2026-' + C.pad(colMissions().all().length + 1, 4);
            v.agent = a ? a.nomComplet : '—';
            v.fonction = a ? a.poste : '';
            return v;
          },
          apres: dessiner,
        });

        host.appendChild(U.dataTable({
          title: 'Registre des ordres de mission',
          rows: rows, exportName: 'ordres-mission', pageSize: 15, searchable: true,
          defaultSort: 'dateDepart', defaultDir: 'desc',
          filters: [
            { name: 'nature', label: 'Nature', options: ['Mission', 'Formation', 'Représentation', 'Convoyage'] },
            {
              name: 'statutMission', label: 'État',
              options: STATUTS_MISSION.map(function (s) { return { value: s.id, label: s.label }; }),
            },
          ],
          columns: [
            { key: 'reference', label: 'N°', nowrap: true, render: function (m) { return el('span.font-mono.text-xs', { text: m.reference }); } },
            {
              key: 'libelle', label: 'Mission',
              render: function (m) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: m.libelle }),
                  el('p.truncate.text-xs.text-slate-400', { text: m.nature + ' · ' + m.destination }),
                ]);
              },
            },
            {
              key: 'agent', label: 'Agent affecté',
              render: function (m) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.text-slate-700', { text: m.agent }),
                  el('p.truncate.text-xs.text-slate-400', { text: m.fonction || '' }),
                ]);
              },
            },
            { key: 'structurePrise', label: 'Prise en charge' },
            {
              key: 'dateDepart', label: 'Période', nowrap: true,
              text: function (m) { return C.dateFR(m.dateDepart) + ' → ' + C.dateFR(m.dateRetour); },
              render: function (m) {
                return el('div', null, [
                  el('p.text-sm.text-slate-700', { text: C.dateFR(m.dateDepart) }),
                  el('p.text-xs.text-slate-400', { text: 'au ' + C.dateFR(m.dateRetour) }),
                ]);
              },
              sortValue: function (m) { return C.toDate(m.dateDepart).getTime(); },
            },
            {
              key: 'statutMission', label: 'État',
              text: function (m) { return statutMission(m.statutMission).label; },
              render: function (m) {
                var s = statutMission(m.statutMission);
                return U.badge(s.label, s.tone);
              },
            },
            {
              key: 'valideePar', label: 'Validation',
              render: function (m) {
                return m.valideePar
                  ? el('div', null, [
                    el('p.text-xs.text-success-700', { text: m.valideePar }),
                    el('p.text-\\[10px\\].text-slate-400', { text: m.valideeLe ? C.dateFR(m.valideeLe) : '' }),
                  ])
                  : el('span.text-xs.text-warning-600', { text: 'non validé' });
              },
            },
          ],
          onRowClick: fiche,
          rowActions: function (m) {
            var actions = [];
            if (m.statutMission === 'a_valider') {
              actions.push(K.iconBtn('stamp', 'Valider (Directrice Administrative)', function () { valider(m); }));
            }
            if (m.statutMission === 'validee' || m.statutMission === 'en_cours') {
              actions.push(K.iconBtn('check', 'Marquer terminée', function () { changerEtat(m, 'terminee', 'Mission terminée.'); }));
              actions.push(K.iconBtn('calendar-clock', 'Reporter', function () { changerEtat(m, 'reportee', 'Mission reportée.'); }));
            }
            actions.push(K.iconBtn('printer', 'Imprimer l’ordre', function () { imprimer(m); }));
            return actions.concat(K.actionsLigne(colMissions(), champsMission, { entite: 'ordre de mission' })(m));
          },
          actions: [creer],
        }));

        root.appendChild(host);
        U.icons(root);
      }

      function valider(m) {
        U.confirm({
          title: 'Valider l’ordre de mission ' + m.reference + ' ?',
          message: 'La validation autorise le départ de ' + m.agent + ' du ' + C.dateFR(m.dateDepart)
            + ' au ' + C.dateFR(m.dateRetour) + ', aux frais de ' + m.structurePrise + '. '
            + 'Elle est journalisée au nom de la Directrice Administrative (RG-12).',
          confirmLabel: 'Valider l’ordre',
        }).then(function (ok) {
          if (!ok) return;
          var res = colMissions().update(m.id, {
            statutMission: 'validee', valideePar: 'TAKI Alimatou', valideeLe: C.iso(AUJ),
          });
          dessiner();
          U.toast('Ordre de mission validé.', {
            type: 'success', detail: m.agent + ' — départ le ' + C.dateFR(m.dateDepart),
            undo: function () { res.undo(); dessiner(); },
          });
        });
      }

      function changerEtat(m, etat, message) {
        var res = colMissions().update(m.id, { statutMission: etat });
        dessiner();
        U.toast(message, { type: 'success', undo: function () { res.undo(); dessiner(); } });
      }

      function fiche(m) {
        U.drawer({
          title: m.reference, subtitle: m.libelle, width: 'max-w-2xl',
          body: el('div.space-y-4', null, [
            U.descList([
              ['Agent affecté', m.agent], ['Fonction', m.fonction || '—'],
              ['Nature', m.nature], ['Objet', m.objet],
              ['Destination', m.destination], ['Moyen', m.moyen || '—'],
              ['Départ', C.dateFR(m.dateDepart)], ['Retour', C.dateFR(m.dateRetour)],
              ['Prise en charge', m.structurePrise],
              ['État', statutMission(m.statutMission).label],
              ['Validée par', m.valideePar || 'non validée'],
              ['Observation', m.observation || '—'],
            ]),
          ]),
          footer: [K.btn('Imprimer l’ordre', { variant: 'primary', icon: 'printer', onclick: function () { imprimer(m); } })],
        });
      }

      function imprimer(m) {
        P.etat({
          titre: 'Ordre de mission',
          sousTitre: m.reference + ' — ' + m.agent,
          cartouche: [['Agent', m.agent], ['Fonction', m.fonction || '—'],
            ['Nature', m.nature], ['Destination', m.destination],
            ['Départ', C.dateFR(m.dateDepart)], ['Retour', C.dateFR(m.dateRetour)],
            ['Moyen de déplacement', m.moyen || '—'],
            ['Prise en charge des frais', m.structurePrise]],
          contenu: el('div.space-y-3', null, [
            el('p.text-\\[10px\\].leading-relaxed.text-slate-700', {
              text: 'La Directrice Administrative de la Clinique NASSIERA TOO donne ordre à '
                + m.agent + ', ' + (m.fonction || 'agent de la clinique')
                + ', de se rendre à ' + m.destination + ' du ' + C.dateFR(m.dateDepart)
                + ' au ' + C.dateFR(m.dateRetour) + ', à l’effet de : ' + m.objet + '.',
            }),
            el('p.mt-2.text-\\[10px\\].leading-relaxed.text-slate-700', {
              text: 'Les frais afférents à cette mission sont pris en charge par ' + m.structurePrise + '.',
            }),
            m.observation ? el('p.mt-2.text-\\[10px\\].text-slate-600', { text: 'Observation : ' + m.observation }) : null,
            el('div.mt-6.grid.grid-cols-2.gap-6.text-\\[10px\\]', null, [
              el('div.rounded.border.border-slate-300.p-3', null, [
                el('p.font-semibold', { text: 'Visa de départ' }),
                el('p.mt-8.border-t.border-dotted.border-slate-400.pt-1.text-slate-400', { text: 'Date, cachet et signature' }),
              ]),
              el('div.rounded.border.border-slate-300.p-3', null, [
                el('p.font-semibold', { text: 'Visa de retour' }),
                el('p.mt-8.border-t.border-dotted.border-slate-400.pt-1.text-slate-400', { text: 'Date, cachet et signature' }),
              ]),
            ]),
          ]),
          signatures: [{ role: 'L’agent', nom: m.agent },
            { role: 'La Directrice Administrative', nom: m.valideePar || 'TAKI Alimatou' }],
        });
      }
    },
  });


  /* ==========================================================================
   * FICHES DE POSTE
   * --------------------------------------------------------------------------
   * Le gabarit vient des DEUX descriptions de poste remises par la clinique :
   * celle de l'Infirmier Général (26/10/2023, archivage 213/10/CNT/DA/2023) et
   * celle intitulée « Directrice Administrative » (01/12/2023, archivage 245)
   * — dont le corps décrit en réalité son ADJOINT.
   *
   * Quatre sections, dans l'ordre du document :
   *   I   Identification du poste — rattachement, niveau N/N+1/N−1, textes ;
   *   II  Missions, activités et tâches, avec leurs INDICATEURS CHIFFRÉS ;
   *   III Relations fonctionnelles, interne et externe ;
   *   IV  Compétences : diplômes, savoir-faire, savoir-être.
   *
   * LES INDICATEURS SONT LE POINT IMPORTANT. « 95 % des retards constatés et
   * notifiés », « 100 % des statistiques transmises à bonne date » : ce sont
   * eux qui rendent l'évaluation NS 131 mesurable au lieu d'être une
   * appréciation. Une fiche de poste sans indicateur ne sert qu'à classer.
   *
   * Les deux fiches documentées sont amorcées telles quelles ; les autres
   * postes reçoivent une fiche VIDE, explicitement marquée « à rédiger ». Les
   * inventer donnerait à la clinique des missions qu'elle n'a jamais écrites.
   * ======================================================================== */
  function colFichesPoste() {
    return S.collection('fichesPoste', { module: 'M10', entite: 'fiche de poste', prefix: 'FDP' });
  }

  global.SIGH.screen('m10-fiches-poste', {
    title: 'Fiches de poste',
    description: 'Identification, missions, indicateurs de performance, relations fonctionnelles et compétences requises.',
    regle: 'Le gabarit est celui des <strong>deux descriptions de poste</strong> remises par la clinique. '
      + 'Les <strong>indicateurs chiffrés</strong> en sont le cœur : ce sont eux qui rendent l’évaluation '
      + 'NS 131 mesurable. Les postes sans document reçoivent une fiche <strong>vide et marquée</strong> — '
      + 'les inventer donnerait à la clinique des missions qu’elle n’a jamais écrites.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      amorcer();
      afficher();
      return null;

      /* Les deux fiches documentées, relevées mot pour mot. */
      function documentees() {
        return [
          {
            intitule: 'Infirmier Général (IG)',
            elaboration: '2023-10-26', archivage: '213/10/CNT/DA/2023',
            rattachement: 'Soins médico-infirmiers et obstétricaux',
            niveauN: 'Exécutant', niveauSup: 'Médecin, DA', niveauInf: 'Infirmiers, sages-femmes',
            statut: 'Employé',
            textes: 'Convention collective du travail · Contrat de travail · Note de service portant nomination de l’IG',
            resume: 'Contrôler le personnel, superviser les soins, produire les statistiques, régler les conflits.',
            missions: [
              { mission: 'Contrôler le personnel', activites: [
                'Contrôler et superviser l’exécution des soins prescrits par les médecins et sages-femmes',
                'Vérifier le bon remplissage des documents de transfusion sanguine',
                'Veiller au bon remplissage des différents registres en vigueur',
                'Contrôler la bonne tenue des documents médicaux',
                'Veiller au port des tenues réglementaires',
                'Veiller à l’exécution des programmes nationaux',
                'Surveiller les retards, les sorties et les absences non autorisées',
                'Surveiller l’utilisation du portable durant le service',
              ], indicateurs: [
                '100 % des documents de transfusion sanguine vérifiés et corrigés par mois',
                '100 % des registres contrôlés par mois',
                '100 % des agents en tenue réglementaire',
                '95 % des retards constatés et notifiés',
              ] },
              { mission: 'Participer aux soins', activites: [
                'Faire la visite des patients avec les médecins',
                'Superviser les soins infirmiers aux patients',
                'Informer les médecins et le chirurgien des cas réputés graves',
              ], indicateurs: [] },
              { mission: 'Commander les registres à mettre à la disposition du personnel', activites: [
                'Collecter les données pour les statistiques',
                'Transmettre les statistiques à la zone sanitaire à bonne date',
              ], indicateurs: ['100 % des statistiques mensuelles transmises à bonne date'] },
              { mission: 'Régler les conflits entre agents et avec les usagers', activites: [
                'Écouter les agents en conflit et faire la réconciliation',
                'Faire la médiation entre usagers en conflit',
              ], indicateurs: ['Au moins 75 % des conflits réglés'] },
              { mission: 'Représenter la clinique et faire le planning du personnel paramédical', activites: [
                'Conseiller l’administration sur les améliorations à apporter',
                'Servir d’intermédiaire entre l’administration et le personnel',
                'Signaler les pannes et défectuosités constatées sur les matériels',
                'Participer aux réunions et aux prises de décisions',
                'Participer à l’élaboration des protocoles de soins',
                'Faire des staffs cliniques avec les infirmiers et sages-femmes',
                'Veiller à l’hygiène',
              ], indicateurs: [
                '80 % de suggestions faites à l’administration',
                '100 % des pannes signalées',
                'Au moins 12 staffs cliniques par an',
              ] },
            ],
            relationsInternes: 'Clinique Nassièra Too · tous les secteurs de la CNT — contacts physiques, corporate, mails, courriers',
            relationsExternes: 'DDS · Zone Sanitaire de Natitingou · Ministère de la Santé · usagers',
            environnement: 'Mobilier de bureau, armoire, brasseur, PC, imprimante, connexion internet, corporate, oxymètre de pouls, stéthoscope, tensiomètre',
            diplomes: 'Diplôme d’Infirmier d’État',
            savoirFaire: 'Expérience professionnelle d’au moins 2 ans · maîtrise de la déontologie médicale · '
              + 'connaissance des textes réglementaires · facilité à communiquer et habileté diplomatique · '
              + 'travail en équipe et sous pression · maîtrise minimale de l’outil informatique et d’internet',
            savoirEtre: 'Respect de la hiérarchie · courtoisie avec les collègues · courtoisie avec les usagers · '
              + 'éviction des actes immoraux (ivresse, propos déplacés, vol)',
            source: 'Description de poste du 26/10/2023',
          },
          {
            intitule: 'Assistant(e) de Direction',
            elaboration: '2023-12-01', archivage: '245',
            rattachement: 'Administration de la CNT',
            niveauN: 'Décideur', niveauSup: 'Directeur Médical', niveauInf: 'DAF',
            statut: 'Employé(e)',
            textes: 'Convention collective du travail · Contrat de travail · Note de service portant nomination',
            resume: 'Tenir la comptabilité, assister la DA, représenter la clinique à diverses occasions, sous l’autorité de la DA.',
            anomalie: 'Le document s’intitule « DIRECTRICE ADMINISTRATIVE (DA) » mais son corps décrit son '
              + 'ADJOINT : mission 2 « assister la Directrice Administrative », activité 28 « assurer l’intérim '
              + 'de la DA ». Un poste ne peut pas être à la fois la DA et son assistant. L’intitulé retenu est '
              + 'donc « Assistant(e) de Direction », conformément à la liste de comptes du 25/08/2026 — et '
              + 'l’écart avec le titre du document est signalé plutôt que corrigé en silence.',
            missions: [
              { mission: 'Tenir la comptabilité', activites: [
                'Mettre à jour les différents livres de compte',
                'Réclamer les factures normalisées après chaque achat',
                'Enregistrer les recettes et les dépenses',
                'Suivre les versements des recettes à la banque',
                'Suivre le compte de la banque à la clinique et de la clinique à la banque',
                'Faire les rapprochements bancaires',
                'Faire le recouvrement des créances chez les débiteurs particuliers et les compagnies d’assurance',
                'Suivre le règlement des créances par les débiteurs et surtout les assureurs',
                'Exécuter les achats et les dépenses budgétisés',
                'Faire les dépôts de recettes, remises de chèque, ordres de virement et retraits',
                'Traiter les salaires des employés et les rémunérations des prestataires, sur avis de la DA',
                'Faire le point des recettes et dépenses autorisées à la caisse en l’absence de la DA',
                'Déclarer et payer à bonne date les obligations fiscales et sociales (Impôts, CNSS, CCIB)',
                'Suivre et rembourser les emprunts de la clinique à bonne date',
                'Calculer chaque mois le bénéfice comptable et le bénéfice fiscal',
                'Suivre les décaissements et les recouvrements des prêts-études',
                'Faire un compte rendu mensuel de la comptabilité à la hiérarchie',
                'Analyser et commenter l’évolution des recettes et des dépenses',
              ], indicateurs: [
                '100 % des livres de compte à jour',
                '100 % des factures d’achats normalisées',
                '100 % des irrégularités et écarts à la banque constatés et réglés',
                '100 % des traitements salariaux et rémunérations prêts à bonne date',
                '100 % des déclarations fiscales et sociales faites à bonne date',
              ] },
              { mission: 'Assister la Directrice Administrative', activites: [
                'Faire des suggestions pour améliorer le climat des affaires',
                'Anticiper par proactivité sur les événements susceptibles de susciter des déconvenues',
                'Veiller au bon fonctionnement du groupe électrogène avec les agents de sécurité',
                'Assister la DA dans la gestion du personnel médical, paramédical et non soignant',
                'Faire l’inventaire périodique et annuel des médicaments d’urgence et des réactifs de laboratoire',
                'Faire l’inventaire périodique et annuel des matériels avec le Directeur Médical',
                'Faire le point journalier de la caisse en l’absence de la DA',
                'Faire appel aux réparateurs pour les pannes, sur avis de la DA',
                'Établir un plan de maintenance des appareils et matériels',
                'Faire les petites commandes et les petites dépenses urgentes sur avis de la DA',
                'Assurer l’intérim de la DA',
              ], indicateurs: [
                'Proportion de bonnes suggestions faites',
                'Proportion des inventaires faits à bonne date',
              ] },
              { mission: 'Représenter la clinique à diverses occasions', activites: [
                'Être le porte-parole de la clinique',
                'Faire les courses administratives',
              ], indicateurs: ['Pourcentage de courses administratives réussies'] },
            ],
            relationsInternes: 'Direction · comptabilité · caisse · tous les secteurs',
            relationsExternes: 'Banques · administration fiscale · CNSS · CCIB · compagnies d’assurance · fournisseurs',
            environnement: 'Mobilier de bureau, PC, imprimante, connexion internet, logiciels de gestion',
            diplomes: 'À préciser par la Direction',
            savoirFaire: 'À préciser par la Direction',
            savoirEtre: 'À préciser par la Direction',
            source: 'Description de poste du 01/12/2023',
          },
        ];
      }

      /* La collection est amorcée par CET écran : lui seul la lit. */
      function amorcer() {
        var col = colFichesPoste();
        if (col.all().length) return;
        documentees().forEach(function (f) { col.insert(Object.assign({ redigee: true }, f)); });
        /* Les autres postes reçoivent une fiche VIDE, marquée : la clinique
           n'a remis que deux documents, en inventer douze donnerait des
           missions qu'elle n'a jamais écrites. */
        var vus = {};
        documentees().forEach(function (f) { vus[f.intitule] = true; });
        S.collection('personnel').active().forEach(function (a) {
          var titre = a.poste || a.fonction;
          if (!titre || vus[titre]) return;
          vus[titre] = true;
          col.insert({
            intitule: titre, rattachement: a.service, statut: 'Employé(e)',
            resume: '', missions: [], redigee: false,
            source: 'Poste relevé à l’organigramme — fiche à rédiger',
          });
        });
        S.save();
      }

      function champs() {
        return [
          { name: 'intitule', label: 'Intitulé du poste', type: 'text', required: true },
          { name: 'archivage', label: 'Numéro d’archivage', type: 'text' },
          { name: 'elaboration', label: 'Date d’élaboration', type: 'date' },
          { name: 'miseAJour', label: 'Date de mise à jour', type: 'date' },
          { name: 'rattachement', label: 'Structure de rattachement', type: 'text', required: true },
          { name: 'niveauN', label: 'Niveau hiérarchique — N', type: 'text' },
          { name: 'niveauSup', label: 'Niveau hiérarchique — N+1', type: 'text' },
          { name: 'niveauInf', label: 'Niveau hiérarchique — N−1', type: 'text' },
          { name: 'statut', label: 'Statut du titulaire', type: 'text' },
          { name: 'textes', label: 'Textes réglementaires liés au poste', type: 'textarea', rows: 2 },
          { name: 'resume', label: 'Résumé succinct du poste', type: 'textarea', rows: 2, required: true },
          { type: 'section', label: 'Relations fonctionnelles et environnement' },
          { name: 'relationsInternes', label: 'Relations internes', type: 'textarea', rows: 2 },
          { name: 'relationsExternes', label: 'Relations externes', type: 'textarea', rows: 2 },
          { name: 'environnement', label: 'Environnement et moyens de travail', type: 'textarea', rows: 2 },
          { type: 'section', label: 'Compétences et qualifications requises' },
          { name: 'diplomes', label: 'Diplômes attendus', type: 'textarea', rows: 2 },
          { name: 'savoirFaire', label: 'Compétences techniques (savoir-faire)', type: 'textarea', rows: 3 },
          { name: 'savoirEtre', label: 'Savoir-être', type: 'textarea', rows: 3 },
        ];
      }

      function afficher() {
        var rows = colFichesPoste().active();
        var redigees = rows.filter(function (r) { return r.redigee; });
        var indicateurs = rows.reduce(function (n, r) {
          return n + (r.missions || []).reduce(function (m, x) { return m + (x.indicateurs || []).length; }, 0);
        }, 0);

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Postes recensés', value: C.num(rows.length), icon: 'file-badge', tone: 'navy' },
          { label: 'Fiches rédigées', value: C.num(redigees.length), icon: 'check-check',
            tone: redigees.length === rows.length ? 'success' : 'warning',
            hint: C.num(rows.length - redigees.length) + ' à rédiger' },
          { label: 'Missions décrites', value: C.num(rows.reduce(function (n, r) {
            return n + (r.missions || []).length;
          }, 0)), icon: 'target', tone: 'info' },
          { label: 'Indicateurs de performance', value: C.num(indicateurs), icon: 'gauge', tone: 'success',
            hint: 'ils rendent l’évaluation NS 131 mesurable' },
        ]));

        vue.appendChild(K.note('Seules <strong>deux fiches</strong> proviennent d’un document remis par la '
          + 'clinique. Les autres postes sont recensés depuis l’organigramme et leur fiche est '
          + '<strong>vide, marquée « à rédiger »</strong> — les inventer donnerait à la clinique des missions '
          + 'qu’elle n’a jamais écrites, et ces missions serviraient ensuite à évaluer des agents.',
        { tone: 'warning', icon: 'file-question' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'intitule'),
          empty: 'Aucune fiche de poste.',
          actions: [K.creer(colFichesPoste(), champs(), {
            module: 'M10', label: 'Nouvelle fiche de poste', titre: 'Fiche de poste',
            entite: 'Fiche de poste', size: 'lg', apres: afficher,
            transform: function (v) {
              return Object.assign({ missions: [], redigee: true,
                source: 'Rédigée dans l’application' }, v);
            },
          })].filter(Boolean),
          columns: [
            { key: 'intitule', label: 'Intitulé du poste' },
            { key: 'rattachement', label: 'Rattachement' },
            { key: 'archivage', label: 'N° d’archivage',
              render: function (r) { return r.archivage || '—'; } },
            { key: 'missions', label: 'Missions', align: 'center',
              render: function (r) { return C.num((r.missions || []).length); } },
            { key: 'redigee', label: 'État',
              render: function (r) {
                return r.redigee ? U.badge('Rédigée', 'success') : U.badge('À rédiger', 'warning');
              } },
          ],
          rowActions: function (r) {
            return [K.iconBtn('printer', 'Imprimer la fiche de poste', function () { imprimer(r); })]
              .concat(K.actionsLigne(colFichesPoste(), champs(), {
                module: 'M10', refresh: afficher, detail: detail,
                titre: function (x) { return x.intitule; },
              })(r));
          },
        }));
        U.icons(vue);
      }

      function detail(r) {
        var blocs = [
          K.grid([
            ['Intitulé du poste', r.intitule],
            ['Numéro d’archivage', r.archivage || '—'],
            ['Élaboration', r.elaboration ? C.dateFR(r.elaboration) : '—'],
            ['Mise à jour', r.miseAJour ? C.dateFR(r.miseAJour) : '—'],
            ['Structure de rattachement', r.rattachement || '—'],
            ['Niveau N', r.niveauN || '—'],
            ['Niveau N+1', r.niveauSup || '—'],
            ['Niveau N−1', r.niveauInf || '—'],
            ['Statut du titulaire', r.statut || '—'],
            ['Source', r.source || '—'],
          ]),
          r.anomalie ? K.note(r.anomalie, { tone: 'warning', icon: 'triangle-alert' }) : null,
          r.resume ? K.section('Résumé succinct du poste',
            el('p.text-sm.text-slate-600', { text: r.resume })) : null,
        ];
        (r.missions || []).forEach(function (m, i) {
          blocs.push(K.section('Mission ' + (i + 1) + ' — ' + m.mission,
            el('div.space-y-3', null, [
              K.miniTable(['Activités et tâches'], (m.activites || []).map(function (a) { return [a]; })),
              (m.indicateurs || []).length
                ? el('div', null, [
                  el('p.mb-1.text-xs.font-semibold.uppercase.tracking-wide.text-slate-500',
                    { text: 'Résultats attendus et indicateurs' }),
                  K.miniTable(['Indicateur'], m.indicateurs.map(function (x) { return [x]; })),
                ])
                : el('p.text-xs.italic.text-slate-400', { text: 'Aucun indicateur chiffré au document.' }),
            ])));
        });
        if (!(r.missions || []).length) {
          blocs.push(K.note('Cette fiche n’a pas encore été rédigée : la clinique n’a remis de description '
            + 'de poste que pour l’Infirmier Général et l’Assistant de Direction.',
          { tone: 'warning', icon: 'file-question' }));
        }
        blocs.push(K.section('Relations fonctionnelles et compétences',
          K.miniTable(['Rubrique', 'Contenu'], [
            ['Relations internes', r.relationsInternes || '—'],
            ['Relations externes', r.relationsExternes || '—'],
            ['Environnement et moyens', r.environnement || '—'],
            ['Diplômes attendus', r.diplomes || '—'],
            ['Savoir-faire', r.savoirFaire || '—'],
            ['Savoir-être', r.savoirEtre || '—'],
          ])));
        return el('div.space-y-4', null, blocs.filter(Boolean));
      }

      function imprimer(r) {
        var corps = el('div');
        corps.appendChild(el('p.mb-2.text-\\[10px\\].font-bold.uppercase', { text: 'I — Identification du poste' }));
        corps.appendChild(P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Contenu', key: 'v' }], [
          { k: 'Intitulé du poste', v: r.intitule },
          { k: 'Numéro d’archivage', v: r.archivage || '—' },
          { k: 'Élaboration', v: r.elaboration ? C.dateFR(r.elaboration) : '—' },
          { k: 'Structure de rattachement', v: r.rattachement || '—' },
          { k: 'Niveau hiérarchique', v: 'N : ' + (r.niveauN || '—') + '   N+1 : ' + (r.niveauSup || '—')
            + '   N−1 : ' + (r.niveauInf || '—') },
          { k: 'Statut du titulaire', v: r.statut || '—' },
          { k: 'Textes réglementaires', v: r.textes || '—' },
          { k: 'Résumé succinct', v: r.resume || '—' },
        ]));
        corps.appendChild(el('p.mb-2.mt-4.text-\\[10px\\].font-bold.uppercase',
          { text: 'II — Missions, activités et tâches' }));
        (r.missions || []).forEach(function (m, i) {
          corps.appendChild(el('p.mb-1.mt-2.text-\\[10px\\].font-semibold',
            { text: 'Mission ' + (i + 1) + ' : ' + m.mission }));
          corps.appendChild(P.tableau([
            { label: 'Activités et tâches', key: 'a' },
            { label: 'Résultats attendus et indicateurs', key: 'i' },
          ], (m.activites || []).map(function (a, j) {
            return { a: 'Activité ' + (j + 1) + ' : ' + a, i: (m.indicateurs || [])[j] || '' };
          })));
        });
        corps.appendChild(el('p.mb-2.mt-4.text-\\[10px\\].font-bold.uppercase',
          { text: 'III — Relations fonctionnelles et environnement de travail' }));
        corps.appendChild(P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Contenu', key: 'v' }], [
          { k: 'Au plan interne', v: r.relationsInternes || '—' },
          { k: 'Au plan externe', v: r.relationsExternes || '—' },
          { k: 'Environnement et moyens de travail', v: r.environnement || '—' },
        ]));
        corps.appendChild(el('p.mb-2.mt-4.text-\\[10px\\].font-bold.uppercase',
          { text: 'IV — Compétences et qualifications requises' }));
        corps.appendChild(P.tableau([
          { label: 'Diplômes attendus', key: 'd' },
          { label: 'Compétences techniques (savoir-faire)', key: 'sf' },
          { label: 'Savoir-être', key: 'se' },
        ], [{ d: r.diplomes || '—', sf: r.savoirFaire || '—', se: r.savoirEtre || '—' }]));

        P.etat({
          titre: 'DESCRIPTION DE POSTE',
          sousTitre: r.intitule,
          contenu: corps,
          signatures: [
            { role: 'Le titulaire du poste', nom: '', mention: 'Signature' },
            { role: 'La Direction', nom: '', mention: 'Signature et cachet' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * STATISTIQUES DES PERMANENCES
   * --------------------------------------------------------------------------
   * Les statistiques de garde comptent ENSEMBLE gardes, permanences, soirées,
   * entretien et incinération. C'est juste pour mesurer la charge totale, et
   * inutilisable pour la prime : la NS 132 tarife la permanence À PART, et un
   * agent qui a fait dix gardes et zéro permanence apparaissait comme un autre
   * qui aurait fait l'inverse.
   *
   * LA PERMANENCE EST UN RÉGIME PRÉCIS — 08h à 18h, par opposition à la garde
   * de vingt-quatre heures. Ce sont deux fatigues et deux rémunérations
   * différentes ; les compter ensemble efface la distinction que la note de
   * service a justement établie.
   * ======================================================================== */
  function estPermanence(v) {
    var t = String(v.type || v.regimeLibelle || '').toLowerCase();
    return /permanence/.test(t);
  }

  global.SIGH.screen('m10-stats-permanences', {
    title: 'Statistiques des permanences',
    description: 'Nombre de permanences assurées par agent, par service et par fonction, sur la période choisie.',
    regle: 'La <strong>permanence</strong> (08h–18h) n’est pas la <strong>garde</strong> (24h) : deux '
      + 'fatigues, deux rémunérations, deux lignes de la <strong>NS 132</strong>. Les compter ensemble '
      + 'effacerait la distinction que la note de service a établie — c’est pourquoi cet écran existe à '
      + 'côté des statistiques de garde. <strong>Repos et congés restent exclus</strong> : ils figurent '
      + 'au planning mais ne sont pas du travail effectué.',
    actions: function () {
      return [
        K.btn('Statistiques de garde', { icon: 'chart-column',
          onclick: function () { global.SIGH.app.go('m10-stats-gardes'); } }),
        K.btn('Planning', { icon: 'calendar-clock',
          onclick: function () { global.SIGH.app.go('m10-planning'); } }),
      ];
    },
    render: function (root) {
      var selPeriode = el('select.select');
      C.PERIODES.forEach(function (x) { selPeriode.appendChild(el('option', { value: x.id }, x.label)); });
      selPeriode.value = 'mois';
      var inDate = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var selService = el('select.select');
      var vue = el('div.space-y-4');

      var services = ['— Tous les services —'].concat(
        Object.keys(C.groupBy(personnel(), 'service')).sort());
      services.forEach(function (x) { selService.appendChild(el('option', { value: x }, x)); });

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Périodicité' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Arrêtée au' }), inDate]),
        el('div', null, [el('label.label', { text: 'Service' }), selService]),
        K.btn('Imprimer l’état', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));
      [selPeriode, inDate, selService].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function bornes() { return C.bornes(selPeriode.value, inDate.value); }

      function agentDe(id) {
        return personnel().filter(function (a) { return a.id === id; })[0] || null;
      }

      function lignes() {
        var b = bornes();
        var svc = selService.value;
        return S.collection('planning').active().filter(function (v) {
          if (!C.dansBornes(v.date, b)) return false;
          if (!estPermanence(v)) return false;
          if (svc && svc.indexOf('Tous') < 0) {
            var a = agentDe(v.employeId || v.personnelId);
            if (!a || a.service !== svc) return false;
          }
          return true;
        });
      }

      function parAgent() {
        var vac = lignes();
        var par = {};
        vac.forEach(function (v) {
          var a = agentDe(v.employeId || v.personnelId);
          var cle = a ? a.id : (v.agent || 'inconnu');
          if (!par[cle]) {
            par[cle] = {
              id: cle, agent: a ? a.nomComplet : (v.agent || '—'),
              matricule: a ? a.matricule : '—',
              service: a ? a.service : '—',
              fonction: a ? a.poste : '—',
              nombre: 0,
            };
          }
          par[cle].nombre++;
        });
        return C.sortBy(Object.keys(par).map(function (k) { return par[k]; }), 'nombre', 'desc');
      }

      function afficher() {
        C.clear(vue);
        var b = bornes();
        var rows = parAgent();
        var total = C.sum(rows, 'nombre');

        vue.appendChild(K.note('<strong>' + C.libellePeriode(b) + '</strong> — ' + C.num(total)
          + ' permanence(s) assurée(s) par ' + C.num(rows.length) + ' agent(s). '
          + 'La permanence court de <strong>08h à 18h</strong> ; la garde de vingt-quatre heures est '
          + 'comptée sur son propre écran.', { tone: 'info', icon: 'clock-9' }));

        vue.appendChild(U.kpiGrid([
          { label: 'Permanences assurées', value: C.num(total), icon: 'clock-9', tone: 'navy' },
          { label: 'Agents concernés', value: C.num(rows.length), icon: 'users', tone: 'info' },
          { label: 'Moyenne par agent', value: rows.length ? (total / rows.length).toFixed(1) : '0',
            icon: 'scale', tone: 'neutral' },
          { label: 'Le plus sollicité', value: rows.length ? rows[0].agent : '—',
            icon: 'award', tone: 'warning',
            hint: rows.length ? C.num(rows[0].nombre) + ' permanence(s)' : '' },
        ]));

        vue.appendChild(U.dataTable({
          rows: rows, exportName: 'stats-permanences', pageSize: 20, searchable: true,
          filters: [{ name: 'service', label: 'Service',
            options: Object.keys(C.groupBy(rows, 'service')).sort() }],
          columns: [
            { key: 'agent', label: 'Agent', render: function (x) {
              return el('div', null, [
                el('p.font-medium', { text: x.agent }),
                el('p.text-[10px].text-slate-400', { text: 'Mat. ' + x.matricule }),
              ]);
            } },
            { key: 'service', label: 'Service', render: function (x) { return U.badge(x.service, 'navy'); } },
            { key: 'fonction', label: 'Fonction' },
            { key: 'nombre', label: 'Permanences', align: 'right',
              render: function (x) {
                return el('span.font-bold.text-navy-800', { text: C.num(x.nombre) });
              } },
          ],
        }));

        if (rows.length) {
          var parSvc = C.groupBy(rows, 'service');
          var svcRows = Object.keys(parSvc).map(function (k) {
            return { label: k, total: C.sum(parSvc[k], 'nombre') };
          });
          svcRows = C.sortBy(svcRows, 'total', 'desc');
          vue.appendChild(K.charts([
            { title: 'Permanences par agent',
              render: function () {
                var top = rows.slice(0, 12);
                return G.barres(top.map(function (x) { return x.agent.split(' ')[0]; }),
                  [{ label: 'Permanences', data: top.map(function (x) { return x.nombre; }),
                    color: G.TONES.navy }], { horizontal: true, height: 300 });
              } },
            { title: 'Permanences par service',
              render: function () {
                return G.anneau(svcRows.map(function (x) { return x.label; }),
                  svcRows.map(function (x) { return x.total; }));
              } },
          ]));
        }
      }

      function imprimer() {
        var b = bornes();
        var rows = parAgent();
        P.etat({
          titre: 'Statistiques des permanences',
          sousTitre: C.libellePeriode(b),
          cartouche: [
            ['Période', C.libellePeriode(b)],
            ['Service', selService.value],
            ['Permanences assurées', C.num(C.sum(rows, 'nombre'))],
            ['Agents concernés', C.num(rows.length)],
          ],
          contenu: P.tableau([
            { label: 'Agent', value: function (x) { return x.agent; } },
            { label: 'Matricule', value: function (x) { return x.matricule; } },
            { label: 'Service', value: function (x) { return x.service; } },
            { label: 'Fonction', value: function (x) { return x.fonction; } },
            { label: 'Permanences', align: 'right',
              value: function (x) { return C.num(x.nombre); },
              somme: function (x) { return x.nombre; },
              formatTotal: function (v) { return C.num(v); } },
          ], rows, { total: true }),
          signatures: [{ role: 'Le Surveillant' },
            { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * TAUX DE PRÉSENCE PAR SERVICE
   * --------------------------------------------------------------------------
   * LE TAUX SE CALCULE SUR LES JOURS RENSEIGNÉS, pas sur le calendrier : un
   * service dont on n'a pointé que dix jours ne doit pas paraître absent les
   * vingt autres. Le nombre de jours observés figure à côté du taux — un
   * pourcentage sans son assiette ne veut rien dire.
   *
   * LE RETARD EST COMPTÉ À PART DE L'ABSENCE. Un agent en retard est présent :
   * le fondre dans l'absence gonflerait l'absentéisme et masquerait le vrai
   * problème, qui est l'indicateur du Surveillant — « 95 % des retards
   * constatés et notifiés ».
   * ======================================================================== */
  global.SIGH.screen('m10-stats-presence', {
    title: 'Taux de présence par service',
    description: 'Présences, retards et absences par service et par agent, sur la période choisie.',
    regle: 'Le taux est calculé sur les <strong>jours effectivement pointés</strong>, non sur le '
      + 'calendrier : un service dont on n’a pointé que dix jours ne doit pas paraître absent les vingt '
      + 'autres. Le <strong>retard est compté à part de l’absence</strong> — un agent en retard est '
      + 'présent, et les fondre gonflerait l’absentéisme en masquant le vrai sujet.',
    actions: function () {
      return [
        K.btn('Registre des présences', { icon: 'user-check',
          onclick: function () { global.SIGH.app.go('m10-presences'); } }),
      ];
    },
    render: function (root) {
      var dDu = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, -29)) });
      var dAu = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), dDu]),
        el('div', null, [el('label.label', { text: 'Au' }), dAu]),
        K.btn('Trente derniers jours', { size: 'sm', icon: 'calendar-range', onclick: function () {
          dDu.value = C.iso(C.addDays(AUJ, -29)); dAu.value = C.iso(AUJ); afficher();
        } }),
        K.btn('Imprimer l’état', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));
      [dDu, dAu].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function pointages() {
        return S.collection('presences').active().filter(function (x) {
          var d = String(x.date || '').slice(0, 10);
          if (dDu.value && d < dDu.value) return false;
          if (dAu.value && d > dAu.value) return false;
          return true;
        });
      }

      function parService() {
        var par = C.groupBy(pointages(), 'service');
        return C.sortBy(Object.keys(par).map(function (k) {
          var g = par[k];
          var presents = g.filter(function (x) { return x.etat === 'present'; }).length;
          var retards = g.filter(function (x) { return x.etat === 'retard'; }).length;
          var absents = g.filter(function (x) { return x.etat === 'absent'; }).length;
          var observes = g.length;
          return {
            id: k, service: k || 'Non renseigné',
            observes: observes,
            /* Le retard EST une présence : l'agent est là. */
            presents: presents, retards: retards, absents: absents,
            agents: Object.keys(C.groupBy(g, 'employeId')).length,
            taux: observes ? Math.round((presents + retards) / observes * 1000) / 10 : 0,
            tauxRetard: observes ? Math.round(retards / observes * 1000) / 10 : 0,
          };
        }), 'taux', 'desc');
      }

      function afficher() {
        C.clear(vue);
        var rows = parService();
        var tous = pointages();
        var presents = tous.filter(function (x) { return x.etat !== 'absent'; }).length;
        var retards = tous.filter(function (x) { return x.etat === 'retard'; }).length;

        vue.appendChild(K.note('<strong>' + C.num(tous.length) + ' journée(s) pointée(s)</strong> sur la '
          + 'période, pour ' + C.num(rows.length) + ' service(s). Le taux porte sur ces journées '
          + '<strong>effectivement renseignées</strong> — un pourcentage calculé sur le calendrier '
          + 'ferait passer pour absents des jours qu’on n’a simplement pas pointés.',
        { tone: 'info', icon: 'user-check' }));

        vue.appendChild(U.kpiGrid([
          { label: 'Taux de présence global',
            value: tous.length ? C.pct(presents / tous.length * 100) : '—',
            icon: 'user-check', tone: 'success',
            hint: C.num(tous.length) + ' journée(s) observée(s)' },
          { label: 'Retards', value: C.num(retards),
            icon: 'clock-alert', tone: retards ? 'warning' : 'success',
            hint: tous.length ? C.pct(retards / tous.length * 100) + ' des journées' : '' },
          { label: 'Absences', value: C.num(tous.length - presents),
            icon: 'user-x', tone: (tous.length - presents) ? 'danger' : 'success' },
          { label: 'Service le plus assidu', value: rows.length ? rows[0].service : '—',
            icon: 'award', tone: 'navy',
            hint: rows.length ? C.pct(rows[0].taux) : '' },
        ]));

        vue.appendChild(U.dataTable({
          rows: rows, exportName: 'taux-presence-service', pageSize: 15, searchable: true,
          columns: [
            { key: 'service', label: 'Service',
              render: function (x) { return el('span.font-medium', { text: x.service }); } },
            { key: 'agents', label: 'Agents', align: 'right' },
            { key: 'observes', label: 'Journées pointées', align: 'right' },
            { key: 'presents', label: 'Présents', align: 'right',
              render: function (x) { return el('span.text-success-700', { text: C.num(x.presents) }); } },
            { key: 'retards', label: 'Retards', align: 'right',
              render: function (x) {
                return x.retards ? el('span.text-warning-700', { text: C.num(x.retards) })
                  : el('span.text-slate-300', { text: '—' });
              } },
            { key: 'absents', label: 'Absents', align: 'right',
              render: function (x) {
                return x.absents ? el('span.text-danger-600', { text: C.num(x.absents) })
                  : el('span.text-slate-300', { text: '—' });
              } },
            { key: 'taux', label: 'Taux de présence', align: 'right',
              render: function (x) {
                var t = x.taux >= 95 ? 'success' : (x.taux >= 85 ? 'warning' : 'danger');
                return U.badge(C.pct(x.taux), t);
              } },
          ],
        }));

        if (rows.length) {
          vue.appendChild(K.charts([
            { title: 'Taux de présence par service',
              render: function () {
                return G.barres(rows.map(function (x) { return x.service; }),
                  [{ label: 'Taux de présence (%)', data: rows.map(function (x) { return x.taux; }),
                    color: G.TONES.vert }], { horizontal: true, height: 300 });
              } },
            { title: 'Présents, retards et absences par service',
              render: function () {
                return G.barres(rows.map(function (x) { return x.service; }), [
                  { label: 'Présents', data: rows.map(function (x) { return x.presents; }), color: G.TONES.vert },
                  { label: 'Retards', data: rows.map(function (x) { return x.retards; }), color: G.TONES.orange },
                  { label: 'Absents', data: rows.map(function (x) { return x.absents; }), color: G.TONES.rouge },
                ], { horizontal: true, height: 300 });
              } },
          ]));
        }
      }

      function imprimer() {
        var rows = parService();
        P.etat({
          titre: 'Taux de présence par service',
          sousTitre: 'Du ' + C.dateFR(dDu.value) + ' au ' + C.dateFR(dAu.value),
          cartouche: [
            ['Période', 'Du ' + C.dateFR(dDu.value) + ' au ' + C.dateFR(dAu.value)],
            ['Services observés', C.num(rows.length)],
            ['Journées pointées', C.num(C.sum(rows, 'observes'))],
            ['Retards constatés', C.num(C.sum(rows, 'retards'))],
          ],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Service', value: function (x) { return x.service; } },
              { label: 'Agents', align: 'right', value: function (x) { return C.num(x.agents); },
                somme: function (x) { return x.agents; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Journées pointées', align: 'right', value: function (x) { return C.num(x.observes); },
                somme: function (x) { return x.observes; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Présents', align: 'right', value: function (x) { return C.num(x.presents); },
                somme: function (x) { return x.presents; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Retards', align: 'right', value: function (x) { return C.num(x.retards); },
                somme: function (x) { return x.retards; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Absents', align: 'right', value: function (x) { return C.num(x.absents); },
                somme: function (x) { return x.absents; }, formatTotal: function (v) { return C.num(v); } },
              { label: 'Taux', align: 'right', value: function (x) { return C.pct(x.taux); } },
            ], rows, { total: true }),
            el('p.mt-3.text-\\[10px\\].italic', {
              text: 'Le taux est calculé sur les journées effectivement pointées. Le retard est compté '
                + 'comme une présence : l’agent est là.' }),
          ]),
          signatures: [{ role: 'Le Surveillant' },
            { role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * BADGES DU PERSONNEL (vague 54)
   * --------------------------------------------------------------------------
   * Le badge est une PIÈCE IMPRIMÉE rattachée à un agent. Sa place est en M10
   * et nulle part ailleurs : l'agent, sa photo, sa fonction et son service y
   * vivent déjà, et un module séparé aurait créé une seconde vérité sur
   * l'identité du personnel — celle du badge finirait par diverger de celle
   * du dossier RH au premier changement de service.
   *
   * DEUX COLLECTIONS, ET PAS UNE :
   *   `badges`       — une fiche par badge ÉMIS, datée, avec son état ;
   *   `modelesBadge` — les gabarits (format, orientation, zones, mentions).
   * Les fondre obligerait à recopier le gabarit sur chaque carte, et changer
   * une mention du verso demanderait de reprendre tous les badges émis.
   *
   * UN BADGE SE RETIRE, IL NE SE SUPPRIME PAS (RG-14, et davantage) : le
   * badge perdu est précisément la fiche qu'on ressort le jour où quelqu'un
   * se présente avec. L'état et le motif sont portés sur la fiche ; elle
   * reste au registre, dans un onglet qui la nomme.
   * ======================================================================== */
  var ETATS_BADGE = [
    { id: 'a_editer', label: 'À éditer', tone: 'warning', actif: true },
    { id: 'edite', label: 'Édité', tone: 'info', actif: true },
    { id: 'remis', label: 'Remis à l’agent', tone: 'success', actif: true },
    { id: 'perdu', label: 'Perdu / volé', tone: 'danger', actif: false },
    { id: 'retire', label: 'Retiré', tone: 'neutral', actif: false },
  ];
  var MOTIFS_RETRAIT = ['Perte', 'Vol', 'Détérioration', 'Départ de l’agent',
    'Réédition — remplacement', 'Erreur de saisie'];

  /* LES QUATRE DÉCISIONS QUI APPARTIENNENT À LA DIRECTION. Elles ne sont PAS
     inventées : elles portent une valeur d'attente explicitement marquée, et
     les écrans le disent. Les fixer en douce aurait produit des badges dont
     personne ne saurait dire d'où sort la durée de validité. */
  var BADGE_A_VALIDER = {
    duree: {
      libelle: 'Durée de validité d’un badge',
      valeur: 24,
      unite: 'mois',
      motif: 'Valeur d’attente — aucun document de cadrage ne fixe de durée. '
        + 'Deux ans est l’usage courant ; la Direction peut retenir la durée du contrat, '
        + 'ou une validité sans terme pour les titulaires.',
    },
    serie: {
      libelle: 'Format du numéro de série',
      valeur: 'BDG-NNNNN-AAAA',
      motif: 'Proposé par analogie avec les pièces certifiantes, dont la série repart à 1 '
        + 'chaque année comme le registre papier. À confirmer : la clinique tient peut-être '
        + 'déjà une numérotation de badges qu’il faudrait reprendre.',
    },
    verso: {
      libelle: 'Mentions portées au verso',
      valeur: 'Restitution, perte, propriété de la clinique',
      motif: 'Rédigées faute de texte remis. Elles engagent la clinique vis-à-vis du porteur : '
        + 'c’est à la Direction de les arrêter.',
    },
    pointage: {
      libelle: 'Le badge sert-il de support de POINTAGE ?',
      valeur: 'Non — décision non prise',
      motif: 'S’il pointe, il se relie au registre des présences (M10) et la conception change : '
        + 'lecteur à l’entrée, horodatage, traitement des oublis de badge. Tant que ce n’est pas '
        + 'tranché, le badge IDENTIFIE seulement.',
    },
  };

  function colBadges() {
    return S.collection('badges', { module: 'M10', entite: 'badge', prefix: 'BDG' });
  }
  function colModelesBadge() {
    return S.collection('modelesBadge', { module: 'M10', entite: 'modèle de badge', prefix: 'MDB' });
  }
  function etatBadge(id) {
    return ETATS_BADGE.filter(function (e) { return e.id === id; })[0]
      || { id: id, label: id, tone: 'neutral', actif: true };
  }

  /**
   * Le gabarit tel que l'impression l'attend. Le magasin garde les zones sous
   * forme de LISTE (c'est ce que rend un champ à cases à cocher) et les
   * mentions sous forme de texte ; l'impression veut un objet et un tableau.
   * La conversion vit ICI, en un seul point : la faire à chaque appel aurait
   * donné deux badges différents selon l'écran qui les imprime.
   */
  function modeleNormalise(m) {
    var mod = m || modeleParDefaut();
    var zones = {};
    ['photo', 'nom', 'fonction', 'service', 'qr'].forEach(function (z) {
      zones[z] = !mod.zones || mod.zones.indexOf(z) !== -1;
    });
    return {
      id: mod.id, libelle: mod.libelle,
      orientation: mod.orientation || 'paysage',
      zones: zones,
      mentionsVerso: String(mod.mentionsVerso || '').split('\n')
        .map(function (x) { return x.trim(); }).filter(Boolean),
    };
  }
  function modeleParDefaut() {
    var tous = colModelesBadge().active();
    return tous.filter(function (m) { return m.defaut; })[0] || tous[0] || null;
  }
  function modeleDe(badge) {
    return modeleNormalise(colModelesBadge().get(badge.modeleId) || modeleParDefaut());
  }

  /** La date d'expiration déduite de la durée d'attente — jamais saisie deux fois. */
  function expirationDepuis(dateEmission) {
    var d = C.toDate(dateEmission);
    var x = new Date(d.getTime());
    x.setMonth(x.getMonth() + BADGE_A_VALIDER.duree.valeur);
    return C.iso(x);
  }
  function expire(b, aLaDate) {
    return !!(b.expireLe && b.expireLe < C.iso(aLaDate || AUJ));
  }

  /**
   * L'état d'un badge présenté au contrôle, en TROIS réponses distinctes.
   * « Inconnu » n'est pas « retiré » : le premier signale un badge qui ne
   * vient pas d'ici, le second un badge que la clinique a repris. Les
   * confondre ferait traiter un faux badge comme une simple péremption.
   */
  function verdictBadge(b, aLaDate) {
    if (!b) return { code: 'inconnu', label: 'BADGE INCONNU', tone: 'danger',
      message: 'Aucun badge ne porte ce numéro. Ce n’est pas un badge de la clinique, '
        + 'ou il a été émis avant la mise en service du registre.' };
    if (!etatBadge(b.etat).actif) {
      return { code: 'retire', label: 'BADGE RETIRÉ', tone: 'danger',
        message: 'Badge ' + etatBadge(b.etat).label.toLowerCase()
          + (b.motifRetrait ? ' — ' + b.motifRetrait : '')
          + (b.retireLe ? ', le ' + C.dateFR(b.retireLe) : '') + '. Il ne vaut plus identification.' };
    }
    if (expire(b, aLaDate)) {
      return { code: 'expire', label: 'BADGE EXPIRÉ', tone: 'warning',
        message: 'Validité échue le ' + C.dateFR(b.expireLe) + '. L’agent est connu du registre : '
          + 'le badge est à rééditer, ce n’est pas un refus d’identité.' };
    }
    if (b.etat === 'a_editer') {
      return { code: 'non_remis', label: 'BADGE NON REMIS', tone: 'warning',
        message: 'Le badge est enregistré mais n’a pas encore été édité ni remis à l’agent : '
          + 'une carte qui circule alors qu’elle n’a pas été remise doit être signalée à la RH.' };
    }
    return { code: 'valide', label: 'BADGE VALIDE', tone: 'success',
      message: 'Valable jusqu’au ' + (b.expireLe ? C.dateFR(b.expireLe) : '—') + '.' };
  }

  /* --------------------------------------------------------------------------
   * Amorçage — trois écrans de M10 lisent ces collections, et une page ne
   * charge que le module de son écran : l'amorçage vit donc au module, appelé
   * par chacun des trois. Le modèle amorcé est une PROPOSITION.
   * ----------------------------------------------------------------------- */
  function amorcerBadges() {
    var mods = colModelesBadge();
    if (!mods.all().length) {
      mods.all().push({
        id: 'MDB001', statut: 'actif', defaut: true,
        libelle: 'Badge agent — CR80 paysage',
        format: 'CR80 (85,6 × 54 mm)', orientation: 'paysage',
        zones: ['photo', 'nom', 'fonction', 'service', 'qr'],
        mentionsVerso: 'Ce badge est la propriété de la Clinique NASSIERA TOO SARL.\n'
          + 'Il doit être porté visiblement pendant le service.\n'
          + 'En cas de perte, prévenir immédiatement la Direction Administrative.\n'
          + 'Toute perte est à signaler dans les 24 heures.\n'
          + 'À restituer au départ de l’agent.',
        aValider: true,
        source: 'Proposition — aucun document de cadrage ne décrit le badge de la clinique. '
          + 'Format CR80 retenu : c’est celui des imprimantes à cartes et des porte-badges du commerce.',
      });
      S.save();
    }

    var col = colBadges();
    if (col.all().length) return;
    var rnd = C.seeded(2609);
    var agents = C.sortBy(personnel(), 'matricule').slice(0, 14);
    var n = 0;
    agents.forEach(function (a, i) {
      n++;
      var emission = C.iso(C.addDays(AUJ, -C.between(rnd, 30, 400)));
      /* Un état par tiers d'effectif, pour que les trois onglets aient
         quelque chose à montrer dès la première ouverture. */
      var etat = i % 7 === 3 ? 'edite' : (i % 11 === 5 ? 'a_editer' : 'remis');
      col.all().push({
        id: 'BDG' + C.pad(n, 4), statut: 'actif',
        numero: 'BDG-' + C.pad(n, 5) + '-' + String(C.toDate(emission).getFullYear()),
        personnelId: a.id, matricule: a.matricule, agent: a.nomComplet,
        poste: a.poste, service: a.service,
        modeleId: 'MDB001', photo: null,
        emisLe: emission, expireLe: expirationDepuis(emission),
        etat: etat, remisLe: etat === 'remis' ? emission : null,
        motifRetrait: null, retireLe: null,
        emisPar: 'Jeu de démonstration',
      });
    });
    S.save();
  }

  /** Les vérifications de badge sont journalisées (RG-12) — voir m14-audit. */
  function journaliserVerification(saisie, b, verdict) {
    S.journaliserAcces({
      action: 'Vérification de badge',
      module: 'M10', entite: 'Badge',
      reference: b ? b.numero : String(saisie).slice(0, 40),
      cible: b ? b.agent : null,
      ecran: 'm10-badges-verification',
      motif: verdict.label,
      trouve: !!b,
    });
  }

  /* ==========================================================================
   * REGISTRE DES BADGES
   * ======================================================================== */
  global.SIGH.screen('m10-badges', {
    title: 'Badges du personnel',
    description: 'Un badge par agent : émission, remise, validité, retrait — et le code de contrôle qui permet de le vérifier.',
    regle: 'Un badge se <strong>RETIRE</strong>, il ne se supprime jamais : la fiche d’un badge perdu '
      + 'est précisément celle qu’on ressort le jour où quelqu’un se présente avec. Le code QR ne porte '
      + '<strong>que le matricule et le numéro de série</strong> — ni nom, ni fonction : un badge se '
      + 'photographie dans un couloir, et la vérification doit passer par le logiciel, seul à savoir si '
      + 'le badge est encore valide.',
    render: function (root) {
      amorcerBadges();
      var host = el('div.space-y-4');
      root.appendChild(host);
      var D_ = K.droits();
      afficher();
      return null;

      function afficher() {
        var tous = colBadges().active();
        C.clear(host);

        var actifs = tous.filter(function (b) { return etatBadge(b.etat).actif; });
        var retires = tous.filter(function (b) { return !etatBadge(b.etat).actif; });
        var expirant = actifs.filter(function (b) {
          return b.expireLe && C.daysBetween(AUJ, b.expireLe) <= 60;
        });
        var sansBadge = personnel().filter(function (a) {
          return !actifs.some(function (b) { return b.personnelId === a.id; });
        });

        host.appendChild(U.kpiGrid([
          { label: 'Badges en cours', value: C.num(actifs.length), icon: 'id-card', tone: 'navy' },
          { label: 'Remis à l’agent', value: C.num(actifs.filter(function (b) { return b.etat === 'remis'; }).length),
            icon: 'hand-coins', tone: 'success' },
          { label: 'À éditer ou à remettre', value: C.num(actifs.filter(function (b) { return b.etat !== 'remis'; }).length),
            icon: 'printer', tone: 'warning' },
          { label: 'Expirent sous 60 jours', value: C.num(expirant.length), icon: 'calendar-clock',
            tone: expirant.length ? 'warning' : 'neutral' },
          { label: 'Retirés (perte, départ)', value: C.num(retires.length), icon: 'archive', tone: 'neutral' },
          { label: 'Agents sans badge', value: C.num(sansBadge.length), icon: 'user-x',
            tone: sansBadge.length ? 'danger' : 'success', hint: 'Effectif rapproché du registre' },
        ]));

        host.appendChild(U.tabs([
          { id: 'badges', label: 'Badges en cours (' + actifs.length + ')',
            render: function () { return tableau(actifs, false); } },
          { id: 'retires', label: 'Retirés (' + retires.length + ')',
            render: function () { return tableau(retires, true); } },
          { id: 'sans', label: 'Agents sans badge (' + sansBadge.length + ')',
            render: function () { return tableauSansBadge(sansBadge); } },
          { id: 'decisions', label: 'À décider par la Direction',
            render: function () { return blocDecisions(); } },
        ]));
        U.icons(host);
      }

      function tableau(rows, retire) {
        return U.dataTable({
          title: retire ? 'Badges retirés — conservés, jamais effacés' : 'Badges en cours de validité',
          rows: C.sortBy(rows, 'numero').reverse(), pageSize: 12, exportName: 'badges',
          emptyMessage: retire ? 'Aucun badge retiré.' : 'Aucun badge émis.',
          filters: [{ name: 'etat', label: 'État', options: ETATS_BADGE
            .filter(function (e) { return e.actif !== retire; })
            .map(function (e) { return { value: e.id, label: e.label }; }) }],
          actions: retire ? null : [K.commande('Émettre un badge', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { emettre(null); },
          })].filter(Boolean),
          columns: [
            { key: 'numero', label: 'N° de série', render: function (b) {
              return el('div.min-w-0', null, [
                el('p.font-mono.text-sm.font-medium.text-slate-800', { text: b.numero }),
                el('p.text-xs.text-slate-400', { text: 'Émis le ' + C.dateFR(b.emisLe) }),
              ]);
            } },
            { key: 'agent', label: 'Agent', render: function (b) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: b.agent }),
                el('p.truncate.text-xs.text-slate-500', { text: (b.poste || '') + ' · ' + (b.service || '') }),
              ]);
            } },
            { key: 'matricule', label: 'Matricule', value: function (b) { return b.matricule; } },
            { key: 'expireLe', label: 'Validité', render: function (b) {
              if (!b.expireLe) return U.badge('non fixée', 'neutral');
              return expire(b) ? U.badge('Expiré le ' + C.dateFR(b.expireLe), 'danger')
                : el('span.text-sm.text-slate-700', { text: 'jusqu’au ' + C.dateFR(b.expireLe) });
            } },
            { key: 'etat', label: 'État', render: function (b) {
              var e = etatBadge(b.etat);
              return el('div', null, [
                U.badge(e.label, e.tone),
                b.motifRetrait ? el('p.mt-0\\.5.text-xs.text-slate-400', { text: b.motifRetrait }) : null,
              ].filter(Boolean));
            } },
          ],
          rowActions: function (b) {
            var actes = [K.iconBtn('eye', 'Consulter le badge', function () { fiche(b); })];
            if (!retire) {
              actes.push(K.iconBtn('printer', 'Imprimer la carte', function () { imprimer(b); }));
              var remis = b.etat !== 'remis' ? K.commandeIcone('hand-coins', 'Marquer remis à l’agent',
                function () { marquerRemis(b); }) : null;
              if (remis) actes.push(remis);
              var ret = K.commandeIcone('ban', 'Retirer le badge', function () { retirer(b); },
                { droit: 'annuler', variant: 'ghost' });
              if (ret) actes.push(ret);
            } else {
              var reed = K.commandeIcone('rotate-ccw', 'Émettre un remplacement',
                function () { emettre(b.personnelId); });
              if (reed) actes.push(reed);
            }
            return actes;
          },
        });
      }

      function tableauSansBadge(agents) {
        return U.dataTable({
          title: 'Agents sans badge en cours', rows: agents, pageSize: 10, exportName: 'agents-sans-badge',
          emptyMessage: 'Tout l’effectif porte un badge.',
          columns: [
            { key: 'matricule', label: 'Matricule' },
            { key: 'nomComplet', label: 'Agent' },
            { key: 'poste', label: 'Poste' },
            { key: 'service', label: 'Service' },
          ],
          rowActions: function (a) {
            var b = K.commande('Émettre', { size: 'sm', variant: 'primary', icon: 'id-card',
              onclick: function () { emettre(a.id); } });
            return [b].filter(Boolean);
          },
        });
      }

      function blocDecisions() {
        var bloc = el('div.space-y-3');
        bloc.appendChild(K.note('Quatre points ne sont fixés par <strong>aucun document de cadrage</strong>. '
          + 'Les écrans fonctionnent avec des valeurs d’attente <strong>marquées comme telles</strong> : '
          + 'les inventer sans le dire aurait produit des badges dont personne ne saurait justifier la durée.',
        { tone: 'warning', icon: 'help-circle' }));
        bloc.appendChild(U.card('En attente d’un arbitrage de la Direction',
          K.miniTable(['Point', 'Valeur d’attente', 'Pourquoi elle n’est pas arrêtée'],
            Object.keys(BADGE_A_VALIDER).map(function (k) {
              var d = BADGE_A_VALIDER[k];
              return [d.libelle, d.valeur + (d.unite ? ' ' + d.unite : ''), d.motif];
            }))));
        return bloc;
      }

      /* --- Émission ------------------------------------------------------- */
      function emettre(personnelId) {
        var modeles = colModelesBadge().active();
        if (!modeles.length) {
          U.toast('Aucun modèle de badge — en créer un aux « Modèles de badge ».', { type: 'error' });
          return;
        }
        var photo = { donnees: null };
        var champPhoto = el('input.input', {
          type: 'file', accept: '.png,.jpg,.jpeg,image/png,image/jpeg',
          'aria-label': 'Photographie de l’agent',
        });
        var apercu = el('div.mt-2');
        champPhoto.addEventListener('change', function () {
          var file = champPhoto.files && champPhoto.files[0];
          C.clear(apercu);
          if (!file) { photo.donnees = null; return; }
          if (file.size > 400 * 1024) {
            apercu.appendChild(K.note('Photographie de ' + Math.round(file.size / 1024) + ' Ko — '
              + 'au-delà de 400 Ko, le stockage local sature vite : une photo d’identité de '
              + '300 × 400 pixels suffit largement à l’impression.', { tone: 'warning', icon: 'alert-triangle' }));
          }
          var lecteur = new FileReader();
          lecteur.onload = function () {
            photo.donnees = lecteur.result;
            apercu.appendChild(el('img.mt-2.h-28.rounded-lg.border.border-slate-200.object-cover',
              { src: photo.donnees, alt: 'Aperçu de la photographie' }));
          };
          lecteur.readAsDataURL(file);
        });

        var f = U.form([
          { name: 'personnelId', label: 'Agent', type: 'select', required: true, col: 'full',
            options: optionsEmployes() },
          { name: 'modeleId', label: 'Modèle de badge', type: 'select', required: true,
            options: modeles.map(function (m) { return { value: m.id, label: m.libelle }; }) },
          { name: 'emisLe', label: 'Date d’émission', type: 'date', required: true },
          { name: 'expireLe', label: 'Valable jusqu’au', type: 'date', required: true,
            hint: 'Proposé à ' + BADGE_A_VALIDER.duree.valeur + ' mois — durée d’attente, à arrêter par la Direction.' },
          { name: 'etat', label: 'État à l’émission', type: 'select', required: true,
            options: ETATS_BADGE.filter(function (e) { return e.actif; })
              .map(function (e) { return { value: e.id, label: e.label }; }) },
        ], {
          personnelId: personnelId || '',
          modeleId: (modeleParDefaut() || {}).id,
          emisLe: C.iso(AUJ), expireLe: expirationDepuis(AUJ), etat: 'a_editer',
        });

        var corps = el('div.space-y-3', null, [
          f,
          el('div', null, [el('label.label', { text: 'Photographie de l’agent — PNG ou JPEG' }), champPhoto, apercu]),
          K.note('Le code QR portera <strong>le matricule et le numéro de série, rien d’autre</strong>. '
            + 'Un QR qui porterait le nom en clair remplacerait un contrôle par une simple lecture.',
          { tone: 'info', icon: 'qr-code' }),
        ]);

        var m = U.modal({
          title: personnelId ? 'Émettre un badge' : 'Émettre un badge',
          subtitle: 'Le numéro de série est attribué automatiquement et ne se modifie pas.',
          size: 'lg', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Émettre le badge', {
              variant: 'primary', icon: 'id-card',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var a = S.collection('personnel').get(v.personnelId);
                if (!a) { U.toast('Agent introuvable.', { type: 'error' }); return; }
                /* UN SEUL BADGE EN COURS PAR AGENT. Deux cartes valides pour
                   la même personne, c'est une carte qui circule sans que
                   personne ne la réclame : le remplacement passe par le
                   retrait de l'ancienne, et on le DIT plutôt que de refuser
                   sans expliquer. */
                var deja = colBadges().active().filter(function (b) {
                  return b.personnelId === a.id && etatBadge(b.etat).actif;
                })[0];
                if (deja) {
                  U.toast('L’agent porte déjà le badge ' + deja.numero + ' — le retirer d’abord.', {
                    type: 'error',
                    detail: 'Deux badges valides pour un même agent laisseraient une carte circuler sans titulaire.',
                  });
                  return;
                }
                var res = colBadges().insert({
                  numero: global.SIGH.parcours.numeroBadge(v.emisLe),
                  personnelId: a.id, matricule: a.matricule, agent: a.nomComplet,
                  poste: a.poste, service: a.service,
                  modeleId: v.modeleId, photo: photo.donnees || null,
                  emisLe: v.emisLe, expireLe: v.expireLe, etat: v.etat,
                  remisLe: v.etat === 'remis' ? v.emisLe : null,
                  motifRetrait: null, retireLe: null,
                  emisPar: S.currentUser(),
                });
                m.close(); afficher();
                U.toast('Badge ' + res.record.numero + ' émis.', {
                  type: 'success', detail: a.nomComplet,
                  undo: function () { colBadges().archive(res.record.id); afficher(); },
                  undoMessage: 'Émission annulée.',
                });
              },
            }),
          ],
        });
        U.icons(corps);
      }

      function marquerRemis(b) {
        U.confirm({
          title: 'Marquer le badge remis à l’agent ?',
          message: 'Le badge <strong>' + b.numero + '</strong> sera enregistré comme remis à '
            + b.agent + ' le ' + C.dateFR(AUJ) + '.',
          confirmLabel: 'Remis',
        }).then(function (rep) {
          if (!rep) return;
          var res = colBadges().update(b.id, { etat: 'remis', remisLe: C.iso(AUJ) });
          afficher();
          U.toast('Badge remis.', { type: 'success',
            undo: function () { res.undo(); afficher(); } });
        });
      }

      function retirer(b) {
        var f = U.form([
          { name: 'motifRetrait', label: 'Motif du retrait', type: 'select', required: true, col: 'full',
            options: MOTIFS_RETRAIT.map(function (x) { return { value: x, label: x }; }) },
          { name: 'retireLe', label: 'Date', type: 'date', required: true },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ], { retireLe: C.iso(AUJ) });
        var m = U.modal({
          title: 'Retirer le badge ' + b.numero,
          subtitle: 'Le badge reste au registre : c’est la fiche qu’on ressort si quelqu’un se présente avec.',
          size: 'md', body: el('div.space-y-3', null, [
            f,
            K.note('Un badge <strong>se retire, il ne se supprime pas</strong> (RG-14). Il basculera à '
              + 'l’onglet « Retirés » et sera refusé à la vérification, en nommant le motif.',
            { tone: 'warning', icon: 'ban' }),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Retirer le badge', {
              variant: 'danger', icon: 'ban',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var etat = /perte|vol/i.test(v.motifRetrait) ? 'perdu' : 'retire';
                var res = colBadges().update(b.id, {
                  etat: etat, motifRetrait: v.motifRetrait, retireLe: v.retireLe,
                  observationRetrait: v.observation || null, retirePar: S.currentUser(),
                });
                m.close(); afficher();
                U.toast('Badge ' + b.numero + ' retiré.', {
                  type: 'success', detail: v.motifRetrait,
                  undo: function () { res.undo(); afficher(); },
                  undoMessage: 'Retrait annulé — le badge redevient valide.',
                });
              },
            }),
          ],
        });
      }

      function fiche(b) {
        var mod = modeleDe(b);
        var v = verdictBadge(b);
        var corps = el('div.space-y-3');
        corps.appendChild(U.descList([
          ['N° de série', b.numero],
          ['Agent', b.agent], ['Matricule', b.matricule],
          ['Poste', b.poste || '—'], ['Service', b.service || '—'],
          ['Émis le', C.dateFR(b.emisLe) + ' par ' + (b.emisPar || '—')],
          ['Valable jusqu’au', b.expireLe ? C.dateFR(b.expireLe) : '—'],
          ['Remis le', b.remisLe ? C.dateFR(b.remisLe) : 'non remis'],
          ['Modèle', mod.libelle || '—'],
          ['État', etatBadge(b.etat).label],
          ['Motif du retrait', b.motifRetrait || '—'],
        ]));
        corps.appendChild(U.card('Contrôle', el('div.flex.items-center.gap-4', null, [
          C.qr(global.SIGH.parcours.badgeQR(b), { taille: 120, marge: 2 }),
          el('div.min-w-0', null, [
            U.badge(v.label, v.tone),
            el('p.mt-1.text-sm.text-slate-600', { text: v.message }),
            el('p.mt-2.font-mono.text-xs.text-slate-400', { text: global.SIGH.parcours.badgeQR(b) }),
            el('p.text-xs.text-slate-400', { text: 'Le code ne porte que le matricule et le numéro de série.' }),
          ]),
        ])));
        U.drawer({
          title: b.numero, subtitle: b.agent,
          body: corps, width: 'max-w-2xl',
          footer: [K.btn('Imprimer la carte', { variant: 'primary', icon: 'printer',
            onclick: function () { imprimer(b); } })],
        });
      }

      function imprimer(b) {
        P.badge({
          badge: b, modele: modeleDe(b),
          agent: S.collection('personnel').get(b.personnelId),
        });
      }
    },
  });

  /* ==========================================================================
   * MODÈLES DE BADGE — les gabarits
   * ======================================================================== */
  global.SIGH.screen('m10-badges-modeles', {
    title: 'Modèles de badge',
    description: 'Les gabarits : format, orientation, zones imprimées et mentions du verso.',
    regle: 'Le badge ne porte <strong>aucune couleur en dur</strong> : il suit la charte de '
      + 'l’établissement, si bien qu’une autre clinique n’a rien à retoucher. L’en-tête officiel ne '
      + 's’y applique <strong>pas</strong> tel quel — un badge n’est pas un état administratif : logo, '
      + 'dénomination et devise, mais ni IFU ni RCCM, qui sont des mentions fiscales. Les mentions du '
      + 'verso sont une <strong>proposition à valider</strong> : elles engagent la clinique envers le porteur.',
    render: function (root) {
      amorcerBadges();
      return K.crud({
        collection: 'modelesBadge', module: 'M10',
        entite: 'modèle de badge', entiteP: 'modèles de badge',
        pageSize: 8, defaultSort: 'libelle',
        columns: [
          { key: 'libelle', label: 'Modèle' },
          { key: 'format', label: 'Format' },
          { key: 'orientation', label: 'Orientation' },
          { key: 'zones', label: 'Zones imprimées', render: function (m) {
            return el('p.text-xs.text-slate-500', { text: (m.zones || []).join(' · ') || '—' });
          } },
          { key: 'defaut', label: 'Par défaut', render: function (m) {
            return m.defaut ? U.badge('Modèle par défaut', 'success') : el('span.text-slate-300', { text: '—' });
          } },
          { key: 'aValider', label: 'Statut', render: function (m) {
            return m.aValider ? U.badge('Proposition à valider', 'warning') : U.badge('Arrêté', 'success');
          } },
        ],
        fields: [
          { name: 'libelle', label: 'Intitulé du modèle', required: true, col: 'full' },
          { name: 'format', label: 'Format de carte', type: 'select', required: true,
            options: [{ value: 'CR80 (85,6 × 54 mm)', label: 'CR80 — 85,6 × 54 mm (standard)' }],
            hint: 'Le format des imprimantes à cartes et des porte-badges du commerce.' },
          { name: 'orientation', label: 'Orientation', type: 'select', required: true,
            options: [{ value: 'paysage', label: 'Paysage' }, { value: 'portrait', label: 'Portrait' }] },
          { name: 'zones', label: 'Zones imprimées au recto', type: 'multiselect', required: true, col: 'full',
            options: [
              { value: 'photo', label: 'Photographie' }, { value: 'nom', label: 'Nom de l’agent' },
              { value: 'fonction', label: 'Fonction / poste' }, { value: 'service', label: 'Service' },
              { value: 'qr', label: 'Code QR de contrôle' },
            ] },
          { name: 'mentionsVerso', label: 'Mentions du verso — une par ligne', type: 'textarea', rows: 5, col: 'full' },
          { name: 'defaut', label: 'Modèle proposé par défaut', type: 'checkbox' },
        ],
        onCreate: function () {
          return { format: 'CR80 (85,6 × 54 mm)', orientation: 'paysage',
            zones: ['photo', 'nom', 'fonction', 'service', 'qr'], aValider: true };
        },
        detail: function (m) {
          var norm = modeleNormalise(m);
          var faux = {
            numero: 'BDG-00000-' + AUJ.getFullYear(), matricule: '00',
            agent: 'SPÉCIMEN — Aperçu', poste: 'Fonction de l’agent', service: 'Service',
            expireLe: expirationDepuis(AUJ), photo: null,
          };
          return el('div.space-y-3', null, [
            K.note('Aperçu à l’échelle : le badge est composé en <strong>millimètres</strong>, pas en '
              + 'pixels — c’est ce qui permet de l’imprimer tel quel sur une carte.', { tone: 'info' }),
            el('div.flex.flex-wrap.gap-4', null, [
              P.carteBadge({ badge: faux, agent: null, modele: norm }, 'recto'),
              P.carteBadge({ badge: faux, agent: null, modele: norm }, 'verso'),
            ]),
            U.descList([
              ['Mentions du verso', norm.mentionsVerso.length + ' ligne(s)'],
              ['Source', m.source || '—'],
            ]),
          ]);
        },
      })(root);
    },
  });

  /* ==========================================================================
   * PLANCHE D'IMPRESSION
   * --------------------------------------------------------------------------
   * Pour les cliniques SANS imprimante à cartes : dix badges sur une feuille
   * A4, avec des repères de découpe. Le pied normalisé (date, utilisateur,
   * identifiant) va sur la PLANCHE et non sur les cartes — un badge n'a pas à
   * porter l'heure de son impression.
   * ======================================================================== */
  global.SIGH.screen('m10-badges-impression', {
    title: 'Planche d’impression des badges',
    description: 'Sélection multiple puis pose sur feuille A4 avec repères de découpe, ou impression carte par carte.',
    regle: 'Deux voies, selon le matériel : l’<strong>imprimante à cartes</strong> reçoit une carte à la '
      + 'fois, au format CR80 ; la <strong>planche A4</strong> en pose dix par feuille, à découper. '
      + 'Un badge retiré n’est jamais proposé à l’impression — réimprimer une carte retirée la remettrait '
      + 'en circulation.',
    render: function (root) {
      amorcerBadges();
      var host = el('div.space-y-4');
      root.appendChild(host);
      var rows = colBadges().active().filter(function (b) { return etatBadge(b.etat).actif; });

      host.appendChild(K.note('La planche pose <strong>dix badges par feuille</strong> (2 × 5 au format '
        + 'CR80). Sélectionner davantage de cartes engendre les feuilles nécessaires, dans l’ordre du '
        + 'tableau.', { tone: 'info', icon: 'printer' }));

      host.appendChild(U.dataTable({
        title: 'Badges imprimables', rows: C.sortBy(rows, 'agent'), pageSize: 15,
        selectable: true, exportName: 'badges-a-imprimer',
        emptyMessage: 'Aucun badge en cours — en émettre au registre des badges.',
        filters: [
          { name: 'etat', label: 'État', options: ETATS_BADGE.filter(function (e) { return e.actif; })
            .map(function (e) { return { value: e.id, label: e.label }; }) },
          { name: 'service', label: 'Service', options: C.sortBy(Object.keys(C.groupBy(rows, 'service'))
            .filter(Boolean).map(function (s) { return { value: s, label: s }; }), 'label') },
        ],
        bulkActions: function (getSelected) {
          var b = K.commande('Imprimer la planche', {
            variant: 'primary', size: 'sm', icon: 'printer',
            onclick: function () { planche(getSelected()); },
          });
          return b ? [b] : [];
        },
        columns: [
          { key: 'numero', label: 'N° de série' },
          { key: 'agent', label: 'Agent' },
          { key: 'service', label: 'Service' },
          { key: 'etat', label: 'État', render: function (b) {
            var e = etatBadge(b.etat); return U.badge(e.label, e.tone);
          } },
          { key: 'photo', label: 'Photographie', render: function (b) {
            return b.photo ? U.badge('Oui', 'success') : U.badge('À coller', 'warning');
          } },
        ],
        rowActions: function (b) {
          return [K.iconBtn('printer', 'Imprimer la carte seule', function () {
            P.badge({ badge: b, modele: modeleDe(b), agent: S.collection('personnel').get(b.personnelId) });
          })];
        },
      }));

      host.appendChild(K.source('Registre des badges — seuls les badges en cours de validité sont proposés.'));
      U.icons(host);
      return null;

      function planche(selection) {
        if (!selection || !selection.length) {
          U.toast('Sélectionner au moins un badge.', { type: 'warning' });
          return;
        }
        var modele = modeleNormalise(colModelesBadge().get(selection[0].modeleId) || modeleParDefaut());
        for (var i = 0; i < selection.length; i += 10) {
          P.planche({
            modele: modele,
            badges: selection.slice(i, i + 10).map(function (b) {
              return { badge: b, agent: S.collection('personnel').get(b.personnelId) };
            }),
          });
        }
      }
    },
  });

  /* ==========================================================================
   * VÉRIFIER UN BADGE
   * --------------------------------------------------------------------------
   * On saisit ou l'on scanne le numéro ; le logiciel répond VALIDE, EXPIRÉ,
   * RETIRÉ ou INCONNU, montre la photo et la fonction, et JOURNALISE la
   * vérification (RG-12). C'est ce contrôle qui donne sa valeur au badge :
   * sans lui, une carte plastifiée n'atteste rien.
   * ======================================================================== */
  global.SIGH.screen('m10-badges-verification', {
    title: 'Vérifier un badge',
    description: 'Le badge présenté est-il valide ? Réponse immédiate, avec la photo et la fonction — et la vérification est journalisée.',
    regle: 'Le code QR ne portant <strong>que le matricule et le numéro de série</strong>, la réponse '
      + 'vient du <strong>logiciel</strong> et non de la carte : lui seul sait si le badge a été retiré. '
      + 'Chaque vérification est <strong>journalisée</strong> (RG-12) et se retrouve au journal d’audit.',
    render: function (root) {
      amorcerBadges();
      var host = el('div.space-y-4');
      root.appendChild(host);

      var saisie = el('input.input.text-lg.font-mono', {
        type: 'text', placeholder: 'BDG-00007-2026 — ou coller le contenu du QR',
        'aria-label': 'Numéro de série ou contenu du code QR',
      });
      var reponse = el('div');
      var bouton = K.btn('Vérifier', { variant: 'primary', icon: 'scan-face', onclick: verifier });
      saisie.addEventListener('keydown', function (e) { if (e.key === 'Enter') verifier(); });

      host.appendChild(U.card('Badge présenté', el('div.space-y-3', null, [
        el('div.flex.flex-wrap.items-end.gap-2', null, [
          el('div.min-w-\\[18rem\\].flex-1', null, [
            el('label.label', { text: 'Numéro de série ou code scanné' }), saisie,
          ]),
          bouton,
        ]),
        K.note('La <strong>saisie manuelle est acceptée</strong> autant que le scan : refuser le numéro '
          + 'à la main rendrait le contrôle impossible le jour où le QR est abîmé — c’est-à-dire le jour '
          + 'où il sert le plus.', { tone: 'info', icon: 'keyboard' }),
        reponse,
      ])));

      var recentes = colBadges().active().filter(function (b) { return !etatBadge(b.etat).actif; });
      host.appendChild(U.card('Badges retirés — à refuser à l’entrée',
        recentes.length
          ? K.miniTable(['N° de série', 'Agent', 'Motif', 'Depuis le'],
            C.sortBy(recentes, 'retireLe').reverse().slice(0, 10).map(function (b) {
              return [b.numero, b.agent, b.motifRetrait || '—', b.retireLe ? C.dateFR(b.retireLe) : '—'];
            }))
          : U.empty('Aucun badge retiré.', { icon: 'check-circle-2' })));

      U.icons(host);
      return null;

      function verifier() {
        var texte = String(saisie.value || '').trim();
        C.clear(reponse);
        if (!texte) { U.toast('Saisir ou scanner un numéro de badge.', { type: 'warning' }); return; }
        var lu = global.SIGH.parcours.lireBadgeQR(texte);
        var b = colBadges().all().filter(function (x) {
          return String(x.numero || '').toUpperCase() === String(lu.numero || '').toUpperCase();
        })[0] || null;
        var v = verdictBadge(b);
        journaliserVerification(texte, b, v);

        var carte = el('div.rounded-xl.border.p-4', {
          class: v.tone === 'success' ? 'border-success-300 bg-success-50'
            : (v.tone === 'warning' ? 'border-warning-300 bg-warning-50' : 'border-danger-300 bg-danger-50'),
        });
        var ligne = el('div.flex.flex-wrap.items-start.gap-4');
        if (b && b.photo) {
          ligne.appendChild(el('img.h-28.w-24.shrink-0.rounded-lg.border.border-slate-200.object-cover',
            { src: b.photo, alt: 'Photographie du porteur' }));
        }
        var bloc = el('div.min-w-0.flex-1');
        bloc.appendChild(el('p.text-xl.font-bold', {
          class: v.tone === 'success' ? 'text-success-700'
            : (v.tone === 'warning' ? 'text-warning-700' : 'text-danger-700'),
          text: v.label,
        }));
        bloc.appendChild(el('p.mt-1.text-sm.text-slate-700', { text: v.message }));
        if (b) {
          bloc.appendChild(el('div.mt-3', null, U.descList([
            ['Agent', b.agent], ['Matricule', b.matricule],
            ['Fonction', b.poste || '—'], ['Service', b.service || '—'],
            ['N° de série', b.numero],
          ])));
          if (lu.matricule && b.matricule && String(lu.matricule) !== String(b.matricule)) {
            /* Le QR porte DEUX informations : si elles se contredisent, le
               code a été fabriqué ailleurs. C'est la seule chose qu'un
               contrôle hors ligne puisse détecter, et elle vaut d'être dite. */
            bloc.appendChild(K.note('<strong>Incohérence</strong> : le code présenté annonce le matricule '
              + C.escapeHtml(lu.matricule) + ', le registre porte le matricule ' + C.escapeHtml(b.matricule)
              + ' pour ce numéro de série. Badge à retenir et à signaler.',
            { tone: 'danger', icon: 'alert-triangle' }));
          }
        }
        bloc.appendChild(el('p.mt-3.text-xs.text-slate-500', {
          text: 'Vérification journalisée le ' + C.dateHeure(new Date()) + ' par ' + S.currentUser() + '.',
        }));
        ligne.appendChild(bloc);
        carte.appendChild(ligne);
        reponse.appendChild(carte);
        U.icons(reponse);
      }
    },
  });


})(window);
