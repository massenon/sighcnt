/* =============================================================================
 * M3 — Hospitalisation
 * -----------------------------------------------------------------------------
 * CDCT §10.4 — admissions, gestion des lits et chambres (nomenclature A1 LIT1,
 * VIP et VVIP), feuille de température numérique, sorties normales et contre
 * avis médical.
 * Règles : RG-06 (solde apuré avant sortie), RG-07 (triple signature :
 * patient, infirmier traitant, constat du gardien), RG-08 (sortie contre avis
 * médical motivée, avis du Procureur le cas échéant).
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  function admissions() { return S.collection('admissions').active(); }
  function enCours() { return admissions().filter(function (a) { return a.statut === 'en_cours'; }); }
  function patients() { return S.collection('patients').active(); }
  function factures() { return S.collection('factures').active(); }

  function tousLits() {
    var out = [];
    D.CHAMBRES.forEach(function (ch) {
      ch.lits.forEach(function (l) { out.push({ chambre: ch, lit: l }); });
    });
    return out;
  }
  function litOccupePar(codeLit) {
    return enCours().filter(function (a) { return a.lit === codeLit; })[0] || null;
  }
  function soldePatient(patientId) {
    return C.sum(factures().filter(function (f) { return f.patientId === patientId; }), 'reliquat');
  }
  function dureeSejour(a) {
    return C.daysBetween(a.dateEntree, a.dateSortie || AUJ);
  }

  function optionsPatients() {
    return C.sortBy(patients(), 'code').map(function (p) {
      return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
    });
  }
  function optionsLitsLibres(courant) {
    return tousLits().filter(function (s) {
      return !litOccupePar(s.lit.label) || s.lit.label === courant;
    }).map(function (s) {
      return { value: s.lit.label, label: s.lit.label + ' — ' + s.chambre.aile + ' (' + typeChambre(s.chambre.type) + ')' };
    });
  }
  function typeChambre(id) {
    var t = D.TYPES_CHAMBRE.filter(function (x) { return x.id === id; })[0];
    return t ? t.label : id;
  }
  function optionsMedecinsObs() {
    return S.collection('personnel').active()
      .filter(function (e) { return e.fonction === 'medecin'; })
      .map(function (e) { return { value: e.nomComplet, label: e.nomComplet }; });
  }
  /* E361 : cette liste portait le nom « optionsSoignants », que la déclaration de l'outillage commun (plus bas : soignants + identifiants)
     écrasait — l'infirmier référent d'une admission s'enregistrait sous un IDENTIFIANT de soignant (« SOI07 »), médecins compris, là où toutes
     les pièces lisent un NOM. */
  function optionsInfirmiersNom() {
    return S.collection('personnel').active()
      .filter(function (e) { return ['infirmier', 'sage_femme', 'aide_soignant'].indexOf(e.fonction) !== -1; })
      .map(function (e) { return { value: e.nomComplet, label: e.nomComplet + ' — ' + e.poste }; });
  }

  /* ==========================================================================
   * MISE EN OBSERVATION
   * --------------------------------------------------------------------------
   * Hospitalisation de courte durée — vingt-quatre heures en médecine générale —
   * pour surveiller un état, poser un diagnostic ou attendre l'évolution des
   * symptômes avant de décider d'un traitement ou d'une sortie.
   *
   * Ce que l'informatisation apporte, et que le papier ne donnait pas :
   *   — la TRAÇABILITÉ : heure d'entrée, évolution horodatée des constantes ;
   *   — la COORDINATION : le médecin et l'infirmier lisent la même feuille ;
   *   — la GESTION DES PLACES : on sait qui occupe quoi et depuis combien de
   *     temps, donc quand libérer ou transférer.
   *
   * L'observation n'est pas une admission : elle a sa propre unité, sa propre
   * durée de référence et sa propre décision de sortie. La confondre avec
   * l'hospitalisation ferait disparaître exactement ce qu'on veut suivre.
   * ======================================================================== */
  function colObs() { return S.collection('observations', { module: 'M3', entite: 'mise en observation', prefix: 'OBS' }); }
  function observations() { return colObs().active(); }
  function enObservation() {
    return observations().filter(function (o) { return o.statutObservation === 'en_cours'; });
  }

  /** Heures écoulées depuis l'entrée — le compteur que tout le monde regarde. */
  function heuresEcoulees(o) {
    var fin = o.dateSortie ? C.toDate(o.dateSortie) : new Date();
    return Math.max(0, Math.round((fin - C.toDate(o.dateEntree)) / 3600000));
  }
  function depasse(o) { return heuresEcoulees(o) > D.DUREE_OBSERVATION_REFERENCE; }

  /* E362 : le bouton « Mettre en observation » de l'en-tête appelait `admettre()`, déclarée dans la fermeture de l'écran — ReferenceError au
     clic (même défaut que « nouvelleVisite », Bug 0a). Le rendu pose ici l'ouverture de la fenêtre, l'en-tête l'appelle. */
  var ouvrirAdmissionObservation = null;

  function orientationDe(id) {
    return D.ORIENTATIONS_OBSERVATION.filter(function (x) { return x.id === id; })[0] || null;
  }

  /* Jeu d'amorçage : quelques patients en salle, d'autres déjà orientés. */
  function amorcerObservations() {
    var db = S.raw();
    if ((db.observations && db.observations.length) || !S.amorcable('observations')) return;
    var pats = S.collection('patients').active();
    var infs = S.collection('personnel').active().filter(function (e) { return e.fonction === 'infirmier'; });
    var meds = S.collection('personnel').active().filter(function (e) { return e.fonction === 'medecin'; });
    if (!pats.length || !infs.length || !meds.length) return;   /* répertoire vide : rien à amorcer */
    var rnd = C.seeded(311);
    var out = [];
    for (var i = 0; i < 18; i++) {
      var p = C.pick(rnd, pats);
      var unite = C.pick(rnd, D.UNITES_OBSERVATION);
      var enCours = i < 6;
      var entree = new Date(AUJ.getTime() - C.between(rnd, enCours ? 1 : 30, enCours ? 30 : 720) * 3600000);
      var orient = enCours ? null : C.pick(rnd, D.ORIENTATIONS_OBSERVATION);
      var constantes = [];
      var n = C.between(rnd, 2, 5);
      for (var k = 0; k < n; k++) {
        constantes.push({
          heure: new Date(entree.getTime() + k * 4 * 3600000).toISOString(),
          temperature: (36.4 + rnd() * 2.4).toFixed(1),
          tension: C.between(rnd, 9, 15) + '/' + C.between(rnd, 5, 10),
          pouls: C.between(rnd, 58, 118),
          spo2: C.between(rnd, 92, 100),
          observation: C.pick(rnd, ['Patient conscient, orienté', 'Douleur en diminution', 'Sous perfusion', 'Vomissements', 'Repos', 'Surveillance rapprochée']),
          par: C.pick(rnd, infs).nomComplet,
        });
      }
      out.push({
        id: 'OBS' + C.pad(i + 1, 4), statut: 'actif',
        reference: 'OBS-2026-' + C.pad(i + 1, 4),
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        unite: unite.id, uniteLabel: unite.label,
        place: unite.label.slice(-10) + ' — place ' + ((i % unite.places) + 1),
        motif: C.pick(rnd, ['Douleur thoracique', 'Traumatisme crânien léger', 'Malaise', 'Fièvre à explorer',
          'Douleur abdominale', 'Suspicion de paludisme grave', 'Vomissements répétés']),
        dateEntree: entree.toISOString(),
        dateSortie: enCours ? null : new Date(entree.getTime() + C.between(rnd, 6, 30) * 3600000).toISOString(),
        medecin: C.pick(rnd, meds).nomComplet,
        infirmier: C.pick(rnd, infs).nomComplet,
        constantes: constantes,
        statutObservation: enCours ? 'en_cours' : 'clos',
        orientation: orient ? orient.id : null,
        orientationLabel: orient ? orient.label : null,
        conclusion: orient ? C.pick(rnd, ['Évolution favorable', 'État stabilisé', 'Aggravation constatée', 'Diagnostic posé']) : null,
      });
    }
    db.observations = out;
    S.save();
  }

  global.SIGH.screen('m3-observation', {
    title: 'Mise en observation',
    description: 'Surveillance de courte durée : admission en unité d’observation, feuille de constantes, prescriptions ciblées et orientation de sortie.',
    regle: 'L’observation est une <strong>hospitalisation de courte durée</strong> — vingt-quatre heures de '
      + 'référence en médecine générale — destinée à surveiller un état, poser un diagnostic ou attendre '
      + 'l’évolution des symptômes. Elle se termine par une <strong>décision d’orientation</strong> : sortie '
      + 'définitive, hospitalisation complète, transfert ou bloc. Un séjour qui dépasse la durée de '
      + 'référence est signalé — il appelle une décision, pas un oubli.',
    actions: function () {
      return [
        K.btn('Plan des lits', { icon: 'layout-grid', onclick: function () { global.SIGH.app.go('m3-plan-lits'); } }),
        K.btn('Feuille de soins', { icon: 'heart-pulse', onclick: function () { global.SIGH.app.go('m3-soins'); } }),
        K.btn('Mettre en observation', { variant: 'primary', icon: 'user-plus', onclick: function () { if (ouvrirAdmissionObservation) ouvrirAdmissionObservation(); } }),
      ];
    },
    render: function (root) {
      ouvrirAdmissionObservation = function () { admettre(); };   /* E362 */
      amorcerObservations();
      dessiner();
      return null;

      function dessiner() {
        C.clear(root);
        var toutes = observations();
        var actives = enObservation();
        var depassements = actives.filter(depasse);
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Patients en observation', value: C.num(actives.length), icon: 'activity', tone: 'navy' },
          {
            label: 'Au-delà de ' + D.DUREE_OBSERVATION_REFERENCE + ' h',
            value: C.num(depassements.length), icon: 'alarm-clock',
            tone: depassements.length ? 'danger' : 'success',
            hint: depassements.length ? 'Décision d’orientation attendue' : 'Aucun dépassement',
          },
          {
            label: 'Durée moyenne',
            value: actives.length ? Math.round(C.sum(actives, heuresEcoulees) / actives.length) + ' h' : '—',
            icon: 'clock', tone: 'info',
          },
          { label: 'Séjours clos', value: C.num(toutes.length - actives.length), icon: 'check-circle-2', tone: 'neutral' },
        ]));

        if (depassements.length) {
          host.appendChild(K.note('<strong>' + depassements.length + ' patient(s) en observation depuis plus de '
            + D.DUREE_OBSERVATION_REFERENCE + ' heures.</strong> L’observation n’est pas une hospitalisation : '
            + 'au-delà de la durée de référence, une orientation doit être décidée — sortie, hospitalisation '
            + 'complète ou transfert.', { tone: 'danger', icon: 'alarm-clock' }));
        }

        /* Occupation des unités : combien de places, combien occupées. */
        var occupation = D.UNITES_OBSERVATION.map(function (u) {
          var n = actives.filter(function (o) { return o.unite === u.id; }).length;
          return { unite: u.label, occupees: n, places: u.places, libres: Math.max(0, u.places - n) };
        });
        host.appendChild(U.card('Occupation des unités d’observation', K.miniTable([
          { label: 'Unité', key: 'unite' },
          { label: 'Occupées', align: 'right', render: function (r) { return String(r.occupees); } },
          { label: 'Places', align: 'right', render: function (r) { return String(r.places); } },
          {
            label: 'Disponibilité',
            render: function (r) {
              return r.libres > 0
                ? U.badge(r.libres + ' libre(s)', 'success')
                : U.badge('Complète', 'danger');
            },
          },
        ], occupation)));

        host.appendChild(U.tabs([
          { id: 'encours', label: 'En observation', badge: actives.length, render: function (p) { table(p, actives, true); return null; } },
          { id: 'clos', label: 'Séjours clos', badge: toutes.length - actives.length, render: function (p) { table(p, toutes.filter(function (o) { return o.statutObservation !== 'en_cours'; }), false); return null; } },
        ]));

        root.appendChild(host);
        U.icons(root);
      }

      function table(panneau, rows, actives) {
        panneau.appendChild(U.dataTable({
          rows: rows, exportName: 'observations', pageSize: 12, searchable: true,
          defaultSort: 'dateEntree', defaultDir: 'desc',
          emptyMessage: actives ? 'Aucun patient en observation.' : 'Aucun séjour clos.',
          filters: [{ name: 'unite', label: 'Unité', options: D.UNITES_OBSERVATION.map(function (u) { return { value: u.id, label: u.label }; }) }],
          columns: [
            { key: 'reference', label: 'N°', nowrap: true, render: function (o) { return el('span.font-mono.text-xs', { text: o.reference }); } },
            {
              key: 'patient', label: 'Patient',
              render: function (o) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: o.patient }),
                  el('p.font-mono.text-xs.text-slate-400', { text: o.patientCode }),
                ]);
              },
            },
            { key: 'motif', label: 'Motif de surveillance' },
            { key: 'uniteLabel', label: 'Unité', render: function (o) { return U.badge(o.uniteLabel.replace('Salle d’observation — ', ''), 'navy'); } },
            {
              key: 'dateEntree', label: 'Entrée', nowrap: true,
              text: function (o) { return C.dateFR(o.dateEntree) + ' ' + C.heure(o.dateEntree); },
              render: function (o) {
                return el('div', null, [
                  el('p.text-sm.text-slate-700', { text: C.dateFR(o.dateEntree) }),
                  el('p.text-xs.text-slate-400', { text: C.heure(o.dateEntree) }),
                ]);
              },
              sortValue: function (o) { return C.toDate(o.dateEntree).getTime(); },
            },
            {
              key: 'duree', label: 'Durée', align: 'right',
              value: heuresEcoulees,
              render: function (o) {
                var h = heuresEcoulees(o);
                return el('span.num', {
                  class: depasse(o) && o.statutObservation === 'en_cours' ? 'font-semibold text-danger-600' : 'text-slate-600',
                  text: h + ' h',
                });
              },
            },
            {
              key: 'constantes', label: 'Constantes', align: 'right',
              value: function (o) { return (o.constantes || []).length; },
              render: function (o) { return String((o.constantes || []).length) + ' relevé(s)'; },
            },
            {
              key: 'orientation', label: 'Issue',
              text: function (o) { return o.orientationLabel || 'en cours'; },
              render: function (o) {
                if (o.statutObservation === 'en_cours') return U.badge('En observation', 'info');
                var or = orientationDe(o.orientation);
                return or ? U.badge(or.label.split(' — ')[0], or.tone) : U.badge('Clos', 'neutral');
              },
            },
          ],
          onRowClick: fiche,
          rowActions: function (o) {
            if (o.statutObservation !== 'en_cours') {
              return [K.iconBtn('printer', 'Imprimer la feuille', function () { imprimer(o); })];
            }
            return [
              K.iconBtn('thermometer', 'Relever les constantes', function () { relever(o); }),
              K.iconBtn('log-out', 'Décider de l’orientation', function () { orienter(o); }),
              K.iconBtn('printer', 'Imprimer la feuille', function () { imprimer(o); }),
            ];
          },
        }));
        U.icons(panneau);
      }

      /* --- Admission en observation -------------------------------------- */
      function admettre() {
        var f = U.form([
          { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, col: 'full', options: optionsPatients() },
          { name: 'motif', label: 'Motif de surveillance', required: true, col: 'full', help: 'Douleur thoracique, traumatisme crânien léger, malaise…' },
          {
            name: 'unite', label: 'Unité d’observation', type: 'select', required: true,
            options: D.UNITES_OBSERVATION.map(function (u) {
              var n = enObservation().filter(function (o) { return o.unite === u.id; }).length;
              return { value: u.id, label: u.label + ' (' + Math.max(0, u.places - n) + ' place(s) libre(s))' };
            }),
          },
          { name: 'place', label: 'Place occupée', help: 'Identifiant de la place dans l’unité.' },
          { name: 'dateEntree', label: 'Heure d’entrée', type: 'datetime-local', required: true, value: C.isoLocal() },
          { name: 'medecin', label: 'Médecin responsable', type: 'select', required: true, options: optionsMedecinsObs() },
          { name: 'infirmier', label: 'Infirmier de surveillance', type: 'select', options: optionsInfirmiersNom() },
        ], {});

        var m = U.modal({
          title: 'Mettre un patient en observation', size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('L’heure d’entrée est <strong>tracée</strong> : c’est elle qui fait courir la durée de '
              + 'référence et déclenche l’alerte au-delà de ' + D.DUREE_OBSERVATION_REFERENCE + ' heures.', { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Mettre en observation', {
              variant: 'primary', icon: 'activity',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var p = patients().filter(function (x) { return x.code === v.patientCode; })[0];
                var u = D.UNITES_OBSERVATION.filter(function (x) { return x.id === v.unite; })[0];
                var res = colObs().insert({
                  reference: 'OBS-2026-' + C.pad(colObs().all().length + 1, 4),
                  patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
                  unite: v.unite, uniteLabel: u ? u.label : v.unite, place: v.place || null,
                  motif: v.motif,
                  dateEntree: new Date(v.dateEntree).toISOString(), dateSortie: null,
                  medecin: v.medecin, infirmier: v.infirmier || null,
                  constantes: [], statutObservation: 'en_cours',
                  orientation: null, orientationLabel: null, conclusion: null,
                });
                m.close(); dessiner();
                U.toast(p.nom + ' ' + p.prenom + ' mis(e) en observation.', {
                  type: 'success',
                  detail: (u ? u.label : '') + ' — entrée à ' + C.heure(res.record.dateEntree),
                  undo: function () { res.undo(); dessiner(); },
                });
              },
            }),
          ],
        });
      }

      /* --- Feuille de surveillance ---------------------------------------- */
      function relever(o) {
        var f = U.form([
          { name: 'heure', label: 'Heure du relevé', type: 'datetime-local', required: true, value: C.isoLocal() },
          { name: 'temperature', label: 'Température (°C)', type: 'number', step: '0.1', required: true },
          { name: 'tension', label: 'Tension artérielle', required: true, placeholder: '12/8' },
          { name: 'pouls', label: 'Pouls (bpm)', type: 'number', required: true },
          { name: 'spo2', label: 'Saturation SpO₂ (%)', type: 'number', min: 0, max: 100 },
          { name: 'observation', label: 'Observation clinique', type: 'textarea', rows: 2, col: 'full' },
          { name: 'par', label: 'Relevé par', required: true, value: S.currentUser() },
        ], {});

        var m = U.modal({
          title: 'Relevé de constantes — ' + o.patient,
          subtitle: o.reference + ' · ' + heuresEcoulees(o) + ' h d’observation',
          size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer le relevé', {
              variant: 'primary', icon: 'thermometer',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var suite = (o.constantes || []).concat([{
                  heure: new Date(v.heure).toISOString(),
                  temperature: v.temperature, tension: v.tension, pouls: v.pouls,
                  spo2: v.spo2 || null, observation: v.observation || '', par: v.par,
                }]);
                var res = colObs().update(o.id, { constantes: suite });
                m.close(); dessiner();
                U.toast('Constantes relevées à ' + C.heure(v.heure) + '.', {
                  type: 'success', detail: v.temperature + ' °C · ' + v.tension + ' · ' + v.pouls + ' bpm',
                  undo: function () { res.undo(); dessiner(); },
                });
              },
            }),
          ],
        });
      }

      /* --- Orientation de sortie ------------------------------------------ */
      function orienter(o) {
        var f = U.form([
          {
            name: 'orientation', label: 'Décision d’orientation', type: 'select', required: true, col: 'full',
            options: D.ORIENTATIONS_OBSERVATION.map(function (x) { return { value: x.id, label: x.label }; }),
          },
          { name: 'conclusion', label: 'Conclusion de la surveillance', required: true, col: 'full' },
          { name: 'dateSortie', label: 'Heure de sortie d’observation', type: 'datetime-local', required: true, value: C.isoLocal() },
          { name: 'medecin', label: 'Décision prise par', required: true, value: o.medecin },
          { name: 'destination', label: 'Établissement de destination', col: 'full', help: 'À renseigner en cas de transfert.' },
        ], {});

        var m = U.modal({
          title: 'Orientation à l’issue de l’observation',
          subtitle: o.patient + ' — ' + heuresEcoulees(o) + ' h de surveillance', size: 'lg',
          body: el('div.space-y-3', null, [
            U.descList([
              ['Motif de surveillance', o.motif],
              ['Unité', o.uniteLabel],
              ['Entrée', C.dateFR(o.dateEntree) + ' à ' + C.heure(o.dateEntree)],
              ['Relevés de constantes', C.num((o.constantes || []).length)],
            ]),
            f,
            K.note('Une <strong>hospitalisation complète</strong> ouvre une admission dans le module M3 : '
              + 'l’observation se termine, le séjour commence, et les deux restent distincts au dossier.',
            { tone: 'info' }),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer la décision', {
              variant: 'primary', icon: 'log-out',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var or = orientationDe(v.orientation);
                var res = colObs().update(o.id, {
                  statutObservation: 'clos',
                  orientation: v.orientation, orientationLabel: or ? or.label : v.orientation,
                  conclusion: v.conclusion,
                  dateSortie: new Date(v.dateSortie).toISOString(),
                  decidePar: v.medecin, destination: v.destination || null,
                });

                /* L'hospitalisation complète ouvre une admission : la place
                   d'observation se libère, le séjour est un autre objet. */
                var suite = null;
                if (v.orientation === 'hospitalisation') {
                  suite = S.collection('admissions', { module: 'M3', entite: 'Admission' }).insert({
                    reference: C.referenceSuivante('H', 5, S.collection('admissions').all()),
                    patientId: o.patientId, patient: o.patient, patientCode: o.patientCode,
                    dateEntree: C.iso(new Date(v.dateSortie)), dateSortie: null,
                    diagnosticEntree: v.conclusion, symptomes: o.motif,
                    priseEnCharge: 'plus_8h', infirmier: o.infirmier,
                    statut: 'en_cours', origineObservation: o.reference,
                  });
                }

                S.log('Orientation d’observation', 'M3', 'Observation', o.reference,
                  { statut: 'en_cours' }, { orientation: v.orientation, duree: heuresEcoulees(o) + ' h' });

                m.close(); dessiner();
                U.toast('Orientation enregistrée — ' + (or ? or.label : v.orientation) + '.', {
                  type: 'success', duration: 6000,
                  detail: suite ? 'Admission ' + suite.record.reference + ' ouverte en hospitalisation.' : null,
                  undo: function () { res.undo(); if (suite) suite.undo(); dessiner(); },
                });
              },
            }),
          ],
        });
      }

      /* --- Fiche complète -------------------------------------------------- */
      function fiche(o) {
        var corps = el('div.space-y-4');
        corps.appendChild(U.descList([
          ['Référence', o.reference], ['Patient', o.patient], ['Dossier', o.patientCode],
          ['Motif de surveillance', o.motif], ['Unité', o.uniteLabel], ['Place', o.place || '—'],
          ['Entrée', C.dateFR(o.dateEntree) + ' à ' + C.heure(o.dateEntree)],
          ['Durée', heuresEcoulees(o) + ' h' + (depasse(o) && o.statutObservation === 'en_cours' ? ' — au-delà de la référence' : '')],
          ['Médecin responsable', o.medecin], ['Infirmier de surveillance', o.infirmier || '—'],
          ['Issue', o.orientationLabel || 'en cours'],
        ]));

        var cs = (o.constantes || []).slice().sort(function (a, b) {
          return C.toDate(a.heure) - C.toDate(b.heure);
        });
        corps.appendChild(U.card('Feuille de surveillance', cs.length
          ? K.miniTable([
            { label: 'Heure', render: function (c) { return C.dateFR(c.heure) + ' ' + C.heure(c.heure); } },
            { label: 'T°', align: 'right', render: function (c) { return c.temperature + ' °C'; } },
            { label: 'TA', align: 'right', key: 'tension' },
            { label: 'Pouls', align: 'right', render: function (c) { return c.pouls + ' bpm'; } },
            { label: 'SpO₂', align: 'right', render: function (c) { return c.spo2 ? c.spo2 + ' %' : '—'; } },
            { label: 'Observation', key: 'observation' },
            { label: 'Relevé par', key: 'par' },
          ], cs)
          : U.empty('Aucun relevé enregistré.', { icon: 'thermometer' }),
        o.statutObservation === 'en_cours'
          ? [K.btn('Relever les constantes', { size: 'sm', variant: 'primary', icon: 'thermometer', onclick: function () { relever(o); } })]
          : null));

        if (cs.length > 1) {
          corps.appendChild(U.card('Évolution', G.ligne(
            cs.map(function (c) { return C.heure(c.heure); }),
            [{ label: 'Température (°C)', data: cs.map(function (c) { return Number(c.temperature); }) },
              { label: 'Pouls (bpm)', data: cs.map(function (c) { return Number(c.pouls); }), fill: false }]
          )));
        }

        var pied = [K.btn('Imprimer la feuille', { icon: 'printer', onclick: function () { imprimer(o); } })];
        if (o.statutObservation === 'en_cours') {
          pied.unshift(K.btn('Prescrire', { icon: 'file-plus', onclick: function () { prescrire(o); } }));
          pied.push(K.btn('Décider de l’orientation', { variant: 'primary', icon: 'log-out', onclick: function () { orienter(o); } }));
        }

        U.drawer({
          title: o.reference, subtitle: o.patient + ' — ' + o.uniteLabel,
          width: 'max-w-3xl', body: corps, footer: pied,
        });
      }

      /* --- Prescriptions ciblées ------------------------------------------- */
      function prescrire(o) {
        var f = U.form([
          {
            name: 'analyses', label: 'Examens biologiques', type: 'multiselect', col: 'full',
            options: D.ANALYSES.map(function (a) {
              return { value: a.code, label: a.designation, detail: a.categorie + ' · ' + a.delai };
            }),
            help: 'Bilans de contrôle demandés pendant la surveillance.',
          },
          {
            name: 'actes', label: 'Soins rapides', type: 'multiselect', col: 'full',
            options: S.collection('actes').active()
              .filter(function (a) { return /Soins|Médecine générale/.test(a.secteur); })
              .map(function (a) { return { value: a.code, label: a.libelle, detail: a.secteur }; }),
          },
        ], {});

        var m = U.modal({
          title: 'Prescrire pendant l’observation', subtitle: o.patient, size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('Prescriptions <strong>ciblées</strong> : bilans de contrôle et soins rapides, adressés '
              + 'immédiatement au laboratoire et à la salle de soins comme toute prescription.', { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Prescrire et transmettre', {
              variant: 'primary', icon: 'send',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                if (!(v.analyses || []).length && !(v.actes || []).length) {
                  U.toast('Choisir au moins un examen ou un soin.', { type: 'warning' });
                  return;
                }
                var res;
                try {
                  res = PR.prescrire({
                    patientCode: o.patientCode, medecin: o.medecin,
                    diagnostic: 'Observation — ' + o.motif,
                    analyses: v.analyses || [], actes: v.actes || [], medicaments: [],
                    secteurDemandeur: o.uniteLabel,
                  });
                } catch (e) {
                  U.toast('Prescription impossible : ' + e.message, { type: 'error' });
                  return;
                }
                m.close();
                U.toast('Prescription ' + res.ordonnance.numero + ' transmise.', {
                  type: 'success', duration: 6000,
                  detail: res.demandes.length + ' examen(s) au laboratoire · facture ' + res.facture.numero + ' à la caisse',
                });
              },
            }),
          ],
        });
      }

      function imprimer(o) {
        var cs = (o.constantes || []).slice().sort(function (a, b) { return C.toDate(a.heure) - C.toDate(b.heure); });
        P.etat({
          titre: 'Feuille de mise en observation',
          sousTitre: o.reference + ' — ' + o.patient,
          cartouche: [['Patient', o.patient], ['Dossier', o.patientCode],
            ['Motif de surveillance', o.motif], ['Unité', o.uniteLabel],
            ['Entrée', C.dateFR(o.dateEntree) + ' à ' + C.heure(o.dateEntree)],
            ['Durée de surveillance', heuresEcoulees(o) + ' h'],
            ['Médecin responsable', o.medecin],
            ['Issue', o.orientationLabel || 'Surveillance en cours']],
          contenu: el('div.space-y-3', null, [
            cs.length ? P.tableau([
              { label: 'Heure', value: function (c) { return C.dateFR(c.heure) + ' ' + C.heure(c.heure); } },
              { label: 'Température', align: 'right', value: function (c) { return c.temperature + ' °C'; } },
              { label: 'Tension', align: 'right', key: 'tension' },
              { label: 'Pouls', align: 'right', value: function (c) { return c.pouls + ' bpm'; } },
              { label: 'SpO₂', align: 'right', value: function (c) { return c.spo2 ? c.spo2 + ' %' : '—'; } },
              { label: 'Observation', key: 'observation' },
              { label: 'Relevé par', key: 'par' },
            ], cs) : el('p.text-\\[10px\\].italic.text-slate-500', { text: 'Aucun relevé de constantes enregistré.' }),
            o.conclusion ? el('p.mt-3.text-\\[10px\\]', null, [
              el('span.font-semibold', { text: 'Conclusion : ' }), el('span', { text: o.conclusion }),
            ]) : null,
          ]),
          signatures: [{ role: 'L’infirmier de surveillance', nom: o.infirmier || '' },
            { role: 'Le médecin responsable', nom: o.medecin }],
        });
      }

    },
  });

  /* ==========================================================================
   * PLAN DES LITS
   * ======================================================================== */
  global.SIGH.screen('m3-plan-lits', {
    title: 'Plan des lits',
    description: 'Visualisation graphique de l’occupation par aile, chambre et lit — nomenclature A1 LIT1, chambres VIP et VVIP.',
    render: function (root) {
      var host = el('div.space-y-4');
      var lits = tousLits();
      var occupes = enCours();

      host.appendChild(U.kpiGrid([
        { label: 'Lits installés', value: C.num(lits.length), icon: 'bed', tone: 'neutral' },
        { label: 'Lits occupés', value: C.num(occupes.length), icon: 'bed-double', tone: 'danger' },
        { label: 'Lits libres', value: C.num(lits.length - occupes.length), icon: 'bed-single', tone: 'success' },
        { label: 'Taux d’occupation', value: C.pct(occupes.length / lits.length * 100), icon: 'gauge', tone: 'navy' },
      ]));

      /* Légende */
      host.appendChild(el('div.flex.flex-wrap.items-center.gap-4.rounded-lg.border.border-slate-200.bg-white.px-4.py-2\\.5', null, [
        el('span.text-xs.font-medium.text-slate-500', { text: 'Légende :' }),
        legende('bg-success-500', 'Libre'),
        legende('bg-danger-500', 'Occupé'),
        legende('bg-warning-500', 'Sortie prévue (séjour > 5 jours)'),
      ]));

      /* Plan par aile */
      var parAile = C.groupBy(D.CHAMBRES, 'aile');
      Object.keys(parAile).forEach(function (aile) {
        var chambres = parAile[aile];
        var grille = el('div.grid.gap-3', { class: 'sm:grid-cols-2 lg:grid-cols-4' });
        chambres.forEach(function (ch) {
          var carte = el('div.rounded-xl.border.border-slate-200.bg-white.p-3.shadow-card');
          var head = el('div.mb-2\\.5.flex.items-center.justify-between');
          head.appendChild(el('span.text-sm.font-semibold.text-slate-800', { text: 'Chambre ' + ch.code }));
          head.appendChild(U.badge(typeChambre(ch.type), ch.type === 'vvip' ? 'navy' : (ch.type === 'vip' ? 'info' : 'neutral')));
          carte.appendChild(head);

          ch.lits.forEach(function (l) {
            var adm = litOccupePar(l.label);
            var sortiePrevue = adm && dureeSejour(adm) > 5;
            var couleur = !adm ? 'bg-success-500' : (sortiePrevue ? 'bg-warning-500' : 'bg-danger-500');
            var bloc = el('button.mb-1\\.5.flex.w-full.items-center.gap-2\\.5.rounded-lg.border.border-slate-200.p-2.text-left.transition-colors.hover\\:border-navy-300.hover\\:bg-navy-50', {
              type: 'button',
              onclick: function () { ouvrirLit(ch, l, adm); },
            });
            bloc.appendChild(el('span.h-2\\.5.w-2\\.5.shrink-0.rounded-full', { class: couleur }));
            var info = el('span.min-w-0.flex-1');
            info.appendChild(el('span.block.font-mono.text-xs.font-semibold.text-slate-700', { text: l.label }));
            info.appendChild(el('span.block.truncate.text-\\[11px\\].text-slate-500', {
              text: adm ? adm.patient : 'Disponible',
            }));
            bloc.appendChild(info);
            if (adm) bloc.appendChild(el('span.shrink-0.text-\\[10px\\].num.text-slate-400', { text: dureeSejour(adm) + ' j' }));
            carte.appendChild(bloc);
          });
          grille.appendChild(carte);
        });
        host.appendChild(U.card(aile, grille));
      });

      host.appendChild(K.charts([
        {
          title: 'Occupation par type de chambre',
          render: function () {
            var types = D.TYPES_CHAMBRE.map(function (t) {
              var l = lits.filter(function (s) { return s.chambre.type === t.id; });
              var o = l.filter(function (s) { return !!litOccupePar(s.lit.label); });
              return { label: t.label, total: l.length, occupes: o.length };
            });
            return G.barres(types.map(function (t) { return t.label; }), [
              { label: 'Occupés', data: types.map(function (t) { return t.occupes; }), color: G.TONES.rouge },
              { label: 'Libres', data: types.map(function (t) { return t.total - t.occupes; }), color: G.TONES.vert },
            ], { stack: true });
          },
        },
        {
          title: 'Durée moyenne de séjour (12 mois)',
          render: function () {
            var termines = admissions().filter(function (a) { return a.dateSortie; });
            var m = K.parMois(termines, 'dateEntree');
            var moy = m.labels.map(function (_, i) {
              var mois = termines.filter(function (a) {
                var d = C.toDate(a.dateEntree);
                var diff = (AUJ.getFullYear() - d.getFullYear()) * 12 + (AUJ.getMonth() - d.getMonth());
                return 11 - diff === i;
              });
              return mois.length ? Math.round(C.sum(mois, dureeSejour) / mois.length * 10) / 10 : 0;
            });
            return G.ligne(m.labels, [{ label: 'Jours', data: moy, color: G.TONES.navy }]);
          },
        },
      ]));

      root.appendChild(host);
      return null;

      function legende(cls, texte) {
        return el('span.flex.items-center.gap-1\\.5', null, [
          el('span.h-2\\.5.w-2\\.5.rounded-full', { class: cls }),
          el('span.text-xs.text-slate-600', { text: texte }),
        ]);
      }

      function ouvrirLit(ch, l, adm) {
        if (!adm) {
          U.drawer({
            title: 'Lit ' + l.label, subtitle: ch.aile + ' — ' + typeChambre(ch.type),
            body: el('div.space-y-4', null, [
              U.descList([['Chambre', ch.code], ['Lit', l.label], ['Type', typeChambre(ch.type)],
                ['Tarif journalier', C.money(D.TYPES_CHAMBRE.filter(function (t) { return t.id === ch.type; })[0].tarif)],
                ['État', U.badge('Libre', 'success')]]),
              U.empty('Ce lit est disponible pour une nouvelle admission.', { icon: 'bed' }),
            ]),
            footer: [K.lien('m3-admissions', 'Créer une admission', { variant: 'primary', icon: 'user-plus' })],
          });
          return;
        }
        var solde = soldePatient(adm.patientId);
        U.drawer({
          title: adm.patient, subtitle: adm.patientCode + ' — Lit ' + adm.lit,
          body: el('div.space-y-4', null, [
            U.descList([
              ['Dossier', el('span.font-mono', { text: adm.patientCode })],
              ['Lit', adm.lit], ['Chambre', typeChambre(adm.typeChambre)],
              ['Date d’entrée', C.dateFR(adm.dateEntree)],
              ['Durée de séjour', dureeSejour(adm) + ' jour(s)'],
              ['Diagnostic d’entrée', adm.diagnosticEntree],
              ['Prise en charge', U.statut(adm.priseEnCharge)],
              ['Infirmier référent', adm.infirmier],
            ]),
            solde > 0
              ? K.note('<strong>RG-06</strong> — Solde restant dû de <strong>' + C.money(solde)
                + '</strong>. La sortie ne pourra être finalisée qu’après apurement, sauf dérogation motivée de la Direction.', { tone: 'warning', icon: 'wallet' })
              : K.note('<strong>RG-06</strong> — Solde apuré : la sortie peut être finalisée.', { tone: 'success', icon: 'check-circle-2' }),
          ]),
          footer: [
            K.lien('m3-feuille-temperature', 'Feuille de température', { icon: 'thermometer' }),
            K.lien('m3-sorties', 'Préparer la sortie', { variant: 'primary', icon: 'door-open' }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * ADMISSIONS
   * ======================================================================== */
  function detailAdmission(a) {
    var solde = soldePatient(a.patientId);
    var wrap = el('div.space-y-4');
    wrap.appendChild(U.descList([
      ['Référence', el('span.font-mono', { text: a.reference || a.id })],
      ['Patient', a.patient], ['Dossier', el('span.font-mono', { text: a.patientCode })],
      ['Lit', a.lit], ['Chambre', typeChambre(a.typeChambre)],
      ['Date d’entrée', C.dateFR(a.dateEntree)],
      ['Date de sortie', a.dateSortie ? C.dateFR(a.dateSortie) : 'En cours'],
      ['Durée', dureeSejour(a) + ' jour(s)'],
      ['Diagnostic d’entrée', a.diagnosticEntree],
      ['Symptômes', a.symptomes],
      ['Prise en charge', U.statut(a.priseEnCharge)],
      ['Infirmier référent', a.infirmier],
      ['Statut', U.statut(a.statut)],
    ]));
    if (a.statut === 'en_cours') {
      wrap.appendChild(solde > 0
        ? K.note('<strong>RG-06</strong> — Reste à régler : <strong>' + C.money(solde) + '</strong> avant finalisation de la sortie.', { tone: 'warning', icon: 'wallet' })
        : K.note('<strong>RG-06</strong> — Situation financière apurée.', { tone: 'success', icon: 'check-circle-2' }));
    }
    return wrap;
  }

  function etatAdmission(a) {
    P.etat({
      titre: 'Bon d’admission',
      sousTitre: 'Référence ' + (a.reference || a.id),
      cartouche: [
        ['Patient', a.patient], ['Dossier', a.patientCode],
        ['Date d’entrée', C.dateFR(a.dateEntree)], ['Lit affecté', a.lit],
        ['Chambre', typeChambre(a.typeChambre)], ['Infirmier référent', a.infirmier],
      ],
      contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
        { k: 'Diagnostic d’entrée', v: a.diagnosticEntree },
        { k: 'Symptômes constatés', v: a.symptomes },
        { k: 'Type de prise en charge', v: a.priseEnCharge === 'plus_8h' ? 'Hospitalisation de plus de 8 heures' : 'Prise en charge de moins de 8 heures' },
        { k: 'Lit et chambre', v: a.lit + ' — ' + typeChambre(a.typeChambre) },
      ]),
      signatures: [{ role: 'Le Médecin', mention: 'Décision d’hospitalisation' },
        { role: 'L’Infirmier traitant', nom: a.infirmier },
        { role: 'Le Patient ou son représentant' }],
    });
  }

  global.SIGH.screen('m3-admissions', {
    title: 'Admissions',
    description: 'Enregistrement des admissions, affectation d’un lit et ouverture du registre d’hospitalisation.',
    regle: 'Un lit ne peut porter qu’une <strong>seule admission active</strong> à la fois : la liste des lits proposés ne présente que les lits libres.',
    render: K.crud({
      collection: 'admissions', entite: 'admission', entiteP: 'admissions', module: 'M3',
      defaultSort: 'dateEntree', defaultDir: 'desc', formSize: 'lg',
      source: 'Registre d’hospitalisation de la clinique.',
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (a) { return el('span.font-mono.text-xs', { text: a.reference || '—' }); } },
        {
          key: 'patient', label: 'Patient',
          render: function (a) {
            return el('div.min-w-0', null, [
              el('p.truncate.text-sm.font-medium.text-slate-800', { text: a.patient }),
              el('p.font-mono.text-xs.text-slate-400', { text: a.patientCode }),
            ]);
          },
        },
        { key: 'lit', label: 'Lit', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: a.lit }); } },
        { key: 'typeChambre', label: 'Chambre', text: function (a) { return typeChambre(a.typeChambre); }, render: function (a) { return U.badge(typeChambre(a.typeChambre), a.typeChambre === 'standard' ? 'neutral' : 'navy'); } },
        { key: 'dateEntree', label: 'Entrée', nowrap: true, text: function (a) { return C.dateFR(a.dateEntree); }, render: function (a) { return C.dateFR(a.dateEntree); } },
        { key: 'duree', label: 'Durée', align: 'right', value: function (a) { return dureeSejour(a); }, render: function (a) { return dureeSejour(a) + ' j'; } },
        { key: 'diagnosticEntree', label: 'Diagnostic' },
        { key: 'priseEnCharge', label: 'Prise en charge', render: function (a) { return U.statut(a.priseEnCharge); } },
        { key: 'statut', label: 'Statut', render: function (a) { return U.statut(a.statut); } },
      ],
      fields: function (record) {
        return [
          { type: 'section', label: 'Patient' },
          { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, options: optionsPatients(), col: 'full' },
          { type: 'section', label: 'Affectation' },
          { name: 'lit', label: 'Lit', type: 'select', required: true, options: optionsLitsLibres(record ? record.lit : null) },
          { name: 'infirmier', label: 'Infirmier référent', type: 'select', required: true, options: optionsInfirmiersNom() },
          { name: 'dateEntree', label: 'Date d’entrée', type: 'date', required: true },
          {
            name: 'priseEnCharge', label: 'Type de prise en charge', type: 'select', required: true,
            options: [{ value: 'moins_8h', label: 'Moins de 8 heures' }, { value: 'plus_8h', label: 'Plus de 8 heures' }],
          },
          { type: 'section', label: 'Motif d’hospitalisation' },
          { name: 'diagnosticEntree', label: 'Diagnostic d’entrée', required: true, col: 'full' },
          { name: 'symptomes', label: 'Symptômes constatés', type: 'textarea', rows: 2, col: 'full' },
        ];
      },
      onCreate: function () {
        return { dateEntree: C.iso(AUJ), statut: 'en_cours', priseEnCharge: 'plus_8h', reference: C.referenceSuivante('H', 5, S.collection('admissions').all()) };
      },
      transform: function (v, record) {
        var p = patients().filter(function (x) { return x.code === v.patientCode; })[0];
        if (p) { v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom; }
        var slot = tousLits().filter(function (s) { return s.lit.label === v.lit; })[0];
        if (slot) { v.chambre = slot.chambre.code; v.typeChambre = slot.chambre.type; }
        if (!v.reference) v.reference = (record && record.reference) || C.referenceSuivante('H', 5, S.collection('admissions').all());   /* E360 : série lue sur le registre, jamais un compteur de page */
        if (!v.statut) v.statut = 'en_cours';
        return v;
      },
      beforeSave: function (v, record) {
        var occupant = litOccupePar(v.lit);
        if (occupant && (!record || occupant.id !== record.id)) {
          return 'Le lit ' + v.lit + ' est déjà occupé par ' + occupant.patient + '.';
        }
        return null;
      },
      filters: [
        { name: 'statut', label: 'Statut', options: [{ value: 'en_cours', label: 'En cours' }, { value: 'sortie', label: 'Sorti' }] },
        { name: 'typeChambre', label: 'Type de chambre', options: D.TYPES_CHAMBRE.map(function (t) { return { value: t.id, label: t.label }; }) },
        { name: 'priseEnCharge', label: 'Prise en charge', options: [{ value: 'moins_8h', label: 'Moins de 8h' }, { value: 'plus_8h', label: 'Plus de 8h' }] },
      ],
      kpis: function (rows) {
        var ec = rows.filter(function (a) { return a.statut === 'en_cours'; });
        var termines = rows.filter(function (a) { return a.dateSortie; });
        return [
          { label: 'Admissions enregistrées', value: C.num(rows.length), icon: 'clipboard-list', tone: 'navy' },
          { label: 'Hospitalisations en cours', value: C.num(ec.length), icon: 'bed-double', tone: 'danger' },
          { label: 'Taux d’occupation', value: C.pct(ec.length / tousLits().length * 100), icon: 'gauge', tone: 'info' },
          { label: 'Durée moyenne de séjour', value: (termines.length ? Math.round(C.sum(termines, dureeSejour) / termines.length * 10) / 10 : 0) + ' j', icon: 'timer', tone: 'neutral' },
        ];
      },
      detail: detailAdmission, etat: etatAdmission,
    }),
  });

  /* ==========================================================================
   * CHAMBRES & LITS
   * ======================================================================== */
  global.SIGH.screen('m3-chambres', {
    title: 'Chambres & lits',
    description: 'Référentiel des chambres, nomenclature des lits et tarification journalière par catégorie.',
    regle: 'Écran en lecture seule. La nomenclature des lits et les tarifs par catégorie sont un <strong>référentiel</strong> : ils se modifient dans « Référentiel tarifaire » (Configuration). L’occupation, elle, découle des admissions.',
    render: function (root) {
      var rows = [];
      D.CHAMBRES.forEach(function (ch) {
        ch.lits.forEach(function (l) {
          var adm = litOccupePar(l.label);
          rows.push({
            id: l.code, code: l.label, chambre: ch.code, aile: ch.aile, type: ch.type,
            tarif: D.TYPES_CHAMBRE.filter(function (t) { return t.id === ch.type; })[0].tarif,
            statut: adm ? 'occupe' : 'libre',
            occupant: adm ? adm.patient : null,
            depuis: adm ? adm.dateEntree : null,
          });
        });
      });

      var host = el('div.space-y-4');
      host.appendChild(U.kpiGrid(D.TYPES_CHAMBRE.map(function (t) {
        var l = rows.filter(function (r) { return r.type === t.id; });
        return {
          label: 'Lits ' + t.label, value: C.num(l.length), icon: 'bed',
          tone: t.id === 'vvip' ? 'navy' : (t.id === 'vip' ? 'info' : 'neutral'),
          hint: C.money(t.tarif) + ' / jour — ' + l.filter(function (r) { return r.statut === 'occupe'; }).length + ' occupé(s)',
        };
      }).concat([{ label: 'Capacité totale', value: C.num(rows.length), icon: 'building', tone: 'success' }])));

      host.appendChild(U.dataTable({
        title: 'Référentiel des lits', rows: rows, exportName: 'chambres-lits', pageSize: 20,
        filters: [
          { name: 'type', label: 'Catégorie', options: D.TYPES_CHAMBRE.map(function (t) { return { value: t.id, label: t.label }; }) },
          { name: 'statut', label: 'État', options: [{ value: 'libre', label: 'Libre' }, { value: 'occupe', label: 'Occupé' }] },
        ],
        columns: [
          { key: 'code', label: 'Lit', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold', { text: r.code }); } },
          { key: 'chambre', label: 'Chambre' },
          { key: 'aile', label: 'Aile / service' },
          { key: 'type', label: 'Catégorie', text: function (r) { return typeChambre(r.type); }, render: function (r) { return U.badge(typeChambre(r.type), r.type === 'standard' ? 'neutral' : 'navy'); } },
          { key: 'tarif', label: 'Tarif / jour', align: 'right', text: function (r) { return C.money(r.tarif, false); }, render: function (r) { return C.money(r.tarif, false); } },
          { key: 'statut', label: 'État', render: function (r) { return U.statut(r.statut); } },
          { key: 'occupant', label: 'Occupant' },
          { key: 'depuis', label: 'Depuis', nowrap: true, text: function (r) { return r.depuis ? C.dateFR(r.depuis) : ''; }, render: function (r) { return r.depuis ? C.dateFR(r.depuis) : '—'; } },
        ],
        actions: [K.btn('Imprimer le plan', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Plan d’occupation des lits',
              sousTitre: 'Situation au ' + C.dateFR(AUJ),
              cartouche: [['Capacité', C.num(rows.length) + ' lits'],
                ['Occupés', C.num(rows.filter(function (r) { return r.statut === 'occupe'; }).length)],
                ['Libres', C.num(rows.filter(function (r) { return r.statut === 'libre'; }).length)],
                ['Taux d’occupation', C.pct(rows.filter(function (r) { return r.statut === 'occupe'; }).length / rows.length * 100)]],
              contenu: P.tableau([
                { label: 'Lit', key: 'code' }, { label: 'Chambre', key: 'chambre' },
                { label: 'Aile', key: 'aile' }, { label: 'Catégorie', value: function (r) { return typeChambre(r.type); } },
                { label: 'État', value: function (r) { return r.statut === 'occupe' ? 'Occupé' : 'Libre'; } },
                { label: 'Occupant', key: 'occupant' },
              ], rows),
              signatures: [{ role: 'Le Surveillant Général', nom: 'GARBA Yahouza' }],
            });
          },
        })],
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * FEUILLE DE TEMPÉRATURE
   * ======================================================================== */
  global.SIGH.screen('m3-feuille-temperature', {
    title: 'Feuille de température',
    description: 'Relevé numérique des constantes : tension, fréquence cardiaque, saturation, diurèse, poids, taille, fréquence respiratoire et traitement.',
    render: function (root) {
      var ec = enCours();
      var host = el('div.space-y-4');
      if (!ec.length) {
        root.appendChild(U.card(null, U.empty('Aucun patient hospitalisé actuellement.', {
          icon: 'bed', hint: 'La feuille de température se saisit pour les patients en cours d’hospitalisation.',
          action: K.lien('m3-admissions', 'Créer une admission', { variant: 'primary', icon: 'user-plus' }),
        })));
        return null;
      }

      var courant = ec[0];
      var releves = S.collection('releves', { module: 'M3', entite: 'FeuilleTemperature' });

      /* Les relevés sont amorcés par le MAGASIN et non par cet écran : trois
         écrans les lisent, et celui qu'on ouvre en premier ne doit pas décider
         si les autres voient quelque chose. */

      /* Sélecteur de patient */
      var barre = el('div.card');
      var bbody = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      var sel = U.combo(ec.map(function (a) {
        return { value: a.id, label: a.patient, detail: 'Lit ' + a.lit + ' — ' + a.patientCode, icon: 'bed-double' };
      }), {
        value: ec.length ? ec[0].id : '',
        searchPlaceholder: 'Patient, lit ou code dossier…',
        placeholder: 'Choisir un patient hospitalisé',
      });
      sel.classList.add('max-w-lg');
      bbody.appendChild(el('div.flex-1', null, [el('label.label', { text: 'Patient hospitalisé' }), sel]));
      /* RELEVER UNE CONSTANTE EST UN GESTE CLINIQUE. L'accueil et le
         surveillant, qui ont M3 en lecture, se le voyaient offrir — l'accueil
         ne doit toucher à aucune donnée clinique (RG-13). */
      C.append(bbody, K.commande('Nouveau relevé', { variant: 'primary', icon: 'plus', onclick: function () { ouvrirSaisie(); } }));
      bbody.appendChild(K.btn('Imprimer la feuille', { icon: 'printer', onclick: function () { imprimer(); } }));
      barre.appendChild(bbody);
      host.appendChild(barre);

      var vue = el('div.space-y-4');
      host.appendChild(vue);
      sel.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;

      function mesRelevés() {
        return C.sortBy(releves.active().filter(function (r) { return r.admissionId === courant.id; }),
          function (r) { return r.date + ' ' + r.heure; }, 'desc');
      }

      function afficher() {
        courant = ec.filter(function (a) { return a.id === sel.value; })[0] || ec[0];
        C.clear(vue);
        var rel = mesRelevés();

        vue.appendChild(U.card('Patient', U.descList([
          ['Patient', courant.patient], ['Dossier', el('span.font-mono', { text: courant.patientCode })],
          ['Lit', courant.lit], ['Chambre', typeChambre(courant.typeChambre)],
          ['Entrée', C.dateFR(courant.dateEntree)], ['Séjour', dureeSejour(courant) + ' jour(s)'],
          ['Diagnostic', courant.diagnosticEntree], ['Infirmier référent', courant.infirmier],
        ], 'grid-cols-2 lg:grid-cols-4')));

        if (!rel.length) {
          vue.appendChild(U.card(null, U.empty('Aucun relevé enregistré pour ce patient.', {
            icon: 'thermometer', action: K.btn('Saisir le premier relevé', { variant: 'primary', icon: 'plus', onclick: function () { ouvrirSaisie(); } }),
          })));
          U.icons(vue);
          return;
        }

        var derniers = rel.slice(0, 24).reverse();
        vue.appendChild(K.charts([
          {
            title: 'Courbe de température (°C)',
            render: function () {
              return G.ligne(derniers.map(function (r) { return C.dateFR(r.date).slice(0, 5) + ' ' + r.heure; }),
                [{ label: 'Température', data: derniers.map(function (r) { return Number(r.temperature); }), color: G.TONES.rouge }],
                { scales: { y: { beginAtZero: false, min: 35, max: 41 } } });
            },
          },
          {
            title: 'Fréquence cardiaque et saturation',
            render: function () {
              return G.ligne(derniers.map(function (r) { return C.dateFR(r.date).slice(0, 5) + ' ' + r.heure; }), [
                { label: 'FC (bpm)', data: derniers.map(function (r) { return r.fc; }), color: G.TONES.navy, fill: false },
                { label: 'SpO₂ (%)', data: derniers.map(function (r) { return r.spo2; }), color: G.TONES.vert, fill: false },
              ]);
            },
          },
        ]));

        vue.appendChild(U.dataTable({
          title: 'Relevés de constantes', rows: rel, exportName: 'feuille-temperature', pageSize: 12,
          columns: [
            { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
            { key: 'heure', label: 'Heure', nowrap: true },
            {
              key: 'temperature', label: 'T° (°C)', align: 'right',
              render: function (r) {
                var t = Number(r.temperature);
                return el('span', { class: t >= 38 ? 'font-semibold text-danger-600' : (t < 36 ? 'font-semibold text-info-600' : ''), text: r.temperature });
              },
            },
            { key: 'tension', label: 'TA', align: 'right' },
            { key: 'fc', label: 'FC', align: 'right' },
            {
              key: 'spo2', label: 'SpO₂', align: 'right',
              render: function (r) { return el('span', { class: r.spo2 < 94 ? 'font-semibold text-danger-600' : '', text: r.spo2 + ' %' }); },
            },
            { key: 'fr', label: 'FR', align: 'right' },
            { key: 'diurese', label: 'Diurèse (ml)', align: 'right' },
            { key: 'poids', label: 'Poids (kg)', align: 'right' },
            { key: 'traitement', label: 'Traitement' },
            { key: 'saisiPar', label: 'Saisi par' },
          ],
          rowActions: function (r) {
            return [K.commandeIcone('trash-2', 'Archiver ce relevé', function () {
              var res = releves.archive(r.id);
              afficher();
              U.toast('Relevé archivé.', { type: 'success', undo: function () { res.undo(); afficher(); } });
            }, { droit: 'annuler', variant: 'ghost' })];
          },
        }));
        U.icons(vue);
      }

      function ouvrirSaisie() {
        var f = U.form([
          { name: 'date', label: 'Date', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'heure', label: 'Heure', type: 'time', required: true, value: '08:00' },
          { name: 'temperature', label: 'Température (°C)', type: 'number', step: '0.1', required: true, validate: function (v) { return (v < 30 || v > 45) ? 'Valeur hors plage physiologique (30–45 °C).' : null; } },
          { name: 'tension', label: 'Tension artérielle', required: true, placeholder: '12/8' },
          { name: 'fc', label: 'Fréquence cardiaque (bpm)', type: 'number', required: true },
          { name: 'spo2', label: 'Saturation SpO₂ (%)', type: 'number', min: 0, max: 100, required: true },
          { name: 'fr', label: 'Fréquence respiratoire', type: 'number' },
          { name: 'diurese', label: 'Diurèse (ml)', type: 'number' },
          { name: 'poids', label: 'Poids (kg)', type: 'number', step: '0.1' },
          { name: 'taille', label: 'Taille (cm)', type: 'number' },
          { name: 'traitement', label: 'Traitement administré', col: 'full' },
        ], {});
        var m = U.modal({
          title: 'Nouveau relevé de constantes',
          subtitle: courant.patient + ' — lit ' + courant.lit,
          size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                v.admissionId = courant.id;
                v.saisiPar = S.currentUser();
                var res = releves.insert(v);
                m.close(); afficher();
                U.toast('Relevé enregistré.', { type: 'success', undo: function () { res.undo(); afficher(); } });
              },
            }),
          ],
        });
      }

      function imprimer() {
        var rel = C.sortBy(mesRelevés(), function (r) { return r.date + ' ' + r.heure; });
        P.etat({
          titre: 'Feuille de température',
          sousTitre: 'Suivi des constantes — hospitalisation',
          cartouche: [
            ['Patient', courant.patient], ['Dossier', courant.patientCode],
            ['Lit', courant.lit], ['Chambre', typeChambre(courant.typeChambre)],
            ['Date d’entrée', C.dateFR(courant.dateEntree)], ['Diagnostic', courant.diagnosticEntree],
          ],
          contenu: rel.length ? P.tableau([
            { label: 'Date', value: function (r) { return C.dateFR(r.date); } },
            { label: 'Heure', key: 'heure' },
            { label: 'T° (°C)', key: 'temperature', align: 'right' },
            { label: 'TA', key: 'tension', align: 'right' },
            { label: 'FC', key: 'fc', align: 'right' },
            { label: 'SpO₂', key: 'spo2', align: 'right' },
            { label: 'FR', key: 'fr', align: 'right' },
            { label: 'Diurèse', key: 'diurese', align: 'right' },
            { label: 'Traitement', key: 'traitement' },
          ], rel) : el('p.italic', { text: 'Aucun relevé enregistré.' }),
          signatures: [{ role: 'L’Infirmier traitant', nom: courant.infirmier }, { role: 'Le Médecin' }],
        });
      }
    },
  });

  /* ==========================================================================
   * FEUILLE DE SOINS
   * ======================================================================== */
  global.SIGH.screen('m3-soins', {
    title: 'Feuille de soins',
    description: 'Actes de soins réalisés au chevet du patient : injections, pansements, perfusions et surveillance.',
    regle: 'Chaque acte est rattaché à une admission et au soignant qui l’a exécuté (RG-12). Les actes figurent dans la fiche du patient. '
      + 'Un acte prescrit et <strong>non coché est réputé non fait</strong> : la validation enregistre l’heure d’exécution '
      + 'en regard de l’heure de prescription.',
    render: function (root) {
      /* « Ce sont les infirmiers qui font les soins. Ce n'est pas les
         aides-soignants. » La file d'exécution n'est donc pas ouverte à tous :
         qui n'a pas la capacité voit la règle, pas le bouton. */
      var cap = PR.capacites();
      if (!PR.peutExecuterSoin()) {
        root.appendChild(K.note('<strong>' + cap.label + ' — l’exécution des soins prescrits ne vous revient pas.</strong> '
          + 'Les soins prescrits sont réalisés par les infirmiers ; la feuille de soins reste consultable '
          + 'pour la continuité de la prise en charge, mais aucune validation n’est possible depuis ce poste.',
        { tone: 'warning', icon: 'shield-alert' }));
      }
      root.appendChild(K.fileAttente('acte', {
        titre: 'Actes prescrits à exécuter',
        vide: 'Aucun acte prescrit en attente.',
        icon: 'check', action: 'Marquer le soin fait',
        onAction: function (tache, refresh) {
          if (!PR.peutExecuterSoin()) {
            U.toast('Cette validation revient aux infirmiers.', {
              type: 'warning', detail: cap.label + ' — capacité « exécuter les soins » non accordée.',
            });
            return;
          }
          U.confirm({
            title: 'Soin fait ?',
            message: 'Les actes de la prescription ' + tache.reference + ' seront marqués exécutés, '
              + 'avec l’heure d’exécution et votre nom. Un acte non coché reste réputé non fait.',
            confirmLabel: 'Soin fait',
          }).then(function (ok) {
            if (!ok) return;
            var ord = S.collection('ordonnances').get(tache.ordonnanceId);
            if (ord) {
              S.collection('ordonnances').update(ord.id, {
                statutActes: 'fait',
                actesFaitsLe: new Date().toISOString(),
                actesFaitsPar: S.currentUser(),
              });
            }
            PR.terminer(tache.id);
            refresh();
            U.toast('Soin fait — exécution enregistrée à ' + C.heure(new Date().toISOString()) + '.', {
              type: 'success', detail: tache.detail,
            });
          });
        },
      }));
      return K.crud({
      collection: 'soins', entite: 'acte de soins', entiteP: 'actes de soins', module: 'M3',
      defaultSort: 'date', defaultDir: 'desc', pageSize: 15,
      source: 'Feuille de soins tenue au chevet du patient.',
      columns: [
        { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
        { key: 'heure', label: 'Heure', nowrap: true },
        { key: 'lit', label: 'Lit', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.lit }); } },
        { key: 'patient', label: 'Patient' },
        { key: 'acte', label: 'Acte réalisé' },
        { key: 'produit', label: 'Produit administré', render: function (r) { return r.produit || '—'; } },
        { key: 'soignant', label: 'Soignant' },
        {
          key: 'etat', label: 'État',
          render: function (r) { return r.etat === 'realise' ? U.badge('Réalisé', 'success') : U.badge('Planifié', 'warning'); },
        },
      ],
      filters: [
        { name: 'acte', label: 'Type d’acte', options: D.ACTES_SOINS },
        { name: 'etat', label: 'État', options: [{ value: 'realise', label: 'Réalisé' }, { value: 'planifie', label: 'Planifié' }] },
      ],
      fields: function () {
        var ec = enCours();
        return [
          {
            name: 'admissionId', label: 'Patient hospitalisé', type: 'select', required: true, col: 'full',
            options: ec.map(function (a) { return { value: a.id, label: a.patient + ' — lit ' + a.lit + ' (' + a.patientCode + ')' }; }),
            searchPlaceholder: 'Patient, lit ou code dossier…',
          },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'heure', label: 'Heure', type: 'time', required: true },
          { name: 'acte', label: 'Acte de soins', type: 'select', required: true, options: D.ACTES_SOINS, col: 'full' },
          { name: 'produit', label: 'Produit administré' },
          { name: 'quantite', label: 'Quantité', type: 'number', min: 0 },
          { name: 'soignant', label: 'Soignant', required: true },
          {
            name: 'etat', label: 'État', type: 'select', required: true,
            options: [{ value: 'realise', label: 'Réalisé' }, { value: 'planifie', label: 'Planifié' }],
          },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ];
      },
      onCreate: function () {
        return { date: C.iso(AUJ), heure: '08:00', etat: 'realise', soignant: S.currentUser(), quantite: 1 };
      },
      /* L'acte porte les références du patient : elles sont recopiées depuis
         l'admission choisie, jamais ressaisies. */
      transform: function (v) {
        var a = S.collection('admissions').get(v.admissionId);
        if (a) {
          v.patient = a.patient;
          v.patientCode = a.patientCode;
          v.patientId = a.patientId;
          v.lit = a.lit;
        }
        return v;
      },
      kpis: function (rows) {
        return [
          { label: 'Actes enregistrés', value: C.num(rows.length), icon: 'syringe', tone: 'navy' },
          { label: 'Réalisés', value: C.num(rows.filter(function (r) { return r.etat === 'realise'; }).length), icon: 'check-circle-2', tone: 'success' },
          { label: 'Planifiés', value: C.num(rows.filter(function (r) { return r.etat === 'planifie'; }).length), icon: 'clock', tone: 'warning' },
          { label: 'Patients concernés', value: C.num(Object.keys(C.groupBy(rows, 'patientCode')).length), icon: 'bed-double', tone: 'info' },
        ];
      },
      detail: function (r) {
        return U.descList([
          ['Date et heure', C.dateFR(r.date) + ' à ' + r.heure],
          ['Patient', r.patient], ['Dossier', r.patientCode], ['Lit', r.lit],
          ['Acte', r.acte], ['Produit administré', r.produit || '—'],
          ['Quantité', r.quantite || '—'], ['Soignant', r.soignant],
          ['État', r.etat === 'realise' ? U.badge('Réalisé', 'success') : U.badge('Planifié', 'warning')],
          ['Observations', r.observations || '—'],
        ]);
      },
      etat: function (r) {
        P.etat({
          titre: 'Feuille de soins',
          sousTitre: r.patient + ' — lit ' + r.lit,
          cartouche: [['Patient', r.patient], ['Dossier', r.patientCode],
            ['Date', C.dateFR(r.date) + ' à ' + r.heure], ['Soignant', r.soignant]],
          contenu: P.tableau([
            { label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' },
          ], [
            { k: 'Acte réalisé', v: r.acte },
            { k: 'Produit administré', v: r.produit || '—' },
            { k: 'Quantité', v: String(r.quantite || '—') },
            { k: 'État', v: r.etat === 'realise' ? 'Réalisé' : 'Planifié' },
            { k: 'Observations', v: r.observations || '—' },
          ]),
          signatures: [{ role: 'Le soignant' }, { role: 'Le Directeur Médical' }],
        });
      },
      })(root);
      return null;
    },
  });

  global.SIGH.screen('m3-visites-patients', {
    title: 'Visites aux patients hospitalisés',
    description: 'Enregistrement des visites du personnel traitant et des visites familiales, avec dates et heures.',
    render: K.registre({
      collection: 'visitesHospi', entite: 'visite', entiteP: 'visites', module: 'M3',
      defaultSort: 'date', defaultDir: 'desc', pageSize: 15,
      source: 'Registre des visites tenu à l’accueil du service.',
      seed: function () {
        var rnd = C.seeded(401), out = [], n = 0;
        enCours().forEach(function (a) {
          var nb = C.between(rnd, 1, 5);
          for (var i = 0; i < nb; i++) {
            var famille = rnd() > 0.45;
            out.push({
              id: 'VIS' + C.pad(++n, 4),
              date: C.iso(C.addDays(AUJ, -C.between(rnd, 0, Math.max(1, dureeSejour(a))))),
              heure: C.pad(C.between(rnd, 8, 19)) + ':' + C.pick(rnd, ['00', '30']),
              admissionId: a.id, patient: a.patient, patientCode: a.patientCode, lit: a.lit,
              type: famille ? 'Famille' : 'Personnel traitant',
              visiteur: famille ? 'Accompagnant déclaré' : a.infirmier,
              observation: famille
                ? C.pick(rnd, ['Apport de repas', 'Visite de courtoisie', 'Accompagnement'])
                : C.pick(rnd, ['Visite médicale', 'Contrôle des constantes', 'Réévaluation du traitement']),
              statut: 'actif',
            });
          }
        });
        return out;
      },
      columns: [
        { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
        { key: 'heure', label: 'Heure', nowrap: true },
        { key: 'lit', label: 'Lit', nowrap: true },
        { key: 'patient', label: 'Patient' },
        { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type, r.type === 'Famille' ? 'success' : 'info'); } },
        { key: 'visiteur', label: 'Visiteur' },
        { key: 'observation', label: 'Observation' },
      ],
      filters: [{ name: 'type', label: 'Type de visite', options: ['Famille', 'Personnel traitant'] }],
      fields: function () {
        var ec = enCours();
        return [
          {
            name: 'admissionId', label: 'Patient hospitalisé', type: 'select', required: true, col: 'full',
            options: ec.map(function (a) { return { value: a.id, label: a.patient + ' — lit ' + a.lit + ' (' + a.patientCode + ')' }; }),
            searchPlaceholder: 'Patient, lit ou code dossier…',
          },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'heure', label: 'Heure', type: 'time', required: true },
          { name: 'type', label: 'Type de visite', type: 'select', required: true, options: ['Famille', 'Personnel traitant'] },
          { name: 'visiteur', label: 'Visiteur', required: true },
          { name: 'observation', label: 'Observation', col: 'full' },
        ];
      },
      onCreate: function () { return { date: C.iso(AUJ), heure: '10:00', type: 'Famille' }; },
      transform: function (v) {
        var a = S.collection('admissions').get(v.admissionId);
        if (a) { v.patient = a.patient; v.patientCode = a.patientCode; v.lit = a.lit; }
        return v;
      },
      kpis: function (rows) {
        return [
          { label: 'Visites enregistrées', value: C.num(rows.length), icon: 'users', tone: 'navy' },
          { label: 'Visites familiales', value: C.num(rows.filter(function (r) { return r.type === 'Famille'; }).length), icon: 'heart', tone: 'success' },
          { label: 'Visites du personnel', value: C.num(rows.filter(function (r) { return r.type !== 'Famille'; }).length), icon: 'stethoscope', tone: 'info' },
          { label: 'Patients visités', value: C.num(Object.keys(C.groupBy(rows, 'patientCode')).length), icon: 'bed-double', tone: 'neutral' },
        ];
      },
    }),
  });

  global.SIGH.screen('m3-sorties', {
    title: 'Sorties d’hospitalisation',
    description: 'Préparation et finalisation des sorties : vérification financière, signatures et édition du bon de sortie.',
    regle: '<strong>RG-06</strong> — la sortie n’est finalisable que si le solde du patient est apuré, sauf dérogation motivée et tracée. '
      + '<strong>RG-07</strong> — elle requiert la signature du patient, celle de l’infirmier traitant et le constat du gardien.',
    render: function (root) {
      var host = el('div.space-y-4');
      var ec = enCours();

      host.appendChild(U.kpiGrid([
        { label: 'Patients hospitalisés', value: C.num(ec.length), icon: 'bed-double', tone: 'navy' },
        { label: 'Sorties finalisables', value: C.num(ec.filter(function (a) { return soldePatient(a.patientId) <= 0; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Bloquées par le solde', value: C.num(ec.filter(function (a) { return soldePatient(a.patientId) > 0; }).length), icon: 'wallet', tone: 'danger', hint: 'RG-06' },
        { label: 'Sorties réalisées', value: C.num(admissions().filter(function (a) { return a.statut === 'sortie'; }).length), icon: 'door-open', tone: 'info' },
      ]));

      var table = U.dataTable({
        title: 'Patients en cours d’hospitalisation',
        rows: function () { return enCours(); },
        exportName: 'sorties-a-preparer', pageSize: 12,
        emptyMessage: 'Aucun patient hospitalisé.',
        columns: [
          { key: 'lit', label: 'Lit', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.font-semibold', { text: a.lit }); } },
          {
            key: 'patient', label: 'Patient',
            render: function (a) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: a.patient }),
                el('p.font-mono.text-xs.text-slate-400', { text: a.patientCode }),
              ]);
            },
          },
          { key: 'dateEntree', label: 'Entrée', nowrap: true, text: function (a) { return C.dateFR(a.dateEntree); }, render: function (a) { return C.dateFR(a.dateEntree); } },
          { key: 'duree', label: 'Séjour', align: 'right', value: dureeSejour, render: function (a) { return dureeSejour(a) + ' j'; } },
          { key: 'diagnosticEntree', label: 'Diagnostic' },
          {
            key: 'solde', label: 'Solde (RG-06)', align: 'right',
            value: function (a) { return soldePatient(a.patientId); },
            text: function (a) { return C.money(soldePatient(a.patientId), false); },
            render: function (a) {
              var s = soldePatient(a.patientId);
              return s > 0
                ? el('span.font-semibold.text-danger-600', { text: C.money(s, false) })
                : U.badge('Apuré', 'success');
            },
          },
        ],
        onRowClick: function (a) { ouvrirSortie(a); },
        rowActions: function (a) {
          return [K.btn('Préparer la sortie', { size: 'sm', icon: 'door-open', onclick: function () { ouvrirSortie(a); } })];
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function ouvrirSortie(a) {
        var solde = soldePatient(a.patientId);
        var body = el('div.space-y-4');

        body.appendChild(U.descList([
          ['Patient', a.patient], ['Dossier', el('span.font-mono', { text: a.patientCode })],
          ['Lit', a.lit], ['Entrée', C.dateFR(a.dateEntree)],
          ['Durée du séjour', dureeSejour(a) + ' jour(s)'], ['Diagnostic', a.diagnosticEntree],
        ]));

        body.appendChild(solde > 0
          ? K.note('<strong>RG-06 — vérification financière non satisfaite.</strong> Solde restant dû : <strong>'
            + C.money(solde) + '</strong>. La sortie exige soit l’encaissement du solde à la caisse, soit une dérogation motivée de la Direction, qui sera tracée dans le journal d’audit.',
            { tone: 'danger', icon: 'wallet' })
          : K.note('<strong>RG-06</strong> — Vérification financière satisfaite : le solde du patient est apuré.', { tone: 'success', icon: 'check-circle-2' }));

        var f = U.form([
          { name: 'dateSortie', label: 'Date de sortie', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'etatSortie', label: 'État à la sortie', type: 'select', required: true, options: ['Guéri', 'Amélioré', 'Stationnaire', 'Transféré', 'Sortie contre avis médical'] },
          { name: 'consignes', label: 'Consignes de sortie et suivi', type: 'textarea', rows: 2, col: 'full' },
          { type: 'section', label: 'Signatures et constat (RG-07)' },
          { name: 'sigPatient', label: 'Signature du patient recueillie', type: 'checkbox' },
          { name: 'sigInfirmier', label: 'Signature de l’infirmier traitant', type: 'checkbox' },
          { name: 'constatGardien', label: 'Constat du gardien effectué', type: 'checkbox' },
          { name: 'derogation', label: 'Dérogation de la Direction (si solde non apuré)', type: 'textarea', rows: 2, col: 'full' },
        ], {});
        body.appendChild(f);

        var m = U.drawer({
          title: 'Sortie d’hospitalisation', subtitle: a.patient + ' — lit ' + a.lit,
          body: body, width: 'max-w-2xl',
          footer: [
            K.btn('Éditer le bon de sortie', { icon: 'printer', onclick: function () { etatBonSortie(a, f.collect() || {}); } }),
            K.btn('Finaliser la sortie', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (!v.sigPatient || !v.sigInfirmier || !v.constatGardien) {
                  U.toast('RG-07 — les trois signatures sont obligatoires.', {
                    type: 'error', detail: 'Patient, infirmier traitant et constat du gardien.',
                  });
                  return;
                }
                if (solde > 0 && !String(v.derogation || '').trim()) {
                  U.toast('RG-06 — solde non apuré : une dérogation motivée est requise.', {
                    type: 'error', detail: 'Encaisser le solde à la caisse ou saisir la dérogation de la Direction.',
                  });
                  return;
                }
                var res = S.collection('admissions', { module: 'M3', entite: 'SortieHospitalisation' })
                  .update(a.id, {
                    statut: 'sortie', dateSortie: v.dateSortie, etatSortie: v.etatSortie,
                    consignes: v.consignes, derogation: v.derogation || null,
                    signaturePatient: true, signatureInfirmier: true, constatGardien: true,
                  });
                m.close(); table.refresh();
                U.toast('Sortie finalisée — le lit ' + a.lit + ' est libéré.', {
                  type: 'success', undo: function () { res.undo(); table.refresh(); },
                });
              },
            }),
          ],
        });
      }

      function etatBonSortie(a, v) {
        P.etat({
          titre: 'Bon de sortie d’hospitalisation',
          sousTitre: 'Référence ' + (a.reference || a.id),
          cartouche: [
            ['Patient', a.patient], ['Dossier', a.patientCode],
            ['Date d’entrée', C.dateFR(a.dateEntree)],
            ['Date de sortie', v.dateSortie ? C.dateFR(v.dateSortie) : C.dateFR(AUJ)],
            ['Lit', a.lit], ['Durée du séjour', dureeSejour(a) + ' jour(s)'],
          ],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Diagnostic d’entrée', v: a.diagnosticEntree },
              { k: 'État à la sortie', v: v.etatSortie || '—' },
              { k: 'Consignes de sortie', v: v.consignes || '—' },
              { k: 'Vérification financière (RG-06)', v: soldePatient(a.patientId) > 0 ? 'Solde restant dû : ' + C.money(soldePatient(a.patientId)) : 'Solde apuré' },
              { k: 'Dérogation Direction', v: v.derogation || 'Sans objet' },
            ]),
            el('p.mt-3.text-\\[10px\\].italic.text-slate-600', {
              text: 'Conformément à la règle RG-07, la présente sortie requiert la signature du patient, celle de l’infirmier traitant et le constat du gardien.',
            }),
          ]),
          signatures: [
            { role: 'Le Patient', mention: 'Signature' },
            { role: 'L’Infirmier traitant', nom: a.infirmier, mention: 'Signature' },
            { role: 'Le Gardien', mention: 'Constat de sortie' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * SORTIE CONTRE AVIS MÉDICAL
   * ======================================================================== */
  global.SIGH.screen('m3-sortie-avis-medical', {
    title: 'Sortie contre avis médical',
    description: 'Enregistrement des sorties décidées par le patient contre l’avis du médecin, avec motif et avis du Procureur le cas échéant.',
    regle: '<strong>RG-08</strong> — toute sortie contre avis médical est motivée ; si la situation l’exige, l’avis du Procureur est consigné avant clôture du dossier.',
    render: function (root) {
      var col = S.collection('sortiesAvisMedical', { module: 'M3', entite: 'SortieAvisMedical' });
      var ec = enCours();
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Sorties contre avis médical', value: C.num(col.active().length), icon: 'file-warning', tone: 'danger' },
        { label: 'Avec avis du Procureur', value: C.num(col.active().filter(function (r) { return r.avisProcureur; }).length), icon: 'gavel', tone: 'warning' },
        { label: 'Patients hospitalisés', value: C.num(ec.length), icon: 'bed-double', tone: 'navy' },
        { label: 'Dossiers clôturés', value: C.num(col.active().filter(function (r) { return r.cloture; }).length), icon: 'archive', tone: 'success' },
      ]));

      host.appendChild(K.note('Cette procédure dégage la responsabilité de la clinique. Le motif du refus de soins et la décharge signée du patient sont impératifs.', { tone: 'warning', icon: 'triangle-alert' }));

      var table;
      function champs() {
        return [
          {
            name: 'admissionId', label: 'Patient hospitalisé', type: 'select', required: true, col: 'full',
            options: ec.map(function (a) { return { value: a.id, label: a.lit + ' — ' + a.patient + ' (' + a.patientCode + ')' }; }),
          },
          { name: 'dateSortie', label: 'Date de sortie', type: 'date', required: true },
          { name: 'heureSortie', label: 'Heure', type: 'time' },
          { name: 'motif', label: 'Motif invoqué par le patient', type: 'textarea', rows: 2, required: true, col: 'full' },
          { name: 'risques', label: 'Risques exposés au patient', type: 'textarea', rows: 2, col: 'full' },
          { name: 'avisProcureur', label: 'Avis du Procureur requis et consigné', type: 'checkbox' },
          { name: 'referenceProcureur', label: 'Référence de l’avis du Procureur' },
          { name: 'decharge', label: 'Décharge signée par le patient', type: 'checkbox' },
          { name: 'cloture', label: 'Dossier clôturé', type: 'checkbox' },
        ];
      }

      table = U.dataTable({
        title: 'Registre des sorties contre avis médical',
        rows: function () { return col.active(); },
        exportName: 'sorties-contre-avis-medical', pageSize: 10,
        emptyMessage: 'Aucune sortie contre avis médical enregistrée.',
        emptyHint: 'Utiliser le bouton « Enregistrer » pour consigner une nouvelle procédure.',
        actions: [K.commande('Enregistrer', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(null); } })],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'patient', label: 'Patient' },
          { key: 'dateSortie', label: 'Date de sortie', nowrap: true, text: function (r) { return C.dateFR(r.dateSortie); }, render: function (r) { return C.dateFR(r.dateSortie); } },
          { key: 'motif', label: 'Motif invoqué' },
          { key: 'avisProcureur', label: 'Procureur', text: function (r) { return r.avisProcureur ? 'Oui' : 'Non'; }, render: function (r) { return r.avisProcureur ? U.badge('Avis consigné', 'warning') : el('span.text-xs.text-slate-400', { text: 'Sans objet' }); } },
          { key: 'decharge', label: 'Décharge', text: function (r) { return r.decharge ? 'Signée' : 'Manquante'; }, render: function (r) { return r.decharge ? U.badge('Signée', 'success') : U.badge('Manquante', 'danger'); } },
          { key: 'cloture', label: 'Dossier', text: function (r) { return r.cloture ? 'Clôturé' : 'Ouvert'; }, render: function (r) { return r.cloture ? U.badge('Clôturé', 'neutral') : U.badge('Ouvert', 'info'); } },
        ],
        rowActions: function (r) {
          return [
            K.iconBtn('printer', 'Imprimer le document', function () { etat(r); }),
            K.iconBtn('pencil', 'Modifier', function () { ouvrir(r); }),
            K.iconBtn('archive', 'Archiver', function () {
              var res = col.archive(r.id);
              table.refresh();
              U.toast('Enregistrement archivé.', { type: 'success', undo: function () { res.undo(); table.refresh(); } });
            }, 'ghost'),
          ];
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function ouvrir(record) {
        var f = U.form(champs(), record || { dateSortie: C.iso(AUJ) });
        var m = U.modal({
          title: record ? 'Modifier la procédure' : 'Sortie contre avis médical',
          subtitle: 'RG-08 — motif obligatoire, avis du Procureur si la situation l’exige.',
          size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(record ? 'Enregistrer' : 'Consigner', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (v.avisProcureur && !String(v.referenceProcureur || '').trim()) {
                  U.toast('La référence de l’avis du Procureur est obligatoire.', { type: 'error' }); return;
                }
                var a = admissions().filter(function (x) { return x.id === v.admissionId; })[0];
                if (a) { v.patient = a.patient; v.patientCode = a.patientCode; v.lit = a.lit; }
                if (!v.reference) v.reference = C.nextRef('SAM', 4);
                var res = record ? col.update(record.id, v) : col.insert(v);
                if (!record && a) S.collection('admissions').update(a.id, { statut: 'sortie', dateSortie: v.dateSortie });
                m.close(); table.refresh();
                U.toast(record ? 'Procédure mise à jour.' : 'Sortie contre avis médical consignée.', {
                  type: 'success', undo: res.undo,
                });
              },
            }),
          ],
        });
      }

      function etat(r) {
        P.etat({
          titre: 'Sortie contre avis médical',
          sousTitre: 'Décharge de responsabilité — ' + r.reference,
          filigrane: 'Document officiel',
          cartouche: [
            ['Patient', r.patient], ['Dossier', r.patientCode], ['Lit', r.lit],
            ['Date de sortie', C.dateFR(r.dateSortie)], ['Heure', r.heureSortie || '—'],
            ['Référence', r.reference],
          ],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Motif invoqué par le patient', v: r.motif },
              { k: 'Risques exposés au patient', v: r.risques || '—' },
              { k: 'Avis du Procureur', v: r.avisProcureur ? ('Consigné — ' + (r.referenceProcureur || '')) : 'Sans objet' },
              { k: 'Décharge signée', v: r.decharge ? 'Oui' : 'Non' },
            ]),
            el('p.mt-4.text-\\[10px\\].leading-relaxed', {
              text: 'Je soussigné(e), patient(e) ou représentant légal, déclare quitter la CLINIQUE NASSIERA TOO SARL '
                + 'contre l’avis du médecin traitant. J’ai été pleinement informé(e) des risques encourus pour ma santé '
                + 'et je décharge l’établissement ainsi que son personnel de toute responsabilité quant aux conséquences '
                + 'de cette décision.',
            }),
          ]),
          signatures: [
            { role: 'Le Patient ou son représentant', mention: 'Signature précédée de la mention « lu et approuvé »' },
            { role: 'Le Médecin', mention: 'Signature' },
            { role: 'La Direction', mention: 'Visa' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * OUTILLAGE COMMUN AU BLOC ET À L'ADMINISTRATION
   * ======================================================================== */
  function colSoignants3() {
    return S.collection('soignants', { module: 'M14', entite: 'soignant', prefix: 'SOI' });
  }
  function optionsSoignants(filtre) {
    return colSoignants3().active().filter(filtre || function () { return true; })
      .map(function (x) { return { value: x.id, label: x.nomComplet + ' — ' + x.poste }; });
  }
  function nomSoignant(id) {
    var x = colSoignants3().active().filter(function (y) { return y.id === id; })[0];
    return x ? x.nomComplet : '—';
  }
  function optionsPatients3() {
    return C.sortBy(S.collection('patients').active(), 'code').map(function (p2) {
      return { value: p2.code, label: p2.code + ' — ' + p2.nom + ' ' + p2.prenom };
    });
  }
  function patientParCode3(code) {
    return S.collection('patients').active().filter(function (p2) { return p2.code === code; })[0] || null;
  }

  /* ==========================================================================
   * ADMINISTRATION DES TRAITEMENTS EN HOSPITALISATION
   * --------------------------------------------------------------------------
   * Le service ne voit QUE ce qui lui revient : la première administration
   * d'un traitement hospitalier appartient à la salle de soins, pas ici. Le
   * partage est calculé par la règle de relais (D.secteurAdministrateur), pas
   * par un filtre écrit dans cet écran — trois postes posent la même question,
   * trois réponses auraient divergé au premier correctif.
   * ======================================================================== */
  global.SIGH.screen('m3-administrations', {
    title: 'Administration des traitements',
    description: 'Administrations dues au service d’hospitalisation, à partir du deuxième passage.',
    regle: 'La <strong>première</strong> administration d’un traitement hospitalier revient à la '
      + '<strong>salle de soins</strong> ; les <strong>suivantes</strong> à l’hospitalisation. '
      + 'Un traitement ambulatoire ne passe jamais par ce poste. '
      + 'Une prescription non réglée reste visible mais non exécutable.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var dus = PR.soinsDuSecteur('hospitalisation');
        var faites = S.collection('administrations', { module: 'M3', entite: 'administration de traitement', prefix: 'ADM' })
          .active().filter(function (a) { return a.secteur === 'hospitalisation'; });
        var lignes = dus.reduce(function (n, d) { return n + d.lignes.length; }, 0);
        var bloquees = dus.reduce(function (n, d) {
          return n + d.lignes.filter(function (l) { return l.bloque; }).length;
        }, 0);

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Patients concernés', value: C.num(dus.length), icon: 'users', tone: 'navy' },
          { label: 'Administrations dues', value: C.num(lignes), icon: 'pill', tone: 'info' },
          { label: 'Déjà administrées ici', value: C.num(faites.length), icon: 'check-check', tone: 'success' },
          { label: 'Bloquées faute de règlement', value: C.num(bloquees), icon: 'lock',
            tone: bloquees ? 'warning' : 'neutral' },
        ]));

        vue.appendChild(K.note('Ce poste ne voit pas les <strong>premières</strong> administrations : elles '
          + 'appartiennent à la salle de soins. C’est le relais décrit par la Direction — le rang du passage '
          + 'décide du secteur, et non l’inverse.', { tone: 'info', icon: 'route' }));

        var rows = [];
        dus.forEach(function (d) {
          d.lignes.forEach(function (l) {
            rows.push({
              prescription: d.prescription, ligne: l,
              reference: d.prescription.reference,
              patient: d.prescription.patient, patientCode: d.prescription.patientCode,
              libelle: l.ligne.libelle, rang: l.rang, total: l.total,
              motif: l.motif, bloque: l.bloque,
            });
          });
        });

        vue.appendChild(U.tabs([
          { id: 'dues', label: 'À administrer', badge: rows.length, render: function () { return tableauDues(rows); } },
          { id: 'faites', label: 'Historique', badge: faites.length, render: function () { return tableauFaites(faites); } },
        ]));
        U.icons(vue);
      }

      function tableauDues(rows) {
        return U.dataTable({
          rows: rows,
          empty: 'Aucune administration due à l’hospitalisation pour l’instant.',
          columns: [
            { key: 'reference', label: 'Prescription' },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
            { key: 'libelle', label: 'Acte ou produit' },
            { key: 'rang', label: 'Passage', align: 'center', render: function (r) { return r.rang + ' / ' + r.total; } },
            { key: 'motif', label: 'Pourquoi ce poste',
              render: function (r) { return el('span.text-xs.text-slate-500', { text: r.motif }); } },
            { key: 'bloque', label: 'État',
              render: function (r) { return r.bloque ? U.badge('Non réglée', 'warning') : U.badge('Exécutable', 'success'); } },
          ],
          rowActions: function (r) {
            if (r.bloque) {
              return [K.iconBtn('lock', 'Bloquée : la prescription n’est pas réglée', function () {
                U.toast('Administration bloquée — la prescription ' + r.reference + ' n’est pas réglée.',
                  { type: 'warning' });
              })];
            }
            if (!K.droits('M3').editer) return [];
            return [K.btn('Administrer', { variant: 'primary', size: 'sm', icon: 'check',
              onclick: function () { administrer(r); } })];
          },
        });
      }

      function tableauFaites(rows) {
        return U.dataTable({
          rows: C.sortBy(rows, 'dateHeure').reverse(),
          empty: 'Aucune administration enregistrée par ce poste.',
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'dateHeure', label: 'Date et heure', render: function (r) { return C.dateHeure(r.dateHeure); } },
            { key: 'patient', label: 'Patient' },
            { key: 'libelle', label: 'Acte ou produit' },
            { key: 'rang', label: 'Passage', align: 'center', render: function (r) { return r.rang + ' / ' + r.total; } },
            { key: 'executant', label: 'Exécutant' },
            { key: 'observation', label: 'Observation', render: function (r) { return r.observation || '—'; } },
          ],
        });
      }

      function administrer(r) {
        var f = U.form([
          { name: 'executantId', label: 'Exécutant', type: 'select', required: true,
            options: optionsSoignants(function (x) {
              return x.execute && (x.secteurs || []).indexOf('hospitalisation') !== -1;
            }),
            hint: 'Infirmiers et sages-femmes. Le médecin prescrit, il n’exécute pas les soins.' },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2 },
        ], {});
        var m = U.modal({
          title: 'Administrer — ' + r.libelle,
          subtitle: r.patient + ' — passage ' + r.rang + ' sur ' + r.total,
          body: el('div.space-y-3', null, K.note(r.motif, { tone: 'info', icon: 'route' }), f),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Confirmer l’administration', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var res = PR.administrer(r.prescription.id, {
                  ligneIndex: r.ligne.index, secteur: 'hospitalisation',
                  executantId: v.executantId, observation: v.observation,
                });
                if (!res.ok) { U.toast(res.motif, { type: 'error' }); return; }
                m.close(); afficher();
                U.toast('Administration n° ' + res.rang + ' enregistrée.', {
                  type: 'success', detail: r.libelle + ' — ' + r.patient });
              } }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * BLOC OPÉRATOIRE — COMPTE RENDU OPÉRATOIRE
   * --------------------------------------------------------------------------
   * Les huit rubriques dictées par la Direction, dans son ordre. Le NIP figure
   * à part de l'identité : c'est le numéro que porte le dossier papier, recopié
   * tel quel sur la pièce.
   *
   * TROIS INTERVENANTS NOMMÉS — opérateur, aide-opérateur, anesthésiste. Un
   * compte rendu opératoire sans ses opérateurs n'a aucune valeur de preuve :
   * c'est la pièce qu'on ressort quand une suite opératoire est contestée.
   * ======================================================================== */
  global.SIGH.screen('m3-bloc-cro', {
    title: 'Comptes rendus opératoires',
    description: 'Rédaction et impression du compte rendu opératoire du secteur Bloc.',
    regle: 'Le compte rendu opératoire est une <strong>pièce de preuve</strong> : il porte ses trois intervenants '
      + 'nommés — opérateur, aide-opérateur et anesthésiste. Le <strong>NIP</strong> y est recopié du dossier. '
      + 'Un compte rendu sans opérateur ne vaut rien le jour où une suite opératoire est contestée.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col2() {
        return S.collection('crOperatoires', { module: 'M3', entite: 'compte rendu opératoire', prefix: 'CRO' });
      }

      function champs() {
        return [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients3() },
          { name: 'nip', label: 'NIP', type: 'text', required: true,
            hint: 'Recopié du dossier — c’est le numéro que porte la fiche d’observation.' },
          { name: 'dateOperation', label: 'Date de l’intervention', type: 'date', required: true },
          { name: 'diagnosticPeroperatoire', label: 'Diagnostic peropératoire', type: 'textarea', rows: 2, required: true },
          { name: 'intervention', label: 'Intervention chirurgicale', type: 'textarea', rows: 2, required: true },
          { name: 'anesthesie', label: 'Anesthésie', type: 'textarea', rows: 2, required: true },
          { name: 'cro', label: 'Compte rendu opératoire proprement dit', type: 'textarea', rows: 10, required: true },
          { name: 'operateurId', label: 'Opérateur', type: 'select', required: true,
            options: optionsSoignants(function (x) { return x.qualite === 'medecin'; }) },
          { name: 'aideOperateurId', label: 'Aide-opérateur', type: 'select',
            options: [{ value: '', label: '— aucun —' }].concat(optionsSoignants()) },
          { name: 'anesthesisteId', label: 'Anesthésiste', type: 'select', required: true,
            options: optionsSoignants() },
        ];
      }

      function afficher() {
        var rows = col2().active();
        var mois = rows.filter(function (r) {
          return String(r.dateOperation || '').slice(0, 7) === C.iso(new Date()).slice(0, 7);
        });
        var sansAide = rows.filter(function (r) { return !r.aideOperateurId; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Comptes rendus', value: C.num(rows.length), icon: 'scissors', tone: 'navy' },
          { label: 'Ce mois-ci', value: C.num(mois.length), icon: 'calendar', tone: 'info' },
          { label: 'Sans aide-opérateur', value: C.num(sansAide.length), icon: 'user-minus',
            tone: 'neutral', hint: 'l’aide-opérateur n’est pas obligatoire' },
          { label: 'Interventions au catalogue', value: C.num((D.tarifParFamille ? D.tarifParFamille('GYNECO') : []).length),
            icon: 'list', tone: 'neutral', hint: 'actes gynéco-obstétricaux' },
        ]));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'dateOperation').reverse(),
          empty: 'Aucun compte rendu opératoire enregistré.',
          actions: [K.creer(col2(), champs(), {
            module: 'M3', label: 'Nouveau compte rendu', titre: 'Compte rendu opératoire',
            entite: 'Compte rendu opératoire', size: 'lg', apres: afficher,
            transform: function (v) {
              var pt = patientParCode3(v.patientCode);
              return Object.assign({}, v, {
                reference: C.nextRef('CRO-', 4),
                patientId: pt ? pt.id : null,
                patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                operateur: nomSoignant(v.operateurId),
                aideOperateur: v.aideOperateurId ? nomSoignant(v.aideOperateurId) : null,
                anesthesiste: nomSoignant(v.anesthesisteId),
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'dateOperation', label: 'Date', render: function (r) { return C.dateFR(r.dateOperation); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — NIP ' + (r.nip || '—'); } },
            { key: 'intervention', label: 'Intervention' },
            { key: 'operateur', label: 'Opérateur' },
            { key: 'anesthesiste', label: 'Anesthésiste' },
          ],
          rowActions: function (r) {
            return [K.iconBtn('printer', 'Imprimer le compte rendu', function () { imprimer(r); })]
              .concat(K.actionsLigne(col2(), champs(), {
                module: 'M3', detail: detail, refresh: afficher,
                titre: function (x) { return x.reference; },
              })(r));
          },
        }));
        U.icons(vue);
      }

      function detail(r) {
        return el('div.space-y-4', null,
          K.grid([
            ['Référence', r.reference], ['Date', C.dateFR(r.dateOperation)],
            ['Patient', r.patient], ['NIP', r.nip || '—'],
            ['Opérateur', r.operateur], ['Aide-opérateur', r.aideOperateur || '—'],
            ['Anesthésiste', r.anesthesiste],
          ]),
          K.section('Diagnostic peropératoire', el('p.text-sm.text-slate-600', { text: r.diagnosticPeroperatoire || '—' })),
          K.section('Intervention chirurgicale', el('p.text-sm.text-slate-600', { text: r.intervention || '—' })),
          K.section('Anesthésie', el('p.text-sm.text-slate-600', { text: r.anesthesie || '—' })),
          K.section('Compte rendu opératoire',
            el('p.whitespace-pre-line.text-sm.text-slate-600', { text: r.cro || '—' })));
      }

      function imprimer(r) {
        /* Une rubrique du compte rendu : un intitulé souligné, puis le texte
           tel qu'il a été rédigé — les retours à la ligne du praticien sont
           conservés, c'est ainsi qu'il structure son récit opératoire. */
        function rubrique(titre, texte) {
          return el('div.mb-3', null, [
            el('p.mb-1.text-\\[10px\\].font-semibold.uppercase.tracking-wide', { text: titre }),
            el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', { text: texte || '—' }),
          ]);
        }
        P.etat({
          titre: 'COMPTE RENDU OPÉRATOIRE',
          sousTitre: r.reference + ' — ' + r.patient,
          cartouche: [
            ['Patient', r.patient], ['NIP', r.nip || '—'],
            ['Dossier', r.patientCode || '—'],
            ['Date de l’intervention', C.dateFR(r.dateOperation)],
            ['Opérateur', r.operateur],
            ['Aide-opérateur', r.aideOperateur || '—'],
            ['Anesthésiste', r.anesthesiste],
          ],
          contenu: el('div', null, [
            rubrique('Diagnostic peropératoire', r.diagnosticPeroperatoire),
            rubrique('Intervention chirurgicale', r.intervention),
            rubrique('Anesthésie', r.anesthesie),
            rubrique('Compte rendu opératoire', r.cro),
          ]),
          /* Trois signatures, parce que trois responsabilités distinctes sont
             engagées. Les fondre en une seule ferait porter à l'opérateur ce
             qui relève de l'anesthésiste. */
          signatures: [
            { role: 'L’opérateur', nom: r.operateur },
            { role: 'L’aide-opérateur', nom: r.aideOperateur || '—' },
            { role: 'L’anesthésiste', nom: r.anesthesiste },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * CHECK-LISTES DU BLOC — ENTRÉE ET SORTIE
   * --------------------------------------------------------------------------
   * DEUX listes distinctes, à deux moments distincts. Les fondre en une seule
   * ferait cocher après l'intervention ce qui devait l'être avant, ce qui vide
   * l'exercice de tout son sens.
   *
   * Le contenu proposé n'est PAS repris d'un document de la clinique : elle
   * n'en a pas remis. Il est donc marqué à valider, et l'écran le dit.
   * ======================================================================== */
  global.SIGH.screen('m3-bloc-checklist', {
    title: 'Check-listes du bloc',
    description: 'Vérifications avant l’incision (entrée) et avant la sortie de salle (sortie).',
    regle: 'Deux listes <strong>séparées</strong>, à deux moments distincts : les fondre ferait cocher après '
      + 'l’intervention ce qui devait l’être avant. Les items proposés ne viennent d’<strong>aucun document '
      + 'remis par la clinique</strong> — proposés à ce titre, puis <strong>arrêtés par les praticiens '
      + 'du bloc le 01/09/2026</strong> (validation écrite). Ils restent administrables.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col3() {
        return S.collection('checklistsBloc', { module: 'M3', entite: 'check-liste', prefix: 'CKL' });
      }

      function afficher() {
        var rows = col3().active();
        var entrees = rows.filter(function (r) { return r.moment === 'entree'; });
        var sorties = rows.filter(function (r) { return r.moment === 'sortie'; });
        var incompletes = rows.filter(function (r) { return r.coches < r.total; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Check-listes remplies', value: C.num(rows.length), icon: 'list-checks', tone: 'navy' },
          { label: 'Entrée', value: C.num(entrees.length), icon: 'log-in', tone: 'info' },
          { label: 'Sortie', value: C.num(sorties.length), icon: 'log-out', tone: 'info' },
          { label: 'Incomplètes', value: C.num(incompletes.length), icon: 'triangle-alert',
            tone: incompletes.length ? 'warning' : 'success' },
        ]));

        vue.appendChild(D.CHECKLIST_BLOC.aValider
          ? K.note('Les items proposés suivent la pratique courante de sécurité au bloc. '
            + 'La clinique n’a remis <strong>aucune check-liste écrite</strong> : cette liste est une '
            + '<strong>proposition à valider</strong> par le Directeur Médical, pas une donnée reprise d’une source.',
          { tone: 'warning', icon: 'triangle-alert' })
          : K.note('Check-listes <strong>arrêtées par les praticiens du bloc le '
            + C.dateFR(D.CHECKLIST_BLOC.arreteLe) + '</strong> (validation écrite). Proposées à '
            + 'l’origine faute de document remis — la provenance reste dite.',
          { tone: 'info', icon: 'check-circle-2' }));

        vue.appendChild(U.tabs([
          { id: 'entree', label: 'Check-liste d’entrée', badge: entrees.length,
            render: function () { return panneau('entree', 'Avant l’incision', D.CHECKLIST_BLOC.entree, entrees); } },
          { id: 'sortie', label: 'Check-liste de sortie', badge: sorties.length,
            render: function () { return panneau('sortie', 'Avant la sortie de salle', D.CHECKLIST_BLOC.sortie, sorties); } },
        ]));
        U.icons(vue);
      }

      function panneau(moment, sousTitre, items, rows) {
        return el('div.space-y-4', null,
          U.dataTable({
            rows: C.sortBy(rows, 'dateHeure').reverse(),
            empty: 'Aucune check-liste ' + (moment === 'entree' ? 'd’entrée' : 'de sortie') + ' enregistrée.',
            actions: K.droits('M3').editer ? [K.btn('Remplir la check-liste', {
              variant: 'primary', size: 'sm', icon: 'plus',
              onclick: function () { remplir(moment, sousTitre, items); },
            })] : [],
            columns: [
              { key: 'reference', label: 'Référence' },
              { key: 'dateHeure', label: 'Date et heure', render: function (r) { return C.dateHeure(r.dateHeure); } },
              { key: 'patient', label: 'Patient' },
              { key: 'responsable', label: 'Responsable' },
              { key: 'coches', label: 'Vérifié', align: 'center',
                render: function (r) {
                  return r.coches === r.total
                    ? U.badge(r.coches + ' / ' + r.total, 'success')
                    : U.badge(r.coches + ' / ' + r.total, 'warning');
                } },
            ],
            rowActions: K.actionsLigne(col3(), null, {
              module: 'M3', refresh: afficher,
              detail: function (r) {
                return el('div.space-y-4', null,
                  K.grid([
                    ['Référence', r.reference], ['Moment', r.moment === 'entree' ? 'Entrée' : 'Sortie'],
                    ['Date et heure', C.dateHeure(r.dateHeure)], ['Patient', r.patient],
                    ['Responsable', r.responsable],
                  ]),
                  K.section('Points vérifiés',
                    K.miniTable(['Point', 'Vérifié'], (r.items || []).map(function (it) {
                      return [it.label, it.coche ? 'Oui' : 'NON'];
                    }))));
              },
              titre: function (r) { return r.reference; },
            }),
          }));
      }

      function remplir(moment, sousTitre, items) {
        var champsList = [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients3() },
          { name: 'responsableId', label: 'Responsable de la vérification', type: 'select', required: true,
            options: optionsSoignants() },
          { type: 'section', label: sousTitre },
        ].concat(items.map(function (label, i) {
          return { name: 'it' + i, label: label, type: 'checkbox' };
        }));

        var f = U.form(champsList, {});
        var m = U.modal({
          title: 'Check-liste ' + (moment === 'entree' ? 'd’entrée' : 'de sortie'),
          subtitle: sousTitre + ' — cocher chaque point vérifié.',
          size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var pt = patientParCode3(v.patientCode);
                var lignes = items.map(function (label, i) { return { label: label, coche: !!v['it' + i] }; });
                var coches = lignes.filter(function (x) { return x.coche; }).length;
                var res = col3().insert({
                  reference: C.nextRef('CKL-', 4), moment: moment,
                  dateHeure: new Date().toISOString(),
                  patientId: pt ? pt.id : null,
                  patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                  responsableId: v.responsableId, responsable: nomSoignant(v.responsableId),
                  items: lignes, coches: coches, total: lignes.length,
                });
                m.close(); afficher();
                /* Une check-liste incomplète n'est pas refusée — elle est
                   SIGNALÉE. Refuser l'enregistrement pousserait à cocher tout
                   pour pouvoir avancer, ce qui est exactement le contraire du
                   but recherché. */
                U.toast(coches === lignes.length
                  ? 'Check-liste complète enregistrée.'
                  : 'Check-liste enregistrée — ' + (lignes.length - coches) + ' point(s) NON vérifié(s).',
                { type: coches === lignes.length ? 'success' : 'warning',
                  detail: res.record.reference,
                  undo: function () { col3().archive(res.record.id); afficher(); },
                  undoMessage: 'Check-liste annulée — la fiche est archivée.' });
              } }),
          ],
        });
      }
    },
  });


  /* ==========================================================================
   * FICHE DE SURVEILLANCE — LA MÊME DONNÉE QUE LA FEUILLE DE TEMPÉRATURE
   * --------------------------------------------------------------------------
   * Le document papier existe en DEUX présentations et c'est délibéré :
   *
   *   - la FEUILLE DE TEMPÉRATURE est un GRAPHIQUE à cinq échelles parallèles,
   *     lu d'un coup d'œil au pied du lit ;
   *   - la FICHE DE SURVEILLANCE est le MÊME relevé en tableau, où l'on écrit.
   *
   * Une seule collection alimente les deux. Les tenir séparées produirait deux
   * vérités divergentes sur les constantes d'un même patient — exactement ce
   * que la numérisation doit supprimer.
   *
   * L'écran lit AUSSI les constantes prises à l'accueil : le patient arrive,
   * on le mesure, puis il est hospitalisé — la mesure d'accueil est la première
   * ligne de sa surveillance, pas une donnée d'un autre monde.
   * ======================================================================== */
  var ECHELLES_TEMPERATURE = [
    { code: 'ta', label: 'TA', unite: 'cmHg', graduations: [5, 10, 15, 20, 25, 30], couleur: '#7c3aed' },
    { code: 'pouls', label: 'Pouls', unite: 'bpm', graduations: [60, 80, 100, 120, 140, 180], couleur: '#dc2626' },
    { code: 'temperature', label: 'T°', unite: '°C', graduations: [36, 37, 38, 39, 40, 41], couleur: '#0f766e' },
    { code: 'fr', label: 'FR', unite: '/min', graduations: [10, 20, 30, 40, 50, 60], couleur: '#2563eb' },
    { code: 'diurese', label: 'Diurèse', unite: 'L', graduations: [0, 0.5, 1, 1.5, 2, 2.5], couleur: '#ca8a04' },
  ];

  var MOMENTS = [
    { code: 'matin', abrev: 'M', label: 'Matin' },
    { code: 'midi', abrev: 'Mi', label: 'Midi' },
    { code: 'soir', abrev: 'S', label: 'Soir' },
  ];

  /* Les cinq séries partagent SIX lignes de grille. La position d'une valeur
     se calcule donc par interpolation entre deux graduations — et NON par une
     règle de trois sur les bornes. L'échelle du pouls n'est pas linéaire
     (60·80·100·120·140·180) : le dernier intervalle vaut le double des
     précédents, et une règle de trois placerait tous les points hauts au
     mauvais endroit. */
  function positionSurEchelle(echelle, valeur) {
    var g = echelle.graduations;
    if (valeur == null || isNaN(valeur)) return null;
    if (valeur <= g[0]) return 0;
    if (valeur >= g[g.length - 1]) return 1;
    for (var i = 0; i < g.length - 1; i++) {
      if (valeur >= g[i] && valeur <= g[i + 1]) {
        var dans = (valeur - g[i]) / (g[i + 1] - g[i]);
        return (i + dans) / (g.length - 1);
      }
    }
    return null;
  }

  function colConstantes3() {
    return S.collection('constantes', { module: 'M1', entite: 'relevé de constantes', prefix: 'CST' });
  }

  /* Le moment de la journée déduit de l'heure : la feuille papier porte trois
     colonnes par date, et un relevé de 14 h appartient à celle du midi. */
  function momentDe(heure) {
    var h = parseInt(String(heure || '').slice(0, 2), 10);
    if (isNaN(h)) return 'matin';
    if (h < 11) return 'matin';
    if (h < 17) return 'midi';
    return 'soir';
  }

  /* La tension systolique, en cmHg, extraite d'une notation « 12/8 ». C'est
     elle que la feuille de température trace — la diastolique ne figure pas
     sur l'échelle du document. */
  function systoliqueDe(tension) {
    var m = String(tension || '').match(/^\s*(\d+(?:[.,]\d+)?)/);
    return m ? Number(String(m[1]).replace(',', '.')) : null;
  }

  /* ==========================================================================
   * LES RELEVÉS D'UN PATIENT — UNE SEULE SÉRIE, DEUX SOURCES
   * --------------------------------------------------------------------------
   * Deux collections portent des constantes, pour des raisons d'histoire :
   * `constantes` (relevée à l'accueil) et `releves` (relevée au lit du
   * patient hospitalisé). Migrer l'une dans l'autre casserait la feuille de
   * température existante et ferait perdre l'historique.
   *
   * La fiche de surveillance les lit donc TOUTES LES DEUX et les présente comme
   * une seule série — ce qu'elles sont. Le patient est mesuré à l'accueil, puis
   * il est hospitalisé : sa courbe est continue. Les séparer ferait apparaître
   * deux patients là où il n'y en a qu'un, et la première mesure — celle de
   * l'accueil, souvent la plus alarmante — disparaîtrait du graphique.
   * ======================================================================== */
  function relevesDe(patientId) {
    var out = [];

    /* Source 1 — l'accueil. */
    colConstantes3().active().filter(function (c) { return c.patientId === patientId; })
      .forEach(function (c) {
        out.push({
          date: String(c.dateHeure || '').slice(0, 10),
          moment: c.moment || momentDe(C.heure(c.dateHeure)),
          heure: C.heure(c.dateHeure),
          temperature: c.temperature,
          ta: c.tensionSys != null ? Number(c.tensionSys) : systoliqueDe(c.tension),
          tension: c.tension,
          pouls: c.pouls, fr: c.fr, spo2: c.spo2, diurese: c.diurese,
          par: c.releveePar, origine: 'Accueil',
        });
      });

    /* Source 2 — l'hospitalisation. Le relevé y est rattaché à l'admission,
       il faut donc remonter à son patient. */
    var admissions = S.collection('admissions').active()
      .filter(function (a) { return a.patientId === patientId; })
      .map(function (a) { return a.id; });
    if (admissions.length) {
      S.collection('releves', { module: 'M3', entite: 'FeuilleTemperature' }).active()
        .filter(function (r) { return admissions.indexOf(r.admissionId) !== -1; })
        .forEach(function (r) {
          out.push({
            date: r.date, moment: momentDe(r.heure), heure: r.heure,
            temperature: r.temperature != null ? Number(r.temperature) : null,
            ta: systoliqueDe(r.tension), tension: r.tension,
            pouls: r.fc, fr: r.fr, spo2: r.spo2,
            /* La diurèse est saisie en millilitres au lit du patient, tandis
               que l'échelle de la feuille est graduée en litres. Convertir ici
               évite de tracer 1 800 sur une échelle qui s'arrête à 2,5. */
            diurese: r.diurese != null ? Math.round((r.diurese / 1000) * 100) / 100 : null,
            par: r.saisiPar, origine: 'Hospitalisation',
          });
        });
    }

    return out.sort(function (a, b) {
      var d = String(a.date).localeCompare(String(b.date));
      return d !== 0 ? d : String(a.heure).localeCompare(String(b.heure));
    });
  }

  global.SIGH.screen('m3-surveillance', {
    title: 'Fiche de surveillance',
    description: 'Relevé horodaté des constantes et courbe de surveillance à cinq échelles.',
    regle: 'La <strong>feuille de température</strong> et la <strong>fiche de surveillance</strong> sont deux '
      + 'présentations d’une <strong>même donnée</strong> : une seule collection les alimente, sans quoi un '
      + 'même patient aurait deux séries de constantes divergentes. L’échelle du pouls '
      + '<strong>n’est pas linéaire</strong> — elle est tracée telle que le document la porte.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      /* Les patients suivis viennent des DEUX sources : un hospitalisé dont les
         constantes sont relevées au lit doit apparaître même si personne ne
         l'a mesuré à l'accueil. */
      function patientsSuivis() {
        var ids = {};
        colConstantes3().active().forEach(function (c) { if (c.patientId) ids[c.patientId] = true; });
        var parAdmission = {};
        S.collection('admissions').active().forEach(function (a) { parAdmission[a.id] = a.patientId; });
        S.collection('releves', { module: 'M3', entite: 'FeuilleTemperature' }).active()
          .forEach(function (r) {
            var pid = parAdmission[r.admissionId];
            if (pid) ids[pid] = true;
          });
        return S.collection('patients').active().filter(function (p2) { return ids[p2.id]; });
      }

      function afficher() {
        var pts = patientsSuivis();
        C.clear(vue);

        if (!pts.length) {
          vue.appendChild(U.card(null, U.empty('Aucune constante relevée.', {
            icon: 'thermometer',
            hint: 'Les constantes se saisissent à l’accueil ou au lit du patient ; elles alimentent cette fiche.',
            action: K.lien('m1-constantes', 'Relever des constantes', { variant: 'primary', icon: 'plus' }),
          })));
          U.icons(vue);
          return;
        }

        /* Le compteur porte sur les DEUX sources, comme la courbe : annoncer
           « 0 relevé » au-dessus d'un graphique qui en trace deux cents ferait
           douter du graphique, pas du compteur. */
        var tous = [];
        pts.forEach(function (p2) { tous = tous.concat(relevesDe(p2.id)); });
        var jourCourant = C.iso(new Date());
        vue.appendChild(U.kpiGrid([
          { label: 'Patients suivis', value: C.num(pts.length), icon: 'users', tone: 'navy' },
          { label: 'Relevés enregistrés', value: C.num(tous.length), icon: 'activity', tone: 'info',
            hint: 'accueil et lit du patient réunis' },
          { label: 'Relevés du jour', value: C.num(tous.filter(function (c) {
            return c.date === jourCourant;
          }).length), icon: 'calendar', tone: 'success' },
          { label: 'Échelles suivies', value: C.num(ECHELLES_TEMPERATURE.length), icon: 'chart-line',
            tone: 'neutral', hint: 'TA, pouls, température, FR, diurèse' },
        ]));

        var sel = el('select.h-10.rounded-lg.border.border-slate-300.px-3.text-sm');
        pts.forEach(function (p2) {
          sel.appendChild(el('option', { value: p2.id, text: p2.code + ' — ' + p2.nom + ' ' + p2.prenom }));
        });
        var host = el('div.space-y-4');
        sel.addEventListener('change', function () { rendre(sel.value); });

        vue.appendChild(U.card('Patient suivi', el('div.flex.flex-wrap.items-center.gap-3', null, [
          el('label.text-sm.font-medium.text-slate-600', { text: 'Sélectionner un patient' }), sel,
        ])));
        vue.appendChild(host);
        rendre(pts[0].id);
        U.icons(vue);

        function rendre(pid) {
          var p2 = S.collection('patients').active().filter(function (x) { return x.id === pid; })[0];
          var rel = relevesDe(pid);
          C.clear(host);
          host.appendChild(courbe(p2, rel));
          host.appendChild(tableau(p2, rel));
          U.icons(host);
        }
      }

      /* La courbe à cinq échelles, telle que la feuille papier la porte :
         sept dates, trois moments par date, six lignes de grille partagées. */
      function courbe(p2, rel) {
        var jours = rel.map(function (r) { return r.date; })
          .filter(function (v, i, a) { return a.indexOf(v) === i; }).slice(-7);
        var colonnes = [];
        jours.forEach(function (j) {
          MOMENTS.forEach(function (m) {
            var r = rel.filter(function (x) { return x.date === j && x.moment === m.code; })[0];
            colonnes.push({ jour: j, moment: m, releve: r || null });
          });
        });

        var H = 260, L = 60, largeur = Math.max(colonnes.length * 34, 300);
        var svg = el('svg', { class: 'block', width: L + largeur + 12, height: H + 46,
          viewBox: '0 0 ' + (L + largeur + 12) + ' ' + (H + 46) });

        function ligne(attrs) { return document.createElementNS('http://www.w3.org/2000/svg', 'line'); }
        function ns(tag, attrs) {
          var n = document.createElementNS('http://www.w3.org/2000/svg', tag);
          Object.keys(attrs || {}).forEach(function (k) { n.setAttribute(k, attrs[k]); });
          return n;
        }

        /* Les six lignes de grille, partagées par les cinq échelles. */
        for (var i = 0; i < 6; i++) {
          var y = H - (i / 5) * H;
          svg.appendChild(ns('line', { x1: L, y1: y, x2: L + largeur, y2: y,
            stroke: '#e2e8f0', 'stroke-width': 1 }));
          /* Les graduations des cinq échelles, empilées à gauche. */
          var txt = ECHELLES_TEMPERATURE.map(function (e) {
            var g = e.graduations[i];
            return g % 1 ? g.toFixed(1) : g;
          }).join(' ');
          svg.appendChild(ns('text', { x: 2, y: y + 3, 'font-size': 7, fill: '#94a3b8' })).textContent = txt;
        }

        /* Les colonnes : une par moment. */
        colonnes.forEach(function (c, k) {
          var x = L + k * (largeur / Math.max(colonnes.length, 1)) + (largeur / Math.max(colonnes.length, 1)) / 2;
          svg.appendChild(ns('line', { x1: x, y1: 0, x2: x, y2: H,
            stroke: k % 3 === 0 ? '#cbd5e1' : '#f1f5f9', 'stroke-width': 1 }));
          var t = ns('text', { x: x, y: H + 12, 'font-size': 7, fill: '#64748b', 'text-anchor': 'middle' });
          t.textContent = c.moment.abrev;
          svg.appendChild(t);
          if (k % 3 === 1) {
            var d = ns('text', { x: x, y: H + 24, 'font-size': 7, fill: '#334155', 'text-anchor': 'middle' });
            d.textContent = C.dateFR(c.jour).slice(0, 5);
            svg.appendChild(d);
          }
        });

        /* Une polyligne par échelle. */
        ECHELLES_TEMPERATURE.forEach(function (e) {
          var pts = [];
          colonnes.forEach(function (c, k) {
            if (!c.releve) return;
            /* E365 : une mesure ABSENTE n'est pas zéro. `Number(null)` valait 0 : la fréquence respiratoire, la tension ou la diurèse non relevées
               étaient tracées au pied de l'échelle, comme une mesure effondrée. */
            var brute = c.releve[e.code];
            if (brute == null || brute === '') return;
            var v = Number(brute);
            var pos = positionSurEchelle(e, v);
            if (pos == null) return;
            var x = L + k * (largeur / Math.max(colonnes.length, 1)) + (largeur / Math.max(colonnes.length, 1)) / 2;
            pts.push([x, H - pos * H]);
          });
          if (pts.length > 1) {
            svg.appendChild(ns('polyline', {
              points: pts.map(function (q) { return q[0] + ',' + q[1]; }).join(' '),
              fill: 'none', stroke: e.couleur, 'stroke-width': 1.6,
            }));
          }
          pts.forEach(function (q) {
            svg.appendChild(ns('circle', { cx: q[0], cy: q[1], r: 2.4, fill: e.couleur }));
          });
        });

        var legende = el('div.mt-3.flex.flex-wrap.gap-4');
        ECHELLES_TEMPERATURE.forEach(function (e) {
          legende.appendChild(el('span.inline-flex.items-center.gap-1.5.text-xs.text-slate-600', null, [
            el('span.inline-block.h-2.w-4.rounded', { style: 'background:' + e.couleur }),
            el('span', { text: e.label + ' (' + e.unite + ') — ' + e.graduations[0] + ' à ' + e.graduations[5] }),
          ]));
        });

        var carte = U.card('Feuille de température — ' + p2.nom + ' ' + p2.prenom,
          el('div', null, [
            el('div.overflow-x-auto', null, svg),
            legende,
            el('p.mt-2.text-xs.text-slate-400', {
              text: 'M = matin · Mi = midi · S = soir. Les cinq échelles partagent six lignes de grille, '
                + 'comme sur la feuille papier. L’échelle du pouls n’est pas linéaire : le dernier '
                + 'intervalle (140 → 180) vaut le double des précédents, et il est tracé comme tel.',
            }),
          ]));
        return carte;
      }

      function tableau(p2, rel) {
        return U.card('Relevés horodatés',
          U.dataTable({
            rows: rel.slice().reverse(),
            empty: 'Aucun relevé pour ce patient.',
            columns: [
              { key: 'date', label: 'Date', render: function (r) { return C.dateFR(r.date); } },
              { key: 'heure', label: 'Heure' },
              { key: 'moment', label: 'Moment', render: function (r) {
                var m = MOMENTS.filter(function (x) { return x.code === r.moment; })[0];
                return m ? m.label : '—';
              } },
              { key: 'temperature', label: 'Température', align: 'right',
                render: function (r) { return r.temperature == null ? '—' : r.temperature + ' °C'; } },
              { key: 'tension', label: 'TA', align: 'right', render: function (r) { return r.tension || '—'; } },
              { key: 'fr', label: 'FR', align: 'right', render: function (r) { return r.fr == null ? '—' : r.fr; } },
              { key: 'pouls', label: 'Pouls', align: 'right', render: function (r) { return r.pouls == null ? '—' : r.pouls; } },
              { key: 'diurese', label: 'Diurèse', align: 'right',
                render: function (r) { return r.diurese == null ? '—' : r.diurese + ' L'; } },
              { key: 'par', label: 'Relevé par' },
              { key: 'origine', label: 'Source',
                render: function (r) {
                  return U.badge(r.origine, r.origine === 'Accueil' ? 'info' : 'neutral');
                } },
            ],
          }));
      }
    },
  });

  /* ==========================================================================
   * SURVEILLANCE TRANSFUSIONNELLE
   * --------------------------------------------------------------------------
   * Un PROTOCOLE à temps imposés, relevé sur la fiche officielle : avant la
   * pose, 15 min, puis toutes les 30 minutes, à la fin, 1 heure après, 2 heures
   * après. Ces temps ne sont pas des suggestions — c'est la fenêtre pendant
   * laquelle un accident transfusionnel se déclare.
   *
   * ELLE RESTE OUVERTE QUAND LA BANQUE DE SANG EST FERMÉE. La clinique ne
   * collecte ni ne délivre de produits sanguins — mais elle en POSE, venus de
   * l'extérieur, et doit les surveiller. La description de poste de l'Infirmier
   * Général le confirme : « vérifier le bon remplissage des documents de
   * transfusion sanguine ». Fermer cette fiche avec la banque de sang aurait
   * supprimé la surveillance sans supprimer la transfusion.
   * ======================================================================== */
  var TEMPS_TRANSFUSION = [
    { code: 't0', label: 'Avant la pose' },
    { code: 't15', label: '15 min' },
    { code: 't30', label: '30 min' },
    { code: 't60', label: '60 min' },
    { code: 't90', label: '90 min' },
    { code: 'fin', label: 'Fin' },
    { code: 'h1', label: '1 heure après' },
    { code: 'h2', label: '2 heures après' },
  ];

  var ELEMENTS_TRANSFUSION = [
    { code: 'temperature', label: 'Température', unite: '°C' },
    { code: 'ta', label: 'Tension artérielle', unite: '' },
    { code: 'fr', label: 'Fréquence respiratoire', unite: '/min' },
    { code: 'fc', label: 'Fréquence cardiaque', unite: 'bpm' },
    { code: 'spo2', label: 'SpO₂', unite: '%' },
    { code: 'urines', label: 'Aspect des urines', unite: '' },
    { code: 'conscience', label: 'Conscience', unite: '' },
    { code: 'autre', label: 'Autre élément surveillé', unite: '',
      note: 'La huitième ligne du formulaire est illisible au scan — à confirmer par le service.' },
  ];

  global.SIGH.screen('m3-transfusion', {
    title: 'Surveillance transfusionnelle',
    description: 'Surveillance d’une transfusion à temps imposés : avant la pose, 15 min, toutes les 30 min, fin, 1 h et 2 h après.',
    regle: 'Les <strong>temps de relevé sont imposés</strong> par le protocole : ce n’est pas une '
      + 'périodicité de confort, c’est la fenêtre pendant laquelle un accident transfusionnel se déclare. '
      + 'Cette fiche reste <strong>ouverte quand la banque de sang est fermée</strong> : la clinique ne '
      + 'collecte pas de sang mais elle en pose, et doit le surveiller.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col4() {
        return S.collection('surveillancesTransfusion',
          { module: 'M3', entite: 'surveillance transfusionnelle', prefix: 'TRF' });
      }

      function afficher() {
        var rows = col4().active();
        var completes = rows.filter(function (r) { return r.releves === r.attendus; });
        var incidents = rows.filter(function (r) { return r.incident; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Surveillances', value: C.num(rows.length), icon: 'droplets', tone: 'navy' },
          { label: 'Protocole complet', value: C.num(completes.length), icon: 'check-check',
            tone: completes.length === rows.length ? 'success' : 'warning',
            hint: C.num(TEMPS_TRANSFUSION.length) + ' temps de relevé attendus' },
          { label: 'Incidents signalés', value: C.num(incidents.length), icon: 'siren',
            tone: incidents.length ? 'danger' : 'success' },
          { label: 'Éléments surveillés', value: C.num(ELEMENTS_TRANSFUSION.length), icon: 'activity', tone: 'info' },
        ]));

        vue.appendChild(K.note('La <strong>huitième ligne</strong> du formulaire officiel est illisible au scan. '
          + 'Elle figure ici sous l’intitulé provisoire « Autre élément surveillé » et reste '
          + '<strong>à confirmer par le service</strong> — deviner ce qu’un protocole de sécurité demande de '
          + 'surveiller serait la pire des improvisations.', { tone: 'warning', icon: 'triangle-alert' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'date').reverse(),
          empty: 'Aucune surveillance transfusionnelle enregistrée.',
          actions: K.droits('M3').editer ? [K.btn('Nouvelle surveillance', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: nouvelle,
          })] : [],
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'date', label: 'Date', render: function (r) { return C.dateFR(r.date); } },
            { key: 'patient', label: 'Patient' },
            { key: 'service', label: 'Service' },
            { key: 'pochePSL', label: 'Poche de PSL',
              render: function (r) { return el('span.font-mono.text-xs', { text: r.pochePSL }); } },
            { key: 'debut', label: 'Début de la transfusion' },
            { key: 'releves', label: 'Relevés', align: 'center',
              render: function (r) {
                return r.releves === r.attendus
                  ? U.badge(r.releves + ' / ' + r.attendus, 'success')
                  : U.badge(r.releves + ' / ' + r.attendus, 'warning');
              } },
            { key: 'incident', label: 'Incident', align: 'center',
              render: function (r) { return r.incident ? U.badge('OUI', 'danger') : U.badge('Non', 'success'); } },
          ],
          rowActions: K.actionsLigne(col4(), null, {
            module: 'M3', refresh: afficher,
            titre: function (r) { return r.reference; },
            detail: function (r) {
              var lignes = ELEMENTS_TRANSFUSION.map(function (e) {
                return [e.label].concat(TEMPS_TRANSFUSION.map(function (t) {
                  var v = ((r.valeurs || {})[t.code] || {})[e.code];
                  return v == null || v === '' ? '—' : String(v);
                }));
              });
              return el('div.space-y-4', null,
                K.grid([
                  ['Référence', r.reference], ['Patient', r.patient],
                  ['Service', r.service], ['Date', C.dateFR(r.date)],
                  ['Référence de la poche de PSL', r.pochePSL],
                  ['Heure de début de la transfusion', r.debut],
                  ['Responsable de la surveillance', r.responsable],
                  ['Incident', r.incident ? 'OUI — ' + (r.natureIncident || 'non précisé') : 'Non'],
                ]),
                K.section('Relevés du protocole',
                  el('div.overflow-x-auto', null,
                    K.miniTable(['Élément'].concat(TEMPS_TRANSFUSION.map(function (t) { return t.label; })), lignes))),
                r.conclusion ? K.section('Conclusion',
                  el('p.text-sm.text-slate-600', { text: r.conclusion })) : null);
            },
          }),
        }));
        U.icons(vue);
      }

      function nouvelle() {
        var champs = [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients3() },
          { name: 'service', label: 'Service', type: 'text', required: true },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'pochePSL', label: 'Référence de la poche de PSL', type: 'text', required: true,
            hint: 'Le numéro porté sur la poche — c’est lui qui rattache un incident à un produit.' },
          { name: 'debut', label: 'Heure du début de la transfusion', type: 'text', required: true },
          { name: 'responsableId', label: 'Responsable de la surveillance', type: 'select', required: true,
            options: optionsSoignants(function (x) { return x.execute; }) },
        ];
        TEMPS_TRANSFUSION.forEach(function (t) {
          champs.push({ type: 'section', label: t.label });
          ELEMENTS_TRANSFUSION.forEach(function (e) {
            champs.push({ name: t.code + '_' + e.code,
              label: e.label + (e.unite ? ' (' + e.unite + ')' : ''), type: 'text' });
          });
        });
        champs.push({ type: 'section', label: 'Conclusion' });
        champs.push({ name: 'incident', label: 'Un incident transfusionnel est survenu', type: 'checkbox' });
        champs.push({ name: 'natureIncident', label: 'Nature de l’incident', type: 'text' });
        champs.push({ name: 'conclusion', label: 'Conclusion', type: 'textarea', rows: 3, required: true });

        var f = U.form(champs, { date: C.iso(new Date()) });
        var m = U.modal({
          title: 'Surveillance transfusionnelle',
          subtitle: 'Les temps de relevé sont imposés par le protocole.',
          size: 'xl', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var pt = patientParCode3(v.patientCode);
                var valeurs = {}, releves = 0;
                TEMPS_TRANSFUSION.forEach(function (t) {
                  valeurs[t.code] = {};
                  var rempli = false;
                  ELEMENTS_TRANSFUSION.forEach(function (e) {
                    var x = v[t.code + '_' + e.code];
                    valeurs[t.code][e.code] = x;
                    if (x != null && x !== '') rempli = true;
                  });
                  if (rempli) releves++;
                });
                var rec = col4().insert({
                  reference: C.referenceSuivante('TRF-', 4, col4().all()),
                  patientId: pt ? pt.id : null,
                  patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                  patientCode: v.patientCode,
                  service: v.service, date: v.date,
                  pochePSL: v.pochePSL, debut: v.debut,
                  responsableId: v.responsableId, responsable: nomSoignant(v.responsableId),
                  valeurs: valeurs, releves: releves, attendus: TEMPS_TRANSFUSION.length,
                  incident: !!v.incident, natureIncident: v.natureIncident,
                  conclusion: v.conclusion,
                });
                m.close(); afficher();
                /* Un protocole incomplet est SIGNALÉ, jamais refusé : refuser
                   l'enregistrement ferait remplir n'importe quoi pour pouvoir
                   valider, ce qui est le contraire du but. */
                U.toast(releves === TEMPS_TRANSFUSION.length
                  ? 'Surveillance complète enregistrée.'
                  : 'Surveillance enregistrée — ' + (TEMPS_TRANSFUSION.length - releves) + ' temps non relevé(s).',
                { type: releves === TEMPS_TRANSFUSION.length ? 'success' : 'warning',
                  detail: rec.record.reference });
                if (v.incident) U.alerter('Incident transfusionnel signalé — poche ' + v.pochePSL, { type: 'danger' });
              } }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * SCORE DE GLASGOW
   * --------------------------------------------------------------------------
   * Le score est CALCULÉ, jamais saisi : il vaut de 3 à 15, et une saisie libre
   * autoriserait un « 2/15 » qui n'existe pas — les trois axes valant au
   * minimum 1 chacun. C'est la borne basse que les soignants vérifient en
   * premier lorsqu'ils relisent une feuille.
   * ======================================================================== */
  var GLASGOW = [
    { axe: 'Ouverture des yeux', items: [
      ['Spontanée', 4], ['Au bruit, à la parole', 3], ['À la douleur', 2], ['Aucune réponse', 1]] },
    { axe: 'Réponse verbale', items: [
      ['Normale', 5], ['Confuse', 4], ['Inappropriée', 3], ['Incompréhensible', 2], ['Aucune réponse', 1]] },
    { axe: 'Réponse motrice', items: [
      ['À la commande', 6], ['Localise la douleur', 5], ['Se retire à la douleur', 4],
      ['Flexion à la douleur', 3], ['Extension à la douleur', 2], ['Aucune réponse', 1]] },
  ];

  global.SIGH.screen('m3-glasgow', {
    title: 'Score de Glasgow',
    description: 'Évaluation de la conscience, adulte et enfant : ouverture des yeux, réponse verbale, réponse motrice.',
    regle: 'Le score est <strong>calculé</strong>, jamais saisi : il vaut de <strong>3 à 15</strong>, chaque '
      + 'axe valant au minimum 1. Une saisie libre autoriserait un « 2/15 » qui n’existe pas — et c’est la '
      + 'borne basse que les soignants vérifient en premier en relisant une feuille.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col5() {
        return S.collection('scoresGlasgow', { module: 'M3', entite: 'score de Glasgow', prefix: 'GCS' });
      }

      /* E364 : à la MODIFICATION, le formulaire ne lisait ni le patient (la fiche ne porte que son identifiant) ni les trois axes (elle porte
         `axes`, pas `axe0…2`) : il s'ouvrait sur le premier patient et sur les meilleures réponses, et l'enregistrement laissait le score
         inchangé. Le patient et les axes sont relus de la fiche, et le score est RECALCULÉ à l'enregistrement. */
      function codePatientDe(r) {
        if (!r) return undefined;
        if (r.patientCode) return r.patientCode;
        var p2 = S.collection('patients').active().filter(function (x) { return x.id === r.patientId; })[0];
        return p2 ? p2.code : undefined;
      }
      /* Le score est la SOMME des trois axes : il ne peut pas être saisi, donc il ne peut pas être faux — ni à la création, ni à la
         modification (E364 : la modification l'écrivait tel quel et laissait le score d'avant). */
      function transformerGlasgow(v, record) {
        var pt = patientParCode3(v.patientCode);
        var detailAxes = GLASGOW.map(function (g, i) {
          var pts = Number(v['axe' + i]);
          var it = g.items.filter(function (x) { return x[1] === pts; })[0];
          return { axe: g.axe, libelle: it ? it[0] : '—', points: pts };
        });
        var score = detailAxes.reduce(function (n, a) { return n + a.points; }, 0);
        return Object.assign({}, v, {
          reference: (record && record.reference) || C.referenceSuivante('GCS-', 4, col5().all()),
          patientId: pt ? pt.id : null,
          patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
          nip: v.nip || v.patientCode,
          axes: detailAxes, score: score,
          evaluateur: nomSoignant(v.evaluePar),
        });
      }

      function champs(record) {
        var out = [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients3(), value: codePatientDe(record) },
          { name: 'nip', label: 'NIP', type: 'text',
            hint: 'Recopié du dossier, comme sur la feuille papier.' },
          { name: 'dateHeure', label: 'Date et heure de l’évaluation', type: 'datetime-local', required: true },
        ];
        GLASGOW.forEach(function (g, i) {
          var deja = record && record.axes && record.axes[i] ? String(record.axes[i].points) : undefined;
          out.push({ name: 'axe' + i, label: g.axe, type: 'select', required: true, value: deja,
            options: g.items.map(function (it) {
              return { value: String(it[1]), label: it[0] + ' — ' + it[1] + ' point(s)' };
            }) });
        });
        out.push({ name: 'observation', label: 'Observation', type: 'textarea', rows: 2 });
        out.push({ name: 'evaluePar', label: 'Évalué par', type: 'select', required: true,
          options: optionsSoignants(function (x) { return x.execute || x.prescrit; }) });
        return out;
      }

      function afficher() {
        var rows = col5().active();
        var graves = rows.filter(function (r) { return r.score <= 8; });
        var moyens = rows.filter(function (r) { return r.score >= 9 && r.score <= 12; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Évaluations', value: C.num(rows.length), icon: 'brain', tone: 'navy' },
          { label: 'Score ≤ 8 — coma', value: C.num(graves.length), icon: 'siren',
            tone: graves.length ? 'danger' : 'success' },
          { label: 'Score 9 à 12', value: C.num(moyens.length), icon: 'triangle-alert',
            tone: moyens.length ? 'warning' : 'neutral' },
          { label: 'Patients évalués', value: C.num(rows.map(function (r) { return r.patientId; })
            .filter(function (v, i, a) { return v && a.indexOf(v) === i; }).length),
          icon: 'users', tone: 'info' },
        ]));

        vue.appendChild(K.note('Le logiciel <strong>calcule et signale</strong> ; il ne diagnostique pas. '
          + 'Un score de 8 ou moins est classiquement le seuil du coma, mais l’appréciation clinique revient '
          + 'au médecin — et un score isolé ne vaut rien sans son évolution.',
        { tone: 'info', icon: 'brain' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'dateHeure').reverse(),
          empty: 'Aucune évaluation enregistrée.',
          actions: [K.creer(col5(), champs(), {
            module: 'M3', label: 'Nouvelle évaluation', titre: 'Score de Glasgow',
            entite: 'Évaluation', apres: afficher,
            transform: function (v) { return transformerGlasgow(v, null); },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'dateHeure', label: 'Date et heure', render: function (r) { return C.dateHeure(r.dateHeure); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — NIP ' + (r.nip || '—'); } },
            { key: 'score', label: 'Score', align: 'center',
              render: function (r) {
                var ton = r.score <= 8 ? 'danger' : (r.score <= 12 ? 'warning' : 'success');
                return U.badge(r.score + ' / 15', ton);
              } },
            { key: 'evaluateur', label: 'Évalué par' },
          ],
          rowActions: K.actionsLigne(col5(), champs, {
            module: 'M3', refresh: afficher, transform: transformerGlasgow,
            titre: function (r) { return r.reference + ' — ' + r.score + '/15'; },
            detail: function (r) {
              return el('div.space-y-4', null,
                K.grid([
                  ['Référence', r.reference], ['Patient', r.patient], ['NIP', r.nip || '—'],
                  ['Date et heure', C.dateHeure(r.dateHeure)],
                  ['Score total', r.score + ' / 15 (calculé)'],
                  ['Évalué par', r.evaluateur],
                ]),
                K.section('Détail par axe',
                  K.miniTable(['Axe', 'Réponse observée', 'Points'],
                    (r.axes || []).map(function (a) { return [a.axe, a.libelle, String(a.points)]; }))),
                r.observation ? K.section('Observation',
                  el('p.text-sm.text-slate-600', { text: r.observation })) : null);
            },
          }),
        }));
        U.icons(vue);
      }
    },
  });

  /* ==========================================================================
   * RAPPORT MÉDICAL
   * --------------------------------------------------------------------------
   * Les quatorze rubriques du formulaire officiel, dans son ordre. Trois
   * couples y sont maintenus DISTINCTS parce que la clinique les distingue :
   *
   *   - hypothèses diagnostiques ≠ diagnostic retenu : les premières sont ce
   *     qu'on suspecte à l'entrée, le second ce que les examens ont confirmé ;
   *   - diagnostic retenu ≠ diagnostic de sortie : le second tient compte de
   *     l'évolution et des complications ;
   *   - traitement d'entrée ≠ traitement réajusté ≠ traitement de sortie.
   *
   * Les fondre ferait perdre exactement ce qui rend un rapport médical utile :
   * le cheminement.
   *
   * Le rapport s'imprime sous la VARIANTE C de l'en-tête — celle du document
   * réel, qui porte « CLINIQUE NASSIERA » sans TOO, un autre IFU et une
   * autorisation d'ouverture de 2008.
   * ======================================================================== */
  global.SIGH.screen('m3-rapport', {
    title: 'Rapport médical',
    description: 'Compte rendu complet d’un séjour : anamnèse, examen physique, diagnostics et traitements.',
    regle: 'Les <strong>hypothèses diagnostiques</strong>, le <strong>diagnostic retenu</strong> et le '
      + '<strong>diagnostic de sortie</strong> sont trois champs distincts, comme sur le formulaire officiel. '
      + 'Les fondre ferait perdre le cheminement, qui est précisément ce qui rend un rapport médical utile. '
      + 'Le rapport s’imprime sous la <strong>variante C</strong> de l’en-tête, celle du document réel.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col6() {
        return S.collection('rapportsMedicaux', { module: 'M3', entite: 'rapport médical', prefix: 'RAP' });
      }

      function champs() {
        return [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients3() },
          { name: 'dateEntree', label: 'Date d’entrée', type: 'date', required: true },
          { name: 'dateSortie', label: 'Date de sortie', type: 'date' },
          { name: 'motif', label: 'Motif de consultation', type: 'textarea', rows: 2, required: true },
          { name: 'anamnese', label: 'Anamnèse', type: 'textarea', rows: 4, required: true },
          { name: 'examenPhysique', label: 'Examen physique', type: 'textarea', rows: 5, required: true },
          { name: 'hypotheses', label: 'Hypothèses diagnostiques', type: 'textarea', rows: 2, required: true,
            hint: 'Ce que l’on suspecte à l’entrée — à distinguer du diagnostic retenu.' },
          { name: 'traitementEntree', label: 'Traitement d’entrée', type: 'textarea', rows: 3, required: true },
          { name: 'examensParacliniques', label: 'Examens paracliniques', type: 'textarea', rows: 3 },
          { name: 'diagnosticRetenu', label: 'Diagnostic retenu', type: 'textarea', rows: 2, required: true,
            hint: 'Ce que les examens ont confirmé.' },
          { name: 'traitementReajuste', label: 'Traitement réajusté', type: 'textarea', rows: 4 },
          { name: 'evolution', label: 'Évolution et traitement des complications', type: 'textarea', rows: 4 },
          { name: 'traitementSortie', label: 'Traitement de sortie', type: 'textarea', rows: 3 },
          { name: 'diagnosticSortie', label: 'Diagnostic de sortie', type: 'textarea', rows: 2, required: true,
            hint: 'Tient compte de l’évolution et des complications.' },
          { name: 'medecinId', label: 'Médecin traitant', type: 'select', required: true,
            options: optionsSoignants(function (x) { return x.qualite === 'medecin'; }) },
        ];
      }

      function afficher() {
        var rows = col6().active();
        var clos = rows.filter(function (r) { return r.dateSortie; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Rapports médicaux', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
          { label: 'Séjours clos', value: C.num(clos.length), icon: 'log-out', tone: 'success' },
          { label: 'En cours', value: C.num(rows.length - clos.length), icon: 'clock',
            tone: rows.length - clos.length ? 'warning' : 'neutral' },
          { label: 'Rubriques du formulaire', value: '14', icon: 'list', tone: 'neutral',
            hint: 'reprises du document officiel' },
        ]));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'dateEntree').reverse(),
          empty: 'Aucun rapport médical enregistré.',
          actions: [K.creer(col6(), champs(), {
            module: 'M3', label: 'Nouveau rapport', titre: 'Rapport médical',
            entite: 'Rapport médical', size: 'xl', apres: afficher,
            transform: function (v) {
              var pt = patientParCode3(v.patientCode);
              return Object.assign({}, v, {
                reference: C.nextRef('RAP-', 4),
                patientId: pt ? pt.id : null,
                patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                age: pt ? C.age(pt.dateNaissance) : null,
                sexe: pt ? pt.sexe : null,
                adresse: pt ? pt.quartier : null,
                telephone: pt ? pt.telephone : null,
                medecin: nomSoignant(v.medecinId),
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
            { key: 'dateEntree', label: 'Entrée', render: function (r) { return C.dateFR(r.dateEntree); } },
            { key: 'dateSortie', label: 'Sortie',
              render: function (r) { return r.dateSortie ? C.dateFR(r.dateSortie) : U.badge('en cours', 'warning'); } },
            { key: 'diagnosticSortie', label: 'Diagnostic de sortie' },
            { key: 'medecin', label: 'Médecin traitant' },
          ],
          rowActions: function (r) {
            return [K.iconBtn('printer', 'Imprimer le rapport', function () { imprimerRapport(r); })]
              .concat(K.actionsLigne(col6(), champs(), {
                module: 'M3', refresh: afficher,
                titre: function (x) { return x.reference; },
                detail: function (x) {
                  function rub(t, v) {
                    return v ? K.section(t, el('p.whitespace-pre-line.text-sm.text-slate-600', { text: v })) : null;
                  }
                  return el('div.space-y-4', null,
                    K.grid([
                      ['Référence', x.reference], ['Patient', x.patient],
                      ['Âge', x.age != null ? x.age + ' ans' : '—'], ['Sexe', x.sexe || '—'],
                      ['Adresse', x.adresse || '—'], ['Téléphone', x.telephone || '—'],
                      ['Date d’entrée', C.dateFR(x.dateEntree)],
                      ['Date de sortie', x.dateSortie ? C.dateFR(x.dateSortie) : 'séjour en cours'],
                      ['Médecin traitant', x.medecin],
                    ]),
                    rub('Motif de consultation', x.motif),
                    rub('Anamnèse', x.anamnese),
                    rub('Examen physique', x.examenPhysique),
                    rub('Hypothèses diagnostiques', x.hypotheses),
                    rub('Traitement d’entrée', x.traitementEntree),
                    rub('Examens paracliniques', x.examensParacliniques),
                    rub('Diagnostic retenu', x.diagnosticRetenu),
                    rub('Traitement réajusté', x.traitementReajuste),
                    rub('Évolution et traitement des complications', x.evolution),
                    rub('Traitement de sortie', x.traitementSortie),
                    rub('Diagnostic de sortie', x.diagnosticSortie));
                },
              })(r));
          },
        }));
        U.icons(vue);
      }

      function imprimerRapport(r) {
        function rubrique(titre, texte) {
          if (!texte) return null;
          return el('div.mb-2', null, [
            el('p.text-\\[10px\\].font-semibold', { text: titre + ' :' }),
            el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', { text: texte }),
          ]);
        }
        /* Le rapport médical s'imprime sous l'UNIQUE en-tête légal (C.BRAND) —
           la variante « C » qu'il désignait est retirée (arbitrage 31/08/2026). */
        P.etat({
          titre: 'RAPPORT MÉDICAL',
          sousTitre: r.reference + ' — ' + r.patient,
          cartouche: [
            ['Nom et prénoms', r.patient],
            ['Âge', r.age != null ? r.age + ' ans' : '—'], ['Sexe', r.sexe || '—'],
            ['Adresse', r.adresse || '—'], ['Téléphone', r.telephone || '—'],
            ['Date d’entrée', C.dateFR(r.dateEntree)],
            ['Date de sortie', r.dateSortie ? C.dateFR(r.dateSortie) : '—'],
          ],
          contenu: el('div', null, [
            rubrique('Motif de consultation', r.motif),
            rubrique('Anamnèse', r.anamnese),
            rubrique('Examen physique', r.examenPhysique),
            rubrique('Hypothèses diagnostiques', r.hypotheses),
            rubrique('Traitement d’entrée', r.traitementEntree),
            rubrique('Examens paracliniques', r.examensParacliniques),
            rubrique('Diagnostic retenu', r.diagnosticRetenu),
            rubrique('Traitement réajusté', r.traitementReajuste),
            rubrique('Évolution et traitement des complications', r.evolution),
            rubrique('Traitement de sortie', r.traitementSortie),
            rubrique('Diagnostic de sortie', r.diagnosticSortie),
          ].filter(Boolean)),
          signatures: [{ role: 'Le Médecin traitant', nom: r.medecin, mention: 'Signature et cachet' }],
        });
      }
    },
  });

  /* ==========================================================================
   * PHASE 7 — ANESTHÉSIE ET DEMANDES DU SERVICE (cible Instructions)
   * --------------------------------------------------------------------------
   * Quatre écrans : la consultation pré-anesthésique (CPA), le compte rendu
   * d'anesthésie (per-opératoire et réveil), la fiche de demande d'examen du
   * service — le formulaire papier de reunions/ — et les bons de pansement,
   * qui réutilisent la chaîne prescription → caisse → exécution.
   *
   * Les référentiels cliniques (ASA, Mallampati, techniques) ne viennent
   * d'AUCUN document remis par la clinique : comme les check-listes du bloc,
   * ils sont proposés et marqués à valider — les écrans le disent.
   * ======================================================================== */
  var ASA = [
    { id: 'I', label: 'ASA I — patient sain' },
    { id: 'II', label: 'ASA II — maladie systémique légère' },
    { id: 'III', label: 'ASA III — maladie systémique sévère' },
    { id: 'IV', label: 'ASA IV — menace vitale constante' },
    { id: 'V', label: 'ASA V — moribond, survie improbable sans intervention' },
  ];
  var MALLAMPATI = [
    { id: 'I', label: 'Mallampati I — piliers, voile et luette visibles' },
    { id: 'II', label: 'Mallampati II — luette partiellement masquée' },
    { id: 'III', label: 'Mallampati III — seul le voile est visible' },
    { id: 'IV', label: 'Mallampati IV — voile non visible' },
  ];
  var TECHNIQUES_ANESTHESIE = ['Anesthésie générale', 'Rachianesthésie', 'Péridurale',
    'Anesthésie locale', 'Sédation'];
  var CONCLUSIONS_CPA = ['Apte à l’anesthésie', 'Apte avec réserves', 'Intervention à reporter'];
  var DECISIONS_REVEIL = ['Retour dans le service', 'Surveillance prolongée en salle de réveil',
    'Transfert / évacuation'];

  function colCpa() {
    return S.collection('cpa', { module: 'M3', entite: 'consultation pré-anesthésique', prefix: 'CPA' });
  }
  function colCrAnesthesie() {
    return S.collection('crAnesthesie', { module: 'M3', entite: 'compte rendu d’anesthésie', prefix: 'CRA' });
  }
  function colCro3() {
    return S.collection('crOperatoires', { module: 'M3', entite: 'compte rendu opératoire', prefix: 'CRO' });
  }

  /* Jeu de démonstration : quelques CPA adossées aux admissions réelles du
     magasin — les écrans doivent montrer leur usage, pas des tableaux vides. */
  function amorcerAnesthesie() {
    var cpa = colCpa();
    if (cpa.all().length) return;
    var rnd = C.seeded(701);
    var adm = admissions().slice(0, 6);
    adm.forEach(function (a, i) {
      var conclu = i === 4 ? CONCLUSIONS_CPA[1] : CONCLUSIONS_CPA[0];
      cpa.all().push({
        id: 'CPA' + C.pad(i + 1, 4), statut: 'actif',
        reference: 'CPA-2026-' + C.pad(i + 1, 4),
        date: a.dateEntree,
        patientId: a.patientId, patient: a.patient, patientCode: a.patientCode,
        asa: C.pick(rnd, ['I', 'I', 'II', 'II', 'III']),
        mallampati: C.pick(rnd, ['I', 'I', 'II', 'III']),
        technique: C.pick(rnd, TECHNIQUES_ANESTHESIE),
        antecedentsAnesthesiques: C.pick(rnd, ['Aucun', 'Aucun', 'Rachianesthésie en 2024, sans incident']),
        allergies: C.pick(rnd, ['Aucune connue', 'Aucune connue', 'Pénicilline']),
        jeuneConsigne: true,
        conclusion: conclu,
        observations: conclu === CONCLUSIONS_CPA[1] ? 'HTA à équilibrer avant l’intervention.' : '',
        anesthesiste: 'Anesthésiste de la clinique',
      });
    });
    S.save();
  }

  /* --------------------------------------------------------------------------
   * CONSULTATION PRÉ-ANESTHÉSIQUE
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m3-cpa', {
    title: 'Consultation pré-anesthésique',
    description: 'Évaluation avant anesthésie : classe ASA, score de Mallampati, technique proposée, conclusion d’aptitude.',
    regle: 'La CPA précède l’intervention : une intervention <strong>sans CPA est signalée, jamais '
      + 'bloquée</strong> — l’urgence vitale n’attend pas une fiche. Les échelles proposées (ASA, '
      + 'Mallampati) ne viennent d’<strong>aucun document remis</strong> : comme les check-listes du '
      + 'bloc, elles ont été <strong>arrêtées par les praticiens du bloc le 01/09/2026</strong> '
      + '(validation écrite).',
    render: function (root) {
      amorcerAnesthesie();
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function champs() {
        return [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients3() },
          { name: 'date', label: 'Date de la consultation', type: 'date', required: true },
          { name: 'asa', label: 'Classe ASA', type: 'select', required: true,
            options: ASA.map(function (x) { return { value: x.id, label: x.label }; }) },
          { name: 'mallampati', label: 'Score de Mallampati', type: 'select', required: true,
            options: MALLAMPATI.map(function (x) { return { value: x.id, label: x.label }; }) },
          { name: 'technique', label: 'Technique d’anesthésie proposée', type: 'select', required: true,
            options: TECHNIQUES_ANESTHESIE.map(function (x) { return { value: x, label: x }; }) },
          { name: 'antecedentsAnesthesiques', label: 'Antécédents anesthésiques', type: 'textarea', rows: 2, required: true,
            hint: '« Aucun » se dit — un champ vide ne distingue pas l’absence d’antécédent de l’oubli.' },
          { name: 'allergies', label: 'Allergies', type: 'text', required: true },
          { name: 'jeuneConsigne', label: 'Consigne de jeûne pré-opératoire donnée', type: 'checkbox' },
          { name: 'conclusion', label: 'Conclusion', type: 'select', required: true,
            options: CONCLUSIONS_CPA.map(function (x) { return { value: x, label: x }; }) },
          { name: 'observations', label: 'Observations et réserves', type: 'textarea', rows: 2,
            hint: 'Obligatoires dès que la conclusion n’est pas « Apte à l’anesthésie ».' },
          { name: 'anesthesiste', label: 'Anesthésiste', type: 'text', required: true },
        ];
      }

      function controler(v) {
        /* La réserve s'écrit : une aptitude conditionnelle sans condition
           nommée ne protège personne. */
        if (v.conclusion !== CONCLUSIONS_CPA[0] && !String(v.observations || '').trim()) {
          U.toast('Conclusion avec réserves : les nommer.', {
            type: 'error',
            detail: 'Une CPA « ' + v.conclusion + ' » doit dire quelles réserves — c’est elles que le bloc doit lire.',
          });
          return false;
        }
        return true;
      }

      function afficher() {
        var rows = colCpa().active();
        var cros = colCro3().active();
        var avecCpa = {};
        rows.forEach(function (r) { avecCpa[r.patientId] = true; });
        var sansCpa = cros.filter(function (c) { return c.patientId && !avecCpa[c.patientId]; });
        var reserves = rows.filter(function (r) { return r.conclusion !== CONCLUSIONS_CPA[0]; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'CPA enregistrées', value: C.num(rows.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'Aptes sans réserve', value: C.num(rows.length - reserves.length), icon: 'check-circle-2', tone: 'success' },
          { label: 'Avec réserves ou report', value: C.num(reserves.length), icon: 'triangle-alert',
            tone: reserves.length ? 'warning' : 'neutral' },
          {
            label: 'Interventions sans CPA', value: C.num(sansCpa.length), icon: 'shield-alert',
            tone: sansCpa.length ? 'danger' : 'neutral',
            hint: 'Signalées, jamais bloquées — l’urgence n’attend pas',
          },
        ]));

        vue.appendChild(K.note('Les échelles ASA et Mallampati et la liste des techniques sont des '
          + '<strong>arrêtées par les praticiens du bloc le 01/09/2026</strong> — proposées à l’origine, '
          + 'aucun document de la clinique ne les fixait ; la provenance reste dite. '
          + 'Les fiches déjà saisies conservent leurs valeurs telles quelles.',
        { tone: 'info', icon: 'check-circle-2' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'date').reverse(),
          empty: 'Aucune consultation pré-anesthésique enregistrée.',
          actions: [K.creer(colCpa(), champs(), {
            module: 'M3', label: 'Nouvelle CPA', titre: 'Consultation pré-anesthésique',
            entite: 'CPA', size: 'lg', apres: afficher, avant: controler,
            transform: function (v) {
              var pt = patientParCode3(v.patientCode);
              return Object.assign({}, v, {
                reference: C.nextRef('CPA-2026-', 4),
                patientId: pt ? pt.id : null,
                patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'date', label: 'Date', render: function (r) { return C.dateFR(r.date); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + (r.patientCode || '—'); } },
            { key: 'asa', label: 'ASA', render: function (r) { return U.badge('ASA ' + r.asa, ['III', 'IV', 'V'].indexOf(r.asa) !== -1 ? 'warning' : 'info'); } },
            { key: 'mallampati', label: 'Mallampati' },
            { key: 'technique', label: 'Technique proposée' },
            {
              key: 'conclusion', label: 'Conclusion',
              render: function (r) {
                return U.badge(r.conclusion,
                  r.conclusion === CONCLUSIONS_CPA[0] ? 'success'
                    : (r.conclusion === CONCLUSIONS_CPA[2] ? 'danger' : 'warning'));
              },
            },
          ],
          rowActions: function (r) {
            return [K.iconBtn('printer', 'Imprimer la fiche', function () { imprimerCpa(r); })]
              .concat(K.actionsLigne(colCpa(), champs(), {
                module: 'M3', detail: detailCpa, refresh: afficher, avant: controler,
                titre: function (x) { return x.reference; },
              })(r));
          },
        }));
        U.icons(vue);
      }

      function detailCpa(r) {
        return el('div.space-y-4', null,
          K.grid([
            ['Référence', r.reference], ['Date', C.dateFR(r.date)],
            ['Patient', r.patient], ['Dossier', r.patientCode || '—'],
            ['Classe ASA', 'ASA ' + r.asa], ['Mallampati', r.mallampati],
            ['Technique proposée', r.technique],
            ['Jeûne consigné', r.jeuneConsigne ? 'Oui' : 'Non'],
            ['Anesthésiste', r.anesthesiste],
          ]),
          K.section('Antécédents anesthésiques', el('p.text-sm.text-slate-600', { text: r.antecedentsAnesthesiques || '—' })),
          K.section('Allergies', el('p.text-sm.text-slate-600', { text: r.allergies || '—' })),
          K.section('Conclusion', el('div', null, [
            U.badge(r.conclusion, r.conclusion === CONCLUSIONS_CPA[0] ? 'success' : 'warning'),
            r.observations ? el('p.mt-2.text-sm.text-slate-600', { text: r.observations }) : null,
          ])));
      }

      function imprimerCpa(r) {
        P.etat({
          titre: 'CONSULTATION PRÉ-ANESTHÉSIQUE',
          sousTitre: r.reference + ' — ' + r.patient,
          cartouche: [
            ['Patient', r.patient], ['Dossier', r.patientCode || '—'],
            ['Date', C.dateFR(r.date)],
            ['Classe ASA', 'ASA ' + r.asa], ['Mallampati', r.mallampati],
            ['Technique proposée', r.technique],
          ],
          contenu: el('div.space-y-2.text-\\[10px\\]', null, [
            el('p', { text: 'Antécédents anesthésiques : ' + (r.antecedentsAnesthesiques || '—') }),
            el('p', { text: 'Allergies : ' + (r.allergies || '—') }),
            el('p', { text: 'Consigne de jeûne pré-opératoire : ' + (r.jeuneConsigne ? 'donnée' : 'NON donnée') }),
            el('p.font-semibold', { text: 'Conclusion : ' + r.conclusion }),
            r.observations ? el('p', { text: 'Réserves : ' + r.observations }) : null,
          ].filter(Boolean)),
          signatures: [{ role: 'L’anesthésiste', nom: r.anesthesiste }],
        });
      }
    },
  });

  /* --------------------------------------------------------------------------
   * COMPTE RENDU D'ANESTHÉSIE — per-opératoire et réveil
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m3-cr-anesthesie', {
    title: 'Comptes rendus d’anesthésie',
    description: 'Le déroulé anesthésique de l’intervention : technique, agents, incidents, réveil et décision de sortie.',
    regle: 'Le compte rendu d’anesthésie complète le compte rendu opératoire : deux pièces, deux '
      + 'responsabilités. Il couvre l’induction, l’entretien et le <strong>réveil</strong> — la '
      + 'surveillance d’étage, elle, reste sur la <strong>fiche de surveillance</strong> (m3-surveillance). '
      + 'Un incident per-opératoire <strong>se nomme</strong> ; « aucun incident » s’écrit aussi.',
    render: function (root) {
      amorcerAnesthesie();
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function champs() {
        return [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients3() },
          { name: 'dateOperation', label: 'Date de l’intervention', type: 'date', required: true },
          {
            name: 'croReference', label: 'Compte rendu opératoire lié', type: 'select',
            options: [{ value: '', label: '— aucun (acte sans CRO) —' }].concat(
              colCro3().active().map(function (c) {
                return { value: c.reference, label: c.reference + ' — ' + c.patient };
              })),
          },
          { name: 'technique', label: 'Technique employée', type: 'select', required: true,
            options: TECHNIQUES_ANESTHESIE.map(function (x) { return { value: x, label: x }; }) },
          { name: 'agents', label: 'Agents et produits employés', type: 'textarea', rows: 2, required: true },
          { name: 'heureInduction', label: 'Heure d’induction', type: 'time', required: true },
          { name: 'heureFin', label: 'Heure de fin d’anesthésie', type: 'time', required: true },
          { name: 'incidents', label: 'Incidents per-opératoires', type: 'textarea', rows: 2, required: true,
            hint: '« Aucun incident » s’écrit : un champ vide ne distingue pas l’absence d’incident de l’oubli.' },
          { name: 'surveillancePerop', label: 'Surveillance per-opératoire (constantes, remplissage)', type: 'textarea', rows: 3 },
          { name: 'heureArriveeReveil', label: 'Arrivée en salle de réveil', type: 'time', required: true },
          { name: 'etatReveil', label: 'État au réveil', type: 'textarea', rows: 2, required: true },
          { name: 'decisionSortie', label: 'Décision de sortie de salle de réveil', type: 'select', required: true,
            options: DECISIONS_REVEIL.map(function (x) { return { value: x, label: x }; }) },
          { name: 'anesthesiste', label: 'Anesthésiste', type: 'text', required: true },
        ];
      }

      function afficher() {
        var rows = colCrAnesthesie().active();
        var incidents = rows.filter(function (r) {
          return r.incidents && !/^aucun/i.test(String(r.incidents).trim());
        });
        var prolonges = rows.filter(function (r) { return r.decisionSortie === DECISIONS_REVEIL[1]; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Comptes rendus', value: C.num(rows.length), icon: 'syringe', tone: 'navy' },
          { label: 'Avec incident nommé', value: C.num(incidents.length), icon: 'triangle-alert',
            tone: incidents.length ? 'warning' : 'neutral' },
          { label: 'Surveillances prolongées', value: C.num(prolonges.length), icon: 'clock', tone: 'info' },
          { label: 'CRO liés', value: C.num(rows.filter(function (r) { return r.croReference; }).length),
            icon: 'scissors', tone: 'neutral' },
        ]));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'dateOperation').reverse(),
          empty: 'Aucun compte rendu d’anesthésie enregistré.',
          actions: [K.creer(colCrAnesthesie(), champs(), {
            module: 'M3', label: 'Nouveau compte rendu', titre: 'Compte rendu d’anesthésie',
            entite: 'Compte rendu d’anesthésie', size: 'lg', apres: afficher,
            transform: function (v) {
              var pt = patientParCode3(v.patientCode);
              return Object.assign({}, v, {
                reference: C.nextRef('CRA-2026-', 4),
                patientId: pt ? pt.id : null,
                patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'dateOperation', label: 'Date', render: function (r) { return C.dateFR(r.dateOperation); } },
            { key: 'patient', label: 'Patient' },
            { key: 'technique', label: 'Technique' },
            {
              key: 'incidents', label: 'Incidents',
              render: function (r) {
                return /^aucun/i.test(String(r.incidents || '').trim())
                  ? el('span.text-xs.text-slate-400', { text: 'Aucun' })
                  : U.badge('Incident nommé', 'warning');
              },
            },
            { key: 'decisionSortie', label: 'Sortie de réveil' },
            { key: 'anesthesiste', label: 'Anesthésiste' },
          ],
          rowActions: function (r) {
            return [K.iconBtn('printer', 'Imprimer le compte rendu', function () { imprimerCra(r); })]
              .concat(K.actionsLigne(colCrAnesthesie(), champs(), {
                module: 'M3', detail: detailCra, refresh: afficher,
                titre: function (x) { return x.reference; },
              })(r));
          },
        }));
        U.icons(vue);
      }

      function detailCra(r) {
        return el('div.space-y-4', null,
          K.grid([
            ['Référence', r.reference], ['Date', C.dateFR(r.dateOperation)],
            ['Patient', r.patient], ['CRO lié', r.croReference || '—'],
            ['Technique', r.technique],
            ['Induction', r.heureInduction || '—'], ['Fin', r.heureFin || '—'],
            ['Arrivée en réveil', r.heureArriveeReveil || '—'],
            ['Décision de sortie', r.decisionSortie],
            ['Anesthésiste', r.anesthesiste],
          ]),
          K.section('Agents et produits', el('p.text-sm.text-slate-600', { text: r.agents || '—' })),
          K.section('Incidents per-opératoires', el('p.text-sm.text-slate-600', { text: r.incidents || '—' })),
          r.surveillancePerop
            ? K.section('Surveillance per-opératoire', el('p.whitespace-pre-line.text-sm.text-slate-600', { text: r.surveillancePerop }))
            : null,
          K.section('État au réveil', el('p.text-sm.text-slate-600', { text: r.etatReveil || '—' })));
      }

      function imprimerCra(r) {
        P.etat({
          titre: 'COMPTE RENDU D’ANESTHÉSIE',
          sousTitre: r.reference + ' — ' + r.patient,
          cartouche: [
            ['Patient', r.patient], ['Dossier', r.patientCode || '—'],
            ['Date de l’intervention', C.dateFR(r.dateOperation)],
            ['CRO lié', r.croReference || '—'],
            ['Technique', r.technique],
            ['Induction — fin', (r.heureInduction || '—') + ' — ' + (r.heureFin || '—')],
          ],
          contenu: el('div.space-y-2.text-\\[10px\\]', null, [
            el('p', { text: 'Agents et produits : ' + (r.agents || '—') }),
            el('p', { text: 'Incidents per-opératoires : ' + (r.incidents || '—') }),
            r.surveillancePerop ? el('p.whitespace-pre-line', { text: 'Surveillance per-opératoire : ' + r.surveillancePerop }) : null,
            el('p', { text: 'Arrivée en salle de réveil : ' + (r.heureArriveeReveil || '—') }),
            el('p', { text: 'État au réveil : ' + (r.etatReveil || '—') }),
            el('p.font-semibold', { text: 'Décision de sortie : ' + r.decisionSortie }),
          ].filter(Boolean)),
          signatures: [
            { role: 'L’anesthésiste', nom: r.anesthesiste },
            { role: 'L’opérateur', mention: 'Pour information' },
          ],
        });
      }
    },
  });

  /* --------------------------------------------------------------------------
   * FICHE DE DEMANDE D'EXAMEN — le formulaire papier du service
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m3-demande-examen', {
    title: 'Demande d’examen',
    description: 'La fiche de demande d’examen du service : identité complète, indication, urgence par examen ou bilan entier.',
    regle: 'La fiche papier exige <strong>tous ses champs</strong> — nom, prénoms, âge, sexe, indication, '
      + 'résidence : un bulletin d’examen anonyme ne se rattache plus à personne. L’urgence se dit '
      + '<strong>par examen ou pour le bilan entier</strong>, et le service demandeur est nommé — c’est '
      + 'lui qui reverra le résultat, sous le RBAC métier. La demande suit la chaîne existante : '
      + 'caisse, prélèvement, laboratoire.',
    render: function (root) {
      var L = global.SIGH.labo;
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function demandesService() {
        return S.collection('demandesAnalyses').active()
          .filter(function (r) { return r.origine === 'service'; });
      }

      function afficher() {
        var rows = demandesService();
        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Fiches du service', value: C.num(rows.length), icon: 'clipboard-list', tone: 'navy' },
          { label: 'En attente de règlement', value: C.num(rows.filter(function (r) { return r.etatAnalyse === 'en_attente'; }).length),
            icon: 'wallet', tone: 'warning' },
          { label: 'Urgentes', value: C.num(rows.filter(function (r) { return r.urgent; }).length),
            icon: 'siren', tone: 'danger' },
          { label: 'Résultats rendus', value: C.num(rows.filter(function (r) { return D.resultatRendu(r.etatAnalyse); }).length),
            icon: 'file-check-2', tone: 'success' },
        ]));

        vue.appendChild(U.dataTable({
          title: 'Registre des fiches de demande', rows: rows,
          exportName: 'demandes-examen-service', pageSize: 12, searchable: true,
          defaultSort: 'dateHeure', defaultDir: 'desc',
          emptyMessage: 'Aucune fiche de demande émise par les services.',
          actions: [K.commande('Nouvelle fiche de demande', {
            variant: 'primary', size: 'sm', icon: 'plus',
            onclick: nouvelleFiche,
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'N°', render: function (r) {
              return el('div', null, [
                el('span.font-mono.text-xs', { text: r.reference }),
                r.codeAnalyse ? el('p.font-mono.text-[10px].text-navy-700', { text: r.codeAnalyse }) : null,
              ]);
            } },
            { key: 'dateHeure', label: 'Date', render: function (r) { return C.dateFR(r.dateHeure); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + (r.patientCode || '—'); } },
            { key: 'analyse', label: 'Examen' },
            { key: 'serviceDemandeur', label: 'Service', render: function (r) {
              var s = (L.SERVICES_DEMANDEURS || []).filter(function (x) { return x.id === r.serviceDemandeur; })[0];
              return s ? s.label : (r.serviceDemandeur || '—');
            } },
            { key: 'urgent', label: 'Urgence', render: function (r) {
              return r.urgent ? U.badge('Urgent', 'danger') : el('span.text-xs.text-slate-400', { text: 'Courant' });
            } },
            { key: 'etatAnalyse', label: 'État', render: function (r) { return U.statut(r.etatAnalyse); } },
          ],
        }));
        U.icons(vue);
      }

      function nouvelleFiche() {
        var f = U.form([
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, col: 'full', options: optionsPatients3() },
          { name: 'residence', label: 'Résidence', type: 'text', required: true,
            hint: 'Reprise du dossier au choix du patient — la fiche papier l’exige.' },
          { name: 'serviceDemandeur', label: 'Service demandeur', type: 'select', required: true,
            options: (L.SERVICES_DEMANDEURS || []).map(function (x) { return { value: x.id, label: x.label }; }) },
        ].concat(K.champsPrescripteur(
          optionsSoignants(function (x) { return x.prescrit; }).map(function (o) {
            return { value: o.label.split(' — ')[0], label: o.label };
          }), { name: 'prescripteur' }
        ), [
          { name: 'indication', label: 'Indication clinique', type: 'textarea', rows: 2, required: true, col: 'full' },
          {
            name: 'analyses', label: 'Examens demandés', type: 'multiselect', required: true, col: 'full',
            options: (D.ANALYSES || []).map(function (a) {
              return { value: a.code, label: a.code + ' — ' + a.designation,
                detail: a.prix ? C.money(a.prix) : 'tarif non renseigné' };
            }),
          },
          { name: 'urgence', label: 'Urgence', type: 'select', required: true,
            options: (L.NIVEAUX_URGENCE || []).map(function (x) { return { value: x.id, label: x.label }; }) },
          { name: 'examenUrgent', label: 'Examen urgent (si « un examen urgent »)', type: 'select',
            options: [{ value: '', label: '—' }].concat((D.ANALYSES || []).map(function (a) {
              return { value: a.code, label: a.designation };
            })) },
          { name: 'hospitalise', label: 'Patient hospitalisé', type: 'checkbox' },
        ]), { urgence: 'aucune' });

        var m = U.modal({
          title: 'Fiche de demande d’examen',
          subtitle: 'Tous les champs de la fiche papier sont obligatoires.',
          size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Émettre la fiche', {
              variant: 'primary', icon: 'send',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (v.urgence === 'examen' && !v.examenUrgent) {
                  U.toast('Nommer L’EXAMEN urgent.', { type: 'error',
                    detail: '« Un examen urgent » sans le nommer laisserait le laboratoire deviner.' });
                  return;
                }
                var pt = patientParCode3(v.patientCode);
                if (!pt) { U.toast('Patient introuvable.', { type: 'error' }); return; }
                var res;
                try {
                  res = PR.ouvrirDemandeExterne({
                    patientId: pt.id,
                    analyses: v.analyses,
                    urgence: v.urgence, examenUrgent: v.examenUrgent || null,
                    prescripteur: v.prescripteur,
                    serviceDemandeur: v.serviceDemandeur,
                    indication: v.indication,
                    hospitalise: !!v.hospitalise,
                    residence: v.residence,
                    /* La fiche du SERVICE : le résultat revient au
                       prescripteur, sous le RBAC métier du secteur. */
                    origineFiche: 'service', origineDemande: 'service',
                    secteurDemandeur: v.serviceDemandeur === 'maternite' ? 'MATERNITÉ' : null,
                  });
                } catch (err) {
                  U.toast(err.message, { type: 'error' });
                  return;
                }
                m.close();
                afficher();
                U.toast('Fiche émise — ' + res.demandes.length + ' examen(s).', {
                  type: 'success', duration: 8000,
                  detail: 'Facture ' + res.facture.numero + ' à la caisse ; le prélèvement suivra le règlement.',
                });
                imprimerFiche(pt, v, res);
              },
            }),
          ],
        });
        /* La résidence se reprend du dossier au choix du patient — sans
           écraser une saisie déjà faite. */
        var selP = f.querySelector('#f_patientCode');
        if (selP) {
          selP.addEventListener('change', function () {
            var pt = patientParCode3(selP.value);
            var champ = f.querySelector('#f_residence');
            if (pt && champ && !champ.value) champ.value = pt.adresse || pt.quartier || '';
          });
        }
      }

      function imprimerFiche(pt, v, res) {
        var s = (L.SERVICES_DEMANDEURS || []).filter(function (x) { return x.id === v.serviceDemandeur; })[0];
        var u = (L.NIVEAUX_URGENCE || []).filter(function (x) { return x.id === v.urgence; })[0];
        P.etat({
          titre: 'FICHE DE DEMANDE D’EXAMEN',
          sousTitre: (res.demandes[0] && res.demandes[0].codeAnalyse) || res.facture.numero,
          cartouche: [
            ['Nom', pt.nom], ['Prénoms', pt.prenom],
            ['Âge', pt.dateNaissance ? C.age(pt.dateNaissance) + ' ans' : '—'],
            ['Sexe', pt.sexe === 'F' ? 'Féminin' : 'Masculin'],
            ['Résidence', v.residence],
            ['Service demandeur', s ? s.label : v.serviceDemandeur],
            ['Prescripteur', v.prescripteur],
            ['Hospitalisé', v.hospitalise ? 'Oui' : 'Non'],
          ],
          contenu: el('div.space-y-2', null, [
            el('p.text-\\[10px\\]', { text: 'Indication clinique : ' + v.indication }),
            el('p.text-\\[10px\\].font-semibold', { text: 'Urgence : ' + (u ? u.label : '—')
              + (v.urgence === 'examen' && v.examenUrgent ? ' — ' + v.examenUrgent : '') }),
            P.tableau([
              { label: 'Code', key: 'analyseCode' },
              { label: 'Examen demandé', key: 'analyse' },
              { label: 'Échantillon', key: 'echantillon' },
              { label: 'Tarif', align: 'right',
                value: function (x) { return C.money(x.prix, false); },
                somme: function (x) { return x.prix || 0; } },
            ], res.demandes, { total: true }),
          ]),
          signatures: [{ role: 'Le prescripteur', nom: v.prescripteur }],
        });
      }
    },
  });

  /* --------------------------------------------------------------------------
   * BONS DE PANSEMENT — la chaîne prescription → caisse → exécution
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m3-bons-pansements', {
    title: 'Bons de pansement',
    description: 'Prescription des pansements, réglés à la caisse séance par séance et exécutés en salle de soins.',
    regle: 'Le bon <strong>réutilise la chaîne existante</strong> : la prescription porte '
      + '<strong>une ligne payable par séance</strong> — la caisse encaisse des séances NOMMÉES, et un '
      + 'règlement partiel libère exactement celles qu’il couvre. L’exécution passe par la file de la '
      + 'salle de soins, débloquée par l’encaissement.',
    render: function (root) {
      var CODES_PANSEMENT = ['SO09', 'CH04'];
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function actesPansement() {
        return S.collection('actes').active().filter(function (a) {
          return CODES_PANSEMENT.indexOf(a.code) !== -1;
        });
      }

      function bons() {
        return S.collection('ordonnances').active().filter(function (o) {
          return (o.actes || []).length
            && o.actes.every(function (a) { return CODES_PANSEMENT.indexOf(a.code) !== -1; })
            && !(o.medicaments || []).length && !(o.analyses || []).length;
        });
      }

      function seancesDe(o) {
        var fac = S.collection('factures').active().filter(function (fc) { return fc.id === o.factureId; })[0];
        var lignes = fac ? (fac.lignes || []).filter(function (l) {
          return CODES_PANSEMENT.indexOf(l.acteCode) !== -1;
        }) : [];
        return {
          facture: fac,
          total: lignes.length,
          reglees: lignes.filter(function (l) { return l.statutPaiement === 'paye'; }).length,
        };
      }

      function afficher() {
        var rows = bons();
        var attente = rows.filter(function (o) { var s = seancesDe(o); return s.total && s.reglees < s.total; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Bons émis', value: C.num(rows.length), icon: 'bandage', tone: 'navy' },
          { label: 'Séances en attente de règlement', value: C.num(attente.length), icon: 'wallet',
            tone: attente.length ? 'warning' : 'neutral' },
          { label: 'Types au catalogue', value: C.num(actesPansement().length), icon: 'list',
            tone: 'neutral', hint: 'Pansement (SO09) et pansement chirurgical (CH04)' },
          { label: 'Tarif du pansement', value: (function () {
            var a = actesPansement().filter(function (x) { return x.code === 'SO09'; })[0];
            return a && a.prix != null ? C.money(a.prix) : '—';
          })(), icon: 'receipt', tone: 'info',
          hint: 'Grille (colonnes inversées, 26/08) : 9 000 non assuré · 6 000 assuré' },
        ]));

        vue.appendChild(U.dataTable({
          title: 'Registre des bons', rows: rows,
          exportName: 'bons-pansements', pageSize: 12,
          defaultSort: 'date', defaultDir: 'desc',
          emptyMessage: 'Aucun bon de pansement émis.',
          actions: [K.commande('Nouveau bon de pansement', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: nouveauBon,
          })].filter(Boolean),
          columns: [
            { key: 'numero', label: 'N°', render: function (o) { return el('span.font-mono.text-xs', { text: o.numero }); } },
            { key: 'date', label: 'Date', render: function (o) { return C.dateFR(o.date); } },
            { key: 'patient', label: 'Patient', render: function (o) { return o.patient + ' — ' + (o.patientCode || '—'); } },
            { key: 'medecin', label: 'Prescripteur' },
            {
              key: 'seances', label: 'Séances réglées', align: 'right',
              value: function (o) { var s = seancesDe(o); return s.reglees + '/' + s.total; },
              render: function (o) {
                var s = seancesDe(o);
                return U.badge(s.reglees + ' / ' + s.total,
                  s.reglees === s.total ? 'success' : (s.reglees ? 'warning' : 'danger'));
              },
            },
            { key: 'montant', label: 'Montant', align: 'right', render: function (o) { return C.money(o.montant, false); } },
          ],
          rowActions: function (o) {
            return [K.iconBtn('printer', 'Imprimer le bon', function () { imprimerBon(o); })];
          },
          onRowClick: function (o) {
            var s = seancesDe(o);
            U.drawer({
              title: 'Bon ' + o.numero, subtitle: o.patient,
              body: el('div.space-y-4', null,
                K.grid([
                  ['Patient', o.patient], ['Prescripteur', o.medecin],
                  ['Date', C.dateFR(o.date)],
                  ['Séances', s.reglees + ' réglée(s) sur ' + s.total],
                  ['Facture', s.facture ? s.facture.numero : '—'],
                  ['Montant', C.money(o.montant)],
                ]),
                K.note(s.reglees < s.total
                  ? 'La salle de soins n’exécute que les séances RÉGLÉES : '
                    + (s.total - s.reglees) + ' séance(s) attendent la caisse.'
                  : 'Toutes les séances sont réglées : la file de la salle de soins les porte.',
                { tone: s.reglees < s.total ? 'warning' : 'info', icon: 'wallet' })),
            });
          },
        }));
        U.icons(vue);
      }

      function nouveauBon() {
        var f = U.form([
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, col: 'full', options: optionsPatients3() },
          { name: 'medecin', label: 'Prescripteur', type: 'select', required: true,
            options: optionsSoignants(function (x) { return x.prescrit; }).map(function (o) {
              return { value: o.label.split(' — ')[0], label: o.label };
            }) },
          {
            name: 'acteCode', label: 'Type de pansement', type: 'select', required: true,
            options: actesPansement().map(function (a) {
              return { value: a.code, label: a.libelle,
                detail: a.prix != null ? C.money(a.prix) + ' la séance' : 'tarif à valider' };
            }),
          },
          { name: 'seances', label: 'Nombre de séances', type: 'number', min: 1, max: 12, value: 1, required: true,
            hint: 'Une ligne payable PAR SÉANCE : la caisse peut encaisser séance par séance.' },
          { name: 'indication', label: 'Indication', type: 'textarea', rows: 2, required: true, col: 'full' },
        ], { seances: 1 });

        var m = U.modal({
          title: 'Nouveau bon de pansement', size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Émettre le bon', {
              variant: 'primary', icon: 'plus',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var n = Math.max(1, Math.min(12, Number(v.seances) || 1));
                var codes = [];
                for (var i = 0; i < n; i++) codes.push(v.acteCode);
                var res;
                try {
                  res = PR.prescrire({
                    patientCode: v.patientCode, medecin: v.medecin,
                    diagnostic: v.indication, actes: codes,
                  });
                } catch (err) { U.toast(err.message, { type: 'error' }); return; }
                m.close();
                afficher();
                U.toast('Bon ' + res.ordonnance.numero + ' émis — ' + n + ' séance(s).', {
                  type: 'success', duration: 8000,
                  detail: 'Facture ' + res.facture.numero + ' à la caisse ; la salle de soins est '
                    + 'informée, exécutable après encaissement.',
                });
                imprimerBon(res.ordonnance);
              },
            }),
          ],
        });
      }

      function imprimerBon(o) {
        var s = seancesDe(o);
        P.etat({
          titre: 'BON DE PANSEMENT',
          sousTitre: o.numero + ' — ' + o.patient,
          cartouche: [
            ['Patient', o.patient], ['Dossier', o.patientCode || '—'],
            ['Date', C.dateFR(o.date)],
            ['Prescripteur', o.medecin],
            ['Facture', s.facture ? s.facture.numero : '—'],
          ],
          contenu: el('div.space-y-2', null, [
            o.diagnostic ? el('p.text-\\[10px\\]', { text: 'Indication : ' + o.diagnostic }) : null,
            P.tableau([
              { label: 'Séance', key: 'rang' },
              { label: 'Acte', key: 'libelle' },
              { label: 'Tarif', align: 'right',
                value: function (x) { return C.money(x.prix, false); },
                somme: function (x) { return x.prix || 0; } },
            ], (o.actes || []).map(function (a, i) {
              return Object.assign({ rang: 'Séance ' + (i + 1) }, a);
            }), { total: true }),
            el('p.mt-2.text-\\[9px\\].italic', {
              text: 'Chaque séance se règle à la caisse ; la salle de soins n’exécute que les séances réglées, '
                + 'sur présentation du présent bon.',
            }),
          ].filter(Boolean)),
          signatures: [
            { role: 'Le prescripteur', nom: o.medecin },
            { role: 'L’exécutant', mention: 'Salle de soins' },
          ],
        });
      }
    },
  });

})(window);