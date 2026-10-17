/* =============================================================================
 * M2 — Rendez-vous, Visites & Consultations (y compris à domicile)
 * -----------------------------------------------------------------------------
 * CDCT §10.5 et §10.6 — remplacement de l'agenda physique, registre des appels,
 * suivi des visites, consultations et soins à domicile avec facturation propre.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  /* Objets d'appel relevés au standard — liste administrable. */
  var OBJETS_APPEL = ['Prise de rendez-vous', 'Report de rendez-vous', 'Demande de résultat d’analyse',
    'Renseignement tarifaire', 'Suivi post-hospitalisation', 'Rappel de règlement',
    'Demande d’ambulance', 'Information administrative'];

  function patients() { return S.collection('patients').active(); }
  function medecins() {
    return S.collection('personnel').active().filter(function (e) { return e.fonction === 'medecin'; });
  }
  function optionsPatients() {
    return C.sortBy(patients(), 'code').map(function (p) {
      return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
    });
  }
  function optionsMedecins() {
    return medecins().map(function (m) { return { value: m.nomComplet, label: m.nomComplet }; });
  }

  /* --- Catalogues de prescription ------------------------------------------
   * Le prescripteur doit atteindre TOUT ce que la clinique sait faire : les
   * médicaments de la pharmacie, les 48 analyses, les actes de chaque secteur
   * et les catégories d'hospitalisation. Ces listes viennent des référentiels
   * administrables — rien n'est écrit ici.
   * ---------------------------------------------------------------------- */
  function optionsMedicaments() {
    return S.collection('produits').active()
      .filter(function (p) { return p.categorie === 'medicament' || p.categorie === 'conso_medical'; })
      .map(function (p) {
        return {
          value: p.id, label: p.designation,
          detail: C.money(p.prixAchat, false) + ' · stock ' + (p.stockDetail != null ? p.stockDetail : p.stock),
        };
      });
  }
  function optionsAnalyses() {
    return D.ANALYSES.map(function (a) {
      return { value: a.code, label: a.designation, detail: a.categorie + ' · ' + C.money(a.prix, false) };
    });
  }
  function optionsActes() {
    return S.collection('actes').active().map(function (a) {
      return {
        value: a.code, label: a.libelle,
        detail: a.secteur + (a.prix ? ' · ' + C.money(a.prix, false) : ' · tarif à valider'),
      };
    });
  }

  /* --- Colonnes communes --------------------------------------------------- */
  function colDate(label) {
    return {
      key: 'date', label: label || 'Date', nowrap: true,
      text: function (r) { return C.dateFR(r.date) + ' ' + C.heure(r.date); },
      render: function (r) {
        return el('div', null, [
          el('p.text-sm.text-slate-700', { text: C.dateFR(r.date) }),
          el('p.text-xs.text-slate-400', { text: C.heure(r.date) }),
        ]);
      },
      sortValue: function (r) { return C.toDate(r.date).getTime(); },
    };
  }
  var colPatient = {
    key: 'patient', label: 'Patient',
    render: function (r) {
      return el('div.min-w-0', null, [
        el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
        el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
      ]);
    },
  };

  /* --- Champs communs ------------------------------------------------------ */
  function champsConsultation() {
    return [
      { type: 'section', label: 'Patient et praticien' },
      { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, options: optionsPatients(), col: 'full' },
      { name: 'medecin', label: 'Praticien', type: 'select', required: true, options: optionsMedecins() },
      {
        name: 'type', label: 'Type', type: 'select', required: true,
        options: ['Consultation', 'Contrôle', 'Urgence', 'Domicile'],
      },
      { type: 'section', label: 'Rendez-vous' },
      { name: 'date', label: 'Date et heure', type: 'datetime-local', required: true },
      { name: 'motif', label: 'Motif', required: true, col: 'full' },
      { name: 'diagnostic', label: 'Diagnostic', col: 'full', type: 'textarea', rows: 2 },
      { name: 'tarif', label: 'Tarif (FCFA)', type: 'money', min: 0 },
      {
        name: 'statut', label: 'Statut', type: 'select', required: true,
        options: [{ value: 'planifiee', label: 'Planifiée' }, { value: 'en_cours', label: 'En cours' }, { value: 'terminee', label: 'Terminée' }],
      },
    ];
  }

  function completerPatient(v) {
    var p = patients().filter(function (x) { return x.code === v.patientCode; })[0];
    if (p) { v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom; }
    if (!v.reference) v.reference = C.nextRef('C', 5);
    return v;
  }

  /* --------------------------------------------------------------------------
   * FUSION RENDEZ-VOUS & VISITES (Bug 3 des Instructions, phase 3b)
   * --------------------------------------------------------------------------
   * L'accueil enregistre aussi des venues pour des INDIVIDUS NON ENREGISTRÉS —
   * visiteur, accompagnant, délégué, rendez-vous d'affaire privée avec la
   * Direction. Leur ouvrir un dossier patient polluerait la base médicale ;
   * les refuser ferait tenir un second agenda papier. Le formulaire porte donc
   * les deux voies : sélectionner un dossier, OU nommer le venu.
   * ------------------------------------------------------------------------ */
  /* --------------------------------------------------------------------------
   * LES CHAMPS DE LA PERSONNE NON ENREGISTRÉE (06/09/2026)
   * --------------------------------------------------------------------------
   * Un seul champ « nom et prénoms » ne suffisait pas : l'accueil doit pouvoir
   * RAPPELER la personne — d'où le téléphone — et savoir d'où elle vient —
   * d'où le quartier, qui est l'adresse telle qu'on la donne à Natitingou.
   * Ce sont exactement les quatre renseignements que porte le registre papier.
   *
   * Ils ne créent AUCUN dossier patient : ni code CNT, ni entrée au répertoire
   * médical (RG-01 protège la série, et un visiteur n'est pas un patient).
   * Un même jeu de champs sert la prise de rendez-vous et le passage sans
   * rendez-vous : deux formulaires auraient divergé au premier ajout.
   * ------------------------------------------------------------------------ */
  function champsNonEnregistre() {
    return [
      { name: '_sectionVisiteur', type: 'section', label: 'Ou personne NON enregistrée (sans dossier)' },
      { name: 'visiteurNom', label: 'Nom', help: 'Visiteur, accompagnant, client, affaire privée.' },
      { name: 'visiteurPrenom', label: 'Prénom(s)' },
      { name: 'visiteurQuartier', label: 'Quartier / résidence' },
      { name: 'visiteurTelephone', label: 'Numéro de téléphone', type: 'tel' },
    ];
  }

  /** Le nom affiché d'une personne non enregistrée, depuis ses champs. */
  function nomNonEnregistre(v) {
    return [String(v.visiteurNom || '').trim().toUpperCase(), String(v.visiteurPrenom || '').trim()]
      .filter(Boolean).join(' ');
  }

  function champsRendezVous() {
    function indexDe(champs, nom) {
      for (var i = 0; i < champs.length; i++) if (champs[i].name === nom) return i;
      return -1;
    }
    var champs = champsConsultation().slice();
    /* Le dossier n'est plus obligatoire : un individu non enregistré n'en a pas. */
    var iPat = indexDe(champs, 'patientCode');
    champs[iPat] = Object.assign({}, champs[iPat], {
      required: false,
      help: 'Laisser vide pour une personne non enregistrée — renseigner alors son identité ci-dessous.',
    });
    champs.splice.apply(champs, [iPat + 1, 0].concat(champsNonEnregistre()));
    /* Les natures de la cible : consultation, contrôle, urgence, visite,
       affaire privée. */
    var iType = indexDe(champs, 'type');
    champs[iType] = Object.assign({}, champs[iType], {
      options: ['Consultation', 'Contrôle', 'Urgence', 'Domicile', 'Visite', 'Affaire privée'],
    });
    return champs;
  }

  function validerVenue(v) {
    if (!v.patientCode && !(v.visiteurNom || '').trim()) {
      return 'Sélectionner un dossier patient, ou renseigner le nom de la personne non enregistrée.';
    }
    return null;
  }

  function completerVenue(v) {
    if (v.patientCode) return completerPatient(v);
    /* Personne non enregistrée : la venue porte son identité, PAS un dossier —
       aucun code CNT n'est consommé (RG-01 protège la série). */
    v.patient = nomNonEnregistre(v);
    v.patientCode = 'NON-PATIENT';
    v.patientId = null;
    v.nonPatient = true;
    if (!v.reference) v.reference = C.nextRef('C', 5);
    return v;
  }

  /* --- Détail d'une consultation ------------------------------------------- */  /* ==========================================================================
   * LA SUITE D’UN RENDEZ-VOUS — honoré, reporté, non honoré
   * --------------------------------------------------------------------------
   * Un rendez-vous honoré n’a plus rien à faire dans la fenêtre de l’agenda :
   * ce qu’on y cherche est ce qui RESTE à faire. Mais « apurer » ne veut pas
   * dire supprimer, ni même archiver : un rendez-vous honoré DEVIENT la
   * consultation — l’archiver effacerait l’acte des dossiers, des ordonnances
   * et des statistiques. Il change donc d’ONGLET, pas d’existence.
   *
   * Trois suites, et la troisième était absente : honoré, REPORTÉ (une
   * nouvelle date est fixée, l’ancienne reste écrite) et NON HONORÉ (le
   * patient n’est pas venu). Confondre les deux dernières ferait disparaître
   * l’absentéisme, qui est justement ce que l’accueil veut mesurer.
   * ======================================================================== */
  function colRdv() { return S.collection('consultations', { module: 'M2', entite: 'Consultation' }); }
  function estApure(r) { return r.statut === 'terminee'; }
  /** Un rendez-vous planifié dont la date est passée : le logiciel le SIGNALE, il ne tranche pas. */
  function enSouffrance(r) {
    return r.statut === 'planifiee' && C.iso(r.date) < C.iso(AUJ);
  }

  function marquerHonore(r, apres) {
    colRdv().update(r.id, { statut: 'terminee', honoreLe: new Date().toISOString() });
    U.toast('Rendez-vous honoré — il passe à l’onglet « Honorés » et quitte l’agenda.', { type: 'success' });
    if (apres) apres();
  }

  function marquerNonHonore(r, apres) {
    U.confirm({
      title: 'Marquer ce rendez-vous non honoré ?',
      message: 'Le rendez-vous reste dans l’agenda, signalé comme non honoré : c’est ce qui permet de rappeler le patient et de mesurer l’absentéisme. Le motif est conservé (RG-12).',
      confirmLabel: 'Marquer non honoré', requireMotif: true,
    }).then(function (res) {
      if (!res) return;
      colRdv().update(r.id, { statut: 'non_honore', motifNonHonore: res.motif,
        constateLe: new Date().toISOString() });
      U.toast('Rendez-vous marqué non honoré.', { type: 'success' });
      if (apres) apres();
    });
  }

  function reporter(r, apres) {
    var f = U.form([
      { name: 'nouvelleDate', label: 'Nouvelle date et heure', type: 'datetime-local', required: true,
        col: 'full' },
      { name: 'motifReport', label: 'Motif du report', type: 'select', required: true, col: 'full',
        options: ['Indisponibilité du praticien', 'Demande du patient', 'Urgence prioritaire',
          'Examen non disponible', 'Patient absent — nouvelle date convenue', 'Autre motif'] },
    ], {});
    var mo = U.modal({
      title: 'Reporter le rendez-vous',
      subtitle: r.patient + ' — ' + C.dateFR(r.date) + ' à ' + C.heure(r.date),
      size: 'md',
      body: el('div.space-y-3', null, [
        K.note('La date initiale reste écrite sur la fiche : un report dont on ne voit plus la date d’origine ne se distingue pas d’une saisie corrigée.', { tone: 'info', icon: 'calendar-clock' }),
        f,
      ]),
      footer: [
        K.btn('Annuler', { onclick: function () { mo.close(); } }),
        K.btn('Reporter', { variant: 'primary', icon: 'calendar-clock', onclick: function () {
          var v = f.collect();
          if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
          colRdv().update(r.id, {
            statut: 'reporte', dateInitiale: r.dateInitiale || r.date,
            date: v.nouvelleDate, motifReport: v.motifReport,
            reporteLe: new Date().toISOString(),
          });
          mo.close();
          U.toast('Rendez-vous reporté au ' + C.dateFR(v.nouvelleDate) + '.', { type: 'success' });
          if (apres) apres();
        } }),
      ],
    });
  }

  /** Les trois commandes de suite, absentes sans le droit d’écrire (RG-13). */
  function commandesSuite(r, apres) {
    return [
      r.statut !== 'terminee' ? K.commande('Marquer honoré', { icon: 'check-circle-2',
        moduleCode: 'M2', onclick: function () { marquerHonore(r, apres); } }) : null,
      r.statut !== 'terminee' ? K.commande('Reporter', { icon: 'calendar-clock',
        moduleCode: 'M2', onclick: function () { reporter(r, apres); } }) : null,
      r.statut !== 'terminee' && r.statut !== 'non_honore'
        ? K.commande('Marquer non honoré', { icon: 'user-x', moduleCode: 'M2',
          onclick: function () { marquerNonHonore(r, apres); } }) : null,
    ].filter(Boolean);
  }

  function detail(r) {
    var p = patients().filter(function (x) { return x.id === r.patientId; })[0];
    var wrap = el('div.space-y-4');
    wrap.appendChild(U.descList([
      ['Référence', el('span.font-mono', { text: r.reference || r.id })],
      ['Date', C.dateFR(r.date) + ' à ' + C.heure(r.date)],
      ['Patient', r.nonPatient
        ? el('span', null, [el('span', { text: r.patient + ' ' }), U.badge('individu non enregistré', 'info')])
        : r.patient],
      ['Dossier', el('span.font-mono', { text: r.nonPatient ? '— (sans dossier)' : r.patientCode })],
      ['Praticien', r.medecin],
      ['Type', r.type],
      ['Statut', U.statut(r.statut)],
      ['Tarif', C.money(r.tarif || 0)],
    ]));
    if (r.dateInitiale) {
      wrap.appendChild(K.note('Rendez-vous <strong>reporté</strong> — date initiale : '
        + C.dateFR(r.dateInitiale) + ' à ' + C.heure(r.dateInitiale)
        + (r.motifReport ? '. Motif : ' + r.motifReport : '') + '.',
      { tone: 'warning', icon: 'calendar-clock' }));
    }
    if (r.statut === 'non_honore') {
      wrap.appendChild(K.note('<strong>Non honoré</strong>' + (r.motifNonHonore ? ' — ' + r.motifNonHonore : '')
        + '. Le rendez-vous reste dans l’agenda : c’est là qu’on retrouve les patients à rappeler.',
      { tone: 'danger', icon: 'user-x' }));
    }
    if (enSouffrance(r)) {
      wrap.appendChild(K.note('La date de ce rendez-vous est <strong>passée</strong> et rien n’a été constaté. Le logiciel le signale ; c’est à l’accueil de dire s’il a été honoré, reporté ou non honoré — le décider tout seul inventerait une absence.',
      { tone: 'warning', icon: 'alert-triangle' }));
    }
    var suites = commandesSuite(r, function () { global.location.reload(); });
    if (suites.length) {
      wrap.appendChild(U.card('Suite du rendez-vous',
        el('div.flex.flex-wrap.gap-2', null, suites)));
    }
    wrap.appendChild(U.card('Motif et diagnostic', el('div.space-y-3', null, [
      el('div', null, [el('p.text-xs.text-slate-500', { text: 'Motif de consultation' }), el('p.mt-0\\.5.text-sm.text-slate-800', { text: r.motif || '—' })]),
      el('div', null, [el('p.text-xs.text-slate-500', { text: 'Diagnostic' }), el('p.mt-0\\.5.text-sm.text-slate-800', { text: r.diagnostic || 'Non renseigné' })]),
    ])));
    if (p && p.assureur) {
      wrap.appendChild(K.note('Patient couvert par <strong>' + p.assureurNom + '</strong> à hauteur de ' + p.tauxPriseEnCharge
        + ' %. La facturation appliquera la répartition patient / assureur (RG-09).', { tone: 'info', icon: 'shield-check' }));
    }
    return wrap;
  }

  /* --- État imprimable : compte rendu de consultation ---------------------- */
  function etatConsultation(r) {
    var p = patients().filter(function (x) { return x.id === r.patientId; })[0];
    var contenu = el('div.space-y-3');
    contenu.appendChild(el('p', null, [
      el('span.font-semibold', { text: 'Motif de consultation : ' }),
      el('span', { text: r.motif || '—' }),
    ]));
    contenu.appendChild(el('p', null, [
      el('span.font-semibold', { text: 'Diagnostic retenu : ' }),
      el('span', { text: r.diagnostic || '—' }),
    ]));
    contenu.appendChild(el('div.mt-4.min-h-\\[60mm\\].rounded.border.border-slate-300.p-3', null, [
      el('p.mb-2.text-\\[10px\\].font-semibold.uppercase.text-slate-500', { text: 'Observations et conduite à tenir' }),
      el('p.text-\\[10px\\].text-slate-400', { text: '(Espace réservé à la rédaction manuscrite ou à la saisie)' }),
    ]));
    P.etat({
      titre: 'Compte rendu de consultation',
      sousTitre: r.type + ' du ' + C.dateFR(r.date),
      cartouche: [
        ['Patient', r.patient], ['Dossier', r.patientCode],
        ['Âge', C.ageTexte(p)],
        ['Praticien', r.medecin],
        ['Référence', r.reference || r.id],
        ['Type', r.type],
      ],
      contenu: contenu,
      signatures: [{ role: 'Le Médecin traitant', nom: r.medecin }],
    });
  }

  /* ==========================================================================
   * AGENDA
   * ======================================================================== */
  /** Les pathologies actives du référentiel. */
  function pathologiesActives() {
    return S.collection('pathologies', { module: 'M2', entite: 'pathologie', prefix: 'PATH' }).active();
  }

  /** Options de sélection, groupées par chapitre pour rester lisibles. */
  function optionsPathologies() {
    return pathologiesActives().map(function (x) {
      var ch = D.CHAPITRES_PATHOLOGIE.filter(function (y) { return y.id === x.chapitre; })[0];
      return {
        value: x.code, label: x.libelle,
        detail: (ch ? ch.label : x.chapitre) + (x.notifiable ? ' · déclaration obligatoire' : ''),
      };
    });
  }

  /* ==========================================================================
   * LES DEUX PIÈCES QUE LE PATIENT EMPORTE
   * --------------------------------------------------------------------------
   * L'ordonnance va à la pharmacie, le bulletin d'analyses au laboratoire —
   * en passant tous deux par la caisse. Elles s'impriment depuis l'ordonnance
   * ENREGISTRÉE et jamais depuis l'état d'un formulaire : le papier doit dire
   * exactement ce qui est parti dans le logiciel, sans quoi la caisse encaisse
   * autre chose que ce que le laboratoire attend.
   * ======================================================================== */
  function etatOrdonnanceMedicale(r) {
    if (!r) return;
    var lignes = (r.medicaments || []).map(function (l) {
      return {
        produit: l.produit, detail: l.posologie || '',
        quantite: l.quantite + ' ' + (l.unite || ''), prix: l.prix, total: l.total,
      };
    });
    P.etat({
      titre: 'Ordonnance médicale',
      sousTitre: r.numero,
      cartouche: [['Patient', r.patient], ['Dossier', r.patientCode], ['Date', C.dateFR(r.date)],
        ['Prescripteur', r.medecin], ['Diagnostic', r.diagnostic || '—'],
        ['Règlement', r.statutPaiement === 'soldee' ? 'Réglée' : 'En attente']],
      contenu: [
        lignes.length ? P.tableau([
          { label: 'Désignation', key: 'produit' },
          { label: 'Posologie', key: 'detail' },
          { label: 'Quantité', align: 'right', key: 'quantite' },
          /* On ne totalise PAS le prix unitaire : additionner des prix
             unitaires ne produit aucune grandeur. */
          { label: 'Prix unitaire', align: 'right', value: function (l) { return C.money(l.prix, false); } },
          {
            label: 'Montant', align: 'right',
            value: function (l) { return C.money(l.total, false); },
            /* LA SOMME EST REFAITE DEPUIS LES LIGNES IMPRIMÉES. Le pied
               recevait un objet dont les clés — `prix`, `total` — ne
               correspondaient à AUCUNE colonne porteuse de `key` : il
               cherchait `total[undefined]` et n’affichait rien. Un pied vide
               se lit comme une mise en page, pas comme un défaut. */
            somme: function (l) { return l.total; },
          },
        ], lignes, { total: true }) : null,
        (r.analyses || []).length ? el('div', null, [
          el('p.mt-3.text-\[11px\].font-bold.uppercase', { text: 'Analyses demandées' }),
          P.tableau([
            { label: 'Analyse demandée', key: 'designation' },
            { label: 'Échantillon', key: 'echantillon' },
            { label: 'Tarif', align: 'right', value: function (l) { return C.money(l.prix, false); },
              somme: function (l) { return l.prix || 0; } },
          ], r.analyses, { total: true }),
        ]) : null,
        (r.actes || []).length ? el('div', null, [
          el('p.mt-3.text-\[11px\].font-bold.uppercase', { text: 'Actes prescrits' }),
          P.tableau([
            { label: 'Acte prescrit', key: 'libelle' },
            { label: 'Secteur', key: 'secteur' },
            { label: 'Tarif', align: 'right', value: function (l) { return l.prix ? C.money(l.prix, false) : 'à valider'; },
              somme: function (l) { return l.prix || 0; } },
          ], r.actes, { total: true }),
        ]) : null,
        !lignes.length && !(r.analyses || []).length && !(r.actes || []).length
          ? el('p.italic.text-slate-500', { text: 'Cette ordonnance ne porte aucune ligne.' }) : null,
      ],
      signatures: [{ role: 'Le Médecin prescripteur', nom: r.medecin, mention: 'Signature et cachet' },
        { role: 'Le Pharmacien', mention: 'Dispensation' }],
    });
  }

  /**
   * Le BULLETIN D'ANALYSES — la pièce que le patient porte à la caisse puis à
   * la salle de prélèvement. Sa forme suit le formulaire papier de la
   * clinique : identité, service demandeur, indication, urgence, puis les
   * examens groupés par section.
   */
  function etatBulletinAnalyses(r) {
    if (!r) return;
    var L = global.SIGH.labo;
    var pat = S.collection('patients').active().filter(function (x) {
      return x.code === r.patientCode || x.id === r.patientId;
    })[0];

    var lignes = (r.analyses || []).map(function (a) {
      var ex = L ? (L.examen(a.code) || L.EXAMENS.filter(function (x) {
        return x.designation.toUpperCase() === String(a.designation || '').toUpperCase();
      })[0]) : null;
      return {
        section: ex ? L.section(ex.section) : (a.categorie || '—'),
        designation: a.designation || (ex ? ex.designation : a.code),
        echantillon: a.echantillon || (ex ? ex.echantillon : '—'),
        prix: a.prix,
      };
    });

    P.etat({
      titre: 'Bulletin d’analyses bio-médicales',
      sousTitre: r.numero,
      cartouche: [
        ['Patient', r.patient], ['Dossier', r.patientCode],
        ['Âge', pat && pat.dateNaissance ? C.age(pat.dateNaissance) + ' ans' : '—'],
        ['Sexe', pat ? (pat.sexe === 'F' ? 'Féminin' : 'Masculin') : '—'],
        ['Date', C.dateFR(r.date)],
        ['Prescripteur', r.medecin],
        ['Indication', r.diagnostic || '—'],
        ['Service demandeur', r.serviceDemandeur || r.secteurDemandeur || '—'],
        ['Priorité', r.urgent ? 'URGENT' : 'Courant'],
        ['Règlement', r.statutPaiement === 'soldee' ? 'Réglé' : 'À régler à la caisse'],
      ],
      contenu: el('div.space-y-3', null, [
        lignes.length
          ? P.tableau([
            { label: 'Section', key: 'section' },
            { label: 'Examen demandé', key: 'designation' },
            { label: 'Échantillon', key: 'echantillon' },
            {
              label: 'Tarif', align: 'right',
              value: function (l) { return C.money(l.prix, false); },
              somme: function (l) { return l.prix; },
            },
          ], lignes, { total: true })
          : el('p.italic.text-slate-500', { text: 'Aucune analyse demandée sur cette ordonnance.' }),
        el('p.mt-3.text-\[10px\].italic', {
          text: 'Ce bulletin accompagne le patient à la caisse puis à la salle de prélèvement, et suit '
            + 'ensuite l’échantillon jusqu’au laboratoire. Le résultat est transmis au clinicien '
            + 'prescripteur ; il est remis directement au patient lorsque celui-ci est adressé de l’extérieur.',
        }),
      ]),
      signatures: [{ role: 'Le Médecin prescripteur', nom: r.medecin, mention: 'Signature et cachet' },
        { role: 'Le Préleveur', mention: 'Heure de prélèvement' }],
    });
  }

  global.SIGH.screen('m2-agenda', {
    title: 'Agenda',
    description: 'Vue calendaire des rendez-vous et consultations, par praticien et par jour.',
    regle: 'L’agenda ne montre pas que la semaine en cours : une <strong>plage de dates</strong> permet de '
      + 'retrouver les semaines passées ou à venir. Un rendez-vous se prend depuis cet écran, par praticien '
      + 'et par jour, et déclenche la notification du praticien concerné.',
    actions: function () {
      return [
        K.btn('Rendez-vous', { icon: 'calendar-check', onclick: function () { global.SIGH.app.go('m2-rendezvous'); } }),
        K.commande('Passage sans rendez-vous', { icon: 'user-check', onclick: function () { nouvelleVisite(); } }),
      ].filter(Boolean);
    },
    render: function (root) {
      var host = el('div.space-y-4');
      var cons = S.collection('consultations').active();
      /* Plage affichée — modifiable, pour retrouver une semaine passée. */
      var debutSel = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, -2)) });
      var finSel = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, 4)) });
      var semaine = [];
      function calculerJours() {
        semaine = [];
        var d = C.toDate(debutSel.value), f = C.toDate(finSel.value);
        var n = Math.max(1, Math.min(31, C.daysBetween(d, f) + 1));
        for (var i = 0; i < n; i++) semaine.push(C.addDays(d, i));
      }
      calculerJours();

      host.appendChild(U.kpiGrid([
        { label: 'Rendez-vous aujourd’hui', value: C.num(cons.filter(function (c) { return C.iso(c.date) === C.iso(AUJ); }).length), icon: 'calendar-check', tone: 'navy' },
        { label: 'Cette semaine', value: C.num(cons.filter(function (c) { return Math.abs(C.daysBetween(AUJ, c.date)) <= 3; }).length), icon: 'calendar-days', tone: 'info' },
        { label: 'À confirmer', value: C.num(cons.filter(function (c) { return c.statut === 'planifiee'; }).length), icon: 'clock', tone: 'warning' },
        { label: 'Praticiens', value: C.num(medecins().length), icon: 'user-round', tone: 'neutral' },
      ]));

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), debutSel]),
        el('div', null, [el('label.label', { text: 'Au' }), finSel]),
        K.btn('Semaine en cours', { icon: 'calendar-days', onclick: function () {
          debutSel.value = C.iso(C.addDays(AUJ, -2)); finSel.value = C.iso(C.addDays(AUJ, 4)); redessiner();
        } }),
        K.commande('Nouveau rendez-vous', { variant: 'primary', icon: 'plus', onclick: nouveauRdv }),
      ]));
      host.appendChild(barre);

      var carteGrille = el('div');
      host.appendChild(carteGrille);
      debutSel.addEventListener('change', redessiner);
      finSel.addEventListener('change', redessiner);

      function redessiner() {
        calculerJours();
        cons = S.collection('consultations').active();
        C.clear(carteGrille);
        carteGrille.appendChild(construireGrille());
        U.icons(carteGrille);
      }

      function construireGrille() {
      /* Grille de la plage choisie */
      var grille = el('div.grid.gap-3', { class: 'md:grid-cols-4 lg:grid-cols-7' });
      semaine.forEach(function (jour) {
        /* La grille suit la même règle que la liste : elle montre ce qui
           reste à faire. Un honoré y prendrait la place d’un à venir. */
        var duJour = C.sortBy(cons.filter(function (c) {
          return C.iso(c.date) === C.iso(jour) && !estApure(c);
        }), 'date');
        var estAuj = C.iso(jour) === C.iso(AUJ);
        var carte = el('div.rounded-xl.border.bg-white.p-3.shadow-card', {
          class: estAuj ? 'border-navy-400 ring-1 ring-navy-200' : 'border-slate-200',
        });
        carte.appendChild(el('p.text-xs.font-semibold.uppercase.tracking-wide', {
          class: estAuj ? 'text-navy-800' : 'text-slate-500',
          text: C.JOURS[jour.getDay()].slice(0, 3) + '. ' + jour.getDate(),
        }));
        carte.appendChild(el('p.mb-2.text-\\[10px\\].text-slate-400', { text: C.MOIS[jour.getMonth()] }));
        if (!duJour.length) {
          carte.appendChild(el('p.py-4.text-center.text-xs.text-slate-300', { text: 'Aucun' }));
        } else {
          var liste = el('div.space-y-1\\.5');
          duJour.slice(0, 6).forEach(function (c) {
            liste.appendChild(el('button.block.w-full.rounded-md.border.border-slate-200.px-2.py-1\\.5.text-left.transition-colors.hover\\:border-navy-300.hover\\:bg-navy-50', {
              type: 'button',
              onclick: function () {
                /* Bug 10 des Instructions : la fiche d'un rendez-vous porte
                   ÉDITER et SUPPRIMER dans son pied — consulter puis refaire
                   le tour de l'écran pour agir faisait perdre le geste. Les
                   commandes sont ABSENTES sans le droit, jamais grisées. */
                var colC = S.collection('consultations', { module: 'M2', entite: 'Consultation' });
                var t = U.drawer({
                  title: c.patient, subtitle: c.patientCode + ' — ' + C.dateFR(c.date), body: detail(c),
                  footer: [
                    K.btn('Imprimer', { icon: 'printer', onclick: function () { etatConsultation(c); } }),
                    K.commande('Éditer le rendez-vous', {
                      variant: 'primary', icon: 'pencil',
                      onclick: function () { t.close(); K.modifier(colC, champsRendezVous, c, redessiner); },
                    }),
                    /* Les trois suites, au même endroit que l’édition : c’est
                       le geste que l’accueil fait vingt fois par jour. */
                    K.commande('Marquer honoré', { icon: 'check-circle-2', moduleCode: 'M2',
                      onclick: function () { t.close(); marquerHonore(c, redessiner); } }),
                    K.commande('Reporter', { icon: 'calendar-clock', moduleCode: 'M2',
                      onclick: function () { t.close(); reporter(c, redessiner); } }),
                    K.commande('Non honoré', { icon: 'user-x', moduleCode: 'M2',
                      onclick: function () { t.close(); marquerNonHonore(c, redessiner); } }),
                    K.commande('Annuler le rendez-vous', {
                      variant: 'danger', icon: 'archive', droit: 'annuler',
                      onclick: function () {
                        t.close();
                        U.confirm({
                          title: 'Annuler ce rendez-vous ?',
                          message: 'Le rendez-vous est archivé (RG-14), pas supprimé : il reste consultable et l’opération est annulable.',
                          confirmLabel: 'Annuler le rendez-vous', danger: true, requireMotif: true,
                        }).then(function (r) {
                          if (!r) return;
                          var res = colC.archive(c.id, r.motif);
                          redessiner();
                          U.toast('Rendez-vous annulé.', { type: 'success', undo: function () { res.undo(); redessiner(); } });
                        });
                      },
                    }),
                  ].filter(Boolean),
                });
              },
            }, [
              el('span.block.text-\\[11px\\].font-semibold.text-navy-800', { text: C.heure(c.date) }),
              el('span.block.truncate.text-\\[11px\\].text-slate-600', { text: c.patient }),
              el('span.block.truncate.text-\\[10px\\].text-slate-400', { text: c.motif }),
            ]));
          });
          if (duJour.length > 6) liste.appendChild(el('p.text-center.text-\\[10px\\].text-slate-400', { text: '+ ' + (duJour.length - 6) + ' autre(s)' }));
          carte.appendChild(liste);
        }
        grille.appendChild(carte);
      });
      return U.card('Du ' + C.dateFR(semaine[0]) + ' au ' + C.dateFR(semaine[semaine.length - 1])
        + ' — ' + C.num(semaine.length) + ' jour(s)', grille,
        [K.lien('m2-rendezvous', 'Gérer les rendez-vous', { size: 'sm', icon: 'arrow-right' })]);
      }
      redessiner();
      setTimeout(rappelerEcheances, 900);

      /* --------------------------------------------------------------------
       * Prise de rendez-vous — par praticien et par jour, avec notification
       * sonore du praticien concerné (le personnel ne regarde pas l'écran en
       * permanence).
       * ------------------------------------------------------------------ */
      function nouveauRdv() {
        var f = U.form([
          { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, col: 'full', options: optionsPatients() },
          { name: 'medecin', label: 'Praticien', type: 'select', required: true, options: optionsMedecins() },
          {
            name: 'type', label: 'Nature', type: 'select', required: true,
            options: ['Consultation', 'Contrôle', 'Urgence'],
          },
          { name: 'date', label: 'Date et heure', type: 'datetime-local', required: true, value: new Date().toISOString().slice(0, 16) },
          { name: 'motif', label: 'Motif', required: true, col: 'full' },
          { name: 'tarif', label: 'Tarif prévu (FCFA)', type: 'money', min: 0 },
          { name: 'notifier', label: 'Notifier le praticien', type: 'checkbox', value: true },
        ], {});

        var m = U.modal({
          title: 'Nouveau rendez-vous', size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('Le rendez-vous est enregistré au nom du praticien choisi et apparaît immédiatement '
              + 'dans son agenda du jour. La notification sonore prévient le poste concerné.', { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer le rendez-vous', {
              variant: 'primary', icon: 'calendar-check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var notifier = v.notifier;
                delete v.notifier;
                v.statut = 'planifiee';
                v.date = new Date(v.date).toISOString();
                completerPatient(v);
                var res = S.collection('consultations', { module: 'M2', entite: 'Consultation' }).insert(v);
                m.close();
                redessiner();
                if (notifier) {
                  U.alerter('Rendez-vous transmis à ' + v.medecin + '.', {
                    son: 'rappel', type: 'success',
                    detail: v.patient + ' — ' + C.dateFR(v.date) + ' à ' + C.heure(v.date) + ' · ' + v.motif,
                    undo: function () { res.undo(); redessiner(); },
                  });
                } else {
                  U.toast('Rendez-vous enregistré.', {
                    type: 'success', detail: v.patient + ' — ' + C.dateFR(v.date),
                    undo: function () { res.undo(); redessiner(); },
                  });
                }
              },
            }),
          ],
        });
      }

      /* Rappel des échéances proches — consultations, rendez-vous, réunions.
         C'est la notification automatique demandée : elle se déclenche à
         l'ouverture de l'agenda, sans action de l'utilisateur. */
      function rappelerEcheances() {
        var maintenant = AUJ.getTime();
        var proches = S.collection('consultations').active().filter(function (c) {
          if (c.statut !== 'planifiee') return false;
          var t = C.toDate(c.date).getTime();
          return t >= maintenant && t - maintenant <= 2 * 3600000;
        });
        var reunions = [];
        try {
          reunions = S.collection('reunions').active().filter(function (r) {
            return C.iso(r.date) === C.iso(AUJ);
          });
        } catch (e) { /* le module M13 peut ne pas avoir amorcé ses réunions */ }

        if (!proches.length && !reunions.length) return;
        var parts = [];
        if (proches.length) parts.push(proches.length + ' consultation(s) dans les deux heures');
        if (reunions.length) parts.push(reunions.length + ' réunion(s) aujourd’hui');
        U.alerter('Échéances du jour : ' + parts.join(' · '), {
          son: 'information', type: 'info',
          detail: proches.length ? 'Prochaine : ' + proches[0].patient + ' à ' + C.heure(proches[0].date) : null,
        });
      }

      host.appendChild(K.charts([
        {
          title: 'Charge par praticien (30 derniers jours)',
          render: function () {
            var recent = cons.filter(function (c) { return C.daysBetween(c.date, AUJ) <= 30 && C.daysBetween(c.date, AUJ) >= 0; });
            var g = C.groupBy(recent, 'medecin');
            return K.ranking(Object.keys(g).map(function (k) { return { label: k, value: g[k].length }; })
              .sort(function (a, b) { return b.value - a.value; }));
          },
        },
        {
          title: 'Répartition par type',
          render: function () {
            var g = C.groupBy(cons, 'type');
            var keys = Object.keys(g);
            return G.anneau(keys, keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
          },
        },
      ]));
      root.appendChild(host);
      return null;

      /* ------------------------------------------------------------------
       * Passage sans rendez-vous : le patient se présente, l'accueil
       * l'enregistre et l'oriente. Si le dossier n'existe pas encore, il se
       * crée ici même — on ne renvoie pas un patient au comptoir voisin.
       * ---------------------------------------------------------------- */
    },
  });

  /* --------------------------------------------------------------------------
   * ENREGISTRER UNE VISITE SANS RENDEZ-VOUS — Bug 0a des Instructions
   * --------------------------------------------------------------------------
   * DÉCLARÉE AU MODULE, et non plus dans la fermeture de l'écran agenda :
   * le bouton « Nouvelle visite » de m2-visites l'appelait aussi, et une
   * fonction déclarée dans la fermeture d'un écran est INVISIBLE au suivant —
   * le clic levait une ReferenceError que ni check.js ni la lecture ne
   * voyaient. Le piège documenté du prototype, rencontré une fois de plus.
   * ------------------------------------------------------------------------ */
  function nouvelleVisite() {
    var f = U.form([
      /* LE DOSSIER N'EST PLUS OBLIGATOIRE (06/09/2026) : se présentent aussi
         des personnes qui ne sont pas des patients — un client qui vient
         retirer un résultat, un accompagnant, un fournisseur. Les renvoyer
         faute de dossier ferait tenir un second registre au comptoir. */
      { name: 'patientCode', label: 'Patient (dossier du répertoire)', type: 'select', col: 'full',
        options: optionsPatients(),
        help: 'Laisser vide si la personne n’est pas un patient — remplir alors les champs ci-dessous.' },
    ].concat(champsNonEnregistre()).concat([
      { name: '_sectionPassage', type: 'section', label: 'Le passage' },
      { name: 'date', label: 'Heure d’arrivée', type: 'datetime-local', required: true, value: new Date().toISOString().slice(0, 16) },
      { name: 'motif', label: 'Motif du passage', required: true, col: 'full' },
      {
        name: 'type', label: 'Nature', type: 'select', required: true,
        options: ['Consultation', 'Urgence', 'Contrôle'],
      },
      {
        name: 'orientation', label: 'Orientation', type: 'select', required: true,
        options: ['Médecine générale', 'Chirurgie', 'Maternité', 'Laboratoire', 'Imagerie / Échographie',
          'Salle de soins', 'Mise en observation', 'Pharmacie', 'Retour à domicile'],
        help: 'Service vers lequel le patient est dirigé après l’accueil.',
      },
      { name: 'medecin', label: 'Praticien pressenti', type: 'select', options: optionsMedecins() },
      { name: 'priorite', label: 'Passage prioritaire', type: 'checkbox' },
      { name: 'tarif', label: 'Tarif de la consultation (FCFA)', type: 'money', min: 0 },
    ]), {});

    var m = U.modal({
      title: 'Enregistrer un passage sans rendez-vous', size: 'lg',
      body: el('div.space-y-3', null, [
        K.note('L’heure d’arrivée est tracée : c’est elle qui mesure l’attente à l’accueil. '
          + 'L’orientation dirige le patient vers le service compétent et prépare sa prise en charge.', { tone: 'info' }),
        K.note('Deux voies, et une seule à la fois : <strong>sélectionner un patient</strong> du '
          + 'répertoire, <strong>ou</strong> renseigner nom, prénom, quartier et téléphone d’une '
          + 'personne non enregistrée. Cette seconde voie <strong>n’ouvre aucun dossier médical</strong> '
          + 'et ne consomme aucun code CNT (RG-01).', { tone: 'info', icon: 'user-plus' }),
        f,
      ]),
      footer: [
        K.btn('Annuler', { onclick: function () { m.close(); } }),
        K.btn('Enregistrer le passage', {
          variant: 'primary', icon: 'user-check',
          onclick: function () {
            var v = f.collect();
            if (!v) return;
            var refus = validerVenue(v);
            if (refus) { U.toast(refus, { type: 'error' }); return; }
            var prioritaire = v.priorite;
            delete v.priorite;
            v.statut = 'en_cours';
            v.date = new Date(v.date).toISOString();
            v.sansRendezVous = true;
            /* La MÊME fabrique que la prise de rendez-vous : patient du
               répertoire, ou personne non enregistrée. Deux chemins d'écriture
               auraient produit deux formes de venue dans la même collection. */
            completerVenue(v);
            var res = S.collection('consultations', { module: 'M2', entite: 'Consultation' }).insert(v);
            m.close();
            if (prioritaire) {
              U.alerter('Passage prioritaire — ' + v.patient + ' orienté vers ' + v.orientation + '.', {
                son: 'alerte', type: 'warning', detail: v.motif,
              });
            } else {
              U.toast('Passage enregistré — ' + v.patient + '.', {
                type: 'success', detail: 'Orienté vers ' + v.orientation,
                undo: function () { res.undo(); },
              });
            }
            setTimeout(function () { global.location.reload(); }, 900);
          },
        }),
      ],
    });
  }

  /* ==========================================================================
   * RENDEZ-VOUS
   * ======================================================================== */
  global.SIGH.screen('m2-rendezvous', {
    title: 'Rendez-vous & visites',
    description: 'Prise de rendez-vous et enregistrement des venues — patients, individus non enregistrés, affaires privées.',
    regle: 'Écran UNIQUE (Bug 3 des Instructions, fusion achevée le 06/09/2026) : rendez-vous de '
      + 'consultation, de contrôle, <strong>passages sans rendez-vous</strong> et <strong>affaires '
      + 'privées</strong> s’enregistrent ici, pour un patient du répertoire <strong>ou une personne non '
      + 'enregistrée</strong> — dont on relève nom, prénom, quartier et téléphone sans lui ouvrir de '
      + 'dossier ni consommer de code CNT (RG-01). Deux filtres les distinguent — « Venue » et '
      + '« Venu » — parce qu’une même population lue selon deux axes vaut mieux que deux registres qui '
      + 'divergent. La plage de dates FILTRE la liste : « les rendez-vous du 21 août » ne se répond pas en triant.',
    actions: function () {
      return [
        K.btn('Agenda', { icon: 'calendar-days', onclick: function () { global.SIGH.app.go('m2-agenda'); } }),
        K.commande('Passage sans rendez-vous', { variant: 'primary', icon: 'user-check',
          onclick: function () { nouvelleVisite(); } }),
      ].filter(Boolean);
    },
    render: K.crud({
      collection: 'consultations', entite: 'rendez-vous', entiteP: 'rendez-vous', module: 'M2',
      defaultSort: 'date', defaultDir: 'desc', formSize: 'lg',
      source: 'Agenda physique de l’accueil — CDCT §10.6 ; fusion RDV + visites : Instructions, Bug 3.',
      /* L’AGENDA EST APURÉ : la liste ne porte que ce qui reste à faire —
         à venir, reportés, non honorés. Les honorés basculent dans leur
         propre onglet ; ils ne sont ni supprimés ni archivés, parce qu’un
         rendez-vous honoré EST la consultation (RG-14). */
      tabLabel: 'Agenda — à venir, reportés, non honorés',
      filtreBase: function (r) { return !estApure(r); },
      extraTabs: function () {
        return [{
          id: 'honores', label: 'Honorés (apurés de l’agenda)',
          badge: S.collection('consultations').active().filter(estApure).length,
          render: function () {
            var rows = C.sortBy(S.collection('consultations').active().filter(estApure), 'date', 'desc');
            if (!rows.length) return U.empty('Aucun rendez-vous honoré.', { icon: 'check-circle-2' });
            return el('div.space-y-3', null, [
              K.note('Ces rendez-vous ont été honorés : ils sont <strong>sortis de l’agenda</strong> mais restent au dossier du patient — un rendez-vous honoré est la consultation elle-même, l’archiver effacerait l’acte.', { tone: 'success', icon: 'archive' }),
              U.dataTable({
                title: 'Rendez-vous honorés', rows: rows, exportName: 'rendez-vous-honores', pageSize: 15,
                defaultSort: 'date', defaultDir: 'desc',
                columns: [
                  { key: 'reference', label: 'N°', nowrap: true,
                    render: function (r) { return el('span.font-mono.text-xs', { text: r.reference || '—' }); } },
                  { key: 'date', label: 'Date et heure', nowrap: true,
                    text: function (r) { return C.dateFR(r.date) + ' ' + C.heure(r.date); },
                    render: function (r) { return C.dateFR(r.date) + ' à ' + C.heure(r.date); } },
                  { key: 'patient', label: 'Patient' },
                  { key: 'medecin', label: 'Praticien' },
                  { key: 'motif', label: 'Motif' },
                  { key: 'type', label: 'Type' },
                ],
                onRowClick: function (r) {
                  U.drawer({ title: r.patient, subtitle: r.patientCode + ' — ' + C.dateFR(r.date),
                    body: detail(r), width: 'max-w-2xl',
                    footer: [K.btn('Imprimer', { icon: 'printer', onclick: function () { etatConsultation(r); } })] });
                },
              }),
            ]);
          },
        }];
      },
      /* Bug 11 : le FILTRE par plage de dates, avec ses raccourcis. */
      plageDates: { champ: 'date', aujourdhui: AUJ },
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference || '—' }); } },
        colDate('Date et heure'), colPatient,
        { key: 'medecin', label: 'Praticien' },
        { key: 'motif', label: 'Motif' },
        { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type, r.type === 'Urgence' ? 'danger' : 'navy'); } },
        { key: 'statut', label: 'Statut', render: function (r) { return U.statut(r.statut); } },
      ],
      fields: champsRendezVous, transform: completerVenue, beforeSave: validerVenue,
      onCreate: function () { return { statut: 'planifiee', type: 'Consultation', tarif: 3000 }; },
      filters: [
        { name: 'statut', label: 'Statut', options: [{ value: 'planifiee', label: 'Planifiée' },
          { value: 'en_cours', label: 'En cours' }, { value: 'reporte', label: 'Reporté' },
          { value: 'non_honore', label: 'Non honoré' }, { value: 'terminee', label: 'Honoré' }] },
        /* Ce que l’accueil cherche vraiment le matin : ce qui a débordé. */
        { name: 'souffrance', label: 'À statuer', options: [
          { value: 'oui', label: 'Date passée, rien de constaté' },
          { value: 'non', label: 'À jour' }],
          match: function (r, v) { return v === 'oui' ? enSouffrance(r) : !enSouffrance(r); } },
        { name: 'type', label: 'Type', options: ['Consultation', 'Contrôle', 'Urgence', 'Domicile', 'Visite', 'Affaire privée'] },
        { name: 'medecin', label: 'Praticien', options: optionsMedecins() },
        { name: 'venu', label: 'Venu', options: [{ value: 'patient', label: 'Patients du répertoire' }, { value: 'externe', label: 'Personnes non enregistrées' }],
          match: function (r, v) { return v === 'externe' ? !!r.nonPatient : !r.nonPatient; } },
        /* La fusion du registre des visites (06/09/2026) : le même écran tient
           les rendez-vous PRIS et les passages SPONTANÉS — c'est un filtre qui
           les distingue, pas un second écran. */
        { name: 'venue', label: 'Venue', options: [{ value: 'rdv', label: 'Sur rendez-vous' }, { value: 'sans', label: 'Sans rendez-vous' }],
          match: function (r, v) { return v === 'sans' ? !!r.sansRendezVous : !r.sansRendezVous; } },
      ],
      kpis: function (rows) {
        /* Les indicateurs comptent CE QUE L’AGENDA MONTRE — ce qui reste à
           faire. Le nombre d’honorés se lit à son onglet ; le mêler ici
           gonflerait un agenda qu’on vient précisément d’apurer. */
        return [
          { label: 'Dans l’agenda', value: C.num(rows.length), icon: 'calendar-days', tone: 'navy',
            hint: 'à venir, reportés ou non honorés' },
          { label: 'À venir', value: C.num(rows.filter(function (r) { return r.statut === 'planifiee' && !enSouffrance(r); }).length), icon: 'clock', tone: 'info' },
          { label: 'Reportés', value: C.num(rows.filter(function (r) { return r.statut === 'reporte'; }).length), icon: 'calendar-clock', tone: 'warning' },
          { label: 'Non honorés & à statuer', value: C.num(rows.filter(function (r) { return r.statut === 'non_honore' || enSouffrance(r); }).length), icon: 'user-x', tone: 'danger', hint: 'patients à rappeler' },
        ];
      },
      detail: detail, etat: etatConsultation,
    }),
  });

  /* ==========================================================================
   * VISITES
   * ======================================================================== */
  /* ==========================================================================
   * REGISTRE DES VISITES — PAGE-RENVOI
   * --------------------------------------------------------------------------
   * FUSIONNÉ dans « Rendez-vous & visites » le 06/09/2026 : un seul écran tient
   * les rendez-vous pris et les passages spontanés, et deux filtres les
   * distinguent. Deux registres sur la même collection finissaient toujours
   * par ne pas dire la même chose — l'un filtrait « type !== Domicile »,
   * l'autre non.
   *
   * La PAGE subsiste hors ruban et renvoie : retirer une entrée du manifeste
   * casserait tout lien et toute surcharge qui la visent.
   * ======================================================================== */
  global.SIGH.screen('m2-visites', {
    title: 'Registre des visites de suivi clinique',
    description: 'Fusionné dans « Rendez-vous & visites » — un seul écran tient les venues, avec ou sans rendez-vous.',
    render: function (root) {
      root.appendChild(el('div.mx-auto.max-w-xl.space-y-4.py-10', null, [
        K.note('Le registre des visites est <strong>fusionné dans « Rendez-vous & visites »</strong> : '
          + 'les venues sur rendez-vous et les passages spontanés s’y tiennent ensemble, et le filtre '
          + '<strong>Venue</strong> les sépare. C’est là aussi que s’enregistre une personne non '
          + 'enregistrée — nom, prénom, quartier, téléphone — sans lui ouvrir de dossier.',
        { tone: 'info', icon: 'merge' }),
        el('div.flex.flex-wrap.justify-center.gap-2', null, [
          K.btn('Ouvrir Rendez-vous & visites', {
            variant: 'primary', icon: 'calendar-check',
            onclick: function () { global.SIGH.app.go('m2-rendezvous'); },
          }),
          K.btn('Agenda', { icon: 'calendar-days', onclick: function () { global.SIGH.app.go('m2-agenda'); } }),
        ]),
      ]));
      return null;
    },
  });

  /* ==========================================================================
   * CONSULTATIONS
   * ======================================================================== */
  global.SIGH.screen('m2-consultations', {
    title: 'Consultations',
    description: 'Enregistrement des consultations, diagnostics et actes réalisés, avec édition du compte rendu.',
    render: K.crud({
      collection: 'consultations', entite: 'consultation', entiteP: 'consultations', module: 'M2',
      defaultSort: 'date', defaultDir: 'desc', formSize: 'lg',
      columns: [
        colDate(), colPatient,
        { key: 'motif', label: 'Motif' },
        { key: 'diagnostic', label: 'Diagnostic' },
        { key: 'medecin', label: 'Praticien' },
        { key: 'tarif', label: 'Tarif', align: 'right', text: function (r) { return C.money(r.tarif || 0, false); }, render: function (r) { return C.money(r.tarif || 0, false); } },
        { key: 'statut', label: 'Statut', render: function (r) { return U.statut(r.statut); } },
      ],
      fields: champsConsultation, transform: completerPatient,
      onCreate: function () { return { statut: 'en_cours', type: 'Consultation', tarif: 3000, date: new Date().toISOString().slice(0, 16) }; },
      filters: [
        { name: 'statut', label: 'Statut', options: [{ value: 'planifiee', label: 'Planifiée' }, { value: 'en_cours', label: 'En cours' }, { value: 'terminee', label: 'Terminée' }] },
        { name: 'medecin', label: 'Praticien', options: optionsMedecins() },
      ],
      kpis: function (rows) {
        var mois = rows.filter(function (r) {
          var d = C.toDate(r.date);
          return d.getFullYear() === AUJ.getFullYear() && d.getMonth() === AUJ.getMonth();
        });
        return [
          { label: 'Consultations totales', value: C.num(rows.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'Ce mois-ci', value: C.num(mois.length), icon: 'calendar-check', tone: 'success' },
          { label: 'Recette consultations', value: C.money(C.sum(rows, 'tarif')), icon: 'coins', tone: 'info' },
          { label: 'Tarif moyen', value: C.money(rows.length ? C.sum(rows, 'tarif') / rows.length : 0), icon: 'trending-up', tone: 'neutral' },
        ];
      },
      detail: detail, etat: etatConsultation,
    }),
  });

  /* ==========================================================================
   * ZONE 2 — LE DOSSIER PUIS LA FICHE DE CONSULTATION (refonte du 14/09/2026)
   * --------------------------------------------------------------------------
   * La METHODOLOGIE remise par la Direction fixe une chronologie STRICTE :
   *
   *   1. Zone 1 — l'ACCUEIL identifie, vérifie la couverture et relève les
   *      constantes de base (température, poids, taille, TA, pouls, SpO₂) ;
   *      il saisit et VERROUILLE : le médecin les lit, il ne les réécrit pas.
   *   2. DOSSIER DE CONSULTATION — le médecin consigne l'anamnèse, les
   *      antécédents et l'EXAMEN CLINIQUE STRUCTURÉ (IPPOA) par appareil.
   *   3. FICHE DE CONSULTATION — la synthèse : le récapitulatif du dossier,
   *      le diagnostic (référentiel de morbidité) et la conduite à tenir.
   *   4. La PRESCRIPTION n'existe QU'À la fiche : médicaments (pharmacie),
   *      analyses (laboratoire), imagerie médicale (poste d'imagerie).
   *   5. La CAISSE reçoit UNE facture globale, part assureur / part patient,
   *      et l'exécution d'aval reste BLOQUÉE jusqu'au règlement.
   *
   * POURQUOI LE DOSSIER DOIT ÊTRE ENREGISTRÉ AVANT LA FICHE : la fiche en fait
   * le récapitulatif. Une fiche ouverte sans dossier prescrirait sur un examen
   * que personne n'a consigné — et c'est exactement ce que la Direction veut
   * rendre impossible. La fiche REFUSE donc, en nommant l'écran où aller.
   *
   * Les deux écrans vivent dans CE module (M2) : la page du dossier et celle
   * de la fiche ne chargent que lui, et un moteur écrit en deux exemplaires
   * divergerait au premier correctif. Tout ce que les deux écrans partagent
   * est déclaré ICI, au module — une fonction posée dans la fermeture d'un
   * écran est invisible de l'autre.
   * ======================================================================== */
  function colDossiersCons() {
    return S.collection('dossiersConsultation', { module: 'M2', entite: 'dossier de consultation', prefix: 'DOS' });
  }
  function etatDossierCons(code) {
    return D.etatDossier ? D.etatDossier(code) : { code: code, label: code, couleur: 'neutral', suivants: [] };
  }
  function patientParCode(code) {
    return patients().filter(function (x) { return x.code === code; })[0] || null;
  }
  function libelleTypeVenue(code) {
    var t = (D.TYPES_VENUE || []).filter(function (x) { return x.value === code; })[0];
    return t ? t.label : (code || '—');
  }
  function libelleEtatGeneral(code) {
    var t = (D.ETATS_GENERAUX || []).filter(function (x) { return x.value === code; })[0];
    return t ? t.label : (code || '—');
  }
  /** Les praticiens qui tiennent un dossier : médecins et sages-femmes du personnel. */
  function optionsPraticiensDossier() {
    return S.collection('personnel').active()
      .filter(function (e) { return ['medecin', 'sage_femme', 'chirurgien'].indexOf(e.fonction) !== -1; })
      .map(function (e) { return { value: e.nomComplet, label: e.nomComplet, detail: e.poste || e.fonction }; });
  }
  /** Le dossier d'un patient EST-IL enregistré ? « En attente » : inscrit, jamais examiné. */
  function dossierEnregistre(d) {
    return !!d && d.statut !== 'archive' && (d.etat === 'consultation' || d.etat === 'attente_labo');
  }
  /**
   * Le dossier ACTIF d'un patient — celui sur lequel la fiche s'appuie : le
   * plus récent des dossiers enregistrés (en consultation, ou en attente des
   * résultats qu'on vient relire).
   */
  function dossierActifDe(patientCode) {
    return colDossiersCons().active()
      .filter(function (d) { return d.patientCode === patientCode && dossierEnregistre(d); })
      .sort(function (a, b) {
        return String(b.dossierSaisiLe || b.ouvertLe || b.dateArrivee || '')
          .localeCompare(String(a.dossierSaisiLe || a.ouvertLe || a.dateArrivee || ''));
      })[0] || null;
  }

  /* --------------------------------------------------------------------------
   * LES CONSTANTES DE LA ZONE 1 — LUES, JAMAIS RESSAISIES
   * --------------------------------------------------------------------------
   * Le relevé vient de la collection `constantes`, tenue par l'accueil
   * (m1-constantes). Le dossier en garde une COPIE datée au moment où il est
   * enregistré (`constantesAccueil`) : le médecin a examiné sur CES valeurs, et
   * un relevé ultérieur ne doit pas réécrire ce qu'il avait sous les yeux. Les
   * dossiers d'avant la refonte portaient leurs constantes à plat : on les lit
   * telles quelles, en le disant.
   * ------------------------------------------------------------------------ */
  function dernierReleve(patientCode, patientId) {
    return S.collection('constantes').active()
      .filter(function (r) { return r.patientCode === patientCode || (patientId && r.patientId === patientId); })
      .sort(function (a, b) { return String(b.dateHeure || '').localeCompare(String(a.dateHeure || '')); })[0] || null;
  }
  function copieReleve(r) {
    if (!r) return null;
    return {
      releveId: r.id || null, dateHeure: r.dateHeure || null, releveePar: r.releveePar || null,
      temperature: r.temperature != null ? r.temperature : null, poids: r.poids != null ? r.poids : null,
      taille: r.taille != null ? r.taille : null, tension: r.tension || null,
      pouls: r.pouls != null ? r.pouls : null, spo2: r.spo2 != null ? r.spo2 : null,
      imc: r.imc != null ? r.imc : ((r.poids && r.taille) ? Math.round((r.poids / Math.pow(r.taille / 100, 2)) * 10) / 10 : null),
    };
  }
  function constantesDuDossier(d) {
    if (d && d.constantesAccueil) return { valeurs: d.constantesAccueil, source: 'copie' };
    if (d && (d.temperature != null || d.tension || d.pouls != null)) {
      return { valeurs: copieReleve(d), source: 'ancienne' };
    }
    return null;
  }
  function blocConstantes(c) {
    if (!c || !c.valeurs) {
      return K.note('Aucun relevé de constantes de l’accueil pour ce patient. Les constantes se relèvent à '
        + '<strong>l’accueil</strong> (« Constantes à l’arrivée ») — elles ne se saisissent pas ici.',
      { tone: 'warning', icon: 'thermometer' });
    }
    var v = c.valeurs;
    var origine = c.source === 'ancienne'
      ? 'Constantes portées par le dossier (saisie antérieure à la refonte).'
      : (c.source === 'copie'
        ? 'Relevé de l’accueil du ' + C.dateFR(v.dateHeure) + ' ' + C.heure(v.dateHeure)
          + ', figé à l’enregistrement du dossier — lecture seule.'
        : 'Relevé de l’accueil du ' + C.dateFR(v.dateHeure) + ' ' + C.heure(v.dateHeure)
          + (v.releveePar ? ' par ' + v.releveePar : '') + ' — saisi et verrouillé par l’accueil, lecture seule.');
    return el('div.space-y-2', null, [
      el('div.grid.grid-cols-2.gap-2.sm\\:grid-cols-4.lg\\:grid-cols-7', null, [
        ['Température', v.temperature != null ? v.temperature + ' °C' : '—'],
        ['TA', v.tension || '—'],
        ['Pouls', v.pouls != null ? v.pouls + ' bpm' : '—'],
        ['SpO₂', v.spo2 != null ? v.spo2 + ' %' : '—'],
        ['Poids', v.poids != null ? v.poids + ' kg' : '—'],
        ['Taille', v.taille != null ? v.taille + ' cm' : '—'],
        ['IMC', v.imc != null ? String(v.imc) : '—'],
      ].map(function (x) {
        return el('div.rounded-lg.border.border-slate-200.bg-slate-50.px-3.py-2', null, [
          el('p.text-\\[11px\\].uppercase.tracking-wide.text-slate-500', { text: x[0] }),
          el('p.text-sm.font-semibold.text-slate-800', { text: x[1] }),
        ]);
      })),
      el('p.flex.items-center.gap-1.text-xs.text-slate-500', null, [C.icon('lock', 'h-3.5 w-3.5'), el('span', { text: origine })]),
    ]);
  }

  /* --------------------------------------------------------------------------
   * LE RÉCAPITULATIF DU DOSSIER — une mécanique, trois portes
   * (tiroir du registre, fiche de consultation, impression)
   * ------------------------------------------------------------------------ */
  function antecedentsObstetricauxLisibles(o) {
    if (!o) return null;
    var t = [];
    if (o.gestite != null) t.push('G' + o.gestite);
    if (o.parite != null) t.push('P' + o.parite);
    if (o.enfantsVivants != null) t.push(o.enfantsVivants + ' enfant(s) vivant(s)');
    if (o.faussesCouches) t.push(o.faussesCouches + ' fausse(s) couche(s)');
    if (o.enfantsDecedes) t.push(o.enfantsDecedes + ' enfant(s) décédé(s)');
    if (o.ageDerniereGrossesse != null) t.push('dernière grossesse à ' + o.ageDerniereGrossesse + ' ans');
    if (o.ddr) t.push('DDR ' + C.dateFR(o.ddr));
    if ((o.pathologies || []).length) t.push('pathologies antérieures : ' + o.pathologies.join(', '));
    if (o.procreateur) t.push('procréateur : ' + o.procreateur);
    return t.length ? t.join(' · ') : null;
  }
  function examenObstetricalLisible(o) {
    if (!o) return [];
    return (D.EXAMEN_OBSTETRICAL || []).filter(function (x) { return o[x.code] != null && o[x.code] !== ''; })
      .map(function (x) { return [x.label, String(o[x.code])]; });
  }
  function fichesDuDossier(d) {
    return S.collection('consultations').active().filter(function (c) { return c.dossierConsultationId === d.id; });
  }

  function recapDossier(d, opts) {
    opts = opts || {};
    var box = el('div.space-y-4');
    var etat = etatDossierCons(d.etat);
    box.appendChild(K.grid([
      ['Dossier', d.reference || d.id],
      ['Patient', (d.patient || '—') + ' — ' + (d.patientCode || d.nip || '')],
      ['Âge · sexe', (d.age != null ? d.age + ' ans' : '—') + ' · ' + (d.sexe === 'F' ? 'Féminin' : (d.sexe === 'M' ? 'Masculin' : '—'))],
      ['Couverture', d.assureur || 'Non assuré'],
      ['Venue', libelleTypeVenue(d.typeVenue) + ' — ' + C.dateFR(d.dateArrivee) + (d.heureArrivee ? ' ' + d.heureArrivee : '')],
      ['Motif', d.motifVenue || '—'],
      ['Praticien', d.soignant || '—'],
      ['État du dossier', U.badge(etat.label, etat.couleur)],
    ]));

    box.appendChild(K.section('Zone 1 — constantes de l’accueil',
      blocConstantes(constantesDuDossier(d) || (opts.releve ? { valeurs: copieReleve(opts.releve), source: 'accueil' } : null))));

    box.appendChild(K.section('Anamnèse', K.miniTable(['Rubrique', 'Contenu'], [
      ['Histoire de la maladie', d.histoire || '—'],
      ['Traitements en cours / habituels', d.traitementEnCours || '—'],
    ])));

    var ant = (D.CATEGORIES_ANTECEDENT || []).map(function (c) { return [c.label, d['ant_' + c.code] || '—']; });
    var obst = antecedentsObstetricauxLisibles(d.antecedentsObstetricaux);
    if (obst) ant.push(['Antécédents obstétricaux (structurés)', obst]);
    box.appendChild(K.section('Antécédents — trois catégories strictes', K.miniTable(['Catégorie', 'Contenu'], ant)));

    var prealables = [
      ['Allergies', d.allergies], ['Allergies médicamenteuses', d.allergiesMedicamenteuses],
      ['Statut vaccinal', d.statutVaccinal], ['Groupe sanguin', d.groupeSanguin],
      ['Électrophorèse de l’hémoglobine', d.electrophoreseHb], ['Dépistage', d.depistage],
      ['Enquête sociale', d.enqueteSociale],
    ].filter(function (x) { return x[1]; });
    if (prealables.length) box.appendChild(K.section('Données préalables', K.miniTable(['Rubrique', 'Contenu'], prealables)));
    if (d.allergiesMedicamenteuses) {
      box.appendChild(K.note('<strong>Allergie médicamenteuse déclarée : ' + d.allergiesMedicamenteuses + '.</strong> '
        + 'À vérifier avant toute prescription.', { tone: 'danger', icon: 'triangle-alert' }));
    }

    var synth = D.syntheseExamen ? D.syntheseExamen(D.examensPhysiquesDe(d)) : [];
    var lignesExamen = [['État général', libelleEtatGeneral(d.etatGeneral)
      + (d.etatGeneralPrecision ? ' — ' + d.etatGeneralPrecision : '')]]
      .concat(synth.map(function (s) { return [s.label, s.texte]; }));
    box.appendChild(K.section('Examen clinique (IPPOA)', synth.length || d.etatGeneral
      ? K.miniTable(['Appareil', 'Constatations'], lignesExamen)
      : U.empty('Aucun examen clinique consigné.', { icon: 'stethoscope' })));

    var obsEx = examenObstetricalLisible(d.examenObstetrical);
    if (obsEx.length) box.appendChild(K.section('Examen obstétrical', K.miniTable(['Élément', 'Constatation'], obsEx)));

    var chir = (D.RUBRIQUES_CHIRURGICALES || []).filter(function (r) { return d[r]; });
    if (chir.length) {
      var libChir = { actesChirurgicaux: 'Actes chirurgicaux', indicationOperatoire: 'Indication opératoire',
        blocPrevu: 'Programmation au bloc', risqueOperatoire: 'Risque opératoire' };
      box.appendChild(K.section('Actes chirurgicaux et bloc (chirurgien)',
        K.miniTable(['Rubrique', 'Contenu'], chir.map(function (r) { return [libChir[r] || r, d[r]]; }))));
    }

    /* Les rubriques de décision des dossiers d'ANCIENNE génération : elles
       vivaient au dossier avant que la fiche ne porte seule la décision. On
       les montre, on ne les recopie pas. */
    if (d.diagnostic || d.traitement || d.analysesDemandees) {
      box.appendChild(K.section('Décisions portées au dossier (saisie antérieure à la refonte)',
        K.miniTable(['Rubrique', 'Contenu'], [
          ['Diagnostic', d.diagnostic || '—'], ['Analyses demandées', d.analysesDemandees || '—'],
          ['Traitement', d.traitement || '—'], ['Conduite à tenir', d.conduite || '—'],
        ])));
    }

    if (!opts.sansFiches) {
      var fiches = fichesDuDossier(d);
      box.appendChild(K.section('Fiches de consultation établies sur ce dossier', fiches.length
        ? K.miniTable([
          { label: 'Date', render: function (c) { return C.dateFR(c.date); } },
          { label: 'Diagnostic retenu', render: function (c) { return c.diagnostic || '—'; } },
          { label: 'Orientation', render: function (c) { return c.orientationLabel || c.orientation || '—'; } },
          { label: 'Ordonnance', render: function (c) { return c.ordonnanceNumero || '—'; } },
        ], C.sortBy(fiches, 'date', 'desc'))
        : U.empty('Aucune fiche encore — la synthèse et la prescription se font à la fiche de consultation.', { icon: 'clipboard-list' })));
    }
    return box;
  }

  /* --------------------------------------------------------------------------
   * LE FORMULAIRE DU DOSSIER — anamnèse, antécédents, examen IPPOA
   * --------------------------------------------------------------------------
   * Pas un formulaire géant : des blocs DÉPLIABLES, un par appareil, comme la
   * METHODOLOGIE le demande — le médecin ne déploie que ce que le motif rend
   * pertinent. Les blocs réservés aux femmes (antécédents obstétricaux,
   * appareil gynéco-obstétrical, menstruation, examen obstétrical) se
   * masquent pour un homme : les lui présenter ferait saisir n'importe quoi.
   * ------------------------------------------------------------------------ */
  /* ==========================================================================
   * UN BLOC REPLIABLE EST UNE CARTE (22/09/2026)
   * --------------------------------------------------------------------------
   * Il portait ses propres bordures et ses propres marges : sur une page qui
   * mêle cartes du kit et blocs du dossier, cela faisait DEUX géométries — un
   * rayon d'angle, une épaisseur de trait et une gouttière intérieure
   * différents à trois pixels près. On ne le voit pas sur une capture, on le
   * voit en faisant défiler.
   *
   * Il emprunte donc `card` / `card-head` / `card-body`, comme tout le reste,
   * et garde son `<details>` — c'est le repli qui compte, pas le cadre.
   * ======================================================================== */
  function repliable(titre, icone, contenu, ouvert, extraEntete) {
    var det = el('details.card.group');
    if (ouvert) det.open = true;
    var sum = el('summary.card-head.cursor-pointer.list-none', null, [
      el('span.flex.min-w-0.items-center.gap-2', null, [
        C.icon(icone || 'chevron-right', 'h-4 w-4 shrink-0 text-navy-700'),
        el('span.card-title.truncate', { text: titre }),
      ]),
    ]);
    if (extraEntete) sum.appendChild(extraEntete);
    det.appendChild(sum);
    det.appendChild(el('div.card-body', null, contenu));
    return det;
  }

  function formulaireDossier(record) {
    var r = record || {};
    var estChirurgien = (function () {
      var s = S.session() || {};
      return s.fonction === 'chirurgien' || s.role === 'chirurgien';
    })();
    /* `space-y-4` comme toute pile de cartes du logiciel : à 3, l'écart entre
       deux blocs du dossier différait de celui des cartes voisines — ce qu'on
       ne voit pas sur une capture et qu'on voit en faisant défiler. */
    var corps = el('div.space-y-4');

    var fIdent = U.form([
      { type: 'section', label: 'Patient et venue' },
      { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, col: 'full',
        options: optionsPatients(), readonly: !!record,
        help: record ? 'Le patient d’un dossier enregistré ne se change pas — ouvrir un autre dossier.' : null },
      { name: 'soignant', label: 'Praticien', type: 'select', required: true, options: optionsPraticiensDossier() },
      { name: 'typeVenue', label: 'Type de venue', type: 'select', required: true, options: D.TYPES_VENUE || [] },
      { name: 'dateArrivee', label: 'Date de la venue', type: 'date', required: true },
      { name: 'heureArrivee', label: 'Heure d’arrivée', type: 'text', placeholder: '08h30' },
      { name: 'motifVenue', label: 'Motif de consultation', type: 'text', required: true, col: 'full' },
    ], Object.assign({ dateArrivee: C.iso(new Date()) }, r));

    var fAnam = U.form([
      { name: 'histoire', label: 'Histoire de la maladie', type: 'textarea', rows: 4, required: true, col: 'full',
        help: 'Le récit clinique : début, évolution, signes associés, ce qui a déjà été tenté.' },
      { name: 'traitementEnCours', label: 'Traitements en cours et habituels', type: 'textarea', rows: 2, col: 'full',
        help: 'Y compris l’automédication — c’est elle qu’on oublie.' },
    ], r);

    var champsAnt = [];
    (D.CATEGORIES_ANTECEDENT || []).forEach(function (cat) {
      champsAnt.push({ name: 'ant_' + cat.code, label: cat.label, type: 'textarea', rows: 2, col: 'full',
        help: cat.note });
    });
    var fAnt = U.form(champsAnt, r);

    var fPrealables = U.form([
      { name: 'allergies', label: 'Allergies', type: 'text' },
      { name: 'allergiesMedicamenteuses', label: 'Allergies médicamenteuses', type: 'text',
        help: 'Affichée en rouge au récapitulatif : elle conditionne la prescription.' },
      { name: 'statutVaccinal', label: 'Statut vaccinal', type: 'select',
        options: ['À jour', 'Incomplet', 'Non vacciné', 'Inconnu'] },
      { name: 'groupeSanguin', label: 'Groupe sanguin', type: 'select',
        options: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Inconnu'] },
      { name: 'electrophoreseHb', label: 'Électrophorèse de l’hémoglobine', type: 'select',
        options: ['AA', 'AS', 'AC', 'SS', 'SC', 'CC', 'Non faite'] },
      { name: 'depistage', label: 'Dépistage', type: 'text', help: 'VIH, hépatite B, syphilis… — résultat et date.' },
      { name: 'enqueteSociale', label: 'Enquête sociale', type: 'textarea', rows: 2, col: 'full' },
    ], r);

    var ao = r.antecedentsObstetricaux || {};
    var fObst = U.form([
      { name: 'gestite', label: 'Gestité', type: 'number', min: 0 },
      { name: 'parite', label: 'Parité', type: 'number', min: 0 },
      { name: 'enfantsVivants', label: 'Enfants vivants', type: 'number', min: 0 },
      { name: 'faussesCouches', label: 'Fausses couches', type: 'number', min: 0 },
      { name: 'enfantsDecedes', label: 'Enfants décédés', type: 'number', min: 0 },
      { name: 'ageDerniereGrossesse', label: 'Âge à la dernière grossesse', type: 'number', min: 10, max: 60 },
      { name: 'ddr', label: 'Date des dernières règles (DDR)', type: 'date' },
      { name: 'pathologiesObst', label: 'Pathologies antérieures', type: 'multiselect', col: 'full',
        options: (D.PATHOLOGIES_OBSTETRICALES_ANTERIEURES || []).map(function (x) { return { value: x, label: x }; }) },
      { name: 'procreateur', label: 'Antécédents du procréateur', type: 'textarea', rows: 2, col: 'full' },
    ], Object.assign({}, ao, { pathologiesObst: ao.pathologies || [] }));

    var fEG = U.form([
      { name: 'etatGeneral', label: 'État général', type: 'select', required: true, options: D.ETATS_GENERAUX || [] },
      { name: 'etatGeneralPrecision', label: 'Précision (en fonction de la maladie)', type: 'text',
        help: 'Exigée si l’état général n’est pas bon — « altéré » sans dire en quoi ne se relit pas.' },
    ], r);

    /* --- L'examen par appareil ------------------------------------------- */
    var examens = D.examensPhysiquesDe ? D.examensPhysiquesDe(r) : {};
    var champsExamen = {};   /* code appareil → { temps → textarea } */
    var blocsFemme = [];
    var blocsMenstruation = [];
    var hoteAppareils = el('div.space-y-2');
    (D.APPAREILS_EXAMEN || []).forEach(function (ap) {
      var valeurs = examens[ap.code] || {};
      var grille = el('div.grid.grid-cols-1.gap-3.sm\\:grid-cols-2');
      champsExamen[ap.code] = {};
      (D.tempsExamenDe ? D.tempsExamenDe(ap) : []).forEach(function (t) {
        var aide = (ap.aides && ap.aides[t.code]) || '';
        var ta = el('textarea.textarea', {
          rows: 2, id: 'ex_' + ap.code + '_' + t.code,
          placeholder: aide && aide !== '—' ? aide : '',
          dataset: { appareil: ap.code, temps: t.code },
        });
        ta.value = valeurs[t.code] || '';
        champsExamen[ap.code][t.code] = ta;
        var cellule = el('div', null, [el('label.label', { for: ta.id, text: t.ordre + '. ' + t.label }), ta]);
        if (t.code === 'menstruation') blocsMenstruation.push(cellule);
        grille.appendChild(cellule);
      });
      var normal = K.btn('Normal par défaut', {
        size: 'sm', icon: 'check-check',
        onclick: function (e) {
          if (e) { e.preventDefault(); e.stopPropagation(); }
          /* « RAS » dans les champs RESTÉS VIDES seulement : le médecin a
             peut-être déjà écrit l'anomalie qui l'a fait déplier ce bloc. La
             menstruation n'est pas un temps d'examen — on ne l'invente pas. */
          Object.keys(champsExamen[ap.code]).forEach(function (tc) {
            var champ = champsExamen[ap.code][tc];
            if (tc !== 'menstruation' && !String(champ.value || '').trim()) champ.value = D.MENTION_NORMALE || 'RAS';
          });
          det.open = true;
        },
      });
      normal.setAttribute('data-normal-defaut', ap.code);
      var dejaRempli = Object.keys(valeurs).some(function (k) { return valeurs[k]; });
      var det = repliable(ap.label, ap.icone, grille, dejaRempli, normal);
      det.setAttribute('data-appareil', ap.code);
      if (ap.femme) blocsFemme.push(det);
      hoteAppareils.appendChild(det);
    });

    var eo = r.examenObstetrical || {};
    var valeursObsEx = {};
    Object.keys(eo).forEach(function (k) { valeursObsEx['obs_' + k] = eo[k]; });
    var fObsEx = U.form((D.EXAMEN_OBSTETRICAL || []).map(function (x) {
      return { name: 'obs_' + x.code, label: x.label, type: x.type, rows: 2,
        options: x.options, col: x.type === 'textarea' ? 'full' : null };
    }), valeursObsEx);

    /* --- Les rubriques chirurgicales : présentes pour tous, ÉCRIVABLES par
       le seul chirurgien — on ne les masque pas au généraliste. ------------ */
    var libChir = { actesChirurgicaux: 'Actes chirurgicaux envisagés ou pratiqués',
      indicationOperatoire: 'Indication opératoire', blocPrevu: 'Programmation au bloc',
      risqueOperatoire: 'Risque opératoire évalué' };
    var fChir = U.form((D.RUBRIQUES_CHIRURGICALES || []).map(function (rub) {
      return { name: rub, label: libChir[rub] || rub, type: 'textarea', rows: 2, disabled: !estChirurgien,
        help: estChirurgien ? null : 'Renseigné par le chirurgien seulement. Vous le lisez — c’est votre patient aussi.' };
    }), r);

    var hoteConstantes = el('div');
    var blocObstAnt = repliable('Antécédents obstétricaux (femme)', 'baby', fObst, !!r.antecedentsObstetricaux);
    var blocObstEx = repliable('Examen obstétrical spécifique (femme)', 'baby', fObsEx, !!r.examenObstetrical);

    /* L'en-tête et les constantes prennent la carte comme les blocs suivants :
       un formulaire nu suivi de sept cartes donnait une page qui commence
       sans cadre puis en prend un — et c'est exactement ce que la Direction
       a nommé « cohérence de la grille ». */
    corps.appendChild(U.card('Patient et venue', fIdent));
    corps.appendChild(U.card('Zone 1 — constantes de l’accueil (lecture seule)', hoteConstantes));
    corps.appendChild(repliable('1. Anamnèse — motif, histoire, traitements', 'notebook-pen', fAnam, true));
    corps.appendChild(repliable('2. Antécédents — trois catégories strictes', 'history', fAnt, true));
    corps.appendChild(repliable('3. Données préalables — allergies, vaccins, groupe, dépistage', 'shield-plus', fPrealables, !!r.allergies || !!r.statutVaccinal));
    corps.appendChild(blocObstAnt);
    corps.appendChild(repliable('4. État général', 'activity', fEG, true));
    corps.appendChild(U.card('5. Examen physique par appareil — Inspection · Palpation · Percussion · Auscultation',
      el('div.space-y-3', null, [
        K.note('Dépliez les appareils pertinents pour le motif. <strong>Normal par défaut</strong> pose « RAS » dans les '
          + 'champs restés vides : vous n’écrivez que l’anormal.', { tone: 'info', icon: 'stethoscope' }),
        hoteAppareils,
      ])));
    corps.appendChild(blocObstEx);
    corps.appendChild(repliable('Actes chirurgicaux et bloc' + (estChirurgien ? '' : ' — lecture seule'), 'scissors', fChir,
      (D.RUBRIQUES_CHIRURGICALES || []).some(function (x) { return r[x]; })));

    function patientCourant() {
      var code = fIdent.controls.patientCode && fIdent.controls.patientCode.value;
      return code ? patientParCode(code) : null;
    }
    function adapterAuPatient() {
      var p = patientCourant();
      var femme = !p || p.sexe === 'F';
      [blocObstAnt, blocObstEx].concat(blocsFemme).concat(blocsMenstruation).forEach(function (n) {
        n.classList.toggle('hidden', !femme);
      });
      C.clear(hoteConstantes);
      var c = record ? constantesDuDossier(record) : null;
      if (!c && p) { var rl = dernierReleve(p.code, p.id); c = rl ? { valeurs: copieReleve(rl), source: 'accueil' } : null; }
      hoteConstantes.appendChild(blocConstantes(c));
      U.icons(hoteConstantes);
    }
    if (fIdent.controls.patientCode && fIdent.controls.patientCode.addEventListener) {
      fIdent.controls.patientCode.addEventListener('change', adapterAuPatient);
    }
    adapterAuPatient();

    function nombre(v) { return v === '' || v == null ? null : Number(v); }

    return {
      node: corps,
      collect: function () {
        var a = fIdent.collect(), b = fAnam.collect(), c = fAnt.collect(), d = fPrealables.collect(),
          e = fObst.collect(), g = fEG.collect(), h = fObsEx.collect(), k = fChir.collect();
        if (!a || !b || !c || !d || !e || !g || !h || !k) return { erreur: 'Le formulaire comporte des erreurs — champs obligatoires à compléter.' };
        if (g.etatGeneral && g.etatGeneral !== 'bon' && !String(g.etatGeneralPrecision || '').trim()) {
          return { erreur: 'État général « ' + libelleEtatGeneral(g.etatGeneral) + ' » : préciser en quoi.' };
        }
        var p = patientParCode(a.patientCode);
        var femme = p && p.sexe === 'F';
        var examensPhysiques = {};
        Object.keys(champsExamen).forEach(function (code) {
          var ap = (D.APPAREILS_EXAMEN || []).filter(function (x) { return x.code === code; })[0] || {};
          if (ap.femme && !femme) return;
          var bloc = {};
          Object.keys(champsExamen[code]).forEach(function (tc) {
            if (tc === 'menstruation' && !femme) return;
            var val = String(champsExamen[code][tc].value || '').trim();
            if (val) bloc[tc] = val;
          });
          /* Seuls les appareils EXAMINÉS entrent au JSON : un appareil vide
             n'est pas « normal », il n'a pas été examiné. */
          if (Object.keys(bloc).length) examensPhysiques[code] = bloc;
        });
        var antObst = null, examObst = null;
        if (femme) {
          antObst = {
            gestite: nombre(e.gestite), parite: nombre(e.parite), enfantsVivants: nombre(e.enfantsVivants),
            faussesCouches: nombre(e.faussesCouches), enfantsDecedes: nombre(e.enfantsDecedes),
            ageDerniereGrossesse: nombre(e.ageDerniereGrossesse), ddr: e.ddr || null,
            pathologies: e.pathologiesObst || [], procreateur: e.procreateur || '',
          };
          if (!Object.keys(antObst).some(function (x) {
            var v = antObst[x]; return Array.isArray(v) ? v.length : (v != null && v !== '');
          })) antObst = null;
          examObst = {};
          (D.EXAMEN_OBSTETRICAL || []).forEach(function (x) {
            var v = h['obs_' + x.code];
            if (v != null && v !== '') examObst[x.code] = v;
          });
          if (!Object.keys(examObst).length) examObst = null;
        }
        return {
          valeurs: Object.assign({}, a, b, c, d, g, k, {
            examensPhysiques: examensPhysiques,
            antecedentsObstetricaux: antObst,
            examenObstetrical: examObst,
          }),
        };
      },
    };
  }

  /**
   * enregistrerDossier(valeurs, record) — le MOTEUR de l'enregistrement,
   * séparé de la modale pour être SONDÉ (scénario 63), comme `emettreAvoir`.
   * Il refuse en le disant ; il ne devine rien.
   */
  function enregistrerDossier(v, record) {
    var p = patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable au répertoire : ' + v.patientCode + '.');
    if (record && record.etat === 'cloture') {
      throw new Error('Le dossier ' + (record.reference || record.id) + ' est CLÔTURÉ : il ne se réécrit pas. '
        + 'Ouvrir un nouveau dossier pour une nouvelle venue.');
    }
    if (!record) {
      /* UN dossier ouvert par patient : deux dossiers « en consultation » pour
         la même personne, et la fiche ne saurait pas lequel récapituler. */
      var ouvert = dossierActifDe(p.code);
      if (ouvert) {
        throw new Error('Un dossier est déjà ouvert pour ' + p.nom + ' ' + p.prenom + ' : '
          + (ouvert.reference || ouvert.id) + ' (' + etatDossierCons(ouvert.etat).label + '). Le compléter plutôt '
          + 'que d’en ouvrir un second, ou le clôturer d’abord.');
      }
    }
    /* Le contrôle d'écriture des rubriques chirurgicales est REFAIT au moteur :
       un champ désactivé dans le navigateur ne protège rien. */
    var s = S.session() || {};
    var capacite = s.fonction || s.role || '';
    (D.RUBRIQUES_CHIRURGICALES || []).forEach(function (rub) {
      var permis = D.peutEcrireRubrique ? D.peutEcrireRubrique(rub, capacite === 'chirurgien' || s.role === 'chirurgien' ? 'chirurgien' : capacite) : { ok: true };
      if (!permis.ok) v[rub] = record ? record[rub] : null;
    });

    var releve = dernierReleve(p.code, p.id);
    var maj = Object.assign({}, v, {
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code, nip: p.code,
      age: p.dateNaissance ? C.age(p.dateNaissance) : null, sexe: p.sexe,
      assureur: p.assureurNom || p.assureur || null,
      /* La copie des constantes de l'accueil : ce que le médecin avait sous les
         yeux en examinant. Posée une fois — une ré-édition ne la remplace pas. */
      constantesAccueil: (record && record.constantesAccueil) || copieReleve(releve),
      dossierSaisiLe: new Date().toISOString(),
    });
    var col = colDossiersCons();
    if (record) {
      /* C'est la SAISIE qui fait avancer un dossier inscrit en attente :
         attente → consultation, la seule transition que l'enregistrement pose. */
      if (record.etat === 'attente') maj.etat = 'consultation';
      var u = col.update(record.id, maj);
      return { dossier: col.get(record.id), undo: u.undo, cree: false };
    }
    /* Un dossier saisi d'un seul geste NAÎT « en consultation » : le patient
       a été reçu et examiné, l'étape « en attente » est derrière lui. */
    var ins = col.insert(Object.assign(maj, {
      reference: C.nextRef('DOS-', 5), etat: 'consultation', ouvertLe: new Date().toISOString(),
    }));
    return { dossier: ins.record, undo: ins.undo, cree: true };
  }

  /* LA SAISIE A QUITTÉ LA MODALE POUR SA PROPRE PAGE (21/09/2026).
     On détourne ICI, en un seul point, plutôt que de rebrancher chaque
     appelant : le registre l'appelle depuis son bouton « Nouveau dossier »
     ET depuis deux actions de ligne. Un appelant oublié aurait rouvert une
     modale que plus personne n'entretient — c'est ainsi que deux formulaires
     divergents finissent par coexister sur la même donnée. */
  function saisirDossier(record) {
    global.SIGH.app.go('m2-dossier-consultation-nouveau', record ? { id: record.id } : {});
  }

  /* ==========================================================================
   * LE DOSSIER DE CONSULTATION EN PAGE PLEINE (21/09/2026)
   * --------------------------------------------------------------------------
   * Le formulaire porte l'anamnèse, quatre catégories d'antécédents, les
   * données préalables, l'examen obstétrical et NEUF appareils en IPPOA. Dans
   * une modale, cela faisait une colonne de saisie qui défilait sans fin
   * au-dessus d'un écran qu'on ne pouvait plus consulter, et qu'un clic hors
   * du cadre refermait. Une consultation ne se saisit pas dans une fenêtre
   * qui flotte : elle dure, on y revient, on regarde autre chose entre-temps.
   *
   * LA MODALE EST SUPPRIMÉE, ET `saisirDossier()` DEVIENT LE RENVOI. Ses trois
   * appelants — le bouton « Nouveau dossier » du registre et deux actions de
   * ligne — la trouvent sans rien changer. Rebrancher chacun à la main aurait
   * garanti d'en oublier un ; garder la modale à côté de la page aurait
   * laissé deux formulaires sur la même donnée, qui divergent au premier
   * correctif. Un seul point de bascule, et aucun code mort.
   *
   * LA PAGE EST HORS RUBAN. Elle n'est pas une destination qu'on choisit dans
   * un menu : on y arrive depuis le registre, pour un dossier précis ou pour
   * en ouvrir un. Elle porte le module M2 et hérite donc de ses droits —
   * l'accueil n'y accède pas plus qu'au registre (RG-13).
   * ======================================================================== */
  var RETOUR_DOSSIER = 'm2-dossiers-consultation';

  global.SIGH.screen('m2-dossier-consultation-nouveau', {
    title: 'Dossier de consultation',
    description: 'Anamnèse, antécédents, données préalables et examen clinique IPPOA par appareil — la saisie complète du dossier.',
    regle: 'Le <strong>dossier</strong> s’enregistre AVANT la <strong>fiche de consultation</strong>, qui en fait le '
      + 'récapitulatif et qui SEULE prescrit. Les <strong>constantes de l’accueil</strong> sont reprises et affichées en '
      + 'lecture — jamais ressaisies. Un second dossier ouvert pour le même patient est refusé en nommant le premier.',
    render: function (root) {
      var p = C.params();
      var retour = p.retour || RETOUR_DOSSIER;
      var record = p.id ? colDossiersCons().get(p.id) : null;

      /* Une adresse qui vise une fiche disparue ne doit pas ouvrir un
         formulaire VIERGE : on créerait un second dossier en croyant
         corriger le premier. */
      if (p.id && !record) {
        root.appendChild(K.note('Ce dossier est introuvable — il a pu être archivé depuis que le lien a été ouvert. '
          + 'Revenez au registre pour le retrouver.', { tone: 'warning', icon: 'alert-triangle' }));
        root.appendChild(el('div.mt-3', null, K.btn('Revenir au registre', {
          variant: 'primary', icon: 'arrow-left', onclick: function () { global.SIGH.app.go(retour); } })));
        return;
      }

      if (!K.droits('M2').editer) {
        root.appendChild(K.note('Votre profil consulte les dossiers de consultation sans les modifier. '
          + 'La saisie appartient au praticien qui examine.', { tone: 'warning', icon: 'lock' }));
        root.appendChild(el('div.mt-3', null, K.btn('Revenir au registre', {
          icon: 'arrow-left', onclick: function () { global.SIGH.app.go(retour); } })));
        return;
      }

      if (record) {
        root.appendChild(K.note('Dossier <strong>' + (record.reference || '') + '</strong> — '
          + (record.patient || '') + ' · ' + (record.patientCode || '') + '.', { tone: 'info', icon: 'user' }));
      }

      /* LE GABARIT À DEUX PANNEAUX de la fiche de consultation : la saisie
         à gauche, l'enchaînement du parcours à droite. Le dossier est long —
         neuf appareils — et sans le rappel de ce qui suit, on oublie que la
         fiche reste à ouvrir et que c'est elle, et elle seule, qui prescrit. */
      var host = el('div.grid.gap-4.lg\\:grid-cols-3');
      var principal = el('div.space-y-4.lg\\:col-span-2');
      var aside = el('div.space-y-4');

      var formu = formulaireDossier(record);
      principal.appendChild(formu.node);

      aside.appendChild(U.card('Enchaînement du parcours', U.timeline([
        { title: 'Accueil — Zone 1', detail: 'Identité, couverture et constantes déjà saisies', date: 'Étape 1', tone: 'success' },
        { title: 'Dossier de consultation', detail: 'Anamnèse, antécédents, examen IPPOA — vous y êtes', date: 'Étape 2', tone: 'navy' },
        { title: 'Fiche de consultation', detail: 'Synthèse, diagnostic et conduite à tenir', date: 'Étape 3', tone: 'info' },
        { title: 'Prescription', detail: 'Médicaments, analyses, imagerie — sur la fiche, jamais ici', date: 'Étape 4', tone: 'info' },
        { title: 'Caisse', detail: 'Facture globale ; l’aval se débloque au règlement (M8)', date: 'Étape 5', tone: 'warning' },
      ])));
      aside.appendChild(U.card('Ce que le dossier engage', el('div.space-y-3', null, [
        K.note('Le dossier s’enregistre <strong>avant</strong> la fiche : celle-ci le refuse tant '
          + 'qu’il n’existe pas, et en fait ensuite le récapitulatif.', { tone: 'info', icon: 'clipboard-check' }),
        K.note('Les <strong>constantes de l’accueil</strong> sont reprises et affichées en lecture — '
          + 'jamais ressaisies : deux saisies de la même mesure finiraient par diverger.',
        { tone: 'neutral', icon: 'activity' }),
      ])));

      host.appendChild(principal);
      host.appendChild(aside);
      root.appendChild(host);

      function enregistrer() {
        var res = formu.collect();
        if (res.erreur) { U.toast(res.erreur, { type: 'error' }); return; }
        var out;
        try { out = enregistrerDossier(res.valeurs, record); } catch (e) {
          U.toast('Enregistrement refusé.', { type: 'error', detail: e.message, duration: 9000 }); return;
        }
        U.toastDiffere('Dossier ' + (out.dossier.reference || '') + ' enregistré — la fiche de consultation peut s’ouvrir.', {
          type: 'success', duration: 8000,
        });
        /* On repart vers le registre : rester sur un formulaire déjà
           enregistré invite à l'enregistrer une seconde fois. */
        global.SIGH.app.go(retour);
      }

      /* La barre du BAS autant que celle du haut : le formulaire est long, et
         remonter chercher le bouton après avoir rempli neuf appareils est
         exactement ce qui fait abandonner une saisie. */
      root.appendChild(el('div.mt-4.flex.flex-wrap.items-center.justify-end.gap-2.border-t.border-slate-200.pt-4', null, [
        K.btn('Annuler', { icon: 'x', onclick: function () { global.SIGH.app.go(retour); } }),
        K.btn('Enregistrer le dossier', { variant: 'primary', icon: 'save', onclick: enregistrer }),
      ]));

      root.__enregistrerDossier = enregistrer;
    },
    actions: function () {
      if (!K.droits('M2').editer) return null;
      return [
        K.btn('Enregistrer le dossier', { variant: 'primary', size: 'sm', icon: 'save', onclick: function () {
          var c = document.getElementById('page-content');
          if (c && c.__enregistrerDossier) c.__enregistrerDossier();
        } }),
      ];
    },
  });

  function changerEtatDossier(r, apres) {
    var courant = etatDossierCons(r.etat);
    var suivants = (courant.suivants || []).map(function (c) {
      var e = etatDossierCons(c);
      return { value: c, label: e.label, detail: e.note };
    });
    if (!suivants.length) { U.toast('Le dossier est clôturé : aucun état suivant.', { type: 'info' }); return; }
    var f = U.form([
      { name: 'etat', label: 'Nouvel état', type: 'select', required: true, options: suivants },
      { name: 'motifEtat', label: 'Précision', type: 'text' },
    ], {});
    var m = U.modal({
      title: 'État du dossier — ' + (r.reference || r.id), subtitle: 'Actuellement : ' + courant.label,
      body: el('div.space-y-3', null, [
        K.note('Les <strong>sauts d’état sont refusés</strong> : clôturer un dossier resté « en attente » signerait une '
          + 'consultation qui n’a pas eu lieu. Depuis « ' + courant.label + ' », les états accessibles sont : '
          + suivants.map(function (x) { return x.label; }).join(', ') + '.', { tone: 'info', icon: 'route' }),
        f,
      ]),
      footer: [
        K.btn('Annuler', { onclick: function () { m.close(); } }),
        K.btn('Appliquer', { variant: 'primary', icon: 'check', onclick: function () {
          var v = f.collect();
          if (!v) return;
          if (D.transitionPermise && !D.transitionPermise(r.etat, v.etat)) {
            U.toast('Transition refusée : « ' + courant.label + ' » ne mène pas à « ' + etatDossierCons(v.etat).label + ' ».', { type: 'error' });
            return;
          }
          colDossiersCons().update(r.id, { etat: v.etat, motifEtat: v.motifEtat,
            cloturLe: v.etat === 'cloture' ? new Date().toISOString() : null });
          m.close(); if (apres) apres();
          U.toast('Dossier ' + etatDossierCons(v.etat).label + '.', { type: 'success', detail: r.reference });
        } }),
      ],
    });
  }

  function imprimerDossier(d) {
    function rubrique(titre, texte) {
      return el('div.mb-2', null, [
        el('p.text-\\[10px\\].font-semibold', { text: titre + ' :' }),
        el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', { text: texte || '—' }),
      ]);
    }
    function titre(t) { return el('p.mb-2.mt-3.text-\\[10px\\].font-bold.uppercase', { text: t }); }
    var corps = el('div');
    corps.appendChild(titre('Anamnèse'));
    corps.appendChild(rubrique('Motif de consultation', d.motifVenue));
    corps.appendChild(rubrique('Histoire de la maladie', d.histoire));
    corps.appendChild(rubrique('Traitements en cours et habituels', d.traitementEnCours));
    corps.appendChild(titre('Antécédents'));
    (D.CATEGORIES_ANTECEDENT || []).forEach(function (c) { corps.appendChild(rubrique(c.label, d['ant_' + c.code])); });
    var obst = antecedentsObstetricauxLisibles(d.antecedentsObstetricaux);
    if (obst) corps.appendChild(rubrique('Antécédents obstétricaux', obst));
    if (d.allergies || d.allergiesMedicamenteuses) {
      corps.appendChild(rubrique('Allergies', [d.allergies, d.allergiesMedicamenteuses ? 'médicamenteuses : ' + d.allergiesMedicamenteuses : null].filter(Boolean).join(' — ')));
    }
    corps.appendChild(titre('Examen clinique'));
    corps.appendChild(rubrique('État général', libelleEtatGeneral(d.etatGeneral) + (d.etatGeneralPrecision ? ' — ' + d.etatGeneralPrecision : '')));
    (D.syntheseExamen ? D.syntheseExamen(D.examensPhysiquesDe(d)) : []).forEach(function (s) {
      corps.appendChild(rubrique(s.label, s.texte));
    });
    examenObstetricalLisible(d.examenObstetrical).forEach(function (x) { corps.appendChild(rubrique(x[0], x[1])); });
    var c = constantesDuDossier(d);
    var cv = c ? c.valeurs : {};
    P.etat({
      titre: 'DOSSIER DE CONSULTATION',
      sousTitre: (d.reference || d.id) + ' — ' + d.patient,
      cartouche: [
        ['Patient', d.patient], ['NIP', d.patientCode || d.nip],
        ['Âge', d.age != null ? d.age + ' ans' : '—'], ['Sexe', d.sexe || '—'],
        ['Venue', libelleTypeVenue(d.typeVenue) + ' du ' + C.dateFR(d.dateArrivee)],
        ['Couverture', d.assureur || 'Non assuré'],
        ['Constantes (accueil)', [cv.temperature != null ? 'T° ' + cv.temperature : null, cv.tension ? 'TA ' + cv.tension : null,
          cv.pouls != null ? 'Pouls ' + cv.pouls : null, cv.spo2 != null ? 'SpO₂ ' + cv.spo2 : null,
          cv.imc != null ? 'IMC ' + cv.imc : null].filter(Boolean).join('   ') || '—'],
        ['État du dossier', etatDossierCons(d.etat).label],
      ],
      contenu: corps,
      signatures: [{ role: 'Le praticien', nom: d.soignant || '', mention: 'Signature et cachet' }],
    });
  }

  /** La fiche de consultation, ouverte SUR ce dossier — l'identifiant voyage dans l'ancre. */
  function ouvrirFicheSur(d) {
    global.SIGH.app.go('m2-consultation-fiche', { onglet: d.id });
  }

  /* ==========================================================================
   * ÉCRAN — DOSSIERS DE CONSULTATION
   * ======================================================================== */
  global.SIGH.screen('m2-dossiers-consultation', {
    title: 'Dossiers de consultation',
    description: 'Anamnèse, antécédents et examen clinique structuré (IPPOA) par appareil — le dossier que la fiche de consultation récapitule.',
    regle: 'Le <strong>dossier</strong> s’enregistre AVANT la <strong>fiche de consultation</strong> : la fiche en fait le '
      + 'récapitulatif, et c’est elle SEULE qui prescrit (médicaments, analyses, imagerie) vers la caisse. Les constantes '
      + 'sont celles de l’<strong>accueil</strong>, lues et non ressaisies. Le cycle est ordonné — EN ATTENTE → EN '
      + 'CONSULTATION → EN ATTENTE LABO → CLÔTURÉ — et les sauts sont refusés. L’accueil n’y accède pas (RG-13).',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var rows = colDossiersCons().active();
        var auj = C.iso(new Date());
        var compte = function (etat) { return rows.filter(function (r) { return r.etat === etat; }).length; };
        var duJour = rows.filter(function (r) { return String(r.dateArrivee || '').slice(0, 10) === auj; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'En attente', value: C.num(compte('attente')), icon: 'clock', tone: 'neutral',
            hint: 'Inscrits, pas encore examinés' },
          { label: 'En consultation', value: C.num(compte('consultation')), icon: 'stethoscope', tone: 'info',
            hint: 'Dossier enregistré — la fiche peut s’ouvrir' },
          { label: 'En attente labo / imagerie', value: C.num(compte('attente_labo')), icon: 'flask-conical', tone: 'warning',
            hint: 'Examens prescrits, décision suspendue' },
          { label: 'Clôturés', value: C.num(compte('cloture')), icon: 'check-check', tone: 'success' },
          { label: 'Venues du jour', value: C.num(duJour.length), icon: 'calendar-days', tone: 'navy',
            hint: C.dateFR(auj) },
        ], 'grid-cols-2 lg:grid-cols-5'));

        vue.appendChild(K.note('<strong>Enchaînement</strong> — 1. l’accueil relève les constantes · 2. vous enregistrez '
          + 'le dossier (anamnèse, antécédents, examen IPPOA) · 3. « <strong>Ouvrir la fiche de consultation</strong> » : '
          + 'synthèse, diagnostic et SEULE étape de prescription · 4. la caisse encaisse une facture globale, puis '
          + 'pharmacie, laboratoire et imagerie exécutent.', { tone: 'info', icon: 'route' }));

        var nouveau = K.commande('Nouveau dossier', { variant: 'primary', size: 'sm', icon: 'plus',
          onclick: function () { saisirDossier(null); } });

        vue.appendChild(U.dataTable({
          title: 'Dossiers de consultation',
          rows: rows, exportName: 'dossiers-consultation', pageSize: 15,
          defaultSort: 'dateArrivee', defaultDir: 'desc',
          searchPlaceholder: 'Patient, NIP, motif, praticien…',
          emptyMessage: 'Aucun dossier de consultation.',
          actions: nouveau ? [nouveau] : null,
          filters: [
            { name: 'etat', label: 'État', options: (D.ETATS_DOSSIER || []).map(function (e) { return { value: e.code, label: e.label }; }) },
            { name: 'typeVenue', label: 'Type de venue', options: D.TYPES_VENUE || [] },
            { name: 'sexe', label: 'Sexe', options: [{ value: 'F', label: 'Féminin' }, { value: 'M', label: 'Masculin' }] },
            { name: 'jour', label: 'Période', options: [{ value: 'jour', label: 'Aujourd’hui' }, { value: 'semaine', label: '7 derniers jours' }],
              match: function (r, v) {
                var d = String(r.dateArrivee || '').slice(0, 10);
                if (v === 'jour') return d === auj;
                var s = new Date(); s.setDate(s.getDate() - 7);
                return d >= C.iso(s) && d <= auj;
              } },
          ],
          columns: [
            { key: 'reference', label: 'Dossier', nowrap: true,
              render: function (r) { return el('span.font-mono.text-xs', { text: r.reference || r.id }); } },
            { key: 'dateArrivee', label: 'Venue', nowrap: true,
              text: function (r) { return C.dateFR(r.dateArrivee); },
              render: function (r) { return C.dateFR(r.dateArrivee) + (r.heureArrivee ? ' ' + r.heureArrivee : ''); } },
            { key: 'patient', label: 'Patient',
              text: function (r) { return (r.patient || '') + ' ' + (r.patientCode || r.nip || ''); },
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient || '—' }),
                  el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode || r.nip || '' }),
                ]);
              } },
            { key: 'typeVenue', label: 'Venue', text: function (r) { return libelleTypeVenue(r.typeVenue); },
              render: function (r) { return r.typeVenue ? libelleTypeVenue(r.typeVenue) : '—'; } },
            { key: 'motifVenue', label: 'Motif' },
            { key: 'examen', label: 'Examen IPPOA', value: function (r) { return (D.syntheseExamen(D.examensPhysiquesDe(r)) || []).length; },
              render: function (r) {
                var n = (D.syntheseExamen(D.examensPhysiquesDe(r)) || []).length;
                return n ? U.badge(n + ' appareil(s)', 'info') : el('span.text-xs.text-slate-400', { text: 'non consigné' });
              } },
            { key: 'soignant', label: 'Praticien', render: function (r) { return r.soignant || '—'; } },
            { key: 'etat', label: 'État', text: function (r) { return etatDossierCons(r.etat).label; },
              render: function (r) { var e = etatDossierCons(r.etat); return U.badge(e.label, e.couleur); } },
          ],
          onRowClick: detail,
          rowActions: function (r) {
            return [
              dossierEnregistre(r) ? K.commandeIcone('clipboard-list', 'Ouvrir la fiche de consultation', function () { ouvrirFicheSur(r); }) : null,
              r.etat !== 'cloture' ? K.commandeIcone('stethoscope', r.etat === 'attente' ? 'Examiner — saisir le dossier' : 'Compléter le dossier',
                function () { saisirDossier(r); }) : null,
              r.etat !== 'cloture' ? K.commandeIcone('arrow-right', 'Changer l’état du dossier', function () { changerEtatDossier(r, afficher); }) : null,
              K.iconBtn('printer', 'Imprimer le dossier', function () { imprimerDossier(r); }),
            ].filter(Boolean);
          },
        }));
        U.icons(vue);
      }

      function detail(r) {
        var d = colDossiersCons().get(r.id) || r;
        U.drawer({
          title: d.patient + ' — ' + (d.patientCode || d.nip || ''),
          subtitle: (d.reference || d.id) + '   ·   ' + etatDossierCons(d.etat).label,
          width: 'max-w-3xl',
          body: recapDossier(d),
          footer: [
            dossierEnregistre(d) ? K.commande('Ouvrir la fiche de consultation', { variant: 'primary', icon: 'clipboard-list',
              onclick: function () { ouvrirFicheSur(d); } }) : null,
            K.btn('Imprimer', { icon: 'printer', onclick: function () { imprimerDossier(d); } }),
          ].filter(Boolean),
        });
      }
    },
  });

  /* ==========================================================================
   * LE MOTEUR DE LA FICHE DE CONSULTATION
   * --------------------------------------------------------------------------
   * enregistrerFiche(v) fait, d'UN seul appel, tout ce que la fiche engage :
   *   1. refuse sans dossier enregistré — en nommant l'écran où aller ;
   *   2. écrit la consultation, reliée à son dossier (`dossierConsultationId`) ;
   *   3. prescrit par PR.prescrire — médicaments, analyses ET imagerie dans
   *      UNE ordonnance et UNE facture globale, aval bloqué jusqu'à la caisse ;
   *   4. fait avancer le dossier : EN ATTENTE LABO si des examens (analyses ou
   *      imagerie) sont prescrits — la décision attend leurs résultats —,
   *      CLÔTURÉ sinon — la consultation est achevée, l'orientation suit son
   *      propre circuit (admission, observation, référence) ;
   *   5. pose la suite de l'orientation : rendez-vous de contrôle, notification
   *      du service d'hospitalisation ou d'observation, fiche de référence.
   * Si la prescription est refusée (examen sans tarif), la consultation est
   * DÉFAITE : rien n'est écrit à moitié.
   * ======================================================================== */
  var ORIENTATIONS = [
    { value: 'domicile', label: 'Domicile — traitement ambulatoire' },
    { value: 'hospitalisation', label: 'Hospitalisation' },
    { value: 'observation', label: 'Mise en observation' },
    { value: 'laboratoire', label: 'Laboratoire (en attente des résultats)' },
    { value: 'pharmacie', label: 'Pharmacie' },
    { value: 'reference', label: 'Référence vers un autre établissement' },
  ];
  function libelleOrientation(code) {
    var o = ORIENTATIONS.filter(function (x) { return x.value === code; })[0];
    return o ? o.label : (code || '—');
  }

  var MESSAGE_SANS_DOSSIER = 'Aucun dossier de consultation enregistré pour ce patient. La fiche fait le '
    + 'RÉCAPITULATIF du dossier : ouvrir d’abord « Soins › Consultations & prescriptions › Dossiers de '
    + 'consultation », y enregistrer l’anamnèse et l’examen clinique, puis revenir à la fiche.';

  function enregistrerFiche(v) {
    var p = patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable au répertoire : ' + v.patientCode + '.');
    var d = v.dossierConsultationId ? colDossiersCons().get(v.dossierConsultationId) : dossierActifDe(p.code);
    if (d && d.patientCode !== p.code) d = null;
    if (!d || !dossierEnregistre(d)) {
      var err = new Error(d && d.etat === 'cloture'
        ? 'Le dossier ' + (d.reference || d.id) + ' est clôturé. ' + MESSAGE_SANS_DOSSIER
        : (d && d.etat === 'attente'
          ? 'Le dossier ' + (d.reference || d.id) + ' est encore EN ATTENTE — l’examen n’y est pas consigné. ' + MESSAGE_SANS_DOSSIER
          : MESSAGE_SANS_DOSSIER));
      err.code = 'SANS_DOSSIER';
      throw err;
    }
    if (!(v.pathologies || []).length) throw new Error('Coder au moins une pathologie retenue (référentiel de morbidité).');
    if (!String(v.diagnostic || '').trim()) throw new Error('Rédiger le diagnostic retenu.');

    var listePath = pathologiesActives();
    function pathologie(code) { return listePath.filter(function (y) { return y.code === code; })[0]; }
    var c = constantesDuDossier(d);
    var cv = c ? c.valeurs : {};
    var typeCons = { urgence: 'Urgence', controle: 'Contrôle', suivi: 'Contrôle' }[d.typeVenue] || 'Consultation';
    var date = v.date ? new Date(v.date).toISOString() : new Date().toISOString();

    var consult = completerPatient({
      patientCode: p.code, medecin: v.medecin, date: date, type: typeCons, statut: 'terminee',
      motif: d.motifVenue || '', diagnostic: v.diagnostic,
      resumeSyndromique: v.resumeSyndromique || '', hypotheses: v.hypotheses || '',
      traitementEmblee: v.traitementEmblee || '', conduite: v.conduite || '',
      pathologies: v.pathologies, pathologiePrincipale: v.pathologies[0],
      pathologiesLibelles: v.pathologies.map(function (code) { var x = pathologie(code); return x ? x.libelle : code; }),
      notifiable: v.pathologies.some(function (code) { var x = pathologie(code); return x && x.notifiable; }),
      /* Les constantes de l'accueil, COPIÉES depuis le dossier : les écrans
         qui lisent `consultations` (dossier patient, statistiques) les
         trouvent là où ils les ont toujours lues — sans ressaisie. */
      temperature: cv.temperature != null ? cv.temperature : null, tension: cv.tension || null,
      poids: cv.poids != null ? cv.poids : null, fc: cv.pouls != null ? cv.pouls : null,
      orientation: v.orientation || null, orientationLabel: libelleOrientation(v.orientation),
      tarif: v.tarif != null ? v.tarif : 3000,
      dossierConsultationId: d.id, dossierReference: d.reference || null,
    });
    var ins = S.collection('consultations', { module: 'M2', entite: 'Consultation' }).insert(consult);

    var medicaments = (v.medicaments || []).filter(function (l) { return l.produitId && Number(l.quantite) > 0; });
    var analyses = v.analyses || [], imagerie = v.imagerie || [];
    var prescription = null;
    if (medicaments.length || analyses.length || imagerie.length) {
      try {
        prescription = PR.prescrire({
          patientCode: p.code, medecin: v.medecin, diagnostic: v.diagnostic, date: date,
          consultationId: ins.record.id, dossierConsultationId: d.id,
          indication: v.diagnostic, origine: 'consultation',
          medicaments: medicaments, analyses: analyses, imagerie: imagerie,
        });
      } catch (e) {
        ins.undo();
        throw new Error('Prescription refusée — rien n’a été enregistré : ' + e.message);
      }
      S.collection('consultations').update(ins.record.id, {
        ordonnanceId: prescription.ordonnance.id, ordonnanceNumero: prescription.ordonnance.numero,
        factureId: prescription.facture.id, factureNumero: prescription.facture.numero,
      });
    }

    /* Le dossier avance. */
    var cible = (analyses.length || imagerie.length) ? 'attente_labo' : 'cloture';
    var patch = {
      derniereFicheId: ins.record.id,
      fichesIds: (d.fichesIds || []).concat([ins.record.id]),
      ordonnanceIds: (d.ordonnanceIds || []).concat(prescription ? [prescription.ordonnance.id] : []),
      diagnosticRetenu: v.diagnostic, pathologiesRetenues: v.pathologies, orientation: v.orientation || null,
    };
    if (cible !== d.etat && (!D.transitionPermise || D.transitionPermise(d.etat, cible))) {
      patch.etat = cible;
      if (cible === 'cloture') patch.cloturLe = new Date().toISOString();
    }
    colDossiersCons().update(d.id, patch);

    /* La suite de l'orientation — on POSE ce qui revient à la consultation,
       on NOTIFIE ce qui revient à un autre service : l'admission et la mise
       en observation ont leurs propres écrans et leurs propres règles (un lit,
       une admission active), qu'on ne recopie pas ici. */
    var suites = [], rdv = null;
    if (v.orientation === 'domicile' && v.prochainRdv) {
      rdv = S.collection('consultations', { module: 'M2', entite: 'Consultation' }).insert({
        patientCode: p.code, patientId: p.id, patient: p.nom + ' ' + p.prenom,
        medecin: v.medecin, type: 'Contrôle', statut: 'planifiee',
        date: v.prochainRdv, motif: 'Contrôle — ' + v.diagnostic,
        reference: C.nextRef('C', 5), origine: 'fiche de consultation', dossierConsultationId: d.id,
      }).record;
      suites.push({ label: 'Rendez-vous de contrôle le ' + C.dateFR(v.prochainRdv), ecran: 'm2-rendezvous' });
    }
    if (v.orientation === 'hospitalisation' || v.orientation === 'observation') {
      var hospi = v.orientation === 'hospitalisation';
      PR.notifier({
        type: hospi ? 'orientation_hospitalisation' : 'orientation_observation',
        poste: hospi ? 'hospitalisation' : 'observation', priorite: 'haute',
        libelle: (hospi ? 'Admission demandée — ' : 'Mise en observation demandée — ') + p.nom + ' ' + p.prenom,
        detail: v.diagnostic + ' — prescrit par ' + v.medecin + ' (dossier ' + (d.reference || d.id) + ')',
        patientId: p.id, reference: d.reference || null,
        ordonnanceId: prescription ? prescription.ordonnance.id : null,
      });
      suites.push({ label: hospi ? 'Ouvrir l’admission' : 'Ouvrir la mise en observation', ecran: hospi ? 'm3-admissions' : 'm3-observation' });
    }
    if (v.orientation === 'reference') suites.push({ label: 'Établir la fiche de référence', ecran: 'm1-reference' });

    S.log('Fiche de consultation', 'M2', 'dossier de consultation', d.reference || d.id,
      { etat: d.etat }, { etat: patch.etat || d.etat, fiche: ins.record.id, prescription: prescription ? prescription.ordonnance.numero : null });

    return {
      consultation: S.collection('consultations').get(ins.record.id),
      prescription: prescription, dossier: colDossiersCons().get(d.id), suites: suites, rendezVous: rdv,
    };
  }

  /* Exposé pour être SONDÉ (scénario 63) — jamais recopié. */
  global.SIGH.consultationZone2 = {
    dossierActifDe: dossierActifDe, enregistrerDossier: enregistrerDossier,
    enregistrerFiche: enregistrerFiche, MESSAGE_SANS_DOSSIER: MESSAGE_SANS_DOSSIER,
  };

  /* --- L'éditeur des lignes de médicaments (produit, quantité, posologie, durée) --- */
  function editeurMedicaments(onChange) {
    var lignes = [];
    var hote = el('div.space-y-2');
    var node = el('div.space-y-2', { id: 'prescription-medicaments' }, [
      el('p.label', { text: 'Médicaments prescrits (pharmacie & stock)' }),
      hote,
      /* Une commande d'ÉCRITURE : absente pour qui lit la fiche sans pouvoir
         prescrire (aide-soignante, surveillant, échographiste) — l'audit RBAC
         l'a relevée comme promesse tant qu'elle était un simple bouton. */
      K.commande('Ajouter un médicament', { size: 'sm', icon: 'plus', onclick: function (e) { if (e) e.preventDefault(); ajouter(); } }),
      el('p.text-xs.text-slate-400', { text: 'Catalogue de la pharmacie, au prix d’achat sans marge (RG-02). Le stock affiché est indicatif : la délivrance le contrôle (RG-03).' }),
    ]);
    function ajouter() {
      var ligne = el('div.grid.grid-cols-1.gap-2.rounded-lg.border.border-slate-200.p-2.sm\\:grid-cols-12');
      var produit = U.combo(optionsProduits(), { placeholder: '— Médicament —' });
      var qte = el('input.input', { type: 'number', min: 1, value: 1, 'aria-label': 'Quantité' });
      var poso = el('input.input', { type: 'text', placeholder: 'Posologie (ex. 1 cp × 3/j)', 'aria-label': 'Posologie' });
      var duree = el('input.input', { type: 'text', placeholder: 'Durée', 'aria-label': 'Durée' });
      var ref = { produit: produit, qte: qte, poso: poso, duree: duree };
      var sup = K.iconBtn('trash-2', 'Retirer la ligne', function () {
        var i = lignes.indexOf(ref); if (i >= 0) lignes.splice(i, 1);
        if (produit.destroy) produit.destroy();
        ligne.remove(); if (onChange) onChange();
      });
      ligne.appendChild(el('div.sm\\:col-span-5', null, produit));
      ligne.appendChild(el('div.sm\\:col-span-1', null, qte));
      ligne.appendChild(el('div.sm\\:col-span-3', null, poso));
      ligne.appendChild(el('div.sm\\:col-span-2', null, duree));
      ligne.appendChild(el('div.sm\\:col-span-1.flex.items-center.justify-end', null, sup));
      lignes.push(ref);
      produit.addEventListener('change', function () { if (onChange) onChange(); });
      qte.addEventListener('input', function () { if (onChange) onChange(); });
      hote.appendChild(ligne);
      U.icons(ligne);
    }
    return {
      node: node, ajouter: ajouter,
      collect: function () {
        return lignes.map(function (l) {
          return { produitId: l.produit.value, quantite: Number(l.qte.value) || 0, posologie: l.poso.value, duree: l.duree.value };
        }).filter(function (l) { return l.produitId && l.quantite > 0; });
      },
      vider: function () {
        lignes.slice().forEach(function (l) { if (l.produit.destroy) l.produit.destroy(); });
        lignes.length = 0; C.clear(hote);
      },
    };
  }

  function optionsImagerie() {
    var cat = S.collection('examensImagerie').active();
    if (!cat.length) cat = (D.IMAGERIE && D.IMAGERIE.EXAMENS) || [];
    return cat.map(function (x) {
      var mod = D.IMAGERIE && D.IMAGERIE.modalite ? D.IMAGERIE.modalite(D.IMAGERIE.modaliteDeExamen(x)) : null;
      return { value: x.code, label: x.label, detail: mod ? mod.label : '' };
    });
  }

  /* ==========================================================================
   * ÉCRAN — FICHE DE CONSULTATION (synthèse, décision, prescription)
   * ======================================================================== */
  global.SIGH.screen('m2-consultation-fiche', {
    title: 'Fiche de consultation',
    description: 'Synthèse du dossier de consultation : diagnostic, conduite à tenir, et SEULE étape de prescription — médicaments, analyses, imagerie médicale.',
    regle: 'La fiche <strong>récapitule un dossier de consultation enregistré</strong> et refuse sans lui. C’est '
      + '<strong>uniquement</strong> ici que se prescrivent médicaments, analyses et imagerie : une ordonnance, '
      + '<strong>une facture globale</strong> à la caisse (part assureur / part patient), et l’exécution — '
      + 'dispensation, prélèvement, imagerie — <strong>bloquée jusqu’au règlement</strong>.',
    render: function (root) {
      var host = el('div.grid.gap-4.lg\\:grid-cols-3');
      var derniereOrdonnance = null;
      var dossierCourant = null;
      var hoteRecap = el('div.space-y-3');
      var total = el('p.text-sm.font-semibold.text-slate-800');

      /* Ancre de la page : l'identifiant du dossier depuis lequel on arrive. */
      var ancre = /[#&]onglet=([^&]+)/.exec(global.location.hash || '');
      var dossierVise = ancre ? colDossiersCons().get(decodeURIComponent(ancre[1])) : null;

      var fEntete = U.form([
        { type: 'section', label: 'Patient et dossier de consultation' },
        { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, options: optionsPatients(), col: 'full',
          value: dossierVise ? dossierVise.patientCode : null },
        { name: 'medecin', label: 'Praticien', type: 'select', required: true, options: optionsPraticiensDossier(),
          value: dossierVise ? dossierVise.soignant : null },
        { name: 'date', label: 'Date et heure', type: 'datetime-local', required: true, value: new Date().toISOString().slice(0, 16) },
      ], {});

      var fSynthese = U.form([
        { type: 'section', label: 'Synthèse et diagnostic' },
        { name: 'resumeSyndromique', label: 'Résumé syndromique', type: 'textarea', rows: 2, col: 'full' },
        { name: 'hypotheses', label: 'Hypothèses diagnostiques', type: 'textarea', rows: 2, col: 'full' },
        /* Deux champs, et non un seul. La PATHOLOGIE est un code que la
           clinique compte ; le DIAGNOSTIC est la phrase que le médecin écrit. */
        { name: 'pathologies', label: 'Pathologie(s) retenue(s)', type: 'multiselect', required: true, col: 'full',
          options: optionsPathologies(),
          help: 'Référentiel de morbidité de la clinique. La première citée est retenue comme principale.' },
        { name: 'diagnostic', label: 'Diagnostic retenu', type: 'textarea', rows: 2, required: true, col: 'full',
          help: 'La phrase clinique — la pathologie ci-dessus sert au comptage.' },
        { name: 'traitementEmblee', label: 'Traitement d’emblée', type: 'textarea', rows: 2, col: 'full',
          help: 'Si nécessaire avant les résultats.' },
        { name: 'conduite', label: 'Conduite à tenir', type: 'textarea', rows: 2, col: 'full' },
      ], {});

      var editeur = editeurMedicaments(recalculer);
      var fExamens = U.form([
        { name: 'analyses', label: 'Analyses de laboratoire prescrites', type: 'multiselect', col: 'full', options: optionsAnalyses(),
          help: 'Chaque analyse engendre sa demande au laboratoire, bloquée jusqu’au règlement.' },
        { name: 'imagerie', label: 'Imagerie médicale prescrite', type: 'multiselect', col: 'full', options: optionsImagerie(),
          help: 'Échographie, radiographie, mammographie, scanner, IRM — la demande part au poste d’imagerie, exécutable après la caisse.' },
      ], {});
      var fOrientation = U.form([
        { type: 'section', label: 'Orientation et décision médicale' },
        { name: 'orientation', label: 'Orientation', type: 'select', required: true, options: ORIENTATIONS },
        { name: 'prochainRdv', label: 'Prochain rendez-vous (retour à domicile)', type: 'datetime-local',
          help: 'Posé à l’agenda comme un contrôle planifié.' },
        { name: 'tarif', label: 'Tarif de la consultation (FCFA)', type: 'money', value: 3000 },
      ], {});
      fExamens.addEventListener('change', recalculer);

      function patientCourant() {
        var code = fEntete.controls.patientCode && fEntete.controls.patientCode.value;
        return code ? patientParCode(code) : null;
      }

      function rafraichirDossier() {
        var p = patientCourant();
        C.clear(hoteRecap);
        dossierCourant = null;
        if (!p) return;
        var d = (dossierVise && dossierVise.patientCode === p.code && dossierEnregistre(dossierVise)) ? dossierVise : dossierActifDe(p.code);
        if (d) d = colDossiersCons().get(d.id);
        var releve = dernierReleve(p.code, p.id);
        if (!d) {
          /* LE REFUS SE DIT, ET IL NOMME OÙ ALLER. Les constantes de l'accueil
             restent affichées : elles existent indépendamment du dossier. */
          hoteRecap.appendChild(K.note('<strong>Fiche impossible sans dossier.</strong> ' + MESSAGE_SANS_DOSSIER,
            { tone: 'danger', icon: 'folder-x' }));
          hoteRecap.appendChild(el('div', null, K.btn('Ouvrir les dossiers de consultation', {
            variant: 'primary', icon: 'folder-heart',
            onclick: function () { global.SIGH.app.go('m2-dossiers-consultation'); },
          })));
          hoteRecap.appendChild(K.section('Zone 1 — constantes de l’accueil',
            blocConstantes(releve ? { valeurs: copieReleve(releve), source: 'accueil' } : null)));
        } else {
          dossierCourant = d;
          hoteRecap.appendChild(K.note('Récapitulatif du dossier <strong>' + (d.reference || d.id) + '</strong> — '
            + etatDossierCons(d.etat).label + '. Pour corriger l’anamnèse ou l’examen, revenir au dossier : la fiche le lit, '
            + 'elle ne le réécrit pas.', { tone: 'success', icon: 'folder-check' }));
          hoteRecap.appendChild(recapDossier(d, { releve: releve }));
        }
        U.icons(hoteRecap);
        recalculer();
      }

      function recalculer() {
        var p = patientCourant();
        var assure = p && PR.carteValide ? PR.carteValide(p, new Date().toISOString()) : false;
        var mMed = C.sum(editeur.collect(), function (l) {
          var pr = S.collection('produits').get(l.produitId);
          return (pr ? pr.prixAchat : 0) * l.quantite;
        });
        var ctrl = fExamens.controls;
        var mAna = C.sum(ctrl.analyses.value || [], function (code) {
          var a = D.ANALYSES.filter(function (x) { return x.code === code; })[0];
          return a ? a.prix : 0;
        });
        var sansTarif = [];
        var mImg = C.sum(ctrl.imagerie.value || [], function (code) {
          var ex = PR.examenImagerieParCode ? PR.examenImagerieParCode(code) : null;
          var pr = D.tarifPrix ? D.tarifPrix((ex && ex.tarifCode) || code, assure) : { montant: null };
          if (pr.montant == null) sansTarif.push(ex ? ex.label : code);
          return pr.montant || 0;
        });
        total.textContent = C.money(mMed + mAna + mImg) + '  (médicaments ' + C.money(mMed, false)
          + ' · analyses ' + C.money(mAna, false) + ' · imagerie ' + C.money(mImg, false) + ')'
          + (sansTarif.length ? ' — sans tarif : ' + sansTarif.join(', ') : '');
      }

      if (fEntete.controls.patientCode && fEntete.controls.patientCode.addEventListener) {
        fEntete.controls.patientCode.addEventListener('change', rafraichirDossier);
      }

      var actions = el('div.mt-4.flex.flex-wrap.gap-2');
      /* ENREGISTRER ET PRESCRIRE : l'écriture médicale par excellence — une
         commande déclarée comme telle, absente sans le droit d'écrire M2
         (aide-soignante, surveillant, technicien d'échographie). */
      C.append(actions, K.commande('Enregistrer et prescrire', {
        variant: 'primary', icon: 'save',
        onclick: function () {
          var a = fEntete.collect(), b = fSynthese.collect(), o = fOrientation.collect(), x = fExamens.collect();
          if (!a || !b || !o || !x) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
          var res;
          try {
            res = enregistrerFiche(Object.assign({}, a, b, o, x, {
              dossierConsultationId: dossierCourant ? dossierCourant.id : null,
              medicaments: editeur.collect(),
            }));
          } catch (e) {
            U.toast(e.code === 'SANS_DOSSIER' ? 'Fiche refusée : aucun dossier de consultation.' : 'Enregistrement refusé.',
              { type: 'error', detail: e.message, duration: 10000 });
            return;
          }
          var ord = res.prescription;
          derniereOrdonnance = ord ? ord.ordonnance.id : null;
          dossierVise = null;
          rafraichirDossier();
          var envois = [];
          if (ord) {
            if (ord.demandes.length) envois.push(ord.demandes.length + ' analyse(s) au laboratoire');
            if ((ord.demandesImagerie || []).length) envois.push(ord.demandesImagerie.length + ' examen(s) à l’imagerie');
            if ((ord.ordonnance.medicaments || []).length) envois.push('pharmacie informée');
            envois.push('facture ' + ord.facture.numero + ' en attente à la caisse');
          }
          U.toast('Fiche de consultation enregistrée — dossier ' + etatDossierCons(res.dossier.etat).label + '.', {
            type: 'success', duration: 9000, detail: envois.join(' · ') || 'Aucune prescription.',
          });

          var m = U.modal({
            title: 'Consultation enregistrée',
            subtitle: ord ? 'Ordonnance ' + ord.ordonnance.numero + ' — facture ' + ord.facture.numero : res.consultation.patient,
            size: 'md',
            body: el('div.space-y-3', null, [
              ord ? K.note('Une <strong>facture globale</strong> attend à la <strong>caisse</strong>. La dispensation, le '
                + 'prélèvement et l’imagerie restent <strong>bloqués jusqu’au règlement</strong>.', { tone: 'info', icon: 'coins' })
                : K.note('Aucune prescription : rien ne part à la caisse.', { tone: 'neutral', icon: 'info' }),
              ord ? U.descList([
                ['Médicaments', C.num((ord.ordonnance.medicaments || []).length)],
                ['Analyses', C.num(ord.demandes.length)],
                ['Imagerie médicale', C.num((ord.demandesImagerie || []).length)],
                ['À régler à la caisse', C.money(ord.facture.partPatient != null ? ord.facture.partPatient : ord.facture.montantTTC)],
                ['Part assureur', C.money(ord.facture.partAssurance || 0)],
                ['Dossier', res.dossier.reference + ' — ' + etatDossierCons(res.dossier.etat).label],
              ], 'grid-cols-2') : null,
              res.suites.length ? K.note('Orientation : <strong>' + libelleOrientation(res.consultation.orientation) + '</strong>.', { tone: 'warning', icon: 'route' }) : null,
            ].filter(Boolean)),
            footer: [
              K.btn('Fermer', { onclick: function () { m.close(); } }),
              ord && (ord.ordonnance.medicaments || []).length ? K.btn('Ordonnance', { icon: 'file-text',
                onclick: function () { etatOrdonnanceMedicale(S.collection('ordonnances').get(ord.ordonnance.id)); } }) : null,
              ord && ord.demandes.length ? K.btn('Bulletin d’analyses', { icon: 'flask-conical',
                onclick: function () { etatBulletinAnalyses(S.collection('ordonnances').get(ord.ordonnance.id)); } }) : null,
            ].concat(res.suites.filter(function (s) { return s.ecran; }).map(function (s) {
              return K.btn(s.label, { variant: 'primary', icon: 'arrow-right', onclick: function () { global.SIGH.app.go(s.ecran); } });
            })).filter(Boolean),
          });
        },
      }));
      function exigerOrdonnance(quoi) {
        var ord = derniereOrdonnance ? S.collection('ordonnances').get(derniereOrdonnance) : null;
        if (ord) return ord;
        U.toast('Aucune ordonnance à imprimer.', { type: 'error',
          detail: 'Cliquer d’abord sur « Enregistrer et prescrire » : ' + quoi + ' reprend ce qui a réellement été transmis, et non le contenu du formulaire.' });
        return null;
      }
      actions.appendChild(K.btn('Éditer l’ordonnance', { icon: 'file-text',
        onclick: function () { var o = exigerOrdonnance('l’ordonnance'); if (o) etatOrdonnanceMedicale(o); } }));
      actions.appendChild(K.btn('Éditer le bulletin d’analyses', { icon: 'flask-conical',
        onclick: function () { var o = exigerOrdonnance('le bulletin'); if (o) etatBulletinAnalyses(o); } }));

      var principal = el('div.space-y-4.lg\\:col-span-2');
      principal.appendChild(U.card('Dossier de consultation — récapitulatif', el('div.space-y-4', null, [fEntete, hoteRecap])));
      principal.appendChild(U.card('Synthèse, diagnostic et conduite à tenir', fSynthese));
      principal.appendChild(U.card('Prescription — la seule étape où l’on prescrit', el('div.space-y-4', null, [
        editeur.node, fExamens,
        el('div.rounded-lg.border.border-slate-200.bg-slate-50.px-3.py-2', null, [
          el('p.text-xs.text-slate-500', { text: 'Total de la prescription (avant répartition assureur / patient)' }), total,
        ]),
      ])));
      principal.appendChild(U.card('Orientation', el('div', null, [fOrientation, actions])));
      host.appendChild(principal);

      var aside = el('div.space-y-4');
      aside.appendChild(U.card('Enchaînement du parcours', U.timeline([
        { title: 'Accueil — Zone 1', detail: 'Identité, couverture, constantes saisies et verrouillées', date: 'Étape 1', tone: 'success' },
        { title: 'Dossier de consultation', detail: 'Anamnèse, antécédents, examen IPPOA — enregistré d’abord', date: 'Étape 2', tone: 'success' },
        { title: 'Fiche de consultation', detail: 'Synthèse, diagnostic, conduite à tenir', date: 'Étape 3', tone: 'navy' },
        { title: 'Prescription', detail: 'Médicaments (M6), analyses (M5), imagerie (M2) — ici seulement', date: 'Étape 4', tone: 'info' },
        { title: 'Caisse', detail: 'Facture globale, part assureur / patient ; l’aval se débloque au règlement (M8)', date: 'Étape 5', tone: 'warning' },
      ])));
      aside.appendChild(U.card('Rappels de facturation', el('div.space-y-3', null, [
        K.note('<strong>RG-02</strong> — Les médicaments sont facturés au <strong>prix d’achat, sans marge</strong>.', { tone: 'info' }),
        K.note('<strong>RG-09</strong> — La prise en charge n’est appliquée que si la carte est valide à la date de facturation.', { tone: 'warning', icon: 'shield-alert' }),
      ])));
      host.appendChild(aside);
      root.appendChild(host);

      /* La première ligne vide n'est offerte qu'à qui peut prescrire : sa
         corbeille serait sinon une commande d'écriture sans droit. */
      if (K.droits().editer) editeur.ajouter();
      rafraichirDossier();
      return null;
    },
  });

  /* ==========================================================================
   * ORDONNANCES
   * ======================================================================== */
  /* ==========================================================================
   * PATHOLOGIES & MORBIDITÉ
   * --------------------------------------------------------------------------
   * Le référentiel que la consultation consomme, et le tableau qu'il permet.
   * C'est cette seconde partie qui justifie la première : sans code, on ne
   * compte rien, et la clinique ne sait pas ce qu'elle traite.
   *
   * Le classement suit les grands chapitres de la CIM-10 SANS en reprendre la
   * codification : la clinique ne code pas en CIM, et lui imposer une
   * nomenclature qu'elle n'emploie pas ferait saisir n'importe quoi.
   * ======================================================================== */
  global.SIGH.screen('m2-pathologies', {
    title: 'Pathologies & morbidité',
    description: 'Référentiel des pathologies de la clinique et tableau de morbidité issu des consultations.',
    regle: 'La <strong>pathologie</strong> est un code que la clinique compte ; le <strong>diagnostic</strong> est '
      + 'la phrase que le médecin rédige. Les deux coexistent sur la consultation — n’avoir que le second '
      + 'rendrait toute statistique impossible. La liste est <strong>administrable</strong> : c’est le tableau '
      + 'de morbidité qui doit la faire évoluer, pas une mise à jour du logiciel. '
      + 'Les libellés proposés restent <strong>à arrêter par le Directeur Médical</strong>.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col() {
        return S.collection('pathologies', { module: 'M2', entite: 'pathologie', prefix: 'PATH' });
      }

      function consultations() {
        return S.collection('consultations').active();
      }

      /** Le nombre de cas par code, sur l'ensemble des consultations. */
      function comptage() {
        var out = {};
        consultations().forEach(function (c) {
          (c.pathologies || []).forEach(function (code) {
            out[code] = (out[code] || 0) + 1;
          });
        });
        return out;
      }

      function afficher() {
        var rows = col().active();
        var cas = comptage();
        var totalCas = Object.keys(cas).reduce(function (n, k) { return n + cas[k]; }, 0);
        var notifiables = rows.filter(function (x) { return x.notifiable; });
        var casNotifiables = notifiables.reduce(function (n, x) { return n + (cas[x.code] || 0); }, 0);

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Pathologies au référentiel', value: C.num(rows.length), icon: 'list', tone: 'navy' },
          { label: 'Chapitres couverts', value: C.num(D.CHAPITRES_PATHOLOGIE.length), icon: 'layers', tone: 'info' },
          { label: 'Cas enregistrés', value: C.num(totalCas), icon: 'activity', tone: 'success',
            hint: 'sur ' + C.num(consultations().length) + ' consultations' },
          {
            label: 'Cas à déclaration obligatoire', value: C.num(casNotifiables),
            icon: 'siren', tone: casNotifiables ? 'danger' : 'neutral',
            hint: C.num(notifiables.length) + ' pathologies notifiables',
          },
        ]));

        vue.appendChild(K.note('Une pathologie <strong>notifiable</strong> relève de la déclaration obligatoire aux '
          + 'autorités sanitaires. Le signaler permet de repérer les cas à déclarer sans relire tout le registre — '
          + 'la clinique reste responsable de la déclaration elle-même, que le logiciel ne transmet pas.',
        { tone: 'warning', icon: 'siren' }));

        vue.appendChild(U.tabs([
          { id: 'morbidite', label: 'Tableau de morbidité', badge: Object.keys(cas).length, render: ongletMorbidite },
          { id: 'referentiel', label: 'Référentiel', badge: rows.length, render: ongletReferentiel },
        ]));
        U.icons(vue);
      }

      function ongletMorbidite() {
        var cas = comptage();
        var rows = col().active().map(function (x) {
          var ch = D.CHAPITRES_PATHOLOGIE.filter(function (y) { return y.id === x.chapitre; })[0];
          return Object.assign({}, x, {
            cas: cas[x.code] || 0,
            chapitreLabel: ch ? ch.label : x.chapitre,
          });
        }).filter(function (x) { return x.cas > 0; })
          .sort(function (a, b) { return b.cas - a.cas; });

        if (!rows.length) {
          return U.card('Tableau de morbidité',
            U.empty('Aucun cas rattaché à une pathologie.', {
              icon: 'activity',
              hint: 'Les consultations enregistrées avant la mise en place du référentiel ne portent qu’un '
                + 'diagnostic rédigé : elles ne peuvent pas être comptées rétrospectivement.',
            }));
        }

        var parChapitre = C.groupBy(rows, 'chapitreLabel');
        var bloc = el('div.space-y-4');

        bloc.appendChild(el('div.grid.gap-4.lg\:grid-cols-2', null, [
          U.card('Les pathologies les plus fréquentes',
            K.ranking(rows.slice(0, 12).map(function (x) {
              return { label: x.libelle, value: x.cas, tone: x.notifiable ? 'danger' : 'navy' };
            }), { format: function (v) { return C.num(v) + ' cas'; } })),
          U.card('Répartition par chapitre',
            G.camembert(Object.keys(parChapitre),
              Object.keys(parChapitre).map(function (k) {
                return parChapitre[k].reduce(function (n, x) { return n + x.cas; }, 0);
              }), { height: 300, legend: 'bottom' })),
        ]));

        bloc.appendChild(U.dataTable({
          title: 'Tableau de morbidité', rows: rows, exportName: 'morbidite',
          pageSize: 20, searchable: true, defaultSort: 'cas', defaultDir: 'desc',
          columns: [
            { key: 'code', label: 'Code', nowrap: true, render: function (x) { return el('span.font-mono.text-xs', { text: x.code }); } },
            { key: 'libelle', label: 'Pathologie', render: function (x) { return el('span.font-medium.text-slate-800', { text: x.libelle }); } },
            { key: 'chapitreLabel', label: 'Chapitre' },
            {
              key: 'notifiable', label: 'Déclaration', align: 'right',
              text: function (x) { return x.notifiable ? 'obligatoire' : ''; },
              render: function (x) { return x.notifiable ? U.badge('Obligatoire', 'danger') : el('span.text-xs.text-slate-300', { text: '—' }); },
            },
            { key: 'cas', label: 'Cas', align: 'right', render: function (x) { return el('span.font-semibold', { text: C.num(x.cas) }); } },
          ],
          actions: [K.btn('Imprimer le tableau', { size: 'sm', icon: 'printer', onclick: function () { imprimer(rows); } })],
        }));
        return bloc;
      }

      function ongletReferentiel() {
        var cas = comptage();
        var rows = col().active().map(function (x) {
          var ch = D.CHAPITRES_PATHOLOGIE.filter(function (y) { return y.id === x.chapitre; })[0];
          return Object.assign({}, x, { cas: cas[x.code] || 0, chapitreLabel: ch ? ch.label : x.chapitre });
        });

        return U.dataTable({
          title: 'Référentiel des pathologies', rows: rows, exportName: 'pathologies',
          pageSize: 25, searchable: true, defaultSort: 'chapitreLabel',
          filters: [
            {
              name: 'chapitre', label: 'Chapitre',
              options: D.CHAPITRES_PATHOLOGIE.map(function (x) { return { value: x.id, label: x.label }; }),
            },
            {
              name: 'notifiable', label: 'Déclaration obligatoire',
              options: [{ value: 'oui', label: 'Notifiable' }, { value: 'non', label: 'Non notifiable' }],
              match: function (r, v) { return v === 'oui' ? !!r.notifiable : !r.notifiable; },
            },
          ],
          columns: [
            { key: 'code', label: 'Code', nowrap: true, render: function (x) { return el('span.font-mono.text-xs', { text: x.code }); } },
            { key: 'libelle', label: 'Pathologie' },
            { key: 'chapitreLabel', label: 'Chapitre', render: function (x) { return U.badge(x.chapitreLabel, 'navy'); } },
            {
              key: 'notifiable', label: 'Déclaration',
              text: function (x) { return x.notifiable ? 'obligatoire' : ''; },
              render: function (x) { return x.notifiable ? U.badge('Obligatoire', 'danger') : el('span.text-xs.text-slate-300', { text: '—' }); },
            },
            { key: 'cas', label: 'Cas enregistrés', align: 'right' },
            {
              key: 'aValider', label: 'Provenance', align: 'right',
              text: function (x) { return x.aValider ? 'à valider' : 'arrêtée'; },
              render: function (x) {
                return x.aValider ? U.badge('À valider', 'warning') : U.badge('Arrêtée', 'success');
              },
            },
          ],
          actions: [K.creer(col(), champs(), {
            module: 'M2', label: 'Nouvelle pathologie', titre: 'Nouvelle pathologie', entite: 'Pathologie',
            defauts: function () { return { chapitre: 'autres', notifiable: false }; },
            transform: function (v) {
              v.notifiable = !!v.notifiable;
              v.aValider = true;
              v.source = 'Ajoutée dans l’application le ' + C.dateFR(AUJ) + ' — à arrêter par le Directeur Médical';
              return v;
            },
            apres: afficher,
          })].filter(Boolean),
          rowActions: K.actionsLigne(col(), champs(), { module: 'M2', refresh: afficher }),
        });
      }

      function champs() {
        return [
          { name: 'code', label: 'Code', type: 'text', required: true, hint: 'Court, stable — il sert au comptage.' },
          { name: 'libelle', label: 'Intitulé de la pathologie', type: 'text', required: true, col: 'full' },
          {
            name: 'chapitre', label: 'Chapitre', type: 'select', required: true,
            options: D.CHAPITRES_PATHOLOGIE.map(function (x) { return { value: x.id, label: x.label }; }),
          },
          {
            name: 'notifiable', label: 'Déclaration obligatoire', type: 'checkbox',
            hint: 'Pathologie à déclarer aux autorités sanitaires. Le logiciel la signale ; il ne la transmet pas.',
          },
        ];
      }

      function imprimer(rows) {
        var total = rows.reduce(function (n, x) { return n + x.cas; }, 0);
        P.etat({
          titre: 'Tableau de morbidité',
          sousTitre: 'Consultations enregistrées — situation au ' + C.dateFR(AUJ),
          cartouche: [['Pathologies rencontrées', C.num(rows.length)],
            ['Cas totaux', C.num(total)],
            ['Dont à déclaration obligatoire',
              C.num(rows.filter(function (x) { return x.notifiable; }).reduce(function (n, x) { return n + x.cas; }, 0))],
            ['Établi par', S.currentUser()], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Code', key: 'code' },
              { label: 'Pathologie', key: 'libelle' },
              { label: 'Chapitre', key: 'chapitreLabel' },
              { label: 'Déclaration', value: function (x) { return x.notifiable ? 'Obligatoire' : ''; } },
              {
                label: 'Cas', align: 'right',
                value: function (x) { return C.num(x.cas); },
                somme: function (x) { return x.cas; },
                /* Des cas ne sont pas des francs : le pied se formate en
                   nombre, sinon le total du tableau de morbidité s’imprimerait
                   en FCFA. */
                formatTotal: function (v) { return C.num(v); },
              },
              {
                /* `key` sert ici au PIED, pas aux cellules : `value` l’emporte
                   pour les lignes, mais c’est par `key` que la mention de pied
                   ci-dessous retrouve sa colonne. */
                label: 'Part', align: 'right', key: 'part',
                value: function (x) { return total ? Math.round(x.cas / total * 1000) / 10 + ' %' : ''; },
              },
            ], rows, {
              /* La part vaut 100 % par construction ; on la laisse au pied
                 comme mention, elle n’est pas une somme. */
              total: { part: '100 %' }, totalLabel: 'TOTAL',
            }),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Le comptage porte sur les pathologies codées à la consultation. Les consultations '
                + 'antérieures à la mise en place du référentiel ne portent qu’un diagnostic rédigé et ne '
                + 'peuvent pas être comptées rétrospectivement. Les pathologies à déclaration obligatoire '
                + 'sont signalées ; leur déclaration aux autorités sanitaires relève de la clinique.',
            }),
          ]),
          signatures: [{ role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  global.SIGH.screen('m2-ordonnances', {
    title: 'Ordonnances',
    description: 'Prescriptions émises, suivi de leur dispensation en pharmacie et réédition.',
    regle: 'Prescrire engage <strong>quatre services d’un seul geste</strong> : la demande d’analyse part au laboratoire, '
      + 'les médicaments sont annoncés à la pharmacie, la facture attend à la caisse. '
      + 'Rien n’est délivré ni prélevé avant l’encaissement. <strong>RG-02</strong> — médicaments au prix d’achat, sans marge.',
    actions: function () {
      return [
        K.btn('File d’attente caisse', { icon: 'coins', onclick: function () { global.SIGH.app.go('m8-caisse'); } }),
        K.btn('Demandes d’analyses', { icon: 'flask-conical', onclick: function () { global.SIGH.app.go('m5-demandes'); } }),
        K.commande('Nouvelle ordonnance', {
          variant: 'primary', icon: 'file-plus',
          onclick: function () { ouvrirPageOrdonnance(); },
        }),
      ];
    },
    render: function (root) {
      amorcerOrdonnances();
      dessiner();
      return null;

      function dessiner() {
        C.clear(root);
        var col = S.collection('ordonnances');
        var rows = col.active();
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Ordonnances émises', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
          {
            label: 'En attente d’encaissement',
            value: C.num(rows.filter(function (r) { return r.statutPaiement !== 'soldee'; }).length),
            icon: 'coins', tone: 'warning',
          },
          {
            label: 'À délivrer en pharmacie',
            value: C.num(rows.filter(function (r) { return r.statutDispensation === 'en_attente'; }).length),
            icon: 'pill', tone: 'info',
          },
          { label: 'Valeur prescrite', value: C.money(C.sum(rows, 'montant')), icon: 'coins', tone: 'success', hint: 'Au prix d’achat (RG-02)' },
        ]));

        host.appendChild(U.dataTable({
          title: 'Ordonnances', rows: rows, exportName: 'ordonnances', pageSize: 12,
          defaultSort: 'date', defaultDir: 'desc',
          filters: [
            {
              name: 'statutDispensation', label: 'Dispensation',
              options: [{ value: 'en_attente', label: 'À délivrer' }, { value: 'servie', label: 'Servie' },
                { value: 'sans_objet', label: 'Sans médicament' }],
            },
            {
              name: 'statutPaiement', label: 'Règlement',
              options: [{ value: 'impayee', label: 'Impayée' }, { value: 'soldee', label: 'Réglée' }],
            },
          ],
          actions: [K.commande('Nouvelle ordonnance', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrirPageOrdonnance(); } })],
          columns: [
            {
              key: 'numero', label: 'N° ordonnance', nowrap: true,
              render: function (r) {
                return el('div', null, [
                  el('span.font-mono.text-xs', { text: r.numero }),
                  r.urgent ? el('span.ml-1', null, U.badge('Urgent', 'danger')) : null,
                ]);
              },
            },
            { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
            colPatient,
            { key: 'medecin', label: 'Prescripteur' },
            {
              key: 'lignes', label: 'Contenu',
              value: function (r) { return (r.medicaments || []).length + (r.analyses || []).length + (r.actes || []).length; },
              render: function (r) {
                var t = [];
                if ((r.medicaments || []).length) t.push(U.badge(r.medicaments.length + ' médic.', 'info'));
                if ((r.analyses || []).length) t.push(U.badge(r.analyses.length + ' analyse(s)', 'navy'));
                if ((r.actes || []).length) t.push(U.badge(r.actes.length + ' acte(s)', 'neutral'));
                return el('div.flex.flex-wrap.gap-1', null, t);
              },
            },
            { key: 'montant', label: 'Montant', align: 'right', text: function (r) { return C.money(r.montant, false); }, render: function (r) { return C.money(r.montant, false); } },
            {
              key: 'statutPaiement', label: 'Caisse',
              render: function (r) {
                return r.statutPaiement === 'soldee' ? U.badge('Réglée', 'success') : U.badge('À encaisser', 'warning');
              },
            },
            {
              key: 'statutDispensation', label: 'Pharmacie',
              render: function (r) {
                var m = { servie: ['Servie', 'success'], en_attente: ['À délivrer', 'warning'], sans_objet: ['—', 'neutral'] };
                var s = m[r.statutDispensation] || m.sans_objet;
                return U.badge(s[0], s[1]);
              },
            },
          ],
          onRowClick: ouvrirDossier,
          rowActions: function (r) {
            return [
              K.iconBtn('printer', 'Imprimer', function () { etatOrdonnance(r); }),
              K.iconBtn('eye', 'Suivre le parcours', function () { ouvrirDossier(r); }),
            ];
          },
        }));

        root.appendChild(host);
        U.icons(root);
      }

      /* --- Le parcours complet d'une ordonnance, pièce par pièce ----------- */
      function ouvrirDossier(r) {
        var d = PR.dossier(r.id) || { ordonnance: r, demandes: [], mouvements: [], taches: [] };
        var corps = el('div.space-y-4');

        corps.appendChild(U.descList([
          ['Patient', r.patient], ['Dossier', r.patientCode], ['Prescripteur', r.medecin],
          ['Diagnostic', r.diagnostic || '—'], ['Date', C.dateFR(r.date)],
          ['Facture', d.facture ? d.facture.numero : '—'],
        ]));

        if ((r.medicaments || []).length) {
          corps.appendChild(U.card('Médicaments prescrits', K.miniTable([
            { label: 'Produit', key: 'produit' },
            { label: 'Posologie', key: 'posologie' },
            { label: 'Quantité', align: 'right', render: function (l) { return l.quantite + ' ' + (l.unite || ''); } },
            { label: 'Montant', align: 'right', render: function (l) { return C.money(l.total, false); } },
          ], r.medicaments)));
        }
        if ((r.analyses || []).length) {
          corps.appendChild(U.card('Analyses demandées', K.miniTable([
            { label: 'Analyse', key: 'designation' },
            { label: 'Échantillon', key: 'echantillon' },
            {
              label: 'État', render: function (l) {
                var dem = d.demandes.filter(function (x) { return x.analyseCode === l.code; })[0];
                if (!dem) return '—';
                return dem.bloqueParPaiement ? U.badge('Attente caisse', 'warning') : U.statut(dem.etatAnalyse);
              },
            },
            { label: 'Tarif', align: 'right', render: function (l) { return C.money(l.prix, false); } },
          ], r.analyses)));
        }
        if ((r.actes || []).length) {
          corps.appendChild(U.card('Actes prescrits', K.miniTable([
            { label: 'Acte', key: 'libelle' },
            { label: 'Secteur', key: 'secteur' },
            {
              label: 'Tarif', align: 'right',
              render: function (l) {
                return l.prix ? C.money(l.prix, false) : el('span.text-warning-600', { text: 'à valider' });
              },
            },
          ], r.actes)));
        }

        corps.appendChild(U.card('Suivi inter-modules', U.timeline(etapes(d))));

        U.drawer({
          title: r.numero, subtitle: r.patient + ' — ' + C.dateFR(r.date),
          width: 'max-w-3xl',
          body: corps,
          footer: [K.btn('Imprimer l’ordonnance', { variant: 'primary', icon: 'printer', onclick: function () { etatOrdonnance(r); } })],
        });
      }

      function etapes(d) {
        var o = d.ordonnance, out = [];
        out.push({ date: C.dateFR(o.date), titre: 'Prescription établie',
          detail: 'Par ' + o.medecin + ' — ' + C.money(o.montant, false), tone: 'success' });
        if (d.demandes.length) {
          out.push({ date: C.dateFR(o.date), titre: d.demandes.length + ' demande(s) d’analyse créée(s) d’office',
            detail: 'Transmises au laboratoire — module M5', tone: 'info' });
        }
        out.push({
          date: o.statutPaiement === 'soldee' ? C.dateFR(o.date) : '—',
          titre: o.statutPaiement === 'soldee' ? 'Encaissement validé par la caisse' : 'En attente d’encaissement',
          detail: d.facture ? d.facture.numero + ' — ' + C.money(d.facture.partPatient, false) + ' à la charge du patient' : '—',
          tone: o.statutPaiement === 'soldee' ? 'success' : 'warning',
        });
        if (o.statutDispensation !== 'sans_objet') {
          out.push({
            date: o.dispenseLe ? C.dateFR(o.dispenseLe) : '—',
            titre: o.statutDispensation === 'servie' ? 'Médicaments délivrés' : 'Délivrance en attente',
            detail: o.statutDispensation === 'servie'
              ? d.mouvements.length + ' sortie(s) de stock — justificatif ' + o.numero
              : 'La pharmacie ne peut servir qu’après encaissement (RG-03)',
            tone: o.statutDispensation === 'servie' ? 'success' : 'warning',
          });
        }
        return out;
      }


      /* Une seule fonction d'impression pour les deux écrans : deux copies
         auraient divergé au premier changement de maquette. */
      function etatOrdonnance(r) { etatOrdonnanceMedicale(r); }

      function etatOrdonnanceAncienne(r) {
        var lignes = (r.medicaments || []).map(function (l) {
          return { produit: l.produit, detail: l.posologie || '', quantite: l.quantite + ' ' + (l.unite || ''), prix: l.prix, total: l.total };
        });
        P.etat({
          titre: 'Ordonnance médicale',
          sousTitre: r.numero,
          cartouche: [['Patient', r.patient], ['Dossier', r.patientCode], ['Date', C.dateFR(r.date)],
            ['Prescripteur', r.medecin], ['Diagnostic', r.diagnostic || '—'],
            ['Règlement', r.statutPaiement === 'soldee' ? 'Réglée' : 'En attente']],
          contenu: [
            lignes.length ? P.tableau([
              { label: 'Désignation', key: 'produit' },
              { label: 'Posologie', key: 'detail' },
              { label: 'Quantité', align: 'right', key: 'quantite' },
              { label: 'Prix unitaire', align: 'right', value: function (l) { return C.money(l.prix, false); } },
              {
                label: 'Montant', align: 'right',
                value: function (l) { return C.money(l.total, false); },
                somme: function (l) { return l.total; },
              },
            ], lignes, { total: true }) : null,
            (r.analyses || []).length ? P.tableau([
              { label: 'Analyse demandée', key: 'designation' },
              { label: 'Échantillon', key: 'echantillon' },
              { label: 'Délai', key: 'delai' },
              { label: 'Tarif', align: 'right', value: function (l) { return C.money(l.prix, false); },
                somme: function (l) { return l.prix || 0; } },
            ], r.analyses, { total: true }) : null,
            (r.actes || []).length ? P.tableau([
              { label: 'Acte prescrit', key: 'libelle' },
              { label: 'Secteur', key: 'secteur' },
              { label: 'Tarif', align: 'right', value: function (l) { return l.prix ? C.money(l.prix, false) : 'à valider'; },
                somme: function (l) { return l.prix || 0; } },
            ], r.actes, { total: true }) : null,
          ],
          signatures: [{ role: 'Le Médecin prescripteur', nom: r.medecin, mention: 'Signature et cachet' },
            { role: 'Le Pharmacien', mention: 'Dispensation' }],
        });
      }
    },
  });

  /* Historique : les ordonnances antérieures sont reconstituées une seule fois
     depuis les consultations terminées, puis vivent leur vie dans la collection.
     Elles arrivent réglées et servies — elles ne doivent pas encombrer les files
     d'attente du jour. */
  function amorcerOrdonnances() {
    var db = S.raw();
    if (db.ordonnances && db.ordonnances.length) return;
    var cons = S.collection('consultations').active().filter(function (c) { return c.statut === 'terminee'; });
    var prods = S.collection('produits').active().filter(function (p) { return p.categorie === 'medicament'; });
    var rnd = C.seeded(97);
    db.ordonnances = cons.slice(0, 120).map(function (c, i) {
      var med = [];
      var nb = C.between(rnd, 1, 4);
      for (var k = 0; k < nb; k++) {
        var p = C.pick(rnd, prods);
        var q = C.between(rnd, 1, 20);
        med.push({ produitId: p.id, produit: p.designation, unite: p.unite, quantite: q,
          posologie: '', duree: '', prix: p.prixAchat, total: p.prixAchat * q });
      }
      var montant = C.sum(med, 'total');
      return {
        id: 'ORD' + C.pad(i + 1, 4), statut: 'actif',
        numero: 'ORD-2026-' + C.pad(i + 1, 5),
        date: c.date, patientId: c.patientId, patientCode: c.patientCode, patient: c.patient,
        medecin: c.medecin, diagnostic: c.diagnostic, consultationId: c.id,
        medicaments: med, analyses: [], actes: [],
        montantMedicaments: montant, montantAnalyses: 0, montantActes: 0, montant: montant,
        urgent: false,
        statutPaiement: 'soldee',
        statutDispensation: C.pick(rnd, ['servie', 'servie', 'servie', 'en_attente']),
        statutAnalyses: 'sans_objet', statutActes: 'sans_objet',
      };
    });
    S.save();
  }

  /* ==========================================================================
   * LE CORPS DE L’ORDONNANCE — HISSÉ AU MODULE (21/09/2026)
   * --------------------------------------------------------------------------
   * Il vivait dans la FERMETURE de l’écran des ordonnances. La page de saisie
   * qui le consomme désormais est un AUTRE écran : l’y laisser aurait levé un
   * ReferenceError AU CLIC — donc hors de portée de `npm run check`, qui ouvre
   * les pages sans cliquer. C’est exactement le Bug 0a de la phase 3, et la
   * règle qui en est sortie : deux écrans qui posent la même question la
   * déclarent au module.
   *
   * `apres` remplace l’appel direct à `dessiner()` : le corps ne sait plus sur
   * quel écran il est rendu, et c’est bien ainsi — c’est l’appelant qui décide
   * s’il faut redessiner un tableau ou quitter la page.
   * ======================================================================== */
  /* ==========================================================================
   * L’ORDONNANCE EN PAGE PLEINE (21/09/2026)
   * --------------------------------------------------------------------------
   * Une ordonnance porte autant de lignes de médicaments qu’il en faut, plus
   * les analyses et les actes au catalogue complet. Dans une modale, ajouter
   * une huitième ligne poussait le total et le bouton hors de l’écran, et le
   * prescripteur validait sans voir ce qu’il engageait à la caisse.
   *
   * LA PAGE NE CHANGE RIEN AU CIRCUIT. C’est toujours `PR.prescrire` qui
   * engendre l’ordonnance, les demandes du laboratoire, celles de l’imagerie
   * et la facture ; la page n’est qu’une autre porte sur le même moteur. Un
   * second chemin d’écriture aurait divergé au premier correctif.
   * ======================================================================== */
  function ouvrirPageOrdonnance() {
    global.SIGH.app.go('m2-ordonnance-nouvelle');
  }

  global.SIGH.screen('m2-ordonnance-nouvelle', {
    title: 'Nouvelle ordonnance',
    description: 'Médicaments, analyses et actes d’une même ordonnance — transmise d’un seul geste à la caisse, à la pharmacie et au laboratoire.',
    regle: 'La prescription passe par le <strong>moteur du parcours</strong> : elle engendre l’ordonnance, les '
      + '<strong>demandes d’analyses</strong>, la <strong>facture</strong> et les files d’attente des postes concernés. '
      + 'Les tâches d’aval naissent <strong>bloquées</strong> — l’encaissement seul les libère (RG-03).',
    render: function (root) {
      var retour = C.params().retour || 'm2-ordonnances';
      if (!K.droits('M2').editer) {
        root.appendChild(K.note('Votre profil consulte les ordonnances sans en établir. La prescription appartient '
          + 'au médecin et à la sage-femme (RG-13).', { tone: 'warning', icon: 'lock' }));
        root.appendChild(el('div.mt-3', null, K.btn('Revenir au registre', {
          icon: 'arrow-left', onclick: function () { global.SIGH.app.go(retour); } })));
        return;
      }

      var host = el('div.grid.gap-4.lg\\:grid-cols-3');
      var principal = el('div.space-y-4.lg\\:col-span-2');
      var aside = el('div.space-y-4');

      var corps = corpsOrdonnance(function () { global.SIGH.app.go(retour); });
      principal.appendChild(corps.node);

      aside.appendChild(U.card('Enchaînement du parcours', U.timeline([
        { title: 'Prescription', detail: 'Médicaments, analyses et actes d’une même ordonnance', date: 'Étape 1', tone: 'navy' },
        { title: 'Caisse', detail: 'Une facture GLOBALE, part assureur et part patient (M8)', date: 'Étape 2', tone: 'warning' },
        { title: 'Pharmacie', detail: 'Dispensation débloquée par l’encaissement, sortie de stock (M6)', date: 'Étape 3', tone: 'info' },
        { title: 'Laboratoire', detail: 'Prélèvement autorisé une fois l’examen réglé (M5)', date: 'Étape 4', tone: 'info' },
        { title: 'Résultats', detail: 'Rendus au prescripteur après validation biologique', date: 'Étape 5', tone: 'neutral' },
      ])));
      aside.appendChild(U.card('Rappels de facturation', el('div.space-y-3', null, [
        K.note('<strong>RG-02</strong> — les médicaments sont facturés au <strong>prix d’achat, '
          + 'sans marge</strong>.', { tone: 'info' }),
        K.note('<strong>RG-03</strong> — les tâches d’aval naissent <strong>bloquées</strong> : '
          + 'seul l’encaissement les libère, ligne par ligne.', { tone: 'warning', icon: 'lock' }),
        K.note('<strong>RG-09</strong> — la prise en charge ne s’applique que si la carte est valide '
          + 'à la date de facturation.', { tone: 'warning', icon: 'shield-alert' }),
      ])));

      host.appendChild(principal);
      host.appendChild(aside);
      root.appendChild(host);
      root.appendChild(el('div.mt-4.flex.flex-wrap.items-center.justify-end.gap-2.border-t.border-slate-200.pt-4', null, [
        K.btn('Annuler', { icon: 'x', onclick: function () { global.SIGH.app.go(retour); } }),
        K.btn('Prescrire et transmettre', { variant: 'primary', icon: 'send', onclick: corps.valider }),
      ]));
      root.__validerOrdonnance = corps.valider;
    },
    actions: function () {
      if (!K.droits('M2').editer) return null;
      return [K.btn('Prescrire et transmettre', { variant: 'primary', size: 'sm', icon: 'send', onclick: function () {
        var c = document.getElementById('page-content');
        if (c && c.__validerOrdonnance) c.__validerOrdonnance();
      } })];
    },
  });

  function corpsOrdonnance(apres) {
    var lignes = [];
    var corps = el('div.space-y-4');

    var entete = U.form([
      { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, options: optionsPatients(), col: 'full' },
      { name: 'medecin', label: 'Médecin prescripteur', type: 'select', required: true, options: optionsMedecins() },
      { name: 'date', label: 'Date et heure', type: 'datetime-local', required: true, value: new Date().toISOString().slice(0, 16) },
      { name: 'diagnostic', label: 'Diagnostic', col: 'full' },
      { name: 'urgent', label: 'Prescription urgente' },
    ].map(function (f) { return f.name === 'urgent' ? Object.assign({ type: 'checkbox' }, f) : f; }), {});
    corps.appendChild(U.card('Patient et prescripteur', entete));

    /* Médicaments : autant de lignes que nécessaire. */
    var hoteLignes = el('div.space-y-2');
    var cartMed = U.card('Médicaments', el('div.space-y-3', null, [
      hoteLignes,
      K.btn('Ajouter un médicament', { size: 'sm', icon: 'plus', onclick: function () { ajouterLigne(); } }),
    ]));
    corps.appendChild(cartMed);

    /* Analyses et actes : sélection multiple sur le catalogue complet. */
    var complements = U.form([
      {
        name: 'analyses', label: 'Analyses de laboratoire', type: 'multiselect', col: 'full',
        options: D.ANALYSES.map(function (a) {
          return { value: a.code, label: a.designation, detail: a.categorie + ' · ' + C.money(a.prix, false) };
        }),
        help: 'Chaque analyse cochée engendre sa demande au laboratoire, sans ressaisie.',
      },
      {
        name: 'actes', label: 'Actes et soins', type: 'multiselect', col: 'full',
        options: optionsActes(),
        help: 'Catalogue des activités par secteur — document « Répartition des activités » de la clinique.',
      },
    ], {});
    corps.appendChild(U.card('Analyses et actes', complements));

    var total = el('p.text-sm.font-semibold.text-slate-800');
    var pied = el('div.flex.items-center.justify-between.gap-3', null, [
      el('div', null, [
        el('p.text-xs.text-slate-500', { text: 'Total de la prescription' }),
        total,
      ]),
    ]);
    corps.appendChild(U.card('Récapitulatif', pied));

    ajouterLigne();
    recalculer();
    complements.addEventListener('change', recalculer);


    function ajouterLigne() {
      var ligne = el('div.grid.grid-cols-1.gap-2.rounded-lg.border.border-slate-200.p-2.sm\\:grid-cols-12');
      var produit = U.combo(optionsProduits(), { placeholder: '— Médicament —' });
      var qte = el('input.input', { type: 'number', min: 1, value: 1, 'aria-label': 'Quantité' });
      var poso = el('input.input', { type: 'text', placeholder: 'Posologie (ex. 1 cp × 3/j)', 'aria-label': 'Posologie' });
      var duree = el('input.input', { type: 'text', placeholder: 'Durée', 'aria-label': 'Durée' });
      var sup = K.iconBtn('trash-2', 'Retirer la ligne', function () {
        var i = lignes.indexOf(ref); if (i >= 0) lignes.splice(i, 1);
        if (produit.destroy) produit.destroy();
        ligne.remove(); recalculer();
      });
      ligne.appendChild(el('div.sm\\:col-span-5', null, produit));
      ligne.appendChild(el('div.sm\\:col-span-1', null, qte));
      ligne.appendChild(el('div.sm\\:col-span-3', null, poso));
      ligne.appendChild(el('div.sm\\:col-span-2', null, duree));
      ligne.appendChild(el('div.sm\\:col-span-1.flex.items-center.justify-end', null, sup));
      var ref = { produit: produit, qte: qte, poso: poso, duree: duree };
      lignes.push(ref);
      produit.addEventListener('change', recalculer);
      qte.addEventListener('input', recalculer);
      hoteLignes.appendChild(ligne);
      U.icons(ligne);
    }

    function collecterMedicaments() {
      return lignes.map(function (l) {
        return { produitId: l.produit.value, quantite: Number(l.qte.value) || 0, posologie: l.poso.value, duree: l.duree.value };
      }).filter(function (l) { return l.produitId && l.quantite > 0; });
    }

    function recalculer() {
      var med = collecterMedicaments();
      var mMed = C.sum(med, function (l) {
        var p = S.collection('produits').get(l.produitId);
        return (p ? p.prixAchat : 0) * l.quantite;
      });
      var ctrl = complements.controls;
      var mAna = C.sum(ctrl.analyses.value || [], function (code) {
        var a = D.ANALYSES.filter(function (x) { return x.code === code; })[0];
        return a ? a.prix : 0;
      });
      var mAct = C.sum(ctrl.actes.value || [], function (code) {
        var a = S.collection('actes').active().filter(function (x) { return x.code === code; })[0];
        return (a && a.prix) || 0;
      });
      total.textContent = C.money(mMed + mAna + mAct)
        + '  (médicaments ' + C.money(mMed, false) + ' · analyses ' + C.money(mAna, false) + ' · actes ' + C.money(mAct, false) + ')';
    }

    function valider() {
      var v = entete.collect();
      if (!v) return;
      var comp = complements.collect() || {};
      var med = collecterMedicaments();
      if (!med.length && !(comp.analyses || []).length && !(comp.actes || []).length) {
        U.toast('Une ordonnance doit porter au moins un médicament, une analyse ou un acte.', { type: 'warning' });
        return;
      }
      var res;
      try {
        res = PR.prescrire({
          patientCode: v.patientCode, medecin: v.medecin, diagnostic: v.diagnostic,
          date: v.date ? new Date(v.date).toISOString() : null, urgent: !!v.urgent,
          medicaments: med, analyses: comp.analyses || [], actes: comp.actes || [],
        });
      } catch (e) {
        U.toast('Prescription impossible : ' + e.message, { type: 'error' });
        return;
      }
      var envois = [];
      if (res.demandes.length) envois.push(res.demandes.length + ' demande(s) au laboratoire');
      if (med.length) envois.push('pharmacie informée');
      envois.push('facture ' + res.facture.numero + ' en attente à la caisse');
      /* DIFFÉRÉ : `apres()` ramène au registre, et le message partirait avec
         le document — or c'est lui qui nomme le numéro d'ordonnance et les
         postes saisis. */
      U.toastDiffere('Ordonnance ' + res.ordonnance.numero + ' transmise.', {
        type: 'success', detail: envois.join(' · '), duration: 9000,
      });
      if (apres) apres();
    }

    return { node: corps, valider: valider };
  }

  function optionsProduits() {
    return S.collection('produits').active()
      .filter(function (p) { return p.categorie === 'medicament' || p.categorie === 'conso_medical'; })
      .map(function (p) {
        return {
          value: p.id, label: p.designation,
          detail: C.money(p.prixAchat, false) + ' · stock ' + (p.stockDetail != null ? p.stockDetail : p.stock) + ' ' + (p.unite || ''),
        };
      });
  }
  /* ==========================================================================
   * CONSULTATIONS & SOINS À DOMICILE
   * ======================================================================== */
  global.SIGH.screen('m2-domicile', {
    title: 'Consultations & soins à domicile',
    description: 'Planification, réalisation et facturation spécifique des prestations réalisées au domicile du patient.',
    regle: 'La facturation à domicile applique un <strong>coût additionnel de déplacement</strong> qui s’ajoute au prix des actes, analyses et médicaments (CDCT §10.5). La facture normalisée est délivrée après règlement.',
    render: K.crud({
      collection: 'consultations', entite: 'intervention à domicile', entiteP: 'interventions à domicile', module: 'M2',
      defaultSort: 'date', defaultDir: 'desc', formSize: 'lg',
      columns: [
        colDate(), colPatient,
        { key: 'motif', label: 'Prestation' },
        { key: 'medecin', label: 'Intervenant' },
        { key: 'tarif', label: 'Montant', align: 'right', text: function (r) { return C.money(r.tarif || 0, false); }, render: function (r) { return C.money(r.tarif || 0, false); } },
        { key: 'statut', label: 'Statut', render: function (r) { return U.statut(r.statut); } },
      ],
      fields: function () {
        return champsConsultation().concat([
          { name: 'fraisDeplacement', label: 'Frais de déplacement (FCFA)', type: 'money', value: 5000, help: 'Coût additionnel propre aux prestations à domicile.' },
          { name: 'adresseIntervention', label: 'Adresse d’intervention', col: 'full' },
        ]);
      },
      transform: function (v) { v.type = 'Domicile'; return completerPatient(v); },
      onCreate: function () { return { type: 'Domicile', statut: 'planifiee', tarif: 10000, fraisDeplacement: 5000 }; },
      /* On restreint l'affichage aux interventions à domicile. */
      intro: function () {
        return K.note('Cet écran ne présente que les prestations de type <strong>Domicile</strong>. Les consultations réalisées à la clinique sont gérées depuis l’écran « Consultations ».', { tone: 'info' });
      },
      kpis: function (rows) {
        var dom = rows.filter(function (r) { return r.type === 'Domicile'; });
        return [
          { label: 'Interventions à domicile', value: C.num(dom.length), icon: 'house-plus', tone: 'navy' },
          { label: 'Planifiées', value: C.num(dom.filter(function (r) { return r.statut === 'planifiee'; }).length), icon: 'calendar-clock', tone: 'warning' },
          { label: 'Réalisées', value: C.num(dom.filter(function (r) { return r.statut === 'terminee'; }).length), icon: 'check-circle-2', tone: 'success' },
          { label: 'Recette domicile', value: C.money(C.sum(dom, 'tarif')), icon: 'coins', tone: 'info' },
        ];
      },
      detail: detail, etat: etatConsultation,
    }),
  });

  /* ==========================================================================
   * REGISTRE DES APPELS
   * ======================================================================== */
  global.SIGH.screen('m2-registre-appels', {
    title: 'Registre des appels',
    description: 'Appels entrants et sortants liés à la prise de rendez-vous, aux résultats et au suivi des patients.',
    render: K.registre({
      collection: 'appels', entite: 'appel', entiteP: 'appels', module: 'M2',
      defaultSort: 'dateHeure', defaultDir: 'desc', pageSize: 15,
      source: 'Registre tenu au standard de la clinique.',
      seed: function () {
        var rnd = C.seeded(131);
        var pats = S.collection('patients').active();
        var out = [];
        for (var i = 0; i < 90; i++) {
          var p = C.pick(rnd, pats);
          var d = C.addDays(AUJ, -C.between(rnd, 0, 45));
          d.setHours(C.between(rnd, 7, 19), C.between(rnd, 0, 59));
          out.push({
            id: 'APL' + C.pad(i + 1, 4),
            reference: 'A' + C.pad(i + 1, 5),
            dateHeure: d.toISOString(),
            sens: rnd() > 0.4 ? 'entrant' : 'sortant',
            interlocuteur: p.nom + ' ' + p.prenom,
            telephone: p.telephone,
            objet: C.pick(rnd, OBJETS_APPEL),
            agent: C.pick(rnd, ['OROU YO Edmond', 'Secrétaire médicale', 'Caisse']),
            suite: C.pick(rnd, ['Rendez-vous fixé', 'Information donnée', 'Rappel à programmer', 'Transféré au médecin', 'Sans suite']),
            statut: 'actif',
          });
        }
        return C.sortBy(out, 'dateHeure', 'desc');
      },
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
        {
          key: 'dateHeure', label: 'Date et heure', nowrap: true,
          text: function (r) { return C.dateHeure(r.dateHeure); },
          render: function (r) { return C.dateHeure(r.dateHeure); },
          sortValue: function (r) { return C.toDate(r.dateHeure).getTime(); },
        },
        {
          key: 'sens', label: 'Sens',
          render: function (r) { return U.badge(r.sens === 'entrant' ? 'Entrant' : 'Sortant', r.sens === 'entrant' ? 'info' : 'success'); },
        },
        { key: 'interlocuteur', label: 'Interlocuteur' },
        { key: 'telephone', label: 'Téléphone', nowrap: true },
        { key: 'objet', label: 'Objet' },
        { key: 'agent', label: 'Traité par' },
        { key: 'suite', label: 'Suite donnée' },
      ],
      filters: [
        { name: 'sens', label: 'Sens', options: [{ value: 'entrant', label: 'Entrant' }, { value: 'sortant', label: 'Sortant' }] },
        { name: 'objet', label: 'Objet', options: OBJETS_APPEL },
      ],
      fields: [
        { name: 'dateHeure', label: 'Date et heure', type: 'datetime-local', required: true },
        {
          name: 'sens', label: 'Sens de l’appel', type: 'select', required: true,
          options: [{ value: 'entrant', label: 'Entrant' }, { value: 'sortant', label: 'Sortant' }],
        },
        { name: 'interlocuteur', label: 'Interlocuteur', required: true },
        { name: 'telephone', label: 'Téléphone', type: 'tel' },
        { name: 'objet', label: 'Objet de l’appel', type: 'select', required: true, options: OBJETS_APPEL, col: 'full' },
        { name: 'agent', label: 'Traité par', required: true },
        {
          name: 'suite', label: 'Suite donnée', type: 'select',
          options: ['Rendez-vous fixé', 'Information donnée', 'Rappel à programmer', 'Transféré au médecin', 'Sans suite'],
        },
        { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
      ],
      onCreate: function () {
        return { dateHeure: new Date(2026, 7, 16, 9, 0).toISOString().slice(0, 16), sens: 'entrant', agent: S.currentUser() };
      },
      kpis: function (rows) {
        return [
          { label: 'Appels enregistrés', value: C.num(rows.length), icon: 'phone', tone: 'navy' },
          { label: 'Entrants', value: C.num(rows.filter(function (r) { return r.sens === 'entrant'; }).length), icon: 'phone-incoming', tone: 'info' },
          { label: 'Sortants', value: C.num(rows.filter(function (r) { return r.sens === 'sortant'; }).length), icon: 'phone-outgoing', tone: 'success' },
          { label: 'Rappels à programmer', value: C.num(rows.filter(function (r) { return r.suite === 'Rappel à programmer'; }).length), icon: 'phone-call', tone: 'warning' },
        ];
      },
      detail: function (r) {
        return U.descList([
          ['Référence', r.reference], ['Date et heure', C.dateHeure(r.dateHeure)],
          ['Sens', r.sens === 'entrant' ? 'Entrant' : 'Sortant'],
          ['Interlocuteur', r.interlocuteur], ['Téléphone', r.telephone],
          ['Objet', r.objet], ['Traité par', r.agent], ['Suite donnée', r.suite || '—'],
          ['Observations', r.observations || '—'],
        ]);
      },
    }),
  });

  /* ==========================================================================
   * REGISTRE DES PRESCRIPTIONS — DEUX TYPES, QUATRE ORIGINES
   * --------------------------------------------------------------------------
   * La clinique prescrit deux choses distinctes et depuis quatre endroits :
   *
   *   - l'ORDONNANCE porte des médicaments : elle part à la pharmacie, sort du
   *     stock (RG-03) et se délivre au comptoir ;
   *   - les SOINS portent des actes : ils ne sortent pas du stock, ils sont
   *     ADRESSÉS à un secteur et quelqu'un les exécute, sous son nom.
   *
   * Les confondre rendait invisible tout le travail infirmier — sept
   * infirmiers et trois sages-femmes exécutent des actes que rien ne traçait.
   *
   * Les quatre origines sont consultation, hospitalisation, bloc et maternité.
   * Le prototype ne connaissait que la première.
   * ======================================================================== */
  function colPrescriptions() {
    return S.collection('prescriptions', { module: 'M2', entite: 'prescription', prefix: 'PRS' });
  }
  function colSoignants() {
    return S.collection('soignants', { module: 'M14', entite: 'soignant', prefix: 'SOI' });
  }
  function prescripteurs() {
    return colSoignants().active().filter(function (x) { return x.prescrit; });
  }
  function libelleOrigine(code) {
    var o = (D.ORIGINES_PRESCRIPTION || []).filter(function (x) { return x.code === code; })[0];
    return o ? o.label : (code || '—');
  }
  function libelleSecteur(code) {
    var o = (D.SECTEURS_SOINS || []).filter(function (x) { return x.code === code; })[0];
    if (o) return o.label;
    return code === 'pharmacie' ? 'Pharmacie' : (code || '—');
  }

  global.SIGH.screen('m2-prescriptions', {
    title: 'Prescriptions',
    description: 'Registre unique des prescriptions d’ordonnance et de soins, quelle qu’en soit l’origine.',
    regle: 'Deux prescriptions distinctes : l’<strong>ordonnance</strong> porte des médicaments et sort du stock ; '
      + 'la <strong>prescription de soins</strong> porte des actes et s’adresse à un secteur. '
      + 'Quatre origines : consultation, hospitalisation, bloc et maternité. '
      + 'Seuls <strong>médecins et sages-femmes</strong> prescrivent — le contrôle est au moteur, pas à l’écran.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var rows = colPrescriptions().active();
        var soins = rows.filter(function (r) { return r.type === 'soins'; });
        var ordo = rows.filter(function (r) { return r.type === 'ordonnance'; });
        var enCours = rows.filter(function (r) { return r.statut === 'en_cours'; });
        var bloquees = rows.filter(function (r) { return r.statutPaiement !== 'payee'; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Prescriptions', value: C.num(rows.length), icon: 'clipboard-plus', tone: 'navy' },
          { label: 'Ordonnances', value: C.num(ordo.length), icon: 'scroll-text', tone: 'info',
            hint: 'médicaments — vers la pharmacie' },
          { label: 'Prescriptions de soins', value: C.num(soins.length), icon: 'hand-heart', tone: 'success',
            hint: 'actes — vers un secteur d’exécution' },
          { label: 'En attente de règlement', value: C.num(bloquees.length), icon: 'lock',
            tone: bloquees.length ? 'warning' : 'neutral', hint: 'exécution bloquée' },
        ]));

        vue.appendChild(K.note('Une prescription non réglée reste <strong>visible mais non exécutable</strong> : '
          + 'l’encaissement la débloque. C’est la même règle que pour la délivrance en pharmacie et pour le '
          + 'laboratoire — le poste voit ce qui l’attend sans pouvoir le servir avant paiement.',
        { tone: 'info', icon: 'lock' }));

        vue.appendChild(U.tabs([
          { id: 'toutes', label: 'Toutes', badge: rows.length, render: function () { return tableau(rows); } },
          { id: 'soins', label: 'Prescriptions de soins', badge: soins.length, render: function () { return tableau(soins); } },
          { id: 'ordonnances', label: 'Ordonnances', badge: ordo.length, render: function () { return tableau(ordo); } },
          { id: 'encours', label: 'En cours', badge: enCours.length, render: function () { return tableau(enCours); } },
        ]));
        U.icons(vue);
      }

      function champs() {
        return [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients() },
          {
            name: 'prescripteurId', label: 'Prescripteur', type: 'select', required: true,
            options: prescripteurs().map(function (x) {
              return { value: x.id, label: x.nomComplet + ' — ' + x.poste };
            }),
            hint: 'Médecins et sages-femmes seulement : l’infirmier n’est pas habilité à prescrire.',
          },
          {
            name: 'origine', label: 'Origine de la prescription', type: 'select', required: true,
            options: (D.ORIGINES_PRESCRIPTION || []).map(function (o) { return { value: o.code, label: o.label }; }),
          },
          {
            name: 'secteurDestinataire', label: 'Secteur destinataire', type: 'select', required: true,
            options: (D.SECTEURS_SOINS || []).map(function (o) { return { value: o.code, label: o.label }; }),
            hint: 'Sans destinataire, la prescription n’apparaîtrait sur aucun poste.',
          },
          {
            name: 'modalite', label: 'Modalité de traitement', type: 'select', required: true,
            options: (D.MODALITES_TRAITEMENT || []).map(function (m) { return { value: m.code, label: m.label }; }),
            hint: 'Ambulatoire : salle de soins seule. Hospitalisation : première administration en salle de soins, '
              + 'les suivantes en hospitalisation.',
          },
          { name: 'indication', label: 'Indication', type: 'textarea', rows: 2 },
          {
            name: 'actes', label: 'Actes prescrits', type: 'multiselect', required: true,
            options: (D.tarifParFamille ? D.tarifParFamille('AMI') : []).map(function (a) {
              return {
                value: a.code,
                label: a.code + ' — ' + a.libelle,
                detail: a.prixNonAssure == null ? 'tarif non renseigné au document'
                  : C.money(a.prixNonAssure) + ' non assuré · ' + C.money(a.prixAssure) + ' assuré',
              };
            }),
          },
          {
            name: 'nbAdministrations', label: 'Nombre d’administrations par acte', type: 'number',
            min: 1, max: 60, value: 1,
            hint: 'C’est ce nombre qui fait vivre le relais : une administration unique ne quitte jamais la salle de soins.',
          },
        ];
      }

      /* La prescription passe OBLIGATOIREMENT par le moteur : c'est lui qui
         refuse un prescripteur non habilité, applique le tarif assuré ou non
         assuré selon RG-09 et notifie le secteur destinataire. K.creer()
         insérerait lui-même et produirait une seconde fiche, vide. On lui
         emprunte donc seulement le contrôle des droits. */
      function nouvelle() {
        if (!K.droits('M2').editer) return null;
        return K.btn('Nouvelle prescription de soins', {
          variant: 'primary', size: 'sm', icon: 'plus',
          onclick: function () {
            var f = U.form(champs(), { modalite: 'ambulatoire', nbAdministrations: 1 });
            var m = U.modal({
              title: 'Prescrire des soins',
              subtitle: 'Les champs marqués d’un astérisque sont obligatoires.',
              size: 'lg', body: f,
              footer: [
                K.btn('Annuler', { onclick: function () { m.close(); } }),
                K.btn('Prescrire', {
                  variant: 'primary', icon: 'plus',
                  onclick: function () {
                    var v = f.collect();
                    if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                    var pres;
                    try {
                      pres = PR.prescrireSoins({
                        patientCode: v.patientCode,
                        prescripteurId: v.prescripteurId,
                        origine: v.origine,
                        secteurDestinataire: v.secteurDestinataire,
                        modalite: v.modalite,
                        indication: v.indication,
                        actes: (v.actes || []).map(function (c) {
                          return { code: c, nbAdministrations: v.nbAdministrations || 1 };
                        }),
                      });
                    } catch (err) {
                      /* Le refus d'habilitation se dit, il ne se tait pas. */
                      U.toast(err.message, { type: 'error' });
                      return;
                    }
                    m.close();
                    afficher();
                    U.toast('Prescription ' + pres.reference + ' enregistrée.', {
                      type: 'success',
                      detail: libelleSecteur(pres.secteurDestinataire) + ' — première administration : '
                        + libelleSecteur(pres.premierAdministrateur),
                      undo: function () { colPrescriptions().archive(pres.id); afficher(); },
                      undoMessage: 'Prescription annulée — la fiche est archivée.',
                    });
                  },
                }),
              ],
            });
          },
        });
      }

      function tableau(rows) {
        return U.dataTable({
          rows: C.sortBy(rows, 'date').reverse(),
          empty: 'Aucune prescription enregistrée.',
          actions: [boutonPrescrire()].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'date', label: 'Date', render: function (r) { return C.dateHeure(r.date); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
            {
              key: 'type', label: 'Type', render: function (r) {
                return U.badge(r.type === 'soins' ? 'Soins' : 'Ordonnance',
                  r.type === 'soins' ? 'success' : 'info');
              },
            },
            { key: 'origine', label: 'Origine', render: function (r) { return libelleOrigine(r.origine); } },
            { key: 'secteurDestinataire', label: 'Destinataire', render: function (r) { return libelleSecteur(r.secteurDestinataire); } },
            { key: 'prescripteur', label: 'Prescripteur' },
            {
              key: 'montant', label: 'Montant', align: 'right',
              render: function (r) { return C.money(r.montant || 0); },
            },
            {
              key: 'statutPaiement', label: 'Règlement', render: function (r) {
                return r.statutPaiement === 'payee'
                  ? U.badge('Réglée', 'success') : U.badge('Non réglée', 'warning');
              },
            },
          ],
          rowActions: K.actionsLigne(colPrescriptions(), null, {
            module: 'M2', detail: detail, refresh: afficher,
            titre: function (r) { return r.reference; },
          }),
        });
      }

      function boutonPrescrire() {
        return nouvelle();
      }

      function detail(r) {
        var lignes = (r.lignes || []).map(function (l, i) {
          var rang = PR.rangSuivant(r.id, i);
          var att = D.secteurAdministrateur(r.modalite, rang);
          return [
            l.libelle,
            String(l.quantite || 1),
            (rang - 1) + ' / ' + (l.nbAdministrations || 1),
            libelleSecteur(att.secteur),
            l.prix == null ? 'tarif non renseigné' : C.money(l.prix),
          ];
        });
        return el('div.space-y-4', null,
          K.grid([
            ['Référence', r.reference], ['Date', C.dateHeure(r.date)],
            ['Patient', r.patient + ' — ' + r.patientCode],
            ['Type', r.type === 'soins' ? 'Prescription de soins' : 'Ordonnance'],
            ['Origine', libelleOrigine(r.origine)],
            ['Prescripteur', r.prescripteur],
            ['Secteur destinataire', libelleSecteur(r.secteurDestinataire)],
            ['Modalité', r.modalite === 'ambulatoire' ? 'Ambulatoire' : 'En hospitalisation'],
            ['Tarif appliqué', r.assure ? 'Assuré (carte valide à la date)' : 'Non assuré'],
            ['Règlement', r.statutPaiement === 'payee' ? 'Réglée' : 'Non réglée'],
          ]),
          r.indication ? K.section('Indication', el('p.text-sm.text-slate-600', { text: r.indication })) : null,
          K.section('Lignes et avancement des administrations',
            K.miniTable(['Acte', 'Qté', 'Administré', 'Prochain secteur', 'Prix'], lignes)),
          K.note('Le <strong>prochain secteur</strong> n’est pas un choix d’organisation : il découle du rang. '
            + 'Traitement ambulatoire, la salle de soins administre du premier au dernier passage ; traitement '
            + 'hospitalier, la <strong>première</strong> administration revient à la salle de soins et les '
            + '<strong>suivantes</strong> à l’hospitalisation.', { tone: 'info', icon: 'route' }));
      }
    },
  });

  /* ==========================================================================
   * SALLE DE SOINS
   * --------------------------------------------------------------------------
   * Le poste voit ce qui LUI revient, calculé par la règle de relais et non
   * par un filtre écrit ici : trois écrans posent la même question, y répondre
   * trois fois aurait produit trois réponses divergentes au premier correctif.
   * ======================================================================== */
  function ecranAdministration(id, secteur, titre, description, regle) {
    global.SIGH.screen(id, {
      title: titre,
      description: description,
      regle: regle,
      render: function (root) {
        var vue = el('div.space-y-4');
        root.appendChild(vue);
        afficher();
        return null;

        function executants() {
          return colSoignants().active().filter(function (x) {
            return x.execute && (x.secteurs || []).indexOf(secteur) !== -1;
          });
        }

        function afficher() {
          var dus = PR.soinsDuSecteur(secteur);
          var lignes = dus.reduce(function (n, d) { return n + d.lignes.length; }, 0);
          var bloquees = dus.reduce(function (n, d) {
            return n + d.lignes.filter(function (l) { return l.bloque; }).length;
          }, 0);
          var premieres = dus.reduce(function (n, d) {
            return n + d.lignes.filter(function (l) { return l.rang === 1; }).length;
          }, 0);

          C.clear(vue);
          vue.appendChild(U.kpiGrid([
            { label: 'Patients concernés', value: C.num(dus.length), icon: 'users', tone: 'navy' },
            { label: 'Administrations dues', value: C.num(lignes), icon: 'syringe', tone: 'info' },
            { label: 'Premières administrations', value: C.num(premieres), icon: 'flag', tone: 'success' },
            { label: 'Bloquées faute de règlement', value: C.num(bloquees), icon: 'lock',
              tone: bloquees ? 'warning' : 'neutral' },
          ]));

          vue.appendChild(K.note(regle, { tone: 'info', icon: 'route' }));

          var rows = [];
          dus.forEach(function (d) {
            d.lignes.forEach(function (l) {
              rows.push({
                id: d.prescription.id + ':' + l.index,
                prescription: d.prescription, ligne: l,
                reference: d.prescription.reference,
                patient: d.prescription.patient,
                patientCode: d.prescription.patientCode,
                libelle: l.ligne.libelle,
                rang: l.rang, total: l.total,
                motif: l.motif, bloque: l.bloque,
              });
            });
          });

          vue.appendChild(U.dataTable({
            rows: rows,
            empty: 'Aucune administration due à ce poste pour l’instant.',
            columns: [
              { key: 'reference', label: 'Prescription' },
              { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
              { key: 'libelle', label: 'Acte ou produit' },
              {
                key: 'rang', label: 'Passage', align: 'center',
                render: function (r) { return r.rang + ' / ' + r.total; },
              },
              {
                key: 'motif', label: 'Pourquoi ce poste',
                render: function (r) { return el('span.text-xs.text-slate-500', { text: r.motif }); },
              },
              {
                key: 'bloque', label: 'État', render: function (r) {
                  return r.bloque ? U.badge('Non réglée', 'warning') : U.badge('Exécutable', 'success');
                },
              },
            ],
            rowActions: function (r) {
              if (r.bloque) {
                return [K.iconBtn('lock', 'Bloquée : la prescription n’est pas réglée', function () {
                  U.toast('Administration bloquée — la prescription ' + r.reference + ' n’est pas réglée.',
                    { type: 'warning' });
                })];
              }
              /* LES DROITS DE L'ÉCRAN, PAS CEUX D'UN AUTRE MODULE. La salle
                 de soins est un écran de M2 ; interroger M3 donnait le droit
                 d'administrer à l'aide-soignante, qui a M3 en écriture et M2
                 en lecture. La matrice descend au niveau de l'écran : c'est
                 l'écran qu'il faut lui nommer. */
              if (!K.droits().editer) return [];
              return [K.btn('Administrer', {
                variant: 'primary', size: 'sm', icon: 'check',
                onclick: function () { administrer(r); },
              })];
            },
          }));
          U.icons(vue);
        }

        function administrer(r) {
          var exs = executants();
          var f = U.form([
            {
              name: 'executantId', label: 'Exécutant', type: 'select', required: true,
              options: exs.map(function (x) { return { value: x.id, label: x.nomComplet + ' — ' + x.poste }; }),
              hint: 'Infirmiers et sages-femmes. Le médecin prescrit, il n’exécute pas les soins.',
            },
            { name: 'observation', label: 'Observation', type: 'textarea', rows: 2 },
          ], {});
          var m = U.modal({
            title: 'Administrer — ' + r.libelle,
            subtitle: r.patient + ' — passage ' + r.rang + ' sur ' + r.total,
            body: el('div.space-y-3', null,
              K.note(r.motif, { tone: 'info', icon: 'route' }), f),
            footer: [
              K.btn('Annuler', { onclick: function () { m.close(); } }),
              K.btn('Confirmer l’administration', {
                variant: 'primary', icon: 'check',
                onclick: function () {
                  var v = f.collect();
                  if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                  var res = PR.administrer(r.prescription.id, {
                    ligneIndex: r.ligne.index, secteur: secteur,
                    executantId: v.executantId, observation: v.observation,
                  });
                  if (!res.ok) { U.toast(res.motif, { type: 'error' }); return; }
                  m.close();
                  afficher();
                  U.toast('Administration n° ' + res.rang + ' enregistrée.', {
                    type: 'success', detail: r.libelle + ' — ' + r.patient,
                  });
                },
              }),
            ],
          });
        }
      },
    });
  }

  ecranAdministration('m2-salle-soins', 'salle_soins', 'Salle de soins',
    'Administrations dues à la salle de soins : ambulatoires et premières administrations des hospitalisés.',
    'La salle de soins administre <strong>tous</strong> les traitements ambulatoires, du premier au dernier passage, '
      + 'et la <strong>première</strong> administration des traitements hospitaliers. Le relais passe ensuite à '
      + 'l’hospitalisation — c’est le circuit décrit par la Direction, appliqué par le moteur et non laissé à '
      + 'l’usage.');


  /* ==========================================================================
   * ÉCHOGRAPHIE ET IMAGERIE
   * --------------------------------------------------------------------------
   * L'écran applique la spécification que l'échographiste a écrite de sa main
   * sur son brouillon : des LISTES DE CHOIX partout où la valeur est
   * catégorielle, MAIS « Annexes » et « Conclusion » en TEXTE LIBRE — « à
   * remplir par moi-même », dit le document. Fermer ces deux rubriques dans un
   * formulaire à cases irait contre une instruction écrite.
   *
   * L'âge gestationnel est un COUPLE « n SA + n jours » et non un texte : le
   * saisir librement autoriserait « 7 mois », qui ne se compare à rien et ne
   * permet aucune datation de terme.
   *
   * Le compte rendu porte DEUX intervenants nommés : le PRESCRIPTEUR et le
   * RÉALISATEUR. Les cinq pièces réelles portent toutes « Réalisé par : AHOHOU
   * Rodrigue » avec ses téléphones — l'échographiste engage sa signature.
   * ======================================================================== */
  function colImagerie() {
    return S.collection('resultatsImagerie', { module: 'M2', entite: 'compte rendu d’imagerie', prefix: 'IMG' });
  }
  function IM() { return D.IMAGERIE || {}; }

  /* --------------------------------------------------------------------------
   * PHASE 8 — LE PARAMÉTRAGE DE L'IMAGERIE VIT AU MAGASIN
   * --------------------------------------------------------------------------
   * `examensImagerie` et `variablesImagerie` sont semées au socle depuis
   * D.IMAGERIE (la semence) et administrées par `cfg-imagerie-catalogue` :
   * lire la constante ici, c'était rendre le catalogue inmodifiable — le
   * défaut déjà corrigé sur les actes (D2). Le repli sur D.IMAGERIE couvre
   * un magasin d'ancienne génération, jamais le cas nominal.
   * ------------------------------------------------------------------------ */
  function colDemandesImagerie() {
    return S.collection('demandesImagerie', { module: 'M2', entite: 'demande d’imagerie', prefix: 'IME' });
  }
  function colCliches() {
    return S.collection('clichesImagerie', { module: 'M2', entite: 'cliché', prefix: 'CLI' });
  }
  function imExamens() {
    var c = S.collection('examensImagerie').active();
    return c.length ? c : (IM().EXAMENS || []);
  }
  function imExamen(code) {
    return imExamens().filter(function (x) { return x.code === code; })[0] || null;
  }
  function imVariablesDe(codeExamen) {
    var c = S.collection('variablesImagerie').active()
      .filter(function (v) { return v.examen === codeExamen && v.actif !== false; })
      .sort(function (a, b) { return (a.ordre || 0) - (b.ordre || 0); });
    if (c.length) return c;
    return IM().variablesDe ? IM().variablesDe(codeExamen) : [];
  }
  function imRubriquesDe(codeExamen) {
    var vus = {}, out = [];
    imVariablesDe(codeExamen).forEach(function (v) {
      if (vus[v.rubrique]) return;
      vus[v.rubrique] = true; out.push(v.rubrique);
    });
    return out;
  }
  /* La modalité d'un examen se lit au CATALOGUE (vague 61) : le compte rendu
     ne porte pas de modalité propre, qui pourrait contredire son examen. */
  function imModaliteDe(codeExamen) {
    var ex = imExamen(codeExamen) || (IM().examen ? IM().examen(codeExamen) : null);
    return IM().modaliteDeExamen ? IM().modaliteDeExamen(ex) : 'echographie';
  }
  function imModalite(code) {
    return (IM().modalite && IM().modalite(code)) || { code: code, label: code };
  }
  /* Les rubriques rédigées dépendent de la modalité : « Annexes » est la
     demande de l'échographiste, « Recommandation » celle du plan radiologique. */
  function imLibresDe(codeExamen) {
    var m = imModalite(imModaliteDe(codeExamen));
    return m.rubriquesLibres || IM().RUBRIQUES_LIBRES || [];
  }

  /* Les états de la demande d'imagerie — LES MÊMES que le laboratoire :
     demandée (caisse) → payée (exécutable) → exécutée (CR saisi) →
     validée (CR rendu au prescripteur). */
  var ETATS_IMAGERIE = [
    { id: 'demandee', label: 'Demandée — attente caisse', tone: 'warning' },
    { id: 'payee', label: 'Payée — à exécuter', tone: 'info' },
    { id: 'executee', label: 'Exécutée — CR en rédaction', tone: 'navy' },
    { id: 'validee', label: 'Validée — CR rendu', tone: 'success' },
  ];
  function etatImagerie(id) {
    return ETATS_IMAGERIE.filter(function (x) { return x.id === id; })[0]
      || { id: id, label: id, tone: 'neutral' };
  }

  /* --- La saisie du compte rendu, partagée entre l'écran de saisie et le
         registre des demandes : UNE mécanique, deux portes. -----------------
     CORRECTIONS DU 14/09/2026 (demande de l'échographiste), portées par le
     MOTEUR et non écran par écran — les variables les déclarent
     (data-imagerie.js), la mécanique les applique à tout examen :
       - `saisieTexte` (modalité) : mesures, dimensions et âge gestationnel se
         saisissent en TEXTE — « 12 x 8 », « < 5 », « non mesurable » ;
       - `conditionnels` : un champ de précision n'apparaît que pour les
         valeurs qui l'appellent (« Autre », « hétérogène », ovaire anormal) ;
       - `repete` : un bloc se duplique selon le nombre déclaré (sacs,
         embryons). Pour ne pas surcharger la modale, les blocs n°2 et n°3
         sont REPLIABLES et n'existent à l'écran que si le nombre les appelle ;
         leurs valeurs se rangent `CODE__2`, `CODE__3`. */
  function saisieTexteDe(codeExamen) {
    var m = imModalite(imModaliteDe(codeExamen));
    return !!(m && m.saisieTexte);
  }
  /** Combien d'exemplaires d'une variable répétée : lu sur la variable qui porte le nombre (« 02 » → 2). */
  function exemplairesDe(v, valeurs) {
    if (!v.repete) return 1;
    var n = parseInt(String((valeurs || {})[v.repete] || ''), 10);
    return n >= 2 && n <= 3 ? n : 1;
  }
  /** La variable pour son n-ième exemplaire : code suffixé, libellé numéroté, précisions suffixées. */
  function exemplaire(v, k) {
    if (k <= 1) return v;
    var suf = '__' + k;
    return Object.assign({}, v, {
      code: v.code + suf, libelle: v.libelle, numero: k,
      conditionnels: (v.conditionnels || []).map(function (c) { return Object.assign({}, c, { code: c.code + suf }); }),
    });
  }
  function valeurCorrespond(c, valeur) {
    return (c.quand || []).some(function (q) { return String(q).toLowerCase() === String(valeur || '').toLowerCase(); });
  }

  function champDeCR(v, texte) {
    var out;
    if (v.type === 'gestationnel') {
      out = [
        texte ? { name: v.code + '_sa', label: v.libelle + ' — semaines d’aménorrhée', type: 'text' }
          : { name: v.code + '_sa', label: v.libelle + ' — semaines d’aménorrhée', type: 'number', min: 1, max: 45 },
        texte ? { name: v.code + '_j', label: v.libelle + ' — jours', type: 'text' }
          : { name: v.code + '_j', label: v.libelle + ' — jours', type: 'number', min: 0, max: 6 },
      ];
    } else if (v.type === 'dimensions') {
      out = ['a:longueur', 'b:largeur', 'c:épaisseur'].map(function (x) {
        var p = x.split(':');
        return texte ? { name: v.code + '_' + p[0], label: v.libelle + ' — ' + p[1] + ' (mm)', type: 'text' }
          : { name: v.code + '_' + p[0], label: v.libelle + ' — ' + p[1] + ' (mm)', type: 'number', step: 0.1 };
      });
    } else if (v.type === 'liste' || v.type === 'binaire') {
      out = [{ name: v.code, label: v.libelle, type: 'select',
        options: (v.options || []).map(function (o) { return { value: o, label: o }; }) }];
    } else if (v.type === 'mesure') {
      out = [texte ? { name: v.code, label: v.libelle + (v.unite ? ' (' + v.unite + ')' : ''), type: 'text' }
        : { name: v.code, label: v.libelle + (v.unite ? ' (' + v.unite + ')' : ''), type: 'number', step: 0.1 }];
    } else if (v.type === 'multiple') {
      out = [{ name: v.code, label: v.libelle, type: 'multiselect',
        options: (v.options || []).map(function (o) { return { value: o, label: o }; }) }];
    } else if (v.type === 'zone') {
      out = [{ name: v.code, label: v.libelle, type: 'textarea', rows: 3 }];
    } else {
      out = [{ name: v.code, label: v.libelle, type: 'text' }];
    }
    /* Les champs de précision suivent IMMÉDIATEMENT la liste qui les appelle. */
    (v.conditionnels || []).forEach(function (c) {
      out.push({ name: c.code, label: c.libelle, type: 'text', condition: { controle: v.code, quand: c.quand } });
    });
    return out;
  }

  function valeurLisibleCR(v, valeurs) {
    function deux(x) { var s = String(x); return /^\d$/.test(s) ? '0' + s : s; }
    var lu;
    if (v.type === 'gestationnel') {
      var sa = valeurs[v.code + '_sa'], j = valeurs[v.code + '_j'];
      lu = (sa == null || sa === '') ? '—' : (deux(sa) + ' SA + ' + deux(j == null || j === '' ? 0 : j) + ' jours');
    } else if (v.type === 'dimensions') {
      var dims = [valeurs[v.code + '_a'], valeurs[v.code + '_b'], valeurs[v.code + '_c']]
        .filter(function (x) { return x != null && x !== ''; });
      lu = dims.length ? dims.join(' x ') + ' mm' : '—';
    } else {
      var val = valeurs[v.code];
      if (Array.isArray(val)) lu = val.length ? val.join(', ') : '—';
      else if (val == null || val === '') lu = '—';
      else lu = String(val) + (v.unite && !/[a-zA-Zµ%]\s*$/.test(String(val)) ? ' ' + v.unite : '');
    }
    /* La précision saisie accompagne la valeur qui l'a appelée. */
    (v.conditionnels || []).forEach(function (c) {
      if (valeurCorrespond(c, valeurs[v.code]) && valeurs[c.code]) lu += ' — ' + c.libelle + ' : ' + valeurs[c.code];
    });
    return lu;
  }

  /**
   * Les lignes lisibles d'un compte rendu, rubrique par rubrique, en tenant
   * compte des exemplaires : un deuxième sac ne s'imprime que si le compte
   * rendu déclare deux sacs. Une mécanique pour le tiroir et l'impression.
   */
  function lignesCR(r) {
    var valeurs = r.valeurs || {};
    var vars = imVariablesDe(r.examenCode);
    return imRubriquesDe(r.examenCode).map(function (rub) {
      var duBloc = vars.filter(function (v) { return v.rubrique === rub; });
      var max = duBloc.reduce(function (n, v) { return Math.max(n, exemplairesDe(v, valeurs)); }, 1);
      var groupes = [];
      for (var k = 1; k <= max; k++) {
        groupes.push({
          titre: max > 1 ? rub + ' n°' + k : rub,
          lignes: duBloc.filter(function (v) { return k === 1 || (v.repete && exemplairesDe(v, valeurs) >= k); })
            .map(function (v) {
              var inst = exemplaire(v, k);
              return { variable: inst, lu: valeurLisibleCR(inst, valeurs), hors: IM().ecart(inst, valeurs[inst.code]) };
            }),
        });
      }
      return { rubrique: rub, groupes: groupes };
    });
  }

  /* ==========================================================================
   * LE CORPS DU COMPTE RENDU — RÉUTILISABLE (21/09/2026)
   * --------------------------------------------------------------------------
   * Il bâtit les formulaires de toutes les rubriques, les blocs répétés, les
   * champs conditionnels et les rubriques libres, puis rend `enregistrer()`.
   * Il ne sait plus s’il vit dans une modale ou dans une page : c’est
   * l’appelant qui pose le cadre et les boutons. Sans cette séparation, la
   * page aurait recopié la construction des formulaires, et la copie aurait
   * cessé de suivre au premier examen ajouté au catalogue.
   *
   * `enregistrer(cible)` ACCEPTE UNE AUTRE FICHE que celle qui a servi à
   * bâtir le formulaire. C’est ce qui permet à la page de tout montrer d’un
   * bloc — en-tête ET variables — puis de créer la fiche au moment de
   * l’enregistrement seulement : un compte rendu ne doit pas exister au
   * registre tant que personne n’a décidé de l’écrire.
   * ======================================================================== */
  function corpsCR(rec) {
    var vars = imVariablesDe(rec.examenCode);
    var rubriques = imRubriquesDe(rec.examenCode);
    var libres = imLibresDe(rec.examenCode);
    var texte = saisieTexteDe(rec.examenCode);
    var valeurs = Object.assign({}, rec.valeurs || {});
    libres.forEach(function (r) { valeurs[r.code] = rec[r.code] || ''; });

    /* ======================================================================
     * UNE RUBRIQUE, UNE CARTE (22/09/2026)
     * ----------------------------------------------------------------------
     * « Résultat », « Ovaires et cul-de-sac de Douglas », « Conclusion » se
     * suivaient dans UN seul formulaire, séparées par de simples titres de
     * section. Sur un compte rendu qui porte trente champs, rien ne dit plus
     * où finit une rubrique et où commence la suivante : on remplit la taille
     * d'un ovaire dans la ligne du cul-de-sac sans s'en apercevoir.
     *
     * Chaque rubrique reçoit donc sa CARTE — en-tête et corps, comme partout
     * ailleurs dans le logiciel. Le mécanisme de relevé n'a rien à changer :
     * `formulaires` était DÉJÀ une liste, et `controle()` cherchait déjà à
     * travers elle — c'est ce qui permet aux champs conditionnels de se
     * commander d'une carte à l'autre.
     * ==================================================================== */
    var corps = el('div.space-y-4');

    function carteRubrique(titre, contenu) {
      return U.card(titre, contenu);
    }
    var formulaires = [];      /* { form, champs, bloc (details répété ou null), controle, rang } */

    rubriques.forEach(function (rub) {
      var duBloc = vars.filter(function (v) { return v.rubrique === rub; });
      if (!duBloc.length) return;
      var champs = [];
      duBloc.forEach(function (v) { champs = champs.concat(champDeCR(v, texte)); });
      var contenu = el('div.space-y-3');
      var f = U.form(champs, valeurs);
      formulaires.push({ form: f, champs: champs, bloc: null });
      contenu.appendChild(f);

      /* Les exemplaires n°2 et n°3 : des blocs REPLIABLES, présents seulement
         quand le nombre déclaré les appelle. Ils restent DANS la carte de
         leur rubrique — un sac gestationnel n°2 rangé ailleurs que sous
         « Sac gestationnel » serait introuvable. */
      var repetees = duBloc.filter(function (v) { return v.repete; });
      repetees.length && [2, 3].forEach(function (k) {
        var champsK = [];
        repetees.forEach(function (v) { champsK = champsK.concat(champDeCR(exemplaire(v, k), texte)); });
        var fk = U.form(champsK, valeurs);
        var det = el('details.rounded-lg.border.border-navy-200.bg-slate-50', { open: true }, [
          el('summary.cursor-pointer.px-3.py-2.text-sm.font-semibold.text-navy-800', { text: rub + ' n°' + k }),
          el('div.border-t.border-slate-200.p-3', null, fk),
        ]);
        det.setAttribute('data-exemplaire', rub + '|' + k);
        formulaires.push({ form: fk, champs: champsK, bloc: det, controle: repetees[0].repete, rang: k });
        contenu.appendChild(det);
      });

      corps.appendChild(carteRubrique(rub, contenu));
    });

    /* Les rubriques RÉDIGÉES — Résultats, Conclusion, Recommandation — ont
       leur carte elles aussi : ce sont celles que le praticien signe. */
    libres.forEach(function (r) {
      var champs = [{ name: r.code, label: r.label, type: 'textarea', rows: 4,
        required: !!r.requis, hint: r.note }];
      var f = U.form(champs, valeurs);
      formulaires.push({ form: f, champs: champs, bloc: null });
      corps.appendChild(carteRubrique(r.label, f));
    });

    function controle(nom) {
      for (var i = 0; i < formulaires.length; i++) {
        if (formulaires[i].form.controls[nom]) return formulaires[i].form.controls[nom];
      }
      return null;
    }
    function actualiser() {
      formulaires.forEach(function (x) {
        if (x.bloc) {
          var ctl = controle(x.controle);
          var n = parseInt(String(ctl ? ctl.value : ''), 10);
          x.bloc.classList.toggle('hidden', !(n >= x.rang && n <= 3));
        }
        x.champs.forEach(function (c) {
          if (!c.condition) return;
          var ctlC = x.form.controls[c.condition.controle] || controle(c.condition.controle);
          var visible = ctlC && valeurCorrespond(c.condition, ctlC.value);
          var cible = x.form.controls[c.name];
          if (cible && cible.parentElement) cible.parentElement.classList.toggle('hidden', !visible);
        });
      });
    }
    formulaires.forEach(function (x) {
      Object.keys(x.form.controls).forEach(function (nom) {
        var ctl = x.form.controls[nom];
        if (ctl && ctl.addEventListener) ctl.addEventListener('change', actualiser);
      });
    });
    actualiser();

    /**
     * Relève les formulaires et écrit sur `cible` (par défaut la fiche qui a
     * servi à bâtir le corps). Retourne `true` si l’écriture a eu lieu.
     */
    function enregistrer(cible) {
      var fiche = cible || rec;
      {
            var v = {}, erreur = false;
            formulaires.forEach(function (x) {
              var bloc = x.form.collect();
              if (!bloc) { erreur = true; return; }
              /* Un bloc masqué (sac non déclaré) ou une précision masquée ne
                 s'enregistrent pas : une valeur invisible est une valeur
                 qu'on ne relira jamais, et qu'on imprimerait pourtant. */
              if (x.bloc && x.bloc.classList.contains('hidden')) return;
              x.champs.forEach(function (c) {
                var cible = c.name && x.form.controls[c.name];
                if (c.condition && cible && cible.parentElement && cible.parentElement.classList.contains('hidden')) {
                  delete bloc[c.name];
                }
              });
              Object.assign(v, bloc);
            });
            if (erreur) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
            var patch = {};
            libres.forEach(function (r) { patch[r.code] = v[r.code] || ''; delete v[r.code]; });
            patch.valeurs = v;
            colImagerie().update(fiche.id, patch);
            /* La demande suit son compte rendu : exécutée dès la saisie. */
            if (fiche.demandeImagerieId) {
              var dem = colDemandesImagerie().get(fiche.demandeImagerieId);
              if (dem && (dem.statut === 'payee' || dem.statut === 'executee')) {
                colDemandesImagerie().update(dem.id, {
                  statut: 'executee', executeLe: new Date().toISOString(),
                });
              }
            }
            /* Différé : l'enregistrement ramène au tableau. */
            U.toastDiffere('Compte rendu enregistré.', { type: 'success', detail: fiche.reference });
            return true;
      }
    }

    return { node: corps, enregistrer: enregistrer };
  }

  function rendreCR(r, apres) {
    if (!r.conclusion) {
      U.toast('La conclusion est obligatoire avant de rendre le compte rendu.', { type: 'error' });
      return;
    }
    U.confirm({
      title: 'Rendre le compte rendu au prescripteur ?',
      message: 'Le compte rendu <strong>' + r.reference + '</strong> sera transmis à '
        + r.prescripteur + '. Une correction ultérieure devra être signalée comme telle.',
      confirmLabel: 'Rendre',
    }).then(function (ok) {
      if (!ok) return;
      colImagerie().update(r.id, { statut: 'rendu', renduLe: new Date().toISOString() });
      if (r.demandeImagerieId) {
        colDemandesImagerie().update(r.demandeImagerieId, {
          statut: 'validee', valideLe: new Date().toISOString(),
        });
      }
      PR.notifier({
        type: 'imagerie_rendue', poste: 'consultation',
        libelle: 'Compte rendu d’imagerie rendu — ' + r.patient,
        detail: r.examen + ' — ' + r.reference + ' — prescripteur ' + r.prescripteur,
        patientId: r.patientId, reference: r.reference,
      });
      if (apres) apres();
      U.toast('Compte rendu rendu au prescripteur.', { type: 'success', detail: r.reference });
    });
  }

  /* Les comptes rendus d'AVANT le retrait de la rubrique « Annexes » la
     portent encore : on l'affiche, marquée comme saisie antérieure — faire
     disparaître un texte écrit et rendu au prescripteur serait réécrire la
     pièce. */
  function annexesAnterieures(r) {
    var libres = imLibresDe(r.examenCode);
    if (!r.annexes || libres.some(function (l) { return l.code === 'annexes'; })) return null;
    return r.annexes;
  }

  function detailCR(r) {
    var lignes = [];
    lignesCR(r).forEach(function (bloc) {
      bloc.groupes.forEach(function (g) {
        g.lignes.forEach(function (l) { lignes.push([g.titre, l.variable.libelle, l.lu]); });
      });
    });
    var anciennes = annexesAnterieures(r);
    return el('div.space-y-4', null,
      K.grid([
        ['Référence', r.reference], ['Examen', r.examen],
        ['Patient', r.patient + ' — ' + r.patientCode],
        ['Âge', r.age != null ? r.age + ' ans' : '—'],
        ['Indication', r.indication], ['DDR', r.ddr || '—'],
        ['Provenance', r.provenance || '—'],
        ['Condition de l’examen', r.condition || '—'],
        ['Prescripteur', r.prescripteur], ['Réalisé par', r.realisateur],
        ['État', r.statut === 'rendu' ? 'Rendu au prescripteur' : 'En rédaction'],
      ]),
      K.section('Résultats', K.miniTable(['Rubrique', 'Variable', 'Valeur'], lignes)),
      imLibresDe(r.examenCode).map(function (lib) {
        if (!r[lib.code]) return null;
        return K.section(lib.label, el('p.whitespace-pre-line.text-sm', {
          class: lib.code === 'conclusion' ? 'font-medium text-slate-800' : 'text-slate-600', text: r[lib.code] }));
      }).filter(Boolean).concat(anciennes ? [K.section('Annexes (saisie antérieure au 14/09/2026)',
        el('p.whitespace-pre-line.text-sm.text-slate-600', { text: anciennes }))] : []));
  }

  function imprimerCR(r) {
    var corps = el('div');
    lignesCR(r).forEach(function (bloc) {
      bloc.groupes.forEach(function (g) {
        corps.appendChild(el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase.tracking-wide', { text: g.titre }));
        g.lignes.forEach(function (l) {
          corps.appendChild(el('p.text-\\[10px\\].leading-relaxed', null, [
            el('span.font-medium', { text: l.variable.libelle + ' : ' }),
            el(l.hors ? 'span.font-bold' : 'span', { text: l.lu }),
          ]));
        });
      });
    });
    var anciennes = annexesAnterieures(r);
    if (anciennes) {
      corps.appendChild(el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase.tracking-wide', { text: 'Annexes' }));
      corps.appendChild(el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', { text: anciennes }));
    }
    imLibresDe(r.examenCode).forEach(function (lib) {
      /* La conclusion s'imprime toujours, fût-elle vide : son absence doit se
         voir. Les autres rubriques rédigées ne paraissent que remplies. */
      if (lib.code !== 'conclusion' && !r[lib.code]) return;
      corps.appendChild(el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase.tracking-wide', { text: lib.label }));
      corps.appendChild(el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', {
        class: lib.code === 'conclusion' ? 'font-semibold' : '', text: r[lib.code] || '—' }));
    });

    var echo = imModaliteDe(r.examenCode) === 'echographie';
    P.etat({
      titre: (r.examen || '').toUpperCase(),
      sousTitre: r.reference + ' — ' + r.patient,
      cartouche: [
        ['Nom et prénoms', r.patient], ['Âge', r.age != null ? r.age + ' ans' : '—'],
        ['Indication', r.indication],
        /* La DDR est une donnée d'échographie ; ailleurs, la modalité la remplace. */
        echo ? ['DDR', r.ddr || '—'] : ['Modalité', imModalite(imModaliteDe(r.examenCode)).label],
        ['Prescripteur', r.prescripteur],
        echo ? ['Provenance', r.provenance || '—'] : null,
        ['Condition de l’examen', r.condition || '—'],
      ].filter(Boolean),
      contenu: corps,
      signatures: [{ role: 'Réalisé par', nom: r.realisateur, mention: 'Signature' }],
    });
  }

  /* ==========================================================================
   * LES CINQ TABLEAUX D'IMAGERIE — UNE FABRIQUE, CINQ MODALITÉS (vague 61)
   * --------------------------------------------------------------------------
   * Radiographie, mammographie, scanner et IRM se branchent sur le socle de
   * l'échographie : même compte rendu par variables, même rendu au
   * prescripteur, même registre des demandes, même verrou de caisse. Seul
   * change le FILTRE — la modalité de l'examen — et ce que l'écran met en
   * avant. Cinq écrans écrits à la main auraient divergé au premier correctif ;
   * c'est la leçon du code patient, qui vivait à deux endroits.
   *
   * Un compte rendu appartient au tableau de la modalité de SON EXAMEN, lue au
   * catalogue : il n'y a pas de champ « modalité » à saisir sur le compte
   * rendu, qui pourrait contredire l'examen.
   * ======================================================================== */
  function crsDeModalite(code) {
    return colImagerie().active().filter(function (r) { return imModaliteDe(r.examenCode) === code; });
  }

  /* ==========================================================================
   * LE COMPTE RENDU D’IMAGERIE EN PAGE PLEINE (21/09/2026)
   * --------------------------------------------------------------------------
   * C’ÉTAIT DEUX MODALES EN CHAÎNE : on choisissait l’examen dans la première,
   * qui CRÉAIT AUSSITÔT la fiche au registre, puis la seconde ouvrait les
   * variables. Deux défauts en découlaient. D’abord, fermer la seconde laissait
   * au registre un compte rendu vide que personne n’avait voulu écrire.
   * Ensuite, l’en-tête disparaissait au moment de saisir : l’échographiste ne
   * voyait plus pour quel patient ni pour quelle indication il remplissait ses
   * mesures — sur une salle qui enchaîne les examens, c’est ainsi qu’un
   * résultat se porte au dossier du patient précédent.
   *
   * LA PAGE MONTRE TOUT D’UN BLOC, et n’écrit qu’au moment où on enregistre.
   * Changer d’examen reconstruit les variables sous l’en-tête, sans rien créer.
   *
   * UNE SEULE PAGE POUR LES CINQ MODALITÉS. Elle lit sa modalité dans son
   * adresse (`#modalite=scanner`). Cinq pages auraient recopié cinq fois le
   * même écran, et le dépôt a déjà payé ce prix — c’est pour l’éviter que les
   * cinq tableaux sortent d’une fabrique unique.
   * ======================================================================== */
  function champsEnteteCR(mod, o) {
    var opts = o || {};
    var lister = function () {
      return imExamens().filter(function (x) {
        return imModaliteDe(x.code) === mod.code;
      });
    };
    var champs = [
      { name: 'examenCode', label: 'Examen', type: 'select', required: true,
        options: lister().map(function (x) { return { value: x.code, label: x.label }; }) },
      { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients() },
      { name: 'indication', label: 'Indication', type: 'text', required: true,
        hint: opts.indicationHint || 'Ce que le prescripteur cherche.' },
      { name: 'realisateurId', label: 'Réalisé par', type: 'select', required: true,
        options: colSoignants().active().filter(function (x) { return x.realiseImagerie || x.qualite === 'medecin'; })
          .map(function (x) { return { value: x.id, label: x.nomComplet + ' — ' + x.poste }; }) },
    ];
    champs.splice.apply(champs, [3, 0].concat(K.champsPrescripteur(prescripteurs().map(function (x) {
      return { value: x.id, label: x.nomComplet + ' — ' + x.poste };
    }))));
    if (mod.code === 'echographie') {
      champs.push({ name: 'ddr', label: 'DDR — date des dernières règles', type: 'text',
        hint: 'Laisser « inconnue » si la patiente ne la connaît pas — c’est le cas sur les pièces réelles.' });
    }
    if (mod.provenance) {
      champs.push({ name: 'provenance', label: 'Provenance', type: 'text',
        hint: 'Service ou établissement d’où vient le patient.' });
    }
    champs.push({ name: 'condition', label: 'Condition de l’examen', type: 'select',
      options: [{ value: 'Bonne', label: 'Bonne' }, { value: 'Moyenne', label: 'Moyenne' },
        { value: 'Difficile', label: 'Difficile' }] });
    return champs;
  }

  /** La fiche à écrire depuis l’en-tête relevé. */
  function ficheDepuisEntete(v) {
    var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
    var ex = imExamen(v.examenCode);
    return {
      reference: C.nextRef('IMG-', 4),
      date: new Date().toISOString(),
      examenCode: v.examenCode, examen: ex ? ex.label : v.examenCode,
      patientId: pt ? pt.id : null,
      patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
      patientCode: v.patientCode,
      /* L’âge se lit par le moteur : un patient sans date de naissance porte
         un âge DÉCLARÉ, et le compte rendu doit le reprendre (21/09/2026). */
      age: C.ageDe(pt),
      indication: v.indication, ddr: v.ddr || '—', condition: v.condition,
      provenance: v.provenance || '',
      prescripteurId: K.idPrescripteur(v), prescripteur: K.nomPrescripteur(v, nomSoignant2),
      realisateurId: v.realisateurId, realisateur: nomSoignant2(v.realisateurId),
      valeurs: {}, annexes: '', conclusion: '',
      statut: 'brouillon',
    };
  }

  /* La saisie a quitté les modales pour la page. Détourné EN UN POINT : le
     registre l’appelle depuis trois endroits, et un appelant oublié aurait
     rouvert une modale que plus personne n’entretient. */
  function saisirCR(rec) {
    global.SIGH.app.go('m2-imagerie-cr', { id: rec.id });
  }

  /* ==========================================================================
   * L'EN-TÊTE SE CHOISIT EN MODALE, LE COMPTE RENDU S'ÉCRIT EN PAGE
   * --------------------------------------------------------------------------
   * Les deux gestes n'ont pas la même durée. Désigner l'examen, le patient et
   * le réalisateur prend quinze secondes et se fait debout, au poste : une
   * fenêtre convient. Rédiger le compte rendu prend dix minutes et demande
   * toute la largeur de l'écran : une page convient.
   *
   * L'EN-TÊTE NE CRÉE RIEN. Il est déposé pour le chargement suivant — le
   * mécanisme du message différé et du drapeau de repli du ruban — et la
   * fiche ne naît qu'à l'ENREGISTREMENT. Créer la fiche à la validation de la
   * modale laisserait au registre un brouillon vide chaque fois qu'on ouvre
   * une saisie puis qu'on se ravise, et c'est précisément ce que le code
   * évitait déjà.
   *
   * « sessionStorage » et non l'adresse : l'en-tête porte huit champs, dont un
   * nom de prescripteur extérieur en toutes lettres. Une adresse les
   * afficherait dans la barre du navigateur et dans l'historique.
   * ======================================================================== */
  var CLE_ENTETE_CR = 'sigh-cnt:cr-entete';

  function deposerEnteteCR(v) {
    try { global.sessionStorage.setItem(CLE_ENTETE_CR, JSON.stringify(v)); return true; }
    catch (e) { return false; }
  }

  /** Relève l'en-tête déposé — UNE fois : on ne rouvre pas deux saisies dessus. */
  function releverEnteteCR() {
    var brut = null;
    try {
      brut = global.sessionStorage.getItem(CLE_ENTETE_CR);
      if (brut) global.sessionStorage.removeItem(CLE_ENTETE_CR);
    } catch (e) { return null; }
    if (!brut) return null;
    try { return JSON.parse(brut); } catch (e) { return null; }
  }

  /**
   * La modale d'en-tête. Sa validation OUVRE la page de saisie — elle
   * n'enregistre rien.
   * @param {Object} mod la modalité (échographie, radiographie, …)
   * @param {Object} o   { retour, indicationHint }
   */
  function modaleEnteteCR(mod, o) {
    var opts = o || {};
    var f = U.form(champsEnteteCR(mod, { indicationHint: opts.indicationHint }),
      { ddr: 'inconnue', condition: 'Bonne' });
    var m = U.modal({
      title: 'Nouveau compte rendu — ' + mod.label,
      subtitle: 'L’examen et le patient d’abord ; la rédaction s’ouvre ensuite en pleine page.',
      size: 'lg',
      body: f,
      footer: [
        K.btn('Annuler', { onclick: function () { m.close(); } }),
        K.btn('Continuer vers la saisie', {
          variant: 'primary', icon: 'arrow-right',
          onclick: function () {
            var v = f.collect();
            if (!v) { U.toast('L’en-tête comporte des erreurs.', { type: 'error' }); return; }
            if (!deposerEnteteCR(v)) {
              U.toast('Impossible d’ouvrir la saisie : le stockage de session est indisponible.',
                { type: 'error', duration: 9000 });
              return;
            }
            m.close();
            global.SIGH.app.go('m2-imagerie-cr', {
              nouveau: '1', modalite: mod.code, retour: opts.retour || mod.ecran || 'm2-imagerie',
            });
          },
        }),
      ],
    });
    return m;
  }

  global.SIGH.screen('m2-imagerie-cr', {
    title: 'Compte rendu d’imagerie',
    description: 'En-tête et variables d’un compte rendu d’imagerie — échographie, radiographie, mammographie, scanner ou IRM.',
    regle: 'Le compte rendu porte le <strong>prescripteur</strong> (qui peut être <strong>extérieur à la clinique</strong>), le <strong>réalisateur</strong> et la <strong>provenance</strong>. Les <strong>mesures se saisissent en texte</strong>, et un champ de précision n’apparaît que lorsque la valeur l’appelle. Rien n’est écrit au registre tant que l’enregistrement n’a pas eu lieu.',
    render: function (root) {
      var p = C.params();
      var rec = p.id ? colImagerie().get(p.id) : null;
      /* L'en-tête a été relevé en modale : on le reprend ici, une seule fois. */
      var entetePose = rec ? null : releverEnteteCR();
      var codeMod = rec ? imModaliteDe(rec.examenCode)
        : (entetePose && entetePose.examenCode ? imModaliteDe(entetePose.examenCode)
          : (p.modalite || 'echographie'));
      var mod = imModalite(codeMod);
      var retour = p.retour || (mod.ecran || 'm2-imagerie');

      if (p.id && !rec) {
        root.appendChild(K.note('Ce compte rendu est introuvable — il a pu être archivé depuis que le lien a été ouvert.',
          { tone: 'warning', icon: 'alert-triangle' }));
        root.appendChild(el('div.mt-3', null, K.btn('Revenir au tableau', { variant: 'primary', icon: 'arrow-left',
          onclick: function () { global.SIGH.app.go(retour); } })));
        return;
      }
      if (!K.droits('M2').editer) {
        root.appendChild(K.note('Votre profil consulte les comptes rendus sans les saisir.', { tone: 'warning', icon: 'lock' }));
        root.appendChild(el('div.mt-3', null, K.btn('Revenir au tableau', { icon: 'arrow-left',
          onclick: function () { global.SIGH.app.go(retour); } })));
        return;
      }

      var corps = null;
      var zone = el('div.space-y-4');

      var host = el('div.grid.gap-4.lg\\:grid-cols-3');
      var principal = el('div.space-y-4.lg\\:col-span-2');
      var aside = el('div.space-y-4');

      aside.appendChild(U.card('Enchaînement du parcours', U.timeline([
        { title: 'Demande', detail: 'Prescrite en consultation ou apportée de l’extérieur', date: 'Étape 1', tone: 'success' },
        { title: 'Caisse', detail: 'L’examen ne s’exécute qu’une fois la ligne réglée (M8)', date: 'Étape 2', tone: 'success' },
        { title: 'Compte rendu', detail: 'En-tête, variables et rubriques rédigées — vous y êtes', date: 'Étape 3', tone: 'navy' },
        { title: 'Rendu au prescripteur', detail: 'La demande passe de « exécutée » à « validée »', date: 'Étape 4', tone: 'info' },
        { title: 'Galerie des clichés', detail: 'Images rattachées au patient et au compte rendu', date: 'Étape 5', tone: 'neutral' },
      ])));
      aside.appendChild(U.card('Règles de saisie', el('div.space-y-3', null, [
        K.note('Les <strong>mesures se saisissent en texte</strong> : « environ 12 mm », « sup à 5 cm ». '
          + 'Un champ numérique refuserait ce que le praticien écrit réellement.', { tone: 'info', icon: 'ruler' }),
        K.note('Un champ de <strong>précision</strong> n’apparaît que lorsque la valeur l’appelle — '
          + '« Autre » ouvre le sien.', { tone: 'neutral', icon: 'list-plus' }),
        K.note('Le <strong>prescripteur peut être extérieur</strong> à la clinique : c’est ce qui '
          + 'permet de lui renvoyer le compte rendu.', { tone: 'neutral', icon: 'user-plus' }),
      ])));

      if (rec) {
        /* Fiche existante : son en-tête est déjà arrêté, on le RAPPELLE en
           lecture. Le rouvrir en saisie permettrait de changer le patient
           d’un compte rendu déjà au registre. */
        principal.appendChild(U.card('Examen', K.grid([
          ['Référence', rec.reference], ['Examen', rec.examen],
          ['Patient', (rec.patient || '') + ' — ' + (rec.patientCode || '')],
          ['Indication', rec.indication || '—'],
          ['Prescripteur', rec.prescripteur || '—'], ['Réalisé par', rec.realisateur || '—'],
          ['Provenance', rec.provenance || '—'],
        ])));
        principal.appendChild(zone);
        corps = corpsCR(rec);
        zone.appendChild(corps.node);
      } else if (entetePose) {
        /* L'EN-TÊTE VIENT DE LA MODALE. Il est rappelé en LECTURE : le
           rouvrir en saisie ici donnerait deux endroits où changer le
           patient d'un même compte rendu, et l'on ne saurait plus lequel
           fait foi. Pour le corriger, on revient au tableau et l'on
           recommence — le compte rendu n'existe pas encore. */
        var exPose = imExamen(entetePose.examenCode);
        principal.appendChild(U.card('Nouveau compte rendu — ' + mod.label, el('div.space-y-3', null, [
          K.grid([
            ['Examen', exPose ? exPose.label : entetePose.examenCode],
            ['Patient', entetePose.patientCode || '—'],
            ['Indication', entetePose.indication || '—'],
            ['Prescripteur', K.nomPrescripteur(entetePose, nomSoignant2) || '—'],
            ['Réalisé par', nomSoignant2(entetePose.realisateurId) || '—'],
            ['Provenance', entetePose.provenance || '—'],
            ['Condition', entetePose.condition || '—'],
          ]),
          K.note('Rien n’est encore écrit au registre : la fiche naîtra à '
            + 'l’enregistrement. Pour corriger l’en-tête, revenez au tableau et '
            + 'rouvrez un compte rendu.', { tone: 'info', icon: 'file-plus' }),
        ])));
        principal.appendChild(zone);
        corps = corpsCR({
          id: null, examenCode: entetePose.examenCode,
          examen: exPose ? exPose.label : entetePose.examenCode, valeurs: {},
        });
        zone.appendChild(corps.node);
      } else {
        /* Ni fiche, ni en-tête : l'adresse a été ouverte à froid, ou la page
           a été rechargée après le relevé. On ne devine pas un patient — on
           renvoie là où l'en-tête se choisit. */
        principal.appendChild(U.card('Nouveau compte rendu — ' + mod.label, el('div.space-y-3', null, [
          K.note('L’en-tête de ce compte rendu n’a pas été relevé — la saisie s’ouvre '
            + 'depuis le tableau de la modalité, qui demande l’examen et le patient.',
          { tone: 'warning', icon: 'alert-triangle' }),
          el('div', null, K.btn('Revenir au tableau', {
            variant: 'primary', icon: 'arrow-left',
            onclick: function () { global.SIGH.app.go(retour); },
          })),
        ])));
      }

      function enregistrer() {
        if (rec) {
          if (corps && corps.enregistrer(rec)) global.SIGH.app.go(retour);
          return;
        }
        if (!entetePose || !corps) {
          U.toast('Aucun en-tête relevé : rouvrez la saisie depuis le tableau.',
            { type: 'warning', duration: 8000 });
          return;
        }
        /* La fiche NAÎT ICI — pas à la validation de la modale : un compte
           rendu ne doit pas exister au registre tant que personne ne l’a
           écrit, sinon chaque saisie ouverte puis abandonnée y laisserait
           un brouillon vide. */
        var creee = colImagerie().insert(ficheDepuisEntete(entetePose)).record;
        if (!corps.enregistrer(creee)) {
          /* La saisie est refusée : on retire la fiche qu’on venait d’ouvrir,
             sinon un brouillon vide resterait au registre (RG-14 : archivage). */
          colImagerie().archive(creee.id);
          return;
        }
        global.SIGH.app.go(retour);
      }

      host.appendChild(principal);
      host.appendChild(aside);
      root.appendChild(host);

      root.appendChild(el('div.mt-4.flex.flex-wrap.items-center.justify-end.gap-2.border-t.border-slate-200.pt-4', null, [
        K.btn('Annuler', { icon: 'x', onclick: function () { global.SIGH.app.go(retour); } }),
        K.btn('Enregistrer le compte rendu', { variant: 'primary', icon: 'save', onclick: enregistrer }),
      ]));
      root.__enregistrerCR = enregistrer;
    },
    actions: function () {
      if (!K.droits('M2').editer) return null;
      return [K.btn('Enregistrer le compte rendu', { variant: 'primary', size: 'sm', icon: 'save', onclick: function () {
        var c = document.getElementById('page-content');
        if (c && c.__enregistrerCR) c.__enregistrerCR();
      } })];
    },
  });

  function ecranTableauImagerie(o) {
    global.SIGH.screen(o.id, {
      title: o.title,
      description: o.description,
      regle: o.regle,
      render: function (root) {
        var mod = (IM().modalite && IM().modalite(o.modalite)) || { code: o.modalite, label: o.modalite };
        var vue = el('div.space-y-4');
        root.appendChild(vue);
        afficher();
        return null;

        function examens() {
          return imExamens().filter(function (x) { return imModaliteDe(x.code) === o.modalite; });
        }

        function afficher() {
          var rows = crsDeModalite(o.modalite);
          var rendus = rows.filter(function (r) { return r.statut === 'rendu'; });
          var brouillons = rows.filter(function (r) { return r.statut !== 'rendu'; });
          var dems = colDemandesImagerie().active().filter(function (d) {
            return imModaliteDe(d.examenCode) === o.modalite;
          });
          var aExecuter = dems.filter(function (d) { return d.statut === 'payee'; });

          C.clear(vue);
          vue.appendChild(U.kpiGrid([
            { label: 'Comptes rendus', value: C.num(rows.length), icon: mod.icone || 'scan-line', tone: 'navy' },
            { label: 'Rendus au prescripteur', value: C.num(rendus.length), icon: 'send', tone: 'success' },
            { label: 'En cours de rédaction', value: C.num(brouillons.length), icon: 'pencil',
              tone: brouillons.length ? 'warning' : 'neutral' },
            o.kpi ? o.kpi(rows, aExecuter)
              : { label: 'Payés — à exécuter', value: C.num(aExecuter.length), icon: 'wallet',
                tone: aExecuter.length ? 'info' : 'neutral', hint: 'Demandes réglées à la caisse' },
          ]));

          if (o.note) vue.appendChild(K.note(o.note, { tone: 'info', icon: 'pen-line' }));
          if (mod.aValider) {
            vue.appendChild(K.note('<strong>Examens et variables proposés, à valider.</strong> Aucun modèle de '
              + 'compte rendu de ' + C.escapeHtml(mod.label.toLowerCase()) + ' n’a été remis : le catalogue '
              + 'suit la pratique radiologique courante et reste <strong>administrable</strong> depuis le '
              + 'catalogue de l’imagerie. Les tarifs sont des <strong>tarifs d’attente</strong>, à arrêter par '
              + 'la Direction. Les images elles-mêmes ne sont pas stockées au format DICOM : le logiciel tient '
              + 'la demande, le compte rendu et les clichés joints à la galerie.',
            { tone: 'warning', icon: 'flask-conical' }));
          }

          vue.appendChild(U.dataTable({
            rows: C.sortBy(rows, 'date').reverse(),
            exportName: 'imagerie-' + o.modalite, pageSize: 12, searchable: true,
            emptyMessage: 'Aucun compte rendu de ' + mod.label.toLowerCase() + ' enregistré.',
            filters: [
              { name: 'examenCode', label: 'Examen',
                options: examens().map(function (x) { return { value: x.code, label: x.label }; }) },
              { name: 'statut', label: 'État',
                options: [{ value: 'rendu', label: 'Rendu' }, { value: 'brouillon', label: 'En rédaction' }] },
            ],
            actions: [K.commande('Nouveau compte rendu', {
              variant: 'primary', size: 'sm', icon: 'plus', onclick: choisirExamen,
            })].filter(Boolean),
            columns: [
              { key: 'reference', label: 'Référence' },
              { key: 'date', label: 'Date', render: function (r) { return C.dateHeure(r.date); } },
              { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
              { key: 'examen', label: 'Examen' },
              { key: 'prescripteur', label: 'Prescripteur' },
              { key: 'realisateur', label: 'Réalisé par' },
              { key: 'statut', label: 'État', render: function (r) {
                return r.statut === 'rendu' ? U.badge('Rendu', 'success') : U.badge('En rédaction', 'warning');
              } },
            ],
            rowActions: function (r) {
              var actes = [K.iconBtn('printer', 'Imprimer le compte rendu', function () { imprimerCR(r); })];
              if (K.droits().editer && r.statut !== 'rendu') {
                actes.push(K.iconBtn('pencil', 'Poursuivre la saisie', function () { saisirCR(r, afficher); }));
                actes.push(K.iconBtn('send', 'Rendre au prescripteur', function () { rendreCR(r, afficher); }));
              }
              return actes.concat(K.actionsLigne(colImagerie(), null, {
                module: 'M2', refresh: afficher, detail: detailCR,
                titre: function (x) { return x.reference + ' — ' + x.examen; },
              })(r));
            },
          }));
          U.icons(vue);
        }

        /* Le choix de l'examen précède la saisie : les variables en dépendent
           entièrement, et un formulaire unique aurait affiché des rubriques
           sans objet — le plus sûr moyen de faire remplir n'importe quoi. */
        /* Le choix de l’examen et la saisie des variables ont quitté les deux
           modales en chaîne pour UNE page (21/09/2026) : elle montre l’en-tête
           et les variables d’un bloc, et n’écrit au registre qu’à
           l’enregistrement. La modalité voyage dans l’adresse. */
        function choisirExamen() {
          /* La modale d'abord — elle ne crée rien —, la page ensuite. Les
             cinq modalités passent par la MÊME fabrique : une modale par
             modalité aurait divergé au premier champ ajouté. */
          modaleEnteteCR(imModalite(o.modalite), {
            retour: o.id, indicationHint: o.indicationHint || '',
          });
        }
      },
    });
  }

  ecranTableauImagerie({
    id: 'm2-imagerie', modalite: 'echographie',
    title: 'Tableau Échographie',
    description: 'Comptes rendus d’échographie et d’électrocardiogramme, saisis par variables et rendus au prescripteur.',
    regle: 'Les résultats se saisissent par <strong>listes de choix</strong> — c’est la demande écrite de '
      + 'l’échographiste ; les <strong>mesures se saisissent en texte</strong>, et un champ de précision '
      + 'n’apparaît que lorsque la valeur l’appelle (« Autre », « hétérogène »). Seule la <strong>Conclusion</strong> '
      + 'reste en texte libre — « Annexes » a été retirée à sa demande (14/09/2026). Le compte rendu porte le '
      + '<strong>prescripteur</strong>, le <strong>réalisateur</strong> et la <strong>provenance</strong>.',
    note: 'Les listes de choix pré-insérées viennent du <strong>brouillon manuscrit de '
      + 'l’échographiste</strong>, des cinq comptes rendus réels et de ses <strong>corrections du 14/09/2026</strong>. '
      + 'Deux ou trois sacs gestationnels déclarés font paraître autant de blocs de sac, repliables.',
    indicationHint: 'Ce que le prescripteur cherche — « Kyste ovarien ? », « RAU », « Terme », « Croissance ».',
    kpi: function (rows) {
      return { label: 'Examens obstétricaux',
        value: C.num(rows.filter(function (r) { return /OBS/.test(r.examenCode || ''); }).length),
        icon: 'baby', tone: 'info' };
    },
  });

  var REGLE_RADIOLOGIE = 'Le tableau se branche sur le <strong>socle commun de l’imagerie</strong> : la demande '
    + 'naît bloquée par le paiement, le compte rendu se saisit par <strong>variables</strong> sur une demande '
    + 'réglée, puis se <strong>rend au prescripteur</strong> — après quoi il ne se modifie plus. Le plan du '
    + 'compte rendu est celui de la radiologie : technique, résultats, <strong>conclusion obligatoire</strong>, '
    + 'recommandation.';

  /** Compte les comptes rendus dont une variable nommée vaut l'une des valeurs. */
  function compterValeur(rows, codes, valeurs) {
    return rows.filter(function (r) {
      var v = r.valeurs || {};
      return codes.some(function (c) { return valeurs.indexOf(v[c]) !== -1; });
    }).length;
  }

  ecranTableauImagerie({
    id: 'm2-imagerie-radiographie', modalite: 'radiographie',
    title: 'Tableau Radiographie',
    description: 'Comptes rendus de radiographie standard — thorax, bassin, rachis, membres, crâne, ASP.',
    regle: REGLE_RADIOLOGIE + ' Un cliché de <strong>qualité insuffisante</strong> se dit sur la pièce : un '
      + '« normal » lu sur une image inexploitable est une fausse assurance.',
    indicationHint: 'Traumatisme, toux fébrile, douleur lombaire, bilan préopératoire…',
    kpi: function (rows) {
      return { label: 'Fractures relevées',
        value: C.num(compterValeur(rows, ['BAS_FRACT', 'MEM_FRACT'], ['présente'])),
        icon: 'bone', tone: 'danger', hint: 'Bassin et membres' };
    },
  });

  ecranTableauImagerie({
    id: 'm2-imagerie-mammographie', modalite: 'mammographie',
    title: 'Tableau Mammographie',
    description: 'Comptes rendus de mammographie — densité, masses, microcalcifications, classification ACR par sein.',
    regle: REGLE_RADIOLOGIE + ' La <strong>classification ACR se porte sein par sein</strong> : c’est la conduite '
      + 'à tenir qui en découle, et elle diffère d’un côté à l’autre.',
    indicationHint: 'Dépistage, nodule palpé, écoulement, surveillance…',
    kpi: function (rows) {
      return { label: 'ACR 4 ou plus', icon: 'alert-triangle', tone: 'danger',
        value: C.num(compterValeur(rows, ['MAM_ACR_D', 'MAM_ACR_G'],
          ['ACR 4 — suspect', 'ACR 5 — hautement suspect', 'ACR 6 — malignité prouvée'])),
        hint: 'Examens appelant une conduite à tenir' };
    },
  });

  ecranTableauImagerie({
    id: 'm2-imagerie-scanner', modalite: 'scanner',
    title: 'Tableau Scanner',
    description: 'Comptes rendus de tomodensitométrie — technique, injection de produit de contraste, résultats.',
    regle: REGLE_RADIOLOGIE + ' L’<strong>injection</strong> est une donnée de sécurité : produit, volume, '
      + 'créatininémie, allergie et réaction se consignent, et « aucune réaction » <strong>s’écrit</strong>.',
    indicationHint: 'Céphalées, traumatisme crânien, bilan d’extension, colique néphrétique…',
    kpi: function (rows) {
      return { label: 'Avec injection', icon: 'syringe', tone: 'info',
        value: C.num(compterValeur(rows, ['TDM_INJ'], ['avec injection'])),
        hint: C.num(compterValeur(rows, ['TDM_REAC'], ['réaction mineure', 'réaction sévère'])) + ' réaction(s) consignée(s)' };
    },
  });

  ecranTableauImagerie({
    id: 'm2-imagerie-irm', modalite: 'irm',
    title: 'Tableau IRM — imagerie par résonance magnétique',
    description: 'Comptes rendus d’IRM — contre-indications, séquences, gadolinium, résultats.',
    regle: REGLE_RADIOLOGIE + ' Les <strong>contre-indications</strong> (pacemaker, clip métallique, grossesse) '
      + 'se vérifient et se consignent <strong>avant</strong> l’examen ; les séquences réalisées sont portées '
      + 'sur la pièce.',
    indicationHint: 'Sciatique, épilepsie, entorse du genou, masse pelvienne…',
    kpi: function (rows) {
      return { label: 'Avec gadolinium', icon: 'droplets', tone: 'info',
        value: C.num(compterValeur(rows, ['IRM_GADO'], ['avec gadolinium'])) };
    },
  });

  function nomSoignant2(id) {
    var x = colSoignants().active().filter(function (y) { return y.id === id; })[0];
    return x ? x.nomComplet : '—';
  }

  /* ==========================================================================
   * PHASE 8 — L'IMAGERIE ÉCLATÉE : DEMANDES, TABLEAU DE BORD, GALERIE
   * --------------------------------------------------------------------------
   * L'imagerie suit désormais LES MÊMES ÉTATS que le laboratoire — demandée →
   * payée → exécutée → validée — portés par `demandesImagerie` et le moteur
   * `PR.ouvrirDemandeImagerie` (la ligne payable porte `demandeImagerieId`).
   * L'écran de saisie (m2-imagerie) reste la porte du compte rendu ; la voie
   * directe y demeure ouverte — c'est la saisie « manuelle » du poste, comme
   * au laboratoire — et se distingue par l'absence de demande liée.
   * ======================================================================== */

  /** Le compte rendu d'une demande, s'il existe. */
  function crDeDemande(dem) {
    return colImagerie().active().filter(function (r) {
      return r.demandeImagerieId === dem.id;
    })[0] || null;
  }

  /** Ouvre (en le créant au besoin) le compte rendu d'une demande PAYÉE. */
  function saisirDepuisDemande(dem, apres) {
    var cr = crDeDemande(dem);
    if (!cr) {
      var pt = S.collection('patients').active().filter(function (x) { return x.id === dem.patientId; })[0];
      var realisateur = colSoignants().active().filter(function (x) { return x.realiseImagerie; })[0];
      cr = colImagerie().insert({
        reference: C.nextRef('IMG-', 4),
        date: new Date().toISOString(),
        examenCode: dem.examenCode, examen: dem.examen,
        patientId: dem.patientId, patient: dem.patient, patientCode: dem.patientCode,
        age: pt ? C.age(pt.dateNaissance) : null,
        indication: dem.indication || '—', ddr: 'inconnue', condition: 'Bonne',
        prescripteur: dem.prescripteur,
        realisateurId: realisateur ? realisateur.id : null,
        realisateur: realisateur ? realisateur.nomComplet : (S.currentUser() || '—'),
        valeurs: {}, annexes: '', conclusion: '',
        statut: 'brouillon',
        demandeImagerieId: dem.id, demandeReference: dem.reference,
      }).record;
    }
    saisirCR(cr, apres);
  }

  /* --------------------------------------------------------------------------
   * REGISTRE DES DEMANDES D'IMAGERIE
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m2-imagerie-demandes', {
    title: 'Demandes d’imagerie médicale',
    description: 'Le registre des examens demandés, aux mêmes états que le laboratoire : demandé, payé, exécuté, validé.',
    regle: 'La demande naît <strong>bloquée par le paiement</strong> : c’est l’encaissement de SA ligne '
      + 'qui la rend exécutable — la caisse encaisse des examens nommés. Le compte rendu ne se saisit '
      + 'que sur une demande <strong>payée</strong>, et sa validation (rendu au prescripteur) clôt le '
      + 'circuit. Un examen sans tarif validé est <strong>refusé en le nommant</strong> — un tiret '
      + 'n’est pas un zéro.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function rows() { return colDemandesImagerie().active(); }

      function afficher() {
        var r0 = rows();
        var parEtat = {};
        ETATS_IMAGERIE.forEach(function (e) {
          parEtat[e.id] = r0.filter(function (r) { return r.statut === e.id; });
        });

        C.clear(vue);
        vue.appendChild(U.kpiGrid(ETATS_IMAGERIE.map(function (e) {
          return { label: e.label, value: C.num(parEtat[e.id].length),
            icon: e.id === 'demandee' ? 'wallet' : (e.id === 'payee' ? 'scan-line'
              : (e.id === 'executee' ? 'pencil' : 'file-check-2')),
            tone: parEtat[e.id].length ? e.tone : 'neutral' };
        })));

        vue.appendChild(U.dataTable({
          title: 'Registre des demandes', rows: function () {
            /* La modalité se lit au catalogue ; elle est posée sur la ligne
               affichée pour que le filtre la trouve, jamais écrite au magasin. */
            return rows().map(function (r) {
              return Object.assign({}, r, { modalite: r.modalite || imModaliteDe(r.examenCode) });
            });
          },
          exportName: 'demandes-imagerie', pageSize: 12, searchable: true,
          defaultSort: 'dateHeure', defaultDir: 'desc',
          filters: [
            { name: 'modalite', label: 'Modalité',
              options: (IM().MODALITES || []).map(function (m) { return { value: m.code, label: m.label }; }) },
            { name: 'statut', label: 'État',
              options: ETATS_IMAGERIE.map(function (e) { return { value: e.id, label: e.label }; }) },
          ],
          emptyMessage: 'Aucune demande d’imagerie. Une demande s’ouvre ici ou naît d’une consultation.',
          /* OUVRIR une demande est un acte de PRESCRIPTION : l'échographiste
             exécute et saisit le CR (son droit d'écran l'y autorise), mais
             prescrire serait un exercice illégal — la commande de création
             lui est fermée NOMMÉMENT, comme ses écrans de prescription. */
          actions: ((S.session() || {}).role === 'echographiste' ? [] : [K.commande('Nouvelle demande', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: nouvelleDemande,
          })]).filter(Boolean),
          columns: [
            { key: 'reference', label: 'N°', render: function (r) {
              return el('div', null, [
                el('span.font-mono.text-xs', { text: r.reference }),
                r.factureNumero ? el('p.font-mono.text-[10px].text-slate-400', { text: r.factureNumero }) : null,
              ]);
            } },
            { key: 'dateHeure', label: 'Date', render: function (r) { return C.dateFR(r.dateHeure); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + (r.patientCode || '—'); } },
            { key: 'examen', label: 'Examen' },
            { key: 'modalite', label: 'Modalité',
              value: function (r) { return imModalite(imModaliteDe(r.examenCode)).label; },
              render: function (r) { return U.badge(imModalite(imModaliteDe(r.examenCode)).label, 'navy'); } },
            { key: 'prescripteur', label: 'Prescripteur' },
            { key: 'prix', label: 'Tarif', align: 'right', render: function (r) { return C.money(r.prix, false); } },
            {
              key: 'statut', label: 'État',
              value: function (r) { return etatImagerie(r.statut).label; },
              render: function (r) {
                var e = etatImagerie(r.statut);
                return U.badge(e.label, e.tone);
              },
            },
          ],
          onRowClick: function (r) {
            var cr = crDeDemande(r);
            U.drawer({
              title: r.examen, subtitle: r.patient + ' — ' + r.reference,
              body: cr ? detailCR(cr) : el('div.space-y-4', null,
                K.grid([
                  ['Référence', r.reference], ['Date', C.dateFR(r.dateHeure)],
                  ['Patient', r.patient], ['Examen', r.examen],
                  ['Prescripteur', r.prescripteur], ['Indication', r.indication || '—'],
                  ['Tarif', C.money(r.prix)], ['Facture', r.factureNumero || '—'],
                  ['État', etatImagerie(r.statut).label],
                ]),
                r.statut === 'demandee'
                  ? K.note('L’examen attend son règlement : la balle est à la caisse ('
                    + (r.factureNumero || 'pièce à émettre') + ').', { tone: 'warning', icon: 'wallet' })
                  : null),
            });
          },
          rowActions: function (r) {
            var actes = [];
            if (r.statut === 'demandee') {
              /* Verrouillé et non masqué : la balle est à la caisse. */
              var b = K.btn('Saisir le CR', {
                size: 'sm', icon: 'lock',
                title: 'Examen non réglé — le patient doit passer à la caisse.',
                onclick: function () {
                  U.toast('Saisie impossible : examen non réglé.', { type: 'error',
                    detail: 'La caisse doit encaisser la pièce ' + (r.factureNumero || '') + ' d’abord.' });
                },
              });
              b.classList.add('opacity-50', 'cursor-not-allowed');
              b.setAttribute('aria-disabled', 'true');
              actes.push(b);
            }
            if (r.statut === 'payee' || r.statut === 'executee') {
              actes.push(K.commande(r.statut === 'payee' ? 'Saisir le CR' : 'Poursuivre le CR', {
                size: 'sm', variant: 'primary', icon: 'file-pen-line',
                onclick: function () { saisirDepuisDemande(r, afficher); },
              }));
            }
            if (r.statut === 'executee') {
              var cr = crDeDemande(r);
              if (cr) {
                actes.push(K.commande('Rendre', {
                  size: 'sm', icon: 'send',
                  onclick: function () { rendreCR(cr, afficher); },
                }));
              }
            }
            if (r.statut === 'validee') {
              var cr2 = crDeDemande(r);
              if (cr2) actes.push(K.iconBtn('printer', 'Imprimer le compte rendu', function () { imprimerCR(cr2); }));
            }
            return actes.filter(Boolean);
          },
        }));
        U.icons(vue);
      }

      function nouvelleDemande() {
        var f = U.form([
          /* PATIENT DU RÉPERTOIRE **OU** ADRESSÉ DE L'EXTÉRIEUR (06/09/2026).
             Une échographie prescrite ailleurs se pratique ici comme une
             analyse prescrite ailleurs : refuser faute de dossier renvoyait
             le patient au comptoir voisin, et le poste tenait son cahier. Le
             dossier s'ouvre par la MÊME fabrique que le laboratoire. */
          { name: 'patientCode', label: 'Patient (dossier du répertoire)', type: 'select', col: 'full',
            options: optionsPatients(),
            help: 'Laisser vide pour un patient ADRESSÉ DE L’EXTÉRIEUR — renseigner alors son identité ci-dessous.' },
          { name: '_sectionExterne', type: 'section', label: 'Ou patient adressé de l’extérieur (dossier créé ici)' },
          /* Identité sur UNE rangée : c'est ainsi qu'on la lit sur une pièce
             d'identité, et c'est ainsi qu'on la saisit. */
          { name: 'nom', label: 'Nom', col: 'third' },
          { name: 'prenom', label: 'Prénom(s)', col: 'third' },
          { name: 'sexe', label: 'Sexe', type: 'select', col: 'third',
            options: [{ value: 'F', label: 'Féminin' }, { value: 'M', label: 'Masculin' }] },
        ].concat(K.champsAge({ required: false }), [
          { name: 'telephone', label: 'Téléphone', type: 'tel' },
          { name: 'residence', label: 'Quartier / résidence' },
          { name: '_sectionExamens', type: 'section', label: 'L’examen demandé' },
          {
            name: 'examens', label: 'Examens demandés', type: 'multiselect', required: true, col: 'third',
            options: imExamens().map(function (x) {
              var t = D.tarif ? D.tarif((x.tarifCode || x.code)) : null;
              return { value: x.code, label: x.label,
                detail: imModalite(imModaliteDe(x.code)).label + ' — ' + (t && t.prixNonAssure != null
                  ? C.money(t.prixNonAssure) + ' non assuré · ' + (t.prixAssure != null ? C.money(t.prixAssure) + ' assuré' : '—')
                    + (t.tarifProvisoire ? ' (tarif d’attente)' : '')
                  : 'tarif non renseigné') };
            }),
          },
          /* Le patient peut être ADRESSÉ DE L'EXTÉRIEUR : une échographie
             prescrite ailleurs se pratique ici, et le compte rendu doit
             pouvoir repartir vers celui qui l'a demandée (21/09/2026). */
        ].concat(K.champsPrescripteur(
          prescripteurs().map(function (x) { return { value: x.nomComplet, label: x.nomComplet + ' — ' + x.poste }; }),
          { name: 'prescripteur', col: 'third', colExterne: 'third' }
        ), [
          { name: 'indication', label: 'Indication', type: 'textarea', rows: 2, required: true },
          { name: 'urgent', label: 'Examen urgent', type: 'checkbox' },
        ])), {});
        var m = U.modal({
          title: 'Nouvelle demande d’imagerie', size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Émettre la demande', {
              variant: 'primary', icon: 'send',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var pt = v.patientCode
                  ? S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0]
                  : null;
                if (v.patientCode && !pt) { U.toast('Patient introuvable.', { type: 'error' }); return; }
                if (!pt && !(String(v.nom || '').trim() && String(v.prenom || '').trim())) {
                  /* Un refus qui NOMME ce qui manque : sans identité, le
                     compte rendu ne peut être ni remis ni retrouvé. */
                  U.toast('Sélectionner un patient du répertoire, ou renseigner le nom et les prénoms '
                    + 'du patient adressé de l’extérieur.', { type: 'error' });
                  return;
                }
                var res;
                try {
                  res = PR.ouvrirDemandeImagerie({
                    patientId: pt ? pt.id : null, examens: v.examens,
                    nom: v.nom, prenom: v.prenom, sexe: v.sexe, dateNaissance: v.dateNaissance,
                    telephone: v.telephone, residence: v.residence,
                    origine: pt ? 'consultation' : 'externe',
                    prescripteur: v.prescripteur, indication: v.indication, urgent: !!v.urgent,
                  });
                } catch (err) { U.toast(err.message, { type: 'error' }); return; }
                m.close(); afficher();
                U.toast('Demande émise — ' + res.demandes.length + ' examen(s).', {
                  type: 'success', duration: 8000,
                  detail: 'Facture ' + res.facture.numero + ' à la caisse ; l’examen sera exécutable après règlement.'
                    + (pt ? '' : ' Dossier ouvert : ' + res.patient.code + '.'),
                });
              },
            }),
          ],
        });
      }
    },
  });

  /* --------------------------------------------------------------------------
   * TABLEAU DE BORD DE L'IMAGERIE — le poste de travail de l'échographiste
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m2-dashboard-imagerie', {
    title: 'Poste d’imagerie médicale',
    description: 'Le premier regard du poste : les examens payés à exécuter, les comptes rendus en rédaction, la file d’attente.',
    regle: 'Un examen ne s’exécute qu’une fois <strong>réglé</strong> — la file du poste ne porte que les '
      + 'demandes payées. Ce tableau LIT les registres, il n’ouvre aucune saisie propre : la donnée '
      + 'n’existe qu’une fois.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      afficher();
      return null;

      function afficher() {
        var dems = colDemandesImagerie().active();
        var payees = dems.filter(function (r) { return r.statut === 'payee'; });
        var attente = dems.filter(function (r) { return r.statut === 'demandee'; });
        var crs = colImagerie().active();
        var redaction = crs.filter(function (r) { return r.statut !== 'rendu'; });
        var moisCourant = C.iso(new Date()).slice(0, 7);
        var rendusMois = crs.filter(function (r) {
          return r.statut === 'rendu' && String(r.renduLe || r.date || '').slice(0, 7) === moisCourant;
        });

        C.clear(host);
        host.appendChild(U.kpiGrid([
          { label: 'Payés — à exécuter', value: C.num(payees.length), icon: 'scan-line',
            tone: payees.length ? 'warning' : 'success', hint: payees.length ? 'Le premier regard du poste' : 'Rien n’attend' },
          { label: 'En attente de caisse', value: C.num(attente.length), icon: 'wallet', tone: 'neutral',
            hint: 'Visibles, non exécutables' },
          { label: 'CR en rédaction', value: C.num(redaction.length), icon: 'pencil',
            tone: redaction.length ? 'info' : 'neutral' },
          { label: 'Rendus ce mois-ci', value: C.num(rendusMois.length), icon: 'file-check-2', tone: 'success' },
        ]));

        if (payees.length) {
          host.appendChild(U.dataTable({
            title: 'À exécuter — examens réglés', rows: payees,
            pageSize: 8, exportName: 'imagerie-a-executer',
            defaultSort: 'dateHeure', defaultDir: 'asc',
            columns: [
              { key: 'reference', label: 'N°', render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
              { key: 'patient', label: 'Patient' },
              { key: 'examen', label: 'Examen' },
              { key: 'urgent', label: 'Priorité', render: function (r) {
                return r.urgent ? U.badge('Urgent', 'danger') : el('span.text-xs.text-slate-400', { text: 'Courante' });
              } },
            ],
            rowActions: function (r) {
              return [K.commande('Saisir le CR', {
                size: 'sm', variant: 'primary', icon: 'file-pen-line',
                moduleCode: 'M2',
                onclick: function () { saisirDepuisDemande(r, afficher); },
              })].filter(Boolean);
            },
          }));
        } else {
          host.appendChild(U.card('À exécuter',
            U.empty('Aucun examen réglé en attente : rien ne vous attend.', { icon: 'check-circle-2' })));
        }

        /* Les cinq modalités d'un coup d'œil : où la charge se trouve, et le
           tableau où la traiter. Un tableau de bord par modalité aurait
           dispersé ce que le poste doit voir ensemble. */
        var parModalite = (IM().MODALITES || []).map(function (m) {
          function de(x) { return imModaliteDe(x.examenCode) === m.code; }
          return {
            code: m.code, label: m.label, ecran: m.ecran, icone: m.icone,
            attente: attente.filter(de).length,
            payees: payees.filter(de).length,
            redaction: redaction.filter(de).length,
            rendus: rendusMois.filter(de).length,
          };
        });
        host.appendChild(U.dataTable({
          title: 'Activité par modalité', rows: parModalite, pageSize: 5, searchable: false,
          exportName: 'imagerie-par-modalite',
          columns: [
            { key: 'label', label: 'Modalité', render: function (r) {
              return el('span.inline-flex.items-center.gap-2.font-medium.text-slate-800', null,
                [C.icon(r.icone || 'scan-line', 'h-4 w-4 text-navy-600'), r.label]);
            } },
            { key: 'attente', label: 'Attente caisse', align: 'right' },
            { key: 'payees', label: 'À exécuter', align: 'right', render: function (r) {
              return r.payees ? el('span.font-semibold.text-warning-700', { text: C.num(r.payees) }) : '0';
            } },
            { key: 'redaction', label: 'CR en rédaction', align: 'right' },
            { key: 'rendus', label: 'Rendus ce mois', align: 'right' },
          ],
          /* Jamais de porte vers un tableau fermé au profil (RG-13). */
          onRowClick: function (r) {
            var Nv = global.SIGH.nav, e = r.ecran && Nv.get(r.ecran);
            if (e && Nv.can((S.session() || {}).role, e)) global.SIGH.app.go(r.ecran);
            else U.toast('Ce tableau n’est pas ouvert à votre profil.', { type: 'info' });
          },
        }));

        host.appendChild(K.fileAttente('imagerie', {
          titre: 'File d’attente du poste',
          vide: 'Aucune tâche d’imagerie en file.',
          icon: 'scan-line',
        }));
        U.icons(host);
      }
    },
  });

  /* --------------------------------------------------------------------------
   * GALERIE DES CLICHÉS — la bibliothèque d'images liée au dossier
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m2-echographie-galerie', {
    title: 'Galerie des clichés',
    description: 'Les clichés d’échographie conservés au poste, rattachés au patient et au compte rendu.',
    regle: 'Un cliché se rattache à un <strong>patient</strong> et, si possible, à son compte rendu : une '
      + 'image orpheline ne se retrouve plus. Conservation locale, <strong>mêmes précautions de taille '
      + 'que les documents du dossier</strong> — au-delà de deux mégaoctets, le stockage du navigateur '
      + 'sature vite. L’archivage est logique (RG-14) : rien ne s’efface.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var rows = colCliches().active();
        var parPatient = {};
        rows.forEach(function (r) { parPatient[r.patientId || r.patient] = true; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Clichés conservés', value: C.num(rows.length), icon: 'images', tone: 'navy' },
          { label: 'Patients concernés', value: C.num(Object.keys(parPatient).length), icon: 'users', tone: 'info' },
          { label: 'Liés à un compte rendu', value: C.num(rows.filter(function (r) { return r.crReference; }).length),
            icon: 'file-check-2', tone: 'success' },
          { label: 'Sans compte rendu lié', value: C.num(rows.filter(function (r) { return !r.crReference; }).length),
            icon: 'help-circle', tone: 'neutral' },
        ]));

        var barre = el('div.card');
        var actions = el('div.card-body.flex.flex-wrap.items-center.gap-3');
        var cmd = K.commande('Ajouter un cliché', {
          variant: 'primary', size: 'sm', icon: 'image-plus', onclick: ajouter,
        });
        if (cmd) actions.appendChild(cmd);
        barre.appendChild(actions);
        vue.appendChild(barre);

        if (!rows.length) {
          vue.appendChild(U.card('Galerie',
            U.empty('Aucun cliché conservé. Les images s’ajoutent depuis ce poste, rattachées au patient.',
              { icon: 'images' })));
        } else {
          var grille = el('div.grid.gap-4.sm:grid-cols-2.lg:grid-cols-3');
          C.sortBy(rows, 'date').reverse().forEach(function (r) {
            var carte = el('div.card.overflow-hidden');
            carte.appendChild(el('img.h-44.w-full.bg-slate-100.object-contain', {
              src: r.fichier, alt: 'Cliché — ' + r.examen,
            }));
            carte.appendChild(el('div.card-body.space-y-1', null, [
              el('p.text-sm.font-medium.text-slate-800', { text: r.patient }),
              el('p.text-xs.text-slate-500', { text: r.examen + ' — ' + C.dateFR(r.date) }),
              r.legende ? el('p.text-xs.text-slate-600', { text: r.legende }) : null,
              el('div.flex.items-center.justify-between.pt-1', null, [
                r.crReference
                  ? el('span.font-mono.text-[10px].text-navy-700', { text: r.crReference })
                  : el('span.text-[10px].text-slate-400', { text: 'sans CR lié' }),
                K.commandeIcone('archive', 'Archiver le cliché', function () {
                  U.confirm({
                    title: 'Archiver ce cliché ?',
                    message: 'Archivage logique (RG-14) : le cliché reste restaurable depuis la Corbeille.',
                    confirmLabel: 'Archiver', danger: true,
                  }).then(function (ok) {
                    if (!ok) return;
                    colCliches().archive(r.id);
                    afficher();
                    U.toast('Cliché archivé.', { type: 'success' });
                  });
                }),
              ].filter(Boolean)),
            ].filter(Boolean)));
            grille.appendChild(carte);
          });
          vue.appendChild(grille);
        }
        U.icons(vue);
      }

      function ajouter() {
        var meta = {};
        var input = el('input.input', { type: 'file', accept: 'image/png,image/jpeg,image/webp' });
        var apercu = el('div');
        input.addEventListener('change', function () {
          C.clear(apercu);
          var file = input.files && input.files[0];
          if (!file) return;
          if (file.size > 2 * 1024 * 1024) {
            apercu.appendChild(K.note('Fichier de ' + Math.round(file.size / 1024) + ' Ko — au-delà de deux '
              + 'mégaoctets, le stockage local sature vite. Exporter le cliché en résolution plus basse.',
            { tone: 'warning', icon: 'alert-triangle' }));
          }
          var lecteur = new FileReader();
          lecteur.onload = function () {
            meta.fichier = lecteur.result;
            apercu.appendChild(el('img.mt-2.max-h-40.rounded-lg.border.border-slate-200.object-contain',
              { src: meta.fichier, alt: 'Aperçu du cliché' }));
          };
          lecteur.readAsDataURL(file);
        });

        var crs = colImagerie().active();
        var f = U.form([
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, col: 'full', options: optionsPatients() },
          {
            name: 'crReference', label: 'Compte rendu lié', type: 'select', col: 'full',
            options: [{ value: '', label: '— aucun —' }].concat(crs.map(function (r) {
              return { value: r.reference, label: r.reference + ' — ' + r.examen + ' — ' + r.patient };
            })),
          },
          { name: 'examen', label: 'Examen', type: 'select', required: true,
            options: imExamens().map(function (x) { return { value: x.label, label: x.label }; }) },
          { name: 'legende', label: 'Légende', type: 'text', col: 'full',
            hint: 'Ce que montre le cliché — coupe, mesure, structure visée.' },
        ], {});

        var m = U.modal({
          title: 'Ajouter un cliché', size: 'lg',
          body: el('div.space-y-3', null, [
            f,
            el('div', null, [el('label.label', { text: 'Image * — PNG, JPEG ou WEBP' }), input, apercu]),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Conserver le cliché', {
              variant: 'primary', icon: 'image-plus',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (!meta.fichier) {
                  U.toast('Choisir une image.', { type: 'error',
                    detail: 'Un cliché sans image n’est qu’une légende.' });
                  return;
                }
                var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
                colCliches().insert({
                  date: new Date().toISOString(),
                  patientId: pt ? pt.id : null,
                  patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                  patientCode: v.patientCode,
                  examen: v.examen, legende: v.legende || '',
                  crReference: v.crReference || null,
                  fichier: meta.fichier,
                  deposePar: S.currentUser(),
                });
                m.close(); afficher();
                U.toast('Cliché conservé.', { type: 'success' });
              },
            }),
          ],
        });
      }
    },
  });


  /* ==========================================================================
   * FILE D'ATTENTE — FIFO TEMPÉRÉ PAR LA PRIORITÉ DE TRIAGE
   * --------------------------------------------------------------------------
   * L'ordre d'arrivée gouverne, SAUF urgence. Les deux règles pures sont
   * mauvaises et la clinique les a toutes deux vécues :
   *
   *   - un FIFO strict fait attendre une urgence vitale derrière douze
   *     consultations de routine ;
   *   - une priorité sans FIFO fait passer indéfiniment les mêmes, et personne
   *     ne sait plus qui est arrivé quand.
   *
   * D'où le rang calculé : la priorité classe d'abord, l'heure d'arrivée
   * départage à priorité égale. Le rang n'est JAMAIS saisi — le saisir
   * permettrait de faire passer quelqu'un devant sans que rien ne le trace.
   *
   * L'heure d'arrivée est celle du dossier patient : c'est la même donnée, et
   * la Direction a demandé qu'elle soit conservée.
   * ======================================================================== */
  var PRIORITES = [
    { code: 'urgence_vitale', label: 'Urgence vitale', rang: 1, couleur: 'danger',
      note: 'Prise en charge immédiate, avant tout autre patient.' },
    { code: 'urgence', label: 'Urgence', rang: 2, couleur: 'warning',
      note: 'Passe devant les consultations programmées et les arrivées libres.' },
    { code: 'rdv', label: 'Sur rendez-vous', rang: 3, couleur: 'info',
      note: 'Le rendez-vous a réservé une plage : il prime sur l’arrivée libre.' },
    { code: 'ordre_arrivee', label: 'Par ordre d’arrivée', rang: 4, couleur: 'neutral',
      note: 'Le cas courant — la sage-femme reçoit par ordre d’arrivée.' },
  ];

  var POSTES_FILE = [
    { code: 'accueil', label: 'Accueil' },
    { code: 'consultation', label: 'Consultation' },
    { code: 'caisse', label: 'Caisse' },
    { code: 'prelevement', label: 'Salle de prélèvement' },
    { code: 'pharmacie', label: 'Pharmacie' },
    { code: 'salle_soins', label: 'Salle de soins' },
    { code: 'imagerie', label: 'Échographie' },
  ];

  function colFile() {
    return S.collection('fileAttente', { module: 'M2', entite: 'ticket de file', prefix: 'FIL' });
  }
  function prioriteDe(code) {
    return PRIORITES.filter(function (x) { return x.code === code; })[0] || PRIORITES[3];
  }
  function libellePoste(code) {
    var x = POSTES_FILE.filter(function (y) { return y.code === code; })[0];
    return x ? x.label : code;
  }

  /* Le classement, écrit UNE fois : l'écran de gestion et l'écran d'appel
     doivent afficher exactement le même ordre, sans quoi le patient appelé ne
     serait pas celui que l'agent voit en tête. */
  function fileTriee(poste) {
    return colFile().active()
      .filter(function (t) { return t.poste === poste && t.etat === 'attente'; })
      .sort(function (a, b) {
        var pa = prioriteDe(a.priorite).rang, pb = prioriteDe(b.priorite).rang;
        if (pa !== pb) return pa - pb;
        return String(a.arriveeLe).localeCompare(String(b.arriveeLe));
      });
  }

  global.SIGH.screen('m2-file-attente', {
    title: 'File d’attente',
    description: 'Gestion des files par poste : ordre d’arrivée tempéré par la priorité de triage.',
    regle: 'L’ordre d’<strong>arrivée</strong> gouverne, <strong>sauf urgence</strong>. Le rang est '
      + '<strong>calculé</strong>, jamais saisi : le saisir permettrait de faire passer quelqu’un devant '
      + 'sans que rien ne le trace. À priorité égale, c’est l’heure d’arrivée qui départage.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var tous = colFile().active();
        var attente = tous.filter(function (t) { return t.etat === 'attente'; });
        var urgences = attente.filter(function (t) { return prioriteDe(t.priorite).rang <= 2; });
        var servis = tous.filter(function (t) { return t.etat === 'servi'; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Patients en attente', value: C.num(attente.length), icon: 'users', tone: 'navy' },
          { label: 'Dont urgences', value: C.num(urgences.length), icon: 'siren',
            tone: urgences.length ? 'danger' : 'success' },
          { label: 'Servis aujourd’hui', value: C.num(servis.filter(function (t) {
            return String(t.serviLe || '').slice(0, 10) === C.iso(new Date());
          }).length), icon: 'check-check', tone: 'success' },
          { label: 'Attente moyenne', value: attenteMoyenne(servis), icon: 'clock', tone: 'info',
            hint: 'sur les patients déjà servis' },
        ]));

        vue.appendChild(K.note('Le <strong>rang</strong> affiché n’est pas un champ : il découle de la priorité '
          + 'et de l’heure d’arrivée. Faire passer un patient devant se fait en changeant sa '
          + '<strong>priorité</strong>, ce qui est tracé — et non en réécrivant un numéro.',
        { tone: 'info', icon: 'list-ordered' }));

        vue.appendChild(U.tabs(POSTES_FILE.map(function (po) {
          var f = fileTriee(po.code);
          return { id: po.code, label: po.label, badge: f.length,
            render: function () { return panneau(po, f); } };
        })));
        U.icons(vue);
      }

      function attenteMoyenne(servis) {
        var avec = servis.filter(function (t) { return t.arriveeLe && t.serviLe; });
        if (!avec.length) return '—';
        var total = avec.reduce(function (n, t) {
          return n + (C.toDate(t.serviLe).getTime() - C.toDate(t.arriveeLe).getTime());
        }, 0);
        return Math.round(total / avec.length / 60000) + ' min';
      }

      function panneau(po, f) {
        return el('div.space-y-3', null,
          U.dataTable({
            rows: f.map(function (t, i) { return Object.assign({ rang: i + 1 }, t); }),
            empty: 'Personne n’attend à ce poste.',
            actions: K.droits('M2').editer ? [K.btn('Inscrire un patient', {
              variant: 'primary', size: 'sm', icon: 'user-plus',
              onclick: function () { inscrire(po.code); },
            })] : [],
            columns: [
              { key: 'rang', label: 'Rang', align: 'center',
                render: function (r) {
                  return el('span.inline-flex.h-7.w-7.items-center.justify-center.rounded-full.bg-navy-900.text-xs.font-bold.text-white',
                    { text: String(r.rang) });
                } },
              { key: 'numero', label: 'N° d’appel',
                render: function (r) { return el('span.font-mono.text-sm.font-semibold', { text: r.numero }); } },
              { key: 'patient', label: 'Patient' },
              { key: 'priorite', label: 'Priorité',
                render: function (r) {
                  var pr = prioriteDe(r.priorite);
                  return U.badge(pr.label, pr.couleur);
                } },
              { key: 'arriveeLe', label: 'Arrivé à',
                render: function (r) { return C.heure(r.arriveeLe); } },
              { key: 'attente', label: 'Attente', align: 'right',
                render: function (r) {
                  var mn = Math.round((Date.now() - C.toDate(r.arriveeLe).getTime()) / 60000);
                  return el('span', { class: mn > 45 ? 'font-semibold text-amber-700' : '',
                    text: mn + ' min' });
                } },
              { key: 'motif', label: 'Motif' },
            ],
            rowActions: function (r) {
              if (!K.droits('M2').editer) return [];
              return [
                K.btn('Appeler', { variant: 'primary', size: 'sm', icon: 'megaphone',
                  onclick: function () { appeler(r); } }),
                K.iconBtn('arrow-up', 'Modifier la priorité', function () { changerPriorite(r); }),
              ];
            },
          }));
      }

      /* Les praticiens qui reçoivent : dérivés du personnel soignant, jamais
         ressaisis — une seconde liste de noms divergerait du dossier RH au
         premier recrutement. */
      function optionsPraticiens() {
        return S.collection('soignants').active()
          .filter(function (x) { return x.prescrit; })
          .map(function (x) { return { value: x.nomComplet, label: x.nomComplet, detail: x.qualiteLabel || '' }; });
      }

      function inscrire(poste) {
        var champs = [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients() },
          { name: 'priorite', label: 'Priorité de triage', type: 'select', required: true,
            options: PRIORITES.map(function (x) { return { value: x.code, label: x.label, detail: x.note }; }) },
          { name: 'motif', label: 'Motif', type: 'text', required: true },
        ];
        /* Le praticien ne se demande QU'EN CONSULTATION, et il reste
           facultatif : la file est souvent commune, le prochain libre prend le
           suivant. L'imposer ferait désigner quelqu'un au hasard, et le
           tableau de bord du médecin porterait des patients qu'un autre
           recevra. */
        if (poste === 'consultation') {
          champs.push({
            name: 'praticien', label: 'Praticien attendu', type: 'select',
            options: [{ value: '', label: '— File commune —' }].concat(optionsPraticiens()),
            help: 'À renseigner seulement si le patient est adressé à un praticien précis '
              + '(rendez-vous nominatif, suivi en cours). Sinon, laisser en file commune.',
          });
        }
        var f = U.form(champs, { priorite: 'ordre_arrivee', praticien: '' });
        var m = U.modal({
          title: 'Inscrire un patient — ' + libellePoste(poste),
          subtitle: 'Le rang sera calculé : priorité d’abord, heure d’arrivée ensuite.',
          body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Inscrire', { variant: 'primary', icon: 'user-plus',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
                /* Le numéro d'appel est propre au poste et à la journée : c'est
                   ce que le patient lit sur l'écran, et il doit repartir à 1
                   chaque matin comme le ticket papier. */
                var jour = C.iso(new Date());
                var n = colFile().all().filter(function (t) {
                  return t.poste === poste && String(t.arriveeLe || '').slice(0, 10) === jour;
                }).length + 1;
                var rec = colFile().insert({
                  numero: libellePoste(poste).slice(0, 1).toUpperCase() + C.pad(n, 3),
                  poste: poste, posteLabel: libellePoste(poste),
                  patientId: pt ? pt.id : null,
                  patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                  patientCode: v.patientCode,
                  priorite: v.priorite, motif: v.motif,
                  /* Vide = file commune. C'est une information, pas un oubli. */
                  praticien: v.praticien || null,
                  arriveeLe: new Date().toISOString(),
                  etat: 'attente',
                }).record;
                m.close(); afficher();
                U.toast('Patient inscrit — numéro ' + rec.numero + '.', {
                  type: 'success', detail: rec.patient + ' — ' + prioriteDe(v.priorite).label,
                  undo: function () { colFile().archive(rec.id); afficher(); },
                  undoMessage: 'Inscription annulée.',
                });
              } }),
          ],
        });
      }

      function appeler(r) {
        colFile().update(r.id, { etat: 'servi', serviLe: new Date().toISOString(), appelePar: S.currentUser() });
        afficher();
        /* Un appel sonne : l'écran d'affichage est dans la salle d'attente, le
           patient ne regarde pas forcément au bon moment. */
        U.sonner('appel');
        U.toast('Patient appelé — ' + r.numero + '.', { type: 'success', detail: r.patient });
      }

      function changerPriorite(r) {
        var f = U.form([
          { name: 'priorite', label: 'Nouvelle priorité', type: 'select', required: true,
            options: PRIORITES.map(function (x) { return { value: x.code, label: x.label, detail: x.note }; }) },
          { name: 'motifChangement', label: 'Motif du changement', type: 'text', required: true,
            hint: 'Obligatoire : faire passer un patient devant un autre doit s’expliquer.' },
        ], { priorite: r.priorite });
        var m = U.modal({
          title: 'Modifier la priorité — ' + r.patient,
          subtitle: 'Le rang se recalcule ; le changement est journalisé (RG-12).',
          body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Appliquer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                colFile().update(r.id, { priorite: v.priorite, motifChangement: v.motifChangement });
                m.close(); afficher();
                U.toast('Priorité modifiée.', { type: 'success',
                  detail: r.patient + ' — ' + prioriteDe(v.priorite).label });
              } }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * ÉCRAN D'APPEL DES PATIENTS
   * --------------------------------------------------------------------------
   * Destiné à un écran de salle d'attente : gros caractères, aucun détail
   * médical. Le patient y lit son NUMÉRO, jamais son nom ni son motif — une
   * salle d'attente n'est pas un lieu où l'on annonce publiquement pourquoi
   * quelqu'un consulte.
   * ======================================================================== */
  global.SIGH.screen('m2-affichage', {
    title: 'Écran d’appel des patients',
    description: 'Affichage de salle d’attente : numéros appelés et numéros suivants, sans aucune donnée médicale.',
    regle: 'Cet écran est destiné à la <strong>salle d’attente</strong>. Il n’affiche que des '
      + '<strong>numéros</strong> — jamais le nom du patient ni son motif. Une salle d’attente n’est pas un '
      + 'lieu où l’on annonce publiquement pourquoi quelqu’un consulte.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      /* L'écran vit sans personne devant le clavier : il se rafraîchit seul. */
      var minuteur = setInterval(afficher, 15000);
      root.addEventListener('sigh:unmount', function () { clearInterval(minuteur); });
      return null;

      function afficher() {
        C.clear(vue);
        var cartes = el('div.grid.gap-4.sm\\:grid-cols-2.lg\\:grid-cols-3');
        POSTES_FILE.forEach(function (po) {
          var f = fileTriee(po.code);
          var dernier = C.sortBy(colFile().active().filter(function (t) {
            return t.poste === po.code && t.etat === 'servi';
          }), 'serviLe').reverse()[0];

          var carte = el('div.rounded-xl.border.border-slate-200.bg-white.p-5.shadow-sm');
          carte.appendChild(el('p.text-xs.font-semibold.uppercase.tracking-wide.text-slate-400', { text: po.label }));
          carte.appendChild(el('p.mt-2.text-xs.text-slate-500', { text: 'Numéro appelé' }));
          carte.appendChild(el('p.text-4xl.font-bold.tracking-tight.text-navy-900', {
            text: dernier ? dernier.numero : '—',
          }));
          carte.appendChild(el('p.mt-3.text-xs.text-slate-500', { text: 'Prochains numéros' }));
          carte.appendChild(el('p.text-lg.font-semibold.text-slate-700', {
            text: f.slice(0, 3).map(function (t) { return t.numero; }).join('   ·   ') || '—',
          }));
          carte.appendChild(el('p.mt-3.text-xs.text-slate-400', {
            text: f.length + ' patient(s) en attente',
          }));
          cartes.appendChild(carte);
        });
        vue.appendChild(cartes);
        vue.appendChild(el('p.text-center.text-xs.text-slate-400', {
          text: 'Actualisé automatiquement toutes les 15 secondes — dernière actualisation à '
            + C.heure(new Date().toISOString()),
        }));
        U.icons(vue);
      }
    },
  });


  /* ==========================================================================
   * PHASE 9 \u2014 AGENDA M\u00c9DECIN ET FILE PAR CABINET
   * --------------------------------------------------------------------------
   * Deux VUES des registres existants, jamais une seconde collection : le
   * m\u00e9decin lit SON agenda, le cabinet lit SA file. La doctrine des deux
   * listes (vague 35) tient : les patients qui attendent NOMM\u00c9MENT un
   * praticien et le vivier commun ne se fondent pas.
   * ======================================================================== */
  global.SIGH.screen('m2-agenda-medecin', {
    title: 'Agenda du m\u00e9decin',
    description: 'Les consultations d\u2019un praticien \u2014 pass\u00e9es, du jour et \u00e0 venir \u2014 lues depuis le registre.',
    regle: 'Une VUE du registre des consultations, filtr\u00e9e sur UN praticien : la donn\u00e9e n\u2019existe '
      + 'qu\u2019une fois. Un m\u00e9decin connect\u00e9 s\u2019ouvre sur son propre agenda.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var medecins = S.collection('personnel').active()
        .filter(function (a) { return a.fonction === 'medecin'; });
      var sess = S.session() || {};
      var moi = medecins.filter(function (a) { return a.nomComplet === (sess.nomComplet || sess.nom); })[0];

      var sel = el('select.select');
      medecins.forEach(function (a) {
        sel.appendChild(el('option', { value: a.nomComplet }, a.nomComplet + ' \u2014 ' + (a.poste || '')));
      });
      if (moi) sel.value = moi.nomComplet;
      var barre = el('div.card');
      barre.appendChild(el('div.card-body.max-w-xl', null,
        el('div', null, [el('label.label', { text: 'Praticien' }), sel])));
      host.appendChild(barre);
      var vue = el('div.space-y-4');
      host.appendChild(vue);
      sel.addEventListener('change', afficher);
      afficher();
      U.icons(host);
      return null;

      function afficher() {
        var nom = sel.value;
        var rows = S.collection('consultations').active()
          .filter(function (r) { return r.medecin === nom; });
        var aujourdHui = C.iso(new Date());
        var duJour = rows.filter(function (r) { return String(r.date || '').slice(0, 10) === aujourdHui; });
        var aVenir = rows.filter(function (r) {
          return String(r.date || '').slice(0, 10) > aujourdHui && r.statut === 'planifiee';
        });
        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Consultations au registre', value: C.num(rows.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'Aujourd\u2019hui', value: C.num(duJour.length), icon: 'calendar', tone: duJour.length ? 'warning' : 'neutral' },
          { label: 'Planifi\u00e9es \u00e0 venir', value: C.num(aVenir.length), icon: 'calendar-plus', tone: 'info' },
          { label: 'Terminees ce mois-ci', value: C.num(rows.filter(function (r) {
            return r.statut === 'terminee' && String(r.date || '').slice(0, 7) === aujourdHui.slice(0, 7);
          }).length), icon: 'check-circle-2', tone: 'success' },
        ]));
        vue.appendChild(U.dataTable({
          title: 'Agenda \u2014 ' + nom, rows: C.sortBy(rows, 'date').reverse(),
          pageSize: 12, exportName: 'agenda-medecin',
          emptyMessage: 'Aucune consultation au registre pour ce praticien.',
          columns: [
            { key: 'date', label: 'Date et heure', render: function (r) { return C.dateHeure(r.date); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' \u2014 ' + (r.patientCode || '\u2014'); } },
            { key: 'motif', label: 'Motif' },
            { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type || 'Consultation', r.type === 'Urgence' ? 'danger' : 'neutral'); } },
            { key: 'statut', label: '\u00c9tat', render: function (r) { return U.statut(r.statut); } },
          ],
        }));
        U.icons(vue);
      }
    },
  });

  global.SIGH.screen('m2-file-cabinet', {
    title: 'File par cabinet',
    description: 'Qui attend quel praticien \u2014 et le vivier commun, que personne ne doit perdre de vue.',
    regle: 'DEUX listes, jamais fondues (doctrine de la vague 35) : les patients qui attendent '
      + '<strong>nomm\u00e9ment</strong> un praticien, et le <strong>vivier commun</strong> \u2014 la file de '
      + 'consultation est souvent commune dans une clinique de cette taille, et n\u2019afficher que \u00ab ses \u00bb '
      + 'patients ferait manquer la charge du service. Le rang n\u2019est jamais saisi.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var tickets = S.collection('fileAttente').active()
        .filter(function (x) { return x.poste === 'consultation' && x.etat !== 'servi' && x.etat !== 'clos'; });
      var nommes = tickets.filter(function (x) { return x.praticien; });
      var vivier = tickets.filter(function (x) { return !x.praticien; });
      var parPraticien = {};
      nommes.forEach(function (x) { (parPraticien[x.praticien] = parPraticien[x.praticien] || []).push(x); });

      host.appendChild(U.kpiGrid([
        { label: 'En file de consultation', value: C.num(tickets.length), icon: 'list-ordered', tone: 'navy' },
        { label: 'Attendent un praticien nomm\u00e9', value: C.num(nommes.length), icon: 'user-check', tone: 'info' },
        { label: 'Vivier commun', value: C.num(vivier.length), icon: 'users', tone: vivier.length ? 'warning' : 'neutral',
          hint: 'Visibles de TOUS les cabinets' },
        { label: 'Cabinets sollicit\u00e9s', value: C.num(Object.keys(parPraticien).length), icon: 'door-open', tone: 'neutral' },
      ]));

      Object.keys(parPraticien).sort().forEach(function (nom) {
        host.appendChild(U.card('Cabinet \u2014 ' + nom + ' (' + parPraticien[nom].length + ')',
          K.miniTable(['Patient', 'Priorit\u00e9', 'Arriv\u00e9 \u00e0'],
            parPraticien[nom].map(function (x2) {
              return [x2.patient || x2.nom || '\u2014', x2.priorite || 'ordre d\u2019arriv\u00e9e',
                x2.arriveeLe ? C.dateHeure(x2.arriveeLe) : '\u2014'];
            }))));
      });

      host.appendChild(U.card('Vivier commun \u2014 par ordre d\u2019arriv\u00e9e, urgences en t\u00eate',
        vivier.length
          ? K.miniTable(['Patient', 'Priorit\u00e9', 'Arriv\u00e9 \u00e0'],
            vivier.map(function (x2) {
              return [x2.patient || x2.nom || '\u2014', x2.priorite || 'ordre d\u2019arriv\u00e9e',
                x2.arriveeLe ? C.dateHeure(x2.arriveeLe) : '\u2014'];
            }))
          : U.empty('Vivier vide \u2014 personne n\u2019attend sans praticien d\u00e9sign\u00e9.', { icon: 'users' })));
      U.icons(host);
      return null;
    },
  });

})(window);