/* =============================================================================
 * M8 — Facturation, Caisse & Facture normalisée
 * -----------------------------------------------------------------------------
 * CDCT §10.7 — facturation des consultations, actes, analyses et médicaments,
 * séparation actes / médicaments, modes de paiement multiples (espèces, TPE,
 * MTN Mobile Money, Moov Money), reliquats, remboursements et annulations,
 * interfaçage avec le stock pour la sortie automatique des produits facturés.
 *
 * RG-02 — médicaments facturés au prix d'achat, sans marge.
 * RG-09 — prise en charge assurance uniquement si la carte est valide.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  /* ==========================================================================
   * LA PART NON ASSURÉE N'EST PAS LA PART PATIENT
   * --------------------------------------------------------------------------
   * La part patient comprend deux choses de nature différente : le ticket
   * modérateur sur des lignes COUVERTES, et l'intégralité des lignes que
   * personne ne couvre. Les confondre empêche d'expliquer au guichet pourquoi
   * telle ligne reste à 100 % à la charge d'un assuré — or c'est exactement la
   * question qu'on y pose tous les jours.
   * ======================================================================== */
  function partNonAssuree(f, lignes) {
    return (lignes || []).reduce(function (n, l) {
      var couverte = (l.partAssureur || 0) > 0;
      if (couverte) return n;
      var montant = l.montant != null ? l.montant
        : l.quantite * (l.prixNet != null ? l.prixNet : l.prixUnitaire);
      return n + (montant || 0);
    }, 0);
  }

  function factures() { return S.collection('factures').active(); }
  function patients() { return S.collection('patients').active(); }
  function produits() { return S.collection('produits').active(); }

  function modeLabel(id) {
    var m = D.MODES_PAIEMENT.filter(function (x) { return x.id === id; })[0];
    return m ? m.label : id;
  }
  /* UNE SEULE VÉRITÉ : la validité se lit au moteur, qui connaît
     l’historique des couvertures. Une copie locale divergerait le jour où
     un assuré changerait de compagnie en cours d’année. */
  function carteValide(p) {
    return PR.carteValide(p, AUJ);
  }
  function duJour(rows) {
    var j = C.iso(AUJ);
    return rows.filter(function (r) { return C.iso(r.date) === j; });
  }
  function duMois(rows) {
    return rows.filter(function (r) {
      var d = C.toDate(r.date);
      return d.getFullYear() === AUJ.getFullYear() && d.getMonth() === AUJ.getMonth();
    });
  }

  /* --- Colonnes réutilisables ---------------------------------------------- */
  var colNumero = {
    key: 'numero', label: 'N° facture', nowrap: true,
    render: function (f) {
      return el('div', null, [
        el('p.font-mono.text-xs.font-semibold.text-navy-800', { text: f.numero }),
        f.numeroMecef ? el('p.font-mono.text-\\[10px\\].text-slate-400', { text: f.numeroMecef }) : null,
      ]);
    },
  };
  var colPatientF = {
    key: 'patient', label: 'Patient',
    render: function (f) {
      return el('div.min-w-0', null, [
        el('p.truncate.text-sm.font-medium.text-slate-800', { text: f.patient }),
        el('p.font-mono.text-xs.text-slate-400', { text: f.patientCode }),
      ]);
    },
  };
  var colDateF = {
    key: 'date', label: 'Date', nowrap: true,
    text: function (f) { return C.dateFR(f.date); },
    render: function (f) { return C.dateFR(f.date); },
  };
  var colMontant = {
    key: 'montantTTC', label: 'Montant', align: 'right',
    text: function (f) { return C.money(f.montantTTC, false); },
    render: function (f) { return el('span.font-semibold', { text: C.money(f.montantTTC, false) }); },
  };
  var colReliquat = {
    key: 'reliquat', label: 'Reste dû', align: 'right',
    text: function (f) { return C.money(f.reliquat, false); },
    render: function (f) {
      return f.reliquat > 0
        ? el('span.font-semibold.text-danger-600', { text: C.money(f.reliquat, false) })
        : el('span.text-xs.text-slate-400', { text: '—' });
    },
  };
  var colStatutPaiement = {
    key: 'statutPaiement', label: 'Règlement',
    render: function (f) { return U.statut(f.statutPaiement); },
  };

  /* --- Détail d'une facture ------------------------------------------------ */
  function detailFacture(f) {
    var p = patients().filter(function (x) { return x.id === f.patientId; })[0];
    var wrap = el('div.space-y-4');

    wrap.appendChild(U.kpiGrid([
      { label: 'Montant total', value: C.money(f.montantTTC), icon: 'receipt', tone: 'navy' },
      { label: 'Reste à payer', value: C.money(f.reliquat), icon: 'wallet', tone: f.reliquat > 0 ? 'danger' : 'success' },
    ], 'grid-cols-2'));

    wrap.appendChild(U.descList([
      ['N° facture', el('span.font-mono', { text: f.numero })],
      ['N° MECeF', f.numeroMecef ? el('span.font-mono', { text: f.numeroMecef }) : U.badge('Non transmise', 'warning')],
      ['Date', C.dateFR(f.date)],
      ['Patient', f.patient], ['Dossier', el('span.font-mono', { text: f.patientCode })],
      ['Nature', f.type],
      ['Montant HT', C.money(f.montantHT)],
      ['Montant TTC', C.money(f.montantTTC)],
      ['Part assurance', f.assureur ? C.money(f.partAssurance) + ' (' + f.tauxPriseEnCharge + ' %)' : 'Sans objet'],
      ['Part patient', C.money(f.partPatient)],
      ['Montant réglé', C.money(f.montantPaye)],
      ['Mode de règlement', modeLabel(f.modePaiement)],
      ['Statut', U.statut(f.statutPaiement)],
    ]));

    if (f.assureur) {
      wrap.appendChild(carteValide(p)
        ? K.note('<strong>RG-09</strong> — carte ' + f.assureur + ' valide jusqu’au ' + C.dateFR(p.carteExpiration)
          + ' : prise en charge de ' + f.tauxPriseEnCharge + ' % appliquée.', { tone: 'success', icon: 'shield-check' })
        : K.note('<strong>RG-09</strong> — carte d’assurance expirée : la facturation aurait dû être intégrale au patient. À régulariser.', { tone: 'danger', icon: 'shield-alert' }));
    }

    if (f.lignes && f.lignes.length) {
      wrap.appendChild(U.card('Détail des prestations', K.miniTable([
        { label: 'Désignation', key: 'designation' },
        { label: 'Quantité', align: 'right', key: 'quantite' },
        { label: 'P.U.', align: 'right', render: function (l) { return C.money(l.prixUnitaire, false); } },
        { label: 'Montant', align: 'right', render: function (l) { return C.money(l.quantite * l.prixUnitaire, false); } },
      ], f.lignes)));
    }
    return wrap;
  }

  /* --- Facture normalisée imprimable --------------------------------------- */
  /* --------------------------------------------------------------------------
   * Catégorie de garantie d'une ligne — c'est elle qui décide du taux appliqué.
   * Le barème distingue les frais pharmaceutiques (80 %) des vitamines (60 %),
   * et la consultation généraliste de la spécialiste : la nature saisie à la
   * caisse ne suffit pas, il faut regarder ce qui est vendu.
   * ----------------------------------------------------------------------- */
  function categorieDe(nature, designation, article) {
    if (nature === 'analyse') return 'analyse';
    if (nature === 'hospitalisation') return 'hospitalisation';
    if (nature === 'medicament') {
      return /vitamin|fortifiant/i.test(designation || '') ? 'vitamine' : 'medicament';
    }
    if (nature === 'acte' && article && article.secteur) {
      var s = article.secteur;
      if (/Imagerie/i.test(s)) return 'imagerie';
      if (/Maternité/i.test(s)) return 'maternite';
      if (/Chirurgie/i.test(s)) return /[Cc]onsultation/.test(designation) ? 'consultation' : 'chirurgie';
      if (/Hospitalisation/i.test(s)) return 'hospitalisation';
      if (/Médecine générale/i.test(s)) return /[Cc]ertificat/.test(designation) ? 'certificat' : 'consultation';
      if (/Soins/i.test(s)) return 'soin';
    }
    if (/consultation/i.test(designation || '')) return 'consultation';
    if (/ambulance/i.test(designation || '')) return 'ambulance';
    return 'autre';
  }

  function etatFacture(f, options) {
    var o = options || {};
    var p = patients().filter(function (x) { return x.id === f.patientId; })[0];
    var lignes = f.lignes && f.lignes.length ? f.lignes : [{
      designation: 'Prestation — ' + f.type, quantite: 1, prixUnitaire: f.montantTTC,
    }];

        var avecRemise = lignes.some(function (l) { return l.remiseUnitaire; });
    var avecAssurance = lignes.some(function (l) { return l.partAssureur; }) || !!f.assureur;

    var colonnes = [
      { label: 'Référence', value: function (l) { return l.produitId || l.nature || '—'; } },
      { label: 'Désignation', key: 'designation' },
      { label: 'Qté', key: 'quantite', align: 'right', somme: true,
        formatTotal: function (v) { return String(v); } },
      { label: 'P.U', align: 'right', value: function (l) { return C.money(l.prixUnitaire, false); } },
    ];
    if (avecRemise) {
      colonnes.push({ label: 'Remise', align: 'right', value: function (l) { return l.remiseUnitaire ? C.money(l.remiseUnitaire, false) : '—'; } });
      colonnes.push({ label: 'P.U net', align: 'right', value: function (l) { return C.money(l.prixNet != null ? l.prixNet : l.prixUnitaire, false); } });
    }
    if (avecAssurance) {
      colonnes.push({
        label: 'Part ass.', align: 'right', somme: function (l) { return l.partAssureur || 0; },
        value: function (l) { return C.money(l.partAssureur || 0, false); },
      });
      colonnes.push({
        label: 'Part pat.', align: 'right',
        somme: function (l) {
          return l.partPatient != null ? l.partPatient
            : (l.quantite * (l.prixNet != null ? l.prixNet : l.prixUnitaire));
        },
        value: function (l) { return C.money(l.partPatient != null ? l.partPatient : (l.quantite * (l.prixNet != null ? l.prixNet : l.prixUnitaire)), false); },
      });
    }
    colonnes.push({
      label: 'Montant', align: 'right',
      /* Le total est refait depuis les lignes imprimées : il ne peut plus
         diverger de ce que la facture montre. */
      somme: function (l) { return l.montant != null ? l.montant : l.quantite * l.prixUnitaire; },
      value: function (l) { return C.money(l.montant != null ? l.montant : l.quantite * l.prixUnitaire, false); },
    });

    var contenu = el('div.space-y-3');
    if (f.libelleVolet) {
      contenu.appendChild(el('p.mb-2.border-l-4.border-navy-700.bg-slate-50.px-3.py-1.5.text-[10px].font-semibold.text-navy-900', {
        text: f.libelleVolet + (o.jumelle ? ' — pièce jumelle : ' + o.jumelle.numero : ''),
      }));
    }
    contenu.appendChild(P.tableau(colonnes, lignes, { total: true }));

    /* Répartition patient / assureur */
    var rep = el('div.mt-4.ml-auto.w-2\\/3');
    rep.appendChild(P.tableau([
      { label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' },
    ], [
      { k: 'Montant brut', v: C.money(f.montantTTC + (f.montantRemises || 0), false) },
      f.montantRemises ? { k: 'Remises accordées', v: '- ' + C.money(f.montantRemises, false) } : null,
      { k: 'Montant total de la facture', v: C.money(f.montantTTC, false) },
      f.assureur ? { k: 'Part assureur ' + f.assureur + (f.souscripteur ? ' — ' + f.souscripteur : ''), v: C.money(f.partAssurance, false) } : null,
      { k: 'Part à la charge du patient', v: C.money(f.partPatient, false) },
      /* La part NON ASSURÉE est celle qu'aucune compagnie ne couvre — actes
         exclus, certificats hors SOS, planification familiale. Elle se
         distingue du ticket modérateur, qui porte sur des lignes couvertes :
         les confondre empêcherait d'expliquer au guichet pourquoi telle ligne
         est intégralement à la charge du patient. */
      { k: 'dont part NON ASSURÉE (aucune couverture)', v: C.money(partNonAssuree(f, lignes), false) },
      { k: 'TOTAL DÛ', v: C.money(f.reliquat != null ? f.reliquat : f.partPatient, false) },
      { k: 'Montant réglé', v: C.money(f.montantPaye, false) },
      { k: 'Reste à payer', v: C.money(f.reliquat, false) },
      { k: 'Base normalisée MECeF', v: C.money(f.baseMecef != null ? f.baseMecef : f.montantPaye, false) },
    ].filter(Boolean)));
    contenu.appendChild(rep);

    /* Mention relevée à l'identique sur les factures réellement émises. */
    contenu.appendChild(el('p.mt-4.text-\\[10px\\].font-semibold.text-slate-800', {
      text: C.BRAND.formuleArrete + ' : ' + C.montantEnLettres(f.partPatient) + '.',
    }));

    contenu.appendChild(el('p.mt-4.text-\\[9px\\].leading-relaxed.text-slate-600', {
      text: o.proforma
        ? 'Facture pro-forma — document non fiscal, établi à titre d’estimation. Elle ne vaut pas facture normalisée et ne peut servir de justificatif comptable.'
        : 'Facture normalisée conforme au dispositif de facturation électronique en vigueur en République du Bénin. '
          + 'Mode de règlement : ' + modeLabel(f.modePaiement) + '.',
    }));

    if (!o.proforma && f.numeroMecef) {
      contenu.appendChild(el('div.mt-3.flex.items-center.gap-3.rounded.border.border-slate-300.p-2', null, [
        el('div.grid.h-16.w-16.shrink-0.place-items-center.border.border-slate-400.text-\\[8px\\].text-slate-400', { text: 'QR MECeF' }),
        el('div', null, [
          el('p.text-\\[9px\\].font-semibold', { text: 'Identifiant fiscal MECeF : ' + f.numeroMecef }),
          el('p.text-\\[9px\\]', { text: 'IFU : ' + C.BRAND.ifu + ' — RCCM : ' + C.BRAND.rccm }),
          el('p.text-\\[9px\\]', { text: 'Statut de transmission : ' + (f.statutMecef === 'valide' ? 'validée par l’administration fiscale' : f.statutMecef) }),
        ]),
      ]));
    }

    contenu.appendChild(el('p.mt-4.text-center.text-\[11px\].font-bold.tracking-wide.text-navy-900', {
      text: C.BRAND.formulePolitesse,
    }));

    P.etat({
      titre: o.proforma ? 'Facture pro-forma' : 'Facture normalisée',
      sousTitre: f.numero + (f.numeroMecef && !o.proforma ? ' — ' + f.numeroMecef : ''),
      filigrane: o.proforma ? 'Pro-forma' : null,
      cartouche: [
        ['Facture n°', f.numero],
        ['Date', C.dateFR(f.date)],
        ['Patient', f.patient],
        ['Dossier', f.operationDissociee ? 'opération détachée du dossier' : (f.patientCode || '—')],
        ['Nature', f.type],
        ['Assurance', f.assureur ? f.assureur + (f.souscripteur ? ' — ' + f.souscripteur : '') : 'Aucune'],
        ['N° de police', f.numeroPolice || '—'],
        /* Les pièces de caisse portent l'autre RCCM (relevé sur les factures réelles). */
        ['RCCM', C.BRAND.rccm],
      ],
      contenu: contenu,
      /* Pas de signature patient sur une pièce de caisse : c'est la caisse
         qui atteste l'encaissement. */
      signatures: [{ role: 'Le Caissier', mention: 'Signature et cachet' }],
    });
  }

  /* ==========================================================================
   * TABLEAU DE BORD FACTURATION
   * ======================================================================== */
  global.SIGH.screen('m8-dashboard', {
    title: 'Tableau de bord — Facturation & Caisse',
    description: 'Chiffre d’affaires, encaissements, reliquats, répartition des règlements et recettes par activité.',
    render: K.dash({
      kpis: function () {
        var f = factures(), fj = duJour(f), fm = duMois(f);
        return [
          { label: 'Chiffre d’affaires du jour', value: C.money(C.sum(fj, 'montantTTC')), icon: 'trending-up', tone: 'navy' },
          { label: 'Encaissé aujourd’hui', value: C.money(C.sum(fj, 'montantPaye')), icon: 'banknote', tone: 'success' },
          { label: 'Chiffre d’affaires du mois', value: C.money(C.sum(fm, 'montantTTC')), icon: 'calendar', tone: 'info', delta: 8.4 },
          { label: 'Encaissé sur le mois', value: C.money(C.sum(fm, 'montantPaye')), icon: 'wallet', tone: 'success' },
          { label: 'Nombre de factures', value: C.num(f.length), icon: 'receipt', tone: 'neutral' },
          { label: 'Reliquats en cours', value: C.money(C.sum(f, 'reliquat')), icon: 'hand-coins', tone: 'warning' },
          { label: 'Factures impayées', value: C.num(f.filter(function (x) { return x.statutPaiement === 'impayee'; }).length), icon: 'file-x', tone: 'danger' },
          { label: 'Part assurance à recouvrer', value: C.money(C.sum(f.filter(function (x) { return x.assureur; }), 'partAssurance')), icon: 'shield-check', tone: 'info' },
        ];
      },
      sections: [
        {
          render: function () {
            return K.charts([
              {
                title: 'Évolution du chiffre d’affaires (12 mois)',
                render: function () {
                  var fa = K.parMois(factures(), 'date', 'montantTTC');
                  var en = K.parMois(factures(), 'date', 'montantPaye');
                  return G.ligne(fa.labels, [
                    { label: 'Facturé', data: fa.data, color: G.TONES.navy },
                    { label: 'Encaissé', data: en.data, color: G.TONES.vert },
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
                title: 'Répartition des modes de paiement',
                render: function () {
                  var g = C.groupBy(factures(), 'modePaiement');
                  var keys = Object.keys(g);
                  return G.barres(keys.map(modeLabel),
                    [{ label: 'Montant encaissé', data: keys.map(function (k) { return C.sum(g[k], 'montantPaye'); }) }],
                    { horizontal: true, height: 260 });
                },
              },
              {
                title: 'Factures par jour (mois en cours)',
                render: function () {
                  var jours = [], data = [];
                  for (var d = 1; d <= AUJ.getDate(); d++) {
                    var jour = new Date(AUJ.getFullYear(), AUJ.getMonth(), d);
                    jours.push(String(d));
                    data.push(factures().filter(function (f) { return C.iso(f.date) === C.iso(jour); }).length);
                  }
                  return G.barres(jours, [{ label: 'Factures', data: data, color: G.TONES.bleu }]);
                },
              },
            ]);
          },
        },
        {
          title: 'Dernières factures',
          actions: function () { return [K.lien('m8-factures', 'Toutes les factures', { size: 'sm', icon: 'arrow-right' })]; },
          render: function () {
            return K.miniTable([
              { label: 'N°', render: function (f) { return el('span.font-mono.text-xs', { text: f.numero }); } },
              { label: 'Date', render: function (f) { return C.dateFR(f.date); } },
              { label: 'Patient', key: 'patient' },
              { label: 'Nature', key: 'type' },
              { label: 'Montant', align: 'right', render: function (f) { return C.money(f.montantTTC, false); } },
              { label: 'Réglé', align: 'right', render: function (f) { return C.money(f.montantPaye, false); } },
              { label: 'Statut', render: function (f) { return U.statut(f.statutPaiement); } },
            ], factures().slice(0, 10));
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm8-facturation', icon: 'file-plus', label: 'Nouvelle facture', detail: 'Actes, analyses, médicaments' },
              { id: 'm8-paiements', icon: 'banknote', label: 'Encaisser', detail: 'Espèces, TPE, Mobile Money' },
              { id: 'm8-reliquats', icon: 'hand-coins', label: 'Reliquats', detail: 'Règlements différés' },
              { id: 'm8-caisse', icon: 'printer', label: 'État de caisse', detail: 'Arrêté journalier' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * NOUVELLE FACTURE
   * ======================================================================== */
  global.SIGH.screen('m8-facturation', {
    title: 'Nouvelle facture',
    description: 'Établissement d’une facture : sélection du patient, ajout des prestations et médicaments, calcul de la prise en charge et encaissement.',
    regle: '<strong>RG-02</strong> — les médicaments sont ajoutés au prix d’achat, sans marge. '
      + '<strong>RG-09</strong> — la prise en charge assurance n’est appliquée que si la carte est valide à la date de facturation.',
    render: function (root) {
      var pats = C.sortBy(patients(), 'code');
      var lignes = [];
      var patientCourant = pats[0];

      var host = el('div.grid.gap-4.lg\\:grid-cols-3');
      var principal = el('div.space-y-4.lg\\:col-span-2');
      var lateral = el('div.space-y-4');

      /* --- Patient --- */
      var selPatient = U.combo(pats.map(function (p) {
        return {
          value: p.id, label: p.nom + ' ' + p.prenom, icon: 'user',
          detail: p.code + (p.assureurNom ? ' — ' + p.assureurNom : ' — non assuré'),
        };
      }), {
        value: pats.length ? pats[0].id : '',
        searchPlaceholder: 'Nom, prénom ou code CNT…',
        placeholder: 'Choisir un patient',
      });
      var infoAssurance = el('div');
      selPatient.addEventListener('change', function () {
        patientCourant = pats.filter(function (p) { return p.id === selPatient.value; })[0];
        majAssurance(); majTotaux();
      });

      /* La nature de la facture vient du référentiel administrable : la liste
         écrite en dur ignorait la Maternité et la Mise en observation, deux
         activités facturées tous les jours. */
      var colNat = S.collection('naturesFacture', { module: 'CFG', entite: 'nature de facture' });
      function optionsNatures() {
        return C.sortBy(colNat.active(), 'ordre').map(function (n) {
          return { value: n.libelle, label: n.libelle, detail: n.secteur };
        });
      }
      var selType = U.combo(optionsNatures(), { placeholder: '— Nature de la facture —' });
      if (optionsNatures().length) selType.value = optionsNatures()[0].value;

      /* Libellé distinct du bouton « Ajouter » des lignes de facture : deux
         commandes homonymes sur le même écran, c'est une hésitation garantie. */
      var ajouterNature = K.commande('Nouvelle nature', {
        size: 'sm', icon: 'plus', title: 'Créer une nature de facture sans quitter l’écran',
        onclick: function () {
          var f = U.form([
            { name: 'libelle', label: 'Nature de la facture', required: true, col: 'full' },
            { name: 'secteur', label: 'Secteur émetteur', type: 'select', required: true, options: D.SECTEURS_ACTIVITE },
          ], {});
          var m = U.modal({
            title: 'Nouvelle nature de facture', size: 'md', body: f,
            footer: [
              K.btn('Annuler', { onclick: function () { m.close(); } }),
              K.btn('Créer', {
                variant: 'primary', icon: 'plus',
                onclick: function () {
                  var v = f.collect();
                  if (!v) return;
                  v.code = (v.libelle || 'NAT').slice(0, 4).toUpperCase();
                  v.ordre = colNat.all().length + 1;
                  v.source = 'Créée depuis l’émission de facture';
                  var res = colNat.insert(v);
                  m.close();
                  /* Un combo n'est pas un <select> : on renouvelle ses entrées
                     par setOptions, puis on choisit la nouvelle. */
                  selType.setOptions(optionsNatures(), true);
                  selType.value = res.record.libelle;
                  U.toast('Nature « ' + res.record.libelle + ' » créée et sélectionnée.', {
                    type: 'success', detail: 'Elle est désormais proposée à toute la caisse.',
                  });
                },
              }),
            ],
          });
        },
      });

      principal.appendChild(U.card('Patient et nature de la facture', el('div.space-y-3', null, [
        el('div.grid.gap-3.sm\\:grid-cols-2', null, [
          el('div', null, [el('label.label', { text: 'Patient' }), selPatient]),
          el('div', null, [
            el('label.label', { text: 'Nature de la facture' }),
            el('div.flex.items-center.gap-2', null, [el('div.min-w-0.flex-1', null, selType), ajouterNature]),
          ]),
        ]),
        infoAssurance,
      ])));

      function majAssurance() {
        C.clear(infoAssurance);
        if (!patientCourant) return;
        if (!patientCourant.assureur) {
          infoAssurance.appendChild(K.note('Patient <strong>non assuré</strong> : la facturation est intégrale à sa charge.', { tone: 'info' }));
        } else if (carteValide(patientCourant)) {
          infoAssurance.appendChild(K.note('Couverture <strong>' + patientCourant.assureurNom + '</strong> — prise en charge <strong>'
            + patientCourant.tauxPriseEnCharge + ' %</strong>. Carte valide jusqu’au ' + C.dateFR(patientCourant.carteExpiration) + '.',
            { tone: 'success', icon: 'shield-check' }));
        } else {
          infoAssurance.appendChild(K.note('<strong>RG-09 — carte expirée</strong> le ' + C.dateFR(patientCourant.carteExpiration)
            + '. La prise en charge ne peut pas être appliquée : la facturation est intégrale au patient.',
            { tone: 'danger', icon: 'shield-alert' }));
        }
        U.icons(infoAssurance);
      }

      /* --- Ajout de lignes --- */
      var ajout = el('div.space-y-3');
      var wrapArticle = null, wrapLibre = null;
      var selNature = el('select.select');
      [['acte', 'Acte / consultation'], ['analyse', 'Analyse de laboratoire'], ['medicament', 'Médicament'], ['hospitalisation', 'Journée d’hospitalisation'], ['libre', 'Ligne libre']]
        .forEach(function (n) { selNature.appendChild(el('option', { value: n[0] }, n[1])); });

      var selArticle = U.combo([], {
        searchPlaceholder: 'Prestation, analyse ou médicament…',
        placeholder: 'Choisir une prestation',
      });
      var champLibre = el('input.input', { type: 'text', placeholder: 'Désignation de la prestation' });
      var qte = el('input.input.w-24', { type: 'number', min: 1, value: 1 });
      var pu = el('input.input.w-32', { type: 'number', min: 0, value: 0 });
      /* Remises personnel et client : les pièces réelles les portent ligne par
         ligne, en colonnes REMISE et P.U NET (facture 19727). */
      var remise = el('input.input.w-24', { type: 'number', min: 0, value: 0 });
      var typeRemise = el('select.select.w-28');
      [['pct', '%'], ['montant', 'FCFA']].forEach(function (t) {
        typeRemise.appendChild(el('option', { value: t[0] }, t[1]));
      });
      var motifRemise = el('select.select.w-40');
      [['', 'Sans remise'], ['personnel', 'Remise personnel'], ['client', 'Remise client'], ['direction', 'Geste commercial']]
        .forEach(function (t) { motifRemise.appendChild(el('option', { value: t[0] }, t[1])); });

      function remplirArticles() {
        var nature = selNature.value;
        var liste = [];
        if (nature === 'acte') {
          /* Catalogue administrable (vague 1) : la liste écrite en dur portait
             des tarifs qu'aucun document de la clinique ne justifiait. */
          liste = S.collection('actes').active()
            .filter(function (a) { return a.prix != null; })
            .map(function (a) {
              return { label: a.libelle, prix: a.prix, code: a.code, secteur: a.secteur };
            });
          if (!liste.length) {
            liste = [{ label: 'Aucun acte tarifé — voir le référentiel tarifaire', prix: 0 }];
          }
        } else if (nature === 'analyse') {
          liste = D.ANALYSES.map(function (a) { return { label: a.designation, prix: a.prix }; });
        } else if (nature === 'medicament') {
          liste = produits().filter(function (p) { return p.stockDetail > 0; })
            .map(function (p) { return { label: p.designation + ' (' + p.stockDetail + ' ' + p.unite + ')', prix: p.prixVente, produitId: p.id }; });
        } else if (nature === 'hospitalisation') {
          liste = D.TYPES_CHAMBRE.map(function (t) { return { label: 'Journée — chambre ' + t.label, prix: t.tarif }; });
        }
        selArticle.setOptions(liste.map(function (x, i) {
          return { value: String(i), label: x.label, detail: C.money(x.prix, false) };
        }));
        if (liste.length) selArticle.value = '0';
        selArticle._liste = liste;
        var visible = nature !== 'libre';
        if (wrapArticle) wrapArticle.hidden = !visible;
        if (wrapLibre) wrapLibre.hidden = visible;
        if (visible && liste.length) pu.value = liste[0].prix;
      }
      selNature.addEventListener('change', remplirArticles);
      selArticle.addEventListener('change', function () {
        var x = (selArticle._liste || [])[Number(selArticle.value)];
        if (x) pu.value = x.prix;
      });

      wrapArticle = el('div.min-w-\\[16rem\\].flex-1', null, [el('label.label', { text: 'Prestation' }), selArticle]);
      wrapLibre = el('div.min-w-\\[16rem\\].flex-1', { hidden: true }, [el('label.label', { text: 'Désignation' }), champLibre]);

      /* Une rangée unique, qui défile horizontalement plutôt que de se replier :
         Nature · Prestation · Qté · P.U. · Remise · Motif · Ajouter forment une
         SEULE saisie, et la replier sur trois lignes le fait oublier. Le
         défilement porte sur le bloc, pas sur la page. */
      ajout.appendChild(el('div.overflow-x-auto.pb-1', null,
        el('div.flex.w-max.min-w-full.items-end.gap-2', null, [
        el('div.min-w-\\[11rem\\]', null, [el('label.label', { text: 'Nature' }), selNature]),
        wrapArticle, wrapLibre,
        el('div.w-20', null, [el('label.label', { text: 'Qté' }), qte]),
        el('div', null, [el('label.label', { text: 'Prix unitaire' }), pu]),
        el('div', null, [el('label.label', { text: 'Remise' }), el('div.flex.gap-1', null, [remise, typeRemise])]),
        el('div', null, [el('label.label', { text: 'Motif de remise' }), motifRemise]),
        K.commande('Ajouter', {
          variant: 'primary', icon: 'plus',
          onclick: function () {
            var nature = selNature.value;
            var designation, produitId = null;
            if (nature === 'libre') {
              designation = champLibre.value.trim();
              if (!designation) { U.toast('Saisir une désignation.', { type: 'error' }); return; }
            } else {
              var x = (selArticle._liste || [])[Number(selArticle.value)];
              if (!x) { U.toast('Sélectionner une prestation.', { type: 'error' }); return; }
              designation = x.label; produitId = x.produitId || null;
            }
            var q = Number(qte.value) || 0, prix = Number(pu.value) || 0;
            if (q <= 0) { U.toast('La quantité doit être positive.', { type: 'error' }); return; }
            if (produitId) {
              var p = produits().filter(function (pp) { return pp.id === produitId; })[0];
              var deja = C.sum(lignes.filter(function (l) { return l.produitId === produitId; }), 'quantite');
              if (p && q + deja > p.stockDetail) {
                U.toast('RG-03 — stock insuffisant en pharmacie (' + p.stockDetail + ' disponibles).', { type: 'error' });
                return;
              }
            }
            var rem = Number(remise.value) || 0;
            var remiseMontant = typeRemise.value === 'pct'
              ? Math.round(prix * Math.min(rem, 100) / 100)
              : Math.min(rem, prix);
            lignes.push({
              nature: nature, designation: designation, quantite: q,
              prixUnitaire: prix, produitId: produitId,
              /* Colonnes REMISE et P.U NET des pièces réelles. */
              remisePct: typeRemise.value === 'pct' ? Math.min(rem, 100) : null,
              remiseUnitaire: remiseMontant,
              motifRemise: motifRemise.value || null,
              prixNet: prix - remiseMontant,
              /* Catégorie de garantie : c'est elle qui décide du taux appliqué. */
              categorie: categorieDe(nature, designation, x),
            });
            qte.value = 1; champLibre.value = ''; remise.value = 0;
            majLignes(); majTotaux();
          },
        }),
      ])));

      var lignesHost = el('div');
      ajout.appendChild(lignesHost);
      principal.appendChild(U.card('Prestations facturées', ajout));

      function majLignes() {
        C.clear(lignesHost);
        if (!lignes.length) { lignesHost.appendChild(U.empty('Aucune prestation ajoutée.', { icon: 'receipt' })); U.icons(lignesHost); return; }
        var t = totaux();
        var tbl = el('table.tbl');
        tbl.appendChild(el('thead', null, el('tr', null, [
          el('th', { text: 'Désignation' }),
          el('th.text-right', { text: 'Qté' }), el('th.text-right', { text: 'P.U.' }),
          el('th.text-right', { text: 'Remise' }), el('th.text-right', { text: 'P.U net' }),
          el('th.text-right', { text: 'Montant' }),
          el('th.text-right', { text: 'Part ass.' }), el('th.text-right', { text: 'Part pat.' }),
          el('th'),
        ])));
        var tb = el('tbody');
        var labels = { acte: 'Acte', analyse: 'Analyse', medicament: 'Médicament', hospitalisation: 'Hospitalisation', libre: 'Divers' };
        lignes.forEach(function (l, i) {
          var d = t.detail[i] || {};
          var net = l.prixNet != null ? l.prixNet : l.prixUnitaire;
          tb.appendChild(el('tr', null, [
            el('td', null, el('div.min-w-0', null, [
              el('p.text-sm.text-slate-800', { text: l.designation }),
              el('p.text-xs.text-slate-400', {
                text: (labels[l.nature] || l.nature)
                  + (l.motifRemise ? ' · remise ' + l.motifRemise : '')
                  + (d.motif ? ' · ' + d.motif : ''),
              }),
            ])),
            el('td.text-right.num', { text: C.num(l.quantite) }),
            el('td.text-right.num', { text: C.money(l.prixUnitaire, false) }),
            el('td.text-right.num', {
              class: l.remiseUnitaire ? 'text-warning-700' : 'text-slate-300',
              text: l.remiseUnitaire ? '- ' + C.money(l.remiseUnitaire, false) + (l.remisePct ? ' (' + l.remisePct + ' %)' : '') : '—',
            }),
            el('td.text-right.num', { text: C.money(net, false) }),
            el('td.text-right.num.font-semibold', { text: C.money(l.quantite * net, false) }),
            el('td.text-right.num', {
              class: d.partAssureur ? 'text-info-600' : 'text-slate-300',
              text: d.partAssureur ? C.money(d.partAssureur, false) : '—',
            }),
            el('td.text-right.num.font-semibold', { text: C.money(d.partPatient != null ? d.partPatient : l.quantite * net, false) }),
            el('td.text-right', null, K.iconBtn('x', 'Retirer', function () { lignes.splice(i, 1); majLignes(); majTotaux(); }, 'ghost')),
          ]));
        });
        tbl.appendChild(tb);
        lignesHost.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, tbl));
        U.icons(lignesHost);
      }

      /* --- Totaux et règlement --- */
      var totauxHost = el('div');
      var selMode = el('select.select');
      D.MODES_PAIEMENT.slice(0, 4).forEach(function (m) { selMode.appendChild(el('option', { value: m.id }, m.label)); });
      var montantRegle = el('input.input', { type: 'number', min: 0, value: 0 });
      /* Le cahier de charge le demande expressément : « dissocier l'opération de
         caisse du numéro de dossier du patient » — vente au comptoir. */
      var dissocier = el('input.checkbox', { type: 'checkbox', id: 'f_dissocier' });

      lateral.appendChild(U.card('Récapitulatif', el('div.space-y-3', null, [
        totauxHost,
        el('div', null, [el('label.label', { text: 'Mode de règlement' }), selMode]),
        el('div', null, [el('label.label', { text: 'Montant réglé (FCFA)' }), montantRegle]),
        el('label.flex.cursor-pointer.items-start.gap-2', { for: 'f_dissocier' }, [
          dissocier,
          el('span.text-xs.text-slate-600', { text: 'Opération de caisse détachée du dossier patient (vente au comptoir)' }),
        ]),
      ])));

      /* La répartition n'est plus un taux unique appliqué au total : le moteur
         de prise en charge traite chaque ligne selon sa catégorie, son plafond,
         les exclusions de la convention et la validité de la carte (RG-09). */
      function totaux() {
        var base = lignes.map(function (l) {
          return {
            libelle: l.designation, categorie: l.categorie || 'autre',
            montant: l.quantite * (l.prixNet != null ? l.prixNet : l.prixUnitaire),
          };
        });
        var r = PR.repartir(patientCourant, base, { date: C.iso(AUJ) });
        var brut = C.sum(lignes, function (l) { return l.quantite * l.prixUnitaire; });
        var remises = C.sum(lignes, function (l) { return l.quantite * (l.remiseUnitaire || 0); });
        return {
          brut: brut, remises: remises,
          total: r.total, partAssurance: r.partAssureur, partPatient: r.partPatient,
          detail: r.lignes, carteValide: r.carteValide, grilleSaisie: r.grilleSaisie,
          souscripteur: r.souscripteur,
          /* La part NON ASSURÉE : les lignes qu'aucune compagnie ne couvre.
             Elle se distingue du ticket modérateur, qui porte sur des lignes
             couvertes — c'est elle qui explique au guichet pourquoi un assuré
             règle intégralement certaines prestations. */
          partNonAssuree: (r.lignes || []).reduce(function (n, l) {
            return n + ((l.partAssureur || 0) > 0 ? 0 : (l.montant || 0));
          }, 0),
        };
      }

      function majTotaux() {
        var t = totaux();
        C.clear(totauxHost);
        var lignesT = [
          ['Total brut des prestations', C.money(t.brut)],
          t.remises ? ['Remises accordées', '− ' + C.money(t.remises)] : null,
          ['Total facturé', C.money(t.total)],
          t.partAssurance ? ['Part assureur', '− ' + C.money(t.partAssurance)] : null,
          ['Part à la charge du patient', C.money(t.partPatient)],
        ].filter(Boolean);
        lignesT.forEach(function (x, i) {
          totauxHost.appendChild(el('div.flex.items-baseline.justify-between.gap-3.py-1.5', {
            class: i === lignesT.length - 1 ? 'border-t border-slate-200 pt-2.5 mt-1' : '',
          }, [
            el('span', { class: i === lignesT.length - 1 ? 'text-sm font-semibold text-slate-800' : 'text-xs text-slate-500', text: x[0] }),
            el('span.num', { class: i === lignesT.length - 1 ? 'text-base font-bold text-navy-900' : 'text-sm text-slate-700', text: x[1] }),
          ]));
        });
        /* Point fiscal du dossier : la MECeF ne porte que la part réglée par le
           patient. Ni la part assureur ni les remises n'y entrent. */
        totauxHost.appendChild(K.note('<strong>Base MECeF : ' + C.money(t.partPatient) + '</strong> — '
          + 'seule la part réglée par le patient est normalisée. '
          + (t.partAssurance ? 'La part assureur (' + C.money(t.partAssurance) + ') ' : '')
          + (t.partAssurance && t.remises ? 'et les remises (' + C.money(t.remises) + ') en sont ' : (t.remises ? 'Les remises (' + C.money(t.remises) + ') en sont ' : ''))
          + (t.partAssurance || t.remises ? 'exclues.' : ''), { tone: 'info', icon: 'landmark' }));
        montantRegle.value = t.partPatient;
      }

      var actions = el('div.flex.flex-wrap.gap-2');
      /* Émettre une facture est une ÉCRITURE : le profil qui ne fait que lire
         la caisse — le magasinier, l'assistant de direction — voit l'écran
         sans se voir offrir de l'alimenter. L'aperçu et le ticket, eux,
         restent : ils n'écrivent rien. */
      C.append(actions, K.commande('Enregistrer et encaisser', {
        variant: 'primary', icon: 'check',
        onclick: function () { enregistrer(false); },
      }));
      C.append(actions, K.commande('Facture pro-forma', { icon: 'file-text', onclick: function () { enregistrer(true); } }));
      /* La caisse imprime sur rouleau : gabarit distinct du A4 (ticket 22118). */
      actions.appendChild(K.btn('Ticket de caisse', { icon: 'receipt', onclick: apercuTicket }));
      lateral.appendChild(U.card('Actions', actions));

      lateral.appendChild(U.card('Rappels', el('div.space-y-2', null, [
        K.note('<strong>RG-02</strong> — médicaments au prix d’achat, sans marge.', { tone: 'info' }),
        K.note('<strong>RG-09</strong> — prise en charge uniquement si la carte est valide.', { tone: 'warning', icon: 'shield-alert' }),
        K.note('La sortie de stock des médicaments facturés est automatique (module M6).', { tone: 'info', icon: 'package' }),
      ])));

      host.appendChild(principal);
      host.appendChild(lateral);
      root.appendChild(host);

      remplirArticles();
      majAssurance(); majLignes(); majTotaux();
      return null;

      /* ----------------------------------------------------------------------
       * Enregistrement — une facture pour un patient non assuré, DEUX pour un
       * assuré : la Direction veut voir séparément ce que l'assureur couvre et
       * ce qu'il ne couvre pas, chacun étant réglé par une partie différente.
       * -------------------------------------------------------------------- */
      /* Aperçu du ticket rouleau tel que la caisse l'imprime. */
      function apercuTicket() {
        if (!lignes.length) { U.toast('Ajouter au moins une prestation.', { type: 'error' }); return; }
        var t = totaux();
        P.ticket({
          titre: 'Ticket de caisse',
          numero: 'T-' + C.pad(factures().length + 1, 5),
          typeVente: t.partAssurance ? 'ASSURANCE' : 'COMPTANT',
          operateur: S.currentUser(),
          assureur: t.partAssurance ? patientCourant.assureurNom : null,
          assure: t.partAssurance ? patientCourant.nom + ' ' + patientCourant.prenom : null,
          dossier: dissocier.checked ? null : patientCourant.code,
          date: C.iso(AUJ),
          mecef: {
            nim: 'NIM' + C.BRAND.ifu.slice(-8),
            code: 'CODE-DGI-EN-ATTENTE',
            compteurs: (factures().length + 1) + '/' + factures().length + ' FN',
          },
          lignes: lignes.map(function (l) {
            var net = l.prixNet != null ? l.prixNet : l.prixUnitaire;
            return { designation: l.designation.toUpperCase(), quantite: l.quantite, prixUnitaire: net, montant: l.quantite * net };
          }),
          total: t.total, remise: t.remises,
          partAssureur: t.partAssurance, partPatient: t.partPatient,
          partNonAssuree: t.partNonAssuree,
          regle: Number(montantRegle.value) || 0,
          /* Exigence écrite du cahier de charge : la facture normalisée ne
             porte QUE la part réglée par le patient. Ni la part assureur, ni
             les remises n'entrent dans la base MECeF. */
          baseMecef: t.partPatient,
        });
      }

      function enregistrer(proforma) {
        if (!lignes.length) { U.toast('Ajouter au moins une prestation.', { type: 'error' }); return; }
        var t = totaux();
        var couvre = t.partAssurance > 0;

        /* Répartition des lignes entre les deux pièces. */
        var enrichies = lignes.map(function (l, i) {
          var d = t.detail[i] || {};
          var net = l.prixNet != null ? l.prixNet : l.prixUnitaire;
          return Object.assign({}, l, {
            prixNet: net, montant: l.quantite * net,
            partAssureur: d.partAssureur || 0,
            partPatient: d.partPatient != null ? d.partPatient : l.quantite * net,
            motifCouverture: d.motif || null,
            taux: d.taux || 0,
          });
        });
        var couvertes = enrichies.filter(function (l) { return l.partAssureur > 0; });
        var nonCouvertes = enrichies.filter(function (l) { return l.partAssureur === 0; });

        var pieces = [];
        if (!couvre || !couvertes.length || !nonCouvertes.length) {
          /* Une seule pièce : patient non assuré, ou toutes les lignes du même côté. */
          pieces.push({ lignes: enrichies, volet: null });
        } else {
          pieces.push({ lignes: couvertes, volet: 'couvert' });
          pieces.push({ lignes: nonCouvertes, volet: 'non_couvert' });
        }

        var creees = [], annulations = [];
        /* Le rang part du nombre de factures AVANT l'émission : le relire dans la boucle compterait deux fois la pièce -A
           déjà insérée et laisserait un trou entre -A et -B (écart E6b, corrigé le 30/10/2026). */
        var rangDebut = factures().length;
        pieces.forEach(function (piece, rang) {
          var totalPiece = C.sum(piece.lignes, 'montant');
          var assPiece = C.sum(piece.lignes, 'partAssureur');
          var patPiece = C.sum(piece.lignes, 'partPatient');
          var remisePiece = C.sum(piece.lignes, function (l) { return l.quantite * (l.remiseUnitaire || 0); });
          /* Le règlement saisi couvre d'abord la pièce à la charge du patient. */
          var aRegler = proforma ? 0 : Math.min(Number(montantRegle.value) || 0, t.partPatient);
          var reglePiece = proforma ? 0 : Math.min(aRegler, patPiece);
          if (rang > 0) reglePiece = Math.max(0, Math.min(aRegler - C.sum(creees, 'montantPaye'), patPiece));

          var suffixe = piece.volet === 'couvert' ? '-A' : (piece.volet === 'non_couvert' ? '-B' : '');
          var f = {
            numero: (proforma ? 'PRO-2026-' : 'FN-2026-') + C.pad(rangDebut + 1 + rang, 5) + suffixe,
            /* Point fiscal : la MECeF ne normalise que la part réglée par le
               patient. Une pièce entièrement à la charge de l'assureur n'y va
               pas, et les remises n'y entrent jamais. */
            numeroMecef: (proforma || patPiece === 0) ? null : 'MECEF' + C.between(C.seeded(Date.now() % 100000 + rang), 1000000, 9999999),
            baseMecef: proforma ? 0 : reglePiece,
            patientId: patientCourant.id, patient: patientCourant.nom + ' ' + patientCourant.prenom,
            patientCode: dissocier.checked ? null : patientCourant.code,
            /* Le cahier de charge demande de pouvoir détacher l'opération de
               caisse du numéro de dossier (vente au comptoir). */
            operationDissociee: !!dissocier.checked,
            date: C.iso(C.aujourdhui()), type: selType.value,
            volet: piece.volet,
            libelleVolet: piece.volet === 'couvert' ? 'Prestations couvertes par l’assurance'
              : (piece.volet === 'non_couvert' ? 'Prestations non couvertes — à la charge du patient' : null),
            lignes: piece.lignes,
            montantHT: totalPiece, montantTTC: totalPiece,
            montantRemises: remisePiece,
            assureur: assPiece > 0 ? patientCourant.assureur : null,
            souscripteur: t.souscripteur ? t.souscripteur.nom : null,
            numeroPolice: t.souscripteur ? t.souscripteur.police : null,
            tauxPriseEnCharge: totalPiece ? Math.round(assPiece * 100 / totalPiece) : 0,
            partAssurance: assPiece, partPatient: patPiece,
            montantPaye: reglePiece, reliquat: patPiece - reglePiece,
            modePaiement: selMode.value,
            statutPaiement: proforma ? 'impayee' : (reglePiece >= patPiece ? 'soldee' : (reglePiece > 0 ? 'partielle' : 'impayee')),
            statutMecef: (proforma || patPiece === 0) ? 'en_attente' : 'valide',
            proforma: !!proforma,
          };
          var res = S.collection('factures', { module: 'M8', entite: 'Facture' }).insert(f);
          creees.push(res.record);
          annulations.push(res.undo);
        });

        /* Sortie automatique du stock pour les médicaments facturés (CDCT §10.7) */
        if (!proforma) {
          lignes.filter(function (l) { return l.produitId; }).forEach(function (l) {
            var prod = produits().filter(function (pp) { return pp.id === l.produitId; })[0];
            if (!prod) return;
            var avant = { stockDetail: prod.stockDetail, stock: prod.stock };
            S.collection('produits').update(prod.id, {
              stockDetail: Math.max(0, prod.stockDetail - l.quantite),
              stock: Math.max(0, prod.stock - l.quantite),
            });
            var mv = S.collection('mouvements', { module: 'M6', entite: 'MouvementStock' }).insert({
              reference: C.nextRef('M', 6), date: C.iso(C.aujourdhui()),
              produitId: prod.id, produit: prod.designation,
              type: 'sortie', typeLabel: 'Sortie', quantite: l.quantite, stockType: 'detail',
              justificatif: 'Facture ' + creees[0].numero, utilisateur: S.currentUser(),
            });
            annulations.push(function () { S.collection('produits').update(prod.id, avant); mv.undo(); });
          });
        }

        var detailToast = creees.length > 1
          ? 'Deux pièces : ' + creees[0].numero + ' (couvert) et ' + creees[1].numero + ' (non couvert).'
          : (creees[0].reliquat > 0 ? 'Reliquat de ' + C.money(creees[0].reliquat) + ' à régler.' : null);

        U.toast(proforma ? 'Facture pro-forma établie.'
          : 'Facture enregistrée — ' + C.money(C.sum(creees, 'montantPaye')) + ' encaissé.', {
          type: 'success', detail: detailToast, duration: 7000,
          undo: function () { annulations.forEach(function (u) { u(); }); },
        });

        etatFacture(creees[0], { proforma: proforma, jumelle: creees[1] || null });

        lignes = [];
        majLignes(); majTotaux();
      }
    },
  });

  /* ==========================================================================
   * OPÉRATIONS DE CAISSE
   * --------------------------------------------------------------------------
   * Demande de la Direction : un module qui rassemble ce qui passe par la
   * caisse — tickets, factures, avoirs — et permet d'en tirer l'inventaire
   * journalier ou hebdomadaire, sans avoir à parcourir les factures une à une.
   * ======================================================================== */
  /* Les six périodicités vivent désormais au SOCLE : le gestionnaire de stock
     demande les mêmes sur ses points de vente, qui sont des écrans de M6 — et
     une page ne charge que le module de son écran. */
  var PERIODES = C.PERIODES;
  var bornes = C.bornes;

  function dansPeriode(f, b) { return C.dansBornes(f.date, b); }

  global.SIGH.screen('m8-operations', {
    title: 'Opérations de caisse',
    description: 'Tickets, factures et avoirs passés en caisse, avec inventaire journalier ou hebdomadaire.',
    regle: 'Toute opération de caisse est ici, quelle que soit la pièce émise. '
      + 'L’<strong>inventaire</strong> arrête la caisse sur une période et se compare à l’espèce comptée ; '
      + 'un écart doit être expliqué avant clôture, jamais absorbé en silence.',
    actions: function () {
      return [
        K.btn('Recettes par période', { icon: 'trending-up', onclick: function () { global.SIGH.app.go('m8-recettes'); } }),
        K.btn('Émettre une facture', { variant: 'primary', icon: 'receipt', onclick: function () { global.SIGH.app.go('m8-facturation'); } }),
      ];
    },
    render: function (root) {
      var selPeriode = el('select.select');
      PERIODES.slice(0, 3).forEach(function (p) { selPeriode.appendChild(el('option', { value: p.id }, p.label)); });
      var selDate = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Périodicité' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Arrêtée au' }), selDate]),
        K.btn('Inventaire de caisse', { variant: 'primary', icon: 'clipboard-check', onclick: inventaire }),
      ]));

      selPeriode.addEventListener('change', afficher);
      selDate.addEventListener('change', afficher);
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function operations() {
        var b = bornes(selPeriode.value, selDate.value);
        return factures().filter(function (f) { return dansPeriode(f, b); });
      }

      function afficher() {
        var b = bornes(selPeriode.value, selDate.value);
        var ops = operations();
        var avoirs = ops.filter(function (f) { return f.montantTTC < 0; });
        var encaisse = C.sum(ops, 'montantPaye');

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Opérations', value: C.num(ops.length), icon: 'scroll-text', tone: 'navy', hint: C.dateFR(b.debut) + ' → ' + C.dateFR(b.fin) },
          { label: 'Encaissé', value: C.money(encaisse), icon: 'banknote', tone: 'success' },
          { label: 'Reste à encaisser', value: C.money(C.sum(ops, 'reliquat')), icon: 'hourglass', tone: 'warning' },
          { label: 'Avoirs', value: C.num(avoirs.length), icon: 'file-minus', tone: avoirs.length ? 'danger' : 'neutral', hint: C.money(Math.abs(C.sum(avoirs, 'montantTTC'))) },
        ]));

        /* Ventilation par mode de règlement — le point de caisse attendu. */
        var parMode = {};
        ops.forEach(function (f) {
          var k = f.modePaiement || 'non_precise';
          parMode[k] = (parMode[k] || 0) + (f.montantPaye || 0);
        });
        vue.appendChild(U.card('Ventilation des encaissements', K.miniTable([
          { label: 'Mode de règlement', key: 'mode' },
          { label: 'Montant', align: 'right', render: function (r) { return C.money(r.montant, false); } },
          {
            label: 'Part', align: 'right',
            render: function (r) { return encaisse ? Math.round(r.montant * 100 / encaisse) + ' %' : '—'; },
          },
        ], Object.keys(parMode).map(function (k) {
          return { mode: modeLabel(k), montant: parMode[k] };
        }).sort(function (a, b2) { return b2.montant - a.montant; }))));

        vue.appendChild(U.dataTable({
          title: 'Pièces passées en caisse', rows: ops, exportName: 'operations-caisse',
          pageSize: 15, searchable: true, defaultSort: 'date', defaultDir: 'desc',
          emptyMessage: 'Aucune opération sur la période.',
          filters: [
            {
              name: 'piece', label: 'Type de pièce',
              options: [{ value: 'facture', label: 'Factures' }, { value: 'avoir', label: 'Avoirs' },
                { value: 'proforma', label: 'Pro-forma' }],
              match: function (f, v) {
                if (v === 'avoir') return f.montantTTC < 0;
                if (v === 'proforma') return !!f.proforma;
                return f.montantTTC >= 0 && !f.proforma;
              },
            },
            { name: 'statutPaiement', label: 'Règlement', options: [{ value: 'soldee', label: 'Soldée' }, { value: 'partielle', label: 'Partielle' }, { value: 'impayee', label: 'Impayée' }] },
          ],
          columns: [
            {
              key: 'numero', label: 'Pièce', nowrap: true,
              render: function (f) {
                return el('div', null, [
                  el('span.font-mono.text-xs', { text: f.numero }),
                  f.montantTTC < 0 ? el('span.ml-1', null, U.badge('Avoir', 'danger')) : null,
                  f.operationDissociee ? el('span.ml-1', null, U.badge('Comptoir', 'neutral')) : null,
                ]);
              },
            },
            { key: 'date', label: 'Date', nowrap: true, text: function (f) { return C.dateFR(f.date); }, render: function (f) { return C.dateFR(f.date); } },
            {
              key: 'patient', label: 'Patient',
              render: function (f) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.text-slate-700', { text: f.patient }),
                  el('p.font-mono.text-xs.text-slate-400', { text: f.operationDissociee ? 'hors dossier' : (f.patientCode || '—') }),
                ]);
              },
            },
            { key: 'type', label: 'Nature' },
            { key: 'montantTTC', label: 'Montant', align: 'right', text: function (f) { return String(f.montantTTC); }, render: function (f) { return C.money(f.montantTTC, false); } },
            { key: 'montantPaye', label: 'Encaissé', align: 'right', text: function (f) { return String(f.montantPaye); }, render: function (f) { return el('span.font-semibold', { text: C.money(f.montantPaye, false) }); } },
            { key: 'modePaiement', label: 'Règlement', text: function (f) { return modeLabel(f.modePaiement); }, render: function (f) { return modeLabel(f.modePaiement); } },
          ],
        }));
        U.icons(vue);
      }

      /* L'inventaire arrête la caisse et confronte le théorique au compté. */
      function inventaire() {
        var b = bornes(selPeriode.value, selDate.value);
        var ops = operations();
        var theorique = C.sum(ops.filter(function (f) { return (f.modePaiement || 'especes') === 'especes'; }), 'montantPaye');

        var f = U.form([
          { name: 'compte', label: 'Espèces comptées en caisse (FCFA)', type: 'money', required: true, min: 0, value: theorique },
          { name: 'agent', label: 'Agent de caisse', required: true, value: S.currentUser() },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ], {});
        var ecartHost = el('div');

        function majEcart() {
          C.clear(ecartHost);
          var compte = Number(f.controls.compte.value) || 0;
          var e = compte - theorique;
          ecartHost.appendChild(K.note(e === 0
            ? '<strong>Caisse juste.</strong> L’espèce comptée correspond au théorique.'
            : '<strong>Écart de ' + C.money(Math.abs(e)) + '</strong> — ' + (e > 0 ? 'excédent' : 'manquant')
              + '. Un écart doit être expliqué avant clôture : il figurera sur l’état d’inventaire.',
          { tone: e === 0 ? 'success' : 'warning', icon: e === 0 ? 'check-circle-2' : 'alert-triangle' }));
        }
        f.addEventListener('input', majEcart);
        majEcart();

        var corps = el('div.space-y-3', null, [
          U.descList([
            ['Périodicité', b.label],
            ['Période', C.dateFR(b.debut) + ' → ' + C.dateFR(b.fin)],
            ['Opérations', C.num(ops.length)],
            ['Encaissé toutes formes', C.money(C.sum(ops, 'montantPaye'))],
            ['Dont espèces (théorique)', C.money(theorique)],
          ]),
          f, ecartHost,
        ]);

        var m = U.modal({
          title: 'Inventaire de caisse — ' + b.label.toLowerCase(), size: 'lg', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Éditer l’inventaire', {
              variant: 'primary', icon: 'printer',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var ecart = v.compte - theorique;
                m.close();
                P.etat({
                  titre: 'Inventaire de caisse — ' + b.label.toLowerCase(),
                  sousTitre: C.dateFR(b.debut) + ' au ' + C.dateFR(b.fin),
                  cartouche: [['Périodicité', b.label], ['Arrêté au', C.dateFR(b.fin)],
                    ['Opérations', C.num(ops.length)], ['Agent de caisse', v.agent],
                    ['Théorique espèces', C.money(theorique)], ['Compté', C.money(v.compte)]],
                  contenu: el('div.space-y-3', null, [
                    P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
                      { k: 'Encaissements de la période', v: C.money(C.sum(ops, 'montantPaye'), false) },
                      { k: 'Dont espèces', v: C.money(theorique, false) },
                      { k: 'Espèces comptées', v: C.money(v.compte, false) },
                      { k: ecart === 0 ? 'Écart' : (ecart > 0 ? 'Excédent constaté' : 'Manquant constaté'), v: C.money(Math.abs(ecart), false) },
                    ]),
                    v.observation ? el('p.mt-3.text-\\[10px\\].text-slate-700', { text: 'Observation : ' + v.observation }) : null,
                  ]),
                  signatures: [{ role: 'L’agent de caisse', nom: v.agent },
                    { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
                });
                S.log('Inventaire de caisse', 'M8', 'Caisse', C.iso(b.fin), null,
                  { theorique: theorique, compte: v.compte, ecart: ecart });
              },
            }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * RECETTES PAR PÉRIODE
   * --------------------------------------------------------------------------
   * Demande de la Direction : suivre les recettes journalières, mais aussi
   * hebdomadaires, mensuelles et annuelles, et pouvoir choisir librement une
   * plage de dates.
   * ======================================================================== */
  global.SIGH.screen('m8-recettes', {
    title: 'Recettes par période',
    description: 'Recettes encaissées par journée, semaine, mois, trimestre, semestre ou année, avec plage libre.',
    regle: 'Les recettes sont <strong>calculées depuis les encaissements</strong> : elles ne se saisissent pas. '
      + 'Une recette ne compte que ce qui est réellement entré en caisse — le facturé non réglé figure à part.',
    actions: function () {
      return [
        K.btn('Opérations de caisse', { icon: 'scroll-text', onclick: function () { global.SIGH.app.go('m8-operations'); } }),
        K.btn('État de caisse journalier', { icon: 'calculator', onclick: function () { global.SIGH.app.go('m8-caisse'); } }),
      ];
    },
    render: function (root) {
      var selPeriode = el('select.select');
      PERIODES.forEach(function (p) { selPeriode.appendChild(el('option', { value: p.id }, p.label)); });
      var debut = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, -29)) });
      var fin = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var libre = el('input.checkbox', { type: 'checkbox', id: 'f_plage' });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Périodicité' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Du' }), debut]),
        el('div', null, [el('label.label', { text: 'Au' }), fin]),
        el('label.flex.cursor-pointer.items-center.gap-2.pb-2', { for: 'f_plage' }, [
          libre, el('span.text-xs.text-slate-600', { text: 'Plage de dates libre' }),
        ]),
        K.btn('Éditer l’état', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));

      [selPeriode, debut, fin, libre].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function plage() {
        if (libre.checked) return { debut: C.toDate(debut.value), fin: C.toDate(fin.value), label: 'Plage libre' };
        var b = bornes(selPeriode.value, fin.value);
        debut.value = C.iso(b.debut);
        return b;
      }

      /* Découpage de la plage en tranches selon la périodicité choisie. */
      function tranches(p) {
        var pas = { jour: 1, semaine: 7, mois: 30, trimestre: 91, semestre: 182, annee: 365 }[selPeriode.value] || 1;
        if (libre.checked) {
          var jours = Math.max(1, Math.round((C.toDate(p.fin) - C.toDate(p.debut)) / 86400000) + 1);
          pas = jours > 180 ? 30 : (jours > 45 ? 7 : 1);
        }
        var out = [], curseur = C.toDate(p.debut);
        while (curseur.getTime() <= C.toDate(p.fin).getTime()) {
          var f = C.addDays(curseur, pas - 1);
          if (f.getTime() > C.toDate(p.fin).getTime()) f = C.toDate(p.fin);
          out.push({ debut: curseur, fin: f });
          curseur = C.addDays(f, 1);
          if (out.length > 400) break;
        }
        return out;
      }

      function afficher() {
        var p = plage();
        var toutes = factures().filter(function (f) { return dansPeriode(f, p); });
        var encaisse = C.sum(toutes, 'montantPaye');
        var facture = C.sum(toutes, 'montantTTC');

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Recette encaissée', value: C.money(encaisse), icon: 'banknote', tone: 'success', hint: C.dateFR(p.debut) + ' → ' + C.dateFR(p.fin) },
          { label: 'Montant facturé', value: C.money(facture), icon: 'receipt', tone: 'navy' },
          { label: 'Reste à encaisser', value: C.money(C.sum(toutes, 'reliquat')), icon: 'hourglass', tone: 'warning' },
          {
            label: 'Taux de recouvrement',
            value: facture ? Math.round(encaisse * 100 / facture) + ' %' : '—',
            icon: 'percent', tone: 'info',
          },
        ]));

        var lignes = tranches(p).map(function (t) {
          var f = factures().filter(function (x) { return dansPeriode(x, t); });
          return {
            periode: C.dateFR(t.debut) + (C.iso(t.debut) === C.iso(t.fin) ? '' : ' → ' + C.dateFR(t.fin)),
            debut: C.iso(t.debut),
            pieces: f.length,
            facture: C.sum(f, 'montantTTC'),
            encaisse: C.sum(f, 'montantPaye'),
            reliquat: C.sum(f, 'reliquat'),
            assureur: C.sum(f, 'partAssurance'),
          };
        });

        if (lignes.length > 1) {
          vue.appendChild(U.card('Évolution des encaissements', G.ligne(
            lignes.map(function (l) { return l.periode; }),
            [{ label: 'Encaissé', data: lignes.map(function (l) { return l.encaisse; }) },
              { label: 'Facturé', data: lignes.map(function (l) { return l.facture; }), fill: false }]
          )));
        }

        vue.appendChild(U.dataTable({
          title: 'Recettes — ' + (libre.checked ? 'plage libre' : p.label.toLowerCase()),
          rows: lignes, exportName: 'recettes', pageSize: 20, defaultSort: 'debut', defaultDir: 'desc',
          emptyMessage: 'Aucune recette sur la période.',
          columns: [
            { key: 'periode', label: 'Période', nowrap: true },
            { key: 'pieces', label: 'Pièces', align: 'right' },
            { key: 'facture', label: 'Facturé', align: 'right', text: function (l) { return String(l.facture); }, render: function (l) { return C.money(l.facture, false); } },
            { key: 'assureur', label: 'Dont part assureur', align: 'right', text: function (l) { return String(l.assureur); }, render: function (l) { return C.money(l.assureur, false); } },
            {
              key: 'encaisse', label: 'Encaissé', align: 'right',
              text: function (l) { return String(l.encaisse); },
              render: function (l) { return el('span.font-semibold.text-success-700', { text: C.money(l.encaisse, false) }); },
            },
            { key: 'reliquat', label: 'Reste à encaisser', align: 'right', text: function (l) { return String(l.reliquat); }, render: function (l) { return C.money(l.reliquat, false); } },
          ],
        }));
        U.icons(vue);
      }

      function imprimer() {
        var p = plage();
        var lignes = tranches(p).map(function (t) {
          var f = factures().filter(function (x) { return dansPeriode(x, t); });
          return {
            periode: C.dateFR(t.debut) + (C.iso(t.debut) === C.iso(t.fin) ? '' : ' → ' + C.dateFR(t.fin)),
            pieces: f.length, facture: C.sum(f, 'montantTTC'),
            encaisse: C.sum(f, 'montantPaye'), reliquat: C.sum(f, 'reliquat'),
          };
        });
        var toutes = factures().filter(function (f) { return dansPeriode(f, p); });
        P.etat({
          titre: 'État des recettes',
          sousTitre: (libre.checked ? 'Plage libre' : p.label) + ' — ' + C.dateFR(p.debut) + ' au ' + C.dateFR(p.fin),
          cartouche: [['Périodicité', libre.checked ? 'Plage libre' : p.label],
            ['Du', C.dateFR(p.debut)], ['Au', C.dateFR(p.fin)],
            ['Pièces', C.num(toutes.length)],
            ['Recette encaissée', C.money(C.sum(toutes, 'montantPaye'))],
            ['Reste à encaisser', C.money(C.sum(toutes, 'reliquat'))]],
          contenu: P.tableau([
            { label: 'Période', key: 'periode' },
            { label: 'Pièces', key: 'pieces', align: 'right', somme: true, formatTotal: function (v) { return C.num(v); } },
            { label: 'Facturé', align: 'right', value: function (l) { return C.money(l.facture, false); }, somme: function (l) { return l.facture; } },
            { label: 'Encaissé', align: 'right', value: function (l) { return C.money(l.encaisse, false); }, somme: function (l) { return l.encaisse; } },
            { label: 'Reste à encaisser', align: 'right', value: function (l) { return C.money(l.reliquat, false); }, somme: function (l) { return l.reliquat; } },
          ], lignes, { total: true, totalLabel: 'TOTAL' }),
          signatures: [{ role: 'L’agent de caisse' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * FACTURES
   * ======================================================================== */
  global.SIGH.screen('m8-factures', {
    title: 'Factures',
    description: 'Ensemble des factures émises, avec suivi du règlement, de la prise en charge assurance et de la transmission MECeF.',
    regle: 'Cet écran <strong>consulte</strong> les factures émises. Une facture s’établit depuis l’écran d’émission, '
      + 'seul endroit où se choisissent les prestations, les remises et la répartition assureur / patient : '
      + 'le bouton « Nouveau » y conduit plutôt que d’ouvrir une saisie incomplète.',
    actions: function () {
      return [
        K.btn('Avoirs', { icon: 'file-minus', onclick: function () { global.SIGH.app.go('m8-remboursements'); } }),
        K.btn('Nouvelle facture', { variant: 'primary', icon: 'plus', onclick: function () { global.SIGH.app.go('m8-facturation'); } }),
      ];
    },
    render: K.crud({
      collection: 'factures', entite: 'facture', entiteP: 'factures', module: 'M8',
      /* Le formulaire générique du kit n'exposerait ni les lignes, ni les
         remises, ni la répartition : la création passe par l'écran d'émission. */
      creerVers: 'm8-facturation',
      defaultSort: 'date', defaultDir: 'desc', pageSize: 15, drawerWidth: 'max-w-2xl',
      columns: [
        colNumero, colDateF, colPatientF,
        { key: 'type', label: 'Nature', render: function (f) { return U.badge(f.type, 'navy'); } },
        colMontant,
        {
          key: 'partAssurance', label: 'Part assurance', align: 'right',
          text: function (f) { return f.assureur ? C.money(f.partAssurance, false) : ''; },
          render: function (f) {
            return f.assureur
              ? el('div.text-right', null, [
                el('p.num.text-sm', { text: C.money(f.partAssurance, false) }),
                el('p.text-xs.text-slate-400', { text: f.assureur + ' ' + f.tauxPriseEnCharge + ' %' }),
              ])
              : el('span.text-xs.text-slate-400', { text: '—' });
          },
        },
        {
          key: 'montantPaye', label: 'Réglé', align: 'right',
          text: function (f) { return C.money(f.montantPaye, false); },
          render: function (f) { return C.money(f.montantPaye, false); },
        },
        colReliquat, colStatutPaiement,
        {
          key: 'statutMecef', label: 'MECeF',
          render: function (f) {
            var m = { valide: ['Validée', 'success'], en_attente: ['En attente', 'warning'], rejete: ['Rejetée', 'danger'] };
            var x = m[f.statutMecef] || ['—', 'neutral'];
            return U.badge(x[0], x[1]);
          },
        },
      ],
      fields: function () {
        return [
          {
            name: 'patientCode', label: 'Patient', type: 'select', required: true, col: 'full',
            options: C.sortBy(patients(), 'code').map(function (p) { return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom }; }),
          },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'type', label: 'Nature', type: 'select', required: true, options: ['Consultation', 'Hospitalisation', 'Laboratoire', 'Pharmacie', 'Soins à domicile'] },
          { name: 'montantTTC', label: 'Montant total (FCFA)', type: 'money', required: true, min: 0 },
          { name: 'montantPaye', label: 'Montant réglé (FCFA)', type: 'money', min: 0 },
          { name: 'modePaiement', label: 'Mode de règlement', type: 'select', required: true, options: D.MODES_PAIEMENT.slice(0, 4).map(function (m) { return { value: m.id, label: m.label }; }) },
        ];
      },
      onCreate: function () { return { date: C.iso(AUJ), type: 'Consultation', montantPaye: 0, modePaiement: 'especes' }; },
      transform: function (v) {
        var p = patients().filter(function (x) { return x.code === v.patientCode; })[0];
        if (p) {
          v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom;
          var taux = carteValide(p) ? p.tauxPriseEnCharge : 0;
          v.assureur = taux ? p.assureur : null;
          v.tauxPriseEnCharge = taux;
          v.partAssurance = Math.round(v.montantTTC * taux / 100);
          v.partPatient = v.montantTTC - v.partAssurance;
        } else {
          v.partAssurance = 0; v.partPatient = v.montantTTC; v.tauxPriseEnCharge = 0;
        }
        v.montantHT = v.montantTTC;
        v.montantPaye = Math.min(Number(v.montantPaye) || 0, v.partPatient);
        v.reliquat = v.partPatient - v.montantPaye;
        v.statutPaiement = v.reliquat <= 0 ? 'soldee' : (v.montantPaye > 0 ? 'partielle' : 'impayee');
        if (!v.numero) v.numero = 'FN-2026-' + C.pad(factures().length + 1, 5);
        if (!v.statutMecef) v.statutMecef = 'en_attente';
        return v;
      },
      filters: [
        { name: 'statutPaiement', label: 'Règlement', options: [{ value: 'soldee', label: 'Soldée' }, { value: 'partielle', label: 'Partielle' }, { value: 'impayee', label: 'Impayée' }] },
        { name: 'type', label: 'Nature', options: ['Consultation', 'Hospitalisation', 'Laboratoire', 'Pharmacie', 'Soins à domicile'] },
        { name: 'statutMecef', label: 'MECeF', options: [{ value: 'valide', label: 'Validée' }, { value: 'en_attente', label: 'En attente' }, { value: 'rejete', label: 'Rejetée' }] },
        {
          name: 'assurance', label: 'Couverture',
          options: [{ value: 'oui', label: 'Avec assurance' }, { value: 'non', label: 'Sans assurance' }],
          match: function (f, v) { return v === 'oui' ? !!f.assureur : !f.assureur; },
        },
      ],
      kpis: function (rows) {
        return [
          { label: 'Factures', value: C.num(rows.length), icon: 'receipt', tone: 'navy' },
          { label: 'Chiffre d’affaires', value: C.money(C.sum(rows, 'montantTTC')), icon: 'trending-up', tone: 'info' },
          { label: 'Encaissé', value: C.money(C.sum(rows, 'montantPaye')), icon: 'banknote', tone: 'success' },
          { label: 'Reste à recouvrer', value: C.money(C.sum(rows, 'reliquat')), icon: 'hand-coins', tone: 'warning' },
        ];
      },
      detail: detailFacture,
      etat: function (f) { etatFacture(f, { proforma: !!f.proforma }); },
    }),
  });

  /* ==========================================================================
   * FACTURES PRO-FORMA
   * ======================================================================== */
  global.SIGH.screen('m8-proforma', {
    title: 'Factures pro-forma',
    description: 'Estimations remises au patient ou à l’assureur avant réalisation des prestations.',
    regle: 'La facture pro-forma n’a <strong>aucune valeur fiscale</strong> : elle ne peut ni servir de justificatif comptable ni être transmise au dispositif MECeF.',
    render: function (root) {
      var rows = factures().filter(function (f) { return f.proforma || String(f.numero).indexOf('PRO-') === 0; });
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Pro-forma établies', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
        { label: 'Montant estimé', value: C.money(C.sum(rows, 'montantTTC')), icon: 'calculator', tone: 'info' },
        { label: 'Converties en facture', value: C.num(0), icon: 'file-check-2', tone: 'success' },
        { label: 'Factures normalisées', value: C.num(factures().length - rows.length), icon: 'file-badge', tone: 'neutral' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Factures pro-forma', rows: rows, exportName: 'proforma', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        emptyMessage: 'Aucune facture pro-forma établie.',
        emptyHint: 'Les pro-forma se créent depuis l’écran « Nouvelle facture ».',
        columns: [colNumero, colDateF, colPatientF,
          { key: 'type', label: 'Nature', render: function (f) { return U.badge(f.type, 'navy'); } },
          colMontant,
        ],
        onRowClick: function (f) { U.drawer({ title: f.numero, subtitle: f.patient, body: detailFacture(f), footer: [K.btn('Imprimer', { variant: 'primary', icon: 'printer', onclick: function () { etatFacture(f, { proforma: true }); } })] }); },
        rowActions: function (f) { return [K.iconBtn('printer', 'Imprimer', function () { etatFacture(f, { proforma: true }); })]; },
        actions: [K.droits().editer ? K.lien('m8-facturation', 'Nouvelle pro-forma', { size: 'sm', variant: 'primary', icon: 'plus' }) : null],
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * PAIEMENTS
   * ======================================================================== */
  global.SIGH.screen('m8-paiements', {
    title: 'Paiements',
    description: 'Encaissements par espèces, terminal de paiement électronique, MTN Mobile Money et Moov Money.',
    regle: 'Écran de travail de la caisse : il ne crée pas de facture mais <strong>encaisse</strong> celles '
      + 'qui sont dues. Une facture se corrige depuis l’émission ou par un avoir — jamais par retouche '
      + 'd’un règlement déjà passé (RG-12).',
    render: function (root) {
      var col = S.collection('factures', { module: 'M8', entite: 'Paiement' });
      var host = el('div.space-y-4');
      var table;

      function aRegler() { return factures().filter(function (f) { return f.reliquat > 0; }); }

      host.appendChild(U.kpiGrid(D.MODES_PAIEMENT.slice(0, 4).map(function (m) {
        var f = factures().filter(function (x) { return x.modePaiement === m.id; });
        return { label: m.label, value: C.money(C.sum(f, 'montantPaye')), icon: m.icon, tone: 'navy', hint: C.num(f.length) + ' opération(s)' };
      })));

      host.appendChild(U.tabs([
        {
          id: 'aregler', label: 'À encaisser', badge: aRegler().length,
          render: function () {
            table = U.dataTable({
              rows: aRegler, exportName: 'factures-a-encaisser', pageSize: 12,
              defaultSort: 'date', defaultDir: 'desc',
              emptyMessage: 'Aucune facture en attente de règlement.',
              columns: [colNumero, colDateF, colPatientF, colMontant,
                { key: 'montantPaye', label: 'Déjà réglé', align: 'right', text: function (f) { return C.money(f.montantPaye, false); }, render: function (f) { return C.money(f.montantPaye, false); } },
                colReliquat, colStatutPaiement,
              ],
              rowActions: function (f) {
                return [K.commande('Encaisser', { size: 'sm', variant: 'primary', icon: 'banknote', onclick: function () { encaisser(f); } })];
              },
            });
            return table;
          },
        },
        {
          id: 'historique', label: 'Historique des règlements',
          render: function () {
            var payees = factures().filter(function (f) { return f.montantPaye > 0; });
            return U.dataTable({
              rows: payees, exportName: 'paiements', pageSize: 15,
              defaultSort: 'date', defaultDir: 'desc',
              filters: [{ name: 'modePaiement', label: 'Mode', options: D.MODES_PAIEMENT.map(function (m) { return { value: m.id, label: m.label }; }) }],
              columns: [colNumero, colDateF, colPatientF,
                {
                  key: 'modePaiement', label: 'Mode de règlement',
                  text: function (f) { return modeLabel(f.modePaiement); },
                  render: function (f) { return U.badge(modeLabel(f.modePaiement), 'navy'); },
                },
                { key: 'montantPaye', label: 'Montant réglé', align: 'right', text: function (f) { return C.money(f.montantPaye, false); }, render: function (f) { return el('span.font-semibold.text-success-700', { text: C.money(f.montantPaye, false) }); } },
                colReliquat, colStatutPaiement,
              ],
              rowActions: function (f) { return [K.iconBtn('printer', 'Reçu de paiement', function () { recu(f); })]; },
            });
          },
        },
      ]));
      root.appendChild(host);
      return null;

      function encaisser(f) {
        var form = U.form([
          { name: 'montant', label: 'Montant encaissé (FCFA)', type: 'money', required: true, min: 1, value: f.reliquat },
          { name: 'modePaiement', label: 'Mode de règlement', type: 'select', required: true, options: D.MODES_PAIEMENT.slice(0, 4).map(function (m) { return { value: m.id, label: m.label }; }) },
          { name: 'reference', label: 'Référence de la transaction', help: 'N° de transaction Mobile Money ou ticket TPE, le cas échéant.' },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ], { montant: f.reliquat, modePaiement: f.modePaiement });

        var body = el('div.space-y-3', null, [
          U.descList([['Facture', f.numero], ['Patient', f.patient],
            ['Montant total', C.money(f.montantTTC)], ['Part patient', C.money(f.partPatient)],
            ['Déjà réglé', C.money(f.montantPaye)], ['Reste à payer', C.money(f.reliquat)]], 'grid-cols-2'),
          form,
        ]);

        var m = U.modal({
          title: 'Encaissement', subtitle: f.numero + ' — ' + f.patient, size: 'md', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Valider l’encaissement', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                var v = form.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (v.montant > f.reliquat) { U.toast('Le montant dépasse le reste dû (' + C.money(f.reliquat) + ').', { type: 'error' }); return; }
                var nouveau = f.montantPaye + v.montant;
                var res = col.update(f.id, {
                  montantPaye: nouveau, reliquat: f.partPatient - nouveau,
                  modePaiement: v.modePaiement,
                  statutPaiement: (f.partPatient - nouveau) <= 0 ? 'soldee' : 'partielle',
                });
                m.close();
                if (table) table.refresh();
                U.toast('Encaissement de ' + C.money(v.montant) + ' enregistré.', {
                  type: 'success',
                  detail: res.record.reliquat > 0 ? 'Reliquat de ' + C.money(res.record.reliquat) + '.' : 'Facture soldée.',
                  undo: function () { res.undo(); if (table) table.refresh(); },
                });
                recu(res.record, v);
              },
            }),
          ],
        });
      }

      /**
       * Le reçu détaille les PRESTATIONS réglées, et celles qui restent dues.
       * C'est ce détail que la caisse et le patient réclamaient : savoir quel
       * examen précis a été payé, et lequel attend encore son règlement.
       */
      function recu(f, v) {
        var lignes = f.lignes || [];
        var payees = lignes.filter(function (l) { return l.statutPaiement === 'paye'; });
        var dues = lignes.filter(function (l) { return l.statutPaiement !== 'paye'; });
        var CATEGORIES = {
          analyse: 'Analyse', medicament: 'Médicament', acte: 'Acte',
          consultation: 'Consultation', hospitalisation: 'Hospitalisation',
        };
        function tableauLignes(rows) {
          return P.tableau([
            { label: 'Nature', value: function (l) { return CATEGORIES[l.categorie] || l.categorie || '—'; } },
            { label: 'Prestation', key: 'designation' },
            { label: 'Qté', align: 'right', somme: function (l) { return l.quantite || 1; },
              formatTotal: function (v) { return C.num(v); },
              value: function (l) { return C.num(l.quantite || 1); } },
            { label: 'P.U.', align: 'right', value: function (l) { return C.money(l.prixUnitaire, false); } },
            { label: 'Part assureur', align: 'right',
              somme: function (l) { return l.partAssureur || 0; },
              value: function (l) { return l.partAssureur ? C.money(l.partAssureur, false) : '—'; } },
            { label: 'À la charge du patient', align: 'right',
              somme: function (l) { return l.partPatient || 0; },
              value: function (l) { return C.money(l.partPatient, false); } },
          ], rows, { total: true, totalLabel: 'TOTAL' });
        }

        P.etat({
          titre: 'Reçu de paiement',
          sousTitre: f.numero,
          cartouche: [['Facture', f.numero], ['Patient', f.patient], ['Dossier', f.patientCode],
            ['Date', C.dateFR(AUJ)], ['Mode de règlement', modeLabel(v ? v.modePaiement : f.modePaiement)],
            ['Encaissé par', (f.dernierReglement && f.dernierReglement.encaissePar) || S.currentUser()],
            ['Référence transaction', (v && v.reference) || '—'],
            ['RCCM', C.BRAND.rccm]],
          contenu: el('div.space-y-3', null, [
            payees.length ? el('div', null, [
              el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Prestations réglées' }),
              tableauLignes(payees),
            ]) : null,
            !lignes.length ? P.tableau(
              [{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
                { k: 'Montant total de la facture', v: C.money(f.montantTTC, false) },
                { k: 'Part à la charge du patient', v: C.money(f.partPatient, false) },
                { k: 'Montant encaissé ce jour', v: C.money(v ? v.montant : f.montantPaye, false) },
              ]) : null,
            dues.length ? el('div', null, [
              el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-danger-700', { text: 'Reste à régler' }),
              tableauLignes(dues),
              el('p.mt-1.text-\\[10px\\].italic', {
                text: 'Ces prestations ne sont pas exécutées tant qu’elles ne sont pas réglées. '
                  + 'Le patient peut revenir les acquitter : ce reçu en fait foi.',
              }),
            ]) : null,
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
              { k: 'Montant total de la facture', v: C.money(f.montantTTC, false) },
              f.partAssurance ? { k: 'Part assureur — ' + (f.assureur || ''), v: C.money(f.partAssurance, false) } : null,
              { k: 'Part à la charge du patient', v: C.money(f.partPatient, false) },
              { k: 'ENCAISSÉ CE JOUR', v: C.money(v ? v.montant : (f.dernierReglement ? f.dernierReglement.montant : f.montantPaye), false) },
              { k: 'Total réglé à ce jour', v: C.money(f.montantPaye, false) },
              { k: 'RESTE À PAYER', v: C.money(f.reliquat, false) },
            ].filter(Boolean)),
            el('p.mt-2.text-\\[10px\\]', {
              text: C.BRAND.formuleArrete + ' : ' + C.montantEnLettres(f.montantPaye || 0) + '.',
            }),
            el('p.mt-3.text-\\[10px\\].italic', {
              text: 'Reçu délivré par la caisse de la CLINIQUE NASSIERA TOO SARL. À conserver et à présenter '
                + 'au laboratoire et à la pharmacie.',
            }),
          ].filter(Boolean)),
          /* La signature du patient n'a pas lieu d'être : un encaissement est
             attesté par celui qui encaisse, pas par celui qui paie. */
          signatures: [{ role: 'Le Caissier', nom: (f.dernierReglement && f.dernierReglement.encaissePar) || '', mention: 'Signature et cachet' }],
        });
      }
    },
  });

  /* ==========================================================================
   * RELIQUATS
   * ======================================================================== */
  global.SIGH.screen('m8-reliquats', {
    title: 'Reliquats',
    description: 'Suivi des règlements différés et des écarts à régulariser, y compris par Mobile Money.',
    regle: 'Le reliquat est enregistré à l’ouverture puis régularisé au règlement différé. '
      + 'Le patient qui ne peut pas payer prend un <strong>engagement écrit</strong> chez le comptable, '
      + 'avec une date ou un échéancier. Faute de règlement, il bascule en <strong>client insolvable</strong> : '
      + 'la créance reste due et tracée, elle n’est jamais effacée.',
    render: function (root) {
      var rows = factures().filter(function (f) { return f.reliquat > 0; });
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Factures avec reliquat', value: C.num(rows.length), icon: 'hand-coins', tone: 'warning' },
        { label: 'Montant total des reliquats', value: C.money(C.sum(rows, 'reliquat')), icon: 'wallet', tone: 'danger' },
        { label: 'Reliquat moyen', value: C.money(rows.length ? C.sum(rows, 'reliquat') / rows.length : 0), icon: 'calculator', tone: 'neutral' },
        { label: 'Patients concernés', value: C.num(Object.keys(C.groupBy(rows, 'patientId')).length), icon: 'users', tone: 'info' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Reliquats en cours', rows: rows, exportName: 'reliquats', pageSize: 15,
        defaultSort: 'reliquat', defaultDir: 'desc',
        emptyMessage: 'Aucun reliquat en cours : toutes les factures sont soldées.',
        filters: [{ name: 'type', label: 'Nature', options: ['Consultation', 'Hospitalisation', 'Laboratoire', 'Pharmacie', 'Soins à domicile'] }],
        columns: [colNumero, colDateF, colPatientF,
          { key: 'type', label: 'Nature' },
          colMontant,
          { key: 'montantPaye', label: 'Réglé', align: 'right', text: function (f) { return C.money(f.montantPaye, false); }, render: function (f) { return C.money(f.montantPaye, false); } },
          colReliquat,
          {
            key: 'anciennete', label: 'Ancienneté', align: 'right',
            value: function (f) { return C.daysBetween(f.date, AUJ); },
            render: function (f) {
              var j = C.daysBetween(f.date, AUJ);
              return el('span.num', { class: j > 60 ? 'font-semibold text-danger-600' : (j > 30 ? 'text-warning-600' : 'text-slate-600'), text: j + ' j' });
            },
          },
        ],
        actions: [K.droits().editer ? K.lien('m8-paiements', 'Encaisser un reliquat', { size: 'sm', variant: 'primary', icon: 'banknote' }) : null],
        onRowClick: function (f) { U.drawer({ title: f.numero, subtitle: f.patient, body: detailFacture(f) }); },
        rowActions: function (f) {
          return [
            /* Un engagement de paiement ENGAGE le patient : c'est une écriture,
               même si son libellé ne commence par aucun verbe. */
            K.commandeIcone('handshake', 'Engagement de paiement', function () { engagement(f); }),
            K.commandeIcone('user-round-x', 'Déclarer insolvable', function () { insolvable(f); }),
            K.iconBtn('printer', 'Imprimer la facture', function () { etatFacture(f, {}); }),
          ];
        },
      }));

      host.appendChild(K.charts([
        {
          title: 'Reliquats par ancienneté',
          render: function () {
            var tranches = [
              { label: 'Moins de 30 jours', min: 0, max: 30 },
              { label: '30 à 60 jours', min: 30, max: 60 },
              { label: '60 à 90 jours', min: 60, max: 90 },
              { label: 'Plus de 90 jours', min: 90, max: 99999 },
            ];
            return G.barres(tranches.map(function (t) { return t.label; }), [{
              label: 'Montant', color: G.TONES.orange,
              data: tranches.map(function (t) {
                return C.sum(rows.filter(function (f) {
                  var j = C.daysBetween(f.date, AUJ);
                  return j >= t.min && j < t.max;
                }), 'reliquat');
              }),
            }], { horizontal: true, height: 240 });
          },
        },
        {
          title: 'Reliquats par nature de prestation',
          render: function () {
            var g = C.groupBy(rows, 'type');
            var keys = Object.keys(g);
            return G.anneau(keys, keys.map(function (k) { return C.sum(g[k], 'reliquat'); }), { legend: 'bottom' });
          },
        },
      ]));
      root.appendChild(host);
      return null;

      /* --------------------------------------------------------------------
       * Engagement de paiement — le processus décrit par la Direction : le
       * patient qui ne peut pas régler prend un engagement écrit chez le
       * comptable, en une ou plusieurs tranches, avec une date.
       * ------------------------------------------------------------------ */
      function engagement(f) {
        var form = U.form([
          {
            name: 'modalite', label: 'Modalité', type: 'select', required: true,
            options: [{ value: 'unique', label: 'Règlement en une seule tranche' },
              { value: 'echeancier', label: 'Échéancier en plusieurs tranches' }],
          },
          { name: 'dateEngagement', label: 'Date de règlement promise', type: 'date', required: true, value: C.iso(C.addDays(AUJ, 30)) },
          { name: 'tranches', label: 'Nombre de tranches', type: 'number', min: 1, max: 12, value: 1 },
          { name: 'recuPar', label: 'Engagement reçu par', required: true, value: 'KASSA Augustin' },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ], {});

        var m = U.modal({
          title: 'Engagement de paiement', subtitle: f.patient + ' — ' + C.money(f.reliquat) + ' dus',
          size: 'lg',
          body: el('div.space-y-3', null, [
            U.descList([['Facture', f.numero], ['Patient', f.patient],
              ['Montant dû', C.money(f.reliquat)], ['Ancienneté', C.daysBetween(f.date, AUJ) + ' jours']]),
            form,
            K.note('L’engagement est <strong>écrit et signé</strong> : il vaut reconnaissance de dette. '
              + 'La créance reste inscrite jusqu’à son règlement effectif.', { tone: 'info' }),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer et éditer', {
              variant: 'primary', icon: 'handshake',
              onclick: function () {
                var v = form.collect();
                if (!v) return;
                var res = S.collection('factures').update(f.id, {
                  engagement: {
                    date: v.dateEngagement, modalite: v.modalite,
                    tranches: v.modalite === 'echeancier' ? Number(v.tranches) || 1 : 1,
                    recuPar: v.recuPar, observation: v.observation,
                    prisLe: C.iso(AUJ), montant: f.reliquat,
                  },
                  insolvable: false,
                });
                m.close();
                U.toast('Engagement enregistré pour le ' + C.dateFR(v.dateEngagement) + '.', {
                  type: 'success', undo: function () { res.undo(); },
                });
                etatEngagement(S.collection('factures').get(f.id));
              },
            }),
          ],
        });
      }

      function etatEngagement(f) {
        var e = f.engagement || {};
        var lignes = [];
        var n = e.tranches || 1;
        var part = Math.round((e.montant || f.reliquat) / n);
        for (var i = 0; i < n; i++) {
          lignes.push({
            tranche: 'Tranche ' + (i + 1) + ' sur ' + n,
            echeance: C.dateFR(C.addDays(C.toDate(e.date), i * 30)),
            montant: C.money(i === n - 1 ? (e.montant || f.reliquat) - part * (n - 1) : part, false),
          });
        }
        P.etat({
          titre: 'Engagement de paiement',
          sousTitre: f.numero + ' — ' + f.patient,
          cartouche: [['Facture', f.numero], ['Patient', f.patient],
            ['Dossier', f.patientCode || '—'], ['Montant dû', C.money(e.montant || f.reliquat)],
            ['Modalité', e.modalite === 'echeancier' ? 'Échéancier' : 'Tranche unique'],
            ['Reçu par', e.recuPar || '—']],
          contenu: el('div.space-y-3', null, [
            el('p.text-\[10px\].leading-relaxed.text-slate-700', {
              text: 'Je soussigné(e) ' + f.patient + ', reconnais devoir à la Clinique NASSIERA TOO la somme de '
                + C.montantEnLettres(e.montant || f.reliquat) + ', au titre de la facture ' + f.numero
                + ', et m’engage à en effectuer le règlement selon l’échéancier ci-dessous.',
            }),
            P.tableau([
              { label: 'Échéance', key: 'tranche' },
              { label: 'Date promise', key: 'echeance' },
              { label: 'Montant', key: 'montant', align: 'right', somme: true },
            ], lignes, { total: true }),
            e.observation ? el('p.mt-2.text-\[10px\].text-slate-600', { text: 'Observation : ' + e.observation }) : null,
          ]),
          signatures: [{ role: 'Le patient', nom: f.patient, mention: 'Lu et approuvé' },
            { role: 'Le comptable', nom: e.recuPar || '' }],
        });
      }

      /* Faute de règlement, la créance bascule en client insolvable : elle
         reste due et tracée — RG-14, rien n'est effacé. */
      function insolvable(f) {
        U.confirm({
          title: 'Déclarer ' + f.patient + ' insolvable ?',
          message: 'La créance de ' + C.money(f.reliquat) + ' reste inscrite et due : la déclaration ne l’efface pas. '
            + 'Elle signale que le recouvrement amiable a échoué et que le dossier passe au traitement contentieux. '
            + 'L’opération est journalisée (RG-12).',
          confirmLabel: 'Déclarer insolvable', danger: true, requireMotif: true,
        }).then(function (r) {
          if (!r) return;
          var res = S.collection('factures').update(f.id, {
            insolvable: true, motifInsolvabilite: r.motif, declareLe: C.iso(AUJ), declarePar: S.currentUser(),
          });
          U.toast(f.patient + ' déclaré(e) client insolvable.', {
            type: 'warning', detail: 'La créance de ' + C.money(f.reliquat) + ' reste due.',
            undo: function () { res.undo(); },
          });
        });
      }
    },
  });

  /* ==========================================================================
   * REMBOURSEMENTS & ANNULATIONS
   * ======================================================================== */
  global.SIGH.screen('m8-remboursements', {
    title: 'Remboursements & annulations',
    description: 'Traitement des remboursements de trop-perçus et des annulations de factures, avec motif obligatoire.',
    regle: 'Toute annulation ou tout remboursement est <strong>motivé et journalisé</strong> (RG-12). L’annulation d’une facture normalisée déclenche l’émission d’un avoir MECeF.',
    render: function (root) {
      var col = S.collection('remboursements', { module: 'M8', entite: 'Remboursement' });
      var host = el('div.space-y-4');
      var table;

      host.appendChild(U.kpiGrid([
        { label: 'Opérations enregistrées', value: C.num(col.active().length), icon: 'undo-2', tone: 'navy' },
        { label: 'Remboursements', value: C.num(col.active().filter(function (r) { return r.nature === 'Remboursement'; }).length), icon: 'banknote', tone: 'warning' },
        { label: 'Annulations', value: C.num(col.active().filter(function (r) { return r.nature === 'Annulation'; }).length), icon: 'file-x', tone: 'danger' },
        { label: 'Montant total', value: C.money(C.sum(col.active(), 'montant')), icon: 'wallet', tone: 'info' },
      ]));

      table = U.dataTable({
        title: 'Remboursements et annulations',
        rows: function () { return col.active(); },
        exportName: 'remboursements-annulations', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        emptyMessage: 'Aucun remboursement ni annulation enregistré.',
        actions: [K.commande('Nouvelle opération', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(); } })],
        filters: [{ name: 'nature', label: 'Nature', options: ['Remboursement', 'Annulation'] }],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'factureNumero', label: 'Facture', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.text-slate-500', { text: r.factureNumero }); } },
          { key: 'patient', label: 'Patient' },
          { key: 'nature', label: 'Nature', render: function (r) { return U.badge(r.nature, r.nature === 'Annulation' ? 'danger' : 'warning'); } },
          { key: 'montant', label: 'Montant', align: 'right', text: function (r) { return C.money(r.montant, false); }, render: function (r) { return el('span.font-semibold', { text: C.money(r.montant, false) }); } },
          { key: 'motif', label: 'Motif' },
          { key: 'autorisePar', label: 'Autorisé par' },
        ],
        rowActions: function (r) { return [K.iconBtn('printer', 'Imprimer', function () { etat(r); })]; },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function ouvrir() {
        var fs = factures().filter(function (f) { return f.montantPaye > 0 || f.statutPaiement !== 'impayee'; });
        var f = U.form([
          {
            name: 'factureId', label: 'Facture concernée', type: 'select', required: true, col: 'full',
            options: C.sortBy(fs, 'date', 'desc').slice(0, 200).map(function (x) {
              return { value: x.id, label: x.numero + ' — ' + x.patient + ' — ' + C.money(x.montantTTC) };
            }),
          },
          {
            name: 'nature', label: 'Nature de l’opération', type: 'select', required: true,
            options: ['Facture avoir', 'Remboursement', 'Annulation'],
            help: 'L’avoir corrige une facture déjà émise ; le remboursement rend un trop-perçu ; l’annulation retire la pièce.',
          },
          {
            name: 'motifAvoir', label: 'Cas de figure', type: 'select',
            options: [
              { value: 'erreur', label: 'Erreur de facturation' },
              { value: 'non_rendu', label: 'Service facturé mais non rendu' },
              { value: 'remboursement', label: 'Remboursement au patient' },
              { value: 'annulation', label: 'Annulation de la prestation' },
            ],
            help: 'Les quatre situations relevées par la Direction.',
          },
          {
            name: 'refacturation', label: 'Suite donnée', type: 'select',
            options: [
              { value: 'aucune', label: 'Aucune refacturation — le service n’est pas exécuté' },
              { value: 'refaire', label: 'Le service est refait et refacturé' },
            ],
            help: 'Un service non rendu peut être refait puis refacturé, ou ne donner lieu à rien.',
          },
          { name: 'date', label: 'Date', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'montant', label: 'Montant (FCFA)', type: 'money', required: true, min: 1 },
          { name: 'motif', label: 'Motif', type: 'textarea', rows: 2, required: true, col: 'full', help: 'Obligatoire — consigné au journal d’audit (RG-12).' },
          { name: 'autorisePar', label: 'Autorisé par', required: true, value: 'TAKI Alimatou' },
        ], {});

        var m = U.modal({
          title: 'Remboursement ou annulation', size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', {
              variant: 'danger', icon: 'undo-2',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var fac = factures().filter(function (x) { return x.id === v.factureId; })[0];
                if (fac) { v.factureNumero = fac.numero; v.patient = fac.patient; v.patientCode = fac.patientCode; }
                v.reference = referenceSuivante('RB-', 5, col.all()); /* série lue sur les opérations existantes (E8) */
                var res = col.insert(v);
                var majF = null;
                if (v.nature === 'Facture avoir' && fac) {
                  /* L'avoir est une pièce à part entière : montant négatif,
                     rattachée à la facture d'origine, transmise à la MECeF.
                     Il ne supprime pas la facture — RG-14. */
                  v.reference = C.nextRef('AV-', 5);
                  var avoir = S.collection('factures', { module: 'M8', entite: 'Facture' }).insert({
                    numero: 'AV-2026-' + C.pad(factures().length + 1, 5),
                    numeroMecef: 'MECEF' + C.between(C.seeded(Date.now() % 90000), 1000000, 9999999),
                    avoirDe: fac.id, avoirDeNumero: fac.numero,
                    motifAvoir: v.motifAvoir, refacturation: v.refacturation,
                    patientId: fac.patientId, patient: fac.patient, patientCode: fac.patientCode,
                    date: v.date, type: 'Avoir',
                    montantHT: -Math.abs(v.montant), montantTTC: -Math.abs(v.montant),
                    partAssurance: 0, partPatient: -Math.abs(v.montant),
                    montantPaye: 0, reliquat: 0,
                    baseMecef: -Math.abs(v.montant),
                    statutPaiement: 'soldee', statutMecef: 'valide',
                    lignes: [{ designation: 'Avoir sur facture ' + fac.numero + ' — ' + (v.motif || ''), quantite: 1, prixUnitaire: -Math.abs(v.montant), montant: -Math.abs(v.montant) }],
                  });
                  v.avoirId = avoir.record.id;
                  v.avoirNumero = avoir.record.numero;
                  majF = { undo: avoir.undo };
                } else if (v.nature === 'Annulation' && fac) {
                  majF = S.collection('factures').update(fac.id, { statutPaiement: 'impayee', statutMecef: 'rejete', annulee: true });
                }
                m.close(); table.refresh();
                U.toast(v.nature + ' de ' + C.money(v.montant) + ' enregistré(e).', {
                  type: 'success',
                  undo: function () { res.undo(); if (majF) majF.undo(); table.refresh(); },
                });
              },
            }),
          ],
        });
      }

      function etat(r) {
        P.etat({
          titre: r.nature === 'Annulation' ? 'Avis d’annulation de facture' : 'Attestation de remboursement',
          sousTitre: r.reference,
          cartouche: [['Référence', r.reference], ['Date', C.dateFR(r.date)],
            ['Facture concernée', r.factureNumero], ['Patient', r.patient],
            ['Montant', C.money(r.montant)], ['Autorisé par', r.autorisePar]],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Nature de l’opération', v: r.nature },
              { k: 'Facture concernée', v: r.factureNumero },
              { k: 'Montant', v: C.money(r.montant) },
              { k: 'Motif', v: r.motif },
            ]),
            r.nature === 'Annulation'
              ? el('p.mt-3.text-\\[10px\\].italic', { text: 'Cette annulation donne lieu à l’émission d’un avoir transmis au dispositif MECeF.' })
              : null,
          ]),
          signatures: [{ role: 'Le Caissier' }, { role: 'La Directrice Administrative', nom: r.autorisePar }],
        });
      }
    },
  });

  /* ==========================================================================
   * ÉTAT DE CAISSE JOURNALIER
   * ======================================================================== */
  global.SIGH.screen('m8-caisse', {
    title: 'État de caisse journalier',
    description: 'Arrêté de caisse : encaissements du jour ventilés par mode de règlement et par nature de prestation.',
    regle: 'L’arrêté journalier est un <strong>état calculé</strong> : il découle des paiements et ne se saisit pas. '
      + 'La <strong>file d’attente</strong>, en revanche, se traite ici : chaque prescription encaissée débloque '
      + 'aussitôt la délivrance des médicaments et le prélèvement au laboratoire.',
    actions: function () {
      return [
        K.btn('Ordonnances', { icon: 'file-text', onclick: function () { global.SIGH.app.go('m2-ordonnances'); } }),
        K.btn('Nouvelle facture', { variant: 'primary', icon: 'plus', onclick: function () { global.SIGH.app.go('m8-facturation'); } }),
      ];
    },
    render: function (root) {
      var host = el('div.space-y-4');
      var dateSel = el('input.input.max-w-xs', { type: 'date', value: C.iso(AUJ) });
      var vue = el('div.space-y-4');

      /* --- Ce que les prescriptions du jour ont adressé à la caisse -------- */
      var file = K.fileAttente('encaissement', {
        titre: 'Prescriptions à encaisser',
        vide: 'Aucune prescription en attente de règlement.',
        icon: 'coins', action: 'Encaisser',
        onAction: function (tache, refresh) { encaisser(tache, refresh); },
      });
      host.appendChild(file);

      var CATEGORIES_LIGNE = {
        analyse: ['Analyse', 'flask-conical', 'navy'],
        medicament: ['Médicament', 'pill', 'success'],
        acte: ['Acte', 'stethoscope', 'info'],
        consultation: ['Consultation', 'user-round', 'info'],
        hospitalisation: ['Hospitalisation', 'bed', 'warning'],
      };

      function encaisser(tache, refresh) {
        var fac = S.collection('factures').get(tache.factureId);
        if (!fac) { U.toast('Facture introuvable.', { type: 'error' }); return; }
        var lignes = (fac.lignes || []).filter(function (l) { return l.statutPaiement !== 'paye'; });
        var deja = (fac.lignes || []).filter(function (l) { return l.statutPaiement === 'paye'; });

        /* Le caissier COCHE les prestations que le patient règle. Le total
           suit la sélection, et non l'inverse : c'est ce renversement qui fait
           qu'un paiement partiel libère exactement les examens payés. */
        var choisies = {};
        lignes.forEach(function (l) { choisies[l.id] = true; });

        var totalLigne = el('span.text-lg.font-bold.text-navy-900');
        var resteLigne = el('span.text-sm.text-slate-500');

        var selMode = el('select.select');
        D.MODES_PAIEMENT.forEach(function (mp) {
          selMode.appendChild(el('option', { value: mp.id }, mp.label));
        });
        var champRef = el('input.input', { type: 'text', placeholder: 'N° de transaction, chèque…' });

        var tableau = el('div.max-h-\[18rem\].overflow-auto.rounded-lg.border.border-slate-200');
        var t = el('table.tbl');
        t.appendChild(el('thead', null, el('tr', null, [
          el('th.w-10', { text: '' }),
          el('th', { text: 'Prestation' }),
          el('th.text-right', { text: 'Part assureur' }),
          el('th.text-right', { text: 'À payer' }),
        ])));
        var tb = el('tbody');

        lignes.forEach(function (l) {
          var tr = el('tr');
          var cb = el('input.checkbox', { type: 'checkbox' });
          cb.checked = true;
          cb.addEventListener('change', function () { choisies[l.id] = cb.checked; recalculer(); });
          tr.appendChild(el('td', null, cb));
          var cat = CATEGORIES_LIGNE[l.categorie] || [l.categorie, 'circle', 'neutral'];
          tr.appendChild(el('td', null, el('div.min-w-0', null, [
            el('p.truncate.text-sm.font-medium.text-slate-800', { text: l.designation }),
            el('p.text-xs.text-slate-400', {
              text: cat[0] + (l.quantite > 1 ? ' · ' + C.num(l.quantite) + ' × ' + C.money(l.prixUnitaire, false) : ''),
            }),
          ])));
          tr.appendChild(el('td.text-right.text-xs.text-slate-500', {
            text: l.partAssureur ? C.money(l.partAssureur, false) : '—',
          }));
          tr.appendChild(el('td.text-right.text-sm.font-semibold', { text: C.money(l.partPatient, false) }));
          tb.appendChild(tr);
        });
        t.appendChild(tb);
        tableau.appendChild(t);

        function selection() {
          return lignes.filter(function (l) { return choisies[l.id]; });
        }
        function recalculer() {
          var sel = selection();
          var total = C.sum(sel, 'partPatient');
          var reste = C.sum(lignes, 'partPatient') - total;
          totalLigne.textContent = C.money(total);
          resteLigne.textContent = reste > 0
            ? 'Reste dû après ce règlement : ' + C.money(reste) + ' — '
              + C.num(lignes.length - sel.length) + ' prestation(s) non réglée(s), non exécutable(s).'
            : 'La facture sera intégralement soldée.';
        }

        var corps = el('div.space-y-3', null, [
          U.descList([
            ['Patient', fac.patient], ['Dossier', fac.patientCode],
            ['Prescription', tache.reference],
            ['Montant total', C.money(fac.montantTTC)],
            ['Part assureur', fac.assureur ? C.money(fac.partAssurance) + ' — ' + fac.assureur : 'Sans assurance'],
            ['Déjà réglé', deja.length ? C.money(C.sum(deja, 'partPatient')) + ' — ' + C.num(deja.length) + ' prestation(s)' : 'Rien'],
          ], 'grid-cols-2'),
          lignes.length ? K.note('<strong>Cocher les prestations que le patient règle.</strong> '
            + 'Seules les prestations réglées passent au laboratoire et à la pharmacie — un examen non payé '
            + 'reste en attente, nommément, et le patient pourra revenir l’acquitter.',
          { tone: 'info', icon: 'list-checks' }) : null,
          lignes.length ? tableau : K.note('Cette facture ne porte pas de lignes détaillées — pièce antérieure '
            + 'au règlement par prestation. L’encaissement portera sur le solde global.', { tone: 'warning' }),
          el('div.flex.flex-wrap.items-center.justify-between.gap-3.rounded-lg.bg-slate-50.p-3', null, [
            el('div', null, [
              el('p.text-xs.uppercase.tracking-wide.text-slate-500', { text: 'Montant à encaisser' }),
              totalLigne,
            ]),
            resteLigne,
          ]),
          el('div.grid.gap-3.sm\\:grid-cols-2', null, [
            el('div', null, [el('label.label', { text: 'Mode de règlement' }), selMode]),
            el('div', null, [el('label.label', { text: 'Référence de transaction' }), champRef]),
          ]),
        ].filter(Boolean));

        recalculer();

        var m = U.modal({
          title: 'Encaisser ' + tache.reference, subtitle: fac.numero, size: 'xl', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            lignes.length ? K.btn('Tout cocher', {
              icon: 'check-check',
              onclick: function () {
                lignes.forEach(function (l) { choisies[l.id] = true; });
                [].forEach.call(tableau.querySelectorAll('input[type=checkbox]'), function (c) { c.checked = true; });
                recalculer();
              },
            }) : null,
            K.btn('Valider l’encaissement', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                var sel = selection();
                if (lignes.length && !sel.length) {
                  U.toast('Aucune prestation cochée.', {
                    type: 'error', detail: 'Cocher au moins une prestation à régler.',
                  });
                  return;
                }
                var res;
                try {
                  res = PR.encaisser(fac.id, {
                    lignes: sel.map(function (l) { return l.id; }),
                    montant: lignes.length ? undefined : fac.reliquat,
                    mode: selMode.value, utilisateur: S.currentUser(),
                  });
                } catch (e) { U.toast('Encaissement impossible : ' + e.message, { type: 'error' }); return; }
                if (champRef.value) {
                  S.collection('factures').update(fac.id, { referenceTransaction: champRef.value });
                }
                m.close();
                refresh();
                afficher();

                var suite = (res.demandesLiberees || []).length
                  ? C.num(res.demandesLiberees.length) + ' examen(s) transmis au laboratoire'
                  : null;
                var detail = [];
                if (suite) detail.push(suite);
                if (res.debloquees.indexOf('dispensation') !== -1) detail.push('pharmacie débloquée');
                if (res.restantDu > 0) detail.push('reste ' + C.money(res.restantDu) + ' à régler');

                U.toast('Encaissement validé — ' + C.money(res.montantRegle) + '.', {
                  type: 'success', duration: 9000,
                  detail: detail.join(' · ') || 'Aucune suite à débloquer.',
                });

                /* Le reçu est la pièce que le patient emporte : on la propose
                   immédiatement, elle nomme ce qui est payé et ce qui reste. */
                var mr = U.modal({
                  title: 'Reçu de paiement', subtitle: fac.numero, size: 'md',
                  body: el('div.space-y-3', null, [
                    U.descList([
                      ['Encaissé', C.money(res.montantRegle)],
                      ['Prestations réglées', C.num((res.lignesReglees || []).length)],
                      ['Reste à payer', C.money(res.restantDu)],
                      ['Examens transmis au laboratoire', C.num((res.demandesLiberees || []).length)],
                    ], 'grid-cols-2'),
                    res.restantDu > 0
                      ? K.note('Le patient conserve ce reçu : il nomme les prestations restant dues, '
                        + 'et lui permet de revenir les acquitter sans reprendre toute la facture.',
                      { tone: 'warning' })
                      : null,
                  ].filter(Boolean)),
                  footer: [
                    K.btn('Fermer', { onclick: function () { mr.close(); } }),
                    K.btn('Imprimer le reçu', {
                      variant: 'primary', icon: 'printer',
                      onclick: function () { recuCaisse(S.collection('factures').get(fac.id), res); },
                    }),
                  ],
                });
              },
            }),
          ].filter(Boolean),
        });
        U.icons(corps);
      }

      /** Le reçu de caisse, détaillé — même pièce que celle de la facturation. */
      function recuCaisse(f, res) {
        var lignes = f.lignes || [];
        var payees = lignes.filter(function (l) { return l.statutPaiement === 'paye'; });
        var dues = lignes.filter(function (l) { return l.statutPaiement !== 'paye'; });
        var CAT = { analyse: 'Analyse', medicament: 'Médicament', acte: 'Acte', consultation: 'Consultation' };
        function tab(rows) {
          return P.tableau([
            { label: 'Nature', value: function (l) { return CAT[l.categorie] || l.categorie || '—'; } },
            { label: 'Prestation', key: 'designation' },
            /* La quantité se totalise ; le PRIX UNITAIRE non — additionner des
               prix unitaires ne produit aucune grandeur. */
            { label: 'Qté', align: 'right', somme: function (l) { return l.quantite || 1; },
              formatTotal: function (v) { return C.num(v); },
              value: function (l) { return C.num(l.quantite || 1); } },
            { label: 'P.U.', align: 'right', value: function (l) { return C.money(l.prixUnitaire, false); } },
            { label: 'Part patient', align: 'right',
              somme: function (l) { return l.partPatient || 0; },
              value: function (l) { return C.money(l.partPatient, false); } },
          ], rows, { total: true, totalLabel: 'TOTAL' });
        }
        P.etat({
          titre: 'Reçu de paiement', sousTitre: f.numero,
          cartouche: [['Facture', f.numero], ['Patient', f.patient], ['Dossier', f.patientCode],
            ['Date', C.dateFR(AUJ)], ['Mode de règlement', (f.modePaiement || '—')],
            ['Encaissé par', (f.dernierReglement && f.dernierReglement.encaissePar) || S.currentUser()],
            ['RCCM', C.BRAND.rccm]],
          contenu: el('div.space-y-3', null, [
            payees.length ? el('div', null, [
              el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Prestations réglées' }),
              tab(payees),
            ]) : null,
            dues.length ? el('div', null, [
              el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-danger-700', { text: 'Reste à régler' }),
              tab(dues),
              el('p.mt-1.text-\\[10px\\].italic', {
                text: 'Ces prestations ne sont pas exécutées tant qu’elles ne sont pas réglées.',
              }),
            ]) : null,
            el('p.mt-2.text-\\[10px\\]', {
              text: C.BRAND.formuleArrete + ' : ' + C.montantEnLettres(f.montantPaye || 0) + '.',
            }),
          ].filter(Boolean)),
          signatures: [{ role: 'Le Caissier', mention: 'Signature et cachet' }],
        });
      }

      /* Le détail d'une pièce, prestation par prestation : c'est ce que la
         Direction demande de pouvoir lire au guichet — « quel examen a été
         payé, on doit savoir ». */
      function detailPiece(f2) {
        if (!f2) return;
        var lignes = f2.lignes || [];
        var payees = lignes.filter(function (l) { return l.statutPaiement === 'paye'; });
        var dues = lignes.filter(function (l) { return l.statutPaiement !== 'paye'; });
        function tableau(rows, vide) {
          if (!rows.length) return el('p.text-sm.italic.text-slate-400', { text: vide });
          return K.miniTable(['Nature', 'Prestation', 'Qté', 'Part assureur', 'À la charge du patient'],
            rows.map(function (l) {
              var cat = CATEGORIES_LIGNE[l.categorie];
              return [cat ? cat[0] : (l.categorie || '—'), l.designation, C.num(l.quantite || 1),
                l.partAssureur ? C.money(l.partAssureur) : '—', C.money(l.partPatient)];
            }));
        }
        U.drawer({
          title: f2.numero + ' — ' + f2.patient,
          subtitle: C.dateFR(f2.date) + ' · ' + f2.type,
          body: el('div.space-y-4', null, [
            K.grid([
              ['Pièce', f2.numero], ['Patient', f2.patient + ' — ' + f2.patientCode],
              ['Total de la pièce', C.money(f2.montantTTC)],
              ['Part assureur', f2.partAssurance ? C.money(f2.partAssurance) : '—'],
              ['Part patient', C.money(f2.partPatient)],
              ['Encaissé', C.money(f2.montantPaye)],
              ['Reste dû', C.money(f2.reliquat)],
              ['Base MECeF', f2.baseMecef != null ? C.money(f2.baseMecef) : C.money(f2.montantPaye)],
            ]),
            K.section('Prestations réglées', tableau(payees, 'Aucune prestation réglée à ce jour.')),
            K.section('Reste à régler', tableau(dues, 'Tout est réglé.')),
            dues.length ? K.note('Ces prestations <strong>ne sont pas exécutées</strong> tant qu’elles ne '
              + 'sont pas réglées : le laboratoire et la pharmacie ne les voient pas. Le patient peut revenir '
              + 'les acquitter — le reçu en fait foi.', { tone: 'warning', icon: 'lock' }) : null,
          ].filter(Boolean)),
          footer: [K.btn('Réimprimer le reçu', { variant: 'primary', icon: 'printer',
            onclick: function () { recuCaisse(f2, null); } })],
        });
      }

      var barre = el('div.card');
      var bbody = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      bbody.appendChild(el('div', null, [el('label.label', { text: 'Journée de caisse' }), dateSel]));
      bbody.appendChild(K.btn('Éditer l’arrêté de caisse', { variant: 'primary', icon: 'printer', onclick: function () { imprimer(); } }));
      barre.appendChild(bbody);
      host.appendChild(barre);
      host.appendChild(vue);

      dateSel.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;

      function duJourSel() {
        return factures().filter(function (f) { return C.iso(f.date) === dateSel.value; });
      }

      function afficher() {
        var f = duJourSel();
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Factures émises', value: C.num(f.length), icon: 'receipt', tone: 'navy' },
          { label: 'Chiffre d’affaires', value: C.money(C.sum(f, 'montantTTC')), icon: 'trending-up', tone: 'info' },
          { label: 'Total encaissé', value: C.money(C.sum(f, 'montantPaye')), icon: 'banknote', tone: 'success' },
          { label: 'Reliquats du jour', value: C.money(C.sum(f, 'reliquat')), icon: 'hand-coins', tone: 'warning' },
        ]));

        /* ====================================================================
         * REGISTRE DES PIÈCES DU JOUR
         * --------------------------------------------------------------------
         * Le patient revient avec son reçu : la caisse doit retrouver sa pièce,
         * voir ce qui a été réglé et ce qui reste, et REPRENDRE l'encaissement
         * là où il s'était arrêté. L'arrêté journalier ne le permet pas — c'est
         * un état agrégé.
         * ================================================================== */
        vue.appendChild(U.card('Pièces de la journée — reçus et reliquats',
          U.dataTable({
            rows: C.sortBy(f, 'date').reverse(),
            empty: 'Aucune pièce émise sur cette journée.',
            columns: [
              { key: 'numero', label: 'Pièce' },
              { key: 'patient', label: 'Patient',
                render: function (r) { return r.patient + ' — ' + r.patientCode; } },
              { key: 'type', label: 'Nature' },
              { key: 'detail', label: 'Prestations',
                render: function (r) {
                  var l = r.lignes || [];
                  if (!l.length) return el('span.text-xs.italic.text-slate-400', { text: 'sans détail' });
                  var payees = l.filter(function (x) { return x.statutPaiement === 'paye'; }).length;
                  return el('span.text-xs', {
                    text: payees + ' réglée(s) sur ' + l.length,
                    class: payees === l.length ? 'text-emerald-700' : 'text-amber-700',
                  });
                } },
              { key: 'montantTTC', label: 'Total', align: 'right',
                render: function (r) { return C.money(r.montantTTC); } },
              { key: 'montantPaye', label: 'Encaissé', align: 'right',
                render: function (r) { return C.money(r.montantPaye); } },
              { key: 'reliquat', label: 'Reste dû', align: 'right',
                render: function (r) {
                  return r.reliquat > 0
                    ? el('span.font-semibold.text-amber-700', { text: C.money(r.reliquat) })
                    : U.badge('soldée', 'success');
                } },
            ],
            rowActions: function (r) {
              var actes = [K.iconBtn('printer', 'Réimprimer le reçu détaillé', function () {
                recuCaisse(S.collection('factures').get(r.id), null);
              })];
              /* Reprendre l'encaissement : c'est la demande exacte de la
                 Direction pour le patient qui revient. */
              if (r.reliquat > 0 && K.droits('M8').editer) {
                actes.push(K.btn('Encaisser le reste', {
                  variant: 'primary', size: 'sm', icon: 'coins',
                  onclick: function () {
                    encaisser({ factureId: r.id }, afficher);
                  },
                }));
              }
              actes.push(K.iconBtn('eye', 'Voir le détail des prestations', function () {
                detailPiece(S.collection('factures').get(r.id));
              }));
              return actes;
            },
          })));

        /* Ventilation par mode de règlement */
        var parMode = D.MODES_PAIEMENT.slice(0, 4).map(function (m) {
          var sel = f.filter(function (x) { return x.modePaiement === m.id; });
          return { mode: m.label, nb: sel.length, montant: C.sum(sel, 'montantPaye') };
        });
        vue.appendChild(U.card('Ventilation par mode de règlement', K.miniTable([
          { label: 'Mode de règlement', key: 'mode' },
          { label: 'Opérations', align: 'right', key: 'nb' },
          { label: 'Montant encaissé', align: 'right', render: function (x) { return C.money(x.montant, false); } },
        ], parMode)));

        /* Ventilation par nature */
        var g = C.groupBy(f, 'type');
        var parNature = Object.keys(g).map(function (k) {
          return { nature: k, nb: g[k].length, facture: C.sum(g[k], 'montantTTC'), encaisse: C.sum(g[k], 'montantPaye') };
        });
        vue.appendChild(U.card('Ventilation par nature de prestation', K.miniTable([
          { label: 'Nature', key: 'nature' },
          { label: 'Factures', align: 'right', key: 'nb' },
          { label: 'Facturé', align: 'right', render: function (x) { return C.money(x.facture, false); } },
          { label: 'Encaissé', align: 'right', render: function (x) { return C.money(x.encaisse, false); } },
        ], parNature, { empty: 'Aucune facture pour cette journée.' })));

        vue.appendChild(U.dataTable({
          title: 'Détail des factures du ' + C.dateFR(dateSel.value),
          rows: f, exportName: 'caisse-' + dateSel.value, pageSize: 15,
          emptyMessage: 'Aucune facture émise ce jour.',
          columns: [colNumero, colPatientF,
            { key: 'type', label: 'Nature' },
            colMontant,
            { key: 'montantPaye', label: 'Encaissé', align: 'right', text: function (x) { return C.money(x.montantPaye, false); }, render: function (x) { return C.money(x.montantPaye, false); } },
            { key: 'modePaiement', label: 'Mode', text: function (x) { return modeLabel(x.modePaiement); }, render: function (x) { return U.badge(modeLabel(x.modePaiement), 'navy'); } },
            colStatutPaiement,
          ],
        }));
        U.icons(vue);
      }

      function imprimer() {
        var f = duJourSel();
        var parMode = D.MODES_PAIEMENT.slice(0, 4).map(function (m) {
          var sel = f.filter(function (x) { return x.modePaiement === m.id; });
          return { mode: m.label, nb: sel.length, montant: C.money(C.sum(sel, 'montantPaye'), false) };
        });
        P.etat({
          titre: 'État de caisse journalier',
          sousTitre: 'Journée du ' + C.dateFR(dateSel.value),
          cartouche: [['Date', C.dateFR(dateSel.value)], ['Factures émises', C.num(f.length)],
            ['Chiffre d’affaires', C.money(C.sum(f, 'montantTTC'))],
            ['Total encaissé', C.money(C.sum(f, 'montantPaye'))],
            ['Reliquats', C.money(C.sum(f, 'reliquat'))],
            ['Caissier', S.currentUser()]],
          contenu: el('div.space-y-4', null, [
            el('div', null, [
              el('p.mb-1.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Ventilation par mode de règlement' }),
              P.tableau([
                { label: 'Mode de règlement', key: 'mode' },
                { label: 'Opérations', key: 'nb', align: 'right' },
                { label: 'Montant', key: 'montant', align: 'right', somme: true },
              ], parMode, { total: true }),
            ]),
            el('div', null, [
              el('p.mb-1.mt-3.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Détail des factures' }),
              P.tableau([
                { label: 'N° facture', key: 'numero' },
                { label: 'Patient', key: 'patient' },
                { label: 'Nature', key: 'type' },
                { label: 'Montant', align: 'right', value: function (x) { return C.money(x.montantTTC, false); },
                  somme: function (x) { return x.montantTTC || 0; } },
                { label: 'Encaissé', align: 'right', value: function (x) { return C.money(x.montantPaye, false); },
                  somme: function (x) { return x.montantPaye || 0; } },
                { label: 'Reste', align: 'right', value: function (x) { return C.money(x.reliquat, false); },
                  somme: function (x) { return x.reliquat || 0; } },
              ], f, { total: true }),
            ]),
          ]),
          signatures: [{ role: 'Le Caissier', nom: S.currentUser() },
            { role: 'Le Comptable', nom: 'KASSA Augustin' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });
  /* ==========================================================================
   * FACTURE D'AVOIR — le canal de correction d'une pièce émise (phase 5)
   * --------------------------------------------------------------------------
   * La cible des Instructions : « en cas d'erreur, ou d'opération démarrée
   * puis évacuation dans un autre centre alors que le patient a déjà payé une
   * partie ou tout ». Une pièce émise NE SE MODIFIE PAS et, depuis la phase 5,
   * ne s'annule plus à la caisse : l'avoir la CONTRE-PASSE — pièce numérotée,
   * lignes nommées, écriture inverse en brouillon, registre MECeF alimenté.
   *
   * UNE SEULE COLLECTION (`avoirs`, au socle) pour deux vues : la gestion ici,
   * le registre fiscal dans MECeF. Deux registres auraient divergé au premier
   * avoir.
   * ======================================================================== */
  function colAvoirs() {
    return S.collection('avoirs', { module: 'M8', entite: 'facture d\u2019avoir', prefix: 'AVR' });
  }

  var MOTIFS_AVOIR = ['Erreur de facturation', 'Interruption de soins',
    'Évacuation vers un autre centre', 'Prestation non réalisée', 'Autre (préciser en observations)'];

  var referenceSuivante = C.referenceSuivante;   /* le moteur de série vit au socle (core.js) : mecef.js s'en sert aussi */

  /** La référence d'un avoir est une SÉRIE ANNUELLE lue sur les avoirs déjà émis (écart E8, corrigé le 30/10/2026) : l'ancien
      compteur vivait en mémoire de page et repartait à 1 à chaque chargement — deux avoirs de deux journées pouvaient porter
      le même numéro. Le millésime est celui de la date de l'avoir, plus un « 2026 » écrit en dur. */
  function referenceAvoir(date) {
    return referenceSuivante('AV-' + String(date).slice(0, 4) + '-', 4, colAvoirs().all());
  }

  /** Le moteur d'émission — séparé de la modale pour être SONDABLE.
      Retourne { record, ecritureIds } ou { erreur } : un refus se lit, il ne
      se devine pas. */
  function emettreAvoir(factureId, params) {
    var fac = factures().filter(function (f) { return f.id === factureId; })[0];
    if (!fac) return { erreur: 'Facture introuvable.' };

    /* UNE FILLE CONSOLIDÉE EST FIGÉE : la mère émise porte son numéro, et la
       compagnie détient la pièce. L'avoir est refusé EN NOMMANT la mère. */
    var mere = S.collection('facturesMere').active().filter(function (m) {
      return (m.piecesFilles || []).indexOf(fac.numero) !== -1;
    })[0];
    if (mere) {
      return { erreur: 'La facture ' + fac.numero + ' est consolidée dans la facture mère '
        + mere.numero + ' (' + (mere.compagnie || '') + '), déjà émise : la corriger passerait '
        + 'derrière le dos de la compagnie. Émettre l\u2019avoir au niveau de la mère, par avenant.' };
    }

    var lignes = params.lignes || [];
    if (!lignes.length) return { erreur: 'Un avoir se rapporte à des LIGNES nommées — en cocher au moins une.' };
    var montant = C.sum(lignes, 'montant');
    if (!(montant > 0)) return { erreur: 'Le montant de l\u2019avoir doit être positif.' };

    var dejaAvoirs = colAvoirs().active().filter(function (a) { return a.factureId === fac.id; });
    var dejaMontant = C.sum(dejaAvoirs, 'montant');
    if (montant + dejaMontant > (fac.montantTTC || 0)) {
      return { erreur: 'Le cumul des avoirs (' + C.money(montant + dejaMontant)
        + ') excéderait la facture (' + C.money(fac.montantTTC) + ').' };
    }

    var rec = colAvoirs().insert({
      reference: referenceAvoir(params.date || C.iso(AUJ)),
      date: params.date || C.iso(AUJ),
      factureId: fac.id, factureNumero: fac.numero,
      patientId: fac.patientId, patient: fac.patient, patientCode: fac.patientCode,
      montant: montant,
      motif: params.motif,
      observations: params.observations || '',
      lignesAnnulees: lignes,
      remboursement: params.remboursement || 'creance',
      origine: 'caisse',
      /* Le registre fiscal : une facture normalisée validée exige la
         régularisation MECeF ; une pièce non transmise n'en relève pas. */
      statutMecef: fac.statutMecef === 'valide' ? 'en_attente' : 'sans_objet',
      emisPar: S.currentUser(),
    }).record;

    /* LA CONTRE-PASSATION — écritures PLATES en brouillon, comme partout :
       débit 706 Prestations (la recette diminue), crédit 571 Caisse si l'on
       rembourse en espèces, crédit 411 Clients sinon (la créance diminue). */
    var colEcr = S.collection('ecritures', { module: 'M12', entite: 'écriture' });
    var base = {
      numero: rec.reference, date: rec.date,
      journal: 'CAI', journalLibelle: 'Journal de caisse-dépenses',
      pieceId: rec.id, pieceNumero: rec.reference,
      origine: 'Facture d\u2019avoir',
      statut: 'brouillon',
    };
    var contre = params.remboursement === 'especes'
      ? { compte: '571000', libelle: 'Remboursement en espèces — avoir ' + rec.reference }
      : { compte: '411000', libelle: 'Créance réduite — avoir ' + rec.reference };
    var ecritures = [
      Object.assign({}, base, {
        compte: '706000', compteLibelle: 'Prestations de services',
        libelle: 'Contre-passation — ' + fac.numero + ' (' + params.motif + ')',
        debit: montant, credit: 0,
      }),
      Object.assign({}, base, {
        compte: contre.compte, compteLibelle: contre.compte === '571000' ? 'Caisse' : 'Clients',
        libelle: contre.libelle,
        debit: 0, credit: montant,
      }),
    ];
    var debit = C.sum(ecritures, 'debit'), credit = C.sum(ecritures, 'credit');
    if (debit !== credit) {
      colAvoirs().archive(rec.id);
      return { erreur: 'RG-10 — contre-passation déséquilibrée (débit ' + C.money(debit)
        + ', crédit ' + C.money(credit) + ') : rien n\u2019est écrit.' };
    }
    var ids = ecritures.map(function (l) { return colEcr.insert(l).record.id; });
    colAvoirs().update(rec.id, { ecritureIds: ids });

    /* La facture PORTE ses avoirs — elle n'est jamais réécrite : la pièce
       d'origine et sa correction doivent pouvoir se lire côte à côte. */
    S.collection('factures').update(fac.id, {
      avoirIds: (fac.avoirIds || []).concat([rec.id]),
      montantAvoirs: (fac.montantAvoirs || 0) + montant,
    });

    S.log('Facture d\u2019avoir émise', 'M8', 'Avoir', rec.reference, null,
      { facture: fac.numero, montant: montant, motif: params.motif });
    return { record: colAvoirs().get(rec.id), ecritureIds: ids };
  }
  /* Exposé pour la sonde fonctionnelle : le scénario appelle le moteur, pas
     une copie de sa logique. */
  global.SIGH.emettreAvoir = emettreAvoir;

  global.SIGH.screen('m8-facture-avoir', {
    title: 'Factures d\u2019avoir',
    description: 'Contre-passation d\u2019une pièce émise : erreur, interruption de soins, évacuation après paiement.',
    regle: 'Une pièce émise <strong>ne se modifie ni ne se supprime</strong> — depuis la phase 5, la '
      + 'caisse n\u2019annule plus (matrice cible) : la correction passe par l\u2019<strong>avoir</strong>, '
      + 'pièce numérotée qui nomme ses lignes, contre-passe la recette <strong>en brouillon</strong> '
      + '(RG-10) et alimente le registre MECeF. Une facture <strong>consolidée dans une mère émise</strong> '
      + 'est figée : l\u2019avoir est refusé en nommant la mère.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        C.clear(vue);
        var rows = colAvoirs().active();
        var caisse = rows.filter(function (a) { return a.origine === 'caisse'; });

        vue.appendChild(U.kpiGrid([
          { label: 'Avoirs émis', value: C.num(rows.length), icon: 'undo-2', tone: 'navy' },
          { label: 'Montant contre-passé', value: C.money(C.sum(rows, 'montant')), icon: 'wallet', tone: 'warning' },
          { label: 'Depuis la caisse', value: C.num(caisse.length), icon: 'receipt', tone: 'info',
            hint: 'le registre fiscal MECeF lit la même collection' },
          { label: 'Factures rectifiées', value: C.num(Object.keys(C.groupBy(rows, 'factureNumero')).length),
            icon: 'file-x', tone: 'neutral' },
        ]));

        vue.appendChild(U.dataTable({
          title: 'Registre des avoirs',
          rows: rows, exportName: 'factures-avoir', pageSize: 12, searchable: true,
          defaultSort: 'date', defaultDir: 'desc',
          emptyMessage: 'Aucun avoir émis.',
          emptyHint: 'Un avoir contre-passe une facture émise — erreur, interruption, évacuation.',
          actions: [K.commande('Émettre un avoir', {
            variant: 'primary', size: 'sm', icon: 'undo-2', onclick: ouvrirEmission,
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'N° avoir', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.font-semibold', { text: a.reference }); } },
            { key: 'date', label: 'Date', nowrap: true, text: function (a) { return C.dateFR(a.date); }, render: function (a) { return C.dateFR(a.date); } },
            { key: 'factureNumero', label: 'Facture rectifiée', nowrap: true, render: function (a) { return el('span.font-mono.text-xs', { text: a.factureNumero }); } },
            { key: 'patient', label: 'Client' },
            {
              key: 'montant', label: 'Montant', align: 'right',
              text: function (a) { return C.money(a.montant, false); },
              render: function (a) { return el('span.font-semibold.text-danger-600', { text: '\u2212 ' + C.money(a.montant, false) }); },
            },
            { key: 'motif', label: 'Motif' },
            {
              key: 'remboursement', label: 'Remboursement',
              text: function (a) { return a.remboursement === 'especes' ? 'Espèces' : 'Créance réduite'; },
              render: function (a) {
                return a.remboursement === 'especes'
                  ? U.badge('Espèces rendues', 'warning') : U.badge('Créance réduite', 'info');
              },
            },
            {
              key: 'origine', label: 'Origine',
              render: function (a) { return U.badge(a.origine === 'caisse' ? 'Caisse' : 'MECeF', a.origine === 'caisse' ? 'navy' : 'neutral'); },
            },
          ],
          onRowClick: consulter,
          rowActions: function (a) {
            return [
              K.iconBtn('eye', 'Consulter', function () { consulter(a); }),
              K.iconBtn('printer', 'Imprimer l\u2019avoir', function () { imprimer(a); }),
            ];
          },
        }));
        U.icons(vue);
      }

      function ouvrirEmission() {
        var candidates = C.sortBy(factures().filter(function (f) { return (f.montantTTC || 0) > 0; }),
          'date', 'desc').slice(0, 300);
        if (!candidates.length) { U.toast('Aucune facture à rectifier.', { type: 'warning' }); return; }

        var selFac = U.combo(candidates.map(function (f) {
          return { value: f.id, label: f.numero + ' — ' + (f.patient || 'Sans dossier'),
            detail: C.dateFR(f.date) + ' · ' + C.money(f.montantTTC, false) };
        }), { placeholder: 'Choisir la facture à rectifier', searchPlaceholder: 'Numéro, patient…' });

        var zoneLignes = el('div.mt-3');
        var cases = [];
        function dessinerLignes() {
          C.clear(zoneLignes);
          cases = [];
          var fac = candidates.filter(function (f) { return f.id === selFac.value; })[0];
          if (!fac) { zoneLignes.appendChild(el('p.text-xs.text-slate-400', { text: 'Choisir une facture pour voir ses lignes.' })); return; }
          if (!(fac.lignes || []).length) {
            zoneLignes.appendChild(K.note('Cette pièce ne porte pas de détail par ligne (génération '
              + 'antérieure) : l\u2019avoir portera son MONTANT TOTAL.', { tone: 'warning', icon: 'file-question' }));
            return;
          }
          zoneLignes.appendChild(el('p.label', { text: 'Lignes à contre-passer *' }));
          (fac.lignes || []).forEach(function (l) {
            var cb = el('input.checkbox', { type: 'checkbox' });
            cases.push({ cb: cb, ligne: l });
            zoneLignes.appendChild(el('label.flex.cursor-pointer.items-center.justify-between.gap-3.rounded-lg.border.border-slate-200.px-3.py-2.text-sm', null, [
              el('span.flex.items-center.gap-2', null, [cb, el('span', { text: l.designation })]),
              el('span.num.text-slate-600', { text: C.money(l.montant || l.prixUnitaire || 0, false) }),
            ]));
          });
          U.icons(zoneLignes);
        }
        selFac.addEventListener('change', dessinerLignes);
        dessinerLignes();

        var f2 = U.form([
          { name: 'motif', label: 'Motif de l\u2019avoir', type: 'select', required: true, options: MOTIFS_AVOIR },
          { name: 'remboursement', label: 'Suite donnée', type: 'select', required: true,
            options: [
              { value: 'especes', label: 'Rembourser en espèces (crédit caisse)' },
              { value: 'creance', label: 'Réduire la créance (crédit clients)' },
            ] },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ], { remboursement: 'creance' });

        var m = U.modal({
          title: 'Émettre une facture d\u2019avoir',
          subtitle: 'La pièce d\u2019origine reste intacte ; l\u2019avoir la contre-passe.',
          size: 'lg',
          body: el('div.space-y-3', null, [
            el('div', null, [el('label.label', { text: 'Facture à rectifier *' }), selFac]),
            zoneLignes, f2,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Émettre l\u2019avoir', {
              variant: 'primary', icon: 'undo-2',
              onclick: function () {
                var v = f2.collect(); if (!v) return;
                var fac = candidates.filter(function (f) { return f.id === selFac.value; })[0];
                if (!fac) { U.toast('Choisir la facture à rectifier.', { type: 'error' }); return; }
                var lignes;
                if (cases.length) {
                  lignes = cases.filter(function (x) { return x.cb.checked; }).map(function (x) {
                    return { designation: x.ligne.designation,
                      montant: Number(x.ligne.montant || x.ligne.prixUnitaire || 0) };
                  });
                } else {
                  lignes = [{ designation: 'Avoir total — ' + fac.numero, montant: Number(fac.montantTTC) || 0 }];
                }
                var res = emettreAvoir(fac.id, {
                  lignes: lignes, motif: v.motif,
                  remboursement: v.remboursement, observations: v.observations,
                });
                if (res.erreur) { U.toast('Avoir refusé.', { type: 'error', detail: res.erreur, duration: 9000 }); return; }
                m.close(); afficher();
                U.toast('Avoir ' + res.record.reference + ' émis.', {
                  type: 'success',
                  detail: '\u2212 ' + C.money(res.record.montant) + ' — contre-passation en brouillon.',
                });
                imprimer(res.record);
              },
            }),
          ],
        });
      }

      function consulter(a) {
        U.drawer({
          title: 'Avoir ' + a.reference,
          subtitle: a.factureNumero + ' — ' + (a.patient || ''),
          body: el('div.space-y-4', null, [
            U.descList([
              ['Référence', a.reference], ['Date', C.dateFR(a.date)],
              ['Facture rectifiée', a.factureNumero],
              ['Client', (a.patient || '—') + (a.patientCode ? ' — ' + a.patientCode : '')],
              ['Montant contre-passé', '\u2212 ' + C.money(a.montant)],
              ['Motif', a.motif || '—'],
              ['Suite donnée', a.remboursement === 'especes' ? 'Remboursé en espèces' : 'Créance réduite'],
              ['Registre MECeF', a.statutMecef === 'sans_objet' ? 'Sans objet (pièce non transmise)' : (a.statutMecef || '—')],
              ['Émis par', a.emisPar || '—'],
            ]),
            (a.lignesAnnulees || []).length
              ? K.section('Lignes contre-passées',
                K.miniTable(['Prestation', 'Montant'], a.lignesAnnulees.map(function (l) {
                  return [l.designation, '\u2212 ' + C.money(l.montant, false)];
                })))
              : null,
            K.note('Contre-passation en <strong>brouillon</strong> : débit 706 Prestations, crédit '
              + (a.remboursement === 'especes' ? '571 Caisse' : '411 Clients')
              + '. La validation comptable reste un geste humain.', { tone: 'info', icon: 'scale' }),
          ]),
          footer: [K.btn('Imprimer l\u2019avoir', { icon: 'printer', onclick: function () { imprimer(a); } })],
        });
      }

      function imprimer(a) {
        P.etat({
          titre: 'FACTURE D\u2019AVOIR',
          sousTitre: a.reference + ' — rectifie ' + a.factureNumero,
          filigrane: 'AVOIR',
          cartouche: [['N° avoir', a.reference], ['Date', C.dateFR(a.date)],
            ['Facture rectifiée', a.factureNumero],
            ['Client', a.patient || '—'], ['Motif', a.motif || '—'],
            ['Suite donnée', a.remboursement === 'especes' ? 'Remboursement en espèces' : 'Créance réduite']],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Prestation contre-passée', value: function (l) { return l.designation; } },
              { label: 'Montant', align: 'right',
                value: function (l) { return '\u2212 ' + C.money(l.montant, false); },
                somme: function (l) { return -l.montant; } },
            ], a.lignesAnnulees || []),
            a.observations ? el('p.text-\[10px\].italic', { text: a.observations }) : null,
            el('p.mt-3.text-\[10px\]', { text: 'La présente pièce contre-passe la facture désignée '
              + 'ci-dessus, qui reste au registre. Écriture comptable en brouillon jusqu\u2019à validation.' }),
          ].filter(Boolean)),
          signatures: [{ role: 'Le Comptable' },
            { role: 'La Directrice de l\u2019Administration et des Finances', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

})(window);
