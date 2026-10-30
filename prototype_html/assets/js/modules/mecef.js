/* =============================================================================
 * MECeF — Facturation normalisée (fiscalité électronique béninoise)
 * -----------------------------------------------------------------------------
 * CDCT §20 / draf1 §10.13 — émission, suivi et archivage des factures
 * normalisées : transmission, réponses, rejets, avoirs, annulations,
 * synchronisation, journal des transactions et paramétrage fiscal.
 *
 * Le prototype simule les échanges avec le dispositif fiscal : l'interfaçage
 * réel s'appuiera sur la machine électronique certifiée de facturation.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  var F = D.PARAM_FISCAL;
  /* Régime en vigueur : exonéré sur la facture de référence. Le taux normal
     de 18 % reste disponible et se règle dans la configuration fiscale. */
  var REGIME = F.regimesTva.filter(function (r) { return r.id === F.regimeTva; })[0] || F.regimesTva[0];
  var TAUX_TVA = REGIME.taux;
  var TAUX_AIB = F.aib.taux;   /* 1 % — acompte sur impôt assis sur les bénéfices. */

  /** Décomposition fiscale d'un montant, selon le régime en vigueur. */
  function decomposer(montantTTC) {
    var ht = TAUX_TVA ? Math.round(montantTTC * 100 / (100 + TAUX_TVA)) : montantTTC;
    var tva = montantTTC - ht;
    var aib = Math.round(ht * TAUX_AIB / 100);
    return { ht: ht, tva: tva, aib: aib, ttc: montantTTC, net: montantTTC + aib };
  }

  /** Code de certification MECeF/DGI : six groupes de quatre caractères. */
  function codeMecef(graine) {
    var alphabet = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    var rnd = C.seeded(graine || 1);
    var groupes = [];
    for (var g = 0; g < 6; g++) {
      var s = '';
      for (var i = 0; i < 4; i++) s += alphabet[Math.floor(rnd() * alphabet.length)];
      groupes.push(s);
    }
    return groupes.join('-');
  }

  function factures() { return S.collection('factures').active(); }
  /* Le registre fiscal suit l'EXERCICE choisi (sélecteur de l'en-tête) : une déclaration à la DGI porte sur une année. */
  function normalisees() {
    var X = global.SIGH.exercice;
    return factures().filter(function (f) { return !f.proforma && (!X || X.dansExercice(f.date)); });
  }

  var STATUTS = {
    valide: ['Validée', 'success'],
    en_attente: ['En attente de transmission', 'warning'],
    rejete: ['Rejetée', 'danger'],
  };
  function statutBadge(s) {
    var x = STATUTS[s] || ['—', 'neutral'];
    return U.badge(x[0], x[1]);
  }

  /* --- Colonnes communes --------------------------------------------------- */
  var colFacture = {
    key: 'numero', label: 'N° facture', nowrap: true,
    render: function (f) {
      return el('div', null, [
        el('p.font-mono.text-xs.font-semibold.text-navy-800', { text: f.numero }),
        f.numeroMecef ? el('p.font-mono.text-\\[10px\\].text-slate-400', { text: f.numeroMecef })
          : el('p.text-\\[10px\\].text-warning-600', { text: 'Non transmise' }),
      ]);
    },
  };
  var colDate = {
    key: 'date', label: 'Date', nowrap: true,
    text: function (f) { return C.dateFR(f.date); },
    render: function (f) { return C.dateFR(f.date); },
  };
  var colMontantTTC = {
    key: 'montantTTC', label: 'Montant TTC', align: 'right',
    text: function (f) { return C.money(f.montantTTC, false); },
    render: function (f) { return el('span.font-semibold', { text: C.money(f.montantTTC, false) }); },
  };
  var colTVA = {
    key: 'tva', label: 'TVA', align: 'right',
    value: function (f) { return Math.round(f.montantTTC * TAUX_TVA / (100 + TAUX_TVA)); },
    text: function (f) { return C.money(Math.round(f.montantTTC * TAUX_TVA / (100 + TAUX_TVA)), false); },
    render: function (f) { return C.money(Math.round(f.montantTTC * TAUX_TVA / (100 + TAUX_TVA)), false); },
  };
  var colStatutMecef = {
    key: 'statutMecef', label: 'Statut fiscal',
    render: function (f) { return statutBadge(f.statutMecef); },
  };

  /* ==========================================================================
   * TABLEAU DE BORD FISCAL
   * ======================================================================== */
  global.SIGH.screen('mecef-dashboard', {
    title: 'Tableau de bord fiscal — MECeF',
    description: 'Supervision de l’émission et de la transmission des factures normalisées à l’administration fiscale.',
    render: K.dash({
      alerte: function () {
        var rejetees = normalisees().filter(function (f) { return f.statutMecef === 'rejete'; });
        var attente = normalisees().filter(function (f) { return f.statutMecef === 'en_attente'; });
        if (!rejetees.length && !attente.length) return null;
        var wrap = el('div.grid.gap-2.sm\\:grid-cols-2');
        if (rejetees.length) {
          wrap.appendChild(K.note('<strong>' + rejetees.length + ' facture(s) rejetée(s)</strong> par le dispositif fiscal — correction et réémission requises.', { tone: 'danger', icon: 'file-x' }));
        }
        if (attente.length) {
          wrap.appendChild(K.note('<strong>' + attente.length + ' facture(s)</strong> en attente de transmission.', { tone: 'warning', icon: 'clock' }));
        }
        return wrap;
      },
      kpis: function () {
        var n = normalisees();
        var j = n.filter(function (f) { return C.iso(f.date) === C.iso(AUJ); });
        var validees = n.filter(function (f) { return f.statutMecef === 'valide'; });
        var tva = C.sum(validees, function (f) { return Math.round(f.montantTTC * TAUX_TVA / (100 + TAUX_TVA)); });
        return [
          { label: 'Factures émises aujourd’hui', value: C.num(j.length), icon: 'file-plus', tone: 'navy' },
          { label: 'Factures validées', value: C.num(validees.length), icon: 'file-check-2', tone: 'success' },
          { label: 'En attente de transmission', value: C.num(n.filter(function (f) { return f.statutMecef === 'en_attente'; }).length), icon: 'clock', tone: 'warning' },
          { label: 'Factures rejetées', value: C.num(n.filter(function (f) { return f.statutMecef === 'rejete'; }).length), icon: 'file-x', tone: 'danger' },
          { label: 'Montant total déclaré', value: C.money(C.sum(validees, 'montantTTC')), icon: 'trending-up', tone: 'info' },
          {
            label: TAUX_TVA ? 'TVA collectée' : 'AIB collecté',
            value: C.money(TAUX_TVA ? tva : C.sum(validees, function (f) { return decomposer(f.montantTTC).aib; })),
            icon: 'landmark', tone: 'navy',
            hint: TAUX_TVA ? 'Taux ' + TAUX_TVA + ' %' : 'AIB ' + TAUX_AIB + ' % — TVA exonérée',
          },
          { label: 'Taux de validation', value: C.pct(n.length ? validees.length / n.length * 100 : 0), icon: 'percent', tone: 'success' },
          { label: 'Dernière synchronisation', value: 'Aujourd’hui', icon: 'refresh-cw', tone: 'neutral', hint: C.heure(AUJ) },
        ];
      },
      sections: [
        {
          render: function () {
            return K.charts([
              {
                title: 'Évolution des factures normalisées (12 mois)',
                render: function () {
                  var s = K.parMois(normalisees(), 'date');
                  return G.ligne(s.labels, [{ label: 'Factures émises', data: s.data, color: G.TONES.navy }]);
                },
              },
              {
                title: 'Statut des transmissions',
                render: function () {
                  var n = normalisees();
                  return G.anneau(['Validées', 'En attente', 'Rejetées'], [
                    n.filter(function (f) { return f.statutMecef === 'valide'; }).length,
                    n.filter(function (f) { return f.statutMecef === 'en_attente'; }).length,
                    n.filter(function (f) { return f.statutMecef === 'rejete'; }).length,
                  ], { legend: 'bottom', colors: [G.TONES.vert, G.TONES.orange, G.TONES.rouge] });
                },
              },
            ]);
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Recettes déclarées et TVA (12 mois)',
                render: function () {
                  var validees = normalisees().filter(function (f) { return f.statutMecef === 'valide'; });
                  var s = K.parMois(validees, 'date', 'montantTTC');
                  var tva = s.data.map(function (v) { return Math.round(v * TAUX_TVA / (100 + TAUX_TVA)); });
                  return G.barres(s.labels, [
                    { label: 'Montant déclaré', data: s.data, color: G.TONES.navy },
                    { label: 'TVA collectée', data: tva, color: G.TONES.orange },
                  ]);
                },
              },
              {
                title: 'Répartition par nature de facture',
                render: function () {
                  var g = C.groupBy(normalisees(), 'type');
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
              { id: 'mecef-factures', icon: 'file-badge', label: 'Factures normalisées', detail: 'Registre fiscal' },
              { id: 'mecef-transmission', icon: 'send', label: 'Transmission', detail: 'File d’envoi et réponses' },
              { id: 'mecef-avoirs', icon: 'undo-2', label: 'Avoirs & annulations', detail: 'Rectifications' },
              { id: 'mecef-config', icon: 'settings', label: 'Configuration fiscale', detail: 'IFU, RCCM, numérotation' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * FACTURES NORMALISÉES
   * ======================================================================== */
  global.SIGH.screen('mecef-factures', {
    title: 'Factures normalisées',
    regle: 'Écran <strong>calculé</strong> : le registre reflète les factures émises et leur état de '
      + 'transmission. Une facture se corrige par un <strong>avoir</strong>, jamais par retouche — '
      + 'une pièce normalisée transmise à la DGI est définitive.',
    description: 'Registre fiscal des factures normalisées, avec identifiant MECeF, montant déclaré et TVA collectée.',
    render: function (root) {
      var rows = normalisees();
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Factures normalisées', value: C.num(rows.length), icon: 'file-badge', tone: 'navy' },
        { label: 'Montant déclaré', value: C.money(C.sum(rows, 'montantTTC')), icon: 'trending-up', tone: 'info' },
        { label: 'TVA collectée', value: C.money(C.sum(rows, function (f) { return Math.round(f.montantTTC * TAUX_TVA / (100 + TAUX_TVA)); })), icon: 'landmark', tone: 'warning' },
        { label: 'Validées par l’administration', value: C.num(rows.filter(function (f) { return f.statutMecef === 'valide'; }).length), icon: 'file-check-2', tone: 'success' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Registre des factures normalisées', rows: rows, exportName: 'factures-normalisees', pageSize: 15,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'statutMecef', label: 'Statut fiscal', options: [{ value: 'valide', label: 'Validée' }, { value: 'en_attente', label: 'En attente' }, { value: 'rejete', label: 'Rejetée' }] },
          { name: 'type', label: 'Nature', options: ['Consultation', 'Hospitalisation', 'Laboratoire', 'Pharmacie', 'Soins à domicile'] },
        ],
        columns: [
          colFacture, colDate,
          { key: 'patient', label: 'Client', render: function (f) { return el('div.min-w-0', null, [el('p.truncate.text-sm.text-slate-800', { text: f.patient }), el('p.font-mono.text-xs.text-slate-400', { text: f.patientCode })]); } },
          { key: 'type', label: 'Nature', render: function (f) { return U.badge(f.type, 'navy'); } },
          {
            key: 'montantHT', label: 'Montant HT', align: 'right',
            value: function (f) { return Math.round(f.montantTTC * 100 / (100 + TAUX_TVA)); },
            text: function (f) { return C.money(Math.round(f.montantTTC * 100 / (100 + TAUX_TVA)), false); },
            render: function (f) { return C.money(Math.round(f.montantTTC * 100 / (100 + TAUX_TVA)), false); },
          },
          colTVA, colMontantTTC, colStatutMecef,
        ],
        onRowClick: function (f) { consulter(f); },
        rowActions: function (f) {
          return [
            K.iconBtn('eye', 'Consulter', function () { consulter(f); }),
            K.iconBtn('printer', 'Imprimer la facture normalisée', function () { imprimer(f); }),
          ];
        },
      }));
      root.appendChild(host);
      return null;

      function consulter(f) {
        var ht = Math.round(f.montantTTC * 100 / (100 + TAUX_TVA));
        var tva = f.montantTTC - ht;
        U.drawer({
          title: f.numero, subtitle: (f.numeroMecef || 'Non transmise') + ' — ' + C.dateFR(f.date), width: 'max-w-2xl',
          body: el('div.space-y-4', null, [
            U.kpiGrid([
              { label: 'Montant TTC', value: C.money(f.montantTTC), icon: 'receipt', tone: 'navy' },
              { label: 'TVA collectée', value: C.money(tva), icon: 'landmark', tone: 'warning' },
            ], 'grid-cols-2'),
            U.descList([
              ['N° facture', el('span.font-mono', { text: f.numero })],
              ['Identifiant MECeF', f.numeroMecef ? el('span.font-mono', { text: f.numeroMecef }) : U.badge('Non attribué', 'warning')],
              ['Date d’émission', C.dateFR(f.date)],
              ['Client', f.patient], ['Dossier', f.patientCode],
              ['Nature', f.type],
              ['Montant HT', C.money(ht)],
              ['TVA (' + TAUX_TVA + ' %)', C.money(tva)],
              ['Montant TTC', C.money(f.montantTTC)],
              ['Statut de transmission', statutBadge(f.statutMecef)],
              ['IFU émetteur', C.BRAND.ifu],
              ['RCCM', C.BRAND.rccm],
            ]),
            f.statutMecef === 'rejete'
              ? K.note('<strong>Facture rejetée</strong> par le dispositif fiscal. Une correction puis une réémission sont nécessaires avant archivage définitif.', { tone: 'danger', icon: 'file-x' })
              : null,
          ]),
          footer: [K.btn('Imprimer', { variant: 'primary', icon: 'printer', onclick: function () { imprimer(f); } })],
        });
      }

      /* Reproduction fidèle de la facture normalisée certifiée MECeF, d'après
         la facture SoBAPS n° 26FNA00026 analysée lors du cadrage : colonnes
         HT/TTC, TVA, AIB, montant en toutes lettres, bloc de certification. */
      function imprimer(f) {
        var dec = decomposer(f.montantTTC);
        var ht = dec.ht, tva = dec.tva, aib = dec.aib, netAPayer = dec.net;
        var lignes = (f.lignes && f.lignes.length) ? f.lignes
          : [{ designation: 'Prestation — ' + f.type, quantite: 1, prixUnitaire: f.montantTTC }];
        var graine = Number(String(f.numeroMecef || f.numero).replace(/\D/g, '').slice(-6)) || 1;

        var contenu = el('div.space-y-3');
        contenu.appendChild(P.tableau([
          { label: 'Désignation', key: 'designation' },
          { label: 'Qté', key: 'quantite', align: 'right' },
          {
            label: 'P.U. HT', align: 'right',
            value: function (l) { return C.money(decomposer(l.prixUnitaire).ht, false); },
          },
          { label: 'P.U. TTC', align: 'right', value: function (l) { return C.money(l.prixUnitaire, false); } },
          {
            label: 'Montant HT', align: 'right',
            value: function (l) { return C.money(decomposer(l.quantite * l.prixUnitaire).ht, false); },
            somme: function (l) { return decomposer(l.quantite * l.prixUnitaire).ht; },
          },
          { label: 'Montant TTC', align: 'right', value: function (l) { return C.money(l.quantite * l.prixUnitaire, false); },
            somme: function (l) { return l.quantite * l.prixUnitaire; } },
        ], lignes, { total: true }));

        /* Bandeau des taxes à gauche, totaux à droite — disposition du modèle. */
        var bas = el('div.mt-4.flex.items-start.justify-between.gap-6');
        var taxes = el('div.w-2\\/5');
        taxes.appendChild(P.tableau([
          { label: 'Taxe', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' },
        ], [
          { k: F.tva.libelle, v: C.money(tva, false) },
          { k: F.aib.libelle + ' (' + F.aib.code + ')', v: C.money(aib, false) },
        ]));
        if (!TAUX_TVA) {
          taxes.appendChild(el('p.mt-1.text-\\[9px\\].italic.text-slate-500', { text: F.mentionExoneration }));
        }
        bas.appendChild(taxes);

        var totaux = el('div.w-1\\/2');
        totaux.appendChild(P.tableau([
          { label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' },
        ], [
          { k: 'TOTAL HT', v: C.money(ht, false) },
          { k: 'TOTAL TTC', v: C.money(f.montantTTC, false) },
          { k: 'NET À PAYER', v: C.money(netAPayer, false) },
        ]));
        totaux.appendChild(el('p.mt-1.text-right.text-\\[9px\\].text-slate-500', { text: 'Devise : ' + C.BRAND.devise }));
        bas.appendChild(totaux);
        contenu.appendChild(bas);

        /* Mention légale du montant en toutes lettres. */
        contenu.appendChild(el('div.mt-4.rounded.border.border-slate-400.p-2', null, [
          el('p.text-\\[9px\\].font-semibold.uppercase.text-slate-700', { text: F.mentionMontant + ' :' }),
          el('p.mt-0\\.5.text-\\[10px\\].font-medium.uppercase', { text: C.montantEnLettres(netAPayer) }),
        ]));

        /* Bloc de certification fiscale. */
        var codeDgi = codeMecef(graine);
        contenu.appendChild(el('div.mt-3.flex.items-center.gap-3.rounded.border-2.border-navy-900.p-3', null, [
          el('div.grid.h-20.w-20.shrink-0.place-items-center.border.border-slate-400.text-\\[8px\\].text-slate-400', { text: 'QR CODE MECeF' }),
          el('div.min-w-0', null, [
            el('p.text-\\[10px\\].font-bold.uppercase.text-navy-900', { text: 'Code MECeF / DGI' }),
            el('p.font-mono.text-\\[11px\\].font-semibold.tracking-wide', { text: codeDgi }),
            el('p.mt-1.text-\\[9px\\]', { text: 'MECeF NIM : ' + (f.numeroMecef || 'en attente d’attribution') }),
            el('p.text-\\[9px\\]', { text: 'MECeF Compteurs : ' + C.pad(graine % 9999, 4) + '/' + C.pad((graine % 9999) + 120, 5) }),
            el('p.text-\\[9px\\]', { text: 'MECeF Heure : ' + C.dateFR(f.date) + ' ' + C.heure(new Date()) }),
            el('p.text-\\[9px\\]', { text: 'IFU émetteur : ' + C.BRAND.ifu + ' — RCCM : ' + C.BRAND.rccm }),
          ]),
        ]));

        contenu.appendChild(el('p.mt-3.text-\\[9px\\].leading-relaxed.text-slate-600', {
          text: 'Facture normalisée émise conformément au dispositif de facturation électronique en vigueur en République du Bénin. '
            + 'Toute facture non revêtue du code MECeF/DGI et du code à barres de vérification est réputée non conforme.',
        }));

        P.etat({
          titre: 'Facture de vente — normalisée',
          sousTitre: f.numero + (f.numeroMecef ? ' — ' + f.numeroMecef : ''),
          cartouche: [
            ['Facture n°', f.numero], ['Date', C.dateFR(f.date)],
            ['Client', f.patient], ['Dossier client', f.patientCode],
            ['IFU client', C.BRAND.ifu], ['Nature', f.type],
          ],
          contenu: contenu,
          signatures: [
            { role: 'Mention du caissier', mention: 'Signature et cachet' },
            { role: 'Visa et cachet de la Direction' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * TRANSMISSION & RÉPONSES
   * ======================================================================== */
  global.SIGH.screen('mecef-transmission', {
    title: 'Transmission & réponses',
    regle: 'Écran <strong>calculé</strong> : le journal de transmission est une <strong>preuve</strong>. '
      + 'Il s’alimente des envois effectués et ne se modifie pas ; un rejet se traite en corrigeant la '
      + 'facture puis en retransmettant.',
    description: 'File d’envoi vers le dispositif fiscal, suivi des réponses, codes de retour et nouvelles tentatives.',
    render: function (root) {
      var col = S.collection('factures', { module: 'MECEF', entite: 'FactureNormalisee' });
      var host = el('div.space-y-4');
      var tabs;

      function enAttente() { return normalisees().filter(function (f) { return f.statutMecef === 'en_attente'; }); }
      function rejetees() { return normalisees().filter(function (f) { return f.statutMecef === 'rejete'; }); }
      function validees() { return normalisees().filter(function (f) { return f.statutMecef === 'valide'; }); }

      var CODES_REJET = [
        { code: 'E-101', libelle: 'Identifiant fiscal du client absent ou invalide' },
        { code: 'E-204', libelle: 'Montant de TVA incohérent avec le montant HT' },
        { code: 'E-307', libelle: 'Numérotation non séquentielle' },
        { code: 'E-412', libelle: 'Dépassement du délai de transmission' },
        { code: 'E-500', libelle: 'Dispositif temporairement indisponible' },
      ];

      host.appendChild(U.kpiGrid([
        { label: 'En attente d’envoi', value: C.num(enAttente().length), icon: 'clock', tone: 'warning' },
        { label: 'Transmissions réussies', value: C.num(validees().length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Rejets à corriger', value: C.num(rejetees().length), icon: 'file-x', tone: 'danger' },
        { label: 'Taux de réussite', value: C.pct(normalisees().length ? validees().length / normalisees().length * 100 : 0), icon: 'percent', tone: 'info' },
      ]));

      host.appendChild(el('div.flex.flex-wrap.gap-2', null, [
        K.btn('Synchroniser maintenant', {
          variant: 'primary', icon: 'refresh-cw',
          onclick: function () {
            var att = enAttente();
            if (!att.length) { U.toast('Aucune facture en attente de transmission.', { type: 'info' }); return; }
            U.confirm({
              title: 'Transmettre ' + att.length + ' facture(s) ?',
              message: 'Les factures en attente seront transmises au dispositif fiscal. Un identifiant MECeF sera attribué à chaque facture acceptée.',
              confirmLabel: 'Transmettre',
            }).then(function (ok) {
              if (!ok) return;
              var rnd = C.seeded(att.length * 7 + 13);
              var majs = [];
              var acceptees = 0, refusees = 0;
              att.forEach(function (f) {
                var accepte = rnd() > 0.12;
                if (accepte) acceptees++; else refusees++;
                majs.push(col.update(f.id, {
                  statutMecef: accepte ? 'valide' : 'rejete',
                  numeroMecef: accepte ? 'MECEF' + C.between(rnd, 1000000, 9999999) : null,
                  codeRetour: accepte ? 'OK-200' : C.pick(rnd, CODES_REJET).code,
                  dateTransmission: C.iso(AUJ),
                }));
              });
              if (tabs) tabs.selectTab('attente');
              U.toast('Synchronisation terminée : ' + acceptees + ' acceptée(s), ' + refusees + ' rejetée(s).', {
                type: refusees ? 'warning' : 'success',
                undo: function () { majs.forEach(function (m) { m.undo(); }); global.location.reload(); },
              });
              setTimeout(function () { global.location.reload(); }, 1500);
            });
          },
        }),
        K.lien('mecef-journal', 'Journal des transactions', { icon: 'scroll-text' }),
      ]));

      tabs = U.tabs([
        {
          id: 'attente', label: 'En attente', badge: enAttente().length,
          render: function () {
            return U.dataTable({
              rows: enAttente, exportName: 'mecef-en-attente', pageSize: 12,
              defaultSort: 'date', defaultDir: 'desc',
              emptyMessage: 'Aucune facture en attente de transmission.',
              columns: [colFacture, colDate, { key: 'patient', label: 'Client' }, colMontantTTC, colTVA, colStatutMecef],
              rowActions: function (f) {
                return [K.btn('Transmettre', {
                  size: 'sm', variant: 'primary', icon: 'send',
                  onclick: function () {
                    var res = col.update(f.id, {
                      statutMecef: 'valide',
                      numeroMecef: 'MECEF' + C.between(C.seeded(Date.now() % 99999), 1000000, 9999999),
                      codeRetour: 'OK-200', dateTransmission: C.iso(AUJ),
                    });
                    U.toast('Facture transmise et validée.', {
                      type: 'success', detail: res.record.numeroMecef,
                      undo: function () { res.undo(); global.location.reload(); },
                    });
                    setTimeout(function () { global.location.reload(); }, 1200);
                  },
                })];
              },
            });
          },
        },
        {
          id: 'rejets', label: 'Rejets', badge: rejetees().length,
          render: function () {
            var wrap = el('div.space-y-3');
            if (rejetees().length) {
              wrap.appendChild(K.note('Chaque rejet doit être corrigé puis réémis. Le code de retour du dispositif fiscal précise la nature de l’anomalie.', { tone: 'danger', icon: 'file-x' }));
            }
            wrap.appendChild(U.dataTable({
              rows: rejetees, exportName: 'mecef-rejets', pageSize: 12,
              defaultSort: 'date', defaultDir: 'desc',
              emptyMessage: 'Aucun rejet à traiter.',
              columns: [colFacture, colDate, { key: 'patient', label: 'Client' }, colMontantTTC,
                {
                  key: 'codeRetour', label: 'Code de retour',
                  render: function (f) {
                    var c = CODES_REJET.filter(function (x) { return x.code === f.codeRetour; })[0];
                    return el('div', null, [
                      el('p.font-mono.text-xs.font-semibold.text-danger-700', { text: f.codeRetour || 'E-000' }),
                      el('p.text-xs.text-slate-500', { text: c ? c.libelle : 'Anomalie non qualifiée' }),
                    ]);
                  },
                },
              ],
              rowActions: function (f) {
                return [K.btn('Corriger et réémettre', {
                  size: 'sm', variant: 'warning', icon: 'repeat',
                  onclick: function () {
                    var res = col.update(f.id, {
                      statutMecef: 'valide',
                      numeroMecef: 'MECEF' + C.between(C.seeded(Date.now() % 88888), 1000000, 9999999),
                      codeRetour: 'OK-200', dateTransmission: C.iso(AUJ), reemise: true,
                    });
                    U.toast('Facture corrigée et réémise avec succès.', {
                      type: 'success', undo: function () { res.undo(); global.location.reload(); },
                    });
                    setTimeout(function () { global.location.reload(); }, 1200);
                  },
                })];
              },
            }));
            return wrap;
          },
        },
        {
          id: 'validees', label: 'Transmissions réussies', badge: validees().length,
          render: function () {
            return U.dataTable({
              rows: validees, exportName: 'mecef-validees', pageSize: 12,
              defaultSort: 'date', defaultDir: 'desc',
              columns: [colFacture, colDate, { key: 'patient', label: 'Client' }, colMontantTTC, colTVA,
                { key: 'codeRetour', label: 'Réponse', render: function (f) { return U.badge(f.codeRetour || 'OK-200', 'success'); } },
              ],
            });
          },
        },
      ]);
      host.appendChild(tabs);
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * AVOIRS & ANNULATIONS
   * ======================================================================== */
  global.SIGH.screen('mecef-avoirs', {
    title: 'Avoirs & annulations',
    description: 'Émission des avoirs rectificatifs et suivi des factures annulées auprès de l’administration fiscale.',
    regle: 'Une facture normalisée transmise ne peut être supprimée : sa rectification passe obligatoirement par l’émission d’un <strong>avoir</strong>.',
    render: function (root) {
      var col = S.collection('avoirs', { module: 'MECEF', entite: 'Avoir' });
      var host = el('div.space-y-4');
      var table;
      function avoirsExercice() {
        var X = global.SIGH.exercice;
        return col.active().filter(function (a) { return !X || X.dansExercice(a.date); });
      }

      host.appendChild(U.kpiGrid([
        { label: 'Avoirs émis', value: C.num(avoirsExercice().length), icon: 'undo-2', tone: 'navy' },
        { label: 'Montant des avoirs', value: C.money(C.sum(avoirsExercice(), 'montant')), icon: 'wallet', tone: 'warning' },
        { label: 'TVA régularisée', value: C.money(C.sum(avoirsExercice(), function (a) { return Math.round(a.montant * TAUX_TVA / (100 + TAUX_TVA)); })), icon: 'landmark', tone: 'info' },
        { label: 'Factures annulées', value: C.num(factures().filter(function (f) { return f.annulee; }).length), icon: 'file-x', tone: 'danger' },
      ]));

      table = U.dataTable({
        title: 'Registre des avoirs',
        rows: function () { return avoirsExercice(); },
        exportName: 'avoirs-mecef', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        emptyMessage: 'Aucun avoir émis.',
        emptyHint: 'Un avoir rectifie une facture normalisée déjà transmise.',
        actions: [K.commande('Émettre un avoir', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(); } })],
        columns: [
          { key: 'reference', label: 'N° avoir', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.font-semibold', { text: a.reference }); } },
          { key: 'numeroMecef', label: 'Identifiant MECeF', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.text-slate-500', { text: a.numeroMecef || '—' }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (a) { return C.dateFR(a.date); }, render: function (a) { return C.dateFR(a.date); } },
          { key: 'factureNumero', label: 'Facture rectifiée', nowrap: true, render: function (a) { return el('span.font-mono.text-xs', { text: a.factureNumero }); } },
          { key: 'patient', label: 'Client' },
          { key: 'montant', label: 'Montant', align: 'right', text: function (a) { return C.money(a.montant, false); }, render: function (a) { return el('span.font-semibold.text-danger-600', { text: '− ' + C.money(a.montant, false) }); } },
          { key: 'motif', label: 'Motif' },
          { key: 'statutMecef', label: 'Statut', render: function (a) { return statutBadge(a.statutMecef); } },
        ],
        rowActions: function (a) { return [K.iconBtn('printer', 'Imprimer l’avoir', function () { etat(a); })]; },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function ouvrir() {
        var n = normalisees().filter(function (f) { return f.statutMecef === 'valide'; });
        if (!n.length) { U.toast('Aucune facture validée à rectifier.', { type: 'warning' }); return; }
        var f = U.form([
          {
            name: 'factureId', label: 'Facture à rectifier', type: 'select', required: true, col: 'full',
            options: C.sortBy(n, 'date', 'desc').slice(0, 200).map(function (x) {
              return { value: x.id, label: x.numero + ' — ' + x.patient + ' — ' + C.money(x.montantTTC) };
            }),
          },
          { name: 'date', label: 'Date de l’avoir', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'montant', label: 'Montant de l’avoir (FCFA)', type: 'money', required: true, min: 1 },
          { name: 'motif', label: 'Motif de la rectification', type: 'select', required: true, options: ['Erreur de facturation', 'Prestation non réalisée', 'Remise commerciale', 'Annulation de commande', 'Erreur de tarif'] },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ], {});

        var m = U.modal({
          title: 'Émettre un avoir', subtitle: 'Rectification d’une facture normalisée transmise', size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Émettre l’avoir', {
              variant: 'primary', icon: 'undo-2',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var fac = normalisees().filter(function (x) { return x.id === v.factureId; })[0];
                if (fac) {
                  v.factureNumero = fac.numero; v.patient = fac.patient; v.patientCode = fac.patientCode;
                  if (v.montant > fac.montantTTC) { U.toast('Le montant de l’avoir ne peut excéder celui de la facture.', { type: 'error' }); return; }
                }
                v.reference = C.referenceSuivante('AV-' + String(v.date).slice(0, 4) + '-', 4, col.all()); /* série lue sur les avoirs existants (E8) */
                v.numeroMecef = 'MECEF' + C.between(C.seeded(Date.now() % 77777), 1000000, 9999999);
                v.statutMecef = 'valide';
                var res = col.insert(v);
                m.close(); table.refresh();
                U.toast('Avoir ' + v.reference + ' émis et transmis.', { type: 'success', undo: function () { res.undo(); table.refresh(); } });
                etat(res.record);
              },
            }),
          ],
        });
      }

      function etat(a) {
        var ht = Math.round(a.montant * 100 / (100 + TAUX_TVA));
        var tva = a.montant - ht;
        P.etat({
          titre: 'Avoir sur facture normalisée',
          sousTitre: a.reference + ' — rectifie la facture ' + a.factureNumero,
          cartouche: [['N° avoir', a.reference], ['Identifiant MECeF', a.numeroMecef || '—'],
            ['Date', C.dateFR(a.date)], ['Facture rectifiée', a.factureNumero],
            ['Client', a.patient], ['Motif', a.motif]],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
              { k: 'Montant hors taxes de l’avoir', v: '− ' + C.money(ht, false) },
              { k: 'TVA (' + TAUX_TVA + ' %)', v: '− ' + C.money(tva, false) },
              { k: 'TOTAL DE L’AVOIR (TTC)', v: '− ' + C.money(a.montant, false) },
            ]),
            el('p.mt-3.text-\\[10px\\]', { text: 'Motif de la rectification : ' + a.motif + (a.observations ? ' — ' + a.observations : '') }),
            el('p.mt-2.text-\\[9px\\].italic.text-slate-600', {
              text: 'Le présent avoir rectifie la facture normalisée ' + a.factureNumero
                + ' et a été transmis au dispositif de facturation électronique. Il vaut régularisation de la TVA correspondante.',
            }),
          ]),
          signatures: [{ role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * JOURNAL DES TRANSACTIONS
   * ======================================================================== */
  global.SIGH.screen('mecef-journal', {
    title: 'Journal des transactions fiscales',
    description: 'Historique horodaté des transmissions, réponses du dispositif et codes de retour.',
    regle: 'Écran en lecture seule. Le journal des transactions fiscales est <strong>immuable</strong> : chaque ligne est certifiée par la machine électronique. Une facture erronée se corrige par un avoir, jamais par modification.',
    render: function (root) {
      var n = normalisees();
      var rows = C.sortBy(n.map(function (f) {
        return {
          id: f.id, date: f.dateTransmission || f.date,
          facture: f.numero, numeroMecef: f.numeroMecef,
          patient: f.patient, montant: f.montantTTC,
          operation: f.reemise ? 'Réémission' : 'Transmission',
          code: f.codeRetour || (f.statutMecef === 'valide' ? 'OK-200' : (f.statutMecef === 'rejete' ? 'E-000' : '—')),
          statut: f.statutMecef,
        };
      }), 'date', 'desc');

      var host = el('div.space-y-4');
      host.appendChild(U.kpiGrid([
        { label: 'Transactions enregistrées', value: C.num(rows.length), icon: 'scroll-text', tone: 'navy' },
        { label: 'Réussies', value: C.num(rows.filter(function (r) { return r.statut === 'valide'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Échouées', value: C.num(rows.filter(function (r) { return r.statut === 'rejete'; }).length), icon: 'x-circle', tone: 'danger' },
        { label: 'Réémissions', value: C.num(rows.filter(function (r) { return r.operation === 'Réémission'; }).length), icon: 'repeat', tone: 'warning' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Journal fiscal', rows: rows, exportName: 'journal-mecef', pageSize: 20,
        filters: [
          { name: 'statut', label: 'Statut', options: [{ value: 'valide', label: 'Réussie' }, { value: 'rejete', label: 'Échouée' }, { value: 'en_attente', label: 'En attente' }] },
          { name: 'operation', label: 'Opération', options: ['Transmission', 'Réémission'] },
        ],
        columns: [
          { key: 'date', label: 'Horodatage', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'facture', label: 'Facture', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.facture }); } },
          { key: 'numeroMecef', label: 'Identifiant MECeF', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.text-slate-500', { text: r.numeroMecef || '—' }); } },
          { key: 'patient', label: 'Client' },
          { key: 'montant', label: 'Montant', align: 'right', text: function (r) { return C.money(r.montant, false); }, render: function (r) { return C.money(r.montant, false); } },
          { key: 'operation', label: 'Opération', render: function (r) { return U.badge(r.operation, r.operation === 'Réémission' ? 'warning' : 'navy'); } },
          {
            key: 'code', label: 'Code de retour',
            render: function (r) {
              return el('span.font-mono.text-xs.font-semibold', {
                class: r.statut === 'valide' ? 'text-success-700' : (r.statut === 'rejete' ? 'text-danger-700' : 'text-slate-500'),
                text: r.code,
              });
            },
          },
          { key: 'statut', label: 'Statut', render: function (r) { return statutBadge(r.statut); } },
        ],
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * CONFIGURATION FISCALE
   * ======================================================================== */
  global.SIGH.screen('mecef-config', {
    title: 'Configuration fiscale',
    description: 'Paramètres d’émission : identifiants légaux, numérotation, taux de TVA et préfixes.',
    regle: 'Ces paramètres alimentent automatiquement toutes les factures normalisées : ils ne doivent jamais être saisis facture par facture.',
    render: function (root) {
      var host = el('div.grid.gap-4.lg\\:grid-cols-2');

      var f = U.form([
        { type: 'section', label: 'Identification légale de l’émetteur' },
        { name: 'raisonSociale', label: 'Raison sociale', required: true, col: 'full', value: C.BRAND.nom },
        { name: 'ifu', label: 'IFU', required: true, value: C.BRAND.ifu },
        { name: 'rccm', label: 'RCCM', required: true, value: C.BRAND.rccm },
        { name: 'autorisation', label: 'N° d’autorisation d’ouverture', col: 'full', value: C.BRAND.autorisation },
        { name: 'adresse', label: 'Adresse', col: 'full', value: C.BRAND.bp },
        { name: 'telephone', label: 'Téléphones', value: C.BRAND.telephones.join(' / ') },
        { name: 'email', label: 'Adresse électronique', value: C.BRAND.email },

        { type: 'section', label: 'Paramètres d’émission' },
        { name: 'prefixeFacture', label: 'Préfixe des factures', value: 'FN-2026-', help: 'La numérotation doit rester strictement séquentielle.' },
        { name: 'prefixeAvoir', label: 'Préfixe des avoirs', value: 'AV-2026-' },
        { name: 'prefixeProforma', label: 'Préfixe des pro-forma', value: 'PRO-2026-' },
        { name: 'prochainNumero', label: 'Prochain numéro', type: 'number', value: normalisees().length + 1 },
        {
          name: 'regimeTva', label: 'Régime de TVA', type: 'select', required: true,
          options: F.regimesTva.map(function (r) { return { value: r.id, label: r.label }; }),
          value: F.regimeTva,
          help: 'Le régime exonéré est celui relevé sur la facture de référence : à confirmer avec le service comptable.',
        },
        { name: 'tauxAib', label: 'Taux d’AIB (%)', type: 'number', value: TAUX_AIB, min: 0, max: 100, help: 'Acompte sur impôt assis sur les bénéfices, prélevé à la source.' },
        { name: 'devise', label: 'Devise', value: C.BRAND.devise, readonly: true },

        { type: 'section', label: 'Transmission' },
        { name: 'modeTransmission', label: 'Mode de transmission', type: 'select', options: ['Automatique à l’émission', 'Manuelle groupée', 'Différée en fin de journée'], value: 'Automatique à l’émission' },
        { name: 'delaiRetransmission', label: 'Délai avant nouvelle tentative (minutes)', type: 'number', value: 15 },
        { name: 'archivageAuto', label: 'Archivage automatique des factures transmises', type: 'checkbox', value: true, col: 'full' },
      ], {});

      var carte = el('div');
      carte.appendChild(U.card('Paramètres fiscaux', el('div', null, [
        f,
        el('div.mt-4.flex.flex-wrap.gap-2', null, [
          /* La configuration fiscale commande TOUTES les factures
             normalisées à venir : elle ne se règle pas depuis un profil qui
             ne fait que consulter la MECeF. */
          K.commande('Enregistrer les paramètres', {
            variant: 'primary', icon: 'save',
            onclick: function () {
              var v = f.collect();
              if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
              S.log('Modification', 'MECEF', 'ConfigurationFiscale', 'CONFIG', null, v);
              U.toast('Paramètres fiscaux enregistrés.', {
                type: 'success',
                detail: 'Ces valeurs alimenteront toutes les prochaines factures normalisées.',
              });
            },
          }),
          K.btn('Tester la connexion au dispositif', {
            icon: 'plug-zap',
            onclick: function () {
              U.toast('Connexion au dispositif fiscal établie.', { type: 'success', detail: 'Temps de réponse : 340 ms' });
            },
          }),
        ]),
      ])));
      host.appendChild(carte);

      /* Aperçu de l'entête fiscale */
      var apercu = el('div.space-y-4');
      apercu.appendChild(U.card('Mentions portées sur chaque facture', U.descList([
        ['Dénomination', C.BRAND.nom],
        ['Adresse', C.BRAND.bp],
        ['Téléphones', C.BRAND.telephones.join(' / ')],
        ['Adresse électronique', C.BRAND.email],
        ['IFU', el('span.font-mono.font-semibold', { text: C.BRAND.ifu })],
        ['RCCM', el('span.font-mono.font-semibold', { text: C.BRAND.rccm })],
        ['Autorisation d’ouverture', C.BRAND.autorisation],
        ['Devise', C.BRAND.devise],
        ['Régime de TVA', REGIME.label],
        ['Taux de TVA appliqué', TAUX_TVA + ' %'],
        ['Acompte AIB', TAUX_AIB + ' % du montant hors taxes'],
      ], 'grid-cols-1')));

      apercu.appendChild(K.note('Le régime <strong>exonéré</strong> est celui relevé sur la facture de référence certifiée MECeF, '
        + 'où la TVA est portée à zéro et le net à payer vaut le hors-taxes augmenté du seul AIB. '
        + 'Ce choix doit être <strong>confirmé par le service comptable</strong> pour les prestations de la clinique.',
        { tone: 'warning', icon: 'help-circle' }));

      apercu.appendChild(U.card('Contrôles automatiques à l’émission', el('div.space-y-2', null, [
        controle('Numérotation strictement séquentielle', true),
        controle('IFU émetteur renseigné', true),
        controle('RCCM renseigné', true),
        controle('Montant de TVA cohérent avec le montant HT', true),
        controle('Identification du client renseignée', true),
        controle('QR code fiscal apposé sur le document', true),
      ])));

      apercu.appendChild(K.note('Le prototype simule les échanges avec le dispositif fiscal. '
        + 'L’interfaçage réel s’effectuera avec la machine électronique certifiée de facturation lors de la mise en œuvre.', { tone: 'info' }));

      host.appendChild(apercu);
      root.appendChild(host);
      return null;

      function controle(libelle, ok) {
        return el('div.flex.items-center.gap-2', null, [
          el('span', { class: ok ? 'text-success-600' : 'text-slate-300' }, C.icon(ok ? 'check-circle-2' : 'circle', 'h-4 w-4')),
          el('span.text-sm.text-slate-700', { text: libelle }),
        ]);
      }
    },
  });
})(window);
