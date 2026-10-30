/* =============================================================================
 * M4 — Maternité, Naissances & Décès
 * -----------------------------------------------------------------------------
 * CDCT §10.4 — suivi de maternité, enregistrement des accouchements, registre
 * des naissances et actes de décès (date, heure, cause).
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  function patients() { return S.collection('patients').active(); }
  function femmes() { return patients().filter(function (p) { return p.sexe === 'F'; }); }
  function sagesFemmes() {
    return S.collection('personnel').active()
      .filter(function (e) { return e.fonction === 'sage_femme' || e.fonction === 'medecin'; })
      .map(function (e) { return { value: e.nomComplet, label: e.nomComplet + ' — ' + e.poste }; });
  }
  function optionsFemmes() {
    return C.sortBy(femmes(), 'code').map(function (p) {
      return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
    });
  }
  function optionsPatients() {
    return C.sortBy(patients(), 'code').map(function (p) {
      return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
    });
  }
  function rattacher(v, source) {
    var p = (source || patients()).filter(function (x) { return x.code === v.patientCode; })[0];
    if (p) { v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom; }
    return v;
  }

  /* --------------------------------------------------------------------------
   * L'AMORÇAGE VIT AU SOCLE (data-seed.js, section maternité) depuis la
   * phase 4 : les statistiques du Pilotage et le tableau de bord de la
   * sage-femme lisent ces collections, et une collection amorcée par son
   * écran affiche un zéro FAUX partout ailleurs. `amorcer()` n'OUVRE plus
   * que les collections.
   * ------------------------------------------------------------------------ */
  function amorcer() {
    S.collection('accouchements', { module: 'M4', entite: 'Accouchement' });
    S.collection('naissances', { module: 'M4', entite: 'Naissance' });
    S.collection('suiviMaternite', { module: 'M4', entite: 'SuiviMaternite' });
    S.collection('deces', { module: 'M4', entite: 'Deces' });
  }

  /* --------------------------------------------------------------------------
   * ALERTES DE SÉCURITÉ CLINIQUE — §5.4 du rapport du 27/08/2026
   * --------------------------------------------------------------------------
   * PC hors 32–38 cm, PT hors 30–36 cm, Apgar à 5 min < 7. L'alerte reste
   * GÉNÉRIQUE — jamais de donnée médicale dans le message (doctrine du moteur
   * de notification) : le détail attend derrière les permissions de l'écran.
   * ------------------------------------------------------------------------ */
  function alertesNouveauNe(v) {
    var b = D.BORNES_NOUVEAU_NE || {};
    var motifs = [];
    if (v.pc != null && b.pc && (v.pc < b.pc.min || v.pc > b.pc.max)) motifs.push('PC');
    if (v.pt != null && b.pt && (v.pt < b.pt.min || v.pt > b.pt.max)) motifs.push('PT');
    if (v.apgar5 != null && b.apgarSeuil5min != null && v.apgar5 < b.apgarSeuil5min) motifs.push('Apgar');
    return motifs;
  }
  function signalerNouveauNe(v) {
    var motifs = alertesNouveauNe(v);
    if (!motifs.length) return;
    try {
      U.alerter('Une mesure néonatale sort des bornes de surveillance — ouvrir le dossier du nouveau-né.', {
        type: 'warning', son: 'alerte',
      });
    } catch (e) { /* le visuel du formulaire suffit */ }
  }

  function apgarTexte(r) {
    if (r.apgar1 == null && r.apgar5 == null && r.apgar != null) return r.apgar + '/10';
    return (r.apgar1 != null ? r.apgar1 : '—') + ' / '
      + (r.apgar5 != null ? r.apgar5 : '—') + ' / '
      + (r.apgar10 != null ? r.apgar10 : '—');
  }

  /* --------------------------------------------------------------------------
   * LE VOLET NOUVEAU-NÉ — un seul formulaire pour deux écrans
   * --------------------------------------------------------------------------
   * Le registre des naissances (état civil) et le dossier bébé (soins)
   * lisent la MÊME collection et saisissent par le MÊME formulaire : deux
   * formulaires auraient divergé au premier correctif. PC et PT sont
   * OBLIGATOIRES (Module C du rapport), l'Apgar se relève aux trois temps.
   * ------------------------------------------------------------------------ */
  function champsNaissance() {
    var b = D.BORNES_NOUVEAU_NE || { pc: {}, pt: {} };
    return [
      { name: 'mereCode', label: 'Dossier de la mère', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
      { name: 'dateHeure', label: 'Date et heure de naissance', type: 'datetime-local', required: true },
      { name: 'sexe', label: 'Sexe du nouveau-né', type: 'select', required: true, options: [{ value: 'M', label: 'Masculin' }, { value: 'F', label: 'Féminin' }] },
      { name: 'vivant', label: 'Né vivant', type: 'checkbox' },
      { type: 'section', label: 'Biométrie — PC et PT obligatoires (rapport du 27/08/2026)' },
      { name: 'poids', label: 'Poids (kg)', type: 'number', step: '0.01', required: true },
      { name: 'taille', label: 'Taille (cm)', type: 'number' },
      { name: 'pc', label: 'Périmètre crânien — PC (cm)', type: 'number', step: '0.1', required: true,
        help: 'Bornes physiologiques ' + b.pc.min + '–' + b.pc.max + ' cm : hors bornes, le dossier est signalé (micro/macrocéphalie).' },
      { name: 'pt', label: 'Périmètre thoracique — PT (cm)', type: 'number', step: '0.1', required: true,
        help: 'Bornes physiologiques ' + b.pt.min + '–' + b.pt.max + ' cm.' },
      { type: 'section', label: 'Apgar et réanimation' },
      { name: 'apgar1', label: 'Apgar à 1 min (/10)', type: 'number', min: 0, max: 10, required: true },
      { name: 'apgar5', label: 'Apgar à 5 min (/10)', type: 'number', min: 0, max: 10, required: true,
        help: 'Un Apgar à 5 min inférieur à 7 déclenche l’alerte de sécurité clinique.' },
      { name: 'apgar10', label: 'Apgar à 10 min (/10)', type: 'number', min: 0, max: 10 },
      { name: 'reanimation', label: 'Réanimation néonatale effectuée', type: 'checkbox',
        help: 'Se rattache à la fonction 7 SONU (réanimation du nouveau-né).' },
      { type: 'section', label: 'Soins essentiels et vaccins de naissance' },
      { name: 'vitK1', label: 'Vitamine K1 administrée', type: 'checkbox' },
      { name: 'collyre', label: 'Collyre tétracycline', type: 'checkbox' },
      { name: 'vpo0', label: 'Polio oral (VPO0)', type: 'checkbox' },
      { name: 'bcg', label: 'BCG', type: 'checkbox' },
      { name: 'hepB0', label: 'Hépatite B (J0)', type: 'checkbox' },
      { name: 'declare', label: 'Déclaré à l’état civil', type: 'checkbox' },
    ];
  }
  /* Certificat de repos post-partum — pièce officielle, en-tête unifié. */
  function certificatRepos(r) {
    P.etat({
      titre: 'CERTIFICAT DE REPOS',
      sousTitre: 'Post-partum — ' + r.reference,
      filigrane: 'Document officiel',
      cartouche: [['Patiente', r.patient], ['Dossier', r.patientCode],
        ['Accouchement du', C.dateHeure(r.dateHeure)], ['Type', r.type || r.voie],
        ['Praticien', r.sageFemme], ['Référence', r.reference]],
      contenu: el('div.space-y-3', null, [
        el('p', { text: 'Le praticien soussigné certifie avoir assisté l’accouchement de la patiente '
          + 'désignée ci-dessus et prescrit un repos post-partum conforme aux suites de couches.' }),
        el('p', { text: 'Un repos est prescrit à compter du ' + C.dateFR(r.dateHeure)
          + ', sauf complication nécessitant une réévaluation.' }),
        el('p.mt-3.text-\\[10px\\].italic', { text: 'Délivré pour servir et valoir ce que de droit.' }),
      ]),
      signatures: [{ role: 'La Sage-femme', nom: r.sageFemme, mention: 'Signature et cachet' },
        { role: 'Le Médecin' }],
    });
  }

  function transformNaissance(v, record) {
    var m = femmes().filter(function (x) { return x.code === v.mereCode; })[0];
    if (m) { v.mere = m.nom + ' ' + m.prenom; v.mereId = m.id; }
    if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('NAI-', 4, S.collection('naissances').all());
    /* La réanimation découle de l'Apgar quand personne ne l'a cochée : un
       Apgar bas sans réanimation tracée est précisément ce que le registre
       SONU doit voir. */
    signalerNouveauNe(v);
    return v;
  }

  /* ==========================================================================
   * SUIVI MATERNITÉ
   * ======================================================================== */
  global.SIGH.screen('m4-maternite', {
    title: 'Suivi maternité',
    description: 'Consultations prénatales, terme, date prévue d’accouchement et niveau de risque obstétrical.',
    render: function (root) {
      amorcer();
      return K.crud({
        collection: 'suiviMaternite', entite: 'suivi de grossesse', entiteP: 'suivis de grossesse', module: 'M4',
        defaultSort: 'dpa',
        columns: [
          {
            key: 'patient', label: 'Patiente',
            render: function (r) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
                el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
              ]);
            },
          },
          { key: 'termeSA', label: 'Terme (SA)', align: 'right', render: function (r) { return r.termeSA + ' SA'; } },
          { key: 'dpa', label: 'Date prévue', nowrap: true, text: function (r) { return C.dateFR(r.dpa); }, render: function (r) { return C.dateFR(r.dpa); } },
          {
            key: 'restant', label: 'Échéance', align: 'right',
            value: function (r) { return C.daysBetween(AUJ, r.dpa); },
            text: function (r) { return C.daysBetween(AUJ, r.dpa) + ' j'; },
            render: function (r) {
              var j = C.daysBetween(AUJ, r.dpa);
              if (j < 0) return U.badge('Terme dépassé', 'danger');
              if (j <= 14) return U.badge('Dans ' + j + ' j', 'warning');
              return el('span.text-sm.num.text-slate-600', { text: j + ' j' });
            },
          },
          { key: 'cpn', label: 'CPN réalisées', align: 'right' },
          { key: 'groupeSanguin', label: 'Groupe' },
          {
            key: 'risque', label: 'Risque',
            render: function (r) { return U.badge(r.risque, r.risque === 'Élevé' ? 'danger' : 'success'); },
          },
          { key: 'sageFemme', label: 'Sage-femme' },
          { key: 'observations', label: 'Observations' },
        ],
        fields: function () {
          return [
            { name: 'patientCode', label: 'Patiente', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
            { name: 'termeSA', label: 'Terme (semaines d’aménorrhée)', type: 'number', min: 1, max: 45, required: true },
            /* VERROUILLAGE du rapport (Module A) : pas d'admission sans ÂGE ni
               POIDS — posologies et statistiques sanitaires en dépendent. */
            { name: 'poids', label: 'Poids de la patiente (kg)', type: 'number', step: '0.1', required: true,
              help: 'Obligatoire — rapport du 27/08/2026 : l’admission se bloque sans le poids.' },
            { name: 'dpa', label: 'Date prévue d’accouchement', type: 'date', required: true },
            { name: 'cpn', label: 'Consultations prénatales réalisées', type: 'number', min: 0, max: 12 },
            { name: 'groupeSanguin', label: 'Groupe sanguin', type: 'select', options: D.GROUPES_SANGUINS },
            { name: 'risque', label: 'Niveau de risque', type: 'select', required: true, options: ['Standard', 'Élevé'] },
            { name: 'sageFemme', label: 'Sage-femme référente', type: 'select', options: sagesFemmes() },
            { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
          ];
        },
        transform: function (v, record) { return rattacher(v, femmes()); },
        beforeSave: function (v) {
          /* Le verrou du rapport (Module A) : l'âge est une donnée VITALE.
             Il vient du dossier patient — si la date de naissance y manque,
             l'admission se refuse en disant OÙ corriger. */
          var p = femmes().filter(function (x) { return x.code === v.patientCode; })[0];
          if (p && !p.dateNaissance) {
            return 'La date de naissance manque au dossier ' + p.code
              + ' : l’admission maternité exige l’âge (rapport du 27/08/2026). '
              + 'Compléter le dossier patient avant d’admettre.';
          }
          if (v.poids == null || v.poids === '') {
            return 'Le poids est obligatoire à l’admission (rapport du 27/08/2026).';
          }
          return null;
        },
        filters: [{ name: 'risque', label: 'Niveau de risque', options: ['Standard', 'Élevé'] }],
        kpis: function (rows) {
          return [
            { label: 'Grossesses suivies', value: C.num(rows.length), icon: 'baby', tone: 'navy' },
            { label: 'Accouchements sous 15 jours', value: C.num(rows.filter(function (r) { var j = C.daysBetween(AUJ, r.dpa); return j >= 0 && j <= 15; }).length), icon: 'calendar-clock', tone: 'warning' },
            { label: 'Grossesses à risque', value: C.num(rows.filter(function (r) { return r.risque === 'Élevé'; }).length), icon: 'heart-pulse', tone: 'danger' },
            { label: 'CPN moyennes', value: rows.length ? (C.sum(rows, 'cpn') / rows.length).toFixed(1) : '0', icon: 'clipboard-check', tone: 'success' },
          ];
        },
        etat: function (r) {
          P.etat({
            titre: 'Fiche de suivi de grossesse',
            cartouche: [['Patiente', r.patient], ['Dossier', r.patientCode], ['Terme', r.termeSA + ' SA'],
              ['Date prévue', C.dateFR(r.dpa)], ['Groupe sanguin', r.groupeSanguin], ['Risque', r.risque]],
            contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Consultations prénatales réalisées', v: String(r.cpn) },
              { k: 'Sage-femme référente', v: r.sageFemme },
              { k: 'Observations cliniques', v: r.observations },
              { k: 'Niveau de risque obstétrical', v: r.risque },
            ]),
            signatures: [{ role: 'La Sage-femme', nom: r.sageFemme }, { role: 'Le Médecin' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * ACCOUCHEMENTS
   * ======================================================================== */
  global.SIGH.screen('m4-accouchements', {
    title: 'Accouchements',
    description: 'Enregistrement des accouchements : voie, durée du travail, complications et issue.',
    render: function (root) {
      amorcer();
      return K.crud({
        collection: 'accouchements', entite: 'accouchement', entiteP: 'accouchements', module: 'M4',
        defaultSort: 'dateHeure', defaultDir: 'desc',
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          {
            key: 'dateHeure', label: 'Date et heure', nowrap: true,
            text: function (r) { return C.dateHeure(r.dateHeure); },
            render: function (r) { return C.dateHeure(r.dateHeure); },
            sortValue: function (r) { return C.toDate(r.dateHeure).getTime(); },
          },
          {
            key: 'patient', label: 'Parturiente',
            render: function (r) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
                el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
              ]);
            },
          },
          {
            key: 'type', label: 'Type',
            text: function (r) { return r.type || r.voie; },
            render: function (r) {
              var t = r.type || r.voie;
              return U.badge(t, t === 'Césarienne' || t === 'Dystocique' ? 'warning' : 'success');
            },
          },
          {
            key: 'actes', label: 'Actes associés',
            text: function (r) { return (r.actes || []).join(', ') || '—'; },
            render: function (r) {
              return (r.actes || []).length
                ? el('div.flex.flex-wrap.gap-1', null, r.actes.map(function (a) { return U.badge(a, 'info'); }))
                : el('span.text-xs.text-slate-400', { text: '—' });
            },
          },
          { key: 'duree', label: 'Durée du travail', align: 'right' },
          {
            key: 'complications', label: 'Complications',
            render: function (r) {
              return r.complications === 'Aucune'
                ? el('span.text-xs.text-slate-400', { text: 'Aucune' })
                : U.badge(r.complications, 'danger');
            },
          },
          { key: 'sageFemme', label: 'Praticien' },
          { key: 'issue', label: 'Issue', render: function (r) { return U.badge(r.issue, r.issue === 'Favorable' ? 'success' : 'danger'); } },
        ],
        fields: function () {
          return [
            { name: 'patientCode', label: 'Parturiente', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
            { name: 'dateHeure', label: 'Date et heure', type: 'datetime-local', required: true },
            { name: 'type', label: 'Type d’accouchement', type: 'select', required: true,
              options: D.TYPES_ACCOUCHEMENT || ['Eutocique', 'Dystocique'],
              help: 'Nomenclature de la cible : eutocique, dystocique, dirigé, gemellaire, trimellaire, césarienne.' },
            { name: 'actes', label: 'Actes associés', type: 'multiselect',
              options: D.ACTES_ACCOUCHEMENT || [],
              help: 'Épisiotomie, délivrance artificielle, révision utérine, AMIU, ventouse, GATPA.' },
            { name: 'duree', label: 'Durée du travail', placeholder: 'ex. 6 h' },
            { name: 'sageFemme', label: 'Praticien', type: 'select', required: true, options: sagesFemmes() },
            { name: 'complications', label: 'Complications', type: 'select', options: ['Aucune', 'Hémorragie de la délivrance', 'Souffrance fœtale', 'Dystocie', 'Éclampsie'] },
            { name: 'issue', label: 'Issue', type: 'select', required: true, options: ['Favorable', 'Défavorable'] },
            { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
          ];
        },
        transform: function (v, record) {
          rattacher(v, femmes());
          if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('ACC-', 4, S.collection('accouchements').all());
          v.voie = v.type === 'Césarienne' ? 'Césarienne' : 'Voie basse';
          return v;
        },
        onCreate: function () { return { type: 'Eutocique', voie: 'Voie basse', issue: 'Favorable', complications: 'Aucune' }; },
        filters: [
          { name: 'type', label: 'Type', options: (D.TYPES_ACCOUCHEMENT || []).slice(),
            match: function (r, v) { return (r.type || r.voie) === v; } },
          { name: 'issue', label: 'Issue', options: ['Favorable', 'Défavorable'] },
        ],
        /* LE CERTIFICAT DE REPOS post-partum s'édite depuis la fiche de
           l'accouchement — c'est lui qui le justifie (cible : m4-accouchements
           « inclut la génération du certificat de repos »). */
        detail: function (r) {
          return el('div.space-y-4', null, [
            K.grid([
              ['Référence', r.reference], ['Parturiente', r.patient + ' — ' + r.patientCode],
              ['Date et heure', C.dateHeure(r.dateHeure)], ['Type', r.type || r.voie],
              ['Actes associés', (r.actes || []).join(', ') || '—'],
              ['Durée du travail', r.duree || '—'], ['Complications', r.complications],
              ['Praticien', r.sageFemme], ['Issue', r.issue],
            ]),
            K.btn('Certificat de repos post-partum', {
              icon: 'file-badge',
              onclick: function () { certificatRepos(r); },
            }),
          ]);
        },
        kpis: function (rows) {
          var cesar = rows.filter(function (r) { return r.voie === 'Césarienne'; });
          return [
            { label: 'Accouchements', value: C.num(rows.length), icon: 'baby', tone: 'navy' },
            { label: 'Césariennes', value: C.num(cesar.length), icon: 'scissors', tone: 'warning', hint: C.pct(rows.length ? cesar.length / rows.length * 100 : 0) + ' des accouchements' },
            { label: 'Avec complications', value: C.num(rows.filter(function (r) { return r.complications !== 'Aucune'; }).length), icon: 'triangle-alert', tone: 'danger' },
            { label: 'Issues favorables', value: C.pct(rows.length ? rows.filter(function (r) { return r.issue === 'Favorable'; }).length / rows.length * 100 : 0), icon: 'heart', tone: 'success' },
          ];
        },
        etat: function (r) {
          P.etat({
            titre: 'Fiche d’accouchement',
            sousTitre: r.reference,
            cartouche: [['Parturiente', r.patient], ['Dossier', r.patientCode],
              ['Date et heure', C.dateHeure(r.dateHeure)], ['Voie', r.voie],
              ['Praticien', r.sageFemme], ['Issue', r.issue]],
            contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Durée du travail', v: r.duree || '—' },
              { k: 'Complications constatées', v: r.complications },
              { k: 'Observations', v: r.observations || '—' },
            ]),
            signatures: [{ role: 'La Sage-femme', nom: r.sageFemme }, { role: 'Le Médecin' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * REGISTRE DES NAISSANCES
   * ======================================================================== */
  global.SIGH.screen('m4-naissances', {
    title: 'Registre des naissances',
    description: 'Déclaration des naissances : sexe, poids, taille, score d’Apgar et suivi de la déclaration à l’état civil.',
    render: function (root) {
      amorcer();
      return K.crud({
        collection: 'naissances', entite: 'naissance', entiteP: 'naissances', module: 'M4',
        defaultSort: 'dateHeure', defaultDir: 'desc',
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          {
            key: 'dateHeure', label: 'Date et heure', nowrap: true,
            text: function (r) { return C.dateHeure(r.dateHeure); },
            render: function (r) { return C.dateHeure(r.dateHeure); },
            sortValue: function (r) { return C.toDate(r.dateHeure).getTime(); },
          },
          { key: 'mere', label: 'Mère' },
          { key: 'mereCode', label: 'Dossier mère', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.mereCode }); } },
          { key: 'sexe', label: 'Sexe', render: function (r) { return U.badge(r.sexe === 'M' ? 'Masculin' : 'Féminin', r.sexe === 'M' ? 'info' : 'navy'); } },
          { key: 'poids', label: 'Poids (kg)', align: 'right' },
          {
            key: 'apgar5', label: 'Apgar 1/5/10', align: 'right',
            text: function (r) { return apgarTexte(r); },
            render: function (r) {
              var seuil = (D.BORNES_NOUVEAU_NE || {}).apgarSeuil5min || 7;
              return el('span', {
                class: (r.apgar5 != null && r.apgar5 < seuil) ? 'font-semibold text-danger-600' : '',
                text: apgarTexte(r),
              });
            },
          },
          {
            key: 'pc', label: 'PC / PT (cm)', align: 'right',
            text: function (r) { return (r.pc || '—') + ' / ' + (r.pt || '—'); },
            render: function (r) {
              var horsBornes = alertesNouveauNe(r).length > 0;
              return el('span', { class: horsBornes ? 'font-semibold text-warning-700' : '',
                text: (r.pc || '—') + ' / ' + (r.pt || '—') });
            },
          },
          { key: 'vivant', label: 'État', text: function (r) { return r.vivant ? 'Né vivant' : 'Mort-né'; }, render: function (r) { return r.vivant ? U.badge('Né vivant', 'success') : U.badge('Mort-né', 'danger'); } },
          { key: 'declare', label: 'État civil', text: function (r) { return r.declare ? 'Déclarée' : 'À déclarer'; }, render: function (r) { return r.declare ? U.badge('Déclarée', 'success') : U.badge('À déclarer', 'warning'); } },
        ],
        fields: champsNaissance,
        transform: transformNaissance,
        onCreate: function () { return { vivant: true, declare: false, apgar1: 8, apgar5: 9, apgar10: 10, vitK1: true, collyre: true }; },
        filters: [
          { name: 'sexe', label: 'Sexe', options: [{ value: 'M', label: 'Masculin' }, { value: 'F', label: 'Féminin' }] },
          { name: 'declare', label: 'État civil', options: [{ value: 'true', label: 'Déclarées' }, { value: 'false', label: 'À déclarer' }], match: function (r, v) { return String(!!r.declare) === v; } },
        ],
        kpis: function (rows) {
          var g = rows.filter(function (r) { return r.sexe === 'M'; });
          return [
            { label: 'Naissances enregistrées', value: C.num(rows.length), icon: 'baby', tone: 'navy' },
            { label: 'Garçons / Filles', value: C.num(g.length) + ' / ' + C.num(rows.length - g.length), icon: 'users', tone: 'info' },
            { label: 'Poids moyen', value: rows.length ? (C.sum(rows, function (r) { return Number(r.poids); }) / rows.length).toFixed(2) + ' kg' : '—', icon: 'scale', tone: 'success' },
            { label: 'À déclarer à l’état civil', value: C.num(rows.filter(function (r) { return !r.declare; }).length), icon: 'file-clock', tone: 'warning' },
          ];
        },
        etat: function (r) {
          P.etat({
            titre: 'Attestation de naissance',
            sousTitre: 'Établie par la maternité — ' + r.reference,
            filigrane: 'Document officiel',
            cartouche: [['Référence', r.reference], ['Date et heure', C.dateHeure(r.dateHeure)],
              ['Mère', r.mere], ['Dossier mère', r.mereCode],
              ['Sexe', r.sexe === 'M' ? 'Masculin' : 'Féminin'], ['État', r.vivant ? 'Né vivant' : 'Mort-né']],
            contenu: el('div.space-y-3', null, [
              el('p', { text: 'La direction de la CLINIQUE NASSIERA TOO SARL atteste que l’enfant désigné ci-après est né dans ses services :' }),
              P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
                { k: 'Date et heure de naissance', v: C.dateHeure(r.dateHeure) },
                { k: 'Sexe', v: r.sexe === 'M' ? 'Masculin' : 'Féminin' },
                { k: 'Poids à la naissance', v: r.poids + ' kg' },
                { k: 'Taille', v: (r.taille || '—') + ' cm' },
                { k: 'Périmètre crânien (PC)', v: (r.pc || '—') + ' cm' },
                { k: 'Périmètre thoracique (PT)', v: (r.pt || '—') + ' cm' },
                { k: 'Score d’Apgar (1 / 5 / 10 min)', v: apgarTexte(r) },
                { k: 'Vitamine K1 / collyre', v: (r.vitK1 ? 'K1 administrée' : 'K1 non tracée') + ' · ' + (r.collyre ? 'collyre fait' : 'collyre non tracé') },
                { k: 'Vaccins de naissance', v: [r.vpo0 ? 'VPO0' : null, r.bcg ? 'BCG' : null, r.hepB0 ? 'Hép. B J0' : null].filter(Boolean).join(', ') || 'Aucun tracé' },
                { k: 'Nom de la mère', v: r.mere },
              ]),
              el('p.mt-3.text-\\[10px\\].italic', { text: 'La présente attestation est délivrée pour servir et valoir ce que de droit, en vue de la déclaration à l’état civil.' }),
            ]),
            signatures: [{ role: 'La Sage-femme' }, { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * REGISTRE DES DÉCÈS
   * ======================================================================== */
  global.SIGH.screen('m4-deces', {
    title: 'Registre des décès',
    description: 'Enregistrement des décès survenus dans l’établissement : date, heure, cause et déclaration.',
    render: function (root) {
      amorcer();
      return K.crud({
        collection: 'deces', entite: 'décès', entiteP: 'décès', module: 'M4',
        defaultSort: 'dateHeure', defaultDir: 'desc',
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          {
            key: 'dateHeure', label: 'Date et heure', nowrap: true,
            text: function (r) { return C.dateHeure(r.dateHeure); },
            render: function (r) { return C.dateHeure(r.dateHeure); },
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
          { key: 'cause', label: 'Cause du décès' },
          { key: 'lieu', label: 'Lieu' },
          { key: 'medecin', label: 'Médecin constatant' },
          { key: 'declare', label: 'Déclaration', text: function (r) { return r.declare ? 'Déclaré' : 'À déclarer'; }, render: function (r) { return r.declare ? U.badge('Déclaré', 'success') : U.badge('À déclarer', 'warning'); } },
        ],
        fields: function () {
          return [
            { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients(), col: 'full' },
            { name: 'dateHeure', label: 'Date et heure du décès', type: 'datetime-local', required: true },
            { name: 'cause', label: 'Cause du décès', required: true, col: 'full' },
            { name: 'lieu', label: 'Lieu', type: 'select', options: ['Hospitalisation', 'Urgences', 'Bloc opératoire', 'Maternité', 'Domicile'] },
            { name: 'medecin', label: 'Médecin constatant', type: 'select', required: true, options: sagesFemmes() },
            { name: 'declare', label: 'Déclaré à l’état civil', type: 'checkbox' },
            { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
          ];
        },
        transform: function (v, record) { rattacher(v); if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('DEC-', 4, S.collection('deces').all()); return v; },
        filters: [{ name: 'lieu', label: 'Lieu', options: ['Hospitalisation', 'Urgences', 'Bloc opératoire', 'Maternité', 'Domicile'] }],
        kpis: function (rows) {
          var annee = rows.filter(function (r) { return C.toDate(r.dateHeure).getFullYear() === 2026; });
          return [
            { label: 'Décès enregistrés', value: C.num(rows.length), icon: 'file-text', tone: 'neutral' },
            { label: 'Sur l’année 2026', value: C.num(annee.length), icon: 'calendar', tone: 'navy' },
            { label: 'À déclarer', value: C.num(rows.filter(function (r) { return !r.declare; }).length), icon: 'file-clock', tone: 'warning' },
            { label: 'Causes distinctes', value: C.num(Object.keys(C.groupBy(rows, 'cause')).length), icon: 'list', tone: 'info' },
          ];
        },
        etat: function (r) {
          P.etat({
            titre: 'Déclaration de décès',
            sousTitre: r.reference,
            filigrane: 'Document officiel',
            cartouche: [['Patient', r.patient], ['Dossier', r.patientCode],
              ['Date et heure', C.dateHeure(r.dateHeure)], ['Lieu', r.lieu || '—'],
              ['Médecin constatant', r.medecin], ['Référence', r.reference]],
            contenu: el('div.space-y-3', null, [
              el('p', { text: 'Le médecin soussigné certifie avoir constaté le décès de la personne désignée ci-dessus.' }),
              P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
                { k: 'Date et heure du décès', v: C.dateHeure(r.dateHeure) },
                { k: 'Lieu du décès', v: r.lieu || '—' },
                { k: 'Cause du décès', v: r.cause },
                { k: 'Observations', v: r.observations || '—' },
              ]),
            ]),
            signatures: [{ role: 'Le Médecin constatant', nom: r.medecin, mention: 'Signature et cachet' },
              { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * COMPTES RENDUS DE MATERNITÉ — ACCOUCHEMENT, PLANNING FAMILIAL, AMIU
   * --------------------------------------------------------------------------
   * TROIS pièces aux rubriques propres, et non un gabarit unique : un compte
   * rendu d'accouchement demande le terme, l'Apgar et le poids de l'enfant ;
   * un compte rendu de planning familial demande la méthode et le geste. Un
   * formulaire commun aurait fait remplir à la sage-femme des champs sans
   * objet, ce qui est le plus sûr moyen de la faire écrire n'importe quoi.
   *
   * Le rendu de chaque pièce est ENGENDRÉ depuis sa déclaration
   * (D.COMPTES_RENDUS_MATERNITE) : ajouter une pièce demain n'exigera pas
   * d'écrire un troisième écran.
   * ======================================================================== */
  function colCrMaternite() {
    return S.collection('crMaternite', { module: 'M4', entite: 'compte rendu de maternité', prefix: 'CRM' });
  }
  function colSoignants4() {
    return S.collection('soignants', { module: 'M14', entite: 'soignant', prefix: 'SOI' });
  }
  function optionsSoignants4(filtre) {
    return colSoignants4().active().filter(filtre || function () { return true; })
      .map(function (x) { return { value: x.id, label: x.nomComplet + ' — ' + x.poste }; });
  }
  function nomSoignant4(id) {
    var x = colSoignants4().active().filter(function (y) { return y.id === id; })[0];
    return x ? x.nomComplet : '—';
  }

  global.SIGH.screen('m4-comptes-rendus', {
    title: 'Comptes rendus de maternité',
    description: 'Comptes rendus d’accouchement, de planning familial et d’AMIU.',
    regle: 'Trois pièces distinctes, aux rubriques propres. Les actes de <strong>planification familiale</strong> '
      + 'sont tous <strong>non couverts</strong> par les assurances — la grille gynéco-obstétricale le porte en '
      + 'toutes lettres, et la facture le dit au guichet.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function modeles() { return D.COMPTES_RENDUS_MATERNITE || []; }
      function modele(code) {
        return modeles().filter(function (m) { return m.code === code; })[0] || null;
      }

      /* Le formulaire d'une pièce, engendré depuis sa déclaration. */
      function champsDe(m) {
        return [
          { name: 'patientCode', label: 'Patiente', type: 'select', required: true, options: optionsPatientes() },
          { name: 'sageFemmeId', label: 'Sage-femme ou médecin', type: 'select', required: true,
            options: optionsSoignants4(function (x) { return x.prescrit || x.execute; }) },
          { type: 'section', label: m.label },
        ].concat(m.rubriques.map(function (r) {
          var base = { name: r[0], label: r[1], required: !!r[3] };
          if (r[2] === 'liste') return Object.assign(base, { type: 'select',
            options: (r[4] || []).map(function (v) { return { value: v, label: v }; }) });
          if (r[2] === 'binaire') return Object.assign(base, { type: 'checkbox' });
          if (r[2] === 'zone') return Object.assign(base, { type: 'textarea', rows: 3 });
          if (r[2] === 'nombre') return Object.assign(base, { type: 'number' });
          if (r[2] === 'date') return Object.assign(base, { type: 'date' });
          if (r[2] === 'datetime') return Object.assign(base, { type: 'datetime-local' });
          if (r[2] === 'soignant') return Object.assign(base, { type: 'select', options: optionsSoignants4() });
          return Object.assign(base, { type: 'text' });
        }));
      }

      function optionsPatientes() {
        return C.sortBy(S.collection('patients').active().filter(function (p2) {
          return p2.sexe === 'F';
        }), 'code').map(function (p2) {
          return { value: p2.code, label: p2.code + ' — ' + p2.nom + ' ' + p2.prenom };
        });
      }

      function afficher() {
        var rows = colCrMaternite().active();
        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Comptes rendus', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
        ].concat(modeles().map(function (m) {
          return {
            label: m.label.replace('Compte rendu ', ''),
            value: C.num(rows.filter(function (r) { return r.typeCr === m.code; }).length),
            icon: m.icone, tone: 'info',
          };
        }))));

        vue.appendChild(K.note('Les actes de <strong>planification familiale</strong> — pose et retrait d’implant, '
          + 'de DIU, injectables — sont <strong>NON COUVERTS</strong> par les assurances selon la grille '
          + 'gynéco-obstétricale de la clinique. La patiente assurée les règle au tarif non assuré, et la facture '
          + 'en porte le motif.', { tone: 'warning', icon: 'shield-off' }));

        vue.appendChild(U.tabs(modeles().map(function (m) {
          var sous = rows.filter(function (r) { return r.typeCr === m.code; });
          return {
            id: m.code, label: m.label.replace('Compte rendu ', ''), badge: sous.length,
            render: function () { return tableau(m, sous); },
          };
        })));
        U.icons(vue);
      }

      function tableau(m, rows) {
        return el('div.space-y-3', null,
          m.note ? K.note(m.note, { tone: 'info', icon: 'info' }) : null,
          U.dataTable({
            rows: C.sortBy(rows, 'creeLe').reverse(),
            empty: 'Aucun ' + m.label.toLowerCase() + ' enregistré.',
            actions: [K.creer(colCrMaternite(), champsDe(m), {
              module: 'M4', label: 'Nouveau — ' + m.label.replace('Compte rendu ', ''),
              titre: m.label, entite: 'Compte rendu', size: 'lg', apres: afficher,
              transform: function (v, record) {
                var pt = S.collection('patients').active().filter(function (x) {
                  return x.code === v.patientCode;
                })[0];
                return Object.assign({}, v, {
                  reference: C.referenceSuivante('CRM-', 4, colCrMaternite().all()), typeCr: m.code, typeLabel: m.label,
                  patientId: pt ? pt.id : null,
                  patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                  sageFemme: nomSoignant4(v.sageFemmeId),
                  creeLe: new Date().toISOString(),
                });
              },
            })].filter(Boolean),
            columns: [
              { key: 'reference', label: 'Référence' },
              { key: 'creeLe', label: 'Enregistré le', render: function (r) { return C.dateHeure(r.creeLe); } },
              { key: 'patient', label: 'Patiente', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
              { key: 'sageFemme', label: 'Rédigé par' },
            ],
            rowActions: K.actionsLigne(colCrMaternite(), champsDe(m), {
              module: 'M4', refresh: afficher,
              titre: function (r) { return r.reference; },
              detail: function (r) { return detail(m, r); },
            }),
          }));
      }

      function detail(m, r) {
        return el('div.space-y-4', null,
          K.grid([
            ['Référence', r.reference], ['Type', r.typeLabel],
            ['Patiente', r.patient + ' — ' + r.patientCode],
            ['Rédigé par', r.sageFemme], ['Enregistré le', C.dateHeure(r.creeLe)],
          ]),
          K.section(m.label,
            K.miniTable(['Rubrique', 'Valeur'], m.rubriques.map(function (rb) {
              var v = r[rb[0]];
              if (rb[2] === 'binaire') v = v ? 'Oui' : 'Non';
              if (rb[2] === 'soignant') v = nomSoignant4(v);
              if (rb[2] === 'date' && v) v = C.dateFR(v);
              return [rb[1], v == null || v === '' ? '—' : String(v)];
            }))));
      }
    },
  });

  /* ==========================================================================
   * CPN — SUIVI DE GROSSESSE & CARTE MATERNELLE (rapport 27/08/2026, Module B)
   * ======================================================================== */
  function colGrossesses() {
    return S.collection('grossesses', { module: 'M4', entite: 'grossesse', prefix: 'GRO' });
  }
  global.SIGH.screen('m4-cpn', {
    title: 'CPN & carte maternelle',
    description: 'Consultations prénatales structurées : SP1-SP5, MILDA, grossesse à risque, Mébendazole, visites CPN.',
    regle: 'La carte maternelle porte les <strong>quatre variables nouvelles du rapport du 27/08/2026</strong> : '
      + 'doses <strong>SP1 à SP5</strong> (TPI paludisme), <strong>MILDA</strong> remise, <strong>GAR</strong> '
      + '(grossesse à risque, badge d’alerte) et <strong>Mébendazole</strong> (déparasitage dès le 2ᵉ trimestre). '
      + 'Un âge &lt; 18 ans ou &gt; 35 ans est un facteur de risque CPN — le formulaire le signale.',
    render: K.crud({
      collection: 'grossesses', entite: 'grossesse suivie', entiteP: 'grossesses suivies', module: 'M4',
      defaultSort: 'dpa', formSize: 'lg',
      source: 'Rapport officiel maternité du 27/08/2026 — Module B et tableau 8 (CPN 1 à 8, OMS).',
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
        {
          key: 'patient', label: 'Patiente',
          render: function (r) {
            return el('div.min-w-0', null, [
              el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
              el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
            ]);
          },
        },
        { key: 'termeSA', label: 'Terme', align: 'right', render: function (r) { return (r.termeSA || '—') + ' SA'; } },
        { key: 'dpa', label: 'DPA', nowrap: true, text: function (r) { return C.dateFR(r.dpa); }, render: function (r) { return C.dateFR(r.dpa); } },
        {
          key: 'gar', label: 'GAR',
          text: function (r) { return r.gar ? 'À risque' : '—'; },
          render: function (r) { return r.gar ? U.badge('GROSSESSE À RISQUE', 'danger') : el('span.text-xs.text-slate-400', { text: '—' }); },
        },
        {
          key: 'sp', label: 'SP (TPI)',
          text: function (r) { return (r.sp || []).join(' '); },
          render: function (r) {
            return (r.sp || []).length
              ? el('div.flex.flex-wrap.gap-1', null, r.sp.map(function (s2) { return U.badge(s2, 'info'); }))
              : el('span.text-xs.text-slate-400', { text: 'Aucune dose' });
          },
        },
        { key: 'milda', label: 'MILDA', text: function (r) { return r.milda ? 'Remise' : 'Non'; }, render: function (r) { return r.milda ? U.badge('Remise', 'success') : U.badge('Non remise', 'warning'); } },
        { key: 'mebendazole', label: 'Mébendazole', text: function (r) { return r.mebendazole ? 'Fait' : '—'; }, render: function (r) { return r.mebendazole ? U.badge('Fait', 'success') : el('span.text-xs.text-slate-400', { text: '—' }); } },
        { key: 'visites', label: 'CPN', align: 'right', value: function (r) { return (r.visites || []).length; }, render: function (r) { return String((r.visites || []).length); } },
        { key: 'sageFemme', label: 'Sage-femme' },
      ],
      fields: function () {
        return [
          { name: 'patientCode', label: 'Patiente', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
          { name: 'ddr', label: 'Date des dernières règles (DDR)', type: 'date', required: true },
          { name: 'dpa', label: 'Date prévue d’accouchement (DPA)', type: 'date', required: true,
            help: 'Calculée depuis la DDR (≈ 40 SA) — corrigée par l’échographie de datation le cas échéant.' },
          { name: 'termeSA', label: 'Terme actuel (SA)', type: 'number', min: 1, max: 45, required: true },
          { name: 'groupeSanguin', label: 'Groupe sanguin / Rhésus', type: 'select', options: D.GROUPES_SANGUINS },
          { name: 'sageFemme', label: 'Sage-femme référente', type: 'select', required: true, options: sagesFemmes() },
          { type: 'section', label: 'Variables du rapport du 27/08/2026' },
          { name: 'sp', label: 'Doses SP administrées (TPI paludisme)', type: 'multiselect', options: D.DOSES_SP || [] },
          { name: 'milda', label: 'MILDA remise', type: 'checkbox' },
          { name: 'gar', label: 'Grossesse à risque (GAR)', type: 'checkbox',
            help: 'Déclenche le badge d’alerte rouge sur la fiche et compte à l’indicateur DHIS2.' },
          { name: 'mebendazole', label: 'Mébendazole (déparasitage, dès le 2ᵉ trimestre)', type: 'checkbox' },
          { type: 'section', label: 'Prévention' },
          { name: 'vat', label: 'Vaccination antitétanique', type: 'select', options: ['VAT1', 'VAT2', 'VAT3', 'VAT4', 'VAT5'] },
          { name: 'fer', label: 'Fer prescrit', type: 'checkbox' },
          { name: 'folates', label: 'Acide folique prescrit', type: 'checkbox' },
        ];
      },
      transform: function (v, record) {
        rattacher(v, femmes());
        if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('CPN-', 4, S.collection('grossesses').all());
        /* Facteur de risque CPN du rapport : âge < 18 ou > 35. On SIGNALE, on
           ne coche pas GAR à la place de la sage-femme. */
        var p = femmes().filter(function (x) { return x.code === v.patientCode; })[0];
        if (p && p.dateNaissance) {
          var age2 = Math.floor(C.daysBetween(p.dateNaissance, new Date()) / 365.25);
          var b = D.AGES_RISQUE_CPN || { min: 18, max: 35 };
          if ((age2 < b.min || age2 > b.max) && !v.gar) {
            try {
              U.alerter('Âge maternel hors de la fenêtre ' + b.min + '–' + b.max
                + ' ans : facteur de risque CPN à évaluer (rapport du 27/08/2026).', { type: 'warning' });
            } catch (e) { /* silencieux */ }
          }
        }
        return v;
      },
      filters: [
        { name: 'gar', label: 'Risque', options: [{ value: 'oui', label: 'Grossesses à risque' }, { value: 'non', label: 'Sans risque identifié' }],
          match: function (r, v) { return v === 'oui' ? !!r.gar : !r.gar; } },
        { name: 'milda', label: 'MILDA', options: [{ value: 'oui', label: 'Remise' }, { value: 'non', label: 'Non remise' }],
          match: function (r, v) { return v === 'oui' ? !!r.milda : !r.milda; } },
      ],
      kpis: function (rows) {
        var sp3 = rows.filter(function (r) { return (r.sp || []).indexOf('SP3') !== -1; });
        return [
          { label: 'Grossesses suivies', value: C.num(rows.length), icon: 'baby', tone: 'navy' },
          { label: 'À risque (GAR)', value: C.num(rows.filter(function (r) { return r.gar; }).length), icon: 'triangle-alert', tone: 'danger' },
          { label: 'Couverture SP3', value: C.pct(rows.length ? sp3.length / rows.length * 100 : 0), icon: 'shield-check', tone: 'info', hint: 'Indicateur DHIS2' },
          { label: 'MILDA remises', value: C.pct(rows.length ? rows.filter(function (r) { return r.milda; }).length / rows.length * 100 : 0), icon: 'tent', tone: 'success' },
        ];
      },
      detail: function (r, aides) {
        return el('div.space-y-4', null, [
          r.gar ? K.note('<strong>GROSSESSE À RISQUE</strong> — le rapport demande un badge visuel '
            + 'd’alerte sur le dossier. Surveillance rapprochée.', { tone: 'danger', icon: 'triangle-alert' }) : null,
          K.grid([
            ['Référence', r.reference], ['Patiente', r.patient + ' — ' + r.patientCode],
            ['DDR', C.dateFR(r.ddr)], ['DPA', C.dateFR(r.dpa)],
            ['Terme', (r.termeSA || '—') + ' SA'], ['Groupe sanguin', r.groupeSanguin || '—'],
            ['Doses SP', (r.sp || []).join(', ') || 'Aucune'],
            ['MILDA', r.milda ? 'Remise' : 'Non remise'],
            ['Mébendazole', r.mebendazole ? 'Administré' : 'Non'],
            ['VAT', r.vat || '—'], ['Fer / folates', (r.fer ? 'Fer' : '—') + ' / ' + (r.folates ? 'folates' : '—')],
            ['Sage-femme', r.sageFemme],
          ]),
          /* K.section(titre, SOUS-TITRE TEXTE) n'accepte PAS d'enfant : lui
             passer un nœud l'avale en silence — la grille ne se rendait
             jamais, et seule la SONDE l'a vu. Le titre et son contenu se
             posent donc côte à côte. */
          el('div', null, [
            K.section('Visites CPN — la grille du formulaire national'),
            (r.visites || []).length
              ? K.miniTable(['CPN', 'Date', 'TA', 'Poids (kg)', 'HU (cm)', 'BDCF', 'Albumine', 'Sucre'],
                (r.visites || []).map(function (vi) {
                  return ['CPN ' + vi.n, C.dateFR(vi.date), vi.ta, String(vi.poids), String(vi.hu), String(vi.bdcf), vi.albumine, vi.sucre];
                }))
              : U.empty('Aucune visite CPN enregistrée.', { icon: 'clipboard' }),
          ]),
          K.commande('Ajouter une visite CPN', {
            variant: 'primary', icon: 'plus',
            onclick: function () {
              var fV = U.form([
                { name: 'date', label: 'Date de la visite', type: 'date', required: true },
                { name: 'ta', label: 'TA', placeholder: '12/8', required: true },
                { name: 'poids', label: 'Poids (kg)', type: 'number', step: '0.1', required: true },
                { name: 'hu', label: 'Hauteur utérine (cm)', type: 'number' },
                { name: 'bdcf', label: 'BDCF (bpm)', type: 'number' },
                { name: 'albumine', label: 'Albumine urinaire', type: 'select', options: ['—', '+', '++'] },
                { name: 'sucre', label: 'Sucre urinaire', type: 'select', options: ['—', '+', '++'] },
              ], {});
              var mV = U.modal({
                title: 'Visite CPN ' + ((r.visites || []).length + 1) + ' — ' + r.patient,
                body: fV,
                footer: [
                  K.btn('Annuler', { onclick: function () { mV.close(); } }),
                  K.btn('Enregistrer la visite', {
                    variant: 'primary', icon: 'check',
                    onclick: function () {
                      var vv = fV.collect();
                      if (!vv) return;
                      var visites = (r.visites || []).concat([Object.assign({ n: (r.visites || []).length + 1 }, vv)]);
                      colGrossesses().update(r.id, { visites: visites });
                      mV.close();
                      if (aides && aides.refresh) aides.refresh();
                      U.toast('Visite CPN enregistrée.', { type: 'success' });
                    },
                  }),
                ],
              });
            },
          }),
        ]);
      },
      etat: function (r) {
        P.etat({
          titre: 'Carte maternelle — suivi CPN',
          sousTitre: r.reference,
          cartouche: [['Patiente', r.patient], ['Dossier', r.patientCode],
            ['DDR', C.dateFR(r.ddr)], ['DPA', C.dateFR(r.dpa)],
            ['Groupe sanguin', r.groupeSanguin || '—'], ['Sage-femme', r.sageFemme]],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Valeur', key: 'v' }], [
              { k: 'Doses SP (TPI paludisme)', v: (r.sp || []).join(', ') || 'Aucune' },
              { k: 'MILDA remise', v: r.milda ? 'Oui' : 'Non' },
              { k: 'Grossesse à risque (GAR)', v: r.gar ? 'OUI' : 'Non' },
              { k: 'Mébendazole', v: r.mebendazole ? 'Oui' : 'Non' },
              { k: 'VAT', v: r.vat || '—' },
            ]),
            P.tableau([
              { label: 'CPN', value: function (vi) { return 'CPN ' + vi.n; } },
              { label: 'Date', value: function (vi) { return C.dateFR(vi.date); } },
              { label: 'TA', key: 'ta' },
              { label: 'Poids (kg)', key: 'poids', align: 'right' },
              { label: 'HU (cm)', key: 'hu', align: 'right' },
              { label: 'BDCF', key: 'bdcf', align: 'right' },
            ], r.visites || []),
          ]),
          signatures: [{ role: 'La Sage-femme', nom: r.sageFemme }],
        });
      },
    }),
  });

  /* ==========================================================================
   * PARTOGRAMME — la PARTOGRAPHIE nationale, dynamique
   * --------------------------------------------------------------------------
   * La ligne d'ALERTE part de 4 cm et monte de 1 cm/h ; la ligne d'ACTION lui
   * est parallèle, décalée de 4 h. Une mesure qui franchit la ligne d'action
   * est SIGNALÉE — le partogramme est un instrument de décision, pas un
   * simple relevé.
   * ======================================================================== */
  function colPartogrammes() {
    return S.collection('partogrammes', { module: 'M4', entite: 'partogramme', prefix: 'PAR' });
  }
  global.SIGH.screen('m4-partogramme', {
    title: 'Partogramme',
    description: 'Suivi dynamique du travail : dilatation, lignes d’alerte et d’action, BDF, contractions.',
    regle: 'Modèle de la <strong>PARTOGRAPHIE nationale</strong> (formulaire scanné) : ligne d’alerte de '
      + '4 cm à 1 cm/h, ligne d’action décalée de <strong>4 heures</strong>. Une dilatation qui franchit '
      + 'la ligne d’action appelle une DÉCISION (codes actions 1 à 7 du formulaire) — le graphique la '
      + 'signale, il ne la prend pas.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      var courant = null;
      afficher();
      return null;

      function param() { return D.PARTOGRAMME || { alerteDepart: 4, alerteParHeure: 1, actionDecalageHeures: 4 }; }

      function franchitAction(r) {
        var p2 = param();
        return (r.mesures || []).some(function (m2) {
          var attendu = p2.alerteDepart + Math.max(0, m2.heure - p2.actionDecalageHeures) * p2.alerteParHeure;
          return m2.heure >= p2.actionDecalageHeures && m2.dilatation < attendu;
        });
      }

      function afficher() {
        var rows = colPartogrammes().active();
        courant = courant || rows[0];
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Partogrammes', value: C.num(rows.length), icon: 'activity', tone: 'navy' },
          { label: 'Travaux en cours', value: C.num(rows.filter(function (r) { return !r.clos; }).length), icon: 'timer', tone: 'warning' },
          { label: 'Ligne d’action franchie', value: C.num(rows.filter(franchitAction).length), icon: 'triangle-alert', tone: 'danger' },
          { label: 'Dilatations complètes', value: C.num(rows.filter(function (r) { return r.clos; }).length), icon: 'check-check', tone: 'success' },
        ]));

        var barre = el('div.card');
        var corps = el('div.card-body.flex.flex-wrap.items-end.gap-3');
        var sel = U.combo(rows.map(function (r) {
          return { value: r.id, label: r.patient, detail: r.reference + ' — début ' + C.dateHeure(r.debut) };
        }), { value: courant ? courant.id : '', placeholder: 'Choisir un travail' });
        sel.classList.add('max-w-md');
        sel.addEventListener('change', function () {
          courant = rows.filter(function (r) { return r.id === sel.value; })[0] || courant;
          afficher();
        });
        corps.appendChild(el('div.flex-1', null, [el('label.label', { text: 'Travail suivi' }), sel]));
        corps.appendChild(K.commande('Ouvrir un partogramme', {
          variant: 'primary', icon: 'plus', onclick: ouvrirNouveau,
        }));
        corps.appendChild(K.commande('Ajouter une mesure', {
          icon: 'activity', onclick: function () { if (courant) ajouterMesure(courant); },
        }));
        if (courant) corps.appendChild(K.btn('Imprimer', { icon: 'printer', onclick: function () { imprimer(courant); } }));
        barre.appendChild(corps);
        vue.appendChild(barre);

        if (!courant) {
          vue.appendChild(U.empty('Aucun partogramme ouvert.', { icon: 'activity' }));
          U.icons(vue); return;
        }

        if (franchitAction(courant)) {
          vue.appendChild(K.note('<strong>La ligne d’ACTION est franchie</strong> : la dilatation est en '
            + 'retard de plus de ' + param().actionDecalageHeures + ' heures sur la ligne d’alerte. Le '
            + 'formulaire national appelle une décision — codes 1 à 7 : '
            + (param().actions || []).join(', ') + '.', { tone: 'danger', icon: 'siren' }));
        }

        vue.appendChild(U.card('Dilatation cervicale — ' + courant.patient + ' (' + courant.reference + ')',
          graphe(courant)));

        vue.appendChild(U.card('Mesures horaires', K.miniTable(
          ['Heure (h)', 'Dilatation (cm)', 'Descente (/5)', 'BDF (bpm)', 'CU / 10 min', 'TA', 'Pouls', 'Liquide'],
          (courant.mesures || []).map(function (m2) {
            return [String(m2.heure), String(m2.dilatation), String(m2.descente),
              String(m2.bdf), String(m2.contractions), m2.ta, String(m2.pouls), m2.liquide];
          }))));
        U.icons(vue);
      }

      function graphe(r) {
        var p2 = param();
        var maxH = Math.max(12, (r.mesures || []).reduce(function (t, m2) { return Math.max(t, m2.heure); }, 0));
        var labels = [], alerte = [], action = [], dil = [];
        for (var h = 0; h <= maxH; h++) {
          labels.push(h + ' h');
          alerte.push(Math.min(10, p2.alerteDepart + h * p2.alerteParHeure));
          action.push(h < p2.actionDecalageHeures ? null
            : Math.min(10, p2.alerteDepart + (h - p2.actionDecalageHeures) * p2.alerteParHeure));
          var m3 = (r.mesures || []).filter(function (x) { return x.heure === h; })[0];
          dil.push(m3 ? m3.dilatation : null);
        }
        return G.ligne(labels, [
          { label: 'Dilatation', data: dil, fill: false, color: '#1e3a5f' },
          { label: 'Ligne d’alerte', data: alerte, fill: false, color: '#b45309' },
          { label: 'Ligne d’action', data: action, fill: false, color: '#b3261e' },
        ], { height: 300 });
      }

      function ouvrirNouveau() {
        var f2 = U.form([
          { name: 'patientCode', label: 'Parturiente', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
          { name: 'debut', label: 'Début du suivi (dilatation ≥ 4 cm)', type: 'datetime-local', required: true },
          { name: 'gestite', label: 'Gestité', type: 'number', min: 1 },
          { name: 'parite', label: 'Parité', type: 'number', min: 0 },
          { name: 'accoucheur', label: 'Accoucheur', type: 'select', required: true, options: sagesFemmes() },
        ], {});
        var m2 = U.modal({
          title: 'Ouvrir un partogramme', body: f2,
          footer: [
            K.btn('Annuler', { onclick: function () { m2.close(); } }),
            K.btn('Ouvrir', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f2.collect(); if (!v) return;
                rattacher(v, femmes());
                v.reference = C.referenceSuivante('PARTO-', 4, S.collection('partogrammes').all());
                v.debut = new Date(v.debut).toISOString();
                v.mesures = []; v.clos = false;
                var res = colPartogrammes().insert(v);
                courant = res.record;
                m2.close(); afficher();
                U.toast('Partogramme ouvert.', { type: 'success', undo: function () { res.undo(); courant = null; afficher(); } });
              },
            }),
          ],
        });
      }

      function ajouterMesure(r) {
        var prochaine = (r.mesures || []).length
          ? r.mesures[r.mesures.length - 1].heure + 1 : 0;
        var f3 = U.form([
          { name: 'heure', label: 'Heure depuis le début (h)', type: 'number', min: 0, max: 24, required: true, value: prochaine },
          { name: 'dilatation', label: 'Dilatation cervicale (cm)', type: 'number', min: 0, max: 10, required: true },
          { name: 'descente', label: 'Descente de la présentation (/5)', type: 'number', min: 0, max: 5 },
          { name: 'bdf', label: 'BDF (battements/min)', type: 'number', min: 60, max: 220, required: true },
          { name: 'contractions', label: 'Contractions / 10 min', type: 'number', min: 0, max: 5 },
          { name: 'ta', label: 'TA maternelle', placeholder: '12/8' },
          { name: 'pouls', label: 'Pouls maternel', type: 'number' },
          { name: 'liquide', label: 'Liquide amniotique', type: 'select',
            options: (param().liquides || []).map(function (l) { return { value: l.code, label: l.label }; }) },
        ], {});
        var m3 = U.modal({
          title: 'Mesure — ' + r.patient, body: f3,
          footer: [
            K.btn('Annuler', { onclick: function () { m3.close(); } }),
            K.btn('Enregistrer', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f3.collect(); if (!v) return;
                var mesures = (r.mesures || []).concat([v]).sort(function (a, b) { return a.heure - b.heure; });
                colPartogrammes().update(r.id, {
                  mesures: mesures,
                  clos: v.dilatation >= 10,
                  resume: v.dilatation >= 10 ? 'Dilatation complète — expulsion' : r.resume,
                });
                courant = colPartogrammes().active().filter(function (x) { return x.id === r.id; })[0];
                m3.close(); afficher();
                if (franchitAction(courant)) {
                  U.alerter('Un partogramme franchit la ligne d’action — une décision est attendue.', {
                    type: 'warning', son: 'alerte',
                  });
                }
              },
            }),
          ],
        });
      }

      function imprimer(r) {
        P.etat({
          titre: 'PARTOGRAPHIE',
          sousTitre: r.reference + ' — ' + r.patient,
          cartouche: [['Parturiente', r.patient], ['Dossier', r.patientCode],
            ['Gestité / parité', (r.gestite || '—') + ' / ' + (r.parite != null ? r.parite : '—')],
            ['Début du suivi', C.dateHeure(r.debut)], ['Accoucheur', r.accoucheur],
            ['Résumé', r.resume || 'Travail en cours']],
          contenu: P.tableau([
            { label: 'Heure (h)', key: 'heure', align: 'right' },
            { label: 'Dilatation (cm)', key: 'dilatation', align: 'right' },
            { label: 'Descente (/5)', key: 'descente', align: 'right' },
            { label: 'BDF', key: 'bdf', align: 'right' },
            { label: 'CU/10 min', key: 'contractions', align: 'right' },
            { label: 'TA', key: 'ta' },
            { label: 'Pouls', key: 'pouls', align: 'right' },
            { label: 'Liquide', key: 'liquide' },
          ], r.mesures || []),
          signatures: [{ role: 'L’Accoucheur', nom: r.accoucheur, mention: 'Nom, qualification et signature' }],
        });
      }
    },
  });

  /* ==========================================================================
   * DOSSIER BÉBÉ — le volet nouveau-né en écran de soins
   * ======================================================================== */
  global.SIGH.screen('m4-dossier-bebe', {
    title: 'Dossier bébé & soins du nouveau-né',
    description: 'PC et PT obligatoires, Apgar aux trois temps, vitamine K1, réanimation et vaccins de naissance.',
    regle: 'MÊME collection et MÊME formulaire que le registre des naissances : deux saisies auraient '
      + 'divergé au premier correctif. Ici, la lecture est celle des <strong>soins</strong> — bornes '
      + 'PC 32–38 cm, PT 30–36 cm, alerte si l’Apgar à 5 min est &lt; 7 (rapport du 27/08/2026, §5.4).',
    render: function (root) {
      amorcer();
      return K.crud({
        collection: 'naissances', entite: 'dossier bébé', entiteP: 'dossiers bébé', module: 'M4',
        defaultSort: 'dateHeure', defaultDir: 'desc', formSize: 'lg',
        source: 'Rapport officiel maternité du 27/08/2026 — Module C et tableau 7.',
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          {
            key: 'mere', label: 'Nouveau-né de',
            render: function (r) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: 'Nouveau-né de ' + r.mere }),
                el('p.font-mono.text-xs.text-slate-400', { text: r.mereCode + ' — ' + C.dateHeure(r.dateHeure) }),
              ]);
            },
          },
          { key: 'poids', label: 'Poids (kg)', align: 'right' },
          {
            key: 'pc', label: 'PC (cm)', align: 'right',
            render: function (r) {
              var b = (D.BORNES_NOUVEAU_NE || {}).pc || {};
              var hors = r.pc != null && (r.pc < b.min || r.pc > b.max);
              return el('span', { class: hors ? 'font-semibold text-danger-600' : '', text: r.pc != null ? String(r.pc) : '—' });
            },
          },
          {
            key: 'pt', label: 'PT (cm)', align: 'right',
            render: function (r) {
              var b = (D.BORNES_NOUVEAU_NE || {}).pt || {};
              var hors = r.pt != null && (r.pt < b.min || r.pt > b.max);
              return el('span', { class: hors ? 'font-semibold text-danger-600' : '', text: r.pt != null ? String(r.pt) : '—' });
            },
          },
          { key: 'apgar5', label: 'Apgar 1/5/10', align: 'right', text: function (r) { return apgarTexte(r); }, render: function (r) { return apgarTexte(r); } },
          { key: 'reanimation', label: 'Réanimation', text: function (r) { return r.reanimation ? 'Oui' : '—'; }, render: function (r) { return r.reanimation ? U.badge('Réanimé — fonction 7 SONU', 'danger') : el('span.text-xs.text-slate-400', { text: '—' }); } },
          {
            key: 'vitK1', label: 'Soins J0',
            text: function (r) { return [r.vitK1 ? 'K1' : null, r.vpo0 ? 'VPO0' : null, r.bcg ? 'BCG' : null, r.hepB0 ? 'HépB' : null].filter(Boolean).join(' '); },
            render: function (r) {
              var faits = [r.vitK1 ? 'Vit K1' : null, r.vpo0 ? 'VPO0' : null, r.bcg ? 'BCG' : null, r.hepB0 ? 'Hép. B' : null].filter(Boolean);
              return faits.length
                ? el('div.flex.flex-wrap.gap-1', null, faits.map(function (s2) { return U.badge(s2, 'success'); }))
                : U.badge('Aucun soin tracé', 'warning');
            },
          },
        ],
        fields: champsNaissance,
        transform: transformNaissance,
        onCreate: function () { return { vivant: true, declare: false, vitK1: true, collyre: true }; },
        filters: [
          { name: 'reanimation', label: 'Réanimation', options: [{ value: 'oui', label: 'Réanimés' }, { value: 'non', label: 'Sans réanimation' }],
            match: function (r, v) { return v === 'oui' ? !!r.reanimation : !r.reanimation; } },
        ],
        kpis: function (rows) {
          var horsBornes = rows.filter(function (r) { return alertesNouveauNe(r).length; });
          var seuil = (D.BORNES_NOUVEAU_NE || {}).apgarSeuil5min || 7;
          return [
            { label: 'Dossiers bébé', value: C.num(rows.length), icon: 'baby', tone: 'navy' },
            { label: 'Mesures hors bornes', value: C.num(horsBornes.length), icon: 'triangle-alert', tone: horsBornes.length ? 'danger' : 'success', hint: 'PC 32–38 · PT 30–36 · Apgar 5 min ≥ ' + seuil },
            { label: 'Réanimations', value: C.num(rows.filter(function (r) { return r.reanimation; }).length), icon: 'heart-pulse', tone: 'warning', hint: 'Fonction 7 SONU' },
            { label: 'Vitamine K1', value: C.pct(rows.length ? rows.filter(function (r) { return r.vitK1; }).length / rows.length * 100 : 0), icon: 'syringe', tone: 'info' },
          ];
        },
        etat: function (r) {
          P.etat({
            titre: 'Volet nouveau-né',
            sousTitre: 'Nouveau-né de ' + r.mere + ' — ' + r.reference,
            cartouche: [['Mère', r.mere], ['Dossier mère', r.mereCode],
              ['Naissance', C.dateHeure(r.dateHeure)], ['Sexe', r.sexe === 'M' ? 'Masculin' : 'Féminin'],
              ['Statut', r.vivant ? 'Né vivant' : 'Mort-né'], ['Référence', r.reference]],
            contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Valeur', key: 'v' }], [
              { k: 'Poids / taille', v: r.poids + ' kg · ' + (r.taille || '—') + ' cm' },
              { k: 'Périmètre crânien (PC)', v: (r.pc || '—') + ' cm' },
              { k: 'Périmètre thoracique (PT)', v: (r.pt || '—') + ' cm' },
              { k: 'Apgar 1 / 5 / 10 min', v: apgarTexte(r) },
              { k: 'Réanimation néonatale', v: r.reanimation ? 'OUI — fonction 7 SONU' : 'Non' },
              { k: 'Soins essentiels', v: [r.vitK1 ? 'Vitamine K1' : null, r.collyre ? 'Collyre' : null].filter(Boolean).join(', ') || '—' },
              { k: 'Vaccins J0', v: [r.vpo0 ? 'VPO0' : null, r.bcg ? 'BCG' : null, r.hepB0 ? 'Hépatite B' : null].filter(Boolean).join(', ') || '—' },
            ]),
            signatures: [{ role: 'La Sage-femme' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * CPoN — CONSULTATIONS POST-NATALES (Module D)
   * ======================================================================== */
  global.SIGH.screen('m4-cpon', {
    title: 'Consultations post-natales (CPoN)',
    description: 'CPoN 1 à 3, hémorragie ANTE-partum, HPP, examen puerpéral et état du nouveau-né.',
    regle: 'Trois séances — CPoN 1 (6 h–24 h), CPoN 2 (J6–J14), CPoN 3 (6ᵉ semaine). '
      + 'L’<strong>hémorragie ANTE-PARTUM</strong> est LA variable nouvelle du rapport : elle corrèle '
      + 'les complications puerpérales aux hémorragies du 3ᵉ trimestre (placenta praevia, HRP, rupture '
      + 'utérine) — sans elle, le suivi post-natal ignore l’antécédent qui le commande.',
    render: K.crud({
      collection: 'cpon', entite: 'consultation post-natale', entiteP: 'consultations post-natales', module: 'M4',
      defaultSort: 'date', defaultDir: 'desc',
      source: 'Rapport officiel maternité du 27/08/2026 — Module D et tableau 1 (registre CPoN).',
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
        { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
        { key: 'patient', label: 'Accouchée', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
        {
          key: 'type', label: 'Séance',
          text: function (r) { var t = (D.TYPES_CPON || []).filter(function (x) { return x.code === r.type; })[0]; return t ? t.label : r.type; },
          render: function (r) {
            var t = (D.TYPES_CPON || []).filter(function (x) { return x.code === r.type; })[0];
            return U.badge(t ? t.label : r.type, 'navy');
          },
        },
        {
          key: 'hemorragieAntePartum', label: 'Hémorragie ANTE-partum',
          text: function (r) { return r.hemorragieAntePartum ? 'Oui — ' + (r.etiologieAnte || '') : 'Non'; },
          render: function (r) {
            return r.hemorragieAntePartum
              ? U.badge('OUI — ' + (r.etiologieAnte || 'étiologie à préciser'), 'danger')
              : el('span.text-xs.text-slate-400', { text: 'Non' });
          },
        },
        { key: 'hpp', label: 'HPP', text: function (r) { return r.hpp ? 'Oui' : 'Non'; }, render: function (r) { return r.hpp ? U.badge('HPP', 'danger') : el('span.text-xs.text-slate-400', { text: 'Non' }); } },
        { key: 'conseilPF', label: 'Conseil PF', text: function (r) { return r.conseilPF ? 'Fait' : '—'; }, render: function (r) { return r.conseilPF ? U.badge('Fait', 'success') : el('span.text-xs.text-slate-400', { text: '—' }); } },
        { key: 'sageFemme', label: 'Sage-femme' },
      ],
      fields: function () {
        return [
          { name: 'patientCode', label: 'Accouchée', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
          { name: 'date', label: 'Date de la consultation', type: 'date', required: true },
          { name: 'type', label: 'Séance', type: 'select', required: true,
            options: (D.TYPES_CPON || []).map(function (t) { return { value: t.code, label: t.label + ' — ' + t.fenetre }; }) },
          { type: 'section', label: 'Hémorragies — la variable nouvelle du rapport' },
          { name: 'hemorragieAntePartum', label: 'Hémorragie ANTE-partum (3ᵉ trimestre)', type: 'checkbox' },
          { name: 'etiologieAnte', label: 'Étiologie (si hémorragie ante-partum)', type: 'select',
            options: ['Placenta praevia', 'Hématome rétro-placentaire', 'Rupture utérine', 'Autre'] },
          { name: 'hpp', label: 'Hémorragie du post-partum (HPP)', type: 'checkbox' },
          { type: 'section', label: 'Examen et suites' },
          { name: 'examen', label: 'Examen clinique (TA, T°, utérus, lochies, seins)', type: 'textarea', rows: 2, col: 'full' },
          { name: 'supplementation', label: 'Supplémentation (Vit A, fer, folates)' },
          { name: 'conseilPF', label: 'Conseil et adoption PF post-partum', type: 'checkbox' },
          { name: 'etatNouveauNe', label: 'État du nouveau-né (poids, ictère, cordon, allaitement)', type: 'textarea', rows: 2, col: 'full' },
          { name: 'sageFemme', label: 'Sage-femme', type: 'select', required: true, options: sagesFemmes() },
        ];
      },
      transform: function (v, record) {
        rattacher(v, femmes());
        if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('CPO-', 4, S.collection('cpon').all());
        if (!v.hemorragieAntePartum) v.etiologieAnte = null;
        return v;
      },
      beforeSave: function (v) {
        if (v.hemorragieAntePartum && !v.etiologieAnte) {
          return 'Une hémorragie ante-partum se précise : l’étiologie est ce que le rapport demande de corréler.';
        }
        return null;
      },
      filters: [
        { name: 'type', label: 'Séance', options: (D.TYPES_CPON || []).map(function (t) { return { value: t.code, label: t.label }; }) },
        { name: 'hemorragieAntePartum', label: 'Hémorragie ante-partum', options: [{ value: 'oui', label: 'Oui' }, { value: 'non', label: 'Non' }],
          match: function (r, v) { return v === 'oui' ? !!r.hemorragieAntePartum : !r.hemorragieAntePartum; } },
      ],
      kpis: function (rows) {
        return [
          { label: 'CPoN enregistrées', value: C.num(rows.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'Hémorragies ante-partum', value: C.num(rows.filter(function (r) { return r.hemorragieAntePartum; }).length), icon: 'droplets', tone: 'danger', hint: '★ variable nouvelle du rapport' },
          { label: 'HPP', value: C.num(rows.filter(function (r) { return r.hpp; }).length), icon: 'droplet', tone: 'warning' },
          { label: 'Conseils PF donnés', value: C.pct(rows.length ? rows.filter(function (r) { return r.conseilPF; }).length / rows.length * 100 : 0), icon: 'heart-handshake', tone: 'success' },
        ];
      },
      etat: function (r) {
        var t = (D.TYPES_CPON || []).filter(function (x) { return x.code === r.type; })[0];
        P.etat({
          titre: 'Consultation post-natale',
          sousTitre: (t ? t.label : r.type) + ' — ' + r.reference,
          cartouche: [['Accouchée', r.patient], ['Dossier', r.patientCode],
            ['Date', C.dateFR(r.date)], ['Séance', t ? t.label + ' (' + t.fenetre + ')' : r.type],
            ['Sage-femme', r.sageFemme], ['Accouchement', r.accouchementRef || '—']],
          contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Valeur', key: 'v' }], [
            { k: 'Hémorragie ANTE-partum', v: r.hemorragieAntePartum ? 'OUI — ' + (r.etiologieAnte || '') : 'Non' },
            { k: 'Hémorragie du post-partum (HPP)', v: r.hpp ? 'OUI' : 'Non' },
            { k: 'Examen clinique', v: r.examen || '—' },
            { k: 'Supplémentation', v: r.supplementation || '—' },
            { k: 'Conseil PF post-partum', v: r.conseilPF ? 'Donné' : 'Non' },
            { k: 'État du nouveau-né', v: r.etatNouveauNe || '—' },
          ]),
          signatures: [{ role: 'La Sage-femme', nom: r.sageFemme }],
        });
      },
    }),
  });

  /* ==========================================================================
   * PLANIFICATION FAMILIALE — 15 méthodes, codification A/N (Module H)
   * ======================================================================== */
  global.SIGH.screen('m4-planification', {
    title: 'Planification familiale',
    description: 'Registre PF : 15 méthodes contraceptives, codification A/N, rendez-vous de renouvellement.',
    regle: 'Choix <strong>exclusif</strong> parmi les <strong>15 méthodes du rapport</strong> ; la colonne '
      + '<strong>A/N</strong> suit la codification nationale — A = nouvelle acceptante, N = ancienne '
      + '(renouvellement ou changement). Les actes de PF sont <strong>non couverts</strong> par les '
      + 'assurances : la grille tarifaire le porte en toutes lettres.',
    render: K.crud({
      collection: 'planificationFamiliale', entite: 'consultation PF', entiteP: 'consultations PF', module: 'M4',
      defaultSort: 'date', defaultDir: 'desc',
      source: 'Rapport officiel maternité du 27/08/2026 — Module H et tableaux B et 5.',
      plageDates: { champ: 'date', aujourdhui: AUJ },
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
        { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
        { key: 'patient', label: 'Cliente', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
        {
          key: 'acceptante', label: 'A/N',
          render: function (r) {
            return U.badge(r.acceptante === 'A' ? 'A — nouvelle' : 'N — ancienne', r.acceptante === 'A' ? 'success' : 'info');
          },
        },
        {
          key: 'methode', label: 'Méthode adoptée',
          text: function (r) { return r.methodeLabel || r.methode; },
          render: function (r) {
            var m2 = D.methodePF ? D.methodePF(r.methode) : null;
            return el('div.min-w-0', null, [
              el('p.text-sm.text-slate-800', { text: r.methodeLabel || r.methode }),
              m2 ? el('p.text-xs.text-slate-400', { text: m2.categorie }) : null,
            ]);
          },
        },
        { key: 'rdv', label: 'Prochain RDV', nowrap: true, text: function (r) { return r.rdv ? C.dateFR(r.rdv) : '—'; }, render: function (r) { return r.rdv ? C.dateFR(r.rdv) : '—'; } },
        { key: 'sageFemme', label: 'Sage-femme' },
      ],
      fields: function () {
        return [
          { name: 'patientCode', label: 'Cliente', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'acceptante', label: 'Statut d’acceptante (A/N)', type: 'select', required: true,
            options: (D.STATUTS_ACCEPTANTE || []).map(function (s2) { return { value: s2.code, label: s2.label }; }) },
          { name: 'methode', label: 'Méthode contraceptive adoptée', type: 'select', required: true, col: 'full',
            options: (D.METHODES_PF || []).map(function (m2) {
              return { value: m2.code, label: m2.label, detail: m2.categorie + ' — ' + m2.specification };
            }),
            help: 'Les 15 méthodes du rapport, en choix exclusif.' },
          { name: 'methodeAnterieure', label: 'Méthode antérieure utilisée' },
          { name: 'ddr', label: 'Date des dernières règles (DDR)', type: 'date' },
          { name: 'constantes', label: 'Constantes (poids, TA, IMC)' },
          { name: 'rdv', label: 'Prochain rendez-vous', type: 'date' },
          { name: 'sageFemme', label: 'Sage-femme', type: 'select', required: true, options: sagesFemmes() },
        ];
      },
      transform: function (v, record) {
        rattacher(v, femmes());
        if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('PF-', 4, S.collection('planificationFamiliale').all());
        var m2 = D.methodePF ? D.methodePF(v.methode) : null;
        v.methodeLabel = m2 ? m2.label : v.methode;
        return v;
      },
      filters: [
        { name: 'acceptante', label: 'A/N', options: [{ value: 'A', label: 'Nouvelles acceptantes (A)' }, { value: 'N', label: 'Anciennes (N)' }] },
        { name: 'methode', label: 'Méthode', options: (D.METHODES_PF || []).map(function (m2) { return { value: m2.code, label: m2.label }; }) },
      ],
      kpis: function (rows) {
        var nouvelles = rows.filter(function (r) { return r.acceptante === 'A'; });
        var longue = rows.filter(function (r) {
          var m2 = D.methodePF ? D.methodePF(r.methode) : null;
          return m2 && /Longue/.test(m2.categorie);
        });
        return [
          { label: 'Consultations PF', value: C.num(rows.length), icon: 'heart-handshake', tone: 'navy' },
          { label: 'Nouvelles acceptantes (A)', value: C.num(nouvelles.length), icon: 'user-plus', tone: 'success', hint: 'Indicateur DHIS2 — taux d’acceptation' },
          { label: 'Méthodes longue durée', value: C.num(longue.length), icon: 'calendar-range', tone: 'info' },
          { label: 'Méthodes distinctes', value: C.num(Object.keys(C.groupBy(rows, 'methode')).length) + ' / 15', icon: 'list-checks', tone: 'neutral' },
        ];
      },
      etat: function (r) {
        var m2 = D.methodePF ? D.methodePF(r.methode) : null;
        P.etat({
          titre: 'Fiche de planification familiale',
          sousTitre: r.reference,
          cartouche: [['Cliente', r.patient], ['Dossier', r.patientCode],
            ['Date', C.dateFR(r.date)], ['Statut', r.acceptante === 'A' ? 'A — nouvelle acceptante' : 'N — ancienne acceptante'],
            ['Sage-femme', r.sageFemme], ['Prochain RDV', r.rdv ? C.dateFR(r.rdv) : '—']],
          contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Valeur', key: 'v' }], [
            { k: 'Méthode adoptée', v: r.methodeLabel || r.methode },
            { k: 'Catégorie', v: m2 ? m2.categorie : '—' },
            { k: 'Spécification', v: m2 ? m2.specification : '—' },
            { k: 'Méthode antérieure', v: r.methodeAnterieure || '—' },
            { k: 'DDR', v: r.ddr ? C.dateFR(r.ddr) : '—' },
            { k: 'Constantes', v: r.constantes || '—' },
          ]),
          signatures: [{ role: 'La Sage-femme', nom: r.sageFemme }],
        });
      },
    }),
  });

  /* ==========================================================================
   * REGISTRE SONUB / SONUC — les 10 fonctions d'urgence (Module F)
   * ======================================================================== */
  global.SIGH.screen('m4-sonu', {
    title: 'Registre SONUB / SONUC',
    description: 'Urgences obstétricales et néonatales : les 10 fonctions officielles, gestes horodatés, évolution.',
    regle: 'Les <strong>7 fonctions SONUB</strong> (base) et les <strong>3 SONUC</strong> (transfusion, '
      + 'chirurgie obstétricale, césarienne) du rapport, en liste fermée, plus une case « autre geste » '
      + 'en texte libre <strong>horodaté</strong>. C’est la cotation exacte des gestes d’urgence vitale '
      + 'posés — elle classe la structure SONUB ou SONUC dans les rapports nationaux.',
    render: K.crud({
      collection: 'registreSONU', entite: 'urgence obstétricale', entiteP: 'urgences obstétricales', module: 'M4',
      defaultSort: 'dateHeure', defaultDir: 'desc', formSize: 'lg',
      source: 'Rapport officiel maternité du 27/08/2026 — Module F et tableaux A et 3.',
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
        {
          key: 'dateHeure', label: 'Arrivée', nowrap: true,
          text: function (r) { return C.dateHeure(r.dateHeure); },
          render: function (r) { return C.dateHeure(r.dateHeure); },
          sortValue: function (r) { return C.toDate(r.dateHeure).getTime(); },
        },
        { key: 'patient', label: 'Patiente', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
        {
          key: 'evacuation', label: 'Provenance',
          text: function (r) { return r.evacuation ? 'Évacuée — ' + (r.provenance || '') : 'Venue d’elle-même'; },
          render: function (r) {
            return r.evacuation ? U.badge('Évacuée — ' + (r.provenance || ''), 'warning')
              : el('span.text-xs.text-slate-500', { text: 'Venue d’elle-même' });
          },
        },
        {
          key: 'fonctions', label: 'Fonctions SONU posées',
          text: function (r) { return (r.fonctions || []).join(', '); },
          render: function (r) {
            return el('div.flex.flex-wrap.gap-1', null, (r.fonctions || []).map(function (n) {
              var f2 = D.fonctionSONU ? D.fonctionSONU(n) : null;
              return U.badge(n + ' — ' + (f2 ? f2.label : ''), f2 && f2.type === 'SONUC' ? 'danger' : 'info');
            }));
          },
        },
        {
          key: 'evolution', label: 'Évolution',
          render: function (r) {
            var tone = r.evolution === 'Favorable' ? 'success' : (r.evolution === 'Décédée' ? 'danger' : 'warning');
            return U.badge(r.evolution || '—', tone);
          },
        },
        { key: 'agent', label: 'Agent' },
      ],
      fields: function () {
        return [
          { name: 'patientCode', label: 'Patiente', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
          { name: 'dateHeure', label: 'Date et heure d’arrivée', type: 'datetime-local', required: true },
          { name: 'gestite', label: 'Gestité', type: 'number', min: 0 },
          { name: 'parite', label: 'Parité', type: 'number', min: 0 },
          { name: 'evacuation', label: 'Évacuée d’une autre structure', type: 'checkbox' },
          { name: 'provenance', label: 'Provenance (CS / localité)' },
          { name: 'diagnosticEvacuation', label: 'Diagnostic d’évacuation' },
          { name: 'heureAbordVeineux', label: 'Heure de l’abord veineux', placeholder: '08h15' },
          { type: 'section', label: 'Les 10 fonctions SONU — diagnostic après examen' },
          { name: 'fonctions', label: 'Fonctions posées', type: 'multiselect', required: true, col: 'full',
            options: ((D.SONU || {}).fonctions || []).map(function (f2) {
              return { value: f2.num, label: f2.num + ' — ' + f2.label + ' (' + f2.type + ')', detail: f2.description };
            }) },
          { name: 'autreGeste', label: 'Autre geste SONU (texte libre)', col: 'full' },
          { name: 'heureFinGestes', label: 'Heure de fin des gestes', placeholder: '10h40' },
          { type: 'section', label: 'Issue' },
          { name: 'evolution', label: 'Évolution', type: 'select', required: true,
            options: ['Favorable', 'Référée', 'Décédée'] },
          { name: 'agent', label: 'Agent (nom et qualification)', type: 'select', required: true, options: sagesFemmes() },
        ];
      },
      transform: function (v, record) {
        rattacher(v, femmes());
        if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('SONU-', 4, S.collection('registreSONU').all());
        v.fonctions = (v.fonctions || []).map(Number).sort(function (a, b) { return a - b; });
        return v;
      },
      filters: [
        { name: 'niveau', label: 'Niveau', options: [{ value: 'sonub', label: 'SONUB seulement (1-7)' }, { value: 'sonuc', label: 'Avec fonction SONUC (8-10)' }],
          match: function (r, v) {
            var aSonuc = (r.fonctions || []).some(function (n) { return n >= 8; });
            return v === 'sonuc' ? aSonuc : !aSonuc;
          } },
        { name: 'evolution', label: 'Évolution', options: ['Favorable', 'Référée', 'Décédée'] },
      ],
      kpis: function (rows) {
        var sonuc = rows.filter(function (r) { return (r.fonctions || []).some(function (n) { return n >= 8; }); });
        var rea = rows.filter(function (r) { return (r.fonctions || []).indexOf(7) !== -1; });
        return [
          { label: 'Urgences enregistrées', value: C.num(rows.length), icon: 'siren', tone: 'danger' },
          { label: 'Avec fonction SONUC', value: C.num(sonuc.length), icon: 'building-2', tone: 'warning', hint: 'transfusion, chirurgie, césarienne' },
          { label: 'Réanimations nouveau-né (f7)', value: C.num(rea.length), icon: 'baby', tone: 'info' },
          { label: 'Évolutions favorables', value: C.pct(rows.length ? rows.filter(function (r) { return r.evolution === 'Favorable'; }).length / rows.length * 100 : 0), icon: 'heart', tone: 'success' },
        ];
      },
      etat: function (r) {
        P.etat({
          titre: 'Registre SONUB / SONUC — fiche d’urgence',
          sousTitre: r.reference,
          cartouche: [['Patiente', r.patient], ['Dossier', r.patientCode],
            ['Arrivée', C.dateHeure(r.dateHeure)],
            ['Gestité / parité', (r.gestite != null ? r.gestite : '—') + ' / ' + (r.parite != null ? r.parite : '—')],
            ['Provenance', r.evacuation ? 'Évacuée — ' + (r.provenance || '') : 'Venue d’elle-même'],
            ['Évolution', r.evolution]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'N°', value: function (n) { return String(n); }, align: 'right' },
              { label: 'Fonction SONU posée', value: function (n) { var f2 = D.fonctionSONU ? D.fonctionSONU(n) : null; return f2 ? f2.label : String(n); } },
              { label: 'Type', value: function (n) { var f2 = D.fonctionSONU ? D.fonctionSONU(n) : null; return f2 ? f2.type : '—'; } },
            ], r.fonctions || []),
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Valeur', key: 'v' }], [
              { k: 'Diagnostic d’évacuation', v: r.diagnosticEvacuation || '—' },
              { k: 'Heure de l’abord veineux', v: r.heureAbordVeineux || '—' },
              { k: 'Autre geste SONU', v: r.autreGeste || '—' },
              { k: 'Heure de fin des gestes', v: r.heureFinGestes || '—' },
            ]),
          ]),
          signatures: [{ role: 'L’Agent', nom: r.agent, mention: 'Nom, prénom et qualification' }],
        });
      },
    }),
  });

  /* ==========================================================================
   * PTME — REGISTRE QUADRIPARTITE (Module I)
   * ======================================================================== */
  global.SIGH.screen('m4-ptme', {
    title: 'Registre PTME',
    description: 'Prévention de la transmission mère-enfant : dépistage, protocole, enfants exposés, dispensation ARV.',
    regle: 'Quatre volets, comme le registre national : <strong>1</strong> dépistage triple (VIH, Ag HBs, '
      + 'syphilis), <strong>2</strong> protocole et allaitement, <strong>3</strong> enfants exposés '
      + '(PCR-1 à 6 semaines, PCR-2 à 9 mois, sérologie à 18 mois), <strong>4</strong> dispensation '
      + 'mensuelle des ARV. Données parmi les plus <strong>sensibles</strong> du dossier — le '
      + 'cloisonnement RBAC de M4 s’applique pleinement (RG-13).',
    render: K.crud({
      collection: 'ptme', entite: 'fiche PTME', entiteP: 'fiches PTME', module: 'M4',
      defaultSort: 'reference', formSize: 'lg',
      source: 'Rapport officiel maternité du 27/08/2026 — Module I et tableau 6 (protocoles PTME).',
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
        { key: 'patient', label: 'Mère suivie', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
        { key: 'chargeVirale', label: 'Charge virale', render: function (r) { return U.badge(r.chargeVirale || '—', r.chargeVirale === 'Indétectable' ? 'success' : 'warning'); } },
        { key: 'allaitement', label: 'Allaitement' },
        {
          key: 'pcr1', label: 'Suivi enfant',
          text: function (r) { return ['N: ' + (r.pcrNaissance || '—'), '6 sem: ' + (r.pcr1 || '—'), '9 m: ' + (r.pcr2 || '—')].join(' · '); },
          render: function (r) {
            return el('div.text-xs.text-slate-600', null, [
              el('p', { text: 'PCR naissance : ' + (r.pcrNaissance || 'en attente') }),
              el('p', { text: 'PCR-1 (6 sem) : ' + (r.pcr1 || 'à faire') + ' · PCR-2 (9 mois) : ' + (r.pcr2 || 'à faire') }),
            ]);
          },
        },
        {
          key: 'dispensations', label: 'Dispensations ARV', align: 'right',
          value: function (r) { return (r.dispensations || []).length; },
          render: function (r) {
            var servies = (r.dispensations || []).filter(function (d2) { return d2.servie; }).length;
            return el('span.text-sm.num', { text: servies + ' / ' + (r.dispensations || []).length });
          },
        },
      ],
      fields: function () {
        return [
          { name: 'patientCode', label: 'Mère suivie', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
          { type: 'section', label: 'Volet 1 — dépistage (CPN)' },
          { name: 'vihTrimestre', label: 'Trimestre du dépistage VIH', type: 'select', options: [1, 2, 3] },
          { name: 'vihType', label: 'Type', type: 'select', options: ['VIH-1', 'VIH-2', 'VIH-1+2'] },
          { name: 'agHbs', label: 'Ag HBs (hépatite B)', type: 'select', options: ['Négatif', 'Positif'] },
          { name: 'syphilis', label: 'Syphilis (TPHA/VDRL)', type: 'select', options: ['Négatif', 'Positif'] },
          { name: 'chargeVirale', label: 'Charge virale' },
          { type: 'section', label: 'Volet 2 — protocole mère et nouveau-né' },
          { name: 'protocoleARV', label: 'Protocole ARV' },
          { name: 'dureeARV', label: 'Durée du traitement', type: 'select', options: (D.PTME || {}).dureesARV || [] },
          { name: 'allaitement', label: 'Mode d’allaitement', type: 'select', required: true, options: (D.PTME || {}).allaitements || [] },
          { name: 'prophylaxieNN', label: 'Prophylaxie ARV du nouveau-né', type: 'select',
            options: ((D.PTME || {}).prophylaxiesNN || []).map(function (p2) { return { value: p2.code, label: p2.code + ' = ' + p2.label }; }) },
          { type: 'section', label: 'Volet 3 — enfant exposé' },
          { name: 'pcrNaissance', label: 'PCR à la naissance', type: 'select', options: ['En attente', 'Négatif', 'Positif'] },
          { name: 'pcr1', label: 'PCR-1 (6 semaines)', type: 'select', options: ['', 'Négatif', 'Positif'] },
          { name: 'pcr2', label: 'PCR-2 (9 mois)', type: 'select', options: ['', 'Négatif', 'Positif'] },
          { name: 'serologie18m', label: 'Sérologie VIH (18 mois)', type: 'select', options: ['', 'Négatif', 'Positif'] },
          { name: 'ctm', label: 'Prophylaxie Cotrimoxazole (CTM)', type: 'checkbox' },
          { name: 'hepBJ0', label: 'Vaccination hépatite B à J0', type: 'checkbox' },
        ];
      },
      transform: function (v, record) {
        rattacher(v, femmes());
        if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('PTME-', 4, S.collection('ptme').all());
        return v;
      },
      kpis: function (rows) {
        var indetectables = rows.filter(function (r) { return r.chargeVirale === 'Indétectable'; });
        return [
          { label: 'Mères suivies', value: C.num(rows.length), icon: 'shield-check', tone: 'navy' },
          { label: 'Charges virales indétectables', value: C.num(indetectables.length), icon: 'check-circle-2', tone: 'success' },
          { label: 'PCR-1 rendues', value: C.num(rows.filter(function (r) { return r.pcr1; }).length), icon: 'flask-conical', tone: 'info' },
          { label: 'Sous CTM', value: C.num(rows.filter(function (r) { return r.ctm; }).length), icon: 'pill', tone: 'neutral' },
        ];
      },
      detail: function (r) {
        return el('div.space-y-4', null, [
          K.note('Fiche <strong>sensible</strong> — le détail reste derrière les permissions de M4 ; il ne '
            + 'figure ni dans les notifications, ni dans les alertes sonores.', { tone: 'warning', icon: 'lock' }),
          K.grid([
            ['Référence', r.reference], ['Mère', r.patient + ' — ' + r.patientCode],
            ['Dépistage', 'VIH ' + (r.vihType || '—') + ' (T' + (r.vihTrimestre || '—') + ') · Ag HBs ' + (r.agHbs || '—') + ' · Syphilis ' + (r.syphilis || '—')],
            ['Charge virale', r.chargeVirale || '—'],
            ['Protocole', (r.protocoleARV || '—') + ' — ' + (r.dureeARV || '—')],
            ['Allaitement', r.allaitement || '—'],
            ['Prophylaxie NN', String(r.prophylaxieNN || '—')],
            ['Enfant exposé', 'PCR naissance ' + (r.pcrNaissance || '—') + ' · PCR-1 ' + (r.pcr1 || '—') + ' · PCR-2 ' + (r.pcr2 || '—') + ' · Séro 18 m ' + (r.serologie18m || '—')],
            ['CTM / Hép. B J0', (r.ctm ? 'CTM' : '—') + ' / ' + (r.hepBJ0 ? 'fait' : '—')],
          ]),
          el('div', null, [
            K.section('Volet 4 — dispensation mensuelle des ARV'),
            (r.dispensations || []).length
              ? K.miniTable(['Mois', 'Servie'], (r.dispensations || []).map(function (d2) {
                return [d2.mois, d2.servie ? 'Oui' : 'MANQUÉE'];
              }))
              : U.empty('Aucune dispensation tracée.', { icon: 'pill' }),
          ]),
        ]);
      },
    }),
  });

  /* ==========================================================================
   * SOINS CURATIFS & URGENCES MATERNITÉ — Case 27 restructurée (Module E)
   * ======================================================================== */
  global.SIGH.screen('m4-soins-curatifs', {
    title: 'Soins curatifs & urgences maternité',
    description: 'Registre des consultations curatives : MILDA, femmes référées d’urgence, devenir (Case 27).',
    regle: 'La <strong>Case 27</strong> du registre national est restructurée comme le rapport le demande : '
      + '« femme observée » (oui/non), « femme hospitalisée » (oui/non) et « nombre de jours » — ce dernier '
      + 'n’a de sens que si l’hospitalisation est cochée, et le formulaire le tient. Les trois variables '
      + 'de <strong>femmes en travail référées d’urgence</strong> alimentent l’audit des transferts.',
    render: K.crud({
      collection: 'soinsCuratifsMaternite', entite: 'soin curatif', entiteP: 'soins curatifs', module: 'M4',
      defaultSort: 'date', defaultDir: 'desc',
      source: 'Rapport officiel maternité du 27/08/2026 — Module E et tableau 2 (registre de soins curatifs).',
      plageDates: { champ: 'date', aujourdhui: AUJ },
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
        { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
        { key: 'patient', label: 'Consultante', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
        { key: 'diagnostic', label: 'Diagnostic' },
        { key: 'mildaDelivree', label: 'MILDA', text: function (r) { return r.mildaDelivree ? 'Délivrée' : '—'; }, render: function (r) { return r.mildaDelivree ? U.badge('Délivrée', 'success') : el('span.text-xs.text-slate-400', { text: '—' }); } },
        {
          key: 'urgenceMaternite', label: 'Urgence maternité',
          text: function (r) {
            var u = (D.URGENCES_MATERNITE || []).filter(function (x) { return x.code === r.urgenceMaternite; })[0];
            return u ? u.label : '—';
          },
          render: function (r) {
            var u = (D.URGENCES_MATERNITE || []).filter(function (x) { return x.code === r.urgenceMaternite; })[0];
            return u ? U.badge(u.label, 'danger') : el('span.text-xs.text-slate-400', { text: '—' });
          },
        },
        {
          key: 'femmeHospitalisee', label: 'Devenir (Case 27)',
          text: function (r) {
            return (r.femmeObservee ? 'Observée' : '') + (r.femmeHospitalisee ? ' · Hospitalisée ' + (r.joursHospitalisation || '?') + ' j' : '');
          },
          render: function (r) {
            var out = [];
            if (r.femmeObservee) out.push(U.badge('Observée', 'info'));
            if (r.femmeHospitalisee) out.push(U.badge('Hospitalisée — ' + (r.joursHospitalisation || '?') + ' j', 'warning'));
            if (!out.length) out.push(el('span.text-xs.text-slate-400', { text: 'Retour à domicile' }));
            return el('div.flex.flex-wrap.gap-1', null, out);
          },
        },
        { key: 'agent', label: 'Agent' },
      ],
      fields: function () {
        return [
          { name: 'patientCode', label: 'Consultante', type: 'select', required: true, options: optionsFemmes(), col: 'full' },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'trancheAge', label: 'Tranche d’âge', type: 'select', options: D.TRANCHES_AGE_CURATIF || [] },
          { name: 'symptomes', label: 'Symptômes et signes (si toux, préciser la durée)', type: 'textarea', rows: 2, col: 'full' },
          { name: 'diagnostic', label: 'Diagnostic', required: true },
          { name: 'traitement', label: 'Traitement / posologie' },
          { name: 'mildaDelivree', label: 'MILDA délivrée', type: 'checkbox' },
          { name: 'urgenceMaternite', label: 'Femme en travail référée d’urgence', type: 'select',
            options: [{ value: '', label: '— Sans objet —' }].concat((D.URGENCES_MATERNITE || []).map(function (u) {
              return { value: u.code, label: u.label };
            })) },
          { type: 'section', label: 'Case 27 — devenir de la patiente' },
          { name: 'femmeObservee', label: 'Femme observée', type: 'checkbox' },
          { name: 'femmeHospitalisee', label: 'Femme hospitalisée', type: 'checkbox' },
          { name: 'joursHospitalisation', label: 'Nombre de jours d’hospitalisation', type: 'number', min: 1,
            help: 'Ne se renseigne que si l’hospitalisation est cochée — le formulaire le contrôle.' },
          { name: 'agent', label: 'Agent', type: 'select', required: true, options: sagesFemmes() },
        ];
      },
      transform: function (v, record) {
        rattacher(v, femmes());
        if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('SCM-', 4, S.collection('soinsCuratifsMaternite').all());
        if (!v.femmeHospitalisee) v.joursHospitalisation = null;
        return v;
      },
      beforeSave: function (v) {
        if (v.femmeHospitalisee && (v.joursHospitalisation == null || v.joursHospitalisation === '')) {
          return 'La Case 27 exige le nombre de jours quand la femme est hospitalisée.';
        }
        if (!v.femmeHospitalisee && v.joursHospitalisation) {
          return 'Un nombre de jours sans hospitalisation cochée n’a pas de sens (Case 27).';
        }
        return null;
      },
      filters: [
        { name: 'urgenceMaternite', label: 'Urgences', options: (D.URGENCES_MATERNITE || []).map(function (u) { return { value: u.code, label: u.label }; }) },
        { name: 'devenir', label: 'Devenir', options: [{ value: 'obs', label: 'Observées' }, { value: 'hosp', label: 'Hospitalisées' }],
          match: function (r, v) { return v === 'obs' ? !!r.femmeObservee : !!r.femmeHospitalisee; } },
      ],
      kpis: function (rows) {
        var refs = rows.filter(function (r) { return r.urgenceMaternite; });
        return [
          { label: 'Consultations curatives', value: C.num(rows.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'MILDA délivrées', value: C.num(rows.filter(function (r) { return r.mildaDelivree; }).length), icon: 'tent', tone: 'success' },
          { label: 'Femmes référées d’urgence', value: C.num(refs.length), icon: 'siren', tone: 'danger', hint: 'les trois variables normalisées' },
          { label: 'Hospitalisées (Case 27)', value: C.num(rows.filter(function (r) { return r.femmeHospitalisee; }).length), icon: 'bed-double', tone: 'warning' },
        ];
      },
    }),
  });

  /* ==========================================================================
   * DOSSIER OBSTÉTRICAL (M4)
   * --------------------------------------------------------------------------
   * LE DOSSIER EST LA PIÈCE QUI TIENT LES AUTRES. Le prototype portait déjà la
   * CPN, le partogramme, l'accouchement, le nouveau-né et les CPoN — chacun
   * dans son écran, et rien pour les relier. Or le formulaire national est UN
   * SEUL cahier : on l'ouvre à la première consultation prénatale et on le
   * referme après la surveillance du deuxième jour. Sans lui, la sage-femme
   * qui reçoit une parturiente à trois heures du matin devait ouvrir cinq
   * écrans pour savoir ce qu'on savait déjà d'elle.
   *
   * Cinq feuillets, transcrits d'un dossier RÉELLEMENT REMPLI (exemplaire de
   * recette du 06/09/2026) : identité et antécédents, soins préventifs et
   * promotionnels, consultation prénatale, accouchement et nouveau-né,
   * surveillance intégrée. AUCUNE identité du document n'est reprise.
   *
   * LE NUMÉRO DE DOSSIER EST CELUI DU REGISTRE PAPIER — NNNNN/AA, série
   * annuelle : c'est par lui que la maternité retrouve un dossier, et le
   * renuméroter romprait la correspondance avec les cahiers tenus depuis des
   * années (même doctrine que le code d'analyse et les pièces certifiantes).
   * ======================================================================== */

  /* L'AMORÇAGE N'OUVRE QUE LA COLLECTION. Les dossiers sont semés au socle
     (data-seed.js, section maternité) : le tableau de bord de la maternité
     et les statistiques du Pilotage les lisent, et une collection amorcée par
     son écran affiche un zéro FAUX partout ailleurs. */
  function amorcerDossiers() {
    colDossiers();
  }

  function colDossiers() {
    return S.collection('dossiersObstetricaux', { module: 'M4', entite: 'dossier obstétrical', prefix: 'DOB' });
  }

  /** Le numéro de dossier obstétrical — fabrique UNIQUE, série annuelle. */
  function numeroDossierObstetrical(date) {
    var d = date ? C.toDate(date) : new Date();
    var an = String(isNaN(d.getTime()) ? new Date().getFullYear() : d.getFullYear());
    var max = 0;
    colDossiers().all().forEach(function (x) {
      var m = /^(\d+)\/(\d{2})$/.exec(String(x.numeroDossier || ''));
      if (m && m[2] === an.slice(-2) && +m[1] > max) max = +m[1];
    });
    /* Cinq chiffres, comme le registre papier et les dossiers déjà ouverts (« 00007/26 ») : « 7/26 » ne se range pas avec eux (écart E404). */
    return String(max + 1).padStart(5, '0') + '/' + an.slice(-2);
  }

  /** Les facteurs de surveillance COCHÉS — c'est leur cumul qui classe à risque. */
  function facteursCoches(d) {
    return (D.FACTEURS_SURVEILLANCE || []).filter(function (f) {
      return (d.facteurs || {})[f.code];
    });
  }
  function estGAR(d) { return facteursCoches(d).length > 0; }

  /* ==========================================================================
   * OUVERTURE D'UN DOSSIER OBSTÉTRICAL — LA PAGE
   * --------------------------------------------------------------------------
   * Mêmes champs, même numérotation annuelle, même déduction de la date
   * probable depuis la DDR, même carte de facteurs : la page CONSOMME la
   * configuration du registre, elle ne la recopie pas. Deux déclarations
   * auraient divergé au premier facteur de surveillance ajouté.
   * ======================================================================== */
  global.SIGH.screen('m4-dossier-obstetrical-nouveau', {
    title: 'Ouvrir un dossier obstétrical',
    description: 'Identité, antécédents gynéco-obstétricaux, facteurs de surveillance et plan d’accouchement — le cahier de la parturiente s’ouvre ici.',
    regle: 'Le <strong>numéro de dossier</strong> suit le registre papier (NNNNN/AA, série annuelle). '
      + 'La <strong>date probable de l’accouchement se déduit de la DDR</strong> (280 jours) — la saisir '
      + 'à part ouvrirait deux dates qui ne se recoupent pas. Le <strong>risque n’est pas un champ</strong> : '
      + 'il se déduit du cumul des facteurs cochés.',
    render: K.pageFormulaire({
      collection: 'dossiersObstetricaux', entite: 'dossier obstétrical', module: 'M4',
      retour: 'm4-dossier-obstetrical',
      titreCarte: 'Le cahier de la parturiente',
      libelleValider: 'Ouvrir le dossier',
      refus: 'Votre profil consulte les dossiers obstétricaux sans les ouvrir. Le cahier appartient '
        + 'à la sage-femme et au médecin qui suivent la grossesse.',
      fields: champsDossier,
      onCreate: function () {
        return { dateEntree: C.iso(AUJ), statutDossier: 'suivi', gestite: 1, parite: 0,
          numeroDossier: numeroDossierObstetrical(AUJ) };
      },
      transform: function (v, record) {
        if (!v.numeroDossier) v.numeroDossier = numeroDossierObstetrical(v.dateEntree);
        var p = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
        if (p) { v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom; v.age = C.age(p.dateNaissance); }
        if (v.ddr) v.dpa = C.iso(C.addDays(v.ddr, 280));
        v.facteurs = {};
        (D.FACTEURS_SURVEILLANCE || []).forEach(function (f) {
          if (v['facteur_' + f.code]) v.facteurs[f.code] = true;
        });
        return v;
      },
      parcours: [
        { title: 'Ouverture du cahier', detail: 'Identité, antécédents, facteurs de surveillance — vous y êtes', date: 'Étape 1', tone: 'navy' },
        { title: 'Consultations prénatales', detail: 'La grille CPN, visite après visite — SP1-5, MILDA, dépistages (M4)', date: 'Étape 2', tone: 'info' },
        { title: 'Travail et partogramme', detail: 'Alerte à 4 cm puis 1 cm/h ; action décalée de 4 h (M4)', date: 'Étape 3', tone: 'info' },
        { title: 'Accouchement et nouveau-né', detail: 'Délivrance, placenta, Apgar 1-5-10, PC/PT (M4)', date: 'Étape 4', tone: 'warning' },
        { title: 'Surveillance et CPoN', detail: 'Fiche intégrée mère-bébé, puis les trois consultations post-natales', date: 'Étape 5', tone: 'neutral' },
      ],
      rappels: [{
        titre: 'Ce que le cahier engage',
        notes: [
          { texte: 'Le <strong>risque se déduit du CUMUL</strong> des facteurs cochés, jamais d’un '
            + 'facteur isolé. Cocher, c’est classer la grossesse à risque et la faire remonter au '
            + 'tableau de bord de la maternité.', tone: 'warning', icon: 'alert-triangle' },
          { texte: 'La <strong>date probable ne se saisit pas</strong> : elle vient de la DDR, à '
            + '280 jours. C’est la règle que la sage-femme applique de tête, et la tenir à un seul '
            + 'endroit évite deux termes qui ne se recoupent pas.', tone: 'info', icon: 'calendar-clock' },
          { texte: 'Le <strong>numéro suit le registre papier</strong> (NNNNN/AA) : le renuméroter '
            + 'romprait la correspondance avec les cahiers tenus depuis des années.',
          tone: 'neutral', icon: 'hash' },
        ],
      }],
    }),
    actions: K.actionsPageFormulaire('M4', 'Ouvrir le dossier'),
  });

  global.SIGH.screen('m4-dossier-obstetrical', {
    title: 'Dossier obstétrical',
    description: 'Le cahier de la parturiente, de la première CPN à la surveillance du deuxième jour — identité, antécédents, facteurs de surveillance, examens, plan d’accouchement.',
    regle: 'Le dossier obstétrical est <strong>un seul cahier</strong> : identité et antécédents, soins '
      + 'préventifs, consultations prénatales, accouchement, surveillance. Les éclater en cinq écrans '
      + 'obligeait la sage-femme de garde à tous les ouvrir pour savoir ce qu’on savait déjà. '
      + 'Le <strong>numéro de dossier</strong> suit le registre papier (NNNNN/AA, série annuelle) : le '
      + 'renuméroter romprait la correspondance avec les cahiers tenus depuis des années. '
      + 'Un <strong>facteur de surveillance coché</strong> classe la grossesse à risque — et c’est le '
      + 'cumul qui compte, jamais un facteur isolé.',
    render: function (root) {
      amorcerDossiers();
      return K.crud({
        collection: 'dossiersObstetricaux', module: 'M4',
        entite: 'dossier obstétrical', entiteP: 'dossiers obstétricaux',
        /* L'OUVERTURE A QUITTÉ LA MODALE (22/09/2026) : un dossier
           obstétrical, c'est l'identité, les antécédents gynéco-obstétricaux,
           douze facteurs de surveillance et le plan d'accouchement — on le
           remplit avec la parturiente en face, en plusieurs minutes. Une
           fenêtre qu'un clic à côté referme n'est pas ce cadre-là. La
           modification, plus courte, reste en modale. */
        creerVers: 'm4-dossier-obstetrical-nouveau',
        defaultSort: 'dateEntree', defaultDir: 'desc', pageSize: 12, formSize: 'xl',
        drawerWidth: 'max-w-4xl',
        source: 'Formulaire national « DOSSIER OBSTÉTRICAL » — Ministère de la Santé, République du Bénin.',
        plageDates: { champ: 'dateEntree', aujourdhui: AUJ },
        columns: [
          { key: 'numeroDossier', label: 'N° dossier', nowrap: true,
            render: function (d) { return el('span.font-mono.text-xs.font-semibold', { text: d.numeroDossier }); } },
          { key: 'patient', label: 'Parturiente', render: function (d) {
            return el('div.min-w-0', null, [
              el('p.truncate.text-sm.font-medium.text-slate-800', { text: d.patient }),
              el('p.text-xs.text-slate-400', { text: (d.patientCode || '') + ' · ' + (d.age || '—') + ' ans' }),
            ]);
          } },
          { key: 'gestiteParite', label: 'G / P', nowrap: true,
            value: function (d) { return 'G' + (d.gestite || 0) + ' P' + (d.parite || 0); } },
          { key: 'ddr', label: 'DDR', nowrap: true, text: function (d) { return d.ddr ? C.dateFR(d.ddr) : ''; },
            render: function (d) { return d.ddr ? C.dateFR(d.ddr) : '—'; } },
          { key: 'dpa', label: 'Terme prévu', nowrap: true, text: function (d) { return d.dpa ? C.dateFR(d.dpa) : ''; },
            render: function (d) {
              if (!d.dpa) return '—';
              var reste = C.daysBetween(AUJ, d.dpa);
              return el('div', null, [
                el('p.text-sm.text-slate-700', { text: C.dateFR(d.dpa) }),
                el('p.text-xs.text-slate-400', { text: reste >= 0 ? 'dans ' + reste + ' j' : 'dépassé de ' + (-reste) + ' j' }),
              ]);
            } },
          { key: 'gar', label: 'Surveillance', value: function (d) { return estGAR(d) ? 'gar' : 'normal'; },
            render: function (d) {
              var f = facteursCoches(d);
              return f.length
                ? el('div', null, [U.badge('GAR — ' + f.length + ' facteur(s)', 'danger'),
                  el('p.mt-0\\.5.text-xs.text-slate-400', { text: f[0].libelle + (f.length > 1 ? '…' : '') })])
                : U.badge('Sans facteur', 'success');
            } },
          { key: 'statutDossier', label: 'État', render: function (d) {
            var m = { suivi: ['Suivi en cours', 'info'], accouchee: ['Accouchée', 'success'],
              clos: ['Clos', 'neutral'] };
            var x = m[d.statutDossier] || ['Suivi en cours', 'info'];
            return U.badge(x[0], x[1]);
          } },
        ],
        filters: [
          { name: 'statutDossier', label: 'État', options: [
            { value: 'suivi', label: 'Suivi en cours' }, { value: 'accouchee', label: 'Accouchée' },
            { value: 'clos', label: 'Clos' }] },
          { name: 'gar', label: 'Surveillance',
            options: [{ value: 'gar', label: 'Grossesse à risque' }, { value: 'normal', label: 'Sans facteur' }],
            match: function (d, v) { return v === 'gar' ? estGAR(d) : !estGAR(d); } },
          { name: 'venue', label: 'Venue',
            options: [{ value: 'elle', label: 'Venue d’elle-même' }, { value: 'referee', label: 'Référée' }],
            match: function (d, v) { return v === 'referee' ? !!d.referee : !d.referee; } },
        ],
        fields: champsDossier,
        transform: function (v, record) {
          if (!v.numeroDossier) v.numeroDossier = numeroDossierObstetrical(v.dateEntree);
          var p = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
          if (p) { v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom; v.age = C.age(p.dateNaissance); }
          /* La date probable de l'accouchement se DÉDUIT de la DDR — 280 jours,
             la règle que la sage-femme applique de tête. La saisir à part
             ouvrirait la porte à deux dates qui ne se recoupent pas. */
          if (v.ddr) v.dpa = C.iso(C.addDays(v.ddr, 280));
          /* Les cases se rangent dans UNE carte : sans elle, chaque écran qui
             veut savoir si la grossesse est à risque devrait connaître les
             douze noms de champ, et un facteur ajouté en oublierait un. */
          v.facteurs = {};
          (D.FACTEURS_SURVEILLANCE || []).forEach(function (f) {
            if (v['facteur_' + f.code]) v.facteurs[f.code] = true;
          });
          return v;
        },
        onCreate: function () {
          return { dateEntree: C.iso(AUJ), statutDossier: 'suivi', gestite: 1, parite: 0,
            numeroDossier: numeroDossierObstetrical(AUJ) };
        },
        kpis: function (rows) {
          var gar = rows.filter(estGAR);
          return [
            { label: 'Dossiers ouverts', value: C.num(rows.length), icon: 'folder-open', tone: 'navy' },
            { label: 'Suivis en cours', value: C.num(rows.filter(function (d) { return d.statutDossier === 'suivi'; }).length),
              icon: 'activity', tone: 'info' },
            { label: 'Grossesses à risque (GAR)', value: C.num(gar.length),
              icon: 'alert-triangle', tone: gar.length ? 'danger' : 'success',
              hint: 'Au moins un facteur de surveillance coché' },
            { label: 'Référées', value: C.num(rows.filter(function (d) { return d.referee; }).length),
              icon: 'share-2', tone: 'warning' },
          ];
        },
        detail: detailDossier,
        etat: etatDossier,
      })(root);
    },
  });

  function champsDossier(record) {
    var champs = [
      { name: '_s1', type: 'section', label: 'Dossier' },
      { name: 'numeroDossier', label: 'N° de dossier (registre papier)', required: true,
        hint: 'Série annuelle NNNNN/AA — reprise du cahier de la maternité.' },
      { name: 'dateEntree', label: 'Date d’entrée', type: 'date', required: true },
      { name: 'patientCode', label: 'Parturiente (dossier patient)', type: 'select', required: true,
        col: 'full', options: C.sortBy(S.collection('patients').active()
          .filter(function (p) { return p.sexe === 'F'; }), 'code').map(function (p) {
          return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
        }) },
      { name: 'profession', label: 'Profession' },
      { name: 'nationalite', label: 'Nationalité' },
      { name: 'quartier', label: 'Village / quartier de ville' },
      { name: 'telephone', label: 'Téléphone', type: 'tel' },
      { name: 'personneContact', label: 'Personne à contacter' },
      { name: 'telephoneContact', label: 'Téléphone de la personne à contacter', type: 'tel' },
      { name: 'referee', label: 'Référée par un autre centre', type: 'checkbox' },
      { name: 'refereePar', label: 'Si référée, par qui' },

      { name: '_s2', type: 'section', label: 'Procréateur' },
      { name: 'procreateurNom', label: 'Nom et prénoms' },
      { name: 'procreateurProfession', label: 'Profession' },
      { name: 'procreateurGs', label: 'Groupe sanguin / Rhésus' },
      { name: 'procreateurSerologie', label: 'Sérologie du conjoint' },

      { name: '_s3', type: 'section', label: 'Antécédents' },
      { name: 'maladies', label: 'Maladies et opérations', col: 'full' },
      { name: 'traitements', label: 'Traitements en cours', col: 'full' },
      { name: 'allergies', label: 'Allergies', col: 'full' },
      { name: 'gestite', label: 'Gestité', type: 'number', min: 0, max: 20, required: true },
      { name: 'parite', label: 'Parité', type: 'number', min: 0, max: 20, required: true },
      { name: 'avortements', label: 'Nombre d’avortements', type: 'number', min: 0 },
      { name: 'enfantsVivants', label: 'Nombre d’enfants vivants', type: 'number', min: 0 },
      { name: 'enfantsDecedes', label: 'Nombre d’enfants décédés', type: 'number', min: 0 },
      { name: 'transfusions', label: 'Transfusions antérieures', type: 'number', min: 0 },
      { name: 'ddr', label: 'Date des dernières règles (DDR)', type: 'date', required: true,
        hint: 'La date probable de l’accouchement en est déduite (280 jours).' },
      { name: 'taille', label: 'Taille (m)', type: 'number', step: 0.01, min: 1, max: 2.2 },

      { name: '_s4', type: 'section', label: 'Facteurs de surveillance — leur cumul classe la grossesse à risque' },
    ];
    (D.FACTEURS_SURVEILLANCE || []).forEach(function (f) {
      champs.push({ name: 'facteur_' + f.code, label: f.libelle, type: 'checkbox',
        value: !!((record || {}).facteurs || {})[f.code] });
    });
    champs.push({ name: '_s5', type: 'section', label: 'Suivi' });
    champs.push({ name: 'sageFemme', label: 'Sage-femme référente', type: 'select',
      options: S.collection('personnel').active()
        .filter(function (e) { return e.fonction === 'sage_femme'; })
        .map(function (e) { return { value: e.nomComplet, label: e.nomComplet }; }) });
    champs.push({ name: 'statutDossier', label: 'État du dossier', type: 'select', required: true,
      options: [{ value: 'suivi', label: 'Suivi en cours' }, { value: 'accouchee', label: 'Accouchée' },
        { value: 'clos', label: 'Clos' }] });
    return champs;
  }

  /* --------------------------------------------------------------------------
   * LE DÉTAIL DU DOSSIER — les cinq feuillets, dans l'ordre du cahier
   * ----------------------------------------------------------------------- */
  function detailDossier(d) {
    var f = facteursCoches(d);
    var cpn = S.collection('grossesses').active()
      .filter(function (g) { return g.dossierId === d.id || g.patientId === d.patientId; });
    var acc = S.collection('accouchements').active()
      .filter(function (a) { return a.dossierId === d.id || a.patientId === d.patientId; });
    var nais = S.collection('naissances').active()
      .filter(function (n) { return acc.some(function (a) { return a.id === n.accouchementId; }); });
    var parto = S.collection('partogrammes').active()
      .filter(function (x) { return x.dossierId === d.id || x.patientId === d.patientId; });
    var cpo = S.collection('cpon').active()
      .filter(function (x) { return x.patientId === d.patientId; });

    var wrap = el('div.space-y-4');

    wrap.appendChild(U.kpiGrid([
      { label: 'N° de dossier', value: d.numeroDossier, icon: 'folder-open', tone: 'navy' },
      { label: 'Gestité / Parité', value: 'G' + (d.gestite || 0) + ' P' + (d.parite || 0),
        icon: 'baby', tone: 'info' },
      { label: 'Terme prévu', value: d.dpa ? C.dateFR(d.dpa) : '—', icon: 'calendar-clock', tone: 'warning' },
      { label: 'Facteurs de surveillance', value: C.num(f.length),
        icon: f.length ? 'alert-triangle' : 'check-circle-2', tone: f.length ? 'danger' : 'success' },
    ], 'grid-cols-2 lg:grid-cols-4'));

    wrap.appendChild(U.tabs([
      { id: 'identite', label: 'Identité & antécédents', render: function () {
        return el('div.space-y-3', null, [
          U.card('Parturiente', U.descList([
            ['N° de dossier', el('span.font-mono', { text: d.numeroDossier })],
            ['Nom', d.patient], ['Dossier patient', d.patientCode],
            ['Âge', d.age ? d.age + ' ans' : '—'], ['Taille', d.taille ? d.taille + ' m' : '—'],
            ['Profession', d.profession || '—'], ['Nationalité', d.nationalite || '—'],
            ['Quartier', d.quartier || '—'], ['Téléphone', d.telephone || '—'],
            ['Personne à contacter', (d.personneContact || '—')
              + (d.telephoneContact ? ' · ' + d.telephoneContact : '')],
            ['Venue', d.referee ? 'Référée' + (d.refereePar ? ' par ' + d.refereePar : '') : 'D’elle-même'],
            ['Date d’entrée', C.dateFR(d.dateEntree)],
            ['Sage-femme référente', d.sageFemme || '—'],
          ])),
          U.card('Procréateur', U.descList([
            ['Nom et prénoms', d.procreateurNom || '—'],
            ['Profession', d.procreateurProfession || '—'],
            ['Groupe sanguin / Rhésus', d.procreateurGs || '—'],
            ['Sérologie du conjoint', d.procreateurSerologie || '—'],
          ])),
          U.card('Antécédents', U.descList([
            ['Maladies et opérations', d.maladies || 'Néant'],
            ['Traitements en cours', d.traitements || 'Néant'],
            ['Allergies', d.allergies || 'Non connues'],
            ['Gestité', String(d.gestite || 0)], ['Parité', String(d.parite || 0)],
            ['Avortements', String(d.avortements || 0)],
            ['Enfants vivants', String(d.enfantsVivants || 0)],
            ['Enfants décédés', String(d.enfantsDecedes || 0)],
            ['Transfusions antérieures', String(d.transfusions || 0)],
            ['DDR', d.ddr ? C.dateFR(d.ddr) : '—'],
            ['Date probable de l’accouchement', d.dpa ? C.dateFR(d.dpa) : '—'],
          ])),
          U.card('Facteurs de surveillance',
            f.length
              ? el('div.space-y-2', null, [
                K.note('<strong>Grossesse à risque</strong> — ' + C.num(f.length) + ' facteur(s) coché(s). '
                  + 'C’est leur CUMUL qui classe, jamais un facteur isolé.',
                { tone: 'danger', icon: 'alert-triangle' }),
                K.miniTable(['Facteur relevé'], f.map(function (x) { return [x.libelle]; })),
              ])
              : U.empty('Aucun facteur de surveillance coché.', { icon: 'check-circle-2' })),
          U.card('Examens complémentaires',
            K.miniTable(['Examen', 'Groupe', 'Résultat'],
              (D.EXAMENS_DOSSIER || []).map(function (x) {
                var v = (d.examens || {})[x.code];
                return [x.libelle, x.groupe, v == null || v === '' ? 'Non renseigné' : String(v)];
              }))),
        ]);
      } },
      { id: 'preventifs', label: 'Soins préventifs', render: function () {
        return el('div.space-y-3', null, [
          U.card('Vaccination antitétanique',
            K.miniTable(['Dose', 'Date'],
              ['VAT1', 'VAT2', 'VAT3', 'VAT4', 'VAT5'].map(function (v) {
                var dt = (d.vat || {})[v];
                return [v, dt ? C.dateFR(dt) : '—'];
              }))),
          U.card('Vulgarisation des dix droits fondamentaux',
            K.miniTable(['Droit', 'Vulgarisé'],
              (D.DROITS_FONDAMENTAUX || []).map(function (x, i) {
                return [(i + 1) + '. ' + x, (d.droits || {})[i] ? 'Oui' : '—'];
              }))),
          U.card('Plan pour l’accouchement',
            el('div.space-y-2', null, [
              K.note('Chacune de ces neuf lignes est une <strong>cause connue de retard</strong> le jour '
                + 'de l’accouchement : savoir qui décide en l’absence du mari, ou qui garde les enfants, '
                + 'évite l’heure perdue à la chercher.', { tone: 'info', icon: 'route' }),
              K.miniTable(['Point du plan', 'Arrêté'],
                (D.PLAN_ACCOUCHEMENT || []).map(function (x, i) {
                  return [x, (d.plan || {})[i] ? 'Oui' : '—'];
                })),
            ])),
          U.card('Autres soins promotionnels', U.descList([
            ['Informations sur la PF', d.infoPF || '—'],
            ['Référence pour CPN', d.referenceCPN || '—'],
            ['Référence pour accouchement', d.referenceAccouchement || '—'],
            ['Classe des mères', (d.classesMeres || []).join(' · ') || '—'],
          ])),
        ]);
      } },
      { id: 'cpn', label: 'Consultations prénatales (' + cpn.length + ')', render: function () {
        if (!cpn.length) return U.empty('Aucune consultation prénatale rattachée.', { icon: 'clipboard-list' });
        var visites = [];
        cpn.forEach(function (g) { (g.visites || []).forEach(function (v) { visites.push(v); }); });
        if (!visites.length) return U.empty('Aucune visite enregistrée.', { icon: 'clipboard-list' });
        /* LA GRILLE SE LIT EN COLONNES : une colonne par visite, les mêmes
           lignes à chaque venue — c'est ce qui donne l'ÉVOLUTION plutôt qu'un
           état. Un écran qui ne montrerait qu'une visite perdrait exactement
           l'information que le formulaire existe pour donner. */
        var groupes = {};
        (D.GRILLE_CPN || []).forEach(function (l) { (groupes[l.groupe] = groupes[l.groupe] || []).push(l); });
        var blocs = Object.keys(groupes).map(function (g) {
          var colonnes = [{ label: g, key: 'libelle' }].concat(visites.map(function (v, i) {
            return { label: 'V' + (v.n || i + 1) + (v.date ? ' — ' + C.dateFR(v.date) : ''),
              align: 'right', key: 'v' + i };
          }));
          var lignes = groupes[g].map(function (l) {
            var row = { libelle: l.libelle };
            visites.forEach(function (v, i) {
              var val = v[l.code];
              row['v' + i] = val == null || val === '' ? '—'
                : (typeof val === 'boolean' ? (val ? 'Oui' : 'Non') : String(val));
            });
            return row;
          });
          return U.card('CPN — ' + g, K.miniTable(colonnes, lignes));
        });
        return el('div.space-y-3', null, blocs);
      } },
      { id: 'accouchement', label: 'Accouchement & nouveau-né', render: function () {
        if (!acc.length) return U.empty('La parturiente n’a pas encore accouché.', { icon: 'baby' });
        return el('div.space-y-3', null, acc.map(function (a) {
          var bebes = nais.filter(function (n) { return n.accouchementId === a.id; });
          return U.card('Accouchement ' + (a.reference || ''), el('div.space-y-3', null, [
            U.descList([
              ['Date et heure', C.dateFR(a.dateHeure) + ' à ' + C.heure(a.dateHeure)],
              ['Type', a.type || '—'], ['Accoucheur', a.sageFemme || a.accoucheur || '—'],
              ['Délivrance', a.modeDelivrance || '—'],
              ['Hémorragie', a.hemorragie ? 'OUI — ' + C.num(a.quantiteSang || 0) + ' ml' : 'Non'],
              ['Issue mère', a.femmeDecedee ? 'DÉCÉDÉE' : (a.femmeReferee ? 'Référée' : 'Sortie')],
            ]),
            /* LE QUATRIÈME FEUILLET : mère et bébé sur la MÊME grille de temps.
               C'est la coïncidence des deux séries, à la même minute, qui fait
               la valeur de la feuille unique — les séparer la perdrait. */
            a.surveillance && (a.surveillance.releves || []).length
              ? U.card('Fiche de surveillance intégrée — accouchée et nouveau-né',
                K.miniTable(['Temps', 'Pouls mère', 'TA mère', 'T° mère', 'Écoulement',
                  'Globe', 'T° bébé', 'Coloration', 'Respiration', 'Allaitement'],
                a.surveillance.releves.map(function (r) {
                  return [r.temps, r.mere.pouls, r.mere.ta, r.mere.temperature, r.mere.ecoulement,
                    r.mere.globe, r.bebe.temperature, r.bebe.coloration, r.bebe.respiration,
                    r.bebe.allaitement];
                })))
              : K.note('La fiche de surveillance intégrée couvre les <strong>48 premières heures</strong> : elle n’est tenue que pour les accouchements récents.', { tone: 'info', icon: 'clock' }),
            bebes.length
              ? K.miniTable(['Sexe', 'Poids', 'Taille', 'PC', 'PT', 'Apgar 1/5/10', 'Vivant'],
                bebes.map(function (n) {
                  return [n.sexe === 'F' ? 'Féminin' : 'Masculin', n.poids + ' kg', n.taille + ' cm',
                    n.pc + ' cm', n.pt + ' cm',
                    [n.apgar1, n.apgar5, n.apgar10].join(' / '), n.vivant ? 'Oui' : 'NON'];
                }))
              : el('p.text-sm.italic.text-slate-500', { text: 'Aucun nouveau-né enregistré.' }),
          ]));
        }));
      } },
      { id: 'suites', label: 'Partogramme & suites', render: function () {
        return el('div.space-y-3', null, [
          U.card('Partogramme',
            parto.length
              ? K.miniTable(['Référence', 'Date', 'Dilatation atteinte', 'Issue'],
                parto.map(function (x) {
                  return [x.reference || '—', x.date ? C.dateFR(x.date) : '—',
                    (x.dilatationFinale || '—') + ' cm', x.issue || '—'];
                }))
              : U.empty('Aucun partogramme ouvert.', { icon: 'activity' })),
          U.card('Consultations post-natales',
            cpo.length
              ? K.miniTable(['Date', 'Type', 'HPP', 'Examen'],
                cpo.map(function (x) {
                  return [C.dateFR(x.date), x.type || '—', x.hpp ? 'OUI' : 'Non', x.examen || '—'];
                }))
              : U.empty('Aucune CPoN enregistrée.', { icon: 'stethoscope' })),
          K.note('Le dossier <strong>rassemble</strong> ce que les écrans de M4 tiennent chacun de leur '
            + 'côté : la CPN, le partogramme, l’accouchement, le nouveau-né et les CPoN. Il ne les '
            + 'duplique pas — c’est une LECTURE, et chaque geste se fait à son écran.',
          { tone: 'info', icon: 'link' }),
        ]);
      } },
    ]));
    return wrap;
  }

  /** Le dossier imprimé — la couverture du cahier. */
  function etatDossier(d) {
    var f = facteursCoches(d);
    P.etat({
      titre: 'Dossier obstétrical',
      sousTitre: 'N° ' + d.numeroDossier + ' — ' + d.patient,
      filtres: false,
      cartouche: [
        ['N° de dossier', d.numeroDossier], ['Parturiente', d.patient],
        ['Dossier patient', d.patientCode], ['Âge', d.age ? d.age + ' ans' : '—'],
        ['Date d’entrée', C.dateFR(d.dateEntree)],
        ['Gestité / Parité', 'G' + (d.gestite || 0) + ' P' + (d.parite || 0)],
        ['DDR', d.ddr ? C.dateFR(d.ddr) : '—'],
        ['Date probable de l’accouchement', d.dpa ? C.dateFR(d.dpa) : '—'],
        ['Sage-femme référente', d.sageFemme || '—'],
        ['Venue', d.referee ? 'Référée' : 'D’elle-même'],
      ],
      contenu: el('div.space-y-3', null, [
        el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Antécédents' }),
        P.tableau([{ label: 'Rubrique', key: 'r' }, { label: 'Information', key: 'v' }], [
          { r: 'Maladies et opérations', v: d.maladies || 'Néant' },
          { r: 'Traitements en cours', v: d.traitements || 'Néant' },
          { r: 'Allergies', v: d.allergies || 'Non connues' },
          { r: 'Avortements', v: String(d.avortements || 0) },
          { r: 'Enfants vivants', v: String(d.enfantsVivants || 0) },
          { r: 'Enfants décédés', v: String(d.enfantsDecedes || 0) },
          { r: 'Transfusions antérieures', v: String(d.transfusions || 0) },
        ]),
        el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Facteurs de surveillance' }),
        f.length
          ? P.tableau([{ label: 'Facteur relevé', key: 'l' }],
            f.map(function (x) { return { l: x.libelle }; }))
          : el('p.text-\\[10px\\].italic', { text: 'Aucun facteur de surveillance coché.' }),
        el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Examens complémentaires' }),
        P.tableau([{ label: 'Examen', key: 'l' }, { label: 'Groupe', key: 'g' },
          { label: 'Résultat', key: 'v' }],
        (D.EXAMENS_DOSSIER || []).map(function (x) {
          var v = (d.examens || {})[x.code];
          return { l: x.libelle, g: x.groupe, v: v == null || v === '' ? 'Non renseigné' : String(v) };
        })),
        el('p.mt-3.text-\\[10px\\].italic', {
          text: 'Formulaire national « DOSSIER OBSTÉTRICAL » — Ministère de la Santé, République du '
            + 'Bénin. Le numéro de dossier suit le registre papier de la maternité.',
        }),
      ]),
      signatures: [{ role: 'La Sage-femme', nom: d.sageFemme || '' },
        { role: 'Le Médecin', mention: 'Visa' }],
    });
  }

})(window);