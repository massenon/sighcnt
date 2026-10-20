/* =============================================================================
 * Tableaux de bord par profil
 * -----------------------------------------------------------------------------
 * CDCT §10.13 — indicateurs financiers, pharmacie/stock, laboratoire, RH et
 * direction/activité, suivis en temps réel et déclinés selon le profil connecté.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours;
  var el = C.el;

  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  /* --- Accès mémorisés aux collections ------------------------------------- */
  function col(n) { return S.collection(n); }
  function patients() { return col('patients').active(); }
  function consultations() { return col('consultations').active(); }
  function admissions() { return col('admissions').active(); }
  function factures() { return col('factures').active(); }
  function produits() { return col('produits').active(); }
  function lots() { return col('lots').active(); }
  function personnel() { return col('personnel').active(); }
  function mouvements() { return col('mouvements').active(); }
  function ecritures() { return col('ecritures').active(); }

  function duJour(rows, key) {
    var j = C.iso(AUJ);
    return rows.filter(function (r) { return C.iso(r[key]) === j; });
  }
  function duMois(rows, key) {
    return rows.filter(function (r) {
      var d = C.toDate(r[key]);
      return d.getFullYear() === AUJ.getFullYear() && d.getMonth() === AUJ.getMonth();
    });
  }

  /* --- Indicateurs partagés ------------------------------------------------ */
  function caDuMois() { return C.sum(duMois(factures(), 'date'), 'montantTTC'); }
  function encaisseDuMois() { return C.sum(duMois(factures(), 'date'), 'montantPaye'); }
  function ruptures() { return produits().filter(function (p) { return p.stock <= p.seuilAlerte; }); }
  function perimes() { return lots().filter(function (l) { return l.statut === 'perime'; }); }
  function peremptionProche() { return lots().filter(function (l) { return l.statut === 'alerte'; }); }
  function litsOccupes() { return admissions().filter(function (a) { return a.statut === 'en_cours'; }); }
  function totalLits() { return D.CHAMBRES.reduce(function (n, ch) { return n + ch.lits.length; }, 0); }

  /* ==========================================================================
   * LE WIDGET BFR — POSÉ SUR LES DEUX TABLEAUX DE LA DIRECTION
   * --------------------------------------------------------------------------
   * BFR_TABLEAU.txt le demande « sous forme de widgets décisionnels » sur
   * `dash-da` et `dash-direction`. Il est DÉCLARÉ UNE FOIS au module et posé
   * deux fois : deux copies auraient divergé au premier ajustement, et c'est
   * précisément le genre d'écart qu'on ne voit qu'en réunion, quand les deux
   * écrans affichent deux BFR différents.
   *
   * Il ne calcule rien non plus — `PR.bfr` fait foi, ici comme en M12.
   * ======================================================================== */
  function widgetBFR() {
    var b = PR.bfr();
    var ind = PR.indicateursPilotage();
    var enAlerte = ind.filter(function (x) { return x.etat === 'alerte'; });
    var indisponibles = ind.filter(function (x) { return x.etat === 'indisponible'; });

    var tuiles = U.kpiGrid([
      { label: 'Besoin en fonds de roulement', value: C.money(b.bfr), icon: 'scale',
        tone: b.bfr > 0 ? 'warning' : 'success',
        hint: b.bfrJours != null ? C.num(b.bfrJours) + ' jours de CA' : 'CA nul sur la période' },
      { label: 'En-cours clients', value: C.money(b.creances), icon: 'hand-coins', tone: 'info' },
      { label: 'Stocks', value: C.money(b.stocks), icon: 'package', tone: 'info' },
      { label: 'Dettes fournisseurs', value: C.money(b.dettes), icon: 'file-minus-2', tone: 'neutral' },
    ]);

    var corps = el('div.space-y-3', null, [tuiles]);

    if (enAlerte.length) {
      corps.appendChild(K.note('<strong>' + enAlerte.length + ' indicateur(s) au-delà du seuil '
        + 'd’alerte</strong> : ' + enAlerte.map(function (x) { return x.label; }).join(' · ') + '.',
      { tone: 'danger', icon: 'siren' }));
    } else if (!indisponibles.length) {
      corps.appendChild(K.note('Tous les indicateurs suivis sont en deçà de leur seuil d’alerte.',
        { tone: 'success', icon: 'check-circle-2' }));
    }

    if (b.incomplet.length) {
      corps.appendChild(K.note('Calcul incomplet — ' + b.incomplet.join(' et ') + ' ne sont pas '
        + 'amorcés sur ce poste : le BFR affiché est <strong>surestimé</strong>.',
      { tone: 'warning', icon: 'triangle-alert' }));
    }

    corps.appendChild(el('div.flex.flex-wrap.gap-2', null, [
      K.btn('Tableau décisionnel', { size: 'sm', variant: 'primary', icon: 'gauge',
        onclick: function () { global.SIGH.app.go('m12-tableau-decisionnel'); } }),
      K.btn('Détail du BFR', { size: 'sm', icon: 'scale',
        onclick: function () { global.SIGH.app.go('m12-bfr'); } }),
    ]));

    return U.card('Trésorerie & besoin en fonds de roulement', corps);
  }

  /** Le ton d'une ligne de la grille — vert atteint, orange vigilance, rouge alerte. */
  function tonIndicateur(etat) {
    return etat === 'atteint' ? 'success'
      : etat === 'vigilance' ? 'warning'
        : etat === 'alerte' ? 'danger' : 'neutral';
  }
  function libelleEtat(etat) {
    return etat === 'atteint' ? 'Objectif atteint'
      : etat === 'vigilance' ? 'Sous surveillance'
        : etat === 'alerte' ? 'Seuil d’alerte franchi' : 'Non calculable';
  }
  /** La valeur, dans l'unité de son objectif. */
  function valeurIndicateur(x) {
    if (x.reel == null) return '—';
    if (x.unite === '%') return C.pct(x.reel);
    if (x.unite === 'jours') return C.num(x.reel) + ' j';
    return C.num(x.reel, 1) + ' ' + x.unite;
  }

  /* --- Bandeau d'alertes transverse ---------------------------------------- */
/* --------------------------------------------------------------------------
   * Ce que le parcours de prescription a adressé à ce poste. Placé en tête du
   * tableau de bord : l'agent voit d'abord ce qui l'attend, les indicateurs
   * viennent ensuite.
   * ----------------------------------------------------------------------- */
  function fileDuPoste(type, cfg) {
    return function () {
      var bloc = el('div.space-y-3');
      var alertes = cfg && cfg.avecAlertes ? bandeauAlertes() : null;
      if (alertes) bloc.appendChild(alertes);
      bloc.appendChild(K.fileAttente(type, cfg));
      return bloc;
    };
  }

  function bandeauAlertes() {
    var items = [];
    var r = ruptures(), pe = perimes(), pp = peremptionProche();
    if (r.length) items.push({ tone: 'danger', icon: 'trending-down', texte: r.length + ' produit(s) sous le seuil d’alerte', lien: 'm6-alertes' });
    if (pe.length) items.push({ tone: 'danger', icon: 'alert-octagon', texte: pe.length + ' lot(s) périmé(s) à retourner', lien: 'm6-lots' });
    if (pp.length) items.push({ tone: 'warning', icon: 'clock', texte: pp.length + ' lot(s) à péremption proche (FEFO)', lien: 'm6-lots' });
    if (!items.length) return null;

    var wrap = el('div.grid.gap-2.sm\\:grid-cols-3');
    items.forEach(function (i) {
      var a = el('a.flex.items-center.gap-2\\.5.rounded-lg.border.px-3.py-2\\.5.transition-colors', {
        href: global.SIGH.app.href(i.lien),
        class: 'border-' + i.tone + '-200 bg-' + i.tone + '-50 hover:bg-' + i.tone + '-100',
      });
      a.appendChild(el('span.shrink-0', { class: 'text-' + i.tone + '-600' }, C.icon(i.icon, 'h-4 w-4')));
      a.appendChild(el('span.flex-1.text-xs.font-medium', { class: 'text-' + i.tone + '-900', text: i.texte }));
      a.appendChild(C.icon('arrow-right', 'h-3.5 w-3.5 text-' + i.tone + '-400'));
      wrap.appendChild(a);
    });
    return wrap;
  }

  /* ==========================================================================
   * DIRECTION — pilotage stratégique
   * ======================================================================== */
  global.SIGH.screen('dash-direction', {
    title: 'Tableau de bord — Direction',
    description: 'Pilotage stratégique : indicateurs financiers, activité, stock et ressources humaines en temps réel.',
    actions: function () {
      return [K.btn('Éditer le rapport de direction', {
        variant: 'primary', icon: 'printer',
        onclick: function () {
          var f = duMois(factures(), 'date');
          P.etat({
            titre: 'Rapport d’activité — Direction',
            sousTitre: 'Période : ' + C.moisAnnee(AUJ),
            cartouche: [
              ['Période', C.moisAnnee(AUJ)],
              ['Chiffre d’affaires', C.money(caDuMois())],
              ['Encaissé', C.money(encaisseDuMois())],
              ['Nombre de factures', C.num(f.length)],
            ],
            contenu: P.tableau([
              { label: 'Indicateur', key: 'k' },
              { label: 'Valeur', key: 'v', align: 'right' },
            ], [
              { k: 'Patients au répertoire', v: C.num(patients().length) },
              { k: 'Consultations du mois', v: C.num(duMois(consultations(), 'date').length) },
              { k: 'Hospitalisations en cours', v: C.num(litsOccupes().length) },
              { k: 'Taux d’occupation des lits', v: C.pct(litsOccupes().length / totalLits() * 100) },
              { k: 'Chiffre d’affaires du mois', v: C.money(caDuMois()) },
              { k: 'Montant encaissé', v: C.money(encaisseDuMois()) },
              { k: 'Reste à recouvrer', v: C.money(C.sum(factures(), 'reliquat')) },
              { k: 'Valeur du stock', v: C.money(C.sum(produits(), function (p) { return p.stock * p.cump; })) },
              { k: 'Produits sous seuil d’alerte', v: C.num(ruptures().length) },
              { k: 'Effectif', v: C.num(personnel().length) + ' agents' },
              { k: 'Masse salariale mensuelle', v: C.money(C.sum(personnel(), 'salaireBase')) },
            ]),
            signatures: [{ role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })];
    },
    render: K.dash({
      /* Fondement : la Direction pilote. Ce qu'elle regarde en premier n'est pas un
       * chiffre d'affaires — c'est ce qui BLOQUE : une échéance fiscale dépassée
       * engage la clinique, un résultat non validé bloque un patient. */
      premierRegard: function () {
      var ech = S.collection('echeancesFiscales').active().filter(function (e) {
        /* Les champs réels sont « paye » (booléen) et « echeance » — non
           « statut » et « dateEcheance ». Le filtre précédent retenait les 63
           échéances de l’exercice au lieu des seules dépassées : un compteur
           qui lit le mauvais champ alarme ou rassure à tort, et les deux sont
           également fautifs. */
        return !e.paye && String(e.echeance || '') < C.iso(AUJ);
      });
      return {
        valeur: ech.length, unite: 'échéance(s) fiscale(s) dépassée(s)',
        question: 'engagent la clinique',
        vide: 'Aucune échéance fiscale en retard.',
        ton: 'danger', icone: 'siren',
        ecran: 'm12-echeances', lienLabel: 'Voir les échéances',
        note: 'Une échéance dépassée engage la clinique, elle ne se rattrape pas — c’est ce qui prime '
          + 'sur le chiffre du jour.',
      };
      },
      alerte: bandeauAlertes,
      kpis: function () {
        var f = factures();
        return [
          { label: 'Chiffre d’affaires du mois', value: C.money(caDuMois()), icon: 'trending-up', tone: 'success', delta: 8.4 },
          { label: 'Montant encaissé', value: C.money(encaisseDuMois()), icon: 'wallet', tone: 'navy', hint: C.pct(caDuMois() ? encaisseDuMois() / caDuMois() * 100 : 0) + ' du facturé' },
          { label: 'Reste à recouvrer', value: C.money(C.sum(f, 'reliquat')), icon: 'hand-coins', tone: 'warning', delta: -3.1, invert: true },
          { label: 'Valeur du stock', value: C.money(C.sum(produits(), function (p) { return p.stock * p.cump; })), icon: 'package', tone: 'info' },
          { label: 'Patients au répertoire', value: C.num(patients().length), icon: 'users', tone: 'navy' },
          { label: 'Consultations du mois', value: C.num(duMois(consultations(), 'date').length), icon: 'stethoscope', tone: 'info', delta: 5.2 },
          { label: 'Lits occupés', value: litsOccupes().length + ' / ' + totalLits(), icon: 'bed-double', tone: 'navy', hint: C.pct(litsOccupes().length / totalLits() * 100) + ' d’occupation' },
          { label: 'Effectif', value: C.num(personnel().length), icon: 'users-round', tone: 'neutral', hint: 'Masse salariale ' + C.money(C.sum(personnel(), 'salaireBase')) },
        ];
      },
      kpiCols: 'grid-cols-2 lg:grid-cols-4',
      sections: [
        /* Le BFR précède les graphiques : la Direction décide d'un
           financement avant de commenter une courbe. */
        { render: widgetBFR },
        {
          render: function () {
            return K.charts([
              {
                title: 'Évolution du chiffre d’affaires (12 mois)',
                render: function () {
                  var s = K.parMois(factures(), 'date', 'montantTTC');
                  var e = K.parMois(factures(), 'date', 'montantPaye');
                  return G.ligne(s.labels, [
                    { label: 'Facturé', data: s.data, color: G.TONES.navy },
                    { label: 'Encaissé', data: e.data, color: G.TONES.vert },
                  ]);
                },
              },
              {
                title: 'Recettes par activité',
                render: function () {
                  var g = C.groupBy(factures(), 'type');
                  var keys = Object.keys(g);
                  return G.anneau(keys, keys.map(function (k) { return C.sum(g[k], 'montantTTC'); }), { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Activité — consultations et hospitalisations',
                render: function () {
                  var c = K.parMois(consultations(), 'date');
                  var a = K.parMois(admissions(), 'dateEntree');
                  return G.barres(c.labels, [
                    { label: 'Consultations', data: c.data, color: G.TONES.bleu },
                    { label: 'Hospitalisations', data: a.data, color: G.TONES.ciel },
                  ]);
                },
              },
              {
                title: 'Répartition des modes de paiement',
                render: function () {
                  var g = C.groupBy(factures(), 'modePaiement');
                  var keys = Object.keys(g);
                  return G.anneau(
                    keys.map(function (k) {
                      var m = D.MODES_PAIEMENT.filter(function (x) { return x.id === k; })[0];
                      return m ? m.label : k;
                    }),
                    keys.map(function (k) { return C.sum(g[k], 'montantPaye'); }),
                    { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          title: 'Performance par service (centre de coûts)',
          render: function () {
            var g = C.groupBy(factures(), 'type');
            return K.ranking(Object.keys(g).map(function (k) {
              return { label: k, value: C.sum(g[k], 'montantTTC') };
            }).sort(function (a, b) { return b.value - a.value; }), { format: function (v) { return C.money(v); } });
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm12-etats-financiers', icon: 'book-open-check', label: 'États financiers', detail: 'Bilan, compte de résultat' },
              { id: 'm11-validation', icon: 'badge-check', label: 'Validation de la paie', detail: 'Soumise par les RH' },
              { id: 'm7-commandes', icon: 'truck', label: 'Commandes à valider', detail: 'RG-04 — validation DA' },
              { id: 'm14-audit', icon: 'scroll-text', label: 'Journal d’audit', detail: 'Traçabilité des actions' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * ADMINISTRATEUR SYSTÈME
   * ======================================================================== */
  global.SIGH.screen('dash-admin', {
    title: 'Tableau de bord — Administration système',
    description: 'Supervision technique : comptes, sessions, journal d’audit, sauvegardes et intégrité des référentiels.',
    render: K.dash({
      /* Fondement : l'administrateur système veille sur les accès. Une tentative de
       * connexion refusée est le signal qu'il doit voir en premier. */
      premierRegard: function () {
      var tentatives = S.collection('tentativesConnexion').active();
      return {
        valeur: tentatives.length, unite: 'tentative(s) de connexion refusée(s)',
        question: 'à examiner',
        vide: 'Aucune tentative de connexion refusée.',
        ton: 'warning', icone: 'shield-alert',
        ecran: 'm14-roles', lienLabel: 'Rôles & permissions',
        note: 'Un rôle archivé n’ouvre plus de session, et la tentative est écrite. Aucune action '
          + 'n’est anonyme (RG-12).',
      };
      },
      kpis: function () {
        var audit = S.raw().audit || [];
        var echecs = audit.filter(function (a) { return a.succes === false; });
        return [
          { label: 'Comptes utilisateurs', value: C.num(personnel().length), icon: 'users-round', tone: 'navy' },
          { label: 'Actions journalisées', value: C.num(audit.length), icon: 'scroll-text', tone: 'info', hint: 'RG-12 — aucune action anonyme' },
          { label: 'Tentatives infructueuses', value: C.num(echecs.length), icon: 'shield-alert', tone: echecs.length ? 'warning' : 'success' },
          { label: 'Dernière sauvegarde', value: 'Aujourd’hui', icon: 'database-backup', tone: 'success', hint: '02h00 — automatique' },
        ];
      },
      sections: [
        {
          title: 'Journal d’audit — dernières actions',
          actions: function () { return [K.lien('m14-audit', 'Tout consulter', { size: 'sm', icon: 'arrow-right' })]; },
          render: function () {
            return K.miniTable([
              { label: 'Horodatage', render: function (a) { return C.dateHeure(a.dateHeure); } },
              { label: 'Utilisateur', key: 'utilisateur' },
              { label: 'Action', render: function (a) { return U.badge(a.action, a.succes === false ? 'danger' : 'navy'); } },
              { label: 'Module', key: 'module' },
              { label: 'Entité', key: 'entite' },
              { label: 'Poste', key: 'poste' },
            ], (S.raw().audit || []).slice(0, 12));
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Intégrité des référentiels',
                render: function () {
                  var refs = [
                    { label: 'Patients', value: patients().length },
                    { label: 'Produits', value: produits().length },
                    { label: 'Analyses de laboratoire', value: D.ANALYSES.length },
                    { label: 'Compagnies d’assurance', value: D.ASSUREURS.length },
                    { label: 'Comptes SYSCOHADA', value: D.PLAN_COMPTABLE.length },
                    { label: 'Agents', value: personnel().length },
                  ];
                  return K.ranking(refs);
                },
              },
              {
                title: 'Répartition des actions par module',
                render: function () {
                  var g = C.groupBy(S.raw().audit || [], 'module');
                  var keys = Object.keys(g);
                  return G.anneau(keys, keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm14-utilisateurs', icon: 'user-cog', label: 'Utilisateurs', detail: 'Comptes et habilitations' },
              { id: 'm14-roles', icon: 'key-round', label: 'Rôles & permissions', detail: 'Matrice RBAC' },
              { id: 'm14-sauvegardes', icon: 'database-backup', label: 'Sauvegardes', detail: 'Quotidienne et hebdomadaire' },
              { id: 'cfg-organisation', icon: 'network', label: 'Configuration clinique', detail: 'Organigramme et référentiels' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * MÉDECIN
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * LA FILE DU PRATICIEN
   * --------------------------------------------------------------------------
   * Le champ `praticien` d'un ticket est FACULTATIF : la file de consultation
   * est souvent commune, et le prochain libre prend le suivant. Un ticket sans
   * praticien n'est donc pas un oubli, c'est une information — et il doit
   * rester visible du médecin, sinon il ne verrait pas la charge du service.
   * ----------------------------------------------------------------------- */
  function fileDuPraticien(nom) {
    var tous = S.collection('fileAttente').active().filter(function (t) {
      return t.poste === 'consultation' && t.etat === 'attente';
    });
    return {
      miens: tous.filter(function (t) { return t.praticien && t.praticien === nom; }),
      communs: tous.filter(function (t) { return !t.praticien; }),
      autres: tous.filter(function (t) { return t.praticien && t.praticien !== nom; }),
      tous: tous,
    };
  }

  function nomDuPraticien() {
    var se = S.session() || {};
    return se.nomComplet || se.nom || '';
  }

  /** Le tableau d'une file, ordonné comme le couloir : priorité, puis heure. */
  function tableFile(tickets, opts) {
    var o = opts || {};
    if (!tickets.length) {
      return U.empty(o.vide || 'Personne n’attend.', { icon: 'user-check' });
    }
    var RANG = { urgence_vitale: 0, urgence: 1, rdv: 2, ordre_arrivee: 3 };
    var rows = tickets.slice().sort(function (a, b) {
      var ra = RANG[a.priorite] != null ? RANG[a.priorite] : 9;
      var rb = RANG[b.priorite] != null ? RANG[b.priorite] : 9;
      if (ra !== rb) return ra - rb;
      return String(a.arriveeLe || '').localeCompare(String(b.arriveeLe || ''));
    });
    return U.dataTable({
      rows: rows, pageSize: 8, searchable: false, exportName: o.exportName || 'file-praticien',
      columns: [
        { key: 'numero', label: 'N°', nowrap: true,
          render: function (r) { return el('span.font-mono.text-xs.font-bold', { text: r.numero }); } },
        { key: 'patient', label: 'Patient', render: function (r) {
          return el('div', null, [
            el('p.font-medium', { text: r.patient }),
            el('p.text-[10px].text-slate-400', { text: r.patientCode || '' }),
          ]);
        } },
        { key: 'priorite', label: 'Priorité', render: function (r) {
          var t = r.priorite === 'urgence_vitale' ? 'danger'
            : (r.priorite === 'urgence' ? 'warning' : (r.priorite === 'rdv' ? 'info' : 'neutral'));
          var lib = r.priorite === 'urgence_vitale' ? 'Urgence vitale'
            : (r.priorite === 'urgence' ? 'Urgence' : (r.priorite === 'rdv' ? 'Rendez-vous' : 'Ordre d’arrivée'));
          return U.badge(lib, t);
        } },
        { key: 'motif', label: 'Motif' },
        { key: 'arriveeLe', label: 'Arrivé à', nowrap: true,
          render: function (r) { return String(r.arriveeLe || '').slice(11, 16) || '—'; } },
        o.montrerPraticien ? { key: 'praticien', label: 'Attendu par',
          render: function (r) {
            return r.praticien ? el('span.text-xs', { text: r.praticien })
              : el('span.text-xs.italic.text-slate-400', { text: 'file commune' });
          } } : null,
      ].filter(Boolean),
      rowActions: function (r) {
        return [K.btn('Recevoir', { size: 'sm', variant: 'primary', icon: 'stethoscope',
          onclick: function () { global.SIGH.app.go('m2-consultation-fiche'); } })];
      },
    });
  }

  /** La section « vos patients », commune aux prescripteurs. */
  function sectionMaFile() {
    return {
      title: 'Vos patients en attente',
      rapide: true,
      render: function () {
        var moi = nomDuPraticien();
        var f = fileDuPraticien(moi);
        var wrap = el('div.space-y-3');

        wrap.appendChild(K.note(f.miens.length
          ? '<strong>' + f.miens.length + ' patient(s) vous attendent nommément</strong>, et '
            + f.communs.length + ' patient(s) sont en file commune — le prochain praticien libre '
            + 'les prend.'
          : '<strong>Aucun patient ne vous est adressé nommément.</strong> '
            + f.communs.length + ' patient(s) attendent en file commune : le prochain praticien '
            + 'libre les reçoit.',
          { tone: f.miens.length ? 'warning' : 'info', icon: 'list-ordered' }));

        if (f.miens.length) {
          wrap.appendChild(U.card('Adressés à ' + (moi || 'vous'),
            tableFile(f.miens, { vide: 'Aucun patient ne vous est adressé.', exportName: 'ma-file' })));
        }
        wrap.appendChild(U.card('File commune de consultation',
          tableFile(f.communs, {
            vide: 'Aucun patient en file commune.',
            exportName: 'file-commune',
          })));

        if (f.autres.length) {
          /* Ce qui revient aux confrères reste VISIBLE mais à part : le médecin
             doit voir la charge du service sans croire que c'est à lui de la
             prendre. */
          wrap.appendChild(K.note(f.autres.length + ' patient(s) attendent un autre praticien. '
            + 'Ils figurent au poste de consultation, pas dans votre liste.',
            { tone: 'neutral', icon: 'users' }));
        }
        wrap.appendChild(el('div.mt-1', null,
          K.btn('Ouvrir la file d’attente', { size: 'sm', icon: 'list-ordered',
            onclick: function () { global.SIGH.app.go('m2-file-attente'); } })));
        return wrap;
      },
    };
  }

  global.SIGH.screen('dash-medecin', {
    title: 'Tableau de bord — Médecin',
    description: 'Consultations du jour, patients hospitalisés sous responsabilité et prescriptions récentes.',
    render: K.dash({
      /* Fondement : le médecin a prescrit et il attend. La validation biologique
       * est ce qui lui rend le résultat — c'est donc ce qu'il vient chercher. */
      premierRegard: function () {
      /* On demande au référentiel si le résultat est OPPOSABLE, au lieu de
         comparer des codes écrits à la main : les deux qui figuraient ici —
         « valide_bio » et « rendu » — n'existaient ni l'un ni l'autre, et le
         compteur affichait donc zéro en permanence. */
      var rendus = S.collection('demandesAnalyses').active().filter(function (d) {
        return D.resultatRendu(d.etatAnalyse);
      });
      return {
        valeur: rendus.length, unite: 'résultat(s) rendu(s)',
        question: 'vous attendent',
        vide: 'Aucun résultat en attente de lecture.',
        ton: 'info', icone: 'flask-conical',
        ecran: 'm5-resultats', lienLabel: 'Lire les résultats',
        note: 'Un résultat n’est visible qu’après validation biologique : ceux-ci le sont.',
      };
      },
      alerte: fileDuPoste('acte', {
        titre: 'Actes prescrits en attente d’exécution',
        vide: 'Aucun acte prescrit en attente.',
        icon: 'arrow-right', action: 'Ouvrir les soins',
        onAction: function () { global.SIGH.app.go('m3-soins'); },
      }),
      kpis: function () {
        var cj = duJour(consultations(), 'date');
        return [
          { label: 'Consultations du jour', value: C.num(cj.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'En attente', value: C.num(consultations().filter(function (c) { return c.statut === 'planifiee'; }).length), icon: 'clock', tone: 'warning' },
          { label: 'Patients hospitalisés', value: C.num(litsOccupes().length), icon: 'bed-double', tone: 'info' },
          { label: 'Consultations du mois', value: C.num(duMois(consultations(), 'date').length), icon: 'calendar-check', tone: 'success' },
        ];
      },
      sections: [
        sectionMaFile(),
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Recevoir un patient', icone: 'stethoscope', action: 'Ouvrir la consultation',
                detail: 'Le patient est appelé, la consultation commence.',
                etapes: [
                  /* Refonte Zone 2 (14/09/2026) : le DOSSIER d'abord, la FICHE
                     ensuite — la fiche récapitule le dossier et refuse sans lui. */
                  { label: 'Enregistrer le dossier de consultation', ecran: 'm2-dossiers-consultation',
                    detail: 'Anamnèse, trois catégories d’antécédents, examen IPPOA par appareil. Les constantes de l’accueil y sont lues, pas ressaisies.' },
                  { label: 'Fiche de consultation : diagnostic et prescription', ecran: 'm2-consultation-fiche',
                    detail: 'Code de pathologie ET diagnostic rédigé ; médicaments, analyses et imagerie — ici seulement.' },
                  { label: 'Le patient règle', poste: 'Caisse' },
                  { label: 'Le laboratoire prélève', poste: 'Laboratoire' },
                ],
              },
              {
                titre: 'Lire les résultats', icone: 'flask-conical', action: 'Voir les résultats',
                detail: 'Vos prescriptions d’analyses sont revenues.',
                etapes: [
                  { label: 'Consulter les résultats rendus', ecran: 'm5-resultats',
                    detail: 'Seuls les résultats VALIDÉS BIOLOGIQUEMENT vous sont visibles.' },
                  { label: 'Réajuster le traitement', ecran: 'm2-ordonnances' },
                  { label: 'Programmer le contrôle', ecran: 'm2-rendezvous' },
                ],
              },
              {
                titre: 'Hospitaliser', icone: 'bed-double', action: 'Admettre',
                detail: 'L’état du patient justifie un séjour.',
                etapes: [
                  { label: 'Créer l’admission et attribuer un lit', ecran: 'm3-admissions',
                    detail: 'Un lit ne porte qu’une admission active à la fois.' },
                  { label: 'Prescrire le traitement d’entrée', ecran: 'm2-prescriptions' },
                  { label: 'Suivre les constantes', ecran: 'm3-surveillance' },
                  { label: 'Rédiger le rapport médical à la sortie', ecran: 'm3-rapport' },
                  { label: 'Vérifier le solde avant sortie', ecran: 'm8-reliquats',
                    detail: 'RG-06 — pas de sortie sans solde apuré.' },
                ],
              },
              {
                titre: 'Délivrer un certificat', icone: 'stamp', action: 'Délivrer',
                detail: 'Le patient réclame une pièce certifiante.',
                etapes: [
                  { label: 'Établir la pièce', ecran: 'm1-pieces',
                    detail: 'Quatorze types. Le prénuptial se remplit depuis les résultats validés.' },
                  { label: 'Encaisser', poste: 'Caisse' },
                ],
              },
            ]);
          },
        },
        {
          title: 'File d’attente et consultations récentes',
          actions: function () { return [K.lien('m2-consultations', 'Toutes les consultations', { size: 'sm', icon: 'arrow-right' })]; },
          render: function () {
            return K.miniTable([
              { label: 'Date', render: function (c) { return C.dateFR(c.date) + ' ' + C.heure(c.date); } },
              { label: 'Dossier', render: function (c) { return el('span.font-mono.text-xs', { text: c.patientCode }); } },
              { label: 'Patient', key: 'patient' },
              { label: 'Motif', key: 'motif' },
              { label: 'Statut', render: function (c) { return U.statut(c.statut); } },
            ], C.sortBy(consultations(), 'date', 'desc').slice(0, 10));
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Motifs de consultation les plus fréquents',
                render: function () {
                  var g = C.groupBy(consultations(), 'motif');
                  return K.ranking(Object.keys(g).map(function (k) { return { label: k, value: g[k].length }; })
                    .sort(function (a, b) { return b.value - a.value; }).slice(0, 8));
                },
              },
              {
                title: 'Diagnostics posés',
                render: function () {
                  var g = C.groupBy(consultations(), 'diagnostic');
                  var keys = Object.keys(g).slice(0, 6);
                  return G.barres(keys, [{ label: 'Cas', data: keys.map(function (k) { return g[k].length; }) }], { horizontal: true, height: 280 });
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm2-consultation-fiche', icon: 'clipboard-plus', label: 'Nouvelle consultation', detail: 'Diagnostic et prescription' },
              { id: 'm5-demandes', icon: 'flask-conical', label: 'Prescrire une analyse', detail: 'Demande au laboratoire' },
              { id: 'm3-admissions', icon: 'bed-double', label: 'Décider une hospitalisation', detail: 'Admission et affectation de lit' },
              { id: 'm2-domicile', icon: 'house-plus', label: 'Consultation à domicile', detail: 'Planification et facturation' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * INFIRMIER / SAGE-FEMME
   * ======================================================================== */
  global.SIGH.screen('dash-infirmier', {
    title: 'Tableau de bord — Infirmier / Sage-femme',
    description: 'Patients hospitalisés, relevés de constantes attendus, sorties à préparer et gardes du jour.',
    render: K.dash({
      /* Fondement : la règle de relais. L'infirmier et la sage-femme viennent
       * chercher ce qui leur revient MAINTENANT, pas la liste de tout. */
      premierRegard: function () {
      var dus = PR.soinsDuSecteur ? PR.soinsDuSecteur('salle_soins') : [];
      var n = dus.reduce(function (t, d) { return t + d.lignes.length; }, 0);
      return {
        valeur: n, unite: 'administration(s)',
        question: 'reviennent à votre poste',
        vide: 'Aucune administration due à votre poste.',
        ton: 'navy', icone: 'syringe',
        ecran: 'm2-salle-soins', lienLabel: 'Salle de soins',
        note: 'Le rang du passage décide du secteur : la première administration d’un traitement '
          + 'hospitalier revient à la salle de soins, les suivantes à l’hospitalisation.',
      };
      },
      kpis: function () {
        var occ = litsOccupes();
        return [
          { label: 'Patients hospitalisés', value: C.num(occ.length), icon: 'bed-double', tone: 'navy' },
          { label: 'Lits libres', value: C.num(totalLits() - occ.length), icon: 'bed', tone: 'success' },
          { label: 'Relevés de constantes attendus', value: C.num(occ.length * 3), icon: 'activity', tone: 'warning', hint: '3 relevés par patient et par jour' },
          { label: 'Sorties à préparer', value: C.num(occ.filter(function (a) { return C.daysBetween(a.dateEntree, AUJ) > 5; }).length), icon: 'door-open', tone: 'info' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Administrer les soins dus', icone: 'syringe', action: 'Salle de soins',
                detail: 'Ce qui revient à votre poste maintenant.',
                etapes: [
                  { label: 'Voir ce qui vous revient', ecran: 'm2-salle-soins',
                    detail: 'Ambulatoire : tous les passages. Hospitalier : la PREMIÈRE administration.' },
                  { label: 'Administrer sous votre nom', ecran: 'm2-salle-soins',
                    detail: 'Une prescription non réglée reste visible mais non exécutable.' },
                  { label: 'Les passages suivants', poste: 'Hospitalisation' },
                ],
              },
              {
                titre: 'Surveiller un hospitalisé', icone: 'activity', action: 'Fiche de surveillance',
                detail: 'Relevé des constantes au lit du patient.',
                etapes: [
                  { label: 'Relever les constantes', ecran: 'm1-constantes' },
                  { label: 'Lire la courbe à cinq échelles', ecran: 'm3-surveillance',
                    detail: 'Même donnée que la feuille de température, autre présentation.' },
                  { label: 'Évaluer la conscience si nécessaire', ecran: 'm3-glasgow',
                    detail: 'Le score est calculé, borné de 3 à 15.' },
                  { label: 'Prévenir le médecin si aggravation', poste: 'Consultation' },
                ],
              },
              {
                titre: 'Poser une transfusion', icone: 'droplets', action: 'Surveiller',
                detail: 'Une poche de PSL est posée.',
                etapes: [
                  { label: 'Ouvrir la fiche de surveillance transfusionnelle', ecran: 'm3-transfusion',
                    detail: 'Huit temps imposés : avant la pose, 15 min, toutes les 30 min, fin, 1 h, 2 h.' },
                  { label: 'Relever à chaque temps', ecran: 'm3-transfusion' },
                  { label: 'Signaler tout incident immédiatement', poste: 'Médecin' },
                ],
              },
              {
                titre: 'Préparer une sortie', icone: 'log-out', action: 'Sorties',
                detail: 'Le séjour se termine.',
                etapes: [
                  { label: 'Vérifier le solde', ecran: 'm8-reliquats', detail: 'RG-06.' },
                  { label: 'Établir la fiche de sortie', ecran: 'm3-sorties',
                    detail: 'RG-07 — trois signatures, dont le constat du gardien.' },
                  { label: 'Remettre le traitement de sortie', poste: 'Pharmacie' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Patients hospitalisés — service',
          actions: function () { return [K.lien('m3-plan-lits', 'Plan des lits', { size: 'sm', icon: 'layout-grid' })]; },
          render: function () {
            var occ = litsOccupes();
            if (!occ.length) return U.empty('Aucun patient hospitalisé actuellement.', { icon: 'bed' });
            return K.miniTable([
              { label: 'Lit', render: function (a) { return el('span.font-mono.text-xs.font-semibold', { text: a.lit }); } },
              { label: 'Patient', key: 'patient' },
              { label: 'Dossier', render: function (a) { return el('span.font-mono.text-xs', { text: a.patientCode }); } },
              { label: 'Entrée', render: function (a) { return C.dateFR(a.dateEntree); } },
              { label: 'Jours', align: 'right', render: function (a) { return String(C.daysBetween(a.dateEntree, AUJ)); } },
              { label: 'Diagnostic', key: 'diagnosticEntree' },
              { label: 'Prise en charge', render: function (a) { return U.statut(a.priseEnCharge); } },
            ], occ);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm3-feuille-temperature', icon: 'thermometer', label: 'Feuille de température', detail: 'Saisie des constantes' },
              { id: 'm3-admissions', icon: 'user-plus', label: 'Nouvelle admission', detail: 'Affecter un lit' },
              { id: 'm3-sorties', icon: 'door-open', label: 'Sortie d’hospitalisation', detail: 'RG-06 / RG-07 — signatures' },
              { id: 'm4-accouchements', icon: 'baby', label: 'Accouchement', detail: 'Maternité et naissance' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * PHARMACIEN
   * ======================================================================== */
  global.SIGH.screen('dash-pharmacien', {
    title: 'Tableau de bord — Pharmacie',
    description: 'Stock de détail, dispensation, alertes de rupture et suivi des péremptions selon le principe FEFO.',
    render: K.dash({
      /* Fondement : le compte Pharmacie est FERMÉ depuis le 24/08/2026 et la
       * pharmacie est tenue par la caisse. Le tableau de bord le dit plutôt que
       * de faire comme si de rien n'était. */
      premierRegard: function () {
      return {
        valeur: 0, unite: '',
        question: '',
        vide: 'Le compte Pharmacie a été fermé — la pharmacie est tenue par la caisse.',
        ton: 'warning', icone: 'info',
        note: 'Décision de la Direction du 24/08/2026 : le stock de détail et la pharmacie d’urgence '
          + 'sont rattachés au compte Caissier. Rien n’a été supprimé — les mouvements signés par ce '
          + 'rôle restent attribuables (RG-14).',
      };
      },
      alerte: fileDuPoste('dispensation', {
        avecAlertes: true,
        titre: 'Ordonnances à délivrer',
        vide: 'Aucune ordonnance en attente de délivrance.',
        icon: 'arrow-right', action: 'Ouvrir la dispensation',
        onAction: function () { global.SIGH.app.go('m6-dispensation'); },
      }),
      kpis: function () {
        var p = produits().filter(function (x) { return x.categorie === 'medicament'; });
        return [
          { label: 'Références en pharmacie', value: C.num(p.length), icon: 'pill', tone: 'navy' },
          { label: 'Valeur du stock détail', value: C.money(C.sum(p, function (x) { return x.stockDetail * x.cump; })), icon: 'wallet', tone: 'info' },
          { label: 'Produits sous seuil', value: C.num(ruptures().length), icon: 'trending-down', tone: 'danger' },
          { label: 'Lots à péremption proche', value: C.num(peremptionProche().length), icon: 'clock', tone: 'warning', hint: 'FEFO — RG-05' },
        ];
      },
      sections: [
        {
          title: 'Produits à réapprovisionner en priorité',
          actions: function () { return [K.lien('m7-besoins', 'Exprimer un besoin', { size: 'sm', icon: 'clipboard-list' })]; },
          render: function () {
            var r = C.sortBy(ruptures(), 'stock').slice(0, 10);
            if (!r.length) return U.empty('Aucun produit sous le seuil d’alerte.', { icon: 'check-circle-2' });
            return K.miniTable([
              { label: 'Code', render: function (p) { return el('span.font-mono.text-xs', { text: p.code }); } },
              { label: 'Désignation', key: 'designation' },
              { label: 'Stock', align: 'right', key: 'stock' },
              { label: 'Seuil', align: 'right', key: 'seuilAlerte' },
              { label: 'Emplacement', key: 'emplacement' },
              { label: 'État', render: function (p) { return p.stock === 0 ? U.badge('Rupture', 'danger') : U.badge('Critique', 'warning'); } },
            ], r);
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
                  return G.barres(e.labels, [
                    { label: 'Entrées', data: e.data, color: G.TONES.vert },
                    { label: 'Sorties', data: s.data, color: G.TONES.navy },
                  ]);
                },
              },
              {
                title: 'Péremptions à venir',
                render: function () {
                  var l = lots();
                  return G.anneau(['Périmés', 'Moins de 90 jours', 'Au-delà de 90 jours'],
                    [perimes().length, peremptionProche().length, l.length - perimes().length - peremptionProche().length],
                    { legend: 'bottom', colors: [G.TONES.rouge, G.TONES.orange, G.TONES.vert] });
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm6-dispensation', icon: 'hand-heart', label: 'Dispensation', detail: 'Servir une ordonnance' },
              { id: 'm6-lots', icon: 'calendar-x', label: 'Lots & péremptions', detail: 'Application du FEFO' },
              { id: 'm6-transferts', icon: 'arrow-left-right', label: 'Transfert gros → détail', detail: 'Réapprovisionner la pharmacie' },
              { id: 'm6-inventaire', icon: 'clipboard-check', label: 'Inventaire', detail: 'Physique contre théorique' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * LABORANTIN
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * LE RAPPEL DU MATIN — deux questions, deux gestes
   * ----------------------------------------------------------------------- */
  var CLE_RAPPEL_LABO = 'sigh-cnt:rappel-labo';

  function rappelBiologiste() {
    /* Une fois par jour et par poste : rouvrir la page dix fois ne doit pas
       rouvrir la modale dix fois, sinon on la ferme sans la lire — et le jour
       où elle compte, elle est balayée du même geste. */
    var jour = C.iso(AUJ);
    try {
      if (global.sessionStorage && global.sessionStorage.getItem(CLE_RAPPEL_LABO) === jour) return;
    } catch (e) { /* stockage de session indisponible : on affiche */ }

    var col = S.collection('demandesAnalyses').active();

    /* 1. RÉGLÉES, PAS ENCORE PRÉLEVÉES. La caisse a fait son travail ; ces
       patients attendent qu'on les appelle. */
    var aPrelever = col.filter(function (d) {
      return d.etatAnalyse === 'attente_prelevement' && !d.preleveLe;
    });

    /* 2. REÇUES AU LABORATOIRE, RÉSULTAT NON SAISI. L'échantillon est là ;
       personne d'autre ne le sait. */
    var aSaisir = col.filter(function (d) {
      return d.recuLaboLe && ['en_cours', 'preleve'].indexOf(d.etatAnalyse) >= 0;
    });

    /* Une modale qui annonce « rien à faire » coûte un clic pour aucune
       information. */
    if (!aPrelever.length && !aSaisir.length) return;

    try {
      if (global.sessionStorage) global.sessionStorage.setItem(CLE_RAPPEL_LABO, jour);
    } catch (e) { /* rien */ }

    function bloc(titre, detail, nb, ton, icone, ecran, libelleBouton) {
      if (!nb) return null;
      return el('div.flex.items-start.gap-3.rounded-lg.border.p-3', {
        class: 'border-' + ton + '-200 bg-' + ton + '-50',
      }, [
        el('span.grid.h-10.w-10.shrink-0.place-items-center.rounded-lg', {
          class: 'bg-' + ton + '-100 text-' + ton + '-700',
        }, C.icon(icone, 'h-5 w-5')),
        el('div.min-w-0.flex-1', null, [
          el('p.text-sm.font-semibold', { class: 'text-' + ton + '-900',
            text: C.num(nb) + ' ' + titre }),
          el('p.text-xs', { class: 'text-' + ton + '-800', text: detail }),
        ]),
        el('a.btn.btn-secondary.btn-sm.shrink-0', {
          href: global.SIGH.app.href(ecran),
        }, libelleBouton),
      ]);
    }

    var corps = el('div.space-y-3', null, [
      bloc('analyse(s) réglée(s) à la caisse, prélèvement à faire',
        'Le patient a payé : il peut être appelé en salle de prélèvement. Tant que le '
        + 'prélèvement n’est pas fait, aucun résultat ne peut être saisi.',
        aPrelever.length, 'warning', 'syringe', 'm5-prelevement', 'Salle de prélèvement'),
      bloc('échantillon(s) reçu(s), résultat à renseigner',
        'L’échantillon est parvenu au laboratoire. Le prescripteur ne verra rien tant que '
        + 'le résultat n’est pas saisi PUIS validé biologiquement.',
        aSaisir.length, 'info', 'file-pen-line', 'm5-resultats', 'Saisie des résultats'),
      K.note('Ce rappel s’affiche <strong>une fois par jour</strong> à l’ouverture de votre poste. '
        + 'Le détail reste disponible à tout moment depuis la cloche et depuis vos écrans.',
      { tone: 'neutral', icon: 'info' }),
    ].filter(Boolean));

    var m = U.modal({
      title: 'Rappel du laboratoire',
      subtitle: 'Ce qui attend votre poste ce matin',
      size: 'md', body: corps,
      footer: [K.btn('J’ai pris connaissance', {
        variant: 'primary', icon: 'check', onclick: function () { m.close(); },
      })],
    });
    U.icons(corps);
  }

  global.SIGH.screen('dash-laborantin', {
    title: 'Tableau de bord — Laboratoire',
    description: 'Demandes d’analyses, résultats à saisir, consommation de réactifs et banque de sang.',
    render: K.dash({
      /* Le rappel s'ouvre AVANT le rendu. Il était déclaré sur la DÉFINITION
         de l'écran alors que le kit le lit dans la configuration du tableau —
         il ne s'exécutait donc jamais, et un crochet qui ne se déclenche pas
         ressemble en tout point à un crochet qui fonctionne. */
      avant: rappelBiologiste,
      /* Fondement : les DEUX verrous du laboratoire. Ce que le biologiste regarde
       * en premier, c'est ce qui attend SA signature — entre les deux
       * validations, le résultat existe mais personne ne le voit. */
      premierRegard: function () {
      var aValider = S.collection('demandesAnalyses').active().filter(function (d) {
        return d.etatAnalyse === 'valide_technique';
      });
      return {
        valeur: aValider.length, unite: 'résultat(s)',
        question: 'attendent votre validation biologique',
        vide: 'Aucun résultat en attente de validation biologique.',
        ton: 'warning', icone: 'shield-check',
        ecran: 'm5-resultats', lienLabel: 'Valider',
        note: 'Entre la validation technique et la vôtre, le résultat existe mais le prescripteur ne '
          + 'le voit pas. C’est votre signature qui le rend opposable.',
      };
      },
      alerte: fileDuPoste('prelevement', {
        titre: 'Prélèvements à réaliser',
        vide: 'Aucun prélèvement en attente.',
        icon: 'arrow-right', action: 'Ouvrir les demandes',
        onAction: function () { global.SIGH.app.go('m5-demandes'); },
      }),
      kpis: function () {
        var reactifs = produits().filter(function (p) { return p.categorie === 'reactif' || p.categorie === 'conso_labo'; });
        return [
          { label: 'Analyses au catalogue', value: C.num(D.ANALYSES.length), icon: 'flask-conical', tone: 'navy', hint: 'Tarifs de la clinique' },
          { label: 'Demandes en attente', value: C.num(28), icon: 'inbox', tone: 'warning' },
          { label: 'Résultats du jour', value: C.num(42), icon: 'file-check-2', tone: 'success' },
          { label: 'Réactifs sous seuil', value: C.num(reactifs.filter(function (p) { return p.stock <= p.seuilAlerte; }).length), icon: 'test-tube', tone: 'danger' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Recevoir un prélèvement', icone: 'test-tube', action: 'Salle de prélèvement',
                detail: 'Le patient a réglé, il peut être appelé.',
                etapes: [
                  { label: 'Appeler le patient et prélever', ecran: 'm5-prelevement',
                    detail: 'Le patient peut repartir dès le prélèvement fait.' },
                  { label: 'Acheminer l’échantillon avec son bon', ecran: 'm5-prelevement' },
                  { label: 'Marquer l’échantillon reçu', ecran: 'm5-prelevement',
                    detail: 'Aucun résultat ne se saisit sur un prélèvement non reçu.' },
                ],
              },
              {
                titre: 'Rendre un résultat', icone: 'file-check-2', action: 'Saisir',
                detail: 'Les deux validations, dans l’ordre.',
                etapes: [
                  { label: 'Saisir les variables', ecran: 'm5-resultats',
                    detail: 'Unités et valeurs de référence pré-insérées ; les bornes suppléées sont marquées.' },
                  { label: 'Valider TECHNIQUEMENT', ecran: 'm5-resultats',
                    detail: 'Atteste la saisie. Le prescripteur ne voit toujours rien.' },
                  { label: 'Valider BIOLOGIQUEMENT', ecran: 'm5-resultats',
                    detail: 'C’est vous qui avez prélevé, c’est vous qui validez : la chaîne ne se rompt pas.' },
                  { label: 'Le prescripteur lit', poste: 'Consultation' },
                  { label: 'Remettre au patient externe', ecran: 'm5-resultats' },
                ],
              },
              {
                titre: 'Corriger un résultat rendu', icone: 'rotate-ccw', action: 'Rectifier',
                detail: 'Une erreur est découverte après validation.',
                etapes: [
                  { label: 'Rectifier avec motif obligatoire', ecran: 'm5-resultats',
                    detail: 'La version lue par le médecin est conservée ; la nouvelle est numérotée.' },
                  { label: 'Le prescripteur est notifié', poste: 'Consultation',
                    detail: 'Il doit savoir que ce qu’il a lu a changé.' },
                ],
              },
              {
                titre: 'Tenir les réactifs', icone: 'flask-conical', action: 'Réactifs',
                detail: 'Rupture et péremption.',
                etapes: [
                  { label: 'Vérifier les seuils', ecran: 'm5-reactifs',
                    detail: 'Un seuil non fixé n’est pas un seuil de zéro : aucune alerte n’est possible.' },
                  { label: 'Demander le réapprovisionnement', poste: 'Stock' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Analyses les plus demandées',
          actions: function () { return [K.lien('m5-catalogue', 'Catalogue des 48 analyses', { size: 'sm', icon: 'list' })]; },
          render: function () {
            var rnd = C.seeded(31);
            return K.ranking(D.ANALYSES.slice(0, 10).map(function (a) {
              return { label: a.designation, value: C.between(rnd, 20, 240) };
            }).sort(function (a, b) { return b.value - a.value; }));
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Analyses réalisées (12 mois)',
                render: function () {
                  var rnd = C.seeded(53);
                  return G.ligne(G.moisGlissants(12), [{
                    label: 'Analyses', data: G.moisGlissants(12).map(function () { return C.between(rnd, 380, 720); }),
                    color: G.TONES.bleu,
                  }]);
                },
              },
              {
                title: 'Répartition par catégorie d’analyse',
                render: function () {
                  var g = C.groupBy(D.ANALYSES, 'categorie');
                  var keys = Object.keys(g);
                  return G.anneau(keys, keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm5-demandes', icon: 'inbox', label: 'Demandes d’analyses', detail: 'File de prélèvement' },
              { id: 'm5-resultats', icon: 'file-pen-line', label: 'Saisir un résultat', detail: 'Validation biologique' },
              { id: 'm5-reactifs', icon: 'test-tube', label: 'Réactifs', detail: 'Consommation et seuils' },
              { id: 'm5-banque-sang', icon: 'droplet', label: 'Banque de sang', detail: 'Poches et donneurs' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * GESTIONNAIRE DE STOCK
   * ======================================================================== */
  global.SIGH.screen('dash-stock', {
    title: 'Tableau de bord — Gestion des stocks',
    description: 'Stock gros et détail, mouvements, cycle d’achat, inventaires et suivi des écarts.',
    render: K.dash({
      /* Fondement : RG-05 (FEFO et alertes de péremption) et RG-03. Le gestionnaire
       * regarde d'abord ce qui va manquer ou périmer — pas l'inventaire. */
      premierRegard: function () {
      var prods = S.collection('produits').active();
      var sous = prods.filter(function (x) {
        return x.seuilAlerte != null && x.stock <= x.seuilAlerte;
      });
      return {
        valeur: sous.length, unite: 'article(s)',
        question: 'sont sous leur seuil d’alerte',
        vide: 'Aucun article sous son seuil d’alerte.',
        ton: 'danger', icone: 'package-x',
        ecran: 'm6-alertes', lienLabel: 'Voir les alertes',
        note: 'Un seuil NON FIXÉ n’est pas un seuil de zéro : les articles sans seuil sont comptés à '
          + 'part et ne peuvent déclencher aucune alerte.',
      };
      },
      alerte: bandeauAlertes,
      kpis: function () {
        var p = produits();
        return [
          { label: 'Références gérées', value: C.num(p.length), icon: 'package', tone: 'navy' },
          { label: 'Valeur totale du stock', value: C.money(C.sum(p, function (x) { return x.stock * x.cump; })), icon: 'wallet', tone: 'info', hint: 'Valorisation au CUMP' },
          { label: 'Mouvements du mois', value: C.num(duMois(mouvements(), 'date').length), icon: 'arrow-left-right', tone: 'success' },
          { label: 'Alertes actives', value: C.num(ruptures().length + perimes().length), icon: 'triangle-alert', tone: 'danger' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Faire le point du jour', icone: 'coins', action: 'Point des ventes',
                detail: 'Le geste quotidien : ce qui a été vendu, par qui, à qui.',
                etapes: [
                  { label: 'Point journalier des ventes', ecran: 'm6-point-ventes',
                    detail: 'Détail par client, par article, par groupe. Six périodicités et une plage libre.' },
                  { label: 'Imprimer le point détaillé ou global', ecran: 'm6-point-ventes',
                    detail: 'Les états portent les trois parts : assureur, personnel pris en charge, remises.' },
                  { label: 'Point du stock valorisé', ecran: 'm6-point-stock',
                    detail: 'Restant, reçu, entré, sorti — au magasin et à la pharmacie, avec leur montant.' },
                  { label: 'Remettre à la Direction', poste: 'DAF' },
                ],
              },
              {
                titre: 'Réapprovisionner', icone: 'package-x', action: 'Voir les alertes',
                detail: 'Un article est passé sous son seuil.',
                etapes: [
                  { label: 'Lire les alertes de rupture', ecran: 'm6-alertes',
                    detail: 'Une sortie qui fait passer sous le seuil ouvre la tâche AU MOMENT où elle a lieu.' },
                  { label: 'Établir le bon d’expression de besoins', ecran: 'm7-besoins',
                    detail: 'Quantité demandée et quantité accordée sont deux colonnes distinctes.' },
                  { label: 'Faire valider par la Direction', poste: 'DAF', detail: 'RG-04.' },
                  { label: 'Passer commande', ecran: 'm7-commandes' },
                  { label: 'Réceptionner et mettre à jour le CUMP', ecran: 'm7-receptions' },
                ],
              },
              {
                titre: 'Transférer vers la pharmacie', icone: 'arrow-left-right', action: 'Nouveau transfert',
                detail: 'Le magasin approvisionne le détail.',
                etapes: [
                  { label: 'Composer le bon multi-articles', ecran: 'm6-transferts',
                    detail: 'Un seul bon pour tout le voyage — pas un bon par référence.' },
                  { label: 'Le stock de détail est crédité', ecran: 'm6-produits' },
                  { label: 'La pharmacie délivre', poste: 'Caisse' },
                ],
              },
              {
                titre: 'Surveiller les péremptions', icone: 'calendar-x', action: 'FEFO',
                detail: 'Premier périmé, premier sorti.',
                etapes: [
                  { label: 'Contrôler les lots proches de péremption', ecran: 'm6-lots', detail: 'RG-05.' },
                  { label: 'Déclarer les pertes constatées', ecran: 'm6-pertes',
                    detail: 'Une perte s’enregistre comme un mouvement : elle n’existe qu’une fois.' },
                ],
              },
              {
                titre: 'Inventaire', icone: 'clipboard-list', action: 'Inventorier',
                detail: 'Comptage périodique.',
                etapes: [
                  { label: 'Saisir le comptage', ecran: 'm6-inventaire' },
                  { label: 'Expliquer les écarts', ecran: 'm6-inventaire' },
                  { label: 'La Direction valide', poste: 'DAF' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Derniers mouvements',
          actions: function () { return [K.lien('m6-mouvements', 'Registre complet', { size: 'sm', icon: 'arrow-right' })]; },
          render: function () {
            return K.miniTable([
              { label: 'Date', render: function (m) { return C.dateFR(m.date); } },
              { label: 'Produit', key: 'produit' },
              { label: 'Type', render: function (m) {
                var t = D.TYPES_MOUVEMENT.filter(function (x) { return x.id === m.type; })[0];
                return U.badge(m.typeLabel, t ? t.badge : 'neutral');
              } },
              { label: 'Quantité', align: 'right', key: 'quantite' },
              { label: 'Justificatif', key: 'justificatif' },
              { label: 'Opérateur', key: 'utilisateur' },
            ], mouvements().slice(0, 10));
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Valeur du stock par catégorie',
                render: function () {
                  var g = C.groupBy(produits(), 'categorie');
                  var keys = Object.keys(g);
                  return G.barres(
                    keys.map(function (k) {
                      var c = D.CATEGORIES_PRODUIT.filter(function (x) { return x.id === k; })[0];
                      return c ? c.label : k;
                    }),
                    [{ label: 'Valeur (FCFA)', data: keys.map(function (k) { return C.sum(g[k], function (p) { return p.stock * p.cump; }); }) }],
                    { horizontal: true, height: 300 });
                },
              },
              {
                title: 'Répartition des mouvements',
                render: function () {
                  var g = C.groupBy(mouvements(), 'typeLabel');
                  var keys = Object.keys(g);
                  return G.anneau(keys, keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm7-besoins', icon: 'clipboard-list', label: 'Bons d’expression de besoins', detail: 'Quantité demandée / accordée' },
              { id: 'm7-commandes', icon: 'truck', label: 'Bons de commande', detail: 'Validation DA requise (RG-04)' },
              { id: 'm6-inventaire', icon: 'clipboard-check', label: 'Inventaire', detail: 'Écarts physique / théorique' },
              { id: 'm6-pertes', icon: 'trash-2', label: 'Pertes et casses', detail: 'Valorisation comptable' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * CAISSE
   * ======================================================================== */
  global.SIGH.screen('dash-caissier', {
    title: 'Tableau de bord — Caisse',
    description: 'Encaissements du jour, factures à régler, reliquats et répartition des modes de paiement.',
    render: K.dash({
      /* Fondement : la file d'attente de l'encaissement. Le caissier ne choisit pas
       * ce qu'il fait — la file le lui dit. La pharmacie lui étant rattachée
       * (décision du 24/08/2026), il voit aussi les délivrances bloquées. */
      premierRegard: function () {
      var taches = S.collection('taches').active().filter(function (t) {
        return t.type === 'encaissement' && t.statut !== 'fait';
      });
      return {
        valeur: taches.length, unite: 'prescription(s)',
        question: 'attendent d’être encaissées',
        vide: 'Aucune prescription en attente de règlement.',
        ton: 'warning', icone: 'coins',
        ecran: 'm8-caisse', lienLabel: 'Encaisser',
        note: 'Chaque encaissement débloque aussitôt la délivrance en pharmacie et le prélèvement au '
          + 'laboratoire — tant qu’il n’a pas lieu, le patient attend à deux endroits.',
      };
      },
      alerte: fileDuPoste('encaissement', {
        titre: 'Prescriptions à encaisser',
        vide: 'Aucune prescription en attente de règlement.',
        icon: 'arrow-right', action: 'Ouvrir la caisse',
        onAction: function () { global.SIGH.app.go('m8-caisse'); },
      }),
      kpis: function () {
        var fj = duJour(factures(), 'date');
        var f = factures();
        return [
          { label: 'Encaissé aujourd’hui', value: C.money(C.sum(fj, 'montantPaye')), icon: 'banknote', tone: 'success' },
          { label: 'Factures du jour', value: C.num(fj.length), icon: 'receipt', tone: 'navy' },
          { label: 'Reliquats en cours', value: C.money(C.sum(f, 'reliquat')), icon: 'hand-coins', tone: 'warning' },
          { label: 'Factures impayées', value: C.num(f.filter(function (x) { return x.statutPaiement === 'impayee'; }).length), icon: 'file-x', tone: 'danger' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Encaisser une prescription', icone: 'coins', action: 'Encaisser',
                detail: 'Le patient se présente avec son ordonnance.',
                etapes: [
                  { label: 'Cocher les prestations réglées', ecran: 'm8-caisse',
                    detail: 'Le patient peut ne payer qu’une partie : cochez CE QU’IL RÈGLE.' },
                  { label: 'Imprimer le reçu détaillé', ecran: 'm8-caisse',
                    detail: 'Il NOMME les prestations réglées et celles qui restent dues.' },
                  { label: 'Le laboratoire est débloqué', poste: 'Laboratoire',
                    detail: 'Exactement les examens payés, pas les autres.' },
                  { label: 'La pharmacie est débloquée', poste: 'Pharmacie' },
                  { label: 'L’écriture comptable est posée', poste: 'Comptabilité' },
                ],
              },
              {
                titre: 'Le patient revient payer le reste', icone: 'wallet', action: 'Reprendre',
                detail: 'Il avait réglé une partie.',
                etapes: [
                  { label: 'Retrouver sa pièce du jour', ecran: 'm8-caisse',
                    detail: 'Le registre dit ce qui est réglé et ce qui reste, prestation par prestation.' },
                  { label: 'Encaisser le reste', ecran: 'm8-caisse' },
                  { label: 'Réimprimer le reçu', ecran: 'm8-caisse' },
                ],
              },
              {
                titre: 'Délivrer un médicament', icone: 'pill', action: 'Pharmacie',
                detail: 'La pharmacie est rattachée à votre compte.',
                etapes: [
                  { label: 'Voie orale — le patient emporte', ecran: 'm6-pharmacie-externe' },
                  { label: 'Urgence — vers la salle de soins', ecran: 'm6-pharmacie-interne',
                    detail: 'Le produit ne quitte pas la clinique : c’est le soignant qui l’administre.' },
                  { label: 'Le stock est décrémenté avec justificatif', detail: 'RG-03.' },
                ],
              },
              {
                titre: 'Arrêter la caisse', icone: 'calculator', action: 'Arrêté du jour',
                detail: 'En fin de journée.',
                etapes: [
                  { label: 'Éditer l’arrêté de caisse', ecran: 'm8-caisse' },
                  { label: 'Vérifier le point des ventes du jour', ecran: 'm6-point-ventes',
                    detail: 'Le détail par client : c’est là qu’un écart de caisse se retrouve.' },
                  { label: 'Remettre à la Direction', poste: 'DAF' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Dernières factures',
          actions: function () {
            return [
              K.lien('m8-facturation', 'Nouvelle facture', { size: 'sm', icon: 'plus', variant: 'primary' }),
              K.lien('m8-caisse', 'État de caisse', { size: 'sm', icon: 'printer' }),
            ];
          },
          render: function () {
            return K.miniTable([
              { label: 'N° facture', render: function (f) { return el('span.font-mono.text-xs', { text: f.numero }); } },
              { label: 'Patient', key: 'patient' },
              { label: 'Type', key: 'type' },
              { label: 'Montant', align: 'right', render: function (f) { return C.money(f.montantTTC, false); } },
              { label: 'Payé', align: 'right', render: function (f) { return C.money(f.montantPaye, false); } },
              { label: 'Reste', align: 'right', render: function (f) { return f.reliquat > 0 ? el('span.font-semibold.text-danger-600', { text: C.money(f.reliquat, false) }) : '—'; } },
              { label: 'Statut', render: function (f) { return U.statut(f.statutPaiement); } },
            ], factures().slice(0, 10));
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Encaissements par mode de paiement',
                render: function () {
                  var g = C.groupBy(factures(), 'modePaiement');
                  var keys = Object.keys(g);
                  return G.barres(
                    keys.map(function (k) {
                      var m = D.MODES_PAIEMENT.filter(function (x) { return x.id === k; })[0];
                      return m ? m.label : k;
                    }),
                    [{ label: 'Montant encaissé', data: keys.map(function (k) { return C.sum(g[k], 'montantPaye'); }) }],
                    { horizontal: true, height: 260 });
                },
              },
              {
                title: 'Recettes quotidiennes du mois',
                render: function () {
                  var jours = [], data = [];
                  for (var d = 1; d <= AUJ.getDate(); d++) {
                    var jour = new Date(2026, 7, d);
                    jours.push(String(d));
                    data.push(C.sum(factures().filter(function (f) { return C.iso(f.date) === C.iso(jour); }), 'montantPaye'));
                  }
                  return G.ligne(jours, [{ label: 'Encaissé', data: data, color: G.TONES.vert }]);
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm8-facturation', icon: 'file-plus-2', label: 'Nouvelle facture', detail: 'Consultation, acte, produit' },
              { id: 'm8-paiements', icon: 'banknote', label: 'Encaisser un paiement', detail: 'Espèces, mobile money, carte' },
              { id: 'm8-reliquats', icon: 'coins', label: 'Reliquats', detail: 'Restes à recouvrer' },
              { id: 'm8-caisse', icon: 'calculator', label: 'État de caisse', detail: 'Arrêté journalier à imprimer' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * COMPTABILITÉ
   * ======================================================================== */
  global.SIGH.screen('dash-comptable', {
    title: 'Tableau de bord — Comptabilité',
    description: 'Écritures SYSCOHADA, équilibre des journaux, créances, dettes et rapprochements bancaires.',
    render: K.dash({
      /* Fondement : les écritures nées de la caisse arrivent en BROUILLON — la
       * validation comptable reste un geste humain. C'est donc la pile de
       * brouillons qui attend le comptable. */
      premierRegard: function () {
      var brouillons = S.collection('ecritures').active().filter(function (e) {
        return e.statut === 'brouillon' || e.etat === 'brouillon';
      });
      return {
        valeur: brouillons.length, unite: 'écriture(s) en brouillon',
        question: 'attendent votre validation',
        vide: 'Aucune écriture en attente de validation.',
        ton: 'warning', icone: 'file-check-2',
        ecran: 'm12-ecritures', lienLabel: 'Valider les écritures',
        note: 'L’encaissement pose l’écriture ; la valider reste un geste humain. Sans cela, la recette '
          + 'se ressaisirait à la main — ce que la clinique fait aujourd’hui entre PERFECTO et la caisse.',
      };
      },
      kpis: function () {
        var e = ecritures();
        var debit = C.sum(e, 'debit'), credit = C.sum(e, 'credit');
        return [
          { label: 'Écritures de l’exercice', value: C.num(e.length), icon: 'book-open-check', tone: 'navy' },
          { label: 'Total débit', value: C.money(debit), icon: 'arrow-down-left', tone: 'info' },
          { label: 'Total crédit', value: C.money(credit), icon: 'arrow-up-right', tone: 'info' },
          {
            label: 'Équilibre (RG-10)', value: debit === credit ? 'Équilibré' : C.money(Math.abs(debit - credit)),
            icon: debit === credit ? 'scale' : 'scale-3d', tone: debit === credit ? 'success' : 'danger',
            hint: debit === credit ? 'Débit = Crédit' : 'Écart à régulariser',
          },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Valider les écritures du jour', icone: 'file-check-2', action: 'Écritures',
                detail: 'La caisse a posé des brouillons.',
                etapes: [
                  { label: 'Relire les écritures en brouillon', ecran: 'm12-ecritures',
                    detail: 'Chaque encaissement en pose une : 571 Caisse, 411 Clients, 706 Prestations.' },
                  { label: 'Vérifier l’équilibre', ecran: 'm12-ecritures', detail: 'RG-10 — débit = crédit.' },
                  { label: 'Valider', ecran: 'm12-ecritures',
                    detail: 'C’est un geste humain : sans lui, la recette se ressaisirait à la main.' },
                ],
              },
              {
                titre: 'Déclarer et payer', icone: 'siren', action: 'Échéances',
                detail: 'Impôts, CNSS, CCIB.',
                etapes: [
                  { label: 'Voir les échéances dues', ecran: 'm12-echeances',
                    detail: 'Une échéance tombant un week-end est reportée, jamais avancée.' },
                  { label: 'Déclarer puis payer', ecran: 'm12-echeances' },
                  { label: 'Enregistrer la quittance', ecran: 'm12-echeances' },
                ],
              },
              {
                titre: 'Clôturer le mois', icone: 'book-open', action: 'États',
                detail: 'Arrêté mensuel.',
                etapes: [
                  { label: 'Rapprochement bancaire', ecran: 'm12-banques' },
                  { label: 'Balance et grand livre', ecran: 'm12-balance' },
                  { label: 'États financiers', ecran: 'm12-etats-financiers' },
                  { label: 'Compte rendu à la hiérarchie', poste: 'DAF' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Dernières écritures',
          actions: function () { return [K.lien('m12-ecritures', 'Toutes les écritures', { size: 'sm', icon: 'arrow-right' })]; },
          render: function () {
            return K.miniTable([
              { label: 'N°', render: function (e) { return el('span.font-mono.text-xs', { text: e.numero }); } },
              { label: 'Date', render: function (e) { return C.dateFR(e.date); } },
              { label: 'Journal', render: function (e) { return U.badge(e.journal, 'navy'); } },
              { label: 'Compte', render: function (e) { return el('span.font-mono.text-xs', { text: e.compte }); } },
              { label: 'Libellé', key: 'libelle' },
              { label: 'Débit', align: 'right', render: function (e) { return e.debit ? C.money(e.debit, false) : '—'; } },
              { label: 'Crédit', align: 'right', render: function (e) { return e.credit ? C.money(e.credit, false) : '—'; } },
            ], ecritures().slice(0, 10));
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Écritures par journal',
                render: function () {
                  var g = C.groupBy(ecritures(), 'journal');
                  var keys = Object.keys(g);
                  return G.barres(keys, [{ label: 'Écritures', data: keys.map(function (k) { return g[k].length; }) }]);
                },
              },
              {
                title: 'Charges par centre de coûts',
                render: function () {
                  var g = C.groupBy(ecritures().filter(function (e) { return e.debit > 0; }), 'centreCout');
                  var keys = Object.keys(g);
                  return G.anneau(
                    keys.map(function (k) {
                      var c = D.CENTRES_COUT.filter(function (x) { return x.id === k; })[0];
                      return c ? c.label : k;
                    }),
                    keys.map(function (k) { return C.sum(g[k], 'debit'); }), { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm12-grand-livre', icon: 'book-open', label: 'Grand livre', detail: 'Par compte SYSCOHADA' },
              { id: 'm12-balance', icon: 'scale', label: 'Balance', detail: 'Générale et âgée' },
              { id: 'm12-banques', icon: 'landmark', label: 'Rapprochements', detail: 'Relevés bancaires' },
              { id: 'm12-etats-financiers', icon: 'file-spreadsheet', label: 'États financiers', detail: 'Bilan et compte de résultat' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * RESSOURCES HUMAINES
   * ======================================================================== */
  global.SIGH.screen('dash-rh', {
    title: 'Tableau de bord — Ressources humaines',
    description: 'Effectif, plannings, présences, évaluations NS 131, primes NS 132 et masse salariale.',
    render: K.dash({
      /* Fondement : le compte RH est FERMÉ depuis le 24/08/2026 et les ressources
       * humaines sont rattachées à la DAF. Recréable. */
      premierRegard: function () {
      return {
        valeur: 0, unite: '',
        question: '',
        vide: 'Le compte RH a été fermé — les ressources humaines relèvent de la DAF.',
        ton: 'warning', icone: 'info',
        note: 'Décision de la Direction du 24/08/2026. Le rôle est archivé, non supprimé : la Direction '
          + 'pourra le recréer depuis la matrice des droits sans retoucher le logiciel.',
      };
      },
      kpis: function () {
        var p = personnel();
        return [
          { label: 'Effectif total', value: C.num(p.length), icon: 'users-round', tone: 'navy', hint: 'Organigramme : 44 agents' },
          { label: 'Masse salariale (base)', value: C.money(C.sum(p, 'salaireBase')), icon: 'banknote', tone: 'info' },
          { label: 'Agents de garde aujourd’hui', value: C.num(col('planning').active().filter(function (x) { return x.date === C.iso(AUJ) && x.type === 'garde'; }).length), icon: 'moon', tone: 'warning' },
          { label: 'Évaluations du mois', value: C.num(p.length), icon: 'clipboard-check', tone: 'success', hint: 'Barème NS 131' },
        ];
      },
      sections: [
        {
          title: 'Effectif par fonction',
          actions: function () { return [K.lien('m10-personnel', 'Gérer le personnel', { size: 'sm', icon: 'arrow-right' })]; },
          render: function () {
            var g = C.groupBy(personnel(), 'fonction');
            return K.ranking(Object.keys(g).map(function (k) {
              var f = D.FONCTIONS.filter(function (x) { return x.id === k; })[0];
              return { label: f ? f.label : k, value: g[k].length };
            }).sort(function (a, b) { return b.value - a.value; }));
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Répartition du personnel par service',
                render: function () {
                  var g = C.groupBy(personnel(), 'service');
                  var keys = Object.keys(g);
                  return G.anneau(keys, keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
                },
              },
              {
                title: 'Planning du jour',
                render: function () {
                  var pl = col('planning').active().filter(function (x) { return x.date === C.iso(AUJ); });
                  var g = C.groupBy(pl, 'type');
                  var keys = Object.keys(g);
                  return G.barres(
                    keys.map(function (k) {
                      var t = D.TYPES_PLANNING.filter(function (x) { return x.id === k; })[0];
                      return t ? t.label : k;
                    }),
                    [{ label: 'Agents', data: keys.map(function (k) { return g[k].length; }) }],
                    { horizontal: true, height: 240 });
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm10-planning', icon: 'calendar-days', label: 'Planning & gardes', detail: 'Garde 24h, permanence' },
              { id: 'm10-evaluations', icon: 'clipboard-check', label: 'Évaluations NS 131', detail: '4 critères, barème de sanction' },
              { id: 'm10-primes', icon: 'gift', label: 'Primes NS 132', detail: 'Grille par fonction' },
              { id: 'm11-calcul', icon: 'calculator', label: 'Calcul de la paie', detail: 'CNSS, ITS, VPS' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * ACCUEIL / RÉCEPTION
   * ======================================================================== */
  global.SIGH.screen('dash-receptionniste', {
    title: 'Tableau de bord — Accueil',
    description: 'Création de dossiers, rendez-vous du jour, visites et orientation des patients.',
    render: K.dash({
      /* Fondement : RG-09 — la validité de la carte est la PREMIÈRE question posée
       * au guichet, et elle décide de la facturation. Vient ensuite la file. */
      premierRegard: function () {
      var attente = S.collection('fileAttente').active().filter(function (t) {
        return t.etat === 'attente';
      });
      return {
        valeur: attente.length, unite: 'patient(s)',
        question: 'attendent d’être appelés',
        vide: 'Personne n’attend à l’accueil.',
        ton: 'navy', icone: 'users',
        ecran: 'm2-file-attente', lienLabel: 'File d’attente',
        note: 'L’ordre d’arrivée gouverne, sauf urgence. Vérifiez la validité de la carte d’assurance '
          + 'à l’enregistrement : c’est elle qui décide de la facturation (RG-09).',
      };
      },
      kpis: function () {
        return [
          { label: 'Dossiers créés ce mois', value: C.num(duMois(patients(), 'dateCreation').length), icon: 'user-plus', tone: 'success' },
          { label: 'Rendez-vous du jour', value: C.num(duJour(consultations(), 'date').length), icon: 'calendar-check', tone: 'navy' },
          { label: 'Patients au répertoire', value: C.num(patients().length), icon: 'users', tone: 'info' },
          { label: 'Cartes d’assurance expirées', value: C.num(patients().filter(function (p) { return p.assureur && C.toDate(p.carteExpiration) < AUJ; }).length), icon: 'shield-alert', tone: 'warning' },
        ];
      },
      sections: [
        {
          /* LES SIX BOUTONS DU BUG 2 (Instructions) — posés AVANT les parcours :
             le kit place la section « Accès rapides » en tête des sections
             rapides, l'ordre demandé est donc structurel, pas accidentel. */
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm1-patients', icon: 'users', label: 'Répertoire patient' },
              { id: 'm1-constantes', icon: 'activity', label: 'Constantes à l’accueil' },
              { id: 'm2-rendezvous', icon: 'calendar-plus', label: 'Agenda et rendez-vous' },
              { id: 'm3-visites-patients', icon: 'door-open', label: 'Visites aux hospitalisés' },
              { id: 'm2-file-attente', icon: 'list-ordered', label: 'File d’attente' },
              { id: 'm2-affichage', icon: 'monitor', label: 'Écran d’appel des patients' },
            ]);
          },
        },
        {
          title: 'Rendez-vous et consultations du jour',
          actions: function () { return [K.lien('m2-agenda', 'Agenda complet', { size: 'sm', icon: 'calendar' })]; },
          render: function () {
            var cj = C.sortBy(duJour(consultations(), 'date'), 'date');
            if (!cj.length) return U.empty('Aucun rendez-vous programmé aujourd’hui.', { icon: 'calendar' });
            return K.miniTable([
              { label: 'Heure', render: function (c) { return C.heure(c.date); } },
              { label: 'Dossier', render: function (c) { return el('span.font-mono.text-xs', { text: c.patientCode }); } },
              { label: 'Patient', key: 'patient' },
              { label: 'Motif', key: 'motif' },
              { label: 'Praticien', key: 'medecin' },
              { label: 'Statut', render: function (c) { return U.statut(c.statut); } },
            ], cj);
          },
        },
        {
          title: 'Ce que vous faites ici — les parcours de l’accueil',
          /* Remontée AVANT les indicateurs : c est par là qu on commence sa
             journée. Un mode d emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            /* Les onze chaînes dictées par la Direction, dans son ordre. Chacune
               montre la SUITE : l'accueil doit savoir quel poste prend le relais,
               faute de quoi il traite son geste comme une fin en soi et le
               patient arrive à la caisse sans que la caisse sache pourquoi. */
            return K.parcours([
              {
                titre: 'Nouveau patient', icone: 'user-plus', action: 'Ouvrir un dossier',
                detail: 'Le patient n’a jamais été reçu à la clinique.',
                etapes: [
                  { label: 'Créer le dossier patient', ecran: 'm1-patients',
                    detail: 'Code CNT/[n°]/[année] attribué automatiquement — RG-01, non modifiable ensuite.' },
                  { label: 'Relever les constantes', ecran: 'm1-constantes',
                    detail: 'Température, TA, pouls, SpO₂, poids, taille. Elles alimentent la feuille de surveillance.' },
                  { label: 'Inscrire à la file d’attente', ecran: 'm2-file-attente' },
                  /* Le dossier de consultation est la ZONE 2 : il appartient au
                     soignant (14/09/2026). L'étape est nommée, pas offerte. */
                  { label: 'Le soignant ouvre le dossier de consultation', poste: 'Consultation' },
                ],
              },
              {
                titre: 'Rendez-vous de consultation', icone: 'calendar-plus', action: 'Prendre le rendez-vous',
                detail: 'Le patient appelle ou se présente pour une date à venir.',
                etapes: [
                  { label: 'Prendre le rendez-vous', ecran: 'm2-rendezvous',
                    detail: 'Généraliste et sage-femme sept jours sur sept ; chirurgien-gynécologue les lundi et jeudi.' },
                  { label: 'Vérifier ou créer le dossier', ecran: 'm1-patients' },
                  { label: 'Le jour venu : constantes puis file d’attente', ecran: 'm1-constantes' },
                  { label: 'Le soignant reçoit', poste: 'Consultation' },
                  { label: 'Règlement', poste: 'Caisse' },
                ],
              },
              {
                titre: 'Rendez-vous de contrôle', icone: 'calendar-check', action: 'Programmer le contrôle',
                detail: 'Le patient revient après un traitement ou un examen.',
                etapes: [
                  { label: 'Programmer le contrôle', ecran: 'm2-rendezvous',
                    detail: 'Le motif « contrôle » distingue la venue d’une première consultation.' },
                  { label: 'Vérifier que les résultats sont rendus', ecran: 'm5-resultats',
                    detail: 'Un contrôle sans son résultat fait revenir le patient pour rien.' },
                  { label: 'Relever les constantes à l’arrivée', ecran: 'm1-constantes' },
                  { label: 'Le soignant reçoit', poste: 'Consultation' },
                ],
              },
              {
                titre: 'Patient référé par un autre centre', icone: 'download', action: 'Enregistrer la référence',
                detail: 'Le patient arrive avec sa fiche de référence.',
                etapes: [
                  { label: 'Enregistrer la fiche de référence entrante', ecran: 'm1-reference',
                    detail: 'La pièce d’origine est conservée et numérisée : elle porte ce que le centre a déjà fait.' },
                  { label: 'Créer le dossier local', ecran: 'm1-patients',
                    detail: 'Sans effacer la pièce d’origine ni sa couverture d’assurance.' },
                  { label: 'Numériser la fiche reçue', ecran: 'm1-documents' },
                  { label: 'Relever les constantes', ecran: 'm1-constantes' },
                  { label: 'Le soignant reçoit', poste: 'Consultation' },
                  { label: 'Renvoyer la contre-référence au centre d’origine', ecran: 'm1-contre-reference',
                    detail: 'Elle dit ce qu’il est advenu du patient — c’est ce que le centre attend.' },
                ],
              },
              {
                titre: 'File d’attente et écran d’appel', icone: 'list-ordered', action: 'Gérer la file',
                detail: 'L’ordre d’arrivée gouverne, sauf urgence.',
                etapes: [
                  { label: 'Inscrire et appeler les patients', ecran: 'm2-file-attente',
                    detail: 'Le rang est calculé : priorité d’abord, heure d’arrivée ensuite. Il ne se saisit pas.' },
                  { label: 'Afficher l’écran d’appel en salle d’attente', ecran: 'm2-affichage',
                    detail: 'Numéros seuls — jamais le nom ni le motif du patient.' },
                ],
              },
              {
                titre: 'Sortie d’hospitalisation', icone: 'log-out', action: 'Préparer la sortie',
                detail: 'Le séjour est terminé, le patient rentre chez lui.',
                etapes: [
                  { label: 'Vérifier que le solde est apuré', ecran: 'm8-reliquats',
                    detail: 'RG-06 — aucune sortie tant qu’un reliquat subsiste.' },
                  { label: 'Établir la fiche de sortie', ecran: 'm3-sorties',
                    detail: 'RG-07 — signature du patient, de l’infirmier et constat du gardien.' },
                  { label: 'Remettre le traitement de sortie', poste: 'Pharmacie' },
                  { label: 'Programmer le contrôle', ecran: 'm2-rendezvous' },
                ],
              },
              {
                titre: 'Sortie contre avis médical', icone: 'triangle-alert', action: 'Enregistrer la sortie',
                detail: 'Le patient part malgré l’avis du médecin.',
                etapes: [
                  { label: 'Recueillir la décharge de responsabilité', ecran: 'm3-sortie-avis-medical',
                    detail: 'RG-08 — le motif est obligatoire, l’avis du Procureur consigné le cas échéant.' },
                  { label: 'Faire signer le patient ou son accompagnant', ecran: 'm3-sortie-avis-medical' },
                  { label: 'Régulariser le solde', ecran: 'm8-reliquats',
                    detail: 'La sortie contre avis n’efface pas la dette.' },
                ],
              },
              {
                titre: 'Registre des appels', icone: 'phone-call', action: 'Ouvrir le registre',
                detail: 'Appels entrants et sortants du standard.',
                etapes: [
                  { label: 'Consigner l’appel', ecran: 'm2-registre-appels',
                    detail: 'Objet, interlocuteur, suite donnée.' },
                  { label: 'Prendre le rendez-vous si l’appel le demande', ecran: 'm2-rendezvous' },
                  { label: 'Appeler l’ambulance si l’appel est une urgence', ecran: 'm13-repertoire-ambulances' },
                ],
              },
              {
                titre: 'Visites aux hospitalisés', icone: 'users-round', action: 'Enregistrer une visite',
                detail: 'Les proches se présentent pour un patient hospitalisé.',
                etapes: [
                  { label: 'Vérifier les heures de visite et enregistrer', ecran: 'm3-visites-patients' },
                  { label: 'Orienter vers la chambre', ecran: 'm3-plan-lits' },
                ],
              },
              {
                titre: 'Annuaire des ambulances', icone: 'ambulance', action: 'Consulter l’annuaire',
                detail: 'Une évacuation est nécessaire.',
                etapes: [
                  { label: 'Appeler un moyen disponible', ecran: 'm13-repertoire-ambulances',
                    detail: 'Les disponibles remontent en tête ; le numéro est cliquable.' },
                  { label: 'Établir la fiche de référence sortante', ecran: 'm1-reference',
                    detail: 'Elle part avec le patient et porte ses constantes et ses traitements reçus.' },
                  { label: 'Consigner l’intervention', ecran: 'm13-ambulance', poste: 'Ambulance' },
                ],
              },
              {
                titre: 'Certificats et attestations', icone: 'stamp', action: 'Délivrer une pièce',
                detail: 'Le patient réclame un certificat.',
                etapes: [
                  { label: 'Délivrer la pièce', ecran: 'm1-pieces',
                    detail: 'Numérotée par sigle et par année. Les certificats ne sont couverts que par SOS.' },
                  { label: 'Encaisser', poste: 'Caisse' },
                ],
              },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * STATISTIQUES MATERNITÉ & NAISSANCES — Pilotage (phase 4)
   * --------------------------------------------------------------------------
   * Les indicateurs DHIS2/SNIS du rapport du 27/08/2026, CALCULÉS depuis les
   * collections du socle — jamais fournis : couverture SP3/SP5, MILDA, GAR,
   * acceptation PF, transferts, vaccinale J0, types d'accouchement, mortalité.
   * ======================================================================== */
  global.SIGH.screen('m4-stats-maternite', {
    title: 'Statistiques maternité & naissances',
    description: 'Indicateurs DHIS2/SNIS : CPN, SP, MILDA, GAR, accouchements, PF, vaccination et mortalité.',
    regle: 'Chaque indicateur est <strong>calculé depuis les registres</strong> (CPN, accouchements, '
      + 'naissances, PF, SONU) — le rapport demande leur agrégation automatique pour la saisie DHIS2, '
      + 'et un chiffre fourni à la main divergerait du registre au premier correctif.',
    render: function (root) {
      var host = el('div.space-y-4');
      var gros = S.collection('grossesses').active();
      var accs = S.collection('accouchements').active();
      var nns = S.collection('naissances').active();
      var pfs = S.collection('planificationFamiliale').active();
      var sonu = S.collection('registreSONU').active();
      var curatifs = S.collection('soinsCuratifsMaternite').active();

      function pctDe(n, total) { return C.pct(total ? n / total * 100 : 0); }

      var sp3 = gros.filter(function (g) { return (g.sp || []).indexOf('SP3') !== -1; }).length;
      var sp5 = gros.filter(function (g) { return (g.sp || []).indexOf('SP5') !== -1; }).length;
      var milda = gros.filter(function (g) { return g.milda; }).length;
      var gar = gros.filter(function (g) { return g.gar; }).length;
      var acceptA = pfs.filter(function (p) { return p.acceptante === 'A'; }).length;
      var mortNes = nns.filter(function (n) { return !n.vivant; }).length;
      var refTravail = curatifs.filter(function (r) { return r.urgenceMaternite; }).length;
      var refPec = curatifs.filter(function (r) { return r.urgenceMaternite === 'referee_pec'; }).length;

      host.appendChild(U.kpiGrid([
        { label: 'Couverture SP3', value: pctDe(sp3, gros.length), icon: 'shield-check', tone: 'info', hint: sp3 + ' / ' + gros.length + ' grossesses suivies' },
        { label: 'Couverture MILDA', value: pctDe(milda, gros.length), icon: 'tent', tone: 'success', hint: 'Indicateur DHIS2' },
        { label: 'Grossesses à risque (GAR)', value: pctDe(gar, gros.length), icon: 'triangle-alert', tone: 'danger', hint: gar + ' fiche(s)' },
        { label: 'Nouvelles acceptantes PF', value: pctDe(acceptA, pfs.length), icon: 'heart-handshake', tone: 'navy', hint: acceptA + ' « A » / ' + pfs.length },
      ]));
      host.appendChild(U.kpiGrid([
        { label: 'Couverture SP5', value: pctDe(sp5, gros.length), icon: 'shield', tone: 'info' },
        { label: 'Mort-nés', value: C.num(mortNes), icon: 'cross', tone: mortNes ? 'danger' : 'success', hint: 'sur ' + nns.length + ' naissances' },
        { label: 'Femmes en travail référées', value: C.num(refTravail), icon: 'ambulance', tone: 'warning', hint: refPec + ' prise(s) en charge à l’arrivée' },
        { label: 'Urgences SONUC', value: C.num(sonu.filter(function (s2) { return (s2.fonctions || []).some(function (n) { return n >= 8; }); }).length), icon: 'siren', tone: 'danger' },
      ]));

      host.appendChild(el('div.grid.gap-4.lg\\:grid-cols-2', null, [
        U.card('Types d’accouchement', (function () {
          var g = C.groupBy(accs, function (a) { return a.type || a.voie; });
          var keys = Object.keys(g);
          return G.barres(keys, [{ label: 'Accouchements', data: keys.map(function (k) { return g[k].length; }) }], { height: 260 });
        })()),
        U.card('Méthodes PF adoptées', (function () {
          var g = C.groupBy(pfs, 'methodeLabel');
          var keys = Object.keys(g);
          return G.barres(keys, [{ label: 'Consultations', data: keys.map(function (k) { return g[k].length; }) }], { horizontal: true, height: 260 });
        })()),
      ]));

      host.appendChild(U.card('Vaccination et soins de naissance (J0)', K.miniTable(
        ['Soin', 'Faits', 'Couverture'],
        [['Vitamine K1', 'vitK1'], ['VPO0', 'vpo0'], ['BCG', 'bcg'], ['Hépatite B J0', 'hepB0']]
          .map(function (s2) {
            var n = nns.filter(function (x) { return x[s2[1]]; }).length;
            return [s2[0], String(n), pctDe(n, nns.length)];
          }))));

      host.appendChild(K.source('Rapport officiel maternité du 27/08/2026 — §5.3 : « calcul automatique des '
        + 'indicateurs DHIS2/SNIS ». Les chiffres sont recalculés à chaque affichage depuis les registres.'));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * CHIRURGIEN — phase 2 (31/08/2026)
   * ======================================================================== */
  global.SIGH.screen('dash-chirurgien', {
    title: 'Tableau de bord — Chirurgien',
    description: 'Bloc opératoire : check-listes, comptes rendus, transfusion et suites opératoires.',
    render: K.dash({
      /* Fondement : les deux check-listes de sécurité sont la discipline du
         bloc (vague 27) — une check-liste incomplète est SIGNALÉE, jamais
         refusée, et c'est donc elle qu'on regarde en arrivant. */
      premierRegard: function () {
        var incompletes = S.collection('checklistsBloc').active().filter(function (c) {
          return (c.coches || 0) < (c.total || 0);
        });
        return {
          valeur: incompletes.length, unite: 'check-liste(s)',
          question: 'restent incomplètes au bloc',
          vide: 'Toutes les check-listes du bloc sont complètes.',
          ton: 'warning', icone: 'clipboard-check',
          ecran: 'm3-bloc-checklist', lienLabel: 'Check-listes du bloc',
          note: 'Une check-liste incomplète est signalée, jamais refusée — la compléter après coup '
            + 'vaut mieux que cocher pour avancer.',
        };
      },
      kpis: function () {
        var cro = S.collection('crOperatoires').active();
        var mois = duMois(cro, 'dateOperation');
        var sansAide = mois.filter(function (r) { return !r.aideOperateur; });
        return [
          { label: 'Interventions du mois', value: C.num(mois.length), icon: 'slice', tone: 'danger' },
          { label: 'Comptes rendus opératoires', value: C.num(cro.length), icon: 'file-text', tone: 'navy',
            hint: 'chacun porte ses trois intervenants nommés' },
          { label: 'Sans aide-opérateur', value: C.num(sansAide.length), icon: 'user-minus', tone: 'warning' },
          { label: 'Patients hospitalisés', value: C.num(litsOccupes().length), icon: 'bed-double', tone: 'info' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Opérer et documenter', icone: 'slice', action: 'Check-listes',
                detail: 'De la check-liste d’entrée au compte rendu signé.',
                etapes: [
                  { label: 'Check-liste d’ENTRÉE', ecran: 'm3-bloc-checklist' },
                  { label: 'Intervention, puis check-liste de SORTIE', ecran: 'm3-bloc-checklist' },
                  { label: 'Compte rendu opératoire — trois intervenants nommés', ecran: 'm3-bloc-cro' },
                  { label: 'Prescrire les suites', ecran: 'm2-prescriptions',
                    detail: 'La première administration revient à la salle de soins, les suivantes à l’hospitalisation.' },
                ],
              },
              {
                titre: 'Suivre un opéré', icone: 'activity', action: 'Surveillance',
                etapes: [
                  { label: 'Feuille de surveillance', ecran: 'm3-surveillance' },
                  { label: 'Feuille de température', ecran: 'm3-feuille-temperature' },
                  { label: 'Résultats de laboratoire', ecran: 'm5-resultats' },
                  { label: 'Sortie d’hospitalisation', ecran: 'm3-sorties', poste: 'Caisse',
                    detail: 'Le solde s’apure à la caisse avant la signature de sortie (RG-06).' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm3-bloc-cro', icon: 'file-text', label: 'Comptes rendus opératoires' },
              { id: 'm3-bloc-checklist', icon: 'clipboard-check', label: 'Check-listes du bloc' },
              { id: 'm3-transfusion', icon: 'droplets', label: 'Transfusion' },
              { id: 'm1-patients', icon: 'users', label: 'Répertoire des patients' },
            ]);
          },
        },
        {
          title: 'Périmètre du profil',
          render: function () {
            return K.note('Ce profil n’ouvre <strong>ni la maternité, ni la caisse, ni le stock</strong> — '
              + 'matrice cible des Instructions. Le dossier obstétrical relève de la sage-femme ; une '
              + 'césarienne se documente au bloc (compte rendu opératoire), son suivi obstétrical en '
              + 'maternité.', { tone: 'info', icon: 'shield' });
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * ANESTHÉSISTE — phase 2 (31/08/2026)
   * ======================================================================== */
  global.SIGH.screen('dash-anesthesiste', {
    title: 'Tableau de bord — Anesthésiste',
    description: 'Sécurité péri-opératoire : check-listes d’entrée, Glasgow, transfusion et surveillance.',
    render: K.dash({
      /* Fondement : l'anesthésiste sécurise l'ENTRÉE au bloc — c'est la
         check-liste d'entrée qui conditionne l'induction. */
      premierRegard: function () {
        var entrees = S.collection('checklistsBloc').active().filter(function (c) {
          return c.moment === 'entree' && (c.coches || 0) < (c.total || 0);
        });
        return {
          valeur: entrees.length, unite: 'check-liste(s) d’entrée',
          question: 'sont incomplètes avant induction',
          vide: 'Toutes les check-listes d’entrée sont complètes.',
          ton: 'danger', icone: 'syringe',
          ecran: 'm3-bloc-checklist', lienLabel: 'Check-listes du bloc',
          note: 'La consultation pré-anesthésique (CPA) et la feuille d’anesthésie arrivent en '
            + 'phase 6 du plan — d’ici là, la sécurité d’entrée se tient ici.',
        };
      },
      kpis: function () {
        var cro = S.collection('crOperatoires').active();
        var mois = duMois(cro, 'dateOperation');
        var parType = C.groupBy(mois, 'anesthesie');
        var generales = (parType['Anesthésie générale'] || []).length;
        var rachi = (parType['Rachianesthésie'] || []).length;
        return [
          { label: 'Interventions du mois', value: C.num(mois.length), icon: 'slice', tone: 'danger' },
          { label: 'Anesthésies générales', value: C.num(generales), icon: 'syringe', tone: 'warning' },
          { label: 'Rachianesthésies', value: C.num(rachi), icon: 'syringe', tone: 'info' },
          { label: 'Patients hospitalisés', value: C.num(litsOccupes().length), icon: 'bed-double', tone: 'navy' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Sécuriser une intervention', icone: 'shield-check', action: 'Check-listes',
                etapes: [
                  { label: 'Check-liste d’ENTRÉE — avant induction', ecran: 'm3-bloc-checklist' },
                  { label: 'Surveillance per-opératoire', ecran: 'm3-surveillance' },
                  { label: 'Check-liste de SORTIE', ecran: 'm3-bloc-checklist' },
                  { label: 'Glasgow et réveil', ecran: 'm3-glasgow' },
                ],
              },
              {
                titre: 'Une transfusion au bloc', icone: 'droplets', action: 'Transfusion',
                etapes: [
                  { label: 'Fiche de surveillance transfusionnelle', ecran: 'm3-transfusion' },
                  { label: 'Constantes au lit du patient', ecran: 'm1-constantes' },
                  { label: 'Résultats de laboratoire', ecran: 'm5-resultats' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm3-bloc-checklist', icon: 'clipboard-check', label: 'Check-listes du bloc' },
              { id: 'm3-glasgow', icon: 'brain', label: 'Score de Glasgow' },
              { id: 'm3-transfusion', icon: 'droplets', label: 'Transfusion' },
              { id: 'm5-resultats', icon: 'flask-conical', label: 'Résultats (lecture)' },
            ]);
          },
        },
        {
          title: 'Périmètre du profil',
          render: function () {
            return K.note('Ce profil n’ouvre <strong>ni la maternité, ni la caisse, ni les consultations '
              + 'générales</strong>. Ses écrans propres — consultation pré-anesthésique, feuille '
              + 'd’anesthésie, suites per et post-opératoires — sont prévus en phase 6 du plan et '
              + 'rejoindront l’hospitalisation (M3), dont ce profil hérite.', { tone: 'info', icon: 'shield' });
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * ASSISTANT COMPTABLE — 16ᵉ rôle, phase 2 (31/08/2026)
   * ======================================================================== */
  global.SIGH.screen('dash-aide-comptable', {
    title: 'Tableau de bord — Assistant Comptable',
    description: 'Saisie des dépenses et des écritures, réceptions fournisseurs et suivi des créances.',
    render: K.dash({
      /* Fondement : il SAISIT, le Comptable principal VALIDE. Ce qu'il regarde
         en arrivant, ce sont ses brouillons — les siens et ceux que
         l'encaissement a posés — avant que le Comptable ne passe. */
      premierRegard: function () {
        var brouillons = S.collection('ecritures').active().filter(function (e) {
          return e.statut === 'brouillon' || e.etat === 'brouillon';
        });
        return {
          valeur: brouillons.length, unite: 'écriture(s) en brouillon',
          question: 'attendent la validation du Comptable',
          vide: 'Aucune écriture en brouillon.',
          ton: 'warning', icone: 'file-clock',
          ecran: 'm12-ecritures', lienLabel: 'Écritures',
          note: 'Vous saisissez, le Comptable principal valide — la validation comptable reste un '
            + 'geste humain, et l’annulation ne vous est pas ouverte (D interdit, matrice cible).',
        };
      },
      kpis: function () {
        var ecr = S.collection('ecritures').active();
        var mois = duMois(ecr, 'date');
        var brouillons = ecr.filter(function (e) {
          return e.statut === 'brouillon' || e.etat === 'brouillon';
        });
        var jour = duJour(factures(), 'date');
        var creances = S.collection('factures').active().filter(function (f) {
          return (f.partAssurance || 0) > 0 && f.statutPaiement !== 'soldee';
        });
        return [
          { label: 'Écritures du mois', value: C.num(mois.length), icon: 'book-open', tone: 'navy' },
          { label: 'Brouillons en attente', value: C.num(brouillons.length), icon: 'file-clock', tone: 'warning' },
          { label: 'Pièces de caisse du jour', value: C.num(jour.length), icon: 'receipt', tone: 'info',
            hint: 'le point journalier de la caisse est dans vos activités' },
          { label: 'Créances assurance ouvertes', value: C.num(creances.length), icon: 'shield-alert', tone: 'danger' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Saisir une dépense', icone: 'wallet', action: 'Dépenses',
                etapes: [
                  { label: 'Enregistrer la dépense avec son justificatif', ecran: 'm12-depenses',
                    detail: 'Une dépense sans justificatif n’est pas bloquée, elle est comptée et signalée.' },
                  { label: 'L’écriture naît en brouillon', ecran: 'm12-ecritures' },
                  { label: 'Validation', ecran: 'm12-ecritures', poste: 'Comptable',
                    detail: 'La validation et l’annulation restent au Comptable principal et à la DAF.' },
                ],
              },
              {
                titre: 'Suivre les créances', icone: 'shield-alert', action: 'Créances',
                etapes: [
                  { label: 'État des créances', ecran: 'm9-creances' },
                  { label: 'Relancer la compagnie', ecran: 'm9-relances' },
                  { label: 'Rapprocher le règlement', ecran: 'm12-banques' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm12-depenses', icon: 'wallet', label: 'Dépenses courantes' },
              { id: 'm12-ecritures', icon: 'book-open', label: 'Écritures' },
              { id: 'm9-creances', icon: 'shield-alert', label: 'Créances' },
              { id: 'm7-receptions', icon: 'package-check', label: 'Réceptions fournisseurs' },
            ]);
          },
        },
        {
          title: 'Périmètre du profil',
          render: function () {
            return K.note('Ce profil n’ouvre <strong>aucun écran clinique</strong> (RG-13) et la '
              + '<strong>clôture annuelle lui est fermée</strong> : elle engage l’exercice et reste au '
              + 'Comptable principal et à la DAF. Aucune suppression : D est interdit sur toute la '
              + 'matrice de ce rôle.', { tone: 'info', icon: 'shield' });
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * AGENT ADMINISTRATIF
   * ======================================================================== */
  global.SIGH.screen('dash-admin-agent', {
    title: 'Tableau de bord — Agent administratif',
    description: 'Courriers, réunions, événements, notes de service et gestion documentaire.',
    render: K.dash({
      /* Fondement : l'agent administratif tient les courriers et les échéances de
       * l'établissement. Les courriers en attente de traitement priment. */
      premierRegard: function () {
      var courriers = S.collection('courriers').active().filter(function (x) {
        return x.traitement !== 'traite';
      });
      return {
        valeur: courriers.length, unite: 'courrier(s)',
        question: 'restent à traiter',
        vide: 'Aucun courrier en attente.',
        ton: 'info', icone: 'mail',
        ecran: 'm13-courriers', lienLabel: 'Courriers',
        note: 'Proposition à valider par la Direction : ce que l’agent administratif regarde en premier '
          + 'n’a pas été précisé.',
      };
      },
      kpis: function () {
        /* Comptés depuis les collections — un indicateur écrit en dur affiche
           la même valeur quoi qu'il se passe, ce qui est pire qu'aucun
           indicateur (le badge « 4 » de la vague 36). */
        var cour = duMois(S.collection('courriers').active(), 'date');
        var arrivees = cour.filter(function (c) { return c.sens === 'arrivee'; }).length;
        var aVenir = S.collection('reunions').active().filter(function (r) {
          return C.toDate(r.date) >= AUJ;
        });
        var notes = [D.NS131, D.NS132];
        var aValider = S.collection('documents').active().filter(function (d) {
          return d.etatValidation === 'en_attente';
        });
        return [
          { label: 'Courriers du mois', value: C.num(cour.length), icon: 'mail', tone: 'navy',
            hint: arrivees + ' arrivée(s), ' + (cour.length - arrivees) + ' départ(s)' },
          { label: 'Réunions planifiées', value: C.num(aVenir.length), icon: 'users', tone: 'info' },
          { label: 'Notes de service actives', value: C.num(notes.length), icon: 'file-text', tone: 'success', hint: 'NS 131 et NS 132' },
          { label: 'Documents à valider', value: C.num(aValider.length), icon: 'file-clock', tone: 'warning' },
        ];
      },
      sections: [
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm13-courriers', icon: 'mail', label: 'Courriers', detail: 'Départ et arrivée' },
              { id: 'm13-reunions', icon: 'users', label: 'Réunions', detail: 'Convocations et comptes rendus' },
              { id: 'm13-notes-service', icon: 'file-text', label: 'Notes de service', detail: 'Versions en vigueur' },
              { id: 'ged-bibliotheque', icon: 'folder-open', label: 'Gestion documentaire', detail: 'Bibliothèque et archivage' },
            ]);
          },
        },
        {
          title: 'Notes de service en vigueur',
          render: function () {
            return K.miniTable([
              { label: 'Référence', render: function (n) { return el('span.font-mono.text-xs', { text: n.reference }); } },
              { label: 'Objet', key: 'objet' },
              { label: 'Signature', render: function (n) { return C.dateFR(n.dateSignature); } },
              { label: 'Statut', render: function (n) { return U.badge(n.statut, 'success'); } },
            ], [D.NS131, D.NS132]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * AMBULANCE
   * ======================================================================== */
  global.SIGH.screen('dash-ambulancier', {
    title: 'Tableau de bord — Ambulance',
    description: 'Interventions, transports sanitaires, consultations et soins à domicile.',
    render: K.dash({
      /* Fondement : l'ambulancier attend une demande. Sans demande, il n'a rien à
       * regarder — et le dire vaut mieux qu'un tableau vide. */
      premierRegard: function () {
      var inter = S.collection('ambulance').active().filter(function (x) {
        return x.statut !== 'archive' && (x.etat === 'demandee' || x.etat === 'en_cours');
      });
      return {
        valeur: inter.length, unite: 'intervention(s)',
        question: 'sont demandées ou en cours',
        vide: 'Aucune intervention en cours.',
        ton: 'danger', icone: 'ambulance',
        ecran: 'm13-ambulance', lienLabel: 'Interventions',
        note: 'La fiche de référence porte les heures de départ et d’arrivée : c’est vous qui les '
          + 'renseignez, et elles font foi.',
      };
      },
      kpis: function () {
        /* Comptés depuis la collection — mêmes champs que l'écran
           m13-ambulance (dateHeure, kilometrage, etat). */
        var toutes = S.collection('ambulance').active();
        var mois = duMois(toutes, 'dateHeure');
        var demandees = toutes.filter(function (x) { return x.etat === 'demandee'; });
        return [
          { label: 'Interventions du mois', value: C.num(mois.length), icon: 'ambulance', tone: 'danger' },
          { label: 'Transports programmés', value: C.num(demandees.length), icon: 'calendar-clock', tone: 'warning' },
          { label: 'Soins à domicile', value: C.num(consultations().filter(function (c) { return c.type === 'Domicile'; }).length), icon: 'house-plus', tone: 'info' },
          { label: 'Kilométrage du mois', value: C.num(C.sum(mois, 'kilometrage')) + ' km', icon: 'route', tone: 'neutral' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Assurer une évacuation', icone: 'ambulance', action: 'Interventions',
                detail: 'Un transfert est demandé.',
                etapes: [
                  { label: 'Prendre l’intervention', ecran: 'm13-ambulance' },
                  { label: 'Emporter la fiche de référence', ecran: 'm1-reference',
                    detail: 'Elle porte les constantes et les traitements déjà donnés.' },
                  { label: 'Renseigner départ et arrivée', ecran: 'm1-reference',
                    detail: 'Ces heures font foi : c’est vous qui les inscrivez.' },
                  { label: 'Clore l’intervention', ecran: 'm13-ambulance' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Consultations et soins à domicile',
          actions: function () { return [K.lien('m2-domicile', 'Planifier', { size: 'sm', icon: 'plus' })]; },
          render: function () {
            var dom = consultations().filter(function (c) { return c.type === 'Domicile'; }).slice(0, 10);
            if (!dom.length) return U.empty('Aucune intervention à domicile enregistrée.', { icon: 'house' });
            return K.miniTable([
              { label: 'Date', render: function (c) { return C.dateFR(c.date); } },
              { label: 'Patient', key: 'patient' },
              { label: 'Motif', key: 'motif' },
              { label: 'Praticien', key: 'medecin' },
              { label: 'Statut', render: function (c) { return U.statut(c.statut); } },
            ], dom);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm13-ambulance', icon: 'ambulance', label: 'Interventions', detail: 'Registre des sorties' },
              { id: 'm2-domicile', icon: 'house-plus', label: 'Soins à domicile', detail: 'Planification et facturation' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * ESPACE PATIENT (consultation par le personnel d'accueil)
   * ======================================================================== */
  global.SIGH.screen('dash-patient', {
    title: 'Espace patient',
    description: 'Vue synthétique remise au patient : parcours de soins, prescriptions, analyses et situation financière.',
    regle: 'Le patient ne dispose d’aucun accès direct au système (CDCT §5) : cet écran est destiné au personnel d’accueil et de caisse pour l’informer et lui remettre ses documents.',
    render: function (root) {
      var pats = patients();
      var host = el('div.space-y-4');
      var courant = pats[0];

      host.appendChild(U.card('Accès rapides', K.shortcuts([
        { id: 'm1-patients', icon: 'users', label: 'Répertoire des patients', detail: 'Rechercher ou créer un dossier' },
        { id: 'm2-rendezvous', icon: 'calendar-check', label: 'Rendez-vous', detail: 'Programmer une consultation' },
        { id: 'm8-facturation', icon: 'file-plus-2', label: 'Nouvelle facture', detail: 'Établir la note du patient' },
        { id: 'm1-documents', icon: 'paperclip', label: 'Documents du patient', detail: 'Pièces numérisées à remettre' },
      ])));

      var barre = el('div.card');
      var body = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      var listePat = C.sortBy(pats, 'code');
      var sel = U.combo(listePat.map(function (p) {
        return { value: p.id, label: p.nom + ' ' + p.prenom, detail: p.code + ' — ' + p.quartier, icon: 'user' };
      }), {
        value: listePat.length ? listePat[0].id : '',
        searchPlaceholder: 'Nom, prénom ou code CNT…',
        placeholder: 'Choisir un patient',
      });
      sel.classList.add('max-w-md');
      body.appendChild(el('div.flex-1', null, [el('label.label', { text: 'Patient' }), sel]));
      barre.appendChild(body);
      host.appendChild(barre);

      var vue = el('div.space-y-4');
      host.appendChild(vue);

      function afficher() {
        courant = pats.filter(function (p) { return p.id === sel.value; })[0] || pats[0];
        C.clear(vue);
        if (!courant) { vue.appendChild(U.empty('Aucun patient.', { icon: 'users' })); return; }

        var cons = consultations().filter(function (c) { return c.patientId === courant.id; });
        var fac = factures().filter(function (f) { return f.patientId === courant.id; });
        var adm = admissions().filter(function (a) { return a.patientId === courant.id; });
        var du = C.sum(fac, 'reliquat');

        vue.appendChild(U.kpiGrid([
          { label: 'Consultations', value: C.num(cons.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'Hospitalisations', value: C.num(adm.length), icon: 'bed-double', tone: 'info' },
          { label: 'Total facturé', value: C.money(C.sum(fac, 'montantTTC')), icon: 'receipt', tone: 'neutral' },
          { label: 'Reste à payer', value: C.money(du), icon: 'wallet', tone: du > 0 ? 'danger' : 'success' },
        ]));

        vue.appendChild(U.card('Parcours de soins', U.timeline(
          C.sortBy(cons, 'date', 'desc').slice(0, 8).map(function (c) {
            return {
              title: c.motif + ' — ' + c.diagnostic,
              detail: c.type + ' avec ' + c.medecin,
              date: C.dateFR(c.date),
              tone: c.statut === 'terminee' ? 'success' : 'info',
            };
          })
        ), [K.btn('Remettre la fiche', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Situation du patient',
              sousTitre: 'Dossier ' + courant.code,
              cartouche: [['Patient', courant.nom + ' ' + courant.prenom], ['Dossier', courant.code],
                ['Consultations', C.num(cons.length)], ['Reste à payer', C.money(du)]],
              contenu: P.tableau([
                { label: 'Date', value: function (c) { return C.dateFR(c.date); } },
                { label: 'Motif', key: 'motif' },
                { label: 'Diagnostic', key: 'diagnostic' },
                { label: 'Praticien', key: 'medecin' },
              ], C.sortBy(cons, 'date', 'desc').slice(0, 20)),
              signatures: [{ role: 'Le Secrétaire Médical' }],
            });
          },
        })]));
        U.icons(vue);
      }
      sel.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;
    },
  });

  /* ==========================================================================
   * TABLEAU DE BORD DYNAMIQUE CROISÉ
   * --------------------------------------------------------------------------
   * Ce que le TDR reproche à l'existant : « il n'existe pas de système
   * permettant de CROISER automatiquement données financières et données
   * opérationnelles ». Les tableaux de bord par profil répondent chacun à une
   * question fixe ; celui-ci laisse poser la question.
   *
   * Trois choix, et le reste se calcule :
   *   - une SOURCE (soins, actes, analyses, stock, patients, personnel, gardes) ;
   *   - deux AXES à croiser — les lignes et les colonnes du tableau ;
   *   - une MESURE : un effectif, un montant, une quantité.
   *
   * DEUX PRINCIPES DE CONCEPTION :
   *
   *   1. Les axes proposés dépendent de la SOURCE. Croiser « type de garde »
   *      avec « famille d'article » ne veut rien dire : proposer le croisement
   *      donnerait un tableau vide que l'utilisateur croirait faux.
   *
   *   2. Un montant ne s'additionne pas avec un effectif. La mesure est donc
   *      déclarée par la source, jamais choisie librement — un total de
   *      « 45 patients + 380 000 FCFA » n'a aucun sens et se lit pourtant
   *      comme un total.
   * ======================================================================== */
  var CROISE_PERIODES = [
    { code: 'jour', label: 'Aujourd’hui', jours: 1 },
    { code: 'semaine', label: '7 derniers jours', jours: 7 },
    { code: 'mois', label: '30 derniers jours', jours: 30 },
    { code: 'trimestre', label: '90 derniers jours', jours: 90 },
    { code: 'semestre', label: '180 derniers jours', jours: 180 },
    { code: 'annee', label: '12 derniers mois', jours: 365 },
    { code: 'tout', label: 'Tout l’historique', jours: null },
  ];

  /* Une source déclare : où elle lit, quelle date porte chaque ligne, quels
     axes elle sait croiser, et quelles mesures ont un sens sur elle. */
  function sourcesCroise() {
    function agentDe(id) {
      var a = S.collection('personnel').active().filter(function (x) { return x.id === id; })[0];
      return a || null;
    }
    function trancheAge(n) {
      if (n == null) return 'Non renseigné';
      if (n < 5) return '0 – 4 ans';
      if (n < 15) return '5 – 14 ans';
      if (n < 25) return '15 – 24 ans';
      if (n < 45) return '25 – 44 ans';
      if (n < 65) return '45 – 64 ans';
      return '65 ans et plus';
    }
    function mois(d) {
      if (!d) return '—';
      return C.moisAnnee(d);
    }

    return [
      {
        code: 'consultations', label: 'Consultations', icone: 'stethoscope',
        lire: function () { return S.collection('consultations').active(); },
        date: function (r) { return r.date; },
        axes: {
          mois: { label: 'Mois', valeur: function (r) { return mois(r.date); } },
          medecin: { label: 'Médecin', valeur: function (r) { return r.medecin || '—'; } },
          service: { label: 'Service', valeur: function (r) { return r.service || r.type || '—'; } },
          motif: { label: 'Motif', valeur: function (r) { return r.motif || '—'; } },
        },
        mesures: {
          nombre: { label: 'Nombre de consultations', unite: null, valeur: function () { return 1; } },
          montant: { label: 'Montant facturé', unite: 'FCFA', valeur: function (r) { return r.montant || 0; } },
        },
      },
      {
        code: 'prescriptionsSoins', label: 'Soins prescrits', icone: 'hand-heart',
        lire: function () {
          return S.collection('prescriptions').active().filter(function (r) { return r.type === 'soins'; });
        },
        date: function (r) { return r.date; },
        axes: {
          mois: { label: 'Mois', valeur: function (r) { return mois(r.date); } },
          secteur: { label: 'Secteur destinataire', valeur: function (r) { return r.secteurDestinataire || '—'; } },
          /* Le SECTEUR d'origine, dit dans le vocabulaire des six — et non
             « bloc » ici quand l'écran voisin dit « Hospitalisation et
             soins » : deux tableaux ne se comparent pas s'ils ne nomment pas
             les services de la même façon. */
          origine: { label: 'Secteur d’origine de la prescription',
            valeur: function (r) { return D.secteurNormalise(r.origine) || r.origine || '—'; } },
          prescripteur: { label: 'Prescripteur', valeur: function (r) { return r.prescripteur || '—'; } },
          modalite: { label: 'Modalité', valeur: function (r) { return r.modalite || '—'; } },
        },
        mesures: {
          nombre: { label: 'Nombre de prescriptions', unite: null, valeur: function () { return 1; } },
          lignes: { label: 'Nombre d’actes', unite: null,
            valeur: function (r) { return (r.lignes || []).length; } },
          montant: { label: 'Montant', unite: 'FCFA', valeur: function (r) { return r.montant || 0; } },
        },
      },
      {
        code: 'analyses', label: 'Analyses de laboratoire', icone: 'flask-conical',
        lire: function () { return S.collection('demandesAnalyses').active(); },
        date: function (r) { return r.dateHeure; },
        axes: {
          mois: { label: 'Mois', valeur: function (r) { return mois(r.dateHeure); } },
          analyse: { label: 'Analyse', valeur: function (r) { return r.analyse || '—'; } },
          categorie: { label: 'Section', valeur: function (r) { return r.categorie || '—'; } },
          prescripteur: { label: 'Prescripteur', valeur: function (r) { return r.prescripteur || '—'; } },
          origine: { label: 'Interne ou externe', valeur: function (r) {
            return /externe/i.test(r.origineDemande || '') ? 'Externe' : 'Interne';
          } },
          etat: { label: 'État', valeur: function (r) { return r.etatAnalyse || '—'; } },
        },
        mesures: {
          nombre: { label: 'Nombre d’analyses', unite: null, valeur: function () { return 1; } },
          montant: { label: 'Montant', unite: 'FCFA', valeur: function (r) { return r.prix || 0; } },
        },
      },
      {
        code: 'mouvements', label: 'Mouvements de stock', icone: 'package',
        lire: function () { return S.collection('mouvements').active(); },
        date: function (r) { return r.date; },
        axes: {
          mois: { label: 'Mois', valeur: function (r) { return mois(r.date); } },
          sens: { label: 'Sens', valeur: function (r) { return r.sens === 'entree' ? 'Entrée' : 'Sortie'; } },
          type: { label: 'Type de mouvement', valeur: function (r) { return r.type || '—'; } },
          produit: { label: 'Article', valeur: function (r) { return r.produit || '—'; } },
          famille: { label: 'Famille d’article', valeur: function (r) {
            var pr = S.collection('produits').active().filter(function (x) { return x.id === r.produitId; })[0];
            return pr ? (pr.famille || '—') : '—';
          } },
        },
        mesures: {
          nombre: { label: 'Nombre de mouvements', unite: null, valeur: function () { return 1; } },
          quantite: { label: 'Quantité', unite: 'unités', valeur: function (r) { return r.quantite || 0; } },
          valeur: { label: 'Valeur', unite: 'FCFA', valeur: function (r) { return r.valeur || 0; } },
        },
      },
      {
        code: 'factures', label: 'Facturation', icone: 'receipt',
        lire: function () { return S.collection('factures').active(); },
        date: function (r) { return r.date; },
        axes: {
          mois: { label: 'Mois', valeur: function (r) { return mois(r.date); } },
          nature: { label: 'Nature', valeur: function (r) { return r.type || r.nature || '—'; } },
          assureur: { label: 'Assureur', valeur: function (r) { return r.assureur || 'Non assuré'; } },
          statut: { label: 'État du règlement', valeur: function (r) { return r.statut || '—'; } },
        },
        mesures: {
          nombre: { label: 'Nombre de factures', unite: null, valeur: function () { return 1; } },
          montant: { label: 'Montant total', unite: 'FCFA', valeur: function (r) { return r.montantTTC || 0; } },
          encaisse: { label: 'Montant encaissé', unite: 'FCFA', valeur: function (r) { return r.montantPaye || 0; } },
          assureur: { label: 'Part assureur', unite: 'FCFA', valeur: function (r) { return r.partAssurance || 0; } },
        },
      },
      {
        code: 'patients', label: 'Patients', icone: 'users',
        lire: function () { return S.collection('patients').active(); },
        date: function (r) { return r.creeLe || r.dateCreation; },
        axes: {
          sexe: { label: 'Sexe', valeur: function (r) { return r.sexe === 'F' ? 'Féminin' : 'Masculin'; } },
          age: { label: 'Tranche d’âge', valeur: function (r) { return trancheAge(C.age(r.dateNaissance)); } },
          quartier: { label: 'Quartier', valeur: function (r) { return r.quartier || '—'; } },
          assurance: { label: 'Couverture', valeur: function (r) { return r.assureurNom || r.assureur || 'Non assuré'; } },
          groupe: { label: 'Groupe sanguin', valeur: function (r) { return r.groupeSanguin || '—'; } },
        },
        mesures: {
          nombre: { label: 'Nombre de patients', unite: null, valeur: function () { return 1; } },
        },
      },
      {
        code: 'personnel', label: 'Personnel', icone: 'users-round',
        lire: function () { return S.collection('personnel').active(); },
        date: function (r) { return r.dateEmbauche; },
        axes: {
          service: { label: 'Service', valeur: function (r) { return r.service || '—'; } },
          fonction: { label: 'Fonction', valeur: function (r) { return r.fonction || '—'; } },
          sexe: { label: 'Sexe', valeur: function (r) { return r.sexe === 'F' ? 'Féminin' : 'Masculin'; } },
          categorie: { label: 'Catégorie', valeur: function (r) { return r.categorie || '—'; } },
        },
        mesures: {
          nombre: { label: 'Effectif', unite: null, valeur: function () { return 1; } },
          masse: { label: 'Masse salariale de base', unite: 'FCFA', valeur: function (r) { return r.salaireBase || 0; } },
        },
      },
      {
        /* ================================================================
         * LES ACTES — la LIGNE, pas la pièce
         * ----------------------------------------------------------------
         * Un acte est une ligne de facture ou de prescription. Compter les
         * pièces à sa place donnerait un chiffre proche, plausible et faux :
         * une prescription porte plusieurs actes.
         * ============================================================== */
        code: 'actes', label: 'Actes réalisés', icone: 'clipboard-list',
        lire: function () {
          var out = [];
          var parCode = {};
          S.collection('actes').active().forEach(function (a) { parCode[a.code] = a; });

          /* Les actes facturés : ils portent leur secteur par le catalogue. */
          S.collection('factures').active().forEach(function (f) {
            (f.lignes || []).forEach(function (l) {
              if (l.categorie !== 'acte' && l.categorie !== 'consultation') return;
              var ref = l.acteCode ? parCode[l.acteCode] : null;
              out.push({
                date: f.date,
                acte: l.designation,
                secteur: ref ? ref.secteur : 'Non rattaché',
                quantite: Number(l.quantite) || 1,
                montant: Number(l.montant) || 0,
                praticien: f.medecin || f.prescripteur || null,
                patientId: f.patientId,
                origine: 'Facturé',
              });
            });
          });

          /* Les actes prescrits en soins : ils portent leur prescripteur et le
             secteur auquel ils sont adressés. */
          S.collection('prescriptions').active().forEach(function (pr) {
            if (pr.type !== 'soins') return;
            (pr.lignes || []).forEach(function (l) {
              out.push({
                date: pr.date,
                acte: l.libelle || l.designation || '—',
                secteur: pr.secteurDestinataire || 'Non rattaché',
                quantite: Number(l.nbAdministrations) || 1,
                montant: Number(l.montant) || 0,
                praticien: pr.prescripteur || null,
                patientId: pr.patientId,
                origine: 'Prescrit',
              });
            });
          });
          return out;
        },
        date: function (r) { return r.date; },
        axes: {
          acte: { label: 'Acte', valeur: function (r) { return r.acte || '—'; } },
          secteur: { label: 'Secteur', valeur: function (r) { return r.secteur || '—'; } },
          praticien: { label: 'Médecin / prescripteur', valeur: function (r) { return r.praticien || 'Non renseigné'; } },
          serviceP: { label: 'Service du praticien', valeur: function (r) {
            if (!r.praticien) return 'Non renseigné';
            var a = S.collection('personnel').active().filter(function (x) {
              return x.nomComplet === r.praticien;
            })[0];
            return a ? a.service : 'Hors effectif';
          } },
          origine: { label: 'Facturé ou prescrit', valeur: function (r) { return r.origine; } },
          mois: { label: 'Mois', valeur: function (r) { return mois(r.date); } },
        },
        mesures: {
          nombre: { label: 'Nombre d’actes', unite: null, valeur: function (r) { return r.quantite || 1; } },
          lignes: { label: 'Nombre de lignes', unite: null, valeur: function () { return 1; } },
          montant: { label: 'Montant', unite: 'FCFA', valeur: function (r) { return r.montant || 0; } },
        },
      },
      {
        /* ================================================================
         * LES SOINS EXÉCUTÉS — ce qui a été fait, et par qui
         * ----------------------------------------------------------------
         * Le prescrit dit ce qu'on a voulu, l'exécuté dit ce qui a été fait.
         * L'écart entre les deux est l'information la plus utile des deux, et
         * c'est ici que l'infirmier apparaît : il n'existe pas dans la
         * prescription.
         * ============================================================== */
        code: 'soinsExecutes', label: 'Soins exécutés', icone: 'syringe',
        lire: function () { return S.collection('administrations').active(); },
        date: function (r) { return r.dateHeure; },
        axes: {
          executant: { label: 'Exécutant (infirmier / sage-femme)',
            valeur: function (r) { return r.executant || 'Non renseigné'; } },
          soin: { label: 'Soin', valeur: function (r) { return r.libelle || '—'; } },
          secteur: { label: 'Secteur qui a servi', valeur: function (r) {
            var lib = { salle_soins: 'Salle de soins', hospitalisation: 'Hospitalisation',
              maternite: 'Maternité', bloc: 'Bloc opératoire' };
            return lib[r.secteur] || r.secteur || '—';
          } },
          modalite: { label: 'Modalité', valeur: function (r) {
            return r.modalite === 'ambulatoire' ? 'Ambulatoire'
              : (r.modalite === 'hospitalier' ? 'Hospitalier' : (r.modalite || '—'));
          } },
          serviceE: { label: 'Service de l’exécutant', valeur: function (r) {
            var a = S.collection('personnel').active().filter(function (x) {
              return x.nomComplet === r.executant;
            })[0];
            return a ? a.service : 'Non renseigné';
          } },
          mois: { label: 'Mois', valeur: function (r) { return mois(r.dateHeure); } },
        },
        mesures: {
          nombre: { label: 'Nombre d’administrations', unite: null, valeur: function () { return 1; } },
          patients: { label: 'Passages', unite: null, valeur: function () { return 1; } },
        },
      },
      {
        code: 'gardes', label: 'Gardes et vacations', icone: 'calendar-clock',
        lire: function () {
          return S.collection('planning').active().filter(function (r) {
            return !/repos|cong/i.test(String(r.regimeLibelle || r.type || ''));
          });
        },
        date: function (r) { return r.date; },
        axes: {
          mois: { label: 'Mois', valeur: function (r) { return mois(r.date); } },
          agent: { label: 'Agent', valeur: function (r) {
            var a = agentDe(r.employeId || r.personnelId);
            return a ? a.nomComplet : (r.agent || '—');
          } },
          service: { label: 'Service', valeur: function (r) {
            var a = agentDe(r.employeId || r.personnelId);
            return a ? a.service : '—';
          } },
          regime: { label: 'Type de vacation', valeur: function (r) {
            return r.regimeLibelle || r.type || '—';
          } },
        },
        mesures: {
          nombre: { label: 'Nombre de vacations', unite: null, valeur: function () { return 1; } },
        },
      },
    ];
  }

  global.SIGH.screen('dash-croise', {
    title: 'Tableau de bord dynamique croisé',
    description: 'Croiser librement soins, actes, analyses, stock, facturation, patients, personnel et gardes.',
    regle: 'Les tableaux de bord par profil répondent chacun à une question fixe ; celui-ci laisse '
      + '<strong>poser la question</strong>. Les axes proposés dépendent de la source — croiser des grandeurs '
      + 'sans rapport donnerait un tableau vide qu’on croirait faux. La <strong>mesure</strong> est déclarée '
      + 'par la source : un effectif ne s’additionne pas avec un montant.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);

      var SOURCES = sourcesCroise();
      var etat = {
        source: SOURCES[0].code,
        lignes: null, colonnes: null, mesure: null,
        periode: 'mois',
      };
      appliquerDefauts();
      afficher();
      return null;

      function src() {
        return SOURCES.filter(function (x) { return x.code === etat.source; })[0] || SOURCES[0];
      }
      function appliquerDefauts() {
        var s2 = src();
        var axes = Object.keys(s2.axes);
        etat.lignes = axes[0];
        etat.colonnes = axes[1] || null;
        etat.mesure = Object.keys(s2.mesures)[0];
      }

      function bornes() {
        var pe = CROISE_PERIODES.filter(function (x) { return x.code === etat.periode; })[0];
        if (!pe || !pe.jours) return null;
        return C.iso(C.addDays(new Date(), -pe.jours));
      }

      /* Le calcul du croisement : deux axes, une mesure, une période. */
      function croiser() {
        var s2 = src();
        var depuis = bornes();
        var rows = s2.lire().filter(function (r) {
          if (!depuis) return true;
          var d = s2.date(r);
          return d && String(d).slice(0, 10) >= depuis;
        });

        var axL = s2.axes[etat.lignes], axC = etat.colonnes ? s2.axes[etat.colonnes] : null;
        var mes = s2.mesures[etat.mesure];

        var table = {}, colonnes = {}, totalGeneral = 0;
        rows.forEach(function (r) {
          var l = String(axL.valeur(r) || '—');
          var c = axC ? String(axC.valeur(r) || '—') : 'Total';
          var v = Number(mes.valeur(r)) || 0;
          if (!table[l]) table[l] = {};
          table[l][c] = (table[l][c] || 0) + v;
          colonnes[c] = (colonnes[c] || 0) + v;
          totalGeneral += v;
        });

        return {
          lignes: Object.keys(table).sort(),
          colonnes: Object.keys(colonnes).sort(),
          table: table, totauxColonnes: colonnes, total: totalGeneral,
          effectif: rows.length, mesure: mes,
        };
      }

      function afficher() {
        var s2 = src();
        var res = croiser();
        C.clear(vue);

        vue.appendChild(commandes(s2));

        vue.appendChild(U.kpiGrid([
          { label: 'Source', value: s2.label, icon: s2.icone, tone: 'navy' },
          { label: 'Enregistrements retenus', value: C.num(res.effectif), icon: 'filter', tone: 'info',
            hint: CROISE_PERIODES.filter(function (x) { return x.code === etat.periode; })[0].label },
          { label: res.mesure.label, icon: 'sigma', tone: 'success',
            value: res.mesure.unite === 'FCFA' ? C.money(res.total) : C.num(res.total) },
          { label: 'Croisement', value: C.num(res.lignes.length) + ' × ' + C.num(res.colonnes.length),
            icon: 'grid-3x3', tone: 'neutral', hint: 'lignes × colonnes' },
        ]));

        if (!res.lignes.length) {
          vue.appendChild(U.card(null, U.empty('Aucune donnée sur la période choisie.', {
            icon: 'chart-scatter',
            hint: 'Élargir la période, ou changer d’axe — la source ne porte peut-être rien sur cet intervalle.',
          })));
          U.icons(vue);
          return;
        }

        vue.appendChild(tableauCroise(s2, res));
        vue.appendChild(graphique(s2, res));
        U.icons(vue);
      }

      function commandes(s2) {
        function choix(label, valeurs, courant, onChange, avecAucun) {
          var sel = el('select.h-10.w-full.rounded-lg.border.border-slate-300.px-3.text-sm');
          if (avecAucun) sel.appendChild(el('option', { value: '', text: '— aucun —' }));
          valeurs.forEach(function (v) {
            var o = el('option', { value: v.value, text: v.label });
            if (v.value === courant) o.selected = true;
            sel.appendChild(o);
          });
          sel.addEventListener('change', function () { onChange(sel.value); });
          return el('div', null, [
            el('label.mb-1.block.text-xs.font-medium.text-slate-500', { text: label }), sel,
          ]);
        }

        var axes = Object.keys(s2.axes).map(function (k) {
          return { value: k, label: s2.axes[k].label };
        });

        return U.card('Construire le croisement',
          el('div.grid.gap-3.sm\\:grid-cols-2.lg\\:grid-cols-5', null, [
            choix('Source', SOURCES.map(function (x) { return { value: x.code, label: x.label }; }),
              etat.source, function (v) { etat.source = v; appliquerDefauts(); afficher(); }),
            choix('Lignes', axes, etat.lignes, function (v) { etat.lignes = v; afficher(); }),
            choix('Colonnes', axes, etat.colonnes, function (v) { etat.colonnes = v || null; afficher(); }, true),
            choix('Mesure', Object.keys(s2.mesures).map(function (k) {
              return { value: k, label: s2.mesures[k].label };
            }), etat.mesure, function (v) { etat.mesure = v; afficher(); }),
            choix('Période', CROISE_PERIODES.map(function (x) { return { value: x.code, label: x.label }; }),
              etat.periode, function (v) { etat.periode = v; afficher(); }),
          ]));
      }

      function tableauCroise(s2, res) {
        var colonnes = [{ key: 'ligne', label: s2.axes[etat.lignes].label }];
        res.colonnes.forEach(function (c) {
          colonnes.push({
            key: 'c_' + c, label: c, align: 'right',
            render: function (r) {
              var v = r['c_' + c];
              if (!v) return el('span.text-slate-300', { text: '—' });
              return res.mesure.unite === 'FCFA' ? C.money(v) : C.num(v);
            },
          });
        });
        colonnes.push({
          key: 'total', label: 'Total', align: 'right',
          render: function (r) {
            return el('span.font-semibold', {
              text: res.mesure.unite === 'FCFA' ? C.money(r.total) : C.num(r.total),
            });
          },
        });

        var rows = res.lignes.map(function (l) {
          var o = { ligne: l, total: 0 };
          res.colonnes.forEach(function (c) {
            var v = res.table[l][c] || 0;
            o['c_' + c] = v; o.total += v;
          });
          return o;
        }).sort(function (a, b) { return b.total - a.total; });

        /* La ligne de total est CALCULÉE depuis les lignes affichées, comme
           partout ailleurs : un total transmis peut diverger de son tableau. */
        var pied = { ligne: 'TOTAL', total: res.total };
        res.colonnes.forEach(function (c) { pied['c_' + c] = res.totauxColonnes[c]; });

        return U.card(res.mesure.label + ' — ' + s2.axes[etat.lignes].label
          + (etat.colonnes ? ' × ' + s2.axes[etat.colonnes].label : ''),
        el('div.overflow-x-auto', null,
          U.dataTable({ searchable: true, rows: rows.concat([pied]), columns: colonnes, empty: 'Aucune donnée.' })));
      }

      function graphique(s2, res) {
        var top = res.lignes.map(function (l) {
          var t = 0;
          res.colonnes.forEach(function (c) { t += res.table[l][c] || 0; });
          return { label: l, valeur: t };
        }).sort(function (a, b) { return b.valeur - a.valeur; }).slice(0, 12);

        return U.card('Les douze premières valeurs — ' + s2.axes[etat.lignes].label,
          G.barres(
            top.map(function (x) { return x.label; }),
            [{ label: res.mesure.label, data: top.map(function (x) { return x.valeur; }) }],
            /* En barres horizontales : les libellés d'axe sont des noms d'agents,
               d'articles ou de services — illisibles à la verticale. */
            { horizontal: true, height: Math.max(240, top.length * 26) }));
      }
    },
  });


  /* ==========================================================================
   * STATISTIQUES DE LA DIRECTION
   * --------------------------------------------------------------------------
   * Demande de la Direction : la caisse du jour, puis les cumuls journaliers,
   * hebdomadaires, mensuels, trimestriels, semestriels et annuels des
   * médicaments vendus, des actes vendus, des analyses réalisées, des soins et
   * des constatations — le tout par service.
   *
   * UN CUMUL N'EST PAS UNE MOYENNE. Chaque périodicité affiche le TOTAL de sa
   * période et la variation par rapport à la période précédente de même durée :
   * c'est la comparaison qui informe, pas le nombre nu. « 380 000 F ce mois »
   * ne dit rien ; « 380 000 F, en hausse de 12 % sur le mois précédent » dit
   * quelque chose.
   * ======================================================================== */
  var PERIODICITES_DA = [
    { code: 'jour', label: 'Jour', jours: 1 },
    { code: 'semaine', label: 'Semaine', jours: 7 },
    { code: 'mois', label: 'Mois', jours: 30 },
    { code: 'trimestre', label: 'Trimestre', jours: 90 },
    { code: 'semestre', label: 'Semestre', jours: 180 },
    { code: 'annee', label: 'Année', jours: 365 },
  ];

  /* UNE PÉRIODE SE NOMME, ELLE NE SE DEVINE PAS.
     ------------------------------------------------------------------
     Les six onglets affichaient « les 30 derniers jours » — une fenêtre
     glissante, sans date, et impossible à déplacer. La Direction demande
     QUEL jour, QUEL mois : un cumul dont on ignore les bornes ne se
     rapproche d'aucun document, et « le mois » d'un tableau qui court sur
     trente jours à cheval sur deux mois n'est le mois de personne.
     Les bornes sont donc CALENDAIRES — du 1er au dernier jour du mois
     choisi — et la période se choisit, la période précédente étant
     l'unité de même nature qui précède (pas « les 30 jours d'avant »).
     L'année courante est le défaut, comme la Direction le suppose. */
  function lundiDe(d) {
    var j = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    var dec = (j.getDay() + 6) % 7; /* lundi = 0 : la semaine ouvrée commence lundi */
    return C.addDays(j, -dec);
  }
  /** Bornes calendaires de la période qui CONTIENT la date d'ancrage. */
  function bornesDA(code, ancre) {
    var a = C.toDate(ancre), an = a.getFullYear(), m = a.getMonth();
    if (code === 'jour') return { debut: new Date(an, m, a.getDate()), fin: new Date(an, m, a.getDate()) };
    if (code === 'semaine') { var l = lundiDe(a); return { debut: l, fin: C.addDays(l, 6) }; }
    if (code === 'mois') return { debut: new Date(an, m, 1), fin: new Date(an, m + 1, 0) };
    if (code === 'trimestre') { var t = Math.floor(m / 3); return { debut: new Date(an, t * 3, 1), fin: new Date(an, t * 3 + 3, 0) }; }
    if (code === 'semestre') { var se = m < 6 ? 0 : 1; return { debut: new Date(an, se * 6, 1), fin: new Date(an, se * 6 + 6, 0) }; }
    return { debut: new Date(an, 0, 1), fin: new Date(an, 11, 31) };
  }
  /** La période de MÊME NATURE qui précède — jamais « la même durée avant ». */
  function bornesPrecedenteDA(code, ancre) {
    var b = bornesDA(code, ancre);
    return bornesDA(code, C.addDays(b.debut, -1));
  }
  /** L'intitulé exact de la période, celui qu'on relit sur un état. */
  function libelleDA(code, b) {
    var MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
      'septembre', 'octobre', 'novembre', 'décembre'];
    var d = C.toDate(b.debut);
    if (code === 'jour') return 'journée du ' + C.dateFR(b.debut);
    if (code === 'mois') return MOIS[d.getMonth()] + ' ' + d.getFullYear();
    if (code === 'trimestre') return 'T' + (Math.floor(d.getMonth() / 3) + 1) + ' ' + d.getFullYear();
    if (code === 'semestre') return 'S' + (d.getMonth() < 6 ? 1 : 2) + ' ' + d.getFullYear();
    if (code === 'annee') return 'année ' + d.getFullYear();
    return 'semaine du ' + C.dateFR(b.debut) + ' au ' + C.dateFR(b.fin);
  }

  global.SIGH.screen('dash-da', {
    title: 'Statistiques de la Direction',
    description: 'Caisse du jour et cumuls par périodicité : médicaments, actes, analyses, soins, par service.',
    regle: 'Chaque périodicité affiche le <strong>total de sa période</strong> et sa <strong>variation</strong> '
      + 'par rapport à la période précédente de même durée : c’est la comparaison qui informe, pas le nombre '
      + 'nu. Les montants sont ceux <strong>réellement encaissés</strong>, distingués du chiffre d’affaires '
      + 'facturé — confondre les deux ferait prendre une créance pour de la trésorerie.',
    render: function (root) {
      var vue = el('div.space-y-4');

      /* PLAGE LIBRE (demande du 02/09/2026) : en plus des périodicités
         fixes, la Direction choisit deux dates et lit la même caisse sur
         cette fenêtre — pièces émises dans la plage, montants réellement
         encaissés dessus. */
      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var zonePlage = el('div');
      var barrePlage = el('div.card');
      barrePlage.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Analyse libre — du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'au' }), dFin]),
      ]));
      root.appendChild(barrePlage);
      root.appendChild(zonePlage);
      /* La caisse du jour dit ce qui est RENTRÉ ; le BFR dit ce qu'il reste à
         financer. La DAF a besoin des deux, et dans cet ordre. */
      root.appendChild(widgetBFR());
      root.appendChild(vue);
      [dDebut, dFin].forEach(function (x) { x.addEventListener('change', peindrePlage); });

      function peindrePlage() {
        C.clear(zonePlage);
        if (!dDebut.value && !dFin.value) return;
        function dans(dt) {
          var x = String(dt || '').slice(0, 10);
          if (dDebut.value && x < dDebut.value) return false;
          if (dFin.value && x > dFin.value) return false;
          return true;
        }
        var fs2 = S.collection('factures').active().filter(function (f) { return dans(f.date); });
        var deps = S.collection('depenses').active().filter(function (d) { return dans(d.date); });
        zonePlage.appendChild(U.kpiGrid([
          { label: 'Pièces émises sur la plage', value: C.num(fs2.length), icon: 'receipt', tone: 'navy' },
          { label: 'Facturé (lignes)', value: C.money(C.sum(fs2, 'montantTTC')), icon: 'file-text', tone: 'info' },
          { label: 'Encaissé sur ces pièces', value: C.money(C.sum(fs2, 'montantPaye')), icon: 'coins', tone: 'success' },
          { label: 'Dépenses de la plage', value: C.money(C.sum(deps, 'montant')), icon: 'wallet', tone: 'warning' },
        ]));
        U.icons(zonePlage);
      }

      /* L'ancre courante par périodicité — elle survit au changement d'onglet :
         revenir sur « Mois » après avoir choisi juin doit rouvrir juin, pas le
         mois en cours. DÉCLARÉE AVANT afficher() : une affectation qui se trouve
         après l'appel n'a pas encore eu lieu quand le premier onglet se peint
         (le piège var-après-return, payé deux fois dans ce prototype). */
      var ancresDA = {};

      afficher();
      return null;

      function entre(d1, d2) {
        return function (dt) {
          var x = String(dt || '').slice(0, 10);
          return x >= d1 && x < d2;
        };
      }

      /* Les grandeurs suivies, chacune avec sa source et sa mesure. */
      function mesures(filtre) {
        var factures = S.collection('factures').active().filter(function (f) { return filtre(f.date); });
        var lignes = factures.reduce(function (acc, f) {
          (f.lignes || []).forEach(function (l) { acc.push({ ligne: l, facture: f }); });
          return acc;
        }, []);
        function parCategorie(cat) {
          return lignes.filter(function (x) { return x.ligne.categorie === cat; });
        }
        function somme(rows) {
          return rows.reduce(function (n, x) { return n + (x.ligne.montant || 0); }, 0);
        }
        var demandes = S.collection('demandesAnalyses').active()
          .filter(function (x) { return filtre(x.dateHeure); });
        var consultations = S.collection('consultations').active()
          .filter(function (x) { return filtre(x.date); });

        return {
          caFacture: factures.reduce(function (n, f) { return n + (f.montantTTC || 0); }, 0),
          encaisse: factures.reduce(function (n, f) { return n + (f.montantPaye || 0); }, 0),
          reliquat: factures.reduce(function (n, f) { return n + (f.reliquat || 0); }, 0),
          pieces: factures.length,
          medicaments: parCategorie('medicament').length,
          medicamentsMontant: somme(parCategorie('medicament')),
          actes: parCategorie('acte').length,
          actesMontant: somme(parCategorie('acte')),
          analyses: demandes.length,
          analysesMontant: somme(parCategorie('analyse')),
          consultations: consultations.length,
          consultationsMontant: somme(parCategorie('consultation')),
          hospitalisation: parCategorie('hospitalisation').length,
          hospitalisationMontant: somme(parCategorie('hospitalisation')),
        };
      }

      function variation(actuel, precedent) {
        if (!precedent) return null;
        return Math.round(((actuel - precedent) / precedent) * 1000) / 10;
      }

      function afficher() {
        var auj = C.iso(new Date());
        var jour = mesures(function (d2) { return String(d2 || '').slice(0, 10) === auj; });

        C.clear(vue);

        /* Le premier regard de la DAF : activité 25 de sa description de poste,
           « faire le point journalier de la caisse ». C'est littéralement écrit. */
        vue.appendChild(K.bandeauPremierRegard({
          valeur: jour.encaisse, unite: 'FCFA encaissés aujourd’hui',
          question: 'sur ' + C.num(jour.pieces) + ' pièce(s) émise(s)',
          vide: 'Aucun encaissement enregistré aujourd’hui.',
          ton: 'navy', icone: 'banknote',
          ecran: 'm8-caisse', lienLabel: 'Point de caisse',
          note: 'Activité 25 de la description de poste : « faire le point journalier de la caisse '
            + 'en l’absence de la DA ou à sa demande ».',
        }));

        /* --- La caisse du jour, d'abord : c'est ce que la DA regarde en
           premier chaque soir. --------------------------------------------- */
        vue.appendChild(U.kpiGrid([
          { label: 'Encaissé aujourd’hui', value: C.money(jour.encaisse), icon: 'banknote', tone: 'success',
            hint: C.num(jour.pieces) + ' pièce(s) émise(s)' },
          { label: 'Facturé aujourd’hui', value: C.money(jour.caFacture), icon: 'receipt', tone: 'navy',
            hint: 'chiffre d’affaires, encaissé ou non' },
          { label: 'Reste dû du jour', value: C.money(jour.reliquat), icon: 'hand-coins',
            tone: jour.reliquat ? 'warning' : 'success' },
          { label: 'Analyses du jour', value: C.num(jour.analyses), icon: 'flask-conical', tone: 'info' },
        ]));

        vue.appendChild(K.note('Le <strong>facturé</strong> et l’<strong>encaissé</strong> sont deux grandeurs '
          + 'distinctes : la première est un chiffre d’affaires, la seconde de la trésorerie. Les confondre '
          + 'ferait prendre une créance pour de l’argent en caisse.', { tone: 'info', icon: 'arrow-left-right' }));

        vue.appendChild(U.tabs(PERIODICITES_DA.map(function (pe) {
          return { id: pe.code, label: pe.label, render: function () { return panneau(pe); } };
        })));
        U.icons(vue);
      }

      /* Le choix de la période, une commande par nature de périodicité :
         une date pour un jour ou une semaine, une liste pour le mois, le
         trimestre, le semestre et l'année. L'ANNÉE COURANTE est le défaut. */
      function selecteurDA(pe, ancre, onChange) {
        var MOIS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août',
          'Septembre', 'Octobre', 'Novembre', 'Décembre'];
        var an = C.toDate(ancre).getFullYear(), mois = C.toDate(ancre).getMonth();
        var ctrl;
        if (pe.code === 'jour' || pe.code === 'semaine') {
          ctrl = el('input.input', { type: 'date', value: C.iso(ancre) });
          ctrl.addEventListener('change', function () {
            if (ctrl.value) onChange(C.toDate(ctrl.value));
          });
        } else {
          var opts = [];
          if (pe.code === 'mois') {
            opts = MOIS.map(function (m, i) { return { value: String(i), label: m + ' ' + an }; });
          } else if (pe.code === 'trimestre') {
            opts = [0, 1, 2, 3].map(function (t) { return { value: String(t * 3), label: 'T' + (t + 1) + ' ' + an }; });
          } else if (pe.code === 'semestre') {
            opts = [0, 1].map(function (x) { return { value: String(x * 6), label: 'S' + (x + 1) + ' ' + an }; });
          } else {
            var ici = new Date().getFullYear();
            opts = [ici - 2, ici - 1, ici, ici + 1].map(function (y) { return { value: String(y), label: String(y) }; });
          }
          ctrl = el('select.input');
          opts.forEach(function (o) { ctrl.appendChild(el('option', { value: o.value, text: o.label })); });
          ctrl.value = pe.code === 'annee' ? String(an)
            : (pe.code === 'mois' ? String(mois)
              : (pe.code === 'trimestre' ? String(Math.floor(mois / 3) * 3) : String(mois < 6 ? 0 : 6)));
          ctrl.addEventListener('change', function () {
            onChange(pe.code === 'annee' ? new Date(+ctrl.value, 0, 15) : new Date(an, +ctrl.value, 15));
          });
        }
        var lbl = pe.code === 'jour' ? 'Jour analysé'
          : (pe.code === 'semaine' ? 'Une date de la semaine analysée' : pe.label + ' analysé' + (pe.code === 'annee' ? 'e' : ''));
        return el('div.card', null, el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
          el('div', null, [el('label.label', { text: lbl }), ctrl]),
          el('p.text-xs.text-slate-500', { text: 'L’année courante est retenue par défaut.' }),
        ]));
      }

      function panneau(pe) {
        var hote = el('div.space-y-4');
        peindre();
        return hote;

        function peindre() {
          C.clear(hote);
          var ancre = ancresDA[pe.code] || new Date();
          hote.appendChild(selecteurDA(pe, ancre, function (d) { ancresDA[pe.code] = d; peindre(); U.icons(hote); }));
          hote.appendChild(corps(pe, ancre));
          U.icons(hote);
        }
      }

      function corps(pe, ancre) {
        var bc = bornesDA(pe.code, ancre), bp = bornesPrecedenteDA(pe.code, ancre);
        var courant = mesures(entre(C.iso(bc.debut), C.iso(C.addDays(bc.fin, 1))));
        var precedent = mesures(entre(C.iso(bp.debut), C.iso(C.addDays(bp.fin, 1))));

        var lignes = [
          ['Chiffre d’affaires facturé', courant.caFacture, precedent.caFacture, true],
          ['Montant encaissé', courant.encaisse, precedent.encaisse, true],
          ['Reste dû', courant.reliquat, precedent.reliquat, true],
          ['Pièces émises', courant.pieces, precedent.pieces, false],
          ['Médicaments vendus (lignes)', courant.medicaments, precedent.medicaments, false],
          ['Médicaments — montant', courant.medicamentsMontant, precedent.medicamentsMontant, true],
          ['Actes vendus (lignes)', courant.actes, precedent.actes, false],
          ['Actes — montant', courant.actesMontant, precedent.actesMontant, true],
          ['Analyses réalisées', courant.analyses, precedent.analyses, false],
          ['Analyses — montant', courant.analysesMontant, precedent.analysesMontant, true],
          ['Consultations', courant.consultations, precedent.consultations, false],
          ['Consultations — montant', courant.consultationsMontant, precedent.consultationsMontant, true],
          ['Journées d’hospitalisation', courant.hospitalisation, precedent.hospitalisation, false],
          ['Hospitalisation — montant', courant.hospitalisationMontant, precedent.hospitalisationMontant, true],
        ];

        return el('div.space-y-4', null, [
          K.note('Période retenue : <strong>' + libelleDA(pe.code, bc) + '</strong> — du '
            + C.dateFR(bc.debut) + ' au ' + C.dateFR(bc.fin) + '. Comparée à <strong>'
            + libelleDA(pe.code, bp) + '</strong> (du ' + C.dateFR(bp.debut) + ' au '
            + C.dateFR(bp.fin) + ').', { tone: 'info', icon: 'calendar-range' }),
          U.dataTable({ searchable: true,
            rows: lignes.map(function (l) {
              return { grandeur: l[0], valeur: l[1], precedent: l[2], argent: l[3],
                var_: variation(l[1], l[2]) };
            }),
            columns: [
              { key: 'grandeur', label: 'Grandeur' },
              { key: 'valeur', label: 'Période courante', align: 'right',
                render: function (r) { return r.argent ? C.money(r.valeur) : C.num(r.valeur); } },
              { key: 'precedent', label: 'Période précédente', align: 'right',
                render: function (r) {
                  return el('span.text-slate-500', {
                    text: r.argent ? C.money(r.precedent) : C.num(r.precedent),
                  });
                } },
              { key: 'var_', label: 'Variation', align: 'right',
                render: function (r) {
                  if (r.var_ == null) {
                    return el('span.text-xs.italic.text-slate-400', { text: 'pas de base de comparaison' });
                  }
                  var cls = r.var_ > 0 ? 'font-semibold text-emerald-700'
                    : (r.var_ < 0 ? 'font-semibold text-rose-700' : 'text-slate-500');
                  return el('span', { class: cls, text: (r.var_ > 0 ? '+' : '') + r.var_ + ' %' });
                } },
            ],
          }),
          U.card('Répartition du chiffre d’affaires — ' + libelleDA(pe.code, bc),
            G.barres(
              ['Médicaments', 'Actes', 'Analyses', 'Consultations', 'Hospitalisation'],
              [{ label: 'Montant facturé',
                data: [courant.medicamentsMontant, courant.actesMontant, courant.analysesMontant,
                  courant.consultationsMontant, courant.hospitalisationMontant] }],
              { horizontal: true, height: 220 })),
        ]);
      }
    },
  });


  /* ==========================================================================
   * AIDE-SOIGNANTE
   * --------------------------------------------------------------------------
   * Elle participe aux soins et ne consulte AUCUN résultat d'analyse : c'est la
   * règle métier posée par la Direction pour cette fonction. Son tableau lui
   * montre donc les patients hospitalisés, jamais un résultat.
   * ======================================================================== */
  global.SIGH.screen('dash-aide-soignant', {
    title: 'Tableau de bord — Aide-soignante',
    description: 'Patients hospitalisés, soins du jour et visites — sans aucun résultat d’analyse.',
    render: K.dash({
      premierRegard: function () {
        var adm = S.collection('admissions').active().filter(function (a) { return !a.dateSortie; });
        return {
          valeur: adm.length, unite: 'patient(s) hospitalisé(s)',
          question: 'sont présents dans le service',
          vide: 'Aucun patient hospitalisé actuellement.',
          ton: 'navy', icone: 'bed-double',
          ecran: 'm3-admissions', lienLabel: 'Voir les admissions',
          note: 'Votre profil ne consulte aucun résultat d’analyse : c’est la règle métier posée par '
            + 'la Direction pour cette fonction, et l’écran des résultats vous est fermé.',
        };
      },
      kpis: function () {
        var adm = S.collection('admissions').active().filter(function (a) { return !a.dateSortie; });
        var rel = S.collection('releves', { module: 'M3', entite: 'FeuilleTemperature' }).active()
          .filter(function (r) { return r.date === C.iso(AUJ); });
        var visites = S.collection('visitesPatients').active().filter(function (v) {
          return String(v.date || '').slice(0, 10) === C.iso(AUJ);
        });
        return [
          { label: 'Patients hospitalisés', value: C.num(adm.length), icon: 'bed-double', tone: 'navy' },
          { label: 'Relevés de constantes du jour', value: C.num(rel.length), icon: 'thermometer', tone: 'info' },
          { label: 'Visites reçues aujourd’hui', value: C.num(visites.length), icon: 'users-round', tone: 'success' },
          { label: 'Lits occupés', value: C.num(adm.length), icon: 'layout-grid', tone: 'neutral' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Prendre soin d’un hospitalisé', icone: 'hand-heart', action: 'Voir les patients',
                detail: 'Les patients dont vous avez la charge.',
                etapes: [
                  { label: 'Voir les patients hospitalisés', ecran: 'm3-admissions' },
                  { label: 'Relever les constantes', ecran: 'm1-constantes' },
                  { label: 'Reporter sur la fiche de surveillance', ecran: 'm3-surveillance' },
                  { label: 'Signaler toute anomalie', poste: 'Infirmier' },
                ],
              },
              {
                titre: 'Accueillir les visites', icone: 'users-round', action: 'Visites',
                detail: 'Les proches se présentent.',
                etapes: [
                  { label: 'Enregistrer la visite', ecran: 'm3-visites-patients' },
                  { label: 'Orienter vers la chambre', ecran: 'm3-plan-lits' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm3-admissions', icon: 'bed-double', label: 'Patients hospitalisés', detail: 'Séjours en cours' },
              { id: 'm3-surveillance', icon: 'activity', label: 'Fiche de surveillance', detail: 'Constantes et courbe' },
              { id: 'm3-visites-patients', icon: 'users-round', label: 'Visites aux hospitalisés', detail: 'Registre du jour' },
              { id: 'm1-constantes', icon: 'thermometer', label: 'Relever des constantes', detail: 'Température, TA, pouls' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * TECHNICIEN D'ÉCHOGRAPHIE
   * --------------------------------------------------------------------------
   * Condition posée par la Direction : AUCUN accès financier. Un manipulateur
   * qui verrait la caisse pourrait faire dépendre l'examen du paiement, ce qui
   * n'est pas son rôle. Son tableau ne porte donc aucun montant.
   * ======================================================================== */
  global.SIGH.screen('dash-echographiste', {
    title: 'Tableau de bord — Échographie',
    description: 'Examens d’imagerie à réaliser et comptes rendus à rendre au prescripteur.',
    render: K.dash({
      premierRegard: function () {
        var brouillons = S.collection('resultatsImagerie').active().filter(function (r) {
          return r.statut !== 'rendu';
        });
        return {
          valeur: brouillons.length, unite: 'compte(s) rendu(s)',
          question: 'restent à terminer et à rendre',
          vide: 'Aucun compte rendu en attente.',
          ton: 'warning', icone: 'scan-line',
          ecran: 'm2-imagerie', lienLabel: 'Échographie & imagerie',
          note: 'La conclusion est obligatoire avant de rendre : c’est elle que le prescripteur lit.',
        };
      },
      kpis: function () {
        var tous = S.collection('resultatsImagerie').active();
        var rendus = tous.filter(function (r) { return r.statut === 'rendu'; });
        var mois = tous.filter(function (r) {
          return String(r.date || '').slice(0, 7) === C.iso(AUJ).slice(0, 7);
        });
        return [
          { label: 'Comptes rendus au total', value: C.num(tous.length), icon: 'scan-line', tone: 'navy' },
          { label: 'Rendus au prescripteur', value: C.num(rendus.length), icon: 'send', tone: 'success' },
          { label: 'Ce mois-ci', value: C.num(mois.length), icon: 'calendar', tone: 'info' },
          { label: 'Examens au catalogue', value: C.num((D.IMAGERIE && D.IMAGERIE.EXAMENS || []).length),
            icon: 'list', tone: 'neutral' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Réaliser un examen', icone: 'scan-line', action: 'Nouveau compte rendu',
                detail: 'Un examen d’imagerie est prescrit.',
                etapes: [
                  { label: 'Vérifier l’indication du prescripteur', ecran: 'm2-prescriptions',
                    detail: 'En lecture seule : vous ne modifiez pas la prescription d’un autre service.' },
                  { label: 'Ouvrir le compte rendu et saisir', ecran: 'm2-imagerie',
                    detail: 'Listes de choix partout ; Annexes et Conclusion restent libres.' },
                  { label: 'Rédiger la conclusion', ecran: 'm2-imagerie',
                    detail: 'Obligatoire avant de rendre : c’est elle que le prescripteur lit.' },
                  { label: 'Rendre au prescripteur', ecran: 'm2-imagerie' },
                  { label: 'Le clinicien décide', poste: 'Consultation' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm2-imagerie', icon: 'scan-line', label: 'Échographie & imagerie', detail: 'Saisie des comptes rendus' },
              { id: 'm1-patients', icon: 'users', label: 'Répertoire des patients', detail: 'Lecture seule' },
              { id: 'm2-prescriptions', icon: 'clipboard-plus', label: 'Prescriptions', detail: 'Lecture seule' },
            ]);
          },
        },
        {
          title: 'Ce que votre profil ne voit pas',
          render: function () {
            return K.note('Votre compte n’a <strong>aucun accès financier</strong> — ni caisse, ni assurances, '
              + 'ni comptabilité. C’est une condition posée par la Direction : un manipulateur qui verrait la '
              + 'caisse pourrait faire dépendre l’examen du paiement, ce qui n’est pas son rôle. '
              + 'Le dossier patient vous est ouvert en <strong>lecture seule</strong>, et vous ne modifiez pas '
              + 'les prescriptions d’un autre service.', { tone: 'info', icon: 'shield' });
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * SURVEILLANT
   * --------------------------------------------------------------------------
   * Missions 1 et 5 de la description de poste de l'Infirmier Général :
   * « surveiller les retards, les sorties et les absences non autorisées » et
   * « faire le planning de travail du personnel paramédical ». L'indicateur
   * chiffré du document — 95 % des retards constatés et notifiés — donne
   * directement le premier regard.
   * ======================================================================== */
  global.SIGH.screen('dash-surveillant', {
    title: 'Tableau de bord — Surveillant',
    description: 'Retards, absences, présences et planning du personnel paramédical.',
    render: K.dash({
      premierRegard: function () {
        var pres = S.collection('presences').active().filter(function (x) {
          return String(x.date || '').slice(0, 10) === C.iso(AUJ);
        });
        var retards = pres.filter(function (x) { return x.retard || x.statut === 'retard'; });
        return {
          valeur: retards.length, unite: 'retard(s)',
          question: 'constatés aujourd’hui',
          vide: 'Aucun retard constaté aujourd’hui.',
          ton: 'warning', icone: 'clock-alert',
          ecran: 'm10-presences', lienLabel: 'Présences du jour',
          note: 'Indicateur de votre description de poste : 95 % des retards constatés et notifiés. '
            + 'Constater ne suffit pas — c’est la notification qui compte.',
        };
      },
      kpis: function () {
        var pres = S.collection('presences').active().filter(function (x) {
          return String(x.date || '').slice(0, 10) === C.iso(AUJ);
        });
        var planning = S.collection('planning').active().filter(function (x) {
          return String(x.date || '').slice(0, 10) === C.iso(AUJ);
        });
        var conges = S.collection('conges').active().filter(function (x) {
          return x.statut !== 'archive' && String(x.debut || '') <= C.iso(AUJ)
            && String(x.fin || '') >= C.iso(AUJ);
        });
        return [
          { label: 'Présences pointées aujourd’hui', value: C.num(pres.length), icon: 'user-check', tone: 'success' },
          { label: 'Vacations planifiées', value: C.num(planning.length), icon: 'calendar-clock', tone: 'navy' },
          { label: 'Agents en congé', value: C.num(conges.length), icon: 'palmtree', tone: 'info' },
          { label: 'Effectif paramédical', value: C.num(S.collection('personnel').active().filter(function (a) {
            return ['infirmier', 'sage_femme', 'aide_soignant'].indexOf(a.fonction) !== -1;
          }).length), icon: 'users-round', tone: 'neutral' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Contrôler les présences', icone: 'user-check', action: 'Présences du jour',
                detail: 'Mission 1 de votre description de poste.',
                etapes: [
                  { label: 'Pointer les présences', ecran: 'm10-presences' },
                  { label: 'Constater ET notifier les retards', ecran: 'm10-presences',
                    detail: 'Votre indicateur : 95 % des retards constatés et notifiés. Constater ne suffit pas.' },
                  { label: 'Signaler les absences non autorisées', ecran: 'm10-conges' },
                ],
              },
              {
                titre: 'Faire le planning', icone: 'calendar-clock', action: 'Planning',
                detail: 'Mission 5 — personnel paramédical.',
                etapes: [
                  { label: 'Poser les vacations', ecran: 'm10-planning',
                    detail: 'Garde 24 h, permanence 08h–18h, repos. Les incompatibilités sont bloquées.' },
                  { label: 'Vérifier la charge par agent', ecran: 'm10-stats-gardes',
                    detail: 'Repos et congés exclus : sinon les plus reposés paraissent les plus chargés.' },
                  { label: 'Les primes suivent le planning validé', poste: 'Paie', detail: 'RG-11.' },
                ],
              },
              {
                titre: 'Superviser les soins', icone: 'clipboard-check', action: 'Vérifier',
                detail: 'Contrôler l’exécution, sans exécuter.',
                etapes: [
                  { label: 'Vérifier les documents de transfusion', ecran: 'm3-transfusion',
                    detail: 'Activité 2 de votre description de poste.' },
                  { label: 'Contrôler les registres', ecran: 'm3-surveillance' },
                  { label: 'Transmettre les statistiques à la zone sanitaire', ecran: 'rapports-bibliotheque',
                    detail: '100 % à bonne date.' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm10-presences', icon: 'user-check', label: 'Présences et retards', detail: 'Pointage du jour' },
              { id: 'm10-planning', icon: 'calendar-clock', label: 'Planning et gardes', detail: 'Vacations du personnel' },
              { id: 'm10-conges', icon: 'palmtree', label: 'Congés et absences', detail: 'Demandes et soldes' },
              { id: 'm10-stats-gardes', icon: 'chart-column', label: 'Statistiques de garde', detail: 'Charge par agent' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * ASSISTANT DE DIRECTION
   * --------------------------------------------------------------------------
   * Activités 7 et 8 de sa description de poste : « faire le recouvrement des
   * créances de la clinique chez les débiteurs particuliers et les compagnies
   * d'assurance » et « suivre le règlement des créances par nos débiteurs et
   * SURTOUT les assureurs ». Le mot « surtout » est dans le document.
   * ======================================================================== */
  global.SIGH.screen('dash-assistant-comptable', {
    title: 'Tableau de bord — Assistant de Direction',
    description: 'Créances assureur, obligations fiscales, point de caisse et inventaires.',
    render: K.dash({
      premierRegard: function () {
        var creances = S.collection('factures').active().filter(function (f) {
          return (f.partAssurance || 0) > 0 && (f.reliquat || 0) > 0;
        });
        var montant = creances.reduce(function (n, f) { return n + (f.partAssurance || 0); }, 0);
        return {
          valeur: montant, unite: 'FCFA de créances assureur',
          question: 'restent à recouvrer',
          vide: 'Aucune créance assureur en cours.',
          ton: 'warning', icone: 'hourglass',
          ecran: 'm9-creances', lienLabel: 'Créances',
          note: 'Activité 8 de votre description de poste : « suivre le règlement des créances par nos '
            + 'débiteurs et SURTOUT les assureurs ». Le mot est dans le document.',
        };
      },
      kpis: function () {
        var ech = S.collection('echeancesFiscales').active().filter(function (e) {
          return !e.paye && String(e.echeance || '') < C.iso(AUJ);
        });
        var jour = S.collection('factures').active().filter(function (f) {
          return String(f.date).slice(0, 10) === C.iso(AUJ);
        });
        var brouillons = S.collection('ecritures').active().filter(function (e) {
          return e.statut === 'brouillon';
        });
        return [
          { label: 'Échéances fiscales dépassées', value: C.num(ech.length), icon: 'siren',
            tone: ech.length ? 'danger' : 'success' },
          { label: 'Encaissé aujourd’hui', value: C.money(jour.reduce(function (n, f) {
            return n + (f.montantPaye || 0); }, 0)), icon: 'banknote', tone: 'success' },
          { label: 'Écritures en brouillon', value: C.num(brouillons.length), icon: 'file-check-2',
            tone: brouillons.length ? 'warning' : 'neutral' },
          { label: 'Réactifs sous seuil', value: C.num(S.collection('produits').active().filter(function (x) {
            return /reactif|réactif/i.test(x.famille || '') && x.seuilAlerte != null && x.stock <= x.seuilAlerte;
          }).length), icon: 'flask-conical', tone: 'info', hint: 'inventaire — activité 23' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Recouvrer les créances', icone: 'hourglass', action: 'Créances',
                detail: 'Activités 7 et 8 de votre description de poste.',
                etapes: [
                  { label: 'Voir les créances assureur', ecran: 'm9-creances' },
                  { label: 'Émettre la facture mère', ecran: 'm9-facture-mere',
                    detail: 'Elle n’est émise que si elle se recoupe exactement avec ses filles.' },
                  { label: 'Relancer les compagnies', ecran: 'm9-relances' },
                  { label: 'Enregistrer le règlement', ecran: 'm9-facture-mere' },
                ],
              },
              {
                titre: 'Tenir les obligations', icone: 'calendar-clock', action: 'Échéances',
                detail: 'Activité 13 — Impôts, CNSS, CCIB.',
                etapes: [
                  { label: 'Suivre le calendrier fiscal', ecran: 'm12-echeances' },
                  { label: 'Déclarer à bonne date', ecran: 'm12-echeances' },
                  { label: 'Payer et classer la quittance', ecran: 'm12-echeances' },
                ],
              },
              {
                titre: 'Point de caisse et inventaires', icone: 'banknote', action: 'Point de caisse',
                detail: 'Activités 23 et 25.',
                etapes: [
                  { label: 'Faire le point journalier de la caisse', ecran: 'm8-caisse',
                    detail: 'En lecture : vous constatez, vous n’encaissez pas.' },
                  { label: 'Inventorier réactifs et médicaments d’urgence', ecran: 'm5-reactifs' },
                  { label: 'Rendre compte à la Direction', poste: 'DAF' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm9-creances', icon: 'hourglass', label: 'Créances', detail: 'Recouvrement — activités 7 et 8' },
              { id: 'm12-echeances', icon: 'calendar-clock', label: 'Échéances fiscales', detail: 'Impôts, CNSS, CCIB — activité 13' },
              { id: 'm8-caisse', icon: 'banknote', label: 'Point de caisse', detail: 'Activité 25 — lecture seule' },
              { id: 'm12-ecritures', icon: 'book-open', label: 'Écritures comptables', detail: 'Livres de compte — activité 1' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * INGÉNIEUR BIOMÉDICAL
   * --------------------------------------------------------------------------
   * Poste rectifié par la Direction le 25/08/2026. Il entretient les automates
   * et le parc technique ; il ne rend AUCUN résultat — la validation biologique
   * engage la responsabilité du biologiste, pas celle du technicien qui a
   * étalonné la machine.
   * ======================================================================== */
  global.SIGH.screen('dash-biomedical', {
    title: 'Tableau de bord — Ingénieur biomédical',
    description: 'Maintenance du parc technique, réactifs et consommables de laboratoire.',
    render: K.dash({
      premierRegard: function () {
        var mat = S.collection('materiel').active().filter(function (m) {
          return m.etat === 'panne' || m.statutMaintenance === 'en_panne';
        });
        return {
          valeur: mat.length, unite: 'matériel(s)',
          question: 'sont signalés en panne',
          vide: 'Aucune panne signalée sur le parc technique.',
          ton: 'danger', icone: 'wrench',
          ecran: 'm13-maintenance', lienLabel: 'Maintenance',
          note: 'Un automate en panne arrête le laboratoire : c’est la première chose à voir. '
            + 'Votre profil n’accède pas aux résultats — la validation biologique engage le biologiste.',
        };
      },
      kpis: function () {
        var reactifs = S.collection('produits').active().filter(function (x) {
          return /reactif|réactif|consommable/i.test(x.famille || '');
        });
        var sous = reactifs.filter(function (x) { return x.seuilAlerte != null && x.stock <= x.seuilAlerte; });
        var sansSeuil = reactifs.filter(function (x) { return x.seuilAlerte == null; });
        return [
          { label: 'Réactifs et consommables', value: C.num(reactifs.length), icon: 'flask-conical', tone: 'navy' },
          { label: 'Sous leur seuil', value: C.num(sous.length), icon: 'package-x',
            tone: sous.length ? 'danger' : 'success' },
          { label: 'Sans seuil fixé', value: C.num(sansSeuil.length), icon: 'circle-help',
            tone: sansSeuil.length ? 'warning' : 'success',
            hint: 'sans seuil, aucune alerte n’est possible' },
          { label: 'Analyses au catalogue', value: C.num(S.collection('examensLabo').active().length),
            icon: 'list', tone: 'neutral' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          /* Remonté avant les indicateurs : c'est par là qu'on commence sa
             journée. Un mode d'emploi placé sous les tableaux ne se lit pas. */
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Tenir les réactifs des automates', icone: 'flask-conical', action: 'Réactifs',
                detail: 'Ce qui fait tourner le laboratoire au quotidien.',
                etapes: [
                  { label: 'Contrôler les seuils et les péremptions', ecran: 'm5-reactifs',
                    detail: 'Une référence sans seuil ne peut déclencher aucune alerte : elle est comptée à part.' },
                  { label: 'Fixer le seuil des références qui n’en ont pas', ecran: 'm5-reactifs',
                    detail: 'Le document SAGE ne renseigne pas cette colonne — c’est à la clinique de la fixer.' },
                  { label: 'Exprimer le besoin', ecran: 'm7-besoins' },
                  { label: 'La Direction accorde', poste: 'DAF', detail: 'RG-04.' },
                ],
              },
              {
                titre: 'Traiter une panne', icone: 'triangle-alert', action: 'Voir le parc',
                detail: 'Un automate ne répond plus.',
                etapes: [
                  { label: 'Passer l’équipement en panne', ecran: 'm13-maintenance',
                    detail: 'Un automate en panne arrête le laboratoire : l’état de marche est la première colonne.' },
                  { label: 'Prévenir le service concerné par note', ecran: 'm13-notes-service' },
                  { label: 'Faire appel au réparateur', poste: 'DAF' },
                  { label: 'Remettre en service et dater l’entretien', ecran: 'm13-maintenance' },
                ],
              },
              {
                titre: 'Tenir le parc à jour', icone: 'wrench', action: 'Compléter les fiches',
                detail: 'Entretiens périodiques et fiches incomplètes.',
                etapes: [
                  { label: 'Relever les entretiens échus', ecran: 'm13-maintenance',
                    detail: 'La périodicité vaut six mois sur les automates et l’énergie, douze ailleurs.' },
                  { label: 'Compléter marque, n° de série et mise en service', ecran: 'm13-maintenance',
                    detail: 'Le parc amorcé est une proposition : aucun document ne l’inventorie.' },
                  { label: 'Le registre comptable suit', ecran: 'm12-immobilisations',
                    poste: 'Comptabilité', detail: 'Les amortissements se calculent là, pas ici.' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm5-reactifs', icon: 'flask-conical', label: 'Réactifs & consommables', detail: 'Seuils et alertes' },
              { id: 'm13-maintenance', icon: 'wrench', label: 'Maintenance', detail: 'Parc technique' },
              { id: 'm6-produits', icon: 'package', label: 'Référentiel produits', detail: 'Lecture' },
              { id: 'm7-commandes', icon: 'shopping-cart', label: 'Commandes', detail: 'Lecture' },
            ]);
          },
        },
        {
          title: 'Ce que votre profil ne voit pas',
          render: function () {
            return K.note('Vous entretenez les automates ; vous ne rendez <strong>aucun résultat</strong>. '
              + 'La validation biologique engage la responsabilité du biologiste, pas celle du technicien qui '
              + 'a étalonné la machine — l’écran des résultats vous est donc fermé.',
            { tone: 'info', icon: 'shield' });
          },
        },
      ],
    }),
  });


  /* ==========================================================================
   * STATISTIQUES DE L'\u00c9CHOGRAPHIE (phase 8 \u2014 Pilotage)
   * --------------------------------------------------------------------------
   * CALCUL\u00c9ES depuis les registres \u2014 demandes d'imagerie et comptes
   * rendus \u2014 jamais fournies. La doctrine de la vague 37 : toute
   * statistique vit sous PIL et se filtre par r\u00f4le.
   * ======================================================================== */
  global.SIGH.screen('m2-stats-echographie', {
    title: 'Statistiques de l\u2019imagerie m\u00e9dicale',
    description: 'Activit\u00e9 d\u2019imagerie calcul\u00e9e depuis les registres : examens par type, par mois, d\u00e9lais et part obst\u00e9tricale.',
    regle: 'Les chiffres sont <strong>calcul\u00e9s</strong> depuis les demandes et les comptes rendus \u2014 '
      + 'jamais fournis. Un indicateur \u00e0 z\u00e9ro se lit : il dit qu\u2019aucun registre ne porte la '
      + 'donn\u00e9e, pas que l\u2019activit\u00e9 n\u2019existe pas.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);

      var dems = S.collection('demandesImagerie').active();
      var crs = S.collection('resultatsImagerie').active();
      var rendus = crs.filter(function (r) { return r.statut === 'rendu'; });
      var obst = crs.filter(function (r) { return /OBS/.test(r.examenCode || ''); });

      /* Le d\u00e9lai demande \u2192 rendu, sur les seules paires TRAC\u00c9ES. */
      var delais = [];
      rendus.forEach(function (r) {
        if (!r.demandeImagerieId) return;
        var d = S.collection('demandesImagerie').get(r.demandeImagerieId);
        if (!d || !d.dateHeure || !r.renduLe) return;
        var h = (new Date(r.renduLe) - new Date(d.dateHeure)) / 36e5;
        if (h >= 0 && h < 24 * 30) delais.push(h);
      });
      var delaiMoyen = delais.length
        ? Math.round(delais.reduce(function (n, x) { return n + x; }, 0) / delais.length)
        : null;

      host.appendChild(U.kpiGrid([
        { label: 'Comptes rendus \u00e9mis', value: C.num(crs.length), icon: 'scan-line', tone: 'navy' },
        { label: 'Rendus au prescripteur', value: C.num(rendus.length), icon: 'file-check-2', tone: 'success' },
        {
          label: 'Part obst\u00e9tricale',
          value: crs.length ? C.pct(obst.length / crs.length * 100) : '\u2014',
          icon: 'baby', tone: 'info',
        },
        {
          label: 'D\u00e9lai moyen demande \u2192 rendu',
          value: delaiMoyen == null ? '\u2014' : C.num(delaiMoyen) + ' h',
          icon: 'clock', tone: 'neutral',
          hint: delaiMoyen == null ? 'Aucune paire demande/CR trac\u00e9e' : delais.length + ' paire(s) trac\u00e9e(s)',
        },
      ]));

      var parExamen = {};
      crs.forEach(function (r) { parExamen[r.examen || r.examenCode] = (parExamen[r.examen || r.examenCode] || 0) + 1; });
      var cles = Object.keys(parExamen).sort(function (a, b) { return parExamen[b] - parExamen[a]; });

      var parMois = {};
      crs.forEach(function (r) {
        var m = String(r.date || '').slice(0, 7);
        if (m) parMois[m] = (parMois[m] || 0) + 1;
      });
      var mois = Object.keys(parMois).sort().slice(-6);

      host.appendChild(K.charts([
        {
          title: 'Examens par type',
          render: function () {
            return cles.length
              ? G.barres(cles, [{ label: 'Comptes rendus', data: cles.map(function (k) { return parExamen[k]; }) }],
                { horizontal: true, height: 260 })
              : U.empty('Aucun compte rendu \u00e0 compter.', { icon: 'scan-line' });
          },
        },
        {
          title: '\u00c9volution mensuelle',
          render: function () {
            return mois.length
              ? G.barres(mois, [{ label: 'Comptes rendus', data: mois.map(function (m) { return parMois[m]; }) }],
                { height: 260 })
              : U.empty('Aucun mois \u00e0 tracer.', { icon: 'calendar' });
          },
        },
      ]));

      var parRealisateur = {};
      crs.forEach(function (r) { parRealisateur[r.realisateur || '\u2014'] = (parRealisateur[r.realisateur || '\u2014'] || 0) + 1; });
      host.appendChild(U.card('Par r\u00e9alisateur \u2014 le pied des pi\u00e8ces r\u00e9elles porte \u00ab R\u00e9alis\u00e9 par \u00bb',
        K.ranking(Object.keys(parRealisateur).map(function (k) {
          return { label: k, value: parRealisateur[k] };
        }).sort(function (a, b) { return b.value - a.value; }))));

      host.appendChild(K.source('Registres demandesImagerie et resultatsImagerie du magasin \u2014 indicateurs '
        + 'recalcul\u00e9s \u00e0 chaque affichage.'));
      U.icons(host);
      return null;
    },
  });


  /* ==========================================================================
   * PHASE 9 \u2014 PILOTAGE & STATISTIQUES TRANSVERSES
   * --------------------------------------------------------------------------
   * La demande \u00e9crite du laboratoire (reunions/) : \u00ab les statistiques des
   * examens selon plusieurs axes \u00bb \u2014 service, \u00e2ge, sexe, p\u00e9riode,
   * interne/externe. Puis les consultations par praticien, le bloc et
   * l'anesth\u00e9sie, le co\u00fbt global de l'agent et la lecture par groupe de
   * prestation. TOUT est CALCUL\u00c9 depuis les registres \u2014 jamais fourni \u2014
   * et vit sous PIL (doctrine vague 37), filtr\u00e9 par r\u00f4le au manifeste.
   * ======================================================================== */

  var TRANCHES_AGE_STATS = [
    { id: '0-4', label: '0\u20134 ans', de: 0, a: 4 },
    { id: '5-14', label: '5\u201314 ans', de: 5, a: 14 },
    { id: '15-24', label: '15\u201324 ans', de: 15, a: 24 },
    { id: '25-44', label: '25\u201344 ans', de: 25, a: 44 },
    { id: '45-64', label: '45\u201364 ans', de: 45, a: 64 },
    { id: '65+', label: '65 ans et plus', de: 65, a: 200 },
  ];

  global.SIGH.screen('m5-stats-examens', {
    title: 'Statistiques des examens',
    description: 'Les examens du laboratoire selon plusieurs axes : service demandeur, \u00e2ge, sexe, p\u00e9riode, interne ou externe.',
    regle: 'La demande \u00e9crite du laboratoire : \u00ab les statistiques des examens selon plusieurs axes \u00bb. '
      + 'Chaque axe est un <strong>filtre</strong> \u2014 les compteurs, les graphiques et le tableau se '
      + 'recalculent sur la population filtr\u00e9e, jamais fournis. Le p\u00e9rim\u00e8tre suit le RBAC du manifeste.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);

      var parPatient = {};
      S.collection('patients').active().forEach(function (p) { parPatient[p.id] = p; });

      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var selService = el('select.select');
      var selSexe = el('select.select');
      var selAge = el('select.select');
      var selOrigine = el('select.select');

      var services = {};
      S.collection('demandesAnalyses').active().forEach(function (r) {
        var s = r.secteurDemandeur || r.serviceDemandeur;
        if (s) services[s] = true;
      });
      selService.appendChild(el('option', { value: '' }, 'Tous les services'));
      Object.keys(services).sort().forEach(function (s) {
        selService.appendChild(el('option', { value: s }, s));
      });
      selSexe.appendChild(el('option', { value: '' }, 'Deux sexes'));
      selSexe.appendChild(el('option', { value: 'F' }, 'F\u00e9minin'));
      selSexe.appendChild(el('option', { value: 'M' }, 'Masculin'));
      selAge.appendChild(el('option', { value: '' }, 'Tous les \u00e2ges'));
      TRANCHES_AGE_STATS.forEach(function (tr) {
        selAge.appendChild(el('option', { value: tr.id }, tr.label));
      });
      selOrigine.appendChild(el('option', { value: '' }, 'Internes et externes'));
      selOrigine.appendChild(el('option', { value: 'interne' }, 'Patients internes'));
      selOrigine.appendChild(el('option', { value: 'externe' }, 'Patients externes'));

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.grid.gap-3.md:grid-cols-3.lg:grid-cols-6', null, [
        el('div', null, [el('label.label', { text: 'Du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'Au' }), dFin]),
        el('div', null, [el('label.label', { text: 'Service demandeur' }), selService]),
        el('div', null, [el('label.label', { text: 'Sexe' }), selSexe]),
        el('div', null, [el('label.label', { text: 'Tranche d\u2019\u00e2ge' }), selAge]),
        el('div', null, [el('label.label', { text: 'Origine' }), selOrigine]),
      ]));
      host.appendChild(barre);
      var vue = el('div.space-y-4');
      host.appendChild(vue);
      [dDebut, dFin, selService, selSexe, selAge, selOrigine].forEach(function (x) {
        x.addEventListener('change', afficher);
      });
      afficher();
      U.icons(host);
      return null;

      function retenues() {
        return S.collection('demandesAnalyses').active().filter(function (r) {
          var d = String(r.dateHeure || '').slice(0, 10);
          if (dDebut.value && d < dDebut.value) return false;
          if (dFin.value && d > dFin.value) return false;
          if (selService.value
            && (r.secteurDemandeur || r.serviceDemandeur) !== selService.value) return false;
          var p = parPatient[r.patientId];
          if (selSexe.value && (!p || p.sexe !== selSexe.value)) return false;
          if (selAge.value) {
            var tr = TRANCHES_AGE_STATS.filter(function (x) { return x.id === selAge.value; })[0];
            var age = p && p.dateNaissance ? C.age(p.dateNaissance) : null;
            if (age == null || age < tr.de || age > tr.a) return false;
          }
          if (selOrigine.value === 'externe' && r.origineDemande !== 'externe') return false;
          if (selOrigine.value === 'interne' && r.origineDemande === 'externe') return false;
          return true;
        });
      }

      function afficher() {
        var rows = retenues();
        var rendus = rows.filter(function (r) { return D.resultatRendu(r.etatAnalyse); });
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Examens (population filtr\u00e9e)', value: C.num(rows.length), icon: 'flask-conical', tone: 'navy' },
          { label: 'R\u00e9sultats rendus', value: C.num(rendus.length), icon: 'file-check-2', tone: 'success' },
          { label: 'Urgents', value: C.num(rows.filter(function (r) { return r.urgent; }).length), icon: 'siren', tone: 'warning' },
          { label: 'Patients externes', value: C.num(rows.filter(function (r) { return r.origineDemande === 'externe'; }).length),
            icon: 'user-plus', tone: 'info' },
        ]));

        var parCategorie = {}, parServiceN = {}, parTranche = {};
        TRANCHES_AGE_STATS.forEach(function (tr) { parTranche[tr.label] = 0; });
        rows.forEach(function (r) {
          parCategorie[r.categorie || 'Autres'] = (parCategorie[r.categorie || 'Autres'] || 0) + 1;
          var s = r.secteurDemandeur || r.serviceDemandeur || 'Non renseign\u00e9';
          parServiceN[s] = (parServiceN[s] || 0) + 1;
          var p = parPatient[r.patientId];
          var age = p && p.dateNaissance ? C.age(p.dateNaissance) : null;
          if (age != null) {
            var tr2 = TRANCHES_AGE_STATS.filter(function (x) { return age >= x.de && age <= x.a; })[0];
            if (tr2) parTranche[tr2.label] += 1;
          }
        });
        var cCat = Object.keys(parCategorie).sort(function (a, b) { return parCategorie[b] - parCategorie[a]; });
        var cSer = Object.keys(parServiceN).sort(function (a, b) { return parServiceN[b] - parServiceN[a]; });
        var cTra = TRANCHES_AGE_STATS.map(function (x) { return x.label; });

        vue.appendChild(K.charts([
          { title: 'Par section d\u2019examen', render: function () {
            return cCat.length
              ? G.barres(cCat, [{ label: 'Examens', data: cCat.map(function (k) { return parCategorie[k]; }) }], { horizontal: true, height: 260 })
              : U.empty('Aucun examen dans la population filtr\u00e9e.', { icon: 'flask-conical' });
          } },
          { title: 'Par service demandeur', render: function () {
            return cSer.length
              ? G.barres(cSer, [{ label: 'Examens', data: cSer.map(function (k) { return parServiceN[k]; }) }], { horizontal: true, height: 260 })
              : U.empty('Aucun service \u00e0 compter.', { icon: 'building-2' });
          } },
        ]));
        vue.appendChild(U.card('Par tranche d\u2019\u00e2ge',
          G.barres(cTra, [{ label: 'Examens', data: cTra.map(function (k) { return parTranche[k]; }) }], { height: 220 })));

        var parExamen = {};
        rows.forEach(function (r) { parExamen[r.analyse] = (parExamen[r.analyse] || 0) + 1; });
        var lignes = Object.keys(parExamen).sort(function (a, b) { return parExamen[b] - parExamen[a]; })
          .map(function (k) { return { examen: k, compte: parExamen[k] }; });
        vue.appendChild(U.dataTable({ searchable: true,
          title: 'D\u00e9tail par examen', rows: lignes, pageSize: 15, exportName: 'stats-examens',
          emptyMessage: 'Rien \u00e0 compter sur ces axes.',
          columns: [
            { key: 'examen', label: 'Examen' },
            { key: 'compte', label: 'Demandes', align: 'right' },
          ],
        }));
        vue.appendChild(K.source('Registre demandesAnalyses du magasin \u2014 recalcul\u00e9 \u00e0 chaque filtre. '
          + 'Les axes sont ceux de la demande \u00e9crite du laboratoire (reunions/).'));
        U.icons(vue);
      }
    },
  });

  global.SIGH.screen('m2-stats-consultations', {
    title: 'Statistiques des consultations',
    description: 'L\u2019activit\u00e9 de consultation par praticien, par type et dans le temps \u2014 calcul\u00e9e depuis le registre.',
    regle: 'Par praticien et par type, depuis le registre des consultations. Le \u00ab secteur \u00bb affich\u00e9 est '
      + 'le <strong>service du praticien \u00e0 l\u2019organigramme</strong> \u2014 la consultation ne porte pas de '
      + 'secteur propre, et l\u2019\u00e9cran le dit plut\u00f4t que d\u2019inventer une donn\u00e9e.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var barreDates = el('div.card');
      barreDates.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'au' }), dFin]),
        K.btn('Toute la p\u00e9riode', { size: 'sm', icon: 'x', onclick: function () { dDebut.value = ''; dFin.value = ''; afficher(); } }),
      ]));
      host.appendChild(barreDates);
      [dDebut, dFin].forEach(function (x) { x.addEventListener('change', afficher); });
      var vueStats = el('div.space-y-4');
      host.appendChild(vueStats);
      afficher();
      U.icons(host);
      return null;

      function afficher() {
      var hostReel = host; var host2 = vueStats; C.clear(vueStats);
      var rows = S.collection('consultations').active().filter(function (r) {
        var d = String(r.date || '').slice(0, 10);
        if (dDebut.value && d < dDebut.value) return false;
        if (dFin.value && d > dFin.value) return false;
        return true;
      });
      var agents = {};
      S.collection('personnel').active().forEach(function (a) { agents[a.nomComplet] = a; });
      var moisCourant = C.iso(new Date()).slice(0, 7);

      vueStats.appendChild(U.kpiGrid([
        { label: 'Consultations au registre', value: C.num(rows.length), icon: 'stethoscope', tone: 'navy' },
        { label: 'Ce mois-ci', value: C.num(rows.filter(function (r) { return String(r.date || '').slice(0, 7) === moisCourant; }).length),
          icon: 'calendar', tone: 'info' },
        { label: 'Praticiens actifs', value: C.num(Object.keys(rows.reduce(function (a, r) { a[r.medecin] = 1; return a; }, {})).length),
          icon: 'users', tone: 'neutral' },
        { label: '\u00c0 domicile', value: C.num(rows.filter(function (r) { return r.type === 'Domicile'; }).length),
          icon: 'house', tone: 'neutral' },
      ]));

      var parPraticien = {};
      rows.forEach(function (r) { parPraticien[r.medecin || '\u2014'] = (parPraticien[r.medecin || '\u2014'] || 0) + 1; });
      vueStats.appendChild(U.card('Par praticien \u2014 et son service \u00e0 l\u2019organigramme',
        K.ranking(Object.keys(parPraticien).map(function (k) {
          var a = agents[k];
          return { label: k + (a ? ' \u2014 ' + (a.service || '') : ''), value: parPraticien[k] };
        }).sort(function (a, b) { return b.value - a.value; }))));

      var parType = {};
      rows.forEach(function (r) { parType[r.type || 'Consultation'] = (parType[r.type || 'Consultation'] || 0) + 1; });
      var types = Object.keys(parType);
      var parMois = {};
      rows.forEach(function (r) {
        var m = String(r.date || '').slice(0, 7);
        if (m) parMois[m] = (parMois[m] || 0) + 1;
      });
      var mois = Object.keys(parMois).sort().slice(-6);
      vueStats.appendChild(K.charts([
        { title: 'Par type', render: function () {
          return G.anneau(types, types.map(function (k) { return parType[k]; }), { legend: 'bottom' });
        } },
        { title: '\u00c9volution mensuelle', render: function () {
          return G.barres(mois, [{ label: 'Consultations', data: mois.map(function (m) { return parMois[m]; }) }], { height: 240 });
        } },
      ]));
      vueStats.appendChild(K.source('Registre des consultations du magasin \u2014 indicateurs recalcul\u00e9s \u00e0 chaque affichage.'));
      U.icons(host);
      U.icons(vueStats);
      }

    },
  });

  global.SIGH.screen('m3-stats-bloc', {
    title: 'Statistiques du bloc & de l\u2019anesth\u00e9sie',
    description: 'Comptes rendus op\u00e9ratoires, comptes rendus d\u2019anesth\u00e9sie et CPA \u2014 calcul\u00e9s depuis les registres du bloc.',
    regle: 'Les interventions <strong>sans CPA</strong> sont compt\u00e9es \u2014 signal\u00e9es, jamais bloqu\u00e9es : '
      + 'l\u2019urgence n\u2019attend pas une fiche. Un incident per-op\u00e9ratoire compte d\u00e8s qu\u2019il est '
      + '<strong>nomm\u00e9</strong> \u2014 \u00ab aucun incident \u00bb s\u2019\u00e9crit et ne compte pas.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var barreDates = el('div.card');
      barreDates.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'au' }), dFin]),
        K.btn('Toute la p\u00e9riode', { size: 'sm', icon: 'x', onclick: function () { dDebut.value = ''; dFin.value = ''; afficher(); } }),
      ]));
      host.appendChild(barreDates);
      [dDebut, dFin].forEach(function (x) { x.addEventListener('change', afficher); });
      function dansPlage(d) {
        var x = String(d || '').slice(0, 10);
        if (dDebut.value && x < dDebut.value) return false;
        if (dFin.value && x > dFin.value) return false;
        return true;
      }
      var vueStats = el('div.space-y-4');
      host.appendChild(vueStats);
      afficher();
      U.icons(host);
      return null;

      function afficher() {
      C.clear(vueStats);
      var cros = S.collection('crOperatoires').active().filter(function (r) { return dansPlage(r.dateOperation); });
      var cras = S.collection('crAnesthesie').active().filter(function (r) { return dansPlage(r.dateOperation); });
      var cpas = S.collection('cpa').active().filter(function (r) { return dansPlage(r.date); });
      var avecCpa = {};
      cpas.forEach(function (r) { avecCpa[r.patientId] = true; });
      var sansCpa = cros.filter(function (c) { return c.patientId && !avecCpa[c.patientId]; });
      var incidents = cras.filter(function (r) {
        return r.incidents && !/^aucun/i.test(String(r.incidents).trim());
      });

      vueStats.appendChild(U.kpiGrid([
        { label: 'Comptes rendus op\u00e9ratoires', value: C.num(cros.length), icon: 'scissors', tone: 'navy' },
        { label: 'Comptes rendus d\u2019anesth\u00e9sie', value: C.num(cras.length), icon: 'syringe', tone: 'info' },
        { label: 'CPA enregistr\u00e9es', value: C.num(cpas.length), icon: 'stethoscope', tone: 'neutral' },
        { label: 'Interventions sans CPA', value: C.num(sansCpa.length), icon: 'shield-alert',
          tone: sansCpa.length ? 'danger' : 'success', hint: 'Signal\u00e9es, jamais bloqu\u00e9es' },
      ]));

      var parOperateur = {};
      cros.forEach(function (r) { parOperateur[r.operateur || '\u2014'] = (parOperateur[r.operateur || '\u2014'] || 0) + 1; });
      vueStats.appendChild(U.card('Interventions par op\u00e9rateur',
        Object.keys(parOperateur).length
          ? K.ranking(Object.keys(parOperateur).map(function (k) { return { label: k, value: parOperateur[k] }; })
            .sort(function (a, b) { return b.value - a.value; }))
          : U.empty('Aucun compte rendu op\u00e9ratoire au registre.', { icon: 'scissors' })));

      var parTechnique = {};
      cras.forEach(function (r) { parTechnique[r.technique || '\u2014'] = (parTechnique[r.technique || '\u2014'] || 0) + 1; });
      var techs = Object.keys(parTechnique);
      var parConclusion = {};
      cpas.forEach(function (r) { parConclusion[r.conclusion || '\u2014'] = (parConclusion[r.conclusion || '\u2014'] || 0) + 1; });
      var concl = Object.keys(parConclusion);
      vueStats.appendChild(K.charts([
        { title: 'Anesth\u00e9sies par technique', render: function () {
          return techs.length
            ? G.barres(techs, [{ label: 'CR', data: techs.map(function (k) { return parTechnique[k]; }) }], { horizontal: true, height: 220 })
            : U.empty('Aucun compte rendu d\u2019anesth\u00e9sie.', { icon: 'syringe' });
        } },
        { title: 'Conclusions des CPA', render: function () {
          return concl.length
            ? G.anneau(concl, concl.map(function (k) { return parConclusion[k]; }), { legend: 'bottom' })
            : U.empty('Aucune CPA au registre.', { icon: 'stethoscope' });
        } },
      ]));
      vueStats.appendChild(U.kpiGrid([
        { label: 'Incidents per-op\u00e9ratoires NOMM\u00c9S', value: C.num(incidents.length), icon: 'triangle-alert',
          tone: incidents.length ? 'warning' : 'success' },
        { label: 'Surveillances prolong\u00e9es en r\u00e9veil', value: C.num(cras.filter(function (r) {
          return r.decisionSortie === 'Surveillance prolong\u00e9e en salle de r\u00e9veil';
        }).length), icon: 'clock', tone: 'neutral' },
      ]));
      vueStats.appendChild(K.source('Registres crOperatoires, crAnesthesie et cpa du magasin.'));
      U.icons(host);
      U.icons(vueStats);
      }

    },
  });

  global.SIGH.screen('m10-cout-agent', {
    title: 'Co\u00fbt global de l\u2019agent',
    description: 'Ce que co\u00fbte un agent \u00e0 l\u2019\u00e9tablissement \u2014 salaire et charges patronales \u2014 et l\u2019historique de ses paies.',
    regle: 'Deux colonnes \u00e0 ne <strong>jamais additionner</strong> : le <strong>co\u00fbt employeur</strong> '
      + '(brut + CNSS patronale 16,4 % + VPS 4 %) et les <strong>retenues de l\u2019agent</strong> (CNSS '
      + 'ouvri\u00e8re 3,6 %, ORTB), qui sortent de SON salaire, pas de la caisse de la clinique. L\u2019ITS, '
      + 'progressif, se lit sur le bulletin \u2014 le recalculer ici cr\u00e9erait une seconde v\u00e9rit\u00e9.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var agents = C.sortBy(S.collection('personnel').active(), 'nomComplet');
      var PP = D.PARAM_PAIE || {};
      var sel = U.combo(agents.map(function (a) {
        return { value: a.id, label: a.nomComplet + ' \u2014 ' + (a.poste || '') };
      }), { placeholder: '\u2014 Choisir un agent \u2014' });
      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div.min-w-\\[20rem\\].flex-1', null, [el('label.label', { text: 'Agent' }), sel]),
        el('div', null, [el('label.label', { text: 'Paies du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'au' }), dFin]),
      ]));
      host.appendChild(barre);
      var vue = el('div.space-y-4');
      host.appendChild(vue);
      sel.addEventListener('change', afficher);
      [dDebut, dFin].forEach(function (x) { x.addEventListener('change', afficher); });
      vue.appendChild(U.empty('Choisir un agent pour lire son co\u00fbt global et l\u2019historique de ses paies.', { icon: 'user' }));
      U.icons(host);
      return null;

      function afficher() {
        var a = agents.filter(function (x) { return x.id === sel.value; })[0];
        C.clear(vue);
        if (!a) return;
        var brut = a.salaireBase || 0;
        var patronale = Math.round(brut * ((PP.cnss && PP.cnss.patronale) || 16.4) / 100);
        var vps = Math.round(brut * ((PP.vps && PP.vps.taux) || 4) / 100);
        var coutMensuel = brut + patronale + vps;
        var ouvriere = Math.round(brut * ((PP.cnss && PP.cnss.ouvriere) || 3.6) / 100);
        var ortbAnnuel = 1000 + (brut > ((PP.ortb && PP.ortb.seuilTele) || 60000) ? 3000 : 0);

        vue.appendChild(U.kpiGrid([
          { label: 'Salaire brut mensuel', value: C.money(brut), icon: 'wallet', tone: 'navy' },
          { label: 'Co\u00fbt employeur mensuel', value: C.money(coutMensuel), icon: 'building-2', tone: 'info',
            hint: 'Brut + CNSS patronale + VPS' },
          { label: 'Co\u00fbt employeur annuel', value: C.money(coutMensuel * 12), icon: 'calendar', tone: 'neutral' },
          { label: 'ORTB annuel (retenue agent)', value: C.money(ortbAnnuel), icon: 'radio', tone: 'neutral',
            hint: brut > 60000 ? 'Radio 1 000 + T\u00e9l\u00e9 3 000 \u2014 elles se CUMULENT' : 'Radio seule (brut \u2264 60 000)' },
        ]));

        vue.appendChild(U.card('Composition mensuelle', K.miniTable(['Poste', 'Qui le supporte', 'Montant'], [
          ['Salaire brut', 'Employeur', C.money(brut, false)],
          ['CNSS \u2014 part patronale ' + ((PP.cnss && PP.cnss.patronale) || 16.4) + ' %', 'Employeur', C.money(patronale, false)],
          ['VPS ' + ((PP.vps && PP.vps.taux) || 4) + ' %', 'Employeur', C.money(vps, false)],
          ['CO\u00dbT EMPLOYEUR', '', C.money(coutMensuel, false)],
          ['CNSS \u2014 part ouvri\u00e8re ' + ((PP.cnss && PP.cnss.ouvriere) || 3.6) + ' %', 'Retenue \u00e0 l\u2019agent', C.money(ouvriere, false)],
        ])));

        var bulls = S.collection('bulletins').active().filter(function (b) {
          if (!(b.personnelId === a.id || b.agentId === a.id || b.nomComplet === a.nomComplet || b.agent === a.nomComplet)) return false;
          /* La plage filtre l'historique : la p\u00e9riode du bulletin (mois/ann\u00e9e). */
          var d = b.date || (b.annee != null && b.mois != null
            ? b.annee + '-' + ('0' + (Number(b.mois) + 1)).slice(-2) + '-01' : null);
          if (d) {
            var x = String(d).slice(0, 10);
            if (dDebut.value && x < dDebut.value) return false;
            if (dFin.value && x > dFin.value) return false;
          }
          return true;
        });
        var avs = S.collection('avances').active().filter(function (x) {
          return x.personnelId === a.id || x.agent === a.nomComplet;
        });
        vue.appendChild(U.dataTable({ searchable: true,
          title: 'Historique des paies \u2014 ' + a.nomComplet, rows: bulls,
          pageSize: 12, exportName: 'historique-paies',
          emptyMessage: 'Aucun bulletin \u00e9mis pour cet agent : la paie se g\u00e9n\u00e8re \u00e0 l\u2019\u00e9cran '
            + '\u00ab Calcul de la paie \u00bb (M11). Cet \u00e9cran LIT, il ne g\u00e9n\u00e8re pas.',
          columns: [
            { key: 'periode', label: 'P\u00e9riode', render: function (b) { return b.periode || (b.mois != null ? C.MOIS[b.mois] + ' ' + (b.annee || 2026) : '\u2014'); } },
            { key: 'brut', label: 'Brut', align: 'right', render: function (b) { return C.money(b.brut, false); } },
            { key: 'net', label: 'Net pay\u00e9', align: 'right', render: function (b) { return C.money(b.net, false); } },
          ],
        }));
        if (avs.length) {
          vue.appendChild(K.note(C.num(avs.length) + ' avance(s) sur salaire au dossier \u2014 elles transitent, '
            + 'elles ne sont ni recette ni charge : le d\u00e9tail vit \u00e0 l\u2019\u00e9cran des avances (M11).',
          { tone: 'info', icon: 'hand-coins' }));
        }
        U.icons(vue);
      }
    },
  });

  global.SIGH.screen('m12-rentabilite-groupes', {
    title: 'Recettes & charges par groupe',
    description: 'Recettes par groupe de prestation, charges par centre de co\u00fbts, et le b\u00e9n\u00e9fice brut par groupe \u2014 rapprochement arr\u00eat\u00e9.',
    regle: 'Les <strong>recettes</strong> se lisent par groupe de prestation (les cat\u00e9gories des lignes '
      + 'payables) ; les <strong>charges</strong> par centre de co\u00fbts (\u00e9critures VALID\u00c9ES de classe 6). '
      + 'Le rapprochement centre \u2192 groupe a \u00e9t\u00e9 <strong>ARR\u00caT\u00c9 par la Direction le 01/09/2026</strong> '
      + 'et s\u2019affiche centre par centre, contestable ligne \u00e0 ligne. Les charges <strong>transverses</strong> '
      + '(administration, entretien, ambulance) ne sont pas ventil\u00e9es : les r\u00e9partir exigerait une cl\u00e9 '
      + 'qu\u2019aucun document ne donne \u2014 le b\u00e9n\u00e9fice brut se lit AVANT elles. '
      + '<strong>Les deux colonnes viennent de DEUX registres</strong> : les recettes des lignes de '
      + 'facture (M8), les charges du journal (M12). Ils ne se calibrent pas l\u2019un sur l\u2019autre, et le '
      + 'jeu de d\u00e9monstration en porte la marque \u2014 c\u2019est la R\u00c9PARTITION entre groupes qui s\u2019y lit, '
      + 'pas le r\u00e9sultat de l\u2019exercice, qui se lit au <em>compte de r\u00e9sultat</em>.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var barreDates = el('div.card');
      barreDates.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'au' }), dFin]),
        K.btn('Toute la p\u00e9riode', { size: 'sm', icon: 'x', onclick: function () { dDebut.value = ''; dFin.value = ''; afficher(); } }),
      ]));
      host.appendChild(barreDates);
      [dDebut, dFin].forEach(function (x) { x.addEventListener('change', afficher); });
      function dansPlage(d) {
        var x = String(d || '').slice(0, 10);
        if (dDebut.value && x < dDebut.value) return false;
        if (dFin.value && x > dFin.value) return false;
        return true;
      }
      var vueStats = el('div.space-y-4');
      host.appendChild(vueStats);
      afficher();
      U.icons(host);
      return null;

      function afficher() {
      C.clear(vueStats);
      var groupes = D.GROUPES_PRESTATION || [];
      var parGroupe = {};
      groupes.forEach(function (g) { parGroupe[g.id] = 0; });
      var horsGroupe = 0;
      S.collection('factures').active().filter(function (fa) { return dansPlage(fa.date); }).forEach(function (fa) {
        (fa.lignes || []).forEach(function (l) {
          /* LA LIGNE ENTIÈRE est passée au moteur, et pas seulement sa
             catégorie : un accouchement et un pansement sont tous deux des
             « actes », seul le secteur du catalogue les sépare. */
          var g = D.groupePrestation(l.categorie, l);
          if (g && parGroupe[g.id] != null) parGroupe[g.id] += l.montant || 0;
          else horsGroupe += l.montant || 0;
        });
      });
      var ecritures = S.collection('ecritures').active().filter(function (e) {
        return dansPlage(e.date) && e.statut === 'validee' && String(e.compte || '').charAt(0) === '6';
      });
      var brouillons = S.collection('ecritures').active().filter(function (e) {
        return dansPlage(e.date) && e.statut === 'brouillon' && String(e.compte || '').charAt(0) === '6';
      });
      var parCentre = {};
      ecritures.forEach(function (e) {
        var c = e.centreCout || 'non_impute';
        parCentre[c] = (parCentre[c] || 0) + (e.debit || 0) - (e.credit || 0);
      });
      /* LE LIBELL\u00c9, PAS L'IDENTIFIANT : la colonne affichait \u00ab laboratoire \u00bb
         et \u00ab hospitalisation \u00bb en minuscules techniques. Le centre se lit
         dans le r\u00e9f\u00e9rentiel administrable, celui-l\u00e0 m\u00eame que le comptable
         choisit en saisissant son \u00e9criture. */
      var centres = S.collection('centresCouts').all();
      function libelleCentre(cle) {
        if (cle === 'non_impute') return 'Non imput\u00e9';
        var c = centres.filter(function (x) { return x.code === cle; })[0];
        if (c) return c.libelle;
        var d = (D.CENTRES_COUT || []).filter(function (x) { return x.id === cle; })[0];
        return d ? d.label : cle;
      }

      var totalRecettes = groupes.reduce(function (n, g) { return n + parGroupe[g.id]; }, 0) + horsGroupe;
      var totalCharges = Object.keys(parCentre).reduce(function (n, k) { return n + parCentre[k]; }, 0);

      vueStats.appendChild(U.kpiGrid([
        { label: 'Recettes factur\u00e9es (lignes)', value: C.money(totalRecettes), icon: 'receipt', tone: 'navy' },
        { label: 'Charges valid\u00e9es (classe 6)', value: C.money(totalCharges), icon: 'wallet', tone: 'info' },
        { label: '\u00c9cart brut global', value: C.money(totalRecettes - totalCharges), icon: 'scale',
          tone: totalRecettes - totalCharges >= 0 ? 'success' : 'danger',
          hint: 'Deux registres distincts \u2014 la r\u00e9partition se lit, pas le r\u00e9sultat' },
        { label: 'Brouillons \u00e9cart\u00e9s', value: C.num(brouillons.length), icon: 'file-question', tone: 'neutral',
          hint: 'Un brouillon n\u2019est pas un fait comptable' },
      ]));

      vueStats.appendChild(U.card('Recettes par groupe de prestation', K.miniTable(['Groupe', 'Recettes'],
        groupes.map(function (g) { return [g.label, C.money(parGroupe[g.id], false)]; })
          .concat(horsGroupe ? [['Hors groupe (cat\u00e9gorie non class\u00e9e)', C.money(horsGroupe, false)]] : []))));

      /* LE RAPPROCHEMENT ARR\u00caT\u00c9 (01/09/2026, vague 51) : chaque centre est
         rattach\u00e9 \u00e0 un groupe par le LIBELL\u00c9 qu'il porte r\u00e9ellement sur les
         \u00e9critures \u2014 les supports (administration, direction, entretien,
         ambulance) restent TRANSVERSES, non ventil\u00e9s : leur r\u00e9partir des
         quotes-parts inventerait une cl\u00e9 qu'aucun document ne donne. */
      /* UNE SEULE R\u00c8GLE DE RATTACHEMENT, celle du socle : le vocabulaire des
         secteurs vit dans `D.secteurNormalise`, et le rapprochement n'en tient
         pas un second qui divergerait au premier renommage de centre.
         `null` = support transverse (Direction, entretien, ambulance). */
      function groupeDuCentre(cle) {
        var g = D.groupeDuSecteur(cle) || D.groupeDuSecteur(libelleCentre(cle));
        return g ? g.id : null;
      }
      var chargesParGroupe = {}, transverses = 0;
      var rattachements = [];
      Object.keys(parCentre).forEach(function (k) {
        var g = groupeDuCentre(k);
        if (g) chargesParGroupe[g] = (chargesParGroupe[g] || 0) + parCentre[k];
        else transverses += parCentre[k];
        rattachements.push([libelleCentre(k), C.money(parCentre[k], false),
          g ? (groupes.filter(function (x) { return x.id === g; })[0] || {}).label || g
            : 'Transverse \u2014 non ventil\u00e9']);
      });

      vueStats.appendChild(U.card('Rapprochement ARR\u00caT\u00c9 le 01/09/2026 \u2014 centre par centre, contestable ligne \u00e0 ligne',
        K.miniTable(['Centre de co\u00fbts', 'Charges', 'Rattach\u00e9 au groupe'], rattachements)));

      vueStats.appendChild(U.card('B\u00e9n\u00e9fice brut par groupe \u2014 avant charges transverses',
        el('div.space-y-2', null, [
          K.miniTable(['Groupe', 'Recettes', 'Charges rattach\u00e9es', 'B\u00e9n\u00e9fice brut'],
            groupes.map(function (g) {
              var ch = chargesParGroupe[g.id] || 0;
              return [g.label, C.money(parGroupe[g.id], false), C.money(ch, false),
                C.money(parGroupe[g.id] - ch, false)];
            })),
          K.note('Les charges <strong>transverses</strong> (' + C.money(transverses, false) + ' \u2014 '
            + 'administration, entretien, ambulance, non imput\u00e9) ne sont PAS ventil\u00e9es : les '
            + 'r\u00e9partir exigerait une cl\u00e9 qu\u2019aucun document ne donne. Le b\u00e9n\u00e9fice brut se lit '
            + 'AVANT elles \u2014 la ligne globale de l\u2019en-t\u00eate les inclut.',
          { tone: 'info', icon: 'scale' }),
        ])));
      vueStats.appendChild(K.source('Lignes payables des factures et \u00e9critures valid\u00e9es du magasin.'));

      U.icons(vueStats);
      }
    },
  });

  /* ==========================================================================
   * STATISTIQUES DES HOSPITALISATIONS (PIL)
   * --------------------------------------------------------------------------
   * L'hospitalisation manquait au pilotage, alors que c'est le séjour qui pèse
   * le plus lourd au compte de résultat et le seul dont la DURÉE se pilote.
   *
   * Tout est CALCULÉ depuis le registre des admissions — rien n'est fourni.
   * Deux populations à ne jamais confondre : les séjours TERMINÉS, dont la
   * durée est connue, et les séjours EN COURS, dont la durée n'est pas encore
   * écrite. Les mêler abaisserait mécaniquement la durée moyenne, puisqu'un
   * séjour en cours est toujours plus court que ce qu'il sera.
   * ======================================================================== */
  global.SIGH.screen('m3-stats-hospitalisations', {
    title: 'Statistiques des hospitalisations',
    description: 'Séjours, durée moyenne, occupation des lits et motifs d’admission — calculés depuis le registre.',
    regle: 'La <strong>durée moyenne de séjour</strong> ne se calcule que sur les séjours '
      + '<strong>TERMINÉS</strong> : un séjour en cours est toujours plus court que ce qu’il sera, et '
      + 'l’inclure abaisserait la moyenne sans que rien ne le signale. Le <strong>taux '
      + 'd’occupation</strong> rapporte les lits occupés au parc réel des chambres — il se lit à une '
      + 'DATE, quand la durée se lit sur une PÉRIODE.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var barreDates = el('div.card');
      barreDates.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'au' }), dFin]),
        K.btn('Toute la période', { size: 'sm', icon: 'x',
          onclick: function () { dDebut.value = ''; dFin.value = ''; afficher(); } }),
      ]));
      host.appendChild(barreDates);
      [dDebut, dFin].forEach(function (x) { x.addEventListener('change', afficher); });
      function dansPlage(d) {
        var x = String(d || '').slice(0, 10);
        if (dDebut.value && x < dDebut.value) return false;
        if (dFin.value && x > dFin.value) return false;
        return true;
      }
      var vue = el('div.space-y-4');
      host.appendChild(vue);
      afficher();
      U.icons(host);
      return null;

      function afficher() {
        C.clear(vue);
        var toutes = S.collection('admissions').active()
          .filter(function (a) { return dansPlage(a.dateEntree); });
        var terminees = toutes.filter(function (a) { return a.dateSortie; });
        var enCours = toutes.filter(function (a) { return !a.dateSortie; });

        function duree(a) { return Math.max(1, C.daysBetween(a.dateEntree, a.dateSortie || AUJ)); }
        var journees = C.sum(terminees, duree);
        var dms = terminees.length ? Math.round(journees / terminees.length * 10) / 10 : 0;

        /* Le parc de lits vient du référentiel des chambres, jamais d'un
           nombre écrit à la main : ouvrir une chambre change le taux. */
        var lits = 0;
        (D.CHAMBRES || []).forEach(function (ch) { lits += (ch.lits || []).length; });
        var occupes = S.collection('admissions').active()
          .filter(function (a) { return !a.dateSortie; }).length;

        vue.appendChild(U.kpiGrid([
          { label: 'Séjours de la période', value: C.num(toutes.length), icon: 'bed-double', tone: 'navy' },
          { label: 'Séjours terminés', value: C.num(terminees.length), icon: 'check-circle-2', tone: 'success' },
          { label: 'Journées d’hospitalisation', value: C.num(journees), icon: 'calendar-days', tone: 'info',
            hint: 'Sur les séjours terminés seulement' },
          { label: 'Durée moyenne de séjour', value: dms + ' j', icon: 'timer', tone: 'warning',
            hint: 'Séjours terminés — les séjours en cours en sont exclus' },
          { label: 'Séjours en cours', value: C.num(enCours.length), icon: 'activity', tone: 'neutral' },
          { label: 'Taux d’occupation', value: lits ? C.pct(occupes / lits * 100) : '—',
            icon: 'layout-grid', tone: occupes / (lits || 1) > 0.8 ? 'danger' : 'success',
            hint: C.num(occupes) + ' lit(s) occupé(s) sur ' + C.num(lits) + ' — à ce jour' },
        ]));

        /* --- Par type de chambre --------------------------------------- */
        var parType = (D.TYPES_CHAMBRE || []).map(function (t) {
          var sel = toutes.filter(function (a) { return a.typeChambre === t.id; });
          var fin = sel.filter(function (a) { return a.dateSortie; });
          var j = C.sum(fin, duree);
          return {
            type: t.label, tarif: t.tarif, sejours: sel.length, journees: j,
            dms: fin.length ? Math.round(j / fin.length * 10) / 10 : 0,
            produit: j * t.tarif,
          };
        });
        vue.appendChild(U.card('Par type de chambre',
          K.miniTable([
            { label: 'Type', key: 'type' },
            { label: 'Prix de journée', align: 'right', render: function (r) { return C.money(r.tarif, false); } },
            { label: 'Séjours', key: 'sejours', align: 'right' },
            { label: 'Journées', key: 'journees', align: 'right' },
            { label: 'Durée moyenne', align: 'right', render: function (r) { return r.dms + ' j'; } },
            { label: 'Produit théorique', align: 'right', render: function (r) { return C.money(r.produit, false); } },
          ], parType)));

        /* --- Motifs et diagnostics -------------------------------------- */
        var parDiag = C.groupBy(toutes, function (a) { return a.diagnosticEntree || 'Non renseigné'; });
        var rangs = Object.keys(parDiag).map(function (k) {
          var fin = parDiag[k].filter(function (a) { return a.dateSortie; });
          return { motif: k, nb: parDiag[k].length,
            dms: fin.length ? Math.round(C.sum(fin, duree) / fin.length * 10) / 10 : 0 };
        }).sort(function (a, b) { return b.nb - a.nb; });

        vue.appendChild(K.grid(2, [
          U.card('Diagnostics d’entrée les plus fréquents',
            rangs.length
              ? G.barres(rangs.slice(0, 8).map(function (r) { return r.motif; }),
                [{ label: 'Séjours', data: rangs.slice(0, 8).map(function (r) { return r.nb; }) }],
                { horizontal: true, height: 240 })
              : U.empty('Aucun séjour sur la période.', { icon: 'bed-double' })),
          (function () {
            var m = K.parMois(toutes, 'dateEntree', null, 8);
            return U.card('Séjours par mois',
              G.ligne(m.labels, [{ label: 'Séjours', data: m.data }], { height: 240 }));
          })(),
        ]));

        vue.appendChild(U.card('Durée moyenne par diagnostic — sur les séjours terminés',
          K.miniTable([
            { label: 'Diagnostic d’entrée', key: 'motif' },
            { label: 'Séjours', key: 'nb', align: 'right' },
            { label: 'Durée moyenne', align: 'right', render: function (r) { return r.dms ? r.dms + ' j' : '—'; } },
          ], rangs.slice(0, 12))));

        vue.appendChild(el('div.flex.flex-wrap.gap-2', null, [
          K.btn('Éditer l’état', { icon: 'printer', variant: 'primary', onclick: function () { etat(); } }),
        ]));
        vue.appendChild(K.source('Registre des admissions et référentiel des chambres — recalculé à chaque affichage.'));
        U.icons(vue);

        function etat() {
          P.etat({
            titre: 'Statistiques des hospitalisations',
            sousTitre: C.libellePeriode
              ? 'Période : ' + (dDebut.value ? C.dateFR(dDebut.value) : 'origine')
                + ' au ' + (dFin.value ? C.dateFR(dFin.value) : C.dateFR(AUJ))
              : null,
            cartouche: [
              ['Période', (dDebut.value ? C.dateFR(dDebut.value) : 'Toute la période')
                + (dFin.value ? ' au ' + C.dateFR(dFin.value) : '')],
              ['Séjours', C.num(toutes.length)],
              ['Séjours terminés', C.num(terminees.length)],
              ['Séjours en cours', C.num(enCours.length)],
              ['Journées d’hospitalisation', C.num(journees)],
              ['Durée moyenne de séjour', dms + ' jours'],
              ['Lits occupés', C.num(occupes) + ' / ' + C.num(lits)],
            ],
            contenu: el('div.space-y-3', null, [
              P.tableau([
                { label: 'Type de chambre', key: 'type' },
                { label: 'Prix de journée', align: 'right', value: function (r) { return C.money(r.tarif, false); } },
                { label: 'Séjours', align: 'right', value: function (r) { return C.num(r.sejours); },
                  somme: function (r) { return r.sejours; },
                  formatTotal: function (v) { return C.num(v); } },
                { label: 'Journées', align: 'right', value: function (r) { return C.num(r.journees); },
                  somme: function (r) { return r.journees; },
                  formatTotal: function (v) { return C.num(v); } },
                { label: 'Durée moyenne', align: 'right', value: function (r) { return r.dms + ' j'; } },
                { label: 'Produit théorique', align: 'right', value: function (r) { return C.money(r.produit, false); },
                  somme: function (r) { return r.produit; } },
              ], parType, { total: true }),
              el('p.mt-3.text-\\[10px\\].italic', {
                text: 'La durée moyenne ne porte que sur les séjours TERMINÉS : un séjour en cours est '
                  + 'toujours plus court que ce qu’il sera. Le produit théorique applique le prix de '
                  + 'journée aux journées constatées — il ne remplace pas la facturation réelle.',
              }),
            ]),
            signatures: [{ role: 'Le Directeur Médical' },
              { role: 'La Directrice de l’Administration et des Finances' }],
          });
        }
      }
    },
  });


  /* ==========================================================================
   * MATERNITÉ — le poste, pas la spécialité
   * --------------------------------------------------------------------------
   * La sage-femme de garde arrive avec trois questions, toujours les mêmes :
   * QUI est en travail en ce moment, QUELS termes tombent cette semaine, et
   * QUELLES grossesses sont à risque. Le tableau du médecin ne répond à aucune
   * des trois — il montre des résultats d'analyse et des consultations. Sans
   * tableau propre, la maternité retombait sur celui de l'infirmier, et
   * c'est la leçon de la vague 31 : un rôle sans tableau à lui en lit un qui
   * ne le concerne pas.
   *
   * TOUT EST CALCULÉ depuis les registres — dossiers, partogrammes,
   * accouchements, naissances, CPoN. Rien n'est fourni.
   * ======================================================================== */
  function dossiersObst() { return col('dossiersObstetricaux').active(); }
  function partogrammes() { return col('partogrammes').active(); }
  function accouchements() { return col('accouchements').active(); }
  function naissances() { return col('naissances').active(); }

  /** Les facteurs cochés d'un dossier — la carte, jamais douze noms de champ. */
  function facteursDossier(d) {
    return (D.FACTEURS_SURVEILLANCE || []).filter(function (f) {
      return (d.facteurs || {})[f.code];
    });
  }
  function travauxEnCours() {
    return partogrammes().filter(function (p) { return !p.clos; });
  }
  /** Les termes qui tombent dans la fenêtre demandée, dépassés compris. */
  function termesProches(jours) {
    return dossiersObst().filter(function (d) {
      if (!d.dpa || d.statutDossier !== 'suivi') return false;
      var r = C.daysBetween(AUJ, d.dpa);
      return r <= jours;
    }).sort(function (a, b) { return C.daysBetween(AUJ, a.dpa) - C.daysBetween(AUJ, b.dpa); });
  }

  global.SIGH.screen('dash-maternite', {
    title: 'Tableau de bord — Maternité',
    description: 'Travail en cours, termes de la semaine, grossesses à risque, accouchements et nouveau-nés du mois.',
    render: K.dash({
      /* Fondement : le travail en cours est la SEULE chose qui ne peut pas
       * attendre. Un partogramme ouvert, c'est une femme dans la salle. */
      premierRegard: function () {
        var t = travauxEnCours();
        return {
          valeur: t.length, unite: 'partogramme(s)',
          question: 'ouverts — travail en cours',
          vide: 'Aucun travail en cours dans la salle d’accouchement.',
          ton: 'danger', icone: 'activity',
          ecran: 'm4-partogramme', lienLabel: 'Partogrammes',
          note: 'Un partogramme non clos est une femme en salle de travail. La ligne d’alerte part '
            + 'de 4 cm à 1 cm par heure ; la ligne d’action lui est parallèle, décalée de 4 heures.',
        };
      },
      kpis: function () {
        var dos = dossiersObst();
        var gar = dos.filter(function (d) { return facteursDossier(d).length > 0; });
        var accMois = duMois(accouchements(), 'dateHeure');
        var naisMois = duMois(naissances(), 'dateHeure');
        return [
          { label: 'Dossiers suivis', value: C.num(dos.filter(function (d) { return d.statutDossier === 'suivi'; }).length),
            icon: 'folder-open', tone: 'navy', hint: 'Dossiers obstétricaux ouverts, non encore clos' },
          { label: 'Grossesses à risque (GAR)', value: C.num(gar.length),
            icon: 'alert-triangle', tone: gar.length ? 'danger' : 'success',
            hint: 'Au moins un facteur de surveillance coché' },
          { label: 'Accouchements du mois', value: C.num(accMois.length), icon: 'baby', tone: 'info' },
          { label: 'Nouveau-nés vivants du mois',
            value: C.num(naisMois.filter(function (n) { return n.vivant; }).length),
            icon: 'heart-pulse', tone: 'success',
            hint: naisMois.length ? C.num(naisMois.filter(function (n) { return !n.vivant; }).length)
              + ' mort-né(s) sur ' + C.num(naisMois.length) : 'Aucune naissance ce mois' },
        ];
      },
      sections: [
        {
          title: 'Ce que vous faites ici — vos parcours',
          rapide: true,
          render: function () {
            return K.parcours([
              {
                titre: 'Ouvrir un dossier obstétrical', icone: 'folder-open', action: 'Dossier obstétrical',
                detail: 'Une femme se présente pour sa première consultation prénatale.',
                etapes: [
                  { label: 'Vérifier ou créer le dossier patient', ecran: 'm1-patients' },
                  { label: 'Ouvrir le dossier obstétrical', ecran: 'm4-dossier-obstetrical',
                    detail: 'Numéro repris du registre papier ; la date probable se déduit de la DDR.' },
                  { label: 'Cocher les facteurs de surveillance', ecran: 'm4-dossier-obstetrical',
                    detail: 'C’est leur CUMUL qui classe à risque, jamais un facteur isolé.' },
                  { label: 'Enregistrer la première CPN', ecran: 'm4-cpn' },
                ],
              },
              {
                titre: 'Suivre une CPN', icone: 'clipboard-list', action: 'CPN & carte maternelle',
                detail: 'La grille se remplit en COLONNES : une par venue, les mêmes lignes à chaque fois.',
                etapes: [
                  { label: 'Relever l’état général et les examens', ecran: 'm4-cpn' },
                  { label: 'Administrer le TPI / SP et le déparasitage', ecran: 'm4-cpn' },
                  { label: 'Prescrire un bilan si nécessaire', ecran: 'm5-demandes', poste: 'Laboratoire' },
                  { label: 'Fixer le rendez-vous et la classe des mères', ecran: 'm4-cpn' },
                ],
              },
              {
                titre: 'Conduire un accouchement', icone: 'activity', action: 'Partogramme',
                detail: 'De l’admission en salle de travail à la surveillance du deuxième jour.',
                etapes: [
                  { label: 'Ouvrir le partogramme', ecran: 'm4-partogramme',
                    detail: 'Dilatation, descente en travers de doigts, chevauchement, liquide amniotique.' },
                  { label: 'Enregistrer l’accouchement et la délivrance', ecran: 'm4-accouchements',
                    detail: 'Mode de délivrance, examen du placenta, issue mère et nouveau-né.' },
                  { label: 'Renseigner le nouveau-né', ecran: 'm4-dossier-bebe',
                    detail: 'PC, PT et Apgar aux trois temps sont OBLIGATOIRES.' },
                  { label: 'Déclarer la naissance', ecran: 'm4-naissances' },
                  { label: 'Établir la facture du séjour', poste: 'Caisse' },
                ],
              },
              {
                titre: 'Suivre les suites de couches', icone: 'stethoscope', action: 'CPoN',
                detail: 'Trois consultations post-natales, la première dans les 48 heures.',
                etapes: [
                  { label: 'Enregistrer la CPoN', ecran: 'm4-cpon' },
                  { label: 'Proposer une méthode de PF', ecran: 'm4-planification' },
                  { label: 'Clore le dossier obstétrical', ecran: 'm4-dossier-obstetrical' },
                ],
              },
            ]);
          },
        },
        {
          title: 'Travail en cours — salle d’accouchement',
          actions: function () { return [K.lien('m4-partogramme', 'Partogrammes', { size: 'sm', icon: 'activity' })]; },
          render: function () {
            var t = travauxEnCours();
            if (!t.length) return U.empty('Aucun travail en cours.', { icon: 'activity' });
            return K.miniTable([
              { label: 'Parturiente', key: 'patient' },
              { label: 'Dossier', render: function (p) { return el('span.font-mono.text-xs', { text: p.patientCode }); } },
              { label: 'G / P', render: function (p) { return 'G' + (p.gestite || 0) + ' P' + (p.parite || 0); } },
              { label: 'Début du travail', render: function (p) { return C.dateFR(p.debut) + ' à ' + C.heure(p.debut); } },
              { label: 'Dilatation', align: 'right', render: function (p) {
                var m = (p.mesures || [])[(p.mesures || []).length - 1] || {};
                return el('span.font-semibold', { text: (m.dilatation || 0) + ' cm' });
              } },
              { label: 'Descente', render: function (p) {
                var m = (p.mesures || [])[(p.mesures || []).length - 1] || {};
                return m.descenteCotee || '—';
              } },
              { label: 'Accoucheur', key: 'accoucheur' },
            ], t);
          },
        },
        {
          title: 'Termes attendus — les quinze prochains jours',
          actions: function () { return [K.lien('m4-dossier-obstetrical', 'Dossiers', { size: 'sm', icon: 'folder-open' })]; },
          render: function () {
            var t = termesProches(15);
            if (!t.length) return U.empty('Aucun terme dans les quinze prochains jours.', { icon: 'calendar-clock' });
            return el('div.space-y-3', null, [
              K.note('Un terme DÉPASSÉ n’est pas une erreur de saisie : c’est la femme qu’il faut '
                + 'rappeler. Le dossier reste « suivi » tant que l’accouchement n’est pas enregistré.',
              { tone: 'warning', icon: 'phone' }),
              K.miniTable([
                { label: 'N° dossier', render: function (d) { return el('span.font-mono.text-xs', { text: d.numeroDossier }); } },
                { label: 'Parturiente', key: 'patient' },
                { label: 'Terme prévu', render: function (d) { return C.dateFR(d.dpa); } },
                { label: 'Échéance', align: 'right', render: function (d) {
                  var r = C.daysBetween(AUJ, d.dpa);
                  return r < 0 ? U.badge('dépassé de ' + (-r) + ' j', 'danger')
                    : U.badge('dans ' + r + ' j', r <= 7 ? 'warning' : 'info');
                } },
                { label: 'Surveillance', render: function (d) {
                  var f = facteursDossier(d);
                  return f.length ? U.badge('GAR — ' + f.length, 'danger') : U.badge('Sans facteur', 'success');
                } },
                { label: 'Sage-femme', key: 'sageFemme' },
                { label: 'Téléphone', key: 'telephone' },
              ], t.slice(0, 12)),
            ]);
          },
        },
        {
          title: 'Grossesses à risque suivies',
          render: function () {
            var gar = dossiersObst().filter(function (d) {
              return d.statutDossier === 'suivi' && facteursDossier(d).length > 0;
            });
            if (!gar.length) return U.empty('Aucune grossesse à risque en cours de suivi.', { icon: 'shield-check' });
            return K.miniTable([
              { label: 'N° dossier', render: function (d) { return el('span.font-mono.text-xs', { text: d.numeroDossier }); } },
              { label: 'Parturiente', key: 'patient' },
              { label: 'Âge', align: 'right', render: function (d) { return (d.age || '—') + ' ans'; } },
              { label: 'G / P', render: function (d) { return 'G' + (d.gestite || 0) + ' P' + (d.parite || 0); } },
              { label: 'Facteurs relevés', render: function (d) {
                return facteursDossier(d).map(function (f) { return f.libelle; }).join(' · ');
              } },
            ], gar.slice(0, 10));
          },
        },
        {
          title: 'Lecture du mois',
          render: function () {
            var accMois = duMois(accouchements(), 'dateHeure');
            var parType = C.groupBy(accMois, 'type');
            var typesK = Object.keys(parType);
            var gar = dossiersObst().filter(function (d) { return facteursDossier(d).length > 0; });
            var compte = {};
            gar.forEach(function (d) {
              facteursDossier(d).forEach(function (f) { compte[f.libelle] = (compte[f.libelle] || 0) + 1; });
            });
            return K.charts([
              {
                title: 'Accouchements du mois par type',
                render: function () {
                  if (!typesK.length) return U.empty('Aucun accouchement ce mois.', { icon: 'baby' });
                  return G.barres(typesK, [{ label: 'Accouchements',
                    data: typesK.map(function (k) { return parType[k].length; }) }], { horizontal: true, height: 260 });
                },
              },
              {
                title: 'Facteurs de surveillance les plus fréquents',
                render: function () {
                  var items = Object.keys(compte).map(function (k) { return { label: k, value: compte[k] }; })
                    .sort(function (a, b) { return b.value - a.value; }).slice(0, 8);
                  if (!items.length) return U.empty('Aucun facteur coché sur les dossiers ouverts.', { icon: 'check-circle-2' });
                  return K.ranking(items);
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm4-dossier-obstetrical', icon: 'folder-open', label: 'Dossier obstétrical', detail: 'Le cahier de la parturiente' },
              { id: 'm4-partogramme', icon: 'activity', label: 'Partogramme', detail: 'Salle de travail' },
              { id: 'm4-accouchements', icon: 'baby', label: 'Accouchement', detail: 'Délivrance et issue' },
              { id: 'm4-cpon', icon: 'stethoscope', label: 'CPoN', detail: 'Suites de couches' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * TABLEAU DE BORD DÉCISIONNEL (BFR_TABLEAU.txt §2.B)
   * --------------------------------------------------------------------------
   * « Une grille comparative dynamique (Objectif fixé vs Réel atteint avec
   * code couleur d'alerte) », sur quatre axes : trésorerie & BFR, activité
   * clinique, logistique & pharmacie, performance administrative.
   *
   * DEUX PRÉCAUTIONS QUI COMMANDENT TOUT L'ÉCRAN :
   *
   *   1. AUCUN OBJECTIF N'EST DOCUMENTÉ. Ni le cahier des charges, ni le
   *      rapport de cadrage, ni la liasse déposée ne fixent de cible de DSO
   *      ou de taux d'occupation. Les cibles affichées sont donc des
   *      PROPOSITIONS, marquées comme telles et corrigeables ici même — un
   *      objectif chiffré finit dans une évaluation, et faire juger un poste
   *      sur un nombre que personne n'a arrêté serait une faute.
   *
   *   2. « NON CALCULABLE » N'EST PAS « ZÉRO ». Un indicateur dont la donnée
   *      manque le dit, et ne se colore pas en rouge : la Direction lirait un
   *      échec là où il n'y a qu'un registre non amorcé.
   * ======================================================================== */
  global.SIGH.screen('m12-tableau-decisionnel', {
    title: 'Tableau de bord décisionnel',
    description: 'Objectif fixé face au réel atteint, sur quatre axes : trésorerie et BFR, activité clinique, logistique et pharmacie, performance administrative.',
    regle: 'Les <strong>cibles ne sont pas documentées</strong> : aucun document de cadrage n’en fixe. '
      + 'Elles sont <strong>proposées</strong>, marquées à valider et corrigeables à l’onglet '
      + '« Objectifs & seuils ». Un indicateur dont la donnée manque affiche '
      + '<strong>« non calculable »</strong> — jamais un zéro, qui se lirait comme un échec.',
    actions: function () {
      return [
        K.btn('Détail du BFR', { icon: 'scale', onclick: function () { global.SIGH.app.go('m12-bfr'); } }),
        K.btn('Coût à l’activité', { icon: 'calculator', onclick: function () { global.SIGH.app.go('m12-cout-activite'); } }),
      ];
    },
    render: function (root) {
      root.appendChild(U.tabs([
        { id: 'grille', label: 'Grille objectif / réel', render: ongletGrille },
        { id: 'objectifs', label: 'Objectifs & seuils', render: ongletObjectifs },
      ]));
      return null;

      function ongletGrille(panneau) {
        var vue = el('div.space-y-4');
        panneau.appendChild(vue);
        peindre();
        return null;

        function peindre() {
          C.clear(vue);
          var ind = PR.indicateursPilotage();
          var b = PR.bfr();

          var aValider = ind.filter(function (x) { return x.aValider; }).length;
          if (aValider) {
            vue.appendChild(K.note('<strong>' + aValider + ' cible(s) en attente d’arbitrage de la '
              + 'Direction.</strong> Aucun document de cadrage ne fixe d’objectif de DSO, de taux '
              + 'd’occupation ou de rotation : les valeurs affichées sont des propositions. '
              + 'L’onglet « Objectifs & seuils » les corrige.', { tone: 'warning', icon: 'triangle-alert' }));
          }

          var compte = { atteint: 0, vigilance: 0, alerte: 0, indisponible: 0 };
          ind.forEach(function (x) { compte[x.etat] += 1; });
          vue.appendChild(U.kpiGrid([
            { label: 'Objectifs atteints', value: C.num(compte.atteint), icon: 'check-circle-2', tone: 'success' },
            { label: 'Sous surveillance', value: C.num(compte.vigilance), icon: 'eye', tone: 'warning' },
            { label: 'Seuils franchis', value: C.num(compte.alerte), icon: 'siren', tone: 'danger' },
            { label: 'Non calculables', value: C.num(compte.indisponible), icon: 'circle-help', tone: 'neutral',
              hint: compte.indisponible ? 'donnée manquante, jamais un zéro' : '' },
          ]));

          vue.appendChild(K.note('Besoin en fonds de roulement au ' + C.dateFR(b.arrete) + ' : '
            + '<strong>' + C.money(b.bfr) + '</strong>'
            + (b.bfrJours != null ? ', soit ' + C.num(b.bfrJours) + ' jours de chiffre d’affaires' : '')
            + '.', { tone: 'info', icon: 'scale' }));

          /* UNE CARTE PAR AXE — la grille du document. Ranger les quatre axes
             dans un seul tableau les mêlerait, alors que ce sont quatre
             postes différents qui les lisent. */
          (D.AXES_PILOTAGE || []).forEach(function (axe) {
            var lignes = ind.filter(function (x) { return x.axe === axe.id; });
            if (!lignes.length) return;
            vue.appendChild(U.card(axe.label, K.miniTable([
              { label: 'Indicateur', render: function (x) {
                return el('div', null, [
                  el('p.text-sm.text-slate-700', { text: x.label }),
                  x.aide ? el('p.text-xs.text-slate-400', { text: x.aide }) : null,
                ].filter(Boolean));
              } },
              { label: 'Objectif', align: 'right', render: function (x) {
                var t = x.unite === '%' ? C.pct(x.cible) : C.num(x.cible) + ' ' + x.unite;
                return el('span', null, [
                  el('span.text-slate-600', { text: t }),
                  x.aValider ? el('span.ml-1\.5.text-\[10px\].uppercase.text-warning-600', { text: 'à valider' }) : null,
                ].filter(Boolean));
              } },
              { label: 'Réel atteint', align: 'right', render: function (x) {
                return el('span.font-semibold', {
                  class: x.reel == null ? 'text-slate-400' : '',
                  text: valeurIndicateur(x),
                });
              } },
              { label: 'Écart', align: 'right', render: function (x) {
                if (x.ecart == null) return '—';
                return el('span', {
                  class: x.ecart >= 0 ? 'text-success-600' : 'text-danger-600',
                  text: (x.ecart > 0 ? '+' : '') + C.num(x.ecart, 1),
                });
              } },
              { label: 'État', render: function (x) {
                return U.badge(libelleEtat(x.etat), tonIndicateur(x.etat));
              } },
            ], lignes)));
          });

          var alertes = PR.alertesRecouvrement();
          if (alertes.length) {
            vue.appendChild(U.dataTable({
              title: 'Compagnies au-delà du seuil d’ancienneté', rows: alertes,
              exportName: 'alertes-recouvrement', pageSize: 8, searchable: true,
              defaultSort: 'montant', defaultDir: 'desc',
              columns: [
                { key: 'assureur', label: 'Compagnie', render: function (r) {
                  var a = (D.ASSUREURS || []).filter(function (x) { return x.code === r.assureur; })[0];
                  return a ? a.nom : r.assureur;
                } },
                { key: 'nb', label: 'Factures', align: 'right' },
                { key: 'jours', label: 'Ancienneté max.', align: 'right',
                  text: function (r) { return r.jours + ' j'; },
                  render: function (r) { return el('span.font-semibold.text-danger-600', { text: r.jours + ' j' }); } },
                { key: 'montant', label: 'Montant dû', align: 'right',
                  text: function (r) { return C.money(r.montant, false); },
                  render: function (r) { return C.money(r.montant, false); } },
              ],
              actions: [K.btn('Ouvrir les relances', { size: 'sm', icon: 'send',
                onclick: function () { global.SIGH.app.go('m9-relances'); } })],
            }));
          }

          vue.appendChild(el('div.flex.flex-wrap.gap-2', null, [
            K.btn('Imprimer la grille', { variant: 'primary', icon: 'printer', onclick: function () { imprimer(ind, b); } }),
          ]));
          U.icons(vue);
        }
      }

      function imprimer(ind, b) {
        P.etat({
          titre: 'Tableau de bord décisionnel',
          sousTitre: 'Objectif fixé / réel atteint — arrêté au ' + C.dateFR(b.arrete),
          cartouche: [['Besoin en fonds de roulement', C.money(b.bfr)],
            ['En-cours clients', C.money(b.creances)],
            ['Stocks', C.money(b.stocks)],
            ['Dettes fournisseurs', C.money(b.dettes)],
            ['Objectifs en alerte', C.num(ind.filter(function (x) { return x.etat === 'alerte'; }).length)],
            ['Cibles non arbitrées', C.num(ind.filter(function (x) { return x.aValider; }).length)]],
          contenu: P.tableau([
            { label: 'Axe', value: function (x) {
              var a = (D.AXES_PILOTAGE || []).filter(function (y) { return y.id === x.axe; })[0];
              return a ? a.label : x.axe;
            } },
            { label: 'Indicateur', key: 'label' },
            { label: 'Objectif', align: 'right', value: function (x) {
              return (x.unite === '%' ? C.pct(x.cible) : C.num(x.cible) + ' ' + x.unite)
                + (x.aValider ? ' (à valider)' : '');
            } },
            { label: 'Réel atteint', align: 'right', value: function (x) { return valeurIndicateur(x); } },
            { label: 'État', value: function (x) { return libelleEtat(x.etat); } },
          ], ind),
          signatures: [{ role: 'La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou' },
            { role: 'La Direction' }],
        });
      }

      /* ----------------------------------------------------------------------
       * LES OBJECTIFS SE CORRIGENT ICI, ET NULLE PART AILLEURS.
       * Ils vivent au magasin (collection `objectifsPilotage`, semée au socle) :
       * les écrire dans le code aurait obligé la Direction à demander une
       * livraison pour changer un seuil de relance.
       * -------------------------------------------------------------------- */
      function ongletObjectifs(panneau) {
        var col = S.collection('objectifsPilotage', { module: 'M12', entite: 'ObjectifPilotage' });
        var vue = el('div.space-y-4');
        panneau.appendChild(vue);
        peindre();
        return null;

        function peindre() {
          C.clear(vue);
          vue.appendChild(K.note('Une cible corrigée ici est <strong>arrêtée par la Direction</strong> : '
            + 'la mention « à valider » tombe d’elle-même. Le <strong>sens</strong> dit de quel côté se '
            + 'trouve la réussite — un DSO se veut bas, un taux d’occupation haut ; sans lui, la grille '
            + 'colorerait en rouge un indicateur excellent.', { tone: 'info', icon: 'target' }));

          vue.appendChild(U.dataTable({
            title: 'Objectifs et seuils d’alerte', rows: col.active(),
            exportName: 'objectifs-pilotage', pageSize: 12, searchable: true,
            columns: [
              { key: 'axe', label: 'Axe', render: function (r) {
                var a = (D.AXES_PILOTAGE || []).filter(function (x) { return x.id === r.axe; })[0];
                return a ? a.label : r.axe;
              } },
              { key: 'label', label: 'Indicateur' },
              { key: 'cible', label: 'Objectif', align: 'right',
                render: function (r) { return C.num(r.cible) + ' ' + r.unite; } },
              { key: 'alerte', label: 'Seuil d’alerte', align: 'right',
                render: function (r) { return el('span.text-danger-600', { text: C.num(r.alerte) + ' ' + r.unite }); } },
              { key: 'sens', label: 'Réussite', render: function (r) {
                return U.badge(r.sens === 'haut' ? 'Le plus haut possible' : 'Le plus bas possible',
                  r.sens === 'haut' ? 'info' : 'navy');
              } },
              { key: 'aValider', label: 'Statut', render: function (r) {
                return r.aValider ? U.badge('Proposition', 'warning') : U.badge('Arrêté par la Direction', 'success');
              } },
            ],
            rowActions: K.actionsLigne(col, [
              { name: 'label', label: 'Indicateur', required: true, col: 'full' },
              { name: 'cible', label: 'Objectif', type: 'number', required: true },
              { name: 'alerte', label: 'Seuil d’alerte', type: 'number', required: true },
              { name: 'unite', label: 'Unité', type: 'select', required: true,
                options: [{ value: 'jours', label: 'jours' }, { value: '%', label: '%' }, { value: 'tours', label: 'tours' }] },
              { name: 'sens', label: 'La réussite est…', type: 'select', required: true,
                options: [{ value: 'bas', label: 'la valeur la plus BASSE' }, { value: 'haut', label: 'la valeur la plus HAUTE' }] },
              { name: 'aide', label: 'Ce que mesure l’indicateur', col: 'full' },
            ], {
              /* Corriger une cible, c'est l'ARRÊTER : la Direction vient de
                 la décider, la marque de proposition n'a plus lieu d'être. */
              transform: function (v) {
                return Object.assign({}, v, {
                  aValider: false,
                  arreteLe: C.iso(new Date()),
                  arretePar: S.currentUser(),
                });
              },
              /* `refresh` et non `apres` : c'est la clé que lit
                 `actionsLigne` — la grille se repeint, seuils compris. */
              refresh: peindre,
            }),
            onRowClick: function (r) {
              U.drawer({
                title: r.label, subtitle: 'Objectif de pilotage',
                body: el('div.space-y-3', null, [
                  U.descList([['Axe', r.axe], ['Objectif', C.num(r.cible) + ' ' + r.unite],
                    ['Seuil d’alerte', C.num(r.alerte) + ' ' + r.unite],
                    ['Réussite', r.sens === 'haut' ? 'valeur la plus haute' : 'valeur la plus basse'],
                    ['Statut', r.aValider ? 'Proposition — non arbitrée' : 'Arrêté le ' + C.dateFR(r.arreteLe || '')]]),
                  r.source ? K.note('<strong>Origine de la valeur proposée</strong> : ' + r.source,
                    { tone: r.aValider ? 'warning' : 'neutral', icon: 'file-search' }) : null,
                ].filter(Boolean)),
              });
            },
          }));
          U.icons(vue);
        }
      }
    },
  });

})(window);