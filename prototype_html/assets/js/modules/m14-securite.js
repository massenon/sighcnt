/* =============================================================================
 * M14 — Sécurité, Utilisateurs & Audit
 * -----------------------------------------------------------------------------
 * CDCT §12 — matrice RBAC, authentification et sessions, protection des
 * données, journal d'audit et sauvegardes.
 * RG-12 — toute action est journalisée : aucune action anonyme n'est permise.
 * RG-13 — cloisonnement des données médicales, financières et RH.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      N = global.SIGH.nav, P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  var NIVEAUX = ['Consultation', 'Création', 'Modification', 'Validation', 'Suppression', 'Impression'];

  function personnel() { return S.collection('personnel').active(); }
  function roleLabel(id) { return N.ROLES[id] ? N.ROLES[id].label : id; }

  /* --- Amorçage des comptes utilisateurs ----------------------------------- */
  function utilisateurs() {
    var col = S.collection('utilisateurs', { module: 'M14', entite: 'Utilisateur' });
    if (col.all().length) return col;
    var rnd = C.seeded(3319);
    /* Les quatorze comptes NOMMÉS par la Direction le 25/08/2026. Cette liste
       est celle des agents qui OUVRENT UNE SESSION — ce n'est pas l'effectif
       soignant : la clinique compte 3 médecins, 3 sages-femmes et 7 infirmiers,
       dont tous n'ont pas de compte. Les confondre fermerait le logiciel à dix
       agents ou ouvrirait des sessions à des agents qui n'en ont pas. */
    var mapping = {
      'BASSONGUI Chabi Séko': 'dm',
      'TAKI Alimatou': 'da',
      'KASSA Augustin': 'comptable',
      'GBEDJI Hervé': 'assistant_comptable',
      'MAMAN Zoukanéri': 'stock',
      'AHOHOU Rodrigue': 'echographiste',
      'BADO BANI A. B. Zoulehath': 'infirmier',
      /* Rectifié le 26/08/2026 : KINNOU reste au laboratoire. */
      'KINNOU A. Ganiou': 'laborantin',
      'OROU YO Edmond': 'reception',
      'IDRISSOU ANIKI Baba-Toundé': 'infirmier',
      'DIEYABIDI Aïssatou': 'caissier',
      'NKOUÉ Jean': 'infirmier',
      'GARBA Yahouza': 'surveillant',
      'BAGRI Elvyre': 'infirmier',
      /* Hors liste remise, mais titulaires d'un poste au dossier RH. */
      'YENI M’PO Florent': 'medecin',
      'TCHANE Nourou': 'ambulancier',
      'OURTCHA Tereyama': 'agentadmin',
      'ISSA Rabiatou': 'agentadmin',
      'TEPA Séraphine': 'aide_soignant',
    };
    personnel().forEach(function (e, i) {
      var role = mapping[e.nomComplet];
      if (!role) {
        role = { medecin: 'medecin', infirmier: 'infirmier', sage_femme: 'infirmier',
          aide_soignant: 'infirmier', tsl: 'laborantin', biomedical: 'biomedical', dispensatrice: 'caissier',
          caissiere: 'caissier', accueil: 'reception', comptable: 'comptable',
          stock: 'stock', securite: 'agentadmin', entretien: 'agentadmin',
          chauffeur: 'ambulancier', direction: 'direction' }[e.fonction] || 'reception';
      }
      var parts = e.nomComplet.split(' ');
      col.all().push({
        id: 'USR' + C.pad(i + 1, 3), statut: 'actif',
        identifiant: (parts[parts.length - 1] || 'u').toLowerCase().charAt(0) + '.' + C.slug(parts[0]),
        nomComplet: e.nomComplet, employeId: e.id, matricule: e.matricule,
        role: role, service: e.service, poste: e.poste,
        actif: rnd() > 0.06,
        mfa: ['dm', 'da', 'direction', 'admin'].indexOf(role) !== -1,
        dernierAcces: C.iso(C.addDays(AUJ, -C.between(rnd, 0, 45))),
        echecs: C.between(rnd, 0, 2),
        creeLe: e.dateEmbauche,
      });
    });
    /* ======================================================================
     * LES COMPTES DES RÔLES CRÉÉS PAR LA DIRECTION
     * ----------------------------------------------------------------------
     * Les rôles existaient depuis le 24/08/2026, les comptes qui les portent
     * non : personne ne pouvait ouvrir une session en aide-soignante ou en
     * assistant de direction, et la matrice des droits ne se vérifiait donc
     * pas à l'usage — seulement sur le papier.
     *
     * L'identifiant suit la convention déjà en place, initiale du nom puis
     * prénom : un agent nouveau n'a pas à retenir une autre règle.
     * ==================================================================== */
    [
      ['TEPA Séraphine', 'aide_soignant', 'Soins infirmiers', 'Aide-soignante — Chef de service'],
      ['AHOHOU Rodrigue', 'echographiste', 'Imagerie / Échographie', 'Échographiste'],
      ['GARBA Yahouza', 'surveillant', 'Soins infirmiers', 'Surveillant'],
      ['GBEDJI Hervé', 'assistant_comptable', 'Direction', 'Assistant de Direction'],
      /* PHASE 2 (31/08/2026) — le chirurgien a un titulaire réel (NS 145 :
         responsable du secteur CHI) ; anesthésiste et assistant comptable
         sont des comptes À POURVOIR, aucun document ne les nomme. */
      ['BASSONGUI Chabi Séko', 'chirurgien', 'Chirurgie', 'Chirurgien généraliste', 'c.bassongui.chi'],
      ['Compte à pourvoir', 'anesthesiste', 'Chirurgie', 'Anesthésiste — Réanimateur', 'demo.anesthesiste'],
      ['Compte à pourvoir', 'aide_comptable', 'Comptabilité', 'Assistant Comptable', 'demo.assist-comptable'],
    ].forEach(function (c, i) {
      var agent = personnel().filter(function (e) { return e.nomComplet === c[0]; })[0];
      var deja = col.all().some(function (u) { return u.nomComplet === c[0] && u.role === c[1]; });
      if (deja) return;
      var parts = c[0].split(' ');
      col.all().push({
        id: 'USRC' + C.pad(i + 1, 2), statut: 'actif',
        identifiant: c[4] || ((parts[parts.length - 1] || 'u').toLowerCase().charAt(0) + '.' + C.slug(parts[0])),
        nomComplet: c[0], employeId: agent ? agent.id : null,
        matricule: agent ? agent.matricule : null,
        role: c[1], service: c[2], poste: c[3],
        actif: true, mfa: false,
        dernierAcces: C.iso(AUJ), echecs: 0,
        creeLe: '2026-08-24',
        note: 'Compte ouvert sur décision de la Direction du 24/08/2026.',
      });
    });

    /* Compte administrateur système dédié */
    col.all().unshift({
      id: 'USR000', statut: 'actif', identifiant: 'admin.systeme',
      nomComplet: 'Administrateur système', role: 'admin', service: 'Administration',
      poste: 'Administrateur système', actif: true, mfa: true,
      dernierAcces: C.iso(AUJ), echecs: 0, creeLe: '2026-01-15',
    });
    S.save();
    return col;
  }

  /* ==========================================================================
   * UTILISATEURS
   * ======================================================================== */
  global.SIGH.screen('m14-utilisateurs', {
    title: 'Utilisateurs',
    description: 'Comptes individuels, rôles attribués, état d’activation et double facteur.',
    regle: '<strong>Aucun compte partagé</strong> : chaque agent dispose d’un identifiant individuel. '
      + 'Le double facteur est exigé pour les profils à privilèges élevés (Administrateur et Direction).',
    render: function (root) {
      utilisateurs();
      return K.crud({
        collection: 'utilisateurs', entite: 'compte', entiteP: 'comptes', module: 'M14',
        defaultSort: 'nomComplet', pageSize: 20,
        source: 'Organigramme de la clinique — un compte par agent.',
        columns: [
          { key: 'identifiant', label: 'Identifiant', nowrap: true, render: function (u) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: u.identifiant }); } },
          {
            key: 'nomComplet', label: 'Utilisateur',
            render: function (u) {
              return el('div.flex.items-center.gap-2', null, [
                el('span.grid.h-7.w-7.shrink-0.place-items-center.rounded-full.bg-slate-100.text-\\[10px\\].font-semibold.text-slate-600', { text: C.initials(u.nomComplet) }),
                el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: u.nomComplet }),
                  el('p.truncate.text-xs.text-slate-400', { text: u.poste || '' }),
                ]),
              ]);
            },
          },
          { key: 'role', label: 'Rôle', text: roleLabel, render: function (u) { return U.badge(roleLabel(u.role), 'navy'); } },
          { key: 'service', label: 'Service' },
          {
            key: 'actif', label: 'État',
            text: function (u) { return u.actif ? 'Actif' : 'Désactivé'; },
            render: function (u) { return u.actif ? U.badge('Actif', 'success') : U.badge('Désactivé', 'danger'); },
          },
          {
            key: 'mfa', label: 'Double facteur',
            text: function (u) { return u.mfa ? 'Activé' : 'Non requis'; },
            render: function (u) { return u.mfa ? U.badge('Activé', 'info') : el('span.text-xs.text-slate-400', { text: 'Non requis' }); },
          },
          {
            key: 'dernierAcces', label: 'Dernier accès', nowrap: true,
            text: function (u) { return C.dateFR(u.dernierAcces); },
            render: function (u) {
              var j = C.daysBetween(u.dernierAcces, AUJ);
              return el('div', null, [
                el('p.text-sm.text-slate-700', { text: C.dateFR(u.dernierAcces) }),
                el('p.text-xs', { class: j > 30 ? 'text-warning-600' : 'text-slate-400', text: 'il y a ' + j + ' j' }),
              ]);
            },
          },
          {
            key: 'echecs', label: 'Échecs', align: 'right',
            render: function (u) { return u.echecs ? el('span.font-semibold.text-warning-600', { text: String(u.echecs) }) : '—'; },
          },
        ],
        fields: function (record) {
          return [
            { name: 'identifiant', label: 'Identifiant de connexion', required: true, help: 'Format usuel : initiale du prénom, point, nom.' },
            {
              name: 'employeId', label: 'Agent rattaché', type: 'select', col: 'full',
              options: C.sortBy(personnel(), 'nomComplet').map(function (e) { return { value: e.id, label: e.matricule + ' — ' + e.nomComplet }; }),
            },
            { name: 'role', label: 'Rôle (RBAC)', type: 'select', required: true, options: Object.keys(N.ROLES).map(function (r) { return { value: r, label: N.ROLES[r].label }; }) },
            { name: 'service', label: 'Service', type: 'select', options: D.SERVICES },
            { name: 'actif', label: 'Compte actif', type: 'checkbox' },
            { name: 'mfa', label: 'Authentification à deux facteurs', type: 'checkbox' },
            /* ================================================================
             * LE MOT DE PASSE — À LA CRÉATION, ET NULLE PART AILLEURS
             * ----------------------------------------------------------------
             * Un compte ouvert sans mot de passe est un compte que n'importe
             * qui endosse : l'identifiant seul ne prouve rien, et RG-12 exige
             * qu'aucune action ne soit anonyme.
             *
             * IL N'APPARAÎT PAS À LA MODIFICATION, et c'est délibéré : changer
             * le mot de passe de quelqu'un n'est pas « corriger une fiche »,
             * c'est un geste distinct qui doit se voir au journal. La
             * réinitialisation a son propre bouton, à la ligne du compte.
             *
             * CE QUI EST SAISI N'EST PAS CE QUI EST GARDÉ : le magasin ne
             * conserve que la DATE de définition et l'obligation de changer
             * à la première connexion. Écrire un mot de passe en clair dans
             * un magasin que l'on exporte, que l'on sauvegarde et que l'on
             * relit à l'écran serait pire que pas de mot de passe du tout.
             * ============================================================== */
            record ? null : { type: 'section', label: 'Mot de passe' },
            record ? null : {
              name: 'motDePasse', label: 'Mot de passe', type: 'password', required: true,
              help: 'Huit caractères au minimum. Il n’est pas conservé en clair : '
                + 'l’agent devra le changer à sa première connexion.',
            },
            record ? null : {
              name: 'motDePasseConfirmation', label: 'Confirmer le mot de passe',
              type: 'password', required: true,
            },
            record ? null : {
              name: 'doitChangerMotDePasse', label: 'Changement obligatoire à la première connexion',
              type: 'checkbox',
            },
          ].filter(Boolean);
        },
        transform: function (v) {
          /* Le secret ne franchit pas cette ligne : on note qu'il a été posé,
             par qui et quand — c'est ce que le journal doit pouvoir montrer —
             et l'on efface la saisie avant l'écriture. */
          if (v.motDePasse) {
            v.motDePasseDefiniLe = new Date().toISOString();
            v.motDePasseDefiniPar = S.currentUser();
            if (v.doitChangerMotDePasse == null) v.doitChangerMotDePasse = true;
          }
          delete v.motDePasse;
          delete v.motDePasseConfirmation;
          var e = personnel().filter(function (x) { return x.id === v.employeId; })[0];
          if (e) { v.nomComplet = e.nomComplet; v.matricule = e.matricule; v.poste = e.poste; v.service = v.service || e.service; }
          if (!v.dernierAcces) v.dernierAcces = C.iso(AUJ);
          if (v.echecs == null) v.echecs = 0;
          if (['dm', 'da', 'direction', 'admin'].indexOf(v.role) !== -1) v.mfa = true;
          return v;
        },
        beforeSave: function (v, record) {
          var existe = S.collection('utilisateurs').all().some(function (u) {
            return u.identifiant === v.identifiant && (!record || u.id !== record.id);
          });
          if (existe) return 'Cet identifiant est déjà attribué : aucun compte ne peut être partagé.';
          if (!record) {
            var mdp = String(v.motDePasse || '');
            if (mdp.length < 8) {
              return 'Le mot de passe doit compter au moins huit caractères.';
            }
            if (mdp !== String(v.motDePasseConfirmation || '')) {
              return 'Les deux mots de passe saisis ne correspondent pas.';
            }
          }
          return null;
        },
        onCreate: function () {
          return { actif: true, mfa: false, role: 'reception', doitChangerMotDePasse: true };
        },
        filters: [
          { name: 'role', label: 'Rôle', options: Object.keys(N.ROLES).map(function (r) { return { value: r, label: N.ROLES[r].label }; }) },
          { name: 'actif', label: 'État', options: [{ value: 'oui', label: 'Actifs' }, { value: 'non', label: 'Désactivés' }], match: function (u, v) { return v === 'oui' ? !!u.actif : !u.actif; } },
          { name: 'service', label: 'Service', options: D.SERVICES },
        ],
        kpis: function (rows) {
          return [
            { label: 'Comptes utilisateurs', value: C.num(rows.length), icon: 'users-round', tone: 'navy' },
            { label: 'Comptes actifs', value: C.num(rows.filter(function (u) { return u.actif; }).length), icon: 'user-check', tone: 'success' },
            { label: 'Désactivés', value: C.num(rows.filter(function (u) { return !u.actif; }).length), icon: 'user-x', tone: 'danger' },
            { label: 'Avec double facteur', value: C.num(rows.filter(function (u) { return u.mfa; }).length), icon: 'shield-check', tone: 'info' },
          ];
        },
        detail: function (u) {
          var perms = permissionsRole(u.role);
          return el('div.space-y-4', null, [
            U.descList([
              ['Identifiant', el('span.font-mono', { text: u.identifiant })],
              ['Nom complet', u.nomComplet], ['Matricule', u.matricule || '—'],
              ['Rôle', U.badge(roleLabel(u.role), 'navy')],
              ['Service', u.service], ['Poste', u.poste || '—'],
              ['Compte actif', u.actif ? U.badge('Actif', 'success') : U.badge('Désactivé', 'danger')],
              ['Double facteur', u.mfa ? U.badge('Activé', 'info') : U.badge('Non requis', 'neutral')],
              ['Dernier accès', C.dateFR(u.dernierAcces)],
              ['Tentatives infructueuses', String(u.echecs || 0)],
              ['Compte créé le', C.dateFR(u.creeLe)],
            ]),
            U.card('Périmètre d’accès (RBAC)', el('div.space-y-2', null, [
              el('p.text-xs.text-slate-500', { text: perms.length + ' module(s) accessible(s) avec ce rôle.' }),
              el('div.flex.flex-wrap.gap-1', null, perms.map(function (p) { return U.badge(p, 'navy'); })),
            ])),
          ]);
        },
        etat: function (u) {
          P.etat({
            titre: 'Fiche de compte utilisateur',
            sousTitre: u.identifiant,
            cartouche: [['Identifiant', u.identifiant], ['Nom complet', u.nomComplet],
              ['Rôle', roleLabel(u.role)], ['Service', u.service],
              ['État', u.actif ? 'Actif' : 'Désactivé'], ['Double facteur', u.mfa ? 'Activé' : 'Non requis']],
            contenu: el('div.space-y-3', null, [
              P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
                { k: 'Matricule de l’agent', v: u.matricule || '—' },
                { k: 'Poste occupé', v: u.poste || '—' },
                { k: 'Date de création du compte', v: C.dateFR(u.creeLe) },
                { k: 'Dernier accès', v: C.dateFR(u.dernierAcces) },
                { k: 'Modules accessibles', v: permissionsRole(u.role).join(', ') },
              ]),
              el('p.mt-3.text-\\[10px\\].italic', {
                text: 'L’utilisateur s’engage à ne pas communiquer ses identifiants et reconnaît que toute action '
                  + 'réalisée sous son compte lui est imputable, conformément à la politique de sécurité de l’établissement (RG-12).',
              }),
            ]),
            signatures: [{ role: 'L’Utilisateur', nom: u.nomComplet, mention: 'Lu et approuvé' },
              { role: 'L’Administrateur système' }],
          });
        },
      })(root);
    },
  });

  /** Codes des modules ouverts à un rôle, surcharges comprises. */
  function permissionsRole(roleId) {
    var out = [];
    N.NAV.forEach(function (dom) {
      dom.modules.forEach(function (mod) {
        if (N.droits(roleId, mod.code).voir) out.push(mod.code);
      });
    });
    return out;
  }

  /** La collection des surcharges, une fiche par rôle. */
  function colRbac() {
    return S.collection('rbac', { module: 'M14', entite: 'rôle', prefix: 'RBAC' });
  }

  /** La fiche d'un rôle, créée à la volée au premier enregistrement. */
  function ficheRole(roleId) {
    return colRbac().all().filter(function (f) { return f.role === roleId; })[0] || null;
  }

  /** Les tentatives de connexion refusées, portées à la connaissance de l'admin. */
  function colTentatives() {
    return S.collection('tentativesConnexion', { module: 'M14', entite: 'tentative', prefix: 'TNT' });
  }

  /** Tous les modules du manifeste, à plat, avec leur domaine. */
  function tousModules() {
    var out = [];
    N.NAV.forEach(function (dom) {
      dom.modules.forEach(function (m) {
        out.push({ code: m.code, label: m.label, domaine: dom.domain, icon: m.icon });
      });
    });
    return out;
  }

  /* ==========================================================================
   * RÔLES & PERMISSIONS (matrice RBAC)
   * --------------------------------------------------------------------------
   * Trois choses que cet écran doit faire, et qu'il ne faisait pas :
   *
   * 1. Ses modifications doivent PRENDRE EFFET. Elles étaient écrites dans une
   *    collection que personne ne relisait ; elles vivent maintenant dans la
   *    couche de surcharges consultée par N.can() — fermer M1 au laborantin
   *    retire réellement le module de son ruban et de ses adresses.
   * 2. Un rôle doit pouvoir être RENOMMÉ (Laborantin → Biologiste médical) sans
   *    toucher au code : le libellé surchargé se propage partout, parce que
   *    tout le prototype lit N.ROLES[x].label.
   * 3. Un rôle doit pouvoir être ARCHIVÉ — jamais supprimé (RG-14). Ses comptes
   *    cessent d'ouvrir une session, la tentative est refusée par une modale
   *    explicite, et l'administrateur la retrouve ici.
   *
   * La granularité demandée est de quatre droits par module et par rôle :
   * voir, éditer, annuler, et la lecture seule qui en découle.
   * ======================================================================== */
  /* La création d'un rôle est une COMMANDE DE L'ÉCRAN : sa place est
     l'en-tête, avec les autres. Elle flottait entre les indicateurs et les
     onglets, seule et alignée à droite — le seul bouton du prototype à cet
     endroit, donc le seul qu'on ne pensait pas à chercher. */
  var creerRoleRef = { fn: null };

  global.SIGH.screen('m14-roles', {
    title: 'Rôles & permissions (RBAC)',
    description: 'Matrice des droits d’accès par rôle et par module : voir, éditer, annuler. Renommage et archivage des rôles.',
    regle: '<strong>RG-13</strong> — l’accès aux données médicales est réservé au personnel soignant habilité ; '
      + 'l’accès aux données financières et RH aux profils comptables et RH. '
      + '<strong>RG-14</strong> — un rôle ne se supprime pas, il s’archive : ses comptes cessent alors d’ouvrir '
      + 'une session et chaque tentative est journalisée.',
    actions: function () {
      if (!K.droits('M14').editer) return [];
      return [K.btn('Nouveau rôle', {
        variant: 'primary', icon: 'user-plus',
        onclick: function () { if (creerRoleRef.fn) creerRoleRef.fn(); },
      })];
    },
    render: function (root) {
      var host = el('div.space-y-4');
      var modules = tousModules();
      var vue = el('div.space-y-4');

      root.appendChild(host);
      host.appendChild(vue);
      afficher();
      return null;

      function roles() { return Object.keys(N.ROLES); }
      function actifs() { return roles().filter(function (r) { return !N.roleArchive(r); }); }
      function archives() { return roles().filter(function (r) { return N.roleArchive(r); }); }

      function afficher() {
        C.clear(vue);
        var tentativesNonTraitees = colTentatives().active().filter(function (t) { return !t.traitee; });

        /* --- Barre de notification des tentatives refusées --------------- */
        if (tentativesNonTraitees.length) {
          vue.appendChild(alerteTentatives(tentativesNonTraitees));
        }

        vue.appendChild(U.kpiGrid([
          { label: 'Rôles actifs', value: C.num(actifs().length), icon: 'shield', tone: 'navy' },
          {
            label: 'Rôles archivés', value: C.num(archives().length), icon: 'archive',
            tone: archives().length ? 'warning' : 'neutral',
            hint: archives().length ? 'Leurs comptes ne peuvent plus se connecter' : 'Aucun rôle retiré',
          },
          { label: 'Modules protégés', value: C.num(modules.length), icon: 'lock', tone: 'info' },
          {
            label: 'Tentatives refusées', value: C.num(tentativesNonTraitees.length), icon: 'shield-alert',
            tone: tentativesNonTraitees.length ? 'danger' : 'success',
            hint: tentativesNonTraitees.length ? 'À examiner' : 'Aucune tentative en attente',
          },
        ]));


        vue.appendChild(U.tabs([
          { id: 'matrice', label: 'Matrice des droits', badge: actifs().length, render: ongletMatrice },
          { id: 'detail', label: 'Détail par rôle', render: ongletDetail },
          { id: 'metier', label: 'Habilitations métier', render: ongletMetier },
          {
            id: 'tentatives', label: 'Tentatives refusées',
            badge: colTentatives().active().length, render: ongletTentatives,
          },
          { id: 'archives', label: 'Rôles archivés', badge: archives().length, render: ongletArchives },
        ]));
        U.icons(vue);
      }

      /* --------------------------------------------------------------------
       * Barre de notification — l'administrateur est prévenu.
       * ------------------------------------------------------------------ */
      function alerteTentatives(liste) {
        var d = el('div.flex.flex-wrap.items-start.gap-3.rounded-lg.border.border-danger-200.bg-danger-50.px-4.py-3');
        d.appendChild(el('span.shrink-0.text-danger-600', null, C.icon('shield-alert', 'h-5 w-5')));
        var txt = el('div.min-w-0.flex-1');
        txt.appendChild(el('p.text-sm.font-semibold.text-danger-900', {
          text: C.num(liste.length) + ' tentative(s) de connexion refusée(s)',
        }));
        txt.appendChild(el('p.mt-0\.5.text-xs.text-danger-800', {
          text: 'Comptes rattachés à un rôle archivé. Dernière : ' + (liste[0].nom || liste[0].identifiant)
            + ' — ' + C.dateHeure(new Date(liste[0].horodatage)),
        }));
        d.appendChild(txt);
        d.appendChild(K.btn('Examiner', {
          size: 'sm', variant: 'danger', icon: 'eye',
          onclick: function () { global.SIGH.app.go('m14-roles', { onglet: 'tentatives' }); },
        }));
        return d;
      }

      /* --------------------------------------------------------------------
       * Onglet 1 — la matrice, une ligne par rôle, une colonne par module.
       * ------------------------------------------------------------------ */
      function ongletMatrice() {
        var wrap = el('div.space-y-3');
        var matrice = el('div.overflow-x-auto');
        var t = el('table.tbl.min-w-\[72rem\]');
        var thead = el('thead'), htr = el('tr');
        htr.appendChild(el('th', { text: 'Rôle' }));
        modules.forEach(function (m) {
          htr.appendChild(el('th.text-center', { class: 'font-mono', title: m.label, text: m.code }));
        });
        htr.appendChild(el('th.text-right', { text: 'Actions' }));
        thead.appendChild(htr); t.appendChild(thead);

        var tb = el('tbody');
        actifs().forEach(function (r) {
          var tr = el('tr');
          var comptes = utilisateurs().active().filter(function (u) { return u.role === r; }).length;
          tr.appendChild(el('td', null, el('div.min-w-0', null, [
            el('p.truncate.text-sm.font-medium.text-slate-800', { text: N.ROLES[r].label }),
            el('p.text-xs.text-slate-400', {
              text: C.num(comptes) + ' compte(s)'
                + (N.ROLES[r].labelOrigine !== N.ROLES[r].label ? ' · ex-' + N.ROLES[r].labelOrigine : ''),
            }),
          ])));
          modules.forEach(function (m) {
            var d = N.droits(r, m.code);
            tr.appendChild(el('td.text-center', null, pastilleDroit(d)));
          });
          tr.appendChild(el('td.text-right.whitespace-nowrap', null, [
            K.iconBtn('sliders-horizontal', 'Modifier les droits de ce rôle', function () { editerRole(r); }),
            K.iconBtn('list-tree', 'Régler écran par écran', function () { editerEcrans(r); }),
            K.iconBtn('pencil', 'Renommer ce rôle', function () { renommerRole(r); }),
            K.iconBtn('archive', 'Archiver ce rôle', function () { archiverRole(r); }, 'ghost'),
          ]));
          tb.appendChild(tr);
        });
        t.appendChild(tb);
        matrice.appendChild(t);

        wrap.appendChild(K.note('Chaque case résume les trois droits du rôle sur le module : '
          + '<strong>vert</strong> plein accès, <strong>bleu</strong> lecture seule, '
          + '<strong>gris</strong> module fermé. Le détail se règle case par case avec le bouton '
          + '« Modifier les droits ».', { tone: 'info' }));
        wrap.appendChild(U.card('Matrice des droits d’accès', matrice, [
          K.btn('Imprimer la matrice', { size: 'sm', icon: 'printer', onclick: imprimerMatrice }),
        ]));
        return wrap;
      }

      function pastilleDroit(d) {
        if (!d.voir) {
          return el('span.inline-grid.h-5.w-5.place-items-center.rounded.bg-slate-100.text-slate-300',
            { title: 'Module fermé' }, C.icon('x', 'h-3 w-3'));
        }
        if (d.lectureSeule) {
          return el('span.inline-grid.h-5.w-5.place-items-center.rounded.bg-info-100.text-info-700',
            { title: 'Lecture seule' }, C.icon('eye', 'h-3 w-3'));
        }
        if (!d.editer || !d.annuler) {
          return el('span.inline-grid.h-5.w-5.place-items-center.rounded.bg-warning-100.text-warning-700',
            { title: (d.editer ? 'Édition' : '') + (d.annuler ? ' Annulation' : '') }, C.icon('pencil', 'h-3 w-3'));
        }
        return el('span.inline-grid.h-5.w-5.place-items-center.rounded.bg-success-100.text-success-700',
          { title: 'Voir, éditer, annuler' }, C.icon('check', 'h-3 w-3'));
      }

      /* --------------------------------------------------------------------
       * Onglet 2 — le détail lisible par rôle.
       * ------------------------------------------------------------------ */
      function ongletDetail() {
        var grille = el('div.grid.gap-3.md\:grid-cols-2.lg\:grid-cols-3');
        actifs().forEach(function (r) {
          var carte = el('div.card');
          var b = el('div.card-body');
          b.appendChild(el('div.mb-2.flex.items-center.justify-between.gap-2', null, [
            el('span.text-sm.font-semibold.text-slate-800', { text: N.ROLES[r].label }),
            U.badge(C.num(utilisateurs().active().filter(function (u) { return u.role === r; }).length), 'navy'),
          ]));
          var ouverts = modules.filter(function (m) { return N.droits(r, m.code).voir; });
          var lecture = ouverts.filter(function (m) { return N.droits(r, m.code).lectureSeule; });
          b.appendChild(el('div.flex.flex-wrap.gap-1', null, ouverts.map(function (m) {
            var d = N.droits(r, m.code);
            return U.badge(m.code, d.lectureSeule ? 'info' : (d.origine ? 'neutral' : 'success'));
          })));
          b.appendChild(el('p.mt-2.text-xs.text-slate-500', {
            text: C.num(ouverts.length) + ' module(s) ouvert(s)'
              + (lecture.length ? ' — dont ' + C.num(lecture.length) + ' en lecture seule' : ''),
          }));
          b.appendChild(el('div.mt-2.flex.gap-1', null, [
            K.btn('Droits', { size: 'sm', icon: 'sliders-horizontal', onclick: function () { editerRole(r); } }),
            K.btn('Renommer', { size: 'sm', icon: 'pencil', onclick: function () { renommerRole(r); } }),
          ]));
          carte.appendChild(b);
          grille.appendChild(carte);
        });
        return U.card('Niveaux d’accès par rôle', grille);
      }

      /* --------------------------------------------------------------------
       * Onglet 3 — habilitations métier (fonction et secteur), inchangées.
       * ------------------------------------------------------------------ */
      function ongletMetier() {
        var lignesCap = Object.keys(D.CAPACITES).map(function (f) {
          var c = D.CAPACITES[f];
          return {
            fonction: f, label: c.label,
            resultats: c.voirResultats, echographie: c.voirEchographie,
            prescrire: (c.prescrire || []).length,
            natures: (c.prescrire || []).map(function (n) {
              var x = D.NATURES_PRESCRIPTION.filter(function (y) { return y.id === n; })[0];
              return x ? x.label : n;
            }).join(', '),
            soins: c.executerSoins, remise: c.remettreResultats, note: c.note || '',
          };
        });

        return el('div.space-y-3', null, [
          U.dataTable({
            title: 'Habilitations métier par fonction',
            rows: lignesCap, exportName: 'habilitations-metier', pageSize: 20, searchable: true,
            columns: [
              { key: 'label', label: 'Fonction', render: function (r) { return el('span.font-medium.text-slate-800', { text: r.label }); } },
              {
                key: 'resultats', label: 'Résultats d’analyses',
                render: function (r) {
                  var m = {
                    tous: ['Tous', 'success'], secteur: ['Son secteur', 'info'],
                    produits: ['Ceux qu’il produit', 'info'], aucun: ['Aucun', 'neutral'],
                  };
                  var x = m[r.resultats] || m.aucun;
                  return U.badge(x[0], x[1]);
                },
              },
              {
                key: 'echographie', label: 'Échographies',
                render: function (r) {
                  var m = { tous: ['Toutes', 'success'], secteur: ['Son secteur', 'info'], aucun: ['Aucune', 'neutral'] };
                  var x = m[r.echographie] || m.aucun;
                  return U.badge(x[0], x[1]);
                },
              },
              {
                key: 'prescrire', label: 'Peut prescrire',
                text: function (r) { return r.natures; },
                render: function (r) {
                  return r.prescrire
                    ? el('span.text-xs.text-slate-600', { text: r.natures })
                    : el('span.text-xs.text-slate-300', { text: 'non' });
                },
              },
              {
                key: 'soins', label: 'Exécute les soins',
                text: function (r) { return r.soins ? 'oui' : 'non'; },
                render: function (r) { return r.soins ? U.badge('Oui', 'success') : U.badge('Non', 'neutral'); },
              },
              {
                key: 'note', label: 'Règle appliquée',
                render: function (r) { return el('span.text-xs.text-slate-500', { text: r.note }); },
              },
            ],
          }),
          K.note('Le <strong>rôle</strong> ouvre les écrans, la <strong>fonction</strong> décide des données, '
            + 'le <strong>secteur</strong> en fixe le périmètre. Ces habilitations-ci s’appliquent aux données, '
            + 'indépendamment de l’écran ouvert.', { tone: 'info', icon: 'quote' }),
        ]);
      }

      /* --------------------------------------------------------------------
       * Onglet 4 — les tentatives refusées.
       * ------------------------------------------------------------------ */
      function ongletTentatives() {
        var rows = colTentatives().active().map(function (t) {
          return Object.assign({}, t, {
            quand: t.horodatage ? C.dateHeure(new Date(t.horodatage)) : '—',
            roleLabel: N.ROLES[t.role] ? N.ROLES[t.role].label : t.role,
          });
        }).sort(function (a, b) { return String(b.horodatage).localeCompare(String(a.horodatage)); });

        if (!rows.length) {
          return U.card('Tentatives de connexion refusées',
            U.empty('Aucune tentative refusée.', {
              icon: 'shield-check',
              hint: 'Les comptes rattachés à un rôle archivé apparaîtraient ici, avec leur horodatage.',
            }));
        }

        return U.dataTable({
          title: 'Tentatives de connexion refusées',
          rows: rows, exportName: 'tentatives-refusees', pageSize: 15, searchable: true,
          filters: [{
            name: 'traitee', label: 'Suivi',
            options: [{ value: 'non', label: 'À examiner' }, { value: 'oui', label: 'Examinée' }],
            match: function (r, v) { return v === 'oui' ? !!r.traitee : !r.traitee; },
          }],
          columns: [
            { key: 'quand', label: 'Date et heure', nowrap: true },
            {
              key: 'nom', label: 'Compte',
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.nom || r.identifiant }),
                  el('p.text-xs.text-slate-400', { text: r.identifiant }),
                ]);
              },
            },
            { key: 'roleLabel', label: 'Rôle' },
            { key: 'motif', label: 'Motif du refus', render: function (r) { return el('span.text-xs.text-danger-700', { text: r.motif }); } },
            {
              key: 'traitee', label: 'Suivi', align: 'right',
              text: function (r) { return r.traitee ? 'examinée' : 'à examiner'; },
              render: function (r) {
                return r.traitee ? U.badge('Examinée', 'success') : U.badge('À examiner', 'danger');
              },
            },
          ],
          rowActions: function (r) {
            if (r.traitee) return [];
            return [K.iconBtn('check', 'Marquer comme examinée', function () {
              colTentatives().update(r.id, { traitee: true, examineePar: S.currentUser(), examineeLe: C.iso(AUJ) });
              afficher();
              U.toast('Tentative marquée comme examinée.', { type: 'success' });
            })];
          },
        });
      }

      /* --------------------------------------------------------------------
       * Onglet 5 — les rôles archivés, restaurables (RG-14).
       * ------------------------------------------------------------------ */
      function ongletArchives() {
        var liste = archives();
        if (!liste.length) {
          return U.card('Rôles archivés', U.empty('Aucun rôle archivé.', {
            icon: 'shield-check',
            hint: 'Un rôle archivé reste dans le manifeste — il cesse simplement d’ouvrir une session.',
          }));
        }
        var rows = liste.map(function (r) {
          var f = ficheRole(r) || {};
          return {
            role: r, label: N.ROLES[r].label,
            comptes: utilisateurs().active().filter(function (u) { return u.role === r; }).length,
            archiveLe: f.archiveLe ? C.dateFR(new Date(f.archiveLe)) : '—',
            motif: f.motifArchivage || '—',
          };
        });
        return el('div.space-y-3', null, [
          K.note('<strong>RG-14</strong> — l’archivage est logique : le rôle n’est pas supprimé, ses habilitations '
            + 'sont conservées et la restauration rend immédiatement l’accès à ses comptes.', { tone: 'warning' }),
          U.dataTable({
            title: 'Rôles archivés', rows: rows, exportName: 'roles-archives', pageSize: 10,
            columns: [
              { key: 'label', label: 'Rôle', render: function (r) { return el('span.font-medium.text-slate-800', { text: r.label }); } },
              {
                key: 'comptes', label: 'Comptes bloqués', align: 'right',
                render: function (r) { return r.comptes ? U.badge(C.num(r.comptes), 'danger') : el('span.text-xs.text-slate-300', { text: '—' }); },
              },
              { key: 'archiveLe', label: 'Archivé le', nowrap: true },
              { key: 'motif', label: 'Motif' },
            ],
            rowActions: function (r) {
              return [K.iconBtn('archive-restore', 'Restaurer ce rôle', function () { restaurerRole(r.role); })];
            },
          }),
        ]);
      }

      /* --------------------------------------------------------------------
       * Enregistrement d'une fiche de rôle — création ou mise à jour.
       * ------------------------------------------------------------------ */
      function enregistrer(roleId, valeurs, journal) {
        var f = ficheRole(roleId);
        if (f) colRbac().update(f.id, valeurs);
        else colRbac().insert(Object.assign({ role: roleId, libelleOrigine: N.ROLES[roleId].labelOrigine }, valeurs));
        N.invaliderRbac();
        S.log(journal || 'Modification RBAC', 'M14', 'Rôle', roleId, null, valeurs);
        afficher();
      }

      /* --------------------------------------------------------------------
       * La sous-matrice : trois cases par module, la lecture seule déduite.
       * ------------------------------------------------------------------ */
      function editerRole(roleId) {
        var f = ficheRole(roleId);
        var etat = {};
        modules.forEach(function (m) {
          var d = N.droits(roleId, m.code);
          etat[m.code] = { voir: d.voir, editer: d.editer, annuler: d.annuler };
        });

        var corps = el('div.space-y-3');
        corps.appendChild(K.note('<strong>RG-13</strong> — le médical reste réservé au soignant habilité, le financier '
          + 'et le RH aux profils comptables et RH. Fermer un module le retire du méga-menu, de la recherche globale '
          + '<em>et</em> de ses adresses : l’écran devient inatteignable, pas seulement invisible.',
        { tone: 'warning', icon: 'shield-alert' }));

        var tableau = el('div.max-h-\[26rem\].overflow-auto.rounded-lg.border.border-slate-200');
        var t = el('table.tbl');
        var thead = el('thead');
        thead.appendChild(el('tr', null, [
          el('th', { text: 'Module' }),
          el('th.text-center', { text: 'Voir' }),
          el('th.text-center', { text: 'Éditer' }),
          el('th.text-center', { text: 'Annuler' }),
          el('th.text-center', { text: 'Lecture seule' }),
        ]));
        t.appendChild(thead);
        var tb = el('tbody');

        modules.forEach(function (m) {
          var tr = el('tr');
          tr.appendChild(el('td', null, el('div.min-w-0', null, [
            el('p.text-sm.font-medium.text-slate-800', { text: m.label }),
            el('p.text-xs.text-slate-400', { text: m.domaine + ' · ' + m.code }),
          ])));

          var cases = {};
          ['voir', 'editer', 'annuler'].forEach(function (k) {
            var c = el('input.checkbox', { type: 'checkbox' });
            c.checked = !!etat[m.code][k];
            cases[k] = c;
            tr.appendChild(el('td.text-center', null, c));
          });
          var lecture = el('input.checkbox', { type: 'checkbox' });
          lecture.checked = etat[m.code].voir && !etat[m.code].editer && !etat[m.code].annuler;
          tr.appendChild(el('td.text-center', null, lecture));

          /* La lecture seule n'est pas un quatrième droit indépendant : c'est
             la combinaison « voir sans agir ». Les quatre cases restent donc
             cohérentes entre elles, quel que soit l'ordre des clics. */
          function synchroniser() {
            if (!cases.voir.checked) { cases.editer.checked = false; cases.annuler.checked = false; }
            lecture.checked = cases.voir.checked && !cases.editer.checked && !cases.annuler.checked;
            etat[m.code] = { voir: cases.voir.checked, editer: cases.editer.checked, annuler: cases.annuler.checked };
          }
          ['voir', 'editer', 'annuler'].forEach(function (k) {
            cases[k].addEventListener('change', function () {
              if (k !== 'voir' && cases[k].checked) cases.voir.checked = true;
              synchroniser();
            });
          });
          lecture.addEventListener('change', function () {
            if (lecture.checked) { cases.voir.checked = true; cases.editer.checked = false; cases.annuler.checked = false; }
            synchroniser();
          });

          tb.appendChild(tr);
        });
        t.appendChild(tb);
        tableau.appendChild(t);
        corps.appendChild(tableau);

        /* Deux commandes globales : la Direction ne veut pas cocher trente fois. */
        corps.appendChild(el('div.flex.flex-wrap.gap-2', null, [
          K.btn('Tout ouvrir', {
            size: 'sm', icon: 'check-check',
            onclick: function () { basculerTout(true); },
          }),
          K.btn('Tout en lecture seule', {
            size: 'sm', icon: 'eye',
            onclick: function () { basculerTout('lecture'); },
          }),
          K.btn('Tout fermer', { size: 'sm', icon: 'x', onclick: function () { basculerTout(false); } }),
        ]));

        function basculerTout(mode) {
          var cases = tableau.querySelectorAll('input[type=checkbox]');
          modules.forEach(function (m, i) {
            var base = i * 4;
            var voir = cases[base], editer = cases[base + 1], annuler = cases[base + 2], lecture = cases[base + 3];
            if (mode === true) { voir.checked = true; editer.checked = true; annuler.checked = true; lecture.checked = false; }
            else if (mode === 'lecture') { voir.checked = true; editer.checked = false; annuler.checked = false; lecture.checked = true; }
            else { voir.checked = false; editer.checked = false; annuler.checked = false; lecture.checked = false; }
            etat[m.code] = { voir: voir.checked, editer: editer.checked, annuler: annuler.checked };
          });
        }

        var m = U.modal({
          title: 'Droits du rôle « ' + N.ROLES[roleId].label + ' »',
          subtitle: 'Trois droits par module ; la lecture seule est la combinaison « voir sans agir ».',
          size: 'xl', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer les droits', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var droitsSaisis = {};
                modules.forEach(function (x) { droitsSaisis[x.code] = etat[x.code]; });
                var ouverts = modules.filter(function (x) { return etat[x.code].voir; });
                var figes = ouverts.filter(function (x) { return !etat[x.code].editer && !etat[x.code].annuler; });
                enregistrer(roleId, {
                  droits: droitsSaisis, statut: 'actif',
                  definiLe: C.iso(AUJ), definiPar: S.currentUser(),
                }, 'Modification des droits RBAC');
                m.close();
                U.toast('Droits du rôle « ' + N.ROLES[roleId].label + ' » enregistrés.', {
                  type: 'success',
                  detail: C.num(ouverts.length) + ' module(s) ouvert(s), dont ' + C.num(figes.length) + ' en lecture seule.',
                });
              },
            }),
          ],
        });
        U.icons(corps);
      }

      /* --------------------------------------------------------------------
       * RÉGLAGE ÉCRAN PAR ÉCRAN
       * --------------------------------------------------------------------
       * La matrice par module ne suffisait pas : la Direction demande que le
       * laborantin consulte le répertoire des patients SANS accéder au
       * dossier médical, aux antécédents ni aux documents. Un même module,
       * deux traitements — d'où ce second niveau.
       *
       * Un écran non réglé suit son module : il ne faut pas avoir à déclarer
       * cent quatre-vingts écrans pour en fermer quatre.
       * ------------------------------------------------------------------ */
      function editerEcrans(roleId) {
        var f = ficheRole(roleId);
        var ecransParModule = {};
        N.NAV.forEach(function (dom) {
          dom.modules.forEach(function (m) {
            m.items.forEach(function (it) {
              (ecransParModule[m.code] = ecransParModule[m.code] || {
                label: m.label, domaine: dom.domain, items: [],
              }).items.push(it);
            });
          });
        });

        var etat = {};
        var corps = el('div.space-y-3');
        corps.appendChild(K.note('Un écran <strong>non réglé suit son module</strong> — il ne faut pas déclarer '
          + 'cent quatre-vingts écrans pour en fermer quatre. Une case décochée ici <strong>l’emporte sur le '
          + 'module</strong> : c’est ce qui permet d’ouvrir M1 en lecture tout en fermant le dossier médical.',
        { tone: 'info', icon: 'list-tree' }));

        var selModule = el('select.select');
        Object.keys(ecransParModule).forEach(function (code) {
          selModule.appendChild(el('option', { value: code },
            code + ' — ' + ecransParModule[code].label));
        });
        corps.appendChild(el('div', null, [el('label.label', { text: 'Module' }), selModule]));

        var zone = el('div.max-h-\[22rem\].overflow-auto.rounded-lg.border.border-slate-200');
        corps.appendChild(zone);

        function dessinerModule() {
          var code = selModule.value;
          var mod = ecransParModule[code];
          C.clear(zone);
          var t = el('table.tbl');
          t.appendChild(el('thead', null, el('tr', null, [
            el('th', { text: 'Écran' }),
            el('th.text-center', { text: 'Voir' }),
            el('th.text-center', { text: 'Éditer' }),
            el('th.text-center', { text: 'Annuler' }),
            el('th.text-right', { text: 'Origine' }),
          ])));
          var tb = el('tbody');
          mod.items.forEach(function (it) {
            var courant = etat[it.id] || N.droitsEcran(roleId, it.id, code);
            var surcharge = !!(f && f.droitsEcrans && f.droitsEcrans[it.id]);
            var tr = el('tr');
            tr.appendChild(el('td', null, el('div.min-w-0', null, [
              el('p.truncate.text-sm.text-slate-800', { text: it.label }),
              el('p.font-mono.text-xs.text-slate-400', { text: it.id }),
            ])));
            var cases = {};
            ['voir', 'editer', 'annuler'].forEach(function (k) {
              var cb = el('input.checkbox', { type: 'checkbox' });
              cb.checked = !!courant[k];
              cases[k] = cb;
              cb.addEventListener('change', function () {
                if (k !== 'voir' && cb.checked) cases.voir.checked = true;
                if (!cases.voir.checked) { cases.editer.checked = false; cases.annuler.checked = false; }
                etat[it.id] = {
                  voir: cases.voir.checked, editer: cases.editer.checked, annuler: cases.annuler.checked,
                };
              });
              tr.appendChild(el('td.text-center', null, cb));
            });
            tr.appendChild(el('td.text-right', null,
              surcharge ? U.badge('Réglé', 'navy') : el('span.text-xs.text-slate-400', { text: 'suit le module' })));
            tb.appendChild(tr);
          });
          t.appendChild(tb);
          zone.appendChild(t);
        }
        selModule.addEventListener('change', dessinerModule);
        dessinerModule();

        var m = U.modal({
          title: 'Droits par écran — « ' + N.ROLES[roleId].label + ' »',
          subtitle: 'Un écran l’emporte sur son module', size: 'xl', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Retirer tous les réglages d’écran', {
              icon: 'rotate-ccw',
              onclick: function () {
                enregistrer(roleId, { droitsEcrans: {} }, 'Retrait des réglages d’écran');
                m.close();
                U.toast('Réglages d’écran retirés.', {
                  type: 'success', detail: 'Tous les écrans suivent de nouveau leur module.',
                });
              },
            }),
            K.btn('Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var existants = (f && f.droitsEcrans) ? Object.assign({}, f.droitsEcrans) : {};
                Object.keys(etat).forEach(function (id) { existants[id] = etat[id]; });
                enregistrer(roleId, { droitsEcrans: existants, statut: 'actif' },
                  'Réglage des droits par écran');
                m.close();
                var fermes = Object.keys(existants).filter(function (id) { return !existants[id].voir; });
                U.toast('Droits par écran enregistrés.', {
                  type: 'success',
                  detail: C.num(Object.keys(existants).length) + ' écran(s) réglé(s), dont '
                    + C.num(fermes.length) + ' fermé(s).',
                });
              },
            }),
          ],
        });
        U.icons(corps);
      }

      /* --------------------------------------------------------------------
       * CRÉATION D'UN RÔLE
       * --------------------------------------------------------------------
       * Un rôle créé part de ZÉRO : il n'apparaît dans aucune liste du
       * manifeste, donc il n'ouvre rien tant que l'administrateur ne lui a
       * rien ouvert. C'est le comportement sûr — l'inverse donnerait tous les
       * droits à un rôle qu'on vient d'inventer.
       * ------------------------------------------------------------------ */
      creerRoleRef.fn = creerRole;
      function creerRole() {
        var f = U.form([
          { name: 'libelle', label: 'Intitulé du rôle', type: 'text', required: true, col: 'full' },
          { name: 'libelleCourt', label: 'Intitulé abrégé', type: 'text',
            hint: 'Affiché au bandeau, quand la place manque.' },
          {
            name: 'id', label: 'Identifiant technique', type: 'text', required: true,
            hint: 'Sans espace ni accent — il sert de clé dans les habilitations.',
          },
          {
            name: 'couleur', label: 'Couleur', type: 'select',
            options: [{ value: 'navy', label: 'Bleu institutionnel' }, { value: 'info', label: 'Bleu clair' },
              { value: 'success', label: 'Vert' }, { value: 'warning', label: 'Orange' },
              { value: 'danger', label: 'Rouge' }, { value: 'neutral', label: 'Gris' }],
          },
          {
            name: 'accueil', label: 'Écran d’accueil', type: 'select', required: true,
            options: N.ids().filter(function (id) { return /^dash-/.test(id); })
              .map(function (id) { var e = N.get(id); return { value: id, label: e ? e.label : id }; }),
          },
          { name: 'motif', label: 'Raison d’être de ce rôle', type: 'textarea', rows: 2, col: 'full' },
        ], { couleur: 'neutral', accueil: 'dash-admin' });

        var m = U.modal({
          title: 'Nouveau rôle', size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('Le rôle est créé <strong>tous modules fermés</strong>. C’est délibéré : certains modules '
              + 'sont ouverts « à tous les rôles » au manifeste, ce qui a été écrit pour les rôles existants '
              + 'et non pour ceux qu’on inventera ensuite. Ouvrez-lui explicitement ce qu’il doit voir — '
              + 'module par module, puis écran par écran pour les exceptions.',
            { tone: 'warning', icon: 'shield-alert' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Créer le rôle', {
              variant: 'primary', icon: 'user-plus',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var id = String(v.id).toLowerCase()
                  .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
                  .replace(/[^a-z0-9]/g, '');
                if (!id) { U.toast('Identifiant technique invalide.', { type: 'error' }); return; }
                if (N.ROLES[id]) {
                  U.toast('Ce rôle existe déjà.', {
                    type: 'error', detail: N.ROLES[id].label + ' porte déjà l’identifiant « ' + id + ' ».',
                  });
                  return;
                }
                /* Chaque module est FERMÉ explicitement. Sans cela, les
                   modules portant « tous les rôles » au manifeste — M1, les
                   rapports — s'ouvriraient d'eux-mêmes à un rôle qu'on vient
                   d'inventer. « Tous » a été écrit pour les rôles existants,
                   pas pour ceux à venir. */
                var ferme = {};
                tousModules().forEach(function (x) {
                  ferme[x.code] = { voir: false, editer: false, annuler: false };
                });
                /* Upsert : si une fiche existe déjà pour cet identifiant —
                   un rôle archivé qu'on recrée, par exemple — on la reprend
                   plutôt que d'en poser une seconde. */
                var dejaLa = ficheRole(id);
                if (dejaLa) {
                  colRbac().update(dejaLa.id, {
                    nouveau: true, statut: 'actif', libelle: v.libelle,
                    libelleCourt: v.libelleCourt || v.libelle, libelleOrigine: v.libelle,
                    couleur: v.couleur, accueil: v.accueil, motif: v.motif,
                    droits: ferme, droitsEcrans: {},
                  });
                  N.invaliderRbac();
                  m.close(); afficher();
                  U.toast('Rôle « ' + v.libelle + ' » rétabli.', { type: 'success' });
                  return;
                }
                colRbac().insert({
                  role: id, nouveau: true, statut: 'actif',
                  libelle: v.libelle, libelleCourt: v.libelleCourt || v.libelle,
                  libelleOrigine: v.libelle,
                  couleur: v.couleur, accueil: v.accueil, motif: v.motif,
                  droits: ferme, droitsEcrans: {},
                  definiLe: C.iso(AUJ), definiPar: S.currentUser(),
                });
                N.invaliderRbac();
                S.log('Création d’un rôle', 'M14', 'Rôle', id, null, { libelle: v.libelle });
                m.close();
                afficher();
                U.toast('Rôle « ' + v.libelle + ' » créé.', {
                  type: 'success', duration: 9000,
                  detail: 'Les ' + C.num(tousModules().length) + ' modules sont fermés : le rôle n’ouvre aucun '
                    + 'écran. Lui régler ses droits avec « Modifier les droits », puis « Régler écran par écran » '
                    + 'pour les exceptions.',
                });
              },
            }),
          ],
        });
      }

      /* --------------------------------------------------------------------
       * Renommage — le libellé se propage à tout le prototype.
       * ------------------------------------------------------------------ */
      function renommerRole(roleId) {
        var f = U.form([
          {
            name: 'libelle', label: 'Intitulé du rôle', type: 'text', required: true,
            hint: 'Intitulé d’origine : ' + N.ROLES[roleId].labelOrigine,
          },
        ], { libelle: N.ROLES[roleId].label });

        var m = U.modal({
          title: 'Renommer le rôle', subtitle: N.ROLES[roleId].labelOrigine, size: 'md',
          body: el('div.space-y-3', null, [
            K.note('Le nouvel intitulé s’applique <strong>partout</strong> — méga-menu, bandeau de session, '
              + 'états imprimés, journal d’audit. Les habilitations ne changent pas : renommer n’est pas '
              + 'redéfinir.', { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Renommer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var ancien = N.ROLES[roleId].label;
                enregistrer(roleId, { libelle: v.libelle, statut: 'actif' }, 'Renommage de rôle');
                m.close();
                U.toast('Rôle renommé.', {
                  type: 'success', detail: ancien + ' → ' + v.libelle,
                  undo: function () {
                    enregistrer(roleId, { libelle: N.ROLES[roleId].labelOrigine === ancien ? null : ancien });
                  },
                });
              },
            }),
          ],
        });
      }

      /* --------------------------------------------------------------------
       * Archivage — jamais de suppression (RG-14).
       * ------------------------------------------------------------------ */
      function archiverRole(roleId) {
        var comptes = utilisateurs().active().filter(function (u) { return u.role === roleId; });
        var session = S.session() || {};
        if (session.role === roleId) {
          U.toast('Impossible d’archiver le rôle de la session en cours.', {
            type: 'error', detail: 'Se connecter avec un autre profil pour procéder.',
          });
          return;
        }
        U.confirm({
          title: 'Archiver le rôle « ' + N.ROLES[roleId].label + ' » ?',
          message: comptes.length
            ? '<strong>' + C.num(comptes.length) + ' compte(s)</strong> sont rattachés à ce rôle. '
              + 'Ils ne pourront plus ouvrir de session : la connexion sera refusée par une modale d’échec '
              + 'et chaque tentative vous sera signalée sur cet écran.<br><br>'
              + 'Conformément à <strong>RG-14</strong>, le rôle n’est pas supprimé — il reste restaurable, '
              + 'avec ses habilitations.'
            : 'Aucun compte n’est rattaché à ce rôle. L’archivage reste logique (RG-14) et se défait.',
          confirmLabel: 'Archiver le rôle', danger: true, requireMotif: true,
        }).then(function (rep) {
          if (!rep) return;
          enregistrer(roleId, {
            statut: 'archive', archiveLe: C.iso(AUJ), archivePar: S.currentUser(),
            motifArchivage: rep.motif,
          }, 'Archivage de rôle');
          U.toast('Rôle archivé.', {
            type: 'success',
            detail: comptes.length ? C.num(comptes.length) + ' compte(s) désormais bloqué(s).' : null,
            undo: function () { enregistrer(roleId, { statut: 'actif' }, 'Restauration de rôle'); },
            undoMessage: 'Archivage annulé — le rôle est de nouveau actif.',
          });
        });
      }

      function restaurerRole(roleId) {
        enregistrer(roleId, { statut: 'actif', restaureLe: C.iso(AUJ), restaurePar: S.currentUser() },
          'Restauration de rôle');
        U.toast('Rôle « ' + N.ROLES[roleId].label + ' » restauré.', {
          type: 'success', detail: 'Ses comptes peuvent de nouveau se connecter.',
        });
      }

      /* --------------------------------------------------------------------
       * Impression de la matrice.
       * ------------------------------------------------------------------ */
      function imprimerMatrice() {
        var lignes = actifs().map(function (r) {
          var ouverts = modules.filter(function (m) { return N.droits(r, m.code).voir; });
          var figes = ouverts.filter(function (m) { return N.droits(r, m.code).lectureSeule; });
          return {
            role: N.ROLES[r].label,
            comptes: C.num(utilisateurs().active().filter(function (u) { return u.role === r; }).length),
            modules: ouverts.map(function (m) { return m.code; }).join(', ') || '—',
            lecture: figes.map(function (m) { return m.code; }).join(', ') || '—',
          };
        });
        P.etat({
          titre: 'Matrice des droits d’accès (RBAC)',
          sousTitre: 'Politique de sécurité — situation au ' + C.dateFR(AUJ),
          cartouche: [['Rôles actifs', C.num(actifs().length)],
            ['Rôles archivés', C.num(archives().length)],
            ['Modules protégés', C.num(modules.length)],
            ['Comptes utilisateurs', C.num(utilisateurs().active().length)],
            ['Date d’édition', C.dateFR(AUJ)]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Rôle', key: 'role' },
              { label: 'Comptes', align: 'right', key: 'comptes' },
              { label: 'Modules accessibles', key: 'modules' },
              { label: 'Dont lecture seule', key: 'lecture' },
            ], lignes),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Conformément à la règle RG-13, l’accès aux données médicales est réservé au personnel soignant '
                + 'habilité, et l’accès aux données financières et de ressources humaines aux profils comptables '
                + 'et RH habilités. Conformément à RG-14, un rôle retiré est archivé et non supprimé. '
                + 'Toute dérogation doit être motivée et tracée.',
            }),
          ]),
          signatures: [{ role: 'L’Administrateur système' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
            { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
        });
      }
    },
  });

  /* ==========================================================================
   * SESSIONS ACTIVES
   * ======================================================================== */
  global.SIGH.screen('m14-sessions', {
    title: 'Sessions actives',
    regle: 'Écran <strong>calculé</strong> : les sessions reflètent les connexions en cours. '
      + 'Elles ne se créent ni ne se modifient — elles se <strong>terminent</strong>, et la clôture '
      + 'est journalisée (RG-12).',
    description: 'Connexions en cours, postes de travail et délai d’inactivité avant verrouillage.',
    render: function (root) {
      var users = utilisateurs().active().filter(function (u) { return u.actif; });
      var rnd = C.seeded(3413);
      var rows = users.slice(0, 12).map(function (u, i) {
        var debut = new Date(AUJ.getTime());
        debut.setHours(C.between(rnd, 7, 15), C.between(rnd, 0, 59));
        var inactivite = C.between(rnd, 0, 25);
        return {
          id: u.id, identifiant: u.identifiant, nomComplet: u.nomComplet,
          role: u.role, poste: 'POSTE-' + C.pick(rnd, ['ACCUEIL', 'CAISSE', 'PHARMA', 'LABO', 'COMPTA', 'DIR', 'SOINS']),
          adresseIp: '192.168.1.' + C.between(rnd, 10, 60),
          debut: debut.toISOString(),
          inactivite: inactivite,
          verrouillage: inactivite >= 15,
        };
      });

      var host = el('div.space-y-4');
      host.appendChild(U.kpiGrid([
        { label: 'Sessions ouvertes', value: C.num(rows.length), icon: 'monitor', tone: 'navy' },
        { label: 'Postes distincts', value: C.num(Object.keys(C.groupBy(rows, 'poste')).length), icon: 'network', tone: 'info' },
        { label: 'Verrouillées pour inactivité', value: C.num(rows.filter(function (r) { return r.verrouillage; }).length), icon: 'lock', tone: 'warning' },
        { label: 'Délai de verrouillage', value: '15 min', icon: 'timer', tone: 'neutral', hint: 'Postes partagés' },
      ]));

      host.appendChild(K.note('Sur les postes partagés — accueil et caisse — un délai d’inactivité de 15 minutes entraîne le <strong>verrouillage automatique de l’écran</strong>.', { tone: 'info', icon: 'lock' }));

      host.appendChild(U.dataTable({
        title: 'Sessions en cours', rows: rows, exportName: 'sessions', pageSize: 15,
        columns: [
          { key: 'identifiant', label: 'Identifiant', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold', { text: r.identifiant }); } },
          { key: 'nomComplet', label: 'Utilisateur' },
          { key: 'role', label: 'Rôle', text: roleLabel, render: function (r) { return U.badge(roleLabel(r.role), 'navy'); } },
          { key: 'poste', label: 'Poste', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.poste }); } },
          { key: 'adresseIp', label: 'Adresse réseau', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.text-slate-500', { text: r.adresseIp }); } },
          {
            key: 'debut', label: 'Ouverture', nowrap: true,
            text: function (r) { return C.heure(r.debut); },
            render: function (r) { return C.heure(r.debut); },
          },
          {
            key: 'inactivite', label: 'Inactivité', align: 'right',
            render: function (r) {
              return el('span.num', { class: r.inactivite >= 15 ? 'font-semibold text-warning-600' : 'text-slate-600', text: r.inactivite + ' min' });
            },
          },
          {
            key: 'verrouillage', label: 'État',
            text: function (r) { return r.verrouillage ? 'Verrouillée' : 'Active'; },
            render: function (r) { return r.verrouillage ? U.badge('Verrouillée', 'warning') : U.badge('Active', 'success'); },
          },
        ],
        rowActions: function (r) {
          return [K.btn('Clôturer', {
            size: 'sm', variant: 'danger', icon: 'log-out',
            onclick: function () {
              U.confirm({
                title: 'Clôturer la session de ' + r.nomComplet + ' ?',
                message: 'L’utilisateur sera immédiatement déconnecté du poste ' + r.poste + '. L’opération est journalisée.',
                confirmLabel: 'Clôturer la session', danger: true,
              }).then(function (ok) {
                if (!ok) return;
                S.log('Modification', 'M14', 'SessionUtilisateur', r.identifiant, { etat: 'ouverte' }, { etat: 'close' });
                U.toast('Session clôturée.', { type: 'success', detail: r.nomComplet + ' — ' + r.poste });
              });
            },
          })];
        },
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * JOURNAL D'AUDIT
   * ======================================================================== */
  global.SIGH.screen('m14-audit', {
    title: 'Journal d’audit',
    description: 'Traçabilité intégrale : création, modification, validation, archivage et connexions.',
    regle: '<strong>RG-12</strong> — toute action de création, modification, validation ou suppression est journalisée '
      + 'avec l’identité de l’utilisateur, la date, l’heure et l’entité concernée. <strong>Aucune action anonyme n’est permise.</strong>',
    render: function (root) {
      var rows = S.raw().audit || [];
      var host = el('div.space-y-4');
      var echecs = rows.filter(function (a) { return a.succes === false; });

      host.appendChild(U.kpiGrid([
        { label: 'Actions journalisées', value: C.num(rows.length), icon: 'scroll-text', tone: 'navy' },
        { label: 'Utilisateurs tracés', value: C.num(Object.keys(C.groupBy(rows, 'utilisateur')).length), icon: 'users', tone: 'info' },
        { label: 'Modules concernés', value: C.num(Object.keys(C.groupBy(rows, 'module')).length), icon: 'layers', tone: 'success' },
        { label: 'Tentatives infructueuses', value: C.num(echecs.length), icon: 'shield-alert', tone: echecs.length ? 'danger' : 'neutral' },
      ]));

      if (echecs.length) {
        host.appendChild(K.note('<strong>' + echecs.length + ' tentative(s) d’accès infructueuse(s)</strong> enregistrée(s). '
          + 'Ces événements doivent faire l’objet d’une revue périodique par l’Administrateur et la Direction.', { tone: 'warning', icon: 'shield-alert' }));
      }

      host.appendChild(U.dataTable({
        title: 'Journal d’audit', rows: rows, exportName: 'journal-audit', pageSize: 25,
        defaultSort: 'dateHeure', defaultDir: 'desc',
        filters: [
          { name: 'action', label: 'Action', options: Object.keys(C.groupBy(rows, 'action')).sort() },
          { name: 'module', label: 'Module', options: Object.keys(C.groupBy(rows, 'module')).sort() },
          { name: 'utilisateur', label: 'Utilisateur', options: Object.keys(C.groupBy(rows, 'utilisateur')).sort() },
          { name: 'succes', label: 'Résultat', options: [{ value: 'ok', label: 'Réussies' }, { value: 'ko', label: 'Échouées' }], match: function (a, v) { return v === 'ok' ? a.succes !== false : a.succes === false; } },
        ],
        columns: [
          {
            key: 'dateHeure', label: 'Horodatage', nowrap: true,
            text: function (a) { return C.dateHeure(a.dateHeure); },
            render: function (a) {
              return el('div', null, [
                el('p.text-sm.text-slate-700', { text: C.dateHeure(a.dateHeure) }),
                el('p.text-xs.text-slate-400', { text: C.ilYA(a.dateHeure) }),
              ]);
            },
            sortValue: function (a) { return C.toDate(a.dateHeure).getTime(); },
          },
          { key: 'utilisateur', label: 'Utilisateur' },
          {
            key: 'action', label: 'Action',
            render: function (a) {
              var tone = a.succes === false ? 'danger'
                : ({ 'Création': 'success', 'Modification': 'info', 'Archivage': 'warning', 'Restauration': 'success', 'Validation': 'navy', 'Impression': 'neutral', 'Connexion': 'navy' }[a.action] || 'neutral');
              return U.badge(a.action, tone);
            },
          },
          { key: 'module', label: 'Module', render: function (a) { return U.badge(a.module, 'neutral'); } },
          { key: 'entite', label: 'Entité concernée' },
          { key: 'reference', label: 'Référence', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.text-slate-500', { text: a.reference || '—' }); } },
          { key: 'poste', label: 'Poste', nowrap: true, render: function (a) { return el('span.font-mono.text-xs.text-slate-500', { text: a.poste || '—' }); } },
          {
            key: 'succes', label: 'Résultat',
            text: function (a) { return a.succes === false ? 'Échec' : 'Succès'; },
            render: function (a) { return a.succes === false ? U.badge('Échec', 'danger') : U.badge('Succès', 'success'); },
          },
        ],
        onRowClick: function (a) {
          /* Le journal conserve la valeur telle qu'écrite (RG-12) : on la
             présente indentée pour qu'elle se lise, sans jamais la réécrire. */
          function jsonLisible(x) {
            try { return JSON.stringify(JSON.parse(x), null, 2); } catch (e) { return String(x); }
          }
          U.drawer({
            title: a.action + ' — ' + a.entite, subtitle: C.dateHeure(a.dateHeure),
            body: el('div.space-y-4', null, [
              U.descList([
                ['Horodatage', C.dateHeure(a.dateHeure)],
                ['Utilisateur', a.utilisateur],
                ['Action', U.badge(a.action, 'navy')],
                ['Module', a.module],
                ['Entité concernée', a.entite],
                ['Référence', a.reference || '—'],
                ['Poste de travail', a.poste || '—'],
                ['Résultat', a.succes === false ? U.badge('Échec', 'danger') : U.badge('Succès', 'success')],
              ]),
              (a.ancienneValeur || a.nouvelleValeur)
                ? U.card('Valeurs', el('div.space-y-3', null, [
                  a.ancienneValeur ? el('div', null, [
                    el('p.text-xs.font-medium.text-slate-500', { text: 'Ancienne valeur' }),
                    el('pre.mt-1.overflow-x-auto.rounded.bg-slate-50.p-2.text-\\[11px\\].text-slate-700', { text: jsonLisible(a.ancienneValeur) }),
                  ]) : null,
                  a.nouvelleValeur ? el('div', null, [
                    el('p.text-xs.font-medium.text-slate-500', { text: 'Nouvelle valeur' }),
                    el('pre.mt-1.overflow-x-auto.rounded.bg-slate-50.p-2.text-\\[11px\\].text-slate-700', { text: jsonLisible(a.nouvelleValeur) }),
                  ]) : null,
                ].filter(Boolean)))
                : U.empty('Aucune valeur détaillée conservée pour cette action.', { icon: 'file' }),
            ]),
          });
        },
        actions: [K.btn('Imprimer le journal', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Journal d’audit',
              sousTitre: 'Traçabilité des actions — situation au ' + C.dateFR(AUJ),
              cartouche: [['Actions journalisées', C.num(rows.length)],
                ['Utilisateurs tracés', C.num(Object.keys(C.groupBy(rows, 'utilisateur')).length)],
                ['Tentatives infructueuses', C.num(echecs.length)],
                ['Date d’édition', C.dateFR(AUJ)]],
              contenu: P.tableau([
                { label: 'Horodatage', value: function (a) { return C.dateHeure(a.dateHeure); } },
                { label: 'Utilisateur', key: 'utilisateur' },
                { label: 'Action', key: 'action' },
                { label: 'Module', key: 'module' },
                { label: 'Entité', key: 'entite' },
                { label: 'Référence', key: 'reference' },
                { label: 'Poste', key: 'poste' },
                { label: 'Résultat', value: function (a) { return a.succes === false ? 'Échec' : 'Succès'; } },
              ], rows.slice(0, 100)),
              signatures: [{ role: 'L’Administrateur système' },
                { role: 'La Direction', nom: 'BASSONGUI Chabi Séko' }],
            });
          },
        })],
      }));

      host.appendChild(K.charts([
        {
          title: 'Actions par module',
          render: function () {
            var g = C.groupBy(rows, 'module');
            var keys = Object.keys(g);
            return G.barres(keys, [{ label: 'Actions', data: keys.map(function (k) { return g[k].length; }) }]);
          },
        },
        {
          title: 'Répartition par type d’action',
          render: function () {
            var g = C.groupBy(rows, 'action');
            var keys = Object.keys(g);
            return G.anneau(keys, keys.map(function (k) { return g[k].length; }), { legend: 'right' });
          },
        },
      ]));

      host.appendChild(K.note('La durée de conservation du journal d’audit est fixée contractuellement à <strong>cinq ans minimum</strong> pour les données financières et médicales.', { tone: 'info', icon: 'archive' }));

      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * SAUVEGARDES & RESTAURATION
   * ======================================================================== */
  global.SIGH.screen('m14-sauvegardes', {
    title: 'Sauvegardes & restauration',
    description: 'Sauvegardes quotidiennes locales, sauvegardes hebdomadaires externalisées et procédure de restauration.',
    regle: 'Politique appliquée : sauvegarde <strong>quotidienne</strong> sur disque local dédié, sauvegarde <strong>hebdomadaire externalisée</strong>, '
      + 'historique glissant de 30 jours et journalisation de chaque opération avec alerte en cas d’échec.',
    render: function (root) {
      var rnd = C.seeded(3517);
      var rows = [];
      for (var i = 0; i < 34; i++) {
        var d = C.addDays(AUJ, -i);
        var hebdo = d.getDay() === 0;
        var succes = rnd() > 0.06;
        rows.push({
          id: 'SVG' + i,
          reference: 'BK-' + C.iso(d).replace(/-/g, ''),
          date: C.iso(d), heure: hebdo ? '01:00' : '02:00',
          type: hebdo ? 'Hebdomadaire externalisée' : 'Quotidienne locale',
          support: hebdo ? 'Disque externe / cloud sécurisé' : 'Disque local dédié',
          taille: C.between(rnd, 180, 620),
          duree: C.between(rnd, 3, 18),
          succes: succes,
          message: succes ? 'Sauvegarde complète vérifiée' : 'Échec — support inaccessible',
        });
      }

      var host = el('div.space-y-4');
      var echecs = rows.filter(function (r) { return !r.succes; });

      host.appendChild(U.kpiGrid([
        { label: 'Sauvegardes conservées', value: C.num(rows.length), icon: 'database-backup', tone: 'navy', hint: 'Historique glissant 30 jours' },
        { label: 'Dernière sauvegarde', value: C.dateFR(rows[0].date), icon: 'calendar-check', tone: rows[0].succes ? 'success' : 'danger', hint: rows[0].heure },
        { label: 'Échecs constatés', value: C.num(echecs.length), icon: 'alert-triangle', tone: echecs.length ? 'danger' : 'success' },
        { label: 'Volume moyen', value: Math.round(C.sum(rows, 'taille') / rows.length) + ' Mo', icon: 'hard-drive', tone: 'neutral' },
      ]));

      if (echecs.length) {
        host.appendChild(K.note('<strong>' + echecs.length + ' sauvegarde(s) en échec</strong>. Une alerte est adressée à l’Administrateur système à chaque échec ; '
          + 'la procédure de restauration doit être testée périodiquement.', { tone: 'danger', icon: 'alert-triangle' }));
      }

      /* --------------------------------------------------------------------
       * Fichiers de sauvegarde exportables
       * --------------------------------------------------------------------
       * La demande de la Direction : une table Fichier · Date · Table · Action,
       * un bouton pour engendrer une sauvegarde, et la possibilité d'exporter
       * une sauvegarde déjà constituée. L'export descend un fichier JSON, seule
       * forme lisible sans dépendance et rechargeable telle quelle.
       * ------------------------------------------------------------------ */
      var colFichiers = S.collection('fichiersSauvegarde', { module: 'M14', entite: 'fichier de sauvegarde' });

      function collectionsBase() {
        var db = S.raw();
        return Object.keys(db).filter(function (k) { return k.charAt(0) !== '_' && Array.isArray(db[k]); });
      }

      function poidsFichier(o) {
        return o > 1024 * 1024 ? (o / 1024 / 1024).toFixed(1) + ' Mo' : Math.round(o / 1024) + ' Ko';
      }

      if (!colFichiers.all().length) {
        var rndB = C.seeded(88);
        for (var fb = 0; fb < 6; fb++) {
          var dB = C.addDays(AUJ, -fb * 7);
          colFichiers.all().push({
            id: 'BKP' + C.pad(fb + 1, 3), statut: 'actif',
            fichier: 'sigh-cnt-' + C.iso(dB).replace(/-/g, '') + '.json',
            date: C.iso(dB), heure: '01:00',
            portee: 'Base complète', tables: collectionsBase().length,
            taille: C.between(rndB, 400, 1800) * 1024,
            genereePar: 'Sauvegarde hebdomadaire automatique',
          });
        }
        S.save();
      }

      function telecharger(nom, contenu) {
        try {
          var blob = new Blob([contenu], { type: 'application/json' });
          var url = URL.createObjectURL(blob);
          var a = el('a', { href: url, download: nom });
          document.body.appendChild(a); a.click(); a.remove();
          setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
          return true;
        } catch (e) { return false; }
      }

      var tableFichiers = U.dataTable({
        title: 'Fichiers de sauvegarde disponibles',
        rows: function () { return colFichiers.active(); },
        exportName: 'fichiers-sauvegarde', pageSize: 10,
        defaultSort: 'date', defaultDir: 'desc',
        emptyMessage: 'Aucun fichier de sauvegarde.',
        columns: [
          { key: 'fichier', label: 'Fichier', render: function (r) { return el('span.font-mono.text-xs', { text: r.fichier }); } },
          {
            key: 'date', label: 'Date', nowrap: true,
            text: function (r) { return C.dateFR(r.date); },
            render: function (r) {
              return el('div', null, [
                el('p.text-sm.text-slate-700', { text: C.dateFR(r.date) }),
                el('p.text-xs.text-slate-400', { text: r.heure + ' — ' + poidsFichier(r.taille) }),
              ]);
            },
          },
          {
            key: 'tables', label: 'Tables', align: 'right',
            render: function (r) { return el('span', { text: C.num(r.tables) + ' table(s)' }); },
          },
          { key: 'portee', label: 'Portée', render: function (r) { return U.badge(r.portee, 'navy'); } },
        ],
        rowActions: function (r) {
          return [K.iconBtn('download', 'Télécharger', function () {
            var contenu = r.contenu || JSON.stringify(S.raw(), null, 2);
            var ok = telecharger(r.fichier, contenu);
            U.toast(ok ? 'Sauvegarde téléchargée.' : 'Téléchargement impossible depuis ce poste.', {
              type: ok ? 'success' : 'error', detail: r.fichier,
            });
          })];
        },
        actions: [
          K.btn('Générer une sauvegarde', {
            variant: 'primary', size: 'sm', icon: 'database-backup',
            onclick: function () {
              var cols = collectionsBase();
              var nom = 'sigh-cnt-' + C.iso(AUJ).replace(/-/g, '') + '-' + C.pad(colFichiers.all().length + 1, 2) + '.json';
              var contenu = JSON.stringify(S.raw(), null, 2);
              var res = colFichiers.insert({
                fichier: nom, date: C.iso(AUJ), heure: C.heure(new Date().toISOString()),
                portee: 'Base complète', tables: cols.length,
                taille: contenu.length, genereePar: S.currentUser(),
              });
              tableFichiers.refresh();
              U.toast('Sauvegarde ' + nom + ' générée.', {
                type: 'success',
                detail: cols.length + ' tables — ' + poidsFichier(contenu.length),
                undo: function () { res.undo(); tableFichiers.refresh(); },
              });
            },
          }),
          K.btn('Importer par module', {
            size: 'sm', icon: 'upload',
            onclick: function () { importer(); },
          }),
        ],
      });
      host.appendChild(tableFichiers);

      host.appendChild(K.note('La sauvegarde <strong>hebdomadaire est automatique</strong> ; l’utilisateur est '
        + 'invité à en télécharger une copie sur un support externe. Une sauvegarde qui reste sur le poste '
        + 'ne protège de rien.', { tone: 'info', icon: 'database-backup' }));

      host.appendChild(el('div.flex.flex-wrap.gap-2', null, [
        K.btn('Lancer une sauvegarde manuelle', {
          variant: 'primary', icon: 'database-backup',
          onclick: function () {
            U.confirm({
              title: 'Lancer une sauvegarde immédiate ?',
              message: 'Une sauvegarde complète de la base de données sera effectuée sur le disque local dédié. L’opération est journalisée.',
              confirmLabel: 'Lancer la sauvegarde',
            }).then(function (ok) {
              if (!ok) return;
              S.log('Création', 'M14', 'Sauvegarde', 'BK-MANUELLE', null, { type: 'manuelle' });
              U.toast('Sauvegarde effectuée avec succès.', { type: 'success', detail: 'Volume : 412 Mo — durée : 9 s' });
            });
          },
        }),
        K.btn('Tester une restauration', {
          icon: 'rotate-ccw',
          onclick: function () {
            U.confirm({
              title: 'Tester la procédure de restauration ?',
              message: 'La restauration sera effectuée sur l’environnement de test, sans incidence sur les données de production.',
              confirmLabel: 'Lancer le test',
            }).then(function (ok) {
              if (!ok) return;
              U.toast('Test de restauration réussi.', { type: 'success', detail: 'Intégrité des données vérifiée sur l’environnement de test.' });
            });
          },
        }),
        K.btn('Exporter le journal des sauvegardes', {
          icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Journal des sauvegardes',
              sousTitre: 'Historique glissant — situation au ' + C.dateFR(AUJ),
              cartouche: [['Sauvegardes conservées', C.num(rows.length)],
                ['Dernière sauvegarde', C.dateFR(rows[0].date) + ' à ' + rows[0].heure],
                ['Échecs', C.num(echecs.length)],
                ['Volume moyen', Math.round(C.sum(rows, 'taille') / rows.length) + ' Mo']],
              contenu: P.tableau([
                { label: 'Référence', key: 'reference' },
                { label: 'Date', value: function (r) { return C.dateFR(r.date); } },
                { label: 'Heure', key: 'heure' },
                { label: 'Type', key: 'type' },
                { label: 'Support', key: 'support' },
                { label: 'Volume', value: function (r) { return r.taille + ' Mo'; }, align: 'right' },
                { label: 'Durée', value: function (r) { return r.duree + ' s'; }, align: 'right' },
                { label: 'Résultat', value: function (r) { return r.succes ? 'Succès' : 'Échec'; } },
              ], rows),
              signatures: [{ role: 'L’Administrateur système' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
            });
          },
        }),
      ]));

      host.appendChild(U.dataTable({
        title: 'Historique des sauvegardes', rows: rows, exportName: 'sauvegardes', pageSize: 15,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'type', label: 'Type', options: ['Quotidienne locale', 'Hebdomadaire externalisée'] },
          { name: 'succes', label: 'Résultat', options: [{ value: 'ok', label: 'Succès' }, { value: 'ko', label: 'Échec' }], match: function (r, v) { return v === 'ok' ? r.succes : !r.succes; } },
        ],
        columns: [
          { key: 'reference', label: 'Référence', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'heure', label: 'Heure', nowrap: true },
          { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type, r.type.indexOf('Hebdo') === 0 ? 'navy' : 'neutral'); } },
          { key: 'support', label: 'Support' },
          { key: 'taille', label: 'Volume', align: 'right', render: function (r) { return r.taille + ' Mo'; } },
          { key: 'duree', label: 'Durée', align: 'right', render: function (r) { return r.duree + ' s'; } },
          {
            key: 'succes', label: 'Résultat',
            text: function (r) { return r.succes ? 'Succès' : 'Échec'; },
            render: function (r) { return r.succes ? U.badge('Succès', 'success') : U.badge('Échec', 'danger'); },
          },
          { key: 'message', label: 'Message' },
        ],
        rowActions: function (r) {
          if (!r.succes) return [];
          return [K.btn('Restaurer', {
            size: 'sm', icon: 'rotate-ccw',
            onclick: function () {
              U.confirm({
                title: 'Restaurer la sauvegarde du ' + C.dateFR(r.date) + ' ?',
                message: 'Cette opération remplacera les données actuelles par celles de la sauvegarde sélectionnée. '
                  + 'Elle doit être réalisée sous le contrôle de l’Administrateur système et est journalisée.',
                confirmLabel: 'Restaurer', danger: true, requireMotif: true,
              }).then(function (res) {
                if (!res) return;
                S.log('Restauration', 'M14', 'Sauvegarde', r.reference, null, { motif: res.motif });
                U.toast('Restauration simulée avec succès.', {
                  type: 'success',
                  detail: 'Dans le prototype, aucune donnée n’est effectivement remplacée.',
                });
              });
            },
          })];
        },
      }));
      root.appendChild(host);
      return null;

      /* Import par module : reprendre une base entière ou seulement quelques
         tables. Remplacer sans prévenir serait irréversible — on le dit. */
      function importer() {
        var input = el('input.input', { type: 'file', accept: '.json,application/json' });
        var choix = U.form([
          {
            name: 'modules', label: 'Tables à importer', type: 'multiselect', col: 'full',
            options: collectionsBase(),
            help: 'Laisser vide pour importer la base entière. Sélectionner pour n’en reprendre qu’une partie.',
          },
        ], {});
        var mi = U.modal({
          title: 'Importer une sauvegarde', size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('L’import <strong>remplace</strong> les tables reprises. Générer une sauvegarde '
              + 'avant d’importer reste la précaution élémentaire.', { tone: 'warning', icon: 'alert-triangle' }),
            el('div', null, [el('label.label', { text: 'Fichier de sauvegarde (JSON)' }), input]),
            choix,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { mi.close(); } }),
            K.btn('Importer', {
              variant: 'danger', icon: 'upload',
              onclick: function () {
                var file = input.files && input.files[0];
                if (!file) { U.toast('Choisir un fichier de sauvegarde.', { type: 'warning' }); return; }
                var v = choix.collect() || {};
                var lecteur = new FileReader();
                lecteur.onload = function () {
                  var data;
                  try { data = JSON.parse(lecteur.result); }
                  catch (e) { U.toast('Fichier illisible : ' + e.message, { type: 'error' }); return; }
                  var db = S.raw();
                  var cibles = (v.modules && v.modules.length) ? v.modules : Object.keys(data);
                  var reprises = 0;
                  cibles.forEach(function (k) {
                    if (k.charAt(0) === '_' || !Array.isArray(data[k])) return;
                    db[k] = data[k];
                    reprises++;
                  });
                  S.save();
                  S.log('Import de sauvegarde', 'M14', 'Base', file.name, null, { tables: reprises });
                  mi.close();
                  U.toast(reprises + ' table(s) importée(s).', {
                    type: 'success', detail: 'Rechargement en cours…',
                  });
                  setTimeout(function () { global.location.reload(); }, 1200);
                };
                lecteur.readAsText(file);
              },
            }),
          ],
        });
      }

      return null;
    },
  });

  /* ==========================================================================
   * PRESCRIPTEURS ET EXÉCUTANTS DE SOINS
   * --------------------------------------------------------------------------
   * La Direction a demandé expressément que l'administrateur puisse ajouter et
   * modifier les soignants et les prescripteurs. C'est cet écran.
   *
   * LES FICHES SONT DÉRIVÉES DU PERSONNEL, jamais ressaisies : une seconde
   * liste de noms divergerait du dossier RH au premier recrutement — c'est la
   * même règle que pour l'assurance du personnel. La fiche ne porte donc que
   * ce que le dossier RH ne dit pas : qui prescrit, qui exécute, où.
   *
   * DEUX DROITS DISTINCTS SUR UNE MÊME FICHE, parce que la sage-femme les
   * cumule — elle prescrit ET elle exécute. Deux listes séparées auraient
   * obligé à l'inscrire deux fois, avec le risque de n'en corriger qu'une.
   * ======================================================================== */
  global.SIGH.screen('m14-soignants', {
    title: 'Prescripteurs & exécutants de soins',
    description: 'Qui prescrit, qui exécute les soins, et dans quels secteurs.',
    regle: 'Seuls <strong>médecins et sages-femmes</strong> prescrivent ; seuls <strong>infirmiers et '
      + 'sages-femmes</strong> exécutent les soins. La sage-femme cumule les deux. Le contrôle est appliqué '
      + 'par le <strong>moteur de parcours</strong> et non par l’écran : une prescription venue d’ailleurs '
      + 'serait refusée de la même façon.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col5() {
        return S.collection('soignants', { module: 'M14', entite: 'soignant', prefix: 'SOI' });
      }
      function qualite(code) {
        return (D.QUALITES_SOIGNANT || []).filter(function (q) { return q.code === code; })[0] || null;
      }

      function champs() {
        return [
          { name: 'personnelId', label: 'Agent', type: 'select', required: true,
            options: S.collection('personnel').active().map(function (a) {
              return { value: a.id, label: a.nomComplet + ' — ' + (a.poste || a.fonction) };
            }),
            hint: 'La fiche est dérivée du dossier RH : le nom ne se ressaisit pas ici.' },
          { name: 'qualite', label: 'Qualité', type: 'select', required: true,
            options: (D.QUALITES_SOIGNANT || []).map(function (q) {
              return { value: q.code, label: q.label, detail: q.note };
            }) },
          { name: 'prescrit', label: 'Habilité à prescrire', type: 'checkbox' },
          { name: 'execute', label: 'Habilité à exécuter les soins', type: 'checkbox' },
          { name: 'supervise', label: 'Supervise les soins sans les exécuter', type: 'checkbox',
            hint: 'C’est le rôle de l’Infirmier Général, tel que sa description de poste le définit.' },
          { name: 'secteurs', label: 'Secteurs d’exercice', type: 'multiselect', required: true,
            options: (D.SECTEURS_SOINS || []).map(function (x) { return { value: x.code, label: x.label }; }) },
        ];
      }

      function afficher() {
        var rows = col5().active();
        var presc = rows.filter(function (x) { return x.prescrit; });
        var exec = rows.filter(function (x) { return x.execute; });
        var deux = rows.filter(function (x) { return x.prescrit && x.execute; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Soignants', value: C.num(rows.length), icon: 'users-round', tone: 'navy' },
          { label: 'Prescripteurs', value: C.num(presc.length), icon: 'clipboard-plus', tone: 'info',
            hint: 'médecins et sages-femmes' },
          { label: 'Exécutants de soins', value: C.num(exec.length), icon: 'syringe', tone: 'success',
            hint: 'infirmiers et sages-femmes' },
          { label: 'Cumulent les deux', value: C.num(deux.length), icon: 'shuffle', tone: 'neutral',
            hint: 'les sages-femmes' },
        ]));

        vue.appendChild(K.note('Les effectifs énoncés par la Direction — <strong>3 médecins, 3 sages-femmes, '
          + '7 infirmiers</strong> — se retrouvent exactement dès lors qu’on met à part les deux agents qui ne '
          + 'sont ni prescripteurs ni exécutants : l’<strong>Infirmier — Surveillant Général</strong>, qui '
          + 'supervise les soins (c’est l’IG de la description de poste du 26/10/2023), et '
          + 'l’<strong>Échographiste</strong>, qui réalise des examens sans prescrire.',
        { tone: 'info', icon: 'users' }));

        vue.appendChild(U.tabs([
          { id: 'tous', label: 'Tous', badge: rows.length, render: function () { return tableau(rows); } },
          { id: 'prescripteurs', label: 'Prescripteurs', badge: presc.length, render: function () { return tableau(presc); } },
          { id: 'executants', label: 'Exécutants', badge: exec.length, render: function () { return tableau(exec); } },
        ]));
        U.icons(vue);
      }

      function tableau(rows) {
        return U.dataTable({
          rows: C.sortBy(rows, 'nomComplet'),
          empty: 'Aucun soignant enregistré.',
          actions: [K.creer(col5(), champs(), {
            module: 'M14', label: 'Nouveau soignant', titre: 'Habiliter un soignant',
            entite: 'Soignant', apres: afficher,
            transform: function (v) {
              var a = S.collection('personnel').active().filter(function (x) {
                return x.id === v.personnelId;
              })[0];
              return Object.assign({}, v, {
                nomComplet: a ? a.nomComplet : '—', poste: a ? a.poste : '',
                source: 'Habilitation saisie par l’administrateur',
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'nomComplet', label: 'Agent' },
            { key: 'poste', label: 'Poste' },
            { key: 'qualite', label: 'Qualité',
              render: function (r) { var q = qualite(r.qualite); return q ? q.label : r.qualite; } },
            { key: 'prescrit', label: 'Prescrit', align: 'center',
              render: function (r) { return r.prescrit ? U.badge('Oui', 'success') : U.badge('Non', 'neutral'); } },
            { key: 'execute', label: 'Exécute', align: 'center',
              render: function (r) { return r.execute ? U.badge('Oui', 'success') : U.badge('Non', 'neutral'); } },
            { key: 'secteurs', label: 'Secteurs',
              render: function (r) {
                return (r.secteurs || []).map(function (c) {
                  var x = (D.SECTEURS_SOINS || []).filter(function (y) { return y.code === c; })[0];
                  return x ? x.label : c;
                }).join(' · ') || '—';
              } },
          ],
          rowActions: K.actionsLigne(col5(), champs(), {
            module: 'M14', refresh: afficher,
            titre: function (r) { return r.nomComplet; },
            detail: function (r) {
              var q = qualite(r.qualite);
              return el('div.space-y-4', null,
                K.grid([
                  ['Agent', r.nomComplet], ['Poste', r.poste || '—'],
                  ['Qualité', q ? q.label : r.qualite],
                  ['Prescrit', r.prescrit ? 'Oui' : 'Non'],
                  ['Exécute les soins', r.execute ? 'Oui' : 'Non'],
                  ['Supervise', r.supervise ? 'Oui' : 'Non'],
                  ['Réalise l’imagerie', r.realiseImagerie ? 'Oui' : 'Non'],
                  ['Origine de la fiche', r.source || '—'],
                ]),
                q ? K.note(q.note, { tone: 'info', icon: q.icone }) : null);
            },
          }),
        });
      }
    },
  });

})(window);