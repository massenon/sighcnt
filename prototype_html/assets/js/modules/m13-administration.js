/* =============================================================================
 * M13 — Administration & Ambulance
 * -----------------------------------------------------------------------------
 * CDCT §10.6 et §10.12 — courriers (départ et arrivée), réunions, événements
 * et notifications, plan annuel de travail, notes de service et registre des
 * interventions d'ambulance.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit,
      N = global.SIGH.nav;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  /* États d'une intervention d'ambulance — lus aussi par le tableau de bord
     de l'ambulancier (« demandées ou en cours »). */
  var ETATS_INTERVENTION = {
    demandee: ['Demandée', 'warning'],
    en_cours: ['En cours', 'info'],
    terminee: ['Terminée', 'success'],
  };

  /* E540 : « AUJ » porte l'HEURE de l'horloge. Comparer une date (minuit) à AUJ rangeait parmi le PASSÉ tout ce qui a lieu aujourd'hui, et
     Math.round((minuit demain − maintenant) / 1 jour) lisait « Aujourd'hui » pour demain dès midi. Les événements se comparent par JOUR ; une réunion,
     qui a une heure, par son DÉBUT. */
  function evenementAVenir(e) { return String(e.date).slice(0, 10) >= C.iso(AUJ); }
  function reunionAVenir(r) { return C.toDate(String(r.date).slice(0, 10) + 'T' + (r.heure || '00:00')) >= AUJ; }

  function personnel() { return S.collection('personnel').active(); }
  function optionsAgents() {
    return C.sortBy(personnel(), 'nomComplet').map(function (e) { return { value: e.nomComplet, label: e.nomComplet + ' — ' + e.poste }; });
  }

  /* ==========================================================================
   * COURRIERS
   * ======================================================================== */
  global.SIGH.screen('m13-courriers', {
    title: 'Courriers (départ / arrivée)',
    description: 'Registre numérisé du courrier administratif, avec suivi des réponses et des accusés de réception.',
    render: function (root) {
      /* Le registre est peuplé AU SOCLE (data-seed.js), à la forme que cet
         écran lit — traitement tri-état, nature, service, numérisation. Deux
         seeds ont coexisté ici avec des formes divergentes : celui du socle
         gagnait toujours, et sa forme muette laissait la colonne Traitement
         afficher des tirets. Un seul seed, une seule forme. */
      return K.crud({
        collection: 'courriers', entite: 'courrier', entiteP: 'courriers', module: 'M13',
        defaultSort: 'date', defaultDir: 'desc', pageSize: 15,
        columns: [
          { key: 'reference', label: 'N° d’ordre', nowrap: true, render: function (c) { return el('span.font-mono.text-xs.font-semibold', { text: c.reference }); } },
          {
            key: 'sens', label: 'Sens',
            text: function (c) { return c.sens === 'arrivee' ? 'Arrivée' : 'Départ'; },
            render: function (c) {
              return c.sens === 'arrivee'
                ? U.badge('Arrivée', 'info')
                : U.badge('Départ', 'success');
            },
          },
          { key: 'date', label: 'Date', nowrap: true, text: function (c) { return C.dateFR(c.date); }, render: function (c) { return C.dateFR(c.date); } },
          { key: 'correspondant', label: 'Correspondant' },
          { key: 'objet', label: 'Objet' },
          { key: 'nature', label: 'Nature', render: function (c) { return U.badge(c.nature, 'neutral'); } },
          { key: 'affecteA', label: 'Affecté à' },
          {
            key: 'traitement', label: 'Traitement',
            render: function (c) {
              var m = { traite: ['Traité', 'success'], en_cours: ['En cours', 'info'], en_attente: ['En attente', 'warning'] };
              var x = m[c.traitement] || ['—', 'neutral'];
              return U.badge(x[0], x[1]);
            },
          },
          {
            key: 'numerise', label: 'Numérisé',
            text: function (c) { return c.numerise ? 'Oui' : 'Non'; },
            render: function (c) { return c.numerise ? U.badge('Oui', 'success') : U.badge('À scanner', 'warning'); },
          },
        ],
        fields: [
          { name: 'sens', label: 'Sens', type: 'select', required: true, options: [{ value: 'arrivee', label: 'Courrier arrivée' }, { value: 'depart', label: 'Courrier départ' }] },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'correspondant', label: 'Correspondant', required: true, col: 'full' },
          { name: 'objet', label: 'Objet', required: true, col: 'full' },
          { name: 'nature', label: 'Nature', type: 'select', required: true, options: ['Lettre', 'Courriel', 'Note', 'Facture', 'Convocation', 'Rapport'] },
          { name: 'affecteA', label: 'Service destinataire', type: 'select', required: true, options: ['Direction Médicale', 'Direction Administrative', 'Comptabilité', 'Ressources humaines', 'Gestion des stocks', 'Laboratoire', 'Pharmacie'] },
          { name: 'traitement', label: 'État du traitement', type: 'select', required: true, options: [{ value: 'en_attente', label: 'En attente' }, { value: 'en_cours', label: 'En cours' }, { value: 'traite', label: 'Traité' }] },
          { name: 'accuseReception', label: 'Accusé de réception', type: 'checkbox' },
          { name: 'numerise', label: 'Document numérisé', type: 'checkbox' },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ],
        transform: function (v, record) {
          /* E530 : à la modification, le formulaire ne porte pas la référence — elle était recalculée (ARR-2026-0004 devenait ARR-2026-0012). */
          if (record && record.reference) v.reference = record.reference;
          /* E538 : série annuelle ARR-AAAA-NNNN / DEP-AAAA-NNNN. Le millésime est l'année de la DATE du courrier, le rang court par sens et par année (archivés compris). */
          if (!v.reference) v.reference = C.referenceSuivante((v.sens === 'arrivee' ? 'ARR-' : 'DEP-') + String(v.date || C.iso(AUJ)).slice(0, 4) + '-', 4,
            S.collection('courriers').all().concat(S.collection('courriers').archived()));
          return v;
        },
        onCreate: function () { return { date: C.iso(AUJ), sens: 'arrivee', traitement: 'en_attente', nature: 'Lettre' }; },
        filters: [
          { name: 'sens', label: 'Sens', options: [{ value: 'arrivee', label: 'Arrivée' }, { value: 'depart', label: 'Départ' }] },
          { name: 'traitement', label: 'Traitement', options: [{ value: 'traite', label: 'Traité' }, { value: 'en_cours', label: 'En cours' }, { value: 'en_attente', label: 'En attente' }] },
          { name: 'affecteA', label: 'Service', options: ['Direction Médicale', 'Direction Administrative', 'Comptabilité', 'Ressources humaines', 'Gestion des stocks'] },
        ],
        kpis: function (rows) {
          return [
            { label: 'Courriers enregistrés', value: C.num(rows.length), icon: 'mail', tone: 'navy' },
            { label: 'Arrivées', value: C.num(rows.filter(function (c) { return c.sens === 'arrivee'; }).length), icon: 'mail-open', tone: 'info' },
            { label: 'Départs', value: C.num(rows.filter(function (c) { return c.sens === 'depart'; }).length), icon: 'send', tone: 'success' },
            { label: 'En attente de traitement', value: C.num(rows.filter(function (c) { return c.traitement === 'en_attente'; }).length), icon: 'inbox', tone: 'warning' },
          ];
        },
        etat: function (c) {
          P.etat({
            titre: 'Fiche de courrier',
            sousTitre: c.reference,
            cartouche: [['Référence', c.reference], ['Sens', c.sens === 'arrivee' ? 'Arrivée' : 'Départ'],
              ['Date', C.dateFR(c.date)], ['Correspondant', c.correspondant],
              ['Nature', c.nature], ['Service destinataire', c.affecteA]],
            contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Objet', v: c.objet },
              { k: 'État du traitement', v: { traite: 'Traité', en_cours: 'En cours', en_attente: 'En attente' }[c.traitement] },
              { k: 'Accusé de réception', v: c.accuseReception ? 'Oui' : 'Non' },
              { k: 'Document numérisé', v: c.numerise ? 'Oui' : 'Non' },
              { k: 'Observations', v: c.observations || '—' },
            ]),
            signatures: [{ role: 'L’Agent administratif' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })(root);
    },
    actions: function () {
      return [K.btn('Imprimer le registre', {
        icon: 'printer',
        onclick: function () {
          var rows = C.sortBy(S.collection('courriers').active(), 'date', 'desc');
          P.etat({
            titre: 'Registre du courrier',
            sousTitre: 'Arrivées et départs, exercice ' + (function () {
              var an = {}; rows.forEach(function (c) { an[String(c.date || '').slice(0, 4)] = true; });
              var l = Object.keys(an).filter(Boolean).sort();
              return l.length ? l.join(', ') : String(AUJ.getFullYear());
            })(),
            cartouche: [['Courriers enregistrés', C.num(rows.length)],
              ['Arrivées', C.num(rows.filter(function (c) { return c.sens === 'arrivee'; }).length)],
              ['Départs', C.num(rows.filter(function (c) { return c.sens === 'depart'; }).length)],
              ['Date d’édition', C.dateFR(AUJ)]],
            contenu: P.tableau([
              { label: 'N° d’ordre', key: 'reference' },
              { label: 'Sens', value: function (c) { return c.sens === 'arrivee' ? 'Arrivée' : 'Départ'; } },
              { label: 'Date', value: function (c) { return C.dateFR(c.date); } },
              { label: 'Correspondant', key: 'correspondant' },
              { label: 'Objet', key: 'objet' },
              { label: 'Affecté à', key: 'affecteA' },
              { label: 'Traitement', value: function (c) { return { traite: 'Traité', en_cours: 'En cours', en_attente: 'En attente' }[c.traitement]; } },
            ], rows.slice(0, 80)),
            signatures: [{ role: 'L’Agent administratif' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })];
    },
  });

  /* ==========================================================================
   * RÉUNIONS
   * ======================================================================== */
  global.SIGH.screen('m13-reunions', {
    title: 'Réunions',
    description: 'Planification des réunions, convocations, ordres du jour et comptes rendus.',
    render: function (root) {
      /* Amorcées au SOCLE (data-seed.js) : trois lecteurs — cet écran, le
         tiroir des consultations et le tableau de bord de l'agent
         administratif. Une collection multi-lecteurs ne s'amorce jamais ici. */
      return K.crud({
        collection: 'reunions', entite: 'réunion', entiteP: 'réunions', module: 'M13',
        defaultSort: 'date', defaultDir: 'desc', pageSize: 12,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'heure', label: 'Heure', nowrap: true },
          { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type, 'navy'); } },
          { key: 'lieu', label: 'Lieu' },
          { key: 'president', label: 'Présidée par' },
          { key: 'participants', label: 'Participants', align: 'right' },
          {
            key: 'statutReunion', label: 'Statut', sortable: false,
            value: function (r) { return reunionAVenir(r) ? 'À venir' : 'Tenue'; },
            render: function (r) {
              return reunionAVenir(r) ? U.badge('À venir', 'info') : U.badge('Tenue', 'success');
            },
          },
          {
            key: 'compteRendu', label: 'Compte rendu',
            text: function (r) { return r.compteRendu ? 'Rédigé' : 'À rédiger'; },
            render: function (r) { return r.compteRendu ? U.badge('Rédigé', 'success') : U.badge('À rédiger', 'warning'); },
          },
        ],
        fields: [
          { name: 'type', label: 'Type de réunion', type: 'select', required: true, options: ['Réunion de direction', 'Réunion de service', 'Comité d’hygiène', 'Revue mensuelle d’activité', 'Réunion du personnel', 'Comité de gestion des stocks'] },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'heure', label: 'Heure', type: 'time', required: true },
          { name: 'lieu', label: 'Lieu', type: 'select', options: ['Salle de réunion', 'Bureau de la Direction', 'Salle de garde'] },
          { name: 'president', label: 'Présidée par', type: 'select', required: true, options: optionsAgents() },
          { name: 'participants', label: 'Nombre de participants', type: 'number', min: 1 },
          { name: 'ordreDuJour', label: 'Ordre du jour', type: 'textarea', rows: 3, required: true, col: 'full' },
          { name: 'compteRendu', label: 'Compte rendu rédigé', type: 'checkbox' },
          { name: 'resolutions', label: 'Résolutions adoptées', type: 'textarea', rows: 3, col: 'full' },
        ],
        /* E531 : C.nextRef est un compteur de PAGE (le premier « Nouveau » donnait RU-2026-001, déjà pris) et la modification recalculait la référence. */
        transform: function (v, record) {
          if (record && record.reference) v.reference = record.reference;
          if (!v.reference) v.reference = C.referenceSuivante('RU-2026-', 3, S.collection('reunions').all());
          return v;
        },
        onCreate: function () { return { date: C.iso(AUJ), heure: '09:00', lieu: 'Salle de réunion', participants: 8 }; },
        filters: [{ name: 'type', label: 'Type', options: ['Réunion de direction', 'Réunion de service', 'Comité d’hygiène', 'Revue mensuelle d’activité', 'Réunion du personnel', 'Comité de gestion des stocks'] }],
        kpis: function (rows) {
          return [
            { label: 'Réunions enregistrées', value: C.num(rows.length), icon: 'users', tone: 'navy' },
            { label: 'À venir', value: C.num(rows.filter(reunionAVenir).length), icon: 'calendar-clock', tone: 'info' },
            { label: 'Comptes rendus à rédiger', value: C.num(rows.filter(function (r) { return !r.compteRendu && !reunionAVenir(r); }).length), icon: 'file-clock', tone: 'warning' },
            { label: 'Participants cumulés', value: C.num(C.sum(rows, 'participants')), icon: 'user-check', tone: 'success' },
          ];
        },
        etat: function (r) {
          var futur = reunionAVenir(r);
          P.etat({
            titre: futur ? 'Convocation à une réunion' : 'Compte rendu de réunion',
            sousTitre: r.type + ' — ' + C.dateFR(r.date),
            cartouche: [['Référence', r.reference], ['Type', r.type],
              ['Date', C.dateFR(r.date)], ['Heure', r.heure],
              ['Lieu', r.lieu], ['Présidée par', r.president]],
            contenu: el('div.space-y-3', null, [
              el('p.font-semibold', { text: 'Ordre du jour' }),
              el('p', { text: r.ordreDuJour }),
              futur
                ? el('p.mt-3', { text: 'Les personnes concernées sont priées de bien vouloir prendre toutes dispositions utiles pour prendre part à cette réunion.' })
                : el('div', null, [
                  el('p.mt-3.font-semibold', { text: 'Résolutions adoptées' }),
                  el('p', { text: r.resolutions || 'Aucune résolution consignée.' }),
                  el('p.mt-3.text-\\[10px\\]', { text: 'Nombre de participants : ' + r.participants }),
                ]),
            ]),
            signatures: futur
              ? [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }]
              : [{ role: 'Le Secrétaire de séance' }, { role: 'Le Président de séance', nom: r.president }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * ÉVÉNEMENTS & NOTIFICATIONS
   * ======================================================================== */
  global.SIGH.screen('m13-evenements', {
    title: 'Événements & notifications',
    description: 'Événements de la clinique et paramétrage des notifications adressées au personnel.',
    regle: 'Un événement inscrit ici est <strong>annoncé au personnel concerné</strong> : la notification '
      + 'sonore prévient le poste au moment voulu, sans que l’agent ait à surveiller l’écran.',
    actions: function () {
      return [
        K.btn('Réunions', { icon: 'users-round', onclick: function () { global.SIGH.app.go('m13-reunions'); } }),
        K.btn('Plan annuel', { icon: 'calendar-range', onclick: function () { global.SIGH.app.go('m13-plan-annuel'); } }),
      ];
    },
    render: function (root) {
      var col = S.collection('evenementsEtablissement', { module: 'M13', entite: 'Evenement' });
      function champsEvenement() {
        return [
          { name: 'libelle', label: 'Intitulé de l’événement', required: true, col: 'full' },
          {
            name: 'categorie', label: 'Catégorie', type: 'select', required: true,
            options: ['Santé publique', 'Formation', 'Qualité', 'Technique', 'Logistique', 'Communication', 'Sécurité', 'Réunion'],
          },
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'heure', label: 'Heure', type: 'time', required: true },
          { name: 'lieu', label: 'Lieu', col: 'full' },
          { name: 'responsable', label: 'Responsable', type: 'select', options: personnel().map(function (e) { return { value: e.nomComplet, label: e.nomComplet }; }) },
          { name: 'notifier', label: 'Notifier le personnel', type: 'checkbox' },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ];
      }
      if (!col.all().length && S.amorcable('evenementsEtablissement')) {
        var rnd = C.seeded(2713);
        var EVTS = [
          ['Journée de vaccination', 'Santé publique'], ['Campagne de dépistage du diabète', 'Santé publique'],
          ['Formation aux gestes d’urgence', 'Formation'], ['Audit qualité interne', 'Qualité'],
          ['Maintenance de l’échographe', 'Technique'], ['Inventaire annuel', 'Logistique'],
          ['Réception des nouveaux équipements', 'Logistique'], ['Journée portes ouvertes', 'Communication'],
          ['Formation au nouveau logiciel SIGH', 'Formation'], ['Contrôle des extincteurs', 'Sécurité'],
        ];
        EVTS.forEach(function (e, i) {
          var d = C.addDays(AUJ, C.between(rnd, -60, 90));
          col.all().push({
            id: 'EVT' + C.pad(i + 1, 3), statut: 'actif',
            reference: 'EV-2026-' + C.pad(i + 1, 3),
            libelle: e[0], categorie: e[1],
            date: C.iso(d), heure: C.pad(C.between(rnd, 8, 16)) + ':00',
            lieu: C.pick(rnd, ['Clinique', 'Salle de réunion', 'Extérieur']),
            responsable: C.pick(rnd, personnel()).nomComplet,
            notifier: rnd() > 0.3,
            canaux: ['In-app'].concat(rnd() > 0.5 ? ['SMS'] : []).concat(rnd() > 0.6 ? ['Courriel'] : []),
          });
        });
        S.save();
      }

      var host = el('div.space-y-4');
      var rows = col.active();

      host.appendChild(U.kpiGrid([
        { label: 'Événements planifiés', value: C.num(rows.length), icon: 'calendar-heart', tone: 'navy' },
        { label: 'À venir', value: C.num(rows.filter(evenementAVenir).length), icon: 'calendar-clock', tone: 'info' },
        { label: 'Avec notification', value: C.num(rows.filter(function (e) { return e.notifier; }).length), icon: 'bell', tone: 'warning' },
        { label: 'Catégories', value: C.num(Object.keys(C.groupBy(rows, 'categorie')).length), icon: 'layers', tone: 'neutral' },
      ]));

      /* Prochains événements */
      var prochains = C.sortBy(rows.filter(evenementAVenir), 'date').slice(0, 6);
      if (prochains.length) {
        var grille = el('div.grid.gap-3.sm\\:grid-cols-2.lg\\:grid-cols-3');
        prochains.forEach(function (e) {
          var j = C.daysBetween(C.iso(AUJ), String(e.date).slice(0, 10));
          var carte = el('div.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card');
          carte.appendChild(el('div.mb-2.flex.items-start.justify-between.gap-2', null, [
            U.badge(e.categorie, 'navy'),
            el('span.text-xs.font-semibold', { class: j <= 7 ? 'text-danger-600' : 'text-slate-400', text: j === 0 ? 'Aujourd’hui' : 'Dans ' + j + ' j' }),
          ]));
          carte.appendChild(el('p.text-sm.font-semibold.text-slate-800', { text: e.libelle }));
          carte.appendChild(el('p.mt-1.text-xs.text-slate-500', { text: C.dateJour(e.date) + ' à ' + e.heure }));
          carte.appendChild(el('p.text-xs.text-slate-400', { text: e.lieu + ' — ' + e.responsable }));
          if (e.notifier) {
            carte.appendChild(el('div.mt-2.flex.flex-wrap.gap-1', null, (e.canaux || []).map(function (c) {
              return U.badge(c, 'info');
            })));
          }
          grille.appendChild(carte);
        });
        host.appendChild(U.card('Prochains événements', grille));
      }

      host.appendChild(U.dataTable({
        title: 'Tous les événements', rows: rows, exportName: 'evenements', pageSize: 15,
        rowActions: K.actionsLigne(col, champsEvenement, {
          entite: 'événement',
          /* E532 : cocher « Notifier le personnel » à la modification ne posait aucun canal (colonne « Notification » vide), la décocher gardait les anciens. */
          transform: function (v, record) {
            v.canaux = v.notifier ? ((record.canaux && record.canaux.length) ? record.canaux : ['In-app']) : [];
            return v;
          },
        }),
        actions: [K.creer(col, champsEvenement, {
          titre: 'Nouvel événement de la clinique', entite: 'Événement',
          defauts: function () { return { categorie: 'Santé publique', date: C.iso(AUJ), heure: '09:00', notifier: true }; },
          transform: function (v) {
            v.reference = 'EVT-' + C.pad(col.all().length + 1, 4);
            v.canaux = v.notifier ? ['In-app'] : [];
            return v;
          },
          apres: function () {
            U.alerter('Événement inscrit au calendrier de la clinique.', { son: 'information', type: 'success' });
            setTimeout(function () { global.location.reload(); }, 900);
          },
        })],
        defaultSort: 'date', defaultDir: 'desc',
        filters: [{ name: 'categorie', label: 'Catégorie', options: Object.keys(C.groupBy(rows, 'categorie')).sort() }],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (e) { return el('span.font-mono.text-xs', { text: e.reference }); } },
          { key: 'libelle', label: 'Événement' },
          { key: 'categorie', label: 'Catégorie', render: function (e) { return U.badge(e.categorie, 'navy'); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (e) { return C.dateFR(e.date); }, render: function (e) { return C.dateFR(e.date); } },
          { key: 'heure', label: 'Heure', nowrap: true },
          { key: 'lieu', label: 'Lieu' },
          { key: 'responsable', label: 'Responsable' },
          {
            key: 'notifier', label: 'Notification',
            text: function (e) { return e.notifier ? (e.canaux || []).join(', ') : 'Aucune'; },
            render: function (e) {
              if (!e.notifier) return el('span.text-xs.text-slate-400', { text: 'Aucune' });
              return el('div.flex.flex-wrap.gap-1', null, (e.canaux || []).map(function (c) { return U.badge(c, 'info'); }));
            },
          },
        ],
      }));

      /* Paramétrage des notifications système */
      var NOTIFS = [
        ['Nouvelle admission', 'Alerte à l’admission d’un patient', ['In-app']],
        ['Rupture de stock', 'Produit passant sous le seuil d’alerte', ['In-app', 'SMS']],
        ['Péremption proche', 'Lot arrivant à échéance sous 90 jours', ['In-app']],
        ['Résultat de laboratoire disponible', 'Notification au prescripteur', ['In-app', 'SMS']],
        ['Facture générée', 'Notification à la caisse et à la comptabilité', ['In-app']],
        ['Commande à valider', 'Demande de validation à la Directrice Administrative', ['In-app', 'Courriel']],
        ['Paie à valider', 'Soumission des bulletins à la Direction', ['In-app', 'Courriel']],
        ['Carte d’assurance expirée', 'Alerte à la caisse lors de la facturation', ['In-app']],
        ['Facture MECeF rejetée', 'Alerte fiscale à corriger', ['In-app', 'Courriel']],
        ['Tentative de connexion infructueuse', 'Alerte de sécurité à l’administrateur', ['In-app', 'Courriel']],
      ];
      host.appendChild(U.card('Paramétrage des notifications système',
        K.miniTable([
          { label: 'Événement déclencheur', key: 'n' },
          { label: 'Description', key: 'd' },
          {
            label: 'Canaux actifs',
            render: function (x) {
              return el('div.flex.flex-wrap.gap-1', null, x.c.map(function (canal) { return U.badge(canal, 'success'); }));
            },
          },
        ], NOTIFS.map(function (n) { return { n: n[0], d: n[1], c: n[2] }; })),
        [K.lien('cfg-notifications', 'Modifier le paramétrage', { size: 'sm', icon: 'settings' })]));

      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * PLAN ANNUEL DE TRAVAIL
   * ======================================================================== */
  global.SIGH.screen('m13-plan-annuel', {
    title: 'Plan annuel de travail',
    description: 'Programmation annuelle des activités de la clinique, par axe et par trimestre.',
    render: function (root) {
      var col = S.collection('planAnnuel', { module: 'M13', entite: 'PlanAnnuelTravail' });
      if (!col.all().length && S.amorcable('planAnnuel')) {
        var ACTIONS = [
          ['Déploiement du SIGH-CNT', 'Digitalisation', 1, 4, 'En cours'],
          ['Numérisation des dossiers patients actifs', 'Digitalisation', 2, 4, 'En cours'],
          ['Formation du personnel au nouveau logiciel', 'Formation', 3, 4, 'Planifiée'],
          ['Inventaire général des stocks', 'Logistique', 1, 1, 'Réalisée'],
          ['Renouvellement des conventions d’assurance', 'Partenariats', 1, 2, 'Réalisée'],
          ['Campagne de dépistage communautaire', 'Santé publique', 2, 3, 'En cours'],
          ['Acquisition d’un nouvel échographe', 'Investissement', 3, 3, 'Planifiée'],
          ['Mise à niveau du réseau informatique', 'Investissement', 1, 2, 'Réalisée'],
          ['Audit qualité et sécurité des patients', 'Qualité', 4, 4, 'Planifiée'],
          ['Révision de la grille des primes', 'Ressources humaines', 3, 3, 'Planifiée'],
          ['Clôture comptable de l’exercice', 'Finance', 4, 4, 'Planifiée'],
          ['Rapprochement bancaire mensuel', 'Finance', 1, 4, 'En cours'],
        ];
        ACTIONS.forEach(function (a, i) {
          col.all().push({
            id: 'PAT' + C.pad(i + 1, 3), statut: 'actif',
            reference: 'PA-2026-' + C.pad(i + 1, 3),
            action: a[0], axe: a[1], trimestreDebut: a[2], trimestreFin: a[3],
            avancement: a[4],
            responsable: a[1] === 'Finance' ? 'KASSA Augustin' : (a[1] === 'Logistique' ? 'MAMAN Zoukanéri' : 'TAKI Alimatou'),
          });
        });
        S.save();
      }

      var rows = col.active();
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Actions programmées', value: C.num(rows.length), icon: 'list-checks', tone: 'navy' },
        { label: 'Réalisées', value: C.num(rows.filter(function (r) { return r.avancement === 'Réalisée'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'En cours', value: C.num(rows.filter(function (r) { return r.avancement === 'En cours'; }).length), icon: 'loader', tone: 'info' },
        { label: 'Planifiées', value: C.num(rows.filter(function (r) { return r.avancement === 'Planifiée'; }).length), icon: 'calendar-clock', tone: 'warning' },
      ]));

      /* Diagramme de Gantt simplifié par trimestre */
      var gantt = el('div.overflow-x-auto');
      var t = el('table.tbl.min-w-\\[48rem\\]');
      t.appendChild(el('thead', null, el('tr', null, [
        el('th', { text: 'Action' }), el('th', { text: 'Axe' }),
        el('th.text-center', { text: 'T1' }), el('th.text-center', { text: 'T2' }),
        el('th.text-center', { text: 'T3' }), el('th.text-center', { text: 'T4' }),
        el('th', { text: 'Avancement' }),
      ])));
      var tb = el('tbody');
      C.sortBy(rows, 'trimestreDebut').forEach(function (r) {
        var tr = el('tr');
        tr.appendChild(el('td.text-sm.text-slate-800', { text: r.action }));
        tr.appendChild(el('td', null, U.badge(r.axe, 'navy')));
        for (var q = 1; q <= 4; q++) {
          var actif = q >= r.trimestreDebut && q <= r.trimestreFin;
          var tone = r.avancement === 'Réalisée' ? 'success' : (r.avancement === 'En cours' ? 'info' : 'warning');
          tr.appendChild(el('td.px-1', null,
            el('div.h-3.rounded-full', { class: actif ? 'bg-' + tone + '-400' : 'bg-slate-100' })));
        }
        tr.appendChild(el('td', null, U.badge(r.avancement,
          r.avancement === 'Réalisée' ? 'success' : (r.avancement === 'En cours' ? 'info' : 'warning'))));
        tb.appendChild(tr);
      });
      t.appendChild(tb);
      gantt.appendChild(t);

      host.appendChild(U.card('Plan annuel de travail 2026', gantt, [
        K.btn('Imprimer le plan', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Plan annuel de travail',
              sousTitre: 'Exercice 2026',
              cartouche: [['Exercice', '2026'], ['Actions programmées', C.num(rows.length)],
                ['Réalisées', C.num(rows.filter(function (r) { return r.avancement === 'Réalisée'; }).length)],
                ['Date d’édition', C.dateFR(AUJ)]],
              contenu: P.tableau([
                { label: 'N°', key: 'reference' },
                { label: 'Action', key: 'action' },
                { label: 'Axe', key: 'axe' },
                { label: 'Période', value: function (r) { return 'T' + r.trimestreDebut + ' à T' + r.trimestreFin; } },
                { label: 'Responsable', key: 'responsable' },
                { label: 'Avancement', key: 'avancement' },
              ], C.sortBy(rows, 'trimestreDebut')),
              signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
                { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
            });
          },
        }),
      ]));

      host.appendChild(U.dataTable({
        title: 'Détail des actions', rows: rows, exportName: 'plan-annuel', pageSize: 15,
        rowActions: K.actionsLigne(col, [
          { name: 'action', label: 'Action', required: true, col: 'full' },
          { name: 'responsable', label: 'Responsable' },
          { name: 'echeance', label: 'Échéance', type: 'date' },
          /* E533 : le champ « Avancement (%) » portait le nom de l'ÉTAT (Réalisée / En cours / Planifiée) : modifier une action écrasait l'état par un nombre ou par rien. */
          { name: 'avancement', label: 'État d’avancement', type: 'select', required: true, options: ['Réalisée', 'En cours', 'Planifiée'] },
          { name: 'tauxAvancement', label: 'Avancement (%)', type: 'number', min: 0, max: 100 },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ]),
        filters: [
          { name: 'axe', label: 'Axe', options: Object.keys(C.groupBy(rows, 'axe')).sort() },
          { name: 'avancement', label: 'Avancement', options: ['Réalisée', 'En cours', 'Planifiée'] },
        ],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'action', label: 'Action' },
          { key: 'axe', label: 'Axe', render: function (r) { return U.badge(r.axe, 'navy'); } },
          { key: 'trimestreDebut', label: 'Période', align: 'right', render: function (r) { return 'T' + r.trimestreDebut + ' – T' + r.trimestreFin; } },
          { key: 'responsable', label: 'Responsable' },
          {
            key: 'avancement', label: 'Avancement',
            render: function (r) {
              return U.badge(r.avancement, r.avancement === 'Réalisée' ? 'success' : (r.avancement === 'En cours' ? 'info' : 'warning'));
            },
          },
        ],
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * NOTES DE SERVICE
   * ======================================================================== */
  global.SIGH.screen('m13-notes-service', {
    title: 'Notes de service',
    description: 'Notes de service en vigueur, versions et dates d’effet — sources des règles métier du système.',
    regle: 'Les notes de service ne sont pas de simples documents archivés : elles constituent les <strong>règles métier versionnées</strong> qui pilotent les moteurs d’évaluation (NS 131) et de primes (NS 132).',
    render: function (root) {
      var host = el('div.space-y-4');
      var notes = [D.NS131, D.NS132];

      host.appendChild(U.kpiGrid([
        { label: 'Notes en vigueur', value: C.num(notes.length), icon: 'file-text', tone: 'navy' },
        { label: 'Règles métier pilotées', value: '2', icon: 'settings-2', tone: 'success', hint: 'Évaluation et primes' },
        { label: 'Dernière mise à jour', value: C.dateFR(D.NS131.dateEffet), icon: 'calendar-check', tone: 'info' },
        { label: 'Agents concernés', value: C.num(personnel().length), icon: 'users-round', tone: 'neutral' },
      ]));

      notes.forEach(function (n) {
        var carte = el('div.card');
        var head = el('div.card-head');
        head.appendChild(el('div', null, [
          el('h3.card-title', { text: n.reference }),
          el('p.mt-0\\.5.text-xs.text-slate-500', { text: n.objet }),
        ]));
        head.appendChild(el('div.flex.items-center.gap-2', null, [
          U.badge('Version ' + n.version, 'navy'),
          U.badge(n.statut, 'success'),
          K.lien(n === D.NS131 ? 'm10-evaluations' : 'm10-primes', 'Ouvrir le moteur', { size: 'sm', icon: 'arrow-right' }),
        ]));
        carte.appendChild(head);

        var body = el('div.card-body.space-y-3');
        body.appendChild(U.descList([
          ['Référence', n.reference],
          ['Objet', n.objet],
          ['Date de signature', C.dateFR(n.dateSignature)],
          ['Date d’effet', C.dateFR(n.dateEffet)],
          ['Signataire', n.signataire],
          ['Statut', U.badge(n.statut, 'success')],
          ['Mention', n.mention],
          ['Provenance', n.source],
        ]));

        if (n === D.NS131) {
          body.appendChild(K.miniTable([
            { label: 'N°', key: 'num' },
            { label: 'Élément d’évaluation', key: 'label' },
            { label: 'Moyenne', align: 'right', render: function (c) { return '− ' + c.sanctions.moyenne + ' %'; } },
            { label: 'Faible à mauvaise', align: 'right', render: function (c) { return '− ' + c.sanctions.faible + ' %'; } },
          ], n.criteres));
        } else {
          body.appendChild(K.miniTable([
            { label: 'Prime', key: 'label' },
            { label: 'Mode', render: function (p) { return p.mode === 'fixe' ? 'Forfait mensuel' : 'Par occurrence'; } },
            {
              label: 'Fonctions concernées',
              render: function (p) {
                var f = Object.keys(p.montants);
                return el('div.flex.flex-wrap.gap-1', null, f.map(function (x) {
                  var lib = D.FONCTIONS.filter(function (y) { return y.id === x; })[0];
                  return U.badge(lib ? lib.label.split(' ')[0] : x, 'neutral');
                }));
              },
            },
          ], n.primes));
        }
        carte.appendChild(body);
        host.appendChild(carte);
      });

      host.appendChild(K.note('Une nouvelle note de service crée une <strong>nouvelle version</strong> de la règle, avec sa propre date d’effet. '
        + 'L’historique demeure intact : les paies et évaluations antérieures conservent le barème qui leur était applicable.', { tone: 'info', icon: 'history' }));

      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * INTERVENTIONS AMBULANCE
   * ======================================================================== */
  global.SIGH.screen('m13-ambulance', {
    title: 'Interventions ambulance',
    description: 'Registre des sorties d’ambulance : transports sanitaires, urgences et évacuations.',
    render: function (root) {
      /* Peuplé AU SOCLE (data-seed.js), à la forme que cet écran lit —
         dateHeure, kilometrage, tarif, facture, plus l'etat (demandée /
         en cours / terminée) que le tableau de bord de l'ambulancier
         consomme. Le second seed qui vivait ici ne gagnait jamais. */
      return K.crud({
        collection: 'ambulance', entite: 'intervention', entiteP: 'interventions', module: 'M13',
        defaultSort: 'dateHeure', defaultDir: 'desc', pageSize: 15,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (a) { return el('span.font-mono.text-xs', { text: a.reference }); } },
          {
            key: 'dateHeure', label: 'Date et heure', nowrap: true,
            text: function (a) { return C.dateHeure(a.dateHeure); },
            render: function (a) { return C.dateHeure(a.dateHeure); },
            sortValue: function (a) { return C.toDate(a.dateHeure).getTime(); },
          },
          {
            key: 'patient', label: 'Patient',
            render: function (a) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.text-slate-800', { text: a.patient }),
                el('p.font-mono.text-xs.text-slate-400', { text: a.patientCode }),
              ]);
            },
          },
          { key: 'motif', label: 'Motif', render: function (a) { return U.badge(a.motif, a.motif.indexOf('Urgence') === 0 ? 'danger' : 'navy'); } },
          { key: 'destination', label: 'Destination' },
          { key: 'kilometrage', label: 'Km', align: 'right' },
          { key: 'chauffeur', label: 'Chauffeur' },
          { key: 'accompagnant', label: 'Accompagnant' },
          { key: 'tarif', label: 'Montant', align: 'right', text: function (a) { return C.money(a.tarif, false); }, render: function (a) { return C.money(a.tarif, false); } },
          {
            key: 'etat', label: 'État',
            text: function (a) { return ETATS_INTERVENTION[a.etat] ? ETATS_INTERVENTION[a.etat][0] : '—'; },
            render: function (a) {
              var x = ETATS_INTERVENTION[a.etat] || ['—', 'neutral'];
              return U.badge(x[0], x[1]);
            },
          },
          {
            key: 'facture', label: 'Facturation',
            text: function (a) { return a.facture ? 'Facturée' : 'À facturer'; },
            render: function (a) { return a.facture ? U.badge('Facturée', 'success') : U.badge('À facturer', 'warning'); },
          },
        ],
        fields: function () {
          return [
            {
              name: 'patientCode', label: 'Patient', type: 'select', required: true, col: 'full',
              options: C.sortBy(S.collection('patients').active(), 'code').map(function (p) { return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom }; }),
            },
            { name: 'dateHeure', label: 'Date et heure', type: 'datetime-local', required: true },
            { name: 'motif', label: 'Motif', type: 'select', required: true, options: ['Urgence médicale', 'Transfert inter-hospitalier', 'Évacuation sanitaire', 'Retour à domicile', 'Accident de la voie publique', 'Urgence obstétricale'] },
            { name: 'destination', label: 'Destination', required: true, col: 'full' },
            { name: 'kilometrage', label: 'Kilométrage parcouru', type: 'number', min: 0, required: true },
            { name: 'etat', label: 'État de l’intervention', type: 'select', required: true,
              options: [{ value: 'demandee', label: 'Demandée' }, { value: 'en_cours', label: 'En cours' }, { value: 'terminee', label: 'Terminée' }] },
            { name: 'chauffeur', label: 'Chauffeur', type: 'select', options: optionsAgents() },
            { name: 'accompagnant', label: 'Accompagnant médical', type: 'select', options: optionsAgents() },
            { name: 'tarif', label: 'Montant facturé (FCFA)', type: 'money', min: 0 },
            { name: 'facture', label: 'Intervention facturée', type: 'checkbox' },
          ];
        },
        transform: function (v, record) {
          var p = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
          if (p) { v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom; }
          if (!v.tarif) v.tarif = 5000 + (Number(v.kilometrage) || 0) * 500;
          /* E534 : C.nextRef = compteur de page (le premier « Nouveau » donnait AM-2026-0001, déjà pris) ; la modification recalculait la référence. */
          if (record && record.reference) v.reference = record.reference;
          if (!v.reference) v.reference = C.referenceSuivante('AM-2026-', 4, S.collection('ambulance').all());
          return v;
        },
        onCreate: function () { return { chauffeur: 'TCHANE Nourou', facture: false, kilometrage: 10, etat: 'demandee' }; },
        filters: [
          { name: 'etat', label: 'État', options: [{ value: 'demandee', label: 'Demandée' }, { value: 'en_cours', label: 'En cours' }, { value: 'terminee', label: 'Terminée' }] },
          { name: 'motif', label: 'Motif', options: ['Urgence médicale', 'Transfert inter-hospitalier', 'Évacuation sanitaire', 'Retour à domicile', 'Accident de la voie publique', 'Urgence obstétricale'] },
          { name: 'facture', label: 'Facturation', options: [{ value: 'oui', label: 'Facturées' }, { value: 'non', label: 'À facturer' }], match: function (a, v) { return v === 'oui' ? !!a.facture : !a.facture; } },
        ],
        kpis: function (rows) {
          var mois = rows.filter(function (a) {
            var d = C.toDate(a.dateHeure);
            return d.getMonth() === AUJ.getMonth() && d.getFullYear() === AUJ.getFullYear();
          });
          return [
            { label: 'Interventions enregistrées', value: C.num(rows.length), icon: 'ambulance', tone: 'danger' },
            { label: 'Ce mois-ci', value: C.num(mois.length), icon: 'calendar', tone: 'navy' },
            { label: 'Kilométrage cumulé', value: C.num(C.sum(rows, 'kilometrage')) + ' km', icon: 'route', tone: 'info' },
            { label: 'Recettes ambulance', value: C.money(C.sum(rows.filter(function (a) { return a.facture; }), 'tarif')), icon: 'wallet', tone: 'success' },
          ];
        },
        etat: function (a) {
          P.etat({
            titre: 'Fiche d’intervention — ambulance',
            sousTitre: a.reference,
            cartouche: [['Référence', a.reference], ['Date et heure', C.dateHeure(a.dateHeure)],
              ['Patient', a.patient], ['Dossier', a.patientCode],
              ['Motif', a.motif], ['Destination', a.destination]],
            contenu: P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Kilométrage parcouru', v: a.kilometrage + ' km' },
              { k: 'Chauffeur', v: a.chauffeur },
              { k: 'Accompagnant médical', v: a.accompagnant },
              { k: 'Montant facturé', v: C.money(a.tarif) },
              { k: 'Facturation', v: a.facture ? 'Facturée' : 'À facturer' },
            ]),
            signatures: [{ role: 'Le Chauffeur', nom: a.chauffeur },
              { role: 'L’Accompagnant médical', nom: a.accompagnant },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * RÉPERTOIRE DES AMBULANCES
   * --------------------------------------------------------------------------
   * Demande de la Direction : « l'accueil garde et met à jour les numéros
   * d'ambulance, avec appel rapide ».
   *
   * POURQUOI CET ÉCRAN N'EST PAS UN SIMPLE CARNET D'ADRESSES. On y vient dans
   * une urgence, et trois choses décident du temps perdu :
   *
   *   1. LA DISPONIBILITÉ D'ABORD. Un numéro qu'on appelle pour s'entendre dire
   *      « nous sommes en course » a coûté deux minutes. Les ambulances
   *      disponibles remontent en tête, et l'indisponible est visiblement telle.
   *
   *   2. LE NUMÉRO EN GRAND, cliquable. À l'accueil on compose sur un
   *      téléphone posé à côté : le numéro doit se lire d'un coup d'œil,
   *      sans loupe. Le lien tel: sert quand le poste est équipé.
   *
   *   3. LA DERNIÈRE VÉRIFICATION EST DATÉE. Un répertoire d'urgence dont on
   *      ignore l'âge est un répertoire qu'on n'ose pas utiliser. Un numéro non
   *      vérifié depuis plus de quatre-vingt-dix jours est signalé — signalé,
   *      pas masqué : un vieux numéro reste meilleur que rien.
   *
   * Le répertoire couvre les ambulances de la clinique ET celles de
   * l'extérieur : un jour d'affluence, la clinique appelle le voisin.
   * ======================================================================== */
  var TYPES_AMBULANCE = [
    { code: 'clinique', label: 'Ambulance de la clinique', icone: 'ambulance', ton: 'success' },
    { code: 'partenaire', label: 'Structure partenaire', icone: 'handshake', ton: 'info' },
    { code: 'publique', label: 'Service public', icone: 'building-2', ton: 'navy' },
    { code: 'prive', label: 'Transporteur privé', icone: 'truck', ton: 'neutral' },
  ];

  var DISPONIBILITES = [
    { code: 'disponible', label: 'Disponible', ton: 'success', ordre: 1 },
    { code: 'en_course', label: 'En course', ton: 'warning', ordre: 2 },
    { code: 'indisponible', label: 'Indisponible', ton: 'danger', ordre: 3 },
  ];

  var JOURS_VERIFICATION = 90;

  function colAmbulances() {
    return S.collection('ambulances', { module: 'M13', entite: 'ambulance', prefix: 'AMB' });
  }

  global.SIGH.screen('m13-repertoire-ambulances', {
    title: 'Répertoire des ambulances',
    description: 'Numéros d’ambulance tenus à jour par l’accueil, avec appel rapide et disponibilité.',
    regle: 'On vient ici <strong>dans une urgence</strong>. Les ambulances <strong>disponibles remontent '
      + 'en tête</strong>, le numéro se lit d’un coup d’œil, et la <strong>date de dernière vérification</strong> '
      + 'est affichée : un répertoire d’urgence dont on ignore l’âge est un répertoire qu’on n’ose pas '
      + 'utiliser. Un numéro périmé est <strong>signalé, jamais masqué</strong> — un vieux numéro vaut mieux '
      + 'que rien.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      amorcer();
      afficher();
      return null;

      function typeDe(code) {
        return TYPES_AMBULANCE.filter(function (t) { return t.code === code; })[0] || TYPES_AMBULANCE[3];
      }
      function dispoDe(code) {
        return DISPONIBILITES.filter(function (d) { return d.code === code; })[0] || DISPONIBILITES[2];
      }
      function joursDepuis(iso) {
        if (!iso) return null;
        return C.daysBetween(String(iso).slice(0, 10), C.iso(new Date()));   /* E540 : par JOUR — vérifié ce matin, « 1 j » dès midi */
      }
      function perime(r) {
        var j = joursDepuis(r.verifieLe);
        return j == null || j > JOURS_VERIFICATION;
      }

      /* Amorçage : les moyens que la clinique possède réellement, complétés
         des structures de Natitingou qu'elle appelle. Les numéros de la
         clinique sont ceux de son en-tête ; les autres sont des ENTRÉES À
         COMPLÉTER, marquées comme telles — inventer un numéro d'urgence
         serait la faute la plus grave de tout ce prototype. */
      function amorcer() {
        var col = colAmbulances();
        if (col.all().length) return;
        var chauffeur = S.collection('personnel').active()
          .filter(function (a) { return a.fonction === 'chauffeur'; })[0];
        [
          ['Ambulance CNT 01', 'clinique', C.BRAND.telephones[0],
            chauffeur ? chauffeur.nomComplet : 'Chauffeur de garde', 'Natitingou — clinique', true],
          ['Ambulance CNT 02', 'clinique', C.BRAND.telephones[1],
            'Chauffeur de garde', 'Natitingou — clinique', true],
          ['CHD Atacora — ambulance', 'publique', null, 'Régulation du CHD', 'Natitingou', false],
          ['Zone sanitaire de Natitingou', 'publique', null, 'Bureau de la zone', 'Natitingou', false],
          ['Sapeurs-pompiers', 'publique', null, 'Poste de commandement', 'Natitingou', false],
        ].forEach(function (a) {
          col.insert({
            libelle: a[0], type: a[1], telephone: a[2],
            contact: a[3], base: a[4],
            disponibilite: a[2] ? 'disponible' : 'indisponible',
            verifieLe: a[5] ? C.iso(new Date()) : null,
            /* Un numéro absent le DIT. Le laisser vide sans explication ferait
               croire à un oubli de saisie ; l'inventer serait pire. */
            aCompleter: !a[2],
            source: a[5] ? 'En-tête officiel de la clinique' : 'Structure à contacter — numéro à renseigner',
          });
        });
        S.save();
      }

      function champs() {
        return [
          { name: 'libelle', label: 'Désignation', type: 'text', required: true },
          { name: 'type', label: 'Type', type: 'select', required: true,
            options: TYPES_AMBULANCE.map(function (t) { return { value: t.code, label: t.label }; }) },
          { name: 'telephone', label: 'Téléphone', type: 'text',   /* E535 : jamais obligatoire — la consigne est « laisser la fiche à compléter », exiger un numéro forçait à en inventer un */
            hint: 'Le numéro que l’accueil compose. Ne rien inventer : laisser la fiche à compléter.' },
          { name: 'telephone2', label: 'Second numéro', type: 'text' },
          { name: 'contact', label: 'Personne à demander', type: 'text' },
          { name: 'base', label: 'Base ou localisation', type: 'text' },
          { name: 'disponibilite', label: 'Disponibilité', type: 'select', required: true,
            options: DISPONIBILITES.map(function (d) { return { value: d.code, label: d.label }; }) },
          { name: 'capacite', label: 'Capacité et équipement', type: 'text',
            hint: 'Brancard, oxygène, accompagnant possible…' },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2 },
        ];
      }

      function afficher() {
        var rows = colAmbulances().active();
        var dispo = rows.filter(function (r) { return r.disponibilite === 'disponible' && r.telephone; });
        var aCompleter = rows.filter(function (r) { return !r.telephone; });
        var perimes = rows.filter(function (r) { return r.telephone && perime(r); });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Moyens répertoriés', value: C.num(rows.length), icon: 'ambulance', tone: 'navy' },
          { label: 'Disponibles maintenant', value: C.num(dispo.length), icon: 'circle-check',
            tone: dispo.length ? 'success' : 'danger',
            hint: dispo.length ? null : 'aucun moyen joignable' },
          { label: 'Numéros à renseigner', value: C.num(aCompleter.length), icon: 'phone-off',
            tone: aCompleter.length ? 'warning' : 'success' },
          { label: 'Non vérifiés depuis ' + JOURS_VERIFICATION + ' j', value: C.num(perimes.length),
            icon: 'clock-alert', tone: perimes.length ? 'warning' : 'success' },
        ]));

        if (aCompleter.length) {
          vue.appendChild(K.note('<strong>' + aCompleter.length + ' fiche(s) sans numéro</strong> : '
            + aCompleter.map(function (r) { return r.libelle; }).join(' · ')
            + '. Ces structures sont connues de la clinique mais leur numéro n’a pas été relevé. '
            + '<strong>Inventer un numéro d’urgence serait la faute la plus grave de tout ce prototype</strong> — '
            + 'la fiche reste donc vide et le dit.', { tone: 'warning', icon: 'phone-off' }));
        }

        /* Les cartes d'appel rapide : disponibles d'abord, numéro en grand. */
        vue.appendChild(U.card('Appel rapide', cartes(rows)));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'libelle'),
          empty: 'Aucune ambulance répertoriée.',
          actions: [K.creer(colAmbulances(), champs(), {
            module: 'M13', label: 'Ajouter une ambulance', titre: 'Fiche ambulance',
            entite: 'Ambulance', apres: afficher,
            transform: function (v) {
              return Object.assign({ verifieLe: C.iso(new Date()), aCompleter: !v.telephone,
                source: 'Saisie à l’accueil' }, v);
            },
          })].filter(Boolean),
          columns: [
            { key: 'libelle', label: 'Désignation' },
            { key: 'type', label: 'Type', render: function (r) {
              var t = typeDe(r.type); return U.badge(t.label, t.ton);
            } },
            { key: 'telephone', label: 'Téléphone',
              render: function (r) {
                if (!r.telephone) return el('span.text-xs.italic.text-amber-700', { text: 'à renseigner' });
                return el('span.font-mono.font-semibold', { text: r.telephone });
              } },
            { key: 'contact', label: 'Demander' },
            { key: 'base', label: 'Base' },
            { key: 'disponibilite', label: 'Disponibilité', render: function (r) {
              var d = dispoDe(r.disponibilite); return U.badge(d.label, d.ton);
            } },
            { key: 'verifieLe', label: 'Vérifié le',
              render: function (r) {
                if (!r.verifieLe) return el('span.text-xs.italic.text-amber-700', { text: 'jamais' });
                var j = joursDepuis(r.verifieLe);
                return el('span', { class: j > JOURS_VERIFICATION ? 'text-amber-700 font-medium' : '',
                  text: C.dateFR(r.verifieLe) + ' (' + j + ' j)' });
              } },
          ],
          rowActions: function (r) {
            var actes = [];
            if (K.droits('M13').editer) {
              actes.push(K.iconBtn('circle-check', 'Confirmer que ce numéro est à jour', function () {
                verifier(r);
              }));
              actes.push(K.iconBtn('repeat', 'Changer la disponibilité', function () { basculer(r); }));
            }
            return actes.concat(K.actionsLigne(colAmbulances(), champs(), {
              module: 'M13', refresh: afficher,
              titre: function (x) { return x.libelle; },
              detail: function (x) {
                return el('div.space-y-4', null, [
                  K.grid([
                    ['Désignation', x.libelle], ['Type', typeDe(x.type).label],
                    ['Téléphone', x.telephone || 'à renseigner'],
                    ['Second numéro', x.telephone2 || '—'],
                    ['Personne à demander', x.contact || '—'],
                    ['Base', x.base || '—'],
                    ['Disponibilité', dispoDe(x.disponibilite).label],
                    ['Capacité', x.capacite || '—'],
                    ['Vérifié le', x.verifieLe ? C.dateFR(x.verifieLe) : 'jamais'],
                    ['Origine de la fiche', x.source || '—'],
                  ]),
                  x.observations ? K.section('Observations',
                    el('p.text-sm.text-slate-600', { text: x.observations })) : null,
                  !x.telephone ? K.note('Le numéro de cette structure n’a pas été relevé. La fiche reste '
                    + 'vide plutôt que de porter une valeur inventée.', { tone: 'warning', icon: 'phone-off' }) : null,
                ].filter(Boolean));
              },
            })(r));
          },
        }));
        U.icons(vue);
      }

      /* Les cartes d'appel : disponibles d'abord, numéro en grand. */
      function cartes(rows) {
        var tries = rows.slice().sort(function (a, b) {
          var da = dispoDe(a.disponibilite).ordre, db = dispoDe(b.disponibilite).ordre;
          if (da !== db) return da - db;
          /* À disponibilité égale, la clinique avant l'extérieur. */
          if ((a.type === 'clinique') !== (b.type === 'clinique')) return a.type === 'clinique' ? -1 : 1;
          return String(a.libelle).localeCompare(String(b.libelle));
        });

        var grille = el('div.grid.gap-3.sm\\:grid-cols-2.lg\\:grid-cols-3');
        tries.forEach(function (r) {
          var d = dispoDe(r.disponibilite);
          var t = typeDe(r.type);
          var carte = el('div.rounded-xl.border.p-4', {
            class: r.disponibilite === 'disponible' && r.telephone
              ? 'border-emerald-200 bg-emerald-50' : 'border-slate-200 bg-white',
          });
          carte.appendChild(el('div.flex.items-center.justify-between.gap-2', null, [
            el('p.text-sm.font-semibold.text-slate-800', { text: r.libelle }),
            U.badge(d.label, d.ton),
          ]));
          carte.appendChild(el('p.mt-1.text-xs.text-slate-500', { text: t.label + (r.base ? ' — ' + r.base : '') }));
          if (r.telephone) {
            /* Le numéro EN GRAND : à l'accueil, on compose sur un téléphone
               posé à côté — il doit se lire d'un coup d'œil, sans loupe. */
            var lien = el('a.mt-3.block.font-mono.text-2xl.font-bold.tracking-tight.text-navy-900.hover\\:underline', {
              href: 'tel:' + String(r.telephone).replace(/\s+/g, ''),
              text: r.telephone,
            });
            carte.appendChild(lien);
            if (r.telephone2) {
              carte.appendChild(el('a.mt-1.block.font-mono.text-sm.text-slate-600.hover\\:underline', {
                href: 'tel:' + String(r.telephone2).replace(/\s+/g, ''), text: r.telephone2,
              }));
            }
          } else {
            carte.appendChild(el('p.mt-3.text-sm.font-medium.italic.text-amber-700',
              { text: 'Numéro à renseigner' }));
          }
          if (r.contact) {
            carte.appendChild(el('p.mt-2.text-xs.text-slate-500', { text: 'Demander : ' + r.contact }));
          }
          if (r.telephone && perime(r)) {
            carte.appendChild(el('p.mt-2.text-xs.font-medium.text-amber-700', {
              text: r.verifieLe ? 'Non vérifié depuis ' + joursDepuis(r.verifieLe) + ' jours' : 'Jamais vérifié',   /* E535 : « depuis null jours » */
            }));
          }
          grille.appendChild(carte);
        });
        return el('div', null, [
          K.note('Les moyens <strong>disponibles</strong> remontent en tête, ceux de la clinique avant '
            + 'l’extérieur. Un numéro qu’on appelle pour s’entendre dire « nous sommes en course » a coûté '
            + 'deux minutes qu’une urgence n’a pas.', { tone: 'info', icon: 'ambulance' }),
          grille,
        ]);
      }

      function verifier(r) {
        colAmbulances().update(r.id, { verifieLe: C.iso(new Date()), verifiePar: S.currentUser() });
        afficher();
        U.toast('Numéro confirmé à jour.', { type: 'success', detail: r.libelle });
      }

      function basculer(r) {
        var f = U.form([
          { name: 'disponibilite', label: 'Disponibilité', type: 'select', required: true,
            options: DISPONIBILITES.map(function (d) { return { value: d.code, label: d.label }; }) },
          { name: 'observations', label: 'Précision', type: 'text' },
        ], { disponibilite: r.disponibilite });
        var m = U.modal({
          title: 'Disponibilité — ' + r.libelle, size: 'sm', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Appliquer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                colAmbulances().update(r.id, v);
                m.close(); afficher();
                U.toast('Disponibilité mise à jour.', { type: 'success',
                  detail: r.libelle + ' — ' + dispoDe(v.disponibilite).label });
              } }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * PARC TECHNIQUE & MAINTENANCE
   * --------------------------------------------------------------------------
   * DEUX PARTIS PRIS.
   *
   * 1. LE PARC EST UNE PROPOSITION, PAS UN RELEVÉ. Aucun document de cadrage
   *    n'inventorie les équipements : l'inventaire SAGE porte les ARTICLES
   *    (médicaments, consommables), pas les machines. Les fiches amorcées ici
   *    portent donc « aCompleter » et l'écran le dit. Inventer un numéro de
   *    série ou une date de mise en service donnerait une donnée fausse qu'on
   *    croirait relevée sur la plaque de la machine.
   *
   * 2. UNE PANNE EST UN ÉTAT, PAS UN COMMENTAIRE. Trois états seulement — en
   *    service, en panne, réformé — parce que c'est la seule question à
   *    laquelle le laboratoire a besoin d'une réponse à huit heures du matin.
   * ======================================================================== */
  var ETATS_MATERIEL = [
    { code: 'service', label: 'En service', ton: 'success' },
    { code: 'panne', label: 'En panne', ton: 'danger' },
    { code: 'reforme', label: 'Réformé', ton: 'neutral' },
  ];
  var CATEGORIES_MATERIEL = ['Automate de laboratoire', 'Imagerie', 'Bloc opératoire',
    'Matériel de soins', 'Énergie & froid', 'Bureautique & réseau', 'Véhicule'];
  var LOCALISATIONS_MATERIEL = ['Laboratoire', 'Salle d’échographie', 'Bloc opératoire',
    'Salle de soins', 'Maternité', 'Hospitalisation', 'Pharmacie', 'Administration', 'Local technique'];

  function etatMateriel(code) {
    return ETATS_MATERIEL.filter(function (e) { return e.code === code; })[0] || ETATS_MATERIEL[0];
  }

  global.SIGH.screen('m13-maintenance', {
    title: 'Parc technique & maintenance',
    description: 'Équipements de la clinique, état de marche, entretiens périodiques et pannes signalées.',
    regle: 'Un automate en panne <strong>arrête le laboratoire</strong> : l’état de marche prime sur tout '
      + 'le reste, et c’est la première colonne. Le parc amorcé ici est une <strong>proposition à '
      + 'compléter</strong> — aucun document de cadrage n’inventorie les équipements, l’inventaire SAGE '
      + 'ne porte que les articles. Les fiches non vérifiées sont <strong>signalées, jamais présentées '
      + 'comme relevées</strong>.',
    render: function (root) {
      var col = S.collection('materiel', { module: 'M13', entite: 'Materiel' });

      /* Amorçage : les équipements que les documents laissent DÉDUIRE — un
         laboratoire qui rend des hémogrammes a un automate, un échographiste
         a un échographe, un bloc a son bistouri électrique. Rien de plus. */
      if (!col.all().length) {
        var rnd = C.seeded(1348);
        [
          ['Automate d’hématologie', 'Automate de laboratoire', 'Laboratoire', 'service'],
          ['Automate de biochimie', 'Automate de laboratoire', 'Laboratoire', 'service'],
          ['Centrifugeuse', 'Automate de laboratoire', 'Laboratoire', 'service'],
          ['Microscope optique', 'Automate de laboratoire', 'Laboratoire', 'service'],
          ['Échographe', 'Imagerie', 'Salle d’échographie', 'service'],
          ['Bistouri électrique', 'Bloc opératoire', 'Bloc opératoire', 'service'],
          ['Table d’opération', 'Bloc opératoire', 'Bloc opératoire', 'service'],
          ['Aspirateur chirurgical', 'Bloc opératoire', 'Bloc opératoire', 'panne'],
          ['Autoclave de stérilisation', 'Bloc opératoire', 'Bloc opératoire', 'service'],
          ['Concentrateur d’oxygène', 'Matériel de soins', 'Hospitalisation', 'service'],
          ['Moniteur multiparamétrique', 'Matériel de soins', 'Hospitalisation', 'service'],
          ['Table d’accouchement', 'Matériel de soins', 'Maternité', 'service'],
          ['Couveuse néonatale', 'Matériel de soins', 'Maternité', 'service'],
          ['Groupe électrogène', 'Énergie & froid', 'Local technique', 'service'],
          ['Réfrigérateur à réactifs', 'Énergie & froid', 'Laboratoire', 'service'],
          ['Réfrigérateur de pharmacie', 'Énergie & froid', 'Pharmacie', 'service'],
          ['Serveur et onduleur', 'Bureautique & réseau', 'Administration', 'service'],
          ['Ambulance de la clinique', 'Véhicule', 'Local technique', 'service'],
        ].forEach(function (m, i) {
          var dernier = C.addDays(AUJ, -C.between(rnd, 20, 260));
          col.all().push({
            id: 'MAT' + C.pad(i + 1, 3), statut: 'actif',
            reference: 'EQ-' + C.pad(i + 1, 3),
            libelle: m[0], categorie: m[1], localisation: m[2], etat: m[3],
            /* Non renseignés à dessein : voir le parti pris 1 ci-dessus. */
            marque: null, numeroSerie: null, miseEnService: null,
            periodiciteMois: (m[1] === 'Automate de laboratoire' || m[1] === 'Énergie & froid') ? 6 : 12,
            dernierEntretien: C.iso(dernier),
            observation: m[3] === 'panne' ? 'Panne signalée par le bloc — dépannage à commander.' : null,
            aCompleter: true,
          });
        });
        S.save();
      }

      function echu(r) {
        if (!r.dernierEntretien || !r.periodiciteMois) return false;
        if (r.etat === 'reforme') return false;   /* E536 : un équipement réformé n'a plus d'entretien à faire — il gonflait l'indicateur « Entretien échu » */
        return C.addDays(C.toDate(r.dernierEntretien), Math.round(r.periodiciteMois * 30.4)) < AUJ;
      }

      return K.crud({
        collection: 'materiel', entite: 'équipement', entiteP: 'équipements', module: 'M13',
        defaultSort: 'libelle', pageSize: 14,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true,
            render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          {
            /* L'état de marche en tête : c'est la seule question posée à huit
               heures du matin. */
            key: 'etat', label: 'État', nowrap: true,
            text: function (r) { return etatMateriel(r.etat).label; },
            render: function (r) {
              var e = etatMateriel(r.etat);
              return U.badge(e.label, e.ton === 'danger' ? 'danger' : (e.ton === 'success' ? 'success' : 'neutral'));
            },
          },
          { key: 'libelle', label: 'Équipement' },
          { key: 'categorie', label: 'Catégorie', render: function (r) { return U.badge(r.categorie, 'navy'); } },
          { key: 'localisation', label: 'Localisation' },
          {
            key: 'marque', label: 'Marque',
            text: function (r) { return r.marque || '—'; },
            render: function (r) {
              return r.marque ? el('span', { text: r.marque })
                : el('span.text-xs.italic.text-slate-400', { text: 'à compléter' });
            },
          },
          {
            key: 'dernierEntretien', label: 'Dernier entretien', nowrap: true,
            text: function (r) { return r.dernierEntretien ? C.dateFR(r.dernierEntretien) : '—'; },
            render: function (r) {
              if (!r.dernierEntretien) return el('span.text-xs.italic.text-slate-400', { text: 'jamais' });
              var t = el('span', { text: C.dateFR(r.dernierEntretien) });
              if (!echu(r)) return t;
              return el('span.flex.items-center.gap-1\\.5', null, [t, U.badge('échu', 'warning')]);
            },
          },
          {
            key: 'periodiciteMois', label: 'Périodicité', align: 'right',
            text: function (r) { return r.periodiciteMois ? r.periodiciteMois + ' mois' : '—'; },
            render: function (r) { return r.periodiciteMois ? r.periodiciteMois + ' mois' : '—'; },
          },
        ],
        fields: [
          { name: 'libelle', label: 'Équipement', required: true, col: 'full' },
          { name: 'categorie', label: 'Catégorie', type: 'select', required: true, options: CATEGORIES_MATERIEL },
          { name: 'localisation', label: 'Localisation', type: 'select', required: true, options: LOCALISATIONS_MATERIEL },
          { name: 'etat', label: 'État de marche', type: 'select', required: true,
            options: ETATS_MATERIEL.map(function (e) { return { value: e.code, label: e.label }; }) },
          { name: 'marque', label: 'Marque et modèle' },
          { name: 'numeroSerie', label: 'Numéro de série' },
          { name: 'miseEnService', label: 'Mise en service', type: 'date' },
          { name: 'periodiciteMois', label: 'Périodicité d’entretien (mois)', type: 'number', min: 1 },
          { name: 'dernierEntretien', label: 'Dernier entretien', type: 'date' },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ],
        transform: function (v, record) {
          /* E536 : compteur de page (EQ-001 déjà pris) et référence recalculée à chaque modification. */
          if (record && record.reference) v.reference = record.reference;
          if (!v.reference) v.reference = C.referenceSuivante('EQ-', 3, S.collection('materiel').all());
          /* Une fiche renseignée cesse d'être « à compléter » : le marquage
             disparaît par la saisie, non par une case à cocher qu'on oublie. */
          v.aCompleter = !(v.marque && v.numeroSerie && v.miseEnService);
          return v;
        },
        onCreate: function () {
          return { etat: 'service', periodiciteMois: 12, dernierEntretien: C.iso(AUJ) };
        },
        filters: [
          {
            /* Trois lectures d'une même population, pas trois populations :
               un filtre, et non des onglets. */
            name: 'suivi', label: 'Suivi',
            options: [
              { value: 'panne', label: 'En panne' },
              { value: 'echu', label: 'Entretien échu' },
              { value: 'acompleter', label: 'Fiche à compléter' },
            ],
            match: function (r, v) {
              if (v === 'panne') return r.etat === 'panne';
              if (v === 'echu') return echu(r);
              return !!r.aCompleter;
            },
          },
          { name: 'categorie', label: 'Catégorie', options: CATEGORIES_MATERIEL },
          { name: 'localisation', label: 'Localisation', options: LOCALISATIONS_MATERIEL },
        ],
        kpis: function (rows) {
          var pannes = rows.filter(function (r) { return r.etat === 'panne'; });
          return [
            { label: 'Équipements au parc', value: C.num(rows.length), icon: 'wrench', tone: 'navy' },
            { label: 'En panne', value: C.num(pannes.length), icon: 'triangle-alert',
              tone: pannes.length ? 'danger' : 'success' },
            { label: 'Entretien échu', value: C.num(rows.filter(echu).length), icon: 'calendar-clock', tone: 'warning' },
            { label: 'Fiches à compléter', value: C.num(rows.filter(function (r) { return r.aCompleter; }).length),
              icon: 'circle-help', tone: 'neutral',
              hint: 'marque, n° de série et mise en service non relevés' },
          ];
        },
        etat: function (r) {
          P.etat({
            titre: 'Fiche d’équipement',
            sousTitre: r.libelle + ' — ' + r.reference,
            cartouche: [['Référence', r.reference], ['Catégorie', r.categorie],
              ['Localisation', r.localisation], ['État', etatMateriel(r.etat).label],
              ['Marque et modèle', r.marque || 'non relevé'],
              ['N° de série', r.numeroSerie || 'non relevé'],
              ['Mise en service', r.miseEnService ? C.dateFR(r.miseEnService) : 'non relevée'],
              ['Périodicité d’entretien', r.periodiciteMois ? r.periodiciteMois + ' mois' : 'non définie'],
              ['Dernier entretien', r.dernierEntretien ? C.dateFR(r.dernierEntretien) : 'jamais']],
            contenu: el('div.space-y-3', null, [
              el('p.font-semibold', { text: 'Observation' }),
              el('p', { text: r.observation || 'Aucune observation consignée.' }),
              r.aCompleter
                ? el('p.mt-3.text-\\[10px\\].italic', {
                  text: 'Fiche à compléter : marque, numéro de série ou date de mise en service '
                    + 'non relevés sur la machine.' })
                : null,
            ].filter(Boolean)),
            signatures: [{ role: 'L’Ingénieur biomédical' },
              { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })(root);
    },
  });


  /* ==========================================================================
   * PHASE 10 \u2014 ENQU\u00caTES & SATISFACTION (cible Instructions)
   * --------------------------------------------------------------------------
   * Le principe KoboCollect, transpos\u00e9 hors ligne : le QUESTIONNAIRE est une
   * donn\u00e9e \u2014 le formulaire de saisie NA\u00ceT du mod\u00e8le, il n'est pas cod\u00e9.
   * Ajouter une question au mod\u00e8le suffit \u00e0 la faire para\u00eetre \u00e0 la
   * prochaine saisie ; les r\u00e9ponses d\u00e9j\u00e0 recueillies gardent leur forme.
   * Le mod\u00e8le de satisfaction amorc\u00e9 est une PROPOSITION \u2014 aucun document
   * de cadrage ne fixe de questionnaire \u2014 et les \u00e9crans le disent.
   * ======================================================================== */
  var TYPES_QUESTION = [
    { id: 'note', label: 'Note de 1 \u00e0 5' },
    { id: 'choix', label: 'Choix dans une liste' },
    { id: 'texte', label: 'R\u00e9ponse libre' },
  ];
  var CANAUX_ENQUETE = ['Au guichet', '\u00c0 la sortie', 'Par t\u00e9l\u00e9phone'];
  /* Le canal des r\u00e9ponses venues d'un LIEN PARTAG\u00c9. Il n'est pas
     s\u00e9lectionnable \u00e0 la main : c'est la page publique qui le pose, et
     c'est pr\u00e9cis\u00e9ment ce qui permettra de comparer plus tard ce que
     disent les r\u00e9ponses recueillies au guichet et celles remplies seul sur
     un t\u00e9l\u00e9phone \u2014 souvent la comparaison la plus instructive. */
  var CANAL_PUBLIC = 'Lien public';

  function colEnquetes() {
    return S.collection('enquetes', { module: 'M13', entite: 'mod\u00e8le d\u2019enqu\u00eate', prefix: 'ENQ' });
  }
  function colReponses() {
    return S.collection('reponsesEnquetes', { module: 'M13', entite: 'r\u00e9ponse d\u2019enqu\u00eate', prefix: 'REP' });
  }
  function colJetons() {
    return S.collection('jetonsEnquete', { module: 'M13', entite: 'lien de partage', prefix: 'JET' });
  }

  function amorcerEnquetes() {
    var col = colEnquetes();
    if (col.all().length) return;
    var rnd = C.seeded(1009);
    col.all().push({
      id: 'ENQ0001', statut: 'actif',
      reference: 'ENQ-SAT', titre: 'Satisfaction des patients',
      description: 'Recueil \u00e0 la sortie \u2014 accueil, attente, soins, recommandation.',
      /* Propos\u00e9 faute de questionnaire dans les documents de cadrage, puis
         VALID\u00c9 par la Direction le 01/09/2026 (vague 49). */
      aValider: false, valideLe: '2026-09-01', validePar: 'Direction',
      source: 'Propos\u00e9 (aucun questionnaire aux documents de cadrage) ; valid\u00e9 par la Direction le 01/09/2026.',
      questions: [
        { code: 'Q_ACCUEIL', libelle: 'Qualit\u00e9 de l\u2019accueil', type: 'note' },
        { code: 'Q_ATTENTE', libelle: 'Temps d\u2019attente ressenti', type: 'note' },
        { code: 'Q_PROPRETE', libelle: 'Propret\u00e9 des locaux', type: 'note' },
        { code: 'Q_SOINS', libelle: 'Qualit\u00e9 des soins re\u00e7us', type: 'note' },
        { code: 'Q_RECO', libelle: 'Recommanderiez-vous la clinique ?', type: 'choix',
          options: ['Oui, sans h\u00e9siter', 'Plut\u00f4t oui', 'Plut\u00f4t non', 'Non'] },
        { code: 'Q_LIBRE', libelle: 'Ce que nous pourrions am\u00e9liorer', type: 'texte' },
      ],
      creeLe: '2026-08-01',
    });
    /* Jeu de d\u00e9monstration : des r\u00e9ponses pour que les \u00e9crans montrent
       leur usage \u2014 marqu\u00e9es comme telles par leur canal de saisie. */
    var rep = colReponses();
    for (var k = 0; k < 26; k++) {
      var reponses = {
        Q_ACCUEIL: C.between(rnd, 3, 5), Q_ATTENTE: C.between(rnd, 2, 5),
        Q_PROPRETE: C.between(rnd, 3, 5), Q_SOINS: C.between(rnd, 3, 5),
        Q_RECO: C.pick(rnd, ['Oui, sans h\u00e9siter', 'Oui, sans h\u00e9siter', 'Plut\u00f4t oui', 'Plut\u00f4t oui', 'Plut\u00f4t non']),
        Q_LIBRE: rnd() > 0.7 ? C.pick(rnd, ['R\u00e9duire l\u2019attente \u00e0 la caisse.',
          'Tr\u00e8s satisfaite des sages-femmes.', 'Mieux indiquer la salle de pr\u00e9l\u00e8vement.',
          'Rien \u00e0 signaler.']) : '',
      };
      rep.all().push({
        id: 'REP' + C.pad(k + 1, 4), statut: 'actif',
        enqueteId: 'ENQ0001',
        date: C.iso(C.addDays(new Date(2026, 7, 16), -C.between(rnd, 0, 45))),
        canal: C.pick(rnd, CANAUX_ENQUETE),
        reponses: reponses,
        saisiPar: 'Jeu de d\u00e9monstration',
      });
    }
    S.save();
  }

  /** L'\u00e9diteur de questions \u2014 le c\u0153ur du g\u00e9n\u00e9rateur : une liste
      modifiable, comme les lignes d'une d\u00e9pense. */
  function editeurQuestions(initiales) {
    var questions = (initiales || []).map(function (q) { return Object.assign({}, q); });
    var bloc2 = el('div.space-y-2');
    var liste = el('div.space-y-1\.5');
    bloc2.appendChild(liste);

    function peindre() {
      C.clear(liste);
      if (!questions.length) {
        liste.appendChild(el('p.text-xs.text-slate-400', { text: 'Aucune question \u2014 en ajouter au moins une.' }));
      }
      questions.forEach(function (q, idx) {
        var ligne = el('div.flex.items-center.gap-2.rounded-lg.border.border-slate-200.px-3.py-1\.5');
        var ty = TYPES_QUESTION.filter(function (x) { return x.id === q.type; })[0];
        ligne.appendChild(el('div.min-w-0.flex-1', null, [
          el('p.truncate.text-sm.text-slate-800', { text: (idx + 1) + '. ' + q.libelle }),
          el('p.text-xs.text-slate-400', { text: (ty ? ty.label : q.type)
            + (q.options && q.options.length ? ' \u2014 ' + q.options.join(' \u00b7 ') : '') }),
        ]));
        ligne.appendChild(K.iconBtn('pencil', 'Modifier la question', function () { editerQ(q, idx); }));
        ligne.appendChild(K.iconBtn('trash-2', 'Retirer la question', function () {
          questions.splice(idx, 1); peindre();
        }));
        liste.appendChild(ligne);
      });
      var ajout = K.btn('Ajouter une question', { size: 'sm', icon: 'plus',
        onclick: function () { editerQ(null, -1); } });
      liste.appendChild(ajout);
      U.icons(liste);
    }

    function editerQ(q, idx) {
      var f2 = U.form([
        { name: 'libelle', label: 'Question', type: 'text', required: true, col: 'full' },
        { name: 'type', label: 'Type de r\u00e9ponse', type: 'select', required: true,
          options: TYPES_QUESTION.map(function (x) { return { value: x.id, label: x.label }; }) },
        { name: 'optionsTexte', label: 'Choix propos\u00e9s (s\u00e9par\u00e9s par |)', type: 'text', col: 'full',
          hint: 'Pour une question \u00e0 choix seulement.' },
      ], q ? { libelle: q.libelle, type: q.type, optionsTexte: (q.options || []).join('|') } : { type: 'note' });
      var m2 = U.modal({
        title: q ? 'Modifier la question' : 'Nouvelle question', size: 'md', body: f2,
        footer: [
          K.btn('Annuler', { onclick: function () { m2.close(); } }),
          K.btn(q ? 'Enregistrer' : 'Ajouter', {
            variant: 'primary', icon: q ? 'save' : 'plus',
            onclick: function () {
              var v2 = f2.collect();
              if (!v2) return;
              if (v2.type === 'choix' && !String(v2.optionsTexte || '').trim()) {
                U.toast('Une question \u00e0 choix a besoin de ses choix.', { type: 'error' });
                return;
              }
              var neuf = {
                code: q ? q.code : 'Q' + Date.now().toString(36).toUpperCase(),
                libelle: v2.libelle, type: v2.type,
                options: v2.type === 'choix'
                  ? String(v2.optionsTexte).split('|').map(function (x) { return x.trim(); }).filter(Boolean)
                  : null,
              };
              if (q) questions[idx] = neuf; else questions.push(neuf);
              m2.close(); peindre();
            },
          }),
        ],
      });
    }

    peindre();
    return { bloc: bloc2, lire: function () { return questions.slice(); } };
  }

  /* --------------------------------------------------------------------------
   * LE G\u00c9N\u00c9RATEUR DE FORMULAIRE \u2014 UN SEUL MOTEUR, DEUX HABILLAGES
   * --------------------------------------------------------------------------
   * La saisie interne (modale au guichet) et la page publique partag\u00e9e
   * naissent du M\u00caME mod\u00e8le par la M\u00caME fonction. \u00c9crire un second
   * g\u00e9n\u00e9rateur pour le public aurait \u00e9t\u00e9 le plus s\u00fbr moyen de les faire
   * diverger \u00e0 la premi\u00e8re question ajout\u00e9e : on aurait ajout\u00e9 la question
   * au mod\u00e8le, elle serait apparue au guichet et pas sur le lien, sans que
   * rien ne le signale.
   * ----------------------------------------------------------------------- */
  function champsDepuisModele(enq, opts) {
    /* `pleineLargeur` ne touche QUE la mise en page : les questions, leurs
       types et leurs contraintes restent rigoureusement les m\u00eames des deux
       c\u00f4t\u00e9s. Un patient r\u00e9pond sur un t\u00e9l\u00e9phone, une seule colonne se lit
       mieux ; l'agent, lui, saisit vite sur deux colonnes. */
    var pleine = opts && opts.pleineLargeur;
    return (enq.questions || []).map(function (q) {
      var col = pleine ? 'full' : null;
      if (q.type === 'note') {
        return { name: q.code, label: q.libelle + ' (1 \u00e0 5)', type: 'select', required: true, col: col,
          options: [1, 2, 3, 4, 5].map(function (n) { return { value: String(n), label: String(n) }; }) };
      }
      if (q.type === 'choix') {
        return { name: q.code, label: q.libelle, type: 'select', required: true, col: col,
          options: (q.options || []).map(function (o) { return { value: o, label: o }; }) };
      }
      return { name: q.code, label: q.libelle, type: 'textarea', rows: 2, col: col };
    });
  }

  /** L'\u00e9criture d'une r\u00e9ponse \u2014 un seul chemin, quel que soit le canal. */
  function enregistrerReponse(enq, valeurs, opts) {
    var o = opts || {};
    var v = Object.assign({}, valeurs);
    (enq.questions || []).forEach(function (q) {
      if (q.type === 'note' && v[q.code] != null) v[q.code] = Number(v[q.code]);
    });
    return colReponses().insert({
      enqueteId: enq.id, date: C.iso(new Date()),
      canal: o.canal || CANAUX_ENQUETE[0],
      reponses: v,
      saisiPar: o.saisiPar || S.currentUser(),
      /* Le jeton est trac\u00e9 pour pouvoir COMPTER par lien et r\u00e9voquer ;
         il n'identifie pas le r\u00e9pondant \u2014 c'est le lien, pas la personne. */
      jetonId: o.jetonId || null,
    });
  }

  /* ==========================================================================
   * PARTAGER UNE FICHE D'ENQU\u00caTE \u00c0 UN TIERS
   * --------------------------------------------------------------------------
   * CE QUI COMMANDE TOUT : un lien suppose d'\u00eatre JOIGNABLE. Le serveur est
   * local, sans port ouvert sur Internet \u2014 un lien envoy\u00e9 par SMS \u00e0 un
   * patient rentr\u00e9 chez lui ne m\u00e8nerait nulle part. Trois situations, et
   * l'\u00e9cran les distingue :
   *   - le tiers est DANS la clinique (salle d'attente, Wi-Fi) : le lien du
   *     r\u00e9seau local ou le QR affich\u00e9 fonctionnent, et ne co\u00fbtent rien ;
   *   - il remplit sur une TABLETTE de la clinique : aucun lien n'est m\u00eame
   *     n\u00e9cessaire, z\u00e9ro surface expos\u00e9e ;
   *   - il r\u00e9pond de CHEZ LUI : cela exige une surface publique sur
   *     Internet, donc un R\u00c9-ARBITRAGE D'ARCHITECTURE. On ne l'improvise pas
   *     en ouvrant le serveur de la clinique.
   * Les deux premiers cas sont couverts ici ; le troisi\u00e8me est nomm\u00e9, chiffr\u00e9
   * dans ses cons\u00e9quences, et laiss\u00e9 \u00e0 la d\u00e9cision.
   *
   * L'ADRESSE PORTE UN JETON, JAMAIS UN IDENTIFIANT : sans cela, on \u00e9num\u00e8re
   * les enqu\u00eates en changeant un num\u00e9ro. Le jeton est dat\u00e9 et r\u00e9vocable \u2014 un
   * lien qui vit ind\u00e9finiment collecte des r\u00e9ponses des mois apr\u00e8s la
   * cl\u00f4ture, et personne ne s'en aper\u00e7oit.
   * ======================================================================== */
  function jetonOuvert(j, aLaDate) {
    if (!j || j.statut === 'archive') return false;
    if (j.revoqueLe) return false;
    return !j.expireLe || j.expireLe >= C.iso(aLaDate || new Date());
  }
  function etatJeton(j) {
    if (!j) return { label: 'inconnu', tone: 'neutral' };
    if (j.revoqueLe) return { label: 'R\u00e9voqu\u00e9 le ' + C.dateFR(j.revoqueLe), tone: 'danger' };
    if (!jetonOuvert(j)) return { label: 'Expir\u00e9 le ' + C.dateFR(j.expireLe), tone: 'warning' };
    return { label: 'Ouvert', tone: 'success' };
  }
  function jetonParCode(code) {
    if (!code) return null;
    return colJetons().all().filter(function (j) { return j.jeton === code; })[0] || null;
  }
  /** L'adresse de la page publique \u2014 construite depuis la page courante. */
  function lienDuJeton(code) {
    try {
      return new URL('enquete-publique' + N.EXT + '?jeton=' + encodeURIComponent(code), global.location.href).href;
    } catch (e) {
      return 'pages/enquete-publique' + N.EXT + '?jeton=' + code;
    }
  }

  /** Le formulaire de saisie d'une r\u00e9ponse NA\u00ceT du mod\u00e8le. */
  function saisirReponse(enq, apres) {
    var champs = [
      { name: '_canal', label: 'Canal de recueil', type: 'select', required: true,
        options: CANAUX_ENQUETE.map(function (x) { return { value: x, label: x }; }) },
    ].concat(champsDepuisModele(enq));
    var f2 = U.form(champs, {});
    var m2 = U.modal({
      title: 'Recueillir une r\u00e9ponse \u2014 ' + enq.titre,
      subtitle: 'Le formulaire est engendr\u00e9 depuis le mod\u00e8le : modifier le mod\u00e8le suffit \u00e0 le changer.',
      size: 'lg', body: f2,
      footer: [
        K.btn('Annuler', { onclick: function () { m2.close(); } }),
        K.btn('Enregistrer la r\u00e9ponse', {
          variant: 'primary', icon: 'check',
          onclick: function () {
            var v2 = f2.collect();
            if (!v2) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
            var canal = v2._canal; delete v2._canal;
            enregistrerReponse(enq, v2, { canal: canal });
            m2.close();
            if (apres) apres();
            U.toast('R\u00e9ponse recueillie.', { type: 'success' });
          },
        }),
      ],
    });
  }

  global.SIGH.screen('adm-enquetes', {
    title: 'Enqu\u00eates & questionnaires',
    description: 'Le g\u00e9n\u00e9rateur de questionnaires : le formulaire de saisie na\u00eet du mod\u00e8le, comme sur KoboCollect.',
    regle: 'Le questionnaire est une <strong>donn\u00e9e</strong> : ajouter une question au mod\u00e8le suffit '
      + '\u00e0 la faire para\u00eetre \u00e0 la prochaine saisie \u2014 rien n\u2019est cod\u00e9. Les r\u00e9ponses '
      + 'd\u00e9j\u00e0 recueillies gardent leur forme. Le mod\u00e8le de satisfaction amorc\u00e9 est une '
      + '<strong>proposition</strong> : aucun document de cadrage ne fixe de questionnaire.',
    render: function (root) {
      amorcerEnquetes();
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var rows = colEnquetes().active();
        var reps = colReponses().active();
        var liens = colJetons().active();
        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Mod\u00e8les d\u2019enqu\u00eate', value: C.num(rows.length), icon: 'clipboard-list', tone: 'navy' },
          { label: 'R\u00e9ponses recueillies', value: C.num(reps.length), icon: 'messages-square', tone: 'info' },
          { label: 'Dont par lien partag\u00e9', value: C.num(reps.filter(function (x) { return x.canal === CANAL_PUBLIC; }).length),
            icon: 'link', tone: 'neutral', hint: 'Canal \u00ab ' + CANAL_PUBLIC + ' \u00bb' },
          { label: 'Liens ouverts', value: C.num(liens.filter(function (j) { return jetonOuvert(j); }).length),
            icon: 'share-2', tone: liens.filter(function (j) { return jetonOuvert(j); }).length ? 'warning' : 'neutral',
            hint: 'Dat\u00e9s et r\u00e9vocables' },
          { label: 'Mod\u00e8les \u00e0 valider', value: C.num(rows.filter(function (r) { return r.aValider; }).length),
            icon: 'help-circle', tone: 'warning', hint: 'Propositions \u2014 aucun document ne les fixe' },
        ]));

        vue.appendChild(U.tabs([
          { id: 'modeles', label: 'Mod\u00e8les (' + rows.length + ')', render: function () { return tableModeles(rows); } },
          { id: 'partage', label: 'Liens de partage (' + liens.length + ')', render: function () { return tablePartage(liens); } },
        ]));
        U.icons(vue);
      }

      function tableModeles(rows) {
        return U.dataTable({
          title: 'Mod\u00e8les', rows: rows, pageSize: 8, exportName: 'enquetes',
          emptyMessage: 'Aucun mod\u00e8le d\u2019enqu\u00eate.',
          actions: [K.commande('Nouveau mod\u00e8le', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { editerModele(null); },
          })].filter(Boolean),
          columns: [
            { key: 'titre', label: 'Enqu\u00eate', render: function (r) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.titre }),
                el('p.text-xs.text-slate-400', { text: r.description || '' }),
              ]);
            } },
            { key: 'questions', label: 'Questions', align: 'right',
              value: function (r) { return (r.questions || []).length; } },
            { key: 'reponses', label: 'R\u00e9ponses', align: 'right',
              value: function (r) { return colReponses().active().filter(function (x) { return x.enqueteId === r.id; }).length; } },
            { key: 'aValider', label: 'Statut', render: function (r) {
              return r.aValider ? U.badge('Proposition \u00e0 valider', 'warning') : U.badge('Valid\u00e9', 'success');
            } },
          ],
          rowActions: function (r) {
            var actes = [
              K.commande('Recueillir', { size: 'sm', variant: 'primary', icon: 'plus',
                onclick: function () { saisirReponse(r, afficher); } }),
              K.iconBtn('eye', 'Voir les r\u00e9ponses', function () { voirReponses(r); }),
            ];
            var partager = K.commandeIcone('share-2', 'Partager \u00e0 un tiers', function () { ouvrirPartage(r); });
            if (partager) actes.push(partager);
            var mod = K.commandeIcone('pencil', 'Modifier le mod\u00e8le', function () { editerModele(r); });
            if (mod) actes.push(mod);
            return actes.filter(Boolean);
          },
        });
      }

      function tablePartage(liens) {
        var bloc = el('div.space-y-3');
        bloc.appendChild(K.note('<strong>Un lien suppose d’être joignable.</strong> Le serveur de la '
          + 'clinique est local, sans port ouvert sur Internet : un lien fonctionne pour qui est '
          + '<strong>dans la clinique</strong> — salle d’attente, Wi-Fi, ou tablette posée à la sortie, '
          + 'qui ne demande même pas de lien. Faire répondre un patient <strong>depuis chez lui</strong> '
          + 'exige une surface publique sur Internet : c’est un <strong>ré-arbitrage d’architecture</strong>, '
          + 'pas une option à cocher — et surtout pas l’ouverture du serveur de la clinique.',
        { tone: 'warning', icon: 'wifi' }));
        bloc.appendChild(K.note('Dans le prototype, chaque poste a son <strong>propre stockage</strong> : '
          + 'un lien ouvert sur une autre machine y afficherait bien le formulaire, mais ses réponses '
          + 'ne reviendraient jamais ici. Le geste se <strong>maquette</strong> — jeton, page publique, '
          + 'QR — la <strong>collecte réelle appartient à la version web</strong>.',
        { tone: 'info', icon: 'info' }));

        bloc.appendChild(U.dataTable({
          title: 'Liens de partage', rows: C.sortBy(liens, 'creeLe').reverse(), pageSize: 8,
          exportName: 'liens-enquete',
          emptyMessage: 'Aucun lien de partage — en ouvrir un depuis l’onglet « Modèles ».',
          columns: [
            { key: 'enqueteTitre', label: 'Enquête' },
            { key: 'jeton', label: 'Jeton', render: function (j) {
              return el('p.font-mono.text-xs.text-slate-500', { text: j.jeton.slice(0, 8) + '…' });
            } },
            { key: 'anonyme', label: 'Recueil', render: function (j) {
              return j.anonyme ? U.badge('Anonyme', 'info') : U.badge('Nominatif', 'warning');
            } },
            { key: 'expireLe', label: 'Expire le', value: function (j) { return C.dateFR(j.expireLe); } },
            { key: 'reponses', label: 'Réponses', align: 'right', value: function (j) {
              return colReponses().active().filter(function (x) { return x.jetonId === j.id; }).length;
            } },
            { key: 'etat', label: 'État', render: function (j) {
              var e = etatJeton(j); return U.badge(e.label, e.tone);
            } },
          ],
          rowActions: function (j) {
            var actes = [K.iconBtn('qr-code', 'Afficher le lien et le QR', function () { montrerLien(j); })];
            if (jetonOuvert(j)) {
              var rev = K.commandeIcone('ban', 'Révoquer le lien', function () { revoquer(j); },
                { droit: 'annuler', variant: 'ghost' });
              if (rev) actes.push(rev);
            }
            return actes;
          },
        }));
        return bloc;
      }

      function ouvrirPartage(enq) {
        var f2 = U.form([
          { name: 'anonyme', label: 'Recueil', type: 'select', required: true, col: 'full',
            options: [
              { value: 'oui', label: 'Anonyme — aucun lien vers un dossier patient' },
              { value: 'non', label: 'Nominatif — le répondant se nomme, et le formulaire le dit' },
            ],
            hint: 'Décision explicite : si l’enquête est annoncée anonyme, on ne stocke ni identité ni '
              + 'lien vers le dossier — sinon « anonyme » est un mensonge.' },
          { name: 'usage', label: 'Où le tiers répond-il ?', type: 'select', required: true,
            options: [
              { value: 'salle', label: 'Dans la clinique — QR affiché ou imprimé' },
              { value: 'tablette', label: 'Sur une tablette de la clinique (mode kiosque)' },
              { value: 'reseau', label: 'Sur le réseau local — lien communiqué' },
            ] },
          { name: 'expireLe', label: 'Le lien expire le', type: 'date', required: true,
            hint: 'Un lien sans terme collecte des réponses des mois après la clôture.' },
          { name: 'note', label: 'Note interne', type: 'text', col: 'full' },
        ], { anonyme: 'oui', usage: 'salle', expireLe: C.iso(C.addDays(new Date(), 30)) });

        var m2 = U.modal({
          title: 'Partager — ' + enq.titre,
          subtitle: 'Le lien porte un jeton tiré au hasard, jamais l’identifiant de l’enquête.',
          size: 'lg',
          body: el('div.space-y-3', null, [
            f2,
            K.note('<strong>Aucune donnée médicale sur une page publique.</strong> Une enquête de '
              + 'satisfaction interroge l’accueil, l’attente, la propreté, la clarté des explications — '
              + 'jamais le diagnostic ni le motif de venue. Un formulaire qui rappellerait « votre '
              + 'consultation du 3 septembre en gynécologie » exposerait le patient à quiconque regarde '
              + 'son écran.', { tone: 'danger', icon: 'shield-alert' }),
            K.note('La page publique ne porte <strong>ni ruban, ni recherche, ni session, ni fil '
              + 'd’Ariane</strong> : une page d’enquête qui afficherait la coquille de l’application '
              + 'serait une porte.', { tone: 'info', icon: 'lock' }),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m2.close(); } }),
            K.btn('Ouvrir le lien', {
              variant: 'primary', icon: 'share-2',
              onclick: function () {
                var v2 = f2.collect();
                if (!v2) return;
                var res = colJetons().insert({
                  jeton: global.SIGH.parcours.jetonEnquete(),
                  enqueteId: enq.id, enqueteTitre: enq.titre,
                  anonyme: v2.anonyme === 'oui', usage: v2.usage,
                  creeLe: C.iso(new Date()), expireLe: v2.expireLe,
                  revoqueLe: null, note: v2.note || null,
                  ouvertPar: S.currentUser(),
                });
                m2.close(); afficher();
                montrerLien(res.record);
              },
            }),
          ],
        });
      }

      function montrerLien(j) {
        var lien = lienDuJeton(j.jeton);
        var e = etatJeton(j);
        var champ = el('input.input.font-mono.text-xs', { type: 'text', value: lien, readonly: true,
          'aria-label': 'Adresse du formulaire' });
        var corps = el('div.space-y-3', null, [
          el('div', null, [U.badge(e.label, e.tone)]),
          el('div', null, [
            el('label.label', { text: 'Adresse à communiquer' }), champ,
            el('p.mt-1.text-xs.text-slate-500', {
              text: 'En exploitation, c’est l’adresse du serveur sur le réseau de la clinique qu’il faut '
                + 'communiquer (http://<serveur>/…) — celle-ci est celle du poste courant.',
            }),
          ]),
          U.card('À afficher en salle d’attente', el('div.flex.flex-wrap.items-center.gap-4', null, [
            C.qr(lien, { taille: 180, marge: 3, alt: 'Code QR du formulaire' }),
            el('div.min-w-0.flex-1', null, [
              el('p.text-sm.text-slate-700', { text: 'Le patient scanne avec son téléphone et remplit '
                + 'sur place. C’est là qu’on obtient des réponses : à chaud, avant de partir.' }),
              el('p.mt-2.text-xs.text-slate-500', { text: j.anonyme
                ? 'Recueil ANONYME : ni identité, ni adresse réseau, ni lien vers un dossier patient.'
                : 'Recueil NOMINATIF : le formulaire demande le nom et l’annonce clairement.' }),
            ]),
          ])),
          U.descList([
            ['Enquête', j.enqueteTitre],
            ['Ouvert le', C.dateFR(j.creeLe) + ' par ' + (j.ouvertPar || '—')],
            ['Expire le', C.dateFR(j.expireLe)],
            ['Réponses reçues', C.num(colReponses().active().filter(function (x) { return x.jetonId === j.id; }).length)],
            ['Note interne', j.note || '—'],
          ]),
        ]);
        var d = U.drawer({
          title: 'Lien de partage', subtitle: j.enqueteTitre, body: corps, width: 'max-w-2xl',
          footer: [
            K.btn('Ouvrir la page publique', { icon: 'external-link',
              onclick: function () { global.open(lien, '_blank'); } }),
            K.btn('Copier l’adresse', {
              variant: 'primary', icon: 'copy',
              onclick: function () {
                champ.select();
                try {
                  document.execCommand('copy');
                  U.toast('Adresse copiée.', { type: 'success' });
                } catch (err) {
                  U.toast('Copie impossible — sélectionner l’adresse à la main.', { type: 'warning' });
                }
              },
            }),
          ],
        });
        return d;
      }

      function revoquer(j) {
        U.confirm({
          title: 'Révoquer ce lien ?',
          message: 'Le formulaire cessera immédiatement de s’ouvrir. Les réponses déjà recueillies '
            + 'sont <strong>conservées</strong> : révoquer ferme la porte, cela n’efface rien.',
          confirmLabel: 'Révoquer', danger: true,
        }).then(function (rep) {
          if (!rep) return;
          var res = colJetons().update(j.id, { revoqueLe: C.iso(new Date()), revoquePar: S.currentUser() });
          afficher();
          U.toast('Lien révoqué.', { type: 'success',
            undo: function () { res.undo(); afficher(); }, undoMessage: 'Révocation annulée.' });
        });
      }

      function editerModele(r) {
        var creation = !r;
        var f2 = U.form([
          { name: 'titre', label: 'Titre de l\u2019enqu\u00eate', type: 'text', required: true, col: 'full' },
          { name: 'description', label: 'Description', type: 'text', col: 'full' },
        ], r || {});
        var ed = editeurQuestions(r ? r.questions : []);
        var m2 = U.modal({
          title: creation ? 'Nouveau mod\u00e8le d\u2019enqu\u00eate' : 'Modifier \u2014 ' + r.titre,
          size: 'lg',
          body: el('div.space-y-3', null, [f2, U.card('Questions', ed.bloc)]),
          footer: [
            K.btn('Annuler', { onclick: function () { m2.close(); } }),
            K.btn(creation ? 'Cr\u00e9er le mod\u00e8le' : 'Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v2 = f2.collect();
                if (!v2) return;
                var qs = ed.lire();
                if (!qs.length) {
                  U.toast('Un questionnaire sans question ne recueille rien.', { type: 'error' });
                  return;
                }
                if (creation) {
                  colEnquetes().insert(Object.assign({}, v2, {
                    reference: C.nextRef('ENQ-', 3), questions: qs,
                    aValider: true, creeLe: C.iso(new Date()),
                    source: 'Cr\u00e9\u00e9 dans l\u2019application \u2014 \u00e0 valider',
                  }));
                } else {
                  colEnquetes().update(r.id, Object.assign({}, v2, { questions: qs }));
                }
                m2.close(); afficher();
                U.toast(creation ? 'Mod\u00e8le cr\u00e9\u00e9.' : 'Mod\u00e8le enregistr\u00e9.', { type: 'success' });
              },
            }),
          ],
        });
      }

      function voirReponses(r) {
        var reps = colReponses().active().filter(function (x) { return x.enqueteId === r.id; });
        U.drawer({
          title: r.titre, subtitle: C.num(reps.length) + ' r\u00e9ponse(s)',
          body: el('div.space-y-3', null, reps.slice(0, 30).map(function (x) {
            return U.card(C.dateFR(x.date) + ' \u2014 ' + (x.canal || ''),
              K.miniTable(['Question', 'R\u00e9ponse'],
                (r.questions || []).map(function (q) {
                  var v2 = (x.reponses || {})[q.code];
                  return [q.libelle, v2 == null || v2 === '' ? '\u2014' : String(v2)];
                })));
          })),
        });
      }
    },
  });

  global.SIGH.screen('adm-satisfaction', {
    title: 'Satisfaction des patients',
    description: 'La lecture de l\u2019enqu\u00eate de satisfaction : notes moyennes par question, recommandation, derniers commentaires.',
    regle: 'Tout est <strong>calcul\u00e9</strong> depuis les r\u00e9ponses recueillies \u2014 le recueil se fait \u00e0 '
      + 'l\u2019\u00e9cran des enqu\u00eates. Le questionnaire, propos\u00e9 faute de document de cadrage, a \u00e9t\u00e9 '
      + '<strong>valid\u00e9 par la Direction le 01/09/2026</strong> ; il reste modifiable \u00e0 l\u2019\u00e9cran des enqu\u00eates.',
    render: function (root) {
      amorcerEnquetes();
      var host = el('div.space-y-4');
      root.appendChild(host);
      var enq = colEnquetes().active().filter(function (r) { return r.reference === 'ENQ-SAT'; })[0]
        || colEnquetes().active()[0];
      if (!enq) {
        host.appendChild(U.empty('Aucune enqu\u00eate de satisfaction \u2014 en cr\u00e9er une \u00e0 l\u2019\u00e9cran des enqu\u00eates.', { icon: 'clipboard-list' }));
        return null;
      }
      var reps = colReponses().active().filter(function (x) { return x.enqueteId === enq.id; });
      var notes = (enq.questions || []).filter(function (q) { return q.type === 'note'; });

      function moyenne(code) {
        var vals = reps.map(function (x) { return Number((x.reponses || {})[code]); })
          .filter(function (n) { return isFinite(n) && n > 0; });
        if (!vals.length) return null;
        return Math.round(vals.reduce(function (n, x) { return n + x; }, 0) / vals.length * 10) / 10;
      }
      var globales = notes.map(function (q) { return moyenne(q.code); }).filter(function (x) { return x != null; });
      var globale = globales.length
        ? Math.round(globales.reduce(function (n, x) { return n + x; }, 0) / globales.length * 10) / 10
        : null;
      var qReco = (enq.questions || []).filter(function (q) { return q.code === 'Q_RECO' || /recommand/i.test(q.libelle); })[0];
      var reco = qReco ? reps.filter(function (x) {
        return /^(oui|plut\u00f4t oui)/i.test(String((x.reponses || {})[qReco.code] || ''));
      }).length : 0;

      host.appendChild(U.kpiGrid([
        { label: 'R\u00e9ponses recueillies', value: C.num(reps.length), icon: 'messages-square', tone: 'navy' },
        { label: 'Note moyenne globale', value: globale == null ? '\u2014' : globale + ' / 5',
          icon: 'star', tone: globale != null && globale >= 4 ? 'success' : 'warning' },
        { label: 'Recommanderaient la clinique', value: reps.length ? C.pct(reco / reps.length * 100) : '\u2014',
          icon: 'thumbs-up', tone: 'info' },
        { label: 'Avec commentaire libre', value: C.num(reps.filter(function (x) {
          return (enq.questions || []).some(function (q) { return q.type === 'texte' && String((x.reponses || {})[q.code] || '').trim(); });
        }).length), icon: 'message-square-text', tone: 'neutral' },
      ]));

      host.appendChild(enq.aValider
        ? K.note('Le questionnaire est une <strong>proposition \u00e0 valider</strong> par la Direction \u2014 '
          + 'aucun document de cadrage n\u2019en fixe le contenu.', { tone: 'warning', icon: 'help-circle' })
        : K.note('Questionnaire <strong>valid\u00e9 par la Direction'
          + (enq.valideLe ? ' le ' + C.dateFR(enq.valideLe) : '') + '</strong>. Les r\u00e9ponses du jeu de '
          + 'd\u00e9monstration restent marqu\u00e9es comme telles par leur champ \u00ab saisi par \u00bb.',
        { tone: 'info', icon: 'check-circle-2' }));

      var libelles = notes.map(function (q) { return q.libelle; });
      host.appendChild(U.card('Note moyenne par question',
        libelles.length
          ? G.barres(libelles, [{ label: 'Moyenne / 5', data: notes.map(function (q) { return moyenne(q.code) || 0; }) }],
            { horizontal: true, height: 220 })
          : U.empty('Aucune question de type note.', { icon: 'star' })));

      var commentaires = [];
      reps.forEach(function (x) {
        (enq.questions || []).forEach(function (q) {
          var v2 = String((x.reponses || {})[q.code] || '').trim();
          if (q.type === 'texte' && v2) commentaires.push({ date: x.date, texte: v2 });
        });
      });
      host.appendChild(U.card('Derniers commentaires',
        commentaires.length
          ? el('div.space-y-2', null, C.sortBy(commentaires, 'date').reverse().slice(0, 8).map(function (x) {
            return el('div.rounded-lg.border.border-slate-200.px-3.py-2', null, [
              el('p.text-sm.text-slate-700', { text: '\u00ab ' + x.texte + ' \u00bb' }),
              el('p.text-xs.text-slate-400', { text: C.dateFR(x.date) }),
            ]);
          }))
          : U.empty('Aucun commentaire libre recueilli.', { icon: 'message-square-text' })));
      host.appendChild(K.source('R\u00e9ponses de l\u2019enqu\u00eate \u00ab ' + enq.titre + ' \u00bb \u2014 recalcul\u00e9 \u00e0 chaque affichage.'));
      U.icons(host);
      return null;
    },
  });


  /* ==========================================================================
   * VAGUE 49 \u2014 LE CENTRE DES VALIDATIONS EN ATTENTE
   * --------------------------------------------------------------------------
   * Un seul \u00e9cran pour r\u00e9pondre \u00e0 \u00ab qu'est-ce qui attend une validation,
   * et de QUI ? \u00bb. Il ORIENTE, il ne valide jamais en masse : la validation
   * est un geste humain, port\u00e9 \u00c0 SON POSTE, par la personne qui engage sa
   * responsabilit\u00e9 (doctrine des deux verrous du laboratoire). Trois
   * familles : les gestes de poste, les r\u00e9f\u00e9rentiels qui attendent un
   * PROFESSIONNEL nomm\u00e9, et ce que la Direction a d\u00e9j\u00e0 valid\u00e9 le 01/09.
   * ======================================================================== */
  global.SIGH.screen('adm-validations', {
    title: 'Validations en attente',
    description: 'Tout ce qui attend une validation, class\u00e9 par poste et par responsable \u2014 avec le chemin vers le geste.',
    regle: 'Cet \u00e9cran <strong>oriente</strong>, il ne valide jamais en masse : la validation est un '
      + '<strong>geste humain, port\u00e9 \u00e0 son poste</strong> \u2014 le biologiste valide au laboratoire, '
      + 'le comptable au journal, la DA sur le bon. Les validations \u00e9crites des professionnels '
      + 'nomm\u00e9s sont <strong>arriv\u00e9es le 01/09/2026</strong> (biologiste, m\u00e9decins, praticiens du '
      + 'bloc) ; ce qui reste en attente est une <strong>donn\u00e9e manquante ou r\u00e9currente</strong>, '
      + 'jamais une signature que la Direction pourrait porter \u00e0 leur place.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var go = global.SIGH.app && global.SIGH.app.go;

      function c(nom) { return S.collection(nom).active(); }
      var AUJ2 = C.iso(new Date());

      var files = [
        { libelle: 'R\u00e9sultats \u00e0 valider biologiquement', poste: 'Biologiste m\u00e9dical',
          compte: c('demandesAnalyses').filter(function (d) { return d.etatAnalyse === 'valide_technique'; }).length,
          ecran: 'm5-resultats', icone: 'shield-check' },
        { libelle: '\u00c9critures comptables en brouillon', poste: 'Comptable',
          compte: c('ecritures').filter(function (e) { return e.statut === 'brouillon'; }).length,
          ecran: 'm12-ecritures', icone: 'pencil-line' },
        /* Les bons et commandes sont amorc\u00e9s par les \u00e9crans M7 : sur un
           poste qui ne les a jamais ouverts, la collection est VIDE et
           \u00ab 0 \u00bb serait un mensonge (doctrine vague 31 : un compteur faux
           dans ce sens est plus dangereux qu'absent). On l'annonce. */
        { libelle: 'Bons de besoins en circuit de validation', poste: 'Directrice Administrative',
          compte: S.collection('besoins').all().length
            ? c('besoins').filter(function (b) { return ['soumis', 'controle_stock', 'validation_da'].indexOf(b.etape) !== -1; }).length
            : null,
          nonAmorce: !S.collection('besoins').all().length,
          ecran: 'm7-besoins', icone: 'clipboard-list' },
        { libelle: 'Commandes fournisseur \u00e0 valider (RG-04)', poste: 'Directrice Administrative',
          compte: S.collection('commandes').all().length
            ? c('commandes').filter(function (x) { return x.statutCommande === 'attente_validation'; }).length
            : null,
          nonAmorce: !S.collection('commandes').all().length,
          ecran: 'm7-commandes', icone: 'shopping-cart' },
        { libelle: 'Factures \u00e0 normaliser MECeF', poste: 'Caisse / fiscalit\u00e9',
          compte: c('factures').filter(function (fa) { return fa.statutMecef === 'en_attente' && fa.numeroMecef; }).length,
          ecran: 'mecef-factures', icone: 'file-badge' },
        { libelle: 'Comptes rendus d\u2019imagerie \u00e0 rendre', poste: '\u00c9chographiste',
          compte: c('resultatsImagerie').filter(function (r) { return r.statut !== 'rendu'; }).length,
          ecran: 'm2-imagerie-demandes', icone: 'scan-line' },
        { libelle: '\u00c9ch\u00e9ances fiscales d\u00e9pass\u00e9es', poste: 'Comptable / DAF',
          compte: c('echeancesFiscales').filter(function (e) { return !e.paye && e.echeance < AUJ2; }).length,
          ecran: 'm12-echeances', icone: 'calendar-clock' },
      ];

      var professionnels = [
        /* Les validations \u00e9crites du 01/09 sont ARRIV\u00c9ES (vague 51) ; ce qui
           reste ici n'attend PAS une signature : ce sont des DONN\u00c9ES
           physiquement manquantes ou structurellement r\u00e9currentes. */
        { libelle: 'Parc technique \u2014 fiches \u00e0 compl\u00e9ter', qui: 'Ing\u00e9nierie / administration',
          compte: c('materiel').filter(function (m) { return m.aCompleter; }).length,
          ecran: 'm13-maintenance',
          motif: 'Marque, n\u00b0 de s\u00e9rie et mise en service MANQUENT physiquement : une validation ne cr\u00e9e '
            + 'pas un num\u00e9ro de s\u00e9rie \u2014 le marquage dispara\u00eet par la SAISIE, jamais par une signature.' },
        { libelle: 'Plages de r\u00e9f\u00e9rence par lot de r\u00e9actif', qui: 'Biologiste m\u00e9dical',
          compte: c('plagesReactif').length,
          ecran: 'm5-valeurs-reference',
          motif: 'Structurel : chaque NOUVEAU lot porte ses bornes \u2014 la notice du r\u00e9actif fait foi, '
            + '\u00e0 chaque arrivage.' },
      ];

      /* QUATRI\u00c8ME FAMILLE \u2014 ce qui attend un ARBITRAGE de la Direction
         elle-m\u00eame, et non la signature d'un professionnel nomm\u00e9. La
         distinction n'est pas cosm\u00e9tique : la Direction ne peut pas signer \u00e0
         la place du biologiste, mais elle est seule \u00e0 pouvoir fixer la dur\u00e9e
         de validit\u00e9 d'un badge. Les ranger ensemble ferait attendre l'un
         pour l'autre. */
      var arbitrages = [
        { libelle: 'Dur\u00e9e de validit\u00e9 d\u2019un badge du personnel',
          attente: '24 mois (valeur d\u2019attente)', ecran: 'm10-badges',
          motif: 'Aucun document de cadrage ne la fixe. Peut aussi suivre la dur\u00e9e du contrat.' },
        { libelle: 'Format du num\u00e9ro de s\u00e9rie des badges',
          attente: 'BDG-NNNNN-AAAA', ecran: 'm10-badges',
          motif: 'Propos\u00e9 par analogie avec les pi\u00e8ces certifiantes (s\u00e9rie annuelle). La clinique tient '
            + 'peut-\u00eatre d\u00e9j\u00e0 une num\u00e9rotation qu\u2019il faudrait reprendre.' },
        { libelle: 'Mentions port\u00e9es au verso du badge',
          attente: 'Restitution, perte, propri\u00e9t\u00e9', ecran: 'm10-badges-modeles',
          motif: 'Elles engagent la clinique envers le porteur : c\u2019est \u00e0 la Direction de les arr\u00eater.' },
        { libelle: 'Le badge sert-il de support de POINTAGE ?',
          attente: 'Non \u2014 d\u00e9cision non prise', ecran: 'm10-badges',
          motif: 'S\u2019il pointe, il se relie au registre des pr\u00e9sences et la conception change : lecteur \u00e0 '
            + 'l\u2019entr\u00e9e, horodatage, traitement des oublis de badge.' },
      ];

      var validees = [
        { libelle: 'Tarifs des actes (valeurs d\u2019attente du 20/08)', detail: 'ARR\u00caT\u00c9S par la Direction \u2014 plus aucun tarif provisoire au catalogue vivant ; la semence garde le marquage historique.' },
        { libelle: 'Valorisation des 34 r\u00e9f\u00e9rences SAGE', detail: 'M\u00e9diane de cat\u00e9gorie CONFIRM\u00c9E ; r\u00e9visable \u00e0 la premi\u00e8re facture fournisseur (surcouche trac\u00e9e).' },
        { libelle: 'Les quatre groupes d\u2019articles', detail: 'CONFIRM\u00c9S \u2014 ils cessent d\u2019\u00eatre une proposition.' },
        { libelle: 'Questionnaire de satisfaction', detail: 'VALID\u00c9 \u2014 le recueil peut s\u2019appuyer dessus.' },
        { libelle: 'Bornes suppl\u00e9\u00e9es du laboratoire (61 variables)', detail: 'Validation \u00e9crite du BIOLOGISTE M\u00c9DICAL (01/09) \u2014 badge \u00ab Valid\u00e9e \u00bb, jamais confondu avec \u00ab Document\u00e9e \u00bb.' },
        { libelle: 'Liste des 55 pathologies', detail: 'Arr\u00eat\u00e9e par les M\u00c9DECINS (tableau de morbidit\u00e9, 01/09) \u2014 elle reste administrable.' },
        { libelle: 'Check-listes du bloc, \u00e9chelles ASA/Mallampati, techniques', detail: 'Arr\u00eat\u00e9es par les PRATICIENS DU BLOC (01/09) \u2014 la provenance propos\u00e9e reste dite.' },
        { libelle: 'Seuils d\u2019alerte du stock', detail: 'Seuils propos\u00e9s (20 % du stock repris) CONFIRM\u00c9S \u2014 r\u00e9visables r\u00e9f\u00e9rence par r\u00e9f\u00e9rence.' },
        { libelle: 'Rapprochement groupe \u2194 centre de co\u00fbts', detail: 'ARR\u00caT\u00c9 \u2014 b\u00e9n\u00e9fice brut par groupe affich\u00e9, charges transverses non ventil\u00e9es (dit).' },
      ];

      var totalGestes = files.reduce(function (n, x) { return n + (x.compte || 0); }, 0);
      host.appendChild(U.kpiGrid([
        { label: 'Gestes de validation en attente', value: C.num(totalGestes), icon: 'list-checks',
          tone: totalGestes ? 'warning' : 'success' },
        { label: 'Files concern\u00e9es', value: C.num(files.filter(function (x) { return x.compte > 0; }).length) + ' / ' + files.length,
          icon: 'layout-grid', tone: 'neutral' },
        { label: 'R\u00e9f\u00e9rentiels en attente d\u2019un professionnel', value: C.num(professionnels.filter(function (x) { return x.compte === null || x.compte > 0; }).length),
          icon: 'user-check', tone: 'info' },
        { label: 'Valid\u00e9s par la Direction le 01/09', value: C.num(validees.length), icon: 'check-circle-2', tone: 'success' },
      ]));

      var grille = el('div.grid.gap-3.md:grid-cols-2');
      files.forEach(function (x) {
        var carte = el('div.card');
        carte.appendChild(el('div.card-body.flex.items-center.gap-3', null, [
          el('span.shrink-0.text-navy-600', null, C.icon(x.icone, 'h-6 w-6')),
          el('div.min-w-0.flex-1', null, [
            el('p.text-sm.font-medium.text-slate-800', { text: x.libelle }),
            el('p.text-xs.text-slate-500', { text: x.nonAmorce
              ? 'File non amorc\u00e9e sur ce poste \u2014 ouvrir l\u2019\u00e9cran pour la charger'
              : 'Le geste appartient \u00e0 : ' + x.poste }),
          ]),
          el('span.shrink-0.text-lg.font-semibold.num', {
            class: x.compte ? 'text-warning-700' : 'text-slate-300',
            text: x.compte == null ? '\u2014' : C.num(x.compte),
          }),
          K.btn('Y aller', { size: 'sm', icon: 'arrow-right',
            onclick: function () { if (go) go(x.ecran); } }),
        ]));
        grille.appendChild(carte);
      });
      host.appendChild(U.card('\u00c0 valider \u00c0 SON POSTE \u2014 l\u2019\u00e9cran oriente, le poste valide', grille));

      host.appendChild(U.card('R\u00e9f\u00e9rentiels en attente d\u2019un PROFESSIONNEL nomm\u00e9 \u2014 la Direction ne signe pas \u00e0 sa place',
        el('div.space-y-2', null, professionnels.map(function (x) {
          return el('div.flex.items-start.gap-3.rounded-lg.border.border-slate-200.px-3.py-2', null, [
            el('div.min-w-0.flex-1', null, [
              el('p.text-sm.font-medium.text-slate-800', {
                text: x.libelle + (x.compte != null ? ' \u2014 ' + C.num(x.compte) + ' entr\u00e9e(s)' : ''),
              }),
              el('p.text-xs.text-slate-500', { text: x.qui + ' \u00b7 ' + x.motif }),
            ]),
            K.btn('Ouvrir', { size: 'sm', icon: 'arrow-right',
              onclick: function () { if (go) go(x.ecran); } }),
          ]);
        }))));

      host.appendChild(U.card('En attente d\u2019un ARBITRAGE de la Direction \u2014 elle seule peut trancher',
        el('div.space-y-2', null, arbitrages.map(function (x) {
          return el('div.flex.items-start.gap-3.rounded-lg.border.border-warning-200.bg-warning-50.px-3.py-2', null, [
            el('div.min-w-0.flex-1', null, [
              el('p.text-sm.font-medium.text-slate-800', { text: x.libelle }),
              el('p.text-xs.text-slate-600', { text: 'Valeur d\u2019attente : ' + x.attente + ' \u00b7 ' + x.motif }),
            ]),
            K.btn('Ouvrir', { size: 'sm', icon: 'arrow-right',
              onclick: function () { if (go) go(x.ecran); } }),
          ]);
        }))));

      host.appendChild(U.card('Valid\u00e9es par la DIRECTION le 01/09/2026 (vague 49)',
        K.miniTable(['R\u00e9f\u00e9rentiel', 'D\u00e9cision'],
          validees.map(function (x) { return [x.libelle, x.detail]; }))));

      host.appendChild(K.source('Compt\u00e9 \u00e0 chaque affichage depuis les registres du magasin \u2014 rien n\u2019est fourni.'));
      U.icons(host);
      return null;
    },
  });

  /* ==========================================================================
   * LA PAGE PUBLIQUE D'UNE FICHE D'ENQUÊTE
   * --------------------------------------------------------------------------
   * Elle est ISOLÉE, et c'est tout son intérêt : ni ruban, ni recherche, ni
   * session, ni fil d'Ariane, ni le moindre lien vers le logiciel. Une page
   * d'enquête qui afficherait la coquille de l'application serait une porte —
   * on la tend à des inconnus.
   *
   * Le formulaire naît du MÊME générateur que la saisie interne
   * (`champsDepuisModele`) : un second générateur aurait divergé du premier à
   * la première question ajoutée.
   *
   * SANS JETON VALIDE, ELLE NE MONTRE RIEN — pas même le titre de l'enquête :
   * une page qui dirait « cette enquête est fermée » confirmerait déjà
   * qu'elle existe, et l'on énumérerait les jetons pour cartographier les
   * enquêtes de la clinique.
   * ======================================================================== */
  global.SIGH.screen('enquete-publique', {
    standalone: true,
    render: function (root) {
      var params = new URLSearchParams(global.location.search || '');
      var code = params.get('jeton');
      var jeton = jetonParCode(code);
      var enq = jeton ? colEnquetes().get(jeton.enqueteId) : null;

      var page = el('div.min-h-screen.bg-slate-100.px-4.py-8');
      var carte = el('div.mx-auto.w-full.max-w-2xl.space-y-4');
      page.appendChild(carte);
      root.appendChild(page);

      /* --- Le bandeau d'identité, et RIEN d'autre ------------------------- */
      var base = document.documentElement.getAttribute('data-root') || '';
      var entete = el('div.rounded-2xl.bg-white.px-6.py-5.text-center.shadow-card');
      entete.appendChild(el('img.mx-auto.h-14.w-14.object-contain', {
        src: base + C.BRAND.logo, alt: '',
        onerror: function () { this.style.visibility = 'hidden'; },
      }));
      entete.appendChild(el('p.mt-2.text-lg.font-bold.text-navy-950', { text: 'CLINIQUE NASSIERA TOO' }));
      entete.appendChild(el('p.text-xs.italic.text-navy-700', { text: C.BRAND.slogan }));
      carte.appendChild(entete);

      if (!jeton || !jetonOuvert(jeton) || !enq) {
        /* Une seule et même réponse pour « jeton inconnu », « expiré » et
           « révoqué » : distinguer les trois renseignerait sur ce qui
           existe. */
        carte.appendChild(el('div.rounded-2xl.bg-white.px-6.py-8.text-center.shadow-card', null, [
          el('p.text-base.font-semibold.text-slate-800', { text: 'Ce lien n’est plus valable.' }),
          el('p.mt-2.text-sm.text-slate-500', {
            text: 'Le questionnaire est clos ou l’adresse est incomplète. '
              + 'Vous pouvez vous adresser à l’accueil de la clinique.',
          }),
          el('p.mt-4.text-xs.text-slate-400', { text: 'Tél. ' + C.BRAND.telephones.join(' / ') }),
        ]));
        U.icons(page);
        return null;
      }

      /* --- Le questionnaire ---------------------------------------------- */
      var corps = el('div.rounded-2xl.bg-white.px-6.py-6.shadow-card.space-y-4');
      corps.appendChild(el('h1.text-xl.font-bold.text-slate-900', { text: enq.titre }));
      if (enq.description) {
        corps.appendChild(el('p.text-sm.text-slate-600', { text: enq.description }));
      }
      corps.appendChild(el('div.rounded-lg.px-3.py-2.text-xs', {
        class: jeton.anonyme ? 'bg-success-50 text-success-800' : 'bg-warning-50 text-warning-800',
        text: jeton.anonyme
          ? 'Questionnaire ANONYME : votre réponse n’est reliée ni à votre nom, ni à votre dossier. '
            + 'Aucune question ne porte sur votre santé.'
          : 'Questionnaire NOMINATIF : votre nom sera enregistré avec votre réponse. '
            + 'Aucune question ne porte sur votre santé.',
      }));

      var champs = [];
      if (!jeton.anonyme) {
        champs.push({ name: '_repondant', label: 'Votre nom', type: 'text', required: true, col: 'full' });
      }
      champs = champs.concat(champsDepuisModele(enq, { pleineLargeur: true }));
      var f = U.form(champs, {});
      corps.appendChild(f);

      var envoyer = el('button.btn.btn-primary.btn-lg.w-full', { type: 'button' }, 'Envoyer ma réponse');
      envoyer.addEventListener('click', function () {
        var v = f.collect();
        if (!v) { U.toast('Merci de compléter les réponses attendues.', { type: 'error' }); return; }
        var nom = v._repondant; delete v._repondant;
        enregistrerReponse(enq, v, {
          canal: CANAL_PUBLIC, jetonId: jeton.id,
          /* ANONYME VEUT DIRE ANONYME : ni nom, ni adresse réseau, ni lien
             vers un dossier. Sinon le mot est un mensonge. */
          saisiPar: jeton.anonyme ? 'Réponse anonyme — lien partagé' : (nom || 'Répondant non nommé'),
        });
        C.clear(carte);
        carte.appendChild(entete);
        carte.appendChild(el('div.rounded-2xl.bg-white.px-6.py-10.text-center.shadow-card', null, [
          el('p.text-lg.font-semibold.text-success-700', { text: 'Merci !' }),
          el('p.mt-2.text-sm.text-slate-600', { text: 'Votre réponse a bien été enregistrée.' }),
          el('p.mt-4.text-xs.italic.text-navy-700', { text: C.BRAND.slogan }),
        ]));
        U.icons(page);
      });
      corps.appendChild(envoyer);
      carte.appendChild(corps);

      carte.appendChild(el('p.text-center.text-xs.text-slate-400', {
        text: C.BRAND.nom + ' — ' + C.BRAND.bp,
      }));
      U.icons(page);
      return null;
    },
  });


})(window);