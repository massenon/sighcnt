/* =============================================================================
 * M11 — Paie & Primes
 * -----------------------------------------------------------------------------
 * CDCT §10.10 — calcul des salaires et des primes, heures supplémentaires,
 * retenues et cotisations (CNSS, VPS, ITS, redevance ORTB), part patronale
 * (16,4 %) et part ouvrière (3,6 %), génération du bulletin de paie, avances
 * sur salaire et rémunération distincte des prestataires externes.
 *
 * La chaîne appliquée est : planning validé → primes NS 132 → évaluation
 * NS 131 (prélèvement) → cotisations → bulletin → écriture comptable.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */
  var PP = D.PARAM_PAIE;

  function personnel() { return S.collection('personnel').active(); }
  function planning() { return S.collection('planning').active(); }
  function evaluations() { return S.collection('evaluations').active(); }
  function bulletins() { return S.collection('bulletins', { module: 'M11', entite: 'BulletinPaie' }); }
  function avances() { return S.collection('avances', { module: 'M11', entite: 'AvanceSalaire' }); }

  function fonctionLabel(id) {
    var f = D.FONCTIONS.filter(function (x) { return x.id === id; })[0];
    return f ? f.label : id;
  }
  function compter(employeId, annee, mois, type) {
    return planning().filter(function (p) {
      if (p.employeId !== employeId || p.type !== type) return false;
      var d = C.toDate(p.date);
      return d.getFullYear() === annee && d.getMonth() === mois;
    }).length;
  }
  function anciennete(e) {
    return Math.floor(C.daysBetween(e.dateEmbauche, AUJ) / 365.25);
  }

  /** Barème ITS progressif par tranches. */
  function calculITS(base) {
    var reste = base, impot = 0;
    PP.its.bareme.forEach(function (t) {
      var plafond = t.a == null ? Infinity : t.a;
      var tranche = Math.max(0, Math.min(base, plafond) - t.de + (t.de === 0 ? 0 : 1));
      if (tranche > 0) impot += tranche * t.taux / 100;
    });
    return Math.round(impot);
  }

  /* ==========================================================================
   * MOTEUR DE CALCUL DE LA PAIE
   * -------------------------------------------------------------------------
   * Un seul point d'entrée : toutes les vues consomment ce calcul, ce qui
   * garantit la cohérence entre le tableau de bord, le bulletin et les états.
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * Redevance ORTB — règle précisée par la Direction le 20/08/2026
   * --------------------------------------------------------------------------
   * DEUX REDEVANCES QUI SE CUMULENT, et non deux tranches exclusives :
   *   ORTB Radio : 1 000 F, TOUS les salariés sans exception, en mars ;
   *   ORTB Télé  : 3 000 F, salaire brut > 60 000 F, en juin, EN SUS.
   * Un agent au-dessus du seuil supporte donc 4 000 F sur l'exercice.
   * Filtrer pour n'en retenir qu'une seule — l'erreur du modèle précédent —
   * dispenserait de la radio les salaires élevés.
   * Le prélèvement est ANNUEL : chacune n'apparaît que sur le bulletin de
   * son mois de prélèvement.
   * ----------------------------------------------------------------------- */
  function calculOrtb(brut, mois) {
    var lignes = (PP.ortb.redevances || []).filter(function (r) {
      return (r.seuilMin == null || brut >= r.seuilMin)
        && (r.seuilMax == null || brut <= r.seuilMax);
    }).map(function (r) {
      var du = mois === r.mois;
      return {
        id: r.id, code: r.code, categorie: r.categorie, libelle: r.libelle,
        assiette: r.assiette, moisLabel: r.moisLabel, mois: r.mois,
        montantAnnuel: r.montant,
        montant: du ? r.montant : 0,
        du: du,
      };
    });
    var parCategorie = {};
    lignes.forEach(function (l) { parCategorie[l.id] = l; });
    return {
      lignes: lignes,
      parCategorie: parCategorie,
      montant: C.sum(lignes, 'montant'),
      montantAnnuel: C.sum(lignes, 'montantAnnuel'),
      du: C.sum(lignes, 'montant') > 0,
      resume: lignes.map(function (l) {
        return l.categorie + ' ' + C.money(l.montantAnnuel, false) + ' en ' + l.moisLabel;
      }).join(' · '),
    };
  }

  /* Les lignes de retenue ORTB d'un bulletin, une par catégorie applicable.
     Une catégorie non prélevée ce mois-ci reste affichée à zéro : le bulletin
     doit dire de quoi l'agent est redevable, pas seulement ce qu'il paie en
     ce mois. */
  function lignesOrtb(c) {
    var d = c.detailOrtb;
    if (!d || !d.lignes || !d.lignes.length) {
      return [{ libelle: 'Redevance ORTB', base: 'Non applicable', montant: C.money(0, false) }];
    }
    return d.lignes.map(function (l) {
      return {
        libelle: l.libelle,
        base: l.du ? 'Annuelle, prélevée ce mois' : 'Annuelle, prélevée en ' + l.moisLabel,
        montant: l.du ? C.money(l.montant, false) : String.fromCharCode(8212),
      };
    });
  }

  function calculer(employe, annee, mois) {
    var gardes = compter(employe.id, annee, mois, 'garde');
    var permanences = compter(employe.id, annee, mois, 'permanence');

    /* Primes NS 132 — la grille est lue À LA DATE du bulletin, et non à la
       date du jour : une prime relevée en août ne doit pas gonfler le bulletin
       de juillet. Les versions antérieures sont conservées à l'écran des
       primes, et c'est là que ce calcul va les rechercher. */
    var dateBulletin = C.iso(new Date(annee, mois, 28));
    var lignesPrimes = [];
    D.NS132.primes.forEach(function (pr) {
      var montant = D.NS132.montant(pr.id, employe.fonction, dateBulletin);
      if (!montant) return;
      var nb = pr.mode === 'fixe' ? 1 : (pr.id === 'garde' ? gardes : (pr.id === 'permanence' ? permanences : 0));
      if (!nb) return;
      lignesPrimes.push({ id: pr.id, label: pr.label, unitaire: montant, nombre: nb, total: montant * nb });
    });
    var totalPrimes = C.sum(lignesPrimes, 'total');

    /* Prime d'ancienneté : 2 % du salaire de base par année, à partir de 2 ans */
    var ans = anciennete(employe);
    var primeAnciennete = ans >= 2 ? Math.round(employe.salaireBase * 0.02 * ans) : 0;

    var salaireBase = employe.salaireBase;
    var brut = salaireBase + primeAnciennete + totalPrimes;

    /* Sanction NS 131 issue de l'évaluation de la période */
    var periode = C.MOIS[mois].charAt(0).toUpperCase() + C.MOIS[mois].slice(1) + ' ' + annee;
    var evaluation = evaluations().filter(function (e) {
      return e.employeId === employe.id && e.periode === periode;
    })[0];
    var pctSanction = evaluation ? (evaluation.prelevementPct || 0) : 0;
    var sanction = Math.round(brut * pctSanction / 100);
    var brutApresSanction = brut - sanction;

    /* Cotisations sociales et fiscales */
    var cnssOuvriere = Math.round(brutApresSanction * PP.cnss.ouvriere / 100);
    var cnssPatronale = Math.round(brutApresSanction * PP.cnss.patronale / 100);
    var vps = Math.round(brutApresSanction * PP.vps.taux / 100);
    var its = calculITS(brutApresSanction - cnssOuvriere);
    /* Les redevances ORTB ne sont pas mensuelles : chacune est prélevée une
       fois l'an, au mois qui lui est propre — la radio en mars pour tous, la
       télé en juin au-delà de 60 000 F. Les porter chaque mois majorerait les
       retenues de onze douzièmes. Les deux parts restent distinguées jusqu'au
       bulletin : c'est ainsi que la clinique les déclare. */
    var detailOrtb = calculOrtb(brut, mois);
    var ortb = detailOrtb.montant;
    var ortbRadio = (detailOrtb.parCategorie.radio || {}).montant || 0;
    var ortbTele = (detailOrtb.parCategorie.tele || {}).montant || 0;

    /* Avances en cours */
    var avancesEnCours = avances().active().filter(function (a) {
      return a.employeId === employe.id && a.statutAvance === 'en_cours';
    });
    var totalAvances = C.sum(avancesEnCours, 'mensualite');

    /* Participations aux événements du personnel imputées sur ce salaire.
       On ne retient QUE le mois de retenue choisi : porter la participation
       chaque mois la prélèverait autant de fois qu'il y a de bulletins. Les
       participations déjà réglées au comptant n'y figurent évidemment pas. */
    var periode = C.pad(annee, 4) + '-' + C.pad(mois + 1, 2);
    var participationsMois = S.collection('participations').active().filter(function (x) {
      return x.employeId === employe.id && x.mode === 'salaire'
        && x.periodeRetenue === periode;
    });
    var totalParticipations = C.sum(participationsMois, 'montant');

    var totalRetenues = cnssOuvriere + its + ortb + totalAvances + totalParticipations;
    var net = brutApresSanction - totalRetenues;

    return {
      employe: employe, periode: periode, annee: annee, mois: mois,
      gardes: gardes, permanences: permanences,
      salaireBase: salaireBase, primeAnciennete: primeAnciennete,
      lignesPrimes: lignesPrimes, totalPrimes: totalPrimes,
      brut: brut, pctSanction: pctSanction, sanction: sanction, brutApresSanction: brutApresSanction,
      cnssOuvriere: cnssOuvriere, cnssPatronale: cnssPatronale,
      vps: vps, its: its, ortb: ortb, detailOrtb: detailOrtb,
      ortbRadio: ortbRadio, ortbTele: ortbTele,
      avances: totalAvances, avancesDetail: avancesEnCours,
      participations: totalParticipations, participationsDetail: participationsMois,
      totalRetenues: totalRetenues,
      net: net,
      coutEmployeur: brutApresSanction + cnssPatronale + vps,
    };
  }

  function calculerTous(annee, mois) {
    return personnel().map(function (e) { return calculer(e, annee, mois); });
  }

  /* ==========================================================================
   * TABLEAU DE BORD PAIE
   * ======================================================================== */
  global.SIGH.screen('m11-dashboard', {
    title: 'Tableau de bord — Paie',
    description: 'Masse salariale, primes, cotisations sociales et fiscales, avances et coût employeur.',
    render: K.dash({
      kpis: function () {
        var calc = calculerTous(AUJ.getFullYear(), AUJ.getMonth());
        return [
          { label: 'Masse salariale brute', value: C.money(C.sum(calc, 'brut')), icon: 'banknote', tone: 'navy' },
          { label: 'Net à payer', value: C.money(C.sum(calc, 'net')), icon: 'wallet', tone: 'success' },
          { label: 'Total des primes', value: C.money(C.sum(calc, 'totalPrimes')), icon: 'gift', tone: 'info', hint: 'Barème NS 132' },
          { label: 'Sanctions (NS 131)', value: C.money(C.sum(calc, 'sanction')), icon: 'trending-down', tone: 'danger' },
          { label: 'CNSS part ouvrière', value: C.money(C.sum(calc, 'cnssOuvriere')), icon: 'shield', tone: 'warning', hint: PP.cnss.ouvriere + ' %' },
          { label: 'CNSS part patronale', value: C.money(C.sum(calc, 'cnssPatronale')), icon: 'building-2', tone: 'warning', hint: PP.cnss.patronale + ' %' },
          { label: 'ITS retenu', value: C.money(C.sum(calc, 'its')), icon: 'landmark', tone: 'info' },
          { label: 'Coût employeur total', value: C.money(C.sum(calc, 'coutEmployeur')), icon: 'calculator', tone: 'neutral' },
        ];
      },
      sections: [
        {
          render: function () {
            var calc = calculerTous(AUJ.getFullYear(), AUJ.getMonth());
            return K.charts([
              {
                title: 'Décomposition de la masse salariale',
                render: function () {
                  return G.anneau(['Salaires de base', 'Primes NS 132', 'Prime d’ancienneté'], [
                    C.sum(calc, 'salaireBase'), C.sum(calc, 'totalPrimes'), C.sum(calc, 'primeAnciennete'),
                  ], { legend: 'bottom' });
                },
              },
              {
                title: 'Répartition des charges et retenues',
                render: function () {
                  return G.barres(['CNSS ouvrière', 'CNSS patronale', 'VPS', 'ITS', 'ORTB'], [{
                    label: 'Montant',
                    data: [C.sum(calc, 'cnssOuvriere'), C.sum(calc, 'cnssPatronale'), C.sum(calc, 'vps'), C.sum(calc, 'its'), C.sum(calc, 'ortb')],
                  }], { horizontal: true, height: 260 });
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
                  var calc = calculerTous(AUJ.getFullYear(), AUJ.getMonth());
                  var g = C.groupBy(calc, function (c) { return c.employe.service; });
                  return K.ranking(Object.keys(g).map(function (k) {
                    return { label: k, value: C.sum(g[k], 'brut') };
                  }).sort(function (a, b) { return b.value - a.value; }), { format: function (v) { return C.money(v, false); } });
                },
              },
              {
                title: 'Évolution de la masse salariale (12 mois)',
                render: function () {
                  var labels = G.moisGlissants(12);
                  var base = C.sum(personnel(), 'salaireBase');
                  var rnd = C.seeded(1733);
                  return G.ligne(labels, [{
                    label: 'Masse salariale',
                    data: labels.map(function (_, i) { return Math.round(base * (0.93 + rnd() * 0.14)); }),
                    color: G.TONES.navy,
                  }]);
                },
              },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm11-calcul', icon: 'calculator', label: 'Calculer la paie', detail: 'Période en cours' },
              { id: 'm11-bulletins', icon: 'file-text', label: 'Bulletins de paie', detail: 'Édition et archivage' },
              { id: 'm11-cotisations', icon: 'landmark', label: 'Cotisations', detail: 'CNSS, ITS, VPS' },
              { id: 'm11-validation', icon: 'badge-check', label: 'Validation Direction', detail: 'Avant diffusion' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * CALCUL DE LA PAIE
   * ======================================================================== */
  global.SIGH.screen('m11-calcul', {
    title: 'Calcul de la paie',
    description: 'Consolidation automatique : salaire de base, primes du planning, sanctions, cotisations et retenues.',
    regle: 'La chaîne appliquée est : <strong>planning validé → primes NS 132 → évaluation NS 131 → cotisations → bulletin</strong>. '
      + 'Aucun montant n’est saisi manuellement : tout découle des référentiels versionnés.',
    render: function (root) {
      var host = el('div.space-y-4');
      var selMois = el('select.select');
      C.MOIS.forEach(function (m, i) {
        selMois.appendChild(el('option', { value: String(i) }, m.charAt(0).toUpperCase() + m.slice(1) + ' 2026'));
      });
      selMois.value = String(AUJ.getMonth());

      var barre = el('div.card');
      var bbody = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      bbody.appendChild(el('div.min-w-\\[14rem\\]', null, [el('label.label', { text: 'Période de paie' }), selMois]));
      bbody.appendChild(K.btn('Lancer le calcul', { variant: 'primary', icon: 'play', onclick: afficher }));
      bbody.appendChild(K.btn('Générer les bulletins', { variant: 'success', icon: 'file-plus', onclick: genererBulletins }));
      bbody.appendChild(K.btn('Éditer le journal de paie', { icon: 'printer', onclick: journalPaie }));
      barre.appendChild(bbody);
      host.appendChild(barre);

      var vue = el('div.space-y-4');
      host.appendChild(vue);
      selMois.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;

      function calculs() { return calculerTous(2026, Number(selMois.value)); }

      function afficher() {
        var calc = calculs();
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Agents concernés', value: C.num(calc.length), icon: 'users-round', tone: 'navy' },
          { label: 'Masse salariale brute', value: C.money(C.sum(calc, 'brut')), icon: 'banknote', tone: 'info' },
          { label: 'Total des retenues', value: C.money(C.sum(calc, 'totalRetenues')), icon: 'trending-down', tone: 'warning' },
          { label: 'Net à payer', value: C.money(C.sum(calc, 'net')), icon: 'wallet', tone: 'success' },
        ]));

        vue.appendChild(U.dataTable({
          title: 'Détail du calcul — ' + C.MOIS[Number(selMois.value)] + ' 2026',
          rows: calc, exportName: 'calcul-paie', pageSize: 20,
          defaultSort: 'net', defaultDir: 'desc',
          columns: [
            { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true, value: function (c) { return c.employe.matricule; }, render: function (c) { return el('span.font-mono.text-xs', { text: c.employe.matricule }); } },
            {
              key: 'agent', label: 'Agent',
              value: function (c) { return c.employe.nomComplet; },
              render: function (c) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: c.employe.nomComplet }),
                  el('p.truncate.text-xs.text-slate-400', { text: fonctionLabel(c.employe.fonction) }),
                ]);
              },
            },
            { key: 'salaireBase', label: 'Base', align: 'right', text: function (c) { return C.money(c.salaireBase, false); }, render: function (c) { return C.money(c.salaireBase, false); } },
            { key: 'gardes', label: 'G', align: 'right', render: function (c) { return c.gardes || '—'; } },
            { key: 'permanences', label: 'P', align: 'right', render: function (c) { return c.permanences || '—'; } },
            { key: 'totalPrimes', label: 'Primes', align: 'right', text: function (c) { return C.money(c.totalPrimes, false); }, render: function (c) { return C.money(c.totalPrimes, false); } },
            { key: 'brut', label: 'Brut', align: 'right', text: function (c) { return C.money(c.brut, false); }, render: function (c) { return el('span.font-semibold', { text: C.money(c.brut, false) }); } },
            {
              key: 'sanction', label: 'Sanction', align: 'right',
              text: function (c) { return C.money(c.sanction, false); },
              render: function (c) { return c.sanction ? el('span.font-semibold.text-danger-600', { text: '− ' + C.money(c.sanction, false) }) : el('span.text-xs.text-slate-400', { text: '—' }); },
            },
            { key: 'cnssOuvriere', label: 'CNSS', align: 'right', text: function (c) { return C.money(c.cnssOuvriere, false); }, render: function (c) { return C.money(c.cnssOuvriere, false); } },
            { key: 'its', label: 'ITS', align: 'right', text: function (c) { return C.money(c.its, false); }, render: function (c) { return C.money(c.its, false); } },
            {
              key: 'avances', label: 'Avance sur salaire', align: 'right',
              text: function (c) { return C.money(c.avances, false); },
              render: function (c) {
                if (!c.avances) return el('span.text-xs.text-slate-300', { text: '—' });
                var reste = C.sum(c.avancesDetail || [], function (a) {
                  return Math.max(0, (a.montant || 0) - (a.rembourse || 0));
                });
                return el('div.text-right', null, [
                  el('span.font-semibold.text-warning-700', { text: '− ' + C.money(c.avances, false) }),
                  el('p.text-xs.text-slate-400', {
                    text: (c.avancesDetail || []).length > 1
                      ? C.num((c.avancesDetail || []).length) + ' avances · reste ' + C.money(reste, false)
                      : 'reste ' + C.money(reste, false),
                  }),
                ]);
              },
            },
            {
              key: 'participations', label: 'Événements', align: 'right',
              text: function (c) { return C.money(c.participations, false); },
              render: function (c) {
                if (!c.participations) return el('span.text-xs.text-slate-300', { text: '—' });
                return el('div.text-right', null, [
                  el('span.font-semibold.text-warning-700', { text: '− ' + C.money(c.participations, false) }),
                  el('p.text-xs.text-slate-400', {
                    text: C.num((c.participationsDetail || []).length) + ' participation(s)',
                  }),
                ]);
              },
            },
            {
              key: 'net', label: 'Net à payer', align: 'right',
              text: function (c) { return C.money(c.net, false); },
              render: function (c) { return el('span.font-bold.text-navy-900', { text: C.money(c.net, false) }); },
            },
          ],
          onRowClick: function (c) { detail(c); },
          rowActions: function (c) {
            return [K.iconBtn('file-text', 'Bulletin de paie', function () { bulletin(c); })];
          },
        }));
        U.icons(vue);
      }

      function detail(c) {
        U.drawer({
          title: c.employe.nomComplet, subtitle: 'Paie de ' + c.periode, width: 'max-w-2xl',
          body: el('div.space-y-4', null, [
            U.kpiGrid([
              { label: 'Salaire brut', value: C.money(c.brut), icon: 'banknote', tone: 'navy' },
              { label: 'Net à payer', value: C.money(c.net), icon: 'wallet', tone: 'success' },
            ], 'grid-cols-2'),
            U.card('Gains', K.miniTable([
              { label: 'Rubrique', key: 'k' },
              { label: 'Base', align: 'right', key: 'b' },
              { label: 'Montant', align: 'right', key: 'm' },
            ], [
              { k: 'Salaire de base', b: '', m: C.money(c.salaireBase, false) },
              { k: 'Prime d’ancienneté', b: anciennete(c.employe) + ' ans', m: C.money(c.primeAnciennete, false) },
            ].concat(c.lignesPrimes.map(function (p) {
              return { k: 'Prime — ' + p.label, b: p.nombre + ' × ' + C.money(p.unitaire, false), m: C.money(p.total, false) };
            })).concat([{ k: 'TOTAL BRUT', b: '', m: C.money(c.brut, false) }]))),
            U.card('Retenues', K.miniTable([
              { label: 'Rubrique', key: 'k' },
              { label: 'Taux / base', align: 'right', key: 'b' },
              { label: 'Montant', align: 'right', key: 'm' },
            ], [
              c.sanction ? { k: 'Sanction NS 131', b: c.pctSanction + ' %', m: C.money(c.sanction, false) } : null,
              { k: 'CNSS part ouvrière', b: PP.cnss.ouvriere + ' %', m: C.money(c.cnssOuvriere, false) },
              { k: 'ITS', b: 'Barème progressif', m: C.money(c.its, false) },
            ].filter(Boolean).concat(lignesOrtb(c).map(function (l) {
              return { k: l.libelle, b: l.base, m: l.montant };
            })).concat([
              c.avances ? { k: 'Remboursement d’avance', b: '', m: C.money(c.avances, false) } : null,
              c.participations ? {
                k: 'Participation aux événements',
                b: (c.participationsDetail || []).map(function (x) { return x.evenementLibelle; }).join(' · '),
                m: C.money(c.participations, false),
              } : null,
              { k: 'TOTAL DES RETENUES', b: '', m: C.money(c.totalRetenues + c.sanction, false) },
            ].filter(Boolean)))),
            U.card('Charges patronales', K.miniTable([
              { label: 'Rubrique', key: 'k' },
              { label: 'Taux', align: 'right', key: 'b' },
              { label: 'Montant', align: 'right', key: 'm' },
            ], [
              { k: 'CNSS part patronale', b: PP.cnss.patronale + ' %', m: C.money(c.cnssPatronale, false) },
              { k: 'VPS', b: PP.vps.taux + ' %', m: C.money(c.vps, false) },
              { k: 'COÛT TOTAL EMPLOYEUR', b: '', m: C.money(c.coutEmployeur, false) },
            ])),
          ]),
          footer: [K.btn('Éditer le bulletin', { variant: 'primary', icon: 'printer', onclick: function () { bulletin(c); } })],
        });
      }

      function genererBulletins() {
        var calc = calculs();
        U.confirm({
          title: 'Générer ' + calc.length + ' bulletin(s) de paie ?',
          message: 'Les bulletins seront enregistrés pour la période ' + C.MOIS[Number(selMois.value)] + ' 2026 '
            + 'et soumis à la validation de la Direction avant diffusion.',
          confirmLabel: 'Générer',
        }).then(function (ok) {
          if (!ok) return;
          var col = bulletins();
          var crees = [];
          calc.forEach(function (c) {
            crees.push(col.insert({
              reference: C.nextRef('BP-', 5),
              periode: c.periode, annee: c.annee, mois: c.mois,
              employeId: c.employe.id, employe: c.employe.nomComplet,
              matricule: c.employe.matricule, fonction: c.employe.fonction,
              service: c.employe.service, categorie: c.employe.categorie,
              cnss: c.employe.cnss, situation: c.employe.situation, telephone: c.employe.telephone,
              salaireBase: c.salaireBase, primeAnciennete: c.primeAnciennete,
              lignesPrimes: c.lignesPrimes, totalPrimes: c.totalPrimes,
              brut: c.brut, pctSanction: c.pctSanction, sanction: c.sanction,
              cnssOuvriere: c.cnssOuvriere, cnssPatronale: c.cnssPatronale,
              vps: c.vps, its: c.its, ortb: c.ortb, avances: c.avances,
              totalRetenues: c.totalRetenues, net: c.net, coutEmployeur: c.coutEmployeur,
              statutBulletin: 'a_valider',
            }));
          });
          U.toast(crees.length + ' bulletin(s) généré(s).', {
            type: 'success',
            detail: 'En attente de validation par la Direction.',
            undo: function () { crees.forEach(function (r) { r.undo(); }); },
          });
        });
      }

      function bulletin(c) {
        etatBulletin({
          reference: 'BP-' + c.employe.matricule + '-' + C.pad(c.mois + 1, 2),
          periode: c.periode, employe: c.employe.nomComplet, matricule: c.employe.matricule,
          fonction: c.employe.fonction, service: c.employe.service, categorie: c.employe.categorie,
          cnss: c.employe.cnss, situation: c.employe.situation, telephone: c.employe.telephone,
          salaireBase: c.salaireBase, primeAnciennete: c.primeAnciennete,
          lignesPrimes: c.lignesPrimes, totalPrimes: c.totalPrimes,
          brut: c.brut, pctSanction: c.pctSanction, sanction: c.sanction,
          cnssOuvriere: c.cnssOuvriere, cnssPatronale: c.cnssPatronale,
          vps: c.vps, its: c.its, ortb: c.ortb, avances: c.avances,
          totalRetenues: c.totalRetenues, net: c.net,
        });
      }

      function journalPaie() {
        var calc = calculs();
        P.etat({
          titre: 'Journal de paie',
          sousTitre: C.MOIS[Number(selMois.value)] + ' 2026',
          cartouche: [['Période', C.MOIS[Number(selMois.value)] + ' 2026'],
            ['Effectif', C.num(calc.length)],
            ['Masse salariale brute', C.money(C.sum(calc, 'brut'))],
            ['Net à payer', C.money(C.sum(calc, 'net'))],
            ['CNSS totale', C.money(C.sum(calc, 'cnssOuvriere') + C.sum(calc, 'cnssPatronale'))],
            ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'Mat.', value: function (c) { return c.employe.matricule; } },
            { label: 'Agent', value: function (c) { return c.employe.nomComplet; } },
            { label: 'Base', align: 'right', value: function (c) { return C.money(c.salaireBase, false); }, somme: function (c) { return c.salaireBase; } },
            { label: 'Primes', align: 'right', value: function (c) { return C.money(c.totalPrimes, false); }, somme: function (c) { return c.totalPrimes; } },
            { label: 'Brut', align: 'right', value: function (c) { return C.money(c.brut, false); }, somme: function (c) { return c.brut; } },
            { label: 'Sanction', align: 'right', value: function (c) { return c.sanction ? C.money(c.sanction, false) : ''; }, somme: function (c) { return c.sanction; } },
            { label: 'CNSS', align: 'right', value: function (c) { return C.money(c.cnssOuvriere, false); }, somme: function (c) { return c.cnssOuvriere; } },
            { label: 'ITS', align: 'right', value: function (c) { return C.money(c.its, false); }, somme: function (c) { return c.its; } },
            { label: 'Net à payer', align: 'right', value: function (c) { return C.money(c.net, false); }, somme: function (c) { return c.net; } },
          ], C.sortBy(calc, function (c) { return c.employe.nomComplet; }), {
            /* Un journal de paie sans total oblige le comptable à additionner
               quarante-quatre lignes à la main pour vérifier ce qu'il verse —
               et le pied ne s'imprimait pas : ses clés ne correspondaient à
               aucune colonne porteuse de `key`. Chaque colonne refait sa somme
               depuis les lignes réellement imprimées. */
            total: true, totalLabel: 'TOTAL GÉNÉRAL',
          }),
          signatures: [{ role: 'Le Responsable RH' },
            { role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Direction', nom: 'BASSONGUI Chabi Séko', mention: 'Validation' }],
        });
      }
    },
  });

  /* ==========================================================================
   * BULLETIN DE PAIE — état imprimable
   * ======================================================================== */
  function etatBulletin(b) {
    var gains = [
      { rub: '01', libelle: 'Salaire de base', base: '', taux: '', montant: C.money(b.salaireBase, false) },
      b.primeAnciennete ? { rub: '02', libelle: 'Prime d’ancienneté', base: '', taux: '', montant: C.money(b.primeAnciennete, false) } : null,
    ].filter(Boolean);
    (b.lignesPrimes || []).forEach(function (p, i) {
      gains.push({
        rub: C.pad(gains.length + 1, 2), libelle: 'Prime — ' + p.label,
        base: String(p.nombre), taux: C.money(p.unitaire, false), montant: C.money(p.total, false),
      });
    });
    gains.push({ rub: '', libelle: 'TOTAL BRUT', base: '', taux: '', montant: C.money(b.brut, false) });

    var retenues = [
      b.sanction ? { rub: '', libelle: 'Sanction NS 131', base: C.money(b.brut, false), taux: b.pctSanction + ' %', montant: C.money(b.sanction, false) } : null,
      { rub: '', libelle: 'CNSS part ouvrière', base: C.money(b.brut - b.sanction, false), taux: PP.cnss.ouvriere + ' %', montant: C.money(b.cnssOuvriere, false) },
      { rub: '', libelle: 'Impôt sur les traitements et salaires (ITS)', base: '', taux: 'Barème', montant: C.money(b.its, false) },
    ].filter(Boolean).concat(lignesOrtb(b).map(function (l) {
      return { rub: '', libelle: l.libelle, base: l.base, taux: 'Forfait annuel', montant: l.montant };
    })).concat([
      b.avances ? { rub: '', libelle: 'Remboursement d’avance sur salaire', base: '', taux: '', montant: C.money(b.avances, false) } : null,
      b.participations ? {
        rub: '', libelle: 'Participation aux événements du personnel',
        base: (b.participationsDetail || []).map(function (x) { return x.evenementLibelle; }).join(' ; '),
        taux: 'Forfait', montant: C.money(b.participations, false),
      } : null,
      { rub: '', libelle: 'TOTAL DES RETENUES', base: '', taux: '', montant: C.money(b.totalRetenues + (b.sanction || 0), false) },
    ].filter(Boolean));

    var contenu = el('div.space-y-3');
    contenu.appendChild(el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Éléments de gain' }));
    contenu.appendChild(P.tableau([
      { label: 'N°', key: 'rub' }, { label: 'Libellé', key: 'libelle' },
      { label: 'Nombre', key: 'base', align: 'right' },
      { label: 'Taux / unitaire', key: 'taux', align: 'right' },
      { label: 'Montant', key: 'montant', align: 'right' },
    ], gains));

    contenu.appendChild(el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Retenues' }));
    contenu.appendChild(P.tableau([
      { label: 'N°', key: 'rub' }, { label: 'Libellé', key: 'libelle' },
      { label: 'Base', key: 'base', align: 'right' },
      { label: 'Taux', key: 'taux', align: 'right' },
      { label: 'Montant', key: 'montant', align: 'right' },
    ], retenues));

    /* Le bulletin doit tenir sur une page : gains, retenues, net et charges
       patronales cohabitent mal en taille courante. La réduction porte sur
       le CONTENU seul — l’en-tête officielle et le cartouche gardent leur
       taille, ce sont eux qu’on lit en premier. */
    contenu.classList.add('text-[10px]');
    var net = el('div.mt-4.ml-auto.w-2\\/3');
    net.appendChild(P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
      { k: 'Salaire brut', v: C.money(b.brut, false) },
      { k: 'Total des retenues', v: C.money(b.totalRetenues + (b.sanction || 0), false) },
      { k: 'NET À PAYER', v: C.money(b.net, false) },
    ]));
    contenu.appendChild(net);

    contenu.appendChild(el('p.mt-3.text-\\[9px\\].text-slate-600', {
      text: 'Charges patronales (non déduites du net) : CNSS ' + PP.cnss.patronale + ' % — '
        + C.money(b.cnssPatronale) + ' ; VPS ' + PP.vps.taux + ' % — ' + C.money(b.vps) + '.',
    }));

    P.etat({
      titre: 'Bulletin de paie',
      sousTitre: b.periode,
      cartouche: [
        ['Nom et prénoms', b.employe],
        ['Matricule', b.matricule],
        ['Fonction', fonctionLabel(b.fonction)],
        ['Service', b.service],
        ['Catégorie / échelon', b.categorie],
        ['Numéro CNSS', b.cnss],
        ['Situation matrimoniale', b.situation],
        ['Téléphone', b.telephone],
      ],
      contenu: contenu,
      signatures: [{ role: 'L’Employé(e)', nom: b.employe, mention: 'Signature' },
        { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
    });
  }

  /* ==========================================================================
   * BULLETINS DE PAIE
   * ======================================================================== */
  global.SIGH.screen('m11-bulletins', {
    title: 'Bulletins de paie',
    description: 'Bulletins générés, statut de validation et édition avec l’entête officielle de la clinique.',
    render: K.crud({
      collection: 'bulletins', entite: 'bulletin', entiteP: 'bulletins', module: 'M11',
      defaultSort: 'periode', defaultDir: 'desc', pageSize: 15, readonly: true,
      intro: function () {
        return K.note('Les bulletins sont produits par le moteur de calcul : ils ne sont pas modifiables directement. '
          + 'Toute correction passe par la reprise du calcul de la période.', { tone: 'info' });
      },
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (b) { return el('span.font-mono.text-xs', { text: b.reference }); } },
        { key: 'periode', label: 'Période', nowrap: true },
        { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true },
        { key: 'employe', label: 'Agent' },
        { key: 'service', label: 'Service' },
        { key: 'brut', label: 'Brut', align: 'right', text: function (b) { return C.money(b.brut, false); }, render: function (b) { return C.money(b.brut, false); } },
        {
          key: 'sanction', label: 'Sanction', align: 'right',
          text: function (b) { return C.money(b.sanction || 0, false); },
          render: function (b) { return b.sanction ? el('span.text-danger-600', { text: '− ' + C.money(b.sanction, false) }) : '—'; },
        },
        { key: 'totalRetenues', label: 'Retenues', align: 'right', text: function (b) { return C.money(b.totalRetenues, false); }, render: function (b) { return C.money(b.totalRetenues, false); } },
        {
          key: 'net', label: 'Net à payer', align: 'right',
          text: function (b) { return C.money(b.net, false); },
          render: function (b) { return el('span.font-bold.text-navy-900', { text: C.money(b.net, false) }); },
        },
        {
          key: 'statutBulletin', label: 'Statut',
          render: function (b) {
            var m = { a_valider: ['À valider', 'warning'], valide: ['Validé', 'success'], diffuse: ['Diffusé', 'navy'] };
            var x = m[b.statutBulletin] || ['—', 'neutral'];
            return U.badge(x[0], x[1]);
          },
        },
      ],
      filters: [
        { name: 'periode', label: 'Période', options: C.MOIS.map(function (m) { return m.charAt(0).toUpperCase() + m.slice(1) + ' 2026'; }) },
        { name: 'service', label: 'Service', options: D.SERVICES },
        { name: 'statutBulletin', label: 'Statut', options: [{ value: 'a_valider', label: 'À valider' }, { value: 'valide', label: 'Validé' }, { value: 'diffuse', label: 'Diffusé' }] },
      ],
      kpis: function (rows) {
        return [
          { label: 'Bulletins générés', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
          { label: 'Masse salariale brute', value: C.money(C.sum(rows, 'brut')), icon: 'banknote', tone: 'info' },
          { label: 'Net à payer', value: C.money(C.sum(rows, 'net')), icon: 'wallet', tone: 'success' },
          { label: 'En attente de validation', value: C.num(rows.filter(function (b) { return b.statutBulletin === 'a_valider'; }).length), icon: 'hourglass', tone: 'warning' },
        ];
      },
      etat: etatBulletin,
      detail: function (b) {
        return el('div.space-y-4', null, [
          U.kpiGrid([
            { label: 'Salaire brut', value: C.money(b.brut), icon: 'banknote', tone: 'navy' },
            { label: 'Net à payer', value: C.money(b.net), icon: 'wallet', tone: 'success' },
          ], 'grid-cols-2'),
          U.descList([['Référence', b.reference], ['Période', b.periode], ['Agent', b.employe],
            ['Matricule', b.matricule], ['Fonction', fonctionLabel(b.fonction)], ['Service', b.service],
            ['Catégorie', b.categorie], ['N° CNSS', b.cnss]]),
          U.card('Gains', K.miniTable([
            { label: 'Rubrique', key: 'k' }, { label: 'Montant', align: 'right', key: 'm' },
          ], [
            { k: 'Salaire de base', m: C.money(b.salaireBase, false) },
            { k: 'Prime d’ancienneté', m: C.money(b.primeAnciennete || 0, false) },
            { k: 'Primes NS 132', m: C.money(b.totalPrimes || 0, false) },
            { k: 'TOTAL BRUT', m: C.money(b.brut, false) },
          ])),
          U.card('Retenues', K.miniTable([
            { label: 'Rubrique', key: 'k' }, { label: 'Montant', align: 'right', key: 'm' },
          ], [
            b.sanction ? { k: 'Sanction NS 131 (' + b.pctSanction + ' %)', m: C.money(b.sanction, false) } : null,
            { k: 'CNSS part ouvrière', m: C.money(b.cnssOuvriere, false) },
            { k: 'ITS', m: C.money(b.its, false) },
          ].filter(Boolean).concat(lignesOrtb(b).map(function (l) {
            return { k: l.libelle, m: l.montant };
          })).concat([
            b.avances ? { k: 'Avance sur salaire', m: C.money(b.avances, false) } : null,
            b.participations ? { k: 'Participation aux événements', m: C.money(b.participations, false) } : null,
          ].filter(Boolean)))),
        ]);
      },
    }),
  });

  /* ==========================================================================
   * COTISATIONS
   * ======================================================================== */
  global.SIGH.screen('m11-cotisations', {
    title: 'Cotisations CNSS / ITS / VPS',
    description: 'États des cotisations sociales et fiscales, exploitables pour les déclarations périodiques.',
    regle: 'Part patronale <strong>' + PP.cnss.patronale + ' %</strong> et part ouvrière <strong>' + PP.cnss.ouvriere
      + ' %</strong> de la CNSS ; VPS ' + PP.vps.taux + ' % ; ITS au barème progressif ; '
      + 'redevances ORTB forfaitaires et annuelles — <strong>Radio 1 000 F pour tous en mars</strong>, '
      + '<strong>Télé 3 000 F au-delà de 60 000 F en juin</strong>, les deux se cumulant.',
    render: function (root) {
      var host = el('div.space-y-4');
      var selMois = el('select.select');
      C.MOIS.forEach(function (m, i) {
        selMois.appendChild(el('option', { value: String(i) }, m.charAt(0).toUpperCase() + m.slice(1) + ' 2026'));
      });
      selMois.value = String(AUJ.getMonth());

      var barre = el('div.card');
      var bbody = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      bbody.appendChild(el('div.min-w-\\[14rem\\]', null, [el('label.label', { text: 'Période' }), selMois]));
      bbody.appendChild(K.btn('État CNSS', { icon: 'printer', onclick: function () { etatCotisation('CNSS'); } }));
      bbody.appendChild(K.btn('État ITS', { icon: 'printer', onclick: function () { etatCotisation('ITS'); } }));
      bbody.appendChild(K.btn('État VPS', { icon: 'printer', onclick: function () { etatCotisation('VPS'); } }));
      bbody.appendChild(K.btn('État ORTB', { icon: 'radio', onclick: function () { etatCotisation('ORTB'); } }));
      barre.appendChild(bbody);
      host.appendChild(barre);

      var vue = el('div.space-y-4');
      host.appendChild(vue);
      selMois.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;

      function calc() { return calculerTous(2026, Number(selMois.value)); }

      function afficher() {
        var c = calc();
        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'CNSS part ouvrière', value: C.money(C.sum(c, 'cnssOuvriere')), icon: 'user', tone: 'warning', hint: PP.cnss.ouvriere + ' % du brut' },
          { label: 'CNSS part patronale', value: C.money(C.sum(c, 'cnssPatronale')), icon: 'building-2', tone: 'warning', hint: PP.cnss.patronale + ' % du brut' },
          { label: 'CNSS totale à verser', value: C.money(C.sum(c, 'cnssOuvriere') + C.sum(c, 'cnssPatronale')), icon: 'landmark', tone: 'danger' },
          { label: 'ITS retenu', value: C.money(C.sum(c, 'its')), icon: 'receipt', tone: 'info' },
          { label: 'VPS', value: C.money(C.sum(c, 'vps')), icon: 'percent', tone: 'navy', hint: PP.vps.taux + ' % du brut' },
          {
            label: 'ORTB Radio', value: C.money(C.sum(c, 'ortbRadio')), icon: 'radio-tower', tone: 'neutral',
            hint: 'Tous les salariés · prélevée en mars',
          },
          {
            label: 'ORTB Télé', value: C.money(C.sum(c, 'ortbTele')), icon: 'tv', tone: 'neutral',
            hint: 'Au-delà de 60 000 F · prélevée en juin',
          },
          { label: 'Masse salariale brute', value: C.money(C.sum(c, 'brut')), icon: 'banknote', tone: 'success' },
          { label: 'Coût employeur', value: C.money(C.sum(c, 'coutEmployeur')), icon: 'calculator', tone: 'neutral' },
        ]));

        vue.appendChild(U.dataTable({
          title: 'Détail des cotisations — ' + C.MOIS[Number(selMois.value)] + ' 2026',
          rows: c, exportName: 'cotisations', pageSize: 20,
          columns: [
            { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true, value: function (x) { return x.employe.matricule; }, render: function (x) { return x.employe.matricule; } },
            { key: 'agent', label: 'Agent', value: function (x) { return x.employe.nomComplet; }, render: function (x) { return x.employe.nomComplet; } },
            { key: 'cnssNum', label: 'N° CNSS', nowrap: true, value: function (x) { return x.employe.cnss; }, render: function (x) { return el('span.font-mono.text-xs.text-slate-500', { text: x.employe.cnss }); } },
            { key: 'brut', label: 'Brut', align: 'right', text: function (x) { return C.money(x.brut, false); }, render: function (x) { return C.money(x.brut, false); } },
            { key: 'cnssOuvriere', label: 'CNSS ouvrière', align: 'right', text: function (x) { return C.money(x.cnssOuvriere, false); }, render: function (x) { return C.money(x.cnssOuvriere, false); } },
            { key: 'cnssPatronale', label: 'CNSS patronale', align: 'right', text: function (x) { return C.money(x.cnssPatronale, false); }, render: function (x) { return C.money(x.cnssPatronale, false); } },
            { key: 'vps', label: 'VPS', align: 'right', text: function (x) { return C.money(x.vps, false); }, render: function (x) { return C.money(x.vps, false); } },
            { key: 'its', label: 'ITS', align: 'right', text: function (x) { return C.money(x.its, false); }, render: function (x) { return C.money(x.its, false); } },
            { key: 'ortbRadio', label: 'ORTB Radio', align: 'right', text: function (x) { return C.money(x.ortbRadio, false); }, render: function (x) { return x.ortbRadio ? C.money(x.ortbRadio, false) : el('span.text-xs.text-slate-300', { text: '—' }); } },
            { key: 'ortbTele', label: 'ORTB Télé', align: 'right', text: function (x) { return C.money(x.ortbTele, false); }, render: function (x) { return x.ortbTele ? C.money(x.ortbTele, false) : el('span.text-xs.text-slate-300', { text: '—' }); } },
            { key: 'ortb', label: 'ORTB total', align: 'right', text: function (x) { return C.money(x.ortb, false); }, render: function (x) { return el('span.font-semibold', { text: C.money(x.ortb, false) }); } },
          ],
        }));

        vue.appendChild(U.card('Barème ITS appliqué', K.miniTable([
          { label: 'Tranche de revenu', render: function (t) { return t.a == null ? 'Au-delà de ' + C.money(t.de - 1) : C.money(t.de) + ' à ' + C.money(t.a); } },
          { label: 'Taux', align: 'right', render: function (t) { return t.taux + ' %'; } },
        ], PP.its.bareme)));

        U.icons(vue);
      }

      function etatCotisation(type) {
        var c = calc();
        var colonnes, total, titre;
        if (type === 'CNSS') {
          titre = 'État des cotisations CNSS';
          colonnes = [
            { label: 'Mat.', value: function (x) { return x.employe.matricule; } },
            { label: 'Agent', value: function (x) { return x.employe.nomComplet; } },
            { label: 'N° CNSS', value: function (x) { return x.employe.cnss; } },
            { label: 'Salaire brut', align: 'right', value: function (x) { return C.money(x.brut, false); } },
            { label: 'Part ouvrière (' + PP.cnss.ouvriere + ' %)', align: 'right', value: function (x) { return C.money(x.cnssOuvriere, false); } },
            { label: 'Part patronale (' + PP.cnss.patronale + ' %)', align: 'right', value: function (x) { return C.money(x.cnssPatronale, false); } },
            { label: 'Total', align: 'right', value: function (x) { return C.money(x.cnssOuvriere + x.cnssPatronale, false); } },
          ];
          total = C.sum(c, 'cnssOuvriere') + C.sum(c, 'cnssPatronale');
        } else if (type === 'ITS') {
          titre = 'État de l’impôt sur les traitements et salaires';
          colonnes = [
            { label: 'Mat.', value: function (x) { return x.employe.matricule; } },
            { label: 'Agent', value: function (x) { return x.employe.nomComplet; } },
            { label: 'Salaire brut', align: 'right', value: function (x) { return C.money(x.brut, false); } },
            { label: 'Base imposable', align: 'right', value: function (x) { return C.money(x.brutApresSanction - x.cnssOuvriere, false); } },
            { label: 'ITS retenu', align: 'right', value: function (x) { return C.money(x.its, false); } },
          ];
          total = C.sum(c, 'its');
        } else if (type === 'ORTB') {
          titre = 'État des redevances ORTB';
          colonnes = [
            { label: 'Mat.', value: function (x) { return x.employe.matricule; } },
            { label: 'Agent', value: function (x) { return x.employe.nomComplet; } },
            { label: 'Salaire brut', align: 'right', value: function (x) { return C.money(x.brut, false); } },
            { label: 'ORTB Radio', align: 'right', value: function (x) { return x.ortbRadio ? C.money(x.ortbRadio, false) : '—'; } },
            { label: 'ORTB Télé', align: 'right', value: function (x) { return x.ortbTele ? C.money(x.ortbTele, false) : '—'; } },
            { label: 'Total retenu', align: 'right', value: function (x) { return C.money(x.ortb, false); } },
          ];
          total = C.sum(c, 'ortb');
        } else {
          titre = 'État du versement patronal de solidarité';
          colonnes = [
            { label: 'Mat.', value: function (x) { return x.employe.matricule; } },
            { label: 'Agent', value: function (x) { return x.employe.nomComplet; } },
            { label: 'Salaire brut', align: 'right', value: function (x) { return C.money(x.brut, false); } },
            { label: 'VPS (' + PP.vps.taux + ' %)', align: 'right', value: function (x) { return C.money(x.vps, false); } },
          ];
          total = C.sum(c, 'vps');
        }

        P.etat({
          titre: titre,
          sousTitre: C.MOIS[Number(selMois.value)] + ' 2026',
          cartouche: [['Période', C.MOIS[Number(selMois.value)] + ' 2026'],
            ['Effectif', C.num(c.length)], ['Masse salariale', C.money(C.sum(c, 'brut'))],
            ['Montant à verser', C.money(total)],
            ['IFU employeur', C.BRAND.ifu], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau(colonnes, C.sortBy(c, function (x) { return x.employe.nomComplet; })),
          signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * HEURES SUPPLÉMENTAIRES
   * ======================================================================== */
  global.SIGH.screen('m11-heures-sup', {
    title: 'Heures supplémentaires',
    description: 'Déclaration et valorisation des heures effectuées au-delà de l’horaire contractuel.',
    render: function (root) {
      var col = S.collection('heuresSup', { module: 'M11', entite: 'HeureSupplementaire' });
      if (!col.all().length && S.amorcable('heuresSup')) {
        var rnd = C.seeded(1949);
        personnel().slice(0, 20).forEach(function (e, i) {
          var h = C.between(rnd, 2, 24);
          var taux = Math.round(e.salaireBase / 173.33 * 1.25);
          col.all().push({
            id: 'HS' + C.pad(i + 1, 4), statut: 'actif',
            reference: 'HS-' + C.pad(i + 1, 4),
            periode: C.MOIS[AUJ.getMonth()].charAt(0).toUpperCase() + C.MOIS[AUJ.getMonth()].slice(1) + ' 2026',
            employeId: e.id, employe: e.nomComplet, matricule: e.matricule, service: e.service,
            heures: h, tauxHoraire: taux, majoration: 25, montant: h * taux,
            motif: C.pick(rnd, ['Renfort de garde', 'Urgence', 'Remplacement', 'Surcroît d’activité']),
            valide: rnd() > 0.3,
          });
        });
        S.save();
      }

      return K.crud({
        collection: 'heuresSup', entite: 'déclaration', entiteP: 'déclarations', module: 'M11',
        defaultSort: 'montant', defaultDir: 'desc', pageSize: 15,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (h) { return el('span.font-mono.text-xs', { text: h.reference }); } },
          { key: 'periode', label: 'Période', nowrap: true },
          { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true },
          { key: 'employe', label: 'Agent' },
          { key: 'service', label: 'Service' },
          { key: 'heures', label: 'Heures', align: 'right' },
          { key: 'tauxHoraire', label: 'Taux horaire', align: 'right', text: function (h) { return C.money(h.tauxHoraire, false); }, render: function (h) { return C.money(h.tauxHoraire, false); } },
          { key: 'majoration', label: 'Majoration', align: 'right', render: function (h) { return h.majoration + ' %'; } },
          { key: 'montant', label: 'Montant', align: 'right', text: function (h) { return C.money(h.montant, false); }, render: function (h) { return el('span.font-semibold', { text: C.money(h.montant, false) }); } },
          { key: 'motif', label: 'Motif' },
          { key: 'valide', label: 'Validation', text: function (h) { return h.valide ? 'Validée' : 'En attente'; }, render: function (h) { return h.valide ? U.badge('Validée', 'success') : U.badge('En attente', 'warning'); } },
        ],
        fields: function () {
          return [
            {
              name: 'employeId', label: 'Agent', type: 'select', required: true, col: 'full',
              options: C.sortBy(personnel(), 'nomComplet').map(function (e) { return { value: e.id, label: e.matricule + ' — ' + e.nomComplet }; }),
            },
            { name: 'periode', label: 'Période', type: 'select', required: true, options: C.MOIS.map(function (m) { return m.charAt(0).toUpperCase() + m.slice(1) + ' 2026'; }) },
            { name: 'heures', label: 'Nombre d’heures', type: 'number', min: 1, required: true },
            { name: 'majoration', label: 'Majoration (%)', type: 'number', min: 0, value: 25 },
            { name: 'motif', label: 'Motif', type: 'select', required: true, options: ['Renfort de garde', 'Urgence', 'Remplacement', 'Surcroît d’activité'] },
            { name: 'valide', label: 'Déclaration validée', type: 'checkbox' },
          ];
        },
        transform: function (v) {
          var e = personnel().filter(function (x) { return x.id === v.employeId; })[0];
          if (e) {
            v.employe = e.nomComplet; v.matricule = e.matricule; v.service = e.service;
            v.tauxHoraire = Math.round(e.salaireBase / 173.33 * (1 + (Number(v.majoration) || 25) / 100));
          }
          v.montant = (Number(v.heures) || 0) * (v.tauxHoraire || 0);
          if (!v.reference) v.reference = C.nextRef('HS-', 4);
          return v;
        },
        onCreate: function () { return { majoration: 25, valide: false, periode: C.MOIS[AUJ.getMonth()].charAt(0).toUpperCase() + C.MOIS[AUJ.getMonth()].slice(1) + ' 2026' }; },
        filters: [
          { name: 'periode', label: 'Période', options: C.MOIS.map(function (m) { return m.charAt(0).toUpperCase() + m.slice(1) + ' 2026'; }) },
          { name: 'service', label: 'Service', options: D.SERVICES },
        ],
        kpis: function (rows) {
          return [
            { label: 'Déclarations', value: C.num(rows.length), icon: 'clock', tone: 'navy' },
            { label: 'Heures déclarées', value: C.num(C.sum(rows, 'heures')), icon: 'timer', tone: 'info' },
            { label: 'Montant à payer', value: C.money(C.sum(rows.filter(function (h) { return h.valide; }), 'montant')), icon: 'wallet', tone: 'success' },
            { label: 'En attente de validation', value: C.num(rows.filter(function (h) { return !h.valide; }).length), icon: 'hourglass', tone: 'warning' },
          ];
        },
      })(root);
    },
  });

  /* ==========================================================================
   * AVANCES SUR SALAIRE
   * ======================================================================== */
  global.SIGH.screen('m11-avances', {
    title: 'Avances sur salaire',
    description: 'Octroi et suivi du remboursement des avances, avec retenue automatique sur le bulletin.',
    render: function (root) {
      var col = avances();
      if (!col.all().length && S.amorcable('avances')) {
        var rnd = C.seeded(2069);
        personnel().slice(0, 12).forEach(function (e, i) {
          var montant = C.between(rnd, 1, 4) * 25000;
          var nb = C.between(rnd, 2, 6);
          col.all().push({
            id: 'AV' + C.pad(i + 1, 4), statut: 'actif',
            reference: 'AVS-' + C.pad(i + 1, 4),
            employeId: e.id, employe: e.nomComplet, matricule: e.matricule, service: e.service,
            date: C.iso(C.addDays(AUJ, -C.between(rnd, 5, 150))),
            montant: montant, nbMensualites: nb, mensualite: Math.round(montant / nb),
            rembourse: Math.round(montant / nb) * C.between(rnd, 0, nb),
            motif: C.pick(rnd, ['Frais de santé', 'Frais de scolarité', 'Événement familial', 'Besoin personnel']),
            statutAvance: 'en_cours',
          });
        });
        col.all().forEach(function (a) {
          if (a.rembourse >= a.montant) { a.statutAvance = 'solde'; a.rembourse = a.montant; }
        });
        S.save();
      }

      return K.crud({
        collection: 'avances', entite: 'avance', entiteP: 'avances', module: 'M11',
        defaultSort: 'date', defaultDir: 'desc', pageSize: 15,
        intro: function () {
          return K.note('La mensualité de remboursement est <strong>automatiquement retenue</strong> sur le bulletin de paie tant que l’avance n’est pas soldée.', { tone: 'info' });
        },
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (a) { return el('span.font-mono.text-xs', { text: a.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (a) { return C.dateFR(a.date); }, render: function (a) { return C.dateFR(a.date); } },
          { key: 'matricule', label: 'Mat.', align: 'right', nowrap: true },
          { key: 'employe', label: 'Agent' },
          { key: 'motif', label: 'Motif' },
          { key: 'montant', label: 'Montant accordé', align: 'right', text: function (a) { return C.money(a.montant, false); }, render: function (a) { return el('span.font-semibold', { text: C.money(a.montant, false) }); } },
          { key: 'nbMensualites', label: 'Mensualités', align: 'right' },
          { key: 'mensualite', label: 'Retenue mensuelle', align: 'right', text: function (a) { return C.money(a.mensualite, false); }, render: function (a) { return C.money(a.mensualite, false); } },
          { key: 'rembourse', label: 'Remboursé', align: 'right', text: function (a) { return C.money(a.rembourse, false); }, render: function (a) { return C.money(a.rembourse, false); } },
          {
            key: 'restant', label: 'Restant dû', align: 'right',
            value: function (a) { return a.montant - a.rembourse; },
            text: function (a) { return C.money(a.montant - a.rembourse, false); },
            render: function (a) {
              var r = a.montant - a.rembourse;
              return r > 0 ? el('span.font-semibold.text-danger-600', { text: C.money(r, false) }) : U.badge('Soldée', 'success');
            },
          },
        ],
        fields: function () {
          return [
            {
              name: 'employeId', label: 'Agent', type: 'select', required: true, col: 'full',
              options: C.sortBy(personnel(), 'nomComplet').map(function (e) { return { value: e.id, label: e.matricule + ' — ' + e.nomComplet + ' (salaire ' + C.money(e.salaireBase) + ')' }; }),
            },
            { name: 'date', label: 'Date d’octroi', type: 'date', required: true },
            { name: 'montant', label: 'Montant accordé (FCFA)', type: 'money', required: true, min: 1 },
            { name: 'nbMensualites', label: 'Nombre de mensualités', type: 'number', min: 1, max: 12, required: true },
            { name: 'motif', label: 'Motif', type: 'select', required: true, options: ['Frais de santé', 'Frais de scolarité', 'Événement familial', 'Besoin personnel', 'Autre'] },
            { name: 'statutAvance', label: 'Statut', type: 'select', options: [{ value: 'en_cours', label: 'En cours de remboursement' }, { value: 'solde', label: 'Soldée' }] },
          ];
        },
        transform: function (v) {
          var e = personnel().filter(function (x) { return x.id === v.employeId; })[0];
          if (e) { v.employe = e.nomComplet; v.matricule = e.matricule; v.service = e.service; }
          v.mensualite = Math.round(v.montant / (Number(v.nbMensualites) || 1));
          if (v.rembourse == null) v.rembourse = 0;
          if (!v.statutAvance) v.statutAvance = 'en_cours';
          if (!v.reference) v.reference = C.nextRef('AVS-', 4);
          return v;
        },
        beforeSave: function (v) {
          var e = personnel().filter(function (x) { return x.id === v.employeId; })[0];
          if (e && v.montant > e.salaireBase * 3) {
            return 'Le montant de l’avance ne peut excéder trois mois de salaire (' + C.money(e.salaireBase * 3) + ').';
          }
          return null;
        },
        onCreate: function () { return { date: C.iso(AUJ), nbMensualites: 3, rembourse: 0, statutAvance: 'en_cours' }; },
        filters: [{ name: 'statutAvance', label: 'Statut', options: [{ value: 'en_cours', label: 'En cours' }, { value: 'solde', label: 'Soldée' }] }],
        kpis: function (rows) {
          var enCours = rows.filter(function (a) { return a.statutAvance === 'en_cours'; });
          return [
            { label: 'Avances accordées', value: C.num(rows.length), icon: 'hand-coins', tone: 'navy' },
            { label: 'Montant total accordé', value: C.money(C.sum(rows, 'montant')), icon: 'banknote', tone: 'info' },
            { label: 'Restant dû', value: C.money(C.sum(rows, function (a) { return a.montant - a.rembourse; })), icon: 'wallet', tone: 'warning' },
            { label: 'Retenues mensuelles', value: C.money(C.sum(enCours, 'mensualite')), icon: 'trending-down', tone: 'danger' },
          ];
        },
        etat: function (a) {
          P.etat({
            titre: 'Demande d’avance sur salaire',
            sousTitre: a.reference,
            cartouche: [['Agent', a.employe], ['Matricule', a.matricule], ['Service', a.service],
              ['Date d’octroi', C.dateFR(a.date)], ['Montant accordé', C.money(a.montant)],
              ['Mensualités', a.nbMensualites + ' × ' + C.money(a.mensualite)]],
            contenu: el('div.space-y-3', null, [
              el('p', { text: 'Il est accordé à ' + a.employe + ', matricule ' + a.matricule
                + ', une avance sur salaire d’un montant de ' + C.money(a.montant) + ', au titre de : ' + a.motif + '.' }),
              P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
                { k: 'Montant accordé', v: C.money(a.montant, false) },
                { k: 'Nombre de mensualités', v: String(a.nbMensualites) },
                { k: 'Retenue mensuelle', v: C.money(a.mensualite, false) },
                { k: 'Déjà remboursé', v: C.money(a.rembourse, false) },
                { k: 'RESTANT DÛ', v: C.money(a.montant - a.rembourse, false) },
              ]),
              el('p.mt-3.text-\\[10px\\].italic', {
                text: 'Le remboursement s’effectue par retenue automatique sur le bulletin de paie, à raison de '
                  + C.money(a.mensualite) + ' par mois, jusqu’à apurement complet.',
              }),
            ]),
            signatures: [{ role: 'L’Agent', nom: a.employe, mention: 'Lu et approuvé' },
              { role: 'Le Comptable', nom: 'KASSA Augustin' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * VALIDATION DIRECTION
   * ======================================================================== */
  global.SIGH.screen('m11-validation', {
    title: 'Validation de la paie',
    description: 'Soumission des bulletins à la Direction pour validation avant diffusion aux agents.',
    regle: 'Aucun bulletin ne peut être diffusé sans <strong>validation formelle de la Direction</strong>.',
    render: function (root) {
      var col = bulletins();
      var host = el('div.space-y-4');
      var table;

      function parPeriode() {
        var g = C.groupBy(col.active(), 'periode');
        return Object.keys(g).map(function (k) {
          var b = g[k];
          return {
            id: k, periode: k, nb: b.length,
            brut: C.sum(b, 'brut'), net: C.sum(b, 'net'),
            cnss: C.sum(b, 'cnssOuvriere') + C.sum(b, 'cnssPatronale'),
            aValider: b.filter(function (x) { return x.statutBulletin === 'a_valider'; }).length,
            valides: b.filter(function (x) { return x.statutBulletin !== 'a_valider'; }).length,
          };
        });
      }

      var lots = parPeriode();
      host.appendChild(U.kpiGrid([
        { label: 'Périodes traitées', value: C.num(lots.length), icon: 'calendar', tone: 'navy' },
        { label: 'Bulletins à valider', value: C.num(C.sum(lots, 'aValider')), icon: 'hourglass', tone: 'warning' },
        { label: 'Bulletins validés', value: C.num(C.sum(lots, 'valides')), icon: 'badge-check', tone: 'success' },
        { label: 'Net à payer cumulé', value: C.money(C.sum(lots, 'net')), icon: 'wallet', tone: 'info' },
      ]));

      if (!lots.length) {
        host.appendChild(U.card(null, U.empty('Aucun bulletin généré.', {
          icon: 'file-text',
          hint: 'Lancer le calcul de la paie puis générer les bulletins avant de les soumettre à validation.',
          action: K.lien('m11-calcul', 'Calculer la paie', { variant: 'primary', icon: 'calculator' }),
        })));
        root.appendChild(host);
        return null;
      }

      table = U.dataTable({
        title: 'Lots de paie par période',
        rows: parPeriode, exportName: 'validation-paie', pageSize: 12,
        columns: [
          { key: 'periode', label: 'Période', nowrap: true },
          { key: 'nb', label: 'Bulletins', align: 'right' },
          { key: 'brut', label: 'Masse brute', align: 'right', text: function (l) { return C.money(l.brut, false); }, render: function (l) { return C.money(l.brut, false); } },
          { key: 'cnss', label: 'CNSS totale', align: 'right', text: function (l) { return C.money(l.cnss, false); }, render: function (l) { return C.money(l.cnss, false); } },
          { key: 'net', label: 'Net à payer', align: 'right', text: function (l) { return C.money(l.net, false); }, render: function (l) { return el('span.font-bold.text-navy-900', { text: C.money(l.net, false) }); } },
          {
            key: 'aValider', label: 'Statut',
            render: function (l) {
              return l.aValider
                ? U.badge(l.aValider + ' à valider', 'warning')
                : U.badge('Validé', 'success');
            },
          },
        ],
        rowActions: function (l) {
          var acts = [K.iconBtn('printer', 'Journal de paie', function () { journal(l); })];
          if (l.aValider) {
            acts.push(K.btn('Valider le lot', { size: 'sm', variant: 'success', icon: 'badge-check', onclick: function () { valider(l); } }));
          }
          return acts;
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function valider(l) {
        U.confirm({
          title: 'Valider la paie de ' + l.periode + ' ?',
          message: 'Cette validation autorise la diffusion de ' + l.nb + ' bulletin(s) pour un net à payer total de '
            + C.money(l.net) + '. L’opération est journalisée au nom de la Direction.',
          confirmLabel: 'Valider la paie',
        }).then(function (ok) {
          if (!ok) return;
          var majs = [];
          col.active().filter(function (b) { return b.periode === l.periode && b.statutBulletin === 'a_valider'; })
            .forEach(function (b) {
              majs.push(col.update(b.id, { statutBulletin: 'valide', validePar: 'BASSONGUI Chabi Séko', dateValidation: C.iso(AUJ) }));
            });
          table.refresh();
          U.toast('Paie de ' + l.periode + ' validée par la Direction.', {
            type: 'success',
            detail: majs.length + ' bulletin(s) autorisé(s) à la diffusion.',
            undo: function () { majs.forEach(function (m) { m.undo(); }); table.refresh(); },
          });
        });
      }

      function journal(l) {
        var b = col.active().filter(function (x) { return x.periode === l.periode; });
        P.etat({
          titre: 'Journal de paie — validation',
          sousTitre: l.periode,
          cartouche: [['Période', l.periode], ['Bulletins', C.num(l.nb)],
            ['Masse salariale brute', C.money(l.brut)], ['Net à payer', C.money(l.net)],
            ['CNSS totale', C.money(l.cnss)], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'Mat.', key: 'matricule' },
            { label: 'Agent', key: 'employe' },
            { label: 'Service', key: 'service' },
            { label: 'Brut', align: 'right', value: function (x) { return C.money(x.brut, false); },
              somme: function (x) { return x.brut || 0; } },
            { label: 'Retenues', align: 'right', value: function (x) { return C.money(x.totalRetenues, false); },
              somme: function (x) { return x.totalRetenues || 0; } },
            { label: 'Net à payer', align: 'right', value: function (x) { return C.money(x.net, false); },
              somme: function (x) { return x.net || 0; } },
            { label: 'Émargement', value: function () { return ''; } },
          ], C.sortBy(b, 'employe'), { total: true }),
          signatures: [{ role: 'Le Responsable RH' },
            { role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Direction', nom: 'BASSONGUI Chabi Séko', mention: 'Bon à payer' }],
        });
      }
    },
  });
  /* ==========================================================================
   * REDEVANCE ORTB
   * --------------------------------------------------------------------------
   * Règle précisée par la Direction le 20/08/2026 : DEUX redevances qui se
   * CUMULENT, et non deux tranches exclusives.
   *   ORTB Radio : 1 000 F, TOUS les salariés sans exception, en mars ;
   *   ORTB Télé  : 3 000 F, salaire brut > 60 000 F, en juin, EN SUS.
   * Un agent au-dessus du seuil supporte donc 4 000 F sur l'exercice.
   *
   * L'écran montre, agent par agent, la part radio et la part télé, ce qui a
   * déjà été prélevé et ce qui reste à prélever — la question que pose le
   * comptable au moment de reverser.
   * ======================================================================== */
  global.SIGH.screen('m11-ortb', {
    title: 'Redevance ORTB',
    description: 'Redevances audiovisuelles prélevées sur les salaires : catégorie Radio et catégorie Télé, mois de prélèvement et suivi de l’exercice.',
    regle: 'Deux redevances <strong>distinctes qui se cumulent</strong> : '
      + '<strong>ORTB Radio, 1 000 F, tous les salariés sans exception, prélevés en mars</strong> ; '
      + '<strong>ORTB Télé, 3 000 F, salaire brut supérieur à 60 000 F, prélevés en juin</strong>, en sus de la radio. '
      + 'Un agent au-dessus du seuil acquitte donc <strong>4 000 F</strong> sur l’exercice. '
      + 'Chacune n’apparaît que sur le bulletin de son mois — les porter chaque mois majorerait '
      + 'les retenues de onze douzièmes.',
    render: function (root) {
      var annee = 2026;
      var PO = PP.ortb;
      var RADIO = (PO.redevances || []).filter(function (r) { return r.id === 'radio'; })[0] || {};
      var TELE = (PO.redevances || []).filter(function (r) { return r.id === 'tele'; })[0] || {};
      var selMois = el('select.select');
      for (var m = 0; m < 12; m++) selMois.appendChild(el('option', { value: String(m) }, C.MOIS[m] + ' ' + annee));
      selMois.value = String(AUJ.getMonth());
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Mois de paie' }), selMois]),
        K.btn('Imprimer l’état', { variant: 'primary', icon: 'printer', onclick: imprimer }),
        K.btn('Obligations', { icon: 'book-open-check', onclick: function () { global.SIGH.app.go('cfg-comptabilite'); } }),
      ]));
      selMois.addEventListener('change', afficher);
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      /* Un agent, ses deux parts, son état sur l'exercice. */
      function lignes() {
        var mois = Number(selMois.value);
        return personnel().map(function (e) {
          var c = calculer(e, annee, mois);
          var d = c.detailOrtb || { lignes: [], parCategorie: {} };
          var radio = d.parCategorie.radio || null;
          var tele = d.parCategorie.tele || null;
          return {
            id: e.id, matricule: e.matricule, agent: e.nomComplet, poste: e.poste,
            brut: c.brut,
            radio: radio ? radio.montantAnnuel : 0,
            tele: tele ? tele.montantAnnuel : 0,
            totalAnnuel: d.montantAnnuel || 0,
            categorie: tele ? 'les_deux' : (radio ? 'radio' : 'aucune'),
            categorieLabel: tele ? 'Radio + Télé' : (radio ? 'Radio seule' : 'Non redevable'),
            duCeMois: d.montant || 0,
            libelleDuCeMois: (d.lignes || []).filter(function (l) { return l.du; })
              .map(function (l) { return l.categorie; }).join(' + '),
            prelevee: (d.lignes || []).filter(function (l) { return mois > l.mois; }).length,
            aPrelever: (d.lignes || []).filter(function (l) { return mois < l.mois; }).length,
            resume: d.resume || '—',
          };
        });
      }

      function afficher() {
        var mois = Number(selMois.value);
        var rows = lignes();
        var avecTele = rows.filter(function (r) { return r.tele > 0; });
        var duCeMois = C.sum(rows, 'duCeMois');
        var totalExercice = C.sum(rows, 'totalAnnuel');

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          {
            label: 'ORTB Radio — tous les salariés', value: C.num(rows.length),
            icon: 'radio-tower', tone: 'navy',
            hint: C.money(rows.length * (RADIO.montant || 0)) + ' en ' + (RADIO.moisLabel || '—'),
          },
          {
            label: 'ORTB Télé — au-delà de ' + C.money(PO.seuilTele, false), value: C.num(avecTele.length),
            icon: 'tv', tone: 'info',
            hint: C.money(avecTele.length * (TELE.montant || 0)) + ' en ' + (TELE.moisLabel || '—'),
          },
          {
            label: 'Cumul par agent au-delà du seuil', value: C.money(PO.cumulMaximum),
            icon: 'layers', tone: 'neutral',
            hint: C.money(RADIO.montant, false) + ' radio + ' + C.money(TELE.montant, false) + ' télé',
          },
          {
            label: 'Dû sur ' + C.MOIS[mois], value: C.money(duCeMois), icon: 'coins',
            tone: duCeMois ? 'warning' : 'success',
            hint: duCeMois ? 'Prélèvement du mois' : 'Aucun prélèvement ce mois',
          },
        ]));

        vue.appendChild(K.note('La radio et la télé sont <strong>deux redevances distinctes qui se cumulent</strong> : '
          + 'un salaire supérieur à ' + C.money(PO.seuilTele, false) + ' n’est pas dispensé de la radio, il acquitte les deux. '
          + 'Total dû sur l’exercice ' + annee + ' : <strong>' + C.money(totalExercice) + '</strong> — '
          + C.money(rows.length * (RADIO.montant || 0)) + ' en ' + (RADIO.moisLabel || '—') + ' (radio) et '
          + C.money(avecTele.length * (TELE.montant || 0)) + ' en ' + (TELE.moisLabel || '—') + ' (télé).',
        { tone: 'info', icon: 'landmark' }));

        vue.appendChild(U.dataTable({
          title: 'Redevances par agent — ' + C.MOIS[mois] + ' ' + annee,
          rows: rows, exportName: 'redevance-ortb', pageSize: 20, searchable: true,
          defaultSort: 'agent',
          filters: [
            {
              name: 'categorie', label: 'Catégories',
              options: [{ value: 'les_deux', label: 'Radio + Télé' }, { value: 'radio', label: 'Radio seule' },
                { value: 'aucune', label: 'Non redevable' }],
            },
            {
              name: 'etat', label: 'État sur l’exercice',
              options: [{ value: 'du', label: 'Dû ce mois' }, { value: 'prelevee', label: 'Déjà prélevée' },
                { value: 'attente', label: 'À prélever' }],
              match: function (r, v) {
                if (v === 'du') return r.duCeMois > 0;
                if (v === 'prelevee') return r.prelevee > 0;
                return r.aPrelever > 0;
              },
            },
          ],
          columns: [
            { key: 'matricule', label: 'Matricule', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.matricule }); } },
            {
              key: 'agent', label: 'Agent',
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.agent }),
                  el('p.truncate.text-xs.text-slate-400', { text: r.poste }),
                ]);
              },
            },
            { key: 'brut', label: 'Salaire brut', align: 'right', text: function (r) { return String(r.brut); }, render: function (r) { return C.money(r.brut, false); } },
            {
              key: 'radio', label: 'ORTB Radio', align: 'right',
              text: function (r) { return String(r.radio); },
              render: function (r) {
                if (!r.radio) return el('span.text-xs.text-slate-400', { text: '—' });
                return el('span.text-sm', { text: C.money(r.radio, false) });
              },
            },
            {
              key: 'tele', label: 'ORTB Télé', align: 'right',
              text: function (r) { return String(r.tele); },
              render: function (r) {
                if (!r.tele) return el('span.text-xs.text-slate-400', { text: 'non redevable' });
                return el('span.text-sm', { text: C.money(r.tele, false) });
              },
            },
            {
              key: 'categorie', label: 'Catégories',
              render: function (r) {
                if (r.categorie === 'aucune') return el('span.text-xs.text-slate-400', { text: 'Non redevable' });
                return U.badge(r.categorieLabel, r.categorie === 'les_deux' ? 'navy' : 'info');
              },
            },
            {
              key: 'totalAnnuel', label: 'Total annuel', align: 'right',
              text: function (r) { return String(r.totalAnnuel); },
              render: function (r) { return el('span.font-semibold', { text: C.money(r.totalAnnuel, false) }); },
            },
            {
              key: 'duCeMois', label: 'Dû ce mois', align: 'right',
              text: function (r) { return String(r.duCeMois); },
              render: function (r) {
                if (r.duCeMois) {
                  return el('div.text-right', null, [
                    el('span.font-semibold.text-warning-700', { text: C.money(r.duCeMois, false) }),
                    el('p.text-xs.text-slate-400', { text: r.libelleDuCeMois }),
                  ]);
                }
                if (r.aPrelever) return el('span.text-xs.text-slate-400', { text: 'à prélever · ' + r.resume });
                if (r.prelevee) return U.badge('Déjà prélevée', 'success');
                return '—';
              },
            },
          ],
        }));
        U.icons(vue);
      }

      function imprimer() {
        var mois = Number(selMois.value);
        var rows = lignes().filter(function (r) { return r.categorie !== 'aucune'; });
        var duCeMois = C.sum(rows, 'duCeMois');
        P.etat({
          titre: 'État des redevances ORTB',
          sousTitre: C.MOIS[mois] + ' ' + annee,
          cartouche: [['Période', C.MOIS[mois] + ' ' + annee],
            ['Agents redevables', C.num(rows.length)],
            ['ORTB Radio', C.num(rows.filter(function (r) { return r.radio > 0; }).length) + ' agents — '
              + C.money(RADIO.montant, false) + ' en ' + (RADIO.moisLabel || '—')],
            ['ORTB Télé', C.num(rows.filter(function (r) { return r.tele > 0; }).length) + ' agents — '
              + C.money(TELE.montant, false) + ' en ' + (TELE.moisLabel || '—')],
            ['Dû sur le mois', C.money(duCeMois)],
            ['Total de l’exercice', C.money(C.sum(rows, 'totalAnnuel'))]],
          contenu: P.tableau([
            { label: 'Matricule', key: 'matricule' },
            { label: 'Agent', key: 'agent' },
            { label: 'Salaire brut', align: 'right', value: function (r) { return C.money(r.brut, false); } },
            /* On ne totalise PAS le salaire brut : ce n'est pas une redevance,
               et un total de bruts sur un état ORTB se lirait comme un montant
               dû. Les deux parts restent distinguées jusqu'au pied. */
            { label: 'ORTB Radio', align: 'right', value: function (r) { return r.radio ? C.money(r.radio, false) : '—'; }, somme: function (r) { return r.radio; } },
            { label: 'ORTB Télé', align: 'right', value: function (r) { return r.tele ? C.money(r.tele, false) : '—'; }, somme: function (r) { return r.tele; } },
            { label: 'Total annuel', align: 'right', value: function (r) { return C.money(r.totalAnnuel, false); }, somme: function (r) { return r.totalAnnuel; } },
            { label: 'Dû ce mois', align: 'right', value: function (r) { return r.duCeMois ? C.money(r.duCeMois, false) : '—'; }, somme: function (r) { return r.duCeMois; } },
          ], C.sortBy(rows, 'agent'), { total: true, totalLabel: 'TOTAL' }),
          signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });


  /* ==========================================================================
   * PRÊTS-ÉTUDES ET AVANCES SUR SALAIRE
   * --------------------------------------------------------------------------
   * Dispositif relevé sur la description de poste de l'Assistant de Direction :
   * « suivre les décaissements et les recouvrements des prêts-études ». Il ne
   * figurait dans aucun autre document et n'existait pas au prototype.
   *
   * LA RÈGLE QUI COMPTE : une échéance est retenue au bulletin du SEUL MOIS de
   * son échéance. La porter chaque mois la prélèverait autant de fois qu'il y a
   * de bulletins — c'est la même erreur que celle corrigée sur les redevances
   * ORTB et sur les participations aux événements. Le dispositif est différent,
   * le piège est identique.
   *
   * Un prêt ne se supprime pas : il s'archive (RG-14). Les échéances déjà
   * retenues l'ont été sur des bulletins émis.
   * ======================================================================== */
  function colPrets() {
    return S.collection('pretsEtudes', { module: 'M11', entite: 'prêt-études', prefix: 'PRT' });
  }

  global.SIGH.screen('m11-prets-etudes', {
    title: 'Prêts-études et avances',
    description: 'Décaissements consentis au personnel et recouvrement par retenue sur salaire.',
    regle: 'Une échéance est retenue au bulletin du <strong>seul mois de son échéance</strong>. La porter '
      + 'chaque mois la prélèverait autant de fois qu’il y a de bulletins — c’est le piège déjà rencontré sur '
      + 'les redevances ORTB et les participations aux événements. Un prêt <strong>s’archive</strong>, il ne '
      + 'se supprime pas : les échéances déjà retenues l’ont été sur des bulletins émis.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function agents() { return S.collection('personnel').active(); }

      function champs() {
        return [
          { name: 'employeId', label: 'Agent bénéficiaire', type: 'select', required: true,
            options: agents().map(function (a) {
              return { value: a.id, label: a.nomComplet, detail: a.poste || a.fonction };
            }) },
          { name: 'nature', label: 'Nature', type: 'select', required: true,
            options: [
              { value: 'pret_etudes', label: 'Prêt-études', detail: 'Financement d’une formation, remboursable' },
              { value: 'avance', label: 'Avance sur salaire', detail: 'Anticipation de rémunération' },
              { value: 'pret_social', label: 'Prêt social', detail: 'Événement familial, santé' },
            ] },
          { name: 'objet', label: 'Objet', type: 'text', required: true },
          { name: 'montant', label: 'Montant accordé (FCFA)', type: 'money', required: true, min: 1 },
          { name: 'dateAccord', label: 'Date d’accord', type: 'date', required: true },
          { name: 'premiereEcheance', label: 'Premier mois de retenue', type: 'month', required: true },
          { name: 'nbEcheances', label: 'Nombre d’échéances mensuelles', type: 'number',
            required: true, min: 1, max: 36,
            hint: 'Le montant est réparti à parts égales ; le dernier arrondi porte le reliquat.' },
          { name: 'autorisePar', label: 'Autorisé par', type: 'text', required: true },
        ];
      }

      /* L'échéancier, calculé et jamais saisi : le total des échéances doit
         valoir exactement le montant accordé, au franc près. */
      function echeancier(p2) {
        var n = Number(p2.nbEcheances) || 1;
        var base = Math.floor((Number(p2.montant) || 0) / n);
        var out = [];
        var an = Number(String(p2.premiereEcheance).slice(0, 4));
        var mo = Number(String(p2.premiereEcheance).slice(5, 7)) - 1;
        for (var i = 0; i < n; i++) {
          var d = new Date(an, mo + i, 1);
          var mois = d.getFullYear() + '-' + C.pad(d.getMonth() + 1, 2);
          /* Le reliquat d'arrondi tombe sur la DERNIÈRE échéance : sans cela,
             la somme des retenues serait inférieure au prêt et le solde ne se
             fermerait jamais. */
          var montant = i === n - 1 ? (Number(p2.montant) || 0) - base * (n - 1) : base;
          out.push({ rang: i + 1, mois: mois, montant: montant,
            retenue: (p2.retenues || []).indexOf(mois) !== -1 });
        }
        return out;
      }

      function solde(p2) {
        return echeancier(p2).filter(function (e) { return !e.retenue; })
          .reduce(function (n, e) { return n + e.montant; }, 0);
      }

      function afficher() {
        var rows = colPrets().active();
        var enCours = rows.filter(function (r) { return solde(r) > 0; });
        var encours = rows.reduce(function (n, r) { return n + solde(r); }, 0);
        var accorde = rows.reduce(function (n, r) { return n + (r.montant || 0); }, 0);

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Prêts et avances', value: C.num(rows.length), icon: 'graduation-cap', tone: 'navy' },
          { label: 'En cours de remboursement', value: C.num(enCours.length), icon: 'clock',
            tone: enCours.length ? 'warning' : 'success' },
          { label: 'Total accordé', value: C.money(accorde), icon: 'hand-coins', tone: 'info' },
          { label: 'Reste à recouvrer', value: C.money(encours), icon: 'wallet',
            tone: encours ? 'warning' : 'success' },
        ]));

        vue.appendChild(K.note('Ces sommes <strong>transitent</strong> : un prêt n’est ni une charge ni une '
          + 'recette, c’est une créance sur l’agent. Elle se solde par des retenues, chacune portée au bulletin '
          + 'du <strong>seul mois</strong> de son échéance.', { tone: 'info', icon: 'arrow-left-right' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'dateAccord').reverse(),
          empty: 'Aucun prêt ni avance enregistré.',
          actions: [K.creer(colPrets(), champs(), {
            module: 'M11', label: 'Nouveau prêt ou avance', titre: 'Prêt-études ou avance sur salaire',
            entite: 'Prêt', apres: afficher,
            transform: function (v) {
              var a = agents().filter(function (x) { return x.id === v.employeId; })[0];
              return Object.assign({}, v, {
                reference: C.nextRef('PRT-', 4),
                agent: a ? a.nomComplet : '—',
                matricule: a ? a.matricule : null,
                retenues: [],
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'agent', label: 'Agent' },
            { key: 'nature', label: 'Nature', render: function (r) {
              return { pret_etudes: 'Prêt-études', avance: 'Avance sur salaire',
                pret_social: 'Prêt social' }[r.nature] || r.nature;
            } },
            { key: 'objet', label: 'Objet' },
            { key: 'montant', label: 'Accordé', align: 'right',
              render: function (r) { return C.money(r.montant); } },
            { key: 'solde', label: 'Reste dû', align: 'right',
              render: function (r) {
                var s2 = solde(r);
                return s2 ? el('span.font-semibold.text-amber-700', { text: C.money(s2) })
                  : U.badge('soldé', 'success');
              } },
            { key: 'avancement', label: 'Échéances', align: 'center',
              render: function (r) {
                var e = echeancier(r);
                var faites = e.filter(function (x) { return x.retenue; }).length;
                return faites + ' / ' + e.length;
              } },
          ],
          rowActions: K.actionsLigne(colPrets(), champs(), {
            module: 'M11', refresh: afficher,
            titre: function (r) { return r.reference + ' — ' + r.agent; },
            detail: function (r) {
              return el('div.space-y-4', null,
                K.grid([
                  ['Référence', r.reference], ['Agent', r.agent],
                  ['Matricule', r.matricule || '—'],
                  ['Nature', { pret_etudes: 'Prêt-études', avance: 'Avance sur salaire',
                    pret_social: 'Prêt social' }[r.nature] || r.nature],
                  ['Objet', r.objet],
                  ['Montant accordé', C.money(r.montant)],
                  ['Date d’accord', C.dateFR(r.dateAccord)],
                  ['Autorisé par', r.autorisePar],
                  ['Reste à recouvrer', C.money(solde(r))],
                ]),
                K.section('Échéancier',
                  K.miniTable(['Rang', 'Mois de retenue', 'Montant', 'État'],
                    echeancier(r).map(function (e) {
                      return [String(e.rang), C.moisAnnee(e.mois + '-01'), C.money(e.montant),
                        e.retenue ? 'Retenue effectuée' : 'À retenir'];
                    }))),
                K.note('Chaque échéance figure au bulletin du <strong>seul mois</strong> indiqué. '
                  + 'La porter tous les mois la prélèverait autant de fois qu’il y a de bulletins.',
                { tone: 'info', icon: 'calendar-check' }));
            },
          }),
        }));
        U.icons(vue);
      }
    },
  });

})(window);
