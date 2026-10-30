/* =============================================================================
 * M5 — Laboratoire & Banque de sang
 * -----------------------------------------------------------------------------
 * CDCT §10.2 — demandes d'analyses rattachées au dossier patient et à la
 * facturation, saisie et archivage des résultats, suivi de la consommation de
 * réactifs, carnet de demande de réactifs, banque de sang et donneurs.
 * Le catalogue reprend les 48 désignations du document tarifaire de la clinique.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours,
      L = global.SIGH.labo;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  function patients() { return S.collection('patients').active(); }
  function laborantins() {
    return S.collection('personnel').active()
      .filter(function (e) { return e.fonction === 'tsl'; })
      .map(function (e) { return { value: e.nomComplet, label: e.nomComplet }; });
  }
  function medecins() {
    return S.collection('personnel').active()
      .filter(function (e) { return e.fonction === 'medecin'; })
      .map(function (e) { return { value: e.nomComplet, label: e.nomComplet }; });
  }
  function optionsPatients() {
    return C.sortBy(patients(), 'code').map(function (p) {
      return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
    });
  }
  function optionsAnalyses() {
    return D.ANALYSES.map(function (a) { return { value: a.code, label: a.code + ' — ' + a.designation }; });
  }
  function analyseParCode(code) {
    return D.ANALYSES.filter(function (a) { return a.code === code; })[0] || null;
  }

  /* --- Amorçage ------------------------------------------------------------ */
  function amorcer() {
    var dem = S.collection('demandesAnalyses', { module: 'M5', entite: 'DemandeAnalyse' });
    if (dem.all().length || !S.amorcable('demandesAnalyses')) return;
    var rnd = C.seeded(601);
    var pats = patients(), labs = laborantins(), meds = medecins();
    /* Un répertoire vide ne s'amorce pas : C.pick sur [] rend undefined et l'écran tombait. */
    if (!pats.length || !labs.length || !meds.length) return;
    for (var i = 0; i < 160; i++) {
      var p = C.pick(rnd, pats);
      var a = C.pick(rnd, D.ANALYSES);
      var d = C.addDays(AUJ, -C.between(rnd, 0, 120));
      d.setHours(C.between(rnd, 7, 17), C.pick(rnd, [0, 15, 30, 45]));
      var statut = C.pick(rnd, ['valide', 'valide', 'valide', 'en_cours', 'en_attente']);
      dem.all().push({
        id: 'DEM' + C.pad(i + 1, 4), statut: 'actif',
        reference: 'LAB-' + C.pad(i + 1, 5),
        dateHeure: d.toISOString(),
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        analyseCode: a.code, analyse: a.designation, categorie: a.categorie,
        echantillon: a.echantillon, delai: a.delai, prix: a.prix,
        prescripteur: C.pick(rnd, meds).value,
        laborantin: C.pick(rnd, labs).value,
        etatAnalyse: statut,
        urgent: rnd() > 0.85,
        /* Secteur prescripteur : c'est lui qui commande la visibilité du
           résultat (une sage-femme ne voit que ceux de la maternité). */
        secteurDemandeur: C.pick(rnd, ['MÉDECINE GÉNÉRALE', 'MÉDECINE GÉNÉRALE', 'MATERNITÉ', 'CHIRURGIE', 'HOSPI']),
        origine: 'manuelle',
        resultat: statut === 'valide' ? genResultat(rnd, a) : null,
        conclusion: statut === 'valide' ? C.pick(rnd, ['Normal', 'Normal', 'Anormal', 'À recontrôler']) : null,
      });
    }
    /* LE CODE D'ANALYSE UNIQUE (NNNNN-AAAA), posé dans l'ordre chronologique
       du registre — la série repart à 1 chaque année, comme le papier. */
    var serie = {};
    dem.all().slice().sort(function (a, b) {
      return String(a.dateHeure).localeCompare(String(b.dateHeure));
    }).forEach(function (d2) {
      var annee = String(new Date(d2.dateHeure).getFullYear());
      serie[annee] = (serie[annee] || 0) + 1;
      d2.codeAnalyse = C.pad(serie[annee], 5) + '-' + annee;
    });
    S.save();
  }

  function genResultat(rnd, a) {
    var modeles = {
      'Biochimie': function () { return (0.5 + rnd() * 4).toFixed(2) + ' g/L'; },
      'Hématologie': function () { return C.between(rnd, 8, 16) + ' g/dL'; },
      'Sérologie': function () { return rnd() > 0.82 ? 'Positif' : 'Négatif'; },
      'Parasitologie': function () { return rnd() > 0.7 ? 'Présence de Plasmodium falciparum' : 'Absence de parasite'; },
      'Bactériologie': function () { return rnd() > 0.6 ? 'Culture positive' : 'Culture stérile'; },
      'Hémostase': function () { return C.between(rnd, 20, 45) + ' secondes'; },
      'Immunologie': function () { return C.between(rnd, 1, 90) + ' mg/L'; },
      'Hormonologie': function () { return (rnd() * 25).toFixed(2) + ' ng/mL'; },
      'Immuno-hématologie': function () { return C.pick(rnd, D.GROUPES_SANGUINS); },
      'Andrologie': function () { return C.between(rnd, 10, 90) + ' M/mL'; },
    };
    var f = modeles[a.categorie];
    return f ? f() : 'Résultat disponible';
  }

  /* ==========================================================================
   * DEMANDES D'ANALYSES
   * ======================================================================== */
  function detailDemande(r) {
    var wrap = el('div.space-y-4');
    wrap.appendChild(U.descList([
      ['Référence', el('span.font-mono', { text: r.reference })],
      ['Code d’analyse', r.codeAnalyse
        ? el('span.font-mono.font-semibold.text-navy-800', { text: r.codeAnalyse })
        : el('span.text-xs.text-slate-400', { text: 'antérieur à la série annuelle' })],
      ['Date de la demande', C.dateHeure(r.dateHeure)],
      ['Patient', r.patient], ['Dossier', el('span.font-mono', { text: r.patientCode })],
      ['Analyse', r.analyse], ['Code', el('span.font-mono', { text: r.analyseCode })],
      ['Catégorie', r.categorie], ['Échantillon', r.echantillon],
      ['Tarif', C.money(r.prix)],
      ['Prescripteur', r.prescripteur], ['Laborantin', r.laborantin],
      ['Priorité', r.urgent ? U.badge('Urgent', 'danger') : U.badge('Normale', 'neutral')],
      ['État', U.statut(r.etatAnalyse)],
    ]));
    if (r.resultat) {
      wrap.appendChild(U.card('Résultat', U.descList([
        ['Valeur mesurée', el('span.text-base.font-semibold.text-navy-900', { text: String(r.resultat) })],
        ['Conclusion', r.conclusion === 'Normal' ? U.badge('Normal', 'success') : U.badge(r.conclusion || '—', 'warning')],
      ])));
    } else {
      wrap.appendChild(U.empty('Résultat non encore saisi.', { icon: 'hourglass' }));
    }
    return wrap;
  }

  function etatResultat(r) {
    var p = patients().filter(function (x) { return x.id === r.patientId; })[0];
    P.etat({
      titre: 'Résultat d’analyse de laboratoire',
      sousTitre: r.reference,
      cartouche: [
        ['Patient', r.patient], ['Dossier', r.patientCode],
        ['Âge', C.ageTexte(p)],
        ['Date de prélèvement', C.dateFR(r.dateHeure)],
        ['Prescripteur', r.prescripteur], ['Laborantin', r.laborantin],
      ],
      contenu: el('div.space-y-3', null, [
        P.tableau([
          { label: 'Code', key: 'analyseCode' },
          { label: 'Analyse', key: 'analyse' },
          { label: 'Échantillon', key: 'echantillon' },
          { label: 'Résultat', value: function (x) { return x.resultat || 'En cours'; } },
          { label: 'Conclusion', value: function (x) { return x.conclusion || '—'; } },
        ], [r]),
        el('p.mt-4.text-\\[9px\\].italic.text-slate-500', {
          text: 'Les résultats doivent être interprétés par le médecin prescripteur en fonction du contexte clinique. '
            + 'Ce document est archivé au dossier patient conformément à la politique de conservation de l’établissement.',
        }),
      ]),
      signatures: [{ role: 'Le Laborantin', nom: r.laborantin }, { role: 'Le Biologiste responsable', nom: 'KINNOU Addoul Ganiou' }],
    });
  }

  var colonnesDemande = [
    {
      key: 'reference', label: 'N°', nowrap: true,
      render: function (r) {
        return el('div', null, [
          el('span.font-mono.text-xs', { text: r.reference }),
          /* Le code d'analyse unique NNNNN-AAAA — l'identifiant du registre
             annuel, distinct de la référence interne de la demande. */
          r.codeAnalyse ? el('p.font-mono.text-[10px].text-navy-700', { text: r.codeAnalyse }) : null,
          /* Une demande née d'une ordonnance se distingue d'une saisie du
             laboratoire : la première est prépayée par le parcours, la seconde
             sert les patients adressés par l'exterieur. */
          r.origine === 'ordonnance'
            ? el('p.text-[10px].text-slate-400', { text: r.ordonnanceNumero || 'Ordonnance' })
            : el('p.text-[10px].text-slate-400', { text: 'Saisie laboratoire' }),
        ]);
      },
    },
    {
      key: 'origine', label: 'Origine', nowrap: true,
      value: function (r) {
        if (r.origine === 'ordonnance') return 'Ordonnance';
        if (r.origine === 'service') return 'Fiche de service';
        if (r.origine === 'accueil-externe') return 'Accueil — externe';
        return 'Manuelle';
      },
      render: function (r) {
        if (r.origine === 'service') return U.badge('Fiche de service', 'info');
        if (r.origine === 'accueil-externe') return U.badge('Accueil — externe', 'info');
        if (r.origine !== 'ordonnance') return U.badge('Manuelle', 'neutral');
        return r.bloqueParPaiement ? U.badge('Attente caisse', 'warning') : U.badge('Prépayée', 'success');
      },
    },
    {
      key: 'dateHeure', label: 'Date', nowrap: true,
      text: function (r) { return C.dateFR(r.dateHeure); },
      render: function (r) { return C.dateFR(r.dateHeure); },
      sortValue: function (r) { return C.toDate(r.dateHeure).getTime(); },
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
    {
      key: 'analyse', label: 'Analyse',
      render: function (r) {
        return el('div.min-w-0', null, [
          el('p.truncate.text-sm.text-slate-700', { text: r.analyse }),
          el('p.text-xs.text-slate-400', { text: r.categorie }),
        ]);
      },
    },
    { key: 'echantillon', label: 'Échantillon' },
    { key: 'prescripteur', label: 'Prescripteur' },
    {
      key: 'urgent', label: 'Priorité',
      text: function (r) { return r.urgent ? 'Urgent' : 'Normale'; },
      render: function (r) { return r.urgent ? U.badge('Urgent', 'danger') : el('span.text-xs.text-slate-400', { text: 'Normale' }); },
    },
    { key: 'etatAnalyse', label: 'État', render: function (r) { return U.statut(r.etatAnalyse); } },
  ];

  function champsDemande() {
    return [
      /* PATIENT DU RÉPERTOIRE **OU** ADRESSÉ DE L'EXTÉRIEUR (07/09/2026).
         La saisie manuelle du laboratoire existe précisément POUR les
         patients venus avec une prescription extérieure : exiger un dossier
         préalable renvoyait l'agent ouvrir le dossier ailleurs, puis revenir.
         Le dossier s'ouvre par la fabrique UNIQUE du parcours, la même que
         l'accueil et que l'imagerie. */
      { name: 'patientCode', label: 'Patient (dossier du répertoire)', type: 'select', options: optionsPatients(), col: 'full',
        help: 'Laisser vide pour un patient ADRESSÉ DE L’EXTÉRIEUR — renseigner alors son identité ci-dessous.' },
      { name: '_sectionExterne', type: 'section', label: 'Ou patient adressé de l’extérieur (dossier créé ici)' },
      { name: 'nom', label: 'Nom', col: 'third' },
      { name: 'prenom', label: 'Prénom(s)', col: 'third' },
      { name: 'sexe', label: 'Sexe', type: 'select', col: 'third',
        options: [{ value: 'F', label: 'Féminin' }, { value: 'M', label: 'Masculin' }] },
    ].concat(K.champsAge({ required: false }), [
      { name: 'telephone', label: 'Téléphone', type: 'tel' },
      { name: 'residence', label: 'Quartier / résidence' },
      { name: '_sectionAnalyse', type: 'section', label: 'L’analyse demandée' },
      { name: 'analyseCode', label: 'Analyse demandée', type: 'select', required: true, options: optionsAnalyses(), col: 'full' },
      { name: 'dateHeure', label: 'Date et heure de la demande', type: 'datetime-local', required: true },
    ].concat(K.champsPrescripteur(medecins(), { name: 'prescripteur', label: 'Médecin prescripteur' }), [
      { name: 'laborantin', label: 'Laborantin', type: 'select', options: laborantins() },
      { name: 'urgent', label: 'Analyse urgente', type: 'checkbox' },
      {
        name: 'etatAnalyse', label: 'État', type: 'select', required: true,
        options: [{ value: 'en_attente', label: 'En attente de prélèvement' },
          { value: 'en_cours', label: 'En cours d’analyse' }, { value: 'valide', label: 'Résultat validé' }],
      },
    ]));
  }

  function transformerDemande(v, record) {
    var p = patients().filter(function (x) { return x.code === v.patientCode; })[0];
    /* Pas de dossier choisi : on en OUVRE un, par la fabrique unique du
       parcours — jamais en recopiant ici la création d'un patient. */
    if (!p && String(v.nom || '').trim() && PR.dossierExterne) {
      p = PR.dossierExterne({
        nom: v.nom, prenom: v.prenom, sexe: v.sexe, dateNaissance: v.dateNaissance,
        /* L'âge DÉCLARÉ se transmet à la fabrique : le formulaire le demande (K.champsAge), et le laisser
           tomber ici écrivait un dossier sans âge ni date de naissance (écart E143). */
        age: v.age,
        telephone: v.telephone, residence: v.residence,
        prescripteur: v.prescripteur,
        origineDossier: 'Patient externe — laboratoire',
      }, v.dateHeure || new Date().toISOString());
      v.patientCode = p.code;
      v.origineDemande = 'externe';
    }
    ['nom', 'prenom', 'sexe', 'dateNaissance', 'naissanceConnue', 'age', 'telephone', 'residence'].forEach(function (k) { delete v[k]; });
    if (p) { v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom; }
    var a = analyseParCode(v.analyseCode);
    if (a) {
      v.analyse = a.designation; v.categorie = a.categorie;
      v.echantillon = a.echantillon; v.delai = a.delai; v.prix = a.prix;
    }
    /* Le rang suit le REGISTRE (C.referenceSuivante), jamais un compteur de page : C.nextRef repart à 1 à chaque
       chargement et émettait un LAB-00001 déjà attribué (écart E142). */
    /* À la MODIFICATION, la référence et le code d'analyse déjà attribués sont conservés : le formulaire ne les porte pas,
       et `!v.reference` les faisait réattribuer à chaque édition (écart E149). */
    if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('LAB-', 5, S.collection('demandesAnalyses').all());
    /* Le code d'analyse vient de la fabrique UNIQUE du parcours — le poser
       ici en dur recréerait la règle en deux exemplaires. */
    if (!v.codeAnalyse && PR.codeAnalyse) v.codeAnalyse = (record && record.codeAnalyse) || PR.codeAnalyse(v.dateHeure);
    return v;
  }

  global.SIGH.screen('m5-demandes', {
    title: 'Demandes d’analyses',
    description: 'File des prescriptions de laboratoire, rattachées au dossier patient et à la facturation.',
    regle: 'Les demandes issues d’une ordonnance sont <strong>créées d’office</strong> par le médecin prescripteur : '
      + 'le laboratoire n’a rien à ressaisir. La <strong>saisie manuelle reste ouverte</strong> pour les patients '
      + 'adressés de l’extérieur, à qui le laboratoire remet directement leurs résultats. '
      + 'Un prélèvement ne s’engage qu’après encaissement.',
    actions: function () {
      return [
        K.btn('Saisie des résultats', { icon: 'clipboard-check', onclick: function () { global.SIGH.app.go('m5-resultats'); } }),
        K.btn('Ordonnances', { icon: 'file-text', onclick: function () { global.SIGH.app.go('m2-ordonnances'); } }),
      ];
    },
    render: function (root) {
      amorcer();
      /* Une marge sous la file : sans elle le tableau touche les indicateurs
         qui le suivent, et les deux blocs se lisent comme un seul. */
      var fileWrap = el('div.mb-6');
      root.appendChild(fileWrap);
      fileWrap.appendChild(K.fileAttente('prelevement', {
        titre: 'Prélèvements à réaliser',
        vide: 'Aucun prélèvement en attente.',
        icon: 'flask-conical', action: 'Prendre en charge',
        onAction: function (tache, refresh) {
          var dem = S.collection('demandesAnalyses').all().filter(function (d) {
            return d.ordonnanceId === tache.ordonnanceId;
          });
          dem.forEach(function (d) {
            if (d.etatAnalyse === 'en_attente') S.collection('demandesAnalyses').update(d.id, { etatAnalyse: 'en_cours' });
          });
          PR.terminer(tache.id);
          refresh();
          U.toast(dem.length + ' analyse(s) prise(s) en charge.', {
            type: 'success', detail: 'Saisir les résultats depuis l’écran « Saisie des résultats ».',
          });
        },
      }));
      return K.crud({
        collection: 'demandesAnalyses', entite: 'demande d’analyse', entiteP: 'demandes d’analyses', module: 'M5',
        defaultSort: 'dateHeure', defaultDir: 'desc',
        source: 'Tarifs des analyses de laboratoire de la clinique (48 désignations).',
        columns: colonnesDemande, fields: champsDemande, transform: transformerDemande,
        /* Un refus qui NOMME ce qui manque : sans identité, le résultat ne
           peut être ni remis ni retrouvé — et c'est au patient externe qu'on
           le remet directement. */
        beforeSave: function (v) {
          if (!v.patientCode && !(String(v.nom || '').trim() && String(v.prenom || '').trim())) {
            return 'Sélectionner un patient du répertoire, ou renseigner le nom ET les prénoms du '
              + 'patient adressé de l’extérieur.';
          }
          return null;
        },
        onCreate: function () { return { etatAnalyse: 'en_attente', urgent: false, dateHeure: new Date().toISOString().slice(0, 16) }; },
        filters: [
          {
            name: 'etatAnalyse', label: 'État',
            options: [{ value: 'en_attente', label: 'En attente' }, { value: 'en_cours', label: 'En cours' }, { value: 'valide', label: 'Validé' }],
          },
          { name: 'categorie', label: 'Catégorie', options: Object.keys(C.groupBy(D.ANALYSES, 'categorie')).sort() },
          { name: 'urgent', label: 'Priorité', options: [{ value: 'true', label: 'Urgentes' }], match: function (r) { return !!r.urgent; } },
        ],
        kpis: function (rows) {
          return [
            { label: 'Demandes enregistrées', value: C.num(rows.length), icon: 'flask-conical', tone: 'navy' },
            { label: 'En attente de prélèvement', value: C.num(rows.filter(function (r) { return r.etatAnalyse === 'en_attente'; }).length), icon: 'hourglass', tone: 'warning' },
            { label: 'Urgentes', value: C.num(rows.filter(function (r) { return r.urgent && r.etatAnalyse !== 'valide'; }).length), icon: 'siren', tone: 'danger' },
            { label: 'Recette laboratoire', value: C.money(C.sum(rows, 'prix')), icon: 'coins', tone: 'success' },
          ];
        },
        detail: detailDemande,
        etat: function (r) {
          if (r.etatAnalyse === 'valide') { etatResultat(r); return; }
          P.etat({
            titre: 'Bon de prélèvement',
            sousTitre: r.reference,
            cartouche: [['Patient', r.patient], ['Dossier', r.patientCode],
              ['Date', C.dateFR(r.dateHeure)], ['Prescripteur', r.prescripteur],
              ['Priorité', r.urgent ? 'URGENT' : 'Normale']],
            contenu: P.tableau([
              { label: 'Code', key: 'analyseCode' }, { label: 'Analyse', key: 'analyse' },
              { label: 'Échantillon', key: 'echantillon' },
              { label: 'Tarif', align: 'right', value: function (x) { return C.money(x.prix, false); } },
            ], [r]),
            signatures: [{ role: 'Le Médecin prescripteur', nom: r.prescripteur }, { role: 'Le Laborantin' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * SAISIE DES RÉSULTATS
   * ======================================================================== */
  global.SIGH.screen('m5-resultats', {
    title: 'Saisie des résultats',
    description: 'Enregistrement, validation biologique et archivage numérique des résultats d’analyses.',
    regle: 'Un résultat d’analyse n’est pas visible de tous. <strong>Le médecin y accède intégralement</strong> ; '
      + 'la <strong>sage-femme</strong> aux seuls résultats demandés par son secteur ; '
      + 'l’<strong>infirmier</strong>, l’<strong>aide-soignant</strong> et l’<strong>accueil</strong> n’y accèdent pas. '
      + 'Le laboratoire produit les résultats et les remet directement aux patients adressés de l’extérieur. '
      + 'Ce qui est masqué est <strong>signalé comme tel</strong>, jamais présenté comme absent.',
    render: function (root) {
      amorcer();
      var col = S.collection('demandesAnalyses', { module: 'M5', entite: 'ResultatAnalyse' });
      var host = el('div.space-y-4');
      var table;
      var cap = PR.capacites();

      /* Périmètre de l'agent connecté : le filtre porte sur les DONNÉES, pas
         seulement sur l'accès à l'écran. */
      function visibles() {
        return PR.filtrerResultats(col.active());
      }
      function masques() {
        return col.active().length - visibles().length;
      }
      /* Le filtre de date — une DATE ou une PLAGE, pas un tri. « Quand on tape
         21 août, ce sont seulement les demandes du 21 août qui apparaissent. » */
      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });

      function dansPlage(r) {
        var d = String(r.dateHeure || r.date || '').slice(0, 10);
        if (dDebut.value && d < dDebut.value) return false;
        if (dFin.value && d > dFin.value) return false;
        return true;
      }
      function filtrees() { return visibles().filter(dansPlage); }

      function aTraiter() {
        return filtrees().filter(function (r) {
          return ['en_attente', 'attente_prelevement', 'preleve', 'en_cours', 'saisi'].indexOf(r.etatAnalyse) !== -1;
        });
      }

      /* ------------------------------------------------------------------
       * QUAND LA SAISIE EST-ELLE OUVERTE ?
       * ------------------------------------------------------------------
       * Seulement sur un échantillon PARVENU au laboratoire. Le circuit
       * décrit par le biologiste est formel : consultation, bon d'analyse,
       * caisse, salle de prélèvement, acheminement, PUIS saisie. Ouvrir la
       * saisie plus tôt permettrait de rendre un résultat pour un prélèvement
       * qui n'a pas eu lieu.
       *
       * La demande reste VISIBLE — le laboratoire a besoin de voir ce qui
       * arrive — mais le bouton dit pourquoi il ne s'ouvre pas et à quel
       * poste la balle se trouve.
       * ---------------------------------------------------------------- */
      var BLOCAGES_SAISIE = {
        en_attente: {
          motif: 'La demande est en attente de règlement.',
          suite: 'Le patient doit d’abord passer à la caisse.',
        },
        attente_prelevement: {
          motif: 'Le prélèvement n’a pas encore été fait.',
          suite: 'La salle de prélèvement doit appeler le patient, puis acheminer l’échantillon.',
        },
        preleve: {
          motif: 'L’échantillon est prélevé mais pas encore parvenu au laboratoire.',
          suite: 'La salle de prélèvement doit le transmettre avec son bon.',
        },
      };
      function blocageSaisie(r) { return BLOCAGES_SAISIE[r.etatAnalyse] || null; }
      /* La fenêtre de relecture : saisi et validé techniquement, pas encore
         rendu au prescripteur. */
      function aValiderBio() {
        return filtrees().filter(function (r) { return r.etatAnalyse === 'valide_technique'; });
      }
      function valides() {
        return filtrees().filter(function (r) { return D.resultatRendu(r.etatAnalyse); });
      }

      /* La barre de dates. Les raccourcis évitent la saisie la plus fréquente. */
      var barreDates = el('div.card');
      barreDates.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'Au' }), dFin]),
        K.btn('Aujourd’hui', {
          icon: 'calendar',
          onclick: function () { dDebut.value = C.iso(AUJ); dFin.value = C.iso(AUJ); afficher(); },
        }),
        K.btn('Sept derniers jours', {
          icon: 'calendar-days',
          onclick: function () { dDebut.value = C.iso(C.addDays(AUJ, -6)); dFin.value = C.iso(AUJ); afficher(); },
        }),
        K.btn('Toutes les dates', {
          icon: 'x',
          onclick: function () { dDebut.value = ''; dFin.value = ''; afficher(); },
        }),
      ]));
      [dDebut, dFin].forEach(function (x) { x.addEventListener('change', afficher); });
      host.appendChild(barreDates);

      var vue = el('div.space-y-4');
      host.appendChild(vue);

      function afficher() {
      C.clear(vue);
      vue.appendChild(U.kpiGrid([
        { label: 'Résultats à saisir', value: C.num(aTraiter().length), icon: 'file-pen-line', tone: 'warning' },
        {
          label: 'À valider biologiquement', value: C.num(aValiderBio().length),
          icon: 'shield-check', tone: aValiderBio().length ? 'navy' : 'neutral',
          hint: 'Non visibles du prescripteur',
        },
        { label: 'Rendus au prescripteur', value: C.num(valides().length), icon: 'file-check-2', tone: 'success' },
        {
          label: 'Rectifiés',
          value: C.num(valides().filter(function (r) { return r.etatAnalyse === 'rectifie'; }).length),
          icon: 'history', tone: 'danger', hint: 'Version rectificative émise',
        },
      ]));

      /* Ce qui est masqué doit être annoncé : sans cela, l'agent croit à une
         donnée manquante au lieu d'une restriction, et rouvre un ticket. */
      var secteur = PR.secteurCourant();
      if (cap.voirResultats === 'aucun') {
        vue.appendChild(K.note('<strong>' + cap.label + ' — aucun résultat d’analyse ne vous est accessible.</strong> '
          + (cap.note || '') + ' Les ' + C.num(col.active().length) + ' résultats du laboratoire existent : '
          + 'ils sont réservés aux prescripteurs. Pour en obtenir un, en faire la demande au médecin.',
        { tone: 'warning', icon: 'shield-alert' }));
      } else if (cap.voirResultats === 'secteur') {
        vue.appendChild(K.note('<strong>' + cap.label + ' — périmètre limité à ' + (secteur ? secteur.libelle : 'votre secteur') + '.</strong> '
          + C.num(masques()) + ' résultat(s) demandé(s) par d’autres secteurs sont masqués : '
          + 'ils ne relèvent pas de votre suivi.', { tone: 'info', icon: 'shield-check' }));
      } else if (cap.voirResultats === 'produits') {
        vue.appendChild(K.note('<strong>Laboratoire.</strong> Vous produisez ces résultats et les remettez '
          + 'directement aux patients adressés de l’extérieur ; ceux des patients internes vont au médecin prescripteur.',
        { tone: 'info', icon: 'flask-conical' }));
      }

      vue.appendChild(K.note('<strong>Deux verrous.</strong> La <strong>validation technique</strong> atteste la '
        + 'saisie ; le prescripteur ne voit encore rien. La <strong>validation biologique</strong> rend le '
        + 'résultat opposable — c’est elle qui le porte au dossier du médecin. Entre les deux, le laboratoire '
        + 'relit. Après elle, une correction devient une <strong>rectification versionnée</strong>, et le '
        + 'prescripteur est averti que ce qu’il a lu a changé.', { tone: 'info', icon: 'shield-check' }));

      vue.appendChild(U.tabs([
        {
          id: 'attente', label: 'À saisir', badge: aTraiter().length,
          render: function () {
            table = U.dataTable({
              rows: aTraiter, exportName: 'resultats-a-saisir', pageSize: 12,
              emptyMessage: 'Aucun résultat en attente de saisie.',
              columns: colonnesDemande,
              /* Un bouton désactivé que le clic sur la ligne contournerait ne
                 protégerait rien. */
              onRowClick: function (r) {
                var bloc = blocageSaisie(r);
                if (bloc) {
                  U.toast('Saisie impossible.', { type: 'error', detail: bloc.motif + ' ' + bloc.suite });
                  return;
                }
                ouvrirSaisie(r);
              },
              rowActions: function (r) {
                var bloc = blocageSaisie(r);
                if (bloc) {
                  /* Désactivé, et non masqué : le laboratoire doit voir ce qui
                     lui arrive, et savoir chez qui la demande est bloquée. */
                  var b = K.btn('Saisir le résultat', {
                    size: 'sm', icon: 'lock',
                    title: bloc.motif + ' ' + bloc.suite,
                    onclick: function () {
                      U.toast('Saisie impossible.', { type: 'error',
                        detail: bloc.motif + ' ' + bloc.suite });
                    },
                  });
                  b.classList.add('opacity-50', 'cursor-not-allowed');
                  b.setAttribute('aria-disabled', 'true');
                  return [b];
                }
                return [K.btn('Saisir le résultat', { size: 'sm', variant: 'primary', icon: 'file-pen-line', onclick: function () { ouvrirSaisie(r); } })];
              },
            });
            return table;
          },
        },
        {
          id: 'relecture', label: 'À valider biologiquement', badge: aValiderBio().length,
          render: function () {
            var cap2 = PR.capacites();
            var peut = !!cap2.validerBiologique;
            var interim = cap2.validerBiologique === 'interim';
            var bloc = el('div.space-y-3');

            bloc.appendChild(K.note(peut
              ? (interim
                ? '<strong>Validation par intérim.</strong> Vous portez la validation biologique en l’absence '
                  + 'du biologiste médical. Votre qualité d’intérimaire sera <strong>portée sur le compte '
                  + 'rendu</strong> : la pièce doit dire qui a signé, et à quel titre.'
                : '<strong>Validation biologique.</strong> Relire l’ensemble avant de valider : au-delà, le '
                  + 'résultat est visible du prescripteur, et toute correction devient une rectification '
                  + 'versionnée dont il sera averti.')
              : '<strong>' + cap2.label + ' — vous n’êtes pas habilité à porter la validation biologique.</strong> '
                + 'Ces résultats attendent le biologiste médical. Ils sont saisis et techniquement validés, '
                + 'mais le prescripteur ne les voit pas encore.',
            { tone: peut ? (interim ? 'warning' : 'info') : 'warning', icon: 'shield-check' }));

            bloc.appendChild(U.dataTable({
              rows: aValiderBio, exportName: 'resultats-a-valider', pageSize: 12,
              emptyMessage: 'Aucun résultat en attente de validation biologique.',
              defaultSort: 'valideTechniqueLe', defaultDir: 'desc',
              columns: colonnesDemande.slice(0, 4).concat([
                {
                  key: 'resultat', label: 'Résultat saisi',
                  render: function (r) { return el('span.text-sm.text-slate-700', { text: String(r.resultat || '—') }); },
                },
                {
                  key: 'conclusion', label: 'Conclusion',
                  render: function (r) {
                    return r.conclusion === 'Normal' ? U.badge('Normal', 'success') : U.badge(r.conclusion || '—', 'warning');
                  },
                },
                { key: 'valideTechniquePar', label: 'Validation technique' },
              ]),
              onRowClick: function (r) {
                U.drawer({
                  title: r.analyse, subtitle: r.patient + ' — ' + r.reference,
                  body: detailDemande(r),
                  footer: [K.btn('Relire et corriger', { icon: 'pencil', onclick: function () { ouvrirSaisie(r); } })],
                });
              },
              rowActions: function (r) {
                /* LA CONTINUITÉ VAUT AUSSI POUR LA RELECTURE. Corriger un
                   résultat avant sa validation, c'est décider de ce qui sera
                   validé : laisser ce geste à un tiers viderait la règle de
                   son sens — il suffirait de corriger la saisie d'un collègue
                   puis de le laisser signer. */
                var moi = S.session() || {};
                var cont = PR.continuiteRespectee(r, {
                  id: moi.employeId || moi.id || null,
                  nomComplet: moi.nomComplet || moi.nom || '',
                });
                var actes = [];
                if (cont.ok) {
                  actes.push(K.iconBtn('pencil', 'Relire et corriger avant validation',
                    function () { ouvrirSaisie(r); }));
                } else {
                  /* Désactivé et NOMMANT le préleveur : un bouton absent
                     laisserait croire à un défaut d'affichage, un bouton qui
                     nomme envoie au bon collègue. */
                  var verrou = K.iconBtn('lock',
                    'Prélevé par ' + (cont.preleveur || 'un autre agent') + ' — à lui de relire',
                    function () {
                      U.toast('Relecture réservée au préleveur.', { type: 'error', detail: cont.motif });
                    });
                  verrou.classList.add('opacity-50', 'cursor-not-allowed');
                  verrou.setAttribute('aria-disabled', 'true');
                  actes.push(verrou);
                }
                if (peut && cont.ok) {
                  actes.push(K.btn(interim ? 'Valider par intérim' : 'Validation biologique', {
                    size: 'sm', variant: 'primary', icon: 'shield-check',
                    onclick: function () { validerBio(r, interim); },
                  }));
                }
                return actes;
              },
              bulkActions: peut ? function (getSelected, clear) {
                return [K.btn('Valider la sélection', {
                  size: 'sm', variant: 'primary', icon: 'shield-check',
                  onclick: function () {
                    var sel = getSelected();
                    if (!sel.length) return;
                    U.confirm({
                      title: 'Valider biologiquement ' + C.num(sel.length) + ' résultat(s) ?',
                      message: 'Une fois validés, ces résultats sont <strong>visibles du prescripteur</strong> '
                        + 'et font foi. Toute correction ultérieure donnera une version rectificative dont il '
                        + 'sera averti.<br><br>Avez-vous relu l’ensemble ?',
                      confirmLabel: 'Valider biologiquement',
                    }).then(function (ok) {
                      if (!ok) return;
                      var n = 0;
                      sel.forEach(function (r) {
                        try { PR.validerBiologique(r.id, { utilisateur: S.currentUser() }); n++; }
                        catch (e) { /* une demande déjà validée entre-temps */ }
                      });
                      clear(); afficher();
                      U.toast(C.num(n) + ' résultat(s) validé(s) biologiquement.', {
                        type: 'success', detail: 'Les prescripteurs en sont notifiés.',
                      });
                    });
                  },
                })];
              } : null,
            }));
            return bloc;
          },
        },
        {
          id: 'valides', label: 'Rendus au prescripteur', badge: valides().length,
          render: function () {
            return U.dataTable({
              rows: valides, exportName: 'resultats-valides', pageSize: 12,
              defaultSort: 'dateHeure', defaultDir: 'desc',
              columns: colonnesDemande.slice(0, 4).concat([
                { key: 'resultat', label: 'Résultat', render: function (r) { return el('span.font-semibold.text-navy-800', { text: String(r.resultat || '—') }); } },
                {
                  key: 'conclusion', label: 'Conclusion',
                  render: function (r) { return r.conclusion === 'Normal' ? U.badge('Normal', 'success') : U.badge(r.conclusion || '—', 'warning'); },
                },
                {
                  key: 'valideBiologiquePar', label: 'Validation biologique',
                  render: function (r) {
                    return el('div.min-w-0', null, [
                      el('p.truncate.text-sm', { text: r.valideBiologiquePar || r.laborantin || '—' }),
                      r.validationInterim
                        ? el('p.text-xs.text-warning-700', { text: 'par intérim' })
                        : null,
                    ].filter(Boolean));
                  },
                },
                {
                  key: 'version', label: 'Version', align: 'right',
                  value: function (r) { return r.version || 1; },
                  render: function (r) {
                    if (r.etatAnalyse !== 'rectifie') return el('span.text-xs.text-slate-400', { text: 'v1' });
                    return U.badge('v' + (r.version || 2) + ' — rectifié', 'danger');
                  },
                },
              ]),
              onRowClick: function (r) { U.drawer({ title: r.analyse, subtitle: r.patient + ' — ' + r.reference, body: detailDemande(r), footer: [K.btn('Imprimer', { variant: 'primary', icon: 'printer', onclick: function () { etatResultat(r); } })] }); },
              rowActions: function (r) {
                return [
                  K.iconBtn('file-text', 'Compte rendu complet du patient', function () {
                    compteRendu(r.patientId, col.active().filter(function (d) { return d.patientId === r.patientId; }));
                  }),
                  K.iconBtn('printer', 'Imprimer ce seul résultat', function () { etatResultat(r); }),
                  K.iconBtn('pencil', 'Corriger', function () { ouvrirSaisie(r); }),
                ];
              },
              /* « Imprimer les résultats en bloc » : ce que le laboratoire
                 veut sortir n'est pas une liste de lignes mais LE COMPTE
                 RENDU — tous les examens du patient, groupés par section,
                 comme la pièce du dossier 2026080411. */
              bulkActions: function (getSelected, clear) {
                return [K.btn('Compte rendu de la sélection', {
                  size: 'sm', variant: 'primary', icon: 'file-text',
                  onclick: function () {
                    var sel = getSelected();
                    if (!sel.length) return;
                    var vus = {};
                    sel.forEach(function (r) { vus[r.patientId] = true; });
                    var ids = Object.keys(vus);
                    if (ids.length > 1) {
                      U.toast('Un compte rendu porte sur un seul patient.', {
                        type: 'error',
                        detail: C.num(ids.length) + ' patients dans la sélection. Restreindre la recherche à '
                          + 'un nom avant d’imprimer — un compte rendu mêlant deux dossiers serait ininterprétable.',
                      });
                      return;
                    }
                    compteRendu(ids[0], sel);
                    clear();
                  },
                })];
              },
            });
          },
        },
      ]));
      U.icons(vue);
      }

      afficher();
      root.appendChild(host);
      return null;

      /* ====================================================================
       * LE SECOND VERROU
       * ================================================================== */
      function validerBio(r, interim) {
        /* CONTINUITÉ — celui qui a prélevé valide. La clinique compte deux
         biologistes : la règle a un effet réel. Le refus NOMME le préleveur,
         faute de quoi on chercherait la panne du côté du logiciel. */
      var sess = S.session() || {};
      var cont = PR.continuiteRespectee ? PR.continuiteRespectee(r, {
        id: sess.soignantId || sess.id, nomComplet: sess.nom,
      }) : { ok: true };
      if (!cont.ok) { U.toast(cont.motif, { type: 'error' }); return; }

        U.confirm({
          title: interim ? 'Valider par intérim ?' : 'Validation biologique',
          message: 'Le résultat de <strong>' + r.analyse + '</strong> pour ' + r.patient
            + ' deviendra <strong>visible du prescripteur</strong> et fera foi.<br><br>'
            + (interim
              ? 'Vous portez cette validation <strong>en l’absence du biologiste médical</strong> : '
                + 'votre qualité d’intérimaire sera portée sur le compte rendu.<br><br>'
              : '')
            + 'Au-delà, une correction donnera une <strong>version rectificative</strong> et le prescripteur '
            + 'sera averti que ce qu’il a lu a changé. Avez-vous relu l’ensemble des valeurs ?',
          confirmLabel: interim ? 'Valider par intérim' : 'Valider biologiquement',
        }).then(function (ok) {
          if (!ok) return;
          var res;
          try { res = PR.validerBiologique(r.id, { utilisateur: S.currentUser() }); }
          catch (e) { U.toast('Validation impossible : ' + e.message, { type: 'error' }); return; }
          afficher();
          U.toast('Validation biologique portée.', {
            type: 'success', duration: 8000,
            detail: (res.interim ? 'Intérim tracé sur la pièce. ' : '')
              + 'Le prescripteur ' + (r.prescripteur || '') + ' en est notifié.',
            undo: function () { res.undo(); afficher(); },
          });
        });
      }

      /* ====================================================================
       * LA RECTIFICATION APRÈS VALIDATION BIOLOGIQUE
       * --------------------------------------------------------------------
       * « Peut-être qu'il a déjà lu le premier, et c'est pas cool. » — La
       * version sortante est conservée, la nouvelle numérotée, et le
       * prescripteur averti. Écraser en silence laisserait le médecin avec
       * une valeur qui n'existe plus nulle part.
       * ================================================================== */
      function demanderRectification(r, valeurs, commentaire) {
        var f = U.form([
          {
            name: 'motif', label: 'Motif de la rectification', type: 'textarea', rows: 2,
            required: true, col: 'full',
            hint: 'Ce motif figure sur la version rectificative et dans la notification au prescripteur.',
          },
        ], {});

        var m = U.modal({
          title: 'Rectifier un résultat déjà rendu',
          subtitle: r.analyse + ' — ' + r.patient,
          size: 'md',
          body: el('div.space-y-3', null, [
            el('div.flex.items-start.gap-3.rounded-lg.border.border-danger-200.bg-danger-50.p-3', null, [
              el('span.shrink-0.text-danger-600', null, C.icon('alert-triangle', 'h-5 w-5')),
              el('div.min-w-0', null, [
                el('p.text-sm.font-semibold.text-danger-900', {
                  text: 'Ce résultat a déjà été validé biologiquement.',
                }),
                el('p.mt-1.text-xs.text-danger-800', {
                  text: 'Le prescripteur ' + (r.prescripteur || '') + ' a pu le lire. La version actuelle sera '
                    + 'CONSERVÉE, la correction deviendra la version ' + ((r.version || 1) + 1)
                    + ', et une notification lui sera adressée pour l’avertir que ce qu’il a lu a changé.',
                }),
              ]),
            ]),
            U.descList([
              ['Validé le', r.valideLe ? C.dateHeure(new Date(r.valideLe)) : '—'],
              ['Validé par', r.valideBiologiquePar || '—'],
              ['Version actuelle', 'v' + (r.version || 1)],
              ['Nouvelle version', 'v' + ((r.version || 1) + 1)],
            ], 'grid-cols-2'),
            f,
          ]),
          footer: [
            K.btn('Renoncer', { onclick: function () { m.close(); } }),
            K.btn('Émettre la rectification', {
              variant: 'danger', icon: 'history',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var res;
                try {
                  res = PR.rectifierResultat(r.id, valeurs, {
                    motif: v.motif, commentaireGeneral: commentaire, utilisateur: S.currentUser(),
                  });
                } catch (e) { U.toast('Rectification impossible : ' + e.message, { type: 'error' }); return; }
                m.close();
                afficher();
                U.toast('Version rectificative v' + res.version + ' émise.', {
                  type: 'warning', duration: 9000,
                  detail: 'Le prescripteur ' + (r.prescripteur || '') + ' est notifié que le résultat a changé. '
                    + 'La version précédente reste consultable.',
                });
              },
            }),
          ],
        });
      }

      /* ====================================================================
       * SAISIE STRUCTURÉE D'UN RÉSULTAT
       * --------------------------------------------------------------------
       * Le prototype rendait un résultat sous la forme d'UN champ de texte
       * libre. Le biologiste l'a signalé : « les variables qui doivent être
       * attribuées pour chaque examen, les sous-variables ne sont pas
       * insérées », « les unités ne sont pas mises ».
       *
       * Le laborantin ne porte désormais QUE la mesure. L'unité, la borne de
       * référence et le contrôle de normalité viennent du paramétrage — et
       * l'écart s'affiche à la saisie, pas seulement à l'impression.
       * ================================================================== */
      function ouvrirSaisie(r) {
        var code = codeExamenDe(r);
        var variables = variablesDe(code).filter(function (v) { return v.actif !== false; });

        if (!variables.length) {
          U.toast('Aucune variable paramétrée pour cet examen.', {
            type: 'error',
            detail: 'Définir ses variables à l’écran « Valeurs de référence » avant de saisir un résultat.',
          });
          return;
        }

        var saisies = Object.assign({}, r.valeurs || {});
        var corps = el('div.space-y-3');

        /* LES DEUX IDENTIFIANTS DU DOSSIER, EN TÊTE DE LA SAISIE (06/09/2026).
           Ils ne s'y lisaient nulle part, alors que ce sont EUX qu'on compare
           au bon papier posé à côté de l'automate : le CODE D'ANALYSE
           (NNNNN-AAAA) identifie le dossier au registre annuel, la RÉFÉRENCE
           (LAB-NNNNN) identifie la demande dans le logiciel. Saisir un
           résultat sans les voir, c'est risquer de le porter au dossier du
           patient précédent. */
        corps.appendChild(U.descList([
          ['Code d’analyse', el('span.font-mono.text-base.font-semibold.text-navy-900',
            { text: r.codeAnalyse || '— non attribué' })],
          ['Référence de la demande', el('span.font-mono', { text: r.reference || '—' })],
          ['Patient', r.patient + ' (' + r.patientCode + ')'],
          ['Examen', r.analyse],
          ['Prélevé le', r.preleveLe ? C.dateFR(r.preleveLe) + ' à ' + C.heure(r.preleveLe) : '—'],
          ['Prescripteur', r.prescripteur || '—'],
        ]));

        corps.appendChild(U.descList([
          ['Patient', r.patient], ['Dossier', r.patientCode],
          ['Examen', r.analyse], ['Échantillon', r.echantillon || '—'],
          ['Prescripteur', r.prescripteur || '—'],
          ['Demandé le', r.dateHeure ? C.dateHeure(r.dateHeure) : '—'],
        ], 'grid-cols-2'));

        var tableau = el('div.max-h-\[24rem\].overflow-auto.rounded-lg.border.border-slate-200');
        var t = el('table.tbl');
        t.appendChild(el('thead', null, el('tr', null, [
          el('th', { text: 'Variable' }),
          el('th', { text: 'Résultat' }),
          el('th.text-right', { text: 'Unité' }),
          el('th.text-right', { text: 'Références' }),
          el('th.text-right', { text: 'Écart' }),
        ])));
        var tb = el('tbody');

        variables.forEach(function (v) {
          var tr = el('tr');
          tr.appendChild(el('td', null, el('div.min-w-0', null, [
            el('p.text-sm', {
              class: v.parent ? 'pl-4 text-slate-600' : 'font-medium text-slate-800',
              text: (v.parent ? '↳ ' : '') + v.libelle,
            }),
            v.accompagnement ? el('p.text-xs.text-slate-400', { text: L.type(v.type) }) : null,
          ].filter(Boolean))));

          var champ = champDeVariable(v, saisies[v.code]);
          tr.appendChild(el('td', null, champ.noeud));

          tr.appendChild(el('td.text-right', null,
            el('span.font-mono.text-xs.text-slate-500', { text: symbole(v.unite) })));
          tr.appendChild(el('td.text-right', null,
            el('span.text-xs', {
              class: v.aValider ? 'text-warning-700' : 'text-slate-500',
              /* La référence affichée est celle du LOT en service à la date
                 de la demande — pas forcément celle de la variable. */
              text: referenceALaDate(v, r.dateHeure) || '—',
            })));

          var cellEcart = el('td.text-right');
          tr.appendChild(cellEcart);

          function evaluer() {
            saisies[v.code] = champ.valeur();
            C.clear(cellEcart);
            var e = L.ecart(variableALaDate(v, r.dateHeure), saisies[v.code]);
            if (!e) {
              if (saisies[v.code]) cellEcart.appendChild(U.badge('Normal', 'success'));
              return;
            }
            var libelles = { bas: ['Bas', 'info'], haut: ['Haut', 'danger'], anormal: ['Anormal', 'danger'] };
            cellEcart.appendChild(U.badge(libelles[e][0], libelles[e][1]));
          }
          champ.onChange(evaluer);
          evaluer();
          tb.appendChild(tr);
        });

        t.appendChild(tb);
        tableau.appendChild(t);
        corps.appendChild(tableau);

        /* Le commentaire GÉNÉRAL porte sur l'échantillon, pas sur un examen :
           c'est là qu'on écrit « hémolysé — reprendre le prélèvement ». */
        var selMotif = el('select.select');
        selMotif.appendChild(el('option', { value: '' }, 'Aucun commentaire général'));
        L.MOTIFS_COMMENTAIRE_GENERAL.forEach(function (x) {
          selMotif.appendChild(el('option', { value: x }, x));
        });
        var txtGeneral = el('textarea.input', { rows: 2, placeholder: 'Commentaire libre sur l’échantillon ou le compte rendu' });
        selMotif.addEventListener('change', function () {
          if (selMotif.value) txtGeneral.value = selMotif.value;
        });

        var selValideur = el('select.select');
        laborantins().forEach(function (x) {
          selValideur.appendChild(el('option', { value: x.value || x }, x.label || x));
        });

        corps.appendChild(U.card('Commentaire général du compte rendu', el('div.space-y-2', null, [
          K.note('À ne pas confondre avec le commentaire d’un examen : celui-ci porte sur '
            + 'l’<strong>échantillon</strong> et le compte rendu — « hémolysé, reprendre le prélèvement » — '
            + 'et non sur l’interprétation d’un résultat.', { tone: 'info' }),
          selMotif, txtGeneral,
        ])));

        corps.appendChild(el('div', null, [
          el('label.label', { text: 'Validé par' }), selValideur,
        ]));

        var m = U.modal({
          title: 'Saisie du résultat — ' + r.analyse,
          subtitle: (r.codeAnalyse ? 'Code ' + r.codeAnalyse + ' · ' : '')
            + (r.reference ? r.reference + ' · ' : '') + r.patient + ' (' + r.patientCode + ')',
          size: 'xl', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer sans valider', {
              icon: 'save',
              onclick: function () { enregistrer(false); },
            }),
            K.btn('Valider le résultat', {
              variant: 'primary', icon: 'check',
              onclick: function () { enregistrer(true); },
            }),
          ],
        });
        U.icons(corps);

        function enregistrer(valider) {
          var manquantes = variables.filter(function (v) {
            return !v.accompagnement && !v.parent
              && (saisies[v.code] == null || saisies[v.code] === '');
          });
          if (valider && manquantes.length) {
            U.toast('Résultat incomplet.', {
              type: 'error',
              detail: C.num(manquantes.length) + ' variable(s) principale(s) non renseignée(s) : '
                + manquantes.slice(0, 3).map(function (v) { return v.libelle; }).join(', ')
                + (manquantes.length > 3 ? '…' : ''),
            });
            return;
          }
          /* Le résumé textuel reste alimenté : les écrans et états antérieurs
             au modèle structuré le lisent encore. Les deux générations de
             données cohabitent, comme ailleurs dans le prototype. */
          var anormales = variables.filter(function (v) { return L.ecart(variableALaDate(v, r.dateHeure), saisies[v.code]); });
          var resume = variables.filter(function (v) { return !v.accompagnement && saisies[v.code]; })
            .map(function (v) {
              var u = symbole(v.unite);
              return v.libelle + ' ' + saisies[v.code] + (u === '—' ? '' : ' ' + u);
            }).join(' · ');

          /* Une RECTIFICATION si le résultat était déjà validé
             biologiquement — jamais un écrasement. */
          if (D.resultatRendu(r.etatAnalyse)) {
            m.close();
            demanderRectification(r, saisies, txtGeneral.value);
            return;
          }

          var res = col.update(r.id, {
            valeurs: saisies,
            resultat: resume || null,
            resultatStructure: true,
            conclusion: anormales.length ? 'Anormal' : 'Normal',
            anormales: anormales.length,
            commentaireGeneral: txtGeneral.value || null,
            laborantin: selValideur.value,
            /* PREMIER VERROU SEULEMENT. La validation biologique est un second
               geste, porté depuis l'onglet dédié après relecture : c'est elle
               qui rend le résultat visible du prescripteur. */
            etatAnalyse: valider ? 'valide_technique' : 'saisi',
            valideTechniqueLe: valider ? new Date().toISOString() : null,
            valideTechniquePar: valider ? selValideur.value : null,
          });
          m.close();
          if (table) table.refresh();
          afficher();
          U.toast(valider ? 'Validation technique portée.' : 'Résultat enregistré, non validé.', {
            type: 'success', duration: 8000,
            detail: valider
              ? 'Le prescripteur NE VOIT PAS encore ce résultat. Il faut la validation biologique — '
                + 'onglet « À valider biologiquement ».'
              : (anormales.length
                ? C.num(anormales.length) + ' valeur(s) hors référence.'
                : 'Toutes les valeurs sont dans les références.'),
            undo: function () { res.undo(); if (table) table.refresh(); afficher(); },
          });
        }
      }

      /** Le champ de saisie qui convient au type de la variable. */
      function champDeVariable(v, valeurInitiale) {
        var noeud, lire, ecouter;
        if (['binaire', 'ternaire', 'titre', 'liste', 'reactif', 'commentaire'].indexOf(v.type) !== -1) {
          var options = v.valeurs
            || (L.TYPES_VARIABLE.filter(function (t) { return t.id === v.type; })[0] || {}).valeurs
            || [];
          var sel = el('select.select');
          sel.appendChild(el('option', { value: '' }, '—'));
          options.forEach(function (o) { sel.appendChild(el('option', { value: o }, o)); });
          if (valeurInitiale) sel.value = valeurInitiale;
          /* Un commentaire ou un réactif accepte aussi une valeur non listée. */
          if (v.type === 'commentaire' || v.type === 'reactif') {
            var libre = el('input.input.mt-1', { type: 'text', placeholder: 'ou saisir librement' });
            if (valeurInitiale && options.indexOf(valeurInitiale) === -1) libre.value = valeurInitiale;
            noeud = el('div', null, [sel, libre]);
            lire = function () { return libre.value || sel.value; };
            ecouter = function (fn) { sel.addEventListener('change', fn); libre.addEventListener('input', fn); };
            return { noeud: noeud, valeur: lire, onChange: ecouter };
          }
          noeud = sel;
          lire = function () { return sel.value; };
          ecouter = function (fn) { sel.addEventListener('change', fn); };
          return { noeud: noeud, valeur: lire, onChange: ecouter };
        }
        if (v.type === 'expiration') {
          var d = el('input.input', { type: 'date', value: valeurInitiale || '' });
          return {
            noeud: d, valeur: function () { return d.value; },
            onChange: function (fn) { d.addEventListener('change', fn); },
          };
        }
        if (v.type === 'texte') {
          var ta = el('textarea.input', { rows: 2 });
          ta.value = valeurInitiale || '';
          return {
            noeud: ta, valeur: function () { return ta.value; },
            onChange: function (fn) { ta.addEventListener('input', fn); },
          };
        }
        var inp = el('input.input.text-right', {
          type: v.type === 'numerique' ? 'number' : 'text',
          step: v.decimales ? Math.pow(10, -v.decimales) : 'any',
          value: valeurInitiale != null ? valeurInitiale : '',
        });
        return {
          noeud: inp, valeur: function () { return inp.value; },
          onChange: function (fn) { inp.addEventListener('input', fn); },
        };
      }

      /** Le code d'examen correspondant à une demande. */
      function codeExamenDe(r) {
        var exs = colExamens().active();
        var parCode = exs.filter(function (e) { return e.code === r.examenCode || e.code === r.analyseCode; })[0];
        if (parCode) return parCode.code;
        /* Le jeu de démonstration antérieur nomme l'analyse en clair : on la
           retrouve par sa désignation, faute de quoi les demandes d'avant le
           modèle structuré resteraient inexploitables. */
        var norm = function (x) {
          return String(x || '').toUpperCase()
            .replace(/[ÉÈÊË]/g, 'E').replace(/[ÀÂÄ]/g, 'A').replace(/[ÎÏ]/g, 'I')
            .replace(/[ÔÖ]/g, 'O').replace(/[ÛÜÙ]/g, 'U').replace(/[^A-Z0-9]/g, '');
        };
        var cible = norm(r.analyse);
        var parNom = exs.filter(function (e) {
          var d = norm(e.designation);
          return d === cible || d.indexOf(cible) === 0 || cible.indexOf(norm(e.code)) === 0;
        })[0];
        return parNom ? parNom.code : null;
      }
    },
  });

  /* ==========================================================================
   * CATALOGUE DES ANALYSES (48 désignations réelles)
   * ======================================================================== */
  global.SIGH.screen('m5-catalogue', {
    title: 'Catalogue des analyses',
    description: 'Référentiel des 48 analyses réalisées par le laboratoire de la clinique, avec catégorie, échantillon, délai et tarif.',
    regle: 'Les désignations reprennent fidèlement le document « Tarifs des analyses de laboratoire » de la clinique. '
      + 'Les <strong>tarifs</strong> portés ici sont des valeurs d’attente : le document source ne renseigne pas la colonne des prix et ceux-ci doivent être confirmés avant recette.',
    render: K.crud({
      collection: 'analyses', entite: 'analyse', entiteP: 'analyses', module: 'M5',
      defaultSort: 'n', pageSize: 20,
      source: 'Tarifs des analyses de laboratoire — 48 désignations.',
      columns: [
        { key: 'n', label: 'N°', align: 'right', nowrap: true },
        { key: 'code', label: 'Code', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: r.code }); } },
        { key: 'designation', label: 'Désignation' },
        { key: 'categorie', label: 'Catégorie', render: function (r) { return U.badge(r.categorie, 'navy'); } },
        { key: 'echantillon', label: 'Échantillon' },

        {
          key: 'prix', label: 'Tarif', align: 'right',
          text: function (r) { return C.money(r.prix, false); },
          render: function (r) {
            return el('span.inline-flex.items-center.gap-1', null, [
              el('span.font-semibold', { text: C.money(r.prix, false) }),
              r.tarifProvisoire ? el('span.text-warning-500', { title: 'Tarif à confirmer' }, C.icon('help-circle', 'h-3.5 w-3.5')) : null,
            ]);
          },
        },
        { key: 'statut', label: 'Statut', render: function (r) { return U.statut(r.statut); } },
      ],
      fields: [
        { name: 'code', label: 'Code', required: true },
        { name: 'designation', label: 'Désignation', required: true, col: 'full' },
        { name: 'categorie', label: 'Catégorie', type: 'select', required: true, options: Object.keys(C.groupBy(D.ANALYSES, 'categorie')).sort() },
        { name: 'echantillon', label: 'Type d’échantillon', type: 'select', options: Object.keys(C.groupBy(D.ANALYSES, 'echantillon')).sort() },
        { name: 'delai', label: 'Délai de rendu', type: 'select', options: ['Immédiat', '1 h', '2 h', '4 h', '6 h', '24 h', '48 h', '72 h'] },
        { name: 'prix', label: 'Tarif (FCFA)', type: 'money', required: true, min: 0 },
      ],
      filters: [
        { name: 'categorie', label: 'Catégorie', options: Object.keys(C.groupBy(D.ANALYSES, 'categorie')).sort() },
        { name: 'echantillon', label: 'Échantillon', options: Object.keys(C.groupBy(D.ANALYSES, 'echantillon')).sort() },
      ],
      kpis: function (rows) {
        return [
          { label: 'Analyses au catalogue', value: C.num(rows.length), icon: 'list-checks', tone: 'navy' },
          { label: 'Catégories', value: C.num(Object.keys(C.groupBy(rows, 'categorie')).length), icon: 'layers', tone: 'info' },
          { label: 'Tarif moyen', value: C.money(rows.length ? C.sum(rows, 'prix') / rows.length : 0), icon: 'coins', tone: 'success' },
          { label: 'Tarifs à confirmer', value: C.num(rows.filter(function (r) { return r.tarifProvisoire; }).length), icon: 'help-circle', tone: 'warning' },
        ];
      },
      extraTabs: [{
        id: 'categories', label: 'Par catégorie',
        render: function () {
          var g = C.groupBy(S.collection('analyses').active(), 'categorie');
          var wrap = el('div.grid.gap-4.md\\:grid-cols-2');
          C.sortBy(Object.keys(g).map(function (k) { return { k: k, n: g[k].length }; }), 'k').forEach(function (x) {
            var card = el('div.card');
            var b = el('div.card-body');
            b.appendChild(el('div.mb-2.flex.items-center.justify-between', null, [
              el('span.text-sm.font-semibold.text-slate-800', { text: x.k }),
              U.badge(x.n + ' analyse' + (x.n > 1 ? 's' : ''), 'navy'),
            ]));
            var ul = el('ul.space-y-1');
            C.sortBy(g[x.k], 'designation').forEach(function (a) {
              ul.appendChild(el('li.flex.items-baseline.justify-between.gap-3.text-xs', null, [
                el('span.text-slate-600', { text: a.designation }),
                el('span.shrink-0.num.font-medium.text-slate-800', { text: C.money(a.prix, false) }),
              ]));
            });
            b.appendChild(ul);
            card.appendChild(b);
            wrap.appendChild(card);
          });
          return wrap;
        },
      }],
      etat: function () { /* remplacé par l'action d'en-tête */ },
    }),
    actions: function () {
      return [K.btn('Imprimer le catalogue', {
        variant: 'primary', icon: 'printer',
        onclick: function () {
          var rows = C.sortBy(S.collection('analyses').active(), 'n');
          P.etat({
            titre: 'Tarifs des analyses de laboratoire',
            sousTitre: rows.length + ' désignations — tarifs en vigueur',
            contenu: P.tableau([
              { label: 'N°', key: 'n', align: 'right' },
              { label: 'Désignation', key: 'designation' },
              { label: 'Catégorie', key: 'categorie' },
              { label: 'Échantillon', key: 'echantillon' },
              { label: 'Tarif', align: 'right', value: function (r) { return C.money(r.prix, false); } },
            ], rows),
            signatures: [{ role: 'Le Laborantin chef', nom: 'KINNOU Addoul Ganiou' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })];
    },
  });

  /* ==========================================================================
   * RÉACTIFS & CONSOMMABLES
   * ======================================================================== */
  /* ==========================================================================
   * COMPTE RENDU D'ANALYSES — la pièce du dossier 2026080411
   * --------------------------------------------------------------------------
   * Reproduit la fiche réelle éditée le 21/08/2026 : un en-tête d'identité,
   * puis les examens groupés par SECTION, chacun sous son intitulé, avec les
   * quatre colonnes du document — ANALYSE, RÉSULTAT, Références, Antériorités.
   *
   * Deux fidélités qui comptent :
   *   — les valeurs HORS BORNES s'impriment EN GRAS, comme sur le document.
   *     C'est la seule signalisation que le clinicien lit en diagonale ;
   *   — la colonne ANTÉRIORITÉS existe même vide : elle dit qu'on a cherché
   *     un résultat antérieur, et qu'il n'y en avait pas.
   * ======================================================================== */
  function compteRendu(patientId, demandes) {
    var pat = patients().filter(function (x) { return x.id === patientId; })[0];
    var rendus = (demandes || []).filter(function (d) {
      return d.etatAnalyse === 'valide' || (d.valeurs && Object.keys(d.valeurs).length);
    });

    if (!rendus.length) {
      U.toast('Aucun résultat à imprimer.', {
        type: 'error',
        detail: 'Le compte rendu ne reprend que les examens dont le résultat a été saisi.',
      });
      return;
    }

    /* Les examens sont groupés par section du bulletin, dans l'ordre du
       document — hématologie d'abord, hormonologie en dernier. */
    var parSection = {};
    rendus.forEach(function (d) {
      var code = codeExamenDeStatique(d);
      var ex = code ? L.examen(code) : null;
      var sec = ex ? ex.sectionResultat : 'autres';
      (parSection[sec] = parSection[sec] || []).push({ demande: d, examen: ex, code: code });
    });

    var ordre = L.SECTIONS.map(function (x) { return x.id; }).concat(['autres']);
    var contenu = el('div');

    /* En-tête du compte rendu, repris du document. */
    var tete = el('table', { style: 'width:100%;border-collapse:collapse;margin-bottom:8px;' });
    var trTete = el('tr');
    var gauche = el('td', {
      style: 'width:52%;border:1px solid #94a3b8;padding:6px 8px;vertical-align:top;font-size:10px;line-height:1.5;',
    });
    var premiere = rendus[0];
    gauche.appendChild(el('div', { text: 'Dossier ' + (pat ? pat.code : '—') + '   Code '
      + (premiere.codeAnalyse || premiere.reference || '') }));
    gauche.appendChild(el('div', {
      text: (pat && pat.dateNaissance ? C.age(pat.dateNaissance) + ' ans' : 'Âge non renseigné')
        + '  ' + (pat ? (pat.sexe === 'F' ? 'Féminin' : 'Masculin') : ''),
    }));
    gauche.appendChild(el('div', { style: 'margin-top:6px;', text: 'Examen prescrit le '
      + C.dateFR(premiere.dateHeure || premiere.date) + ' par ' + (premiere.prescripteur || '—') }));
    gauche.appendChild(el('div', { text: 'Enregistré le ' + C.dateFR(premiere.dateHeure || premiere.date)
      + ' édité le ' + C.dateFR(AUJ) }));
    var droite = el('td', {
      style: 'border:1px solid #94a3b8;padding:6px 8px;vertical-align:top;font-size:13px;font-weight:700;',
    });
    droite.appendChild(el('div', { text: (pat ? (pat.nom + ' ' + pat.prenom).toUpperCase() : '—') }));
    trTete.appendChild(gauche); trTete.appendChild(droite);
    tete.appendChild(trTete);
    contenu.appendChild(tete);

    /* Renseignements cliniques — présents sur le document, même vides. */
    contenu.appendChild(el('div', {
      style: 'border:1px solid #94a3b8;padding:5px 8px;font-size:10px;margin-bottom:8px;min-height:26px;',
      text: 'Renseignements cliniques : ' + (premiere.indication || premiere.motif || ''),
    }));

    /* Le tableau des résultats. */
    var t = el('table', { style: 'width:100%;border-collapse:collapse;font-size:10px;' });
    var thead = el('thead');
    thead.appendChild(el('tr', null, [
      el('th', { style: enteteStyle('35%', 'center'), text: 'ANALYSE' }),
      el('th', { style: enteteStyle('25%', 'right'), text: 'RESULTAT' }),
      el('th', { style: enteteStyle('20%', 'center'), text: 'Références' }),
      el('th', { style: enteteStyle('20%', 'center'), text: 'Antériorités' }),
    ]));
    t.appendChild(thead);
    var tb = el('tbody');
    var anormales = 0;

    ordre.forEach(function (sec) {
      var groupe = parSection[sec];
      if (!groupe || !groupe.length) return;

      /* Titre de section, centré sur toute la largeur — comme le document. */
      tb.appendChild(el('tr', null, el('td', {
        colspan: 4,
        style: 'text-align:center;font-weight:700;font-size:13px;padding:8px 0 4px;',
        text: sec === 'autres' ? 'Autres examens' : L.section(sec),
      })));

      groupe.forEach(function (g) {
        /* Intitulé de l'examen, en gras, aligné à gauche. */
        tb.appendChild(el('tr', null, el('td', {
          colspan: 4,
          style: 'font-weight:700;padding:4px 4px 2px;',
          text: g.examen ? g.examen.designation : g.demande.analyse,
        })));

        var variables = g.code ? variablesDe(g.code).filter(function (v) { return v.actif !== false; }) : [];
        var valeurs = g.demande.valeurs || {};

        if (!variables.length) {
          /* Résultat antérieur au modèle structuré : on rend ce qu'on a. */
          tb.appendChild(ligneResultat(g.demande.analyse, g.demande.resultat || '—', '', null));
          return;
        }

        variables.forEach(function (v) {
          var val = valeurs[v.code];
          if (val == null || val === '') return;
          /* Les bornes du LOT en service à la date de la demande : un compte
             rendu ancien se relit avec les références de son époque. */
          var ecart = L.ecart(variableALaDate(v, g.demande.dateHeure), val);
          if (ecart) anormales++;
          var u = symbole(v.unite);
          var affiche = String(val) + (u === '—' ? '' : ' ' + u);
          tb.appendChild(ligneResultat(v.libelle, affiche,
            referenceALaDate(v, g.demande.dateHeure), ecart));
        });
      });
    });

    t.appendChild(tb);
    contenu.appendChild(t);

    /* Commentaire général — sur l'échantillon, pas sur un examen. */
    var commentaires = rendus.filter(function (d) { return d.commentaireGeneral; });
    if (commentaires.length) {
      contenu.appendChild(el('div', { style: 'margin-top:10px;border:1px solid #94a3b8;padding:6px 8px;font-size:10px;' }, [
        el('p', { style: 'font-weight:700;margin-bottom:2px;', text: 'Commentaire du laboratoire' }),
        el('p', { text: commentaires.map(function (d) { return d.commentaireGeneral; }).join(' — ') }),
      ]));
    }

    contenu.appendChild(el('p', {
      style: 'margin-top:10px;font-size:9px;font-style:italic;',
      text: 'Les valeurs en gras sont hors des bornes de référence. Les résultats doivent être interprétés '
        + 'par le clinicien en fonction du contexte. Les valeurs de référence dépendent du réactif et de '
        + 'l’automate employés.',
    }));

    var valides = rendus.filter(function (d) { return d.etatAnalyse === 'valide'; }).length;
    P.etat({
      titre: 'Compte rendu',
      sousTitre: (pat ? pat.nom + ' ' + pat.prenom : '') + ' — ' + C.num(rendus.length) + ' examen(s)',
      cartouche: null,
      filigrane: valides < rendus.length ? 'PROVISOIRE' : null,
      contenu: contenu,
      signatures: [{ role: 'Le Biologiste médical', mention: 'Validation biologique' }],
    });

    function enteteStyle(largeur, align) {
      return 'width:' + largeur + ';text-align:' + align + ';border-top:1px solid #64748b;'
        + 'border-bottom:1px solid #64748b;background:#f1f5f9;padding:4px 6px;font-weight:600;';
    }

    /** Une ligne de résultat. Le gras signale l'écart, comme sur le document. */
    function ligneResultat(libelle, valeur, reference, ecart) {
      return el('tr', null, [
        el('td', { style: 'padding:2px 4px;', text: libelle }),
        el('td', {
          style: 'padding:2px 4px;text-align:right;' + (ecart ? 'font-weight:700;' : ''),
          text: String(valeur),
        }),
        el('td', { style: 'padding:2px 4px;text-align:center;font-size:9px;', text: reference || '' }),
        el('td', { style: 'padding:2px 4px;text-align:center;font-size:9px;', text: '' }),
      ]);
    }
  }

  /* ==========================================================================
   * PARAMÉTRAGE DU LABORATOIRE — socle commun
   * --------------------------------------------------------------------------
   * Trois écrans lisent les mêmes collections, sous trois angles :
   *   « Catalogue des examens »   — quels examens la clinique réalise ;
   *   « Unités de mesure »        — dans quoi les résultats s'expriment ;
   *   « Valeurs de référence »    — à quoi ils se comparent.
   *
   * UNE SEULE collection porte les bornes (`variablesLabo`) : l'écran des
   * valeurs de référence n'en est qu'une vue. Deux collections auraient
   * divergé au premier changement de réactif.
   * ======================================================================== */
  function colExamens() {
    return S.collection('examensLabo', { module: 'M5', entite: 'examen', prefix: 'EXA' });
  }
  function colUnites() {
    return S.collection('unitesLabo', { module: 'M5', entite: 'unité', prefix: 'UNI' });
  }
  function colVariables() {
    return S.collection('variablesLabo', { module: 'M5', entite: 'variable', prefix: 'VAR' });
  }

  function colPlages() {
    return S.collection('plagesReactif', { module: 'M5', entite: 'plage de référence', prefix: 'PLG' });
  }

  /* --------------------------------------------------------------------------
   * LA PLAGE DU LOT DE RÉACTIF (phase 6 — observation du labo, reunions/)
   * --------------------------------------------------------------------------
   * « Les paramètres d'examen sont modifiables selon le réactif. » Les bornes
   * de la variable valent pour le réactif en service ; un changement de lot
   * peut les déplacer. La plage est VERSIONNÉE comme la grille des primes :
   * elle porte sa date d'entrée en service, et un résultat se compare aux
   * bornes du lot EN SERVICE À SA DATE — une borne relevée au changement de
   * réactif ne doit pas changer un résultat déjà rendu. Sans plage
   * enregistrée, la borne de la variable fait foi.
   * ----------------------------------------------------------------------- */
  function plagePour(variable, date) {
    var d = String(date || '').slice(0, 10) || C.iso(AUJ);
    var cands = colPlages().active().filter(function (p) {
      return p.variableId === variable.id && (!p.dateDebut || p.dateDebut <= d);
    }).sort(function (a, b) { return String(a.dateDebut || '').localeCompare(String(b.dateDebut || '')); });
    return cands.length ? cands[cands.length - 1] : null;
  }
  function variableALaDate(v, date) {
    var p = plagePour(v, date);
    return p ? Object.assign({}, v, { min: p.min, max: p.max }) : v;
  }
  function referenceALaDate(v, date) {
    var p = plagePour(v, date);
    var lib = L.libelleReference(p ? Object.assign({}, v, { min: p.min, max: p.max }) : v);
    return p && lib ? lib + ' — lot ' + p.lot : lib;
  }
  /* Exposé pour la sonde fonctionnelle : le scénario interroge le moteur de
     versionnement, il n'en recopie pas la logique. */
  global.SIGH.laboPlages = {
    plagePour: plagePour, variableALaDate: variableALaDate, referenceALaDate: referenceALaDate,
  };

  /** Les variables d'un examen, dans l'ordre de rendu, telles que paramétrées. */
  function variablesDe(codeExamen) {
    return colVariables().active()
      .filter(function (v) { return v.examen === codeExamen; })
      .sort(function (a, b) { return (a.ordre || 0) - (b.ordre || 0); });
  }

  /** Le symbole d'une unité, lu dans le magasin. */
  function symbole(id) {
    var u = colUnites().active().filter(function (x) { return x.id === id || x.symbole === id; })[0];
    return u ? u.symbole : L.unite(id);
  }

  /* ==========================================================================
   * UNITÉS DE MESURE
   * ======================================================================== */
  global.SIGH.screen('m5-unites', {
    title: 'Unités de mesure',
    description: 'Unités dans lesquelles les résultats s’expriment, pré-insérées pour que le laboratoire n’ait pas à les ressaisir.',
    regle: 'Les symboles sont ceux de la <strong>fiche de résultats de la clinique</strong> — « G/l », « T/l », '
      + '« g/dl » — et non les notations normalisées 10⁹/L ou g/L. Le laboratoire lit ce qu’il écrit : '
      + 'lui imposer une autre notation, plus « correcte », l’obligerait à traduire à chaque lecture.',
    render: K.crud({
      collection: 'unitesLabo', entite: 'unité', entiteP: 'unités', module: 'M5',
      pageSize: 25, defaultSort: 'domaine',
      columns: [
        {
          key: 'symbole', label: 'Symbole', nowrap: true,
          render: function (u) { return el('span.font-mono.text-sm.font-semibold.text-navy-800', { text: u.symbole }); },
        },
        { key: 'libelle', label: 'Intitulé' },
        { key: 'domaine', label: 'Domaine', render: function (u) { return U.badge(u.domaine, 'navy'); } },
        {
          key: 'aValider', label: 'Provenance',
          text: function (u) { return u.aValider ? 'à confirmer' : 'documentée'; },
          render: function (u) {
            return u.aValider
              ? U.badge('À confirmer', 'warning')
              : el('span.text-xs.text-slate-500', { text: u.source || 'Fiche de résultats CNT' });
          },
        },
      ],
      filters: [
        { name: 'domaine', label: 'Domaine', options: ['Hématologie', 'Biochimie', 'Hormonologie', 'Bactériologie', 'Parasitologie', 'Hémostase', 'Andrologie', 'Général'] },
      ],
      fields: [
        { name: 'symbole', label: 'Symbole', type: 'text', required: true, hint: 'Tel qu’il s’imprime sur la fiche de résultats' },
        { name: 'libelle', label: 'Intitulé complet', type: 'text', required: true, col: 'full' },
        {
          name: 'domaine', label: 'Domaine', type: 'select', required: true,
          options: ['Hématologie', 'Biochimie', 'Hormonologie', 'Bactériologie', 'Parasitologie', 'Hémostase', 'Andrologie', 'Général'],
        },
      ],
      kpis: function (rows) {
        return [
          { label: 'Unités paramétrées', value: C.num(rows.length), icon: 'ruler', tone: 'navy' },
          { label: 'Reprises de la fiche', value: C.num(rows.filter(function (u) { return !u.aValider; }).length), icon: 'file-check-2', tone: 'success' },
          { label: 'À confirmer', value: C.num(rows.filter(function (u) { return u.aValider; }).length), icon: 'help-circle', tone: 'warning' },
          { label: 'Domaines couverts', value: C.num(Object.keys(C.groupBy(rows, 'domaine')).length), icon: 'layers', tone: 'info' },
        ];
      },
      source: L.source,
    }),
  });

  /* ==========================================================================
   * VALEURS DE RÉFÉRENCE
   * --------------------------------------------------------------------------
   * « Donner la possibilité d'ajouter ou de modifier les paramètres d'un examen
   * (car en fonction des réactifs les valeurs peuvent changer). » — c'est
   * exactement ce que fait cet écran, et c'est pourquoi les bornes vivent dans
   * le magasin plutôt que dans le code.
   * ======================================================================== */
  global.SIGH.screen('m5-valeurs-reference', {
    title: 'Valeurs de référence',
    description: 'Bornes de normalité, unités et type de chaque variable de résultat. Modifiables : elles dépendent du réactif.',
    regle: 'Les bornes <strong>dépendent du réactif et de l’automate</strong> : elles se modifient ici, sans toucher au code. '
      + 'Celles reprises de la fiche de résultats du 21/08/2026 sont marquées <strong>documentées</strong> ; '
      + 'les valeurs usuelles suppléées ont reçu la <strong>validation écrite du biologiste médical le '
      + '01/09/2026</strong> et le portent — les deux provenances ne se confondent jamais. Une variable '
      + 'créée ou modifiée depuis repart « à valider ».',
    render: function (root) {
      var vue = el('div.space-y-4');
      var selSection = el('select.select');
      var selExamen = el('select.select');
      var selEtat = el('select.select');

      selSection.appendChild(el('option', { value: '' }, 'Toutes les sections'));
      L.SECTIONS.forEach(function (x) { selSection.appendChild(el('option', { value: x.id }, x.label)); });
      selEtat.appendChild(el('option', { value: '' }, 'Toutes les variables'));
      selEtat.appendChild(el('option', { value: 'documente' }, 'Documentées'));
      selEtat.appendChild(el('option', { value: 'valider' }, 'À valider'));
      selEtat.appendChild(el('option', { value: 'ferme' }, 'Fermées'));
      remplirExamens();

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div.min-w-\[12rem\]', null, [el('label.label', { text: 'Section' }), selSection]),
        el('div.min-w-\[16rem\]', null, [el('label.label', { text: 'Examen' }), selExamen]),
        el('div', null, [el('label.label', { text: 'État' }), selEtat]),
        K.btn('Imprimer le référentiel', { icon: 'printer', onclick: imprimer }),
      ]));
      selSection.addEventListener('change', function () { remplirExamens(); afficher(); });
      [selExamen, selEtat].forEach(function (x) { x.addEventListener('change', afficher); });

      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function remplirExamens() {
        C.clear(selExamen);
        selExamen.appendChild(el('option', { value: '' }, 'Tous les examens'));
        colExamens().active()
          .filter(function (e) { return !selSection.value || e.section === selSection.value; })
          .forEach(function (e) { selExamen.appendChild(el('option', { value: e.code }, e.designation)); });
      }

      function lignes() {
        return colVariables().all().filter(function (v) {
          if (selSection.value && v.section !== selSection.value) return false;
          if (selExamen.value && v.examen !== selExamen.value) return false;
          if (selEtat.value === 'documente' && (v.aValider || !v.actif)) return false;
          if (selEtat.value === 'valider' && !v.aValider) return false;
          if (selEtat.value === 'ferme' && v.actif !== false) return false;
          if (!selEtat.value && v.statut === 'archive') return false;
          return true;
        });
      }

      function afficher() {
        var rows = lignes();
        var toutes = colVariables().active();
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Variables paramétrées', value: C.num(toutes.length), icon: 'target', tone: 'navy' },
          {
            label: 'Documentées', value: C.num(toutes.filter(function (v) { return !v.aValider && !v.valideLe; }).length),
            icon: 'file-check-2', tone: 'success', hint: 'Fiche de résultats du 21/08/2026',
          },
          {
            label: 'Validées par le biologiste',
            value: C.num(toutes.filter(function (v) { return v.valideLe; }).length),
            icon: 'shield-check', tone: 'info', hint: 'Validation écrite du 01/09/2026',
          },
          {
            label: 'Variables fermées', value: C.num(toutes.filter(function (v) { return v.actif === false; }).length),
            icon: 'eye-off', tone: 'neutral', hint: 'Retirées du compte rendu',
          },
        ]));

        vue.appendChild(K.note('Une variable d’<strong>accompagnement</strong> — réactif, lot, expiration, commentaire — '
          + 'se <strong>ferme</strong> sans se supprimer : le jour où un changement de réactif rend l’interprétation '
          + 'inutile, elle disparaît du compte rendu et les résultats déjà rendus la conservent. '
          + 'C’est la demande du biologiste, mot pour mot : « on peut les fermer ».',
        { tone: 'info', icon: 'eye-off' }));

        vue.appendChild(U.dataTable({
          title: 'Variables et valeurs de référence', rows: rows,
          exportName: 'valeurs-reference', pageSize: 25, searchable: true,
          columns: [
            {
              key: 'examenLibelle', label: 'Examen',
              render: function (v) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: v.examenLibelle }),
                  el('p.text-xs.text-slate-400', { text: L.section(v.section) }),
                ]);
              },
            },
            {
              key: 'libelle', label: 'Variable',
              render: function (v) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm', {
                    class: v.parent ? 'pl-4 text-slate-600' : 'font-medium text-slate-800',
                    text: (v.parent ? '↳ ' : '') + v.libelle,
                  }),
                  el('p.font-mono.text-xs.text-slate-400', { text: v.code }),
                ]);
              },
            },
            { key: 'type', label: 'Type', text: function (v) { return L.type(v.type); }, render: function (v) { return U.badge(L.type(v.type), v.accompagnement ? 'neutral' : 'info'); } },
            { key: 'unite', label: 'Unité', align: 'right', text: function (v) { return symbole(v.unite); }, render: function (v) { return el('span.font-mono.text-xs', { text: symbole(v.unite) }); } },
            {
              key: 'reference', label: 'Référence', align: 'right',
              value: function (v) { return L.libelleReference(v); },
              render: function (v) {
                var t = L.libelleReference(v);
                if (!t) return el('span.text-xs.text-slate-300', { text: '—' });
                return el('span.text-sm', { class: v.aValider ? 'text-warning-700' : 'text-slate-700', text: t });
              },
            },
            {
              key: 'etat', label: 'État', align: 'right',
              /* TROIS provenances, pas deux : « documentée » vient de la
                 fiche du 21/08 ; « validée » a été suppléée PUIS arrêtée par
                 le biologiste (01/09). Les fondre ferait passer une valeur
                 usuelle pour une lecture du document. */
              value: function (v) {
                if (v.actif === false) return 'fermée';
                if (v.aValider) return 'à valider';
                return v.valideLe ? 'validée' : 'documentée';
              },
              render: function (v) {
                if (v.actif === false) return U.badge('Fermée', 'neutral');
                if (v.aValider) return U.badge('À valider', 'warning');
                if (v.valideLe) return U.badge('Validée (biologiste)', 'info');
                return U.badge('Documentée', 'success');
              },
            },
          ],
          actions: K.droits('M5').editer ? [K.btn('Nouvelle variable', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { editer(null); },
          })] : [],
          rowActions: function (v) {
            var actes = [];
            if (K.droits('M5').editer) {
              actes.push(K.iconBtn('pencil', 'Modifier les paramètres', function () { editer(v); }));
              if (v.retractable) {
                actes.push(K.iconBtn(v.actif === false ? 'eye' : 'eye-off',
                  v.actif === false ? 'Rouvrir cette variable' : 'Fermer cette variable',
                  function () { basculer(v); }));
              }
            }
            return actes;
          },
        }));

        /* ------------------------------------------------------------------
         * PLAGES PAR LOT DE RÉACTIF (phase 6)
         * ------------------------------------------------------------------
         * L'observation du laboratoire : « les paramètres d'examen sont
         * modifiables selon le réactif ». Une plage NOMME son lot et porte sa
         * date d'entrée en service — versionnée comme la grille des primes :
         * un résultat se compare aux bornes du lot en service à SA date, et
         * relever une borne ne change pas un compte rendu déjà rendu.
         * AUCUNE plage n'est pré-remplie : aucun document n'en fournit, et
         * inventer un lot de réactif serait affirmer un contrôle qui n'a pas
         * eu lieu.
         * ---------------------------------------------------------------- */
        var plages = colPlages().active();
        vue.appendChild(U.dataTable({
          title: 'Plages de référence par lot de réactif',
          rows: plages, exportName: 'plages-reactif', pageSize: 10,
          emptyMessage: 'Aucune plage par lot enregistrée : les bornes des variables ci-dessus font foi. '
            + 'À l’arrivée d’un lot dont la notice déplace les bornes, l’enregistrer ici — '
            + 'les saisies à venir s’y compareront, les résultats déjà rendus gardent leurs références.',
          columns: [
            {
              key: 'variableLibelle', label: 'Variable',
              render: function (p) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: p.variableLibelle }),
                  el('p.text-xs.text-slate-400', { text: p.examenLibelle || '' }),
                ]);
              },
            },
            { key: 'lot', label: 'Lot du réactif', render: function (p) { return el('span.font-mono.text-sm', { text: p.lot }); } },
            {
              key: 'bornes', label: 'Bornes du lot', align: 'right',
              value: function (p) { return (p.min != null ? p.min : '') + ' – ' + (p.max != null ? p.max : ''); },
            },
            { key: 'dateDebut', label: 'En service depuis', render: function (p) { return C.dateFR(p.dateDebut); } },
            { key: 'source', label: 'Source' },
          ],
          actions: K.droits('M5').editer ? [K.btn('Nouvelle plage de lot', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { editerPlage(null); },
          })] : [],
          rowActions: function (p) {
            if (!K.droits('M5').editer) return [];
            return [
              K.iconBtn('pencil', 'Modifier la plage', function () { editerPlage(p); }),
              K.iconBtn('archive', 'Archiver la plage', function () {
                U.confirm({
                  title: 'Archiver la plage du lot ' + p.lot + ' ?',
                  message: 'Les saisies à venir se compareront de nouveau aux bornes de la variable '
                    + '(ou à la plage antérieure). Les résultats déjà rendus ne changent pas.',
                  confirmLabel: 'Archiver', danger: true,
                }).then(function (ok) {
                  if (!ok) return;
                  colPlages().archive(p.id);
                  afficher();
                  U.toast('Plage archivée.', { type: 'success' });
                });
              }),
            ];
          },
        }));
        U.icons(vue);
      }

      function editerPlage(p) {
        var creation = !p;
        var numeriques = colVariables().active().filter(function (v) {
          return !v.accompagnement && v.type === 'numerique';
        });
        var f = U.form([
          {
            name: 'variableId', label: 'Variable concernée', type: 'select', required: true, col: 'full',
            options: numeriques.map(function (v) {
              return { value: v.id, label: v.examenLibelle + ' — ' + v.libelle };
            }),
          },
          { name: 'lot', label: 'Lot du réactif', type: 'text', required: true,
            hint: 'Tel qu’il figure sur le flacon et la notice' },
          { name: 'dateDebut', label: 'En service depuis le', type: 'date', required: true },
          { name: 'min', label: 'Borne basse du lot', type: 'number' },
          { name: 'max', label: 'Borne haute du lot', type: 'number' },
          { name: 'source', label: 'Source des bornes', type: 'text', required: true, col: 'full',
            hint: 'La notice du réactif, la validation de méthode… Une borne sans origine est le problème qu’on cherche à éviter.' },
        ], p || { dateDebut: C.iso(AUJ) });
        var m = U.modal({
          title: creation ? 'Nouvelle plage par lot de réactif' : 'Plage du lot ' + p.lot,
          size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('La plage s’applique aux demandes <strong>à compter de sa date d’entrée en service</strong>. '
              + 'Les résultats déjà rendus gardent les références de leur époque — c’est le même principe '
              + 'que la grille des primes datée.', { tone: 'info', icon: 'calendar' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(creation ? 'Enregistrer la plage' : 'Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var val = f.collect();
                if (!val) return;
                ['min', 'max'].forEach(function (k) {
                  val[k] = val[k] === '' || val[k] == null ? null : Number(val[k]);
                });
                if (val.min == null && val.max == null) {
                  U.toast('Une plage sans aucune borne ne compare rien.', { type: 'error',
                    detail: 'Renseigner au moins une borne, ou ne pas enregistrer de plage.' });
                  return;
                }
                var vRef = colVariables().active().filter(function (v) { return v.id === val.variableId; })[0];
                if (vRef) { val.variableLibelle = vRef.libelle; val.examenLibelle = vRef.examenLibelle; val.examen = vRef.examen; }
                if (creation) colPlages().insert(val);
                else colPlages().update(p.id, val);
                S.log(creation ? 'Plage par lot créée' : 'Plage par lot modifiée', 'M5', 'PlageReactif',
                  val.lot, p ? { min: p.min, max: p.max } : null, { min: val.min, max: val.max });
                m.close(); afficher();
                U.toast(creation ? 'Plage enregistrée.' : 'Plage modifiée.', {
                  type: 'success',
                  detail: (val.variableLibelle || '') + ' — lot ' + val.lot + ', en service depuis le ' + C.dateFR(val.dateDebut),
                });
              },
            }),
          ],
        });
      }

      function champs(v) {
        return [
          {
            name: 'examen', label: 'Examen', type: 'select', required: true, col: 'full',
            options: colExamens().active().map(function (e) { return { value: e.code, label: e.designation }; }),
          },
          { name: 'code', label: 'Code de la variable', type: 'text', required: true },
          { name: 'libelle', label: 'Intitulé', type: 'text', required: true, col: 'full' },
          {
            name: 'type', label: 'Type de résultat', type: 'select', required: true,
            options: L.TYPES_VARIABLE.map(function (t) { return { value: t.id, label: t.label }; }),
            hint: 'Le type commande la saisie et le contrôle de normalité.',
          },
          {
            name: 'unite', label: 'Unité', type: 'select',
            options: colUnites().active().map(function (u) { return { value: u.id, label: u.symbole + ' — ' + u.libelle }; }),
          },
          { name: 'min', label: 'Borne basse', type: 'number', hint: 'Vide si la référence n’a pas de borne basse' },
          { name: 'max', label: 'Borne haute', type: 'number', hint: 'Vide si la référence n’a pas de borne haute' },
          { name: 'normal', label: 'Issue attendue', type: 'text', hint: 'Pour un résultat qualitatif : Négatif, Absent…' },
          { name: 'decimales', label: 'Décimales', type: 'number', min: 0, max: 4 },
          { name: 'ordre', label: 'Rang de rendu', type: 'number', min: 1, required: true },
          { name: 'parent', label: 'Sous-variable de', type: 'text', hint: 'Code de la variable parente, si applicable' },
          { name: 'regle', label: 'Référence exprimée par une règle', type: 'text', col: 'full',
            hint: 'Quand la borne n’est pas un nombre — par exemple « inférieure à la moitié de la glycémie ».' },
        ];
      }

      function editer(v) {
        var creation = !v;
        var f = U.form(champs(v), v || { type: 'numerique', ordre: 99, unite: 'sans' });
        var m = U.modal({
          title: creation ? 'Nouvelle variable de résultat' : 'Paramètres de « ' + v.libelle + ' »',
          subtitle: creation ? null : v.examenLibelle, size: 'lg',
          body: el('div.space-y-3', null, [
            v && !v.aValider ? K.note('Cette borne est <strong>reprise de la fiche de résultats du 21/08/2026</strong>. '
              + 'La modifier fera diverger le logiciel du document de référence — à ne faire que sur décision '
              + 'du biologiste, par exemple après un changement de réactif.', { tone: 'warning', icon: 'file-check-2' }) : null,
            f,
          ].filter(Boolean)),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(creation ? 'Créer' : 'Enregistrer', {
              variant: 'primary', icon: creation ? 'plus' : 'save',
              onclick: function () {
                var val = f.collect();
                if (!val) return;
                ['min', 'max', 'decimales', 'ordre'].forEach(function (k) {
                  val[k] = val[k] === '' || val[k] == null ? null : Number(val[k]);
                });
                var ex = colExamens().active().filter(function (e) { return e.code === val.examen; })[0];
                if (ex) { val.examenLibelle = ex.designation; val.section = ex.section; }
                val.accompagnement = L.TYPES_ACCOMPAGNEMENT.indexOf(val.type) !== -1;
                val.retractable = val.accompagnement;
                if (creation) {
                  val.actif = true;
                  val.aValider = true;
                  val.source = 'Créée dans l’application le ' + C.dateFR(AUJ) + ' — à valider';
                  colVariables().insert(val);
                } else {
                  /* Modifier une borne la fait sortir du document : on le dit
                     dans la source plutôt que de laisser croire qu'elle en vient. */
                  /* Une valeur ABSENTE (null, undefined, '') n'est pas une valeur déplacée : le formulaire rend '' pour la borne qualitative d'une
                     variable numérique, et la comparer brute marquait « modifiée » toute fiche dont on corrigeait seulement l'intitulé (écart E182). */
                  var vide = function (x) { return x == null || x === '' ? null : x; };
                  var bougee = vide(val.min) !== vide(v.min) || vide(val.max) !== vide(v.max) || vide(val.normal) !== vide(v.normal);
                  if (bougee) {
                    val.source = 'Modifiée par ' + S.currentUser() + ' le ' + C.dateFR(AUJ)
                      + ' — précédemment : ' + (L.libelleReference(v) || '—');
                  }
                  colVariables().update(v.id, val);
                }
                S.log(creation ? 'Création d’une variable de résultat' : 'Modification d’une valeur de référence',
                  'M5', 'Variable', val.code, v ? { min: v.min, max: v.max } : null, { min: val.min, max: val.max });
                m.close(); afficher();
                U.toast(creation ? 'Variable créée.' : 'Paramètres enregistrés.', {
                  type: 'success', detail: val.libelle + ' — ' + (L.libelleReference(val) || 'sans référence'),
                });
              },
            }),
          ],
        });
      }

      function basculer(v) {
        var fermer = v.actif !== false;
        U.confirm({
          title: fermer ? 'Fermer « ' + v.libelle + ' » ?' : 'Rouvrir « ' + v.libelle + ' » ?',
          message: fermer
            ? 'Cette variable <strong>disparaîtra des nouvelles saisies et des comptes rendus à venir</strong>. '
              + 'Les résultats déjà rendus la conservent — un compte rendu ancien doit rester reproductible.<br><br>'
              + 'C’est le geste prévu pour un changement de réactif qui rend l’interprétation inutile. '
              + 'La variable n’est pas supprimée : elle se rouvre d’un clic.'
            : 'La variable réapparaîtra dans les saisies et les comptes rendus à venir.',
          confirmLabel: fermer ? 'Fermer la variable' : 'Rouvrir', danger: fermer,
        }).then(function (ok) {
          if (!ok) return;
          colVariables().update(v.id, { actif: !fermer, fermeeLe: fermer ? C.iso(AUJ) : null, fermeePar: fermer ? S.currentUser() : null });
          afficher();
          U.toast(fermer ? 'Variable fermée.' : 'Variable rouverte.', {
            type: 'success',
            detail: fermer ? 'Retirée des comptes rendus à venir ; les anciens la conservent.' : null,
          });
        });
      }

      function imprimer() {
        var rows = C.sortBy(lignes(), 'examenLibelle');
        P.etat({
          titre: 'Référentiel des valeurs de référence',
          sousTitre: 'Laboratoire d’analyses biomédicales — situation au ' + C.dateFR(AUJ),
          cartouche: [['Variables', C.num(rows.length)],
            ['Documentées', C.num(rows.filter(function (v) { return !v.aValider; }).length)],
            ['À valider', C.num(rows.filter(function (v) { return v.aValider; }).length)],
            ['Établi par', S.currentUser()], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Section', value: function (v) { return L.section(v.section); } },
              { label: 'Examen', key: 'examenLibelle' },
              { label: 'Variable', key: 'libelle' },
              { label: 'Type', value: function (v) { return L.type(v.type); } },
              { label: 'Unité', align: 'right', value: function (v) { return symbole(v.unite); } },
              { label: 'Références', align: 'right', value: function (v) { return L.libelleReference(v) || '—'; } },
              { label: 'Provenance', value: function (v) {
                if (v.aValider) return 'À valider';
                return v.valideLe ? 'Validée (biologiste, 01/09/2026)' : 'Documentée';
              } },
            ], rows),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Les valeurs marquées « documentées » sont reprises de la fiche de résultats de la clinique '
                + 'éditée le 21/08/2026. Celles marquées « à valider » sont des valeurs usuelles de la biologie '
                + 'médicale, portées à titre d’attente : elles dépendent du réactif et de l’automate employés et '
                + 'doivent être arrêtées par le biologiste médical avant mise en service.',
            }),
          ]),
          signatures: [{ role: 'Le Biologiste médical' },
            { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
        });
      }
    },
  });

  /* ==========================================================================
   * SALLE DE PRÉLÈVEMENT
   * --------------------------------------------------------------------------
   * Le circuit décrit par le biologiste, dans son ordre exact :
   *
   *   consultation → le médecin coche les examens → le patient sort avec son
   *   BON D'ANALYSE → il paie à la CAISSE → il se présente à la SALLE DE
   *   PRÉLÈVEMENT → le prélèvement est fait → il peut partir → la salle
   *   transmet l'ÉCHANTILLON AU LABORATOIRE avec le bon → le laboratoire
   *   traite, saisit les résultats, imprime, et transmet au clinicien
   *   prescripteur — ou directement au patient s'il est externe.
   *
   * L'écran tient le maillon que le prototype sautait : entre l'encaissement
   * et la saisie du résultat, quelqu'un prélève, et l'échantillon voyage. Sans
   * ce maillon, un résultat pouvait être saisi pour un prélèvement jamais fait.
   * ======================================================================== */
  global.SIGH.screen('m5-prelevement', {
    title: 'Salle de prélèvement',
    description: 'Prélèvement des échantillons après encaissement, et transmission au laboratoire avec le bon d’analyse.',
    regle: 'Le prélèvement ne s’effectue qu’<strong>après encaissement</strong> : une demande impayée reste visible '
      + 'mais non exécutable. Une fois prélevé, <strong>le patient peut partir</strong> — c’est la salle qui '
      + 'transmet l’échantillon au laboratoire, accompagné du bon d’analyse. '
      + 'Le laboratoire ne saisit un résultat que sur un échantillon <strong>reçu</strong>.',
    render: function (root) {
      amorcer();
      var col = S.collection('demandesAnalyses', { module: 'M5', entite: 'DemandeAnalyse' });
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      /* Trois états qui se suivent : à prélever, prélevé, reçu au laboratoire. */
      function aPrelever() {
        return col.active().filter(function (r) {
          return !r.preleveLe && !D.resultatRendu(r.etatAnalyse);
        });
      }
      function preleves() {
        return col.active().filter(function (r) { return r.preleveLe && !r.recuLaboLe; });
      }
      function recus() {
        /* ON INTERROGE LE RÉFÉRENTIEL, on ne compare pas des chaînes. Le
           filtre excluait « valide » mais pas « rectifie » : une analyse
           rectifiée — donc rendue — réapparaissait dans la file de travail du
           laboratoire, comme s'il restait quelque chose à en faire. */
        return col.active().filter(function (r) {
          return r.recuLaboLe && !D.resultatRendu(r.etatAnalyse);
        });
      }

      /** Une demande est-elle réglée ? Le parcours pose `bloquee` tant que non. */
      function reglee(r) {
        /* `bloqueParPaiement` est le champ que le parcours pose et que l'encaissement lève ; l'ancien test (`bloquee`,
           inexistant) tenait toutes les demandes pour réglées et laissait prélever sans caisse (écart E140). */
        return !r.bloquee && !r.bloqueParPaiement && r.statutPaiement !== 'impaye';
      }

      function afficher() {
        C.clear(vue);
        var attente = aPrelever();
        var bloquees = attente.filter(function (r) { return !reglee(r); });

        vue.appendChild(U.kpiGrid([
          {
            label: 'À prélever', value: C.num(attente.length - bloquees.length),
            icon: 'syringe', tone: 'warning', hint: 'Demandes réglées, patient attendu',
          },
          {
            label: 'En attente de règlement', value: C.num(bloquees.length),
            icon: 'lock', tone: bloquees.length ? 'danger' : 'neutral', hint: 'Prélèvement impossible',
          },
          { label: 'Prélevés, à transmettre', value: C.num(preleves().length), icon: 'package', tone: 'info' },
          { label: 'Reçus au laboratoire', value: C.num(recus().length), icon: 'flask-conical', tone: 'success' },
        ]));

        vue.appendChild(K.note('Le patient <strong>peut partir dès le prélèvement fait</strong> : c’est la salle qui '
          + 'achemine l’échantillon au laboratoire avec le bon d’analyse. Le laboratoire ne saisit un résultat '
          + 'que sur un échantillon <strong>reçu</strong> — sans quoi un résultat pourrait être rendu pour un '
          + 'prélèvement qui n’a jamais eu lieu.', { tone: 'info', icon: 'route' }));

        vue.appendChild(U.tabs([
          { id: 'attente', label: 'À prélever', badge: attente.length, render: function () { return table(attente, 'attente'); } },
          { id: 'transmettre', label: 'À transmettre', badge: preleves().length, render: function () { return table(preleves(), 'transmettre'); } },
          { id: 'labo', label: 'Reçus au laboratoire', badge: recus().length, render: function () { return table(recus(), 'labo'); } },
        ]));
        U.icons(vue);
      }

      function table(rows, mode) {
        return U.dataTable({
          title: mode === 'attente' ? 'Patients attendus en salle de prélèvement'
            : (mode === 'transmettre' ? 'Échantillons prélevés, à acheminer' : 'Échantillons reçus au laboratoire'),
          rows: rows, exportName: 'prelevements', pageSize: 15, searchable: true,
          emptyMessage: mode === 'attente' ? 'Aucun prélèvement en attente.' : 'Aucun échantillon à ce stade.',
          columns: [
            { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
            {
              key: 'patient', label: 'Patient',
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
                  el('p.text-xs.text-slate-400', { text: r.patientCode + (r.origineDemande === 'externe' ? ' · externe' : '') }),
                ]);
              },
            },
            { key: 'analyse', label: 'Examen' },
            { key: 'echantillon', label: 'Échantillon', nowrap: true },
            {
              key: 'urgence', label: 'Priorité', nowrap: true,
              value: function (r) { return r.urgent ? 'urgent' : 'courant'; },
              render: function (r) { return r.urgent ? U.badge('Urgent', 'danger') : U.badge('Courant', 'neutral'); },
            },
            {
              key: 'etat', label: 'État', align: 'right',
              value: function (r) { return reglee(r) ? 'réglée' : 'impayée'; },
              render: function (r) {
                if (mode === 'attente') {
                  return reglee(r) ? U.badge('Réglée — à prélever', 'success') : U.badge('En attente de caisse', 'danger');
                }
                if (mode === 'transmettre') {
                  return el('div.text-right', null, [
                    U.badge('Prélevé', 'info'),
                    el('p.mt-0\.5.text-xs.text-slate-400', { text: r.preleveLe ? C.dateHeure(r.preleveLe) : '' }),
                  ]);
                }
                return el('div.text-right', null, [
                  U.badge('Reçu', 'success'),
                  el('p.mt-0\.5.text-xs.text-slate-400', { text: r.recuLaboLe ? C.dateHeure(r.recuLaboLe) : '' }),
                ]);
              },
            },
          ],
          rowActions: function (r) {
            var actes = [K.iconBtn('printer', 'Imprimer le bon d’analyse', function () { bon(r); })];
            if (!K.droits('M5').editer) return actes;
            if (mode === 'attente') {
              if (!reglee(r)) {
                actes.push(K.iconBtn('lock', 'Règlement requis avant prélèvement', function () {
                  U.toast('Prélèvement impossible.', {
                    type: 'error',
                    detail: 'La demande n’est pas réglée. Le patient doit d’abord passer à la caisse.',
                  });
                }));
                return actes;
              }
              actes.push(K.iconBtn('syringe', 'Enregistrer le prélèvement', function () { prelever(r); }));
            } else if (mode === 'transmettre') {
              actes.push(K.iconBtn('send', 'Transmettre au laboratoire', function () { transmettre(r); }));
            } else {
              actes.push(K.iconBtn('file-pen-line', 'Saisir le résultat', function () {
                global.SIGH.app.go('m5-resultats');
              }));
            }
            return actes;
          },
        });
      }

      function prelever(r) {
        var f = U.form([
          { name: 'preleveur', label: 'Prélevé par', type: 'select', required: true, options: laborantins() },
          { name: 'heurePrelevement', label: 'Heure du prélèvement', type: 'time', required: true },
          {
            name: 'natureEchantillon', label: 'Nature de l’échantillon', type: 'text', required: true,
            hint: 'Reprise de la demande ; corrigeable si le prélèvement a différé.',
          },
          { name: 'observationPrelevement', label: 'Observation', type: 'textarea', rows: 2, col: 'full',
            hint: 'Difficulté de prélèvement, patient à jeun ou non, tout ce que le laboratoire doit savoir.' },
        ], {
          heurePrelevement: C.heure(new Date()),
          natureEchantillon: r.echantillon || '',
        });

        var m = U.modal({
          title: 'Enregistrer le prélèvement', subtitle: r.patient + ' — ' + r.analyse, size: 'md',
          body: el('div.space-y-3', null, [
            U.descList([['Patient', r.patient], ['Dossier', r.patientCode],
              ['Examen', r.analyse], ['Prescripteur', r.prescripteur || '—']], 'grid-cols-2'),
            K.note('Une fois le prélèvement enregistré, <strong>le patient peut partir</strong>. '
              + 'L’échantillon reste à acheminer au laboratoire avec son bon.', { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Prélèvement effectué', {
              variant: 'primary', icon: 'syringe',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var res = col.update(r.id, Object.assign({}, v, {
                  preleveLe: new Date().toISOString(),
                  etatAnalyse: r.etatAnalyse === 'attente' ? 'preleve' : r.etatAnalyse,
                }));
                S.log('Prélèvement effectué', 'M5', 'DemandeAnalyse', r.reference, null,
                  { preleveur: v.preleveur });
                m.close(); afficher();
                U.toast('Prélèvement enregistré.', {
                  type: 'success',
                  detail: 'Le patient peut partir ; l’échantillon est à transmettre au laboratoire.',
                  undo: function () { res.undo(); afficher(); },
                });
              },
            }),
          ],
        });
      }

      function transmettre(r) {
        U.confirm({
          title: 'Transmettre l’échantillon au laboratoire ?',
          message: 'L’échantillon de <strong>' + r.patient + '</strong> (' + r.analyse + ') est remis au '
            + 'laboratoire avec son bon d’analyse.<br><br>'
            + 'À compter de cette remise, le laboratoire peut saisir le résultat — et pas avant : '
            + 'un résultat rendu sur un échantillon non reçu serait invérifiable.',
          confirmLabel: 'Transmettre',
        }).then(function (ok) {
          if (!ok) return;
          var res = col.update(r.id, {
            recuLaboLe: new Date().toISOString(),
            recuPar: S.currentUser(),
            etatAnalyse: 'en_cours',
          });
          S.log('Échantillon reçu au laboratoire', 'M5', 'DemandeAnalyse', r.reference, null, {});
          afficher();
          U.toast('Échantillon transmis au laboratoire.', {
            type: 'success', detail: 'Le résultat peut désormais être saisi.',
            undo: function () { res.undo(); afficher(); },
          });
        });
      }

      /* Le BON D'ANALYSE — la pièce qui accompagne le patient puis l'échantillon. */
      function bon(r) {
        var pat = patients().filter(function (x) { return x.id === r.patientId; })[0];
        P.etat({
          titre: 'Bulletin d’analyses bio-médicales',
          sousTitre: 'Bon n° ' + r.reference,
          cartouche: [['Patient', r.patient], ['Dossier', r.patientCode],
            ['Âge', pat && pat.dateNaissance ? C.age(pat.dateNaissance) + ' ans' : '—'],
            ['Sexe', pat ? (pat.sexe === 'F' ? 'Féminin' : 'Masculin') : '—'],
            ['Service demandeur', r.serviceDemandeur || r.secteurDemandeur || '—'],
            ['Indication', r.indication || '—'],
            ['Prescripteur', r.prescripteur || '—'],
            ['Heure de prélèvement', r.preleveLe ? C.heure(new Date(r.preleveLe)) : '—'],
            ['Priorité', r.urgent ? 'URGENT' : 'Courant']],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Section', value: function (x) { var e = L.examen(codeExamenDeStatique(x)); return e ? L.section(e.section) : '—'; } },
              { label: 'Examen demandé', key: 'analyse' },
              { label: 'Échantillon', key: 'echantillon' },
            ], [r]),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Ce bon accompagne le patient à la caisse puis à la salle de prélèvement, et suit ensuite '
                + 'l’échantillon jusqu’au laboratoire. Le résultat est transmis au clinicien prescripteur ; '
                + 'il est remis directement au patient lorsque celui-ci est adressé de l’extérieur.',
            }),
          ]),
          signatures: [{ role: 'Le Prescripteur', nom: r.prescripteur || '' },
            { role: 'Le Préleveur', nom: r.preleveur || '' }],
        });
      }
    },
  });

  /** Le code d'examen d'une demande, hors contexte d'écran. */
  function codeExamenDeStatique(r) {
    var norm = function (x) {
      return String(x || '').toUpperCase()
        .replace(/[ÉÈÊË]/g, 'E').replace(/[ÀÂÄ]/g, 'A').replace(/[ÎÏ]/g, 'I')
        .replace(/[ÔÖ]/g, 'O').replace(/[ÛÜÙ]/g, 'U').replace(/[^A-Z0-9]/g, '');
    };
    var cible = norm(r.analyse);
    var e = L.EXAMENS.filter(function (x) {
      var d = norm(x.designation);
      return x.code === r.examenCode || d === cible || d.indexOf(cible) === 0;
    })[0];
    return e ? e.code : null;
  }

  /* ==========================================================================
   * STATISTIQUES DU LABORATOIRE
   * --------------------------------------------------------------------------
   * « Pouvoir ressortir les statistiques des examens réalisés en fonction des
   * services, de l'âge, du sexe, période, interne ou externe. » — les cinq axes
   * sont demandés nommément, et la période va de la semaine à l'année.
   * ======================================================================== */
  var PERIODES_LABO = [
    { id: 'semaine', label: 'Semaine', jours: 7 },
    { id: 'mois', label: 'Mois', jours: 30 },
    { id: 'trimestre', label: 'Trimestre', jours: 91 },
    { id: 'semestre', label: 'Semestre', jours: 182 },
    { id: 'annee', label: 'Année', jours: 365 },
    { id: 'libre', label: 'Plage libre', jours: null },
  ];

  var TRANCHES_AGE = [
    { id: '0-5', label: '0 – 5 ans', min: 0, max: 5 },
    { id: '6-15', label: '6 – 15 ans', min: 6, max: 15 },
    { id: '16-25', label: '16 – 25 ans', min: 16, max: 25 },
    { id: '26-45', label: '26 – 45 ans', min: 26, max: 45 },
    { id: '46-65', label: '46 – 65 ans', min: 46, max: 65 },
    { id: '66+', label: '66 ans et plus', min: 66, max: 200 },
  ];

  global.SIGH.screen('m5-stats', {
    title: 'Statistiques du laboratoire',
    description: 'Examens réalisés par service, âge, sexe, période et origine du patient ; consommation des réactifs.',
    regle: 'Les cinq axes demandés par le laboratoire : <strong>service demandeur, âge, sexe, période, '
      + 'patient interne ou externe</strong>. La périodicité va de la semaine à l’année, plage libre comprise. '
      + 'Le comptage porte sur les demandes <strong>enregistrées</strong>, qu’elles soient rendues ou en cours.',
    render: function (root) {
      amorcer();
      var col = S.collection('demandesAnalyses', { module: 'M5', entite: 'DemandeAnalyse' });
      var vue = el('div.space-y-4');

      var selPeriode = el('select.select');
      PERIODES_LABO.forEach(function (x) { selPeriode.appendChild(el('option', { value: x.id }, x.label)); });
      selPeriode.value = 'mois';
      var dDebut = el('input.input', { type: 'date' });
      var dFin = el('input.input', { type: 'date' });
      var selSection = el('select.select');
      selSection.appendChild(el('option', { value: '' }, 'Toutes les sections'));
      L.SECTIONS.forEach(function (x) { selSection.appendChild(el('option', { value: x.id }, x.label)); });
      var selService = el('select.select');
      selService.appendChild(el('option', { value: '' }, 'Tous les services'));
      L.SERVICES_DEMANDEURS.forEach(function (x) { selService.appendChild(el('option', { value: x.label }, x.label)); });
      var selOrigine = el('select.select');
      selOrigine.appendChild(el('option', { value: '' }, 'Interne et externe'));
      L.ORIGINES_PATIENT.forEach(function (x) { selOrigine.appendChild(el('option', { value: x.id }, x.label)); });
      var selSexe = el('select.select');
      selSexe.appendChild(el('option', { value: '' }, 'Les deux sexes'));
      selSexe.appendChild(el('option', { value: 'M' }, 'Masculin'));
      selSexe.appendChild(el('option', { value: 'F' }, 'Féminin'));

      appliquerPeriode();

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.grid.gap-3.md\:grid-cols-3.lg\:grid-cols-6', null, [
        el('div', null, [el('label.label', { text: 'Périodicité' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Du' }), dDebut]),
        el('div', null, [el('label.label', { text: 'Au' }), dFin]),
        el('div', null, [el('label.label', { text: 'Section' }), selSection]),
        el('div', null, [el('label.label', { text: 'Service demandeur' }), selService]),
        el('div', null, [el('label.label', { text: 'Origine du patient' }), selOrigine]),
        el('div', null, [el('label.label', { text: 'Sexe' }), selSexe]),
        el('div.flex.items-end.gap-2.md\:col-span-2', null, [
          K.btn('Appliquer', { variant: 'primary', icon: 'filter', onclick: afficher }),
          K.btn('Imprimer l’état', { icon: 'printer', onclick: imprimer }),
        ]),
      ]));
      selPeriode.addEventListener('change', function () { appliquerPeriode(); afficher(); });
      [dDebut, dFin, selSection, selService, selOrigine, selSexe].forEach(function (x) {
        x.addEventListener('change', afficher);
      });

      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function appliquerPeriode() {
        var per = PERIODES_LABO.filter(function (x) { return x.id === selPeriode.value; })[0];
        if (!per || per.jours == null) return;
        dFin.value = C.iso(AUJ);
        dDebut.value = C.iso(C.addDays(AUJ, -per.jours + 1));
      }

      function patientDe(r) {
        return patients().filter(function (x) { return x.id === r.patientId; })[0] || null;
      }

      function trancheAge(pat) {
        if (!pat || !pat.dateNaissance) return 'Non renseigné';
        var a = C.age(pat.dateNaissance);
        var t = TRANCHES_AGE.filter(function (x) { return a >= x.min && a <= x.max; })[0];
        return t ? t.label : 'Non renseigné';
      }

      function lignes() {
        return col.active().filter(function (r) {
          var d = String(r.dateHeure || r.date || '').slice(0, 10);
          if (dDebut.value && d && d < dDebut.value) return false;
          if (dFin.value && d && d > dFin.value) return false;
          if (selSection.value) {
            var code = codeExamenDeStatique(r);
            var ex = code ? L.examen(code) : null;
            if (!ex || ex.section !== selSection.value) return false;
          }
          if (selService.value && (r.serviceDemandeur || '') !== selService.value) return false;
          if (selOrigine.value && (r.origineDemande || 'interne') !== selOrigine.value) return false;
          if (selSexe.value) {
            var pat = patientDe(r);
            if (!pat || pat.sexe !== selSexe.value) return false;
          }
          return true;
        });
      }

      function afficher() {
        var rows = lignes();
        C.clear(vue);

        var rendus = rows.filter(function (r) { return r.etatAnalyse === 'valide'; });
        var urgents = rows.filter(function (r) { return r.urgent; });

        vue.appendChild(U.kpiGrid([
          { label: 'Examens demandés', value: C.num(rows.length), icon: 'clipboard-list', tone: 'navy' },
          { label: 'Résultats rendus', value: C.num(rendus.length), icon: 'file-check-2', tone: 'success',
            hint: rows.length ? Math.round(rendus.length / rows.length * 100) + ' % du volume' : null },
          { label: 'Demandes urgentes', value: C.num(urgents.length), icon: 'siren', tone: urgents.length ? 'danger' : 'neutral' },
          {
            label: 'Patients distincts',
            value: C.num(Object.keys(C.groupBy(rows, 'patientId')).length), icon: 'users', tone: 'info',
          },
        ]));

        if (!rows.length) {
          vue.appendChild(U.card('Statistiques',
            U.empty('Aucun examen sur la période et les filtres retenus.', { icon: 'chart-column' })));
          U.icons(vue);
          return;
        }

        /* --- Les cinq axes demandés ------------------------------------- */
        var parExamen = C.groupBy(rows, 'analyse');
        var topExamens = Object.keys(parExamen)
          .sort(function (a, b) { return parExamen[b].length - parExamen[a].length; }).slice(0, 12);

        var parSection = C.groupBy(rows, function (r) {
          var code = codeExamenDeStatique(r);
          var ex = code ? L.examen(code) : null;
          return ex ? L.section(ex.section) : 'Non classé';
        });
        var parService = C.groupBy(rows, function (r) { return r.serviceDemandeur || 'Non renseigné'; });
        var parOrigine = C.groupBy(rows, function (r) {
          return (r.origineDemande || 'interne') === 'externe' ? 'Patient externe' : 'Patient interne';
        });
        var parSexe = C.groupBy(rows, function (r) {
          var pat = patientDe(r);
          return pat ? (pat.sexe === 'F' ? 'Féminin' : 'Masculin') : 'Non renseigné';
        });
        var parAge = C.groupBy(rows, function (r) { return trancheAge(patientDe(r)); });

        vue.appendChild(U.card('Les examens les plus demandés',
          K.ranking(topExamens.map(function (k) {
            return { label: k, value: parExamen[k].length, tone: 'navy' };
          }), { format: function (v) { return C.num(v) + ' demande(s)'; } })));

        vue.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Par section du bulletin',
            G.camembert(Object.keys(parSection),
              Object.keys(parSection).map(function (k) { return parSection[k].length; }),
              { height: 260, legend: 'bottom' })),
          U.card('Par service demandeur',
            G.barres(Object.keys(parService),
              [{ label: 'Examens', data: Object.keys(parService).map(function (k) { return parService[k].length; }), color: G.TONES.navy }],
              { horizontal: true, height: 260 })),
          U.card('Patient interne ou externe',
            G.anneau(Object.keys(parOrigine),
              Object.keys(parOrigine).map(function (k) { return parOrigine[k].length; }),
              { legend: 'bottom', colors: [G.TONES.navy, G.TONES.ciel] })),
        ]));

        vue.appendChild(el('div.grid.gap-4.lg\:grid-cols-2', null, [
          U.card('Par sexe',
            G.anneau(Object.keys(parSexe),
              Object.keys(parSexe).map(function (k) { return parSexe[k].length; }),
              { legend: 'bottom', colors: [G.TONES.bleu, G.TONES.orange, G.TONES.gris] })),
          U.card('Par tranche d’âge',
            G.barres(TRANCHES_AGE.map(function (t) { return t.label; }),
              [{ label: 'Examens', data: TRANCHES_AGE.map(function (t) { return (parAge[t.label] || []).length; }), color: G.TONES.vert }],
              { height: 260 })),
        ]));

        /* --- Évolution dans le temps ------------------------------------ */
        var parJour = C.groupBy(rows, function (r) { return String(r.dateHeure || r.date || '').slice(0, 10); });
        var jours = Object.keys(parJour).filter(Boolean).sort();
        if (jours.length > 1) {
          vue.appendChild(U.card('Volume d’examens au fil du temps',
            G.ligne(jours.map(function (j) { return C.dateFR(j); }),
              [{ label: 'Examens', data: jours.map(function (j) { return parJour[j].length; }), color: G.TONES.navy }],
              { height: 240 })));
        }

        vue.appendChild(U.dataTable({
          title: 'Détail des examens — ' + C.dateFR(dDebut.value) + ' au ' + C.dateFR(dFin.value),
          rows: Object.keys(parExamen).map(function (k) {
            var v = parExamen[k];
            var code = codeExamenDeStatique(v[0]);
            var ex = code ? L.examen(code) : null;
            return {
              examen: k, section: ex ? L.section(ex.section) : 'Non classé',
              total: v.length,
              rendus: v.filter(function (x) { return x.etatAnalyse === 'valide'; }).length,
              urgents: v.filter(function (x) { return x.urgent; }).length,
              externes: v.filter(function (x) { return x.origineDemande === 'externe'; }).length,
            };
          }).sort(function (a, b) { return b.total - a.total; }),
          exportName: 'statistiques-laboratoire', pageSize: 20, searchable: true,
          columns: [
            { key: 'examen', label: 'Examen' },
            { key: 'section', label: 'Section', render: function (r) { return U.badge(r.section, 'navy'); } },
            { key: 'total', label: 'Demandes', align: 'right', render: function (r) { return el('span.font-semibold', { text: C.num(r.total) }); } },
            { key: 'rendus', label: 'Rendus', align: 'right' },
            { key: 'urgents', label: 'Urgents', align: 'right' },
            { key: 'externes', label: 'Patients externes', align: 'right' },
          ],
        }));
        U.icons(vue);
      }

      function imprimer() {
        var rows = lignes();
        var parExamen = C.groupBy(rows, 'analyse');
        var lignesEtat = Object.keys(parExamen).map(function (k) {
          var v = parExamen[k];
          return {
            examen: k, total: v.length,
            rendus: v.filter(function (x) { return x.etatAnalyse === 'valide'; }).length,
            urgents: v.filter(function (x) { return x.urgent; }).length,
            externes: v.filter(function (x) { return x.origineDemande === 'externe'; }).length,
          };
        }).sort(function (a, b) { return b.total - a.total; });

        P.etat({
          titre: 'Activité du laboratoire d’analyses biomédicales',
          sousTitre: 'Du ' + C.dateFR(dDebut.value) + ' au ' + C.dateFR(dFin.value),
          cartouche: [['Période', C.dateFR(dDebut.value) + ' – ' + C.dateFR(dFin.value)],
            ['Examens demandés', C.num(rows.length)],
            ['Résultats rendus', C.num(rows.filter(function (r) { return r.etatAnalyse === 'valide'; }).length)],
            ['Patients distincts', C.num(Object.keys(C.groupBy(rows, 'patientId')).length)],
            ['Établi par', S.currentUser()], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'Examen', key: 'examen' },
            /* Des comptages, pas des francs : chaque colonne porte sa somme
               et son format. Le pied recevait un objet dont les clés ne
               correspondaient à aucune colonne porteuse de `key` — il
               cherchait `total[undefined]` et l’état sortait avec quatre
               cases vides sous la mention TOTAL. */
            { label: 'Demandes', align: 'right', value: function (r) { return C.num(r.total); }, somme: function (r) { return r.total; }, formatTotal: function (v) { return C.num(v); } },
            { label: 'Rendus', align: 'right', value: function (r) { return C.num(r.rendus); }, somme: function (r) { return r.rendus; }, formatTotal: function (v) { return C.num(v); } },
            { label: 'Urgents', align: 'right', value: function (r) { return C.num(r.urgents); }, somme: function (r) { return r.urgents; }, formatTotal: function (v) { return C.num(v); } },
            { label: 'Patients externes', align: 'right', value: function (r) { return C.num(r.externes); }, somme: function (r) { return r.externes; }, formatTotal: function (v) { return C.num(v); } },
          ], lignesEtat, { total: true, totalLabel: 'TOTAL' }),
          signatures: [{ role: 'Le Biologiste médical' },
            { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
        });
      }
    },
  });

  global.SIGH.screen('m5-reactifs', {
    title: 'Réactifs & consommables de laboratoire',
    description: 'Suivi des stocks de réactifs, consommation rattachée aux analyses réalisées et carnet de demande.',
    regle: 'Le <strong>coût unitaire moyen pondéré (CUMP)</strong> est calculé automatiquement pour les réactifs '
      + 'et consommables de laboratoire (CDCT §10.1). Le <strong>seuil d’alerte est fixé par la clinique</strong>, '
      + 'référence par référence : le document SAGE d’origine ne le renseigne pas, et un seuil unique n’aurait '
      + 'aucun sens entre un réactif à péremption courte et un consommable de fond de rayon.',
    render: function (root) {
      var colProduits = S.collection('produits', { module: 'M6', entite: 'Produit' });
      var host = el('div.space-y-4');
      var blocKpi = el('div'), blocTable = el('div'), blocGraphes = el('div');
      host.appendChild(blocKpi);
      host.appendChild(blocTable);
      host.appendChild(blocGraphes);

      var selPeriode = el('select.select');
      PERIODES_LABO.forEach(function (x) { selPeriode.appendChild(el('option', { value: x.id }, x.label)); });
      selPeriode.value = 'mois';
      /* La périodicité doit COMMANDER le classement des plus consommés (écart E183 : le sélecteur n'écoutait rien). */
      selPeriode.addEventListener('change', function () { rendreGraphes(); });

      rendreTout();
      host.appendChild(K.source('Inventaire SAGE « Grand Stock » — les seuils d’alerte y sont absents et se '
        + 'définissent ici, référence par référence.'));
      root.appendChild(host);
      return null;

      function produits() {
        return colProduits.active().filter(function (x) {
          return x.categorie === 'reactif' || x.categorie === 'conso_labo';
        });
      }

      function champsReactif() {
        return [
          { name: 'designation', label: 'Désignation', type: 'text', required: true, col: 'full' },
          {
            name: 'categorie', label: 'Catégorie', type: 'select', required: true,
            options: [{ value: 'reactif', label: 'Réactif' }, { value: 'conso_labo', label: 'Consommable de laboratoire' }],
          },
          { name: 'unite', label: 'Unité de conditionnement', type: 'text', required: true },
          { name: 'stock', label: 'Stock actuel', type: 'number', required: true, min: 0 },
          {
            name: 'seuilAlerte', label: 'Seuil d’alerte', type: 'number', required: true, min: 0,
            hint: 'À partir de quelle quantité la clinique veut être prévenue. Absent du document SAGE : '
              + 'c’est à l’établissement de l’arrêter.',
          },
          {
            name: 'seuilCritique', label: 'Seuil critique', type: 'number', min: 0,
            hint: 'Quantité au-dessous de laquelle l’activité s’arrête. Facultatif.',
          },
          { name: 'cump', label: 'CUMP (FCFA)', type: 'number', min: 0 },
          { name: 'emplacement', label: 'Emplacement', type: 'text' },
          { name: 'fournisseur', label: 'Fournisseur habituel', type: 'text' },
          { name: 'examensLies', label: 'Examens desservis', type: 'multiselect', col: 'full',
            options: L.EXAMENS.map(function (e) { return { value: e.code, label: e.designation }; }),
            hint: 'Sert à rattacher la consommation aux examens réalisés.' },
        ];
      }

      /** RG-03 : le stock ne peut jamais être négatif. Le champ déclarait `min: 0`, que le formulaire n'applique pas : un stock de −1 s'enregistrait (écart E185). */
      function refuserStockNegatif(v) {
        if (Number(v.stock) < 0) {
          U.toast('Le stock ne peut pas être négatif.', { type: 'error', detail: 'RG-03 — corriger la quantité saisie.' });
          return false;
        }
        return true;
      }

      /** `LAB-NNNN` : le plus grand rang déjà écrit au registre des produits, plus un (écart E180). */
      function codeReactifSuivant() {
        var max = 0;
        colProduits.all().forEach(function (p) {
          var c = String(p.code || '');
          if (c.indexOf('LAB-') === 0) max = Math.max(max, parseInt(c.slice(4), 10) || 0);
        });
        return 'LAB-' + String(max + 1).padStart(4, '0');
      }

      function rendreTout() { rendreKpi(); rendreTable(); rendreGraphes(); }

      function rendreKpi() {
        var prods = produits();
        C.clear(blocKpi);
        blocKpi.appendChild(U.kpiGrid([
          { label: 'Références suivies', value: C.num(prods.length), icon: 'test-tube', tone: 'navy' },
          { label: 'Valeur du stock', value: C.money(C.sum(prods, function (p) { return p.stock * p.cump; })), icon: 'wallet', tone: 'info', hint: 'Valorisation au CUMP' },
          {
            label: 'Sous le seuil d’alerte',
            value: C.num(prods.filter(function (p) { return p.seuilAlerte != null && p.stock <= p.seuilAlerte; }).length),
            icon: 'trending-down', tone: 'danger', hint: 'Seuils fixés par la clinique',
          },
          { label: 'En rupture', value: C.num(prods.filter(function (p) { return p.stock === 0; }).length), icon: 'x-circle', tone: 'danger' },
        ]));
        var sansSeuil = prods.filter(function (p) { return p.seuilAlerte == null || p.seuilAlerte === ''; });
        if (sansSeuil.length) {
          blocKpi.appendChild(K.note('<strong>' + C.num(sansSeuil.length) + ' référence(s) sans seuil d’alerte.</strong> '
            + 'Tant qu’un seuil n’est pas fixé, aucune alerte ne peut être émise sur ces articles — '
            + 'le document SAGE d’origine ne renseigne pas cette colonne, c’est à la clinique de l’arrêter.',
          { tone: 'warning', icon: 'alert-triangle' }));
        }
        U.icons(blocKpi);
      }

      function rendreTable() {
        C.clear(blocTable);
        blocTable.appendChild(U.dataTable({
        title: 'Stock des réactifs et consommables',
        rows: function () { return produits(); },
        exportName: 'reactifs-laboratoire', pageSize: 15, searchable: true,
        rowActions: K.actionsLigne(colProduits, champsReactif(), {
          module: 'M5', archivable: false, refresh: rendreTout, avant: refuserStockNegatif,
        }),
        filters: [
          {
            name: 'categorie', label: 'Catégorie',
            options: [{ value: 'reactif', label: 'Réactifs' }, { value: 'conso_labo', label: 'Consommables de laboratoire' }],
          },
          {
            name: 'alerte', label: 'Niveau de stock',
            options: [{ value: 'rupture', label: 'En rupture' }, { value: 'alerte', label: 'Sous le seuil' },
              { value: 'ok', label: 'Stock suffisant' }, { value: 'sansSeuil', label: 'Sans seuil défini' }],
            match: function (r, v) {
              if (v === 'rupture') return r.stock === 0;
              if (v === 'alerte') return r.seuilAlerte != null && r.stock > 0 && r.stock <= r.seuilAlerte;
              if (v === 'sansSeuil') return r.seuilAlerte == null || r.seuilAlerte === '';
              return r.seuilAlerte != null && r.stock > r.seuilAlerte;
            },
          },
        ],
        columns: [
          { key: 'code', label: 'Code', nowrap: true, render: function (p) { return el('span.font-mono.text-xs', { text: p.code }); } },
          { key: 'designation', label: 'Désignation' },
          {
            key: 'categorie', label: 'Catégorie',
            text: function (p) { return p.categorie === 'reactif' ? 'Réactif' : 'Consommable labo'; },
            render: function (p) { return U.badge(p.categorie === 'reactif' ? 'Réactif' : 'Consommable', 'navy'); },
          },
          { key: 'unite', label: 'Unité' },
          {
            key: 'stock', label: 'Stock', align: 'right',
            render: function (p) {
              var cls = p.stock === 0 ? 'font-semibold text-danger-600' : (p.stock <= p.seuilAlerte ? 'font-semibold text-warning-600' : '');
              return el('span', { class: cls, text: C.num(p.stock) });
            },
          },
          { key: 'seuilAlerte', label: 'Seuil', align: 'right' },
          { key: 'cump', label: 'CUMP', align: 'right', text: function (p) { return C.money(p.cump, false); }, render: function (p) { return C.money(p.cump, false); } },
          {
            key: 'valeur', label: 'Valeur', align: 'right',
            value: function (p) { return p.stock * p.cump; },
            text: function (p) { return C.money(p.stock * p.cump, false); },
            render: function (p) { return C.money(p.stock * p.cump, false); },
          },
          {
            key: 'etat', label: 'État',
            value: function (p) { return p.stock === 0 ? 'rupture' : (p.stock <= p.seuilAlerte ? 'critique' : 'normal'); },
            render: function (p) { return U.statut(p.stock === 0 ? 'rupture' : (p.stock <= p.seuilAlerte ? 'critique' : 'normal')); },
          },
        ],
        actions: [
          K.creer(colProduits, champsReactif(), {
          module: 'M5', label: 'Nouveau réactif', titre: 'Nouveau réactif ou consommable', entite: 'Référence', avant: refuserStockNegatif,
          defauts: function () { return { categorie: 'reactif', stock: 0, seuilAlerte: 10, cump: 0 }; },
          transform: function (v) {
            /* Le code suit le REGISTRE des produits (plus grand rang LAB- + 1), jamais un compteur de page qui repart à 1 à chaque chargement
               et émettait un code déjà attribué (écart E180, même défaut que E8 / E142). */
            if (!v.code) v.code = codeReactifSuivant();
            v.stock = Number(v.stock) || 0;
            v.seuilAlerte = v.seuilAlerte === '' ? null : Number(v.seuilAlerte);
            v.seuilCritique = v.seuilCritique === '' || v.seuilCritique == null ? null : Number(v.seuilCritique);   /* facultatif : vide ≠ 0 (écart E184) */
            v.cump = Number(v.cump) || 0;
            v.seuilDefiniPar = S.currentUser();
            v.seuilDefiniLe = C.iso(AUJ);
            return v;
          },
          apres: rendreTout,
          }),
          K.btn('Bon de demande de réactifs', {
          size: 'sm', variant: 'primary', icon: 'clipboard-list',
          onclick: function () {
            /* Un seuil non fixé n'est pas un seuil de zéro : l'article est
               signalé à part, il n'est pas passé sous silence. */
            var prods = produits();
            var manquants = prods.filter(function (p) {
              return p.seuilAlerte != null && p.seuilAlerte !== '' && p.stock <= p.seuilAlerte;
            });
            var sansSeuil = prods.filter(function (p) { return p.seuilAlerte == null || p.seuilAlerte === ''; });
            if (!manquants.length) {
              U.toast('Aucune référence sous son seuil d’alerte.', {
                type: sansSeuil.length ? 'warning' : 'success',
                detail: sansSeuil.length
                  ? C.num(sansSeuil.length) + ' référence(s) n’ont pas de seuil défini : elles ne peuvent '
                    + 'pas être surveillées tant que la clinique ne l’a pas fixé.'
                  : 'Le stock de réactifs et consommables est au-dessus des seuils fixés.',
              });
              return;
            }
            P.etat({
              titre: 'Bon d’expression de besoins — Laboratoire',
              sousTitre: 'Réactifs et consommables sous le seuil d’alerte',
              cartouche: [['Service demandeur', 'Laboratoire'], ['Date', C.dateFR(AUJ)],
                ['Références concernées', C.num(manquants.length)], ['Établi par', 'KINNOU Addoul Ganiou']],
              contenu: P.tableau([
                { label: 'Code', key: 'code' },
                { label: 'Désignation', key: 'designation' },
                { label: 'Unité', key: 'unite' },
                { label: 'Stock actuel', key: 'stock', align: 'right' },
                { label: 'Seuil', key: 'seuilAlerte', align: 'right' },
                { label: 'Qté demandée', align: 'right', value: function (p) { return Math.max(p.seuilAlerte * 2 - p.stock, 1); } },
                { label: 'Qté accordée', value: function () { return ''; } },
              ], manquants),
              signatures: [{ role: 'Le Laborantin chef', nom: 'KINNOU Addoul Ganiou' },
                { role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou', mention: 'Validation' }],
            });
          },
        })].filter(Boolean),
        }));
        U.icons(blocTable);
      }

      /* ====================================================================
       * CONSOMMATION DES RÉACTIFS ET CONSOMMABLES
       * --------------------------------------------------------------------
       * Ce que le laboratoire veut savoir : lesquels partent le plus vite, et
       * sur quelle période. La périodicité va de la semaine à l'année, comme
       * partout ailleurs dans le prototype.
       * ================================================================== */
      function rendreGraphes() {
        C.clear(blocGraphes);
        var prods = produits();
        var per = PERIODES_LABO.filter(function (x) { return x.id === selPeriode.value; })[0] || PERIODES_LABO[1];
        var depuis = per.jours ? C.iso(C.addDays(AUJ, -per.jours + 1)) : null;

        var mvts = S.collection('mouvements').active().filter(function (m) {
          if (m.type !== 'sortie') return false;
          if (!prods.some(function (x) { return x.id === m.produitId; })) return false;
          if (depuis && String(m.date).slice(0, 10) < depuis) return false;
          return true;
        });

        var barre = el('div.card');
        barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
          el('div.min-w-\[12rem\]', null, [el('label.label', { text: 'Période de consommation' }), selPeriode]),
          K.btn('Bon d’expression de besoins', {
            icon: 'printer',
            onclick: function () { global.SIGH.app.go('m7-besoins'); },
          }),
        ]));
        blocGraphes.appendChild(barre);

        var parProduit = C.groupBy(mvts, 'produitId');
        var nomDe = function (id) {
          var x = prods.filter(function (y) { return y.id === id; })[0];
          return x ? x.designation : id;
        };
        var top = Object.keys(parProduit)
          .sort(function (a, b) { return C.sum(parProduit[b], 'quantite') - C.sum(parProduit[a], 'quantite'); })
          .slice(0, 10);

        var parCategorie = C.groupBy(prods, function (x) {
          return x.categorie === 'reactif' ? 'Réactifs' : 'Consommables de laboratoire';
        });

        blocGraphes.appendChild(el('div.grid.gap-4.lg\:grid-cols-3', null, [
          U.card('Les plus consommés — ' + per.label.toLowerCase(),
            top.length
              ? K.ranking(top.map(function (id) {
                return { label: nomDe(id), value: C.sum(parProduit[id], 'quantite'), tone: 'navy' };
              }), { format: function (v) { return C.num(v) + ' unité(s)'; } })
              : U.empty('Aucune sortie sur la période.', { icon: 'package-x' })),
          U.card('Valeur du stock par référence',
            K.ranking(C.sortBy(prods.slice(), function (x) { return x.stock * x.cump; }).reverse().slice(0, 10)
              .map(function (x) {
                return {
                  label: x.designation, value: x.stock * x.cump,
                  tone: x.seuilAlerte != null && x.stock <= x.seuilAlerte ? 'danger' : 'navy',
                };
              }), { format: function (v) { return C.money(v, false); } })),
          U.card('Réactifs et consommables',
            G.anneau(Object.keys(parCategorie),
              Object.keys(parCategorie).map(function (k) { return parCategorie[k].length; }),
              { legend: 'bottom', colors: [G.TONES.navy, G.TONES.ciel] })),
        ]));

        var serie = K.parMois(mvts, 'date', 'quantite');
        blocGraphes.appendChild(U.card('Consommation au fil des mois',
          G.barres(serie.labels, [{ label: 'Unités consommées', data: serie.data, color: G.TONES.bleu }],
            { height: 240 })));

        blocGraphes.appendChild(K.note('Une référence dont le classement de valeur apparaît en <strong>rouge</strong> '
          + 'est sous son seuil d’alerte : c’est du stock immobilisé sur un article qui va manquer. '
          + 'Le rapprochement des deux classements — le plus consommé et le plus immobilisé — désigne '
          + 'les réapprovisionnements à passer en premier.', { tone: 'info' }));
        U.icons(blocGraphes);
      }
    },
  });

  /* ==========================================================================
   * PHASE 6 — TRAÇABILITÉ, IMPRESSION FILTRÉE ET COMPARAISON
   * --------------------------------------------------------------------------
   * Quatre écrans de la cible : l'impression des résultats filtrée par le
   * RÈGLEMENT, le comparatif bi-panneau des antériorités, les vues des
   * demandes par service (maternité, hospitalisation) et les statistiques
   * des réactifs. Aucun ne touche aux deux verrous ni aux états.
   * ======================================================================== */

  /* LE RÈGLEMENT D'UNE DEMANDE se lit sur la LIGNE de facture qui la couvre —
     c'est la raison d'être des lignes payables. Trois réponses, pas deux :
     réglée, due, et SANS PIÈCE LIÉE — les demandes d'avant les lignes
     payables n'ont pas de facture ; les dire impayées serait aussi faux que
     les dire réglées. */
  function indexReglements() {
    var idx = {};
    S.collection('factures').active().forEach(function (f) {
      (f.lignes || []).forEach(function (l) {
        if (l.demandeId) {
          idx[l.demandeId] = {
            statut: l.statutPaiement === 'paye' ? 'regle' : 'du',
            facture: f.numero, montant: l.partPatient,
          };
        }
      });
    });
    return idx;
  }
  function reglementDemande(r, idx) {
    var v = idx[r.id];
    if (v) return v;
    if (r.bloqueParPaiement) return { statut: 'du', facture: r.factureNumero || null, montant: r.prix || null };
    return { statut: 'non_trace', facture: null, montant: null };
  }
  function badgeReglement(g) {
    if (g.statut === 'regle') return U.badge('Réglée', 'success');
    if (g.statut === 'du') return U.badge('Règlement dû', 'danger');
    return U.badge('Sans pièce liée', 'neutral');
  }

  /* --------------------------------------------------------------------------
   * IMPRESSION DES RÉSULTATS — FILTRÉE PAR LE RÈGLEMENT
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m5-impression-resultats', {
    title: 'Impression des résultats',
    description: 'Édition des comptes rendus, réservée aux examens réglés : un résultat dont l’examen n’est pas payé reste visible mais ne s’imprime pas.',
    regle: 'Le compte rendu ne sort que pour un examen <strong>réglé à la caisse</strong>. Un résultat non '
      + 'réglé reste <strong>visible</strong> — le masquer ferait croire à une analyse non faite — mais son '
      + 'impression est <strong>verrouillée, en le disant</strong> : la balle est à la caisse, pas au '
      + 'laboratoire. Les demandes antérieures aux lignes payables n’ont pas de pièce de caisse liée : '
      + 'elles sont signalées « sans pièce liée », ce qui n’est ni réglé ni dû.',
    render: function (root) {
      amorcer();
      var col = S.collection('demandesAnalyses');
      var host = el('div.space-y-4');
      root.appendChild(host);
      afficher();
      return null;

      function rendus() {
        return PR.filtrerResultats(col.active().filter(function (r) {
          return D.resultatRendu(r.etatAnalyse);
        }));
      }

      function afficher() {
        C.clear(host);
        var idx = indexReglements();
        var rows = rendus();
        var regles = rows.filter(function (r) { return reglementDemande(r, idx).statut === 'regle'; });
        var dus = rows.filter(function (r) { return reglementDemande(r, idx).statut === 'du'; });
        var sans = rows.filter(function (r) { return reglementDemande(r, idx).statut === 'non_trace'; });

        host.appendChild(U.kpiGrid([
          { label: 'Résultats rendus', value: C.num(rows.length), icon: 'file-check-2', tone: 'navy' },
          { label: 'Imprimables (réglés)', value: C.num(regles.length), icon: 'printer', tone: 'success' },
          {
            label: 'Verrouillés — règlement dû', value: C.num(dus.length),
            icon: 'lock', tone: dus.length ? 'danger' : 'neutral',
            hint: 'La balle est à la caisse',
          },
          {
            label: 'Sans pièce de caisse liée', value: C.num(sans.length),
            icon: 'help-circle', tone: 'neutral', hint: 'Antérieurs aux lignes payables',
          },
        ]));

        host.appendChild(U.dataTable({
          title: 'Comptes rendus à éditer', rows: rows,
          exportName: 'impression-resultats', pageSize: 12, searchable: true,
          defaultSort: 'dateHeure', defaultDir: 'desc',
          emptyMessage: 'Aucun résultat rendu dans votre périmètre.',
          columns: colonnesDemande.slice(0, 5).concat([
            {
              key: 'reglement', label: 'Règlement',
              value: function (r) { return reglementDemande(r, idx).statut; },
              render: function (r) {
                var g = reglementDemande(r, idx);
                return el('div', null, [
                  badgeReglement(g),
                  g.facture ? el('p.font-mono.text-[10px].text-slate-400', { text: g.facture }) : null,
                ]);
              },
            },
          ]),
          onRowClick: function (r) {
            U.drawer({ title: r.analyse, subtitle: r.patient + ' — ' + (r.codeAnalyse || r.reference), body: detailDemande(r) });
          },
          rowActions: function (r) {
            var g = reglementDemande(r, idx);
            if (g.statut === 'du') {
              /* Verrouillé et non masqué : le bouton dit pourquoi et chez qui. */
              var b = K.btn('Imprimer', {
                size: 'sm', icon: 'lock',
                title: 'Examen non réglé — le patient doit passer à la caisse (' + (g.facture || 'pièce à émettre') + ').',
                onclick: function () {
                  U.toast('Impression verrouillée : examen non réglé.', {
                    type: 'error',
                    detail: 'Le résultat existe et reste consultable, mais le compte rendu ne sort '
                      + 'qu’après règlement' + (g.facture ? ' de la pièce ' + g.facture : '') + '. La balle est à la caisse.',
                  });
                },
              });
              b.classList.add('opacity-50', 'cursor-not-allowed');
              b.setAttribute('aria-disabled', 'true');
              return [b];
            }
            return [K.btn('Imprimer', {
              size: 'sm', variant: 'primary', icon: 'printer',
              onclick: function () { etatResultat(r); },
            })];
          },
          bulkActions: function (getSelected, clear) {
            return [K.btn('Compte rendu de la sélection', {
              size: 'sm', variant: 'primary', icon: 'file-text',
              onclick: function () {
                var sel = getSelected();
                if (!sel.length) return;
                var pats = {};
                sel.forEach(function (r) { pats[r.patientId] = true; });
                if (Object.keys(pats).length > 1) {
                  U.toast('Un compte rendu porte sur un seul patient.', { type: 'error' });
                  return;
                }
                var bloquees = sel.filter(function (r) { return reglementDemande(r, idx).statut === 'du'; });
                if (bloquees.length) {
                  U.toast('Sélection partiellement non réglée.', {
                    type: 'error',
                    detail: bloquees.length + ' examen(s) non réglé(s) — ' + bloquees.slice(0, 3)
                      .map(function (r) { return r.analyse; }).join(', ')
                      + (bloquees.length > 3 ? '…' : '') + '. Les retirer de la sélection ou régler d’abord.',
                  });
                  return;
                }
                compteRendu(sel[0].patientId, sel);
                clear();
              },
            })];
          },
        }));
        U.icons(host);
      }
    },
  });

  /* --------------------------------------------------------------------------
   * COMPARATIF DES RÉSULTATS — BI-PANNEAU (les « Antériorités » de la fiche)
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m5-resultats-comparatif', {
    title: 'Comparatif des résultats',
    description: 'Deux mesures du même examen côte à côte, variable par variable — la colonne « Antériorités » de la fiche de résultats, à l’écran.',
    regle: 'La fiche de résultats de la clinique porte une colonne <strong>Antériorités</strong> : c’est elle '
      + 'que cet écran développe. Seuls les résultats <strong>rendus</strong> (validés biologiquement) se '
      + 'comparent — comparer une saisie non validée reviendrait à lire par-dessus l’épaule du laboratoire. '
      + 'Le périmètre est celui du RBAC métier : chacun ne compare que ce qu’il a le droit de voir.',
    render: function (root) {
      amorcer();
      var col = S.collection('demandesAnalyses');
      var host = el('div.space-y-4');
      root.appendChild(host);

      function comparables() {
        return PR.filtrerResultats(col.active().filter(function (r) {
          return D.resultatRendu(r.etatAnalyse) && r.valeurs && Object.keys(r.valeurs).length;
        }));
      }

      var rows = comparables();
      var parPatient = {};
      rows.forEach(function (r) { (parPatient[r.patientId] = parPatient[r.patientId] || []).push(r); });

      var selPatient = U.combo(Object.keys(parPatient).map(function (pid) {
        var l = parPatient[pid];
        return { value: pid, label: l[0].patient + ' (' + l[0].patientCode + ') — ' + C.num(l.length) + ' résultat(s)' };
      }), { placeholder: '— Choisir un patient —' });
      var selExamen = el('select.select');
      var zone = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.grid.gap-3.md:grid-cols-2', null, [
        el('div', null, [el('label.label', { text: 'Patient' }), selPatient]),
        el('div', null, [el('label.label', { text: 'Examen' }), selExamen]),
      ]));
      host.appendChild(barre);
      host.appendChild(zone);

      var masques = col.active().filter(function (r) { return D.resultatRendu(r.etatAnalyse); }).length
        - rows.length;
      if (masques > 0) {
        host.appendChild(K.note(C.num(masques) + ' résultat(s) rendus sont hors de votre périmètre '
          + 'et n’apparaissent pas ici — restriction du RBAC métier, pas donnée manquante.',
        { tone: 'info', icon: 'shield-check' }));
      }

      selPatient.addEventListener('change', remplirExamens);
      selExamen.addEventListener('change', comparer);
      vider('Choisir un patient pour ouvrir la comparaison.');
      U.icons(host);
      return null;

      function vider(message) {
        C.clear(zone);
        zone.appendChild(U.empty(message, { icon: 'git-compare-arrows' }));
      }

      function siens() {
        return (parPatient[selPatient.value] || []).slice().sort(function (a, b) {
          return String(a.dateHeure).localeCompare(String(b.dateHeure));
        });
      }

      function remplirExamens() {
        C.clear(selExamen);
        var parExamen = {};
        siens().forEach(function (r) {
          var code = codeExamenDeStatique(r);
          if (code) (parExamen[code] = parExamen[code] || []).push(r);
        });
        selExamen.appendChild(el('option', { value: '' }, '— Choisir un examen —'));
        Object.keys(parExamen).forEach(function (code) {
          var ex = L.examen(code);
          selExamen.appendChild(el('option', { value: code },
            (ex ? ex.designation : code) + ' (' + parExamen[code].length + ' mesure'
            + (parExamen[code].length > 1 ? 's' : '') + ')'));
        });
        vider('Choisir un examen : ceux qui portent plusieurs mesures se comparent.');
      }

      function comparer() {
        var code = selExamen.value;
        if (!code) { vider('Choisir un examen.'); return; }
        var mesures = siens().filter(function (r) { return codeExamenDeStatique(r) === code; });

        C.clear(zone);
        if (mesures.length < 2) {
          zone.appendChild(U.empty('Une seule mesure de cet examen : aucune antériorité à comparer. '
            + 'La colonne « Antériorités » se remplira à la prochaine mesure.', { icon: 'history' }));
          U.icons(zone);
          return;
        }

        /* Les deux plus récentes par défaut ; l'utilisateur choisit. */
        var selA = el('select.select'), selB = el('select.select');
        mesures.forEach(function (r, i) {
          var lbl = C.dateFR(r.dateHeure) + ' — ' + (r.codeAnalyse || r.reference)
            + (r.etatAnalyse === 'rectifie' ? ' (rectifié v' + (r.version || 2) + ')' : '');
          selA.appendChild(el('option', { value: String(i) }, lbl));
          selB.appendChild(el('option', { value: String(i) }, lbl));
        });
        selA.value = String(mesures.length - 2);
        selB.value = String(mesures.length - 1);

        var deux = el('div.card');
        deux.appendChild(el('div.card-body.grid.gap-3.md:grid-cols-2', null, [
          el('div', null, [el('label.label', { text: 'Antériorité (colonne gauche)' }), selA]),
          el('div', null, [el('label.label', { text: 'Mesure comparée (colonne droite)' }), selB]),
        ]));
        zone.appendChild(deux);
        var tableau = el('div');
        zone.appendChild(tableau);
        [selA, selB].forEach(function (x) { x.addEventListener('change', peindre); });
        peindre();

        function peindre() {
          C.clear(tableau);
          var a = mesures[+selA.value], b = mesures[+selB.value];
          if (!a || !b) return;
          var variables = variablesDe(code).filter(function (v) { return v.actif !== false && !v.accompagnement; });
          var t = el('table.tbl');
          t.appendChild(el('thead', null, el('tr', null, [
            el('th', { text: 'Variable' }),
            el('th.text-right', { text: C.dateFR(a.dateHeure) }),
            el('th.text-right', { text: C.dateFR(b.dateHeure) }),
            el('th.text-right', { text: 'Évolution' }),
            el('th.text-right', { text: 'Références' }),
          ])));
          var tb = el('tbody');
          variables.forEach(function (v) {
            var va = (a.valeurs || {})[v.code], vb = (b.valeurs || {})[v.code];
            if ((va == null || va === '') && (vb == null || vb === '')) return;
            var eA = L.ecart(variableALaDate(v, a.dateHeure), va);
            var eB = L.ecart(variableALaDate(v, b.dateHeure), vb);
            var u = symbole(v.unite);
            var suffixe = u === '—' ? '' : ' ' + u;
            var delta = null;
            if (v.type === 'numerique' && va !== '' && vb !== '' && va != null && vb != null
              && !isNaN(Number(va)) && !isNaN(Number(vb))) {
              delta = Number(vb) - Number(va);
            }
            tb.appendChild(el('tr', null, [
              el('td', null, el('p.text-sm', {
                class: v.parent ? 'pl-4 text-slate-600' : 'font-medium text-slate-800',
                text: (v.parent ? '↳ ' : '') + v.libelle,
              })),
              el('td.text-right', null, el('span.text-sm', {
                class: eA ? 'font-bold text-danger-700' : 'text-slate-700',
                text: va == null || va === '' ? '—' : String(va) + suffixe,
              })),
              el('td.text-right', null, el('span.text-sm', {
                class: eB ? 'font-bold text-danger-700' : 'text-slate-700',
                text: vb == null || vb === '' ? '—' : String(vb) + suffixe,
              })),
              el('td.text-right', null, delta == null
                ? el('span.text-xs.text-slate-300', { text: '—' })
                : el('span.text-xs.font-medium', {
                  class: delta > 0 ? 'text-danger-700' : (delta < 0 ? 'text-info-700' : 'text-slate-500'),
                  text: (delta > 0 ? '↑ +' : (delta < 0 ? '↓ ' : '= ')) + (Math.round(delta * 100) / 100) + suffixe,
                })),
              el('td.text-right', null, el('span.text-xs.text-slate-500', {
                text: referenceALaDate(v, b.dateHeure) || '—',
              })),
            ]));
          });
          t.appendChild(tb);
          tableau.appendChild(el('div.card', null,
            el('div.overflow-x-auto', null, t)));
          tableau.appendChild(K.note('L’<strong>évolution</strong> se lit de gauche à droite. Les valeurs en '
            + 'gras sont hors des références <strong>de leur époque</strong> : chaque colonne se compare aux '
            + 'bornes du lot de réactif en service à sa date.', { tone: 'info', icon: 'git-compare-arrows' }));
          U.icons(tableau);
        }
      }
    },
  });

  /* --------------------------------------------------------------------------
   * VUES PAR SERVICE DEMANDEUR — maternité et hospitalisation
   * ----------------------------------------------------------------------- */
  function ecranDemandesService(id, titre, description, correspond, complement) {
    global.SIGH.screen(id, {
      title: titre,
      description: description,
      regle: 'Une VUE du registre des demandes, pas une seconde collection : la demande n’existe qu’une '
        + 'fois, c’est le <strong>service demandeur</strong> qui la classe ici. ' + complement,
      render: function (root) {
        amorcer();
        var col = S.collection('demandesAnalyses');
        var host = el('div.space-y-4');
        root.appendChild(host);

        function rows() { return col.active().filter(correspond); }

        var r0 = rows();
        var attCaisse = r0.filter(function (r) { return r.etatAnalyse === 'en_attente'; });
        var attPrel = r0.filter(function (r) {
          return ['attente_prelevement', 'preleve'].indexOf(r.etatAnalyse) !== -1;
        });
        var rendues = r0.filter(function (r) { return D.resultatRendu(r.etatAnalyse); });

        host.appendChild(U.kpiGrid([
          { label: 'Demandes du service', value: C.num(r0.length), icon: 'clipboard-list', tone: 'navy' },
          { label: 'En attente de règlement', value: C.num(attCaisse.length), icon: 'wallet', tone: attCaisse.length ? 'warning' : 'neutral' },
          { label: 'À prélever / transmettre', value: C.num(attPrel.length), icon: 'syringe', tone: attPrel.length ? 'info' : 'neutral' },
          { label: 'Résultats rendus', value: C.num(rendues.length), icon: 'file-check-2', tone: 'success' },
        ]));

        host.appendChild(U.dataTable({
          title: titre, rows: rows,
          exportName: id, pageSize: 12, searchable: true,
          defaultSort: 'dateHeure', defaultDir: 'desc',
          emptyMessage: 'Aucune demande de ce service.',
          columns: colonnesDemande,
          onRowClick: function (r) {
            U.drawer({ title: r.analyse, subtitle: r.patient + ' — ' + (r.codeAnalyse || r.reference), body: detailDemande(r) });
          },
        }));
        U.icons(host);
        return null;
      },
    });
  }

  ecranDemandesService('m5-demandes-maternite', 'Demandes — maternité',
    'Les demandes d’analyses prescrites par la maternité : CPN, bilans d’admission, suites de couches.',
    function (r) {
      /* Le service se lit AUSSI dans son libellé : le jeu écrit « Maternité » là où la fiche du service écrit
         l'identifiant `maternite` — le test strict sur l'identifiant laissait la vue vide (écart E145). */
      return /MATERN/i.test(String(r.secteurDemandeur || '')) || /MATERN/i.test(String(r.serviceDemandeur || ''));
    },
    'La sage-femme y suit ses bilans ; le RBAC métier continue de décider qui lit les résultats.');

  ecranDemandesService('m5-demandes-hospitalisation', 'Demandes — hospitalisation',
    'Les demandes d’analyses des patients hospitalisés ou mis en observation.',
    function (r) {
      return r.hospitalise === true || /HOSPI|OBSERVATION/i.test(String(r.secteurDemandeur || ''));
    },
    'Le service d’hospitalisation y voit où en sont les bilans de ses lits, sans ouvrir le registre entier.');

  /* --------------------------------------------------------------------------
   * STATISTIQUES DES RÉACTIFS
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m5-reactifs-stats', {
    title: 'Statistiques des réactifs',
    description: 'État du stock de réactifs et consommables de laboratoire : valeur, seuils, péremptions, demandes par section.',
    regle: 'Les chiffres sont <strong>calculés</strong> depuis le stock, les lots et le registre des demandes '
      + '— jamais fournis. Les sorties de stock détaillées vivent au module M6 (mouvements) : cet écran '
      + 'lit l’état, M6 tient le flux.',
    render: function (root) {
      amorcer();
      var host = el('div.space-y-4');
      root.appendChild(host);

      var refs = S.collection('produits').active().filter(function (p) {
        return p.categorie === 'reactif' || p.categorie === 'conso_labo';
      });
      var ids = {};
      refs.forEach(function (p) { ids[p.id] = true; });
      var lots = S.collection('lots').active().filter(function (l) { return ids[l.produitId]; });
      var perimes = lots.filter(function (l) { return l.statut === 'perime'; });
      var alerte = lots.filter(function (l) { return l.statut === 'alerte'; });
      var sousSeuil = refs.filter(function (p) { return p.seuilAlerte != null && p.stock <= p.seuilAlerte; });
      var sansSeuil = refs.filter(function (p) { return p.seuilAlerte == null; });
      var valeur = refs.reduce(function (n, p) { return n + (p.stock || 0) * (p.prixAchat || 0); }, 0);

      host.appendChild(U.kpiGrid([
        { label: 'Références suivies', value: C.num(refs.length), icon: 'test-tubes', tone: 'navy',
          hint: 'Réactifs et consommables de laboratoire' },
        { label: 'Valeur du stock', value: C.money(valeur), icon: 'wallet', tone: 'info' },
        {
          label: 'Sous le seuil d’alerte', value: C.num(sousSeuil.length),
          icon: 'triangle-alert', tone: sousSeuil.length ? 'danger' : 'neutral',
          hint: sansSeuil.length ? C.num(sansSeuil.length) + ' référence(s) sans seuil fixé' : null,
        },
        {
          label: 'Lots périmés / en alerte', value: C.num(perimes.length) + ' / ' + C.num(alerte.length),
          icon: 'calendar-x', tone: (perimes.length || alerte.length) ? 'warning' : 'neutral',
          hint: 'Alerte : péremption sous 90 jours',
        },
      ]));

      if (sansSeuil.length) {
        host.appendChild(K.note('<strong>' + C.num(sansSeuil.length) + ' référence(s) sans seuil d’alerte.</strong> '
          + 'Sans seuil, aucune alerte n’est possible : le seuil se fixe référence par référence à l’écran '
          + '« Réactifs & consommables » — le document SAGE ne renseigne pas cette colonne.',
        { tone: 'warning', icon: 'triangle-alert' }));
      }

      /* Les demandes par section — la consommation de réactifs suit l'activité
         du laboratoire, et c'est la section qui dit quel automate travaille. */
      var demandes = S.collection('demandesAnalyses').active();
      var parSection = {};
      demandes.forEach(function (r) {
        var code = codeExamenDeStatique(r);
        var ex = code ? L.examen(code) : null;
        var sec = ex ? L.section(ex.section) : (r.categorie || 'Autres');
        parSection[sec] = (parSection[sec] || 0) + 1;
      });
      var secKeys = Object.keys(parSection).sort(function (a, b) { return parSection[b] - parSection[a]; });
      host.appendChild(U.card('Demandes d’analyses par section — activité qui consomme les réactifs',
        G.barres(secKeys, [{ label: 'Demandes', data: secKeys.map(function (k) { return parSection[k]; }) }],
          { horizontal: true, height: 260 })));

      host.appendChild(U.dataTable({
        title: 'Références de laboratoire — état du stock', rows: refs,
        exportName: 'reactifs-stats', pageSize: 15, searchable: true,
        defaultSort: 'stock', defaultDir: 'asc',
        columns: [
          { key: 'designation', label: 'Désignation' },
          { key: 'categorie', label: 'Catégorie', render: function (p) {
            return U.badge(p.categorie === 'reactif' ? 'Réactif' : 'Consommable labo',
              p.categorie === 'reactif' ? 'info' : 'neutral');
          } },
          { key: 'stock', label: 'Stock', align: 'right', value: function (p) { return p.stock || 0; } },
          {
            key: 'seuilAlerte', label: 'Seuil', align: 'right',
            render: function (p) {
              if (p.seuilAlerte == null) return el('span.text-xs.text-warning-700', { text: 'non fixé' });
              return el('span', {
                class: p.stock <= p.seuilAlerte ? 'font-semibold text-danger-700' : '',
                text: String(p.seuilAlerte),
              });
            },
          },
          {
            key: 'valeur', label: 'Valeur (P.A.)', align: 'right',
            value: function (p) { return (p.stock || 0) * (p.prixAchat || 0); },
            render: function (p) { return C.money((p.stock || 0) * (p.prixAchat || 0), false); },
          },
        ],
      }));
      U.icons(host);
      return null;
    },
  });

  /* ==========================================================================
   * BANQUE DE SANG
   * ======================================================================== */
  global.SIGH.screen('m5-banque-sang', {
    title: 'Banque de sang',
    description: 'Gestion des poches de sang par groupe, dates de péremption et demandes de transfusion.',
    render: function (root) {
      var col = S.collection('poches', { module: 'M5', entite: 'PocheSang' });
      if (!col.all().length && S.amorcable('poches')) {
        var rnd = C.seeded(701);
        D.GROUPES_SANGUINS.forEach(function (g) {
          var n = C.between(rnd, 2, 9);
          for (var i = 0; i < n; i++) {
            var jours = C.between(rnd, -10, 40);
            col.all().push({
              id: 'PS' + C.uid(), statut: 'actif',
              reference: 'PS-' + C.pad(col.all().length + 1, 4),
              groupe: g,
              volume: C.pick(rnd, [250, 350, 450]),
              datePrelevement: C.iso(C.addDays(AUJ, -(42 - jours))),
              datePeremption: C.iso(C.addDays(AUJ, jours)),
              donneur: 'Donneur ' + C.pad(C.between(rnd, 1, 60), 3),
              etat: jours < 0 ? 'perime' : (jours < 7 ? 'alerte' : 'actif'),
              reserve: rnd() > 0.8,
            });
          }
        });
        S.save();
      }

      var poches = col.active();
      var host = el('div.space-y-4');
      var disponibles = poches.filter(function (p) { return p.etat !== 'perime' && !p.reserve; });

      host.appendChild(U.kpiGrid([
        { label: 'Poches en stock', value: C.num(poches.length), icon: 'droplet', tone: 'navy' },
        { label: 'Disponibles', value: C.num(disponibles.length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Péremption sous 7 jours', value: C.num(poches.filter(function (p) { return p.etat === 'alerte'; }).length), icon: 'clock', tone: 'warning' },
        { label: 'Périmées à détruire', value: C.num(poches.filter(function (p) { return p.etat === 'perime'; }).length), icon: 'trash-2', tone: 'danger' },
      ]));

      /* Disponibilité par groupe */
      var grille = el('div.grid.gap-3', { class: 'grid-cols-2 sm:grid-cols-4 lg:grid-cols-8' });
      D.GROUPES_SANGUINS.forEach(function (g) {
        var dispo = disponibles.filter(function (p) { return p.groupe === g; }).length;
        var tone = dispo === 0 ? 'danger' : (dispo <= 2 ? 'warning' : 'success');
        var carte = el('div.rounded-xl.border.bg-white.p-3.text-center.shadow-card', { class: 'border-' + tone + '-200' });
        carte.appendChild(el('p.text-lg.font-bold', { class: 'text-' + tone + '-700', text: g }));
        carte.appendChild(el('p.mt-1.text-2xl.font-semibold.num.text-slate-900', { text: String(dispo) }));
        carte.appendChild(el('p.text-\\[10px\\].text-slate-400', { text: 'poche' + (dispo > 1 ? 's' : '') }));
        grille.appendChild(carte);
      });
      host.appendChild(U.card('Disponibilité par groupe sanguin', grille, [
        K.btn('Bon de demande de sang', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Bon de demande de sang',
              cartouche: [['Service demandeur', ''], ['Date', C.dateFR(AUJ)], ['Patient', ''], ['Groupe requis', '']],
              contenu: el('div.space-y-3', null, [
                P.tableau([
                  { label: 'Groupe sanguin', key: 'g' },
                  { label: 'Nombre de poches demandées', key: 'n' },
                  { label: 'Indication', key: 'i' },
                ], [{ g: '', n: '', i: '' }, { g: '', n: '', i: '' }]),
                el('p.mt-3.text-\\[10px\\]', { text: 'Disponibilité au ' + C.dateFR(AUJ) + ' : '
                  + D.GROUPES_SANGUINS.map(function (g) {
                    return g + ' (' + disponibles.filter(function (p) { return p.groupe === g; }).length + ')';
                  }).join(', ') }),
              ]),
              signatures: [{ role: 'Le Médecin prescripteur' }, { role: 'Le Laborantin', nom: 'KINNOU Addoul Ganiou' },
                { role: 'Le Directeur Médical', mention: 'Agrément' }],
            });
          },
        }),
      ]));

      host.appendChild(U.dataTable({
        title: 'Poches de sang', rows: poches, exportName: 'banque-sang', pageSize: 15,
        rowActions: K.actionsLigne(col, [
          { name: 'groupe', label: 'Groupe sanguin', type: 'select', required: true, options: D.GROUPES_SANGUINS },
          { name: 'volume', label: 'Volume (ml)', type: 'number', min: 0 },
          { name: 'datePrelevement', label: 'Date de prélèvement', type: 'date' },
          { name: 'datePeremption', label: 'Date de péremption', type: 'date', required: true },
          { name: 'donneur', label: 'Donneur' },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ]),
        defaultSort: 'datePeremption',
        filters: [
          { name: 'groupe', label: 'Groupe', options: D.GROUPES_SANGUINS },
          { name: 'etat', label: 'État', options: [{ value: 'actif', label: 'Disponible' }, { value: 'alerte', label: 'Péremption proche' }, { value: 'perime', label: 'Périmée' }] },
        ],
        columns: [
          { key: 'reference', label: 'N° poche', nowrap: true, render: function (p) { return el('span.font-mono.text-xs', { text: p.reference }); } },
          { key: 'groupe', label: 'Groupe', render: function (p) { return U.badge(p.groupe, 'danger'); } },
          { key: 'volume', label: 'Volume', align: 'right', render: function (p) { return p.volume + ' ml'; } },
          { key: 'datePrelevement', label: 'Prélèvement', nowrap: true, text: function (p) { return C.dateFR(p.datePrelevement); }, render: function (p) { return C.dateFR(p.datePrelevement); } },
          { key: 'datePeremption', label: 'Péremption', nowrap: true, text: function (p) { return C.dateFR(p.datePeremption); }, render: function (p) { return C.dateFR(p.datePeremption); } },
          {
            key: 'restant', label: 'Reste', align: 'right',
            value: function (p) { return C.daysBetween(AUJ, p.datePeremption); },
            render: function (p) {
              var j = C.daysBetween(AUJ, p.datePeremption);
              return j < 0 ? U.badge('Périmée', 'danger') : el('span.num', { class: j < 7 ? 'font-semibold text-warning-600' : '', text: j + ' j' });
            },
          },
          { key: 'donneur', label: 'Donneur' },
          { key: 'reserve', label: 'Réservée', text: function (p) { return p.reserve ? 'Oui' : 'Non'; }, render: function (p) { return p.reserve ? U.badge('Réservée', 'warning') : el('span.text-xs.text-slate-400', { text: '—' }); } },
        ],
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * DONNEURS & TRANSFUSIONS
   * ======================================================================== */
  global.SIGH.screen('m5-donneurs', {
    title: 'Donneurs & transfusions',
    description: 'Registre des donneurs de sang, dons réalisés et transfusions effectuées avec leur agrément.',
    render: function (root) {
      var col = S.collection('donneurs', { module: 'M5', entite: 'DonneurSang' });
      if (!col.all().length && S.amorcable('donneurs')) {
        var rnd = C.seeded(809);
        var pats = patients();
        for (var i = 0; i < 60; i++) {
          var p = C.pick(rnd, pats);
          col.all().push({
            id: 'DON' + C.pad(i + 1, 4), statut: 'actif',
            reference: 'DON-' + C.pad(i + 1, 4),
            nom: p.nom + ' ' + p.prenom, telephone: p.telephone,
            groupe: p.groupeSanguin,
            dernierDon: C.iso(C.addDays(AUJ, -C.between(rnd, 10, 400))),
            nbDons: C.between(rnd, 1, 12),
            eligible: rnd() > 0.2,
            type: C.pick(rnd, ['Bénévole', 'Familial', 'Familial', 'Compensation']),
          });
        }
        S.save();
      }

      return K.crud({
        collection: 'donneurs', entite: 'donneur', entiteP: 'donneurs', module: 'M5',
        defaultSort: 'dernierDon', defaultDir: 'desc',
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'nom', label: 'Donneur' },
          { key: 'groupe', label: 'Groupe', render: function (r) { return U.badge(r.groupe, 'danger'); } },
          { key: 'telephone', label: 'Téléphone', nowrap: true },
          { key: 'type', label: 'Type de don', render: function (r) { return U.badge(r.type, 'navy'); } },
          { key: 'nbDons', label: 'Dons', align: 'right' },
          { key: 'dernierDon', label: 'Dernier don', nowrap: true, text: function (r) { return C.dateFR(r.dernierDon); }, render: function (r) { return C.dateFR(r.dernierDon); } },
          {
            key: 'eligible', label: 'Éligibilité',
            text: function (r) { return r.eligible ? 'Éligible' : 'Non éligible'; },
            render: function (r) {
              var delai = C.daysBetween(r.dernierDon, AUJ);
              if (!r.eligible) return U.badge('Non éligible', 'danger');
              return delai >= 90 ? U.badge('Éligible', 'success') : U.badge('Délai ' + (90 - delai) + ' j', 'warning');
            },
          },
        ],
        fields: [
          { name: 'nom', label: 'Nom et prénoms', required: true, col: 'full' },
          { name: 'telephone', label: 'Téléphone', type: 'tel', required: true },
          { name: 'groupe', label: 'Groupe sanguin', type: 'select', required: true, options: D.GROUPES_SANGUINS },
          { name: 'type', label: 'Type de don', type: 'select', required: true, options: ['Bénévole', 'Familial', 'Compensation'] },
          { name: 'dernierDon', label: 'Date du dernier don', type: 'date' },
          { name: 'nbDons', label: 'Nombre total de dons', type: 'number', min: 0 },
          { name: 'eligible', label: 'Donneur éligible', type: 'checkbox' },
        ],
        onCreate: function () { return { eligible: true, nbDons: 1, type: 'Bénévole', dernierDon: C.iso(AUJ) }; },
        transform: function (v) { if (!v.reference) v.reference = C.nextRef('DON-', 4); return v; },
        filters: [
          { name: 'groupe', label: 'Groupe', options: D.GROUPES_SANGUINS },
          { name: 'type', label: 'Type de don', options: ['Bénévole', 'Familial', 'Compensation'] },
        ],
        kpis: function (rows) {
          return [
            { label: 'Donneurs enregistrés', value: C.num(rows.length), icon: 'users', tone: 'navy' },
            { label: 'Éligibles', value: C.num(rows.filter(function (r) { return r.eligible && C.daysBetween(r.dernierDon, AUJ) >= 90; }).length), icon: 'check-circle-2', tone: 'success' },
            { label: 'Dons cumulés', value: C.num(C.sum(rows, 'nbDons')), icon: 'droplet', tone: 'danger' },
            { label: 'Donneurs bénévoles', value: C.num(rows.filter(function (r) { return r.type === 'Bénévole'; }).length), icon: 'heart', tone: 'info' },
          ];
        },
        etat: function (r) {
          P.etat({
            titre: 'Carte de donneur de sang',
            cartouche: [['Donneur', r.nom], ['Référence', r.reference], ['Groupe sanguin', r.groupe],
              ['Type de don', r.type], ['Dons réalisés', String(r.nbDons)], ['Dernier don', C.dateFR(r.dernierDon)]],
            contenu: el('p', { text: 'La CLINIQUE NASSIERA TOO SARL remercie chaleureusement ce donneur pour son engagement au service de la collectivité.' }),
            signatures: [{ role: 'Le Laborantin', nom: 'KINNOU Addoul Ganiou' }, { role: 'Le Directeur Médical' }],
          });
        },
      })(root);
    },
  });
})(window);
